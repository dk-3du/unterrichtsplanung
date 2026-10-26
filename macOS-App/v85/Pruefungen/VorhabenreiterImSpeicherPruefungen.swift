// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Reiter des Vorhaben-Blatts im Speicher (v85, AW3-neu; E731, E653) ────
// `vorhabenReiter` steht neben `materialblattOffen`: Beim Öffnen und mit dem Blatt zurück auf „Grundlegendes“ (E731) — auch
// bei „Als Termin führen …“. „Hausaufgabe hinzufügen …“ öffnet das Blatt auf dem Reiter „Hausaufgabe“ mit eingeschalteter
// Hausaufgabe im Entwurf (E653) — „Übernehmen“ schreibt, „Abbrechen“ lässt nichts zurück.

@Suite("Der Reiter des Vorhaben-Blatts im Speicher (E731, E653)")
@MainActor
struct VorhabenreiterImSpeicherPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "vorhabenreiter-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// „Fotosynthese“ mit Kommentar, „Zellgewebe“ als Prüfung, „Mikroskop“ ohne alles.
    private func speicher(_ ablage: URL) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        var p = Planung.leer(titel: "Biologie 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        let k = p.klassen[0].id
        var foto = Vorhaben(id: "e-foto", klasseId: k, woche: 1, titel: "Fotosynthese", text: "", erledigt: false,
                            materialien: [], links: [])
        foto.kommentar = "Lief gut"
        var zell = Vorhaben(id: "e-zell", klasseId: k, woche: 2, titel: "Zellgewebe", text: "", erledigt: false,
                            materialien: [], links: [])
        zell.pruefung = true
        let mikro = Vorhaben(id: "e-mikro", klasseId: k, woche: 3, titel: "Mikroskop", text: "", erledigt: false,
                             materialien: [], links: [])
        p.eintraege = [foto, zell, mikro]
        s.planung = p
        return s
    }

    private func vorhaben(_ s: Planungsspeicher, _ id: String) -> Vorhaben? {
        s.planung?.eintraege.first { $0.id == id }
    }

    @Test("Beim Öffnen immer „Grundlegendes“ — auch wenn andere Reiter etwas tragen (E731)")
    func beimOeffnen() throws {
        let ablage = try ordner("oeffnen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        // Vorher ein anderer Reiter: Das Öffnen muss ihn setzen (Z-AW2b-04).
        s.vorhabenReiter = .links
        s.vorhabenOeffnen(id: "e-zell")
        #expect(s.vorhabenReiter == .grundlegendes, "„Zellgewebe“ ist eine Prüfung")
        s.vorhabenDialog = nil
        s.vorhabenReiter = .links
        s.vorhabenOeffnen(id: "e-foto")
        #expect(s.vorhabenReiter == .grundlegendes, "„Fotosynthese“ hat einen Kommentar")
        s.vorhabenDialog = nil
        s.vorhabenReiter = .links
        s.vorhabenOeffnen(klasse: s.planung?.klassen.first?.id, woche: 1)
        #expect(s.vorhabenReiter == .grundlegendes, "ein neues Vorhaben")
    }

    @Test("Mit dem Blatt zurück auf „Grundlegendes“")
    func zuruecksetzen() throws {
        let ablage = try ordner("zuruecksetzen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        s.vorhabenOeffnen(id: "e-mikro")
        s.vorhabenReiter = .links
        s.vorhabenDialog = nil
        #expect(s.vorhabenReiter == .grundlegendes)
    }

    @Test("„Als Termin führen …“: eingeschaltet, das Blatt auf „Grundlegendes“ (E731)")
    func alsTermin() throws {
        let ablage = try ordner("termin")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        s.vorhabenReiter = .links
        s.vorhabenOeffnen(id: "e-mikro", alsTermin: true)
        #expect(s.vorhabenDialog?.termin == true && s.vorhabenReiter == .grundlegendes)
    }

    @Test("„Hausaufgabe hinzufügen …“: das Blatt auf „Hausaufgabe“, im Entwurf eingeschaltet, in der Planung noch nicht (E653)")
    func hausaufgabeOeffnet() throws {
        let ablage = try ordner("hausaufgabe")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        s.vorhabenOeffnen(id: "e-foto", alsHausaufgabe: true)
        #expect(s.vorhabenDialog?.hausaufgabe == true, "im Entwurf eingeschaltet")
        #expect(s.vorhabenReiter == .hausaufgabe, "der Reiter „Hausaufgabe“ statt „Grundlegendes“")
        #expect(vorhaben(s, "e-foto")?.hausaufgabe == false, "die Planung bleibt bis „Übernehmen“")
    }

    @Test("„Hausaufgabe hinzufügen …“, dann „Abbrechen“: nichts bleibt zurück (E653)")
    func hausaufgabeAbbrechen() throws {
        let ablage = try ordner("abbrechen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let vorher = s.planung
        s.vorhabenOeffnen(id: "e-foto", alsHausaufgabe: true)
        s.vorhabenDialog = nil
        #expect(s.planung == vorher, "die Planung wie vorher")
        #expect(s.vorhabenReiter == .grundlegendes, "der Reiter zurück")
    }

    @Test("„Hausaufgabe hinzufügen …“, dann „Übernehmen“: Die Hausaufgabe steht in der Planung (E653)")
    func hausaufgabeUebernehmen() throws {
        let ablage = try ordner("uebernehmen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        s.vorhabenOeffnen(id: "e-foto", alsHausaufgabe: true)
        var e = try #require(s.vorhabenDialog)
        e.hausaufgabenText = "S. 42, Nr. 3"
        s.vorhabenSichernFragen(e)
        #expect(vorhaben(s, "e-foto")?.hausaufgabe == true, "eingeschaltet")
        #expect(vorhaben(s, "e-foto")?.hausaufgabenText == "S. 42, Nr. 3", "mit der Zeile")
        #expect(s.vorhabenDialog == nil && s.vorhabenReiter == .grundlegendes, "das Blatt zu, der Reiter zurück")
    }

    @Test("Ändert sich der Entwurf desselben Blatts, bleibt der Reiter (Z-AW2b-06)")
    func gleicherEntwurf() throws {
        let ablage = try ordner("gleich")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        s.vorhabenOeffnen(id: "e-zell")
        s.vorhabenReiter = .links
        s.vorhabenDialog?.kommentar = "Nachtrag"
        #expect(s.vorhabenReiter == .links)
    }

    @Test("Von einem Vorhaben zum nächsten ohne Schließen: wieder „Grundlegendes“ (Z-AW2b-06)")
    func wechselOhneSchliessen() throws {
        let ablage = try ordner("wechsel")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        s.vorhabenOeffnen(id: "e-foto")
        // Ein anderer Reiter vor dem Wechsel — sonst unterschiede sich die Erwartung nicht vom Stand (Z-AW2c-03).
        s.vorhabenReiter = .links
        s.vorhabenOeffnen(id: "e-zell")
        #expect(s.vorhabenReiter == .grundlegendes)
    }
}
