// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Kurse, Fächer, Farben, Ferien und Sperrzeiten lassen sich zurücknehmen (S5).
///
/// Je Dialogeingabe ein Schritt — und beide Richtungen jedes Schalters tragen
/// ihren eigenen Namen, denn im Menü steht, was zurückgenommen wird.
@Suite("Rücknahme: Kurse und Zeiträume")
struct RuecknahmeBearbeitenPruefungen {

    struct Fall: Sendable {
        let name: String
        var vorbereiten: (@Sendable @MainActor (Planungsspeicher) -> Void)?
        let tun: @Sendable @MainActor (Planungsspeicher) -> Void
    }

    static let faelle: [Fall] = [
        Fall(name: Schrittname.planungstitelAendern) { s in s.titelSetzen("Neues Schuljahr") },
        Fall(name: Schrittname.einstellungenUebernehmen) { s in
            guard let start = s.planung?.start else { return }
            s.einstellungenUebernehmen(start: start, wochen: 12, ersterSchultag: nil)
        },

        // ── Kurse ─────────────────────────────────────────────────────────
        Fall(name: Schrittname.kursHinzufuegen) { s in s.klasseHinzufuegen() },
        Fall(name: Schrittname.kursEntfernen) { s in
            guard let klasse = s.planung?.klassen.first else { return }
            s.klasseEntfernen(klasse)
            s.rueckfrageBeantworten(true)
        },
        Fall(name: Schrittname.kursAendern) { s in
            s.klasseAendern(id: "k1", name: "G6b", fach: "Physik")
        },
        Fall(name: Schrittname.kurseUmstellen) { s in s.klassenTauschen(0, 1) },
        Fall(name: Schrittname.bezeichnungAendern) { s in s.klasseAendern(id: "k1", name: "G6b") },
        Fall(name: Schrittname.fachAendern) { s in s.klasseAendern(id: "k1", fach: "Physik") },
        Fall(name: Schrittname.notizAendern) { s in s.klasseAendern(id: "k1", notiz: "Doppelstunde") },
        Fall(name: Schrittname.unterrichtstagHinzufuegen) { s in
            s.unterrichtstagSetzen(klasse: "k1", tag: .mittwoch, an: true)
        },
        Fall(name: Schrittname.unterrichtstagEntfernen,
             vorbereiten: { s in s.unterrichtstagSetzen(klasse: "k1", tag: .mittwoch, an: true) }) { s in
            s.unterrichtstagSetzen(klasse: "k1", tag: .mittwoch, an: false)
        },
        Fall(name: Schrittname.sonderzeileHinzufuegen(.klassenleitung)) { s in s.sonderzeileHinzufuegen(.klassenleitung) },
        Fall(name: Schrittname.sonderzeileHinzufuegen(.weiteres)) { s in s.sonderzeileHinzufuegen(.weiteres) },
        Fall(name: Schrittname.sonderzeileHinzufuegen(.vertretungen)) { s in s.sonderzeileHinzufuegen(.vertretungen) },

        // ── Fächer und Farben ─────────────────────────────────────────────
        Fall(name: Schrittname.fachUmbenennen) { s in
            s.fachUmbenennen(von: "Informatik", nach: "Technik")
        },
        Fall(name: Schrittname.fachEntfernen,
             vorbereiten: { s in s.fachfarbeSetzen(fach: "ohnezeile", ton: "rot-hell") }) { s in
            s.fachEntfernen("ohnezeile")
        },
        Fall(name: Schrittname.farbeWaehlen) { s in s.farbeSetzen(klasse: "k1", farbe: 3) },
        Fall(name: Schrittname.farbeDemFachFolgen,
             vorbereiten: { s in s.farbeSetzen(klasse: "k1", farbe: 3) }) { s in
            s.farbeDemFachFolgen(klasse: "k1")
        },
        Fall(name: Schrittname.fachfarbeWaehlen) { s in
            s.fachfarbeSetzen(fach: Farbwelt.fachSchluessel("Informatik"), ton: "tuerkis-dunkel")
        },
        Fall(name: Schrittname.fachfarbeEntfernen,
             vorbereiten: { s in
                 s.fachfarbeSetzen(fach: Farbwelt.fachSchluessel("Informatik"), ton: "tuerkis-dunkel")
             }) { s in
            s.fachfarbeSetzen(fach: Farbwelt.fachSchluessel("Informatik"), ton: nil)
        },

        // ── Die beiden Dateien eines Kurses ───────────────────────────────
        Fall(name: Schrittname.verwaltungsdateiHinterlegen) { s in
            s.kursdateiSetzen(klasse: "k1", art: .verwaltung, pfad: "/tmp/kursliste.numbers")
        },
        Fall(name: Schrittname.verwaltungsdateiEntfernen,
             vorbereiten: { s in
                 s.kursdateiSetzen(klasse: "k1", art: .verwaltung, pfad: "/tmp/kursliste.numbers")
             }) { s in
            s.kursdateiSetzen(klasse: "k1", art: .verwaltung, pfad: nil)
        },
        Fall(name: Schrittname.curriculumHinterlegen) { s in
            s.kursdateiSetzen(klasse: "k1", art: .curriculum, pfad: "/tmp/lehrplan.pdf")
        },
        Fall(name: Schrittname.curriculumEntfernen,
             vorbereiten: { s in
                 s.kursdateiSetzen(klasse: "k1", art: .curriculum, pfad: "/tmp/lehrplan.pdf")
             }) { s in
            s.kursdateiSetzen(klasse: "k1", art: .curriculum, pfad: nil)
        },

        // ── Ferien ────────────────────────────────────────────────────────
        Fall(name: Schrittname.ferienHinzufuegen) { s in s.ferienHinzufuegen() },
        Fall(name: Schrittname.ferienUmbenennen) { s in
            s.ferienNamenSetzen(id: "f1", name: "Herbstferien")
        },
        Fall(name: Schrittname.ferienAendern) { s in
            guard var zeitraum = s.planung?.ferien.first(where: { $0.id == "f1" }) else { return }
            zeitraum.bis = zeitraum.bis.plus(tage: 7)
            s.ferienAendern(zeitraum)
        },
        Fall(name: Schrittname.ferienEntfernen) { s in s.ferienEntfernen("f1") },

        // ── Sperrzeiten ───────────────────────────────────────────────────
        Fall(name: Schrittname.sperrzeitHinzufuegen) { s in _ = s.sperrzeitHinzufuegen() },
        Fall(name: Schrittname.sperrzeitUmbenennen) { s in
            s.sperrzeitNamenSetzen(id: "s1", name: "Praktikum")
        },
        Fall(name: Schrittname.sperrzeitAendern) { s in
            guard var zeitraum = s.planung?.sperrzeiten.first(where: { $0.id == "s1" }) else { return }
            zeitraum.bis = zeitraum.bis.plus(tage: 7)
            s.sperrzeitAendern(zeitraum)
        },
        Fall(name: Schrittname.sperrzeitKurse) { s in
            s.sperrzeitKurseSetzen(id: "s1", kurse: ["k1"])
        },
        Fall(name: Schrittname.sperrzeitEntfernen) { s in s.sperrzeitEntfernen("s1") },
    ]

    @MainActor
    static func speicher() throws -> (Planungsspeicher, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "bearb-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        let start = try #require(Tag(iso: "2026-08-03"))
        var p = Planung.leer(titel: "Bearbeiten", start: start, wochen: 8, basis: "",
                             klassen: [
                                Klasse(id: "k1", name: "G6a", fach: "Informatik", notiz: "", farbe: 0,
                                       farbeManuell: false),
                                Klasse(id: "k2", name: "G7b", fach: "Mathematik", notiz: "", farbe: 1,
                                       farbeManuell: false)],
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "v1", klasseId: "k1", woche: 1, titel: "Erstes", text: "",
                                erledigt: false, materialien: [], links: [])]
        p.ferien = [Ferienzeitraum(id: "f1", name: "Ferien", von: start.plus(tage: 21),
                                   bis: start.plus(tage: 25))]
        p.sperrzeiten = [Sperrzeitraum(id: "s1", name: "Sperrzeitraum", von: start.plus(tage: 35),
                                       bis: start.plus(tage: 39))]
        s.planung = p
        return (s, ordner)
    }

    @MainActor
    @Test("Tun, widerrufen, wiederholen — über alle Eingaben",
          arguments: RuecknahmeBearbeitenPruefungen.faelle.indices)
    func hinUndZurueck(_ nummer: Int) throws {
        // Aufbau und Handlung unter derselben angehaltenen Uhr (S4-R1).
        try Pruefuhr.angehalten {
            let fall = RuecknahmeBearbeitenPruefungen.faelle[nummer]
            let (s, ordner) = try RuecknahmeBearbeitenPruefungen.speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }

            fall.vorbereiten?(s)
            let vorher = try #require(s.planung)
            fall.tun(s)
            let nachher = try #require(s.planung)
            #expect(nachher != vorher, Comment(rawValue: "\(fall.name): die Eingabe muss etwas ändern"))
            #expect(s.verlauf.naechsterName == fall.name,
                    Comment(rawValue: "\(fall.name): im Menü steht „\(s.widerrufenTitel)“"))

            s.widerrufen()
            #expect(s.planung == vorher, Comment(rawValue: "\(fall.name): Wert für Wert wie vorher"))

            s.wiederholen()
            #expect(s.planung == nachher, Comment(rawValue: "\(fall.name): Wert für Wert wie danach"))
        }
    }

    @MainActor
    @Test("Ein Kurs kommt samt seinem Sitzplan zurück")
    func kursMitSitzplanKommtZurueck() throws {
        // Der Sitzplan liegt außerhalb der Planung und hat seinen eigenen
        // Schauplatz (E82) — mit dem Kurs verschwindet er trotzdem. Also reist
        // er als Beiwerk des Schrittes mit: Ein halbes Zurück ist keines.
        try Pruefuhr.angehalten {
            let (s, ordner) = try RuecknahmeBearbeitenPruefungen.speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let plan = Sitzplan.anordnen(klasseId: "k1", namen: ["Ada", "Alan", "Grace"])
            #expect(s.sitzplaene.setzen(plan, fuer: "k1") == nil)
            let vorher = try #require(s.planung)
            let gelegt = try #require(s.sitzplaene.plan(fuer: "k1"))

            let klasse = try #require(vorher.klassen.first { $0.id == "k1" })
            s.klasseEntfernen(klasse)
            let frage = try #require(s.rueckfrage)
            #expect(frage.text.contains("Sitzplan"), Comment(rawValue: frage.text))
            #expect(!frage.text.contains("nicht widerrufen"), "umkehrbar ist umkehrbar")
            s.rueckfrageBeantworten(true)
            #expect(s.planung?.klassen.contains { $0.id == "k1" } == false)
            #expect(s.sitzplaene.plan(fuer: "k1") == nil, "der Sitzplan ist mit fort")

            s.widerrufen()
            #expect(s.planung == vorher, "der Kurs ist Wert für Wert zurück")
            #expect(s.sitzplaene.plan(fuer: "k1") == gelegt, "und sein Sitzplan auch")

            s.wiederholen()
            #expect(s.planung?.klassen.contains { $0.id == "k1" } == false)
            #expect(s.sitzplaene.plan(fuer: "k1") == nil, "beim Wiederholen geht beides wieder fort")
        }
    }

    // ── Die Tasche statt der Momentaufnahme (N58-02, B31, E110) ───────────
    //
    // Der Löschschritt fing den Sitzplan beim Löschen und legte beim zweiten
    // ⌘Z genau den zurück — auch wenn dazwischen ein neuer übernommen wurde;
    // ein Kurs ohne Sitzplan trug gar kein Beiwerk. Jetzt trägt jeder
    // Löschschritt eine Tasche: Wiederholen greift den Sitzplan, der dann da
    // ist, Widerrufen bringt genau den zurück.

    @MainActor
    @Test("Nach ⌘Z ein neuer Sitzplan, dann ⇧⌘Z und ⌘Z — zurück kommt der neue, nicht der alte (N58-02)")
    func wiederholenNimmtDenNeuenSitzplan() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try RuecknahmeBearbeitenPruefungen.speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let p0 = Sitzplan.anordnen(klasseId: "k1", namen: ["Ada", "Alan", "Grace"])
            #expect(s.sitzplaene.setzen(p0, fuer: "k1") == nil)
            let klasse = try #require(s.planung?.klassen.first { $0.id == "k1" })
            s.klasseEntfernen(klasse)
            s.rueckfrageBeantworten(true)
            s.widerrufen()
            #expect(s.sitzplaene.plan(fuer: "k1")?.tische.map(\.name) == ["Ada", "Alan", "Grace"], "P0 ist zurück")

            // Neue Arbeit am Sitzplan — übernommen wie aus dem Blatt.
            let p1 = Sitzplan.anordnen(klasseId: "k1", namen: ["Edsger", "Barbara"])
            #expect(s.sitzplanUebernehmen(p1) == nil)
            #expect(s.kannWiederholen, "der Löschschritt steht noch vorn")

            s.wiederholen()
            #expect(s.planung?.klassen.contains { $0.id == "k1" } == false)
            #expect(s.sitzplaene.plan(fuer: "k1") == nil, "das Wiederholen nimmt den Sitzplan, der da ist")

            s.widerrufen()
            #expect(s.sitzplaene.plan(fuer: "k1")?.tische.map(\.name) == ["Edsger", "Barbara"],
                    "zurück kommt P1 — nicht die Momentaufnahme P0 vom ersten Löschen")

            // Und die Platte trägt P1: ein frischer Dienst liest die Datei.
            let frisch = Sitzplandienst(ablage: Ablage(ordner: ordner))
            _ = frisch.laden(stempel: "neu")
            #expect(frisch.plan(fuer: "k1")?.tische.map(\.name) == ["Edsger", "Barbara"])
        }
    }

    @MainActor
    @Test("Ein Kurs ohne Sitzplan trägt eine leere Tasche — ein später angelegter Sitzplan reist beim Wiederholen mit (B31)")
    func kursOhneSitzplanTraegtLeereTasche() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try RuecknahmeBearbeitenPruefungen.speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let klasse = try #require(s.planung?.klassen.first { $0.id == "k2" })
            s.klasseEntfernen(klasse)
            s.rueckfrageBeantworten(true)
            #expect(s.verlauf.zurueck.last?.beiwerk != nil, "die Tasche ist da, auch wenn sie leer ist")
            s.widerrufen()
            #expect(s.planung?.klassen.contains { $0.id == "k2" } == true)

            let neu = Sitzplan.anordnen(klasseId: "k2", namen: ["Ada"])
            #expect(s.sitzplanUebernehmen(neu) == nil)
            s.wiederholen()
            #expect(s.planung?.klassen.contains { $0.id == "k2" } == false)
            #expect(s.sitzplaene.plan(fuer: "k2") == nil, "der Sitzplan geht mit dem Kurs — bleibt nicht verwaist liegen")
            // Ohne Pläne legt der Dienst keine Datei hin — liegt eine, trägt sie k2 nicht.
            if let roh = try? Data(contentsOf: Ablage(ordner: ordner).sitzplaene) {
                #expect(!(try Sitzplandatei.lesen(roh)).keys.contains("k2"), "auch nicht in der Datei")
            }

            s.widerrufen()
            #expect(s.sitzplaene.plan(fuer: "k2")?.tische.map(\.name) == ["Ada"], "und kommt mit ihm zurück")
        }
    }

    @MainActor
    @Test("Eine leere Tasche hält kein Widerrufen auf — gesperrte Sitzpläne zählen nur, wenn einer zurückzulegen ist")
    func leereTascheHaeltNichtAuf() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try RuecknahmeBearbeitenPruefungen.speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let klasse = try #require(s.planung?.klassen.first { $0.id == "k2" })
            s.klasseEntfernen(klasse)
            s.rueckfrageBeantworten(true)
            s.sitzplaene.schliessen()
            s.widerrufen()
            #expect(s.planung?.klassen.contains { $0.id == "k2" } == true, "nichts zurückzulegen — der Kurs kommt")
        }
    }

    @MainActor
    @Test("Sind die Sitzpläne gesperrt, wird der Schritt gar nicht genommen")
    func gesperrteSitzplaeneVerhindernDasHalbeZurueck() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try RuecknahmeBearbeitenPruefungen.speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            #expect(s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: "k1", namen: ["Ada"]),
                                        fuer: "k1") == nil)
            let klasse = try #require(s.planung?.klassen.first { $0.id == "k1" })
            s.klasseEntfernen(klasse)
            s.rueckfrageBeantworten(true)

            // Die Sitzpläne sind nicht mehr zu haben — versiegelt, gesperrt,
            // was auch immer: Dann käme der Kurs zurück und sein Sitzplan nicht.
            s.sitzplaene.schliessen()
            s.widerrufen()
            #expect(s.planung?.klassen.contains { $0.id == "k1" } == false,
                    "der Schritt bleibt ungetan")
            #expect(s.kannWiderrufen, "und er bleibt im Verlauf stehen")
            #expect(s.meldungen.last?.art == .warnung, "gesagt wird es auch")
            #expect(s.meldungen.last?.text.contains("nicht zurücknehmen") == true,
                    Comment(rawValue: s.meldungen.last?.text ?? ""))
        }
    }

    @MainActor
    @Test("Ein Schritt mit Beiwerk wächst in keinen anderen hinein (E88)")
    func beiwerkFasstNichtZusammen() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try RuecknahmeBearbeitenPruefungen.speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            #expect(s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: "k1", namen: ["Ada"]),
                                        fuer: "k1") == nil)
            s.klasseAendern(id: "k1", name: "G6b")
            let klasse = try #require(s.planung?.klassen.first { $0.id == "k1" })
            s.klasseEntfernen(klasse)
            s.rueckfrageBeantworten(true)
            #expect(s.verlauf.zurueck.count == 2, "zwei Handgriffe, zwei Schritte")

            s.widerrufen()
            #expect(s.sitzplaene.plan(fuer: "k1") != nil, "der Sitzplan kommt mit dem Kurs zurück")
            s.widerrufen()
            #expect(s.planung?.klassen.first { $0.id == "k1" }?.name == "G6a",
                    "und der Schritt davor geht auch noch zurück")
        }
    }
}
