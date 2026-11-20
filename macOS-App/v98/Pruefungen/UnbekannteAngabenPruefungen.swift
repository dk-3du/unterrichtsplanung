// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unbekannte Angaben an Vorhaben (v93, E1079): Trägt ein Vorhaben Angaben, die diese Fassung nicht kennt — etwa aus
/// einer neueren —, meldet das Öffnen, wie viele Vorhaben betroffen sind; beim nächsten Sichern gehen sie verloren.
/// Eine Datei aus 2.6.1 oder 2.7.0 meldet nichts, auch nicht mit dem Altnamen `beschreibung`.
@Suite("Unbekannte Angaben an Vorhaben")
@MainActor
struct UnbekannteAngabenPruefungen {
    private func datei(_ eintraege: String, oben: String = "", zeile: String = "") -> Data {
        Data("""
            {"typ": "unterrichtsplanung", "version": 2, "titel": "U", "start": "2026-08-10", "wochen": 4, "basis": ""\(oben),
             "klassen": [{"id": "k1", "name": "G8b", "fach": "Chemie", "farbe": 1\(zeile)}],
             "eintraege": [\(eintraege)]}
            """.utf8)
    }

    private static func satz(_ anzahl: Int) -> String {
        " Die Datei enthält Angaben einer neueren Fassung, die diese Fassung nicht kennt (\(anzahl) Vorhaben); "
            + "die App führt sie nicht weiter."
    }

    @Test("Eine Datei aus 2.6.1 und 2.7.0 meldet nichts — alle Angaben bekannt, auch der Altname „beschreibung“")
    func bekannt() throws {
        let alle = #"""
            {"id": "e1", "klasseId": "k1", "woche": 0, "titel": "t", "text": "", "erledigt": false, "materialien": [],
             "links": [], "pruefung": false, "pruefungstag": "", "datum": "2026-08-12", "dringend": true,
             "korrektur": false, "vorbereitung": true, "kommentar": "", "statusGeaendert": "", "hausaufgabe": false,
             "hausaufgabenText": "", "termin": "m-1", "terminzeit": "07:45", "beschreibung": "alt"}
            """#
        let (p, bilanz) = try Planungsdatei.lesenMitBilanz(datei(alle))
        #expect(p.eintraege.count == 1)
        #expect(bilanz.unbekannteAngaben == 0 && bilanz.istLeer)
        #expect(Planungsspeicher.verlusttext(bilanz) == "")
    }

    @Test("Was der Schreiber schreibt, kennt der Leser — sonst meldete jede eigene Datei")
    func schreiberBekannt() throws {
        var p = Planung.leer(titel: "U", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
                             klassen: Standardkurse.aufbauen([("G8b", "Chemie")]), fachfarben: [:])
        let klasse = try #require(p.klassen.first?.id)
        var e = Vorhaben(id: "e1", klasseId: klasse, woche: 0, titel: "t", text: "x", erledigt: true,
                         materialien: [], links: [])
        e.datum = Tag(iso: "2026-08-12")
        e.dringend = true
        e.vorbereitung = true
        e.termin = "m-1"
        e.terminzeit = "07:45"
        e.hausaufgabe = true
        e.hausaufgabenText = "S. 4"
        e.kommentar = "k"
        p.eintraege = [e]
        let eintraege = try #require(Planungsdatei.alsObjekt(p)["eintraege"] as? [[String: Any]])
        let geschrieben = Set(eintraege.flatMap(\.keys))
        let fremd = geschrieben.subtracting(Planungsdatei.bekannteVorhabenschluessel).sorted()
        #expect(fremd.isEmpty, Comment(rawValue: "geschrieben, aber nicht bekannt: \(fremd)"))
        #expect(geschrieben.count == 20, "alle Angaben eines Vorhabens, Termin und Vorbereitung eingeschlossen")
        let (_, bilanz) = try Planungsdatei.lesenMitBilanz(try Planungsdatei.schreiben(p))
        #expect(bilanz.unbekannteAngaben == 0)
    }

    @Test("Unbekannte Angaben an drei Vorhaben: je Vorhaben einmal gezählt, gemeldet mit dem Satz zum Sichern")
    func gemeldet() throws {
        let (p, bilanz) = try Planungsdatei.lesenMitBilanz(datei(#"""
            {"id": "e1", "klasseId": "k1", "woche": 0, "titel": "a", "zukunft": 1},
            {"id": "e2", "klasseId": "k1", "woche": 0, "titel": "b", "zukunft": true, "farbe": "rot"},
            {"id": "e3", "klasseId": "k1", "woche": 1, "titel": "c", "__proto__": {}},
            {"id": "e4", "klasseId": "k1", "woche": 1, "titel": "d", "beschreibung": "alt"}
            """#))
        #expect(p.eintraege.count == 4, "die Vorhaben selbst bleiben")
        #expect(bilanz.unbekannteAngaben == 3 && !bilanz.istLeer)
        #expect(bilanz.verworfenes.isEmpty && bilanz.hinweise.isEmpty, "nichts verworfen, nichts gekürzt")
        #expect(Planungsspeicher.verlusttext(bilanz) == "", "nichts übergangen")
        #expect(Planungsspeicher.unbekannteAngabenText(bilanz.unbekannteAngaben, .geoeffnet) == Self.satz(3))
    }

    @Test("Gerettet bei gesperrter Ablage (H3-03, R-BE8-03): Die Meldung an der Aufrufstelle sagt „gehen beim nächsten Sichern verloren“")
    func rettungGesperrt() throws {
        let (gelesen, bilanz) = try Planungsdatei.lesenMitBilanz(datei(#"""
            {"id": "e1", "klasseId": "k1", "woche": 0, "titel": "a", "zukunft": 1}
            """#))
        let s = Planungsspeicher(vorschau: gelesen)
        try #require(s.sicherung.gesperrt, "Vorschau: die Ablage ist gesperrt")
        s.vorigeRettung(gelesen, bilanz: bilanz, grund: "Probe")
        #expect(s.sicherung.gesperrt, "noch gesperrt — nichts geschrieben")
        let text = s.meldungen.map(\.text).last ?? ""
        #expect(text.hasSuffix(" Die geladene Fassung enthält Angaben einer neueren Fassung, die diese Fassung nicht kennt "
                               + "(1 Vorhaben); sie gehen beim nächsten Sichern verloren."), Comment(rawValue: text))
    }

    @Test("Der Satz je Fundort (Z-BE4-R01, -R02, H3-03): geöffnet, Autosicherung, schon gesichert, geladen — leer bei keiner")
    func fundorte() {
        let kern = "Angaben einer neueren Fassung, die diese Fassung nicht kennt (2 Vorhaben)"
        #expect(Planungsspeicher.unbekannteAngabenText(2, .geoeffnet) == " Die Datei enthält \(kern); die App führt sie nicht weiter.")
        #expect(Planungsspeicher.unbekannteAngabenText(2, .autosicherung)
                == " Die Autosicherung enthält \(kern); sie gehen beim nächsten Sichern verloren.")
        #expect(Planungsspeicher.unbekannteAngabenText(2, .gesichert)
                == " Die geladene Fassung enthielt \(kern); gesichert wurde sie ohne diese Angaben.")
        #expect(Planungsspeicher.unbekannteAngabenText(2, .geladen)
                == " Die geladene Fassung enthält \(kern); sie gehen beim nächsten Sichern verloren.")
        #expect(Planungsspeicher.unbekannteAngabenText(0, .geoeffnet).isEmpty)
        // Gerettet bei gesperrter Ablage ist noch nichts geschrieben (H3-03).
        #expect(Planungsspeicher.rettungsfundort(gesperrt: true) == .geladen
                && Planungsspeicher.rettungsfundort(gesperrt: false) == .gesichert)
    }

    @Test("Mit Übergangenem: erst die Bilanz, dann der Satz; ein verworfenes Vorhaben zählt nur als verworfen")
    func mitBilanz() throws {
        let (_, bilanz) = try Planungsdatei.lesenMitBilanz(datei(#"""
            {"id": "e1", "klasseId": "k1", "woche": 0, "titel": "a", "zukunft": 1},
            {"id": "e2", "klasseId": "fehlt", "woche": 0, "titel": "b", "zukunft": 1}
            """#))
        #expect(bilanz.unbekannteAngaben == 1 && bilanz.vorhaben == 1)
        #expect(Planungsspeicher.verlusttext(bilanz) + Planungsspeicher.unbekannteAngabenText(bilanz.unbekannteAngaben, .geoeffnet)
                == " Übergangen: 1 Vorhaben." + Self.satz(1))
    }

    @Test("Nur an Vorhaben (E1079): Unbekanntes oben in der Datei oder an einer Zeile zählt nicht")
    func nurVorhaben() throws {
        let (_, bilanz) = try Planungsdatei.lesenMitBilanz(datei(#"{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "a"}"#,
                                                                 oben: #", "zukunft": 1, "basisordner": "/alt""#,
                                                                 zeile: #", "zukunft": 1"#))
        #expect(bilanz.unbekannteAngaben == 0 && bilanz.istLeer)
    }

    @Test("Geschrieben wird nur Bekanntes: Nach dem Sichern ist die Angabe fort — und die Meldung mit ihr")
    func nachDemSichern() throws {
        let (p, bilanz) = try Planungsdatei.lesenMitBilanz(
            datei(#"{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "a", "zukunft": 1}"#))
        #expect(bilanz.unbekannteAngaben == 1)
        let (_, wieder) = try Planungsdatei.lesenMitBilanz(try Planungsdatei.schreiben(p))
        #expect(wieder.unbekannteAngaben == 0 && wieder.istLeer)
    }
}
