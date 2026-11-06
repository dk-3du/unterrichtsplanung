// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Kein Rückweg auf eine Vorversion (v80, AP13a, E286, E297; seit 2.5.0 E971–E973, E981) ──
// Seit 2.5.0 macht ein neuer Merker den Hinweis fällig; der alte sagt nur noch den Weg (E972).
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

    @Test("Gelesen ist gelesen: der neue Merker seit 2.5.0 (E972) — im Prüflauf bleiben die Einstellungen unberührt")
    func merker() throws {
        let s = Planungsspeicher(vorschau: try planung())
        #expect(!s.rueckwegHinweisGezeigt)
        s.rueckwegHinweisGelesen()
        #expect(s.rueckwegHinweisGezeigt)
        #expect(Einstellungen.speicher == nil, "im Prüflauf wird nichts in die Einstellungen geschrieben")
        #expect(Einstellungen.Schluessel.rueckwegHinweis == "unterrichtsplanung.rueckweg.hinweis.2-5", "der neue Merker")
        #expect(Einstellungen.Schluessel.rueckwegHinweisBis24 == "unterrichtsplanung.rueckweg.hinweis",
                "der alte — nur noch gelesen, für den Weg")
    }

    @Test("Der Weg nach dem alten Merker (E972): gesetzt — Update seit 2.0.0 (b); sonst — vor 2.0.0 oder neu installiert (a)")
    func weg() {
        #expect(Rueckwegweg.aus(alterMerker: true) == .seitZweiNull)
        #expect(Rueckwegweg.aus(alterMerker: false) == .vorZweiNull)
        #expect(Rueckwegweg.aus(alterMerker: nil) == .vorZweiNull, "Neuinstallation wie (a)")
        let s = Planungsspeicher(vorschau: nil)
        #expect(s.rueckwegHinweisWeg == .vorZweiNull, "im Prüflauf ohne Einstellungen: (a)")
    }

    @Test("Wortlaut beider Wege (E973, E981), wörtlich — keine Anleitung zum Rückweg (E971); das Blatt gehört zu den Dialogen")
    func wortlaut() {
        #expect(RueckwegHinweisDialog.titel == "Bitte bei Version 2.5.0 oder höher bleiben")
        #expect(RueckwegHinweisDialog.unterzeile == "Ein Hinweis zur neuen Fassung — einmalig")
        let bitte = "Bitte deshalb keine ältere Version mehr installieren; neue Fassungen kommen über „Nach Updates suchen“."
        #expect(RueckwegHinweisDialog.absaetze(.vorZweiNull) == [
            "Seit 2.0.0 verfügt die App über eine Lernendenverwaltung. Daran geknüpft sind zahlreiche neue Funktionen.",
            "Eine ältere Version bis einschließlich 1.9.8 verfügt über keine Lernendenverwaltung und lässt daher Eingaben, "
                + "welche bei Verwendung von Version 2.0.0 oder höher gemacht wurden, beim nächsten Sichern fallen.",
            "Seit 2.5.0 speichert die App die Lernendendaten und die Sitzpläne in einer neuen Fassung, die ältere Versionen "
                + "nicht lesen können.",
            bitte,
        ])
        #expect(RueckwegHinweisDialog.absaetze(.seitZweiNull) == [
            "Seit 2.5.0 gibt es keine Obergrenze mehr für die Zahl der Personen je Lerngruppe, Anliegen und Termin und für die "
                + "Tische je Sitzplan.",
            "Dafür speichert die App die Lernendendaten und die Sitzpläne in einer neuen Fassung, die ältere Versionen nicht "
                + "lesen können.",
            bitte,
        ])
        #expect(RueckwegHinweisDialog.knopf == "Verstanden")
        let alle = RueckwegHinweisDialog.absaetze(.vorZweiNull) + RueckwegHinweisDialog.absaetze(.seitZweiNull)
        #expect(!(alle + [RueckwegHinweisDialog.titel]).joined().contains("Ansicht"), "E219")
        #expect(!alle.joined().contains("exportieren"), "keine Anleitung zum Rückweg (E971)")
        #expect(Dialogfenster(rawValue: "rueckwegHinweis") == .rueckwegHinweis, "abbildbar über --dialog")
    }

    @Test("Der alte Merker wird nur noch gelesen — für den Weg (E972); er macht nichts fällig und wird nicht geschrieben")
    func alterMerkerNurGelesen() throws {
        let quellen = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung")
        let name = "rueckwegHinweisBis24"
        let definition = "static let rueckwegHinweisBis24 = \"unterrichtsplanung.rueckweg.hinweis\""
        let lesen = "Rueckwegweg.aus(alterMerker: Einstellungen.wert(Einstellungen.Schluessel.rueckwegHinweisBis24))"
        let kette = "\"unterrichtsplanung.rueckweg.hinweis\""
        func zahl(_ muster: String, _ text: String) -> Int { text.components(separatedBy: muster).count - 1 }
        var stellen: [String: Int] = [:]
        var (definiert, gelesen, ketten) = (0, 0, 0)
        let dateien = try #require(FileManager.default.enumerator(at: quellen, includingPropertiesForKeys: nil))
        for case let datei as URL in dateien where datei.pathExtension == "swift" {
            let text = try String(contentsOf: datei, encoding: .utf8)
            if zahl(name, text) > 0 { stellen[datei.lastPathComponent] = zahl(name, text) }
            if datei.lastPathComponent == "Einstellungen.swift" {
                definiert += zahl(definition, text)
            } else {
                gelesen += zahl(lesen, text)
                ketten += zahl(kette, text)
            }
        }
        // Vorkommen, nicht Zeilen (Z-BB6-01): ein Schreiben in derselben Zeile wie das Lesen fiele sonst nicht auf.
        #expect(stellen["Einstellungen.swift"] == 1 && definiert == 1, "in den Einstellungen nur die Definition: \(stellen)")
        #expect(stellen.values.reduce(0, +) == 2 && gelesen == 1, "sonst nur das Lesen für den Weg: \(stellen)")
        #expect(ketten == 0, "die Zeichenkette des alten Schlüssels steht nur in den Einstellungen")
        // Z-BB8-W3-08: auch kein Skript der Fassung (`runde.py`, `*.sh`) fasst die Merker an.
        let fassung = quellen.deletingLastPathComponent().deletingLastPathComponent()
        let skripte = try FileManager.default.contentsOfDirectory(at: fassung, includingPropertiesForKeys: nil)
            .filter { ["py", "sh"].contains($0.pathExtension) }
        #expect(!skripte.isEmpty)
        for skript in skripte {
            #expect(!(try String(contentsOf: skript, encoding: .utf8)).contains("rueckweg.hinweis"), "\(skript.lastPathComponent)")
        }
    }
}
