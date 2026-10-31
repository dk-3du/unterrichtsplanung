// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Was das Blatt „Lernende“ zeigt (v84, AT2b: F, G, H/I) ─────────────────
// Die reinen Teile hinter der Oberfläche: der Filter der Gruppenliste (E359, E480), Suche, Filter und Ordnung von
// „Alle Lernenden“ (E360, E362–E364), der Zusatz „auch in …“ (E370) und das Menü „Lerngruppen“ (E365, E369, E497).
// Wie es aussieht, zeigen Abbild und Handprobe.

@Suite("Blatt „Lernende“: Gruppenfilter, Suche und Ordnung, „auch in …“, Menü „Lerngruppen“")
struct LernendenblattAnsichtPruefungen {

    private let t = "2026-09-01T08:00:00.000Z"

    /// Die Zeilen der Planung „p“ und ihre Titel — darüber trifft die Suche das Fach (E671).
    private static let zeilen = [("6a", "k-1", "6a · Biologie"), ("6b", "k-2", "6b · Chemie"), ("G6a", "k-3", "G6a · Biologie"),
                                 ("7b", "k-4", "7b · Physik"), ("Alt", "k-5", "Alt · Biologie")]
    private static var zeilentitel: [Zeilenbindung: String] {
        Dictionary(uniqueKeysWithValues: zeilen.map { (Zeilenbindung(planung: "p", klasseId: $0.1), $0.2) })
    }

    /// Fünf aktive Lerngruppen nach den Beispielen des Nutzers (E480) — ohne Fach, an ihren Zeilen — und eine archivierte;
    /// Personen in „6a“.
    private func bestand() throws -> (Lernendenbestand, [String: String]) {
        var b = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: t)
        var ids: [String: String] = [:]
        for name in ["6a", "6b", "16a", "G6a", "7b", "Alt"] {
            let (c, id) = try #require(b.mitNeuerGruppe(name: name, art: .klasse, jetzt: t))
            b = c
            ids[name] = id
        }
        for (name, zeile, _) in Self.zeilen {
            b = b.mitBindung(try #require(ids[name]), an: Zeilenbindung(planung: "p", klasseId: zeile), jetzt: t)
        }
        let alt = try #require(ids["Alt"])
        let bio = try #require(ids["6a"])
        b = b.mitArchivierterGruppe(alt, jetzt: t)
        b = b.mitPersonen(Namenszeilen.lesen("Müller, Anna\nAbel, Ben\nÇelik, Cem").namen, inGruppe: bio, jetzt: t).bestand
        return (b, ids)
    }

    @Test("Gruppenfilter nach den Beispielen des Nutzers (E480, E671): Name und verknüpfte Zeilen, Wortteile, archivierte nur mit dem Schalter")
    func gruppenfilter() throws {
        let (b, _) = try bestand()
        func liste(_ suche: String, archivierte: Bool = false) -> [String] {
            Lernendenblatt.gruppenliste(b, archivierte: archivierte, suche: suche, zeilentitel: Self.zeilentitel).map(\.beschriftung)
        }
        #expect(liste("6a") == ["6a", "16a", "G6a"], "auch 16a und G6a")
        #expect(liste("Biologie") == ["6a", "G6a"], "über die Zeilen „6a · Biologie“ und „G6a · Biologie“")
        #expect(liste("bio") == ["6a", "G6a"])
        #expect(liste("che") == ["6b"])
        #expect(liste("6b · Chemie") == ["6b"], "„·“ trennt wie ein Leerzeichen")
        #expect(liste("") == ["6a", "6b", "7b", "16a", "G6a"], "leer: alle aktiven")
        #expect(liste("bio", archivierte: true) == ["6a", "Alt", "G6a"])
    }

    @Test("Suche unter „Alle Lernenden“: Akzente und Rufname, zusammen mit „Nur mit offenen Anliegen“ (E360)")
    func suche() throws {
        var (b, ids) = try bestand()
        let anna = try #require(b.lernende.first { $0.nachname == "Müller" }).id
        b = b.mitPerson(anna, vorname: "Anna", nachname: "Müller", rufname: "Anni", jetzt: t)
        let ben = try #require(b.lernende.first { $0.nachname == "Abel" }).id
        let bio = try #require(ids["6a"])
        b = try #require(b.mitNeuemAnliegen(.massnahme, titel: "Heft", lerngruppe: bio, betroffene: [ben],
                                            datum: "2026-09-01", frist: "2026-09-08", jetzt: t)).bestand
        let v = Lernendenverzeichnis(b)
        func namen(_ suche: String, nurOffen: Bool = false) -> [String] {
            Lernendenblatt.uebersicht(v, suche: suche, archivierte: false, nurOffen: nurOffen,
                                      ordnung: Personenzeile.vorgabe).map(\.nachname)
        }
        #expect(namen("") == ["Abel", "Çelik", "Müller"])
        #expect(namen("mul") == ["Müller"], "ohne Akzent")
        #expect(namen("anni") == ["Müller"], "der Rufname")
        #expect(namen("cel") == ["Çelik"])
        #expect(namen("", nurOffen: true) == ["Abel"])
        #expect(namen("mül", nurOffen: true).isEmpty, "beides zusammen")
    }

    @Test("Ordnung nach einer Spalte (E362, E363): Vorname lokalisiert, auf- und absteigend; die Vorgabe nach Nachname")
    func ordnung() throws {
        let (b, _) = try bestand()
        let v = Lernendenverzeichnis(b)
        func vornamen(_ ordnung: [KeyPathComparator<Personenzeile>]) -> [String] {
            Lernendenblatt.uebersicht(v, suche: "", archivierte: false, nurOffen: false, ordnung: ordnung).map(\.vorname)
        }
        #expect(vornamen([Personenspalte.vorname.vergleicher]) == ["Anna", "Ben", "Cem"])
        var absteigend = Personenspalte.vorname.vergleicher
        absteigend.order = .reverse
        #expect(vornamen([absteigend]) == ["Cem", "Ben", "Anna"])
        #expect(vornamen(Personenzeile.vorgabe) == ["Ben", "Cem", "Anna"], "Vorgabe: Nachname (Abel, Çelik, Müller)")
    }

    @Test("Der Zusatz „auch in …“ (E370): nichts ohne weitere Gruppe, sonst die Gruppen in der Folge der Listen")
    func auchIn() throws {
        let (b, ids) = try bestand()
        let g = Lernendenverzeichnis(b)
        #expect(Lernendenblatt.auchIn([]) == nil)
        let chemie = try #require(ids["6b"]), g16 = try #require(ids["16a"])
        let zwei = [try #require(g.gruppe(chemie)), try #require(g.gruppe(g16))]
        #expect(Lernendenblatt.auchIn(zwei) == "auch in 6b, 16a")
    }

    @Test("Menü „Lerngruppen“ (E365, E369, E497): Häkchen je aktiver Gruppe, volle abgeblendet, Umziehen nur ins Neue")
    func menue() throws {
        var (b, ids) = try bestand()
        let anna = try #require(b.lernende.first { $0.nachname == "Müller" }).id
        let bio = try #require(ids["6a"]), chemie = try #require(ids["6b"])
        let voll = try #require(ids["7b"]), g16 = try #require(ids["16a"])
        b = try #require(b.mitMitglied(anna, inGruppe: chemie, jetzt: t))
        // „7b“ voll: 40 andere.
        let vierzig = (1...Kennwerte.maxMitgliederJeLerngruppe).map { "Name\($0), Vor\($0)" }.joined(separator: "\n")
        b = b.mitPersonen(Namenszeilen.lesen(vierzig).namen, inGruppe: voll, jetzt: t).bestand
        #expect(b.istVoll(voll))

        let m = Mitgliedschaftsmenue(person: anna, aus: bio, bestand: b)
        #expect(m.haekchen.map(\.titel) == ["6a", "6b", "7b (voll)", "16a", "G6a"],
                "aktive Gruppen in der Folge der Listen; die archivierte fehlt")
        #expect(m.haekchen.map(\.mitglied) == [true, true, false, false, false])
        #expect(m.haekchen.map(\.waehlbar) == [true, true, false, true, true], "voll: abgeblendet")
        let g6 = try #require(ids["G6a"])
        #expect(m.umziehen.map(\.id) == [voll, g16, g6],
                "ohne die Quelle und ohne „6b“, wo sie schon ist")
        #expect(m.umziehen.first?.titel == "7b (voll)" && m.umziehen.first?.waehlbar == false)
        #expect(Mitgliedschaftsmenue(person: anna, aus: nil, bestand: b).umziehen.isEmpty, "ohne Quelle kein Umziehen")
        #expect(Mitgliedschaftsmenue(person: anna, aus: g16, bestand: b).umziehen.isEmpty, "nicht in der Quelle: kein Umziehen")
    }

    @Test("Archiv (E362, E363): Mitglieder als Zahl, der Tag einer Maßnahme ist ihre Frist, ISO-Tage ordnen zeitlich")
    func archivzeilen() throws {
        var b = Lernendenbestand.leer(planung: "p", schuljahr: "2025/26", jetzt: t)
        let (c, zehn) = try #require(b.mitNeuerGruppe(name: "5a", art: .klasse, jetzt: t))
        let (d, neun) = try #require(c.mitNeuerGruppe(name: "5b", art: .kurs, jetzt: t))
        b = d.mitPersonen(Namenszeilen.lesen((1...10).map { "A\($0), B\($0)" }.joined(separator: "\n")).namen,
                          inGruppe: zehn, jetzt: t).bestand
        b = b.mitPersonen(Namenszeilen.lesen((1...9).map { "C\($0), D\($0)" }.joined(separator: "\n")).namen,
                          inGruppe: neun, jetzt: t).bestand
        let person = try #require(b.lernende.first).id
        b = try #require(b.mitNeuemAnliegen(.massnahme, titel: "Heft", lerngruppe: zehn, betroffene: [person],
                                            datum: "2025-09-01", frist: "2025-10-10", jetzt: t)).bestand
        b = try #require(b.mitNeuemAnliegen(.mitteilung, titel: "Brief", lerngruppe: zehn, betroffene: [person],
                                            datum: "2025-09-30", frist: "", jetzt: t)).bestand
        let v = Lernendenverzeichnis(b)
        let gruppen = ArchivAnsicht.gruppenzeilen(v)
        #expect(gruppen.map(\.mitglieder) == [10, 9] && gruppen.map(\.name) == ["5a", "5b"], "ohne Spalten „Fach“ und „Art“ (E666)")
        #expect(Tabellenordnung.geordnet(gruppen, nach: [KeyPathComparator(\.mitglieder)]).map(\.mitglieder) == [9, 10],
                "als Zahl: 9 vor 10")
        let anliegen = ArchivAnsicht.anliegenzeilen(b, v)
        #expect(anliegen.map(\.tag) == ["2025-10-10", "2025-09-30"], "Maßnahme: die Frist")
        #expect(Tabellenordnung.geordnet(anliegen, nach: [KeyPathComparator(\.tag, comparator: String.StandardComparator.lexical)])
                .map(\.titel) == ["Brief", "Heft"])
        #expect(anliegen.map(\.lerngruppe) == ["5a", "5a"])
    }

    @Test("Menü einer archivierten Person: Häkchen nehmen geht, setzen nicht, Umziehen nicht")
    func menueArchiviert() throws {
        var (b, ids) = try bestand()
        let anna = try #require(b.lernende.first { $0.nachname == "Müller" }).id
        let bio = try #require(ids["6a"])
        b = b.mitArchivierterPerson(anna, jetzt: t)
        let m = Mitgliedschaftsmenue(person: anna, aus: bio, bestand: b)
        #expect(m.haekchen.first { $0.id == bio }?.waehlbar == true, "aus der Gruppe nehmen geht")
        #expect(m.haekchen.filter { $0.id != bio }.allSatisfy { !$0.waehlbar }, "aufnehmen nicht")
        #expect(m.umziehen.allSatisfy { !$0.waehlbar })
    }

    @Test("Menü, Grenzfälle: archivierte Quelle ohne Umziehen, Mitglied einer vollen Gruppe ohne „(voll)“, unbekannte Person")
    func menueGrenzfaelle() throws {
        var (b, ids) = try bestand()
        let anna = try #require(b.lernende.first { $0.nachname == "Müller" }).id
        let alt = try #require(ids["Alt"]), voll = try #require(ids["7b"])
        b = b.mitZurueckgeholterGruppe(alt, jetzt: t, sitzplanzeilen: [])
        b = try #require(b.mitMitglied(anna, inGruppe: alt, jetzt: t)).mitArchivierterGruppe(alt, jetzt: t)
        #expect(Mitgliedschaftsmenue(person: anna, aus: alt, bestand: b).umziehen.isEmpty, "archivierte Quelle")
        b = try #require(b.mitMitglied(anna, inGruppe: voll, jetzt: t))
        let neununddreissig = (1..<Kennwerte.maxMitgliederJeLerngruppe).map { "Name\($0), Vor\($0)" }.joined(separator: "\n")
        b = b.mitPersonen(Namenszeilen.lesen(neununddreissig).namen, inGruppe: voll, jetzt: t).bestand
        #expect(b.istVoll(voll))
        let eintrag = try #require(Mitgliedschaftsmenue(person: anna, aus: nil, bestand: b).haekchen.first { $0.id == voll })
        #expect(eintrag.titel == "7b" && eintrag.mitglied && eintrag.waehlbar, "Mitglied: Ohne „(voll)“, nehmen geht")
        let fremd = Mitgliedschaftsmenue(person: "l-unbekannt", aus: nil, bestand: b)
        #expect(fremd.haekchen.allSatisfy { !$0.mitglied && !$0.waehlbar })
    }

    @Test("Ordnung nach „Angelegt“ (E363): zeitlich, auf- und absteigend")
    func angelegt() throws {
        var b = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: t)
        let (c, g) = try #require(b.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: t))
        b = c.mitPersonen(Namenszeilen.lesen("Zander, Zoe").namen, inGruppe: g, jetzt: "2026-09-03T08:00:00.000Z").bestand
        b = b.mitPersonen(Namenszeilen.lesen("Abel, Anna").namen, inGruppe: g, jetzt: "2026-09-10T08:00:00.000Z").bestand
        b = b.mitPersonen(Namenszeilen.lesen("Meier, Max").namen, inGruppe: g, jetzt: "2026-09-01T08:00:00.000Z").bestand
        let v = Lernendenverzeichnis(b)
        func folge(_ ordnung: [KeyPathComparator<Personenzeile>]) -> [String] {
            Lernendenblatt.uebersicht(v, suche: "", archivierte: false, nurOffen: false, ordnung: ordnung).map(\.nachname)
        }
        #expect(folge(Personenspalte.angelegt.ordnung) == ["Meier", "Zander", "Abel"])
        var absteigend = Personenspalte.angelegt.ordnung
        absteigend[0].order = .reverse
        #expect(folge(absteigend) == ["Abel", "Zander", "Meier"])
    }

    @Test("Zähler (Z-AT2b-14): „12 Personen“, mit Filter „‹n› von ‹m› Personen“, Einzahl bei einer Person")
    func zaehler() {
        #expect(Lernendenblatt.zaehler(treffer: 12, gesamt: 12, gefiltert: false) == "12 Personen")
        #expect(Lernendenblatt.zaehler(treffer: 1, gesamt: 1, gefiltert: false) == "1 Person")
        #expect(Lernendenblatt.zaehler(treffer: 1, gesamt: 12, gefiltert: true) == "1 von 12 Personen")
        #expect(Lernendenblatt.zaehler(treffer: 0, gesamt: 1, gefiltert: true) == "0 von 1 Person")
        #expect(Lernendenblatt.zaehler(treffer: 1, gesamt: 1, gefiltert: true) == "1 von 1 Person")
    }

    @Test("Plätze (E499): archivierte belegen einen Platz; ausgeblendet nennt der Zusatz ihre Zahl")
    func plaetze() throws {
        var (b, ids) = try bestand()
        let bio = try #require(ids["6a"])
        let anna = try #require(b.lernende.first { $0.nachname == "Müller" }).id
        let ohne = try #require(Lernendenverzeichnis(b).gruppe(bio))
        #expect(Lernendenblatt.plaetze(ohne, Lernendenverzeichnis(b), archivierte: false) == "3 von 40 Plätzen")
        b = b.mitArchivierterPerson(anna, jetzt: t)
        let v = Lernendenverzeichnis(b)
        let g = try #require(v.gruppe(bio))
        #expect(Lernendenblatt.plaetze(g, v, archivierte: false) == "3 von 40 Plätzen (davon 1 archiviert)")
        #expect(Lernendenblatt.plaetze(g, v, archivierte: true) == "3 von 40 Plätzen", "sichtbar: kein Zusatz")
    }

    @Test("Leere Liste (Z-AT2b-15): was Suche oder Filter sagen, wenn nichts übrig bleibt")
    func leerHinweis() {
        #expect(Lernendenblatt.leerHinweis(suche: "xy", nurOffen: false) == "Nichts passt zu „xy“.")
        #expect(Lernendenblatt.leerHinweis(suche: " xy ", nurOffen: true) == "Nichts passt zu „xy“.")
        #expect(Lernendenblatt.leerHinweis(suche: "  ", nurOffen: true) == "Keine Person mit offenen Anliegen.")
        #expect(Lernendenblatt.leerHinweis(suche: "", nurOffen: false) == nil)
    }

    @Test("Der Kopf der vorn ordnenden Spalte (E498): nur sie, nach einem Kopfklick die neue")
    func vorn() {
        let vorgabe = Personenzeile.vorgabe
        #expect(Lernendenblatt.vorn(vorgabe, \Personenzeile.nachname))
        #expect(!Lernendenblatt.vorn(vorgabe, \Personenzeile.vorname), "der Zweitschlüssel nicht")
        let vorname = Personenspalte.vorname.ordnung
        #expect(Lernendenblatt.vorn(vorname, \Personenzeile.vorname) && !Lernendenblatt.vorn(vorname, \Personenzeile.nachname))
        #expect(!Lernendenblatt.vorn([KeyPathComparator<Personenzeile>](), \Personenzeile.nachname), "ohne Ordnung keine")
    }
}
