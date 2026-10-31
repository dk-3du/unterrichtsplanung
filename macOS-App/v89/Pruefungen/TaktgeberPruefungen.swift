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

// ── Der Taktgeber (v84, AT6f-1, E548, E560, E562, E563) ─────────────────────
// Die Zeitgeber des Speichers gehen über `takt`: im Betrieb der Systemtakt, hier der Taktschreiber, der nur mitschreibt
// und nie vorrückt. Die Prüfungen halten fest, wo welcher Takt gilt, dass der Systemtakt die Mittel von vorher nutzt,
// und die Standardwerte je Auslöser. Gewartet wird nur auf das Mitschreiben (`abwarten`) oder auf das Ende einer
// Aufgabe, nie auf Zeit.

@Suite("Taktgeber: Systemtakt im Betrieb, Standardwerte je Auslöser")
@MainActor
struct TaktgeberPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "taktgeber-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// Ein Speicher auf dem Schreiber; mit Planung, wo es eine braucht.
    private func speicher(_ ablage: URL, _ schreiber: Taktschreiber, planung: Bool = false) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.takt = schreiber
        if planung {
            s.planung = Planung.leer(titel: "Takt", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                                     klassen: [], fachfarben: [:])
        }
        return s
    }

    /// Was der Schreiber verlangt bekam, sobald es `anzahl` Dauern sind — `warten` verlangt erst, wenn seine Aufgabe läuft.
    private func verlangt(_ schreiber: Taktschreiber, anzahl: Int = 1, _ was: String,
                          sourceLocation: SourceLocation = #_sourceLocation) async throws -> [Taktschreiber.Verlangt] {
        try await abwarten(was, sourceLocation: sourceLocation) { schreiber.verlangt.count >= anzahl }
        return schreiber.verlangt
    }

    @Test("Im Betrieb der Systemtakt; der Takt des Speichers gilt mit für Sicherung, Titel und Updates")
    func verdrahtung() throws {
        let ablage = try ordner("verdrahtung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        #expect(s.takt is Systemtakt && s.sicherung.takt is Systemtakt && s.titelentpreller.takt is Systemtakt
                && s.updates.takt is Systemtakt, "im Betrieb überall der Systemtakt")
        #expect(Entpreller().takt is Systemtakt, "die Entpreller der Blätter")
        let schreiber = Taktschreiber()
        defer { schreiber.abraeumen() }
        s.takt = schreiber
        #expect(s.sicherung.takt === schreiber && s.titelentpreller.takt === schreiber && s.updates.takt === schreiber)
    }

    @Test("Der Systemtakt: `nach` und `gleich` laufen nicht im Aufruf, sondern danach; `warten` kehrt zurück und endet mit dem Abbruch seiner Aufgabe")
    func systemtakt() async throws {
        let takt = Systemtakt.gemeinsam
        let liste = Liste()
        // `nach(0)` und `warten(.zero)` rufen die echten Mittel mit 0 s auf und warten damit auf keine Dauer; `abwarten`
        // wartet nur auf ihr Ergebnis — keine weitere Uhr (E564). Die Dauer reichen `nach` und `warten` an `asyncAfter`
        // und `Task.sleep(for:)` durch; dass sie voll gewartet wird, zeigte nur eine Uhr (Z-AT6f1-03).
        takt.nach(0) { liste.werte.append("nach") }
        #expect(liste.werte.isEmpty, "nicht im Aufruf")
        try await abwarten("`nach` läuft danach") { liste.werte == ["nach"] }
        let ohneFrist = takt.gleich { liste.werte.append("gleich") }
        #expect(liste.werte == ["nach"], "`gleich` nicht im Aufruf")
        await ohneFrist.value
        #expect(liste.werte == ["nach", "gleich"], "`gleich` läuft danach")
        Task { @MainActor in
            do {
                try await takt.warten(.zero)
                liste.werte.append("zurück")
            } catch {
                liste.werte.append("Fehler")
            }
        }
        try await abwarten("`warten` kehrt zurück") { liste.werte.count == 3 }
        // Abgebrochen, ehe die Aufgabe läuft: Auch hier wartet nichts auf Zeit.
        let abgebrochen = Task { @MainActor in
            do {
                try await takt.warten(.seconds(60))
                liste.werte.append("ohne Abbruch zurück")
            } catch {
                liste.werte.append(Task.isCancelled ? "abgebrochen" : "anderer Fehler")
            }
        }
        abgebrochen.cancel()
        try await abwarten("`warten` endet mit dem Abbruch") { liste.werte.count == 4 }
        #expect(liste.werte == ["nach", "gleich", "zurück", "abgebrochen"])
    }

    @Test("PRUEFTAKT im Prüfziel: dehnen ×10, stauchen ×0, ohne Wert ×1; ein anderer Wert ist kein Faktor (E551)")
    func prueftakt() throws {
        #expect(Systemtakt.faktorVon(nil) == 1)
        #expect(Systemtakt.faktorVon("dehnen") == 10)
        #expect(Systemtakt.faktorVon("stauchen") == 0)
        #expect(Systemtakt.faktorVon("dehen") == nil, "ein Tippfehler dehnt nichts")
        // Der Faktor dieses Laufs: Mit einem unbekannten Wert liefe die Probe still mit den Fristen des Betriebs.
        let wert = ProcessInfo.processInfo.environment["PRUEFTAKT"]
        let faktor = try #require(Systemtakt.faktorVon(wert), "PRUEFTAKT=\(wert ?? "") ist weder dehnen noch stauchen")
        #expect(Systemtakt.faktor == faktor)
    }

    @Test("Der Taktschreiber rückt nie vor: Handlungen nur von Hand, Wartende enden erst mit dem Abbruch — dann abgebrochen")
    func taktschreiber() async throws {
        let schreiber = Taktschreiber()
        defer { schreiber.abraeumen() }
        let liste = Liste()
        schreiber.nach(0) { liste.werte.append("Handlung") }
        let erster = Task { @MainActor in
            try? await schreiber.warten(.zero)
            liste.werte.append(Task.isCancelled ? "erster abgebrochen" : "erster zurück")
        }
        Task { @MainActor in
            try? await schreiber.warten(.zero)
            liste.werte.append(Task.isCancelled ? "zweiter abgebrochen" : "zweiter zurück")
        }
        try await abwarten("beide warten") { schreiber.offen == 3 }
        #expect(liste.werte.isEmpty, "nichts läuft von selbst, auch nicht nach 0 s")
        erster.cancel()
        try await abwarten("der Abbruch weckt den ersten") { liste.werte.count == 1 }
        #expect(liste.werte == ["erster abgebrochen"])
        let ausgeloest = schreiber.ausloesen()
        #expect(ausgeloest && liste.werte.last == "Handlung", "von Hand, im Aufruf")
        let nochEine = schreiber.ausloesen()
        #expect(!nochEine, "keine Handlung mehr offen")
        schreiber.abraeumen()
        try await abwarten("das Abräumen weckt den zweiten") { liste.werte.count == 3 }
        Task { @MainActor in
            try? await schreiber.warten(.seconds(1))
            liste.werte.append(Task.isCancelled ? "dritter abgebrochen" : "dritter zurück")
        }
        try await abwarten("nach dem Abräumen endet `warten` gleich") { liste.werte.count == 4 }
        #expect(liste.werte == ["erster abgebrochen", "Handlung", "zweiter abgebrochen", "dritter abgebrochen"],
                "abgeräumt heißt abgebrochen — ein Sichern oder Entpreller dahinter läuft nicht (Z-AT6f-01)")
        #expect(schreiber.offen == 0)
        #expect(schreiber.verlangt == [.nach(0), .warten(.zero), .warten(.zero), .warten(.seconds(1))])
    }

    @Test("Verfall der Meldungen: die Warnung nach 5,2 s, der Hinweis nach 2,8 s")
    func verfall() async throws {
        let ablage = try ordner("verfall")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let schreiber = Taktschreiber()
        defer { schreiber.abraeumen() }
        let s = try speicher(ablage, schreiber)
        s.melden("Eine Warnung", .warnung)
        let warnung = try await verlangt(schreiber, "die Warnung verlangt ihren Verfall")
        #expect(warnung == [.warten(.milliseconds(5200))])
        s.melden("Ein Hinweis")
        let beide = try await verlangt(schreiber, anzahl: 2, "der Hinweis verlangt seinen Verfall")
        #expect(beide == [.warten(.milliseconds(5200)), .warten(.milliseconds(2800))])
        #expect(s.meldungen.map(\.text) == ["Eine Warnung", "Ein Hinweis"], "ohne Vorrücken verfällt nichts")
    }

    @Test("Fortsetzung nach 0,35 s; blendet das Alert noch aus, alle 0,05 s erneut — 50-mal, der 51. Lauf setzt fort (E563)")
    func fortsetzung() throws {
        let ablage = try ordner("fortsetzung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let schreiber = Taktschreiber()
        defer { schreiber.abraeumen() }
        let s = try speicher(ablage, schreiber)
        s.rueckfrageSichtbar = { true }
        let liste = Liste()
        s.nachDerAntwort { liste.werte.append("fortgesetzt") }
        #expect(schreiber.verlangt == [.nach(0.35)], "im Aufruf verlangt")
        for _ in 1...50 { schreiber.ausloesen() }
        #expect(liste.werte.isEmpty && s.ausstehendeFortsetzungen == 1, "nach 50 Versuchen steht sie noch aus")
        #expect(schreiber.verlangt == [.nach(0.35)] + Array(repeating: .nach(0.05), count: 50))
        let einundfuenfzigster = schreiber.ausloesen()
        #expect(einundfuenfzigster, "der 51. Lauf")
        #expect(liste.werte == ["fortgesetzt"] && s.ausstehendeFortsetzungen == 0 && schreiber.offen == 0)
        #expect(schreiber.verlangt.count == 51, "danach verlangt sie nichts mehr")
    }

    @Test("Nachholen einer wartenden Frage nach 0,7 s")
    func nachholen() throws {
        let ablage = try ordner("nachholen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let schreiber = Taktschreiber()
        defer { schreiber.abraeumen() }
        let s = try speicher(ablage, schreiber, planung: true)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Zweite", bestaetigung: "Ja") {}
        #expect(schreiber.verlangt.isEmpty, "solange die erste steht, nichts")
        s.rueckfrageBeantworten(false)
        #expect(schreiber.verlangt == [.nach(0.7)])
    }

    @Test("Sichern nach einer Änderung: entprellt um 700 ms")
    func sichern() async throws {
        let ablage = try ordner("sichern")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let schreiber = Taktschreiber()
        defer { schreiber.abraeumen() }
        let s = try speicher(ablage, schreiber, planung: true)
        s.titelSetzen("Sichern")
        let sichern = try await verlangt(schreiber, "das Sichern verlangt seine Entprellung")
        #expect(sichern == [.warten(.milliseconds(700))])
    }

    @Test("Titel: entprellt um 400 ms")
    func titel() async throws {
        let ablage = try ordner("titel")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let schreiber = Taktschreiber()
        defer { schreiber.abraeumen() }
        let s = try speicher(ablage, schreiber, planung: true)
        defer { s.titelentpreller.abbrechen() }
        s.planungstitel = "Entprellt"
        #expect(s.planung?.titel == "Takt", "nicht im Aufruf geschrieben — entprellt (Z-AT6f1-05)")
        // Der Entpreller gilt im ganzen Prozess: Löst eine Nachbarsuite mit `allesUebernehmen` den Titel früher aus,
        // verlangt das Sichern dahinter 700 ms (N-08) — das zählt hier nicht.
        let titel = { schreiber.verlangt.filter { $0 != .warten(.milliseconds(700)) } }
        try await abwarten("der Titel verlangt seine Entprellung") { !titel().isEmpty }
        s.titelentpreller.abbrechen()
        #expect(titel() == [.warten(.milliseconds(400))])
    }

    @Test("Meldung nach der Tour: 300 ms (E560)")
    func tour() async throws {
        let ablage = try ordner("tour")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let schreiber = Taktschreiber()
        defer { schreiber.abraeumen() }
        let s = try speicher(ablage, schreiber, planung: true)
        s.tourBeginnen()
        s.tourBeenden()
        let tour = try await verlangt(schreiber, "die Tour verlangt ihre Meldung")
        #expect(tour == [.warten(.milliseconds(300))])
        #expect(s.meldungen.isEmpty, "die Meldung kommt erst nach der Frist")
    }

    @Test("Prüfung auf Updates beim Start: 3 s nach dem Anstoß (E560)")
    func updates() async throws {
        let ablage = try ordner("updates")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let schreiber = Taktschreiber()
        defer { schreiber.abraeumen() }
        let s = try speicher(ablage, schreiber)
        let angestossen = s.updates.beimStartPruefen(hatPlanung: true)
        #expect(angestossen)
        let updates = try await verlangt(schreiber, "die Prüfung beim Start verlangt ihre Frist")
        #expect(updates == [.warten(.seconds(3))])
    }
}
