// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Mehrfachauswahl verschieben ───────────────────────────────────────────

@Suite("Mehrfachauswahl verschieben")
@MainActor
struct MehrfachVerschiebenPruefungen {

    private func speicherMitDreien() throws -> Planungsspeicher {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 12,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let kurs = planung.klassen[0].id
        planung.eintraege = (0..<3).map {
            Vorhaben(id: "e\($0)", klasseId: kurs, woche: $0, titel: "V\($0)", text: "",
                     erledigt: false, materialien: [], links: [])
        }
        return Planungsspeicher(vorschau: planung)
    }

    @Test("Drei vorgemerkte Vorhaben werden auch zu dritt verschoben")
    func dreiVerschieben() throws {
        let speicher = try speicherMitDreien()
        let planung = try #require(speicher.planung)
        let quelle = planung.klassen[0].id
        let ziel = planung.klassen[1].id

        speicher.anwaehlen(vorhaben: "e0")
        speicher.anwaehlen(vorhaben: "e1", erweitern: true)
        speicher.anwaehlen(vorhaben: "e2", erweitern: true)
        #expect(speicher.auswahl.count == 3)

        speicher.verschiebenVormerken()
        #expect(speicher.ablage?.vorhaben.count == 3)

        speicher.anwaehlen(zelle: Zellenort(klasse: ziel, woche: 5))
        speicher.einfuegen()

        let nachher = try #require(speicher.planung)
        let imZiel = nachher.eintraege.filter { $0.klasseId == ziel }
        #expect(imZiel.count == 3, "alle drei müssen im Zielkurs liegen")
        #expect(nachher.eintraege.filter { $0.klasseId == quelle }.isEmpty,
                "im Ausgangskurs darf keines liegen bleiben")
        #expect(imZiel.map(\.woche).sorted() == [5, 6, 7])
    }

    @Test("Die Ablage überlebt einen Wechsel der Zielzelle")
    func ablageUeberlebt() throws {
        let speicher = try speicherMitDreien()
        let planung = try #require(speicher.planung)
        speicher.anwaehlen(vorhaben: "e0")
        speicher.anwaehlen(vorhaben: "e1", erweitern: true)
        speicher.verschiebenVormerken()
        speicher.anwaehlen(zelle: Zellenort(klasse: planung.klassen[2].id, woche: 1))
        speicher.anwaehlen(zelle: Zellenort(klasse: planung.klassen[1].id, woche: 4))
        #expect(speicher.ablage?.vorhaben.count == 2)
        speicher.einfuegen()
        let nachher = try #require(speicher.planung)
        #expect(nachher.eintraege.filter { $0.klasseId == planung.klassen[1].id }.count == 2)
    }
}

// ── Fachfarben ────────────────────────────────────────────────────────────

@Suite("Fachfarben")
@MainActor
struct FachfarbenPruefungen {

    @Test("Jedes eingetragene Fach bekommt eine Farbe aus der Palette")
    func jedesFachBekommtEine() throws {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
            basis: "", klassen: Standardkurse.aufbauen([(name: "K1", fach: "Musik")]),
            fachfarben: [:])
        planung.eintraege = []
        let speicher = Planungsspeicher(vorschau: planung)
        let schluessel = Farbwelt.fachSchluessel("Musik")

        let vergeben = try #require(speicher.planung?.fachfarbe("Musik"))
        #expect(Farbwelt.istGueltig(vergeben))
        #expect(speicher.planung?.klassen[0].farbe == vergeben)
        // Hergeleitet, nicht geschrieben.
        #expect(speicher.planung?.fachfarben.isEmpty == true)

        speicher.fachfarbeSetzen(fach: schluessel, ton: "tuerkis-dunkel")
        let nachher = try #require(speicher.planung)
        #expect(nachher.fachfarben[schluessel] == "tuerkis-dunkel")
        #expect(nachher.klassen[0].farbe == Farbwelt.stelle("tuerkis-dunkel"))
    }

    @Test("Eine Fachfarbe übersteht das Schreiben und Lesen der Datei")
    func fachfarbeUeberlebt() throws {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
            basis: "", klassen: Standardkurse.aufbauen([(name: "K1", fach: "Musik")]),
            fachfarben: [Farbwelt.fachSchluessel("Musik"): "violett-hell"])
        planung.eintraege = []
        let daten = try Planungsdatei.schreiben(planung)
        let gelesen = try Planungsdatei.lesen(daten)
        #expect(gelesen.fachfarben[Farbwelt.fachSchluessel("Musik")] == "violett-hell")
        #expect(gelesen.klassen[0].farbe == Farbwelt.stelle("violett-hell"))
    }

    @Test("Eine Planung der alten Palette wird beim Lesen übersetzt")
    func altePaletteUebersetzen() throws {
        // Ohne „version“: alte Plätze. 0 = Biologie, 10 = Informatik, 32 = Grau.
        let alt = #"""
        {"typ":"unterrichtsplanung","titel":"Alt","start":"2026-08-03","wochen":4,
         "fachfarben":{"biologie":"biologie","kunst":"magenta"},
         "klassen":[{"id":"k1","name":"G5","fach":"Biologie","farbe":0},
                    {"id":"k2","name":"G8","fach":"Informatik","farbe":10},
                    {"id":"k3","name":"Chor","fach":"","farbe":32}],
         "eintraege":[]}
        """#
        let gelesen = try Planungsdatei.lesen(Data(alt.utf8))
        #expect(gelesen.fachfarben["biologie"] == "gruen-mittel")
        #expect(gelesen.fachfarben["kunst"] == "magenta-mittel")
        #expect(gelesen.klassen[0].farbe == Farbwelt.stelle("gruen-mittel"))
        #expect(gelesen.klassen[1].farbe == Farbwelt.stelle("blau-mittel"))
        #expect(gelesen.fachfarbe("Informatik") == Farbwelt.stelle("blau-mittel"))
        #expect(gelesen.fachfarben["informatik"] == nil)
        // Grau hat keine Entsprechung: eine freie Farbe, die keiner sonst trägt.
        #expect(Farbwelt.istGueltig(gelesen.klassen[2].farbe))
        #expect(Set(gelesen.klassen.map(\.farbe)).count == 3)
        #expect(gelesen.fachfarben.count == 2)

        let neu = #"""
        {"typ":"unterrichtsplanung","version":2,"titel":"Neu","start":"2026-08-03","wochen":4,
         "fachfarben":{"biologie":"rot-hell"},
         "klassen":[{"id":"k1","name":"G5","fach":"Biologie","farbe":7}],
         "eintraege":[]}
        """#
        let zweite = try Planungsdatei.lesen(Data(neu.utf8))
        #expect(zweite.fachfarben["biologie"] == "rot-hell")
        #expect(zweite.klassen[0].farbe == 7)
    }

    @Test("Ohne übersetzbare Farbe fällt „von Hand gesetzt“ weg")
    func handfarbeOhneFarbe() throws {
        let alt = #"""
        {"typ":"unterrichtsplanung","titel":"Alt","start":"2026-08-03","wochen":4,
         "klassen":[{"id":"k1","name":"A","fach":"Sport","farbe":32,"farbeManuell":true},
                    {"id":"k2","name":"B","fach":"Sport"}],
         "eintraege":[]}
        """#
        let gelesen = try Planungsdatei.lesen(Data(alt.utf8))
        #expect(!gelesen.klassen[0].farbeManuell)
        #expect(Farbwelt.istGueltig(gelesen.klassen[0].farbe))
        #expect(gelesen.klassen[0].farbe == gelesen.klassen[1].farbe)
        #expect(gelesen.fachfarbe("Sport") == gelesen.klassen[0].farbe)
    }

    /// Der einzige Setzer, der lange bar jeder Kappung war.
    @Test("Ein Fach lässt sich nicht über die Namenslänge hinaus umbenennen")
    func umbenennenKappt() throws {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
            basis: "", klassen: Standardkurse.aufbauen([(name: "K1", fach: "Musik")]),
            fachfarben: [Farbwelt.fachSchluessel("Musik"): "violett-hell"])
        planung.eintraege = []
        let speicher = Planungsspeicher(vorschau: planung)

        let lang = String(repeating: "m", count: Planungsdatei.maxNamenslaenge + 100)
        speicher.fachUmbenennen(von: Farbwelt.fachSchluessel("Musik"), nach: lang)

        let nachher = try #require(speicher.planung)
        let gekappt = String(lang.prefix(Planungsdatei.maxNamenslaenge))
        #expect(nachher.klassen[0].fach == gekappt)
        #expect(nachher.fachfarben[Farbwelt.fachSchluessel(gekappt)] == "violett-hell")
        // Der Leser findet nichts mehr zu kürzen.
        let gelesen = try Planungsdatei.lesenMitBilanz(Planungsdatei.schreiben(nachher))
        #expect(gelesen.bilanz.gekuerzteTexte == 0)
    }

    /// Eine Grenze, die nur beim Lesen gälte, wäre eine Datenfalle.
    @Test("Die Zahl der festgelegten Fachfarben bleibt unter der Lesegrenze")
    func fachfarbenGrenze() throws {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
            basis: "", klassen: [], fachfarben: [:])
        planung.eintraege = []
        // Bis an die Grenze gefüllt, ohne eine einzige Zeile.
        for nummer in 0..<Planungsdatei.maxFachfarben {
            planung.fachfarben["fach\(nummer)"] = "blau-mittel"
        }
        let speicher = Planungsspeicher(vorschau: planung)

        speicher.fachfarbeSetzen(fach: "einsZuviel", ton: "rot-hell")
        #expect(speicher.planung?.fachfarben.count == Planungsdatei.maxFachfarben)
        #expect(speicher.planung?.fachfarben["einsZuviel"] == nil)
        #expect(speicher.meldungen.contains { $0.art == .warnung })

        // Ein schon belegtes Fach darf seine Farbe auch am Rand noch wechseln.
        speicher.fachfarbeSetzen(fach: "fach0", ton: "rot-hell")
        #expect(speicher.planung?.fachfarben["fach0"] == "rot-hell")
        #expect(speicher.planung?.fachfarben.count == Planungsdatei.maxFachfarben)

        // Und Wegnehmen macht wieder Platz.
        speicher.fachfarbeSetzen(fach: "fach0", ton: nil)
        speicher.fachfarbeSetzen(fach: "einsZuviel", ton: "rot-hell")
        #expect(speicher.planung?.fachfarben["einsZuviel"] == "rot-hell")
    }
}

// ── Rasterdaten ───────────────────────────────────────────────────────────

@Suite("Rasterdaten")
@MainActor
struct RasterdatenPruefungen {

    private func planungMitZellen() throws -> Planung {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 12,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let kurs = planung.klassen[0].id
        planung.eintraege = (0..<3).map {
            Vorhaben(id: "e\($0)", klasseId: kurs, woche: 1, titel: "V\($0)", text: "",
                     erledigt: false, materialien: [], links: [])
        }
        return planung
    }

    @Test("Die Zelle weiß, welche Kachel sich rücken lässt")
    func rueckbarkeit() throws {
        let daten = Rasterdaten(try planungMitZellen(), stand: 1, breite: 280)
        let kacheln = daten.kacheln(zeile: 0, woche: 1)
        #expect(kacheln.count == 3)
        #expect(!kacheln[0].kannHoch && kacheln[0].kannRunter)
        #expect(kacheln[1].kannHoch && kacheln[1].kannRunter)
        #expect(kacheln[2].kannHoch && !kacheln[2].kannRunter)
    }

    @Test("Unveränderte Kacheln werden aus der vorigen Aufnahme übernommen")
    func uebernahme() throws {
        let planung = try planungMitZellen()
        let erste = Rasterdaten(planung, stand: 1, breite: 280)
        let zweite = Rasterdaten(planung, stand: 2, breite: 280, vorher: erste)
        // Übernommen heißt: derselbe gesetzte Text, nicht bloß ein gleicher.
        let a = try #require(erste.kacheln(zeile: 0, woche: 1).first)
        let b = try #require(zweite.kacheln(zeile: 0, woche: 1).first)
        #expect(a.gesetzterTitel === b.gesetzterTitel)
    }

    @Test("Die Gesamtbreite deckt alle Wochen ab")
    func gesamtbreite() throws {
        let planung = try planungMitZellen()
        let daten = Rasterdaten(planung, stand: 1, breite: 280)
        #expect(daten.wochen.count == planung.wochen)
        #expect(daten.gesamtbreite == CGFloat(280 * planung.wochen))
    }

    /// Unter der letzten Kurszeile endet der Rollinhalt — ein Zuschlag sah aus
    /// wie Platz für eine weitere Zeile.
    @Test("Die Gesamthöhe ist die Summe der Zeilenhöhen, ohne Zuschlag")
    func gesamthoehe() throws {
        let planung = try planungMitZellen()
        let daten = Rasterdaten(planung, stand: 1, breite: 280)
        #expect(daten.gesamthoehe == daten.zeilen.map(\.hoehe).reduce(0, +))
        #expect(daten.zeilen.count == planung.klassen.count)
    }
}

// ── Prüfungen ─────────────────────────────────────────────────────────────

@Suite("Vorhaben als Prüfung")
@MainActor
struct PruefungsPruefungen {

    private func planungMitPruefungen() throws -> Planung {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-03")), wochen: 12,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let a = planung.klassen[0].id
        let b = planung.klassen[1].id
        planung.eintraege = [
            Vorhaben(id: "ohne", klasseId: a, woche: 0, titel: "Ohne Termin", text: "",
                     erledigt: false, materialien: [], links: [], pruefung: true),
            Vorhaben(id: "spaet", klasseId: b, woche: 4, titel: "Später", text: "",
                     erledigt: false, materialien: [], links: [], pruefung: true,
                     pruefungstag: Tag(iso: "2026-09-03")),
            Vorhaben(id: "frueh", klasseId: a, woche: 1, titel: "Früher", text: "",
                     erledigt: false, materialien: [], links: [], pruefung: true,
                     pruefungstag: Tag(iso: "2026-08-12")),
            Vorhaben(id: "keine", klasseId: a, woche: 2, titel: "Gewöhnlich", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        return planung
    }

    @Test("Die Übersicht ordnet nach Termin, Unbestimmtes ans Ende")
    func reihenfolge() throws {
        let speicher = Planungsspeicher(vorschau: try planungMitPruefungen())
        #expect(speicher.pruefungsliste.map(\.vorhaben.id) == ["frueh", "spaet", "ohne"])
    }

    @Test("Ein Termin außerhalb der geplanten Woche wird erkannt")
    func ausserhalb() throws {
        let planung = try planungMitPruefungen()
        let start = planung.start
        // „frueh“ steht in Woche 1 (10.–16.08.), Termin am 12.08. — passt.
        let passend = try #require(planung.eintraege.first { $0.id == "frueh" })
        #expect(!passend.terminAusserhalb(start: start))
        let auchPassend = try #require(planung.eintraege.first { $0.id == "spaet" })
        #expect(!auchPassend.terminAusserhalb(start: start))
        let ohne = try #require(planung.eintraege.first { $0.id == "ohne" })
        #expect(!ohne.terminAusserhalb(start: start))
        var verschoben = passend
        verschoben.woche = 8
        #expect(verschoben.terminAusserhalb(start: start))
    }

    @Test("Umschalten schlägt den Wochenmontag vor und nimmt ihn wieder mit")
    func umschalten() throws {
        let speicher = Planungsspeicher(vorschau: try planungMitPruefungen())
        speicher.pruefungUmschalten("keine")
        var eintrag = try #require(speicher.planung?.eintraege.first { $0.id == "keine" })
        #expect(eintrag.pruefung)
        // Woche 2 der Planung ab dem 03.08. — Montag ist der 17.08.
        #expect(eintrag.pruefungstag == Tag(iso: "2026-08-17"))

        speicher.pruefungUmschalten("keine")
        eintrag = try #require(speicher.planung?.eintraege.first { $0.id == "keine" })
        #expect(!eintrag.pruefung)
        #expect(eintrag.pruefungstag == nil,
                "ohne Kennzeichnung darf kein Termin liegen bleiben")
    }

    @Test("Kennzeichnung und Termin überstehen Schreiben und Lesen")
    func dateiweg() throws {
        let daten = try Planungsdatei.schreiben(try planungMitPruefungen())
        let gelesen = try Planungsdatei.lesen(daten)
        let frueh = try #require(gelesen.eintraege.first { $0.id == "frueh" })
        #expect(frueh.pruefung)
        #expect(frueh.pruefungstag == Tag(iso: "2026-08-12"))
        let ohne = try #require(gelesen.eintraege.first { $0.id == "ohne" })
        #expect(ohne.pruefung)
        #expect(ohne.pruefungstag == nil)
        let keine = try #require(gelesen.eintraege.first { $0.id == "keine" })
        #expect(!keine.pruefung)
    }

    @Test("Ältere Dateien ohne die Felder bleiben lesbar")
    func alteDatei() throws {
        // Die Form einer älteren Datei — ohne „pruefung“.
        let roh = """
        {"typ":"unterrichtsplanung","version":1,"titel":"Alt","start":"2026-08-03",
         "wochen":4,"klassen":[{"id":"k1","name":"K1","fach":"Biologie","farbe":0}],
         "eintraege":[{"id":"e1","klasseId":"k1","woche":0,"titel":"Alt","erledigt":false}]}
        """
        let gelesen = try Planungsdatei.lesen(Data(roh.utf8))
        let eintrag = try #require(gelesen.eintraege.first)
        #expect(!eintrag.pruefung)
        #expect(eintrag.pruefungstag == nil)
    }

    @Test("Eine Prüfung braucht mehr Höhe als dasselbe Vorhaben ohne")
    func hoehe() throws {
        var ohne = Vorhaben(id: "x", klasseId: "k", woche: 0, titel: "Titel", text: "",
                            erledigt: false, materialien: [], links: [])
        let schmal = Zellenmass.kachelhoehe(ohne, breite: 280)
        ohne.pruefung = true
        ohne.pruefungstag = Tag(iso: "2026-08-12")
        let hoch = Zellenmass.kachelhoehe(ohne, breite: 280)
        #expect(hoch > schmal, "die Terminzeile muss in der Höhe stehen")
        #expect(hoch - schmal == Zellenmass.hoehePruefungszeile + Zellenmass.abstandPruefung)
    }
}

// ── Datum und Dringlichkeit ───────────────────────────────────────────────

@Suite("Datum und Dringlichkeit eines Vorhabens")
@MainActor
struct DatumUndDringlichkeit {

    private func planung() throws -> Planung {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-03")), wochen: 12,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let a = planung.klassen[0].id
        planung.eintraege = [
            Vorhaben(id: "mit", klasseId: a, woche: 1, titel: "Mit Datum", text: "",
                     erledigt: false, materialien: [], links: [],
                     datum: Tag(iso: "2026-08-12"), dringend: true),
            Vorhaben(id: "ohne", klasseId: a, woche: 2, titel: "Ohne", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        return planung
    }

    @Test("Datum und Kennzeichnung überstehen Schreiben und Lesen")
    func dateiweg() throws {
        let daten = try Planungsdatei.schreiben(try planung())
        let gelesen = try Planungsdatei.lesen(daten)
        let mit = try #require(gelesen.eintraege.first { $0.id == "mit" })
        #expect(mit.datum == Tag(iso: "2026-08-12"))
        #expect(mit.dringend)
        let ohne = try #require(gelesen.eintraege.first { $0.id == "ohne" })
        #expect(ohne.datum == nil)
        #expect(!ohne.dringend)
    }

    @Test("Ältere Dateien ohne die Felder bleiben lesbar")
    func alteDatei() throws {
        let roh = """
        {"typ":"unterrichtsplanung","version":1,"titel":"Alt","start":"2026-08-03",
         "wochen":4,"klassen":[{"id":"k1","name":"K1","fach":"Biologie","farbe":0}],
         "eintraege":[{"id":"e1","klasseId":"k1","woche":0,"titel":"Alt","erledigt":false}]}
        """
        let eintrag = try #require(try Planungsdatei.lesen(Data(roh.utf8)).eintraege.first)
        #expect(eintrag.datum == nil)
        #expect(!eintrag.dringend)
    }

    @Test("Ein unlesbares Datum wird verworfen, das Vorhaben bleibt")
    func unlesbaresDatum() throws {
        let roh = """
        {"typ":"unterrichtsplanung","titel":"X","start":"2026-08-03","wochen":4,
         "klassen":[{"id":"k1","name":"K1","farbe":0}],
         "eintraege":[{"id":"e1","klasseId":"k1","woche":0,"titel":"X",
                       "datum":"morgen","dringend":"ja"}]}
        """
        let eintrag = try #require(try Planungsdatei.lesen(Data(roh.utf8)).eintraege.first)
        #expect(eintrag.titel == "X")
        #expect(eintrag.datum == nil)
        // Beim nachsichtigen Lesen gilt eine nichtleere Zeichenkette als wahr.
        #expect(eintrag.dringend)
    }

    @Test("Ein Datum außerhalb der geplanten Woche wird erkannt")
    func ausserhalb() throws {
        let p = try planung()
        let mit = try #require(p.eintraege.first { $0.id == "mit" })
        #expect(!mit.datumAusserhalb(start: p.start))
        var verschoben = mit
        verschoben.woche = 8
        #expect(verschoben.datumAusserhalb(start: p.start))
        let ohne = try #require(p.eintraege.first { $0.id == "ohne" })
        #expect(!ohne.datumAusserhalb(start: p.start))
    }

    /// Ein Sperrzeitraum verbietet Prüfungen, nicht den Unterricht — das Datum
    /// eines gewöhnlichen Vorhabens darf darin liegen.
    @Test("Ein Sperrzeitraum nimmt dem Datum nichts")
    func sperrzeitraum() throws {
        var p = try planung()
        p.sperrzeiten = [Sperrzeitraum(id: "s1", name: "Projektwoche",
                                       von: try #require(Tag(iso: "2026-08-10")),
                                       bis: try #require(Tag(iso: "2026-08-16")))]
        let speicher = Planungsspeicher(vorschau: p)
        var entwurf = VorhabenEntwurf(try #require(p.eintraege.first { $0.id == "mit" }))
        entwurf.pruefung = true
        entwurf.pruefungstag = Tag(iso: "2026-08-12")
        speicher.vorhabenSichern(entwurf)

        let gesichert = try #require(speicher.planung?.eintraege.first { $0.id == "mit" })
        #expect(gesichert.datum == Tag(iso: "2026-08-12"), "das Datum bleibt")
        #expect(gesichert.pruefungstag == nil, "der Prüfungstermin wird abgewiesen")
    }

    @Test("Der Dialog schreibt Datum und Kennzeichnung zurück")
    func ausDemDialog() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        var entwurf = VorhabenEntwurf(try #require(speicher.planung?.eintraege
            .first { $0.id == "ohne" }))
        #expect(!entwurf.veraendert)
        entwurf.datum = Tag(iso: "2026-08-19")
        entwurf.dringend = true
        #expect(entwurf.veraendert, "sonst ginge die Eingabe beim Abbrechen still verloren")
        speicher.vorhabenSichern(entwurf)

        let gesichert = try #require(speicher.planung?.eintraege.first { $0.id == "ohne" })
        #expect(gesichert.datum == Tag(iso: "2026-08-19"))
        #expect(gesichert.dringend)
    }

    @Test("Am Kontextmenü lässt sich die Dringlichkeit umschalten")
    func umschalten() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.dringlichUmschalten("ohne")
        #expect(speicher.planung?.eintraege.first { $0.id == "ohne" }?.dringend == true)
        speicher.dringlichUmschalten("ohne")
        #expect(speicher.planung?.eintraege.first { $0.id == "ohne" }?.dringend == false)
    }

    /// Der Wochentag ist kein eigenes Feld, sondern der Wochentag des Datums —
    /// so können beide nie auseinanderlaufen.
    @Test("Der Wochentag eines Vorhabens ist der seines Datums")
    func wochentag() throws {
        let p = try planung()
        let mit = try #require(p.eintraege.first { $0.id == "mit" })
        #expect(mit.wochentag == .mittwoch)
        let ohne = try #require(p.eintraege.first { $0.id == "ohne" })
        #expect(ohne.wochentag == nil)
        var wochenende = mit
        wochenende.datum = Tag(iso: "2026-08-15")
        #expect(wochenende.wochentag == nil, "ein Samstag ist kein Unterrichtstag")
        // Auch der Entwurf des Dialogs leitet ab statt zu speichern.
        var entwurf = VorhabenEntwurf(mit)
        #expect(entwurf.wochentag == .mittwoch)
        entwurf.datum = Tag(iso: "2026-08-14")
        #expect(entwurf.wochentag == .freitag)
        entwurf.datum = nil
        #expect(entwurf.wochentag == nil)
    }

    /// In eine andere Woche verschoben,
    /// verfallen Wochentag und Datum — mit Meldung. In derselben Woche in eine
    /// andere Zeile bleibt beides; ohne Datum gibt es nichts zu melden.
    @Test("Verschieben in eine andere Woche setzt Wochentag und Datum zurück")
    func verschiebenSetztZurueck() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let p = try #require(speicher.planung)
        let a = p.klassen[0].id, b = p.klassen[1].id
        let mit = try #require(p.eintraege.first { $0.id == "mit" })

        speicher.versetzen([mit], nach: Zellenort(klasse: b, woche: 1), verschieben: true)
        var stand = try #require(speicher.planung?.eintraege.first { $0.id == "mit" })
        #expect(stand.klasseId == b)
        #expect(stand.datum == Tag(iso: "2026-08-12"))
        #expect(speicher.meldungen.map(\.text) == ["Vorhaben verschoben"])

        speicher.versetzen([stand], nach: Zellenort(klasse: a, woche: 3), verschieben: true)
        stand = try #require(speicher.planung?.eintraege.first { $0.id == "mit" })
        #expect(stand.woche == 3)
        #expect(stand.datum == nil)
        #expect(stand.wochentag == nil)
        #expect(speicher.meldungen.last?.text == Planungsspeicher.zurueckgesetzt(1))
        #expect(Planungsspeicher.zurueckgesetzt(1)
                == "Durch das Verschieben des Ereignisses in eine andere Woche wurden "
                + "Wochentag und Datum für dieses Vorhaben zurückgesetzt.")

        let gezaehlt = speicher.meldungen.count
        let ohne = try #require(speicher.planung?.eintraege.first { $0.id == "ohne" })
        speicher.versetzen([ohne], nach: Zellenort(klasse: a, woche: 5), verschieben: true)
        #expect(speicher.meldungen.count == gezaehlt + 1)
        #expect(speicher.meldungen.last?.text == "Vorhaben verschoben")
    }

    /// Dieselbe Regel auf den beiden anderen Wegen: einer Mehrfachauswahl über
    /// Zellen hinweg und dem Sichern aus dem Dialog — dort als Schranke für
    /// jeden Weg, der am Dialog vorbeiführt. Eine **Kopie** kommt immer ohne
    /// Datum an, auch in derselben Woche: Sie wird neu platziert und neu
    /// terminiert.
    @Test("Mehrfachauswahl, Dialog und Kopie beim Wochenwechsel")
    func mehrfachDialogKopie() throws {
        var p = try planung()
        let a = p.klassen[0].id, b = p.klassen[1].id
        p.eintraege.append(Vorhaben(id: "zwei", klasseId: b, woche: 2, titel: "Zwei", text: "",
                                    erledigt: false, materialien: [], links: [],
                                    datum: Tag(iso: "2026-08-20")))
        let speicher = Planungsspeicher(vorschau: p)
        let gruppe = p.eintraege.filter { ["mit", "zwei"].contains($0.id) }
        speicher.versetzen(gruppe, nach: Zellenort(klasse: a, woche: 2), verschieben: true)
        let danach = try #require(speicher.planung)
        #expect(danach.eintraege.first { $0.id == "mit" }?.woche == 2)
        #expect(danach.eintraege.first { $0.id == "zwei" }?.woche == 3)
        #expect(danach.eintraege.filter { ["mit", "zwei"].contains($0.id) }
                    .allSatisfy { $0.datum == nil })
        #expect(speicher.meldungen.last?.text == Planungsspeicher.zurueckgesetzt(2))

        // Dialog: Woche gewechselt, Datum unverändert mitgebracht → verfällt.
        let frisch = Planungsspeicher(vorschau: try planung())
        var entwurf = VorhabenEntwurf(try #require(frisch.planung?.eintraege
            .first { $0.id == "mit" }))
        entwurf.woche = 4
        frisch.vorhabenSichern(entwurf)
        var gesichert = try #require(frisch.planung?.eintraege.first { $0.id == "mit" })
        #expect(gesichert.woche == 4)
        #expect(gesichert.datum == nil)
        #expect(frisch.meldungen.last?.text == Planungsspeicher.zurueckgesetzt(1))

        // Dialog: Woche gewechselt UND ein Tag der neuen Woche gewählt → bleibt.
        var erneut = VorhabenEntwurf(gesichert)
        erneut.woche = 5
        erneut.datum = Tag(iso: "2026-09-08")   // Dienstag der 6. Spalte (Start 03.08.)
        frisch.vorhabenSichern(erneut)
        gesichert = try #require(frisch.planung?.eintraege.first { $0.id == "mit" })
        #expect(gesichert.woche == 5)
        #expect(gesichert.datum == Tag(iso: "2026-09-08"))
        #expect(gesichert.wochentag == .dienstag)

        // Kopie in eine andere Woche: ohne Datum, mit eigener Meldung.
        // (Jede `planung()` vergibt frische Zeilenkennungen — die Zelle kommt
        // deshalb aus diesem Speicher, nicht aus `p`.)
        let kopiert = Planungsspeicher(vorschau: try planung())
        let quelle = try #require(kopiert.planung?.eintraege.first { $0.id == "mit" })
        kopiert.versetzen([quelle], nach: Zellenort(klasse: quelle.klasseId, woche: 6),
                          verschieben: false)
        let kopie = try #require(kopiert.planung?.eintraege.first { $0.woche == 6 })
        #expect(kopie.datum == nil)
        #expect(kopie.wochentag == nil)
        #expect(kopiert.meldungen.map(\.text)
                == ["Vorhaben eingefügt", Planungsspeicher.kopieOhneDatum(1)])
        // Das Original behält sein Datum.
        #expect(kopiert.planung?.eintraege.first { $0.id == "mit" }?.datum
                == Tag(iso: "2026-08-12"))

        // Auch in dieselbe Zelle kopiert: ohne Datum — neu platziert heißt neu
        // terminiert. Über Zellen hinweg (Mehrzellen-Zweig) ebenso.
        kopiert.versetzen([quelle], nach: Zellenort(klasse: quelle.klasseId, woche: 1),
                          verschieben: false)
        let daneben = try #require(kopiert.planung?.eintraege
            .first { $0.woche == 1 && $0.id != "mit" })
        #expect(daneben.datum == nil)
        let zweiQuellen = try #require(kopiert.planung).eintraege
            .filter { $0.id == "mit" || $0.id == "ohne" }
        kopiert.versetzen(zweiQuellen, nach: Zellenort(klasse: quelle.klasseId, woche: 8),
                          verschieben: false)
        #expect(kopiert.planung?.eintraege.filter { $0.woche >= 8 }.count == 2)
        #expect(kopiert.planung?.eintraege.filter { $0.woche >= 8 }
                    .allSatisfy { $0.datum == nil } == true)
        #expect(kopiert.meldungen.last?.text == Planungsspeicher.kopieOhneDatum(1),
                "nur die eine Quelle mit Datum zählt")
        // Ohne Datum in der Quelle gibt es auch keine Meldung darüber.
        let ohneQuelle = try #require(kopiert.planung?.eintraege.first { $0.id == "ohne" })
        let vorher = kopiert.meldungen.count
        kopiert.versetzen([ohneQuelle], nach: Zellenort(klasse: quelle.klasseId, woche: 10),
                          verschieben: false)
        #expect(kopiert.meldungen.count == vorher + 1)
        #expect(kopiert.meldungen.last?.text == "Vorhaben eingefügt")
    }

    @Test("Ein Datum braucht eine eigene Zeile in der Kachelhöhe")
    func hoehe() throws {
        var vorhaben = Vorhaben(id: "x", klasseId: "k", woche: 0, titel: "Titel", text: "",
                                erledigt: false, materialien: [], links: [])
        let schmal = Zellenmass.kachelhoehe(vorhaben, breite: 280)
        vorhaben.datum = Tag(iso: "2026-08-12")
        let hoch = Zellenmass.kachelhoehe(vorhaben, breite: 280)
        #expect(hoch - schmal == Zellenmass.hoeheDatumszeile + Zellenmass.abstandDatum)
        vorhaben.dringend = true
        #expect(Zellenmass.kachelhoehe(vorhaben, breite: 280) == hoch)
    }
}

// ── Sperrzeiträume ────────────────────────────────────────────────────────

@Suite("Sperrzeiträume für Prüfungen")
@MainActor
struct SperrzeitPruefungen {

    /// Beide Dialoge setzen die Datumsfelder über `mitBeginn`/`mitEnde`. Ein
    /// Zeitraum mit „Ende vor Beginn“ sperrt keinen Tag — er darf über die
    /// Oberfläche gar nicht erst entstehen, denn eine Sperre, die nichts
    /// sperrt, fällt erst auf, wenn ein Prüfungstermin durchgeht.
    @Test("Beim Verdrehen der Daten zieht das andere Ende mit")
    func zeitspanneZiehtMit() throws {
        let montag = try #require(Tag(iso: "2026-08-10"))
        let freitag = try #require(Tag(iso: "2026-08-14"))
        let spaeter = try #require(Tag(iso: "2026-08-24"))
        let frueher = try #require(Tag(iso: "2026-08-03"))

        let sperre = Sperrzeitraum(id: "s1", name: "Projektwoche", von: montag, bis: freitag)
        #expect(sperre.mitBeginn(spaeter) == Sperrzeitraum(id: "s1", name: "Projektwoche",
                                                           von: spaeter, bis: spaeter))
        #expect(sperre.mitEnde(frueher) == Sperrzeitraum(id: "s1", name: "Projektwoche",
                                                         von: frueher, bis: frueher))
        // Innerhalb bleibt das andere Ende, wo es war.
        #expect(sperre.mitBeginn(frueher).bis == freitag)
        #expect(sperre.mitEnde(spaeter).von == montag)
        #expect(!sperre.mitBeginn(spaeter).ungueltig)
        #expect(!sperre.mitEnde(frueher).ungueltig)
        // Die Kurszuweisung bleibt unberührt.
        var mitKursen = sperre
        mitKursen.kurse = ["k1", "k2"]
        #expect(mitKursen.mitBeginn(spaeter).kurse == ["k1", "k2"])

        // Wortgleich für die Ferien — dieselbe Regel, ein Ort.
        let ferien = Ferienzeitraum(id: "f1", name: "Herbst", von: montag, bis: freitag)
        #expect(ferien.mitBeginn(spaeter) == Ferienzeitraum(id: "f1", name: "Herbst",
                                                            von: spaeter, bis: spaeter))
        #expect(ferien.mitEnde(frueher) == Ferienzeitraum(id: "f1", name: "Herbst",
                                                          von: frueher, bis: frueher))
        #expect(ferien.mitBeginn(frueher).bis == freitag)
    }

    private func grundplanung() throws -> Planung {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-03")), wochen: 12,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let kurs = planung.klassen[0].id
        planung.eintraege = [
            Vorhaben(id: "e0", klasseId: kurs, woche: 2, titel: "In der Sperre", text: "",
                     erledigt: false, materialien: [], links: []),
            Vorhaben(id: "e1", klasseId: kurs, woche: 5, titel: "Daneben", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        // Woche 2 beginnt am 17.08.2026 — genau darüber liegt die Sperre.
        planung.sperrzeiten = [
            Sperrzeitraum(id: "s1", name: "Zeugniskonferenzen",
                          von: try #require(Tag(iso: "2026-08-17")),
                          bis: try #require(Tag(iso: "2026-08-21"))),
        ]
        return planung
    }

    private func speicherMitSperre() throws -> Planungsspeicher {
        Planungsspeicher(vorschau: try grundplanung())
    }

    @Test("Ein Tag in der Sperre wird erkannt, einer daneben nicht")
    func erkennung() throws {
        let speicher = try speicherMitSperre()
        let kurs = try #require(speicher.planung?.klassen[0].id)
        for iso in ["2026-08-17", "2026-08-19", "2026-08-21"] {
            let tag = try #require(Tag(iso: iso))
            #expect(speicher.sperre(am: tag, fuer: kurs) != nil, "\(iso) liegt in der Sperre")
        }
        for iso in ["2026-08-16", "2026-08-22"] {
            let tag = try #require(Tag(iso: iso))
            #expect(speicher.sperre(am: tag, fuer: kurs) == nil, "\(iso) liegt daneben")
        }
    }

    @Test("Die Abweisung nennt Beginn und Ende")
    func wortlaut() throws {
        let speicher = try speicherMitSperre()
        let tag = try #require(Tag(iso: "2026-08-19"))
        let kurs = try #require(speicher.planung?.klassen[0].id)
        let sperre = try #require(speicher.sperre(am: tag, fuer: kurs))
        #expect(sperre.abweisung
                == "Im Zeitraum vom 17.08.2026 bis zum 21.08.2026 dürfen keine "
                 + "Prüfungen eingetragen werden.")
    }

    @Test("Das Sichern nimmt einen gesperrten Termin nicht an")
    func sichernWeistAb() throws {
        let speicher = try speicherMitSperre()
        var entwurf = VorhabenEntwurf(try #require(speicher.planung?.eintraege[0]))
        entwurf.pruefung = true
        entwurf.pruefungstag = Tag(iso: "2026-08-19")
        speicher.vorhabenSichern(entwurf)

        let eintrag = try #require(speicher.planung?.eintraege.first { $0.id == "e0" })
        #expect(eintrag.pruefung, "die Kennzeichnung bleibt — verboten ist der Tag")
        #expect(eintrag.pruefungstag == nil, "der gesperrte Termin darf nicht in der Datei landen")
        #expect(speicher.meldungen.contains { $0.art == .warnung })
    }

    @Test("Ein Termin daneben wird angenommen")
    func danebenGehtDurch() throws {
        let speicher = try speicherMitSperre()
        var entwurf = VorhabenEntwurf(try #require(speicher.planung?.eintraege[1]))
        entwurf.pruefung = true
        entwurf.pruefungstag = Tag(iso: "2026-09-08")
        speicher.vorhabenSichern(entwurf)
        let eintrag = try #require(speicher.planung?.eintraege.first { $0.id == "e1" })
        #expect(eintrag.pruefungstag == Tag(iso: "2026-09-08"))
    }

    @Test("Das Umschalten schlägt keinen gesperrten Tag vor")
    func umschaltenMeidetSperre() throws {
        let speicher = try speicherMitSperre()
        speicher.pruefungUmschalten("e0")
        let inSperre = try #require(speicher.planung?.eintraege.first { $0.id == "e0" })
        #expect(inSperre.pruefung)
        #expect(inSperre.pruefungstag == nil, "der Vorschlag lag in der Sperre und entfällt")

        speicher.pruefungUmschalten("e1")
        let frei = try #require(speicher.planung?.eintraege.first { $0.id == "e1" })
        #expect(frei.pruefungstag == Tag(iso: "2026-09-07"))
    }

    @Test("Nachträglich gesperrte Termine bleiben stehen und werden gemeldet")
    func nachtraeglich() throws {
        let speicher = try speicherMitSperre()
        var entwurf = VorhabenEntwurf(try #require(speicher.planung?.eintraege[1]))
        entwurf.pruefung = true
        entwurf.pruefungstag = Tag(iso: "2026-09-08")
        speicher.vorhabenSichern(entwurf)
        #expect(speicher.gesperrteTermine.isEmpty)

        speicher.sperrzeitAendern(Sperrzeitraum(
            id: "s1", name: "Projektwoche",
            von: try #require(Tag(iso: "2026-09-07")),
            bis: try #require(Tag(iso: "2026-09-11"))))

        let eintrag = try #require(speicher.planung?.eintraege.first { $0.id == "e1" })
        #expect(eintrag.pruefungstag == Tag(iso: "2026-09-08"),
                "bestehende Eintragungen werden nicht angetastet")
        #expect(speicher.gesperrteTermine.count == 1, "die Übersicht weist sie aus")
        #expect(speicher.meldungen.contains { $0.art == .warnung })
    }

    @Test("Sperrzeiträume überstehen Schreiben und Lesen")
    func dateiweg() throws {
        let speicher = try speicherMitSperre()
        let daten = try Planungsdatei.schreiben(try #require(speicher.planung))
        let gelesen = try Planungsdatei.lesen(daten)
        #expect(gelesen.sperrzeiten.count == 1)
        let sperre = try #require(gelesen.sperrzeiten.first)
        #expect(sperre.name == "Zeugniskonferenzen")
        #expect(sperre.von == Tag(iso: "2026-08-17"))
        #expect(sperre.bis == Tag(iso: "2026-08-21"))
        let mittendrin = try #require(Tag(iso: "2026-08-19"))
        let kurs = try #require(gelesen.klassen.first?.id)
        #expect(gelesen.sperre(am: mittendrin, fuer: kurs) != nil)
    }

    @Test("Vertauschte Angaben bleiben vertauscht und sperren nichts")
    func vertauscht() throws {
        let roh = """
        {"typ":"unterrichtsplanung","start":"2026-08-03","wochen":4,
         "klassen":[{"id":"k1","name":"K1","fach":"Biologie","farbe":0}],"eintraege":[],
         "sperrzeiten":[{"id":"s1","name":"Verdreht","von":"2026-09-11","bis":"2026-09-07"}]}
        """
        let gelesen = try Planungsdatei.lesen(Data(roh.utf8))
        let sperre = try #require(gelesen.sperrzeiten.first)
        // Gedreht wäre der Zeitraum nach dem nächsten Öffnen wirksam, obwohl
        // die App ihn als „Ende vor Beginn“ ausweist.
        #expect(sperre.von == Tag(iso: "2026-09-11"))
        #expect(sperre.bis == Tag(iso: "2026-09-07"))
        #expect(sperre.ungueltig)
        // Und er sperrt an keinem Tag dazwischen.
        let kurs = try #require(gelesen.klassen.first).id
        for tag in ["2026-09-07", "2026-09-09", "2026-09-11"] {
            #expect(gelesen.sperre(am: try #require(Tag(iso: tag)), fuer: kurs) == nil)
        }
    }

    // ── Kurszuweisung ─────────────────────────────────────────────────────

    /// Dieselbe Sperre, nur auf den **zweiten** Kurs beschränkt; die Vorhaben
    /// stehen im ersten und dürfen unberührt bleiben.
    private func speicherMitKurssperre() throws -> Planungsspeicher {
        let speicher = try speicherMitSperre()
        let zweiter = try #require(speicher.planung?.klassen[1].id)
        speicher.sperrzeitKurseSetzen(id: "s1", kurse: [zweiter])
        return speicher
    }

    @Test("Ohne Zuweisung gilt eine Sperre für jeden Kurs")
    func ohneZuweisungFuerAlle() throws {
        let speicher = try speicherMitSperre()
        let tag = try #require(Tag(iso: "2026-08-19"))
        let sperre = try #require(speicher.planung?.sperrzeiten.first)
        #expect(sperre.giltFuerAlle)
        for klasse in try #require(speicher.planung?.klassen) {
            #expect(speicher.sperre(am: tag, fuer: klasse.id) != nil,
                    "\(klasse.name) muss gebunden sein")
        }
    }

    @Test("Eine zugewiesene Sperre bindet nur die genannten Kurse")
    func zuweisungBindetNurGenannte() throws {
        let speicher = try speicherMitKurssperre()
        let tag = try #require(Tag(iso: "2026-08-19"))
        let klassen = try #require(speicher.planung?.klassen)
        #expect(speicher.sperre(am: tag, fuer: klassen[1].id) != nil, "der genannte Kurs")
        #expect(speicher.sperre(am: tag, fuer: klassen[0].id) == nil, "ein anderer Kurs")
        #expect(speicher.sperre(am: tag, fuer: klassen[2].id) == nil, "ein dritter Kurs")
    }

    @Test("Das Sichern nimmt den Termin an, wenn der Kurs nicht gesperrt ist")
    func sichernAusserhalbDerZuweisung() throws {
        let speicher = try speicherMitKurssperre()
        var entwurf = VorhabenEntwurf(try #require(speicher.planung?.eintraege[0]))
        entwurf.pruefung = true
        entwurf.pruefungstag = Tag(iso: "2026-08-19")
        speicher.vorhabenSichern(entwurf)

        let eintrag = try #require(speicher.planung?.eintraege.first { $0.id == "e0" })
        #expect(eintrag.pruefungstag == Tag(iso: "2026-08-19"),
                "der Kurs steht nicht in der Sperre — der Termin darf stehen")
        #expect(speicher.gesperrteTermine.isEmpty)
    }

    @Test("Das Sichern weist ab, sobald der Kurs in der Sperre steht")
    func sichernInnerhalbDerZuweisung() throws {
        var planung = try grundplanung()
        let zweiter = planung.klassen[1].id
        planung.eintraege.append(Vorhaben(id: "e2", klasseId: zweiter, woche: 2,
                                          titel: "Im gesperrten Kurs", text: "",
                                          erledigt: false, materialien: [], links: []))
        let speicher = Planungsspeicher(vorschau: planung)
        speicher.sperrzeitKurseSetzen(id: "s1", kurse: [zweiter])

        var entwurf = VorhabenEntwurf(try #require(
            speicher.planung?.eintraege.first { $0.id == "e2" }))
        entwurf.pruefung = true
        entwurf.pruefungstag = Tag(iso: "2026-08-19")
        speicher.vorhabenSichern(entwurf)

        let eintrag = try #require(speicher.planung?.eintraege.first { $0.id == "e2" })
        #expect(eintrag.pruefung, "die Kennzeichnung bleibt")
        #expect(eintrag.pruefungstag == nil, "der gesperrte Termin darf nicht in die Datei")
        #expect(speicher.meldungen.contains { $0.art == .warnung })
    }

    @Test("Die Zuweisung folgt der Kursliste, nicht der Reihenfolge des Anklickens")
    func zuweisungGeordnet() throws {
        let speicher = try speicherMitSperre()
        let klassen = try #require(speicher.planung?.klassen)
        speicher.sperrzeitKurseSetzen(id: "s1", kurse: [klassen[4].id, klassen[1].id])
        let sperre = try #require(speicher.planung?.sperrzeiten.first)
        #expect(sperre.kurse == [klassen[1].id, klassen[4].id])
        #expect(!sperre.giltFuerAlle)
    }

    @Test("Die Kurszuweisung übersteht Schreiben und Lesen")
    func zuweisungDateiweg() throws {
        let speicher = try speicherMitKurssperre()
        let zweiter = try #require(speicher.planung?.klassen[1].id)
        let daten = try Planungsdatei.schreiben(try #require(speicher.planung))
        let gelesen = try Planungsdatei.lesen(daten)
        let sperre = try #require(gelesen.sperrzeiten.first)
        #expect(sperre.kurse == [zweiter])
        let tag = try #require(Tag(iso: "2026-08-19"))
        #expect(gelesen.sperre(am: tag, fuer: zweiter) != nil)
        #expect(gelesen.sperre(am: tag, fuer: gelesen.klassen[0].id) == nil)
    }

    @Test("Unbekannte Kurse in der Zuweisung werden beim Lesen verworfen")
    func unbekannteKurseVerworfen() throws {
        let roh = """
        {"typ":"unterrichtsplanung","start":"2026-08-03","wochen":4,
         "klassen":[{"id":"k1","name":"K1","fach":"Biologie","farbe":0}],"eintraege":[],
         "sperrzeiten":[{"id":"s1","name":"Sperre","von":"2026-09-07","bis":"2026-09-11",
                         "kurse":["k1","gibtesnicht","k1"]}]}
        """
        let gelesen = try Planungsdatei.lesen(Data(roh.utf8))
        let sperre = try #require(gelesen.sperrzeiten.first)
        #expect(sperre.kurse == ["k1"], "unbekannt und doppelt fallen weg")
    }

    @Test("Fällt die Zuweisung ganz weg, gilt die Sperre wieder für alle")
    func zuweisungLeerGiltFuerAlle() throws {
        let roh = """
        {"typ":"unterrichtsplanung","start":"2026-08-03","wochen":4,
         "klassen":[{"id":"k1","name":"K1","fach":"Biologie","farbe":0}],"eintraege":[],
         "sperrzeiten":[{"id":"s1","name":"Sperre","von":"2026-09-07","bis":"2026-09-11",
                         "kurse":["fort"]}]}
        """
        let gelesen = try Planungsdatei.lesen(Data(roh.utf8))
        let sperre = try #require(gelesen.sperrzeiten.first)
        #expect(sperre.giltFuerAlle)
        let tag = try #require(Tag(iso: "2026-09-08"))
        #expect(gelesen.sperre(am: tag, fuer: "k1") != nil)
    }

    @Test("Das Entfernen eines Kurses räumt ihn aus den Sperren")
    func kursEntfernenRaeumtAuf() throws {
        let speicher = try speicherMitSperre()
        let klassen = try #require(speicher.planung?.klassen)
        speicher.sperrzeitKurseSetzen(id: "s1", kurse: [klassen[1].id, klassen[2].id])
        speicher.klasseEntfernen(klassen[1])
        speicher.rueckfrageBeantworten(true)

        let sperre = try #require(speicher.planung?.sperrzeiten.first)
        #expect(sperre.kurse == [klassen[2].id])
        let tag = try #require(Tag(iso: "2026-08-19"))
        #expect(speicher.sperre(am: tag, fuer: klassen[0].id) == nil,
                "der verbliebene Kurs bindet die anderen nicht")
    }

    @Test("Der letzte entfernte Kurs lässt die Sperre wieder für alle gelten")
    func letzterKursEntferntGiltFuerAlle() throws {
        let speicher = try speicherMitSperre()
        let klassen = try #require(speicher.planung?.klassen)
        speicher.sperrzeitKurseSetzen(id: "s1", kurse: [klassen[1].id])
        speicher.klasseEntfernen(klassen[1])
        speicher.rueckfrageBeantworten(true)

        let sperre = try #require(speicher.planung?.sperrzeiten.first)
        #expect(sperre.giltFuerAlle)
        let tag = try #require(Tag(iso: "2026-08-19"))
        #expect(speicher.sperre(am: tag, fuer: klassen[0].id) != nil)
    }

    @Test("Die Übersicht zählt nur Termine, deren Kurs auch gesperrt ist")
    func gesperrteTermineAchtenAufDenKurs() throws {
        var planung = try grundplanung()
        let klassen = planung.klassen
        let termin = try #require(Tag(iso: "2026-08-19"))
        planung.eintraege = [
            Vorhaben(id: "a", klasseId: klassen[0].id, woche: 2, titel: "Erster", text: "",
                     erledigt: false, materialien: [], links: [],
                     pruefung: true, pruefungstag: termin),
            Vorhaben(id: "b", klasseId: klassen[1].id, woche: 2, titel: "Zweiter", text: "",
                     erledigt: false, materialien: [], links: [],
                     pruefung: true, pruefungstag: termin),
        ]
        let speicher = Planungsspeicher(vorschau: planung)
        #expect(speicher.gesperrteTermine.count == 2, "ohne Zuweisung sind beide betroffen")

        speicher.sperrzeitKurseSetzen(id: "s1", kurse: [klassen[1].id])
        #expect(speicher.gesperrteTermine.map(\.vorhaben.id) == ["b"])
    }
}

// ── Bestehende Termine überleben eine nachträgliche Sperre ────────────────

@Suite("Nachträgliche Sperre tastet Bestehendes nicht an")
@MainActor
struct SperreNachtraeglichPruefungen {

    /// Die Schranke beim Sichern nahm einen bereits gespeicherten Termin
    /// heraus, sobald eine Sperre darüberlag — auch beim bloßen Berichtigen des
    /// Titels. Ein stiller Datenverlust.
    @Test("Wer den Titel ändert, verliert einen gesperrten Termin nicht")
    func titelaenderungBehaeltTermin() throws {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-03")), wochen: 12,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let kurs = planung.klassen[0].id
        let termin = try #require(Tag(iso: "2026-08-19"))
        planung.eintraege = [
            Vorhaben(id: "e0", klasseId: kurs, woche: 2, titel: "Alt", text: "",
                     erledigt: false, materialien: [], links: [],
                     pruefung: true, pruefungstag: termin),
        ]
        // Die Sperre kommt erst nach dem Termin dazu.
        planung.sperrzeiten = [
            Sperrzeitraum(id: "s1", name: "Später gesperrt",
                          von: try #require(Tag(iso: "2026-08-17")),
                          bis: try #require(Tag(iso: "2026-08-21"))),
        ]
        let speicher = Planungsspeicher(vorschau: planung)

        var entwurf = VorhabenEntwurf(try #require(speicher.planung?.eintraege[0]))
        entwurf.titel = "Neu"
        speicher.vorhabenSichern(entwurf)

        let eintrag = try #require(speicher.planung?.eintraege.first { $0.id == "e0" })
        #expect(eintrag.titel == "Neu")
        #expect(eintrag.pruefungstag == termin,
                "der bestehende Termin darf beim Sichern nicht verschwinden")

        var verschoben = VorhabenEntwurf(eintrag)
        verschoben.pruefungstag = Tag(iso: "2026-08-20")
        speicher.vorhabenSichern(verschoben)
        let danach = try #require(speicher.planung?.eintraege.first { $0.id == "e0" })
        #expect(danach.pruefungstag == nil, "ein neu gewählter gesperrter Tag wird abgewiesen")
    }
}
