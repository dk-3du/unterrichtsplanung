// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

@Suite("Planungsdatei lesen und schreiben")
struct DateiPruefungen {

    private func beispiel() throws -> Planung {
        var planung = Planung.leer(
            titel: "Unterrichtsplanung 2026/27",
            start: try #require(Tag(iso: "2026-08-12")),
            wochen: 8,
            basis: "/Users/lehrkraft/Unterricht",
            klassen: Standardkurse.aufbauen(Array(Standardkurse.liste.prefix(3))),
            fachfarben: ["mathematik": "rot-mittel"])
        planung.frei = [try #require(Tag(iso: "2026-09-07"))]
        planung.ferien = [Ferienzeitraum(id: "f-1", name: "Herbstferien",
                                         von: try #require(Tag(iso: "2026-10-05")),
                                         bis: try #require(Tag(iso: "2026-10-16")))]
        planung.zellenfrei = [FreieZelle(klasseId: planung.klassen[0].id,
                                         woche: try #require(Tag(iso: "2026-08-24")))]
        planung.klassen[0].unterrichtstage = [.mittwoch, .montag]
        planung.eintraege = [
            Vorhaben(id: "e-1", klasseId: planung.klassen[0].id, woche: 2,
                     titel: "Zellen unter dem Mikroskop",
                     text: "Mikroskopieren, Zeichnen, Beschriften", erledigt: true,
                     materialien: [Material(titel: "Arbeitsblatt", pfad: "Bio/AB-Zelle.pdf"),
                                   Material(titel: "Film", pfad: "/Volumes/Stick/film.mp4")],
                     links: [Weblink(titel: "3ducation", adresse: "https://3ducation.org/")]),
        ]
        return planung
    }

    /// Bis 75 Zeilen werden gelesen; was darüber steht, fällt weg.
    @Test("Mehr Klassen/Kurse als vorgesehen werden beim Lesen abgeschnitten")
    func zuVieleKurse() throws {
        let kurse = (1...80).map {
            #"{"id":"k\#($0)","name":"K\#($0)","fach":"Biologie","farbe":0}"#
        }.joined(separator: ",")
        let roh = #"{"typ":"unterrichtsplanung","titel":"Viele","start":"2026-08-03","#
            + #""wochen":4,"klassen":[\#(kurse)]}"#
        let gelesen = try Planungsdatei.lesen(Data(roh.utf8))
        #expect(gelesen.klassen.count == Kennwerte.maxKlassen)
        #expect(gelesen.klassen.last?.name == "K75")
    }

    @Test("Schreiben und wieder Lesen ändert nichts")
    func hinUndZurueck() throws {
        let vorher = try beispiel()
        let daten = try Planungsdatei.schreiben(vorher)
        let nachher = try Planungsdatei.lesen(daten)

        #expect(nachher.titel == vorher.titel)
        #expect(nachher.start == vorher.start)
        #expect(nachher.wochen == vorher.wochen)
        #expect(nachher.basis == vorher.basis)
        #expect(nachher.frei == vorher.frei)
        #expect(nachher.fachfarben == vorher.fachfarben)
        #expect(nachher.zellenfrei == vorher.zellenfrei)
        #expect(nachher.klassen.map(\.id) == vorher.klassen.map(\.id))
        #expect(nachher.klassen.map(\.farbe) == vorher.klassen.map(\.farbe))
        #expect(nachher.klassen.map(\.unterrichtstage) == vorher.klassen.map(\.unterrichtstage))
        #expect(nachher.ferien.map(\.name) == vorher.ferien.map(\.name))
        #expect(nachher.eintraege.count == 1)
        #expect(nachher.eintraege[0].titel == "Zellen unter dem Mikroskop")
        #expect(nachher.eintraege[0].erledigt)
        #expect(nachher.eintraege[0].materialien.map(\.pfad)
                == ["Bio/AB-Zelle.pdf", "/Volumes/Stick/film.mp4"])
        #expect(nachher.eintraege[0].links.map(\.adresse) == ["https://3ducation.org/"])
    }

    @Test("Die geschriebene Datei trägt die Schlüssel des Web-Dashboards")
    func schluessel() throws {
        let daten = try Planungsdatei.schreiben(try beispiel())
        let roh = try #require(try JSONSerialization.jsonObject(with: daten) as? [String: Any])
        #expect(roh["typ"] as? String == "unterrichtsplanung")
        #expect(roh["version"] as? Int == 2)
        for schluessel in ["titel", "erstellt", "geaendert", "basis", "start", "wochen",
                           "ersterSchultag", "frei", "ferien", "sperrzeiten", "fachfarben",
                           "klassen", "zellenfrei", "eintraege"] {
            #expect(roh[schluessel] != nil, "Schlüssel \(schluessel) fehlt")
        }
        let eintraege = try #require(roh["eintraege"] as? [[String: Any]])
        #expect(eintraege[0]["klasseId"] != nil)
        // Die Unterrichtstage je Zeile, aufsteigend als Zahlen.
        let klassen = try #require(roh["klassen"] as? [[String: Any]])
        #expect(klassen[0]["unterrichtstage"] as? [Int] == [1, 3])
        #expect(klassen[1]["unterrichtstage"] as? [Int] == [])
        let links = try #require(eintraege[0]["links"] as? [[String: Any]])
        #expect(links[0]["url"] as? String == "https://3ducation.org/")
        // Schrägstriche stehen unmaskiert in der Datei — wie bei JSON.stringify.
        let text = try #require(String(data: daten, encoding: .utf8))
        #expect(text.contains("Bio/AB-Zelle.pdf"))
        #expect(!text.contains("Bio\\/AB-Zelle.pdf"))
    }

    @Test("Eine vom Web-Dashboard geschriebene Datei wird gelesen")
    func webDatei() throws {
        let text = """
        {
          "typ": "unterrichtsplanung",
          "version": 1,
          "titel": "Aus dem Browser",
          "erstellt": "2026-08-12T15:56:12.345Z",
          "geaendert": "2026-08-12T16:10:00.000Z",
          "basisordner": "/Users/x/Alt",
          "start": "2026-08-12",
          "wochen": 6,
          "frei": ["2026-08-17", "kaputt"],
          "ferien": [{ "id": "f1", "name": "Herbst", "von": "2026-10-16", "bis": "2026-10-05" }],
          "fachfarben": { "  Mathematik ": "rot", "Physik": "gibtsnicht" },
          "klassen": [
            { "id": "k1", "name": "G5", "fach": "Biologie", "farbe": 0, "farbeManuell": true },
            { "id": "k1", "name": "G6", "fach": "Chemie", "farbe": "4" },
            { "fach": "Mathematik" }
          ],
          "zellenfrei": [
            { "klasseId": "k1", "woche": "2026-08-24" },
            { "klasseId": "k1", "woche": "2026-08-24" },
            { "klasseId": "unbekannt", "woche": "2026-08-24" }
          ],
          "eintraege": [
            { "id": "e1", "klasseId": "k1", "woche": "1", "titel": "A",
              "beschreibung": "Alter Feldname",
              "materialien": [{ "pfad": "Bio/AB.pdf" }, { "titel": "leer" }],
              "links": [{ "url": "javascript:alert(1)" }, { "url": "3ducation.org" }] },
            { "id": "e2", "klasseId": "k1", "woche": 99, "titel": "Zu weit hinten" },
            { "id": "e3", "klasseId": "weg", "woche": 0, "titel": "Fremder Kurs" }
          ]
        }
        """
        let planung = try Planungsdatei.lesen(try #require(text.data(using: .utf8)))

        #expect(planung.titel == "Aus dem Browser")
        // Der alte Feldname basisordner wird noch gelesen.
        #expect(planung.basis == "/Users/x/Alt")
        // Der Start wird auf den Montag gezogen.
        #expect(planung.start.iso == "2026-08-10")
        #expect(planung.wochen == 6)
        #expect(planung.ersterSchultag == nil)
        // Unlesbare Daten in `frei` fallen weg.
        #expect(planung.frei.count == 1)
        // Vertauschte Ferienangaben bleiben vertauscht — gedreht würden sie
        // beim nächsten Öffnen stillschweigend wirksam.
        #expect(planung.ferien[0].von.iso == "2026-10-16")
        #expect(planung.ferien[0].bis.iso == "2026-10-05")
        #expect(planung.ferien[0].ungueltig)
        // Fachschlüssel normalisiert, unbekannte Farbe verworfen, „rot“ übersetzt.
        #expect(planung.fachfarben["mathematik"] == "rot-mittel")
        #expect(planung.fachfarben["physik"] == nil)
        #expect(planung.klassen.count == 3)
        #expect(Set(planung.klassen.map(\.id)).count == 3)
        #expect(planung.klassen[0].farbeManuell)
        // Der alte Platz 0 stand für Biologie und wird übersetzt.
        #expect(Farbwelt.ton(planung.klassen[0].farbe).schluessel == "gruen-mittel")
        // Die einzige Biologiezeile trägt ihre Farbe von Hand — keine Fachfarbe.
        #expect(planung.fachfarbe("Biologie") == nil)
        // „4“ als Zeichenkette ist kein gültiger Farbwert — es wird neu vergeben.
        #expect(Farbwelt.istGueltig(planung.klassen[1].farbe))
        #expect(planung.fachfarbe("Chemie") == planung.klassen[1].farbe)
        #expect(planung.klassen[2].name == "Klasse/Kurs 3")
        #expect(Farbwelt.ton(planung.klassen[2].farbe).schluessel == "rot-mittel")
        // Doppelte und unbekannte Zellen fallen weg.
        #expect(planung.zellenfrei.count == 1)
        #expect(planung.eintraege.count == 1)
        #expect(planung.eintraege[0].text == "Alter Feldname")
        // Material ohne Pfad fällt weg, Titel wird aus dem Dateinamen gebildet.
        #expect(planung.eintraege[0].materialien.count == 1)
        #expect(planung.eintraege[0].materialien[0].titel == "AB.pdf")
        // javascript: wird abgewiesen, die zweite Adresse ergänzt.
        #expect(planung.eintraege[0].links.map(\.adresse) == ["https://3ducation.org/"])
        #expect(planung.eintraege[0].links[0].titel == "3ducation.org")
    }

    @Test("Fremde und beschädigte Dateien werden benannt")
    func fremdeDateien() throws {
        #expect(throws: Planungsfehler.self) {
            try Planungsdatei.lesen(try #require("[]".data(using: .utf8)))
        }
        #expect(throws: Planungsfehler.self) {
            try Planungsdatei.lesen(try #require("{\"typ\":\"etwasanderes\"}".data(using: .utf8)))
        }
        #expect(throws: Planungsfehler.self) {
            try Planungsdatei.lesen(try #require("{\"foo\":1}".data(using: .utf8)))
        }
        #expect(throws: Planungsfehler.self) {
            try Planungsdatei.lesen(try #require("kein json".data(using: .utf8)))
        }
        let mitNull = try Planungsdatei.lesen(
            try #require("{\"typ\":null,\"klassen\":[]}".data(using: .utf8)))
        #expect(mitNull.klassen.isEmpty)
        let mitLeer = try Planungsdatei.lesen(
            try #require("{\"typ\":\"\",\"wochen\":4}".data(using: .utf8)))
        #expect(mitLeer.wochen == 4)

        let knapp = try Planungsdatei.lesen(try #require("{\"wochen\":4}".data(using: .utf8)))
        #expect(knapp.wochen == 4)
        #expect(knapp.titel == "Unterrichtsplanung")
    }

    @Test("Die Wochenzahl bleibt im erlaubten Bereich")
    func wochengrenzen() throws {
        func wochen(_ roh: String) throws -> Int {
            try Planungsdatei.lesen(try #require("{\"wochen\":\(roh)}".data(using: .utf8))).wochen
        }
        #expect(try wochen("0") == 52)
        #expect(try wochen("-3") == 1)
        #expect(try wochen("99") == 52)
        #expect(try wochen("\"12\"") == 12)
        #expect(try wochen("null") == 52)
    }

    @Test("Der Exportname wird entschärft")
    func exportname() {
        let heute = Tag.heute.iso
        #expect(Planungsdatei.exportName(titel: "Unterrichtsplanung 2026/27")
                == "Unterrichtsplanung_2026-27_\(heute).json")
        #expect(Planungsdatei.exportName(titel: "  Bio & Chemie: 5a  ")
                == "Bio_Chemie-_5a_\(heute).json")
        #expect(Planungsdatei.exportName(titel: "") == "Unterrichtsplanung_\(heute).json")
        #expect(Planungsdatei.exportName(titel: "&&&") == "Unterrichtsplanung_\(heute).json")
        #expect(Planungsdatei.exportName(titel: "Größen & Maße")
                == "Größen_Maße_\(heute).json")
    }

    @Test("Die Sicherungskopie trägt denselben Namen ohne Datum")
    func festerName() {
        #expect(Planungsdatei.festerName(titel: "Unterrichtsplanung 2026/27")
                == "Unterrichtsplanung_2026-27.json")
        #expect(Planungsdatei.festerName(titel: "  Bio & Chemie: 5a  ") == "Bio_Chemie-_5a.json")
        #expect(Planungsdatei.festerName(titel: "") == "Unterrichtsplanung.json")
        let heute = Tag.heute.iso
        #expect(Planungsdatei.exportName(titel: "Größen & Maße")
                == "Größen_Maße_\(heute).json")
        #expect(Planungsdatei.festerName(titel: "Größen & Maße") == "Größen_Maße.json")
    }

    /// Dateisysteme nehmen 255 Byte je Namensbestandteil; der Titel darf
    /// 500 Zeichen tragen, ein Umlaut zählt zwei Byte, ein Emoji vier.
    @Test("Der Dateiname bleibt unter der Byte-Grenze der Dateisysteme")
    func dateinameInBytes() {
        for titel in [String(repeating: "t", count: Planungsdatei.maxNamenslaenge),
                      String(repeating: "ä", count: Planungsdatei.maxNamenslaenge),
                      String(repeating: "😀", count: Planungsdatei.maxNamenslaenge)] {
            let mitDatum = Planungsdatei.exportName(titel: titel)
            let ohneDatum = Planungsdatei.festerName(titel: titel)
            #expect(mitDatum.utf8.count <= 255)
            #expect(ohneDatum.utf8.count <= 255)
            // Nicht mitten in ein Zeichen geschnitten.
            #expect(String(data: Data(mitDatum.utf8), encoding: .utf8) == mitDatum)
        }
        // Ein Emoji fällt der Entschärfung ohnehin zum Opfer; übrig bleibt der Ersatz.
        #expect(Planungsdatei.festerName(titel: String(repeating: "😀", count: 300))
                == "Unterrichtsplanung.json")
    }

    @Test("Was die Obergrenzen kappen, weist die Bilanz aus")
    func verlustbilanz() throws {
        let materialien = (1...250).map { #"{"pfad":"m\#($0).pdf"}"# }.joined(separator: ",")
        let links = (1...230).map { #"{"url":"https://a\#($0).org/"}"# }.joined(separator: ",")
        let roh = #"{"typ":"unterrichtsplanung","titel":"Grenzfall","start":"2026-08-10","#
            + #""wochen":4,"klassen":[{"id":"k1","name":"5a","fach":"Bio"}],"#
            + #""eintraege":[{"id":"e1","klasseId":"k1","woche":0,"titel":"T","#
            + #""materialien":[\#(materialien)],"links":[\#(links)]}]}"#

        let (planung, bilanz) = try Planungsdatei.lesenMitBilanz(Data(roh.utf8))
        #expect(planung.eintraege[0].materialien.count == Planungsdatei.maxMaterialien)
        #expect(planung.eintraege[0].links.count == Planungsdatei.maxLinks)
        #expect(bilanz.materialien == 250 - Planungsdatei.maxMaterialien)
        #expect(bilanz.links == 230 - Planungsdatei.maxLinks)
        #expect(!bilanz.istLeer)
        #expect(bilanz.verworfenes.contains("50 Materialien"))
        #expect(bilanz.verworfenes.contains("30 Weblinks")
                || bilanz.verworfenes.contains("30 Links"), "\(bilanz.verworfenes)")
    }

    @Test("Gekürzte Texte werden gezählt, nicht stillschweigend beschnitten")
    func gekuerzteTexte() throws {
        let langerText = String(repeating: "x", count: Planungsdatei.maxTextlaenge + 5_000)
        let langerTitel = String(repeating: "t", count: Planungsdatei.maxNamenslaenge + 200)
        let roh = #"{"typ":"unterrichtsplanung","titel":"Kurz","start":"2026-08-10","wochen":4,"#
            + #""klassen":[{"id":"k1","name":"5a","fach":"Bio"}],"#
            + #""eintraege":[{"id":"e1","klasseId":"k1","woche":0,"#
            + #""titel":"\#(langerTitel)","text":"\#(langerText)"}]}"#

        let (planung, bilanz) = try Planungsdatei.lesenMitBilanz(Data(roh.utf8))
        #expect(planung.eintraege[0].text.count == Planungsdatei.maxTextlaenge)
        #expect(planung.eintraege[0].titel.count == Planungsdatei.maxNamenslaenge)
        #expect(bilanz.gekuerzteTexte == 2)
        #expect(bilanz.gekuerztes == "2 gekürzte Texte")
    }

    /// Dieselben Fälle fährt `Web-App/vNN/leser_pruefen.py` gegen den Leser
    /// der Ansichtsfassung. Eine Grenze, die nur eine der beiden Fassungen
    /// kennt, lässt dieselbe Datei auf Mac und iPad Verschiedenes bedeuten.
    @Test("Die Grenzen des Lesers gelten wie in der Ansichtsfassung")
    func grenzenBeiderFassungen() throws {
        let langerPfad = String(repeating: "p", count: Planungsdatei.maxPfadlaenge + 200)
        let farben = (0..<(Planungsdatei.maxFachfarben + 100))
            .map { #""fach\#($0)":"blau-mittel""# }.joined(separator: ",")

        // Pfade messen an `maxPfadlaenge`, nicht an `maxNamenslaenge`.
        let pfade = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","wochen":4,"#
            + #""basis":"\#(langerPfad)","#
            + #""klassen":[{"id":"k1","name":"5a","verwaltung":"\#(langerPfad)"}],"#
            + #""eintraege":[]}"#
        let (mitPfaden, pfadbilanz) = try Planungsdatei.lesenMitBilanz(Data(pfade.utf8))
        #expect(mitPfaden.basis.count == Planungsdatei.maxPfadlaenge)
        #expect(mitPfaden.klassen[0].verwaltung.count == Planungsdatei.maxPfadlaenge)
        #expect(pfadbilanz.gekuerzteTexte == 2)
        // Wortgleich zur Meldung, die die Ansicht zeigt.
        #expect(pfadbilanz.gekuerztes == "2 gekürzte Texte")

        // Der Rückfall wird nur ausgewertet, wenn er gebraucht wird — sonst
        // zählte ein verworfenes Kürzen mit.
        let ungenutzt = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","#
            + #""wochen":4,"basis":"/kurz","basisordner":"\#(langerPfad)","#
            + #""klassen":[],"eintraege":[]}"#
        let (mitBasis, ohneVerlust) = try Planungsdatei.lesenMitBilanz(Data(ungenutzt.utf8))
        #expect(mitBasis.basis == "/kurz")
        #expect(ohneVerlust.gekuerzteTexte == 0)

        let gebraucht = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","#
            + #""wochen":4,"basis":"","basisordner":"\#(langerPfad)","#
            + #""klassen":[],"eintraege":[]}"#
        let (ausOrdner, mitVerlust) = try Planungsdatei.lesenMitBilanz(Data(gebraucht.utf8))
        #expect(ausOrdner.basis.count == Planungsdatei.maxPfadlaenge)
        #expect(mitVerlust.gekuerzteTexte == 1)

        let vieleFarben = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","#
            + #""wochen":4,"fachfarben":{\#(farben)},"klassen":[],"eintraege":[]}"#
        let (bunt, farbbilanz) = try Planungsdatei.lesenMitBilanz(Data(vieleFarben.utf8))
        #expect(bunt.fachfarben.count == Planungsdatei.maxFachfarben)
        #expect(farbbilanz.fachfarben == 100)
        // Sortiert gelesen: Welche wegfallen, darf nicht von der Reihenfolge
        // in der Datei abhängen.
        #expect(bunt.fachfarben["fach0"] == "blau-mittel")

        let zellen = (0..<10).map { _ in #"{"klasseId":"k1","woche":"2026-08-10"}"# }
            .joined(separator: ",")
        let doppelt = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","#
            + #""wochen":4,"klassen":[{"id":"k1","name":"5a"}],"#
            + #""frei":["2026-08-10","2026-08-10","krumm"],"#
            + #""zellenfrei":[\#(zellen)],"eintraege":[]}"#
        let (mengen, mengenbilanz) = try Planungsdatei.lesenMitBilanz(Data(doppelt.utf8))
        #expect(mengen.frei.count == 1)
        #expect(mengen.zellenfrei.count == 1)
        #expect(mengenbilanz.freieTage == 1)
    }

    /// Drei Stellen, an denen App und Ansicht leicht verschieden stutzen könnten —
    /// jede mit einer Wirkung auf die Daten, nicht nur auf die Anzeige.
    @Test("Gestutzt und verschluckt wird wie in der Ansichtsfassung")
    func stutzenBeiderFassungen() throws {
        // 1) `JSONSerialization` verschluckt genau EIN führendes U+FEFF je
        //    Zeichenkette. `JSON.parse` der Ansicht tut das nicht; ohne
        //    Nachbau hieße dasselbe Fach dort „\u{FEFF}mathe“ — ein zweites
        //    Fach mit eigener Farbe, und die Suche fände es nicht.
        let bom = "\u{FEFF}"
        let mitBOM = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","#
            + #""wochen":4,"titel":"\#(bom)Titel","#
            + #""klassen":[{"id":"k1","name":"\#(bom)5a","fach":"\#(bom)Mathe"}],"#
            + #""eintraege":[]}"#
        let (ohneVorspann, _) = try Planungsdatei.lesenMitBilanz(Data(mitBOM.utf8))
        #expect(ohneVorspann.titel == "Titel")
        #expect(ohneVorspann.klassen[0].name == "5a")
        #expect(ohneVorspann.klassen[0].fach == "Mathe")
        // Nur das erste, nur am Anfang.
        let innen = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","#
            + #""wochen":4,"titel":"a\#(bom)b","klassen":[],"eintraege":[]}"#
        #expect(try Planungsdatei.lesen(Data(innen.utf8)).titel == "a\u{FEFF}b")

        // 2) Kennungen werden an `.whitespaces` gestutzt — Zeilenumbrüche
        //    bleiben also stehen. Die Ansicht stutzte mit `String.trim()` und
        //    fand damit eine Zeile, die die App nicht fand: dasselbe Vorhaben
        //    stand dort im Raster und fehlte hier.
        let umbruch = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","#
            + #""wochen":4,"klassen":[{"id":"k1\n","name":"5a"}],"#
            + #""eintraege":[{"id":"e1","klasseId":"k1","woche":0,"titel":"T"}]}"#
        let (mitUmbruch, umbruchbilanz) = try Planungsdatei.lesenMitBilanz(Data(umbruch.utf8))
        #expect(mitUmbruch.klassen[0].id == "k1\n")
        #expect(mitUmbruch.eintraege.isEmpty)
        #expect(umbruchbilanz.vorhaben == 1)
        // Leerzeichen und Tabulator dagegen fallen auf beiden Seiten weg.
        let tabulator = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","#
            + #""wochen":4,"klassen":[{"id":"\tk1 ","name":"5a"}],"#
            + #""eintraege":[{"id":"e1","klasseId":"k1","woche":0,"titel":"T"}]}"#
        let (gestutzt, _) = try Planungsdatei.lesenMitBilanz(Data(tabulator.utf8))
        #expect(gestutzt.klassen[0].id == "k1")
        #expect(gestutzt.eintraege.count == 1)

        // 3) Der Fachschlüssel stutzt `.whitespacesAndNewlines` — dazu gehört
        //    U+0085, aber nicht U+FEFF. Genau umgekehrt hielt es die Ansicht.
        #expect(Farbwelt.fachSchluessel("\u{85}Mathe\u{2028}") == "mathe")
        #expect(Farbwelt.fachSchluessel("Mathe\u{FEFF}") == "mathe\u{FEFF}")
    }

    /// Der Abzugvergleich (1 500 erzeugte Grenzfälle, Werkzeug
    /// `abzug_pruefen.py` in der Ansichtsfassung) fand 136 Abweichungen mit
    /// einer Ursache: `JSONSerialization` verschluckt das führende U+FEFF
    /// **jeder** Zeichenkette — auch vor einer Zahl in Zeichenkettenform, in
    /// einem Wahrheitswert und in einem Schlüssel; die Ansicht tat es nur an
    /// den Stellen, die durch `textwert` gehen. Bei zwei danach gleichen
    /// Schlüsseln behält `JSONSerialization` den **ersten** (nachgemessen).
    /// Derselbe Fall steht in `leser_pruefen.py`.
    @Test("U+FEFF vor Zahlen, in Wahrheitswerten und Schlüsseln wird gelesen wie in der Ansichtsfassung")
    func vorspannBeiderFassungen() throws {
        let bom = "\u{FEFF}"
        let roh = #"{"typ":"unterrichtsplanung","version":"\#(bom)2","start":"2026-08-10","#
            + #""wochen":"\#(bom)6","#
            + #""fachfarben":{"\#(bom)mathe":"blau-mittel","mathe":"rot-hell"},"#
            + #""klassen":[{"id":"k1","name":"5a","fach":"Mathe","farbe":9,"#
            + #""farbeManuell":"\#(bom)","unterrichtstage":["\#(bom)3"]}],"#
            + #""eintraege":[{"id":"e1","klasseId":"k1","woche":"\#(bom)1","titel":"T","#
            + #""erledigt":"\#(bom)","dringend":"\#(bom)x"}]}"#
        let gelesen = try Planungsdatei.lesen(Data(roh.utf8))
        #expect(gelesen.wochen == 6)
        // „version“ 2 gelesen: Die Farbe bleibt, wie sie steht — in der alten
        // Palette würde Platz 9 übersetzt.
        #expect(gelesen.klassen[0].farbe == 9)
        #expect(!gelesen.klassen[0].farbeManuell)
        #expect(gelesen.klassen[0].unterrichtstage == [.mittwoch])
        #expect(gelesen.eintraege.count == 1)
        #expect(gelesen.eintraege[0].woche == 1)
        #expect(!gelesen.eintraege[0].erledigt)
        #expect(gelesen.eintraege[0].dringend)
        #expect(gelesen.fachfarben["mathe"] == "blau-mittel", "der erste Schlüssel gilt")
    }

    /// Wie `farbe`: Was keinen Tag Montag bis Freitag nennt, fällt still weg,
    /// Dubletten fallen in der Menge zusammen — derselbe Fall steht in
    /// `leser_pruefen.py`, damit die Ansicht dieselbe Zeile gleich liest.
    @Test("Unterrichtstage werden gelesen wie in der Ansichtsfassung")
    func unterrichtstageBeiderFassungen() throws {
        let roh = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","wochen":4,"#
            + #""klassen":[{"id":"k1","name":"5a","#
            + #""unterrichtstage":[5,"3",3,0,6,1.9,true,"x",null,-1]},"#
            + #"{"id":"k2","name":"5b","unterrichtstage":"Mo"},{"id":"k3","name":"5c"}],"#
            + #""eintraege":[]}"#
        let (gelesen, bilanz) = try Planungsdatei.lesenMitBilanz(Data(roh.utf8))
        #expect(gelesen.klassen[0].unterrichtstage == [.montag, .mittwoch, .freitag])
        #expect(gelesen.klassen[0].unterrichtstage.gespeichert == [1, 3, 5])
        #expect(gelesen.klassen[1].unterrichtstage.isEmpty)
        #expect(gelesen.klassen[2].unterrichtstage.isEmpty)
        // Kein Verlust im Sinne der Bilanz: Es fehlt nichts, das je galt.
        #expect(bilanz.istLeer)
    }

    @Test("Eine gewöhnliche Planung geht ohne Verlust durch")
    func bilanzLeer() throws {
        let (_, bilanz) = try Planungsdatei.lesenMitBilanz(try Planungsdatei.schreiben(beispiel()))
        #expect(bilanz.istLeer)
        #expect(bilanz.verworfenes.isEmpty)
        #expect(bilanz.gekuerztes == nil)
    }
}

// ── Sicherungskopie beim Beenden ──────────────────────────────────────────

@Suite("Sicherungskopie beim Beenden")
@MainActor
struct SicherungskopiePruefungen {

    /// Die Vorbedingung für jede Prüfung dieser Reihe, hart statt gemeldet:
    /// Ohne eigenen Ablageort schriebe jedes `autoexportAktiv = …` über die
    /// `didSet` in die Voreinstellungen des laufenden Prozesses, und `Ablage`
    /// zeigte auf die echte Planung.
    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    /// Ein eigener Ordner je Prüfung — geschrieben wird nur dorthin.
    private func ordner() throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "autoexport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Kopie & Test", start: try #require(Tag(iso: "2026-08-03")),
                             wochen: 4, basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1,
                                titel: "Bits und Bytes", text: "", erledigt: false,
                                materialien: [], links: [])]
        return p
    }

    @Test("Die Kopie landet als lesbare Planung im gewählten Ordner")
    func kopieWirdGeschrieben() throws {
        let ziel = try ordner()
        defer { try? FileManager.default.removeItem(at: ziel) }

        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportOrdner = ziel.path
        speicher.autoexportAktiv = true
        // Nur verschlüsselt: Gelesen wird durch den Tresor der Sitzung.
        try speicher.pruefverschluesselung()

        #expect(speicher.autoexportAusfuehren())

        let datei = ziel.appending(component: "Kopie_Test.json")
        let tresor = try #require(speicher.tresor)
        let gelesen = try Planungsdatei.lesen(try tresor.oeffnen(try Data(contentsOf: datei)))
        #expect(gelesen.titel == "Kopie & Test")
        #expect(gelesen.eintraege.count == 1)
        #expect(speicher.letzterAutoexport != nil)
    }

    @Test("Ohne Einstellung wird nichts geschrieben")
    func abgeschaltetSchreibtNichts() throws {
        let ziel = try ordner()
        defer { try? FileManager.default.removeItem(at: ziel) }

        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportOrdner = ziel.path
        speicher.autoexportAktiv = false

        #expect(!speicher.autoexportAusfuehren())
        #expect(try FileManager.default.contentsOfDirectory(atPath: ziel.path).isEmpty)

        speicher.autoexportAktiv = true
        speicher.autoexportOrdner = ""
        #expect(!speicher.autoexportAusfuehren())
    }

    @Test("Ein fehlender Zielordner wird gemeldet, nicht angelegt")
    func fehlenderOrdner() throws {
        let ziel = try ordner()
        let weg = ziel.appending(component: "nicht-da", directoryHint: .isDirectory)

        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportOrdner = weg.path
        speicher.autoexportAktiv = true

        #expect(!speicher.autoexportAusfuehren(vomNutzer: true))
        #expect(!FileManager.default.fileExists(atPath: weg.path))
        #expect(speicher.meldungen.contains { $0.art == .warnung })
        try? FileManager.default.removeItem(at: ziel)
    }

    /// Ein Prüflauf darf in den Einstellungen des Nutzers nichts hinterlassen —
    /// **auch nichts wegnehmen.** Die vorgemerkte Autoexport-Warnung wird beim
    /// Anzeigen verbraucht; lief das Löschen an `Einstellungen` vorbei, nahm ein
    /// Prüflauf sie dem Nutzer weg.
    @Test("Im Prüflauf bleiben die Einstellungen unberührt — auch beim Löschen")
    func einstellungenBleibenUnberuehrt() {
        let schluessel = "unterrichtsplanung.pruefung.\(UUID().uuidString)"
        UserDefaults.standard.set("vorher", forKey: schluessel)
        defer { UserDefaults.standard.removeObject(forKey: schluessel) }

        Planungsspeicher.Einstellungen.setzen("nachher", schluessel)
        #expect(UserDefaults.standard.string(forKey: schluessel) == "vorher")

        Planungsspeicher.Einstellungen.entfernen(schluessel)
        #expect(UserDefaults.standard.string(forKey: schluessel) == "vorher",
                "Löschen ist auch Schreiben")
    }

    // ── Der Ordner wandert ──────────────────────────────────────────

    @Test("Ein umbenannter Zielordner wird über das Lesezeichen wiedergefunden")
    func lesezeichenFindetUmbenannten() throws {
        let ziel = try ordner()
        let speicher = Planungsspeicher(vorschau: try planung())
        try speicher.pruefverschluesselung()
        speicher.autoexportZielSetzen(ziel.path)
        #expect(speicher.autoexportAktiv, "die Wahl schaltet die Kopie mit ein")
        #expect(speicher.autoexportAusfuehren())

        let neuerName = ziel.deletingLastPathComponent()
            .appending(component: "umbenannt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: ziel, to: neuerName)
        defer { try? FileManager.default.removeItem(at: neuerName) }

        #expect(speicher.autoexportAusfuehren(), "das Lesezeichen zeigt weiter auf denselben Ordner")
        // Verglichen wird die aufgelöste Form: Lesezeichen `/private/var/…`, Prüfordner `/var/…`.
        #expect(Systemzugriff.vereinheitlicht(speicher.autoexportOrdner)
                == Systemzugriff.vereinheitlicht(neuerName.path), "der Pfad wird nachgeführt")
        #expect(FileManager.default.fileExists(
            atPath: neuerName.appending(component: "Kopie_Test.json").path))
    }

    @Test("Ein gelöschter Zielordner wird als solcher benannt")
    func geloeschterOrdnerWirdBenannt() throws {
        let ziel = try ordner()
        let speicher = Planungsspeicher(vorschau: try planung())
        try speicher.pruefverschluesselung()
        speicher.autoexportZielSetzen(ziel.path)
        #expect(speicher.autoexportAusfuehren())

        try FileManager.default.removeItem(at: ziel)

        #expect(!speicher.autoexportAusfuehren(vomNutzer: true))
        let warnung = try #require(speicher.meldungen.last { $0.art == .warnung })
        #expect(warnung.text.contains("nicht mehr da"),
                "„nicht mehr da“ und „ließ sich nicht schreiben“ sind zwei Lagen")
    }

    @Test("Ein Zielordner aus einer älteren Fassung bekommt sein Lesezeichen nachgereicht")
    func lesezeichenNachgereicht() throws {
        let ziel = try ordner()
        let speicher = Planungsspeicher(vorschau: try planung())
        try speicher.pruefverschluesselung()
        // Eine Einstellung ohne Lesezeichen: ein Pfad, sonst nichts.
        speicher.autoexportOrdner = ziel.path
        speicher.autoexportAktiv = true
        speicher.lesezeichenNachruesten()

        let neuerName = ziel.deletingLastPathComponent()
            .appending(component: "spaeter-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: ziel, to: neuerName)
        defer { try? FileManager.default.removeItem(at: neuerName) }

        #expect(speicher.autoexportAusfuehren(), "auch die alte Einstellung findet ihren Ordner wieder")
    }

    // ── Ersteinrichtung ─────────────────────────────────────────────

    @Test("Gefragt wird genau einmal — und nie im Prüflauf")
    func ersteinrichtungFaellig() {
        let faellig = Planungsspeicher.ersteinrichtungFaellig

        #expect(faellig(false, "", false), "erster Start, nichts gewählt, nie gefragt")
        #expect(!faellig(false, "", true), "beantwortet ist beantwortet — auch „Später“")
        #expect(!faellig(false, "/tmp/irgendwo", false),
                "wer den Ordner schon hat, hat die Frage längst beantwortet")
        #expect(!faellig(true, "", false), "ein Prüflauf fragt nichts")
    }

    @Test("Im Prüflauf öffnet die Frage kein Blatt")
    func ersteinrichtungSchweigtImPruefstand() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.ersteinrichtungPruefen()
        #expect(speicher.offenerDialog == nil)
    }

    // Drei Fragen: erst die Verschlüsselung, dann die Kopie, zuletzt die Updates.

    @Test("Verschlüsselung zuerst: Einrichten, Abbrechen, Weiter, Einschalten — dann Kopie und Updates")
    func ersteinrichtungInSchritten() throws {
        typealias Schritt = Planungsspeicher.Ersteinrichtungsschritt
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.ersteinrichtungOeffnen()
        #expect(speicher.offenerDialog == .ersteinrichtung)
        #expect(speicher.ersteinrichtungsschritt == Schritt.verschluesselung)

        speicher.ersteinrichtungEinrichten()
        #expect(speicher.ersteinrichtungsschritt == Schritt.passphrase)
        speicher.ersteinrichtungAbbrechen()
        #expect(speicher.ersteinrichtungsschritt == Schritt.verschluesselung,
                "Abbrechen führt zur Frage zurück")
        #expect(!speicher.verschluesselt)

        speicher.ersteinrichtungEinrichten()
        #expect(throws: (any Error).self, "zu kurz — der Schritt bleibt stehen") {
            try speicher.ersteinrichtungWeiter(passphrase: "kurz")
        }
        #expect(speicher.ersteinrichtungsschritt == Schritt.passphrase)
        speicher.ersteinrichtungEinschalten()
        #expect(!speicher.verschluesselt, "ohne Blatt schaltet nichts")

        try speicher.ersteinrichtungWeiter(passphrase: "Ein Satz, den man behält")
        var schluessel: String?
        if case .blatt(let s) = speicher.ersteinrichtungsschritt { schluessel = s }
        #expect((schluessel?.count ?? 0) > 20, "das Blatt zeigt den Wiederherstellungsschlüssel")
        #expect(!speicher.verschluesselt, "scharf ist erst nach dem bestätigten Blatt")
        speicher.ersteinrichtungEinschalten()
        #expect(speicher.verschluesselt)
        #expect(speicher.wicklungen.map(\.art).sorted() == ["passphrase", "wiederherstellung"])
        #expect(speicher.ersteinrichtungsschritt == Schritt.sicherung)

        // Die dritte Frage — „Einschalten“ zählt als Antwort und erlaubt.
        speicher.ersteinrichtungZuUpdates()
        #expect(speicher.ersteinrichtungsschritt == Schritt.updates)
        #expect(!speicher.updatesGefragt)
        speicher.ersteinrichtungUpdates(erlauben: true)
        #expect(speicher.updatesGefragt && speicher.updatesErlaubt)

        // Eine versiegelte Planung als erste: nur noch die zweite und dritte Frage.
        speicher.offenerDialog = nil
        speicher.ersteinrichtungOeffnen()
        #expect(speicher.ersteinrichtungsschritt == Schritt.sicherung)
    }

    @Test("Überspringen lässt die Verschlüsselung aus und führt zur Kopie — „Nicht jetzt“ zählt als Antwort")
    func ersteinrichtungUeberspringen() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.ersteinrichtungOeffnen()
        speicher.ersteinrichtungUeberspringen()
        #expect(speicher.ersteinrichtungsschritt == .sicherung)
        #expect(!speicher.verschluesselt)
        #expect(speicher.wicklungen.isEmpty)

        speicher.ersteinrichtungZuUpdates()
        speicher.ersteinrichtungUpdates(erlauben: false)
        #expect(speicher.updatesGefragt && !speicher.updatesErlaubt,
                "„Nicht jetzt“ ist eine Antwort — gefragt wird nicht wieder")
    }

    @Test("Die Kopie überschreibt sich selbst statt danebenzuschreiben")
    func gleicherName() throws {
        let ziel = try ordner()
        defer { try? FileManager.default.removeItem(at: ziel) }

        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportOrdner = ziel.path
        speicher.autoexportAktiv = true
        try speicher.pruefverschluesselung()

        #expect(speicher.autoexportAusfuehren())
        #expect(speicher.autoexportAusfuehren())
        #expect(try FileManager.default.contentsOfDirectory(atPath: ziel.path).count == 1)
    }
}

// ── Stand aus der Ansicht fürs iPad ───────────────────────────────────────

@Suite("Statusdatei aus der iPad-Ansicht")
@MainActor
struct StatusPruefungen {

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Statusprobe", start: try #require(Tag(iso: "2026-08-03")),
                             wochen: 4, basis: "",
                             klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [
            Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Bits",
                     text: "", erledigt: false, materialien: [], links: []),
            Vorhaben(id: "e-2", klasseId: p.klassen[0].id, woche: 2, titel: "Bytes",
                     text: "", erledigt: true, materialien: [], links: [],
                     kommentar: "lief gut"),
        ]
        return p
    }

    private func datei(_ inhalt: String) -> Data { Data(inhalt.utf8) }

    @Test("Haken und Kommentar kommen an, Unbekanntes wird übergangen")
    func uebernahme() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let stand = Statusstand(
            gespeichert: "2026-08-18T18:00:00.000Z", planungstitel: "Statusprobe",
            eintraege: ["e-1": .init(erledigt: true, kommentar: "kam gut an"),
                        "e-fremd": .init(erledigt: true, kommentar: "gehört woanders hin")])

        let (haken, notizen) = speicher.statusAnwenden(stand)
        #expect(haken == 1)
        #expect(notizen == 1)

        let eins = try #require(speicher.planung?.eintraege.first { $0.id == "e-1" })
        #expect(eins.erledigt)
        #expect(eins.kommentar == "kam gut an")
        // Was nicht in der Datei steht, bleibt, wie es war.
        let zwei = try #require(speicher.planung?.eintraege.first { $0.id == "e-2" })
        #expect(zwei.erledigt)
        #expect(zwei.kommentar == "lief gut")
    }

    @Test("Ein zurückgenommener Haken wird ebenso übernommen wie ein gesetzter")
    func zurueckgenommen() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let stand = Statusstand(gespeichert: "2026-08-18T18:00:00.000Z", planungstitel: "",
                                eintraege: ["e-2": .init(erledigt: false, kommentar: "")])

        let (haken, notizen) = speicher.statusAnwenden(stand)
        #expect(haken == 1)
        #expect(notizen == 1, "auch der geleerte Kommentar ist eine Änderung")
        let zwei = try #require(speicher.planung?.eintraege.first { $0.id == "e-2" })
        #expect(!zwei.erledigt)
        #expect(zwei.kommentar.isEmpty)
    }

    @Test("Derselbe Stand ein zweites Mal ändert nichts mehr")
    func zweimalGleich() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let stand = Statusstand(gespeichert: "2026-08-18T18:00:00.000Z", planungstitel: "",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "Notiz")])
        #expect(speicher.statusAnwenden(stand) == (1, 1))
        #expect(speicher.statusAnwenden(stand) == (0, 0))
    }

    /// Der Stempel entscheidet, welcher Stand gilt — hier wie in der Ansicht.
    /// Beide Datumsleser sind darin nachsichtig, aber verschieden nachsichtig:
    /// Foundation nimmt den 30. Februar an und rechnet ihn auf den 2. März, der
    /// des Browsers weist ihn ab; die Schaltsekunde geht dort durch und hier
    /// nicht. Geprüft werden deshalb die Felder selbst.
    @Test("Ein unmöglicher Zeitpunkt taugt auf keiner Seite als Schranke")
    func zeitstempelGrenzfaelle() {
        let gut = "2026-08-10T10:00:00.000Z"
        #expect(Planungsspeicher.zeitstempelBrauchbar(gut))
        // Unmögliche Datums- und Uhrzeitfelder.
        #expect(!Planungsspeicher.zeitstempelBrauchbar("2026-02-30T10:00:00.000Z"))
        #expect(!Planungsspeicher.zeitstempelBrauchbar("2026-02-29T10:00:00.000Z"))
        #expect(Planungsspeicher.zeitstempelBrauchbar("2024-02-29T10:00:00.000Z"))
        #expect(!Planungsspeicher.zeitstempelBrauchbar("2026-08-10T24:00:00.000Z"))
        #expect(!Planungsspeicher.zeitstempelBrauchbar("2026-08-10T10:60:00.000Z"))
        #expect(!Planungsspeicher.zeitstempelBrauchbar("2026-08-10T10:00:60.000Z"))
        // Form und Zukunft wie bisher.
        #expect(!Planungsspeicher.zeitstempelBrauchbar("2026-08-10T10:00:00Z"))
        #expect(!Planungsspeicher.zeitstempelBrauchbar(""))
        #expect(!Planungsspeicher.zeitstempelBrauchbar("2099-01-01T00:00:00.000Z"))
        // Dieselbe Jahresschranke wie `Tag(iso:)`.
        #expect(!Planungsspeicher.zeitstempelBrauchbar("1899-12-31T23:59:59.999Z"))
    }

    @Test("Was am Mac zuletzt geändert wurde, schlägt den älteren Stand vom iPad")
    func aeltererStandVerliert() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        // Am Mac kommentiert: setzt den Stempel dieses Vorhabens auf jetzt.
        speicher.vorhabenSichern(try entwurf(speicher, id: "e-1", kommentar: "am Mac getippt"))

        let alt = Statusstand(gespeichert: "2026-08-18T18:00:00.000Z", planungstitel: "",
                              eintraege: ["e-1": .init(erledigt: true, kommentar: "vom iPad",
                                                       geaendert: "2026-08-18T18:00:00.000Z")])
        #expect(speicher.statusAnwenden(alt) == (0, 0))
        let eins = try #require(speicher.planung?.eintraege.first { $0.id == "e-1" })
        #expect(eins.kommentar == "am Mac getippt")
        #expect(!eins.erledigt)
    }

    @Test("Der jüngere Stand vom iPad kommt an, auch neben einer Mac-Änderung")
    func juengererStandGewinnt() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.vorhabenSichern(try entwurf(speicher, id: "e-1", kommentar: "am Mac getippt"))
        // Stempel lösen in Millisekunden auf; bei Gleichstand behält der Mac recht.
        Thread.sleep(forTimeInterval: 0.005)
        let spaeter = Zeitrechnung.jetztAlsZeitstempel()

        let jung = Statusstand(gespeichert: spaeter, planungstitel: "",
                               eintraege: ["e-1": .init(erledigt: true, kommentar: "später vom iPad",
                                                        geaendert: spaeter)])
        #expect(speicher.statusAnwenden(jung) == (1, 1))
        let eins = try #require(speicher.planung?.eintraege.first { $0.id == "e-1" })
        #expect(eins.kommentar == "später vom iPad")
        #expect(eins.erledigt)
    }

    /// Ein Entwurf, der nur den Kommentar setzt und alles Übrige stehen lässt.
    private func entwurf(_ speicher: Planungsspeicher, id: String,
                         kommentar: String) throws -> VorhabenEntwurf {
        let vorhaben = try #require(speicher.planung?.eintraege.first { $0.id == id })
        var e = VorhabenEntwurf(vorhaben)
        e.kommentar = kommentar
        return e
    }

    @Test("Die Datei der Ansicht wird gelesen — auch ohne Feld „typ“")
    func lesen() throws {
        let stand = try Statusdatei.lesen(datei("""
        {"typ":"unterrichtsplanung-status","version":1,
         "gespeichert":"2026-08-18T18:00:00.000Z","planungstitel":"Statusprobe",
         "eintraege":{"e-1":{"erledigt":true,"kommentar":" mit Rand "}}}
        """))
        #expect(stand.gespeichert == "2026-08-18T18:00:00.000Z")
        #expect(stand.eintraege["e-1"]?.erledigt == true)
        #expect(stand.eintraege["e-1"]?.kommentar == "mit Rand", "Rand wird abgeschnitten")

        let ohneTyp = try Statusdatei.lesen(datei("""
        {"gespeichert":"2026-08-18T18:00:00.000Z","eintraege":{"e-1":{"erledigt":true}}}
        """))
        #expect(ohneTyp.eintraege.count == 1)
    }

    @Test("Eine fremde oder kaputte Datei wird abgewiesen, nicht geraten")
    func abgewiesen() {
        #expect(throws: Planungsfehler.self) {
            try Statusdatei.lesen(datei("{\"typ\":\"etwas-anderes\",\"eintraege\":{}}"))
        }
        #expect(throws: Planungsfehler.self) { try Statusdatei.lesen(datei("kein JSON")) }
        #expect(throws: Planungsfehler.self) { try Statusdatei.lesen(datei("[1,2,3]")) }
        #expect(throws: Planungsfehler.self) {
            try Statusdatei.lesen(datei("{\"gespeichert\":\"2026-08-18T18:00:00.000Z\"}"))
        }
    }

    @Test("Geschrieben und wieder gelesen ergibt denselben Stand")
    func hinUndZurueck() throws {
        let stand = Statusstand(
            gespeichert: "2026-08-18T18:00:00.000Z", planungstitel: "Statusprobe",
            eintraege: ["e-1": .init(erledigt: true, kommentar: "Notiz mit „Zeichen“ & /"),
                        "e-2": .init(erledigt: false, kommentar: "")])
        #expect(try Statusdatei.lesen(try Statusdatei.schreiben(stand)) == stand)
    }

    @Test("Die Datei wird im Ordner der Sicherungskopie gefunden und übernommen")
    func ausDemOrdner() throws {
        let ordner = URL.temporaryDirectory
            .appending(component: "status-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportZielSetzen(ordner.path)

        let stand = Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(),
                                planungstitel: "Statusprobe",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "aus dem Ordner")])
        try Statusdatei.schreiben(stand)
            .write(to: ordner.appending(component: Statusdatei.name), options: [.atomic])

        speicher.statusUebernehmen()

        let eins = try #require(speicher.planung?.eintraege.first { $0.id == "e-1" })
        #expect(eins.erledigt)
        #expect(eins.kommentar == "aus dem Ordner")
        #expect(speicher.meldungen.contains { $0.text.contains("Ansicht fürs iPad") })
    }

    /// Wörtlich das, was die Ansicht schreibt — am laufenden Browser
    /// abgenommen, nicht von Hand nachgebaut.
    @Test("Was die Ansicht wirklich schreibt, liest die App")
    func abgenommeneDatei() throws {
        let stand = try Statusdatei.lesen(datei("""
        {
          "typ": "unterrichtsplanung-status",
          "version": 1,
          "gespeichert": "2026-08-19T16:00:20.503Z",
          "planungstitel": "Probeplanung",
          "eintraege": {
            "e-1": {
              "erledigt": true,
              "kommentar": "Klasse war laut, Einstieg trotzdem geschafft",
              "geaendert": "2026-08-19T16:00:04.892Z"
            }
          }
        }
        """))
        #expect(stand.planungstitel == "Probeplanung")
        #expect(stand.eintraege.count == 1)
        let eintrag = try #require(stand.eintraege["e-1"])
        #expect(eintrag.erledigt)
        #expect(eintrag.kommentar == "Klasse war laut, Einstieg trotzdem geschafft")

        #expect(stand.gespeichert == "2026-08-19T16:00:20.503Z")
    }

    @Test("Eine übergroße Statusdatei wird nicht eingelesen")
    func zuGross() throws {
        let ordner = URL.temporaryDirectory
            .appending(component: "status-gross-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportZielSetzen(ordner.path)

        let riese = String(repeating: "x", count: Statusdatei.hoechstgroesse + 1024)
        let stand = Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(),
                                planungstitel: "Statusprobe",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: riese)])
        try Statusdatei.schreiben(stand)
            .write(to: ordner.appending(component: Statusdatei.name), options: [.atomic])

        speicher.statusUebernehmen()

        let eins = try #require(speicher.planung?.eintraege.first { $0.id == "e-1" })
        #expect(!eins.erledigt, "nichts übernommen")
        #expect(speicher.meldungen.contains { $0.text.contains("ungewöhnlich groß") })
    }

    @Test("Ohne Statusdatei bleibt es still")
    func ohneDatei() throws {
        let ordner = URL.temporaryDirectory
            .appending(component: "status-leer-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }

        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportZielSetzen(ordner.path)
        speicher.statusUebernehmen()
        #expect(speicher.meldungen.isEmpty)
    }
}

// ── Eine Datei von außen öffnen ───────────────────────────────────────────

/// Der Weg, den eine Datei per Doppelklick, „Öffnen mit“ oder ⌘O nimmt.
@Suite("Planung von außen öffnen")
@MainActor
struct OeffnenVonAussenPruefungen {

    private func dateiMitPlanung(titel: String) throws -> URL {
        var p = Planung.leer(titel: titel, start: try #require(Tag(iso: "2026-08-03")),
                             wochen: 6, basis: "",
                             klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 2,
                                titel: "Bits und Bytes", text: "", erledigt: false,
                                materialien: [], links: [])]
        let ziel = URL.temporaryDirectory.appending(component: "oeffnen-\(UUID().uuidString).json")
        try Planungsdatei.schreiben(p).write(to: ziel)
        return ziel
    }

    @Test("Ohne bestehende Planung wird ohne Rückfrage übernommen")
    func ohneBestand() throws {
        let datei = try dateiMitPlanung(titel: "Von außen")
        defer { try? FileManager.default.removeItem(at: datei) }

        let speicher = Planungsspeicher(vorschau: nil)
        speicher.importieren(von: datei)

        #expect(speicher.rueckfrage == nil)
        #expect(speicher.planung?.titel == "Von außen")
        #expect(speicher.planung?.eintraege.count == 1)
    }

    /// Beim Start ohne Autosicherung steht der Dialog „Neue Planungsdatei“
    /// offen; kommt dann eine Datei herein, läge er über der Planung.
    @Test("Der Dialog „Neue Planungsdatei“ schließt sich, wenn eine Datei hereinkommt")
    func dialogSchliesstSich() throws {
        let datei = try dateiMitPlanung(titel: "Hereingereicht")
        defer { try? FileManager.default.removeItem(at: datei) }

        let speicher = Planungsspeicher(vorschau: nil)
        speicher.offenerDialog = .neuePlanung
        speicher.importieren(von: datei)

        #expect(speicher.offenerDialog == nil)
        #expect(speicher.planung?.titel == "Hereingereicht")
    }

    @Test("Eine bestehende Planung mit Vorhaben wird erst nach Rückfrage ersetzt")
    func mitBestand() throws {
        let datei = try dateiMitPlanung(titel: "Neu")
        defer { try? FileManager.default.removeItem(at: datei) }

        var alt = Planung.leer(titel: "Alt", start: try #require(Tag(iso: "2026-08-03")),
                               wochen: 6, basis: "",
                               klassen: Standardkurse.aufbauen([("G5", "Biologie")]),
                               fachfarben: [:])
        alt.eintraege = [Vorhaben(id: "a-1", klasseId: alt.klassen[0].id, woche: 0,
                                  titel: "Zellen", text: "", erledigt: false,
                                  materialien: [], links: [])]
        let speicher = Planungsspeicher(vorschau: alt)
        speicher.importieren(von: datei)

        #expect(speicher.rueckfrage != nil, "eine bestehende Planung darf nicht stillschweigend weichen")
        #expect(speicher.planung?.titel == "Alt")

        speicher.rueckfrageBeantworten(true)
        #expect(speicher.planung?.titel == "Neu")
    }

    @Test("Eine unbrauchbare Datei wird gemeldet und lässt die Planung stehen")
    func unbrauchbar() throws {
        let datei = URL.temporaryDirectory.appending(component: "kaputt-\(UUID().uuidString).json")
        try Data("{ kein JSON".utf8).write(to: datei)
        defer { try? FileManager.default.removeItem(at: datei) }

        let alt = Planung.leer(titel: "Alt", start: try #require(Tag(iso: "2026-08-03")),
                               wochen: 6, basis: "", klassen: [], fachfarben: [:])
        let speicher = Planungsspeicher(vorschau: alt)
        speicher.importieren(von: datei)

        #expect(speicher.planung?.titel == "Alt")
        #expect(speicher.meldungen.contains { $0.art == .warnung })
    }
}

// ── Ferien und Wochenlage ─────────────────────────────────────────────────

@Suite("Unterrichtsfreie Zeiten")
struct FerienPruefungen {

    private func planung(ferien: [Ferienzeitraum], frei: Set<Tag> = []) throws -> Planung {
        var p = Planung.leer(titel: "T", start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 10, basis: "", klassen: [], fachfarben: [:])
        p.ferien = ferien
        p.frei = frei
        return p
    }

    @Test("Eine ganz getroffene Woche ist unterrichtsfrei")
    func ganzeWoche() throws {
        let p = try planung(ferien: [Ferienzeitraum(
            id: "f", name: "Herbstferien",
            von: try #require(Tag(iso: "2026-08-17")),
            bis: try #require(Tag(iso: "2026-08-23")))])
        let lage = p.lage(p.wochenListe[1])
        #expect(lage.frei)
        #expect(!lage.teilweise)
        #expect(lage.name == "Herbstferien")
    }

    @Test("Eine angeschnittene Woche bleibt bespielbar")
    func angeschnitten() throws {
        // Ferien enden am Mittwoch: drei von fünf Tagen fallen aus.
        let p = try planung(ferien: [Ferienzeitraum(
            id: "f", name: "Praktikum",
            von: try #require(Tag(iso: "2026-08-17")),
            bis: try #require(Tag(iso: "2026-08-19")))])
        let lage = p.lage(p.wochenListe[1])
        #expect(!lage.frei)
        #expect(lage.teilweise)
        #expect(lage.tage == 3)
        #expect(lage.name == "Praktikum")
    }

    @Test("Zwei Zeiträume, die eine Woche gemeinsam bedecken, machen sie frei")
    func mehrere() throws {
        let p = try planung(ferien: [
            Ferienzeitraum(id: "a", name: "A", von: try #require(Tag(iso: "2026-08-17")),
                           bis: try #require(Tag(iso: "2026-08-18"))),
            Ferienzeitraum(id: "b", name: "B", von: try #require(Tag(iso: "2026-08-19")),
                           bis: try #require(Tag(iso: "2026-08-21"))),
        ])
        let lage = p.lage(p.wochenListe[1])
        #expect(lage.frei)
        #expect(!lage.teilweise)
        #expect(lage.tage == 5)
        #expect(lage.name == "B", "B stellt drei der fünf Tage, A nur zwei")
    }

    @Test("Bei gleich vielen Tagen nennt der Spaltenkopf die Zahl der Zeiträume")
    func gleichstand() throws {
        let p = try planung(ferien: [
            Ferienzeitraum(id: "a", name: "A", von: try #require(Tag(iso: "2026-08-17")),
                           bis: try #require(Tag(iso: "2026-08-18"))),
            Ferienzeitraum(id: "b", name: "B", von: try #require(Tag(iso: "2026-08-20")),
                           bis: try #require(Tag(iso: "2026-08-21"))),
        ])
        let lage = p.lage(p.wochenListe[1])
        #expect(lage.teilweise)
        #expect(lage.tage == 4)
        #expect(lage.name == "2 Zeiträume")
    }

    @Test("Überlappende Zeiträume werden nicht doppelt gezählt")
    func ueberlappend() throws {
        let p = try planung(ferien: [
            Ferienzeitraum(id: "a", name: "A", von: try #require(Tag(iso: "2026-08-17")),
                           bis: try #require(Tag(iso: "2026-08-19"))),
            Ferienzeitraum(id: "b", name: "B", von: try #require(Tag(iso: "2026-08-18")),
                           bis: try #require(Tag(iso: "2026-08-20"))),
        ])
        let lage = p.lage(p.wochenListe[1])
        #expect(lage.teilweise)
        #expect(lage.tage == 4, "Mo–Do, nicht die Summe von sechs")
    }

    @Test("Eine von Hand geschaltete Woche hat Vorrang")
    func vonHand() throws {
        let p = try planung(ferien: [], frei: [try #require(Tag(iso: "2026-08-17"))])
        let lage = p.lage(p.wochenListe[1])
        #expect(lage.frei)
        #expect(lage.name == "unterrichtsfrei")
    }

    @Test("Wochenende zählt nicht mit")
    func wochenende() throws {
        let p = try planung(ferien: [Ferienzeitraum(
            id: "f", name: "Wochenende",
            von: try #require(Tag(iso: "2026-08-15")),
            bis: try #require(Tag(iso: "2026-08-16")))])
        #expect(p.lage(p.wochenListe[0]) == .unterricht)
        #expect(p.lage(p.wochenListe[1]) == .unterricht)
    }

    @Test("Die Bilanz zählt Unterrichts- und Ferienwochen")
    func bilanz() throws {
        let p = try planung(ferien: [Ferienzeitraum(
            id: "f", name: "Ferien",
            von: try #require(Tag(iso: "2026-08-17")),
            bis: try #require(Tag(iso: "2026-08-26")))])
        let b = p.ferienBilanz()
        #expect(b.gesamt == 10)
        #expect(b.frei == 1)          // 17.–21.08. ganz
        #expect(b.teilweise == 1)     // 24.–26.08. angeschnitten
        #expect(b.unterricht == 9)
        #expect(b.text == "9 Unterrichtswochen · 1 unterrichtsfrei · 1 angeschnitten · 10 insgesamt")
    }

    @Test("Die Lagebeschreibung eines Zeitraums")
    func lagetext() throws {
        let zeitraum = Ferienzeitraum(id: "f", name: "Ferien",
                                      von: try #require(Tag(iso: "2026-08-17")),
                                      bis: try #require(Tag(iso: "2026-08-26")))
        let p = try planung(ferien: [zeitraum])
        #expect(zeitraum.lageText(in: p) == "1 ganze Woche · 1 angeschnitten")

        let daneben = Ferienzeitraum(id: "g", name: "Weit weg",
                                     von: try #require(Tag(iso: "2027-08-17")),
                                     bis: try #require(Tag(iso: "2027-08-26")))
        #expect(daneben.lageText(in: p) == "außerhalb des Zeitraums")

        let verdreht = Ferienzeitraum(id: "h", name: "Verdreht",
                                      von: try #require(Tag(iso: "2026-08-26")),
                                      bis: try #require(Tag(iso: "2026-08-17")))
        #expect(verdreht.ungueltig)
        #expect(verdreht.lageText(in: p) == "Ende vor Beginn")
    }
}
