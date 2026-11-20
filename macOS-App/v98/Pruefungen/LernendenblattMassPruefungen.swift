// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Das Blatt „Lernende“ (⌘L, v96, BH5, E1173): 980 × 820 wie das Vorhaben-Blatt, fest in beiden Richtungen; auf kleinem
/// Bildschirm niedriger wie dieses (E1150) — Lage und Höhe am Fenster prüft die Dialogprobe („Kleiner Bildschirm“).
@Suite("Blatt „Lernende“ 980 × 820", .serialized)
@MainActor
struct LernendenblattMassPruefungen {
    init() throws {
        try #require(Ablage.istPruefstand, "die Blätter brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    @Test("E1173: Das Blatt „Lernende“ misst 980 × 820, fest in beiden Richtungen")
    func masse() throws {
        let planung = Planung.leer(titel: "Lernende", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
                                   basis: "/Users/lehrkraft/Unterricht",
                                   klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: planung)
        let groesse = SeitenleistePruefungen.groesse(LernendenDialog().environment(speicher))
        // Feste Sollwerte, nicht die Konstanten des Blatts (R-BG8c-05).
        #expect(abs(groesse.width - 980) < 0.5 && abs(groesse.height - 820) < 0.5,
                "\(Int(groesse.width)) × \(Int(groesse.height)) (−1 × −1: nicht fest)")
    }
}
