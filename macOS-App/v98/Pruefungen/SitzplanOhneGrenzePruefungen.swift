// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Sitzplan ohne Grenze der Tische (v90, BB3, E979) ──
// Bis 2.4.0 fasste ein Sitzplan 40 Tische — fünf Reihen zu acht (E283). Seit Fassung 2 der Sitzplandatei (BB1) liest sie
// jede Zahl; Namen eingeben, die Anordnung, „Tisch hinzufügen“ und die Vorlage aus der Lerngruppe nehmen jetzt alle. Was
// das Raster nicht mehr fasst, liegt an der Ausweichstelle oben links; ob Tische sich überlagern, liegt beim Nutzer.

@Suite("v90 BB3: Sitzplan ohne Grenze der Tische — je mit 41 und 300 (E979)")
@MainActor
struct SitzplanOhneGrenzePruefungen {

    private static let s = "2026-10-31T08:00:00.000Z"
    private static let zahlen = [41, 300]

    private static func namen(_ n: Int) -> [String] { (1...n).map { "Name \($0)" } }

    private static func lage(_ t: Tisch) -> CGPoint { CGPoint(x: t.x, y: t.y) }

    @Test("Namen eingeben: 41 und 300 Zeilen ohne Fehler")
    func namenEingeben() {
        for n in Self.zahlen {
            let liste = Sitzplan.namenLesen(Self.namen(n).joined(separator: "\n"))
            #expect(liste.fehler.isEmpty && liste.namen.count == n, "\(n) Namen: \(liste.fehler.map(\.grund))")
        }
    }

    @Test("Anordnung mit 41 und 300: die ersten 40 wie bisher, dann die Gänge, dann freie Stellen, der Rest oben links — alle in der Fläche")
    func anordnung() {
        for n in Self.zahlen {
            let p = Sitzplan.anordnen(klasseId: "k", namen: Self.namen(n))
            #expect(p.tische.count == n && p.tische.map(\.name) == Self.namen(n), "\(n) Tische in der Folge der Namen")
            let vierzig = Sitzplan.anordnen(klasseId: "k", namen: Array(Self.namen(n).prefix(40)))
            #expect(zip(p.tische.prefix(40), vierzig.tische).allSatisfy { Self.lage($0) == Self.lage($1) }, "die ersten 40 wie bisher")
            if p.tische.count > 40 {
                #expect([Sitzplanmasse.platz(0), Sitzplanmasse.platz(9)].contains(p.tische[40].x), "der 41. in einem Gang")
            }
            #expect(p.tische.allSatisfy { Sitzplanmasse.tischbereich.contains($0.rahmen) }, "alle in der Fläche (\(n))")
            #expect(Set(p.tische.map(\.id)).count == n, "Kennungen eindeutig")
        }
        // Nach der Stelle in der Liste, nicht nach der Lage: (0, 0) ist zugleich die erste Stelle des feinen Rasters und
        // die Ausweichstelle (Z-BB3-01). 40 in Reihen, 10 in den Gängen, 11 am oberen Rand — dann der Stapel oben links.
        let gross = Sitzplan.anordnen(klasseId: "k", namen: Self.namen(300))
        let gaenge = gross.tische[40..<50], rand = gross.tische[50..<61], stapel = gross.tische[61...]
        #expect(gaenge.allSatisfy { [Sitzplanmasse.platz(0), Sitzplanmasse.platz(9)].contains($0.x) },
                "41–50 in den Gängen")
        #expect(rand.allSatisfy { $0.y == 0 } && Set(rand.map(\.x)).count == 11, "51–61 am oberen Rand nebeneinander")
        #expect(stapel.allSatisfy { Self.lage($0) == Sitzplanmasse.ausweichstelle }, "ab dem 62. übereinander oben links")
        let imRaster = Array(gross.tische[..<61])
        for (i, a) in imRaster.enumerated() {
            for b in imRaster.dropFirst(i + 1) where a.rahmen.intersects(b.rahmen) {
                Issue.record("\(a.name) und \(b.name) überlappen im Raster")
            }
        }
    }

    @Test("„Tisch hinzufügen“ an einem Plan mit 40 und mit 300 Tischen — immer ein neuer, am vollen Raster oben links")
    func tischHinzufuegen() {
        for n in [40, 300] {
            let p = Sitzplan.anordnen(klasseId: "k", namen: Self.namen(n))
            let mehr = p.mitNeuemTisch(name: "Neu")
            #expect(mehr.tische.count == n + 1 && mehr.tische.last?.name == "Neu", "\(n) + 1")
            #expect(mehr.tische.last.map { Sitzplanmasse.tischbereich.contains($0.rahmen) } == true)
        }
        let neben = Sitzplan.anordnen(klasseId: "k", namen: Self.namen(40)).mitNeuemTisch(name: "Neu")
        #expect(neben.tische.last.map { [Sitzplanmasse.platz(0), Sitzplanmasse.platz(9)].contains($0.x) } == true,
                "der 41. in einem Gang")
        let voll = Sitzplan.anordnen(klasseId: "k", namen: Self.namen(300)).mitNeuemTisch(name: "Neu")
        #expect(voll.tische.last.map(Self.lage) == Sitzplanmasse.ausweichstelle)
    }

    @Test("„Namen aus der Lerngruppe übernehmen“: alle aktiven Mitglieder einer Gruppe mit 41 und 300 — je mit ihrer Person")
    func vorlageAusDerLerngruppe() {
        for n in Self.zahlen {
            var b = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: Self.s)
            b.lernende = (0..<n).map {
                Lernender(id: "p-\($0)", vorname: "V\($0)", nachname: "N\($0)", angelegt: Self.s, geaendert: Self.s,
                          archiviert: "")
            }
            b.lerngruppen = [Lerngruppe(id: "g", name: "6a", art: .klasse, mitglieder: b.lernende.map(\.id), zeilen: [],
                                        skalen: [:], halbjahreswechsel: "", geaendert: Self.s, archiviert: "")]
            let vorlage = Lernendenverzeichnis(b).sitzplatzvorlage(der: "g")
            let p = Sitzplan.anordnen(klasseId: "k", lernende: vorlage)
            #expect(p.tische.count == n && Set(p.tische.map(\.lernender)) == Set(b.lernende.map(\.id)), "alle \(n)")
        }
    }

    @Test("Größe: 75 Pläne zu 45 Tischen, jeder Name mit 100 Zeichen und gebunden, bleiben versiegelt unter der Lesegrenze der Sitzplandatei")
    func groesse() throws {
        let name = String(repeating: "x", count: Kennwerte.maxSitzplatzname)
        var plaene: [String: Sitzplan] = [:]
        for k in 0..<75 {
            let tische = (0..<45).map {
                // Kennungen in voller Länge wie `Kennung.neu` (16 Zeichen, Z-BB3-04).
                Tisch(id: "t-" + String(format: "%06d%08d", k, $0), name: name, x: CGFloat($0 % 10) * 72,
                      y: CGFloat($0 / 10) * 72, lernender: "l-" + String(format: "%06d%08d", k, $0))
            }
            plaene["k-\(k)"] = Sitzplan(klasseId: "k-\(k)", tische: tische, lehrertisch: Sitzplanmasse.lehrertischStart,
                                        geaendert: Self.s)
        }
        let klartext = try Sitzplandatei.schreiben(plaene)
        let t = Tresor.neu()
        try t.passphraseSetzen("Ein Satz, den man behält", runden: Tresor.rundenMindestens)
        let versiegelt = try t.versiegeln(klartext, inhalt: .sitzplaene, ziel: .ablage)
        #expect(versiegelt.count <= Sitzplandatei.hoechstgroesse,
                "\(klartext.count) Byte Klartext, \(versiegelt.count) Byte versiegelt, Grenze \(Sitzplandatei.hoechstgroesse)")
    }

    @Test("Die Unterzeile des Blatts zählt die Plätze ohne Grenze — „1 Platz“, „45 Plätze · Lehrertisch“")
    func unterzeile() {
        var p = Sitzplan.anordnen(klasseId: "k", namen: Self.namen(45))
        #expect(SitzplanDialog.plaetzezeile(p) == "45 Plätze · Lehrertisch")
        p.lehrertisch = nil
        #expect(SitzplanDialog.plaetzezeile(p) == "45 Plätze")
        #expect(SitzplanDialog.plaetzezeile(Sitzplan.anordnen(klasseId: "k", namen: ["Ada"])) == "1 Platz · Lehrertisch")
    }
}
