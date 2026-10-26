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

/// Der Entwurf eines Blatts, den die Prüfung nachträglich ändert.
@MainActor
private final class Blattstand {
    var bestand: Lernendenbestand
    init(_ bestand: Lernendenbestand) { self.bestand = bestand }
}

/// Beantwortet die stehende Rückfrage wie ein Klick auf den Knopf ihres Alerts: Währenddessen hängt
/// das Alert noch (B95, E431). Danach gilt wieder die Vorgabe der Prüfung für `rueckfrageSichtbar`.
@MainActor
func antwortenBeiHaengendemAlert(_ s: Planungsspeicher, _ bestaetigt: Bool = true, weitere: Bool = false) {
    let vorher = s.rueckfrageSichtbar
    s.rueckfrageSichtbar = { true }
    if weitere { s.rueckfrageWeitere() } else { s.rueckfrageBeantworten(bestaetigt) }
    s.rueckfrageSichtbar = vorher
}

// ── Umbauende Handlungen erst nach dem Schließen des Alerts (B95, E417, E429–E431) ─────────────────
// Im Klick hängt das Alert noch; baut die Handlung dann die Hauptfläche oder ein Blatt um, schließt SwiftUI
// das Alert-Blatt mitten im Layout (Gattung B88). Jede Prüfung antwortet bei hängendem Alert und sieht nach,
// dass im Klick noch nichts geschah — und danach alles.

@Suite("Handlungen von Rückfragen, die die Hauptfläche oder ein Blatt umbauen, laufen erst nach dem Schließen des Alerts")
@MainActor
struct NachDemSchliessenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "schliessen-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    /// Im Klartext — ohne Verschlüsselung, die Lernendenverwaltung ist aus.
    private func klartext(_ ablage: URL) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        return s
    }

    /// Eingeschaltet: Anna mit einem Termin, dessen Vorhaben in der Klassenleitung steht (Woche 2).
    private func mitTermin(_ ablage: URL) async throws -> (Planungsspeicher, vorhaben: String) {
        let s = try klartext(ablage)
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: "Ein Satz, den man behält"))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let s0 = a.erstellt
        let (b, gruppe) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: s0))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna").namen, inGruppe: gruppe, jetzt: s0).bestand
        let anna = try #require(c.lernende.first).id
        let (d, termin) = try #require(c.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [anna],
                                                          datum: "2026-08-20", frist: "", uhrzeit: "07:45", jetzt: s0))
        #expect(s.lernendenUebernehmen(d.mitTerminwunsch(termin, zeile: "k-kl")) == nil)
        let vorhaben = try #require(s.planung?.eintraege.first { $0.termin == termin }).id
        return (s, vorhaben)
    }

    private func vorhaben(_ s: Planungsspeicher, _ id: String) -> Vorhaben? {
        s.planung?.eintraege.first { $0.id == id }
    }

    // ── Die Option selbst (E430, E431) ─────────────────────────────────

    @Test("Mit hängendem Alert läuft die Handlung erst, wenn es fort ist — auch wenn es länger ausblendet")
    func optionNachDemSchliessen() async throws {
        let ablage = try ordner("option")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let haengt = Merker()
        s.rueckfrageSichtbar = { haengt.an }
        var gelaufen = 0
        s.fragen("Umbauen?", bestaetigung: "Ja", nachDemSchliessen: true) { gelaufen += 1 }
        haengt.an = true
        s.rueckfrageBeantworten(true)
        #expect(gelaufen == 0, "im Klick noch nicht")
        await uhr.vorruecken(um: .seconds(1))  // über den Verzug hinaus, das Alert hängt noch
        #expect(gelaufen == 0, "solange das Alert hängt, nicht (Z-AU4-08)")
        haengt.an = false
        await uhr.vorruecken(um: .seconds(1))
        #expect(gelaufen == 1, "nach dem Schließen")
    }

    @Test("Auch der Knopf „Abbrechen“ läuft erst nach dem Schließen (Z-AU4-02)")
    func optionAbbrechenKnopf() async throws {
        let ablage = try ordner("option-abbrechen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var abgelehnt = 0
        s.fragen("Umbauen?", bestaetigung: "Ja", beiAblehnung: { abgelehnt += 1 }, nachDemSchliessen: true) {}
        antwortenBeiHaengendemAlert(s, false)
        #expect(abgelehnt == 0, "im Klick noch nicht")
        let gelaufen = await uhr.vorruecken(bis: { abgelehnt == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "nach dem Schließen")
    }

    @Test("Ohne hängendes Alert läuft die Handlung gleich (E431)")
    func optionOhneAlertGleich() throws {
        let ablage = try ordner("option-gleich")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        var gelaufen = 0
        s.fragen("Umbauen?", bestaetigung: "Ja", nachDemSchliessen: true) { gelaufen += 1 }
        s.rueckfrageBeantworten(true)
        #expect(gelaufen == 1)
    }

    @Test("Kommt nach der Antwort eine andere Frage, läuft die Handlung nach deren Antwort — sie geht nicht verloren")
    func optionHinterAndererFrage() async throws {
        let ablage = try ordner("option-andere")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var gelaufen = 0
        s.fragen("Umbauen?", bestaetigung: "Ja", nachDemSchliessen: true) { gelaufen += 1 }
        antwortenBeiHaengendemAlert(s)
        #expect(gelaufen == 0, "im Klick noch nicht")
        s.fragen("Eine andere Frage", bestaetigung: "Ja") {}
        let zurueckgestellt = await uhr.vorruecken(bis: { s.ausstehendeFortsetzungen == 0 }, hoechstens: .seconds(1))
        try #require(zurueckgestellt, "die Handlung wartet hinter der anderen Frage")
        #expect(gelaufen == 0, "solange die andere Frage steht, nicht")
        s.rueckfrageBeantworten(false)
        let nachgeholt = await uhr.vorruecken(bis: { gelaufen == 1 }, hoechstens: .seconds(1))
        try #require(nachgeholt, "nach ihrer Antwort")
    }

    @Test("Auch der dritte Knopf läuft erst nach dem Schließen")
    func optionDritterKnopf() async throws {
        let ablage = try ordner("option-weitere")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var weiter = 0
        s.fragen("Umbauen?", bestaetigung: "Ja", weitere: "Anders", beiWeitere: { weiter += 1 },
                 nachDemSchliessen: true) {}
        antwortenBeiHaengendemAlert(s, weitere: true)
        #expect(weiter == 0, "im Klick noch nicht")
        let gelaufen = await uhr.vorruecken(bis: { weiter == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "nach dem Schließen")
    }

    // ── Die Stellen (Durchsicht AU4, Gruppen C und D) ──────────────────

    @Test("„Ersetzen“ beim Öffnen einer Planung (B95)")
    func ersetzen() async throws {
        let ablage = try ordner("ersetzen")
        let quelle = try ordner("ersetzen-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _) = try await mitTermin(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        // Dieselbe Herkunft: kein Wechsel, sondern „… wird ersetzt“ — die Planung hat Vorhaben.
        var ersatz = try #require(s.planung)
        ersatz.titel = "Ersatz"
        let datei = quelle.appending(component: "ersatz.json")
        try Planungsdatei.schreiben(ersatz).write(to: datei)
        s.importieren(von: datei)
        #expect(s.rueckfrage?.bestaetigung == "Ersetzen", Comment(rawValue: s.rueckfrage?.text ?? "—"))
        antwortenBeiHaengendemAlert(s)
        #expect(s.planung?.titel == "Schuljahr 2026/27", "im Klick noch nicht ersetzt")
        let ersatzGeladen = await uhr.vorruecken(bis: { s.planung?.titel == "Ersatz" }, hoechstens: .seconds(1))
        try #require(ersatzGeladen, "nach dem Schließen ersetzt")
    }

    @Test("„Ohne Archiv fortfahren“ und „Verschlüsselung einrichten …“ bei „Neue Planung“")
    func neuePlanung() async throws {
        let ablage = try ordner("neue-planung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var angelegt = 0
        s.neuePlanungFragen { angelegt += 1 }
        #expect(s.rueckfrage?.bestaetigung == "Ohne Archiv fortfahren")
        antwortenBeiHaengendemAlert(s)
        #expect(angelegt == 0, "im Klick noch nicht angelegt")
        let angelegtGesehen = await uhr.vorruecken(bis: { angelegt == 1 }, hoechstens: .seconds(1))
        try #require(angelegtGesehen, "nach dem Schließen angelegt")
        s.neuePlanungFragen { angelegt += 1 }
        antwortenBeiHaengendemAlert(s, weitere: true)
        #expect(s.offenerDialog == nil, "im Klick noch kein Blatt")
        let blattGesehen = await uhr.vorruecken(bis: { s.offenerDialog == .verschluesselung }, hoechstens: .seconds(1))
        try #require(blattGesehen, "nach dem Schließen das Blatt")
        #expect(angelegt == 1)
    }

    @Test("„Verschlüsselung einrichten …“ aus der Sperre der Lernendenverwaltung")
    func lernendenSperre() async throws {
        let ablage = try ordner("lernenden-sperre")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.lernendenBlattOeffnen()
        #expect(s.rueckfrage?.bestaetigung == "Verschlüsselung einrichten …")
        antwortenBeiHaengendemAlert(s)
        #expect(s.offenerDialog == nil, "im Klick noch kein Blatt")
        let blattGesehen = await uhr.vorruecken(bis: { s.offenerDialog == .verschluesselung }, hoechstens: .seconds(1))
        try #require(blattGesehen, "nach dem Schließen das Blatt")
    }

    @Test("Vorhaben entfernen")
    func vorhabenEntfernen() async throws {
        let ablage = try ordner("vorhaben")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, v) = try await mitTermin(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.vorhabenOeffnen(id: v)  // Aus dem Blatt, an dem die Frage hängt (E418).
        s.vorhabenLoeschen(v)
        antwortenBeiHaengendemAlert(s)
        #expect(vorhaben(s, v) != nil, "im Klick noch da")
        let entfernt = await uhr.vorruecken(bis: { vorhaben(s, v) == nil }, hoechstens: .seconds(1))
        try #require(entfernt, "nach dem Schließen entfernt")
    }

    @Test("Gewählte Vorhaben entfernen")
    func auswahlEntfernen() async throws {
        let ablage = try ordner("auswahl")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        // Zwei gewählt — eines allein ginge über „Vorhaben entfernen“.
        var p = try #require(s.planung)
        let kurs = try #require(p.klassen.first { $0.name == "6a" }).id
        p.eintraege = ["a", "b"].map {
            Vorhaben(id: $0, klasseId: kurs, woche: 1, titel: $0, text: "", erledigt: false, materialien: [], links: [])
        }
        s.planung = p
        s.auswahl = ["a", "b"]
        s.auswahlLoeschen()
        #expect(s.rueckfrage?.text.hasPrefix("2 Vorhaben endgültig entfernen?") == true, Comment(rawValue: s.rueckfrage?.text ?? "—"))
        antwortenBeiHaengendemAlert(s)
        #expect(s.planung?.eintraege.count == 2, "im Klick noch da")
        let entfernt = await uhr.vorruecken(bis: { s.planung?.eintraege.isEmpty == true }, hoechstens: .seconds(1))
        try #require(entfernt, "nach dem Schließen entfernt")
    }

    @Test("Termin-Kennzeichnung entfernen")
    func terminkennzeichnung() async throws {
        let ablage = try ordner("kennzeichnung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, v) = try await mitTermin(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.terminkennzeichnungEntfernenFragen(v)
        antwortenBeiHaengendemAlert(s)
        #expect(vorhaben(s, v)?.istTermin == true, "im Klick noch Termin")
        let entfernt = await uhr.vorruecken(bis: { vorhaben(s, v)?.istTermin == false }, hoechstens: .seconds(1))
        try #require(entfernt, "nach dem Schließen kein Termin mehr")
    }

    @Test("Termin löschen beim „Übernehmen“ im Vorhaben-Dialog")
    func terminImDialog() async throws {
        let ablage = try ordner("termin-dialog")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, v) = try await mitTermin(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.vorhabenOeffnen(id: v)
        var e = try #require(s.vorhabenDialog)
        e.termin = false
        s.vorhabenSichernFragen(e)
        #expect(s.rueckfrage?.bestaetigung == "Löschen")
        antwortenBeiHaengendemAlert(s)
        #expect(vorhaben(s, v)?.istTermin == true, "im Klick noch Termin")
        let entfernt = await uhr.vorruecken(bis: { vorhaben(s, v)?.istTermin == false }, hoechstens: .seconds(1))
        try #require(entfernt, "nach dem Schließen kein Termin mehr")
    }

    @Test("Klasse entfernen")
    func klasseEntfernen() async throws {
        let ablage = try ordner("klasse")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let klasse = try #require(s.planung?.klassen.first { $0.name == "6a" })
        s.offenerDialog = .klassen  // Aus dem Blatt, an dem die Frage hängt (E418).
        s.klasseEntfernen(klasse)
        antwortenBeiHaengendemAlert(s)
        #expect(s.planung?.klasse(klasse.id) != nil, "im Klick noch da")
        let entfernt = await uhr.vorruecken(bis: { s.planung?.klasse(klasse.id) == nil }, hoechstens: .seconds(1))
        try #require(entfernt, "nach dem Schließen entfernt")
    }

    @Test("Wochen kürzen in den Einstellungen")
    func wochenKuerzen() async throws {
        let ablage = try ordner("wochen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _) = try await mitTermin(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let p = try #require(s.planung)
        s.offenerDialog = .einstellungen  // Aus dem Blatt, an dem die Frage hängt (E418).
        s.einstellungenUebernehmen(start: p.start, wochen: 1, ersterSchultag: p.ersterSchultag)
        #expect(s.rueckfrage?.bestaetigung == "Entfernen", Comment(rawValue: s.rueckfrage?.text ?? "—"))
        antwortenBeiHaengendemAlert(s)
        #expect(s.planung?.wochen == 10, "im Klick noch nicht gekürzt")
        let gekuerzt = await uhr.vorruecken(bis: { s.planung?.wochen == 1 }, hoechstens: .seconds(1))
        try #require(gekuerzt, "nach dem Schließen gekürzt")
    }

    // ── Das Blatt „Lernende“ (AU4a, Durchsicht E und Z-AU4-03) ─────────────

    /// Mit Termin, dazu das Blatt mit Griff — Anna ist in der Gruppe, der Termin ihr Anliegen.
    private func imBlatt(_ ablage: URL, griff: Lernendenblattgriff = Lernendenblattgriff())
        async throws -> (Planungsspeicher, entwurf: Lernendenbestand, gruppe: String, anna: String, termin: String) {
        let (s, _) = try await mitTermin(ablage)
        let b = try #require(s.lernende.bestand)
        let gruppe = try #require(b.lerngruppen.first).id
        let anna = try #require(b.lernende.first).id
        let termin = try #require(b.anliegen.first { $0.art == .termin }).id
        s.lernendenblattUebernimmt({ _ in }, griff: griff)
        s.offenerDialog = .lernende
        return (s, b, gruppe, anna, termin)
    }

    @Test("Lerngruppe, Person und Anliegen im Blatt „Lernende“ löschen")
    func loeschenImBlatt() async throws {
        let ablage = try ordner("loeschen-blatt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, b, gruppe, anna, termin) = try await imBlatt(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var gesetzt: [Lernendenbestand] = []
        s.lerngruppeLoeschenFragen(gruppe, in: b) { gesetzt.append($0) }
        antwortenBeiHaengendemAlert(s)
        #expect(gesetzt.isEmpty, "Gruppe: im Klick noch nicht")
        let gruppeGeloescht = await uhr.vorruecken(bis: { gesetzt.count == 1 }, hoechstens: .seconds(1))
        try #require(gruppeGeloescht, "Gruppe: nach dem Schließen")
        await uhr.vorruecken(um: .zero)  // auch, was zur selben Frist noch fällig ist (Z-AT6g2-01)
        s.personLoeschenFragen(anna, in: b) { gesetzt.append($0) }
        antwortenBeiHaengendemAlert(s)
        #expect(gesetzt.count == 1, "Person: im Klick noch nicht")
        let personGeloescht = await uhr.vorruecken(bis: { gesetzt.count == 2 }, hoechstens: .seconds(1))
        try #require(personGeloescht, "Person: nach dem Schließen")
        await uhr.vorruecken(um: .zero)  // auch, was zur selben Frist noch fällig ist (Z-AT6g2-01)
        s.anliegenLoeschenFragen(termin, in: b) { gesetzt.append($0) }
        antwortenBeiHaengendemAlert(s)
        #expect(gesetzt.count == 2, "Anliegen: im Klick noch nicht")
        let anliegenGeloescht = await uhr.vorruecken(bis: { gesetzt.count == 3 }, hoechstens: .seconds(1))
        try #require(anliegenGeloescht, "Anliegen: nach dem Schließen")
    }

    @Test("Änderungen im Blatt „Lernende“ verwerfen")
    func verwerfenImBlatt() async throws {
        let ablage = try ordner("verwerfen-blatt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _, _, _) = try await imBlatt(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var verworfen = 0
        s.lernendenVerwerfenFragen { verworfen += 1 }
        antwortenBeiHaengendemAlert(s)
        #expect(verworfen == 0, "im Klick noch nicht")
        let gelaufen = await uhr.vorruecken(bis: { verworfen == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "nach dem Schließen")
    }

    @Test("Beim Beenden mit Blatt „Lernende“: den offenen Bogen verwerfen")
    func beendenBogenVerwerfen() async throws {
        let ablage = try ordner("beenden-bogen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let offen = Merker()
        offen.an = true
        let (s, _, _, _, _) = try await imBlatt(ablage, griff: Lernendenblattgriff(
            bogenOffen: { offen.an }, bogenSchliessen: { offen.an = false }))
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var weiter = 0, zuBeimWeiter = false
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1; zuBeimWeiter = !offen.an })
        #expect(gefragt)
        #expect(s.rueckfrage?.text == "Den offenen Bogen verwerfen?")
        antwortenBeiHaengendemAlert(s)
        #expect(offen.an, "im Klick noch offen")
        let gelaufen = await uhr.vorruecken(bis: { !offen.an && weiter == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "nach dem Schließen zu, dann weiter")
        #expect(zuBeimWeiter, "erst zu, dann weiter")
    }

    @Test("Beim Beenden mit Blatt „Lernende“: die getippten Namen verwerfen")
    func beendenNamenVerwerfen() async throws {
        let ablage = try ordner("beenden-namen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let namen = Merker()
        namen.an = true
        let (s, _, _, _, _) = try await imBlatt(ablage, griff: Lernendenblattgriff(
            namenOffen: { namen.an }, namenVerwerfen: { namen.an = false }))
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var weiter = 0, verworfenBeimWeiter = false
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1; verworfenBeimWeiter = !namen.an })
        #expect(gefragt)
        #expect(s.rueckfrage?.text == "Die eingegebenen Namen verwerfen?")
        antwortenBeiHaengendemAlert(s)
        #expect(namen.an, "im Klick noch nicht verworfen")
        let gelaufen = await uhr.vorruecken(bis: { !namen.an && weiter == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "nach dem Schließen verworfen, dann weiter")
        #expect(verworfenBeimWeiter, "erst verworfen, dann weiter")
    }

    @Test("Beim Beenden mit Blatt „Lernende“: „Übernehmen“ schreibt erst nach dem Schließen — der Griff geht sofort (E319)")
    func beendenUebernehmen() async throws {
        let ablage = try ordner("beenden-uebernehmen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, b, _, _, termin) = try await imBlatt(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let geaendert = b.mitAnliegen(termin, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
        var weiter = 0
        var titelBeimWeiter: String?
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: {
            weiter += 1
            titelBeimWeiter = s.lernende.bestand?.anliegen.first { $0.id == termin }?.titel
        })
        #expect(gefragt)
        antwortenBeiHaengendemAlert(s)
        #expect(s.lernende.bestand?.anliegen.first { $0.id == termin }?.titel == "Elterngespräch"
                && s.lernendenblattGriff == nil && s.handlungAussteht,
                "im Klick noch nicht übernommen — der Griff ist abgegeben, ein zweites ⌘Q prallt bis dahin ab (E436)")
        let gelaufen = await uhr.vorruecken(bis: {
            s.lernende.bestand?.anliegen.first { $0.id == termin }?.titel == "Gespräch" && weiter == 1
        }, hoechstens: .seconds(1))
        try #require(gelaufen, "nach dem Schließen übernommen, dann weiter")
        #expect(titelBeimWeiter == "Gespräch", "erst übernommen, dann weiter")
    }

    @Test("Beim Beenden mit Blatt „Lernende“: Kommt nach „Verwerfen“ eine andere Frage, gilt sie — die Namen gehen, das Beenden bleibt aus (Z14b-11)")
    func beendenAndereFrageGilt() async throws {
        let ablage = try ordner("beenden-andere-frage")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let namen = Merker()
        namen.an = true
        let (s, _, _, _, _) = try await imBlatt(ablage, griff: Lernendenblattgriff(
            namenOffen: { namen.an }, namenVerwerfen: { namen.an = false }))
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt)
        antwortenBeiHaengendemAlert(s)
        // Das Alert ist fort, die Handlung noch nicht gelaufen: eine andere Frage, etwa nach ⎋ im Blatt.
        s.fragen("Eine andere Frage?", bestaetigung: "Ja", ort: .lernende, ablehnung: "Nein") {}
        #expect(s.ausstehendeFortsetzungen == 1, "die Fortsetzung steht noch aus")
        let zurueckgestellt = await uhr.vorruecken(bis: { s.ausstehendeFortsetzungen == 0 }, hoechstens: .seconds(1))
        try #require(zurueckgestellt, "die Fortsetzung sieht die andere Frage")
        #expect(namen.an, "solange die andere Frage steht, noch nicht verworfen")
        s.rueckfrageBeantworten(false)
        let verworfenDanach = await uhr.vorruecken(bis: { !namen.an }, hoechstens: .seconds(1))
        try #require(verworfenDanach, "nach ihrer Antwort verworfen — Bestätigtes geht nicht verloren")
        // Steht nach dem Verwerfen keine Fortsetzung mehr aus, kommt auch das Beenden nicht mehr (E549).
        #expect(weiter == 0, "das Beenden wartet auf ein neues ⌘Q")
        #expect(s.ausstehendeFortsetzungen == 0, "keine Fortsetzung steht mehr aus")
    }

    @Test("⌘Z im Blatt mit getippter Liste: „Verwerfen“ wirkt erst nach dem Schließen, dann der Schritt")
    func widerrufenNamenVerwerfen() async throws {
        let ablage = try ordner("widerrufen-namen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let namen = Merker()
        namen.an = true
        let (s, b, _, _, termin) = try await imBlatt(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let geaendert = b.mitAnliegen(termin, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        var gesetzt: [Lernendenbestand] = []
        s.lernendenblattUebernimmt({ gesetzt.append($0) }, griff: Lernendenblattgriff(
            gruppeBleibt: { _ in false }, namenOffen: { namen.an }, namenVerwerfen: { namen.an = false }))
        s.lernendenverlauf.anmelden(Schrittname.terminAendern, kennung: termin, vorher: b, nachher: geaendert)
        s.widerrufen()
        #expect(s.rueckfrage?.text == "Die eingegebenen Namen verwerfen?")
        antwortenBeiHaengendemAlert(s)
        #expect(namen.an, "im Klick noch nicht verworfen")
        let gelaufen = await uhr.vorruecken(bis: { !namen.an && gesetzt.count == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "nach dem Schließen verworfen, dann das ⌘Z")
    }

    @Test("⌘Z im Blatt mit getippter Liste: Ist das Blatt zu, ehe der Schritt läuft, entfällt er — die Planung bleibt")
    func widerrufenBlattZu() async throws {
        let ablage = try ordner("widerrufen-blatt-zu")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let namen = Merker()
        namen.an = true
        let (s, b, _, _, termin) = try await imBlatt(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let geaendert = b.mitAnliegen(termin, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(
            gruppeBleibt: { _ in false }, namenOffen: { namen.an }, namenVerwerfen: { namen.an = false }))
        s.lernendenverlauf.anmelden(Schrittname.terminAendern, kennung: termin, vorher: b, nachher: geaendert)
        let schritte = s.verlauf.zurueck.count
        #expect(schritte > 0, "die Planung hat einen Schritt zum Zurücknehmen")
        s.widerrufen()
        #expect(s.rueckfrage?.text == "Die eingegebenen Namen verwerfen?")
        antwortenBeiHaengendemAlert(s)
        let verworfen = await uhr.vorruecken(bis: { !namen.an }, hoechstens: .seconds(1))
        try #require(verworfen, "nach dem Schließen verworfen")
        await uhr.vorruecken(um: .zero)  // auch, was zur selben Frist noch fällig ist (Z-AT6g2-01)
        // Verworfen, der Schritt noch nicht gelaufen: Das Blatt schließt, etwa mit ⏎ für sein „Übernehmen“.
        #expect(s.ausstehendeFortsetzungen == 1, "der Schritt steht noch aus")
        s.lernendenblattGibtAb()
        s.offenerDialog = nil
        let gelaufen = await uhr.vorruecken(bis: { s.ausstehendeFortsetzungen == 0 }, hoechstens: .seconds(1))
        try #require(gelaufen, "die Fortsetzung des Schritts lief")
        #expect(s.verlauf.zurueck.count == schritte, "kein Schritt der Planung zurückgenommen")
        #expect(s.ausstehendeFortsetzungen == 0, "keine Fortsetzung steht mehr aus")
    }

    @Test("Sitzplan löschen")
    func sitzplanLoeschen() async throws {
        let ablage = try ordner("sitzplan")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let klasse = try #require(s.planung?.klassen.first { $0.name == "6a" })
        #expect(s.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse.id, namen: ["Anna", "Ben"])) == nil)
        s.offenerDialog = .klassen  // Aus dem Blatt, an dem die Frage hängt (E418).
        s.sitzplanEntfernen(klasse: klasse.id, ort: .klassen)
        antwortenBeiHaengendemAlert(s)
        #expect(s.sitzplan(fuer: klasse.id) != nil, "im Klick noch da")
        let geloescht = await uhr.vorruecken(bis: { s.sitzplan(fuer: klasse.id) == nil }, hoechstens: .seconds(1))
        try #require(geloescht, "nach dem Schließen gelöscht")
    }

    // ── Die Lücke: Das Alert ist fort, die Handlung läuft gleich (AU4c, E435–E439) ─────────────

    /// Eine Rückfrage mit verschobener Handlung, beantwortet bei hängendem Alert — danach die Lücke.
    private func inDieLuecke(_ s: Planungsspeicher, gelaufen: Merker) {
        s.fragen("Probe?", bestaetigung: "Ja", nachDemSchliessen: true) { gelaufen.an = true }
        antwortenBeiHaengendemAlert(s)
    }

    @Test("In der Lücke prallt ⌘Z ab, mit Ton — danach wirkt es wieder (E435)")
    func befehlInDerLuecke() async throws {
        let ablage = try ordner("luecke-befehl")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.titelSetzen("Ein neuer Titel")
        let schritte = s.verlauf.zurueck.count
        let gelaufen = Merker()
        inDieLuecke(s, gelaufen: gelaufen)
        let vorher = s.gesperrteBefehle
        s.widerrufen()
        #expect(s.handlungAussteht && s.gesperrteBefehle == vorher + 1 && s.verlauf.zurueck.count == schritte,
                "in der Lücke: nichts zurückgenommen, der Befehl prallt ab")
        let handlungGelaufen = await uhr.vorruecken(bis: { gelaufen.an && !s.handlungAussteht }, hoechstens: .seconds(1))
        try #require(handlungGelaufen, "die Handlung läuft")
        s.widerrufen()
        #expect(s.verlauf.zurueck.count == schritte - 1 && s.planung?.titel != "Ein neuer Titel", "danach wirkt ⌘Z wieder")
    }

    @Test("In der Lücke prallt das Beenden ab — über ⌘Q wie über AppKit; danach beendet ein neues (E436)")
    func beendenInDerLuecke() async throws {
        let ablage = try ordner("luecke-beenden")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var beendet = 0
        s.appBeenden = { beendet += 1 }
        let gelaufen = Merker()
        inDieLuecke(s, gelaufen: gelaufen)
        let vorher = s.gesperrteBefehle
        s.beenden()
        let erlaubt = s.beendenErlauben()
        #expect(beendet == 0, "⌘Q in der Lücke: nicht beendet")
        #expect(!erlaubt && s.gesperrteBefehle == vorher + 2, "AppKit fragt in der Lücke: abgelehnt — beides mit Ton")
        let handlungGelaufen = await uhr.vorruecken(bis: { gelaufen.an && !s.handlungAussteht }, hoechstens: .seconds(1))
        try #require(handlungGelaufen, "die Handlung läuft")
        s.beenden()
        #expect(beendet == 1, "danach beendet ein neues ⌘Q")
    }

    @Test("Ein Skript, dessen Beenden in der Lücke abprallt, erfährt den Grund (E439)")
    func beendengrundInDerLuecke() {
        #expect(Planungsspeicher.beendengrund(frage: nil, wartete: false, handlung: true)
                == "Eine bestätigte Handlung läuft noch; das Beenden wurde abgelehnt — ein erneutes Beenden beendet.")
    }

    @Test("In der Lücke prallt ein Knopf über `blattknopf` ab, mit Ton — danach wirkt er (E437)")
    func blattknopfInDerLuecke() async throws {
        let ablage = try ordner("luecke-knopf")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let gedrueckt = Merker()
        let knopf = s.blattknopf { gedrueckt.an = true }
        let gelaufen = Merker()
        inDieLuecke(s, gelaufen: gelaufen)
        let vorher = s.gesperrteBefehle
        knopf()
        #expect(!gedrueckt.an && s.gesperrteBefehle == vorher + 1, "in der Lücke: der Knopf prallt ab")
        let handlungGelaufen = await uhr.vorruecken(bis: { gelaufen.an && !s.handlungAussteht }, hoechstens: .seconds(1))
        try #require(handlungGelaufen, "die Handlung läuft")
        knopf()
        #expect(gedrueckt.an, "danach wirkt der Knopf")
    }

    @Test("In der Lücke stellt das Blatt „Lernende“ keine neue Löschfrage (E437, Z-AU4a-02)")
    func loeschenInDerLuecke() async throws {
        let ablage = try ordner("luecke-loeschen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, b, gruppe, _, termin) = try await imBlatt(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var gesetzt: [Lernendenbestand] = []
        s.anliegenLoeschenFragen(termin, in: b) { gesetzt.append($0) }
        antwortenBeiHaengendemAlert(s)
        let vorher = s.gesperrteBefehle
        s.lerngruppeLoeschenFragen(gruppe, in: b) { gesetzt.append($0) }
        #expect(s.rueckfrage == nil && s.gesperrteBefehle == vorher + 1, "in der Lücke: keine zweite Frage, mit Ton")
        let geloescht = await uhr.vorruecken(bis: { gesetzt.count == 1 }, hoechstens: .seconds(1))
        try #require(geloescht, "die erste Löschung läuft")
    }

    @Test("Entfällt das Beenden nach „Verwerfen“, weil eine andere Frage kam, fragt ein späteres ⌘Q wieder (Z-AU4a-12)")
    func beendenEntfaelltFragtWieder() async throws {
        let ablage = try ordner("beenden-entfaellt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, b, _, _, termin) = try await imBlatt(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let geaendert = b.mitAnliegen(termin, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt)
        antwortenBeiHaengendemAlert(s, weitere: true)
        s.fragen("Eine andere Frage?", bestaetigung: "Ja", ort: .lernende, ablehnung: "Nein") {}
        #expect(s.ausstehendeFortsetzungen == 1, "das Beenden steht noch aus")
        await uhr.vorruecken(um: .seconds(1))
        #expect(s.ausstehendeFortsetzungen == 0, "die Fortsetzung sieht die andere Frage")
        s.rueckfrageBeantworten(false)
        await uhr.vorruecken(um: .seconds(1))  // über den Verzug der Fortsetzung hinaus
        #expect(s.ausstehendeFortsetzungen == 0, "nichts steht mehr aus")
        #expect(weiter == 0, "das Beenden entfiel (Z14b-11)")
        let wieder = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(wieder, "ein späteres ⌘Q fragt wieder — das Blatt hat seine Änderungen noch")
    }

    // ── Nachgefasst nach der Review (Z-AU4c-01–12) ─────────────

    @Test("In der Lücke sperrt der Speicher Tasten und Klicks für den Ereignis-Monitor, mit Ton (Z-AU4c-01/-02)")
    func eingabeInDerLuecke() async throws {
        let ablage = try ordner("luecke-eingabe")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let gelaufen = Merker()
        inDieLuecke(s, gelaufen: gelaufen)
        let vorher = s.gesperrteBefehle
        let gesperrt = s.eingabeSperrt()
        #expect(gesperrt && s.gesperrteBefehle == vorher + 1, "in der Lücke: die Eingabe prallt ab")
        let handlungGelaufen = await uhr.vorruecken(bis: { gelaufen.an && !s.handlungAussteht }, hoechstens: .seconds(1))
        try #require(handlungGelaufen, "die Handlung läuft")
        let danach = s.eingabeSperrt()
        #expect(!danach && s.gesperrteBefehle == vorher + 1, "danach: frei, ohne Ton")
    }

    @Test("Ein Skript erfährt den Grund der Lücke auch, solange das Alert noch ausblendet (Z-AU4c-06/-07)")
    func beendengrundJetztInDerLuecke() async throws {
        let ablage = try ordner("luecke-grund")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let gelaufen = Merker()
        inDieLuecke(s, gelaufen: gelaufen)
        let text = "Eine bestätigte Handlung läuft noch; das Beenden wurde abgelehnt — ein erneutes Beenden beendet."
        let ausblendend = s.beendengrundJetzt(wartete: true)
        let fort = s.beendengrundJetzt(wartete: false)
        #expect(ausblendend == text, Comment(rawValue: ausblendend))
        #expect(fort == text, Comment(rawValue: fort))
        let handlungGelaufen = await uhr.vorruecken(bis: { gelaufen.an }, hoechstens: .seconds(1))
        try #require(handlungGelaufen, "die Handlung läuft")
    }

    @Test("Steht eine Frage, die nicht zu sehen ist, endet die Sperre der Lücke — keine Dauersperre (Z-AU4c-04)")
    func unsichtbareFrageHebtSperre() async throws {
        let ablage = try ordner("luecke-unsichtbar")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let gelaufen = Merker()
        inDieLuecke(s, gelaufen: gelaufen)
        s.rueckfrageSichtbar = { false }
        s.fragen("Eine Frage, die nicht zu sehen ist?", bestaetigung: "Ja") {}
        #expect(s.rueckfrage != nil && !s.handlungAussteht && !s.frageSperrtBefehl(), "die Lücke sperrt nicht mehr")
        // Erst sieht die Fortsetzung die Frage und stellt sich zurück (H2-01) — dann die Antwort.
        let zurueckgestellt = await uhr.vorruecken(bis: { s.ausstehendeFortsetzungen == 0 }, hoechstens: .seconds(1))
        try #require(zurueckgestellt, "die Fortsetzung wartet hinter der Frage")
        #expect(!gelaufen.an, "zurückgestellt, noch nicht gelaufen")
        s.rueckfrageBeantworten(false)
        let handlungGelaufen = await uhr.vorruecken(bis: { gelaufen.an }, hoechstens: .seconds(1))
        try #require(handlungGelaufen, "nach ihrer Antwort läuft die Handlung")
    }

    @Test("Eine Fortsetzung geht an der Sperre einer anderen Lücke vorbei (Z-AU4c-10)")
    func fortsetzungGehtVorbei() async throws {
        let ablage = try ordner("luecke-fortsetzung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.titelSetzen("Ein neuer Titel")
        let schritte = s.verlauf.zurueck.count
        let lueckeBeimLauf = Merker()
        s.nachDerAntwort { [weak s] in
            lueckeBeimLauf.an = s?.handlungAussteht == true
            s?.widerrufen()
        }
        // Die zweite Lücke beginnt vor dem ersten `await`. Beide Fortsetzungen haben dieselbe Frist; die zuerst
        // angemeldete läuft zuerst — beim Lauf der ersten besteht die Lücke (E549).
        let gelaufen = Merker()
        inDieLuecke(s, gelaufen: gelaufen)
        let zurueckgenommen = await uhr.vorruecken(bis: { s.verlauf.zurueck.count == schritte - 1 }, hoechstens: .seconds(1))
        try #require(zurueckgenommen, "die Fortsetzung nahm den Schritt zurück")
        #expect(lueckeBeimLauf.an, "beim Lauf der Fortsetzung bestand die andere Lücke (Z-AU4c-21)")
        let handlungGelaufen = await uhr.vorruecken(bis: { gelaufen.an }, hoechstens: .seconds(1))
        try #require(handlungGelaufen, "die verschobene Handlung läuft")
    }

    @Test("Entfällt das Beenden nach „Übernehmen“, fragt ein späteres ⌘Q nur nach Änderungen seit dem Übernehmen (Z-AU4c-19)")
    func beendenNachUebernehmenEntfaellt() async throws {
        let ablage = try ordner("uebernehmen-entfaellt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, b, _, _, termin) = try await imBlatt(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let geaendert = b.mitAnliegen(termin, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        let blatt = Blattstand(geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(ausgang: { b }, aenderungen: { blatt.bestand }))
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt)
        antwortenBeiHaengendemAlert(s)
        let uebernommen = await uhr.vorruecken(bis: { s.lernende.bestand?.anliegen.first { $0.id == termin }?.titel == "Gespräch" }, hoechstens: .seconds(1))
        try #require(uebernommen, "übernommen")
        await uhr.vorruecken(um: .zero)  // auch, was zur selben Frist noch fällig ist (Z-AT6g2-01)
        // Gleich nach dem Übernehmen eine andere Frage: Das Beenden entfällt (Z14b-11).
        s.fragen("Eine andere Frage?", bestaetigung: "Ja", ort: .lernende, ablehnung: "Nein") {}
        #expect(s.ausstehendeFortsetzungen == 1, "das Beenden steht noch aus")
        let gesehen = await uhr.vorruecken(bis: { s.ausstehendeFortsetzungen == 0 }, hoechstens: .seconds(1))
        try #require(gesehen, "die Fortsetzung sieht die andere Frage, ehe sie beantwortet wird")
        s.rueckfrageBeantworten(false)
        #expect(weiter == 0, "das Beenden entfiel")
        let ohneAenderung = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(!ohneAenderung, "seit dem Übernehmen nichts geändert: keine Frage")
        blatt.bestand = geaendert.mitAnliegen(termin, titel: "Gespräch mit den Eltern", datum: "2026-08-20", frist: "", notiz: "",
                                              jetzt: geaendert.geaendert)
        let mitAenderung = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(mitAenderung, "danach geändert: ⌘Q fragt wieder")
    }

    @Test("Eine Datei aus dem Finder in der Lücke: nicht geöffnet — mit dem Grund der Lücke (Z-AU4c-12)")
    func finderInDerLuecke() async throws {
        let ablage = try ordner("luecke-finder")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try klartext(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let gelaufen = Merker()
        inDieLuecke(s, gelaufen: gelaufen)
        s.importieren(von: ablage.appending(component: "fremd.json"))
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.contains { $0.text == "„fremd.json“ wurde nicht geöffnet, weil eine bestätigte Handlung noch lief. "
                                       + "Bitte die Datei erneut öffnen." }
        }, hoechstens: .seconds(1))
        try #require(gesehen, "die Meldung kommt nach der Lücke")
    }
}
