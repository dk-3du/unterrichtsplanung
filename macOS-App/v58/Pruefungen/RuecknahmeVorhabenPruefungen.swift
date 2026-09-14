// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Jede Handlung an einem Vorhaben lässt sich zurücknehmen (S3).
///
/// Geprüft wird je Handlung dasselbe: tun → widerrufen → **Wert für Wert** wie
/// vorher; wiederholen → Wert für Wert wie danach. Der Vergleich nimmt die
/// ganze Planung, nicht das eine Feld — so fällt auch auf, was eine Handlung
/// nebenbei anfasst. Die Uhr steht dabei (E81): Sonst unterschiede allein der
/// Zeitstempel zwei Stände, die gleich sein müssen.
@Suite("Rücknahme: Vorhaben")
struct RuecknahmeVorhabenPruefungen {

    struct Fall: Sendable {
        /// Der Name, der im Menü stehen muss.
        let name: String
        /// Was vor der Momentaufnahme geschehen muss — für die Gegenrichtung
        /// eines Schalters: erst hinzufügen, dann entfernen.
        var vorbereiten: (@Sendable @MainActor (Planungsspeicher, String) -> Void)?
        let tun: @Sendable @MainActor (Planungsspeicher, String) -> Void
    }

    static let faelle: [Fall] = [
        Fall(name: Schrittname.titelAendern) { s, id in
            s.titelSetzen(vorhaben: id, titel: "Ganz neuer Titel")
        },
        Fall(name: Schrittname.vorhabenUmstellen) { s, id in s.reihen(id, nachOben: false) },
        Fall(name: Schrittname.vorhabenAbhaken) { s, id in s.erledigtUmschalten(id) },
        Fall(name: Schrittname.hakenEntfernen,
             vorbereiten: { s, id in s.erledigtUmschalten(id) }) { s, id in
            s.erledigtUmschalten(id)
        },
        Fall(name: Schrittname.dringlichKennzeichnen) { s, id in s.dringlichUmschalten(id) },
        Fall(name: Schrittname.dringlichkeitEntfernen,
             vorbereiten: { s, id in s.dringlichUmschalten(id) }) { s, id in
            s.dringlichUmschalten(id)
        },
        Fall(name: Schrittname.hausaufgabeHinzufuegen) { s, id in s.hausaufgabeUmschalten(id) },
        Fall(name: Schrittname.hausaufgabeEntfernen,
             vorbereiten: { s, id in s.hausaufgabeUmschalten(id) }) { s, id in
            s.hausaufgabeUmschalten(id)
        },
        Fall(name: Schrittname.alsPruefungFuehren) { s, id in s.pruefungUmschalten(id) },
        Fall(name: Schrittname.pruefungEntfernen,
             vorbereiten: { s, id in s.pruefungUmschalten(id) }) { s, id in
            s.pruefungUmschalten(id)
        },
        Fall(name: Schrittname.vorhabenVerschieben) { s, id in
            s.vorhabenVerschieben(id, klasse: "k2", woche: 2)
        },
        Fall(name: Schrittname.vorhabenAendern) { s, id in
            guard let vorhaben = s.planung?.eintraege.first(where: { $0.id == id }) else { return }
            var entwurf = VorhabenEntwurf(vorhaben)
            entwurf.text = "Aus dem Dialog geändert"
            entwurf.dringend = true
            s.vorhabenSichern(entwurf)
        },
        Fall(name: Schrittname.vorhabenHinzufuegen) { s, _ in
            var entwurf = VorhabenEntwurf(klasseId: "k1", woche: 3)
            entwurf.titel = "Neu aus dem Dialog"
            s.vorhabenSichern(entwurf)
        },
        Fall(name: Schrittname.vorhabenEntfernen) { s, id in
            s.vorhabenLoeschen(id, ort: .hauptansicht)
            s.rueckfrageBeantworten(true)
        },
    ]

    @MainActor
    private func speicher() throws -> (Planungsspeicher, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "vorhaben-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        var p = Planung.leer(titel: "Vorhaben", start: try #require(Tag(iso: "2026-08-03")), wochen: 6,
                             basis: "", klassen: [
                                Klasse(id: "k1", name: "G6a", fach: "Informatik", notiz: "", farbe: 0,
                                       farbeManuell: false),
                                Klasse(id: "k2", name: "G7b", fach: "Mathematik", notiz: "", farbe: 1,
                                       farbeManuell: false)],
                             fachfarben: [:])
        // Zwei in derselben Zelle — sonst ließe sich nichts umstellen.
        p.eintraege = [
            Vorhaben(id: "v1", klasseId: "k1", woche: 1, titel: "Erstes", text: "Text",
                     erledigt: false, materialien: [], links: []),
            Vorhaben(id: "v2", klasseId: "k1", woche: 1, titel: "Zweites", text: "Text",
                     erledigt: false, materialien: [], links: []),
        ]
        s.planung = p
        return (s, ordner)
    }

    @MainActor
    @Test("Tun, widerrufen, wiederholen — über alle Handlungen",
          arguments: RuecknahmeVorhabenPruefungen.faelle.indices)
    func hinUndZurueck(_ nummer: Int) throws {
        // Aufbau und Handlung unter derselben angehaltenen Uhr: `sichern()`
        // stempelt auch beim Widerrufen, und ein Stempel von vorhin machte
        // zwei Stände ungleich, die gleich sein müssen.
        try Pruefuhr.angehalten {
            let fall = RuecknahmeVorhabenPruefungen.faelle[nummer]
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }

            fall.vorbereiten?(s, "v1")
            let vorher = try #require(s.planung)
            fall.tun(s, "v1")
            let nachher = try #require(s.planung)
            #expect(nachher != vorher, Comment(rawValue: "\(fall.name): die Handlung muss etwas ändern"))
            #expect(s.verlauf.naechsterName == fall.name,
                    Comment(rawValue: "\(fall.name): im Menü steht „\(s.widerrufenTitel)“"))

            s.widerrufen()
            #expect(s.planung == vorher, Comment(rawValue: "\(fall.name): Wert für Wert wie vorher"))

            s.wiederholen()
            #expect(s.planung == nachher, Comment(rawValue: "\(fall.name): Wert für Wert wie danach"))
        }
    }

    @MainActor
    @Test("Jede Handlung ist ein eigener Schritt — keine fasst die andere ein")
    func jedeHandlungEinSchritt() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        Pruefuhr.angehalten {
            s.erledigtUmschalten("v1")
            s.dringlichUmschalten("v1")
            s.hausaufgabeUmschalten("v1")
        }
        #expect(s.verlauf.zurueck.count == 3, "drei Handgriffe, drei Schritte")
        #expect(s.verlauf.zurueck.map(\.name)
                == [Schrittname.vorhabenAbhaken, Schrittname.dringlichKennzeichnen,
                    Schrittname.hausaufgabeHinzufuegen])
    }

    @MainActor
    @Test("Der Titel an der Kachel bleibt ein Schritt, so lange daran getippt wird (E88)")
    func titelIstEineSchreibphase() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let vorher = try #require(s.planung)
            s.titelSetzen(vorhaben: "v1", titel: "E")
            s.titelSetzen(vorhaben: "v1", titel: "Er")
            s.titelSetzen(vorhaben: "v1", titel: "Erst")
            s.titelSetzen(vorhaben: "v1", titel: "Erstens")
            #expect(s.verlauf.zurueck.count == 1, "ein Titel, ein Schritt")
            s.widerrufen()
            #expect(s.planung == vorher, "und zurück geht es bis vor den ersten Tastendruck")
        }
    }

    @MainActor
    @Test("Zwei Titel an zwei Kacheln sind zwei Schritte")
    func zweiKachelnZweiSchritte() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        Pruefuhr.angehalten {
            s.titelSetzen(vorhaben: "v1", titel: "Eins")
            s.titelSetzen(vorhaben: "v2", titel: "Zwei")
        }
        #expect(s.verlauf.zurueck.count == 2)
    }

    @MainActor
    @Test("Die Auswahl steht nach einer Rücknahme auf dem, was wieder da ist")
    func auswahlNachDerRuecknahme() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        s.anwaehlen(vorhaben: "v1")
        s.vorhabenLoeschen("v1", ort: .hauptansicht)
        s.rueckfrageBeantworten(true)
        #expect(s.planung?.eintraege.contains { $0.id == "v1" } == false)
        #expect(!s.auswahl.contains("v1"), "was fort ist, bleibt nicht angewählt")

        s.widerrufen()
        #expect(s.planung?.eintraege.contains { $0.id == "v1" } == true, "und ist wieder da")
    }
}
