// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Warum ein Vorhaben auf der Tagesliste steht. `woche` heißt: kein Tag
/// gesetzt, es gehört in die laufende Woche.
enum Tagesgrund: Sendable, Hashable {
    case datum
    case pruefung
    case beides
    case woche

    var beschriftung: String {
        switch self {
        case .datum: "für heute datiert"
        case .pruefung: "Prüfung heute"
        case .beides: "für heute datiert · Prüfung heute"
        case .woche: "ohne festen Tag"
        }
    }

    var amTag: Bool { self != .woche }

    /// Nur dann heißt die Marke „Prüfung heute“: Ein als Prüfung geführtes
    /// Vorhaben ohne Termin steht wegen seiner Woche auf der Liste.
    var pruefungHeute: Bool { self == .pruefung || self == .beides }
}

/// Ein Posten der Tagesliste — ein Vorhaben samt seinem Kurs.
struct Tagesposten: Identifiable, Hashable, Sendable {
    let vorhaben: Vorhaben
    let klasse: Klasse
    let grund: Tagesgrund

    var id: String { vorhaben.id }

    /// Steht das Vorhaben in einer anderen Woche als dem Tag der Liste?
    ///
    /// Erlaubt, aber meist ein Vertippen. Gefragt wird nach der Angabe, die den
    /// Posten auf die Liste gebracht hat.
    func ausserhalbSeinerWoche(start: Tag) -> Bool {
        switch grund {
        case .datum: vorhaben.datumAusserhalb(start: start)
        case .pruefung: vorhaben.terminAusserhalb(start: start)
        case .beides: vorhaben.datumAusserhalb(start: start)
                   || vorhaben.terminAusserhalb(start: start)
        case .woche: false
        }
    }
}

struct Tagesliste: Sendable {
    var tag: Tag = .heute
    /// Vorhaben, deren Tag genau dieser Tag ist.
    var amTag: [Tagesposten] = []
    /// Vorhaben ohne eigenen Tag, die in der laufenden Woche stehen.
    var inDerWoche: [Tagesposten] = []
    /// Die laufende Woche — `nil`, wenn der Tag außerhalb des Zeitraums liegt.
    var woche: Woche?
    var lage: Wochenlage = .unterricht
    /// Der Name des Ferienzeitraums, in den DER TAG fällt (nicht die Woche).
    var ferientag: String?

    var alle: [Tagesposten] { amTag + inDerWoche }
    var anzahl: Int { amTag.count + inDerWoche.count }
    /// Ohne den Umweg über `alle` — das spart die Kopie beider Gruppen.
    var erledigt: Int {
        amTag.count(where: \.vorhaben.erledigt) + inDerWoche.count(where: \.vorhaben.erledigt)
    }
    var offen: Int { anzahl - erledigt }
    var istLeer: Bool { anzahl == 0 }
}

extension Planung {

    /// Was an einem Tag ansteht — in zwei Gruppen.
    ///
    /// **Die zweite Gruppe ist keine Notlösung:** Ohne sie bliebe die Liste bei
    /// einer Planung ohne Datumsangaben immer leer. **Wessen Tag bekannt ist
    /// und nicht heute, steht nicht darauf.** Geordnet wird wie im Raster.
    func tagesliste(am tag: Tag = .heute) -> Tagesliste {
        var liste = Tagesliste(tag: tag)
        let woche = wochenListe.first { $0.montag == tag.montagDerWoche }
        liste.woche = woche
        if let woche { liste.lage = lage(woche) }
        liste.ferientag = ferien.first { !$0.ungueltig && $0.von <= tag && tag <= $0.bis }?.name

        // Ganz unterrichtsfreie Woche: keine Wochengruppe, aber für heute Datiertes bleibt.
        let wochengruppe: Woche? = liste.lage.frei ? nil : woche

        var kurse: [String: (platz: Int, klasse: Klasse)] = [:]
        for (platz, klasse) in klassen.enumerated() {
            kurse[klasse.id] = (platz, klasse)
        }

        var amTag: [(platz: Int, stelle: Int, posten: Tagesposten)] = []
        var inDerWoche: [(platz: Int, stelle: Int, posten: Tagesposten)] = []

        for (stelle, eintrag) in eintraege.enumerated() {
            guard let kurs = kurse[eintrag.klasseId] else { continue }

            let datiert = eintrag.datum == tag
            let geprueft = eintrag.pruefung && eintrag.pruefungstag == tag
            if datiert || geprueft {
                let grund: Tagesgrund = datiert && geprueft ? .beides : (datiert ? .datum : .pruefung)
                amTag.append((kurs.platz, stelle,
                              Tagesposten(vorhaben: eintrag, klasse: kurs.klasse, grund: grund)))
                continue
            }

            guard let wochengruppe, eintrag.woche == wochengruppe.nummer else { continue }
            guard eintrag.datum == nil, !(eintrag.pruefung && eintrag.pruefungstag != nil)
            else { continue }
            guard !istZelleFrei(klasse: eintrag.klasseId, woche: wochengruppe) else { continue }
            inDerWoche.append((kurs.platz, stelle,
                               Tagesposten(vorhaben: eintrag, klasse: kurs.klasse, grund: .woche)))
        }

        liste.amTag = ordnen(amTag)
        liste.inDerWoche = ordnen(inDerWoche)
        return liste
    }

    private func ordnen(_ roh: [(platz: Int, stelle: Int, posten: Tagesposten)]) -> [Tagesposten] {
        roh.sorted { ($0.platz, $0.stelle) < ($1.platz, $1.stelle) }.map(\.posten)
    }
}
