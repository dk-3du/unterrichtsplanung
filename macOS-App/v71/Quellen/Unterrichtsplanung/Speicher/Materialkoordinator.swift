// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Die Erlaubnis für die Materialliste von 3ducation.org (E176) — dieselbe
/// Mechanik wie bei der Prüfung auf Updates: `nil` heißt nie gefragt, dann
/// stellt die Ersteinrichtung die Frage (die vierte) oder, für eine Planung,
/// die es vor ihr schon gab, das eigene Blatt; umkehrbar unter „Einstellungen“.
/// Geladen wird nur mit Erlaubnis und nur auf Klick; gemerkt wird nichts als
/// die Antwort. Nie im Prüfstand: Der erbt die Erlaubnis nicht und geht nur
/// mit `MATERIAL_QUELLE` an eine Datei.
@MainActor
@Observable
final class Materialkoordinator {
    let pruefstand: Bool
    @ObservationIgnored private let umgebung: [String: String]

    /// `nil`: nie gefragt.
    private(set) var erlaubt: Bool?

    var gefragt: Bool { erlaubt != nil }
    var istErlaubt: Bool { erlaubt ?? false }

    init(pruefstand: Bool, umgebung: [String: String] = ProcessInfo.processInfo.environment) {
        self.pruefstand = pruefstand
        self.umgebung = umgebung
        erlaubt = Einstellungen.wert(Einstellungen.Schluessel.materialienErlaubt)
    }

    /// Die Antwort — aus der Ersteinrichtung, dem eigenen Blatt, dem
    /// Material-Blatt oder den Einstellungen. Ja wie Nein zählen als Antwort.
    func erlauben(_ erlaubt: Bool) {
        self.erlaubt = erlaubt
        Einstellungen.setzen(erlaubt, Einstellungen.Schluessel.materialienErlaubt)
    }

    /// Woher die Liste käme — `nil` im Prüfstand ohne Datei.
    var quelle: URL? {
        Materiallader.quelle(umgebung: umgebung, pruefstand: pruefstand)
    }

    /// Lädt die Liste — nur mit Erlaubnis; ohne Quelle (Prüfstand ohne Datei)
    /// ist sie nicht erreichbar.
    func laden() async -> Materialbefund {
        guard istErlaubt else { return .keineErlaubnis }
        guard let quelle else { return .nichtErreichbar }
        return await Materiallader(quelle: quelle, installiert: Updates.installierterBuild).laden()
    }
}
