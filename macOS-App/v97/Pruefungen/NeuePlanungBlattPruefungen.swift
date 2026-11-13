// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Lernende aus IServ am Blatt „Neue Planung“ (v84, AT7: D, E351, E613, E616, E617) ──
// Was das Blatt mit einer übernommenen Lesung tut, bevor etwas geschrieben wird: die Klassen der Datei, die Zeile nach
// dem Bogen, die Klassen ins Feld — gleichnamige nicht doppelt — und der Hinweis auf Klassen ohne Zeile. Dazu am
// Speicher der Schuljahreswechsel mit Hochstufung und Import zugleich: Die hochgestufte „5a“ und die Klasse 5a der
// Datei ergeben eine Lerngruppe, nicht zwei.

@Suite("Neue Planung: Lernende aus IServ am Blatt — Klassen ins Feld, Zeile, Hinweis; mit Hochstufung")
@MainActor
struct NeuePlanungBlattPruefungen {

    private let passphrase = "Ein Satz, den man behält"
    private static let stempel = "2026-10-14T08:00:00.000Z"

    /// Je Person Vorname, Nachname, Klasse — in der Folge der Datei, ab Zeile 2 (nach der Kopfzeile).
    private func lesung(_ personen: [(String, String, String)]) -> IServImport.Lesung {
        IServImport.Lesung(zeilen: personen.enumerated().map { stelle, p in
            IServImport.Zeile(nummer: stelle + 2, vorname: p.0, nachname: p.1, klasse: p.2)
        })
    }

    @Test("Die Klassen der Datei: je Name einmal, Groß/Klein unerheblich, ohne leere, in natürlicher Ordnung")
    func klassen() {
        let l = lesung([("Ada", "Abel", "10a"), ("Ben", "Brandt", "5a"), ("Cem", "Cetin", "5A"), ("Dana", "Dorn", ""),
                        ("Eli", "Ernst", "6c")])
        #expect(NeuePlanungDialog.klassen(l) == ["5a", "6c", "10a"])
    }

    @Test("Die Zeile nach dem Bogen zählt nur Personen mit Klasse; Einzahl bei einer (Z-AT7-04)")
    func importzeile() {
        #expect(NeuePlanungDialog.importzeile(lesung([("Ada", "Abel", "5a"), ("Ben", "Brandt", "5b"), ("Cem", "Cetin", "")]),
                                              datei: "export.csv")
                == "Aus „export.csv“: 2 Personen in 2 Klassen — je Klasse eine Zeile und eine Lerngruppe.")
        #expect(NeuePlanungDialog.importzeile(lesung([("Ada", "Abel", "5a")]), datei: "a.csv")
                == "Aus „a.csv“: 1 Person in 1 Klasse — je Klasse eine Zeile und eine Lerngruppe.")
    }

    @Test("Klassen ins Feld (E351): ans Ende, in der Ordnung der Klassen, Leerzeilen am Ende weg, gleichnamige nicht doppelt")
    func mitKlassen() {
        let l = lesung([("Ada", "Abel", "6c"), ("Ben", "Brandt", "5a"), ("Cem", "Cetin", "5b")])
        #expect(NeuePlanungDialog.mitKlassen("", l) == "5a\n5b\n6c")
        #expect(NeuePlanungDialog.mitKlassen("7b - Chemie\n\n", l) == "7b - Chemie\n5a\n5b\n6c")
        // „5a - Mathematik“ trägt den Namen 5a, „5B“ ist 5b — beide stehen schon.
        #expect(NeuePlanungDialog.mitKlassen("5a - Mathematik\n5B", l) == "5a - Mathematik\n5B\n6c")
        // Alles schon da: Das Feld bleibt, wie es war.
        #expect(NeuePlanungDialog.mitKlassen("5a\n5b\n6c\n", l) == "5a\n5b\n6c\n")
    }

    @Test("Eine Klasse mit „ - “ im Namen kommt nicht doppelt ins Feld (Z-AT7-05)")
    func klasseMitStrich() {
        let l = lesung([("Ada", "Abel", "Q1 - LK"), ("Ben", "Brandt", "Q2")])
        #expect(NeuePlanungDialog.mitKlassen("Q1 - LK", l) == "Q1 - LK\nQ2")
        // Der Hinweis nennt sie trotzdem: Gelesen heißt die Zeile „Q1“ mit Fach „LK“ (E622).
        #expect(NeuePlanungDialog.ohneZeile(l, zeilennamen: ["Q1", "Q2"]) == ["Q1 - LK"])
    }

    @Test("Eine übernommene Unterrichtszeile gleichen Namens zählt im Doppelschutz (E623)")
    func uebernommeneZeile() {
        let l = lesung([("Ada", "Abel", "5a"), ("Ben", "Brandt", "6c")])
        #expect(NeuePlanungDialog.mitKlassen("", l, uebernommen: ["5a"]) == "6c")
        #expect(NeuePlanungDialog.mitKlassen("7b", l, uebernommen: [" 5A "]) == "7b\n6c")
    }

    @Test("Die Zeilen des Hinweises: eingetippt bis zur Grenze, übernommen ohne Sonderzeilen (Z-AT7N-03)")
    func unterrichtszeilen() {
        let eingaben = (1...(Kennwerte.maxKlassen + 1)).map { (name: "K\($0)", fach: "") }
        let alt = [Klasse(id: "k-1", name: "5a", fach: "Biologie", notiz: "", farbe: 0, farbeManuell: false, art: .unterricht),
                   Klasse.sonderzeile(.klassenleitung)]
        let namen = NeuePlanungDialog.unterrichtszeilen(eingaben: eingaben, uebernommene: alt)
        #expect(namen.count == Kennwerte.maxKlassen + 1 && namen.last == "5a" && !namen.contains("K\(Kennwerte.maxKlassen + 1)"))
    }

    @Test("Der Knopf „Aus IServ importieren …“: grau ohne Verschlüsselung, bei Sperre und nach einem Import (E350, E612, E614)")
    func importknopf() {
        let ohne = NeuePlanungDialog.importknopf(moeglich: false, sperrhinweis: "x", uebernommen: true)
        #expect(!ohne.aktiv && ohne.hilfe.hasPrefix("Nur mit eingeschalteter Verschlüsselung"))
        let gesperrt = NeuePlanungDialog.importknopf(moeglich: true, sperrhinweis: "Die Lernendenverwaltung ist gesperrt.",
                                                     uebernommen: true)
        #expect(!gesperrt.aktiv && gesperrt.hilfe == "Die Lernendenverwaltung ist gesperrt.")
        let zweiter = NeuePlanungDialog.importknopf(moeglich: true, sperrhinweis: nil, uebernommen: true)
        #expect(!zweiter.aktiv && zweiter.hilfe.hasPrefix("Schon übernommen"))
        #expect(NeuePlanungDialog.importknopf(moeglich: true, sperrhinweis: nil, uebernommen: false).aktiv)
    }

    @Test("Ein Baustein als Satzanfang: der erste Buchstabe groß, sonst nichts (E615, E619)")
    func satzanfang() {
        #expect("die Platte ist voll".satzanfang == "Die Platte ist voll")
        #expect("über der Grenze".satzanfang == "Über der Grenze")
        #expect("„planung.json“ fehlt".satzanfang == "„planung.json“ fehlt")
        #expect("Schon groß".satzanfang == "Schon groß" && "".satzanfang == "")
    }

    @Test("Klassen ohne Unterrichtszeile gleichen Namens (E613) — verglichen wie die Bindung nach Namen")
    func ohneZeile() {
        let l = lesung([("Ada", "Abel", "5a"), ("Ben", "Brandt", "6c"), ("Cem", "Cetin", "7b")])
        #expect(NeuePlanungDialog.ohneZeile(l, zeilennamen: [" 5A ", "7b"]) == ["6c"])
        #expect(NeuePlanungDialog.ohneZeile(l, zeilennamen: []) == ["5a", "6c", "7b"])
        #expect(NeuePlanungDialog.ohneZeile(l, zeilennamen: ["5a", "6c", "7b", "8a"]).isEmpty)
    }

    @Test("Der Hinweis (E617): mit Namen, Einzahl, nach sechs gekürzt; ohne Klassen keiner")
    func hinweis() {
        #expect(NeuePlanungDialog.ohneZeileHinweis([]) == nil)
        #expect(NeuePlanungDialog.ohneZeileHinweis(["6c"]) == "Ohne Zeile im Feld: 6c — diese Lerngruppe entsteht ohne Zeile.")
        #expect(NeuePlanungDialog.ohneZeileHinweis(["6c", "7b"])
                == "Ohne Zeile im Feld: 6c, 7b — diese Lerngruppen entstehen ohne Zeile.")
        let viele = ["6c", "7b", "8a", "8b", "9c", "10a"] + (1...30).map { "K\($0)" }
        #expect(NeuePlanungDialog.ohneZeileHinweis(Array(viele.prefix(6)))
                == "Ohne Zeile im Feld: 6c, 7b, 8a, 8b, 9c, 10a — diese Lerngruppen entstehen ohne Zeile.")
        #expect(NeuePlanungDialog.ohneZeileHinweis(viele)
                == "Ohne Zeile im Feld: 6c, 7b, 8a, 8b, 9c, 10a und 30 weitere — diese Lerngruppen entstehen ohne Zeile.")
        #expect(NeuePlanungDialog.ohneZeileHinweis(Array(viele.prefix(7)))
                == "Ohne Zeile im Feld: 6c, 7b, 8a, 8b, 9c, 10a und 1 weitere — diese Lerngruppen entstehen ohne Zeile.")
    }

    @Test("Schuljahreswechsel mit Hochstufung und Import zugleich: „4a“ wird „5a“ an Zeile 5a, die Klasse 5a der Datei trifft sie — eine aktive „5a“ (Z-AT7-03)")
    func hochstufungUndImport() async throws {
        try #require(Ablage.istPruefstand, "die Prüfung braucht einen eigenen Ablageort (PLANUNGSORDNER)")
        let ordner = URL.temporaryDirectory
            .appending(component: "neueplanung-blatt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                                 basis: "", klassen: Standardkurse.aufbauen([("4a", "Biologie")]), fachfarben: [:])
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let alt = try #require(s.planung)
        let st = Self.stempel
        var b = Lernendenbestand.leer(planung: alt.erstellt, schuljahr: "2026/27", jetzt: st)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: st, geaendert: st, archiviert: "")]
        b.lerngruppen = [Lerngruppe(id: "g-1", name: "4a", art: .klasse, mitglieder: ["l-1"],
                                    zeilen: [Zeilenbindung(planung: alt.erstellt, klasseId: alt.klassen[0].id)],
                                    skalen: [:], halbjahreswechsel: "", geaendert: st, archiviert: "")]
        #expect(s.lernende.setzen(b) == nil)

        let eingetippt = Standardkurse.aufbauen([("5a", "Biologie")])
        s.neuePlanung(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                      klassen: eingetippt, ersterSchultag: nil, uebernahme: [], lerngruppen: ["g-1"],
                      ziele: ["g-1": Gruppenwahl(name: "5a", zeilen: [.kennung(eingetippt[0].id)])], ohneMitglieder: [],
                      iserv: (lesung([("Ben", "Brandt", "5a"), ("Cem", "Cetin", "5a")]), .jeKlasse))
        let neu = try #require(s.planung)
        let jahresdatei = try #require(s.lernende.bestand)
        let aktiv = jahresdatei.lerngruppen.filter { $0.archiviert.isEmpty && $0.name.lowercased() == "5a" }
        #expect(aktiv.count == 1, "\(jahresdatei.lerngruppen.map(\.beschriftung))")
        #expect(aktiv.first?.id == "g-1" && aktiv.first?.mitglieder.count == 3)
        #expect(aktiv.first?.zeilen == [Zeilenbindung(planung: neu.erstellt, klasseId: eingetippt[0].id)])
        #expect(s.meldungen.contains { $0.text == "IServ-Import: 2 neu · 0 unverändert · 0 übergangen." },
                "\(s.meldungen.map(\.text))")
    }

    // ── Wer beim Wechsel mit Import mitkommt (E657, Z-AT9M-11, -12) ──

    @Test("Wer mitkommt, wie das Blatt rechnet (E657, Z-AT9M-12): eine Zeile oder mit dem neuen Namen im Import — ohne Import nur die Zeilen")
    func mitkommendAmBlatt() {
        let gruppen = [lerngruppe("g-1", "6a"), lerngruppe("g-2", "6b"), lerngruppe("g-3", "AG")]
        let namen = ["g-1": "7a", "g-2": "7b", "g-3": "AG"]
        let zuteilung = ["g-1": ["e:7a"]]
        #expect(NeuePlanungDialog.mitkommend(gruppen, namen: namen, zuteilung: zuteilung, lesung: nil) == ["g-1"])
        #expect(NeuePlanungDialog.mitkommend(gruppen, namen: namen, zuteilung: zuteilung,
                                             lesung: lesung([("Ben", "Brandt", "7b"), ("Ida", "Iser", "9c")])) == ["g-1", "g-2"],
                "„6b“ heißt „7b“ und steht in der Datei; die „AG“ nicht")
    }

    @Test("Eine Lerngruppe ohne Zeile, aber im Import erkannt, kommt mit, und der Import trifft sie — eine aktive „7a“ mit allen Personen (E657, Z-AT9M-12)")
    func importOhneZeile() async throws {
        let (s, ordner) = try await speicherMit([lerngruppe("g-1", "6a", mitglieder: ["l-1", "l-2"])])
        defer { try? FileManager.default.removeItem(at: ordner) }
        let bestand = try await wechselMitImport(s, eingaben: [("8b", "Musik")],
                                                 lesung: lesung([("Anna", "Abel", "7a"), ("Cem", "Cetin", "7a")]))
        let aktiv = bestand.lerngruppen.filter { $0.archiviert.isEmpty && $0.name.lowercased() == "7a" }
        #expect(aktiv.map(\.id) == ["g-1"] && aktiv.first?.mitglieder.count == 3, "\(bestand.lerngruppen.map(\.beschriftung))")
        #expect(aktiv.first?.zeilen.isEmpty == true, "ohne Zeile „7a“ im Feld bleibt sie ungebunden")
    }

    @Test("Zwei Lerngruppen „6a“, wie die App sie bisher zulässt: Keine gilt als im Import erkannt (Z-AT9M-11); beide kommen über die Zeile „7a“ mit (E675); der Import trifft die erste und legt keine dritte an (V10)")
    func zweiLerngruppenGleichenNamens() async throws {
        // Vorgesehen ist eine Lerngruppe „6a“ (E656); zwei lässt die App bisher zu (AT9a).
        let (s, ordner) = try await speicherMit([lerngruppe("g-1", "6a", mitglieder: ["l-1", "l-2"]),
                                                 lerngruppe("g-2", "6a", mitglieder: ["l-1", "l-2"])])
        defer { try? FileManager.default.removeItem(at: ordner) }
        let bestand = try await wechselMitImport(s, eingaben: [("7a", "")],
                                                 lesung: lesung([("Anna", "Abel", "7a"), ("Cem", "Cetin", "7a")]))
        let aktiv = bestand.lerngruppen.filter { $0.archiviert.isEmpty && $0.name.lowercased() == "7a" }
        #expect(aktiv.map(\.id) == ["g-1", "g-2"], "\(bestand.lerngruppen.map(\.beschriftung))")
        #expect(aktiv.map(\.mitglieder.count) == [3, 2], "Cem Cetin kommt in die erste „7a“")
        #expect(aktiv.allSatisfy { $0.zeilen.count == 1 }, "beide tragen die Zeile „7a“")
    }

    private func lerngruppe(_ id: String, _ name: String, mitglieder: [String] = []) -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: mitglieder, zeilen: [], skalen: [:],
                   halbjahreswechsel: "", geaendert: Self.stempel, archiviert: "")
    }

    /// Eine verschlüsselte Planung 2026/27 mit der Zeile „6a“ und den Lerngruppen daran; dazu Anna Abel und Bo Berg.
    private func speicherMit(_ gruppen: [Lerngruppe]) async throws -> (Planungsspeicher, URL) {
        try #require(Ablage.istPruefstand, "die Prüfung braucht einen eigenen Ablageort (PLANUNGSORDNER)")
        let ordner = URL.temporaryDirectory
            .appending(component: "neueplanung-blatt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        // Bricht der Aufbau ab, räumt er selbst — das `defer` des Aufrufers greift erst danach (Z-AT9M-21).
        var fertig = false
        defer { if !fertig { try? FileManager.default.removeItem(at: ordner) } }
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                                 basis: "", klassen: Standardkurse.aufbauen([("6a", "")]), fachfarben: [:])
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let alt = try #require(s.planung)
        let st = Self.stempel
        var b = Lernendenbestand.leer(planung: alt.erstellt, schuljahr: "2026/27", jetzt: st)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: st, geaendert: st, archiviert: ""),
                      Lernender(id: "l-2", vorname: "Bo", nachname: "Berg", angelegt: st, geaendert: st, archiviert: "")]
        b.lerngruppen = gruppen.map { g in
            var g = g
            g.zeilen = [Zeilenbindung(planung: alt.erstellt, klasseId: alt.klassen[0].id)]
            return g
        }
        #expect(s.lernende.setzen(b) == nil)
        fertig = true
        return (s, ordner)
    }

    /// „Neue Planung“ für 2027/28 mit Hochstufung und Import, gerechnet wie das Blatt: Zuteilung, wer mitkommt, Ziele.
    private func wechselMitImport(_ s: Planungsspeicher, eingaben: [(name: String, fach: String)],
                                  lesung: IServImport.Lesung) async throws -> Lernendenbestand {
        let angebot = NeuePlanungDialog.zeilenangebot(eingaben: eingaben, sonderzeilen: [], uebernommene: [])
        let gruppen = s.lerngruppenZurWahl
        let w = Hochstufungswahl()
        let namen = Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, w.suchname($0, stufen: 1)) })
        let zuteilung = Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: angebot, gewaehlt: [:])
        let mitkommend = NeuePlanungDialog.mitkommend(gruppen, namen: namen, zuteilung: zuteilung, lesung: lesung)
        let klassen = Standardkurse.aufbauen(eingaben)
        let ziele = Dictionary(uniqueKeysWithValues: gruppen.filter { mitkommend.contains($0.id) }.map { g in
            (g.id, Gruppenwahl(name: namen[g.id] ?? g.name, zeilen: (zuteilung[g.id] ?? []).map {
                NeuePlanungDialog.zielzeile($0, eingaben: eingaben, klassen: klassen)
            }.filter { $0 != .keine }))
        })
        s.neuePlanung(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                      klassen: klassen, ersterSchultag: nil, uebernahme: [], lerngruppen: mitkommend, ziele: ziele,
                      ohneMitglieder: [], iserv: (lesung, .jeKlasse))
        return try #require(s.lernende.bestand)
    }
}
