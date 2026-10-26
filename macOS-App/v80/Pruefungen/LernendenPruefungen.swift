// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die Jahresdatei der Lernendenverwaltung (v80, AP1) ─────────────────────
// Das reine Modell: Datei hin und zurück, fünfzehn verdorbene Dateien mit
// vorhergesagter Bilanz, je Grenze zwei Fälle, das Verzeichnis, die Eingabe
// von Hand (E273) und das Löschen samt allem, was an einer Person hängt (E252).

@Suite("Lernende: Jahresdatei, Bilanz, Grenzen, Verzeichnis, Namenszeilen, Löschen")
struct LernendenPruefungen {

    private static let herkunft = "2026-08-10T09:00:00.000Z"
    private static let stempel = "2026-10-03T08:00:00.000Z"

    // ── Ein gültiger Bestand, als Wert und als Rohobjekt ────────────────────

    private func bestand() -> Lernendenbestand {
        let s = Self.stempel
        return Lernendenbestand(
            planung: Self.herkunft, schuljahr: "2026/27", erstellt: s, geaendert: s,
            lernende: [
                Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                Lernender(id: "l-2", vorname: "Ben", nachname: "Bauer", angelegt: s, geaendert: s, archiviert: ""),
                Lernender(id: "l-3", vorname: "Cem", nachname: "Çelik", angelegt: s, geaendert: s, archiviert: ""),
                Lernender(id: "l-4", vorname: "Dora", nachname: "Dietz", angelegt: s, geaendert: s, archiviert: ""),
            ],
            lerngruppen: [
                Lerngruppe(id: "g-1", name: "6a", fach: "Biologie", art: .klasse,
                           mitglieder: ["l-1", "l-2", "l-3"],
                           zeilen: [Zeilenbindung(planung: Self.herkunft, klasseId: "k-1")],
                           skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: ""),
            ],
            anliegen: [
                Anliegen(id: "m-1", art: .mitteilung, titel: "Elternbrief Wandertag", lerngruppe: "g-1",
                         betroffene: ["l-1", "l-2", "l-3"], datum: "2026-10-01", frist: "2026-10-08",
                         notiz: "", angelegt: s, geaendert: s),
                Anliegen(id: "m-2", art: .massnahme, titel: "Nacharbeit", lerngruppe: "",
                         betroffene: ["l-2"], datum: "2026-10-02", frist: "2026-10-09",
                         notiz: "Arbeitsblatt 3", angelegt: s, geaendert: s),
            ],
            rueckmeldungen: [
                Rueckmeldung(anliegen: "m-1", lernender: "l-1", stand: .erledigt, datum: "2026-10-03", notiz: "", geaendert: s),
                Rueckmeldung(anliegen: "m-1", lernender: "l-2", stand: .abgelehnt, datum: "2026-10-04",
                             notiz: "kein Einverständnis", geaendert: s),
                Rueckmeldung(anliegen: "m-2", lernender: "l-2", stand: .offen, datum: "", notiz: "", geaendert: s),
            ],
            erfassung: [
                Erfassungseintrag(id: "a-1", lernender: "l-1", lerngruppe: "g-1", planung: Self.herkunft,
                                  vorhaben: "e-1", datum: "2026-10-05", art: .muendlich, wert: "+",
                                  notiz: "", angelegt: s, geaendert: s),
            ],
            beurteilung: [
                Beurteilung(id: "b-1", lernender: "l-1", lerngruppe: "g-1", schuljahr: "2026/27", halbjahr: 1,
                            zeugnisnote: "2", notiz: "", geaendert: s),
            ])
    }

    private func roh() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(bestand())) as? [String: Any])
    }

    private func lesen(_ objekt: [String: Any]) throws -> (bestand: Lernendenbestand, bilanz: Lernendendatei.Bilanz) {
        try Lernendendatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: objekt))
    }

    /// Eine Liste im Rohobjekt ändern.
    private func liste(_ objekt: inout [String: Any], _ name: String,
                       _ aendern: (inout [[String: Any]]) -> Void) throws {
        var eintraege = try #require(objekt[name] as? [[String: Any]])
        aendern(&eintraege)
        objekt[name] = eintraege
    }

    // ── Die Datei ─────────────────────────────────────────────────────────

    @Test("Jahresdatei hin und zurück: derselbe Bestand, kanonisch geschrieben, leere Bilanz")
    func hinUndZurueck() throws {
        var b = bestand()
        b.lernende[2].nachname = "Çelik-Ünal / ß"
        b.anliegen[1].notiz = "Zeile eins\nZeile zwei"
        b.lerngruppen[0].skalen = ["muendlich": "fuenfstufig", "noten": "1-6"]
        b.lerngruppen[0].halbjahreswechsel = "2027-01-29"
        let daten = try Lernendendatei.schreiben(b)
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(daten)
        #expect(gelesen == b)
        #expect(bilanz.istLeer, "\(bilanz.beschreibung)")
        #expect(try Lernendendatei.schreiben(gelesen) == daten, "kanonisch")
        let text = String(decoding: daten, as: UTF8.self)
        #expect(text.contains("\"typ\":\"unterrichtsplanung-lernende\"") && text.contains("\"version\":1"))

        let leer = Lernendenbestand.leer(planung: Self.herkunft, schuljahr: "2026/27", jetzt: Self.stempel)
        #expect(try Lernendendatei.lesen(try Lernendendatei.schreiben(leer)) == leer)
    }

    @Test("Rufname (E285): freiwillig, nur geschrieben, wo gesetzt; gekürzt und gezählt; mitPerson setzt und leert ihn")
    func rufname() throws {
        let s = Self.stempel
        let b = bestand().mitPerson("l-1", vorname: "Anna", nachname: "Abel", rufname: " Anni ", jetzt: s)
        #expect(b.lernende.first { $0.id == "l-1" }?.rufname == "Anni")
        #expect(b.mitPerson("l-1", vorname: "Anna", nachname: "Abel", rufname: "Anni", jetzt: s) == b, "gleich ändert nichts")
        #expect(b.mitPerson("l-1", vorname: "Anna", nachname: "Abel", jetzt: s) == b, "ohne Angabe bleibt er")
        #expect(b.mitPerson("l-1", vorname: "Anna", nachname: "Abel", rufname: "", jetzt: s)
                    .lernende.first { $0.id == "l-1" }?.rufname == "", "leer löscht ihn")
        let daten = try Lernendendatei.schreiben(b)
        #expect(String(decoding: daten, as: UTF8.self).components(separatedBy: "\"rufname\"").count - 1 == 1,
                "nur am gesetzten")
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(daten)
        #expect(gelesen == b && bilanz.istLeer)
        #expect(try Lernendendatei.schreiben(gelesen) == daten, "kanonisch")
        var objekt = try roh()
        try liste(&objekt, "lernende") { $0[1]["rufname"] = String(repeating: "r", count: Kennwerte.maxLernendenname + 1) }
        let (lang, langBilanz) = try lesen(objekt)
        #expect(lang.lernende[1].rufname.count == Kennwerte.maxLernendenname && langBilanz.gekuerzteTexte == 1)
    }

    @Test("CSV (E257): UTF-8 mit BOM, Semikolon, CRLF; aktive Personen nach Nachname, Rufname, Lerngruppen; Semikolon und Anführungszeichen gequotet")
    func csv() {
        let s = Self.stempel
        var b = bestand()
            .mitPerson("l-1", vorname: "Anna", nachname: "Abel", rufname: "Anni", jetzt: s)
            .mitPerson("l-2", vorname: "Ben \"Benni\"", nachname: "Bauer; Brandt", jetzt: s)
            .mitArchivierterPerson("l-4", jetzt: s)
        b.lerngruppen.append(Lerngruppe(id: "g-2", name: "AG Robotik", fach: "", art: .kurs, mitglieder: ["l-1"],
                                        zeilen: [], skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: ""))
        let daten = Lernendendatei.csv(b)
        #expect(Array(daten.prefix(3)) == [0xEF, 0xBB, 0xBF], "BOM")
        #expect(String(decoding: daten.dropFirst(3), as: UTF8.self)
                == "Nachname;Vorname;Rufname;Lerngruppen\r\n"
                + "Abel;Anna;Anni;6a · Biologie, AG Robotik\r\n"
                + "\"Bauer; Brandt\";\"Ben \"\"Benni\"\"\";;6a · Biologie\r\n"
                + "Çelik;Cem;;6a · Biologie\r\n")
        #expect(Lernendendatei.exportName(schuljahr: "2026/27", endung: "csv") == "Lernende 2026-27.csv")
    }

    @Test("Fehlende Listen sind leer und gültig; Fassung 2 sperrt; Unlesbares ist beschädigt")
    func kopfUndFassung() throws {
        let minimal = try lesen(["typ": Lernendendatei.typ, "version": 1])
        #expect(minimal.bestand.lernende.isEmpty && minimal.bestand.anliegen.isEmpty && minimal.bilanz.istLeer)

        do {
            _ = try lesen(["typ": Lernendendatei.typ, "version": 2])
            Issue.record("eine neuere Fassung muss abgewiesen werden")
        } catch let fehler as Lernendendatei.Fehler {
            #expect(fehler.art == .neuereFassung && fehler.text.contains("aktualisieren"))
        }
        for kaputt in ["", "[]", "{}", "kein JSON",
                       "{\"typ\":\"unterrichtsplanung-sitzplaene\",\"version\":1}",
                       "{\"typ\":\"unterrichtsplanung-lernende\",\"version\":true}",
                       "{\"typ\":\"unterrichtsplanung-lernende\",\"version\":0}",
                       "{\"typ\":\"unterrichtsplanung-lernende\",\"version\":1,\"lernende\":{}}",
                       "{\"typ\":\"unterrichtsplanung-lernende\",\"version\":1,\"rueckmeldungen\":\"keine\"}"] {
            #expect(throws: Lernendendatei.Fehler.self, "\(kaputt)") { try Lernendendatei.lesen(Data(kaputt.utf8)) }
        }
        let zuGross = Data(count: Lernendendatei.hoechstgroesse + 1)
        do {
            _ = try Lernendendatei.lesen(zuGross)
            Issue.record("eine Datei über der Grenze muss abgewiesen werden, bevor sie gelesen wird")
        } catch let fehler as Lernendendatei.Fehler {
            #expect(fehler.art == .beschaedigt && fehler.text.contains("16 MB"))
        }
    }

    /// Fünfzehn verdorbene Dateien — je eine Änderung am gültigen Bestand,
    /// je eine vorhergesagte Bilanz. Die Bilanz muss **genau** stimmen: Was
    /// sie nicht nennt, darf nicht geschehen sein.
    @Test("Fünfzehn verdorbene Dateien ergeben die vorhergesagte Bilanz")
    func verdorbeneDateien() throws {
        typealias Bilanz = Lernendendatei.Bilanz
        func bilanz(_ setzen: (inout Bilanz) -> Void) -> Bilanz { var b = Bilanz(); setzen(&b); return b }
        let lang = String(repeating: "x", count: 101) + String(UnicodeScalar(7))

        let faelle: [(String, (inout [String: Any]) throws -> Void, Bilanz)] = [
            ("Person kein Objekt", { o in var l = (o["lernende"] as? [Any]) ?? []; l[3] = "kein Objekt"; o["lernende"] = l },
             bilanz { $0.verworfeneLernende = 1 }),
            ("Person ohne Namen", { o in try liste(&o, "lernende") { $0[3]["vorname"] = ""; $0[3]["nachname"] = "  " } },
             bilanz { $0.verworfeneLernende = 1 }),
            ("Kennung doppelt", { o in try liste(&o, "lernende") { $0[3]["id"] = "l-1" } },
             bilanz { $0.ersetzteKennungen = 1 }),
            ("Name über der Grenze, mit Steuerzeichen", { o in try liste(&o, "lernende") { $0[3]["nachname"] = lang } },
             bilanz { $0.gekuerzteTexte = 1 }),
            ("Mitglied doppelt und ohne Person", { o in
                try liste(&o, "lerngruppen") { $0[0]["mitglieder"] = ["l-1", "l-1", "l-9", "l-2", "l-3"] } },
             bilanz { $0.verworfeneMitglieder = 2 }),
            ("Gruppe ohne Namen", { o in
                try liste(&o, "lerngruppen") { $0.append(["id": "g-2", "name": " ", "art": "kurs", "mitglieder": []]) } },
             bilanz { $0.verworfeneGruppen = 1 }),
            ("Zeilen: fremde Kennung, doppelt", { o in
                try liste(&o, "lerngruppen") {
                    $0[0]["zeilen"] = [["planung": Self.herkunft, "klasseId": "/böse"],
                                       ["planung": Self.herkunft, "klasseId": "k-1"],
                                       ["planung": Self.herkunft, "klasseId": "k-1"]]
                } },
             bilanz { $0.verworfeneZeilen = 2 }),
            ("Anliegen unbekannter Art samt Rücklauf", { o in try liste(&o, "anliegen") { $0[1]["art"] = "strafe" } },
             bilanz { $0.verworfeneAnliegen = 1; $0.verworfeneRueckmeldungen = 1 }),
            ("Mitteilung an eine Gruppe, die es nicht gibt, samt Rückläufen", { o in
                try liste(&o, "anliegen") { $0[0]["lerngruppe"] = "g-9" } },
             bilanz { $0.verworfeneAnliegen = 1; $0.verworfeneRueckmeldungen = 2 }),
            ("Maßnahme an einer Gruppe, die es nicht gibt", { o in
                try liste(&o, "anliegen") { $0[1]["lerngruppe"] = "g-9" } },
             bilanz { $0.bereinigteBezuege = 1 }),
            ("Rückläufe: ohne Anliegen, nicht betroffen, doppelt, unbekannter Stand", { o in
                try liste(&o, "rueckmeldungen") {
                    $0.append(["anliegen": "m-9", "lernender": "l-1", "stand": "offen"])
                    $0.append(["anliegen": "m-2", "lernender": "l-1", "stand": "erledigt"])
                    $0.append(["anliegen": "m-1", "lernender": "l-1", "stand": "offen"])
                    $0.append(["anliegen": "m-1", "lernender": "l-3", "stand": "vielleicht"])
                } },
             bilanz { $0.verworfeneRueckmeldungen = 4 }),
            ("Tage: der 31. Februar und „morgen“", { o in
                try liste(&o, "anliegen") { $0[0]["datum"] = "2026-02-31"; $0[0]["frist"] = "morgen" } },
             bilanz { $0.bereinigteTage = 2 }),
            ("Zeitstempel „gestern“", { o in try liste(&o, "lernende") { $0[0]["angelegt"] = "gestern" } },
             bilanz { $0.bereinigteStempel = 1 }),
            ("Erfassung unbekannter Art", { o in try liste(&o, "erfassung") { $0[0]["art"] = "sport" } },
             bilanz { $0.verworfeneEintraege = 1 }),
            ("Halbjahr als Wahrheitswert", { o in try liste(&o, "beurteilung") { $0[0]["halbjahr"] = true } },
             bilanz { $0.verworfeneEintraege = 1 }),
        ]
        #expect(faelle.count == 15)
        for (name, aendern, erwartet) in faelle {
            var objekt = try roh()
            try aendern(&objekt)
            let (gelesen, bilanz) = try lesen(objekt)
            #expect(bilanz == erwartet, "\(name): \(bilanz.beschreibung)")
            #expect(Set(gelesen.lernende.map(\.id)).count == gelesen.lernende.count, "\(name): Kennungen eindeutig")
        }
    }

    @Test("Was die Bilanz zählt, ist auch geschehen: Waisen weg, Bezüge geleert, Kennung ersetzt")
    func bilanzStimmtMitInhalt() throws {
        var objekt = try roh()
        try liste(&objekt, "lernende") { $0[3]["id"] = "l-1" }
        try liste(&objekt, "lerngruppen") { $0[0]["mitglieder"] = ["l-1", "l-1", "l-9", "l-2", "l-3"] }
        try liste(&objekt, "anliegen") { $0[1]["lerngruppe"] = "g-9" }
        let (b, bilanz) = try lesen(objekt)
        #expect(b.lernende[3].nachname == "Dietz" && b.lernende[3].id != "l-1" && Kennung.istGueltig(b.lernende[3].id))
        #expect(b.lerngruppen[0].mitglieder == ["l-1", "l-2", "l-3"])
        #expect(b.anliegen[1].lerngruppe.isEmpty && b.anliegen[1].art == .massnahme)
        #expect(bilanz.verlust, "eine geleerte Gruppe einer Maßnahme ist Verlust")
        #expect(!bilanz.beschreibung.isEmpty)
    }

    // ── Grenzen: je zwei Fälle — an der Grenze behalten, eins darüber gekappt ──

    @Test("Grenzen der Personen, Gruppen und Mitglieder: an der Grenze behalten, eins darüber gekappt und gezählt")
    func grenzenPersonenUndGruppen() throws {
        for (anzahl, verworfen) in [(Kennwerte.maxLernende, 0), (Kennwerte.maxLernende + 1, 1)] {
            var objekt = try roh()
            objekt["lernende"] = (0..<anzahl).map { ["id": "l-\($0)", "vorname": "V", "nachname": "N\($0)"] }
            objekt["lerngruppen"] = []; objekt["anliegen"] = []; objekt["rueckmeldungen"] = []
            objekt["erfassung"] = []; objekt["beurteilung"] = []
            let (b, bilanz) = try lesen(objekt)
            #expect(b.lernende.count == min(anzahl, Kennwerte.maxLernende) && bilanz.verworfeneLernende == verworfen)
        }
        for (anzahl, verworfen) in [(Kennwerte.maxLerngruppen, 0), (Kennwerte.maxLerngruppen + 1, 1)] {
            var objekt = try roh()
            objekt["lerngruppen"] = (0..<anzahl).map { ["id": "g-\($0)", "name": "G\($0)", "art": "kurs"] }
            objekt["anliegen"] = []; objekt["rueckmeldungen"] = []; objekt["erfassung"] = []; objekt["beurteilung"] = []
            let (b, bilanz) = try lesen(objekt)
            #expect(b.lerngruppen.count == min(anzahl, Kennwerte.maxLerngruppen) && bilanz.verworfeneGruppen == verworfen)
        }
        for (anzahl, verworfen) in [(Kennwerte.maxMitgliederJeLerngruppe, 0), (Kennwerte.maxMitgliederJeLerngruppe + 1, 1)] {
            var objekt = try roh()
            objekt["lernende"] = (0..<anzahl).map { ["id": "l-\($0)", "vorname": "V", "nachname": "N\($0)"] }
            objekt["lerngruppen"] = [["id": "g-1", "name": "6a", "art": "klasse", "mitglieder": (0..<anzahl).map { "l-\($0)" }]]
            objekt["anliegen"] = []; objekt["rueckmeldungen"] = []; objekt["erfassung"] = []; objekt["beurteilung"] = []
            let (b, bilanz) = try lesen(objekt)
            #expect(b.lerngruppen[0].mitglieder.count == min(anzahl, Kennwerte.maxMitgliederJeLerngruppe)
                    && bilanz.verworfeneMitglieder == verworfen)
        }
        for (anzahl, verworfen) in [(Lernendendatei.maxZeilenJeGruppe, 0), (Lernendendatei.maxZeilenJeGruppe + 1, 1)] {
            var objekt = try roh()
            try liste(&objekt, "lerngruppen") {
                $0[0]["zeilen"] = (0..<anzahl).map { ["planung": Self.herkunft, "klasseId": "k-\($0)"] }
            }
            let (b, bilanz) = try lesen(objekt)
            #expect(b.lerngruppen[0].zeilen.count == min(anzahl, Lernendendatei.maxZeilenJeGruppe)
                    && bilanz.verworfeneZeilen == verworfen)
        }
        for (anzahl, verworfen) in [(Lernendendatei.maxSkalen, 0), (Lernendendatei.maxSkalen + 1, 1)] {
            var objekt = try roh()
            try liste(&objekt, "lerngruppen") {
                $0[0]["skalen"] = Dictionary(uniqueKeysWithValues: (0..<anzahl).map { ("s\($0)", "wert") })
            }
            let (b, bilanz) = try lesen(objekt)
            #expect(b.lerngruppen[0].skalen.count == min(anzahl, Lernendendatei.maxSkalen)
                    && bilanz.verworfeneFelder == verworfen)
        }
    }

    @Test("Grenzen der Texte: Name, Titel, Notiz, Wert — an der Grenze behalten, eins darüber gekürzt und gezählt")
    func grenzenTexte() throws {
        let faelle: [(String, Int, (inout [String: Any], String) throws -> Void, (Lernendenbestand) -> String)] = [
            ("Name", Kennwerte.maxLernendenname,
             { o, t in try liste(&o, "lernende") { $0[0]["vorname"] = t } }, { $0.lernende[0].vorname }),
            ("Titel", Lernendendatei.maxTitel,
             { o, t in try liste(&o, "anliegen") { $0[0]["titel"] = t } }, { $0.anliegen[0].titel }),
            ("Notiz", Lernendendatei.maxNotiz,
             { o, t in try liste(&o, "rueckmeldungen") { $0[0]["notiz"] = t } }, { $0.rueckmeldungen[0].notiz }),
            ("Wert", Lernendendatei.maxWert,
             { o, t in try liste(&o, "erfassung") { $0[0]["wert"] = t } }, { $0.erfassung[0].wert }),
        ]
        for (name, grenze, setzen, lesenWert) in faelle {
            for (laenge, gekuerzt) in [(grenze, 0), (grenze + 1, 1)] {
                var objekt = try roh()
                try setzen(&objekt, String(repeating: "ä", count: laenge))
                let (b, bilanz) = try lesen(objekt)
                #expect(lesenWert(b).count == grenze && bilanz.gekuerzteTexte == gekuerzt, "\(name) \(laenge)")
            }
        }
    }

    @Test("Grenzen der großen Listen: Anliegen, Rückläufe, Erfassung, Beurteilung")
    func grenzenListen() throws {
        // Anliegen: Maßnahmen ohne Gruppe an Person l-1.
        for (anzahl, verworfen) in [(Lernendendatei.maxAnliegen, 0), (Lernendendatei.maxAnliegen + 1, 1)] {
            var objekt = try roh()
            objekt["anliegen"] = (0..<anzahl).map {
                ["id": "m-\($0)", "art": "massnahme", "titel": "T", "betroffene": ["l-1"]] as [String: Any]
            }
            objekt["rueckmeldungen"] = []
            let (b, bilanz) = try lesen(objekt)
            #expect(b.anliegen.count == min(anzahl, Lernendendatei.maxAnliegen) && bilanz.verworfeneAnliegen == verworfen)
        }
        // Rückläufe: eine volle Gruppe, so viele Mitteilungen, dass die Paare reichen.
        let personen = Kennwerte.maxMitgliederJeLerngruppe
        let mitteilungen = Lernendendatei.maxRueckmeldungen / personen + 1
        for (anzahl, verworfen) in [(Lernendendatei.maxRueckmeldungen, 0), (Lernendendatei.maxRueckmeldungen + 1, 1)] {
            var objekt = try roh()
            let ids = (0..<personen).map { "l-\($0)" }
            objekt["lernende"] = ids.map { ["id": $0, "vorname": "V", "nachname": $0] }
            objekt["lerngruppen"] = [["id": "g-1", "name": "6a", "art": "klasse", "mitglieder": ids]]
            objekt["anliegen"] = (0..<mitteilungen).map {
                ["id": "m-\($0)", "art": "mitteilung", "titel": "T", "lerngruppe": "g-1", "betroffene": ids] as [String: Any]
            }
            objekt["rueckmeldungen"] = (0..<anzahl).map {
                ["anliegen": "m-\($0 / personen)", "lernender": "l-\($0 % personen)", "stand": "erledigt"]
            }
            objekt["erfassung"] = []; objekt["beurteilung"] = []
            let (b, bilanz) = try lesen(objekt)
            #expect(b.rueckmeldungen.count == min(anzahl, Lernendendatei.maxRueckmeldungen)
                    && bilanz.verworfeneRueckmeldungen == verworfen)
        }
        for (anzahl, verworfen) in [(Lernendendatei.maxErfassung, 0), (Lernendendatei.maxErfassung + 1, 1)] {
            var objekt = try roh()
            objekt["erfassung"] = (0..<anzahl).map {
                ["id": "a-\($0)", "lernender": "l-1", "lerngruppe": "g-1", "datum": "2026-10-05", "art": "frei"]
            }
            let (b, bilanz) = try lesen(objekt)
            #expect(b.erfassung.count == min(anzahl, Lernendendatei.maxErfassung) && bilanz.verworfeneEintraege == verworfen)
        }
        for (anzahl, verworfen) in [(Lernendendatei.maxBeurteilungen, 0), (Lernendendatei.maxBeurteilungen + 1, 1)] {
            var objekt = try roh()
            objekt["beurteilung"] = (0..<anzahl).map {
                ["id": "b-\($0)", "lernender": "l-1", "lerngruppe": "g-1", "schuljahr": "2026/27", "halbjahr": 2]
            }
            let (b, bilanz) = try lesen(objekt)
            #expect(b.beurteilung.count == min(anzahl, Lernendendatei.maxBeurteilungen)
                    && bilanz.verworfeneEintraege == verworfen)
        }
    }

    @Test("Die Grenzen tragen die Werte des Vertrags")
    func grenzwerte() {
        #expect(Kennwerte.maxLernende == 2_000 && Kennwerte.maxLerngruppen == 200)
        #expect(Kennwerte.maxMitgliederJeLerngruppe == 40 && Kennwerte.maxLernendenname == 100, "40 je Lerngruppe (E279)")
        #expect(Kennwerte.maxSitzplaetze == 40, "40 Tische je Sitzplan (E283)")
        #expect(Lernendendatei.maxAnliegen == 2_000 && Lernendendatei.maxRueckmeldungen == 60_000)
        #expect(Lernendendatei.maxErfassung == 30_000 && Lernendendatei.maxBeurteilungen == 5_000)
        #expect(Lernendendatei.maxTitel == 200 && Lernendendatei.maxNotiz == 2_000 && Lernendendatei.maxWert == 32)
        #expect(Lernendendatei.hoechstgroesse == 16 * 1024 * 1024 && Lernendendatei.hinweisgroesse == 8 * 1024 * 1024)
    }

    // ── Das Verzeichnis ───────────────────────────────────────────────────

    @Test("Verzeichnis: Reihenfolge nach Nachname, Archivierte außen vor, Stand und offene Anliegen je Person")
    func verzeichnis() throws {
        var b = bestand()
        b.lernende.append(Lernender(id: "l-5", vorname: "Emil", nachname: "Celik", angelegt: "", geaendert: "", archiviert: ""))
        b.lerngruppen[0].mitglieder.append("l-5")
        b = b.mitArchivierterPerson("l-2", jetzt: Self.stempel)
        let v = Lernendenverzeichnis(b)
        #expect(v.mitglieder("g-1").map(\.id) == ["l-1", "l-5", "l-3"], "Abel, Celik, Çelik — ohne die archivierte Person")
        #expect(v.mitglieder("g-1", archivierte: true).map(\.id) == ["l-1", "l-2", "l-5", "l-3"])
        #expect(v.mitgliederzahl("g-1") == 3 && v.mitgliederzahl("g-unbekannt") == 0, "gezählt ohne die archivierte Person")
        #expect(v.alle.map(\.id) == ["l-1", "l-5", "l-3", "l-4"])
        #expect(v.gruppen(von: "l-3").map(\.id) == ["g-1"] && v.gruppen(von: "l-4").isEmpty)
        #expect(v.stand("m-1", "l-1") == .erledigt && v.stand("m-1", "l-2") == .abgelehnt)
        #expect(v.stand("m-1", "l-3") == .offen, "ohne Rücklauf gilt „offen“")
        #expect(v.offeneAnliegen(von: "l-3").map(\.id) == ["m-1"])
        #expect(v.offeneAnliegen(von: "l-1").isEmpty)
        #expect(v.offeneAnliegen(von: "l-2").map(\.id) == ["m-2"], "der abgelehnte Rücklauf ist nicht offen, die Maßnahme schon")
        #expect(v.anliegen(der: "g-1").map(\.id) == ["m-1"])
        #expect(Rueckmeldestand.abgelehnt.beschriftung(fuer: .mitteilung) == "abgelehnt")
        #expect(Rueckmeldestand.abgelehnt.beschriftung(fuer: .massnahme) == "nicht erfüllt")
        #expect(Rueckmeldestand.erledigt.beschriftung(fuer: .massnahme) == "erfüllt")

        let zurueck = b.mitZurueckgeholterPerson("l-2", jetzt: "2026-10-05T08:00:00.000Z")
        #expect(zurueck.lernende[1].archiviert.isEmpty)
    }

    @Test("Schuljahr aus dem Beginn der Planung: ab Juli das neue")
    func schuljahr() throws {
        #expect(Lernendenbestand.schuljahr(fuer: try #require(Tag(iso: "2026-08-03"))) == "2026/27")
        #expect(Lernendenbestand.schuljahr(fuer: try #require(Tag(iso: "2026-07-27"))) == "2026/27")
        #expect(Lernendenbestand.schuljahr(fuer: try #require(Tag(iso: "2027-01-04"))) == "2026/27")
        #expect(Lernendenbestand.schuljahr(fuer: try #require(Tag(iso: "1999-09-01"))) == "1999/00")
    }

    // ── Eingabe von Hand (E273) ───────────────────────────────────────────

    @Test("Namenszeilen: mit Komma eindeutig, ohne Komma das letzte Wort als Nachname, Fehler benannt")
    func namenszeilen() {
        let text = [
            "Müller, Anna",              // 1
            "Anna Lena Schmidt",         // 2
            "",                          // 3
            "von der Heide, Jan",        // 4
            "  Ömer\tÜnal  ",            // 5
            "Müller, Anna, Lena",        // 6 — zwei Kommas
            "Einwort",                   // 7 — nur ein Wort
            " , ",                       // 8 — leer um das Komma
            "Zuse,",                     // 9 — Nachname allein, bewusst
            String(repeating: "q", count: 101) + ", Max",  // 10 — zu lang
        ].joined(separator: "\r\n")
        let e = Namenszeilen.lesen(text)
        #expect(e.namen == [
            .init(vorname: "Anna", nachname: "Müller"),
            .init(vorname: "Anna Lena", nachname: "Schmidt"),
            .init(vorname: "Jan", nachname: "von der Heide"),
            .init(vorname: "Ömer", nachname: "Ünal"),
            .init(vorname: "", nachname: "Zuse"),
        ])
        #expect(e.fehler.map(\.nummer) == [6, 7, 8, 10], "die Zeilennummern zählen leere Zeilen mit")

        let viele = (0...Kennwerte.maxMitgliederJeLerngruppe).map { "Name\($0), V" }.joined(separator: "\n")
        let grenze = Namenszeilen.lesen(viele)
        #expect(grenze.namen.count == Kennwerte.maxMitgliederJeLerngruppe)
        #expect(grenze.fehler.map(\.nummer) == [Kennwerte.maxMitgliederJeLerngruppe + 1])
    }

    // ── Ändern im Blatt (AP7): reine Funktionen am Wert ────────────────────

    @Test("Gruppe anlegen, umbenennen, archivieren und zurückholen — Texte bereinigt, Grenze beachtet")
    func gruppenAendern() throws {
        let leer = Lernendenbestand.leer(planung: Self.herkunft, schuljahr: "2026/27", jetzt: Self.stempel)
        let (mitGruppe, id) = try #require(leer.mitNeuerGruppe(name: "  7b\nBio ", fach: "Biologie", art: .kurs, jetzt: Self.stempel))
        #expect(id.hasPrefix("g-") && Kennung.istGueltig(id))
        let g = try #require(mitGruppe.lerngruppen.first)
        #expect(g.name == "7b Bio" && g.fach == "Biologie" && g.art == .kurs && g.mitglieder.isEmpty && g.geaendert == Self.stempel)
        #expect(leer.mitNeuerGruppe(name: "   ", fach: "", art: .klasse, jetzt: Self.stempel) == nil, "ohne Namen keine Gruppe")
        let umbenannt = mitGruppe.mitGruppe(id, name: "7b", fach: "Chemie", jetzt: "2026-10-04T08:00:00.000Z")
        #expect(umbenannt.lerngruppen.first?.name == "7b" && umbenannt.lerngruppen.first?.fach == "Chemie")
        #expect(mitGruppe.mitGruppe(id, name: "", fach: "x", jetzt: Self.stempel) == mitGruppe, "ein leerer Name ändert nichts")
        #expect(umbenannt.mitGruppe(id, name: " 7b ", fach: "Chemie", jetzt: "2026-10-05T08:00:00.000Z") == umbenannt,
                "derselbe Name ändert nichts — auch nicht den Zeitstempel")
        #expect(umbenannt.mitArt(id, .kurs, jetzt: "2026-10-05T08:00:00.000Z") == umbenannt, "dieselbe Art ändert nichts")
        #expect(umbenannt.mitArt(id, .klasse, jetzt: Self.stempel).lerngruppen.first?.art == .klasse)
        let archiviert = umbenannt.mitArchivierterGruppe(id, jetzt: Self.stempel)
        #expect(archiviert.lerngruppen.first?.archiviert == Self.stempel)
        #expect(archiviert.mitZurueckgeholterGruppe(id, jetzt: "2026-10-05T08:00:00.000Z").lerngruppen.first?.archiviert.isEmpty == true)

        var voll = leer
        for i in 0..<Kennwerte.maxLerngruppen { voll = try #require(voll.mitNeuerGruppe(name: "G\(i)", fach: "", art: .klasse, jetzt: Self.stempel)).bestand }
        #expect(voll.mitNeuerGruppe(name: "zu viel", fach: "", art: .klasse, jetzt: Self.stempel) == nil, "an der Grenze keine weitere")
    }

    @Test("Namen in eine Gruppe: neue Personen mit Importkennung, Gleiche in der Gruppe übergangen, Grenze 40")
    func personenEintragen() throws {
        var b = bestand()
        let namen = Namenszeilen.lesen("Neu, Nora\nabel,   ANNA\nÖzil, Mesut").namen
        let ergebnis = b.mitPersonen(namen, inGruppe: "g-1", jetzt: "2026-10-04T09:00:00.000Z")
        b = ergebnis.bestand
        #expect(ergebnis.neu.count == 2 && ergebnis.schonDa == 1 && ergebnis.ueberGrenze == 0,
                "„abel, ANNA“ ist Anna Abel — Groß/Klein und Leerraum unerheblich")
        #expect(ergebnis.neu.allSatisfy { $0.hasPrefix("l-") })
        let nora = try #require(b.lernende.first { $0.nachname == "Neu" })
        #expect(nora.vorname == "Nora" && nora.angelegt == "2026-10-04T09:00:00.000Z", "die Importkennung ist der Zeitpunkt der Anlage")
        #expect(b.lerngruppen[0].mitglieder.suffix(2) == ArraySlice(ergebnis.neu))

        // Bis 40 Mitglieder (E279), was darüber ist, wird gezählt.
        let viele = (0..<70).map { Namenszeilen.Name(vorname: "V\($0)", nachname: "N\($0)") }
        let voll = b.mitPersonen(viele, inGruppe: "g-1", jetzt: Self.stempel)
        #expect(voll.bestand.lerngruppen[0].mitglieder.count == Kennwerte.maxMitgliederJeLerngruppe)
        #expect(voll.ueberGrenze == 70 - (Kennwerte.maxMitgliederJeLerngruppe - b.lerngruppen[0].mitglieder.count))
        #expect(b.mitPersonen(namen, inGruppe: "g-9", jetzt: Self.stempel).neu.isEmpty, "unbekannte Gruppe: nichts")
    }

    @Test("Über die ganze Jahresdatei (E288): eine Person einer anderen Gruppe wird zugeordnet, nicht neu angelegt; mehrere werden genannt; Archivierte zählen nicht")
    func zuordnenStattNeu() throws {
        let s = Self.stempel
        // Dora Dietz (l-4) steht in keiner Gruppe von g-1 — aber in der Jahresdatei.
        let e = bestand().mitPersonen(Namenszeilen.lesen("Dietz, Dora\nNeu, Nora\nAbel, Anna").namen, inGruppe: "g-1", jetzt: s)
        #expect(e.ausgaenge.count == 3 && e.zugeordnet == ["l-4"] && e.neu.count == 1 && e.schonDa == 1)
        #expect(e.bestand.lernende.count == 5, "Dora ist dieselbe Person, keine neue")
        #expect(e.bestand.lerngruppen[0].mitglieder.contains("l-4"))
        // Zwei aktive „Max Mai“ außerhalb der Gruppe: genannt, nichts geraten, nichts geändert.
        var zwei = bestand()
        for id in ["l-8", "l-9"] {
            zwei.lernende.append(Lernender(id: id, vorname: "Max", nachname: "Mai", angelegt: s, geaendert: s, archiviert: ""))
        }
        let m = zwei.mitPersonen([Namenszeilen.Name(vorname: "Max", nachname: "Mai")], inGruppe: "g-1", jetzt: s)
        #expect(m.ausgaenge == [.gleichnamig] && m.bestand == zwei)
        // Eine archivierte Person gleichen Namens wird nicht zugeordnet.
        let a = bestand().mitArchivierterPerson("l-4", jetzt: s)
            .mitPersonen([Namenszeilen.Name(vorname: "Dora", nachname: "Dietz")], inGruppe: "g-1", jetzt: s)
        #expect(a.neu.count == 1 && a.zugeordnet.isEmpty)
    }

    @Test("Person bearbeiten und aus einer Gruppe nehmen — die Person bleibt, ihre Einträge bleiben")
    func personAendern() throws {
        let b = bestand()
        let bearbeitet = b.mitPerson("l-2", vorname: " Benjamin ", nachname: "Bauer-Klein", jetzt: "2026-10-04T08:00:00.000Z")
        #expect(bearbeitet.lernende[1].vorname == "Benjamin" && bearbeitet.lernende[1].nachname == "Bauer-Klein")
        #expect(bearbeitet.lernende[1].angelegt == Self.stempel, "die Importkennung bleibt")
        #expect(b.mitPerson("l-2", vorname: "", nachname: " ", jetzt: Self.stempel) == b, "ohne Namen ändert sich nichts")
        #expect(bearbeitet.mitPerson("l-2", vorname: "Benjamin", nachname: "Bauer-Klein", jetzt: Self.stempel) == bearbeitet,
                "derselbe Name ändert nichts")
        let ohne = b.ohneMitglied("l-1", ausGruppe: "g-1")
        #expect(ohne.lerngruppen[0].mitglieder == ["l-2", "l-3"] && ohne.lernende.count == 4)
        #expect(ohne.erfassung.count == 1 && ohne.rueckmeldungen.count == 3, "Einträge und Rückläufe bleiben")
    }

    // ── Löschen samt allem, was daran hängt (E252, E276) ──────────────────

    @Test("Person endgültig löschen: Mitgliedschaft, Betroffenheit, Rückläufe, Einträge — eine Maßnahme nur für sie geht mit")
    func personLoeschen() {
        let (b, zahl) = bestand().ohnePerson("l-2")
        #expect(!b.lernende.contains { $0.id == "l-2" })
        #expect(b.lerngruppen[0].mitglieder == ["l-1", "l-3"])
        #expect(b.anliegen.map(\.id) == ["m-1"] && b.anliegen[0].betroffene == ["l-1", "l-3"])
        #expect(!b.rueckmeldungen.contains { $0.lernender == "l-2" })
        #expect(zahl == Lernendenbestand.Loeschzahl(personen: 1, gruppen: 0, anliegen: 1, rueckmeldungen: 2, eintraege: 0))

        let (c, zahl1) = bestand().ohnePerson("l-1")
        #expect(c.erfassung.isEmpty && c.beurteilung.isEmpty)
        #expect(zahl1 == Lernendenbestand.Loeschzahl(personen: 1, gruppen: 0, anliegen: 0, rueckmeldungen: 1, eintraege: 2))
        #expect(bestand().ohnePerson("l-9").zahl == Lernendenbestand.Loeschzahl(), "Unbekanntes löscht nichts")
    }

    @Test("Gruppe löschen: ihre Mitteilungen samt Rückläufen und ihre Einträge gehen, Personen und Maßnahmen bleiben")
    func gruppeLoeschen() {
        var start = bestand()
        start.anliegen[1].lerngruppe = "g-1"
        let (b, zahl) = start.ohneGruppe("g-1")
        #expect(b.lerngruppen.isEmpty && b.lernende.count == 4)
        #expect(b.anliegen.map(\.id) == ["m-2"] && b.anliegen[0].lerngruppe.isEmpty)
        #expect(b.rueckmeldungen.map(\.anliegen) == ["m-2"])
        #expect(b.erfassung.isEmpty && b.beurteilung.isEmpty)
        #expect(zahl == Lernendenbestand.Loeschzahl(personen: 0, gruppen: 1, anliegen: 1, rueckmeldungen: 2, eintraege: 2))
    }

    @Test("Einzelnes löschen: ein Anliegen samt Rückläufen, ein Eintrag der Erfassung oder Beurteilung")
    func einzelnesLoeschen() {
        let (a, zahlA) = bestand().ohneAnliegen("m-1")
        #expect(a.anliegen.map(\.id) == ["m-2"] && a.rueckmeldungen.count == 1)
        #expect(zahlA == Lernendenbestand.Loeschzahl(personen: 0, gruppen: 0, anliegen: 1, rueckmeldungen: 2, eintraege: 0))
        let (e, zahlE) = bestand().ohneEintrag("a-1")
        #expect(e.erfassung.isEmpty && e.beurteilung.count == 1 && zahlE.eintraege == 1)
        let (f, zahlF) = bestand().ohneEintrag("b-1")
        #expect(f.beurteilung.isEmpty && f.erfassung.count == 1 && zahlF.eintraege == 1)
    }


    // ── Anliegen im Blatt (AP8): reine Funktionen am Wert ─────────────────

    @Test("Mitteilung und Maßnahme anlegen — Titel bereinigt, Tage geprüft, nur bekannte Betroffene, Grenze der Anliegen")
    func anliegenAnlegen() throws {
        let s = Self.stempel
        let b = bestand()
        let (m, id) = try #require(b.mitNeuemAnliegen(.mitteilung, titel: "  Einverständnis\nVideo ", lerngruppe: "g-1",
                                                       betroffene: ["l-1", "l-2", "l-9", "l-1"], datum: "2026-10-05",
                                                       frist: "kein Tag", jetzt: s))
        let a = try #require(m.anliegen.first { $0.id == id })
        #expect(id.hasPrefix("m-") && Kennung.istGueltig(id))
        #expect(a.titel == "Einverständnis Video" && a.art == .mitteilung && a.lerngruppe == "g-1")
        #expect(a.betroffene == ["l-1", "l-2"], "nur bekannte, jede einmal")
        #expect(a.datum == "2026-10-05" && a.frist.isEmpty && a.angelegt == s && a.geaendert == s)
        #expect(try Lernendendatei.lesen(try Lernendendatei.schreiben(m)) == m, "liest sich zurück, wie es geschrieben wurde")
        #expect(b.mitNeuemAnliegen(.mitteilung, titel: " ", lerngruppe: "g-1", betroffene: ["l-1"], datum: "",
                                   frist: "", jetzt: s)?.id == nil, "ohne Titel nichts")
        #expect(b.mitNeuemAnliegen(.mitteilung, titel: "X", lerngruppe: "g-9", betroffene: ["l-1"], datum: "",
                                   frist: "", jetzt: s)?.id == nil, "eine Mitteilung braucht ihre Gruppe")
        let (n, mid) = try #require(b.mitNeuemAnliegen(.massnahme, titel: "Nacharbeit AB 4", lerngruppe: "g-1",
                                                       betroffene: ["l-3"], datum: "2026-10-05", frist: "2026-10-12", jetzt: s))
        let massnahme = n.anliegen.first { $0.id == mid }
        #expect(massnahme?.frist == "2026-10-12" && massnahme?.betroffene == ["l-3"])
        var voll = b
        voll.anliegen = (0..<Lernendendatei.maxAnliegen).map {
            Anliegen(id: "m-x\($0)", art: .massnahme, titel: "M", lerngruppe: "", betroffene: [], datum: "", frist: "",
                     notiz: "", angelegt: s, geaendert: s)
        }
        #expect(voll.mitNeuemAnliegen(.massnahme, titel: "eins zu viel", lerngruppe: "", betroffene: ["l-1"], datum: "",
                                      frist: "", jetzt: s)?.id == nil, "an der Grenze nichts mehr")
    }

    @Test("Anliegen ändern — gleiche Werte und ein leerer Titel ändern nichts, ein falscher Tag wird leer")
    func anliegenAendern() {
        let b = bestand()
        let alt = b.anliegen[0]
        let c = b.mitAnliegen("m-1", titel: "Elternbrief Wandertag 2", datum: "2026-10-01", frist: "33.13.",
                              notiz: " bis Freitag ", jetzt: "2026-10-04T08:00:00.000Z")
        #expect(c.anliegen[0].titel == "Elternbrief Wandertag 2" && c.anliegen[0].frist.isEmpty)
        #expect(c.anliegen[0].notiz == "bis Freitag" && c.anliegen[0].geaendert == "2026-10-04T08:00:00.000Z")
        #expect(b.mitAnliegen("m-1", titel: "", datum: "", frist: "", notiz: "", jetzt: "später") == b)
        #expect(b.mitAnliegen("m-1", titel: alt.titel, datum: alt.datum, frist: alt.frist, notiz: alt.notiz, jetzt: "später") == b)
        #expect(b.mitAnliegen("m-9", titel: "X", datum: "", frist: "", notiz: "", jetzt: "später") == b)
    }

    @Test("Betroffene hinzu und heraus — wer herausgeht, verliert seinen Rücklauf")
    func betroffeneAendern() {
        let s = Self.stempel
        let b = bestand()
        let ohne = b.mitBetroffenem("m-1", "l-1", false, jetzt: s)
        #expect(ohne.anliegen[0].betroffene == ["l-2", "l-3"])
        #expect(!ohne.rueckmeldungen.contains { $0.anliegen == "m-1" && $0.lernender == "l-1" })
        #expect(ohne.mitBetroffenem("m-1", "l-1", true, jetzt: s).anliegen[0].betroffene == ["l-2", "l-3", "l-1"])
        #expect(b.mitBetroffenem("m-1", "l-9", true, jetzt: s) == b, "Unbekannte nicht")
        #expect(b.mitBetroffenem("m-1", "l-1", true, jetzt: s) == b, "schon betroffen: nichts")
    }

    @Test("Rücklauf eintragen: drei Stände, „offen“ ohne Notiz ist kein Eintrag, nur Betroffene, Tag geprüft")
    func ruecklaufEintragen() throws {
        let s = Self.stempel
        let b = bestand()
        let c = b.mitRuecklauf("m-1", "l-3", stand: .erledigt, datum: "2026-10-05", notiz: " unterschrieben ", jetzt: s)
        let r = try #require(c.rueckmeldungen.first { $0.anliegen == "m-1" && $0.lernender == "l-3" })
        #expect(r.stand == .erledigt && r.datum == "2026-10-05" && r.notiz == "unterschrieben" && r.geaendert == s)
        let d = c.mitRuecklauf("m-1", "l-2", stand: .erledigt, datum: "kein Tag", notiz: "", jetzt: s)
        let ersetzt = d.rueckmeldungen.filter { $0.anliegen == "m-1" && $0.lernender == "l-2" }
        #expect(ersetzt.count == 1 && ersetzt.first?.stand == .erledigt && ersetzt.first?.datum == "", "ersetzt, nicht verdoppelt")
        let e = b.mitRuecklauf("m-1", "l-1", stand: .offen, datum: "2026-10-05", notiz: "", jetzt: s)
        #expect(!e.rueckmeldungen.contains { $0.anliegen == "m-1" && $0.lernender == "l-1" }, "offen ohne Notiz: kein Eintrag")
        let f = b.mitRuecklauf("m-1", "l-1", stand: .offen, datum: "", notiz: "fragt nach", jetzt: s)
        #expect(f.rueckmeldungen.first { $0.anliegen == "m-1" && $0.lernender == "l-1" }?.stand == .offen, "offen mit Notiz bleibt")
        #expect(b.mitRuecklauf("m-1", "l-4", stand: .erledigt, datum: "", notiz: "", jetzt: s) == b, "nur Betroffene")
        #expect(b.mitRuecklauf("m-1", "l-1", stand: .erledigt, datum: "2026-10-03", notiz: "", jetzt: "später") == b,
                "gleich: nichts")
        #expect(try Lernendendatei.lesen(try Lernendendatei.schreiben(d)) == d, "liest sich zurück, wie es geschrieben wurde")
    }

    @Test("Verzeichnis der Anliegen: Mitteilungen der Gruppe, Maßnahmen der Personen, Rücklauf und offene Zahl je Person")
    func verzeichnisAnliegen() {
        let v = Lernendenverzeichnis(bestand())
        #expect(v.mitteilungen(der: "g-1").map(\.id) == ["m-1"])
        #expect(v.massnahmen(fuer: ["l-1", "l-2"]).map(\.id) == ["m-2"] && v.massnahmen(fuer: ["l-1"]).isEmpty)
        #expect(v.rueckmeldung("m-1", "l-2")?.notiz == "kein Einverständnis" && v.rueckmeldung("m-1", "l-3") == nil)
        #expect(v.offeneZahl(von: "l-3") == 1 && v.offeneZahl(von: "l-2") == 1 && v.offeneZahl(von: "l-1") == 0)
        #expect(v.offeneZahl(von: "l-2") == v.offeneAnliegen(von: "l-2").count, "gezählt wie gelistet")
    }

    @Test("Offene Anliegen der Gruppe (Verwaltungszeile): Anliegen, nicht Einträge je Person — wie das Blatt sie zeigt")
    func offeneAnliegenDerGruppe() {
        let s = Self.stempel
        // m-1 (Mitteilung an g-1): l-3 noch offen; m-2 (Maßnahme für l-2): offen → zwei Anliegen,
        // obwohl je Person gezählt l-2 und l-3 je eines tragen.
        #expect(Lernendenverzeichnis(bestand()).offeneAnliegenzahl(der: "g-1") == 2)
        // Ein Anliegen bleibt eines, auch wenn drei offen stehen.
        let ohneRuecklauf = Lernendenbestand(
            planung: bestand().planung, schuljahr: bestand().schuljahr, erstellt: s, geaendert: s,
            lernende: bestand().lernende, lerngruppen: bestand().lerngruppen, anliegen: bestand().anliegen,
            rueckmeldungen: [], erfassung: [], beurteilung: [])
        #expect(Lernendenverzeichnis(ohneRuecklauf).offeneAnliegenzahl(der: "g-1") == 2)
        // Alle erledigt oder abgelehnt → keines offen.
        let erledigt = bestand()
            .mitRuecklauf("m-1", "l-3", stand: .erledigt, datum: "2026-10-05", notiz: "", jetzt: s)
            .mitRuecklauf("m-2", "l-2", stand: .abgelehnt, datum: "2026-10-05", notiz: "", jetzt: s)
        #expect(Lernendenverzeichnis(erledigt).offeneAnliegenzahl(der: "g-1") == 0)
        // Eine Maßnahme zählt nur über die Mitglieder der Gruppe: steht nur noch l-4 (kein
        // Mitglied) offen, zählt sie für g-1 nicht. Eine fremde Gruppe zählt null.
        let nachschrift = Anliegen(id: "m-3", art: .massnahme, titel: "Nachschrift", lerngruppe: "",
                                   betroffene: ["l-2", "l-4"], datum: "2026-10-02", frist: "",
                                   notiz: "", angelegt: s, geaendert: s)
        let mitFremdem = Lernendenbestand(
            planung: bestand().planung, schuljahr: bestand().schuljahr, erstellt: s, geaendert: s,
            lernende: bestand().lernende, lerngruppen: bestand().lerngruppen,
            anliegen: bestand().anliegen + [nachschrift],
            rueckmeldungen: bestand().rueckmeldungen
                + [Rueckmeldung(anliegen: "m-3", lernender: "l-2", stand: .erledigt, datum: "2026-10-05",
                                notiz: "", geaendert: s)],
            erfassung: [], beurteilung: [])
        #expect(Lernendenverzeichnis(mitFremdem).offeneAnliegenzahl(der: "g-1") == 2)
        #expect(Lernendenverzeichnis(bestand()).offeneAnliegenzahl(der: "g-fremd") == 0)
    }

    @Test("Sitzplatzvorlage einer Gruppe: aktive Mitglieder in der Ordnung des Verzeichnisses, „Vorname Nachname“, Rufname statt Vorname (E252, E255, E285)")
    func sitzplatzvorlage() {
        let s = Self.stempel
        #expect(Lernendenverzeichnis(bestand()).sitzplatzvorlage(der: "g-1")
                == [Sitzplan.Platzvorlage(name: "Anna Abel", lernender: "l-1"),
                    Sitzplan.Platzvorlage(name: "Ben Bauer", lernender: "l-2"),
                    Sitzplan.Platzvorlage(name: "Cem Çelik", lernender: "l-3")])
        // Archivierte gehören nicht ins Angebot; ein fehlender Vorname lässt den Nachnamen.
        let anders = bestand().mitArchivierterPerson("l-2", jetzt: s).mitPerson("l-3", vorname: "", nachname: "Çelik", jetzt: s)
        #expect(Lernendenverzeichnis(anders).sitzplatzvorlage(der: "g-1").map(\.name) == ["Anna Abel", "Çelik"])
        // Der Rufname steht statt des Vornamens (E285).
        let gerufen = bestand().mitPerson("l-1", vorname: "Anna Maria", nachname: "Abel", rufname: "Anni", jetzt: s)
        #expect(Lernendenverzeichnis(gerufen).sitzplatzvorlage(der: "g-1").first?.name == "Anni Abel")
        #expect(Lernendenverzeichnis(bestand()).sitzplatzvorlage(der: "g-fremd").isEmpty)
    }

    // ── Zeitstempel: der schnelle Weg (AP9) ────────────────────────────────

    @Test("Zeitstempel: der schnelle Weg urteilt wie der Datumsformatierer — an rund 20 000 erzeugten Stempeln")
    func zeitstempelSchnell() {
        var faelle: [String] = []
        let jahre = [1899, 1900, 1904, 1999, 2000, 2024, 2026, 2100, 2199, 2200]
        let zeiten = ["00:00:00.000", "23:59:59.999", "24:00:00.000", "12:60:00.000", "12:00:60.000", "08:15:30.123"]
        for jahr in jahre {
            for monat in 0...13 {
                for tag in 0...32 {
                    for zeit in zeiten {
                        faelle.append(String(format: "%04d-%02d-%02dT", jahr, monat, tag) + zeit + "Z")
                    }
                }
            }
        }
        faelle += ["", "2026-10-03T08:00:00Z", "2026-10-03", "2026-10-03T08:00:00.000z", "2026-10-03 08:00:00.000Z",
                   "2026-10-03T08:00:00.000+00:00", " 2026-10-03T08:00:00.000Z", "2026-10-03T08:00:00.0000Z",
                   "2026-1O-03T08:00:00.000Z", "\u{FF12}026-10-03T08:00:00.000Z", "2026-10-03T08:00:00.000Z\u{0}"]
        var abweichend: [String] = []
        for fall in faelle where Zeitrechnung.istZeitstempel(fall) != (Zeitrechnung.zeitpunkt(aus: fall) != nil) {
            abweichend.append(fall)
        }
        #expect(faelle.count > 20_000)
        #expect(abweichend.isEmpty, Comment(rawValue: "\(abweichend.count) abweichend: \(abweichend.prefix(5))"))
        // Der schnelle Weg ist streng; der Formatierer ist nachsichtig (er nimmt den
        // 29.02.2100) — das Urteil bleibt seins, gemessen oben an allen Fällen.
        #expect(Zeitrechnung.istUeblicherZeitstempel("2024-02-29T00:00:00.000Z"))
        #expect(!Zeitrechnung.istUeblicherZeitstempel("2100-02-29T00:00:00.000Z"))
        #expect(Zeitrechnung.istZeitstempel("2100-02-29T00:00:00.000Z") == (Zeitrechnung.zeitpunkt(aus: "2100-02-29T00:00:00.000Z") != nil))
    }

    // ── Bindung an Zeilen der Planung (AP10, E248) ────────────────────────

    @Test("Binden und lösen: eine Zeile trägt höchstens eine Gruppe, Archivierte zählen nicht, Grenze der Zeilen")
    func bindung() throws {
        let s = Self.stempel
        var b = bestand()
        b.lerngruppen.append(Lerngruppe(id: "g-2", name: "AG", fach: "", art: .kurs, mitglieder: ["l-4"], zeilen: [],
                                        skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: ""))
        let zeile = Zeilenbindung(planung: Self.herkunft, klasseId: "k-1")
        #expect(b.gruppe(an: zeile)?.id == "g-1", "die Saat bindet g-1 an k-1")
        let umgebunden = b.mitBindung("g-2", an: zeile, jetzt: s)
        #expect(umgebunden.gruppe(an: zeile)?.id == "g-2")
        #expect(umgebunden.lerngruppen[0].zeilen.isEmpty, "die Zeile wurde bei g-1 gelöst")
        #expect(umgebunden.mitBindung("g-2", an: zeile, jetzt: "später") == umgebunden, "schon gebunden: nichts")
        let geloest = umgebunden.ohneBindung(zeile, jetzt: s)
        #expect(geloest.gruppe(an: zeile) == nil && geloest.lerngruppen.allSatisfy { !$0.zeilen.contains(zeile) })
        #expect(geloest.ohneBindung(zeile, jetzt: "später") == geloest, "nicht gebunden: nichts")
        #expect(b.mitArchivierterGruppe("g-1", jetzt: s).gruppe(an: zeile) == nil, "eine archivierte Gruppe zeigt keine Zeile")
        #expect(b.mitBindung("g-9", an: zeile, jetzt: s) == b, "unbekannte Gruppe: nichts")
        var voll = b
        voll.lerngruppen[1].zeilen = (0..<Lernendendatei.maxZeilenJeGruppe).map { Zeilenbindung(planung: Self.herkunft, klasseId: "k-x\($0)") }
        #expect(voll.mitBindung("g-2", an: zeile, jetzt: s) == voll, "an der Grenze der Zeilen: nichts")
        #expect(try Lernendendatei.lesen(try Lernendendatei.schreiben(umgebunden)) == umgebunden)
    }

    @Test("Eingabe von Hand: eine archivierte Person der Gruppe gleichen Namens wird zurückgeholt, dieselbe Person (E299)")
    func archivierteZurueckholenVonHand() {
        let s = "2026-10-03T08:00:00.000Z"
        let jetzt = "2026-10-05T09:00:00.000Z"
        var b = Lernendenbestand.leer(planung: "2026-08-01T08:00:00.000Z", schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: s)]
        b.lerngruppen = [Lerngruppe(id: "g-1", name: "6a", fach: "", art: .klasse, mitglieder: ["l-1"], zeilen: [],
                                    skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        let e = b.mitPersonen(Namenszeilen.lesen("Abel, Anna").namen, inGruppe: "g-1", jetzt: jetzt)
        #expect(e.ausgaenge == [.zurueckgeholt("l-1")] && e.zurueckgeholt == ["l-1"])
        #expect(e.bestand.lernende.count == 1 && e.bestand.lernende[0].archiviert.isEmpty)
    }

    @Test("Zurückholen stempelt Person bzw. Gruppe und den Bestand (W1-09)")
    func zurueckholenStempelt() {
        let s = "2026-10-03T08:00:00.000Z"
        let jetzt = "2026-10-05T09:00:00.000Z"
        var b = Lernendenbestand.leer(planung: "2026-08-01T08:00:00.000Z", schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: s)]
        b.lerngruppen = [Lerngruppe(id: "g-1", name: "6a", fach: "", art: .klasse, mitglieder: ["l-1"], zeilen: [],
                                    skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: s)]
        let person = b.mitZurueckgeholterPerson("l-1", jetzt: jetzt)
        #expect(person.lernende[0].archiviert.isEmpty && person.lernende[0].geaendert == jetzt && person.geaendert == jetzt)
        let gruppe = b.mitZurueckgeholterGruppe("g-1", jetzt: jetzt)
        #expect(gruppe.lerngruppen[0].archiviert.isEmpty && gruppe.lerngruppen[0].geaendert == jetzt && gruppe.geaendert == jetzt)
    }

}

