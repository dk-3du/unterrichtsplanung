// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Zeichnet die Oberfläche abseits des Bildschirms in PNG-Dateien: Es fällt
/// auf, wenn sich eine Ansicht nicht mehr anlegen lässt, und die Bilder lassen
/// sich ansehen. Ablageort in `ABBILDER`, sonst der Zwischenordner.
@Suite("Abbilder der Oberfläche", .serialized)
@MainActor
struct Abbilder {

    /// Die Vorbedingung dieser Reihe, hart statt gemeldet: Ohne eigenen
    /// Ablageort schriebe jedes `speicher.erscheinung = …` über sein `didSet`
    /// in die Voreinstellungen des laufenden Prozesses.
    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Abbilder brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private var ordner: URL {
        let pfad = ProcessInfo.processInfo.environment["ABBILDER"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: pfad, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func beispielplanung() throws -> Planung {
        var planung = Planung.leer(
            titel: "Unterrichtsplanung 2026/27",
            start: try #require(Tag(iso: "2026-08-10")),
            wochen: 20,
            basis: "/Users/lehrkraft/Unterricht",
            klassen: Standardkurse.aufbauen(Standardkurse.liste),
            fachfarben: [:])

        planung.ferien = [
            Ferienzeitraum(id: "f1", name: "Herbstferien",
                           von: try #require(Tag(iso: "2026-10-12")),
                           bis: try #require(Tag(iso: "2026-10-23"))),
            Ferienzeitraum(id: "f2", name: "Betriebspraktikum",
                           von: try #require(Tag(iso: "2026-09-14")),
                           bis: try #require(Tag(iso: "2026-09-16"))),
        ]
        planung.frei = [try #require(Tag(iso: "2026-11-02"))]
        planung.zellenfrei = [FreieZelle(klasseId: planung.klassen[1].id,
                                         woche: try #require(Tag(iso: "2026-08-24")))]

        let inhalte: [(Int, Int, String, String, Bool, [String], [String])] = [
            (0, 0, "Zellen unter dem Mikroskop", "Mikroskopieren, Zeichnen, Beschriften — Einführung in die Lupe und das Lichtmikroskop.", true,
             ["Bio/AB-Zelle.pdf", "/Volumes/Stick/mikroskop.mp4"], ["https://3ducation.org/"]),
            (0, 1, "Vom Bau der Pflanzenzelle", "Chloroplasten, Zellwand, Vakuole.", false, ["Bio/Zellwand.key"], []),
            (2, 0, "Bewegung und Gelenke", "", false, [], []),
            (4, 0, "Was ist Information?", "Zeichen, Daten, Information — mit Beispielen aus dem Alltag.", false,
             ["Info/Einstieg.pdf"], ["https://www.inf-schule.de/", "https://scratch.mit.edu/"]),
            (4, 2, "Scratch: erste Schleifen", "Wiederholung als Baustein.", true, [], []),
            (6, 1, "Stoffe und ihre Eigenschaften", "Dichte, Löslichkeit, Schmelztemperatur.", false,
             ["Chemie/AB-Stoffe.pdf", "Chemie/Versuch.pdf", "Chemie/Tabelle.pdf", "Chemie/Extra.pdf"], []),
            (12, 3, "LEGO-Roboter: Linienverfolgung", "Sensorwerte auslesen und in Fahrbefehle übersetzen.", false, [], []),
            (3, 4, "Klimazonen der Erde", "Karten lesen, Diagramme auswerten.", false, ["Geo/Klima.pdf"], []),
        ]
        for (kurs, woche, titel, text, erledigt, pfade, adressen) in inhalte {
            planung.eintraege.append(Vorhaben(
                id: Kennung.neu("e"), klasseId: planung.klassen[kurs].id, woche: woche,
                titel: titel, text: text, erledigt: erledigt,
                materialien: pfade.map { Material(titel: Pfade.dateiName($0), pfad: $0) },
                links: adressen.map { Weblink(titel: Weblinks.name($0), adresse: $0) }))
        }
        return planung
    }

    /// Zeichnet über eine echte AppKit-Ansicht in einem unsichtbaren Fenster.
    /// `ImageRenderer` wäre einfacher, ließe aber alles aus, was auf AppKit
    /// aufsetzt — Rollbereiche, Textfelder und Menüs blieben leer.
    private func ablegen(_ name: String, _ bild: some View,
                         breite: CGFloat, hoehe: CGFloat, dunkel: Bool,
                         rollen: CGPoint? = nil) throws {
        let anwendung = NSApplication.shared
        if anwendung.activationPolicy() != .accessory {
            anwendung.setActivationPolicy(.accessory)
        }

        let wurzel = bild.frame(width: breite, height: hoehe)

        let ansicht = NSHostingView(rootView: AnyView(wurzel))
        ansicht.appearance = NSAppearance(named: dunkel ? .darkAqua : .aqua)
        ansicht.frame = CGRect(x: 0, y: 0, width: breite, height: hoehe)

        let fenster = NSWindow(contentRect: ansicht.frame,
                               styleMask: [.borderless], backing: .buffered, defer: false)
        fenster.appearance = ansicht.appearance
        fenster.contentView = ansicht
        fenster.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        fenster.orderFrontRegardless()

        // Kurz laufen lassen, damit SwiftUI seine Anordnung abschließt.
        ansicht.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        ansicht.layoutSubtreeIfNeeded()

        // Zum Prüfen der klebenden Köpfe: den Rollbereich von Hand verschieben.
        if let rollen, let rollbereich = grosserRollbereich(in: ansicht) {
            rollbereich.contentView.scroll(to: rollen)
            rollbereich.reflectScrolledClipView(rollbereich.contentView)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            ansicht.layoutSubtreeIfNeeded()
        }

        fenster.displayIfNeeded()

        let abzug = try #require(ansicht.bitmapImageRepForCachingDisplay(in: ansicht.bounds),
                                 "\(name) ließ sich nicht zeichnen")
        ansicht.cacheDisplay(in: ansicht.bounds, to: abzug)
        let daten = try #require(abzug.representation(using: .png, properties: [:]))
        try daten.write(to: ordner.appendingPathComponent(name + ".png"))

        fenster.orderOut(nil)
        fenster.contentView = nil
    }

    /// Der flächengrößte Rollbereich der Ansicht — das ist das Raster.
    private func grosserRollbereich(in wurzel: NSView) -> NSScrollView? {
        var gefunden: [NSScrollView] = []
        func absuchen(_ ansicht: NSView) {
            if let rollbereich = ansicht as? NSScrollView { gefunden.append(rollbereich) }
            ansicht.subviews.forEach(absuchen)
        }
        absuchen(wurzel)
        return gefunden.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    @Test("Die klebenden Köpfe bleiben beim Rollen an ihrem Platz")
    func klebendeKoepfe() throws {
        var planung = try beispielplanung()
        planung.wochen = 30
        let speicher = Planungsspeicher(vorschau: planung)
        speicher.erscheinung = .dunkel
        try ablegen("14-gerollt", Hauptansicht().environment(speicher),
                    breite: 1480, hoehe: 900, dunkel: true,
                    rollen: CGPoint(x: 1100, y: 260))
    }

    @Test("Das Raster mit Planung zeichnet sich in beiden Darstellungen")
    func hauptfenster() throws {
        let planung = try beispielplanung()
        for dunkel in [true, false] {
            let speicher = Planungsspeicher(vorschau: planung)
            speicher.erscheinung = dunkel ? .dunkel : .hell
            try ablegen(dunkel ? "01-raster-dunkel" : "02-raster-hell",
                        Hauptansicht().environment(speicher),
                        breite: 1480, hoehe: 940, dunkel: dunkel)
        }
    }

    @Test("Der Leerzustand zeichnet sich")
    func leerzustand() throws {
        let speicher = Planungsspeicher(vorschau: nil)
        try ablegen("03-leer", Hauptansicht().environment(speicher),
                    breite: 1200, hoehe: 760, dunkel: true)
    }

    @Test("Die Dialoge zeichnen sich")
    func dialoge() throws {
        var planung = try beispielplanung()
        // Mit einem gültigen und einem verdrehten Zeitraum: Der zweite kann seit
        // 0.22 nur noch aus einer Datei kommen und steht rot da.
        planung.sperrzeiten = [
            Sperrzeitraum(id: "s1", name: "Projektwoche",
                          von: try #require(Tag(iso: "2026-09-21")),
                          bis: try #require(Tag(iso: "2026-09-25")),
                          kurse: [planung.klassen[0].id]),
            Sperrzeitraum(id: "s2", name: "Aus einer älteren Datei",
                          von: try #require(Tag(iso: "2026-11-20")),
                          bis: try #require(Tag(iso: "2026-11-16"))),
        ]
        let speicher = Planungsspeicher(vorschau: planung)

        try ablegen("04-neue-planung", NeuePlanungDialog().environment(speicher),
                    breite: 760, hoehe: 700, dunkel: true)
        // Zwei Fragen: erst die Verschlüsselung samt ihren zwei
        // Schritten, dann die Kopie. Alle vier hell — das dunkle Offscreen-
        // Abbild eines gruppierten Formulars kommt weiß (wie 09b).
        try ablegen("04b-ersteinrichtung", ErsteinrichtungDialog().environment(speicher),
                    breite: 640, hoehe: 600, dunkel: false)
        speicher.ersteinrichtungEinrichten()
        try ablegen("04c-ersteinrichtung-passphrase",
                    ErsteinrichtungDialog().environment(speicher),
                    breite: 640, hoehe: 520, dunkel: false)
        try speicher.ersteinrichtungWeiter(passphrase: "Ein Satz, den man behält")
        try ablegen("04d-ersteinrichtung-blatt", ErsteinrichtungDialog().environment(speicher),
                    breite: 640, hoehe: 600, dunkel: false)
        // Nichts einschalten: Die übrigen Abbilder zeigen die Klartextfassung.
        speicher.ersteinrichtungAbbrechen()
        speicher.ersteinrichtungUeberspringen()
        try ablegen("04e-ersteinrichtung-sicherung",
                    ErsteinrichtungDialog().environment(speicher),
                    breite: 640, hoehe: 680, dunkel: false)
        // Breiter wegen der Tagesspalte mit fünf Kästchen je Zeile.
        try ablegen("05-klassen", KlassenDialog().environment(speicher),
                    breite: 840, hoehe: 740, dunkel: true)
        try ablegen("06-ferien", FerienDialog().environment(speicher),
                    breite: 760, hoehe: 560, dunkel: true)
        // Höher als die übrigen: bei 560 wäre „Sicherungskopie beim Beenden“ abgeschnitten.
        try ablegen("06b-pruefungen", PruefungsDialog().environment(speicher),
                    breite: 900, hoehe: 700, dunkel: true)
        try ablegen("07-einstellungen", EinstellungenDialog().environment(speicher),
                    breite: 760, hoehe: 700, dunkel: true)
        try ablegen("08-farbwahl",
                    FarbwahlDialog(ziel: .kurs(planung.klassen[0].id)).environment(speicher),
                    breite: 760, hoehe: 520, dunkel: true)
        try ablegen("08b-farbwahl-fach",
                    FarbwahlDialog(ziel: .fach("biologie")).environment(speicher),
                    breite: 760, hoehe: 520, dunkel: false)
        try ablegen("09-hilfe", HilfeDialog().environment(speicher),
                    breite: 680, hoehe: 660, dunkel: true)
        // Die Einrichtung der Verschlüsselung (Schritt 1) und die Freigabe.
        try ablegen("09b-verschluesselung", VerschluesselungDialog().environment(speicher),
                    breite: 700, hoehe: 700, dunkel: true)
        try ablegen("09c-entsperren", EntsperrenDialog().environment(speicher),
                    breite: 620, hoehe: 580, dunkel: false)
        let gesperrt = Planungsspeicher(vorschau: planung)
        gesperrt.entsperrungswegWechseln()
        // Hell wie 09c: Das dunkle Abbild eines gruppierten Formulars bleibt
        // abseits des Bildschirms leer (siehe 09b).
        try ablegen("09d-entsperren-schluessel", EntsperrenDialog().environment(gesperrt),
                    breite: 620, hoehe: 580, dunkel: false)

        let entwurf = VorhabenEntwurf(planung.eintraege[0])
        try ablegen("10-vorhaben", VorhabenDialog(start: entwurf).environment(speicher),
                    breite: 760, hoehe: 740, dunkel: true)
        try ablegen("11-vorhaben-hell", VorhabenDialog(start: entwurf).environment(speicher),
                    breite: 760, hoehe: 740, dunkel: false)

        // Das Angebot der Tour und eine ihrer Karten.
        try ablegen("14-tour", TourDialog().environment(speicher),
                    breite: 600, hoehe: 460, dunkel: false)
        let tour = Planungsspeicher(vorschau: planung)
        tour.tourBeginnen()
        for _ in 0..<3 { tour.tourWeiter() }
        tour.tourZelle = "5a, KW 33"
        try ablegen("14b-tourkarte", Tourkarte().environment(tour),
                    breite: 420, hoehe: 260, dunkel: false)

        let tag = Planungsspeicher(vorschau: try heuteplanung())
        try ablegen("12-heute", HeuteDialog().environment(tag),
                    breite: 760, hoehe: 700, dunkel: true)
        try ablegen("13-heute-hell", HeuteDialog().environment(tag),
                    breite: 760, hoehe: 700, dunkel: false)
    }

    /// Für die Tagesliste: dieselbe Planung, so verschoben, dass der heutige
    /// Tag in Woche 1 liegt — sonst zeigte das Bild je nach Kalendertag eine
    /// leere Liste.
    private func heuteplanung() throws -> Planung {
        var planung = try beispielplanung()
        planung.start = Tag.heute.montagDerWoche.plus(tage: -7)
        planung.eintraege.append(Vorhaben(
            id: Kennung.neu("e"), klasseId: planung.klassen[0].id, woche: 1,
            titel: "Bau der Blüte", text: "", erledigt: false, materialien: [], links: [],
            datum: Tag.heute))
        planung.eintraege.append(Vorhaben(
            id: Kennung.neu("e"), klasseId: planung.klassen[4].id, woche: 1,
            titel: "Klassenarbeit: Schleifen", text: "", erledigt: true,
            materialien: [], links: [], pruefung: true, pruefungstag: Tag.heute))
        return planung
    }

    @Test("Der Größtfall — 52 Wochen mal 75 Klassen/Kurse — bleibt zügig")
    func vollausbau() throws {
        var planung = try beispielplanung()
        planung.wochen = Kennwerte.wochenMax
        // 75 Zeilen, in jeder zweiten Woche etwas: 3 900 Zellen.
        while planung.klassen.count < Kennwerte.maxKlassen {
            planung.klassen.append(Klasse(id: Kennung.neu("k"), name: "Z\(planung.klassen.count)",
                                          fach: "Mathematik", notiz: "",
                                          farbe: Farbwelt.ohneFarbe, farbeManuell: false))
        }
        planung.farbenVervollstaendigen()
        for klasse in planung.klassen {
            for woche in stride(from: 0, to: planung.wochen, by: 2) {
                planung.eintraege.append(Vorhaben(
                    id: Kennung.neu("e"), klasseId: klasse.id, woche: woche,
                    titel: "Vorhaben \(woche)", text: "Kurzbeschreibung des Vorhabens.",
                    erledigt: woche % 6 == 0, materialien: [], links: []))
            }
        }
        #expect(planung.eintraege.count >= Kennwerte.maxKlassen * 26)

        // Gemessen wird das Öffnen des Fensters: aufbauen und einmal anordnen.
        // Das Abzeichnen zählt nicht mit — `cacheDisplay` rastert und dauert ein Vielfaches.
        func anordnungsdauer(_ p: Planung) -> (dauer: TimeInterval, kacheln: Int) {
            let speicher = Planungsspeicher(vorschau: p)
            let ansicht = NSHostingView(rootView: AnyView(
                Hauptansicht()
                    .environment(speicher)
                    .frame(width: 1680, height: 1000)))
            let beginn = Date()
            // Innerhalb der Messung, weil das Vermessen des Rasters zum Öffnen
            // des Fensters gehört; sein Ergebnis liefert zugleich die Kachelzahl.
            let daten = Rasterdaten.bereitstellen(p, stand: speicher.planungsstand,
                                                  breite: CGFloat(speicher.spaltenbreite))
            ansicht.frame = CGRect(x: 0, y: 0, width: 1680, height: 1000)
            ansicht.layoutSubtreeIfNeeded()
            let dauer = Date().timeIntervalSince(beginn)
            let kacheln = daten.zeilen.reduce(0) { summe, zeile in
                summe + zeile.kacheln.values.reduce(0) { $0 + $1.count }
            }
            return (dauer, kacheln)
        }

        var ohne = planung
        ohne.eintraege = []
        let leer = anordnungsdauer(ohne)
        let voll = anordnungsdauer(planung)
        #expect(voll.kacheln == planung.eintraege.count,
                "die Messung muss alle Vorhaben angeordnet haben")

        try ablegen("13-vollausbau",
                    Hauptansicht().environment(Planungsspeicher(vorschau: planung)),
                    breite: 1680, hoehe: 1000, dunkel: true)

        let bericht = "Anordnung Vollausbau: \(String(format: "%.2f", voll.dauer)) s · "
            + "leeres Raster \(String(format: "%.2f", leer.dauer)) s · "
            + "\(planung.eintraege.count) Vorhaben"
        // Gebaut werden nur die sichtbaren Zellen; der Bericht stellt die Zeit
        // des Vollausbaus der des leeren Rasters gegenüber.
        #expect(voll.dauer < 1.0, Comment(rawValue: bericht))
    }

    /// Was gezeichnet wird, muss in die vorausberechnete Höhe passen.
    ///
    /// Daran hängt das ganze Raster: Die Anordnung bekommt ihre Zeilenhöhen aus
    /// `Zellenmass`, **bevor** eine Zelle gebaut ist. Zu knapp gerechnet wird
    /// Inhalt abgeschnitten, zu großzügig klaffen Lücken; geprüft wird deshalb
    /// gegen das, was die Kachel wirklich anordnet.
    @Test("Was die Kachel anordnet, passt in die vorausberechnete Höhe")
    func kachelhoeheTraegt() throws {
        let planung = try beispielplanung()
        let klasse = planung.klassen[0]
        var groesstAbweichung: CGFloat = 0
        var bericht: [String] = []

        for breite in [CGFloat(160), 200, 280, 400] {
            for (nummer, vorhaben) in vergleichsfaelle(klasse: klasse).enumerated() {
                var eigene = planung
                eigene.eintraege = vorhaben
                let daten = Rasterdaten(eigene, stand: nummer, breite: breite)
                for stand in daten.kacheln(zeile: 0, woche: 0) {
                    let ansicht = Kachelansicht(frame: .zero)
                    ansicht.setzen(stand, ton: Farbwelt.ton(klasse.farbe),
                                   angewaehlt: false, griffe: .init())
                    let innen = breite - Zellenmass.polsterZelle * 2
                    ansicht.frame = NSRect(x: 0, y: 0, width: innen, height: stand.hoehe)
                    ansicht.layoutSubtreeIfNeeded()

                    // Gezeichneter Text ist keine Unteransicht — daher `inhaltsende`.
                    let unterkante = max(ansicht.inhaltsende,
                                         ansicht.subviews.map(\.frame.maxY).max() ?? 0)
                    let abweichung = stand.hoehe - unterkante
                    groesstAbweichung = max(groesstAbweichung, abs(abweichung))
                    let zeile = String(format: "Fall %2d bei %.0f pt: %.1f hoch, Inhalt bis %.1f (%+.1f)",
                                       nummer + 1, breite, stand.hoehe, unterkante, abweichung)
                    bericht.append(zeile)
                    #expect(unterkante <= stand.hoehe + 0.5,
                            Comment(rawValue: "ragt hinaus — " + zeile))
                }
            }
        }
        // Zu großzügig ist kein Fehler, aber sichtbar als Leerraum.
        #expect(groesstAbweichung < 6, Comment(rawValue: bericht.joined(separator: "\n")))
    }

    /// Aus dem Zeigerort wird die Einfügestelle: aus einer Bildschirmkoordinate
    /// das Vorhaben, vor dem eingesetzt wird.
    @Test("Die Einfügestelle folgt der Mitte der Kacheln")
    func einfuegestelle() throws {
        var planung = try beispielplanung()
        let klasse = planung.klassen[0]
        planung.eintraege = (1...3).map { nummer in
            Vorhaben(id: "e\(nummer)", klasseId: klasse.id, woche: 0,
                     titel: "Vorhaben \(nummer)", text: "", erledigt: false,
                     materialien: [], links: [])
        }
        let breite: CGFloat = 280
        let daten = Rasterdaten(planung, stand: 1, breite: breite)
        let koerper = Zellenkoerper(frame: .zero)
        koerper.setzen(daten: daten, zeile: 0, woche: 0, angewaehlt: false,
                       auswahl: [], treffer: nil, griffe: .init())
        koerper.frame = NSRect(x: 0, y: 0, width: breite, height: daten.zeilen[0].hoehe)
        koerper.layoutSubtreeIfNeeded()

        let kacheln = koerper.subviews.compactMap { $0 as? Kachelansicht }
        #expect(kacheln.count == 3)

        #expect(koerper.einfuegestelle(bei: NSPoint(x: 10, y: kacheln[0].frame.minY + 1)).vorId
                == "e1")
        #expect(koerper.einfuegestelle(bei: NSPoint(x: 10, y: kacheln[0].frame.maxY - 1)).vorId
                == "e2")
        let unten = koerper.einfuegestelle(bei: NSPoint(x: 10, y: kacheln[2].frame.maxY + 5))
        #expect(unten.vorId == nil)
        #expect(unten.stelle == 3)
    }

    /// Die Zellenhöhe trägt alle Kacheln samt Abständen und Fußzeile.
    @Test("Die Zellenhöhe trägt ihre Kacheln")
    func zellenhoeheTraegt() throws {
        let planung = try beispielplanung()
        let klasse = planung.klassen[0]
        for breite in [CGFloat(160), 280, 400] {
            for vorhaben in vergleichsfaelle(klasse: klasse) {
                var eigene = planung
                eigene.eintraege = vorhaben
                let daten = Rasterdaten(eigene, stand: 0, breite: breite)
                let staende = daten.kacheln(zeile: 0, woche: 0)
                let gebraucht = Zellenmass.polsterZelle * 2
                    + staende.reduce(CGFloat(0)) { $0 + $1.hoehe }
                    + Zellenmass.abstandKacheln * CGFloat(staende.count + 1)
                    + Zellenmass.hoeheFuss
                let zeilenhoehe = daten.zeilen[0].hoehe
                #expect(zeilenhoehe >= gebraucht - 0.5,
                        "Zeile \(zeilenhoehe) pt trägt \(gebraucht) pt Inhalt nicht")
            }
        }
    }

    /// Kacheln, die die Höhe auf jede mögliche Weise wachsen lassen.
    private func vergleichsfaelle(klasse: Klasse) -> [[Vorhaben]] {
        func machen(_ titel: String, _ text: String, _ mat: Int, _ links: Int,
                    erledigt: Bool = false, pruefung: Bool = false,
                    datum: Tag? = nil, dringend: Bool = false) -> Vorhaben {
            Vorhaben(id: Kennung.neu("e"), klasseId: klasse.id, woche: 0,
                     titel: titel, text: text, erledigt: erledigt,
                     materialien: (0..<mat).map { Material(titel: "AB \($0).pdf",
                                                           pfad: "Ordner/AB \($0).pdf") },
                     links: (0..<links).map { Weblink(titel: "3ducation.org",
                                                      adresse: "https://3ducation.org/\($0)") },
                     pruefung: pruefung,
                     pruefungstag: pruefung ? Tag(iso: "2026-08-12") : nil,
                     datum: datum, dringend: dringend)
        }
        let tag = Tag(iso: "2026-08-13")
        let lang = "Kompetenzen, Stundenverlauf und Differenzierung — eine Beschreibung, "
            + "die über mehrere Zeilen läuft und deshalb umgebrochen wird."
        return [
            [machen("Kurz", "", 0, 0)],
            [machen("Ein deutlich längerer Titel, der über mehrere Zeilen umbricht", "", 0, 0)],
            [machen("Kurz", "Eine Zeile.", 0, 0)],
            [machen("Kurz", lang, 0, 0)],
            [machen("Kurz", "", 1, 0)],
            [machen("Kurz", "", 0, 1)],
            [machen("Kurz", "Kurzbeschreibung des Vorhabens.", 1, 1)],
            [machen("Kurz", lang, 3, 3)],
            [machen("Kurz", lang, 5, 5)],
            [machen("Erstes", "Kurz.", 1, 0), machen("Zweites", "Kurz.", 0, 1, erledigt: true)],
            [machen("Eins", lang, 2, 1), machen("Zwei", "", 0, 0), machen("Drei", "Kurz.", 1, 1)],
            [machen("Mit Datum", "Kurz.", 0, 0, datum: tag)],
            [machen("Dringlich", lang, 1, 1, dringend: true)],
            [machen("Prüfung und Datum", "Kurz.", 1, 0, pruefung: true, datum: tag,
                    dringend: true)],
        ]
    }

    /// Ein Handgriff im Raster muss sofort sichtbar werden. Gemessen wird die
    /// Rechenzeit des Hauptstrangs zwischen Klick und fertigem Bild, nicht die
    /// Anordnung allein — SwiftUI erledigt einen Teil erst im Ablaufring.
    @Test("Eine Zelle freizuschalten wird sofort sichtbar")
    func handgriffsdauer() throws {
        let planung = try grosseplanung()
        let speicher = Planungsspeicher(vorschau: planung)

        let ansicht = NSHostingView(rootView: AnyView(
            Hauptansicht().environment(speicher).frame(width: 1680, height: 1000)))
        ansicht.frame = CGRect(x: 0, y: 0, width: 1680, height: 1000)
        let fenster = NSWindow(contentRect: ansicht.frame,
                               styleMask: [.borderless], backing: .buffered, defer: false)
        fenster.contentView = ansicht
        fenster.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        fenster.orderFrontRegardless()
        ansicht.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let wochen = planung.wochenListe
        let klasse = planung.klassen[3].id
        let vorher = rechenzeit()
        let handgriffe = 8
        for stelle in 0..<handgriffe {
            speicher.zelleFreiSchalten(klasse: klasse, woche: wochen[stelle * 3])
            ansicht.layoutSubtreeIfNeeded()
            fenster.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let dauer = (rechenzeit() - vorher) / Double(handgriffe)

        fenster.orderOut(nil)
        fenster.contentView = nil

        let bericht = String(format: "Handgriff im Raster: %.0f ms im Hauptstrang "
                             + "(%d Kurse, %d Wochen, %d Vorhaben)", dauer * 1000,
                             planung.klassen.count, planung.wochen,
                             planung.eintraege.count)
        // Unter 100 ms wirkt ein Handgriff unmittelbar; prozessweit gemessen 18 ms,
        // der Hauptstrang allein bleibt darunter. Die Schranke schlägt an, wenn
        // wieder das ganze Raster durchgerechnet wird.
        #expect(dauer < 0.1, Comment(rawValue: bericht))
    }

    /// Die Rechenzeit des **Hauptstrangs**, nicht die des Prüfprozesses.
    ///
    /// `getrusage(RUSAGE_SELF)` summiert alle Stränge: Was die nebenläufig
    /// gefahrenen Suiten im Messfenster rechnen, landete sonst im Messwert —
    /// nachgestellt ergaben zwei rechnende Fremdstränge über 0,4 s Wartezeit
    /// +102 ms je Handgriff. Während des Ablaufrings wartet der Hauptstrang
    /// und verbraucht dabei nichts; gezählt wird also genau die Arbeit, die
    /// der Handgriff auslöst.
    private func rechenzeit() -> Double {
        var angabe = thread_basic_info()
        var anzahl = mach_msg_type_number_t(
            MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        // Jeder Aufruf holt ein eigenes Senderecht; ohne Rückgabe liefe der
        // Port-Zähler des Hauptstrangs mit jeder Messung weiter hoch.
        let strang = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, strang) }
        let ergebnis = withUnsafeMutablePointer(to: &angabe) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(anzahl)) {
                thread_info(strang, thread_flavor_t(THREAD_BASIC_INFO), $0, &anzahl)
            }
        }
        guard ergebnis == KERN_SUCCESS else { return 0 }
        let nutzer = angabe.user_time
        let system = angabe.system_time
        return Double(nutzer.seconds) + Double(nutzer.microseconds) / 1e6
            + Double(system.seconds) + Double(system.microseconds) / 1e6
    }

    /// Der Größtfall: volle 52 Wochen, alle Zeilen, in jeder zweiten Woche etwas.
    private func grosseplanung() throws -> Planung {
        var planung = try beispielplanung()
        planung.wochen = Kennwerte.wochenMax
        while planung.klassen.count < Kennwerte.maxKlassen {
            planung.klassen.append(Klasse(id: Kennung.neu("k"), name: "Z\(planung.klassen.count)",
                                          fach: "Mathematik", notiz: "",
                                          farbe: Farbwelt.ohneFarbe, farbeManuell: false))
        }
        planung.farbenVervollstaendigen()
        for klasse in planung.klassen {
            for woche in stride(from: 0, to: planung.wochen, by: 2) {
                planung.eintraege.append(Vorhaben(
                    id: Kennung.neu("e"), klasseId: klasse.id, woche: woche,
                    titel: "Vorhaben \(woche)", text: "Kurzbeschreibung des Vorhabens.",
                    erledigt: woche % 6 == 0,
                    materialien: [Material(titel: "AB.pdf", pfad: "Material/AB.pdf")],
                    links: [Weblink(titel: "3ducation.org", adresse: "https://3ducation.org/")]))
            }
        }
        return planung
    }

    /// Zeichnet wie `ablegen`, gibt den Abzug aber zum Nachmessen heraus.
    private func abzug(_ bild: some View, breite: CGFloat, hoehe: CGFloat)
        throws -> NSBitmapImageRep {
        let anwendung = NSApplication.shared
        if anwendung.activationPolicy() != .accessory {
            anwendung.setActivationPolicy(.accessory)
        }
        let ansicht = NSHostingView(rootView: AnyView(bild.frame(width: breite, height: hoehe)))
        ansicht.appearance = NSAppearance(named: .aqua)
        ansicht.frame = CGRect(x: 0, y: 0, width: breite, height: hoehe)

        let fenster = NSWindow(contentRect: ansicht.frame,
                               styleMask: [.borderless], backing: .buffered, defer: false)
        fenster.appearance = ansicht.appearance
        fenster.contentView = ansicht
        fenster.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        fenster.orderFrontRegardless()
        ansicht.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        fenster.displayIfNeeded()

        let bitmuster = try #require(ansicht.bitmapImageRepForCachingDisplay(in: ansicht.bounds))
        ansicht.cacheDisplay(in: ansicht.bounds, to: bitmuster)
        fenster.orderOut(nil)
        fenster.contentView = nil
        return bitmuster
    }

    /// Zwei aufeinanderfolgende `.background` stapeln nach hinten: Stünde die
    /// deckende Fensterfläche vor der Tönung, wäre die Kursfarbe im Kopf nicht
    /// zu sehen. Gemessen statt beteuert.
    @Test("Die Kursfarbe tönt den Klassenkopf sichtbar")
    func kursfarbeImKopf() throws {
        func flaeche(_ ton: String) throws -> NSColor {
            let planung = Planung.leer(
                titel: "Farbe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
                basis: "", klassen: [], fachfarben: [:])
            let speicher = Planungsspeicher(vorschau: planung)
            let klasse = Klasse(id: "k1", name: "5a", fach: "", notiz: "",
                                farbe: try #require(Farbwelt.stelle(ton)), farbeManuell: true)
            let bild = Klassenkopf(klasse: klasse).environment(speicher)
            let abzug = try abzug(bild, breite: 200, hoehe: 90)
            // Unten rechts: abseits von Schrift, Farbstreifen und Trennlinien.
            return try #require(abzug.colorAt(x: abzug.pixelsWide - 20,
                                              y: abzug.pixelsHigh - 20)?
                .usingColorSpace(.sRGB))
        }

        let rot = try flaeche("rot-mittel")
        let blau = try flaeche("blau-mittel")
        #expect(rot.redComponent > rot.blueComponent + 0.01)
        #expect(blau.blueComponent > blau.redComponent + 0.01)
    }

    @Test("Die Druckfassung zeichnet sich")
    func druckfassung() throws {
        var planung = try beispielplanung()
        planung.wochen = 6
        planung.eintraege.removeAll { $0.woche >= 6 }
        try ablegen("12-druck", Druckansicht(planung: planung),
                    breite: Druckansicht.breite(planung), hoehe: 1400, dunkel: false)
    }
}
