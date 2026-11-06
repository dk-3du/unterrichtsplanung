// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

/// Die Probe an SwiftUI-Auswahlfeldern und -Menüs (K2, E1019): Unter macOS 27 haben sie keine eigene AppKit-Ansicht, und die
/// Lernendenprobe bedient sie wie von Hand — ein Klick an ihren Platz neben einer AppKit-Ansicht (`menueAmPunkt`). Am
/// Quelltext, dass jede Stelle diesen Weg hat; ob er trägt, zeigt die Probe am Fenster, unter macOS 27 in der VM-Runde.
@Suite("Probe: SwiftUI-Menüs wie von Hand (K2)")
struct ProbeMenuewegPruefungen {
    /// Der Quelltext der Probe ohne Kommentare — gezählt wird im Code (R8d-08, U3-05).
    static func probe() throws -> String {
        HuelltabellePruefungen.code(try HuelltabellePruefungen.quelle("App/Lernendenprobe.swift"))
    }

    @Test("K2: Auswahlfeld der Mitteilungen, „Lerngruppen“, „Stand für …“ und die Schuljahreswahl gehen wie von Hand")
    func stellen() throws {
        let text = try Self.probe()
        func zahl(_ s: String) -> Int { text.components(separatedBy: s).count - 1 }
        // Auswahlfeld: gezeigt nach dem Anlegen, nach dem Wechsel der Lerngruppe, Wechsel mit Fokus im Titel, Schritt
        // „Auswahlfeld“ (gefunden, gewählt, gelesen) und Tag des Rücklaufs (gewählt, gelesen).
        #expect(zahl("Menueanker.auswahlfeld(") == 8, "das Auswahlfeld an acht Stellen wie von Hand")
        #expect(zahl("Menueanker.lerngruppen(") == 1, "„Lerngruppen“ → „Umziehen nach“ wie von Hand")
        #expect(zahl("Menueanker.standFuer(") == 1, "„Stand für …“ wie von Hand")
        #expect(text.contains("let menue = await menueAmPunkt(blatt3, punkte,"), "die Schuljahreswahl über denselben Helfer")
        let roh = try HuelltabellePruefungen.quelle("App/Lernendenprobe.swift")
        for alt in ["bedient es nicht", "bedient sie nicht", "bedient die Probe nicht", "sieht die Hand"] {
            #expect(!roh.contains(alt), "keine Stelle mehr, an der die Probe ein Menü der Hand lässt: „\(alt)“")
        }
    }

    @Test("W3-09: Jede Suche der Probe nach einem NSPopUpButton hat ihren Weg wie von Hand — eine neue fällt hier auf")
    func popUpSuchen() throws {
        // Einen NSPopUpButton baut SwiftUI nur unter macOS 26. Die sechs Suchen: das Auswahlfeld der Mitteilungen nach dem
        // Anlegen und mit genau den Einträgen (Wechsel der Lerngruppe), im Schritt „Auswahlfeld“ und beim Tag des Rücklaufs;
        // die Schuljahreswahl beim Öffnen und im Vorjahr. Kommt eine Suche dazu, braucht sie den Weg über `menueAmPunkt`,
        // am Mac in einer Kopie erprobt, in der `suchen` keinen NSPopUpButton findet — erst dann die Zahl hier anpassen.
        let text = try Self.probe()
        #expect(text.components(separatedBy: "NSPopUpButton.self").count - 1 == 6)
    }
}
