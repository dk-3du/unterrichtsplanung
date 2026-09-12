// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Sitzplan ──────────────────────────────────────────────────────────
// Namensliste, Anordnung, Bewegen, Datei, Dienst — und der Behälter in den
// Übergängen des Schutzes: dieselbe Rücknahme wie die Lesezeichen.

@Suite("Sitzplan: Namen, Anordnung, Bewegen, Datei, Behälter, Übergänge")
@MainActor
struct SitzplanPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "sitzplan-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func aufraeumen(_ orte: URL...) {
        for ort in orte { try? FileManager.default.removeItem(at: ort) }
    }

    private func namen(_ anzahl: Int) -> [String] {
        (0..<anzahl).map { "Name \($0 + 1)" }
    }

    private func plan(_ anzahl: Int = 10, klasse: String = "k-eins") -> Sitzplan {
        Sitzplan.anordnen(klasseId: klasse, namen: namen(anzahl))
    }

    private func tresor() throws -> Tresor {
        let t = Tresor.neu()
        try t.passphraseSetzen(passphrase, runden: Tresor.rundenMindestens)
        return t
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Sitzplan", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("7a", "Mathematik"), ("G9", "Chemie")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Brüche",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    /// Ein Speicher mit eigener Ablage, die Planung im Klartext.
    private func speicher(ablage: URL) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        return s
    }

    private func kopf(_ url: URL) throws -> Behaelterkopf {
        try Tresor.kopfLesen(try Data(contentsOf: url))
    }

    /// Der Übergang am Dienst, wie der Übergabestand ihn ausführt: den Inhalt
    /// liefern, hinlegen (oder entfernen), umschalten.
    private func umstellen(_ dienst: Sitzplandienst, _ ablage: Ablage, auf t: Tresor?) throws {
        if let daten = try dienst.inhalt(unter: t) {
            try ablage.sitzplaeneSchreiben(daten)
        } else {
            ablage.sitzplaeneEntfernen()
        }
        dienst.umschalten(auf: t)
    }

    // ── Die Namensliste ───────────────────────────────────────────────────

    @Test("Namensliste: leere Zeilen und Windows-Enden übergangen, Doppelte erlaubt, Steuerzeichen weg")
    func namensliste() {
        let liste = Sitzplan.namenLesen("Anna Berg\r\n\r\n  Max  \nMax\n\t\nBe\u{07}n\n")
        #expect(liste.namen == ["Anna Berg", "Max", "Max", "Ben"])
        #expect(liste.fehler.isEmpty)
        #expect(Sitzplan.namenLesen("   \n\n").namen.isEmpty)
    }

    @Test("Namensliste: die 36. Zeile und ein Name mit 101 Zeichen werden benannt, nicht gekürzt")
    func namenslisteGrenzen() {
        let lang = String(repeating: "x", count: Kennwerte.maxSitzplatzname + 1)
        let text = (namen(Kennwerte.maxSitzplaetze) + ["Zu viel", lang]).joined(separator: "\n")
        let liste = Sitzplan.namenLesen(text)
        #expect(liste.namen.count == Kennwerte.maxSitzplaetze)
        #expect(liste.fehler.count == 2)
        #expect(liste.fehler[0].nummer == 36 && liste.fehler[0].grund.contains("35"))
        #expect(liste.fehler[1].nummer == 37 && liste.fehler[1].grund.contains("100"))
        let genau = String(repeating: "y", count: Kennwerte.maxSitzplatzname)
        #expect(Sitzplan.namenLesen(genau).namen == [genau], "genau 100 Zeichen gehen durch")
    }

    // ── Die Anordnung ─────────────────────────────────────────────────────

    @Test("Anordnung: Reihen zu acht von der Tafel weg, die fünfte ab dem 33. Namen, alles in der Fläche, nichts überlappt")
    func anordnung() {
        for anzahl in [1, 8, 9, 24, 32, 33, 35] {
            let p = plan(anzahl)
            #expect(p.tische.count == anzahl)
            #expect(p.tische.map(\.name) == namen(anzahl), "Reihenfolge der Namen")
            let reihen = Set(p.tische.map(\.y))
            #expect(reihen.count == (anzahl + 7) / 8, "\(anzahl) Namen → \(reihen.count) Reihen")
            #expect(p.tische[0].x == Sitzplanmasse.reihenanfang && p.tische[0].y == Sitzplanmasse.ersteReihe,
                    "der erste Tisch steht vorn an der Tafel, ein Platz vom Rand frei")
            if anzahl > 8 {
                #expect(p.tische[8].y == Sitzplanmasse.ersteReihe - Sitzplanmasse.reihenschritt
                        && p.tische[8].x == Sitzplanmasse.reihenanfang, "die neunte Zeile beginnt die zweite Reihe dahinter")
                #expect(p.tische[7].x + Sitzplanmasse.spaltenschritt == Sitzplanmasse.platz(9),
                        "rechts vom achten Tisch bleibt der zehnte Platz frei")
            }
            for tisch in p.tische {
                #expect(Sitzplanmasse.tischbereich.contains(tisch.rahmen), "\(tisch.name) in der Fläche")
                #expect(tisch.rahmen.maxY <= Sitzplanmasse.tafel.minY, "\(tisch.name) über der Tafel")
            }
            for a in p.tische {
                for b in p.tische where a.id != b.id {
                    #expect(!a.rahmen.intersects(b.rahmen), "\(a.name) und \(b.name) überlappen nicht")
                }
            }
            #expect(p.lehrertisch == Sitzplanmasse.lehrertischStart)
            #expect(Set(p.tische.map(\.id)).count == anzahl, "Kennungen eindeutig")
        }
        #expect(plan(40).tische.count == Kennwerte.maxSitzplaetze, "mehr als 35 Namen werden gekappt")
    }

    @Test("Zehn Plätze je Reihe: ein Tisch rückt um einen Platz nach außen und bleibt auf dem Raster in der Fläche — zwei Gänge lassen sich aussparen")
    func zehnPlaetze() {
        let p = plan(8)
        let links = p.verschoben([p.tische[0].id], um: CGPoint(x: -Sitzplanmasse.spaltenschritt, y: 0))
        #expect(links.tische[0].x == Sitzplanmasse.platz(0) && links.tische[0].x == Sitzplanmasse.rand)
        let rechts = p.verschoben([p.tische[7].id], um: CGPoint(x: Sitzplanmasse.spaltenschritt, y: 0))
        #expect(rechts.tische[7].x == Sitzplanmasse.platz(9))
        #expect(rechts.tische[7].rahmen.maxX == Sitzplanmasse.breite - Sitzplanmasse.rand)
        #expect(Sitzplanmasse.platz(Sitzplanmasse.plaetzeJeReihe - 1) + Sitzplanmasse.tischbreite
                <= Sitzplanmasse.tischbereich.maxX, "der zehnte Platz liegt in der Fläche")
        // Zwei Gänge: Tisch 1 und 2 nach links, Tisch 7 und 8 nach rechts — vier Blöcke, zwei Lücken.
        let gaenge = p.verschoben([p.tische[0].id, p.tische[1].id], um: CGPoint(x: -Sitzplanmasse.spaltenschritt, y: 0))
            .verschoben([p.tische[6].id, p.tische[7].id], um: CGPoint(x: Sitzplanmasse.spaltenschritt, y: 0))
        let belegt = Set(gaenge.tische.map { Int(($0.x - Sitzplanmasse.rand) / Sitzplanmasse.spaltenschritt) })
        #expect(belegt == [0, 1, 3, 4, 5, 6, 8, 9], "Plätze 2 und 7 sind die Gänge")
        for tisch in gaenge.tische { #expect(Sitzplanmasse.tischbereich.contains(tisch.rahmen)) }
        // Weiter nach außen geht es nicht: die Fläche hält den Tisch am Rand.
        #expect(rechts.verschoben([p.tische[7].id], um: CGPoint(x: Sitzplanmasse.spaltenschritt, y: 0)).tische[7].x
                == Sitzplanmasse.breite - Sitzplanmasse.tischbreite)
    }

    @Test("Anordnung: die Lagen liegen auf dem 8-Punkt-Raster, Lehrertisch und Tafel überlappen keinen Tisch")
    func anordnungRaster() {
        let p = plan(35)
        for tisch in p.tische {
            #expect(tisch.x.truncatingRemainder(dividingBy: 8) == 0 && tisch.y.truncatingRemainder(dividingBy: 8) == 0)
            #expect(!tisch.rahmen.intersects(Sitzplanmasse.tafel))
            if let lehrer = p.lehrertischRahmen { #expect(!tisch.rahmen.intersects(lehrer)) }
        }
    }

    // ── Bewegen ───────────────────────────────────────────────────────────

    @Test("Verschieben: mit Fangen rastet der Anker ein, ohne zählt der Punkt, Lagen sind ganze Punkte")
    func verschieben() {
        let p = plan(3)
        let id = p.tische[0].id
        // Die erste Reihe steht an der Tafel — nach oben (kleineres y) ist Platz.
        let gefangen = p.verschoben([id], um: CGPoint(x: 41.4, y: -30.6), anker: id)
        #expect(gefangen.tische[0].x == p.tische[0].x + 40 && gefangen.tische[0].y == p.tische[0].y - 32)
        let frei = p.verschoben([id], um: CGPoint(x: 41.4, y: -30.6), anker: id, fangen: false)
        #expect(frei.tische[0].x == p.tische[0].x + 41 && frei.tische[0].y == p.tische[0].y - 31)
        #expect(p.verschoben([id], um: CGPoint(x: 0, y: 30), anker: id).tische[0].y == p.tische[0].y,
                "nach unten ist an der Tafel Schluss")
        #expect(frei.tische[1] == p.tische[1] && frei.tische[2] == p.tische[2], "die anderen bleiben")
        #expect(p.verschoben([], um: CGPoint(x: 8, y: 8)) == p)
        #expect(p.verschoben(["gibt-es-nicht"], um: CGPoint(x: 8, y: 8)) == p)
    }

    @Test("Verschieben: eine Gruppe wandert gemeinsam, die Abstände bleiben, der äußerste hält die Gruppe in der Fläche")
    func gruppeVerschieben() {
        let p = plan(9)
        let gruppe: Set<String> = [p.tische[0].id, p.tische[7].id, p.tische[8].id]
        let abstand = p.tische[7].x - p.tische[0].x
        let bewegt = p.verschoben(gruppe, um: CGPoint(x: 8, y: -16), anker: p.tische[0].id)
        #expect(bewegt.tische[0].x == p.tische[0].x + 8 && bewegt.tische[0].y == p.tische[0].y - 16)
        #expect(bewegt.tische[7].x - bewegt.tische[0].x == abstand)
        #expect(bewegt.tische[8].y == p.tische[8].y - 16)
        #expect(bewegt.tische[1] == p.tische[1], "nicht angewählt bleibt stehen")

        // Weit nach rechts: Der achte Tisch stößt an, alle drei bleiben stehen, wo er sie hält.
        let rechts = p.verschoben(gruppe, um: CGPoint(x: 2000, y: 0), anker: p.tische[0].id)
        #expect(rechts.tische[7].rahmen.maxX == Sitzplanmasse.tischbereich.maxX)
        #expect(rechts.tische[7].x - rechts.tische[0].x == abstand)
        // Weit nach unten: über der Tafel ist Schluss.
        let unten = p.verschoben(gruppe, um: CGPoint(x: 0, y: 5000), anker: p.tische[0].id)
        #expect(unten.tische[0].rahmen.maxY == Sitzplanmasse.tischbereich.maxY)
        for tisch in unten.tische { #expect(Sitzplanmasse.tischbereich.contains(tisch.rahmen)) }
        // Und nach links oben aus der Fläche: nicht unter null.
        let oben = p.verschoben(gruppe, um: CGPoint(x: -9999, y: -9999), anker: p.tische[0].id)
        #expect(oben.tische[0].x == 0 && oben.tische[8].y == 0)
    }

    @Test("Lehrertisch: wählbar, verschiebbar bis an die Unterkante, entfernbar, wieder hinzuzufügen")
    func lehrertisch() {
        let p = plan(2)
        let mit = p.verschoben([Sitzplan.lehrertischKennung, p.tische[0].id], um: CGPoint(x: 0, y: 9999),
                               anker: Sitzplan.lehrertischKennung)
        // Der Tisch hält die Gruppe: Er darf nicht unter die Tafelgrenze.
        #expect(mit.tische[0].rahmen.maxY == Sitzplanmasse.tischbereich.maxY)
        let allein = p.verschoben([Sitzplan.lehrertischKennung], um: CGPoint(x: 0, y: 9999))
        #expect(allein.lehrertischRahmen?.maxY == Sitzplanmasse.lehrertischbereich.maxY)
        let ohne = p.ohne(Sitzplan.lehrertischKennung)
        #expect(ohne.lehrertisch == nil && ohne.elementKennungen.count == 2)
        #expect(ohne.verschoben([Sitzplan.lehrertischKennung], um: CGPoint(x: 8, y: 0)) == ohne)
        #expect(ohne.mitLehrertisch().lehrertisch == Sitzplanmasse.lehrertischStart)
    }

    @Test("Bereichsauswahl trifft genau die Tische im Rechteck, das Element unter dem Punkt ist das oberste")
    func bereich() {
        let p = plan(10)
        let zweiter = p.tische[1].rahmen, dritter = p.tische[2].rahmen
        let rechteck = CGRect(x: zweiter.minX - 2, y: zweiter.minY - 2,
                              width: dritter.maxX - zweiter.minX + 4, height: zweiter.height + 4)
        #expect(p.imBereich(rechteck) == [p.tische[1].id, p.tische[2].id])
        #expect(p.imBereich(CGRect(x: 0, y: 0, width: 4, height: 4)).isEmpty)
        #expect(p.imBereich(CGRect(x: 0, y: 0, width: 9999, height: 9999))
                == Set(p.tische.map(\.id)).union([Sitzplan.lehrertischKennung]))
        #expect(p.element(bei: CGPoint(x: zweiter.midX, y: zweiter.midY)) == p.tische[1].id)
        #expect(p.element(bei: CGPoint(x: 2, y: 2)) == nil)
        if let lehrer = p.lehrertischRahmen {
            #expect(p.element(bei: CGPoint(x: lehrer.midX, y: lehrer.midY)) == Sitzplan.lehrertischKennung)
        }
    }

    @Test("Umbenennen, entfernen, hinzufügen: bereinigt, in der Grenze, an eine freie Stelle, nie über 35")
    func aendern() {
        var p = plan(3)
        let id = p.tische[1].id
        #expect(p.umbenannt(id, name: "  Mia\u{07} Neu  ").tisch(id)?.name == "Mia Neu")
        #expect(p.umbenannt(id, name: "   ") == p, "leer heißt: bleibt")
        let lang = String(repeating: "z", count: 130)
        #expect(p.umbenannt(id, name: lang).tisch(id)?.name.count == Kennwerte.maxSitzplatzname)
        #expect(p.ohne(id).tische.count == 2 && p.ohne(id).tisch(id) == nil)

        let mehr = try? #require(p.mitNeuemTisch(name: "Neu"))
        #expect(mehr?.tische.count == 4)
        #expect(mehr?.tische.last?.name == "Neu")
        // Die freie Stelle ist der vierte Platz der Anfangsanordnung in der ersten Reihe.
        #expect(mehr?.tische.last?.x == Sitzplanmasse.reihenanfang + 3 * Sitzplanmasse.spaltenschritt
                && mehr?.tische.last?.y == Sitzplanmasse.ersteReihe)
        // Ist die erste Reihe voll, kommt die zweite Reihe vor den Randplätzen —
        // die bleiben für die Gänge frei, solange es geht.
        let voll = plan(8).mitNeuemTisch(name: "Neun")
        #expect(voll?.tische.last?.x == Sitzplanmasse.reihenanfang
                && voll?.tische.last?.y == Sitzplanmasse.ersteReihe - Sitzplanmasse.reihenschritt)
        // Erst wenn alle inneren Plätze belegt sind, der erste Randplatz vorn links.
        let rand = plan(Sitzplanmasse.spalten * Sitzplanmasse.reihenHoechstens - 6)
        #expect(rand.tische.count == 34)
        let neun = rand.mitNeuemTisch(name: "Rand")
        #expect(neun?.tische.last?.x == Sitzplanmasse.reihenanfang + 2 * Sitzplanmasse.spaltenschritt
                && neun?.tische.last?.y == Sitzplanmasse.ersteReihe - 4 * Sitzplanmasse.reihenschritt,
                "der nächste innere Platz in der fünften Reihe")
        for tisch in mehr?.tische.dropLast() ?? [] {
            #expect(!(tisch.rahmen.intersects(mehr?.tische.last?.rahmen ?? .zero)))
        }
        p = plan(Kennwerte.maxSitzplaetze)
        #expect(p.mitNeuemTisch(name: "36") == nil)
        #expect(plan(0).mitNeuemTisch(name: "")?.tische.first?.name == "Name")
    }

    // ── Die Datei ─────────────────────────────────────────────────────────

    @Test("Datei hin und zurück: Byte für Byte derselbe Plan, kanonisch geschrieben")
    func dateiHinUndZurueck() throws {
        var plaene = ["k-eins": plan(35), "k-zwei": plan(3, klasse: "k-zwei").ohne(Sitzplan.lehrertischKennung)]
        plaene["k-zwei"] = plaene["k-zwei"]?.umbenannt(plaene["k-zwei"]!.tische[0].id, name: "Ömer Ünal / ß")
        let daten = try Sitzplandatei.schreiben(plaene)
        #expect(try Sitzplandatei.lesen(daten) == plaene)
        #expect(try Sitzplandatei.schreiben(try Sitzplandatei.lesen(daten)) == daten, "kanonisch")
        let text = String(decoding: daten, as: UTF8.self)
        #expect(text.hasPrefix("{\"plaene\":{\"k-eins\":") && text.contains("\"typ\":\"unterrichtsplanung-sitzplaene\"")
                && text.contains("\"version\":1") && text.contains("\"lehrertisch\":null"))
        #expect(try Sitzplandatei.lesen(try Sitzplandatei.schreiben([:])).isEmpty)
    }

    @Test("Datei mit Müll: Lagen geklemmt, 36 Tische gekappt, Name 101 gekürzt, leerer Name und fremde Kennung übergangen, Kennungen ersetzt")
    func dateiMuell() throws {
        let lang = String(repeating: "q", count: 101)
        var tische: [[String: Any]] = (0..<36).map { ["id": "t-\($0)", "name": "N\($0)", "x": 40, "y": 336] }
        tische[0] = ["id": "t-0", "name": lang, "x": 9999, "y": -50]
        tische[1] = ["id": "t-1", "name": "   ", "x": 0, "y": 0]
        tische[2] = ["id": "t-2", "name": "Bruch", "x": 12.7, "y": true]
        tische[3] = ["id": "t-2", "name": "Doppelt", "x": "x", "y": 8]
        tische[4] = ["id": "", "name": "Ohne Kennung", "x": 8, "y": 8]
        let roh: [String: Any] = ["typ": "unterrichtsplanung-sitzplaene", "version": 1, "plaene": [
            "k-eins": ["tische": tische, "lehrertisch": ["x": -100, "y": 9999], "geaendert": "2026-09-12T10:00:00.000Z"],
            "": ["tische": []],
            "/böse": ["tische": []],
            "k-leer": ["tische": [], "lehrertisch": NSNull()],
            "k-kaputt": "kein Objekt",
        ]]
        let gelesen = try Sitzplandatei.lesen(try JSONSerialization.data(withJSONObject: roh))
        #expect(Set(gelesen.keys) == ["k-eins", "k-leer"])
        let p = try #require(gelesen["k-eins"])
        #expect(p.tische.count == 34, "36 Einträge, einer ohne Namen, die 36. gekappt")
        #expect(p.tische[0].name.count == 100)
        #expect(p.tische[0].x == Sitzplanmasse.tischbereich.maxX - Sitzplanmasse.tischbreite && p.tische[0].y == 0)
        #expect(p.tische[1].name == "Bruch" && p.tische[1].x == 13 && p.tische[1].y == 0)
        #expect(p.tische[2].name == "Doppelt" && p.tische[2].id != "t-2" && p.tische[2].x == 0)
        #expect(p.tische[3].name == "Ohne Kennung" && Kennung.istGueltig(p.tische[3].id))
        #expect(Set(p.tische.map(\.id)).count == p.tische.count)
        #expect(p.lehrertisch == CGPoint(x: 0, y: Sitzplanmasse.lehrertischbereich.maxY - Sitzplanmasse.lehrertischhoehe))
        #expect(p.geaendert == "2026-09-12T10:00:00.000Z", "ein Stempel in der Form der App bleibt")
        #expect(gelesen["k-leer"]?.tische.isEmpty == true && gelesen["k-leer"]?.lehrertisch == nil)

        for kaputt in ["", "[]", "{}", "kein JSON",
                       "{\"typ\":\"unterrichtsplanung\",\"version\":1,\"plaene\":{}}",
                       "{\"typ\":\"unterrichtsplanung-sitzplaene\",\"version\":true,\"plaene\":{}}",
                       "{\"typ\":\"unterrichtsplanung-sitzplaene\",\"version\":1,\"plaene\":[]}"] {
            #expect(throws: Sitzplandatei.Fehler.self, "\(kaputt)") { try Sitzplandatei.lesen(Data(kaputt.utf8)) }
        }
        do {
            _ = try Sitzplandatei.lesen(Data("{\"typ\":\"unterrichtsplanung-sitzplaene\",\"version\":2,\"plaene\":{}}".utf8))
            Issue.record("eine neuere Fassung muss abgewiesen werden")
        } catch let fehler as Sitzplandatei.Fehler {
            #expect(fehler.art == .neuereFassung && fehler.text.contains("aktualisieren"))
        }
    }

    // ── Der Dienst ────────────────────────────────────────────────────────

    @Test("Dienst im Klartext: setzen schreibt die Datei, ein frischer Dienst liest sie, entfernen nimmt die Datei weg")
    func dienstKlartext() throws {
        let ort = try ordner("klartext")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let dienst = Sitzplandienst(ablage: ablage)
        #expect(dienst.laden(stempel: "s") == .keine)
        #expect(dienst.schreibbar && dienst.quelle == .klartext && !dienst.hatPlaene)
        let p = plan(12)
        #expect(dienst.setzen(p, fuer: "k-eins") == nil)
        #expect(dienst.hatPlaene && dienst.plan(fuer: "k-eins")?.tische == p.tische)
        let roh = try Data(contentsOf: ablage.sitzplaene)
        #expect(!Tresor.istBehaelter(roh) && String(decoding: roh, as: UTF8.self).contains("Name 12"))

        let frisch = Sitzplandienst(ablage: ablage)
        #expect(frisch.laden(stempel: "s") == .geladen(1))
        #expect(frisch.plan(fuer: "k-eins") == dienst.plan(fuer: "k-eins"))
        #expect(frisch.setzen(nil, fuer: "k-eins") == nil)
        #expect(!FileManager.default.fileExists(atPath: ablage.sitzplaene.path), "ohne Pläne keine Datei")
        #expect(frisch.setzen(nil, fuer: "k-eins") == nil, "nochmal entfernen ist nichts")
    }

    @Test("Dienst: versiegeln, schließen, öffnen, entsiegeln — der Behälter trägt Inhalt „sitzplaene“ und die Kennung")
    func dienstBehaelter() throws {
        let ort = try ordner("behaelter")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let dienst = Sitzplandienst(ablage: ablage)
        _ = dienst.laden(stempel: "s")
        let p = plan(5)
        dienst.setzen(p, fuer: "k-eins")
        let t = try tresor()
        try umstellen(dienst, ablage, auf: t)
        #expect(dienst.quelle == .behaelter && dienst.plan(fuer: "k-eins") != nil)
        let kopf = try kopf(ablage.sitzplaene)
        #expect(kopf.inhalt == "sitzplaene" && kopf.kennung == t.kennung)
        #expect(try Sitzplandatei.lesen(try t.oeffnen(kopf: kopf))["k-eins"]?.tische == p.tische)

        // Wie nach einem Neustart: zu, bis der Schlüssel da ist.
        let neustart = Sitzplandienst(ablage: ablage)
        neustart.schliessen()
        #expect(neustart.quelle == .zu && !neustart.schreibbar && neustart.plan(fuer: "k-eins") == nil)
        #expect(neustart.setzen(plan(2), fuer: "k-zwei") != nil, "zu heißt: nichts nehmen")
        #expect(neustart.sperrhinweis?.contains("entsperren") == true)
        #expect(neustart.oeffnen(mit: t, stempel: "s") == .geladen(1))
        #expect(neustart.quelle == .behaelter && neustart.plan(fuer: "k-eins")?.tische == p.tische)

        // Entsiegeln: der Klartext liegt wieder da.
        try umstellen(neustart, ablage, auf: nil)
        #expect(neustart.quelle == .klartext)
        #expect(!Tresor.istBehaelter(try Data(contentsOf: ablage.sitzplaene)))
        #expect(try Sitzplandatei.lesen(try Data(contentsOf: ablage.sitzplaene))["k-eins"]?.tische == p.tische)
    }

    @Test("Dienst: ein fremder Behälter wird als fremd beiseitegelegt, ein beschädigter als beschädigt, ein Behälter neben Klartext als fremd")
    func dienstBeiseitelegen() throws {
        let ort = try ordner("fremd")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let eigener = try tresor()
        let fremder = try tresor()
        try ablage.sitzplaeneSchreiben(try fremder.versiegeln(try Sitzplandatei.schreiben(["k-eins": plan(2)]),
                                                                inhalt: .sitzplaene, ziel: .ablage))
        let dienst = Sitzplandienst(ablage: ablage)
        let befund = dienst.oeffnen(mit: eigener, stempel: "s1")
        guard case .beiseitegelegt(let grund, let rettung) = befund else {
            Issue.record("erwartet beiseitegelegt, war \(befund)")
            return
        }
        #expect(grund.contains("anderen Schlüssel") && rettung == "sitzplaene-fremd-s1.json")
        #expect(FileManager.default.fileExists(atPath: ort.appendingPathComponent(rettung).path))
        #expect(!FileManager.default.fileExists(atPath: ablage.sitzplaene.path), "ohne Pläne keine Datei")
        #expect(dienst.quelle == .behaelter && !dienst.hatPlaene)

        try Data("kaputt".utf8).write(to: ablage.sitzplaene)
        let zweiter = Sitzplandienst(ablage: ablage)
        guard case .beiseitegelegt(_, let rettung2) = zweiter.oeffnen(mit: eigener, stempel: "s2") else {
            Issue.record("erwartet beiseitegelegt")
            return
        }
        #expect(rettung2 == "sitzplaene-beschaedigt-s2.json")

        // Ein Behälter neben einer Klartext-Planung: fremd, nicht beschädigt.
        try ablage.sitzplaeneSchreiben(try eigener.versiegeln(try Sitzplandatei.schreiben(["k-eins": plan(2)]),
                                                                inhalt: .sitzplaene, ziel: .ablage))
        let dritter = Sitzplandienst(ablage: ablage)
        guard case .beiseitegelegt(_, let rettung3) = dritter.laden(stempel: "s3") else {
            Issue.record("erwartet beiseitegelegt")
            return
        }
        #expect(rettung3 == "sitzplaene-fremd-s3.json" && dritter.quelle == .klartext)
        // Die Rettungskopien stehen im Register der Nebendateien.
        #expect(Set(try ablage.nebendateien().map(\.lastPathComponent))
                == ["sitzplaene-fremd-s1.json", "sitzplaene-beschaedigt-s2.json", "sitzplaene-fremd-s3.json"])
    }

    @Test("Dienst: Behälter mit anderem Inhalt, neuere Fassung und Klartext neben versiegelter Ablage")
    func dienstSonderfaelle() throws {
        let ort = try ordner("sonder")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        // Inhalt „lesezeichen“ unter dem eigenen Schlüssel: beschädigt, nicht fremd.
        try ablage.sitzplaeneSchreiben(try t.versiegeln(Data("{}".utf8), inhalt: .lesezeichen, ziel: .ablage))
        guard case .beiseitegelegt(let grund, let rettung) = Sitzplandienst(ablage: ablage).oeffnen(mit: t, stempel: "a") else {
            Issue.record("erwartet beiseitegelegt")
            return
        }
        #expect(grund.contains("lesezeichen") && rettung.hasPrefix("sitzplaene-beschaedigt-"))

        // Eine neuere Fassung bleibt liegen: gesperrt.
        try Data("{\"typ\":\"unterrichtsplanung-sitzplaene\",\"version\":9,\"plaene\":{}}".utf8).write(to: ablage.sitzplaene)
        let gesperrt = Sitzplandienst(ablage: ablage)
        guard case .gesperrt = gesperrt.laden(stempel: "b") else {
            Issue.record("erwartet gesperrt")
            return
        }
        #expect(!gesperrt.schreibbar && gesperrt.sperrhinweis?.contains("nächsten Start") == true)
        #expect(gesperrt.setzen(plan(1), fuer: "k") != nil)
        #expect(FileManager.default.fileExists(atPath: ablage.sitzplaene.path), "unangetastet")
        #expect(throws: Uebergangsfehler.self) { try gesperrt.inhalt(unter: t) }
        gesperrt.umschalten(auf: nil)
        #expect(gesperrt.sperrgrund != nil, "gesperrt bleibt gesperrt")

        // Klartext neben der versiegelten Ablage: gefunden, nicht still versiegelt
        // — erst die Antwort „Versiegeln“ schreibt den Behälter (E43 (b)).
        try Sitzplandatei.schreiben(["k-eins": plan(4)]).write(to: ablage.sitzplaene)
        let nachholer = Sitzplandienst(ablage: ablage)
        guard case .klartextGefunden(1, _, kopie: nil) = nachholer.oeffnen(mit: t, stempel: "c") else {
            Issue.record("erwartet klartextGefunden")
            return
        }
        #expect(nachholer.plan(fuer: "k-eins")?.tische.count == 4)
        nachholer.klartextVersiegeln()
        #expect(try kopf(ablage.sitzplaene).inhalt == "sitzplaene")
    }

    @Test("Dienst: der Inhalt für die Generation entsteht ohne Schreiben — nil ohne Pläne, zu liefert keinen; Umschalten folgt der Platte")
    func dienstInhalt() throws {
        let ort = try ordner("inhalt")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let dienst = Sitzplandienst(ablage: ablage)
        _ = dienst.laden(stempel: "s")
        #expect(try dienst.inhalt(unter: try tresor()) == nil, "ohne Pläne keine Datei")
        dienst.setzen(plan(3), fuer: "k-eins")
        let klartextVorher = try Data(contentsOf: ablage.sitzplaene)
        let neu = try tresor()
        let behaelter = try #require(try dienst.inhalt(unter: neu))
        #expect(try Data(contentsOf: ablage.sitzplaene) == klartextVorher, "nichts geschrieben")
        #expect(dienst.quelle == .klartext, "die Sitzung bleibt, bis die Marke liegt")
        let kopf = try Tresor.kopfLesen(behaelter)
        #expect(kopf.inhalt == "sitzplaene" && kopf.kennung == neu.kennung)
        #expect(try Sitzplandatei.lesen(try neu.oeffnen(kopf: kopf))["k-eins"]?.tische.count == 3)
        #expect(try dienst.inhalt(unter: nil) == klartextVorher, "der Klartext ist derselbe")

        // Umschalten nach dem Einsetzen: Schlüssel und Quelle folgen, nichts wird geschrieben.
        try ablage.sitzplaeneSchreiben(behaelter)
        dienst.umschalten(auf: neu)
        #expect(dienst.quelle == .behaelter && dienst.ungesichert == nil && dienst.plan(fuer: "k-eins") != nil)
        #expect(try Data(contentsOf: ablage.sitzplaene) == behaelter, "unverändert")
        // Der nächste Schreibanlass geht unter dem neuen Schlüssel.
        dienst.setzen(plan(4), fuer: "k-zwei")
        #expect(try self.kopf(ablage.sitzplaene).kennung == neu.kennung)

        // Zu: kein Inhalt — die Datei gehört nicht in die Generation; Umschalten lässt zu zu.
        let zu = Sitzplandienst(ablage: ablage)
        zu.schliessen()
        #expect(throws: Uebergangsfehler.self) { try zu.inhalt(unter: neu) }
        zu.umschalten(auf: nil)
        #expect(zu.quelle == .zu)

        // E46: Das Original einer verlustbehaftet gelesenen Datei muss bewahrt sein, bevor der Übergang es ersetzt.
        let ort2 = try ordner("inhalt-kopie")
        defer { aufraeumen(ort2) }
        let ablage2 = Ablage(ordner: ort2)
        let roh: [String: Any] = ["typ": Sitzplandatei.typ, "version": 1, "plaene": [
            "k-eins": ["tische": [["id": "t-1", "name": String(repeating: "q", count: 120), "x": 40, "y": 336]]]]]
        try JSONSerialization.data(withJSONObject: roh).write(to: ablage2.sitzplaene)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ort2.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort2.path) }
        let bereinigt = Sitzplandienst(ablage: ablage2)
        guard case .bereinigt(1, _, kopie: nil) = bereinigt.laden(stempel: "s") else {
            Issue.record("erwartet bereinigt ohne Kopie")
            return
        }
        #expect(throws: Uebergangsfehler.self, "ohne Kopie kein Inhalt") { try bereinigt.inhalt(unter: neu) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort2.path)
        #expect(try bereinigt.inhalt(unter: neu) != nil)
        #expect(bereinigt.ausstehendeKopie == nil && FileManager.default.fileExists(atPath: ort2.appendingPathComponent("sitzplaene-bereinigt-s.json").path))
    }

    @Test("Dienst: entfernen und umschreiben — Klasse weg, Plan weg; Übernahme trägt den Plan unter die neue Kennung")
    func dienstUmschreiben() throws {
        let ort = try ordner("umschreiben")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let dienst = Sitzplandienst(ablage: ablage)
        _ = dienst.laden(stempel: "s")
        dienst.setzen(plan(2), fuer: "k-eins")
        dienst.setzen(plan(3, klasse: "k-zwei"), fuer: "k-zwei")
        dienst.setzen(plan(4, klasse: "k-drei"), fuer: "k-drei")
        #expect(dienst.entfernen(klassen: ["k-drei", "k-nie"]) == nil)
        #expect(Set(dienst.plaene.keys) == ["k-eins", "k-zwei"])
        #expect(dienst.umschreiben(zuordnung: ["k-eins": "k-neu"]) == nil)
        #expect(Set(dienst.plaene.keys) == ["k-neu"])
        #expect(dienst.plan(fuer: "k-neu")?.klasseId == "k-neu" && dienst.plan(fuer: "k-neu")?.tische.count == 2)
        #expect(dienst.umschreiben(zuordnung: [:]) == nil && dienst.plaene.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: ablage.sitzplaene.path))
    }

    @Test("Vorschau schreibt nicht: Pläne gelten für die Sitzung, die Platte bleibt leer")
    func vorschau() throws {
        let ort = try ordner("vorschau")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let dienst = Sitzplandienst(ablage: ablage, vorschau: true)
        #expect(dienst.laden(stempel: "s") == .keine)
        #expect(dienst.setzen(plan(2), fuer: "k-eins") == nil && dienst.hatPlaene)
        #expect(!FileManager.default.fileExists(atPath: ablage.sitzplaene.path))
        let t = try tresor()
        #expect(try dienst.inhalt(unter: t) != nil)
        dienst.umschalten(auf: t)
        #expect(dienst.quelle == .behaelter && dienst.hatPlaene)
        #expect(!FileManager.default.fileExists(atPath: ablage.sitzplaene.path))
    }

    // ── Der Speicher: Übergänge des Schutzes ──────────────────────────────

    @Test("Einschalten versiegelt die Klartext-Sitzpläne mit; Aufheben legt sie wieder im Klartext hin")
    func einschaltenUndAufheben() throws {
        let ort = try ordner("einschalten")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first?.id)
        #expect(s.sitzplanUebernehmen(plan(6, klasse: klasse)) == nil)
        let ablage = Ablage(ordner: ort)
        #expect(!Tresor.istBehaelter(try Data(contentsOf: ablage.sitzplaene)), "Klartext neben Klartext")

        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        let tresor = try #require(s.tresor)
        #expect(ergebnis.ablage == .geschrieben && ergebnis.sitzplaene == .erledigt && ergebnis.offenes.isEmpty)
        #expect(s.sitzplaene.quelle == .behaelter)
        let kopf = try kopf(ablage.sitzplaene)
        #expect(kopf.inhalt == "sitzplaene" && kopf.kennung == tresor.kennung)
        #expect(try Sitzplandatei.lesen(try tresor.oeffnen(kopf: kopf))[klasse]?.tische.count == 6)
        #expect(s.sitzplan(fuer: klasse)?.tische.count == 6, "in der Sitzung unverändert")

        let aufgehoben = s.verschluesselungAufheben()
        #expect(aufgehoben.ablage == .geschrieben && aufgehoben.sitzplaene == .erledigt)
        #expect(s.sitzplaene.quelle == .klartext)
        #expect(!Tresor.istBehaelter(try Data(contentsOf: ablage.sitzplaene)))
        #expect(try Sitzplandatei.lesen(try Data(contentsOf: ablage.sitzplaene))[klasse]?.tische.count == 6)
    }

    @Test("Einschalten ohne Sitzpläne: nichts nötig, keine Datei; ein Ordner an der Stelle der Sitzpläne ⇒ Erneuern zurückgenommen vor der Marke, Lesezeichen und Ablage beim alten Schlüssel")
    func erneuernScheitert() throws {
        let ort = try ordner("erneuern")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ohne = s.verschluesselungEinschalten()
        #expect(ohne.ablage == .geschrieben && ohne.sitzplaene == .nichtNoetig)
        let ablage = Ablage(ordner: ort)
        #expect(!FileManager.default.fileExists(atPath: ablage.sitzplaene.path))
        let alt = try #require(s.tresor)

        let klasse = try #require(s.planung?.klassen.first?.id)
        s.sitzplanUebernehmen(plan(7, klasse: klasse))
        #expect(try kopf(ablage.sitzplaene).kennung == alt.kennung)
        // Ein Ordner im Weg: Der Sitzplan-Behälter lässt sich nicht schreiben.
        try FileManager.default.removeItem(at: ablage.sitzplaene)
        try FileManager.default.createDirectory(at: ablage.sitzplaene, withIntermediateDirectories: false)
        _ = try s.schluesselErneuernVorbereiten(alt: passphrase, neu: "Ein anderer Satz")
        let ergebnis = s.verschluesselungEinschalten()
        guard case .zurueckgenommen(let grund) = ergebnis.ablage else {
            Issue.record("erwartet zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(grund.contains("sitzplaene.json") && grund.contains("Ordner"), "\(grund)")
        #expect(s.tresor?.kennung == alt.kennung, "die Sitzung behält den alten Schlüssel")
        #expect(try kopf(ablage.datei).kennung == alt.kennung, "die Ablage auch")
        #expect(try kopf(ablage.lesezeichen).kennung == alt.kennung, "die Lesezeichen blieben, wie sie waren")
        #expect(s.sitzplan(fuer: klasse)?.tische.count == 7, "der Plan gilt weiter")
        try FileManager.default.removeItem(at: ablage.sitzplaene)
        // Der nächste Schreibanlass legt den Behälter unter dem alten Schlüssel hin.
        s.sitzplanUebernehmen(plan(8, klasse: klasse))
        #expect(try kopf(ablage.sitzplaene).kennung == alt.kennung)
    }

    @Test("Erneuern und Passphrase ändern: der Sitzplan-Behälter wandert mit — der alte Schlüssel öffnet ihn nicht mehr")
    func erneuernUndPassphrase() throws {
        let ort = try ordner("wandert")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first?.id)
        s.sitzplanUebernehmen(plan(5, klasse: klasse))
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        _ = s.verschluesselungEinschalten()
        let alt = try #require(s.tresor)
        let ablage = Ablage(ordner: ort)

        _ = try s.schluesselErneuernVorbereiten(alt: passphrase, neu: "Ein anderer Satz")
        let erneuert = s.verschluesselungEinschalten()
        let neu = try #require(s.tresor)
        #expect(erneuert.ablage == .geschrieben && erneuert.sitzplaene == .erledigt)
        #expect(neu.kennung != alt.kennung)
        let kopf1 = try kopf(ablage.sitzplaene)
        #expect(kopf1.kennung == neu.kennung)
        #expect(throws: Tresorfehler.self) { try alt.oeffnen(kopf: kopf1) }
        #expect(try Sitzplandatei.lesen(try neu.oeffnen(kopf: kopf1))[klasse]?.tische.count == 5)

        let geaendert = try s.passphraseAendern(alt: "Ein anderer Satz", neu: "Der dritte Satz")
        #expect(geaendert.ablage == .geschrieben && geaendert.sitzplaene == .erledigt)
        let kopf2 = try kopf(ablage.sitzplaene)
        #expect(try Tresor.oeffnen(kopf: kopf2, passphrase: "Der dritte Satz").kennung == neu.kennung)
        #expect(throws: Tresorfehler.self) { try Tresor.oeffnen(kopf: kopf2, passphrase: "Ein anderer Satz") }
    }

    @Test("Neustart hinter versiegelter Ablage: zu bis zum Entsperren, danach offen — auch die dritte Spalte weiß es")
    func neustart() async throws {
        let ort = try ordner("neustart")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first?.id)
        s.sitzplanUebernehmen(plan(9, klasse: klasse))
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        _ = s.verschluesselungEinschalten()
        s.jetztSichern()

        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ort))
        zweiter.starten()
        #expect(zweiter.verschluesselungsstand == .gesperrt)
        #expect(zweiter.sitzplaene.quelle == .zu && zweiter.sitzplan(fuer: klasse) == nil)
        #expect(zweiter.sitzplaene.sperrhinweis?.contains("entsperren") == true)
        zweiter.sitzplanOeffnen(klasse: klasse)
        #expect(zweiter.offenerDialog != .sitzplan, "zu heißt: kein Editor")

        await zweiter.entsperren(passphrase: passphrase)
        #expect(zweiter.verschluesselungsstand == .an)
        #expect(zweiter.sitzplaene.quelle == .behaelter)
        #expect(zweiter.sitzplan(fuer: klasse)?.tische.count == 9)
        zweiter.sitzplanOeffnen(klasse: klasse, zurueck: .klassen)
        #expect(zweiter.offenerDialog == .sitzplan && zweiter.sitzplanKlasse == klasse
                && zweiter.sitzplanEntwurf?.tische.count == 9)
        zweiter.sitzplanDialogSchliessen()
        #expect(zweiter.sitzplanEntwurf == nil && zweiter.naechsterDialog == .klassen)
    }

    @Test("Klasse entfernen nimmt den Sitzplan mit — nach der Rückfrage, die ihn nennt")
    func klasseEntfernen() throws {
        let ort = try ordner("klasse")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first)
        s.sitzplanUebernehmen(plan(4, klasse: klasse.id))
        s.klasseEntfernen(klasse)
        let frage = try #require(s.rueckfrage)
        #expect(frage.text.contains("Sitzplan") && frage.ort == .klassen)
        s.rueckfrageBeantworten(false)
        #expect(s.sitzplan(fuer: klasse.id) != nil && s.planung?.klasse(klasse.id) != nil, "abgebrochen")
        s.klasseEntfernen(klasse)
        s.rueckfrageBeantworten(true)
        #expect(s.planung?.klasse(klasse.id) == nil && s.sitzplan(fuer: klasse.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: Ablage(ordner: ort).sitzplaene.path))
    }

    @Test("Sitzplan entfernen: zweistufig — die Rückfrage, dann erst weg; danach läuft die Fortsetzung")
    func sitzplanEntfernen() throws {
        let ort = try ordner("entfernen")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first)
        s.sitzplanUebernehmen(plan(4, klasse: klasse.id))
        var fortgesetzt = 0
        s.sitzplanEntfernen(klasse: klasse.id, ort: .sitzplan) { fortgesetzt += 1 }
        let frage = try #require(s.rueckfrage)
        #expect(frage.gefahr && frage.ort == .sitzplan && frage.bestaetigung == "Sitzplan löschen")
        s.rueckfrageBeantworten(false)
        #expect(s.sitzplan(fuer: klasse.id) != nil && fortgesetzt == 0)
        s.sitzplanEntfernen(klasse: klasse.id, ort: .klassen)
        s.rueckfrageBeantworten(true)
        #expect(s.sitzplan(fuer: klasse.id) == nil)
        s.sitzplanEntfernen(klasse: klasse.id, ort: .klassen)
        #expect(s.rueckfrage == nil, "ohne Plan keine Frage")
    }

    @Test("Neue Planung: der Sitzplan folgt der übernommenen Klasse unter die neue Kennung, die übrigen fallen weg")
    func neuePlanung() throws {
        let ort = try ordner("neu")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let alte = try #require(s.planung?.klassen)
        s.sitzplanUebernehmen(plan(4, klasse: alte[0].id))
        s.sitzplanUebernehmen(plan(5, klasse: alte[1].id))
        s.neuePlanung(titel: "Neu", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                      klassen: Standardkurse.aufbauen([("5c", "Biologie")]), ersterSchultag: nil,
                      uebernahme: [Planung.Uebernahmewunsch(klasse: alte[0], mitVorhaben: true)])
        let neue = try #require(s.planung)
        #expect(neue.klassen.count == 2)
        let uebernommen = try #require(neue.klassen.first { $0.name == "7a" })
        #expect(uebernommen.id != alte[0].id)
        #expect(Set(s.sitzplaene.plaene.keys) == [uebernommen.id])
        #expect(s.sitzplan(fuer: uebernommen.id)?.tische.count == 4 && s.sitzplan(fuer: uebernommen.id)?.klasseId == uebernommen.id)
        // Ohne Übernahme: alles weg.
        s.neuePlanung(titel: "Leer", start: try #require(Tag(iso: "2028-08-07")), wochen: 2, basis: "",
                      klassen: [], ersterSchultag: nil, uebernahme: [])
        #expect(s.sitzplaene.plaene.isEmpty)
    }

    @Test("Übernahmebilanz nennt die Zuordnung alter zu neuer Kennung — nur für aufgenommene Zeilen")
    func zuordnung() throws {
        let alte = try planung()
        let (neue, bilanz) = Planung.mitUebernahme(
            titel: "Neu", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "", klassen: [],
            fachfarben: [:], von: alte,
            uebernahme: [Planung.Uebernahmewunsch(klasse: alte.klassen[1], mitVorhaben: false)])
        #expect(bilanz.zuordnung.count == 1 && bilanz.zuordnung[alte.klassen[1].id] == neue.klassen[0].id)
        let (_, ohne) = Planung.mitUebernahme(
            titel: "Neu", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "", klassen: [],
            fachfarben: [:], von: alte, uebernahme: [])
        #expect(ohne.zuordnung.isEmpty)
    }

    @Test("Druck: die Kopfzeile nennt Klasse, Fach, Sitzplan und Stand; die PDF ist eine Seite A4 quer")
    func druck() throws {
        var klasse = Standardkurse.aufbauen([("7a", "Mathematik")])[0]
        var p = plan(3, klasse: klasse.id)
        p.geaendert = "2026-09-11T10:15:00.000Z"
        #expect(Sitzplandruck.kopfzeile(klasse, plan: p) == "7a · Mathematik · Sitzplan · Stand 11.09.2026")
        klasse.fach = ""
        #expect(Sitzplandruck.kopfzeile(klasse, plan: p) == "7a · Sitzplan · Stand 11.09.2026")
        p.geaendert = ""
        #expect(Sitzplandruck.kopfzeile(klasse, plan: p).hasSuffix("Stand " + Tag.heute.deutsch))

        let daten = try #require(Sitzplandruck.pdf(p, klasse: klasse))
        let quelle = try #require(CGDataProvider(data: daten as CFData))
        let pdf = try #require(CGPDFDocument(quelle))
        #expect(pdf.numberOfPages == 1)
        let kasten = try #require(pdf.page(at: 1)).getBoxRect(.mediaBox)
        #expect(Int(kasten.width) == 842 && Int(kasten.height) == 595)
        #expect(Sitzplanblatt(daten, mass: CGSize(width: 700, height: 500)) != nil)
        #expect(Sitzplanblatt(Data("kein PDF".utf8), mass: CGSize(width: 700, height: 500)) == nil)
    }

    @Test("Sitzplanansicht: Klick wählt, Ziehen verschiebt eingerastet, ⌥ frei, Kontextmenü-Weg entfernt")
    func ansicht() {
        let p = plan(4)
        let ansicht = Sitzplanansicht(plan: p, ton: Farbwelt.ton(0))
        var gemeldet: [Sitzplan] = []
        var auswahlen: [Set<String>] = []
        ansicht.beiAenderung = { gemeldet.append($0) }
        ansicht.beiAuswahl = { auswahlen.append($0) }
        // Ohne Fenster: die Fläche misst sich selbst.
        #expect(ansicht.intrinsicContentSize == NSSize(width: Sitzplanmasse.breite, height: Sitzplanmasse.hoehe))
        #expect(ansicht.isFlipped && ansicht.acceptsFirstResponder)
        // Bedienungshilfen ohne Fenster: nichts — mit Fenster je Tisch ein Element.
        #expect(ansicht.accessibilityChildren() == nil)
        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                               styleMask: [.titled], backing: .buffered, defer: true)
        fenster.contentView = ansicht
        let kinder = ansicht.accessibilityChildren() as? [NSAccessibilityElement]
        #expect(kinder?.count == 4 + 2, "vier Tische, Lehrertisch, Tafel")
        #expect(kinder?.first?.accessibilityLabel()?.hasPrefix("Tisch: Name 1") == true)
        ansicht.auswahl = [p.tische[0].id]
        ansicht.plan = p.verschoben([p.tische[0].id], um: CGPoint(x: 8, y: 0))
        #expect(ansicht.plan.tische[0].x == p.tische[0].x + 8)
        #expect(gemeldet.isEmpty && auswahlen.isEmpty, "von außen gesetzt heißt: nicht zurückgemeldet")

        // Tastatur (B06, B08): ⌫ entfernt die Auswahl, ⏎ ruft den Haken, ⌥⏎ öffnet das Namensfeld.
        var uebernommen = 0
        ansicht.beiUebernehmen = { uebernommen += 1 }
        func taste(_ code: UInt16, _ tasten: NSEvent.ModifierFlags = []) {
            guard let ereignis = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: tasten, timestamp: 0,
                                                  windowNumber: 0, context: nil, characters: "",
                                                  charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)
            else { return }
            ansicht.keyDown(with: ereignis)
        }
        ansicht.auswahl = [p.tische[1].id, p.tische[2].id]
        taste(51)
        #expect(ansicht.plan.tische.count == 2 && gemeldet.last?.tische.count == 2 && ansicht.auswahl.isEmpty)
        taste(36)
        #expect(uebernommen == 1, "⏎ übernimmt über den Haken")
        ansicht.auswahl = [ansicht.plan.tische[0].id]
        taste(36, .option)
        #expect(ansicht.subviews.contains { $0 is NSTextField }, "⌥⏎ öffnet das Namensfeld")
    }

    @Test("E40: die Sitzplan-PDF trägt auf Wunsch ein Kennwort — ohne geht sie nicht auf, mit schon")
    func pdfKennwort() throws {
        let klasse = Standardkurse.aufbauen([("7a", "Mathematik")])[0]
        let p = plan(3, klasse: klasse.id)
        let daten = try #require(Sitzplandruck.pdf(p, klasse: klasse, kennwort: "geheim"))
        let quelle = try #require(CGDataProvider(data: daten as CFData))
        let pdf = try #require(CGPDFDocument(quelle))
        #expect(pdf.isEncrypted && !pdf.isUnlocked)
        #expect(!pdf.unlockWithPassword("falsch"))
        #expect(pdf.unlockWithPassword("geheim") && pdf.isUnlocked && pdf.numberOfPages == 1)
        let offen = try #require(Sitzplandruck.pdf(p, klasse: klasse))
        let offeneQuelle = try #require(CGDataProvider(data: offen as CFData))
        let offenesPdf = try #require(CGPDFDocument(offeneQuelle))
        #expect(!offenesPdf.isEncrypted)
        #expect(Sitzplandruck.pdf(p, klasse: klasse, kennwort: "").map { CGDataProvider(data: $0 as CFData).flatMap(CGPDFDocument.init)?.isEncrypted } == false,
                "ein leeres Kennwort heißt: kein Schutz")
    }

    // ── v49: Behebungen nach den Reviews (JB1–JB3) ────────────────────────

    @Test("B01: jeder Zeilenwechsel trennt Namen — \\r, U+2028; ein eingesetzter Absatz wird beim Umbenennen eine Zeile")
    func zeilenwechsel() {
        let liste = Sitzplan.namenLesen("Anna\rBen\u{2028}Cem\r\n\nDana")
        #expect(liste.namen == ["Anna", "Ben", "Cem", "Dana"])
        #expect(liste.fehler.isEmpty)
        let zeilen = Sitzplan.namenLesen("A\n\n\n" + String(repeating: "x", count: 101))
        #expect(zeilen.fehler.first?.nummer == 4, "die Zeilennummer zählt leere Zeilen mit")
        let p = plan(2)
        #expect(p.umbenannt(p.tische[0].id, name: "Mia\r\nNeu  \n").tisch(p.tische[0].id)?.name == "Mia Neu")
    }

    @Test("B07: ein Tisch über dem Lehrertisch ist das, was der Klick trifft")
    func trefferreihenfolge() throws {
        var p = plan(1)
        let lehrer = try #require(p.lehrertisch)
        p.tische[0].x = lehrer.x
        p.tische[0].y = lehrer.y
        #expect(p.element(bei: CGPoint(x: lehrer.x + 8, y: lehrer.y + 8)) == p.tische[0].id)
        #expect(p.element(bei: CGPoint(x: lehrer.x + Sitzplanmasse.lehrertischbreite - 4, y: lehrer.y + 8))
                == Sitzplan.lehrertischKennung)
    }

    @Test("B14/H01: die Bilanz nennt, was das Lesen wegnahm oder änderte; ein unlesbarer Stempel wird geleert")
    func lesebilanz() throws {
        var tische: [[String: Any]] = (0..<36).map { ["id": "t-\($0)", "name": "N\($0)", "x": 40, "y": 336] }
        tische[0] = ["id": "t-0", "name": String(repeating: "q", count: 101), "x": 9999, "y": -50]
        tische[1] = ["id": "t-1", "name": "   ", "x": 0, "y": 0]
        tische[2] = ["id": "t-2", "name": "Bruch", "x": 12.7, "y": true]
        tische[3] = ["id": "t-2", "name": "Doppelt", "x": "x", "y": 8]
        tische[4] = ["id": "", "name": "Ohne Kennung", "x": 8, "y": 8]
        let roh: [String: Any] = ["typ": Sitzplandatei.typ, "version": 1, "plaene": [
            "k-eins": ["tische": tische, "lehrertisch": ["x": -100, "y": 9999], "geaendert": "gestern"],
            "": ["tische": []],
            "/böse": ["tische": []],
            "k-kaputt": "kein Objekt",
            "k-sauber": ["tische": [["id": "t-9", "name": "Sauber", "x": 96, "y": 336]],
                         "lehrertisch": NSNull(), "geaendert": "2026-09-12T10:00:00.000Z"],
        ]]
        let (gelesen, bilanz) = try Sitzplandatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: roh))
        #expect(gelesen.count == 2)
        #expect(bilanz.verworfeneKlassen == 3 && bilanz.verworfeneTische == 2 && bilanz.gekuerzteNamen == 1)
        #expect(bilanz.ersetzteKennungen == 2 && bilanz.bereinigteStempel == 1 && bilanz.geklemmteLagen == 4)
        #expect(bilanz.verlust && !bilanz.istLeer)
        #expect(bilanz.beschreibung.contains("3 Klassen") && bilanz.beschreibung.contains("1 Name gekürzt"))
        #expect(gelesen["k-eins"]?.geaendert == "" && gelesen["k-sauber"]?.geaendert == "2026-09-12T10:00:00.000Z")
        let sauber = try Sitzplandatei.lesenMitBilanz(try Sitzplandatei.schreiben(["k": plan(3, klasse: "k")]))
        #expect(sauber.bilanz.istLeer && !sauber.bilanz.verlust)
    }

    @Test("B14: ein Dienst, der mit Verlust liest, meldet es und bewahrt das Original im Register")
    func dienstBereinigt() throws {
        let ort = try ordner("bereinigt")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let roh: [String: Any] = ["typ": Sitzplandatei.typ, "version": 1, "plaene": [
            "k-eins": ["tische": [["id": "t-1", "name": String(repeating: "q", count: 120), "x": 40, "y": 336],
                                  ["id": "t-2", "name": "", "x": 40, "y": 200]]]]]
        let original = try JSONSerialization.data(withJSONObject: roh)
        try original.write(to: ablage.sitzplaene)
        let dienst = Sitzplandienst(ablage: ablage)
        guard case .bereinigt(let anzahl, let bilanz, let kopie) = dienst.laden(stempel: "s1") else {
            Issue.record("erwartet bereinigt")
            return
        }
        #expect(anzahl == 1 && bilanz.gekuerzteNamen == 1 && bilanz.verworfeneTische == 1)
        #expect(kopie == "sitzplaene-bereinigt-s1.json")
        let bewahrt = try Data(contentsOf: ort.appendingPathComponent("sitzplaene-bereinigt-s1.json"))
        #expect(bewahrt == original)
        let register = try ablage.nebendateien().map(\.lastPathComponent)
        #expect(register == ["sitzplaene-bereinigt-s1.json"])
        #expect(dienst.plan(fuer: "k-eins")?.tische.count == 1)
    }

    @Test("B05/E43: „Versiegeln“ mit scheiterndem Schreiben meldet nicht „versiegelt“ — ungesichert; nachholen() holt es nach")
    func nachgeholtScheitert() throws {
        let ort = try ordner("nachholen")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        try Sitzplandatei.schreiben(["k-eins": plan(4)]).write(to: ablage.sitzplaene)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ort.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort.path) }
        let dienst = Sitzplandienst(ablage: ablage)
        guard case .klartextGefunden(1, _, kopie: nil) = dienst.oeffnen(mit: try tresor(), stempel: "s") else {
            Issue.record("erwartet klartextGefunden")
            return
        }
        dienst.klartextVersiegeln()
        #expect(dienst.ungesichert != nil && dienst.plan(fuer: "k-eins")?.tische.count == 4)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort.path)
        dienst.nachholen()
        let danach = try Data(contentsOf: ablage.sitzplaene)
        #expect(dienst.ungesichert == nil && Tresor.istBehaelter(danach))
    }

    @Test("B02/E38: ohne Schreibrecht entsteht die Generation des Aufhebens nicht — zurückgenommen vor der Marke; bei gesperrtem Dienst abgewiesen")
    func aufhebenZurueckgenommen() async throws {
        let ort = try ordner("aufheben-speicher")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first?.id)
        s.sitzplanUebernehmen(plan(5, klasse: klasse))
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        _ = s.verschluesselungEinschalten()
        let tresor = try #require(s.tresor)
        let ablage = Ablage(ordner: ort)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ort.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort.path) }
        let ergebnis = s.verschluesselungAufheben()
        guard case .zurueckgenommen(let grund) = ergebnis.ablage else {
            Issue.record("erwartet zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(grund.contains("Generation"), "\(grund)")
        #expect(s.tresor?.kennung == tresor.kennung && s.sitzplaene.quelle == .behaelter)
        #expect(Tresor.istBehaelter(try Data(contentsOf: ablage.sitzplaene)))
        #expect(Tresor.istBehaelter(try Data(contentsOf: ablage.datei)))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort.path)

        // Gesperrter Dienst (Datei aus einer neueren Fassung): abgewiesen (E38 (a)).
        try Data("{\"typ\":\"unterrichtsplanung-sitzplaene\",\"version\":9,\"plaene\":{}}".utf8).write(to: ablage.sitzplaene)
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ort))
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        #expect(zweiter.verschluesselungsstand == .an && zweiter.sitzplaene.sperrgrund != nil)
        guard case .zurueckgenommen(let grund2) = zweiter.verschluesselungAufheben().ablage else {
            Issue.record("erwartet abgewiesen")
            return
        }
        #expect(grund2.contains("nicht lesbar") && zweiter.tresor != nil)
        #expect(Tresor.istBehaelter(try Data(contentsOf: ablage.datei)), "die Ablage bleibt versiegelt")
    }

    @Test("B03: Einschalten aus dem Klartext bei gesperrtem Dienst — eingeschaltet, die Datei bleibt liegen und wird benannt")
    func einschaltenBeiGesperrtemDienst() throws {
        let ort = try ordner("einschalten-gesperrt")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let alt = Data("{\"typ\":\"unterrichtsplanung-sitzplaene\",\"version\":9,\"plaene\":{}}".utf8)
        try alt.write(to: ablage.sitzplaene)
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        #expect(s.sitzplaene.sperrgrund != nil)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        #expect(ergebnis.ablage == .geschrieben)
        guard case .offen(let grund) = ergebnis.sitzplaene else {
            Issue.record("erwartet offen, war \(ergebnis.sitzplaene)")
            return
        }
        #expect(grund.contains("nächsten Start"))
        let liegt = try Data(contentsOf: ablage.sitzplaene)
        #expect(liegt == alt, "unangetastet")
        #expect(Tresor.istBehaelter(try Data(contentsOf: ablage.datei)))
    }

    @Test("B09/E47: unveränderbare Sitzpläne oder Lesezeichen — die Passphrase ändert sich nicht, nichts trägt zwei Hüllen; danach gelingt es, ein Stand")
    func huelleInEinemStand() async throws {
        let ort = try ordner("huelle")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first?.id)
        s.sitzplanUebernehmen(plan(6, klasse: klasse))
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        _ = s.verschluesselungEinschalten()
        s.jetztSichern()
        let ablage = Ablage(ordner: ort)
        let dateien = [ablage.sitzplaene, ablage.lesezeichen]
        for datei in dateien { try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: datei.path) }
        defer { for datei in dateien { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: datei.path) } }
        let neu = "Ein ganz anderer Satz"
        let abgewiesen = try s.passphraseAendern(alt: passphrase, neu: neu)
        guard case .zurueckgenommen(let grund) = abgewiesen.ablage else {
            Issue.record("erwartet zurückgenommen, war \(abgewiesen.ablage)")
            return
        }
        #expect(grund.contains("nicht ersetzen"), "\(grund)")
        // Alles trägt noch die alte Hülle — auch die Ablage.
        for datei in dateien + [ablage.datei] {
            _ = try Tresor.oeffnen(kopf: try kopf(datei), passphrase: passphrase)
        }
        for datei in dateien { try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: datei.path) }

        #expect(try s.passphraseAendern(alt: passphrase, neu: neu).ablage == .geschrieben)
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ort))
        zweiter.starten()
        await zweiter.entsperren(passphrase: neu)
        #expect(zweiter.verschluesselungsstand == .an && zweiter.sitzplan(fuer: klasse)?.tische.count == 6)
        for datei in dateien + [ablage.datei, ablage.vorherigeFassung] {
            let k = try kopf(datei)
            #expect(throws: Tresorfehler.self, "\(datei.lastPathComponent) öffnet mit der alten Passphrase") {
                try Tresor.oeffnen(kopf: k, passphrase: passphrase)
            }
            _ = try Tresor.oeffnen(kopf: k, passphrase: neu)
        }
        #expect(!zweiter.meldungen.contains { $0.text.contains("neu versiegelt") || $0.text.contains("galten nicht") },
                "\(zweiter.meldungen.map(\.text))")
    }

    @Test("B10: ein Sitzplan, den die Platte nicht trägt, hält das Beenden auf — jetztSichern holt ihn nach")
    func beendenWaechter() throws {
        let ort = try ordner("beenden")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        s.jetztSichern()
        let klasse = try #require(s.planung?.klassen.first?.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ort.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort.path) }
        #expect(s.sitzplanUebernehmen(plan(3, klasse: klasse)) != nil)
        #expect(s.verlustDroht && !s.beendenBeiLetztemFenster)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort.path)
        s.jetztSichern()
        #expect(s.sitzplaene.ungesichert == nil && !s.verlustDroht)
        #expect(FileManager.default.fileExists(atPath: Ablage(ordner: ort).sitzplaene.path))
    }

    @Test("E41: Sitzpläne ohne Klasse räumt der Speicher auf — mit Rettungskopie im Register")
    func verwaisteAufgeraeumt() throws {
        let ort = try ordner("verwaist")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first?.id)
        s.sitzplanUebernehmen(plan(2, klasse: klasse))
        s.sitzplaene.setzen(plan(3, klasse: "k-fort"), fuer: "k-fort")
        #expect(s.sitzplaene.plaene.count == 2)
        s.sitzplaeneAufraeumen()
        #expect(Set(s.sitzplaene.plaene.keys) == [klasse])
        let ablage = Ablage(ordner: ort)
        let kopien = try ablage.nebendateien().map(\.lastPathComponent).filter { $0.hasPrefix("sitzplaene-verwaist-") }
        #expect(kopien.count == 1)
        let gerettet = try Sitzplandatei.lesen(try Data(contentsOf: ort.appendingPathComponent(kopien[0])))
        #expect(gerettet["k-fort"]?.tische.count == 3)
        #expect(s.meldungen.last?.text.contains("ohne Klasse") == true)
        s.sitzplaeneAufraeumen()
        let registerDanach = try ablage.nebendateien()
        #expect(registerDanach.count == 1, "nichts mehr zu tun")
    }

    @Test("B02/E47: unveränderbare Ablage beim Einschalten — zurückgenommen vor der Marke, die Sitzpläne blieben im Klartext")
    func ruecknahmeEinschalten() throws {
        let ort = try ordner("ruecknahme")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        s.jetztSichern()
        let klasse = try #require(s.planung?.klassen.first?.id)
        s.sitzplanUebernehmen(plan(4, klasse: klasse))
        let ablage = Ablage(ordner: ort)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: ablage.datei.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: ablage.datei.path) }
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        guard case .zurueckgenommen = ergebnis.ablage else {
            Issue.record("erwartet zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(s.tresor == nil && s.sitzplaene.quelle == .klartext)
        #expect(!Tresor.istBehaelter(try Data(contentsOf: ablage.sitzplaene)))
        #expect(ergebnis.sitzplaene != .erledigt)
        #expect(s.sitzplan(fuer: klasse)?.tische.count == 4)
    }

    // ── v50: Behebungen nach der externen Review an v49 (KB1–KB6) ─────────

    @Test("B17: die Rücknahme-Meldung nennt die Sitzpläne")
    func ruecknahmeMeldung() throws {
        let s = Planungsspeicher(vorschau: try planung())
        s.schutzMelden(Planungsspeicher.Schutzergebnis(ablage: .zurueckgenommen("kein Platz"),
                                                       sitzplaene: .offen("liegen im Klartext")),
                       getan: "Verschlüsselung aufgehoben", nichtGetan: "Verschlüsselung nicht aufgehoben")
        let text = s.meldungen.last?.text ?? ""
        #expect(text.contains("nicht aufgehoben: kein Platz") && text.contains("Sitzpläne: liegen im Klartext."))
    }

    @Test("B23: eine Tischliste, die keine ist, verwirft den Plan und zählt ihn; ein Lehrertisch falscher Form wird benannt; fehlende Schlüssel bleiben gültig")
    func falscheForm() throws {
        let roh: [String: Any] = ["typ": Sitzplandatei.typ, "version": 1, "plaene": [
            "k-eins": ["tische": ["a": 1]],
            "k-zwei": ["tische": "x"],
            "k-drei": ["tische": [["id": "t-1", "name": "Mia", "x": 40, "y": 336]], "lehrertisch": "oben"],
            "k-vier": [String: Any]()]]
        let (plaene, bilanz) = try Sitzplandatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: roh))
        #expect(Set(plaene.keys) == ["k-drei", "k-vier"])
        #expect(bilanz.verworfeneKlassen == 2 && bilanz.verworfeneFelder == 1 && bilanz.verlust)
        #expect(plaene["k-vier"]?.tische.isEmpty == true)
        let drei = try #require(plaene["k-drei"])
        #expect(drei.lehrertisch == nil)
        #expect(bilanz.beschreibung.contains("Feld ohne lesbare Form"))
    }

    @Test("E46: scheitert die Rettungskopie, geht nichts über das Original — bis die Kopie liegt")
    func kopieScheitert() throws {
        let ort = try ordner("kopie")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let roh: [String: Any] = ["typ": Sitzplandatei.typ, "version": 1, "plaene": [
            "k-eins": ["tische": [["id": "t-1", "name": String(repeating: "q", count: 120), "x": 40, "y": 336]]]]]
        let original = try JSONSerialization.data(withJSONObject: roh)
        try original.write(to: ablage.sitzplaene)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ort.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort.path) }
        let dienst = Sitzplandienst(ablage: ablage)
        guard case .bereinigt(let anzahl, _, let kopie) = dienst.laden(stempel: "s2") else {
            Issue.record("erwartet bereinigt")
            return
        }
        #expect(anzahl == 1 && kopie == nil && dienst.ausstehendeKopie == "sitzplaene-bereinigt-s2.json")
        #expect(dienst.setzen(plan(2), fuer: "k-zwei")?.contains("noch nicht bewahrt") == true)
        let unangetastet = try Data(contentsOf: ablage.sitzplaene)
        #expect(unangetastet == original, "das Original liegt unangetastet")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ort.path)
        dienst.nachholen()
        #expect(dienst.ungesichert == nil && dienst.ausstehendeKopie == nil)
        let bewahrt = try Data(contentsOf: ort.appendingPathComponent("sitzplaene-bereinigt-s2.json"))
        #expect(bewahrt == original)
        let geschrieben = try Sitzplandatei.lesen(try Data(contentsOf: ablage.sitzplaene))
        #expect(geschrieben.count == 2)
    }

    @Test("E43: Klartext neben der versiegelten Planung wird nicht still übernommen — Versiegeln oder Beiseitelegen")
    func klartextGefunden() throws {
        let ort = try ordner("klartext-frage")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let original = try Sitzplandatei.schreiben(["k-eins": plan(4)])
        try original.write(to: ablage.sitzplaene)
        let t = try tresor()
        let dienst = Sitzplandienst(ablage: ablage)
        guard case .klartextGefunden(let anzahl, let bilanz, let kopie) = dienst.oeffnen(mit: t, stempel: "s") else {
            Issue.record("erwartet klartextGefunden")
            return
        }
        #expect(anzahl == 1 && bilanz.istLeer && kopie == nil)
        #expect(dienst.klartextUnbestaetigt && dienst.schreibbar && dienst.plan(fuer: "k-eins")?.tische.count == 4)
        let vorher = try Data(contentsOf: ablage.sitzplaene)
        #expect(!Tresor.istBehaelter(vorher), "noch nichts geschrieben")
        dienst.klartextVersiegeln()
        #expect(!dienst.klartextUnbestaetigt && dienst.ungesichert == nil)
        let nachher = try Data(contentsOf: ablage.sitzplaene)
        #expect(Tresor.istBehaelter(nachher))

        // Beiseitelegen: die Datei wandert ins Register, die Pläne sind leer.
        try original.write(to: ablage.sitzplaene)
        let zweiter = Sitzplandienst(ablage: ablage)
        guard case .klartextGefunden = zweiter.oeffnen(mit: t, stempel: "s") else {
            Issue.record("erwartet klartextGefunden")
            return
        }
        #expect(zweiter.klartextBeiseitelegen(stempel: "s3") == "sitzplaene-unerwartet-s3.json")
        #expect(!zweiter.klartextUnbestaetigt && zweiter.plan(fuer: "k-eins") == nil && !zweiter.hatPlaene)
        #expect(!FileManager.default.fileExists(atPath: ablage.sitzplaene.path))
        let beiseite = try Data(contentsOf: ort.appendingPathComponent("sitzplaene-unerwartet-s3.json"))
        #expect(beiseite == original)
        let register = try ablage.nebendateien().map(\.lastPathComponent)
        #expect(register.contains("sitzplaene-unerwartet-s3.json"))
    }

    @Test("E43: der Speicher fragt beim Entsperren nach dem Klartext — „Versiegeln“ schreibt den Behälter, „Beiseitelegen“ legt ihn ins Register")
    func klartextRueckfrage() async throws {
        let ort = try ordner("klartext-speicher")
        defer { aufraeumen(ort) }
        let s = try speicher(ablage: ort)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first?.id)
        s.sitzplanUebernehmen(plan(3, klasse: klasse))
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        _ = s.verschluesselungEinschalten()
        let ablage = Ablage(ordner: ort)
        #expect(Tresor.istBehaelter(try Data(contentsOf: ablage.sitzplaene)))
        // Wie nach einem Einschalten, dessen Sitzplan-Schreiben liegen blieb: Klartext daneben.
        let klartext = try Sitzplandatei.schreiben([klasse: plan(3, klasse: klasse)])
        try klartext.write(to: ablage.sitzplaene)

        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ort))
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        let frage = try #require(zweiter.rueckfrage)
        #expect(frage.ort == .hauptansicht && frage.bestaetigung == "Versiegeln" && frage.ablehnung == "Beiseitelegen")
        #expect(frage.text.contains("im Klartext neben der versiegelten Planung"))
        #expect(zweiter.sitzplan(fuer: klasse)?.tische.count == 3, "die Pläne gelten derweil für die Sitzung")
        let vorAntwort = try Data(contentsOf: ablage.sitzplaene)
        #expect(!Tresor.istBehaelter(vorAntwort), "vor der Antwort wird nicht geschrieben")
        zweiter.rueckfrageBeantworten(true)
        #expect(zweiter.rueckfrage == nil && !zweiter.sitzplaene.klartextUnbestaetigt)
        let nachAntwort = try Data(contentsOf: ablage.sitzplaene)
        #expect(Tresor.istBehaelter(nachAntwort))
        #expect(zweiter.meldungen.last?.text.contains("jetzt versiegelt") == true)

        try klartext.write(to: ablage.sitzplaene)
        let dritter = Planungsspeicher(ablage: Ablage(ordner: ort))
        dritter.starten()
        await dritter.entsperren(passphrase: passphrase)
        #expect(dritter.rueckfrage != nil)
        dritter.rueckfrageBeantworten(false)
        #expect(dritter.sitzplan(fuer: klasse) == nil && !dritter.sitzplaene.hatPlaene)
        #expect(!FileManager.default.fileExists(atPath: ablage.sitzplaene.path))
        let register = try ablage.nebendateien().map(\.lastPathComponent)
        #expect(register.contains { $0.hasPrefix("sitzplaene-unerwartet-") })
        #expect(dritter.meldungen.last?.text.contains("beiseitegelegt") == true)
    }

    @Test("E45: das PDF-Kennwort — nur ASCII, höchstens 32 Zeichen; was darüber liegt, wird benannt, nicht gekürzt")
    func pdfKennwortGrenzen() throws {
        #expect(Sitzplandruck.kennwortEinwand("geheim") == nil)
        #expect(Sitzplandruck.kennwortEinwand("Straße")?.contains("ASCII") == true)
        #expect(Sitzplandruck.kennwortEinwand("🙂")?.contains("ASCII") == true)
        let einunddreissig = String(repeating: "a", count: 31)
        let zweiunddreissig = einunddreissig + "b"
        let dreiunddreissig = zweiunddreissig + "c"
        #expect(Sitzplandruck.kennwortEinwand(einunddreissig) == nil)
        #expect(Sitzplandruck.kennwortEinwand(zweiunddreissig) == nil)
        #expect(Sitzplandruck.kennwortEinwand(dreiunddreissig)?.contains("32") == true)
        let klasse = Standardkurse.aufbauen([("7a", "Mathematik")])[0]
        let p = plan(3, klasse: klasse.id)
        #expect(Sitzplandruck.pdf(p, klasse: klasse, kennwort: "Straße") == nil, "keine PDF mit anderem Schutz als gedacht")
        #expect(Sitzplandruck.pdf(p, klasse: klasse, kennwort: dreiunddreissig) == nil)
        let daten = try #require(Sitzplandruck.pdf(p, klasse: klasse, kennwort: zweiunddreissig))
        let quelle = try #require(CGDataProvider(data: daten as CFData))
        let pdf = try #require(CGPDFDocument(quelle))
        #expect(pdf.isEncrypted && !pdf.unlockWithPassword(einunddreissig), "die ersten 31 Zeichen genügen nicht")
        #expect(pdf.unlockWithPassword(zweiunddreissig))
    }
}
