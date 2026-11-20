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

// ── Die Arbeit der Lernendendaten auf dem Hauptstrang (F-02, v89) ─────────
// Die Prüfmarke (`Hauptstrangzaehler`) zählt Lesen, Zurücklesen und Bauen von
// Jahresdatei und Archiv, wenn es auf dem Hauptstrang läuft — ohne Uhr, ohne
// Schwelle in Millisekunden. Gezählt wird der Unterschied vor und nach einem
// Handgriff; was die Prüfung danach selbst liest, zählt nicht mit.
// Eng (E949 c): die Lesungen des Archivs bei einer bestätigten Löschung und
// vor dem Aufheben; wo ein Lesen abseits nicht trägt, liest die Löschung selbst,
// gleichlaufend wie bisher (Rückfälle, eigene Prüfungen). Der Jahreswechsel
// (E953 b) und das Beenden bleiben gleichlaufend — die Grenzen, je eine Prüfung.

@Suite("Lernendendaten abseits des Hauptstrangs: die Prüfmarke zählt null — an den Grenzen und in den Rückfällen eins (F-02)")
@MainActor
struct HauptstrangPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "hauptstrang-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// Eingeschaltet, mit einem Archiv aus einem Schuljahr (`j-1`) und den drei Personen des Prüfentwurfs; das Archiv
    /// steht im Blatt, dort hängt die Frage (E418) — wie in den Prüfungen zu B94.
    private func speicher(_ ort: URL) async throws -> (Planungsspeicher, Archivbestand) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                                 basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let vorjahr = Planung.leer(titel: "Prüfvektor 2025/26", start: try #require(Tag(iso: "2025-08-04")), wochen: 4,
                                   basis: "", klassen: [], fachfarben: [:])
        let archiv = Archivbestand(geaendert: "", jahre: [
            Archivjahr(id: "j-1", schuljahr: "2025/26", archiviert: RuecknahmeLernendenPruefungen.stempel,
                       planung: vorjahr, lernende: RuecknahmeLernendenPruefungen.entwurf()),
        ])
        #expect(s.archivSchreiben(archiv) == nil)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.offenerDialog = .lernende
        return (s, archiv)
    }

    /// Die Personen im Archiv, wie es liegt — ein unlesbares ist selbst ein Befund.
    private func personenImArchiv(_ s: Planungsspeicher) -> [String]? {
        guard case .gelesen(let archiv, _, _) = s.lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) else {
            Issue.record("das Archiv ist nicht lesbar")
            return nil
        }
        return archiv.jahre.flatMap { $0.lernende?.lernende.map(\.id) ?? [] }
    }

    // ── Eng: die Lesungen des Archivs ─────────────────────────────────────

    @Test("Eine bestätigte Löschung im Archiv liest das Archiv abseits des Hauptstrangs (F-02, eng)")
    func loeschungLiestAbseits() async throws {
        let ort = try ordner("loeschung")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var geschrieben = 0
        let m = s.lernende.hauptstrang
        let vorher = m.zahl(.archiv, .lesen), gebautVorher = m.zahl(.archiv, .bauen)
        let zurueckVorher = m.zahl(.archiv, .zuruecklesen)
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let gelaufen = await uhr.vorruecken(bis: { geschrieben == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "die Löschung ist geschrieben")
        let zahl = m.zahl(.archiv, .lesen) - vorher
        let gebaut = m.zahl(.archiv, .bauen) - gebautVorher, zurueck = m.zahl(.archiv, .zuruecklesen) - zurueckVorher
        #expect(zahl == 0, Comment(rawValue: "Lesungen des Archivs auf dem Hauptstrang: \(zahl)"))
        #expect(gebaut == 1 && zurueck == 1,
                Comment(rawValue: "geschrieben wie bisher, auf dem Hauptstrang (E949 c): gebaut \(gebaut), zurückgelesen \(zurueck)"))
        #expect(personenImArchiv(s) == ["l-2", "l-3"], "die Löschung gilt")
    }

    @Test("Die Frage vor dem Aufheben liest das Archiv abseits des Hauptstrangs (F-02, eng)")
    func aufhebenLiestAbseits() async throws {
        let ort = try ordner("aufheben")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, _) = try await speicher(ort)
        let vorher = s.lernende.hauptstrang.zahl(.archiv, .lesen)
        let sperre = await s.lernendenAufhebenSperrePruefen()
        let zahl = s.lernende.hauptstrang.zahl(.archiv, .lesen) - vorher
        #expect(sperre?.contains("Archiv der Lernendenverwaltung ist nicht leer") == true, Comment(rawValue: sperre ?? "—"))
        #expect(zahl == 0, Comment(rawValue: "Lesungen des Archivs auf dem Hauptstrang: \(zahl)"))
    }

    // ── Die Frage vor dem Aufheben: alle Zweige (E956, E965) ─────────────────

    @Test("Die Frage vor dem Aufheben kommt nach dem Prüfen — der Knopf wird wieder frei (E956, E965)")
    func aufhebenFragtNachDemPruefen() async throws {
        let ort = try ordner("aufheben-fragt")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, _) = try await speicher(ort)
        s.offenerDialog = .verschluesselung
        var geprueft = false
        var beimLesen: Bool?
        s.lernende.nachDemAbseitsLesen = { beimLesen = geprueft }
        await s.aufhebenFragenAnstossen(gilt: { true }, geprueft: { geprueft = true }) {}.value
        #expect(beimLesen == false, "während des Lesens bleibt der Knopf grau (E956)")
        #expect(geprueft, "danach wird er wieder frei")
        #expect(s.rueckfrage?.text.contains("Archiv der Lernendenverwaltung ist nicht leer") == true,
                Comment(rawValue: s.rueckfrage?.text ?? "keine Frage"))
    }

    @Test("Auf einem anderen Schritt oder nach dem Schließen entfällt die Frage vor dem Aufheben (E956, E965)")
    func aufhebenOhneFrageNachSchrittwechsel() async throws {
        let ort = try ordner("aufheben-schritt")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, _) = try await speicher(ort)
        s.offenerDialog = .verschluesselung
        var geprueft = 0
        await s.aufhebenFragenAnstossen(gilt: { false }, geprueft: { geprueft += 1 }) {}.value
        #expect(s.rueckfrage == nil, "während des Lesens auf „Passphrase ändern …“: keine Frage")
        s.offenerDialog = nil
        let toene = s.systemtoene
        await s.aufhebenFragenAnstossen(gilt: { true }, geprueft: { geprueft += 1 }) {}.value
        // Ohne die Prüfung „Blatt steht“ fiele eine Frage für das geschlossene Blatt fort — mit Ton und Hinweis.
        #expect(s.rueckfrage == nil && s.systemtoene == toene, "das Blatt ist zu: keine Frage, kein Ton")
        #expect(geprueft == 2, "der Knopf wird jedes Mal wieder frei")
    }

    @Test("Ist das Archiv leer, fragt das Aufheben mit „Aufheben“ und hebt auf, wenn das Alert fort ist (E956, E965, E431)")
    func aufhebenFragtUndHebtAuf() async throws {
        let ort = try ordner("aufheben-leer")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, _) = try await speicher(ort)
        #expect(s.archivSchreiben(Archivbestand(geaendert: "", jahre: [])) == nil)
        s.offenerDialog = .verschluesselung
        var aufgehoben = 0
        await s.aufhebenFragenAnstossen(gilt: { true }) { aufgehoben += 1 }.value
        #expect(s.rueckfrage?.bestaetigung == "Aufheben" && s.rueckfrage?.gefahr == true,
                Comment(rawValue: s.rueckfrage?.text ?? "keine Frage"))
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        // Das Alert blendet noch aus — ohne `nachDemSchliessen` liefe das Aufheben schon im Klick (E431).
        let haengt = Merker()
        haengt.an = true
        s.rueckfrageSichtbar = { haengt.an }
        s.rueckfrageBeantworten(true)
        #expect(aufgehoben == 0 && s.verschluesselt, "im Klick noch nicht — erst, wenn das Alert fort ist")
        haengt.an = false
        let gelaufen = await uhr.vorruecken(bis: { aufgehoben == 1 }, hoechstens: .seconds(1))
        #expect(gelaufen && !s.verschluesselt, "aufgehoben, danach schließt das Blatt (`aufgehoben`)")
    }

    @Test("Bricht das Schließen des Blatts die Aufgabe ab, entfällt die Frage vor dem Aufheben (E956, E965)")
    func aufhebenOhneFrageNachAbbruch() async throws {
        let ort = try ordner("aufheben-abbruch")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, _) = try await speicher(ort)
        s.offenerDialog = .verschluesselung
        let aufgabe = s.aufhebenFragenAnstossen(gilt: { true }) {}
        aufgabe.cancel()
        await aufgabe.value
        #expect(s.rueckfrage == nil, "abgebrochen: keine Frage")
    }

    // ── Eng: die Rückfälle — gleichlaufend, wo ein Lesen abseits nicht trägt ──

    @Test("Ändert sich das Archiv, während eine Löschung es abseits liest, liest sie neu — keine Änderung geht verloren (F-02, Z-AS2a-02)")
    func loeschungNachAenderung() async throws {
        let ort = try ordner("loeschung-geaendert")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        // Gleich nach dem Lesen abseits schreibt ein anderer: „l-3“ geht — mit Befund, damit er selbst nicht liest.
        s.lernende.nachDemAbseitsLesen = { [weak s] in
            s?.lernende.nachDemAbseitsLesen = nil
            _ = s?.lernende.archivSetzen(gezeigt.ohnePerson("l-3", jetzt: "2026-10-29T08:00:00.000Z").bestand,
                                         stempel: "p", gelesen: .gelesen(gezeigt, .init(), kopie: nil))
        }
        var geschrieben = 0
        let vorher = s.lernende.hauptstrang.zahl(.archiv, .lesen)
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let gelaufen = await uhr.vorruecken(bis: { geschrieben == 1 }, hoechstens: .seconds(1))
        try #require(gelaufen, "die Löschung ist geschrieben")
        let zahl = s.lernende.hauptstrang.zahl(.archiv, .lesen) - vorher
        #expect(personenImArchiv(s) == ["l-2"], "beide Änderungen gelten")
        #expect(zahl == 1, Comment(rawValue: "neu gelesen, auf dem Hauptstrang: \(zahl)"))
    }

    // Unter der Stelluhr laufen Aufgaben ohnehin nacheinander: Die Kette selbst zeigt diese Prüfung nicht (G6, Z-BA3-03);
    // sie zeigt `zweiLoeschungenLesenNacheinander` mit dem Taktschreiber (G1-01).
    @Test("Zwei Löschungen kurz nacheinander: beide gelten, keine setzt die andere zurück (F-02, Z-AS2a-02)")
    func zweiLoeschungenNacheinander() async throws {
        let ort = try ordner("zwei")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var geschrieben = 0
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        // Die zweite Frage kommt, bevor die erste fortgesetzt hat — aus dem Blatt, das noch alle drei zeigt.
        s.archivPersonLoeschenFragen("l-2", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let beide = await uhr.vorruecken(bis: { geschrieben == 2 }, hoechstens: .seconds(2))
        try #require(beide, "beide Löschungen sind geschrieben")
        #expect(personenImArchiv(s) == ["l-3"], "keine Löschung setzte die andere zurück")
        #expect(s.ausstehendeArchivloeschungen.isEmpty)
    }

    // Die Kette selbst: Mit dem Taktschreiber laufen die Aufgaben wie im Betrieb sofort los, nebeneinander (G1-01). Ohne
    // Kette läsen beide Löschungen zugleich dieselbe Datei — die spätere fände sie danach geändert und läse selbst, auf
    // dem Hauptstrang. Unabhängig von der Last zeigt es die Prüfnaht vor dem Lesen (E967, Z-BA7N-04).
    @Test("Zwei bestätigte Löschungen lesen nacheinander: Die zweite liest erst, wenn die erste geschrieben hat — beide abseits (F-02, G1-01)")
    func zweiLoeschungenLesenNacheinander() async throws {
        let ort = try ordner("kette")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let takt = Taktschreiber()
        s.takt = takt
        defer { takt.abraeumen() }
        var geschrieben = 0
        // Je Beginn eines Lesens abseits, wie viele schon geschrieben sind: mit Kette [0, 1], ohne [0, 0] (E967).
        var beimLesen: [Int] = []
        s.lernende.vorDemAbseitsLesen = { beimLesen.append(geschrieben) }
        let vorher = s.lernende.hauptstrang.zahl(.archiv, .lesen)
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        s.archivPersonLoeschenFragen("l-2", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        // Beide Fortsetzungen nach dem Alert, im Aufruf: Jede stößt ihr Lesen über `gleich` an — es läuft sofort los.
        let erste = takt.ausloesen()
        let zweite = takt.ausloesen()
        #expect(erste && zweite, "zwei Fortsetzungen")
        let kette = try #require(s.archivloeschungskette, "die Kette hält die zweite")
        await kette.value
        let zahl = s.lernende.hauptstrang.zahl(.archiv, .lesen) - vorher
        #expect(geschrieben == 2, Comment(rawValue: "beide geschrieben: \(geschrieben)"))
        #expect(beimLesen == [0, 1], Comment(rawValue: "geschrieben je Beginn eines Lesens: \(beimLesen)"))
        #expect(zahl == 0, Comment(rawValue: "Lesungen auf dem Hauptstrang: \(zahl) — ohne Kette fände die spätere das Archiv geändert"))
        #expect(personenImArchiv(s) == ["l-3"], "beide Löschungen gelten")
        #expect(s.ausstehendeArchivloeschungen.isEmpty && s.archivloeschungenUnterwegs.isEmpty)
    }

    @Test("Wird die Lernendenverwaltung geschlossen, während eine Löschung abseits liest, gilt das Gelesene nicht — sie schreibt nichts, eine Warnung sagt es (F-02, G1-02)")
    func loeschungNachDemSchliessen() async throws {
        let ort = try ordner("geschlossen")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        // Auf der Platte fehlt „l-1“ schon, das Blatt zeigt sie noch: Nähme die Löschung das abseits Gelesene trotz des
        // Schließens, fände sie „l-1“ nicht und versuchte nichts — so zeigt die Prüfung den Wächter nach dem Lesen
        // (Z-BA7N-01).
        let ohneL1 = gezeigt.ohnePerson("l-1", jetzt: "2026-10-29T08:00:00.000Z").bestand
        #expect(s.lernende.archivSetzen(ohneL1, stempel: "p", gelesen: .gelesen(gezeigt, .init(), kopie: nil)) == nil)
        let datei = Ablage(ordner: ort).archiv
        let vorher = try Data(contentsOf: datei)
        // Gleich nach dem Lesen abseits: gesperrt — wie nach dem Ruhezustand oder „Sperren“. Die Löschung liest dann
        // selbst, findet das Archiv nicht lesbar, wendet auf das Gezeigte an, und das Schreiben lehnt ab.
        s.lernende.nachDemAbseitsLesen = { [weak s] in
            s?.lernende.nachDemAbseitsLesen = nil
            s?.lernende.schliessen()
        }
        var geschrieben = 0
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let gelaufen = await uhr.vorruecken(bis: { s.ausstehendeArchivloeschungen.isEmpty }, hoechstens: .seconds(1))
        try #require(gelaufen, "die Löschung lief")
        #expect(geschrieben == 1 && s.archivSchreibfehler == 1,
                Comment(rawValue: "versucht und abgelehnt: \(geschrieben), Fehler \(s.archivSchreibfehler)"))
        #expect(s.meldungen.contains { $0.text.hasPrefix("Das Archiv ließ sich nicht ändern") },
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
        #expect(try Data(contentsOf: datei) == vorher, "die Datei unberührt")
        #expect(s.archivloeschungenUnterwegs.isEmpty)
    }

    @Test("Blendet nach dem Lesen abseits ein Alert aus, wartet die Löschung dahinter und liest danach neu, abseits (F-02, B88, Z-BA3-01, E962)")
    func loeschungWartetHinterAusblendendemAlert() async throws {
        let ort = try ordner("ausblendend")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var blendetAus = false
        s.rueckfrageSichtbar = { [weak s] in blendetAus || s?.rueckfrage != nil }
        // Gleich nach dem Lesen abseits blendet ein anderes Alert aus.
        s.lernende.nachDemAbseitsLesen = { [weak s] in
            s?.lernende.nachDemAbseitsLesen = nil
            blendetAus = true
        }
        var geschrieben = 0
        let vorher = s.lernende.hauptstrang.zahl(.archiv, .lesen)
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let zuFrueh = await uhr.vorruecken(bis: { geschrieben > 0 }, hoechstens: .seconds(1))
        #expect(!zuFrueh, "unter dem ausblendenden Alert nichts geschrieben")
        // Derweil schreibt ein anderer: „l-3“ geht — mit Befund, damit er selbst nicht liest.
        _ = s.lernende.archivSetzen(gezeigt.ohnePerson("l-3", jetzt: "2026-10-29T08:00:00.000Z").bestand,
                                    stempel: "p", gelesen: .gelesen(gezeigt, .init(), kopie: nil))
        blendetAus = false
        let gelaufen = await uhr.vorruecken(bis: { geschrieben > 0 }, hoechstens: .seconds(1))
        let zahl = s.lernende.hauptstrang.zahl(.archiv, .lesen) - vorher
        #expect(gelaufen && geschrieben == 1, Comment(rawValue: "nach dem Alert genau einmal geschrieben: \(geschrieben)"))
        #expect(zahl == 0, Comment(rawValue: "danach neu gelesen, abseits (E962) — auf dem Hauptstrang: \(zahl)"))
        #expect(personenImArchiv(s) == ["l-2"], "beide Änderungen gelten")
        #expect(s.ausstehendeArchivloeschungen.isEmpty && s.archivloeschungenUnterwegs.isEmpty)
    }

    @Test("Steht nach dem Lesen abseits eine andere Frage, wartet die Löschung auf ihre Antwort und liest danach neu, abseits — keine Änderung aus der Zwischenzeit geht verloren (F-02, Z-AS2a-01, Z-BA3-01, E962)")
    func loeschungWartetHinterAndererFrage() async throws {
        let ort = try ordner("andere-frage")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        // Gleich nach dem Lesen abseits kommt eine andere Frage — wie die Verlustfrage nach ⌘Q.
        s.lernende.nachDemAbseitsLesen = { [weak s] in
            s?.lernende.nachDemAbseitsLesen = nil
            s?.fragen("Eine andere Frage", bestaetigung: "Ja", ort: .lernende) {}
        }
        var geschrieben = 0
        let vorher = s.lernende.hauptstrang.zahl(.archiv, .lesen)
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let zuFrueh = await uhr.vorruecken(bis: { geschrieben > 0 }, hoechstens: .seconds(1))
        #expect(!zuFrueh && s.rueckfrage != nil, "solange die andere Frage steht, nichts geschrieben")
        #expect(s.archivloeschungenUnterwegs.count == 1, "derweil unterwegs — „Trotzdem beenden“ führte sie zuerst aus (E957)")
        // Derweil schreibt ein anderer: „l-3“ geht — mit Befund, damit er selbst nicht liest.
        _ = s.lernende.archivSetzen(gezeigt.ohnePerson("l-3", jetzt: "2026-10-29T08:00:00.000Z").bestand,
                                    stempel: "p", gelesen: .gelesen(gezeigt, .init(), kopie: nil))
        s.rueckfrageBeantworten(false)
        let gelaufen = await uhr.vorruecken(bis: { geschrieben > 0 }, hoechstens: .seconds(1))
        let zahl = s.lernende.hauptstrang.zahl(.archiv, .lesen) - vorher
        #expect(gelaufen && geschrieben == 1, Comment(rawValue: "nach ihrer Antwort genau einmal geschrieben: \(geschrieben)"))
        #expect(zahl == 0, Comment(rawValue: "nach der Antwort neu gelesen, abseits (E962) — auf dem Hauptstrang: \(zahl)"))
        #expect(personenImArchiv(s) == ["l-2"], "beide Änderungen gelten")
        #expect(s.ausstehendeArchivloeschungen.isEmpty && s.archivloeschungenUnterwegs.isEmpty)
    }

    @Test("Blendet das Alert auch nach dem zweiten Lesen noch aus, liest die Löschung danach selbst — genau ein Lesen abseits mehr, keine Schleife (F-02, E962)")
    func loeschungLiestHoechstensEinmalMehr() async throws {
        let ort = try ordner("zweimal")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var blendetAus = false
        s.rueckfrageSichtbar = { [weak s] in blendetAus || s?.rueckfrage != nil }
        // Nach dem ersten Lesen abseits blendet ein Alert aus und bleibt — wie ein eigenes eines Dialogs. Gezählt
        // wird jedes Lesen abseits.
        var abseits = 0
        s.lernende.nachDemAbseitsLesen = {
            abseits += 1
            blendetAus = true
        }
        var geschrieben = 0
        let vorher = s.lernende.hauptstrang.zahl(.archiv, .lesen)
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let gelaufen = await uhr.vorruecken(bis: { geschrieben > 0 }, hoechstens: .seconds(10))
        let zahl = s.lernende.hauptstrang.zahl(.archiv, .lesen) - vorher
        #expect(gelaufen && geschrieben == 1, Comment(rawValue: "nach dem zweiten Warten genau einmal geschrieben: \(geschrieben)"))
        #expect(abseits == 2, Comment(rawValue: "abseits gelesen: \(abseits) — das erste Mal und nach dem ersten Warten"))
        #expect(zahl == 1, Comment(rawValue: "danach gleichlaufend gelesen — auf dem Hauptstrang: \(zahl)"))
        #expect(personenImArchiv(s) == ["l-2", "l-3"], "die Löschung gilt")
        #expect(s.ausstehendeArchivloeschungen.isEmpty && s.archivloeschungenUnterwegs.isEmpty)
    }

    @Test("Wird beendet, während eine Löschung abseits liest, geschieht sie im Beenden — einmal; die späte Aufgabe findet nichts mehr (F-02, Z-AS2a-07, Z-BA3-03)")
    func beendenWaehrendDesLesens() async throws {
        let ort = try ordner("beenden-lesend")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        var erlaubt: Bool?
        var geschrieben = 0
        var imBeenden: Int?
        var blendetAus = false
        s.rueckfrageSichtbar = { [weak s] in blendetAus || s?.rueckfrage != nil }
        // Nach dem Beenden blendet ein Alert aus: Sähe die späte Aufgabe nicht nach, ob die Löschung noch aussteht,
        // wartete sie mit einer Fortsetzung dahinter — ohne Wirkung (Z-BA3N-04). Ein Alert, keine Frage: Hinter einer
        // Frage zählte die Fortsetzung nach 0,35 s nicht mehr; und die Prüfung sieht nach rund 1 s nach, vor dem Deckel
        // der Fortsetzung (rund 2,85 s).
        s.lernende.nachDemAbseitsLesen = { [weak s] in
            s?.lernende.nachDemAbseitsLesen = nil
            erlaubt = s?.beendenErlauben()
            imBeenden = geschrieben
            blendetAus = true
        }
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let fertig = await uhr.vorruecken(bis: { s.archivloeschungenUnterwegs.isEmpty && erlaubt != nil },
                                          hoechstens: .seconds(1))
        await uhr.vorruecken(um: .seconds(1))
        #expect(fertig && erlaubt == true, "das Beenden ging durch")
        #expect(imBeenden == 1, Comment(rawValue: "im Beenden geschrieben: \(imBeenden.map(String.init) ?? "—")"))
        #expect(geschrieben == 1, Comment(rawValue: "genau einmal geschrieben: \(geschrieben)"))
        #expect(s.ausstehendeArchivloeschungen.isEmpty && s.archivloeschungenUnterwegs.isEmpty)
        #expect(s.ausstehendeFortsetzungen == 0,
                Comment(rawValue: "keine Fortsetzung ohne Wirkung: \(s.ausstehendeFortsetzungen)"))
        #expect(personenImArchiv(s) == ["l-2", "l-3"], "die Löschung gilt")
    }

    // ── Die Grenzen: Jahreswechsel und Beenden ────────────────────────────

    @Test("Der Jahreswechsel liest das Archiv gleichlaufend — eine Grenze der Prüfmarke (F-02, E953 b)")
    func jahreswechselBleibtGleichlaufend() async throws {
        let ort = try ordner("wechsel")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, _) = try await speicher(ort)
        s.offenerDialog = nil
        let neue = Planung.leer(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4,
                                basis: "", klassen: [], fachfarben: [:])
        let vorher = s.lernende.hauptstrang.zahl(.archiv, .lesen)
        let grund = s.jahreswechsel(zu: neue, zuordnung: [:], gruppen: [], ohneMitglieder: [])
        let zahl = s.lernende.hauptstrang.zahl(.archiv, .lesen) - vorher
        #expect(grund == nil, Comment(rawValue: grund ?? "—"))
        #expect(zahl == 1, Comment(rawValue: "Lesungen des Archivs auf dem Hauptstrang: \(zahl)"))
        guard case .gelesen(let archiv, _, _) = s.lernende.archivLesen(stempel: "p") else {
            Issue.record("das Archiv öffnet nicht")
            return
        }
        #expect(archiv.jahre.map(\.schuljahr) == ["2025/26", "2026/27"], "das bisherige Jahr kam dazu")
    }

    @Test("Setzen, Entsperren und Übergang arbeiten gleichlaufend wie bisher — Grenzen der Prüfmarke (F-02, E949 c, E959)")
    func setzenEntsperrenUebergangGleichlaufend() async throws {
        let ort = try ordner("grenzen")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, _) = try await speicher(ort)
        let tresor = try #require(s.tresor)
        let m = s.lernende.hauptstrang
        func stand() -> [Int] {
            [m.zahl(.jahresdatei, .bauen), m.zahl(.jahresdatei, .zuruecklesen), m.zahl(.jahresdatei, .lesen),
             m.zahl(.archiv, .uebergang)]
        }
        let vorher = stand()
        #expect(s.lernende.setzen(RuecknahmeLernendenPruefungen.entwurf()) == nil)
        let gesetzt = zip(stand(), vorher).map { $0 - $1 }
        #expect(gesetzt == [1, 1, 0, 0], Comment(rawValue: "Setzen baut und liest zurück, gleichlaufend: \(gesetzt)"))
        _ = s.lernende.oeffnen(mit: tresor, stempel: "p")
        _ = try s.lernende.archivInhalt(unter: tresor)
        let danach = zip(stand(), vorher).map { $0 - $1 }
        #expect(danach == [1, 1, 1, 1],
                Comment(rawValue: "Entsperren liest die Jahresdatei, der Übergang entziffert das Archiv — gleichlaufend: \(danach)"))
    }

    @Test("Vor dem Beenden geschieht eine bestätigte Löschung gleichlaufend — eine Grenze der Prüfmarke (F-02, Z-AS2a-07)")
    func beendenBleibtGleichlaufend() async throws {
        let ort = try ordner("beenden")
        defer { try? FileManager.default.removeItem(at: ort) }
        let (s, gezeigt) = try await speicher(ort)
        var geschrieben = 0
        let vorher = s.lernende.hauptstrang.zahl(.archiv, .lesen)
        s.archivPersonLoeschenFragen("l-1", in: gezeigt) { neu in _ = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        // Gleich danach beendet, vor der Fortsetzung: Das Beenden führt sie noch aus — auf dem Hauptstrang.
        #expect(s.beendenErlauben())
        let zahl = s.lernende.hauptstrang.zahl(.archiv, .lesen) - vorher
        #expect(geschrieben == 1 && zahl == 1, Comment(rawValue: "geschrieben \(geschrieben), Lesungen \(zahl)"))
        #expect(personenImArchiv(s) == ["l-2", "l-3"], "vor dem Beenden gelöscht")
    }
}
