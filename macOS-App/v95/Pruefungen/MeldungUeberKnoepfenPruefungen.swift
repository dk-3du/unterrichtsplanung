// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// v92 (E1061): In schmalen Bögen am Blatt „Lernende“ steht die jüngste Meldung auf eigener Zeile über den Knöpfen — in der
/// Lücke neben drei Knöpfen blieben im Bogen „Rückmeldungsliste“ nur zwei Wörter. Breite Blätter bleiben, wie sie sind.
@Suite("Meldung im Fuß: in schmalen Bögen am Blatt „Lernende“ auf eigener Zeile (E1061)")
@MainActor
struct MeldungUeberKnoepfenPruefungen {
    @Test("E1061: schmale Bögen am Blatt „Lernende“ — eigene Zeile; das Blatt selbst und andere Blätter wie bisher")
    func wann() {
        for breite: CGFloat in [520, 560, 640] {
            #expect(Meldungszeile.ueberDenKnoepfen(.lernende, breite: breite), "\(breite)")
        }
        // Der Rand: unter 720 (H1-05).
        #expect(Meldungszeile.ueberDenKnoepfen(.lernende, breite: 719), "719")
        #expect(!Meldungszeile.ueberDenKnoepfen(.lernende, breite: 720), "720")
        #expect(!Meldungszeile.ueberDenKnoepfen(.lernende, breite: 1000), "das Blatt „Lernende“")
        #expect(!Meldungszeile.ueberDenKnoepfen(.vorhaben, breite: 640), "der Material-Bogen am Vorhaben-Blatt")
        #expect(!Meldungszeile.ueberDenKnoepfen(.klassen, breite: 720), "„Farbe wählen“ an ⌘K")
        #expect(!Meldungszeile.ueberDenKnoepfen(nil, breite: 520), "ohne eigene Meldungszeile")
    }

    @Test("E1061 am Quelltext: Die Meldung steht dann über den Knöpfen, die Lücke im Fuß bleibt leer")
    func verdrahtet() throws {
        let datei = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Gestaltung/Dialograhmen.swift")
        let text = try String(contentsOf: datei, encoding: .utf8)
        #expect(text.contains("let darueber = eigene && Meldungszeile.ueberDenKnoepfen(meldungsblatt, breite: breite)"))
        #expect(text.contains(".environment(\\.meldungImFuss, eigene && !darueber)"), "die Lücke zeigt dann nichts")
        #expect(text.contains("if darueber, let speicher,"), "die Zeile darüber")
        #expect(text.contains("                Meldungskapseln(kompakt: true, nurJuengste: true)\n"
                              + "                    .environment(speicher)\n"
                              + "                    .frame(maxWidth: .infinity, alignment: .leading)"),
                "dort nur die jüngste Meldung, wie in der Lücke (E856)")
    }
}
