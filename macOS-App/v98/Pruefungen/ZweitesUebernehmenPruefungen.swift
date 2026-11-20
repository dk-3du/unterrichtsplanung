// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Ein zweites „Übernehmen“ desselben Entwurfs (v84, AT4a, E509) ──────────
// Nach „Verwerfen“ der Namensfrage setzt das Blatt „Lernende“ verzögert fort (`namenVorher`); in dieser Lücke ging ein
// zweites ⏎ durch, und „Übernehmen“ schrieb denselben Entwurf mit demselben Ausgang ein zweites Mal (Z-AT4-01). Hier
// nachgestellt am Speicher: was richtet das zweite Schreiben an? Ohne Jahresdatei, mit Jahresdatei (gelöschte Person
// samt Termin, neuer Termin mit Wunsch) und mit einem Termin außerhalb der Planung (Z-AT4a-03, -04).

@Suite("Zweites „Übernehmen“ desselben Entwurfs — Termine, Wünsche, Rückverweise")
@MainActor
struct ZweitesUebernehmenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "zweites-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    @Test("Ein Termin mit Wunsch „In der Planung eintragen“, zweimal übernommen: Ein Vorhaben, Rückverweis bleibt")
    func terminMitWunsch() throws {
        let ablage = try ordner("wunsch")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.id = "k-kl"
        leitung.fach = "6a"
        p.klassen += [leitung]
        s.planung = p
        s.jetztSichern()
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)

        // Der Stand beim Öffnen des Blatts — der Ausgang beider „Übernehmen“.
        let ausgang = try #require(s.lernendenEntwurfBeginnen())
        let s0 = ausgang.erstellt
        let (b, gruppe) = try #require(ausgang.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: s0))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: gruppe, jetzt: s0).bestand
            .mitBindung(gruppe, an: Zeilenbindung(planung: ausgang.planung, klasseId: p.klassen[0].id), jetzt: s0)
            .mitBindung(gruppe, an: Zeilenbindung(planung: ausgang.planung, klasseId: "k-kl"), jetzt: s0)
        let anna = try #require(c.lernende.first).id
        let (d, termin) = try #require(c.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [anna],
                                                          datum: "2026-08-20", frist: "", uhrzeit: "07:45", jetzt: s0))
        let entwurf = d.mitTerminwunsch(termin, zeile: "k-kl")

        #expect(s.lernendenUebernehmen(entwurf, ausgang: ausgang) == nil)
        let erste = s.planung?.eintraege.filter { $0.termin == termin }.map(\.id) ?? []
        #expect(erste.count == 1, "das erste „Übernehmen“ trägt den Termin ein")
        let eintraege = try #require(s.planung?.eintraege.count)
        let anliegen = try #require(s.lernende.bestand?.anliegen)

        // Das zweite „Übernehmen“ aus der Lücke: derselbe Entwurf, derselbe Ausgang.
        #expect(s.lernendenUebernehmen(entwurf, ausgang: ausgang) == nil)
        let zweite = s.planung?.eintraege.filter { $0.termin == termin }.map(\.id) ?? []
        #expect(zweite == erste, "kein zweites Vorhaben für denselben Termin: \(zweite)")
        #expect(s.planung?.eintraege.count == eintraege, "die Planung hat so viele Vorhaben wie nach dem ersten")
        #expect(s.lernende.bestand?.anliegen.first { $0.id == termin }?.vorhaben == erste.first, "der Rückverweis bleibt")
        #expect(s.lernende.bestand?.anliegen == anliegen, "die Anliegen bleiben, wie sie nach dem ersten waren")
    }

    /// Ein eingeschalteter Speicher mit „Klassenleitung · 6a“ („k-kl“), verknüpft wie „6a · Biologie“ mit der Lerngruppe „6a“
    /// mit Anna und Ben (E686), und —
    /// schon in der Jahresdatei — einem Termin für Ben mit Vorhaben. Dazu der Stand beim Öffnen des Blatts.
    private func mitJahresdatei(_ ablage: URL) throws -> (Planungsspeicher, ausgang: Lernendenbestand, anna: String,
                                                         ben: String, bens: String) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.id = "k-kl"
        leitung.fach = "6a"
        p.klassen += [leitung]
        s.planung = p
        s.jetztSichern()
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let s0 = a.erstellt
        let (b, gruppe) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: s0))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: gruppe, jetzt: s0).bestand
            .mitBindung(gruppe, an: Zeilenbindung(planung: a.planung, klasseId: p.klassen[0].id), jetzt: s0)
            .mitBindung(gruppe, an: Zeilenbindung(planung: a.planung, klasseId: "k-kl"), jetzt: s0)
        let anna = try #require(c.lernende.first { $0.nachname == "Abel" }).id
        let ben = try #require(c.lernende.first { $0.nachname == "Bauer" }).id
        let (d, bens) = try #require(c.mitNeuemAnliegen(.termin, titel: "Gespräch Ben", lerngruppe: "", betroffene: [ben],
                                                       datum: "2026-08-18", frist: "", uhrzeit: "08:00", jetzt: s0))
        #expect(s.lernendenUebernehmen(d.mitTerminwunsch(bens, zeile: "k-kl"), ausgang: a) == nil)
        #expect(s.planung?.eintraege.contains { $0.termin == bens } == true, "Bens Termin hat sein Vorhaben")
        return (s, try #require(s.lernendenEntwurfBeginnen()), anna, ben, bens)
    }

    @Test("Mit Jahresdatei: Ben gelöscht samt Termin, ein neuer Termin mit Wunsch — das zweite „Übernehmen“ ändert nichts")
    func mitJahresdateiZweimal() throws {
        let ablage = try ordner("jahresdatei")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, ausgang, anna, ben, bens) = try mitJahresdatei(ablage)
        let (ohneBen, _) = ausgang.ohnePerson(ben)
        let (e, annas) = try #require(ohneBen.mitNeuemAnliegen(.termin, titel: "Gespräch Anna", lerngruppe: "",
                                                              betroffene: [anna], datum: "2026-08-25", frist: "",
                                                              uhrzeit: "07:45", jetzt: ausgang.erstellt))
        let entwurf = e.mitTerminwunsch(annas, zeile: "k-kl")

        #expect(s.lernendenUebernehmen(entwurf, ausgang: ausgang) == nil)
        let planung = try #require(s.planung)
        let bestand = try #require(s.lernende.bestand)
        let titel = s.widerrufenTitel
        let meldungen = s.meldungen.count
        #expect(!planung.eintraege.contains { $0.termin == bens }, "Bens Vorhaben ging mit seinem Termin")
        #expect(planung.eintraege.filter { $0.termin == annas }.count == 1, "Annas Termin hat ein Vorhaben")

        // Das zweite „Übernehmen“ aus der Lücke: derselbe Entwurf, derselbe Ausgang.
        #expect(s.lernendenUebernehmen(entwurf, ausgang: ausgang) == nil)
        #expect(s.planung == planung, "die Planung bleibt, wie sie nach dem ersten war")
        var zweiter = try #require(s.lernende.bestand)
        zweiter.geaendert = bestand.geaendert
        #expect(zweiter == bestand, "die Jahresdatei trägt denselben Stand — bis auf den Stempel")
        #expect(s.widerrufenTitel == titel, "kein zweiter Schritt im Verlauf")
        #expect(s.meldungen.count == meldungen, "keine zweite Meldung")
    }

    /// Die eine Folge eines zweiten „Übernehmen“: Ein Termin außerhalb der Planung wird ein zweites Mal gemeldet —
    /// hingenommen (E517: selten, nur mit einem zweiten ⏎ in der Lücke). Ändert sich das, fällt es hier auf.
    @Test("Ein Termin außerhalb der Planung: Das zweite „Übernehmen“ meldet ihn ein zweites Mal (E517, hingenommen)")
    func ausserhalbZweimal() throws {
        let ablage = try ordner("ausserhalb")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, ausgang, anna, _, _) = try mitJahresdatei(ablage)
        let (e, spaet) = try #require(ausgang.mitNeuemAnliegen(.termin, titel: "Nach den Ferien", lerngruppe: "",
                                                              betroffene: [anna], datum: "2027-03-01", frist: "",
                                                              uhrzeit: "07:45", jetzt: ausgang.erstellt))
        let entwurf = e.mitTerminwunsch(spaet, zeile: "k-kl")
        func ausserhalb() -> Int { s.meldungen.filter { $0.text.contains("außerhalb der Planung") }.count }

        #expect(s.lernendenUebernehmen(entwurf, ausgang: ausgang) == nil)
        #expect(ausserhalb() == 1, "das erste „Übernehmen“ meldet den Termin außerhalb der Planung")
        #expect(s.lernendenUebernehmen(entwurf, ausgang: ausgang) == nil)
        #expect(ausserhalb() == 2, "das zweite meldet ihn noch einmal — sonst nichts (E517)")
    }
}
