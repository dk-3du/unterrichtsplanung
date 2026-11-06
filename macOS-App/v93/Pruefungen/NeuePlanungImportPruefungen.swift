// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── „Neue Planung“ mit IServ-Import und Einschalten beim Anlegen (v84, AT5b: D1b, E349, E478, E529, E530) ──
// Eine vorbereitete Verschlüsselung wird beim Anlegen eingeschaltet — im selben Schritt, bevor das entprellte Sichern
// die Planung im Klartext schriebe —, danach kommt der Import in die versiegelte Jahresdatei, gebunden an die Zeilen
// gleichen Namens. Wird das Einschalten zurückgenommen, sagt es eine Warnung statt zweier; ohne Verschlüsselung
// unterbleibt der Import.

@Suite("Neue Planung mit IServ-Import: Einschalten beim Anlegen, Import gebunden, nie Klartext")
@MainActor
struct NeuePlanungImportPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    static let importmeldung = "IServ-Import: 3 neu · 0 unverändert · 0 übergangen; 1 Lerngruppe an ihre Zeilen gebunden, "
        + "1 ohne freie Zeile gleichen Namens — binden unter „Lernende, Klassen/Kurse und Fächer“ (⌘K)."

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "neueplanung-import-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func lesung() throws -> IServImport.Lesung {
        try ImportPruefungen.lesung(ImportPruefungen.datei([
            ImportPruefungen.zeile("Eva", "Ernst", klasse: "05G"), ImportPruefungen.zeile("Finn", "Fink", klasse: "7c"),
            ImportPruefungen.zeile("Gil", "Gras", klasse: "05G")]))
    }

    private func neuePlanung(_ s: Planungsspeicher, iserv: (lesung: IServImport.Lesung, ziel: Importziel)?,
                             einschalten: Bool) throws {
        s.neuePlanung(titel: "Import D1b", start: try #require(Tag(iso: "2026-08-10")), wochen: 6, basis: "",
                      klassen: Standardkurse.aufbauen([("05G", "Biologie"), ("05G", "Chemie"), ("6a", "")]),
                      ersterSchultag: nil, uebernahme: [], ohneMitglieder: [], iserv: iserv, einschalten: einschalten)
    }

    /// Ein Speicher wie beim ersten Start, das Blatt „Neue Planung“ zu — sonst würde eine Meldung nach `spaeterMelden`
    /// vorgemerkt und nicht gezählt (Z-AT5b-06).
    private func ersterStart(_ ordner: URL) -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        s.starten()
        s.offenerDialog = nil
        return s
    }

    /// Die Dateien unter dem Ordner, die einen Namen oder den Titel im Klartext tragen — auch zusammengesetzt
    /// („Finn Fink“ im Sitzplan, „Fink, Finn“). Ein Treffer zählt nur mit Nachbarn außerhalb des Base64-Alphabets:
    /// Sonst stand „Fink“ oder „Gras“ zufällig im Chiffrat eines versiegelten Behälters (nachgestellt je
    /// Versiegelung etwa 1:5000 bzw. 1:8000; v84, AT6a, E541, E542).
    private func klartextSpuren(_ ordner: URL) -> [String] {
        guard let liste = FileManager.default.enumerator(at: ordner, includingPropertiesForKeys: nil) else { return [] }
        var spuren: [String] = []
        for case let url as URL in liste {
            guard let d = try? Data(contentsOf: url) else { continue }
            let t = String(decoding: d, as: UTF8.self)
            if ["Ernst", "Fink", "Gras", "Import D1b"].contains(where: { Self.traegtWort(t, $0) }) {
                spuren.append(url.lastPathComponent)
            }
        }
        return spuren.sorted()
    }

    private static let base64Zeichen = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=\\")

    /// Steht `wort` in `text` mit Nachbarn außerhalb des Base64-Alphabets (oder am Rand)? Im Chiffrat hat jeder
    /// Treffer mindestens einen Nachbarn daraus; im Klartext stehen Anführungszeichen, Leerzeichen oder Komma.
    static func traegtWort(_ text: String, _ wort: String) -> Bool {
        var ab = text.startIndex
        while let r = text.range(of: wort, range: ab..<text.endIndex) {
            let vor: Character? = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : nil
            let nach: Character? = r.upperBound < text.endIndex ? text[r.upperBound] : nil
            if !(vor.map(base64Zeichen.contains) ?? false), !(nach.map(base64Zeichen.contains) ?? false) { return true }
            ab = text.index(after: r.lowerBound)
        }
        return false
    }

    @Test("Die Klartextsuche findet zusammengesetzte Namen, aber keinen Zufallstreffer im Base64 (E542)")
    func klartextsuche() {
        let f = Self.traegtWort
        #expect(f(#"{"nachname":"Fink"}"#, "Fink"), "als JSON-Zeichenkette")
        #expect(f(#"{"name":"Finn Fink"}"#, "Fink"), "zusammengesetzt, wie am Tisch im Sitzplan")
        #expect(f("Fink, Finn", "Fink"), "wie der Anzeigename")
        #expect(f(#""titel":"Import D1b""#, "Import D1b"))
        #expect(!f(#""daten":"q8xFinkveKRBc+G""#, "Fink"), "mitten im Base64")
        #expect(!f(#""daten":"Fink9ab""#, "Fink"), "am Anfang des Base64")
        #expect(!f(#""daten":"ab+Fink""#, "Fink"), "am Ende des Base64")
    }

    @Test("Vorbereitet, mit IServ-Datei (D1b): eingeschaltet beim Anlegen, Import gebunden in der versiegelten Jahresdatei — nie Klartext")
    func eingeschaltetMitImport() async throws {
        let ordner = try ordner("a")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let ablage = Ablage(ordner: ordner)
        let s = ersterStart(ordner)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        try neuePlanung(s, iserv: (try lesung(), .jeKlasse), einschalten: true)

        #expect(klartextSpuren(ordner).isEmpty, "schon direkt nach dem Anlegen kein Klartext: \(klartextSpuren(ordner))")
        #expect(s.meldungsfang == nil, "der Fang ist wieder zu")
        #expect(s.tresor != nil && s.vorbereitung == nil, "eingeschaltet beim Anlegen, die Vorbereitung verbraucht")
        let bestand = try #require(s.lernende.bestand, "die Jahresdatei mit dem Import")
        let p = try #require(s.planung)
        #expect(bestand.lernende.count == 3 && bestand.planung == p.erstellt)
        #expect(Set(bestand.lerngruppen.first { $0.name == "05G" }?.zeilen.map(\.klasseId) ?? [])
                == Set(p.klassen.filter { $0.name == "05G" }.map(\.id)), "an beide Zeilen „05G“")
        #expect(bestand.lerngruppen.first { $0.name == "7c" }?.zeilen.isEmpty == true, "„7c“ ohne Zeile")
        #expect(Tresor.istBehaelter(try Data(contentsOf: ablage.datei)), "planung.json versiegelt")
        #expect(Tresor.istBehaelter(try Data(contentsOf: ablage.lernende)), "lernende.json versiegelt")
        #expect(s.meldungen.contains { $0.text.hasPrefix("Verschlüsselung eingeschaltet") }, "die Meldung des Übergangs kommt")
        #expect(s.meldungen.contains { $0.text == Self.importmeldung })
        await s.sicherung.entprelltJetzt()
        s.jetztSichern()
        #expect(klartextSpuren(ordner).isEmpty, "Klartext in: \(klartextSpuren(ordner))")

        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ordner))
        zweiter.nachwahlProbe = true
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        #expect(zweiter.lernende.bestand?.lernende.count == 3, "nach einem neuen Start alles da")
        #expect(zweiter.lernende.bestand?.lerngruppen.first { $0.name == "05G" }?.zeilen.count == 2)
    }

    @Test("Zurückgenommen (Ordner schreibgeschützt): eine Warnung statt zweier (E478, E529), kein Import, die Planung in der Sitzung")
    func zurueckgenommen() throws {
        let ordner = try ordner("b")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ordner.path)
            try? FileManager.default.removeItem(at: ordner)
        }
        let s = ersterStart(ordner)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ordner.path)
        try neuePlanung(s, iserv: (try lesung(), .jeKlasse), einschalten: true)
        #expect(s.meldungsfang == nil, "der Fang ist wieder zu")

        #expect(s.tresor == nil && s.planung?.titel == "Import D1b", "die Planung steht in der Sitzung, unverschlüsselt")
        #expect(s.vorbereitung == nil, "die Vorbereitung ist verbraucht")
        let warnungen = s.meldungen.filter { $0.art == .warnung }.map(\.text)
        #expect(warnungen.count == 1
                && warnungen.first?.hasPrefix("Die Planung ist angelegt, die Verschlüsselung aber nicht eingeschaltet (") == true
                && warnungen.first?.hasSuffix(") — der Import aus IServ unterblieb, die gelesenen Namen sind verworfen. Der "
                                              + "notierte Wiederherstellungsschlüssel gilt nicht; einrichten lässt sich die "
                                              + "Verschlüsselung unter „Planung → Verschlüsselung …“.") == true,
                "\(warnungen)")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("Verschlüsselung nicht eingeschaltet") }, "nicht die allgemeine")
        #expect(s.lernende.bestand == nil && !FileManager.default.fileExists(atPath: Ablage(ordner: ordner).lernende.path),
                "kein Import")
    }

    @Test("Ohne Verschlüsselung, mit Datei (E530): Die Planung entsteht, der Import unterbleibt mit Warnung")
    func ohneVerschluesselung() throws {
        let ordner = try ordner("c")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        try neuePlanung(s, iserv: (try lesung(), .jeKlasse), einschalten: false)
        #expect(s.planung?.titel == "Import D1b" && s.tresor == nil)
        #expect(s.meldungen.contains {
            $0.art == .warnung && $0.text == "Die Planung ist angelegt; der Import aus IServ unterblieb, die gelesenen Namen "
                + "sind verworfen — die Lernendenverwaltung gibt es nur mit eingeschalteter Verschlüsselung."
        })
        #expect(!FileManager.default.fileExists(atPath: Ablage(ordner: ordner).lernende.path), "keine Jahresdatei")
    }

    @Test("Wortlaute (E478, E522, E530)")
    func wortlaute() {
        let grund = "die Generation ließ sich nicht anlegen (Zugriff verweigert)."
        let schluss = " Der notierte Wiederherstellungsschlüssel gilt nicht; einrichten lässt sich die Verschlüsselung unter "
            + "„Planung → Verschlüsselung …“."
        #expect(Planungsspeicher.einschaltenZurueckgenommen(grund, mitImport: true)
                == "Die Planung ist angelegt, die Verschlüsselung aber nicht eingeschaltet (die Generation ließ sich nicht "
                + "anlegen (Zugriff verweigert)) — der Import aus IServ unterblieb, die gelesenen Namen sind verworfen." + schluss)
        #expect(Planungsspeicher.einschaltenZurueckgenommen(grund, mitImport: false)
                == "Die Planung ist angelegt, die Verschlüsselung aber nicht eingeschaltet (die Generation ließ sich nicht "
                + "anlegen (Zugriff verweigert))." + schluss)
        #expect(Planungsspeicher.iservOhneVerschluesselung == "Die Planung ist angelegt; der Import aus IServ unterblieb, "
                + "die gelesenen Namen sind verworfen — die Lernendenverwaltung gibt es nur mit eingeschalteter Verschlüsselung.")
        #expect(Planungsspeicher.iservGesperrt("Die Lernendenverwaltung ist gerade nicht verfügbar (x) — die App liest sie "
                                               + "beim nächsten Start erneut.")
                == "Die Planung ist angelegt; der Import aus IServ unterblieb, die gelesenen Namen sind verworfen. Die "
                + "Lernendenverwaltung ist gerade nicht verfügbar (x) — die App liest sie beim nächsten Start erneut.", "E533")
    }

    @Test("Mit Verschlüsselung über einer bisherigen Planung (Schuljahreswechsel): Der Import kommt in die neue Jahresdatei, gebunden")
    func schuljahreswechselMitImport() async throws {
        let ordner = try ordner("e")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                                 basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        s.jetztSichern()
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let alt = try #require(s.planung)
        #expect(s.lernende.setzen(.leer(planung: alt.erstellt, schuljahr: "2026/27", jetzt: alt.erstellt)) == nil)

        s.neuePlanung(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                      klassen: Standardkurse.aufbauen([("05G", "Biologie"), ("05G", "Chemie")]), ersterSchultag: nil,
                      uebernahme: [], ohneMitglieder: [], iserv: (try lesung(), .jeKlasse))
        #expect(s.planung?.titel == "Schuljahr 2027/28")
        let b = try #require(s.lernende.bestand)
        #expect(b.lerngruppen.first { $0.name == "05G" }?.zeilen.count == 2, "an beide Zeilen der neuen Planung")
        #expect(b.planung == s.planung?.erstellt, "die neue Jahresdatei gehört zur neuen Planung")
        #expect(Tresor.istBehaelter(try Data(contentsOf: Ablage(ordner: ordner).lernende)), "versiegelt")
        #expect(s.meldungen.contains { $0.text == Self.importmeldung })
    }

    @Test("Ohne ausdrücklichen Wunsch bleibt eine liegende Vorbereitung unberührt (E531) — kein Einschalten, keine Warnung")
    func liegendeVorbereitung() throws {
        let ordner = try ordner("f")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        try neuePlanung(s, iserv: nil, einschalten: false)
        #expect(s.tresor == nil && s.vorbereitung != nil, "nicht eingeschaltet, die Vorbereitung liegt weiter")
        #expect(!s.meldungen.contains { $0.art == .warnung }, "\(s.meldungen.map(\.text))")
    }

    @Test("Ausdrücklich, aber ohne Vorbereitung (E531): die Warnung aus E478 mit dem Grund „es liegt keine Vorbereitung vor“")
    func ausdruecklichOhneVorbereitung() throws {
        let ordner = try ordner("g")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        try neuePlanung(s, iserv: nil, einschalten: true)
        #expect(s.tresor == nil && s.planung?.titel == "Import D1b")
        #expect(s.meldungen.filter { $0.art == .warnung }.map(\.text)
                == [Planungsspeicher.einschaltenZurueckgenommen("es liegt keine Vorbereitung vor", mitImport: false)])
    }

    @Test("D1b ohne Datei: eingeschaltet, keine Import-Meldung; beim Schuljahreswechsel bleibt eine Vorbereitung (Erneuern) liegen")
    func ohneDateiUndErneuern() async throws {
        let ordner = try ordner("h")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        try neuePlanung(s, iserv: nil, einschalten: true)
        #expect(s.tresor != nil && s.vorbereitung == nil && !s.meldungen.contains { $0.text.hasPrefix("IServ-Import") })

        let alt = try #require(s.planung)
        #expect(s.lernende.setzen(.leer(planung: alt.erstellt, schuljahr: "2026/27", jetzt: alt.erstellt)) == nil)
        _ = try s.verschluesselungVorbereiten(passphrase: "Ein anderer Satz, den man behält")
        s.neuePlanung(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                      klassen: [], ersterSchultag: nil, uebernahme: [], ohneMitglieder: [], einschalten: true)
        #expect(s.planung?.titel == "Schuljahr 2027/28" && s.vorbereitung != nil,
                "der Schuljahreswechsel schaltet nicht ein — die Vorbereitung bleibt dem Blatt „Verschlüsselung“")
    }

    @Test("Die allgemeine Warnung abtrennen (E529, E532) — ihr Zusatz kommt an die Warnung aus E478, die übrigen bleiben")
    func abtrennen() {
        let grund = "die Generation ließ sich nicht anlegen (x)"
        let gefangen: [(text: String, art: Meldung.Art)] = [
            ("Die Statusdatei der Web App …", .warnung),
            // Nach dem Doppelpunkt groß, im Nebensatz der Warnung aus E478 klein (E615).
            ("Verschlüsselung nicht eingeschaltet: Die Generation ließ sich nicht anlegen (x). Die Planung bleibt, wie sie "
             + "war. Lesezeichen: y.", .warnung)]
        let (uebrige, zusatz) = Planungsspeicher.allgemeineAbtrennen(gefangen, grund: grund)
        #expect(uebrige.map(\.text) == ["Die Statusdatei der Web App …"] && zusatz == " Lesezeichen: y.")
        #expect(Planungsspeicher.einschaltenZurueckgenommen(grund, mitImport: false, zusatz: zusatz)
                .hasSuffix("„Planung → Verschlüsselung …“. Lesezeichen: y."))
    }

    @Test("E681: Lässt sich die Planung beim Import nicht sichern, wird die Herkunft einmal gesichert, und eine Warnung nennt beide Folgen")
    func importOhneHerkunftEineWarnung() async throws {
        let ordner = try ordner("e681")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ordner.path)
            try? FileManager.default.removeItem(at: ordner)
        }
        let s = ersterStart(ordner)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        try neuePlanung(s, iserv: nil, einschalten: true)
        #expect(s.tresor != nil, "eingeschaltet beim Anlegen")
        // Nur ohne Jahresdatei versuchte „Übernehmen“ die Herkunft ein zweites Mal (Z-AT15N-15).
        #expect(s.lernende.bestand == nil, "noch keine Jahresdatei")
        var p = try #require(s.planung)
        p.erstellt = "2026-10-16T09:00:00.000Z"
        s.stempelEinsetzen(p)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ordner.path)
        s.meldungsfang = []
        s.iservUebernehmen((try lesung(), .jeKlasse))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ordner.path)
        let herkunft = (s.meldungsfang ?? []).map(\.text).filter { $0.contains("Herkunft") }
        s.meldungsfang = nil
        #expect(herkunft == [Planungsspeicher.iservOhneHerkunft], Comment(rawValue: herkunft.joined(separator: " | ")))
    }
}
