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
/// `planung.json`, versiegelt unter dem Datenschlüssel. Bis zum Entsperren ist
/// der Vorrat **zu**, nicht leer. Im versiegelten Zustand geht kein Pfad in
/// die Einstellungen — außer beim Aufheben, vor der Marke des Übergangs
/// (`entsiegelnVorbereiten`, E47): Lässt sich der Behälter nicht schreiben,
/// gilt der Vorrat für die Sitzung, `ungesichert` nennt den Grund, und der
/// nächste Schreibanlass versucht es erneut. Ein Behälter, der nicht zu lesen ist, wird nicht
/// angefasst — der Vorrat ist dann **gesperrt**, bis der nächste Start ihn liest.
///
/// Ohne Sandbox (das Prüfziel von `swift test`, ein ungesiegelter Bau) läuft
/// derselbe Code mit gewöhnlichen Lesezeichen: `mit` legt keinen
/// Sicherheitsbereich, und der Zugriff gelingt ohnehin.
///
/// Einer je Sicherungsdienst, an dessen Ablage — keinen prozessweiten. Den
/// Klartext-Vorrat hält `Einstellungen.speicher` (`Einstellungsspeicher`);
/// Prüfungen reichen eine Attrappe herein.
@MainActor
@Observable
final class Ordnerzugriff {

    /// Läuft die App im App Sandbox? Dann gilt: kein Zugriff ohne Wahl.
    static var imSandbox: Bool { Ablage.container != nil }

    /// Ein benannter Fehler — die Oberfläche macht daraus „erneut wählen“,
    /// nie ein stilles Scheitern.
    struct Fehler: Error, Equatable, Sendable {
        enum Art: Sendable { case keinLesezeichen, unaufloesbar, keinZugriff, versiegelt, gesperrt }
        let art: Art
        let pfad: String
        let text: String

        init(_ art: Art, pfad: String, grund: String = "") {
            self.art = art
            self.pfad = pfad
            let name = Pfade.dateiName(pfad)
            let dazu = grund.isEmpty ? "" : " (\(grund))"
            switch art {
            case .keinLesezeichen:
                text = "Auf „\(name)“ darf die App noch nicht zugreifen — der Ort wurde ihr "
                    + "in dieser Fassung noch nicht gezeigt."
            case .unaufloesbar:
                text = "„\(name)“ ließ sich nicht wiederfinden\(dazu)."
            case .keinZugriff:
                text = "Der Zugriff auf „\(name)“ wurde nicht gewährt\(dazu) — bitte den Ort erneut wählen."
            case .versiegelt:
                text = "Die Lesezeichen sind noch versiegelt — bitte zuerst die Planung entsperren."
            case .gesperrt:
                text = "Die Lesezeichen sind gerade nicht verfügbar\(dazu) — die App liest sie beim "
                    + "nächsten Start erneut."
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
        /// Der Behälter liegt, wird aber nicht angefasst: unlesbar, aus einer
        /// neueren Fassung, oder nicht beiseitezulegen. Nichts gilt, nichts
        /// wird geschrieben — bis der nächste Start ihn liest.
        case gesperrt(String)
    }

    private(set) var quelle: Quelle = .einstellungen

    /// Der Behälter trägt nicht den Stand der Sitzung — der Grund; `nil`
    /// heißt gesichert. Die Oberfläche zeigt es, solange es gilt.
    private(set) var ungesichert: String?

    @ObservationIgnored private let ablage: Ablage
    @ObservationIgnored private var tresor: Tresor?

    /// Wo der Klartext-Vorrat liegt — `nil` im Prüflauf: Der lässt die
    /// Einstellungen des Nutzers unangetastet.
    @ObservationIgnored private let einstellungen: (any Einstellungsspeicher)?

    /// Die Einstellungen tragen noch Klartext, der in den Behälter gehört —
    /// geleert wird erst, wenn der Behälter ihn nachweislich trägt.
    @ObservationIgnored private var einstellungenNachzutragen = false

    /// Schlüssel = kanonischer Pfad. Zu heißt: liegt im Speicher, gilt nicht.
    private(set) var eintraege: [String: Data]

    /// Der Zielordner der Kopie, wie er gemerkt ist — auch hinter „zu“.
    private var gemerkterZielordner: String

    /// Die Meldungssenke des Speichers — ein Schreibfehler des Behälters,
    /// einmal je Störung.
    @ObservationIgnored var melden: @MainActor (String, Meldung.Art) -> Void = { _, _ in }

    init(ablage: Ablage, einstellungen: (any Einstellungsspeicher)? = Einstellungen.speicher) {
        self.ablage = ablage
        self.einstellungen = einstellungen
        guard let einstellungen else {
            eintraege = [:]
            gemerkterZielordner = ""
            return
        }
        eintraege = einstellungen.dictionary(forKey: Ordnerzugriff.schluessel) as? [String: Data] ?? [:]
        gemerkterZielordner = einstellungen.string(forKey: Einstellungen.Schluessel.autoexportOrdner) ?? ""
        einstellungenNachzutragen = !eintraege.isEmpty || !gemerkterZielordner.isEmpty
    }

    /// Für Prüfungen: Ein Prüflauf hat keinen Einstellungsspeicher.
    var hatEinstellungsspeicher: Bool { einstellungen != nil }

    /// Offen für Lesen und Schreiben — Einstellungen oder Behälter.
    var schreibbar: Bool {
        switch quelle {
        case .einstellungen, .behaelter: true
        case .zu, .gesperrt: false
        }
    }

    var sperrgrund: String? {
        if case .gesperrt(let grund) = quelle { grund } else { nil }
    }

    /// Leer heißt: noch keiner gewählt — oder noch zu.
    var zielordner: String {
        get { schreibbar ? gemerkterZielordner : "" }
        set {
            guard schreibbar, newValue != gemerkterZielordner else { return }
            gemerkterZielordner = newValue
            ablegen()
        }
    }

    // ── Ablegen: Einstellungen oder Behälter ─────────────────────────────

    private func ablegen() {
        switch quelle {
        case .einstellungen:
            einstellungenSchreiben()
        case .zu, .gesperrt:
            break
        case .behaelter:
            if let grund = behaelterSchreiben().grund {
                if ungesichert == nil {
                    melden("Die Lesezeichen ließen sich nicht versiegelt sichern (\(grund)) — sie gelten "
                           + "für diese Sitzung; die App versucht es beim nächsten Schreiben und beim "
                           + "nächsten Start erneut.", .warnung)
                }
                ungesichert = grund
            } else {
                ungesichert = nil
                if einstellungenNachzutragen { einstellungenLeeren() }
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
        einstellungenNachzutragen = false
        guard let einstellungen else { return }
        einstellungen.removeObject(forKey: Ordnerzugriff.schluessel)
        einstellungen.removeObject(forKey: Einstellungen.Schluessel.autoexportOrdner)
    }

    // ── Der Behälter ──────────────────────────────────────────────────────

    /// Obergrenze beim Lesen — ein Lesezeichen hat rund ein Kilobyte.
    static let hoechstgroesse = Statusdatei.hoechstgroesse

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
              JSONWert.ganzzahl(aus: objekt["version"]) == nutzlastfassung,
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

    /// Der eine Weg vom rohen Behälter zur Nutzlast — beim Öffnen und beim
    /// Zurücklesen nach dem Schreiben derselbe: Inhalt, Schlüssel, Nutzlast.
    private static func nutzlastAus(_ roh: Data, tresor: Tresor)
        throws -> (eintraege: [String: Data], zielordner: String, huelleVeraltet: Bool) {
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
        let nutzlast = try nutzlastLesen(try tresor.oeffnen(kopf: kopf))
        // Derselbe Schlüssel, aber eine ältere Hülle (Passphrase geändert, Wicklung
        // dieses Macs): Der Aufrufer schreibt dann neu (B09).
        return (nutzlast.eintraege, nutzlast.zielordner, !tresor.huelleGleich(kopf, ziel: .ablage))
    }

    /// Was das Schreiben des Behälters ergab — mit dem Unterschied, ob schon
    /// etwas auf der Platte liegt.
    enum Schreibbefund: Equatable {
        case gelungen
        /// Nichts liegt neu auf der Platte.
        case nichtGeschrieben(String)
        /// Atomar abgelegt, aber nicht bestätigt: Die Platte trägt womöglich
        /// diesen Stand — oder einen anderen.
        case ungeprueft(String)

        var grund: String? {
            switch self {
            case .gelungen: nil
            case .nichtGeschrieben(let grund), .ungeprueft(let grund): grund
            }
        }
    }

    /// Den Behälter im Speicher bauen und prüfen: Die Nutzlast muss sich
    /// lesen lassen und der Behälter unter der Grenze bleiben, die das Öffnen
    /// anlegt — sonst schriebe die App etwas hin, das ihr nächster Start
    /// beiseitelegt. Derselbe Weg für das Schreiben und für die Generation
    /// eines Übergangs.
    private func behaelterBauen(unter tresor: Tresor) throws -> Data {
        let klartext = try Ordnerzugriff.nutzlast(eintraege: eintraege, zielordner: gemerkterZielordner)
        let gedeutet = try Ordnerzugriff.nutzlastLesen(klartext)
        guard gedeutet.eintraege == eintraege, gedeutet.zielordner == gemerkterZielordner else {
            throw Uebergangsfehler(text: "die Nutzlast liest sich anders, als sie geschrieben wurde")
        }
        let behaelter = try tresor.versiegeln(klartext, inhalt: .lesezeichen, ziel: .ablage)
        guard behaelter.count <= Ordnerzugriff.hoechstgroesse else {
            throw Uebergangsfehler(text: "der Behälter wäre mit \(behaelter.count / 1024 / 1024) MB größer als die Lesegrenze")
        }
        return behaelter
    }

    /// Bauen, atomar ablegen, über denselben Weg wie das Öffnen zurücklesen
    /// und vergleichen.
    private func behaelterSchreiben() -> Schreibbefund {
        guard let tresor else { return .nichtGeschrieben("kein Schlüssel") }
        var abgelegt = false
        do {
            let behaelter = try behaelterBauen(unter: tresor)
            try ablage.lesezeichenSchreiben(behaelter)
            abgelegt = true
            guard case .daten(let roh) = ablage.lesezeichenLesen(hoechstens: Ordnerzugriff.hoechstgroesse) else {
                return .ungeprueft("nicht zurücklesbar")
            }
            let gelesen = try Ordnerzugriff.nutzlastAus(roh, tresor: tresor)
            guard gelesen.eintraege == eintraege, gelesen.zielordner == gemerkterZielordner else {
                return .ungeprueft("die Platte trägt einen anderen Stand")
            }
            return .gelungen
        } catch {
            return abgelegt ? .ungeprueft(error.localizedDescription) : .nichtGeschrieben(error.localizedDescription)
        }
    }

    // ── Übergänge ─────────────────────────────────────────────────────────

    /// Die Ablage liegt versiegelt, der Schlüssel ist noch zu: Der Vorrat
    /// schließt sich. Was aus den Einstellungen kam, bleibt für das Entsperren
    /// im Speicher — zu sehen ist nichts.
    func schliessen() {
        quelle = .zu
        tresor = nil
        ungesichert = nil
    }

    /// Was das Öffnen nach dem Entsperren ergab.
    enum Oeffnungsbefund: Equatable, Sendable {
        /// Der Behälter lag und ist offen — so viele Lesezeichen. Trug er
        /// noch eine ältere Hülle (aus einer früheren Fassung), ist er still
        /// neu versiegelt.
        case geoeffnet(Int)
        /// Kein Behälter: Der Vorrat aus den Einstellungen ist jetzt versiegelt.
        case angelegt(Int, zielordner: Bool)
        /// Beschädigt oder unter fremdem Schlüssel: beiseitegelegt unter
        /// `rettung`; der Vorrat aus Sitzung und Einstellungen ist neu versiegelt.
        case beiseitegelegt(String, rettung: String, versiegelt: Int)
        /// Der Behälter ließ sich nicht schreiben — der Vorrat gilt für die
        /// Sitzung, die App versucht es beim nächsten Anlass erneut.
        case ungesichert(String)
        /// Der Behälter liegt und bleibt unangetastet; der Vorrat ist gesperrt.
        case gesperrt(String)
    }

    /// Nach dem Entsperren: den Behälter unter dem Datenschlüssel öffnen. Ohne
    /// Behälter wandert der Klartext-Vorrat der Einstellungen hinein (der
    /// erste Start dieser Fassung); ein beschädigter oder fremd versiegelter
    /// wird beiseitegelegt; einer, der sich nicht lesen lässt oder aus einer
    /// neueren Fassung stammt, bleibt liegen — nie still: Der Befund geht an
    /// den Nutzer. Eine ältere Hülle (aus einer Fassung vor dem Übergabestand)
    /// wird still neu versiegelt.
    func oeffnen(mit tresor: Tresor, stempel: String) -> Oeffnungsbefund {
        self.tresor = tresor
        ungesichert = nil
        let roh: Data
        switch ablage.lesezeichenLesen(hoechstens: Ordnerzugriff.hoechstgroesse) {
        case .keine:
            return versiegeln()
        case .unlesbar(let fehler):
            return sperren(fehler.localizedDescription)
        case .zuGross(let groesse):
            // Ein Lesezeichen hat rund ein Kilobyte — das hat diese App nicht geschrieben.
            return beiseitelegen(grund: "ungewöhnlich groß (\(groesse / 1024 / 1024) MB)",
                                 fremd: false, stempel: stempel)
        case .daten(let daten):
            roh = daten
        }
        do {
            let gelesen = try Ordnerzugriff.nutzlastAus(roh, tresor: tresor)
            eintraege.merge(gelesen.eintraege) { _, behaelter in behaelter }
            // Die spätere Wahl gewinnt: Tragen die Einstellungen einen
            // Zielordner, ist er nach dem Behälter gewählt worden.
            if gemerkterZielordner.isEmpty { gemerkterZielordner = gelesen.zielordner }
            quelle = .behaelter
            if einstellungenNachzutragen || gelesen.huelleVeraltet { ablegen() }
            return .geoeffnet(eintraege.count)
        } catch let fehler as Tresorfehler where fehler.art == .neuereFassung {
            return sperren(fehler.text)
        } catch {
            return beiseitelegen(grund: error.localizedDescription,
                                 fremd: (error as? Tresorfehler)?.art == .falscherSchluessel,
                                 stempel: stempel)
        }
    }

    /// Den Behälter als Rettungskopie beiseitelegen und den Vorrat aus
    /// Sitzung und Einstellungen neu versiegeln.
    private func beiseitelegen(grund: String, fremd: Bool, stempel: String) -> Oeffnungsbefund {
        guard let rettung = ablage.lesezeichenBeiseitelegen(stempel: stempel, fremd: fremd) else {
            return sperren(grund + "; die Rettungskopie ließ sich nicht anlegen")
        }
        if case .ungesichert(let schreibgrund) = versiegeln() {
            return .ungesichert(grund + "; neu anlegen: " + schreibgrund)
        }
        return .beiseitegelegt(grund, rettung: rettung, versiegelt: eintraege.count)
    }

    private func sperren(_ grund: String) -> Oeffnungsbefund {
        quelle = .gesperrt(grund)
        tresor = nil
        return .gesperrt(grund)
    }

    /// Den Vorrat, wie er im Speicher liegt, unter `tresor` versiegeln.
    /// Gelingt es, sind die Einstellungen leer; sonst bleibt der Vorrat für
    /// die Sitzung, und der nächste Anlass versucht es erneut.
    private func versiegeln() -> Oeffnungsbefund {
        quelle = .behaelter
        if let grund = behaelterSchreiben().grund {
            ungesichert = grund
            return .ungesichert(grund)
        }
        ungesichert = nil
        einstellungenLeeren()
        return .angelegt(eintraege.count, zielordner: !gemerkterZielordner.isEmpty)
    }

    // ── Der Übergang des Schutzes (E47): Inhalt liefern, dann umschalten ──
    // Geschrieben wird im Übergang nichts hier: Der Übergangsdienst legt den
    // Behälter als Zwilling daneben und setzt ihn nach der Marke ein.

    /// Der Vorrat als Behälter unter `neu`, im Speicher gebaut und geprüft.
    /// Wirft, wenn der Vorrat zu ist oder gesperrt — seine Datei gehört dann
    /// nicht in die Generation.
    func behaelter(unter neu: Tresor) throws -> Data {
        guard schreibbar else {
            throw Uebergangsfehler(text: quelle == .zu ? "noch nicht entsperrt" : (sperrgrund ?? "gesperrt"))
        }
        return try behaelterBauen(unter: neu)
    }

    /// Aufheben, vorbereitet: Der Vorrat geht in die Einstellungen, seine
    /// Klartext-Heimat, solange der Behälter noch gilt. Endet der Prozess vor
    /// der Marke, nimmt der nächste Start ihn beim Entsperren wieder in den
    /// Behälter (wie beim ersten Start dieser Fassung); `entsiegelnVerwerfen`
    /// leert sie sofort. Ohne offenen Behälter nichts zu tun.
    func entsiegelnVorbereiten() {
        guard quelle == .behaelter else { return }
        einstellungenSchreiben()
    }

    /// Das Aufheben findet nicht statt: die Einstellungen wieder leer.
    func entsiegelnVerwerfen() {
        guard quelle == .behaelter else { return }
        einstellungenLeeren()
    }

    /// Nach dem Einsetzen der Generation: Die Platte trägt den Vorrat unter
    /// `neu` — oder beim Aufheben (`nil`) keinen Behälter mehr —, Quelle und
    /// Schlüssel der Sitzung folgen. Nichts wird geschrieben. Ein zuer Vorrat
    /// bleibt zu; ein gesperrter bleibt gesperrt, bis das Aufheben ihn in die
    /// Einstellungen entlässt: Sein Behälter trägt nur Chiffrat unter einem
    /// Schlüssel, den es nicht mehr gibt.
    func umschalten(auf neu: Tresor?) {
        if let neu {
            guard schreibbar else { return }
            tresor = neu
            quelle = .behaelter
            ungesichert = nil
            einstellungenLeeren()
            return
        }
        guard schreibbar || sperrgrund != nil else { return }
        tresor = nil
        quelle = .einstellungen
        ungesichert = nil
        einstellungenNachzutragen = false
        einstellungenSchreiben()
    }

    // ── Pfade ─────────────────────────────────────────────────────────────

    /// Die Form, in der ein Pfad als Schlüssel dient und verglichen wird: ohne
    /// `.` und `..`, ohne Endschrägstrich, ohne das `/private` vor /var, /tmp
    /// und /etc — **rein lexikalisch, ohne Symlinks aufzulösen**: Das Auflösen
    /// braucht Zugriff auf den Weg dorthin, und ein Schlüssel, der beim Merken
    /// (mit Zugriff) anders ausfiele als beim nächsten Start (ohne), fände sein
    /// Lesezeichen nicht wieder. Ein Ort hinter einem Symlink wird unter dem
    /// Namen gemerkt, unter dem er gewählt wurde. Kein Dateisystemzugriff —
    /// auch in einer Schleife über viele Pfade nicht.
    static func kanonisch(_ pfad: String) -> String {
        var teile: [Substring] = []
        for teil in pfad.split(separator: "/", omittingEmptySubsequences: true) {
            switch teil {
            case ".": continue
            case "..": if !teile.isEmpty { teile.removeLast() }
            default: teile.append(teil)
            }
        }
        if teile.count >= 2, teile[0] == "private", ["var", "tmp", "etc"].contains(teile[1]) {
            teile.removeFirst()
        }
        return "/" + teile.joined(separator: "/")
    }

    /// Wie die App an einen Ort kommt — die eine Frage der Nachwahl, statt
    /// vier Lagen (Quelle, Vorrat, Lesezeichen, Zustand) am Aufrufer zu mischen.
    enum Zugang: Equatable, Sendable {
        /// Ein Lesezeichen deckt den Ort — sein Schlüssel.
        case offen(String)
        /// Der Vorrat steht offen und kennt den Ort nicht: nie gewählt oder vergessen.
        case nieGewaehlt
        /// Der Vorrat ist noch zu (versiegelt, nicht entsperrt) — bis dahin keine Frage.
        case nochZu
        /// Der Vorrat ist gesperrt (Behälter unangetastet) — bis zum nächsten Start.
        case gesperrt(String)
    }

    func zugang(fuer pfad: String) -> Zugang {
        switch quelle {
        case .zu: .nochZu
        case .gesperrt(let grund): .gesperrt(grund)
        case .einstellungen, .behaelter:
            zustaendig(kanonisch: Ordnerzugriff.kanonisch(pfad)).map(Zugang.offen) ?? .nieGewaehlt
        }
    }

    private static func liegtUnter(_ pfad: String, _ ordner: String) -> Bool {
        pfad == ordner || pfad.hasPrefix(ordner + "/")
    }

    /// Das Lesezeichen, das für den Pfad gilt: genau dieser Ort oder der
    /// nächstliegende Ordner darüber. `nil` heißt: noch nie gewählt — oder
    /// der Vorrat ist zu oder gesperrt.
    func zustaendig(fuer pfad: String) -> String? {
        guard schreibbar else { return nil }
        return zustaendig(kanonisch: Ordnerzugriff.kanonisch(pfad))
    }

    private func zustaendig(kanonisch gesucht: String) -> String? {
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

    var alle: [String] { schreibbar ? eintraege.keys.sorted() : [] }

    // ── Anlegen und Vergessen ─────────────────────────────────────────────

    private static var erzeugen: URL.BookmarkCreationOptions {
        imSandbox ? [.withSecurityScope] : []
    }

    private static var lesen: URL.BookmarkResolutionOptions {
        imSandbox ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting]
    }

    private func schreibsperre(_ pfad: String) -> Fehler? {
        switch quelle {
        case .einstellungen, .behaelter: nil
        case .zu: Fehler(.versiegelt, pfad: pfad)
        case .gesperrt(let grund): Fehler(.gesperrt, pfad: pfad, grund: grund)
        }
    }

    /// Aus einer Wahl des Nutzers ein Lesezeichen anlegen. Liefert den
    /// Schlüssel. Wirft, wenn der Ort der App nicht offensteht — dann war es
    /// keine Wahl, sondern ein eingesetzter Pfad — oder der Vorrat zu ist.
    @discardableResult
    func merken(_ url: URL) throws -> String {
        let ziel = url.standardizedFileURL
        if let sperre = schreibsperre(ziel.path) { throw sperre }
        let eintrag = try eintragen(ziel)
        ablegen()
        return eintrag
    }

    /// Mehrere Orte aus einer Wahl — ein Schreibvorgang des Behälters statt
    /// einem je Datei. Was sich nicht merken lässt, fehlt in der Rückgabe.
    @discardableResult
    func merken(alle urls: [URL]) -> [String] {
        guard schreibbar else { return [] }
        let neu = urls.compactMap { try? eintragen($0.standardizedFileURL) }
        if !neu.isEmpty { ablegen() }
        return neu
    }

    private func eintragen(_ ziel: URL) throws -> String {
        let daten: Data
        do {
            daten = try ziel.bookmarkData(options: Ordnerzugriff.erzeugen, includingResourceValuesForKeys: nil,
                                          relativeTo: nil)
        } catch {
            throw Fehler(.keinZugriff, pfad: ziel.path, grund: error.localizedDescription)
        }
        let eintrag = Ordnerzugriff.kanonisch(ziel.path)
        eintraege[eintrag] = daten
        return eintrag
    }

    func vergessen(_ pfad: String) {
        guard schreibbar, eintraege.removeValue(forKey: Ordnerzugriff.kanonisch(pfad)) != nil else { return }
        ablegen()
    }

    // ── Auflösen und Arbeiten ─────────────────────────────────────────────

    /// Das Lesezeichen zum Pfad und sein aufgelöstes Ziel — ein umbenannter
    /// oder verschobener Ordner wird still nachgeführt (`bookmarkDataIsStale`).
    /// Geliefert wird der Schlüssel, der gepasst hat: An ihm wird der Rest des
    /// Pfades abgetrennt, auch wenn das Ziel inzwischen anders heißt.
    private func finden(_ gesucht: String) throws -> (eintrag: String, ziel: URL) {
        if let sperre = schreibsperre(gesucht) { throw sperre }
        guard let eintrag = zustaendig(kanonisch: gesucht), let daten = eintraege[eintrag] else {
            throw Fehler(.keinLesezeichen, pfad: gesucht)
        }
        var veraltet = false
        let ziel: URL
        do {
            ziel = try URL(resolvingBookmarkData: daten, options: Ordnerzugriff.lesen, relativeTo: nil,
                           bookmarkDataIsStale: &veraltet)
        } catch {
            throw Fehler(.unaufloesbar, pfad: gesucht, grund: error.localizedDescription)
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
    /// hin, wandert der Rest des Pfades mit. Der Pfad kommt kanonisch herein.
    private static func verlegt(_ gesucht: String, eintrag: String, ziel: URL) -> URL {
        URL(fileURLWithPath: kanonisch(ziel.path) + gesucht.dropFirst(eintrag.count))
    }

    /// Wo der Pfad heute liegt — über sein Lesezeichen. Ohne Lesezeichen ein
    /// benannter Fehler.
    func aufloesen(_ pfad: String) throws -> URL {
        let gesucht = Ordnerzugriff.kanonisch(pfad)
        let (eintrag, ziel) = try finden(gesucht)
        return Ordnerzugriff.verlegt(gesucht, eintrag: eintrag, ziel: ziel)
    }

    /// Die Arbeit im Sicherheitsbereich des zuständigen Lesezeichens — nur
    /// für genau diese Arbeit, nie über ein `await` hinweg, danach wieder
    /// geschlossen. Die Arbeit bekommt den nachgeführten Pfad.
    func mit<T>(_ pfad: String, _ arbeit: (URL) throws -> T) throws -> T {
        let gesucht = Ordnerzugriff.kanonisch(pfad)
        let (eintrag, ziel) = try finden(gesucht)
        let offen = ziel.startAccessingSecurityScopedResource()
        defer { if offen { ziel.stopAccessingSecurityScopedResource() } }
        if Ordnerzugriff.imSandbox, !offen { throw Fehler(.keinZugriff, pfad: pfad) }
        return try arbeit(Ordnerzugriff.verlegt(gesucht, eintrag: eintrag, ziel: ziel))
    }
}
