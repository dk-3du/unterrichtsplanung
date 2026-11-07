// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Mitteilungen: Auswahlfeld und Tabelle wie bei den Maßnahmen (v91, BC2: V1–V3, V7, V10) ──
// Eine Mitteilung je Ansicht statt einer Spalte je Mitteilung: Das Auswahlfeld über der Tabelle wählt, was die Tabelle zeigt
// und „Löschen …“ betrifft (V1); die Tabelle zeigt genau die Betroffenen unter den Mitgliedern (V2), Spalten Person ·
// Mitteilung · Frist · Stand (V3); beim Erscheinen die jüngste (V7). Wer nicht betroffen ist, kommt über „Auch an …“ dazu —
// von Hand, nie von selbst. Reine Funktionen und der Aufbau der Ansicht am Quelltext; den Weg über das Blatt prüft die
// Lernendenprobe (AP8, Sammelleiste).

@Suite("Mitteilungen: Auswahlfeld und Tabelle der gewählten Mitteilung (BC2)")
struct MitteilungstabellePruefungen {

    private static let s = "2026-08-20T08:00:00.000Z"
    private static let anna = "l-anna", ben = "l-ben", clara = "l-clara", david = "l-david", emil = "l-emil"

    private static func person(_ id: String, _ vorname: String, _ nachname: String, archiviert: String = "") -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: s, geaendert: s, archiviert: archiviert)
    }

    /// Das Beispiel aus E929: die 5a; „Wandertag · 01.09.2026“ betrifft Anna, Ben, Clara und David — David ist archiviert,
    /// Emil kam später und ist nicht betroffen; Anna hat „erledigt“. Dazu „Fotos“ an Anna und Clara, „Elternabend“ an alle
    /// fünf und die Maßnahme „Nacharbeit“ für Ben.
    private static func bestand() -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [person(anna, "Anna", "Adam"), person(ben, "Ben", "Brandt"), person(clara, "Clara", "Conrad"),
                      person(david, "David", "Dorn", archiviert: s), person(emil, "Emil", "Eck")]
        b.lerngruppen = [Lerngruppe(id: "g-5a", name: "5a", art: .klasse, mitglieder: [anna, ben, clara, david, emil],
                                    zeilen: [], skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        func mitteilung(_ id: String, _ titel: String, _ betroffene: [String], _ datum: String) -> Anliegen {
            Anliegen(id: id, art: .mitteilung, titel: titel, lerngruppe: "g-5a", betroffene: betroffene, datum: datum,
                     frist: "", notiz: "", angelegt: s, geaendert: s)
        }
        b.anliegen = [
            mitteilung("m-w", "Wandertag", [anna, ben, clara, david], "2026-09-01"),
            mitteilung("m-f", "Fotos", [anna, clara], "2026-09-03"),
            Anliegen(id: "m-n", art: .massnahme, titel: "Nacharbeit", lerngruppe: "g-5a", betroffene: [ben],
                     datum: "2026-10-01", frist: "2026-10-08", notiz: "", angelegt: s, geaendert: s),
            mitteilung("m-e", "Elternabend", [anna, ben, clara, david, emil], ""),
        ]
        b.rueckmeldungen = [Rueckmeldung(anliegen: "m-w", lernender: anna, stand: .erledigt, datum: "2026-09-03", notiz: "",
                                         geaendert: s)]
        return b
    }

    private static func anliegen(_ b: Lernendenbestand, _ id: String) throws -> Anliegen {
        try #require(b.anliegen.first { $0.id == id })
    }

    // ── Die Zeilen (V2) ───────────────────────────────────────────────────

    @Test("V2: Die Tabelle zeigt genau die Betroffenen der gewählten Mitteilung unter den Mitgliedern — Emil nicht, David nur mit dem Schalter")
    func zeilenNurBetroffene() throws {
        let b = Self.bestand()
        let v = Lernendenverzeichnis(b)
        let wandertag = try Self.anliegen(b, "m-w")
        #expect(Ruecklaufliste.zeilen(wandertag, v.mitglieder("g-5a")).map(\.id) == [Self.anna, Self.ben, Self.clara],
                "aktiv und betroffen — Emil kam später")
        #expect(Ruecklaufliste.zeilen(wandertag, v.mitglieder("g-5a", archivierte: true)).map(\.id)
                == [Self.anna, Self.ben, Self.clara, Self.david], "„Archivierte zeigen“: auch David")
        let fotos = try Self.anliegen(b, "m-f")
        #expect(Ruecklaufliste.zeilen(fotos, v.mitglieder("g-5a")).map(\.id) == [Self.anna, Self.clara], "eine Teilmenge")
        let abend = try Self.anliegen(b, "m-e")
        #expect(Ruecklaufliste.zeilen(abend, v.mitglieder("g-5a")).map(\.id) == [Self.anna, Self.ben, Self.clara, Self.emil])
    }

    @Test("V2: Wer die Lerngruppe verließ, steht nicht in der Tabelle, zählt aber in „‹n› von ‹m› zurück“ — auch sein Rücklauf; V10: ohne Betroffene keine Zeile")
    func verlassenUndLeer() throws {
        let b = Self.bestand().ohneMitglied(Self.ben, ausGruppe: "g-5a")
        let v = Lernendenverzeichnis(b)
        let wandertag = try Self.anliegen(b, "m-w")
        #expect(Ruecklaufliste.zeilen(wandertag, v.mitglieder("g-5a")).map(\.id) == [Self.anna, Self.clara])
        #expect(Mitteilungstext.zurueck(wandertag, v) == "1 von 4 zurück", "Ben und David zählen mit, wie bisher")
        // Mit Bens Rücklauf zählt er auch im Zähler mit, nicht nur im Nenner (W1-09).
        var mitBen = Self.bestand()
        mitBen.rueckmeldungen.append(Rueckmeldung(anliegen: "m-w", lernender: Self.ben, stand: .abgelehnt, datum: "2026-09-04",
                                                  notiz: "", geaendert: Self.s))
        let ohneBen = mitBen.ohneMitglied(Self.ben, ausGruppe: "g-5a")
        #expect(Mitteilungstext.zurueck(try Self.anliegen(ohneBen, "m-w"), Lernendenverzeichnis(ohneBen)) == "2 von 4 zurück")
        // Verlassen beide Betroffene die Lerngruppe: keine Zeile, sie zählen weiter (W1-09).
        let fort = Self.bestand().ohneMitglied(Self.anna, ausGruppe: "g-5a").ohneMitglied(Self.clara, ausGruppe: "g-5a")
        let fotosFort = try Self.anliegen(fort, "m-f")
        #expect(Ruecklaufliste.zeilen(fotosFort, Lernendenverzeichnis(fort).mitglieder("g-5a")).isEmpty)
        #expect(Mitteilungstext.zurueck(fotosFort, Lernendenverzeichnis(fort)) == "0 von 2 zurück")
        // V10: Die einzige Betroffene ist gelöscht — die Mitteilung bleibt, ohne Zeile, „0 von 0 zurück“.
        let ohneFotos = Self.bestand().ohnePersonen([Self.anna, Self.clara]).bestand
        let fotos = try Self.anliegen(ohneFotos, "m-f")
        #expect(fotos.betroffene.isEmpty, "die Mitteilung bleibt stehen (V10)")
        #expect(Ruecklaufliste.zeilen(fotos, Lernendenverzeichnis(ohneFotos).mitglieder("g-5a")).isEmpty)
        #expect(Mitteilungstext.zurueck(fotos, Lernendenverzeichnis(ohneFotos)) == "0 von 0 zurück")
    }

    // ── Das Auswahlfeld (V1, V7) ──────────────────────────────────────────

    @Test("V7: Beim Erscheinen die vorgegebene Mitteilung der Gruppe, sonst die jüngste; ohne Mitteilung keine")
    func startwahl() {
        let v = Lernendenverzeichnis(Self.bestand())
        let mitteilungen = v.mitteilungen(der: "g-5a")
        #expect(mitteilungen.map(\.id) == ["m-w", "m-f", "m-e"], "in der Folge der Jahresdatei, ohne die Maßnahme")
        #expect(Ruecklaufliste.startwahl("m-f", mitteilungen) == "m-f")
        #expect(Ruecklaufliste.startwahl(nil, mitteilungen) == "m-e", "die jüngste")
        #expect(Ruecklaufliste.startwahl("m-n", mitteilungen) == "m-e", "eine Maßnahme ist keine Mitteilung der Gruppe")
        #expect(Ruecklaufliste.startwahl(nil, []) == nil)
    }

    @Test("E775: Das Auswahlfeld nennt „Titel · Tag“ mit Jahr, wie der Bogen „Rückmeldungsliste“; ohne Tag nur der Titel")
    func wahltitel() throws {
        let b = Self.bestand()
        let wandertag = try Self.anliegen(b, "m-w")
        let abend = try Self.anliegen(b, "m-e")
        #expect(Ruecklaufliste.wahltitel(wandertag) == "Wandertag · 01.09.2026")
        #expect(Ruecklaufliste.wahltitel(abend) == "Elternabend")
        #expect(Ruecklaufliste.standmenueTitel(wandertag) == "Stand für „Wandertag · 01.09.2026“",
                "die Sammelleiste nennt die Mitteilung wie das Auswahlfeld")
    }

    // ── „Auch an …“: von Hand, nie von selbst ─────────────────────────────

    @Test("„Auch an …“ bietet die angezeigten Nicht-Betroffenen an — Emil, der später kam; David nur mit dem Schalter (Z-BC2-06)")
    func aufzunehmen() throws {
        let b = Self.bestand()
        let v = Lernendenverzeichnis(b)
        let aktive = v.mitglieder("g-5a"), mitArchivierten = v.mitglieder("g-5a", archivierte: true)
        let wandertag = try Self.anliegen(b, "m-w"), fotos = try Self.anliegen(b, "m-f"), abend = try Self.anliegen(b, "m-e")
        #expect(Ruecklaufliste.aufzunehmen(wandertag, aktive).map(\.id) == [Self.emil])
        #expect(Ruecklaufliste.aufzunehmen(fotos, aktive).map(\.id) == [Self.ben, Self.emil], "ohne den Schalter")
        #expect(Ruecklaufliste.aufzunehmen(fotos, mitArchivierten).map(\.id) == [Self.ben, Self.david, Self.emil],
                "mit dem Schalter auch David, wie „Auch für …“")
        #expect(Ruecklaufliste.aufzunehmen(abend, mitArchivierten).isEmpty, "alle schon betroffen")
        // „Alle Mitglieder der Lerngruppe“: nur die aktiven, erst ab zweien (wie E853).
        #expect(Ruecklaufliste.alleAufzunehmen(Ruecklaufliste.aufzunehmen(fotos, mitArchivierten)) == [Self.ben, Self.emil])
        #expect(Ruecklaufliste.alleAufzunehmen(Ruecklaufliste.aufzunehmen(wandertag, mitArchivierten)).isEmpty,
                "einer allein: kein Sammeleintrag")
    }

    @Test("E999: Von mehreren Gewählten steht genau eine in der Tabelle — ihre Leiste steht; die gewählte Person geht vor")
    func leistenperson() {
        let zeilen = [Self.anna, Self.clara]
        #expect(Ruecklaufliste.leistenperson(nil, gewaehlt: [Self.anna, Self.ben, Self.emil], sichtbar: zeilen) == Self.anna)
        #expect(Ruecklaufliste.leistenperson(nil, gewaehlt: [Self.anna, Self.clara], sichtbar: zeilen) == nil,
                "zwei sichtbare: die Sammelleiste")
        #expect(Ruecklaufliste.leistenperson(Self.clara, gewaehlt: [Self.clara], sichtbar: zeilen) == Self.clara)
        #expect(Ruecklaufliste.leistenperson(Self.ben, gewaehlt: [Self.ben], sichtbar: zeilen) == nil,
                "die Gewählte steht nicht in der Tabelle")
        #expect(Ruecklaufliste.leistenperson(Self.clara, gewaehlt: [Self.anna], sichtbar: zeilen) == Self.clara,
                "die gewählte Person geht der einen sichtbaren Gewählten vor (W1-09)")
    }

    @Test("„Alle Mitglieder der Lerngruppe“ nimmt die Aufzunehmenden in einem Schritt hinten an; Rückläufe bleiben")
    func alleAufnehmen() throws {
        let b = Self.bestand()
        let neu = Ruecklaufliste.alleAufnehmen(b, "m-f", [Self.ben, Self.emil], jetzt: "2026-11-02T09:00:00.000Z")
        let fotos = try Self.anliegen(neu, "m-f")
        #expect(fotos.betroffene == [Self.anna, Self.clara, Self.ben, Self.emil])
        #expect(neu.rueckmeldungen == b.rueckmeldungen)
        let vorher = try Self.anliegen(b, "m-w"), nachher = try Self.anliegen(neu, "m-w")
        #expect(nachher == vorher, "die übrigen bleiben")
        #expect(Ruecklaufliste.alleAufnehmen(b, "m-x", [Self.ben], jetzt: Self.s) == b, "unbekannt: nichts")
        #expect(Mitteilungstext.auchAnAlle == Vereinbarungstext.auchFuerAlle, "derselbe Wortlaut wie E853")
    }

    // ── Sammelleiste über den Zeilen der Tabelle (E929) ───────────────────

    @Test("E929 über der neuen Tabelle: Die Sammelleiste nimmt die Gewählten, die in der Tabelle stehen — Emil zählt nicht")
    func sammelauswahl() throws {
        let b = Self.bestand()
        let wandertag = try Self.anliegen(b, "m-w")
        let zeilen = Ruecklaufliste.zeilen(wandertag, Lernendenverzeichnis(b).mitglieder("g-5a")).map(\.id)
        #expect(Lernendenblatt.sammelauswahl(sichtbar: zeilen, mehrere: [Self.anna, Self.ben, Self.emil]) == [Self.anna, Self.ben])
        #expect(Lernendenblatt.sammelauswahl(sichtbar: zeilen, mehrere: [Self.anna, Self.emil]) == nil,
                "eine sichtbare Gewählte ist keine Sammelauswahl")
    }

    // ── Wortlaute (V3, V8 — wie im Prototyp, E994) ─────────────────────────

    @Test("V3: Spalten wie bei den Maßnahmen — Person · Mitteilung · Frist · Stand; die Wortlaute an einer Stelle")
    func wortlaute() {
        #expect([Mitteilungstext.spaltePerson, Mitteilungstext.spalteMitteilung, Mitteilungstext.spalteFrist,
                 Mitteilungstext.spalteStand] == ["Person", "Mitteilung", "Frist", "Stand"])
        #expect(Mitteilungstext.auswahlHilfe == "Die Mitteilung, die die Tabelle zeigt und „Löschen …“ betrifft")
        #expect(Mitteilungstext.auchAn == "Auch an …" && Mitteilungstext.ausNehmen == "Aus der Mitteilung nehmen")
    }

    // ── Der Aufbau der Ansicht (V1) — am Quelltext, wie E851 ──────────────

    private static func ruecklaufliste() throws -> String {
        let datei = URL(filePath: #filePath)
            .deletingLastPathComponent()      // Pruefungen
            .deletingLastPathComponent()      // Fassungsordner
            .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Dialoge/AnliegenAnsicht.swift")
        let text = try String(contentsOf: datei, encoding: .utf8)
        let anfang = try #require(text.range(of: "struct Ruecklaufliste: View {"))
        let ende = try #require(text.range(of: "// ── Die Maßnahmen", range: anfang.upperBound..<text.endIndex))
        return String(text[anfang.upperBound..<ende.lowerBound])
    }

    @Test("V1: ein Auswahlfeld über der Tabelle wählt Anzeige und „Löschen …“ zugleich; keine Spalte je Mitteilung mehr")
    func aufbau() throws {
        // Leerraum zusammengezogen — die Prüfung hängt nicht an der Einrückung (Z-BC2-04).
        let liste = try Self.ruecklaufliste().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(!liste.contains("TableColumnForEach"), "keine Spalte je Mitteilung")
        #expect(liste.components(separatedBy: "Picker(Mitteilungstext.auswahlBezeichnung, selection: $aktiv)").count == 2,
                "genau ein Auswahlfeld, gebunden an die gezeigte Mitteilung")
        let auswahl = try #require(liste.range(of: "anlegezeile auswahlzeile"))
        let tabelle = try #require(liste.range(of: "tabelle(m, zeilen) mitteilungsleiste(m, personen)"))
        #expect(auswahl.upperBound <= tabelle.lowerBound, "das Auswahlfeld steht über der Tabelle")
        // Die Tabelle zeigt nur Betroffene, die Sammelleiste nimmt nur, was dort steht (E988, E929; Z-BC2-03).
        #expect(liste.contains("let personen = bezug.personen(gruppe) let zeilen = Tabellenordnung.geordnet(Self.reihen(m, "
                               + "Self.zeilen(m, personen), bezug.verzeichnis), nach: ordnung)"),
                "die Zeilen sind die Betroffenen der gewählten Mitteilung, samt Stand (E1008)")
        // „Auch an …“ aus denselben Personen wie die Zeilen — mit dem Schalter auch Archivierte (W1-06, W1-09).
        #expect(liste.contains("mitteilungsleiste(m, personen)")
                    && liste.contains("private func mitteilungsleiste(_ m: Anliegen, _ personen: [Lernender]) -> some View { "
                                      + "let weitere = Self.aufzunehmen(m, personen)"),
                "die Leiste nimmt die Personen des Körpers")
        #expect(liste.contains("Lernendenblatt.sammelauswahl(sichtbar: zeilen.map(\\.id), mehrere: auswahl.wrappedValue)"),
                "die Sammelleiste nimmt die sichtbaren Gewählten")
        let zeile = try #require(liste.range(of: "private var auswahlzeile: some View {"))
        let danach = try #require(liste.range(of: "private func tabelle(", range: zeile.upperBound..<liste.endIndex))
        let inDerZeile = liste[zeile.upperBound..<danach.lowerBound]
        let loeschen = "if let m = aktive { Button(\"Löschen …\", role: .destructive) { bezug.loeschen(m.id) }"
        #expect(inDerZeile.contains(loeschen), "„Löschen …“ betrifft die gewählte")
        #expect(inDerZeile.contains("Picker(Mitteilungstext.auswahlBezeichnung, selection: $aktiv)"),
                "das Auswahlfeld steht in der Zeile über der Tabelle (Z-BC2N-02)")
        // Die Leiste gehört der Person aus `leistenperson` — im Körper, beim Laden und beim Wechsel (E999; Z-BC2N-03).
        #expect(liste.contains("Self.leistenperson(person, gewaehlt: auswahl.wrappedValue, sichtbar: zeilen.map(\\.id))"),
                "die Leiste zeigt die Person aus `leistenperson`")
        #expect(liste.contains("leistenId.map { Paar(anliegen: a, person: $0) }") && liste.contains(".onChange(of: leistenId)"),
                "Notiz laden und übernehmen an derselben Person")
        #expect(inDerZeile.contains("Rueckmeldungslistenbogen.knopftitel"), "„Rückmeldungsliste …“ in derselben Zeile")
    }
}
