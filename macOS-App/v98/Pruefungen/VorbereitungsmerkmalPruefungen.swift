// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Das Merkmal „Vorbereitung“ am Vorhaben (v93, E1074, E1075, E1077, E1080): gehandhabt wie die Korrektur — ein
/// Schalter, kein Pflichtdatum —, nie zugleich mit Prüfung, Korrektur oder Termin, mit dringlich zusammen. In der Datei
/// steht es nur, wo es gesetzt ist: Eine Planung ohne Vorbereitung bleibt Byte für Byte, wie 2.6.1 sie schrieb.
@Suite("Merkmal Vorbereitung: Datei, Speicher, Rücknahme")
@MainActor
struct VorbereitungsmerkmalPruefungen {
    private func speicher() throws -> Planungsspeicher {
        var planung = Planung.leer(titel: "Merkmal", start: try #require(Tag(iso: "2026-08-10")),
                                   wochen: 6, basis: "",
                                   klassen: Standardkurse.aufbauen([("G8b", "Chemie")]),
                                   fachfarben: [:])
        let klasse = try #require(planung.klassen.first?.id)
        var korrektur = Vorhaben(id: "korrektur", klasseId: klasse, woche: 2, titel: "Klassenarbeit 1 korrigieren",
                                 text: "", erledigt: false, materialien: [], links: [])
        korrektur.korrektur = true
        var termin = Vorhaben(id: "termin", klasseId: klasse, woche: 3, titel: "Elterngespräch", text: "",
                              erledigt: false, materialien: [], links: [])
        termin.termin = "m-1"
        planung.eintraege = [
            Vorhaben(id: "vorbereitung", klasseId: klasse, woche: 0, titel: "Klassenarbeit 1 vorbereiten", text: "",
                     erledigt: false, materialien: [], links: []),
            Vorhaben(id: "arbeit", klasseId: klasse, woche: 1, titel: "Klassenarbeit 1", text: "", erledigt: false,
                     materialien: [], links: [], pruefung: true, pruefungstag: Tag(iso: "2026-08-19")),
            korrektur,
            termin,
        ]
        return Planungsspeicher(vorschau: planung)
    }

    private func eintrag(_ s: Planungsspeicher, _ id: String) throws -> Vorhaben {
        try #require(s.planung?.eintraege.first { $0.id == id })
    }

    // ── Datei ─────────────────────────────────────────────────────────────

    private func datei(_ eintrag: String) -> Data {
        Data("""
            {"typ": "unterrichtsplanung", "version": 2, "titel": "V", "start": "2026-08-10", "wochen": 4, "basis": "",
             "klassen": [{"id": "k1", "name": "G8b", "fach": "Chemie", "farbe": 1}],
             "eintraege": [\(eintrag)]}
            """.utf8)
    }

    private func gelesen(_ felder: String) throws -> Vorhaben {
        let p = try Planungsdatei.lesen(datei(#"{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "t"\#(felder)}"#))
        return try #require(p.eintraege.first)
    }

    @Test("Lesen: Fehlt das Feld, ist es falsch; gesetzt wird es gelesen wie die Korrektur")
    func lesen() throws {
        func vorbereitung(_ felder: String) throws -> Bool { try gelesen(felder).vorbereitung }
        #expect(try !vorbereitung(""), "eine Datei aus 2.6.1 und früher")
        #expect(try vorbereitung(#", "vorbereitung": true"#))
        #expect(try !vorbereitung(#", "vorbereitung": false"#))
        #expect(try vorbereitung(#", "vorbereitung": 1"#) && vorbereitung(#", "vorbereitung": "ja""#),
                "Fremdwerte wie bei dringend")
        #expect(try !vorbereitung(#", "vorbereitung": 0"#) && !vorbereitung(#", "vorbereitung": """#)
                && !vorbereitung(#", "vorbereitung": null"#))
        let mit = try gelesen(#", "vorbereitung": true, "datum": "2026-08-12", "dringend": true"#)
        #expect(mit.vorbereitung && mit.dringend && mit.datum == Tag(iso: "2026-08-12"), "mit Datum und dringlich")
    }

    @Test("Lesen: Prüfung und Korrektur gehen vor — am Rohwert; neben einem Termin bleibt sie (E1080)")
    func lesenVorrang() throws {
        let pruefung = try gelesen(#", "pruefung": true, "pruefungstag": "2026-08-12", "vorbereitung": true"#)
        #expect(pruefung.pruefung && !pruefung.vorbereitung)
        let korrektur = try gelesen(#", "korrektur": true, "vorbereitung": true"#)
        #expect(korrektur.korrektur && !korrektur.vorbereitung)
        let alle = try gelesen(#", "pruefung": true, "korrektur": true, "vorbereitung": true"#)
        #expect(alle.pruefung && !alle.korrektur && !alle.vorbereitung, "nur die Prüfung")
        // Den Termin liest die Web App nicht — beide Leser bleiben gleich; die Anzeige setzt die Vorbereitung vor ihn.
        let termin = try gelesen(#", "vorbereitung": true, "termin": "m-1", "datum": "2026-08-12""#)
        #expect(termin.vorbereitung && termin.istTermin)
    }

    @Test("Nur geschrieben, wo gesetzt (E1077): ohne Vorbereitung kein Schlüssel; gesetzt genau einer; entfernt wie vorher")
    func nurWoGesetzt() throws {
        let s = try speicher()
        func eintraege() throws -> [[String: Any]] {
            let planung = try #require(s.planung)
            return try #require(Planungsdatei.alsObjekt(planung)["eintraege"] as? [[String: Any]])
        }
        func bytes(_ e: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: e, options: [.sortedKeys])
        }
        let ohne = try eintraege()
        #expect(ohne.allSatisfy { $0["vorbereitung"] == nil }, "eine Planung ohne Vorbereitung: wie aus 2.6.1")
        s.vorbereitungUmschalten("vorbereitung")
        #expect(try eintraege().map { $0["vorbereitung"] as? Bool } == [true, nil, nil, nil],
                "genau ein Schlüssel, an diesem Vorhaben")
        let gesetzt = try #require(s.planung)
        #expect(Planungsdatei.alsObjekt(gesetzt)["version"] as? Int == Kennwerte.dateiVersion
                && Kennwerte.dateiVersion == 2, "kein Sprung der Fassung")
        s.vorbereitungUmschalten("vorbereitung")
        // Die Vorhaben, nicht die ganze Datei: `sichern()` stempelt `geaendert` mit der Uhr. Die ganze Datei Byte für
        // Byte wie aus 2.6.1 hält `LeistungsdokumentationPruefungen.alteDateiBytegleich`.
        #expect(try bytes(eintraege()) == bytes(ohne), "wieder entfernt: die Vorhaben Byte für Byte wie vorher")
    }

    @Test("Schreiben und wieder lesen: Die Vorbereitung bleibt — neben dringlich, die Nachbarn unberührt")
    func rundreise() throws {
        let s = try speicher()
        s.vorbereitungUmschalten("vorbereitung")
        s.dringlichUmschalten("vorbereitung")
        let gelesen = try Planungsdatei.lesen(try Planungsdatei.schreiben(try #require(s.planung)))
        #expect(gelesen.eintraege.map(\.vorbereitung) == [true, false, false, false])
        #expect(gelesen.eintraege.map(\.dringend) == [true, false, false, false])
        #expect(gelesen.eintraege.map(\.pruefung) == [false, true, false, false])
        #expect(gelesen.eintraege.map(\.korrektur) == [false, false, true, false])
        #expect(gelesen.eintraege.map(\.istTermin) == [false, false, false, true])
    }

    // ── Speicher ──────────────────────────────────────────────────────────

    @Test("Umschalten: ein Schritt hin, ein Schritt zurück — mit eigenen Namen, neben dringlich")
    func umschalten() throws {
        let s = try speicher()
        s.vorbereitungUmschalten("vorbereitung")
        #expect(try eintrag(s, "vorbereitung").vorbereitung)
        #expect(try eintrag(s, "vorbereitung").datum == nil, "ein Datum braucht sie nicht")
        #expect(s.widerrufenTitel.contains(Schrittname.alsVorbereitungKennzeichnen))
        s.dringlichUmschalten("vorbereitung")
        #expect(try eintrag(s, "vorbereitung").vorbereitung && eintrag(s, "vorbereitung").dringend,
                "mit dringlich zusammen (E1075)")
        s.vorbereitungUmschalten("vorbereitung")
        #expect(try !eintrag(s, "vorbereitung").vorbereitung && eintrag(s, "vorbereitung").dringend)
        #expect(s.widerrufenTitel.contains(Schrittname.vorbereitungEntfernen))
        s.widerrufen()
        #expect(try eintrag(s, "vorbereitung").vorbereitung)
        #expect(Schrittname.alsVorbereitungKennzeichnen == "Als Vorbereitung kennzeichnen")
        #expect(Schrittname.vorbereitungEntfernen == "Kennzeichnung als Vorbereitung entfernen")
        #expect(Schrittname.alle.contains(Schrittname.alsVorbereitungKennzeichnen)
                && Schrittname.alle.contains(Schrittname.vorbereitungEntfernen))
    }

    @Test("Entweder–oder (E1075): An Prüfung, Korrektur oder Termin wirkt der Schalter nicht — und umgekehrt")
    func entwederOder() throws {
        let s = try speicher()
        let vorher = s.planung
        s.vorbereitungUmschalten("arbeit")
        s.vorbereitungUmschalten("korrektur")
        s.vorbereitungUmschalten("termin")
        #expect(s.planung == vorher, "an Prüfung, Korrektur und Termin ändert sich nichts")
        s.vorbereitungUmschalten("vorbereitung")
        let alsVorbereitung = s.planung
        s.pruefungUmschalten("vorbereitung")
        s.korrekturUmschalten("vorbereitung")
        #expect(s.planung == alsVorbereitung, "an einer Vorbereitung wird weder Prüfung noch Korrektur")
        // „Als Termin führen …“ aus dem Menü: Das Blatt geht auf, der Schalter bleibt aus.
        s.vorhabenOeffnen(id: "vorbereitung", alsTermin: true)
        #expect(s.vorhabenDialog?.vorbereitung == true && s.vorhabenDialog?.termin == false)
    }

    @Test("Das Blatt sichert das Merkmal — die Schranke davor hält die Regel; der Termin-Schalter ist gesperrt")
    func dialog() throws {
        let s = try speicher()
        var entwurf = VorhabenEntwurf(try eintrag(s, "vorbereitung"))
        #expect(!entwurf.vorbereitung && !entwurf.veraendert)
        entwurf.vorbereitung = true
        #expect(entwurf.veraendert, "der Schalter ist eine Eingabe")
        #expect(entwurf.terminSchalterGesperrt(verwaltungOffen: true)
                && entwurf.terminSchalterGesperrt(verwaltungOffen: false))
        entwurf.termin = true
        #expect(!entwurf.alsTermin, "die Vorbereitung geht dem Termin vor")
        entwurf.termin = false
        s.vorhabenSichern(entwurf)
        #expect(try eintrag(s, "vorbereitung").vorbereitung)
        #expect(VorhabenEntwurf(try eintrag(s, "vorbereitung")).vorbereitung, "der Entwurf liest es zurück")
        // Am Blatt vorbei: Prüfung bzw. Korrektur gehen vor.
        var pruefung = VorhabenEntwurf(try eintrag(s, "arbeit"))
        pruefung.vorbereitung = true
        s.vorhabenSichern(pruefung)
        #expect(try eintrag(s, "arbeit").pruefung && !eintrag(s, "arbeit").vorbereitung)
        var korrektur = VorhabenEntwurf(try eintrag(s, "korrektur"))
        korrektur.vorbereitung = true
        s.vorhabenSichern(korrektur)
        #expect(try eintrag(s, "korrektur").korrektur && !eintrag(s, "korrektur").vorbereitung)
        // Ein neues Vorhaben als Vorbereitung.
        var neu = VorhabenEntwurf(klasseId: try eintrag(s, "arbeit").klasseId, woche: 4)
        neu.titel = "Experiment vorbereiten"
        neu.vorbereitung = true
        s.vorhabenSichern(neu)
        #expect(s.planung?.eintraege.last?.vorbereitung == true)
        // Neu und am Blatt vorbei (Z-BE3-06): Prüfung bzw. Korrektur gehen auch beim Anlegen vor.
        var neuePruefung = VorhabenEntwurf(klasseId: try eintrag(s, "arbeit").klasseId, woche: 4)
        neuePruefung.titel = "Test"
        neuePruefung.pruefung = true
        neuePruefung.vorbereitung = true
        s.vorhabenSichern(neuePruefung)
        #expect(s.planung?.eintraege.last?.pruefung == true && s.planung?.eintraege.last?.vorbereitung == false)
        var neueKorrektur = VorhabenEntwurf(klasseId: try eintrag(s, "arbeit").klasseId, woche: 5)
        neueKorrektur.titel = "Test korrigieren"
        neueKorrektur.korrektur = true
        neueKorrektur.vorbereitung = true
        s.vorhabenSichern(neueKorrektur)
        #expect(s.planung?.eintraege.last?.korrektur == true && s.planung?.eintraege.last?.vorbereitung == false)
    }

    @Test("Lösen geht immer (Z-BE3-04): eine Vorbereitung neben einem Termin aus einer fremden Datei — ohne den Termin")
    func loesenNebenTermin() throws {
        var planung = Planung.leer(titel: "Merkmal", start: try #require(Tag(iso: "2026-08-10")), wochen: 6, basis: "",
                                   klassen: Standardkurse.aufbauen([("G8b", "Chemie")]), fachfarben: [:])
        var beides = Vorhaben(id: "beides", klasseId: try #require(planung.klassen.first?.id), woche: 1,
                              titel: "Elterngespräch vorbereiten", text: "", erledigt: false, materialien: [], links: [])
        beides.termin = "m-1"
        beides.vorbereitung = true
        planung.eintraege = [beides]
        let s = Planungsspeicher(vorschau: planung)
        s.vorbereitungUmschalten("beides")
        #expect(try eintrag(s, "beides").vorbereitung == false && eintrag(s, "beides").istTermin, "gelöst, Termin bleibt")
        s.vorbereitungUmschalten("beides")
        #expect(try eintrag(s, "beides").vorbereitung == false, "setzen am Termin bleibt ohne Wirkung")
    }

    @Test("Blatt übernehmen neben einem Termin aus einer fremden Datei (H1-01): Termin und Vorbereitung bleiben, ohne Rückfrage")
    func blattNebenTermin() throws {
        var planung = Planung.leer(titel: "Merkmal", start: try #require(Tag(iso: "2026-08-10")), wochen: 6, basis: "",
                                   klassen: Standardkurse.aufbauen([("G8b", "Chemie")]), fachfarben: [:])
        var beides = Vorhaben(id: "beides", klasseId: try #require(planung.klassen.first?.id), woche: 1,
                              titel: "Elterngespräch vorbereiten", text: "", erledigt: false, materialien: [], links: [])
        beides.termin = "m-1"
        beides.datum = Tag(iso: "2026-08-19")
        beides.vorbereitung = true
        planung.eintraege = [beides]
        let s = Planungsspeicher(vorschau: planung)
        s.vorhabenOeffnen(id: "beides")
        var e = try #require(s.vorhabenDialog)
        #expect(e.termin && e.vorbereitung && e.alsTermin, "der bestehende Termin bleibt ein Termin")
        e.titel = "Elterngespräch: Unterlagen bereitlegen"
        s.vorhabenSichernFragen(e)
        #expect(s.rueckfrage == nil, "keine Rückfrage zum Löschen eines Termins")
        let nachher = try eintrag(s, "beides")
        #expect(nachher.titel == "Elterngespräch: Unterlagen bereitlegen", "übernommen")
        #expect(nachher.termin == "m-1" && nachher.vorbereitung, "Termin und Vorbereitung bleiben")
    }

    @Test("Kopieren und neues Schuljahr: Die Vorbereitung bleibt wie die Korrektur")
    func kopie() throws {
        let s = try speicher()
        s.vorbereitungUmschalten("vorbereitung")
        s.dringlichUmschalten("vorbereitung")
        let neuesJahr = try eintrag(s, "vorbereitung").uebernommen(klasseId: "neu", woche: 0, basis: "")
        #expect(neuesJahr.vorbereitung && !neuesJahr.dringend, "ins neue Schuljahr wie die Korrektur — dringlich fällt")
        let klasse = try eintrag(s, "vorbereitung").klasseId
        s.anwaehlen(vorhaben: "vorbereitung")
        s.kopieren()
        s.anwaehlen(zelle: Zellenort(klasse: klasse, woche: 5))
        s.einfuegen()
        let kopien = s.planung?.eintraege.filter { $0.woche == 5 } ?? []
        #expect(kopien.count == 1 && kopien.first?.vorbereitung == true && kopien.first?.id != "vorbereitung")
    }

    // ── Darstellung (BE5) ─────────────────────────────────────────────────

    @Test("Die Kachel: eine Zeile „Vorbereitung“ am Platz der Prüfungszeile — gleich hoch; vor einem Termin (E1080)")
    func kachel() throws {
        let s = try speicher()
        s.vorbereitungUmschalten("vorbereitung")
        let planung = try #require(s.planung)
        let daten = Rasterdaten(planung, stand: 1, breite: 280)
        let vorbereitung = try #require(daten.kacheln(zeile: 0, woche: 0).first)
        let pruefung = try #require(daten.kacheln(zeile: 0, woche: 1).first)
        #expect(vorbereitung.istVorbereitung && !vorbereitung.istKorrektur && !vorbereitung.istPruefung)
        #expect(vorbereitung.gesetzteVorbereitung?.string == "Vorbereitung")
        #expect(vorbereitung.gesetzteKorrektur == nil && vorbereitung.gesetztePruefung == nil
                && vorbereitung.gesetzterTermin == nil)
        #expect(pruefung.gesetzteVorbereitung == nil)
        var gleich = try eintrag(s, "vorbereitung")
        gleich.titel = try eintrag(s, "arbeit").titel
        #expect(Zellenmass.kachelhoehe(gleich, breite: 280) == Zellenmass.kachelhoehe(try eintrag(s, "arbeit"), breite: 280))
        var ohne = gleich
        ohne.vorbereitung = false
        #expect(Zellenmass.kachelhoehe(gleich, breite: 280) > Zellenmass.kachelhoehe(ohne, breite: 280))
        // Aus einer fremden Datei mit Termin (E1080): eine Zeile, die der Vorbereitung.
        var mitTermin = try eintrag(s, "termin")
        mitTermin.vorbereitung = true
        var nurDiese = planung
        nurDiese.eintraege = [mitTermin]
        let beides = try #require(Rasterdaten(nurDiese, stand: 1, breite: 280).kacheln(zeile: 0, woche: 3).first)
        #expect(beides.gesetzteVorbereitung != nil && beides.gesetzterTermin == nil)
        let ansicht = Kachelansicht(frame: .zero)
        ansicht.setzen(vorbereitung, ton: Farbwelt.ton(planung.klassen[0].farbe), angewaehlt: false, griffe: .init())
        #expect(ansicht.accessibilityLabel()?.contains(", Vorbereitung") == true)
        #expect(ansicht.accessibilityLabel()?.contains("Korrektur") == false)
    }

    @Test("Rechtsklick: Vorbereitung zwischen dringlich und Korrektur — was sich ausschließt, ist gesperrt; Lösen nie")
    func rechtsklick() throws {
        let s = try speicher()
        func zeilen(_ id: String) throws -> [Rasterkoordinator.Merkmalzeile] {
            Rasterkoordinator.merkmalzeilen(try eintrag(s, id))
        }
        #expect(try zeilen("vorbereitung").map(\.merkmal) == [.dringlich, .vorbereitung, .korrektur, .pruefung, .termin])
        let zeile = try #require(try zeilen("vorbereitung").first { $0.merkmal == .vorbereitung })
        #expect(zeile.aus == "Als Vorbereitung kennzeichnen" && zeile.ein == "Nicht mehr als Vorbereitung führen")
        #expect(try zeilen("vorbereitung").allSatisfy { !$0.gesperrt && !$0.gesetzt }, "ein gewöhnliches Vorhaben: alles frei")
        #expect(try zeilen("arbeit").map(\.gesperrt) == [false, true, true, false, true], "an der Prüfung")
        #expect(try zeilen("korrektur").map(\.gesperrt) == [false, true, false, true, true], "an der Korrektur")
        #expect(try zeilen("termin").map(\.gesperrt) == [false, true, true, true, false], "am Termin")
        s.vorbereitungUmschalten("vorbereitung")
        #expect(try zeilen("vorbereitung").map(\.gesperrt) == [false, false, true, true, true], "an der Vorbereitung")
        #expect(try zeilen("vorbereitung").map(\.gesetzt) == [false, true, false, false, false])
        // Neben einem Termin aus einer fremden Datei (E1080): Lösen bleibt frei (Z-BE3-04) — die Vorbereitung und, seit
        // R-BE8-02, auch der Termin; Korrektur und Prüfung lassen sich nicht setzen.
        var beides = try eintrag(s, "termin")
        beides.vorbereitung = true
        #expect(Rasterkoordinator.merkmalzeilen(beides).map(\.gesperrt) == [false, false, true, true, false])
    }

    @Test("Das Blau (E1078): hell #0062CC, dunkel #409CFF")
    func farbe() throws {
        func srgb(_ name: NSAppearance.Name) throws -> [Int] {
            let erscheinung = try #require(NSAppearance(named: name))
            var werte: [Int] = []
            erscheinung.performAsCurrentDrawingAppearance {
                if let c = Rasterfarben.vorbereitung.usingColorSpace(.sRGB) {
                    werte = [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
                }
            }
            return werte
        }
        #expect(try srgb(.aqua) == [0, 98, 204])
        #expect(try srgb(.darkAqua) == [64, 156, 255])
    }

    @Test("Einzug der Kachel (E1082): eine Zeile über dem Titel bei Prüfung, Korrektur, Vorbereitung und Termin — genau eine")
    func einzug() throws {
        let s = try speicher()
        let planung = try #require(s.planung)
        func ende(_ vorhaben: Vorhaben) throws -> CGFloat {
            var nur = planung
            nur.eintraege = [vorhaben]
            let stand = try #require(Rasterdaten(nur, stand: 1, breite: 280).kacheln(zeile: 0, woche: vorhaben.woche).first)
            let ansicht = Kachelansicht(frame: NSRect(x: 0, y: 0, width: 280 - Zellenmass.polsterZelle * 2, height: stand.hoehe))
            ansicht.setzen(stand, ton: Farbwelt.ton(planung.klassen[0].farbe), angewaehlt: false, griffe: .init())
            ansicht.layout()
            return ansicht.inhaltsende
        }
        let zeile = Zellenmass.hoehePruefungszeile + Zellenmass.abstandPruefung
        var schlicht = try eintrag(s, "vorbereitung")
        let ohne = try ende(schlicht)
        var pruefung = schlicht; pruefung.pruefung = true
        var korrektur = schlicht; korrektur.korrektur = true
        var vorbereitung = schlicht; vorbereitung.vorbereitung = true
        var termin = schlicht; termin.termin = "m-1"
        var beides = vorbereitung; beides.termin = "m-1"
        for (name, v) in [("Prüfung", pruefung), ("Korrektur", korrektur), ("Vorbereitung", vorbereitung),
                          ("Termin", termin), ("Vorbereitung mit Termin", beides)] {
            #expect(try ende(v) - ohne == zeile, Comment(rawValue: name))
        }
        schlicht.dringend = true
        #expect(try ende(schlicht) == ohne, "dringlich trägt keine Zeile")
    }

    @Test("Blatt, Heute-Blatt, Druck (Z-BE5-03): Sperre des Schalters, Folge der Marken, Rahmen und Termin im Druck")
    func blattHeuteDruck() throws {
        let s = try speicher()
        #expect(try VorhabenEntwurf(eintrag(s, "arbeit")).vorbereitungGesperrt, "an der Prüfung")
        #expect(try VorhabenEntwurf(eintrag(s, "korrektur")).vorbereitungGesperrt, "an der Korrektur")
        #expect(try VorhabenEntwurf(eintrag(s, "termin")).vorbereitungGesperrt, "am Termin")
        #expect(try !VorhabenEntwurf(eintrag(s, "vorbereitung")).vorbereitungGesperrt, "frei")
        var beides = try eintrag(s, "termin")
        beides.vorbereitung = true
        #expect(!VorhabenEntwurf(beides).vorbereitungGesperrt, "Lösen frei, auch neben einem Termin (E1080)")

        var v = try eintrag(s, "vorbereitung")
        #expect(HeuteDialog.merkmalwoerter(v).isEmpty)
        v.vorbereitung = true
        v.dringend = true
        #expect(HeuteDialog.merkmalwoerter(v) == ["dringlich", "Vorbereitung"], "die Folge des Blatts")
        #expect(HeuteDialog.merkmalwoerter(try eintrag(s, "korrektur")) == ["Korrektur"])

        #expect(Druckraster.gestrichelterRahmen(v) == nil, "dringlich geht vor")
        v.dringend = false
        #expect(Druckraster.gestrichelterRahmen(v) == Rasterfarben.vorbereitung)
        #expect(Druckraster.gestrichelterRahmen(try eintrag(s, "korrektur")) == Rasterfarben.pruefung)
        #expect(Druckraster.gestrichelterRahmen(try eintrag(s, "arbeit")) == nil)
        #expect(Druckraster.zeigtTermin(try eintrag(s, "termin")))
        #expect(!Druckraster.zeigtTermin(beides), "neben der Vorbereitung nennt der Druck den Termin nicht (E1080)")
    }
}
