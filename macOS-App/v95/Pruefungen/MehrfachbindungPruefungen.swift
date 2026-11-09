// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Eine Lerngruppe an mehreren Zeilen (v84, AT9 (Modell), E625, E649, E650, E652) ──
// Der Vorschlag beim Jahreswechsel gibt einer Gruppe alle Zeilen ihres
// neuen Namens (auch allen gleichnamigen, E675), dazu die Klassenleitung ihrer Klasse und die Bindungen aus dem
// Vorjahr — erst je Gruppe die erste (die übernommene, sonst die erste des Angebots, V11), dann die weiteren. Am Menü einer
// Zeile kommt eine Gruppe hinzu, „Keine Gruppe“ löst nur diese Zeile und lässt
// sie frei. Ein Fach setzt der Wechsel nicht (E656); mit kommt, wer eine Zeile
// trägt oder im Import erkannt ist (E657).

@Suite("Eine Lerngruppe an mehreren Zeilen (E625, E649, E650, E652)")
struct MehrfachbindungPruefungen {

    private static let stempel = "2026-10-15T08:00:00.000Z"

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

    /// Das Beispiel zu E650: „G7a · Biologie“, „G7a · Informatik“, die Klassenleitung der G7a, „G7b · Biologie“.
    private var zeilen: [Hochstufung.Zeile] {
        [zeile("n-1", "G7a", "Biologie"), zeile("n-2", "G7a", "Informatik"),
         zeile("n-3", "Klassenleitung", "G7a", .klassenleitung), zeile("n-4", "G7b", "Biologie")]
    }

    // Vier Lerngruppen „G6a“ (doppelte Lerngruppen derselben Klasse, ohne Fach); eine Stufe höher heißen alle „G7a“.
    private var bio: Lerngruppe { gruppe("g-1", "G6a") }
    private var inf: Lerngruppe { gruppe("g-2", "G6a") }
    private var chemie: Lerngruppe { gruppe("g-3", "G6a") }
    private var kl: Lerngruppe { gruppe("g-4", "G6a") }

    /// Wie die Blätter rechnen: Suchname aus der Wahl, von Hand Festgelegtes und freie Zeilen.
    private func zuteilung(_ w: Hochstufungswahl, _ gruppen: [Lerngruppe],
                           uebernommen: [String: [String]] = [:]) -> [String: [String]] {
        Hochstufung.zuteilung(gruppen,
                              namen: Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, w.suchname($0, stufen: 1)) }),
                              uebernommen: uebernommen, zeilen: zeilen, gewaehlt: w.zeilen, frei: w.freieZeilen)
    }

    /// Am Menü einer Zeile eine Gruppe wählen (E649).
    private func geben(_ zeile: String, an gruppe: String, _ w: inout Hochstufungswahl, _ gruppen: [Lerngruppe],
                       uebernommen: [String: [String]] = [:]) {
        let z = zuteilung(w, gruppen, uebernommen: uebernommen)
        w.zeileGeben(zeile, an: gruppe, zuteilung: z)
    }

    /// „Keine Gruppe“ am Menü einer Zeile (E649, E652).
    private func loesen(_ zeile: String, _ w: inout Hochstufungswahl, _ gruppen: [Lerngruppe],
                        uebernommen: [String: [String]] = [:]) {
        let z = zuteilung(w, gruppen, uebernommen: uebernommen)
        w.zeileLoesen(zeile, zuteilung: z)
    }

    /// Das Modell, wie der Bogen es bekommt.
    private func modell(_ w: Hochstufungswahl, _ gruppen: [Lerngruppe]) -> Hochstufung.Zeilenmodell {
        let z = zuteilung(w, gruppen)
        return Hochstufung.zeilenmodell(
            gruppen, mitkommend: Hochstufung.mitkommend(z),
            namen: Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, w.name($0, stufen: 1)) }),
            zeilen: zeilen, zuteilung: z)
    }

    @Test("Vorschlag am Beispiel (E650): „G7a“ an „G7a · Biologie“, „G7a · Informatik“ und der Klassenleitung; „G7b · Biologie“ bleibt frei")
    func vorschlagAmBeispiel() {
        #expect(zuteilung(Hochstufungswahl(), [bio]) == ["g-1": ["n-1", "n-2", "n-3"]],
                "zuerst die erste Zeile des Namens (V11), dann die übrigen gleichen Namens in der Folge des Angebots")
    }

    @Test("Zwei Lerngruppen gleichen Namens: Der Vorschlag gibt jeder alle Zeilen ihres Namens — in jeder Folge (E650, E675)")
    func ersteDannWeitere() {
        let alle = ["n-1", "n-2", "n-3"]
        #expect(zuteilung(Hochstufungswahl(), [bio, inf]) == ["g-1": alle, "g-2": alle])
        #expect(zuteilung(Hochstufungswahl(), [inf, bio]) == ["g-1": alle, "g-2": alle], "die Folge ändert nichts")
    }

    @Test("Die erste Zeile ohne Fach: die erste des Angebots, dann die übrigen gleichen Namens (V11, E650)")
    func ohneEindeutigeErste() {
        #expect(Hochstufung.vorgabe(name: "G7a", uebernommen: nil, zeilen: zeilen) == "n-1",
                "mehrere Zeilen des Namens: die erste des Angebots")
        #expect(zuteilung(Hochstufungswahl(), [chemie]) == ["g-3": ["n-1", "n-2", "n-3"]])
    }

    @Test("Bindungen aus dem Vorjahr: alle übernommenen im Vorschlag, die erste zuerst — lösbar wie jede Zeile (E650)")
    func vorjahresbindungen() {
        var g = bio
        g.zeilen = [Zeilenbindung(planung: "alt", klasseId: "o-2"), Zeilenbindung(planung: "alt", klasseId: "o-9"),
                    Zeilenbindung(planung: "alt", klasseId: "o-4"), Zeilenbindung(planung: "alt", klasseId: "o-2"),
                    Zeilenbindung(planung: "fremd", klasseId: "o-1")]
        let zuordnung = ["o-2": "n-2", "o-4": "n-4", "o-1": "n-1"]
        let uebernommen = ["g-1": Hochstufung.uebernommeneZeilen(g, planung: "alt", zuordnung: zuordnung)]
        #expect(uebernommen["g-1"] == ["n-2", "n-4"],
                "in ihrer Folge, jede einmal; eine nicht übernommene und eine aus fremder Planung zählen nicht")
        var w = Hochstufungswahl()
        #expect(zuteilung(w, [g], uebernommen: uebernommen) == ["g-1": ["n-2", "n-4", "n-1", "n-3"]],
                "die übernommenen zuerst, dann die gleichen Namens in der Folge des Angebots")
        loesen("n-4", &w, [g], uebernommen: uebernommen)
        #expect(zuteilung(w, [g], uebernommen: uebernommen) == ["g-1": ["n-2", "n-1", "n-3"]], "gelöst wie jede Zeile")
    }

    @Test("Am Menü einer Zeile kommt die Gruppe hinzu — keiner anderen wird etwas genommen; eine Gruppe ohne Zeile kommt erst damit mit (E649, E657, E675)")
    func gebenKommtHinzu() {
        let gruppen = [bio, inf]
        var w = Hochstufungswahl()
        geben("n-4", an: "g-2", &w, gruppen)
        #expect(zuteilung(w, gruppen) == ["g-1": ["n-1", "n-2", "n-3"], "g-2": ["n-1", "n-2", "n-3", "n-4"]],
                "„G7b · Biologie“ kommt bei g-2 dazu; g-1 behält alles")
        #expect(Hochstufung.mitkommend(zuteilung(w, gruppen)) == ["g-1", "g-2"], "beide tragen eine Zeile und kommen mit")
        geben("n-4", an: "g-2", &w, gruppen)
        #expect(zuteilung(w, gruppen)["g-2"] == ["n-1", "n-2", "n-3", "n-4"], "eine Zeile, die die Gruppe schon trägt: Nichts ändert sich")
        // E657: Eine Gruppe ohne Zeile ihres Namens kommt erst mit, wenn sie am Menü eine Zeile bekommt.
        let ag = gruppe("g-5", "Bio-AG")
        var h = Hochstufungswahl()
        #expect(!Hochstufung.mitkommend(zuteilung(h, [bio, ag])).contains("g-5"), "ohne Zeile kommt die „Bio-AG“ nicht mit")
        geben("n-4", an: "g-5", &h, [bio, ag])
        #expect(Hochstufung.mitkommend(zuteilung(h, [bio, ag])).contains("g-5") && zuteilung(h, [bio, ag])["g-5"] == ["n-4"],
                "mit „G7b · Biologie“ kommt sie mit")
    }

    @Test("„Keine Gruppe“ löst nur diese Zeile; die nächste wird die erste; Umziehen in zwei Griffen (E649)")
    func loesenNurDiese() {
        let gruppen = [bio]
        var w = Hochstufungswahl()
        loesen("n-1", &w, gruppen)
        #expect(zuteilung(w, gruppen) == ["g-1": ["n-2", "n-3"]], "nur „G7a · Biologie“ ist gelöst")
        #expect(Hochstufung.mitkommend(zuteilung(w, gruppen)) == ["g-1"], "sie kommt weiter mit")
        let m = modell(w, gruppen)
        #expect(m.links.first?.ziel == "→ G7a · Informatik", "„G7a · Informatik“ ist jetzt die erste")
        geben("n-4", an: "g-1", &w, gruppen)
        loesen("n-2", &w, gruppen)
        #expect(zuteilung(w, gruppen) == ["g-1": ["n-3", "n-4"]], "von „G7a · Informatik“ nach „G7b · Biologie“")
    }

    @Test("„Keine Gruppe“: Keine Lerngruppe trägt die Zeile, auch wenn ein Vorschlag sie gäbe; die Wahl einer Lerngruppe gibt sie nur dieser (E652, E675)")
    func keineGruppeBleibtFrei() {
        let gruppen = [inf, kl]
        var w = Hochstufungswahl()
        #expect(zuteilung(w, gruppen) == ["g-2": ["n-1", "n-2", "n-3"], "g-4": ["n-1", "n-2", "n-3"]])
        loesen("n-2", &w, gruppen)
        #expect(zuteilung(w, gruppen) == ["g-2": ["n-1", "n-3"], "g-4": ["n-1", "n-3"]],
                "„G7a · Informatik“ trägt keine mehr — beide verlieren nur sie")
        #expect(w.freieZeilen == ["n-2"])
        geben("n-2", an: "g-4", &w, gruppen)
        #expect(zuteilung(w, gruppen) == ["g-2": ["n-1", "n-3"], "g-4": ["n-1", "n-3", "n-2"]] && w.freieZeilen == ["n-2"],
                "von Hand nur g-4 — für den Vorschlag bleibt sie frei")
    }

    @Test("Im Bogen: links die erste Zeile und die weiteren, rechts die weiteren gekennzeichnet; gezählt wird jede Gruppe mit einer Zeile (E649)")
    func zeilenmodellMehrereZeilen() {
        let m = modell(Hochstufungswahl(), [bio, inf])
        #expect(m.links.map(\.id) == ["g-1", "g-2"])
        #expect(m.links.first?.zeile == "n-1" && m.links.first?.ziel == "→ G7a · Biologie"
                && m.links.first?.weitere == ["G7a · Informatik", "Klassenleitung · G7a"])
        #expect(m.links.last?.zeile == "n-1" && m.links.last?.weitere == ["G7a · Informatik", "Klassenleitung · G7a"],
                "die zweite „G6a“ ebenso (E675)")
        #expect(m.rechts.map(\.gruppen) == [["g-1", "g-2"], ["g-1", "g-2"], ["g-1", "g-2"], []])
        #expect(m.rechts.map(\.weitere) == [false, true, true, false])
        #expect(m.zusammenfassung == "2 von 2 Lerngruppen zugeordnet")
    }

    // AT9 (Modell): Das neue Jahr setzt kein Fach (E656) — bis dahin folgte es der Unterrichtszeile (E313).
    @Test("Das neue Jahr bindet alle gewählten Zeilen; was die Wahl nicht nennt, geht (E649, E650, E656)")
    func neuesJahrMehrereZeilen() {
        let s = Self.stempel
        func b(_ k: String) -> Zeilenbindung { Zeilenbindung(planung: "alt", klasseId: k) }
        var bestand = Lernendenbestand.leer(planung: "alt", schuljahr: "2026/27", jetzt: s)
        bestand.lerngruppen = [gruppe("g-1", "G6a", [b("o-1"), b("o-9")]), gruppe("g-2", "G6a"),
                               gruppe("g-3", "6c")]
        let zuordnung = ["o-1": "n-1", "o-9": "n-9"]
        let klassen = [klasse("n-1", "G7a", "Biologie"), klasse("n-2", "G7a", "Informatik"),
                       klasse("n-3", "Klassenleitung", "G7a", .klassenleitung), klasse("n-4", "G7b", "Biologie"),
                       klasse("n-6", "Weiteres", "", .weiteres), klasse("n-7", "7c", "Musik"), klasse("n-9", "AG", "Robotik")]
        let ziele = ["g-1": Gruppenziel(name: "G7a", zeilen: ["n-1", "n-2", "n-3"]),
                     "g-2": Gruppenziel(name: "G7a", zeilen: ["n-2", "n-4"]),
                     "g-3": Gruppenziel(name: "7c", zeilen: ["n-6", "n-7"])]
        let neu = bestand.neuesJahr(gruppen: ["g-1", "g-2", "g-3"], zuordnung: zuordnung, planung: "neu",
                                    schuljahr: "2027/28",
                                    termine: .abDemNeuenSchuljahr, jetzt: s, ziele: ziele, zeilen: klassen)
        func g(_ id: String) -> Lerngruppe? { neu.lerngruppen.first { $0.id == id } }
        #expect(g("g-1")?.name == "G7a" && g("g-1")?.zeilen.map(\.klasseId) == ["n-1", "n-2", "n-3"],
                "alle drei; die Bindung an „AG · Robotik“ aus dem Vorjahr nennt die Wahl nicht — sie geht")
        #expect(g("g-1")?.zeilen.allSatisfy { $0.planung == "neu" } == true)
        #expect(g("g-2")?.zeilen.map(\.klasseId) == ["n-2", "n-4"], "„G7a · Informatik“ tragen beide (E670)")
        #expect(g("g-3")?.zeilen.map(\.klasseId) == ["n-6", "n-7"])
    }

    // ── Kein Fach im Wechsel, wer mitkommt, Grenzen der Wahl (E652, E656, E657) ──

    @Test("Das neue Jahr setzt kein Fach (E656, E665): An der Zeile „G7a · Informatik“ heißt die Lerngruppe „G7a“ — das Fach steht an der Zeile")
    func neuesJahrSetztKeinFach() {
        let s = Self.stempel
        var bestand = Lernendenbestand.leer(planung: "alt", schuljahr: "2026/27", jetzt: s)
        bestand.lerngruppen = [gruppe("g-1", "G6a"), gruppe("g-2", "G6b")]
        let klassen = [klasse("n-1", "G7a", "Informatik"), klasse("n-2", "G7b", "Informatik"), klasse("n-3", "G7a", "Biologie")]
        let ziele = ["g-1": Gruppenziel(name: "G7a", zeilen: ["n-1"]), "g-2": Gruppenziel(name: "G7b", zeilen: ["n-2"])]
        let neu = bestand.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: [:], planung: "neu", schuljahr: "2027/28",
                                    termine: .abDemNeuenSchuljahr, jetzt: s,
                                    ziele: ziele, zeilen: klassen)
        func g(_ id: String) -> Lerngruppe? { neu.lerngruppen.first { $0.id == id } }
        #expect(g("g-1")?.beschriftung == "G7a" && g("g-1")?.zeilen.map(\.klasseId) == ["n-1"], "„G7a“ — das Fach steht an der Zeile")
        #expect(g("g-2")?.beschriftung == "G7b" && g("g-2")?.zeilen.map(\.klasseId) == ["n-2"])
    }

    @Test("Im IServ-Import erkannt (E657): Eine Gruppe, deren neuer Name eine Klasse der Datei ist, kommt mit — auch ohne Zeile, sofern keine zweite so heißt; verglichen ohne Groß/Klein und Leerraum am Rand")
    func imImportErkannt() {
        let gruppen = [bio, gruppe("g-6", "G6b"), gruppe("g-7", "Bio-AG")]
        let namen = ["g-1": "G7a", "g-6": "G7b", "g-7": "Bio-AG"]
        #expect(Hochstufung.imImport(gruppen, namen: namen, klassen: [" g7a ", "G7B", "8c"]) == ["g-1", "g-6"],
                "die „Bio-AG“ steht nicht in der Datei")
        #expect(Hochstufung.imImport(gruppen, namen: namen, klassen: []) == [])
        #expect(Hochstufung.mitkommend(["g-1": ["n-1"], "g-7": []], importiert: ["g-6"]) == ["g-1", "g-6"],
                "mit einer Zeile oder im Import erkannt — sonst nicht")
    }

    @Test("Höchstens 20 Zeilen je Gruppe (Z-AT9M-04): Der Vorschlag hört bei 20 auf, „Zeile geben“ an eine volle Gruppe ändert nichts — wie das neue Jahr")
    func hoechstens20() {
        let viele = (1...25).map { zeile("v-\($0)", "G7a", "Fach \($0)") }
        let a = gruppe("g-1", "G6a"), b = gruppe("g-2", "G6a")
        let z = Hochstufung.zuteilung([a], namen: ["g-1": "G7a"], uebernommen: [:], zeilen: viele, gewaehlt: [:])
        #expect(z["g-1"]?.count == Lernendendatei.maxZeilenJeGruppe, "\(z["g-1"]?.count ?? 0) Zeilen")
        var w = Hochstufungswahl()
        w.zeileGeben("v-25", an: "g-1", zuteilung: z)
        #expect(w.zeilen.isEmpty && w.freieZeilen.isEmpty, "die volle Gruppe bekommt keine 21. Zeile — nichts ändert sich")
        // Je Lerngruppe höchstens 20: Beide bekommen dieselben 20, v-21 bis v-25 bleiben ohne Lerngruppe (E675).
        let zwei = Hochstufung.zuteilung([a, b], namen: ["g-1": "G7a", "g-2": "G7a"], uebernommen: [:], zeilen: viele,
                                         gewaehlt: [:])
        #expect(zwei["g-1"] == (1...20).map { "v-\($0)" } && zwei["g-2"] == (1...20).map { "v-\($0)" },
                "jede Lerngruppe höchstens 20 — der Vorschlag gibt beiden dieselben (E675)")
    }

    @Test("Heißen mehrere Lerngruppen hochgestuft gleich, gilt keine als im Import erkannt — es entscheiden die Zeilen (Z-AT9M-11)")
    func imImportNurEindeutig() {
        let a = gruppe("g-1", "G6a"), b = gruppe("g-2", "G6a")
        #expect(Hochstufung.imImport([a, b], namen: ["g-1": "G7a", "g-2": "G7a"], klassen: ["G7a"]) == [],
                "zwei „G7a“ — keine gilt als erkannt")
        #expect(Hochstufung.imImport([a, b], namen: ["g-1": "G7a", "g-2": "G7b"], klassen: ["G7a", "G7b"]) == ["g-1", "g-2"])
        let c = gruppe("g-3", "G6b")
        #expect(Hochstufung.imImport([a, b, c], namen: ["g-1": "G7a", "g-2": " g7A ", "g-3": "G7b"], klassen: ["G7a", "G7b"]) == ["g-3"],
                "„G7a“ und „ g7A “ sind derselbe Name; „G7b“ allein bleibt erkannt")
    }

    @Test("Am Menü der Zeilen eine Lerngruppe abwählen — keiner anderen wird etwas genommen, keine Zeile wird frei (E652, E670, E675)")
    func abwaehlenNimmtNichts() {
        let gruppen = [inf, kl]
        var w = Hochstufungswahl()
        #expect(zuteilung(w, gruppen) == ["g-2": ["n-1", "n-2", "n-3"], "g-4": ["n-1", "n-2", "n-3"]])
        w.zeileNehmen("n-1", von: "g-2", zuteilung: zuteilung(w, gruppen))
        w.zeileNehmen("n-3", von: "g-2", zuteilung: zuteilung(w, gruppen))
        #expect(w.freieZeilen.isEmpty && zuteilung(w, gruppen) == ["g-2": ["n-2"], "g-4": ["n-1", "n-2", "n-3"]],
                "g-2 trägt nur noch „G7a · Informatik“ — g-4 behält alles")
        w.zeileNehmen("n-2", von: "g-2", zuteilung: zuteilung(w, gruppen))
        #expect(w.freieZeilen.isEmpty && zuteilung(w, gruppen) == ["g-4": ["n-1", "n-2", "n-3"]], "„Keine Zeile“ nur für g-2")
    }

    @Test("Von Hand Festgelegtes, dessen Zeilen teils verschwunden sind (Z-AT9M-09): Die übrigen gelten; sind alle verschwunden, gilt wieder der Vorschlag")
    func vonHandTeilsVerschwunden() {
        let teils = Hochstufung.zuteilung([bio], namen: ["g-1": "G7a"], uebernommen: [:], zeilen: zeilen,
                                          gewaehlt: ["g-1": ["n-weg", "n-4"]])
        #expect(teils == ["g-1": ["n-4"]], "von Hand nur „G7b · Biologie“ — kein Vorschlag dazu")
        let alle = Hochstufung.zuteilung([bio], namen: ["g-1": "G7a"], uebernommen: [:], zeilen: zeilen,
                                         gewaehlt: ["g-1": ["n-weg"]])
        #expect(alle == ["g-1": ["n-1", "n-2", "n-3"]])
    }

    @Test("Das neue Jahr bindet jede Zeile einer Gruppe einmal, auch wenn das Ziel sie doppelt nennt (Z-AT9M-09)")
    func neuesJahrDoppelt() {
        let s = Self.stempel
        var bestand = Lernendenbestand.leer(planung: "alt", schuljahr: "2026/27", jetzt: s)
        bestand.lerngruppen = [gruppe("g-1", "G6a")]
        let neu = bestand.neuesJahr(gruppen: ["g-1"], zuordnung: [:], planung: "neu", schuljahr: "2027/28",
                                    termine: .abDemNeuenSchuljahr, jetzt: s,
                                    ziele: ["g-1": Gruppenziel(name: "G7a", zeilen: ["n-1", "n-1", "n-2"])],
                                    zeilen: [klasse("n-1", "G7a", "Biologie"), klasse("n-2", "G7a", "Informatik")])
        #expect(neu.lerngruppen.first?.zeilen.map(\.klasseId) == ["n-1", "n-2"])
    }
}
