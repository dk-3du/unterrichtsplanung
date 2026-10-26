// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Hochstufen beim Schuljahreswechsel (v80, E307–E311) ──────────────────
// Wie viele Stufen zwischen den Schuljahren liegen, welchen Namen eine
// Lerngruppe im neuen trägt und an welche Zeile der neuen Planung sie geht —
// reine Funktionen für „Neue Planung“ und ⌘O.

/// Was das Blatt je Lerngruppe festlegt (E308, E310): der Name im neuen
/// Schuljahr und die Zeile der neuen Planung (Kennung) — `nil`: keine.
struct Gruppenziel: Hashable, Sendable {
    var name: String
    var zeile: String?
}

enum Hochstufung {

    /// Eine Zeile der neuen Planung, wie das Blatt sie anbietet. `id` ist ihre
    /// Kennung — oder ein Schlüssel, solange sie noch keine hat („Neue Planung“).
    struct Zeile: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let fach: String
        let art: Zeilenart
        let titel: String

        init(id: String, name: String, fach: String, art: Zeilenart, titel: String) {
            self.id = id
            self.name = name
            self.fach = fach
            self.art = art
            self.titel = titel
        }

        init(_ klasse: Klasse, id: String? = nil) {
            self.init(id: id ?? klasse.id, name: klasse.name, fach: klasse.fach, art: klasse.art,
                      titel: klasse.beschriftung)
        }
    }

    /// Die Schuljahre zwischen dem der Jahresdatei und dem der neuen Planung
    /// (E307) — 0 im selben, negativ bei einem früheren; `nil`, wenn eines
    /// nicht die Form „2026/27“ hat.
    static func stufen(von bisher: String, zu neu: String) -> Int? {
        guard Lernendenbestand.istSchuljahr(bisher), Lernendenbestand.istSchuljahr(neu),
              let a = Int(bisher.prefix(4)), let b = Int(neu.prefix(4)) else { return nil }
        return b - a
    }

    /// Der Name `stufen` Klassenstufen höher (E308): die erste Zahl von 5 bis
    /// 13 im Namen, um `stufen` erhöht. Gibt es keine, läge das Ergebnis über
    /// 13 oder ist `stufen` nicht positiv, bleibt der Name.
    static func name(_ name: String, um stufen: Int) -> String {
        guard stufen > 0 else { return name }
        var stelle = name.startIndex
        while stelle < name.endIndex {
            guard name[stelle].isASCII, name[stelle].isNumber else {
                stelle = name.index(after: stelle)
                continue
            }
            var ende = stelle
            while ende < name.endIndex, name[ende].isASCII, name[ende].isNumber { ende = name.index(after: ende) }
            if let zahl = Int(name[stelle..<ende]), (5...13).contains(zahl) {
                guard zahl + stufen <= 13 else { return name }
                // Eine führende Null bleibt: „G05a“ wird „G06a“.
                let neu = String(zahl + stufen)
                let breite = name.distance(from: stelle, to: ende)
                return name.replacingCharacters(in: stelle..<ende,
                                                with: String(repeating: "0", count: max(0, breite - neu.count)) + neu)
            }
            stelle = ende
        }
        return name
    }

    /// Die erste Zeile, an der die Gruppe in der bisherigen Planung hängt und
    /// die übernommen wird — in der neuen Planung (`zuordnung` alt → neu).
    static func uebernommeneZeile(_ gruppe: Lerngruppe, planung: String, zuordnung: [String: String]) -> String? {
        gruppe.zeilen.lazy.filter { $0.planung == planung }.compactMap { zuordnung[$0.klasseId] }.first
    }

    /// Verglichen wird ohne Groß/Klein und Leerraum am Rand.
    private static func schluessel(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Die vorbelegte Zeile einer Gruppe (E311): die übernommene, sonst die
    /// eine, die `name` trägt — bei mehreren die mit dem bisherigen Fach,
    /// sonst keine. Die Klassenleitung trägt ihre Klasse im Fach.
    static func vorgabe(fuer gruppe: Lerngruppe, name: String, uebernommen: String?, zeilen: [Zeile]) -> String? {
        if let uebernommen, zeilen.contains(where: { $0.id == uebernommen }) { return uebernommen }
        let gesucht = schluessel(name)
        guard !gesucht.isEmpty else { return nil }
        let passend = zeilen.filter { schluessel($0.art == .klassenleitung ? $0.fach : $0.name) == gesucht }
        if passend.count == 1 { return passend[0].id }
        // Mehrere: die mit dem bisherigen Fach — eine Sonderzeile trägt keines.
        let fach = schluessel(gruppe.fach)
        let mitFach = passend.filter { schluessel($0.art == .unterricht ? $0.fach : "") == fach }
        return mitFach.count == 1 ? mitFach[0].id : nil
    }

    /// Die Zeile je Gruppe: von Hand Gewähltes zuerst (`""` heißt keine),
    /// dann die Vorgabe — in der Folge der Gruppen, keine Zeile zweimal.
    /// Eine gewählte Zeile, die es nicht mehr gibt, zählt nicht.
    static func zuteilung(_ gruppen: [Lerngruppe], namen: [String: String], uebernommen: [String: String],
                          zeilen: [Zeile], gewaehlt: [String: String]) -> [String: String] {
        let vorhanden = Set(zeilen.map(\.id))
        var ergebnis: [String: String] = [:]
        var vergeben = Set<String>()
        var vonHand = Set<String>()
        for g in gruppen {
            guard let wahl = gewaehlt[g.id], wahl.isEmpty || vorhanden.contains(wahl) else { continue }
            vonHand.insert(g.id)
            if !wahl.isEmpty, vergeben.insert(wahl).inserted { ergebnis[g.id] = wahl }
        }
        for g in gruppen where !vonHand.contains(g.id) {
            if let v = vorgabe(fuer: g, name: namen[g.id] ?? g.name, uebernommen: uebernommen[g.id], zeilen: zeilen),
               vergeben.insert(v).inserted {
                ergebnis[g.id] = v
            }
        }
        return ergebnis
    }

    /// Die Zeile unter dem Schalter „Lerngruppen hochstufen“ (E307).
    static func stufentext(bisher: String, neu: String, stufen: Int, an: Bool) -> String {
        let wirksam = an ? max(stufen, 1) : 0
        let folge = switch wirksam {
        case 0: "die Namen bleiben"
        case 1: "eine Stufe höher"
        default: "\(wirksam) Stufen höher"
        }
        return stufen == 0 ? "Beide im Schuljahr \(bisher) — \(folge)" : "\(bisher) → \(neu): \(folge)"
    }
}
