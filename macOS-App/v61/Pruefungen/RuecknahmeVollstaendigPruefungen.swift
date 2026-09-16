// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Die Prüfung, die den Ausbau zusammenhält (S5).
///
/// Sie verlangt dreierlei: Jeder Name, den die App vergibt, kommt in einem
/// Hin-und-zurück-Lauf vor; kein Lauf prüft einen Namen, den es nicht gibt; und
/// kein Schreibweg vergibt einen Namen am Katalog vorbei. Eine neue Änderung
/// ohne Rücknahmeprüfung fällt damit durch, statt still durchzurutschen.
@Suite("Rücknahme: vollständig")
struct RuecknahmeVollstaendigPruefungen {

    /// Namen, die keine Tabelle trägt, weil ihr Weg ein eigener ist — mit der
    /// Prüfung, die sie hin und zurück führt. Eine kurze Liste, und jede Zeile
    /// nennt ihren Beleg.
    static let einzeln: [String: String] = [
        Schrittname.sitzplanEntfernen: "Rücknahme: Sitzplan · „Ein entfernter Sitzplan kommt mit ⌘Z zurück“",
    ]

    /// Jeder Name, der in einer Fälle-Tabelle wirklich hin und zurück läuft.
    static let abgedeckt: Set<String> =
        Set(RuecknahmeVorhabenPruefungen.faelle.map(\.name))
        .union(RuecknahmeFlaechePruefungen.faelle.map(\.name))
        .union(RuecknahmeBearbeitenPruefungen.faelle.map(\.name))
        .union(RuecknahmeSitzplanPruefungen.faelle.map(\.name))
        .union(einzeln.keys)

    @Test("Jeder Schrittname kommt in einem Hin-und-zurück-Lauf vor")
    func jederNameGeprueft() {
        let fehlend = Schrittname.alle.filter { !Self.abgedeckt.contains($0) }.sorted()
        #expect(fehlend.isEmpty,
                Comment(rawValue: "ohne Rücknahmeprüfung: \(fehlend.joined(separator: " · "))"))
    }

    @Test("Und kein Lauf prüft einen Namen, den der Katalog nicht kennt")
    func keinNameZuviel() {
        let unbekannt = Self.abgedeckt.subtracting(Schrittname.alle).sorted()
        #expect(unbekannt.isEmpty,
                Comment(rawValue: "nicht im Katalog: \(unbekannt.joined(separator: " · "))"))
    }

    @Test("Die Namen sind eindeutig — zwei Handlungen, zwei Wortlaute")
    func keineDoppelten() {
        let doppelte = Dictionary(grouping: Schrittname.alle, by: { $0 })
            .filter { $0.value.count > 1 }.keys.sorted()
        #expect(doppelte.isEmpty, Comment(rawValue: doppelte.joined(separator: " · ")))
    }

    @Test("Kein Schreibweg vergibt seinen Namen am Katalog vorbei")
    func keineRohenWortlaute() throws {
        // Ein Wortlaut, der nur an der Aufrufstelle steht, ist einer, den der
        // Katalog nicht kennt — und den `jederNameGeprueft` darum nicht sieht.
        let quellen = URL(filePath: #filePath)
            .deletingLastPathComponent()      // Pruefungen
            .deletingLastPathComponent()      // v58
            .appending(path: "Quellen/Unterrichtsplanung")
        let verwaltung = FileManager.default
        let inhalt = try #require(verwaltung.enumerator(at: quellen, includingPropertiesForKeys: nil))
        var geprueft = 0
        var roh: [String] = []
        for fall in inhalt {
            guard let datei = fall as? URL, datei.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: datei, encoding: .utf8)
            for zeile in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let stelle = zeile.range(of: "aendern(") ?? zeile.range(of: "anmelden(")
                guard let stelle else { continue }
                guard !zeile.contains("func aendern("), !zeile.contains("func anmelden(") else { continue }
                geprueft += 1
                // Das erste Argument — bis zum Komma oder zur schließenden Klammer.
                let rest = zeile[stelle.upperBound...]
                let erstes = rest.prefix { $0 != "," && $0 != ")" }
                if erstes.contains("\"") {
                    roh.append("\(datei.lastPathComponent): \(zeile.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(geprueft >= 25, "die Quellen wurden wirklich durchgesehen")
        #expect(roh.isEmpty, Comment(rawValue: roh.joined(separator: "\n")))
    }
}
