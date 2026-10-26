// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Der IServ-Import (AP13, Plan 4.4, E254) ───────────────────────────────
// Kodierung, Trenner, Zerlegen nach RFC 4180, Kopfzeile, Zuordnung, Zeilen —
// und der Abgleich mit der Zielgruppe. Gelesen werden nur Vorname, Nachname,
// Klasse/Information.

@Suite("IServ-Import: Kodierung, Trenner, Zeilen, Abgleich")
struct ImportPruefungen {

    static let stempel = "2026-10-04T08:00:00.000Z"
    static let jetzt = "2026-10-04T15:00:00.000Z"

    /// Die Kopfzeile der Musterdatei des Nutzers (Plan 4.4).
    static let kopf = #"Account;Vorname;Nachname;Status;"Erstellt am";"Erstellt von";Klasse/Information;E-Mail-Adresse"#

    static func zeile(_ vorname: String, _ nachname: String, klasse: String = "G6a") -> String {
        "\(vorname.lowercased()).\(nachname.lowercased());\(vorname);\(nachname);aktiviert;01.08.2026;\"Administrator\";"
            + "\(klasse);\(vorname.lowercased())@iserv.de"
    }

    /// Wie die Saat: BOM, CRLF, kein Zeilenwechsel am Ende.
    static func datei(_ zeilen: [String], bom: Bool = true) -> Data {
        (bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(([kopf] + zeilen).joined(separator: "\r\n").utf8)
    }

    /// Drei Personen in „6a“ (g-1), dazu eine ohne Gruppe.
    static func bestand() -> Lernendenbestand {
        let s = stempel
        func person(_ id: String, _ vorname: String, _ nachname: String) -> Lernender {
            Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: s, geaendert: s, archiviert: "")
        }
        return Lernendenbestand(
            planung: "2026-08-01T08:00:00.000Z", schuljahr: "2026/27", erstellt: s, geaendert: s,
            lernende: [person("l-1", "Anna", "Abel"), person("l-2", "Ben", "Bauer"), person("l-3", "Cem", "Çelik"),
                       person("l-4", "Dora", "Dietz")],
            lerngruppen: [Lerngruppe(id: "g-1", name: "6a", art: .klasse,
                                     mitglieder: ["l-1", "l-2", "l-3"], zeilen: [], skalen: [:], halbjahreswechsel: "",
                                     geaendert: s, archiviert: "")],
            anliegen: [], rueckmeldungen: [], erfassung: [], beurteilung: [])
    }

    /// Der ganze Weg: Byte → Text → Tabelle → Zuordnung aus dem Kopf → Zeilen.
    static func lesung(_ daten: Data) throws -> IServImport.Lesung {
        let text = try #require(IServImport.entschluesseln(daten))
        let tabelle = IServImport.zerlegen(text.inhalt, trenner: IServImport.trennerErkennen(text.inhalt))
        let kopf = try #require(tabelle.first)
        let zuordnung = try #require(IServImport.zuordnungAusKopf(kopf))
        return IServImport.lesen(tabelle, kopfzeile: true, zuordnung: zuordnung)
    }

    // ── Kodierung ─────────────────────────────────────────────────────────

    @Test("Kodierung: UTF-8 mit BOM und Umlauten, ohne BOM, Windows-1252, ISO-8859-15 als letzter Rückfall; gewählt gilt genau die")
    func kodierung() throws {
        let mitBom = try #require(IServImport.entschluesseln(Data([0xEF, 0xBB, 0xBF]) + Data("Müller;Öz;ß".utf8)))
        #expect(mitBom.kodierung == .utf8 && mitBom.bom && mitBom.inhalt == "Müller;Öz;ß")
        let ohne = try #require(IServImport.entschluesseln(Data("Müller".utf8)))
        #expect(ohne.kodierung == .utf8 && !ohne.bom)
        // „Müller“ in Windows-1252: ü = 0xFC — kein gültiges UTF-8.
        let alt = try #require(IServImport.entschluesseln(Data([0x4D, 0xFC, 0x6C, 0x6C, 0x65, 0x72])))
        #expect(alt.kodierung == .windows1252 && alt.inhalt == "Müller")
        // 0x81 ist in Windows-1252 nicht belegt: ISO-8859-15.
        let iso = try #require(IServImport.entschluesseln(Data([0x41, 0x81, 0xA4])))
        #expect(iso.kodierung == .iso885915 && iso.inhalt.hasSuffix("€"), "0xA4 ist in ISO-8859-15 das Euro-Zeichen")
        // Gewählt: genau diese — UTF-8 auf Windows-1252-Bytes geht nicht.
        #expect(IServImport.entschluesseln(Data([0x4D, 0xFC]), kodierung: .utf8) == nil)
        #expect(IServImport.entschluesseln(Data([0x4D, 0xFC]), kodierung: .iso885915)?.inhalt == "Mü")
    }

    // ── Trenner und Zerlegen ──────────────────────────────────────────────

    @Test("Trenner: Semikolon, Komma, Tab — gezählt außerhalb der Anführungszeichen, gleichmäßig verteilt gewinnt")
    func trenner() {
        #expect(IServImport.trennerErkennen("a;b;c\r\nd;e;f") == .semikolon)
        #expect(IServImport.trennerErkennen("a,b,c\nd,e,f") == .komma)
        #expect(IServImport.trennerErkennen("a\tb\tc\nd\te\tf") == .tab)
        // Kommas in Anführungszeichen zählen nicht: Semikolon trennt.
        #expect(IServImport.trennerErkennen("\"Abel, Anna\";6a\n\"Bauer, Ben\";6a") == .semikolon)
    }

    @Test("Zerlegen nach RFC 4180: Trenner und Zeilenwechsel in Anführungszeichen, \"\" als Zeichen; CRLF, LF und CR trennen; Leerzeilen bleiben gezählt")
    func zerlegen() {
        let text = "a;\"b;c\";\"d\"\"e\"\r\n\r\n\"zwei\nZeilen\";x\rletzte"
        #expect(IServImport.zerlegen(text, trenner: .semikolon)
                == [["a", "b;c", "d\"e"], [""], ["zwei\nZeilen", "x"], ["letzte"]])
        #expect(IServImport.zerlegen("", trenner: .semikolon) == [])
        #expect(IServImport.zerlegen("\"offen", trenner: .semikolon) == [["offen"]], "ein offenes Anführungszeichen nimmt den Rest")
    }

    // ── Kopfzeile, Zuordnung, Zeilen ──────────────────────────────────────

    @Test("Kopfzeile: an Vorname, Nachname, Klasse/Information erkannt — sonst keine; nur diese drei Spalten werden gelesen")
    func kopfzeile() throws {
        let kopf = IServImport.zerlegen(Self.kopf, trenner: .semikolon)[0]
        #expect(IServImport.zuordnungAusKopf(kopf) == IServImport.Zuordnung(vorname: 1, nachname: 2, klasse: 6))
        #expect(IServImport.zuordnungAusKopf([" vorname ", "NACHNAME"]) == IServImport.Zuordnung(vorname: 0, nachname: 1, klasse: nil))
        #expect(IServImport.zuordnungAusKopf(["Anna", "Abel", "6a"]) == nil, "Daten statt Kopf: keine Kopfzeile")
    }

    @Test("Zeilen: Leerzeile übergangen ohne Befund; ohne Namen und über 100 Zeichen benannt mit Zeilennummer; Steuerzeichen und Leerraum bereinigt")
    func zeilen() throws {
        let lang = String(repeating: "x", count: Kennwerte.maxLernendenname + 1)
        let tabelle = IServImport.zerlegen([Self.kopf, Self.zeile("Anna", "Abel"), "", "x;;;aktiviert;;;6a;x@iserv.de",
                                            Self.zeile(lang, "Lang"), "a.b; Ben\u{0007}  Benno ;  Bauer ;s;d;v;7b;m"]
                                               .joined(separator: "\r\n"), trenner: .semikolon)
        let zuordnung = try #require(IServImport.zuordnungAusKopf(tabelle[0]))
        let lesung = IServImport.lesen(tabelle, kopfzeile: true, zuordnung: zuordnung)
        #expect(lesung.zeilen == [IServImport.Zeile(nummer: 2, vorname: "Anna", nachname: "Abel", klasse: "G6a"),
                                  IServImport.Zeile(nummer: 6, vorname: "Ben Benno", nachname: "Bauer", klasse: "7b")])
        #expect(lesung.fehler.map(\.nummer) == [4, 5])
        #expect(lesung.fehler[0].grund.contains("Vor- und Nachname") && lesung.fehler[1].grund.contains("100"))
        // Ohne Kopfzeile zählt die erste Zeile mit; ohne Vor- oder Nachnamen-Spalte wird nichts gelesen.
        #expect(IServImport.lesen(Array(tabelle.dropFirst()), kopfzeile: false, zuordnung: zuordnung).zeilen.first?.nummer == 1)
        #expect(IServImport.lesen(tabelle, kopfzeile: true, zuordnung: IServImport.Zuordnung(vorname: 1, nachname: nil, klasse: nil))
                    .zeilen.isEmpty)
    }

    // ── Abgleich mit der Zielgruppe (E254) ────────────────────────────────

    @Test("Musterdatei in eine Gruppe: 3 neu / 1 unverändert / 1 übergangen; neue tragen den Zeitpunkt des Imports (E251); Fehlende genannt, nicht gelöscht")
    func muster() throws {
        let daten = Self.datei([Self.zeile("Vorname1", "Nachname1"), Self.zeile("Vorname2", "Nachname2"),
                                Self.zeile("Vorname3", "Nachname3"), Self.zeile("anna", "ABEL"),
                                "ohne.namen;;;aktiviert;01.08.2026;\"Administrator\";G6a;ohne.namen@iserv.de"])
        let (neu, bilanz) = Self.bestand().mitImport(try Self.lesung(daten), ziel: .gruppe("g-1"), jetzt: Self.jetzt)
        #expect(bilanz.kurz == "3 neu · 1 unverändert · 1 übergangen")
        #expect(bilanz.uebergangen.map(\.nummer) == [6])
        let gruppe = try #require(neu.lerngruppen.first { $0.id == "g-1" })
        #expect(gruppe.mitglieder.count == 6)
        let angelegt = neu.lernende.filter { $0.nachname.hasPrefix("Nachname") }
        #expect(angelegt.count == 3 && angelegt.allSatisfy { $0.angelegt == Self.jetzt && $0.rufname.isEmpty })
        #expect(Set(bilanz.fehlende) == ["l-2", "l-3"], "Ben und Cem fehlen in der Datei — genannt, nicht gelöscht")
        #expect(neu.lernende.count == 7 && neu.lernende.allSatisfy { $0.archiviert.isEmpty })
    }

    @Test("Gleichnamige: zweimal in der Datei oder zweimal in der Gruppe — genannt, nichts geraten; eine Dublette der Gruppe bleibt unverändert")
    func gleichnamige() throws {
        var b = Self.bestand()
        b.lernende.append(Lernender(id: "l-5", vorname: "Anna", nachname: "Abel", angelegt: Self.stempel,
                                    geaendert: Self.stempel, archiviert: ""))
        b.lerngruppen[0].mitglieder.append("l-5")
        let daten = Self.datei([Self.zeile("Max", "Mai"), Self.zeile("Ben", "Bauer"), Self.zeile("Max", "Mai"),
                                Self.zeile("Anna", "Abel")])
        let (neu, bilanz) = b.mitImport(try Self.lesung(daten), ziel: .gruppe("g-1"), jetzt: Self.jetzt)
        #expect(bilanz.neu.isEmpty && bilanz.unveraendert.map(\.nummer) == [3])
        #expect(bilanz.uebergangen.map(\.nummer) == [2, 4, 5])
        #expect(bilanz.uebergangen[0].grund.contains("Zeilen 2 und 4") && bilanz.uebergangen[2].grund.contains("Gleichnamige"))
        #expect(neu.lernende.count == b.lernende.count, "niemand angelegt")
        // Z-AT1-01: Wen die Datei nennt — auch zweimal —, der fehlt nicht. Ben zweimal, Cem nicht genannt.
        let zweimalBen = Self.datei([Self.zeile("Anna", "Abel"), Self.zeile("Ben", "Bauer"), Self.zeile("Ben", "Bauer")])
        let benBilanz = Self.bestand().mitImport(try Self.lesung(zweimalBen), ziel: .gruppe("g-1"), jetzt: Self.jetzt).bilanz
        #expect(benBilanz.uebergangen.map(\.nummer) == [3, 4] && benBilanz.fehlende == ["l-3"],
                "Ben steht in der Datei — nicht fehlend, nichts geraten")
    }

    @Test("Über die ganze Jahresdatei (E288): Eine Person ohne Platz in der Zielgruppe wird zugeordnet; zwei Gleichnamige der Jahresdatei genannt")
    func zuordnenBeimImport() throws {
        var b = Self.bestand()
        for id in ["l-8", "l-9"] {
            b.lernende.append(Lernender(id: id, vorname: "Max", nachname: "Mai", angelegt: Self.stempel,
                                        geaendert: Self.stempel, archiviert: ""))
        }
        let daten = Self.datei([Self.zeile("Dora", "Dietz"), Self.zeile("Eva", "Ernst"), Self.zeile("Max", "Mai"),
                                Self.zeile("Ben", "Bauer")])
        let (neu, bilanz) = b.mitImport(try Self.lesung(daten), ziel: .gruppe("g-1"), jetzt: Self.jetzt)
        #expect(bilanz.zugeordnet.map(\.nummer) == [2] && bilanz.neu.map(\.nummer) == [3] && bilanz.unveraendert.map(\.nummer) == [5])
        #expect(bilanz.uebergangen.map(\.nummer) == [4] && bilanz.uebergangen[0].grund.contains("Gleichnamige in diesem Schuljahr"))
        #expect(bilanz.kurz == "1 neu · 1 zugeordnet · 1 unverändert · 1 übergangen")
        #expect(neu.lernende.count == b.lernende.count + 1 && neu.lerngruppen[0].mitglieder.contains("l-4"))
    }

    @Test("Grenze: 40 je Lerngruppe (E279) — was darüber geht, wird mit Zeilennummer übergangen")
    func grenze() throws {
        var b = Self.bestand()
        for i in 4..<Kennwerte.maxMitgliederJeLerngruppe {
            b.lernende.append(Lernender(id: "l-x\(i)", vorname: "V\(i)", nachname: "N\(i)", angelegt: Self.stempel,
                                        geaendert: Self.stempel, archiviert: ""))
            b.lerngruppen[0].mitglieder.append("l-x\(i)")
        }
        #expect(b.lerngruppen[0].mitglieder.count == Kennwerte.maxMitgliederJeLerngruppe - 1)
        let daten = Self.datei([Self.zeile("Eins", "Neu"), Self.zeile("Zwei", "Neu"), Self.zeile("Drei", "Neu")])
        let (_, bilanz) = b.mitImport(try Self.lesung(daten), ziel: .gruppe("g-1"), jetzt: Self.jetzt)
        #expect(bilanz.neu.map(\.nummer) == [2])
        #expect(bilanz.uebergangen.map(\.nummer) == [3, 4] && bilanz.uebergangen.allSatisfy { $0.grund.contains("40") })
    }

    @Test("Neue Lerngruppen erscheinen geordnet wie alle Listen (E343, Z-AS5-08) — angelegt in der Folge der Datei")
    func neueGruppenGeordnet() throws {
        let daten = Self.datei([Self.zeile("Eva", "Ernst", klasse: "10a"), Self.zeile("Finn", "Fink", klasse: "5b"),
                                Self.zeile("Gil", "Gras", klasse: "7c")])
        let (neu, bilanz) = Self.bestand().mitImport(try Self.lesung(daten), ziel: .jeKlasse, jetzt: Self.jetzt)
        #expect(bilanz.neueGruppen == ["10a", "5b", "7c"], "angelegt in der Folge der Datei")
        #expect(bilanz.neueGruppenGeordnet == ["5b", "7c", "10a"], Comment(rawValue: bilanz.neueGruppenGeordnet.joined(separator: ", ")))
        #expect(neu.lerngruppen.suffix(3).map(\.name) == ["10a", "5b", "7c"], "die Jahresdatei bleibt in Anlegefolge")
    }

    @Test("Zielgruppen: neue Gruppe; je Klasse eine — die erste gleichnamige (E353, V10), sonst neu; ohne Klasse übergangen")
    func zielgruppen() throws {
        let daten = Self.datei([Self.zeile("Eva", "Ernst", klasse: "7b"), Self.zeile("Finn", "Fink", klasse: ""),
                                Self.zeile("Anna", "Abel", klasse: "6a"), Self.zeile("Gil", "Gras", klasse: "7b"),
                                Self.zeile("Hana", "Huber", klasse: "6a")])
        let lesung = try Self.lesung(daten)
        let (neu, bilanz) = Self.bestand().mitImport(lesung, ziel: .neueGruppe("AG Robotik"), jetzt: Self.jetzt)
        // Anna Abel steht schon in „6a“ — dieselbe Person, zugeordnet (E288).
        #expect(bilanz.neu.count == 4 && bilanz.zugeordnet.map(\.nummer) == [4] && bilanz.neueGruppen == ["AG Robotik"])
        #expect(neu.lerngruppen.first { $0.name == "AG Robotik" }?.mitglieder.count == 5)

        var b = Self.bestand()
        b.lerngruppen.append(Lerngruppe(id: "g-2", name: "6a", art: .klasse, mitglieder: ["l-1"], zeilen: [],
                                        skalen: [:], halbjahreswechsel: "", geaendert: Self.stempel, archiviert: ""))
        let (jeKlasse, klassenbilanz) = b.mitImport(lesung, ziel: .jeKlasse, jetzt: Self.jetzt)
        #expect(klassenbilanz.neueGruppen == ["7b"])
        #expect(klassenbilanz.unveraendert.map(\.nummer) == [4], "Anna Abel steht schon in der ersten „6a“")
        #expect(klassenbilanz.uebergangen.map(\.nummer) == [3] && klassenbilanz.uebergangen[0].grund.contains("Klasse"))
        #expect(jeKlasse.lerngruppen.first { $0.name == "7b" }?.mitglieder.count == 2)
        #expect(jeKlasse.lerngruppen.first { $0.id == "g-1" }?.mitglieder.count == 4, "Hana Huber kommt in die erste „6a“ (V10)")
        #expect(jeKlasse.lerngruppen.first { $0.id == "g-2" }?.mitglieder.count == 1, "die zweite „6a“ bleibt unberührt")
        #expect(Self.bestand().mitImport(lesung, ziel: .gruppe("g-unbekannt"), jetzt: Self.jetzt).bilanz.neu.isEmpty)

        // Die einzige „6a“ trifft „Je Klasse“ — Hana Huber kommt hinein, keine zweite „6a“.
        let (eine, einebilanz) = Self.bestand().mitImport(lesung, ziel: .jeKlasse, jetzt: Self.jetzt)
        #expect(einebilanz.neueGruppen == ["7b"], "keine zweite „6a“")
        #expect(eine.lerngruppen.first { $0.id == "g-1" }?.mitglieder.count == 4, "Hana Huber kommt in „6a“")
    }

    @Test("„Je Klasse“ (E353): Groß/Klein unerheblich, archivierte zählen nicht")
    func jeKlasseGrenzfaelle() throws {
        let gross = try Self.lesung(Self.datei([Self.zeile("Hana", "Huber", klasse: "6A")]))
        let (b, bilanz) = Self.bestand().mitImport(gross, ziel: .jeKlasse, jetzt: Self.jetzt)
        #expect(bilanz.neueGruppen.isEmpty, "„6A“ trifft „6a“")
        #expect(b.lerngruppen.first { $0.id == "g-1" }?.mitglieder.count == 4)
        var archiviert = Self.bestand()
        archiviert.lerngruppen[0].archiviert = Self.stempel
        let (_, neu) = archiviert.mitImport(gross, ziel: .jeKlasse, jetzt: Self.jetzt)
        #expect(neu.neueGruppen == ["6A"], "eine archivierte „6a“ zählt nicht — neu")
    }

    @Test("Fehlende getrennt (E368): ohne andere Gruppe archivieren, in anderer Gruppe nur aus der Zielgruppe nehmen; Einträge und übrige Mitgliedschaften bleiben (E252)")
    func fehlendeArchivieren() throws {
        var b = Self.bestand()
        // Cem (l-3) steht auch in der Lese-AG.
        b.lerngruppen.append(Lerngruppe(id: "g-2", name: "Lese-AG", art: .kurs, mitglieder: ["l-3"], zeilen: [],
                                        skalen: [:], halbjahreswechsel: "", geaendert: Self.stempel, archiviert: ""))
        let nurAnna = try Self.lesung(Self.datei([Self.zeile("Anna", "Abel")]))
        let (neu, bilanz) = b.mitImport(nurAnna, ziel: .gruppe("g-1"), jetzt: Self.jetzt)
        #expect(bilanz.fehlende == ["l-2"], "Ben steht in keiner anderen Gruppe")
        #expect(bilanz.fehlendeAnderswo == [Fehlmitgliedschaft(person: "l-3", gruppe: "g-1")], "Cem steht in der Lese-AG")
        let archiviert = neu.mitArchiviertenPersonen(bilanz.fehlende, jetzt: Self.jetzt)
        #expect(archiviert.lernende.filter { !$0.archiviert.isEmpty }.map(\.id) == ["l-2"])
        #expect(archiviert.lerngruppen[0].mitglieder == ["l-1", "l-2", "l-3"], "Mitgliedschaft bleibt beim Archivieren")
        let genommen = archiviert.ohneMitgliedschaften(bilanz.fehlendeAnderswo, jetzt: Self.jetzt)
        #expect(genommen.lerngruppen[0].mitglieder == ["l-1", "l-2"] && genommen.lerngruppen[0].geaendert == Self.jetzt)
        #expect(genommen.lerngruppen[1].mitglieder == ["l-3"], "in der Lese-AG bleibt Cem")
        #expect(genommen.lernende.first { $0.id == "l-3" }?.archiviert.isEmpty == true, "Cem bleibt in den Listen")
        // Eine archivierte andere Gruppe zählt nicht — dann wird archiviert.
        var c = b
        c.lerngruppen[1].archiviert = Self.stempel
        let ohneAG = c.mitImport(nurAnna, ziel: .gruppe("g-1"), jetzt: Self.jetzt).bilanz
        #expect(ohneAG.fehlende == ["l-2", "l-3"] && ohneAG.fehlendeAnderswo.isEmpty)
    }

    @Test("Fehlende getrennt je Klasse (E368, Z-AT1-02): wer in beiden Zielgruppen fehlt, einmal zum Archivieren; wer in der anderen Zielgruppe zugeordnet wird, nur aus der ersten genommen")
    func fehlendeJeKlasse() throws {
        let s = Self.stempel
        func klasse(_ id: String, _ name: String, _ mitglieder: [String]) -> Lerngruppe {
            Lerngruppe(id: id, name: name, art: .klasse, mitglieder: mitglieder, zeilen: [], skalen: [:],
                       halbjahreswechsel: "", geaendert: s, archiviert: "")
        }
        var b = Self.bestand()
        // Ben (l-2) steht in 6a und 7b, Cem (l-3) in 6a, Dora (l-4) in 7b.
        b.lerngruppen = [klasse("k-6", "6a", ["l-1", "l-2", "l-3"]), klasse("k-7", "7b", ["l-2", "l-4"])]
        // Die Datei: Anna in 6a; Cem jetzt in 7b; Dora in 7b; Ben nirgends.
        let daten = Self.datei([Self.zeile("Anna", "Abel", klasse: "6a"), Self.zeile("Cem", "Çelik", klasse: "7b"),
                                Self.zeile("Dora", "Dietz", klasse: "7b")])
        let (neu, bilanz) = b.mitImport(try Self.lesung(daten), ziel: .jeKlasse, jetzt: Self.jetzt)
        #expect(bilanz.zugeordnet.map(\.nachname) == ["Çelik"], "Cem kommt nach 7b (E288)")
        #expect(bilanz.fehlende == ["l-2"], "Ben fehlt in beiden Klassen und steht sonst nirgends — einmal")
        #expect(bilanz.fehlendeAnderswo == [Fehlmitgliedschaft(person: "l-3", gruppe: "k-6")], "Cem steht jetzt in 7b")
        #expect(neu.lerngruppen.first { $0.id == "k-7" }?.mitglieder == ["l-2", "l-4", "l-3"])
    }

    @Test("Eine archivierte Person der Zielgruppe, die die Datei wieder nennt, wird zurückgeholt und genannt (E299)")
    func archivierteZurueckholen() throws {
        let b = Self.bestand().mitArchiviertenPersonen(["l-2"], jetzt: Self.stempel)
        let daten = Self.datei([Self.zeile("Anna", "Abel"), Self.zeile("Ben", "Bauer")])
        let (neu, bilanz) = b.mitImport(try Self.lesung(daten), ziel: .gruppe("g-1"), jetzt: Self.jetzt)
        #expect(bilanz.zurueckgeholt.map(\.nachname) == ["Bauer"] && bilanz.unveraendert.map(\.nachname) == ["Abel"])
        #expect(bilanz.kurz == "0 neu · 1 zurückgeholt · 1 unverändert · 0 übergangen")
        let ben = try #require(neu.lernende.first { $0.id == "l-2" })
        #expect(ben.archiviert.isEmpty && ben.geaendert == Self.jetzt, "wieder in den Listen, gestempelt")
        #expect(neu.lernende.count == 4 && !bilanz.fehlende.contains("l-2"), "dieselbe Person, nicht fehlend")
    }

    @Test("Eine aktive und eine archivierte Person gleichen Namens: Die aktive gilt, wie bei der Eingabe von Hand (Z14c-03)")
    func aktiveVorArchivierter() throws {
        var b = Self.bestand().mitArchiviertenPersonen(["l-2"], jetzt: Self.stempel)
        b.lernende.append(Lernender(id: "l-5", vorname: "Ben", nachname: "Bauer", angelegt: Self.stempel,
                                    geaendert: Self.stempel, archiviert: ""))
        b.lerngruppen[0].mitglieder.append("l-5")
        let daten = Self.datei([Self.zeile("Ben", "Bauer")])
        let (neu, bilanz) = b.mitImport(try Self.lesung(daten), ziel: .gruppe("g-1"), jetzt: Self.jetzt)
        #expect(bilanz.unveraendert.map(\.nachname) == ["Bauer"] && bilanz.uebergangen.isEmpty && bilanz.zurueckgeholt.isEmpty,
                Comment(rawValue: bilanz.kurz))
        #expect(neu.lernende.first { $0.id == "l-2" }?.archiviert.isEmpty == false, "die archivierte bleibt archiviert")
    }

    @Test("Spaltennamen nur aus einer erkannten Kopfzeile (W3-02) — sonst stünde eine Datenzeile in der Wahl")
    func spaltennamen() {
        let kopf = Self.kopf.split(separator: ";").map { $0.replacingOccurrences(of: "\"", with: "") }
        let daten = Self.zeile("Max", "Muster").split(separator: ";").map(String.init)
        #expect(ImportBogen.spaltenname(1, tabelle: [kopf, daten], kopfzeile: true) == "Spalte 2 „Vorname“")
        #expect(ImportBogen.spaltenname(7, tabelle: [daten, daten], kopfzeile: true) == "Spalte 8", "eine Datenzeile ist kein Kopf")
        #expect(ImportBogen.spaltenname(7, tabelle: [kopf, daten], kopfzeile: false) == "Spalte 8")
    }
}
