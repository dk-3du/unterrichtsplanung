// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Updates ───────────────────────────────────────────────────────────────────
// Einwilligung, Frist und Angebot führt der `Updatekoordinator`; hier steht,
// wann die Frage und wann das Blatt kommen darf — das hängt an den offenen
// Blättern und der Tour, die nur der Speicher kennt.
extension Planungsspeicher {

    var updatestand: Updatestand { updates.stand }
    /// Das Release, das das Blatt zeigt — `nil`, sobald es beantwortet ist.
    var update: Veroeffentlichung? { updates.angebot }
    var updateLaeuft: Bool { updates.laeuft }
    /// Das Ergebnis der letzten Prüfung in einem Satz — für die Einstellungen.
    var updateMeldung: String? { updates.meldung }
    var updatesErlaubt: Bool { updates.erlaubt }
    var updatesGefragt: Bool { updates.gefragt }

    /// Die Antwort auf die Frage — aus der Ersteinrichtung, dem eigenen Blatt
    /// oder den Einstellungen. Wer einschaltet, bekommt die erste Prüfung gleich.
    func updatesErlauben(_ erlaubt: Bool) {
        updates.erlauben(erlaubt)
    }

    /// Das eigene Blatt: eine Planung, die es vor der dritten Frage schon gab
    /// (die Ersteinrichtung ist nicht mehr fällig) — und die Frage nie gestellt.
    static func updateNachfrageFaellig(pruefstand: Bool, hatPlanung: Bool,
                                       ersteinrichtungFaellig: Bool, gefragt: Bool) -> Bool {
        !pruefstand && hatPlanung && !ersteinrichtungFaellig && !gefragt
    }

    /// Wie die Ersteinrichtung: nie über ein offenes Blatt oder die Tour hinweg.
    func updateNachfragePruefen() {
        guard Planungsspeicher.updateNachfrageFaellig(
                pruefstand: Ablage.istPruefstand, hatPlanung: hatPlanung,
                ersteinrichtungFaellig: ersteinrichtungFaellig, gefragt: updatesGefragt),
              !dialogOffen, !tourLaeuft else { return }
        offenerDialog = .updateNachfrage
    }

    /// Beim Öffnen: einmal je Start, ein paar Sekunden nachdem die Planung
    /// da ist. Sagt, ob die Prüfung angestoßen wurde.
    @discardableResult
    func updatesBeimStartPruefen() -> Bool {
        updates.beimStartPruefen(hatPlanung: hatPlanung)
    }

    /// Von Hand (`erzwungen`: immer, mit Rückmeldung) oder beim Öffnen (nur
    /// mit Einwilligung, nur wöchentlich, still).
    func updatesPruefen(erzwungen: Bool = false) {
        updates.pruefen(erzwungen: erzwungen)
    }

    func updateErgebnisUebernehmen(_ ergebnis: Updateergebnis, erzwungen: Bool) {
        updates.ergebnisUebernehmen(ergebnis, erzwungen: erzwungen)
    }

    /// Das Blatt kommt erst, wenn kein anderes liegt und keine Tour läuft —
    /// sonst beim nächsten Schließen eines Blatts.
    func updateAnzeigenPruefen() {
        guard update != nil, !dialogOffen, !tourLaeuft else { return }
        offenerDialog = .update
    }

    /// Für Abbild und Prüfstand: ein Release vorgeben, ohne zu fragen.
    func updateVorgeben(_ release: Veroeffentlichung) {
        updates.vorgeben(release)
    }

    /// „Später“ und ⎋: Die nächste Prüfung zeigt es wieder.
    func updateSpaeter() {
        updates.spaeter()
    }

    /// „Diese Version überspringen“: gemerkt wird der Build.
    func updateUeberspringen() {
        updates.ueberspringen()
    }

    /// „Zum Download“: die Release-Seite im Browser — nur HTTPS, sonst nichts.
    func updateSeiteOeffnen() {
        if let seite = updates.seiteAbrufen() { Systemzugriff.adresseOeffnen(seite.absoluteString) }
    }
}
