// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Der Übergabestand mit Generationen (E47) ──────────────────────────────
// Reine Dateilogik an einem eigenen Ordner: Zwillinge, Marke, Einsetzen,
// Verwerfen, Wiederanlauf — jeder Schritt einzeln und jeder Abbruch dazwischen.

@Suite("Übergang: Zwillinge, Marke, Einsetzen, Wiederanlauf")
@MainActor
struct UebergangPruefungen {

    private func ordner(_ name: String = "uebergang") throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func schreiben(_ text: String, _ name: String, in ordner: URL) throws {
        try Data(text.utf8).write(to: ordner.appending(component: name), options: [.atomic])
    }

    private func inhalt(_ name: String, in ordner: URL) -> String? {
        (try? Data(contentsOf: ordner.appending(component: name))).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func liegt(_ name: String, in ordner: URL) -> Bool {
        FileManager.default.fileExists(atPath: ordner.appending(component: name).path)
    }

    private func namen(in ordner: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: ordner.path).sorted()
    }

    private func schreibrecht(_ ordner: URL, _ an: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: an ? 0o700 : 0o500], ofItemAtPath: ordner.path)
    }

    /// Ein Ordner mit zwei Dateien des alten Stands und eine Generation, die
    /// eine ersetzt, eine entfernt und eine neu anlegt.
    private func alterStand(in ordner: URL) throws {
        try schreiben("a-alt", "a.json", in: ordner)
        try schreiben("b-alt", "b.json", in: ordner)
    }

    private let generation: [String: Uebergangsdienst.Inhalt] = [
        "a.json": .daten(Data("a-neu".utf8)),
        "b.json": .entfernen,
        "c.json": .daten(Data("c-neu".utf8)),
    ]

    private func neuerStandPruefen(in ordner: URL) throws {
        #expect(inhalt("a.json", in: ordner) == "a-neu")
        #expect(!liegt("b.json", in: ordner))
        #expect(inhalt("c.json", in: ordner) == "c-neu")
        #expect(!liegt(Uebergangsdienst.markenname, in: ordner))
        let liegend = try namen(in: ordner)
        #expect(liegend == ["a.json", "c.json"], "\(liegend)")
    }

    private func alterStandPruefen(in ordner: URL) throws {
        #expect(inhalt("a.json", in: ordner) == "a-alt")
        #expect(inhalt("b.json", in: ordner) == "b-alt")
        #expect(!liegt("c.json", in: ordner))
    }

    @Test("SHA-256 hexadezimal, wie jede Prüfsumme")
    func pruefsumme() {
        #expect(Uebergangsdienst.sha256(Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("Die Marke trägt Art, Stempel, Kennung und Prüfsummen — kein Schlüsselmaterial; sortierte Schlüssel")
    func marke() throws {
        let marke = Uebergangsmarke(art: .erneuern, stempel: "2026-09-12-220000", kennung: "0a0b",
                                    dateien: [.init(name: "a.json", sha256: "00"), .init(name: "b.json", sha256: nil)])
        let codierer = JSONEncoder()
        codierer.outputFormatting = [.sortedKeys]
        let text = String(decoding: try codierer.encode(marke), as: UTF8.self)
        #expect(text.hasPrefix("{\"art\":\"erneuern\",\"dateien\":[{\"name\":\"a.json\",\"sha256\":\"00\"},{\"name\":\"b.json\"}]"), Comment(rawValue: text))
        #expect(text.contains("\"typ\":\"unterrichtsplanung-uebergang\"") && text.contains("\"version\":1"))
        #expect(try JSONDecoder().decode(Uebergangsmarke.self, from: Data(text.utf8)) == marke)
        #expect(marke.gueltig)
        #expect(Uebergangsart.wicklungAnlegen.rawValue == "wicklung-anlegen")
        for art in Uebergangsart.allCases { #expect(art.beschreibung.hasPrefix("das ")) }
    }

    @Test("Namen der Generation: kein Pfad, nicht die Marke, kein Zwilling")
    func namen() {
        #expect(Uebergangsdienst.nameZulaessig("planung.json"))
        #expect(!Uebergangsdienst.nameZulaessig(""))
        #expect(!Uebergangsdienst.nameZulaessig("a/b.json"))
        #expect(!Uebergangsdienst.nameZulaessig(".."))
        #expect(!Uebergangsdienst.nameZulaessig(Uebergangsdienst.markenname))
        #expect(!Uebergangsdienst.nameZulaessig("planung.json.uebergang"))
        #expect(Uebergangsdienst.rettungsname(zwilling: "planung.json.uebergang", stempel: "s") == "planung-uebergang-s.json")
        #expect(Uebergangsdienst.rettungsname(zwilling: "notiz.uebergang", stempel: "s") == "notiz-uebergang-s")
    }

    @Test("Vorbereiten legt Zwillinge, Übergeben die Marke, Einsetzen tauscht und räumt")
    func dreiSchritte() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        let dienst = Uebergangsdienst(ordner: ordner)

        #expect(dienst.vorbereiten(.einschalten, kennung: Data([0xab, 0xcd]), stempel: "s1", dateien: generation) == nil)
        #expect(try namen(in: ordner) == ["a.json", "a.json.uebergang", "b.json", "c.json.uebergang"])
        try alterStandPruefen(in: ordner)
        #expect(inhalt("a.json.uebergang", in: ordner) == "a-neu")
        let laufend = try #require(dienst.laufend)
        #expect(laufend.art == .einschalten && laufend.stempel == "s1" && laufend.kennung == "abcd")
        #expect(laufend.dateien.map(\.name) == ["a.json", "b.json", "c.json"])
        #expect(laufend.dateien[1].sha256 == nil && laufend.dateien[0].sha256 == Uebergangsdienst.sha256(Data("a-neu".utf8)))
        #expect(!dienst.istUebergeben)

        #expect(dienst.uebergeben() == nil)
        #expect(dienst.istUebergeben)
        let marke = try JSONDecoder().decode(Uebergangsmarke.self,
                                             from: try Data(contentsOf: ordner.appending(component: Uebergangsdienst.markenname)))
        #expect(marke == laufend)
        try alterStandPruefen(in: ordner)

        #expect(dienst.einsetzen() == .vollendet)
        try neuerStandPruefen(in: ordner)
        #expect(dienst.laufend == nil && !dienst.istUebergeben)
        #expect(dienst.einsetzen() == .unvollendet("keine übergebene Generation"))
    }

    @Test("Aufheben: Kennung leer, Klartext-Zwillinge")
    func klartext() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let dienst = Uebergangsdienst(ordner: ordner)
        #expect(dienst.vorbereiten(.aufheben, kennung: nil, stempel: "s", dateien: ["a.json": .daten(Data("klar".utf8))]) == nil)
        #expect(dienst.laufend?.kennung == "")
        #expect(dienst.uebergeben() == nil && dienst.einsetzen() == .vollendet)
        #expect(inhalt("a.json", in: ordner) == "klar")
    }

    @Test("Verwerfen vor der Marke lässt nichts zurück; nach der Marke tut es nichts")
    func verwerfen() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        let dienst = Uebergangsdienst(ordner: ordner)
        #expect(dienst.vorbereiten(.erneuern, kennung: Data([1]), stempel: "s", dateien: generation) == nil)
        dienst.verwerfen()
        #expect(dienst.laufend == nil)
        #expect(try namen(in: ordner) == ["a.json", "b.json"])
        try alterStandPruefen(in: ordner)

        #expect(dienst.vorbereiten(.erneuern, kennung: Data([1]), stempel: "s", dateien: generation) == nil)
        #expect(dienst.uebergeben() == nil)
        dienst.verwerfen()
        #expect(dienst.laufend != nil && dienst.istUebergeben, "nach der Marke gilt der neue Stand")
        #expect(liegt(Uebergangsdienst.markenname, in: ordner) && liegt("a.json.uebergang", in: ordner))
        #expect(dienst.einsetzen() == .vollendet)
        try neuerStandPruefen(in: ordner)
    }

    @Test("Vorbereiten scheitert: Ordner an der Stelle einer Datei, ohne Schreibrecht, unzulässiger Name, leer — kein Zwilling bleibt")
    func vorbereitenScheitert() throws {
        let ordner = try ordner()
        defer {
            try? schreibrecht(ordner, true)
            try? FileManager.default.removeItem(at: ordner)
        }
        try alterStand(in: ordner)
        let dienst = Uebergangsdienst(ordner: ordner)
        #expect(dienst.vorbereiten(.einschalten, kennung: nil, stempel: "s", dateien: [:]) == "nichts zu übergeben")
        #expect(dienst.vorbereiten(.einschalten, kennung: nil, stempel: "s", dateien: ["x/y": .daten(Data())])
                == "„x/y“ ist kein Name für die Generation")

        try FileManager.default.createDirectory(at: ordner.appending(component: "c.json"), withIntermediateDirectories: true)
        let grund = try #require(dienst.vorbereiten(.einschalten, kennung: nil, stempel: "s", dateien: generation))
        #expect(grund == "an der Stelle von „c.json“ liegt ein Ordner", Comment(rawValue: grund))
        #expect(dienst.laufend == nil)
        #expect(try namen(in: ordner) == ["a.json", "b.json", "c.json"], "der Zwilling von a.json ist wieder fort")
        try FileManager.default.removeItem(at: ordner.appending(component: "c.json"))

        try schreibrecht(ordner, false)
        let ohneRecht = try #require(dienst.vorbereiten(.einschalten, kennung: nil, stempel: "s", dateien: generation))
        #expect(!ohneRecht.isEmpty && dienst.laufend == nil)
        try schreibrecht(ordner, true)
        #expect(try namen(in: ordner) == ["a.json", "b.json"])
        try alterStandPruefen(in: ordner)
    }

    @Test("Ein zweites Vorbereiten wartet; eine liegende Marke sperrt das Vorbereiten")
    func nacheinander() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        let dienst = Uebergangsdienst(ordner: ordner)
        #expect(dienst.vorbereiten(.einschalten, kennung: nil, stempel: "s", dateien: generation) == nil)
        #expect(dienst.vorbereiten(.einschalten, kennung: nil, stempel: "s", dateien: generation)
                == "ein Übergang ist schon in Vorbereitung")
        #expect(dienst.uebergeben() == nil && dienst.uebergeben() == nil, "übergeben ist wiederholbar")
        #expect(dienst.einsetzen() == .vollendet)

        try schreiben("{}", Uebergangsdienst.markenname, in: ordner)
        let zweiter = Uebergangsdienst(ordner: ordner)
        #expect(zweiter.vorbereiten(.aufheben, kennung: nil, stempel: "s", dateien: ["a.json": .entfernen])
                == "ein früherer Übergang ist nicht abgeschlossen — bitte die App neu starten")
        #expect(zweiter.uebergeben() == "keine Generation vorbereitet")
    }

    // ── Jeder Abbruch und sein Wiederanlauf ───────────────────────────────

    @Test("Nichts liegt: nichts zu tun")
    func wiederanlaufLeer() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        #expect(Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") == .nichts)
        try alterStandPruefen(in: ordner)
    }

    @Test("Abbruch nach dem Vorbereiten: Zwillinge ohne Marke werden entfernt, der alte Stand bleibt")
    func abbruchNachVorbereiten() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        #expect(Uebergangsdienst(ordner: ordner).vorbereiten(.einschalten, kennung: nil, stempel: "s", dateien: generation) == nil)
        try schreiben("fremd", "x.uebergang", in: ordner)

        #expect(Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") == .verworfen(3))
        #expect(try namen(in: ordner) == ["a.json", "b.json"])
        try alterStandPruefen(in: ordner)
    }

    @Test("Abbruch nach dem Übergeben: der Wiederanlauf setzt ein — ohne Schlüssel, allein über die Prüfsummen")
    func abbruchNachUebergeben() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        let erster = Uebergangsdienst(ordner: ordner)
        #expect(erster.vorbereiten(.erneuern, kennung: Data([7]), stempel: "s", dateien: generation) == nil)
        #expect(erster.uebergeben() == nil)

        #expect(Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") == .vollendet(.erneuern))
        try neuerStandPruefen(in: ordner)
        #expect(Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") == .nichts, "ein zweiter Start findet nichts")
    }

    @Test("Abbruch mitten im Einsetzen: schon getauschte Dateien gelten, der Rest wird nachgeholt")
    func abbruchImEinsetzen() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        let erster = Uebergangsdienst(ordner: ordner)
        #expect(erster.vorbereiten(.aufheben, kennung: nil, stempel: "s", dateien: generation) == nil)
        #expect(erster.uebergeben() == nil)
        // Der erste Tausch ist geschehen, dann endete der Prozess.
        let verwaltung = FileManager.default
        _ = try verwaltung.replaceItemAt(ordner.appending(component: "a.json"),
                                         withItemAt: ordner.appending(component: "a.json.uebergang"))
        #expect(inhalt("a.json", in: ordner) == "a-neu" && inhalt("b.json", in: ordner) == "b-alt")

        #expect(Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") == .vollendet(.aufheben))
        try neuerStandPruefen(in: ordner)
    }

    @Test("Ein Zwilling weicht ab: der alte Stand bleibt, Marke und Zwillinge kommen gestempelt ins Register")
    func zwillingWeichtAb() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        let erster = Uebergangsdienst(ordner: ordner)
        #expect(erster.vorbereiten(.einschalten, kennung: Data([1]), stempel: "s", dateien: generation) == nil)
        #expect(erster.uebergeben() == nil)
        try schreiben("verändert", "c.json.uebergang", in: ordner)

        let befund = Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w")
        #expect(befund == .nichtVollendbar(.einschalten, grund: "„c.json“ weicht ab",
                                           rettung: ["uebergang-w.json", "a-uebergang-w.json", "c-uebergang-w.json"]))
        try alterStandPruefen(in: ordner)
        #expect(try namen(in: ordner) == ["a-uebergang-w.json", "a.json", "b.json", "c-uebergang-w.json", "uebergang-w.json"])
        #expect(inhalt("a-uebergang-w.json", in: ordner) == "a-neu")
        #expect(Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w2") == .nichts)
    }

    @Test("Ein Zwilling fehlt: nicht vollendbar — es sei denn, das Original trägt schon die Prüfsumme")
    func zwillingFehlt() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        let erster = Uebergangsdienst(ordner: ordner)
        #expect(erster.vorbereiten(.passphrase, kennung: Data([1]), stempel: "s", dateien: generation) == nil)
        #expect(erster.uebergeben() == nil)
        try FileManager.default.removeItem(at: ordner.appending(component: "c.json.uebergang"))

        guard case .nichtVollendbar(let art, let grund, let rettung) = Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") else {
            Issue.record("erwartet: nicht vollendbar")
            return
        }
        #expect(art == .passphrase && grund == "„c.json“ fehlt" && rettung == ["uebergang-w.json", "a-uebergang-w.json"])
        try alterStandPruefen(in: ordner)
    }

    @Test("Die Marke ist nicht lesbar: beiseite, der alte Stand bleibt")
    func markeUnlesbar() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        try schreiben("a-neu", "a.json.uebergang", in: ordner)
        try schreiben("{\"typ\":\"anderes\"}", Uebergangsdienst.markenname, in: ordner)

        guard case .nichtVollendbar(let art, let grund, let rettung) = Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") else {
            Issue.record("erwartet: nicht vollendbar")
            return
        }
        #expect(art == nil && grund.hasPrefix("die Marke ist nicht lesbar (") && rettung == ["uebergang-w.json", "a-uebergang-w.json"])
        try alterStandPruefen(in: ordner)
        #expect(try namen(in: ordner) == ["a-uebergang-w.json", "a.json", "b.json", "uebergang-w.json"])
    }

    @Test("Einsetzen ohne Schreibrecht: die Marke bleibt, der nächste Start vollendet, sobald es geht")
    func einsetzenGesperrt() throws {
        let ordner = try ordner()
        defer {
            try? schreibrecht(ordner, true)
            try? FileManager.default.removeItem(at: ordner)
        }
        try alterStand(in: ordner)
        let dienst = Uebergangsdienst(ordner: ordner)
        #expect(dienst.vorbereiten(.wicklungAnlegen, kennung: Data([1]), stempel: "s", dateien: generation) == nil)
        #expect(dienst.uebergeben() == nil)
        try schreibrecht(ordner, false)

        guard case .unvollendet(let grund) = dienst.einsetzen() else {
            Issue.record("erwartet: unvollendet")
            return
        }
        #expect(grund.contains("a.json") && grund.contains("b.json") && grund.contains("c.json"), Comment(rawValue: grund))
        #expect(dienst.laufend != nil && dienst.istUebergeben)
        #expect(liegt(Uebergangsdienst.markenname, in: ordner))
        #expect(dienst.vorbereiten(.aufheben, kennung: nil, stempel: "s2", dateien: generation)
                == "ein früherer Übergang ist nicht abgeschlossen — bitte die App neu starten")
        guard case .gesperrt(let art, _) = Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") else {
            Issue.record("erwartet: gesperrt")
            return
        }
        #expect(art == .wicklungAnlegen)
        try schreibrecht(ordner, true)
        #expect(Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") == .vollendet(.wicklungAnlegen))
        try neuerStandPruefen(in: ordner)
    }
}
