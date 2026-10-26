// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Hält jede Anfrage an, bis `freigeben()` antwortet, und zählt Start und
/// Abbruch — so wird sichtbar, ob ein Abbruch die Anfrage erreicht, nicht nur,
/// ob ein Ergebnis verworfen wird (R72-03). Mit `teilweise` kommen Kopf und die
/// erste Hälfte des Körpers gleich beim Start, der Rest nie (R73, Empfehlung 1);
/// `geliefert` zählt, wann beides an die Sitzung übergeben ist — ein Signal am
/// Transport, das nicht davon abhängt, wann der Leser der Antwort drankommt.
private final class Haltestub: URLProtocol {
    nonisolated(unsafe) static var gestartet = 0
    nonisolated(unsafe) static var gestoppt = 0
    nonisolated(unsafe) static var geliefert = 0
    nonisolated(unsafe) static var offen: [Haltestub] = []
    nonisolated(unsafe) static var daten = Data()
    nonisolated(unsafe) static var teilweise = false
    static let schloss = NSLock()

    static func zuruecksetzen(_ antwort: Data, teilweise: Bool = false) {
        schloss.withLock {
            gestartet = 0; gestoppt = 0; geliefert = 0; offen = []; daten = antwort
            self.teilweise = teilweise
        }
    }

    static var zaehler: (gestartet: Int, gestoppt: Int, geliefert: Int) {
        schloss.withLock { (gestartet, gestoppt, geliefert) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (teil, antwort) = Haltestub.schloss.withLock { () -> (Bool, Data) in
            Haltestub.gestartet += 1
            Haltestub.offen.append(self)
            return (Haltestub.teilweise, Haltestub.daten)
        }
        guard teil, let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                         headerFields: ["Content-Length": "\(antwort.count)"])
        else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: antwort.prefix(antwort.count / 2))
        Haltestub.schloss.withLock { Haltestub.geliefert += 1 }
    }

    override func stopLoading() {
        Haltestub.schloss.withLock { Haltestub.gestoppt += 1 }
    }

    /// Beantwortet jede Anfrage, die noch hängt, mit 200 und den Daten.
    static func freigeben() {
        let (liste, antwort) = schloss.withLock { () -> ([Haltestub], Data) in
            defer { offen = [] }
            return (offen, daten)
        }
        for anfrage in liste {
            guard let url = anfrage.request.url,
                  let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])
            else { continue }
            anfrage.client?.urlProtocol(anfrage, didReceive: http, cacheStoragePolicy: .notAllowed)
            anfrage.client?.urlProtocol(anfrage, didLoad: antwort)
            anfrage.client?.urlProtocolDidFinishLoading(anfrage)
        }
    }
}

/// Wie lange eine festgehaltene Anfrage auf Daten wartet (B66, v76). Im Betrieb
/// sind es 10 s; hier hält die Prüfung die Anfrage fest, bis sie selbst wieder
/// an der Reihe ist — im vollen Parallellauf kam sie erst nach 22–33 s dazu, und
/// die Anfrage lief ab („nichtErreichbar“; seit v73, je 1 von 20 Läufen).
private let haltegrenze: TimeInterval = 600

private func haltesitzung() -> URLSession {
    let konfiguration = URLSessionConfiguration.ephemeral
    konfiguration.protocolClasses = [Haltestub.self]
    return Updatepruefer.sitzung(konfiguration, zeitgrenze: haltegrenze)
}

private let vorlagenordner = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Vorlagen")

/// Ein Release, das neuer ist als jede Fassung im Prüfziel (dort ist der Build 0).
private let releaseNeu = Data(#"""
{"tag_name": "v99", "name": "Unterrichtsplanung 9.9.9 (99)", "draft": false, "prerelease": false,
 "html_url": "https://github.com/dk-3du/unterrichtsplanung/releases/tag/v99", "body": "x", "assets": []}
"""#.utf8)

/// Dasselbe Release mit langem Text, für den Entzug mitten im Körper: Bei 101
/// Byte als erster Hälfte kam der Kopf nie bei der Sitzung an, bei 1 291 Byte
/// (Materialliste) sofort (gemessen 18.09.2026) — URLSession hält einen kurzen
/// Anfang offenbar zurück, wohl um den Inhaltstyp zu erkennen.
private let releaseLang = Data((#"{"tag_name": "v99", "name": "Unterrichtsplanung 9.9.9 (99)", "draft": false, "#
    + #""prerelease": false, "html_url": "https://github.com/dk-3du/unterrichtsplanung/releases/tag/v99", "#
    + #""body": ""# + String(repeating: "x", count: 3000) + #"", "assets": []}"#).utf8)

/// Der Entzug einer Erlaubnis (E199, R72-03, B46, v73): Er bricht die laufende
/// Anfrage ab — der Abbruch erreicht den Transport —, und ein Ergebnis aus der
/// Zeit davor gilt nicht, auch nicht nach erneutem Einschalten. Eine Prüfung
/// auf Updates von Hand hängt nicht an der Erlaubnis und läuft zu Ende.
///
/// Geprüft wird erst, wenn die alte Aufgabe zu Ende ist (E207, R73-01, v74) —
/// nie nach einer Zahl von Yields: Eine Wache, die fehlt, fiele sonst nur auf,
/// wenn die alte Aufgabe zufällig vor den Erwartungen drankommt.
@Suite("Entzug: Wer die Erlaubnis entzieht, bricht die laufende Anfrage ab", .serialized)
@MainActor
struct EntzugPruefungen {

    // ── Die Materialliste ─────────────────────────────────────────────────

    /// Ein Koordinator, der über den Haltestub lädt. Die Quelle ist eine Datei
    /// (Prüfstand) — der Stub nimmt auch sie an, ins Netz geht nichts.
    private func materialkoordinator(teilweise: Bool = false) throws -> Materialkoordinator {
        Haltestub.zuruecksetzen(try Data(contentsOf: vorlagenordner.appending(path: "inhalte-synthetisch.js")),
                                teilweise: teilweise)
        let k = Materialkoordinator(pruefstand: true, umgebung: ["MATERIAL_QUELLE": "/gibt/es/nicht/inhalte.js"])
        let sitzung = haltesitzung()
        k.lader = { await Materiallader(quelle: $0, installiert: 0, sitzung: sitzung, zeitgrenze: haltegrenze).laden() }
        k.erlauben(true)
        return k
    }

    /// B66 (v76): Die Prüfungen hier halten eine Anfrage fest, bis sie selbst
    /// wieder an der Reihe sind. Mit der Zeitgrenze des Betriebs (10 s) lief sie
    /// im vollen Lauf dabei gelegentlich ab. Die festgehaltene Anfrage hat darum
    /// ihre eigene Grenze — der Betrieb behält seine.
    @Test("Die festgehaltene Anfrage hängt nicht an der Zeitgrenze des Betriebs — die bleibt 10 s")
    func zeitgrenzen() throws {
        let quelle = URL(fileURLWithPath: "/gibt/es/nicht/inhalte.js")
        #expect(Materiallader(quelle: quelle, installiert: 0).anfrage.timeoutInterval == 10)
        #expect(Updatepruefer(quelle: quelle, installiert: 0).anfrage.timeoutInterval == 10)
        #expect(Updatepruefer.standardSitzung.configuration.timeoutIntervalForRequest == 10)
        #expect(Updatepruefer.standardSitzung.configuration.timeoutIntervalForResource == 20)
        #expect(Updatekoordinator(pruefstand: true, umgebung: [:]).zeitgrenze == 10)

        #expect(haltesitzung().configuration.timeoutIntervalForRequest == haltegrenze)
        #expect(Materiallader(quelle: quelle, installiert: 0, zeitgrenze: haltegrenze).anfrage.timeoutInterval == haltegrenze)
        #expect(updatekoordinator {}.zeitgrenze == haltegrenze)
    }

    @Test("Ohne Entzug kommt die Liste an — der Umweg über die gehaltene Aufgabe ändert daran nichts")
    func ohneEntzug() async throws {
        let k = try materialkoordinator()
        let aufgabe = Task { await k.laden() }
        try await abwarten("die Anfrage steht") { Haltestub.zaehler.gestartet == 1 }
        Haltestub.freigeben()
        let ergebnis = await aufgabe.value
        guard case .geladen(let katalog) = ergebnis else {
            // Was kam, steht in der Meldung — so zeigte sich B66 (v76).
            Issue.record(Comment(rawValue: "mit Erlaubnis kommt die Liste an — kam: \(ergebnis)")); return
        }
        #expect(katalog.kacheln > 0)
        // Wann URLSession die beendete Anfrage abräumt, sagt sie nicht zu —
        // gewartet wird auf das Ereignis, nicht angenommen (E211, B55, v74).
        try await abwarten("die beendete Anfrage wird wie jede abgeräumt") { Haltestub.zaehler.gestoppt == 1 }
    }

    @Test("Entzug während des Ladens: der Abbruch erreicht die Anfrage, keine Liste kommt an")
    func entzugBrichtAb() async throws {
        let k = try materialkoordinator()
        let aufgabe = Task { await k.laden() }
        try await abwarten("die Anfrage steht") { Haltestub.zaehler.gestartet == 1 }
        #expect(Haltestub.zaehler.gestoppt == 0)
        k.erlauben(false)
        try await abwarten("der Abbruch erreicht den Transport") { Haltestub.zaehler.gestoppt == 1 }
        #expect(await aufgabe.value == .keineErlaubnis)
    }

    @Test("Entzug, nachdem Kopf und halber Körper da sind: abgebrochen, keine Liste kommt an")
    func entzugImKoerper() async throws {
        let k = try materialkoordinator(teilweise: true)
        let aufgabe = Task { await k.laden() }
        try await abwarten("Kopf und halber Körper sind geliefert") { Haltestub.zaehler.geliefert == 1 }
        k.erlauben(false)
        try await abwarten("der Abbruch erreicht den Transport") { Haltestub.zaehler.gestoppt == 1 }
        #expect(await aufgabe.value == .keineErlaubnis)
    }

    @Test("Drei Ladeaufgaben zugleich, dann Entzug: jede Anfrage abgebrochen, keine Liste kommt an")
    func dreiZugleich() async throws {
        let k = try materialkoordinator()
        let aufgaben = (0..<3).map { _ in Task { await k.laden() } }
        try await abwarten("drei Anfragen stehen") { Haltestub.zaehler.gestartet == 3 }
        k.erlauben(false)
        try await abwarten("alle drei abgebrochen") { Haltestub.zaehler.gestoppt == 3 }
        for aufgabe in aufgaben {
            #expect(await aufgabe.value == .keineErlaubnis)
        }
    }

    @Test("Aus und gleich wieder an: das Ergebnis aus der Zeit davor gilt nicht")
    func ausUndWiederAn() async throws {
        let k = try materialkoordinator()
        let aufgabe = Task { await k.laden() }
        try await abwarten("die Anfrage steht") { Haltestub.zaehler.gestartet == 1 }
        k.erlauben(false)
        k.erlauben(true)
        Haltestub.freigeben()
        #expect(await aufgabe.value == .keineErlaubnis, "kein altes Ergebnis nach erneutem Einschalten")
        // Das nächste Laden gilt wieder.
        let neu = Task { await k.laden() }
        try await abwarten("die neue Anfrage steht") { Haltestub.zaehler.gestartet == 2 }
        Haltestub.freigeben()
        guard case .geladen = await neu.value else { Issue.record("danach wird wieder geladen"); return }
    }

    @Test("Kontrolle: Schließt das Blatt, bricht seine Aufgabe ab — und mit ihr die Anfrage")
    func blattSchliesst() async throws {
        let k = try materialkoordinator()
        let aufgabe = Task { await k.laden() }
        try await abwarten("die Anfrage steht") { Haltestub.zaehler.gestartet == 1 }
        aufgabe.cancel()
        try await abwarten("der Abbruch erreicht den Transport") { Haltestub.zaehler.gestoppt == 1 }
        #expect(k.istErlaubt, "die Erlaubnis bleibt")
    }

    // ── Die Prüfung auf Updates ───────────────────────────────────────────

    /// Ein Koordinator, der über den Haltestub prüft; die Quelle ist eine Datei.
    private func updatekoordinator(teilweise: Bool = false,
                                   _ angebote: @escaping @MainActor () -> Void) -> Updatekoordinator {
        Haltestub.zuruecksetzen(teilweise ? releaseLang : releaseNeu, teilweise: teilweise)
        let k = Updatekoordinator(pruefstand: true, umgebung: ["UPDATE_QUELLE": "/gibt/es/nicht/latest.json"])
        k.sitzung = haltesitzung()
        k.zeitgrenze = haltegrenze
        k.beiAngebot = angebote
        return k
    }

    @Test("Update: ohne Entzug kommt das Angebot")
    func updateOhneEntzug() async throws {
        var angeboten = 0
        let k = updatekoordinator { angeboten += 1 }
        k.erlauben(true)
        try await abwarten("die Anfrage steht") { Haltestub.zaehler.gestartet == 1 }
        Haltestub.freigeben()
        try await abwarten("die Prüfung ist fertig") { !k.laeuft }
        #expect(k.angebot?.build == 99 && angeboten == 1)
        #expect(k.stand.zuletzt != nil)
    }

    @Test("Update: Entzug während der Prüfung — abgebrochen, kein Angebot, nichts gemerkt")
    func updateEntzug() async throws {
        var angeboten = 0
        let k = updatekoordinator { angeboten += 1 }
        k.erlauben(true)
        try await abwarten("die Anfrage steht") { Haltestub.zaehler.gestartet == 1 }
        let alt = try #require(k.letztePruefung)
        k.erlauben(false)
        try await abwarten("der Abbruch erreicht den Transport") { Haltestub.zaehler.gestoppt == 1 }
        Haltestub.freigeben()
        // Die Schranke: Gefragt wird, wenn die alte Prüfung zu Ende ist.
        await alt.value
        #expect(!k.laeuft)
        #expect(k.angebot == nil && angeboten == 0, "kein Angebot nach dem Entzug")
        #expect(k.stand.zuletzt == nil && k.stand.etag == nil && k.stand.antwort == nil, "nichts gemerkt")
    }

    @Test("Update: Entzug, nachdem Kopf und halber Körper da sind — abgebrochen, nichts gemerkt")
    func updateEntzugImKoerper() async throws {
        var angeboten = 0
        let k = updatekoordinator(teilweise: true) { angeboten += 1 }
        k.erlauben(true)
        let alt = try #require(k.letztePruefung)
        try await abwarten("Kopf und halber Körper sind geliefert") { Haltestub.zaehler.geliefert == 1 }
        k.erlauben(false)
        try await abwarten("der Abbruch erreicht den Transport") { Haltestub.zaehler.gestoppt == 1 }
        await alt.value
        #expect(k.angebot == nil && angeboten == 0, "kein Angebot nach dem Entzug")
        #expect(k.stand.zuletzt == nil && k.stand.etag == nil && k.stand.antwort == nil, "nichts gemerkt")
    }

    @Test("Update: aus und gleich wieder an — die alte Prüfung stört die neue nicht")
    func updateAusUndWiederAn() async throws {
        var angeboten = 0
        let k = updatekoordinator { angeboten += 1 }
        k.erlauben(true)
        try await abwarten("die erste Anfrage steht") { Haltestub.zaehler.gestartet == 1 }
        let alt = try #require(k.letztePruefung)
        k.erlauben(false)
        k.erlauben(true)
        let neu = try #require(k.letztePruefung)
        #expect(neu != alt, "das Einschalten stößt eine neue Prüfung an")
        try await abwarten("die zweite Anfrage steht") { Haltestub.zaehler.gestartet == 2 }
        await alt.value
        #expect(k.laeuft, "die neue Prüfung läuft weiter")
        #expect(k.stand.zuletzt == nil && k.angebot == nil && angeboten == 0,
                "von der alten Prüfung ist nichts übernommen")
        Haltestub.freigeben()
        await neu.value
        #expect(!k.laeuft && k.angebot?.build == 99 && angeboten == 1, "die neue bringt genau ein Angebot")
    }

    @Test("Update: eine Prüfung von Hand hängt nicht an der Erlaubnis und läuft zu Ende")
    func updateVonHand() async throws {
        var angeboten = 0
        let k = updatekoordinator { angeboten += 1 }
        k.erlauben(false)
        k.pruefen(erzwungen: true)
        try await abwarten("die Anfrage steht") { Haltestub.zaehler.gestartet == 1 }
        k.erlauben(false)
        Haltestub.freigeben()
        try await abwarten("die Prüfung ist fertig") { !k.laeuft }
        #expect(k.angebot?.build == 99 && angeboten == 1, "von Hand verlangt, von Hand gezeigt")
    }
}
