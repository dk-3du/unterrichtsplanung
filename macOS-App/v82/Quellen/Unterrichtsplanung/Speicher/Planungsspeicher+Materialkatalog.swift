// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Die Materialliste von 3ducation.org ──────────────────────────────────────
// Erlaubnis und Laden führt der `Materialkoordinator`; hier steht, wann die
// einmalige Nachfrage kommen darf — das hängt an den offenen Blättern und der
// Tour, die nur der Speicher kennt (E176).
extension Planungsspeicher {

    var materialienErlaubt: Bool { materialliste.istErlaubt }
    var materialienGefragt: Bool { materialliste.gefragt }

    /// Die Antwort auf die Frage — aus der Ersteinrichtung, dem eigenen Blatt,
    /// dem Material-Blatt oder den Einstellungen.
    func materialienErlauben(_ erlaubt: Bool) {
        materialliste.erlauben(erlaubt)
    }

    /// Das eigene Blatt: eine Planung, die es vor der vierten Frage schon gab
    /// — die Ersteinrichtung ist nicht mehr fällig, die Update-Frage ist
    /// beantwortet (sonst kommt die zuerst, als eigenes Blatt), diese nie.
    static func materialNachfrageFaellig(pruefstand: Bool, hatPlanung: Bool,
                                         ersteinrichtungFaellig: Bool, updateGefragt: Bool,
                                         gefragt: Bool) -> Bool {
        !pruefstand && hatPlanung && !ersteinrichtungFaellig && updateGefragt && !gefragt
    }

    /// Wie die Update-Nachfrage: nie über ein offenes Blatt oder die Tour hinweg.
    func materialNachfragePruefen() {
        guard Planungsspeicher.materialNachfrageFaellig(
                pruefstand: Ablage.istPruefstand, hatPlanung: hatPlanung,
                ersteinrichtungFaellig: ersteinrichtungFaellig, updateGefragt: updatesGefragt,
                gefragt: materialienGefragt),
              !dialogOffen, !tourLaeuft else { return }
        offenerDialog = .materialNachfrage
    }

    /// Die Liste für das Material-Blatt — nur mit Erlaubnis, sonst der Befund
    /// `keineErlaubnis`, und das Blatt zeigt die Frage.
    func materialkatalogLaden() async -> Materialbefund {
        await materialliste.laden()
    }
}
