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
        return p
    }

    /// Eingeschaltet: Anna und Ben, ein Termin für Anna mit Vorhaben in der Klassenleitung.
    private func speicher(_ ablage: URL) throws -> (Planungsspeicher, termin: String, anna: String) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
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
        #expect(s.planung?.eintraege.contains { $0.termin == termin } == true)
        return (s, termin, anna)
    }

    @Test("Beenden mit geändertem Blatt „Lernende“ (E300): Übernehmen, Verwerfen oder Abbrechen — ohne Änderung keine Frage")
    func beendenFragt() async throws {
        let ablage = try ordner("beenden")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try speicher(ablage)
        let ohneBlatt = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(!ohneBlatt, "ohne Blatt nichts zu fragen")
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt, "geändert: die Frage steht")
        let frage = try #require(s.rueckfrage)
        #expect(frage.text == "Die Änderungen an den Lernenden übernehmen?\n\nDas Blatt „Lernende“ ist noch offen; ohne "
                + "„Übernehmen“ gehen seine Änderungen beim Beenden verloren.", Comment(rawValue: frage.text))
        #expect(frage.bestaetigung == "Übernehmen" && frage.weitere == "Verwerfen" && frage.ablehnung == "Abbrechen"
                && frage.ort == .lernende)
        s.rueckfrageBeantworten(true)
        #expect(s.lernende.bestand?.anliegen.first { $0.id == t }?.titel == "Gespräch", "übernommen")
        // Die Fortsetzung kommt nach der Frist, nicht in der Knopf-Handlung (E319).
        try await abwarten("übernommen, dann weiter") { weiter == 1 }
        let nochmal = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(!nochmal, "einmal gefragt, nicht noch einmal")

        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { b }))
        var verworfen = 0
        let zweite = s.lernendenblattBeimBeendenFragen(dann: { verworfen += 1 })
        #expect(zweite)
        s.rueckfrageWeitere()
        #expect(s.lernende.bestand?.anliegen.first { $0.id == t }?.titel == "Gespräch", "verworfen")
        try await abwarten("verworfen, dann weiter") { verworfen == 1 }

        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { b }))
        var abgebrochen = 0
        let dritte = s.lernendenblattBeimBeendenFragen(dann: { abgebrochen += 1 })
        #expect(dritte)
        s.rueckfrageBeantworten(false)
        #expect(abgebrochen == 0, "abgebrochen: die App bleibt")
        s.lernendenblattGibtAb()
        let abgegeben = s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(!abgegeben, "abgegeben: nichts mehr zu fragen")
    }

    @Test("„Übernehmen“/„Verwerfen“ beim Beenden: die Fortsetzung wartet, bis das Alert fort ist (Z14c3-12, E319)")
    func e300FortsetzungWartetAufDasAlert() async throws {
        let ablage = try ordner("e300-alert")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try speicher(ablage)
        let blendetAus = Merker()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || blendetAus.an }
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        for knopf in ["Übernehmen", "Verwerfen"] {
            s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
            var weiter = 0
            let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
            #expect(gefragt)
            // Die Knopf-Handlung läuft, während das Alert-Blatt noch hängt.
            blendetAus.an = true
            if knopf == "Übernehmen" { s.rueckfrageBeantworten(true) } else { s.rueckfrageWeitere() }
            #expect(weiter == 0 && s.lernendenblattGriff == nil, "\(knopf): noch nicht — der Griff ist abgegeben")
            try await Task.sleep(for: .milliseconds(Int(Planungsspeicher.folgefrageVerzug * 1000) + 200))  // E145: Uhr — die Frist der Fortsetzung verstreichen lassen
            #expect(weiter == 0, "\(knopf): auch nach der Frist nicht, solange das Alert hängt")
            blendetAus.an = false
            try await abwarten("\(knopf): danach geht das Beenden weiter") { weiter == 1 }
        }
    }

    @Test("Beenden mit getippter, nicht eingetragener Namensliste (Z14b-02): erst „Die eingegebenen Namen verwerfen?“")
    func beendenMitNamensliste() async throws {
        let ablage = try ordner("namensliste")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try speicher(ablage)
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        var namen = true
        var vorbereitet = 0
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(
            vorbereiten: { vorbereitet += 1 }, namenOffen: { namen }, namenVerwerfen: { namen = false },
            aenderungen: { geaendert }))
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt && vorbereitet == 1, "Bögen zu, Felder übernommen, dann die Frage")
        #expect(s.rueckfrage?.text == "Die eingegebenen Namen verwerfen?" && s.rueckfrage?.ablehnung == "Weiter bearbeiten",
                Comment(rawValue: s.rueckfrage?.text ?? "—"))
        s.rueckfrageBeantworten(false)
        #expect(namen && weiter == 0, "„Weiter bearbeiten“: die App bleibt, die Namen auch")
        let nochmal = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(nochmal)
        s.rueckfrageBeantworten(true)
        #expect(!namen, "verworfen")
        #expect(weiter == 0, "noch nicht: erst, wenn die Frage geschlossen ist")
        try await abwarten("danach geht das Beenden weiter") { weiter == 1 }
    }

    @Test("Steht in der Wartezeit eine andere Frage, setzt die verzögerte Fortsetzung das Beenden nicht fort (Z14b-11)")
    func fortsetzungWeichtAnderer() async throws {
        let ablage = try ordner("fortsetzung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        var namen = true
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(namenOffen: { namen }, namenVerwerfen: { namen = false }))
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt)
        s.rueckfrageBeantworten(true)
        s.fragen("Eine andere Frage des Blatts", bestaetigung: "Ja", ort: .lernende) {}
        // Die Fortsetzung kommt nach `folgefrageVerzug`; dass sie ausbleibt, zeigt nur die verstrichene Zeit.
        try await Task.sleep(for: .milliseconds(Int(Planungsspeicher.folgefrageVerzug * 1000) + 400))  // E145: Uhr — Ausbleiben der verzögerten Fortsetzung
        #expect(weiter == 0, "die andere Frage bleibt, das Beenden wartet auf ein neues ⌘Q")
        #expect(s.rueckfrage?.text == "Eine andere Frage des Blatts")
    }

    @Test("Beenden bei stehender Rückfrage wartet auf ihre Antwort — die App nimmt sie nicht weg und legt keine zweite darüber (B82, E315)")
    func beendenWartetAufStehendeFrage() throws {
        let ablage = try ordner("stehend")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try speicher(ablage)
        let b = try #require(s.lernende.bestand)
        let geaendert = b.mitAnliegen(t, titel: "Gespräch", datum: "2026-08-20", frist: "", notiz: "", jetzt: b.geaendert)
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
        s.offenerDialog = .lernende
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Eine Frage des Blatts", bestaetigung: "Ja", ort: .lernende) {}
        let stand = try #require(s.rueckfrage).id
        s.beenden()
        #expect(s.rueckfrage?.id == stand && s.offenerDialog == .lernende && !s.beendetGleich,
                "⌘Q: die stehende Frage bleibt, das Blatt auch")
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
    func unsichtbareFrageSperrtNicht() throws {
        let ablage = try ordner("unsichtbar")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try speicher(ablage)
        s.rueckfrageSichtbar = { false }
        let vorhaben = try #require(s.planung?.eintraege.first { $0.termin == t }).id
        s.offenerDialog = .klassen
        s.fragen("Hinter dem Blatt", bestaetigung: "Ersetzen") {}
        s.zeigeVorhaben(vorhaben)
        #expect(s.rueckfrage == nil && s.offenerDialog == nil, "der Sprung räumt die unsichtbare Frage mit ab")
        s.fragen("Hinter dem Blatt", bestaetigung: "Ersetzen") {}
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
        let (s, _, _) = try speicher(ablage)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") {}
        let erste = try #require(s.rueckfrage).id
        var zweite = 0
        s.fragen("Zweite", bestaetigung: "Ja") { zweite += 1 }
        #expect(s.rueckfrage?.id == erste && s.wartendeRueckfragen.count == 1, "die sichtbare bleibt, die zweite wartet")
        s.rueckfrageBeantworten(false)
        #expect(s.rueckfrage == nil, "noch nicht — erst nach der Nachholfrist")
        try await abwarten("die zweite erscheint nach der Antwort") { s.rueckfrage?.text == "Zweite" }
        s.rueckfrageBeantworten(true)
        #expect(zweite == 1 && s.wartendeRueckfragen.isEmpty)
    }

    @Test("Eine nicht angezeigte Rückfrage wird ersetzt, nicht eingereiht (E317, Z14c3-01)")
    func unsichtbareWirdErsetzt() throws {
        let ablage = try ordner("ersetzt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        s.rueckfrageSichtbar = { false }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Zweite", bestaetigung: "Ja") {}
        #expect(s.rueckfrage?.text == "Zweite" && s.wartendeRueckfragen.isEmpty)
    }

    @Test("Schließen räumt auch die wartenden Fragen ab — nach dem Beenden oder einem Sprung erscheint keine mehr (E317)")
    func schliessenLeertWarteschlange() async throws {
        let ablage = try ordner("leert")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Zweite", bestaetigung: "Ja") {}
        s.alleDialogeSchliessen()
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.isEmpty)
        try await Task.sleep(for: .milliseconds(Int(Planungsspeicher.nachholfrist * 1000) + 300))  // E145: Uhr — Ausbleiben der wartenden Frage
        #expect(s.rueckfrage == nil, "keine wartende Frage kommt nach")
    }

    @Test("Bei sichtbarer Rückfrage tun ⌘Z und ⌘P/⇧⌘P im Sitzplan nichts (E317, E318)")
    func befehleGesperrt() throws {
        let ablage = try ordner("befehle")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try speicher(ablage)
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
        let (s, _, _) = try speicher(ablage)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        var namen = true
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(namenOffen: { namen }, namenVerwerfen: { namen = false }))
        var weiter = 0
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { weiter += 1 })
        #expect(gefragt)
        s.fragen("Wartet", bestaetigung: "Ja") {}
        #expect(s.wartendeRueckfragen.count == 1)
        s.rueckfrageBeantworten(true)
        try await abwarten("das Beenden geht weiter") { weiter == 1 }
        try await abwarten("danach erscheint die wartende") { s.rueckfrage?.text == "Wartet" }
    }

    @Test("Eine Frage aus der Handlung heraus wartet, bis das Alert-Blatt fort ist (Z14c4-02)")
    func folgeImHandlerWartet() async throws {
        let ablage = try ordner("handler")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        // Ein Alert hängt, solange eine Frage gesetzt ist — und während er nach der Antwort ausblendet.
        let blendetAus = Merker()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || blendetAus.an }
        s.fragen("Erste", bestaetigung: "Ja") { [weak s] in s?.fragen("Folge", bestaetigung: "Ja") {} }
        #expect(s.rueckfrage?.text == "Erste")
        blendetAus.an = true
        s.rueckfrageBeantworten(true)
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.count == 1, "das Alert hängt noch — die Folge wartet")
        blendetAus.an = false
        try await abwarten("danach erscheint sie") { s.rueckfrage?.text == "Folge" }
    }

    @Test("Zwei wartende Fragen erscheinen nacheinander (E317)")
    func zweiWartende() async throws {
        let ablage = try ordner("zwei")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Zweite", bestaetigung: "Ja") {}
        s.fragen("Dritte", bestaetigung: "Ja") {}
        #expect(s.rueckfrage?.text == "Erste" && s.wartendeRueckfragen.map(\.text) == ["Zweite", "Dritte"])
        s.rueckfrageBeantworten(false)
        try await abwarten("die zweite") { s.rueckfrage?.text == "Zweite" }
        s.rueckfrageBeantworten(false)
        try await abwarten("die dritte") { s.rueckfrage?.text == "Dritte" }
    }

    @Test("Eine Planung per Finder öffnen, während eine Rückfrage sichtbar steht: abgewiesen und gesagt (Z14c4-03)")
    func oeffnenWartetAufFrage() throws {
        let ablage = try ordner("oeffnen")
        let quelle = try ordner("oeffnen-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let (s, _, _) = try speicher(ablage)
        var fremd = try #require(s.planung)
        fremd.titel = "Fremd"
        fremd.erstellt = "2027-07-01T10:00:00.000Z"
        let datei = quelle.appending(component: "fremd.json")
        try Planungsdatei.schreiben(fremd).write(to: datei)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.fragen("Steht", bestaetigung: "Ja") {}
        let stand = try #require(s.rueckfrage).id
        let vorher = try #require(s.planung).erstellt
        s.importieren(von: datei)
        #expect(s.rueckfrage?.id == stand && s.wartendeRueckfragen.isEmpty && s.schuljahrwechsel == nil
                && s.offenerDialog == nil && s.planung?.erstellt == vorher
                && s.meldungen.last?.text == "„fremd.json“ wurde nicht geöffnet: Bitte zuerst die Rückfrage "
                    + "beantworten, dann die Datei erneut öffnen.", Comment(rawValue: s.meldungen.last?.text ?? "—"))
    }

    @Test("Auch der eigene Alert eines Dialogs sperrt: Beenden wartet, ⌘Z und der Sprung tun nichts darunter (Z14c4-10)")
    func eigenerAlertSperrt() throws {
        let ablage = try ordner("eigener")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try speicher(ablage)
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
        let (s, _, _) = try speicher(ablage)
        let blendetAus = Merker()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || blendetAus.an }
        var namen = true
        s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(namenOffen: { namen }, namenVerwerfen: { namen = false }))
        let gefragt = s.lernendenblattBeimBeendenFragen(dann: { [weak s] in s?.fragen("Folge", bestaetigung: "Ja") {} })
        #expect(gefragt)
        s.fragen("Wartet", bestaetigung: "Ja") {}
        blendetAus.an = true
        s.rueckfrageBeantworten(true)
        // Solange das Blatt ausblendet, wartet die Fortsetzung — und die Wartende hinter ihr (E319).
        try await Task.sleep(for: .milliseconds(Int(Planungsspeicher.nachholfrist * 1000) + 200))  // E145: Uhr — die Frist des Nachholens verstreichen lassen
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.map(\.text) == ["Wartet"] && s.ausstehendeFortsetzungen == 1,
                "noch nichts: das Alert hängt, die Fortsetzung steht aus")
        blendetAus.an = false
        try await abwarten("eine Frage erscheint") { s.rueckfrage != nil }
        #expect(s.rueckfrage?.text == "Folge", Comment(rawValue: s.rueckfrage?.text ?? "—"))
    }

    @Test("Solange eine Fortsetzung aussteht, holt die Warteschlange nichts nach — auch wenn das Alert schon fort ist (E319)")
    func wartendeWartetAufFortsetzung() async throws {
        let ablage = try ordner("zaehler")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        let blendetAus = Merker()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil || blendetAus.an }
        s.fragen("Erste", bestaetigung: "Ja") {}
        s.fragen("Wartet", bestaetigung: "Ja") {}
        #expect(s.rueckfrage?.text == "Erste" && s.wartendeRueckfragen.map(\.text) == ["Wartet"])
        // Abgelehnt, das Alert blendet aus; das Nachholen schaut nach `nachholfrist` (0,7 s) wieder.
        blendetAus.an = true
        s.rueckfrageBeantworten(false)
        // Bei 0,5 s ist das Alert fort, und eine Fortsetzung steht aus — sie kommt erst nach dem Nachhol-Takt
        // (Z14d2-02). Über dieselbe Hauptwarteschlange wie der Takt, damit die Reihenfolge hält (Z14d2-10).
        await withCheckedContinuation { (fertig: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak s] in  // E145: Uhr — vor den Nachhol-Takt bei 0,7 s
                blendetAus.an = false
                s?.nachDerAntwort { s?.fragen("Folge", bestaetigung: "Ja") {} }
                fertig.resume()
            }
        }
        try await abwarten("eine Frage erscheint") { s.rueckfrage != nil }
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
    }

    @Test("„Neue Planung“ ohne Verschlüsselung (E302): die Rückfrage sagt, dass das Anlegen danach neu beginnt")
    func neuePlanungOhneVerschluesselung() throws {
        let ablage = try ordner("neue-planung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.neuePlanungFragen(ort: .neuePlanung) {}
        let frage = try #require(s.rueckfrage)
        #expect(frage.text == "Die bisherige Planung „Schuljahr 2026/27“ wird nur mit eingeschalteter Verschlüsselung "
                + "archiviert — ohne sie ersetzt die neue Planung die bisherige, wie bisher. Mit dem Einrichten der "
                + "Verschlüsselung beginnt das Anlegen einer neuen Planung ohne Übernahme der bisherigen Eingaben.\n\n"
                + "Zuerst die Verschlüsselung einrichten oder ohne Archiv fortfahren?", Comment(rawValue: frage.text))
        s.rueckfrageBeantworten(false)
    }

    @Test("Person endgültig löschen (W2-05): die Rückfrage nennt die Vorhaben, die mit ihren Terminen gehen")
    func personLoeschenNenntVorhaben() throws {
        let ablage = try ordner("person")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, anna) = try speicher(ablage)
        s.personLoeschenFragen(anna, in: try #require(s.lernende.bestand)) { _ in }
        let frage = try #require(s.rueckfrage)
        #expect(frage.text.contains("\n\nBeim „Übernehmen“ geht auch 1 Vorhaben in der Planung."), Comment(rawValue: frage.text))
        s.rueckfrageBeantworten(false)
        let ben = try #require(s.lernende.bestand?.lernende.first { $0.id != anna }).id
        s.personLoeschenFragen(ben, in: try #require(s.lernende.bestand)) { _ in }
        #expect(s.rueckfrage?.text.contains("Vorhaben in der Planung") == false, "ohne Termin kein Satz")
        s.rueckfrageBeantworten(false)
    }

    @Test("Aufheben (E301): die Rückfrage nennt Rettungskopien, die keine überholten Stände sind, eigens")
    func aufhebenNenntArten() throws {
        let ablage = try ordner("aufheben")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
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
    func aufhebenEinzahl() throws {
        let ablage = try ordner("aufheben-einzahl")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        let art = "(unter einem anderen Schlüssel, beschädigt oder im Klartext abgelegt)"
        let klartext = ablage.appending(component: "lernende-unerwartet-a.json")
        try Data("{}".utf8).write(to: klartext)
        #expect(s.aufhebenRueckfrage.contains("Eine Rettungskopie der Lernendendaten wird dabei endgültig gelöscht — "
                                              + "Lernendendaten werden nie entsiegelt. Sie ist kein überholter Stand, sondern "
                                              + "eine Kopie, die sich nicht öffnen ließ \(art); sie kann die einzige Fassung "
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
}
