// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// ⌘Z unter einem Bogen am Blatt „Lernende“ (G2-07, E776).
///
/// Steht ein Bogen auf dem Blatt („Rückmeldungsliste“, „Zeilen wählen“, Maßnahme/Termin, Import), zeigt er eine Kopie des
/// Entwurfs. Nähme ⌘Z darunter einen Schritt zurück, liefen Bogen und Entwurf auseinander. Darum weist der Speicher ⌘Z und ⇧⌘Z
/// ab, solange ein Bogen steht — mit Ton, der Verlauf bleibt. Ohne Bogen wie bisher.
@Suite("⌘Z unter einem Bogen am Blatt „Lernende“ (G2-07, E776)")
@MainActor
struct WiderrufenUnterDemBogenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand, "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    /// Ein Speicher mit offenem Blatt „Lernende“ und einem Schritt im Verlauf des Blatts.
    private func blattMitSchritt(_ ordner: URL, bogen: @escaping () -> Bool,
                                 gesetzt: @escaping @MainActor (Lernendenbestand) -> Void) -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        s.lernendenblattUebernimmt(gesetzt, griff: Lernendenblattgriff(bogenOffen: bogen))
        let vorher = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: "2026-10-23T10:00:00Z")
        let nachher = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: "2026-10-23T10:05:00Z")
        s.lernendenverlauf.anmelden(Schrittname.lerngruppeAnlegen, vorher: vorher, nachher: nachher)
        return s
    }

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory.appending(component: "bogen-z-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    @Test("Bei offenem Bogen: ⌘Z nimmt nichts zurück, ein Ton")
    func abgewiesen() throws {
        let ablage = try ordner("offen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        var gesetzt: [Lernendenbestand] = []
        let s = blattMitSchritt(ablage, bogen: { true }, gesetzt: { gesetzt.append($0) })
        let toene = s.systemtoene
        s.widerrufen()
        #expect(gesetzt.isEmpty && s.lernendenverlauf.kannZurueck, "der Schritt bleibt, der Entwurf auch")
        #expect(s.systemtoene == toene + 1, "ein Ton")
        s.lernendenblattGibtAb()
    }

    @Test("Ohne Bogen wie bisher: ⌘Z nimmt den Schritt zurück, ⇧⌘Z bringt ihn")
    func ohneBogen() throws {
        let ablage = try ordner("zu")
        defer { try? FileManager.default.removeItem(at: ablage) }
        var gesetzt: [Lernendenbestand] = []
        let s = blattMitSchritt(ablage, bogen: { false }, gesetzt: { gesetzt.append($0) })
        let toene = s.systemtoene
        s.widerrufen()
        #expect(gesetzt.count == 1 && !s.lernendenverlauf.kannZurueck && s.systemtoene == toene, "zurückgenommen, ohne Ton")
        s.wiederholen()
        #expect(gesetzt.count == 2 && s.lernendenverlauf.kannZurueck, "wiederholt")
        s.lernendenblattGibtAb()
    }

    @Test("E841: Bei offenem Bogen nennt das Menü keinen Schritt — ohne Bogen wieder mit Namen, auch „Wiederholen: …“")
    func titelOhneNamen() throws {
        let ablage = try ordner("titel")
        defer { try? FileManager.default.removeItem(at: ablage) }
        var bogen = true
        let s = blattMitSchritt(ablage, bogen: { bogen }, gesetzt: { _ in })
        #expect(s.widerrufenTitel == "Widerrufen" && s.wiederholenTitel == "Wiederholen", "Bogen offen: ohne Namen")
        bogen = false
        #expect(s.widerrufenTitel == "Widerrufen: " + Schrittname.lerngruppeAnlegen, "Bogen zu: der Name kommt wieder")
        s.widerrufen()
        #expect(s.wiederholenTitel == "Wiederholen: " + Schrittname.lerngruppeAnlegen)
        bogen = true
        #expect(s.wiederholenTitel == "Wiederholen", "Bogen offen: auch „Wiederholen“ ohne Namen")
        s.lernendenblattGibtAb()
    }

    @Test("Bei offenem Bogen bleibt auch ⇧⌘Z ohne Wirkung, mit Ton")
    func wiederholenAbgewiesen() throws {
        let ablage = try ordner("vor")
        defer { try? FileManager.default.removeItem(at: ablage) }
        var gesetzt: [Lernendenbestand] = []
        var bogen = false
        let s = blattMitSchritt(ablage, bogen: { bogen }, gesetzt: { gesetzt.append($0) })
        s.widerrufen()
        try #require(gesetzt.count == 1, "ohne Bogen zurückgenommen")
        bogen = true
        let toene = s.systemtoene
        s.wiederholen()
        #expect(gesetzt.count == 1 && !s.lernendenverlauf.kannZurueck, "nichts wiederholt")
        #expect(s.systemtoene == toene + 1, "ein Ton")
        s.lernendenblattGibtAb()
    }
}
