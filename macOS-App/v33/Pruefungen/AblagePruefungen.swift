// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Der Schreibweg auf die Platte — geprüft an einer eigenen Ablage, damit
/// `Ablage.shared` und der Ordner des Prüflaufs unberührt bleiben.
@Suite("Ablage")
struct AblagePruefungen {

    private func ablage() throws -> (Ablage, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "ablage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return (Ablage(ordner: ordner), ordner)
    }

    private func inhalt(_ ziel: URL) -> String? {
        (try? Data(contentsOf: ziel)).flatMap { String(data: $0, encoding: .utf8) }
    }

    @Test("Der erste Schreibvorgang legt die Datei an, ohne Vorgängerfassung")
    func ersterSchreibvorgang() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("eins".utf8))
        #expect(inhalt(ablage.datei) == "eins")
        #expect(ablage.vorigeFassungLesen() == nil)
    }

    @Test("Der zweite Schreibvorgang schiebt den bisherigen Stand zur Seite")
    func vorgaengerfassung() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("eins".utf8))
        try ablage.schreiben(Data("zwei".utf8))
        #expect(inhalt(ablage.datei) == "zwei")
        #expect(ablage.vorigeFassungLesen().flatMap { String(data: $0, encoding: .utf8) } == "eins")

        try ablage.schreiben(Data("drei".utf8))
        #expect(inhalt(ablage.datei) == "drei")
        #expect(ablage.vorigeFassungLesen().flatMap { String(data: $0, encoding: .utf8) } == "zwei")
    }

    @Test("Die Nebendatei des Fortschreibens bleibt nicht liegen")
    func keineNebendatei() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("eins".utf8))
        try ablage.schreiben(Data("zwei".utf8))
        let liegt = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        #expect(!liegt.contains { $0.hasSuffix(".neu") }, "übrig: \(liegt)")
    }

    @Test("Ein leerer Ordner meldet keinen Bestand, kein Fehler")
    func keinBestand() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        guard case .keine = ablage.lesen() else {
            Issue.record("erwartet war .keine")
            return
        }
        #expect(ablage.stand() == nil)
    }

    @Test("Was geschrieben wurde, kommt unverändert zurück")
    func lesen() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let planung = Planung.leer(titel: "Ablageprobe",
                                   start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
                                   basis: "", klassen: [], fachfarben: [:])
        try ablage.schreiben(try Planungsdatei.schreiben(planung))
        guard case .daten(let gelesen) = ablage.lesen() else {
            Issue.record("erwartet war .daten")
            return
        }
        #expect(try Planungsdatei.lesen(gelesen).titel == "Ablageprobe")
    }

    @Test("Ein unlesbarer Stand wird als solcher gemeldet, nicht als leer")
    func unlesbar() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        // Ein Ordner an der Stelle der Datei: vorhanden, aber nicht lesbar.
        try FileManager.default.createDirectory(at: ablage.datei, withIntermediateDirectories: true)
        guard case .unlesbar = ablage.lesen() else {
            Issue.record("erwartet war .unlesbar")
            return
        }
    }

    @Test("Der beschädigte Stand wird beiseitegelegt und macht den Platz frei")
    func beiseitelegen() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("kaputt".utf8))
        #expect(ablage.beschaedigtenStandBeiseitelegen(stempel: "2026-08-28-0130-00"))
        #expect(!FileManager.default.fileExists(atPath: ablage.datei.path))
        let liegt = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        #expect(liegt.contains("planung-beschaedigt-2026-08-28-0130-00.json"))
    }

    @Test("Zwei Störungen bekommen verschiedene Rettungskopien")
    func zweiRettungskopien() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("erste".utf8))
        #expect(ablage.beschaedigtenStandBeiseitelegen(stempel: "2026-08-28-0130-00"))
        try ablage.schreiben(Data("zweite".utf8))
        #expect(ablage.beschaedigtenStandBeiseitelegen(stempel: "2026-08-28-0130-07"))

        let liegt = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
            .filter { $0.hasPrefix("planung-beschaedigt-") }
        #expect(liegt.count == 2, "beide Stände müssen erhalten bleiben: \(liegt)")
    }

    @Test("Ohne Datei ist nichts beiseitezulegen — und der Platz gilt als frei")
    func nichtsBeiseitezulegen() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        #expect(ablage.beschaedigtenStandBeiseitelegen(stempel: "2026-08-28-0130-00"))
    }
}

// ── Der Sicherungsweg der App ─────────────────────────────────────────────

/// Der Weg, den die App wirklich geht: `Planungsspeicher` über `Ablage.shared`.
///
/// Nicht `Planungsspeicher(vorschau:)` — der ist schreibgesperrt und käme an
/// `starten()`, `sichern()` und `jetztSichern()` nie vorbei. Geschrieben wird
/// deshalb in den Ordner aus `PLANUNGSORDNER`, den der Prüflauf mitbringt.
@Suite("Sicherungsweg", .serialized)
@MainActor
struct SicherungswegPruefungen {

    /// Die Vorbedingung jeder Prüfung dieser Reihe, hart statt gemeldet: Ohne
    /// eigenen Ablageort zeigte `Ablage.shared` auf die echte Planung.
    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    /// Nur die Dateien der Ablage, nicht der ganze Ordner: Was der Prüflauf
    /// sonst dort abgelegt hat, bleibt liegen.
    private func ablageLeeren() {
        let verwaltung = FileManager.default
        try? verwaltung.removeItem(at: Ablage.shared.datei)
        try? verwaltung.removeItem(at: Ablage.shared.vorherigeFassung)
        for name in rettungskopien() {
            try? verwaltung.removeItem(at: Ablage.shared.ordner.appendingPathComponent(name))
        }
    }

    private func rettungskopien() -> [String] {
        let inhalt = try? FileManager.default
            .contentsOfDirectory(atPath: Ablage.shared.ordner.path)
        return (inhalt ?? []).filter { $0.hasPrefix("planung-beschaedigt-") }
    }

    private func planung(_ titel: String) throws -> Planung {
        Planung.leer(titel: titel, start: try #require(Tag(iso: "2026-08-10")), wochen: 6,
                     basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                     fachfarben: [:])
    }

    private func anlegen(_ speicher: Planungsspeicher, titel: String) throws {
        speicher.neuePlanung(titel: titel, start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 6, basis: "",
                             klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             ersterSchultag: nil, uebernahme: [])
    }

    /// Der Änderungsstempel löst in Millisekunden auf, und `jetztSichern`
    /// schreibt nur bei abweichendem Stempel. Zwei Änderungen im selben
    /// Programmlauf fallen ohne Abstand in dieselbe Millisekunde.
    private func stempelweiter() {
        Thread.sleep(forTimeInterval: 0.003)
    }

    private func aufDerPlatte() throws -> Planung {
        try Planungsdatei.lesen(try Data(contentsOf: Ablage.shared.datei))
    }

    private func vorigeFassung() throws -> Planung {
        try Planungsdatei.lesen(try #require(Ablage.shared.vorigeFassungLesen()))
    }

    @Test("Ohne Bestand fragt der Start nach einer neuen Planung")
    func startOhneBestand() {
        ablageLeeren()
        let speicher = Planungsspeicher()
        speicher.starten()

        #expect(speicher.planung == nil)
        #expect(speicher.offenerDialog == .neuePlanung)
        #expect(!speicher.sicherungLiegtStill)
    }

    @Test("Der Start lädt den Stand von der Platte — und nur einmal")
    func startMitBestand() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        try Ablage.shared.schreiben(try Planungsdatei.schreiben(try planung("Erster Stand")))

        let speicher = Planungsspeicher()
        speicher.starten()
        #expect(speicher.planung?.titel == "Erster Stand")
        #expect(speicher.offenerDialog == nil)
        #expect(speicher.letzteSicherung != nil)

        // Der zweite Aufruf darf den geladenen Stand nicht ersetzen.
        try Ablage.shared.schreiben(try Planungsdatei.schreiben(try planung("Zweiter Stand")))
        speicher.starten()
        #expect(speicher.planung?.titel == "Erster Stand")
    }

    @Test("Ein unlesbarer Stand sperrt das Schreiben, statt ihn zu überschreiben")
    func startMitUnlesbaremStand() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        // Ein Ordner an der Stelle der Datei: vorhanden, aber nicht lesbar.
        try FileManager.default.createDirectory(at: Ablage.shared.datei,
                                                withIntermediateDirectories: true)
        let speicher = Planungsspeicher()
        speicher.starten()

        #expect(speicher.planung == nil)
        #expect(speicher.offenerDialog == .neuePlanung)
        #expect(speicher.sicherungLiegtStill)
        #expect(speicher.meldungen.contains { $0.art == .warnung })
        #expect(rettungskopien().isEmpty)
    }

    @Test("Eine neue Planung hebt die Startsperre auf und legt den Stand beiseite")
    func startsperreWirdAufgehoben() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        try FileManager.default.createDirectory(at: Ablage.shared.datei,
                                                withIntermediateDirectories: true)
        let speicher = Planungsspeicher()
        speicher.starten()
        #expect(speicher.sicherungLiegtStill)

        try anlegen(speicher, titel: "Nach der Sperre")
        stempelweiter()
        speicher.jetztSichern()

        #expect(!speicher.sicherungLiegtStill)
        #expect(try aufDerPlatte().titel == "Nach der Sperre")
        #expect(rettungskopien().count == 1)
    }

    @Test("Ein beschädigter Stand wird gerettet und wieder hingelegt")
    func beschaedigterStandWirdGerettet() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        try Ablage.shared.schreiben(try Planungsdatei.schreiben(try planung("Die Rettung")))
        try Ablage.shared.schreiben(Data("{kein JSON".utf8))

        let speicher = Planungsspeicher()
        speicher.starten()

        #expect(speicher.planung?.titel == "Die Rettung")
        #expect(rettungskopien().count == 1)
        // Sonst fände der nächste Start nichts mehr vor.
        #expect(try aufDerPlatte().titel == "Die Rettung")
        #expect(speicher.meldungen.contains { $0.art == .warnung })
    }

    @Test("Ohne Vorgängerfassung bleibt vom beschädigten Stand die Rettungskopie")
    func beschaedigterStandOhneVorgaenger() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        try Ablage.shared.schreiben(Data("{kein JSON".utf8))

        let speicher = Planungsspeicher()
        speicher.starten()

        #expect(speicher.planung == nil)
        #expect(speicher.offenerDialog == .neuePlanung)
        #expect(rettungskopien().count == 1)
        #expect(!FileManager.default.fileExists(atPath: Ablage.shared.datei.path))
    }

    @Test("Der entprellte Weg schreibt einmal, und zwar den jüngsten Stand")
    func entprellteSicherung() async throws {
        ablageLeeren()
        defer { ablageLeeren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        try anlegen(speicher, titel: "Entprellt")
        stempelweiter()
        speicher.titelSetzen("Zwischenstand")
        stempelweiter()
        speicher.titelSetzen("Endstand")

        // 700 ms Entprellung, dann das Schreiben abseits des Hauptstrangs.
        try await Task.sleep(for: .milliseconds(1500))

        #expect(try aufDerPlatte().titel == "Endstand")
        #expect(speicher.letzteSicherung != nil)
        // Ein einziger Schreibvorgang — sonst läge hier schon eine Vorgängerfassung.
        #expect(Ablage.shared.vorigeFassungLesen() == nil)
    }

    @Test("Jetzt sichern macht aus der Vorgängerfassung keine Kopie")
    func vorgaengerfassungBleibtStehen() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        try anlegen(speicher, titel: "Erster Wurf")
        speicher.jetztSichern()
        #expect(try aufDerPlatte().titel == "Erster Wurf")

        stempelweiter()
        speicher.titelSetzen("Zweiter Wurf")
        speicher.jetztSichern()
        #expect(try aufDerPlatte().titel == "Zweiter Wurf")
        #expect(try vorigeFassung().titel == "Erster Wurf")

        // Ohne Änderung wird nicht noch einmal geschrieben.
        speicher.jetztSichern()
        speicher.jetztSichern()
        #expect(try aufDerPlatte().titel == "Zweiter Wurf")
        #expect(try vorigeFassung().titel == "Erster Wurf")
    }

    @Test("Eine Vorschau rührt die Ablage auf keinem der beiden Wege an")
    func vorschauSchreibtNicht() async throws {
        ablageLeeren()
        defer { ablageLeeren() }
        let speicher = Planungsspeicher(vorschau: try planung("Nur Vorschau"))
        stempelweiter()
        speicher.titelSetzen("Trotzdem geändert")
        try await Task.sleep(for: .milliseconds(1000))
        speicher.jetztSichern()

        #expect(!FileManager.default.fileExists(atPath: Ablage.shared.datei.path))
        // Eine Vorschau schreibt absichtlich nicht; das ist keine Störung.
        #expect(!speicher.sicherungLiegtStill)
    }
}
