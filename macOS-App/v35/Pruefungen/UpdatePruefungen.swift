// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Eine gespeicherte Antwort der Schnittstelle (`releases/latest`), auf die
/// Felder gekürzt, die das Blatt braucht — plus einige, die es nicht braucht:
/// Die müssen ohne Wirkung bleiben.
private let antwortV33 = Data(#"""
{
  "url": "https://api.github.com/repos/dk-3du/unterrichtsplanung/releases/278415512",
  "html_url": "https://github.com/dk-3du/unterrichtsplanung/releases/tag/v33",
  "id": 278415512,
  "author": { "login": "dk-3du", "type": "User" },
  "tag_name": "v33",
  "target_commitish": "main",
  "name": "Unterrichtsplanung 1.2.3 (33)",
  "draft": false,
  "prerelease": false,
  "created_at": "2026-09-05T16:20:42Z",
  "published_at": "2026-09-05T16:39:51Z",
  "assets": [
    {
      "name": "Unterrichtsplanung-1.2.3-33.dmg",
      "content_type": "application/octet-stream",
      "size": 3199912,
      "digest": "sha256:fe992191bb02746b3f6cc85a4fd14fd617c57e8cca3cd06ce090303ccd143fda",
      "download_count": 0,
      "browser_download_url": "https://github.com/dk-3du/unterrichtsplanung/releases/download/v33/Unterrichtsplanung-1.2.3-33.dmg"
    }
  ],
  "body": "Erste Veröffentlichung unter GPL-3.0-or-later (macOS-App) und AGPL-3.0-or-later (Ansicht fürs iPad).\r\n\r\n**Voraussetzungen:** macOS 26 auf Apple Silicon.\r\n"
}
"""#.utf8)

/// Antworten ohne Netz: Der Stub beantwortet jede Adresse aus seiner Tabelle
/// und hält die letzte Anfrage fest — für die Kopfzeilen.
private final class Antwortstub: URLProtocol {
    struct Antwort { let status: Int; let kopf: [String: String]; let daten: Data }

    nonisolated(unsafe) static var antworten: [String: Antwort] = [:]
    nonisolated(unsafe) static var letzteAnfrage: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Antwortstub.letzteAnfrage = request
        guard let url = request.url, let antwort = Antwortstub.antworten[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: antwort.status,
                                   httpVersion: "HTTP/1.1", headerFields: antwort.kopf)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: antwort.daten)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Updates: Tag, Befund, Frist, Quelle", .serialized)
struct UpdatePruefungen {

    private func lesen() throws -> Veroeffentlichung { try Veroeffentlichung.lesen(antwortV33) }

    @Test("Das Tag-Schema vNN: nur die Zahl zählt, alles andere ist keins")
    func tagzahl() {
        let zahl = Veroeffentlichung.build(aus:)
        #expect(zahl("v33") == 33)
        #expect(zahl("V34") == 34)
        #expect(zahl(" v35\n") == 35)
        #expect(zahl("v0") == 0)
        #expect(zahl("34") == nil, "ohne v ist es kein Tag dieses Schemas")
        #expect(zahl("v") == nil)
        #expect(zahl("v3a") == nil)
        #expect(zahl("v1.2.3") == nil)
        #expect(zahl("") == nil)
        #expect(zahl("latest") == nil)
    }

    @Test("Die Antwort der Schnittstelle: nur die nötigen Felder, der Rest bleibt liegen")
    func antwortLesen() throws {
        let release = try lesen()
        #expect(release.tagName == "v33")
        #expect(release.build == 33)
        #expect(release.titel == "Unterrichtsplanung 1.2.3 (33)")
        #expect(release.seite?.host() == "github.com")
        #expect(release.seite?.path() == "/dk-3du/unterrichtsplanung/releases/tag/v33")
        #expect(release.veroeffentlicht != nil)
        #expect(release.notizen.hasPrefix("Erste Veröffentlichung"))
        #expect(!release.notizen.contains("\r"), "Zeilenenden vereinheitlicht")
        #expect(!release.notizen.hasSuffix("\n"))
        #expect(release.assets?.first?.digest?.hasPrefix("sha256:fe992191") == true)
        #expect(release.assets?.first?.size == 3_199_912)
    }

    @Test("Ohne Namen zählt das Tag; ohne HTTPS gibt es keine Seite")
    func ersatzwerte() {
        let ohne = Veroeffentlichung(tagName: "v40", name: "  ", htmlUrl: "http://example.org/x",
                                     body: nil, publishedAt: "kein Datum", assets: nil)
        #expect(ohne.titel == "v40")
        #expect(ohne.seite == nil, "nur HTTPS")
        #expect(ohne.veroeffentlicht == nil)
        #expect(ohne.notizen.isEmpty)
    }

    @Test("Der Befund: größer und nicht übersprungen heißt neu")
    func befund() throws {
        let v33 = try lesen()
        func mit(_ tag: String) -> Veroeffentlichung {
            Veroeffentlichung(tagName: tag, name: nil, htmlUrl: v33.htmlUrl, body: nil,
                              publishedAt: nil, assets: nil)
        }
        let befund = Updatepruefer.befund

        #expect(befund(v33, 33, nil) == .aktuell(v33))
        #expect(befund(v33, 34, nil) == .aktuell(v33), "eine neuere App als das Release")
        #expect(befund(v33, 32, nil) == .neu(v33))
        #expect(befund(mit("v34"), 33, 34) == .uebersprungen(mit("v34")))
        #expect(befund(mit("v35"), 33, 34) == .neu(mit("v35")),
                "ein späteres Release hebt das Überspringen auf")
        #expect(befund(mit("latest"), 33, nil) == .unlesbar)
    }

    @Test("Die Wochenfrist: nur mit Einwilligung, von Hand immer")
    func frist() {
        let jetzt = Date(timeIntervalSince1970: 1_800_000_000)
        let vorSechsTagen = jetzt.addingTimeInterval(-6 * 86_400)
        let vorSiebenTagen = jetzt.addingTimeInterval(-7 * 86_400)
        let faellig = Updatepruefer.faellig

        #expect(!faellig(false, nil, jetzt, false), "ohne Einwilligung nie")
        #expect(faellig(true, nil, jetzt, false), "erlaubt und nie geprüft")
        #expect(!faellig(true, vorSechsTagen, jetzt, false))
        #expect(faellig(true, vorSiebenTagen, jetzt, false))
        #expect(faellig(false, vorSechsTagen, jetzt, true), "von Hand: immer")
        #expect(faellig(true, jetzt.addingTimeInterval(3_600), jetzt, false),
                "eine Prüfung in der Zukunft — falsche Uhr — sperrt nicht")
    }

    @Test("Die Quelle: im Prüfstand nie das Netz, eine Datei nur als Datei")
    func quelle() {
        let quelle = Updatepruefer.quelle
        #expect(quelle([:], true) == nil)
        #expect(quelle([:], false) == Updatepruefer.schnittstelle)
        #expect(quelle(["UPDATE_QUELLE": ""], true) == nil, "leer zählt nicht")

        let datei = quelle(["UPDATE_QUELLE": "/tmp/antwort.json"], true)
        #expect(datei?.isFileURL == true)
        #expect(datei?.path() == "/tmp/antwort.json")
        #expect(quelle(["UPDATE_QUELLE": "file:///tmp/antwort.json"], true)?.path() == "/tmp/antwort.json")

        #expect(quelle(["UPDATE_QUELLE": "https://example.org/latest"], false) == Updatepruefer.schnittstelle,
                "eine Netzadresse aus der Umgebung wird übergangen — im Betrieb bleibt die Schnittstelle")
        #expect(quelle(["UPDATE_QUELLE": "https://example.org/latest"], true) == nil,
                "… und im Prüfstand bleibt es beim Nichts")
        #expect(quelle(["UPDATE_QUELLE": "antwort.json"], false) == Updatepruefer.schnittstelle,
                "ein relativer Pfad zählt nicht")
    }

    @Test("Aus einer Datei: derselbe Weg wie aus dem Netz, ohne Netz")
    func ausDatei() async throws {
        let datei = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(component: "antwort-\(UUID().uuidString).json")
        try antwortV33.write(to: datei)
        defer { try? FileManager.default.removeItem(at: datei) }

        let alt = Updatepruefer(quelle: datei, installiert: 32)
        let ergebnis = await alt.pruefen()
        #expect(ergebnis.befund == .neu(try lesen()))
        #expect(ergebnis.antwort == antwortV33)
        #expect(ergebnis.etag == nil, "eine Datei hat kein ETag")

        let gleich = Updatepruefer(quelle: datei, installiert: 33)
        #expect(await gleich.pruefen().befund == .aktuell(try lesen()))
    }

    @Test("Die Anfrage trägt genau: Accept, API-Fassung, User-Agent mit Build — sonst nichts")
    func anfrage() {
        let pruefer = Updatepruefer(quelle: Updatepruefer.schnittstelle, installiert: 34)
        let kopf = pruefer.anfrage.allHTTPHeaderFields ?? [:]
        #expect(kopf["Accept"] == "application/vnd.github+json")
        #expect(kopf["X-GitHub-Api-Version"] == "2022-11-28")
        #expect(kopf["User-Agent"] == "Unterrichtsplanung/34")
        #expect(kopf["Accept-Language"] == "de", "fest — nicht die Sprachen des Systems")
        #expect(kopf["If-None-Match"] == nil, "ohne gemerkte Antwort kein ETag")
        #expect(kopf.count == 4)
        #expect(pruefer.anfrage.timeoutInterval == Updatepruefer.zeitueberschreitung)

        var mitEtag = pruefer
        mitEtag.etag = "W/\"abc\""
        #expect(mitEtag.anfrage.allHTTPHeaderFields?["If-None-Match"] == nil,
                "ein ETag ohne die Antwort dazu hilft nicht — ein 304 wäre nicht zu deuten")
        mitEtag.gemerkt = antwortV33
        #expect(mitEtag.anfrage.allHTTPHeaderFields?["If-None-Match"] == "W/\"abc\"")
    }

    @Test("Die Sitzung: flüchtig, ohne Cookies, ohne Cache, ohne Warten aufs Netz — und eine für alle")
    func sitzung() {
        let eine = Updatepruefer(quelle: Updatepruefer.schnittstelle, installiert: 1)
        let andere = Updatepruefer(quelle: Updatepruefer.schnittstelle, installiert: 2)
        #expect(eine.sitzung === andere.sitzung, "je Prüfung eine neue Sitzung bliebe stehen")
        let konfiguration = Updatepruefer.sitzung().configuration
        #expect(konfiguration.httpShouldSetCookies == false)
        #expect(konfiguration.httpCookieAcceptPolicy == .never)
        #expect(konfiguration.urlCache == nil)
        #expect(konfiguration.waitsForConnectivity == false)
        #expect(konfiguration.timeoutIntervalForRequest == Updatepruefer.zeitueberschreitung)
    }

    // ── Antworten des Netzes, nachgestellt ─────────────────────────────────

    private func pruefer(_ name: String, installiert: Int = 32,
                         etag: String? = nil, gemerkt: Data? = nil) -> Updatepruefer {
        let konfiguration = URLSessionConfiguration.ephemeral
        konfiguration.protocolClasses = [Antwortstub.self]
        return Updatepruefer(quelle: URL(string: "https://stub.test/\(name)")!,
                             installiert: installiert, etag: etag, gemerkt: gemerkt,
                             sitzung: Updatepruefer.sitzung(konfiguration))
    }

    @Test("200: gelesen, verglichen, ETag und Antwort gemerkt")
    func antwort200() async throws {
        Antwortstub.antworten["https://stub.test/200"] =
            .init(status: 200, kopf: ["ETag": "W/\"neu\"", "Content-Type": "application/json"],
                  daten: antwortV33)
        let ergebnis = await pruefer("200").pruefen()
        #expect(ergebnis.befund == .neu(try lesen()))
        #expect(ergebnis.etag == "W/\"neu\"")
        #expect(ergebnis.antwort == antwortV33)
        #expect(Antwortstub.letzteAnfrage?.value(forHTTPHeaderField: "User-Agent")
                == "Unterrichtsplanung/32")
        #expect(Antwortstub.letzteAnfrage?.value(forHTTPHeaderField: "Accept-Language") == "de")
        #expect(Antwortstub.letzteAnfrage?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test("304: die gemerkte Antwort gilt weiter, das ETag bleibt")
    func antwort304() async throws {
        Antwortstub.antworten["https://stub.test/304"] = .init(status: 304, kopf: [:], daten: Data())
        let ergebnis = await pruefer("304", etag: "W/\"alt\"", gemerkt: antwortV33).pruefen()
        #expect(ergebnis.befund == .neu(try lesen()))
        #expect(ergebnis.etag == "W/\"alt\"")
        #expect(ergebnis.antwort == antwortV33)
        #expect(Antwortstub.letzteAnfrage?.value(forHTTPHeaderField: "If-None-Match") == "W/\"alt\"")
    }

    @Test("403 und Verbindungsfehler: nicht erreichbar, das Gemerkte bleibt")
    func nichtErreichbar() async {
        Antwortstub.antworten["https://stub.test/403"] = .init(status: 403, kopf: [:], daten: Data("{}".utf8))
        let gesperrt = await pruefer("403", etag: "W/\"alt\"", gemerkt: antwortV33).pruefen()
        #expect(gesperrt.befund == .nichtErreichbar)
        #expect(gesperrt.etag == "W/\"alt\"")
        #expect(gesperrt.antwort == antwortV33)

        let kein = await pruefer("nirgends", etag: "W/\"alt\"", gemerkt: antwortV33).pruefen()
        #expect(kein.befund == .nichtErreichbar)
        #expect(kein.antwort == antwortV33)
    }

    @Test("Kein JSON oder kein Tag im Schema: unlesbar, nichts gemerkt")
    func unlesbar() async {
        Antwortstub.antworten["https://stub.test/text"] =
            .init(status: 200, kopf: ["ETag": "W/\"x\""], daten: Data("<html>".utf8))
        let text = await pruefer("text").pruefen()
        #expect(text.befund == .unlesbar)
        #expect(text.etag == nil && text.antwort == nil)

        Antwortstub.antworten["https://stub.test/tag"] = .init(
            status: 200, kopf: [:],
            daten: Data(#"{"tag_name":"latest","html_url":"https://github.com/x"}"#.utf8))
        #expect(await pruefer("tag").pruefen().befund == .unlesbar)
    }
}

@Suite("Updates im Speicher")
@MainActor
struct UpdateSpeicherPruefungen {

    private func speicher() throws -> Planungsspeicher {
        let planung = Planung.leer(titel: "Updates", start: try #require(Tag(iso: "2026-08-10")),
                                   wochen: 6, basis: "",
                                   klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                                   fachfarben: [:])
        return Planungsspeicher(vorschau: planung)
    }

    private func ergebnis(_ befund: Updatebefund, etag: String? = "W/\"e\"") -> Updateergebnis {
        Updateergebnis(befund: befund, etag: etag, antwort: Data("{}".utf8))
    }

    @Test("Die Einwilligung: nie gefragt, dann ja oder nein — beides ist eine Antwort")
    func einwilligung() throws {
        let s = try speicher()
        #expect(!s.updatesGefragt && !s.updatesErlaubt)
        s.updatesErlauben(false)
        #expect(s.updatesGefragt && !s.updatesErlaubt)
        s.updatesErlauben(true)
        #expect(s.updatesGefragt && s.updatesErlaubt)
        #expect(!s.updateLaeuft, "im Prüfstand geht nichts ins Netz — auch nicht beim Einschalten")
    }

    @Test("Das eigene Blatt: nur für eine Planung, die es vor der Frage schon gab")
    func nachfrage() throws {
        let faellig = Planungsspeicher.updateNachfrageFaellig
        #expect(faellig(false, true, false, false), "Bestand, Ersteinrichtung vorbei, nie gefragt")
        #expect(!faellig(false, true, true, false), "die Ersteinrichtung fragt selbst")
        #expect(!faellig(false, false, false, false), "ohne Planung keine Frage")
        #expect(!faellig(false, true, false, true), "beantwortet ist beantwortet")
        #expect(!faellig(true, true, false, false), "nie im Prüfstand")

        let s = try speicher()
        s.updateNachfragePruefen()
        #expect(s.offenerDialog == nil, "im Prüflauf öffnet die Frage kein Blatt")
    }

    @Test("Neu: das Blatt kommt — und wartet, solange ein anderes liegt")
    func neu() throws {
        let s = try speicher()
        s.updateErgebnisUebernehmen(ergebnis(.neu(.probe)), erzwungen: false)
        #expect(s.update == .probe)
        #expect(s.offenerDialog == .update)
        #expect(s.updatestand.zuletzt != nil)
        #expect(s.updatestand.etag == "W/\"e\"")
        #expect(s.updatestand.antwort == Data("{}".utf8))

        s.updateSpaeter()
        #expect(s.update == nil)
        s.offenerDialog = .einstellungen
        s.updateErgebnisUebernehmen(ergebnis(.neu(.probe)), erzwungen: false)
        #expect(s.offenerDialog == .einstellungen, "nie über ein offenes Blatt hinweg")
        #expect(s.update == .probe)
        s.offenerDialog = nil
        s.updateAnzeigenPruefen()
        #expect(s.offenerDialog == .update)
    }

    @Test("Überspringen merkt den Build; von Hand wird es trotzdem gezeigt")
    func ueberspringen() throws {
        let s = try speicher()
        s.updateVorgeben(.probe)
        s.updateUeberspringen()
        #expect(s.update == nil)
        #expect(s.updatestand.uebersprungen == 99)
        #expect(Updatepruefer.befund(.probe, installiert: 34, uebersprungen: s.updatestand.uebersprungen)
                == .uebersprungen(.probe))

        s.updateErgebnisUebernehmen(ergebnis(.uebersprungen(.probe)), erzwungen: false)
        #expect(s.offenerDialog == nil && s.update == nil, "beim Öffnen bleibt es still")
        s.updateErgebnisUebernehmen(ergebnis(.uebersprungen(.probe)), erzwungen: true)
        #expect(s.offenerDialog == .update, "von Hand gefragt heißt: zeigen")
    }

    @Test("Aktuell und nicht erreichbar: still beim Öffnen, eine Meldung von Hand — das Ergebnis steht immer im Speicher")
    func meldungen() throws {
        let s = try speicher()
        #expect(s.updateMeldung == nil)
        s.updateErgebnisUebernehmen(ergebnis(.aktuell(.probe)), erzwungen: false)
        #expect(s.meldungen.isEmpty && s.offenerDialog == nil)
        #expect(s.updateMeldung?.contains("neuesten Stand") == true, "für die Einstellungen")
        s.updateErgebnisUebernehmen(ergebnis(.aktuell(.probe)), erzwungen: true)
        #expect(s.meldungen.last?.text.contains("neuesten Stand") == true)

        s.updateErgebnisUebernehmen(ergebnis(.nichtErreichbar, etag: nil), erzwungen: true)
        #expect(s.meldungen.last?.art == .warnung)
        #expect(s.updateMeldung == "Keine Verbindung zu GitHub.")
        #expect(s.updatestand.etag == "W/\"e\"", "eine gescheiterte Prüfung löscht nichts Gemerktes")
        #expect(s.updatestand.zuletzt != nil, "zählt aber als Prüfung — kein Nachbohren")
    }

    @Test("Die Prüfung beim Öffnen wartet auf die Planung — und läuft je Start nur einmal an")
    func beimStart() throws {
        let ohne = Planungsspeicher(vorschau: nil)
        #expect(!ohne.updatesBeimStartPruefen(), "ohne Planung nichts — die Freigabe läuft noch")
        #expect(!ohne.updatesBeimStartPruefen())

        let s = try speicher()
        #expect(s.updatesBeimStartPruefen(), "mit Planung angestoßen")
        #expect(!s.updatesBeimStartPruefen(), "ein zweites Mal im selben Start nicht")
    }

    @Test("Im Prüfstand geht auch der Befehl von Hand nicht ins Netz")
    func pruefstand() throws {
        let s = try speicher()
        s.updatesPruefen(erzwungen: true)
        #expect(!s.updateLaeuft)
        #expect(s.meldungen.last?.text.contains("Prüfstand") == true)
    }

    @Test("Was die Frage sagt, deckt sich mit dem, was die Anfrage trägt")
    func hinweis() {
        let hinweis = Updates.datenschutzhinweis
        for begriff in ["api.github.com", "IP-Adresse", "Versionsnummer", "ETag",
                        "keine Planungsdaten", "einmal je Woche"] {
            #expect(hinweis.contains(begriff), "fehlt: \(begriff)")
        }
        #expect(Veroeffentlichung.probe.build == 99)
        #expect(Updates.menuebefehl.hasPrefix("Nach Updates suchen"))
    }
}
