// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Die Kapsel des Hauptfensters neben einem Blatt mit eigener Meldungszeile (E489) ─────────────────────────────
// Steht ein Blatt, das seine Meldungen selbst zeigt, bleibt die Kapsel des Hauptfensters still — sonst stünde
// dieselbe Meldung doppelt, bei großem Fenster angeschnitten unter dem Blatt. Steht darüber ein Blatt ohne Zeile,
// bleibt sie sichtbar: Sonst läge die einzige Zeile verdeckt. Geprüft wird die Entscheidung als reine Funktion und
// ihre Brücke vom Speicher; wie es aussieht, zeigt die Handprobe.

@Suite("Meldungszeile: Das Hauptfenster bleibt still neben einem Blatt mit eigener Zeile")
@MainActor
struct MeldungszeilePruefungen {
    let beide: Set<Meldungszeile.Blatt> = [.lernende, .vorhaben]

    private func still(_ dialog: Dialogfenster?, vorhaben: Bool = false, material: Bool = false,
                       _ eingeschaltet: Set<Meldungszeile.Blatt>, abbild: Bool = false) -> Bool {
        Meldungszeile.hauptfensterStill(offenerDialog: dialog, vorhabenOffen: vorhaben, materialOffen: material,
                                        eingeschaltet: eingeschaltet, imAbbild: abbild)
    }

    @Test("Kein Blatt offen: Das Hauptfenster zeigt seine Kapsel")
    func keinBlatt() {
        #expect(!still(nil, beide))
    }

    @Test("Lernende offen und eingeschaltet: still")
    func lernendeEingeschaltet() {
        #expect(still(.lernende, [.lernende]))
    }

    @Test("Lernende offen, aber nicht eingeschaltet: Die Kapsel bleibt — sonst sähe niemand die Meldung")
    func lernendeAus() {
        #expect(!still(.lernende, [.vorhaben]))
    }

    @Test("Vorhaben-Blatt offen und eingeschaltet: still")
    func vorhabenEingeschaltet() {
        #expect(still(nil, vorhaben: true, [.vorhaben]))
    }

    @Test("Vorhaben-Blatt offen, aber nicht eingeschaltet: Die Kapsel bleibt")
    func vorhabenAus() {
        #expect(!still(nil, vorhaben: true, [.lernende]))
    }

    @Test("Ein anderes Blatt, auch wenn alle eingeschaltet sind: Die Kapsel bleibt")
    func anderesBlatt() {
        #expect(!still(.einstellungen, beide))
    }

    @Test("Vorhaben-Blatt über dem Lernenden-Blatt: still nur, wenn beide eingeschaltet sind")
    func zweiBlaetter() {
        #expect(!still(.lernende, vorhaben: true, [.lernende]), "die Zeile läge unter dem Vorhaben-Blatt")
        #expect(still(.lernende, vorhaben: true, beide))
    }

    @Test("Ein anderes Blatt unter dem Vorhaben-Blatt: Die Kapsel bleibt")
    func vorhabenUeberAnderem() {
        #expect(!still(.klassen, vorhaben: true, beide))
    }

    @Test("Der Material-Bogen auf dem Vorhaben-Blatt hat keine eigene Zeile: Die Kapsel bleibt")
    func materialbogen() {
        #expect(!still(nil, vorhaben: true, material: true, beide))
    }

    @Test("Im Abbild zeigt jedes Blatt die Zeile: still bei jedem Blatt, ohne Blatt nicht")
    func abbild() {
        #expect(still(.einstellungen, [], abbild: true))
        #expect(still(nil, vorhaben: true, [], abbild: true))
        #expect(!still(nil, [], abbild: true))
    }

    @Test("Die Brücke vom Speicher: Lernenden- und Vorhaben-Blatt, wie sie im Speicher stehen")
    func bruecke() throws {
        let ablage = URL.temporaryDirectory
            .appending(component: "meldungszeile-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ablage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        #expect(!Meldungszeile.hauptfensterStill(s, eingeschaltet: beide, imAbbild: false), "kein Blatt")
        s.vorhabenDialog = VorhabenEntwurf(klasseId: "k1", woche: 1)
        #expect(Meldungszeile.hauptfensterStill(s, eingeschaltet: [.vorhaben], imAbbild: false))
        s.materialblattOffen = true
        #expect(!Meldungszeile.hauptfensterStill(s, eingeschaltet: beide, imAbbild: false), "Material-Bogen darüber")
        s.materialblattOffen = false
        s.offenerDialog = .lernende
        #expect(!Meldungszeile.hauptfensterStill(s, eingeschaltet: [.lernende], imAbbild: false),
                "Vorhaben-Blatt über dem Lernenden-Blatt")
        s.vorhabenDialog = nil
        #expect(Meldungszeile.hauptfensterStill(s, eingeschaltet: [.lernende], imAbbild: false))
    }

    @Test("Eingeschaltet ist das Blatt „Lernende“ (AT2); das Vorhaben-Blatt kommt mit AT13")
    func eingeschaltetHeute() {
        #expect(Meldungszeile.eingeschaltet == [.lernende])
    }
}
