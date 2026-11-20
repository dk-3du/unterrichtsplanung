// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Widerrufen und Wiederholen — das Fundament (E82, E83, E85, E87, E88).
@Suite("Rücknahme")
struct RuecknahmePruefungen {

    private func planung() throws -> Planung {
        Planung.leer(titel: "Verlauf", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                     basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                     fachfarben: [:])
    }

    private func ablage() throws -> (Ablage, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "verlauf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return (Ablage(ordner: ordner), ordner)
    }

    // ── Die Mechanik ──────────────────────────────────────────────────────

    @MainActor
    @Test("Anmelden, zurücknehmen, wiederholen")
    func hinUndZurueck() {
        let verlauf = Ruecknahme<Int>()
        #expect(!verlauf.kannZurueck && !verlauf.kannVor)
        verlauf.anmelden("Erstes", vorher: 1, nachher: 2)
        #expect(verlauf.kannZurueck && !verlauf.kannVor)
        #expect(verlauf.naechsterName == "Erstes")

        let zurueck = verlauf.zuruecknehmen()
        #expect(zurueck?.vorher == 1)
        #expect(!verlauf.kannZurueck && verlauf.kannVor)
        #expect(verlauf.wiederholungsName == "Erstes")

        let vor = verlauf.wiederholen()
        #expect(vor?.nachher == 2)
        #expect(verlauf.kannZurueck && !verlauf.kannVor)
    }

    @MainActor
    @Test("Eine Änderung ohne Wirkung ist kein Schritt")
    func ohneWirkungKeinSchritt() {
        let verlauf = Ruecknahme<Int>()
        verlauf.anmelden("Nichts", vorher: 7, nachher: 7)
        #expect(!verlauf.kannZurueck)
    }

    @MainActor
    @Test("Ein neuer Schritt räumt den Weg nach vorn")
    func neuerSchrittRaeumtVor() {
        let verlauf = Ruecknahme<Int>()
        verlauf.anmelden("Erstes", vorher: 1, nachher: 2)
        _ = verlauf.zuruecknehmen()
        #expect(verlauf.kannVor)
        verlauf.anmelden("Zweites", vorher: 1, nachher: 3)
        #expect(!verlauf.kannVor, "was wiederholt worden wäre, gibt es nicht mehr")
    }

    @MainActor
    @Test("Der Verlauf reicht fünfzig Schritte zurück (E83)")
    func kappungBeiFuenfzig() {
        let verlauf = Ruecknahme<Int>()
        #expect(verlauf.tiefe == 50)
        for schritt in 1...55 { verlauf.anmelden("Schritt \(schritt)", vorher: schritt, nachher: schritt + 1) }
        #expect(verlauf.zurueck.count == 50)
        #expect(verlauf.zurueck.first?.name == "Schritt 6", "die ältesten fallen heraus")
        #expect(verlauf.naechsterName == "Schritt 55")
    }

    @MainActor
    @Test("Leeren — nach einem Wechsel des Schauplatzes (E82)")
    func leeren() {
        let verlauf = Ruecknahme<Int>()
        verlauf.anmelden("Erstes", vorher: 1, nachher: 2)
        _ = verlauf.zuruecknehmen()
        verlauf.leeren()
        #expect(!verlauf.kannZurueck && !verlauf.kannVor)
    }

    // ── Die Schreibphase (E88) ────────────────────────────────────────────

    @MainActor
    @Test("Dieselbe Eingabe am selben Ziel bleibt ein Schritt")
    func schreibphaseFasstZusammen() {
        let verlauf = Ruecknahme<String>()
        Pruefuhr.angehalten {
            verlauf.anmelden("Kurs umbenennen", kennung: "k1", vorher: "", nachher: "G")
            verlauf.anmelden("Kurs umbenennen", kennung: "k1", vorher: "G", nachher: "G6")
            verlauf.anmelden("Kurs umbenennen", kennung: "k1", vorher: "G6", nachher: "G6a")
        }
        #expect(verlauf.zurueck.count == 1, "ein Name, ein Schritt")
        let schritt = verlauf.zurueck.first
        #expect(schritt?.vorher == "" && schritt?.nachher == "G6a", "von ganz vorn bis ganz hinten")
    }

    @MainActor
    @Test("Ein anderes Ziel beginnt einen neuen Schritt")
    func anderesZielNeuerSchritt() {
        let verlauf = Ruecknahme<String>()
        Pruefuhr.angehalten {
            verlauf.anmelden("Kurs umbenennen", kennung: "k1", vorher: "", nachher: "G6a")
            verlauf.anmelden("Kurs umbenennen", kennung: "k2", vorher: "G6a", nachher: "G6b")
        }
        #expect(verlauf.zurueck.count == 2)
    }

    @MainActor
    @Test("Ohne Kennung wird nie zusammengefasst")
    func ohneKennungZweiSchritte() {
        let verlauf = Ruecknahme<Int>()
        Pruefuhr.angehalten {
            verlauf.anmelden("Vorhaben löschen", vorher: 3, nachher: 2)
            verlauf.anmelden("Vorhaben löschen", vorher: 2, nachher: 1)
        }
        #expect(verlauf.zurueck.count == 2, "zwei Löschungen sind zwei Schritte")
    }

    @MainActor
    @Test("Nach der Phase beginnt ein neuer Schritt")
    func nachDerPhaseNeuerSchritt() {
        let verlauf = Ruecknahme<String>()
        let anfang = Date(timeIntervalSince1970: 1_800_000_000)
        Pruefuhr.angehalten(anfang) {
            verlauf.anmelden("Kurs umbenennen", kennung: "k1", vorher: "", nachher: "G")
        }
        Pruefuhr.angehalten(anfang.addingTimeInterval(verlauf.phasendauer + 1)) {
            verlauf.anmelden("Kurs umbenennen", kennung: "k1", vorher: "G", nachher: "G6a")
        }
        #expect(verlauf.zurueck.count == 2, "eine Pause trennt zwei Handgriffe")
    }

    // ── Am Speicher (E82, E85) ────────────────────────────────────────────

    @MainActor
    @Test("Ändern, widerrufen, wiederholen — Wert für Wert")
    func amSpeicherHinUndZurueck() throws {
        try Pruefuhr.angehalten {
            let (ablage, ordner) = try ablage()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let s = Planungsspeicher(ablage: ablage)
            s.planung = try planung()

            let vorher = try #require(s.planung)
            s.aendern("Titel setzen") { $0.titel = "Zweites Halbjahr" }
            let nachher = try #require(s.planung)
            #expect(nachher != vorher)
            #expect(s.kannWiderrufen)
            #expect(s.widerrufenTitel == "Widerrufen: Titel setzen")

            s.widerrufen()
            #expect(s.planung == vorher, "Wert für Wert wie vorher")
            #expect(!s.kannWiderrufen && s.kannWiederholen)
            #expect(s.wiederholenTitel == "Wiederholen: Titel setzen")

            s.wiederholen()
            #expect(s.planung == nachher, "und Wert für Wert wie danach")
        }
    }

    @MainActor
    @Test("Was nichts ändert, kommt nicht in den Verlauf")
    func aendernOhneWirkung() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: ablage)
        s.planung = try planung()
        let gemacht = s.aendern("Titel setzen") { $0.titel = $0.titel }
        #expect(!gemacht)
        #expect(!s.kannWiderrufen)
    }

    @MainActor
    @Test("Ein Wechsel des Schauplatzes leert den Verlauf (E82, E84)")
    func wechselLeertDenVerlauf() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: ablage)
        s.planung = try planung()
        s.aendern("Titel setzen") { $0.titel = "Erstes" }
        #expect(s.kannWiderrufen)

        // Von außen eingesetzt: geladen, eingespielt, ein Stand vom iPad.
        var fremd = try #require(s.planung)
        fremd.titel = "Von außen"
        s.planung = fremd
        #expect(!s.kannWiderrufen, "darüber hinweg wird nichts zurückgenommen")
        #expect(!s.kannWiederholen)
    }

    @MainActor
    @Test("Ein Stand aus der iPad-Ansicht kommt nicht in den Verlauf (E84)")
    func statusstandNichtUmkehrbar() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: ablage)
        var p = try planung()
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 0, titel: "Reihe",
                                text: "", erledigt: false, materialien: [], links: [])]
        s.planung = p
        s.aendern(Schrittname.titelAendern) { $0.titel = "Eigene Änderung" }
        #expect(s.kannWiderrufen)

        // Häkchen und Kommentare kommen von außen — ein stilles Zurücknehmen
        // fremder Eintragungen wäre eine Falle.
        let stand = Statusstand(gespeichert: "2026-08-18T18:00:00.000Z", planungstitel: "Verlauf",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "lief gut")])
        #expect(s.statusAnwenden(stand) == (1, 1))
        #expect(!s.kannWiderrufen, "der Verlauf davor gehört zu einem anderen Stand")
        #expect(!s.kannWiederholen)
    }

    @MainActor
    @Test("Eine Rücknahme wird gesichert wie jede Änderung")
    func ruecknahmeWirdGesichert() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: ablage)
        s.planung = try planung()
        s.aendern("Titel setzen") { $0.titel = "Zweites Halbjahr" }
        s.jetztSichern()
        #expect(try Data(contentsOf: ablage.datei).text.contains("Zweites Halbjahr"))

        s.widerrufen()
        s.jetztSichern()
        let liegt = try Data(contentsOf: ablage.datei).text
        #expect(!liegt.contains("Zweites Halbjahr"), "auf der Platte liegt, was gilt")
        #expect(liegt.contains("Verlauf"))
    }
}

private extension Data {
    var text: String { String(data: self, encoding: .utf8) ?? "" }
}
