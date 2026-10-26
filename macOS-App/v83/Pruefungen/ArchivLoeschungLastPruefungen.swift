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
// Gezählt am Dienst (`archivEntschluesselungen`).

@Suite("Last einer Löschung im Archiv: zwei Entschlüsselungen je Löschung, nicht drei (B94, E454)")
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
    private func speicher(_ ort: URL) throws -> (Planungsspeicher, Archivbestand) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                                 basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        s.jetztSichern()
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
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

    @Test("Je Löschung zwei Entschlüsselungen — eine Person, ein Anliegen, ein Schuljahr; jede Löschung gilt (B94, E454 a)")
    func zweiJeLoeschung() async throws {
        let ort = try ordner("drei-arten")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try speicher(ort)
        var geschrieben = 0
        var gruende: [String?] = []
        let schreiben: @MainActor (Archivbestand) -> Void = { neu in gruende.append(s.archivSchreiben(neu)); geschrieben += 1 }
        var zahlen: [Int] = []

        var vorher = s.lernende.archivEntschluesselungen
        s.archivPersonLoeschenFragen("l-1", in: gezeigt, dann: schreiben)
        s.rueckfrageBeantworten(true)
        try await abwarten("die Person ist gelöscht") { geschrieben == 1 }
        zahlen.append(s.lernende.archivEntschluesselungen - vorher)
        let nachPerson = try #require(liegt(s))
        #expect(nachPerson.jahre.first?.lernende?.lernende.map(\.id) == ["l-2", "l-3"])

        vorher = s.lernende.archivEntschluesselungen
        s.archivAnliegenLoeschenFragen("m-2", imJahr: "j-1", in: nachPerson, dann: schreiben)
        s.rueckfrageBeantworten(true)
        try await abwarten("das Anliegen ist gelöscht") { geschrieben == 2 }
        zahlen.append(s.lernende.archivEntschluesselungen - vorher)
        let nachAnliegen = try #require(liegt(s))
        #expect(nachAnliegen.jahre.first?.lernende?.anliegen.map(\.id) == ["m-1", "m-3"])

        vorher = s.lernende.archivEntschluesselungen
        s.archivJahrLoeschenFragen("j-1", in: nachAnliegen, dann: schreiben)
        s.rueckfrageBeantworten(true)
        try await abwarten("das Schuljahr ist gelöscht") { geschrieben == 3 }
        zahlen.append(s.lernende.archivEntschluesselungen - vorher)
        #expect(liegt(s)?.jahre.isEmpty == true)

        #expect(gruende == [nil, nil, nil], Comment(rawValue: "\(gruende)"))
        #expect(zahlen == [2, 2, 2], Comment(rawValue: "Entschlüsselungen je Löschung: \(zahlen)"))
    }

    @Test("Vor dem Beenden ausgeführt: ebenso zwei Entschlüsselungen, einmal geschrieben (B94, Z-AS2a-07)")
    func zweiVorDemBeenden() async throws {
        let ort = try ordner("beenden")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try speicher(ort)
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
        let (s, gezeigt) = try speicher(ort)
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
        try await abwarten("die Fortsetzung ist gelaufen") { geschrieben == 1 }
        let zahl = s.lernende.archivEntschluesselungen - vorher
        #expect(grund?.hasPrefix("Das Archiv lässt sich nicht lesen") == true && grund?.contains("nicht überschrieben") == true,
                Comment(rawValue: grund ?? "—"))
        #expect(try Data(contentsOf: Ablage(ordner: ort).archiv) == kaputt, "unangetastet")
        #expect(zahl == 1, Comment(rawValue: "Entschlüsselungen: \(zahl)"))
    }

    @Test("Schreibt die Fortsetzung nicht, verfällt ihr Befund: Ein späteres Schreiben liest selbst, ein inzwischen unlesbares Archiv bleibt unangetastet (B94)")
    func befundVerfaellt() async throws {
        let ort = try ordner("verfaellt")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try speicher(ort)
        let t = try #require(s.tresor)
        var gelaufen = false
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { _ in gelaufen = true }
        s.rueckfrageBeantworten(true)
        try await abwarten("die Fortsetzung ist gelaufen, ohne zu schreiben") { gelaufen }
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
        let (s, gezeigt) = try speicher(ort)
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
        try await abwarten("die Fortsetzung ist gelaufen") { fertig }
        #expect(zahlen == [1, 2], Comment(rawValue: "erstes Schreiben: nur die Rückprüfung, zweites: lesen und Rückprüfung — \(zahlen)"))
    }

    @Test("Findet eine bestätigte Löschung ihr Ziel nicht mehr, schreibt sie nichts und sagt es (Z-AV6-02)")
    func zielFort() async throws {
        let ort = try ordner("ziel-fort")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try speicher(ort)
        var geschrieben = 0
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        // Vor der Fortsetzung ist die Person schon fort — wie nach einem Lesen mit neuen Kennungen.
        #expect(s.archivSchreiben(gezeigt.ohnePerson("l-1", jetzt: "2026-10-10T10:00:00.000Z").bestand) == nil)
        try await abwarten("die Fortsetzung ist gelaufen") { s.ausstehendeArchivloeschungen.isEmpty && s.ausstehendeFortsetzungen == 0 }
        #expect(geschrieben == 0, "nichts geschrieben")
        #expect(s.meldungen.last?.text.hasSuffix("“ ließ sich im Archiv nicht mehr finden — gelöscht wurde nichts.") == true
                && s.meldungen.last?.art == .warnung, Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
    }
}
