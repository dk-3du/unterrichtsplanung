// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Die Tour ohne Fenster: Schrittfolge, Angebot und Texte. Wo die Karte
/// wirklich hängt, zeigt nur `--tourtest` am echten Fenster.
@Suite("Tour durch die Oberfläche")
@MainActor
struct TourPruefungen {

    private typealias Schritt = Planungsspeicher.Tourschritt

    private func speicher(klassen: [(String, String)] = [("G6a", "Informatik")]) throws
    -> Planungsspeicher {
        let planung = Planung.leer(titel: "Tour", start: try #require(Tag(iso: "2026-08-10")),
                                   wochen: 6, basis: "",
                                   klassen: Standardkurse.aufbauen(klassen), fachfarben: [:])
        return Planungsspeicher(vorschau: planung)
    }

    @Test("Sechs Schritte mit Zeile, vier ohne — der letzte sagt dann, wo Zeilen herkommen")
    func schrittfolge() throws {
        #expect(try speicher().tourSchritte
                == [.dateien, .planung, .ansicht, .zelle, .anlegen, .frei])
        #expect(try speicher(klassen: []).tourSchritte
                == [.dateien, .planung, .ansicht, .ohneZeile])
    }

    @Test("Weiter, Zurück, Fertig — und die Stelle stimmt an jedem Punkt")
    func durchlauf() async throws {
        let s = try speicher()
        #expect(!s.tourLaeuft)
        s.tourBeginnen()
        #expect(s.tourSchritt == .dateien)
        #expect(s.tourStelle == (1, 6))
        #expect(s.tourAmAnfang && !s.tourAmEnde)

        s.tourZurueck()
        #expect(s.tourSchritt == .dateien, "am Anfang führt Zurück nirgendwohin")
        s.tourWeiter()
        s.tourWeiter()
        #expect(s.tourSchritt == .ansicht)
        #expect(s.tourStelle == (3, 6))
        s.tourZurueck()
        #expect(s.tourSchritt == .planung)

        for _ in 0..<4 { s.tourWeiter() }
        #expect(s.tourSchritt == .frei)
        #expect(s.tourAmEnde)
        s.tourWeiter()
        #expect(s.tourSchritt == nil)
        // Die Meldung kommt einen Augenblick nach der Karte.
        try await Task.sleep(for: .milliseconds(500))
        #expect(s.meldungen.last?.text.contains("Das war die Tour") == true)
    }

    @Test("Beenden räumt auf, ohne Planung beginnt nichts, über ein Blatt hinweg auch nicht")
    func beenden() async throws {
        let s = try speicher()
        s.tourBeginnen()
        s.tourWeiter()
        s.tourZelle = "G6a, KW 33"
        s.tourBeenden()
        #expect(s.tourSchritt == nil)
        #expect(s.tourZelle.isEmpty)
        s.tourBeenden()
        try await Task.sleep(for: .milliseconds(500))
        #expect(s.meldungen.last?.text.contains("Tour beendet") == true)
        #expect(s.meldungen.count == 1, "ein zweites Beenden meldet nichts")

        let leer = Planungsspeicher(vorschau: nil)
        leer.tourBeginnen()
        #expect(leer.tourSchritt == nil)
        #expect(leer.meldungen.last?.art == .warnung)

        let belegt = try speicher()
        belegt.offenerDialog = .klassen
        belegt.tourBeginnen()
        #expect(belegt.tourSchritt == nil)
    }

    @Test("Das Angebot kommt nach dem Anlegen einer Planung — einmal, und nicht über ein Blatt")
    func angebot() throws {
        let s = Planungsspeicher(vorschau: nil)
        s.tourAnbietenPruefen()
        #expect(s.offenerDialog == nil, "ohne angelegte Planung kein Angebot")

        s.neuePlanung(titel: "Erste", start: try #require(Tag(iso: "2026-08-10")),
                      wochen: 6, basis: "",
                      klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                      ersterSchultag: nil, uebernahme: [])
        s.offenerDialog = .ersteinrichtung
        s.tourAnbietenPruefen()
        #expect(s.offenerDialog == .ersteinrichtung, "kein Angebot über ein offenes Blatt")

        s.offenerDialog = nil
        s.tourAnbietenPruefen()
        #expect(s.offenerDialog == .tour)

        s.offenerDialog = nil
        s.neuePlanung(titel: "Zweite", start: try #require(Tag(iso: "2026-08-10")),
                      wochen: 6, basis: "",
                      klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                      ersterSchultag: nil, uebernahme: [])
        s.tourAnbietenPruefen()
        #expect(s.offenerDialog == nil, "gefragt wird genau einmal")
    }

    @Test("Anker und Texte: Werkzeugleiste, Beispielzelle, Zellenname im Text")
    func ankerUndTexte() {
        #expect(Schritt.dateien.anker == .werkzeug(["Neue Planung"]))
        #expect(Schritt.planung.anker == .werkzeug(["Klassen/Kurse"]))
        #expect(Schritt.ohneZeile.anker == .werkzeug(["Klassen/Kurse"]))
        #expect(Schritt.ansicht.anker == .werkzeug(["Darstellung umschalten"]))
        for schritt in [Schritt.zelle, .anlegen, .frei] { #expect(schritt.anker == .zelle) }

        #expect(Schritt.zelle.text(zelle: "G6a, KW 33").contains("G6a, KW 33"))
        #expect(Schritt.zelle.text(zelle: "").contains("ersten Zeile"))
        for schritt in Schritt.allCases {
            #expect(!schritt.titel.isEmpty)
            #expect(schritt.text(zelle: "x").count > 80, Comment(rawValue: schritt.rawValue))
        }
        #expect(Schritt.anlegen.text(zelle: "").contains("+ Vorhaben"))
        #expect(Schritt.frei.text(zelle: "").contains("Schirmsymbol"))
    }
}
