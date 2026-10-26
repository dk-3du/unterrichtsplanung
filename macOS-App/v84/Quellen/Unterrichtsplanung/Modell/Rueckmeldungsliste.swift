// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Listen zum Setzen: die Rückmeldungsliste (v84, AT16) ──────────────────
//
// Je Lerngruppe eine Tabelle — Personen als Zeilen, Mitteilungen als Spalten,
// in den Zellen der Stand (E402). Die Tabelle entsteht als `Liste`, der
// allgemeinen Form, die `Listensatz` aufs Papier bringt; 2.2.0 setzt darin
// die Spalten der Leistungen ein (E412). Reines Modell ohne AppKit —
// `abzug_pruefen.py` übersetzt es allein.

/// Eine Liste zum Setzen (E412): Kopf, Namensspalte, weitere Spalten, Zeilen
/// mit Zellen als fertigem Text, Legende, Anhang. Der Listensatz deutet
/// nichts — was hier steht, steht so auf dem Papier.
struct Liste: Hashable, Sendable {
    struct Spalte: Hashable, Sendable {
        var titel: String
        /// Die zweite Zeile im Spaltenkopf, etwa der Tag — oder leer.
        var unterzeile: String = ""
    }

    struct Zeile: Hashable, Sendable {
        var name: String
        /// Je Spalte ein Text, in der Folge der Spalten; was fehlt, bleibt leer.
        var zellen: [String]
        /// Eine Zwischenzeile über die ganze Breite, ohne Zellen — `name` ist ihr Text (E484).
        var trenner = false
    }

    struct Legendeneintrag: Hashable, Sendable {
        var zeichen: String
        var bedeutung: String
    }

    /// Ein Abschnitt des Anhangs — etwa die Notizen zu einer Mitteilung.
    struct Abschnitt: Hashable, Sendable {
        var ueberschrift: String
        var eintraege: [Eintrag]
    }

    struct Eintrag: Hashable, Sendable {
        var name: String
        var text: String
    }

    /// Die Teile der Kopfzeile, auf jeder Seite (E411).
    var kopf: [String]
    /// Der Kopf der Namensspalte.
    var namensspalte: String
    var spalten: [Spalte]
    var zeilen: [Zeile]
    var legende: [Legendeneintrag]
    /// Ohne Abschnitte kein Anhang (E409).
    var anhangstitel: String = ""
    var anhang: [Abschnitt] = []
}

/// Die Rückmeldungsliste einer Lerngruppe (E402): die aktiven Mitglieder nach
/// Nachname und Vorname, der Rufname in Klammern (E410) — darunter, nach einer
/// Zwischenzeile, wer betroffen, aber nicht mehr Mitglied ist (E484); die gewählten
/// Mitteilungen der Gruppe als Spalten, je mit allen Rückläufen — nichts wird
/// nach offen oder erledigt ausgesiebt (E408); in den Zellen der Stand als
/// Zeichen, die Notizen im Anhang (E409). Ohne Rücklauf gilt `offen` (E272).
enum Rueckmeldungsliste {
    /// Die Zeichen der Stände — Vorlage zur Sichtprüfung, nicht entschieden.
    static func zeichen(_ stand: Rueckmeldestand) -> String {
        switch stand {
        case .offen: "\u{25CB}"
        case .erledigt: "\u{2713}"
        case .abgelehnt: "\u{2717}"
        }
    }

    /// Wie im Blatt: Wer nicht betroffen ist, bekommt einen Strich.
    static let nichtBetroffen = "\u{2014}"
    /// Hinter dem Zeichen: Zu diesem Rücklauf steht eine Notiz im Anhang.
    static let mitNotiz = "*"
    /// Die Zwischenzeile über denen, die betroffen, aber nicht mehr Mitglied sind (E484) — Vorlage zur Sichtprüfung.
    static let nichtMehrMitglied = "nicht mehr in der Lerngruppe"

    /// Die Liste — `nil`, wenn die Gruppe fehlt oder keine der gewählten
    /// Kennungen eine Mitteilung dieser Gruppe ist. Die Spalten stehen in der
    /// Folge des Blatts, gleich in welcher Folge gewählt wurde; `stand` ist der
    /// Tag im Kopf (E411).
    static func liste(_ bestand: Lernendenbestand, gruppe id: String, mitteilungen gewaehlt: Set<String>,
                      stand: Tag) -> Liste? {
        let verzeichnis = Lernendenverzeichnis(bestand)
        guard let gruppe = verzeichnis.gruppe(id) else { return nil }
        let mitteilungen = verzeichnis.mitteilungen(der: gruppe.id).filter { gewaehlt.contains($0.id) }
        guard !mitteilungen.isEmpty else { return nil }
        let personen = verzeichnis.mitglieder(gruppe.id)
        // Wer betroffen ist, aber nicht mehr Mitglied (Umzug, E366/E367), steht unten, damit alle Rückläufe
        // mitkommen (E408, E484); archivierte bleiben draußen wie bei den Mitgliedern (E410).
        let mitglieder = Set(personen.map(\.id))
        let ehemalige = verzeichnis.alle.filter { p in
            !mitglieder.contains(p.id) && mitteilungen.contains { $0.betroffene.contains(p.id) }
        }

        var notizen: [String: [Liste.Eintrag]] = [:]
        func zeile(_ p: Lernender) -> Liste.Zeile {
            Liste.Zeile(name: name(p), zellen: mitteilungen.map { m in
                guard m.betroffene.contains(p.id) else { return nichtBetroffen }
                guard let rueck = verzeichnis.rueckmeldung(m.id, p.id) else { return zeichen(.offen) }
                guard !rueck.notiz.isEmpty else { return zeichen(rueck.stand) }
                notizen[m.id, default: []].append(Liste.Eintrag(name: name(p), text: notiztext(rueck)))
                return zeichen(rueck.stand) + mitNotiz
            })
        }
        var zeilen = personen.map(zeile)
        if !ehemalige.isEmpty {
            zeilen.append(Liste.Zeile(name: nichtMehrMitglied, zellen: [], trenner: true))
            zeilen += ehemalige.map(zeile)
        }
        let anhang = mitteilungen.compactMap { m in
            notizen[m.id].map { Liste.Abschnitt(ueberschrift: ([m.titel] + tag(m.datum)).joined(separator: " · "),
                                                eintraege: $0) }
        }

        var legende = Rueckmeldestand.allCases.map {
            Liste.Legendeneintrag(zeichen: zeichen($0), bedeutung: $0.beschriftung(fuer: .mitteilung))
        }
        legende.append(Liste.Legendeneintrag(zeichen: nichtBetroffen, bedeutung: "nicht betroffen"))
        if !anhang.isEmpty { legende.append(Liste.Legendeneintrag(zeichen: mitNotiz, bedeutung: "Notiz im Anhang")) }

        let kopf = [gruppe.name, "Rückmeldungsliste",
                    bestand.schuljahr.isEmpty ? "" : "Schuljahr " + bestand.schuljahr,
                    "Stand " + stand.deutsch].filter { !$0.isEmpty }
        return Liste(kopf: kopf, namensspalte: "Name",
                     spalten: mitteilungen.map { Liste.Spalte(titel: $0.titel, unterzeile: tag($0.datum).first ?? "") },
                     zeilen: zeilen, legende: legende, anhangstitel: "Notizen", anhang: anhang)
    }

    /// „Abel, Anna (Anni)“ — der Rufname in Klammern, wo gesetzt (E410).
    static func name(_ person: Lernender) -> String {
        person.rufname.isEmpty ? person.anzeigename : "\(person.anzeigename) (\(person.rufname))"
    }

    /// „erledigt, 02.09.2026: ‹Notiz›“ — Stand und Tag des Rücklaufs vor der Notiz.
    private static func notiztext(_ rueck: Rueckmeldung) -> String {
        ([rueck.stand.beschriftung(fuer: .mitteilung)] + tag(rueck.datum)).joined(separator: ", ") + ": " + rueck.notiz
    }

    /// Ein ISO-Tag als „01.09.2026“ — oder nichts.
    private static func tag(_ iso: String) -> [String] {
        Tag(iso: iso).map { [$0.deutsch] } ?? []
    }
}
