// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

private typealias Tag = Unterrichtsplanung.Tag

// ── Schulwochen ───────────────────────────────────────────────────────────

@Suite("Schulwochen")
struct SchulwochenPruefungen {

    /// Start Montag, 10.08.2026 — Woche n beginnt am 10.08. + n·7 Tage.
    private func planung(wochen: Int = 8) throws -> Planung {
        Planung.leer(titel: "Probe", start: try #require(Tag(iso: "2026-08-10")),
                     wochen: wochen, basis: "",
                     klassen: Standardkurse.aufbauen([("7a", "Mathematik"), ("8b", "Chemie")]),
                     fachfarben: [:])
    }

    private func vorhaben(_ klasseId: String, woche: Int) -> Vorhaben {
        Vorhaben(id: Kennung.neu("e"), klasseId: klasseId, woche: woche,
                 titel: "Vorhaben", text: "", erledigt: false, materialien: [], links: [])
    }

    /// Montag und Freitag der n-ten Woche als Ferienzeitraum.
    private func ferienwoche(_ nummer: Int, in planung: Planung,
                             name: String = "Ferien") -> Ferienzeitraum {
        let montag = planung.start.plus(tage: nummer * 7)
        return Ferienzeitraum(id: "f\(nummer)", name: name,
                              von: montag, bis: montag.plus(tage: 4))
    }

    @Test("Ohne Ferien und ohne Vorhaben zählen alle Wochen von 1 an")
    func ohneAlles() throws {
        let p = try planung()
        #expect(p.schulwochen(p.wochenListe) == (1...8).map { $0 })
    }

    @Test("Die 1. Schulwoche ist die erste Woche mit einem Vorhaben")
    func beginntBeimErstenVorhaben() throws {
        var p = try planung()
        p.eintraege.append(vorhaben(p.klassen[0].id, woche: 2))
        #expect(p.schulwochen(p.wochenListe) == [nil, nil, 1, 2, 3, 4, 5, 6])
    }

    @Test("Volle Ferienwochen tragen keine Nummer, danach läuft die Zählung weiter")
    func volleFerienwochenZaehlenNicht() throws {
        var p = try planung()
        p.eintraege.append(vorhaben(p.klassen[0].id, woche: 0))
        p.ferien = [ferienwoche(3, in: p)]
        #expect(p.schulwochen(p.wochenListe) == [1, 2, 3, nil, 4, 5, 6, 7])
    }

    @Test("Angeschnittene Ferienwochen zählen mit")
    func angeschnitteneZaehlen() throws {
        var p = try planung()
        p.eintraege.append(vorhaben(p.klassen[0].id, woche: 0))
        // Mittwoch bis Freitag der Woche 2 — drei von fünf Tagen.
        let montag = p.start.plus(tage: 2 * 7)
        p.ferien = [Ferienzeitraum(id: "t", name: "Brücke",
                                   von: montag.plus(tage: 2), bis: montag.plus(tage: 4))]
        #expect(p.schulwochen(p.wochenListe) == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test("Auch von Hand freigestellte Wochen tragen keine Nummer")
    func vonHandFreigestellt() throws {
        var p = try planung()
        p.eintraege.append(vorhaben(p.klassen[0].id, woche: 0))
        p.frei.insert(p.start.plus(tage: 7))
        #expect(p.schulwochen(p.wochenListe) == [1, nil, 2, 3, 4, 5, 6, 7])
    }

    @Test("Sommerferien am Anfang: die Zählung beginnt nach den Ferien")
    func sommerferienAmAnfang() throws {
        var p = try planung()
        p.ferien = [Ferienzeitraum(id: "s", name: "Sommerferien",
                                   von: p.start, bis: p.start.plus(tage: 11))]
        p.eintraege.append(vorhaben(p.klassen[0].id, woche: 2))
        #expect(p.schulwochen(p.wochenListe) == [nil, nil, 1, 2, 3, 4, 5, 6])
    }

    @Test("Liegen alle Vorhaben in Ferienwochen, zählt die erste freie Woche als 1.")
    func vorhabenNurInFerien() throws {
        var p = try planung()
        p.ferien = [ferienwoche(0, in: p)]
        p.eintraege.append(vorhaben(p.klassen[0].id, woche: 0))
        #expect(p.schulwochen(p.wochenListe) == [nil, 1, 2, 3, 4, 5, 6, 7])
    }

    // ── Von Hand gesetzter erster Schultag ────────────────────

    @Test("Der erste Schultag legt die 1. Schulwoche fest — Vorhaben zählen nicht mehr")
    func ersterSchultagLegtFest() throws {
        var p = try planung()
        p.ersterSchultag = p.start.plus(tage: 2 * 7 + 2)
        p.eintraege.append(vorhaben(p.klassen[0].id, woche: 0))
        #expect(p.schulwochen(p.wochenListe) == [nil, nil, 1, 2, 3, 4, 5, 6])
    }

    @Test("Auch mit erstem Schultag tragen volle Ferienwochen keine Nummer")
    func ersterSchultagMitFerien() throws {
        var p = try planung()
        p.ersterSchultag = p.start.plus(tage: 7)
        p.ferien = [ferienwoche(3, in: p)]
        #expect(p.schulwochen(p.wochenListe) == [nil, 1, 2, nil, 3, 4, 5, 6])
    }

    @Test("Fällt der erste Schultag in volle Ferien, zählt die Woche danach als 1.")
    func ersterSchultagInFerien() throws {
        var p = try planung()
        p.ersterSchultag = p.start.plus(tage: 7 + 3)
        p.ferien = [ferienwoche(1, in: p)]
        #expect(p.schulwochen(p.wochenListe) == [nil, nil, 1, 2, 3, 4, 5, 6])
    }

    @Test("Ein erster Schultag am Wochenende ankert dieselbe Woche")
    func ersterSchultagAmWochenende() throws {
        var p = try planung()
        // Sonntag der Woche 2: hier könnten die Wochentagsformeln auseinanderlaufen.
        p.ersterSchultag = p.start.plus(tage: 2 * 7 + 6)
        #expect(p.schulwochen(p.wochenListe) == [nil, nil, 1, 2, 3, 4, 5, 6])
    }

    @Test("Liegt der erste Schultag außerhalb der Planung, greift die Herleitung")
    func ersterSchultagAusserhalb() throws {
        var p = try planung()
        p.ersterSchultag = p.start.plus(tage: 100 * 7)
        p.eintraege.append(vorhaben(p.klassen[0].id, woche: 2))
        #expect(p.schulwochen(p.wochenListe) == [nil, nil, 1, 2, 3, 4, 5, 6])
    }

    @Test("Der erste Schultag übersteht den Weg durch die Datei")
    func ersterSchultagInDerDatei() throws {
        var p = try planung()
        p.ersterSchultag = p.start.plus(tage: 2 * 7)
        let gelesen = try Planungsdatei.lesen(try Planungsdatei.schreiben(p))
        #expect(gelesen.ersterSchultag == p.ersterSchultag)

        // Leer wird als "" geschrieben; den fehlenden Schlüssel prüfen die DateiPruefungen.
        p.ersterSchultag = nil
        let ohne = try Planungsdatei.lesen(try Planungsdatei.schreiben(p))
        #expect(ohne.ersterSchultag == nil)
    }
}

// ── Wochenstand ───────────────────────────────────────────────────────────

@Suite("Wochenstand")
struct WochenstandPruefungen {

    @Test("Der Wochenstand entspricht den einzeln gerechneten Listen")
    func entsprichtDenEinzellisten() throws {
        var p = Planung.leer(titel: "Probe", start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 6, basis: "",
                             klassen: Standardkurse.aufbauen([("7a", "Mathematik")]),
                             fachfarben: [:])
        let montag = p.start.plus(tage: 7)
        p.ferien = [Ferienzeitraum(id: "f", name: "Ferien",
                                   von: montag, bis: montag.plus(tage: 4))]
        p.eintraege = [Vorhaben(id: "e", klasseId: p.klassen[0].id, woche: 2,
                                titel: "V", text: "", erledigt: false,
                                materialien: [], links: [])]

        let stand = p.wochenstand()
        let wochen = p.wochenListe
        #expect(stand.wochen == wochen)
        #expect(stand.lagen == p.alleLagen(wochen))
        #expect(stand.schulwochen == p.schulwochen(wochen))
    }

    @Test("Die Zugriffe je Woche treffen dieselben Stellen wie die Listen")
    func zugriffeJeWoche() throws {
        let p = Planung.leer(titel: "Probe", start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 4, basis: "", klassen: [], fachfarben: [:])
        let stand = p.wochenstand()
        for woche in stand.wochen {
            #expect(stand.lage(woche) == stand.lagen[woche.nummer])
            #expect(stand.schulwoche(woche) == stand.schulwochen[woche.nummer])
            #expect(stand.woche(woche.nummer) == woche)
        }
        #expect(stand.woche(-1) == nil)
        #expect(stand.woche(stand.wochen.count) == nil)
    }

    @Test("Eine hereingereichte Wochenliste ergibt denselben Stand")
    func hereingereichteListe() throws {
        var p = Planung.leer(titel: "Probe", start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 6, basis: "",
                             klassen: Standardkurse.aufbauen([("7a", "Mathematik")]),
                             fachfarben: [:])
        let montag = p.start.plus(tage: 7)
        p.ferien = [Ferienzeitraum(id: "f", name: "Ferien",
                                   von: montag, bis: montag.plus(tage: 4))]
        p.eintraege = [Vorhaben(id: "e", klasseId: p.klassen[0].id, woche: 2,
                                titel: "V", text: "", erledigt: false,
                                materialien: [], links: [])]
        #expect(p.wochenstand(p.wochenListe) == p.wochenstand())
    }

    @Test("Der leere Stand ist in allen drei Listen leer")
    func leererStand() {
        #expect(Wochenstand.leer.wochen.isEmpty)
        #expect(Wochenstand.leer.lagen.isEmpty)
        #expect(Wochenstand.leer.schulwochen.isEmpty)
    }
}

// ── Übernahme in eine neue Planung ────────────────────────────────────────

@Suite("Übernahme")
struct UebernahmePruefungen {

    private func alte() throws -> Planung {
        var p = Planung.leer(titel: "Altes Jahr", start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 6, basis: "",
                             klassen: Standardkurse.aufbauen([("7a", "Mathematik"),
                                                             ("8b", "Chemie")]),
                             fachfarben: [:])
        // Woche 1 sind volle Ferien: Schulwochen [1, nil, 2, 3, 4, 5].
        let montag = p.start.plus(tage: 7)
        p.ferien = [Ferienzeitraum(id: "f", name: "Herbstferien",
                                   von: montag, bis: montag.plus(tage: 4))]
        p.eintraege = [
            Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 0, titel: "Auftakt",
                     text: "Einstieg", erledigt: true, materialien: [], links: [],
                     pruefung: true, pruefungstag: p.start.plus(tage: 3),
                     datum: p.start.plus(tage: 2), dringend: true, kommentar: "lief gut"),
            Vorhaben(id: "e-2", klasseId: p.klassen[0].id, woche: 2, titel: "Vertiefung",
                     text: "", erledigt: false, materialien: [], links: []),
            Vorhaben(id: "e-3", klasseId: p.klassen[0].id, woche: 1, titel: "In den Ferien",
                     text: "", erledigt: false, materialien: [], links: []),
            Vorhaben(id: "e-4", klasseId: p.klassen[1].id, woche: 0, titel: "Fremde Zeile",
                     text: "", erledigt: false, materialien: [], links: []),
        ]
        return p
    }

    private func anlegen(_ alte: Planung, wochen: Int = 6,
                         uebernahme: [Planung.Uebernahmewunsch])
        -> (planung: Planung, bilanz: Planung.Uebernahmebilanz) {
        Planung.mitUebernahme(titel: "Neues Jahr", start: alte.start.plus(tage: 52 * 7),
                              wochen: wochen, basis: "", klassen: [], fachfarben: [:],
                              von: alte, uebernahme: uebernahme)
    }

    @Test("Nur Klasse/Kurs und Fach: Zeile kommt mit eigener Kennung, ohne Vorhaben")
    func nurZeile() throws {
        let alt = try alte()
        let (neu, bilanz) = anlegen(alt, uebernahme: [.init(klasse: alt.klassen[0],
                                                            mitVorhaben: false)])
        #expect(neu.klassen.count == 1)
        #expect(neu.klassen[0].name == "7a")
        #expect(neu.klassen[0].fach == "Mathematik")
        #expect(neu.klassen[0].id != alt.klassen[0].id)
        #expect(neu.eintraege.isEmpty)
        #expect(bilanz == Planung.Uebernahmebilanz(klassen: 1, vorhaben: 0, uebergangen: 0))
    }

    @Test("Samt Vorhaben: die Schulwoche entscheidet über die neue Spalte")
    func vorhabenNachSchulwoche() throws {
        let alt = try alte()
        let (neu, bilanz) = anlegen(alt, uebernahme: [.init(klasse: alt.klassen[0],
                                                            mitVorhaben: true)])
        // Die neue Planung hat keine Ferien: Schulwoche n liegt dort in Spalte n − 1.
        #expect(neu.eintraege.map(\.titel) == ["Auftakt", "Vertiefung"])
        #expect(neu.eintraege.map(\.woche) == [0, 1])
        #expect(bilanz == Planung.Uebernahmebilanz(klassen: 1, vorhaben: 2, uebergangen: 1))
        #expect(neu.klassen.count == 1)
    }

    @Test("Übernommene Vorhaben beginnen unerledigt und ohne Termine")
    func vorhabenBeginnenFrisch() throws {
        let alt = try alte()
        let (neu, _) = anlegen(alt, uebernahme: [.init(klasse: alt.klassen[0],
                                                       mitVorhaben: true)])
        let auftakt = try #require(neu.eintraege.first { $0.titel == "Auftakt" })
        #expect(auftakt.id != "e-1")
        #expect(auftakt.klasseId == neu.klassen[0].id)
        #expect(!auftakt.erledigt)
        #expect(!auftakt.dringend)
        #expect(auftakt.kommentar.isEmpty)
        #expect(auftakt.datum == nil)
        #expect(auftakt.pruefung)
        #expect(auftakt.pruefungstag == nil)
        #expect(auftakt.text == "Einstieg")
    }

    @Test("Schulwochen jenseits der neuen Planung werden übergangen")
    func jenseitsDerNeuenPlanung() throws {
        let alt = try alte()
        let (neu, bilanz) = anlegen(alt, wochen: 1,
                                    uebernahme: [.init(klasse: alt.klassen[0],
                                                       mitVorhaben: true)])
        #expect(neu.eintraege.map(\.titel) == ["Auftakt"])
        #expect(bilanz.vorhaben == 1)
        #expect(bilanz.uebergangen == 2)
    }

    @Test("Eine doppelte Wunschzeile wird nur einmal übernommen")
    func doppelterWunsch() throws {
        let alt = try alte()
        let wunsch = Planung.Uebernahmewunsch(klasse: alt.klassen[0], mitVorhaben: true)
        let (neu, bilanz) = anlegen(alt, uebernahme: [wunsch, wunsch])
        #expect(neu.klassen.count == 1)
        #expect(neu.eintraege.map(\.titel) == ["Auftakt", "Vertiefung"])
        #expect(bilanz.klassen == 1)
        #expect(bilanz.vorhaben == 2)
    }

    @Test("Der Obergrenze geopferte Zeilen zählen ihre Vorhaben als übergangen")
    func kappungZaehlt() throws {
        let alt = try alte()
        let viele = (0..<Kennwerte.maxKlassen).map { stelle in
            Klasse(id: "neu-\(stelle)", name: "K\(stelle)", fach: "", notiz: "",
                   farbe: Farbwelt.ohneFarbe, farbeManuell: false)
        }
        let (neu, bilanz) = Planung.mitUebernahme(
            titel: "Voll", start: alt.start, wochen: 6, basis: "",
            klassen: viele, fachfarben: [:], von: alt,
            uebernahme: [.init(klasse: alt.klassen[0], mitVorhaben: true)])
        #expect(neu.klassen.count == Kennwerte.maxKlassen)
        #expect(neu.eintraege.isEmpty)
        #expect(bilanz.klassen == 0)
        #expect(bilanz.vorhaben == 0)
        #expect(bilanz.uebergangen == 3)
    }

    @Test("Ein Ziel-Anker verschiebt die Übernahme-Zuordnung")
    func uebernahmeMitAnker() throws {
        let alt = try alte()   // Schulwochen alt: Woche 0 → 1, Woche 1 Ferien, Woche 2 → 2
        let start = alt.start.plus(tage: 52 * 7)
        let (neu, bilanz) = Planung.mitUebernahme(
            titel: "Neues Jahr", start: start, wochen: 4, basis: "", klassen: [],
            fachfarben: [:], ersterSchultag: start.plus(tage: 7),
            von: alt, uebernahme: [.init(klasse: alt.klassen[0], mitVorhaben: true)])
        // Anker in Woche 1: Schulwoche s liegt in Spalte s, Spalte 0 bleibt leer.
        #expect(neu.eintraege.map(\.titel) == ["Auftakt", "Vertiefung"])
        #expect(neu.eintraege.map(\.woche) == [1, 2])
        #expect(bilanz.vorhaben == 2)
        #expect(bilanz.uebergangen == 1)   // „In den Ferien“ trägt keine Schulwoche.
    }

    @Test("Relative Verweise werden über den alten Basisordner aufgelöst")
    func verweiseWerdenAufgeloest() throws {
        var alt = try alte()
        alt.basis = "/Ordner/Schule"
        alt.klassen[0].verwaltung = "Listen/7a.numbers"
        alt.eintraege[0].materialien = [Material(titel: "AB", pfad: "AB-Zelle.pdf"),
                                        Material(titel: "Voll", pfad: "/woanders/x.pdf")]
        let (neu, _) = anlegen(alt, uebernahme: [.init(klasse: alt.klassen[0],
                                                       mitVorhaben: true)])
        #expect(neu.klassen[0].verwaltung == "/Ordner/Schule/Listen/7a.numbers")
        let auftakt = try #require(neu.eintraege.first { $0.titel == "Auftakt" })
        #expect(auftakt.materialien.map(\.pfad)
                == ["/Ordner/Schule/AB-Zelle.pdf", "/woanders/x.pdf"])
    }
}
