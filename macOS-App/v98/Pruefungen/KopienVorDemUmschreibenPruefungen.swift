// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Kopien aus der Umstellung auf 2.5.0 (v92, E1049) ─────────────────────
// Die Umstellung auf Fassung 2 (seit 2.5.0) schreibt Jahresdatei, Archiv und Sitzpläne um und lässt die Originale als
// `…-fassung1-<Stempel>.json` neben der Planung (E970). Das endgültige Löschen erreicht sie nicht. Die Rückfragen — eine
// Person, mehrere, eine Person in allen archivierten Schuljahren, ein ganzes Schuljahr (E1066), eine Lerngruppe, ein
// Anliegen im Blatt und im Archiv (E1069), ein Sitzplan und eine Klasse mit Sitzplan (E1070) — sagen das und wo sie
// liegen, wenn welche liegen, die das Gelöschte enthalten können; liegen keine oder lässt sich der Ordner nicht lesen,
// bleiben sie wörtlich, wie sie waren.
// Reine Funktionen für Finden und Absatz, dazu die Rückfragen an einem Ordner mit Kopien.

@Suite("Kopien vor dem Umschreiben: Die Rückfragen beim endgültigen Löschen nennen sie, wenn welche liegen (E1049, E1066, E1069, E1070)")
@MainActor
struct KopienVorDemUmschreibenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand, "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private static let s = "2026-10-03T08:00:00.000Z"

    /// Die drei Kopien, wie 2.5.0 sie anlegte — in der Folge des Registers.
    private static let kopien = ["archiv-fassung1-2026-09-01-074501.json", "lernende-fassung1-2026-09-01-074500.json",
                                 "sitzplaene-fassung1-2026-09-01-074502.json"]
    /// Rettungskopien anderer Art und die Dateien selbst — sie zählen nicht.
    private static let andere = ["archiv-beschaedigt-2026-10-02-120000.json", "archiv.json",
                                 "lernende-bereinigt-2026-10-01-100000.json", "lernende-unerwartet-2026-10-03-090000.json",
                                 "lernende.json", "planung-vorher.json", "sitzplaene-bereinigt-2026-10-01-100001.json",
                                 "sitzplaene.json"]

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "kopien-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func ablegen(_ namen: [String], in ort: URL) throws {
        for name in namen { try Data("{}".utf8).write(to: ort.appending(component: name)) }
    }

    /// Der Speicher an `ort`, ohne die Platte zu beschreiben; das Blatt „Lernende“ offen — die Fragen hängen an ihm (E418).
    private func speicher(_ ort: URL) -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ort), vorschau: true)
        s.offenerDialog = .lernende
        return s
    }

    /// Ben Abel und Cem Çelik in „6a“ — ohne Anliegen, Tische und Vorhaben: Die Rückfragen tragen nur ihre Zahlen.
    private static func bestand() -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-ben", vorname: "Ben", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-cem", vorname: "Cem", nachname: "Çelik", angelegt: s, geaendert: s, archiviert: "")]
        b.lerngruppen = [Lerngruppe(id: "g-6a", name: "6a", art: .kurs, mitglieder: ["l-ben", "l-cem"], zeilen: [],
                                    skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        return b
    }

    /// Dieselben, dazu eine Mitteilung an Ben in „6a“ und ein Termin mit ihm — für „Lerngruppe löschen“ und „Anliegen
    /// löschen“ (E1069).
    private static func mitAnliegen() -> Lernendenbestand {
        var b = bestand()
        b.anliegen = [Anliegen(id: "a-m", art: .mitteilung, titel: "Fotoerlaubnis", lerngruppe: "g-6a",
                               betroffene: ["l-ben"], datum: "2026-09-01", frist: "", notiz: "", angelegt: s, geaendert: s),
                      Anliegen(id: "a-t", art: .termin, titel: "Elterngespräch", lerngruppe: "", betroffene: ["l-ben"],
                               datum: "2026-09-02", frist: "", notiz: "", angelegt: s, geaendert: s)]
        return b
    }

    /// Dieselben im Archiv, im Schuljahr 2025/26.
    private static func archiv(_ lernende: Lernendenbestand = bestand()) throws -> Archivbestand {
        let planung = Planung.leer(titel: "Schuljahr 2025/26", start: try #require(Tag(iso: "2025-08-04")), wochen: 4,
                                   basis: "", klassen: [], fachfarben: [:])
        return Archivbestand(geaendert: "", jahre: [Archivjahr(id: "j-1", schuljahr: "2025/26", archiviert: s,
                                                               planung: planung, lernende: lernende)])
    }

    /// Eine Rückfrage, wie sie gerade lautet — gestellt und abgebrochen.
    private func frage(_ s: Planungsspeicher, _ stellen: () -> Void) throws -> String {
        stellen()
        let textOderNil = s.rueckfrage?.text
        let text = try #require(textOderNil)
        s.rueckfrageBeantworten(false)
        return text
    }

    /// Die drei Rückfragen, wie sie gerade lauten — je gestellt und abgebrochen.
    private func fragen(_ s: Planungsspeicher) throws -> (eine: String, mehrere: String, archiv: String) {
        s.personLoeschenFragen("l-ben", in: Self.bestand()) { _ in }
        let eineOderNil = s.rueckfrage?.text
        let eine = try #require(eineOderNil)
        s.rueckfrageBeantworten(false)
        s.personenLoeschenFragen(["l-ben", "l-cem"], in: Self.bestand()) { _ in }
        let mehrereOderNil = s.rueckfrage?.text
        let mehrere = try #require(mehrereOderNil)
        s.rueckfrageBeantworten(false)
        s.archivPersonLoeschenFragen("l-ben", in: try Self.archiv()) { _ in }
        let archivOderNil = s.rueckfrage?.text
        let archiv = try #require(archivOderNil)
        s.rueckfrageBeantworten(false)
        return (eine, mehrere, archiv)
    }

    /// Die drei Rückfragen ohne Kopien — wörtlich wie bis 2.6.0.
    private static let eineOhne = "„Abel, Ben“ endgültig löschen?\n\nMit der Person gehen in diesem Schuljahr ihre "
        + "Mitgliedschaft in 1 Lerngruppe, 0 Rückläufe, 0 Maßnahmen und 0 Einträge. Frühere Schuljahre im Archiv bleiben "
        + "unberührt.\n\nArchivieren nimmt die Person nur aus den Listen; alles bleibt."
    private static let mehrereOhne = "2 Personen endgültig löschen?\n\n„Abel, Ben“, „Çelik, Cem“.\n\nMit ihnen gehen in "
        + "diesem Schuljahr ihre Mitgliedschaften in 1 Lerngruppe, 0 Rückläufe, 0 Maßnahmen und 0 Einträge. Frühere "
        + "Schuljahre im Archiv bleiben unberührt.\n\nArchivieren nimmt die Personen nur aus den Listen; alles bleibt."
    private static let archivOhne = "„Abel, Ben“ in allen archivierten Schuljahren löschen?\n\nDie Person steht in "
        + "1 Schuljahr des Archivs. Mit ihr gehen dort ihre Mitgliedschaft in 1 Lerngruppe, 0 Rückläufe, 0 Maßnahmen und "
        + "0 Einträge. Das laufende Schuljahr bleibt unberührt.\n\nDas geschieht gleich nach dieser Frage, unabhängig von "
        + "„Übernehmen“, und lässt sich nicht widerrufen."

    @Test("E1049: Gefunden werden genau die Kopien vor dem Umschreiben — Jahresdatei, Archiv, Sitzpläne; andere Rettungskopien nicht")
    func kopienFinden() throws {
        #expect(Planungsspeicher.vorDemUmschreiben(Self.andere + Self.kopien) == Self.kopien)
        #expect(Planungsspeicher.vorDemUmschreiben(Self.andere).isEmpty)
        // Am Ordner: über das Register der Nebendateien, in seiner Folge.
        let ort = try ordner("finden")
        defer { try? FileManager.default.removeItem(at: ort) }
        try ablegen(Self.andere + Self.kopien, in: ort)
        #expect(speicher(ort).kopienVorDemUmschreiben == Self.kopien)
    }

    @Test("E1049: der Absatz — leer ohne Kopien; eine Kopie oder mehrere, eine Person oder mehrere")
    func wortlaut() {
        #expect(Planungsspeicher.kopienSatz([]) == "" && Planungsspeicher.kopienSatz([], mehrere: true) == "")
        #expect(Planungsspeicher.kopienSatz(["lernende-fassung1-2026-09-01-074500.json"])
                == "\n\nDas Löschen erreicht eine ältere Kopie aus der Umstellung auf 2.5.0 nicht; sie kann die Person "
                + "noch enthalten. Die Kopie liegt im Ordner der Autosicherung („Ablage → Ordner der Autosicherung "
                + "zeigen“), erkennbar an „fassung1“ im Namen.")
        #expect(Planungsspeicher.kopienSatz(Self.kopien, mehrere: true)
                == "\n\nDas Löschen erreicht 3 ältere Kopien aus der Umstellung auf 2.5.0 nicht; sie können die Personen "
                + "noch enthalten. Die Kopien liegen im Ordner der Autosicherung („Ablage → Ordner der Autosicherung "
                + "zeigen“), erkennbar an „fassung1“ im Namen.")
        // E1066: für ein ganzes Schuljahr im Archiv.
        #expect(Planungsspeicher.kopienSatz(["archiv-fassung1-2026-09-01-074501.json"], schuljahr: true)
                == "\n\nDas Löschen erreicht eine ältere Kopie aus der Umstellung auf 2.5.0 nicht; sie kann dieses Schuljahr "
                + "noch enthalten. Die Kopie liegt im Ordner der Autosicherung („Ablage → Ordner der Autosicherung "
                + "zeigen“), erkennbar an „fassung1“ im Namen.")
    }

    @Test("E1049: Liegen keine Kopien vor dem Umschreiben — auch nicht, wenn andere Rettungskopien liegen —, bleiben die drei Rückfragen wörtlich, wie sie waren")
    func ohneKopienWieBisher() throws {
        let ort = try ordner("ohne")
        defer { try? FileManager.default.removeItem(at: ort) }
        let s = speicher(ort)
        for runde in ["leer", "andere"] {
            if runde == "andere" { try ablegen(Self.andere, in: ort) }
            let (eine, mehrere, archiv) = try fragen(s)
            #expect(eine == Self.eineOhne, "\(runde): \(eine)")
            #expect(mehrere == Self.mehrereOhne, "\(runde): \(mehrere)")
            #expect(archiv == Self.archivOhne, "\(runde): \(archiv)")
        }
    }

    @Test("E1049: Eine Person, drei Kopien liegen — die Rückfrage nennt sie und den Ordner vor „Archivieren …“; liegen sie nicht mehr, schweigt sie")
    func einePersonMitKopien() throws {
        let ort = try ordner("eine")
        defer { try? FileManager.default.removeItem(at: ort) }
        try ablegen(Self.andere + Self.kopien, in: ort)
        let s = speicher(ort)
        let mit = try fragen(s).eine
        #expect(mit == "„Abel, Ben“ endgültig löschen?\n\nMit der Person gehen in diesem Schuljahr ihre Mitgliedschaft in "
                + "1 Lerngruppe, 0 Rückläufe, 0 Maßnahmen und 0 Einträge. Frühere Schuljahre im Archiv bleiben unberührt."
                + "\n\nDas Löschen erreicht 3 ältere Kopien aus der Umstellung auf 2.5.0 nicht; sie können die Person noch "
                + "enthalten. Die Kopien liegen im Ordner der Autosicherung („Ablage → Ordner der Autosicherung zeigen“), "
                + "erkennbar an „fassung1“ im Namen.\n\nArchivieren nimmt die Person nur aus den Listen; alles bleibt.",
                Comment(rawValue: mit))
        // Bei jeder Frage neu gelesen: Wer die Kopien fortgelegt hat, bekommt die Rückfrage wie bisher.
        for name in Self.kopien { try FileManager.default.removeItem(at: ort.appending(component: name)) }
        #expect(try fragen(s).eine == Self.eineOhne)
    }

    @Test("E1049: Mehrere Personen, eine Kopie liegt — die Rückfrage nennt sie in der Einzahl, für „die Personen“")
    func mehrerePersonenMitKopie() throws {
        let ort = try ordner("mehrere")
        defer { try? FileManager.default.removeItem(at: ort) }
        try ablegen(Self.andere + ["lernende-fassung1-2026-09-01-074500.json"], in: ort)
        let mit = try fragen(speicher(ort)).mehrere
        #expect(mit == "2 Personen endgültig löschen?\n\n„Abel, Ben“, „Çelik, Cem“.\n\nMit ihnen gehen in diesem Schuljahr "
                + "ihre Mitgliedschaften in 1 Lerngruppe, 0 Rückläufe, 0 Maßnahmen und 0 Einträge. Frühere Schuljahre im "
                + "Archiv bleiben unberührt.\n\nDas Löschen erreicht eine ältere Kopie aus der Umstellung auf 2.5.0 nicht; "
                + "sie kann die Personen noch enthalten. Die Kopie liegt im Ordner der Autosicherung („Ablage → Ordner der "
                + "Autosicherung zeigen“), erkennbar an „fassung1“ im Namen.\n\nArchivieren nimmt die Personen nur aus den "
                + "Listen; alles bleibt.", Comment(rawValue: mit))
    }

    @Test("E1049: Eine Person in allen archivierten Schuljahren, zwei Kopien liegen — die Rückfrage nennt sie zuletzt")
    func archivPersonMitKopien() throws {
        let ort = try ordner("archiv")
        defer { try? FileManager.default.removeItem(at: ort) }
        try ablegen(Self.andere + Array(Self.kopien.prefix(2)), in: ort)
        let mit = try fragen(speicher(ort)).archiv
        #expect(mit == "„Abel, Ben“ in allen archivierten Schuljahren löschen?\n\nDie Person steht in 1 Schuljahr des "
                + "Archivs. Mit ihr gehen dort ihre Mitgliedschaft in 1 Lerngruppe, 0 Rückläufe, 0 Maßnahmen und 0 Einträge. "
                + "Das laufende Schuljahr bleibt unberührt.\n\nDas geschieht gleich nach dieser Frage, unabhängig von "
                + "„Übernehmen“, und lässt sich nicht widerrufen.\n\nDas Löschen erreicht 2 ältere Kopien aus der Umstellung "
                + "auf 2.5.0 nicht; sie können die Person noch enthalten. Die Kopien liegen im Ordner der Autosicherung "
                + "(„Ablage → Ordner der Autosicherung zeigen“), erkennbar an „fassung1“ im Namen.", Comment(rawValue: mit))
    }

    @Test("E1066: der Absatz für ein Schuljahr auch mit mehreren Kopien")
    func schuljahrMehrereKopien() {
        #expect(Planungsspeicher.kopienSatz(Self.kopien, schuljahr: true)
                == "\n\nDas Löschen erreicht 3 ältere Kopien aus der Umstellung auf 2.5.0 nicht; sie können dieses Schuljahr "
                + "noch enthalten. Die Kopien liegen im Ordner der Autosicherung („Ablage → Ordner der Autosicherung "
                + "zeigen“), erkennbar an „fassung1“ im Namen.")
    }

    @Test("E1049: Lässt sich der Ordner nicht lesen, nennt die Rückfrage keine Kopien — sie bleibt wörtlich, wie sie war")
    func ordnerNichtLesbar() throws {
        let fort = URL.temporaryDirectory.appending(component: "kopien-fort-\(UUID().uuidString)", directoryHint: .isDirectory)
        let s = speicher(fort)
        #expect(s.kopienVorDemUmschreiben.isEmpty)
        #expect(try fragen(s).eine == Self.eineOhne)
    }

    @Test("E1049: Die Präfixe der Rückfragen sind die, mit denen die Umstellung die Kopien anlegt — Jahresdatei, Archiv, Sitzpläne")
    func praefixeWieDieDienste() throws {
        let dienste = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Dienste")
        let text = try ["Lernendendienst.swift", "Sitzplandienst.swift"]
            .map { try String(contentsOf: dienste.appending(component: $0), encoding: .utf8) }.joined()
        // Jede Art, mit der ein Dienst eine Kopie vor dem Umschreiben anlegt, und keine sonst (H2-02, R-BD7-06).
        let angelegt = Set(text.matches(of: #/"([a-z]+-fassung1-)"/#).map { String($0.output.1) })
        #expect(angelegt == Set(Planungsspeicher.kopienpraefixe), "so legt die Umstellung die Kopien an (E970)")
    }

    @Test("E1049: Der Absatz steht nach dem zu den Tischen und vor „Archivieren …“ — für eine Person und für mehrere")
    func absatzNachDenTischen() throws {
        let datei = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Speicher/Planungsspeicher+Lernende.swift")
        let text = try String(contentsOf: datei, encoding: .utf8)
        #expect(text.contains("            + Self.vorhabenSatz(vorhaben) + Self.tischeSatz(tische, plaene: plaene)\n"
                              + "            + Self.kopienSatz(kopienVorDemUmschreiben)\n"
                              + "            + \"\\n\\nArchivieren nimmt die Person nur aus den Listen; alles bleibt.\""), "eine (H2-06)")
        #expect(text.contains("            + Self.vorhabenSatz(vorhaben) + Self.tischeSatz(tische, plaene: plaene)\n"
                              + "            + Self.kopienSatz(kopienVorDemUmschreiben, mehrere: true)\n"
                              + "            + \"\\n\\nArchivieren nimmt die Personen nur aus den Listen; alles bleibt.\""),
                "mehrere (H2-06)")
    }

    @Test("E1066: Ein ganzes Schuljahr im Archiv löschen — ohne Kopien wie bisher; mit einer Kopie nennt die Rückfrage sie zuletzt, für „dieses Schuljahr“")
    func schuljahrMitKopien() throws {
        let ort = try ordner("schuljahr")
        defer { try? FileManager.default.removeItem(at: ort) }
        let s = speicher(ort)
        s.archivJahrLoeschenFragen("j-1", in: try Self.archiv()) { _ in }
        let ohneOderNil = s.rueckfrage?.text
        let ohne = try #require(ohneOderNil)
        s.rueckfrageBeantworten(false)
        #expect(ohne == "Das Schuljahr 2025/26 aus dem Archiv löschen?\n\nMit ihm gehen die Planung „Schuljahr 2025/26“ und "
                + "die Lernendendaten dieses Jahres: 2 Personen, 1 Lerngruppe, 0 Anliegen samt 0 Rückläufen und 0 Einträge.\n\n"
                + Planungsspeicher.archivEndgueltig, Comment(rawValue: ohne))
        try ablegen(Self.andere + ["archiv-fassung1-2026-09-01-074501.json"], in: ort)
        s.archivJahrLoeschenFragen("j-1", in: try Self.archiv()) { _ in }
        let mitOderNil = s.rueckfrage?.text
        let mit = try #require(mitOderNil)
        s.rueckfrageBeantworten(false)
        #expect(mit == ohne + "\n\nDas Löschen erreicht eine ältere Kopie aus der Umstellung auf 2.5.0 nicht; sie kann dieses "
                + "Schuljahr noch enthalten. Die Kopie liegt im Ordner der Autosicherung („Ablage → Ordner der Autosicherung "
                + "zeigen“), erkennbar an „fassung1“ im Namen.", Comment(rawValue: mit))
    }

    // ── Weitere endgültige Löschungen (V9, E1069) ─────────────────────────

    @Test("E1069: der Absatz mit „wen“ — gleich dem für Person, Personen und Schuljahr; ohne Kopien leer")
    func kopienSatzWen() {
        #expect(Planungsspeicher.kopienSatz(Self.kopien, wen: "die Person") == Planungsspeicher.kopienSatz(Self.kopien))
        #expect(Planungsspeicher.kopienSatz(Self.kopien, wen: "die Personen")
                == Planungsspeicher.kopienSatz(Self.kopien, mehrere: true))
        #expect(Planungsspeicher.kopienSatz(Self.kopien, wen: "dieses Schuljahr")
                == Planungsspeicher.kopienSatz(Self.kopien, schuljahr: true))
        #expect(Planungsspeicher.kopienSatz([], wen: "die Lerngruppe").isEmpty)
    }

    @Test("E1069: „Lerngruppe löschen“ nennt die Kopien am Ende — ohne Kopien wie bisher")
    func lerngruppeMitKopien() throws {
        let ort = try ordner("lerngruppe")
        defer { try? FileManager.default.removeItem(at: ort) }
        let s = speicher(ort)
        let ohne = try frage(s) { s.lerngruppeLoeschenFragen("g-6a", in: Self.mitAnliegen()) { _ in } }
        #expect(!ohne.contains("fassung1") && ohne.hasSuffix("Archivieren nimmt die Gruppe nur aus den Listen."),
                Comment(rawValue: ohne))
        // Eine Kopie der Sitzpläne enthält keine Lerngruppe (R-BD7-02).
        try ablegen(["sitzplaene-fassung1-2026-09-01-074502.json"], in: ort)
        #expect(try frage(s) { s.lerngruppeLoeschenFragen("g-6a", in: Self.mitAnliegen()) { _ in } } == ohne,
                "nur eine Kopie der Sitzpläne: wie ohne")
        try ablegen(Self.andere + ["lernende-fassung1-2026-09-01-074500.json"], in: ort)
        let mit = try frage(s) { s.lerngruppeLoeschenFragen("g-6a", in: Self.mitAnliegen()) { _ in } }
        #expect(mit == ohne + "\n\nDas Löschen erreicht eine ältere Kopie aus der Umstellung auf 2.5.0 nicht; sie kann die "
                + "Lerngruppe noch enthalten. Die Kopie liegt im Ordner der Autosicherung („Ablage → Ordner der Autosicherung "
                + "zeigen“), erkennbar an „fassung1“ im Namen.", Comment(rawValue: mit))
    }

    @Test("E1069: „Anliegen löschen“ nennt die Kopien am Ende — „die Mitteilung“, „den Termin“; ohne Kopien wie bisher")
    func anliegenMitKopien() throws {
        let ort = try ordner("anliegen")
        defer { try? FileManager.default.removeItem(at: ort) }
        let s = speicher(ort)
        let mitteilungOhne = try frage(s) { s.anliegenLoeschenFragen("a-m", in: Self.mitAnliegen()) { _ in } }
        let terminOhne = try frage(s) { s.anliegenLoeschenFragen("a-t", in: Self.mitAnliegen()) { _ in } }
        #expect(!mitteilungOhne.contains("fassung1") && !terminOhne.contains("fassung1"))
        try ablegen(Self.andere + Self.kopien, in: ort)
        let mitteilung = try frage(s) { s.anliegenLoeschenFragen("a-m", in: Self.mitAnliegen()) { _ in } }
        let termin = try frage(s) { s.anliegenLoeschenFragen("a-t", in: Self.mitAnliegen()) { _ in } }
        let liegen = " noch enthalten. Die Kopien liegen im Ordner der Autosicherung („Ablage → Ordner der Autosicherung "
            + "zeigen“), erkennbar an „fassung1“ im Namen."
        // Von den drei Kopien zählen Jahresdatei und Archiv, nicht die Sitzpläne (R-BD7-02).
        #expect(mitteilung == mitteilungOhne + "\n\nDas Löschen erreicht 2 ältere Kopien aus der Umstellung auf 2.5.0 nicht; "
                + "sie können die Mitteilung" + liegen, Comment(rawValue: mitteilung))
        #expect(termin == terminOhne + "\n\nDas Löschen erreicht 2 ältere Kopien aus der Umstellung auf 2.5.0 nicht; "
                + "sie können den Termin" + liegen, Comment(rawValue: termin))
    }

    @Test("E1069: Ein Anliegen im Archiv löschen — die Rückfrage nennt die Kopien ganz am Ende; ohne Kopien wie bisher")
    func archivAnliegenMitKopien() throws {
        let ort = try ordner("archivanliegen")
        defer { try? FileManager.default.removeItem(at: ort) }
        let s = speicher(ort)
        let archiv = try Self.archiv(Self.mitAnliegen())
        let ohne = try frage(s) { s.archivAnliegenLoeschenFragen("a-m", imJahr: "j-1", in: archiv) { _ in } }
        #expect(!ohne.contains("fassung1") && ohne.hasSuffix(Planungsspeicher.archivEndgueltig), Comment(rawValue: ohne))
        try ablegen(Self.andere + ["archiv-fassung1-2026-09-01-074501.json"], in: ort)
        let mit = try frage(s) { s.archivAnliegenLoeschenFragen("a-m", imJahr: "j-1", in: archiv) { _ in } }
        #expect(mit == ohne + "\n\nDas Löschen erreicht eine ältere Kopie aus der Umstellung auf 2.5.0 nicht; sie kann die "
                + "Mitteilung noch enthalten. Die Kopie liegt im Ordner der Autosicherung („Ablage → Ordner der Autosicherung "
                + "zeigen“), erkennbar an „fassung1“ im Namen.", Comment(rawValue: mit))
    }

    /// Ein Speicher an `ort` mit der Planung „6a“ samt Sitzplan — für „Sitzplan löschen“ und „Klasse entfernen“ (E1070).
    private func speicherMitSitzplan(_ ort: URL) throws -> (Planungsspeicher, Klasse) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ort), vorschau: true)
        let startOderNil = Tag(iso: "2026-08-03")
        let p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(startOderNil), wochen: 4, basis: "",
                             klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        s.planung = p
        let klasseOderNil = p.klassen.first
        let klasse = try #require(klasseOderNil)
        _ = s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: klasse.id, lernende: [.init(name: "Ben Abel", lernender: "l-ben")]),
                                fuer: klasse.id)
        try #require(s.sitzplaene.plan(fuer: klasse.id) != nil, "die Vorbedingung: ein Sitzplan an „6a“")
        return (s, klasse)
    }

    @Test("E1070: „Sitzplan löschen“ und „Klasse entfernen“ mit Sitzplan nennen die Kopie der Sitzpläne am Ende — nur sie; ohne wie bisher")
    func sitzplanMitKopien() throws {
        let ort = try ordner("sitzplan")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, klasse) = try speicherMitSitzplan(ort)
        let sitzplanOhne = try frage(s) { s.sitzplanEntfernen(klasse: klasse.id, ort: .hauptansicht) }
        s.offenerDialog = .klassen  // „Klasse entfernen“ hängt am Blatt der Klassen (E418).
        let klasseOhne = try frage(s) { s.klasseEntfernen(klasse) }
        s.offenerDialog = nil
        #expect(sitzplanOhne.hasSuffix("die Namen lassen sich jederzeit neu eingeben."), Comment(rawValue: sitzplanOhne))
        #expect(klasseOhne.hasSuffix("Der Sitzplan der Klasse wird mit entfernt."), Comment(rawValue: klasseOhne))
        // Kopien von Jahresdatei und Archiv enthalten keinen Sitzplan.
        try ablegen(Self.andere + ["archiv-fassung1-2026-09-01-074501.json", "lernende-fassung1-2026-09-01-074500.json"],
                    in: ort)
        #expect(try frage(s) { s.sitzplanEntfernen(klasse: klasse.id, ort: .hauptansicht) } == sitzplanOhne)
        try ablegen(["sitzplaene-fassung1-2026-09-01-074502.json"], in: ort)
        let absatz = "\n\nDas Löschen erreicht eine ältere Kopie aus der Umstellung auf 2.5.0 nicht; sie kann den Sitzplan "
            + "noch enthalten. Die Kopie liegt im Ordner der Autosicherung („Ablage → Ordner der Autosicherung zeigen“), "
            + "erkennbar an „fassung1“ im Namen."
        let sitzplan = try frage(s) { s.sitzplanEntfernen(klasse: klasse.id, ort: .hauptansicht) }
        s.offenerDialog = .klassen
        let klasseMit = try frage(s) { s.klasseEntfernen(klasse) }
        s.offenerDialog = nil
        #expect(sitzplan == sitzplanOhne + absatz, Comment(rawValue: sitzplan))
        #expect(klasseMit == klasseOhne + absatz, Comment(rawValue: klasseMit))
    }
}
