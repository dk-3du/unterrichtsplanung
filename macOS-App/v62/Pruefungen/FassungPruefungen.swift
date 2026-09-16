// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Die Sicherung unterscheidet ihre Fassungen am Inhalt, nicht am Stempel (N56-02, E80).
///
/// Der Zeitstempel sagt, wann zuletzt geändert wurde; er sagt nicht, *was*
/// geändert wurde. Zwei Änderungen in derselben Millisekunde tragen denselben —
/// wer daran „liegt schon“ festmacht, verwirft die zweite stillschweigend und
/// verbucht sie zugleich als geschrieben. Darum: unten der Abdruck der Byte,
/// oben ein Zähler, der jede angemeldete Änderung zählt.
@Suite("Fassung statt Stempel")
struct FassungPruefungen {

    private func planung() throws -> Planung {
        Planung.leer(titel: "Fassung", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                     basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                     fachfarben: [:])
    }

    private func ablage() throws -> (Ablage, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "fassung-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return (Ablage(ordner: ordner), ordner)
    }

    // ── Unten: die Sicherungsfolge ────────────────────────────────────────

    @Test("Andere Byte — geschrieben wird, ohne Ansehen der Uhr")
    func andererInhaltUnterEinemStempel() throws {
        // Die Folge kennt gar keinen Stempel mehr: Sie sieht nur die Byte.
        // Vorher entschied der Stempel, und zwei Änderungen in derselben
        // Millisekunde tragen denselben (N56-02).
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let folge = Sicherungsfolge(ablage: ablage, hoechstens: Sicherungsdienst.schreibgrenze)
        let a = Data("{\"stand\":\"A\"}".utf8)
        let b = Data("{\"stand\":\"B — etwas ganz anderes\"}".utf8)

        #expect(try folge.schreiben(nummer: folge.naechsteNummer(), daten: a, tresor: nil) == .geschrieben(a.count))
        let zweit = try folge.schreiben(nummer: folge.naechsteNummer(), daten: b, tresor: nil)
        #expect(zweit == .geschrieben(b.count), Comment(rawValue: "die Folge meldet \(zweit)"))
        #expect(try Data(contentsOf: ablage.datei) == b, "auf der Platte liegt der zweite Stand")
    }

    @Test("Gleiche Byte — nichts zu tun, auch später noch")
    func gleicherInhaltNeuerStempel() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let folge = Sicherungsfolge(ablage: ablage, hoechstens: Sicherungsdienst.schreibgrenze)
        let a = Data("{\"stand\":\"A\"}".utf8)

        #expect(try folge.schreiben(nummer: folge.naechsteNummer(), daten: a, tresor: nil) == .geschrieben(a.count))
        // Dieselbe Planung, ein zweiter Anlass: Die Platte trägt sie schon.
        #expect(try folge.schreiben(nummer: folge.naechsteNummer(), daten: a, tresor: nil) == .unveraendert)
        #expect(!FileManager.default.fileExists(atPath: ablage.vorherigeFassung.path),
                "und es entsteht auch keine Fassung davor")
    }

    @Test("Ein Behälter zählt nach seinem Klartext, nicht nach seinen Byte")
    func versiegeltNachKlartext() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let folge = Sicherungsfolge(ablage: ablage, hoechstens: Sicherungsdienst.schreibgrenze)
        let tresor = Tresor.neu()
        let a = Data("{\"stand\":\"A\"}".utf8)
        // Zweimal derselbe Klartext ergibt zwei verschiedene Behälter (neuer
        // Nonce) — hingelegt wird er einmal.
        #expect(try folge.schreiben(nummer: folge.naechsteNummer(), daten: a, tresor: tresor) != .unveraendert)
        #expect(try folge.schreiben(nummer: folge.naechsteNummer(), daten: a, tresor: tresor) == .unveraendert)
    }

    // ── Die angehaltene Uhr (E81) ─────────────────────────────────────────

    @Test("Die Uhr lässt sich für den Prüflauf anhalten")
    func uhrHaeltAn() {
        let angehalten = Pruefuhr.angehalten(Date(timeIntervalSince1970: 1_800_000_000)) {
            let erst = Zeitrechnung.jetztAlsZeitstempel()
            #expect(erst == Zeitrechnung.jetztAlsZeitstempel(), "zweimal derselbe")
            return erst
        }
        #expect(angehalten == "2027-01-15T08:00:00.000Z", Comment(rawValue: angehalten))
        #expect(Zeitrechnung.jetztAlsZeitstempel() != angehalten, "danach geht sie wieder")
    }

    // ── Oben: der Weg durch die App ───────────────────────────────────────

    @MainActor
    @Test("Zwei Änderungen unter einem Stempel: die zweite liegt auf der Platte")
    func zweiAenderungenUnterEinemStempel() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: ablage)
        s.planung = try planung()

        try Pruefuhr.angehalten {
            s.titelSetzen("Fassung A")
            s.jetztSichern()
            let nachA = try Data(contentsOf: ablage.datei).text
            #expect(nachA.contains("Fassung A"))

            s.titelSetzen("Fassung B")
            #expect(s.planung?.geaendert == s.sicherung.gesicherterStand,
                    "die Uhr steht: beide Fassungen tragen denselben Stempel")
            #expect(s.sicherung.ungesichert, "und die App weiß, dass etwas aussteht")
            s.jetztSichern()

            let nachB = try Data(contentsOf: ablage.datei).text
            #expect(nachB.contains("Fassung B"),
                    "die zweite Änderung darf nicht stillschweigend entfallen")
            #expect(!s.sicherung.ungesichert, "und danach steht nichts mehr aus")
        }
    }

    @MainActor
    @Test("Ein von außen eingesetzter Stand wird geschrieben, auch ohne angemeldete Änderung")
    func standVonAussenEingesetzt() throws {
        // Diesen Weg gehen Export (`exportSchreiben` hebt den Stempel und ruft
        // `jetztSichern()`), Import, Statusstand und die Rettungswege: Sie setzen
        // eine Planung ein, ohne eine Änderung anzumelden. Der Zähler allein
        // sähe das nicht — darum entscheidet er zusammen mit dem Stempel.
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: ablage)
        s.planung = try planung()
        s.titelSetzen("Fassung A")
        s.jetztSichern()
        #expect(!s.sicherung.ungesichert)

        // Von außen eingesetzt: neue Planung, neuer Stempel, kein `sichern()`.
        var eingesetzt = try #require(s.planung)
        eingesetzt.titel = "Von außen"
        eingesetzt.geaendert = "2030-01-01T00:00:00.000Z"
        s.planung = eingesetzt
        #expect(!s.sicherung.ungesichert, "angemeldet ist nichts — der Zähler steht still")
        s.jetztSichern()

        let liegt = try Data(contentsOf: ablage.datei).text
        #expect(liegt.contains("Von außen"), "geschrieben wird trotzdem")
    }

    @MainActor
    @Test("Auch entprellt geht die zweite Änderung nicht verloren")
    func entprelltUnterEinemStempel() async throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: ablage)
        s.planung = try planung()

        try await Pruefuhr.angehalten {
            s.titelSetzen("Fassung A")
            s.jetztSichern()
            s.titelSetzen("Fassung B")
            s.sichern()
            for _ in 0..<60 where s.sicherung.ungesichert {
                try await Task.sleep(for: .milliseconds(50))
            }
            let liegt = try Data(contentsOf: ablage.datei).text
            #expect(liegt.contains("Fassung B"))
        }
    }
}

private extension Data {
    var text: String { String(data: self, encoding: .utf8) ?? "" }
}
