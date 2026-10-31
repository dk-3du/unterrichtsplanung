// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

// ── B109 (v87, AY7, E887 a): „Übernehmen“ im Blatt sichert eine geänderte Planung sofort ──
// „Übernehmen“ schreibt die Jahresdatei sofort; die Planung, die ein geänderter Termin mitzieht, wurde bis 2.2.1 entprellt
// (700 ms). Endete die App dazwischen ohne Beenden, las der nächste Start eine neue Jahresdatei neben einer alten Planung —
// in AY0 an einer Kopie nachgestellt (rot). Die Stelluhr hält das Entprellen an; so steht auf der Platte, was ein Absturz in
// der Lücke hinterließe.

import Foundation
import Testing

@testable import Unterrichtsplanung

private typealias Tag = Unterrichtsplanung.Tag

@Suite("B109: Übernehmen im Blatt sichert die Planung sofort (E887 a)", .serialized)
@MainActor
struct UebernehmenSichertPlanungPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand, "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory.appending(component: "b109-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    @Test("B109: Termin im Blatt geändert und übernommen, die Entprellung angehalten — nach dem Neustart tragen Termin und Vorhaben die Änderung")
    func b109() async throws {
        let ablage = try ordner("neustart")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try await speicher(ablage)
        await s.sicherung.entprelltJetzt()
        s.jetztSichern()
        let uhr = Stelluhr()
        s.takt = uhr
        let bestand = try #require(s.lernende.bestand)
        let geaendert = bestand.mitAnliegen(t, titel: "Gespräch", datum: "2026-09-08", frist: "", notiz: "", uhrzeit: "09:30",
                                            jetzt: bestand.geaendert)
        #expect(s.lernendenUebernehmen(geaendert) == nil)
        #expect(s.planung?.eintraege.first { $0.id == v }?.titel == "Gespräch", "in der Sitzung folgt das Vorhaben")

        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablage))
        zweiter.nachwahlProbe = true
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        let t2 = zweiter.lernende.bestand?.anliegen.first { $0.id == t }
        let v2 = zweiter.planung?.eintraege.first { $0.id == v }
        #expect(t2?.titel == "Gespräch" && v2?.titel == "Gespräch", "B109: die Änderung im Blatt übersteht den Neustart")
    }
}
