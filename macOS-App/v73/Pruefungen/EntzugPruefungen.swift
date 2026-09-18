// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Hält jede Anfrage an, bis `freigeben()` antwortet, und zählt Start und
/// Abbruch — so wird sichtbar, ob ein Abbruch die Anfrage erreicht, nicht nur,
/// ob ein Ergebnis verworfen wird (R72-03).
private final class Haltestub: URLProtocol {
    nonisolated(unsafe) static var gestartet = 0
    nonisolated(unsafe) static var gestoppt = 0
    nonisolated(unsafe) static var offen: [Haltestub] = []
    nonisolated(unsafe) static var daten = Data()
    static let schloss = NSLock()

    static func zuruecksetzen(_ antwort: Data) {
        schloss.withLock { gestartet = 0; gestoppt = 0; offen = []; daten = antwort }
    }

    static var zaehler: (gestartet: Int, gestoppt: Int) {
        schloss.withLock { (gestartet, gestoppt) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Haltestub.schloss.withLock {
            Haltestub.gestartet += 1
            Haltestub.offen.append(self)
        }
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

private func haltesitzung() -> URLSession {
    let konfiguration = URLSessionConfiguration.ephemeral
    konfiguration.protocolClasses = [Haltestub.self]
    return Updatepruefer.sitzung(konfiguration)
}

private let vorlagenordner = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Vorlagen")

/// Ein Release, das neuer ist als jede Fassung im Prüfziel (dort ist der Build 0).
private let releaseNeu = Data(#"""
{"tag_name": "v99", "name": "Unterrichtsplanung 9.9.9 (99)", "draft": false, "prerelease": false,
 "html_url": "https://github.com/dk-3du/unterrichtsplanung/releases/tag/v99", "body": "x", "assets": []}
"""#.utf8)

/// Der Entzug einer Erlaubnis (E199, R72-03, B46, v73): Er bricht die laufende
/// Anfrage ab — der Abbruch erreicht den Transport —, und ein Ergebnis aus der
/// Zeit davor gilt nicht, auch nicht nach erneutem Einschalten. Eine Prüfung
/// auf Updates von Hand hängt nicht an der Erlaubnis und läuft zu Ende.
@Suite("Entzug: Wer die Erlaubnis entzieht, bricht die laufende Anfrage ab", .serialized)
@MainActor
struct EntzugPruefungen {

    // ── Die Materialliste ─────────────────────────────────────────────────

    /// Ein Koordinator, der über den Haltestub lädt. Die Quelle ist eine Datei
    /// (Prüfstand) — der Stub nimmt auch sie an, ins Netz geht nichts.
    private func materialkoordinator() throws -> Materialkoordinator {
        Haltestub.zuruecksetzen(try Data(contentsOf: vorlagenordner.appending(path: "inhalte-synthetisch.js")))
        let k = Materialkoordinator(pruefstand: true, umgebung: ["MATERIAL_QUELLE": "/gibt/es/nicht/inhalte.js"])
        let sitzung = haltesitzung()
        k.lader = { await Materiallader(quelle: $0, installiert: 0, sitzung: sitzung).laden() }
        k.erlauben(true)
        return k
    }

    @Test("Ohne Entzug kommt die Liste an — der Umweg über die gehaltene Aufgabe ändert daran nichts")
    func ohneEntzug() async throws {
        let k = try materialkoordinator()
        let aufgabe = Task { await k.laden() }
        try await abwarten("die Anfrage steht") { Haltestub.zaehler.gestartet == 1 }
        Haltestub.freigeben()
        guard case .geladen(let katalog) = await aufgabe.value else {
            Issue.record("mit Erlaubnis kommt die Liste an"); return
        }
        #expect(katalog.kacheln > 0)
        #expect(Haltestub.zaehler.gestoppt == 1, "die beendete Anfrage wird wie jede abgeräumt")
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
    private func updatekoordinator(_ angebote: @escaping @MainActor () -> Void) -> Updatekoordinator {
        Haltestub.zuruecksetzen(releaseNeu)
        let k = Updatekoordinator(pruefstand: true, umgebung: ["UPDATE_QUELLE": "/gibt/es/nicht/latest.json"])
        k.sitzung = haltesitzung()
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
        k.erlauben(false)
        try await abwarten("der Abbruch erreicht den Transport") { Haltestub.zaehler.gestoppt == 1 }
        Haltestub.freigeben()
        try await abwarten("die Prüfung ist beendet") { !k.laeuft }
        // Der Aufgabe Zeit lassen, ein verspätetes Ergebnis doch noch zu übernehmen.
        for _ in 0..<20 { await Task.yield() }
        #expect(k.angebot == nil && angeboten == 0, "kein Angebot nach dem Entzug")
        #expect(k.stand.zuletzt == nil && k.stand.etag == nil, "nichts gemerkt")
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
