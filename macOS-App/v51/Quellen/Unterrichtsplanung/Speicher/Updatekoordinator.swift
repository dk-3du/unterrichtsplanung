// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Was von der Prüfung auf Updates zu merken ist — in den Einstellungen,
/// außer im Prüflauf.
struct Updatestand: Equatable, Sendable {
    /// `nil` heißt: nie gefragt — dann stellt die Ersteinrichtung die Frage
    /// oder, für eine Planung, die es vor ihr schon gab, das eigene Blatt.
    var erlaubt: Bool?
    /// Die letzte Prüfung, auch eine gescheiterte — kein Nachbohren.
    var zuletzt: Date?
    /// Der übersprungene Build; ein späteres Release hebt ihn auf.
    var uebersprungen: Int?
    var etag: String?
    /// Die Antwort zum ETag, für ein 304.
    var antwort: Data?
}

/// Die Prüfung auf Updates: nur mit Einwilligung, höchstens einmal je Woche,
/// nie im Prüfstand. Der Prüfer (`Updatepruefer`) fragt und vergleicht; hier
/// liegt, was zu merken ist, und ob ein Angebot vorliegt. Ob das Blatt kommen
/// darf, entscheidet der Speicher — er kennt die offenen Blätter und die Tour.
@MainActor
@Observable
final class Updatekoordinator {
    /// Im Prüfstand geht nichts ins Netz, und die Einwilligung wird nicht geerbt.
    let pruefstand: Bool
    @ObservationIgnored private let umgebung: [String: String]

    private(set) var stand: Updatestand
    /// Das Release, das das Blatt zeigt — `nil`, sobald es beantwortet ist.
    private(set) var angebot: Veroeffentlichung?
    private(set) var laeuft = false
    /// Das Ergebnis der letzten Prüfung in einem Satz — für die Einstellungen,
    /// wo der Melder unter dem Blatt läge.
    private(set) var meldung: String?
    @ObservationIgnored private var beimStartGeprueft = false

    /// Was der Nutzer zu hören bekommt — nur bei einer Prüfung von Hand.
    @ObservationIgnored var melden: @MainActor (String, Meldung.Art) -> Void = { _, _ in }
    /// Ein Angebot liegt vor — der Speicher zeigt das Blatt, sobald keines liegt.
    @ObservationIgnored var beiAngebot: @MainActor () -> Void = {}

    var erlaubt: Bool { stand.erlaubt ?? false }
    var gefragt: Bool { stand.erlaubt != nil }

    init(pruefstand: Bool, umgebung: [String: String] = ProcessInfo.processInfo.environment) {
        self.pruefstand = pruefstand
        self.umgebung = umgebung
        // Über die Schranke: Ein Prüflauf erbt die Einwilligung nicht — er fragt ohnehin nie.
        stand = Updatekoordinator.standLesen()
    }

    private static func standLesen() -> Updatestand {
        typealias S = Einstellungen.Schluessel
        return Updatestand(
            erlaubt: Einstellungen.wert(S.updatesErlaubt), zuletzt: Einstellungen.wert(S.updateZuletzt),
            uebersprungen: Einstellungen.wert(S.updateUebersprungen), etag: Einstellungen.wert(S.updateEtag),
            antwort: Einstellungen.wert(S.updateAntwort))
    }

    private func standSichern() {
        func ablegen(_ wert: Any?, _ schluessel: String) {
            if let wert { Einstellungen.setzen(wert, schluessel) } else { Einstellungen.entfernen(schluessel) }
        }
        ablegen(stand.erlaubt, Einstellungen.Schluessel.updatesErlaubt)
        ablegen(stand.zuletzt, Einstellungen.Schluessel.updateZuletzt)
        ablegen(stand.uebersprungen, Einstellungen.Schluessel.updateUebersprungen)
        ablegen(stand.etag, Einstellungen.Schluessel.updateEtag)
        ablegen(stand.antwort, Einstellungen.Schluessel.updateAntwort)
    }

    /// Die Antwort auf die Frage — aus der Ersteinrichtung, dem eigenen Blatt
    /// oder den Einstellungen. Wer einschaltet, bekommt die erste Prüfung gleich.
    func erlauben(_ erlaubt: Bool) {
        stand.erlaubt = erlaubt
        standSichern()
        if erlaubt { pruefen() }
    }

    /// Beim Öffnen: einmal je Start, ein paar Sekunden nachdem die Planung
    /// da ist — nicht früher, sonst käme das Blatt in die Freigabe hinein —,
    /// und nur, wenn die Woche um ist. Sagt, ob die Prüfung angestoßen wurde.
    @discardableResult
    func beimStartPruefen(hatPlanung: Bool) -> Bool {
        guard hatPlanung, !beimStartGeprueft else { return false }
        beimStartGeprueft = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.pruefen()
        }
        return true
    }

    /// Von Hand (`erzwungen`: immer, mit Rückmeldung) oder beim Öffnen (nur
    /// mit Einwilligung, nur wöchentlich, still). Im Prüfstand geht nichts ins Netz.
    func pruefen(erzwungen: Bool = false) {
        guard !laeuft else {
            if erzwungen { melden("Die Prüfung läuft schon.", .hinweis) }
            return
        }
        guard Updatepruefer.faellig(erlaubt: erlaubt, zuletzt: stand.zuletzt, erzwungen: erzwungen) else { return }
        guard let quelle = Updatepruefer.quelle(umgebung: umgebung, pruefstand: pruefstand) else {
            if erzwungen { melden("Im Prüfstand wird nicht nach Updates gesucht.", .warnung) }
            return
        }
        laeuft = true
        let pruefer = Updatepruefer(quelle: quelle, installiert: Updates.installierterBuild,
                                    uebersprungen: stand.uebersprungen,
                                    etag: stand.etag, gemerkt: stand.antwort)
        Task { @MainActor [weak self] in
            let ergebnis = await pruefer.pruefen()
            self?.ergebnisUebernehmen(ergebnis, erzwungen: erzwungen)
        }
    }

    /// Der Zeitstempel wird in jedem Fall gesetzt; ETag und Antwort nur, wenn
    /// eine kam. Das Angebot nur für Neues — von Hand auch für Übersprungenes.
    func ergebnisUebernehmen(_ ergebnis: Updateergebnis, erzwungen: Bool) {
        laeuft = false
        stand.zuletzt = .now
        if case .nichtErreichbar = ergebnis.befund {} else {
            stand.etag = ergebnis.etag
            stand.antwort = ergebnis.antwort
        }
        standSichern()

        switch ergebnis.befund {
        case .neu(let release):
            meldung = "Neu: \(release.titel)."
            angebot = release
            beiAngebot()
        case .uebersprungen(let release):
            meldung = "\(release.titel) liegt vor — übersprungen."
            guard erzwungen else { return }
            angebot = release
            beiAngebot()
        case .aktuell:
            meldung = "Auf dem neuesten Stand — Version \(Updates.installierteFassung)."
            if erzwungen { melden("Die App ist auf dem neuesten Stand — Version \(Updates.installierteFassung).", .hinweis) }
        case .nichtErreichbar:
            meldung = "Keine Verbindung zu GitHub."
            if erzwungen {
                melden("Keine Verbindung zu GitHub — bitte später noch einmal versuchen.", .warnung)
            }
        case .unlesbar:
            meldung = "Die Antwort von GitHub ließ sich nicht lesen."
            if erzwungen { melden("Die Antwort von GitHub ließ sich nicht lesen.", .warnung) }
        }
    }

    /// Für Abbild und Prüfstand: ein Release vorgeben, ohne zu fragen.
    func vorgeben(_ release: Veroeffentlichung) {
        angebot = release
    }

    /// „Später“ und ⎋: Die nächste Prüfung zeigt es wieder.
    func spaeter() {
        angebot = nil
    }

    /// „Diese Version überspringen“: gemerkt wird der Build.
    func ueberspringen() {
        if let build = angebot?.build {
            stand.uebersprungen = build
            standSichern()
        }
        angebot = nil
    }

    /// „Zum Download“: die Release-Seite — beantwortet ist das Angebot damit.
    func seiteAbrufen() -> URL? {
        let seite = angebot?.seite
        angebot = nil
        return seite
    }
}
