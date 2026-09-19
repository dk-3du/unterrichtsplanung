// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import Testing

@testable import Unterrichtsplanung

/// Der Stand der Web App bei geöffneter App (E216 d, E217 a, v75): einmal nach
/// dem Aufwachen des Macs aus dem Ruhezustand und jederzeit über „Stand der Web
/// App abrufen“. Ein offenes Blatt lässt die Übernahme warten, bis es zu ist;
/// der Verlauf beginnt nur neu, wenn Haken oder Kommentare kommen — und die
/// Meldung sagt es. Die 15 Sekunden nach dem Aufwachen hält der Prüfstand
/// `--statustest` am Paket; hier wird die Übernahme direkt gerufen (E145).
@Suite("Stand der Web App: nach dem Aufwachen und auf Befehl")
@MainActor
struct StatusAbrufPruefungen {

    /// `autoexportOrdner` schreibt in die Einstellungen — nur mit eigenem Ablageort.
    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Abruf", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Bits",
                                text: "", erledigt: false, materialien: [], links: []),
                       Vorhaben(id: "e-2", klasseId: p.klassen[0].id, woche: 2, titel: "Bytes",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    /// Ein Speicher mit Planung und Zielordner — und die Ordner zum Aufräumen.
    private func speicher() throws -> (Planungsspeicher, URL, URL) {
        let ablageOrdner = try ordner("abruf-ablage")
        let ziel = try ordner("abruf-ziel")
        let s = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        s.planung = try planung()
        s.autoexportOrdner = ziel.path
        return (s, ablageOrdner, ziel)
    }

    private func aufraeumen(_ ordner: URL...) {
        for o in ordner { try? FileManager.default.removeItem(at: o) }
    }

    /// Die Statusdatei, wie die Web App sie ablegt — jeder Eintrag mit eigenem Stempel.
    private func statusSchreiben(_ ziel: URL, _ eintraege: [String: Statusstand.Eintrag]) throws {
        let stand = Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(), planungstitel: "Abruf",
                                eintraege: eintraege)
        try Statusdatei.schreiben(stand).write(to: ziel.appending(component: Statusdatei.name), options: [.atomic])
    }

    private func erledigt(_ s: Planungsspeicher, _ id: String) -> Bool {
        s.planung?.eintraege.first { $0.id == id }?.erledigt == true
    }

    private func gemeldet(_ s: Planungsspeicher, _ teil: String) -> Int {
        s.meldungen.count { $0.text.contains(teil) }
    }

    @Test("Nach dem Aufwachen: Ein neuer Stand wird übernommen und gemeldet — derselbe noch einmal ändert nichts")
    func nachDemAufwachen() throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])

        s.statusNachAufwachen()
        #expect(erledigt(s, "e-1"))
        #expect(gemeldet(s, "Aus der Web App übernommen: 1 Markierung.") == 1)

        let meldungen = s.meldungen.count
        s.statusNachAufwachen()
        #expect(s.meldungen.count == meldungen, "derselbe Stand meldet nichts")
    }

    /// Hinter einem offenen Blatt soll sich die Planung nicht ändern (E216 d).
    @Test("Ist ein Blatt, ein Dialog oder eine Rückfrage offen, wartet die Übernahme — und kommt einmal, wenn es zu ist",
          arguments: ["Dialog", "Vorhaben-Blatt", "Rückfrage", "Farbwahl"])
    func wartetAufDasBlatt(_ was: String) async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        let kurs = try #require(s.planung?.klassen.first?.id)
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "vom Gerät", geaendert: Zeitrechnung.jetztAlsZeitstempel())])

        func oeffnen() {
            switch was {
            case "Dialog": s.offenerDialog = .hilfe
            case "Vorhaben-Blatt": s.vorhabenDialog = VorhabenEntwurf(klasseId: kurs, woche: 0)
            case "Rückfrage": s.rueckfrage = Rueckfrage(text: "?", bestaetigung: "Ja", handlung: {})
            default: s.farbwahlFuer = .kurs(kurs)
            }
        }
        func schliessen() {
            switch was {
            case "Dialog": s.offenerDialog = nil
            case "Vorhaben-Blatt": s.vorhabenDialog = nil
            case "Rückfrage": s.rueckfrage = nil
            default: s.farbwahlFuer = nil
            }
        }

        oeffnen()
        s.statusNachAufwachen()
        #expect(!erledigt(s, "e-1"), "hinter dem offenen \(was) ändert sich nichts")
        schliessen()
        try await abwarten("Übernahme nach dem Schließen (\(was))") { erledigt(s, "e-1") }
        #expect(gemeldet(s, "Aus der Web App übernommen") == 1)

        // Einmal nachgeholt ist erledigt: Ein weiteres Blatt holt nichts mehr nach.
        try statusSchreiben(ziel, ["e-2": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        oeffnen()
        schliessen()
        s.statusAbrufen()  // der Befehl liest — nur so kommt der zweite Stand
        #expect(erledigt(s, "e-2"))
        #expect(gemeldet(s, "Aus der Web App übernommen") == 2)
    }

    @Test("Ohne Planung oder ohne Zielordner geschieht nach dem Aufwachen nichts")
    func ohneZielordner() throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        s.autoexportOrdner = ""
        let meldungen = s.meldungen.count
        s.statusNachAufwachen()
        #expect(!erledigt(s, "e-1"))
        #expect(s.meldungen.count == meldungen)
    }

    @Test("Der Befehl liest sofort — und sagt, wenn nichts Neues vorliegt oder kein Zielordner gewählt ist")
    func befehl() throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }

        s.statusAbrufen()
        #expect(gemeldet(s, "Von der Web App liegt nichts Neues vor.") == 1, "ohne Datei")

        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        s.statusAbrufen()
        #expect(erledigt(s, "e-1"))
        #expect(gemeldet(s, "Aus der Web App übernommen: 1 Markierung.") == 1)

        s.statusAbrufen()
        #expect(gemeldet(s, "Von der Web App liegt nichts Neues vor.") == 2, "derselbe Stand")

        s.autoexportOrdner = ""
        s.statusAbrufen()
        #expect(gemeldet(s, "Für den Stand der Web App ist kein Zielordner gewählt") == 1)
    }

    /// B61 (v75): Gewählt, aber nicht erreichbar — ein abgezogener
    /// Wechseldatenträger, ein Cloud-Ordner, der fehlt. Der Befehl sagte
    /// „nichts Neues“, weil das Lesen den Ordner wie eine fehlende Datei nahm.
    @Test("Zielordner gewählt, aber nicht erreichbar: Der Befehl nennt ihn — nach dem Aufwachen bleibt es still")
    func zielordnerNichtErreichbar() throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        try FileManager.default.removeItem(at: ziel)

        #expect(s.statusUebernehmen() == .zielordnerFehlt)
        let meldungen = s.meldungen.count
        s.statusNachAufwachen()
        #expect(s.meldungen.count == meldungen, "nach dem Aufwachen still — das Schreiben der Kopie meldet den Ordner")

        s.statusAbrufen()
        #expect(gemeldet(s, "Der Zielordner ist gerade nicht erreichbar — der Stand der Web App wurde nicht gelesen.") == 1)
        #expect(gemeldet(s, "nichts Neues") == 0)
    }

    /// Liest, was `StatusAbrufBefehl` liest, und sagt, ob eine Handlung es
    /// ändert — so erfährt SwiftUI, dass der Eintrag im Menü nachzuführen ist.
    private func loestAus(_ s: Planungsspeicher, _ handlung: () async throws -> Void) async rethrows -> Bool {
        final class Schalter: @unchecked Sendable { var ausgeloest = false }
        let schalter = Schalter()
        withObservationTracking {
            _ = s.statusAbrufAngeboten
        } onChange: {
            schalter.ausgeloest = true
        }
        try await handlung()
        return schalter.ausgeloest
    }

    /// E223, E224 (v75): Der Eintrag „Stand der Web App abrufen“ ist grau ohne
    /// Zielordner und ohne geöffnete Planung. Er folgt beidem ohne Neustart —
    /// und nichts anderem: Hinge er an jeder Bearbeitung oder an einem Blatt,
    /// baute SwiftUI das Menü laufend neu (N04, v49: ⌘⏎ im Blatt ging verloren).
    @Test("Im Menü angeboten nur mit Planung und Zielordner — nachgeführt bei beidem, bei nichts sonst")
    func imMenueAngeboten() async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        #expect(s.statusAbrufAngeboten, "Planung und Zielordner: angeboten")

        #expect(await loestAus(s) { s.aendern(Schrittname.titelAendern) { $0.titel = "Anders" } } == false,
                "eine Bearbeitung führt den Eintrag nicht nach")
        #expect(await loestAus(s) {
            s.offenerDialog = .hilfe
            s.offenerDialog = nil
            s.vorhabenDialog = nil
            s.rueckfrage = nil
        } == false, "ein Blatt führt den Eintrag nicht nach")

        #expect(await loestAus(s) { s.autoexportOrdner = "" })
        #expect(!s.statusAbrufAngeboten, "ohne Zielordner: grau")
        #expect(await loestAus(s) { s.autoexportOrdner = ziel.path })
        #expect(s.statusAbrufAngeboten)

        let offen = s.planung
        #expect(await loestAus(s) { s.planung = nil })
        #expect(!s.statusAbrufAngeboten, "ohne Planung: grau, auch mit Zielordner (E224)")
        #expect(await loestAus(s) { s.planung = offen })
        #expect(s.statusAbrufAngeboten)
    }

    @Test("Versiegelte Ablage: gesperrt nach dem Start grau, nach dem Entsperren angeboten")
    func imMenueVersiegelt() async throws {
        let ablageOrdner = try ordner("abruf-ablage")
        let ziel = try ordner("abruf-ziel")
        defer { aufraeumen(ablageOrdner, ziel) }
        let passphrase = "Ein Satz, den man behält"
        let erster = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        erster.planung = try planung()
        erster.autoexportZielSetzen(ziel.path)
        _ = try erster.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(erster.verschluesselungEinschalten().lesezeichen == .erledigt)

        // Neuer Prozessstart nachgestellt: ein zweiter Speicher an derselben Ablage.
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        zweiter.nachwahlProbe = true
        zweiter.starten()
        #expect(zweiter.verschluesselungsstand == .gesperrt)
        #expect(!zweiter.statusAbrufAngeboten, "gesperrt: grau")
        #expect(await loestAus(zweiter) { await zweiter.entsperren(passphrase: passphrase) })
        #expect(zweiter.statusAbrufAngeboten, "entsperrt: angeboten")
    }

    /// Eine Datei unter fremdem Schlüssel, geöffnet: Das Blatt zum Entsperren steht.
    private func fremdeDateiOeffnen(_ s: Planungsspeicher) throws -> URL {
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        let datei = URL.temporaryDirectory.appending(component: "abruf-fremde-\(UUID().uuidString).json")
        var p = try planung()
        p.titel = "Von draußen"
        try fremder.versiegeln(try Planungsdatei.schreiben(p), inhalt: .planung, ziel: .export).write(to: datei)
        s.importieren(von: datei)
        return datei
    }

    /// B62 (v75): Jede Bedingung von `statusMussWarten`, auf ihrem echten Weg
    /// geöffnet und geschlossen. Das Entsperren einer fremden Datei endete mit
    /// dem Blatt zuerst und der Datei danach — die Übernahme wartete dann auf
    /// die nächste eigene Änderung und nahm deren Widerrufen mit.
    @Test("Jede Bedingung, die warten lässt, holt beim Ende einmal nach — auf ihrem echten Weg",
          arguments: ["fremde Datei, abgebrochen", "fremde Datei, entsperrt", "Schlüsselarbeit", "nächster Dialog"])
    func wartetAufJedeBedingung(_ was: String) async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        let fremd = was.hasPrefix("fremde Datei")
        if fremd { try s.pruefverschluesselung() }
        let stempel = Zeitrechnung.jetztAlsZeitstempel()
        let stand = Statusstand(gespeichert: stempel, planungstitel: "Abruf",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "", geaendert: stempel)])
        var daten = try Statusdatei.schreiben(stand)
        if let tresor = s.tresor { daten = try tresor.versiegeln(daten, inhalt: .status, ziel: .kopie) }
        try daten.write(to: ziel.appending(component: Statusdatei.name), options: [.atomic])

        var aufgabe: Task<String?, any Error>?
        var datei: URL?
        defer { if let datei { try? FileManager.default.removeItem(at: datei) } }
        switch was {
        case "Schlüsselarbeit":
            aufgabe = Task { @MainActor in try await s.verschluesselungVorbereitenAsynchron(passphrase: "Ein Satz, den man behält") }
            try await abwarten("Beginn der Schlüsselarbeit") { s.schluesselarbeitLaeuft }
        case "nächster Dialog":
            s.dialogOeffnen(.hilfe)
            s.dialogOeffnen(.einstellungen)
            try #require(s.offenerDialog == nil && s.naechsterDialog == .einstellungen)
        default:
            datei = try fremdeDateiOeffnen(s)
            try #require(s.entsperrungOffen && s.offenerDialog == .entsperren)
        }
        #expect(s.statusMussWarten)

        s.statusNachAufwachen()
        #expect(s.statusVorgemerkt && !erledigt(s, "e-1"), "\(was): vorgemerkt, nichts übernommen")

        switch was {
        case "Schlüsselarbeit":
            _ = try await aufgabe?.value
        case "nächster Dialog":
            s.naechstenDialogOeffnen()
            #expect(s.offenerDialog == .einstellungen)
            s.offenerDialog = nil
        case "fremde Datei, abgebrochen":
            s.entsperrungAbbrechen()
        default:
            await s.entsperren(passphrase: "Fremde Passphrase 2026")
            s.rueckfrageBeantworten(true)
        }
        #expect(!s.statusMussWarten)
        // Ohne eigene Änderung: Die Übernahme kommt mit dem Ende, nicht mit der nächsten Änderung.
        try await abwarten("Übernahme nach dem Ende (\(was))") { erledigt(s, "e-1") }
        #expect(!s.statusVorgemerkt)
        #expect(gemeldet(s, "Aus der Web App übernommen") == 1)
    }

    /// E84, bestätigt als E217: Was von außen kommt, ist nicht widerrufbar —
    /// der Verlauf beginnt neu, und die Meldung sagt es, wenn es etwas zu
    /// widerrufen gab.
    @Test("Kommen Haken oder Kommentare, beginnt der Verlauf neu — die Meldung sagt es, wenn es etwas zu widerrufen gab")
    func verlaufBeginntNeu() throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        s.aendern(Schrittname.titelAendern) { $0.titel = "Eigene Änderung" }
        #expect(s.kannWiderrufen)

        try statusSchreiben(ziel, ["e-1": .init(erledigt: false, kommentar: "lief gut", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        s.statusNachAufwachen()
        #expect(!s.kannWiderrufen)
        #expect(gemeldet(s, "Aus der Web App übernommen: 1 Kommentar. Widerrufen beginnt hier neu.") == 1)

        // Ohne Schritte davor kein Nachsatz.
        try statusSchreiben(ziel, ["e-2": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        s.statusAbrufen()
        #expect(gemeldet(s, "Aus der Web App übernommen: 1 Markierung.") == 1)
        #expect(gemeldet(s, "Widerrufen beginnt hier neu.") == 1)
    }

    /// B59 (v75): Ein Stand, der nur Stempel bringt — auf dem Gerät ein Haken
    /// gesetzt und wieder entfernt —, änderte bis 1.9.3 die Planung und leerte
    /// damit still den Verlauf. Er ändert nichts, was man sieht: Der Verlauf
    /// bleibt (E217), und ein Widerrufen senkt den Stempel nicht (E120).
    @Test("Nur ein neuer Stempel: Der Verlauf bleibt, und Widerrufen senkt den Stempel nicht")
    func nurStempel() throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        s.aendern(Schrittname.titelAendern) { $0.titel = "Eigene Änderung" }
        let stempel = Zeitrechnung.jetztAlsZeitstempel()
        try statusSchreiben(ziel, ["e-1": .init(erledigt: false, kommentar: "", geaendert: stempel)])
        let meldungen = s.meldungen.count

        s.statusNachAufwachen()
        #expect(s.planung?.eintraege.first { $0.id == "e-1" }?.statusGeaendert == stempel, "der Stempel ist übernommen")
        #expect(s.kannWiderrufen, "nichts Sichtbares kam — der Verlauf bleibt")
        #expect(s.meldungen.count == meldungen)

        s.widerrufen()
        #expect(s.planung?.titel == "Abruf")
        #expect(s.planung?.eintraege.first { $0.id == "e-1" }?.statusGeaendert == stempel,
                "ein Widerrufen senkt keinen Stempel (E120)")
    }
}
