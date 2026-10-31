// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

// ── H1-01 (v87, AY9a, E896 a, E900 a, E901): Geht ein Termin mit seinem Vorhaben, kommt er zurück oder entsteht er
// neu, wird die Planung sofort gesichert ──
// `termineNachfuehren` schreibt die Jahresdatei sofort; die Planung, aus der das Vorhaben ging, wurde bis 2.2.1 nur
// entprellt (700 ms). Endete die App dazwischen, stand das Vorhaben nach dem Neustart wieder im Raster, der Termin samt
// Rückläufen fehlte — still; umgekehrt (⌘Z) stand der Termin ohne Vorhaben da. In AY9 an einer Kopie nachgestellt (rot).
// Die Stelluhr hält das Entprellen an; so steht auf der Platte, was ein Absturz in der Lücke hinterließe. Wird ein Vorhaben
// mit Termin nur bearbeitet, verschoben oder abgehakt, bleibt es beim Entprellen.

import Foundation
import Testing

@testable import Unterrichtsplanung

private typealias Tag = Unterrichtsplanung.Tag

@Suite("H1-01: Geht ein Termin mit seinem Vorhaben, kommt er zurück oder entsteht er neu, sichert die Planung sofort (E896 a, E900 a, E901)", .serialized)
@MainActor
struct TerminfolgeSichertPlanungPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand, "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory.appending(component: "h101-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// Wie `TerminkopplungPruefungen.speicher`: 6a, Klassenleitung, Weiteres; Anna und Ben; ein Termin für Anna mit Vorhaben.
    private func speicher(_ ablage: URL) async throws -> (Planungsspeicher, termin: String, vorhaben: String) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.id = "k-kl"
        leitung.fach = "6a"
        var weiteres = Klasse.sonderzeile(.weiteres)
        weiteres.id = "k-we"
        p.klassen += [leitung, weiteres]
        s.planung = p
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let s0 = a.erstellt
        let (b, gruppe) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: s0))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: gruppe, jetzt: s0).bestand
            .mitBindung(gruppe, an: Zeilenbindung(planung: a.planung, klasseId: p.klassen[0].id), jetzt: s0)
            .mitBindung(gruppe, an: Zeilenbindung(planung: a.planung, klasseId: "k-kl"), jetzt: s0)
        let anna = try #require(c.lernende.first).id
        let (d, termin) = try #require(c.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [anna],
                                                          datum: "2026-08-20", frist: "", uhrzeit: "07:45", jetzt: s0))
        #expect(s.lernendenUebernehmen(d.mitTerminwunsch(termin, zeile: "k-kl")) == nil)
        let vorhaben = try #require(s.planung?.eintraege.first { $0.termin == termin }).id
        return (s, termin, vorhaben)
    }

    /// Ein zweiter Speicher auf derselben Ablage — wie der nächste Start nach einem Absturz.
    private func neustart(_ ablage: URL) async -> Planungsspeicher {
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablage))
        zweiter.nachwahlProbe = true
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        return zweiter
    }

    @Test("H1-01: Ein Vorhaben mit Termin entfernt, die Entprellung angehalten — nach dem Neustart sind beide fort")
    func entfernt() async throws {
        let ablage = try ordner("entfernt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try await speicher(ablage)
        await s.sicherung.entprelltJetzt()
        s.jetztSichern()
        s.takt = Stelluhr()
        s.aendern(Schrittname.vorhabenEntfernen) { $0.eintraege.removeAll { $0.id == v } }
        #expect(s.lernende.bestand?.anliegen.contains { $0.id == t } == false, "in der Sitzung geht der Termin mit")
        let zweiter = await neustart(ablage)
        // Der Neustart hat beides geladen — sonst wäre „fort“ leer wahr (Z-AY9a-03).
        let geladen = try #require(zweiter.planung)
        let bestand = try #require(zweiter.lernende.bestand)
        #expect(geladen.klassen.contains { $0.id == "k-kl" } && bestand.lernende.contains { $0.nachname == "Abel" })
        let t2 = bestand.anliegen.first { $0.id == t }
        let v2 = geladen.eintraege.first { $0.id == v }
        #expect(t2 == nil && v2 == nil, "H1-01: Termin und Vorhaben gehen gemeinsam — Vorhaben \(v2?.titel ?? "fort")")
    }

    @Test("Z-AY9a-01: Auch mit demselben Stempel wie der zuletzt geschriebene Stand (angehaltene Uhr) wird sofort geschrieben")
    func gleicherStempel() async throws {
        let ablage = try ordner("stempel")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try await speicher(ablage)
        await s.sicherung.entprelltJetzt()
        s.jetztSichern()
        s.takt = Stelluhr()
        // Zwei Änderungen mit demselben Stempel, dazwischen ein gleichlaufendes Schreiben — wie zwei Handgriffe in
        // derselben Millisekunde. Ohne angemeldete Änderung hielte der Dienst die zweite für gesichert.
        // Die Lage muss eintreten (Z-AY9aN-02): derselbe Stempel, und das Schreiben dazwischen hat geschrieben.
        let (stempel, danach) = Pruefuhr.angehalten {
            s.aendern(Schrittname.titelAendern) { $0.titel += " (Probe)" }
            let stempel = s.planung?.geaendert
            s.jetztSichern()
            s.aendern(Schrittname.vorhabenEntfernen) { $0.eintraege.removeAll { $0.id == v } }
            return (stempel, s.planung?.geaendert)
        }
        #expect(stempel != nil && stempel == danach, "gleicher Stempel")
        let zweiter = await neustart(ablage)
        let geladen = try #require(zweiter.planung)
        let bestand = try #require(zweiter.lernende.bestand)
        #expect(geladen.titel.hasSuffix(" (Probe)"), "das Schreiben dazwischen trug — und der Neustart lud diese Planung")
        #expect(bestand.anliegen.first { $0.id == t } == nil && geladen.eintraege.first { $0.id == v } == nil,
                "Termin und Vorhaben gehen gemeinsam, auch bei gleichem Stempel")
    }

    @Test("Z-AY9a-02: Ein neues Vorhaben gleich als Termin angelegt — sofort gesichert, nach dem Neustart beide da und verbunden")
    func neuerTerminSofort() async throws {
        let ablage = try ordner("neu")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let anna = try #require(s.lernende.bestand?.lernende.first { $0.nachname == "Abel" }).id
        await s.sicherung.entprelltJetzt()
        s.jetztSichern()
        s.takt = Stelluhr()
        s.vorhabenOeffnen(klasse: "k-we", woche: 1)
        var e = try #require(s.vorhabenDialog)
        e.titel = "Hospitation"
        e.datum = Tag(iso: "2026-08-12")
        e.termin = true
        e.terminzeit = "9.15"
        e.terminpersonen = [anna]
        s.vorhabenSichernFragen(e)
        let v = try #require(s.planung?.eintraege.first { $0.titel == "Hospitation" })
        let zweiter = await neustart(ablage)
        let v2 = zweiter.planung?.eintraege.first { $0.id == v.id }
        let t2 = zweiter.lernende.bestand?.anliegen.first { $0.id == v.termin }
        #expect(v2?.termin == v.termin && t2?.vorhaben == v.id, "beide da und verbunden")
        #expect(!zweiter.meldungen.contains { $0.text.contains("Vorhaben in der Planung verloren") },
                Comment(rawValue: "\(zweiter.meldungen.map(\.text))"))
    }

    @Test("H1-01: Entfernt und mit ⌘Z zurückgeholt, die Entprellung angehalten — nach dem Neustart sind beide da und verbunden, ohne Meldung")
    func zurueck() async throws {
        let ablage = try ordner("zurueck")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try await speicher(ablage)
        s.aendern(Schrittname.vorhabenEntfernen) { $0.eintraege.removeAll { $0.id == v } }
        await s.sicherung.entprelltJetzt()
        s.jetztSichern()
        s.takt = Stelluhr()
        s.widerrufen()
        #expect(s.planung?.eintraege.contains { $0.id == v } == true && s.lernende.bestand?.anliegen.contains { $0.id == t } == true,
                "in der Sitzung kommen beide zurück")
        let zweiter = await neustart(ablage)
        let t2 = zweiter.lernende.bestand?.anliegen.first { $0.id == t }
        let v2 = zweiter.planung?.eintraege.first { $0.id == v }
        #expect(t2?.vorhaben == v && v2?.termin == t, "H1-01: beide da und verbunden")
        #expect(!zweiter.meldungen.contains { $0.text.contains("Vorhaben in der Planung verloren") },
                Comment(rawValue: "\(zweiter.meldungen.map(\.text))"))
    }

    @Test("H1-01: Wer nur bearbeitet, bleibt beim Entprellen — der Titel eines Vorhabens mit Termin, nach dem Neustart wie vorher")
    func bearbeitenEntprellt() async throws {
        let ablage = try ordner("bearbeiten")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, v) = try await speicher(ablage)
        await s.sicherung.entprelltJetzt()
        s.jetztSichern()
        s.takt = Stelluhr()
        s.aendern(Schrittname.titelAendern) { p in
            if let i = p.eintraege.firstIndex(where: { $0.id == v }) { p.eintraege[i].titel = "Gespräch" }
        }
        #expect(s.planung?.eintraege.first { $0.id == v }?.titel == "Gespräch")
        let zweiter = await neustart(ablage)
        #expect(zweiter.planung?.eintraege.first { $0.id == v }?.titel == "Elterngespräch",
                "die Planung wurde nicht sofort geschrieben — nur Gehen und Zurückkommen sichern sofort")
    }
}
