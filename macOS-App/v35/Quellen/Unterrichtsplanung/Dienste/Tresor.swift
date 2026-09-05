// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Ein Fehler des Tresors mit einem Satz für den Nutzer. Die Art trennt
/// „falscher Schlüssel“ (ein Rückweg) von „beschädigt“ (sieht wie Datenverlust
/// aus) — beide dürfen nie dieselbe Meldung ergeben.
struct Tresorfehler: LocalizedError, Sendable {
    enum Art: Sendable {
        case beschaedigt
        case falscherSchluessel
        /// Die Freigabe durch Touch ID oder das Anmeldepasswort blieb aus.
        case abgebrochen
        case keineWicklung
        /// Prüfstand, oder es gibt keine Secure Enclave.
        case keineEnklave
        /// Ein Behälter aus einer neueren Fassung — nicht anfassen, nicht beiseitelegen.
        case neuereFassung
    }
    let art: Art
    let text: String
    var errorDescription: String? { text }
}

/// Ein JSON-Wert aus dem Kopf eines Behälters. Über ihn werden Wicklungen
/// weitergetragen, die diese Fassung nicht kennt — Feld für Feld.
indirect enum JSONWert: Sendable, Equatable {
    case text(String)
    case zahl(Double)
    case wahr(Bool)
    case leer
    case liste([JSONWert])
    case objekt([String: JSONWert])

    init?(_ roh: Any) {
        switch roh {
        case let s as String: self = .text(s)
        case let n as NSNumber:
            // `JSONSerialization` liefert Wahrheitswerte und Zahlen beide als
            // `NSNumber`; nur `objCType` "c" ist der Wahrheitswert.
            if String(cString: n.objCType) == "c" { self = .wahr(n.boolValue) }
            else { self = .zahl(n.doubleValue) }
        case is NSNull: self = .leer
        case let l as [Any]:
            var werte: [JSONWert] = []
            for eintrag in l { guard let w = JSONWert(eintrag) else { return nil }; werte.append(w) }
            self = .liste(werte)
        case let o as [String: Any]:
            var werte: [String: JSONWert] = [:]
            for (k, v) in o { guard let w = JSONWert(v) else { return nil }; werte[k] = w }
            self = .objekt(werte)
        default: return nil
        }
    }

    var roh: Any {
        switch self {
        case .text(let s): s
        case .zahl(let z): z == z.rounded() && abs(z) < 1e15 ? Int(z) as Any : z as Any
        case .wahr(let b): b
        case .leer: NSNull()
        case .liste(let l): l.map(\.roh)
        case .objekt(let o): o.mapValues(\.roh)
        }
    }

    var text: String? { if case .text(let s) = self { return s }; return nil }
    var ganzzahl: Int? { if case .zahl(let z) = self, z == z.rounded() { return Int(z) }; return nil }
}

/// Der Datenschlüssel, versiegelt unter einem Wicklungsschlüssel. `art` sagt,
/// woher der kommt; die Felder sind je Art verschieden und werden für
/// unbekannte Arten unverändert mitgeführt.
struct Wicklung: Sendable, Equatable {
    static let enklave = "enklave"
    static let passphrase = "passphrase"
    static let wiederherstellung = "wiederherstellung"
    /// Die Arten, die diese Fassung selbst anlegt — und nie von außen annimmt.
    static let eigeneArten: Set<String> = [enklave, passphrase, wiederherstellung]

    let art: String
    var felder: [String: JSONWert]

    func text(_ name: String) -> String? { felder[name]?.text }
    func daten(_ name: String) -> Data? { felder[name]?.text.flatMap { Data(base64Encoded: $0) } }
    func zahl(_ name: String) -> Int? { felder[name]?.ganzzahl }

    var beschriftung: String {
        switch art {
        case Wicklung.enklave: "Dieser Mac (Secure Enclave, Touch ID oder Anmeldepasswort)"
        case Wicklung.passphrase: "Passphrase"
        case Wicklung.wiederherstellung: "Wiederherstellungsschlüssel"
        default: "Unbekannte Art „\(art)“ — wird unverändert weitergetragen"
        }
    }

    /// Hängt am Gerät und verlässt die Kopie nie.
    var istGeraetegebunden: Bool { art == Wicklung.enklave }
}

/// Der gelesene Kopf eines Behälters samt Nutzlast — noch verschlossen.
struct Behaelterkopf: Sendable {
    let version: Int
    let inhalt: String
    let kennung: Data
    let nonce: Data
    let wicklungen: [Wicklung]
    /// Chiffrat samt 16 Byte Beglaubigung, ohne Nonce.
    let daten: Data

    func wicklung(_ art: String) -> Wicklung? { wicklungen.first { $0.art == art } }
    var kennungHex: String { kennung.hex }
}

/// Der Umschlag: ein zufälliger Datenschlüssel (256 Bit) versiegelt jede Datei
/// mit AES-256-GCM und liegt mehrfach *gewickelt* im Kopf derselben Datei. Wer
/// eine Wicklung öffnen kann, hat den Datenschlüssel; die Daten werden nie
/// umgeschlüsselt. Die Wicklungsliste ist offen und je Ziel anders bestückt —
/// die Enklaven-Wicklung verlässt den Mac nie.
///
/// Der Datenschlüssel liegt nach dem Öffnen einmal je Sitzung im Speicher;
/// sonst fragte jede Sicherung nach. Ohne fremde Bibliothek: CryptoKit,
/// CommonCrypto (PBKDF2), LocalAuthentication und Security sind System.
final class Tresor: @unchecked Sendable {

    // ── Festwerte — die Ansicht führt dieselben (masse_pruefen.py) ────────
    static let typ = "unterrichtsplanung-tresor"
    static let version = 1
    static let verfahren = "AES-256-GCM"
    static let kdfPassphrase = "PBKDF2-HMAC-SHA256"
    static let kdfWiederherstellung = "HKDF-SHA256"
    /// Vorschlag bis zur Messung auf dem iPad; steht im Kopf jeder Datei.
    static let rundenStandard = 1_000_000
    /// Darunter ist ein Kopf untergeschoben, darüber ist er eine Bremse: Ein
    /// Fremder könnte mit 100 Mio. Runden die App zehn Sekunden anhalten.
    static let rundenMindestens = 100_000
    static let rundenHoechstens = 10_000_000
    static let passphraseMindestlaenge = 12
    static let kennungLaenge = 16
    /// Salt — der Fachbegriff bleibt unübersetzt. Im Behälter heißt das Feld
    /// `salz`; der Name ist Teil des Dateiformats, damit jede versiegelte Datei und
    /// die Ansicht im Netz weiterlesen.
    static let saltLaenge = 16
    static let wiederherstellungLaenge = 20
    /// Base32 ohne 0, 1, 8 und 9 — nichts, was sich beim Abtippen verwechselt.
    static let wiederherstellungAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    static let wiederherstellungZeichen = Array(wiederherstellungAlphabet)

    enum Inhalt: String, Sendable { case planung, status, rohdaten }

    /// Wohin der Behälter geht — danach richtet sich, welche Wicklungen er trägt.
    enum Ziel: Sendable {
        /// Alle Wicklungen.
        case ablage
        /// Alles außer dem, was am Gerät hängt.
        case kopie
        /// Nur Passphrase und Wiederherstellung — was in zehn Jahren noch aufgeht.
        case export
    }

    let schluessel: SymmetricKey
    let kennung: Data
    private let sperre = NSLock()
    private var eigeneWicklungen: [Wicklung]

    var wicklungen: [Wicklung] { sperre.withLock { eigeneWicklungen } }
    var kennungHex: String { kennung.hex }

    init(schluessel: SymmetricKey, kennung: Data, wicklungen: [Wicklung] = []) {
        self.schluessel = schluessel
        self.kennung = kennung
        eigeneWicklungen = wicklungen
    }

    static func neu() -> Tresor {
        Tresor(schluessel: SymmetricKey(size: .bits256), kennung: Data.zufall(kennungLaenge))
    }

    /// Jeder unterstützte Mac hat eine Secure Enclave — nur der Prüfstand
    /// verzichtet: Kein `swift test` darf je in einen Touch-ID-Dialog laufen.
    /// `Ablage.enklaveImPruefstand` hebt das für den Prüfstand am Fenster auf.
    static var enklaveVerfuegbar: Bool {
        (!Ablage.istPruefstand || Ablage.enklaveImPruefstand) && SecureEnclave.isAvailable
    }

    func hat(_ art: String) -> Bool { wicklungen.contains { $0.art == art } }

    // ── Wicklungen anlegen ────────────────────────────────────────────────

    private func ersetzen(_ neu: Wicklung) {
        sperre.withLock {
            eigeneWicklungen.removeAll { $0.art == neu.art }
            eigeneWicklungen.append(neu)
        }
    }

    func entfernen(art: String) {
        sperre.withLock { eigeneWicklungen.removeAll { $0.art == art } }
    }

    /// Übernimmt aus einem fremden Kopf, was hier fehlt und was diese Fassung
    /// nicht selbst anlegt — etwa eine Wicklung der Ansicht. Die eigenen Arten
    /// kommen nie von außen. Aufzurufen nur, wenn der fremde Behälter unter dem
    /// eigenen Schlüssel aufging: Wer ihn versiegeln konnte, kannte den Schlüssel.
    @discardableResult
    func fremdeWicklungenUebernehmen(aus kopf: Behaelterkopf) -> Int {
        guard kopf.kennung == kennung else { return 0 }
        return sperre.withLock {
            var neu = 0
            for w in kopf.wicklungen
            where !Wicklung.eigeneArten.contains(w.art)
                && !eigeneWicklungen.contains(where: { $0.art == w.art }) {
                eigeneWicklungen.append(w)
                neu += 1
            }
            return neu
        }
    }

    /// PBKDF2 läuft nur hier und beim Ändern der Passphrase — nie beim Sichern,
    /// nie beim Beenden.
    func passphraseSetzen(_ passphrase: String, runden: Int = rundenStandard) throws {
        guard passphrase.count >= Tresor.passphraseMindestlaenge else {
            throw Tresorfehler(art: .falscherSchluessel,
                               text: "Die Passphrase braucht mindestens "
                                     + "\(Tresor.passphraseMindestlaenge) Zeichen.")
        }
        let salt = Data.zufall(Tresor.saltLaenge)
        let kek = try Tresor.pbkdf2(passphrase, salt: salt, runden: runden)
        let (nonce, umschlag) = try wickeln(mit: kek, art: Wicklung.passphrase)
        ersetzen(Wicklung(art: Wicklung.passphrase, felder: [
            "kdf": .text(Tresor.kdfPassphrase),
            "runden": .zahl(Double(runden)),
            "salz": .text(salt.base64EncodedString()),
            "nonce": .text(nonce.base64EncodedString()),
            "umschlag": .text(umschlag.base64EncodedString()),
        ]))
    }

    /// Erzeugt einen neuen Wiederherstellungsschlüssel, wickelt damit und gibt
    /// ihn **einmal** zurück — angezeigt, gedruckt, nie gespeichert.
    func wiederherstellungAnlegen() throws -> String {
        let roh = Data.zufall(Tresor.wiederherstellungLaenge)
        let salt = Data.zufall(Tresor.saltLaenge)
        let kek = Tresor.hkdfWiederherstellung(roh, salt: salt)
        let (nonce, umschlag) = try wickeln(mit: kek, art: Wicklung.wiederherstellung)
        ersetzen(Wicklung(art: Wicklung.wiederherstellung, felder: [
            "kdf": .text(Tresor.kdfWiederherstellung),
            "salz": .text(salt.base64EncodedString()),
            "nonce": .text(nonce.base64EncodedString()),
            "umschlag": .text(umschlag.base64EncodedString()),
        ]))
        return Tresor.wiederherstellungText(roh)
    }

    /// Ein P256-Schlüssel in der Secure Enclave, gebunden an Touch ID **oder**
    /// das Anmeldepasswort. Gewickelt wird über den öffentlichen Teil — der ist
    /// ohne Freigabe zu haben (nachgemessen); Anlegen und Neuwickeln
    /// kosten keine Nachfrage. `auchImPruefstand` nur für den Prüfstein ohne Dialog.
    func enklaveAnlegen(auchImPruefstand: Bool = false) throws {
        guard Tresor.enklaveVerfuegbar || (auchImPruefstand && SecureEnclave.isAvailable) else {
            throw Tresorfehler(art: .keineEnklave,
                               text: "Die Secure Enclave steht hier nicht zur Verfügung.")
        }
        var fehler: Unmanaged<CFError>?
        guard let schutz = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet, .or, .devicePasscode], &fehler)
        else {
            throw Tresorfehler(art: .keineEnklave,
                               text: "Die Zugriffsbedingung für die Secure Enclave ließ sich "
                                     + "nicht anlegen.")
        }
        let geraet = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: schutz)
        let fluechtig = P256.KeyAgreement.PrivateKey()
        let salt = Data.zufall(Tresor.saltLaenge)
        let kek = try fluechtig.sharedSecretFromKeyAgreement(with: geraet.publicKey)
            .hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                     sharedInfo: fluechtig.publicKey.rawRepresentation,
                                     outputByteCount: 32)
        let (nonce, umschlag) = try wickeln(mit: kek, art: Wicklung.enklave)
        ersetzen(Wicklung(art: Wicklung.enklave, felder: [
            "geraet": .text(geraet.dataRepresentation.base64EncodedString()),
            "fluechtig": .text(fluechtig.publicKey.rawRepresentation.base64EncodedString()),
            "salz": .text(salt.base64EncodedString()),
            "nonce": .text(nonce.base64EncodedString()),
            "umschlag": .text(umschlag.base64EncodedString()),
        ]))
    }

    private func wickeln(mit kek: SymmetricKey, art: String) throws -> (nonce: Data, umschlag: Data) {
        let nonce = AES.GCM.Nonce()
        let versiegelt = try schluessel.withUnsafeBytes { roh in
            try AES.GCM.seal(Data(roh), using: kek, nonce: nonce,
                             authenticating: Tresor.zusatz(art: art, kennung: kennung))
        }
        return (Data(nonce), versiegelt.ciphertext + versiegelt.tag)
    }

    // ── Versiegeln und öffnen ─────────────────────────────────────────────

    /// Die Nutzlast ist genau das, was die Leser bisher lasen — die Bytes aus
    /// `Planungsdatei.schreiben` oder `Statusdatei.schreiben`. Die Hülle ändert
    /// an den Zwillingslesern nichts.
    func versiegeln(_ klartext: Data, inhalt: Inhalt, ziel: Ziel) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let versiegelt = try AES.GCM.seal(
            klartext, using: schluessel, nonce: nonce,
            authenticating: Tresor.zusatz(inhalt: inhalt.rawValue, kennung: kennung))
        let getragen: [Wicklung] = switch ziel {
        case .ablage: wicklungen
        case .kopie: wicklungen.filter { !$0.istGeraetegebunden }
        case .export: wicklungen.filter {
            $0.art == Wicklung.passphrase || $0.art == Wicklung.wiederherstellung }
        }
        return try Tresor.behaelterSchreiben(
            inhalt: inhalt, kennung: kennung, nonce: Data(nonce),
            wicklungen: getragen, daten: versiegelt.ciphertext + versiegelt.tag)
    }

    func oeffnen(_ roh: Data) throws -> Data {
        try oeffnen(kopf: Tresor.kopfLesen(roh))
    }

    func oeffnen(kopf: Behaelterkopf) throws -> Data {
        guard kopf.kennung == kennung else {
            throw Tresorfehler(art: .falscherSchluessel,
                               text: "Die Datei ist unter einem anderen Schlüssel versiegelt.")
        }
        return try Tresor.entsiegeln(kopf, mit: schluessel)
    }

    func passt(zu kopf: Behaelterkopf) -> Bool { kopf.kennung == kennung }

    /// Belegt, nicht abgefragt: Nur wer die Passphrase kennt, darf sie ersetzen
    /// oder den Schlüssel erneuern.
    func passphraseStimmt(_ passphrase: String) -> Bool {
        guard let w = wicklungen.first(where: { $0.art == Wicklung.passphrase }),
              let runden = w.zahl("runden"), let salt = w.daten("salz"),
              let kek = try? Tresor.pbkdf2(passphrase, salt: salt, runden: runden),
              let probe = try? Tresor.entwickeln(w, kopf: Behaelterkopf(
                  version: Tresor.version, inhalt: Inhalt.planung.rawValue, kennung: kennung,
                  nonce: Data(count: 12), wicklungen: [], daten: Data(count: 16)),
                  mit: kek, fehltext: "")
        else { return false }
        return probe.schluessel == schluessel
    }

    // ── Entwickeln: aus einem Kopf den Datenschlüssel holen ───────────────

    static func oeffnen(kopf: Behaelterkopf, passphrase: String) throws -> Tresor {
        guard let w = kopf.wicklung(Wicklung.passphrase) else {
            throw Tresorfehler(art: .keineWicklung,
                               text: "Die Datei trägt keine Passphrase-Wicklung.")
        }
        guard w.text("kdf") == kdfPassphrase,
              let runden = w.zahl("runden"), runden >= rundenMindestens, runden <= rundenHoechstens,
              let salt = w.daten("salz"), salt.count >= 8
        else { throw Tresorfehler(art: .beschaedigt, text: "Die Passphrase-Wicklung ist beschädigt.") }
        let kek = try pbkdf2(passphrase, salt: salt, runden: runden)
        return try entwickeln(w, kopf: kopf, mit: kek, fehltext: "Die Passphrase passt nicht.")
    }

    static func oeffnen(kopf: Behaelterkopf, wiederherstellung text: String) throws -> Tresor {
        guard let w = kopf.wicklung(Wicklung.wiederherstellung) else {
            throw Tresorfehler(art: .keineWicklung,
                               text: "Die Datei trägt keine Wiederherstellungswicklung.")
        }
        guard w.text("kdf") == kdfWiederherstellung, let salt = w.daten("salz"), salt.count >= 8
        else { throw Tresorfehler(art: .beschaedigt, text: "Die Wiederherstellungswicklung ist beschädigt.") }
        guard let roh = wiederherstellungRoh(text) else {
            throw Tresorfehler(art: .falscherSchluessel,
                               text: "Der Wiederherstellungsschlüssel hat nicht die erwartete Form "
                                     + "(8 Gruppen zu 4 Zeichen).")
        }
        return try entwickeln(w, kopf: kopf, mit: hkdfWiederherstellung(roh, salt: salt),
                              fehltext: "Der Wiederherstellungsschlüssel passt nicht.")
    }

    /// Hier, und nur hier, fragt Touch ID. Blockiert bis zur Antwort — nie auf
    /// dem Hauptstrang aufrufen. `interactionNotAllowed` im Kontext macht daraus
    /// einen Prüflauf ohne Dialog (LAError −1004, nachgemessen).
    static func oeffnen(kopf: Behaelterkopf, enklave kontext: LAContext) throws -> Tresor {
        guard let w = kopf.wicklung(Wicklung.enklave) else {
            throw Tresorfehler(art: .keineWicklung,
                               text: "Die Datei trägt keine Wicklung für diesen Mac.")
        }
        guard let blob = w.daten("geraet"), let fluechtigRoh = w.daten("fluechtig"),
              let salt = w.daten("salz")
        else { throw Tresorfehler(art: .beschaedigt, text: "Die Wicklung für diesen Mac ist beschädigt.") }
        let geraet: SecureEnclave.P256.KeyAgreement.PrivateKey
        let fluechtig: P256.KeyAgreement.PublicKey
        do {
            geraet = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: blob, authenticationContext: kontext)
            fluechtig = try P256.KeyAgreement.PublicKey(rawRepresentation: fluechtigRoh)
        } catch {
            throw Tresorfehler(art: .falscherSchluessel,
                               text: "Der Schlüssel dieses Macs ließ sich nicht laden — die "
                                     + "Wicklung gehört zu einem anderen Gerät.")
        }
        let kek: SymmetricKey
        do {
            kek = try geraet.sharedSecretFromKeyAgreement(with: fluechtig)
                .hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                         sharedInfo: fluechtigRoh, outputByteCount: 32)
        } catch {
            // Was aus LocalAuthentication kommt, ist eine ausgebliebene Freigabe;
            // alles andere ein Schlüssel, der nicht mehr passt (etwa nach neu
            // angelernten Fingerabdrücken — dafür steht das Anmeldepasswort als Oder-Zweig).
            let ns = error as NSError
            if ns.domain == LAErrorDomain || ns.domain == "com.apple.LocalAuthentication" {
                throw Tresorfehler(art: .abgebrochen, text: "Die Freigabe wurde nicht erteilt.")
            }
            throw Tresorfehler(art: .falscherSchluessel,
                               text: "Die Secure Enclave hat die Wicklung nicht geöffnet: "
                                     + error.localizedDescription)
        }
        return try entwickeln(w, kopf: kopf, mit: kek,
                              fehltext: "Die Wicklung für diesen Mac passt nicht.")
    }

    /// Die Beglaubigung der Wicklung schlägt fehl, bevor irgendwer die Daten
    /// anrührt: „falsch“ ist belegt, nicht geraten.
    private static func entwickeln(_ w: Wicklung, kopf: Behaelterkopf, mit kek: SymmetricKey,
                                   fehltext: String) throws -> Tresor {
        guard let nonce = w.daten("nonce"), let umschlag = w.daten("umschlag"),
              nonce.count == 12, umschlag.count == 32 + 16
        else { throw Tresorfehler(art: .beschaedigt, text: "Die Wicklung ist beschädigt.") }
        let roh: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce),
                                            ciphertext: umschlag.prefix(32),
                                            tag: umschlag.suffix(16))
            roh = try AES.GCM.open(box, using: kek,
                                   authenticating: zusatz(art: w.art, kennung: kopf.kennung))
        } catch {
            throw Tresorfehler(art: .falscherSchluessel, text: fehltext)
        }
        return Tresor(schluessel: SymmetricKey(data: roh), kennung: kopf.kennung,
                      wicklungen: kopf.wicklungen)
    }

    // ── Der Behälter auf der Platte ───────────────────────────────────────

    /// So beginnt, was diese App und die Ansicht schreiben — `typ` vorne, damit
    /// `head -c 40` es zeigt.
    private static let kopfvorsatz = Data("{\"typ\":\"\(typ)\"".utf8)

    /// Erkannt wird am Feld `typ`, nicht an einer Zeichenfolge irgendwo in der
    /// Datei — eine Planung, deren Titel den Typnamen trägt, ist Klartext.
    static func istBehaelter(_ roh: Data) -> Bool {
        if roh.starts(with: kopfvorsatz) { return true }
        guard let erstes = roh.prefix(64).first(where: { $0 != 0x20 && $0 != 0x0a && $0 != 0x0d && $0 != 0x09 }),
              erstes == UInt8(ascii: "{"),
              roh.range(of: Data("\"\(typ)\"".utf8)) != nil,
              let objekt = (try? JSONSerialization.jsonObject(with: roh)) as? [String: Any]
        else { return false }
        return objekt["typ"] as? String == typ
    }

    static func kopfLesen(_ roh: Data) throws -> Behaelterkopf {
        let beschaedigt = Tresorfehler(art: .beschaedigt,
                                       text: "Der verschlüsselte Behälter ist beschädigt.")
        guard let objekt = (try? JSONSerialization.jsonObject(with: roh)) as? [String: Any],
              objekt["typ"] as? String == typ
        else { throw beschaedigt }
        guard let version = (objekt["version"] as? NSNumber)?.intValue, version >= 1 else { throw beschaedigt }
        guard version <= Tresor.version else {
            throw Tresorfehler(art: .neuereFassung,
                               text: "Der Behälter stammt aus einer neueren Fassung (\(version)) — "
                                     + "bitte die App aktualisieren; die Datei bleibt unangetastet.")
        }
        guard let inhalt = objekt["inhalt"] as? String,
              let kennungHex = objekt["schluesselkennung"] as? String,
              let kennung = Data(hex: kennungHex), kennung.count == kennungLaenge,
              objekt["verfahren"] as? String == verfahren,
              let nonce = (objekt["nonce"] as? String).flatMap({ Data(base64Encoded: $0) }),
              nonce.count == 12,
              let daten = (objekt["daten"] as? String).flatMap({ Data(base64Encoded: $0) }),
              daten.count >= 16,
              let rohWicklungen = objekt["wicklungen"] as? [[String: Any]]
        else { throw beschaedigt }
        var wicklungen: [Wicklung] = []
        for eintrag in rohWicklungen {
            guard let art = eintrag["art"] as? String, !art.isEmpty else { throw beschaedigt }
            var felder: [String: JSONWert] = [:]
            for (name, wert) in eintrag where name != "art" {
                guard let w = JSONWert(wert) else { throw beschaedigt }
                felder[name] = w
            }
            wicklungen.append(Wicklung(art: art, felder: felder))
        }
        return Behaelterkopf(version: version, inhalt: inhalt, kennung: kennung, nonce: nonce,
                             wicklungen: wicklungen, daten: daten)
    }

    static func entsiegeln(_ kopf: Behaelterkopf, mit schluessel: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: kopf.nonce),
                                            ciphertext: kopf.daten.dropLast(16),
                                            tag: kopf.daten.suffix(16))
            return try AES.GCM.open(box, using: schluessel,
                                    authenticating: zusatz(inhalt: kopf.inhalt, kennung: kopf.kennung))
        } catch {
            throw Tresorfehler(art: .beschaedigt,
                               text: "Der Inhalt des Behälters ließ sich nicht entsiegeln — "
                                     + "die Datei ist beschädigt oder verändert.")
        }
    }

    /// Von Hand zusammengesetzt, damit `typ` vorne steht; nur die Wicklungen
    /// gehen durch `JSONSerialization`, weil sie Unbekanntes tragen können.
    static func behaelterSchreiben(inhalt: Inhalt, kennung: Data, nonce: Data,
                                   wicklungen: [Wicklung], daten: Data) throws -> Data {
        let liste = wicklungen.map { w -> [String: Any] in
            var o = w.felder.mapValues(\.roh)
            o["art"] = w.art
            return o
        }
        let wicklungenJSON = try JSONSerialization.data(
            withJSONObject: liste, options: [.sortedKeys, .withoutEscapingSlashes])
        var text = "{\"typ\":\"\(typ)\",\"version\":\(version),\"inhalt\":\"\(inhalt.rawValue)\","
        text += "\"schluesselkennung\":\"\(kennung.hex)\",\"verfahren\":\"\(verfahren)\","
        text += "\"nonce\":\"\(nonce.base64EncodedString())\",\"wicklungen\":"
        var aus = Data(text.utf8)
        aus.append(wicklungenJSON)
        aus.append(Data(",\"daten\":\"".utf8))
        aus.append(Data(daten.base64EncodedString().utf8))
        aus.append(Data("\"}\n".utf8))
        return aus
    }

    // ── Zusatzdaten (AAD) ─────────────────────────────────────────────────
    // Kurze feste Zeichenketten, kein kanonisch serialisierter Kopf: Zwei
    // JSON-Schreiber, die Byte für Byte übereinstimmen müssten, wären die
    // Zwillingsfalle, die dieses Projekt schon dreimal getroffen hat.

    static func zusatz(inhalt: String, kennung: Data) -> Data {
        Data("\(typ)|\(version)|\(inhalt)|\(kennung.hex)".utf8)
    }

    static func zusatz(art: String, kennung: Data) -> Data {
        Data("\(art)|\(kennung.hex)".utf8)
    }

    // ── Schlüsselableitung ────────────────────────────────────────────────

    /// NFC-normalisiert und UTF-8 — sonst ist ein „ä“ hier ein Zeichen und
    /// im Browser zwei, und die Passphrase „geht nicht“.
    static func pbkdf2(_ passphrase: String, salt: Data, runden: Int) throws -> SymmetricKey {
        let pass = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        guard !pass.isEmpty else {
            throw Tresorfehler(art: .falscherSchluessel, text: "Die Passphrase ist leer.")
        }
        var abgeleitet = [UInt8](repeating: 0, count: 32)
        let status = pass.withUnsafeBufferPointer { passZeiger in
            salt.withUnsafeBytes { saltZeiger in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passZeiger.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                    pass.count,
                    saltZeiger.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(runden),
                    &abgeleitet, abgeleitet.count)
            }
        }
        guard status == kCCSuccess else {
            throw Tresorfehler(art: .beschaedigt, text: "Die Schlüsselableitung schlug fehl (\(status)).")
        }
        return SymmetricKey(data: abgeleitet)
    }

    static func hkdfWiederherstellung(_ roh: Data, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: roh), salt: salt,
                               info: Data(Wicklung.wiederherstellung.utf8), outputByteCount: 32)
    }

    // ── Der Wiederherstellungsschlüssel als Text ──────────────────────────

    /// 20 Byte → 32 Zeichen Base32 in acht Vierergruppen.
    static func wiederherstellungText(_ roh: Data) -> String {
        var bits = 0
        var wert = 0
        var zeichen: [Character] = []
        for byte in roh {
            wert = (wert << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                zeichen.append(wiederherstellungZeichen[(wert >> bits) & 31])
            }
        }
        if bits > 0 { zeichen.append(wiederherstellungZeichen[(wert << (5 - bits)) & 31]) }
        return stride(from: 0, to: zeichen.count, by: 4)
            .map { String(zeichen[$0..<min($0 + 4, zeichen.count)]) }
            .joined(separator: "-")
    }

    /// Nachsichtig beim Abtippen: Groß und Klein gleich, alles außer
    /// ASCII-Buchstaben und -Ziffern frei, 0 und 1 als O und I. Dieselbe Regel
    /// gilt in der Ansicht.
    static func wiederherstellungRoh(_ text: String) -> Data? {
        let bereinigt = text.uppercased()
            .replacingOccurrences(of: "0", with: "O")
            .replacingOccurrences(of: "1", with: "I")
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard bereinigt.count == wiederherstellungLaenge * 8 / 5 else { return nil }
        var bits = 0
        var wert = 0
        var bytes: [UInt8] = []
        for z in bereinigt {
            guard let stelle = wiederherstellungZeichen.firstIndex(of: z) else { return nil }
            wert = (wert << 5) | stelle
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((wert >> bits) & 255))
            }
        }
        guard bytes.count == wiederherstellungLaenge else { return nil }
        return Data(bytes)
    }
}

// ── Kleine Helfer ─────────────────────────────────────────────────────────

extension Data {
    static func zufall(_ anzahl: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: anzahl)
        if SecRandomCopyBytes(kSecRandomDefault, anzahl, &bytes) != errSecSuccess {
            var quelle = SystemRandomNumberGenerator()
            bytes = (0..<anzahl).map { _ in UInt8.random(in: .min ... .max, using: &quelle) }
        }
        return Data(bytes)
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }

    /// Nur Hexziffern — `UInt8("+f", radix: 16)` nähme ein Vorzeichen an.
    init?(hex: String) {
        let zeichen = Array(hex.lowercased())
        guard zeichen.count % 2 == 0, zeichen.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(zeichen.count / 2)
        var stelle = 0
        while stelle < zeichen.count {
            guard let byte = UInt8(String(zeichen[stelle...stelle + 1]), radix: 16) else { return nil }
            bytes.append(byte)
            stelle += 2
        }
        self.init(bytes)
    }
}
