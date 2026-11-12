// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Ob eine Nebendatei trägt, was sie bewahren soll — gebunden gelesen (v87, AY4, R86-05) ──
// Bis 2.2.1 las `nebendateiTraegt` als einzige Stelle der Ablage mit `Data(contentsOf:)` — an einer benannten Pipe
// unter diesem Namen hätte es unter der Sperre gewartet. Jetzt über `gebundenLesen` wie jedes Lesen der Ablage; die
// Regel „Lesestellen der Ablage nur gebunden“ in pruefen.sh hält das fest. Die Pipe ist erst nach der Behebung prüfbar: vorher hinge der Lauf.
// Abhängigkeit (Z-AY4-04): Liest `nebendateiTraegt` je wieder ungebunden, hängt `traegt` an der Pipe, und ohne Uhr bricht
// der Lauf hier nicht ab — die Regel „Lesestellen der Ablage nur gebunden“ läuft in pruefen.sh vor der Suite und nennt
// die Stelle zuerst.

@Suite("Ablage: nebendateiTraegt liest gebunden (R86-05)")
struct NebendateiTraegtPruefungen {

    private func ordner() throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "nebendatei-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    @Test("Die Kopie, die trägt: ja; eine andere, ein Ordner, eine fehlende, eine benannte Pipe: nein — ohne zu warten")
    func traegt() throws {
        let ort = try ordner()
        defer { try? FileManager.default.removeItem(at: ort) }
        let ablage = Ablage(ordner: ort)
        let klartext = Data("{\"typ\":\"planung\"}".utf8)
        try klartext.write(to: ort.appending(component: "planung-bereinigt-1.json"))
        try Data("{}".utf8).write(to: ort.appending(component: "planung-bereinigt-2.json"))
        try FileManager.default.createDirectory(at: ort.appending(component: "planung-bereinigt-3.json"),
                                                withIntermediateDirectories: false)
        #expect(mkfifo(ort.appending(component: "planung-bereinigt-4.json").path, 0o600) == 0)
        #expect(ablage.nebendateiTraegt("planung-bereinigt-1.json", klartext, tresor: nil))
        #expect(!ablage.nebendateiTraegt("planung-bereinigt-2.json", klartext, tresor: nil), "ein anderer Inhalt")
        #expect(!ablage.nebendateiTraegt("planung-bereinigt-3.json", klartext, tresor: nil), "ein Ordner")
        #expect(!ablage.nebendateiTraegt("planung-bereinigt-fehlt.json", klartext, tresor: nil), "keine Datei")
        #expect(!ablage.nebendateiTraegt("planung-bereinigt-4.json", klartext, tresor: nil), "eine Pipe: nein, und kein Warten")
    }

    @Test("Über der Obergrenze: nein; eine gleiche Kopie genau an der Grenze: ja (Z-AY4-05, Z-AY4N-04, Z-AY4N2-01)")
    func ueberDerGrenze() throws {
        let ort = try ordner()
        defer { try? FileManager.default.removeItem(at: ort) }
        let ablage = Ablage(ordner: ort)
        // Eine Datei mit Loch: so groß wie verlangt, ohne den Platz zu belegen; Nullen wie der Klartext daneben.
        let ziel = ort.appending(component: "planung-bereinigt-gross.json")
        #expect(FileManager.default.createFile(atPath: ziel.path, contents: nil))
        let griff = try FileHandle(forWritingTo: ziel)
        try griff.truncate(atOffset: UInt64(Ablage.formgrenze + 1))
        try griff.close()
        #expect(!ablage.nebendateiTraegt("planung-bereinigt-gross.json", Data(count: Ablage.formgrenze + 1), tresor: nil))
        // Das Gegenstück aus derselben Art Datei, genau an der Grenze: Nullen tragen, die Grenze allein entscheidet — und
        // sie liegt nicht tiefer (über viele Lesestücke gelesen; kurz rund 256 MB Speicher).
        let darunter = ort.appending(component: "planung-bereinigt-grenze.json")
        #expect(FileManager.default.createFile(atPath: darunter.path, contents: nil))
        let zweiter = try FileHandle(forWritingTo: darunter)
        try zweiter.truncate(atOffset: UInt64(Ablage.formgrenze))
        try zweiter.close()
        #expect(ablage.nebendateiTraegt("planung-bereinigt-grenze.json", Data(count: Ablage.formgrenze), tresor: nil))
    }
}
