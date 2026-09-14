// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Der Formwächter gegen den Leser gehalten (N55-01, E77).
///
/// Der Wächter beantwortet dieselbe Frage wie der Leser: Liegt an dieser Stelle
/// Schutz? Zwei Erkenner derselben Sache dürfen nicht auseinanderlaufen — genau
/// daran krankte v55, und in derselben Klasse lag N54-02 („gibt es den Ordner?“).
/// Darum steht hier eine Fälle-Tabelle, die beide gegeneinander hält, statt
/// einzelner Prüfungen mit je eigener Erwartung.
@Suite("Formwächter")
struct FormwaechterPruefungen {

    // ── Das Feld der Fälle ────────────────────────────────────────────────

    /// Was der Leser der App über eine Datei sagt — die maßgebliche Antwort.
    enum Lesart: Equatable, Sendable {
        case keine
        case klartext
        /// Ein Behälter, den der Leser öffnen würde; die Kennung, unter der er liegt.
        case behaelter(String)
        case unlesbar
    }

    struct Fall: Sendable {
        let name: String
        /// Legt die Datei an und sagt, was der Leser darin sieht.
        let legen: @Sendable (URL, Tresor) throws -> Lesart
    }

    static let faelle: [Fall] = [
        Fall(name: "nichts liegt") { _, _ in .keine },
        Fall(name: "Klartext, kurz") { url, _ in
            try Data("{\"typ\":\"unterrichtsplanung\",\"titel\":\"offen\"}".utf8).write(to: url)
            return .klartext
        },
        Fall(name: "Klartext, länger als der Kopf") { url, _ in
            var text = "{\n  \"typ\" : \"unterrichtsplanung\",\n  \"vorhaben\" : [\n"
            while text.utf8.count < 3 * Ablage.formkopf { text += "    \"Reihe im Schuljahr\",\n" }
            text += "    \"Ende\"\n  ]\n}\n"
            try Data(text.utf8).write(to: url)
            return .klartext
        },
        Fall(name: "Klartext, der den Typnamen im Titel trägt") { url, _ in
            try Data("{\"typ\":\"unterrichtsplanung\",\"titel\":\"unterrichtsplanung-tresor\"}".utf8)
                .write(to: url)
            return .klartext
        },
        Fall(name: "Behälter, wie die App ihn schreibt") { url, tresor in
            try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage).write(to: url)
            return .behaelter(tresor.kennungHex)
        },
        Fall(name: "Behälter mit führendem Zeilenumbruch") { url, tresor in
            var daten = Data("\n".utf8)
            daten.append(try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage))
            try daten.write(to: url)
            return .behaelter(tresor.kennungHex)
        },
        Fall(name: "Behälter, neu gesetzt und sortiert") { url, tresor in
            let behaelter = try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
            let objekt = try JSONSerialization.jsonObject(with: behaelter)
            try JSONSerialization.data(withJSONObject: objekt, options: [.prettyPrinted, .sortedKeys])
                .write(to: url)
            return .behaelter(tresor.kennungHex)
        },
        Fall(name: "Behälter, dessen Kennung erst hinter dem Kopf steht") { url, tresor in
            // Ein Feld vor der Kennung schiebt sie aus den ersten Byte. Der Leser
            // deutet ihn weiterhin — und der Wächter muss dieselbe Kennung sehen,
            // sonst spricht er die Sitzung mit dem richtigen Schlüssel schuldig.
            let behaelter = try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
            let text = String(data: behaelter, encoding: .utf8)!
            let vorsatz = "{\"typ\":\"unterrichtsplanung-tresor\""
            #expect(text.hasPrefix(vorsatz), "der Vorsatz steht, wie die App ihn schreibt")
            let fuellung = ",\"notiz\":\"" + String(repeating: "x", count: Ablage.formkopf) + "\""
            try Data((vorsatz + fuellung + text.dropFirst(vorsatz.count)).utf8).write(to: url)
            return .behaelter(tresor.kennungHex)
        },
        Fall(name: "Behälter mit zwei Kennungen — es gilt die erste, für beide") { url, _ in
            let echt = Tresor.neu()
            let fremd = Tresor.neu()
            let behaelter = try echt.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
            let text = String(data: behaelter, encoding: .utf8)!
            let vorsatz = "{\"typ\":\"unterrichtsplanung-tresor\""
            let doppelt = vorsatz + ",\"schluesselkennung\":\"\(fremd.kennungHex)\""
                + text.dropFirst(vorsatz.count)
            try Data(doppelt.utf8).write(to: url)
            // Nachgemessen: Sowohl die Suche im Kopf als auch `kopfLesen` nehmen
            // den ersten Wert. Die Datei ist damit für jeden unbrauchbar — aber
            // Wächter und Leser sagen dasselbe, und darauf kommt es hier an.
            return .behaelter(fremd.kennungHex)
        },
        Fall(name: "Behälter unter einem fremden Schlüssel") { url, _ in
            let fremd = Tresor.neu()
            try fremd.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage).write(to: url)
            return .behaelter(fremd.kennungHex)
        },
        Fall(name: "Datei, die sich nicht öffnen lässt") { url, tresor in
            try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
            return .unlesbar
        },
        Fall(name: "keine reguläre Datei") { url, _ in
            #expect(mkfifo(url.path, 0o644) == 0)
            return .unlesbar
        },
        Fall(name: "größer als die Deutungsgrenze") { url, _ in
            try Data("{\"typ\":\"unterrichtsplanung\"".utf8).write(to: url)
            let griff = try FileHandle(forWritingTo: url)
            defer { try? griff.close() }
            try griff.truncate(atOffset: UInt64(Ablage.formgrenze) + 1)
            return .unlesbar
        },
    ]

    /// Was der Leser wirklich sagt — nicht, was die Tabelle behauptet.
    private func gelesen(_ url: URL, tresor: Tresor) -> Lesart {
        switch Ablage.gebundenLesen(url, hoechstens: Ablage.formgrenze) {
        case .keine: return .keine
        case .unlesbar, .zuGross: return .unlesbar
        case .daten(let roh):
            guard Tresor.istBehaelter(roh) else { return .klartext }
            guard let kopf = try? Tresor.kopfLesen(roh) else { return .unlesbar }
            return .behaelter(kopf.kennungHex)
        }
    }

    private func imOrdner(_ was: (URL, Tresor) throws -> Void) throws {
        let ordner = URL.temporaryDirectory.appending(component: "form-\(UUID().uuidString)",
                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer {
            let datei = ordner.appendingPathComponent("planung.json", isDirectory: false)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: datei.path)
            try? FileManager.default.removeItem(at: ordner)
        }
        try was(ordner, Tresor.neu())
    }

    // ── Die Zwillingsprobe ────────────────────────────────────────────────

    @Test("Wächter und Leser sagen dasselbe — über alle Fälle (E77)",
          arguments: FormwaechterPruefungen.faelle.indices)
    func zwillingsprobe(_ nummer: Int) throws {
        let fall = FormwaechterPruefungen.faelle[nummer]
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            let behauptet = try fall.legen(ablage.datei, tresor)
            let leser = gelesen(ablage.datei, tresor: tresor)
            #expect(leser == behauptet, Comment(rawValue: "\(fall.name): der Leser sagt \(leser)"))

            let ohne = Ablage.formwaechter(ablage.datei, tresor: nil)
            switch leser {
            case .keine, .klartext:
                #expect(ohne == nil, Comment(rawValue: "\(fall.name): hier darf geschrieben werden"))
            case .behaelter, .unlesbar:
                #expect(ohne != nil, Comment(rawValue: "\(fall.name): hier darf nichts geschrieben werden"))
            }

            // Mit einem Schlüssel: Nur der eigene Behälter geht durch.
            let mit = Ablage.formwaechter(ablage.datei, tresor: tresor)
            switch leser {
            case .keine, .klartext:
                #expect(mit == nil, Comment(rawValue: "\(fall.name): versiegeln darf man ihn"))
            case .behaelter(let kennung) where kennung == tresor.kennungHex:
                #expect(mit == nil, Comment(rawValue: "\(fall.name): der eigene Behälter"))
            case .behaelter, .unlesbar:
                #expect(mit != nil, Comment(rawValue: "\(fall.name): fremd oder ungewiss — nichts"))
            }
        }
    }

    @Test("Und keine Fassung der Tabelle ist versehentlich leer")
    func tabelleGefuellt() {
        #expect(FormwaechterPruefungen.faelle.count >= 13)
    }

    @Test("Der Wächter deutet so weit, wie die App ihre Ablage liest")
    func deutgrenzeDecktDieLesedecke() {
        // Sonst hielte er einen Stand für ungewiss, den die App gerade geladen
        // hat — und die Autosicherung stünde still, ohne dass etwas fehlt.
        #expect(Sicherungsdienst.lesedecke <= Ablage.formgrenze)
        #expect(Sicherungsdienst.schreibgrenze <= Ablage.formgrenze)
    }

    // ── Was daran hängt: der Schreibweg ───────────────────────────────────

    @Test("Ein umformatierter Behälter wird nicht durch Klartext ersetzt (N55-01 A)")
    func umformatierterBehaelterBleibt() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            var daten = Data("\n".utf8)
            daten.append(try tresor.versiegeln(Data("geheime Planung".utf8), inhalt: .planung, ziel: .ablage))
            try daten.write(to: ablage.datei)

            #expect(throws: Ablage.Formsperre.self) {
                try ablage.schreiben(Data("{\"titel\":\"jetzt offen\"}".utf8), tresor: nil)
            }
            #expect(try Data(contentsOf: ablage.datei) == daten, "Byte für Byte unberührt")
            // Der Leser öffnet ihn weiterhin — daran ändert der Wächter nichts.
            #expect(try tresor.oeffnen(try Data(contentsOf: ablage.datei))
                    == Data("geheime Planung".utf8))
            // Unter demselben Schlüssel darf geschrieben werden.
            #expect(throws: Never.self) { try ablage.schreiben(Data("neu".utf8), tresor: tresor) }
        }
    }

    @Test("Was sich nicht einsehen lässt, wird nicht ersetzt (N55-01 B)")
    func unlesbaresBleibt() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            let behaelter = try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
            try behaelter.write(to: ablage.datei)
            try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                                  ofItemAtPath: ablage.datei.path)

            #expect(throws: Ablage.Formsperre.self) {
                try ablage.schreiben(Data("Klartext".utf8), tresor: nil)
            }
            #expect(throws: Ablage.Formsperre.self) {
                try ablage.schreiben(Data("Klartext".utf8), tresor: tresor)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                  ofItemAtPath: ablage.datei.path)
            #expect(try Data(contentsOf: ablage.datei) == behaelter, "der Behälter liegt noch")
            #expect(!FileManager.default.fileExists(atPath: ablage.vorherigeFassung.path),
                    "und es wurde auch keine Fassung davor angelegt")
        }
    }

    @Test("Der Grund nennt die Datei und sagt, was zu tun ist")
    func grundIstBrauchbar() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
                .write(to: ablage.datei)
            try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                                  ofItemAtPath: ablage.datei.path)
            let grund = Ablage.formwaechter(ablage.datei, tresor: nil)?.grund ?? ""
            #expect(grund.contains("planung.json"), Comment(rawValue: grund))
            #expect(grund.contains("einsehen"), Comment(rawValue: grund))
            try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                  ofItemAtPath: ablage.datei.path)
        }
    }

    // ── Dieselbe Frage an den anderen beiden Stellen ──────────────────────

    @Test("Sitzpläne und Lesezeichen gehen durch denselben Wächter")
    func nebendateienEbenso() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            for (ziel, inhalt) in [(ablage.sitzplaene, Tresor.Inhalt.sitzplaene),
                                   (ablage.lesezeichen, Tresor.Inhalt.lesezeichen)] {
                var daten = Data("\n".utf8)
                daten.append(try tresor.versiegeln(Data("geheim".utf8), inhalt: inhalt, ziel: .ablage))
                try daten.write(to: ziel)
                #expect(Ablage.formwaechter(ziel, tresor: nil) != nil,
                        Comment(rawValue: "\(ziel.lastPathComponent): umformatierter Behälter"))

                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ziel.path)
                #expect(Ablage.formwaechter(ziel, tresor: tresor) != nil,
                        Comment(rawValue: "\(ziel.lastPathComponent): nicht einsehbar"))
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ziel.path)
            }
        }
    }
}
