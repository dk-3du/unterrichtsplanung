// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Hochstufen beim Schuljahreswechsel (v80, AP14c-2, E307–E311) ──────────
// Stufen zwischen den Schuljahren, der Name eine Stufe höher, die Zeile der
// neuen Planung je Lerngruppe — und was das Blatt „Neue Planung“ dafür anbietet.

@Suite("Hochstufen: Stufen, Name, Zeile je Lerngruppe (E307–E311)")
struct HochstufungPruefungen {

    private static let stempel = "2026-10-05T08:00:00.000Z"

    private func gruppe(_ id: String, _ name: String, _ fach: String, _ zeilen: [Zeilenbindung] = []) -> Lerngruppe {
        Lerngruppe(id: id, name: name, fach: fach, art: .klasse, mitglieder: [], zeilen: zeilen, skalen: [:],
                   halbjahreswechsel: "", geaendert: Self.stempel, archiviert: "")
    }

    private func zeile(_ id: String, _ name: String, _ fach: String, _ art: Zeilenart = .unterricht) -> Hochstufung.Zeile {
        Hochstufung.Zeile(id: id, name: name, fach: fach, art: art, titel: name + (fach.isEmpty ? "" : " · " + fach))
    }

    private func klasse(_ id: String, _ name: String, _ fach: String, _ art: Zeilenart = .unterricht) -> Klasse {
        Klasse(id: id, name: name, fach: fach, notiz: "", farbe: 0, farbeManuell: false, art: art)
    }

    /// Die neue Planung im Beispiel des Nutzers: „G7a · Informatik“ statt „G6a · Biologie“.
    private var zeilen: [Hochstufung.Zeile] {
        [zeile("n-1", "G7a", "Informatik"), zeile("n-2", "G7a", "Mathematik"),
         zeile("n-3", "Klassenleitung", "G7a", .klassenleitung), zeile("n-4", "G8c", "Informatik")]
    }

    @Test("Stufen zwischen zwei Schuljahren (E307)")
    func stufen() {
        #expect(Hochstufung.stufen(von: "2026/27", zu: "2027/28") == 1)
        #expect(Hochstufung.stufen(von: "2026/27", zu: "2026/27") == 0)
        #expect(Hochstufung.stufen(von: "2026/27", zu: "2025/26") == -1)
        #expect(Hochstufung.stufen(von: "2026/27", zu: "2028/29") == 2)
        #expect(Hochstufung.stufen(von: "", zu: "2027/28") == nil)
        #expect(Hochstufung.stufen(von: "2026/27", zu: "neu") == nil)
    }

    @Test("Der Name eine Stufe höher: erste Zahl 5–13, sonst bleibt er (E308)")
    func name() {
        let faelle: [(String, Int, String)] = [
            ("G6a", 1, "G7a"), ("10c", 1, "11c"), ("G9", 2, "G11"), ("Kl. 6a", 1, "Kl. 7a"), ("G6a2", 1, "G7a2"),
            ("Jahrgang 2026 G8", 1, "Jahrgang 2026 G9"),
            ("Q1", 1, "Q1"), ("AG Robotik", 1, "AG Robotik"), ("AG 3D-Druck", 1, "AG 3D-Druck"), ("G13", 1, "G13"),
            ("12b", 2, "12b"), ("5b", 0, "5b"), ("5b", -1, "5b"),
            ("G05a", 1, "G06a"), ("G09", 1, "G10"),
        ]
        for (ein, um, aus) in faelle {
            #expect(Hochstufung.name(ein, um: um) == aus, "„\(ein)“ um \(um)")
        }
    }

    @Test("Die übernommene Zeile einer Gruppe: die erste, deren Zeile mitkommt")
    func uebernommeneZeile() {
        let g = gruppe("g-1", "G6a", "Biologie", [Zeilenbindung(planung: "P", klasseId: "k-9"),
                                                  Zeilenbindung(planung: "P", klasseId: "k-1"),
                                                  Zeilenbindung(planung: "Q", klasseId: "k-2")])
        let zuordnung = ["k-1": "n-1", "k-2": "n-2"]
        #expect(Hochstufung.uebernommeneZeile(g, planung: "P", zuordnung: zuordnung) == "n-1")
        #expect(Hochstufung.uebernommeneZeile(gruppe("g-2", "G6b", ""), planung: "P", zuordnung: zuordnung) == nil)
    }

    @Test("Vorbelegung der Zeile: übernommen, sonst der Name, bei mehreren das Fach (E311)")
    func vorgabe() {
        let inf = gruppe("g-1", "G6a", "Informatik")
        let kl = gruppe("g-2", "G6a", "")
        let bio = gruppe("g-3", "G6a", "Biologie")
        let c = gruppe("g-4", "G7c", "Informatik")
        #expect(Hochstufung.vorgabe(fuer: bio, name: "G7a", uebernommen: "n-4", zeilen: zeilen) == "n-4", "übernommen geht vor")
        #expect(Hochstufung.vorgabe(fuer: inf, name: "G7a", uebernommen: "n-9", zeilen: zeilen) == "n-1",
                "eine übernommene Zeile, die es nicht gibt, zählt nicht — dann der Name, bei mehreren das Fach")
        #expect(Hochstufung.vorgabe(fuer: kl, name: "G7a", uebernommen: nil, zeilen: zeilen) == "n-3",
                "die Klassenleitung trägt ihre Klasse — ohne Fach passt sie zur Gruppe ohne Fach")
        #expect(Hochstufung.vorgabe(fuer: bio, name: "G7a", uebernommen: nil, zeilen: zeilen) == nil,
                "mehrere Zeilen, keine mit dem bisherigen Fach: keine")
        #expect(Hochstufung.vorgabe(fuer: c, name: "G8c", uebernommen: nil, zeilen: zeilen) == "n-4", "genau eine Zeile")
        #expect(Hochstufung.vorgabe(fuer: c, name: "G9z", uebernommen: nil, zeilen: zeilen) == nil)
        #expect(Hochstufung.vorgabe(fuer: inf, name: " g7A ", uebernommen: nil, zeilen: zeilen) == "n-1",
                "Groß/Klein und Leerraum am Rand zählen nicht")
    }

    @Test("Zuteilung: von Hand zuerst, dann die Vorgabe — keine Zeile zweimal (E311, Voreinstellung 4)")
    func zuteilung() {
        let inf = gruppe("g-1", "G6a", "Informatik")
        let kl = gruppe("g-2", "G6a", "")
        let bio = gruppe("g-3", "G6a", "Biologie")
        let namen = ["g-1": "G7a", "g-2": "G7a", "g-3": "G7a", "g-5": "G7a"]
        let gruppen = [inf, kl, bio]
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: [:])
                == ["g-1": "n-1", "g-2": "n-3"])
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: ["g-3": "n-1"])
                == ["g-3": "n-1", "g-2": "n-3"], "die von Hand gewählte Zeile nimmt sie der Vorgabe einer anderen")
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: ["g-2": ""])
                == ["g-1": "n-1"], "„Keine Zeile“ von Hand")
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: ["g-1": "n-weg"])
                == ["g-1": "n-1", "g-2": "n-3"], "eine gewählte Zeile, die es nicht mehr gibt, zählt nicht")
        let zweite = gruppe("g-5", "G6a", "Informatik")
        #expect(Hochstufung.zuteilung([inf, zweite], namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: [:])
                == ["g-1": "n-1"], "zwei Vorgaben für dieselbe Zeile: die erste Gruppe")
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen,
                                      gewaehlt: ["g-1": "n-4", "g-3": "n-4"]) == ["g-1": "n-4", "g-2": "n-3"],
                "zweimal dieselbe Zeile von Hand: die erste Gruppe")
    }

    @Test("Die Zeile unter dem Schalter „Lerngruppen hochstufen“ (E307)")
    func stufentext() {
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2027/28", stufen: 1, an: true)
                == "2026/27 → 2027/28: eine Stufe höher")
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2027/28", stufen: 1, an: false)
                == "2026/27 → 2027/28: die Namen bleiben")
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2026/27", stufen: 0, an: false)
                == "Beide im Schuljahr 2026/27 — die Namen bleiben")
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2026/27", stufen: 0, an: true)
                == "Beide im Schuljahr 2026/27 — eine Stufe höher")
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2028/29", stufen: 2, an: true)
                == "2026/27 → 2028/29: 2 Stufen höher")
    }

    @Test("Das neue Jahr nimmt Name und Zeile aus dem Blatt; das Fach folgt einer Unterrichtszeile (E308, E310)")
    func neuesJahrMitZielen() {
        let s = Self.stempel
        let alt = "alt-herkunft"
        func b(_ k: String) -> Zeilenbindung { Zeilenbindung(planung: alt, klasseId: k) }
        var bestand = Lernendenbestand.leer(planung: alt, schuljahr: "2026/27", jetzt: s)
        bestand.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: "")]
        bestand.lerngruppen = [gruppe("g-1", "6a", "Biologie", [b("k-1")]), gruppe("g-2", "6a", "", [b("k-2")]),
                               gruppe("g-3", "7b", "Chemie", [b("k-3"), b("k-4")]), gruppe("g-4", "8c", "Kunst", [b("k-6")]),
                               gruppe("g-5", "9d", "Musik", [b("k-7")])]
        let zuordnung = ["k-1": "n-5", "k-2": "n-2", "k-3": "n-3", "k-4": "n-4", "k-6": "n-6"]
        let neueZeilen = [klasse("n-1", "7a", "Informatik"), klasse("n-2", "Klassenleitung", "7a", .klassenleitung),
                          klasse("n-3", "7b", "Chemie"), klasse("n-4", "7b", "Physik"), klasse("n-5", "6a", "Biologie"),
                          klasse("n-6", "8c", "Kunst")]
        let ziele = ["g-1": Gruppenziel(name: "7a", zeile: "n-1"), "g-2": Gruppenziel(name: "7a", zeile: "n-2"),
                     "g-3": Gruppenziel(name: "  ", zeile: nil), "g-5": Gruppenziel(name: "10d", zeile: "n-6")]
        let alle: Set<String> = ["g-1", "g-2", "g-3", "g-4", "g-5"]
        let neu = bestand.neuesJahr(gruppen: alle, zuordnung: zuordnung, planung: "neu-herkunft", schuljahr: "2027/28",
                                    jetzt: s, ziele: ziele, zeilen: neueZeilen)
        func g(_ id: String) -> Lerngruppe? { neu.lerngruppen.first { $0.id == id } }
        #expect(g("g-1")?.name == "7a" && g("g-1")?.fach == "Informatik", "„6a · Biologie“ wird „7a · Informatik“")
        #expect(g("g-1")?.zeilen == [Zeilenbindung(planung: "neu-herkunft", klasseId: "n-1")],
                "die gewählte Zeile ersetzt die übernommene")
        #expect(g("g-2")?.name == "7a" && g("g-2")?.fach == "" && g("g-2")?.zeilen.map(\.klasseId) == ["n-2"],
                "an der Klassenleitung bleibt das Fach")
        #expect(g("g-3")?.name == "7b" && g("g-3")?.fach == "Chemie", "leerer Name: der bisherige")
        #expect(g("g-3")?.zeilen.map(\.klasseId) == ["n-4"], "„Keine Zeile“ ersetzt die vorbelegte; die weitere bleibt")
        #expect(g("g-5")?.fach == "Kunst" && g("g-5")?.zeilen.map(\.klasseId) == ["n-6"], "gewählt: die Zeile einer anderen Gruppe")
        #expect(g("g-4")?.zeilen.isEmpty == true, "eine Zeile trägt eine Gruppe — die gewählte geht vor")

        let ohne = bestand.neuesJahr(gruppen: alle, zuordnung: zuordnung, planung: "neu-herkunft", schuljahr: "2027/28",
                                     jetzt: s)
        #expect(ohne.lerngruppen.first?.name == "6a" && ohne.lerngruppen.first?.zeilen.map(\.klasseId) == ["n-5"],
                "ohne Ziele wie bisher")
    }

    @Test("„Neue Planung“: Zeilenangebot mit Schlüsseln und deren Auflösung beim Anlegen (E310)")
    func angebotUndAufloesung() {
        let eingaben: [(name: String, fach: String)] = [("G7a", "Informatik"), ("G7a", "Informatik"), ("G8c", "")]
        let alt = klasse("k-2", "Klassenleitung", "G6a", .klassenleitung)
        let angebot = NeuePlanungDialog.zeilenangebot(eingaben: eingaben, sonderzeilen: [.klassenleitung], uebernommene: [alt])
        #expect(angebot.map(\.id) == ["e:g7a\u{1F}informatik", "e:g8c\u{1F}", "s:klassenleitung", "u:k-2"],
                "jede Zeile einmal — \(angebot.map(\.id))")
        #expect(angebot.map(\.titel) == ["G7a · Informatik", "G8c", "Klassenleitung", "Klassenleitung · G6a"])
        let klassen = Standardkurse.aufbauen(eingaben) + [Klasse.sonderzeile(.klassenleitung)]
        #expect(NeuePlanungDialog.zielzeile("e:g7a\u{1F}informatik", eingaben: eingaben, klassen: klassen) == .kennung(klassen[0].id))
        #expect(NeuePlanungDialog.zielzeile("s:klassenleitung", eingaben: eingaben, klassen: klassen) == .kennung(klassen[3].id))
        #expect(NeuePlanungDialog.zielzeile("u:k-2", eingaben: eingaben, klassen: klassen) == .uebernommen("k-2"))
        #expect(NeuePlanungDialog.zielzeile("", eingaben: eingaben, klassen: klassen) == .keine)
        #expect(NeuePlanungDialog.zielzeile("e:weg", eingaben: eingaben, klassen: klassen) == .keine)
        #expect(NeuePlanungDialog.zielzeile("s:weiteres", eingaben: eingaben, klassen: klassen) == .keine)
    }

    @Test("Namensfeld: Vorschlag nach Schalter und Stufen, getippt geht vor, leer heißt der bisherige Name (E308)")
    func namensfeld() {
        let g = gruppe("g-1", "G6a", "Informatik")
        var w = Hochstufungswahl()
        #expect(w.name(g, stufen: 1) == "G7a" && w.name(g, stufen: 0) == "G6a")
        w.hochstufen = true
        #expect(w.name(g, stufen: 0) == "G7a" && w.name(g, stufen: -1) == "G7a",
                "von Hand an ohne Wechsel: eine Stufe (Voreinstellung 1)")
        w.hochstufen = false
        #expect(w.name(g, stufen: 2) == "G6a")
        w.namen["g-1"] = " "
        #expect(w.name(g, stufen: 1) == " " && w.suchname(g, stufen: 1) == "G6a", "leer: der bisherige Name")
    }

    @Test("Haken: live bis zur ersten Änderung; eine Zeilenwahl setzt den Haken, „Keine Zeile“ und Abgabe nehmen ihn nicht (E312)")
    func hakenUndZeile() {
        var w = Hochstufungswahl()
        let vorwahl: Set<String> = ["g-1", "g-2"]
        #expect(w.gewaehlt(vorwahl: vorwahl) == vorwahl && w.gewaehlt(vorwahl: ["g-2"]) == ["g-2"], "live")
        w.zeileWaehlen("n-1", fuer: "g-3", zuteilung: ["g-1": "n-1", "g-2": "n-3"], vorwahl: vorwahl)
        #expect(w.gewaehlt(vorwahl: []) == ["g-1", "g-2", "g-3"], "eingefroren; g-3 dazu, g-1 behält den Haken")
        #expect(w.zeilen == ["g-1": "", "g-3": "n-1"], "die Zeile wandert, die bisherige Gruppe steht auf „Keine Zeile“")
        w.zeileWaehlen("", fuer: "g-2", zuteilung: ["g-3": "n-1", "g-2": "n-3"], vorwahl: [])
        #expect(w.gewaehlt(vorwahl: []) == ["g-1", "g-2", "g-3"], "„Keine Zeile“ nimmt den Haken nicht")
        let g1 = gruppe("g-1", "G6a", "Informatik")
        var n = Hochstufungswahl()
        n.nameSetzen("G7a", fuer: g1, stufen: 1, vorwahl: ["g-1"])
        #expect(n.haken == nil && n.namen.isEmpty, "der angezeigte Name, ohne Änderung zurückgegeben: nichts geschieht (Z14c2-09)")
        n.nameSetzen("G7b", fuer: g1, stufen: 1, vorwahl: ["g-1"])
        #expect(n.gewaehlt(vorwahl: []) == ["g-1"] && n.namen == ["g-1": "G7b"], "Tippen friert die Vorwahl ein")
        var s = Hochstufungswahl()
        s.hochstufenSetzen(false, vorwahl: ["g-2"])
        #expect(s.gewaehlt(vorwahl: []) == ["g-2"] && s.hochstufen == false, "der Schalter friert sie ein")
        var h = Hochstufungswahl()
        h.haken = ["g-9"]
        #expect(h.gewaehlt(vorwahl: ["g-1"]) == ["g-9"], "Haken von Hand gelten")
    }

    @Test("Eine Zeile trägt auch nach dem Wechsel nur eine Gruppe — auch ohne Wahl im Blatt (Z14c2-07); höchstens 20 Zeilen je Gruppe")
    func eineZeileEineGruppe() {
        let s = Self.stempel
        let alt = "alt-herkunft"
        func b(_ k: String) -> Zeilenbindung { Zeilenbindung(planung: alt, klasseId: k) }
        var bestand = Lernendenbestand.leer(planung: alt, schuljahr: "2026/27", jetzt: s)
        let viele = (1...20).map { "k-v\($0)" }
        bestand.lerngruppen = [gruppe("g-1", "6a", "", [b("k-1")]), gruppe("g-2", "6a", "Kunst", [b("k-1"), b("k-2")]),
                               gruppe("g-3", "7c", "", viele.map(b))]
        var zuordnung = ["k-1": "n-1", "k-2": "n-2"]
        for (i, k) in viele.enumerated() { zuordnung[k] = "n-v\(i + 1)" }
        let neu = bestand.neuesJahr(gruppen: ["g-1", "g-2", "g-3"], zuordnung: zuordnung, planung: "neu", schuljahr: "2027/28",
                                    jetzt: s, ziele: ["g-3": Gruppenziel(name: "8c", zeile: "n-x")],
                                    zeilen: [klasse("n-x", "8c", "Physik")])
        func g(_ id: String) -> Lerngruppe? { neu.lerngruppen.first { $0.id == id } }
        #expect(g("g-1")?.zeilen.map(\.klasseId) == ["n-1"])
        #expect(g("g-2")?.zeilen.map(\.klasseId) == ["n-2"], "dieselbe übernommene Zeile: die erste Gruppe")
        #expect(g("g-3")?.zeilen.count == Lernendendatei.maxZeilenJeGruppe && g("g-3")?.zeilen.first?.klasseId == "n-x",
                "die gewählte Zeile vorn, höchstens 20")
    }
}
