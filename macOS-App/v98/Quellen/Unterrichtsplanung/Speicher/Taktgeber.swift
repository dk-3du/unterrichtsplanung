// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Die Zeitgeber des Speichers aus einer Quelle (v84, AT6f-1, E548): Fortsetzung und Nachholen, Verfall der Meldungen,
/// das entprellte Sichern, der Entpreller, die Meldung nach der Tour und die Prüfung auf Updates beim Start (E560); ohne
/// Frist die vorgemerkten Meldungen und das Beenden nach dem Schließen der Blätter (E568). Im Betrieb der
/// `Systemtakt`: `DispatchQueue.main.asyncAfter`, `Task.sleep` und `Task {}`. Je Instanz gesetzt wie `zeitgrenze` (E233);
/// einen anderen Takt gibt es nur im Prüfziel. Die Zeitgeber der Oberfläche, das Warten auf AppKit und der
/// Aufwachabruf bleiben außen vor (E561); `pruefen.sh` hält sie als benannte Ausnahmen.
@MainActor
protocol Taktgeber: AnyObject {
    /// `handlung` nach `sekunden` auf der Hauptwarteschlange — wie `DispatchQueue.main.asyncAfter`.
    func nach(_ sekunden: Double, _ handlung: @escaping @MainActor () -> Void)
    /// Wartet `dauer` — wie `Task.sleep(for:)`, auch im Abbruch.
    func warten(_ dauer: Duration) async throws
    /// `arbeit` in einer eigenen Aufgabe nach `dauer` (E565). Bricht jemand die Aufgabe ab, endet das Warten, und
    /// `arbeit` läuft mit `Task.isCancelled` — wie nach `Task.sleep`. Im Betrieb die Vorgabe unten.
    @discardableResult
    func aufgabe(nach dauer: Duration, _ arbeit: @escaping @MainActor () async -> Void) -> Task<Void, Never>
    /// `arbeit` in einer eigenen Aufgabe, ohne Frist — „nicht in derselben Änderung“ (E568). Im Betrieb die Vorgabe unten.
    @discardableResult
    func gleich(_ arbeit: @escaping @MainActor () async -> Void) -> Task<Void, Never>
}

@MainActor
extension Taktgeber {
    /// Die Aufgabe im Betrieb: warten, dann arbeiten.
    @discardableResult
    func aufgabe(nach dauer: Duration, _ arbeit: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        nachFrist(dauer, arbeit)
    }

    /// Warten, dann arbeiten — die Vorgabe und der Systemtakt, solange er nicht staucht. Ein Abbruch beendet das
    /// Warten, `arbeit` läuft mit `Task.isCancelled` (E565).
    func nachFrist(_ dauer: Duration, _ arbeit: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        Task {
            try? await warten(dauer)
            await arbeit()
        }
    }

    /// Ohne Frist im Betrieb: eine eigene Aufgabe auf dem Hauptakteur.
    @discardableResult
    func gleich(_ arbeit: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        Task { await arbeit() }
    }
}

/// Der Takt im Betrieb.
@MainActor
final class Systemtakt: Taktgeber {
    static let gemeinsam = Systemtakt()

    #if DEBUG
    /// Nur in Debug-Bauten — Prüfziel und Entwicklungsbau (E551): `PRUEFTAKT` dehnt jede Frist auf das Zehnfache oder
    /// staucht sie auf null — die Verzögerungsprobe. Gestaucht kommt alles so früh wie möglich (E609): `nach` stellt die
    /// Handlung sofort an, eine Aufgabe startet ohne Warten. Ohne Wert bleibt die Frist; ein anderer Wert ist kein
    /// Faktor, die Prüfung meldet ihn. `pruefen.sh` verlangt den Faktor in beiden Zeilen des Systemtakts.
    static func faktorVon(_ wert: String?) -> Double? {
        switch wert {
        case nil: 1
        case "dehnen": 10
        case "stauchen": 0
        default: nil
        }
    }

    static let faktor: Double = faktorVon(ProcessInfo.processInfo.environment["PRUEFTAKT"]) ?? 1
    #else
    static let faktor: Double = 1
    #endif

    func nach(_ sekunden: Double, _ handlung: @escaping @MainActor () -> Void) {
        #if DEBUG
        // Gestaucht sofort angestellt, ohne Frist — so früh wie möglich (E609).
        if Self.faktor == 0 {
            DispatchQueue.main.async { handlung() }
            return
        }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + sekunden * Self.faktor) { handlung() }  // E561: Zeitgeber (Takt) — der Systemtakt: Fristen des Speichers im Betrieb
    }

    func warten(_ dauer: Duration) async throws {
        try await Task.sleep(for: dauer * Self.faktor)  // E561: Zeitgeber (Takt) — der Systemtakt: Fristen des Speichers im Betrieb
    }

    #if DEBUG
    /// Gestaucht startet die Aufgabe ohne Warten, so früh wie möglich (E609); sonst wie die Vorgabe. Ein Abbruch vor
    /// dem Start: `arbeit` läuft mit `Task.isCancelled` (E565).
    @discardableResult
    func aufgabe(nach dauer: Duration, _ arbeit: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        Self.faktor == 0 ? Task { await arbeit() } : nachFrist(dauer, arbeit)
    }
    #endif
}
