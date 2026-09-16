// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Zwischenablage und Fläche lassen sich zurücknehmen (S4).
///
/// Eine Gruppe ist **ein** Handgriff: Wer drei Vorhaben auf einmal einsetzt
/// oder entfernt, nimmt sie auch auf einmal zurück. Die Auswahl selbst gehört
/// nicht in den Verlauf — sie ist Ansicht, nicht Inhalt.
@Suite("Rücknahme: Zwischenablage und Fläche")
struct RuecknahmeFlaechePruefungen {

    struct Fall: Sendable {
        let name: String
        /// Was vor der Momentaufnahme geschehen muss — für die Gegenrichtung.
        var vorbereiten: (@Sendable @MainActor (Planungsspeicher) -> Void)?
        let tun: @Sendable @MainActor (Planungsspeicher) -> Void
    }

    static let faelle: [Fall] = [
        Fall(name: Schrittname.vorhabenEinsetzen) { s in
            s.anwaehlen(vorhaben: "v1")
            s.kopieren()
            s.anwaehlen(zelle: Zellenort(klasse: "k2", woche: 3))
            s.einfuegen()
        },
        Fall(name: Schrittname.vorhabenVerschieben) { s in
            s.anwaehlen(vorhaben: "v1")
            s.verschiebenVormerken()
            s.anwaehlen(zelle: Zellenort(klasse: "k2", woche: 3))
            s.einfuegen()
        },
        Fall(name: Schrittname.reihenfolgeAendern) { s in
            guard let zweites = s.planung?.eintraege.first(where: { $0.id == "v2" }) else { return }
            s.versetzen([zweites], nach: Zellenort(klasse: "k1", woche: 1), verschieben: true, vor: "v1")
        },
        Fall(name: Schrittname.vorhabenEntfernen) { s in
            s.anwaehlen(vorhaben: "v1")
            s.anwaehlen(vorhaben: "v2", erweitern: true)
            s.auswahlLoeschen()
            s.rueckfrageBeantworten(true)
        },
        Fall(name: Schrittname.wocheFrei) { s in
            guard let woche = s.planung?.wochenListe[safe: 2] else { return }
            s.wocheFreiSchalten(woche)
        },
        Fall(name: Schrittname.wocheUnterricht,
             vorbereiten: { s in
                 guard let woche = s.planung?.wochenListe[safe: 2] else { return }
                 s.wocheFreiSchalten(woche)
             }) { s in
            guard let woche = s.planung?.wochenListe[safe: 2] else { return }
            s.wocheFreiSchalten(woche)
        },
        Fall(name: Schrittname.zelleFrei) { s in
            guard let woche = s.planung?.wochenListe[safe: 2] else { return }
            s.zelleFreiSchalten(klasse: "k1", woche: woche)
        },
        Fall(name: Schrittname.zelleUnterricht,
             vorbereiten: { s in
                 guard let woche = s.planung?.wochenListe[safe: 2] else { return }
                 s.zelleFreiSchalten(klasse: "k1", woche: woche)
             }) { s in
            guard let woche = s.planung?.wochenListe[safe: 2] else { return }
            s.zelleFreiSchalten(klasse: "k1", woche: woche)
        },
    ]

    @MainActor
    private func speicher() throws -> (Planungsspeicher, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "flaeche-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        var p = Planung.leer(titel: "Fläche", start: try #require(Tag(iso: "2026-08-03")), wochen: 8,
                             basis: "", klassen: [
                                Klasse(id: "k1", name: "G6a", fach: "Informatik", notiz: "", farbe: 0,
                                       farbeManuell: false),
                                Klasse(id: "k2", name: "G7b", fach: "Mathematik", notiz: "", farbe: 1,
                                       farbeManuell: false)],
                             fachfarben: [:])
        p.eintraege = [
            Vorhaben(id: "v1", klasseId: "k1", woche: 1, titel: "Erstes", text: "",
                     erledigt: false, materialien: [], links: []),
            Vorhaben(id: "v2", klasseId: "k1", woche: 1, titel: "Zweites", text: "",
                     erledigt: false, materialien: [], links: []),
            Vorhaben(id: "v3", klasseId: "k2", woche: 5, titel: "Drittes", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        s.planung = p
        return (s, ordner)
    }

    @MainActor
    @Test("Tun, widerrufen, wiederholen — über alle Handgriffe",
          arguments: RuecknahmeFlaechePruefungen.faelle.indices)
    func hinUndZurueck(_ nummer: Int) throws {
        // Aufbau und Handlung unter derselben angehaltenen Uhr: `sichern()`
        // stempelt auch beim Widerrufen, und ein Stempel von vorhin machte
        // zwei Stände ungleich, die gleich sein müssen.
        try Pruefuhr.angehalten {
            let fall = RuecknahmeFlaechePruefungen.faelle[nummer]
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }

            fall.vorbereiten?(s)
            let vorher = try #require(s.planung)
            fall.tun(s)
            let nachher = try #require(s.planung)
            #expect(nachher != vorher, Comment(rawValue: "\(fall.name): der Handgriff muss etwas ändern"))
            #expect(s.verlauf.naechsterName == fall.name,
                    Comment(rawValue: "\(fall.name): im Menü steht „\(s.widerrufenTitel)“"))
            #expect(s.verlauf.zurueck.count == (fall.vorbereiten == nil ? 1 : 2),
                    Comment(rawValue: "\(fall.name): ein Handgriff, ein Schritt"))

            s.widerrufen()
            #expect(s.planung == vorher, Comment(rawValue: "\(fall.name): Wert für Wert wie vorher"))

            s.wiederholen()
            #expect(s.planung == nachher, Comment(rawValue: "\(fall.name): Wert für Wert wie danach"))
        }
    }

    @MainActor
    @Test("Drei auf einmal entfernt gehen auf einmal zurück")
    func gruppeIstEinSchritt() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            // Die Uhr steht: Sonst unterschiede allein der Stempel zwei Stände,
            // die gleich sein müssen — `sichern()` stempelt auch beim Widerrufen.
            let vorher = try #require(s.planung)
            s.allesAnwaehlen()
            s.auswahlLoeschen()
            s.rueckfrageBeantworten(true)
            #expect(s.planung?.eintraege.isEmpty == true)
            #expect(s.verlauf.zurueck.count == 1, "eine Handlung, ein Schritt")

            s.widerrufen()
            #expect(s.planung == vorher, "und alle drei sind wieder da")
        }
    }

    @MainActor
    @Test("Über mehrere Zellen hinweg verschoben — ein Schritt")
    func ueberMehrereZellen() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let vorher = try #require(s.planung)
            let alle = vorher.eintraege
            s.versetzen(alle, nach: Zellenort(klasse: "k1", woche: 3), verschieben: true)
            #expect(s.verlauf.zurueck.count == 1)
            #expect(s.verlauf.naechsterName == Schrittname.vorhabenVerschieben)

            s.widerrufen()
            #expect(s.planung == vorher, "Wert für Wert wie vorher")
        }
    }

    @MainActor
    @Test("Die Zwischenablage selbst kommt nicht zurück")
    func ablageBleibtWieSieIst() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        s.anwaehlen(vorhaben: "v1")
        s.kopieren()
        #expect(s.ablage != nil)
        s.anwaehlen(zelle: Zellenort(klasse: "k2", woche: 3))
        s.einfuegen()
        s.widerrufen()
        // Was kopiert wurde, bleibt kopiert: Der Verlauf trägt die Planung,
        // nicht den Zwischenstand der Hand.
        #expect(s.ablage != nil)
    }
}
