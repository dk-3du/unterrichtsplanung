// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Kopf der Lerngruppe, Zeilen wählen, Zusammenführen (v84, AT9a-2; E667, E669, E670, E672) ──
// Der Kopf einer Lerngruppe im Blatt „Lernende“ nennt die verknüpften Zeilen; „Zeilen wählen …“ legt sie mit Kästchen fest und
// nimmt keiner anderen Lerngruppe etwas (E670). Zwei gleichnamige lassen sich zusammenführen: Mitglieder, Zeilen, Mitteilungen
// und Maßnahmen gehen auf die eine über, die andere wird archiviert — mit ihrer Mitgliederliste, ohne Zeilen und Anliegen.

@Suite("Kopf der Lerngruppe: verknüpfte Zeilen, Zeilen wählen, Zusammenführen")
struct LerngruppenkopfPruefungen {

    private static let stempel = "2026-10-15T19:00:00.000Z"
    private static let fremd = Zeilenbindung(planung: "2025-08-11T09:00:00.000Z", klasseId: "k-alt")

    /// „6a · Biologie“, „6a · Chemie“, „7b · Biologie“, dann Klassenleitung (Klasse „6a“), Weiteres, Vertretungen.
    private static func planung() throws -> Planung {
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.fach = "6a"
        let klassen = Standardkurse.aufbauen([("6a", "Biologie"), ("6a", "Chemie"), ("7b", "Biologie")])
            + [leitung, Klasse.sonderzeile(.weiteres), Klasse.sonderzeile(.vertretungen)]
        return Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                            klassen: klassen, fachfarben: [:])
    }

    private static func z(_ p: Planung, _ stelle: Int) -> Zeilenbindung {
        Zeilenbindung(planung: p.erstellt, klasseId: p.klassen[stelle].id)
    }

    private static func gruppe(_ id: String, _ name: String, mitglieder: [String] = [], zeilen: [Zeilenbindung] = [],
                               archiviert: String = "") -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: mitglieder, zeilen: zeilen, skalen: [:],
                   halbjahreswechsel: "", geaendert: stempel, archiviert: archiviert)
    }

    private static func bestand(_ planung: String, _ gruppen: [Lerngruppe], personen: Int = 4) -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: planung, schuljahr: "2026/27", jetzt: stempel)
        let s = stempel
        b.lernende = (1...personen).map { Lernender(id: "l-\($0)", vorname: "V\($0)", nachname: "N\($0)", angelegt: s, geaendert: s,
                                                    archiviert: "") }
        b.lerngruppen = gruppen
        return b
    }

    private static func anliegen(_ id: String, _ art: Anliegenart, gruppe: String) -> Anliegen {
        Anliegen(id: id, art: art, titel: "T " + id, lerngruppe: gruppe, betroffene: ["l-3"], datum: "2026-10-20", frist: "",
                 notiz: "", angelegt: stempel, geaendert: stempel)
    }

    // ── Kopf ──────────────────────────────────────────────────────────────

    @Test("E669: Der Kopf nennt die verknüpften Zeilen in ihrer Folge; ohne: „Mit keiner Zeile verknüpft“; Zeilen, die diese Planung nicht kennt, als Zahl")
    func verknuepft() throws {
        let p = try Self.planung()
        let titel = Lernendenblatt.zeilentitel(p)
        #expect(Lernendenblatt.verknuepft(Self.gruppe("g-1", "6a", zeilen: [Self.z(p, 1), Self.z(p, 0), Self.z(p, 3)]),
                                          zeilentitel: titel)
                == "Verknüpft mit: 6a · Chemie, 6a · Biologie, Klassenleitung · 6a")
        #expect(Lernendenblatt.verknuepft(Self.gruppe("g-2", "6a"), zeilentitel: titel) == "Mit keiner Zeile verknüpft")
        #expect(Lernendenblatt.verknuepft(Self.gruppe("g-3", "6a", zeilen: [Self.z(p, 0), Self.fremd]), zeilentitel: titel)
                == "Verknüpft mit: 6a · Biologie und 1 Zeile außerhalb dieser Planung")
        let zweiFremde = [Self.fremd, Zeilenbindung(planung: Self.fremd.planung, klasseId: "k-alt-2")]
        #expect(Lernendenblatt.verknuepft(Self.gruppe("g-4", "6a", zeilen: zweiFremde), zeilentitel: titel)
                == "Verknüpft mit 2 Zeilen außerhalb dieser Planung")
        #expect(Lernendenblatt.verknuepft(Self.gruppe("g-5", "6a", zeilen: [Self.z(p, 0)]), zeilentitel: [:])
                == "Verknüpft mit 1 Zeile außerhalb dieser Planung", "ohne geöffnete Planung")
    }

    @Test("E683: Verknüpfungen an entfernten Zeilen dieser Planung heißen „entfernte Zeile“, Zeilen anderer Planungen weiter „außerhalb dieser Planung“")
    func entfernteZeile() throws {
        let p = try Self.planung()
        let titel = Lernendenblatt.zeilentitel(p)
        let weg = Zeilenbindung(planung: p.erstellt, klasseId: "k-entfernt")
        let weg2 = Zeilenbindung(planung: p.erstellt, klasseId: "k-entfernt-2")
        #expect(Lernendenblatt.verknuepft(Self.gruppe("g-1", "6a", zeilen: [Self.z(p, 0), weg]), zeilentitel: titel,
                                          planung: p.erstellt)
                == "Verknüpft mit: 6a · Biologie und 1 entfernte Zeile")
        #expect(Lernendenblatt.verknuepft(Self.gruppe("g-2", "6a", zeilen: [Self.z(p, 0), weg, Self.fremd]), zeilentitel: titel,
                                          planung: p.erstellt)
                == "Verknüpft mit: 6a · Biologie, 1 entfernte Zeile und 1 Zeile außerhalb dieser Planung")
        #expect(Lernendenblatt.verknuepft(Self.gruppe("g-3", "6a", zeilen: [weg, weg2]), zeilentitel: titel, planung: p.erstellt)
                == "Verknüpft mit: 2 entfernte Zeilen")
        #expect(Lernendenblatt.verknuepft(Self.gruppe("g-4", "6a", zeilen: [Self.fremd]), zeilentitel: titel, planung: p.erstellt)
                == "Verknüpft mit 1 Zeile außerhalb dieser Planung", "wie bisher")
    }

    @Test("Z-AT15N-09: Das Menü „Zusammenführen mit“ nennt eine Lerngruppe ohne Zeile dieser Planung wie der Kopf (E683)")
    func ersteZeileImMenue() throws {
        let p = try Self.planung()
        let titel = Lernendenblatt.zeilentitel(p)
        let weg = Zeilenbindung(planung: p.erstellt, klasseId: "k-entfernt")
        func erste(_ zeilen: [Zeilenbindung]) -> String {
            Lernendenblatt.ersteZeile(Self.gruppe("g", "6a", zeilen: zeilen), zeilentitel: titel, planung: p.erstellt)
        }
        #expect(erste([weg, Self.z(p, 1)]) == "6a · Chemie")
        #expect(erste([]) == "keine Zeile")
        #expect(erste([weg]) == "1 entfernte Zeile")
        #expect(erste([Self.fremd]) == "1 Zeile außerhalb dieser Planung")
        #expect(erste([weg, Self.fremd]) == "1 entfernte Zeile und 1 Zeile außerhalb dieser Planung")
    }

    @Test("Z-AT15M-01, -02, Z-AT15L-02, Z-AT15K-01, -02: Das Suchfeld wird nur geleert, wenn es die Lerngruppe verdeckt — auch für eine eben angelegte")
    func sucheFuerWahl() throws {
        let p = try Self.planung()
        let titel = Lernendenblatt.zeilentitel(p)
        let b = Self.bestand(p.erstellt, [Self.gruppe("g-1", "6a"), Self.gruppe("g-2", "Bio-AG"),
                                          Self.gruppe("g-z", "Chor", zeilen: [Self.z(p, 1)])])
        #expect(Lernendenblatt.sucheFuerWahl("g-1", in: b, suche: "Bio", zeilentitel: titel) == "", "verdeckt — geleert")
        #expect(Lernendenblatt.sucheFuerWahl("g-1", in: b, suche: "6", zeilentitel: titel) == "6", "sichtbar — bleibt")
        #expect(Lernendenblatt.sucheFuerWahl("g-z", in: b, suche: "Chemie", zeilentitel: titel) == "Chemie",
                "über die verknüpfte Zeile „6a · Chemie“ sichtbar — bleibt (E671)")
        #expect(Lernendenblatt.sucheFuerWahl(nil, in: b, suche: "Bio", zeilentitel: titel) == "Bio", "nichts gewählt")
        // Eben angelegt: Die neue entsteht über `mitNeuerGruppe` wie im Blatt. Geprüft ist nur die reine Funktion — nicht, dass
        // `gruppeAnlegenOhneFrage` erst den Entwurf ändert und dann `suchfeldFuerWahl` ruft, und nicht, dass `suchfeldFuerWahl` die
        // Zeilentitel der Planung weiterreicht (Z-AT15J-01).
        let neu = try #require(b.mitNeuerGruppe(name: "6c", art: .klasse, jetzt: Self.stempel))
        #expect(Lernendenblatt.sucheFuerWahl(neu.id, in: neu.bestand, suche: "6", zeilentitel: titel) == "6",
                "eben angelegt, sichtbar — bleibt")
        #expect(Lernendenblatt.sucheFuerWahl(neu.id, in: neu.bestand, suche: "Inf", zeilentitel: titel) == "",
                "eben angelegt, verdeckt — geleert")
        #expect(Lernendenblatt.sucheFuerWahl(neu.id, in: b, suche: "6", zeilentitel: titel) == "",
                "im Entwurf vor dem Anlegen fehlt sie — die Funktion braucht den Entwurf danach")
    }

    @Test("E685: Fällt die gewählte Lerngruppe aus dem Suchfeld der Liste, ist rechts keine gewählt; leer gesucht wieder sie — archivierte zählen mit")
    func wahlImFilter() throws {
        let p = try Self.planung()
        let titel = Lernendenblatt.zeilentitel(p)
        let b = Self.bestand(p.erstellt, [Self.gruppe("g-1", "6a"), Self.gruppe("g-2", "Bio-AG"),
                                          Self.gruppe("g-3", "7b", archiviert: Self.stempel)])
        #expect(Lernendenblatt.sichtbareWahl("g-1", in: b, suche: "Bio", zeilentitel: titel) == nil)
        #expect(Lernendenblatt.sichtbareWahl("g-1", in: b, suche: "", zeilentitel: titel) == "g-1")
        #expect(Lernendenblatt.sichtbareWahl("g-1", in: b, suche: "6", zeilentitel: titel) == "g-1")
        #expect(Lernendenblatt.sichtbareWahl("g-3", in: b, suche: "", zeilentitel: titel) == "g-3",
                "archivierte zählen mit — welche gewählt bleibt, regelt das Blatt (Z-AT15N-13)")
        #expect(Lernendenblatt.sichtbareWahl(nil, in: b, suche: "", zeilentitel: titel) == nil)
    }

    @Test("E689: Zurückgeholt wird eine Lerngruppe nicht wieder mit Zeilen verknüpft, mit denen inzwischen eine andere aktive verknüpft ist; der Hinweis nennt Zeile und Lerngruppe")
    func zurueckgeholt() throws {
        let p = try Self.planung()
        let titel = Lernendenblatt.zeilentitel(p)
        let bio = Self.z(p, 0), chemie = Self.z(p, 1)
        let b = Self.bestand(p.erstellt, [Self.gruppe("g-alt", "Bio-AG", zeilen: [bio, chemie], archiviert: Self.stempel),
                                          Self.gruppe("g-neu", "Bio-AG 2. Halbjahr", zeilen: [bio])])
        let sitz = Lernendenblatt.sitzplanzeilen(p)
        let besetzt = b.besetzteZeilen(von: "g-alt", unter: sitz)
        #expect(besetzt == [BesetzteZeile(zeile: bio, andere: ["Bio-AG 2. Halbjahr"])])
        let zurueck = b.mitZurueckgeholterGruppe("g-alt", jetzt: Self.stempel, sitzplanzeilen: sitz)
        #expect(zurueck.lerngruppen.first { $0.id == "g-alt" }?.zeilen == [chemie], "an „6a · Chemie“ wieder, an „6a · Biologie“ nicht")
        #expect(zurueck.lerngruppen.first { $0.id == "g-alt" }?.archiviert.isEmpty == true)
        #expect(zurueck.gruppen(an: bio).map(\.id) == ["g-neu"], "die Zeile behält die eine")
        #expect(Lernendenblatt.zurueckgeholtHinweis("Bio-AG", besetzt: besetzt, zeilentitel: titel)
                == "„Bio-AG“ ist zurückgeholt, ohne die Zeile „6a · Biologie“ — dort ist „Bio-AG 2. Halbjahr“ verknüpft.")
        #expect(Lernendenblatt.zurueckgeholtHinweis("Bio-AG", besetzt: [BesetzteZeile(zeile: bio, andere: ["A", "B"])],
                                                    zeilentitel: titel)
                == "„Bio-AG“ ist zurückgeholt, ohne die Zeile „6a · Biologie“ — dort sind „A“, „B“ verknüpft.")
        #expect(Lernendenblatt.zurueckgeholtHinweis("Bio-AG", besetzt: [BesetzteZeile(zeile: bio, andere: ["A"]),
                                                                         BesetzteZeile(zeile: chemie, andere: ["B"])],
                                                    zeilentitel: titel)
                == "„Bio-AG“ ist zurückgeholt, ohne die Zeilen „6a · Biologie“, „6a · Chemie“ — dort sind inzwischen andere "
                + "Lerngruppen verknüpft.")
        #expect(Lernendenblatt.zurueckgeholtHinweis("Bio-AG", besetzt: [], zeilentitel: titel) == nil)
        // Nur Zeilen mit Sitzplan (Z-AT15N-01): An „Weiteres“ tragen oft mehrere — dort wieder verknüpft, neben „Chor“.
        let weiteres = Self.z(p, 4)
        let mitWeiteres = Self.bestand(p.erstellt, [
            Self.gruppe("g-alt", "Bio-AG", zeilen: [bio, weiteres], archiviert: Self.stempel),
            Self.gruppe("g-neu", "Bio-AG 2. Halbjahr", zeilen: [bio]), Self.gruppe("g-chor", "Chor", zeilen: [weiteres])])
        #expect(mitWeiteres.besetzteZeilen(von: "g-alt", unter: sitz) == [BesetzteZeile(zeile: bio, andere: ["Bio-AG 2. Halbjahr"])],
                "„Weiteres“ zählt nicht als besetzt")
        #expect(mitWeiteres.mitZurueckgeholterGruppe("g-alt", jetzt: Self.stempel, sitzplanzeilen: sitz).lerngruppen[0].zeilen
                == [weiteres], "an „Weiteres“ wieder, an „6a · Biologie“ nicht")
        // Ohne andere aktive an ihren Zeilen: wieder an allen, wie bisher.
        let frei = Self.bestand(p.erstellt, [Self.gruppe("g-alt", "Bio-AG", zeilen: [bio, chemie], archiviert: Self.stempel)])
        #expect(frei.mitZurueckgeholterGruppe("g-alt", jetzt: Self.stempel, sitzplanzeilen: sitz).lerngruppen[0].zeilen
                == [bio, chemie])
    }

    // ── Zeilen wählen ─────────────────────────────────────────────────────

    @Test("E669, E670: Der Bogen „Zeilen wählen“ — ein Kästchen je Zeile, die eine Lerngruppe tragen kann (nicht Vertretungen); gewählt die eigenen; andere aktive Lerngruppen als Hinweis")
    func zeilenwahl() throws {
        let p = try Self.planung()
        let b = Self.bestand(p.erstellt, [
            Self.gruppe("g-1", "6a", zeilen: [Self.z(p, 0)]),
            Self.gruppe("g-2", "Bio-AG", zeilen: [Self.z(p, 0), Self.z(p, 2)]),
            Self.gruppe("g-3", "7b", zeilen: [Self.z(p, 2)]),
            Self.gruppe("g-4", "alt", zeilen: [Self.z(p, 1)], archiviert: Self.stempel)])
        let wahl = Zeilenwahl.zeilen(p, bestand: b, gruppe: "g-1")
        #expect(wahl.map(\.titel) == ["6a · Biologie", "6a · Chemie", "7b · Biologie", "Klassenleitung · 6a", "Weiteres"])
        #expect(wahl.map(\.gewaehlt) == [true, false, false, false, false])
        #expect(wahl.map(\.auch) == ["auch: Bio-AG", nil, "auch: 7b, Bio-AG", nil, nil],
                "in der Folge der Listen; die eigene und archivierte nicht")
    }

    @Test("E669, E670: Zeilen wählen legt die Zeilen einer Lerngruppe in dieser Planung fest — keiner anderen wird etwas genommen; Bindungen außerhalb bleiben")
    func mitZeilen() throws {
        let p = try Self.planung()
        let b = Self.bestand(p.erstellt, [Self.gruppe("g-1", "6a", zeilen: [Self.z(p, 1), Self.fremd]),
                                          Self.gruppe("g-2", "Bio-AG", zeilen: [Self.z(p, 0)])])
        let ids = p.klassen.map(\.id)
        let neu = b.mitZeilen("g-1", [ids[3], ids[0], ids[1]], zeilen: p.klassen, planung: p.erstellt, jetzt: Self.stempel)
        #expect(neu.lerngruppen[0].zeilen == [Self.z(p, 1), Self.fremd, Self.z(p, 0), Self.z(p, 3)],
                "behaltene in ihrer Folge, neue in der Folge der Planung dahinter")
        #expect(neu.lerngruppen[1].zeilen == [Self.z(p, 0)], "„Bio-AG“ behält „6a · Biologie“ (E670)")
        #expect(neu.gruppen(an: Self.z(p, 0)).map(\.id) == ["g-1", "g-2"])
        #expect(neu.lerngruppen[0].geaendert == Self.stempel)
        let weniger = neu.mitZeilen("g-1", [ids[3]], zeilen: p.klassen, planung: p.erstellt, jetzt: Self.stempel)
        #expect(weniger.lerngruppen[0].zeilen == [Self.fremd, Self.z(p, 3)])
        #expect(b.mitZeilen("g-1", [ids[1]], zeilen: p.klassen, planung: p.erstellt, jetzt: "später") == b,
                "dieselbe Wahl ändert nichts")
        #expect(b.mitZeilen("g-1", [ids[1], ids[5], "k-gibt-es-nicht"], zeilen: p.klassen, planung: p.erstellt,
                            jetzt: "später") == b, "Vertretungen und unbekannte Zeilen nie")
    }

    @Test("Zeilen wählen: höchstens 20 Zeilen je Lerngruppe — die behaltenen zuerst, dann neue in der Folge der Planung")
    func mitZeilenGrenze() throws {
        let p = Planung.leer(titel: "Groß", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                             klassen: Standardkurse.aufbauen((1...25).map { ("K\($0)", "Fach") }), fachfarben: [:])
        let b = Self.bestand(p.erstellt, [Self.gruppe("g-1", "AG", zeilen: [Self.fremd, Self.z(p, 24)])])
        let neu = b.mitZeilen("g-1", Set(p.klassen.map(\.id)), zeilen: p.klassen, planung: p.erstellt, jetzt: Self.stempel)
        #expect(neu.lerngruppen[0].zeilen.count == Lernendendatei.maxZeilenJeGruppe)
        #expect(Array(neu.lerngruppen[0].zeilen.prefix(3)) == [Self.fremd, Self.z(p, 24), Self.z(p, 0)])
        #expect(neu.lerngruppen[0].zeilen.last == Self.z(p, 17))
    }

    // ── Zusammenführen ────────────────────────────────────────────────────

    @Test("E667: Gleichnamig sind aktive Lerngruppen desselben Namens — Groß/Klein und Rand unerheblich; die eigene und archivierte nicht")
    func gleichnamige() {
        let b = Self.bestand("p", [Self.gruppe("g-1", "6a"), Self.gruppe("g-2", "6A"), Self.gruppe("g-3", "6b"),
                                   Self.gruppe("g-4", "6a", archiviert: Self.stempel), Self.gruppe("g-0", "6a")])
        let gleich = Lernendenblatt.gleichnamige("g-1", in: b)
        #expect(Set(gleich.map(\.id)) == ["g-0", "g-2"])
        #expect(gleich == gleich.sorted(by: Lerngruppe.vorgehen), "in der Folge der Listen")
        #expect(Lernendenblatt.gleichnamige("g-3", in: b).isEmpty)
        #expect(Lernendenblatt.gleichnamige("g-4", in: b).isEmpty, "eine archivierte führt nicht zusammen")
    }

    @Test("E667, E672: Zusammenführen — Mitglieder, Zeilen, Mitteilungen und Maßnahmen gehen auf die eine über; die andere wird archiviert, mit ihrer Mitgliederliste, ohne Zeilen")
    func zusammenfuehren() throws {
        let p = try Self.planung()
        var b = Self.bestand(p.erstellt, [Self.gruppe("g-1", "6a", mitglieder: ["l-1", "l-2"], zeilen: [Self.z(p, 0)]),
                                          Self.gruppe("g-2", "6a", mitglieder: ["l-2", "l-3"], zeilen: [Self.z(p, 1), Self.z(p, 0)]),
                                          Self.gruppe("g-3", "Bio-AG", mitglieder: ["l-4"], zeilen: [Self.z(p, 1)])])
        b.anliegen = [Self.anliegen("a-1", .mitteilung, gruppe: "g-2"), Self.anliegen("a-2", .massnahme, gruppe: "g-2"),
                      Self.anliegen("a-3", .termin, gruppe: "g-2"), Self.anliegen("a-4", .mitteilung, gruppe: "g-1"),
                      Self.anliegen("a-5", .mitteilung, gruppe: "g-3")]
        b.rueckmeldungen = [Rueckmeldung(anliegen: "a-1", lernender: "l-3", stand: .erledigt, datum: "2026-10-21", notiz: "",
                                         geaendert: Self.stempel)]
        b.leistungen = [Leistung(id: "e-1", lernender: "l-3", lerngruppe: "g-2", schuljahr: "2026/27", halbjahr: 1, art: .schriftlich,
                                 titel: "", datum: "", wert: "2", notiz: "", planung: "", vorhaben: "", angelegt: Self.stempel,
                                 geaendert: Self.stempel)]
        b.erfassung = [Erfassungseintrag(id: "f-1", lernender: "l-3", lerngruppe: "g-2", planung: "", vorhaben: "", datum: "2026-10-20",
                                         art: .muendlich, wert: "", notiz: "", angelegt: Self.stempel, geaendert: Self.stempel)]
        b.beurteilung = [Beurteilung(id: "u-1", lernender: "l-3", lerngruppe: "g-2", schuljahr: "2026/27", halbjahr: 1,
                                     zeugnisnote: "2", notiz: "", geaendert: Self.stempel)]
        let ergebnis = b.mitZusammenfuehrung("g-2", in: "g-1", jetzt: Self.stempel)
        #expect(ergebnis.grund == nil)
        #expect(ergebnis.bestand.erfassung.map(\.lerngruppe) == ["g-1"] && ergebnis.bestand.beurteilung.map(\.lerngruppe) == ["g-1"],
                "Erfassung und Beurteilung gehen mit")
        let neu = ergebnis.bestand
        let eine = try #require(neu.lerngruppen.first { $0.id == "g-1" })
        let andere = try #require(neu.lerngruppen.first { $0.id == "g-2" })
        #expect(eine.mitglieder == ["l-1", "l-2", "l-3"])
        #expect(eine.zeilen == [Self.z(p, 0), Self.z(p, 1)])
        #expect(andere.archiviert == Self.stempel)
        #expect(andere.zeilen.isEmpty, "ohne Zeilen (E672)")
        #expect(andere.mitglieder == ["l-2", "l-3"], "mit ihrer Mitgliederliste (E672)")
        #expect(neu.anliegen.map(\.lerngruppe) == ["g-1", "g-1", "g-1", "g-1", "g-3"])
        #expect(neu.rueckmeldungen == b.rueckmeldungen, "Rückläufe hängen am Anliegen und gehen mit")
        #expect(neu.leistungen.map(\.lerngruppe) == ["g-1"])
        #expect(neu.gruppen(an: Self.z(p, 1)).map(\.id) == ["g-1", "g-3"], "„Bio-AG“ bleibt an „6a · Chemie“ (E670)")
        #expect(Sitzplanfolgen(vorher: b, nachher: neu, planung: p.erstellt).entfernen.isEmpty, "kein Tisch geht")
    }

    @Test("Zusammenführen geht nicht über 40 Mitglieder oder 20 Zeilen, nicht mit sich selbst und nicht mit einer archivierten — dann bleibt alles")
    func zusammenfuehrenGrenzen() {
        let viele = Self.bestand("p", [Self.gruppe("g-1", "6a", mitglieder: (1...30).map { "l-\($0)" }),
                                       Self.gruppe("g-2", "6a", mitglieder: (21...45).map { "l-\($0)" })], personen: 45)
        let zuViele = viele.mitZusammenfuehrung("g-2", in: "g-1", jetzt: Self.stempel)
        #expect(zuViele.bestand == viele)
        #expect(zuViele.grund == "Zusammen wären es 45 Mitglieder — höchstens 40 je Lerngruppe.")
        let zeilen = (1...12).map { Zeilenbindung(planung: "p", klasseId: "k-\($0)") }
        let breit = Self.bestand("p", [Self.gruppe("g-1", "6a", zeilen: Array(zeilen.prefix(10))),
                                       Self.gruppe("g-2", "6a", zeilen: (13...24).map { Zeilenbindung(planung: "p", klasseId: "k-\($0)") })])
        #expect(breit.mitZusammenfuehrung("g-2", in: "g-1", jetzt: Self.stempel).grund
                == "Zusammen wären es 22 Zeilen — höchstens 20 je Lerngruppe.")
        #expect(viele.mitZusammenfuehrung("g-1", in: "g-1", jetzt: Self.stempel).bestand == viele)
        let archiviert = Self.bestand("p", [Self.gruppe("g-1", "6a"), Self.gruppe("g-2", "6a", archiviert: Self.stempel)])
        #expect(archiviert.mitZusammenfuehrung("g-2", in: "g-1", jetzt: Self.stempel).bestand == archiviert)
        #expect(archiviert.mitZusammenfuehrung("g-1", in: "g-2", jetzt: Self.stempel).bestand == archiviert, "auch kein archiviertes Ziel")
    }

    @Test("Zusammenführen genau an den Grenzen geht: 20 + 20 Mitglieder, 10 + 10 Zeilen; die Meldung nennt archivierte Mitglieder (E369, Z-AT9a2-02, -06)")
    func zusammenfuehrenAnDenGrenzen() {
        let vierzig = Self.bestand("p", [Self.gruppe("g-1", "6a", mitglieder: (1...20).map { "l-\($0)" },
                                                    zeilen: (1...10).map { Zeilenbindung(planung: "p", klasseId: "k-\($0)") }),
                                         Self.gruppe("g-2", "6a", mitglieder: (21...40).map { "l-\($0)" },
                                                    zeilen: (11...20).map { Zeilenbindung(planung: "p", klasseId: "k-\($0)") })],
                                   personen: 42)
        let ergebnis = vierzig.mitZusammenfuehrung("g-2", in: "g-1", jetzt: Self.stempel)
        #expect(ergebnis.grund == nil && ergebnis.bestand.lerngruppen[0].mitglieder.count == 40
                && ergebnis.bestand.lerngruppen[0].zeilen.count == 20)
        var mitArchivierten = vierzig
        mitArchivierten.lerngruppen[1].mitglieder.append("l-41")
        mitArchivierten.lernende[40].archiviert = Self.stempel
        mitArchivierten.lernende[41].archiviert = Self.stempel  // l-42: in keiner der beiden — zählt nicht
        #expect(mitArchivierten.mitZusammenfuehrung("g-2", in: "g-1", jetzt: Self.stempel).grund
                == "Zusammen wären es 41 Mitglieder, davon 1 archiviert — höchstens 40 je Lerngruppe.")
    }

    @Test("Zeilen wählen: Eine archivierte Lerngruppe bekommt keine Zeile (Z-AT9a2-05)")
    func mitZeilenNichtArchiviert() throws {
        let p = try Self.planung()
        let b = Self.bestand(p.erstellt, [Self.gruppe("g-1", "6a", archiviert: Self.stempel)])
        #expect(b.mitZeilen("g-1", [p.klassen[0].id], zeilen: p.klassen, planung: p.erstellt, jetzt: Self.stempel) == b)
    }

    @Test("E667: Die Rückfrage nennt die andere mit ihrer Mitgliederzahl und sagt, was mit ihr geschieht")
    func frage() {
        #expect(Lernendenblatt.zusammenfuehrenFrage(name: "6a", andere: 10)
                == "Zwei Lerngruppen „6a“ zusammenführen?\n\nMitglieder, Zeilen, Mitteilungen und Maßnahmen der anderen „6a“ "
                + "(10 Mitglieder) gehen auf diese über. Die andere wird archiviert, mit ihrer Liste der Mitglieder.")
        #expect(Lernendenblatt.zusammenfuehrenFrage(name: "6a", andere: 1).contains("(1 Mitglied)"))
    }
}
