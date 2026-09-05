// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Kalender ──────────────────────────────────────────────────────────────

@Suite("Kalenderwochen nach ISO 8601")
struct KalenderPruefungen {

    @Test("Der Montag einer Woche wird richtig bestimmt")
    func montag() throws {
        // 12.08.2026 ist ein Mittwoch.
        let mittwoch = try #require(Tag(iso: "2026-08-12"))
        #expect(mittwoch.montagDerWoche.iso == "2026-08-10")
        let sonntag = try #require(Tag(iso: "2026-08-16"))
        #expect(sonntag.montagDerWoche.iso == "2026-08-10")
        let montag = try #require(Tag(iso: "2026-08-10"))
        #expect(montag.montagDerWoche.iso == "2026-08-10")
    }

    @Test("Kalenderwoche und Wochenjahr")
    func kalenderwoche() throws {
        #expect(try #require(Tag(iso: "2026-08-10")).kalenderwoche == (33, 2026))
        #expect(try #require(Tag(iso: "2026-01-01")).kalenderwoche == (1, 2026))
        // 2026 hat 53 Wochen — der 01.01.2027 gehört noch dazu.
        #expect(try #require(Tag(iso: "2027-01-01")).kalenderwoche == (53, 2026))
        #expect(try #require(Tag(iso: "2024-12-31")).kalenderwoche == (1, 2025))
    }

    @Test("Nur die strenge Form JJJJ-MM-TT wird angenommen")
    func strengeForm() {
        #expect(Tag(iso: "2026-8-10") == nil)
        #expect(Tag(iso: "26-08-10") == nil)
        #expect(Tag(iso: "2026/08/10") == nil)
        #expect(Tag(iso: "") == nil)
        #expect(Tag(iso: "2026-08-10x") == nil)
        #expect(Tag(iso: "2026-08-10") != nil)
    }

    @Test("Die Wochenliste beginnt beim Montag und zählt in Siebenerschritten")
    func wochenliste() throws {
        let liste = Tag.wochenListe(start: try #require(Tag(iso: "2026-08-12")), anzahl: 4)
        #expect(liste.count == 4)
        #expect(liste[0].montag.iso == "2026-08-10")
        #expect(liste[0].freitag.iso == "2026-08-14")
        #expect(liste[3].montag.iso == "2026-08-31")
        #expect(liste.map(\.kw) == [33, 34, 35, 36])
        #expect(liste[0].spanne == "10.08.–14.08.")
    }

    @Test("Die Ordnung der Tage entspricht der ihrer ISO-Schreibweise")
    func ordnung() throws {
        let a = try #require(Tag(iso: "2026-08-09"))
        let b = try #require(Tag(iso: "2026-08-10"))
        #expect(a < b)
        #expect(a.iso < b.iso)
        #expect(min(b, a) == a)
    }

    /// Foundation zählt ab Sonntag, ISO 8601 ab Montag — der Wochentag eines
    /// Vorhabens rechnet in ISO, wie die Ansichtsfassung (`wochentagISO`).
    @Test("Montag bis Freitag tragen einen Wochentag, das Wochenende keinen")
    func wochentage() throws {
        let montag = try #require(Tag(iso: "2026-08-10"))
        #expect(montag.wochentag == .montag)
        #expect(montag.plus(tage: 2).wochentag == .mittwoch)
        #expect(montag.plus(tage: 4).wochentag == .freitag)
        #expect(montag.plus(tage: 5).wochentag == nil)
        #expect(montag.plus(tage: 6).wochentag == nil)
        #expect(Wochentag.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
        #expect(Wochentag.allCases.map(\.kurz) == ["Mo.", "Di.", "Mi.", "Do.", "Fr."])
        #expect(Wochentag.freitag.lang == "Freitag")
        // Aus dem Wochentag wird das Datum der Woche — der Weg des Dialogs.
        let woche = Woche(nummer: 0, montag: montag)
        #expect(woche.tag(.mittwoch) == Tag(iso: "2026-08-12"))
        #expect(woche.tag(.mittwoch).wochentag == .mittwoch)
        // Anzeige und Dateiform einer Menge: in Wochenreihenfolge, egal wie befüllt.
        let tage: Set<Wochentag> = [.freitag, .montag, .mittwoch]
        #expect(tage.beschriftung == "Mo., Mi., Fr.")
        #expect(tage.gespeichert == [1, 3, 5])
        #expect(Set<Wochentag>().beschriftung == "")
    }
}

// ── Farben ────────────────────────────────────────────────────────────────

@Suite("Farblogik")
struct FarbPruefungen {

    @Test("Die Palette hat 24 Farben: acht Grundfarben in je drei Stufen")
    func palette() {
        #expect(Farbwelt.grundfarben.count == 8)
        #expect(Farbwelt.stufen.count == 3)
        #expect(Farbwelt.toene.count == 24)
        #expect(Set(Farbwelt.toene.map(\.schluessel)).count == 24)
        for (stelle, ton) in Farbwelt.toene.enumerated() {
            #expect(ton.stelle == stelle)
        }
        for grund in Farbwelt.grundfarben {
            let seine = Farbwelt.toene.filter { $0.grundfarbe == grund.schluessel }
            #expect(seine.count == 3)
            #expect(Set(seine.map(\.stufe)) == Set(Farbwelt.stufen.map(\.schluessel)))
            #expect(Set(seine.map(\.h)).count == 1)
        }
    }

    @Test("Die acht Farbtöne liegen äquidistant über dem Farbkreis")
    func aequidistant() {
        let toene = Farbwelt.grundfarben.map(\.h).sorted()
        #expect(toene.count == 8)
        // Reihum, über den Nullpunkt hinweg: acht gleiche Schritte von 45°.
        var abstaende: [Double] = []
        for (stelle, wert) in toene.enumerated() {
            let naechster = toene[(stelle + 1) % toene.count]
            abstaende.append((naechster - wert + 360).truncatingRemainder(dividingBy: 360))
        }
        #expect(abstaende.allSatisfy { abs($0 - 45) < 0.001 },
                Comment(rawValue: "Abstände: \(abstaende)"))
    }

    @Test("Die drei Stufen unterscheiden sich nur in der Helligkeit")
    func stufen() {
        for grund in Farbwelt.grundfarben {
            let seine = Farbwelt.toene.filter { $0.grundfarbe == grund.schluessel }
            #expect(Set(seine.map(\.ds)).count == 1, "eine Sättigung je Grundfarbe")
            #expect(Set(seine.map(\.dl)).count == 3, "drei Helligkeiten je Grundfarbe")
        }
        let hell = Farbwelt.tonNachSchluessel["blau-hell"]?.dl
        let mittel = Farbwelt.tonNachSchluessel["blau-mittel"]?.dl
        let dunkel = Farbwelt.tonNachSchluessel["blau-dunkel"]?.dl
        #expect(hell != nil && mittel != nil && dunkel != nil)
        #expect((hell ?? 0) > (mittel ?? 0))
        #expect((mittel ?? 0) > (dunkel ?? 0))
    }

    /// Die Grundwerte tendieren ins Pastellige: weniger Sättigung, mehr
    /// Helligkeit als die kräftige ältere Palette (55 / 45 bzw. 52 / 62).
    @Test("Die Grundwerte liegen im pastelligen Bereich")
    func pastell() {
        #expect(Farbwelt.saettigungHell < 55)
        #expect(Farbwelt.helligkeitHell > 45)
        #expect(Farbwelt.saettigungDunkel < 52)
        #expect(Farbwelt.helligkeitDunkel > 62)
    }

    @Test("Kein Fach ist fest belegt — die Festlegung entscheidet")
    func keineFesteZuweisung() {
        let leer = Planung.leer(titel: "P", start: .heute, wochen: 4, basis: "",
                                klassen: [], fachfarben: [:])
        #expect(leer.fachfarbe("Biologie") == nil)
        #expect(leer.fachfarbe("Informatik") == nil)
        #expect(leer.fachfarbe("") == nil)

        let gesetzt = Planung.leer(
            titel: "P", start: .heute, wochen: 4, basis: "", klassen: [],
            fachfarben: ["biologie": "magenta-hell", "mathematik": "rot-dunkel"])
        #expect(gesetzt.fachfarbe("Biologie") == Farbwelt.stelle("magenta-hell"))
        #expect(gesetzt.fachfarbe(" Mathematik ") == Farbwelt.stelle("rot-dunkel"))

        // Unsinn und alte Familienschlüssel zählen nicht als Festlegung.
        let unsinn = Planung.leer(titel: "P", start: .heute, wochen: 4, basis: "", klassen: [],
                                  fachfarben: ["mathematik": "quatsch", "physik": "rot"])
        #expect(unsinn.fachfarbe("Mathematik") == nil)
        #expect(unsinn.fachfarbe("Physik") == nil)
    }

    @Test("Die Fachfarbe kommt von der ersten Zeile, die sie nicht von Hand trägt")
    func fachfarbeHergeleitet() throws {
        var planung = Planung.leer(
            titel: "P", start: .heute, wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("7a", "Mathematik"), ("8b", "Mathematik")]),
            fachfarben: [:])
        let geerbt = planung.klassen[0].farbe
        #expect(planung.fachfarbe("Mathematik") == geerbt)
        #expect(planung.klassen[1].farbe == geerbt)
        // Hergeleitetes wird nicht geschrieben — sonst bliebe es hängen.
        #expect(planung.fachfarben.isEmpty)

        planung.klassen[0].farbe = try #require(Farbwelt.stelle("limette-hell"))
        planung.klassen[0].farbeManuell = true
        #expect(planung.fachfarbe("Mathematik") == geerbt)

        planung.fachfarben["mathematik"] = "violett-dunkel"
        #expect(planung.fachfarbe("Mathematik") == Farbwelt.stelle("violett-dunkel"))
    }

    @Test("Die Farbwahl zeigt jede Stufe genau einmal, von hell nach dunkel")
    func anzeigezeilen() {
        #expect(Farbwelt.anzeigezeilen.count == Farbwelt.stufen.count)
        #expect(Farbwelt.anzeigezeilen.map(\.stufe.schluessel) == ["hell", "mittel", "dunkel"])
        #expect(Farbwelt.anzeigezeilen.allSatisfy {
            $0.toene.count == Farbwelt.grundfarben.count
        })
        #expect(Set(Farbwelt.anzeigezeilen.flatMap { $0.toene.map(\.stelle) })
                == Set(Farbwelt.toene.map(\.stelle)))
    }

    @Test("Die nächste freie Farbe geht erst durch alle acht Grundfarben")
    func freieFarben() {
        var nutzung: [Int: Int] = [:]
        var reihe: [Int] = []
        for _ in 0..<10 {
            let farbe = Farbwelt.naechsteFreieFarbe(nutzung)
            nutzung[farbe, default: 0] += 1
            reihe.append(farbe)
        }
        #expect(reihe == Array(0..<10))
        let ersteAcht = reihe.prefix(8).map { Farbwelt.ton($0) }
        #expect(Set(ersteAcht.map(\.grundfarbe)).count == 8)
        #expect(ersteAcht.allSatisfy { $0.stufe == "mittel" })
    }

    @Test("Ist die Palette voll, geht die Vergabe von vorn durch alle 24")
    func volleParette() {
        var nutzung = Dictionary(uniqueKeysWithValues: Farbwelt.toene.map { ($0.stelle, 1) })
        var reihe: [Int] = []
        for _ in Farbwelt.toene.indices {
            let farbe = Farbwelt.naechsteFreieFarbe(nutzung)
            nutzung[farbe, default: 0] += 1
            reihe.append(farbe)
        }
        // Nicht 24-mal dieselbe: die am seltensten benutzte, also reihum.
        #expect(reihe == Array(Farbwelt.toene.indices))
    }

    @Test("Mehr Zeilen als Farben verteilen sich weiter über die Palette")
    func mehrZeilenAlsFarben() {
        let roh = (0..<30).map { (name: "Z\($0)", fach: "Fach \($0)") }
        let planung = Planung.leer(titel: "P", start: .heute, wochen: 4, basis: "",
                                   klassen: Standardkurse.aufbauen(roh), fachfarben: [:])
        let farben = planung.klassen.map(\.farbe)
        #expect(Set(farben).count == Farbwelt.toene.count)
        #expect(Set(farben.suffix(6)).count == 6)
    }

    @Test("Eine Planung vergibt jedem Fach eine eigene Farbe")
    func farbenVervollstaendigen() {
        var planung = Planung.leer(
            titel: "P", start: .heute, wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        #expect(planung.klassen.count == 13)
        #expect(planung.klassen.allSatisfy { Farbwelt.istGueltig($0.farbe) })

        let informatik = planung.klassen.filter { $0.fach == "Informatik" }
        #expect(informatik.count == 5)
        #expect(Set(informatik.map(\.farbe)).count == 1)
        var jeFach: [String: Set<Int>] = [:]
        for klasse in planung.klassen {
            jeFach[Farbwelt.fachSchluessel(klasse.fach), default: []].insert(klasse.farbe)
        }
        #expect(jeFach.values.allSatisfy { $0.count == 1 })
        #expect(Set(jeFach.values.flatMap { $0 }).count == jeFach.count)
        #expect(Set(planung.fachfarbenWirksam().keys) == Set(jeFach.keys.filter { !$0.isEmpty }))
        #expect(planung.fachfarben.isEmpty)

        let vorher = planung.klassen.map(\.farbe)
        planung.farbenVervollstaendigen()
        #expect(planung.klassen.map(\.farbe) == vorher)
    }

    @Test("Eine Zeile ohne Fach bekommt eine eigene Farbe")
    func ohneFach() {
        let planung = Planung.leer(
            titel: "P", start: .heute, wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("Chorprobe", ""), ("Aufsicht", ""),
                                             ("7a", "Mathematik")]),
            fachfarben: [:])
        #expect(planung.klassen.allSatisfy { Farbwelt.istGueltig($0.farbe) })
        #expect(Set(planung.klassen.map(\.farbe)).count == 3)
        #expect(planung.fachfarbe("Mathematik") == planung.klassen[2].farbe)
        #expect(planung.fachfarben.isEmpty)
    }

    @Test("Die Farbnutzung zählt Fachfarben und Zeilen zusammen")
    func farbnutzung() throws {
        let planung = Planung.leer(
            titel: "P", start: .heute, wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("7a", "Mathematik")]),
            fachfarben: ["kunst": "violett-dunkel"])
        let violett = try #require(Farbwelt.stelle("violett-dunkel"))
        let nutzung = planung.farbnutzung
        #expect(nutzung[violett] == 1)
        #expect(nutzung[planung.klassen[0].farbe] == 1)
        #expect(planung.klassen[0].farbe != violett)
    }

    @Test("Ein Fach gilt als bekannt, sobald eine Zeile es trägt")
    func kenntFach() {
        let planung = Planung.leer(
            titel: "P", start: .heute, wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("7a", "Mathematik")]),
            fachfarben: ["kunst": "violett-dunkel"])
        #expect(planung.kenntFach("Mathematik"), "hergeleitet, steht nicht in der Zuordnung")
        #expect(planung.kenntFach(" mathematik "))
        #expect(planung.kenntFach("Kunst"), "festgelegt, ohne Zeile")
        #expect(!planung.kenntFach("Physik"))
        #expect(!planung.kenntFach(""))
    }

    // ── Übergang von der alten Palette ────────────────────────────────────

    @Test("Alte Plätze werden in die neue Palette übersetzt")
    func altePlaetze() {
        // 0–3 Biologie, 4–6 Chemie, 7–9 Geographie, 10–16 Informatik,
        // 17–19 AG, 20–22 Rot, …, 32–34 Grau.
        #expect(Altfarben.tonSchluessel(zuPlatz: 0) == "gruen-mittel")
        #expect(Altfarben.tonSchluessel(zuPlatz: 3) == "gruen-mittel")
        #expect(Altfarben.tonSchluessel(zuPlatz: 4) == "orange-mittel")
        #expect(Altfarben.tonSchluessel(zuPlatz: 7) == "orange-dunkel")
        #expect(Altfarben.tonSchluessel(zuPlatz: 10) == "blau-mittel")
        #expect(Altfarben.tonSchluessel(zuPlatz: 16) == "blau-mittel")
        #expect(Altfarben.tonSchluessel(zuPlatz: 17) == "violett-mittel")
        #expect(Altfarben.tonSchluessel(zuPlatz: 20) == "rot-mittel")
        #expect(Altfarben.tonSchluessel(zuPlatz: 31) == "limette-mittel")
        #expect(Altfarben.tonSchluessel(zuPlatz: 32) == nil)
        #expect(Altfarben.tonSchluessel(zuPlatz: 34) == nil)
        #expect(Altfarben.tonSchluessel(zuPlatz: 35) == nil)
        #expect(Altfarben.tonSchluessel(zuPlatz: -1) == nil)
        for platz in 0..<32 {
            #expect(Altfarben.tonSchluessel(zuPlatz: platz).flatMap(Farbwelt.stelle) != nil,
                    Comment(rawValue: "Platz \(platz) hat keine Entsprechung"))
        }
        #expect(Altfarben.tonSchluessel(zuFamilie: "chemie")
                != Altfarben.tonSchluessel(zuFamilie: "geographie"))
        #expect(Altfarben.tonSchluessel(zuFamilie: "neutral") == nil)
    }
}

// ── Eingabezeilen ─────────────────────────────────────────────────────────

@Suite("Eingabezeilen einlesen")
struct KurszeilenPruefungen {

    @Test("Gültige Zeilen mit beiden Strichformen")
    func gueltig() {
        let ergebnis = Kurszeilen.pruefen("""
        G6a - Informatik
        R9b – Informatik
        AG – LEGO-Robotik

        G9 - Chemie
        """)
        #expect(ergebnis.fehler.isEmpty)
        #expect(ergebnis.kurse.count == 4)
        #expect(ergebnis.kurse[0].name == "G6a")
        #expect(ergebnis.kurse[0].fach == "Informatik")
        #expect(ergebnis.kurse[2].name == "AG")
        #expect(ergebnis.kurse[2].fach == "LEGO-Robotik")
    }

    @Test("Ohne Strich ist die ganze Zeile die Klasse bzw. der Kurs")
    func fachIstFreiwillig() {
        let ergebnis = Kurszeilen.pruefen("G6a\nChorprobe\nG6a-Informatik\n7a Sport")
        #expect(ergebnis.fehler.isEmpty)
        #expect(ergebnis.kurse.count == 4)
        #expect(ergebnis.kurse[0].name == "G6a")
        #expect(ergebnis.kurse[0].fach == "")
        #expect(ergebnis.kurse[1].name == "Chorprobe")
        // Ein Bindestrich ohne Leerzeichen gehört zur Bezeichnung.
        #expect(ergebnis.kurse[2].name == "G6a-Informatik")
        #expect(ergebnis.kurse[2].fach == "")
        #expect(ergebnis.kurse[3].name == "7a Sport")
        #expect(ergebnis.kurse[3].fach == "")
    }

    @Test("Ein angefangener Strich wird benannt")
    func fehler() {
        let vorn = Kurszeilen.pruefen("– Informatik")
        #expect(vorn.kurse.isEmpty)
        #expect(vorn.fehler.count == 1)
        #expect(vorn.fehler[0].nummer == 1)
        #expect(vorn.fehler[0].grund == "Vor dem Strich fehlt die Klasse bzw. der Kurs.")

        let hinten = Kurszeilen.pruefen("G6a -")
        #expect(hinten.kurse.isEmpty)
        #expect(hinten.fehler.count == 1)
        #expect(hinten.fehler[0].grund.hasPrefix("Nach dem Strich fehlt das Fach."))
    }

    @Test("Die Zeilennummer zählt Leerzeilen mit")
    func zeilennummer() {
        let ergebnis = Kurszeilen.pruefen("G6a - Informatik\n\n- \nG9 - Chemie")
        #expect(ergebnis.fehler.count == 1)
        #expect(ergebnis.fehler[0].nummer == 3)
        #expect(ergebnis.kurse.count == 2)
    }

    @Test("Windows-Zeilenenden zählen nicht als Fehler")
    func wagenruecklauf() {
        let ergebnis = Kurszeilen.pruefen("G6a - Informatik\r\n\r\nG9 - Chemie\r\n")
        #expect(ergebnis.fehler.isEmpty)
        #expect(ergebnis.kurse.count == 2)
        #expect(ergebnis.kurse[1].fach == "Chemie")
    }

    @Test("Das erste Strichpaar trennt, nicht das letzte")
    func ersterStrich() {
        let ergebnis = Kurszeilen.pruefen("AG – LEGO – Robotik")
        #expect(ergebnis.fehler.isEmpty)
        #expect(ergebnis.kurse[0].name == "AG")
        #expect(ergebnis.kurse[0].fach == "LEGO – Robotik")
    }
}

// ── Weblinks ──────────────────────────────────────────────────────────────

@Suite("Weblinks prüfen")
struct WeblinkPruefungen {

    @Test("Fehlender Vorsatz wird zu https ergänzt")
    func vorsatz() {
        #expect(Weblinks.pruefen("3ducation.org") == "https://3ducation.org/")
        #expect(Weblinks.pruefen("www.example.org/pfad") == "https://www.example.org/pfad")
        #expect(Weblinks.pruefen("localhost:8000") == "https://localhost:8000/")
        #expect(Weblinks.pruefen("example.org:8080/x") == "https://example.org:8080/x")
    }

    @Test("Nur http und https werden zugelassen")
    func schemata() {
        #expect(Weblinks.pruefen("http://example.org") == "http://example.org/")
        #expect(Weblinks.pruefen("https://example.org/") == "https://example.org/")
        #expect(Weblinks.pruefen("javascript:alert(1)") == nil)
        #expect(Weblinks.pruefen("file:///etc/passwd") == nil)
        #expect(Weblinks.pruefen("data:text/html,<h1>x") == nil)
        #expect(Weblinks.pruefen("mailto:jemand@example.org") == nil)
        #expect(Weblinks.pruefen("ftp://example.org") == nil)
    }

    @Test("Was nicht nach einem Rechnernamen aussieht, wird abgewiesen")
    func keinRechnername() {
        #expect(Weblinks.pruefen("einfach nur text") == nil)
        #expect(Weblinks.pruefen("kaputt") == nil)
        #expect(Weblinks.pruefen("") == nil)
        #expect(Weblinks.pruefen("   ") == nil)
    }

    @Test("Spitze Klammern und Leerraum werden abgestreift")
    func klammern() {
        #expect(Weblinks.pruefen("  <https://example.org/a>  ") == "https://example.org/a")
    }

    @Test("Vorgabe-Ports fallen weg, Schema und Rechner werden kleingeschrieben")
    func normalisierung() {
        #expect(Weblinks.pruefen("HTTPS://Example.ORG:443/Pfad") == "https://example.org/Pfad")
        #expect(Weblinks.pruefen("http://Example.org:80") == "http://example.org/")
        #expect(Weblinks.pruefen("https://example.org:8443/a") == "https://example.org:8443/a")
    }

    @Test("Sonderzeichen werden kodiert statt die Adresse zu verwerfen")
    func sonderzeichen() {
        #expect(Weblinks.pruefen("https://example.org/a b") == "https://example.org/a%20b")
        #expect(Weblinks.pruefen("example.org/Größen und Maße")
                == "https://example.org/Gr%C3%B6%C3%9Fen%20und%20Ma%C3%9Fe")
        // Kodieren macht aus etwas Unbrauchbarem nichts Gültiges.
        #expect(Weblinks.pruefen("javascript:alert(1) x") == nil)
    }

    /// Alles hier könnte die App von der Ansicht trennen: `URLComponents`
    /// nimmt an, was der URL-Leser der Browser abweist, und umgekehrt. Was nur
    /// eine Seite gelten lässt, stünde in der Datei und fehlte auf dem anderen
    /// Gerät — samt der Meldung „1 Link übergangen“ an einer Datei, an der
    /// niemand etwas geändert hat. Gegenstück: `linkPruefen` der Ansicht.
    @Test("Was der URL-Leser der Browser abweist, weist auch die App ab")
    func gleichlaufMitDerAnsicht() {
        // Über 65 535 gibt es keinen Anschluss.
        #expect(Weblinks.pruefen("https://example.org:99999/") == nil)
        #expect(Weblinks.pruefen("https://example.org:65535/") == "https://example.org:65535/")
        // Angebrochene Prozentfolge: Kodiert ergäbe sie „%25zz“ — eine andere
        // Adresse als die, die die Ansicht daraus liest.
        #expect(Weblinks.pruefen("https://example.org/x?y=%zz") == nil)
        #expect(Weblinks.pruefen("https://example.org/x%2Fy") == "https://example.org/x%2Fy")
        // Gegenschrägstrich: Der Browser macht daraus einen Schrägstrich.
        #expect(Weblinks.pruefen("http://example.org\\x") == nil)
        // Tabulator und Zeilenumbruch fallen heraus, statt kodiert zu werden.
        #expect(Weblinks.pruefen("https://example.org/x\ty") == "https://example.org/xy")
        #expect(Weblinks.pruefen("https://example.org/x\ny") == "https://example.org/xy")
        // Ein Schema ohne „//“ trägt für `URLComponents` keinen Rechnernamen;
        // der Browser ergänzt es stillschweigend. Beide weisen ab.
        #expect(Weblinks.pruefen("https:example.org") == nil)
        #expect(Weblinks.pruefen("https:///example.org") == nil)
    }

    @Test("Der Anzeigename ist der Rechner ohne www.")
    func anzeigename() {
        #expect(Weblinks.name("https://www.example.org/a") == "example.org")
        #expect(Weblinks.name("https://3ducation.org/") == "3ducation.org")
    }
}

// ── Pfade ─────────────────────────────────────────────────────────────────

@Suite("Materialpfade")
struct PfadPruefungen {
    private let basis = "/Users/lehrkraft/Unterricht"

    @Test("file://-Adressen, Anführungszeichen und Endschrägstriche")
    func normalisieren() {
        #expect(Pfade.normalisieren("file:///Users/lehrkraft/Unterricht/AB.pdf", basis: basis)
                == "/Users/lehrkraft/Unterricht/AB.pdf")
        #expect(Pfade.normalisieren("file:///Users/lehrkraft/Bio%20Klasse%205/AB.pdf", basis: basis)
                == "/Users/lehrkraft/Bio Klasse 5/AB.pdf")
        #expect(Pfade.normalisieren("\"/Users/lehrkraft/AB.pdf\"", basis: basis)
                == "/Users/lehrkraft/AB.pdf")
        #expect(Pfade.normalisieren("  /Users/lehrkraft/Ordner/  ", basis: basis)
                == "/Users/lehrkraft/Ordner")
        #expect(Pfade.normalisieren("", basis: basis) == "")
        #expect(Pfade.normalisieren("/", basis: basis) == "/")
    }

    @Test("Die Tilde wird am Basisordner aufgelöst")
    func tilde() {
        #expect(Pfade.normalisieren("~/Unterricht/AB.pdf", basis: basis)
                == "/Users/lehrkraft/Unterricht/AB.pdf")
        let heim = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Pfade.normalisieren("~/AB.pdf", basis: "") == heim + "/AB.pdf")
    }

    @Test("Innerhalb des Basisordners relativ, außerhalb absolut")
    func relativMachen() {
        #expect(Pfade.relativMachen("/Users/lehrkraft/Unterricht/Bio/AB.pdf", basis: basis)
                == "Bio/AB.pdf")
        #expect(Pfade.relativMachen("/Users/lehrkraft/Unterricht", basis: basis) == ".")
        #expect(Pfade.relativMachen("/Users/lehrkraft/Sonstiges/AB.pdf", basis: basis)
                == "/Users/lehrkraft/Sonstiges/AB.pdf")
        // Ein Ordner mit gleichem Vorsatz ist nicht derselbe Ordner.
        #expect(Pfade.relativMachen("/Users/lehrkraft/Unterrichtsmaterial/AB.pdf", basis: basis)
                == "/Users/lehrkraft/Unterrichtsmaterial/AB.pdf")
        #expect(Pfade.relativMachen("/anderswo/AB.pdf", basis: "") == "/anderswo/AB.pdf")
    }

    @Test("Der vollständige Pfad setzt den Basisordner wieder davor")
    func vollerPfad() {
        #expect(Pfade.vollerPfad("Bio/AB.pdf", basis: basis) == basis + "/Bio/AB.pdf")
        #expect(Pfade.vollerPfad("/anderswo/AB.pdf", basis: basis) == "/anderswo/AB.pdf")
        #expect(Pfade.vollerPfad("Bio/AB.pdf", basis: basis + "/") == basis + "/Bio/AB.pdf")
        #expect(Pfade.vollerPfad("Bio/AB.pdf", basis: "") == "Bio/AB.pdf")
    }

    @Test("Dateiname und Absolutheit")
    func namen() {
        #expect(Pfade.dateiName("/a/b/c.pdf") == "c.pdf")
        #expect(Pfade.dateiName("c.pdf") == "c.pdf")
        #expect(Pfade.dateiName("/a/b/") == "b")
        #expect(Pfade.istAbsolut("/a"))
        #expect(!Pfade.istAbsolut("a"))
    }
}

// ── Sperre für Ausführbares ───────────────────────────────────────────────

@Suite("Was geöffnet werden darf")
@MainActor
struct OeffnenPruefungen {

    @Test("Programmbündel bleiben gesperrt — auch über Umwege im Pfad")
    func programme() {
        let rechner = "/System/Applications/Rechner.app"
        let vorhanden = FileManager.default.fileExists(atPath: rechner)
        let bündel = vorhanden ? rechner : "/System/Applications/Calculator.app"

        #expect(!Systemzugriff.oeffnenErlaubt(bündel))
        #expect(!Systemzugriff.oeffnenErlaubt(bündel + "/"))
        #expect(!Systemzugriff.oeffnenErlaubt(bündel + "/."))
        #expect(!Systemzugriff.oeffnenErlaubt(bündel + "/Contents/.."))
        #expect(!Systemzugriff.oeffnenErlaubt("/System/Applications/../Applications/"
                                              + (bündel as NSString).lastPathComponent))
    }

    @Test("Auch die übrigen Bündelformate sind gesperrt")
    func weitereBuendel() {
        for pfad in ["/System/Library/PreferencePanes/Bluetooth.prefPane",
                     "/System/Library/Automator"] where FileManager.default.fileExists(atPath: pfad) {
            var istOrdner: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: pfad, isDirectory: &istOrdner)
            let werte = try? URL(fileURLWithPath: pfad).resourceValues(forKeys: [.isPackageKey])
            if werte?.isPackage == true {
                #expect(!Systemzugriff.oeffnenErlaubt(pfad), "Bündel \(pfad) müsste gesperrt sein")
            }
        }
        #expect(Systemzugriff.oeffnenErlaubt(NSTemporaryDirectory()))
    }

    @Test("Was der Inhaltstyp nicht hergibt, fängt die Endungsliste")
    func typloseStartbare() throws {
        // `.term` erbt von keinem der startbaren Typen, führt beim Öffnen aber
        // den hinterlegten Befehl in Terminal aus; die Abbild-Formate hängen
        // sich ein wie `.dmg`.
        let ordner = URL.temporaryDirectory
            .appending(component: "oeffnen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        for endung in ["term", "terminal", "wflow", "iso", "img", "cdr", "xip",
                       "sparseimage", "smi", "toast"] {
            let datei = ordner.appending(component: "probe." + endung)
            try Data("beliebig".utf8).write(to: datei)
            #expect(!Systemzugriff.oeffnenErlaubt(datei.path),
                    ".\(endung) müsste gesperrt sein")
        }

        // Gegenprobe: gewöhnliche Unterrichtsmaterialien bleiben offen.
        for endung in ["pdf", "docx", "png", "mp4", "csv"] {
            let datei = ordner.appending(component: "material." + endung)
            try Data("beliebig".utf8).write(to: datei)
            #expect(Systemzugriff.oeffnenErlaubt(datei.path),
                    ".\(endung) müsste sich öffnen lassen")
        }
    }

    @Test("Ein PDF mit gesetztem Ausführungsbit bleibt eine gewöhnliche Datei")
    func pdfMitAusfuehrungsrecht() throws {
        // FAT-, Netz- und manche Cloud-Ordner setzen das POSIX-Ausführungsbit;
        // beurteilt wird deshalb der Inhaltstyp.
        let ordner = URL.temporaryDirectory
            .appending(component: "oeffnen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        let pdf = ordner.appending(component: "Lehrplan.pdf")
        try Data("%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n".utf8)
            .write(to: pdf)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pdf.path)

        #expect(FileManager.default.isExecutableFile(atPath: pdf.path),
                "die Vorbedingung der Prüfung: das Bit ist gesetzt")
        #expect(Systemzugriff.oeffnenErlaubt(pdf.path))
    }

    @Test("Skripte und ausführbare Dateien bleiben gesperrt, gewöhnliche nicht")
    func skripte() throws {
        let ordner = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("unterrichtsplanung-pruefung-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        let skript = ordner.appendingPathComponent("start.command")
        try "echo hallo".write(to: skript, atomically: true, encoding: .utf8)
        #expect(!Systemzugriff.oeffnenErlaubt(skript.path))

        let pdf = ordner.appendingPathComponent("Arbeitsblatt.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        #expect(Systemzugriff.oeffnenErlaubt(pdf.path))

        let ausfuehrbar = ordner.appendingPathComponent("programm")
        try Data("#!/bin/sh\necho hallo".utf8).write(to: ausfuehrbar)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ausfuehrbar.path)
        #expect(!Systemzugriff.oeffnenErlaubt(ausfuehrbar.path))
    }

    /// Eine Aliasdatei trägt weder Endung noch Inhaltstyp ihres Ziels — ein
    /// Alias auf ein Programm kam so an der Sperre vorbei, denn
    /// `NSWorkspace.open` startet über ihn das Ziel. Beurteilt wird das ZIEL.
    @Test("Ein Alias auf ein Programm bleibt gesperrt, einer auf ein PDF nicht")
    func aliasdateien() throws {
        let rechner = "/System/Applications/Rechner.app"
        let programm = FileManager.default.fileExists(atPath: rechner)
            ? rechner : "/System/Applications/Calculator.app"
        try #require(FileManager.default.fileExists(atPath: programm),
                     "die Vorbedingung: irgendein Programmbündel muss da sein")

        let ordner = URL.temporaryDirectory.appending(component: "alias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        func aliasAnlegen(auf ziel: URL, name: String) throws -> URL {
            let daten = try ziel.bookmarkData(options: [.suitableForBookmarkFile],
                                              includingResourceValuesForKeys: nil, relativeTo: nil)
            let alias = ordner.appending(component: name)
            try URL.writeBookmarkData(daten, to: alias)
            return alias
        }

        let aufProgramm = try aliasAnlegen(auf: URL(fileURLWithPath: programm), name: "Rechner-Alias")
        #expect(Systemzugriff.aufgeloest(aufProgramm).path == programm,
                "die Vorbedingung: der Alias muss sich auflösen lassen")
        #expect(!Systemzugriff.oeffnenErlaubt(aufProgramm.path))

        let pdf = ordner.appending(component: "Lehrplan.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        let aufPDF = try aliasAnlegen(auf: pdf, name: "Lehrplan-Alias")
        #expect(Systemzugriff.oeffnenErlaubt(aufPDF.path))
    }

    /// Verweisdateien tragen eine Adresse statt eines Inhalts — und die kann
    /// auf alles zeigen, auch auf ein Programm.
    @Test("Verweisdateien werden nicht geöffnet")
    func verweisdateien() throws {
        let ordner = URL.temporaryDirectory.appending(component: "verweis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        for (name, adresse) in [("Ziel.webloc", "https://3ducation.org/"),
                                ("Ziel.fileloc", "file:///System/Applications/")] {
            let datei = ordner.appending(component: name)
            let inhalt = try PropertyListSerialization.data(
                fromPropertyList: ["URL": adresse], format: .xml, options: 0)
            try inhalt.write(to: datei)
            #expect(!Systemzugriff.oeffnenErlaubt(datei.path),
                    Comment(rawValue: "\(name) müsste abgewiesen werden"))
        }
    }
}

// ── Standarddatensatz ─────────────────────────────────────────────────────

@Suite("Standardkurse")
struct StandardkursePruefungen {

    /// Klasse **und** Fach zusammen sind eindeutig, der Name allein nicht:
    /// „G6a“ steht dreimal in der Liste, und dreimal dieselbe `ForEach`-Kennung
    /// ist für SwiftUI undefiniertes Verhalten.
    @Test("Klasse und Fach zusammen sind eindeutig")
    func eindeutigkeit() {
        let namen = Standardkurse.liste.map(\.name)
        #expect(Set(namen).count < namen.count,
                "die Vorbedingung: derselbe Klassenname kommt mehrfach vor")

        let paare = Standardkurse.liste.map { $0.name + "|" + $0.fach }
        #expect(Set(paare).count == paare.count, "Klasse und Fach müssen zusammen eindeutig sein")
    }

    @Test("Jeder Standardkurs trägt Klasse und Fach")
    func vollstaendig() {
        #expect(!Standardkurse.liste.isEmpty)
        #expect(Standardkurse.liste.count <= Kennwerte.maxKlassen)
        #expect(Kennwerte.maxKlassen == 75)
        for kurs in Standardkurse.liste {
            #expect(!kurs.name.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!kurs.fach.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

// ── Pfade zusammenfassen ──────────────────────────────────────────────────

@Suite("Verweise aus einer Datei zusammenfassen")
struct ZusammenfassenPruefungen {
    private let basis = "/Users/lehrkraft/Unterricht"

    @Test("„..“ verlässt den Basisordner und wird danach als außerhalb geführt")
    func hinaus() {
        let ergebnis = Pfade.zusammenfassen("../../../System/Applications/Rechner.app", basis: basis)
        #expect(ergebnis == "/System/Applications/Rechner.app")
        #expect(Pfade.istAbsolut(ergebnis))
    }

    @Test("Verweise innerhalb bleiben relativ")
    func drinnen() {
        #expect(Pfade.zusammenfassen("Bio/AB.pdf", basis: basis) == "Bio/AB.pdf")
        #expect(Pfade.zusammenfassen("Bio/../Chemie/AB.pdf", basis: basis) == "Chemie/AB.pdf")
        #expect(Pfade.zusammenfassen("/Users/lehrkraft/Unterricht/Bio/AB.pdf", basis: basis)
                == "Bio/AB.pdf")
    }

    @Test("Ohne Basisordner bleibt alles, wie es ist")
    func ohneBasis() {
        #expect(Pfade.zusammenfassen("Bio/AB.pdf", basis: "") == "Bio/AB.pdf")
    }
}
