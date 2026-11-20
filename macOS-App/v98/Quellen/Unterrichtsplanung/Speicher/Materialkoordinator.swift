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

    /// Wer lädt — für Prüfungen ersetzbar.
    @ObservationIgnored var lader: @Sendable (URL) async -> Materialbefund = { quelle in
        await Materiallader(quelle: quelle, installiert: Updates.installierterBuild).laden()
    }

    /// `nil`: nie gefragt.
    private(set) var erlaubt: Bool?

    /// Was gerade lädt, und die Epoche der Erlaubnis (E199, R72-03, v73): Der
    /// Entzug bricht jede laufende Ladeaufgabe ab — der Abbruch erreicht die
    /// Anfrage — und zählt die Epoche weiter; ein Befund aus einer früheren
    /// Epoche gilt nicht, auch nicht nach erneutem Einschalten.
    @ObservationIgnored private var laufende: Set<Task<Materialbefund, Never>> = []
    @ObservationIgnored private var epoche = 0

    var gefragt: Bool { erlaubt != nil }
    var istErlaubt: Bool { erlaubt ?? false }

    init(pruefstand: Bool, umgebung: [String: String] = ProcessInfo.processInfo.environment) {
        self.pruefstand = pruefstand
        self.umgebung = umgebung
        erlaubt = Einstellungen.wert(Einstellungen.Schluessel.materialienErlaubt)
    }

    /// Die Antwort — aus der Ersteinrichtung, dem eigenen Blatt, dem
    /// Material-Blatt oder den Einstellungen. Ja wie Nein zählen als Antwort.
    /// Ein Nein bricht ab, was noch lädt: „Ausgeschaltet geht dafür nichts ins Netz.“
    func erlauben(_ erlaubt: Bool) {
        self.erlaubt = erlaubt
        Einstellungen.setzen(erlaubt, Einstellungen.Schluessel.materialienErlaubt)
        guard !erlaubt else { return }
        epoche += 1
        for aufgabe in laufende { aufgabe.cancel() }
        laufende.removeAll()
    }

    /// Woher die Liste käme — `nil` im Prüfstand ohne Datei.
    var quelle: URL? {
        Materiallader.quelle(umgebung: umgebung, pruefstand: pruefstand)
    }

    /// Lädt die Liste — nur mit Erlaubnis, vor dem Laden geprüft und danach
    /// noch einmal; ohne Quelle (Prüfstand ohne Datei) ist sie nicht erreichbar.
    /// Die Ladeaufgabe hält der Koordinator, damit ein Entzug sie abbrechen
    /// kann; schließt das Blatt, bricht seine Aufgabe ab und mit ihr diese.
    func laden() async -> Materialbefund {
        guard istErlaubt else { return .keineErlaubnis }
        guard let quelle else { return .nichtErreichbar }
        let meine = epoche
        let lader = self.lader
        let aufgabe = Task { await lader(quelle) }
        laufende.insert(aufgabe)
        let befund = await withTaskCancellationHandler {
            await aufgabe.value
        } onCancel: {
            aufgabe.cancel()
        }
        laufende.remove(aufgabe)
        // Die Erlaubnis gilt auch für das Ergebnis: Wer sie entzieht, während
        // noch geladen wird, bekommt keine Liste mehr zu sehen — auch nicht,
        // wenn er sie gleich wieder erteilt.
        guard istErlaubt, epoche == meine else { return .keineErlaubnis }
        return befund
    }
}
