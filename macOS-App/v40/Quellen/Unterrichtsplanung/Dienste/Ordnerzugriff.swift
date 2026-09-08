// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Zugriff auf Orte außerhalb des Containers — über Lesezeichen mit
/// Sicherheitsbereich, die aus der Wahl des Nutzers entstehen (Auswahldialog,
/// Ziehen) und diese Wahl über Neustarts hinweg festhalten. Dazu der Pfad des
/// Zielordners der Kopie: Er ist ein Ort wie die Lesezeichen und geht
/// denselben Weg.
///
/// Im App Sandbox erreicht die App von sich aus nur ihren Container. Jede Wahl
/// des Nutzers gewährt den Zugriff für die laufende Sitzung; damit er den
/// Neustart übersteht, entsteht sofort ein Lesezeichen (`merken`). Ein
/// Lesezeichen auf einen Ordner deckt alles darunter ab.
///
/// **Wo der Vorrat liegt**, hängt am Schutz der Ablage: unverschlüsselt in den
/// Einstellungen im Container — nur für diese App auf diesem Mac; bei
/// eingeschalteter Verschlüsselung als Behälter `lesezeichen.json` neben
/// `planung.json`, versiegelt unter dem Datenschlüssel: Ein Lesezeichen nennt
/// Pfade, und die stünden sonst als Einziges einer versiegelten Planung im
/// Klartext. Bis zum Entsperren ist der Vorrat **zu**, nicht leer — nichts
/// ist zuständig, und nichts fragt vorher nach einem Ort. Ein Prüflauf lässt
/// die Einstellungen unangetastet (Klartext nur im Speicher); den Behälter
/// schreibt er in seine eigene Ablage.
///
/// Ohne Sandbox (das Prüfziel von `swift test`, ein ungesiegelter Bau) läuft
/// derselbe Code mit gewöhnlichen Lesezeichen: `mit` legt keinen
/// Sicherheitsbereich, und der Zugriff gelingt ohnehin.
///
/// Einer je Sicherungsdienst, an dessen Ablage — keinen prozessweiten: Die
/// App hat einen, Prüfungen mit eigener Ablage haben ihren eigenen.
/// Die vier Handgriffe, die der Klartext-Vorrat an den Einstellungen braucht
/// — `UserDefaults` hat sie; Prüfungen bringen eine Attrappe im Speicher mit,
/// damit kein Prüflauf eine Datei unter `~/Library/Preferences` hinterlässt.
protocol Einstellungsspeicher: AnyObject {
    func dictionary(forKey defaultName: String) -> [String: Any]?
    func string(forKey defaultName: String) -> String?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: Einstellungsspeicher {}

@MainActor
@Observable
final class Ordnerzugriff {

    /// Läuft die App im App Sandbox? Dann gilt: kein Zugriff ohne Wahl.
    static var imSandbox: Bool { Ablage.container != nil }

    /// Ein benannter Fehler — die Oberfläche macht daraus „erneut wählen“,
    /// nie ein stilles Scheitern.
    struct Fehler: Error, Equatable, Sendable {
        enum Art: Sendable { case keinLesezeichen, unaufloesbar, keinZugriff, versiegelt }
        let art: Art
        let pfad: String
        let text: String

        init(_ art: Art, pfad: String, grund: String = "") {
            self.art = art
            self.pfad = pfad
            let name = Pfade.dateiName(pfad)
            switch art {
            case .keinLesezeichen:
                text = "Auf „\(name)“ darf die App noch nicht zugreifen — der Ort wurde ihr "
                    + "in dieser Fassung noch nicht gezeigt."
            case .unaufloesbar:
                text = "„\(name)“ ließ sich nicht wiederfinden"
                    + (grund.isEmpty ? "." : " (\(grund)).")
            case .keinZugriff:
                text = "Der Zugriff auf „\(name)“ wurde nicht gewährt — bitte den Ort erneut wählen."
            case .versiegelt:
                text = "Die Lesezeichen sind noch versiegelt — bitte zuerst die Planung entsperren."
            }
        }
    }

    private static let schluessel = "unterrichtsplanung.lesezeichen"

    // ── Der Vorrat und seine Quelle ───────────────────────────────────────

    /// Woher der Vorrat kommt — und ob er gerade offensteht.
    enum Quelle: Equatable, Sendable {
        /// Klartext in den Einstellungen: Die Ablage ist unverschlüsselt.
        case einstellungen
        /// Die Ablage liegt versiegelt, der Behälter ist noch zu.
        case zu
        /// Der Behälter neben der Ablage, offen unter dem Datenschlüssel.
        case behaelter
    }

    private(set) var quelle: Quelle = .einstellungen

    @ObservationIgnored private let ablage: Ablage
    @ObservationIgnored private var tresor: Tresor?

    /// Wo der Klartext-Vorrat liegt — `nil` im Prüflauf: Der lässt die
    /// Einstellungen des Nutzers unangetastet. Prüfungen reichen eine eigene
    /// Suite herein, um den Weg in die Einstellungen und zurück zu belegen.
    @ObservationIgnored private let einstellungen: (any Einstellungsspeicher)?

    /// Schlüssel = kanonischer Pfad. Zu heißt: liegt im Speicher, gilt nicht.
    private(set) var eintraege: [String: Data]

    /// Der Zielordner der Kopie, wie er gemerkt ist — auch hinter „zu“.
    private var gemerkterZielordner: String

    /// Ein Schreibfehler des Behälters, der niemanden aufhalten darf: Die
    /// Sitzung behält den Eintrag, gesichert ist er nicht — das sagt der
    /// Speicher dem Nutzer.
    @ObservationIgnored var beiStoerung: @MainActor (String) -> Void = { _ in }

    init(ablage: Ablage,
         einstellungen: (any Einstellungsspeicher)? = Ablage.istPruefstand ? nil : UserDefaults.standard) {
        self.ablage = ablage
        self.einstellungen = einstellungen
        // Ein Prüflauf erbt nichts aus den Einstellungen und schreibt nichts hinein.
        guard let einstellungen else {
            eintraege = [:]
            gemerkterZielordner = ""
            return
        }
        eintraege = einstellungen.dictionary(forKey: Ordnerzugriff.schluessel) as? [String: Data] ?? [:]
        gemerkterZielordner = einstellungen.string(forKey: Einstellungen.Schluessel.autoexportOrdner) ?? ""
    }

    /// Leer heißt: noch keiner gewählt — oder noch zu.
    var zielordner: String {
        get { quelle == .zu ? "" : gemerkterZielordner }
        set {
            guard quelle != .zu, newValue != gemerkterZielordner else { return }
            gemerkterZielordner = newValue
            ablegen()
        }
    }

    // ── Ablegen: Einstellungen oder Behälter ─────────────────────────────

    private func ablegen() {
        switch quelle {
        case .einstellungen:
            einstellungenSchreiben()
        case .zu:
            break
        case .behaelter:
            if let grund = behaelterSchreiben() {
                beiStoerung("Die Lesezeichen ließen sich nicht versiegelt sichern (\(grund)) — sie gelten "
                            + "für diese Sitzung; der nächste Start fragt nach den Ordnern.")
            }
        }
    }

    private func einstellungenSchreiben() {
        guard let einstellungen else { return }
        if eintraege.isEmpty {
            einstellungen.removeObject(forKey: Ordnerzugriff.schluessel)
        } else {
            einstellungen.set(eintraege, forKey: Ordnerzugriff.schluessel)
        }
        if gemerkterZielordner.isEmpty {
            einstellungen.removeObject(forKey: Einstellungen.Schluessel.autoexportOrdner)
        } else {
            einstellungen.set(gemerkterZielordner, forKey: Einstellungen.Schluessel.autoexportOrdner)
        }
    }

    /// Nach dem Versiegeln: Kein Pfad bleibt im Klartext zurück.
    private func einstellungenLeeren() {
        guard let einstellungen else { return }
        einstellungen.removeObject(forKey: Ordnerzugriff.schluessel)
        einstellungen.removeObject(forKey: Einstellungen.Schluessel.autoexportOrdner)
    }

    // ── Der Behälter ──────────────────────────────────────────────────────

    /// Obergrenze beim Lesen — ein Lesezeichen hat rund ein Kilobyte.
    static let hoechstgroesse = 8 * 1024 * 1024

    /// Die Fassung der Nutzlast; der Behälter darum hat seine eigene.
    static let nutzlastfassung = 1

    /// Die Nutzlast: Lesezeichen (Base64) je Pfad und der Zielordner.
    static func nutzlast(eintraege: [String: Data], zielordner: String) throws -> Data {
        let objekt: [String: Any] = [
            "version": nutzlastfassung,
            "lesezeichen": eintraege.mapValues { $0.base64EncodedString() },
            "zielordner": zielordner,
        ]
        return try JSONSerialization.data(withJSONObject: objekt, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func nutzlastLesen(_ daten: Data) throws -> (eintraege: [String: Data], zielordner: String) {
        let beschaedigt = Tresorfehler(art: .beschaedigt, text: "Die Nutzlast der Lesezeichen ist beschädigt.")
        guard let objekt = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any],
              let rohVersion = objekt["version"] as? NSNumber, String(cString: rohVersion.objCType) != "c",
              Int(exactly: rohVersion.doubleValue) == nutzlastfassung,
              let roh = objekt["lesezeichen"] as? [String: Any],
              let zielordner = objekt["zielordner"] as? String
        else { throw beschaedigt }
        var eintraege: [String: Data] = [:]
        for (pfad, wert) in roh {
            guard !pfad.isEmpty, let text = wert as? String, let daten = Data(base64Encoded: text)
            else { throw beschaedigt }
            eintraege[pfad] = daten
        }
        return (eintraege, zielordner)
    }

    /// Den Behälter im Speicher bauen, atomar ablegen, zurücklesen und
    /// vergleichen. `nil` heißt gelungen, sonst der Grund — und dann liegt auf
    /// der Platte, was vorher lag.
    private func behaelterSchreiben() -> String? {
        guard let tresor else { return "kein Schlüssel" }
        do {
            let klartext = try Ordnerzugriff.nutzlast(eintraege: eintraege, zielordner: gemerkterZielordner)
            try ablage.lesezeichenSchreiben(try tresor.versiegeln(klartext, inhalt: .lesezeichen, ziel: .ablage))
            guard case .daten(let roh) = ablage.lesezeichenLesen() else { return "nicht zurücklesbar" }
            let gelesen = try Ordnerzugriff.nutzlastLesen(try tresor.oeffnen(roh))
            guard gelesen.eintraege == eintraege, gelesen.zielordner == gemerkterZielordner else {
                return "die Platte trägt einen anderen Stand"
            }
            return nil
        } catch {
            return (error as? Tresorfehler)?.text ?? error.localizedDescription
        }
    }

    // ── Übergänge ─────────────────────────────────────────────────────────

    /// Die Ablage liegt versiegelt, der Schlüssel ist noch zu: Der Vorrat
    /// schließt sich. Was aus den Einstellungen kam, bleibt für das Entsperren
    /// im Speicher — zu sehen ist nichts.
    func schliessen() {
        quelle = .zu
        tresor = nil
    }

    /// Was das Öffnen nach dem Entsperren ergab.
    enum Oeffnungsbefund: Equatable, Sendable {
        /// Der Behälter lag und ist offen — so viele Lesezeichen.
        case geoeffnet(Int)
        /// Kein Behälter: Der Vorrat aus den Einstellungen ist jetzt versiegelt.
        case angelegt(Int, zielordner: Bool)
        /// Beschädigt oder unter fremdem Schlüssel: beiseitegelegt, leer neu angelegt.
        case beiseitegelegt(String)
        /// Der Behälter ließ sich nicht schreiben — der Vorrat bleibt Klartext.
        case klartextGeblieben(String)
        /// Liegt da, ließ sich aber nicht lesen (Rechte, Datenträger): offen mit dem, was da ist.
        case unlesbar(String)
    }

    /// Nach dem Entsperren: den Behälter unter dem Datenschlüssel öffnen. Ohne
    /// Behälter wandert der Klartext-Vorrat der Einstellungen hinein (der
    /// erste Start dieser Fassung); ein beschädigter oder fremd versiegelter
    /// wird beiseitegelegt (`lesezeichen-beschaedigt-<Stempel>.json`) und leer
    /// neu angelegt — nie still: Der Befund geht an den Nutzer.
    func oeffnen(mit tresor: Tresor, stempel: String) -> Oeffnungsbefund {
        self.tresor = tresor
        switch ablage.lesezeichenLesen() {
        case .keine:
            return versiegeln()
        case .unlesbar(let fehler):
            quelle = .behaelter
            return .unlesbar(fehler.localizedDescription)
        case .daten(let roh):
            do {
                guard roh.count <= Ordnerzugriff.hoechstgroesse else {
                    throw Tresorfehler(art: .beschaedigt, text: "ungewöhnlich groß (\(roh.count / 1024 / 1024) MB)")
                }
                guard Tresor.istBehaelter(roh) else {
                    throw Tresorfehler(art: .beschaedigt, text: "kein Behälter")
                }
                let kopf = try Tresor.kopfLesen(roh)
                guard kopf.inhalt == Tresor.Inhalt.lesezeichen.rawValue else {
                    throw Tresorfehler(art: .beschaedigt, text: "Behälter mit Inhalt „\(kopf.inhalt)“")
                }
                guard tresor.passt(zu: kopf) else {
                    throw Tresorfehler(art: .falscherSchluessel, text: "unter einem anderen Schlüssel versiegelt")
                }
                let gelesen = try Ordnerzugriff.nutzlastLesen(try tresor.oeffnen(kopf: kopf))
                // Der Behälter gilt. Tragen die Einstellungen noch etwas (ein
                // liegengebliebener Übergang), kommt es dazu und wird versiegelt.
                let nachzutragen = !eintraege.isEmpty || !gemerkterZielordner.isEmpty
                eintraege.merge(gelesen.eintraege) { _, behaelter in behaelter }
                if !gelesen.zielordner.isEmpty { gemerkterZielordner = gelesen.zielordner }
                quelle = .behaelter
                if nachzutragen {
                    if let grund = behaelterSchreiben() {
                        beiStoerung("Die Lesezeichen ließen sich nicht versiegelt sichern (\(grund)) — sie gelten "
                                    + "für diese Sitzung; der nächste Start fragt nach den Ordnern.")
                    } else {
                        einstellungenLeeren()
                    }
                }
                return .geoeffnet(eintraege.count)
            } catch {
                let grund = (error as? Tresorfehler)?.text ?? error.localizedDescription
                ablage.lesezeichenBeiseitelegen(stempel: stempel)
                if case .klartextGeblieben(let schreibgrund) = versiegeln() {
                    return .klartextGeblieben(grund + "; neu anlegen: " + schreibgrund)
                }
                return .beiseitegelegt(grund)
            }
        }
    }

    /// Den Vorrat, wie er im Speicher liegt, unter `tresor` versiegeln:
    /// Gelingt es, sind die Einstellungen leer; sonst bleibt der Klartext, und
    /// der Befund sagt es.
    private func versiegeln() -> Oeffnungsbefund {
        quelle = .behaelter
        if let grund = behaelterSchreiben() {
            quelle = .einstellungen
            tresor = nil
            return .klartextGeblieben(grund)
        }
        einstellungenLeeren()
        return .angelegt(eintraege.count, zielordner: !gemerkterZielordner.isEmpty)
    }

    /// Einschalten und Erneuern: den Vorrat unter `neu` versiegeln — aus den
    /// Einstellungen in den Behälter, oder den Behälter unter den neuen
    /// Schlüssel. Zurückgelesen; misslingt es, bleibt alles, wie es war, und
    /// der Grund kommt zurück.
    func versiegeln(unter neu: Tresor) -> String? {
        guard quelle != .zu else { return "noch nicht entsperrt" }
        let (alteQuelle, alterTresor) = (quelle, tresor)
        tresor = neu
        quelle = .behaelter
        if let grund = behaelterSchreiben() {
            tresor = alterTresor
            quelle = alteQuelle
            return grund
        }
        if alteQuelle == .einstellungen { einstellungenLeeren() }
        return nil
    }

    /// Die Hülle hat gewechselt (Wicklung dieses Macs angelegt oder entfernt):
    /// Der Behälter trägt dieselben Wicklungen wie die Ablage, also neu schreiben.
    func neuVersiegeln() {
        guard quelle == .behaelter else { return }
        ablegen()
    }

    /// Aufheben: der Vorrat zurück in die Einstellungen, der Behälter weg.
    func entsiegeln() {
        guard quelle == .behaelter else { return }
        quelle = .einstellungen
        tresor = nil
        einstellungenSchreiben()
        ablage.lesezeichenEntfernen()
    }

    // ── Pfade ─────────────────────────────────────────────────────────────

    /// Die Form, in der ein Pfad als Schlüssel dient und verglichen wird:
    /// ohne `..`, ohne Endschrägstrich, Symlinks aufgelöst, soweit erreichbar.
    static func kanonisch(_ pfad: String) -> String { Ablage.vergleichbar(pfad) }

    private static func liegtUnter(_ pfad: String, _ ordner: String) -> Bool {
        pfad == ordner || pfad.hasPrefix(ordner + "/")
    }

    /// Das Lesezeichen, das für den Pfad gilt: genau dieser Ort oder der
    /// nächstliegende Ordner darüber. `nil` heißt: noch nie gewählt — oder
    /// der Vorrat ist noch zu.
    func zustaendig(fuer pfad: String) -> String? {
        guard quelle != .zu else { return nil }
        let gesucht = Ordnerzugriff.kanonisch(pfad)
        var bester: String?
        for eintrag in eintraege.keys where Ordnerzugriff.liegtUnter(gesucht, eintrag) {
            if bester.map({ eintrag.count > $0.count }) ?? true { bester = eintrag }
        }
        return bester
    }

    /// Kommt die App an den Ort heran — über ein Lesezeichen, ohne Sandbox
    /// ohnehin, oder weil er ihr offensteht (Container, Systemordner)?
    func erreichbar(_ pfad: String) -> Bool {
        guard Ordnerzugriff.imSandbox else { return true }
        if zustaendig(fuer: pfad) != nil { return true }
        return FileManager.default.isReadableFile(atPath: pfad)
    }

    var alle: [String] { quelle == .zu ? [] : eintraege.keys.sorted() }

    // ── Anlegen und Vergessen ─────────────────────────────────────────────

    private static var erzeugen: URL.BookmarkCreationOptions {
        imSandbox ? [.withSecurityScope] : []
    }

    private static var lesen: URL.BookmarkResolutionOptions {
        imSandbox ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting]
    }

    /// Aus einer Wahl des Nutzers ein Lesezeichen anlegen. Liefert den
    /// Schlüssel. Wirft, wenn der Ort der App nicht offensteht — dann war es
    /// keine Wahl, sondern ein eingesetzter Pfad — oder der Vorrat noch zu ist.
    @discardableResult
    func merken(_ url: URL) throws -> String {
        let ziel = url.standardizedFileURL
        guard quelle != .zu else { throw Fehler(.versiegelt, pfad: ziel.path) }
        let daten: Data
        do {
            daten = try ziel.bookmarkData(options: Ordnerzugriff.erzeugen, includingResourceValuesForKeys: nil,
                                          relativeTo: nil)
        } catch {
            throw Fehler(.keinZugriff, pfad: ziel.path, grund: error.localizedDescription)
        }
        let eintrag = Ordnerzugriff.kanonisch(ziel.path)
        eintraege[eintrag] = daten
        ablegen()
        return eintrag
    }

    func vergessen(_ pfad: String) {
        guard quelle != .zu else { return }
        guard eintraege.removeValue(forKey: Ordnerzugriff.kanonisch(pfad)) != nil else { return }
        ablegen()
    }

    // ── Auflösen und Arbeiten ─────────────────────────────────────────────

    /// Das Lesezeichen zum Pfad und sein aufgelöstes Ziel — ein umbenannter
    /// oder verschobener Ordner wird still nachgeführt (`bookmarkDataIsStale`).
    /// Geliefert wird der Schlüssel, der gepasst hat: An ihm wird der Rest des
    /// Pfades abgetrennt, auch wenn das Ziel inzwischen anders heißt.
    private func finden(_ pfad: String) throws -> (eintrag: String, ziel: URL) {
        guard quelle != .zu else { throw Fehler(.versiegelt, pfad: pfad) }
        guard let eintrag = zustaendig(fuer: pfad), let daten = eintraege[eintrag] else {
            throw Fehler(.keinLesezeichen, pfad: pfad)
        }
        var veraltet = false
        let ziel: URL
        do {
            ziel = try URL(resolvingBookmarkData: daten, options: Ordnerzugriff.lesen, relativeTo: nil,
                           bookmarkDataIsStale: &veraltet)
        } catch {
            throw Fehler(.unaufloesbar, pfad: pfad, grund: error.localizedDescription)
        }
        if veraltet { erneuern(eintrag, ziel: ziel) }
        return (eintrag, ziel)
    }

    /// Ein veraltetes Lesezeichen neu anlegen — im Bereich des alten, denn
    /// ohne ihn stünde der Ort im Sandbox nicht offen. Der neue Ort bekommt
    /// seinen Schlüssel, der alte bleibt als Zweitname stehen: Die
    /// Planungsdatei kennt weiterhin den alten Pfad. Misslingt es, bleibt das
    /// alte Lesezeichen; es löst weiterhin auf.
    private func erneuern(_ eintrag: String, ziel: URL) {
        let offen = ziel.startAccessingSecurityScopedResource()
        defer { if offen { ziel.stopAccessingSecurityScopedResource() } }
        guard let neu = try? ziel.bookmarkData(options: Ordnerzugriff.erzeugen, includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        else { return }
        eintraege[eintrag] = neu
        eintraege[Ordnerzugriff.kanonisch(ziel.path)] = neu
        ablegen()
    }

    /// Der Pfad, wie er heute gilt: Zeigt das Lesezeichen inzwischen woanders
    /// hin, wandert der Rest des Pfades mit.
    private static func verlegt(_ pfad: String, eintrag: String, ziel: URL) -> URL {
        let gesucht = kanonisch(pfad)
        let rest = String(gesucht.dropFirst(eintrag.count))
        return URL(fileURLWithPath: kanonisch(ziel.path) + rest)
    }

    /// Wo der Pfad heute liegt — über sein Lesezeichen. Ohne Lesezeichen ein
    /// benannter Fehler.
    func aufloesen(_ pfad: String) throws -> URL {
        let (eintrag, ziel) = try finden(pfad)
        return Ordnerzugriff.verlegt(pfad, eintrag: eintrag, ziel: ziel)
    }

    /// Die Arbeit im Sicherheitsbereich des zuständigen Lesezeichens — nur
    /// für genau diese Arbeit, nie über ein `await` hinweg, danach wieder
    /// geschlossen. Die Arbeit bekommt den nachgeführten Pfad.
    func mit<T>(_ pfad: String, _ arbeit: (URL) throws -> T) throws -> T {
        let (eintrag, ziel) = try finden(pfad)
        let offen = ziel.startAccessingSecurityScopedResource()
        defer { if offen { ziel.stopAccessingSecurityScopedResource() } }
        if Ordnerzugriff.imSandbox, !offen { throw Fehler(.keinZugriff, pfad: pfad) }
        return try arbeit(Ordnerzugriff.verlegt(pfad, eintrag: eintrag, ziel: ziel))
    }
}
