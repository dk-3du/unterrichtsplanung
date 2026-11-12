// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Der Sitzplan-Editor (v96, BH4, E1192): 820 × 700, fest in beiden Richtungen; auf kleinem Bildschirm niedriger wie das
/// Vorhaben-Blatt (E1150, E1188), der Körper in einer Rollfläche; die Bedienung hinter dem ⓘ (E1191). Lage und Rollen am
/// Fenster prüft die Dialogprobe („Kleiner Bildschirm · Sitzplan“), die Abstände im Bild die Abbilder 19–19f.
@Suite("Sitzplan-Editor 820 × 700", .serialized)
@MainActor
struct SitzplanblattPruefungen {
    init() throws {
        try #require(Ablage.istPruefstand, "die Blätter brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    @Test("E1192: Der Sitzplan-Editor misst 820 × 700, fest in beiden Richtungen")
    func masse() throws {
        let planung = Planung.leer(titel: "Sitzplan", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
                                   basis: "/Users/lehrkraft/Unterricht",
                                   klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: planung)
        // Ohne Fenster läuft kein `onAppear`: Das Blatt steht ohne Plan, mit der Namensliste. Die Fläche misst die
        // Dialogprobe am Fenster, in beiden Läufen (mit und ohne Datenschutzhinweis).
        let groesse = SeitenleistePruefungen.groesse(SitzplanDialog().environment(speicher))
        // Feste Sollwerte, nicht die Konstanten des Blatts (R-BG8c-05).
        #expect(abs(groesse.width - 820) < 0.5 && abs(groesse.height - 700) < 0.5,
                "\(Int(groesse.width)) × \(Int(groesse.height)) (−1 × −1: nicht fest)")
    }
}
