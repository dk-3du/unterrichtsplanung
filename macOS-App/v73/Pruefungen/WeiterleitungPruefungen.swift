// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Antworten ohne Netz, mit Weiterleitungen: Der Stub beantwortet jede Adresse
/// aus seiner Tabelle und zählt die Anfragen je Rechner — so zeigt sich, ob ein
/// fremder Rechner je eine Anfrage sah.
private final class Umleitungsstub: URLProtocol {
    struct Antwort {
        var status = 200
        var weiter: String? = nil
        var daten = Data()
    }

    nonisolated(unsafe) static var antworten: [String: Antwort] = [:]
    nonisolated(unsafe) static var anfragenJeRechner: [String: Int] = [:]

    static func zuruecksetzen(_ antworten: [String: Antwort]) {
        self.antworten = antworten
        anfragenJeRechner = [:]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let rechner = (url.scheme ?? "") + "://" + (url.host() ?? "")
        Umleitungsstub.anfragenJeRechner[rechner, default: 0] += 1
        guard let antwort = Umleitungsstub.antworten[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        var kopf: [String: String] = [:]
        if let weiter = antwort.weiter { kopf["Location"] = weiter }
        let http = HTTPURLResponse(url: url, statusCode: antwort.status, httpVersion: "HTTP/1.1", headerFields: kopf)!
        if let weiter = antwort.weiter, let ziel = URL(string: weiter, relativeTo: url)?.absoluteURL {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: ziel), redirectResponse: http)
            // Wie ein gewöhnlicher Lader: Nach der Meldung ist dieser Auftrag zu
            // Ende — folgt der Client nicht, bleibt ihm die Antwort 3xx.
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: antwort.daten)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let vorlagenordner = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Vorlagen")

@Suite("Weiterleitungen: beide Netzwege bleiben beim erlaubten Rechner", .serialized)
struct WeiterleitungPruefungen {
    private func sitzung() -> URLSession {
        let konfiguration = URLSessionConfiguration.ephemeral
        konfiguration.protocolClasses = [Umleitungsstub.self]
        return Updatepruefer.sitzung(konfiguration)
    }

    private func liste() throws -> Data {
        try Data(contentsOf: vorlagenordner.appending(path: "inhalte-synthetisch.js"))
    }

    private func materiallader() -> Materiallader {
        Materiallader(quelle: Materiallader.schnittstelle, installiert: 72, sitzung: sitzung())
    }

    private let quelle = Materiallader.schnittstelle.absoluteString

    @Test("Die Regel als Tabelle: https, derselbe Rechner, derselbe Anschluss, keine Zugangsdaten")
    func regel() {
        func erlaubt(_ von: String, _ nach: String) -> Bool {
            Weiterleitung.erlaubt(von: URL(string: von), nach: URL(string: nach))
        }
        let basis = "https://3ducation.org/inhalte.js"
        #expect(erlaubt(basis, "https://3ducation.org/neu/inhalte.js"))
        #expect(erlaubt(basis, "https://3DUCATION.org/x"), "Groß und klein zählt beim Rechner nicht")
        #expect(erlaubt(basis, "https://3ducation.org:443/x"), "443 ist der Anschluss von https")
        #expect(!erlaubt(basis, "https://www.3ducation.org/x"), "eine Unterdomäne ist ein anderer Rechner")
        #expect(!erlaubt(basis, "https://3ducation.org.fremd.example/x"))
        #expect(!erlaubt(basis, "https://fremd.example/3ducation.org"))
        #expect(!erlaubt(basis, "http://3ducation.org/x"), "nie herab auf http")
        #expect(!erlaubt("http://3ducation.org/x", "https://3ducation.org/x"), "und nie von http aus")
        #expect(!erlaubt(basis, "https://3ducation.org:8443/x"))
        #expect(!erlaubt(basis, "https://nutzer@3ducation.org/x"))
        #expect(!erlaubt(basis, "https://nutzer:geheim@3ducation.org/x"))
        #expect(!erlaubt(basis, "ftp://3ducation.org/x"))
        #expect(!erlaubt(basis, "file:///etc/hosts"))
        #expect(!Weiterleitung.erlaubt(von: nil, nach: URL(string: basis)))
        #expect(!Weiterleitung.erlaubt(von: URL(string: basis), nach: nil))
    }

    @Test("Materialliste: Eine Weiterleitung zu einem fremden Rechner wird nicht verfolgt — er sieht keine Anfrage")
    func fremderRechner() async throws {
        Umleitungsstub.zuruecksetzen([
            quelle: .init(status: 302, weiter: "https://fremd.example/inhalte.js"),
            "https://fremd.example/inhalte.js": .init(daten: try liste()),
        ])
        #expect(await materiallader().laden() == .nichtErreichbar)
        #expect(Umleitungsstub.anfragenJeRechner["https://fremd.example"] == nil, "der fremde Rechner sah nichts")
        #expect(Umleitungsstub.anfragenJeRechner["https://3ducation.org"] == 1)
    }

    @Test("Materialliste: Auch eine Unterdomäne und ein anderer Anschluss sind ein fremder Rechner")
    func unterdomaeneUndAnschluss() async throws {
        for ziel in ["https://www.3ducation.org/inhalte.js", "https://3ducation.org:8443/inhalte.js",
                     "https://nutzer:geheim@3ducation.org/inhalte.js"] {
            Umleitungsstub.zuruecksetzen([quelle: .init(status: 301, weiter: ziel), ziel: .init(daten: try liste())])
            #expect(await materiallader().laden() == .nichtErreichbar, Comment(rawValue: ziel))
            #expect(Umleitungsstub.anfragenJeRechner.values.reduce(0, +) == 1, Comment(rawValue: "\(ziel): nur die erste Anfrage"))
        }
    }

    @Test("Materialliste: Von https nach http wird nicht verfolgt")
    func herabstufung() async throws {
        Umleitungsstub.zuruecksetzen([
            quelle: .init(status: 301, weiter: "http://3ducation.org/inhalte.js"),
            "http://3ducation.org/inhalte.js": .init(daten: try liste()),
        ])
        #expect(await materiallader().laden() == .nichtErreichbar)
        #expect(Umleitungsstub.anfragenJeRechner["http://3ducation.org"] == nil)
    }

    @Test("Materialliste: Derselbe Rechner über https wird verfolgt")
    func derselbeRechner() async throws {
        Umleitungsstub.zuruecksetzen([
            quelle: .init(status: 301, weiter: "/neu/inhalte.js"),
            "https://3ducation.org/neu/inhalte.js": .init(daten: try liste()),
        ])
        guard case .geladen(let katalog) = await materiallader().laden() else {
            Issue.record("derselbe Rechner müsste geladen werden"); return
        }
        #expect(katalog.kategorien.count == 3)
        #expect(Umleitungsstub.anfragenJeRechner["https://3ducation.org"] == 2)
    }

    @Test("Materialliste: Eine Schleife endet — nicht erreichbar")
    func schleife() async {
        Umleitungsstub.zuruecksetzen([
            quelle: .init(status: 302, weiter: "/b.js"),
            "https://3ducation.org/b.js": .init(status: 302, weiter: "/inhalte.js"),
        ])
        #expect(await materiallader().laden() == .nichtErreichbar)
        #expect((Umleitungsstub.anfragenJeRechner["https://3ducation.org"] ?? 0) < 40, "die Schleife endet")
    }

    @Test("Prüfung auf Updates: dieselbe Regel")
    func updates() async throws {
        let schnittstelle = Updatepruefer.schnittstelle.absoluteString
        func pruefer() -> Updatepruefer {
            Updatepruefer(quelle: Updatepruefer.schnittstelle, installiert: 72, sitzung: sitzung())
        }
        let antwort = Data(#"{"tag_name":"v99","name":"Unterrichtsplanung 9.9.9 (99)","html_url":"https://github.com/dk-3du/unterrichtsplanung/releases/tag/v99","body":"","draft":false,"prerelease":false,"assets":[]}"#.utf8)
        Umleitungsstub.zuruecksetzen([
            schnittstelle: .init(status: 301, weiter: "https://fremd.example/latest"),
            "https://fremd.example/latest": .init(daten: antwort),
        ])
        #expect(await pruefer().pruefen().befund == .nichtErreichbar)
        #expect(Umleitungsstub.anfragenJeRechner["https://fremd.example"] == nil, "der fremde Rechner sah nichts")
        // Ein umbenanntes Repository: GitHub leitet auf demselben Rechner um.
        Umleitungsstub.zuruecksetzen([
            schnittstelle: .init(status: 301, weiter: "https://api.github.com/repositories/1/releases/latest"),
            "https://api.github.com/repositories/1/releases/latest": .init(daten: antwort),
        ])
        guard case .neu = await pruefer().pruefen().befund else {
            Issue.record("derselbe Rechner müsste gelesen werden"); return
        }
        #expect(Umleitungsstub.anfragenJeRechner["https://api.github.com"] == 2)
    }
}
