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

    @Test("Z-AT9M-19, Z-AT9a1-02: Der Fuß nennt, wer mitkommt — ohne Fach und ohne „die eine“; an „Neue Planung“ mit dem Import")
    func fuss() {
        let neu = LerngruppenWahl.fuss(mitImport: true)
        let oeffnen = LerngruppenWahl.fuss(mitImport: false)
        #expect(neu == "Mit kommen die Lerngruppen, die eine Zeile der neuen Planung tragen oder im IServ-Import erkannt sind — mit "
                + "ihren Personen und offenen Anliegen; die übrigen bleiben mit der bisherigen Planung im Archiv. Vorgeschlagen sind "
                + "für jede Lerngruppe ihre übernommenen Zeilen und die Zeilen ihres neuen Namens.")
        #expect(oeffnen == neu.replacingOccurrences(of: " oder im IServ-Import erkannt sind", with: ""))
        #expect(!neu.contains("Fach") && !oeffnen.contains("Import"))
    }

    @Test("E684: „Keine Gruppe“ nur an einer Zeile mit Lerngruppe — an einer leeren gibt es nichts zu lösen")
    func keineGruppeNurMitGruppe() {
        #expect(!ZuordnungsBogen.keineGruppeFrei([]))
        #expect(ZuordnungsBogen.keineGruppeFrei(["g-1"]))
    }
}
