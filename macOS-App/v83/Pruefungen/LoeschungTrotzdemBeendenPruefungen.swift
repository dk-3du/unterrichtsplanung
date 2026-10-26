// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Bestätigte Löschung im Archiv, dann „Trotzdem beenden“ (B99, E455, Z-AU2-04) ─────────────
// Die Löschung wartet auf das Ende ihres Alerts; ⌘Q stellt die Verlustfrage, „Trotzdem beenden“ geht.
// Scheitert die Löschung dabei, bleibt die App und die Warnung steht — wie beim Beenden über AppKit
// (Z-AS2a-08). Ohne das ginge die Warnung 0,35 s später mit der App fort.

@Suite("Eine bestätigte Löschung im Archiv, die beim „Trotzdem beenden“ scheitert, hält die App")
@MainActor
struct LoeschungTrotzdemBeendenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "loeschung-beenden-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// Eingeschaltet, mit Lernendendaten — ohne sie gäbe es weder Archiv noch Verlustfrage.
    private func speicher(_ ablage: URL) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                                 basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        s.jetztSichern()
        _ = try s.verschluesselungVorbereiten(passphrase: "Ein Satz, den man behält")
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let (b, gruppe) = try #require(a.mitNeuerGruppe(name: "6a", fach: "Biologie", art: .klasse, jetzt: a.erstellt))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: gruppe, jetzt: a.erstellt).bestand
        #expect(s.lernendenUebernehmen(c) == nil)
        // Die Frage steht, solange sie gesetzt ist; ein Fenster für die Verlustfrage gibt es (E425).
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fensterFuerFrage = { {} }
        return s
    }

    /// Ein Archiv mit einem Schuljahr und drei Personen — geschrieben, solange nichts gesperrt ist.
    private func archivAnlegen(_ s: Planungsspeicher) throws -> Archivbestand {
        let start = try #require(Tag(iso: "2025-08-04"))
        let planung = Planung.leer(titel: "Prüfvektor 2025/26", start: start, wochen: 4, basis: "", klassen: [], fachfarben: [:])
        let jahr = Archivjahr(id: "j-1", schuljahr: "2025/26", archiviert: RuecknahmeLernendenPruefungen.stempel,
                              planung: planung, lernende: RuecknahmeLernendenPruefungen.entwurf())
        let archiv = Archivbestand(geaendert: "", jahre: [jahr])
        #expect(s.archivSchreiben(archiv) == nil)
        return archiv
    }

    /// Die Personen im Archiv — ein unlesbares Archiv ist selbst ein Befund (Z-AS2a-10).
    private func personenImArchiv(_ s: Planungsspeicher) -> [String]? {
        guard case .gelesen(let archiv, _, _) = s.lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) else {
            Issue.record("das Archiv ist nicht lesbar")
            return nil
        }
        return archiv.jahre.flatMap { $0.lernende?.lernende.map(\.id) ?? [] }
    }

    /// Bis zur Verlustfrage: die Löschung im Blatt „Lernende“ bestätigt, die Lernendendaten — und mit ihnen das
    /// Archiv — gesperrt, dann ⌘Q (`beenden()`), noch vor der Fortsetzung der Löschung.
    private func loeschungBestaetigtDannBeenden(_ s: Planungsspeicher) throws {
        let gezeigt = try archivAnlegen(s)
        s.offenerDialog = .lernende  // Das Archiv steht im Blatt; dort hängt die Frage (E418).
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu) }
        antwortenBeiHaengendemAlert(s)
        #expect(s.ausstehendeArchivloeschungen.count == 1, "bestätigt, noch nicht geschrieben")
        let bestand = try #require(s.lernende.bestand)
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        #expect(s.lernende.setzen(bestand) != nil && s.verlustDroht)
        s.beenden()
        #expect(s.rueckfrage?.bestaetigung == "Trotzdem beenden" && !s.beendetGleich, "⌘Q: die Verlustfrage")
        #expect(s.ausstehendeArchivloeschungen.count == 1, "die Löschung steht weiter aus")
    }

    /// Nach beiden Fortsetzungen: Die App ist noch da — die Fortsetzung des Beendens versuchte es gar nicht erst,
    /// ohne zusätzlichen Ton, mit dem Merker —, die Warnung steht, das Archiv ist unberührt; das nächste Beenden
    /// fragt wieder — die Sicherung scheitert weiter (B91, E414).
    private func appBleibtMitWarnung(_ s: Planungsspeicher, versucht: Int, toene: Int) {
        #expect(versucht == 0, "die App bleibt — die Warnung ginge sonst mit ihr (Z-AU2-04, wie Z-AS2a-08)")
        #expect(s.beendenAmArchivAngehalten, "angehalten an der Löschung im Archiv")
        #expect(s.systemtoene == toene, "kein zusätzlicher Ton — die Warnung ist das Signal")
        #expect(s.ausstehendeArchivloeschungen.isEmpty, "die Löschung lief einmal")
        #expect(s.meldungen.contains { $0.text.hasPrefix("Das Archiv ließ sich nicht ändern") },
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
        #expect(personenImArchiv(s) == ["l-1", "l-2", "l-3"], "nichts gelöscht, nichts zerstört")
        s.beenden()
        #expect(s.rueckfrage?.bestaetigung == "Trotzdem beenden", "das nächste Beenden fragt wieder")
        s.rueckfrageBeantworten(false)
    }

    @Test("Wartet die Fortsetzung einer bestätigten Löschung hinter der Verlustfrage und scheitert die Löschung nach „Trotzdem beenden“, bleibt die App mit der Warnung (B99, Z-AU2-04)")
    func loeschungHinterDerVerlustfrage() async throws {
        let ablage = try ordner("dahinter")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        defer { s.lernende.schreibsperre = nil }
        // Jeder Versuch zu beenden zählt — auch einer, den `beendenErlauben` dann anhielte (Z-AS2a-08).
        var versucht = 0
        s.appBeenden = { [weak s] in versucht += 1; _ = s?.beendenErlauben() }
        try loeschungBestaetigtDannBeenden(s)
        try await abwarten("die Fortsetzung der Löschung wartet hinter der Verlustfrage") { s.ausstehendeFortsetzungen == 0 }
        #expect(s.ausstehendeArchivloeschungen.count == 1, "noch nicht geschrieben")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("Das Archiv ließ sich nicht ändern") }, "noch keine Warnung des Archivs")
        let toene = s.systemtoene
        antwortenBeiHaengendemAlert(s)
        #expect(s.ausstehendeFortsetzungen == 2, "die Löschung und das Beenden setzen fort")
        try await abwarten("beide Fortsetzungen sind gelaufen") { s.ausstehendeFortsetzungen == 0 }
        appBleibtMitWarnung(s, versucht: versucht, toene: toene)
    }

    @Test("Läuft eine bestätigte Löschung erst nach „Trotzdem beenden“ und scheitert, bleibt die App mit der Warnung (B99, Z-AU2-04)")
    func loeschungNachDerAntwort() async throws {
        let ablage = try ordner("danach")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        defer { s.lernende.schreibsperre = nil }
        var versucht = 0
        s.appBeenden = { [weak s] in versucht += 1; _ = s?.beendenErlauben() }
        try loeschungBestaetigtDannBeenden(s)
        // Gleich geantwortet, noch vor der Fortsetzung der Löschung: Sie läuft vor der des Beendens.
        let toene = s.systemtoene
        antwortenBeiHaengendemAlert(s)
        #expect(s.ausstehendeFortsetzungen == 2, "die Löschung und das Beenden setzen fort")
        try await abwarten("beide Fortsetzungen sind gelaufen") { s.ausstehendeFortsetzungen == 0 }
        appBleibtMitWarnung(s, versucht: versucht, toene: toene)
    }

    @Test("Scheiterte eine bestätigte Löschung schon vor ⌘Q — ihre Warnung stand bei der Entscheidung —, beendet „Trotzdem beenden“ (B99, Grenze der Wache)")
    func loeschungVorDemBeenden() async throws {
        let ablage = try ordner("vorher")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        defer { s.lernende.schreibsperre = nil }
        // Das Beenden fragt den Delegaten wie AppKit; beendet ist, was er erlaubt.
        var beendet = 0
        s.appBeenden = { [weak s] in if s?.beendenErlauben() == true { beendet += 1 } }
        let gezeigt = try archivAnlegen(s)
        s.offenerDialog = .lernende
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu) }
        antwortenBeiHaengendemAlert(s)
        let bestand = try #require(s.lernende.bestand)
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        #expect(s.lernende.setzen(bestand) != nil && s.verlustDroht)
        try await abwarten("die Löschung lief und scheiterte") {
            s.ausstehendeArchivloeschungen.isEmpty && s.ausstehendeFortsetzungen == 0
        }
        #expect(s.meldungen.contains { $0.text.hasPrefix("Das Archiv ließ sich nicht ändern") }, "die Warnung steht vor ⌘Q")
        s.beenden()
        #expect(s.rueckfrage?.bestaetigung == "Trotzdem beenden", "⌘Q: die Verlustfrage")
        antwortenBeiHaengendemAlert(s)
        try await abwarten("das Beenden setzte fort") { s.ausstehendeFortsetzungen == 0 }
        #expect(beendet == 1 && !s.beendenAmArchivAngehalten, "beendet — die Warnung war bei der Entscheidung zu sehen")
    }
}
