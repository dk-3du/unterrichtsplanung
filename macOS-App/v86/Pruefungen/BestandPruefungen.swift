// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Bestand am Speicher (v80, AP14c) ──────────────────────────────────
// Nach der Review: Tischbindung beim Löschen (E304), Stempel (W1-09),
// Herkunft vor dem ersten Schreiben (W1-06), Verlauf nach gescheitertem
// Schuljahreswechsel (W2-09); dazu die offenen Punkte ⌘Z mit getippter
// Liste, offener Bogen beim Beenden, Haken vom iPad bei offenem Blatt.

@Suite("Bestand am Speicher: Tischbindung, Stempel, Herkunft, Verlauf, ⌘Z, Bogen, Stand der Sitzung")
@MainActor
struct BestandPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "bestand-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.id = "k-kl"
        p.klassen += [leitung]
        // Wie im Programm: Eine neue Zeile bekommt ihre Farbe — sonst läse das Archiv sie anders.
        p.farbenVervollstaendigen()
        return p
    }

    /// Eingeschaltet, noch ohne Jahresdatei.
    private func eingeschaltet(_ ablage: URL) async throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        return s
    }

    /// Anna und Ben in der Klassenleitung, ein Termin für Anna mit Vorhaben.
    private func speicher(_ ablage: URL) async throws -> (Planungsspeicher, termin: String, vorhaben: String, anna: String, ben: String) {
        let s = try await eingeschaltet(ablage)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let s0 = a.erstellt
        let (b, gruppe) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: s0))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: gruppe, jetzt: s0).bestand
        let anna = try #require(c.lernende.first { $0.nachname == "Abel" }).id
        let ben = try #require(c.lernende.first { $0.nachname == "Bauer" }).id
        let (d, termin) = try #require(c.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [anna],
                                                          datum: "2026-08-20", frist: "", uhrzeit: "07:45", jetzt: s0))
        #expect(s.lernendenUebernehmen(d.mitTerminwunsch(termin, zeile: "k-kl")) == nil)
        let vorhaben = try #require(s.planung?.eintraege.first { $0.termin == termin }).id
        return (s, termin, vorhaben, anna, ben)
    }

    @Test("Endgültig gelöscht (E304): Die Bindung an Tischen geht, der Name bleibt — und die Rückfrage nennt es")
    func bindungGehtMitPerson() async throws {
        let ablage = try ordner("bindung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _, anna, ben) = try await speicher(ablage)
        let plan = Sitzplan.anordnen(klasseId: "k-kl", lernende: [.init(name: "Anna Abel", lernender: anna),
                                                                  .init(name: "Ben Bauer", lernender: ben)])
        #expect(s.sitzplaene.setzen(plan, fuer: "k-kl") == nil)
        let b = try #require(s.lernende.bestand)
        s.offenerDialog = .lernende  // Die Frage hängt am Blatt (E418).
        s.personLoeschenFragen(anna, in: b) { _ in }
        #expect(s.rueckfrage?.text.contains("\n\nAn 1 Tisch im Sitzplan wird die Zuordnung gelöst; der Name am Tisch bleibt.")
                == true, Comment(rawValue: s.rueckfrage?.text ?? "—"))
        s.rueckfrageBeantworten(false)
        #expect(s.lernendenUebernehmen(b.ohnePerson(anna).bestand) == nil)
        let danach = try #require(s.sitzplaene.plan(fuer: "k-kl"))
        #expect(danach.tische.map(\.lernender) == ["", ben] && danach.tische.map(\.name) == ["Anna Abel", "Ben Bauer"],
                "gelöst, der Name bleibt")
        let frisch = Sitzplandienst(ablage: Ablage(ordner: ablage))
        _ = frisch.oeffnen(mit: try #require(s.tresor), stempel: "probe")
        #expect(frisch.plan(fuer: "k-kl")?.tische.map(\.lernender) == ["", ben], "so auf der Platte")
    }

    @Test("Löschen über das Blatt stempelt die Jahresdatei (W1-09)")
    func loeschenStempelt() async throws {
        let ablage = try ordner("stempel")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _, _, ben) = try await speicher(ablage)
        // Ein alter Stempel — ein neuer fiele sonst womöglich in dieselbe Millisekunde.
        var b = try #require(s.lernende.bestand)
        b.geaendert = "2026-01-01T00:00:00.000Z"
        #expect(s.lernende.setzen(b) == nil)
        #expect(s.lernendenUebernehmen(b.ohnePerson(ben).bestand) == nil)
        #expect(s.lernende.bestand?.geaendert != b.geaendert, "der Stempel folgt der Änderung")
    }

    @Test("Ändert das Übernehmen nur Rückverweise, trägt die Jahresdatei trotzdem den neuen Stempel (Z14c-07)")
    func stempelNachRueckverweis() async throws {
        let ablage = try ordner("stempel-verweis")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _, _, ben) = try await speicher(ablage)
        let b = try #require(s.lernende.bestand)
        let (c, id) = try #require(b.mitNeuemAnliegen(.termin, titel: "Sprechstunde", lerngruppe: "", betroffene: [ben],
                                                       datum: "2026-08-21", frist: "", uhrzeit: "", jetzt: b.geaendert))
        #expect(s.lernendenUebernehmen(c) == nil)
        // Ein alter Stempel — ein neuer fiele sonst womöglich in dieselbe Millisekunde.
        var alt = try #require(s.lernende.bestand)
        alt.geaendert = "2026-01-01T00:00:00.000Z"
        #expect(s.lernende.setzen(alt) == nil)
        #expect(s.lernendenUebernehmen(alt.mitTerminwunsch(id, zeile: "k-kl")) == nil)
        #expect(s.lernende.bestand?.anliegen.first { $0.id == id }?.vorhaben.isEmpty == false, "der Rückverweis steht")
        #expect(s.lernende.bestand?.geaendert != alt.geaendert, "und der Stempel folgt")
    }

    @Test("Eine Planung anderer Herkunft bei offenem Blatt: abgewiesen — das Blatt bleibt; gesagt, wenn es zu ist (Z14c-02, E335, E391)")
    func andereHerkunftBeiOffenemBlatt() async throws {
        let ablage = try ordner("offenes-blatt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.dialogOeffnen(.lernende)
        var fremd = try #require(s.planung)
        fremd.titel = "Fremd 2027/28"
        fremd.erstellt = "2027-07-01T10:00:00.000Z"
        // Ein Jahr später, wie der Titel sagt — dasselbe Schuljahr nennt die Meldung anders (E309).
        fremd.start = fremd.start.plus(tage: 364)
        let meldungen = s.meldungen.count
        let davor = Set(s.meldungen.map(\.id))
        let toene = s.systemtoene
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "fremd.json"))
        #expect(s.offenerDialog == .lernende && s.naechsterDialog == nil && s.schuljahrwechsel == nil, "das Blatt bleibt")
        // Ebenso „Neue Planung“ mitten in der Sitzung — dort stünden getippte Kurse (Z14c-09).
        s.offenerDialog = .neuePlanung
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "fremd.json"))
        #expect(s.offenerDialog == .neuePlanung && s.schuljahrwechsel == nil, "„Neue Planung“ bleibt")
        #expect(s.meldungen.count == meldungen, "hinter den Blättern noch kein Text (E335)")
        #expect(s.systemtoene == toene + 2, "je ein Ton sofort (E399)")
        let dahinter = await uhr.vorruecken(bis: { s.meldungen.contains { !davor.contains($0.id) } },
                                             hoechstens: .seconds(1))
        #expect(!dahinter, "auch über die Zeit nicht, solange das Blatt steht")
        let text = "„Fremd 2027/28“ gehört zu einem anderen Schuljahr und wurde nicht geöffnet, weil ein Blatt offen war. "
            + "Bitte die Datei erneut öffnen."
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Schließen des Blatts der Text")
        #expect(s.meldungen.filter { $0.text == text }.count == 1, "zweimal abgewiesen, einmal gesagt")
        // Gezählt wird, was gesagt wurde — eine Meldung kann verfallen, ehe die nächste kommt.
        var gesagt = Set<UUID>()
        let weitere = await uhr.vorruecken(bis: {
            gesagt.formUnion(s.meldungen.filter { $0.text == text }.map(\.id))
            return gesagt.count > 1
        }, hoechstens: .seconds(1))
        #expect(!weitere, "auch danach kein zweites Mal")
    }

    @Test("Lässt sich vor dem ersten Schreiben die Herkunft nicht sichern, bleibt der Stand in der Sitzung — und es wird gesagt (Z14c-01)")
    func herkunftNichtGesichert() async throws {
        let ablage = try ordner("herkunft-gescheitert")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ablage.path)
            try? FileManager.default.removeItem(at: ablage)
        }
        let s = try await eingeschaltet(ablage)
        var p = try #require(s.planung)
        p.erstellt = "2026-10-03T09:00:00.000Z"
        s.stempelEinsetzen(p)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let (b, _) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: a.erstellt))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ablage.path)
        _ = s.lernendenUebernehmen(b)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ablage.path)
        #expect(s.lernende.bestand?.lerngruppen.map(\.name) == ["6a"], "der Stand gilt für die Sitzung")
        #expect(s.meldungen.contains { $0.text.hasPrefix("Die Herkunft der Planung steht noch nicht auf der Platte") },
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
    }

    @Test("Vor dem ersten Schreiben der Jahresdatei steht die Herkunft der Planung auf der Platte (W1-06, A4)")
    func herkunftVorDemErstenSchreiben() async throws {
        let ablage = try ordner("herkunft")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await eingeschaltet(ablage)
        var p = try #require(s.planung)
        // Eine Herkunft, die die Platte nicht trägt — wie nach dem Lesen einer Datei ohne `erstellt`.
        p.erstellt = "2026-10-03T09:00:00.000Z"
        s.stempelEinsetzen(p)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let (b, _) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: a.erstellt))
        #expect(s.lernendenUebernehmen(b) == nil)
        let roh = try Data(contentsOf: Ablage(ordner: ablage).datei)
        let gelesen = try Planungsdatei.lesen(try #require(s.tresor).oeffnen(roh))
        #expect(gelesen.erstellt == "2026-10-03T09:00:00.000Z", "die Platte trägt die Herkunft der Jahresdatei")
    }

    @Test("Scheitert der Schuljahreswechsel, bleibt der Verlauf (W2-09)")
    func verlaufNachGescheitertemWechsel() async throws {
        let ablage = try ordner("wechsel")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ablage.path)
            try? FileManager.default.removeItem(at: ablage)
        }
        let (s, _, _, _, _) = try await speicher(ablage)
        s.aendern(Schrittname.titelAendern) { $0.titel = "Probe" }
        #expect(s.verlauf.kannZurueck)
        let alt = try #require(s.planung)
        let neue = Planung.leer(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4,
                                basis: "", klassen: Standardkurse.aufbauen([("7a", "Biologie")]), fachfarben: [:])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ablage.path)
        let grund = s.jahreswechsel(zu: neue, zuordnung: [:], gruppen: [], ohneMitglieder: [])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ablage.path)
        #expect(grund != nil, "gescheitert")
        #expect(s.planung == alt, "die bisherige gilt weiter")
        #expect(s.verlauf.kannZurueck, "⌘Z bleibt")
    }

    @Test("⌘Z im Blatt mit getippter Liste (offener Punkt 1): Nimmt es die gewählte Gruppe, fragt es zuerst")
    func widerrufenMitNamensliste() async throws {
        let ablage = try ordner("widerrufen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        var gesetzt: [Lernendenbestand] = []
        var namen = true
        var bleibt = false
        s.lernendenblattUebernimmt({ gesetzt.append($0) }, griff: Lernendenblattgriff(
            gruppeBleibt: { _ in bleibt }, namenOffen: { namen }, namenVerwerfen: { namen = false }))
        s.offenerDialog = .lernende  // Die Frage hängt am Blatt (E418).
        s.lernendenverlauf.anmelden(Schrittname.terminAendern, kennung: t, vorher: b, nachher: geaendert)
        s.widerrufen()
        #expect(s.rueckfrage?.text == "Die eingegebenen Namen verwerfen?" && gesetzt.isEmpty, "erst die Frage, noch kein ⌘Z")
        s.rueckfrageBeantworten(true)
        #expect(!namen, "verworfen")
        let zurueckgenommen = await uhr.vorruecken(bis: { gesetzt.count == 1 }, hoechstens: .seconds(1))
        try #require(zurueckgenommen, "dann das ⌘Z")
        // Bleibt die Gruppe, geht ⌘Z ohne Frage.
        namen = true
        bleibt = true
        s.wiederholen()
        #expect(s.rueckfrage == nil && gesetzt.count == 2)
        s.lernendenblattGibtAb()
    }

    @Test("Offener Bogen beim Beenden (offener Punkt 2): „Den offenen Bogen verwerfen?“ am Bogen, dann weiter")
    func bogenBeimBeenden() async throws {
        let ablage = try ordner("bogen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var bogen = true
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(bogenOffen: { bogen }, bogenSchliessen: { bogen = false }))
        s.offenerDialog = .lernende  // Die Frage hängt am Bogen des Blatts (E418).
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt && s.rueckfrage?.text == "Den offenen Bogen verwerfen?" && s.rueckfrage?.ort == .bogen
                && s.rueckfrage?.ablehnung == "Weiter bearbeiten", Comment(rawValue: s.rueckfrage?.text ?? "—"))
        s.rueckfrageBeantworten(false)
        #expect(bogen && weiter == 0, "„Weiter bearbeiten“: Der Bogen bleibt, die App auch")
        let nochmal = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(nochmal)
        s.rueckfrageBeantworten(true)
        #expect(!bogen, "verworfen: Der Bogen ist zu")
        let gelaufen = await uhr.vorruecken(bis: { weiter == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "dann geht das Beenden weiter")
        s.lernendenblattGibtAb()
    }

    @Test("Haken vom iPad bei offenem Blatt (offener Punkt 3): ein Termin, den das Blatt nicht anfasste, behält den Stand der Sitzung")
    func standDerSitzungBleibt() async throws {
        let ablage = try ordner("ipad")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v, anna, ben) = try await speicher(ablage)
        let ausgang = try #require(s.lernende.bestand)
        // Während das Blatt offen ist, kommt der Haken (wie ein Stand vom iPad).
        s.erledigtUmschalten(v)
        #expect(s.lernende.verzeichnis?.stand(t, anna) == .erledigt)
        let entwurf = ausgang.mitPerson(ben, vorname: "Benno", nachname: "Bauer", rufname: "", jetzt: ausgang.geaendert)
        #expect(s.lernendenUebernehmen(entwurf, ausgang: ausgang) == nil)
        #expect(s.planung?.eintraege.first { $0.id == v }?.erledigt == true && s.lernende.verzeichnis?.stand(t, anna) == .erledigt,
                "der Haken bleibt")
        #expect(s.lernende.bestand?.lernende.contains { $0.vorname == "Benno" } == true, "die Änderung des Blatts gilt")
    }
}
