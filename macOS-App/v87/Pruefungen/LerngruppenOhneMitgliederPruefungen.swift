// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Lerngruppen ohne Mitglieder beim Schuljahreswechsel (v85 P1, v86 AX2: E699, E708, E763–E765) ──
// Förder-, AG- und Kurs-Lerngruppen werden jedes Schuljahr neu zusammengesetzt: Sie kommen mit Namen, Zeilen und
// Skalen ins neue Jahr, aber ohne Mitglieder (E699); die Mitglieder bleiben in der Vorjahresplanung im Archiv. Je
// Lerngruppe ein Schalter „mit Mitgliedern“, vorbelegt nach der Stufe im Namen — dieselbe Regel wie das Hochstufen
// (E708). Reine Funktionen: das neue Jahr, die Vorbelegung, die Menge für Bogen und neues Jahr, das Zeilenmodell.

@Suite("Lerngruppen ohne Mitglieder: neues Jahr, Vorbelegung, Bogen (E699, E708)")
struct LerngruppenOhneMitgliederPruefungen {

    private static let stempel = "2026-10-03T08:00:00.000Z"
    private static let spaeter = "2027-07-20T08:00:00.000Z"
    private static let herkunft = "alt-herkunft"

    /// Je Lerngruppe ihre Zeile der bisherigen Planung → die Zeile der neuen.
    private static let zuordnung = ["k-6a": "n-7a", "k-6b": "n-7b", "k-6c": "n-7c", "k-mf": "n-mf", "k-ag": "n-ag"]

    /// Die Klassen-Lerngruppen „6a“ (Anna, Ben), „6b“ (Cem, Dora) und „6c“ (Emil); „Mathe-Förder“ mit Anna aus der 6a
    /// und Cem aus der 6b; „Bio-AG“ mit Dora aus der 6b und Emil aus der 6c. Offen: eine Mitteilung an „Mathe-Förder“
    /// für Anna und Cem (beide mit Rücklauf samt Notiz), eine Maßnahme aus „Mathe-Förder“ nur für Cem, ein Termin aus
    /// der „Bio-AG“ nur für Emil.
    private func bestand() -> Lernendenbestand {
        let s = Self.stempel
        func person(_ id: String, _ vor: String, _ nach: String) -> Lernender {
            Lernender(id: id, vorname: vor, nachname: nach, angelegt: s, geaendert: s, archiviert: "")
        }
        func gruppe(_ id: String, _ name: String, _ art: Lerngruppenart, _ mitglieder: [String], _ zeile: String) -> Lerngruppe {
            Lerngruppe(id: id, name: name, art: art, mitglieder: mitglieder,
                       zeilen: [Zeilenbindung(planung: Self.herkunft, klasseId: zeile)],
                       skalen: ["muendlich": "fuenfstufig"], halbjahreswechsel: "2027-01-29", geaendert: s, archiviert: "")
        }
        var b = Lernendenbestand.leer(planung: Self.herkunft, schuljahr: "2026/27", jetzt: s)
        b.lernende = [person("l-1", "Anna", "Abel"), person("l-2", "Ben", "Bauer"), person("l-3", "Cem", "Çelik"),
                      person("l-4", "Dora", "Dietz"), person("l-5", "Emil", "Ernst")]
        b.lerngruppen = [gruppe("g-6a", "6a", .klasse, ["l-1", "l-2"], "k-6a"),
                         gruppe("g-6b", "6b", .klasse, ["l-3", "l-4"], "k-6b"),
                         gruppe("g-6c", "6c", .klasse, ["l-5"], "k-6c"),
                         gruppe("g-mf", "Mathe-Förder", .kurs, ["l-1", "l-3"], "k-mf"),
                         gruppe("g-ag", "Bio-AG", .kurs, ["l-4", "l-5"], "k-ag")]
        b.anliegen = [
            Anliegen(id: "m-1", art: .mitteilung, titel: "Förderplan unterschreiben", lerngruppe: "g-mf",
                     betroffene: ["l-1", "l-3"], datum: "2026-10-01", frist: "", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "m-2", art: .massnahme, titel: "Übungsheft nachreichen", lerngruppe: "g-mf", betroffene: ["l-3"],
                     datum: "2026-10-02", frist: "2026-10-16", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "m-3", art: .termin, titel: "Gespräch zur AG", lerngruppe: "g-ag", betroffene: ["l-5"],
                     datum: "2026-10-20", frist: "", notiz: "", angelegt: s, geaendert: s),
        ]
        b.rueckmeldungen = [
            Rueckmeldung(anliegen: "m-1", lernender: "l-1", stand: .offen, datum: "", notiz: "kommt Montag", geaendert: s),
            Rueckmeldung(anliegen: "m-1", lernender: "l-3", stand: .offen, datum: "", notiz: "fehlt noch", geaendert: s),
        ]
        return b
    }

    private func neuesJahr(_ b: Lernendenbestand, _ gruppen: Set<String>, ohne: Set<String>) -> Lernendenbestand {
        b.neuesJahr(gruppen: gruppen, zuordnung: Self.zuordnung, planung: "neu", schuljahr: "2027/28",
                    termine: .abDemNeuenSchuljahr, jetzt: Self.spaeter,
                    ohneMitglieder: ohne)
    }

    // ── Das neue Jahr (E699) ──────────────────────────────────────────────

    @Test("Eine Lerngruppe ohne Mitglieder kommt mit Namen, Zeile und Skalen — die Mitgliederliste leer (E699)")
    func ohneMitgliederMitZeile() throws {
        let neu = neuesJahr(bestand(), ["g-6a", "g-mf"], ohne: ["g-mf"])
        #expect(neu.lerngruppen.map(\.id) == ["g-6a", "g-mf"])
        let mf = try #require(neu.lerngruppen.first { $0.id == "g-mf" })
        #expect(mf.name == "Mathe-Förder" && mf.art == .kurs && mf.skalen == ["muendlich": "fuenfstufig"])
        #expect(mf.zeilen == [Zeilenbindung(planung: "neu", klasseId: "n-mf")], "die Zeile kommt mit")
        #expect(mf.mitglieder.isEmpty, "ohne Mitglieder — die Zusammensetzung des Vorjahrs bleibt im Archiv")
        #expect(neu.lerngruppen.first { $0.id == "g-6a" }?.mitglieder == ["l-1", "l-2"], "die Klasse mit ihren Mitgliedern")
    }

    @Test("Personen kommen nur über Lerngruppen mit Mitgliedern — wer nur in einer ohne steckt, bleibt im Archiv (E699)")
    func personenNurUeberMitMitgliedern() {
        let b = bestand()
        let nurFoerder = neuesJahr(b, ["g-6a", "g-mf"], ohne: ["g-mf"])
        #expect(nurFoerder.lernende.map(\.id) == ["l-1", "l-2"], "Anna über die 6a; Cem steckt nur in „Mathe-Förder“")
        let mitKlassen = neuesJahr(b, ["g-6a", "g-6b", "g-mf", "g-ag"], ohne: ["g-mf", "g-ag"])
        #expect(mitKlassen.lernende.map(\.id) == ["l-1", "l-2", "l-3", "l-4"],
                "Cem und Dora über die 6b; Emil steckt nur in der „Bio-AG“")
        #expect(mitKlassen.lerngruppen.filter(\.mitglieder.isEmpty).map(\.id) == ["g-mf", "g-ag"],
                "auch wer über eine Klasse mitkommt, ist kein Mitglied einer Lerngruppe ohne Mitglieder")
        let nurOhne = neuesJahr(b, ["g-mf", "g-ag"], ohne: ["g-mf", "g-ag"])
        #expect(nurOhne.lernende.isEmpty && nurOhne.anliegen.isEmpty && nurOhne.rueckmeldungen.isEmpty,
                "keine Person, darum nichts Offenes")
        #expect(nurOhne.lerngruppen.map(\.id) == ["g-mf", "g-ag"], "beide Lerngruppen kommen — leer")
    }

    @Test("Ohne Angabe wie bisher: Jede gewählte Lerngruppe kommt mit ihren Mitgliedern (Vorgabe leer)")
    func vorgabeWieBisher() {
        let b = bestand()
        let ohneAngabe = b.neuesJahr(gruppen: ["g-6a", "g-mf"], zuordnung: Self.zuordnung, planung: "neu",
                                     schuljahr: "2027/28", termine: .abDemNeuenSchuljahr, jetzt: Self.spaeter)
        #expect(ohneAngabe == neuesJahr(b, ["g-6a", "g-mf"], ohne: []))
        #expect(ohneAngabe.lerngruppen.first { $0.id == "g-mf" }?.mitglieder == ["l-1", "l-3"])
        #expect(ohneAngabe.lernende.map(\.id) == ["l-1", "l-2", "l-3"], "Cem über „Mathe-Förder“")
    }

    @Test("Kennungen ohne Wahl wirken nicht: Eine nicht gewählte oder unbekannte Lerngruppe in der Menge ändert nichts")
    func fremdeKennungen() {
        let b = bestand()
        #expect(neuesJahr(b, ["g-6a", "g-mf"], ohne: ["g-6b", "g-weg"]) == neuesJahr(b, ["g-6a", "g-mf"], ohne: []))
        #expect(neuesJahr(b, ["g-6a", "g-6b"], ohne: ["g-mf"]).lernende.map(\.id) == ["l-1", "l-2", "l-3", "l-4"],
                "„Mathe-Förder“ ist nicht gewählt — Anna und Cem kommen über ihre Klassen")
    }

    // Nach E763/E764 (v86, AX2) umgestellt — P1 hielt das alte Verhalten fest (die Mitteilung kam mit der Lerngruppe).
    @Test("Für Anliegen zählt eine Lerngruppe ohne Mitglieder wie eine, die nicht mitkommt: die Mitteilung bleibt im Archiv, Maßnahme und Termin kommen mit der Person, ohne Lerngruppe (E763, E764)")
    func anliegenOhneMitglieder() {
        var b = bestand()
        let s = Self.stempel
        // Dazu aus „Mathe-Förder“ für Anna, die über die 6a mitkommt: eine Maßnahme und ein Termin.
        b.anliegen += [
            Anliegen(id: "m-4", art: .massnahme, titel: "Übungsheft nachreichen", lerngruppe: "g-mf", betroffene: ["l-1"],
                     datum: "2026-10-02", frist: "2026-10-16", notiz: "", angelegt: s, geaendert: s),
            // Im neuen Schuljahr — ein Termin davor bliebe im Archiv (E816).
            Anliegen(id: "m-5", art: .termin, titel: "Fördergespräch", lerngruppe: "g-mf", betroffene: ["l-1"],
                     datum: "2027-09-22", frist: "", notiz: "", angelegt: s, geaendert: s),
        ]
        let neu = neuesJahr(b, ["g-6a", "g-mf"], ohne: ["g-mf"])
        #expect(neu.anliegen.map(\.id) == ["m-4", "m-5"],
                "die Mitteilung an „Mathe-Förder“ bleibt im Archiv (E763); die Maßnahme nur für Cem ebenso, der Termin für Emil")
        let ohneGruppe = neu.anliegen.allSatisfy { $0.lerngruppe.isEmpty && $0.betroffene == ["l-1"] }
        #expect(ohneGruppe, "Maßnahme und Termin kommen mit Anna, ohne Lerngruppe (E764)")
        #expect(neu.rueckmeldungen.isEmpty, "Annas Rücklauf zur Mitteilung bleibt mit ihr im Archiv")
        // Mit Mitgliedern wie bisher: Alles bleibt an „Mathe-Förder“, auch Cem kommt mit.
        let mit = neuesJahr(b, ["g-6a", "g-mf"], ohne: [])
        #expect(mit.anliegen.map(\.id) == ["m-1", "m-2", "m-4", "m-5"])
        let anDerGruppe = mit.anliegen.allSatisfy { $0.lerngruppe == "g-mf" }
        #expect(anDerGruppe)
    }

    @Test("E765: Die Zeilen, an denen im neuen Jahr nur Lerngruppen ohne Mitglieder hängen — eine gemischte Zeile nicht, ohne Menge keine")
    func zeilenNurOhneMitglieder() {
        var b = bestand()
        // „Mathe-Förder“ hängt auch an der Zeile der 6a — die Zeile „7a“ trägt im neuen Jahr eine mit und eine ohne.
        if let stelle = b.lerngruppen.firstIndex(where: { $0.id == "g-mf" }) {
            b.lerngruppen[stelle].zeilen.append(Zeilenbindung(planung: Self.herkunft, klasseId: "k-6a"))
        }
        let neu = neuesJahr(b, ["g-6a", "g-mf", "g-ag"], ohne: ["g-mf", "g-ag"])
        #expect(neu.zeilenNurOhneMitglieder(planung: "neu") == ["n-mf", "n-ag"],
                "„Mathe-Förder“ und „Bio-AG“ allein an ihrer Zeile; „7a“ trägt die 6a mit Mitgliedern")
        #expect(neuesJahr(b, ["g-6a", "g-mf", "g-ag"], ohne: []).zeilenNurOhneMitglieder(planung: "neu").isEmpty)
        #expect(neu.zeilenNurOhneMitglieder(planung: "andere").isEmpty, "nur Zeilen der genannten Planung")
    }

    // ── Die Vorbelegung des Schalters (E708) ──────────────────────────────

    @Test("Vorbelegung „mit Mitgliedern“: an mit einer Stufe 5–13 im Namen, sonst aus — Fehlvorbelegungen bleiben umlegbar (E708)")
    func vorbelegung() {
        let faelle: [(String, Bool)] = [
            ("6a", true), ("G6a", true), ("7b", true), ("G13", true), ("6 Inf", true), ("Jahrgang 2026 G8", true),
            // Bekannt und gewollt: Die Regel sieht nur die Zahl — von Hand umlegbar.
            ("Mathe-Förder 7", true),
            ("Q1", false), ("Mathe-Förder", false), ("Bio-AG", false), ("AG 3D-Druck", false), ("4b", false),
            ("G14", false), ("", false),
        ]
        for (name, an) in faelle {
            #expect(Hochstufung.mitMitgliedernVorbelegt(name: name) == an, "„\(name)“")
        }
    }

    @Test("Eine Regel mit dem Hochstufen: Wo es den Namen ändert, ist „mit Mitgliedern“ vorbelegt (E308, E708)")
    func eineRegel() {
        let namen = ["6a", "G6a", "7b", "Q1", "Mathe-Förder", "Mathe-Förder 7", "Bio-AG", "AG 3D-Druck", "AG Robotik",
                     "G13", "6 Inf", "", "4b", "G14", "Jahrgang 2026 G8", "G05a", "G09", "Kl. 6a", "10c", "12b"]
        for name in namen {
            let aendert = (1...8).contains { Hochstufung.name(name, um: $0) != name }
            #expect(!aendert || Hochstufung.mitMitgliedernVorbelegt(name: name), "„\(name)“")
        }
    }

    @Test("Die Menge ohne Mitglieder: vorbelegt nach dem bisherigen Namen, von Hand umgelegt in beide Richtungen (E708)")
    func mengeOhneMitglieder() {
        let gruppen = bestand().lerngruppen
        #expect(Hochstufung.ohneMitglieder(gruppen) == ["g-mf", "g-ag"], "die Klassen mit, „Mathe-Förder“ und „Bio-AG“ ohne")
        #expect(Hochstufung.ohneMitglieder(gruppen, gewaehlt: ["g-ag": true, "g-6b": false]) == ["g-mf", "g-6b"],
                "die „Bio-AG“ von Hand mit, die 6b von Hand ohne")
        #expect(Hochstufung.ohneMitglieder([], gewaehlt: ["g-mf": false]).isEmpty, "nur Lerngruppen der Liste")
        // Das Feld „art“ steht in der Datei, wirkt aber nicht (E666): vertauscht, gleiche Vorbelegung.
        var vertauscht = gruppen
        for i in vertauscht.indices { vertauscht[i].art = vertauscht[i].art == .klasse ? .kurs : .klasse }
        #expect(Hochstufung.ohneMitglieder(vertauscht) == ["g-mf", "g-ag"], "es zählt der Name, nicht „art“ (E666)")
    }

    // ── Der Bogen „Lerngruppen zuordnen“ (E708) ───────────────────────────

    /// Die neue Planung: „7a · Mathematik“, „7b · Mathematik“, „Mathe-Förder“ und „Bio-AG“ — für die 6c keine Zeile.
    private var klassen: [Klasse] {
        [Klasse(id: "n-7a", name: "7a", fach: "Mathematik", notiz: "", farbe: 0, farbeManuell: false, art: .unterricht),
         Klasse(id: "n-7b", name: "7b", fach: "Mathematik", notiz: "", farbe: 0, farbeManuell: false, art: .unterricht),
         Klasse(id: "n-mf", name: "Mathe-Förder", fach: "", notiz: "", farbe: 0, farbeManuell: false, art: .unterricht),
         Klasse(id: "n-ag", name: "Bio-AG", fach: "", notiz: "", farbe: 0, farbeManuell: false, art: .unterricht)]
    }

    /// Wie die Blätter rechnen: die Namen eine Stufe höher, die Zuteilung nach dem Vorschlag; mit kommt, wer eine Zeile
    /// trägt (E657).
    private func wahl(_ gruppen: [Lerngruppe]) -> (namen: [String: String], zeilen: [Hochstufung.Zeile],
                                                    zuteilung: [String: [String]], mitkommend: Set<String>) {
        let namen = Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, Hochstufung.name($0.name, um: 1)) })
        let zeilen = klassen.map { Hochstufung.Zeile($0) }
        let zuteilung = Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: [:])
        return (namen, zeilen, zuteilung, Hochstufung.mitkommend(zuteilung))
    }

    @Test("Zeilenmodell: je Lerngruppe der Schalter „mit Mitgliedern“ — ohne Angabe alle an; Folge, Zeilen und Zusammenfassung unberührt (E708)")
    func zeilenmodell() {
        let gruppen = bestand().lerngruppen
        let w = wahl(gruppen)
        #expect(w.mitkommend == ["g-6a", "g-6b", "g-mf", "g-ag"], "die 6c findet keine Zeile „7c“")
        let m = Hochstufung.zeilenmodell(gruppen, mitkommend: w.mitkommend, namen: w.namen, zeilen: w.zeilen,
                                         zuteilung: w.zuteilung, ohneMitglieder: ["g-mf", "g-ag"])
        let schalter = Dictionary(uniqueKeysWithValues: m.links.map { ($0.id, $0.mitMitgliedern) })
        #expect(schalter == ["g-6a": true, "g-6b": true, "g-6c": true, "g-mf": false, "g-ag": false])
        let ohneAngabe = Hochstufung.zeilenmodell(gruppen, mitkommend: w.mitkommend, namen: w.namen, zeilen: w.zeilen,
                                                  zuteilung: w.zuteilung)
        let alleMit = ohneAngabe.links.allSatisfy(\.mitMitgliedern)
        #expect(alleMit, "ohne Angabe: alle mit Mitgliedern")
        #expect(m.links.map(\.id) == ohneAngabe.links.map(\.id) && m.rechts == ohneAngabe.rechts
                    && m.zusammenfassung == ohneAngabe.zusammenfassung,
                "der Schalter ändert weder Folge noch Zeilen noch Zusammenfassung")
    }

    @Test("Was der Bogen zeigt, entsteht im neuen Jahr: ohne Mitglieder leer, von Hand mit Mitgliedern samt Personen (E708)")
    func bogenWieDasNeueJahr() throws {
        let b = bestand()
        let gruppen = b.lerngruppen.sorted(by: Lerngruppe.vorgehen)
        let w = wahl(gruppen)
        // Die „Bio-AG“ von Hand mit Mitgliedern — so kommt Emil aus der 6c mit.
        let ohne = Hochstufung.ohneMitglieder(gruppen, gewaehlt: ["g-ag": true])
        let m = Hochstufung.zeilenmodell(gruppen, mitkommend: w.mitkommend, namen: w.namen, zeilen: w.zeilen,
                                         zuteilung: w.zuteilung, ohneMitglieder: ohne)
        let ziele = Dictionary(uniqueKeysWithValues: m.links.filter(\.kommtMit).map {
            ($0.id, Gruppenziel(name: $0.name, zeilen: w.zuteilung[$0.id] ?? []))
        })
        let neu = b.neuesJahr(gruppen: Set(ziele.keys), zuordnung: Self.zuordnung, planung: "neu", schuljahr: "2027/28",
                              termine: .abDemNeuenSchuljahr,
                              jetzt: Self.spaeter, ziele: ziele, zeilen: klassen, ohneMitglieder: ohne)
        for g in m.links where g.kommtMit {
            let imNeuenJahr = try #require(neu.lerngruppen.first { $0.id == g.id })
            #expect(imNeuenJahr.mitglieder.isEmpty == !g.mitMitgliedern, "\(g.id)")
        }
        #expect(neu.lernende.map(\.id) == ["l-1", "l-2", "l-3", "l-4", "l-5"], "Emil über die „Bio-AG“")
    }
}
