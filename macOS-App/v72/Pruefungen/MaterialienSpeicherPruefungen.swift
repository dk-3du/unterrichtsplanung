// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Antworten ohne Netz: Der Stub beantwortet jede Adresse aus seiner Tabelle,
/// zählt die Anfragen und hält die letzte fest — für die Kopfzeilen.
private final class Materialstub: URLProtocol {
    struct Antwort { let status: Int; let kopf: [String: String]; let daten: Data }

    nonisolated(unsafe) static var antworten: [String: Antwort] = [:]
    nonisolated(unsafe) static var anfragen = 0
    nonisolated(unsafe) static var letzteAnfrage: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Materialstub.anfragen += 1
        Materialstub.letzteAnfrage = request
        guard let url = request.url, let antwort = Materialstub.antworten[url.absoluteString] else {
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

private let vorlagenordner = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Vorlagen")

private func liveVorlage() throws -> Data {
    try Data(contentsOf: vorlagenordner.appending(path: "inhalte-2026-09-17.js"))
}

private func stubSitzung() -> URLSession {
    let konfiguration = URLSessionConfiguration.ephemeral
    konfiguration.protocolClasses = [Materialstub.self]
    return Updatepruefer.sitzung(konfiguration)
}

@Suite("Materialliste: Lader und Quelle", .serialized)
struct MaterialladerPruefungen {

    private func lader(_ adresse: String = Materiallader.schnittstelle.absoluteString) -> Materiallader {
        Materiallader(quelle: URL(string: adresse)!, installiert: 71, sitzung: stubSitzung())
    }

    @Test("200 mit der Live-Vorlage: geladen — und die Anfrage trägt nur, was der Hinweis sagt")
    func geladen() async throws {
        Materialstub.antworten = [Materiallader.schnittstelle.absoluteString:
            .init(status: 200, kopf: ["Content-Type": "text/javascript"], daten: try liveVorlage())]
        Materialstub.anfragen = 0
        let befund = await lader().laden()
        guard case .geladen(let katalog) = befund else {
            Issue.record("Befund \(befund)")
            return
        }
        #expect(katalog.kategorien.count > 0 && katalog.uebergangen == 0)
        #expect(Materialstub.anfragen == 1)
        let anfrage = try #require(Materialstub.letzteAnfrage)
        #expect(anfrage.value(forHTTPHeaderField: "User-Agent") == "Unterrichtsplanung/71")
        #expect(anfrage.value(forHTTPHeaderField: "Accept")?.hasPrefix("text/javascript") == true)
        #expect(anfrage.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(anfrage.value(forHTTPHeaderField: "If-None-Match") == nil, "nichts gemerkt, nichts mitgebracht")
        #expect(anfrage.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(anfrage.timeoutInterval == Materiallader.zeitueberschreitung)
    }

    @Test("Kein Netz, 404, 500: nicht erreichbar")
    func nichtErreichbar() async {
        Materialstub.antworten = [:]
        #expect(await lader().laden() == .nichtErreichbar, "keine Verbindung")
        for status in [404, 500, 304] {
            Materialstub.antworten = [Materiallader.schnittstelle.absoluteString:
                .init(status: status, kopf: [:], daten: Data("const KATEGORIEN = [];".utf8))]
            #expect(await lader().laden() == .nichtErreichbar, "Status \(status)")
        }
    }

    @Test("Eine Antwort, die kein Katalog ist: unlesbar, mit dem Grund")
    func unlesbar() async {
        func mit(_ daten: Data, kopf: [String: String] = [:]) async -> Materialbefund {
            Materialstub.antworten = [Materiallader.schnittstelle.absoluteString:
                .init(status: 200, kopf: kopf, daten: daten)]
            return await lader().laden()
        }
        guard case .unlesbar(let grund) = await mit(Data("<html>Wartung</html>".utf8)) else {
            Issue.record("HTML müsste unlesbar sein"); return
        }
        #expect(grund.hasPrefix("Zeile 1"), Comment(rawValue: grund))
        #expect(await mit(Data([0x5B, 0xFF, 0x5D])) == .unlesbar(Materialkatalog.Fehler.keinUTF8.description))
        #expect(await mit(Data("{}".utf8)) == .unlesbar(Materialkatalog.Fehler.keineListe.description))
        let zuGross = await mit(Data(repeating: 0x20, count: 64),
                                kopf: ["Content-Length": String(Materialkatalog.hoechstens + 1)])
        guard case .unlesbar(let text) = zuGross else { Issue.record("zu groß müsste unlesbar sein"); return }
        #expect(text.contains("zu groß"), Comment(rawValue: text))
    }

    @Test("Die Quelle: MATERIAL_QUELLE nur als Datei, im Prüfstand sonst gar nicht")
    func quelle() {
        let quelle = Materiallader.quelle
        #expect(quelle([:], false) == Materiallader.schnittstelle)
        #expect(quelle([:], true) == nil, "kein Prüflauf geht ins Netz")
        #expect(quelle(["MATERIAL_QUELLE": "/tmp/inhalte.js"], true) == URL(fileURLWithPath: "/tmp/inhalte.js"))
        #expect(quelle(["MATERIAL_QUELLE": "file:///tmp/inhalte.js"], false)?.isFileURL == true)
        #expect(quelle(["MATERIAL_QUELLE": "https://example.org/inhalte.js"], true) == nil,
                "eine Webadresse in der Umgebung zählt nicht")
        #expect(quelle(["MATERIAL_QUELLE": ""], false) == Materiallader.schnittstelle)
    }

    @Test("Aus einer Datei: derselbe Weg ohne HTTP")
    func datei() async throws {
        let quelle = vorlagenordner.appending(path: "inhalte-synthetisch.js")
        let befund = await Materiallader(quelle: quelle, installiert: 0).laden()
        guard case .geladen(let katalog) = befund else { Issue.record("Befund \(befund)"); return }
        #expect(katalog.kategorien.count == 3 && katalog.uebergangen == 3)
        let fehlt = await Materiallader(quelle: vorlagenordner.appending(path: "gibt-es-nicht.js"),
                                        installiert: 0).laden()
        #expect(fehlt == .nichtErreichbar)
    }
}

@Suite("Materialliste im Speicher: Erlaubnis, Nachfrage, Ersteinrichtung")
@MainActor
struct MaterialienSpeicherPruefungen {

    private func speicher() throws -> Planungsspeicher {
        let planung = Planung.leer(titel: "Materialien", start: try #require(Tag(iso: "2026-08-10")),
                                   wochen: 6, basis: "",
                                   klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                                   fachfarben: [:])
        return Planungsspeicher(vorschau: planung)
    }

    @Test("Die Erlaubnis: nie gefragt, dann ja oder nein — beides ist eine Antwort")
    func erlaubnis() throws {
        let s = try speicher()
        #expect(!s.materialienGefragt && !s.materialienErlaubt)
        s.materialienErlauben(false)
        #expect(s.materialienGefragt && !s.materialienErlaubt)
        s.materialienErlauben(true)
        #expect(s.materialienGefragt && s.materialienErlaubt)
    }

    @Test("Ohne Erlaubnis keine Anfrage; im Prüfstand ohne Datei nicht erreichbar")
    func ohneErlaubnis() async throws {
        let s = try speicher()
        #expect(await s.materialkatalogLaden() == .keineErlaubnis)
        s.materialienErlauben(true)
        #expect(await s.materialkatalogLaden() == .nichtErreichbar, "im Prüflauf gibt es keine Quelle")
        // Mit Datei in der Umgebung liest der Koordinator sie — das ist der Weg des Prüfstands.
        let mitDatei = Materialkoordinator(
            pruefstand: true,
            umgebung: ["MATERIAL_QUELLE": vorlagenordner.appending(path: "inhalte-synthetisch.js").path])
        #expect(await mitDatei.laden() == .keineErlaubnis, "auch mit Datei erst nach der Antwort")
        mitDatei.erlauben(true)
        guard case .geladen(let katalog) = await mitDatei.laden() else { Issue.record("nicht geladen"); return }
        #expect(katalog.kategorien.count == 3)
    }

    @Test("Der Grund im Blatt: eine Zeile, höchstens 200 Zeichen, ohne Steuerzeichen")
    func einzelheit() {
        #expect(MaterialDialog.einzelheit("Zeile 1, Spalte 2: unerwartet") == "Einzelheit: Zeile 1, Spalte 2: unerwartet")
        let lang = MaterialDialog.einzelheit(String(repeating: "x", count: 5000))
        #expect(lang.count == "Einzelheit: ".count + 200 && lang.hasSuffix("…"))
        #expect(MaterialDialog.einzelheit("a\nb\u{202E}c") == "Einzelheit: a bc")
    }

    @Test("Die Erlaubnis gilt auch für das Ergebnis: während des Ladens entzogen, kommt keine Liste mehr an")
    func erlaubnisWaehrendDesLadensEntzogen() async throws {
        let quelle = vorlagenordner.appending(path: "inhalte-synthetisch.js")
        let koordinator = Materialkoordinator(pruefstand: true, umgebung: ["MATERIAL_QUELLE": quelle.path])
        koordinator.erlauben(true)
        // Der Lader entzieht die Erlaubnis, während er „lädt“ — so, wie es der
        // Schalter in den Einstellungen während einer langsamen Antwort täte.
        koordinator.lader = { url in
            let befund = await Materiallader(quelle: url, installiert: 0).laden()
            await MainActor.run { koordinator.erlauben(false) }
            return befund
        }
        #expect(await koordinator.laden() == .keineErlaubnis)
        koordinator.erlauben(true)
        koordinator.lader = { await Materiallader(quelle: $0, installiert: 0).laden() }
        guard case .geladen = await koordinator.laden() else { Issue.record("mit Erlaubnis wird geladen"); return }
    }

    @Test("Das eigene Blatt: nur für eine Planung, die es vor der Frage schon gab — nach der Update-Frage")
    func nachfrage() throws {
        let faellig = Planungsspeicher.materialNachfrageFaellig
        #expect(faellig(false, true, false, true, false), "Bestand, Ersteinrichtung vorbei, Updates beantwortet, nie gefragt")
        #expect(!faellig(false, true, false, false, false), "die Update-Frage kommt zuerst — als eigenes Blatt")
        #expect(!faellig(false, true, true, true, false), "die Ersteinrichtung fragt selbst")
        #expect(!faellig(false, false, false, true, false), "ohne Planung keine Frage")
        #expect(!faellig(false, true, false, true, true), "beantwortet ist beantwortet")
        #expect(!faellig(true, true, false, true, false), "nie im Prüfstand")

        let s = try speicher()
        s.updatesErlauben(false)
        s.materialNachfragePruefen()
        #expect(s.offenerDialog == nil, "im Prüflauf öffnet die Frage kein Blatt")
    }

    @Test("Die Ersteinrichtung stellt vier Fragen; die vierte schließt sie")
    func ersteinrichtung() throws {
        typealias Schritt = Planungsspeicher.Ersteinrichtungsschritt
        let s = try speicher()
        s.ersteinrichtungOeffnen()
        #expect(s.ersteinrichtungsschritt == Schritt.verschluesselung)
        s.ersteinrichtungUeberspringen()
        #expect(s.ersteinrichtungsschritt == Schritt.sicherung)
        s.ersteinrichtungZuUpdates()
        #expect(s.ersteinrichtungsschritt == Schritt.updates)
        s.ersteinrichtungUpdates(erlauben: false)
        #expect(s.updatesGefragt && !s.updatesErlaubt)
        #expect(s.ersteinrichtungsschritt == Schritt.materialien, "nach den Updates die Materialien")
        #expect(!s.materialienGefragt)
        s.ersteinrichtungMaterialien(erlauben: true)
        #expect(s.materialienGefragt && s.materialienErlaubt)
        // Wer beide Fragen beantwortet hat, bekommt kein Nachfrageblatt mehr.
        #expect(!Planungsspeicher.materialNachfrageFaellig(
            pruefstand: false, hatPlanung: true, ersteinrichtungFaellig: false,
            updateGefragt: s.updatesGefragt, gefragt: s.materialienGefragt))
    }

    @Test("Ein Klick hinterlegt, ein zweiter nimmt zurück — Bezeichnung ist der Kacheltitel (E179, E180)")
    func linkAufnehmenUndEntfernen() throws {
        let s = try speicher()
        var entwurf = VorhabenEntwurf(klasseId: try #require(s.planung?.klassen.first?.id), woche: 0)
        #expect(s.linkAufnehmen(titel: "Lernumgebung: Dichte", adresse: "https://3ducation.org/chemie/dichte.html",
                                in: &entwurf))
        #expect(entwurf.links.map(\.titel) == ["Lernumgebung: Dichte"])
        #expect(entwurf.links.map(\.adresse) == ["https://3ducation.org/chemie/dichte.html"])
        #expect(s.linkAufnehmen(titel: "noch einmal", adresse: "https://3ducation.org/chemie/dichte.html",
                                in: &entwurf), "dieselbe Adresse zählt als hinterlegt")
        #expect(entwurf.links.count == 1, "kein zweiter Eintrag")
        #expect(!s.linkAufnehmen(titel: "kaputt", adresse: "javascript:alert(1)", in: &entwurf),
                "die Schranke gilt auch hier")
        #expect(entwurf.links.count == 1)
        #expect(s.linkEntfernen(adresse: "https://3ducation.org/chemie/dichte.html", in: &entwurf))
        #expect(entwurf.links.isEmpty)
        #expect(!s.linkEntfernen(adresse: "https://3ducation.org/chemie/dichte.html", in: &entwurf),
                "nichts mehr da")
        // Die Höchstzahl: der 201. bleibt außen vor, mit Meldung.
        for i in 0..<Planungsdatei.maxLinks {
            #expect(s.linkAufnehmen(titel: "L\(i)", adresse: "https://example.org/\(i)", in: &entwurf))
        }
        let meldungenVorher = s.meldungen.count
        #expect(!s.linkAufnehmen(titel: "zu viel", adresse: "https://example.org/zuviel", in: &entwurf))
        #expect(entwurf.links.count == Planungsdatei.maxLinks)
        #expect(s.meldungen.count == meldungenVorher + 1, "genau eine Meldung")
        #expect(s.meldungen.last?.art == .warnung)
        #expect(s.meldungen.last?.text.contains("Höchstens \(Planungsdatei.maxLinks) Links") == true)
    }

    @Test("Bezeichnungen tragen keine Steuerzeichen — aus der Liste wie von Hand, Links wie Materialien")
    func bezeichnungenBereinigt() throws {
        let s = try speicher()
        var entwurf = VorhabenEntwurf(klasseId: try #require(s.planung?.klassen.first?.id), woche: 0)
        entwurf.titel = "Stunde"
        #expect(s.linkAufnehmen(titel: "Dichte\u{202E}fdp.exe\u{7}", adresse: "https://3ducation.org/x.html", in: &entwurf))
        #expect(entwurf.links.first?.titel == "Dichtefdp.exe", "schon im Entwurf bereinigt — so zeigt ihn der Dialog")
        // Von Hand: Der Dialog bindet die Bezeichnung unmittelbar an den Entwurf.
        entwurf.links.append(Weblink(titel: "Hand\u{2067}schrift\u{1}", adresse: "https://example.org/hand"))
        entwurf.materialien.append(Material(titel: "Blatt\u{202D} 1\u{7F}", pfad: "blatt.pdf"))
        entwurf.links.append(Weblink(titel: "مرحبا שלום", adresse: "https://example.org/rtl"))
        s.vorhabenSichern(entwurf)
        let gesichert = try #require(s.planung?.eintraege.first)
        #expect(gesichert.links.map(\.titel) == ["Dichtefdp.exe", "Handschrift", "مرحبا שלום"])
        #expect(gesichert.materialien.map(\.titel) == ["Blatt 1"])
        // Die Rundreise: Was die App schreibt, muss ihr Leser nicht mehr bereinigen.
        let planung = try #require(s.planung)
        let (gelesen, bilanz) = try Planungsdatei.lesenMitBilanz(try Planungsdatei.schreiben(planung))
        #expect(bilanz.bereinigteTexte == 0, "der Leser findet nichts zu bereinigen")
        #expect(gelesen.eintraege.first?.links.map(\.titel) == gesichert.links.map(\.titel))
        #expect(gelesen.eintraege.first?.materialien.map(\.titel) == gesichert.materialien.map(\.titel))
    }

    @Test("Eine Bezeichnung wird erst bereinigt, dann gekappt")
    func bezeichnungErstBereinigtDannGekappt() throws {
        let s = try speicher()
        var entwurf = VorhabenEntwurf(klasseId: try #require(s.planung?.klassen.first?.id), woche: 0)
        entwurf.titel = "Stunde"
        let lang = String(repeating: "\u{202E}", count: 10) + String(repeating: "a", count: Planungsdatei.maxNamenslaenge)
        entwurf.links.append(Weblink(titel: lang, adresse: "https://example.org/lang"))
        let vorher = s.meldungen.count
        s.vorhabenSichern(entwurf)
        #expect(s.planung?.eintraege.first?.links.first?.titel == String(repeating: "a", count: Planungsdatei.maxNamenslaenge))
        #expect(s.meldungen.count == vorher, "nichts gekürzt, also keine Meldung")
    }

    @Test("Das Material-Blatt öffnet und schließt mit dem Vorhaben-Blatt")
    func blattschalter() throws {
        let s = try speicher()
        #expect(!s.materialblattOffen)
        s.materialblattOffen = true
        s.alleDialogeSchliessen()
        #expect(!s.materialblattOffen, "alleDialogeSchliessen räumt auch den Bogen")
    }

    @Test("Was die Frage sagt, deckt sich mit dem, was die Anfrage trägt")
    func wortlaut() {
        let hinweis = Materialien.datenschutzhinweis
        #expect(hinweis.contains("3ducation.org"))
        #expect(hinweis.contains("IP-Adresse") && hinweis.contains("Versionsnummer der App"))
        #expect(hinweis.contains("keine Planungsdaten") && hinweis.contains("keine Cookies"))
        #expect(hinweis.contains("Gespeichert wird nichts"))
        #expect(hinweis.contains("Ausgeschaltet geht dafür nichts ins Netz"))
        let anfrage = Materiallader(quelle: Materiallader.schnittstelle, installiert: 71).anfrage
        #expect(anfrage.url?.host() == "3ducation.org")
        #expect(anfrage.allHTTPHeaderFields?.keys.sorted() == ["Accept", "Accept-Language", "User-Agent"],
                "nur diese drei Kopfzeilen — nichts, was der Hinweis nicht nennt")
        #expect(Materialien.worumEsGeht.contains("Ein Klick fügt einem Vorhaben das gewählte Material als Link direkt hinzu."))
    }
}
