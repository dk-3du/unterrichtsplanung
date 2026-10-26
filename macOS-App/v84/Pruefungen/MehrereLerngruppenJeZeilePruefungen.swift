// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Mehrere Lerngruppen je Zeile (v84, AT9b; E670, E674–E676) ────────────────
// Eine Zeile kann mehreren Lerngruppen zugeordnet sein und eine Lerngruppe mehreren Zeilen. Verknüpfen fügt hinzu und nimmt
// keiner anderen Lerngruppe etwas; der Vorschlag beim Jahreswechsel gibt eine Zeile allen Lerngruppen gleichen neuen Namens.

@Suite("Mehrere Lerngruppen je Zeile: Verknüpfen, Lösen, Tische, Terminsuche, Jahreswechsel")
struct MehrereLerngruppenJeZeilePruefungen {

    private static let planung = "2026-08-10T09:00:00.000Z"
    private static let stempel = "2026-10-15T08:00:00.000Z"
    private static let z = Zeilenbindung(planung: planung, klasseId: "k-wpu")

    private static func gruppe(_ id: String, _ name: String, mitglieder: [String] = [], zeilen: [Zeilenbindung] = []) -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: mitglieder, zeilen: zeilen, skalen: [:],
                   halbjahreswechsel: "", geaendert: stempel, archiviert: "")
    }

    private static func bestand(_ gruppen: [Lerngruppe]) -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: planung, schuljahr: "2026/27", jetzt: stempel)
        let s = stempel
        b.lernende = ["l-1", "l-2", "l-3"].map { Lernender(id: $0, vorname: "V" + $0, nachname: "N" + $0, angelegt: s, geaendert: s,
                                                           archiviert: "") }
        b.lerngruppen = gruppen
        return b
    }

    @Test("E670: Eine zweite Lerngruppe an derselben Zeile kommt hinzu — die erste bleibt")
    func bindenFuegtHinzu() {
        let b = Self.bestand([Self.gruppe("g-1", "9a"), Self.gruppe("g-2", "9b")])
            .mitBindung("g-1", an: Self.z, jetzt: Self.stempel).mitBindung("g-2", an: Self.z, jetzt: Self.stempel)
        #expect(b.gruppen(an: Self.z).map(\.id) == ["g-1", "g-2"])
    }

    @Test("E670: „Bindung lösen“ an einer Lerngruppe löst nur sie von der Zeile")
    func loesenNurEine() {
        let b = Self.bestand([Self.gruppe("g-1", "9a", zeilen: [Self.z]), Self.gruppe("g-2", "9b", zeilen: [Self.z])])
        #expect(b.ohneBindung("g-1", an: Self.z, jetzt: Self.stempel).gruppen(an: Self.z).map(\.id) == ["g-2"])
    }

    @Test("E367 mit mehreren Lerngruppen: Der Tisch einer Person geht erst, wenn sie an der Zeile in keiner Lerngruppe mehr ist")
    func tischBleibtBeiVerbleib() {
        let vorher = Self.bestand([Self.gruppe("g-1", "9a", mitglieder: ["l-1", "l-2"], zeilen: [Self.z]),
                                   Self.gruppe("g-2", "9b", mitglieder: ["l-1"], zeilen: [Self.z])])
        var nachher = vorher
        nachher.lerngruppen[0].mitglieder = ["l-2"]
        #expect(Sitzplanfolgen(vorher: vorher, nachher: nachher, planung: Self.planung).entfernen["k-wpu"] == nil,
                "l-1 ist an der Zeile noch in „9b“")
        nachher.lerngruppen[1].mitglieder = []
        #expect(Sitzplanfolgen(vorher: vorher, nachher: nachher, planung: Self.planung).entfernen["k-wpu"] == ["l-1"])
    }

    @Test("Terminsuche: zuerst die Mitglieder aller Lerngruppen der Zeile")
    func terminsucheZuerst() {
        let b = Self.bestand([Self.gruppe("g-1", "9a", mitglieder: ["l-1"], zeilen: [Self.z]),
                              Self.gruppe("g-2", "9b", mitglieder: ["l-2"], zeilen: [Self.z]),
                              Self.gruppe("g-3", "AG", mitglieder: ["l-3"])])
        #expect(VorhabenDialog.zuerst(b, planung: Self.planung, klasseId: "k-wpu") == ["l-1", "l-2"])
    }

    // ── Jahreswechsel (E675) ──

    private static let angebot = [Hochstufung.Zeile(id: "n-1", name: "G7a", fach: "Biologie", art: .unterricht, titel: "G7a · Biologie"),
                                  Hochstufung.Zeile(id: "n-2", name: "G7a", fach: "Informatik", art: .unterricht, titel: "G7a · Informatik"),
                                  Hochstufung.Zeile(id: "n-3", name: "Klassenleitung", fach: "G7a", art: .klassenleitung,
                                                    titel: "Klassenleitung · G7a")]

    private static func zuteilung(_ w: Hochstufungswahl, _ gruppen: [Lerngruppe]) -> [String: [String]] {
        Hochstufung.zuteilung(gruppen, namen: Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, w.suchname($0, stufen: 1)) }),
                              uebernommen: [:], zeilen: angebot, gewaehlt: w.zeilen, frei: w.freieZeilen)
    }

    @Test("E675: Der Vorschlag gibt eine Zeile allen Lerngruppen gleichen neuen Namens")
    func vorschlagAlleGleichenNamens() {
        let gruppen = [Self.gruppe("g-1", "G6a"), Self.gruppe("g-2", "G6a")]
        #expect(Self.zuteilung(Hochstufungswahl(), gruppen) == ["g-1": ["n-1", "n-2", "n-3"], "g-2": ["n-1", "n-2", "n-3"]])
    }

    @Test("E675: Am Menü einer Zeile kommt eine Lerngruppe hinzu — keiner anderen wird etwas genommen")
    func gebenNimmtNichts() {
        let gruppen = [Self.gruppe("g-1", "G6a"), Self.gruppe("g-3", "Bio-AG")]
        var w = Hochstufungswahl()
        w.zeileGeben("n-1", an: "g-3", zuteilung: Self.zuteilung(w, gruppen))
        #expect(Self.zuteilung(w, gruppen) == ["g-1": ["n-1", "n-2", "n-3"], "g-3": ["n-1"]])
    }

    @Test("E670: Im Bogen „G7a“ von einer Zeile abwählen, die auch „Bio-AG“ trägt — „Bio-AG“ behält sie")
    func abwaehlenLaesstAndere() {
        let gruppen = [Self.gruppe("g-1", "G6a"), Self.gruppe("g-3", "Bio-AG")]
        var w = Hochstufungswahl()
        w.zeileGeben("n-1", an: "g-3", zuteilung: Self.zuteilung(w, gruppen))
        w.zeileNehmen("n-1", von: "g-1", zuteilung: Self.zuteilung(w, gruppen))
        #expect(Self.zuteilung(w, gruppen) == ["g-1": ["n-2", "n-3"], "g-3": ["n-1"]])
    }

    @Test("E670, E675: Im neuen Jahr tragen beide Lerngruppen die Zeile, die beide gewählt haben")
    func neuesJahrMehrere() {
        let b = Self.bestand([Self.gruppe("g-1", "G6a", mitglieder: ["l-1"]), Self.gruppe("g-2", "G6b", mitglieder: ["l-2"])])
        let klassen = [Klasse(id: "n-1", name: "WPU-9", fach: "Informatik", notiz: "", farbe: 0, farbeManuell: false, art: .unterricht)]
        let neu = b.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: [:], planung: "neu", schuljahr: "2027/28", jetzt: Self.stempel,
                              ziele: ["g-1": Gruppenziel(name: "G7a", zeilen: ["n-1"]), "g-2": Gruppenziel(name: "G7b", zeilen: ["n-1"])],
                              zeilen: klassen)
        #expect(neu.lerngruppen.map { $0.zeilen.map(\.klasseId) } == [["n-1"], ["n-1"]])
    }

    @Test("Eine Lerngruppe aus der Zeile heißt wie die Klasse/der Kurs — an der Klassenleitung wie ihre Klasse (Z-AT9b-02)")
    func lerngruppenname() {
        var leitung = Klasse.sonderzeile(.klassenleitung)
        #expect(Planungsspeicher.lerngruppenname(leitung) == "Klassenleitung", "ohne Klasse der Titel der Zeile")
        leitung.fach = " 6a "
        #expect(Planungsspeicher.lerngruppenname(leitung) == "6a")
        let kurs = Standardkurse.aufbauen([("WPU Bio", "Biologie")])[0]
        #expect(Planungsspeicher.lerngruppenname(kurs) == "WPU Bio")
    }

    @Test("E680: Die Kurszelle — „Nur „WPU Informatik““, „+ „WPU Informatik““ und „+ Lerngruppe“ mit den entschiedenen Hilfen")
    func kurszellentext() {
        let wpu = Self.gruppe("g-w", "WPU Informatik"), a = Self.gruppe("g-1", "9a"), b = Self.gruppe("g-2", "9b")
        let nur = Planungsspeicher.kurszellentext(.behalten(wpu), klasse: "WPU Informatik", gruppen: [wpu, a])
        #expect(nur.knopf == "Nur „WPU Informatik“")
        #expect(nur.bedienung == "Nur die Lerngruppe WPU Informatik an dieser Zeile behalten, statt 9a", "Z-AT15N-06")
        #expect(nur.hilfe == "An dieser Zeile: „WPU Informatik“, „9a“. Nur „WPU Informatik“ an dieser Zeile behalten — „9a“ geht "
                + "von dieser Zeile, an ihren anderen Zeilen bleibt sie")
        #expect(Planungsspeicher.kurszellentext(.behalten(wpu), klasse: "WPU Informatik", gruppen: [wpu, a, b]).hilfe
                .hasSuffix("— „9a“, „9b“ gehen von dieser Zeile, an ihren anderen Zeilen bleiben sie"))
        let dazu = Planungsspeicher.kurszellentext(.verknuepfen(wpu), klasse: "WPU Informatik", gruppen: [a, b])
        #expect(dazu.knopf == "+ „WPU Informatik“")
        #expect(dazu.bedienung == "Die Lerngruppe WPU Informatik mit dieser Zeile verknüpfen, statt 9a, 9b")
        #expect(dazu.hilfe == "An dieser Zeile: „9a“, „9b“. Die Lerngruppe „WPU Informatik“ mit dieser Zeile verknüpfen — sie "
                + "ersetzt „9a“, „9b“ an dieser Zeile, an ihren anderen Zeilen bleiben sie")
        let neu = Planungsspeicher.kurszellentext(.anlegen, klasse: "WPU Informatik", gruppen: [a, b])
        #expect(neu.knopf == "+ Lerngruppe" && neu.hilfe.hasPrefix("An dieser Zeile: „9a“, „9b“. Eine eigene Lerngruppe für "))
    }

    @Test("E700: Nach dem Klick in der Kurszelle sagt ein Hinweis, welche Lerngruppen die Zeile verloren haben")
    func kurszellenhinweis() {
        let wpu = Self.gruppe("g-w", "WPU Informatik"), a = Self.gruppe("g-1", "9a"), b = Self.gruppe("g-2", "9b")
        let zeile = "WPU Informatik · Informatik"
        #expect(Planungsspeicher.kurszellenhinweis(.verknuepfen(wpu), gruppen: [a, b], zeile: zeile)
                == "„9a“, „9b“ sind von der Zeile „WPU Informatik · Informatik“ gelöst — an ihren anderen Zeilen bleiben sie.")
        #expect(Planungsspeicher.kurszellenhinweis(.behalten(wpu), gruppen: [wpu, a], zeile: zeile)
                == "„9a“ ist von der Zeile „WPU Informatik · Informatik“ gelöst — an ihren anderen Zeilen bleibt sie.")
        #expect(Planungsspeicher.kurszellenhinweis(.anlegen, gruppen: [a, b], zeile: zeile)?.hasPrefix("„9a“, „9b“ sind von") == true)
        #expect(Planungsspeicher.kurszellenhinweis(.behalten(wpu), gruppen: [wpu], zeile: zeile) == nil, "nichts gelöst")
    }

    @Test("Sitzplan bei mehreren Lerngruppen (E674): Die Hilfe nennt sie und den Weg über die Kurszelle (Z-AT9b-01, E691)")
    func sitzplanhilfe() {
        let a = Self.gruppe("g-1", "9a"), b = Self.gruppe("g-2", "9b")
        #expect(SitzplanDialog.gruppenhilfe(nil, plaetze: 0, gebunden: [a, b])
                == "Mit dieser Zeile sind mehrere Lerngruppen verknüpft („9a“, „9b“) — für den Sitzplan in der Kurszelle eine "
                + "Lerngruppe für diese Zeile festlegen")
        #expect(SitzplanDialog.gruppenhilfe(nil, plaetze: 0, gebunden: [])
                == "An diese Zeile ist keine Lerngruppe gebunden — binden unter „Lernende, Klassen/Kurse und Fächer“ (⌘K)")
        #expect(SitzplanDialog.gruppenhilfe(a, plaetze: 3, gebunden: [a]) == "Die 3 Mitglieder von „9a“ als Tische anordnen (⇧⌘L)")
    }
}
