// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Das Merkmal „Korrektur“ am Vorhaben: gehandhabt wie die Dringlichkeit —
/// ein Schalter, kein Pflichtdatum —, im Bezug zur Prüfung, aber nie zugleich
/// mit ihr: Ein Vorhaben ist entweder Prüfung oder Korrektur.
@Suite("Merkmal Korrektur: Datei, Speicher, Rücknahme")
@MainActor
struct KorrekturmerkmalPruefungen {
    private func speicher() throws -> Planungsspeicher {
        var planung = Planung.leer(titel: "Korrektur", start: try #require(Tag(iso: "2026-08-10")),
                                   wochen: 6, basis: "",
                                   klassen: Standardkurse.aufbauen([("G8b", "Chemie")]),
                                   fachfarben: [:])
        let klasse = try #require(planung.klassen.first?.id)
        planung.eintraege = [
            Vorhaben(id: "arbeit", klasseId: klasse, woche: 1, titel: "Klassenarbeit 1", text: "", erledigt: false,
                     materialien: [], links: [], pruefung: true, pruefungstag: Tag(iso: "2026-08-19")),
            Vorhaben(id: "korrektur", klasseId: klasse, woche: 2, titel: "Klassenarbeit 1 korrigieren", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        return Planungsspeicher(vorschau: planung)
    }

    private func eintrag(_ s: Planungsspeicher, _ id: String) throws -> Vorhaben {
        try #require(s.planung?.eintraege.first { $0.id == id })
    }

    // ── Datei ─────────────────────────────────────────────────────────────

    private func datei(_ eintrag: String) -> Data {
        Data("""
            {"typ": "unterrichtsplanung", "version": 2, "titel": "K", "start": "2026-08-10", "wochen": 4, "basis": "",
             "klassen": [{"id": "k1", "name": "G8b", "fach": "Chemie", "farbe": 1}],
             "eintraege": [\(eintrag)]}
            """.utf8)
    }

    @Test("Lesen: fehlt das Feld, ist es falsch; gesetzt wird es gelesen wie die Dringlichkeit")
    func lesen() throws {
        func korrektur(_ felder: String) throws -> Bool {
            let p = try Planungsdatei.lesen(datei(#"{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "t"\#(felder)}"#))
            return try #require(p.eintraege.first).korrektur
        }
        #expect(try !korrektur(""), "eine Datei von früher")
        #expect(try korrektur(#", "korrektur": true"#))
        #expect(try !korrektur(#", "korrektur": false"#))
        #expect(try korrektur(#", "korrektur": 1"#) && korrektur(#", "korrektur": "ja""#), "Fremdwerte wie bei dringend")
        #expect(try !korrektur(#", "korrektur": 0"#) && !korrektur(#", "korrektur": """#) && !korrektur(#", "korrektur": null"#))
        #expect(try korrektur(#", "korrektur": true, "datum": "2026-08-12", "dringend": true"#), "mit Datum und dringlich")
    }

    @Test("Lesen: Prüfung und Korrektur zugleich — die Prüfung gilt, die Korrektur fällt")
    func lesenBeides() throws {
        let p = try Planungsdatei.lesen(datei(
            #"{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "t", "pruefung": true, "pruefungstag": "2026-08-12", "korrektur": true}"#))
        let e = try #require(p.eintraege.first)
        #expect(e.pruefung && e.pruefungstag == Tag(iso: "2026-08-12"))
        #expect(!e.korrektur)
    }

    @Test("Schreiben und wieder lesen: das Feld steht in der Datei, die Fassung des Formats bleibt")
    func rundreise() throws {
        let s = try speicher()
        s.korrekturUmschalten("korrektur")
        let planung = try #require(s.planung)
        let objekt = Planungsdatei.alsObjekt(planung)
        let eintraege = try #require(objekt["eintraege"] as? [[String: Any]])
        #expect(eintraege.map { $0["korrektur"] as? Bool } == [false, true])
        #expect(objekt["version"] as? Int == Kennwerte.dateiVersion && Kennwerte.dateiVersion == 2)
        let gelesen = try Planungsdatei.lesen(try Planungsdatei.schreiben(planung))
        #expect(gelesen.eintraege.map(\.korrektur) == [false, true])
        #expect(gelesen.eintraege.map(\.pruefung) == [true, false])
    }

    // ── Speicher ──────────────────────────────────────────────────────────

    @Test("Umschalten: ein Schritt hin, ein Schritt zurück — ohne Datum, mit Datum, neben dringlich")
    func umschalten() throws {
        let s = try speicher()
        s.korrekturUmschalten("korrektur")
        #expect(try eintrag(s, "korrektur").korrektur)
        #expect(try eintrag(s, "korrektur").datum == nil, "ein Datum braucht sie nicht zwingend")
        #expect(s.widerrufenTitel.contains(Schrittname.alsKorrekturKennzeichnen))
        s.dringlichUmschalten("korrektur")
        #expect(try eintrag(s, "korrektur").korrektur && eintrag(s, "korrektur").dringend, "beides zugleich geht")
        s.korrekturUmschalten("korrektur")
        #expect(try !eintrag(s, "korrektur").korrektur && eintrag(s, "korrektur").dringend)
        #expect(s.widerrufenTitel.contains(Schrittname.korrekturEntfernen))
        s.widerrufen()
        #expect(try eintrag(s, "korrektur").korrektur)
    }

    @Test("Entweder Prüfung oder Korrektur: Der Schalter des einen wirkt am anderen nicht")
    func entwederOder() throws {
        let s = try speicher()
        let vorher = s.planung
        s.korrekturUmschalten("arbeit")
        #expect(s.planung == vorher, "an einer Prüfung ändert sich nichts — auch kein Termin")
        #expect(try eintrag(s, "arbeit").pruefungstag == Tag(iso: "2026-08-19"))
        s.korrekturUmschalten("korrektur")
        let alsKorrektur = s.planung
        s.pruefungUmschalten("korrektur")
        #expect(s.planung == alsKorrektur, "an einer Korrektur wird keine Prüfung")
        #expect(try !eintrag(s, "korrektur").pruefung && eintrag(s, "korrektur").korrektur)
    }

    @Test("Der Dialog sichert das Merkmal — und die Schranke davor hält die Regel")
    func dialog() throws {
        let s = try speicher()
        var entwurf = VorhabenEntwurf(try eintrag(s, "korrektur"))
        #expect(!entwurf.korrektur)
        entwurf.korrektur = true
        s.vorhabenSichern(entwurf)
        #expect(try eintrag(s, "korrektur").korrektur)
        #expect(VorhabenEntwurf(try eintrag(s, "korrektur")).korrektur, "der Entwurf liest es zurück")
        // Am Dialog vorbei: beides gesetzt — die Prüfung gilt.
        var beides = VorhabenEntwurf(try eintrag(s, "arbeit"))
        beides.korrektur = true
        s.vorhabenSichern(beides)
        #expect(try eintrag(s, "arbeit").pruefung && !eintrag(s, "arbeit").korrektur)
        // Ein neues Vorhaben als Korrektur.
        var neu = VorhabenEntwurf(klasseId: try eintrag(s, "arbeit").klasseId, woche: 3)
        neu.titel = "Test korrigieren"
        neu.korrektur = true
        s.vorhabenSichern(neu)
        #expect(s.planung?.eintraege.last?.korrektur == true)
    }

    // ── Raster ────────────────────────────────────────────────────────────

    @Test("Die Kachel: eine Zeile „Korrektur“ am Platz der Prüfungszeile — gleich hoch, kein Pflichtdatum")
    func kachel() throws {
        let s = try speicher()
        s.korrekturUmschalten("korrektur")
        let planung = try #require(s.planung)
        let daten = Rasterdaten(planung, stand: 1, breite: 280)
        let korrektur = try #require(daten.kacheln(zeile: 0, woche: 2).first)
        let pruefung = try #require(daten.kacheln(zeile: 0, woche: 1).first)
        #expect(korrektur.istKorrektur && !korrektur.istPruefung)
        #expect(korrektur.gesetzteKorrektur?.string == "Korrektur")
        #expect(korrektur.gesetztePruefung == nil && pruefung.gesetzteKorrektur == nil)
        #expect(pruefung.gesetztePruefung?.string.hasPrefix("Prüfung · ") == true)
        // Dieselbe Zeile, dieselbe Höhe: gleicher Titelumfang, also gleiche Kachelhöhe.
        var gleich = try eintrag(s, "korrektur")
        gleich.titel = try eintrag(s, "arbeit").titel
        #expect(Zellenmass.kachelhoehe(gleich, breite: 280) == Zellenmass.kachelhoehe(try eintrag(s, "arbeit"), breite: 280))
        var ohne = gleich
        ohne.korrektur = false
        #expect(Zellenmass.kachelhoehe(gleich, breite: 280) > Zellenmass.kachelhoehe(ohne, breite: 280))

        let ansicht = Kachelansicht(frame: .zero)
        ansicht.setzen(korrektur, ton: Farbwelt.ton(planung.klassen[0].farbe), angewaehlt: false, griffe: .init())
        #expect(ansicht.accessibilityLabel()?.contains(", Korrektur") == true)
        #expect(ansicht.accessibilityLabel()?.contains("Prüfung") == false)
    }

    @Test("Rechtsklick: drei Schalter in der Reihenfolge des Vorhaben-Blatts — und der jeweils andere ist gesperrt")
    func rechtsklick() throws {
        let s = try speicher()
        func zeilen(_ id: String) throws -> [Rasterkoordinator.Merkmalzeile] {
            Rasterkoordinator.merkmalzeilen(try eintrag(s, id))
        }
        // Wie im Vorhaben-Blatt von oben nach unten: dringlich, Korrektur, Prüfung.
        #expect(try zeilen("korrektur").map(\.aus) == ["Als dringlich kennzeichnen", "Als Korrektur kennzeichnen", "Als Prüfung führen"])
        #expect(try zeilen("korrektur").map(\.merkmal) == [.dringlich, .korrektur, .pruefung])
        #expect(try zeilen("korrektur").map(\.ein) == ["Nicht mehr als dringlich führen", "Nicht mehr als Korrektur führen",
                                                       "Nicht mehr als Prüfung führen"])
        #expect(try zeilen("korrektur").allSatisfy { !$0.gesperrt && !$0.gesetzt }, "ein gewöhnliches Vorhaben: alles frei")
        #expect(try zeilen("arbeit").map(\.gesperrt) == [false, true, false], "an der Prüfung ist die Korrektur gesperrt")
        s.korrekturUmschalten("korrektur")
        #expect(try zeilen("korrektur").map(\.gesperrt) == [false, false, true], "an der Korrektur ist die Prüfung gesperrt")
        #expect(try zeilen("korrektur").map(\.gesetzt) == [false, true, false])
    }

    @Test("Kopieren: Die Korrektur bleibt wie die Prüfung, die Dringlichkeit fällt")
    func kopie() throws {
        let s = try speicher()
        s.korrekturUmschalten("korrektur")
        s.dringlichUmschalten("korrektur")
        let kopie = try eintrag(s, "korrektur").uebernommen(klasseId: "neu", woche: 0, basis: "")
        #expect(kopie.korrektur && !kopie.dringend)
    }
}
