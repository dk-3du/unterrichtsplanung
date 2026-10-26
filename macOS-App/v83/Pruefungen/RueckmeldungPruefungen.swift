// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Rückmeldungen der Sicherung kommen in der Reihenfolge an, in der sie fertig
/// werden — nicht in der, in der sie losgeschickt wurden (N57-02, E91).
///
/// Geschrieben wird geordnet: Die Sicherungsfolge nimmt unter derselben Sperre
/// nur Nummern an, die größer sind als die zuletzt geschriebene — alte Byte
/// können jüngere nicht überholen. Ungeordnet war bisher, was danach kommt: Wer
/// als Letzter zurückkommt, setzte die Merker und die Störung. Ein alter Erfolg
/// löschte damit einen jungen Fehlschlag, ein alter Fehlschlag meldete eine
/// überholte Störung.
@Suite("Rückmeldungen der Sicherung")
struct RueckmeldungPruefungen {

    /// Hält die Veröffentlichung an, bis der Lauf sie freigibt (E92).
    ///
    /// Aufgabenweit wie die Prüfuhr: Prüfläufe laufen nebeneinander, und eine
    /// Naht für alle brächte die anderen durcheinander (Lehre aus E81).
    /// **Ohne Uhr (E145):** drei Fortsetzungen statt Schleifen — „erreicht“,
    /// „frei“, „durch“. Wer `durchAbwarten()` zurückbekommt, weiß auch, dass
    /// die Veröffentlichung gelaufen ist: Nach der Naht geht
    /// `imHintergrundSichern` ohne weiteres `await` bis `uebernehmen`, und ein
    /// wiederaufgenommener Prüflauf kommt erst danach zu Wort.
    @MainActor final class Naht {
        private(set) var erreicht = false
        private(set) var durch = false
        private(set) var frei = false
        private var aufErreicht: CheckedContinuation<Void, Never>?
        private var aufFrei: CheckedContinuation<Void, Never>?
        private var aufDurch: CheckedContinuation<Void, Never>?

        var halten: @Sendable @MainActor (Int) async -> Void {
            { [self] _ in
                erreicht = true
                aufErreicht?.resume(); aufErreicht = nil
                if !frei { await withCheckedContinuation { aufFrei = $0 } }
                durch = true
                aufDurch?.resume(); aufDurch = nil
            }
        }

        /// Die Hintergrundsicherung steht an der Naht.
        func erreichtAbwarten() async {
            if !erreicht { await withCheckedContinuation { aufErreicht = $0 } }
        }

        /// Die Naht öffnen — die Veröffentlichung läuft.
        func freigeben() {
            frei = true
            aufFrei?.resume(); aufFrei = nil
        }

        /// Die Veröffentlichung ist gelaufen (siehe oben).
        func durchAbwarten() async {
            if !durch { await withCheckedContinuation { aufDurch = $0 } }
        }
    }

    private func planung() throws -> Planung {
        Planung.leer(titel: "Rückmeldung", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                     basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                     fachfarben: [:])
    }

    private func ablage() throws -> (Ablage, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "rueck-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return (Ablage(ordner: ordner), ordner)
    }

    // ── Der alte Erfolg ───────────────────────────────────────────────────

    @MainActor
    @Test("Ein alter Erfolg löscht keinen jungen Fehlschlag (N57-02)")
    func alterErfolgLoeschtNichts() async throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: ablage)
        s.planung = try planung()
        s.titelSetzen("A")
        s.jetztSichern()
        #expect(s.sicherung.stoerung == nil, "der erste Stand liegt")

        let naht = Naht()
        try await Sicherungsnaht.gestellt(naht.halten) {
            // A schreibt im Hintergrund und bleibt vor der Veröffentlichung stehen.
            s.titelSetzen("B")
            s.sichern()
            await naht.erreichtAbwarten()
            #expect(naht.erreicht, "die Hintergrundsicherung steht an der Naht")

            // Dazwischen legt sich ein fremder Behälter auf die Platte: Der
            // gleichlaufende Weg weist ab und meldet die Störung.
            let fremd = Tresor.neu()
            try fremd.versiegeln(Data("fremd".utf8), inhalt: .planung, ziel: .ablage)
                .write(to: ablage.datei)
            s.titelSetzen("C")
            s.jetztSichern()
            let gemeldet = try #require(s.sicherung.stoerung, "die junge Rückmeldung meldet")

            // Jetzt kommt A nach — und sagt nichts mehr über den Stand.
            naht.freigeben()
            await naht.durchAbwarten()

            #expect(s.sicherung.stoerung == gemeldet, "die jüngere Störung bleibt stehen")
            #expect(s.sicherung.ungesichert, "und der Stand gilt weiter als nicht geschrieben")
        }
    }

    // ── Der alte Fehlschlag ───────────────────────────────────────────────

    @MainActor
    @Test("Ein alter Fehlschlag meldet keine überholte Störung (N57-02)")
    func alterFehlschlagMeldetNicht() async throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: ablage)
        s.planung = try planung()
        s.titelSetzen("A")
        s.jetztSichern()

        // Ein fremder Behälter liegt im Weg: Die Hintergrundsicherung wird
        // abgewiesen — und bleibt mit ihrem Fehlschlag an der Naht stehen.
        let fremd = Tresor.neu()
        try fremd.versiegeln(Data("fremd".utf8), inhalt: .planung, ziel: .ablage)
            .write(to: ablage.datei)
        let naht = Naht()
        try await Sicherungsnaht.gestellt(naht.halten) {
            s.titelSetzen("B")
            s.sichern()
            await naht.erreichtAbwarten()
            #expect(naht.erreicht)

            // Das Hindernis ist fort, der gleichlaufende Weg schreibt.
            try FileManager.default.removeItem(at: ablage.datei)
            s.titelSetzen("C")
            s.jetztSichern()
            #expect(s.sicherung.stoerung == nil, "geschrieben, nichts zu melden")
            #expect(!s.sicherung.ungesichert)

            // Der alte Fehlschlag kommt nach: Er gilt nicht mehr.
            naht.freigeben()
            await naht.durchAbwarten()

            #expect(s.sicherung.stoerung == nil, "eine überholte Störung wird nicht gemeldet")
            #expect(!s.sicherung.ungesichert, "und der geschriebene Stand bleibt geschrieben")
        }
    }

    // ── Die Regel selbst ──────────────────────────────────────────────────

    @MainActor
    @Test("Die Schranke lässt nur vorwärts durch")
    func schrankeGehtNurVorwaerts() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let dienst = Planungsspeicher(ablage: ablage).sicherung
        #expect(dienst.rueckmeldungGilt(5))
        #expect(!dienst.rueckmeldungGilt(4), "älter als die zuletzt veröffentlichte")
        #expect(!dienst.rueckmeldungGilt(5), "und dieselbe zweimal gilt auch nicht")
        #expect(dienst.rueckmeldungGilt(6))
    }

    @MainActor
    @Test("Die Naht steht nur, wo sie gestellt wurde")
    func nahtNurWoGestellt() async {
        // Sie steht unter derselben Schranke wie die Prüfuhr: aufgabenweit, und
        // außerhalb des Prüfziels wirkungslos.
        #expect(Pruefziel.ja, "dieser Lauf ist das Prüfziel")
        #expect(Sicherungsnaht.halten == nil, "hier ist keine gestellt")
        await Sicherungsnaht.gestellt({ _ in }) {
            #expect(Sicherungsnaht.halten != nil, "und drinnen schon")
        }
        #expect(Sicherungsnaht.halten == nil, "danach wieder nicht")
    }
}
