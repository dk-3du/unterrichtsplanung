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
/// der nächste Schreibanlass versucht es erneut. Eine Datei, die nicht zu
/// lesen ist, wird nicht angefasst — die Pläne sind dann **gesperrt**, bis
/// der nächste Start sie liest. Beschädigt oder fremd versiegelt heißt:
/// beiseitegelegt als `sitzplaene-beschaedigt-`/`-fremd-<Stempel>.json`.
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
        /// Klartext neben einer versiegelten Ablage — jetzt versiegelt.
        case nachgeholt(Int)
        /// Beschädigt, fremd versiegelt oder Behälter neben einer
        /// Klartext-Planung: beiseitegelegt unter `rettung`; die Pläne sind leer.
        case beiseitegelegt(String, rettung: String)
        /// Die Datei liegt und bleibt unangetastet; die Pläne sind gesperrt.
        case gesperrt(String)
    }

    /// Der eine Weg von der Platte zu den Plänen — beim Laden und beim
    /// Zurücklesen derselbe: Behälter oder Klartext, Inhalt, Schlüssel, Datei.
    private func gedeutet(_ roh: Data, tresor: Tresor?) throws -> [String: Sitzplan] {
        guard Tresor.istBehaelter(roh) else { return try Sitzplandatei.lesen(roh) }
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
        return try Sitzplandatei.lesen(try tresor.oeffnen(kopf: kopf))
    }

    /// Beim Start neben einer Klartext-Planung (oder ohne Planung).
    func laden(stempel: String) -> Ladebefund {
        tresor = nil
        ungesichert = nil
        return lesen(stempel: stempel)
    }

    /// Nach dem Entsperren: den Behälter unter dem Datenschlüssel öffnen.
    /// Klartext neben der versiegelten Ablage (ein Einschalten, das zwischen
    /// zwei Schritten abbrach) wird jetzt versiegelt; ein beschädigter oder
    /// fremd versiegelter Behälter wird beiseitegelegt; einer, der sich
    /// nicht lesen lässt oder aus einer neueren Fassung stammt, bleibt liegen.
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
            plaene = try gedeutet(roh, tresor: tresor)
            quelle = offen
            // Klartext neben der versiegelten Ablage: jetzt nachholen.
            if tresor != nil, !Tresor.istBehaelter(roh) {
                ablegen()
                return .nachgeholt(plaene.count)
            }
            return .geladen(plaene.count)
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
            guard try gedeutet(roh, tresor: tresor) == plaene else {
                return .ungeprueft("die Platte trägt einen anderen Stand")
            }
            return .gelungen
        } catch {
            let grund = (error as? Tresorfehler)?.text ?? error.localizedDescription
            return abgelegt ? .ungeprueft(grund) : .nichtGeschrieben(grund)
        }
    }

    /// Schreiben und den Grund festhalten — gemeldet einmal je Störung.
    private func ablegen() {
        guard schreibbar else { return }
        if let grund = schreiben().grund {
            if ungesichert == nil {
                melden("Die Sitzpläne ließen sich nicht sichern (\(grund)) — sie gelten für diese "
                       + "Sitzung; die App versucht es beim nächsten Schreiben und beim nächsten "
                       + "Start erneut.", .warnung)
            }
            ungesichert = grund
        } else {
            ungesichert = nil
        }
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

    // ── Übergänge ─────────────────────────────────────────────────────────

    /// Unter `neu` versiegeln, wenn `neu` schon gilt — die Ablage trägt ihn
    /// (Passphrase geändert) oder ist auf ihn zurückgenommen. Misslingt es,
    /// geht Klartext als Klartext zurück; ein Behälter behält `neu` und gilt
    /// als ungesichert, bis der nächste Schreibvorgang gelingt.
    func versiegeln(unter neu: Tresor) -> String? {
        versiegeln(neu, bisherigerGiltWeiter: false)
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
            // Lag schon ein Behälter, kommt der Klartext zurück.
            if case .ungeprueft = befund { _ = schreiben() }
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

    /// Aufheben: die Pläne im Klartext hinlegen. `false`, wenn kein offener
    /// Behälter da war — ein gesperrter bleibt liegen, der nächste Start legt
    /// ihn als fremd beiseite.
    @discardableResult
    func entsiegeln() -> Bool {
        guard quelle == .behaelter else { return false }
        tresor = nil
        quelle = .klartext
        ablegen()
        return true
    }
}
