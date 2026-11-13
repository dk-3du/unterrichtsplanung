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

    /// Rückt die Uhr vor, bis die Meldung steht, die der Speicher verzögert ausspricht (300 ms nach dem Ende
    /// der Tour), mit Spielraum für eine gedehnte Frist — Zeit der Uhr, keine Wanduhr.
    private func meldungSehen(_ s: Planungsspeicher, _ uhr: Stelluhr, _ teil: String) async throws {
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.contains(teil) } }, hoechstens: .seconds(5))
        try #require(gesehen, "Meldung „\(teil)“")
    }

    @Test("E842, v97 (E1261, E1263): zehn Schritte mit Zeile, sechs ohne — „Lernende“ immer, die Kurszelle nach dem Raster")
    func schrittfolge() throws {
        let mitZeile: [Schritt] = [.dateien, .woche, .lernende, .planung, .ansicht, .zelle, .kurszelle, .kacheln, .anlegen, .frei]
        let ohneZeile: [Schritt] = [.dateien, .woche, .lernende, .planung, .ansicht, .ohneZeile]
        #expect(Planungsspeicher.tourSchritte(mitZeilen: true) == mitZeile)
        #expect(Planungsspeicher.tourSchritte(mitZeilen: false) == ohneZeile)
        // Der Speicher der Vorschau hat keine Lernendenverwaltung — „Lernende“ kommt trotzdem (E1261).
        #expect(try speicher().tourSchritte == mitZeile)
        #expect(try speicher(klassen: []).tourSchritte == ohneZeile)
    }

    @Test("Weiter, Zurück, Fertig — und die Stelle stimmt an jedem Punkt")
    func durchlauf() async throws {
        let s = try speicher()
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        #expect(!s.tourLaeuft)
        s.tourBeginnen()
        #expect(s.tourSchritt == .dateien)
        #expect(s.tourStelle == (1, 10))
        #expect(s.tourAmAnfang && !s.tourAmEnde)

        s.tourZurueck()
        #expect(s.tourSchritt == .dateien, "am Anfang führt Zurück nirgendwohin")
        s.tourWeiter()
        s.tourWeiter()
        #expect(s.tourSchritt == .lernende, "die dritte Karte zeigt seit v97 die Lernenden (E1261)")
        #expect(s.tourStelle == (3, 10))
        s.tourZurueck()
        #expect(s.tourSchritt == .woche)

        for _ in 0..<8 { s.tourWeiter() }
        #expect(s.tourSchritt == .frei, "zuletzt der Schirm (E1263)")
        #expect(s.tourAmEnde)
        s.tourWeiter()
        #expect(s.tourSchritt == nil)
        // Die Meldung kommt einen Augenblick nach der Karte — und verschwindet
        // nach 2,8 s wieder; vorgerückt wird bis zu ihr, nicht um eine feste Spanne.
        try await meldungSehen(s, uhr, "Das war die Tour")
        #expect(s.meldungen.last?.text.contains("Das war die Tour") == true)
    }

    @Test("Beenden räumt auf, ohne Planung beginnt nichts, über ein Blatt hinweg auch nicht")
    func beenden() async throws {
        let s = try speicher()
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.tourBeginnen()
        s.tourWeiter()
        s.tourZelle = "G6a, KW 33"
        s.tourBeenden()
        #expect(s.tourSchritt == nil)
        #expect(s.tourZelle.isEmpty)
        s.tourBeenden()
        try await meldungSehen(s, uhr, "Tour beendet")
        #expect(s.meldungen.last?.text.contains("Tour beendet") == true)
        #expect(s.meldungen.count == 1, "ein zweites Beenden meldet nichts")
        // Gezählt wird, was gesagt wurde — eine Meldung kann verfallen, ehe die nächste kommt.
        var gesagt = Set<UUID>()
        let weitere = await uhr.vorruecken(bis: {
            gesagt.formUnion(s.meldungen.map(\.id))
            return gesagt.count > 1
        }, hoechstens: .seconds(1))
        #expect(!weitere, "auch danach nicht")

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
                      ersterSchultag: nil, uebernahme: [], ohneMitglieder: [])
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
                      ersterSchultag: nil, uebernahme: [], ohneMitglieder: [])
        s.tourAnbietenPruefen()
        #expect(s.offenerDialog == nil, "gefragt wird genau einmal")
    }

    @Test("Anker und Texte: Werkzeugleiste, Beispielzelle, Kurszelle, Zellenname im Text")
    func ankerUndTexte() {
        #expect(Schritt.dateien.anker == .werkzeug(["Neue Planung"]))
        #expect(Schritt.woche.anker == .werkzeug(["Zur laufenden Woche"]))
        #expect(Schritt.planung.anker == .werkzeug(["Klassen/Kurse"]))
        #expect(Schritt.ohneZeile.anker == .werkzeug(["Klassen/Kurse"]))
        #expect(Schritt.ansicht.anker == .werkzeug(["Darstellung umschalten"]))
        for schritt in [Schritt.zelle, .kacheln, .anlegen, .frei] { #expect(schritt.anker == .zelle) }
        #expect(Schritt.kurszelle.anker == .kurszelle)
        #expect(Schritt.lernende.anker == .werkzeug(["Lernende"]), "am Knopf der Werkzeugleiste (E1261)")
        // Ohne Klassenkopf im Raster fällt die Karte auf das Werkzeug zurück,
        // aus dem die Zeilen kommen; die anderen Schritte haben keinen Ersatz.
        #expect(Schritt.kurszelle.ersatzanker == .werkzeug(["Klassen/Kurse"]))
        for schritt in Schritt.allCases where schritt != .kurszelle {
            #expect(schritt.ersatzanker == nil, Comment(rawValue: schritt.rawValue))
        }
        // Die Stelle im Raster: die Kurszelle am Klassenkopf (Z-GR2-01); „Lernende“ hängt seit v97 in der Werkzeugleiste.
        let stellen: [Schritt: Schritt.Rasterstelle] = [
            .kurszelle: .klassenkopf, .zelle: .zelle, .kacheln: .kacheln,
            .anlegen: .anlegenknopf, .frei: .freiknopf,
        ]
        for schritt in Schritt.allCases {
            #expect(schritt.rasterstelle == stellen[schritt], Comment(rawValue: schritt.rawValue))
            #expect((schritt.rasterstelle == nil) == (schritt.anker != .zelle && schritt.anker != .kurszelle),
                    Comment(rawValue: schritt.rawValue))
        }

        #expect(Schritt.zelle.text(zelle: "G6a, KW 33", verschluesselt: true).contains("G6a, KW 33"))
        #expect(Schritt.zelle.text(zelle: "", verschluesselt: true).contains("ersten Zeile"))
        for schritt in Schritt.allCases {
            #expect(!schritt.titel.isEmpty)
            for verschluesselt in [true, false] {
                let text = schritt.text(zelle: "G6a, KW 33", verschluesselt: verschluesselt)
                // Kurz (E842): höchstens zwei Sätze, keine Karte über 190 Zeichen; kein „Reiter“, keine Anrede. Bis 230
                // dürfen „Die Kacheln“ (E911, 223 Zeichen; E936, belegt am Abbild des Tourtests vom 29.10.2026: vier Zeilen)
                // und „Lernende“ ohne Verschlüsselung (E1262, 229 Zeichen; belegt am Tourtest vom 12.11.2026: fünf Zeilen).
                let grenze = schritt == .kacheln || (schritt == .lernende && !verschluesselt) ? 230 : 190
                #expect(text.count > 80 && text.count <= grenze,
                        Comment(rawValue: "\(schritt.rawValue), verschlüsselt \(verschluesselt): \(text.count)"))
                #expect(!text.contains("Reiter") && !text.contains("Sie ") && !text.contains(" du "),
                        Comment(rawValue: schritt.rawValue))
            }
        }
        // Geschütztes Leerzeichen: Das Plus bleibt beim Wort, wenn die Karte umbricht.
        #expect(Schritt.kurszelle.text(zelle: "", verschluesselt: true).contains("„+\u{00A0}…“"))
    }

    /// Die freigegebenen Wortlaute (E842; die Karte „Die Kacheln“ nach E911), wörtlich.
    @Test("E842, E911, E1262–E1264, E1275: Titel und Texte der zehn Karten und der Karte ohne Zeile, wie freigegeben")
    func wortlaute() {
        let soll: [(Schritt, String, String)] = [
            (.dateien, "Planungsdateien",
             "Ganz links: neue Planung (⌘N), Datei öffnen (⌘O), sichern (⌘S). Gesichert wird ohnehin laufend; „Sichern“ legt "
             + "eine Kopie zum Mitnehmen an."),
            (.woche, "Woche und Tagesliste",
             "Zur laufenden Woche springen (⌘J) und die heute anstehenden Vorhaben zum Abhaken zeigen (⌘D)."),
            (.planung, "Die Planung einrichten",
             "Klassen und Kurse mit Fächern und Farben (⌘K), Ferien (⌘E), alle Prüfungstermine (⌘R) und die Einstellungen "
             + "(⌘,) mit Zeitraum, Sicherung und Verschlüsselung."),
            (.ansicht, "Breite, Darstellung, Suche",
             "Der Regler stellt die Spaltenbreite in drei Stufen (⌘+, ⌘−), der Knopf daneben hell oder dunkel. Die Suche "
             + "ganz rechts (⌘F) blendet Kacheln aus, die nicht passen."),
            (.zelle, "Das Raster",
             "Jede Zeile ist eine Klasse oder ein Kurs, jede Spalte eine Woche; oben stehen Kalender- und Schulwoche. Diese "
             + "Zelle gehört zu G6a, KW 33."),
            (.kacheln, "Die Kacheln",
             "Jedes Vorhaben ist eine Kachel: Ein Klick wählt sie an, ein Doppelklick öffnet sie, Ziehen verschiebt sie. Dateien "
             + "und Links lassen sich auf sie ziehen und ablegen; der Rechtsklick setzt etwa Wochentag, Prüfung oder Termin."),
            (.anlegen, "Ein Vorhaben anlegen",
             "„+ Vorhaben“ unten links, ein Doppelklick auf freie Fläche oder ⌘T öffnet das Vorhaben-Blatt: Grundlegendes, "
             + "Kommentar, Prüfung, Termin, Hausaufgabe, Material, Links."),
            (.frei, "Unterrichtsfrei",
             "Der Schirm unten rechts stellt diese Klasse in dieser Woche frei, der im Spaltenkopf die ganze Woche. Ein "
             + "zweiter Klick nimmt es zurück; Ferien kommen über ⌘E."),
            (.kurszelle, "Die Kurszelle",
             "Links je Zeile die Klasse oder der Kurs mit vier Verweisen: Verwaltungsdatei (Kursbuch, Listen), Curriculum, "
             + "Sitzplan, externe Leistungsdokumentation (Noten). Ein Klick öffnet, „+\u{00A0}…“ wählt."),
            (.lernende, "Lernende",
             "Das Personen-Symbol (⌘L) öffnet die Lernendenverwaltung: Lerngruppen mit Mitgliedern, Mitteilungen, "
             + "Maßnahmen und Vereinbarungen."),
            (.ohneZeile, "Noch keine Zeile",
             "Das Raster bekommt seine Zeilen aus „Klassen/Kurse“ (⌘K). Danach zeigt die Tour dort Raster, Kurszelle und "
             + "Kacheln — Hilfe → Tour durch die Oberfläche."),
        ]
        // Ohne Verschlüsselung (E1262, E1275): 229 Zeichen — über den 190 aus E842, wie „Die Kacheln“ (E936) bis 230;
        // belegt am Abbild des Tourtests am Paket vom 12.11.2026 (nur im Arbeitsverzeichnis des Autors): fünf Zeilen, nichts
        // abgeschnitten.
        let ohne = "Das Personen-Symbol öffnet die Lernendenverwaltung: Lerngruppen mit Mitgliedern, Mitteilungen, Maßnahmen und Vereinbarungen. Ein Klick auf dieses Symbol startet nach einer Rückfrage die Einrichtung der benötigten Verschlüsselung."
        #expect(Schritt.lernende.text(zelle: "", verschluesselt: false) == ohne)
        #expect(ohne.count <= 230)
        // Jede Karte genau einmal; die Folge der Tour prüft `schrittfolge` (BI4-05).
        let folge = soll.map { $0.0 }
        #expect(folge.count == Schritt.allCases.count && Set(folge) == Set(Schritt.allCases))
        for (schritt, titel, text) in soll {
            #expect(schritt.titel == titel, Comment(rawValue: schritt.rawValue))
            #expect(schritt.text(zelle: "G6a, KW 33", verschluesselt: true) == text, Comment(rawValue: schritt.rawValue))
        }
        // Das Angebot vor dem Start (E843, E1280).
        #expect(Planungsspeicher.tourAngebot == "Die Tour führt von links nach rechts durch die Werkzeugleiste, dann durch "
                + "eine Zelle des Rasters samt der Kurszelle am linken Rand.")
    }

    @Test("E1262, E1280 (R97-W2-04, R97-W2N-03): Karte und Angebot lesen Lage und Wortlaut aus dem Speicher")
    func karteLiestDieLage() throws {
        // Am Quelltext: Die Karte ist ein Popover; ihren Text liest kein Prüfstand.
        let datei = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Tour.swift")
        let text = try String(contentsOf: datei, encoding: .utf8)
        let zeile = "schritt.text(zelle: speicher.tourZelle, verschluesselt: speicher.tourVerschluesselt)"
        #expect(text.components(separatedBy: zeile).count - 1 == 1)
        #expect(text.components(separatedBy: "Text(Planungsspeicher.tourAngebot)").count - 1 == 1, "das Angebot (E1280)")
    }
}
