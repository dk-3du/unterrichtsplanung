// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Der Schreibweg auf die Platte — geprüft an einer eigenen Ablage, damit
/// `Ablage.shared` und der Ordner des Prüflaufs unberührt bleiben.
@Suite("Ablage")
struct AblagePruefungen {

    private func ablage() throws -> (Ablage, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "ablage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return (Ablage(ordner: ordner), ordner)
    }

    private func inhalt(_ ziel: URL) -> String? {
        (try? Data(contentsOf: ziel)).flatMap { String(data: $0, encoding: .utf8) }
    }

    @Test("Im Prüfziel gibt es ohne PLANUNGSORDNER einen eigenen Ort — nie Application Support")
    func pruefziel() {
        #expect(Ablage.imPruefziel, "diese Prüfung läuft im Prüfziel")
        #expect(Ablage.istPruefstand)
        #expect(Ablage.ablageort(umgebung: "/tmp/eigener", imPruefziel: true).path == "/tmp/eigener")
        let eigen = Ablage.ablageort(umgebung: "", imPruefziel: true)
        #expect(eigen.path.hasPrefix(URL.temporaryDirectory.path))
        #expect(eigen.lastPathComponent.hasPrefix("Unterrichtsplanung-Pruefziel-"))
        let echt = Ablage.ablageort(umgebung: "", imPruefziel: false)
        #expect(echt.lastPathComponent == "Unterrichtsplanung" && echt.path.contains("Application Support"))
    }

    @Test("Der erste Schreibvorgang legt die Datei an, ohne Vorgängerfassung")
    func ersterSchreibvorgang() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("eins".utf8), tresor: nil)
        #expect(inhalt(ablage.datei) == "eins")
        #expect(ablage.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse) == nil)
    }

    @Test("Der zweite Schreibvorgang schiebt den bisherigen Stand zur Seite")
    func vorgaengerfassung() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("eins".utf8), tresor: nil)
        try ablage.schreiben(Data("zwei".utf8), tresor: nil)
        #expect(inhalt(ablage.datei) == "zwei")
        #expect(ablage.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse).flatMap { String(data: $0, encoding: .utf8) } == "eins")

        try ablage.schreiben(Data("drei".utf8), tresor: nil)
        #expect(inhalt(ablage.datei) == "drei")
        #expect(ablage.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse).flatMap { String(data: $0, encoding: .utf8) } == "zwei")
    }

    @Test("Die Nebendatei des Fortschreibens bleibt nicht liegen")
    func keineNebendatei() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("eins".utf8), tresor: nil)
        try ablage.schreiben(Data("zwei".utf8), tresor: nil)
        let liegt = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        #expect(!liegt.contains { $0.hasSuffix(".neu") }, "übrig: \(liegt)")
    }

    @Test("Die Versiegelung der Nebendateien benennt, was übrig bleibt")
    func nebendateienBilanz() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let tresor = Tresor.neu()
        try tresor.passphraseSetzen("Ein Satz, den man behält", runden: Tresor.rundenMindestens)
        let vorher = ordner.appending(component: "planung-vorher.json")
        let unlesbar = ordner.appending(component: "planung-beschaedigt-1.json")
        let fremd = ordner.appending(component: "planung-beschaedigt-2.json")
        try Data("{\"typ\":\"unterrichtsplanung\"}".utf8).write(to: vorher)
        try Data("kein JSON".utf8).write(to: unlesbar)
        let anderer = Tresor.neu()
        try anderer.passphraseSetzen("Ein ganz anderer Satz", runden: Tresor.rundenMindestens)
        try anderer.versiegeln(Data("x".utf8), inhalt: .rohdaten, ziel: .ablage).write(to: fremd)
        let verwaltung = FileManager.default
        try verwaltung.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unlesbar.path)
        defer { try? verwaltung.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unlesbar.path) }

        let bilanz = ablage.altbestaendeVersiegeln(mit: tresor)
        #expect(bilanz.umgestellt == ["planung-vorher.json"])
        #expect(bilanz.uebrig.map(\.name) == ["planung-beschaedigt-1.json", "planung-beschaedigt-2.json"])
        #expect(!bilanz.vollstaendig)
        #expect(bilanz.beschreibung.contains("anderen Schlüssel"))
        #expect(Tresor.istBehaelter(try Data(contentsOf: vorher)))

        // Nachholen beim Start: Klartext wird versiegelt, ein Behälter unter dem
        // eigenen Schlüssel bleibt liegen, der fremde wird weiter benannt.
        try verwaltung.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unlesbar.path)
        let nachgeholt = ablage.altbestaendeVersiegeln(mit: tresor, nurKlartext: true)
        #expect(nachgeholt.umgestellt == ["planung-beschaedigt-1.json"])
        #expect(nachgeholt.uebrig.map(\.name) == ["planung-beschaedigt-2.json"])
        #expect(ablage.altbestaendeVersiegeln(mit: tresor, nurKlartext: true).umgestellt.isEmpty, "nichts mehr im Klartext")

        // Ein Ordner, der sich nicht lesen lässt, ist kein leerer Ordner.
        let weg = Ablage(ordner: ordner.appending(component: "gibt-es-nicht", directoryHint: .isDirectory))
        let ohneOrdner = weg.altbestaendeVersiegeln(mit: tresor)
        #expect(!ohneOrdner.vollstaendig && ohneOrdner.uebrig.first?.name == "gibt-es-nicht")

        // Der Rückweg benennt ebenso, was nicht aufging.
        let zurueck = ablage.altbestaendeEntsiegeln(tresor)
        #expect(zurueck.umgestellt == ["planung-beschaedigt-1.json", "planung-vorher.json"])
        #expect(zurueck.uebrig.map(\.name) == ["planung-beschaedigt-2.json"])
    }
    @Test("Ein leerer Ordner meldet keinen Bestand, kein Fehler")
    func keinBestand() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        guard case .keine = ablage.lesen(hoechstens: Planungsdatei.hoechstgroesse) else {
            Issue.record("erwartet war .keine")
            return
        }
        #expect(ablage.stand() == nil)
    }

    @Test("Was geschrieben wurde, kommt unverändert zurück")
    func lesen() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        let planung = Planung.leer(titel: "Ablageprobe",
                                   start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
                                   basis: "", klassen: [], fachfarben: [:])
        try ablage.schreiben(try Planungsdatei.schreiben(planung), tresor: nil)
        guard case .daten(let gelesen) = ablage.lesen(hoechstens: Planungsdatei.hoechstgroesse) else {
            Issue.record("erwartet war .daten")
            return
        }
        #expect(try Planungsdatei.lesen(gelesen).titel == "Ablageprobe")
    }

    @Test("Ein unlesbarer Stand wird als solcher gemeldet, nicht als leer")
    func unlesbar() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        // Ein Ordner an der Stelle der Datei: vorhanden, aber nicht lesbar.
        try FileManager.default.createDirectory(at: ablage.datei, withIntermediateDirectories: true)
        guard case .unlesbar = ablage.lesen(hoechstens: Planungsdatei.hoechstgroesse) else {
            Issue.record("erwartet war .unlesbar")
            return
        }
    }

    /// Die Grenze reicht der Aufrufer herein; ein Ordner oder eine Pipe an der
    /// Stelle der Datei wird gar nicht erst gelesen.
    @Test("Übergroß oder keine reguläre Datei: nicht gelesen, benannt — und die Fassung davor ebenso")
    func gebundenLesen() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try ablage.schreiben(Data(repeating: UInt8(ascii: "x"), count: 100), tresor: nil)
        guard case .zuGross(let groesse) = ablage.lesen(hoechstens: 99) else {
            Issue.record("erwartet .zuGross"); return
        }
        #expect(groesse == 100)
        guard case .daten(let gelesen) = ablage.lesen(hoechstens: 100) else {
            Issue.record("erwartet .daten"); return
        }
        #expect(gelesen.count == 100)

        try ablage.schreiben(Data("neu".utf8), tresor: nil)
        #expect(ablage.vorigeFassungLesen(hoechstens: 100)?.count == 100)
        #expect(ablage.vorigeFassungLesen(hoechstens: 99) == nil, "die Fassung davor ist ebenso gebunden")

        try FileManager.default.createDirectory(at: ablage.lesezeichen, withIntermediateDirectories: false)
        guard case .unlesbar(let fehler) = ablage.lesezeichenLesen(hoechstens: 1_000_000) else {
            Issue.record("erwartet .unlesbar"); return
        }
        #expect(fehler.localizedDescription.contains("keine reguläre Datei"))
    }

    @Test("Der beschädigte Stand wird beiseitegelegt und macht den Platz frei")
    func beiseitelegen() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("kaputt".utf8), tresor: nil)
        #expect(ablage.beschaedigtenStandBeiseitelegen(stempel: "2026-08-28-0130-00"))
        #expect(!FileManager.default.fileExists(atPath: ablage.datei.path))
        let liegt = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        #expect(liegt.contains("planung-beschaedigt-2026-08-28-0130-00.json"))
    }

    @Test("Zwei Störungen bekommen verschiedene Rettungskopien")
    func zweiRettungskopien() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        try ablage.schreiben(Data("erste".utf8), tresor: nil)
        #expect(ablage.beschaedigtenStandBeiseitelegen(stempel: "2026-08-28-0130-00"))
        try ablage.schreiben(Data("zweite".utf8), tresor: nil)
        #expect(ablage.beschaedigtenStandBeiseitelegen(stempel: "2026-08-28-0130-07"))

        let liegt = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
            .filter { $0.hasPrefix("planung-beschaedigt-") }
        #expect(liegt.count == 2, "beide Stände müssen erhalten bleiben: \(liegt)")
    }

    @Test("Ohne Datei ist nichts beiseitezulegen — und der Platz gilt als frei")
    func nichtsBeiseitezulegen() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }

        #expect(ablage.beschaedigtenStandBeiseitelegen(stempel: "2026-08-28-0130-00"))
    }
}

// ── Der Sicherungsweg der App ─────────────────────────────────────────────

/// Der Weg, den die App wirklich geht: `Planungsspeicher` über `Ablage.shared`.
///
/// Nicht `Planungsspeicher(vorschau:)` — der ist schreibgesperrt und käme an
/// `starten()`, `sichern()` und `jetztSichern()` nie vorbei. Geschrieben wird
/// deshalb in den Ordner aus `PLANUNGSORDNER`, den der Prüflauf mitbringt.
@Suite("Sicherungsweg", .serialized)
@MainActor
struct SicherungswegPruefungen {

    /// Die Vorbedingung jeder Prüfung dieser Reihe, hart statt gemeldet: Ohne
    /// eigenen Ablageort zeigte `Ablage.shared` auf die echte Planung.
    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    /// Nur die Dateien der Ablage, nicht der ganze Ordner: Was der Prüflauf
    /// sonst dort abgelegt hat, bleibt liegen.
    private func ablageLeeren() {
        let verwaltung = FileManager.default
        try? verwaltung.removeItem(at: Ablage.shared.datei)
        try? verwaltung.removeItem(at: Ablage.shared.vorherigeFassung)
        for name in rettungskopien() {
            try? verwaltung.removeItem(at: Ablage.shared.ordner.appendingPathComponent(name))
        }
    }

    private func rettungskopien() -> [String] {
        let inhalt = try? FileManager.default
            .contentsOfDirectory(atPath: Ablage.shared.ordner.path)
        return (inhalt ?? []).filter { $0.hasPrefix("planung-beschaedigt-") }
    }

    private func planung(_ titel: String) throws -> Planung {
        Planung.leer(titel: titel, start: try #require(Tag(iso: "2026-08-10")), wochen: 6,
                     basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                     fachfarben: [:])
    }

    private func anlegen(_ speicher: Planungsspeicher, titel: String) throws {
        speicher.neuePlanung(titel: titel, start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 6, basis: "",
                             klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             ersterSchultag: nil, uebernahme: [])
    }

    /// Der Änderungsstempel löst in Millisekunden auf, und `jetztSichern`
    /// schreibt nur bei abweichendem Stempel. Zwei Änderungen im selben
    /// Programmlauf fallen ohne Abstand in dieselbe Millisekunde.
    private func stempelweiter() {
        Thread.sleep(forTimeInterval: 0.003)
    }

    private func aufDerPlatte() throws -> Planung {
        try Planungsdatei.lesen(try Data(contentsOf: Ablage.shared.datei))
    }

    private func vorigeFassung() throws -> Planung {
        try Planungsdatei.lesen(try #require(Ablage.shared.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse)))
    }

    /// Was so groß ist, hat diese App nicht geschrieben: beiseite wie ein
    /// beschädigter Stand, die Fassung davor kommt zurück — mit der Größe im Satz.
    @Test("Eine übergroße Autosicherung wird beiseitegelegt und die Fassung davor geladen")
    func uebergross() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        try Planungsdatei.schreiben(try planung("Davor")).write(to: Ablage.shared.vorherigeFassung)
        try Data(count: Planungsdatei.hoechstgroesse + 1).write(to: Ablage.shared.datei)

        let speicher = Planungsspeicher()
        speicher.starten()
        #expect(speicher.planung?.titel == "Davor")
        #expect(rettungskopien().count == 1)
        #expect(try aufDerPlatte().titel == "Davor", "die gerettete Fassung liegt wieder als planung.json")
        let meldung = try #require(speicher.meldungen.last?.text)
        #expect(meldung.contains("größer als die Lesegrenze") && meldung.contains("32 MB"), "\(meldung)")
    }

    @Test("Ohne Bestand fragt der Start nach einer neuen Planung")
    func startOhneBestand() {
        ablageLeeren()
        let speicher = Planungsspeicher()
        speicher.starten()

        #expect(speicher.planung == nil)
        #expect(speicher.offenerDialog == .neuePlanung)
        #expect(!speicher.sicherungLiegtStill)
    }

    @Test("Der Start lädt den Stand von der Platte — und nur einmal")
    func startMitBestand() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        try Ablage.shared.schreiben(try Planungsdatei.schreiben(try planung("Erster Stand")), tresor: nil)
        let speicher = Planungsspeicher()
        speicher.starten()
        #expect(speicher.planung?.titel == "Erster Stand")
        #expect(speicher.offenerDialog == nil)
        #expect(speicher.letzteSicherung != nil)

        // Der zweite Aufruf darf den geladenen Stand nicht ersetzen.
        try Ablage.shared.schreiben(try Planungsdatei.schreiben(try planung("Zweiter Stand")), tresor: nil)
        speicher.starten()
        #expect(speicher.planung?.titel == "Erster Stand")
    }

    @Test("Ein unlesbarer Stand sperrt das Schreiben, statt ihn zu überschreiben")
    func startMitUnlesbaremStand() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        // Ein Ordner an der Stelle der Datei: vorhanden, aber nicht lesbar.
        try FileManager.default.createDirectory(at: Ablage.shared.datei,
                                                withIntermediateDirectories: true)
        let speicher = Planungsspeicher()
        speicher.starten()

        #expect(speicher.planung == nil)
        #expect(speicher.offenerDialog == .neuePlanung)
        #expect(speicher.sicherungLiegtStill)
        #expect(speicher.meldungen.contains { $0.art == .warnung })
        #expect(rettungskopien().isEmpty)
    }

    @Test("Eine neue Planung hebt die Startsperre auf und legt den Stand beiseite")
    func startsperreWirdAufgehoben() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        try FileManager.default.createDirectory(at: Ablage.shared.datei,
                                                withIntermediateDirectories: true)
        let speicher = Planungsspeicher()
        speicher.starten()
        #expect(speicher.sicherungLiegtStill)

        try anlegen(speicher, titel: "Nach der Sperre")
        stempelweiter()
        speicher.jetztSichern()

        #expect(!speicher.sicherungLiegtStill)
        #expect(try aufDerPlatte().titel == "Nach der Sperre")
        #expect(rettungskopien().count == 1)
    }

    @Test("Ein beschädigter Stand wird gerettet und wieder hingelegt")
    func beschaedigterStandWirdGerettet() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        try Ablage.shared.schreiben(try Planungsdatei.schreiben(try planung("Die Rettung")), tresor: nil)
        try Ablage.shared.schreiben(Data("{kein JSON".utf8), tresor: nil)
        let speicher = Planungsspeicher()
        speicher.starten()

        #expect(speicher.planung?.titel == "Die Rettung")
        #expect(rettungskopien().count == 1)
        // Sonst fände der nächste Start nichts mehr vor.
        #expect(try aufDerPlatte().titel == "Die Rettung")
        #expect(speicher.meldungen.contains { $0.art == .warnung })
    }

    @Test("Ohne Vorgängerfassung bleibt vom beschädigten Stand die Rettungskopie")
    func beschaedigterStandOhneVorgaenger() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        try Ablage.shared.schreiben(Data("{kein JSON".utf8), tresor: nil)
        let speicher = Planungsspeicher()
        speicher.starten()

        #expect(speicher.planung == nil)
        #expect(speicher.offenerDialog == .neuePlanung)
        #expect(rettungskopien().count == 1)
        #expect(!FileManager.default.fileExists(atPath: Ablage.shared.datei.path))
    }

    @Test("Der entprellte Weg schreibt einmal, und zwar den jüngsten Stand")
    func entprellteSicherung() async throws {
        ablageLeeren()
        defer { ablageLeeren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        try anlegen(speicher, titel: "Entprellt")
        stempelweiter()
        speicher.titelSetzen("Zwischenstand")
        stempelweiter()
        speicher.titelSetzen("Endstand")

        // 700 ms Entprellung, dann das Schreiben abseits des Hauptstrangs.
        try await Task.sleep(for: .milliseconds(1500))

        #expect(try aufDerPlatte().titel == "Endstand")
        #expect(speicher.letzteSicherung != nil)
        // Ein einziger Schreibvorgang — sonst läge hier schon eine Vorgängerfassung.
        #expect(Ablage.shared.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse) == nil)
    }

    @Test("Jetzt sichern macht aus der Vorgängerfassung keine Kopie")
    func vorgaengerfassungBleibtStehen() throws {
        ablageLeeren()
        defer { ablageLeeren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        try anlegen(speicher, titel: "Erster Wurf")
        speicher.jetztSichern()
        #expect(try aufDerPlatte().titel == "Erster Wurf")

        stempelweiter()
        speicher.titelSetzen("Zweiter Wurf")
        speicher.jetztSichern()
        #expect(try aufDerPlatte().titel == "Zweiter Wurf")
        #expect(try vorigeFassung().titel == "Erster Wurf")

        // Ohne Änderung wird nicht noch einmal geschrieben.
        speicher.jetztSichern()
        speicher.jetztSichern()
        #expect(try aufDerPlatte().titel == "Zweiter Wurf")
        #expect(try vorigeFassung().titel == "Erster Wurf")
    }

    @Test("Eine Vorschau rührt die Ablage auf keinem der beiden Wege an")
    func vorschauSchreibtNicht() async throws {
        ablageLeeren()
        defer { ablageLeeren() }
        let speicher = Planungsspeicher(vorschau: try planung("Nur Vorschau"))
        stempelweiter()
        speicher.titelSetzen("Trotzdem geändert")
        try await Task.sleep(for: .milliseconds(1000))
        speicher.jetztSichern()

        #expect(!FileManager.default.fileExists(atPath: Ablage.shared.datei.path))
        // Eine Vorschau schreibt absichtlich nicht; das ist keine Störung.
        #expect(!speicher.sicherungLiegtStill)
    }

}
