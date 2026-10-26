// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Weg aus ⌘K zur Lernendenverwaltung (v84, AT4) ─────────────────────
// Ganz oben in ⌘K ein Abschnitt „Lernende“ mit Knopf und Zusammenfassung (E356). Nach dem Blatt geht es zurück zu
// ⌘K (E358) — auch, wenn es über das Personen-Symbol einer Zeile aufging (E505). Ist die Verwaltung versiegelt oder
// gesperrt, fragt ⌘K mit einem Knopf, statt hinter dem Blatt zu melden (E357).

@Suite("⌘K: Abschnitt „Lernende“, Rückweg, Rückfrage bei versiegelt oder gesperrt")
@MainActor
struct KlassenLernendenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "klassenlernende-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                     basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
    }

    /// Ein eingeschalteter Speicher, noch ohne Jahresdatei.
    private func speicher(_ ablage: URL) async throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        return s
    }

    @Test("Aus ⌘K mit Rückweg (E358): ⌘K geht, das Blatt kommt; beim Schließen ist ⌘K vorgemerkt und steht wieder")
    func rueckweg() async throws {
        let ablage = try ordner("rueckweg")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        s.offenerDialog = .klassen
        s.lernendenBlattOeffnen(ort: .klassen, zurueck: .klassen)
        #expect(s.offenerDialog == nil && s.naechsterDialog == .lernende, "ein Fenster trägt ein Blatt")
        #expect(s.lernendenVorgabe?.zurueck == .klassen, "das Blatt erfährt den Rückweg")
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == .lernende)
        s.lernendenblattSchliessen(zurueck: .klassen)
        #expect(s.naechsterDialog == .klassen, "vorgemerkt, bevor das Blatt geht")
        s.offenerDialog = nil
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == .klassen, "⌘K steht wieder")
        // Ein zweites Schließen des schon fortgegangenen Blatts — aus der Lücke nach einer Antwort — merkt nichts mehr
        // vor; sonst ginge ⌘K nach „Fertig“ noch einmal auf (Z-AT4-01).
        s.lernendenblattSchliessen(zurueck: .klassen)
        #expect(s.naechsterDialog == nil, "⌘K nicht noch einmal vorgemerkt")
    }

    @Test("Ohne Rückweg — aus dem Menü (⌘L) oder der Kurszelle — ins Hauptfenster; ⌘Q räumt einen vorgemerkten Rückweg")
    func ohneRueckweg() async throws {
        let ablage = try ordner("ohne")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        s.lernendenBlattOeffnen(gruppe: "g-1")
        #expect(s.offenerDialog == .lernende && s.lernendenVorgabe != nil && s.lernendenVorgabe?.zurueck == nil)
        s.lernendenblattSchliessen(zurueck: nil)
        #expect(s.naechsterDialog == nil)
        s.offenerDialog = nil
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == nil, "kein Blatt danach")

        s.offenerDialog = .lernende
        s.lernendenblattSchliessen(zurueck: .klassen)
        s.alleDialogeSchliessen()
        #expect(s.offenerDialog == nil && s.naechsterDialog == nil, "beim Beenden kein ⌘K")
    }

    @Test("Versiegelt oder gesperrt aus ⌘K (E357): eine Rückfrage mit einem Knopf an ⌘K — kein Blatt, keine Meldung dahinter")
    func gesperrtFragt() async throws {
        let ablage = try ordner("gesperrt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        let tresor = try #require(s.tresor)
        s.lernende.schliessen()
        #expect(s.lernende.quelle == .zu)
        s.offenerDialog = .klassen
        let vorher = s.meldungen.count
        s.lernendenBlattOeffnen(ort: .klassen, zurueck: .klassen)
        let frage = try #require(s.rueckfrage, "eine Rückfrage statt der Meldung hinter dem Blatt")
        #expect(frage.text == s.lernende.sperrhinweis && frage.ort == .klassen)
        #expect(frage.bestaetigung == "Verstanden" && frage.ablehnung == "", "ein Knopf")
        #expect(s.offenerDialog == .klassen && s.naechsterDialog == nil && s.meldungen.count == vorher)
        s.rueckfrageBeantworten(true)
        #expect(s.rueckfrage == nil && s.offenerDialog == .klassen, "„Verstanden“ lässt ⌘K stehen")

        // Gesperrt: eine Jahresdatei in einer neueren Fassung.
        let leer = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: "2026-09-01T08:00:00.000Z")
        var neuer = try #require(JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(leer)) as? [String: Any])
        neuer["version"] = 2
        let neuere = try tresor.versiegeln(try JSONSerialization.data(withJSONObject: neuer), inhalt: .lernende, ziel: .ablage)
        try neuere.write(to: Ablage(ordner: ablage).lernende)
        guard case .gesperrt = s.lernende.oeffnen(mit: tresor, stempel: "s") else {
            Issue.record("erwartet gesperrt")
            return
        }
        s.lernendenBlattOeffnen(ort: .klassen, zurueck: .klassen)
        let zweite = try #require(s.rueckfrage)
        #expect(zweite.text == s.lernende.sperrhinweis && zweite.ablehnung == "" && zweite.ort == .klassen)
        s.rueckfrageBeantworten(true)

        // Aus dem Hauptfenster bleibt es die Meldung — dort ist die Kapsel zu sehen.
        s.offenerDialog = nil
        s.lernendenBlattOeffnen()
        #expect(s.rueckfrage == nil && s.meldungen.last?.text == s.lernende.sperrhinweis)
    }

    @Test("Zusammenfassung und Hilfetext (E356, E508): gezählt wie die Unterzeile des Blatts — aktive Personen und Lerngruppen")
    func zusammenfassung() async throws {
        let ablage = try ordner("zahl")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        #expect(s.lernendenZusammenfassung == "0 Personen in 0 Lerngruppen", "ohne Jahresdatei")
        #expect(s.lernendenKnopfhilfe == "Die Lernendenverwaltung öffnen (⌘L)")
        let a = try #require(s.lernendenEntwurfBeginnen())
        let (b, g) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: a.erstellt))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna").namen, inGruppe: g, jetzt: a.erstellt).bestand
        #expect(s.lernendenUebernehmen(c) == nil)
        #expect(s.lernendenZusammenfassung == "1 Person in 1 Lerngruppe")
        let (d, ag) = try #require(c.mitNeuerGruppe(name: "Theater", art: .kurs, jetzt: a.erstellt))
        let e = d.mitPersonen(Namenszeilen.lesen("Bauer, Ben\nCelik, Cem").namen, inGruppe: ag, jetzt: a.erstellt).bestand
        let cem = try #require(e.lernende.first { $0.nachname == "Celik" }).id
        let f = e.mitArchivierterGruppe(g, jetzt: a.erstellt).mitArchiviertenPersonen([cem], jetzt: a.erstellt)
        #expect(s.lernendenUebernehmen(f) == nil)
        #expect(s.lernendenZusammenfassung == "2 Personen in 1 Lerngruppe", "archivierte zählen nicht")

        s.lernende.schliessen()
        #expect(s.lernendenZusammenfassung == s.lernende.sperrhinweis && s.lernendenKnopfhilfe == s.lernende.sperrhinweis)
        #expect(s.lerngruppenhilfeOhneVerwaltung == s.lernende.sperrhinweis, "am Personen-Symbol ebenso (E510)")

        let ohne = try ordner("aus")
        defer { try? FileManager.default.removeItem(at: ohne) }
        let aus = Planungsspeicher(ablage: Ablage(ordner: ohne))
        aus.planung = try planung()
        #expect(aus.lernende.quelle == .aus)
        #expect(aus.lernendenZusammenfassung == "keine Lernendenverwaltung — nur mit eingeschalteter Verschlüsselung")
        #expect(aus.lernendenKnopfhilfe == "Lernendenverwaltung — nur mit eingeschalteter Verschlüsselung")
        #expect(aus.lerngruppenhilfeOhneVerwaltung == "Lerngruppe — nur mit eingeschalteter Verschlüsselung")
    }

    @Test("Eine Zählzeile für die Unterzeile des Blatts und die Zusammenfassung in ⌘K (Z-AT4-03)")
    func zaehlzeile() {
        #expect(Lernendenblatt.zaehlzeile(personen: 0, gruppen: 0) == "0 Personen in 0 Lerngruppen")
        #expect(Lernendenblatt.zaehlzeile(personen: 1, gruppen: 1) == "1 Person in 1 Lerngruppe")
        #expect(Lernendenblatt.zaehlzeile(personen: 2, gruppen: 1) == "2 Personen in 1 Lerngruppe")
        #expect(Lernendenblatt.zaehlzeile(personen: 12, gruppen: 2) == "12 Personen in 2 Lerngruppen")
    }
}
