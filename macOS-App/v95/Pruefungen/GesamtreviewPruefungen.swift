// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Befunde des Gesamtreviews von v91 (BC7) am Quelltext ──
// Je Befund eine Prüfung, die bei einem Rückfall rot wird — Leerraum zusammengezogen, damit sie nicht an der Einrückung
// hängt. Den Weg über das Blatt (E999, ein getippter Tag beim Wechsel im Auswahlfeld) prüft die Lernendenprobe.

@Suite("Gesamtreview v91: Gruppenwechsel, Auswahlfeld, Frist, Adressaten, Rückmeldungsliste (BC7)")
struct GesamtreviewPruefungen {

    private static func quelle(_ pfad: String) throws -> String {
        let datei = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/" + pfad)
        return try String(contentsOf: datei, encoding: .utf8).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Das Stück von `anfang` bis `ende` (beide ausschließlich); ohne `ende` bis zum Schluss.
    private static func stueck(_ text: String, _ anfang: String, _ ende: String? = nil) throws -> String {
        let a = try #require(text.range(of: anfang))
        guard let ende else { return String(text[a.upperBound...]) }
        let e = try #require(text.range(of: ende, range: a.upperBound..<text.endIndex))
        return String(text[a.upperBound..<e.lowerBound])
    }

    private static func anliegenAnsicht() throws -> String { try quelle("Oberflaeche/Dialoge/AnliegenAnsicht.swift") }

    @Test("W1-01: Maßnahmen und Vereinbarungen — beim Wechsel der Lerngruppe „für“ auf ihr erstes Mitglied; angelegt wird nur für ein Mitglied")
    func gruppenwechselFuer() throws {
        let text = try Self.anliegenAnsicht()
        let massnahmen = try Self.stueck(text, "struct Massnahmenliste: View {", "struct Vereinbarungsliste: View {")
        let vereinbarungen = try Self.stueck(text, "struct Vereinbarungsliste: View {")
        for (name, liste) in [("Maßnahmen", massnahmen), ("Vereinbarungen", vereinbarungen)] {
            #expect(liste.contains(".onChange(of: gruppe.id) { _, _ in"), "\(name): reagiert auf den Wechsel der Lerngruppe")
            #expect(liste.contains("fuer = mitglieder.first?.id zeile = nil felderLaden() }"),
                    "\(name): „für“ auf das erste Mitglied der neuen Lerngruppe, keine Zeile gewählt")
            #expect(liste.contains("|| Anliegenbezug.fuerGueltig(fuer, mitglieder) == nil"), "\(name): „Anlegen“ gesperrt")
            #expect(liste.contains("guard let fuer = Anliegenbezug.fuerGueltig(fuer, mitglieder),"),
                    "\(name): angelegt wird nur für ein Mitglied")
            // Erst das Getippte in die Zeile der vorigen Lerngruppe; geschrieben wird nur in die geladene Zeile (N7-05, BC7b).
            #expect(liste.contains(".onChange(of: gruppe.id) { _, _ in uebernehmen(zeile, ueberAlle: true)"),
                    "\(name): vor dem Wechsel übernommen")
            #expect(liste.contains("guard let id, id == geladenFuer,") && liste.contains("geladenFuer = z?.id"),
                    "\(name): nur in die Zeile, für die die Felder geladen sind")
        }
    }

    @Test("W1-02: Die Datumsfelder der Mitteilung gehören ihr — ein getippter Tag wandert beim Wechsel im Auswahlfeld nicht weiter")
    func datumsfelderJeMitteilung() throws {
        let leiste = try Self.stueck(try Self.anliegenAnsicht(), "private func mitteilungsleiste(", "Menu(Mitteilungstext.auchAn)")
        #expect(leiste.components(separatedBy: ".id(m.id)").count == 3, "Tag und „Rückmeldung bis“ je mit `.id(m.id)`")
        let person = try Self.stueck(try Self.anliegenAnsicht(), "private func ruecklaufleiste(", "Spacer(minLength: 0)")
        #expect(person.contains(".id(\"\\(m.id)/\\(p.id)\")"), "der Tag des Rücklaufs je Mitteilung und Person (N7-02)")
    }

    @Test("W1-04: Die Frist einer Mitteilung ist ein eigener Schritt — sie wächst nicht mit Tag und Titel zusammen")
    func fristEigenerSchritt() throws {
        #expect(try Self.anliegenAnsicht().contains("mitteilungSetzen(m.id, frist: $0.iso, kennung: \"\\(m.id)/frist\")"))
    }

    @Test("W1-05: Gesperrt zeigt „Rückmeldung bis“ das Datum, das der Haken setzen würde")
    func fristGesperrtWieHaken() throws {
        #expect(try Self.anliegenAnsicht().contains("Tag(iso: m.frist) ?? .heute.plus(tage: Mitteilungstext.fristTage)"))
    }

    @Test("W1-07: Kehrt eine Mitteilung der Lerngruppe zurück (⌘Z, ⇧⌘Z), ist sie gewählt")
    func zurueckgekehrteGewaehlt() throws {
        let text = try Self.anliegenAnsicht()
        #expect(text.contains(".onChange(of: bezug.entwurf) { alt, neu in"))
        #expect(text.contains("if let zurueck = Self.neuErschienen(alt: alt, neu: neu, gruppe: gruppe.id) { aktiv = zurueck }"))
    }

    @Test("W1-10, N7-01: „Anlegen“ nennt „Die Lerngruppe hat kein aktives Mitglied“ nur, wenn es deswegen gesperrt ist")
    func sperrgrundOhneMitglieder() throws {
        #expect(try Self.anliegenAnsicht().contains(".hilfe(Mitteilungstext.anlegenHilfe(ohneAdressaten: ohneAdressaten, "
                                                     + "keinAktives: gruppenmitglieder.isEmpty),"))
        #expect(Mitteilungstext.anlegenHilfe(ohneAdressaten: false, keinAktives: true) == Knopfhilfe.mitteilungAnlegen,
                "„an alle“ in einer leeren Lerngruppe: anlegbar, die gewohnte Hilfe")
        #expect(Mitteilungstext.anlegenHilfe(ohneAdressaten: true, keinAktives: true) == Mitteilungstext.ohneMitglieder)
        #expect(Mitteilungstext.anlegenHilfe(ohneAdressaten: true, keinAktives: false) == Mitteilungstext.ohneAdressaten)
        #expect(Mitteilungstext.anlegenHilfe(ohneAdressaten: false, keinAktives: false) == Knopfhilfe.mitteilungAnlegen)
    }

    @Test("W2-01: „Einzelne …“ liest die Lerngruppe nach dem Ausstehenden neu — ein eben getippter Name steht im Bogen")
    func bogenFrischeGruppe() throws {
        let blatt = try Self.quelle("Oberflaeche/Dialoge/LernendenDialog.swift")
        #expect(blatt.contains("ausstehendeUebernehmen() guard let g = verzeichnis.gruppe(g.id) else { return } adressatenbogen ="))
    }

    @Test("W2-02: Die Auswahl aus dem Bogen gilt nur in der Lerngruppe, für die er offen war")
    func bogenNurEigeneGruppe() throws {
        let blatt = try Self.quelle("Oberflaeche/Dialoge/LernendenDialog.swift")
        #expect(blatt.contains("AdressatenBogen(vorlage: vorlage) { auswahl in if gruppe == vorlage.gruppe.id { "
                               + "adressaten = .einzelne(auswahl) } }"))
    }

    @Test("W2-03: Die Knöpfe des Bogens „Einzelne …“ tragen ihre Hilfe; „Übernehmen“ nennt gesperrt seinen Grund")
    func bogenHilfen() throws {
        let bogen = try Self.quelle("Oberflaeche/Dialoge/AdressatenBogen.swift")
        #expect(bogen.contains(".hilfe(Mitteilungstext.bogenAlleHilfe, gesperrt: alle)"))
        #expect(bogen.contains(".hilfe(Mitteilungstext.bogenKeineHilfe, gesperrt: keine)"))
        #expect(bogen.contains(".hilfe(leer ? Mitteilungstext.bogenUebernehmenGesperrt : Mitteilungstext.bogenUebernehmenHilfe, "
                               + "gesperrt: leer)"))
    }

    @Test("W2-07: Der Bogen rechnet Anfang, Zähler, Sperre und Ergebnis über `Adressatenwahl`; die Vorlage nimmt nur aktive")
    func bogenWahlRein() throws {
        let bogen = try Self.quelle("Oberflaeche/Dialoge/AdressatenBogen.swift")
        for aufruf in ["Adressatenwahl.zaehler(gewaehlt, kennungen)", "Adressatenwahl.leer(gewaehlt, kennungen)",
                       "Adressatenwahl.ergebnis(gewaehlt, kennungen)", "Adressatenwahl.anfang(vorlage.vorgewaehlt, kennungen)"] {
            #expect(bogen.contains(aufruf), Comment(rawValue: aufruf))
        }
        let blatt = try Self.quelle("Oberflaeche/Dialoge/LernendenDialog.swift")
        #expect(blatt.contains("Adressatenvorlage(gruppe: g, mitglieder: verzeichnis.mitglieder(g.id), vorgewaehlt:"),
                "die Vorlage ohne Archivierte")
    }

    @Test("W2-05: Mit Frist trägt der Spaltenkopf der Rückmeldungsliste höchstens zwei Titelzeilen — über eine reine Funktion")
    func fristzeilenImKopf() throws {
        let satz = try Self.quelle("Dienste/Listensatz.swift")
        #expect(satz.contains("hoechstens: Listensatz.titelzeilen(frist: spalte.frist)"))
    }

    @Test("W1-01: `fuerGueltig` — nur ein Mitglied der gezeigten Lerngruppe")
    func fuerGueltigRein() {
        let s = "2026-08-20T08:00:00.000Z"
        let anna = Lernender(id: "l-anna", vorname: "Anna", nachname: "Adam", angelegt: s, geaendert: s, archiviert: "")
        #expect(Anliegenbezug.fuerGueltig("l-anna", [anna]) == "l-anna")
        #expect(Anliegenbezug.fuerGueltig("l-ben", [anna]) == nil, "eine Person der vorigen Lerngruppe")
        #expect(Anliegenbezug.fuerGueltig(nil, [anna]) == nil)
    }

    @Test("W1-07: `neuErschienen` — genau eine neue Mitteilung der Lerngruppe; keine, mehrere oder fremde nicht")
    func neuErschienenRein() {
        let s = "2026-08-20T08:00:00.000Z"
        func mitteilung(_ id: String, _ gruppe: String, _ art: Anliegenart = .mitteilung) -> Anliegen {
            Anliegen(id: id, art: art, titel: id, lerngruppe: gruppe, betroffene: [], datum: "", frist: "", notiz: "",
                     angelegt: s, geaendert: s)
        }
        var alt = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        alt.anliegen = [mitteilung("m-1", "g-a")]
        var neu = alt
        neu.anliegen.append(mitteilung("m-2", "g-a"))
        #expect(Ruecklaufliste.neuErschienen(alt: alt, neu: neu, gruppe: "g-a") == "m-2", "⌘Z nach dem Löschen")
        #expect(Ruecklaufliste.neuErschienen(alt: neu, neu: alt, gruppe: "g-a") == nil, "fort, nicht dazu")
        #expect(Ruecklaufliste.neuErschienen(alt: alt, neu: neu, gruppe: "g-b") == nil, "eine andere Lerngruppe")
        var zwei = neu
        zwei.anliegen.append(mitteilung("m-3", "g-a"))
        #expect(Ruecklaufliste.neuErschienen(alt: alt, neu: zwei, gruppe: "g-a") == nil, "mehrere")
        // Beim Zusammenführen geht eine Mitteilung der anderen Lerngruppe über — sie ist nicht neu (N7-04).
        var anderswo = alt
        anderswo.anliegen.append(mitteilung("m-5", "g-b"))
        var zusammen = anderswo
        zusammen.anliegen = zusammen.anliegen.map { a in
            a.id == "m-5" ? Anliegen(id: a.id, art: a.art, titel: a.titel, lerngruppe: "g-a", betroffene: [], datum: "",
                                     frist: "", notiz: "", angelegt: s, geaendert: s) : a
        }
        #expect(Ruecklaufliste.neuErschienen(alt: anderswo, neu: zusammen, gruppe: "g-a") == nil, "übergegangen, nicht neu")
        var massnahme = alt
        massnahme.anliegen.append(mitteilung("m-4", "g-a", .massnahme))
        #expect(Ruecklaufliste.neuErschienen(alt: alt, neu: massnahme, gruppe: "g-a") == nil, "eine Maßnahme ist keine")
    }

    @Test("W2-05: Mit Frist trägt der Titel im Spaltenkopf höchstens zwei Zeilen, ohne drei")
    func titelzeilenRein() {
        #expect(Listensatz.titelzeilen(frist: "") == 3)
        #expect(Listensatz.titelzeilen(frist: "bis 14.09.2026") == 2)
    }

    @Test("W2-07: `Adressatenwahl` — Anfang, Zähler, Sperre und Ergebnis nur über aktive Mitglieder")
    func adressatenwahlRein() {
        let aktive = ["l-anna", "l-ben", "l-clara"]
        #expect(Adressatenwahl.anfang(["l-ben", "l-david"], aktive) == ["l-ben"], "die archivierte David fällt heraus")
        #expect(Adressatenwahl.anfang([], aktive).isEmpty, "beim ersten Öffnen nichts gewählt")
        #expect(Adressatenwahl.zaehler(["l-ben", "l-david"], aktive) == 1, "„1 von 3 gewählt“")
        #expect(Adressatenwahl.leer(["l-david"], aktive), "nur eine Archivierte: „Übernehmen“ gesperrt")
        #expect(!Adressatenwahl.leer(["l-anna"], aktive))
        #expect(Adressatenwahl.ergebnis(["l-anna", "l-david"], aktive) == ["l-anna"])
    }

    @Test("E1008 (W1-08): „Stand“ ordnet in der Tabelle einer Mitteilung wie bei den Maßnahmen — über den Rang des Stands")
    func standOrdnet() throws {
        let text = try Self.anliegenAnsicht()
        #expect(text.contains("@Binding var ordnung: [KeyPathComparator<Ruecklaufzeile>]"), "die Zeilen tragen den Stand")
        #expect(text.contains("Huellspalte(Mitteilungstext.spalteStand, ordnen: KeyPathComparator(\\.stand), "
                              + "breite: .fest(130),"), "der Kopf „Stand“ ordnet")
        #expect(text.contains("let zeilen = Tabellenordnung.geordnet(Self.reihen(m, Self.zeilen(m, personen), "
                              + "bezug.verzeichnis), nach: ordnung)"), "geordnet werden die Zeilen samt Stand")
    }

    @Test("E1008: `reihen` — je Person der Rang ihres Stands; nach ihm geordnet stehen gleiche Stände beisammen")
    func reihenRein() throws {
        let s = "2026-08-20T08:00:00.000Z"
        func person(_ id: String, _ name: String) -> Lernender {
            Lernender(id: id, vorname: name, nachname: name, angelegt: s, geaendert: s, archiviert: "")
        }
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [person("l-a", "Adam"), person("l-b", "Brandt"), person("l-c", "Conrad"), person("l-d", "Dorn")]
        b.lerngruppen = [Lerngruppe(id: "g-1", name: "5a", art: .klasse, mitglieder: ["l-a", "l-b", "l-c", "l-d"], zeilen: [],
                                    skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        b.anliegen = [Anliegen(id: "m-1", art: .mitteilung, titel: "Brief", lerngruppe: "g-1",
                               betroffene: ["l-a", "l-b", "l-c", "l-d"], datum: "2026-09-01", frist: "", notiz: "",
                               angelegt: s, geaendert: s)]
        b.rueckmeldungen = [Rueckmeldung(anliegen: "m-1", lernender: "l-a", stand: .abgelehnt, datum: "2026-09-02", notiz: "",
                                         geaendert: s),
                            Rueckmeldung(anliegen: "m-1", lernender: "l-c", stand: .erledigt, datum: "2026-09-02", notiz: "",
                                         geaendert: s)]
        let v = Lernendenverzeichnis(b)
        let m = try #require(b.anliegen.first)
        let reihen = Ruecklaufliste.reihen(m, v.mitglieder("g-1"), v)
        #expect(reihen.map(\.id) == ["l-a", "l-b", "l-c", "l-d"], "die Folge der Personen bleibt, `id` ist die der Person")
        #expect(reihen.map(\.stand) == [Rueckmeldestand.abgelehnt.rang, Rueckmeldestand.offen.rang, Rueckmeldestand.erledigt.rang,
                                       Rueckmeldestand.offen.rang])
        let nachStand = Tabellenordnung.geordnet(reihen, nach: [KeyPathComparator(\Ruecklaufzeile.stand)])
        #expect(nachStand.map(\.stand) == nachStand.map(\.stand).sorted(), "der Kopf „Stand“ ordnet nach dem Rang")
        // Brandt und Dorn sind beide offen und stehen beisammen, bei Gleichstand nach der Kennung.
        let offen = nachStand.indices.filter { nachStand[$0].stand == Rueckmeldestand.offen.rang }
        #expect(offen.count == 2 && offen[1] == offen[0] + 1 && nachStand[offen[0]].id == "l-b")
    }

    @Test("W2-06: Frist und Regel sind verdrahtet — Spalte „Tag“ im Archiv, „Offen: …“, „verstrichen“ bei den Maßnahmen")
    func verdrahtungFrist() throws {
        #expect(try Self.quelle("Oberflaeche/Dialoge/ArchivAnsicht.swift").contains("ideal: Self.tagspalteIdeal(lernende)"))
        #expect(try Self.quelle("Oberflaeche/Dialoge/LernendenDialog.swift").contains("offen.map(Anliegenbezug.offenerEintrag)"))
        let massnahmen = try Self.stueck(try Self.anliegenAnsicht(), "struct Massnahmenliste: View {",
                                         "struct Vereinbarungsliste: View {")
        #expect(massnahmen.contains("Anliegenbezug.verstrichen("), "Maßnahmen nach derselben Regel wie die Mitteilungen")
    }
}
