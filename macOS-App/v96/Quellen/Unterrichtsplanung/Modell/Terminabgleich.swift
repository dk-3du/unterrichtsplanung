// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Termin ↔ Vorhaben (v80, E291, E293) ───────────────────────────────────
//
// Ein Termin der Lernendenverwaltung kann ein Vorhaben in der Planung haben.
// Das Vorhaben trägt nur die Kennung des Termins (`Vorhaben.termin`), nie
// einen Namen; der Termin den Rückverweis auf sein Vorhaben. Tag, Uhrzeit,
// Titel und Stand („stattgefunden“ ↔ Haken „Durchgeführt“) laufen in beide
// Richtungen synchron: Was in der Planung geändert wird, zieht der Termin nach
// (`ausPlanung`); was im Blatt „Lernende“ geändert wird, zieht beim
// „Übernehmen“ das Vorhaben nach (`inPlanung`). Gelöscht gehen immer beide.
// Reines Modell ohne AppKit.

enum Terminabgleich {

    /// Die Spalte eines Tags in der Planung — `nil` außerhalb.
    static func woche(von tag: Tag, in planung: Planung) -> Int? {
        let tage = planung.start.montagDerWoche.tageBis(tag)
        guard tage >= 0, tage / 7 < planung.wochen else { return nil }
        return tage / 7
    }

    /// Die Zeile, die der Bogen vorschlägt (E291): die Klassenleitung, deren
    /// Lerngruppe die Person führt — sonst „Weiteres“; gibt es beides nicht, keine.
    static func vorbelegteZeile(fuer person: String, planung: Planung, bestand: Lernendenbestand) -> String? {
        let leitung = planung.klassen.first { k in
            k.art == .klassenleitung && bestand.lerngruppen.contains {
                $0.archiviert.isEmpty && $0.mitglieder.contains(person)
                    && $0.zeilen.contains(Zeilenbindung(planung: planung.erstellt, klasseId: k.id))
            }
        }
        return (leitung ?? planung.klassen.first { $0.art == .weiteres })?.id
    }

    /// Termin-Kennung → Vorhaben: die Verbindungen dieser Planung.
    static func verbunden(_ planung: Planung) -> [String: Vorhaben] {
        var aus: [String: Vorhaben] = [:]
        for v in planung.eintraege where v.istTermin && aus[v.termin] == nil { aus[v.termin] = v }
        return aus
    }

    /// Der Tag eines Zeitstempels als ISO-Tag — für den Stand, den ein Haken setzt.
    private static func tag(aus jetzt: String) -> String {
        Zeitrechnung.zeitpunkt(aus: jetzt).map { Tag($0).iso } ?? Tag.heute.iso
    }

    // ── Planung → Jahresdatei ─────────────────────────────────────────────

    /// Ob alle Betroffenen eines Termins „stattgefunden“ haben — so steht der
    /// Haken seines Vorhabens (E293); ohne Betroffene nie.
    static func stattgefunden(_ a: Anliegen, _ verzeichnis: Lernendenverzeichnis) -> Bool {
        !a.betroffene.isEmpty && a.betroffene.allSatisfy { verzeichnis.stand(a.id, $0) == .erledigt }
    }

    /// Jeder Termin mit Vorhaben in dieser Planung folgt ihm: Tag, Uhrzeit,
    /// Titel, Rückverweis. Vom Haken wirkt nur sein Wechsel (E298): Stimmt er
    /// mit „alle stattgefunden“ überein, bleiben die Stände, auch gemischte.
    /// Weicht er ab, hat die Planung ihn gesetzt — dann haben alle
    /// stattgefunden — oder genommen — dann wird „stattgefunden“ wieder
    /// „offen“ („abgesagt“ bleibt). Eine Jahresdatei einer anderen Planung bleibt unberührt.
    static func ausPlanung(_ planung: Planung, _ bestand: Lernendenbestand, jetzt: String) -> Lernendenbestand {
        guard bestand.planung == planung.erstellt else { return bestand }
        let verbunden = verbunden(planung)
        guard !verbunden.isEmpty else { return bestand }
        var neu = bestand
        for stelle in neu.anliegen.indices {
            let alt = neu.anliegen[stelle]
            guard alt.art == .termin, let v = verbunden[alt.id] else { continue }
            var a = alt
            if let tag = v.datum { a.datum = tag.iso }
            a.uhrzeit = v.terminzeit
            let titel = Lernendenbestand.zeile(v.titel, Lernendendatei.maxTitel)
            if !titel.isEmpty { a.titel = titel }
            a.planung = planung.erstellt
            a.vorhaben = v.id
            if a != alt {
                a.geaendert = jetzt
                neu.anliegen[stelle] = a
            }
            guard v.erledigt != stattgefunden(a, Lernendenverzeichnis(neu)) else { continue }
            neu = mitHaken(v.erledigt, a, neu, jetzt: jetzt)
        }
        if neu != bestand { neu.geaendert = jetzt }
        return neu
    }

    /// Was ein Haken an einem Termin bewirkt (E298): Gesetzt haben alle
    /// stattgefunden, genommen wird „stattgefunden“ wieder „offen“
    /// („abgesagt“ bleibt). Die Notizen bleiben.
    static func mitHaken(_ erledigt: Bool, _ a: Anliegen, _ bestand: Lernendenbestand, jetzt: String) -> Lernendenbestand {
        var neu = bestand
        let verzeichnis = Lernendenverzeichnis(bestand)
        for person in a.betroffene {
            let rueck = verzeichnis.rueckmeldung(a.id, person)
            let stand = rueck?.stand ?? .offen
            if erledigt, stand != .erledigt {
                neu = neu.mitRuecklauf(a.id, person, stand: .erledigt, datum: tag(aus: jetzt), notiz: rueck?.notiz ?? "",
                                       jetzt: jetzt)
            } else if !erledigt, stand == .erledigt {
                neu = neu.mitRuecklauf(a.id, person, stand: .offen, datum: "", notiz: rueck?.notiz ?? "", jetzt: jetzt)
            }
        }
        return neu
    }

    /// Termine mit Rückverweis auf diese Planung, deren Vorhaben fehlt oder
    /// nicht mehr auf sie zeigt — etwa nach einer Bearbeitung ohne offene Verwaltung.
    static func verwaiste(_ planung: Planung, _ bestand: Lernendenbestand) -> [String] {
        guard bestand.planung == planung.erstellt else { return [] }
        let verbunden = verbunden(planung)
        return bestand.anliegen.filter { a in
            a.art == .termin && a.planung == planung.erstellt && !a.vorhaben.isEmpty && verbunden[a.id]?.id != a.vorhaben
        }.map(\.id)
    }

    /// Den Rückverweis lösen — der Termin bleibt.
    static func ohneRueckverweis(_ ids: [String], _ bestand: Lernendenbestand) -> Lernendenbestand {
        guard !ids.isEmpty else { return bestand }
        let menge = Set(ids)
        var neu = bestand
        for stelle in neu.anliegen.indices where menge.contains(neu.anliegen[stelle].id) {
            neu.anliegen[stelle].planung = ""
            neu.anliegen[stelle].vorhaben = ""
        }
        return neu
    }

    // ── Jahresdatei → Planung (beim „Übernehmen“ des Blatts) ─────────────

    struct Uebertrag: Equatable, Sendable {
        var planung: Planung
        /// Die Jahresdatei mit den Rückverweisen neuer Vorhaben.
        var bestand: Lernendenbestand
        /// Termine, die im Blatt gelöscht wurden und ihr Vorhaben mitnahmen.
        var entfernt: [String]
        /// Termine, deren Tag außerhalb der Planung liegt — ohne neues Vorhaben
        /// bzw. mit dem Tag ihres bestehenden Vorhabens.
        var ausserhalb: Int
    }

    /// Was das Blatt zwischen `vorher` und `nachher` an Terminen geändert hat,
    /// in der Planung: Gelöschte nehmen ihr Vorhaben mit; Verbundene ziehen ihr
    /// Vorhaben nach (Tag samt Woche, Uhrzeit, Titel, Haken); neue Termine mit
    /// Wunsch (Kennung → Zeile) bekommen ihr Vorhaben.
    static func inPlanung(_ planung: Planung, vorher: Lernendenbestand, nachher: Lernendenbestand,
                          wuensche: [String: String], jetzt: String) -> Uebertrag {
        var p = planung
        var b = nachher
        var entfernt: [String] = []
        var ausserhalb = 0
        guard nachher.planung == planung.erstellt else {
            return Uebertrag(planung: planung, bestand: nachher, entfernt: [], ausserhalb: 0)
        }
        let bleiben = Set(nachher.anliegen.map(\.id))
        for a in vorher.anliegen where a.art == .termin && !bleiben.contains(a.id) && p.eintraege.contains(where: { $0.termin == a.id }) {
            p.eintraege.removeAll { $0.termin == a.id }
            entfernt.append(a.id)
        }
        let verzeichnis = Lernendenverzeichnis(nachher)
        var belegt = Set(p.eintraege.map(\.id))
        for stelle in b.anliegen.indices where b.anliegen[stelle].art == .termin {
            let a = b.anliegen[stelle]
            let stattgefunden = Self.stattgefunden(a, verzeichnis)
            if let i = p.eintraege.firstIndex(where: { $0.termin == a.id }) {
                var v = p.eintraege[i]
                if let tag = Tag(iso: a.datum), tag != v.datum {
                    if let woche = woche(von: tag, in: p) {
                        v.woche = woche
                        v.datum = tag
                    } else {
                        // Außerhalb der Planung behält der Termin den Tag seines
                        // Vorhabens — sonst nähme ihn der nächste Abgleich still zurück (W1-03).
                        ausserhalb += 1
                        if let alt = v.datum { b.anliegen[stelle].datum = alt.iso }
                    }
                }
                v.terminzeit = a.uhrzeit
                v.titel = a.titel
                // Ohne Betroffene (nur nach bereinigtem Lesen) gibt es keinen Stand, dem der Haken folgen könnte (Z14a-06).
                if !a.betroffene.isEmpty, v.erledigt != stattgefunden {
                    v.erledigt = stattgefunden
                    v.statusGeaendert = jetzt
                }
                if v != p.eintraege[i] { p.eintraege[i] = v }
                b.anliegen[stelle].planung = planung.erstellt
                b.anliegen[stelle].vorhaben = v.id
            } else if let zeile = wuensche[a.id], a.vorhaben.isEmpty, p.klassen.contains(where: { $0.id == zeile }) {
                guard let tag = Tag(iso: a.datum), let woche = woche(von: tag, in: p) else {
                    ausserhalb += 1
                    continue
                }
                var id = Kennung.neu("e")
                while belegt.contains(id) { id = Kennung.neu("e") }
                belegt.insert(id)
                p.eintraege.append(Vorhaben(
                    id: id, klasseId: zeile, woche: woche, titel: a.titel, text: "", erledigt: stattgefunden,
                    materialien: [], links: [], datum: tag, statusGeaendert: stattgefunden ? jetzt : "",
                    termin: a.id, terminzeit: a.uhrzeit))
                b.anliegen[stelle].planung = planung.erstellt
                b.anliegen[stelle].vorhaben = id
            }
        }
        return Uebertrag(planung: p, bestand: b, entfernt: entfernt, ausserhalb: ausserhalb)
    }

    /// Was das Blatt an Terminen nicht anfasste, hat den Stand der Sitzung —
    /// ein Haken vom iPad oder ein Nachführen aus der Planung, während das
    /// Blatt offen war, bleibt (offener Punkt 3). Angefasst oder gelöscht gilt
    /// das Blatt; ein Termin, der in der Sitzung inzwischen erschien, bleibt.
    static func mitStandDerSitzung(_ entwurf: Lernendenbestand, ausgang: Lernendenbestand,
                                   sitzung: Lernendenbestand) -> Lernendenbestand {
        func termin(_ b: Lernendenbestand, _ id: String) -> Anliegen? {
            b.anliegen.first { $0.id == id && $0.art == .termin }
        }
        func rueck(_ b: Lernendenbestand, _ id: String) -> [Rueckmeldung] { b.rueckmeldungen.filter { $0.anliegen == id } }
        // Nur Personen, die das Blatt behält — sonst trüge die Datei Verweise ins Leere.
        let personen = Set(entwurf.lernende.map(\.id))
        func behalten(_ a: Anliegen) -> Anliegen? {
            var a = a
            a.betroffene = a.betroffene.filter(personen.contains)
            return a.betroffene.isEmpty ? nil : a
        }
        var neu = entwurf
        for alt in ausgang.anliegen where alt.art == .termin {
            // Eine im Blatt gelöschte Person fasst den Termin nicht an — verglichen wird ohne sie (Z14c-06).
            var ohneGeloeschte = alt
            ohneGeloeschte.betroffene = alt.betroffene.filter(personen.contains)
            guard termin(entwurf, alt.id) == ohneGeloeschte,
                  rueck(entwurf, alt.id) == rueck(ausgang, alt.id).filter({ personen.contains($0.lernender) }),
                  let stelle = neu.anliegen.firstIndex(where: { $0.id == alt.id }) else { continue }
            neu.rueckmeldungen.removeAll { $0.anliegen == alt.id }
            if let jetzig = termin(sitzung, alt.id).flatMap(behalten) {
                neu.anliegen[stelle] = jetzig
                neu.rueckmeldungen += rueck(sitzung, alt.id).filter { jetzig.betroffene.contains($0.lernender) }
            } else {
                neu.anliegen.remove(at: stelle)
            }
        }
        for erschienen in sitzung.anliegen where erschienen.art == .termin
            && termin(ausgang, erschienen.id) == nil && termin(entwurf, erschienen.id) == nil {
            // Über der Grenze der Anliegen ließe sich die Jahresdatei nicht schreiben (W1-02).
            guard neu.anliegen.count < Lernendendatei.maxAnliegen, let jetzig = behalten(erschienen) else { continue }
            neu.anliegen.append(jetzig)
            neu.rueckmeldungen += rueck(sitzung, jetzig.id).filter { jetzig.betroffene.contains($0.lernender) }
        }
        return neu
    }

    // ── Zwischen zwei Ständen derselben Planung ───────────────────────────

    /// Termin-Kennungen, deren Vorhaben zwischen `alt` und `neu` verschwand.
    static func verschwunden(von alt: Planung, zu neu: Planung) -> Set<String> {
        guard alt.erstellt == neu.erstellt else { return [] }
        return Set(verbunden(alt).keys).subtracting(verbunden(neu).keys)
    }

    /// Termin-Kennungen, deren Vorhaben zwischen `alt` und `neu` erschien.
    static func erschienen(von alt: Planung, zu neu: Planung) -> Set<String> {
        guard alt.erstellt == neu.erstellt else { return [] }
        return Set(verbunden(neu).keys).subtracting(verbunden(alt).keys)
    }
}
