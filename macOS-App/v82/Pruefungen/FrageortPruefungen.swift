// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Ein Zustand, den ein Abschluss liest und die Prüfung umstellt.
@MainActor
private final class Merker {
    var an = false
}

/// Wie oft ein Abschluss lief.
@MainActor
private final class Zaehler {
    var wert = 0
}

/// Was ein Abschluss sammelt.
@MainActor
private final class Liste {
    var werte: [String] = []
}

/// Der Entwurf eines Blatts, den die Prüfung nachträglich ändert.
@MainActor
private final class Entwurfsstand {
    var bestand: Lernendenbestand
    init(_ bestand: Lernendenbestand) { self.bestand = bestand }
}

// ── Eine Frage, deren Ort nicht zu sehen ist (B89, E418) ──────────────────
// Ohne Alert gilt für eine neue Frage die Lage ihres Orts wie in der Warteschlange: zu sehen → gesetzt;
// verdeckt oder im Kommen → sie wartet; fort → sie entfällt, der Ton sofort, der Text danach (Z-AU5-03). Gesetzt stünde sie
// unsichtbar: Sie sperrte das Menü still (`dialogOffen`), hielte zurückgestellte Handlungen samt der Lücke
// fest (Z-AU4b-05, Z-AU4b-12) und verdrängte im Grund für ein Skript das Blatt (Z-AU3-12). Jede Prüfung stellt
// einen gemessenen Weg nach; ein Alert hängt hier wie an AppKit nur, wenn der Ort seiner Frage zu sehen ist.

@Suite("Eine Frage, deren Ort nicht zu sehen ist: verdeckt oder im Kommen wartet sie, fort entfällt sie mit Hinweis (B89, E418)")
@MainActor
struct FrageortPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let blatthinweis = "Eine Rückfrage entfiel, weil ihr Blatt nicht mehr offen war."
    private let bogenhinweis = "Eine Rückfrage entfiel, weil ihr Bogen nicht mehr offen war."
    private let hauptflaechenhinweis = "Eine Rückfrage entfiel, weil ein Blatt offen war."

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "frageort-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.id = "k-kl"
        p.klassen += [leitung]
        p.farbenVervollstaendigen()
        return p
    }

    /// Ein Alert hängt wie an AppKit nur, wenn der Ort der gesetzten Frage zu sehen ist — oder solange das
    /// eigene Alert eines Blatts steht (`eigenes`).
    private func alertWieAppKit(_ s: Planungsspeicher, eigenes: Merker = Merker()) {
        s.rueckfrageSichtbar = { [weak s] in
            guard let s else { return false }
            if eigenes.an { return true }
            guard let frage = s.rueckfrage else { return false }
            return s.ortAngezeigt(frage.ort)
        }
    }

    /// Im Klartext — ohne Verschlüsselung.
    private func klartext(_ ablage: URL) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        alertWieAppKit(s)
        return s
    }

    /// Eingeschaltet: Anna und Ben, ein Termin für Anna mit Vorhaben in der Klassenleitung.
    private func mitLernenden(_ ablage: URL) throws -> (Planungsspeicher, termin: String, vorhaben: String) {
        let s = try klartext(ablage)
        _ = try s.verschluesselungVorbereiten(passphrase: "Ein Satz, den man behält")
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let s0 = a.erstellt
        let (b, gruppe) = try #require(a.mitNeuerGruppe(name: "Klassenleitung 6a", fach: "", art: .klasse, jetzt: s0))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: gruppe, jetzt: s0).bestand
        let anna = try #require(c.lernende.first).id
        let (d, termin) = try #require(c.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [anna],
                                                          datum: "2026-08-20", frist: "", uhrzeit: "07:45", jetzt: s0))
        #expect(s.lernendenUebernehmen(d.mitTerminwunsch(termin, zeile: "k-kl")) == nil)
        let vorhaben = try #require(s.planung?.eintraege.first { $0.termin == termin }).id
        return (s, termin, vorhaben)
    }

    /// Ein Ordner, dessen Wiederanlauf blockiert (E67) — wie in `SchutzuebergangPruefungen`.
    private func blockierenderOrdner(_ ablage: URL) throws {
        try Data("{\"typ\":\"unterrichtsplanung\",\"version\":2,\"titel\":\"alt\"}".utf8)
            .write(to: ablage.appending(component: "planung.json"))
        try Data("alt".utf8).write(to: ablage.appending(component: "sitzplaene.json"))
        let dienst = Uebergangsdienst(ordner: ablage)
        #expect(dienst.vorbereiten(.erneuern, kennung: Data([3]), stempel: "s",
                                   dateien: ["planung.json": .daten(Data("neu-planung".utf8)),
                                             "sitzplaene.json": .daten(Data("neu-sitzplaene".utf8))]) == nil)
        #expect(dienst.uebergeben() == nil)
        _ = try FileManager.default.replaceItemAt(ablage.appending(component: "planung.json"),
                                                  withItemAt: ablage.appending(component: "planung.json.uebergang"),
                                                  backupItemName: "planung.json.vorgaenger",
                                                  options: [.withoutDeletingBackupItem])
        for name in [Uebergangsdienst.markenname, Uebergangsdienst.zweitschriftname] {
            try Data("{\"typ\":\"unterrichtsplanung-uebergang\",\"version\":9".utf8)
                .write(to: ablage.appending(component: name))
        }
    }

    // ── Die Regel (E418) ──────────────────────────────────────────────

    @Test("Liegt ein Bogen über dem Blatt der neuen Frage, wartet sie — keine unsichtbare Frage; danach erscheint sie")
    func verdecktWartet() async throws {
        let ablage = try ordner("verdeckt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let bogen = Merker()
        s.bogenSichtbar = { bogen.an }
        s.offenerDialog = .klassen
        bogen.an = true
        s.fragen("Unter dem Bogen", bestaetigung: "Ja", ort: .klassen) {}
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.map(\.text) == ["Unter dem Bogen"], "unter dem Bogen wartet sie")
        bogen.an = false
        try await abwarten("nach dem Bogen erscheint sie") { s.rueckfrage?.text == "Unter dem Bogen" }
        s.rueckfrageBeantworten(false)
    }

    @Test("Ist das Blatt der neuen Frage im Kommen, wartet sie und erscheint darin")
    func imKommenWartet() async throws {
        let ablage = try ordner("kommen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        s.offenerDialog = .klassen
        s.dialogOeffnen(.sitzplan)
        s.fragen("Im kommenden Blatt", bestaetigung: "Ja", ort: .sitzplan) {}
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.map(\.text) == ["Im kommenden Blatt"],
                "für das kommende Blatt wartet sie")
        s.naechstenDialogOeffnen()
        try await abwarten("im Blatt erscheint sie") { s.rueckfrage?.text == "Im kommenden Blatt" }
        s.rueckfrageBeantworten(false)
    }

    @Test("Ist der Ort der neuen Frage fort — ihr Blatt, ihr Bogen —, entfällt sie: der Ton sofort, gesagt als Warnung, das Menü bleibt bedienbar (Z-AU5-03)")
    func fortEntfaellt() throws {
        let ablage = try ordner("fort")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let toene = s.systemtoene
        s.fragen("Am geschlossenen Blatt", bestaetigung: "Ja", ort: .sitzplan) {}
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.isEmpty && !s.dialogOffen
                && s.meldungen.last?.text == blatthinweis && s.meldungen.last?.art == .warnung,
                Comment(rawValue: s.meldungen.last?.text ?? "—"))
        #expect(s.systemtoene == toene + 1, "der Ton kommt sofort — Blatt")
        s.alleDialogeSchliessen()
        s.fragen("Am geschlossenen Bogen", bestaetigung: "Ja", ort: .bogen) {}
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.isEmpty && !s.dialogOffen
                && s.meldungen.last?.text == bogenhinweis && s.meldungen.last?.art == .warnung,
                Comment(rawValue: s.meldungen.last?.text ?? "—"))
        #expect(s.systemtoene == toene + 2, "der Ton kommt sofort — Bogen")
    }

    @Test("Eine Folgefrage aus einer Fortsetzung, deren Ort verdeckt ist, geht den wartenden vor — wie unter einem Alert (Z-AU5-02, Z14c4-12)")
    func verdeckteFolgefrageGehtVor() async throws {
        let ablage = try ordner("folgefrage-verdeckt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let bogen = Merker()
        s.bogenSichtbar = { bogen.an }
        s.offenerDialog = .klassen
        s.fragen("Erste", bestaetigung: "Ja", ort: .klassen) { [weak s] in
            s?.nachDerAntwort { [weak s] in s?.fragen("Folgefrage", bestaetigung: "Ja", ort: .klassen) {} }
        }
        s.fragen("Wartende", bestaetigung: "Ja", ort: .klassen) {}
        #expect(s.rueckfrage?.text == "Erste" && s.wartendeRueckfragen.map(\.text) == ["Wartende"])
        s.rueckfrageBeantworten(true)
        // Ein Bogen legt sich über das Blatt, ehe die Fortsetzung fragt.
        bogen.an = true
        try await abwarten("die Folgefrage wartet") { s.wartendeRueckfragen.count == 2 }
        #expect(s.wartendeRueckfragen.map(\.text) == ["Folgefrage", "Wartende"],
                Comment(rawValue: s.wartendeRueckfragen.map(\.text).joined(separator: " | ")))
        // Eine verdeckte Frage ohne Fortsetzung reiht hinten ein (Z-AU5-11).
        s.fragen("Spätere", bestaetigung: "Ja", ort: .klassen) {}
        #expect(s.wartendeRueckfragen.map(\.text) == ["Folgefrage", "Wartende", "Spätere"],
                Comment(rawValue: s.wartendeRueckfragen.map(\.text).joined(separator: " | ")))
        bogen.an = false
        try await abwarten("nach dem Bogen erscheint eine") { s.rueckfrage != nil }
        #expect(s.rueckfrage?.text == "Folgefrage", Comment(rawValue: s.rueckfrage?.text ?? "—"))
        s.rueckfrageBeantworten(false)
    }

    @Test("Folgefragen einer Welle reihen in der Folge ihrer Handlungen vor den wartenden ein — unter dem Alert und verdeckt (Z-AU5-12)")
    func folgefragenEinerWelleInIhrerFolge() async throws {
        let ablage = try ordner("welle")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        // Unter dem ausblendenden Alert: zwei Folgefragen aus der Handlung selbst.
        s.fragen("Erste", bestaetigung: "Ja") { [weak s] in
            s?.fragen("Folge A", bestaetigung: "Ja") {}
            s?.fragen("Folge B", bestaetigung: "Ja") {}
        }
        s.fragen("Wartende", bestaetigung: "Ja") {}
        let vorher = s.rueckfrageSichtbar
        s.rueckfrageSichtbar = { true }
        s.rueckfrageBeantworten(true)
        s.rueckfrageSichtbar = vorher
        #expect(s.wartendeRueckfragen.map(\.text) == ["Folge A", "Folge B", "Wartende"],
                Comment(rawValue: s.wartendeRueckfragen.map(\.text).joined(separator: " | ")))
        s.wartendeRueckfragen.removeAll()
        // Verdeckt: zwei Fortsetzungen derselben Antwort fragen unter einem Bogen.
        let bogen = Merker()
        s.bogenSichtbar = { bogen.an }
        s.offenerDialog = .klassen
        s.fragen("Zweite", bestaetigung: "Ja", ort: .klassen) { [weak s] in
            s?.nachDerAntwort { [weak s] in s?.fragen("Folge C", bestaetigung: "Ja", ort: .klassen) {} }
            s?.nachDerAntwort { [weak s] in s?.fragen("Folge D", bestaetigung: "Ja", ort: .klassen) {} }
        }
        s.fragen("Wartende 2", bestaetigung: "Ja", ort: .klassen) {}
        s.rueckfrageBeantworten(true)
        bogen.an = true
        try await abwarten("beide Folgefragen warten") { s.wartendeRueckfragen.count == 3 }
        #expect(s.wartendeRueckfragen.map(\.text) == ["Folge C", "Folge D", "Wartende 2"],
                Comment(rawValue: s.wartendeRueckfragen.map(\.text).joined(separator: " | ")))
        s.wartendeRueckfragen.removeAll()
    }

    // ── Die gemessenen Wege ───────────────────────────────────────────

    @Test("„Unterbrochenen Übergang beiseitelegen …“ bei offenem Blatt: keine Frage hinter dem Blatt — sie entfällt, gesagt nach dem Blatt; erneut gewählt, steht sie")
    func blockadeHinterBlatt() async throws {
        let ablage = try ordner("blockade")
        defer { try? FileManager.default.removeItem(at: ablage) }
        try blockierenderOrdner(ablage)
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        alertWieAppKit(s)
        s.starten()
        #expect(s.blockadeOffen, "blockiert")
        // Der Menübefehl sperrt nicht bei offenem Blatt — ⌘N öffnet „Neue Planung“ auch ohne Planung.
        s.offenerDialog = .neuePlanung
        s.blockadeRaeumenFragen()
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.isEmpty && s.blockadeOffen,
                "hinter dem Blatt keine Frage, nichts geräumt")
        s.offenerDialog = nil
        try await abwarten("nach dem Blatt der Hinweis") { s.meldungen.contains { $0.text == hauptflaechenhinweis } }
        s.blockadeRaeumenFragen()
        #expect(s.rueckfrage?.bestaetigung == "Beiseitelegen", "ohne Blatt steht die Frage")
        s.rueckfrageBeantworten(false)
    }

    @Test("⌘Q mit geändertem Blatt „Lernende“, über dem ein Bogen liegt: die Frage wartet und erscheint danach; der Grund für ein Skript nennt sie (Z-AU3-12)")
    func beendenLernendeUnterBogen() async throws {
        let ablage = try ordner("beenden-bogen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try mitLernenden(ablage)
        let bogen = Merker()
        s.bogenSichtbar = { bogen.an }
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
        s.offenerDialog = .lernende
        // Ein Sichern- oder Druckbogen aus dem Blatt liegt darüber.
        bogen.an = true
        s.beenden()
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.count == 1 && !s.beendetGleich,
                "unter dem Bogen wartet sie — keine unsichtbare Frage")
        let grund = s.beendengrundJetzt(wartete: false)
        #expect(grund == "Das Blatt „Lernende“ hat ungesicherte Änderungen; das Beenden wartet auf eine Antwort.",
                Comment(rawValue: grund))
        bogen.an = false
        try await abwarten("nach dem Bogen erscheint sie") {
            s.rueckfrage?.text.hasPrefix("Die Änderungen an den Lernenden übernehmen?") == true
        }
        s.rueckfrageBeantworten(false)
        s.lernendenblattGibtAb()
    }

    @Test("Ergibt der Öffnen-Bogen am Blatt „Lernende“ einen neuen Entwurf, während die Frage beim Beenden wartet, übernimmt „Übernehmen“ den Stand der Antwort (Z-AU5-01)")
    func uebernehmenLiestEntwurfBeiDerAntwort() async throws {
        let ablage = try ordner("entwurf-antwort")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try mitLernenden(ablage)
        let bogen = Merker()
        s.bogenSichtbar = { bogen.an }
        let b = try #require(s.lernende.bestand)
        let entwurf = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        let blatt = Entwurfsstand(entwurf)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(ausgang: { b }, aenderungen: { blatt.bestand }))
        s.offenerDialog = .lernende
        // Der Öffnen-Bogen des Imports liegt am Blatt.
        bogen.an = true
        let weiter = Zaehler()
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter.wert += 1 })
        #expect(gefragt && s.rueckfrage == nil && s.wartendeRueckfragen.count == 1, "unter dem Bogen wartet sie")
        // Der Import ergibt einen neueren Entwurf; dann geht der Bogen.
        blatt.bestand = entwurf.mitAnliegen(t, titel: "Gespräch mit den Eltern", datum: "2026-08-20", frist: "", notiz: "",
                                            jetzt: entwurf.geaendert)
        bogen.an = false
        try await abwarten("nach dem Bogen erscheint sie") { s.rueckfrage?.bestaetigung == "Übernehmen" }
        s.rueckfrageBeantworten(true)
        try await abwarten("übernommen, dann weiter") { weiter.wert == 1 }
        let titel = s.lernende.bestand?.anliegen.first { $0.id == t }?.titel
        #expect(titel == "Gespräch mit den Eltern", Comment(rawValue: titel ?? "—"))
        s.lernendenblattGibtAb()
    }

    @Test("Nimmt ⌘Z unter dem Bogen alle Änderungen zurück, während die Frage beim Beenden wartet, schreibt „Übernehmen“ nichts — das Beenden geht weiter (Z-AU5-10)")
    func uebernehmenOhneAenderungenSchreibtNichts() async throws {
        let ablage = try ordner("entwurf-zurueck")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try mitLernenden(ablage)
        let bogen = Merker()
        s.bogenSichtbar = { bogen.an }
        let b = try #require(s.lernende.bestand)
        let blatt = Entwurfsstand(b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert))
        // Wie das Blatt: Änderungen nur, solange der Entwurf vom Ausgang abweicht.
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(
            ausgang: { b }, aenderungen: { blatt.bestand == b ? nil : blatt.bestand }))
        s.offenerDialog = .lernende
        bogen.an = true
        let weiter = Zaehler()
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter.wert += 1 })
        #expect(gefragt && s.rueckfrage == nil && s.wartendeRueckfragen.count == 1, "unter dem Bogen wartet sie")
        // ⌘Z bis zum Anfang; dann geht der Bogen.
        blatt.bestand = b
        bogen.an = false
        try await abwarten("nach dem Bogen erscheint sie") { s.rueckfrage?.bestaetigung == "Übernehmen" }
        s.rueckfrageBeantworten(true)
        try await abwarten("das Beenden geht weiter") { weiter.wert == 1 }
        let titel = s.lernende.bestand?.anliegen.first { $0.id == t }?.titel
        #expect(titel == "Elterngespräch", Comment(rawValue: titel ?? "—"))
        s.lernendenblattGibtAb()
    }

    @Test("Entfällt das Beenden nach „Übernehmen“ mit dem Entwurf der Antwort, fragt ein späteres ⌘Q nur nach dem, was seitdem neu ist (Z-AU5-11)")
    func nachUebernehmenFragtNurNachNeuem() async throws {
        let ablage = try ordner("entwurf-danach")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try mitLernenden(ablage)
        let bogen = Merker()
        s.bogenSichtbar = { bogen.an }
        let b = try #require(s.lernende.bestand)
        let entwurf = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        let blatt = Entwurfsstand(entwurf)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(
            ausgang: { b }, aenderungen: { blatt.bestand == b ? nil : blatt.bestand }))
        s.offenerDialog = .lernende
        bogen.an = true
        let weiter = Zaehler()
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter.wert += 1 })
        #expect(gefragt, "gefragt, unter dem Bogen wartend")
        let antwort = entwurf.mitAnliegen(t, titel: "Gespräch mit den Eltern", datum: "2026-08-20", frist: "", notiz: "",
                                          jetzt: entwurf.geaendert)
        blatt.bestand = antwort
        bogen.an = false
        try await abwarten("nach dem Bogen erscheint sie") { s.rueckfrage?.bestaetigung == "Übernehmen" }
        s.rueckfrageBeantworten(true)
        // Gleich danach eine andere Frage am Blatt: Das Beenden entfällt (Z14b-11), der Griff meldet sich wieder an.
        s.fragen("Eine andere Frage?", bestaetigung: "Ja", ort: .lernende, ablehnung: "Nein") {}
        try await Task.sleep(for: .milliseconds(Int(Planungsspeicher.folgefrageVerzug * 1000) + 200))  // E145: Uhr — Ausbleiben der Fortsetzung
        s.rueckfrageBeantworten(false)
        #expect(weiter.wert == 0, "das Beenden entfiel")
        let ohneNeues = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(!ohneNeues, "seit dem Übernehmen nichts Neues: keine Frage")
        blatt.bestand = antwort.mitAnliegen(t, titel: "Gespräch mit Anna", datum: "2026-08-20", frist: "", notiz: "",
                                            jetzt: antwort.geaendert)
        let mitNeuem = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(mitNeuem, "danach geändert: ⌘Q fragt wieder")
        s.rueckfrageBeantworten(false)
        s.lernendenblattGibtAb()
    }

    @Test("⇧⌘P im Sitzplan-Editor, über dem ein Bogen liegt: die Frage zur PDF wartet und erscheint danach")
    func pdfImSitzplanUnterBogen() async throws {
        let ablage = try ordner("sitzplan-bogen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try mitLernenden(ablage)
        let bogen = Merker()
        s.bogenSichtbar = { bogen.an }
        let klasse = try #require(s.planung?.klassen.first).id
        #expect(s.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse, namen: ["Dana", "Emil"])) == nil)
        s.sitzplanOeffnen(klasse: klasse)
        #expect(s.offenerDialog == .sitzplan && s.sitzplanEntwurf != nil)
        // Der Druckbogen eines ⌘P liegt noch am Editor.
        bogen.an = true
        s.sitzplanAlsPDFSichern()
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.first?.bestaetigung == "Als PDF sichern",
                "unter dem Bogen wartet sie")
        bogen.an = false
        try await abwarten("nach dem Bogen erscheint sie") { s.rueckfrage?.bestaetigung == "Als PDF sichern" }
        // Abgebrochen — im Prüfziel kein Sichern-Dialog.
        s.rueckfrageBeantworten(false)
    }

    @Test("⌘Z im Blatt „Lernende“ mit getippter Liste, über dem ein Bogen liegt: „Die eingegebenen Namen verwerfen?“ wartet und erscheint danach")
    func widerrufenUnterBogen() async throws {
        let ablage = try ordner("widerrufen-bogen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try mitLernenden(ablage)
        let bogen = Merker()
        s.bogenSichtbar = { bogen.an }
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        let gesetzt = Zaehler()
        let namen = Merker()
        namen.an = true
        s.lernendenblattUebernimmt({ _ in gesetzt.wert += 1 }, griff: Lernendenblattgriff(
            gruppeBleibt: { _ in false }, namenOffen: { namen.an }, namenVerwerfen: { namen.an = false }))
        s.offenerDialog = .lernende
        s.lernendenverlauf.anmelden(Schrittname.terminAendern, kennung: t, vorher: b, nachher: geaendert)
        bogen.an = true
        s.widerrufen()
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.map(\.text) == ["Die eingegebenen Namen verwerfen?"]
                && gesetzt.wert == 0, "unter dem Bogen wartet sie, noch kein ⌘Z")
        bogen.an = false
        try await abwarten("nach dem Bogen erscheint sie") { s.rueckfrage?.text == "Die eingegebenen Namen verwerfen?" }
        s.rueckfrageBeantworten(true)
        try await abwarten("verworfen, dann das ⌘Z") { !namen.an && gesetzt.wert == 1 }
        s.lernendenblattGibtAb()
    }

    @Test("Eine Frage der Hauptfläche hinter einem kommenden Blatt entfällt — die Handlung eines eigenen Alerts im Blatt läuft danach, nichts hält sie fest (Z-AU4b-05, Z-AU4b-12)")
    func zurueckgestellteHandlungLaeuft() async throws {
        let ablage = try ordner("zurueckgestellt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, v) = try mitLernenden(ablage)
        let eigenes = Merker()
        alertWieAppKit(s, eigenes: eigenes)
        s.anwaehlen(vorhaben: v)
        // Aus „Klassen/Kurse“ in den Sitzplan-Editor: Solange das Blatt im Kommen ist, trifft ⌫ die Auswahl.
        s.offenerDialog = .klassen
        s.dialogOeffnen(.sitzplan)
        #expect(s.naechsterDialog == .sitzplan && !s.dialogOffen)
        s.auswahlLoeschen()
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.isEmpty, "hinter dem kommenden Blatt keine Frage")
        s.naechstenDialogOeffnen()
        // Im Editor: ⎋, das eigene Alert, „Verwerfen“ — die Handlung läuft erst nach dem Schließen (AU4b).
        let verworfen = Zaehler()
        eigenes.an = true
        let verwerfen = s.nachDemSchliessenAusfuehren { verworfen.wert += 1 }
        verwerfen()
        #expect(verworfen.wert == 0 && s.handlungAussteht, "im Klick noch nicht")
        eigenes.an = false
        try await abwarten("nach dem Schließen läuft sie, die Lücke endet") { verworfen.wert == 1 && !s.handlungAussteht }
        let bleibt = s.planung?.eintraege.contains { $0.id == v } == true
        #expect(bleibt, "das Vorhaben bleibt")
        s.offenerDialog = nil
        try await abwarten("nach dem Blatt der Hinweis") { s.meldungen.contains { $0.text == hauptflaechenhinweis } }
    }

    @Test("Erscheint beim Beenden nach dem Schließen der Blätter eine Frage, deren Blatt fort ist, entfällt sie — der Grund für ein Skript bleibt „Blatt“ (Z-AU3-12)")
    func spaeteAblehnungFrageOhneOrt() async throws {
        let ablage = try ordner("spaet-ohne-ort")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        // AppKit lehnt ab; derweil kommt eine Frage an das Blatt, das eben schloss.
        s.appBeenden = { [weak s] in s?.fragen("Eine Frage am Klassen-Blatt", bestaetigung: "Ja", ort: .klassen) {} }
        let gruende = Liste()
        s.beendenAbgelehnt = { gruende.werte.append($0) }
        s.offenerDialog = .klassen
        s.beenden()
        try await abwarten("die Ablehnung ist gemeldet") { !gruende.werte.isEmpty }
        let gesagt = s.meldungen.contains { $0.text == blatthinweis }
        #expect(gruende.werte == ["Ein Blatt ließ sich nicht schließen; das Beenden wurde abgelehnt."] && s.rueckfrage == nil
                && gesagt, Comment(rawValue: gruende.werte.joined(separator: " | ")))
    }

    @Test("Fragt AppKit beim Beenden, während ein Blatt im Kommen ist, entfällt die Verlustfrage mit Hinweis — abgelehnt, ohne Frage hinter dem Blatt; ohne Blatt fragt das nächste")
    func verlustfrageImKommen() async throws {
        let ablage = try ordner("verlust-kommen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try mitLernenden(ablage)
        defer { s.lernende.schreibsperre = nil }
        s.fensterFuerFrage = { {} }
        let bestand = try #require(s.lernende.bestand)
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        #expect(s.lernende.setzen(bestand) != nil && s.verlustDroht)
        s.offenerDialog = .einstellungen
        s.dialogOeffnen(.klassen)
        #expect(!s.beendenErlauben(), "abgelehnt")
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.isEmpty, "keine Verlustfrage hinter dem kommenden Blatt")
        s.naechstenDialogOeffnen()
        s.offenerDialog = nil
        try await abwarten("nach dem Blatt der Hinweis") { s.meldungen.contains { $0.text == hauptflaechenhinweis } }
        #expect(!s.beendenErlauben() && s.rueckfrage?.bestaetigung == "Trotzdem beenden", "ohne Blatt steht die Verlustfrage")
        s.rueckfrageBeantworten(false)
    }
}
