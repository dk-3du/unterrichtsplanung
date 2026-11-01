// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import Foundation
import PDFKit
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die Rückmeldungsliste im Blatt „Lernende“: Bogen, Druckweg, Druckansicht ──
// Der Bogen über reine Funktionen: Knöpfe aus Auswahl und Kennwort (E406, E408), nichts vorgewählt,
// Dateiname, Kopf mit Stand; das Sichern schreibt nur das verschlüsselte PDF (E405). Der Druck: nur ein
// Auftrag an den Drucker bekommt Seiten, PDF-Wege des Druckdialogs werden abgewiesen (E407); die
// Druckansicht trägt alle Seiten in ihrer Folge (E411) — am echten Druckvorgang in eine Datei geprüft.

@Suite("Rückmeldungsliste: Bogen, Druckweg, Druckansicht", .serialized)
@MainActor
struct RueckmeldungslisteBogenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let kennwort = "Elternbriefe 2026"
    private let stand = Tag(jahr: 2026, monat: 10, tagImMonat: 11)

    /// Ein eigener Ordner im Ablageort des Laufs — er bleibt liegen.
    private func ordner(_ name: String) throws -> URL {
        let wurzel = try #require(ProcessInfo.processInfo.environment["PLANUNGSORDNER"])
        let ziel = URL(fileURLWithPath: wurzel, isDirectory: true)
            .appending(component: "rueckmeldungsbogen-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    // ── Der Bestand ───────────────────────────────────────────────────────

    private func person(_ id: String, _ vorname: String, _ nachname: String) -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, rufname: "", angelegt: "", geaendert: "", archiviert: "")
    }

    /// Eine Lerngruppe trägt kein Fach (E656).
    private func gruppe(_ id: String, _ name: String, _ mitglieder: [String] = []) -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: mitglieder, zeilen: [], skalen: [:],
                   halbjahreswechsel: "", geaendert: "", archiviert: "")
    }

    private func anliegen(_ id: String, _ art: Anliegenart, _ titel: String, gruppe: String, datum: String,
                          _ betroffene: [String]) -> Anliegen {
        Anliegen(id: id, art: art, titel: titel, lerngruppe: gruppe, betroffene: betroffene, datum: datum, frist: "",
                 notiz: "", angelegt: "", geaendert: "")
    }

    /// 6a mit zwei Mitteilungen und einer Maßnahme; dazu eine Mitteilung des Förderkurses.
    private func bestand() -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p1", schuljahr: "2026/27", jetzt: "")
        b.lernende = [person("ada", "Ada", "Zimmer"), person("ben", "Ben", "Abel"), person("olaf", "Olaf", "Ost")]
        b.lerngruppen = [gruppe("g1", "6a", ["ada", "ben"]), gruppe("g2", "Förderkurs", ["olaf"])]
        b.anliegen = [anliegen("m1", .mitteilung, "Wandertag", gruppe: "g1", datum: "2026-09-01", ["ada", "ben"]),
                      anliegen("m3", .mitteilung, "Ausflug", gruppe: "g2", datum: "2026-09-05", ["olaf"]),
                      anliegen("n1", .massnahme, "Nacharbeit", gruppe: "g1", datum: "2026-09-10", ["ben"]),
                      anliegen("m2", .mitteilung, "Fotos", gruppe: "g1", datum: "", ["ada"])]
        b.rueckmeldungen = [Rueckmeldung(anliegen: "m1", lernender: "ben", stand: .erledigt, datum: "2026-09-02",
                                         notiz: "", geaendert: "")]
        return b
    }

    /// Eine Liste über sieben Seiten: drei Spaltengruppen mal zwei Bänder, dann der Anhang (E411).
    private func siebenSeiten() -> Liste {
        let spalten = "ABCDEFGHIJKLMNOPQRST".map { Liste.Spalte(titel: "Brief \($0)") }
        let zeilen = (1...40).map { i in
            Liste.Zeile(name: String(format: "Kind %02d, Vera", i), zellen: spalten.map { _ in "x" })
        }
        return Liste(kopf: ["6a", "Rückmeldungsliste", "Stand 11.10.2026"], namensspalte: "Name",
                     spalten: spalten, zeilen: zeilen, legende: [.init(zeichen: "x", bedeutung: "Probe")],
                     anhangstitel: "Notizen",
                     anhang: [.init(ueberschrift: "Brief A", eintraege: [.init(name: "Kind 01, Vera", text: "Notiz")])])
    }

    private func pdfDaten(_ ausgabe: Listensatz.Ausgabe) -> Data? {
        if case .verschluesselt(let d) = ausgabe { return d }
        return nil
    }

    // ── Der Bogen (E406, E408) ────────────────────────────────────────────

    @Test("E408/E406: beide Knöpfe gesperrt ohne gewählte Mitteilung der Gruppe; „Als PDF sichern“ zudem ohne taugliches, zweimal gleiches Kennwort")
    func knoepfe() {
        let ms = ["m1", "m2"]
        func k(_ gewaehlt: Set<String>, _ k1: String, _ k2: String) -> Rueckmeldungslistenbogen.Knoepfe {
            Rueckmeldungslistenbogen.knoepfe(gewaehlt: gewaehlt, mitteilungen: ms, kennwort: k1, wiederholung: k2)
        }
        #expect(k([], kennwort, kennwort) == .init(sichern: false, drucken: false), "ohne Auswahl beide gesperrt")
        #expect(k(["m3", "n1"], kennwort, kennwort) == .init(sichern: false, drucken: false),
                "eine fremde Mitteilung und eine Maßnahme sind keine Auswahl")
        #expect(k(["m1"], "", "") == .init(sichern: false, drucken: true), "Drucken braucht kein Kennwort")
        #expect(k(["m1"], kennwort, "Elternbriefe 202") == .init(sichern: false, drucken: true), "Wiederholung weicht ab")
        #expect(k(["m1"], kennwort, "") == .init(sichern: false, drucken: true), "nur einmal getippt")
        #expect(k(["m1"], "elf Zeichen", "elf Zeichen") == .init(sichern: false, drucken: true), "zu kurz")
        #expect(k(["m1"], "Straße am Meer 12", "Straße am Meer 12") == .init(sichern: false, drucken: true), "kein ASCII")
        #expect(k(["m1", "m3"], kennwort, kennwort) == .init(sichern: true, drucken: true))
        #expect(k(["m2"], "123456789012", "123456789012") == .init(sichern: true, drucken: true))
    }

    @Test("E406: der Einwand live aus dem Listensatz, dann die Gleichheit der Wiederholung; leer nichts")
    func kennworthinweis() {
        let h = Rueckmeldungslistenbogen.kennworthinweis
        #expect(h("", "") == nil, "vor dem Tippen kein Einwand")
        #expect(h("kurz", "") == Listensatz.kennwortEinwand("kurz") && h("kurz", "")?.contains("12") == true)
        #expect(h("", "etwas") == Listensatz.kennwortEinwand(""), "Wiederholung ohne Kennwort")
        #expect(h("Straße am Meer 12", "") == Listensatz.kennwortEinwand("Straße am Meer 12"))
        #expect(h(kennwort, "") == nil, "die Wiederholung steht noch aus")
        #expect(h(kennwort, "Elternbriefe 202") == Rueckmeldungslistenbogen.wiederholungWeichtAb)
        #expect(h("kurz", "kurz2") == Listensatz.kennwortEinwand("kurz"), "erst der Einwand, dann die Gleichheit")
        #expect(h(kennwort, kennwort) == nil)
    }

    @Test("E408: nichts vorgewählt; eine Vorgabe (Prüfstand, Abbild) nur mit Mitteilungen der Gruppe")
    func startauswahl() {
        let ms = ["m1", "m2"]
        #expect(Rueckmeldungsbogenvorgabe() == Rueckmeldungsbogenvorgabe(auswahl: [], kennwort: "", wiederholung: ""))
        #expect(Rueckmeldungslistenbogen.startauswahl(Rueckmeldungsbogenvorgabe(), mitteilungen: ms).isEmpty)
        #expect(Rueckmeldungslistenbogen.startauswahl(.init(auswahl: ["m2", "m3"]), mitteilungen: ms) == ["m2"])
    }

    @Test("Zählung, Zeile je Mitteilung, Knopf im Blatt")
    func anzeige() {
        let ms = ["m1", "m2"]
        #expect(Rueckmeldungslistenbogen.zaehlung(gewaehlt: ["m1", "m3"], mitteilungen: ms) == "1 von 2 gewählt")
        #expect(Rueckmeldungslistenbogen.zaehlung(gewaehlt: [], mitteilungen: ms) == "0 von 2 gewählt")
        let b = bestand()
        #expect(Rueckmeldungslistenbogen.mitteilungszeile(b.anliegen[0]) == "Wandertag · 01.09.2026")
        #expect(Rueckmeldungslistenbogen.mitteilungszeile(b.anliegen[3]) == "Fotos", "ohne Tag nur der Titel")
        let ohne = Rueckmeldungslistenbogen.knopf(mitteilungen: 0)
        #expect(ohne.gesperrt && ohne.hilfe == Rueckmeldungslistenbogen.knopfhilfeOhneMitteilung)
        let mit = Rueckmeldungslistenbogen.knopf(mitteilungen: 2)
        #expect(!mit.gesperrt && mit.hilfe == Rueckmeldungslistenbogen.knopfhilfe)
        #expect(Rueckmeldungslistenbogen.knopftitel == "Rückmeldungsliste …")
        #expect(Rueckmeldungslistenbogen.sichernTitel == "Als PDF sichern (verschlüsselt) …")
        #expect(Rueckmeldungslistenbogen.druckenTitel == "Drucken …")
    }

    @Test("E761: Hilfetexte am Bogen — gesperrt mit eigenen Texten; „Anlegen“ und „Zeilen wählen …“ behalten ihren Wortlaut")
    func hilfetexte() {
        #expect(Knopfhilfe.alleWaehlen == "Alle Mitteilungen der Lerngruppe wählen")
        #expect(Knopfhilfe.auswahlAufheben == "Keine Mitteilung wählen")
        let drucken = "Die Liste der gewählten Mitteilungen auf Papier — die PDF-Wege des Druckdialogs weist die App ab"
        let sichern = "Die Liste als PDF, verschlüsselt mit dem Kennwort oben"
        #expect(Knopfhilfe.drucken(gesperrt: false) == drucken)
        #expect(Knopfhilfe.sichern(gesperrt: false) == sichern)
        #expect(Knopfhilfe.drucken(gesperrt: true) == "Erst eine Mitteilung wählen")
        #expect(Knopfhilfe.sichern(gesperrt: true) == "Erst eine Mitteilung wählen und das Kennwort zweimal gleich eingeben")
        // Gesperrt, wie der Bogen die Knöpfe sperrt (E406, E408): ohne Auswahl beide, ohne Kennwort nur das Sichern.
        let ohneAuswahl = Rueckmeldungslistenbogen.knoepfe(gewaehlt: [], mitteilungen: ["m1"], kennwort: kennwort,
                                                           wiederholung: kennwort)
        #expect(Knopfhilfe.drucken(gesperrt: !ohneAuswahl.drucken) == "Erst eine Mitteilung wählen")
        let ohneKennwort = Rueckmeldungslistenbogen.knoepfe(gewaehlt: ["m1"], mitteilungen: ["m1"], kennwort: "",
                                                            wiederholung: "")
        #expect(Knopfhilfe.sichern(gesperrt: !ohneKennwort.sichern)
                == "Erst eine Mitteilung wählen und das Kennwort zweimal gleich eingeben")
        #expect(Knopfhilfe.drucken(gesperrt: !ohneKennwort.drucken) == drucken)
        // Wortlaut bleibt, gezeigt auch gesperrt (Z-AW5bN-06).
        #expect(Knopfhilfe.mitteilungAnlegen == "Eine Mitteilung an alle Mitglieder dieser Lerngruppe anlegen, mit dem heutigen "
                + "Tag (⏎)")
        #expect(Knopfhilfe.zeilenWaehlen == "Die Zeilen dieser Planung wählen, mit denen die Lerngruppe verknüpft ist — eine "
                + "Zeile kann mehrere tragen")
    }

    @Test("E775: „Titel · Tag“ mit Jahr im Bogen und in der Wahl unter der Rücklaufliste — nur der Spaltenkopf nennt den Tag vorn, ohne Jahr (E739)")
    func titelUndTag() {
        let b = bestand()
        #expect(Ruecklaufliste.wahltitel(b.anliegen[0]) == "Wandertag · 01.09.2026", "die Wahl unter der Tabelle")
        #expect(Ruecklaufliste.wahltitel(b.anliegen[0]) == Rueckmeldungslistenbogen.mitteilungszeile(b.anliegen[0]),
                "wie die Zeile im Bogen")
        #expect(Ruecklaufliste.kopftitel(b.anliegen[0]) == "01.09. · Wandertag", "der Spaltenkopf bleibt (E739)")
        #expect(Ruecklaufliste.wahltitel(b.anliegen[3]) == "Fotos", "ohne Tag nur der Titel")
    }

    @Test("E738: Der Fuß unter den Kennwortfeldern sagt, wann „Als PDF sichern (verschlüsselt) …“ wählbar ist")
    func kennwortFussNenntDenKnopf() {
        #expect(Rueckmeldungslistenbogen.kennwortFuss == "Mindestens 12, höchstens 32 Zeichen, nur ASCII — keine Umlaute, "
                + "kein ß. „Als PDF sichern (verschlüsselt) …“ ist erst wählbar, wenn das Kennwort zweimal gleich getippt ist. "
                + "Die App merkt sich das Kennwort nicht; getrennt vom PDF weitergeben.")
        // Nennt den Knopf, wie er heißt — auch nach einer Umbenennung (Z-AW5bN-05).
        #expect(Rueckmeldungslistenbogen.kennwortFuss.contains("„\(Rueckmeldungslistenbogen.sichernTitel)“"))
    }

    @Test("Dateiname wie beim Sitzplan, nur mit der Lerngruppe (E656); Titel des Druckauftrags")
    func namen() {
        let heute = Tag.heute.iso
        #expect(Rueckmeldungslistenbogen.dateiname(gruppe("g1", "6a")) == "Rückmeldungsliste_6a_\(heute).pdf")
        #expect(Rueckmeldungslistenbogen.dateiname(gruppe("g2", "Förderkurs")) == "Rückmeldungsliste_Förderkurs_\(heute).pdf")
        #expect(Rueckmeldungslistenbogen.dateiname(gruppe("g3", "7/8 AG")) == "Rückmeldungsliste_7-8_AG_\(heute).pdf")
        #expect(Rueckmeldungslistenbogen.auftragstitel(gruppe("g1", "6a")) == "Rückmeldungsliste 6a")
    }

    // ── Sichern (E405, E406, E411) ────────────────────────────────────────

    @Test("E405/E411: das PDF aus dem Bestand — verschlüsselt, Kopf mit Lerngruppe, Schuljahr und Stand; ohne Auswahl oder mit schwachem Kennwort keines")
    func pdf() throws {
        let ausgabe = Rueckmeldungslistenbogen.pdf(bestand(), gruppe: "g1", auswahl: ["m1"], kennwort: kennwort,
                                                   stand: stand)
        let daten = try #require(pdfDaten(ausgabe))
        #expect(Listensatz.verschluesselungBelegt(daten, kennwort: kennwort))
        let dokument = try #require(PDFDocument(data: daten))
        #expect(dokument.isLocked && dokument.unlock(withPassword: kennwort))
        let text = try #require(dokument.page(at: 0)?.string)
        #expect(text.contains("6a · Rückmeldungsliste · Schuljahr 2026/27 · Stand 11.10.2026"), "kein Fach im Kopf (AT9a)")
        #expect(text.contains("Abel, Ben") && text.contains("Wandertag") && !text.contains("Fotos"))
        for fremd in [Set<String>(), ["m3"], ["n1"]] {
            #expect(Rueckmeldungslistenbogen.pdf(bestand(), gruppe: "g1", auswahl: fremd, kennwort: kennwort, stand: stand)
                    == .abgewiesen(Rueckmeldungslistenbogen.ohneAuswahl), "\(fremd)")
        }
        let einwand = try #require(Listensatz.kennwortEinwand("kurz"))
        #expect(Rueckmeldungslistenbogen.pdf(bestand(), gruppe: "g1", auswahl: ["m1"], kennwort: "kurz", stand: stand)
                == .abgewiesen(einwand))
    }

    @Test("E405: geschrieben wird genau das verschlüsselte PDF, mit Meldung; scheitert das Schreiben, eine Warnung")
    func schreiben() throws {
        let ablage = try ordner("schreiben")
        let daten = try #require(pdfDaten(Rueckmeldungslistenbogen.pdf(bestand(), gruppe: "g1", auswahl: ["m1", "m2"],
                                                                      kennwort: kennwort, stand: stand)))
        let ziel = ablage.appending(component: "liste.pdf")
        let gut = Listendruck.schreiben(daten, nach: ziel, gruppe: "6a")
        #expect(gut.art == .hinweis && gut.text == Rueckmeldungslistenbogen.gesichert("6a"))
        #expect(gut.text == "Die Rückmeldungsliste „6a“ ist als verschlüsseltes PDF gesichert — es öffnet nur "
                + "mit dem Kennwort.")
        let gelesen = try Data(contentsOf: ziel)
        #expect(gelesen == daten && Listensatz.verschluesselungBelegt(gelesen, kennwort: kennwort), "nie Klartext auf der Platte")
        let fehl = Listendruck.schreiben(daten, nach: ablage.appending(component: "fehlt/liste.pdf"), gruppe: "6a")
        #expect(fehl.art == .warnung && fehl.text.hasPrefix("Die PDF-Datei konnte nicht geschrieben werden: "))
    }

    // ── Der Druckweg (E407) ───────────────────────────────────────────────

    @Test("E407: nur ein Auftrag an den Drucker bekommt Seiten — „Als PDF sichern“, „In Vorschau öffnen“, Arbeitsabläufe und unbestimmte Ziele nicht")
    func druckweg() {
        #expect(Listendruck.druckweg(auftrag: .spool, ziel: .drucker) == .drucker)
        #expect(Listendruck.druckweg(auftrag: .save, ziel: .drucker) == .pdfWeg, "Als PDF sichern")
        #expect(Listendruck.druckweg(auftrag: .preview, ziel: .drucker) == .pdfWeg, "In Vorschau öffnen")
        for ziel: Listendruck.Druckziel in [.datei, .fax, .vorschau, .pdfArbeitsablauf, .unbekannt] {
            #expect(Listendruck.druckweg(auftrag: .spool, ziel: ziel) == .pdfWeg, "\(ziel)")
        }
        #expect(Listendruck.druckweg(auftrag: .cancel, ziel: .drucker) == .abgebrochen)
        #expect(Listendruck.druckweg(auftrag: .cancel, ziel: .datei) == .abgebrochen)
        #expect(Listendruck.druckweg(auftrag: NSPrintInfo.JobDisposition(rawValue: "NSPrintUnbekannt"), ziel: .drucker)
                == .pdfWeg, "ein unbekannter Auftrag gilt als PDF-Weg")
    }

    @Test("E407: die Ziele des Drucksystems — Drucker, Datei, Fax, Vorschau, PDF-Arbeitsablauf; alles andere unbekannt")
    func druckziel() {
        typealias Z = Listendruck.Druckziel
        #expect(Z(pm: PMDestinationType(kPMDestinationPrinter)) == .drucker)
        #expect(Z(pm: PMDestinationType(kPMDestinationFile)) == .datei)
        #expect(Z(pm: PMDestinationType(kPMDestinationFax)) == .fax)
        #expect(Z(pm: PMDestinationType(kPMDestinationPreview)) == .vorschau)
        #expect(Z(pm: PMDestinationType(kPMDestinationProcessPDF)) == .pdfArbeitsablauf)
        #expect(Z(pm: PMDestinationType(kPMDestinationInvalid)) == .unbekannt)
        #expect(Z(pm: 99) == .unbekannt)
    }

    @Test("E407/E411: gezeichnet nur an den Drucker, ein PDF-Weg abgewiesen; Seiten untereinander, die erste oben; eingepasst, mittig, Seitenverhältnis gewahrt")
    func seitenUndEinpassung() {
        #expect(Listendruck.behandlung(.drucker) == .zeichnen)
        #expect(Listendruck.behandlung(.pdfWeg) == .abweisen)
        #expect(Listendruck.behandlung(.abgebrochen) == .nichts)
        let mass = CGSize(width: 800, height: 500)
        #expect(Listendruck.seitenrahmen(1, seiten: 3, mass: mass) == NSRect(x: 0, y: 1000, width: 800, height: 500))
        #expect(Listendruck.seitenrahmen(3, seiten: 3, mass: mass) == NSRect(x: 0, y: 0, width: 800, height: 500))
        let a4 = CGRect(x: 0, y: 0, width: 842, height: 595)
        #expect(a4.applying(Listendruck.einpassung(a4, in: CGRect(x: 10, y: 20, width: 421, height: 595)))
                == CGRect(x: 10, y: 168.75, width: 421, height: 297.5), "halb so groß, senkrecht mittig")
        #expect(a4.applying(Listendruck.einpassung(a4, in: CGRect(x: 0, y: 0, width: 1684, height: 595)))
                == CGRect(x: 421, y: 0, width: 842, height: 595), "waagerecht mittig, nicht verzerrt")
        let versetzt = CGRect(x: 100, y: 50, width: 842, height: 595)
        #expect(versetzt.applying(Listendruck.einpassung(versetzt, in: a4)) == a4, "der Ursprung des Kastens zählt")
    }

    // ── Die Druckansicht ──────────────────────────────────────────────────

    @MainActor
    private final class Zaehler { var zahl = 0 }

    @Test("E407: Das Blatt meldet einen PDF-Weg einmal, einen abgebrochenen Auftrag nicht; die Seiten nennt es immer alle")
    func blattWeistAb() throws {
        let dokument = try #require(Listensatz.druckschriftstueck(siebenSeiten()))
        let abgewiesen = Zaehler()
        let blatt = try #require(Listenblatt(dokument, mass: CGSize(width: 794, height: 547)) { abgewiesen.zahl += 1 })
        #expect(blatt.seitenzahl == 7 && blatt.frame.size == CGSize(width: 794, height: 547 * 7))
        let alle = NSRange(location: 1, length: 7)
        var bereich = NSRange()
        blatt.wegLesen = { .drucker }
        #expect(blatt.knowsPageRange(&bereich) && bereich == alle)
        #expect(abgewiesen.zahl == 0)
        blatt.wegLesen = { .pdfWeg }
        #expect(blatt.knowsPageRange(&bereich) && bereich == alle, "ohne Seiten zeigte AppKit einen Fehler")
        _ = blatt.knowsPageRange(&bereich)
        #expect(abgewiesen.zahl == 1, "einmal je Vorgang")
        blatt.wegLesen = { .abgebrochen }
        #expect(blatt.knowsPageRange(&bereich) && bereich == alle && abgewiesen.zahl == 1, "abgebrochen ohne Meldung")
        #expect(blatt.rectForPage(1) == NSRect(x: 0, y: 547 * 6, width: 794, height: 547))
    }

    @Test("E407/E411: der Druckvorgang — mit Druckdialog, A4 quer, als Auftrag an den Drucker begonnen, alle Seiten im Blatt")
    func vorgang() throws {
        let angaben = Drucken.druckangaben()
        angaben.jobDisposition = .save
        let vorgang = try #require(Listendruck.vorgang(siebenSeiten(), titel: "Rückmeldungsliste 6a",
                                                       angaben: angaben) {})
        #expect(vorgang.showsPrintPanel && vorgang.showsProgressPanel)
        #expect(vorgang.printInfo.jobDisposition == .spool, "die Vorschau im Dialog zeigt die Seiten")
        #expect(vorgang.printInfo.orientation == .landscape)
        #expect(vorgang.jobTitle == "Rückmeldungsliste 6a")
        #expect((vorgang.view as? Listenblatt)?.seitenzahl == 7)
    }

    /// Ein Druckvorgang an den Drucker, ohne Dialog und ohne Fortschritt in eine Datei umgeleitet — wie
    /// `DruckPruefungen.ausdruckIstNichtLeer`; AppKit zeigt dabei nichts an. Der Weg ist vorgegeben: Mit dem echten
    /// Weg (`.save`) bräche das Blatt den Auftrag ab.
    private func druckInDatei(_ name: String) throws -> (lief: Bool, datei: URL, abgewiesen: Int) {
        if NSApplication.shared.activationPolicy() != .accessory {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        let angaben = Drucken.druckangaben()
        angaben.paperSize = NSSize(width: 842, height: 595)
        Drucken.raender(angaben)
        let abgewiesen = Zaehler()
        let vorgang = try #require(Listendruck.vorgang(siebenSeiten(), titel: "Probe", angaben: angaben) {
            abgewiesen.zahl += 1
        })
        let blatt = try #require(vorgang.view as? Listenblatt)
        blatt.wegLesen = { .drucker }
        let ziel = try ordner(name).appending(component: "druck.pdf")
        vorgang.printInfo.jobDisposition = .save
        vorgang.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = ziel
        vorgang.showsPrintPanel = false
        vorgang.showsProgressPanel = false
        return (vorgang.run(), ziel, abgewiesen.zahl)
    }

    @Test("E411: an den Drucker alle sieben Seiten in ihrer Folge — Kopf, Namen, „Seite n von 7“")
    func druckTraegtAlleSeiten() throws {
        let (lief, ziel, abgewiesen) = try druckInDatei("drucker")
        #expect(lief && abgewiesen == 0)
        let dokument = try #require(PDFDocument(url: ziel))
        #expect(dokument.pageCount == 7)
        for stelle in 0..<dokument.pageCount {
            let text = dokument.page(at: stelle)?.string ?? ""
            #expect(text.contains("6a · Rückmeldungsliste") && text.contains("Seite \(stelle + 1) von 7"),
                    "Seite \(stelle + 1)")
        }
        #expect(dokument.page(at: 1)?.string?.contains("Kind 21, Vera") == true, "das zweite Band auf Seite 2")
    }

    /// Nicht weiße Bildpunkte der ersten Seite, wie das Blatt sie zeichnet — halb so groß, in einen Bildspeicher.
    private func farbpunkte(_ blatt: Listenblatt) throws -> Int {
        let platz = blatt.rectForPage(1)
        let breite = Int(platz.width / 2), hoehe = Int(platz.height / 2)
        let feld = try #require(CGContext(data: nil, width: breite, height: hoehe, bitsPerComponent: 8,
                                          bytesPerRow: breite * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        feld.setFillColor(CGColor(gray: 1, alpha: 1))
        feld.fill(CGRect(x: 0, y: 0, width: breite, height: hoehe))
        feld.scaleBy(x: 0.5, y: 0.5)
        feld.translateBy(x: -platz.minX, y: -platz.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: feld, flipped: false)
        blatt.draw(platz)
        NSGraphicsContext.restoreGraphicsState()
        let punkte = try #require(feld.data)
        var gezaehlt = 0
        for stelle in stride(from: 0, to: breite * hoehe * 4, by: 4) {
            let rot = punkte.load(fromByteOffset: stelle, as: UInt8.self)
            let gruen = punkte.load(fromByteOffset: stelle + 1, as: UInt8.self)
            let blau = punkte.load(fromByteOffset: stelle + 2, as: UInt8.self)
            if rot < 250 || gruen < 250 || blau < 250 { gezaehlt += 1 }
        }
        return gezaehlt
    }

    @Test("E407: gezeichnet wird nur an den Drucker — an einem PDF-Weg und abgebrochen bleibt die Seite leer")
    func zeichnetNurAnDenDrucker() throws {
        let dokument = try #require(Listensatz.druckschriftstueck(siebenSeiten()))
        let blatt = try #require(Listenblatt(dokument, mass: CGSize(width: 794, height: 547)) {})
        blatt.wegLesen = { .drucker }
        #expect(try farbpunkte(blatt) > 1_000)
        for weg: Listendruck.Druckweg in [.pdfWeg, .abgebrochen] {
            blatt.wegLesen = { weg }
            #expect(try farbpunkte(blatt) == 0, "\(weg)")
        }
    }

    /// Ohne Druckvorgang: Der Vorgang wird nur als laufender gesetzt, wie AppKit ihn nach dem Dialog führt —
    /// ausgeführt wird nichts, angezeigt auch nicht. Dass AppKit einen Auftrag auf `.cancel` ohne Ausgabe und ohne
    /// Anzeige beendet, ist am Lauf gemessen (Bericht), nicht Teil der Suite.
    @Test("E407: „Als PDF sichern“ im Druckdialog — der echte Weg des Vorgangs gilt als PDF-Weg; das Blatt setzt den Auftrag auf .cancel und meldet einmal")
    func pdfWegAbgewiesen() throws {
        let abgewiesen = Zaehler()
        let vorgang = try #require(Listendruck.vorgang(siebenSeiten(), titel: "Probe") { abgewiesen.zahl += 1 })
        let blatt = try #require(vorgang.view as? Listenblatt)
        NSPrintOperation.current = vorgang
        defer { NSPrintOperation.current = nil }
        vorgang.printInfo.jobDisposition = .save
        #expect(Listendruck.wegDesAuftrags() == .pdfWeg)
        var bereich = NSRange()
        #expect(blatt.knowsPageRange(&bereich) && bereich == NSRange(location: 1, length: 7))
        #expect(vorgang.printInfo.jobDisposition == .cancel, "abgebrochen, bevor eine Ausgabe entsteht")
        #expect(abgewiesen.zahl == 1)
        #expect(Listendruck.wegDesAuftrags() == .abgebrochen)
        _ = blatt.knowsPageRange(&bereich)
        #expect(abgewiesen.zahl == 1, "einmal je Vorgang")
        #expect(Rueckmeldungslistenbogen.pdfWegAbgewiesen.contains(Rueckmeldungslistenbogen.sichernTitel),
                "der Hinweis verweist auf den verschlüsselten Export")
    }
}
