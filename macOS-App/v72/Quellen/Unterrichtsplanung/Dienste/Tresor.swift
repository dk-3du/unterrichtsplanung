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

    /// Begrenzt in Tiefe, Breite und Textlänge (`Tresor.wicklungTiefeHoechstens`
    /// und Nachbarn): Der Kopf kommt aus einer fremden Datei, und eine
    /// Wicklung, die diese Fassung nicht kennt, wird Feld für Feld
    /// weitergetragen — ohne Grenze trüge sie beliebig viel mit. Dieselben
    /// Grenzen prüft die Ansicht (`wicklungGueltig`).
    init?(_ roh: Any, tiefe: Int = 0) {
        guard tiefe <= Tresor.wicklungTiefeHoechstens else { return nil }
        switch roh {
        case let s as String:
            guard s.unicodeScalars.count <= Tresor.wicklungTextHoechstens else { return nil }
            self = .text(s)
        case let n as NSNumber:
            // `JSONSerialization` liefert Wahrheitswerte und Zahlen beide als
            // `NSNumber`; nur `objCType` "c" ist der Wahrheitswert.
            if String(cString: n.objCType) == "c" { self = .wahr(n.boolValue) }
            else { self = .zahl(n.doubleValue) }
        case is NSNull: self = .leer
        case let l as [Any]:
            guard l.count <= Tresor.wicklungEintraegeHoechstens else { return nil }
            var werte: [JSONWert] = []
            for eintrag in l {
                guard let w = JSONWert(eintrag, tiefe: tiefe + 1) else { return nil }
                werte.append(w)
            }
            self = .liste(werte)
        case let o as [String: Any]:
            guard o.count <= Tresor.wicklungEintraegeHoechstens else { return nil }
            var werte: [String: JSONWert] = [:]
            for (k, v) in o {
                guard k.unicodeScalars.count <= Tresor.wicklungTextHoechstens,
                      let w = JSONWert(v, tiefe: tiefe + 1) else { return nil }
                werte[k] = w
            }
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
    /// Nur, was ein `Int` darstellen kann — `Int(z)` bräche bei 1e100 oder
    /// Unendlich den Prozess ab, und die Zahl kommt aus einer fremden Datei.
    var ganzzahl: Int? { if case .zahl(let z) = self, z.isFinite { return Int(exactly: z) }; return nil }

    /// Die Fassungsprüfung der Dienste (Behälterkopf, Nutzlast der
    /// Lesezeichen): nur eine echte ganze Zahl — `JSONSerialization` liefert
    /// auch `true` als `NSNumber`, und die Ansicht weist den Wahrheitswert ab.
    /// Das Modell hat dieselbe Regel als `Planungsdatei.ganzzahl`: Beide
    /// Dateien werden von den Prüfskripten für sich übersetzt und können
    /// einander nicht sehen.
    static func ganzzahl(aus wert: Any?) -> Int? {
        guard let zahl = wert as? NSNumber, String(cString: zahl.objCType) != "c" else { return nil }
        return Int(exactly: zahl.doubleValue)
    }
}

/// Der Datenschlüssel, versiegelt unter einem Wicklungsschlüssel. `art` sagt,
/// woher der kommt; die Felder sind je Art verschieden und werden für
/// unbekannte Arten unverändert mitgeführt.
struct Wicklung: Sendable, Equatable {
    static let enklave = "enklave"
    static let passphrase = "passphrase"
    static let wiederherstellung = "wiederherstellung"

    /// Feld der Wicklung dieses Macs (seit 1.7.6, E141): womit sie öffnet —
    /// „biometrie“ (Touch ID oder Anmeldepasswort) oder „passwort“ (das
    /// Anmeldepasswort allein). Ohne das Feld (Dateien bis 1.7.5) sagt die
    /// Oberfläche, was das Gerät kann. Nur Text im Kopf, nicht Teil des
    /// Umschlags; die Ansicht prüft es wie jedes Feld nur der Form nach.
    static let bedingung = "bedingung"
    static let bedingungBiometrie = "biometrie"
    static let bedingungPasswort = "passwort"

    let art: String
    var felder: [String: JSONWert]

    func text(_ name: String) -> String? { felder[name]?.text }

    /// Die Bedingung der Wicklung dieses Macs: wahr = Touch ID oder
    /// Anmeldepasswort, falsch = Anmeldepasswort allein, `nil` = kein Feld
    /// (bis 1.7.5), unbekannter Wert oder eine andere Wicklung.
    var biometrieBedingung: Bool? {
        guard art == Wicklung.enklave else { return nil }
        switch text(Wicklung.bedingung) {
        case Wicklung.bedingungBiometrie?: return true
        case Wicklung.bedingungPasswort?: return false
        default: return nil
        }
    }
    func daten(_ name: String) -> Data? { felder[name]?.text.flatMap { Data(base64Encoded: $0) } }
    func zahl(_ name: String) -> Int? { felder[name]?.ganzzahl }

    var beschriftung: String {
        switch art {
        case Wicklung.enklave:
            biometrieBedingung == false ? "Dieser Mac (Secure Enclave, Anmeldepasswort)"
                                        : "Dieser Mac (Secure Enclave, Touch ID oder Anmeldepasswort)"
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
    static let passphraseRegel = "Die Passphrase braucht mindestens \(passphraseMindestlaenge) Zeichen "
        + "und darf nicht nur aus Leerraum bestehen."

    /// Dieselbe Regel beim Anlegen, Ändern und Erneuern — das Entsperrblatt
    /// prüft nur auf leer, damit eine ältere Passphrase weiter hineinkommt.
    /// Getrimmt wird nichts: Das änderte den Schlüssel.
    static func passphraseZulaessig(_ passphrase: String) -> Bool {
        passphrase.count >= passphraseMindestlaenge
            && !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    static let kennungLaenge = 16
    /// Wicklungen je Behälter: Passphrase, Wiederherstellung, Enklave — und
    /// eine für eine spätere Art. Mehr trägt kein Behälter dieser App; darüber
    /// ist die Datei verdorben oder eine Bremse (jede Wicklung wäre zu prüfen).
    static let wicklungenHoechstens = 4
    /// Je Wicklung: Verschachtelungstiefe, Einträge je Objekt oder Liste,
    /// Codepunkte je Text und Schlüssel. Die Enklaven-Wicklung trägt den
    /// größten Wert (die Darstellung des Geräteschlüssels, einige hundert Byte).
    static let wicklungTiefeHoechstens = 4
    static let wicklungEintraegeHoechstens = 64
    static let wicklungTextHoechstens = 4096
    /// Salt — der Fachbegriff bleibt unübersetzt. Im Behälter heißt das Feld
    /// `salz`; der Name ist Teil des Dateiformats, damit jede versiegelte Datei und
    /// die Ansicht im Netz weiterlesen.
    static let saltLaenge = 16
    static let wiederherstellungLaenge = 20
    /// Base32 ohne 0, 1, 8 und 9 — nichts, was sich beim Abtippen verwechselt.
    static let wiederherstellungAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    static let wiederherstellungZeichen = Array(wiederherstellungAlphabet)

    /// `lesezeichen`: der Vorrat der Lesezeichen samt Zielordner neben der
    /// Ablage; `sitzplaene`: die Sitzpläne der Klassen daneben — beide liest nur
    /// die App, die Ansicht weist sie wie `rohdaten` ab.
    enum Inhalt: String, Sendable { case planung, status, rohdaten, lesezeichen, sitzplaene }

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

    /// Ob die Secure Enclave für die Wicklung dieses Macs in Frage kommt — nur
    /// der Prüfstand verzichtet: Kein `swift test` darf je in einen
    /// Touch-ID-Dialog laufen. `Ablage.enklaveImPruefstand` hebt das für den
    /// Prüfstand am Fenster auf. **Verfügbar heißt nicht, dass die Wicklung
    /// gelingt** (B32): In einer VM ohne eingerichtete Touch ID meldete sich die
    /// Enklave verfügbar, der Schlüssel mit `.biometryCurrentSet` ließ sich aber
    /// nicht anlegen. Darum ist die Wicklung nie Bedingung des Einschaltens
    /// (`Planungsspeicher.tresorVorbereiten`), und die Zugriffsbedingung folgt
    /// dem Gerät (`zugriffsbedingung(biometrie:)`).
    static var enklaveVerfuegbar: Bool {
        (!Ablage.istPruefstand || Ablage.enklaveImPruefstand) && enklaveVorhanden
    }

    static var enklaveVorhanden: Bool { SecureEnclave.isAvailable }

    /// Ist auf diesem Mac Biometrie eingerichtet (Touch ID mit angelernten
    /// Fingern)? **Im Augenblick bestimmt, bei jedem Aufruf** (E140, N64-01).
    /// Bis 1.7.5 war das ein `static let`: Wer Touch ID nach dem Start
    /// einrichtete und die Wicklung über „Dieser Mac“ aus- und wieder
    /// einschaltete, bekam dieselbe Bedingung noch einmal — entgegen dem Fuß
    /// des Schalters. Apple rät, das Ergebnis von `canEvaluatePolicy` nicht
    /// aufzubewahren; ein frischer Aufruf kostet rund eine Millisekunde
    /// (gemessen 16.09.2026). Wer Touch ID später einrichtet, legt die
    /// Wicklung über den Schalter neu an (E135) — jetzt nach dem Gerät der
    /// Stunde.
    static var biometrieEingerichtet: Bool {
        // Nur im Prüfstand (eigener Ordner oder Prüfziel) lässt sich das Gerät
        // stellen — `PRUEFSTAND_BIOMETRIE=0|1` zeigt die Wörter und Blätter
        // eines Macs ohne Touch ID auch auf einem Mac mit Touch ID (B33).
        if Ablage.istPruefstand,
           let gestellt = ProcessInfo.processInfo.environment["PRUEFSTAND_BIOMETRIE"] {
            return gestellt == "1"
        }
        var fehler: NSError?
        let kann = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &fehler)
        return biometrieEingerichtet(
            kann: kann,
            fehler: fehler.flatMap { $0.domain == LAErrorDomain ? LAError.Code(rawValue: $0.code) : nil })
    }

    /// Die reine Abbildung — nicht jedes „nein“ heißt „keine Biometrie“
    /// (zwölfte Review): Nach zu vielen Fehlversuchen gesperrt, die Tastatur
    /// mit Touch ID getrennt oder nicht gekoppelt — die Finger sind angelernt,
    /// der Schlüssel mit `.biometryCurrentSet` lässt sich anlegen, und das
    /// Anmeldepasswort ist der Oder-Zweig. Nicht angelernt (die VM: −7), nicht
    /// vorhanden, kein Passwort gesetzt oder ein anderer Grund: nein.
    /// Sperre und getrennte Tastatur sind hier nicht am Lauf nachgestellt —
    /// nur diese Abbildung; scheitert das Anlegen dort doch, greift E131.
    static func biometrieEingerichtet(kann: Bool, fehler: LAError.Code?) -> Bool {
        if kann { return true }
        switch fehler {
        case .biometryLockout?, .biometryDisconnected?, .biometryNotPaired?: return true
        default: return false
        }
    }

    /// Die Zugriffsbedingung des Schlüssels dieses Macs, nach dem Gerät (E132):
    /// mit eingerichteter Biometrie Touch ID der heutigen Finger **oder** das
    /// Anmeldepasswort — die Wicklung verfällt mit neu angelernten Fingern, das
    /// Passwort ist der Oder-Zweig —; ohne sie das Anmeldepasswort allein. In
    /// der VM des Nutzers gemessen (16.09.2026, macOS 27.0 ohne Touch ID): Die
    /// erste Form scheitert mit LocalAuthentication −1000, die zweite legt an.
    static func zugriffsbedingung(biometrie: Bool) -> SecAccessControlCreateFlags {
        biometrie ? [.privateKeyUsage, .biometryCurrentSet, .or, .devicePasscode]
                  : [.privateKeyUsage, .devicePasscode]
    }

    /// Wie dieser Mac die Wicklung öffnet — für die Wörter der Oberfläche
    /// (E134): Ein Häkchen „Mit Touch ID öffnen“ auf einem Mac ohne Touch ID
    /// wäre eine falsche Zusage.
    static func freigabeName(biometrie: Bool) -> String {
        biometrie ? "Touch ID oder das Anmeldepasswort" : "das Anmeldepasswort"
    }
    static var freigabeName: String { freigabeName(biometrie: biometrieEingerichtet) }

    /// Dasselbe am Satzanfang.
    static func freigabeNameGross(biometrie: Bool) -> String {
        biometrie ? "Touch ID oder das Anmeldepasswort" : "Das Anmeldepasswort"
    }
    static var freigabeNameGross: String { freigabeNameGross(biometrie: biometrieEingerichtet) }

    static func schalterName(biometrie: Bool) -> String {
        biometrie ? "Mit Touch ID öffnen" : "Mit dem Anmeldepasswort öffnen"
    }
    static var schalterName: String { schalterName(biometrie: biometrieEingerichtet) }

    /// Womit dieser Mac beim Start öffnet — der Satz, den die Einrichtung
    /// sagen muss, bevor eingeschaltet wird (B33, Nutzer 16.09.2026: In der VM
    /// erfuhr niemand, dass künftig das Anmeldepasswort entsperrt). Steht in
    /// der Frage der Ersteinrichtung, in Schritt 2 vor dem Einschalten und
    /// als Meldung danach.
    /// In drei Teilen, weil der Kern im Blatt **fett** steht (Nutzer,
    /// 16.09.2026: Der Satz muss ins Auge fallen — ein Missverständnis hier
    /// kostet viel Frust): ein Vorsatz, der sagt, was der Mac nicht hat (nur
    /// ohne Touch ID), der Kern — womit beim Start geöffnet wird — und der
    /// Rest zur Passphrase.
    struct Starthinweis: Equatable, Sendable {
        let vorsatz: String?
        let kern: String
        let rest: String
        var text: String { [vorsatz, kern, rest].compactMap { $0 }.joined(separator: " ") }
    }

    static func starthinweis(biometrie: Bool) -> Starthinweis {
        biometrie
            ? Starthinweis(
                vorsatz: nil,
                kern: "Beim Start öffnet Touch ID oder das Anmeldepasswort dieses Macs die Planung.",
                rest: "Die Passphrase ist auf diesem Mac nur fällig, wenn der Schalter „Mit Touch ID "
                    + "öffnen“ ausgeschaltet wird; auf dem iPad und auf jedem anderen Rechner öffnet "
                    + "immer die Passphrase.")
            : Starthinweis(
                vorsatz: "Dieser Mac hat keine eingerichtete Touch ID.",
                kern: "Beim Start öffnet deshalb das Anmeldepasswort dieses Macs die Planung — dasselbe "
                    + "Passwort wie bei der Anmeldung am Mac.",
                rest: "Die Passphrase ist auf diesem Mac nur fällig, wenn der Schalter „Mit dem "
                    + "Anmeldepasswort öffnen“ ausgeschaltet wird; auf dem iPad und auf jedem anderen "
                    + "Rechner öffnet immer die Passphrase.")
    }
    static var starthinweis: Starthinweis { starthinweis(biometrie: biometrieEingerichtet) }

    static func startHinweis(biometrie: Bool) -> String { starthinweis(biometrie: biometrie).text }
    static var startHinweis: String { startHinweis(biometrie: biometrieEingerichtet) }

    /// Was aus der Wicklung dieses Macs beim Vorbereiten wurde (E139, N64-02).
    /// Bis 1.7.5 gab es nur „ein Grund“ oder keiner — und keiner hieß
    /// „Wicklung da“, auch wenn keine versucht worden war (keine Secure
    /// Enclave, Prüfstand): Schritt 2 versprach dann das Anmeldepasswort.
    /// Blatt, Meldung und Prüfungen lesen jetzt aus diesem Ergebnis, nicht aus
    /// der Abwesenheit eines Fehlers und nicht aus dem Gerät.
    enum Geraetewicklung: Equatable, Sendable {
        /// Angelegt — mit der Bedingung des Augenblicks: Touch ID oder das
        /// Anmeldepasswort (`biometrie`), sonst das Anmeldepasswort allein.
        case angelegt(biometrie: Bool)
        /// Nicht versucht: keine Secure Enclave — oder der Prüfstand meidet sie.
        case nichtVerfuegbar
        /// Versucht und gescheitert — der Satz mit Grund und Weg (E131).
        case gescheitert(grund: String)

        /// Der Hinweis für Schritt 2 (B33) — für die Fälle mit einem
        /// Öffnungsweg; das Scheitern zeigt das Blatt als Warnung mit dem Grund.
        var starthinweis: Starthinweis? {
            switch self {
            case .angelegt(let biometrie):
                Tresor.starthinweis(biometrie: biometrie)
            case .nichtVerfuegbar:
                Starthinweis(
                    vorsatz: "Dieser Mac bietet keine Wicklung für das Gerät (keine Secure Enclave verfügbar).",
                    kern: "Beim Start ist deshalb die Passphrase fällig.",
                    rest: "So öffnet die Planung auch auf dem iPad und auf jedem anderen Rechner.")
            case .gescheitert:
                nil
            }
        }

        /// Die Meldung nach dem Einschalten oder Erneuern — aus dem Ergebnis:
        /// gescheitert → der Grund als Warnung (B32); angelegt ohne Touch ID →
        /// dass ab jetzt das Anmeldepasswort öffnet (B33); nicht verfügbar →
        /// dass die Passphrase fällig ist. Mit Touch ID gibt es nichts zu sagen.
        var meldung: (text: String, warnung: Bool)? {
            switch self {
            case .angelegt(biometrie: true):
                nil
            case .angelegt(biometrie: false):
                ("Beim Start öffnet das Anmeldepasswort dieses Macs die Planung — dasselbe "
                 + "Passwort wie bei der Anmeldung am Mac; die Passphrase gilt auf dem iPad und "
                 + "auf jedem anderen Rechner.", false)
            case .nichtVerfuegbar:
                ("Dieser Mac bietet keine Wicklung für das Gerät (keine Secure Enclave verfügbar) — "
                 + "beim Start ist die Passphrase fällig, wie auf dem iPad und auf jedem anderen Rechner.", false)
            case .gescheitert(let grund):
                (grund, true)
            }
        }
    }

    func hat(_ art: String) -> Bool { wicklungen.contains { $0.art == art } }

    func wicklung(_ art: String) -> Wicklung? { wicklungen.first { $0.art == art } }

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

    /// Eine Wicklung, die abseits des Hauptstrangs an einer Kopie dieses Tresors
    /// entstanden ist (gleicher Schlüssel, gleiche Kennung), hier übernehmen.
    func wicklungUebernehmen(_ neu: Wicklung) { ersetzen(neu) }

    /// PBKDF2 läuft nur hier und beim Ändern der Passphrase — nie beim Sichern,
    /// nie beim Beenden.
    func passphraseSetzen(_ passphrase: String, runden: Int = rundenStandard) throws {
        guard Tresor.passphraseZulaessig(passphrase) else {
            throw Tresorfehler(art: .falscherSchluessel, text: Tresor.passphraseRegel)
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

    /// Ein P256-Schlüssel in der Secure Enclave, gebunden nach dem Gerät
    /// (`zugriffsbedingung(biometrie:)`): an Touch ID **oder** das
    /// Anmeldepasswort, ohne eingerichtete Biometrie an das Anmeldepasswort
    /// allein. `biometrie` ist der Wert des Augenblicks, vom Aufrufer bestimmt
    /// (E140); die Wicklung trägt ihn als Feld `bedingung` (E141), weil die
    /// Zugriffsbedingung im Schlüsselblob von außen nicht zu lesen ist.
    /// Gewickelt wird über den öffentlichen Teil — der ist ohne Freigabe zu
    /// haben (nachgemessen); Anlegen und Neuwickeln kosten keine Nachfrage.
    /// `auchImPruefstand` nur für den Prüfstein ohne Dialog.
    func enklaveAnlegen(biometrie: Bool = Tresor.biometrieEingerichtet, auchImPruefstand: Bool = false) throws {
        guard Tresor.enklaveVerfuegbar || (auchImPruefstand && SecureEnclave.isAvailable) else {
            throw Tresorfehler(art: .keineEnklave,
                               text: "Die Secure Enclave steht hier nicht zur Verfügung.")
        }
        var fehler: Unmanaged<CFError>?
        guard let schutz = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            Tresor.zugriffsbedingung(biometrie: biometrie), &fehler)
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
            Wicklung.bedingung: .text(biometrie ? Wicklung.bedingungBiometrie : Wicklung.bedingungPasswort),
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
            authenticating: Tresor.zusatz(inhalt: inhalt.rawValue, kennung: kennung, version: Tresor.version))
        return try Tresor.behaelterSchreiben(
            inhalt: inhalt, kennung: kennung, nonce: Data(nonce),
            wicklungen: wicklungen(fuer: ziel), daten: versiegelt.ciphertext + versiegelt.tag)
    }

    /// Die Wicklungen, die ein Behälter für dieses Ziel trägt.
    func wicklungen(fuer ziel: Ziel) -> [Wicklung] {
        let alle = wicklungen
        return switch ziel {
        case .ablage: alle
        case .kopie: alle.filter { !$0.istGeraetegebunden }
        case .export: alle.filter { $0.art == Wicklung.passphrase || $0.art == Wicklung.wiederherstellung }
        }
    }

    /// Trägt der Behälter denselben Datenschlüssel **und** dieselbe Hülle wie
    /// dieser Tresor für das Ziel? Nur dann ist nach einem Wechsel der Hülle
    /// (Passphrase, Wicklung dieses Macs) nichts nachzuziehen — die Kennung
    /// allein bleibt dabei gleich.
    func huelleGleich(_ kopf: Behaelterkopf, ziel: Ziel) -> Bool {
        guard kopf.kennung == kennung else { return false }
        let nachArt: (Wicklung, Wicklung) -> Bool = { $0.art < $1.art }
        return kopf.wicklungen.sorted(by: nachArt) == wicklungen(fuer: ziel).sorted(by: nachArt)
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

    static let bisherigePasstNicht = "Die bisherige Passphrase passt nicht."

    /// Belegt, nicht abgefragt: Nur wer die Passphrase kennt, darf sie ersetzen
    /// oder den Schlüssel erneuern. Der Kopf wird geprüft wie beim Öffnen — die
    /// Wicklung kann aus einer Datei stammen, die über die Enklave aufging —,
    /// und ein beschädigter heißt hier wie dort beschädigt, nie „passt nicht“.
    func passphraseBelegen(_ passphrase: String) throws {
        let (w, salt, runden) = try Tresor.passphraseWicklung(in: wicklungen)
        let kek = try Tresor.pbkdf2(passphrase, salt: salt, runden: runden)
        let probe = try Tresor.entwickeln(w, kennung: kennung, wicklungen: wicklungen, mit: kek,
                                          fehltext: Tresor.bisherigePasstNicht)
        guard probe.schluessel == schluessel else {
            throw Tresorfehler(art: .falscherSchluessel, text: Tresor.bisherigePasstNicht)
        }
    }

    func passphraseStimmt(_ passphrase: String) -> Bool {
        (try? passphraseBelegen(passphrase)) != nil
    }

    // ── Entwickeln: aus einem Kopf den Datenschlüssel holen ───────────────

    static func oeffnen(kopf: Behaelterkopf, passphrase: String) throws -> Tresor {
        let (w, salt, runden) = try passphraseWicklung(in: kopf.wicklungen)
        let kek = try pbkdf2(passphrase, salt: salt, runden: runden)
        return try entwickeln(w, kennung: kopf.kennung, wicklungen: kopf.wicklungen, mit: kek, fehltext: "Die Passphrase passt nicht.")
    }

    /// Die Passphrase-Wicklung, geprüft: `kdf`, Rundenzahl in den Grenzen,
    /// Salt-Mindestlänge — eine Schranke für Öffnen, Belegen und Neuwickeln.
    private static func passphraseWicklung(in wicklungen: [Wicklung]) throws
        -> (wicklung: Wicklung, salt: Data, runden: Int) {
        guard let w = wicklungen.first(where: { $0.art == Wicklung.passphrase }) else {
            throw Tresorfehler(art: .keineWicklung,
                               text: "Die Datei trägt keine Passphrase-Wicklung.")
        }
        guard w.text("kdf") == kdfPassphrase,
              let runden = w.zahl("runden"), runden >= rundenMindestens, runden <= rundenHoechstens,
              let salt = w.daten("salz"), salt.count >= 8
        else { throw Tresorfehler(art: .beschaedigt, text: "Die Passphrase-Wicklung ist beschädigt.") }
        return (w, salt, runden)
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
        return try entwickeln(w, kennung: kopf.kennung, wicklungen: kopf.wicklungen, mit: hkdfWiederherstellung(roh, salt: salt),
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
        return try entwickeln(w, kennung: kopf.kennung, wicklungen: kopf.wicklungen, mit: kek,
                              fehltext: "Die Wicklung für diesen Mac passt nicht.")
    }

    /// Die Beglaubigung der Wicklung schlägt fehl, bevor irgendwer die Daten
    /// anrührt: „falsch“ ist belegt, nicht geraten.
    private static func entwickeln(_ w: Wicklung, kennung: Data, wicklungen: [Wicklung],
                                   mit kek: SymmetricKey, fehltext: String) throws -> Tresor {
        guard let nonce = w.daten("nonce"), let umschlag = w.daten("umschlag"),
              nonce.count == 12, umschlag.count == 32 + 16
        else { throw Tresorfehler(art: .beschaedigt, text: "Die Wicklung ist beschädigt.") }
        let roh: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce),
                                            ciphertext: umschlag.prefix(32),
                                            tag: umschlag.suffix(16))
            roh = try AES.GCM.open(box, using: kek,
                                   authenticating: zusatz(art: w.art, kennung: kennung))
        } catch {
            throw Tresorfehler(art: .falscherSchluessel, text: fehltext)
        }
        return Tresor(schluessel: SymmetricKey(data: roh), kennung: kennung, wicklungen: wicklungen)
    }

    // ── Der Behälter auf der Platte ───────────────────────────────────────

    /// Was in den Byte liegt — nach der Regel, die die Ansicht seit je hat
    /// (`istBehaelter(zerlegt)`: deuten, dann `typ`; E107): Byte-Reihenfolgemarke
    /// und Leerraum überspringen, JSON deuten, das Feld `typ` vergleichen. An
    /// der Schreibweise hängt nichts — nicht am Vorsatz `{"typ":…` (den diese
    /// App schreibt, damit `head -c 40` ihn zeigt), nicht an einem Fenster von
    /// 64 Byte, nicht an einer Zeichenfolge irgendwo in der Datei. Bis v59
    /// taten das drei Abkürzungen, und jede irrte einmal (N57-01 Rest, B28): Ein
    /// umformatierter, abgeschnittener Behälter galt als Klartext und wurde
    /// ersetzt (gemessen: 289 → 23 Byte); ein unversehrter mit Marke,
    /// Ausweichschreibung im Typnamen oder mehr Leerraum davor ebenso — obwohl
    /// `oeffnen` ihn öffnete. Damit fällt der letzte zweite Erkenner (nach
    /// N54-02, N55-01, N56-01, N57-01) — es gibt nur noch diesen.
    ///
    /// **Drei Antworten, nicht zwei (E108).** Was sich nicht als JSON deuten
    /// lässt, ist *kein* Klartext — der Formwächter sperrt dann, statt zu
    /// ersetzen. Leer oder nur Leerraum ist Klartext (eine frisch angelegte
    /// Datei darf beschrieben werden); deutbares JSON ohne den Typ ist Klartext
    /// (eine Planung, deren Titel den Typnamen trägt, bleibt eine).
    enum Deutung: Equatable, Sendable {
        case klartext
        case behaelter
        /// Nicht leer und kein JSON.
        case undeutbar
    }

    static func deuten(_ roh: Data) -> Deutung {
        let inhalt = ohneMarkeUndLeerraum(roh)
        if inhalt.isEmpty { return .klartext }
        guard let objekt = try? JSONSerialization.jsonObject(with: inhalt) else { return .undeutbar }
        return (objekt as? [String: Any])?["typ"] as? String == typ ? .behaelter : .klartext
    }

    /// Ein Behälter, den der Leser zu öffnen versuchen würde. Ob er ihn
    /// annimmt, sagt allein `kopfLesen` — Erkennen ist nicht Erlauben (N57-01).
    static func istBehaelter(_ roh: Data) -> Bool { deuten(roh) == .behaelter }

    /// UTF-8-Marke (EF BB BF) und Leerraum am Anfang, so weit sie reichen — als
    /// Teilstück, ohne Kopie. Deuter und Leser nehmen denselben Weg.
    private static func ohneMarkeUndLeerraum(_ roh: Data) -> Data {
        var inhalt = roh[...]
        if inhalt.starts(with: [0xEF, 0xBB, 0xBF]) { inhalt = inhalt.dropFirst(3) }
        return inhalt.drop { $0 == 0x20 || $0 == 0x0a || $0 == 0x0d || $0 == 0x09 }
    }

    static func kopfLesen(_ roh: Data) throws -> Behaelterkopf {
        let beschaedigt = Tresorfehler(art: .beschaedigt,
                                       text: "Der verschlüsselte Behälter ist beschädigt.")
        guard let objekt = (try? JSONSerialization.jsonObject(with: ohneMarkeUndLeerraum(roh))) as? [String: Any],
              objekt["typ"] as? String == typ
        else { throw beschaedigt }
        guard let version = JSONWert.ganzzahl(aus: objekt["version"]), version >= 1 else { throw beschaedigt }
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
              let rohWicklungen = objekt["wicklungen"] as? [[String: Any]],
              rohWicklungen.count <= wicklungenHoechstens
        else { throw beschaedigt }
        var wicklungen: [Wicklung] = []
        for eintrag in rohWicklungen {
            guard let art = eintrag["art"] as? String, !art.isEmpty,
                  art.unicodeScalars.count <= wicklungTextHoechstens,
                  eintrag.count <= wicklungEintraegeHoechstens
            else { throw beschaedigt }
            var felder: [String: JSONWert] = [:]
            for (name, wert) in eintrag where name != "art" {
                guard name.unicodeScalars.count <= wicklungTextHoechstens,
                      let w = JSONWert(wert, tiefe: 1) else { throw beschaedigt }
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
            // Die Fassung aus dem Kopf, nicht die Konstante — wie die Ansicht:
            // Ein späterer Sprung der Fassung öffnete Behälter der Fassung 1 sonst
            // nicht mehr, obwohl `kopfLesen` sie noch annimmt.
            return try AES.GCM.open(box, using: schluessel,
                                    authenticating: zusatz(inhalt: kopf.inhalt, kennung: kopf.kennung,
                                                           version: kopf.version))
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

    static func zusatz(inhalt: String, kennung: Data, version: Int) -> Data {
        Data("\(typ)|\(version)|\(inhalt)|\(kennung.hex)".utf8)
    }

    static func zusatz(art: String, kennung: Data) -> Data {
        Data("\(art)|\(kennung.hex)".utf8)
    }

    // ── Schlüsselableitung ────────────────────────────────────────────────

    /// Die Rundenzahl im erlaubten Bereich und als `UInt32` — geprüft hier,
    /// an der tiefsten Stelle, damit kein Aufrufer daran vorbeikommt: Darunter
    /// ist ein Kopf untergeschoben, darüber eine Bremse, und `UInt32(_:)`
    /// bräche bei einem Wert außerhalb den Prozess ab.
    static func gepruefteRundenzahl(_ runden: Int) throws -> UInt32 {
        guard (rundenMindestens...rundenHoechstens).contains(runden), let anzahl = UInt32(exactly: runden) else {
            throw Tresorfehler(art: .beschaedigt, text: "Die Rundenzahl liegt außerhalb des erlaubten Bereichs.")
        }
        return anzahl
    }

    /// NFC-normalisiert und UTF-8 — sonst ist ein „ä“ hier ein Zeichen und
    /// im Browser zwei, und die Passphrase „geht nicht“.
    static func pbkdf2(_ passphrase: String, salt: Data, runden: Int) throws -> SymmetricKey {
        let anzahl = try gepruefteRundenzahl(runden)
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
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), anzahl,
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
