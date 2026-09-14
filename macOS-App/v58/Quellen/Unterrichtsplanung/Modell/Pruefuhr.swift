// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Läuft dieser Prozess als Prüfziel (`swift test`, Xcode)?
///
/// Die Frage gehört ins Modell, nicht in die Ablage: Die Ablage braucht die
/// Antwort (ohne `PLANUNGSORDNER` einen eigenen Ordner je Prozess), die
/// `Pruefuhr` auch — und die Modellschicht hängt an nichts, was über sie
/// hinausgeht. Genau darauf besteht `abzug_pruefen.py`, das sie allein
/// übersetzt; als die Uhr hier nach `Ablage` griff, hat es das gemeldet.
enum Pruefziel {
    static let ja: Bool = {
        let prozess = ProcessInfo.processInfo
        let programm = (prozess.arguments.first as NSString?)?.lastPathComponent ?? ""
        // `swift test` läuft über den swiftpm-testing-helper, Xcode über xctest.
        return programm == "swiftpm-testing-helper" || programm == "xctest"
            || Bundle.main.bundleURL.pathExtension == "xctest"
            || prozess.environment["XCTestConfigurationFilePath"] != nil
            || prozess.environment["XCTestBundlePath"] != nil
    }()
}

/// Die Uhr, nach der gestempelt wird — im Betrieb die Systemuhr.
///
/// Prüfläufe halten sie an, damit zwei Änderungen denselben Stempel tragen:
/// Nur so lässt sich messen, dass die Sicherung ihre Fassungen nicht am
/// Stempel auseinanderhält (E81). **Außerhalb des Prüfziels bleibt das
/// wirkungslos** — die ausgelieferte App geht nach der Systemuhr, und eine
/// angehaltene Uhr in einer ausgelieferten App wäre ein Fehler, kein Werkzeug.
enum Pruefuhr {
    /// Aufgabenweit, nicht programmweit: Prüfläufe laufen nebeneinander, und
    /// eine angehaltene Uhr für alle brächte die Läufe durcheinander, die
    /// Zeitpunkte vergleichen (am Lauf gesehen — drei Suiten kippten).
    @TaskLocal private static var festgehalten: Date?

    static var jetzt: Date { festgehalten ?? Date() }

    /// Hält die Uhr für die Dauer des Aufrufs an; ohne Angabe beim jetzigen
    /// Zeitpunkt. Außerhalb des Prüfziels geschieht nichts.
    static func angehalten<T>(_ zeitpunkt: Date = Date(),
                              _ waehrenddessen: () throws -> T) rethrows -> T {
        guard Pruefziel.ja else { return try waehrenddessen() }
        return try $festgehalten.withValue(zeitpunkt) { try waehrenddessen() }
    }

    static func angehalten<T>(_ zeitpunkt: Date = Date(),
                              isolation: isolated (any Actor)? = #isolation,
                              _ waehrenddessen: () async throws -> T) async rethrows -> T {
        guard Pruefziel.ja else { return try await waehrenddessen() }
        return try await $festgehalten.withValue(zeitpunkt,
                                                 operation: { try await waehrenddessen() },
                                                 isolation: isolation)
    }
}
