// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

// ── Erläuterungen im Kasten (v95, E1122) ──
// Nutzer, 07.11.2026: „Achte darauf, dass die Erläuterungen stets im grau hinterlegten Feld stehen, nicht darunter.“ Am
// Quelltext: In den Quellen der App (alle, nicht nur `Oberflaeche/Dialoge/`, R-BG8-W2-06) trägt kein Abschnitt mehr einen
// Fuß (`footer:`) — die Erläuterung ist eine Zeile im Kasten (`Erlaeuterung`). So kehrt die Regel nicht still zurück.

@Suite("Erläuterungen im Kasten (E1122)")
struct ErlaeuterungImKastenPruefungen {

    /// Der Quelltext ohne Kommentare (`//` bis zum Zeilenende, `/* … */` auch verschachtelt). Zeichenketten bleiben samt
    /// ihren Interpolationen stehen — ein `//` darin ist kein Kommentar. Die Zeilenumbrüche bleiben, damit die
    /// Zeilennummern stimmen.
    static func ohneKommentare(_ text: String) -> String {
        String(Kommentarfilter(text).ergebnis)
    }

    @Test("Der Filter nimmt Kommentare, nicht Zeichenketten")
    func filter() {
        let probe = #"""
            a;// footer: weg
            /* footer: /* innen */ weg */b "// bleibt" "x \(f("y")) // bleibt"
            """#
        let erwartet = #"""
            a;
            b "// bleibt" "x \(f("y")) // bleibt"
            """#
        #expect(Self.ohneKommentare(probe) == erwartet)
    }

    @Test("E1122: Kein `footer:` in den Quellen der App — außerhalb von Kommentaren")
    func keinTextUnterDemKasten() throws {
        // Gelesen über die URL, nicht über den prozentkodierten Pfad — unter „Claude Code“ fände `FileManager` den Ordner
        // sonst nicht (Z-AX9R6-01). Alle Quellen samt Unterordnern, nicht nur die Blätter (R-BG8-W2-06).
        let ordner = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung")
        let aufzaehlung = try #require(FileManager.default.enumerator(at: ordner, includingPropertiesForKeys: nil))
        var dateien: [URL] = []
        for case let datei as URL in aufzaehlung where datei.pathExtension == "swift" {
            // Die gesperrten Dateien werden hier nicht gelesen — sie tragen keine Oberfläche.
            guard !["Tresor.swift", "Uebergang.swift", "Planungsspeicher+Verschluesselung.swift"]
                .contains(datei.lastPathComponent) else { continue }
            dateien.append(datei)
        }
        dateien.sort { $0.path < $1.path }
        try #require(dateien.contains { $0.lastPathComponent == "VorhabenDialog.swift" }
                     && dateien.contains { $0.lastPathComponent == "Tour.swift" },
                     "die Quellen gefunden: \(dateien.count) Dateien")
        var funde: [String] = []
        for datei in dateien {
            let zeilen = Self.ohneKommentare(try String(contentsOf: datei, encoding: .utf8))
                .split(separator: "\n", omittingEmptySubsequences: false)
            // Auch `footer :` mit Leerraum vor dem Doppelpunkt (R-BG5b-07), wie das Werkzeug der Vorarbeit.
            for (stelle, zeile) in zeilen.enumerated()
            where zeile.range(of: #"\bfooter\s*:"#, options: .regularExpression) != nil {
                funde.append("\(datei.lastPathComponent):\(stelle + 1)")
            }
        }
        #expect(funde.isEmpty, "Erläuterungen gehören in den Kasten (E1122): \(funde.joined(separator: ", "))")
    }
}

/// Liest Swift-Quelltext Zeichen für Zeichen und lässt die Kommentare weg — für `ohneKommentare`.
private struct Kommentarfilter {
    private let zeichen: [Unicode.Scalar]
    private var stelle = 0
    private(set) var ergebnis = String.UnicodeScalarView()

    init(_ text: String) {
        zeichen = Array(text.unicodeScalars)
        code(bisKlammer: false)
    }

    private func folgt(_ muster: String, ab anfang: Int) -> Bool {
        var k = anfang
        for s in muster.unicodeScalars {
            guard k < zeichen.count, zeichen[k] == s else { return false }
            k += 1
        }
        return true
    }

    private mutating func uebernehmen(_ anzahl: Int) {
        for _ in 0..<anzahl where stelle < zeichen.count {
            ergebnis.append(zeichen[stelle])
            stelle += 1
        }
    }

    /// Code — bis zum Ende oder, in einer Interpolation (`bisKlammer`), bis vor ihre schließende Klammer.
    private mutating func code(bisKlammer: Bool) {
        var tiefe = 0
        while stelle < zeichen.count {
            if folgt("//", ab: stelle) {
                while stelle < zeichen.count, zeichen[stelle] != "\n" { stelle += 1 }
            } else if folgt("/*", ab: stelle) {
                var offen = 0
                repeat {
                    if folgt("/*", ab: stelle) {
                        offen += 1
                        stelle += 2
                    } else if folgt("*/", ab: stelle) {
                        offen -= 1
                        stelle += 2
                    } else {
                        if zeichen[stelle] == "\n" { ergebnis.append("\n") }
                        stelle += 1
                    }
                } while offen > 0 && stelle < zeichen.count
            } else if zeichen[stelle] == "\"" || (zeichen[stelle] == "#" && rohAnfang()) {
                zeichenkette()
            } else {
                if bisKlammer, zeichen[stelle] == "(" {
                    tiefe += 1
                } else if bisKlammer, zeichen[stelle] == ")" {
                    if tiefe == 0 { return }
                    tiefe -= 1
                }
                uebernehmen(1)
            }
        }
    }

    /// Steht hier `#…#"` — der Anfang einer rohen Zeichenkette?
    private func rohAnfang() -> Bool {
        var k = stelle
        while k < zeichen.count, zeichen[k] == "#" { k += 1 }
        return k < zeichen.count && zeichen[k] == "\""
    }

    /// Eine Zeichenkette — einfach, mehrzeilig oder roh — bis zu ihrem Ende, Interpolationen eingeschlossen.
    private mutating func zeichenkette() {
        var rauten = 0
        while zeichen[stelle + rauten] == "#" { rauten += 1 }
        let raute = String(repeating: "#", count: rauten)
        let mehrzeilig = folgt("\"\"\"", ab: stelle + rauten)
        let ende = (mehrzeilig ? "\"\"\"" : "\"") + raute
        let flucht = "\\" + raute
        uebernehmen(rauten + (mehrzeilig ? 3 : 1))
        while stelle < zeichen.count {
            if folgt(ende, ab: stelle) {
                uebernehmen(ende.unicodeScalars.count)
                return
            } else if folgt(flucht + "(", ab: stelle) {
                uebernehmen(flucht.unicodeScalars.count + 1)
                code(bisKlammer: true)
                uebernehmen(1)
            } else if folgt(flucht, ab: stelle) {
                uebernehmen(flucht.unicodeScalars.count + 1)
            } else {
                uebernehmen(1)
            }
        }
    }
}
