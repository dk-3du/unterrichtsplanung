// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Rückfragen rund um die Lernenden (v80, AP14b) ─────────────────────────
// Nach der Review: Beenden mit geändertem Blatt (E300), „Neue Planung“ ohne
// Verschlüsselung (E302), das Löschen einer Person nennt die Vorhaben ihrer
// Termine (W2-05), das Aufheben nennt die Arten der Rettungskopien (E301).

/// Ein Zustand, den ein Abschluss liest und die Prüfung umstellt.
@MainActor
private final class Merker {
    var an = false
}

@Suite("Rückfragen rund um die Lernenden: Beenden, neue Planung, Person löschen, Aufheben")
@MainActor
struct LernendenRueckfragenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "rueckfragen-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.id = "k-kl"
        p.klassen += [leitung]
        // Wie `sonderzeileHinzufuegen`: Ohne Farbe läse sich das Archiv beim Jahreswechsel anders, als es geschrieben wurde.
        p.farbenVervollstaendigen()
        return p
    }

    /// Eingeschaltet: Anna und Ben, ein Termin für Anna mit Vorhaben in der Klassenleitung.
    private func speicher(_ ablage: URL) async throws -> (Planungsspeicher, termin: String, anna: String) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: "Ein Satz, den man behält"))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let s0 = a.erstellt
        let (b, gruppe) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: s0))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: gruppe, jetzt: s0).bestand
        let anna = try #require(c.lernende.first).id
        let (d, termin) = try #require(c.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [anna],
                                                          datum: "2026-08-20", frist: "", uhrzeit: "07:45", jetzt: s0))
        #expect(s.lernendenUebernehmen(d.mitTerminwunsch(termin, zeile: "k-kl")) == nil)
        #expect(s.planung?.eintraege.contains { $0.termin == termin } == true)
        return (s, termin, anna)
    }

    @Test("Beenden mit geändertem Blatt „Lernende“ (E300): Übernehmen, Verwerfen oder Abbrechen — ohne Änderung keine Frage")
    func beendenFragt() async throws {
        let ablage = try ordner("beenden")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let ohneBlatt = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(!ohneBlatt, "ohne Blatt nichts zu fragen")
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
        s.offenerDialog = .lernende  // Die Frage hängt am Blatt (E418).
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt, "geändert: Die Frage steht")
        let frage = try #require(s.rueckfrage)
        #expect(frage.text == "Die Änderungen an den Lernenden übernehmen?\n\nDas Blatt „Lernende“ ist noch offen; ohne "
                + "„Übernehmen“ gehen seine Änderungen beim Beenden verloren.", Comment(rawValue: frage.text))
        #expect(frage.bestaetigung == "Übernehmen" && frage.weitere == "Verwerfen" && frage.ablehnung == "Abbrechen"
                && frage.ort == .lernende)
        s.rueckfrageBeantworten(true)
        #expect(s.lernende.bestand?.anliegen.first { $0.id == t }?.titel == "Gespräch", "übernommen")
        // Die Fortsetzung kommt nach der Frist, nicht in der Knopf-Handlung (E319).
        let weiterNachUebernehmen = await uhr.vorruecken(bis: { weiter == 1 }, hoechstens: .seconds(1))
        try #require(weiterNachUebernehmen, "übernommen, dann weiter")
        let nochmal = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(!nochmal, "einmal gefragt, nicht noch einmal")

        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { b }))
        var verworfen = 0
        let zweite = s.lernendenblattBeimBeendenFragen(dann: { verworfen += 1 })
        #expect(zweite)
        s.rueckfrageWeitere()
        #expect(s.lernende.bestand?.anliegen.first { $0.id == t }?.titel == "Gespräch", "verworfen")
        let weiterNachVerwerfen = await uhr.vorruecken(bis: { verworfen == 1 }, hoechstens: .seconds(1))
        try #require(weiterNachVerwerfen, "verworfen, dann weiter")

        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { b }))
        var abgebrochen = 0
        let dritte = s.lernendenblattBeimBeendenFragen(dann: { abgebrochen += 1 })
        #expect(dritte)
        s.rueckfrageBeantworten(false)
        #expect(abgebrochen == 0, "abgebrochen: Die App bleibt")
        s.lernendenblattGibtAb()
        let abgegeben = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(!abgegeben, "abgegeben: nichts mehr zu fragen")
    }

    @Test("„Übernehmen“/„Verwerfen“ beim Beenden: Die Fortsetzung wartet, bis das Alert fort ist (Z14c3-12, E319)")
    func e300FortsetzungWartetAufDasAlert() async throws {
        let ablage = try ordner("e300-alert")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let blendetAus = Merker()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || blendetAus.an }
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.offenerDialog = .lernende  // Die Frage hängt am Blatt (E418).
        for knopf in ["Übernehmen", "Verwerfen"] {
            s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
            var weiter = 0
            let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
            #expect(gefragt)
            // Die Knopf-Handlung läuft, während das Alert-Blatt noch hängt.
            blendetAus.an = true
            if knopf == "Übernehmen" { s.rueckfrageBeantworten(true) } else { s.rueckfrageWeitere() }
            #expect(weiter == 0 && s.lernendenblattGriff == nil, "\(knopf): noch nicht — der Griff ist abgegeben")
            await uhr.vorruecken(um: .seconds(1))  // über die Frist der Fortsetzung hinaus
            #expect(weiter == 0, "\(knopf): auch nach der Frist nicht, solange das Alert hängt")
            blendetAus.an = false
            await uhr.vorruecken(um: .seconds(1))
            #expect(weiter == 1, "\(knopf): Danach geht das Beenden weiter")
        }
    }

    @Test("Beenden mit getippter, nicht eingetragener Namensliste (Z14b-02): erst „Die eingegebenen Namen verwerfen?“")
    func beendenMitNamensliste() async throws {
        let ablage = try ordner("namensliste")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        var namen = true
        var vorbereitet = 0
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(
            vorbereiten: { vorbereitet += 1 }, namenOffen: { namen }, namenVerwerfen: { namen = false },
            aenderungen: { geaendert }))
        s.offenerDialog = .lernende  // Die Frage hängt am Blatt (E418).
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt && vorbereitet == 1, "Bögen zu, Felder übernommen, dann die Frage")
        #expect(s.rueckfrage?.text == "Die eingegebenen Namen verwerfen?" && s.rueckfrage?.ablehnung == "Weiter bearbeiten",
                Comment(rawValue: s.rueckfrage?.text ?? "—"))
        s.rueckfrageBeantworten(false)
        #expect(namen && weiter == 0, "„Weiter bearbeiten“: Die App bleibt, die Namen auch")
        let nochmal = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(nochmal)
        s.rueckfrageBeantworten(true)
        #expect(!namen, "verworfen")
        #expect(weiter == 0, "noch nicht: erst, wenn die Frage geschlossen ist")
        let gelaufen = await uhr.vorruecken(bis: { weiter == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "danach geht das Beenden weiter")
    }

    @Test("Steht in der Wartezeit eine andere Frage, setzt die verzögerte Fortsetzung das Beenden nicht fort (Z14b-11)")
    func fortsetzungWeichtAnderer() async throws {
        let ablage = try ordner("fortsetzung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var namen = true
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(namenOffen: { namen }, namenVerwerfen: { namen = false }))
        s.offenerDialog = .lernende  // Die Fragen hängen am Blatt (E418).
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt)
        s.rueckfrageBeantworten(true)
        s.fragen("Eine andere Frage des Blatts", bestaetigung: "Ja", ort: .lernende) {}
        #expect(s.ausstehendeFortsetzungen == 1, "die Fortsetzung steht noch aus")
        // Die Fortsetzung kommt nach `folgefrageVerzug`; die Uhr rückt über sie hinaus.
        await uhr.vorruecken(um: .seconds(1))
        #expect(s.ausstehendeFortsetzungen == 0, "die Fortsetzung lief und sah die andere Frage")
        #expect(weiter == 0, "die andere Frage bleibt, das Beenden wartet auf ein neues ⌘Q")
        #expect(s.rueckfrage?.text == "Eine andere Frage des Blatts")
    }

    @Test("Beenden bei stehender Rückfrage wartet auf ihre Antwort — die App nimmt sie nicht weg und legt keine zweite darüber (B82, E315)")
    func beendenWartetAufStehendeFrage() async throws {
        let ablage = try ordner("stehend")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try await speicher(ablage)
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
        s.offenerDialog = .lernende
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Eine Frage des Blatts", bestaetigung: "Ja", ort: .lernende) {}
        let stand = try #require(s.rueckfrage).id
        s.beenden()
        #expect(s.rueckfrage?.id == stand && s.offenerDialog == .lernende && !s.beendetGleich,
                "⌘Q: Die stehende Frage bleibt, das Blatt auch")
        #expect(!s.beendenErlauben() && s.rueckfrage?.id == stand, "auch der Weg über applicationShouldTerminate wartet")
        let vorhaben = try #require(s.planung?.eintraege.first { $0.termin == t }).id
        s.zeigeVorhaben(vorhaben)
        #expect(s.rueckfrage?.id == stand && s.offenerDialog == .lernende, "der Sprung zu einem Vorhaben schließt nichts")
        // Beantwortet, geht das nächste ⌘Q weiter — hier zur Frage nach den Änderungen (Z14c3-11).
        s.rueckfrageBeantworten(false)
        s.beenden()
        #expect(s.rueckfrage?.text.hasPrefix("Die Änderungen an den Lernenden übernehmen?") == true,
                Comment(rawValue: s.rueckfrage?.text ?? "—"))
    }

    @Test("Eine gesetzte, aber nicht angezeigte Rückfrage sperrt weder Beenden noch Sprung (Z14c3-01, Z14c3-02)")
    func unsichtbareFrageSperrtNicht() async throws {
        let ablage = try ordner("unsichtbar")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try await speicher(ablage)
        s.rueckfrageSichtbar = { false }
        let vorhaben = try #require(s.planung?.eintraege.first { $0.termin == t }).id
        // Gesetzt an der Hauptfläche, dann geht ein Blatt darüber auf: Die Frage steht, nicht zu sehen —
        // fragte sie erst hinter dem Blatt, entfiele sie gleich (E418), und hier wäre nichts geprüft (Z-AU5-05).
        s.fragen("Hinter dem Blatt", bestaetigung: "Ersetzen") {}
        s.offenerDialog = .klassen
        try #require(s.rueckfrage != nil, "die Frage ist gesetzt")
        s.zeigeVorhaben(vorhaben)
        #expect(s.rueckfrage == nil && s.offenerDialog == nil, "der Sprung räumt die unsichtbare Frage mit ab")
        s.fragen("Hinter dem Blatt", bestaetigung: "Ersetzen") {}
        try #require(s.rueckfrage != nil, "wieder gesetzt, nicht angezeigt")
        #expect(s.beendenErlauben(), "applicationShouldTerminate wartet nicht auf eine unsichtbare Frage")
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
        s.offenerDialog = .lernende
        s.beenden()
        #expect(s.rueckfrage?.text.hasPrefix("Die Änderungen an den Lernenden übernehmen?") == true,
                "⌘Q geht weiter — die Frage nach den Änderungen tritt an die Stelle der unsichtbaren")
    }

    @Test("Über eine sichtbare Rückfrage legt sich keine zweite — sie wartet und erscheint nach der Antwort (E317)")
    func zweiteFrageWartet() async throws {
        let ablage = try ordner("wartet")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") {}
        let erste = try #require(s.rueckfrage).id
        var zweite = 0
        s.fragen("Zweite", bestaetigung: "Ja") { zweite += 1 }
        #expect(s.rueckfrage?.id == erste && s.wartendeRueckfragen.count == 1, "die sichtbare bleibt, die zweite wartet")
        s.rueckfrageBeantworten(false)
        #expect(s.rueckfrage == nil, "noch nicht — erst nach der Nachholfrist")
        let erschienen = await uhr.vorruecken(bis: { s.rueckfrage?.text == "Zweite" }, hoechstens: .seconds(1))
        try #require(erschienen, "die zweite erscheint nach der Antwort")
        s.rueckfrageBeantworten(true)
        #expect(zweite == 1 && s.wartendeRueckfragen.isEmpty)
    }

    @Test("Eine nicht angezeigte Rückfrage wird ersetzt, nicht eingereiht (E317, Z14c3-01)")
    func unsichtbareWirdErsetzt() async throws {
        let ablage = try ordner("ersetzt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        s.rueckfrageSichtbar = { false }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Zweite", bestaetigung: "Ja") {}
        #expect(s.rueckfrage?.text == "Zweite" && s.wartendeRueckfragen.isEmpty)
    }

    @Test("Schließen räumt auch die wartenden Fragen ab — nach dem Beenden oder einem Sprung erscheint keine mehr (E317)")
    func schliessenLeertWarteschlange() async throws {
        let ablage = try ordner("leert")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Zweite", bestaetigung: "Ja") {}
        s.alleDialogeSchliessen()
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.isEmpty)
        await uhr.vorruecken(um: .seconds(2))  // über die Frist des Nachholens hinaus
        #expect(s.rueckfrage == nil, "keine wartende Frage kommt nach")
    }

    @Test("Bei sichtbarer Rückfrage tun ⌘Z und ⌘P/⇧⌘P im Sitzplan nichts (E317, E318)")
    func befehleGesperrt() async throws {
        let ablage = try ordner("befehle")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try await speicher(ablage)
        let v = try #require(s.planung?.eintraege.first { $0.termin == t })
        s.vorhabenVerschieben(v.id, klasse: v.klasseId, woche: v.woche + 1)
        let verschoben = try #require(s.planung)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Steht", bestaetigung: "Ja") {}
        let stand = try #require(s.rueckfrage).id
        let meldungen = s.meldungen.count
        s.widerrufen()
        #expect(s.planung == verschoben, "⌘Z nimmt nichts zurück")
        // Im offenen Sitzplan — sonst täten die Befehle ohnehin nichts (der Verlauf des Blatts erst danach).
        s.offenerDialog = .sitzplan
        s.sitzplanAlsPDFSichern()
        s.sitzplanDrucken()
        #expect(s.rueckfrage?.id == stand && s.meldungen.count == meldungen, "⌘P und ⇧⌘P im Sitzplan tun nichts")
        s.offenerDialog = nil
        s.wiederholen()
        #expect(s.planung == verschoben, "⇧⌘Z ebenso")
        s.rueckfrageBeantworten(false)
        s.widerrufen()
        #expect(s.planung != verschoben, "nach der Antwort nimmt ⌘Z zurück")
    }

    @Test("Eine Folgefrage geht einer wartenden vor — die Fortsetzung des Beendens geht nicht verloren (Z14c4-01)")
    func folgefrageVorWartender() async throws {
        let ablage = try ordner("folgefrage")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        var namen = true
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(namenOffen: { namen }, namenVerwerfen: { namen = false }))
        // Beide Fragen hängen am Blatt, das offen bleibt (E418).
        s.offenerDialog = .lernende
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt)
        s.fragen("Wartet", bestaetigung: "Ja", ort: .lernende) {}
        #expect(s.wartendeRueckfragen.count == 1)
        s.rueckfrageBeantworten(true)
        let gelaufen = await uhr.vorruecken(bis: { weiter == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "das Beenden geht weiter")
        let erschienen = await uhr.vorruecken(bis: { s.rueckfrage?.text == "Wartet" }, hoechstens: .seconds(1))
        try #require(erschienen, "danach erscheint die wartende")
    }

    @Test("Eine Frage aus der Handlung heraus wartet, bis das Alert-Blatt fort ist (Z14c4-02)")
    func folgeImHandlerWartet() async throws {
        let ablage = try ordner("handler")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        // Ein Alert hängt, solange eine Frage gesetzt ist — und während er nach der Antwort ausblendet.
        let blendetAus = Merker()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || blendetAus.an }
        s.fragen("Erste", bestaetigung: "Ja") { [weak s] in s?.fragen("Folge", bestaetigung: "Ja") {} }
        #expect(s.rueckfrage?.text == "Erste")
        blendetAus.an = true
        s.rueckfrageBeantworten(true)
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.count == 1, "das Alert hängt noch — die Folge wartet")
        blendetAus.an = false
        let erschienen = await uhr.vorruecken(bis: { s.rueckfrage?.text == "Folge" }, hoechstens: .seconds(1))
        try #require(erschienen, "danach erscheint sie")
    }

    @Test("Zwei wartende Fragen erscheinen nacheinander (E317)")
    func zweiWartende() async throws {
        let ablage = try ordner("zwei")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Zweite", bestaetigung: "Ja") {}
        s.fragen("Dritte", bestaetigung: "Ja") {}
        #expect(s.rueckfrage?.text == "Erste" && s.wartendeRueckfragen.map(\.text) == ["Zweite", "Dritte"])
        s.rueckfrageBeantworten(false)
        let zweite = await uhr.vorruecken(bis: { s.rueckfrage?.text == "Zweite" }, hoechstens: .seconds(1))
        try #require(zweite, "die zweite")
        s.rueckfrageBeantworten(false)
        let dritte = await uhr.vorruecken(bis: { s.rueckfrage?.text == "Dritte" }, hoechstens: .seconds(1))
        try #require(dritte, "die dritte")
    }

    /// Eine Planung anderer Herkunft als Datei — `importieren(von:)` wiese sie ohne Sperre als Wechsel aus.
    private func fremdeDatei(_ s: Planungsspeicher, in quelle: URL) throws -> URL {
        var fremd = try #require(s.planung)
        fremd.titel = "Fremd"
        fremd.erstellt = "2027-07-01T10:00:00.000Z"
        let datei = quelle.appending(component: "fremd.json")
        try Planungsdatei.schreiben(fremd).write(to: datei)
        return datei
    }

    @Test("Eine Planung per Finder öffnen, während eine Rückfrage sichtbar steht: abgewiesen, gesagt erst nach der Antwort — einmal (Z14c4-03, Z14c4-14, E334)")
    func oeffnenWartetAufFrage() async throws {
        let ablage = try ordner("oeffnen")
        let quelle = try ordner("oeffnen-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(s, in: quelle)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Steht", bestaetigung: "Ja") {}
        let stand = try #require(s.rueckfrage).id
        let vorher = try #require(s.planung).erstellt
        let meldungen = s.meldungen.count
        let gesperrt = s.gesperrteBefehle
        // Zweimal, wie ein ungeduldiger Doppelklick im Finder.
        s.importieren(von: datei)
        s.importieren(von: datei)
        #expect(s.rueckfrage?.id == stand && s.wartendeRueckfragen.isEmpty && s.schuljahrwechsel == nil
                && s.offenerDialog == nil && s.planung?.erstellt == vorher && s.gesperrteBefehle == gesperrt + 2,
                "abgewiesen, mit dem Systemton sofort (E318)")
        #expect(s.meldungen.count == meldungen, "unter der Frage noch kein Text — er verfiele dort ungelesen (Z14c4-14)")
        let dahinter = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.contains("wurde nicht geöffnet") } },
                                             hoechstens: .seconds(1))
        #expect(!dahinter, "auch über die Zeit nicht, solange die Frage steht")
        let text = "„fremd.json“ wurde nicht geöffnet, weil eine Rückfrage stand. Bitte die Datei erneut öffnen."
        s.rueckfrageBeantworten(false)
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen, "nach der Antwort erscheint der Text")
        #expect(s.meldungen.filter { $0.text == text }.count == 1, "zweimal geöffnet, einmal gesagt")
        // Gezählt wird, was gesagt wurde — eine Meldung kann verfallen, ehe die zweite kommt (Z-AT6g3a-06).
        var gesagt = Set<UUID>()
        let doppelt = await uhr.vorruecken(bis: {
            gesagt.formUnion(s.meldungen.filter { $0.text == text }.map(\.id))
            return gesagt.count > 1
        }, hoechstens: .seconds(1))
        #expect(!doppelt, "auch danach kein zweites Mal")
    }

    @Test("Abgewiesen unter dem eigenen Alert eines Blatts: Der Text erscheint erst, wenn weder Frage noch Blatt offen ist (Z14c4-14, E334)")
    func meldungHinterBlattKommtNach() async throws {
        let ablage = try ordner("hinter-blatt")
        let quelle = try ordner("hinter-blatt-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(s, in: quelle)
        let alert = Merker()
        alert.an = true
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || alert.an }
        s.offenerDialog = .klassen
        let meldungen = s.meldungen.count
        s.importieren(von: datei)
        #expect(s.meldungen.count == meldungen, "unter dem Alert des Blatts noch kein Text")
        // Das Alert geht; am Blatt wird noch eine Frage gestellt und beantwortet — das Blatt steht weiter.
        alert.an = false
        s.fragen("Am Blatt", bestaetigung: "Ja", ort: .klassen) {}
        s.rueckfrageBeantworten(false)
        let text = "„fremd.json“ wurde nicht geöffnet, weil eine Rückfrage stand. Bitte die Datei erneut öffnen."
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text == text } }, hoechstens: .seconds(1))
        #expect(!erschienen, "auch nicht kurz erschienen")
        // Nach dem Text gefragt, nicht nach der Zahl: Eine andere Meldung kann im Fenster verfallen (Z-AS2-07).
        #expect(!s.meldungen.contains { $0.text == text }, "solange das Blatt offen ist, noch nicht — der Text läge hinter ihm")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Schließen des Blatts erscheint der Text")
    }

    @Test("Ein Wechsel der Blätter und das Vorhaben-Blatt halten den Text zurück, bis nichts mehr offen ist (Z14c4-14, Z-AS2-06)")
    func meldungWartetAufBlattwechsel() async throws {
        let ablage = try ordner("blattwechsel")
        let quelle = try ordner("blattwechsel-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(s, in: quelle)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        let text = "„Fremd“ ist eine andere Planung desselben Schuljahrs und wurde nicht geöffnet, weil ein Blatt offen war. "
            + "Bitte die Datei erneut öffnen."
        s.offenerDialog = .klassen
        let toene = s.systemtoene
        s.importieren(von: datei)
        #expect(s.systemtoene == toene + 1, "der Ton kommt sofort (E399)")
        // Das eine Blatt geht, das nächste kommt erst (`naechsterDialog`).
        s.dialogOeffnen(.einstellungen)
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text == text } }, hoechstens: .seconds(1))
        #expect(!erschienen, "auch nicht kurz erschienen")
        #expect(s.offenerDialog == nil && s.naechsterDialog == .einstellungen && !s.meldungen.contains { $0.text == text },
                "im Wechsel der Blätter noch nicht")
        s.naechstenDialogOeffnen()
        let erschienen2 = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text == text } }, hoechstens: .seconds(1))
        #expect(!erschienen2, "auch nicht kurz erschienen")
        #expect(!s.meldungen.contains { $0.text == text }, "hinter dem nächsten Blatt noch nicht")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem letzten Blatt erscheint der Text")
        // Ebenso hinter dem Vorhaben-Blatt — die erste Meldung weggeklickt, damit nur die neue zählt.
        for meldung in s.meldungen where meldung.text == text { s.meldungSchliessen(meldung.id) }
        s.vorhabenDialog = VorhabenEntwurf(klasseId: "k-kl", woche: 1)
        s.importieren(von: datei)
        let erschienen3 = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text == text } }, hoechstens: .seconds(1))
        #expect(!erschienen3, "auch nicht kurz erschienen")
        #expect(!s.meldungen.contains { $0.text == text }, "hinter dem Vorhaben-Blatt noch nicht")
        s.vorhabenDialog = nil
        let gesehen2 = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen2, "nach dem Vorhaben-Blatt erscheint der Text")
    }

    @Test("Folgt der Antwort eine wartende Frage, kommt der Text erst nach ihr — sonst läge er unter ihr (Z-AS2-02)")
    func meldungWartetAufWartendeFrage() async throws {
        let ablage = try ordner("wartende-frage")
        let quelle = try ordner("wartende-frage-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(s, in: quelle)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Zweite", bestaetigung: "Ja") {}
        s.importieren(von: datei)
        let text = "„fremd.json“ wurde nicht geöffnet, weil eine Rückfrage stand. Bitte die Datei erneut öffnen."
        s.rueckfrageBeantworten(false)
        let zweite = await uhr.vorruecken(bis: { s.rueckfrage?.text == "Zweite" }, hoechstens: .seconds(1))
        try #require(zweite, "die zweite Frage erscheint")
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text == text } }, hoechstens: .seconds(1))
        #expect(!erschienen, "auch nicht kurz erschienen")
        #expect(!s.meldungen.contains { $0.text == text }, "zwischen den Fragen noch nicht")
        s.rueckfrageBeantworten(false)
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen, "nach der letzten Antwort der Text")
    }

    @Test("Steht nach der Antwort eine Fortsetzung aus, kommt der Text erst nach ihrer Frage (Z-AS2-02, E319)")
    func meldungWartetAufFortsetzung() async throws {
        let ablage = try ordner("fortsetzung")
        let quelle = try ordner("fortsetzung-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(s, in: quelle)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") { [weak s] in s?.nachDerAntwort { s?.fragen("Folge", bestaetigung: "Ja") {} } }
        s.importieren(von: datei)
        let text = "„fremd.json“ wurde nicht geöffnet, weil eine Rückfrage stand. Bitte die Datei erneut öffnen."
        s.rueckfrageBeantworten(true)
        let gesehen = await uhr.vorruecken(bis: { s.rueckfrage?.text == "Folge" }, hoechstens: .seconds(1))
        try #require(gesehen, "die Folgefrage erscheint")
        await uhr.vorruecken(um: .zero)  // was zur selben Frist ansteht
        #expect(!s.meldungen.contains { $0.text == text }, "vor der Folgefrage noch nicht")
        s.rueckfrageBeantworten(false)
        let gesehen2 = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen2, "nach ihrer Antwort der Text")
        // Eine Fortsetzung ohne Frage: Danach stößt sie selbst an — keine Frage täte es.
        for meldung in s.meldungen where meldung.text == text { s.meldungSchliessen(meldung.id) }
        s.fragen("Dritte", bestaetigung: "Ja") { [weak s] in s?.nachDerAntwort {} }
        s.importieren(von: datei)
        s.rueckfrageBeantworten(true)
        await uhr.vorruecken(um: .zero)  // vor der Fortsetzung
        #expect(s.ausstehendeFortsetzungen == 1 && !s.meldungen.contains { $0.text == text },
                "solange die Fortsetzung aussteht, noch nicht")
        let gesehen3 = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen3, "nach der Fortsetzung der Text")
    }

    @Test("Dieselbe Datei zweimal geöffnet, während ihre Frage „… wird ersetzt“ steht: das zweite Mal still abgewiesen — ob ersetzt oder abgelehnt, kein „nicht geöffnet“ hinterher (Z-AS2-01, Z-AS2-10)")
    func doppeltGeoeffnetUndUebernommen() async throws {
        let ablage = try ordner("doppelt")
        let quelle = try ordner("doppelt-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        // Dieselbe Herkunft: kein Wechsel, sondern „… wird ersetzt“ — die Planung hat Vorhaben.
        var ersatz = try #require(s.planung)
        ersatz.titel = "Ersatz"
        let datei = quelle.appending(component: "ersatz.json")
        try Planungsdatei.schreiben(ersatz).write(to: datei)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.importieren(von: datei)
        #expect(s.rueckfrage?.text.hasPrefix("Die geöffnete Planung") == true, Comment(rawValue: s.rueckfrage?.text ?? "—"))
        let gesperrt = s.gesperrteBefehle
        s.importieren(von: datei)
        #expect(s.gesperrteBefehle == gesperrt + 1, "das zweite Öffnen prallt an der Frage ab, mit Ton (Z-AS2-15)")
        s.rueckfrageBeantworten(true)
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text.hasPrefix("Planung „Ersatz“ geladen.") == true }, hoechstens: .seconds(1))
        try #require(gesehen, "ersetzt und gemeldet")
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.contains("wurde nicht geöffnet") } }, hoechstens: .seconds(1))
        #expect(!erschienen, "auch nicht kurz erschienen")
        #expect(s.planung?.titel == "Ersatz" && !s.meldungen.contains { $0.text.contains("wurde nicht geöffnet") },
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
        // Abgelehnt: ebenso still — die Entscheidung über diese Datei stand ja an (Z-AS2-10).
        var abgelehnt = try #require(s.planung)
        abgelehnt.titel = "Abgelehnt"
        let zweite = quelle.appending(component: "abgelehnt.json")
        try Planungsdatei.schreiben(abgelehnt).write(to: zweite)
        s.importieren(von: zweite)
        #expect(s.rueckfrage?.text.hasPrefix("Die geöffnete Planung") == true, Comment(rawValue: s.rueckfrage?.text ?? "—"))
        s.importieren(von: zweite)
        s.rueckfrageBeantworten(false)
        let erschienen2 = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.hasPrefix("„abgelehnt.json“") } }, hoechstens: .seconds(1))
        #expect(!erschienen2, "auch nicht kurz erschienen")
        #expect(s.planung?.titel == "Ersatz" && !s.meldungen.contains { $0.text.hasPrefix("„abgelehnt.json“") },
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
    }

    @Test("Dieselbe fremde Planung zweimal geöffnet, während ihr Blatt „Neues Schuljahr öffnen“ steht: still abgewiesen — abgebrochen oder geöffnet, kein „nicht geöffnet“ hinterher (Z-AS2-10, Z-AS2-13)")
    func wechselDoppeltGeoeffnet() async throws {
        let ablage = try ordner("wechsel-doppelt")
        let quelle = try ordner("wechsel-doppelt-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(s, in: quelle)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.importieren(von: datei)
        #expect(s.schuljahrwechsel != nil && s.offenerDialog == .schuljahrOeffnen)
        let toene = s.systemtoene
        s.importieren(von: datei)
        #expect(s.systemtoene == toene + 1, "still, aber mit Ton (E399, wie Z-AS3-01)")
        s.schuljahrOeffnenAbbrechen()
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.contains("wurde nicht geöffnet") } }, hoechstens: .seconds(1))
        #expect(!erschienen, "auch nicht kurz erschienen")
        #expect(!s.meldungen.contains { $0.text.contains("wurde nicht geöffnet") },
                Comment(rawValue: "abgebrochen: nichts hinterher — " + s.meldungen.map(\.text).joined(separator: " | ")))
        for meldung in s.meldungen { s.meldungSchliessen(meldung.id) }
        s.importieren(von: datei)
        s.importieren(von: datei)
        s.schuljahrOeffnen(gruppen: [])
        // Gleichlaufend: Der Wechsel ist mit dem Knopf durch — sonst sagt die Meldung, warum nicht.
        #expect(s.planung?.titel == "Fremd", Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
        let erschienen2 = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.contains("wurde nicht geöffnet") } }, hoechstens: .seconds(1))
        #expect(!erschienen2, "auch nicht kurz erschienen")
        #expect(!s.meldungen.contains { $0.text.contains("wurde nicht geöffnet") },
                Comment(rawValue: "geöffnet: nichts hinterher — " + s.meldungen.map(\.text).joined(separator: " | ")))
    }

    @Test("Geht das Blatt „Neues Schuljahr öffnen“ auf anderem Weg, weist ein späteres Öffnen derselben Datei nicht mehr still ab (Z-AS2-16)")
    func wechselBlattAbgeloest() async throws {
        let ablage = try ordner("wechsel-abgeloest")
        let quelle = try ordner("wechsel-abgeloest-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(s, in: quelle)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.importieren(von: datei)
        #expect(s.offenerDialog == .schuljahrOeffnen)
        // Wie ein Sprung zu einem Vorhaben: alles zu, ohne „Abbrechen“ — `schuljahrwechsel` bleibt stehen.
        s.alleDialogeSchliessen()
        s.offenerDialog = .klassen
        s.importieren(von: datei)
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.last?.text == "„Fremd“ ist eine andere Planung desselben Schuljahrs und wurde nicht geöffnet, "
                + "weil ein Blatt offen war. Bitte die Datei erneut öffnen."
        }, hoechstens: .seconds(1))
        try #require(gesehen, "gesagt, wenn das Blatt zu ist")
    }

    @Test("Zwei Dateien gleichen Namens aus zwei Ordnern, beide abgewiesen: Die Vormerkung trägt ihre Datei — verfällt die der einen, bleibt die andere gesagt (Z-AS2-11)")
    func gleichnamigeDateien() async throws {
        let ablage = try ordner("gleichnamig")
        let quelleA = try ordner("gleichnamig-a")
        let quelleB = try ordner("gleichnamig-b")
        defer { for o in [ablage, quelleA, quelleB] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let a = try fremdeDatei(s, in: quelleA)
        let b = try fremdeDatei(s, in: quelleB)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Steht", bestaetigung: "Ja") {}
        s.importieren(von: a)
        s.importieren(von: b)
        s.vorgemerkteMeldungenVerwerfen(datei: a)
        s.rueckfrageBeantworten(false)
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.last?.text == "„fremd.json“ wurde nicht geöffnet, weil eine Rückfrage stand. Bitte die Datei erneut öffnen."
        }, hoechstens: .seconds(1))
        try #require(gesehen, "die zweite bleibt gesagt")
        // Gezählt wird, was gesagt wurde — eine Meldung kann verfallen, ehe die zweite kommt (Z-AT6g3a-06).
        var gesagt = Set<UUID>()
        let doppelt = await uhr.vorruecken(bis: {
            gesagt.formUnion(s.meldungen.filter { $0.text.hasPrefix("„fremd.json“") }.map(\.id))
            return gesagt.count > 1
        }, hoechstens: .seconds(1))
        #expect(!doppelt, "die der einen bleibt verworfen — einmal gesagt")
    }

    @Test("Der Schlüssel der Vormerkung: Dieselbe Datei über einen Symlink ist dieselbe Datei (Z-AS2-12)")
    func schluesselUeberSymlink() async throws {
        let ablage = try ordner("symlink")
        let quelle = try ordner("symlink-quelle")
        let verweis = try ordner("symlink-verweis")
        defer { for o in [ablage, quelle, verweis] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(s, in: quelle)
        let link = verweis.appending(component: "quelle")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: quelle)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Steht", bestaetigung: "Ja") {}
        s.importieren(von: datei)
        s.vorgemerkteMeldungenVerwerfen(datei: link.appending(component: "fremd.json"))
        s.rueckfrageBeantworten(false)
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.hasPrefix("„fremd.json“ wurde nicht geöffnet") } }, hoechstens: .seconds(1))
        #expect(!erschienen, "auch nicht kurz erschienen")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("„fremd.json“ wurde nicht geöffnet") },
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
    }

    @Test("Auch der eigene Alert eines Dialogs sperrt: Beenden wartet, ⌘Z und der Sprung tun nichts darunter (Z14c4-10)")
    func eigenerAlertSperrt() async throws {
        let ablage = try ordner("eigener")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try await speicher(ablage)
        let v = try #require(s.planung?.eintraege.first { $0.termin == t })
        s.vorhabenVerschieben(v.id, klasse: v.klasseId, woche: v.woche + 1)
        let verschoben = try #require(s.planung)
        let alert = Merker()
        alert.an = true
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || alert.an }
        #expect(!s.beendenErlauben(), "applicationShouldTerminate wartet")
        s.widerrufen()
        #expect(s.planung == verschoben, "⌘Z ändert nichts darunter")
        // Ein Blatt erst jetzt — bei offenem Blatt gehört ⌘Z dem Blatt, nicht der Planung.
        s.offenerDialog = .klassen
        s.zeigeVorhaben(v.id)
        #expect(s.offenerDialog == .klassen, "der Sprung schließt das Blatt unter dem Alert nicht")
    }

    @Test("Auch wenn das Alert-Blatt noch ausblendet, geht die Folgefrage einer wartenden vor (Z14c4-12)")
    func folgefrageVorWartenderBeimAusblenden() async throws {
        let ablage = try ordner("ausblenden")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let blendetAus = Merker()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || blendetAus.an }
        var namen = true
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(namenOffen: { namen }, namenVerwerfen: { namen = false }))
        // Alle Fragen hängen am Blatt, das offen bleibt (E418).
        s.offenerDialog = .lernende
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { [weak s] in s?.fragen("Folge", bestaetigung: "Ja", ort: .lernende) {} })
        #expect(gefragt)
        s.fragen("Wartet", bestaetigung: "Ja", ort: .lernende) {}
        blendetAus.an = true
        s.rueckfrageBeantworten(true)
        // Solange das Blatt ausblendet, wartet die Fortsetzung — und die Wartende hinter ihr (E319).
        await uhr.vorruecken(um: .seconds(1))  // über die Frist des Nachholens hinaus
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.map(\.text) == ["Wartet"] && s.ausstehendeFortsetzungen == 1,
                "noch nichts: Das Alert hängt, die Fortsetzung steht aus")
        blendetAus.an = false
        await uhr.vorruecken(um: .seconds(2))
        #expect(s.rueckfrage != nil, "eine Frage erscheint")
        #expect(s.rueckfrage?.text == "Folge", Comment(rawValue: s.rueckfrage?.text ?? "—"))
    }

    @Test("Solange eine Fortsetzung aussteht, holt die Warteschlange nichts nach — auch wenn das Alert schon fort ist (E319)")
    func wartendeWartetAufFortsetzung() async throws {
        let ablage = try ordner("zaehler")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let blendetAus = Merker()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || blendetAus.an }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Wartet", bestaetigung: "Ja") {}
        #expect(s.rueckfrage?.text == "Erste" && s.wartendeRueckfragen.map(\.text) == ["Wartet"])
        // Abgelehnt, das Alert blendet aus; das Nachholen schaut nach `nachholfrist` (0,7 s) wieder.
        blendetAus.an = true
        s.rueckfrageBeantworten(false)
        // Bei 0,5 s ist das Alert fort, und eine Fortsetzung steht aus — sie kommt erst nach dem Nachhol-Takt
        // bei 0,7 s (Z14d2-02); die Stelluhr hält die Reihenfolge (Z14d2-10).
        await uhr.vorruecken(um: .milliseconds(500))
        blendetAus.an = false
        s.nachDerAntwort { [weak s] in s?.fragen("Folge", bestaetigung: "Ja") {} }
        await uhr.vorruecken(um: .seconds(2))
        #expect(s.rueckfrage != nil, "eine Frage erscheint")
        #expect(s.rueckfrage?.text == "Folge" && s.wartendeRueckfragen.map(\.text) == ["Wartet"],
                Comment(rawValue: "\(s.rueckfrage?.text ?? "—"), wartend \(s.wartendeRueckfragen.map(\.text))"))
    }

    @Test("Der Grund für ein Beenden per AppleScript folgt der Frage, die steht (Z14b-03, E316)")
    func beendengrund() {
        let lernende = Rueckfrage(text: "L", bestaetigung: "Ja", ort: .lernende, handlung: {})
        let bogen = Rueckfrage(text: "B", bestaetigung: "Ja", ort: .bogen, handlung: {})
        let sicherung = Rueckfrage(text: "S", bestaetigung: "Ja", handlung: {})
        let blatt = "Das Blatt „Lernende“ hat ungesicherte Änderungen; das Beenden wartet auf eine Antwort."
        #expect(Planungsspeicher.beendengrund(frage: lernende, wartete: false) == blatt)
        #expect(Planungsspeicher.beendengrund(frage: bogen, wartete: false) == blatt, "der offene Bogen gehört zum Blatt")
        #expect(Planungsspeicher.beendengrund(frage: sicherung, wartete: false)
                == "Die Planung ließ sich nicht sichern; das Beenden wartet auf eine Antwort.")
        #expect(Planungsspeicher.beendengrund(frage: lernende, wartete: true)
                == "Eine Rückfrage steht; das Beenden wartet auf eine Antwort.", "die Frage stand schon vor dem Beenden")
        #expect(Planungsspeicher.beendengrund(frage: nil, wartete: true)
                == "Eine Rückfrage steht; das Beenden wartet auf eine Antwort.", "der eigene Alert eines Dialogs (Z14c4-10)")
        #expect(Planungsspeicher.beendengrund(frage: nil, wartete: false)
                == "Die Planung ließ sich nicht sichern; das Beenden wartet auf eine Antwort.")
        // Die Verlustfrage trägt ihren Grund (E327) — er folgt den Teilen ihres Texts (E328, Z14c3-07).
        let mitGrund = Rueckfrage(text: "S", bestaetigung: "Trotzdem beenden", skriptgrund: "X", handlung: {})
        #expect(Planungsspeicher.beendengrund(frage: mitGrund, wartete: false) == "X")
        #expect(Planungsspeicher.beendengrund(frage: mitGrund, wartete: true)
                == "Eine Rückfrage steht; das Beenden wartet auf eine Antwort.", "stand sie schon vor dem Beenden, gilt das")
        // An einem Blatt abgelehnt (E427, E428) — nur ohne Frage; Warten und der Grund der Verlustfrage gehen vor.
        #expect(Planungsspeicher.beendengrund(frage: nil, wartete: false, blatt: true)
                == "Ein Blatt ließ sich nicht schließen; das Beenden wurde abgelehnt.")
        #expect(Planungsspeicher.beendengrund(frage: nil, wartete: true, blatt: true)
                == "Eine Rückfrage steht; das Beenden wartet auf eine Antwort.")
        #expect(Planungsspeicher.beendengrund(frage: mitGrund, wartete: false, blatt: true) == "X")
        #expect(Planungsspeicher.beendengrund(frage: sicherung, wartete: false, blatt: true)
                == "Die Planung ließ sich nicht sichern; das Beenden wartet auf eine Antwort.", "eine Frage ohne Grund: wie ohne Blatt")
        let warten = " sich nicht sichern; das Beenden wartet auf eine Antwort."
        let faelle: [(Bool, Bool, Bool, String)] = [
            (true, false, false, "Die Planung ließ"), (false, true, false, "Die Sitzpläne ließen"),
            (false, false, true, "Die Lernendendaten ließen"), (true, true, false, "Die Planung und die Sitzpläne ließen"),
            (true, false, true, "Die Planung und die Lernendendaten ließen"),
            (false, true, true, "Die Sitzpläne und die Lernendendaten ließen"),
            (true, true, true, "Die Planung, die Sitzpläne und die Lernendendaten ließen"),
        ]
        for (planung, sitzplaene, lernende, erwartet) in faelle {
            let grund = Planungsspeicher.verlustgrund(planung: planung, sitzplaene: sitzplaene, lernende: lernende)
            #expect(grund == erwartet + warten, Comment(rawValue: grund))
        }
        // Angehalten an einer Löschung im Archiv (E396, Z-AS2a-11).
        #expect(Planungsspeicher.beendengrund(frage: nil, wartete: false, archiv: true)
                == "Eine Löschung im Archiv ließ sich nicht schreiben; das Beenden wurde angehalten — ein erneutes Beenden beendet.")
    }

    @Test("„Neue Planung“ ohne Verschlüsselung (E302): Die Rückfrage sagt, dass das Anlegen danach neu beginnt")
    func neuePlanungOhneVerschluesselung() throws {
        let ablage = try ordner("neue-planung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.offenerDialog = .neuePlanung  // Aus dem Blatt, an dem die Frage hängt (E418).
        s.neuePlanungFragen(ort: .neuePlanung) {}
        let frage = try #require(s.rueckfrage)
        #expect(frage.text == "Die bisherige Planung „Schuljahr 2026/27“ wird nur mit eingeschalteter Verschlüsselung "
                + "archiviert — ohne sie ersetzt die neue Planung die bisherige, wie bisher. Mit dem Einrichten der "
                + "Verschlüsselung beginnt das Anlegen einer neuen Planung ohne Übernahme der bisherigen Eingaben.\n\n"
                + "Zuerst die Verschlüsselung einrichten oder ohne Archiv fortfahren?", Comment(rawValue: frage.text))
        s.rueckfrageBeantworten(false)
    }

    @Test("Person endgültig löschen (W2-05): Die Rückfrage nennt die Vorhaben, die mit ihren Terminen gehen")
    func personLoeschenNenntVorhaben() async throws {
        let ablage = try ordner("person")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, anna) = try await speicher(ablage)
        s.offenerDialog = .lernende  // Die Frage hängt am Blatt (E418).
        s.personLoeschenFragen(anna, in: try #require(s.lernende.bestand)) { _ in }
        let frage = try #require(s.rueckfrage)
        #expect(frage.text.contains("\n\nBeim „Übernehmen“ geht auch 1 Vorhaben in der Planung."), Comment(rawValue: frage.text))
        s.rueckfrageBeantworten(false)
        let ben = try #require(s.lernende.bestand?.lernende.first { $0.id != anna }).id
        s.personLoeschenFragen(ben, in: try #require(s.lernende.bestand)) { _ in }
        #expect(s.rueckfrage?.text.contains("Vorhaben in der Planung") == false, "ohne Termin kein Satz")
        s.rueckfrageBeantworten(false)
    }

    @Test("Aufheben (E301): Die Rückfrage nennt Rettungskopien, die keine überholten Stände sind, eigens")
    func aufhebenNenntArten() async throws {
        let ablage = try ordner("aufheben")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        for name in ["lernende-bereinigt-x.json", "lernende-fremd-y.json", "archiv-beschaedigt-z.json"] {
            try Data("{}".utf8).write(to: ablage.appending(component: name))
        }
        let text = s.aufhebenRueckfrage
        #expect(text.contains("3 Rettungskopien der Lernendendaten werden dabei endgültig gelöscht — Lernendendaten werden nie "
                              + "entsiegelt. Davon sind 2 keine überholten Stände, sondern Kopien, die sich nicht öffnen ließen "
                              + "(unter einem anderen Schlüssel, beschädigt oder im Klartext abgelegt); sie können die einzige "
                              + "Fassung dieser Daten sein."), Comment(rawValue: text))
    }

    @Test("Aufheben (E301, Z14b-07): eine Kopie im Klartext allein, „Davon ist 1 …“, nur überholte — je ihr Satz")
    func aufhebenEinzahl() async throws {
        let ablage = try ordner("aufheben-einzahl")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let art = "(unter einem anderen Schlüssel, beschädigt oder im Klartext abgelegt)"
        let klartext = ablage.appending(component: "lernende-unerwartet-a.json")
        try Data("{}".utf8).write(to: klartext)
        #expect(s.aufhebenRueckfrage.contains("Eine Rettungskopie der Lernendendaten wird dabei endgültig gelöscht — "
                                              + "Lernendendaten werden nie entsiegelt. Diese Kopie ist kein überholter Stand, "
                                              + "sondern ließ sich nicht öffnen \(art); sie kann die einzige Fassung "
                                              + "dieser Daten sein."), Comment(rawValue: s.aufhebenRueckfrage))
        try Data("{}".utf8).write(to: ablage.appending(component: "archiv-bereinigt-b.json"))
        #expect(s.aufhebenRueckfrage.contains("2 Rettungskopien der Lernendendaten werden dabei endgültig gelöscht — "
                                              + "Lernendendaten werden nie entsiegelt. Davon ist 1 kein überholter Stand, "
                                              + "sondern eine Kopie, die sich nicht öffnen ließ \(art); sie kann die einzige "
                                              + "Fassung dieser Daten sein."), Comment(rawValue: s.aufhebenRueckfrage))
        try FileManager.default.removeItem(at: klartext)
        #expect(s.aufhebenRueckfrage.contains("Eine Rettungskopie der Lernendendaten wird dabei endgültig gelöscht — "
                                              + "Lernendendaten werden nie entsiegelt.\n\nFortfahren?"), "nur überholt: kein Zusatz")
    }

    /// Ein Archiv mit einem Schuljahr und den drei Personen des Prüfentwurfs — geschrieben unter dem Schlüssel.
    private func archivAnlegen(_ s: Planungsspeicher) throws -> Archivbestand {
        let start = try #require(Tag(iso: "2025-08-04"))
        let planung = Planung.leer(titel: "Prüfvektor 2025/26", start: start, wochen: 4, basis: "", klassen: [], fachfarben: [:])
        let jahr = Archivjahr(id: "j-1", schuljahr: "2025/26", archiviert: RuecknahmeLernendenPruefungen.stempel,
                              planung: planung, lernende: RuecknahmeLernendenPruefungen.entwurf())
        let archiv = Archivbestand(geaendert: "", jahre: [jahr])
        #expect(s.archivSchreiben(archiv) == nil)
        return archiv
    }

    /// Die Personen im Archiv — ein unlesbares Archiv ist selbst ein Befund, kein leeres (Z-AS2a-10).
    private func personenImArchiv(_ s: Planungsspeicher) -> [String]? {
        guard case .gelesen(let archiv, _, _) = s.lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) else {
            Issue.record("das Archiv ist nicht lesbar")
            return nil
        }
        return archiv.jahre.flatMap { $0.lernende?.lernende.map(\.id) ?? [] }
    }

    @Test("Eine Löschung im Archiv wirkt auf das Archiv, das beim Schreiben gilt — eine zweite auf altem Stand setzt die erste nicht zurück (Z-AS2a-02, Z-AS2a-05)")
    func archivLoeschungFrischAngewandt() async throws {
        let ablage = try ordner("archiv-frisch")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        let gezeigt = try archivAnlegen(s)
        var geschrieben = 0
        s.offenerDialog = .lernende  // Das Archiv steht im Blatt; dort hängt die Frage (E418).
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let ersteGeschrieben = await uhr.vorruecken(bis: { geschrieben == 1 }, hoechstens: .seconds(1))
        try #require(ersteGeschrieben, "die erste Löschung ist geschrieben")
        // Die zweite Frage kommt aus der Ansicht, die das Archiv noch mit „l-1“ zeigt.
        s.archivPersonLoeschenFragen("l-2", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let zweiteGeschrieben = await uhr.vorruecken(bis: { geschrieben == 2 }, hoechstens: .seconds(1))
        try #require(zweiteGeschrieben, "die zweite Löschung ist geschrieben")
        let danach = personenImArchiv(s)
        #expect(danach == ["l-3"], Comment(rawValue: "\(danach ?? [])"))
    }

    @Test("Eine bestätigte Löschung im Archiv geschieht noch vor dem Beenden — einmal (Z-AS2a-07)")
    func archivLoeschungVorDemBeenden() async throws {
        let ablage = try ordner("archiv-beenden")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        let gezeigt = try archivAnlegen(s)
        var geschrieben = 0
        s.offenerDialog = .lernende  // Das Archiv steht im Blatt; dort hängt die Frage (E418).
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        #expect(s.ausstehendeFortsetzungen == 1, "die Fortsetzung steht noch aus")
        // Gleich danach beendet, vor der Fortsetzung: Das Beenden führt sie noch aus.
        #expect(s.beendenErlauben())
        #expect(geschrieben == 1 && personenImArchiv(s) == ["l-2", "l-3"], "vor dem Beenden gelöscht")
        await uhr.vorruecken(um: .seconds(1))  // über den Verzug der Fortsetzung hinaus
        #expect(s.ausstehendeFortsetzungen == 0, "die Fortsetzung lief")
        #expect(geschrieben == 1, "die Fortsetzung schreibt nicht ein zweites Mal")
    }

    @Test("Scheitert eine ausstehende Löschung im Archiv beim Beenden, hält das Beenden an — die Warnung bleibt zu sehen; erneut beendet es (Z-AS2a-08)")
    func archivLoeschungScheitertBeimBeenden() async throws {
        let ablage = try ordner("archiv-scheitert")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        let gezeigt = try archivAnlegen(s)
        s.offenerDialog = .lernende  // Das Archiv steht im Blatt; dort hängt die Frage (E418).
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu) }
        s.rueckfrageBeantworten(true)
        // Das Archiv lässt sich nicht ändern — nur die Lernendendaten sind gesperrt, die Planung sichert wie immer.
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        #expect(!s.beendenErlauben() && s.rueckfrage == nil, "das Beenden hält an, ohne weitere Frage")
        #expect(s.beendenAmArchivAngehalten
                && Planungsspeicher.beendengrund(frage: s.rueckfrage, wartete: false, archiv: s.beendenAmArchivAngehalten)
                    .hasPrefix("Eine Löschung im Archiv ließ sich nicht schreiben"), "ein Skript erfährt den Grund (Z-AS2a-11)")
        #expect(s.meldungen.contains { $0.text.hasPrefix("Das Archiv ließ sich nicht ändern") },
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
        s.lernende.schreibsperre = nil
        #expect(s.beendenErlauben() && !s.beendenAmArchivAngehalten, "ein zweites Beenden beendet — die Löschung ist nicht mehr ausstehend")
        #expect(personenImArchiv(s) == ["l-1", "l-2", "l-3"], "nichts gelöscht, nichts zerstört")
    }

    // ── Die Freigabe nach „Trotzdem beenden“ (B91, E414, E415) ────────────

    /// Die Lernendendaten lassen sich nicht sichern — das Beenden stellt die Verlustfrage; ein Fenster für sie
    /// gibt es (E425). Gesperrt, lässt sich auch das Archiv nicht schreiben.
    private func verlustDroht(_ s: Planungsspeicher) throws {
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fensterFuerFrage = { {} }
        let bestand = try #require(s.lernende.bestand)
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        #expect(s.lernende.setzen(bestand) != nil && s.verlustDroht)
        #expect(!s.beendenErlauben() && s.rueckfrage?.bestaetigung == "Trotzdem beenden",
                "applicationShouldTerminate: die Verlustfrage")
    }

    @Test("„Trotzdem beenden“ beendet — das Beenden nach der Antwort fragt nicht noch einmal (E414, E415)")
    func trotzdemBeendenBeendet() async throws {
        let ablage = try ordner("freigabe-beendet")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        defer { s.lernende.schreibsperre = nil }
        // Das Beenden fragt den Delegaten wie AppKit; beendet ist, was er erlaubt.
        var beendet = 0, abgelehnt = 0
        s.appBeenden = { [weak s] in if s?.beendenErlauben() == true { beendet += 1 } else { abgelehnt += 1 } }
        try verlustDroht(s)
        s.rueckfrageBeantworten(true)
        let entschieden = await uhr.vorruecken(bis: { beendet + abgelehnt == 1 }, hoechstens: .seconds(1))
        try #require(entschieden, "die Antwort beendet")
        await uhr.vorruecken(um: .zero)  // auch, was zur selben Frist noch fällig ist (Z-AT6g2-01)
        #expect(beendet == 1 && abgelehnt == 0 && s.rueckfrage == nil, "beendet, ohne ein zweites Mal zu fragen")
    }

    @Test("Nach „Trotzdem beenden“ gilt die Freigabe nur für das eine Beenden — lehnt AppKit es ab, fragt das nächste wieder (B91, E414)")
    func freigabeNachAbgelehntemBeenden() async throws {
        let ablage = try ordner("freigabe-abgelehnt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        defer { s.lernende.schreibsperre = nil }
        // AppKit lehnt ab, ohne den Delegaten zu fragen — wie bei einem Blatt, das vor dem Beenden aufging.
        var beendet = 0
        s.appBeenden = { beendet += 1 }
        try verlustDroht(s)
        s.rueckfrageBeantworten(true)
        let entschieden = await uhr.vorruecken(bis: { beendet == 1 }, hoechstens: .seconds(1))
        try #require(entschieden, "die Antwort beendet")
        // Beide Wege fragen wieder — ⌘Q, Dock und AppleScript über `beenden()`, AppKit über den Delegaten.
        s.beenden()
        #expect(!s.beendetGleich && s.rueckfrage?.bestaetigung == "Trotzdem beenden",
                "das nächste ⌘Q fragt wieder — die Sicherung scheitert weiter")
        s.rueckfrageBeantworten(false)
        #expect(!s.beendenErlauben() && s.rueckfrage?.bestaetigung == "Trotzdem beenden",
                "auch applicationShouldTerminate fragt wieder")
    }

    @Test("Hält das Beenden nach „Trotzdem beenden“ an einer Löschung im Archiv an, fragt das nächste wieder (G1-04, E414)")
    func freigabeNachHaltImArchiv() async throws {
        let ablage = try ordner("freigabe-archiv")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        defer { s.lernende.schreibsperre = nil }
        var beendet = 0, abgelehnt = 0
        s.appBeenden = { [weak s] in if s?.beendenErlauben() == true { beendet += 1 } else { abgelehnt += 1 } }
        let gezeigt = try archivAnlegen(s)
        try verlustDroht(s)
        s.rueckfrageBeantworten(true)
        // Vor der Fortsetzung bestätigt: eine Löschung im Archiv — sie steht aus, wenn die Fortsetzung beendet.
        s.offenerDialog = .lernende  // Das Archiv steht im Blatt; dort hängt die Frage (E418).
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu) }
        s.rueckfrageBeantworten(true)
        s.offenerDialog = nil  // Das Blatt ist zu; die Verlustfrage hängt an der Hauptfläche.
        let entschieden = await uhr.vorruecken(bis: { beendet + abgelehnt == 1 }, hoechstens: .seconds(1))
        try #require(entschieden, "die Fortsetzung beendet und hält am Archiv an")
        #expect(beendet == 0 && s.beendenAmArchivAngehalten, "angehalten an der Löschung, die sich nicht schreiben ließ")
        #expect(!s.beendenErlauben() && s.rueckfrage?.bestaetigung == "Trotzdem beenden",
                "das nächste Beenden fragt wieder — die Sicherung scheitert weiter")
    }

    @Test("Kommt nach „Trotzdem beenden“ vor dem Beenden eine zweite Verlustfrage, gilt ihre Antwort — auch „Abbrechen“ (Z-AU2-01)")
    func zweiteVerlustfrageGilt() async throws {
        let ablage = try ordner("freigabe-zweite")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        defer { s.lernende.schreibsperre = nil }
        var beendet = 0
        s.appBeenden = { beendet += 1 }
        try verlustDroht(s)
        s.rueckfrageBeantworten(true)
        // ⌘Q vor der Fortsetzung: die zweite Verlustfrage; die Fortsetzung der ersten wartet hinter ihr.
        s.beenden()
        #expect(s.rueckfrage?.bestaetigung == "Trotzdem beenden" && !s.beendetGleich, "⌘Q vor der Fortsetzung: die Verlustfrage")
        let zurueckgestellt = await uhr.vorruecken(bis: { s.ausstehendeFortsetzungen == 0 }, hoechstens: .seconds(1))
        try #require(zurueckgestellt, "die erste Fortsetzung wartet hinter der zweiten Frage")
        // Umentschieden — noch exportieren.
        s.rueckfrageBeantworten(false)
        #expect(s.ausstehendeFortsetzungen == 1, "die zurückgestellte Fortsetzung ist nachgeholt")
        let nachgeholt = await uhr.vorruecken(bis: { s.ausstehendeFortsetzungen == 0 }, hoechstens: .seconds(1))
        try #require(nachgeholt, "die nachgeholte Fortsetzung ist gelaufen")
        #expect(beendet == 0, "„Abbrechen“ gilt — die Fortsetzung der ersten Antwort beendet nicht")
        s.beenden()
        s.rueckfrageBeantworten(true)
        let beendetZuletzt = await uhr.vorruecken(bis: { beendet == 1 }, hoechstens: .seconds(1))
        try #require(beendetZuletzt, "die jüngste Antwort beendet")
    }

    @Test("Wartet nach „Trotzdem beenden“ eine bestätigte Handlung hinter derselben Frage, beendet die App nicht vor ihr — mit Ton; das nächste Beenden fragt wieder (H1-01, Z-AU11-01)")
    func trotzdemBeendenWartetAufBestaetigtes() async throws {
        let ablage = try ordner("freigabe-handlung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        defer { s.lernende.schreibsperre = nil }
        var beendet = 0
        s.appBeenden = { beendet += 1 }
        try verlustDroht(s)
        s.rueckfrageBeantworten(true)
        // Vor der Fortsetzung: eine Frage, deren Handlung erst nach dem Schließen ihres Alerts läuft.
        var gelaufen = false
        s.fragen("Die gewählten Vorhaben entfernen?", bestaetigung: "Entfernen", nachDemSchliessen: true) { gelaufen = true }
        let zurueckgestellt = await uhr.vorruecken(bis: { s.ausstehendeFortsetzungen == 0 }, hoechstens: .seconds(1))
        try #require(zurueckgestellt, "die Fortsetzung wartet hinter dieser Frage")
        let toene = s.systemtoene
        antwortenBeiHaengendemAlert(s)
        let handlungGelaufen = await uhr.vorruecken(bis: { gelaufen }, hoechstens: .seconds(1))
        try #require(handlungGelaufen, "die bestätigte Handlung läuft")
        await uhr.vorruecken(um: .zero)  // auch, was zur selben Frist noch fällig ist (Z-AT6g2-01)
        #expect(beendet == 0, "„Trotzdem beenden“ beendet nicht vor der bestätigten Handlung")
        #expect(s.systemtoene == toene + 1, "nicht beendet — mit Ton")
        #expect(!s.beendenErlauben() && s.rueckfrage?.bestaetigung == "Trotzdem beenden", "das nächste Beenden fragt wieder")
        s.rueckfrageBeantworten(false)
    }

    // ── Beenden per AppleScript bei offenem Blatt (B90, E416) ─────────────

    @Test("Ohne Blatt wird gleich abgelehnt — keine späte Meldung (B90)")
    func beendenOhneBlattGleich() async throws {
        let ablage = try ordner("beenden-gleich")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        var beendet = 0
        s.appBeenden = { beendet += 1 }
        var gruende: [String] = []
        s.beendenAbgelehnt = { gruende.append($0) }
        s.beenden()
        #expect(beendet == 1 && !s.beendetGleich, "gleich versucht, gleich abgelehnt")
        await uhr.vorruecken(um: .seconds(1))
        #expect(gruende.isEmpty, "keine späte Meldung")
    }

    @Test("Bei offenem Blatt erfährt ein Skript die Ablehnung, die erst nach dem Schließen der Blätter kommt (B90, E416, E427)")
    func spaeteAblehnungAmBlatt() async throws {
        let ablage = try ordner("spaet-blatt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        // AppKit lehnt ab, ohne den Delegaten zu fragen — ein Blatt schloss nicht.
        var beendet = 0
        s.appBeenden = { beendet += 1 }
        var gruende: [String] = []
        s.beendenAbgelehnt = { gruende.append($0) }
        s.offenerDialog = .klassen
        s.beenden()
        #expect(s.beendetGleich && beendet == 0, "unterwegs: Erst lösen sich die Blätter")
        try await abwarten("die Ablehnung ist gemeldet") { !gruende.isEmpty }
        #expect(beendet == 1 && !s.beendetGleich, "einmal versucht, abgelehnt")
        #expect(gruende == ["Ein Blatt ließ sich nicht schließen; das Beenden wurde abgelehnt."],
                Comment(rawValue: gruende.joined(separator: " | ")))
    }

    @Test("Hält das Beenden nach dem Schließen der Blätter an einer Löschung im Archiv an, erfährt ein Skript es mit Grund (B90, E416)")
    func spaeteAblehnungImArchiv() async throws {
        let ablage = try ordner("spaet-archiv")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        defer { s.lernende.schreibsperre = nil }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        // Das Beenden fragt den Delegaten wie AppKit.
        var beendet = 0, abgelehnt = 0
        s.appBeenden = { [weak s] in if s?.beendenErlauben() == true { beendet += 1 } else { abgelehnt += 1 } }
        var gruende: [String] = []
        s.beendenAbgelehnt = { gruende.append($0) }
        let gezeigt = try archivAnlegen(s)
        s.offenerDialog = .lernende  // Das Archiv steht im Blatt; dort hängt die Frage (E418).
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu) }
        s.rueckfrageBeantworten(true)
        // Das Archiv lässt sich nicht ändern; die Löschung steht aus, wenn das Beenden kommt.
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        s.offenerDialog = .klassen
        s.beenden()
        let gemeldet = await uhr.vorruecken(bis: { !gruende.isEmpty }, hoechstens: .seconds(1))
        try #require(gemeldet, "die Ablehnung ist gemeldet")
        #expect(abgelehnt == 1 && beendet == 0 && s.beendenAmArchivAngehalten, "angehalten an der Löschung")
        #expect(gruende.count == 1 && gruende[0].hasPrefix("Eine Löschung im Archiv ließ sich nicht schreiben"),
                Comment(rawValue: gruende.joined(separator: " | ")))
    }

    @Test("Ein Halt im Archiv aus einem früheren Versuch verdrängt den Grund „Blatt“ der späten Ablehnung nicht (B90, Z-AU3-05, Z-AU3-09)")
    func spaeteAblehnungAlterArchivhalt() async throws {
        let ablage = try ordner("spaet-alter-halt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        defer { s.lernende.schreibsperre = nil }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        // AppKit lehnt ab, ohne den Delegaten zu fragen.
        s.appBeenden = {}
        var gruende: [String] = []
        s.beendenAbgelehnt = { gruende.append($0) }
        let gezeigt = try archivAnlegen(s)
        s.offenerDialog = .lernende  // Das Archiv steht im Blatt; dort hängt die Frage (E418).
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu) }
        s.rueckfrageBeantworten(true)
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        s.offenerDialog = .klassen
        s.beenden()
        // Vor der späten Aufgabe hält ein anderer Versuch an der Löschung an — der Merker steht.
        #expect(!s.beendenErlauben() && s.beendenAmArchivAngehalten, "ein anderer Versuch hielt im Archiv an")
        try await abwarten("die Ablehnung ist gemeldet") { !gruende.isEmpty }
        #expect(gruende == ["Ein Blatt ließ sich nicht schließen; das Beenden wurde abgelehnt."],
                Comment(rawValue: gruende.joined(separator: " | ")))
    }

    @Test("Scheitert die Sicherung erst beim Beenden nach dem Schließen der Blätter, erfährt ein Skript den Grund der Verlustfrage (B90, Z-AU3-04)")
    func spaeteAblehnungDurchVerlustfrage() async throws {
        let ablage = try ordner("spaet-verlust")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        defer { s.lernende.schreibsperre = nil }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fensterFuerFrage = { {} }
        var beendet = 0, abgelehnt = 0
        s.appBeenden = { [weak s] in if s?.beendenErlauben() == true { beendet += 1 } else { abgelehnt += 1 } }
        var gruende: [String] = []
        s.beendenAbgelehnt = { gruende.append($0) }
        s.offenerDialog = .klassen
        s.beenden()
        // Das Blatt schrieb beim Verschwinden — die Sicherung scheitert erst danach.
        let bestand = try #require(s.lernende.bestand)
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        #expect(s.lernende.setzen(bestand) != nil)
        try await abwarten("die Ablehnung ist gemeldet") { !gruende.isEmpty }
        #expect(abgelehnt == 1 && beendet == 0 && s.rueckfrage?.bestaetigung == "Trotzdem beenden", "die Verlustfrage steht")
        #expect(gruende == ["Die Lernendendaten ließen sich nicht sichern; das Beenden wartet auf eine Antwort."],
                Comment(rawValue: gruende.joined(separator: " | ")))
    }

    @Test("Erscheint beim Beenden nach dem Schließen der Blätter eine Frage ohne eigenen Grund, heißt es „Eine Rückfrage steht“ (B90, Z-AU3-05)")
    func spaeteAblehnungAnFrage() async throws {
        let ablage = try ordner("spaet-frage")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        // Eine Folgefrage erscheint, AppKit lehnt ab.
        s.appBeenden = { [weak s] in s?.fragen("Eine Folgefrage", bestaetigung: "Ja") {} }
        var gruende: [String] = []
        s.beendenAbgelehnt = { gruende.append($0) }
        s.offenerDialog = .klassen
        s.beenden()
        try await abwarten("die Ablehnung ist gemeldet") { !gruende.isEmpty }
        #expect(gruende == ["Eine Rückfrage steht; das Beenden wartet auf eine Antwort."],
                Comment(rawValue: gruende.joined(separator: " | ")))
    }

    @Test("Der Grund für ein Skript folgt dem Stand: Gesperrte Lernendendaten nennen die Lernendendaten (Z-AS4-05)")
    func verlustgrundAusDemStandLernende() async throws {
        let ablage = try ordner("grund-lernende")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let bestand = try #require(s.lernende.bestand)
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        defer { s.lernende.schreibsperre = nil }
        #expect(s.lernende.setzen(bestand) != nil && s.verlustDroht)
        #expect(s.verlustgrundJetzt == "Die Lernendendaten ließen sich nicht sichern; das Beenden wartet auf eine Antwort.",
                Comment(rawValue: s.verlustgrundJetzt))
    }

    // ── AS3: Warteschlange und Ort (Punkte 4, 5), B87 ─────────────────────────

    @Test("Eine wartende Frage, deren Blatt inzwischen schloss, erscheint nicht — sie entfällt, und es wird gesagt; das Menü bleibt bedienbar (Z14c4-06, E330, E332)")
    func nachgeholteFrageOhneBlattEntfaellt() async throws {
        let ablage = try ordner("ohne-blatt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.offenerDialog = .klassen
        s.fragen("Erste", bestaetigung: "Ja", ort: .klassen) {}
        s.fragen("Zweite", bestaetigung: "Ja", ort: .klassen) {}
        #expect(s.wartendeRueckfragen.count == 1)
        s.rueckfrageBeantworten(false)
        s.offenerDialog = nil  // Die Handlung schloss das Blatt.
        let fort = await uhr.vorruecken(bis: { s.wartendeRueckfragen.isEmpty }, hoechstens: .seconds(1))
        try #require(fort, "die wartende ist fort")
        #expect(s.rueckfrage == nil, "die Frage des geschlossenen Blatts erscheint nicht")
        #expect(s.meldungen.last?.text == "Eine wartende Rückfrage entfiel, weil ihr Blatt geschlossen wurde."
                && s.meldungen.last?.art == .warnung, Comment(rawValue: s.meldungen.last?.text ?? "—"))
        #expect(!s.dialogOffen, "das Menü bleibt bedienbar")
    }

    @Test("Eine wartende Frage der Hauptfläche, vor der die Antwort ein Blatt öffnete, entfällt — mit eigenem Hinweis, wenn das Blatt zu ist (E394)")
    func nachgeholteHauptflaechenfrageHinterBlattEntfaellt() async throws {
        let ablage = try ordner("hinter-neuem-blatt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") { [weak s] in s?.dialogOeffnen(.einstellungen) }
        s.fragen("Zweite", bestaetigung: "Ja") {}
        s.rueckfrageBeantworten(true)
        let fort = await uhr.vorruecken(bis: { s.wartendeRueckfragen.isEmpty }, hoechstens: .seconds(1))
        try #require(fort, "die wartende ist fort")
        let hinweis = "Eine wartende Rückfrage entfiel, weil ein Blatt darüber geöffnet wurde."
        #expect(s.rueckfrage == nil && s.offenerDialog == .einstellungen && !s.meldungen.contains { $0.text == hinweis },
                "die Frage der Hauptfläche erscheint nicht hinter dem Blatt — der Hinweis auch noch nicht (Z-AS3-05)")
        let erschienen = await uhr.vorruecken(bis: { s.rueckfrage != nil || s.meldungen.contains { $0.text == hinweis } },
                                              hoechstens: .seconds(1))
        #expect(!erschienen, "auch danach nicht, solange das Blatt steht")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text == hinweis }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Blatt der Hinweis")
        #expect(s.meldungen.last?.art == .warnung)
    }

    @Test("Eine Planung gleicher Herkunft per Finder öffnen, während ein Blatt offen ist: abgewiesen, keine Frage hinter dem Blatt — gesagt, wenn es zu ist (Z14c4-06, E331, E391)")
    func oeffnenHinterBlattAbgewiesen() async throws {
        let ablage = try ordner("ersetzen-hinter-blatt")
        let quelle = try ordner("ersetzen-hinter-blatt-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var ersatz = try #require(s.planung)
        ersatz.titel = "Ersatz"
        let datei = quelle.appending(component: "ersatz.json")
        try Planungsdatei.schreiben(ersatz).write(to: datei)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.offenerDialog = .klassen
        let toene = s.systemtoene
        s.importieren(von: datei)
        #expect(s.systemtoene == toene + 1, "der Ton kommt sofort (E399)")
        let text = "„Ersatz“ wurde nicht geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen."
        #expect(s.rueckfrage == nil && s.planung?.titel != "Ersatz" && !s.meldungen.contains { $0.text == text },
                "abgewiesen — keine Frage „… wird ersetzt“ hinter dem Blatt, noch kein Text (Z-AS3-05)")
        let dahinter = await uhr.vorruecken(bis: { s.rueckfrage != nil || s.planung?.titel == "Ersatz" || s.meldungen.contains { $0.text == text } },
                                             hoechstens: .seconds(1))
        #expect(!dahinter, "auch über die Zeit nicht, solange das Blatt steht")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Blatt der Text")
    }

    @Test("Der Sprung zu einem Vorhaben behält die wartenden Fragen — sie erscheinen danach (Z14c4-07, E333)")
    func sprungBehaeltWartende() async throws {
        let ablage = try ordner("sprung-wartende")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let vorhaben = try #require(s.planung?.eintraege.first { $0.termin == t }).id
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Zweite", bestaetigung: "Ja") {}
        s.rueckfrageBeantworten(false)
        s.zeigeVorhaben(vorhaben)
        #expect(s.wartendeRueckfragen.count == 1, "der Sprung behält die wartende")
        let erschienen = await uhr.vorruecken(bis: { s.rueckfrage?.text == "Zweite" }, hoechstens: .seconds(1))
        try #require(erschienen, "die wartende erscheint nach dem Sprung")
    }

    @Test("Eine Datei per Finder öffnen, während das Blatt „Planung entsperren“ offen ist: abgewiesen, der Text erst, wenn das Blatt zu ist (B87, E393)")
    func oeffnenHinterEntsperrenKommtNach() async throws {
        let ablage = try ordner("hinter-entsperren")
        let quelle = try ordner("hinter-entsperren-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let datei = try fremdeDatei(s, in: quelle)
        s.jetztSichern()
        // Ein neuer Start auf derselben Ablage: versiegelt, das Blatt „Planung entsperren“ steht.
        let gesperrt = Planungsspeicher(ablage: Ablage(ordner: ablage))
        let uhr = Stelluhr()
        gesperrt.takt = uhr
        defer { uhr.abraeumen() }
        gesperrt.starten()
        #expect(gesperrt.entsperrungOffen && gesperrt.offenerDialog == .entsperren)
        gesperrt.rueckfrageSichtbar = { [weak gesperrt] in gesperrt?.rueckfrage != nil }
        let meldungen = gesperrt.meldungen.count
        let davor = Set(gesperrt.meldungen.map(\.id))
        let toene = gesperrt.systemtoene
        gesperrt.importieren(von: datei)
        #expect(gesperrt.meldungen.count == meldungen, "hinter dem Blatt noch kein Text — er läge dort ungelesen")
        #expect(gesperrt.systemtoene == toene + 1, "der Ton kommt sofort (Z-AS3-08)")
        let dahinter = await uhr.vorruecken(bis: { gesperrt.meldungen.contains { !davor.contains($0.id) } },
                                             hoechstens: .seconds(1))
        #expect(!dahinter, "auch über die Zeit nicht, solange das Blatt steht")
        gesperrt.entsperrungAbbrechen()
        let gesehen = await uhr.vorruecken(bis: {
            gesperrt.meldungen.last?.text == "„fremd.json“ wurde nicht geöffnet, weil die Planung noch nicht entsperrt war. "
                + "Bitte die Datei erneut öffnen."
        }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Blatt der Text")
    }

    // ── AS3, nach der Review (Z-AS3-01, -02, -03, -06, E395) ──────────────────

    @Test("Eine fremde Datei wartet auf ihre Entsperrung: Dieselbe erneut geöffnet bleibt still, eine andere bekommt den Text aus E391 — je mit Ton (Z-AS3-01)")
    func oeffnenHinterFremderEntsperrung() async throws {
        let ablage = try ordner("fremde-entsperrung")
        let quelle = try ordner("fremde-entsperrung-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        let andere = try fremdeDatei(s, in: quelle)
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        var p = try #require(s.planung)
        p.titel = "Von draußen"
        let fremde = quelle.appending(component: "fremd-versiegelt.json")
        try fremder.versiegeln(try Planungsdatei.schreiben(p), inhalt: .planung, ziel: .export).write(to: fremde)
        s.importieren(von: fremde)
        #expect(s.entsperrungOffen && !s.entsperrungFuerAblage && s.offenerDialog == .entsperren)
        let toene = s.systemtoene
        s.importieren(von: fremde)
        s.importieren(von: andere)
        #expect(s.systemtoene == toene + 2, "je ein Ton sofort")
        s.entsperrungAbbrechen()
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.last?.text == "„fremd.json“ wurde nicht geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen."
        }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Blatt der Text zur anderen Datei")
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.hasPrefix("„fremd-versiegelt.json“") } },
                                              hoechstens: .seconds(1))
        #expect(!erschienen, "auch nicht kurz erschienen")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("„fremd-versiegelt.json“") },
                Comment(rawValue: "dieselbe Datei: still — " + s.meldungen.map(\.text).joined(separator: " | ")))
    }

    @Test("Liegt ein Bogen über dem Blatt der wartenden Frage, wartet sie — verworfen wird sie nicht; danach erscheint sie (Z-AS3-03)")
    func wartendeFrageUnterBogenWartet() async throws {
        let ablage = try ordner("unter-bogen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        var bogenOffen = false
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(bogenOffen: { bogenOffen }))
        s.offenerDialog = .lernende
        s.fragen("Erste", bestaetigung: "Ja", ort: .lernende) {}
        s.fragen("Zweite", bestaetigung: "Ja", ort: .lernende) {}
        bogenOffen = true  // Ein Bogen geht über dem Blatt auf.
        s.rueckfrageBeantworten(false)
        await uhr.vorruecken(um: .seconds(2))  // über die Frist des Nachholens hinaus
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.count == 1, "unter dem Bogen wartet sie")
        bogenOffen = false
        await uhr.vorruecken(um: .seconds(2))
        #expect(s.rueckfrage?.text == "Zweite", "nach dem Bogen erscheint sie")
    }

    @Test("Ist das Blatt der wartenden Frage im Kommen, wartet sie und erscheint darin (Z-AS3-03)")
    func wartendeFrageFuerKommendesBlattWartet() async throws {
        let ablage = try ordner("kommendes-blatt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.offenerDialog = .klassen
        s.fragen("Erste", bestaetigung: "Ja", ort: .klassen) { [weak s] in s?.dialogOeffnen(.sitzplan) }
        s.fragen("Zweite", bestaetigung: "Ja", ort: .sitzplan) {}
        s.rueckfrageBeantworten(true)
        await uhr.vorruecken(um: .seconds(2))  // über die Frist des Nachholens hinaus
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.count == 1 && s.naechsterDialog == .sitzplan,
                "für das kommende Blatt wartet sie — verworfen wird sie nicht")
        s.naechstenDialogOeffnen()
        await uhr.vorruecken(um: .seconds(2))
        #expect(s.rueckfrage?.text == "Zweite", "im Blatt erscheint sie")
    }

    @Test("Eine wartende Frage am Bogen, dessen Bogen schloss, entfällt mit eigenem Hinweis — als Warnung (E395)")
    func wartendeBogenfrageEntfaellt() async throws {
        let ablage = try ordner("bogen-zu")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        var bogenOffen = true
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(bogenOffen: { bogenOffen }))
        s.offenerDialog = .lernende
        s.fragen("Erste", bestaetigung: "Ja", ort: .bogen) {}
        s.fragen("Zweite", bestaetigung: "Ja", ort: .bogen) {}
        s.rueckfrageBeantworten(false)
        bogenOffen = false  // Die Handlung schloss den Bogen.
        let fort = await uhr.vorruecken(bis: { s.wartendeRueckfragen.isEmpty }, hoechstens: .seconds(1))
        try #require(fort, "die wartende ist fort")
        let hinweis = "Eine wartende Rückfrage entfiel, weil ihr Bogen geschlossen wurde."
        #expect(s.rueckfrage == nil && !s.meldungen.contains { $0.text == hinweis }, "solange das Blatt steht, noch kein Hinweis")
        let erschienen = await uhr.vorruecken(bis: { s.rueckfrage != nil || s.meldungen.contains { $0.text == hinweis } },
                                              hoechstens: .seconds(1))
        #expect(!erschienen, "auch danach nicht, solange das Blatt steht")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text == hinweis }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Blatt der Hinweis")
        #expect(s.meldungen.last?.art == .warnung)
    }

    @Test("Zwei wartende Fragen eines geschlossenen Blatts entfallen — ein Hinweis, nicht zwei (Z-AS3-02)")
    func zweiVerworfeneEinHinweis() async throws {
        let ablage = try ordner("zwei-verworfen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        // Gezählt im Meldungsfang: Er verfällt nicht (E547).
        s.meldungsfang = []
        s.offenerDialog = .klassen
        s.fragen("Erste", bestaetigung: "Ja", ort: .klassen) {}
        s.fragen("Zweite", bestaetigung: "Ja", ort: .klassen) {}
        s.fragen("Dritte", bestaetigung: "Ja", ort: .klassen) {}
        s.rueckfrageBeantworten(false)
        s.offenerDialog = nil
        // Die Hinweise kommen im selben Ereignis wie das Entfernen, ein zweiter auch — gezählt gleich danach (E557).
        let fort = await uhr.vorruecken(bis: { s.wartendeRueckfragen.isEmpty }, hoechstens: .seconds(1))
        try #require(fort, "die wartenden sind fort")
        let text = "Eine wartende Rückfrage entfiel, weil ihr Blatt geschlossen wurde."
        let gezaehlt = s.meldungsfang?.filter { $0.text == text }.count ?? 0
        #expect(gezaehlt == 1, Comment(rawValue: "\(gezaehlt)"))
    }

    @Test("Leert das Verwerfen die Warteschlange, kommt auch eine vorgemerkte Meldung — kein Wechsel der Frage stößt sie sonst an (Z-AS3-06)")
    func vorgemerkteMeldungNachVerworfenerFrage() async throws {
        let ablage = try ordner("vorgemerkt-verworfen")
        let quelle = try ordner("vorgemerkt-verworfen-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(s, in: quelle)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.offenerDialog = .klassen
        s.fragen("Erste", bestaetigung: "Ja", ort: .klassen) {}
        s.fragen("Zweite", bestaetigung: "Ja", ort: .klassen) {}
        s.importieren(von: datei)
        s.rueckfrageBeantworten(false)
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.contains { $0.text == "„fremd.json“ wurde nicht geöffnet, weil eine Rückfrage stand. Bitte die Datei erneut öffnen." }
        }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Verwerfen der vorgemerkte Text")
    }

    @Test("Die Lage eines Orts: zu sehen, verdeckt (Farbwahl, Material, Vorhaben-Blatt, Bogen am Blatt) oder im Kommen, sonst fort (Z-AS3-03, -11, -12, -13)")
    func ortslagen() async throws {
        let ablage = try ordner("ortslagen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try await speicher(ablage)
        let bogenAmBlatt = Merker()
        s.bogenSichtbar = { bogenAmBlatt.an }
        s.offenerDialog = .klassen
        #expect(s.ortslage(.klassen) == .sichtbar && s.ortslage(.hauptansicht) == .fort && s.ortslage(.sitzplan) == .fort)
        s.farbwahlFuer = .kurs("k-kl")
        #expect(s.ortslage(.klassen) == .verdeckt, "unter der Farbwahl")
        s.farbwahlFuer = nil
        bogenAmBlatt.an = true
        #expect(s.ortslage(.klassen) == .verdeckt, "unter einem Sichern-, Öffnen- oder Druckbogen (Z-AS3-11)")
        bogenAmBlatt.an = false
        s.vorhabenDialog = VorhabenEntwurf(klasseId: "k-kl", woche: 1)
        #expect(s.ortslage(.klassen) == .verdeckt && s.ortslage(.vorhaben) == .verdeckt, "zwei Blätter: Keines gilt als zu sehen")
        s.offenerDialog = nil
        #expect(s.ortslage(.vorhaben) == .sichtbar && s.ortslage(.hauptansicht) == .fort)
        s.materialblattOffen = true
        #expect(s.ortslage(.vorhaben) == .verdeckt, "unter dem Material-Blatt")
        s.materialblattOffen = false
        bogenAmBlatt.an = true
        #expect(s.ortslage(.vorhaben) == .verdeckt, "unter einem Sichern- oder Öffnen-Bogen (Z-AS3-11)")
        bogenAmBlatt.an = false
        s.vorhabenDialog = nil
        // Der Bogen am Blatt „Lernende“ — und ein Vorhaben-Blatt darüber (Z-AS3-12).
        var bogenOffen = true
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(bogenOffen: { bogenOffen }))
        s.offenerDialog = .lernende
        #expect(s.ortslage(.bogen) == .sichtbar && s.ortslage(.lernende) == .verdeckt)
        s.vorhabenDialog = VorhabenEntwurf(klasseId: "k-kl", woche: 1)
        #expect(s.ortslage(.bogen) == .verdeckt, "Vorhaben-Blatt über dem Bogen")
        s.vorhabenDialog = nil
        bogenOffen = false
        #expect(s.ortslage(.bogen) == .fort && s.ortslage(.lernende) == .sichtbar)
        // Im Kommen.
        s.dialogOeffnen(.sitzplan)
        #expect(s.offenerDialog == nil && s.ortslage(.sitzplan) == .verdeckt && s.ortslage(.hauptansicht) == .fort)
    }

    @Test("Eine Planung gleicher Herkunft per Finder öffnen, während ein Blatt im Kommen ist: abgewiesen, keine Frage — gesagt, wenn alles zu ist (Z-AS3-04, Z-AS3-13)")
    func oeffnenWaehrendBlattwechselAbgewiesen() async throws {
        let ablage = try ordner("blattwechsel-oeffnen")
        let quelle = try ordner("blattwechsel-oeffnen-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var ersatz = try #require(s.planung)
        ersatz.titel = "Ersatz"
        let datei = quelle.appending(component: "ersatz.json")
        try Planungsdatei.schreiben(ersatz).write(to: datei)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.offenerDialog = .klassen
        s.dialogOeffnen(.einstellungen)
        #expect(s.offenerDialog == nil && s.naechsterDialog == .einstellungen)
        let toene = s.systemtoene
        s.importieren(von: datei)
        #expect(s.rueckfrage == nil && s.planung?.titel != "Ersatz", "abgewiesen — keine Frage, während das Blatt kommt")
        #expect(s.systemtoene == toene + 1, "der Ton kommt sofort (E399)")
        s.naechstenDialogOeffnen()
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.last?.text == "„Ersatz“ wurde nicht geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen."
        }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Blatt der Text")
    }

    // ── AS7a, aus der Gesamtreview (G1-01, G1-E1, E398, E399) ────────────────

    @Test("Ein Export der Lernendenverwaltung per Finder hinter einem offenen Blatt: nicht eingelesen, Ton sofort, Text nach dem Blatt — das „Übernehmen“ des Blatts geht danach durch (G1-01, E398)")
    func lernendenExportHinterBlatt() async throws {
        let ablage = try ordner("export-hinter-blatt")
        let quelle = try ordner("export-hinter-blatt-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        let datei = quelle.appending(component: "lernende-export.json")
        try s.lernendenExportSchreiben(nach: datei)
        // Eingelesen wird nur in eine leere Verwaltung (E287).
        let alt = try #require(s.lernende.bestand)
        #expect(s.lernendenUebernehmen(.leer(planung: alt.planung, schuljahr: alt.schuljahr,
                                             jetzt: Zeitrechnung.jetztAlsZeitstempel())) == nil)
        try #require(s.lernendenLeer)
        // Das Blatt „Lernende“ ist offen, im Entwurf eine getippte Gruppe.
        s.offenerDialog = .lernende
        let ausgang = try #require(s.lernendenEntwurfBeginnen())
        let entwurf = try #require(ausgang.mitNeuerGruppe(name: "Getippt", art: .kurs,
                                                         jetzt: Zeitrechnung.jetztAlsZeitstempel())).bestand
        let toene = s.systemtoene
        s.importieren(von: datei)
        let text = "„lernende-export.json“ wurde nicht geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen."
        #expect(s.lernendenLeer, "hinter dem Blatt nicht eingelesen")
        #expect(s.systemtoene == toene + 1, "der Ton kommt sofort (E399)")
        #expect(!s.meldungen.contains { $0.text == text }, "hinter dem Blatt noch kein Text")
        let dahinter = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text == text } }, hoechstens: .seconds(1))
        #expect(!dahinter, "auch über die Zeit nicht, solange das Blatt steht")
        let vorher = Set(s.lernende.bestand?.lerngruppen.map(\.id) ?? [])
        #expect(s.lernendenUebernehmen(entwurf, ausgang: ausgang) == nil)
        #expect(s.lernende.bestand?.lerngruppen.contains { $0.name == "Getippt" } == true, "das „Übernehmen“ geht durch")
        // Netz für die Gegenprobe: Liest die App doch ein, nimmt das „Übernehmen“ es wieder heraus (G1-01).
        #expect(vorher.isSubset(of: Set(s.lernende.bestand?.lerngruppen.map(\.id) ?? [])),
                "„Übernehmen“ verliert nichts, was auf der Platte stand")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: { s.meldungen.last?.text == text }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Blatt der Text")
    }

    @Test("Eine Datei unter fremdem Schlüssel per Finder hinter einem offenen Blatt: Das Blatt bleibt, kein Entsperren dahinter — Ton sofort, Text nach dem Blatt (G1-E1, E398)")
    func fremderSchluesselHinterBlatt() async throws {
        let ablage = try ordner("fremd-hinter-blatt")
        let quelle = try ordner("fremd-hinter-blatt-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        var p = try #require(s.planung)
        p.titel = "Von draußen"
        let datei = quelle.appending(component: "fremd-versiegelt.json")
        try fremder.versiegeln(try Planungsdatei.schreiben(p), inhalt: .planung, ziel: .export).write(to: datei)
        s.offenerDialog = .lernende
        let toene = s.systemtoene
        s.importieren(von: datei)
        #expect(s.offenerDialog == .lernende && s.naechsterDialog == nil && !s.entsperrungOffen,
                "das Blatt bleibt, kein Entsperren dahinter")
        #expect(s.systemtoene == toene + 1, "der Ton kommt sofort (E399)")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.last?.text == "„fremd-versiegelt.json“ wurde nicht geöffnet, weil ein Blatt offen war. "
                + "Bitte die Datei erneut öffnen."
        }, hoechstens: .seconds(1))
        try #require(gesehen, "nach dem Blatt der Text")
        let geoeffnet = await uhr.vorruecken(bis: { s.entsperrungOffen || s.planung?.titel == "Von draußen" }, hoechstens: .seconds(1))
        #expect(!geoeffnet, "auch danach nicht")
        #expect(!s.entsperrungOffen && s.planung?.titel != "Von draußen", "nichts entsperrt, nichts geöffnet")
    }

    @Test("Ein Export, hinter einem Blatt abgewiesen und danach doch eingelesen, sagt kein „nicht geöffnet“ hinterher — auch wenn ein Dialog des Systems die Meldung zurückhielt (Z-AS7a-03, wie Z-AS2-01)")
    func lernendenExportDochEingelesen() async throws {
        let ablage = try ordner("export-doch")
        let quelle = try ordner("export-doch-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        let datei = quelle.appending(component: "lernende-export.json")
        try s.lernendenExportSchreiben(nach: datei)
        let alt = try #require(s.lernende.bestand)
        #expect(s.lernendenUebernehmen(.leer(planung: alt.planung, schuljahr: alt.schuljahr,
                                             jetzt: Zeitrechnung.jetztAlsZeitstempel())) == nil)
        s.offenerDialog = .lernende
        s.importieren(von: datei)
        try #require(s.lernendenLeer, "hinter dem Blatt abgewiesen")
        Dialogort.frei {
            // Das Blatt ist zu, ein Dialog des Systems hält die Meldung zurück — die Datei geht jetzt auf.
            s.offenerDialog = nil
            s.importieren(von: datei)
            #expect(!s.lernendenLeer, "eingelesen")
        }
        s.vorgemerkteMeldungenZeigen()
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.hasPrefix("„lernende-export.json“ wurde nicht geöffnet") } }, hoechstens: .seconds(1))
        #expect(!erschienen, "auch nicht kurz erschienen")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("„lernende-export.json“ wurde nicht geöffnet") },
                Comment(rawValue: "eingelesen: nichts hinterher — " + s.meldungen.map(\.text).joined(separator: " | ")))
    }

    @Test("Steht ohne Planung nur „Neue Planungsdatei“ (nach einer unlesbaren Autosicherung), wird eine Datei unter fremdem Schlüssel entsperrt wie eine im Klartext geöffnet (E331) — mit Planung bleibt das Blatt (Z-AS7a-04)")
    func fremderSchluesselBeiNeuerPlanungsdatei() async throws {
        let ablage = try ordner("fremd-neue-planungsdatei")
        let quelle = try ordner("fremd-neue-planungsdatei-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try await speicher(ablage)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        var p = try #require(s.planung)
        p.titel = "Von draußen"
        let datei = quelle.appending(component: "fremd-versiegelt.json")
        try fremder.versiegeln(try Planungsdatei.schreiben(p), inhalt: .planung, ziel: .export).write(to: datei)
        // Mit Planung: „Neue Planung“ mitten in der Sitzung trägt getippte Kurse — abgewiesen (E398).
        s.offenerDialog = .neuePlanung
        s.importieren(von: datei)
        #expect(s.offenerDialog == .neuePlanung && !s.entsperrungOffen, "mit Planung bleibt das Blatt")
        // Ohne Planung hinter einem anderen Blatt: abgewiesen wie mit Planung (Z-AS7a-09).
        s.planung = nil
        s.offenerDialog = .einstellungen
        var toene = s.systemtoene
        s.importieren(von: datei)
        #expect(s.offenerDialog == .einstellungen && !s.entsperrungOffen && s.systemtoene == toene + 1,
                "ohne Planung, anderes Blatt: abgewiesen, mit Ton")
        // Ohne Planung, nur „Neue Planungsdatei“, wie nach einer unlesbaren Autosicherung: Die App bittet, eine Planung zu öffnen.
        s.offenerDialog = .neuePlanung
        toene = s.systemtoene
        s.importieren(von: datei)
        #expect(s.entsperrungOffen && !s.entsperrungFuerAblage, "die fremde Datei wird entsperrt — wie E331")
        #expect(s.systemtoene == toene, "kein Ton")
    }
}
