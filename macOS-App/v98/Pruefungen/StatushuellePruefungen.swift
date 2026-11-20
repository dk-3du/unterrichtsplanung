// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Statusdatei in alter Hülle (R97-01, E1311) ────────────────────────────
// Nach „Passphrase ändern“ wickelt die App jede Datei neu. Ein Tab der Web App, der seit vorher offen war, schreibt
// aber weiter Statusdateien in der alten Hülle — die alte Passphrase öffnete sie. Liest die App eine solche Datei unter
// eigenem Schlüssel, wickelt sie sie gleich neu und sagt es einmal. Dazu die Erinnerung im Blatt „Verschlüsselung“
// (R97-04, E1309).

@Suite("Statusdatei in alter Hülle: neu gewickelt beim Einlesen")
@MainActor
struct StatushuellePruefungen {

    init() throws {
        try #require(Ablage.istPruefstand, "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let alt = "Ein Satz, den man behält"
    private let neu = "Ein anderer Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "statushuelle-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Statushülle", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]), fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Bits",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    /// Ein eingeschalteter Speicher mit Zielordner; zurück kommt dazu eine Abschrift des Tresors in seiner ersten Hülle.
    private func eingeschaltet(ablage: URL, ziel: URL) async throws -> (Planungsspeicher, alteHuelle: Tresor) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        s.autoexportZielSetzen(ziel.path)
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: alt))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let t = try #require(s.tresor)
        return (s, Tresor(schluessel: t.schluessel, kennung: t.kennung, wicklungen: t.wicklungen))
    }

    private func stand(_ kommentar: String) -> Statusstand {
        Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(), planungstitel: "Statushülle",
                    eintraege: ["e-1": .init(erledigt: true, kommentar: kommentar)])
    }

    private func schreiben(_ stand: Statusstand, mit tresor: Tresor, nach ziel: URL) throws -> Data {
        let roh = try tresor.versiegeln(try Statusdatei.schreiben(stand), inhalt: .status, ziel: .kopie)
        try roh.write(to: ziel.appending(component: Statusdatei.name), options: [.atomic])
        return roh
    }

    private func hinweise(_ s: Planungsspeicher) -> Int {
        s.meldungen.count(where: { $0.text.contains("Hülle der vorherigen Passphrase") })
    }

    @Test("Alte Hülle: übernommen, gleich neu gewickelt, die alte Passphrase öffnet sie nicht mehr, einmal gesagt")
    func alteHuelleNeuGewickelt() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, alteHuelle) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        #expect(try s.passphraseAendern(alt: alt, neu: neu).offenes.isEmpty)
        let tresor = try #require(s.tresor)
        let vorher = stand("aus dem alten Tab")
        let roh = try schreiben(vorher, mit: alteHuelle, nach: ziel)
        let kopfVorher = try Tresor.kopfLesen(roh)
        try #require(!tresor.huelleGleich(kopfVorher, ziel: .kopie), "Voraussetzung: die Datei trägt die alte Hülle")
        try #require(try Tresor.oeffnen(kopf: kopfVorher, passphrase: alt).kennung == tresor.kennung,
                     "Voraussetzung: die alte Passphrase öffnet sie")

        #expect(s.statusUebernehmen() == .uebernommen)
        let eins = try #require(s.planung?.eintraege.first { $0.id == "e-1" })
        #expect(eins.erledigt && eins.kommentar == "aus dem alten Tab", "die Einträge sind übernommen")

        let danach = try Data(contentsOf: ziel.appending(component: Statusdatei.name))
        let kopf = try Tresor.kopfLesen(danach)
        #expect(tresor.huelleGleich(kopf, ziel: .kopie), "die Datei trägt jetzt die aktuelle Hülle")
        #expect(throws: Tresorfehler.self, "die alte Passphrase öffnet sie nicht mehr") {
            try Tresor.oeffnen(kopf: kopf, passphrase: alt)
        }
        let inhalt = try Statusdatei.lesen(try tresor.oeffnen(kopf: kopf))
        #expect(inhalt == vorher, "der Inhalt ist unverändert")
        #expect(hinweise(s) == 1, "einmal gesagt: \(s.meldungen.map(\.text))")
        #expect(s.meldungen.contains { $0.text == "Die Statusdatei der Web App trug noch die Hülle der vorherigen Passphrase "
                + "und ist jetzt neu versiegelt. Bitte die Web App neu laden und die aktuelle Kopie öffnen." },
                "Wortlaut E1317")

        // Noch einmal gelesen: dieselbe Hülle, nichts zu tun, kein zweiter Hinweis.
        _ = s.statusUebernehmen()
        #expect(hinweise(s) == 1)
    }

    @Test("Alte Hülle im Hintergrund gelesen: ebenso neu gewickelt und einmal gesagt")
    func alteHuelleImHintergrund() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, alteHuelle) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        #expect(try s.passphraseAendern(alt: alt, neu: neu).offenes.isEmpty)
        let tresor = try #require(s.tresor)
        _ = try schreiben(stand("im Hintergrund"), mit: alteHuelle, nach: ziel)

        let ergebnis = await s.statusUebernehmenImHintergrund()
        #expect(ergebnis == .uebernommen)
        let kopf = try Tresor.kopfLesen(try Data(contentsOf: ziel.appending(component: Statusdatei.name)))
        #expect(tresor.huelleGleich(kopf, ziel: .kopie))
        #expect(hinweise(s) == 1)
    }

    @Test("Alte Hülle, aber nichts Neues: trotzdem neu gewickelt und gesagt")
    func alteHuelleOhneNeues() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, alteHuelle) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        #expect(try s.passphraseAendern(alt: alt, neu: neu).offenes.isEmpty)
        let tresor = try #require(s.tresor)
        let derselbe = stand("schon da")
        _ = try schreiben(derselbe, mit: alteHuelle, nach: ziel)
        #expect(s.statusUebernehmen() == .uebernommen)
        // Derselbe Stand noch einmal aus einem alten Tab: nichts Neues — und doch wieder in alter Hülle.
        _ = try schreiben(derselbe, mit: alteHuelle, nach: ziel)
        #expect(s.statusUebernehmen() == .nichtsNeues)
        let kopf = try Tresor.kopfLesen(try Data(contentsOf: ziel.appending(component: Statusdatei.name)))
        #expect(tresor.huelleGleich(kopf, ziel: .kopie), "auch ohne Neues neu gewickelt")
        #expect(hinweise(s) == 2, "je Lesung in alter Hülle einmal: \(s.meldungen.map(\.text))")
    }

    @Test("Neuwickeln scheitert: Einträge übernommen, Datei unverändert, der Grund gesagt")
    func neuwickelnScheitert() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ziel.path)
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, alteHuelle) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        #expect(try s.passphraseAendern(alt: alt, neu: neu).offenes.isEmpty)
        let roh = try schreiben(stand("schreibgeschützt"), mit: alteHuelle, nach: ziel)
        // Lesen gelingt, das atomare Schreiben nicht: Der Ordner nimmt keine neue Datei an.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ziel.path)
        #expect(s.statusUebernehmen() == .uebernommen)
        let eins = try #require(s.planung?.eintraege.first { $0.id == "e-1" })
        #expect(eins.kommentar == "schreibgeschützt", "übernommen ist trotzdem")
        #expect(try Data(contentsOf: ziel.appending(component: Statusdatei.name)) == roh, "die Datei bleibt, wie sie war")
        #expect(s.meldungen.contains { $0.text.contains("ließ sich nicht neu versiegeln: ") },
                "der Grund ist gesagt: \(s.meldungen.map(\.text))")
        #expect(!s.meldungen.contains { $0.text.contains("ist jetzt neu versiegelt") })
        #expect(!s.meldungen.contains { $0.text.contains("..") }, "ein Punkt nach dem Grund (R98-W2-05)")
    }

    @Test("Die Funktion des Einlesens wickelt nur Behälter unter eigenem Schlüssel — Klartext und Fremdes bleiben (R98-W2-02)")
    func neuwickelnNurBehaelter() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, _) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        #expect(try s.passphraseAendern(alt: alt, neu: neu).offenes.isEmpty)
        let tresor = try #require(s.tresor)
        let datei = ziel.appending(component: Statusdatei.name)
        // Das Restfenster: Zwischen Lesen und Wickeln liegt dort eine Klartext-Datei oder ein fremder Behälter.
        let klartext = try Statusdatei.schreiben(stand("Klartext im Fenster"))
        try klartext.write(to: datei, options: [.atomic])
        #expect(try s.sicherung.statusdateiNachEinlesenNeuWickeln(neu: tresor) == false)
        #expect(try Data(contentsOf: datei) == klartext, "Klartext bleibt Klartext")
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        let roh = try schreiben(stand("fremd im Fenster"), mit: fremder, nach: ziel)
        #expect(try s.sicherung.statusdateiNachEinlesenNeuWickeln(neu: tresor) == false)
        #expect(try Data(contentsOf: datei) == roh, "Fremdes bleibt, ohne Fehler")
    }

    /// Hält das Lesen an, bis die Prüfung es freigibt (wie in `StatusAbrufPruefungen`).
    private final class Lesesperre: @unchecked Sendable {
        private let tor = DispatchSemaphore(value: 0)
        private let sperre = NSLock()
        private var angekommen = 0
        var haengt: Bool { sperre.withLock { angekommen > 0 } }
        var halten: @Sendable () -> Void {
            { [self] in
                sperre.withLock { angekommen += 1 }
                _ = tor.wait(timeout: .now() + 120)
            }
        }
        func oeffnen() { tor.signal() }
    }

    @Test("Alte Hülle, aber die Lesung im Hintergrund ist überholt: Datei bleibt, kein Hinweis (R98-W2-08)")
    func alteHuelleVerworfen() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, alteHuelle) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        #expect(try s.passphraseAendern(alt: alt, neu: neu).offenes.isEmpty)
        let roh = try schreiben(stand("überholt"), mit: alteHuelle, nach: ziel)
        let tor = Lesesperre()
        var aufgabe: Task<Planungsspeicher.Statusuebernahme?, Never>?
        Statusnaht.$halten.withValue(tor.halten) { aufgabe = s.statusAbrufen() }
        try await abwarten("das Lesen hängt") { tor.haengt }
        // Überholt bei gleichem Zielordner: Ein Neuwickeln nach dem Verwerfen träfe dieselbe Datei (RR98-W2-01).
        s.schauplatzGewechselt()
        tor.oeffnen()
        #expect(await aufgabe?.value == .some(nil), "verworfen")
        #expect(try Data(contentsOf: ziel.appending(component: Statusdatei.name)) == roh, "die Datei bleibt bytegleich")
        #expect(hinweise(s) == 0, "kein Hinweis: \(s.meldungen.map(\.text))")
    }

    @Test("Passphrase ändern bei liegender Statusdatei: kein Hinweis zur alten Hülle")
    func passphraseAendernOhneHinweis() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, _) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        let tresor = try #require(s.tresor)
        _ = try schreiben(stand("vor dem Wechsel"), mit: tresor, nach: ziel)
        #expect(try s.passphraseAendern(alt: alt, neu: neu).offenes.isEmpty)
        let kopf = try Tresor.kopfLesen(try Data(contentsOf: ziel.appending(component: Statusdatei.name)))
        #expect(try #require(s.tresor).huelleGleich(kopf, ziel: .kopie), "der Übergang hat sie neu gewickelt")
        #expect(hinweise(s) == 0, "der Übergang ist kein alter Tab: \(s.meldungen.map(\.text))")
    }

    @Test("Klartext-Statusdatei bei eingeschalteter Verschlüsselung: wie bisher, nicht gewickelt, kein Hinweis")
    func klartextBleibt() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, _) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        let roh = try Statusdatei.schreiben(stand("im Klartext"))
        try roh.write(to: ziel.appending(component: Statusdatei.name), options: [.atomic])
        _ = s.statusUebernehmen()
        let eins = try #require(s.planung?.eintraege.first { $0.id == "e-1" })
        #expect(eins.kommentar.isEmpty, "nicht übernommen")
        #expect(try Data(contentsOf: ziel.appending(component: Statusdatei.name)) == roh, "die Datei bleibt bytegleich")
        #expect(s.meldungen.contains { $0.text.contains("unverschlüsselt") })
        #expect(hinweise(s) == 0)
    }

    @Test("Gleiche Hülle: nichts neu geschrieben, kein Hinweis")
    func gleicheHuelleBleibt() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, _) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        let tresor = try #require(s.tresor)
        let roh = try schreiben(stand("aktuell"), mit: tresor, nach: ziel)
        #expect(s.statusUebernehmen() == .uebernommen)
        #expect(try Data(contentsOf: ziel.appending(component: Statusdatei.name)) == roh, "die Datei bleibt bytegleich")
        #expect(hinweise(s) == 0)
    }

    @Test("Fremder Schlüssel: wie bisher benannt, nicht übernommen, nicht neu geschrieben, kein Hinweis zur Hülle")
    func fremderSchluesselBleibt() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let (s, _) = try await eingeschaltet(ablage: ablage, ziel: ziel)
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        let roh = try schreiben(stand("fremd"), mit: fremder, nach: ziel)
        _ = s.statusUebernehmen()
        #expect(try Data(contentsOf: ziel.appending(component: Statusdatei.name)) == roh, "die Datei bleibt bytegleich")
        #expect(s.meldungen.contains { $0.text.contains("anderen Schlüssel") })
        #expect(hinweise(s) == 0)
    }
}
