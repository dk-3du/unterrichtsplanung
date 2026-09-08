// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Zugriff auf Orte außerhalb des Containers — über Lesezeichen mit
/// Sicherheitsbereich, die aus der Wahl des Nutzers entstehen (Auswahldialog,
/// Ziehen) und diese Wahl über Neustarts hinweg festhalten.
///
/// Im App Sandbox erreicht die App von sich aus nur ihren Container. Jede Wahl
/// des Nutzers gewährt den Zugriff für die laufende Sitzung; damit er den
/// Neustart übersteht, entsteht sofort ein Lesezeichen (`merken`). Ein
/// Lesezeichen auf einen Ordner deckt alles darunter ab. Die Lesezeichen liegen
/// in den Einstellungen im Container, nie in der Planungsdatei — sie gelten nur
/// für diese App auf diesem Mac; ein Prüflauf hält sie nur im Speicher.
///
/// Ohne Sandbox (das Prüfziel von `swift test`, ein ungesiegelter Bau) läuft
/// derselbe Code mit gewöhnlichen Lesezeichen: `mit` legt keinen
/// Sicherheitsbereich, und der Zugriff gelingt ohnehin.
@MainActor
enum Ordnerzugriff {

    /// Läuft die App im App Sandbox? Dann gilt: kein Zugriff ohne Wahl.
    static var imSandbox: Bool { Ablage.container != nil }

    /// Ein benannter Fehler — die Oberfläche macht daraus „erneut wählen“,
    /// nie ein stilles Scheitern.
    struct Fehler: Error, Equatable, Sendable {
        enum Art: Sendable { case keinLesezeichen, unaufloesbar, keinZugriff }
        let art: Art
        let pfad: String
        let text: String

        init(_ art: Art, pfad: String, grund: String = "") {
            self.art = art
            self.pfad = pfad
            let name = Pfade.dateiName(pfad)
            switch art {
            case .keinLesezeichen:
                text = "Auf „\(name)“ darf die App noch nicht zugreifen — der Ort wurde ihr "
                    + "in dieser Fassung noch nicht gezeigt."
            case .unaufloesbar:
                text = "„\(name)“ ließ sich nicht wiederfinden"
                    + (grund.isEmpty ? "." : " (\(grund)).")
            case .keinZugriff:
                text = "Der Zugriff auf „\(name)“ wurde nicht gewährt — bitte den Ort erneut wählen."
            }
        }
    }

    private static let schluessel = "unterrichtsplanung.lesezeichen"

    /// Der Vorrat der Sitzung, Schlüssel = kanonischer Pfad. Ein Prüflauf
    /// erbt nichts aus den Einstellungen und schreibt nichts hinein.
    private static var vorrat: [String: Data] = {
        guard !Ablage.istPruefstand,
              let gelesen = UserDefaults.standard.dictionary(forKey: schluessel) as? [String: Data]
        else { return [:] }
        return gelesen
    }()

    private static func ablegen() {
        guard !Ablage.istPruefstand else { return }
        if vorrat.isEmpty {
            UserDefaults.standard.removeObject(forKey: schluessel)
        } else {
            UserDefaults.standard.set(vorrat, forKey: schluessel)
        }
    }

    // ── Pfade ─────────────────────────────────────────────────────────────

    /// Die Form, in der ein Pfad als Schlüssel dient und verglichen wird:
    /// ohne `..`, ohne Endschrägstrich, Symlinks aufgelöst, soweit erreichbar.
    static func kanonisch(_ pfad: String) -> String { Ablage.vergleichbar(pfad) }

    private static func liegtUnter(_ pfad: String, _ ordner: String) -> Bool {
        pfad == ordner || pfad.hasPrefix(ordner + "/")
    }

    /// Das Lesezeichen, das für den Pfad gilt: genau dieser Ort oder der
    /// nächstliegende Ordner darüber. `nil` heißt: noch nie gewählt.
    static func zustaendig(fuer pfad: String) -> String? {
        let gesucht = kanonisch(pfad)
        var bester: String?
        for eintrag in vorrat.keys where liegtUnter(gesucht, eintrag) {
            if bester.map({ eintrag.count > $0.count }) ?? true { bester = eintrag }
        }
        return bester
    }

    /// Kommt die App an den Ort heran — über ein Lesezeichen, ohne Sandbox
    /// ohnehin, oder weil er ihr offensteht (Container, Systemordner)?
    static func erreichbar(_ pfad: String) -> Bool {
        guard imSandbox else { return true }
        if zustaendig(fuer: pfad) != nil { return true }
        return FileManager.default.isReadableFile(atPath: pfad)
    }

    static var alle: [String] { vorrat.keys.sorted() }

    // ── Anlegen und Vergessen ─────────────────────────────────────────────

    private static var erzeugen: URL.BookmarkCreationOptions {
        imSandbox ? [.withSecurityScope] : []
    }

    private static var lesen: URL.BookmarkResolutionOptions {
        imSandbox ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting]
    }

    /// Aus einer Wahl des Nutzers ein Lesezeichen anlegen. Liefert den
    /// Schlüssel. Wirft, wenn der Ort der App nicht offensteht — dann war es
    /// keine Wahl, sondern ein eingesetzter Pfad.
    @discardableResult
    static func merken(_ url: URL) throws -> String {
        let ziel = url.standardizedFileURL
        let daten: Data
        do {
            daten = try ziel.bookmarkData(options: erzeugen, includingResourceValuesForKeys: nil,
                                          relativeTo: nil)
        } catch {
            throw Fehler(.keinZugriff, pfad: ziel.path, grund: error.localizedDescription)
        }
        let eintrag = kanonisch(ziel.path)
        vorrat[eintrag] = daten
        ablegen()
        return eintrag
    }

    static func vergessen(_ pfad: String) {
        vorrat.removeValue(forKey: kanonisch(pfad))
        ablegen()
    }

    // ── Auflösen und Arbeiten ─────────────────────────────────────────────

    /// Das Lesezeichen zum Pfad und sein aufgelöstes Ziel — ein umbenannter
    /// oder verschobener Ordner wird still nachgeführt (`bookmarkDataIsStale`).
    /// Geliefert wird der Schlüssel, der gepasst hat: An ihm wird der Rest des
    /// Pfades abgetrennt, auch wenn das Ziel inzwischen anders heißt.
    private static func finden(_ pfad: String) throws -> (eintrag: String, ziel: URL) {
        guard let eintrag = zustaendig(fuer: pfad), let daten = vorrat[eintrag] else {
            throw Fehler(.keinLesezeichen, pfad: pfad)
        }
        var veraltet = false
        let ziel: URL
        do {
            ziel = try URL(resolvingBookmarkData: daten, options: lesen, relativeTo: nil,
                           bookmarkDataIsStale: &veraltet)
        } catch {
            throw Fehler(.unaufloesbar, pfad: pfad, grund: error.localizedDescription)
        }
        if veraltet { erneuern(eintrag, ziel: ziel) }
        return (eintrag, ziel)
    }

    /// Ein veraltetes Lesezeichen neu anlegen — im Bereich des alten, denn
    /// ohne ihn stünde der Ort im Sandbox nicht offen. Der neue Ort bekommt
    /// seinen Schlüssel, der alte bleibt als Zweitname stehen: Die
    /// Planungsdatei kennt weiterhin den alten Pfad. Misslingt es, bleibt das
    /// alte Lesezeichen; es löst weiterhin auf.
    private static func erneuern(_ eintrag: String, ziel: URL) {
        let offen = ziel.startAccessingSecurityScopedResource()
        defer { if offen { ziel.stopAccessingSecurityScopedResource() } }
        guard let neu = try? ziel.bookmarkData(options: erzeugen, includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        else { return }
        vorrat[eintrag] = neu
        vorrat[kanonisch(ziel.path)] = neu
        ablegen()
    }

    /// Der Pfad, wie er heute gilt: Zeigt das Lesezeichen inzwischen woanders
    /// hin, wandert der Rest des Pfades mit.
    private static func verlegt(_ pfad: String, eintrag: String, ziel: URL) -> URL {
        let gesucht = kanonisch(pfad)
        let rest = String(gesucht.dropFirst(eintrag.count))
        return URL(fileURLWithPath: kanonisch(ziel.path) + rest)
    }

    /// Wo der Pfad heute liegt — über sein Lesezeichen. Ohne Lesezeichen ein
    /// benannter Fehler.
    static func aufloesen(_ pfad: String) throws -> URL {
        let (eintrag, ziel) = try finden(pfad)
        return verlegt(pfad, eintrag: eintrag, ziel: ziel)
    }

    /// Die Arbeit im Sicherheitsbereich des zuständigen Lesezeichens — nur
    /// für genau diese Arbeit, nie über ein `await` hinweg, danach wieder
    /// geschlossen. Die Arbeit bekommt den nachgeführten Pfad.
    static func mit<T>(_ pfad: String, _ arbeit: (URL) throws -> T) throws -> T {
        let (eintrag, ziel) = try finden(pfad)
        let offen = ziel.startAccessingSecurityScopedResource()
        defer { if offen { ziel.stopAccessingSecurityScopedResource() } }
        if imSandbox, !offen { throw Fehler(.keinZugriff, pfad: pfad) }
        return try arbeit(verlegt(pfad, eintrag: eintrag, ziel: ziel))
    }
}
