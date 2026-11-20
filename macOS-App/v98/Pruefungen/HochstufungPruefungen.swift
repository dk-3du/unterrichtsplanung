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

    private func gruppe(_ id: String, _ name: String, _ zeilen: [Zeilenbindung] = []) -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: [], zeilen: zeilen, skalen: [:],
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

    @Test("Der Name eine Stufe höher: Erste Zahl 5–13, sonst bleibt er (E308)")
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

    // AT9 (Modell): statt der einen übernommenen Zeile alle, in ihrer Folge (E650) — die erste ist die bisherige.
    @Test("Die übernommenen Zeilen einer Gruppe: alle, deren Zeile mitkommt, in ihrer Folge — die erste ist die vorbelegte (E311, E650)")
    func uebernommeneZeilen() {
        let g = gruppe("g-1", "G6a", [Zeilenbindung(planung: "P", klasseId: "k-9"),
                                                  Zeilenbindung(planung: "P", klasseId: "k-1"),
                                                  Zeilenbindung(planung: "Q", klasseId: "k-2"),
                                                  Zeilenbindung(planung: "P", klasseId: "k-3")])
        let zuordnung = ["k-1": "n-1", "k-2": "n-2", "k-3": "n-3"]
        #expect(Hochstufung.uebernommeneZeilen(g, planung: "P", zuordnung: zuordnung) == ["n-1", "n-3"])
        #expect(Hochstufung.uebernommeneZeilen(gruppe("g-2", "G6b"), planung: "P", zuordnung: zuordnung) == [])
    }

    @Test("Vorbelegung der Zeile: übernommen, sonst die erste des Angebots mit dem Namen — ohne Fach (E311, V11, E665)")
    func vorgabe() {
        #expect(Hochstufung.vorgabe(name: "G7a", uebernommen: "n-4", zeilen: zeilen) == "n-4", "übernommen geht vor")
        #expect(Hochstufung.vorgabe(name: "G7a", uebernommen: "n-9", zeilen: zeilen) == "n-1",
                "eine übernommene Zeile, die es nicht gibt, zählt nicht — dann die erste mit dem Namen")
        #expect(Hochstufung.vorgabe(name: "G7a", uebernommen: nil, zeilen: Array(zeilen.dropFirst(2))) == "n-3",
                "die Klassenleitung trägt ihre Klasse")
        #expect(Hochstufung.vorgabe(name: "G8c", uebernommen: nil, zeilen: zeilen) == "n-4", "genau eine Zeile")
        #expect(Hochstufung.vorgabe(name: "G9z", uebernommen: nil, zeilen: zeilen) == nil)
        #expect(Hochstufung.vorgabe(name: " g7A ", uebernommen: nil, zeilen: zeilen) == "n-1",
                "Groß/Klein und Leerraum am Rand zählen nicht")
    }

    @Test("Zuteilung: von Hand Festgelegtes genau so, sonst die Vorgabe und die übrigen Zeilen des Namens — eine Zeile kann mehrere Gruppen tragen (E311, E650, E675)")
    func zuteilung() {
        let inf = gruppe("g-1", "G6a")
        let kl = gruppe("g-2", "G6a")
        let bio = gruppe("g-3", "G6a")
        let namen = ["g-1": "G7a", "g-2": "G7a", "g-3": "G7a", "g-5": "G7a"]
        let gruppen = [inf, kl, bio]
        let alle = ["n-1", "n-2", "n-3"]
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: [:])
                == ["g-1": alle, "g-2": alle, "g-3": alle], "der Vorschlag gibt jeder „G6a“ alle Zeilen ihres neuen Namens (E675)")
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: ["g-3": ["n-1"]])
                == ["g-3": ["n-1"], "g-1": alle, "g-2": alle], "von Hand genau die gewählte — den übrigen wird nichts genommen")
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: ["g-1": []])
                == ["g-2": alle, "g-3": alle], "„Keine Zeile“ von Hand: Nur diese Gruppe trägt keine")
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: ["g-1": ["n-weg"]])
                == ["g-1": alle, "g-2": alle, "g-3": alle], "eine gewählte Zeile, die es nicht mehr gibt, zählt nicht")
        let zweite = gruppe("g-5", "G6a")
        #expect(Hochstufung.zuteilung([inf, zweite], namen: namen, uebernommen: [:], zeilen: zeilen, gewaehlt: [:])
                == ["g-1": alle, "g-5": alle], "zwei Vorgaben für dieselbe Zeile: beide (E670)")
        #expect(Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: zeilen,
                                      gewaehlt: ["g-1": ["n-4"], "g-3": ["n-4"]]) == ["g-1": ["n-4"], "g-2": alle, "g-3": ["n-4"]],
                "zweimal dieselbe Zeile von Hand: beide tragen sie; von Hand Festgelegtes bekommt nichts dazu")
    }

    @Test("Die Zeile unter dem Schalter „Lerngruppen hochstufen“ (E307)")
    func stufentext() {
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2027/28", stufen: 1, an: true)
                == "2026/27 → 2027/28: eine Stufe höher")
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2027/28", stufen: 1, an: false)
                == "2026/27 → 2027/28: Die Namen bleiben")
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2026/27", stufen: 0, an: false)
                == "Beide im Schuljahr 2026/27 — die Namen bleiben")
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2026/27", stufen: 0, an: true)
                == "Beide im Schuljahr 2026/27 — eine Stufe höher")
        #expect(Hochstufung.stufentext(bisher: "2026/27", neu: "2028/29", stufen: 2, an: true)
                == "2026/27 → 2028/29: 2 Stufen höher")
    }

    // AT9 (Modell): Das neue Jahr setzt kein Fach (E656) — bis dahin folgte es der Unterrichtszeile (E313).
    @Test("Das neue Jahr nimmt Name und Zeile aus dem Blatt (E308, E310, E656)")
    func neuesJahrMitZielen() {
        let s = Self.stempel
        let alt = "alt-herkunft"
        func b(_ k: String) -> Zeilenbindung { Zeilenbindung(planung: alt, klasseId: k) }
        var bestand = Lernendenbestand.leer(planung: alt, schuljahr: "2026/27", jetzt: s)
        bestand.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: "")]
        bestand.lerngruppen = [gruppe("g-1", "6a", [b("k-1")]), gruppe("g-2", "6a", [b("k-2")]),
                               gruppe("g-3", "7b", [b("k-3"), b("k-4")]), gruppe("g-4", "8c", [b("k-6")]),
                               gruppe("g-5", "9d", [b("k-7")])]
        let zuordnung = ["k-1": "n-5", "k-2": "n-2", "k-3": "n-3", "k-4": "n-4", "k-6": "n-6"]
        let neueZeilen = [klasse("n-1", "7a", "Informatik"), klasse("n-2", "Klassenleitung", "7a", .klassenleitung),
                          klasse("n-3", "7b", "Chemie"), klasse("n-4", "7b", "Physik"), klasse("n-5", "6a", "Biologie"),
                          klasse("n-6", "8c", "Kunst")]
        let ziele = ["g-1": Gruppenziel(name: "7a", zeilen: ["n-1"]), "g-2": Gruppenziel(name: "7a", zeilen: ["n-2"]),
                     "g-3": Gruppenziel(name: "  ", zeilen: []), "g-5": Gruppenziel(name: "10d", zeilen: ["n-6"])]
        let alle: Set<String> = ["g-1", "g-2", "g-3", "g-4", "g-5"]
        let neu = bestand.neuesJahr(gruppen: alle, zuordnung: zuordnung, planung: "neu-herkunft", schuljahr: "2027/28",
                                    termine: .abDemNeuenSchuljahr,
                                    jetzt: s, ziele: ziele, zeilen: neueZeilen)
        func g(_ id: String) -> Lerngruppe? { neu.lerngruppen.first { $0.id == id } }
        #expect(g("g-1")?.name == "7a", "„6a“ heißt „7a“")
        #expect(g("g-1")?.zeilen == [Zeilenbindung(planung: "neu-herkunft", klasseId: "n-1")],
                "die gewählte Zeile ersetzt die übernommene")
        #expect(g("g-2")?.name == "7a" && g("g-2")?.zeilen.map(\.klasseId) == ["n-2"],
                "an der Klassenleitung")
        #expect(g("g-3")?.name == "7b", "leerer Name: der bisherige")
        // AT9 (Modell): Die Wahl ist vollständig (E650) — bis dahin blieb die weitere übernommene (E310).
        #expect(g("g-3")?.zeilen.isEmpty == true, "„Keine Zeile“: Auch die weitere übernommene geht")
        #expect(g("g-5")?.zeilen.map(\.klasseId) == ["n-6"], "gewählt: die Zeile einer anderen Gruppe")
        #expect(g("g-4")?.zeilen.map(\.klasseId) == ["n-6"], "ohne Wahl behält sie ihre übernommene — auch wenn eine andere sie wählt (E670)")

        let ohne = bestand.neuesJahr(gruppen: alle, zuordnung: zuordnung, planung: "neu-herkunft", schuljahr: "2027/28",
                                     termine: .abDemNeuenSchuljahr,
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
        let g = gruppe("g-1", "G6a")
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

    // AT9 (Modell): Den Haken gibt es nicht mehr (E657) — mit kommt, wer eine Zeile trägt; bis dahin E312.
    @Test("Am Menü einer Zeile im Bogen: Eine Lerngruppe kommt hinzu oder geht — keiner anderen wird etwas genommen (E670, E675); mit kommt, wer eine Zeile trägt; Name und Schalter legen selbst keine Zeile fest (E657, Z14c2-09)")
    func menueDerZeile() {
        var w = Hochstufungswahl()
        w.zeileGeben("n-1", an: "g-3", zuteilung: ["g-1": ["n-1"], "g-2": ["n-3"]])
        #expect(w.zeilen == ["g-3": ["n-1"]], "die Zeile kommt dazu; „g-1“ behält sie")
        #expect(Hochstufung.mitkommend(["g-1": ["n-1"], "g-2": [], "g-3": ["n-1"]]) == ["g-1", "g-3"],
                "ohne Zeile kommt „g-2“ nicht mit")
        w.zeileNehmen("n-3", von: "g-2", zuteilung: ["g-1": ["n-1"], "g-2": ["n-3"], "g-3": ["n-1"]])
        #expect(w.zeilen["g-2"] == [], "abgewählt: keine Zeile")
        let g1 = gruppe("g-1", "G6a")
        var n = Hochstufungswahl()
        n.nameSetzen("G7a", fuer: g1, stufen: 1)
        #expect(n.namen.isEmpty, "der angezeigte Name, ohne Änderung zurückgegeben: Nichts geschieht (Z14c2-09)")
        n.nameSetzen("G7b", fuer: g1, stufen: 1)
        #expect(n.namen == ["g-1": "G7b"])
        var s = Hochstufungswahl()
        s.hochstufenSetzen(false)
        #expect(s.hochstufen == false)
        #expect(n.zeilen.isEmpty && n.freieZeilen.isEmpty && s.zeilen.isEmpty && s.freieZeilen.isEmpty,
                "Name und Schalter ändern die Zuteilung nur über den Vorschlag, nicht von Hand")
    }

    @Test("Nach dem Wechsel ohne Wahl im Blatt: Eine übernommene Zeile bleibt bei allen, die sie trugen (E670, Z14c2-07); höchstens 20 Zeilen je Gruppe")
    func uebernommeneZeileBleibtBeiAllen() {
        let s = Self.stempel
        let alt = "alt-herkunft"
        func b(_ k: String) -> Zeilenbindung { Zeilenbindung(planung: alt, klasseId: k) }
        var bestand = Lernendenbestand.leer(planung: alt, schuljahr: "2026/27", jetzt: s)
        let viele = (1...20).map { "k-v\($0)" }
        bestand.lerngruppen = [gruppe("g-1", "6a", [b("k-1")]), gruppe("g-2", "6a", [b("k-1"), b("k-2")]),
                               gruppe("g-3", "7c", viele.map(b))]
        var zuordnung = ["k-1": "n-1", "k-2": "n-2"]
        for (i, k) in viele.enumerated() { zuordnung[k] = "n-v\(i + 1)" }
        // AT9 (Modell): Die Wahl ist vollständig (E650) — sie nennt die gewählte Zeile vorn und die übernommenen dahinter.
        let gewaehlt = ["n-x"] + viele.indices.map { "n-v\($0 + 1)" }
        let neu = bestand.neuesJahr(gruppen: ["g-1", "g-2", "g-3"], zuordnung: zuordnung, planung: "neu", schuljahr: "2027/28",
                                    termine: .abDemNeuenSchuljahr,
                                    jetzt: s, ziele: ["g-3": Gruppenziel(name: "8c", zeilen: gewaehlt)],
                                    zeilen: [klasse("n-x", "8c", "Physik")] + gewaehlt.dropFirst().map { klasse($0, "8c", "") })
        func g(_ id: String) -> Lerngruppe? { neu.lerngruppen.first { $0.id == id } }
        #expect(g("g-1")?.zeilen.map(\.klasseId) == ["n-1"])
        #expect(g("g-2")?.zeilen.map(\.klasseId) == ["n-1", "n-2"], "dieselbe übernommene Zeile: beide behalten sie")
        #expect(g("g-3")?.zeilen.count == Lernendendatei.maxZeilenJeGruppe && g("g-3")?.zeilen.first?.klasseId == "n-x",
                "die gewählte Zeile vorn, höchstens 20")
    }
}

// ── Bogen „Lerngruppen zuordnen“: das Zeilenmodell (v84, AT8, E382–E386) ──
// Links je aktive Lerngruppe, rechts je Zeile der neuen Planung, dazu die
// Zusammenfassung im Blatt — aus der Wahl, wie die Blätter sie rechnen: mit
// mehreren Zeilen je Gruppe (E649, E650), dem Menü einer Zeile (E649, E652)
// und ohne Haken (E657); die Suite „Mehrfachbindung“ prüft sie eigens.

@Suite("Bogen „Lerngruppen zuordnen“: Zeilenmodell (E382–E386)")
struct HochstufungZeilenmodellPruefungen {

    private typealias Gruppe = Hochstufung.Zeilenmodell.Gruppe
    private typealias Belegung = Hochstufung.Zeilenmodell.Belegung

    private static let stempel = "2026-10-05T08:00:00.000Z"

    private func gruppe(_ id: String, _ name: String, archiviert: String = "") -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: [], zeilen: [], skalen: [:],
                   halbjahreswechsel: "", geaendert: Self.stempel, archiviert: archiviert)
    }

    private func zeile(_ id: String, _ name: String, _ fach: String, _ art: Zeilenart = .unterricht) -> Hochstufung.Zeile {
        Hochstufung.Zeile(id: id, name: name, fach: fach, art: art, titel: name + (fach.isEmpty ? "" : " · " + fach))
    }

    /// Die neue Planung wie in der Suite oben: zwei Zeilen „G7a“, die Klassenleitung der G7a, „G8c · Informatik“.
    private var zeilen: [Hochstufung.Zeile] {
        [zeile("n-1", "G7a", "Informatik"), zeile("n-2", "G7a", "Mathematik"),
         zeile("n-3", "Klassenleitung", "G7a", .klassenleitung), zeile("n-4", "G8c", "Informatik")]
    }

    // Eine Stufe höher heißen g-1, g-2 und g-3 alle „G7a“ (doppelte Lerngruppen derselben Klasse); der Vorschlag gibt
    // jeder alle Zeilen ihres Namens (E650, E675). g-4 heißt „G8c“.
    private var kl: Lerngruppe { gruppe("g-2", "G6a") }
    private var bio: Lerngruppe { gruppe("g-3", "G6a") }
    private var inf: Lerngruppe { gruppe("g-1", "G6a") }
    private var c: Lerngruppe { gruppe("g-4", "G7c") }

    /// Eine „G6a“: alle Zeilen „G7a“, die erste nach dem Angebot (V11, E675).
    private static func alleG7a(_ id: String) -> Gruppe {
        Gruppe(id: id, kommtMit: true, bisher: "bisher G6a", name: "G7a", neuerName: "G7a", zeile: "n-1", ziel: "→ G7a · Informatik",
               weitere: ["G7a · Mathematik", "Klassenleitung · G7a"])
    }
    /// Eine weitere „G6a“ — ohne Zeile, sie kommt nicht mit (E657).
    private static func ohneZeile(_ id: String) -> Gruppe {
        Gruppe(id: id, kommtMit: false, bisher: "bisher G6a", name: "G7a", neuerName: "G7a", zeile: nil, ziel: "→ keine Zeile")
    }
    private static let cAnN4 = Gruppe(id: "g-4", kommtMit: true, bisher: "bisher G7c", name: "G8c", neuerName: "G8c",
                                      zeile: "n-4", ziel: "→ G8c · Informatik")

    /// Die Zuteilung, wie das Blatt „Neue Planung“ sie rechnet: Suchname aus der Wahl, von Hand Gewähltes zuerst,
    /// freie Zeilen („Keine Gruppe“) nimmt der Vorschlag nicht (E652).
    private func zuteilung(_ w: Hochstufungswahl, _ gruppen: [Lerngruppe],
                           uebernommen: [String: [String]] = [:]) -> [String: [String]] {
        Hochstufung.zuteilung(gruppen,
                              namen: Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, w.suchname($0, stufen: 1)) }),
                              uebernommen: uebernommen, zeilen: zeilen, gewaehlt: w.zeilen, frei: w.freieZeilen)
    }

    /// Am Menü des Bogens (E649, E652): eine Gruppe an eine Zeile — sie
    /// kommt hinzu; `""`: „Keine Gruppe“ an jeder ihrer Zeilen.
    private func waehlen(_ zeile: String, fuer gruppe: String, _ w: inout Hochstufungswahl, _ gruppen: [Lerngruppe],
                         uebernommen: [String: [String]] = [:]) {
        if zeile.isEmpty {
            for z in zuteilung(w, gruppen, uebernommen: uebernommen)[gruppe] ?? [] {
                loesen(z, &w, gruppen, uebernommen: uebernommen)
            }
        } else {
            let zugeteilt = zuteilung(w, gruppen, uebernommen: uebernommen)
            w.zeileGeben(zeile, an: gruppe, zuteilung: zugeteilt)
        }
    }

    /// „Keine Gruppe“ am Menü einer Zeile (E649, E652).
    private func loesen(_ zeile: String, _ w: inout Hochstufungswahl, _ gruppen: [Lerngruppe],
                        uebernommen: [String: [String]] = [:]) {
        let zugeteilt = zuteilung(w, gruppen, uebernommen: uebernommen)
        w.zeileLoesen(zeile, zuteilung: zugeteilt)
    }

    /// Das Modell, wie der Bogen es bekommt — wer mitkommt, aus der Zuteilung (E657).
    private func modell(_ w: Hochstufungswahl, _ gruppen: [Lerngruppe],
                        uebernommen: [String: [String]] = [:]) -> Hochstufung.Zeilenmodell {
        let zugeteilt = zuteilung(w, gruppen, uebernommen: uebernommen)
        return Hochstufung.zeilenmodell(
            gruppen, mitkommend: Hochstufung.mitkommend(zugeteilt),
            namen: Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, w.name($0, stufen: 1)) }),
            zeilen: zeilen, zuteilung: zugeteilt)
    }

    @Test("Vorschlag nach E311, E650 und E675: links Name, Ziel und weitere Zeilen, wer mitkommt zuerst; rechts die Lerngruppen je Zeile")
    func vorschlag() {
        let m = modell(Hochstufungswahl(), [kl, inf, c])
        #expect(m.links == [Self.alleG7a("g-1"), Self.alleG7a("g-2"), Self.cAnN4],
                "beide „G6a“ bekommen alle Zeilen „G7a“ (E675); in der Folge der Listen")
        #expect(m.rechts == [
            Belegung(id: "n-1", titel: "G7a · Informatik", gruppen: ["g-1", "g-2"], traeger: "← G6a, G6a", kommtMit: true),
            Belegung(id: "n-2", titel: "G7a · Mathematik", gruppen: ["g-1", "g-2"], traeger: "← G6a, G6a", kommtMit: true, weitere: true),
            Belegung(id: "n-3", titel: "Klassenleitung · G7a", gruppen: ["g-1", "g-2"], traeger: "← G6a, G6a", kommtMit: true,
                     weitere: true),
            Belegung(id: "n-4", titel: "G8c · Informatik", gruppen: ["g-4"], traeger: "← G7c", kommtMit: true),
        ], "in der Folge des Angebots; eine Zeile kann mehrere Lerngruppen tragen (E670)")
        #expect(m.zusammenfassung == "3 von 3 Lerngruppen zugeordnet")
    }

    @Test("Eine Gruppe ohne Zeile: „Keine Gruppe“ an ihren Zeilen — die Zeilen bleiben frei, die Gruppe kommt nicht mit (E652, E657)")
    func ohneZeile() {
        let gruppen = [kl, inf, c]
        var w = Hochstufungswahl()
        waehlen("", fuer: "g-2", &w, gruppen)
        let m = modell(w, gruppen)
        #expect(m.links == [Self.cAnN4, Self.ohneZeile("g-1"), Self.ohneZeile("g-2")])
        #expect(m.rechts.map(\.gruppen.first) == [nil, nil, nil, "g-4"], "die Zeilen „G7a“ sind frei — „Keine Gruppe“ nahm sie beiden „G6a“ (E652, E675)")
        #expect(w.freieZeilen == ["n-1", "n-2", "n-3"])
        #expect(m.zusammenfassung == "1 von 3 Lerngruppen zugeordnet")
    }

    // AT9 (Modell): statt der Haken (E382 b, E312) — wer eine Zeile trägt, kommt mit (E657).
    @Test("Links alle aktiven: wer mitkommt zuerst, die übrigen dahinter — sie kommen nicht mit; archivierte fehlen; gezählt werden alle aktiven (E382 b, E657)")
    func nichtMit() {
        let archiviert = gruppe("g-9", "G9z", archiviert: Self.stempel)
        // Eine Lerngruppe ohne Zeile ihres Namens, etwa eine AG (E657).
        let ag = gruppe("g-3", "Bio-AG")
        let gruppen = [c, inf, archiviert, ag, kl]
        var w = Hochstufungswahl()
        let m = modell(w, gruppen)
        let agOhne = Gruppe(id: "g-3", kommtMit: false, bisher: "bisher Bio-AG", name: "Bio-AG", neuerName: "Bio-AG", zeile: nil,
                            ziel: "→ keine Zeile")
        #expect(m.links == [Self.alleG7a("g-1"), Self.alleG7a("g-2"), Self.cAnN4, agOhne],
                "ohne Zeile kommt die „Bio-AG“ nicht mit — hinter den übrigen; die Folge ordnet das Modell")
        #expect(m.zusammenfassung == "3 von 4 Lerngruppen zugeordnet")
        waehlen("", fuer: "g-4", &w, gruppen)
        let n = modell(w, gruppen)
        #expect(n.links.map(\.id) == ["g-1", "g-2", "g-3", "g-4"] && n.links.map(\.kommtMit) == [true, true, false, false],
                "ohne Zeile kommt auch „G7c“ nicht mit — die übrigen in der Folge der Listen")
        #expect(n.rechts.last == Belegung(id: "n-4", titel: "G8c · Informatik", gruppen: [], traeger: nil, kommtMit: false))
        #expect(n.zusammenfassung == "2 von 4 Lerngruppen zugeordnet")
    }

    @Test("Zeile geben an eine weitere Lerngruppe: Die bisherige behält sie, rechts stehen beide (E649, E670, E675)")
    func zeileGebenAnWeitere() {
        let gruppen = [kl, bio, inf, c]
        var w = Hochstufungswahl()
        waehlen("n-4", fuer: "g-3", &w, gruppen)
        let m = modell(w, gruppen)
        #expect(m.links == [Self.alleG7a("g-1"), Self.alleG7a("g-2"),
                            Gruppe(id: "g-3", kommtMit: true, bisher: "bisher G6a", name: "G7a", neuerName: "G7a", zeile: "n-1",
                                   ziel: "→ G7a · Informatik",
                                   weitere: ["G7a · Mathematik", "Klassenleitung · G7a", "G8c · Informatik"]),
                            Self.cAnN4], "„G7c“ behält ihre Zeile; g-3 bekommt sie dazu")
        #expect(m.rechts.last == Belegung(id: "n-4", titel: "G8c · Informatik", gruppen: ["g-3", "g-4"], traeger: "← G6a, G7c",
                                          kommtMit: true), "die erste von „G7c“ — darum keine weitere")
        #expect(m.zusammenfassung == "4 von 4 Lerngruppen zugeordnet")
    }

    // AT9 (Modell): ohne den Fachhinweis; das neue Jahr setzt kein Fach (E656) — bis dahin folgte es der Unterrichtszeile.
    @Test("Das neue Jahr nimmt Name und Zeile aus dem Bogen; das Fach bleibt an jeder Zeile (E310, E656)")
    func neuesJahrFach() {
        let s = Self.stempel
        let klassen = [Klasse(id: "n-1", name: "7a", fach: "Informatik", notiz: "", farbe: 0, farbeManuell: false, art: .unterricht),
                       Klasse(id: "n-2", name: "Klassenleitung", fach: "7b", notiz: "", farbe: 0, farbeManuell: false,
                              art: .klassenleitung),
                       Klasse(id: "n-3", name: "Weiteres", fach: "", notiz: "", farbe: 0, farbeManuell: false, art: .weiteres)]
        let angebot = klassen.map { Hochstufung.Zeile($0) }
        var bestand = Lernendenbestand.leer(planung: "alt", schuljahr: "2026/27", jetzt: s)
        bestand.lerngruppen = [gruppe("g-1", "6a"), gruppe("g-2", "6b"), gruppe("g-3", "6c")]
        let gruppen = bestand.lerngruppen
        let namen = ["g-1": "7a", "g-2": "7b", "g-3": "7c"]
        let zugeteilt = Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: [:], zeilen: angebot,
                                              gewaehlt: ["g-1": ["n-1"], "g-2": ["n-2"], "g-3": ["n-3"]])
        let m = Hochstufung.zeilenmodell(gruppen, mitkommend: Hochstufung.mitkommend(zugeteilt), namen: namen, zeilen: angebot,
                                         zuteilung: zugeteilt)
        #expect(m.links.map(\.ziel) == ["→ 7a · Informatik", "→ Klassenleitung · 7b", "→ Weiteres"])
        let ziele = Dictionary(uniqueKeysWithValues: m.links.filter(\.kommtMit).map {
            ($0.id, Gruppenziel(name: $0.name, zeilen: zugeteilt[$0.id] ?? []))
        })
        let neu = bestand.neuesJahr(gruppen: Set(ziele.keys), zuordnung: [:], planung: "neu", schuljahr: "2027/28",
                                    termine: .abDemNeuenSchuljahr, jetzt: s,
                                    ziele: ziele, zeilen: klassen)
        #expect(neu.lerngruppen.map(\.beschriftung) == ["7a", "7b", "7c"], "nur der Name — das Fach steht an der Zeile (E665)")
        #expect(neu.lerngruppen.map { $0.zeilen.map(\.klasseId) } == [["n-1"], ["n-2"], ["n-3"]], "die Zeilen aus dem Bogen")
    }

    @Test("Der neue Name, wie das neue Jahr ihn speichert (Z-AT8-02): Bereinigt, ein leeres Feld heißt der bisherige — das Feld bleibt, wie getippt")
    func neuerName() {
        let lang = String(repeating: "x", count: Planungsdatei.maxNamenslaenge + 5)
        let namen = ["g-1": "  ", "g-2": "  G7a  ", "g-4": lang]
        let m = Hochstufung.zeilenmodell([kl, inf, c], mitkommend: ["g-1", "g-2", "g-4"], namen: namen, zeilen: zeilen,
                                         zuteilung: [:])
        let links = Dictionary(uniqueKeysWithValues: m.links.map { ($0.id, $0) })
        #expect(links["g-1"]?.name == "  " && links["g-1"]?.neuerName == "G6a", "leer: der bisherige Name")
        #expect(links["g-2"]?.neuerName == "G7a", "ohne Leerraum am Rand")
        #expect(links["g-4"]?.neuerName.count == Planungsdatei.maxNamenslaenge, "gekürzt")
        // Derselbe Name, den das neue Jahr speichert.
        var bestand = Lernendenbestand.leer(planung: "alt", schuljahr: "2026/27", jetzt: Self.stempel)
        bestand.lerngruppen = [kl, inf, c]
        let ziele = Dictionary(uniqueKeysWithValues: m.links.map { ($0.id, Gruppenziel(name: $0.name, zeilen: [])) })
        let neu = bestand.neuesJahr(gruppen: Set(ziele.keys), zuordnung: [:], planung: "neu", schuljahr: "2027/28",
                                    termine: .abDemNeuenSchuljahr,
                                    jetzt: Self.stempel, ziele: ziele, zeilen: [])
        #expect(neu.lerngruppen.map(\.name).sorted() == m.links.map(\.neuerName).sorted())
    }

    @Test("Ränder (Z-AT8-05): leeres Angebot, eine Zeile, die das Angebot nicht kennt, Schlüssel einer neuen Zeile und eine Sonderzeile ohne Fach")
    func raender() {
        let leer = Hochstufung.zeilenmodell([inf, c], mitkommend: ["g-1", "g-4"], namen: [:], zeilen: [], zuteilung: [:])
        #expect(leer.rechts.isEmpty
                && leer.links.allSatisfy { $0.zeile == nil && $0.ziel == "→ keine Zeile" })
        #expect(leer.zusammenfassung == "keine Lerngruppe zugeordnet")
        let unbekannt = Hochstufung.zeilenmodell([inf], mitkommend: ["g-1"], namen: [:], zeilen: zeilen,
                                                 zuteilung: ["g-1": ["n-x"]])
        #expect(unbekannt.links.first?.zeile == nil && unbekannt.links.first?.ziel == "→ keine Zeile")
        #expect(unbekannt.rechts.allSatisfy { $0.gruppen.isEmpty })
        // Wie das Blatt „Neue Planung“ vor dem Anlegen: Schlüssel statt Kennungen.
        let neueZeile = Hochstufung.Zeile(id: "e:0", name: "G7a", fach: "Informatik", art: .unterricht,
                                          titel: "G7a · Informatik")
        let sonder = Hochstufung.Zeile(id: "s:klassenleitung", name: "Klassenleitung", fach: "", art: .klassenleitung,
                                       titel: "Klassenleitung")
        let m = Hochstufung.zeilenmodell([kl, inf], mitkommend: ["g-1", "g-2"], namen: [:], zeilen: [neueZeile, sonder],
                                         zuteilung: ["g-2": ["s:klassenleitung"], "g-1": ["e:0"]])
        #expect(m.links.map(\.ziel) == ["→ G7a · Informatik", "→ Klassenleitung"], "gleiche Namen: in der Folge der Kennung")
        #expect(m.rechts.map(\.gruppen.first) == ["g-1", "g-2"])
    }

    @Test("Zusammenfassung neben dem Knopf: „keine Lerngruppe zugeordnet“, sonst „k von n“ — der Plural folgt n")
    func zusammenfassung() {
        let faelle: [(Int, Int, String)] = [
            (0, 0, "keine Lerngruppe zugeordnet"), (0, 4, "keine Lerngruppe zugeordnet"),
            (1, 1, "1 von 1 Lerngruppe zugeordnet"), (1, 4, "1 von 4 Lerngruppen zugeordnet"),
            (3, 4, "3 von 4 Lerngruppen zugeordnet"), (4, 4, "4 von 4 Lerngruppen zugeordnet"),
        ]
        for (k, n, text) in faelle {
            #expect(Hochstufung.zusammenfassung(k, von: n) == text, "\(k) von \(n)")
        }
        var w = Hochstufungswahl()
        #expect(modell(w, [inf]).zusammenfassung == "1 von 1 Lerngruppe zugeordnet")
        waehlen("", fuer: "g-1", &w, [inf])
        #expect(modell(w, [inf]).zusammenfassung == "keine Lerngruppe zugeordnet", "ohne Zeile")
    }

    // AT9 (Modell): Nach E652 bleibt die Zeile frei — bis dahin rückte eine Gruppe mit derselben Vorgabe nach.
    @Test("„Keine Gruppe“ an einer Zeile: Alle Lerngruppen mit derselben Vorgabe verlieren sie, keine bekommt sie wieder (E652, E675)")
    func keineGruppeFuerAlle() {
        let zweite = gruppe("g-5", "G6a")
        let gruppen = [inf, zweite]
        var w = Hochstufungswahl()
        #expect(modell(w, gruppen).rechts.first?.gruppen == ["g-1", "g-5"], "zwei Vorgaben für dieselbe Zeile: beide (E675)")
        waehlen("", fuer: "g-1", &w, gruppen)
        let m = modell(w, gruppen)
        #expect(m.rechts.first == Belegung(id: "n-1", titel: "G7a · Informatik", gruppen: [], traeger: nil, kommtMit: false))
        #expect(m.links.map(\.id) == ["g-1", "g-5"] && m.links.map(\.kommtMit) == [false, false])
        #expect(m.zusammenfassung == "keine Lerngruppe zugeordnet")
    }

    @Test("„Keine Gruppe“ sperrt den Vorschlag (E652): Eine Lerngruppe, die die Zeile erst danach über ihren Namen bekäme, bekommt sie nicht — von Hand weiter (Z-AT9M-09, Z-AT9b-04)")
    func freiSperrtDenVorschlag() {
        let spaeter = gruppe("g-5", "G6b")
        let gruppen = [c, spaeter]
        var w = Hochstufungswahl()
        loesen("n-1", &w, gruppen)
        #expect(w.freieZeilen == ["n-1"] && w.zeilen.isEmpty, "niemand trug „n-1“ — nichts von Hand")
        w.nameSetzen("G7a", fuer: spaeter, stufen: 1)
        #expect(zuteilung(w, gruppen)["g-5"] == ["n-2", "n-3"], "die übrigen Zeilen „G7a“, nicht die freie")
        waehlen("n-1", fuer: "g-5", &w, gruppen)
        #expect(zuteilung(w, gruppen)["g-5"] == ["n-2", "n-3", "n-1"], "von Hand bekommt sie die freie")
    }

    // AT9 (Modell): statt der weiteren Bindungen nach E482 — die Bindungen aus dem Vorjahr sind Zeilen der Gruppe (E650).
    @Test("Bindungen aus dem Vorjahr (E650): als Zeilen der Gruppe im Vorschlag, rechts als weitere gekennzeichnet, links bei der Gruppe; lösbar; die erste Zeile einer anderen Gruppe geht vor")
    func vorjahrImBogen() {
        var mehrfach = inf
        mehrfach.zeilen = [Zeilenbindung(planung: "alt", klasseId: "o-1"), Zeilenbindung(planung: "alt", klasseId: "o-3"),
                           Zeilenbindung(planung: "fremd", klasseId: "o-2")]
        let zuordnung = ["o-1": "n-1", "o-3": "n-3", "o-2": "n-2"]
        let uebernommen = ["g-1": Hochstufung.uebernommeneZeilen(mehrfach, planung: "alt", zuordnung: zuordnung)]
        #expect(uebernommen["g-1"] == ["n-1", "n-3"], "eine Bindung aus fremder Planung zählt nicht")
        var w = Hochstufungswahl()
        let m = modell(w, [mehrfach], uebernommen: uebernommen)
        #expect(m.links.first?.zeile == "n-1" && m.links.first?.weitere == ["Klassenleitung · G7a", "G7a · Mathematik"],
                "die übernommenen zuerst, dann die übrigen gleichen Namens")
        #expect(m.rechts.map(\.gruppen.first) == ["g-1", "g-1", "g-1", nil] && m.rechts.map(\.weitere) == [false, true, true, false])
        #expect(m.zusammenfassung == "1 von 1 Lerngruppe zugeordnet")
        loesen("n-3", &w, [mehrfach], uebernommen: uebernommen)
        let geloest = modell(w, [mehrfach], uebernommen: uebernommen)
        #expect(geloest.links.first?.weitere == ["G7a · Mathematik"] && geloest.rechts[2].gruppen.first == nil,
                "am Menü der Klassenleitung „Keine Gruppe“: Nur sie ist gelöst")
        let mitLeitung = modell(Hochstufungswahl(), [mehrfach, kl], uebernommen: uebernommen)
        #expect(mitLeitung.rechts[2].gruppen.first == "g-1" && mitLeitung.rechts[2].weitere,
                "ohne Fach hat die zweite „G6a“ keine eigene erste Zeile — die Bindung aus dem Vorjahr behält die Klassenleitung")
        #expect(mitLeitung.links.first { $0.id == "g-1" }?.weitere == ["Klassenleitung · G7a", "G7a · Mathematik"])
        // Die erste Zeile einer anderen Gruppe geht einer weiteren Bindung vor (erst die Vorgabe, dann die übrigen Bindungen):
        // g-1 ohne Bindung bekommt „G7a · Informatik“, obwohl g-2 sie als zweite Bindung aus dem Vorjahr trägt.
        let folge = Hochstufung.zuteilung([gruppe("g-1", "G6a"), gruppe("g-2", "G6a")], namen: ["g-1": "G7a", "g-2": "G7a"],
                                          uebernommen: ["g-2": ["n-2", "n-1"]], zeilen: zeilen, gewaehlt: [:])
        #expect(folge == ["g-1": ["n-1", "n-2", "n-3"], "g-2": ["n-2", "n-1", "n-3"]],
                "je Gruppe ihre Folge — erst die übernommenen, dann die übrigen des Namens; keine nimmt der anderen etwas (E675)")
    }

    // AT9 (Modell): statt „Weitere Bindungen wie im neuen Jahr“ (E482) — dieselbe Zusage für mehrere Zeilen je Gruppe.
    @Test("Was der Bogen zeigt, entsteht im neuen Jahr — Vorschlag, gelöst, gegeben, mit Bindungen aus dem Vorjahr (E649, E650, E652)")
    func bogenWieDasNeueJahr() {
        let s = Self.stempel
        var mehrfach = inf
        mehrfach.zeilen = [Zeilenbindung(planung: "alt", klasseId: "o-1"), Zeilenbindung(planung: "alt", klasseId: "o-3")]
        var leitung = kl
        leitung.zeilen = [Zeilenbindung(planung: "alt", klasseId: "o-4")]
        let zuordnung = ["o-1": "n-1", "o-3": "n-3", "o-4": "n-4"]
        func klasse(_ id: String, _ name: String, _ fach: String, _ art: Zeilenart) -> Klasse {
            Klasse(id: id, name: name, fach: fach, notiz: "", farbe: 0, farbeManuell: false, art: art)
        }
        // Dieselben Zeilen wie `zeilen` oben.
        let klassen = [klasse("n-1", "G7a", "Informatik", .unterricht), klasse("n-2", "G7a", "Mathematik", .unterricht),
                       klasse("n-3", "Klassenleitung", "G7a", .klassenleitung), klasse("n-4", "G8c", "Informatik", .unterricht)]
        var bestand = Lernendenbestand.leer(planung: "alt", schuljahr: "2026/27", jetzt: s)
        bestand.lerngruppen = [mehrfach, leitung]
        let gruppen = bestand.lerngruppen.sorted(by: Lerngruppe.vorgehen)
        var uebernommen: [String: [String]] = [:]
        for g in gruppen {
            let folge = Hochstufung.uebernommeneZeilen(g, planung: "alt", zuordnung: zuordnung)
            if !folge.isEmpty { uebernommen[g.id] = folge }
        }
        var w = Hochstufungswahl()
        #expect(zuteilung(w, gruppen, uebernommen: uebernommen) == ["g-1": ["n-1", "n-3", "n-2"], "g-2": ["n-4", "n-1", "n-2", "n-3"]],
                "die Bindungen aus dem Vorjahr zuerst; die Zeilen „G7a“ an beide „G6a“ (E675)")
        var staende = [w]
        loesen("n-3", &w, gruppen, uebernommen: uebernommen)
        staende.append(w)
        waehlen("n-3", fuer: "g-2", &w, gruppen, uebernommen: uebernommen)
        staende.append(w)
        func titel(_ id: String) -> String? { klassen.first { $0.id == id }.map { Hochstufung.Zeile($0).titel } }
        for (nummer, stand) in staende.enumerated() {
            let zugeteilt = zuteilung(stand, gruppen, uebernommen: uebernommen)
            let m = modell(stand, gruppen, uebernommen: uebernommen)
            // Wie die Blätter beim Anlegen: Name und Zeilen je gewählter Gruppe aus der Zuteilung.
            let ziele = Dictionary(uniqueKeysWithValues: m.links.filter(\.kommtMit).map {
                ($0.id, Gruppenziel(name: $0.name, zeilen: zugeteilt[$0.id] ?? []))
            })
            let neu = bestand.neuesJahr(gruppen: Set(ziele.keys), zuordnung: zuordnung, planung: "neu", schuljahr: "2027/28",
                                        termine: .abDemNeuenSchuljahr,
                                        jetzt: s, ziele: ziele, zeilen: klassen)
            // Je Zeile alle Lerngruppen, die sie im neuen Jahr tragen (E670).
            var traeger: [String: Set<String>] = [:]
            for g in neu.lerngruppen { for b in g.zeilen { traeger[b.klasseId, default: []].insert(g.id) } }
            #expect(m.rechts.map { Set($0.gruppen) } == klassen.map { traeger[$0.id] ?? [] }, "Stand \(nummer)")
            for g in m.links where g.kommtMit {
                let imNeuenJahr = neu.lerngruppen.first { $0.id == g.id }?.zeilen.compactMap { titel($0.klasseId) } ?? []
                #expect([g.zeile].compactMap { $0 }.compactMap(titel) + g.weitere == imNeuenJahr, "Stand \(nummer), \(g.id)")
            }
        }
    }

    @Test("Zwei Gruppen mit derselben Bindung aus dem Vorjahr (Z-NF-01): Beide behalten sie — Bogen und neues Jahr gleich (E650, E670)")
    func geteilteVorjahresbindung() {
        let s = Self.stempel
        var a = inf        // g-1 — in der Jahresdatei hinter g-2, geordnet (nach der Kennung) davor
        a.zeilen = [Zeilenbindung(planung: "alt", klasseId: "o-1"), Zeilenbindung(planung: "alt", klasseId: "o-3")]
        var b = kl         // g-2
        b.zeilen = [Zeilenbindung(planung: "alt", klasseId: "o-4"), Zeilenbindung(planung: "alt", klasseId: "o-3")]
        let zuordnung = ["o-1": "n-1", "o-3": "n-3", "o-4": "n-4"]
        func klasse(_ id: String, _ name: String, _ fach: String, _ art: Zeilenart) -> Klasse {
            Klasse(id: id, name: name, fach: fach, notiz: "", farbe: 0, farbeManuell: false, art: art)
        }
        let klassen = [klasse("n-1", "G7a", "Informatik", .unterricht), klasse("n-3", "Klassenleitung", "G7a", .klassenleitung),
                       klasse("n-4", "G8c", "Informatik", .unterricht)]
        let angebot = klassen.map { Hochstufung.Zeile($0) }
        var bestand = Lernendenbestand.leer(planung: "alt", schuljahr: "2026/27", jetzt: s)
        bestand.lerngruppen = [b, a]
        let geordnet = bestand.lerngruppen.sorted(by: Lerngruppe.vorgehen)
        #expect(geordnet.map(\.id) == ["g-1", "g-2"], "das Blatt ordnet gleiche Namen nach der Kennung — anders als die Jahresdatei")
        var uebernommen: [String: [String]] = [:]
        for g in geordnet { uebernommen[g.id] = Hochstufung.uebernommeneZeilen(g, planung: "alt", zuordnung: zuordnung) }
        // Die bisherigen Namen — keiner trägt eine Zeile; es zählen nur die Bindungen.
        let zugeteilt = Hochstufung.zuteilung(geordnet, namen: [:], uebernommen: uebernommen, zeilen: angebot, gewaehlt: [:])
        #expect(zugeteilt == ["g-1": ["n-1", "n-3"], "g-2": ["n-4", "n-3"]])
        let m = Hochstufung.zeilenmodell(geordnet, mitkommend: ["g-1", "g-2"], namen: [:], zeilen: angebot, zuteilung: zugeteilt)
        let ziele = Dictionary(uniqueKeysWithValues: m.links.map {
            ($0.id, Gruppenziel(name: $0.name, zeilen: zugeteilt[$0.id] ?? []))
        })
        let neu = bestand.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: zuordnung, planung: "neu", schuljahr: "2027/28",
                                    termine: .abDemNeuenSchuljahr,
                                    jetzt: s, ziele: ziele, zeilen: klassen)
        var traeger: [String: Set<String>] = [:]
        for g in neu.lerngruppen { for bindung in g.zeilen { traeger[bindung.klasseId, default: []].insert(g.id) } }
        #expect(traeger["n-3"] == ["g-1", "g-2"], "beide tragen die geteilte Bindung (E670)")
        #expect(m.rechts.map { Set($0.gruppen) } == klassen.map { traeger[$0.id] ?? [] })
        // Auch links: je Gruppe die Zeilen, die sie im neuen Jahr trägt — in ihrer Folge.
        func titel(_ id: String) -> String? { klassen.first { $0.id == id }.map { Hochstufung.Zeile($0).titel } }
        for g in m.links {
            let imNeuenJahr = neu.lerngruppen.first { $0.id == g.id }?.zeilen.compactMap { titel($0.klasseId) } ?? []
            #expect([g.zeile].compactMap { $0 }.compactMap(titel) + g.weitere == imNeuenJahr, "\(g.id)")
        }
        #expect(m.zusammenfassung == "2 von 2 Lerngruppen zugeordnet")
    }
}
