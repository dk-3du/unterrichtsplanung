// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Bindung nach Namen (v84, AT5: E352, E521, E523) ───────────────────────
// Nach „Je Klasse eine Lerngruppe“ bindet der Import jede neu angelegte Lerngruppe an die Unterrichtszeilen gleichen
// Namens — Groß/Klein egal, Fach beliebig —, aber nur an freie: Eine Zeile, die schon eine aktive Lerngruppe trägt,
// bleibt dort; Sonderzeilen nie. Die Meldung nennt, wie viele gebunden sind und wie viele ohne freie Zeile blieben.

@Suite("Bindung nach Namen: neue Lerngruppen an freie Unterrichtszeilen gleichen Namens")
struct NamensbindungPruefungen {

    static let jetzt = "2026-10-12T10:00:00.000Z"
    static let planung = "2026-08-01T08:00:00.000Z"
    static let basis = "IServ-Import: 0 neu · 0 unverändert · 0 übergangen"
    static let weg = "binden unter „Lernende, Klassen/Kurse und Fächer“ (⌘K)"

    private func leer() -> Lernendenbestand {
        Lernendenbestand.leer(planung: Self.planung, schuljahr: "2026/27", jetzt: Self.jetzt)
    }

    private func gruppe(_ b: inout Lernendenbestand, _ name: String) throws -> String {
        let (neu, id) = try #require(b.mitNeuerGruppe(name: name, art: .klasse, jetzt: Self.jetzt))
        b = neu
        return id
    }

    @Test("Je Gruppe alle freien Unterrichtszeilen gleichen Namens; besetzte und Sonderzeilen bleiben")
    func bindung() throws {
        var b = leer()
        let g05 = try gruppe(&b, "05G"), g6a = try gruppe(&b, "6a"), g7c = try gruppe(&b, "7c")
        let weiteres = try gruppe(&b, "Weiteres"), theater = try gruppe(&b, "Theater")
        let zeilen = Standardkurse.aufbauen([("05G", "Biologie"), ("05g", "Chemie"), ("6a", "")])
            + [Klasse.sonderzeile(.weiteres)]
        func bindung(_ k: Klasse) -> Zeilenbindung { Zeilenbindung(planung: Self.planung, klasseId: k.id) }
        // Die Zeile „6a“ trägt schon das Theater.
        b = b.mitBindung(theater, an: bindung(zeilen[2]), jetzt: Self.jetzt)

        let (c, ergebnis) = b.mitBindungenNachNamen([g05, g6a, g7c, weiteres], zeilen: zeilen, planung: Self.planung,
                                                    jetzt: Self.jetzt)
        #expect(ergebnis == Namensbindung(gebunden: 1, ohneZeile: 3), "05G gebunden; 6a besetzt, 7c ohne, Weiteres nur Sonderzeile")
        #expect(Set(c.lerngruppen.first { $0.id == g05 }?.zeilen ?? []) == [bindung(zeilen[0]), bindung(zeilen[1])],
                "beide Fächer, Groß/Klein egal")
        #expect(c.gruppe(an: bindung(zeilen[2]))?.id == theater, "die besetzte Zeile bleibt am Theater")
        #expect(c.lerngruppen.first { $0.id == weiteres }?.zeilen.isEmpty == true, "keine Sonderzeile")

        let (d, nichts) = b.mitBindungenNachNamen([], zeilen: zeilen, planung: Self.planung, jetzt: Self.jetzt)
        #expect(d == b && nichts == Namensbindung(), "ohne Gruppen nichts")
    }

    @Test("Import „Je Klasse“ mit Schalter: Nur die neu angelegten Gruppen werden gebunden; ohne Schalter oder anderes Ziel nicht")
    func importMitBindung() throws {
        let lesung = try ImportPruefungen.lesung(ImportPruefungen.datei([
            ImportPruefungen.zeile("Eva", "Ernst", klasse: "05G"), ImportPruefungen.zeile("Finn", "Fink", klasse: "7c"),
            ImportPruefungen.zeile("Gil", "Gras", klasse: "05G")]))
        let zeilen = Standardkurse.aufbauen([("05G", "Biologie"), ("05G", "Chemie")])

        let (b, bilanz, bindung) = leer().mitImport(lesung, ziel: .jeKlasse, binden: zeilen, planung: Self.planung,
                                                    jetzt: Self.jetzt)
        #expect(bilanz.neueGruppen == ["05G", "7c"])
        #expect(bindung == Namensbindung(gebunden: 1, ohneZeile: 1))
        #expect(b.lerngruppen.first { $0.name == "05G" }?.zeilen.count == 2, "beide Zeilen „05G“")
        #expect(bilanz.meldung(bindung) == "IServ-Import: 3 neu · 0 unverändert · 0 übergangen; 1 Lerngruppe an ihre "
                + "Zeilen gebunden, 1 ohne freie Zeile gleichen Namens — \(Self.weg).")

        let (c, _, ohne) = leer().mitImport(lesung, ziel: .jeKlasse, binden: nil, planung: Self.planung, jetzt: Self.jetzt)
        #expect(ohne == nil && c.lerngruppen.allSatisfy { $0.zeilen.isEmpty }, "ohne Schalter keine Bindung")
        let (_, _, andere) = leer().mitImport(lesung, ziel: .neueGruppe("05G"), binden: zeilen, planung: Self.planung,
                                              jetzt: Self.jetzt)
        #expect(andere == nil, "nur bei „Je Klasse“")

        // „05G“ gibt es schon: Die Gruppe wird getroffen, nicht neu angelegt — und nicht gebunden; nur „7c“ ist neu.
        var mit = leer()
        _ = try gruppe(&mit, "05G")
        let (d, _, nurNeue) = mit.mitImport(lesung, ziel: .jeKlasse, binden: zeilen, planung: Self.planung, jetzt: Self.jetzt)
        #expect(nurNeue == Namensbindung(gebunden: 0, ohneZeile: 1), "nur die neue „7c“, ohne Zeile")
        #expect(d.lerngruppen.allSatisfy { $0.zeilen.isEmpty }, "die bestehende „05G“ bleibt ungebunden")
    }

    @Test("Grenzfälle: Zeile an einer archivierten Gruppe ist frei (E527); Leerraum am Rand; die Planung der Bindung; höchstens 20")
    func grenzfaelle() throws {
        var b = leer()
        let alt = try gruppe(&b, "Alt"), neu6a = try gruppe(&b, "6a"), g7c = try gruppe(&b, "7c"), g9z = try gruppe(&b, "9z")
        let zeile6a = try #require(Standardkurse.aufbauen([("6a", "")]).first)
        // Direkt gebaut — `aufbauen` stutzt den Namen schon.
        let zeile7c = Klasse(id: "k-7c", name: " 7c ", fach: "", notiz: "", farbe: Farbwelt.ohneFarbe, farbeManuell: false)
        let neun = Standardkurse.aufbauen((1...21).map { ("9z", "Fach \($0)") })
        let an6a = Zeilenbindung(planung: Self.planung, klasseId: zeile6a.id)
        b = b.mitBindung(alt, an: an6a, jetzt: Self.jetzt).mitArchivierterGruppe(alt, jetzt: Self.jetzt)

        let (c, ergebnis) = b.mitBindungenNachNamen([neu6a, g7c, g9z], zeilen: [zeile6a, zeile7c] + neun,
                                                    planung: Self.planung, jetzt: Self.jetzt)
        #expect(ergebnis == Namensbindung(gebunden: 3, ohneZeile: 0))
        #expect(c.gruppe(an: an6a)?.id == neu6a, "die Zeile der archivierten Gruppe ist frei — wie in ⌘K")
        #expect(c.lerngruppen.first { $0.id == alt }?.zeilen == [an6a], "die archivierte behält ihre Bindung — sie zeigt keine Zeile (E670)")
        #expect(c.lerngruppen.first { $0.id == g7c }?.zeilen == [Zeilenbindung(planung: Self.planung, klasseId: "k-7c")],
                "Leerraum am Rand zählt nicht; die Bindung trägt die Planung")
        #expect(c.lerngruppen.first { $0.id == g9z }?.zeilen.count == Lernendendatei.maxZeilenJeGruppe,
                "höchstens 20 Zeilen — die 21. bleibt frei (Z-AT5-05, hingenommen)")
    }

    @Test("Meldung (E523): Einzahl und Mehrzahl, mit und ohne Gruppen ohne freie Zeile")
    func meldung() {
        let b = Importbilanz()
        #expect(b.meldung(nil) == Self.basis + ".")
        #expect(b.meldung(Namensbindung()) == Self.basis + ".", "nichts zu binden — wie ohne Schalter")
        #expect(b.meldung(.init(gebunden: 2, ohneZeile: 0)) == Self.basis + "; 2 Lerngruppen an ihre Zeilen gebunden.")
        #expect(b.meldung(.init(gebunden: 1, ohneZeile: 0)) == Self.basis + "; 1 Lerngruppe an ihre Zeilen gebunden.")
        #expect(b.meldung(.init(gebunden: 2, ohneZeile: 1))
                == Self.basis + "; 2 Lerngruppen an ihre Zeilen gebunden, 1 ohne freie Zeile gleichen Namens — \(Self.weg).")
        #expect(b.meldung(.init(gebunden: 0, ohneZeile: 2))
                == Self.basis + "; 2 Lerngruppen ohne freie Zeile gleichen Namens — \(Self.weg).")
        #expect(b.meldung(.init(gebunden: 0, ohneZeile: 1))
                == Self.basis + "; 1 Lerngruppe ohne freie Zeile gleichen Namens — \(Self.weg).")
    }
}
