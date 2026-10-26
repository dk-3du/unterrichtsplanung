// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Kein Rückweg auf eine Vorversion (v80, AP13a, E286, E297) ─────────────
// Ein Hinweis, einmal, nach den Fragen und vor der Tour — im Prüflauf stumm
// wie die beiden Nachfragen (siehe `DateiPruefungen.ersatzblaetterVorDerTour`):
// Seine Stellung zeigt die Bedingung, am Paket der Live-Test.

@Suite("Rückweg: der einmalige Hinweis gegen eine Vorversion — Fälligkeit, Merker, Wortlaut")
@MainActor
struct RueckwegPruefungen {

    private func planung() throws -> Planung {
        Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                     basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
    }

    @Test("Fällig nur mit Planung, nach der Ersteinrichtung, einmal — nie im Prüflauf; auch ohne Verschlüsselung")
    func faelligkeit() {
        func faellig(pruefstand: Bool = false, planung: Bool = true, ersteinrichtung: Bool = false,
                     gezeigt: Bool = false) -> Bool {
            Planungsspeicher.rueckwegHinweisFaellig(pruefstand: pruefstand, hatPlanung: planung,
                                                     ersteinrichtungFaellig: ersteinrichtung, gezeigt: gezeigt)
        }
        #expect(faellig(), "nach einem Update wie nach einer Neuinstallation mit beantworteter Einrichtung")
        #expect(!faellig(pruefstand: true), "im Prüflauf stumm")
        #expect(!faellig(planung: false), "ohne Planung nicht")
        #expect(!faellig(ersteinrichtung: true), "erst nach der Einrichtung")
        #expect(!faellig(gezeigt: true), "nur einmal")
    }

    @Test("Gelesen ist gelesen: Der Merker steht — und im Prüflauf bleiben die Einstellungen des Nutzers unberührt")
    func merker() throws {
        let s = Planungsspeicher(vorschau: try planung())
        #expect(!s.rueckwegHinweisGezeigt)
        s.rueckwegHinweisGelesen()
        #expect(s.rueckwegHinweisGezeigt)
        #expect(Einstellungen.speicher == nil, "im Prüflauf wird nichts in die Einstellungen geschrieben")
        #expect(Einstellungen.Schluessel.rueckwegHinweis == "unterrichtsplanung.rueckweg.hinweis")
    }

    @Test("Wortlaut des Nutzers (E297), wörtlich — und das Blatt gehört zu den Dialogen")
    func wortlaut() {
        #expect(RueckwegHinweisDialog.titel == "Bitte bei Version 2 bleiben")
        #expect(RueckwegHinweisDialog.unterzeile == "Ein Hinweis zur neuen Fassung — einmalig")
        #expect(RueckwegHinweisDialog.absaetze == [
            "Seit 2.0.0 verfügt die App über eine Lernendenverwaltung. Daran geknüpft sind zahlreiche neue Funktionen.",
            "Eine ältere Version bis einschließlich 1.9.8 verfügt über keine Lernendenverwaltung und lässt daher Eingaben, "
                + "welche bei Verwendung von Version 2.0.0 oder höher gemacht wurden, beim nächsten Sichern fallen. Bitte "
                + "deshalb keine ältere Version mehr installieren; neue Fassungen kommen über „Nach Updates suchen“.",
            "Falls eine Rückkehr dennoch notwendig ist, bitte die Lernendendaten vorher exportieren: Ablage → "
                + "„Lernende exportieren …“.",
        ])
        #expect(RueckwegHinweisDialog.knopf == "Verstanden")
        #expect(!(RueckwegHinweisDialog.absaetze + [RueckwegHinweisDialog.titel]).joined().contains("Ansicht"), "E219")
        #expect(Dialogfenster(rawValue: "rueckwegHinweis") == .rueckwegHinweis, "abbildbar über --dialog")
    }
}
