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
        Fall(name: "Behälter mit einer Kennung in einem eingebetteten Objekt davor") { url, tresor in
            // N56-01: Eine Zeichensuche fände die eingebettete Kennung zuerst;
            // der Leser nimmt die oberste. Zwei Erkenner, zwei Antworten.
            let behaelter = try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
            let text = String(data: behaelter, encoding: .utf8)!
            let vorsatz = "{\"typ\":\"unterrichtsplanung-tresor\""
            #expect(text.hasPrefix(vorsatz), "der Vorsatz steht, wie die App ihn schreibt")
            let fremd = Tresor.neu().kennungHex
            try Data((vorsatz + ",\"meta\":{\"schluesselkennung\":\"\(fremd)\"}"
                      + text.dropFirst(vorsatz.count)).utf8).write(to: url)
            return .behaelter(tresor.kennungHex)
        },
        Fall(name: "Behälter mit einer eingebetteten Kennung dahinter") { url, tresor in
            // Die Gegenprobe zur Zeile darüber: Wer „die letzte“ nähme, läge
            // hier falsch. Maßgeblich ist die oberste, nicht die nächstbeste.
            let behaelter = try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
            let text = String(data: behaelter, encoding: .utf8)!
            let fremd = Tresor.neu().kennungHex
            let schluss = "\"}\n"
            #expect(text.hasSuffix(schluss))
            try Data((text.dropLast(schluss.count) + "\",\"meta\":{\"schluesselkennung\":\"\(fremd)\"}}\n").utf8)
                .write(to: url)
            return .behaelter(tresor.kennungHex)
        },
        Fall(name: "Behälter mit zwei Kennungen im Kopf — der Deuter entscheidet") { url, tresor in
            // Die Abkürzung weicht aus; maßgeblich ist, was `kopfLesen` sagt.
            let behaelter = try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
            let text = String(data: behaelter, encoding: .utf8)!
            let feld = "\"schluesselkennung\":\"\(tresor.kennungHex)\""
            #expect(text.contains(feld))
            let fremd = Tresor.neu().kennungHex
            try Data(text.replacingOccurrences(
                of: feld, with: feld + ",\"schluesselkennung\":\"\(fremd)\"").utf8).write(to: url)
            return .behaelter(tresor.kennungHex)
        },
        Fall(name: "größer als die Deutungsgrenze") { url, _ in
            try Data("{\"typ\":\"unterrichtsplanung\"".utf8).write(to: url)
            let griff = try FileHandle(forWritingTo: url)
            defer { try? griff.close() }
            try griff.truncate(atOffset: UInt64(Ablage.formgrenze) + 1)
            return .unlesbar
        },

        // ── Was der Leser aus strukturellen Gründen abweist (N57-01) ───────
        // Bis hierher hieß „unlesbar“ immer: Das Betriebssystem gibt die Datei
        // nicht her (Rechte, kein regulärer Knoten, zu groß). Diese vier weist
        // der **Leser** ab, obwohl ihr Kopf aussieht wie der eigene — und genau
        // dort gab die Abkürzung sie zum Ersetzen frei. Erkennen ist nicht
        // Erlauben.
        Fall(name: "Behälter aus einer neueren Fassung") { url, tresor in
            try FormwaechterPruefungen.neuereFassung(tresor).write(to: url)
            return .unlesbar
        },
        Fall(name: "Behälter aus einer neueren Fassung, umformatiert") { url, tresor in
            // Dieselbe Datei, anders gesetzt: Das Urteil darf sich davon nicht
            // ändern — in v57 sperrte nur dieser Weg, der kanonische nicht.
            var daten = Data("\n".utf8)
            daten.append(try FormwaechterPruefungen.neuereFassung(tresor))
            try daten.write(to: url)
            return .unlesbar
        },
        Fall(name: "Behälter, abgeschnitten hinter der Kennung") { url, tresor in
            let text = try FormwaechterPruefungen.alsText(tresor)
            let feld = "\"schluesselkennung\":\"\(tresor.kennungHex)\""
            let stelle = try #require(text.range(of: feld))
            try Data(text[text.startIndex..<stelle.upperBound].utf8).write(to: url)
            return .unlesbar
        },
        Fall(name: "Behälter mit unbekanntem Verfahren") { url, tresor in
            let text = try FormwaechterPruefungen.alsText(tresor)
            let neu = text.replacingOccurrences(of: "\"verfahren\":\"\(Tresor.verfahren)\"",
                                                with: "\"verfahren\":\"unbekannt\"")
            #expect(neu != text, "das Verfahren steht, wo es erwartet wird")
            try Data(neu.utf8).write(to: url)
            return .unlesbar
        },

        // ── Anders geschrieben, aber derselbe Behälter (B28, E107) ─────────
        // Bis v59 schnüffelte `istBehaelter` an Byte: Vorsatz, 64-Byte-Fenster,
        // Zeichensuche nach dem Typnamen. Diese drei öffnet der Leser ohne
        // Murren — und der Erkenner nannte sie Klartext, der ersetzt werden
        // darf. Die Ansicht deutet seit je zuerst und fragt dann `typ`.
        Fall(name: "Behälter mit Byte-Reihenfolgemarke davor") { url, tresor in
            var daten = Data([0xEF, 0xBB, 0xBF])
            daten.append(try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage))
            try daten.write(to: url)
            return .behaelter(tresor.kennungHex)
        },
        Fall(name: "Behälter hinter mehr als 64 Byte Leerraum") { url, tresor in
            var daten = Data(String(repeating: " \n", count: 48).utf8)
            daten.append(try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage))
            try daten.write(to: url)
            return .behaelter(tresor.kennungHex)
        },
        Fall(name: "Behälter, dessen Typname in Ausweichschreibung steht") { url, tresor in
            let text = try FormwaechterPruefungen.alsText(tresor)
            let neu = text.replacingOccurrences(of: "\"typ\":\"unterrichtsplanung-tresor\"",
                                                with: "\"typ\":\"\\u0075nterrichtsplanung-tresor\"")
            #expect(neu != text, "der Typ steht, wo er erwartet wird")
            try Data(neu.utf8).write(to: url)
            return .behaelter(tresor.kennungHex)
        },

        // ── Was sich nicht deuten lässt, ist kein Klartext (N57-01 Rest, E108) ─
        // Der Rest des neunten Befunds: Ein Behälter, der zugleich umformatiert
        // und abgeschnitten ist, fiel durch die Zeichensuche auf den Klartextweg
        // und wurde ersetzt (gemessen an v58: 289 → 23 Byte); der kanonisch
        // abgeschnittene wurde gesperrt. Die Freigabe hing an der Schreibweise.
        Fall(name: "Behälter, kanonisch, ohne die schließende Klammer") { url, tresor in
            let text = try FormwaechterPruefungen.alsText(tresor)
            #expect(text.hasSuffix("}\n"))
            try Data(text.dropLast(2).utf8).write(to: url)
            return .unlesbar
        },
        Fall(name: "Behälter, umformatiert, ohne die schließende Klammer") { url, tresor in
            let behaelter = try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
            let objekt = try JSONSerialization.jsonObject(with: behaelter)
            let gesetzt = try JSONSerialization.data(withJSONObject: objekt, options: [.prettyPrinted, .sortedKeys])
            #expect(gesetzt.last == UInt8(ascii: "}"))
            try gesetzt.dropLast().write(to: url)
            return .unlesbar
        },
        Fall(name: "kein JSON") { url, _ in
            try Data("Hallo Welt\n".utf8).write(to: url)
            return .unlesbar
        },
        Fall(name: "leere Datei") { url, _ in
            try Data().write(to: url)
            return .klartext
        },
        Fall(name: "nur Leerraum") { url, _ in
            try Data("  \n\t\n".utf8).write(to: url)
            return .klartext
        },
        Fall(name: "deutbares JSON ohne den Typ") { url, _ in
            try Data("{\"version\":1,\"plaene\":{}}".utf8).write(to: url)
            return .klartext
        },
    ]

    // ── Vorlagen, die der Leser abweist ───────────────────────────────────

    /// Ein Behälter, wie die App ihn schreibt — als Text, um ihn zu verbiegen.
    static func alsText(_ tresor: Tresor) throws -> String {
        let behaelter = try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
        return try #require(String(data: behaelter, encoding: .utf8))
    }

    /// Derselbe Behälter mit einer Fassung, die diese App nicht kennt — die
    /// Kennung bleibt, wo sie steht. `kopfLesen` weist ihn ab und sagt dabei
    /// zu, die Datei bleibe unangetastet; daran ist der Wächter gebunden.
    static func neuereFassung(_ tresor: Tresor) throws -> Data {
        let text = try alsText(tresor)
        let neu = text.replacingOccurrences(of: "\"version\":\(Tresor.version),",
                                            with: "\"version\":\(Tresor.version + 1),")
        #expect(neu != text, "die Fassung steht, wo sie erwartet wird")
        return Data(neu.utf8)
    }

    /// Was der Leser wirklich sagt — nicht, was die Tabelle behauptet.
    private func gelesen(_ url: URL, tresor: Tresor) -> Lesart {
        switch Ablage.gebundenLesen(url, hoechstens: Ablage.formgrenze) {
        case .keine: return .keine
        case .unlesbar, .zuGross: return .unlesbar
        case .daten(let roh):
            switch Tresor.deuten(roh) {
            case .klartext: return .klartext
            case .undeutbar: return .unlesbar
            case .behaelter:
                guard let kopf = try? Tresor.kopfLesen(roh) else { return .unlesbar }
                return .behaelter(kopf.kennungHex)
            }
        }
    }

    /// Der dritte Zeuge — die Regel der Ansicht, unabhängig von beiden
    /// Erkennern der App (`istBehaelter(zerlegt)`: deuten, dann `typ`): `true`
    /// Behälter, `false` deutbar und keiner, `nil` nicht deutbar. B28 zeigte,
    /// dass Wächter und Leser einig sein können und beide falsch liegen —
    /// Einigkeit ist kein Beleg (E107).
    static func wieDieAnsicht(_ roh: Data) -> Bool? {
        var inhalt = roh
        if inhalt.starts(with: [0xEF, 0xBB, 0xBF]) { inhalt = inhalt.dropFirst(3) }
        guard !inhalt.allSatisfy({ $0 == 0x20 || $0 == 0x0a || $0 == 0x0d || $0 == 0x09 }) else { return false }
        guard let objekt = try? JSONSerialization.jsonObject(with: inhalt) else { return nil }
        return (objekt as? [String: Any])?["typ"] as? String == Tresor.typ
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

            // Die dritte Spalte: was die Vorlage wirklich ist — nach der Regel der
            // Ansicht, die keinen der beiden Erkenner der App teilt (E107).
            if case .daten(let roh) = Ablage.gebundenLesen(ablage.datei, hoechstens: Ablage.formgrenze) {
                let zeuge = FormwaechterPruefungen.wieDieAnsicht(roh)
                switch behauptet {
                case .behaelter:
                    #expect(zeuge == true, Comment(rawValue: "\(fall.name): die Ansicht sähe einen Behälter"))
                case .klartext:
                    #expect(zeuge == false, Comment(rawValue: "\(fall.name): die Ansicht sähe Klartext"))
                case .unlesbar:
                    #expect(zeuge != false, Comment(rawValue: "\(fall.name): die Ansicht sähe jedenfalls keinen Klartext"))
                case .keine:
                    Issue.record("\(fall.name): es liegt etwas, wo nichts liegen soll")
                }
            }

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

            // Und dann wirklich schreiben: Was der Wächter sagt, muss auf der
            // Platte auch geschehen (Empfehlung des Berichts zu N56-01).
            let vorher = try? Data(contentsOf: ablage.datei)
            let fremder = Tresor.neu()
            let gesperrt = Ablage.formwaechter(ablage.datei, tresor: fremder) != nil
            let versuch = Result { try ablage.schreiben(Data("{\"titel\":\"Versuch\"}".utf8),
                                                        tresor: fremder) }
            switch versuch {
            case .failure(let fehler):
                #expect(gesperrt && fehler is Ablage.Formsperre,
                        Comment(rawValue: "\(fall.name): \(fehler)"))
                if let vorher {
                    #expect((try? Data(contentsOf: ablage.datei)) == vorher,
                            Comment(rawValue: "\(fall.name): Byte für Byte unberührt"))
                }
            case .success:
                #expect(!gesperrt, Comment(rawValue: "\(fall.name): geschrieben, obwohl gesperrt"))
                #expect(Ablage.formAufDerPlatte(ablage.datei) == .behaelter(fremder.kennungHex),
                        Comment(rawValue: "\(fall.name): jetzt liegt der neue Behälter dort"))
            }
        }
    }

    @Test("Und keine Fassung der Tabelle ist versehentlich leer")
    func tabelleGefuellt() {
        #expect(FormwaechterPruefungen.faelle.count >= 28)
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

    // ── Erkennen ist nicht Erlauben (N57-01, E89/E90) ─────────────────────

    @Test("Ein Behälter aus einer neueren Fassung wird nicht ersetzt (N57-01)")
    func neuereFassungBleibt() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            let daten = try FormwaechterPruefungen.neuereFassung(tresor)
            try daten.write(to: ablage.datei)
            // Der Leser weist ihn ab — und sagt dabei zu, die Datei bleibe
            // unangetastet. Der Wächter ist an dieses Wort gebunden, auch wenn
            // der Kopf die Kennung der Sitzung nennt.
            #expect(throws: Tresorfehler.self) { _ = try Tresor.kopfLesen(daten) }
            let sperre = try #require(Ablage.formwaechter(ablage.datei, tresor: tresor))
            #expect(sperre.anlass == .unbrauchbar, Comment(rawValue: sperre.grund))
            #expect(sperre.grund.contains("neueren Fassung"), Comment(rawValue: sperre.grund))
            #expect(throws: Ablage.Formsperre.self) {
                try ablage.schreiben(Data("{\"titel\":\"neu\"}".utf8), tresor: tresor)
            }
            #expect(try Data(contentsOf: ablage.datei) == daten, "Byte für Byte unberührt")
        }
    }

    @Test("Die Schreibweise entscheidet nicht über die Freigabe (N57-01)")
    func schreibweiseEntscheidetNicht() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            let kanonisch = try FormwaechterPruefungen.neuereFassung(tresor)
            var umformatiert = Data("\n".utf8)
            umformatiert.append(kanonisch)

            try kanonisch.write(to: ablage.datei)
            let a = Ablage.formwaechter(ablage.datei, tresor: tresor)
            try umformatiert.write(to: ablage.datei)
            let b = Ablage.formwaechter(ablage.datei, tresor: tresor)
            #expect(a?.anlass == b?.anlass, "dieselbe Datei, anders gesetzt — dasselbe Urteil")
            #expect(a != nil && b != nil, "und beide Male gesperrt")
        }
    }

    @Test("Der eigene Behälter geht weiterhin durch — die Kennung kommt vom Leser")
    func eigenerBehaelterGehtDurch() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
                .write(to: ablage.datei)
            #expect(Ablage.formAufDerPlatte(ablage.datei) == .behaelter(tresor.kennungHex))
            #expect(Ablage.formwaechter(ablage.datei, tresor: tresor) == nil)
            #expect(throws: Never.self) { try ablage.schreiben(Data("neu".utf8), tresor: tresor) }
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

    // ── Eine Deutungsregel für alle (N57-01 Rest, B28, E107/E108) ─────────

    @Test("Ein abgeschnittener Behälter wird nicht ersetzt — gleich, wie er gesetzt ist (N57-01 Rest)")
    func abgeschnittenerBehaelterBleibt() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            let text = try FormwaechterPruefungen.alsText(tresor)
            let kanonisch = Data(text.dropLast(2).utf8)
            let objekt = try JSONSerialization.jsonObject(with: Data(text.utf8))
            let umformatiert = try JSONSerialization.data(withJSONObject: objekt,
                                                          options: [.prettyPrinted, .sortedKeys]).dropLast()
            var anlaesse: [Ablage.Formsperre.Anlass] = []
            for (name, daten) in [("kanonisch", kanonisch), ("umformatiert", Data(umformatiert))] {
                try daten.write(to: ablage.datei)
                let sperre = try #require(Ablage.formwaechter(ablage.datei, tresor: tresor), Comment(rawValue: name))
                anlaesse.append(sperre.anlass)
                #expect(sperre.grund.contains("planung.json") && sperre.grund.contains("deuten"),
                        Comment(rawValue: "\(name): \(sperre.grund)"))
                for schluessel in [nil, tresor, Tresor.neu()] {
                    #expect(throws: Ablage.Formsperre.self, Comment(rawValue: name)) {
                        try ablage.schreiben(Data("{\"titel\":\"neu\"}".utf8), tresor: schluessel)
                    }
                }
                #expect(try Data(contentsOf: ablage.datei) == daten,
                        Comment(rawValue: "\(name): Byte für Byte unberührt"))
            }
            #expect(anlaesse == [.ungewiss, .ungewiss], "dieselbe Datei, anders gesetzt — dasselbe Urteil")
        }
    }

    @Test("Anders geschrieben ist derselbe Behälter — für Wächter, Leser, Statusabgleich und Erkenner (B28)")
    func andersGeschriebenIstDerselbe() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            let planung = try tresor.versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
            let text = try #require(String(data: planung, encoding: .utf8))
            let schreibweisen: [(String, Data)] = [
                ("Marke", Data([0xEF, 0xBB, 0xBF]) + planung),
                ("Leerraum", Data(String(repeating: "\n", count: 100).utf8) + planung),
                ("Ausweichschreibung", Data(text.replacingOccurrences(
                    of: "\"typ\":\"unterrichtsplanung-tresor\"",
                    with: "\"typ\":\"\\u0075nterrichtsplanung-tresor\"").utf8)),
            ]
            for (name, daten) in schreibweisen {
                #expect(Tresor.istBehaelter(daten), Comment(rawValue: name))
                #expect(try tresor.oeffnen(daten) == Data("geheim".utf8), Comment(rawValue: "\(name): der Leser öffnet ihn"))
                try daten.write(to: ablage.datei)
                #expect(Ablage.formAufDerPlatte(ablage.datei) == .behaelter(tresor.kennungHex), Comment(rawValue: name))
                #expect(Ablage.formwaechter(ablage.datei, tresor: nil) != nil,
                        Comment(rawValue: "\(name): kein Klartext darüber"))
                #expect(Ablage.formwaechter(ablage.datei, tresor: Tresor.neu()) != nil,
                        Comment(rawValue: "\(name): kein fremder Schlüssel darüber"))
                #expect(Ablage.formwaechter(ablage.datei, tresor: tresor) == nil,
                        Comment(rawValue: "\(name): der eigene darf"))
            }
            // Dieselbe Regel an der Statusdatei — sie geht durch `Statusabgleich.entsiegeln`.
            let status = Data([0xEF, 0xBB, 0xBF])
                + (try tresor.versiegeln(Data("{}".utf8), inhalt: .status, ziel: .kopie))
            #expect(try Statusabgleich.entsiegeln(status, tresor: tresor) == Data("{}".utf8))
        }
    }

    @Test("Undeutbares sperrt mit eigener Meldung; die leere Datei und JSON ohne den Typ bleiben Klartext (E108)")
    func undeutbaresSperrt() throws {
        try imOrdner { ordner, tresor in
            let ablage = Ablage(ordner: ordner)
            try Data("Hallo Welt".utf8).write(to: ablage.datei)
            let sperre = try #require(Ablage.formwaechter(ablage.datei, tresor: nil))
            #expect(sperre.anlass == .ungewiss && sperre.grund.contains("deuten"), Comment(rawValue: sperre.grund))
            #expect(Ablage.formwaechter(ablage.datei, tresor: tresor) != nil)
            #expect(throws: Ablage.Formsperre.self) { try ablage.schreiben(Data("{}".utf8), tresor: nil) }
            #expect(try Data(contentsOf: ablage.datei) == Data("Hallo Welt".utf8))

            for (name, daten) in [("leer", Data()), ("Leerraum", Data(" \n".utf8)),
                                  ("ohne Typ", Data("{\"typ\":\"unterrichtsplanung\"}".utf8))] {
                try daten.write(to: ablage.datei)
                #expect(Ablage.formAufDerPlatte(ablage.datei) == .klartext, Comment(rawValue: name))
                #expect(Ablage.formwaechter(ablage.datei, tresor: nil) == nil, Comment(rawValue: name))
                #expect(Ablage.formwaechter(ablage.datei, tresor: tresor) == nil, Comment(rawValue: name))
            }
            #expect(throws: Never.self) { try ablage.schreiben(Data("{\"titel\":\"neu\"}".utf8), tresor: nil) }
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
