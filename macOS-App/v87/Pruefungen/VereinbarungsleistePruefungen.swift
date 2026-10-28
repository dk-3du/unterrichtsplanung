// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Vereinbarungen aus den Handproben H-AX9-02 bis -05 und die Meldung im Fuß (v86, AX9: E851–E855) ──
// Die Leiste in drei Zeilen (E851), der Stand als Menü in der Spalte (E852), „Alle Mitglieder der Lerngruppe“ in „Auch für …“
// (E853), die Zeile „Vereinbarungen: …“ unter „Alle Lernenden“ (E854), die Meldungskapsel eines Blatts im Fuß (E855).

@Suite("Vereinbarungen: Leiste, Standmenü, alle Mitglieder, Zeile unter „Alle Lernenden“; Meldung im Fuß")
@MainActor
struct VereinbarungsleistePruefungen {

    private static let s = "2026-10-03T08:00:00.000Z"

    private func tag(_ iso: String) throws -> Tag { try #require(Tag(iso: iso)) }

    private static func person(_ id: String, _ vorname: String, _ nachname: String, archiviert: String = "") -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: s, geaendert: s, archiviert: archiviert)
    }

    /// „6a“ mit Anna Abel, Ben Abel, Cem Çelik und Dora Dietz; „Handyregel“ (6a) für Ben und Cem, gültig bis einschließlich
    /// 31.10.2026; „Nachreichen per Mail“ ohne Lerngruppe für Ben, ohne Datum.
    private static func bestand(doraArchiviert: Bool = false) -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [person("l-1", "Anna", "Abel"), person("l-2", "Ben", "Abel"), person("l-3", "Cem", "Çelik"),
                      person("l-4", "Dora", "Dietz", archiviert: doraArchiviert ? s : "")]
        b.lerngruppen = [Lerngruppe(id: "g-6a", name: "6a", art: .klasse, mitglieder: ["l-1", "l-2", "l-3", "l-4"], zeilen: [],
                                    skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        b.anliegen = [
            Anliegen(id: "v-1", art: .vereinbarung, titel: "Handyregel", lerngruppe: "g-6a", betroffene: ["l-2", "l-3"],
                     datum: "2026-10-01", frist: "2026-10-31", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "v-2", art: .vereinbarung, titel: "Nachreichen per Mail", lerngruppe: "", betroffene: ["l-2"],
                     datum: "2026-10-01", frist: "", notiz: "", angelegt: s, geaendert: s),
        ]
        return b
    }

    private static func quelltext(_ pfad: String) throws -> String {
        let datei = URL(filePath: #filePath)
            .deletingLastPathComponent()      // Pruefungen
            .deletingLastPathComponent()      // v86
            .appending(path: "Quellen/Unterrichtsplanung/" + pfad)
        return try String(contentsOf: datei, encoding: .utf8)
    }

    @Test("E854: Unter „Alle Lernenden“ die Zeile „Vereinbarungen: …“ — alle der Person, mit Lerngruppe und Stand; ohne keine")
    func personenzeile() throws {
        let vorher = Lernendenverzeichnis(Self.bestand(), heute: try tag("2026-10-05"))
        #expect(Vereinbarungstext.personenzeile("l-2", vorher)
                == "Vereinbarungen: Handyregel (6a, gültig) · Nachreichen per Mail (ohne Lerngruppe, gültig)")
        #expect(Vereinbarungstext.personenzeile("l-3", vorher) == "Vereinbarungen: Handyregel (6a, gültig)")
        #expect(Vereinbarungstext.personenzeile("l-1", vorher) == nil, "ohne Vereinbarung keine Zeile")
        // Abgelaufen: abgeleitet „ungültig“ (E743, E806).
        let danach = Lernendenverzeichnis(Self.bestand(), heute: try tag("2026-11-01"))
        #expect(Vereinbarungstext.personenzeile("l-3", danach) == "Vereinbarungen: Handyregel (6a, ungültig)")
    }

    @Test("E853: „Alle Mitglieder der Lerngruppe“ nimmt die aktiven, noch nicht Betroffenen in einem Schritt — erst ab zweien")
    func alleMitglieder() throws {
        #expect(Vereinbarungstext.auchFuerAlle == "Alle Mitglieder der Lerngruppe")
        let b = Self.bestand()
        let v = try #require(b.anliegen.first { $0.id == "v-1" })
        let ids = Vereinbarungsliste.alleAufzunehmen(b.lernende, v, gruppe: "g-6a")
        #expect(ids == ["l-1", "l-4"], "Anna und Dora — Ben und Cem sind schon betroffen")
        let danach = Vereinbarungsliste.alleAufnehmen(b, "v-1", ids, jetzt: Self.s)
        let alle = danach.anliegen.first { $0.id == "v-1" }?.betroffene
        #expect(alle == ["l-2", "l-3", "l-1", "l-4"], "ein Schritt nimmt beide auf")
        // Archivierte nicht; bliebe dann nur eine, steht ihr Name schon darunter — kein Eintrag.
        let mitArchiv = Self.bestand(doraArchiviert: true)
        #expect(Vereinbarungsliste.alleAufzunehmen(mitArchiv.lernende, v, gruppe: "g-6a").isEmpty)
        // Nur an einer Vereinbarung dieser Lerngruppe — nicht an einer ohne Lerngruppe oder aus einer anderen (Z-AX9R2-03).
        let ohne = try #require(b.anliegen.first { $0.id == "v-2" })
        #expect(Vereinbarungsliste.alleAufzunehmen(b.lernende, ohne, gruppe: "g-6a").isEmpty)
        #expect(Vereinbarungsliste.alleAufzunehmen(b.lernende, v, gruppe: "g-6b").isEmpty)
    }

    @Test("E851, E852: Leiste in drei Zeilen — Titel ohne feste Breite, die Knöpfe in eigener Zeile; der Stand der Spalte ist das Menü, die Segmente bleiben")
    func leisteUndStandmenue() throws {
        let text = try Self.quelltext("Oberflaeche/Dialoge/AnliegenAnsicht.swift")
        let anfang = try #require(text.range(of: "struct Vereinbarungsliste: View {"))
        let ende = try #require(text.range(of: "// ── Maßnahmen und Termine ohne Lerngruppe", range: anfang.upperBound..<text.endIndex))
        let liste = String(text[anfang.upperBound..<ende.lowerBound])
        #expect(!liste.contains(".frame(width: 180)"), "der Titel nimmt die volle Breite (E851)")
        #expect(liste.contains("HStack(spacing: 8) {\n                Spacer(minLength: 0)\n                if !weitere.isEmpty {"),
                "„Auch für …“ beginnt eine eigene, rechtsbündige Zeile (E851)")
        // An der Spalte selbst, nicht irgendwo (Z-AX9R2-05); am Titelfeld keine feste Breite.
        #expect(liste.contains("value: \\.stand) { z in\n                        standmenue(z)"), "die Spalte ruft das Menü (E852)")
        #expect(liste.contains("return Gueltigkeitsmenue(stand:"), "das Menü ist `Gueltigkeitsmenue`")
        let titelfeld = try #require(liste.range(of: "TextField(\"Titel\", text: $titel)"))
        let bisKaestchen = try #require(liste.range(of: "Toggle(", range: titelfeld.upperBound..<liste.endIndex))
        #expect(!liste[titelfeld.upperBound..<bisKaestchen.lowerBound].contains(".frame(width:"), "Titelfeld ohne feste Breite")
        #expect(liste.contains(".pickerStyle(.segmented)"), "die Segmente in der Leiste bleiben (E852)")
    }

    @Test("E855: Jedes Blatt mit eigener Meldungszeile trägt die Lücke im Fuß; über dem Körper liegt keine Kapsel mehr")
    func meldungImFuss() throws {
        let rahmen = try Self.quelltext("Gestaltung/Dialograhmen.swift")
        #expect(!rahmen.contains(".overlay(alignment: .bottom)"), "keine Kapsel über dem Körper")
        #expect(rahmen.contains(".environment(\\.meldungImFuss, eigene)"))
        // Im Abbild keine zweite Kapsel unter einem Bogen (Z-AX9R2-10).
        #expect(rahmen.contains("if !eigene, !zeileAbgegeben, Meldungszeile.imAbbild"))
        #expect(try Self.quelltext("Oberflaeche/Dialoge/LernendenDialog.swift").contains("zeileAbgegeben: bogenDarauf"))
        #expect(try Self.quelltext("Oberflaeche/Dialoge/VorhabenDialog.swift").contains("zeileAbgegeben: speicher.materialblattOffen"))
        // Auch Blätter ohne eigene Zeile, auf denen ein Bogen liegt (Z-AX9R4-04).
        #expect(try Self.quelltext("Oberflaeche/Dialoge/NeuePlanungDialog.swift").contains("zeileAbgegeben: bogen != nil"))
        #expect(try Self.quelltext("Oberflaeche/Dialoge/KlassenDialog.swift").contains("zeileAbgegeben: speicher.farbwahlFuer != nil"))
        #expect(try Self.quelltext("Oberflaeche/Dialoge/SchuljahrOeffnenDialog.swift").contains("zeileAbgegeben: zuordnung != nil"))
        var blaetter = 0
        for datei in ["LernendenDialog.swift", "ImportBogen.swift", "AnliegenAnsicht.swift", "RueckmeldungslisteBogen.swift",
                      "MaterialDialog.swift", "VorhabenDialog.swift"] {
            let zeilen = try Self.quelltext("Oberflaeche/Dialoge/" + datei)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (stelle, zeile) in zeilen.enumerated() where zeile.contains("Dialograhmen(") {
                let kopf = zeilen[stelle...].prefix { !$0.contains("} fuss: {") }
                guard kopf.contains(where: { $0.contains("meldungsblatt:") }) else { continue }
                blaetter += 1
                // Der Fuß bis zur schließenden Klammer auf seiner Einrückung.
                let fussStelle = stelle + kopf.count
                let einzug = zeilen[fussStelle].prefix { $0 == " " }.count
                let fuss = zeilen[(fussStelle + 1)...].prefix {
                    !($0.trimmingCharacters(in: .whitespaces) == "}" && $0.prefix { $0 == " " }.count == einzug)
                }
                // Je Zweig des Fußes eine Lücke — sonst fehlten dort die Meldungen ganz (Z-AX9R2-07).
                // Nur die Zweige des Fußes selbst, nicht die in Knopfaktionen (eine Ebene tiefer eingerückt).
                let zweige = fuss.filter {
                    $0.trimmingCharacters(in: .whitespaces) == "} else {" && $0.prefix { $0 == " " }.count == einzug + 4
                }.count + 1
                let luecken = fuss.filter { $0.contains("Fussluecke()") }.count
                #expect(luecken >= zweige, Comment(rawValue: "\(datei):\(fussStelle + 1): \(luecken) Lücken, \(zweige) Zweige"))
            }
        }
        #expect(blaetter == 8, "alle Blätter mit eigener Meldungszeile gefunden")
        // Allgemein (Z-AX9R5-02): Ein Blatt ohne eigene Zeile, das einen Bogen trägt, gibt seine Zeile im Abbild ab. Grenzen:
        // nur `Oberflaeche/Dialoge`, nur ein `.sheet(` in derselben Datei, geprüft wird das Vorkommen von `zeileAbgegeben:` —
        // die Bedingungen der drei Blätter stehen oben wörtlich (Z-AX9R6-02). Gelesen über die URL, nicht über den
        // prozentkodierten Pfad — unter „Claude Code“ fände `FileManager` den Ordner sonst nicht (Z-AX9R6-01).
        let ordner = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Dialoge")
        var mitBogen = 0
        let dateien = try FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)
        for name in dateien.map(\.lastPathComponent).sorted() where name.hasSuffix(".swift") {
            let zeilen = try Self.quelltext("Oberflaeche/Dialoge/" + name)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard zeilen.contains(where: { $0.contains(".sheet(") }) else { continue }
            for (stelle, zeile) in zeilen.enumerated() where zeile.contains("Dialograhmen(") && !zeile.contains("struct ") {
                var kopf = [String]()
                for weitere in zeilen[stelle...] {
                    kopf.append(weitere)
                    if weitere.trimmingCharacters(in: .whitespaces).hasSuffix("{") { break }
                }
                guard !kopf.contains(where: { $0.contains("meldungsblatt:") }) else { continue }
                mitBogen += 1
                #expect(kopf.contains { $0.contains("zeileAbgegeben:") }, Comment(rawValue: "\(name):\(stelle + 1)"))
            }
        }
        #expect(mitBogen == 3, "Klassen/Kurse, Neue Planungsdatei, Schuljahr öffnen")
    }

    @Test("E856, Z-AX9R5-03: Gewichen ist am Speicher vermerkt — auch ein neuer Fuß zeigt sie nicht wieder; mit ihr fällt der Vermerk")
    func gewicheneAmSpeicher() async throws {
        let ablage = URL.temporaryDirectory.appending(component: "gewichen-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ablage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.melden("Warnung", .warnung)
        s.melden("Hinweis")
        let warnung = try #require(s.meldungen.first)
        #expect(s.gewicheneMeldungen == [warnung.id], "die ältere wich der neueren")
        let vorher = Meldungskapseln.gezeigt(s.meldungen, nurJuengste: true, verdraengt: s.gewicheneMeldungen)
        #expect(vorher.map(\.text) == ["Hinweis"])
        await uhr.vorruecken(um: .milliseconds(2810))
        #expect(s.meldungen.map(\.text) == ["Warnung"], "der Hinweis ist verfallen")
        #expect(Meldungskapseln.gezeigt(s.meldungen, nurJuengste: true, verdraengt: s.gewicheneMeldungen).isEmpty,
                "die gewichene kommt nicht wieder — auch nicht in einem neuen Fuß")
        await uhr.vorruecken(um: .milliseconds(2400))
        #expect(s.meldungen.isEmpty && s.gewicheneMeldungen.isEmpty, "verfallen, der Vermerk fällt mit")
    }

    @Test("E856: Im Fuß steht nur die jüngste Meldung — der Fuß wächst nicht mit jeder; das Hauptfenster zeigt weiter alle")
    func nurDieJuengsteImFuss() throws {
        let erste = Meldung(text: "Die Gültigkeit bis einschließlich 24.10.2026 ist aufgehoben — „Handyregel“ gilt wieder für Ben Abel.",
                            art: .hinweis)
        let zweite = Meldung(text: "Die Gültigkeit bis einschließlich 24.10.2026 ist aufgehoben — „Sitzplatz“ gilt wieder für Cem Çelik.",
                             art: .hinweis)
        #expect(Meldungskapseln.gezeigt([erste, zweite], nurJuengste: true).map(\.text) == [zweite.text])
        #expect(Meldungskapseln.gezeigt([erste, zweite], nurJuengste: false).map(\.text) == [erste.text, zweite.text])
        #expect(Meldungskapseln.gezeigt([], nurJuengste: true).isEmpty)
        // Eine gewichene wird nicht gezeigt, auch wenn sie die letzte ist (Z-AX9R3-05).
        #expect(Meldungskapseln.gezeigt([erste], nurJuengste: true, verdraengt: [erste.id]).isEmpty)
        // Höchstens zwei Zeilen, ohne Hilfe; der Fuß nimmt nur die jüngste (Z-AX9R3-06, -07).
        let haupt = try Self.quelltext("Oberflaeche/Hauptansicht.swift")
        #expect(haupt.contains(".lineLimit(kompakt ? 2 : nil)"))
        #expect(haupt.contains("verdraengt: speicher.gewicheneMeldungen"), "der Vermerk am Speicher (Z-AX9R4-03, Z-AX9R5-03)")
        let kapseln = try #require(haupt.range(of: "struct Meldungskapseln: View {"))
        let melder = try #require(haupt.range(of: "struct Melder: View {"))
        #expect(!haupt[kapseln.upperBound..<melder.lowerBound].contains(".help("), "keine Hilfe an der Kapsel")
        #expect(try Self.quelltext("Gestaltung/Dialograhmen.swift").contains("Meldungskapseln(kompakt: true, nurJuengste: true)"))
    }
}
