// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die Last einer Löschung im Archiv (B94, E454 a) ───────────────────────
// Jede bestätigte Löschung entschlüsselte das Archiv dreimal auf dem
// Hauptstrang: in ihrer Fortsetzung, vor dem Schreiben noch einmal und nach
// dem Schreiben zur Prüfung. Das in der Fortsetzung gelesene Archiv geht an
// das Schreiben, das nicht noch einmal liest; die Prüfung danach bleibt.
// Gezählt am Dienst (`archivEntschluesselungen`) — auf dem Hauptstrang. Seit
// F-02 (v89) liest die Fortsetzung abseits; auf dem Hauptstrang bleibt je
// Löschung die Rückprüfung, vor dem Beenden und in den Rückfällen beide
// (`HauptstrangPruefungen`).

@Suite("Last einer Löschung im Archiv: zwei Entschlüsselungen je Löschung, nicht drei — eine davon abseits (B94, E454, F-02)")
@MainActor
struct ArchivLoeschungLastPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "archivlast-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// Eingeschaltet, mit einem Archiv aus einem Schuljahr (`j-1`) und den drei Personen des Prüfentwurfs;
    /// das Archiv steht im Blatt, dort hängt die Frage (E418).
    private func speicher(_ ort: URL) async throws -> (Planungsspeicher, Archivbestand) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                                 basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let vorjahr = Planung.leer(titel: "Prüfvektor 2025/26", start: try #require(Tag(iso: "2025-08-04")), wochen: 4,
                                   basis: "", klassen: [], fachfarben: [:])
        let archiv = Archivbestand(geaendert: "", jahre: [
            Archivjahr(id: "j-1", schuljahr: "2025/26", archiviert: RuecknahmeLernendenPruefungen.stempel,
                       planung: vorjahr, lernende: RuecknahmeLernendenPruefungen.entwurf()),
        ])
        #expect(s.archivSchreiben(archiv) == nil)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.offenerDialog = .lernende
        return (s, archiv)
    }

    /// Das Archiv, wie es liegt — ein unlesbares ist selbst ein Befund.
    private func liegt(_ s: Planungsspeicher) -> Archivbestand? {
        guard case .gelesen(let archiv, _, _) = s.lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) else {
            Issue.record("das Archiv ist nicht lesbar")
            return nil
        }
        return archiv
    }

    @Test("Je Löschung zwei Entschlüsselungen, auf dem Hauptstrang eine — eine Person, ein Anliegen, ein Schuljahr; jede Löschung gilt (B94, E454 a, F-02)")
    func zweiJeLoeschung() async throws {
        let ort = try ordner("drei-arten")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var geschrieben = 0
        var gruende: [String?] = []
        let schreiben: @MainActor (Archivbestand) -> Void = { neu in gruende.append(s.archivSchreiben(neu)); geschrieben += 1 }
        var zahlen: [Int] = []

        var vorher = s.lernende.archivEntschluesselungen
        s.archivPersonLoeschenFragen("l-1", in: gezeigt, dann: schreiben)
        s.rueckfrageBeantworten(true)
        let personGeloescht = await uhr.vorruecken(bis: { geschrieben == 1 }, hoechstens: .seconds(1))
        try #require(personGeloescht, "die Person ist gelöscht")
        zahlen.append(s.lernende.archivEntschluesselungen - vorher)
        let nachPerson = try #require(liegt(s))
        #expect(nachPerson.jahre.first?.lernende?.lernende.map(\.id) == ["l-2", "l-3"])

        vorher = s.lernende.archivEntschluesselungen
        s.archivAnliegenLoeschenFragen("m-2", imJahr: "j-1", in: nachPerson, dann: schreiben)
        s.rueckfrageBeantworten(true)
        let anliegenGeloescht = await uhr.vorruecken(bis: { geschrieben == 2 }, hoechstens: .seconds(1))
        try #require(anliegenGeloescht, "das Anliegen ist gelöscht")
        zahlen.append(s.lernende.archivEntschluesselungen - vorher)
        let nachAnliegen = try #require(liegt(s))
        #expect(nachAnliegen.jahre.first?.lernende?.anliegen.map(\.id) == ["m-1", "m-3"])

        vorher = s.lernende.archivEntschluesselungen
        s.archivJahrLoeschenFragen("j-1", in: nachAnliegen, dann: schreiben)
        s.rueckfrageBeantworten(true)
        let jahrGeloescht = await uhr.vorruecken(bis: { geschrieben == 3 }, hoechstens: .seconds(1))
        try #require(jahrGeloescht, "das Schuljahr ist gelöscht")
        zahlen.append(s.lernende.archivEntschluesselungen - vorher)
        #expect(liegt(s)?.jahre.isEmpty == true)

        #expect(gruende == [nil, nil, nil], Comment(rawValue: "\(gruende)"))
        // Gelesen abseits (F-02), zurückgeprüft auf dem Hauptstrang.
        #expect(zahlen == [1, 1, 1], Comment(rawValue: "Entschlüsselungen je Löschung auf dem Hauptstrang: \(zahlen)"))
    }

    @Test("Vor dem Beenden ausgeführt: ebenso zwei Entschlüsselungen, einmal geschrieben (B94, Z-AS2a-07)")
    func zweiVorDemBeenden() async throws {
        let ort = try ordner("beenden")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        var geschrieben = 0
        let vorher = s.lernende.archivEntschluesselungen
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        // Gleich danach beendet, vor der Fortsetzung: Das Beenden führt sie noch aus.
        #expect(s.beendenErlauben())
        let zahl = s.lernende.archivEntschluesselungen - vorher
        #expect(geschrieben == 1 && zahl == 2, Comment(rawValue: "geschrieben \(geschrieben), Entschlüsselungen \(zahl)"))
        #expect(liegt(s)?.jahre.first?.lernende?.lernende.map(\.id) == ["l-2", "l-3"], "vor dem Beenden gelöscht")
    }

    @Test("Lässt sich das Archiv in der Fortsetzung nicht lesen, wird es nicht überschrieben — ohne es ein zweites Mal zu entschlüsseln (B94)")
    func unlesbarNichtUeberschrieben() async throws {
        let ort = try ordner("unlesbar")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let t = try #require(s.tresor)
        var geschrieben = 0
        var grund: String?
        let vorher = s.lernende.archivEntschluesselungen
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in grund = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        // Vor der Fortsetzung: ein Archiv unter dem eigenen Schlüssel, das sich nicht lesen lässt.
        let kaputt = try t.versiegeln(Data("{\"typ\":\"unterrichtsplanung-archiv\",\"version\":1,\"jahre\":{}}".utf8),
                                      inhalt: .archiv, ziel: .ablage)
        try kaputt.write(to: Ablage(ordner: ort).archiv)
        let gelaufen = await uhr.vorruecken(bis: { geschrieben == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "die Fortsetzung ist gelaufen")
        let zahl = s.lernende.archivEntschluesselungen - vorher
        #expect(grund?.hasPrefix("Das Archiv lässt sich nicht lesen") == true && grund?.contains("nicht überschrieben") == true,
                Comment(rawValue: grund ?? "—"))
        #expect(try Data(contentsOf: Ablage(ordner: ort).archiv) == kaputt, "unangetastet")
        // Gelesen abseits (F-02): Auf dem Hauptstrang entschlüsselt die Löschung nichts.
        #expect(zahl == 0, Comment(rawValue: "Entschlüsselungen auf dem Hauptstrang: \(zahl)"))
    }

    @Test("Schreibt die Fortsetzung nicht, verfällt ihr Befund: Ein späteres Schreiben liest selbst, ein inzwischen unlesbares Archiv bleibt unangetastet (B94)")
    func befundVerfaellt() async throws {
        let ort = try ordner("verfaellt")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let t = try #require(s.tresor)
        var gelaufen = false
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { _ in gelaufen = true }
        s.rueckfrageBeantworten(true)
        let fortgesetzt = await uhr.vorruecken(bis: { gelaufen }, hoechstens: .seconds(1))
        try #require(fortgesetzt, "die Fortsetzung ist gelaufen, ohne zu schreiben")
        let kaputt = try t.versiegeln(Data("{\"typ\":\"unterrichtsplanung-archiv\",\"version\":1,\"jahre\":{}}".utf8),
                                      inhalt: .archiv, ziel: .ablage)
        try kaputt.write(to: Ablage(ordner: ort).archiv)
        let vorher = s.lernende.archivEntschluesselungen
        let grund = s.archivSchreiben(gezeigt)
        #expect(grund?.hasPrefix("Das Archiv lässt sich nicht lesen") == true, Comment(rawValue: grund ?? "—"))
        #expect(try Data(contentsOf: Ablage(ordner: ort).archiv) == kaputt, "unangetastet")
        #expect(s.lernende.archivEntschluesselungen - vorher == 1, "das Schreiben las selbst")
    }

    @Test("Schreibt die Fortsetzung zweimal, nimmt nur das erste Schreiben ihren Befund — das zweite liest selbst (B94)")
    func befundNurEinmal() async throws {
        let ort = try ordner("einmal")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var zahlen: [Int] = []
        var fertig = false
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in
            var vorher = s.lernende.archivEntschluesselungen
            _ = s.archivSchreiben(neu)
            zahlen.append(s.lernende.archivEntschluesselungen - vorher)
            vorher = s.lernende.archivEntschluesselungen
            _ = s.archivSchreiben(neu)
            zahlen.append(s.lernende.archivEntschluesselungen - vorher)
            fertig = true
        }
        s.rueckfrageBeantworten(true)
        let gelaufen = await uhr.vorruecken(bis: { fertig }, hoechstens: .seconds(1))
        try #require(gelaufen, "die Fortsetzung ist gelaufen")
        #expect(zahlen == [1, 2], Comment(rawValue: "erstes Schreiben: nur die Rückprüfung, zweites: lesen und Rückprüfung — \(zahlen)"))
    }

    @Test("Findet eine bestätigte Löschung ihr Ziel nicht mehr, schreibt sie nichts und sagt es (Z-AV6-02)")
    func zielFort() async throws {
        let ort = try ordner("ziel-fort")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var geschrieben = 0
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        // Vor der Fortsetzung ist die Person schon fort — wie nach einem Lesen mit neuen Kennungen.
        #expect(s.archivSchreiben(gezeigt.ohnePerson("l-1", jetzt: "2026-10-10T10:00:00.000Z").bestand) == nil)
        let gelaufen = await uhr.vorruecken(bis: { s.ausstehendeArchivloeschungen.isEmpty && s.ausstehendeFortsetzungen == 0 }, hoechstens: .seconds(1))
        try #require(gelaufen, "die Fortsetzung ist gelaufen")
        #expect(geschrieben == 0, "nichts geschrieben")
        #expect(s.meldungen.last?.text.hasSuffix("“ ließ sich im Archiv nicht mehr finden — gelöscht wurde nichts.") == true
                && s.meldungen.last?.art == .warnung, Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
    }
}
