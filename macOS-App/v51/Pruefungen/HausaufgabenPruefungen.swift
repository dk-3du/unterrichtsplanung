// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

private typealias Tag = Unterrichtsplanung.Tag

// ── Hausaufgaben (v47) ────────────────────────────────────────────────────
//
// Schalter und Zeile je Vorhaben — dieselbe Datei liest die Ansicht; die
// Fälle zum Lesen stehen deshalb auch in `leser_pruefen.py`.

@Suite("Hausaufgaben")
@MainActor
struct HausaufgabenPruefungen {

    private func planung() throws -> Planung {
        var planung = Planung.leer(
            titel: "Hausaufgaben", start: try #require(Tag(iso: "2026-08-10")), wochen: 8,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let a = planung.klassen[0].id
        planung.eintraege = [
            Vorhaben(id: "e1", klasseId: a, woche: 0, titel: "Brüche", text: "",
                     erledigt: false, materialien: [], links: [],
                     hausaufgabe: true, hausaufgabenText: "S. 42, Nr. 3–5"),
            Vorhaben(id: "e2", klasseId: a, woche: 0, titel: "Ohne", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        return planung
    }

    private func eintrag(_ speicher: Planungsspeicher, _ id: String) throws -> Vorhaben {
        try #require(speicher.planung?.eintraege.first { $0.id == id })
    }

    @Test("Schalter und Zeile überstehen Schreiben und Lesen; ohne sie bleibt beides leer")
    func hinUndZurueck() throws {
        let daten = try Planungsdatei.schreiben(try planung())
        let gelesen = try Planungsdatei.lesen(daten)
        #expect(gelesen.eintraege[0].hausaufgabe)
        #expect(gelesen.eintraege[0].hausaufgabenText == "S. 42, Nr. 3–5")
        #expect(!gelesen.eintraege[1].hausaufgabe)
        #expect(gelesen.eintraege[1].hausaufgabenText.isEmpty)
        // Genau diese Schlüssel liest die Ansicht.
        let roh = try #require(try JSONSerialization.jsonObject(with: daten) as? [String: Any])
        let eintraege = try #require(roh["eintraege"] as? [[String: Any]])
        #expect(eintraege[0]["hausaufgabe"] as? Bool == true)
        #expect(eintraege[0]["hausaufgabenText"] as? String == "S. 42, Nr. 3–5")
        #expect(eintraege[1]["hausaufgabe"] as? Bool == false)
    }

    @Test("Eine Datei ohne die Felder liest sich wie bisher")
    func ohneFelder() throws {
        let roh = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","wochen":4,"#
            + #""klassen":[{"id":"k1","name":"5a"}],"#
            + #""eintraege":[{"id":"e1","klasseId":"k1","woche":0,"titel":"T"}]}"#
        let (gelesen, bilanz) = try Planungsdatei.lesenMitBilanz(Data(roh.utf8))
        #expect(!gelesen.eintraege[0].hausaufgabe)
        #expect(gelesen.eintraege[0].hausaufgabenText.isEmpty)
        #expect(bilanz.istLeer)
    }

    @Test("Die Zeile misst sich am Titelmaß, der Schalter gilt wie jeder Wahrheitswert — wie in der Ansichtsfassung")
    func grenzenBeiderFassungen() throws {
        let lang = String(repeating: "h", count: Planungsdatei.maxNamenslaenge + 100)
        let roh = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","wochen":4,"#
            + #""klassen":[{"id":"k1","name":"5a"}],"eintraege":["#
            + #"{"id":"e1","klasseId":"k1","woche":0,"titel":"T","hausaufgabe":1,"hausaufgabenText":"\#(lang)"},"#
            + #"{"id":"e2","klasseId":"k1","woche":0,"titel":"T","hausaufgabe":0,"hausaufgabenText":"Heft"},"#
            + #"{"id":"e3","klasseId":"k1","woche":0,"titel":"T","hausaufgabe":"x","hausaufgabenText":"S.\u00071"}]}"#
        let (gelesen, bilanz) = try Planungsdatei.lesenMitBilanz(Data(roh.utf8))
        #expect(gelesen.eintraege[0].hausaufgabe, "1 gilt wie jede Zahl außer 0")
        #expect(gelesen.eintraege[0].hausaufgabenText.count == Planungsdatei.maxNamenslaenge)
        #expect(bilanz.gekuerzteTexte == 1)
        // Ohne Schalter bleibt die Zeile beim Lesen stehen — die App schreibt sie so nie.
        #expect(!gelesen.eintraege[1].hausaufgabe)
        #expect(gelesen.eintraege[1].hausaufgabenText == "Heft")
        #expect(gelesen.eintraege[2].hausaufgabe, "eine nichtleere Zeichenkette gilt")
        #expect(gelesen.eintraege[2].hausaufgabenText == "S.1", "Steuerzeichen fallen weg")
    }

    @Test("Übernehmen ohne Schalter leert die Zeile; mit Schalter wird sie eine Zeile und gekappt")
    func uebernehmen() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        var entwurf = VorhabenEntwurf(try eintrag(speicher, "e1"))
        entwurf.hausaufgabe = false
        speicher.vorhabenSichern(entwurf)
        var e1 = try eintrag(speicher, "e1")
        #expect(!e1.hausaufgabe)
        #expect(e1.hausaufgabenText.isEmpty, "die Zeile gilt nur mit Schalter")

        entwurf = VorhabenEntwurf(e1)
        entwurf.hausaufgabe = true
        entwurf.hausaufgabenText = "  S. 42,\nNr. 3–5 \r\n\n"
        speicher.vorhabenSichern(entwurf)
        e1 = try eintrag(speicher, "e1")
        #expect(e1.hausaufgabe)
        #expect(e1.hausaufgabenText == "S. 42, Nr. 3–5", "ein eingesetzter Absatz wird eine Zeile")

        entwurf = VorhabenEntwurf(e1)
        entwurf.hausaufgabenText = String(repeating: "x", count: Planungsdatei.maxNamenslaenge + 5)
        speicher.vorhabenSichern(entwurf)
        e1 = try eintrag(speicher, "e1")
        #expect(e1.hausaufgabenText.count == Planungsdatei.maxNamenslaenge)
        #expect(speicher.meldungen.last?.text.contains("Hausaufgabe") == true, "gekürzt wird mit Meldung")
    }

    @Test("Hinzufügen und Entfernen aus dem Rechtsklickmenü — Entfernen nimmt die Zeile mit")
    func umschalten() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.hausaufgabeUmschalten("e2")
        #expect(try eintrag(speicher, "e2").hausaufgabe)
        speicher.hausaufgabeUmschalten("e1")
        let e1 = try eintrag(speicher, "e1")
        #expect(!e1.hausaufgabe)
        #expect(e1.hausaufgabenText.isEmpty)
        speicher.hausaufgabeUmschalten("gibt-es-nicht")
        #expect(speicher.planung?.eintraege.count == 2)
    }

    @Test("Der Entwurf merkt Schalter und Zeile — die Escape-Rückfrage hängt daran")
    func entwurf() throws {
        let vorhaben = try planung().eintraege[0]
        var entwurf = VorhabenEntwurf(vorhaben)
        #expect(!entwurf.veraendert)
        entwurf.hausaufgabenText = "S. 43"
        #expect(entwurf.veraendert)
        entwurf = VorhabenEntwurf(vorhaben)
        entwurf.hausaufgabe = false
        #expect(entwurf.veraendert)
        let neu = VorhabenEntwurf(klasseId: vorhaben.klasseId, woche: 0)
        #expect(!neu.hausaufgabe)
        #expect(neu.hausaufgabenText.isEmpty)
    }

    @Test("Ein Wortlaut für Tagesliste, Bedienungshilfen, Ansicht und Papier")
    func beschriftung() throws {
        let mit = try planung().eintraege[0]
        #expect(mit.hausaufgabenBeschriftung == "Hausaufgabe: S. 42, Nr. 3–5")
        #expect(mit.hausaufgabenDruckmarke == "Hausaufgabe · S. 42, Nr. 3–5")
        var ohne = mit
        ohne.hausaufgabenText = ""
        #expect(ohne.hausaufgabenBeschriftung == "Hausaufgabe")
        #expect(ohne.hausaufgabenDruckmarke == "Hausaufgabe")
        #expect(Planungsspeicher.einzeilig("a\n\n b \r\nc") == "a b c")
        #expect(Planungsspeicher.einzeilig("") == "")
    }

    @Test("Die Suche findet die Zeile")
    func suche() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let klasse = try #require(speicher.planung?.klassen.first)
        let e1 = try eintrag(speicher, "e1")
        speicher.suchbegriff = "nr. 3–5"
        #expect(speicher.trifft(e1, klasse: klasse))
        speicher.suchbegriff = "nr. 7"
        #expect(!speicher.trifft(e1, klasse: klasse))
    }

    @Test("In eine neue Planung übernommen bleibt die Hausaufgabe — sie ist Inhalt, kein Verlauf")
    func uebernommen() throws {
        let neu = try planung().eintraege[0].uebernommen(klasseId: "k9", woche: 3, basis: "")
        #expect(neu.hausaufgabe)
        #expect(neu.hausaufgabenText == "S. 42, Nr. 3–5")
        #expect(neu.kommentar.isEmpty)
        #expect(!neu.erledigt)
    }

    @Test("Das Zeichen nimmt dem Titel Breite, keine Höhe")
    func zellenmass() throws {
        var kurz = try planung().eintraege[0]
        kurz.titel = "Brüche"
        var ohne = kurz
        ohne.hausaufgabe = false
        ohne.hausaufgabenText = ""
        let breite: CGFloat = 280
        #expect(Zellenmass.kachelhoehe(kurz, breite: breite) == Zellenmass.kachelhoehe(ohne, breite: breite))
        #expect(Zellenmass.titelbreite(innen: 200, hausaufgabe: true)
                == Zellenmass.titelbreite(innen: 200, hausaufgabe: false) - Zellenmass.breiteHausaufgabe)
        // Ein langer Titel bricht mit dem Zeichen früher um — nie später.
        var lang = kurz
        lang.titel = String(repeating: "Bruchrechnen ", count: 6)
        var langOhne = lang
        langOhne.hausaufgabe = false
        #expect(Zellenmass.kachelhoehe(lang, breite: breite)
                >= Zellenmass.kachelhoehe(langOhne, breite: breite))
    }
}
