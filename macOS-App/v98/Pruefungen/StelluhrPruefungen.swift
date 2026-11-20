// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

@MainActor
private final class Liste {
    var werte: [String] = []
}

// ── Die Stelluhr (v84, AT6f-2, E548, E565) ─────────────────────────────────
// Die Regeln der Stelluhr, auf die AT6g baut, und an den Zeitgebern des Speichers die Grenzen: Ein Zeitgeber läuft, wenn
// die Uhr seine Frist erreicht — nicht früher, nicht später —, und was er über den Taktgeber auslöst, ist zu Ende, wenn
// `vorruecken` zurückkehrt, soweit seine Frist im Schritt liegt. `abwarten` steht nur dort, wo eine Aufgabe ohne die Uhr
// enden muss: rot statt Hängen.
// Den Titel-Entpreller prüft hier keine Grenze: Entpreller gelten im ganzen Prozess, und während die Uhr auf das Ende
// einer Aufgabe wartet, bricht `allesAbbrechen` einer Nachbarsuite ihn ab (N-08) — seinen Wert hält TaktgeberPruefungen.

@Suite("Stelluhr: Folge der Fristen, Ende der Aufgaben, Grenzen der Zeitgeber")
@MainActor
struct StelluhrPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "stelluhr-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// Ein Speicher auf der Stelluhr; mit Planung, wo es eine braucht.
    private func speicher(_ ablage: URL, _ uhr: Stelluhr, planung: Bool = false) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.takt = uhr
        if planung {
            s.planung = Planung.leer(titel: "Takt", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                                     klassen: [], fachfarben: [:])
        }
        return s
    }

    // ── Regeln ──

    @Test("In der Folge der Fristen, gleiche Fristen in der Folge der Anmeldung — in einem Schritt und über Schritte (Z-AT6e-02)")
    func folgeDerFristen() async {
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let folge = Liste()
        uhr.nach(0.35) { folge.werte.append("A") }
        uhr.nach(0.35) { folge.werte.append("B") }
        uhr.nach(0.1) { folge.werte.append("C") }
        await uhr.vorruecken(um: .milliseconds(350))
        #expect(folge.werte == ["C", "A", "B"], "in einem Schritt")
        folge.werte = []
        uhr.nach(0.35) { folge.werte.append("früh angemeldet") }
        await uhr.vorruecken(um: .milliseconds(100))
        uhr.nach(0.25) { folge.werte.append("spät angemeldet") }
        await uhr.vorruecken(um: .milliseconds(250))
        #expect(folge.werte == ["früh angemeldet", "spät angemeldet"], "gleiche Frist aus zwei Schritten")
        #expect(uhr.ausstehend == 0 && uhr.jetzt == .milliseconds(700))
    }

    @Test("Handlungen und Aufgaben mit gleicher Frist laufen in der Folge der Anmeldung — angemeldet wird im Aufruf")
    func handlungUndAufgabe() async {
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let folge = Liste()
        uhr.nach(0.4) { folge.werte.append("Handlung") }
        uhr.aufgabe(nach: .milliseconds(400)) { folge.werte.append("Aufgabe") }
        uhr.nach(0.4) { folge.werte.append("zweite Handlung") }
        #expect(uhr.ausstehend == 3, "alle drei im Aufruf angemeldet")
        await uhr.vorruecken(um: .milliseconds(400))
        #expect(folge.werte == ["Handlung", "Aufgabe", "zweite Handlung"])
    }

    @Test("Keine Aufgabe läuft vor ihrer Frist — auch wenn die Uhr derweil auf eine frühere wartet (Z-AT6f2-02)")
    func nichtVorDerFrist() async {
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let folge = Liste()
        uhr.aufgabe(nach: .milliseconds(500)) { folge.werte.append("später") }
        uhr.aufgabe(nach: .milliseconds(100)) { folge.werte.append("früher") }
        await uhr.vorruecken(um: .milliseconds(499))
        #expect(folge.werte == ["früher"] && uhr.ausstehend == 1,
                "während die Uhr das Ende der früheren abwartete, blieb die spätere am Tor")
        await uhr.vorruecken(um: .milliseconds(1))
        #expect(folge.werte == ["früher", "später"])
    }

    @Test("Was ein Zeitgeber neu anmeldet, zählt ab seiner Frist — auch in einem großen Schritt (Z-AT6f-02)")
    func ketteInEinemSchritt() async {
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let folge = Liste()
        uhr.nach(0.35) {
            folge.werte.append("X")
            uhr.nach(0.05) { folge.werte.append("X′") }
        }
        uhr.aufgabe(nach: .milliseconds(380)) {
            folge.werte.append("Z")
            uhr.aufgabe(nach: .milliseconds(30)) { folge.werte.append("Z′") }
        }
        uhr.nach(0.42) { folge.werte.append("Y") }
        await uhr.vorruecken(um: .milliseconds(500))
        #expect(folge.werte == ["X", "Z", "X′", "Z′", "Y"], "wie im Betrieb: X′ bei 0,40 s, Z′ bei 0,41 s, Y bei 0,42 s")
    }

    @Test("Eine Aufgabe ist zu Ende, wenn `vorruecken` zurückkehrt — auch mit Arbeit abseits der Hauptwarteschlange")
    func endeAbgewartet() async {
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let folge = Liste()
        uhr.aufgabe(nach: .milliseconds(100)) {
            folge.werte.append("vor")
            let ergebnis = await Task.detached { "abseits" }.value
            folge.werte.append(ergebnis)
            uhr.aufgabe(nach: .zero) { folge.werte.append("danach angemeldet") }
        }
        await uhr.vorruecken(um: .milliseconds(100))
        #expect(folge.werte == ["vor", "abseits", "danach angemeldet"])
        #expect(uhr.ausstehend == 0)
    }

    @Test("Ohne Frist (`gleich`): nicht im Aufruf, sondern beim nächsten `vorruecken`, auch um null — bis zu ihrem Ende (E568)")
    func gleichBeimVorruecken() async {
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let folge = Liste()
        uhr.nach(0) { folge.werte.append("Handlung") }
        uhr.gleich {
            folge.werte.append("gleich")
            let ergebnis = await Task.detached { "abseits" }.value
            folge.werte.append(ergebnis)
        }
        #expect(folge.werte.isEmpty && uhr.ausstehend == 2, "nicht im Aufruf")
        await uhr.vorruecken(um: .zero)
        #expect(folge.werte == ["Handlung", "gleich", "abseits"] && uhr.ausstehend == 0)
        #expect(uhr.verlangt == [.nach(0), .gleich])
    }

    @Test("`vorruecken(bis:)` hält nach dem Ereignis an, mit dem die Bedingung gilt — vor dem, das sie wieder aufhebt")
    func vorrueckenBis() async {
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let liste = Liste()
        uhr.nach(0.3) {
            liste.werte.append("da")
            uhr.nach(0.05) { liste.werte.removeAll() }
        }
        let gesehen = await uhr.vorruecken(bis: { liste.werte == ["da"] }, hoechstens: .seconds(1))
        #expect(gesehen && uhr.jetzt == .milliseconds(300) && uhr.ausstehend == 1, "bei 0,3 s, vor dem Verschwinden")
        let schon = await uhr.vorruecken(bis: { liste.werte == ["da"] }, hoechstens: .seconds(1))
        #expect(schon && uhr.jetzt == .milliseconds(300) && uhr.ausstehend == 1, "gilt sie schon, läuft nichts")
        let nie = await uhr.vorruecken(bis: { liste.werte == ["nie"] }, hoechstens: .seconds(1))
        #expect(!nie && uhr.jetzt == .milliseconds(1300) && liste.werte.isEmpty, "gilt sie nie: nein, an der Grenze")
    }

    @Test("Bricht das Programm eine Aufgabe ab, läuft ihre Arbeit gleich und sieht den Abbruch — wie nach `Task.sleep`")
    func abbruchDurchDasProgramm() async throws {
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let folge = Liste()
        let aufgabe = uhr.aufgabe(nach: .milliseconds(400)) {
            folge.werte.append(Task.isCancelled ? "abgebrochen" : "gelaufen")
        }
        aufgabe.cancel()
        #expect(uhr.ausstehend == 0, "abgebrochen zählt nicht — noch ehe ihr Abbruch ausgetragen ist (Z-AT6f2-05)")
        try await abwarten("die abgebrochene Aufgabe läuft") { folge.werte.count == 1 }
        #expect(folge.werte == ["abgebrochen"])
    }

    @Test("Nach dem Abräumen: Handlungen entfallen, Aufgaben laufen abgebrochen — auch was danach noch kommt")
    func abraeumen() async throws {
        let uhr = Stelluhr()
        let folge = Liste()
        uhr.nach(0.1) { folge.werte.append("Handlung") }
        uhr.aufgabe(nach: .seconds(5)) { folge.werte.append(Task.isCancelled ? "abgebrochen" : "gelaufen") }
        uhr.abraeumen()
        try await abwarten("die wartende Aufgabe läuft abgebrochen") { folge.werte.count == 1 }
        uhr.nach(0) { folge.werte.append("Handlung danach") }
        uhr.aufgabe(nach: .seconds(1)) { folge.werte.append(Task.isCancelled ? "danach abgebrochen" : "danach gelaufen") }
        try await abwarten("die spätere Aufgabe läuft gleich abgebrochen") { folge.werte.count == 2 }
        await uhr.vorruecken(um: .seconds(10))
        #expect(folge.werte == ["abgebrochen", "danach abgebrochen"] && uhr.ausstehend == 0,
                "abgeräumt heißt abgebrochen — ein Sichern oder Entpreller dahinter läuft nicht (Z-AT6f-01)")
    }

    // ── Grenzen am Programm ──

    @Test("Verfall: der Hinweis bei 2,79 s noch da, bei 2,81 s fort; die Warnung bei 5,19 s noch da, bei 5,21 s fort")
    func verfallAnDerGrenze() async throws {
        let ablage = try ordner("verfall")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let s = try speicher(ablage, uhr)
        s.melden("Warnung", .warnung)
        s.melden("Hinweis")
        await uhr.vorruecken(um: .milliseconds(2790))
        #expect(s.meldungen.map(\.text) == ["Warnung", "Hinweis"], "2,79 s")
        await uhr.vorruecken(um: .milliseconds(20))
        #expect(s.meldungen.map(\.text) == ["Warnung"], "2,81 s")
        await uhr.vorruecken(um: .milliseconds(2380))
        #expect(s.meldungen.map(\.text) == ["Warnung"], "5,19 s")
        await uhr.vorruecken(um: .milliseconds(20))
        #expect(s.meldungen.isEmpty, "5,21 s")
    }

    @Test("Die Fortsetzung nach einer Antwort läuft bei 0,34 s noch nicht, bei 0,35 s schon")
    func fortsetzungAnDerGrenze() async throws {
        let ablage = try ordner("fortsetzung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let s = try speicher(ablage, uhr)
        s.rueckfrageSichtbar = { false }
        let folge = Liste()
        s.nachDerAntwort { folge.werte.append("fortgesetzt") }
        await uhr.vorruecken(um: .milliseconds(340))
        #expect(folge.werte.isEmpty && s.ausstehendeFortsetzungen == 1, "0,34 s")
        await uhr.vorruecken(um: .milliseconds(10))
        #expect(folge.werte == ["fortgesetzt"] && s.ausstehendeFortsetzungen == 0, "0,35 s")
    }

    @Test("Blendet das Alert aus, versucht die Fortsetzung es alle 0,05 s erneut — 50-mal, dann läuft sie bei 2,85 s")
    func wiederholenBisZurObergrenze() async throws {
        let ablage = try ordner("obergrenze")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let s = try speicher(ablage, uhr)
        s.rueckfrageSichtbar = { true }
        let folge = Liste()
        s.nachDerAntwort { folge.werte.append("fortgesetzt") }
        await uhr.vorruecken(um: .milliseconds(2849))
        #expect(folge.werte.isEmpty, "2,849 s: Das Alert blendet noch aus")
        await uhr.vorruecken(um: .milliseconds(1))
        #expect(folge.werte == ["fortgesetzt"], "2,85 s: Nach 50 Versuchen läuft sie")
        #expect(uhr.verlangt == [.nach(0.35)] + Array(repeating: .nach(0.05), count: 50))
    }

    @Test("Sichern: 700 ms nach der Änderung geschrieben — fertig, wenn `vorruecken` zurückkehrt (Schreiben im Hintergrund, N-01)")
    func sichernAnDerGrenze() async throws {
        let ablage = try ordner("sichern")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let s = try speicher(ablage, uhr, planung: true)
        s.titelSetzen("Gesichert")
        #expect(s.sicherung.ungesichert)
        await uhr.vorruecken(um: .milliseconds(699))
        #expect(s.sicherung.ungesichert, "0,699 s")
        await uhr.vorruecken(um: .milliseconds(1))
        #expect(!s.sicherung.ungesichert, "0,7 s: geschrieben")
    }

    @Test("Meldung nach der Tour: bei 0,299 s noch keine, bei 0,3 s da (E560)")
    func tourAnDerGrenze() async throws {
        let ablage = try ordner("tour")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let uhr = Stelluhr()
        defer { uhr.abraeumen() }
        let s = try speicher(ablage, uhr, planung: true)
        s.tourBeginnen()
        s.tourBeenden()
        await uhr.vorruecken(um: .milliseconds(299))
        #expect(s.meldungen.isEmpty, "0,299 s")
        await uhr.vorruecken(um: .milliseconds(1))
        #expect(s.meldungen.map(\.text) == ["Tour beendet — jederzeit wieder unter Hilfe → Tour durch die Oberfläche."],
                "0,3 s")
    }
}
