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
/// Seit v76 liest sie nach dem Aufwachen und auf Befehl abseits des
/// Hauptstrangs (R75-01); die Prüfungen warten auf das Ende ihrer Aufgabe.
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

    /// Die Kennungen der Meldungen, die gerade stehen. Eine Meldung verschwindet
    /// nach 2,8 s — gezählt wird darum an der Kennung und gleich nach dem Abruf,
    /// nie über mehrere Abrufe im Hintergrund hinweg (v76).
    private func kennungen(_ s: Planungsspeicher) -> Set<UUID> { Set(s.meldungen.map(\.id)) }

    /// Was seit `vorher` gemeldet wurde.
    private func neu(_ s: Planungsspeicher, seit vorher: Set<UUID>) -> [String] {
        s.meldungen.filter { !vorher.contains($0.id) }.map(\.text)
    }

    @Test("Nach dem Aufwachen: Ein neuer Stand wird übernommen und gemeldet — derselbe noch einmal ändert nichts")
    func nachDemAufwachen() async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])

        var vorher = kennungen(s)
        #expect(await s.statusNachAufwachen()?.value == .uebernommen)
        #expect(erledigt(s, "e-1"))
        #expect(neu(s, seit: vorher) == ["Aus der Web App übernommen: 1 Markierung."])

        vorher = kennungen(s)
        #expect(await s.statusNachAufwachen()?.value == .nichtsNeues)
        #expect(neu(s, seit: vorher).isEmpty, "derselbe Stand meldet nichts")
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
        let vorher = kennungen(s)
        #expect(await s.statusAbrufen()?.value == .uebernommen, "der Befehl liest — nur so kommt der zweite Stand")
        #expect(erledigt(s, "e-2"))
        #expect(neu(s, seit: vorher) == ["Aus der Web App übernommen: 1 Markierung."])
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
    func befehl() async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }

        var vorher = kennungen(s)
        #expect(await s.statusAbrufen()?.value == .nichtsNeues)
        #expect(neu(s, seit: vorher) == ["Von der Web App liegt nichts Neues vor."], "ohne Datei")

        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        vorher = kennungen(s)
        #expect(await s.statusAbrufen()?.value == .uebernommen)
        #expect(erledigt(s, "e-1"))
        #expect(neu(s, seit: vorher) == ["Aus der Web App übernommen: 1 Markierung."])

        vorher = kennungen(s)
        #expect(await s.statusAbrufen()?.value == .nichtsNeues)
        #expect(neu(s, seit: vorher) == ["Von der Web App liegt nichts Neues vor."], "derselbe Stand")

        s.autoexportOrdner = ""
        #expect(s.statusAbrufen() == nil, "ohne Zielordner: keine Aufgabe, gleich die Meldung")
        #expect(gemeldet(s, "Für den Stand der Web App ist kein Zielordner gewählt") == 1)
    }

    /// B61 (v75): Gewählt, aber nicht erreichbar — ein abgezogener
    /// Wechseldatenträger, ein Cloud-Ordner, der fehlt. Der Befehl sagte
    /// „nichts Neues“, weil das Lesen den Ordner wie eine fehlende Datei nahm.
    @Test("Zielordner gewählt, aber nicht erreichbar: Der Befehl nennt ihn — nach dem Aufwachen bleibt es still")
    func zielordnerNichtErreichbar() async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        try FileManager.default.removeItem(at: ziel)

        #expect(s.statusUebernehmen() == .zielordnerFehlt)
        var vorher = kennungen(s)
        #expect(await s.statusNachAufwachen()?.value == .zielordnerFehlt)
        #expect(neu(s, seit: vorher).isEmpty, "nach dem Aufwachen still — das Schreiben der Kopie meldet den Ordner")

        vorher = kennungen(s)
        #expect(await s.statusAbrufen()?.value == .zielordnerFehlt)
        #expect(neu(s, seit: vorher) == ["Der Zielordner ist gerade nicht erreichbar — der Stand der Web App wurde nicht gelesen."])
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

    /// B64 (v76): Hinter einem Dialog des Systems am Hauptfenster
    /// (`Dialogort.frei`, dort `runModal()` oder `run()`) läuft die
    /// Hauptschleife weiter — die Übernahme wartet trotzdem, bis er zu ist.
    /// Im Prüfziel geht kein Dialog auf; `frei` bekommt statt seiner, was
    /// während des Dialogs geschieht. Den echten Dialog hält `--statustest`.
    @Test("Ein Dialog des Systems lässt warten und holt beim Schließen des letzten einmal nach")
    func wartetHinterDemDialogDesSystems() async throws {
        let (s, ablage, ziel) = try speicher()
        let vorher = Dialogort.nachDemSchliessen
        Dialogort.nachDemSchliessen = { s.statusNachholenWennFrei() }
        defer {
            Dialogort.nachDemSchliessen = vorher
            aufraeumen(ablage, ziel)
        }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])

        #expect(!s.statusMussWarten)
        Dialogort.frei {
            #expect(s.statusMussWarten, "ein Dialog des Systems steht")
            s.statusNachAufwachen()
            #expect(s.statusVorgemerkt && !erledigt(s, "e-1"), "vorgemerkt, nichts übernommen")
            Dialogort.frei {
                #expect(Dialogort.freieDialoge == 2)
            }
            #expect(s.statusMussWarten, "der äußere Dialog steht noch")
        }
        #expect(Dialogort.freieDialoge == 0 && !s.statusMussWarten)
        try await abwarten("Übernahme nach dem Dialog des Systems") { erledigt(s, "e-1") }
        #expect(!s.statusVorgemerkt)
        #expect(gemeldet(s, "Aus der Web App übernommen") == 1)
    }

    /// Ein Wert, den ein anderer Faden setzt und die Prüfung liest.
    private final class Messwert: @unchecked Sendable {
        private let sperre = NSLock()
        private var wert: Double?
        func setzen(_ neu: Double) { sperre.withLock { wert = neu } }
        var gelesen: Double? { sperre.withLock { wert } }
    }

    /// R75-01 (v76): Nach dem Aufwachen und auf Befehl liest die App nicht auf
    /// dem Hauptstrang. Die Naht hält fest, auf welchem Faden das Lesen läuft —
    /// der Beweis am Faden selbst, ohne Frist. (Ein erster Anlauf wartete auf
    /// einen Block am Hauptstrang; im vollen Parallellauf maß er damit das
    /// Gedränge am Hauptakteur mit und wurde gelegentlich rot.)
    @Test("Nach dem Aufwachen und auf Befehl liest die App nicht auf dem Hauptstrang",
          arguments: ["Befehl", "Aufwachen"])
    func hauptstrangFrei(_ weg: String) async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        let aufDemHauptstrang = Messwert()
        var aufgabe: Task<Planungsspeicher.Statusuebernahme?, Never>?
        Statusnaht.$halten.withValue({ aufDemHauptstrang.setzen(pthread_main_np() != 0 ? 1 : 0) }) {
            aufgabe = weg == "Befehl" ? s.statusAbrufen() : s.statusNachAufwachen()
        }
        let vorher = kennungen(s)
        let ergebnis = await aufgabe?.value
        #expect(aufDemHauptstrang.gelesen == 0, "\(weg): Die Statusdatei wurde auf dem Hauptstrang gelesen")
        #expect(ergebnis == .some(.uebernommen) && erledigt(s, "e-1"))
        #expect(neu(s, seit: vorher) == ["Aus der Web App übernommen: 1 Markierung."])
    }

    /// Hält das Lesen an, bis die Prüfung es freigibt, und sagt, ob es hängt.
    private final class Lesetor: @unchecked Sendable {
        private let tor = DispatchSemaphore(value: 0)
        private let angekommen = Messwert()
        var haengt: Bool { angekommen.gelesen != nil }
        var halten: @Sendable () -> Void {
            { [self] in
                angekommen.setzen(1)
                // Großzügig: Freigegeben wird vom Hauptakteur, und der ist im vollen
                // Lauf zeitweise belegt (v76).
                _ = tor.wait(timeout: .now() + 120)
            }
        }
        func oeffnen() { tor.signal() }
    }

    /// R75-01 (v76): Was im Hintergrund gelesen wurde, gilt nur für die Lage,
    /// in der es angefragt wurde. Wechseln während des Lesens die Planung, der
    /// Zielordner oder der Schlüssel, wird es verworfen — ohne Meldung; jeder
    /// dieser Wechsel liest die Datei auf seinem eigenen Weg.
    @Test("Wechselt während des Lesens Planung, Zielordner oder Schlüssel, wird das Ergebnis verworfen",
          arguments: ["Planung", "Zielordner", "Schlüssel"])
    func veraltetesErgebnisVerworfen(_ was: String) async throws {
        let (s, ablage, ziel) = try speicher()
        let anderer = try ordner("abruf-anderer")
        defer { aufraeumen(ablage, ziel, anderer) }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        let tor = Lesetor()
        var aufgabe: Task<Planungsspeicher.Statusuebernahme?, Never>?
        Statusnaht.$halten.withValue(tor.halten) { aufgabe = s.statusAbrufen() }
        try await abwarten("das Lesen hängt (\(was))") { tor.haengt }
        switch was {
        case "Planung":
            var andere = try planung()
            andere.erstellt = "2000-01-01T00:00:00.000Z"
            s.planung = andere
        case "Zielordner":
            s.autoexportOrdner = anderer.path
        default:
            s.sitzung = .verschluesselt(s.planung, Tresor.neu())
        }
        tor.oeffnen()
        #expect(await aufgabe?.value == .some(nil), "\(was): verworfen")
        #expect(!erledigt(s, "e-1"), "\(was): nichts übernommen")
        // Nur die Sätze der Übernahme — ein neuer Schlüssel kann eine Meldung der Sicherung bringen.
        #expect(gemeldet(s, "Web App") == 0, "\(was): verworfen, ohne Meldung der Übernahme")
    }

    /// R75-01 (v76): Öffnet sich während des Lesens ein Blatt, wird nicht
    /// dahinter übernommen, sondern vorgemerkt — und beim Schließen einmal nachgeholt.
    @Test("Öffnet sich während des Lesens ein Blatt, wird vorgemerkt und nach dem Schließen einmal übernommen")
    func blattWaehrendDesLesens() async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        let tor = Lesetor()
        var aufgabe: Task<Planungsspeicher.Statusuebernahme?, Never>?
        Statusnaht.$halten.withValue(tor.halten) { aufgabe = s.statusAbrufen() }
        try await abwarten("das Lesen hängt") { tor.haengt }
        s.offenerDialog = .hilfe
        tor.oeffnen()
        #expect(await aufgabe?.value == .some(nil), "vorgemerkt statt übernommen")
        #expect(s.statusVorgemerkt && !erledigt(s, "e-1"), "vorgemerkt, nichts übernommen")
        s.offenerDialog = nil
        try await abwarten("nach dem Schließen übernommen") { erledigt(s, "e-1") }
        #expect(!s.statusVorgemerkt)
        #expect(gemeldet(s, "Aus der Web App übernommen") == 1)
    }

    /// R75-01 (v76): Eine jüngere Anfrage überholt eine ältere, die noch
    /// liest; die ältere antwortet nicht mehr — übernommen und gemeldet wird einmal.
    @Test("Eine zweite Anfrage überholt die erste — übernommen und gemeldet wird einmal")
    func zweiteAnfrageUeberholt() async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        try statusSchreiben(ziel, ["e-1": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        let tor = Lesetor()
        var erste: Task<Planungsspeicher.Statusuebernahme?, Never>?
        Statusnaht.$halten.withValue(tor.halten) { erste = s.statusAbrufen() }
        try await abwarten("das erste Lesen hängt") { tor.haengt }
        var vorher = kennungen(s)
        #expect(await s.statusAbrufen()?.value == .uebernommen)
        #expect(erledigt(s, "e-1"), "die zweite Anfrage hat übernommen")
        #expect(neu(s, seit: vorher) == ["Aus der Web App übernommen: 1 Markierung."])
        vorher = kennungen(s)
        tor.oeffnen()
        #expect(await erste?.value == .some(nil), "die überholte Anfrage wird verworfen")
        #expect(neu(s, seit: vorher).isEmpty, "die überholte Anfrage antwortet nicht")
    }

    /// R75-01 (v76): Die größte zulässige Datei (knapp 8 MiB, 380 Einträge mit
    /// je 20 000 Zeichen) wird im Hintergrund vollständig übernommen.
    @Test("Die größte zulässige Statusdatei wird im Hintergrund vollständig übernommen")
    func groessteDatei() async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        let anzahl = 380
        let kurs = try #require(s.planung?.klassen.first?.id)
        s.planung?.eintraege = (0..<anzahl).map {
            Vorhaben(id: "g-\($0)", klasseId: kurs, woche: 1 + $0 % 4, titel: "V\($0)",
                     text: "", erledigt: false, materialien: [], links: [])
        }
        let satz = "Die Klasse hat das Thema gut bearbeitet. "
        let kommentar = String(String(repeating: satz, count: 20_000 / satz.count + 1).prefix(20_000))
        let stempel = Zeitrechnung.jetztAlsZeitstempel()
        var eintraege: [String: Statusstand.Eintrag] = [:]
        for i in 0..<anzahl { eintraege["g-\(i)"] = .init(erledigt: true, kommentar: kommentar, geaendert: stempel) }
        try statusSchreiben(ziel, eintraege)
        let groesse = try #require(try FileManager.default.attributesOfItem(
            atPath: ziel.appending(component: Statusdatei.name).path)[.size] as? Int)
        try #require(groesse > 7 * 1024 * 1024 && groesse <= Statusdatei.hoechstgroesse, "Größe \(groesse)")

        let vorher = kennungen(s)
        #expect(await s.statusAbrufen()?.value == .uebernommen)
        #expect(s.planung?.eintraege.allSatisfy { $0.erledigt && $0.kommentar == kommentar } == true)
        #expect(neu(s, seit: vorher) == ["Aus der Web App übernommen: \(anzahl) Markierungen und \(anzahl) Kommentare."])
    }

    /// E84, bestätigt als E217: Was von außen kommt, ist nicht widerrufbar —
    /// der Verlauf beginnt neu, und die Meldung sagt es, wenn es etwas zu
    /// widerrufen gab.
    @Test("Kommen Haken oder Kommentare, beginnt der Verlauf neu — die Meldung sagt es, wenn es etwas zu widerrufen gab")
    func verlaufBeginntNeu() async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        s.aendern(Schrittname.titelAendern) { $0.titel = "Eigene Änderung" }
        #expect(s.kannWiderrufen)

        try statusSchreiben(ziel, ["e-1": .init(erledigt: false, kommentar: "lief gut", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        var vorher = kennungen(s)
        #expect(await s.statusNachAufwachen()?.value == .uebernommen)
        #expect(!s.kannWiderrufen)
        #expect(neu(s, seit: vorher) == ["Aus der Web App übernommen: 1 Kommentar. Widerrufen beginnt hier neu."])

        // Ohne Schritte davor kein Nachsatz.
        try statusSchreiben(ziel, ["e-2": .init(erledigt: true, kommentar: "", geaendert: Zeitrechnung.jetztAlsZeitstempel())])
        vorher = kennungen(s)
        #expect(await s.statusAbrufen()?.value == .uebernommen)
        #expect(neu(s, seit: vorher) == ["Aus der Web App übernommen: 1 Markierung."])
    }

    /// B59 (v75): Ein Stand, der nur Stempel bringt — auf dem Gerät ein Haken
    /// gesetzt und wieder entfernt —, änderte bis 1.9.3 die Planung und leerte
    /// damit still den Verlauf. Er ändert nichts, was man sieht: Der Verlauf
    /// bleibt (E217), und ein Widerrufen senkt den Stempel nicht (E120).
    @Test("Nur ein neuer Stempel: Der Verlauf bleibt, und Widerrufen senkt den Stempel nicht")
    func nurStempel() async throws {
        let (s, ablage, ziel) = try speicher()
        defer { aufraeumen(ablage, ziel) }
        s.aendern(Schrittname.titelAendern) { $0.titel = "Eigene Änderung" }
        let stempel = Zeitrechnung.jetztAlsZeitstempel()
        try statusSchreiben(ziel, ["e-1": .init(erledigt: false, kommentar: "", geaendert: stempel)])
        let vorher = kennungen(s)

        #expect(await s.statusNachAufwachen()?.value == .nichtsNeues)
        #expect(s.planung?.eintraege.first { $0.id == "e-1" }?.statusGeaendert == stempel, "der Stempel ist übernommen")
        #expect(s.kannWiderrufen, "nichts Sichtbares kam — der Verlauf bleibt")
        #expect(neu(s, seit: vorher).isEmpty)

        s.widerrufen()
        #expect(s.planung?.titel == "Abruf")
        #expect(s.planung?.eintraege.first { $0.id == "e-1" }?.statusGeaendert == stempel,
                "ein Widerrufen senkt keinen Stempel (E120)")
    }
}
