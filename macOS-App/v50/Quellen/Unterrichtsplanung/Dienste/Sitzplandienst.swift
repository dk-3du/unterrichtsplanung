// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Die Sitzpläne der Klassen — in `sitzplaene.json` neben der Planung, und
/// **unter demselben Schutz** (E22): Klartext, solange die Planung Klartext
/// ist; versiegelt unter dem Datenschlüssel, sobald sie es ist; entsiegelt,
/// wenn die Verschlüsselung aufgehoben wird. Bis zum Entsperren sind die
/// Pläne **zu**, nicht leer.
///
/// Nach dem Muster des Ordnerzugriffs, ohne ihn umzubauen: Geschrieben wird
/// atomar und zurückgelesen; ein Behälter, der sich nicht schreiben lässt,
/// lässt die Pläne für die Sitzung gelten (`ungesichert` nennt den Grund),
/// der nächste Schreibanlass, das Sichern beim Beenden und der nächste Start
/// versuchen es erneut. Eine Datei, die nicht zu lesen ist, wird nicht
/// angefasst — die Pläne sind dann **gesperrt**, bis der nächste Start sie
/// liest. Beschädigt oder fremd versiegelt heißt: beiseitegelegt als
/// `sitzplaene-beschaedigt-`/`-fremd-<Stempel>.json`. Ein Behälter unter
/// einer älteren Hülle (Passphrase geändert, Wicklung dieses Macs) wird beim
/// Öffnen nachgezogen; was das Lesen mit Verlust bereinigt, wird gemeldet und
/// als `sitzplaene-bereinigt-<Stempel>.json` bewahrt.
///
/// Einer je Sicherungsdienst, an dessen Ablage; eine Vorschau (Prüfungen)
/// rührt die Platte nicht an.
@MainActor
@Observable
final class Sitzplandienst {

    enum Quelle: Equatable, Sendable {
        /// Die Planung liegt im Klartext — die Sitzpläne auch.
        case klartext
        /// Die Ablage liegt versiegelt, der Schlüssel ist noch zu.
        case zu
        /// Versiegelt unter dem Datenschlüssel, offen.
        case behaelter
        /// Die Datei liegt, wird aber nicht angefasst — bis der nächste Start
        /// sie liest.
        case gesperrt(String)
    }

    private(set) var quelle: Quelle = .klartext

    /// Alle Pläne je Klassen-Kennung — gilt nur, solange `schreibbar`.
    private(set) var plaene: [String: Sitzplan] = [:]

    /// Die Platte trägt nicht den Stand der Sitzung — der Grund; `nil` heißt gesichert.
    private(set) var ungesichert: String?

    /// Das Original einer verlustbehaftet gelesenen Datei ist noch nicht
    /// bewahrt: der Name der ausstehenden Kopie. Bis sie liegt, geht nichts
    /// über die Datei — jedes Schreiben versucht die Kopie zuerst (E46).
    private(set) var ausstehendeKopie: String?

    /// Klartext neben der versiegelten Planung liegt, und der Nutzer hat noch
    /// nicht gesagt, ob er versiegelt oder beiseitegelegt wird (E43 (b)). Die
    /// Pläne gelten derweil für die Sitzung; ein Schreiben versiegelt sie.
    private(set) var klartextUnbestaetigt = false

    @ObservationIgnored private let ablage: Ablage
    @ObservationIgnored private let vorschau: Bool
    @ObservationIgnored private var tresor: Tresor?

    /// Die Meldungssenke des Speichers — ein Schreibfehler, einmal je Störung.
    @ObservationIgnored var melden: @MainActor (String, Meldung.Art) -> Void = { _, _ in }

    static let hoechstgroesse = Sitzplandatei.hoechstgroesse

    init(ablage: Ablage, vorschau: Bool = false) {
        self.ablage = ablage
        self.vorschau = vorschau
    }

    var schreibbar: Bool {
        switch quelle {
        case .klartext, .behaelter: true
        case .zu, .gesperrt: false
        }
    }

    var sperrgrund: String? {
        if case .gesperrt(let grund) = quelle { grund } else { nil }
    }

    /// Warum gerade kein Sitzplan zu haben ist — für die Oberfläche.
    var sperrhinweis: String? {
        switch quelle {
        case .klartext, .behaelter: nil
        case .zu: "Die Sitzpläne sind noch versiegelt — bitte zuerst die Planung entsperren."
        case .gesperrt(let grund):
            "Die Sitzpläne sind gerade nicht verfügbar (\(grund)) — die App liest sie beim "
                + "nächsten Start erneut."
        }
    }

    var hatPlaene: Bool { schreibbar && !plaene.isEmpty }

    func plan(fuer klasseId: String) -> Sitzplan? {
        schreibbar ? plaene[klasseId] : nil
    }

    // ── Lesen ─────────────────────────────────────────────────────────────

    enum Ladebefund: Equatable, Sendable {
        /// So viele Pläne liegen und sind offen.
        case geladen(Int)
        /// Keine Datei — nichts angelegt.
        case keine
        /// Klartext neben einer versiegelten Ablage: nicht stillschweigend
        /// übernommen — der Nutzer entscheidet, versiegeln oder beiseitelegen
        /// (E43 (b)); was das Lesen dabei bereinigt hat, steht in der Bilanz.
        case klartextGefunden(Int, Sitzplandatei.Bilanz, kopie: String?)
        /// Der Behälter trug eine ältere Hülle (Passphrase geändert, Wicklung
        /// dieses Macs) und ist jetzt neu versiegelt (B09).
        case nachgezogen(Int)
        /// Gelesen, aber mit Verlust bereinigt (B14); das Original liegt als
        /// `kopie` daneben — `nil`, wenn die Kopie misslang.
        case bereinigt(Int, Sitzplandatei.Bilanz, kopie: String?)
        /// Beschädigt, fremd versiegelt oder Behälter neben einer
        /// Klartext-Planung: beiseitegelegt unter `rettung`; die Pläne sind leer.
        case beiseitegelegt(String, rettung: String)
        /// Die Datei liegt und bleibt unangetastet; die Pläne sind gesperrt.
        case gesperrt(String)
    }

    private struct Deutung {
        var plaene: [String: Sitzplan]
        var bilanz: Sitzplandatei.Bilanz
        var huelleVeraltet: Bool
    }

    /// Der eine Weg von der Platte zu den Plänen — beim Laden und beim
    /// Zurücklesen derselbe: Behälter oder Klartext, Inhalt, Schlüssel, Datei.
    private func gedeutet(_ roh: Data, tresor: Tresor?) throws -> Deutung {
        guard Tresor.istBehaelter(roh) else {
            let (plaene, bilanz) = try Sitzplandatei.lesenMitBilanz(roh)
            return Deutung(plaene: plaene, bilanz: bilanz, huelleVeraltet: false)
        }
        guard let tresor else {
            throw Tresorfehler(art: .falscherSchluessel, text: "Behälter neben einer Klartext-Planung")
        }
        let kopf = try Tresor.kopfLesen(roh)
        guard kopf.inhalt == Tresor.Inhalt.sitzplaene.rawValue else {
            throw Tresorfehler(art: .beschaedigt, text: "Behälter mit Inhalt „\(kopf.inhalt)“")
        }
        guard tresor.passt(zu: kopf) else {
            throw Tresorfehler(art: .falscherSchluessel, text: "unter einem anderen Schlüssel versiegelt")
        }
        let (plaene, bilanz) = try Sitzplandatei.lesenMitBilanz(try tresor.oeffnen(kopf: kopf))
        return Deutung(plaene: plaene, bilanz: bilanz,
                       huelleVeraltet: !tresor.huelleGleich(kopf, ziel: .ablage))
    }

    /// Beim Start neben einer Klartext-Planung (oder ohne Planung).
    func laden(stempel: String) -> Ladebefund {
        tresor = nil
        ungesichert = nil
        klartextUnbestaetigt = false
        return lesen(stempel: stempel)
    }

    /// Nach dem Entsperren: den Behälter unter dem Datenschlüssel öffnen.
    /// Klartext neben der versiegelten Ablage (ein Einschalten, das zwischen
    /// zwei Schritten abbrach) wird jetzt versiegelt; eine ältere Hülle wird
    /// nachgezogen; ein beschädigter oder fremd versiegelter Behälter wird
    /// beiseitegelegt; einer, der sich nicht lesen lässt oder aus einer
    /// neueren Fassung stammt, bleibt liegen.
    func oeffnen(mit tresor: Tresor, stempel: String) -> Ladebefund {
        self.tresor = tresor
        ungesichert = nil
        return lesen(stempel: stempel)
    }

    private func lesen(stempel: String) -> Ladebefund {
        let offen: Quelle = tresor == nil ? .klartext : .behaelter
        guard !vorschau else {
            quelle = offen
            return .keine
        }
        let roh: Data
        switch ablage.sitzplaeneLesen(hoechstens: Sitzplandienst.hoechstgroesse) {
        case .keine:
            plaene = [:]
            quelle = offen
            return .keine
        case .unlesbar(let fehler):
            return sperren(fehler.localizedDescription)
        case .zuGross(let groesse):
            return beiseitelegen(grund: "ungewöhnlich groß (\(groesse / 1024 / 1024) MB)",
                                 fremd: false, stempel: stempel)
        case .daten(let daten):
            roh = daten
        }
        do {
            let deutung = try gedeutet(roh, tresor: tresor)
            // Das Original bewahren, bevor die bereinigte Fassung beim nächsten
            // Schreiben darüber geht — gelingt das nicht, bleibt die Kopie
            // ausstehend, und nichts geht über die Datei (E46).
            var kopie: String?
            if deutung.bilanz.verlust {
                let name = "sitzplaene-bereinigt-\(stempel).json"
                kopie = ablage.sitzplaeneKopieren(als: name)
                ausstehendeKopie = kopie == nil ? name : nil
            }
            plaene = deutung.plaene
            quelle = offen
            let anzahl = plaene.count
            if tresor != nil, !Tresor.istBehaelter(roh) {
                // Klartext neben der versiegelten Ablage: nicht stillschweigend
                // übernehmen — der Nutzer entscheidet (E43 (b)).
                klartextUnbestaetigt = true
                return .klartextGefunden(anzahl, deutung.bilanz, kopie: kopie)
            }
            // Eine ältere Hülle: jetzt neu schreiben.
            if deutung.huelleVeraltet { ablegen() }
            if deutung.bilanz.verlust { return .bereinigt(anzahl, deutung.bilanz, kopie: kopie) }
            if deutung.huelleVeraltet { return ungesichert == nil ? .nachgezogen(anzahl) : .geladen(anzahl) }
            return .geladen(anzahl)
        } catch let fehler as Tresorfehler where fehler.art == .neuereFassung {
            return sperren(fehler.text)
        } catch let fehler as Sitzplandatei.Fehler where fehler.art == .neuereFassung {
            return sperren(fehler.text)
        } catch {
            return beiseitelegen(grund: (error as? Tresorfehler)?.text ?? error.localizedDescription,
                                 fremd: (error as? Tresorfehler)?.art == .falscherSchluessel,
                                 stempel: stempel)
        }
    }

    private func beiseitelegen(grund: String, fremd: Bool, stempel: String) -> Ladebefund {
        guard let rettung = ablage.sitzplaeneBeiseitelegen(stempel: stempel, fremd: fremd) else {
            return sperren(grund + "; die Rettungskopie ließ sich nicht anlegen")
        }
        plaene = [:]
        quelle = tresor == nil ? .klartext : .behaelter
        return .beiseitegelegt(grund, rettung: rettung)
    }

    private func sperren(_ grund: String) -> Ladebefund {
        plaene = [:]
        quelle = .gesperrt(grund)
        return .gesperrt(grund)
    }

    /// Die Ablage liegt versiegelt, der Schlüssel ist noch zu.
    func schliessen() {
        quelle = .zu
        tresor = nil
        ungesichert = nil
        klartextUnbestaetigt = false
        ausstehendeKopie = nil
        plaene = [:]
    }

    // ── Schreiben ─────────────────────────────────────────────────────────

    enum Schreibbefund: Equatable {
        case gelungen
        case nichtGeschrieben(String)
        /// Atomar abgelegt, aber nicht bestätigt.
        case ungeprueft(String)

        var grund: String? {
            switch self {
            case .gelungen: nil
            case .nichtGeschrieben(let grund), .ungeprueft(let grund): grund
            }
        }
    }

    /// Die Datei im Speicher bauen und prüfen, atomar ablegen, über denselben
    /// Weg wie das Lesen zurücklesen und vergleichen. Ohne Pläne liegt keine Datei.
    private func schreiben() -> Schreibbefund {
        guard !vorschau else { return .gelungen }
        if let name = ausstehendeKopie {
            // Erst das Original bewahren (E46): Liegt die Datei nicht mehr, gibt
            // es nichts zu bewahren; sonst geht ohne Kopie nichts darüber.
            if !FileManager.default.fileExists(atPath: ablage.sitzplaene.path) {
                ausstehendeKopie = nil
            } else if ablage.sitzplaeneKopieren(als: name) != nil {
                ausstehendeKopie = nil
            } else {
                return .nichtGeschrieben("das Original ist noch nicht bewahrt — die Kopie „\(name)“ ließ sich nicht anlegen")
            }
        }
        guard !plaene.isEmpty else {
            ablage.sitzplaeneEntfernen()
            return FileManager.default.fileExists(atPath: ablage.sitzplaene.path)
                ? .nichtGeschrieben("die leere Datei ließ sich nicht entfernen") : .gelungen
        }
        var abgelegt = false
        do {
            let klartext = try Sitzplandatei.schreiben(plaene)
            guard try Sitzplandatei.lesen(klartext) == plaene else {
                return .nichtGeschrieben("die Sitzpläne lesen sich anders, als sie geschrieben wurden")
            }
            let daten = try tresor.map { try $0.versiegeln(klartext, inhalt: .sitzplaene, ziel: .ablage) } ?? klartext
            guard daten.count <= Sitzplandienst.hoechstgroesse else {
                return .nichtGeschrieben("die Datei wäre mit \(daten.count / 1024) KB größer als die Lesegrenze")
            }
            try ablage.sitzplaeneSchreiben(daten)
            abgelegt = true
            guard case .daten(let roh) = ablage.sitzplaeneLesen(hoechstens: Sitzplandienst.hoechstgroesse) else {
                return .ungeprueft("nicht zurücklesbar")
            }
            guard try gedeutet(roh, tresor: tresor).plaene == plaene else {
                return .ungeprueft("die Platte trägt einen anderen Stand")
            }
            return .gelungen
        } catch {
            let grund = (error as? Tresorfehler)?.text ?? error.localizedDescription
            return abgelegt ? .ungeprueft(grund) : .nichtGeschrieben(grund)
        }
    }

    /// Ob das, was auf der Platte liegt, beim nächsten Start als Stand gälte:
    /// dieselbe Form wie die Sitzung — Klartext neben Klartext, Behälter unter
    /// diesem Schlüssel. Sonst legte der nächste Start die Datei beiseite, und
    /// die Meldung darf ihn nicht versprechen (B02).
    private var standAufDerPlatteGilt: Bool {
        guard case .daten(let roh) = ablage.sitzplaeneLesen(hoechstens: Sitzplandienst.hoechstgroesse) else {
            return true
        }
        guard Tresor.istBehaelter(roh) else { return tresor == nil }
        guard let tresor, let kopf = try? Tresor.kopfLesen(roh) else { return false }
        return tresor.passt(zu: kopf)
    }

    /// Schreiben und den Grund festhalten — gemeldet einmal je Störung.
    private func ablegen() {
        guard schreibbar else { return }
        if let grund = schreiben().grund {
            if ungesichert == nil {
                melden("Die Sitzpläne ließen sich nicht sichern (\(grund)) — sie gelten für diese "
                       + "Sitzung; die App versucht es beim nächsten Schreiben und beim Beenden erneut"
                       + (standAufDerPlatteGilt
                          ? ", und der nächste Start liest, was zuletzt gelang."
                          : " — die Datei auf der Platte hat eine andere Form, ein Neustart nähme sie "
                            + "nicht als Stand; bitte vor dem Beenden noch einmal übernehmen."),
                       .warnung)
            }
            ungesichert = grund
        } else {
            ungesichert = nil
            // Ein Behälter liegt — was vorher im Klartext lag, ist übernommen.
            klartextUnbestaetigt = false
        }
    }

    /// E43 (b), Antwort „Versiegeln“: den Klartext unter den Schlüssel bringen.
    func klartextVersiegeln() {
        guard klartextUnbestaetigt else { return }
        klartextUnbestaetigt = false
        ablegen()
    }

    /// E43 (b), Antwort „Beiseitelegen“: die Datei als
    /// `sitzplaene-unerwartet-<Stempel>.json` ins Register, die Pläne leer.
    /// Liefert den Namen der Kopie; `nil`, wenn die Datei im Weg bleibt — dann
    /// bleibt auch die Frage offen, der nächste Start stellt sie erneut.
    func klartextBeiseitelegen(stempel: String) -> String? {
        guard klartextUnbestaetigt else { return nil }
        guard let name = ablage.sitzplaeneBeiseitelegen(als: "sitzplaene-unerwartet-\(stempel).json") else {
            return nil
        }
        klartextUnbestaetigt = false
        ausstehendeKopie = nil
        plaene = [:]
        ungesichert = nil
        return name
    }

    /// Ein Stand, den die Platte nicht trägt, noch einmal — beim Sichern und
    /// beim Beenden (B10).
    func nachholen() {
        guard schreibbar, ungesichert != nil else { return }
        ablegen()
    }

    /// Den Plan einer Klasse setzen oder mit `nil` entfernen. Liefert den
    /// Grund, wenn die Platte ihn nicht trägt — der Plan gilt dann für die Sitzung.
    @discardableResult
    func setzen(_ plan: Sitzplan?, fuer klasseId: String) -> String? {
        guard schreibbar else { return sperrhinweis }
        if let plan {
            var stand = plan
            stand.klasseId = klasseId
            stand.geaendert = Zeitrechnung.jetztAlsZeitstempel()
            plaene[klasseId] = stand
        } else {
            guard plaene.removeValue(forKey: klasseId) != nil else { return nil }
        }
        ablegen()
        return ungesichert
    }

    /// Klassen sind fort (entfernt, nicht übernommen): ihre Pläne mit.
    @discardableResult
    func entfernen(klassen: Set<String>) -> String? {
        guard schreibbar else { return sperrhinweis }
        let vorher = plaene.count
        plaene = plaene.filter { !klassen.contains($0.key) }
        guard plaene.count != vorher else { return nil }
        ablegen()
        return ungesichert
    }

    /// „Neue Planung“: Die Pläne der übernommenen Klassen folgen der neuen
    /// Kennung, alle übrigen werden entfernt.
    @discardableResult
    func umschreiben(zuordnung: [String: String]) -> String? {
        guard schreibbar else { return sperrhinweis }
        var neu: [String: Sitzplan] = [:]
        for (alt, plan) in plaene {
            guard let ziel = zuordnung[alt] else { continue }
            neu[ziel] = plan.mitKlasse(ziel)
        }
        guard neu != plaene else { return nil }
        plaene = neu
        ablegen()
        return ungesichert
    }

    /// Pläne, deren Klasse die Planung nicht kennt (E41): weg, aber nicht
    /// verloren — vorher als `sitzplaene-verwaist-<Stempel>.json` ins Register,
    /// in der Form der Sitzung (Klartext oder Behälter). Ohne Rettungskopie
    /// wird nichts entfernt. Liefert, wie viele gingen, und den Namen der Kopie.
    func aufraeumen(behalte klassen: Set<String>, stempel: String) -> (entfernt: Int, kopie: String?) {
        guard schreibbar else { return (0, nil) }
        let verwaiste = plaene.filter { !klassen.contains($0.key) }
        guard !verwaiste.isEmpty else { return (0, nil) }
        var kopie: String?
        if !vorschau {
            do {
                let klartext = try Sitzplandatei.schreiben(verwaiste)
                let daten = try tresor.map { try $0.versiegeln(klartext, inhalt: .sitzplaene, ziel: .ablage) } ?? klartext
                kopie = try ablage.sitzplaeneRettungSchreiben(daten, als: "sitzplaene-verwaist-\(stempel).json")
            } catch {
                return (0, nil)
            }
        }
        plaene = plaene.filter { klassen.contains($0.key) }
        ablegen()
        return (verwaiste.count, kopie)
    }

    // ── Übergänge ─────────────────────────────────────────────────────────

    /// Unter `neu` versiegeln, wenn `neu` schon gilt — die Ablage trägt ihn
    /// (Passphrase geändert) oder ist auf ihn zurückgenommen. Misslingt es,
    /// geht Klartext als Klartext zurück; ein Behälter behält `neu` und gilt
    /// als ungesichert, bis der nächste Schreibvorgang gelingt.
    func versiegeln(unter neu: Tresor) -> String? {
        versiegeln(neu, bisherigerGiltWeiter: false)
    }

    /// Abgleich, kein Versuch (B17): `neu` gilt schon — die Ablage ist auf ihn
    /// zurückgenommen, nachdem das Aufheben die Pläne vorab im Klartext
    /// hingelegt hatte. Schlüssel und Quelle bleiben deshalb auch bei einem
    /// Fehlschlag auf dem Behälter; `ungesichert` trägt den Grund, und das
    /// nächste Schreiben, das Beenden und der nächste Start holen es nach.
    /// Wurde nichts geschrieben, liegt noch der Klartext des Vorab-Schritts:
    /// Er wird entfernt, solange die Pläne in der Sitzung stehen — er soll
    /// nicht liegen bleiben (Hinweis des Nutzers, 12.09.2026). Der Grund
    /// nennt, was daraus wurde.
    func versiegeln(zurueck neu: Tresor) -> String? {
        guard schreibbar else { return quelle == .zu ? "noch nicht entsperrt" : (sperrgrund ?? "gesperrt") }
        tresor = neu
        quelle = .behaelter
        klartextUnbestaetigt = false
        let befund = schreiben()
        guard let grund = befund.grund else {
            ungesichert = nil
            return nil
        }
        ungesichert = grund
        // Entfernt wird nur der Klartext, den der Vorab-Schritt aus der Sitzung
        // geschrieben hat — nie ein Original, dessen Rettungskopie aussteht (E46).
        guard case .nichtGeschrieben = befund, !plaene.isEmpty, ausstehendeKopie == nil,
              case .daten(let roh) = ablage.sitzplaeneLesen(hoechstens: Sitzplandienst.hoechstgroesse),
              !Tresor.istBehaelter(roh)
        else { return grund }
        ablage.sitzplaeneEntfernen()
        let entfernt = !FileManager.default.fileExists(atPath: ablage.sitzplaene.path)
        return grund + (entfernt
                        ? "; die Klartextdatei wurde entfernt, die Pläne gelten für diese Sitzung"
                        : "; die Klartextdatei ließ sich nicht entfernen und liegt noch")
    }

    /// Unter `neu` versiegeln, bevor die Ablage wechselt (Einschalten,
    /// Erneuern): Misslingt es, findet der Wechsel nicht statt — der bisherige
    /// Stand gilt weiter und wird nachgeschrieben, wenn schon etwas unter
    /// `neu` lag.
    func versiegeln(vorab neu: Tresor) -> String? {
        versiegeln(neu, bisherigerGiltWeiter: true)
    }

    private func versiegeln(_ neu: Tresor, bisherigerGiltWeiter: Bool) -> String? {
        guard schreibbar else { return quelle == .zu ? "noch nicht entsperrt" : (sperrgrund ?? "gesperrt") }
        let alteQuelle = quelle
        let bisheriger = tresor
        tresor = neu
        quelle = .behaelter
        let befund = schreiben()
        guard let grund = befund.grund else {
            ungesichert = nil
            return nil
        }
        if alteQuelle == .klartext {
            tresor = nil
            quelle = .klartext
            // Lag schon ein Behälter, kommt der Klartext zurück — und was dabei
            // nicht gelingt, steht in `ungesichert` und wird gemeldet (B02).
            if case .ungeprueft = befund { ablegen() }
            return grund
        }
        if bisherigerGiltWeiter {
            tresor = bisheriger
            if case .ungeprueft = befund, schreiben() == .gelungen {
                ungesichert = nil
                return grund
            }
        }
        ungesichert = grund
        return grund
    }

    /// Die Hülle hat gewechselt (Wicklung dieses Macs angelegt oder entfernt).
    func neuVersiegeln() {
        guard quelle == .behaelter else { return }
        ablegen()
    }

    /// Aufheben, erster Schritt (B02): die Pläne im Klartext hinlegen, bevor
    /// der Schlüssel geht. `nil`: Der Klartext liegt (oder es gab keinen
    /// offenen Behälter). Sonst der Grund — der Behälter bleibt unter dem
    /// Schlüssel, die Sitzung auch, und der Aufrufer nimmt das Aufheben zurück.
    func entsiegelnVorab() -> String? {
        switch quelle {
        case .klartext: return nil
        case .zu: return "noch nicht entsperrt"
        case .gesperrt(let grund): return grund
        case .behaelter: break
        }
        let bisheriger = tresor
        tresor = nil
        quelle = .klartext
        let befund = schreiben()
        guard let grund = befund.grund else {
            ungesichert = nil
            return nil
        }
        tresor = bisheriger
        quelle = .behaelter
        // Lag schon Klartext, kommt der Behälter zurück.
        if case .ungeprueft = befund { ablegen() }
        return grund
    }

    /// Rücknahme eines Einschaltens aus dem Klartext: die Pläne wieder im
    /// Klartext hinlegen. `false`, wenn kein offener Behälter da war; was
    /// dabei nicht gelingt, steht in `ungesichert`.
    @discardableResult
    func entsiegeln() -> Bool {
        guard quelle == .behaelter else { return false }
        tresor = nil
        quelle = .klartext
        ablegen()
        return true
    }
}
