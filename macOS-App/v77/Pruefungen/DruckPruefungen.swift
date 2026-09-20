// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

private typealias Tag = Unterrichtsplanung.Tag

// ── Drucken ───────────────────────────────────────────────────────────────
//
// `NSPrintOperation` hat aus einer `NSHostingView` leere Blätter gemacht — richtig
// gezählt und aufgeteilt, ohne einen Strich. Geprüft wird deshalb die Farbe auf dem Papier.

@Suite("Drucken", .serialized)
@MainActor
struct DruckPruefungen {

    private func planung() throws -> Planung {
        var planung = Planung.leer(
            titel: "Ausdruck 2026/27", start: try #require(Tag(iso: "2026-08-10")),
            wochen: 6, basis: "",
            klassen: Standardkurse.aufbauen(Array(Standardkurse.liste.prefix(4))),
            fachfarben: [:])
        planung.ferien = [
            Ferienzeitraum(id: "f1", name: "Herbstferien",
                           von: try #require(Tag(iso: "2026-09-14")),
                           bis: try #require(Tag(iso: "2026-09-18"))),
        ]
        let inhalte: [(Int, Int, String, String)] = [
            (0, 0, "Zellen unter dem Mikroskop", "Mikroskopieren, Zeichnen, Beschriften."),
            (0, 2, "Vom Bau der Pflanzenzelle", "Chloroplasten, Zellwand, Vakuole."),
            (1, 1, "Bewegung und Gelenke", ""),
            (2, 3, "Was ist Information?", "Zeichen, Daten, Information."),
            (3, 4, "Klimazonen der Erde", "Karten lesen, Diagramme auswerten."),
        ]
        for (kurs, woche, titel, text) in inhalte {
            planung.eintraege.append(Vorhaben(
                id: Kennung.neu("e"), klasseId: planung.klassen[kurs].id, woche: woche,
                titel: titel, text: text, erledigt: false, materialien: [], links: []))
        }
        return planung
    }

    /// Bildpunkte, die nicht weiß sind — das Maß für „da steht etwas“.
    /// Gezeichnet wird klein (die Hälfte), das reicht zum Zählen und hält den
    /// Lauf kurz.
    private func farbpunkte(_ seite: CGPDFPage, anteilLinks: Double = 1) throws -> Int {
        let kasten = seite.getBoxRect(.mediaBox)
        let breite = max(1, Int(kasten.width / 2))
        let hoehe = max(1, Int(kasten.height / 2))
        let feld = try #require(CGContext(
            data: nil, width: breite, height: hoehe, bitsPerComponent: 8,
            bytesPerRow: breite * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        feld.setFillColor(NSColor.white.cgColor)
        feld.fill(CGRect(x: 0, y: 0, width: breite, height: hoehe))
        feld.scaleBy(x: 0.5, y: 0.5)
        feld.translateBy(x: -kasten.minX, y: -kasten.minY)
        feld.drawPDFPage(seite)

        let punkte = try #require(feld.data)
        var gezaehlt = 0
        let bis = max(1, Int(Double(breite) * anteilLinks))
        for zeile in 0..<hoehe {
            for spalte in 0..<bis {
                let stelle = (zeile * breite + spalte) * 4
                let rot = punkte.load(fromByteOffset: stelle, as: UInt8.self)
                let gruen = punkte.load(fromByteOffset: stelle + 1, as: UInt8.self)
                let blau = punkte.load(fromByteOffset: stelle + 2, as: UInt8.self)
                if rot < 250 || gruen < 250 || blau < 250 { gezaehlt += 1 }
            }
        }
        return gezaehlt
    }

    private func seiten(_ daten: Data) throws -> [CGPDFPage] {
        let quelle = try #require(CGDataProvider(data: daten as CFData))
        let schriftstueck = try #require(CGPDFDocument(quelle))
        return try (1...schriftstueck.numberOfPages).map {
            try #require(schriftstueck.page(at: $0))
        }
    }

    @Test("Die Druckfassung trägt Inhalt — dieselbe Zeichnung wie „Als PDF sichern“")
    func zeichnungTraegtInhalt() throws {
        let planung = try planung()
        let (daten, groesse) = try #require(Drucken.zeichnung(planung),
                                            "Die Druckfassung ließ sich nicht zeichnen")
        // Die 32 Punkte sind das Seiten-Padding der Druckansicht; es gehört mit aufs Blatt.
        #expect(groesse.width == Druckansicht.breite(planung) + 32)
        #expect(groesse.height > 100)

        let alleSeiten = try seiten(daten)
        #expect(alleSeiten.count == 1)
        #expect(try farbpunkte(try #require(alleSeiten.first)) > 5_000)
    }

    /// Der eigentliche Fund: Der Druckvorgang selbst muss Farbe aufs Blatt
    /// bringen. Gedruckt wird in eine Datei — dafür braucht es keinen Drucker.
    @Test("Der Druckvorgang bedruckt jede Seite")
    func ausdruckIstNichtLeer() throws {
        if NSApplication.shared.activationPolicy() != .accessory {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        let planung = try planung()
        let angaben = Drucken.druckangaben()
        // A4 quer festnageln: `druckangaben()` erbt Papier und bedruckbare Fläche
        // vom Standarddrucker der Maschine. Ab 1290 pt nutzbarer Breite stünden
        // alle sechs Wochen auf einem Blatt und die Aufteilung bliebe ungeprüft.
        angaben.paperSize = NSSize(width: 842, height: 595)
        Drucken.raender(angaben)
        let mass = Drucken.blattmass(angaben)
        let blatt = try #require(Druckblatt(planung, mass: mass), "Kein Druckblatt")

        let ziel = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("druckprobe-\(UUID().uuidString).pdf")
        angaben.jobDisposition = .save
        angaben.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = ziel

        let vorgang = NSPrintOperation(view: blatt, printInfo: angaben)
        vorgang.jobTitle = planung.titel
        vorgang.showsPrintPanel = false
        vorgang.showsProgressPanel = false
        #expect(vorgang.run())

        defer { try? FileManager.default.removeItem(at: ziel) }
        let alleSeiten = try seiten(try Data(contentsOf: ziel))
        let erwartet = Drucken.blaetter(planung, mass: mass).count
        #expect(erwartet > 1, "Diese Planung ist breiter als ein Blatt")
        // Die Aufteilung kommt aus `knowsPageRange`, nicht von AppKit: Was der
        // Vorgang aufs Papier bringt, muss der gerechneten Blattzahl entsprechen.
        #expect(alleSeiten.count == erwartet)
        for (stelle, seite) in alleSeiten.enumerated() {
            #expect(try farbpunkte(seite) > 500,
                    "Blatt \(stelle + 1) von \(alleSeiten.count) ist leer")
            #expect(try farbpunkte(seite, anteilLinks: 0.3) > 100,
                    "Blatt \(stelle + 1) trägt links keine Kurskennung")
        }
    }

    // ── Die Aufteilung ────────────────────────────────────────────────────

    @Test("Jede Woche und jede Zeile steht genau einmal auf einem Blatt")
    func aufteilungIstVollstaendig() throws {
        let planung = try planung()
        let mass = CGSize(width: 794, height: 547)
        let blaetter = Drucken.blaetter(planung, mass: mass)
        #expect(blaetter.count > 1)

        var gesehen: [Int] = []
        var gruppen: [[Int]] = []
        for blatt in blaetter {
            let nummern = blatt.wochen.map(\.nummer)
            if gruppen.last != nummern { gruppen.append(nummern) }
        }
        for gruppe in gruppen { gesehen.append(contentsOf: gruppe) }
        #expect(gesehen == Array(0..<planung.wochen))

        for gruppe in gruppen {
            let zeilen = blaetter.filter { $0.wochen.map(\.nummer) == gruppe }
                .flatMap(\.klassen).map(\.id)
            #expect(zeilen == planung.klassen.map(\.id))
        }

        #expect(blaetter.map(\.blatt) == Array(1...blaetter.count))
        #expect(blaetter.allSatisfy { $0.blaetter == blaetter.count })
    }

    /// Die Zahl selbst, nicht nur ihre Folgen: Die Ansichtsfassung teilt nach
    /// derselben Rechnung auf, übernähme die Maße ohne diese Prüfung aber leicht als Zahl **ohne
    /// Einheit** übernommen — 190 Punkt der App gegen 190 CSS-Pixel dort, also
    /// vier Wochen je Blatt statt drei. Wandert `Druckmasse`, muss die Ansicht
    /// mit; `Web-App/vNN/masse_pruefen.py` stellt beide Zahlen gegeneinander.
    @Test("Auf A4 quer stehen drei Wochen je Blatt")
    func dreiWochenJeBlatt() throws {
        // A4 quer (842 × 595 pt) abzüglich der beiden 24-Punkt-Ränder.
        let mass = CGSize(width: 794, height: 547)
        let jeBlatt = Int((mass.width - Druckmasse.spalteKlasse) / Druckmasse.spalteWoche)
        #expect(jeBlatt == 3)

        let planung = try planung()
        let gruppen = Set(Drucken.blaetter(planung, mass: mass).map { $0.wochen.count })
        #expect(gruppen.allSatisfy { $0 <= 3 })
        #expect(gruppen.contains(3), "Volle Blätter tragen alle drei Wochen")
    }

    @Test("Keine Zeile wird an der Blattkante durchgeschnitten")
    func zeilenBleibenGanz() throws {
        var planung = try planung()
        // Höhere Zeilen erzwingen: mehrere Vorhaben in derselben Zelle.
        for stelle in 0..<6 {
            planung.eintraege.append(Vorhaben(
                id: Kennung.neu("e"), klasseId: planung.klassen[1].id, woche: 1,
                titel: "Vorhaben \(stelle)",
                text: "Eine Beschreibung, die über mehrere Zeilen läuft und die Zelle "
                    + "damit spürbar in die Höhe treibt.",
                erledigt: false, materialien: [], links: []))
        }
        let mass = CGSize(width: 794, height: 547)
        let blaetter = Drucken.blaetter(planung, mass: mass)
        for blatt in blaetter {
            let gemessen = Drucken.hoehe(blatt, breite: mass.width)
            // Ausnahme: eine einzelne Zeile höher als das Blatt wird beim Zeichnen verkleinert.
            #expect(gemessen <= mass.height || blatt.klassen.count == 1,
                    "Blatt \(blatt.blatt) läuft über: \(gemessen) statt \(mass.height)")
        }
    }

    @Test("Die Zeilen verteilen sich gleichmäßig auf die Bänder")
    func baenderSindAusgeglichen() {
        let platz: CGFloat = 547

        // Der Reihe nach gefüllt ergäbe 8 + 5; verteilt wird auf 7 + 6.
        let dreizehn = Array(repeating: CGFloat(66), count: 13)
        let verteilt = Drucken.baender(dreizehn, platz: platz)
        #expect(verteilt.count == 2)
        #expect(verteilt.flatMap { $0 } == Array(0..<13))
        #expect(verteilt.map(\.count) == [7, 6])
        #expect(verteilt.allSatisfy { band in
            band.reduce(0) { $0 + dreizehn[$1] } <= platz
        })

        // Mehr Blätter dürfen dabei nie entstehen.
        let gemischt: [CGFloat] = [200, 60, 60, 300, 54, 54, 120, 90, 400, 54]
        let bandzahl = Drucken.baender(gemischt, platz: platz).count
        #expect(bandzahl == 3, "\(gemischt.reduce(0, +)) Punkt auf \(platz) Punkt hohe Blätter")
        #expect(Drucken.baender(gemischt, platz: platz).flatMap { $0 } == Array(0..<gemischt.count))

        let riesig: [CGFloat] = [600, 100]
        #expect(Drucken.baender(riesig, platz: platz) == [[0], [1]])

        // Auch neben einer überhohen Zeile darf nie oberhalb der Blattgrenze gebündelt werden.
        let ueberhoch: [CGFloat] = [600, 300, 290]
        let gebuendelt = Drucken.baender(ueberhoch, platz: platz)
        #expect(gebuendelt == [[0], [1], [2]])
        #expect(gebuendelt.allSatisfy { band in
            band.count == 1 || band.reduce(0) { $0 + ueberhoch[$1] } <= platz
        })
    }
}
