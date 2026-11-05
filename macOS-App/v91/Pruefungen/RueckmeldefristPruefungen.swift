// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import PDFKit
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die Rückmeldefrist einer Mitteilung (v91, BC3: V5, V6) ────────────────
// Eine Mitteilung trägt wahlweise eine Frist in `frist` — anlegen, ändern, leeren. Verstrichen und offen steht sie orange
// wie bei den Maßnahmen (dieselbe Regel). Sie erscheint in der Tabelle, im Bogen „Rückmeldungsliste“ (Spaltenkopf
// „bis ‹Tag›“), im Archiv und in der Zeile „Offen: …“ einer Person (V5). Eine Mitteilung mit verstrichener Frist wird nie
// „ungültig“ — Gültigkeit gibt es nur an Vereinbarungen.

@Suite("Rückmeldefrist der Mitteilungen: anlegen, ändern, leeren; verstrichen; Bogen, Archiv, „Offen: …“ (BC3)")
@MainActor
struct RueckmeldefristPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private static let s = "2026-09-01T08:00:00.000Z"
    private let kennwort = "Elternbriefe 2026"

    private func tag(_ iso: String) throws -> Tag { try #require(Tag(iso: iso)) }

    private static func person(_ id: String, _ vorname: String, _ nachname: String) -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: s, geaendert: s, archiviert: "")
    }

    /// „6a“ mit Anna und Ben; „Elternbrief“ vom 07.09.2026 mit Rückmeldung bis 14.09.2026 an beide, Anna erledigt;
    /// „Fotos“ vom 10.09.2026 ohne Frist an beide; die Maßnahme „Nacharbeit“ bis 14.09.2026 für Ben; der Termin
    /// „Elterngespräch“ am 20.10.2026, 07:45 Uhr, für Ben.
    private static func bestand() -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [person("l-anna", "Anna", "Abel"), person("l-ben", "Ben", "Bauer")]
        b.lerngruppen = [Lerngruppe(id: "g-6a", name: "6a", art: .klasse, mitglieder: ["l-anna", "l-ben"], zeilen: [],
                                    skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        b.anliegen = [
            Anliegen(id: "m-brief", art: .mitteilung, titel: "Elternbrief", lerngruppe: "g-6a", betroffene: ["l-anna", "l-ben"],
                     datum: "2026-09-07", frist: "2026-09-14", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "m-fotos", art: .mitteilung, titel: "Fotos", lerngruppe: "g-6a", betroffene: ["l-anna", "l-ben"],
                     datum: "2026-09-10", frist: "", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "n-1", art: .massnahme, titel: "Nacharbeit", lerngruppe: "g-6a", betroffene: ["l-ben"],
                     datum: "2026-09-07", frist: "2026-09-14", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "t-1", art: .termin, titel: "Elterngespräch", lerngruppe: "", betroffene: ["l-ben"],
                     datum: "2026-10-20", frist: "", uhrzeit: "07:45", notiz: "", angelegt: s, geaendert: s),
        ]
        b.rueckmeldungen = [Rueckmeldung(anliegen: "m-brief", lernender: "l-anna", stand: .erledigt, datum: "2026-09-09",
                                         notiz: "", geaendert: s)]
        return b
    }

    private func anliegen(_ b: Lernendenbestand, _ id: String) throws -> Anliegen {
        try #require(b.anliegen.first { $0.id == id })
    }

    // ── Am Bestand: anlegen, ändern, leeren (V6) ──────────────────────────

    @Test("V6: Eine Mitteilung mit oder ohne Frist anlegen; die Frist ändern und leeren — je ein Schritt am Bestand")
    func anlegenAendernLeeren() throws {
        let b = Self.bestand()
        let jetzt = "2026-09-02T08:00:00.000Z"
        let (mit, id) = try #require(b.mitNeuemAnliegen(.mitteilung, titel: "Wandertag", lerngruppe: "g-6a",
                                                       betroffene: ["l-anna"], datum: "2026-09-02", frist: "2026-09-09",
                                                       jetzt: jetzt))
        #expect(try anliegen(mit, id).frist == "2026-09-09", "mit Frist angelegt")
        let (ohne, ohneId) = try #require(b.mitNeuemAnliegen(.mitteilung, titel: "Wandertag", lerngruppe: "g-6a",
                                                            betroffene: ["l-anna"], datum: "2026-09-02", frist: "",
                                                            jetzt: jetzt))
        #expect(try anliegen(ohne, ohneId).frist == "", "ohne Frist (V6: wahlweise)")
        let m = try anliegen(mit, id)
        let geaendert = mit.mitAnliegen(id, titel: m.titel, datum: m.datum, frist: "2026-09-16", notiz: m.notiz, jetzt: jetzt)
        #expect(try anliegen(geaendert, id).frist == "2026-09-16")
        let geleert = geaendert.mitAnliegen(id, titel: m.titel, datum: m.datum, frist: "", notiz: m.notiz, jetzt: jetzt)
        #expect(try anliegen(geleert, id).frist == "", "geleert")
        #expect(geleert.mitAnliegen(id, titel: m.titel, datum: m.datum, frist: "kein Tag", notiz: m.notiz, jetzt: jetzt)
                == geleert, "kein lesbarer Tag: keine Frist, nichts geändert")
    }

    // ── Verstrichen (wie bei den Maßnahmen) ───────────────────────────────

    @Test("Die Frist an der Oberfläche: Anlegezeile mit und ohne Haken; Kästchen der Leiste an eine Woche, aus keine (Z-BC3-01)")
    func fristAnDerOberflaeche() throws {
        let woche = try tag("2026-11-08"), heute = try tag("2026-11-01")
        #expect(Ruecklaufliste.fristBeimAnlegen(mitFrist: true, woche) == "2026-11-08")
        #expect(Ruecklaufliste.fristBeimAnlegen(mitFrist: false, woche) == "", "ohne Haken keine Frist")
        #expect(Ruecklaufliste.fristNachKaestchen(true, heute: heute) == "2026-11-08", "an: eine Woche ab heute")
        #expect(Ruecklaufliste.fristNachKaestchen(false, heute: heute) == "", "aus: keine")
        // Verdrahtet — und das Kästchen der Leiste ist ein eigener Schritt (ohne Kennung), am Quelltext wie `aufbau`.
        let datei = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Dialoge/AnliegenAnsicht.swift")
        let quelle = try String(contentsOf: datei, encoding: .utf8).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(quelle.contains("Tag.heute.iso, Self.fristBeimAnlegen(mitFrist: mitFrist, neueFrist))"), "Anlegezeile")
        #expect(quelle.contains("mitteilungSetzen(m.id, frist: Self.fristNachKaestchen(an, heute: .heute), kennung: nil)"),
                "Kästchen der Leiste, ein eigener Schritt")
        // Kästchen und Datum der Anlegezeile für VoiceOver von der Leiste unterschieden (Z-BC3-06, Z-BC5-01).
        let kaestchen = try #require(quelle.range(of: "Toggle(Mitteilungstext.rueckmeldungBis, isOn: $mitFrist)"))
        let datum = try #require(quelle.range(of: "Datumsfeld(tag: $neueFrist)", range: kaestchen.upperBound..<quelle.endIndex))
        let bezeichnung = ".accessibilityLabel(Mitteilungstext.fristNeuBezeichnung)"
        #expect(quelle[kaestchen.upperBound..<datum.lowerBound].contains(bezeichnung), "das Kästchen trägt die Bezeichnung")
        #expect(quelle[datum.upperBound...].prefix(120).contains(bezeichnung), "das Datum ebenso")
    }

    @Test("Verstrichen ist eine Frist ab dem Folgetag und nur, solange die Person offen steht — dieselbe Regel für Maßnahmen")
    func verstrichen() throws {
        let frist = "2026-09-14"
        let amTag = try tag("2026-09-14"), danach = try tag("2026-09-15")
        #expect(!Anliegenbezug.verstrichen(frist, .offen, heute: amTag), "am Tag der Frist noch nicht")
        #expect(Anliegenbezug.verstrichen(frist, .offen, heute: danach))
        #expect(!Anliegenbezug.verstrichen(frist, .erledigt, heute: danach), "erledigt: nicht markiert")
        #expect(!Anliegenbezug.verstrichen(frist, .abgelehnt, heute: danach))
        #expect(!Anliegenbezug.verstrichen("", .offen, heute: danach), "ohne Frist nie")
        #expect(Anliegenbezug.fristVerstrichen == "Die Frist ist verstrichen", "der Wortlaut der Maßnahmen")
    }

    @Test("Eine Mitteilung mit verstrichener Frist wird nie „ungültig“ — sie bleibt ein offenes Anliegen mit Rückläufen")
    func nieUngueltig() throws {
        let b = Self.bestand()
        let spaeter = try tag("2026-10-01")
        let v = Lernendenverzeichnis(b, heute: spaeter)
        let brief = try anliegen(b, "m-brief")
        #expect(Lernendenverzeichnis.offen(brief, v.stand(brief.id, "l-ben")), "Ben steht offen")
        #expect(v.offeneAnliegen(von: "l-ben").contains { $0.id == "m-brief" })
        let versuch = b.mitGueltigkeit("m-brief", "l-ben", .ungueltig, heute: spaeter, jetzt: Self.s)
        #expect(versuch.bestand == b && versuch.hinweis == nil, "„ungültig“ gibt es nur an Vereinbarungen")
        #expect(Vereinbarungstext.personenzeile("l-ben", v) == nil, "keine Vereinbarung")
        let archiv = try #require(ArchivAnsicht.anliegenzeilen(b, v).first { $0.id == "m-brief" })
        #expect(archiv.stand == "1 offen · 1 erledigt", "die Stände eines Rücklaufs, nicht gültig/ungültig")
    }

    // ── Wo die Frist erscheint (V5) ───────────────────────────────────────

    @Test("V5: „Offen: …“ einer Person nennt die Rückmeldefrist einer Mitteilung, wo gesetzt; Maßnahme und Termin wie bisher")
    func offenerEintrag() throws {
        let b = Self.bestand()
        let brief = try anliegen(b, "m-brief"), fotos = try anliegen(b, "m-fotos")
        let massnahme = try anliegen(b, "n-1"), termin = try anliegen(b, "t-1")
        #expect(Anliegenbezug.offenerEintrag(brief) == "Elternbrief (Mitteilung vom 07.09.2026, Rückmeldung bis 14.09.2026)")
        #expect(Anliegenbezug.offenerEintrag(fotos) == "Fotos (Mitteilung vom 10.09.2026)")
        #expect(Anliegenbezug.offenerEintrag(massnahme) == "Nacharbeit (Maßnahme bis 14.09.2026)")
        #expect(Anliegenbezug.offenerEintrag(termin) == "Elterngespräch (Termin am 20.10.2026, 07:45 Uhr)")
    }

    @Test("V5: Im Archiv „07.09.2026, Rückmeldung bis 14.09.2026“ — geordnet weiter nach dem Tag; die Spalte wird breit")
    func archiv() throws {
        let b = Self.bestand()
        let zeilen = ArchivAnsicht.anliegenzeilen(b, Lernendenverzeichnis(b))
        let brief = try #require(zeilen.first { $0.id == "m-brief" })
        #expect(brief.tagtext == "07.09.2026, Rückmeldung bis 14.09.2026")
        #expect(brief.tag == "2026-09-07", "geordnet nach dem Tag der Mitteilung, nicht nach der Frist")
        #expect(try #require(zeilen.first { $0.id == "m-fotos" }).tagtext == "10.09.2026", "ohne Frist nur der Tag")
        #expect(ArchivAnsicht.tagspalteBreit(b), "mit einer Frist an einer Mitteilung")
        var ohne = b
        ohne.anliegen = b.anliegen.filter { $0.id != "m-brief" }
        #expect(!ArchivAnsicht.tagspalteBreit(ohne), "ohne Frist und ohne Vereinbarung bleibt sie schmal")
        // Breit genug für den längsten Text in der Systemschrift, mit Rand (Z-BC3-02).
        let schrift = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let laengster = ("30.09.2026, Rückmeldung bis 30.09.2026" as NSString).size(withAttributes: [.font: schrift]).width
        #expect(ArchivAnsicht.tagspalteIdeal(b) >= laengster + 16,
                "\(laengster) pt Text, \(ArchivAnsicht.tagspalteIdeal(b)) pt Spalte")
        #expect(ArchivAnsicht.tagspalteIdeal(ohne) == 90)
    }

    @Test("V5: Im Bogen „Rückmeldungsliste“ steht die Frist im Spaltenkopf unter dem Tag — „bis 14.09.2026“; ohne Frist nichts")
    func bogenSpaltenkopf() throws {
        let stand = try tag("2026-09-20")
        let liste = try #require(Rueckmeldungsliste.liste(Self.bestand(), gruppe: "g-6a", mitteilungen: ["m-brief", "m-fotos"],
                                                          stand: stand))
        #expect(liste.spalten.map(\.titel) == ["Elternbrief", "Fotos"])
        #expect(liste.spalten.map(\.unterzeile) == ["07.09.2026", "10.09.2026"])
        #expect(liste.spalten.map(\.frist) == ["bis 14.09.2026", ""])
        #expect(Rueckmeldungsliste.fristzeile("") == "" && Rueckmeldungsliste.fristzeile("kein Tag") == "")
    }

    @Test("V5 im PDF: Der Spaltenkopf trägt „bis 14.09.2026“ ungekürzt, Titel und Tag bleiben lesbar")
    func fristImPDF() throws {
        let stand = try tag("2026-09-20")
        let liste = try #require(Rueckmeldungsliste.liste(Self.bestand(), gruppe: "g-6a", mitteilungen: ["m-brief"],
                                                          stand: stand))
        guard case .verschluesselt(let daten) = Listensatz.pdf(liste, kennwort: kennwort) else {
            Issue.record("kein PDF")
            return
        }
        let pdf = try #require(PDFDocument(data: daten))
        #expect(pdf.unlock(withPassword: kennwort))
        let text = try #require(pdf.page(at: 0)?.string)
        #expect(text.contains("bis 14.09.2026"), "die Frist ungekürzt: \(text.prefix(300))")
        #expect(text.contains("Elternbrief") && text.contains("07.09.2026"))
    }

    // ── Wortlaute (V8 — Vorschläge für den Prototyp) ──────────────────────

    @Test("Wortlaute der Frist an einer Stelle: „Rückmeldung bis“, VoiceOver am Datum, eine Woche als Vorgabe")
    func wortlaute() {
        #expect(Mitteilungstext.rueckmeldungBis == "Rückmeldung bis")
        #expect(Mitteilungstext.fristNeuBezeichnung == "Rückmeldung bis — neue Mitteilung")
        #expect(Mitteilungstext.fristBezeichnung == "Rückmeldung bis")
        #expect(Mitteilungstext.fristTage == 7)
    }
}
