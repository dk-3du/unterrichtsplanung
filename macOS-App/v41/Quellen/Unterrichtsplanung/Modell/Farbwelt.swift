// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Ein Ton der Palette. `dl`/`ds` verschieben Helligkeit und Sättigung in
/// Prozentpunkten (im CSS `--kurs-dl`/`--kurs-ds`) und tragen die
/// Helligkeitsstufe bereits in sich.
struct Farbton: Sendable, Hashable {
    /// Stelle in der flachen Liste — zugleich der gespeicherte Farbwert.
    let stelle: Int
    /// „blau-mittel“ — so steht eine Fachfarbe in der Datei.
    let schluessel: String
    let grundfarbe: String
    let stufe: String
    let h: Double
    let dl: Double
    let ds: Double
    /// „Blau · mittel“
    let name: String
}

/// `dl`/`ds` gleichen aus, dass Limette heller wirkt als Blau.
struct Grundfarbe: Sendable, Hashable {
    let schluessel: String
    let name: String
    let h: Double
    let dl: Double
    let ds: Double
}

struct Helligkeitsstufe: Sendable, Hashable {
    let schluessel: String
    let name: String
    let dl: Double
}

/// Eine Zeile der Farbwahl: alle Grundfarben in einer Helligkeitsstufe.
struct Farbzeile: Identifiable, Sendable, Hashable {
    let stufe: Helligkeitsstufe
    let toene: [Farbton]

    var id: String { stufe.schluessel }
}

/// Farblogik der Planung: **eine Farbe je Fach, frei zugewiesen.** Acht
/// Grundfarben im Abstand von 45 Grad, jede in drei Helligkeitsstufen.
enum Farbwelt {

    // ── Grundwerte ────────────────────────────────────────────────────────
    // Gleichlauf mit `--s-basis`/`--l-basis` im CSS der Ansichtsfassung.

    static let saettigungHell: Double = 50
    static let helligkeitHell: Double = 50
    static let saettigungDunkel: Double = 48
    static let helligkeitDunkel: Double = 64

    // ── Palette ───────────────────────────────────────────────────────────

    static let grundfarben: [Grundfarbe] = [
        Grundfarbe(schluessel: "rot",     name: "Rot",     h: 355, dl:  0, ds: 0),
        Grundfarbe(schluessel: "orange",  name: "Orange",  h:  40, dl: -3, ds: 8),
        Grundfarbe(schluessel: "limette", name: "Limette", h:  85, dl: -6, ds: 5),
        Grundfarbe(schluessel: "gruen",   name: "Grün",    h: 130, dl: -3, ds: 0),
        Grundfarbe(schluessel: "tuerkis", name: "Türkis",  h: 175, dl: -3, ds: 8),
        Grundfarbe(schluessel: "blau",    name: "Blau",    h: 220, dl:  2, ds: 0),
        Grundfarbe(schluessel: "violett", name: "Violett", h: 265, dl:  5, ds: 0),
        Grundfarbe(schluessel: "magenta", name: "Magenta", h: 310, dl:  2, ds: 0),
    ]

    /// **Mittel zuerst:** Die Reihenfolge der flachen Liste ist zugleich die,
    /// in der freie Farben vergeben werden — sonst bekämen die ersten drei
    /// Fächer drei kaum unterscheidbare Rottöne.
    static let stufen: [Helligkeitsstufe] = [
        Helligkeitsstufe(schluessel: "mittel", name: "mittel", dl:   0),
        Helligkeitsstufe(schluessel: "hell",   name: "hell",   dl:  12),
        Helligkeitsstufe(schluessel: "dunkel", name: "dunkel", dl: -15),
    ]

    /// Die Reihenfolge darf sich nie ändern: Gespeichert wird die Stelle.
    static let toene: [Farbton] = {
        var laufend = 0
        return stufen.flatMap { stufe in
            grundfarben.map { grund in
                defer { laufend += 1 }
                return Farbton(stelle: laufend,
                               schluessel: grund.schluessel + "-" + stufe.schluessel,
                               grundfarbe: grund.schluessel,
                               stufe: stufe.schluessel,
                               h: grund.h,
                               dl: grund.dl + stufe.dl,
                               ds: grund.ds,
                               name: grund.name + " · " + stufe.name)
            }
        }
    }()

    static let tonNachSchluessel: [String: Farbton] =
        Dictionary(uniqueKeysWithValues: toene.map { ($0.schluessel, $0) })

    /// Für die Farbwahl: von hell nach dunkel. Abgeleitet und nicht aufgezählt,
    /// damit keine Stufe stillschweigend aus dem Raster fällt.
    static let anzeigezeilen: [Farbzeile] = stufen.sorted { $0.dl > $1.dl }.map { stufe in
        Farbzeile(stufe: stufe, toene: toene.filter { $0.stufe == stufe.schluessel })
    }

    static func ton(_ index: Int) -> Farbton {
        toene.indices.contains(index) ? toene[index] : toene[0]
    }

    static func stelle(_ schluessel: String) -> Int? {
        tonNachSchluessel[schluessel]?.stelle
    }

    static func istGueltig(_ index: Int) -> Bool { toene.indices.contains(index) }

    /// Steht für „noch keine Farbe“, bis eine vergeben ist.
    static let ohneFarbe = -1

    // ── Zuordnung ─────────────────────────────────────────────────────────

    static func fachSchluessel(_ fach: String) -> String {
        fach.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Die erste Farbe, die noch niemand trägt. Ist die Palette erschöpft, die
    /// am seltensten benutzte: Sonst bekäme alles ab der 25. Zeile dasselbe Rot.
    /// `nutzung` zählt je Stelle, wie oft sie vorkommt (`Planung.farbnutzung`).
    static func naechsteFreieFarbe(_ nutzung: [Int: Int]) -> Int {
        var beste = 0
        var wenigste = Int.max
        for ton in toene {
            let zahl = nutzung[ton.stelle] ?? 0
            if zahl == 0 { return ton.stelle }
            if zahl < wenigste {
                wenigste = zahl
                beste = ton.stelle
            }
        }
        return beste
    }
}

/// Hülle um `NSRegularExpression`, damit die Muster einmal übersetzt werden.
/// Der Typ ist nebenläufig benutzbar, aber nicht `Sendable` — daher ungeprüft.
struct Muster: @unchecked Sendable {
    private let ausdruck: NSRegularExpression?

    init(_ pattern: String, ohneGrossKlein: Bool = false) {
        ausdruck = try? NSRegularExpression(
            pattern: pattern, options: ohneGrossKlein ? [.caseInsensitive] : [])
    }

    func trifft(_ text: String) -> Bool {
        guard let ausdruck else { return false }
        return ausdruck.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
