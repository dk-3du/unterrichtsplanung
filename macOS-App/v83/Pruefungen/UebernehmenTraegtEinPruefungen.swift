// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── „Übernehmen“ mit getippter Namensliste (v83, AV2a: B106, E457, E458) ──
// Ein Knopf im Fuß des Blatts schließt einen im Abschnitt ein, wo sie sich
// nicht widersprechen: „Übernehmen“ trägt eine lesbare Liste ein wie
// „Eintragen“ — dieselbe Rechnung, dieselbe Meldung — und übernimmt dann.
// Mit einer fehlerhaften Zeile bleibt das Blatt offen: nichts übernommen,
// nichts verloren, die Warnung nennt die Zeile. Ist die Liste verdeckt, kommt
// sie erst nach vorn und wird nicht eingetragen (Z-AV2a-01). Die übrigen Wege
// fragen weiter (E303). Geprüft an der reinen Entscheidung `listeBeimUebernehmen`.

@Suite("„Übernehmen“ mit getippter Namensliste: eintragen und übernehmen — oder offen bleiben (B106, E457, E458)")
struct UebernehmenTraegtEinPruefungen {

    private static let stempel = "2026-10-10T08:00:00.000Z"
    private static let jetzt = "2026-10-10T09:00:00.000Z"

    /// „6a“ mit Anna Abel und Ben Bauer, „6b“ leer; dazu zweimal „Max Mai“, aktiv und ohne Gruppe.
    private func bestand() throws -> (bestand: Lernendenbestand, g1: String, g2: String) {
        var b = Lernendenbestand.leer(planung: "2026-08-10T09:00:00.000Z", schuljahr: "2026/27", jetzt: Self.stempel)
        let eins = try #require(b.mitNeuerGruppe(name: "6a", fach: "Biologie", art: .klasse, jetzt: Self.stempel))
        b = eins.bestand
        let zwei = try #require(b.mitNeuerGruppe(name: "6b", fach: "", art: .klasse, jetzt: Self.stempel))
        b = zwei.bestand
        b = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: eins.id, jetzt: Self.stempel).bestand
        for id in ["l-8", "l-9"] {
            b.lernende.append(Lernender(id: id, vorname: "Max", nachname: "Mai", angelegt: Self.stempel,
                                        geaendert: Self.stempel, archiviert: ""))
        }
        return (b, eins.id, zwei.id)
    }

    private func uebernahme(_ text: String, _ gruppe: String?, _ b: Lernendenbestand, sichtbar: Bool = true) -> Listenausgang {
        LernendenDialog.listeBeimUebernehmen(text, gruppe: gruppe, sichtbar: sichtbar, entwurf: b, jetzt: Self.jetzt)
    }

    /// Der Stand ohne Kennungen — neue Personen tragen je Lauf eine andere.
    private func abbild(_ b: Lernendenbestand) -> [String] {
        let name = Dictionary(uniqueKeysWithValues: b.lernende.map { ($0.id, "\($0.vorname) \($0.nachname)") })
        return ["geändert \(b.geaendert)"]
            + b.lernende.map { "\($0.vorname) \($0.nachname) · angelegt \($0.angelegt) · archiviert „\($0.archiviert)“" }
            + b.lerngruppen.map { g in
                "\(g.name) · \(g.fach) · geändert \(g.geaendert): " + g.mitglieder.map { name[$0] ?? "?" }.joined(separator: ", ")
            }
    }

    /// Der Stand und die Meldung, wenn eingetragen wird — sonst `nil`.
    private func eingetragen(_ weg: Listenausgang) -> (bestand: Lernendenbestand, meldung: String?)? {
        guard case .eintragen(let bestand, let meldung) = weg else { return nil }
        return (bestand, meldung)
    }

    @Test("Ohne getippte Liste übernimmt es wie bisher — Leerzeilen und Leerraum sind keine Liste")
    func ohneListe() throws {
        let (b, g1, _) = try bestand()
        for text in ["", "   ", "\n \n\t\n"] {
            #expect(uebernahme(text, g1, b) == .ohneListe, Comment(rawValue: "„\(text)“"))
        }
        #expect(uebernahme("", nil, b) == .ohneListe)
    }

    @Test("Eine lesbare Liste wird eingetragen wie mit „Eintragen“ — dieselbe Rechnung, keine Frage (E457)")
    func lesbarTraegtEin() throws {
        let (b, g1, _) = try bestand()
        let text = "Neu, Nora\nabel, ANNA\nPeter Pan\n"
        let erwartet = b.mitPersonen(Namenszeilen.lesen(text).namen, inGruppe: g1, jetzt: Self.jetzt)
        let (neu, meldung) = try #require(eingetragen(uebernahme(text, g1, b)), "eingetragen wird — nicht gefragt")
        #expect(abbild(neu) == abbild(erwartet.bestand) && meldung == nil)
        // Am Stand: Nora Neu und Peter Pan neu in „6a“, Anna Abel war schon da.
        let gruppe = try #require(neu.lerngruppen.first { $0.id == g1 })
        let namen = gruppe.mitglieder.compactMap { id in neu.lernende.first { $0.id == id }.map { "\($0.vorname) \($0.nachname)" } }
        #expect(namen == ["Anna Abel", "Ben Bauer", "Nora Neu", "Peter Pan"])
        #expect(neu.lernende.count == b.lernende.count + 2)
    }

    @Test("Mehrfach im Schuljahr und über der Grenze: Der Rest wird eingetragen, die Meldung lautet wie beim Eintragen (E458)")
    func meldungWieBeimEintragen() throws {
        let (b, g1, _) = try bestand()
        // „6a“ hat zwei Mitglieder, Platz für 38: „Max Mai“ steht zweimal im Schuljahr, von 39 Neuen bleibt einer draußen.
        let text = (["Mai, Max"] + (1...39).map { "Nachname\($0), Vorname\($0)" }).joined(separator: "\n")
        let ergebnis = b.mitPersonen(Namenszeilen.lesen(text).namen, inGruppe: g1, jetzt: Self.jetzt)
        #expect(ergebnis.neu.count == 38 && ergebnis.ueberGrenze == 1 && ergebnis.gleichnamig == 1, "Vorbedingung")
        let meldung = "38 eingetragen — 1 über der Grenze von 40 je Lerngruppe blieben draußen — 1 Namen stehen "
            + "mehrfach im Schuljahr und wurden nicht eingetragen (nichts geraten)."
        #expect(LernendenDialog.eintragsmeldung(ergebnis) == meldung, "der Wortlaut von „Eintragen“")
        let weg = try #require(eingetragen(uebernahme(text, g1, b)), "eingetragen wird — nicht gefragt")
        #expect(abbild(weg.bestand) == abbild(ergebnis.bestand))
        #expect(weg.meldung == meldung)
    }

    @Test("Die Meldung des Eintragens: keine, wenn alle eingetragen oder schon da sind; sonst je Grund ihr Teil")
    func meldungJeGrund() throws {
        let (b, g1, g2) = try bestand()
        let ohne = b.mitPersonen(Namenszeilen.lesen("Neu, Nora\nAbel, Anna").namen, inGruppe: g1, jetzt: Self.jetzt)
        #expect(LernendenDialog.eintragsmeldung(ohne) == nil)
        let mehrfach = b.mitPersonen([Namenszeilen.Name(vorname: "Max", nachname: "Mai")], inGruppe: g2, jetzt: Self.jetzt)
        #expect(LernendenDialog.eintragsmeldung(mehrfach)
                == "0 eingetragen — 1 Namen stehen mehrfach im Schuljahr und wurden nicht eingetragen (nichts geraten).")
        // „6b“ voll mit 40, dann noch zwei.
        let vierzig = (1...40).map { Namenszeilen.Name(vorname: "V\($0)", nachname: "N\($0)") }
        let voll = b.mitPersonen(vierzig, inGruppe: g2, jetzt: Self.jetzt).bestand
        let zwei = [Namenszeilen.Name(vorname: "Zu", nachname: "Viel"), Namenszeilen.Name(vorname: "Noch", nachname: "Einer")]
        #expect(LernendenDialog.eintragsmeldung(voll.mitPersonen(zwei, inGruppe: g2, jetzt: Self.jetzt))
                == "0 eingetragen — 2 über der Grenze von 40 je Lerngruppe blieben draußen.")
    }

    @Test("Eine fehlerhafte Zeile: Das Blatt bleibt offen, nichts eingetragen — die Warnung nennt die erste Zeile wie die Vorschau (E458)")
    func fehlerhafteZeileBleibtOffen() throws {
        let (b, g1, _) = try bestand()
        let faelle: [(text: String, zeile: Int)] = [
            ("Neu, Nora\nPan\nPeter Pan", 2),                                  // nur ein Wort
            ("\n\nA, B, C\nPan", 3),                                            // Leerzeilen zählen; die erste von zweien
            ((1...41).map { "N\($0), V\($0)" }.joined(separator: "\n"), 41),    // über der Grenze je Eingabe
        ]
        for fall in faelle {
            #expect(Namenszeilen.lesen(fall.text).fehler.first?.nummer == fall.zeile,
                    "Vorbedingung: die Vorschau zeigt Zeile \(fall.zeile) rot")
            #expect(uebernahme(fall.text, g1, b) == .offenBleiben(warnung: "Zeile \(fall.zeile) lässt sich nicht eintragen — nichts übernommen."))
        }
    }

    @Test("Lesbar, aber nichts einzutragen (alle schon da): Der Stand bleibt, übernommen wird — ohne Frage, ohne Meldung")
    func nichtsEinzutragen() throws {
        let (b, g1, _) = try bestand()
        #expect(uebernahme("Abel, Anna\nBen Bauer", g1, b) == .eintragen(b, meldung: nil))
    }

    @Test("Eine Liste ohne ihre Lerngruppe im Entwurf fragt wie die übrigen Wege (E303) — nichts geht stumm verloren")
    func ohneGruppeFragt() throws {
        let (b, _, _) = try bestand()
        #expect(uebernahme("Neu, Nora", nil, b) == .fragen)
        #expect(uebernahme("Neu, Nora", "g-99", b) == .fragen)
    }

    @Test("Verdeckt und lesbar („Alle Lernenden“, „Archiv“, „Mitteilungen“, „Maßnahmen“ vorn): nichts eingetragen — die Liste kommt nach vorn, ein Hinweis sagt es (Z-AV2a-01)")
    func verdecktZeigt() throws {
        let (b, g1, _) = try bestand()
        let hinweis = "Die getippten Namen sind noch nicht eingetragen — „Übernehmen“ trägt sie ein."
        for text in ["Neu, Nora", "Abel, Anna\nBen Bauer"] {
            #expect(uebernahme(text, g1, b, sichtbar: false) == .zeigen(hinweis: hinweis), Comment(rawValue: "„\(text)“"))
        }
    }

    @Test("Verdeckt und fehlerhaft: dieselbe Warnung wie sichtbar; ohne Liste oder ohne Gruppe wie sichtbar (Z-AV2a-01)")
    func verdecktSonstWieSichtbar() throws {
        let (b, g1, _) = try bestand()
        #expect(uebernahme("Neu, Nora\nPan", g1, b, sichtbar: false)
                == .offenBleiben(warnung: "Zeile 2 lässt sich nicht eintragen — nichts übernommen."))
        let faelle: [(text: String, gruppe: String?)] = [("Neu, Nora\nPan", g1), ("", g1), ("  ", nil), ("Neu, Nora", nil), ("Neu, Nora", "g-99")]
        for fall in faelle {
            #expect(uebernahme(fall.text, fall.gruppe, b, sichtbar: false) == uebernahme(fall.text, fall.gruppe, b),
                    Comment(rawValue: "„\(fall.text)“ in \(fall.gruppe ?? "keiner Gruppe")"))
        }
    }
}
