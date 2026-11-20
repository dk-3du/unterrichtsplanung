// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

// Was aus der Fassung ins Repository geht, verweist auf keine Datei außerhalb (E1042); die Skripte laufen auch unter UTF-8.

@Suite("Verweise und Skripte: keine Dateien außerhalb des Repositorys, Variablen vor Mehrbytezeichen geklammert (E1042)")
struct VerweisePruefungen {
    /// Der Ordner der Fassung (`macOS-App/vNN`), von dieser Datei aus.
    static let fassung = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Alle Swift-Dateien unter `ordner` — fehlt der Ordner oder ist er fast leer, bricht die Prüfung ab: Sonst hieße
    /// „nichts gefunden“ auch „nichts gelesen“.
    static func swiftDateien(_ ordner: String) throws -> [URL] {
        let gang = try #require(FileManager.default.enumerator(at: fassung.appending(component: ordner),
                                                               includingPropertiesForKeys: nil), "\(ordner) fehlt")
        let dateien = gang.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        try #require(dateien.count > 100, "die Vorbedingung: \(ordner) gelesen (\(dateien.count) Dateien)")
        return dateien
    }

    /// Die Dateien an der Wurzel der Fassung mit einer dieser Endungen — Skripte, Werkzeug, `Package.swift`.
    static func wurzeldateien(_ endungen: Set<String>) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: fassung, includingPropertiesForKeys: nil)
            .filter { endungen.contains($0.pathExtension) }
    }

    /// Namen und Orte der Arbeitsunterlagen, wie sie auch die Prüfung vor der Beglaubigung sucht — dazu der Ordner des
    /// Projekts, auch in der Schreibweise mit `~/` (H3-06). Aus Teilen gebaut, damit diese Datei — sie wird mitgeprüft —
    /// sich nicht selbst trifft.
    static func internesMuster() throws -> Regex<AnyRegexOutput> {
        try Regex([
            "Vor" + "arbeiten", "Fassungs" + "vertr", "Entwicklungs" + "prozess", "scratch" + "pad", "/private/tmp/" + "claude",
            "/Users/" + "dominikkluge", #"werkzeug-v[0-9]"#, #"\b"# + "LIES" + #"MICH\b(?!\.(md|txt)\b)"#,
            #"\b"# + "LIES" + #"MICH\.md\b"#, #"\b"# + "VER" + #"SIONEN\b"#, #"plan-[a-z0-9]+\.md"#, "befunde" + "-",
            #"auftrag-[a-z]"#, "fortsetzung" + "-v", "vorlage" + "-", "vorlagen" + "-", "wortlaute" + "-", #"review-[A-Z]"#,
            "Dashboard_zur_" + "Unterrichtsplanung",
        ].joined(separator: "|"))
    }

    /// Erlaubt, weil Teil des Werkzeugs: `pruefen.sh` nimmt die Beschreibung der Fassung aus dem Inventar aus, `runde.py`
    /// legt eine Anleitung als Textdatei ins Rundenpaket. Ausgenommen wird nur der erlaubte Teil, nicht die Zeile (H3-05).
    static func erlaubtesMuster() throws -> Regex<AnyRegexOutput> {
        try Regex(#"_AUSNAHMEN=\("# + "LIES" + #"MICH\.md|> "\$basis/app/"# + "LIES" + #"MICH\.md"|"# + "LIES"
                  + #"MICH\.txt|\b"# + "LIES" + #"MICH,$"#)
    }

    @Test("Keine Datei der Fassung, die ins Repository geht, nennt eine Datei außerhalb — Quellen, Prüfungen, Skripte, Werkzeug")
    func keineInternenVerweise() throws {
        let intern = try Self.internesMuster()
        let erlaubt = try Self.erlaubtesMuster()
        // Das Muster greift: Ein erlaubter Name verdeckt den Rest der Zeile nicht; der Ordner des Projekts zählt auch mit
        // `~/` (H3-05, H3-06); der erlaubte Name allein bleibt frei.
        #expect(("siehe " + "LIES" + "MICH.txt und " + "Vor" + "arbeiten/x").replacing(erlaubt, with: "").contains(intern))
        #expect(("~/Downloads/" + "Dashboard_zur_" + "Unterrichtsplanung/macOS-App").contains(intern))
        #expect(!("die " + "LIES" + "MICH.txt im Paket").replacing(erlaubt, with: "").contains(intern))
        let wurzel = try Self.wurzeldateien(["sh", "py", "swift"])
        try #require(wurzel.contains { $0.lastPathComponent == "Package.swift" } && wurzel.count >= 6,
                     "die Vorbedingung: Skripte und Werkzeug gefunden (\(wurzel.map(\.lastPathComponent)))")
        var treffer: [String] = []
        for url in try Self.swiftDateien("Quellen") + Self.swiftDateien("Pruefungen") + wurzel {
            let zeilen = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (stelle, zeile) in zeilen.enumerated() where zeile.replacing(erlaubt, with: "").contains(intern) {
                treffer.append("\(url.lastPathComponent):\(stelle + 1)")
            }
        }
        #expect(treffer.isEmpty, "Verweise: \(treffer.joined(separator: ", "))")
    }

    @Test("In den Skripten steht keine Variable direkt vor einem Mehrbytezeichen — die Bash 3.2 läse es unter UTF-8 mit")
    func variablenGeklammert() throws {
        // Je Unicode-Skalar, wie die Bash je Byte liest: Auch ein Buchstabe mit folgendem Akzentzeichen zählt.
        let muster = try Regex(#"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]"#).matchingSemantics(.unicodeScalar)
        // Das Muster greift: ungeklammert vor „“ ja, geklammert und `$1` nein.
        #expect("Profil „$PROFIL“".contains(muster))
        #expect(!"Profil „${PROFIL}“".contains(muster) && !"$1“".contains(muster))
        let skripte = try Self.wurzeldateien(["sh"])
        try #require(skripte.count >= 4, "die Vorbedingung: die Skripte gefunden (\(skripte.map(\.lastPathComponent)))")
        var treffer: [String] = []
        for url in skripte {
            let zeilen = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (stelle, zeile) in zeilen.enumerated() where zeile.contains(muster) {
                treffer.append("\(url.lastPathComponent):\(stelle + 1)")
            }
        }
        #expect(treffer.isEmpty, "ungeklammert: \(treffer.joined(separator: ", "))")
    }
}
