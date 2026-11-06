// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Unterrichtsplanung

private typealias Tag = Unterrichtsplanung.Tag

// ── Behebungen der externen Review v86 → v89 (v90, BB5; E982) ──
// R89-02: Ein Ziehen „von innen“ wird an der Quelle erkannt — einer eigenen Kachel —, nicht am Typ auf der Zwischenablage.
// R89-04 mit B: Lesezeichen nur für Dateien, die wirklich aufgenommen werden; fehlt der dauerhafte Zugriff, sagt es eine
// Warnung — auf der Kachel wie im Blatt. R89-06: `runde.py` beendet eine Probe über die Frist, ohne `pkill -f`. A: Der Satz zur
// bestätigten Löschung im Archiv verspricht, was geschieht. Den Weg vom Raster her prüft die Klickprobe (`klick`).

@Suite("v90 BB5: Behebungen der externen Review (R89-02, R89-04 mit B, R89-06, A)")
@MainActor
struct ExterneReviewPruefungen {

    private static let verweis = NSPasteboard.PasteboardType(UTType.vorhabenverweis.identifier)
    private static let ohneZugriff = "der dauerhafte Zugriff ließ sich aber nicht sichern — nach einem Neustart fragt die App "
        + "beim Öffnen danach."

    @Test("R89-02: Von innen ist nur ein Ziehen von einer eigenen Kachel mit dem Verweis — fremd mit demselben Typ ist von außen")
    func vonInnenNurVonDerKachel() {
        let kachel = Kachelansicht(frame: .zero)
        #expect(!Rasterkoordinator.vonAussen(quelle: kachel, typen: [Self.verweis]), "von der eigenen Kachel")
        #expect(Rasterkoordinator.vonAussen(quelle: nil, typen: [Self.verweis]), "fremd, auch mit dem Typ der Vorhaben")
        #expect(Rasterkoordinator.vonAussen(quelle: NSView(), typen: [Self.verweis]), "eine andere Ansicht ist keine Kachel")
        #expect(Rasterkoordinator.vonAussen(quelle: kachel, typen: [.fileURL]), "von der Kachel, aber ohne Verweis")
        #expect(Rasterkoordinator.vonAussen(quelle: nil, typen: [.fileURL, .URL]), "aus Finder oder Safari")
    }

    // ── R89-04 mit B ──

    /// Ein eigener Ordner mit echten Dateien — für sie gelingt ein Lesezeichen, für erfundene Pfade nicht.
    private static func ordner() throws -> URL {
        let ziel = URL.temporaryDirectory.appending(component: "bb5-ablegen-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private static func datei(_ ordner: URL, _ name: String) throws -> URL {
        let ziel = ordner.appending(component: name)
        try Data("Probe".utf8).write(to: ziel)
        return ziel
    }

    private static func planung(basis: String, materialien: [Material] = []) throws -> Planung {
        var planung = Planung.leer(
            titel: "Ablegen", start: try #require(Tag(iso: "2026-08-10")), wochen: 8,
            basis: basis, klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let a = planung.klassen[0].id
        planung.eintraege = [
            Vorhaben(id: "e1", klasseId: a, woche: 2, titel: "Photosynthese", text: "",
                     erledigt: false, materialien: materialien, links: []),
            Vorhaben(id: "e2", klasseId: a, woche: 3, titel: "Zellatmung", text: "",
                     erledigt: false, materialien: materialien, links: []),
        ]
        return planung
    }

    private static func schluessel(_ url: URL) -> String { Ordnerzugriff.kanonisch(url.standardizedFileURL.path) }

    @Test("R89-04: Lesezeichen fürs Aufgenommene und schon Verknüpfte (frischt auf, Z-BB5-02), nicht fürs über der Grenze")
    func lesezeichenNurFuerAufgenommene() throws {
        let o = try Self.ordner()
        defer { try? FileManager.default.removeItem(at: o) }
        let a = try Self.datei(o, "a.pdf"), b = try Self.datei(o, "b.pdf"), c = try Self.datei(o, "c.pdf")
        let speicher = Planungsspeicher(vorschau: try Self.planung(basis: o.path, materialien: [Material(titel: "a.pdf",
                                                                                                         pfad: "a.pdf")]))
        let vorher = Set(speicher.zugriff.alle)
        #expect(speicher.ablegen(dateien: [a, b], links: [], auf: "e1"))
        let nachKachel = Set(speicher.zugriff.alle).subtracting(vorher)
        // a war schon verknüpft — erneut gezogen, frischt es sein Lesezeichen auf (der Weg, einen verlorenen Zugriff zu holen).
        #expect(nachKachel == [Self.schluessel(a), Self.schluessel(b)], "neu und aufgefrischt: \(nachKachel.sorted())")
        var entwurf = VorhabenEntwurf(try #require(speicher.planung?.eintraege.first { $0.id == "e2" }))
        #expect(speicher.materialAufnehmen([a.path, c.path], in: &entwurf) == 1)
        let nachBlatt = Set(speicher.zugriff.alle).subtracting(vorher)
        #expect(nachBlatt == [Self.schluessel(a), Self.schluessel(b), Self.schluessel(c)], "im Blatt ebenso: \(nachBlatt.sorted())")
        #expect(!speicher.meldungen.contains { $0.text.contains("dauerhafte Zugriff") }, "gelungen — keine Warnung")
        // NF-07 d: ein Ordner als Material bekommt sein Lesezeichen ebenso über die Aufnahme.
        let mappe = o.appending(component: "Mappe", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mappe, withIntermediateDirectories: true)
        #expect(speicher.materialAufnehmen([mappe.path], in: &entwurf) == 1)
        #expect(speicher.zugriff.alle.contains(Self.schluessel(mappe)), "der Ordner im Vorrat")
        // Über der Grenze bleibt eine Datei außen vor — und bekommt kein Lesezeichen (R89-04).
        let d = try Self.datei(o, "d.pdf")
        let voll = (0..<Planungsdatei.maxMaterialien).map { Material(titel: "M\($0)", pfad: "M\($0).pdf") }
        let speicherVoll = Planungsspeicher(vorschau: try Self.planung(basis: o.path, materialien: voll))
        _ = speicherVoll.ablegen(dateien: [d], links: [], auf: "e1")
        #expect(!speicherVoll.zugriff.alle.contains(Self.schluessel(d)), "außen vor — ohne Lesezeichen")
    }

    @Test("R89-04 mit B: Fehlt der dauerhafte Zugriff, ist die Datei verknüpft und eine Warnung sagt es — Einzahl und Mehrzahl")
    func warnungOhneDauerhaftenZugriff() throws {
        let o = try Self.ordner()
        defer { try? FileManager.default.removeItem(at: o) }
        let a = try Self.datei(o, "a.pdf"), b = try Self.datei(o, "b.pdf"), c = try Self.datei(o, "c.pdf")
        let speicher = Planungsspeicher(vorschau: try Self.planung(basis: o.path))
        // Der Vorrat zu — wie wenn sich kein Lesezeichen anlegen lässt.
        speicher.zugriff.schliessen()
        #expect(speicher.ablegen(dateien: [a], links: [], auf: "e1"))
        #expect(speicher.planung?.eintraege.first { $0.id == "e1" }?.materialien.map(\.pfad) == ["a.pdf"], "verknüpft")
        let einzahl = "„a.pdf“ ist verknüpft, " + Self.ohneZugriff
        #expect(speicher.meldungen.last.map { $0.art == .warnung && $0.text == einzahl } == true,
                "\(speicher.meldungen.last?.text ?? "—")")
        var entwurf = VorhabenEntwurf(try #require(speicher.planung?.eintraege.first { $0.id == "e2" }))
        #expect(speicher.materialAufnehmen([b.path, c.path], in: &entwurf) == 2)
        // Die Mehrzahl sagt, für wie viele der Zugriff fehlt (Z-BB5-03) — die Bestätigung davor ist im Blatt schon fort (E856).
        let mehrzahl = "Für 2 der verknüpften Materialien ließ sich der dauerhafte Zugriff nicht sichern — nach einem Neustart "
            + "fragt die App beim Öffnen danach."
        // Die Dateien liegen im temporären Ordner — im Blatt steht dann der fremde Ort vorn, der Zugriff kurz (Z-BB8-W3-01);
        // die lange Mehrzahl sagen die Kachel und das Blatt ohne fremden Ort.
        #expect(speicher.meldungen.last.map { $0.art == .warnung
            && $0.text.hasSuffix(" Für 2 Materialien fehlt der dauerhafte Zugriff.") } == true,
                "\(speicher.meldungen.last?.text ?? "—")")
        #expect(Planungsspeicher.zugriffSatz([b.path, c.path]) == mehrzahl)
        // Unter einem erfundenen Pfad liegt nichts — dort gibt es keinen Zugriff zu sichern, also keine Warnung dazu.
        let anzahl = speicher.meldungen.count { $0.text.contains("dauerhafte Zugriff") }
        #expect(speicher.materialAufnehmen([o.appending(component: "fehlt.pdf").path], in: &entwurf) == 1)
        #expect(speicher.meldungen.count { $0.text.contains("dauerhafte Zugriff") } == anzahl)
        // Z-BB8-W3-08: ein Ordner als Material — auch sein Lesezeichen kommt nur über die Aufnahme, und es fehlt hier.
        let mappe = o.appending(component: "Mappe", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mappe, withIntermediateDirectories: true)
        #expect(speicher.materialAufnehmen([mappe.path], in: &entwurf) == 1)
        #expect(speicher.meldungen.last.map { $0.art == .warnung && $0.text.contains("„Mappe“")
            && $0.text.contains("dauerhafte Zugriff") } == true, "\(speicher.meldungen.last?.text ?? "—")")
    }

    @Test("Z-BB8-W3-01: die Warnung im Blatt — fremder Ort zuerst, der Zugriff kurz; ohne fremden Ort die lange Form")
    func blattWarnungRegel() {
        let pfad = "/Benutzer/x/a.pdf"
        #expect(Planungsspeicher.blattWarnung(fremd: nil, ohneZugriff: []) == nil)
        #expect(Planungsspeicher.blattWarnung(fremd: "F.", ohneZugriff: []) == "F.")
        #expect(Planungsspeicher.blattWarnung(fremd: nil, ohneZugriff: [pfad]) == Planungsspeicher.zugriffSatz([pfad]))
        #expect(Planungsspeicher.blattWarnung(fremd: "F.", ohneZugriff: [pfad])
                == "F. Für ein Material fehlt der dauerhafte Zugriff.")
        #expect(Planungsspeicher.blattWarnung(fremd: "F.", ohneZugriff: [pfad, pfad + "2"])
                == "F. Für 2 Materialien fehlt der dauerhafte Zugriff.")
    }

    @Test("Z-BB5-04: Im Blatt stehen fremder Ort und fehlender Zugriff in einer Meldung — keine verdrängt die andere (E856)")
    func blattEinSatz() throws {
        let o = try Self.ordner()
        defer { try? FileManager.default.removeItem(at: o) }
        let mail = o.appending(component: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
                               directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mail, withIntermediateDirectories: true)
        let anhang = try Self.datei(mail, "anhang.pdf")
        let speicher = Planungsspeicher(vorschau: try Self.planung(basis: o.path))
        speicher.zugriff.schliessen()
        var entwurf = VorhabenEntwurf(try #require(speicher.planung?.eintraege.first { $0.id == "e1" }))
        #expect(speicher.materialAufnehmen([anhang.path], in: &entwurf) == 1)
        // Der fremde Ort zuerst, der Zugriff kurz — so passt beides in die zwei Zeilen der Meldung (Z-BB8-W3-01, E487;
        // am Abbild mit 620 pt Breite stehen 176 Zeichen ganz in zwei Zeilen, 23:42).
        let erwartet = "„anhang.pdf“ liegt im Download-Ordner von Mail und kann dort verschwinden — sicherer zuerst im "
            + "Finder sichern und neu verknüpfen. Für ein Material fehlt der dauerhafte Zugriff."
        #expect(speicher.meldungen.last.map { $0.art == .warnung && $0.text == erwartet } == true,
                "\(speicher.meldungen.last?.text ?? "—")")
        #expect(erwartet.count <= 176)
    }

    // ── R89-06 und A ──

    @Test("R89-06: Die Runde beendet eine Probe über die Frist von `subprocess.run` — kein `pkill -f` mit dem Pfad als Muster")
    func rundeOhnePkill() throws {
        let fassung = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let runde = fassung.appending(component: "runde.py")
        let text = try String(contentsOf: runde, encoding: .utf8)
        // Hinter dem Docstring des Moduls — dort nennt der Kopf die Werkzeuge; jede Form zählt (Z-BB5-05).
        let teile = text.components(separatedBy: "\"\"\"")
        try #require(teile.count >= 3, "runde.py beginnt mit einem Docstring")
        #expect(!teile.dropFirst(2).joined().contains("pkill"), "runde.py ruft pkill auf")
        // Z-BB8-W3-08, NF-04: Jeder Start der Probe trägt eine Frist — `subprocess.run([app` und `befehl(app`, jeweils bis
        // zur schließenden Klammer des Aufrufs gelesen.
        func aufruf(_ rest: String) -> String {
            var tiefe = 1, ende = rest.endIndex
            for i in rest.indices {
                if rest[i] == "(" { tiefe += 1 } else if rest[i] == ")" { tiefe -= 1; if tiefe == 0 { ende = i; break } }
            }
            return String(rest[..<ende])
        }
        let code = teile.dropFirst(2).joined()
        let starts = ["subprocess.run([app", "befehl(app"].flatMap { code.components(separatedBy: $0).dropFirst() }
        #expect(starts.count >= 3 && starts.allSatisfy { aufruf($0).contains("timeout=") }, "jeder Start der Probe mit timeout=")
    }

    @Test("A: Die bestätigte Löschung im Archiv — der Satz sagt, wann sie geschieht")
    func archivSatz() {
        #expect(Planungsspeicher.archivEndgueltig
                == "Das geschieht gleich nach dieser Frage, unabhängig von „Übernehmen“, und lässt sich nicht widerrufen.")
    }
}
