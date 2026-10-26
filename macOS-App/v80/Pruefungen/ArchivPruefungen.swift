// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Das Archiv der Vorjahre und der Schuljahreswechsel als Funktion (v80, AP2) ─
// Archiv hin und zurück, die neue Jahresdatei nach E271 (nur Gewähltes, gleiche
// Kennungen, nur Offenes), die drei Löschungen nach E276 und der Leser des
// Archivs. Reine Funktionen — der Übergang über drei Dateien folgt in AP5.

@Suite("Archiv: Vorjahre, Jahreswechsel als Funktion, Löschungen")
struct ArchivPruefungen {

    private static let stempel = "2026-10-03T08:00:00.000Z"
    private static let spaeter = "2027-07-20T08:00:00.000Z"

    private func planung(_ start: String = "2026-08-03") throws -> Planung {
        Planung.leer(titel: "Planung \(start)", start: try #require(Tag(iso: start)), wochen: 4, basis: "",
                     klassen: Standardkurse.aufbauen([("6a", "Biologie"), ("7b", "Chemie")]), fachfarben: [:])
    }

    /// Zwei Gruppen an den beiden Klassen der Planung. In g-1: Anna (Mitteilung
    /// erledigt), Ben (Mitteilung offen mit Notiz, Maßnahme erfüllt), Cem
    /// (Mitteilung ohne Rücklauf = offen). In g-2: Dora (Maßnahme und
    /// Mitteilung offen) und Emil (archiviert). Dazu eine Maßnahme aus g-2 für
    /// Anna, offen — Anna kommt über g-1 mit.
    private func bestand(_ p: Planung) -> Lernendenbestand {
        let s = Self.stempel
        func person(_ id: String, _ vor: String, _ nach: String, archiviert: String = "") -> Lernender {
            Lernender(id: id, vorname: vor, nachname: nach, angelegt: "2026-09-01T07:00:00.000Z", geaendert: s,
                      archiviert: archiviert)
        }
        func gruppe(_ id: String, _ name: String, _ klasse: String, _ mitglieder: [String]) -> Lerngruppe {
            Lerngruppe(id: id, name: name, fach: "", art: .klasse, mitglieder: mitglieder,
                       zeilen: [Zeilenbindung(planung: p.erstellt, klasseId: klasse)],
                       skalen: ["muendlich": "fuenfstufig"], halbjahreswechsel: "2027-01-29", geaendert: s, archiviert: "")
        }
        func anliegen(_ id: String, _ art: Anliegenart, _ gruppe: String, _ betroffene: [String]) -> Anliegen {
            Anliegen(id: id, art: art, titel: "Anliegen \(id)", lerngruppe: gruppe, betroffene: betroffene,
                     datum: "2026-10-01", frist: "", notiz: "", angelegt: s, geaendert: s)
        }
        func rueck(_ a: String, _ l: String, _ stand: Rueckmeldestand, notiz: String = "") -> Rueckmeldung {
            Rueckmeldung(anliegen: a, lernender: l, stand: stand, datum: "", notiz: notiz, geaendert: s)
        }
        return Lernendenbestand(
            planung: p.erstellt, schuljahr: "2026/27", erstellt: s, geaendert: s,
            lernende: [person("l-1", "Anna", "Abel"), person("l-2", "Ben", "Bauer"), person("l-3", "Cem", "Çelik"),
                       person("l-4", "Dora", "Dietz"), person("l-5", "Emil", "Ernst", archiviert: s)],
            lerngruppen: [gruppe("g-1", "6a", p.klassen[0].id, ["l-1", "l-2", "l-3"]),
                          gruppe("g-2", "7b", p.klassen[1].id, ["l-4", "l-5"])],
            anliegen: [anliegen("m-1", .mitteilung, "g-1", ["l-1", "l-2", "l-3"]),
                       anliegen("m-2", .massnahme, "g-1", ["l-2"]),
                       anliegen("m-3", .massnahme, "g-2", ["l-4"]),
                       anliegen("m-4", .mitteilung, "g-2", ["l-4", "l-5"]),
                       anliegen("m-5", .massnahme, "g-2", ["l-1"])],
            rueckmeldungen: [rueck("m-1", "l-1", .erledigt), rueck("m-1", "l-2", .offen, notiz: "kommt Montag"),
                             rueck("m-2", "l-2", .erledigt), rueck("m-4", "l-5", .erledigt)],
            erfassung: [Erfassungseintrag(id: "a-1", lernender: "l-1", lerngruppe: "g-1", planung: p.erstellt,
                                          vorhaben: "", datum: "2026-10-05", art: .muendlich, wert: "+",
                                          notiz: "", angelegt: s, geaendert: s)],
            beurteilung: [Beurteilung(id: "b-1", lernender: "l-2", lerngruppe: "g-1", schuljahr: "2026/27",
                                      halbjahr: 1, zeugnisnote: "", notiz: "", geaendert: s)])
    }

    // ── Archiv hin und zurück ─────────────────────────────────────────────

    @Test("Archiv hin und zurück: zwei Jahre, eines ohne Jahresdatei, kanonisch, leere Bilanz")
    func hinUndZurueck() throws {
        let p1 = try planung("2026-08-03")
        let p2 = try planung("2027-08-02")
        let b = bestand(p1)
        let archiv = Archivbestand.leer.mitJahr(planung: p1, lernende: b, jetzt: Self.spaeter)
            .mitJahr(planung: p2, lernende: nil, jetzt: Self.spaeter)
        #expect(archiv.jahre.map(\.schuljahr) == ["2026/27", "2027/28"], "aus der Jahresdatei, sonst aus dem Beginn")
        #expect(Set(archiv.jahre.map(\.id)).count == 2 && archiv.jahre.allSatisfy { $0.id.hasPrefix("j-") })
        let daten = try Archivdatei.schreiben(archiv)
        let (gelesen, bilanz) = try Archivdatei.lesenMitBilanz(daten)
        #expect(bilanz.istLeer, "\(bilanz.beschreibung)")
        #expect(try Archivdatei.schreiben(gelesen) == daten, "kanonisch")
        #expect(gelesen.jahre[0].lernende == b && gelesen.jahre[1].lernende == nil)
        #expect(try Planungsdatei.schreiben(gelesen.jahre[0].planung) == (try Planungsdatei.schreiben(p1)))
        #expect(try Archivdatei.lesen(try Archivdatei.schreiben(.leer)).jahre.isEmpty)
    }

    // ── Der Schuljahreswechsel als Funktion (E271) ────────────────────────

    @Test("Neue Jahresdatei: nur gewählte Gruppen, gleiche Kennungen, neue Zeilen, nur das Offene")
    func neuesJahr() throws {
        let p1 = try planung()
        let b = bestand(p1)
        let k6a = p1.klassen[0].id, k7b = p1.klassen[1].id
        let zuordnung = [k6a: "k-neu-6a", k7b: "k-neu-7b"]

        let nur1 = b.neuesJahr(gruppen: ["g-1"], zuordnung: zuordnung, planung: "H2", schuljahr: "2027/28",
                               jetzt: Self.spaeter)
        #expect(nur1.planung == "H2" && nur1.schuljahr == "2027/28" && nur1.erstellt == Self.spaeter)
        #expect(nur1.lernende.map(\.id) == ["l-1", "l-2", "l-3"], "Dora und Emil hängen an g-2")
        #expect(nur1.lernende.allSatisfy { $0.angelegt == "2026-09-01T07:00:00.000Z" }, "die Importkennung bleibt")
        #expect(nur1.lerngruppen.map(\.id) == ["g-1"])
        #expect(nur1.lerngruppen[0].zeilen == [Zeilenbindung(planung: "H2", klasseId: "k-neu-6a")])
        #expect(nur1.lerngruppen[0].skalen == ["muendlich": "fuenfstufig"] && nur1.lerngruppen[0].halbjahreswechsel.isEmpty)
        #expect(nur1.anliegen.map(\.id) == ["m-1", "m-5"], "m-2 ist erfüllt, m-3/m-4 betreffen nur g-2")
        #expect(nur1.anliegen[0].betroffene == ["l-2", "l-3"], "nur der offene Teil der Mitteilung")
        #expect(nur1.anliegen[1].lerngruppe.isEmpty, "die Maßnahme aus g-2 kommt mit Anna, ohne ihre Gruppe")
        #expect(nur1.rueckmeldungen.map { "\($0.anliegen)/\($0.lernender)/\($0.notiz)" } == ["m-1/l-2/kommt Montag"])
        #expect(nur1.erfassung.isEmpty && nur1.beurteilung.isEmpty)

        let beide = b.neuesJahr(gruppen: ["g-1", "g-2"], zuordnung: zuordnung, planung: "H2", schuljahr: "2027/28",
                                jetzt: Self.spaeter)
        #expect(beide.lernende.map(\.id) == ["l-1", "l-2", "l-3", "l-4"], "Emil ist archiviert und bleibt im Archiv")
        #expect(beide.lerngruppen[1].mitglieder == ["l-4"])
        #expect(beide.anliegen.map(\.id) == ["m-1", "m-3", "m-4", "m-5"])
        #expect(beide.anliegen[3].lerngruppe == "g-2" && beide.anliegen[2].betroffene == ["l-4"])
        #expect(beide.rueckmeldungen.count == 1, "Emils erledigter Rücklauf bleibt im Archiv")

        let ohneZuordnung = b.neuesJahr(gruppen: ["g-1"], zuordnung: [:], planung: "H2", schuljahr: "2027/28",
                                        jetzt: Self.spaeter)
        #expect(ohneZuordnung.lerngruppen[0].zeilen.isEmpty, "nicht übernommene Zeile: Gruppe bleibt, ungebunden")
        #expect(b.neuesJahr(gruppen: [], zuordnung: zuordnung, planung: "H2", schuljahr: "2027/28",
                            jetzt: Self.spaeter).lernende.isEmpty)
    }

    // ── Die drei Löschungen (E276) ────────────────────────────────────────

    @Test("Ein ganzes Schuljahr löschen: die Zahl nennt, was darin war")
    func jahrLoeschen() throws {
        let p1 = try planung()
        let archiv = Archivbestand.leer.mitJahr(planung: p1, lernende: bestand(p1), jetzt: Self.stempel)
            .mitJahr(planung: try planung("2027-08-02"), lernende: nil, jetzt: Self.stempel)
        let (ohne, zahl) = archiv.ohneJahr(archiv.jahre[0].id, jetzt: Self.spaeter)
        #expect(ohne.jahre.map(\.id) == [archiv.jahre[1].id] && ohne.geaendert == Self.spaeter)
        #expect(zahl == Lernendenbestand.Loeschzahl(personen: 5, gruppen: 2, anliegen: 5, rueckmeldungen: 4,
                                                    eintraege: 2, jahre: 1))
        #expect(archiv.ohneJahr("j-unbekannt", jetzt: Self.spaeter).bestand == archiv)
    }

    @Test("Eine Person in der Jahresdatei und in allen Jahren löschen — dieselbe Kennung über die Jahre")
    func personUeberall() throws {
        let p1 = try planung(), p2 = try planung("2027-08-02")
        var vorjahr = bestand(p1)
        vorjahr.schuljahr = "2025/26"
        let archiv = Archivbestand.leer.mitJahr(planung: p1, lernende: vorjahr, jetzt: Self.stempel)
            .mitJahr(planung: p2, lernende: bestand(p2), jetzt: Self.stempel)
        let laufend = bestand(p2)

        let (archivOhne, zahlArchiv) = archiv.ohnePerson("l-2", jetzt: Self.spaeter)
        let (laufendOhne, zahlLaufend) = laufend.ohnePerson("l-2")
        for jahr in archivOhne.jahre { #expect(jahr.lernende?.lernende.contains { $0.id == "l-2" } == false) }
        #expect(!laufendOhne.lernende.contains { $0.id == "l-2" })
        // Je Jahr: Ben selbst, die Maßnahme m-2 nur für ihn, zwei Rückläufe, eine Beurteilung.
        let jeJahr = Lernendenbestand.Loeschzahl(personen: 1, gruppen: 0, anliegen: 1, rueckmeldungen: 2, eintraege: 1)
        #expect(zahlLaufend == jeJahr)
        #expect(zahlArchiv == jeJahr + jeJahr)
        #expect(archiv.ohnePerson("l-9", jetzt: Self.spaeter).bestand == archiv, "Unbekanntes ändert nichts")
    }

    @Test("Einzelnes im Archiv löschen: ein Anliegen samt Rückläufen, ein Eintrag — nur im genannten Jahr")
    func einzelnesImArchiv() throws {
        let p1 = try planung(), p2 = try planung("2027-08-02")
        let archiv = Archivbestand.leer.mitJahr(planung: p1, lernende: bestand(p1), jetzt: Self.stempel)
            .mitJahr(planung: p2, lernende: bestand(p2), jetzt: Self.stempel)
        let erstes = archiv.jahre[0].id
        let (a, zahlA) = archiv.ohneAnliegen("m-1", imJahr: erstes, jetzt: Self.spaeter)
        #expect(a.jahre[0].lernende?.anliegen.contains { $0.id == "m-1" } == false)
        #expect(a.jahre[1].lernende?.anliegen.contains { $0.id == "m-1" } == true, "das andere Jahr bleibt")
        #expect(zahlA == Lernendenbestand.Loeschzahl(anliegen: 1, rueckmeldungen: 2))
        let (e, zahlE) = archiv.ohneEintrag("a-1", imJahr: erstes, jetzt: Self.spaeter)
        #expect(e.jahre[0].lernende?.erfassung.isEmpty == true && zahlE.eintraege == 1)
        #expect(archiv.ohneEintrag("a-1", imJahr: "j-unbekannt", jetzt: Self.spaeter).bestand == archiv)
    }

    // ── Der Leser des Archivs ─────────────────────────────────────────────

    private func archivObjekt() throws -> [String: Any] {
        let p1 = try planung(), p2 = try planung("2027-08-02")
        let archiv = Archivbestand.leer.mitJahr(planung: p1, lernende: bestand(p1), jetzt: Self.stempel)
            .mitJahr(planung: p2, lernende: nil, jetzt: Self.stempel)
        return try #require(JSONSerialization.jsonObject(with: try Archivdatei.schreiben(archiv)) as? [String: Any])
    }

    private func jahrAendern(_ objekt: inout [String: Any], _ stelle: Int,
                             _ aendern: (inout [String: Any]) -> Void) throws {
        var jahre = try #require(objekt["jahre"] as? [[String: Any]])
        aendern(&jahre[stelle])
        objekt["jahre"] = jahre
    }

    private func lesen(_ objekt: [String: Any]) throws -> (bestand: Archivbestand, bilanz: Archivdatei.Bilanz) {
        try Archivdatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: objekt))
    }

    @Test("Archiv-Leser: unlesbares Jahr übergangen, bereinigtes gezählt, Kennung ersetzt — die anderen Jahre bleiben")
    func leser() throws {
        var kaputt = try archivObjekt()
        try jahrAendern(&kaputt, 1) { $0["planung"] = "keine Planung" }
        let (a, bilanzA) = try lesen(kaputt)
        #expect(a.jahre.count == 1 && bilanzA.verworfeneJahre == 1 && bilanzA.verlust)

        var bereinigt = try archivObjekt()
        try jahrAendern(&bereinigt, 0) {
            var l = $0["lernende"] as? [String: Any] ?? [:]
            var g = l["lerngruppen"] as? [[String: Any]] ?? []
            g[0]["mitglieder"] = ["l-1", "l-9"]
            l["lerngruppen"] = g
            $0["lernende"] = l
            $0["schuljahr"] = "irgendwann"
        }
        let ersteKennung = (bereinigt["jahre"] as? [[String: Any]])?[0]["id"] as? String ?? ""
        try jahrAendern(&bereinigt, 1) { $0["id"] = ersteKennung }
        let (b, bilanzB) = try lesen(bereinigt)
        #expect(b.jahre.count == 2 && bilanzB.bereinigteJahre == 1 && bilanzB.ersetzteKennungen == 1)
        #expect(b.jahre[0].schuljahr == "2026/27", "aus der Jahresdatei wiederhergestellt")
        #expect(b.jahre[0].lernende?.lerngruppen[0].mitglieder == ["l-1"])

        var leer = try archivObjekt()
        try jahrAendern(&leer, 0) { $0["lernende"] = 42 }
        #expect(try lesen(leer).bilanz.verworfeneJahre == 1, "Lernende, die kein Objekt sind, verwerfen das Jahr")
    }

    @Test("Archiv-Leser: neuere Fassung — des Archivs, einer Planung oder einer Jahresdatei — sperrt das Ganze")
    func neuereFassung() throws {
        var archiv = try archivObjekt()
        archiv["version"] = 2
        var planungNeu = try archivObjekt()
        try jahrAendern(&planungNeu, 1) {
            var p = $0["planung"] as? [String: Any] ?? [:]
            p["version"] = Kennwerte.dateiVersion + 1
            $0["planung"] = p
        }
        var lernendeNeu = try archivObjekt()
        try jahrAendern(&lernendeNeu, 0) {
            var l = $0["lernende"] as? [String: Any] ?? [:]
            l["version"] = 2
            $0["lernende"] = l
        }
        for (name, objekt) in [("Archiv", archiv), ("Planung", planungNeu), ("Jahresdatei", lernendeNeu)] {
            do {
                _ = try lesen(objekt)
                Issue.record("\(name): eine neuere Fassung muss das Archiv sperren")
            } catch let fehler as Archivdatei.Fehler {
                #expect(fehler.art == .neuereFassung && fehler.text.contains("aktualisieren"), "\(name)")
            }
        }
        for kaputt in ["", "[]", "{}", "{\"typ\":\"unterrichtsplanung-archiv\",\"version\":true}",
                       "{\"typ\":\"unterrichtsplanung-archiv\",\"version\":1,\"jahre\":{}}"] {
            #expect(throws: Archivdatei.Fehler.self, "\(kaputt)") { try Archivdatei.lesen(Data(kaputt.utf8)) }
        }
        do {
            _ = try Archivdatei.lesen(Data(count: Archivdatei.hoechstgroesse + 1))
            Issue.record("ein Archiv über der Grenze muss abgewiesen werden, bevor es gelesen wird")
        } catch let fehler as Archivdatei.Fehler {
            #expect(fehler.art == .beschaedigt && fehler.text.contains("128 MB"))
        }
    }

    @Test("Grenze der Jahre: an der Grenze behalten, eins darüber gekappt und gezählt; Werte des Vertrags")
    func grenzen() throws {
        #expect(Archivdatei.hoechstgroesse == 128 * 1024 * 1024 && Archivdatei.hinweisgroesse == 64 * 1024 * 1024)
        let p = try planung()
        for (anzahl, verworfen) in [(Archivdatei.maxJahre, 0), (Archivdatei.maxJahre + 1, 1)] {
            var archiv = Archivbestand.leer
            for _ in 0..<anzahl { archiv = archiv.mitJahr(planung: p, lernende: nil, jetzt: Self.stempel) }
            let (gelesen, bilanz) = try Archivdatei.lesenMitBilanz(try Archivdatei.schreiben(archiv))
            #expect(gelesen.jahre.count == min(anzahl, Archivdatei.maxJahre) && bilanz.verworfeneJahre == verworfen)
        }
    }
}
