// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die personenbezogene Ebene der Jahresdatei (v80, AP13b, E289/E290) ────
// Eine Identität je Person; je Gruppe getrennt, was zum Unterricht gehört
// (Leistungen, Beurteilung), gemeinsam Arbeits- und Sozialverhalten, Notizen
// ohne Gruppe und Anliegen ohne Gruppe — Maßnahmen und Termine.

@Suite("Personenebene: Verhalten, Leistungen, Beurteilung, Notizen und Termine ohne Gruppe")
struct PersonenebenePruefungen {

    private static let herkunft = "2026-08-10T09:00:00.000Z"
    private static let stempel = "2026-10-04T08:00:00.000Z"

    /// Anna (l-1) in der Klasse 6a (g-1) und im Kurs Informatik (g-2), Ben
    /// (l-2) nur in 6a. Je Person einmal Verhalten; Leistungen je Gruppe,
    /// darunter das Ergebnis einer Klassenarbeit mit Verweis aufs Vorhaben;
    /// eine Beurteilung; eine Notiz ohne Gruppe; ein Termin ohne Gruppe nur
    /// für Anna (stattgefunden) und eine Maßnahme ohne Gruppe für Ben.
    private func bestand() -> Lernendenbestand {
        let s = Self.stempel
        var b = Lernendenbestand.leer(planung: Self.herkunft, schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-2", vorname: "Ben", nachname: "Bauer", angelegt: s, geaendert: s, archiviert: "")]
        b.lerngruppen = [
            Lerngruppe(id: "g-1", name: "6a", art: .klasse, mitglieder: ["l-1", "l-2"], zeilen: [],
                       skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: ""),
            Lerngruppe(id: "g-2", name: "6 Inf", art: .kurs, mitglieder: ["l-1"], zeilen: [],
                       skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: ""),
        ]
        b.anliegen = [
            Anliegen(id: "m-1", art: .termin, titel: "Elterngespräch", lerngruppe: "", betroffene: ["l-1"],
                     datum: "2026-10-20", frist: "", uhrzeit: "07:45", notiz: "mit der Mutter", angelegt: s, geaendert: s),
            Anliegen(id: "m-2", art: .massnahme, titel: "Heft nachreichen", lerngruppe: "", betroffene: ["l-2"],
                     datum: "2026-10-04", frist: "2026-10-11", notiz: "", angelegt: s, geaendert: s),
        ]
        b.rueckmeldungen = [Rueckmeldung(anliegen: "m-1", lernender: "l-1", stand: .erledigt, datum: "2026-10-20",
                                         notiz: "", geaendert: s)]
        b.erfassung = [Erfassungseintrag(id: "a-1", lernender: "l-1", lerngruppe: "", planung: "", vorhaben: "",
                                         datum: "2026-10-02", art: .frei, wert: "", notiz: "Hat ein Geschwisterkind bekommen.",
                                         angelegt: s, geaendert: s)]
        b.beurteilung = [Beurteilung(id: "b-1", lernender: "l-1", lerngruppe: "g-1", schuljahr: "2026/27", halbjahr: 1,
                                     zeugnisnote: "2", notiz: "", geaendert: s)]
        b.verhalten = [Verhalten(id: "v-1", lernender: "l-1", schuljahr: "2026/27", halbjahr: 1,
                                 arbeitsverhalten: "B", sozialverhalten: "A", notiz: "", geaendert: s)]
        b.leistungen = [
            Leistung(id: "n-1", lernender: "l-1", lerngruppe: "g-1", schuljahr: "2026/27", halbjahr: 1, art: .muendlich,
                     titel: "Mündlich bis zu den Herbstferien", datum: "", wert: "2", notiz: "", planung: "", vorhaben: "",
                     angelegt: s, geaendert: s),
            Leistung(id: "n-2", lernender: "l-1", lerngruppe: "g-2", schuljahr: "2026/27", halbjahr: 1, art: .schriftlich,
                     titel: "1. Klassenarbeit", datum: "2026-09-30", wert: "3+", notiz: "", planung: Self.herkunft,
                     vorhaben: "e-7", angelegt: s, geaendert: s),
            Leistung(id: "n-3", lernender: "l-1", lerngruppe: "g-1", schuljahr: "2026/27", halbjahr: 1, art: .muendlich,
                     titel: "Referat", datum: "2026-10-01", wert: "1-", notiz: "", planung: "", vorhaben: "",
                     angelegt: s, geaendert: s),
            Leistung(id: "n-4", lernender: "l-2", lerngruppe: "g-1", schuljahr: "2026/27", halbjahr: 1, art: .schriftlich,
                     titel: "Lernkontrolle 1", datum: "2026-09-25", wert: "4", notiz: "", planung: "", vorhaben: "",
                     angelegt: s, geaendert: s),
        ]
        return b
    }

    private func roh() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(bestand())) as? [String: Any])
    }

    private func lesen(_ objekt: [String: Any]) throws -> (bestand: Lernendenbestand, bilanz: Lernendendatei.Bilanz) {
        try Lernendendatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: objekt))
    }

    private func liste(_ objekt: inout [String: Any], _ name: String,
                       _ aendern: (inout [[String: Any]]) -> Void) throws {
        var eintraege = try #require(objekt[name] as? [[String: Any]])
        aendern(&eintraege)
        objekt[name] = eintraege
    }

    // ── Die Datei ─────────────────────────────────────────────────────────

    @Test("Hin und zurück: Verhalten, Leistungen, Beurteilung, Notiz ohne Gruppe, Termin mit Uhrzeit — kanonisch, leere Bilanz")
    func hinUndZurueck() throws {
        let b = bestand()
        let daten = try Lernendendatei.schreiben(b)
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(daten)
        #expect(gelesen == b)
        #expect(bilanz.istLeer, "\(bilanz.beschreibung)")
        #expect(try Lernendendatei.schreiben(gelesen) == daten, "kanonisch")

        let o = try roh()
        let beurteilung = try #require((o["beurteilung"] as? [[String: Any]])?.first)
        #expect(Set(beurteilung.keys) == ["id", "lernender", "lerngruppe", "schuljahr", "halbjahr", "zeugnisnote",
                                          "notiz", "geaendert"], "keine Gesamtnoten, kein Verhalten je Gruppe")
        let verhalten = try #require((o["verhalten"] as? [[String: Any]])?.first)
        #expect(Set(verhalten.keys) == ["id", "lernender", "schuljahr", "halbjahr", "arbeitsverhalten",
                                        "sozialverhalten", "notiz", "geaendert"])
        let leistung = try #require((o["leistungen"] as? [[String: Any]])?.first)
        #expect(Set(leistung.keys) == ["id", "lernender", "lerngruppe", "schuljahr", "halbjahr", "art", "titel", "datum",
                                       "wert", "notiz", "planung", "vorhaben", "angelegt", "geaendert"])
        let anliegen = try #require(o["anliegen"] as? [[String: Any]])
        #expect(anliegen[0]["art"] as? String == "termin" && anliegen[0]["uhrzeit"] as? String == "07:45")
        #expect(anliegen[1]["uhrzeit"] == nil, "die Uhrzeit nur, wo gesetzt")

        let leer = Lernendenbestand.leer(planung: Self.herkunft, schuljahr: "2026/27", jetzt: Self.stempel)
        let leerText = String(decoding: try Lernendendatei.schreiben(leer), as: UTF8.self)
        #expect(leerText.contains("\"verhalten\":[]") && leerText.contains("\"leistungen\":[]"), "stets beide Listen")
    }

    @Test("Dateien aus AP1–AP13 lesen sich weiter: alte Felder der Beurteilung übergangen, neue Listen leer")
    func alteDateien() throws {
        var objekt = try roh()
        objekt["verhalten"] = nil
        objekt["leistungen"] = nil
        try liste(&objekt, "beurteilung") {
            $0[0]["muendlich"] = "2"
            $0[0]["arbeitsverhalten"] = "B"
            $0[0]["sozialverhalten"] = ""
        }
        let (b, bilanz) = try lesen(objekt)
        #expect(b.verhalten.isEmpty && b.leistungen.isEmpty)
        #expect(b.beurteilung.count == 1 && b.beurteilung[0].zeugnisnote == "2")
        #expect(bilanz.istLeer, "\(bilanz.beschreibung)")
    }

    /// Je eine Änderung, je eine vorhergesagte Bilanz — genau.
    @Test("Zwölf verdorbene Einträge der Personenebene ergeben die vorhergesagte Bilanz")
    func verdorbeneEintraege() throws {
        typealias Bilanz = Lernendendatei.Bilanz
        func bilanz(_ setzen: (inout Bilanz) -> Void) -> Bilanz { var b = Bilanz(); setzen(&b); return b }
        let faelle: [(String, (inout [String: Any]) throws -> Void, Bilanz)] = [
            ("Verhalten doppelt im Halbjahr", { o in
                try liste(&o, "verhalten") { $0.append(["id": "v-2", "lernender": "l-1", "schuljahr": "2026/27", "halbjahr": 1]) } },
             bilanz { $0.verworfeneEintraege = 1 }),
            ("Verhalten ohne Person", { o in try liste(&o, "verhalten") { $0[0]["lernender"] = "l-9" } },
             bilanz { $0.verworfeneEintraege = 1 }),
            ("Verhalten im dritten Halbjahr", { o in try liste(&o, "verhalten") { $0[0]["halbjahr"] = 3 } },
             bilanz { $0.verworfeneEintraege = 1 }),
            ("Leistung ohne Gruppe", { o in try liste(&o, "leistungen") { $0[0]["lerngruppe"] = "" } },
             bilanz { $0.verworfeneEintraege = 1 }),
            ("Leistung unbekannter Art", { o in try liste(&o, "leistungen") { $0[0]["art"] = "praktisch" } },
             bilanz { $0.verworfeneEintraege = 1 }),
            ("Leistung mit fremder Kennung des Vorhabens", { o in try liste(&o, "leistungen") { $0[1]["vorhaben"] = "/böse" } },
             bilanz { $0.bereinigteBezuege = 1 }),
            ("Leistung am Tag „morgen“", { o in try liste(&o, "leistungen") { $0[2]["datum"] = "morgen" } },
             bilanz { $0.bereinigteTage = 1 }),
            ("Notiz ohne Gruppe als mündliche Mitarbeit", { o in try liste(&o, "erfassung") { $0[0]["art"] = "muendlich" } },
             bilanz { $0.verworfeneEintraege = 1 }),
            ("Notiz ohne Gruppe mit Wert, Vorhaben und Planung", { o in
                try liste(&o, "erfassung") { $0[0]["wert"] = "+"; $0[0]["vorhaben"] = "e-1"; $0[0]["planung"] = Self.herkunft } },
             bilanz { $0.verworfeneFelder = 1; $0.bereinigteBezuege = 2 }),
            ("Termin ohne Tag samt Rücklauf", { o in try liste(&o, "anliegen") { $0[0]["datum"] = "" } },
             bilanz { $0.verworfeneAnliegen = 1; $0.verworfeneRueckmeldungen = 1 }),
            ("Termin um 25 Uhr", { o in try liste(&o, "anliegen") { $0[0]["uhrzeit"] = "25:00" } },
             bilanz { $0.bereinigteTage = 1 }),
            ("Termin an einer Gruppe, die es nicht gibt", { o in try liste(&o, "anliegen") { $0[0]["lerngruppe"] = "g-9" } },
             bilanz { $0.bereinigteBezuege = 1 }),
        ]
        #expect(faelle.count == 12)
        for (name, aendern, erwartet) in faelle {
            var objekt = try roh()
            try aendern(&objekt)
            let (_, bilanz) = try lesen(objekt)
            #expect(bilanz == erwartet, "\(name): \(bilanz.beschreibung)")
        }
    }

    @Test("Was die Bilanz zählt, ist geschehen: Das erste Verhalten bleibt, die Notiz ohne Wert und Bezug, der Termin ohne Gruppe")
    func bilanzStimmtMitInhalt() throws {
        var objekt = try roh()
        try liste(&objekt, "verhalten") {
            $0.append(["id": "v-2", "lernender": "l-1", "schuljahr": "2026/27", "halbjahr": 1, "arbeitsverhalten": "E"])
        }
        try liste(&objekt, "erfassung") { $0[0]["wert"] = "+"; $0[0]["vorhaben"] = "e-1"; $0[0]["planung"] = Self.herkunft }
        try liste(&objekt, "anliegen") { $0[0]["lerngruppe"] = "g-9"; $0[0]["uhrzeit"] = "7:45" }
        let (b, bilanz) = try lesen(objekt)
        #expect(b.verhalten.map(\.id) == ["v-1"] && b.verhalten[0].arbeitsverhalten == "B")
        #expect(b.erfassung[0].wert.isEmpty && b.erfassung[0].vorhaben.isEmpty && b.erfassung[0].planung.isEmpty)
        #expect(b.erfassung[0].notiz == "Hat ein Geschwisterkind bekommen.")
        #expect(b.anliegen[0].art == .termin && b.anliegen[0].lerngruppe.isEmpty)
        #expect(b.anliegen[0].uhrzeit.isEmpty, "die Datei trägt die Uhrzeit in fester Form — „7:45“ ist keine")
        #expect(bilanz.verlust)
    }

    @Test("Grenzen: Verhalten und Leistungen — an der Grenze behalten, eins darüber gekappt und gezählt")
    func grenzen() throws {
        #expect(Lernendendatei.maxVerhalten == 4_000 && Lernendendatei.maxLeistungen == 30_000)
        for (anzahl, verworfen) in [(Lernendendatei.maxVerhalten, 0), (Lernendendatei.maxVerhalten + 1, 1)] {
            var objekt = try roh()
            objekt["lernende"] = (0..<Kennwerte.maxLernende).map { ["id": "l-\($0)", "vorname": "V", "nachname": "N\($0)"] }
            objekt["lerngruppen"] = []; objekt["anliegen"] = []; objekt["rueckmeldungen"] = []
            objekt["erfassung"] = []; objekt["beurteilung"] = []; objekt["leistungen"] = []
            // Zwei Halbjahre je Person füllen die Grenze; der Eintrag darüber ist gültig (ein anderes
            // Schuljahr), damit nur die Grenze ihn verwerfen kann — keine Waise (W4-03).
            objekt["verhalten"] = (0..<anzahl).map { i -> [String: Any] in
                i < Lernendendatei.maxVerhalten
                    ? ["id": "v-\(i)", "lernender": "l-\(i / 2)", "schuljahr": "2026/27", "halbjahr": i % 2 + 1]
                    : ["id": "v-\(i)", "lernender": "l-0", "schuljahr": "2025/26", "halbjahr": 1]
            }
            let (b, bilanz) = try lesen(objekt)
            #expect(b.verhalten.count == Lernendendatei.maxVerhalten && bilanz.verworfeneEintraege == verworfen)
        }
        for (anzahl, verworfen) in [(Lernendendatei.maxLeistungen, 0), (Lernendendatei.maxLeistungen + 1, 1)] {
            var objekt = try roh()
            objekt["leistungen"] = (0..<anzahl).map {
                ["id": "n-\($0)", "lernender": "l-1", "lerngruppe": "g-1", "schuljahr": "2026/27", "halbjahr": 1,
                 "art": "muendlich"] as [String: Any]
            }
            let (b, bilanz) = try lesen(objekt)
            #expect(b.leistungen.count == Lernendendatei.maxLeistungen && bilanz.verworfeneEintraege == verworfen)
        }
    }

    // ── Termine ───────────────────────────────────────────────────────────

    @Test("Termin anlegen: Tag Pflicht, Uhrzeit frei, Gruppe freiwillig; Stände offen / stattgefunden / abgesagt")
    func terminAnlegen() throws {
        let s = Self.stempel
        let b = bestand()
        let (t, id) = try #require(b.mitNeuemAnliegen(.termin, titel: " Elterngespräch ", lerngruppe: "", betroffene: ["l-2"],
                                                       datum: "2026-11-03", frist: "", uhrzeit: "7.30", jetzt: s))
        let termin = try #require(t.anliegen.first { $0.id == id })
        #expect(termin.art == .termin && termin.titel == "Elterngespräch" && termin.lerngruppe.isEmpty)
        #expect(termin.datum == "2026-11-03" && termin.uhrzeit == "07:30" && termin.betroffene == ["l-2"])
        #expect(try Lernendendatei.lesen(try Lernendendatei.schreiben(t)) == t)
        #expect(b.mitNeuemAnliegen(.termin, titel: "X", lerngruppe: "", betroffene: ["l-2"], datum: "", frist: "",
                                   jetzt: s)?.id == nil, "ohne Tag kein Termin")
        #expect(b.mitNeuemAnliegen(.termin, titel: "X", lerngruppe: "", betroffene: ["l-2"], datum: "kein Tag", frist: "",
                                   jetzt: s)?.id == nil)
        let ohneZeit = b.mitNeuemAnliegen(.termin, titel: "X", lerngruppe: "g-9", betroffene: ["l-2"], datum: "2026-11-03",
                                          frist: "", uhrzeit: "25:00", jetzt: s)
        let x = try #require(ohneZeit.flatMap { e in e.bestand.anliegen.first { $0.id == e.id } })
        #expect(x.uhrzeit.isEmpty && x.lerngruppe.isEmpty, "eine falsche Uhrzeit bleibt leer, eine fremde Gruppe auch")

        #expect(Rueckmeldestand.offen.beschriftung(fuer: .termin) == "offen")
        #expect(Rueckmeldestand.erledigt.beschriftung(fuer: .termin) == "stattgefunden")
        #expect(Rueckmeldestand.abgelehnt.beschriftung(fuer: .termin) == "abgesagt")
        #expect(Anliegenart.termin.titel == "Termin" && Anliegenart.massnahme.titel == "Maßnahme"
                && Anliegenart.mitteilung.titel == "Mitteilung")
    }

    @Test("Uhrzeit: „7.30“ und „7:30“ werden „07:30“; 24:00, 12:5 und Text sind keine; leer ist keine Uhrzeit")
    func uhrzeit() {
        #expect(Lernendenbestand.uhrzeit("7.30") == "07:30" && Lernendenbestand.uhrzeit(" 07:30 ") == "07:30")
        #expect(Lernendenbestand.uhrzeit("23:59") == "23:59" && Lernendenbestand.uhrzeit("0:00") == "00:00")
        for falsch in ["24:00", "12:5", "12:60", "halb acht", "7", "123:00", "-1:00"] {
            #expect(Lernendenbestand.uhrzeit(falsch) == nil, "\(falsch)")
        }
        #expect(Lernendenbestand.uhrzeit("  ") == "")
    }

    @Test("Termin ändern: Der Tag bleibt Pflicht, die Uhrzeit nur, wenn genannt")
    func terminAendern() throws {
        let s = "2026-10-05T08:00:00.000Z"
        let b = bestand()
        #expect(b.mitAnliegen("m-1", titel: "Elterngespräch", datum: "", frist: "", notiz: "mit der Mutter", jetzt: s) == b,
                "ohne Tag ändert sich nichts")
        let neu = b.mitAnliegen("m-1", titel: "Elterngespräch", datum: "2026-10-21", frist: "", notiz: "mit der Mutter",
                                uhrzeit: "8:15", jetzt: s)
        #expect(neu.anliegen[0].datum == "2026-10-21" && neu.anliegen[0].uhrzeit == "08:15" && neu.anliegen[0].geaendert == s)
        let ohneAngabe = neu.mitAnliegen("m-1", titel: "Gespräch", datum: "2026-10-21", frist: "", notiz: "", jetzt: s)
        #expect(ohneAngabe.anliegen[0].uhrzeit == "08:15", "ohne Angabe bleibt die Uhrzeit")
        #expect(neu.mitAnliegen("m-1", titel: "Elterngespräch", datum: "2026-10-21", frist: "", notiz: "mit der Mutter",
                                uhrzeit: "", jetzt: s).anliegen[0].uhrzeit.isEmpty, "leer nimmt sie weg")
    }

    @Test("Verzeichnis: Maßnahmen und Termine ohne Gruppe an der Person, keine Mitteilungen; offene Termine zählen mit")
    func verzeichnis() throws {
        var b = bestand()
        let v = Lernendenverzeichnis(b)
        #expect(v.anliegenOhneGruppe(von: "l-1").map(\.id) == ["m-1"])
        #expect(v.anliegenOhneGruppe(von: "l-2").map(\.id) == ["m-2"])
        #expect(v.offeneZahl(von: "l-1") == 0, "der Termin hat stattgefunden")
        b.rueckmeldungen = []
        b.anliegen.append(Anliegen(id: "m-3", art: .mitteilung, titel: "Elternbrief", lerngruppe: "g-1",
                                   betroffene: ["l-1"], datum: "", frist: "", notiz: "", angelegt: "", geaendert: ""))
        let w = Lernendenverzeichnis(b)
        #expect(w.anliegenOhneGruppe(von: "l-1").map(\.id) == ["m-1"], "die Mitteilung gehört der Gruppe")
        #expect(w.offeneZahl(von: "l-1") == 2, "der offene Termin zählt mit")
    }

    // ── Löschen ───────────────────────────────────────────────────────────

    @Test("Person löschen: Verhalten, Leistungen, Notizen, Beurteilung und der Termin nur für sie gehen mit")
    func personLoeschen() {
        let (b, zahl) = bestand().ohnePerson("l-1")
        #expect(b.verhalten.isEmpty && b.erfassung.isEmpty && b.beurteilung.isEmpty)
        #expect(b.leistungen.map(\.id) == ["n-4"])
        #expect(b.anliegen.map(\.id) == ["m-2"] && b.rueckmeldungen.isEmpty)
        #expect(zahl == Lernendenbestand.Loeschzahl(personen: 1, anliegen: 1, termine: 1, rueckmeldungen: 1, eintraege: 6))
    }

    @Test("Gruppe löschen: Die Leistungen und Beurteilungen der Gruppe gehen; Verhalten, Notizen und Termine bleiben")
    func gruppeLoeschen() {
        var start = bestand()
        start.anliegen[0].lerngruppe = "g-1"
        let (b, zahl) = start.ohneGruppe("g-1")
        #expect(b.leistungen.map(\.id) == ["n-2"] && b.beurteilung.isEmpty)
        #expect(b.verhalten.count == 1 && b.erfassung.count == 1)
        #expect(b.anliegen.map(\.id) == ["m-1", "m-2"] && b.anliegen[0].lerngruppe.isEmpty, "der Termin bleibt ohne Gruppe")
        #expect(zahl == Lernendenbestand.Loeschzahl(gruppen: 1, eintraege: 4))
    }

    @Test("Einzelnes löschen: ein Verhalten, eine Leistung — je ein Eintrag")
    func einzelnesLoeschen() {
        let (v, zahlV) = bestand().ohneEintrag("v-1")
        #expect(v.verhalten.isEmpty && zahlV.eintraege == 1)
        let (n, zahlN) = bestand().ohneEintrag("n-2")
        #expect(n.leistungen.map(\.id) == ["n-1", "n-3", "n-4"] && zahlN.eintraege == 1)
    }

    // ── Archiv und Schuljahreswechsel ─────────────────────────────────────

    // Nach E816 (R2-A2): Beim Termin entscheidet das Datum — der Termin steht darum im neuen Schuljahr.
    @Test("Schuljahreswechsel: Termine im neuen Schuljahr wandern wie Maßnahmen, ohne ihre Gruppe, wenn sie nicht mitkommt; das Übrige bleibt im Archiv")
    func neuesJahr() {
        var b = bestand()
        b.rueckmeldungen = []
        b.anliegen[0].lerngruppe = "g-2"
        b.anliegen[0].datum = "2027-09-14"
        let neu = b.neuesJahr(gruppen: ["g-1"], zuordnung: [:], planung: "H2", schuljahr: "2027/28",
                              termine: .abDemNeuenSchuljahr,
                              jetzt: "2027-08-02T08:00:00.000Z")
        #expect(neu.anliegen.map(\.id) == ["m-1", "m-2"])
        #expect(neu.anliegen[0].art == .termin && neu.anliegen[0].lerngruppe.isEmpty && neu.anliegen[0].uhrzeit == "07:45")
        #expect(neu.verhalten.isEmpty && neu.leistungen.isEmpty && neu.erfassung.isEmpty && neu.beurteilung.isEmpty)

        // Ohne Rücklauf ist der Termin offen — es entscheidet nur sein Datum (Z-R2A2-02).
        var offen = bestand()
        offen.rueckmeldungen = []
        let vorher = offen.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: [:], planung: "H2", schuljahr: "2027/28",
                                     termine: .abDemNeuenSchuljahr,
                                     jetzt: "2027-08-02T08:00:00.000Z")
        #expect(vorher.anliegen.map(\.id) == ["m-2"], "der Termin am 20.10.2026 liegt vor dem neuen Schuljahr — offen, und doch bleibt er (E816)")
    }

    @Test("E826: Jeder Termin ab dem neuen Schuljahr kommt mit, auch ein späterer; davor bleibt er — und nur mit einem Schuljahr in fester Form (Z-R2A2-01)")
    func termineAbDemNeuenSchuljahr() {
        var b = bestand()
        b.rueckmeldungen = []
        let s = Self.stempel
        b.anliegen += [
            Anliegen(id: "m-3", art: .termin, titel: "Elterngespräch", lerngruppe: "", betroffene: ["l-1"], datum: "2028-09-14",
                     frist: "", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "m-4", art: .termin, titel: "Zeugnisgespräch", lerngruppe: "", betroffene: ["l-1"], datum: "2027-06-25",
                     frist: "", notiz: "", angelegt: s, geaendert: s),
        ]
        let neu = b.neuesJahr(gruppen: ["g-1"], zuordnung: [:], planung: "H2", schuljahr: "2027/28",
                              termine: .abDemNeuenSchuljahr,
                              jetzt: "2027-08-02T08:00:00.000Z")
        let ids = neu.anliegen.map(\.id)
        #expect(ids == ["m-2", "m-3"], "14.09.2028 kommt mit; 20.10.2026 und 25.06.2027 bleiben im Archiv")
        // Ohne Schuljahr in fester Form nähme der Vergleich sonst beliebige Termine mit — so bleibt keiner; die Maßnahme kommt
        // wie bisher (Z-R2A2-01, Z-R2A2N-04).
        for fremd in ["", "2027-28", "neu"] {
            let ohne = b.neuesJahr(gruppen: ["g-1"], zuordnung: [:], planung: "H2", schuljahr: fremd,
                                   termine: .abDemNeuenSchuljahr,
                                   jetzt: "2027-08-02T08:00:00.000Z")
            let ohneIds = ohne.anliegen.map(\.id)
            #expect(ohneIds == ["m-2"], Comment(rawValue: "„\(fremd)“"))
        }
    }

    /// ⌘O führt jede Planung anderer Herkunft über `jahreswechsel(zu:…)` (Planungsspeicher+Dateien) und `neuesJahr` mit dem
    /// Schuljahr der geöffneten Planung (`schuljahr(fuer: geladen.start)`) — auch „Andere Planung öffnen“ (`stufen == 0`) und
    /// „Früheres Schuljahr öffnen“ (`stufen < 0`). Dort kommen nur offene Termine mit, wie Maßnahmen (E830); `jahreswechsel`
    /// reicht `terminwahl(stufen:)` durch.
    @Test("E830: Bei „Andere Planung öffnen“ und „Früheres Schuljahr öffnen“ kommen nur offene Termine mit — je Person, welches Datum er auch hat; ein stattgefundener oder abgesagter bleibt im Archiv")
    func termineBeiAndererUndFruehererPlanung() throws {
        var b = bestand()
        let s = Self.stempel
        func termin(_ id: String, _ titel: String, _ betroffene: [String], _ datum: String) -> Anliegen {
            Anliegen(id: id, art: .termin, titel: titel, lerngruppe: "", betroffene: betroffene, datum: datum, frist: "",
                     notiz: "", angelegt: s, geaendert: s)
        }
        func ruecklauf(_ id: String, _ person: String, _ stand: Rueckmeldestand) -> Rueckmeldung {
            Rueckmeldung(anliegen: id, lernender: person, stand: stand, datum: "2026-11-02", notiz: "", geaendert: s)
        }
        // m-1 am 20.10.2026 hat stattgefunden. Dazu m-3 am 01.12.2026 (offen), m-4 am 14.09.2027 (offen), m-5 am 10.12.2026
        // (abgesagt), m-6 am 15.06.2026 (offen, vor 2026/27), m-7 am 20.11.2026 für Anna und Ben — für Anna stattgefunden —
        // und m-8 am 05.10.2027 (abgesagt, in 2027/28).
        b.anliegen += [termin("m-3", "Elternsprechtag", ["l-1"], "2026-12-01"),
                       termin("m-4", "Elternabend 7", ["l-1"], "2027-09-14"),
                       termin("m-5", "Förderkonferenz", ["l-1"], "2026-12-10"),
                       termin("m-6", "Nachgespräch", ["l-1"], "2026-06-15"),
                       termin("m-7", "Lernstandsgespräch", ["l-1", "l-2"], "2026-11-20"),
                       termin("m-8", "Elternabend 7b", ["l-1"], "2027-10-05")]
        b.rueckmeldungen += [ruecklauf("m-5", "l-1", .abgelehnt), ruecklauf("m-7", "l-1", .erledigt),
                             ruecklauf("m-8", "l-1", .abgelehnt)]
        let jetzt = "2026-11-05T08:00:00.000Z"
        let andere = b.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: [:], planung: "H2", schuljahr: "2026/27",
                                 termine: .nurOffene, jetzt: jetzt)
        let andereIds = andere.anliegen.map(\.id)
        #expect(andereIds == ["m-2", "m-3", "m-4", "m-6", "m-7"],
                "dasselbe Schuljahr: die offenen Termine, auch der vom 15.06.2026 vor dem Schuljahr (Z-R2A2N2-02)")
        let m7OderNil = andere.anliegen.first { $0.id == "m-7" }
        let m7 = try #require(m7OderNil)
        #expect(m7.betroffene == ["l-2"], "nur für Ben offen — Anna bleibt mit ihrem Rücklauf im Archiv")
        let ruecklaeufe = andere.rueckmeldungen.filter { ["m-1", "m-5", "m-7", "m-8"].contains($0.anliegen) }
        #expect(ruecklaeufe.isEmpty, "die Rückläufe der gebliebenen Termine und Personen bleiben im Archiv")
        let frueher = b.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: [:], planung: "H2", schuljahr: "2025/26",
                                  termine: .nurOffene, jetzt: jetzt)
        let frueherIds = frueher.anliegen.map(\.id)
        #expect(frueherIds == ["m-2", "m-3", "m-4", "m-6", "m-7"], "ein früheres Schuljahr ebenso")
        // Der Gegenfall, der echte Wechsel nach 2027/28 (Z-R2A2N2-03): Nach E826 entscheidet das Datum — der offene Termin
        // vom 14.09.2027 und der abgesagte vom 05.10.2027 kommen mit, alle aus 2026/27 bleiben, auch die offenen.
        let naechstes = b.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: [:], planung: "H2", schuljahr: "2027/28",
                                    termine: .abDemNeuenSchuljahr, jetzt: "2027-08-02T08:00:00.000Z")
        let naechstesIds = naechstes.anliegen.map(\.id)
        #expect(naechstesIds == ["m-2", "m-4", "m-8"])
        let abgesagt = naechstes.rueckmeldungen.first { $0.anliegen == "m-8" }
        #expect(abgesagt?.stand == .abgelehnt, "samt dem Rücklauf „abgesagt“")
    }

    @Test("E830: Die Wahl der Termine folgt den Stufen wie die Blätter — echter Wechsel nach dem Datum, sonst nur offene")
    func terminwahl() {
        let wahl = [2, 1, 0, -1].map { Lernendenbestand.terminwahl(stufen: $0) }
        #expect(wahl == [.abDemNeuenSchuljahr, .abDemNeuenSchuljahr, .nurOffene, .nurOffene])
    }

    @Test("E816: Beim Termin entscheidet nur das Datum — im neuen Schuljahr (ab Juli) kommt er mit den übernommenen Personen, auch stattgefunden, samt Rücklauf; davor bleibt er im Archiv, auch offen")
    func termineBeimWechsel() throws {
        var b = bestand()
        let s = Self.stempel
        func termin(_ id: String, _ titel: String, _ gruppe: String, _ betroffene: [String], _ datum: String) -> Anliegen {
            Anliegen(id: id, art: .termin, titel: titel, lerngruppe: gruppe, betroffene: betroffene, datum: datum, frist: "",
                     notiz: "", angelegt: s, geaendert: s)
        }
        // m-1 (20.10.2026, stattgefunden) bleibt. Dazu: m-3 am 14.09.2027 an der 6a für Anna und Ben, für Anna
        // stattgefunden; m-4 am 01.07.2027 (ab Juli das neue Schuljahr); m-5 am 30.06.2027, offen; m-6 am 20.09.2027
        // aus „6 Inf“ für Anna.
        b.anliegen += [termin("m-3", "Elternabend", "g-1", ["l-1", "l-2"], "2027-09-14"),
                       termin("m-4", "Gespräch zum Wechsel", "", ["l-1"], "2027-07-01"),
                       termin("m-5", "Zeugnisgespräch", "", ["l-1"], "2027-06-30"),
                       termin("m-6", "Informatik-Abend", "g-2", ["l-1"], "2027-09-20")]
        b.rueckmeldungen.append(Rueckmeldung(anliegen: "m-3", lernender: "l-1", stand: .erledigt, datum: "2027-09-14",
                                             notiz: "", geaendert: s))
        let neu = b.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: [:], planung: "H2", schuljahr: "2027/28",
                              termine: .abDemNeuenSchuljahr,
                              jetzt: "2027-08-02T08:00:00.000Z")
        let ids = neu.anliegen.map(\.id)
        #expect(ids == ["m-2", "m-3", "m-4", "m-6"], "m-1 und m-5 liegen davor — sie bleiben im Archiv, auch offen")
        let m3OderNil = neu.anliegen.first { $0.id == "m-3" }
        let m3 = try #require(m3OderNil)
        #expect(m3.betroffene == ["l-1", "l-2"] && m3.lerngruppe == "g-1", "stattgefunden für Anna — der Stand zählt nicht")
        let ruecklauf = neu.rueckmeldungen.first { $0.anliegen == "m-3" && $0.lernender == "l-1" }
        #expect(ruecklauf?.stand == .erledigt, "Annas Rücklauf geht mit")

        // Nur Anna kommt mit (über „6 Inf“); die 6a kommt nicht mit: m-3 nur für Anna, ohne Lerngruppe.
        let nurAnna = b.neuesJahr(gruppen: ["g-2"], zuordnung: [:], planung: "H2", schuljahr: "2027/28",
                                  termine: .abDemNeuenSchuljahr,
                                  jetzt: "2027-08-02T08:00:00.000Z")
        let m3AnnaOderNil = nurAnna.anliegen.first { $0.id == "m-3" }
        let m3Anna = try #require(m3AnnaOderNil)
        #expect(m3Anna.betroffene == ["l-1"] && m3Anna.lerngruppe.isEmpty)
        // E763/E764: „6 Inf“ ohne Mitglieder — m-6 kommt mit Anna (über die 6a), ohne Lerngruppe.
        let ohne = b.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: [:], planung: "H2", schuljahr: "2027/28",
                               termine: .abDemNeuenSchuljahr,
                               jetzt: "2027-08-02T08:00:00.000Z", ohneMitglieder: ["g-2"])
        let m6OderNil = ohne.anliegen.first { $0.id == "m-6" }
        let m6 = try #require(m6OderNil)
        #expect(m6.betroffene == ["l-1"] && m6.lerngruppe.isEmpty)
    }

    @Test("Archiv: Ein Jahr zählt Verhalten und Leistungen mit; eine Person in allen Jahren nennt ihre Termine")
    func archiv() throws {
        let planung = Planung.leer(titel: "Planung", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                                   klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        let archiv = Archivbestand.leer.mitJahr(planung: planung, lernende: bestand(), jetzt: Self.stempel)
            .mitJahr(planung: planung, lernende: bestand(), jetzt: Self.stempel)
        let (_, jahr) = archiv.ohneJahr(archiv.jahre[0].id, jetzt: Self.stempel)
        #expect(jahr.eintraege == 7 && jahr.termine == 1, "1 Notiz + 1 Beurteilung + 1 Verhalten + 4 Leistungen")
        let (_, person) = archiv.ohnePerson("l-1", jetzt: Self.stempel)
        #expect(person.termine == 2 && person.anliegen == 2 && person.eintraege == 12)
    }
}
