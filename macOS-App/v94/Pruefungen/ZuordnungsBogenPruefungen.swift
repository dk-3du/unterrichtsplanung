// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Bogen „Lerngruppen zuordnen“ (v84, AT9; E382–E388, E647, E652, E657, E670) ──
// Das Blatt „Neue Planung“ und das Blatt „Neues Schuljahr öffnen“ zeigen nur noch den Schalter, die Zusammenfassung und den
// Knopf; Namen und Zeilen stehen im Bogen (E383). Am Menü einer Zeile kommt eine Lerngruppe hinzu oder geht (E649, E670),
// „Keine Gruppe“ löst die Zeile (E652), „Vorschlag wiederherstellen“ nimmt, was von Hand geschah (E386).

@Suite("Bogen „Lerngruppen zuordnen“: Knopf, Vorschlag wiederherstellen, Menü der Zeile, Lagen, Fuß")
struct ZuordnungsBogenPruefungen {

    private static let stempel = "2026-10-15T20:00:00.000Z"

    private static func gruppe(_ id: String, _ name: String, archiviert: String = "") -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: [], zeilen: [], skalen: [:], halbjahreswechsel: "",
                   geaendert: stempel, archiviert: archiviert)
    }

    @Test("E647: Den Knopf „Lerngruppen zuordnen …“ gibt es nur verschlüsselt und mit aktiven Lerngruppen — an beiden Blättern, auch ⌘O ohne Lerngruppen nicht")
    func knopf() {
        #expect(LerngruppenWahl.knopfFrei(verschluesselt: true, gruppen: [Self.gruppe("g-1", "G6a")]))
        #expect(!LerngruppenWahl.knopfFrei(verschluesselt: false, gruppen: [Self.gruppe("g-1", "G6a")]), "im Klartext nicht")
        #expect(!LerngruppenWahl.knopfFrei(verschluesselt: true, gruppen: []), "ohne Lerngruppen nicht — auch an ⌘O")
        #expect(!LerngruppenWahl.knopfFrei(verschluesselt: true, gruppen: [Self.gruppe("g-1", "G6a", archiviert: Self.stempel)]),
                "nur archivierte: nicht")
    }

    @Test("E386: „Vorschlag wiederherstellen“ nimmt, was von Hand an den Zeilen geschah — Namen und Schalter bleiben")
    func vorschlagWiederherstellen() {
        var w = Hochstufungswahl()
        w.hochstufen = false
        w.namen = ["g-1": "7a"]
        w.zeilen = ["g-1": ["n-2"]]
        w.freieZeilen = ["n-1"]
        w.vorschlagWiederherstellen()
        #expect(w.zeilen.isEmpty && w.freieZeilen.isEmpty)
        #expect(w.namen == ["g-1": "7a"] && w.hochstufen == false)
    }

    @Test("E670: Am Menü einer Zeile eine Lerngruppe abwählen — nur sie verliert die Zeile, die übrigen behalten sie; nichts wird frei")
    func zeileNehmen() {
        var w = Hochstufungswahl()
        let zuteilung = ["g-1": ["n-1", "n-2"], "g-2": ["n-1"]]
        w.zeileNehmen("n-1", von: "g-1", zuteilung: zuteilung)
        #expect(w.zeilen == ["g-1": ["n-2"]] && w.freieZeilen.isEmpty)
        w.zeileNehmen("n-9", von: "g-2", zuteilung: zuteilung)
        #expect(w.zeilen == ["g-1": ["n-2"]], "eine Zeile, die sie nicht trägt: nichts")
    }

    @Test("E629, E630: Die Lagen für Prüfstand und Abbild — der Vorschlag; an einer Zeile kommt eine Lerngruppe hinzu; eine Lerngruppe ohne Zeile und eine Zeile „Keine Gruppe“")
    func lagen() {
        let gruppen = [Self.gruppe("g-1", "G6a"), Self.gruppe("g-2", "G6b")]
        let zuteilung = ["g-1": ["n-1"], "g-2": ["n-2"]]
        var vorschlag = Hochstufungswahl()
        vorschlag.lage(.vorschlag, gruppen: gruppen, zuteilung: zuteilung)
        #expect(vorschlag.zeilen.isEmpty && vorschlag.freieZeilen.isEmpty)
        var hinzu = Hochstufungswahl()
        hinzu.lage(.verdraengt, gruppen: gruppen, zuteilung: zuteilung)
        #expect(hinzu.zeilen == ["g-2": ["n-2", "n-1"]], "die letzte bekommt die erste Zeile der ersten dazu (E670)")
        var ohne = Hochstufungswahl()
        ohne.lage(.ohne, gruppen: gruppen, zuteilung: zuteilung)
        #expect(ohne.zeilen == ["g-2": []] && ohne.freieZeilen == ["n-2"], "die letzte mit Zeile verliert sie; die Zeile bleibt frei")
        var zwei = Hochstufungswahl()
        zwei.lage(.ohne, gruppen: gruppen, zuteilung: ["g-1": ["n-1"], "g-2": ["n-2", "n-3"]])
        #expect(zwei.zeilen == ["g-2": []] && zwei.freieZeilen == ["n-2", "n-3"], "mit zwei Zeilen verliert sie beide (Z-AT9B-05)")
    }

    @Test("E161, Z-AT9B-12: Das Angebot ohne Vertretungen — auch eine Lerngruppe namens „Vertretungen“ bekommt sie nicht vorgeschlagen")
    func angebotOhneVertretungen() {
        let zeilen = [Hochstufung.Zeile(id: "n-1", name: "G7a", fach: "Biologie", art: .unterricht, titel: "G7a · Biologie"),
                      Hochstufung.Zeile(id: "s:vertretungen", name: "Vertretungen", fach: "", art: .vertretungen, titel: "Vertretungen"),
                      Hochstufung.Zeile(id: "s:weiteres", name: "Weiteres", fach: "", art: .weiteres, titel: "Weiteres")]
        #expect(LerngruppenWahl.angebot(zeilen).map(\.id) == ["n-1", "s:weiteres"])
        let g = Self.gruppe("g-1", "Vertretungen")
        #expect(Hochstufung.zuteilung([g], namen: ["g-1": "Vertretungen"], uebernommen: [:], zeilen: LerngruppenWahl.angebot(zeilen),
                                      gewaehlt: [:]).isEmpty)
    }

    // v86 (AX2, E767): Variante 2 — ein eigener Satz zum Schalter „mit Mitgliedern“; sein Inhalt nach E817 (R2-A2), die
    // Termine nach E827, an „Andere Planung öffnen“ und „Früheres Schuljahr öffnen“ nach E831, an „Neue Planung“ mit Beginn
    // im selben oder einem früheren Schuljahr ebenso (E832).
    @Test("Z-AT9M-19, Z-AT9a1-02, E767, E817, E827, E831, E832: Der Fuß nennt, wer mitkommt und mit oder ohne Mitglieder — ohne Fach und ohne „die eine“; an „Neue Planung“ mit dem Import; an anderer oder früherer Planung die offenen Termine — an beiden Blättern nach den Stufen")
    func fuss() {
        let neu = LerngruppenWahl.fuss(mitImport: true, termine: .abDemNeuenSchuljahr)
        let oeffnen = LerngruppenWahl.fuss(mitImport: false, termine: .abDemNeuenSchuljahr)
        #expect(neu == "Mit kommen die Lerngruppen, die eine Zeile der neuen Planung tragen oder im IServ-Import erkannt sind; die "
                + "übrigen bleiben mit der bisherigen Planung im Archiv. Mit Mitgliedern — vorbelegt bei einer Klassenstufe im Namen "
                + "— kommt eine Lerngruppe mit ihren Personen, ihren offenen Mitteilungen und Maßnahmen, den Terminen ab dem neuen "
                + "Schuljahr und den geltenden Vereinbarungen, sonst nur mit Namen und Zeilen. Vorgeschlagen sind für jede "
                + "Lerngruppe ihre übernommenen Zeilen und die Zeilen ihres neuen Namens.")
        #expect(oeffnen == neu.replacingOccurrences(of: " oder im IServ-Import erkannt sind", with: ""))
        #expect(!neu.contains("Fach") && !oeffnen.contains("Import"))
        // E831: an „Andere Planung öffnen“ und „Früheres Schuljahr öffnen“ — der übrige Fuß gleich.
        let andere = LerngruppenWahl.fuss(mitImport: false, termine: .nurOffene)
        #expect(andere == "Mit kommen die Lerngruppen, die eine Zeile der neuen Planung tragen; die übrigen bleiben mit der "
                + "bisherigen Planung im Archiv. Mit Mitgliedern — vorbelegt bei einer Klassenstufe im Namen — kommt eine Lerngruppe "
                + "mit ihren Personen, ihren offenen Mitteilungen, Maßnahmen und Terminen und den geltenden Vereinbarungen, sonst nur "
                + "mit Namen und Zeilen. Vorgeschlagen sind für jede Lerngruppe ihre übernommenen Zeilen und die Zeilen ihres neuen "
                + "Namens.")
        // Welcher Fuß an welchem Blatt steht: an beiden nach den Stufen wie der Titel — „Neue Planung“ mit dem Import (E832).
        let jeStufe = [1, 0, -1].map { SchuljahrOeffnenDialog.fuss(stufen: $0) }
        #expect(jeStufe == [oeffnen, andere, andere])
        let andereMitImport = LerngruppenWahl.fuss(mitImport: true, termine: .nurOffene)
        #expect(andereMitImport == andere.replacingOccurrences(of: "tragen; die übrigen",
                                                               with: "tragen oder im IServ-Import erkannt sind; die übrigen"))
        let neuJeStufe = [1, 0, -1].map { NeuePlanungDialog.fuss(stufen: $0) }
        #expect(neuJeStufe == [neu, andereMitImport, andereMitImport])
    }

    @Test("Z-R2A2N2-04, Z-R2A2N3-02: Eine Zahl der Stufen für Titel und Wahl der Termine — rein, am Speicher und in der Vorgabe an ⌘O")
    @MainActor
    func eineStufenzahl() throws {
        let faelle: [(String, Int, String, Terminwahl)] = [
            ("2027-08-02", 1, "Neues Schuljahr öffnen", .abDemNeuenSchuljahr),
            ("2026-09-07", 0, "Andere Planung öffnen", .nurOffene),
            ("2025-08-04", -1, "Früheres Schuljahr öffnen", .nurOffene),
        ]
        let startOderNil = Unterrichtsplanung.Tag(iso: "2026-08-03")
        let alt = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(startOderNil), wochen: 4, basis: "",
                               klassen: [], fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: alt)
        for (beginn, stufen, titel, wahl) in faelle {
            let tagOderNil = Unterrichtsplanung.Tag(iso: beginn)
            let tag = try #require(tagOderNil)
            let rein = Hochstufung.stufen(von: "2026/27", beginn: tag)
            let amSpeicher = speicher.stufen(zu: tag)
            #expect(rein == stufen && amSpeicher == stufen, Comment(rawValue: beginn))
            #expect(SchuljahrOeffnenDialog.titel(stufen: rein) == titel)
            #expect(Lernendenbestand.terminwahl(stufen: rein) == wahl)
            // Z-R2A2N3-02: Die Vorgabe, mit der ⌘O das Blatt öffnet, trägt dieselbe Zahl — am Speicher, nicht nachgerechnet.
            let geladen = Planung.leer(titel: "Neue Planung", start: tag, wochen: 4, basis: "", klassen: [], fachfarben: [:])
            let vorgabe = speicher.hochstufungsvorgabe(zu: geladen, zuordnung: [:])
            #expect(vorgabe.stufen == amSpeicher, Comment(rawValue: beginn))
        }
        let spaeterOderNil = Unterrichtsplanung.Tag(iso: "2027-08-02")
        let ohneForm = Hochstufung.stufen(von: "", beginn: try #require(spaeterOderNil))
        #expect(ohneForm == 0, "ohne Schuljahr in fester Form 0 — wie bisher an allen drei Stellen")
    }

    @Test("E708, E768: Der Schalter „mit Mitgliedern“ — vorbelegt nach dem bisherigen Namen, von Hand in beide Richtungen; weder Umbenennen noch „Vorschlag wiederherstellen“ legt ihn um")
    func schalterNurVonHand() {
        let klasse = Self.gruppe("g-6a", "6a"), foerder = Self.gruppe("g-mf", "Mathe-Förder")
        var w = Hochstufungswahl()
        #expect(w.ohneMitglieder([klasse, foerder]) == ["g-mf"], "vorbelegt: die Klasse mit, „Mathe-Förder“ ohne")
        w.mitMitgliedernSetzen(true, fuer: "g-mf")
        #expect(w.ohneMitglieder([klasse, foerder]).isEmpty, "„Mathe-Förder“ von Hand mit Mitgliedern")
        w.mitMitgliedernSetzen(false, fuer: "g-6a")
        #expect(w.ohneMitglieder([klasse, foerder]) == ["g-6a"], "die 6a von Hand ohne")
        var v = Hochstufungswahl()
        v.nameSetzen("Mathe-Förder 7", fuer: foerder, stufen: 1)
        #expect(v.ohneMitglieder([foerder]) == ["g-mf"], "umbenannt mit einer Stufe im Namen — der Schalter bleibt aus (E768)")
        v.mitMitgliedernSetzen(true, fuer: "g-mf")
        v.zeilen = ["g-mf": []]
        v.vorschlagWiederherstellen()
        #expect(v.ohneMitglieder([foerder]).isEmpty && v.mitMitgliedern == ["g-mf": true],
                "„Vorschlag wiederherstellen“ nimmt die Zeilen, nicht den Schalter (E768)")
    }

    @Test("E766: An der Lerngruppe ohne Mitglieder der Hinweis und „12 Lernende bleiben im Archiv“; die Bedienhilfe des Schalters; ohne Zeile gesperrt")
    func hinweisUndZahl() {
        #expect(ZuordnungsBogen.schaltertitel == "mit Mitgliedern")
        #expect(ZuordnungsBogen.lernendentext(12, bleiben: 12, kommtMit: true, mitMitgliedern: true) == "12 Lernende")
        #expect(ZuordnungsBogen.lernendentext(12, bleiben: 12, kommtMit: true, mitMitgliedern: false)
                == "12 Lernende bleiben im Archiv")
        #expect(ZuordnungsBogen.lernendentext(12, bleiben: 12, kommtMit: false, mitMitgliedern: false) == "12 Lernende",
                "ohne Zeile wird die ganze Lerngruppe archiviert — das sagt „wird archiviert“")
        #expect(ZuordnungsBogen.hinweis(kommtMit: true, mitMitgliedern: false)
                == "ohne Mitglieder — sie bleiben in der Vorjahresplanung im Archiv")
        #expect(ZuordnungsBogen.hinweis(kommtMit: true, mitMitgliedern: true) == nil)
        #expect(ZuordnungsBogen.hinweis(kommtMit: false, mitMitgliedern: true) == "wird archiviert")
        #expect(ZuordnungsBogen.schalterhilfe("bisher Mathe-Förder") == "Mit Mitgliedern ins neue Schuljahr — bisher Mathe-Förder")
        #expect(ZuordnungsBogen.schalterFrei(kommtMit: true) && !ZuordnungsBogen.schalterFrei(kommtMit: false),
                "eine Lerngruppe ohne Zeile kommt nicht mit (E657) — ihr Schalter ist gesperrt")
    }

    @Test("E797: „N Lernende bleiben im Archiv“ zählt nur, wer über keine andere Lerngruppe mitkommt, die mit Mitgliedern mitkommt — die Zahl folgt der Wahl")
    func bleibenImArchiv() {
        // „Mathe-Förder“ mit 12 Lernenden, 3 davon auch in der 6a; die „Bio-AG“ mit allen 12.
        let foerder = (1...12).map { "l-\($0)" }
        let gruppen = ["g-mf": foerder, "g-6a": ["l-1", "l-2", "l-3", "l-20"], "g-ag": foerder]
        let mitglieder: (String) -> [String] = { gruppen[$0] ?? [] }
        func zahl(mitkommend: Set<String>, ohne: Set<String>) -> Int {
            Hochstufung.bleibenImArchiv("g-mf", mitglieder: mitglieder, mitkommend: mitkommend, ohneMitglieder: ohne)
        }
        #expect(zahl(mitkommend: ["g-mf", "g-6a"], ohne: ["g-mf"]) == 9, "3 kommen über die 6a")
        #expect(zahl(mitkommend: ["g-mf", "g-6a"], ohne: ["g-mf", "g-6a"]) == 12, "die 6a ohne Mitglieder — das Kästchen")
        #expect(zahl(mitkommend: ["g-mf"], ohne: ["g-mf"]) == 12, "die 6a ohne Zeile — die Zuordnung")
        #expect(zahl(mitkommend: ["g-mf", "g-6a", "g-ag"], ohne: ["g-mf"]) == 0, "alle über die „Bio-AG“")
        #expect(zahl(mitkommend: ["g-mf", "g-6a"], ohne: []) == 0, "mit Mitgliedern bleibt niemand")
        #expect(ZuordnungsBogen.lernendentext(12, bleiben: 9, kommtMit: true, mitMitgliedern: false)
                == "9 Lernende bleiben im Archiv")
        #expect(ZuordnungsBogen.lernendentext(12, bleiben: 0, kommtMit: true, mitMitgliedern: false) == "12 Lernende",
                "kommen alle über andere Lerngruppen mit, steht nur die Zahl")
    }

    @Test("E795, E796: Die Hilfe an „Vorschlag wiederherstellen“; am gesperrten Kästchen (ohne Zeile) die eigene Hilfe, frei die zum Ziehen")
    func hilfen() {
        #expect(ZuordnungsBogen.vorschlagHilfe == "Die Zeilen wieder wie vorgeschlagen — die Namen und „mit Mitgliedern“ bleiben")
        #expect(ZuordnungsBogen.schalterHilfe(frei: false)
                == "Erst mit einer Zeile kommt die Lerngruppe mit — auf eine Zeile rechts ziehen")
        #expect(ZuordnungsBogen.schalterHilfe(frei: true) == "Auf eine Zeile rechts ziehen — die Lerngruppe kommt dort hinzu",
                "frei die Hilfe der ganzen Zeile, wie bisher")
    }

    @Test("E821, E833, Z-R2A2N3-04: Oben nur „bisher …“, die Zahl und das Kästchen; Name und Ziel für sich in der zweiten Zeile; darunter die weiteren Zeilen der Gruppe, dann in eigener Zeile „wird archiviert“ (ohne Zeile) oder der Hinweis nach E766 A (aus)")
    func reihen() {
        let oben: [[ZuordnungsBogen.Teil]] = [[.bisher, .zahl, .abstand, .schalter], [.name, .ziel]]
        let mit = ZuordnungsBogen.reihen(kommtMit: true, mitMitgliedern: true, weitere: false)
        #expect(mit == oben)
        let ohneMitglieder = ZuordnungsBogen.reihen(kommtMit: true, mitMitgliedern: false, weitere: false)
        #expect(ohneMitglieder == oben + [[.hinweis]])
        let ohneZeile = ZuordnungsBogen.reihen(kommtMit: false, mitMitgliedern: false, weitere: false)
        #expect(ohneZeile == oben + [[.wirdArchiviert]])
        let ohneZeileMit = ZuordnungsBogen.reihen(kommtMit: false, mitMitgliedern: true, weitere: false)
        #expect(ohneZeileMit == ohneZeile, "ohne Zeile zählt das Kästchen nicht — es ist gesperrt")
        // Z-R2A2N3-04: Die weiteren Zeilen („+ …“) gleich unter Name und Ziel — vor dem Hinweis und vor „wird archiviert“.
        let mitWeiteren = ZuordnungsBogen.reihen(kommtMit: true, mitMitgliedern: true, weitere: true)
        #expect(mitWeiteren == oben + [[.weitere]])
        let ausMitWeiteren = ZuordnungsBogen.reihen(kommtMit: true, mitMitgliedern: false, weitere: true)
        #expect(ausMitWeiteren == oben + [[.weitere], [.hinweis]])
        // Ohne Zeile hat das Modell keine weiteren; die Folge gilt trotzdem.
        let ohneZeileMitWeiteren = ZuordnungsBogen.reihen(kommtMit: false, mitMitgliedern: false, weitere: true)
        #expect(ohneZeileMitWeiteren == oben + [[.weitere], [.wirdArchiviert]])
        // Am Modell, wie die Zeile im Bogen fragt: „aus“ mit zwei Zeilen — die zweite als „+ …“ vor dem Hinweis; mit einer
        // Zeile kein Teil dafür.
        let zweiZeilen = Hochstufung.Zeilenmodell.Gruppe(
            id: "g-1", kommtMit: true, bisher: "bisher G6a", name: "G7a", neuerName: "G7a", zeile: "n-1",
            ziel: "→ G7a · Informatik", weitere: ["G7a · Mathematik"], mitMitgliedern: false)
        #expect(ZuordnungsBogen.reihen(zweiZeilen) == oben + [[.weitere], [.hinweis]])
        let eineZeile = Hochstufung.Zeilenmodell.Gruppe(
            id: "g-2", kommtMit: true, bisher: "bisher G6a", name: "G7a", neuerName: "G7a", zeile: "n-1",
            ziel: "→ G7a · Informatik", mitMitgliedern: false)
        #expect(ZuordnungsBogen.reihen(eineZeile) == oben + [[.hinweis]])
    }

    @Test("E684: „Keine Gruppe“ nur an einer Zeile mit Lerngruppe — an einer leeren gibt es nichts zu lösen")
    func keineGruppeNurMitGruppe() {
        #expect(!ZuordnungsBogen.keineGruppeFrei([]))
        #expect(ZuordnungsBogen.keineGruppeFrei(["g-1"]))
    }

    @Test("E834: Die Zahl bricht nur zwischen ganzen Wörtern um — nie schmaler als ihr längstes Wort, geteilt nur am Leerzeichen")
    func zahlNurAnWortgrenzen() {
        let lang = ZuordnungsBogen.laengstesWort("9 Lernende bleiben im Archiv")
        #expect(lang > 0 && lang == ZuordnungsBogen.laengstesWort("Lernende"), "„Lernende“ ist das längste Wort")
        for wort in ["9", "bleiben", "im", "Archiv"] {
            #expect(ZuordnungsBogen.laengstesWort(wort) <= lang, Comment(rawValue: wort))
        }
        #expect(ZuordnungsBogen.laengstesWort("12 Lernende") == lang, "eine kurze Zahl: dasselbe längste Wort")
        #expect(ZuordnungsBogen.laengstesWort("9LernendebleibenimArchiv") > lang, "ohne Leerzeichen ein einziges Wort")
    }
}
