// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

@MainActor
private final class Zaehler {
    var stand = 0
    var letzterWert = ""
}

@Suite("Entprellte Eingaben")
@MainActor
struct EntprellerPruefungen {

    @Test("Die Handlung läuft erst nach der Wartezeit")
    func wartet() async throws {
        let zaehler = Zaehler()
        let entpreller = Entpreller()
        entpreller.nach(60) { zaehler.stand += 1 }
        #expect(zaehler.stand == 0)
        try await Task.sleep(for: .milliseconds(200))
        #expect(zaehler.stand == 1)
    }

    @Test("Ein neuer Anstoß verwirft den vorigen")
    func verwirftVorigen() async throws {
        let zaehler = Zaehler()
        let entpreller = Entpreller()
        entpreller.nach(60) { zaehler.letzterWert = "alt" }
        entpreller.nach(60) { zaehler.letzterWert = "neu" }
        try await Task.sleep(for: .milliseconds(200))
        #expect(zaehler.letzterWert == "neu")
        #expect(zaehler.stand == 0)
    }

    @Test("Vor dem Sichern wird alles Ausstehende übernommen")
    func allesUebernehmen() {
        let zaehler = Zaehler()
        // Bewusst lang: Ohne das Übernehmen bliebe die Handlung liegen.
        let einer = Entpreller()
        let anderer = Entpreller()
        einer.nach(30_000) { zaehler.stand += 1 }
        anderer.nach(30_000) { zaehler.letzterWert = "übernommen" }
        #expect(zaehler.stand == 0)

        Entpreller.allesUebernehmen()

        #expect(zaehler.stand == 1)
        #expect(zaehler.letzterWert == "übernommen")

        Entpreller.allesUebernehmen()
        #expect(zaehler.stand == 1)
    }

    @Test("Abgebrochenes wird nicht mehr übernommen")
    func abgebrochen() {
        let zaehler = Zaehler()
        let entpreller = Entpreller()
        entpreller.nach(30_000) { zaehler.stand += 1 }
        entpreller.abbrechen()
        Entpreller.allesUebernehmen()
        #expect(zaehler.stand == 0)
    }
}

@Suite("Planungsspeicher")
@MainActor
struct SpeicherPruefungen {

    private func speicherMitPlanung() throws -> Planungsspeicher {
        let planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 6,
            basis: "/Users/lehrkraft/Unterricht",
            klassen: Standardkurse.aufbauen(Array(Standardkurse.liste.prefix(3))),
            fachfarben: [:])
        return Planungsspeicher(vorschau: planung)
    }

    // ── Sprung zur laufenden Woche ────────────────────────────────────────

    private func speicherAbHeute(_ verschiebung: Int) throws -> Planungsspeicher {
        let planung = Planung.leer(
            titel: "Sprung", start: Tag.heute.montagDerWoche.plus(tage: verschiebung * 7),
            wochen: 12, basis: "",
            klassen: Standardkurse.aufbauen(Array(Standardkurse.liste.prefix(2))),
            fachfarben: [:])
        return Planungsspeicher(vorschau: planung)
    }

    /// Auch die erste Spalte ist ein Ziel: Eine Untergrenze ließe den Sprung
    /// genau dann verpuffen, wenn heute in der ersten Woche liegt.
    @Test("Der Sprung trifft auch die erste Woche")
    func sprungAufWocheNull() throws {
        let speicher = try speicherAbHeute(0)
        #expect(speicher.planung?.laufendeWoche == 0)
        speicher.zurLaufendenWoche()
        #expect(speicher.sprung?.woche == 0)
    }

    @Test("Der Sprung trifft eine Woche mitten im Zeitraum")
    func sprungInDieMitte() throws {
        let speicher = try speicherAbHeute(-4)
        speicher.zurLaufendenWoche()
        #expect(speicher.sprung?.woche == 4)
    }

    /// Zweimal hintereinander muss zweimal springen — sonst bliebe das Raster
    /// stehen, wenn jemand wegrollt und den Knopf erneut drückt.
    @Test("Zweimal ausgelöst ist zweimal ein Sprung")
    func sprungWiederholt() throws {
        let speicher = try speicherAbHeute(-4)
        speicher.zurLaufendenWoche()
        let erster = try #require(speicher.sprung)
        speicher.zurLaufendenWoche()
        #expect(speicher.sprung != erster)
    }

    @Test("Liegt heute außerhalb des Zeitraums, sagt die App es")
    func sprungOhneLaufendeWoche() throws {
        let speicher = try speicherAbHeute(4)
        #expect(speicher.planung?.laufendeWoche == nil)
        speicher.zurLaufendenWoche()
        #expect(speicher.sprung == nil)
        #expect(speicher.meldungen.last?.text.contains("außerhalb des geplanten Zeitraums") == true)
    }

    @Test("Die Suche verknüpft alle Wörter und schaut in Material und Links")
    func suche() throws {
        let speicher = try speicherMitPlanung()
        let klasse = try #require(speicher.planung?.klassen.first)
        let vorhaben = Vorhaben(
            id: "e1", klasseId: klasse.id, woche: 0,
            titel: "Zellen unter dem Mikroskop", text: "Mikroskopieren und Zeichnen",
            erledigt: false,
            materialien: [Material(titel: "Arbeitsblatt", pfad: "Bio/AB-Zelle.pdf")],
            links: [Weblink(titel: "3ducation", adresse: "https://3ducation.org/")])

        speicher.suchbegriff = ""
        #expect(speicher.trifft(vorhaben, klasse: klasse))

        speicher.suchbegriff = "zellen mikroskop"
        #expect(speicher.trifft(vorhaben, klasse: klasse))

        speicher.suchbegriff = "zellen fahrrad"
        #expect(!speicher.trifft(vorhaben, klasse: klasse))

        speicher.suchbegriff = "ab-zelle.pdf"
        #expect(speicher.trifft(vorhaben, klasse: klasse))
        speicher.suchbegriff = "3ducation.org"
        #expect(speicher.trifft(vorhaben, klasse: klasse))

        speicher.suchbegriff = klasse.name.lowercased()
        #expect(speicher.trifft(vorhaben, klasse: klasse))
    }

    @Test("Das Löschen eines Kurses nimmt Vorhaben und freie Zellen mit")
    func kursEntfernen() throws {
        let speicher = try speicherMitPlanung()
        var planung = try #require(speicher.planung)
        let klasse = planung.klassen[0]
        let andere = planung.klassen[1]
        planung.eintraege = [
            Vorhaben(id: "a", klasseId: klasse.id, woche: 0, titel: "A", text: "",
                     erledigt: false, materialien: [], links: []),
            Vorhaben(id: "b", klasseId: andere.id, woche: 1, titel: "B", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        planung.zellenfrei = [
            FreieZelle(klasseId: klasse.id, woche: try #require(Tag(iso: "2026-08-10"))),
            FreieZelle(klasseId: andere.id, woche: try #require(Tag(iso: "2026-08-10"))),
        ]
        let neu = Planungsspeicher(vorschau: planung)

        neu.klasseEntfernen(klasse)
        #expect(neu.planung?.klassen.count == 3)
        try #require(neu.rueckfrage).handlung()

        #expect(neu.planung?.klassen.count == 2)
        #expect(neu.planung?.eintraege.map(\.id) == ["b"])
        #expect(neu.planung?.zellenfrei.count == 1)
    }

    @Test("Das Verkürzen des Zeitraums fragt nach und räumt danach auf")
    func zeitraumVerkuerzen() throws {
        let speicher = try speicherMitPlanung()
        var planung = try #require(speicher.planung)
        let klasse = planung.klassen[0]
        planung.eintraege = [
            Vorhaben(id: "drin", klasseId: klasse.id, woche: 1, titel: "drin", text: "",
                     erledigt: false, materialien: [], links: []),
            Vorhaben(id: "draussen", klasseId: klasse.id, woche: 5, titel: "draußen", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        planung.frei = [try #require(Tag(iso: "2026-09-07"))]   // Woche 4, fällt heraus
        let neu = Planungsspeicher(vorschau: planung)

        neu.einstellungenUebernehmen(start: try #require(Tag(iso: "2026-08-10")), wochen: 3,
                                     ersterSchultag: nil)
        #expect(neu.planung?.eintraege.count == 2)
        try #require(neu.rueckfrage).handlung()

        #expect(neu.planung?.wochen == 3)
        #expect(neu.planung?.eintraege.map(\.id) == ["drin"])
        // Die Markierung bleibt: Sie hängt am Montagsdatum, nicht am
        // Spaltenindex, und ist nach einem Verschieben des Starts wieder da.
        // Vorhaben liegen dagegen auf Spalten und können nicht mitwandern.
        #expect(neu.planung?.frei == [try #require(Tag(iso: "2026-09-07"))])
    }

    /// Wie die freien Wochen hängen die freien Zellen am Montagsdatum.
    @Test("Auch eine freie Zelle übersteht die Übernahme der Einstellungen")
    func freieZelleUeberlebtUebernahme() throws {
        let speicher = try speicherMitPlanung()
        var planung = try #require(speicher.planung)
        let klasse = planung.klassen[0].id
        let draussen = try #require(Tag(iso: "2026-09-07"))   // Woche 4, fällt heraus
        planung.zellenfrei = [FreieZelle(klasseId: klasse, woche: draussen)]
        let neu = Planungsspeicher(vorschau: planung)

        neu.einstellungenUebernehmen(start: try #require(Tag(iso: "2026-08-10")), wochen: 3,
                                     ersterSchultag: nil)
        if let frage = neu.rueckfrage { frage.handlung() }
        #expect(neu.planung?.zellenfrei == [FreieZelle(klasseId: klasse, woche: draussen)])
    }

    /// Was der Leser beim nächsten Start kürzte, soll gar nicht erst entstehen.
    @Test("Eine neue Planung kappt Titel, Klassenname und Fach")
    func neuePlanungKapptNamen() throws {
        let speicher = try speicherMitPlanung()
        let lang = String(repeating: "l", count: Planungsdatei.maxNamenslaenge + 200)
        speicher.neuePlanung(titel: lang, start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 4, basis: "",
                             klassen: Standardkurse.aufbauen([(name: lang, fach: lang)]),
                             ersterSchultag: nil, uebernahme: [])
        let p = try #require(speicher.planung)
        #expect(p.titel.count == Planungsdatei.maxNamenslaenge)
        #expect(p.klassen[0].name.count == Planungsdatei.maxNamenslaenge)
        #expect(p.klassen[0].fach.count == Planungsdatei.maxNamenslaenge)
        // Und was hier steht, übersteht das Schreiben und Lesen unverändert.
        let gelesen = try Planungsdatei.lesenMitBilanz(Planungsdatei.schreiben(p))
        #expect(gelesen.bilanz.gekuerzteTexte == 0)
        #expect(gelesen.planung.titel == p.titel)
    }

    @Test("Ein leerer Titel wird zum Ersatznamen des Lesers")
    func neuePlanungOhneTitel() throws {
        let speicher = try speicherMitPlanung()
        speicher.neuePlanung(titel: "   ", start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 4, basis: "", klassen: [], ersterSchultag: nil,
                             uebernahme: [])
        #expect(speicher.planung?.titel == "Unterrichtsplanung")
    }

    @Test("Nach dem Zurückschieben ist die Markierung wieder in Sicht")
    func freieWocheUeberlebtVerschieben() throws {
        let speicher = try speicherMitPlanung()
        var planung = try #require(speicher.planung)
        planung.frei = [try #require(Tag(iso: "2026-09-07"))]
        let neu = Planungsspeicher(vorschau: planung)

        // Eine Woche nach hinten: Der 07.09. fällt aus der Wochenliste …
        neu.einstellungenUebernehmen(start: try #require(Tag(iso: "2026-08-17")), wochen: 3,
                                     ersterSchultag: nil)
        if let frage = neu.rueckfrage { frage.handlung() }
        // … und nach dem Zurückschieben ist er wieder da.
        neu.einstellungenUebernehmen(start: try #require(Tag(iso: "2026-08-10")), wochen: 6,
                                     ersterSchultag: nil)
        if let frage = neu.rueckfrage { frage.handlung() }
        #expect(neu.planung?.frei == [try #require(Tag(iso: "2026-09-07"))])
    }

    @Test("Der erste Schultag lässt sich nachträglich setzen, ändern und entfernen")
    func ersterSchultagNachtraeglich() throws {
        let speicher = try speicherMitPlanung()
        let planung = try #require(speicher.planung)
        #expect(planung.ersterSchultag == nil)

        let tag = planung.start.plus(tage: 7 + 2)
        speicher.einstellungenUebernehmen(start: planung.start, wochen: planung.wochen,
                                          ersterSchultag: tag)
        #expect(speicher.planung?.ersterSchultag == tag)

        speicher.einstellungenUebernehmen(start: planung.start, wochen: planung.wochen,
                                          ersterSchultag: planung.start.plus(tage: 100 * 7))
        #expect(speicher.planung?.ersterSchultag == tag)

        speicher.einstellungenUebernehmen(start: planung.start, wochen: planung.wochen,
                                          ersterSchultag: nil)
        #expect(speicher.planung?.ersterSchultag == nil)
    }

    @Test("Eine Startverschiebung im Zeitraum verankert die Zählung neu")
    func startverschiebungMitAnker() throws {
        let speicher = try speicherMitPlanung()
        let planung = try #require(speicher.planung)
        let anker = planung.start.plus(tage: 7)   // Montag der Woche 1
        speicher.einstellungenUebernehmen(start: planung.start, wochen: planung.wochen,
                                          ersterSchultag: anker)

        // Der Start rückt vor; der Anker ist ein absoluter Tag und wandert eine Spalte.
        speicher.einstellungenUebernehmen(start: planung.start.plus(tage: -7),
                                          wochen: planung.wochen, ersterSchultag: anker)
        let p = try #require(speicher.planung)
        #expect(p.ersterSchultag == anker)
        #expect(p.schulwochen(p.wochenListe) == [nil, nil, 1, 2, 3, 4])
    }

    @Test("Eine Fachfarbe färbt alle Zeilen des Fachs nach — außer den von Hand gesetzten")
    func fachfarbe() throws {
        var planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("M1", "Mathematik"), ("M2", "Mathematik"),
                                             ("M3", "Mathematik")]),
            fachfarben: [:])
        let vonHand = try #require(Farbwelt.stelle("limette-hell"))
        planung.klassen[2].farbe = vonHand
        planung.klassen[2].farbeManuell = true
        let speicher = Planungsspeicher(vorschau: planung)

        speicher.fachfarbeSetzen(fach: "mathematik", ton: "rot-dunkel")

        let rot = try #require(Farbwelt.stelle("rot-dunkel"))
        #expect(speicher.planung?.klassen[0].farbe == rot)
        #expect(speicher.planung?.klassen[1].farbe == rot)
        #expect(speicher.planung?.klassen[2].farbe == vonHand)

        // Ohne Zuweisung behalten die Zeilen, was sie tragen — Grau gibt es nicht mehr.
        speicher.fachfarbeSetzen(fach: "mathematik", ton: nil)
        #expect(speicher.planung?.fachfarben["mathematik"] == nil)
        #expect(speicher.planung?.klassen[0].farbe == rot)
        #expect(speicher.planung?.klassen[2].farbe == vonHand)
    }

    @Test("Ein neues Fach bekommt beim Anlegen gleich eine eigene Farbe")
    func fachfarbeBeimAnlegen() throws {
        let planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: planung)
        let neu = try #require(speicher.klasseHinzufuegen())

        speicher.klasseAendern(id: neu, name: "R10", fach: "Englisch")

        let englisch = try #require(speicher.planung?.fachfarbe("Englisch"))
        #expect(Farbwelt.istGueltig(englisch), "eine Farbe der Palette")
        let kurs = try #require(speicher.planung?.klassen.first { $0.id == neu })
        #expect(kurs.farbe == englisch)

        let karte = try #require(speicher.planung?.fachfarbenWirksam())
        #expect(!karte.filter { $0.key != "englisch" }.values.contains(englisch))

        let zweite = try #require(speicher.klasseHinzufuegen())
        speicher.klasseAendern(id: zweite, name: "R9", fach: "Kunst")
        #expect(speicher.planung?.fachfarbe("Kunst") != englisch)
        #expect(speicher.planung?.fachfarben.isEmpty == true)
    }

    /// Das Fachfeld ist entprellt: Es meldet jeden Zwischenstand des Getippten.
    @Test("Halbgetipptes im Fachfeld hinterlässt kein Fach und lässt die Farbe stehen")
    func fachfeldEntprellt() throws {
        let planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("7a", "Deutsch")]), fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: planung)
        let neu = try #require(speicher.klasseHinzufuegen())
        let anfangs = try #require(speicher.planung?.klassen.first { $0.id == neu }?.farbe)

        for zwischenstand in ["M", "Ma", "Mat", "Mathe", "Mathematik"] {
            speicher.klasseAendern(id: neu, fach: zwischenstand)
        }

        let fertig = try #require(speicher.planung)
        #expect(fertig.klassen.first { $0.id == neu }?.farbe == anfangs, "die Farbe springt nicht")
        #expect(fertig.fachfarbenWirksam().keys.sorted() == ["deutsch", "mathematik"])
        #expect(fertig.fachfarben.isEmpty)
    }

    @Test("Wird das Fach geleert, behält die Zeile ihre Farbe")
    func fachGeleert() throws {
        let planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("7a", "Deutsch"), ("8b", "Deutsch")]),
            fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: planung)
        let erste = try #require(speicher.planung?.klassen[0].id)
        let deutsch = try #require(speicher.planung?.fachfarbe("Deutsch"))

        speicher.klasseAendern(id: erste, fach: "")

        let nachher = try #require(speicher.planung)
        #expect(nachher.klassen[0].fach.isEmpty)
        #expect(nachher.klassen[0].farbe == deutsch, "die Zeile sieht aus wie zuvor")
        #expect(nachher.fachfarbe("Deutsch") == deutsch, "die zweite Zeile trägt es weiter")
    }

    @Test("Ein Fach an einer von Hand gefärbten Zeile lässt deren Farbe unberührt")
    func fachAnHandfarbe() throws {
        let planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("7a", "Deutsch"), ("8b", "")]), fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: planung)
        let zweite = try #require(speicher.planung?.klassen[1].id)
        let vonHand = try #require(Farbwelt.stelle("magenta-dunkel"))
        speicher.farbeSetzen(klasse: zweite, farbe: vonHand)

        speicher.klasseAendern(id: zweite, fach: "Kunst")

        let nachher = try #require(speicher.planung)
        #expect(nachher.klassen[1].farbe == vonHand)
        #expect(nachher.klassen[1].farbeManuell)
        #expect(nachher.fachfarbe("Kunst") == nil, "von Hand bestimmt keine Fachfarbe")

        speicher.farbeDemFachFolgen(klasse: zweite)
        let zurueck = try #require(speicher.planung)
        #expect(!zurueck.klassen[1].farbeManuell)
        #expect(zurueck.fachfarbe("Kunst") == vonHand)
    }

    @Test("Wechselt die letzte Zeile eines Fachs, bleibt keine Farbe zurück")
    func keinRestNachFachwechsel() throws {
        let planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("7a", "Deutsch"), ("8b", "Deutsch"),
                                             ("9c", "Physik")]),
            fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: planung)
        let einzige = try #require(speicher.planung?.klassen[2].id)

        speicher.klasseAendern(id: einzige, fach: "Chemie")

        let nachher = try #require(speicher.planung)
        #expect(nachher.fachfarbenWirksam().keys.sorted() == ["chemie", "deutsch"])
        #expect(nachher.farbnutzung.count == 2, "Physik gibt seine Farbe frei")
    }

    @Test("Ein Fach lässt sich nicht auf ein schon vorhandenes umbenennen")
    func umbenennenAufVorhandenes() throws {
        let planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("7a", "Mathematik"), ("8b", "Mathematik")]),
            fachfarben: ["kunst": "violett-dunkel"])
        let speicher = Planungsspeicher(vorschau: planung)
        let mathe = try #require(speicher.planung?.fachfarbe("Mathematik"))

        speicher.fachUmbenennen(von: "kunst", nach: "Mathematik")

        let nachher = try #require(speicher.planung)
        #expect(nachher.fachfarben["kunst"] == "violett-dunkel", "abgewiesen")
        #expect(nachher.fachfarben["mathematik"] == nil)
        #expect(nachher.fachfarbe("Mathematik") == mathe, "die Zeilen bleiben, wie sie sind")
    }

    @Test("Ein Fach ohne Klasse und Kurs lässt sich umbenennen und wieder entfernen")
    func fachVormerken() throws {
        let planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen([("M1", "Mathematik")]), fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: planung)

        speicher.fachfarbeSetzen(fach: "kunst", ton: "magenta-mittel")
        #expect(speicher.planung?.fachfarben["kunst"] == "magenta-mittel")

        speicher.fachUmbenennen(von: "kunst", nach: "Werken")
        #expect(speicher.planung?.fachfarben["kunst"] == nil)
        #expect(speicher.planung?.fachfarben["werken"] == "magenta-mittel")

        speicher.fachfarbeSetzen(fach: "mathematik", ton: "rot-mittel")
        speicher.fachUmbenennen(von: "mathematik", nach: "Mathe")
        #expect(speicher.planung?.klassen[0].fach == "Mathe")
        #expect(speicher.planung?.fachfarben["mathe"] == "rot-mittel")

        speicher.fachEntfernen("mathe")
        #expect(speicher.planung?.fachfarben["mathe"] == "rot-mittel",
                "Fach mit Klasse/Kurs bleibt stehen")
        speicher.fachEntfernen("werken")
        #expect(speicher.planung?.fachfarben["werken"] == nil)
    }

    @Test("Die Standardliste ergänzen fügt nur Fehlendes hinzu")
    func standardkurseErgaenzen() throws {
        let planung = Planung.leer(
            titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
            klassen: Standardkurse.aufbauen(Array(Standardkurse.liste.prefix(3))),
            fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: planung)

        speicher.standardkurseErgaenzen()
        #expect(speicher.planung?.klassen.count == Standardkurse.liste.count)

        speicher.standardkurseErgaenzen()
        #expect(speicher.planung?.klassen.count == Standardkurse.liste.count)
    }

    @Test("Ein Vorhaben verschiebt sich nur in eine andere Zelle")
    func verschieben() throws {
        let speicher = try speicherMitPlanung()
        var planung = try #require(speicher.planung)
        let a = planung.klassen[0], b = planung.klassen[1]
        planung.eintraege = [Vorhaben(id: "e", klasseId: a.id, woche: 1, titel: "E", text: "",
                                      erledigt: false, materialien: [], links: [],
                                      datum: Tag(iso: "2026-08-19"))]
        let neu = Planungsspeicher(vorschau: planung)
        let vorher = try #require(neu.planung?.geaendert)

        neu.vorhabenVerschieben("e", klasse: a.id, woche: 1)
        #expect(neu.planung?.geaendert == vorher)

        // Andere Zeile, dieselbe Woche: Das Datum bleibt.
        neu.vorhabenVerschieben("e", klasse: b.id, woche: 1)
        #expect(neu.planung?.eintraege[0].klasseId == b.id)
        #expect(neu.planung?.eintraege[0].datum == Tag(iso: "2026-08-19"))
        #expect(neu.meldungen.isEmpty)

        // Andere Woche: Wochentag und Datum verfallen, die Meldung sagt es.
        neu.vorhabenVerschieben("e", klasse: b.id, woche: 3)
        #expect(neu.planung?.eintraege[0].woche == 3)
        #expect(neu.planung?.eintraege[0].datum == nil)
        #expect(neu.planung?.eintraege[0].wochentag == nil)
        #expect(neu.meldungen.last?.text == Planungsspeicher.zurueckgesetzt(1))

        neu.vorhabenVerschieben("gibtsnicht", klasse: a.id, woche: 0)
        #expect(neu.planung?.eintraege[0].klasseId == b.id)
    }

    /// Die Unterrichtstage einer Zeile
    /// sind eine Angabe über den Stundenplan, keine über die Vorhaben.
    @Test("Unterrichtstage lassen sich je Zeile ankreuzen, ohne ein Vorhaben zu berühren")
    func unterrichtstage() throws {
        let speicher = try speicherMitPlanung()
        var planung = try #require(speicher.planung)
        let a = planung.klassen[0]
        planung.eintraege = [Vorhaben(id: "e", klasseId: a.id, woche: 1, titel: "E", text: "",
                                      erledigt: false, materialien: [], links: [],
                                      datum: Tag(iso: "2026-08-19"))]
        let neu = Planungsspeicher(vorschau: planung)
        #expect(neu.planung?.klassen[0].unterrichtstage.isEmpty == true)

        neu.unterrichtstagSetzen(klasse: a.id, tag: .mittwoch, an: true)
        neu.unterrichtstagSetzen(klasse: a.id, tag: .montag, an: true)
        #expect(neu.planung?.klassen[0].unterrichtstage == [.montag, .mittwoch])

        // Ein Klick, der nichts ändert, schreibt nichts.
        let stand = try #require(neu.planung)
        neu.unterrichtstagSetzen(klasse: a.id, tag: .montag, an: true)
        neu.unterrichtstagSetzen(klasse: a.id, tag: .freitag, an: false)
        #expect(neu.planung == stand)

        neu.unterrichtstagSetzen(klasse: a.id, tag: .mittwoch, an: false)
        #expect(neu.planung?.klassen[0].unterrichtstage == [.montag])

        // Das Vorhaben behält Datum und Wochentag — der Mittwoch ist kein
        // Unterrichtstag mehr, das Vorhaben findet trotzdem an ihm statt.
        #expect(neu.planung?.eintraege[0].datum == Tag(iso: "2026-08-19"))
        #expect(neu.planung?.eintraege[0].wochentag == .mittwoch)
        #expect(neu.meldungen.isEmpty)

        neu.unterrichtstagSetzen(klasse: "gibtsnicht", tag: .montag, an: true)
        #expect(neu.planung?.klassen.map(\.unterrichtstage) == [[.montag], [], []])
    }

    @Test("Freie Wochen und freie Zellen lassen sich umschalten")
    func freiSchalten() throws {
        let speicher = try speicherMitPlanung()
        let woche = try #require(speicher.planung?.wochenListe[2])
        let klasse = try #require(speicher.planung?.klassen.first)

        speicher.wocheFreiSchalten(woche)
        #expect(speicher.planung?.frei.contains(woche.montag) == true)
        #expect(speicher.planung?.lage(woche).frei == true)
        speicher.wocheFreiSchalten(woche)
        #expect(speicher.planung?.frei.isEmpty == true)

        speicher.zelleFreiSchalten(klasse: klasse.id, woche: woche)
        #expect(speicher.planung?.istZelleFrei(klasse: klasse.id, woche: woche) == true)
        speicher.zelleFreiSchalten(klasse: klasse.id, woche: woche)
        #expect(speicher.planung?.zellenfrei.isEmpty == true)
    }
}
