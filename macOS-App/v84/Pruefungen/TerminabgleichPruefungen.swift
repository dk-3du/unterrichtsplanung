// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Termin ↔ Vorhaben: Kopplung und Abgleich (v80, AP13c-1, E291/E293) ────
// Die Kennung des Termins steht am Vorhaben, der Rückverweis am Termin; Tag,
// Uhrzeit, Titel und Stand laufen in beide Richtungen; verschoben bleibt der
// Wochentag; gelöscht gehen immer beide. Reine Funktionen am Wert.

@Suite("Termin ↔ Vorhaben: Felder, Abgleich in beide Richtungen, Verschieben, Löschen")
struct TerminabgleichPruefungen {

    private static let herkunft = "2026-08-01T09:00:00.000Z"
    private static let stempel = "2026-10-04T08:00:00.000Z"

    /// Zehn Wochen ab Montag, 3. August 2026: 6a, Klassenleitung · 6a, Weiteres.
    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: [], fachfarben: [:])
        p.erstellt = Self.herkunft
        var unterricht = Klasse.sonderzeile(.klassenleitung)
        unterricht.id = "k-6a"; unterricht.name = "6a"; unterricht.art = .unterricht
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.id = "k-kl"
        leitung.fach = "6a"
        var weiteres = Klasse.sonderzeile(.weiteres)
        weiteres.id = "k-we"
        p.klassen = [unterricht, leitung, weiteres]
        return p
    }

    /// Anna (l-1) in der Lerngruppe „6a“, verknüpft mit „6a“ und „Klassenleitung · 6a“; Ben (l-2) in „6b“, ohne
    /// Klassenleitung (E686); ein Termin m-1 für Anna am Donnerstag, 20. August (Woche 2), 07:45.
    private func bestand() -> Lernendenbestand {
        let s = Self.stempel
        var b = Lernendenbestand.leer(planung: Self.herkunft, schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-2", vorname: "Ben", nachname: "Bauer", angelegt: s, geaendert: s, archiviert: "")]
        b.lerngruppen = [
            Lerngruppe(id: "g-1", name: "6a", art: .klasse, mitglieder: ["l-1"],
                       zeilen: [Zeilenbindung(planung: Self.herkunft, klasseId: "k-6a"),
                                Zeilenbindung(planung: Self.herkunft, klasseId: "k-kl")], skalen: [:],
                       halbjahreswechsel: "", geaendert: s, archiviert: ""),
            Lerngruppe(id: "g-6b", name: "6b", art: .klasse, mitglieder: ["l-2"], zeilen: [], skalen: [:],
                       halbjahreswechsel: "", geaendert: s, archiviert: ""),
        ]
        b.anliegen = [Anliegen(id: "m-1", art: .termin, titel: "Elterngespräch", lerngruppe: "", betroffene: ["l-1"],
                               datum: "2026-08-20", frist: "", uhrzeit: "07:45", notiz: "", angelegt: s, geaendert: s)]
        return b
    }

    /// Das Vorhaben zum Termin m-1 in der Klassenleitung.
    private func gekoppelt() throws -> (Planung, Lernendenbestand) {
        var p = try planung()
        p.eintraege = [Vorhaben(id: "e-1", klasseId: "k-kl", woche: 2, titel: "Elterngespräch", text: "", erledigt: false,
                                materialien: [], links: [], datum: Tag(iso: "2026-08-20"),
                                termin: "m-1", terminzeit: "07:45")]
        var b = bestand()
        b.anliegen[0].planung = Self.herkunft
        b.anliegen[0].vorhaben = "e-1"
        return (p, b)
    }

    // ── Die Felder ────────────────────────────────────────────────────────

    @Test("Vorhaben: termin und terminzeit hin und zurück, nur geschrieben, wo gesetzt; fremde Formen leer; doppelt gilt das erste")
    func vorhabenfelder() throws {
        var (p, _) = try gekoppelt()
        p.eintraege.append(Vorhaben(id: "e-2", klasseId: "k-6a", woche: 0, titel: "Bruchrechnung", text: "", erledigt: false,
                                    materialien: [], links: []))
        let daten = try Planungsdatei.schreiben(p)
        // Die Vorhaben — die Farben der Zeilen vergibt der Leser beim ersten Lesen.
        #expect(try Planungsdatei.lesen(daten).eintraege == p.eintraege)
        let objekt = try #require(JSONSerialization.jsonObject(with: daten) as? [String: Any])
        let eintraege = try #require(objekt["eintraege"] as? [[String: Any]])
        #expect(eintraege[0]["termin"] as? String == "m-1" && eintraege[0]["terminzeit"] as? String == "07:45")
        #expect(eintraege[1]["termin"] == nil && eintraege[1]["terminzeit"] == nil, "nur, wo gesetzt")
        #expect(!String(decoding: daten, as: UTF8.self).contains("Anna"), "kein Name in planung.json")

        var fremd = objekt
        var e = eintraege
        e[0]["terminzeit"] = "7:45"
        e[1]["termin"] = "/böse"
        e[1]["terminzeit"] = "08:00"
        e.append(["id": "e-3", "klasseId": "k-we", "woche": 1, "titel": "Zweites", "termin": "m-1"])
        fremd["eintraege"] = e
        let (gelesen, bilanz) = try Planungsdatei.pruefenMitBilanz(fremd)
        #expect(gelesen.eintraege[0].termin == "m-1" && gelesen.eintraege[0].terminzeit.isEmpty, "Uhrzeit nur in fester Form")
        #expect(gelesen.eintraege[1].termin.isEmpty && gelesen.eintraege[1].terminzeit.isEmpty, "ohne Kennung keine Uhrzeit")
        #expect(gelesen.eintraege[2].termin.isEmpty, "ein Termin hat ein Vorhaben — das erste gilt")
        #expect(bilanz.istLeer, "ein Verweis ohne Halt ist kein Verlust an Inhalt")
    }

    @Test("Verschieben: ein Termin behält seinen Wochentag; ohne Termin verfällt das Datum; Kopie und neue Planung lösen den Termin")
    func verschieben() throws {
        let (p, _) = try gekoppelt()
        var v = p.eintraege[0]
        let verfallen = v.wocheWechseln(nach: 4)
        #expect(!verfallen, "kein Datum verfallen")
        #expect(v.woche == 4 && v.datum == Tag(iso: "2026-09-03") && v.datum?.wochentag == .donnerstag)
        var ohne = p.eintraege[0]
        ohne.termin = ""
        let ohneVerfallen = ohne.wocheWechseln(nach: 4)
        #expect(ohneVerfallen && ohne.datum == nil, "wie bisher")
        var kopie = p.eintraege[0]
        let kopieVerfallen = kopie.datumVerwerfen()
        #expect(kopieVerfallen)
        #expect(kopie.termin.isEmpty && kopie.terminzeit.isEmpty && kopie.datum == nil, "eine Kopie ist kein Termin")
        let neu = p.eintraege[0].uebernommen(klasseId: "k-x", woche: 0, basis: "")
        #expect(neu.termin.isEmpty && neu.terminzeit.isEmpty)
    }

    @Test("Termin: Rückverweis hin und zurück, nur am Termin und nur, wo gesetzt; der Schuljahreswechsel löst ihn")
    func rueckverweis() throws {
        let (_, b) = try gekoppelt()
        let daten = try Lernendendatei.schreiben(b)
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(daten)
        #expect(gelesen == b && bilanz.istLeer)
        var mit = b
        mit.anliegen.append(Anliegen(id: "m-2", art: .massnahme, titel: "Heft", lerngruppe: "", betroffene: ["l-2"],
                                     datum: "", frist: "", notiz: "", angelegt: "", geaendert: ""))
        let objekt = try #require(JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(mit)) as? [String: Any])
        var anliegen = try #require(objekt["anliegen"] as? [[String: Any]])
        #expect(anliegen[0]["vorhaben"] as? String == "e-1" && anliegen[0]["planung"] as? String == Self.herkunft)
        #expect(anliegen[1]["vorhaben"] == nil && anliegen[1]["planung"] == nil, "nur, wo gesetzt")

        anliegen[1]["vorhaben"] = "e-9"
        anliegen[1]["planung"] = Self.herkunft
        anliegen[0]["vorhaben"] = "/böse"
        var fremd = objekt
        fremd["anliegen"] = anliegen
        let (b2, bilanz2) = try Lernendendatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: fremd))
        #expect(b2.anliegen[0].vorhaben.isEmpty && b2.anliegen[0].planung.isEmpty, "fremde Form: beides geleert")
        #expect(b2.anliegen[1].vorhaben.isEmpty && b2.anliegen[1].planung.isEmpty, "nur ein Termin trägt ihn")
        #expect(bilanz2.bereinigteBezuege == 2)

        let neu = b.neuesJahr(gruppen: ["g-1"], zuordnung: [:], planung: "H2", schuljahr: "2027/28", jetzt: Self.stempel)
        #expect(neu.anliegen.map(\.id) == ["m-1"] && neu.anliegen[0].vorhaben.isEmpty && neu.anliegen[0].planung.isEmpty,
                "der Termin wandert ohne sein Vorhaben")
    }

    // ── Hilfen ────────────────────────────────────────────────────────────

    @Test("Woche eines Tags in der Planung; vorbelegte Zeile: Klassenleitung der Person, sonst Weiteres")
    func woecheUndZeile() throws {
        let p = try planung()
        #expect(Terminabgleich.woche(von: try #require(Tag(iso: "2026-08-03")), in: p) == 0)
        #expect(Terminabgleich.woche(von: try #require(Tag(iso: "2026-08-20")), in: p) == 2)
        #expect(Terminabgleich.woche(von: try #require(Tag(iso: "2026-10-11")), in: p) == 9)
        #expect(Terminabgleich.woche(von: try #require(Tag(iso: "2026-10-12")), in: p) == nil)
        #expect(Terminabgleich.woche(von: try #require(Tag(iso: "2026-08-02")), in: p) == nil)
        let b = bestand()
        #expect(Terminabgleich.vorbelegteZeile(fuer: "l-1", planung: p, bestand: b) == "k-kl")
        #expect(Terminabgleich.vorbelegteZeile(fuer: "l-2", planung: p, bestand: b) == "k-we")
        var ohneWeiteres = p
        ohneWeiteres.klassen.removeAll { $0.id == "k-we" }
        #expect(Terminabgleich.vorbelegteZeile(fuer: "l-2", planung: ohneWeiteres, bestand: b) == nil)
    }

    // ── Planung → Jahresdatei ─────────────────────────────────────────────

    @Test("Planung → Termin: Tag, Uhrzeit, Titel und Haken ziehen den Termin nach; der Rückverweis wird gesetzt")
    func ausPlanung() throws {
        var (p, b) = try gekoppelt()
        b.anliegen[0].vorhaben = ""
        b.anliegen[0].planung = ""
        #expect(Terminabgleich.ausPlanung(p, b, jetzt: Self.stempel).anliegen[0].vorhaben == "e-1", "Rückverweis gesetzt")
        _ = p.eintraege[0].wocheWechseln(nach: 3)
        p.eintraege[0].terminzeit = "08:15"
        p.eintraege[0].titel = "Gespräch mit den Eltern"
        p.eintraege[0].erledigt = true
        let n = Terminabgleich.ausPlanung(p, b, jetzt: Self.stempel)
        let t = n.anliegen[0]
        #expect(t.datum == "2026-08-27" && t.uhrzeit == "08:15" && t.titel == "Gespräch mit den Eltern" && t.geaendert == Self.stempel)
        #expect(Lernendenverzeichnis(n).stand("m-1", "l-1") == .erledigt, "der Haken setzt „stattgefunden“")
        #expect(n.rueckmeldungen.first?.datum == "2026-10-04")
        #expect(Terminabgleich.ausPlanung(p, n, jetzt: "2026-10-05T08:00:00.000Z") == n, "ein zweiter Lauf ändert nichts")

        p.eintraege[0].erledigt = false
        let zurueck = Terminabgleich.ausPlanung(p, n, jetzt: Self.stempel)
        #expect(Lernendenverzeichnis(zurueck).stand("m-1", "l-1") == .offen, "ohne Haken wieder offen")
        let abgesagt = n.mitRuecklauf("m-1", "l-1", stand: .abgelehnt, datum: "2026-08-19", notiz: "", jetzt: Self.stempel)
        #expect(Lernendenverzeichnis(Terminabgleich.ausPlanung(p, abgesagt, jetzt: Self.stempel)).stand("m-1", "l-1") == .abgelehnt,
                "„abgesagt“ bleibt ohne Haken")
    }

    @Test("Planung → Termin: Fremde Herkunft, eine Maßnahme statt eines Termins und Unverbundenes bleiben unberührt")
    func ausPlanungUnberuehrt() throws {
        var (p, b) = try gekoppelt()
        p.eintraege[0].titel = "Neu"
        var fremd = b
        fremd.planung = "2025-08-01T09:00:00.000Z"
        #expect(Terminabgleich.ausPlanung(p, fremd, jetzt: Self.stempel) == fremd)
        var massnahme = b
        massnahme.anliegen[0].art = .massnahme
        #expect(Terminabgleich.ausPlanung(p, massnahme, jetzt: Self.stempel) == massnahme)
        p.eintraege[0].termin = ""
        #expect(Terminabgleich.ausPlanung(p, b, jetzt: Self.stempel) == b)
    }

    @Test("Verwaist: Ein Termin mit Rückverweis, dessen Vorhaben fehlt, wird erkannt und gelöst — nicht gelöscht")
    func verwaist() throws {
        var (p, b) = try gekoppelt()
        #expect(Terminabgleich.verwaiste(p, b).isEmpty)
        p.eintraege = []
        #expect(Terminabgleich.verwaiste(p, b) == ["m-1"])
        let geloest = Terminabgleich.ohneRueckverweis(["m-1"], b)
        #expect(geloest.anliegen.map(\.id) == ["m-1"] && geloest.anliegen[0].vorhaben.isEmpty && geloest.anliegen[0].planung.isEmpty)
    }

    // ── Jahresdatei → Planung (beim Übernehmen des Blatts) ───────────────

    @Test("Termin → Planung: Ein neuer Termin mit Wunsch bekommt sein Vorhaben in der gewählten Zeile, ohne Namen")
    func neuerTermin() throws {
        let p = try planung()
        let vorher = bestand()
        let (nachher, id) = try #require(vorher.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "",
                                                                 betroffene: ["l-2"], datum: "2026-09-10", frist: "",
                                                                 uhrzeit: "14:00", jetzt: Self.stempel))
        let u = Terminabgleich.inPlanung(p, vorher: vorher, nachher: nachher, wuensche: [id: "k-we"], jetzt: Self.stempel)
        let v = try #require(u.planung.eintraege.first { $0.termin == id })
        #expect(v.klasseId == "k-we" && v.woche == 5 && v.datum == Tag(iso: "2026-09-10") && v.terminzeit == "14:00")
        #expect(v.titel == "Elterngespräch" && !v.erledigt && Kennung.istGueltig(v.id))
        let t = try #require(u.bestand.anliegen.first { $0.id == id })
        #expect(t.vorhaben == v.id && t.planung == Self.herkunft)
        #expect(u.entfernt.isEmpty && u.ausserhalb == 0)
        #expect(!String(decoding: try Planungsdatei.schreiben(u.planung), as: UTF8.self).contains("Bauer"))
        #expect(u.planung.eintraege.count == 1, "der Termin m-1 ohne Wunsch bleibt ohne Vorhaben")
    }

    @Test("Termin → Planung: außerhalb der Planung kein Vorhaben, gezählt; eine Zeile, die es nicht gibt, auch nicht")
    func neuerTerminAusserhalb() throws {
        let p = try planung()
        let vorher = bestand()
        let (nachher, id) = try #require(vorher.mitNeuemAnliegen(.termin, titel: "Spät", lerngruppe: "", betroffene: ["l-2"],
                                                                 datum: "2026-12-01", frist: "", jetzt: Self.stempel))
        let u = Terminabgleich.inPlanung(p, vorher: vorher, nachher: nachher, wuensche: [id: "k-we"], jetzt: Self.stempel)
        #expect(u.planung == p && u.ausserhalb == 1 && u.bestand.anliegen.last?.vorhaben == "")
        let (nachher2, id2) = try #require(vorher.mitNeuemAnliegen(.termin, titel: "X", lerngruppe: "", betroffene: ["l-2"],
                                                                   datum: "2026-09-10", frist: "", jetzt: Self.stempel))
        #expect(Terminabgleich.inPlanung(p, vorher: vorher, nachher: nachher2, wuensche: [id2: "k-zz"], jetzt: Self.stempel)
                    .planung == p)
    }

    @Test("Termin → Planung: Tag, Uhrzeit, Titel und Stand ziehen das Vorhaben nach; „stattgefunden“ setzt den Haken mit Stempel")
    func geaenderterTermin() throws {
        let (p, vorher) = try gekoppelt()
        var nachher = vorher.mitAnliegen("m-1", titel: "Gespräch", datum: "2026-09-08", frist: "", notiz: "",
                                         uhrzeit: "09:30", jetzt: Self.stempel)
        nachher = nachher.mitRuecklauf("m-1", "l-1", stand: .erledigt, datum: "2026-09-08", notiz: "", jetzt: Self.stempel)
        let u = Terminabgleich.inPlanung(p, vorher: vorher, nachher: nachher, wuensche: [:], jetzt: Self.stempel)
        let v = u.planung.eintraege[0]
        #expect(v.woche == 5 && v.datum == Tag(iso: "2026-09-08") && v.terminzeit == "09:30" && v.titel == "Gespräch")
        #expect(v.erledigt && v.statusGeaendert == Self.stempel)
        #expect(Terminabgleich.inPlanung(p, vorher: vorher, nachher: vorher, wuensche: [:], jetzt: Self.stempel).planung == p,
                "ohne Änderung keine")
        let weg = vorher.mitAnliegen("m-1", titel: "Gespräch", datum: "2026-12-01", frist: "", notiz: "", jetzt: Self.stempel)
        let draussen = Terminabgleich.inPlanung(p, vorher: vorher, nachher: weg, wuensche: [:], jetzt: Self.stempel)
        #expect(draussen.ausserhalb == 1 && draussen.planung.eintraege[0].datum == Tag(iso: "2026-08-20"),
                "außerhalb der Planung bleibt das Vorhaben stehen")
    }

    @Test("Ein verbundener Termin außerhalb der Planung behält den Tag seines Vorhabens — auch in der Jahresdatei (W1-03)")
    func ausserhalbBehaeltTag() throws {
        let (p, vorher) = try gekoppelt()
        let weg = vorher.mitAnliegen("m-1", titel: "Gespräch", datum: "2026-12-01", frist: "", notiz: "", jetzt: Self.stempel)
        let u = Terminabgleich.inPlanung(p, vorher: vorher, nachher: weg, wuensche: [:], jetzt: Self.stempel)
        #expect(u.ausserhalb == 1 && u.planung.eintraege[0].datum == Tag(iso: "2026-08-20"))
        #expect(u.bestand.anliegen[0].datum == "2026-08-20", "der Termin folgt seinem Vorhaben")
        #expect(u.bestand.anliegen[0].titel == "Gespräch", "das Übrige bleibt")
    }

    @Test("Stand der Sitzung (offener Punkt 3, Z14c-06): Eine im Blatt gelöschte Person macht den Termin nicht „angefasst“")
    func geloeschtePersonFasstNichtAn() throws {
        var (_, a) = try gekoppelt()
        a.anliegen[0].betroffene = ["l-1", "l-2"]
        let sitzung = a.mitRuecklauf("m-1", "l-1", stand: .erledigt, datum: "2026-08-20", notiz: "", jetzt: Self.stempel)
            .mitRuecklauf("m-1", "l-2", stand: .erledigt, datum: "2026-08-20", notiz: "", jetzt: Self.stempel)
        let entwurf = a.ohnePerson("l-2").bestand
        let neu = Terminabgleich.mitStandDerSitzung(entwurf, ausgang: a, sitzung: sitzung)
        #expect(neu.anliegen.first { $0.id == "m-1" }?.betroffene == ["l-1"])
        #expect(Lernendenverzeichnis(neu).stand("m-1", "l-1") == .erledigt, "Annas Stand aus der Sitzung bleibt")
    }

    @Test("Ein Termin ohne Betroffene (nach bereinigtem Lesen) nimmt dem Vorhaben den Haken nicht (Z14a-06)")
    func ohneBetroffeneBleibtHaken() throws {
        var (p, b) = try gekoppelt()
        b.anliegen[0].betroffene = []
        p.eintraege[0].erledigt = true
        let u = Terminabgleich.inPlanung(p, vorher: b, nachher: b, wuensche: [:], jetzt: Self.stempel)
        #expect(u.planung.eintraege[0].erledigt, "der Haken bleibt")
    }

    @Test("Gemischter Stand (E298): Nur der Wechsel des Hakens wirkt — „stattgefunden“ neben „offen“ oder „abgesagt“ bleibt")
    func gemischterStand() throws {
        var (p, b) = try gekoppelt()
        b.anliegen[0].betroffene = ["l-1", "l-2"]
        var gemischt = b.mitRuecklauf("m-1", "l-1", stand: .erledigt, datum: "2026-08-20", notiz: "", jetzt: Self.stempel)
        var n = Terminabgleich.ausPlanung(p, gemischt, jetzt: Self.stempel)
        #expect(Lernendenverzeichnis(n).stand("m-1", "l-1") == .erledigt, "„stattgefunden“ neben „offen“ bleibt")
        gemischt = gemischt.mitRuecklauf("m-1", "l-2", stand: .abgelehnt, datum: "2026-08-20", notiz: "", jetzt: Self.stempel)
        n = Terminabgleich.ausPlanung(p, gemischt, jetzt: Self.stempel)
        #expect(Lernendenverzeichnis(n).stand("m-1", "l-1") == .erledigt && Lernendenverzeichnis(n).stand("m-1", "l-2") == .abgelehnt,
                "neben „abgesagt“ ebenso")
        p.eintraege[0].erledigt = true
        n = Terminabgleich.ausPlanung(p, gemischt, jetzt: Self.stempel)
        #expect(["l-1", "l-2"].allSatisfy { Lernendenverzeichnis(n).stand("m-1", $0) == .erledigt }, "der gesetzte Haken setzt alle")
        p.eintraege[0].erledigt = false
        let ohne = Terminabgleich.ausPlanung(p, n, jetzt: Self.stempel)
        #expect(["l-1", "l-2"].allSatisfy { Lernendenverzeichnis(ohne).stand("m-1", $0) == .offen },
                "der entfernte Haken nimmt „stattgefunden“")
        #expect(Terminabgleich.ausPlanung(p, ohne, jetzt: Self.stempel) == ohne, "ein zweiter Abgleich ändert nichts")
    }

    @Test("Termin gelöscht: Sein Vorhaben geht mit (immer beide), die Kennung wird genannt")
    func geloeschterTermin() throws {
        let (p, vorher) = try gekoppelt()
        let nachher = vorher.ohneAnliegen("m-1").bestand
        let u = Terminabgleich.inPlanung(p, vorher: vorher, nachher: nachher, wuensche: [:], jetzt: Self.stempel)
        #expect(u.planung.eintraege.isEmpty && u.entfernt == ["m-1"])
    }

    @Test("Zwischen zwei Ständen derselben Planung: verschwundene und wieder erschienene Verbindungen")
    func verschwundenUndErschienen() throws {
        let (p, _) = try gekoppelt()
        var ohne = p
        ohne.eintraege = []
        #expect(Terminabgleich.verschwunden(von: p, zu: ohne) == ["m-1"] && Terminabgleich.erschienen(von: p, zu: ohne).isEmpty)
        #expect(Terminabgleich.erschienen(von: ohne, zu: p) == ["m-1"] && Terminabgleich.verschwunden(von: ohne, zu: p).isEmpty)
        var andere = ohne
        andere.erstellt = "2027-08-01T09:00:00.000Z"
        #expect(Terminabgleich.verschwunden(von: p, zu: andere).isEmpty, "eine andere Planung ist kein Löschen")
    }
}
