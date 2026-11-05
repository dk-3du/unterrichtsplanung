// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Keine Grenze je Lerngruppe, Anliegen, Termin und Eingabe (v90, BB2, E978) ──
// Bis 2.4.0 hielten 40 je Lerngruppe (E279) die Gruppe, die Sammelgriffe, das Zusammenführen, den Import, die Eingabe von
// Hand, die Betroffenen eines Anliegens und „Alle Mitglieder der Lerngruppe“ an. Seit Fassung 2 der Jahresdatei (BB1) liest
// sie jede Zahl; jede Stelle wird hier mit 41 und mit 300 geprüft. Es bleibt die Grenze des Schuljahrs (2 000 Personen,
// archivierte eingeschlossen). Den Termin prüft `TerminkopplungPruefungen.ohneGrenzeDerPersonen` am Speicher.

@Suite("v90 BB2: keine Grenze je Lerngruppe, Anliegen und Eingabe — je mit 41 und 300 (E978)")
@MainActor
struct GrenzenFallenPruefungen {

    private static let s = "2026-10-31T08:00:00.000Z"
    private static let jetzt = "2026-10-31T09:00:00.000Z"
    private static let zahlen = [41, 300]

    private static func person(_ id: String) -> Lernender {
        Lernender(id: id, vorname: "V-\(id)", nachname: "N-\(id)", angelegt: s, geaendert: s, archiviert: "")
    }

    private static func gruppe(_ id: String, _ name: String, _ mitglieder: [String]) -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .kurs, mitglieder: mitglieder, zeilen: [], skalen: [:], halbjahreswechsel: "",
                   geaendert: s, archiviert: "")
    }

    private static func ids(_ von: Int, _ bis: Int) -> [String] { (von..<bis).map { "p-\($0)" } }

    /// `personen` Personen p-0, p-1, …; „Voll“ (g-voll) mit den ersten `voll`, „Leer“ (g-leer) ohne Mitglieder.
    private static func bestand(personen: Int, voll: Int) -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = ids(0, personen).map(person)
        b.lerngruppen = [gruppe("g-voll", "Voll", ids(0, voll)), gruppe("g-leer", "Leer", [])]
        return b
    }

    private static func mitglieder(_ b: Lernendenbestand, _ gruppe: String) -> [String] {
        b.lerngruppen.first { $0.id == gruppe }?.mitglieder ?? []
    }

    @Test("Eingabe von Hand: 41 und 300 Namen in einer Eingabe, alle neu in der Lerngruppe; eine Person von anderswo kommt in eine Gruppe mit 40 und mit 299")
    func eingabeVonHand() {
        for n in Self.zahlen {
            let gelesen = Namenszeilen.lesen((1...n).map { "Nachname\($0), Vorname\($0)" }.joined(separator: "\n"))
            #expect(gelesen.fehler.isEmpty && gelesen.namen.count == n, "\(n) Namen ohne Fehler")
            let ergebnis = Self.bestand(personen: 0, voll: 0)
                .mitPersonen(gelesen.namen, inGruppe: "g-leer", jetzt: Self.jetzt)
            #expect(ergebnis.neu.count == n && ergebnis.ueberGrenze == 0, "alle \(n) neu")
            #expect(Self.mitglieder(ergebnis.bestand, "g-leer").count == n)

            let b = Self.bestand(personen: n, voll: n - 1)
            let zugeordnet = b.mitPersonen([Namenszeilen.Name(vorname: "V-p-\(n - 1)", nachname: "N-p-\(n - 1)")],
                                           inGruppe: "g-voll", jetzt: Self.jetzt)
            #expect(zugeordnet.zugeordnet == ["p-\(n - 1)"] && Self.mitglieder(zugeordnet.bestand, "g-voll").count == n,
                    "zugeordnet bis \(n)")
        }
    }

    @Test("Z-BB2-01: Die Ausgänge über das Wörterbuch der Namen wie bisher — auch wenn derselbe Name im Text zweimal steht")
    func ausgaengeWieBisher() {
        var b = Self.bestand(personen: 4, voll: 2)
        b.lernende[1].archiviert = Self.s
        b.lernende.append(Lernender(id: "q-3", vorname: "V-p-3", nachname: "N-p-3", angelegt: Self.s, geaendert: Self.s,
                                    archiviert: ""))
        func name(_ v: String, _ n: String) -> Namenszeilen.Name { Namenszeilen.Name(vorname: v, nachname: n) }
        let namen = [name("V-p-0", "N-p-0"), name("V-p-1", "N-p-1"), name("V-p-2", "N-p-2"), name("V-p-2", "N-p-2"),
                     name("V-p-3", "N-p-3"), name("Neu", "Name"), name("Neu", "Name"), name(" neu ", "NAME"), name("", "")]
        let e = b.mitPersonen(namen, inGruppe: "g-voll", jetzt: Self.jetzt)
        func art(_ a: Namensausgang) -> String {
            switch a {
            case .neu: "neu"
            case .zugeordnet(let id): "zugeordnet \(id)"
            case .zurueckgeholt(let id): "zurückgeholt \(id)"
            case .schonDa: "schon da"
            case .gleichnamig: "gleichnamig"
            case .ueberGrenze: "über der Grenze"
            case .leer: "leer"
            }
        }
        #expect(e.ausgaenge.map(art) == ["schon da", "zurückgeholt p-1", "zugeordnet p-2", "schon da", "gleichnamig", "neu",
                                         "schon da", "schon da", "leer"])
        #expect(Self.mitglieder(e.bestand, "g-voll").count == 4, "p-0, p-1, p-2 und die neue — jede einmal")
        #expect(e.bestand.lernende.count == b.lernende.count + 1)
    }

    @Test("Eine Person aufnehmen und umziehen in eine Lerngruppe mit 40 und mit 299 — die Menüs zeigen kein „(voll)“")
    func einzeln() throws {
        for n in Self.zahlen {
            let letzte = "p-\(n - 1)"
            let b = Self.bestand(personen: n, voll: n - 1)
            let auf = try #require(b.mitMitglied(letzte, inGruppe: "g-voll", jetzt: Self.jetzt), "aufgenommen (\(n))")
            #expect(Self.mitglieder(auf, "g-voll").count == n)

            var c = b
            c.lerngruppen[1].mitglieder = [letzte]
            let um = try #require(c.mitUmzug(letzte, von: "g-leer", nach: "g-voll", jetzt: Self.jetzt), "umgezogen (\(n))")
            #expect(Self.mitglieder(um, "g-voll").count == n && Self.mitglieder(um, "g-leer").isEmpty)

            let menue = Mitgliedschaftsmenue(person: letzte, aus: "g-leer", bestand: c)
            let haken = try #require(menue.haekchen.first { $0.id == "g-voll" })
            #expect(haken.titel == "Voll" && haken.waehlbar, "Häkchen ohne „(voll)“ (\(n))")
            #expect(menue.umziehen.map(\.titel) == ["Voll"] && menue.umziehen.allSatisfy(\.waehlbar), "Umziehen nach (\(n))")
            let sammel = Sammelmenue(personen: [letzte], aus: "g-leer", bestand: c)
            #expect(sammel.aufnehmen.map(\.titel) == ["Voll"] && sammel.aufnehmen.allSatisfy(\.waehlbar),
                    "Sammelleiste (\(n))")
        }
    }

    @Test("„Auch aufnehmen in“ und „Umziehen nach“ für mehrere: auf 41 und 300 Mitglieder — ohne Meldung, alle in einem Schritt")
    func sammelgriffe() {
        for n in Self.zahlen {
            var b = Self.bestand(personen: n, voll: n - 2)
            let zwei = ["p-\(n - 2)", "p-\(n - 1)"]
            let auf = b.mitMitgliedern(zwei, inGruppe: "g-voll", jetzt: Self.jetzt)
            #expect(auf.grund == nil && auf.zahl == 2 && Self.mitglieder(auf.bestand, "g-voll").count == n,
                    "aufgenommen bis \(n): \(auf.grund ?? "")")
            b.lerngruppen[1].mitglieder = zwei
            let um = b.mitUmzuegen(zwei, von: "g-leer", nach: "g-voll", jetzt: Self.jetzt)
            #expect(um.grund == nil && um.zahl == 2 && Self.mitglieder(um.bestand, "g-voll").count == n
                        && Self.mitglieder(um.bestand, "g-leer").isEmpty, "umgezogen bis \(n): \(um.grund ?? "")")
        }
    }

    @Test("Zusammenführen auf 41 und 300 Mitglieder, eine archivierte eingeschlossen — ohne Grund")
    func zusammenfuehren() {
        for n in Self.zahlen {
            var b = Self.bestand(personen: n, voll: n / 2)
            b.lernende[0].archiviert = Self.s
            b.lerngruppen[1].mitglieder = Self.ids(n / 2, n)
            let (neu, grund) = b.mitZusammenfuehrung("g-leer", in: "g-voll", jetzt: Self.jetzt)
            #expect(grund == nil, "\(n): \(grund ?? "")")
            #expect(Self.mitglieder(neu, "g-voll").count == n)
            #expect(neu.lerngruppen.first { $0.id == "g-leer" }?.archiviert.isEmpty == false, "die andere ist archiviert")
        }
    }

    @Test("IServ-Import: 41 und 300 Zeilen in eine Lerngruppe — alle neu, keine übergangen")
    func importOhneGrenze() throws {
        for n in Self.zahlen {
            let daten = ImportPruefungen.datei((1...n).map { ImportPruefungen.zeile("Vor\($0)", "Nach\($0)") })
            let (neu, bilanz) = Self.bestand(personen: 0, voll: 0)
                .mitImport(try ImportPruefungen.lesung(daten), ziel: .gruppe("g-leer"), jetzt: Self.jetzt)
            #expect(bilanz.neu.count == n && bilanz.uebergangen.isEmpty, "\(n): \(bilanz.kurz)")
            #expect(Self.mitglieder(neu, "g-leer").count == n)
        }
    }

    @Test("Betroffene: ein Anliegen mit 41 und 300 Betroffenen anlegen; eine weitere Person aufnehmen bis 41 und 300")
    func betroffene() throws {
        for n in Self.zahlen {
            let b = Self.bestand(personen: n, voll: n)
            let (neu, id) = try #require(b.mitNeuemAnliegen(.massnahme, titel: "Nacharbeit", lerngruppe: "g-voll",
                                                            betroffene: Self.ids(0, n), datum: "2026-10-30", frist: "",
                                                            jetzt: Self.jetzt))
            #expect(neu.anliegen.first { $0.id == id }?.betroffene.count == n, "angelegt mit \(n)")
            let (klein, k) = try #require(b.mitNeuemAnliegen(.massnahme, titel: "Nachtrag", lerngruppe: "g-voll",
                                                              betroffene: Self.ids(0, n - 1), datum: "2026-10-30", frist: "",
                                                              jetzt: Self.jetzt))
            let dazu = klein.mitBetroffenem(k, "p-\(n - 1)", true, jetzt: Self.jetzt)
            #expect(dazu.anliegen.first { $0.id == k }?.betroffene.count == n, "aufgenommen bis \(n)")
        }
    }

    @Test("„Alle Mitglieder der Lerngruppe“ an einer Vereinbarung einer Gruppe mit 41 und 300 — alle betroffen")
    func alleMitglieder() throws {
        for n in Self.zahlen {
            let b = Self.bestand(personen: n, voll: n)
            let (mit, id) = try #require(b.mitNeuemAnliegen(.vereinbarung, titel: "Handyregel", lerngruppe: "g-voll",
                                                            betroffene: ["p-0"], datum: "2026-10-30", frist: "",
                                                            jetzt: Self.jetzt))
            let v = try #require(mit.anliegen.first { $0.id == id })
            let ids = Vereinbarungsliste.alleAufzunehmen(mit.lernende, v, gruppe: "g-voll")
            #expect(ids.count == n - 1)
            let alle = Vereinbarungsliste.alleAufnehmen(mit, id, ids, jetzt: Self.jetzt)
            #expect(alle.anliegen.first { $0.id == id }?.betroffene.count == n, "alle \(n)")
        }
    }

    @Test("Die Zeile unter der Mitgliederliste zählt die aktiven wie der Kopf, archivierte als Zusatz — ohne Grenze")
    func mitgliederzeile() {
        var b = Self.bestand(personen: 300, voll: 300)
        #expect(Lernendenblatt.mitgliederzeile(b.lerngruppen[0], Lernendenverzeichnis(b)) == "300 Mitglieder")
        b.lernende[0].archiviert = Self.s
        b.lernende[1].archiviert = Self.s
        let v = Lernendenverzeichnis(b)
        #expect(Lernendenblatt.mitgliederzeile(b.lerngruppen[0], v) == "298 Mitglieder, dazu 2 archiviert")
        #expect(v.mitgliederzahl("g-voll") == 298, "wie im Kopf der Lerngruppe")
        var c = Self.bestand(personen: 2, voll: 2)
        c.lernende[1].archiviert = Self.s
        #expect(Lernendenblatt.mitgliederzeile(c.lerngruppen[0], Lernendenverzeichnis(c)) == "1 Mitglied, dazu 1 archiviert")
        #expect(Lernendenblatt.mitgliederzeile(c.lerngruppen[1], Lernendenverzeichnis(c)) == "0 Mitglieder")
    }

    @Test("Es bleibt die Grenze des Schuljahrs (2 000 Personen, archivierte eingeschlossen) — beim Eintragen und im Import mit ihrem Wortlaut")
    func grenzeDesSchuljahrs() throws {
        let zweitausend = Lernendenbestand.tausender(Kennwerte.maxLernende)
        let b = Self.bestand(personen: Kennwerte.maxLernende - 1, voll: 0)
        let drei = (1...3).map { Namenszeilen.Name(vorname: "Neu\($0)", nachname: "Name") }
        let ergebnis = b.mitPersonen(drei, inGruppe: "g-leer", jetzt: Self.jetzt)
        #expect(ergebnis.neu.count == 1 && ergebnis.ueberGrenze == 2, "Vorbedingung")
        #expect(LernendenDialog.eintragsmeldung(ergebnis)
                == "1 eingetragen — 2 blieben draußen: höchstens \(zweitausend) Personen je Schuljahr, archivierte "
                    + "eingeschlossen.")
        let zwei = b.mitPersonen(Array(drei.prefix(2)), inGruppe: "g-leer", jetzt: Self.jetzt)
        #expect(LernendenDialog.eintragsmeldung(zwei)
                == "1 eingetragen — 1 blieb draußen: höchstens \(zweitausend) Personen je Schuljahr, archivierte "
                    + "eingeschlossen.", "Einzahl (Z-BB2-06)")
        // Über der Grenze und mehrfach zugleich (Z-BB4c-01): ohne Warnung, die Grenze ist genannt — dahinter der Mehrfach-Teil.
        var mitMax = Self.bestand(personen: Kennwerte.maxLernende - 3, voll: 0)
        for i in 0..<2 {
            mitMax.lernende.append(Lernender(id: "max-\(i)", vorname: "Max", nachname: "Mai", angelegt: Self.s, geaendert: Self.s,
                                             archiviert: ""))
        }
        let beides = mitMax.mitPersonen([Namenszeilen.Name(vorname: "Max", nachname: "Mai")] + drei, inGruppe: "g-leer",
                                        jetzt: Self.jetzt)
        #expect(beides.neu.count == 1 && beides.ueberGrenze == 2 && beides.gleichnamig == 1, "Vorbedingung")
        #expect(LernendenDialog.eintragsmeldung(beides)
                == "1 eingetragen — 2 blieben draußen: höchstens \(zweitausend) Personen je Schuljahr, archivierte "
                    + "eingeschlossen — 1 Name mehrfach vorhanden, daher nicht eingetragen.")
        #expect(Lernendenblatt.ueberGrenzeText == "über der Grenze des Schuljahrs")
        let daten = ImportPruefungen.datei([ImportPruefungen.zeile("Eins", "Neu"), ImportPruefungen.zeile("Zwei", "Neu")])
        let (_, bilanz) = b.mitImport(try ImportPruefungen.lesung(daten), ziel: .gruppe("g-leer"), jetzt: Self.jetzt)
        #expect(bilanz.neu.count == 1
                && bilanz.uebergangen.map(\.grund) == ["Über der Grenze von \(zweitausend) Personen je Schuljahr."])
    }
}
