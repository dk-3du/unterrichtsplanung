// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Hochstufen beim Schuljahreswechsel (v80, E307–E311) ──────────────────
// Wie viele Stufen zwischen den Schuljahren liegen, welchen Namen eine
// Lerngruppe im neuen trägt und an welche Zeile der neuen Planung sie geht —
// reine Funktionen für „Neue Planung“ und ⌘O.

/// Was das Blatt je Lerngruppe festlegt (E308, E310, E649): der Name im neuen
/// Schuljahr und die Zeilen der neuen Planung (Kennungen), in ihrer Folge —
/// leer: keine. Ein Fach setzt der Wechsel nicht (E656).
struct Gruppenziel: Hashable, Sendable {
    var name: String
    var zeilen: [String]
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

    /// Die Zeilen, an denen die Gruppe in der bisherigen Planung hängt und die
    /// übernommen werden — in der neuen Planung (`zuordnung` alt → neu), in
    /// ihrer Folge, jede einmal. Die erste ist die vorbelegte (E311), die
    /// übrigen schlägt der Bogen mit vor (E650).
    static func uebernommeneZeilen(_ gruppe: Lerngruppe, planung: String, zuordnung: [String: String]) -> [String] {
        var folge: [String] = []
        for alt in gruppe.zeilen where alt.planung == planung {
            if let neu = zuordnung[alt.klasseId], !folge.contains(neu) { folge.append(neu) }
        }
        return folge
    }

    /// Verglichen wird ohne Groß/Klein und Leerraum am Rand.
    private static func schluessel(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Trägt die Zeile den gesuchten Namen (als `schluessel`)? Die Klassenleitung trägt ihre Klasse im Fach.
    private static func traegt(_ zeile: Zeile, _ gesucht: String) -> Bool {
        schluessel(zeile.art == .klassenleitung ? zeile.fach : zeile.name) == gesucht
    }

    /// Die vorbelegte Zeile einer Gruppe (E311, V11): die übernommene, sonst die
    /// erste des Angebots, die `name` trägt — ohne Fach der Gruppe (E665). Die
    /// Klassenleitung trägt ihre Klasse im Fach.
    static func vorgabe(name: String, uebernommen: String?, zeilen: [Zeile]) -> String? {
        if let uebernommen, zeilen.contains(where: { $0.id == uebernommen }) { return uebernommen }
        let gesucht = schluessel(name)
        guard !gesucht.isEmpty else { return nil }
        return zeilen.first { traegt($0, gesucht) }?.id
    }

    /// Die Zeilen, die `name` tragen — verglichen wie die Vorgabe, also auch die
    /// Klassenleitung mit der Klasse im Fach —, in der Folge des Angebots (E650).
    static func gleichnamige(_ name: String, zeilen: [Zeile]) -> [String] {
        let gesucht = schluessel(name)
        guard !gesucht.isEmpty else { return [] }
        return zeilen.filter { traegt($0, gesucht) }.map(\.id)
    }

    /// Die Zeilen je Gruppe (E311, E649, E650, E675), in der Folge der Gruppen —
    /// eine Zeile kann mehrere Gruppen tragen (E670) —, in vier Stufen: zuerst von Hand Festgelegtes (eine leere
    /// Folge heißt keine; eine Folge zählt nur, wenn sie leer ist oder eine
    /// Zeile nennt, die es gibt), dann je übrige Gruppe die vorbelegte Zeile
    /// (`vorgabe`), dann ihre übrigen Bindungen aus dem Vorjahr, zuletzt die
    /// Zeilen ihres Namens (`gleichnamige`) — der Vorschlag gibt eine Zeile allen
    /// Gruppen gleichen neuen Namens (E675); keiner wird etwas genommen. Je Gruppe
    /// steht eine Zeile einmal. Eine Gruppe trägt höchstens 20 Zeilen
    /// (`Lernendendatei.maxZeilenJeGruppe`, wie das neue Jahr). `frei`: Zeilen,
    /// die am Menü „Keine Gruppe“ bekamen — kein Vorschlag nimmt sie (E652).
    /// Gruppen ohne Zeile fehlen.
    static func zuteilung(_ gruppen: [Lerngruppe], namen: [String: String], uebernommen: [String: [String]],
                          zeilen: [Zeile], gewaehlt: [String: [String]], frei: Set<String> = []) -> [String: [String]] {
        let vorhanden = Set(zeilen.map(\.id))
        var ergebnis: [String: [String]] = [:]
        // Frei (E652) gilt für den Vorschlag, nicht für die Wahl von Hand.
        var gesperrt = Set<String>()
        func nehmen(_ zeile: String, fuer gruppe: String) {
            // Je Gruppe einmal, höchstens 20 (Z-AT9M-04); andere Gruppen behalten die Zeile (E670, E675).
            let eigene = ergebnis[gruppe] ?? []
            guard eigene.count < Lernendendatei.maxZeilenJeGruppe, !eigene.contains(zeile), !gesperrt.contains(zeile) else { return }
            ergebnis[gruppe, default: []].append(zeile)
        }
        var uebrige: [Lerngruppe] = []
        for g in gruppen {
            guard let folge = gewaehlt[g.id], folge.isEmpty || folge.contains(where: vorhanden.contains) else {
                uebrige.append(g)
                continue
            }
            for z in folge where vorhanden.contains(z) { nehmen(z, fuer: g.id) }
        }
        gesperrt = frei
        for g in uebrige {
            if let v = vorgabe(name: namen[g.id] ?? g.name, uebernommen: uebernommen[g.id]?.first, zeilen: zeilen) {
                nehmen(v, fuer: g.id)
            }
        }
        for g in uebrige {
            for z in (uebernommen[g.id] ?? []).dropFirst() where vorhanden.contains(z) { nehmen(z, fuer: g.id) }
        }
        for g in uebrige {
            for z in gleichnamige(namen[g.id] ?? g.name, zeilen: zeilen) { nehmen(z, fuer: g.id) }
        }
        return ergebnis
    }

    /// Wer ins neue Schuljahr mitkommt (E657): jede Gruppe, die eine Zeile trägt, dazu die, die der IServ-Import am
    /// Blatt „Neue Planung“ erkennt (`imImport`). Die übrigen bleiben mit dem Vorjahr im Archiv.
    static func mitkommend(_ zuteilung: [String: [String]], importiert: Set<String> = []) -> Set<String> {
        Set(zuteilung.filter { !$0.value.isEmpty }.keys).union(importiert)
    }

    /// Die Gruppen, deren Name im neuen Schuljahr (`namen`) eine Klasse der IServ-Datei ist (E657) — verglichen wie die
    /// Zuteilung: ohne Groß/Klein und Leerraum am Rand. Heißen mehrere Lerngruppen so, gilt keine als erkannt: Es
    /// entscheiden ihre Zeilen (Z-AT9M-11).
    static func imImport(_ gruppen: [Lerngruppe], namen: [String: String], klassen: [String]) -> Set<String> {
        let gesucht = Set(klassen.map(schluessel).filter { !$0.isEmpty })
        var je: [String: [String]] = [:]
        for g in gruppen { je[schluessel(namen[g.id] ?? g.name), default: []].append(g.id) }
        return Set(je.filter { gesucht.contains($0.key) && $0.value.count == 1 }.flatMap(\.value))
    }

    /// Die Zeile unter dem Schalter „Lerngruppen hochstufen“ (E307).
    static func stufentext(bisher: String, neu: String, stufen: Int, an: Bool) -> String {
        let wirksam = an ? max(stufen, 1) : 0
        let folge = switch wirksam {
        case 0: "die Namen bleiben"
        case 1: "eine Stufe höher"
        default: "\(wirksam) Stufen höher"
        }
        // Nach dem Doppelpunkt ist „Die Namen bleiben“ ein ganzer Satz — groß (E585, E608); nach dem Strich klein.
        return stufen == 0 ? "Beide im Schuljahr \(bisher) — \(folge)"
            : "\(bisher) → \(neu): \(wirksam == 0 ? "Die Namen bleiben" : folge)"
    }
}

// ── Der Bogen „Lerngruppen zuordnen“ (v84, E382–E386) ────────────────────
// Was der Bogen zeigt — links je Lerngruppe, rechts je Zeile der neuen
// Planung — und die Zusammenfassung neben seinem Knopf im Blatt. Gerechnet
// aus dem Zustand der Wahl, wie beide Blätter ihn führen — je Gruppe alle
// ihre Zeilen (E649, E650); mit kommt, wer eine Zeile trägt oder im Import
// erkannt ist (E657).

extension Hochstufung {

    struct Zeilenmodell: Hashable, Sendable {

        /// Links: eine aktive Lerngruppe mit Namen und Ziel im neuen Schuljahr.
        struct Gruppe: Identifiable, Hashable, Sendable {
            let id: String
            /// Kommt ins neue Schuljahr mit — sie trägt eine Zeile oder ist im Import erkannt (E657); die übrigen
            /// bleiben mit dem Vorjahr im Archiv.
            let kommtMit: Bool
            /// „bisher G6a“
            let bisher: String
            /// Was im Namensfeld steht (E308, E383).
            let name: String
            /// Der Name, den die Gruppe im neuen Schuljahr trägt — bereinigt wie beim Übernehmen, ein leeres Feld
            /// heißt der bisherige (Voreinstellung 5, Z-AT8-02). Zum Anzeigen; `name` bleibt das Feld.
            let neuerName: String
            /// Die erste Zeile, Kennung oder Schlüssel — `nil`: keine.
            let zeile: String?
            /// „→ G7a · Informatik“ oder „→ keine Zeile“ — die erste Zeile
            let ziel: String
            /// Die Titel der weiteren Zeilen der Gruppe, nach der ersten in ihrer Folge (E649).
            var weitere: [String] = []
        }

        /// Rechts: eine Zeile der neuen Planung und die Lerngruppen daran — eine Zeile kann mehrere tragen (E670).
        struct Belegung: Identifiable, Hashable, Sendable {
            let id: String
            let titel: String
            /// Die Lerngruppen an der Zeile, wer mitkommt zuerst — leer: keine.
            let gruppen: [String]
            /// „← G6a“, bei mehreren „← G6a, Bio-AG“ — ohne Gruppe `nil`.
            let traeger: String?
            /// Eine Lerngruppe an der Zeile kommt mit (E657).
            let kommtMit: Bool
            /// Die Zeile ist für keine ihrer Lerngruppen die erste (E649).
            var weitere = false
        }

        /// Wer mitkommt zuerst, die übrigen dahinter — je in der Folge der Listen (`Lerngruppe.vorgehen`).
        let links: [Gruppe]
        /// In der Folge des Zeilenangebots.
        let rechts: [Belegung]

        /// Alle aktiven Gruppen und die davon mit wenigstens einer Zeile.
        var gesamt: Int { links.count }
        var zugeordnet: Int { links.filter { $0.zeile != nil }.count }
        var zusammenfassung: String { Hochstufung.zusammenfassung(zugeordnet, von: gesamt) }
    }

    /// Das Zeilenmodell aus dem Zustand der Wahl: `mitkommend` wer mitkommt
    /// (`mitkommend(…)`, E657), `namen` was in den Namensfeldern steht,
    /// `zuteilung` die Zeilen je Gruppe (aus `zuteilung(…)`; eine Zeile kann
    /// mehrere Gruppen tragen, E670; die Bindungen aus dem Vorjahr stehen darin, E650).
    /// Eine Zeile, die `zeilen` nicht anbietet, zählt als keine — wie beim
    /// Übernehmen.
    static func zeilenmodell(_ gruppen: [Lerngruppe], mitkommend: Set<String>, namen: [String: String],
                             zeilen: [Zeile], zuteilung zeilenfolgen: [String: [String]]) -> Zeilenmodell {
        let aktiv = gruppen.filter { $0.archiviert.isEmpty }.sorted(by: Lerngruppe.vorgehen)
        let folge = aktiv.filter { mitkommend.contains($0.id) } + aktiv.filter { !mitkommend.contains($0.id) }
        let angebot = Dictionary(zeilen.map { ($0.id, $0) }, uniquingKeysWith: { erste, _ in erste })
        // Je Gruppe ihre Zeilen, die das Angebot kennt — eine unbekannte zählt als keine, wie beim Übernehmen.
        let eigene = Dictionary(uniqueKeysWithValues: folge.map { g in
            (g.id, (zeilenfolgen[g.id] ?? []).compactMap { angebot[$0] })
        })
        let links = folge.map { g in
            let zeile = eigene[g.id]?.first
            let feld = namen[g.id] ?? g.name
            // Wie `neuesJahr` (Archiv.swift): Bereinigt, ein leeres Feld heißt der bisherige Name.
            let sauber = Lernendenbestand.zeile(feld, Planungsdatei.maxNamenslaenge)
            return Zeilenmodell.Gruppe(
                id: g.id, kommtMit: mitkommend.contains(g.id), bisher: "bisher " + g.beschriftung,
                name: feld, neuerName: sauber.isEmpty ? g.name : sauber,
                zeile: zeile?.id, ziel: "→ " + (zeile?.titel ?? "keine Zeile"),
                weitere: (eigene[g.id] ?? []).dropFirst().map(\.titel))
        }
        let rechts = zeilen.map { z in
            // Die Lerngruppen an der Zeile — wer mitkommt zuerst (E670).
            let an = folge.filter { eigene[$0.id]?.contains { $0.id == z.id } == true }
            guard !an.isEmpty else {
                return Zeilenmodell.Belegung(id: z.id, titel: z.titel, gruppen: [], traeger: nil, kommtMit: false)
            }
            return Zeilenmodell.Belegung(id: z.id, titel: z.titel, gruppen: an.map(\.id),
                                         traeger: "← " + an.map(\.beschriftung).joined(separator: ", "),
                                         kommtMit: an.contains { mitkommend.contains($0.id) },
                                         weitere: an.allSatisfy { eigene[$0.id]?.first?.id != z.id })
        }
        return Zeilenmodell(links: links, rechts: rechts)
    }

    /// Neben dem Knopf „Lerngruppen zuordnen …“: „3 von 4 Lerngruppen
    /// zugeordnet“ — der Plural folgt der Zahl aller aktiven (`gesamt`).
    static func zusammenfassung(_ zugeordnet: Int, von gesamt: Int) -> String {
        guard zugeordnet > 0 else { return "keine Lerngruppe zugeordnet" }
        return "\(zugeordnet) von \(gesamt) " + (gesamt == 1 ? "Lerngruppe" : "Lerngruppen") + " zugeordnet"
    }
}
