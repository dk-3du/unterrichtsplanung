// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

/// Warten in Prüfungen (E145, v66): **Signale statt Zeit, wo ein Signal zu
/// haben ist** — `Sicherungsdienst.entprelltJetzt()`, die Fortsetzungen der
/// `Naht`, eine angehaltene `Pruefuhr`. Wo eine echte Nebenarbeit läuft, deren
/// Ende der Prüfling nicht meldet (Schlüsselarbeit, Systemabfrage, verzögerte
/// Meldung), wartet diese eine Hilfe auf die Bedingung — mit einer Zahl von
/// Versuchen als Sicherheitsnetz, die **mit Meldung** scheitert. Bis v65 liefen solche
/// Schleifen still aus, und erst die nächste Erwartung fiel, mit einer Meldung
/// über etwas anderes. Die Frist ist kein Takt: Sie bemisst, wann etwas
/// eindeutig nicht mehr kommt (v59: Zeit-Warten kippte im Parallellauf, ohne
/// dass etwas falsch war).
@MainActor
func abwarten(_ was: String, versuche: Int = 600,
              sourceLocation: SourceLocation = #_sourceLocation,
              bis bedingung: @MainActor () -> Bool) async throws {
    // Gezählt werden die eigenen Versuche (je 5 ms Schlaf), nicht die Wanduhr:
    // Im vollen Parallellauf halten andere Suiten den Hauptakteur sekundenlang
    // mit synchronem PBKDF2 fest — eine Wanduhr-Frist liefe dann ab, ehe der
    // Prüfling überhaupt drankam (gemessen 16.09.2026: 5 s Frist, Meldung nach
    // 9 s). Die Versuche dehnen sich mit dem Hauptakteur; 600 Versuche sind
    // drei Sekunden eigener Wartezeit.
    let anfang = ContinuousClock.now
    for _ in 0..<versuche {
        if bedingung() { return }
        try await Task.sleep(for: .milliseconds(5))  // E145: Uhr — Takt der Hilfe abwarten(_:bis:), begrenzt durch die Zahl der Versuche
    }
    guard bedingung() else {
        Issue.record("\(versuche) Versuche (\(ContinuousClock.now - anfang) Wanduhr) — nicht eingetreten: \(was)",
                     sourceLocation: sourceLocation)
        throw Fristablauf(was: was)
    }
}

struct Fristablauf: Error { let was: String }
