// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Die übrigen Tabellen und die Fehlenden des Imports (v84, AT3) ─────────
// Maßnahmen und Anliegen einer Person ordnen per Kopfklick (E362, E363): Die Zeilen tragen Frist bzw. Tag als ISO-Text
// und den Stand als Rang. Der Import-Bogen nennt die Fehlenden getrennt (E368): Wer in einer anderen Lerngruppe steht,
// wird nicht archiviert, nur aus dieser genommen.

@Suite("Tabellen der Anliegen und Fehlende des Imports")
struct AnliegenTabellenPruefungen {

    private let t = "2026-09-01T08:00:00.000Z"

    private func bestand() throws -> (Lernendenbestand, g: String, anna: String, ben: String) {
        let leer = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: t)
        let (b, g) = try #require(leer.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: t))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: g, jetzt: t).bestand
        let anna = try #require(c.lernende.first { $0.nachname == "Abel" }).id
        let ben = try #require(c.lernende.first { $0.nachname == "Bauer" }).id
        return (c, g, anna, ben)
    }

    @Test("Maßnahmen (E362, E363): Frist als ISO-Tag, Stand als Rang — zeitlich und nach Stand geordnet")
    func massnahmen() throws {
        let (b0, g, anna, ben) = try bestand()
        var b = b0
        let (c, spaet) = try #require(b.mitNeuemAnliegen(.massnahme, titel: "Heft", lerngruppe: g, betroffene: [anna],
                                                        datum: "2026-09-01", frist: "2026-10-10", jetzt: t))
        let (d, frueh) = try #require(c.mitNeuemAnliegen(.massnahme, titel: "Lesen", lerngruppe: g, betroffene: [anna, ben],
                                                        datum: "2026-09-01", frist: "2026-09-30", jetzt: t))
        b = d.mitRuecklauf(frueh, anna, stand: .erledigt, datum: "2026-09-29", notiz: "", jetzt: t)
        let v = Lernendenverzeichnis(b)
        let zeilen = Massnahmenliste.zeilen(v.mitglieder(g), v)
        #expect(Massnahmenliste.geordnet(zeilen, []).map(\.id) == ["\(spaet)/\(anna)", "\(frueh)/\(anna)", "\(frueh)/\(ben)"],
                "ohne Kopfklick die Folge der Jahresdatei")
        let nachFrist = Tabellenordnung.geordnet(zeilen, nach: [
            KeyPathComparator(\.frist, comparator: String.StandardComparator.lexical),
            KeyPathComparator(\.person, comparator: Namensfolge())])
        #expect(nachFrist.map(\.id) == ["\(frueh)/\(anna)", "\(frueh)/\(ben)", "\(spaet)/\(anna)"], "die frühe Frist vorn")
        #expect(zeilen.first { $0.id == "\(frueh)/\(anna)" }?.stand == Rueckmeldestand.erledigt.rang)
        let nachStand = Tabellenordnung.geordnet(zeilen, nach: [KeyPathComparator(\.stand)])
        #expect(nachStand.last?.id == "\(frueh)/\(anna)", "offen vor erfüllt")
    }

    @Test("Anliegen einer Person (E362): Der Tag einer Maßnahme ist ihre Frist, eines Termins Tag und Uhrzeit")
    func personenanliegen() throws {
        let (b, _, anna, _) = try bestand()
        let (c, termin) = try #require(b.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [anna],
                                                          datum: "2026-10-20", frist: "", uhrzeit: "07:45", jetzt: t))
        let (d, massnahme) = try #require(c.mitNeuemAnliegen(.massnahme, titel: "Heft", lerngruppe: "", betroffene: [anna],
                                                            datum: "2026-09-01", frist: "2026-10-12", jetzt: t))
        let e = d.mitRuecklauf(massnahme, anna, stand: .abgelehnt, datum: "2026-10-13", notiz: "", jetzt: t)
        let zeilen = Personenanliegen.zeilen(anna, Lernendenverzeichnis(e))
        #expect(zeilen.first { $0.id == termin }?.tag == "2026-10-20 07:45")
        #expect(zeilen.first { $0.id == massnahme }?.tag == "2026-10-12")
        #expect(zeilen.first { $0.id == massnahme }?.stand == Rueckmeldestand.abgelehnt.rang)
        let nachTag = Tabellenordnung.geordnet(zeilen, nach: [KeyPathComparator(\.tag, comparator: String.StandardComparator.lexical)])
        #expect(nachTag.map(\.id) == [massnahme, termin])
    }

    @Test("Fehlende des Imports (E368): alle genannt, die in anderer Lerngruppe gezählt — Wortlaut des Nutzers je Fall")
    func fehlende() {
        let namen = ["l-1": "Abel, Anna", "l-2": "Bauer, Ben", "l-3": "Celik, Cem"]
        func texte(_ fehlende: [String], _ anderswo: [(String, String)]) -> (String?, String?) {
            var bilanz = Importbilanz()
            bilanz.fehlende = fehlende
            bilanz.fehlendeAnderswo = anderswo.map { Fehlmitgliedschaft(person: $0.0, gruppe: $0.1) }
            let t = ImportBogen.fehlendeTexte(bilanz) { namen[$0] ?? "—" }
            return (t.fehlen, t.anderswo)
        }
        let knopf = "„Fehlende aus der Lerngruppe nehmen“ entfernt sie nur dort, wo sie"
        let geordnet = texte(["l-3"], [("l-1", "g")])
        #expect(geordnet.0 == "In der Datei fehlen 2 bisherige Mitglieder: Abel, Anna; Celik, Cem.", "Namen geordnet")
        #expect(geordnet.1 == "1 davon steht noch in einer anderen Lerngruppe — sie wird nicht archiviert; \(knopf) fehlt.")
        let drei = texte(["l-1"], [("l-2", "g"), ("l-3", "g")])
        #expect(drei.0 == "In der Datei fehlen 3 bisherige Mitglieder: Abel, Anna; Bauer, Ben; Celik, Cem.")
        #expect(drei.1 == "2 davon stehen noch in einer anderen Lerngruppe — sie werden nicht archiviert; \(knopf) fehlen.")
        let eine = texte(["l-1"], [])
        #expect(eine.0 == "In der Datei fehlt 1 bisheriges Mitglied: Abel, Anna." && eine.1 == nil)
        let anderswo = texte([], [("l-2", "g1"), ("l-2", "g2")])
        #expect(anderswo.0 == "In der Datei fehlt 1 bisheriges Mitglied: Bauer, Ben.", "zweimal fehlend, einmal gezählt")
        #expect(anderswo.1 == "1 Person steht noch in einer anderen Lerngruppe und wird nicht archiviert; \(knopf) fehlt.")
        let alle = texte([], [("l-1", "g"), ("l-2", "g"), ("l-3", "g")])
        #expect(alle.0 == "In der Datei fehlen 3 bisherige Mitglieder: Abel, Anna; Bauer, Ben; Celik, Cem.")
        #expect(alle.1 == "Alle 3 davon stehen noch in einer anderen Lerngruppe — sie werden nicht archiviert; \(knopf) fehlen.")
        let keine = texte([], [])
        #expect(keine.0 == nil && keine.1 == nil)
    }

    @Test("Rücklaufliste ohne Kopfklick wie bisher (Z-AT3-01): Nachname, dann Vorname — auch bei Meier, Meier-Schulz, Meier Schulz")
    func ruecklaufVorgabe() throws {
        let leer = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: t)
        let (b, g) = try #require(leer.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: t))
        let c = b.mitPersonen(Namenszeilen.lesen("Meier-Schulz, Ben\nMeier, Zoe\nMeier Schulz, Anna\nMeier, Anna\nÄrmel, Max")
            .namen, inGruppe: g, jetzt: t).bestand
        let v = Lernendenverzeichnis(c)
        let bisher = v.mitglieder(g).sorted(by: Lernendenverzeichnis.vorgehen).map(\.anzeigename)
        let jetzt = Tabellenordnung.geordnet(v.mitglieder(g), nach: Anliegenordnung().ruecklauf).map(\.anzeigename)
        #expect(jetzt == bisher, "\(jetzt) gegen \(bisher)")
        let rueckwaerts = Tabellenordnung.geordnet(v.mitglieder(g), nach: [
            KeyPathComparator(\Lernender.self, comparator: Namensfolge(), order: .reverse)]).map(\.anzeigename)
        #expect(rueckwaerts == bisher.reversed(), "der zweite Klick kehrt um")
        #expect(Lernendenblatt.vorn(Anliegenordnung().ruecklauf, \Lernender.self), "„Name“ hervorgehoben")
        #expect(Anliegenordnung().massnahmen.isEmpty && Anliegenordnung().personenanliegen.isEmpty,
                "Maßnahmen und Anliegen ohne Vorgabe — kein Kopf hervorgehoben")
    }

    @Test("Herausnehmen nur, wer beim Klick noch anderswo steht (Z-AT3-02) — eine archivierte Gruppe zählt nicht")
    func nochAnderswo() throws {
        let leer = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: t)
        let (b1, g1) = try #require(leer.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: t))
        let (b2, g2) = try #require(b1.mitNeuerGruppe(name: "6b", art: .klasse, jetzt: t))
        let (b3, ag) = try #require(b2.mitNeuerGruppe(name: "Theater", art: .klasse, jetzt: t))
        let c = b3.mitPersonen(Namenszeilen.lesen("Abel, Anna").namen, inGruppe: g1, jetzt: t).bestand
        let anna = try #require(c.lernende.first).id
        let d0 = try #require(c.mitMitglied(anna, inGruppe: g2, jetzt: t))
        let d = try #require(d0.mitMitglied(anna, inGruppe: ag, jetzt: t))
        let beide = [Fehlmitgliedschaft(person: anna, gruppe: g1), Fehlmitgliedschaft(person: anna, gruppe: g2)]
        #expect(ImportBogen.nochAnderswo(beide, in: d) == beide, "noch im Theater — aus beiden Klassen")
        let ohneAG = d.ohneMitglied(anna, ausGruppe: ag)
        #expect(ImportBogen.nochAnderswo(beide, in: ohneAG).isEmpty, "sonst nirgends — nichts herausnehmen")
        #expect(ImportBogen.nochAnderswo(beide, in: d.mitArchivierterGruppe(ag, jetzt: t)).isEmpty, "Theater archiviert")
        let eine = [Fehlmitgliedschaft(person: anna, gruppe: g1)]
        #expect(ImportBogen.nochAnderswo(eine, in: ohneAG) == eine, "noch in 6b — aus 6a")
    }

    @Test("Rang des Stands: offen vor erledigt vor abgelehnt")
    func rang() {
        #expect(Rueckmeldestand.offen.rang < Rueckmeldestand.erledigt.rang
                && Rueckmeldestand.erledigt.rang < Rueckmeldestand.abgelehnt.rang)
    }
}
