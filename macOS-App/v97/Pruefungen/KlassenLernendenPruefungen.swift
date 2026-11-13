// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Weg aus ⌘K zur Lernendenverwaltung (v84, AT4) ─────────────────────
// Bis v96 in ⌘K ein Eintrag „Lernende“ mit Knopf und Zusammenfassung (E356, E1130); seit v97 ein eigener Knopf in der
// Werkzeugleiste (E1258, E1260). Aus ⌘K führt nur noch das Personen-Symbol einer Zeile zum Blatt (E505) — danach geht es
// zurück zu ⌘K (E358). Ist die Verwaltung versiegelt oder gesperrt, fragt ⌘K mit einem Knopf, statt hinter dem Blatt zu
// melden (E357).

@Suite("Weg zur Lernendenverwaltung: aus ⌘K mit Rückweg, Rückfrage bei versiegelt oder gesperrt, Knopf „Lernende“")
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
        neuer["version"] = Lernendendatei.version + 1
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

    @Test("Hilfetext am Knopf „Lernende“ (E508, E1259) und Wortlaut der Tourkarte (E1262): offen, versiegelt, gesperrt, ohne Verschlüsselung — die Zusammenfassung entfiel in v97 (E1260)")
    func knopfhilfe() async throws {
        let ablage = try ordner("zahl")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        #expect(s.lernendenKnopfhilfe == "Die Lernendenverwaltung öffnen (⌘L)")
        // Die Karte „Lernende“ der Tour folgt der Verschlüsselung, nicht dem Blatt (E1262, BI4-03).
        #expect(s.lernende.quelle == .behaelter && s.tourVerschluesselt)
        // Bis v96 baute die Prüfung hier Lerngruppen für die Zusammenfassung in ⌘K auf; die entfiel (E1260, R97-W2-05).
        let tresor = try #require(s.tresor)
        s.lernende.schliessen()
        #expect(s.lernendenKnopfhilfe == s.lernende.sperrhinweis)
        #expect(s.lernende.quelle == .zu && s.tourVerschluesselt, "versiegelt: der Wortlaut mit ⌘L")
        #expect(s.lerngruppenhilfeOhneVerwaltung == s.lernende.sperrhinweis, "versiegelt: am Personen-Symbol ebenso (E510)")

        // Gesperrt (R97-W2-05): eine Jahresdatei in einer neueren Fassung, wie in `gesperrtFragt`.
        let leer = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: "2026-09-01T08:00:00.000Z")
        var neuer = try #require(JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(leer)) as? [String: Any])
        neuer["version"] = Lernendendatei.version + 1
        let neuere = try tresor.versiegeln(try JSONSerialization.data(withJSONObject: neuer), inhalt: .lernende, ziel: .ablage)
        try neuere.write(to: Ablage(ordner: ablage).lernende)
        guard case .gesperrt = s.lernende.oeffnen(mit: tresor, stempel: "s") else {
            Issue.record("erwartet gesperrt")
            return
        }
        #expect(s.lernende.sperrhinweis != nil && s.lernendenKnopfhilfe == s.lernende.sperrhinweis, "gesperrt: der Sperrhinweis")
        #expect(s.tourVerschluesselt, "gesperrt: der Wortlaut mit ⌘L")
        #expect(s.lerngruppenhilfeOhneVerwaltung == s.lernende.sperrhinweis, "gesperrt: am Personen-Symbol ebenso (E510)")

        let ohne = try ordner("aus")
        defer { try? FileManager.default.removeItem(at: ohne) }
        let aus = Planungsspeicher(ablage: Ablage(ordner: ohne))
        aus.planung = try planung()
        #expect(aus.lernende.quelle == .aus)
        #expect(aus.lernendenKnopfhilfe == "Lernendenverwaltung — nur mit eingeschalteter Verschlüsselung")
        #expect(!aus.tourVerschluesselt, "ohne Verschlüsselung: der Wortlaut mit der Rückfrage")
        #expect(aus.lerngruppenhilfeOhneVerwaltung == "Lerngruppe — nur mit eingeschalteter Verschlüsselung")
    }

    @Test("Eine Zählzeile für die Unterzeile des Blatts und die Meldung des Einlesens (Z-AT4-03; ⌘K ohne Zusammenfassung seit v97)")
    func zaehlzeile() {
        #expect(Lernendenblatt.zaehlzeile(personen: 0, gruppen: 0) == "0 Personen in 0 Lerngruppen")
        #expect(Lernendenblatt.zaehlzeile(personen: 1, gruppen: 1) == "1 Person in 1 Lerngruppe")
        #expect(Lernendenblatt.zaehlzeile(personen: 2, gruppen: 1) == "2 Personen in 1 Lerngruppe")
        #expect(Lernendenblatt.zaehlzeile(personen: 12, gruppen: 2) == "12 Personen in 2 Lerngruppen")
        // Mit Tausenderabstand wie die Warnung zum Schuljahr (v90, Hinweis aus Z-BB4b/Z-BB4c): „1 999 Personen …“.
        #expect(Lernendenblatt.zaehlzeile(personen: 1_999, gruppen: 2)
                == "\(Lernendenbestand.tausender(1_999)) Personen in 2 Lerngruppen")
    }
}
