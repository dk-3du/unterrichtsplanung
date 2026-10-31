// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Lerngruppen ohne Mitglieder im Wechsel am Speicher (v86, AX2: E699, E708, E763–E765) ──
// Was die Blätter mitgeben, kommt im Wechsel an: „Neue Planung“ und ⌘O reichen die Menge der Lerngruppen ohne Mitglieder bis
// zum neuen Jahr durch. Die Mitteilung an „Mathe-Förder“ bleibt im Archiv (E763), die Maßnahme kommt mit Anna, ohne
// Lerngruppe (E764); an der Zeile „Mathe-Förder“, deren Lerngruppe ohne Mitglieder kommt, lassen alle Tische los — die
// Namen und die Tischordnung bleiben, still wie beim Wechsel (E765).

@Suite("Lerngruppen ohne Mitglieder im Wechsel: Durchreichen, Anliegen, Sitzplan (E699, E763–E765)")
@MainActor
struct OhneMitgliederWechselPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private static let stempel = "2026-10-03T08:00:00.000Z"

    private func ordner(_ name: String) throws -> URL {
        let wurzel = try #require(ProcessInfo.processInfo.environment["PLANUNGSORDNER"])
        let ziel = URL(filePath: wurzel).appending(component: "ohne-mitglieder-\(name)-\(UUID().uuidString)",
                                                   directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// „6a · Mathematik“ und „Mathe-Förder · Mathematik“.
    private func planung() throws -> Planung {
        Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                     klassen: Standardkurse.aufbauen([("6a", "Mathematik"), ("Mathe-Förder", "Mathematik")]), fachfarben: [:])
    }

    /// „6a“ (Anna, Ben) und „Mathe-Förder“ (Anna, Cem); offen: die Mitteilung „Förderplan unterschreiben“ an
    /// „Mathe-Förder“ für Anna und Cem, die Maßnahme „Übungsheft nachreichen“ aus „Mathe-Förder“ für Anna.
    private func bestand(_ p: Planung) -> Lernendenbestand {
        let s = Self.stempel
        func person(_ id: String, _ vor: String, _ nach: String) -> Lernender {
            Lernender(id: id, vorname: vor, nachname: nach, angelegt: s, geaendert: s, archiviert: "")
        }
        func gruppe(_ id: String, _ name: String, _ mitglieder: [String], _ zeile: Int) -> Lerngruppe {
            Lerngruppe(id: id, name: name, art: .klasse, mitglieder: mitglieder,
                       zeilen: [Zeilenbindung(planung: p.erstellt, klasseId: p.klassen[zeile].id)],
                       skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")
        }
        var b = Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: s)
        b.lernende = [person("l-1", "Anna", "Abel"), person("l-2", "Ben", "Bauer"), person("l-3", "Cem", "Çelik")]
        b.lerngruppen = [gruppe("g-6a", "6a", ["l-1", "l-2"], 0), gruppe("g-mf", "Mathe-Förder", ["l-1", "l-3"], 1)]
        b.anliegen = [
            Anliegen(id: "m-1", art: .mitteilung, titel: "Förderplan unterschreiben", lerngruppe: "g-mf",
                     betroffene: ["l-1", "l-3"], datum: "2026-10-01", frist: "", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "m-2", art: .massnahme, titel: "Übungsheft nachreichen", lerngruppe: "g-mf", betroffene: ["l-1"],
                     datum: "2026-10-02", frist: "2026-10-16", notiz: "", angelegt: s, geaendert: s),
        ]
        return b
    }

    /// Eingeschaltet, mit Jahresdatei und je einem Sitzplan an beiden Zeilen.
    private func speicher(_ ablage: URL) async throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let p = try #require(s.planung)
        #expect(s.lernende.setzen(bestand(p)) == nil)
        #expect(s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: p.klassen[0].id, lernende: [
            .init(name: "Anna Abel", lernender: "l-1"), .init(name: "Ben Bauer", lernender: "l-2")]), fuer: p.klassen[0].id) == nil)
        #expect(s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: p.klassen[1].id, lernende: [
            .init(name: "Anna Abel", lernender: "l-1"), .init(name: "Cem Çelik", lernender: "l-3")]), fuer: p.klassen[1].id) == nil)
        return s
    }

    @Test("„Neue Planung“ mit „Mathe-Förder“ ohne Mitglieder: leer im neuen Jahr, die Mitteilung im Archiv, die Maßnahme mit Anna ohne Lerngruppe, die Tische der Zeile gelöst")
    func neuePlanungOhneMitglieder() async throws {
        let s = try await speicher(try ordner("neu"))
        let alt = try #require(s.planung)
        let vorher = Set(s.meldungen.map(\.id))
        s.neuePlanung(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                      klassen: [], ersterSchultag: nil,
                      uebernahme: alt.klassen.map { Planung.Uebernahmewunsch(klasse: $0, mitVorhaben: false) },
                      lerngruppen: ["g-6a", "g-mf"], ohneMitglieder: ["g-mf"])
        let neu = try #require(s.planung)
        #expect(neu.erstellt != alt.erstellt, "gewechselt")
        let jahresdatei = try #require(s.lernende.bestand)
        let mf = try #require(jahresdatei.lerngruppen.first { $0.id == "g-mf" })
        #expect(mf.mitglieder.isEmpty, "„Mathe-Förder“ kommt ohne Mitglieder (E699)")
        #expect(jahresdatei.lernende.map(\.id) == ["l-1", "l-2"], "Anna und Ben über die 6a; Cem bleibt im Archiv")
        #expect(!jahresdatei.anliegen.contains { $0.id == "m-1" }, "die Mitteilung an „Mathe-Förder“ bleibt im Archiv (E763)")
        let massnahme = jahresdatei.anliegen.first { $0.id == "m-2" }
        #expect(massnahme?.lerngruppe == "" && massnahme?.betroffene == ["l-1"],
                "die Maßnahme kommt mit Anna, ohne Lerngruppe (E764)")
        let zeileMF = try #require(mf.zeilen.first?.klasseId)
        let zeile6a = try #require(jahresdatei.lerngruppen.first { $0.id == "g-6a" }?.zeilen.first?.klasseId)
        let planMF = try #require(s.sitzplaene.plan(fuer: zeileMF))
        #expect(planMF.tische.map(\.lernender) == ["", ""], "an „Mathe-Förder“ lässt auch Annas Tisch los (E765)")
        #expect(planMF.tische.map(\.name) == ["Anna Abel", "Cem Çelik"], "die Namen bleiben (E304)")
        #expect(s.sitzplaene.plan(fuer: zeile6a)?.tische.map(\.lernender) == ["l-1", "l-2"], "an der 6a bleibt alles")
        let gemeldet = s.meldungen.filter { !vorher.contains($0.id) && $0.text.contains("Zuordnung") }
        #expect(gemeldet.isEmpty, "still wie beim Wechsel")
    }

    @Test("⌘O ins nächste Schuljahr mit „Mathe-Förder“ ohne Mitglieder: Die Menge kommt im Wechsel an, die Tische der Zeile lassen los")
    func oeffnenOhneMitglieder() async throws {
        let s = try await speicher(try ordner("oeffnen"))
        let alt = try #require(s.planung)
        // Die Zeile „Mathe-Förder“ unter derselben Kennung — ihr Plan übersteht das Aufräumen; dazu „7a · Mathematik“.
        let neu7a = Standardkurse.aufbauen([("7a", "Mathematik")])[0]
        var fremd = Planung.leer(titel: "Fremd 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                                 klassen: [neu7a, alt.klassen[1]], fachfarben: [:])
        fremd.erstellt = "2027-07-01T10:00:00.000Z"
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "/tmp/fremd.json"))
        _ = try #require(s.schuljahrwechsel)
        s.schuljahrOeffnen(gruppen: ["g-6a", "g-mf"],
                           ziele: ["g-6a": Gruppenziel(name: "7a", zeilen: [neu7a.id]),
                                   "g-mf": Gruppenziel(name: "Mathe-Förder", zeilen: [alt.klassen[1].id])],
                           ohneMitglieder: ["g-mf"])
        #expect(s.planung?.erstellt == fremd.erstellt, "gewechselt")
        let jahresdatei = try #require(s.lernende.bestand)
        #expect(jahresdatei.lerngruppen.first { $0.id == "g-mf" }?.mitglieder.isEmpty == true, "ohne Mitglieder (E699)")
        #expect(jahresdatei.lernende.map(\.id) == ["l-1", "l-2"], "Cem bleibt im Archiv")
        #expect(s.sitzplaene.plan(fuer: alt.klassen[1].id)?.tische.map(\.lernender) == ["", ""],
                "an „Mathe-Förder“ lässt auch Annas Tisch los (E765)")
    }
}
