// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Einrichten, Passphrase ändern und Erneuern rechnen abseits des
/// Hauptstrangs (Befund B13): Der Hauptakteur bleibt frei, ein zweites
/// Absenden ist wirkungslos, ein Abbruch verwirft das Ergebnis.
@Suite("Schlüsselarbeit abseits des Hauptstrangs")
@MainActor
struct SchluesselarbeitPruefungen {

    private let alt = "Ein Satz, den man behält"
    private let neu = "Ein anderer Satz, den man behält"

    private func speicher() throws -> Planungsspeicher {
        Planungsspeicher(vorschau: Planung.leer(
            titel: "Schlüsselarbeit", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
            basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]), fachfarben: [:]))
    }

    @Test("Einrichten rechnet abseits des Hauptstrangs — der Hauptakteur bleibt frei")
    func hauptakteurFrei() async throws {
        let s = try speicher()
        let aufgabe = Task { @MainActor in try await s.verschluesselungVorbereitenAsynchron(passphrase: alt) }
        while !s.schluesselarbeitLaeuft { await Task.yield() }
        // Solange die Rechnung läuft, kommt der Hauptakteur hier zu Wort —
        // stünde er, käme die erste Runde erst mit dem Ergebnis. Wie viele
        // Runden es werden, sagt im parallelen Prüflauf nichts (andere Suiten
        // halten den Hauptakteur mit synchronem PBKDF2 an); gemessen wird am
        // laufenden Fenster, nicht hier.
        var runden = 0
        while s.schluesselarbeitLaeuft {
            runden += 1
            try await Task.sleep(for: .milliseconds(5))
        }
        let blatt = try await aufgabe.value
        #expect(blatt != nil && s.vorbereitung != nil)
        #expect(runden >= 1, "der Hauptakteur kam zu Wort, während PBKDF2 lief")
        #expect(!s.schluesselarbeitLaeuft)
    }

    @Test("Doppeltes Absenden ist wirkungslos, Verwerfen lässt das Ergebnis fallen")
    func doppeltUndVerworfen() async throws {
        let s = try speicher()
        let erste = Task { @MainActor in try await s.verschluesselungVorbereitenAsynchron(passphrase: alt) }
        while !s.schluesselarbeitLaeuft { await Task.yield() }
        let zweite = try await s.verschluesselungVorbereitenAsynchron(passphrase: alt)
        #expect(zweite == nil, "solange eine Rechnung läuft, ist die zweite wirkungslos")
        #expect(s.schluesselarbeitLaeuft)
        s.verschluesselungVerwerfen()
        let ergebnis = try await erste.value
        #expect(ergebnis == nil && s.vorbereitung == nil, "verworfen — nichts übernommen")
        // Danach geht es wieder — mit neuer Generation.
        #expect(try await s.verschluesselungVorbereitenAsynchron(passphrase: alt) != nil)
        #expect(s.vorbereitung != nil)
    }

    @Test("Passphrase ändern und Erneuern asynchron wirken wie synchron — die falsche Passphrase wirft")
    func aendernUndErneuern() async throws {
        let s = try speicher()
        try s.pruefverschluesselung(alt)
        let kennung = try #require(s.tresor?.kennung)

        await #expect(throws: Tresorfehler.self) {
            try await s.passphraseAendernAsynchron(alt: "nicht die richtige", neu: neu)
        }
        #expect(s.tresor?.passphraseStimmt(alt) == true, "nach dem Fehlschlag bleibt alles")
        let ergebnis = try await s.passphraseAendernAsynchron(alt: alt, neu: neu)
        #expect(ergebnis?.ablage == .vorschau)
        #expect(s.tresor?.kennung == kennung, "nur die Wicklung wechselt")
        #expect(s.tresor?.passphraseStimmt(neu) == true && s.tresor?.passphraseStimmt(alt) == false)

        await #expect(throws: Tresorfehler.self, "dieselbe Passphrase erneuert nichts") {
            try await s.schluesselErneuernVorbereitenAsynchron(alt: neu, neu: neu)
        }
        let blatt = try await s.schluesselErneuernVorbereitenAsynchron(alt: neu, neu: "Noch ein neuer Satz")
        #expect(blatt != nil)
        #expect(s.vorbereitung != nil && s.vorbereitung?.kennung != kennung)
        #expect(s.tresor?.kennung == kennung, "vor der Bestätigung geschieht nichts")
        s.verschluesselungEinschalten()
        #expect(s.tresor?.kennung != kennung)
        #expect(s.tresor?.passphraseStimmt("Noch ein neuer Satz") == true)
    }

    @Test("Ein Wechsel des Sitzungsschlüssels verwirft, was gerade rechnet — und eine Wicklung für einen anderen Schlüssel wird nicht übernommen")
    func schluesselwechsel() async throws {
        let s = try speicher()
        try s.pruefverschluesselung(alt)
        let erste = try #require(s.tresor)
        let aufgabe = Task { @MainActor in try await s.passphraseAendernAsynchron(alt: alt, neu: neu) }
        while !s.schluesselarbeitLaeuft { await Task.yield() }
        // Derweil ein anderer Schlüssel: Erneuern, bestätigt.
        _ = try s.schluesselErneuernVorbereiten(alt: alt, neu: "Noch ein neuer Satz")
        s.verschluesselungEinschalten()
        let zweite = try #require(s.tresor)
        #expect(zweite.kennung != erste.kennung)
        #expect(try await aufgabe.value == nil, "verworfen — der Sitzungsschlüssel hat gewechselt")
        #expect(zweite.passphraseStimmt("Noch ein neuer Satz") && !zweite.passphraseStimmt(neu))
        #expect(!erste.passphraseStimmt(neu), "auch der alte Tresor bekam die Wicklung nicht")

        // Der zweite Riegel: eine Wicklung, die für den ersten Schlüssel gerechnet wurde.
        let fremd = try Planungsspeicher.passphraseNeuWickeln(erste, alt: alt, neu: neu)
        let ergebnis = s.passphraseUebernehmen(fremd, fuer: erste.kennung)
        #expect(ergebnis.ablage == .zurueckgenommen("der Sitzungsschlüssel hat gewechselt"))
        #expect(!zweite.passphraseStimmt(neu))
    }
}
