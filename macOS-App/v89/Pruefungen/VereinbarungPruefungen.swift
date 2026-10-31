// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Vereinbarungen (v86, AX3, Nachfassen R2-A1: E741, E743, E745, E746, E750, E751, E804–E815) ──
// Eine Vereinbarung wird gehandhabt wie eine Maßnahme (E741) — eine neue Art in `anliegen` (E750), ihr Stand je Person
// „gültig“ oder „ungültig“, getrennt von den drei Ständen der übrigen Anliegen (E746). Das Datum ist der letzte gültige Tag:
// Sie gilt bis einschließlich dieses Tages, ab dem Folgetag ist sie abgeleitet „ungültig“ — ohne Zeitgeber, nichts still
// geschrieben (E743, E806). Von Hand wieder „gültig“ hebt die Gültigkeit bis einschließlich für alle auf, der Hinweis nennt,
// für wen sie wieder gilt (E751, E815). Eine Vereinbarung ist kein offenes Anliegen (E804). Reine Funktionen am Bestand.

@Suite("Vereinbarungen: Stand, Gültigkeit, keine offenen Anliegen, Datei, Löschen, Wechsel")
@MainActor
struct VereinbarungPruefungen {

    private static let s = "2026-10-03T08:00:00.000Z"

    private func tag(_ iso: String) throws -> Tag { try #require(Tag(iso: iso)) }

    private static func person(_ id: String, _ vorname: String, _ nachname: String) -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: s, geaendert: s, archiviert: "")
    }

    /// „6a“ mit Anna Abel, Ben Abel, Cem Çelik und Dora Dietz; die Vereinbarung „Handyregel“ für Ben und Cem, gültig bis
    /// einschließlich 31.10.2026, dazu die Maßnahme „Heft nachreichen“ für Ben.
    private static func bestand() -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [person("l-1", "Anna", "Abel"), person("l-2", "Ben", "Abel"), person("l-3", "Cem", "Çelik"),
                      person("l-4", "Dora", "Dietz")]
        b.lerngruppen = [Lerngruppe(id: "g-6a", name: "6a", art: .klasse, mitglieder: ["l-1", "l-2", "l-3", "l-4"], zeilen: [],
                                    skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        b.anliegen = [
            Anliegen(id: "v-1", art: .vereinbarung, titel: "Handyregel", lerngruppe: "g-6a", betroffene: ["l-2", "l-3"],
                     datum: "2026-10-01", frist: "2026-10-31", notiz: "Das Handy bleibt in der Tasche.", angelegt: s,
                     geaendert: s),
            Anliegen(id: "m-1", art: .massnahme, titel: "Heft nachreichen", lerngruppe: "g-6a", betroffene: ["l-2"],
                     datum: "2026-10-01", frist: "2026-10-16", notiz: "", angelegt: s, geaendert: s),
        ]
        return b
    }

    private func vereinbarung(_ b: Lernendenbestand) throws -> Anliegen {
        try #require(b.anliegen.first { $0.id == "v-1" })
    }

    @Test("E746: die Art „Vereinbarung“ und ihr Stand „gültig“/„ungültig“ — eine eigene Kategorie")
    func artUndStand() {
        #expect(Anliegenart.vereinbarung.titel == "Vereinbarung")
        #expect(Gueltigkeit.gueltig.beschriftung == "gültig" && Gueltigkeit.ungueltig.beschriftung == "ungültig")
        #expect(Gueltigkeit.allCases == [.gueltig, .ungueltig])
    }

    @Test("E743, E806: gültig bis einschließlich des Datums, ab dem Folgetag abgeleitet „ungültig“ — für alle; von Hand „ungültig“ je Person; nichts geschrieben")
    func abgeleitet() throws {
        let b = Self.bestand()
        let v = try vereinbarung(b)
        #expect(Lernendenbestand.gueltigkeit(v, "l-2", heute: try tag("2026-10-30")) == .gueltig)
        #expect(Lernendenbestand.gueltigkeit(v, "l-2", heute: try tag("2026-10-31")) == .gueltig, "am letzten gültigen Tag (E806)")
        #expect(Lernendenbestand.gueltigkeit(v, "l-2", heute: try tag("2026-11-01")) == .ungueltig, "ab dem Folgetag")
        #expect(Lernendenbestand.gueltigkeit(v, "l-3", heute: try tag("2026-11-05")) == .ungueltig, "auch für Cem")
        var ohneDatum = v
        ohneDatum.frist = ""
        #expect(Lernendenbestand.gueltigkeit(ohneDatum, "l-2", heute: try tag("2027-07-01")) == .gueltig, "ohne Datum gilt sie")
        let (vonHand, hinweis) = b.mitGueltigkeit("v-1", "l-2", .ungueltig, heute: try tag("2026-10-20"), jetzt: Self.s)
        let neu = try vereinbarung(vonHand)
        #expect(neu.ungueltig == ["l-2"] && hinweis == nil, "von Hand ungültig für Ben")
        let t20 = try tag("2026-10-20")
        #expect(Lernendenbestand.gueltigkeit(neu, "l-2", heute: t20) == .ungueltig
                && Lernendenbestand.gueltigkeit(neu, "l-3", heute: t20) == .gueltig, "Cem bleibt gültig")
        // Die Verzeichnisse leiten ab, sie schreiben nichts (E743): Der Bestand bleibt derselbe.
        let verzeichnis = Lernendenverzeichnis(b, heute: try tag("2026-11-05"))
        #expect(verzeichnis.gueltigkeit(v, "l-2") == .ungueltig)
        let unveraendert = try vereinbarung(b)
        #expect(unveraendert.frist == "2026-10-31" && unveraendert.ungueltig.isEmpty)
    }

    @Test("E751, E815: von Hand wieder „gültig“ nach dem Ablauf hebt die Gültigkeit bis einschließlich für alle auf — der Hinweis nennt, für wen sie wieder gilt")
    func wiederGueltig() throws {
        let nach = try tag("2026-11-05")
        let (zwei, hinweisZwei) = Self.bestand().mitGueltigkeit("v-1", "l-2", .gueltig, heute: nach, jetzt: Self.s)
        #expect(try vereinbarung(zwei).frist.isEmpty, "das Datum ist entfernt")
        #expect(hinweisZwei == "Die Gültigkeit bis einschließlich 31.10.2026 ist aufgehoben — „Handyregel“ gilt wieder für "
                + "Ben Abel und Cem Çelik.")
        // Cem von Hand ungültig: Der Hinweis nennt nur Ben.
        var mitCem = Self.bestand()
        mitCem.anliegen[0].ungueltig = ["l-3"]
        let (eins, hinweisEins) = mitCem.mitGueltigkeit("v-1", "l-2", .gueltig, heute: nach, jetzt: Self.s)
        #expect(hinweisEins == "Die Gültigkeit bis einschließlich 31.10.2026 ist aufgehoben — „Handyregel“ gilt wieder für "
                + "Ben Abel.")
        #expect(try vereinbarung(eins).ungueltig == ["l-3"], "Cem bleibt von Hand ungültig")
        var drei = Self.bestand()
        drei.anliegen[0].betroffene = ["l-2", "l-3", "l-4"]
        #expect(drei.mitGueltigkeit("v-1", "l-2", .gueltig, heute: nach, jetzt: Self.s).hinweis
                == "Die Gültigkeit bis einschließlich 31.10.2026 ist aufgehoben — „Handyregel“ gilt wieder für 3 Personen.")
        // Vor dem Ablauf — auch am letzten gültigen Tag (E806): wieder gültig ohne Hinweis, das Datum bleibt.
        var vorher = Self.bestand()
        vorher.anliegen[0].ungueltig = ["l-2"]
        for heute in ["2026-10-20", "2026-10-31"] {
            let (frueh, ohneHinweis) = vorher.mitGueltigkeit("v-1", "l-2", .gueltig, heute: try tag(heute), jetzt: Self.s)
            let fruehV = try vereinbarung(frueh)
            #expect(fruehV.frist == "2026-10-31" && fruehV.ungueltig.isEmpty && ohneHinweis == nil, "\(heute)")
        }
        // Nichts zu ändern, nicht betroffen, keine Vereinbarung: derselbe Bestand.
        let b = Self.bestand()
        #expect(b.mitGueltigkeit("v-1", "l-2", .gueltig, heute: try tag("2026-10-20"), jetzt: Self.s).bestand == b)
        #expect(b.mitGueltigkeit("v-1", "l-1", .ungueltig, heute: try tag("2026-10-20"), jetzt: Self.s).bestand == b)
        #expect(b.mitGueltigkeit("m-1", "l-2", .ungueltig, heute: try tag("2026-10-20"), jetzt: Self.s).bestand == b)
    }

    @Test("E813: „ungültig“ von Hand an einer schon abgelaufenen wird eingetragen — ein Schritt; die Person bleibt auch nach einer Verlängerung ungültig")
    func ungueltigNachDemAblauf() throws {
        let b = Self.bestand()
        let nach = try tag("2026-11-05")
        let (eingetragen, hinweis) = b.mitGueltigkeit("v-1", "l-2", .ungueltig, heute: nach, jetzt: Self.s)
        #expect(eingetragen != b && hinweis == nil, "ein Schritt, ohne Hinweis")
        #expect(try vereinbarung(eingetragen).ungueltig == ["l-2"])
        // Verlängert bis einschließlich 31.12.2026: Ben bleibt ungültig, Cem gilt wieder.
        let v = try vereinbarung(eingetragen)
        let verlaengert = eingetragen.mitAnliegen("v-1", titel: v.titel, datum: v.datum, frist: "2026-12-31", notiz: v.notiz,
                                                  jetzt: Self.s)
        let lang = try vereinbarung(verlaengert)
        #expect(Lernendenbestand.gueltigkeit(lang, "l-2", heute: nach) == .ungueltig
                && Lernendenbestand.gueltigkeit(lang, "l-3", heute: nach) == .gueltig)
    }

    @Test("E804: Eine Vereinbarung ist kein offenes Anliegen — weder in der Zahl noch in „Offen: …“ noch im Filter; ein altes Feld „offenesAnliegen“ wirkt nicht und wird nicht geschrieben")
    func keinOffenesAnliegen() throws {
        let (b, id) = try #require(Self.bestand().mitNeuemAnliegen(.vereinbarung, titel: "Pünktlichkeit", lerngruppe: "",
                                                                    betroffene: ["l-1"], datum: "2026-10-03", frist: "",
                                                                    jetzt: Self.s))
        let heute = try tag("2026-10-20")
        let neu = try #require(b.anliegen.first { $0.id == id })
        #expect(!Lernendenverzeichnis.offen(neu, .offen), "gültig, ohne Rücklauf — trotzdem nicht offen")
        let verzeichnis = Lernendenverzeichnis(b, heute: heute)
        #expect(verzeichnis.offeneZahl(von: "l-1") == 0 && verzeichnis.offeneAnliegen(von: "l-1").isEmpty)
        #expect(verzeichnis.offeneZahl(von: "l-2") == 1, "Bens Maßnahme zählt")
        #expect(verzeichnis.offeneZahl(von: "l-3") == 0, "Cem hat nur die Vereinbarung")
        let gefiltert = Lernendenblatt.uebersicht(verzeichnis, suche: "", archivierte: false, nurOffen: true,
                                                  ordnung: Personenzeile.vorgabe).map(\.id)
        #expect(gefiltert == ["l-2"], "„Nur mit offenen Anliegen“ zeigt nur Ben")
        // Ein Feld aus der Entwicklung von AX3 (vor E804) wirkt nicht und geht beim Schreiben nicht mit — übergangen wie
        // jeder unbekannte Schlüssel, ohne Eintrag in der Bilanz (E750, Z-R2A1-05).
        var objekt = Lernendendatei.alsObjekt(b)
        var anliegen = try #require(objekt["anliegen"] as? [[String: Any]])
        let stelle = try #require(anliegen.firstIndex { $0["id"] as? String == id })
        anliegen[stelle]["offenesAnliegen"] = true
        objekt["anliegen"] = anliegen
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: objekt))
        #expect(bilanz.istLeer, "\(bilanz.beschreibung)")
        #expect(Lernendenverzeichnis(gelesen, heute: heute).offeneZahl(von: "l-1") == 0)
        let wieder = try #require(Lernendendatei.alsObjekt(gelesen)["anliegen"] as? [[String: Any]])
        #expect(wieder.allSatisfy { $0["offenesAnliegen"] == nil })
    }

    @Test("E750, E805: in der Datei die Art „vereinbarung“, das Datum in „frist“, die Gültigkeit in „ungueltig“ — nur, wo gesetzt")
    func datei() throws {
        var b = Self.bestand()
        b.anliegen[0].ungueltig = ["l-3"]
        let daten = try Lernendendatei.schreiben(b)
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(daten)
        #expect(gelesen == b && bilanz.istLeer, "\(bilanz.beschreibung)")
        #expect(try Lernendendatei.schreiben(gelesen) == daten, "kanonisch")
        let objekt = Lernendendatei.alsObjekt(b)
        let anliegen = try #require(objekt["anliegen"] as? [[String: Any]])
        #expect(anliegen[0]["art"] as? String == "vereinbarung" && anliegen[0]["frist"] as? String == "2026-10-31")
        #expect(anliegen[0]["ungueltig"] as? [String] == ["l-3"])
        // Ohne gesetzte Gültigkeit schreibt eine Vereinbarung das Feld nicht; die übrigen Anliegen tragen nur die Schlüssel
        // von bisher.
        let alt: Set<String> = ["id", "art", "titel", "lerngruppe", "betroffene", "datum", "frist", "notiz", "angelegt", "geaendert"]
        let ohne = try #require(Lernendendatei.alsObjekt(Self.bestand())["anliegen"] as? [[String: Any]])
        #expect(Set(ohne[0].keys) == alt && Set(ohne[1].keys) == alt)
        #expect(Set(anliegen[0].keys) == alt.union(["ungueltig"]), "kein weiteres Feld (E804)")
    }

    @Test("E750: Der Leser bereinigt — Gültigkeit nur für Betroffene und nur als Liste, nur an einer Vereinbarung, keine Rückläufe zu ihr")
    func leser() throws {
        var objekt = Lernendendatei.alsObjekt(Self.bestand())
        var anliegen = try #require(objekt["anliegen"] as? [[String: Any]])
        anliegen[0]["ungueltig"] = ["l-3", "l-1", "l-9"]
        anliegen[1]["ungueltig"] = ["l-2"]
        objekt["anliegen"] = anliegen
        objekt["rueckmeldungen"] = [["anliegen": "v-1", "lernender": "l-2", "stand": "erledigt", "datum": "", "notiz": "",
                                     "geaendert": Self.s]]
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: objekt))
        #expect(gelesen.anliegen[0].ungueltig == ["l-3"], "nur Cem ist betroffen")
        #expect(gelesen.anliegen[1].ungueltig.isEmpty, "an einer Maßnahme nicht")
        #expect(gelesen.rueckmeldungen.isEmpty, "eine Vereinbarung hat keinen Rücklauf")
        #expect(bilanz.verworfeneBetroffene == 2 && bilanz.verworfeneFelder == 1 && bilanz.verworfeneRueckmeldungen == 1,
                "\(bilanz.beschreibung)")
        // In falscher Form (Z-AX3-02 d): eine Zeichenkette statt einer Liste — übergangen und gezählt.
        var falsch = Lernendendatei.alsObjekt(Self.bestand())
        var liste = try #require(falsch["anliegen"] as? [[String: Any]])
        liste[0]["ungueltig"] = "l-3"
        falsch["anliegen"] = liste
        let (form, bilanzForm) = try Lernendendatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: falsch))
        #expect(form.anliegen[0].ungueltig.isEmpty && bilanzForm.verworfeneBetroffene == 1, "\(bilanzForm.beschreibung)")
    }

    @Test("E811: Löschen — „Mit ihr gehen die Stände von 2 Personen.“; mit einer Person geht ihre Vereinbarung und wird gezählt, ihr Stand geht mit")
    func loeschen() throws {
        #expect(Planungsspeicher.vereinbarungStaende(2) == "Mit ihr gehen die Stände von 2 Personen.")
        #expect(Planungsspeicher.vereinbarungStaende(1) == "Mit ihr geht der Stand von 1 Person.")
        let (art, mit) = Planungsspeicher.benennung(.vereinbarung)
        #expect(art == "Die Vereinbarung" && mit == "Mit ihr")
        #expect(Planungsspeicher.massnahmenUndTermine(.init(anliegen: 4, termine: 2, vereinbarungen: 1))
                == "1 Maßnahme, 1 Vereinbarung, 2 Termine")
        #expect(Planungsspeicher.massnahmenUndTermine(.init(anliegen: 3, termine: 2)) == "1 Maßnahme, 2 Termine",
                "ohne Vereinbarung wie bisher")
        var b = Self.bestand()
        b.anliegen[0].ungueltig = ["l-3"]
        // Ben ohne Cem: Die Vereinbarung bleibt für Cem, Bens Maßnahme geht.
        let (ohneBen, zahl) = b.ohnePerson("l-2")
        #expect(zahl.anliegen == 1 && zahl.vereinbarungen == 0)
        let ohneBenV = try vereinbarung(ohneBen)
        #expect(ohneBenV.betroffene == ["l-3"] && ohneBenV.ungueltig == ["l-3"])
        let (ohneBeide, zahlCem) = ohneBen.ohnePerson("l-3")
        #expect(zahlCem.anliegen == 1 && zahlCem.vereinbarungen == 1 && !ohneBeide.anliegen.contains { $0.id == "v-1" })
        // Cem endgültig gelöscht, Ben bleibt: Cems Stand geht mit (Z-AX3-02 a).
        let (ohneCem, _) = b.ohnePerson("l-3")
        let ohneCemV = try vereinbarung(ohneCem)
        #expect(ohneCemV.betroffene == ["l-2"] && ohneCemV.ungueltig.isEmpty)
        // Herausnehmen nimmt den Stand mit.
        let heraus = try vereinbarung(b.mitBetroffenem("v-1", "l-3", false, jetzt: Self.s))
        #expect(heraus.betroffene == ["l-2"] && heraus.ungueltig.isEmpty)
    }

    @Test("Z-AX3-02 c: Im Archiv zählt das Löschen einer Person über alle Schuljahre auch ihre Vereinbarungen")
    func loeschzahlImArchiv() throws {
        var jahr = Self.bestand()
        jahr.anliegen[0].betroffene = ["l-2"]
        let planung = Planung.leer(titel: "Schuljahr", start: try tag("2025-08-04"), wochen: 4, basis: "", klassen: [],
                                   fachfarben: [:])
        let archiv = Archivbestand.leer.mitJahr(planung: planung, lernende: jahr, jetzt: Self.s)
            .mitJahr(planung: planung, lernende: jahr, jetzt: Self.s)
        let zahl = archiv.ohnePerson("l-2", jetzt: Self.s).zahl
        #expect(zahl.vereinbarungen == 2 && zahl.anliegen == 4, "je Jahr die Vereinbarung und die Maßnahme")
    }

    @Test("Z-AX3-13: Eine Vereinbarung nimmt keinen Rücklauf an")
    func keinRuecklauf() {
        let b = Self.bestand()
        #expect(b.mitRuecklauf("v-1", "l-2", stand: .erledigt, datum: "2026-10-20", notiz: "", jetzt: Self.s) == b)
        #expect(b.mitRuecklauf("m-1", "l-2", stand: .erledigt, datum: "2026-10-20", notiz: "", jetzt: Self.s) != b,
                "eine Maßnahme schon")
    }

    @Test("E807, E808, E810, E812, E819 und die Tabellen 7–9: die Wortlaute; die Schritte")
    func wortlaute() throws {
        #expect(Gruppenteil.allCases.map(\.titel) == ["Mitglieder", "Mitteilungen", "Maßnahmen", "Vereinbarungen"])
        #expect(Vereinbarungstext.neue == "Neue Vereinbarung" && Vereinbarungstext.gueltigBis == "gültig bis einschließlich")
        #expect(Vereinbarungstext.anlegenHilfe == "Eine Vereinbarung für die gewählte Person anlegen (⏎)")
        #expect(Vereinbarungstext.leer == "Noch keine Vereinbarung für Mitglieder dieser Lerngruppe. Eine Vereinbarung "
                + "betrifft eine oder wenige Personen und gilt, bis sie abläuft oder ungültig gesetzt wird; ihr Stand ist gültig "
                + "oder ungültig.")
        #expect(Vereinbarungstext.spalteVereinbarung == "Vereinbarung" && Vereinbarungstext.spalteGueltigBis == "Gültig bis")
        #expect(Vereinbarungstext.inhalt == "Inhalt der Vereinbarung")
        #expect(Vereinbarungstext.auchFuerHilfe == "Die Vereinbarung gilt auch für eine weitere Person dieser Lerngruppe")
        #expect(Vereinbarungstext.loeschenHilfe == "Die Vereinbarung samt ihren Ständen löschen — mit Rückfrage")
        #expect(Vereinbarungstext.abgelaufenHilfe(try tag("2026-10-31")) == "Abgelaufen — gültig bis einschließlich 31.10.2026")
        #expect(Vereinbarungstext.knopf == "Vereinbarung …"
                && Vereinbarungstext.knopfHilfe == "Eine Vereinbarung für diese Person, ohne Lerngruppe")
        #expect(Vereinbarungstext.titelAendern == "Vereinbarung ändern" && Vereinbarungstext.platzhalter == "etwa Handyregel")
        #expect(Vereinbarungstext.gueltigBisBogen == "Gültig bis einschließlich")
        #expect(Vereinbarungstext.fuss == "Ohne Datum gilt die Vereinbarung, bis sie ungültig gesetzt wird; mit Datum gilt sie "
                + "bis einschließlich dieses Tages. Der Stand: gültig oder ungültig.")
        #expect(Vereinbarungstext.datumNeuBezeichnung == "Gültig bis einschließlich — neue Vereinbarung"
                && Vereinbarungstext.datumBezeichnung == "Gültig bis einschließlich")
        #expect(Vereinbarungstext.aendernHilfe == "Titel, Gültigkeit und Inhalt ändern")
        #expect(Vereinbarungstext.ohneLerngruppeLeer == "Keine Maßnahme, keine Vereinbarung und kein Termin ohne Lerngruppe.")
        #expect(Vereinbarungstext.filterHilfe == "Nur Personen mit offenen Mitteilungen, Maßnahmen oder Terminen zeigen")
        #expect(Lernendendatei.grenzmeldung == "Höchstens \(Lernendendatei.maxAnliegen) Anliegen je Schuljahr.")
        #expect(Lernendendatei.vollmeldung == "Die Lernendenverwaltung trägt schon \(Lernendendatei.maxAnliegen) Anliegen.")
        let v = try vereinbarung(Self.bestand())
        var ohneDatum = v
        ohneDatum.frist = ""
        #expect(Personenanliegen.tagtext(v) == "gültig bis einschließlich 31.10.2026" && Personenanliegen.tagtext(ohneDatum) == "—")
        #expect(Vereinbarungstext.standtext(gueltig: 1, ungueltig: 1) == "1 gültig · 1 ungültig")
        #expect(Vereinbarungstext.standtext(gueltig: 2, ungueltig: 0) == "2 gültig")
        #expect([Schrittname.vereinbarungAnlegen, Schrittname.vereinbarungAendern, Schrittname.vereinbarungLoeschen,
                 Schrittname.gueltigkeitAendern] == ["Vereinbarung anlegen", "Vereinbarung ändern", "Vereinbarung löschen",
                                                    "Gültigkeit ändern"])
    }

    @Test("Z-AX3-10: Das Menü des Stands unter „Ohne Lerngruppe“ trägt beide Stände, das Häkchen am geltenden")
    func standmenue() {
        let ungueltig = Standwahl.eintraege(.ungueltig)
        let titel = ungueltig.map(\.titel)
        let haken = ungueltig.map(\.haken)
        #expect(titel == ["gültig", "ungültig"] && haken == [false, true])
        let hakenGueltig = Standwahl.eintraege(.gueltig).map(\.haken)
        #expect(hakenGueltig == [true, false])
    }

    @Test("Z-R2A1-03, E808: Am Stand einer abgelaufenen die Hilfe „Abgelaufen — gültig bis einschließlich 31.10.2026“ — im Teil der Lerngruppe wie unter „Ohne Lerngruppe“; sonst dort „Stand ändern“")
    func standHilfe() throws {
        let v = try vereinbarung(Self.bestand())
        let nach = try tag("2026-11-01")
        let abgelaufen = "Abgelaufen — gültig bis einschließlich 31.10.2026"
        #expect(Vereinbarungstext.standHilfe(v, "l-2", heute: nach) == abgelaufen)
        #expect(Vereinbarungstext.standHilfe(v, "l-2", heute: try tag("2026-10-31")) == nil, "am letzten gültigen Tag gilt sie")
        var vonHand = v
        vonHand.ungueltig = ["l-2"]
        #expect(Vereinbarungstext.standHilfe(vonHand, "l-2", heute: nach) == nil, "von Hand ungültig — keine Hilfe zum Ablauf")
        #expect(Vereinbarungstext.standHilfe(vonHand, "l-3", heute: nach) == abgelaufen, "für Cem abgelaufen")
        #expect(Vereinbarungstext.standmenueHilfe(v, "l-2", heute: nach) == abgelaufen, "unter „Ohne Lerngruppe“")
        #expect(Vereinbarungstext.standmenueHilfe(v, "l-2", heute: try tag("2026-10-20")) == "Stand ändern")
    }

    @Test("Z-R2A1-03, E807: Im Archiv zeigt die Spalte „Tag“ einer Vereinbarung „gültig bis einschließlich 31.10.2026“, ohne Datum „—“; geordnet wird weiter nach dem ISO-Tag")
    func archivTag() {
        var b = Self.bestand()
        b.anliegen.append(Anliegen(id: "v-2", art: .vereinbarung, titel: "Pünktlichkeit", lerngruppe: "g-6a", betroffene: ["l-1"],
                                   datum: "2026-10-01", frist: "", notiz: "", angelegt: Self.s, geaendert: Self.s))
        let zeilen = ArchivAnsicht.anliegenzeilen(b, Lernendenverzeichnis(b))
        let texte = zeilen.map(\.tagtext)
        #expect(texte == ["gültig bis einschließlich 31.10.2026", "16.10.2026", "—"], "die Maßnahme mit dem Tag ihrer Frist")
        let tage = zeilen.map(\.tag)
        #expect(tage == ["2026-10-31", "2026-10-16", ""], "die Ordnung nach dem ISO-Tag wie bisher")
    }

    @Test("E271, E763, E764, E806: Beim Wechsel folgt die geltende Vereinbarung der Person — wie eine Maßnahme; ungültige und abgelaufene bleiben im Archiv")
    func wechsel() throws {
        var b = Self.bestand()
        b.lerngruppen.append(Lerngruppe(id: "g-mf", name: "Mathe-Förder", art: .kurs, mitglieder: ["l-1"], zeilen: [],
                                        skalen: [:], halbjahreswechsel: "", geaendert: Self.s, archiviert: ""))
        b.anliegen[0].frist = ""
        b.anliegen[0].ungueltig = ["l-3"]
        b.anliegen.append(Anliegen(id: "v-2", art: .vereinbarung, titel: "Förderheft", lerngruppe: "g-mf", betroffene: ["l-1"],
                                   datum: "2026-10-01", frist: "", notiz: "", angelegt: Self.s, geaendert: Self.s))
        // Weit hinter der Wanduhr (Z-AX3-04): Der Wechsel leitet am Tag des Wechsels ab, nicht an heute.
        b.anliegen.append(Anliegen(id: "v-3", art: .vereinbarung, titel: "Abgelaufen", lerngruppe: "g-6a", betroffene: ["l-1"],
                                   datum: "2026-10-01", frist: "2099-06-01", notiz: "", angelegt: Self.s, geaendert: Self.s))
        b.anliegen.append(Anliegen(id: "v-4", art: .vereinbarung, titel: "Bis zum Wechsel", lerngruppe: "g-6a",
                                   betroffene: ["l-1"], datum: "2026-10-01", frist: "2099-07-20", notiz: "", angelegt: Self.s,
                                   geaendert: Self.s))
        let neu = b.neuesJahr(gruppen: ["g-6a", "g-mf"], zuordnung: [:], planung: "p-2", schuljahr: "2099/00",
                              termine: .abDemNeuenSchuljahr,
                              jetzt: "2099-07-20T08:00:00.000Z", ohneMitglieder: ["g-mf"])
        let v1 = try #require(neu.anliegen.first { $0.id == "v-1" })
        #expect(v1.betroffene == ["l-2"] && v1.ungueltig.isEmpty && v1.lerngruppe == "g-6a",
                "nur Ben, für den sie gilt; Cem (ungültig) bleibt im Archiv")
        let v2 = try #require(neu.anliegen.first { $0.id == "v-2" })
        #expect(v2.lerngruppe.isEmpty, "aus „Mathe-Förder“ ohne Mitglieder: mit Anna, ohne Lerngruppe (E764)")
        #expect(!neu.anliegen.contains { $0.id == "v-3" }, "abgelaufen — bleibt im Archiv")
        #expect(neu.anliegen.contains { $0.id == "v-4" }, "am Tag des Wechsels noch gültig (E806) — kommt mit")
    }
}
