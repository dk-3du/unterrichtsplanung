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
        let summe = Uebergangsdienst.sha256(Data("a-neu".utf8))
        let marke = Uebergangsmarke(art: .erneuern, stempel: "2026-09-12-220000", kennung: "0a0b",
                                    dateien: [.init(name: "a.json", sha256: summe), .init(name: "b.json", sha256: nil)])
        let codierer = JSONEncoder()
        codierer.outputFormatting = [.sortedKeys]
        let text = String(decoding: try codierer.encode(marke), as: UTF8.self)
        #expect(text.hasPrefix("{\"art\":\"erneuern\",\"dateien\":[{\"name\":\"a.json\",\"sha256\":\"\(summe)\",\"vorhanden\":true},{\"name\":\"b.json\",\"vorhanden\":true}]"), Comment(rawValue: text))
        // Eine Marke aus 1.5.1 ohne das Feld: gelesen, mit Vorgänger vorausgesetzt.
        let alt = try JSONDecoder().decode(Uebergangsmarke.self, from: Data(text.replacingOccurrences(of: ",\"vorhanden\":true", with: "").utf8))
        #expect(alt == marke)
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

    @Test("Eine Marke gilt nur mit Namen der Generation, einmalig, mit Prüfsumme aus 64 Hexziffern oder ohne")
    func markeGueltig() {
        func marke(_ dateien: [Uebergangsmarke.Eintrag]) -> Uebergangsmarke {
            Uebergangsmarke(art: .einschalten, stempel: "s", kennung: "", dateien: dateien)
        }
        let summe = Uebergangsdienst.sha256(Data("x".utf8))
        #expect(marke([.init(name: "a.json", sha256: summe), .init(name: "b.json", sha256: nil)]).gueltig)
        #expect(!marke([]).gueltig, "nichts zu übergeben")
        #expect(!marke([.init(name: "../a.json", sha256: nil)]).gueltig, "kein Pfad nach oben")
        #expect(!marke([.init(name: "a/b.json", sha256: summe)]).gueltig, "kein Pfad")
        #expect(!marke([.init(name: Uebergangsdienst.markenname, sha256: nil)]).gueltig, "nicht die Marke")
        #expect(!marke([.init(name: "a.json.uebergang", sha256: summe)]).gueltig, "kein Zwilling")
        #expect(!marke([.init(name: "a.json", sha256: summe), .init(name: "a.json", sha256: nil)]).gueltig, "einmalig")
        #expect(!marke([.init(name: "a.json", sha256: String(summe.dropLast()))]).gueltig, "64 Zeichen")
        #expect(!marke([.init(name: "a.json", sha256: "g" + summe.dropFirst())]).gueltig, "nur Hexziffern")
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
        #expect(laufend.dateien.map(\.vorhanden) == [true, true, false], "c.json ist neu")
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

    @Test("Eine Marke mit Pfad, doppeltem Namen oder unförmiger Prüfsumme wird nicht eingesetzt — nichts außerhalb des Ordners wird angerührt (N51-02)")
    func markeUnzulaessig() throws {
        let eltern = try ordner("eltern")
        defer { try? FileManager.default.removeItem(at: eltern) }
        let ordner = eltern.appending(component: "ablage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try alterStand(in: ordner)
        // Neben dem Ordner: eine Datei, die eine Marke entfernen wollte, und ein
        // „Zwilling“, der über sein Original wandern sollte.
        try schreiben("geschwister", "geschwister.txt", in: eltern)
        try schreiben("fremd", "fremd.txt.uebergang", in: eltern)
        let summe = Uebergangsdienst.sha256(Data("a-neu".utf8))
        let kopf = #"{"typ":"unterrichtsplanung-uebergang","version":1,"art":"einschalten","stempel":"s","kennung":"","dateien":"#
        let faelle: [(String, String)] = [
            ("pfad", kopf + #"[{"name":"../geschwister.txt","sha256":null},{"name":"../fremd.txt","sha256":"\#(Uebergangsdienst.sha256(Data("fremd".utf8)))"}]}"#),
            ("doppelt", kopf + #"[{"name":"a.json","sha256":"\#(summe)"},{"name":"a.json","sha256":null}]}"#),
            ("summe", kopf + #"[{"name":"a.json","sha256":"abc"}]}"#),
        ]
        for (fall, text) in faelle {
            try schreiben("a-neu", "a.json.uebergang", in: ordner)
            try schreiben(text, Uebergangsdienst.markenname, in: ordner)
            guard case .nichtVollendbar(let art, let grund, let rettung) = Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: fall) else {
                Issue.record("\(fall): erwartet nicht vollendbar")
                continue
            }
            #expect(art == nil && grund.hasPrefix("die Marke ist nicht lesbar (")
                    && rettung == ["uebergang-\(fall).json", "a-uebergang-\(fall).json"], "\(fall): \(grund)")
            try alterStandPruefen(in: ordner)
        }
        #expect(inhalt("geschwister.txt", in: eltern) == "geschwister")
        #expect(inhalt("fremd.txt.uebergang", in: eltern) == "fremd" && !liegt("fremd.txt", in: eltern))
    }

    // ── Übergeben, nicht eingesetzt (N51-01, E53): Vorgänger je Datei und der Rückweg ──

    @Test("Einsetzen behält je Datei den Vorgänger, bis die Marke fort ist — und der Haken feuert nach jedem Tausch")
    func vorgaengerWaehrendDesEinsetzens() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        let dienst = Uebergangsdienst(ordner: ordner)
        #expect(dienst.vorbereiten(.erneuern, kennung: Data([2]), stempel: "s", dateien: generation) == nil)
        #expect(dienst.uebergeben() == nil)
        var staende: [[String]] = []
        dienst.haken = { schritt in
            guard schritt == .einsetzen else { return }
            staende.append((try? self.namen(in: ordner)) ?? [])
        }
        #expect(dienst.einsetzen() == .vollendet)
        #expect(staende.count == 3, "ein Haken je Tausch: \(staende)")
        #expect(staende.first == ["a.json", "a.json.vorgaenger", "b.json", "c.json.uebergang", "uebergang.json"], "\(staende)")
        #expect(staende.dropFirst().first == ["a.json", "a.json.vorgaenger", "b.json.vorgaenger", "c.json.uebergang", "uebergang.json"], "\(staende)")
        #expect(staende.last == ["a.json", "a.json.vorgaenger", "b.json.vorgaenger", "c.json", "uebergang.json"], "\(staende)")
        try neuerStandPruefen(in: ordner)
    }

    @Test("Teilweise eingesetzt und ein Zwilling beschädigt: der Wiederanlauf stellt die Vorgänger zurück — der alte Stand gilt wirklich (N51-01)")
    func rueckwegUeberVorgaenger() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        let erster = Uebergangsdienst(ordner: ordner)
        #expect(erster.vorbereiten(.erneuern, kennung: Data([2]), stempel: "s", dateien: generation) == nil)
        #expect(erster.uebergeben() == nil)
        // Zwei Tausche sind geschehen, wie das Einsetzen sie hinterlässt; dann
        // endete der Prozess, und der dritte Zwilling ist beschädigt.
        let verwaltung = FileManager.default
        _ = try verwaltung.replaceItemAt(ordner.appending(component: "a.json"), withItemAt: ordner.appending(component: "a.json.uebergang"),
                                         backupItemName: "a.json.vorgaenger", options: [.withoutDeletingBackupItem])
        try verwaltung.moveItem(at: ordner.appending(component: "b.json"), to: ordner.appending(component: "b.json.vorgaenger"))
        try schreiben("verändert", "c.json.uebergang", in: ordner)

        let befund = Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w")
        #expect(befund == .nichtVollendbar(.erneuern, grund: "„c.json“ weicht ab", rettung: ["uebergang-w.json", "c-uebergang-w.json"]), "\(befund)")
        try alterStandPruefen(in: ordner)
        #expect(try namen(in: ordner) == ["a.json", "b.json", "c-uebergang-w.json", "uebergang-w.json"])
        #expect(Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w2") == .nichts)
    }

    @Test("Rückweg: eine neue Datei geht wieder fort; fehlt der Vorgänger einer ersetzten, bleibt alles liegen — gesperrt, nicht „alter Stand“")
    func rueckwegGrenzen() throws {
        // Fall 1: c.json (neu, ohne Original) ist eingesetzt, der Zwilling von a.json beschädigt.
        let eins = try ordner("eins")
        defer { try? FileManager.default.removeItem(at: eins) }
        try alterStand(in: eins)
        let d1 = Uebergangsdienst(ordner: eins)
        #expect(d1.vorbereiten(.passphrase, kennung: Data([3]), stempel: "s",
                               dateien: ["a.json": .daten(Data("a-neu".utf8)), "c.json": .daten(Data("c-neu".utf8))]) == nil)
        #expect(d1.uebergeben() == nil)
        try FileManager.default.moveItem(at: eins.appending(component: "c.json.uebergang"), to: eins.appending(component: "c.json"))
        try schreiben("verändert", "a.json.uebergang", in: eins)
        let b1 = Uebergangsdienst(ordner: eins).wiederanlaufen(stempel: "w")
        #expect(b1 == .nichtVollendbar(.passphrase, grund: "„a.json“ weicht ab", rettung: ["uebergang-w.json", "a-uebergang-w.json"]), "\(b1)")
        try alterStandPruefen(in: eins)
        #expect(try namen(in: eins) == ["a-uebergang-w.json", "a.json", "b.json", "uebergang-w.json"])

        // Fall 2: a.json ist ersetzt, aber ohne Vorgänger — kein Rückweg: Alles bleibt liegen.
        let zwei = try ordner("zwei")
        defer { try? FileManager.default.removeItem(at: zwei) }
        try alterStand(in: zwei)
        let d2 = Uebergangsdienst(ordner: zwei)
        #expect(d2.vorbereiten(.aufheben, kennung: nil, stempel: "s", dateien: generation) == nil)
        #expect(d2.uebergeben() == nil)
        _ = try FileManager.default.replaceItemAt(zwei.appending(component: "a.json"), withItemAt: zwei.appending(component: "a.json.uebergang"))
        try schreiben("verändert", "c.json.uebergang", in: zwei)
        let b2 = Uebergangsdienst(ordner: zwei).wiederanlaufen(stempel: "w")
        if case .nichtVollendbar = b2 { Issue.record("ein gemischter Stand ist kein alter Stand: \(b2)") }
        if case .vollendet = b2 { Issue.record("\(b2)") }
        #expect(inhalt("a.json", in: zwei) == "a-neu" && inhalt("b.json", in: zwei) == "b-alt"
                && liegt(Uebergangsdienst.markenname, in: zwei) && liegt("c.json.uebergang", in: zwei), "alles bleibt liegen")
    }

    @Test("Vorgänger ohne Marke — Rest eines vollendeten Einsetzens — werden beim Start still entfernt")
    func vorgaengerOhneMarke() throws {
        let ordner = try ordner()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try alterStand(in: ordner)
        try schreiben("uralt", "a.json.vorgaenger", in: ordner)
        #expect(Uebergangsdienst(ordner: ordner).wiederanlaufen(stempel: "w") == .nichts)
        try alterStandPruefen(in: ordner)
        #expect(try namen(in: ordner) == ["a.json", "b.json"])
        #expect(!Uebergangsdienst.nameZulaessig("a.json.vorgaenger"), "kein Name der Generation")
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
