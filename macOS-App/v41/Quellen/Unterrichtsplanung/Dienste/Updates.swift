// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Updates ───────────────────────────────────────────────────────────────
// Die App sieht — nur mit Einwilligung, höchstens einmal je Woche — nach, ob
// im Repository ein neueres Release liegt, und zeigt dann ein Blatt. Geladen
// und installiert wird nichts: Der Weg führt über die Release-Seite im Browser.
// Von Hand geht es jederzeit über „Nach Updates suchen …“.

/// Das jüngste veröffentlichte Release, wie die Schnittstelle es liefert
/// (`releases/latest` kennt weder Entwürfe noch Vorabversionen). Gelesen
/// wird nur, was das Blatt braucht; alles Übrige der Antwort bleibt liegen.
struct Veroeffentlichung: Codable, Equatable, Sendable {
    struct Anhang: Codable, Equatable, Sendable {
        let name: String
        let size: Int?
        let digest: String?
        let browserDownloadUrl: String?
    }

    let tagName: String
    let name: String?
    let htmlUrl: String
    let body: String?
    let publishedAt: String?
    let assets: [Anhang]?

    /// Die Zahl hinter dem `v` — das Tag-Schema ist `vNN` = Build der App.
    /// `nil`, wenn das Tag dem Schema nicht folgt; verglichen wird dann nicht.
    var build: Int? { Veroeffentlichung.build(aus: tagName) }

    static func build(aus tag: String) -> Int? {
        let bereinigt = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let erstes = bereinigt.first, erstes == "v" || erstes == "V" else { return nil }
        let ziffern = bereinigt.dropFirst()
        guard !ziffern.isEmpty, ziffern.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(ziffern)
    }

    /// Der Name des Release, ersatzweise das Tag.
    var titel: String {
        let bereinigt = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bereinigt.isEmpty ? tagName : bereinigt
    }

    /// Die Release-Seite — nur über HTTPS, sonst gar nicht.
    var seite: URL? {
        guard let url = URL(string: htmlUrl), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    var veroeffentlicht: Date? {
        publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// Die Release-Notizen mit einheitlichen Zeilenenden; leer, wenn keine da sind.
    var notizen: String {
        (body ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func lesen(_ daten: Data) throws -> Veroeffentlichung {
        let leser = JSONDecoder()
        leser.keyDecodingStrategy = .convertFromSnakeCase
        return try leser.decode(Veroeffentlichung.self, from: daten)
    }

    /// Für Abbilder und Prüfstände: ein Release, das es nicht gibt.
    static let probe = Veroeffentlichung(
        tagName: "v99",
        name: "Unterrichtsplanung 9.9 (99)",
        htmlUrl: "https://github.com/dk-3du/unterrichtsplanung/releases/tag/v99",
        body: "Eine erfundene Fassung für den Prüfstand.\n\n**Neu:** ein Blatt, das dieses "
            + "Release ankündigt — mit Notizen, Datum und dem Weg zur Release-Seite.\n"
            + "**Unverändert:** Dateiformat, Tresor, Ansicht.",
        publishedAt: "2026-12-24T10:00:00Z",
        assets: [Anhang(name: "Unterrichtsplanung-9.9-99.dmg", size: 3_200_000,
                        digest: nil, browserDownloadUrl: nil)])
}

/// Was eine Prüfung ergab.
enum Updatebefund: Equatable, Sendable {
    /// Nichts Neueres — mit dem Release, das die Schnittstelle nannte.
    case aktuell(Veroeffentlichung)
    case neu(Veroeffentlichung)
    /// Neuer, aber vom Nutzer übersprungen — von Hand wird es trotzdem gezeigt.
    case uebersprungen(Veroeffentlichung)
    /// Keine Verbindung, Zeitüberschreitung, eine andere Antwort als 200 oder 304.
    case nichtErreichbar
    /// Eine Antwort, die sich nicht lesen ließ — kein JSON, Tag außerhalb des Schemas.
    case unlesbar
}

/// Der Befund samt dem, was sich für die nächste Anfrage merken lässt: das
/// ETag und die Antwort dazu — mit `If-None-Match` antwortet GitHub bei
/// unverändertem Stand mit 304, und das zählt nicht gegen das Kontingent.
struct Updateergebnis: Equatable, Sendable {
    let befund: Updatebefund
    let etag: String?
    let antwort: Data?
}

/// Fragt die Quelle und vergleicht. Ohne Zustand im Speicher: Was zu merken
/// ist, kommt als Ergebnis zurück.
struct Updatepruefer: Sendable {
    static let schnittstelle =
        URL(string: "https://api.github.com/repos/dk-3du/unterrichtsplanung/releases/latest")!
    static let wochenfrist: TimeInterval = 7 * 24 * 60 * 60
    static let zeitueberschreitung: TimeInterval = 10

    let quelle: URL
    /// `CFBundleVersion` der laufenden App.
    let installiert: Int
    var uebersprungen: Int? = nil
    var etag: String? = nil
    /// Die Antwort zum ETag — ohne sie hilft ein 304 nichts.
    var gemerkt: Data? = nil
    var sitzung: URLSession = Updatepruefer.standardSitzung

    /// Eine Sitzung für alle Prüfungen — je Prüfung eine neue bliebe stehen,
    /// bis die App endet.
    static let standardSitzung = sitzung()

    /// Flüchtig und ohne Cookies: Die Anfrage soll nichts hinterlassen und
    /// nichts mitbringen.
    static func sitzung(_ konfiguration: URLSessionConfiguration = .ephemeral) -> URLSession {
        konfiguration.timeoutIntervalForRequest = zeitueberschreitung
        konfiguration.timeoutIntervalForResource = zeitueberschreitung * 2
        konfiguration.waitsForConnectivity = false
        konfiguration.httpCookieAcceptPolicy = .never
        konfiguration.httpShouldSetCookies = false
        konfiguration.urlCache = nil
        konfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: konfiguration)
    }

    /// Woher die Antwort kommt: `UPDATE_QUELLE` — nur eine Datei (`file:`-URL
    /// oder absoluter Pfad), für Prüfstand und Abbild —, sonst die
    /// Schnittstelle. Alles andere in der Umgebung wird übergangen. Im
    /// Prüfstand ohne Datei: gar nicht; keine Prüfung geht ins Netz.
    static func quelle(umgebung: [String: String], pruefstand: Bool) -> URL? {
        if let wert = umgebung["UPDATE_QUELLE"], !wert.isEmpty {
            if let url = URL(string: wert), url.isFileURL { return url }
            if wert.hasPrefix("/") { return URL(fileURLWithPath: wert) }
        }
        return pruefstand ? nil : schnittstelle
    }

    /// Beim Öffnen nur mit Einwilligung und nur, wenn die letzte Prüfung eine
    /// Woche zurückliegt — auch eine gescheiterte; von Hand immer.
    static func faellig(erlaubt: Bool, zuletzt: Date?, jetzt: Date = .now,
                        erzwungen: Bool) -> Bool {
        if erzwungen { return true }
        guard erlaubt else { return false }
        guard let zuletzt else { return true }
        // Eine Prüfung in der Zukunft — die Uhr stand falsch — sperrt nicht.
        if zuletzt > jetzt { return true }
        return jetzt.timeIntervalSince(zuletzt) >= wochenfrist
    }

    /// Größer als der eigene Build und nicht übersprungen ⇒ neu. Ein späteres
    /// Release hebt das Überspringen von selbst auf.
    static func befund(_ release: Veroeffentlichung, installiert: Int,
                       uebersprungen: Int?) -> Updatebefund {
        guard let build = release.build else { return .unlesbar }
        if build <= installiert { return .aktuell(release) }
        if build == uebersprungen { return .uebersprungen(release) }
        return .neu(release)
    }

    /// Was die Anfrage trägt — und damit alles, was übertragen wird: die
    /// Fassung der App im User-Agent, das ETag der letzten Antwort. Die
    /// Sprache steht fest, sonst setzte `URLSession` die des Systems ein.
    var anfrage: URLRequest {
        var anfrage = URLRequest(url: quelle)
        anfrage.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        anfrage.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        anfrage.setValue("Unterrichtsplanung/\(installiert)", forHTTPHeaderField: "User-Agent")
        anfrage.setValue("de", forHTTPHeaderField: "Accept-Language")
        if let etag, gemerkt != nil {
            anfrage.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        anfrage.cachePolicy = .reloadIgnoringLocalCacheData
        anfrage.timeoutInterval = Updatepruefer.zeitueberschreitung
        return anfrage
    }

    /// Wirft nie — jeder Fehler ist ein Befund. Bei einer Datei als Quelle
    /// gibt es keinen HTTP-Status: gelesen wird, was da ist.
    func pruefen() async -> Updateergebnis {
        let daten: Data
        let antwort: URLResponse
        do {
            (daten, antwort) = try await sitzung.data(for: anfrage)
        } catch {
            return Updateergebnis(befund: .nichtErreichbar, etag: etag, antwort: gemerkt)
        }

        var neuesEtag = etag
        var inhalt = daten
        if let http = antwort as? HTTPURLResponse {
            switch http.statusCode {
            case 200:
                neuesEtag = http.value(forHTTPHeaderField: "ETag")
            case 304:
                guard let gemerkt else {
                    return Updateergebnis(befund: .nichtErreichbar, etag: nil, antwort: nil)
                }
                inhalt = gemerkt
            default:
                return Updateergebnis(befund: .nichtErreichbar, etag: etag, antwort: gemerkt)
            }
        }
        guard let release = try? Veroeffentlichung.lesen(inhalt) else {
            return Updateergebnis(befund: .unlesbar, etag: nil, antwort: nil)
        }
        return Updateergebnis(
            befund: Updatepruefer.befund(release, installiert: installiert,
                                         uebersprungen: uebersprungen),
            etag: neuesEtag, antwort: inhalt)
    }
}

/// Was die Oberfläche über die laufende App und die Prüfung sagt.
enum Updates {
    static let menuebefehl = "Nach Updates suchen …"

    /// `CFBundleVersion` der laufenden App — 0 außerhalb eines Pakets.
    static var installierterBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// „1.2.4 (34)“ — wie der Über-Dialog; außerhalb eines Pakets (Prüflauf)
    /// ohne Zahlen.
    static var installierteFassung: String {
        let angaben = Bundle.main.infoDictionary
        guard let fassung = angaben?["CFBundleShortVersionString"] as? String,
              let stufe = angaben?["CFBundleVersion"] as? String else { return "diese Fassung" }
        return "\(fassung) (\(stufe))"
    }

    /// Steht wörtlich in der Frage der Ersteinrichtung, im eigenen Blatt für
    /// bestehende Planungen und unter „Einstellungen“ — der Grund, warum die
    /// Prüfung eine Einwilligung braucht.
    static let datenschutzhinweis =
        "Die Prüfung ist eine Anfrage an api.github.com (GitHub, Inc., USA), höchstens "
        + "einmal je Woche. Übertragen werden dabei die IP-Adresse dieses Rechners, die "
        + "Versionsnummer der App und das Kennzeichen der zuletzt gesehenen Antwort "
        + "(ETag) — sonst nichts: keine Planungsdaten, keine Gerätekennung, keine Cookies. "
        + "Ausgeschaltet geht beim Öffnen nichts ins Netz."
}
