// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import LocalAuthentication
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Der Umschlag ohne Enklave: Behälter erkennen, wickeln, entwickeln,
/// versiegeln, öffnen — mit festem Datenschlüssel und fester Passphrase, damit
/// kein Prüflauf je in einen Touch-ID-Dialog läuft.
@Suite("Tresor")
struct TresorPruefungen {

    /// Die Mindestzahl an Runden, damit die Prüfungen schnell bleiben.
    private let runden = Tresor.rundenMindestens
    private let wort = "Ein Satz, den man behält"

    private func planung() throws -> Data {
        var p = Planung.leer(titel: "Tresorprobe", start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 4, basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1,
                                titel: "Bits und Bytes", text: "Schülername steht hier nicht",
                                erledigt: false, materialien: [], links: [],
                                kommentar: "lief gut")]
        return try Planungsdatei.schreiben(p)
    }

    private func tresor() throws -> Tresor {
        let t = Tresor.neu()
        try t.passphraseSetzen(wort, runden: runden)
        return t
    }

    @Test("Klartext bleibt erkennbar, ein Behälter ebenso")
    func erkennen() throws {
        let klartext = try planung()
        #expect(!Tresor.istBehaelter(klartext))
        let t = try tresor()
        let behaelter = try t.versiegeln(klartext, inhalt: .planung, ziel: .ablage)
        #expect(Tresor.istBehaelter(behaelter))
        // `typ` steht vorne — `head -c 40` zeigt es.
        #expect(String(decoding: behaelter.prefix(40), as: UTF8.self)
                    .hasPrefix("{\"typ\":\"unterrichtsplanung-tresor\""))
        // Ein anders geordneter Kopf (die Ansicht schreibt ihn) wird ebenso erkannt.
        let umgeordnet = Data("{\"version\":1,\"typ\":\"unterrichtsplanung-tresor\"}".utf8)
        #expect(Tresor.istBehaelter(umgeordnet))
        #expect(!Tresor.istBehaelter(Data("{\"typ\":\"unterrichtsplanung\"}".utf8)))
        #expect(!Tresor.istBehaelter(Data("kein JSON".utf8)))
    }

    @Test("Versiegelt und geöffnet ergibt dieselben Bytes — nichts Lesbares dazwischen")
    func rundlauf() throws {
        let klartext = try planung()
        let t = try tresor()
        let behaelter = try t.versiegeln(klartext, inhalt: .planung, ziel: .ablage)
        #expect(try t.oeffnen(behaelter) == klartext)
        let text = String(decoding: behaelter, as: UTF8.self)
        #expect(!text.contains("Bits und Bytes"))
        #expect(!text.contains("lief gut"))
        #expect(!text.contains("Tresorprobe"))
        let kopf = try Tresor.kopfLesen(behaelter)
        #expect(kopf.inhalt == "planung")
        #expect(kopf.kennung == t.kennung)
        #expect(kopf.wicklungen.map(\.art) == [Wicklung.passphrase])
    }

    @Test("Die Passphrase-Wicklung geht auf — die falsche nicht, und die Daten bleiben zu")
    func passphrase() throws {
        let klartext = try planung()
        let t = try tresor()
        let behaelter = try t.versiegeln(klartext, inhalt: .planung, ziel: .kopie)
        let kopf = try Tresor.kopfLesen(behaelter)

        let offen = try Tresor.oeffnen(kopf: kopf, passphrase: wort)
        #expect(offen.kennung == t.kennung)
        #expect(try offen.oeffnen(kopf: kopf) == klartext)

        #expect(throws: Tresorfehler.self) {
            try Tresor.oeffnen(kopf: kopf, passphrase: "Ein Satz, den man vergisst")
        }
        do {
            _ = try Tresor.oeffnen(kopf: kopf, passphrase: "Ein Satz, den man vergisst")
        } catch let fehler as Tresorfehler {
            #expect(fehler.art == .falscherSchluessel, "falsch, nicht beschädigt")
        }
    }

    @Test("Zerlegtes und zusammengesetztes ä sind dieselbe Passphrase")
    func normalisierung() throws {
        let zusammengesetzt = "Käse und Brötchen 2026"          // U+00E4, U+00F6
        let zerlegt = "Ka\u{0308}se und Bro\u{0308}tchen 2026"  // a + U+0308
        // Swift vergleicht Zeichenketten kanonisch — die Bytes müssen verschieden sein.
        #expect(Array(zusammengesetzt.utf8) != Array(zerlegt.utf8),
                "die Prüfung braucht zwei verschiedene Kodierungen")
        let t = Tresor.neu()
        try t.passphraseSetzen(zusammengesetzt, runden: runden)
        let kopf = try Tresor.kopfLesen(try t.versiegeln(try planung(), inhalt: .planung, ziel: .kopie))
        #expect(try Tresor.oeffnen(kopf: kopf, passphrase: zerlegt).kennung == t.kennung)
    }

    @Test("Zu kurze Passphrasen werden abgewiesen")
    func mindestlaenge() {
        let t = Tresor.neu()
        #expect(throws: Tresorfehler.self) { try t.passphraseSetzen("elf zeichen", runden: 100_000) }
        #expect(!t.hat(Wicklung.passphrase))
    }

    @Test("Der Wiederherstellungsschlüssel öffnet — auch klein geschrieben, ohne Striche, mit 0 statt O")
    func wiederherstellung() throws {
        let t = try tresor()
        let blatt = try t.wiederherstellungAnlegen()
        #expect(blatt.count == 39, "8 Gruppen zu 4 Zeichen mit 7 Strichen: \(blatt)")
        #expect(blatt.split(separator: "-").count == 8)
        #expect(!blatt.contains("0") && !blatt.contains("1"))
        let kopf = try Tresor.kopfLesen(try t.versiegeln(try planung(), inhalt: .planung, ziel: .export))
        #expect(kopf.wicklungen.map(\.art).sorted() == [Wicklung.passphrase, Wicklung.wiederherstellung])

        #expect(try Tresor.oeffnen(kopf: kopf, wiederherstellung: blatt).kennung == t.kennung)
        let nachlaessig = " " + blatt.lowercased().replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "o", with: "0") + "\n"
        #expect(try Tresor.oeffnen(kopf: kopf, wiederherstellung: nachlaessig).kennung == t.kennung)

        var falsch = Array(blatt)
        falsch[0] = falsch[0] == "A" ? "B" : "A"
        #expect(throws: Tresorfehler.self) {
            try Tresor.oeffnen(kopf: kopf, wiederherstellung: String(falsch))
        }
        #expect(throws: Tresorfehler.self) {
            try Tresor.oeffnen(kopf: kopf, wiederherstellung: "zu kurz")
        }
    }

    @Test("Ein beschädigter Behälter heißt beschädigt, nicht „falscher Schlüssel“")
    func beschaedigt() throws {
        let t = try tresor()
        var behaelter = try t.versiegeln(try planung(), inhalt: .planung, ziel: .ablage)
        // Ein Byte in der Nutzlast kippen — die Beglaubigung schlägt an.
        let stelle = behaelter.lastIndex(of: UInt8(ascii: "\"")).map { $0 - 20 } ?? behaelter.count - 30
        behaelter[stelle] = behaelter[stelle] == UInt8(ascii: "A") ? UInt8(ascii: "B") : UInt8(ascii: "A")
        do {
            _ = try t.oeffnen(behaelter)
            Issue.record("ein gekippter Behälter darf nicht aufgehen")
        } catch let fehler as Tresorfehler {
            #expect(fehler.art == .beschaedigt)
        }
        #expect(throws: Tresorfehler.self) { try Tresor.kopfLesen(Data("{\"typ\":\"unterrichtsplanung-tresor\"".utf8)) }
        #expect(throws: Tresorfehler.self) {
            try Tresor.kopfLesen(Data("{\"typ\":\"unterrichtsplanung-tresor\",\"version\":1}".utf8))
        }
    }

    @Test("Eine Wicklung mit lächerlicher Rundenzahl wird nicht geöffnet")
    func rundenSchranke() throws {
        let t = try tresor()
        let behaelter = try t.versiegeln(try planung(), inhalt: .planung, ziel: .kopie)
        let text = String(decoding: behaelter, as: UTF8.self)
            .replacingOccurrences(of: "\"runden\":\(runden)", with: "\"runden\":10")
        let kopf = try Tresor.kopfLesen(Data(text.utf8))
        do {
            _ = try Tresor.oeffnen(kopf: kopf, passphrase: wort)
            Issue.record("zehn Runden dürfen nicht genügen")
        } catch let fehler as Tresorfehler {
            #expect(fehler.art == .beschaedigt)
        }
    }

    @Test("Ein Behälter unter fremdem Schlüssel wird benannt, nicht geraten")
    func fremderSchluessel() throws {
        let eins = try tresor()
        let zwei = try tresor()
        let behaelter = try eins.versiegeln(try planung(), inhalt: .status, ziel: .kopie)
        do {
            _ = try zwei.oeffnen(behaelter)
            Issue.record("fremde Kennung darf nicht aufgehen")
        } catch let fehler as Tresorfehler {
            #expect(fehler.art == .falscherSchluessel)
        }
        #expect(!zwei.passt(zu: try Tresor.kopfLesen(behaelter)))
    }

    @Test("Ziel entscheidet, welche Wicklungen reisen — die Enklave nie, der Export nur zwei")
    func ziele() throws {
        let t = try tresor()
        _ = try t.wiederherstellungAnlegen()
        // Eine Enklaven-Wicklung und eine unbekannte, wie sie aus einem fremden Kopf kämen.
        let fremd = Behaelterkopf(
            version: 1, inhalt: "status", kennung: t.kennung, nonce: Data(count: 12),
            wicklungen: [Wicklung(art: Wicklung.enklave, felder: ["geraet": .text("AAAA")]),
                         Wicklung(art: "passkey", felder: ["kennung": .text("p-1"),
                                                            "salz": .text("QUJD"),
                                                            "runden": .zahl(3),
                                                            "extras": .liste([.wahr(true), .leer])])],
            daten: Data(count: 16))
        // Nur die unbekannte Art kommt von außen; die Enklaven-Wicklung entsteht
        // hier direkt, wie sie ein Mac anlegte.
        #expect(t.fremdeWicklungenUebernehmen(aus: fremd) == 1)
        #expect(t.fremdeWicklungenUebernehmen(aus: fremd) == 0, "nichts doppelt")
        let mitEnklave = Tresor(schluessel: t.schluessel, kennung: t.kennung,
                                wicklungen: t.wicklungen
                                + [Wicklung(art: Wicklung.enklave, felder: ["geraet": .text("AAAA")])])

        let klartext = try planung()
        func arten(_ ziel: Tresor.Ziel) throws -> [String] {
            try Tresor.kopfLesen(try mitEnklave.versiegeln(klartext, inhalt: .planung, ziel: ziel))
                .wicklungen.map(\.art).sorted()
        }
        #expect(try arten(.ablage) == ["enklave", "passkey", "passphrase", "wiederherstellung"])
        #expect(try arten(.kopie) == ["passkey", "passphrase", "wiederherstellung"])
        #expect(try arten(.export) == ["passphrase", "wiederherstellung"])
    }

    @Test("Eine unbekannte Wicklung überlebt Schreiben und Lesen Feld für Feld")
    func unbekannteWicklung() throws {
        let t = try tresor()
        let fremd = Wicklung(art: "passkey", felder: [
            "kennung": .text("p-1"), "salz": .text("QUJD"), "runden": .zahl(3),
            "verschachtelt": .objekt(["a": .liste([.zahl(1.5), .wahr(false), .leer, .text("x/y")])]),
        ])
        _ = t.fremdeWicklungenUebernehmen(aus: Behaelterkopf(
            version: 1, inhalt: "status", kennung: t.kennung, nonce: Data(count: 12),
            wicklungen: [fremd], daten: Data(count: 16)))
        let behaelter = try t.versiegeln(try planung(), inhalt: .planung, ziel: .kopie)
        let gelesen = try Tresor.kopfLesen(behaelter).wicklung("passkey")
        #expect(gelesen == fremd)

        // Und durch einen zweiten Tresor, der sie nur trägt:
        let traeger = try Tresor.oeffnen(kopf: try Tresor.kopfLesen(behaelter), passphrase: wort)
        let weiter = try traeger.versiegeln(Data("x".utf8), inhalt: .status, ziel: .kopie)
        #expect(try Tresor.kopfLesen(weiter).wicklung("passkey") == fremd)
    }

    @Test("Passphrase ändern wickelt neu, der Datenschlüssel bleibt")
    func passphraseWechsel() throws {
        let t = try tresor()
        let klartext = try planung()
        let alt = try t.versiegeln(klartext, inhalt: .planung, ziel: .ablage)
        #expect(t.passphraseStimmt(wort))
        #expect(!t.passphraseStimmt("Ein Satz, den man vergisst"))

        try t.passphraseSetzen("Ein ganz anderer Satz", runden: runden)
        let neu = try t.versiegeln(klartext, inhalt: .planung, ziel: .ablage)
        // Die alte Datei geht mit dem alten Wort auf, die neue nur mit dem neuen.
        #expect(try Tresor.oeffnen(kopf: try Tresor.kopfLesen(alt), passphrase: wort).kennung == t.kennung)
        #expect(throws: Tresorfehler.self) {
            try Tresor.oeffnen(kopf: try Tresor.kopfLesen(neu), passphrase: wort)
        }
        let offen = try Tresor.oeffnen(kopf: try Tresor.kopfLesen(neu), passphrase: "Ein ganz anderer Satz")
        #expect(try offen.oeffnen(alt) == klartext, "derselbe Datenschlüssel öffnet auch die alte Datei")
    }

    @Test("Im Prüfstand gibt es keine Enklave")
    func keineEnklaveImPruefstand() {
        #expect(!Tresor.enklaveVerfuegbar)
        let t = Tresor.neu()
        #expect(throws: Tresorfehler.self) { try t.enklaveAnlegen() }
        #expect(!t.hat(Wicklung.enklave))
    }

    /// Der Prüfstein ohne Dialog: Der Enklaven-Schlüssel wird wirklich angelegt
    /// und die Wicklung wirklich gewickelt; das Entwickeln läuft mit
    /// unterbundener Nachfrage in die erwartete Abweisung (LAError −1004,
    /// nachgemessen) — belegt also den ganzen Weg bis zur Enklave,
    /// ohne dass ein Touch-ID-Dialog erscheint.
    @Test("Die Enklaven-Wicklung entsteht ohne Nachfrage und verlangt beim Öffnen die Freigabe")
    func enklaveOhneDialog() throws {
        guard SecureEnclave.isAvailable else { return }
        let t = try tresor()
        try t.enklaveAnlegen(auchImPruefstand: true)
        #expect(t.hat(Wicklung.enklave))
        let behaelter = try t.versiegeln(try planung(), inhalt: .planung, ziel: .ablage)
        let kopf = try Tresor.kopfLesen(behaelter)
        let w = try #require(kopf.wicklung(Wicklung.enklave))
        #expect((w.daten("geraet")?.count ?? 0) > 300, "der Blob der Enklave")
        #expect(w.daten("fluechtig")?.count == 64)
        // Die Kopie trägt sie nie.
        #expect(try Tresor.kopfLesen(try t.versiegeln(Data("x".utf8), inhalt: .status, ziel: .kopie))
                    .wicklung(Wicklung.enklave) == nil)

        let kontext = LAContext()
        kontext.interactionNotAllowed = true
        do {
            _ = try Tresor.oeffnen(kopf: kopf, enklave: kontext)
            Issue.record("ohne Freigabe darf die Wicklung nicht aufgehen")
        } catch let fehler as Tresorfehler {
            #expect(fehler.art == .abgebrochen, "\(fehler.text)")
        }
    }

    @Test("Erkannt wird am Feld typ — nicht an einer Zeichenfolge im Titel")
    func erkennungAmFeld() throws {
        var p = Planung.leer(titel: "unterrichtsplanung-tresor", start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 2, basis: "", klassen: [], fachfarben: [:])
        p.eintraege = []
        let klartext = try Planungsdatei.schreiben(p)
        #expect(String(decoding: klartext, as: UTF8.self).contains("\"unterrichtsplanung-tresor\""))
        #expect(!Tresor.istBehaelter(klartext), "ein Titel ist kein Typ")
        // Ein Behälter mit `typ` weit hinten — von einem fremden Schreiber — wird trotzdem erkannt.
        let t = try tresor()
        let text = String(decoding: try t.versiegeln(klartext, inhalt: .planung, ziel: .kopie), as: UTF8.self)
        let umgeordnet = "{" + text.dropFirst().replacingOccurrences(
            of: "\"typ\":\"unterrichtsplanung-tresor\",", with: "") .dropLast(2)
            + ",\"typ\":\"unterrichtsplanung-tresor\"}"
        #expect(Tresor.istBehaelter(Data(umgeordnet.utf8)))
        #expect(try t.oeffnen(Data(umgeordnet.utf8)) == klartext)
    }

    @Test("Ein Behälter aus einer neueren Fassung wird benannt, nicht beschädigt genannt")
    func neuereFassung() throws {
        let t = try tresor()
        let text = String(decoding: try t.versiegeln(try planung(), inhalt: .planung, ziel: .kopie),
                          as: UTF8.self)
            .replacingOccurrences(of: "\"version\":1,", with: "\"version\":2,")
        do {
            _ = try Tresor.kopfLesen(Data(text.utf8))
            Issue.record("Fassung 2 darf diese App nicht lesen")
        } catch let fehler as Tresorfehler {
            #expect(fehler.art == .neuereFassung)
        }
    }

    @Test("Zu viele Runden sind eine Bremse und werden abgewiesen")
    func rundenObergrenze() throws {
        let t = try tresor()
        let text = String(decoding: try t.versiegeln(try planung(), inhalt: .planung, ziel: .kopie),
                          as: UTF8.self)
            .replacingOccurrences(of: "\"runden\":\(runden)", with: "\"runden\":\(Tresor.rundenHoechstens + 1)")
        let kopf = try Tresor.kopfLesen(Data(text.utf8))
        do {
            _ = try Tresor.oeffnen(kopf: kopf, passphrase: wort)
            Issue.record("über der Obergrenze darf nicht gerechnet werden")
        } catch let fehler as Tresorfehler {
            #expect(fehler.art == .beschaedigt)
        }
    }

    @Test("Eigene Arten kommen nie von außen — nur Unbekanntes wird übernommen")
    func keineEigenenArtenVonAussen() throws {
        let t = try tresor()
        let fremd = Behaelterkopf(
            version: 1, inhalt: "status", kennung: t.kennung, nonce: Data(count: 12),
            wicklungen: [Wicklung(art: Wicklung.enklave, felder: ["geraet": .text("AAAA")]),
                         Wicklung(art: Wicklung.wiederherstellung, felder: ["umschlag": .text("AAAA")]),
                         Wicklung(art: "passkey", felder: ["kennung": .text("p-1")])],
            daten: Data(count: 16))
        #expect(t.fremdeWicklungenUebernehmen(aus: fremd) == 1)
        #expect(t.wicklungen.map(\.art).sorted() == ["passkey", "passphrase"])
        // Und nie unter fremder Kennung.
        let anderer = try tresor()
        #expect(anderer.fremdeWicklungenUebernehmen(aus: fremd) == 0)
    }

    @Test("Hex nur aus Hexziffern, Wiederherstellung nur aus ASCII")
    func strengeKodierung() {
        #expect(Data(hex: "+f00") == nil, "ein Vorzeichen ist keine Hexziffer")
        #expect(Data(hex: "0F0a") == Data([0x0f, 0x0a]))
        let roh = Data.zufall(Tresor.wiederherstellungLaenge)
        let text = Tresor.wiederherstellungText(roh)
        #expect(Tresor.wiederherstellungRoh(text + " ä") == roh, "Fremdzeichen fallen weg wie in der Ansicht")
        // „ß“ wird beim Großschreiben zu „SS“ — zwei ASCII-Buchstaben zu viel,
        // hier wie in der Ansicht (`toUpperCase`): beide weisen ab.
        #expect(Tresor.wiederherstellungRoh("ß" + text) == nil)
    }

    @Test("Eine leere Passphrase ist falsch, nicht beschädigt")
    func leerePassphrase() throws {
        let t = try tresor()
        let kopf = try Tresor.kopfLesen(try t.versiegeln(Data("x".utf8), inhalt: .status, ziel: .kopie))
        do {
            _ = try Tresor.oeffnen(kopf: kopf, passphrase: "")
            Issue.record("leer darf nicht öffnen")
        } catch let fehler as Tresorfehler {
            #expect(fehler.art == .falscherSchluessel)
        }
    }

    @Test("Base32 hin und zurück, byteweise")
    func base32() {
        for _ in 0..<20 {
            let roh = Data.zufall(Tresor.wiederherstellungLaenge)
            let text = Tresor.wiederherstellungText(roh)
            #expect(Tresor.wiederherstellungRoh(text) == roh)
        }
        #expect(Data(hex: "00ff10") == Data([0x00, 0xff, 0x10]))
        #expect(Data(hex: "0ff") == nil)
        #expect(Data([0x00, 0xff, 0x10]).hex == "00ff10")
    }
}

// ── Die Ablage versiegelt ─────────────────────────────────────────────────

@Suite("Ablage versiegelt")
struct AblageVersiegeltPruefungen {

    private func ablage() throws -> (Ablage, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "tresor-ablage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return (Ablage(ordner: ordner), ordner)
    }

    private func tresor() throws -> Tresor {
        let t = Tresor.neu()
        try t.passphraseSetzen("Ein Satz, den man behält", runden: Tresor.rundenMindestens)
        return t
    }

    @Test("Mit Tresor liegt ein Behälter auf der Platte, ohne Klartext")
    func schreibenVersiegelt() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        ablage.tresor = try tresor()
        try ablage.schreiben(Data("{\"titel\":\"Geheimes\"}".utf8))
        let roh = try Data(contentsOf: ablage.datei)
        #expect(Tresor.istBehaelter(roh))
        #expect(!String(decoding: roh, as: UTF8.self).contains("Geheimes"))
        guard case .daten(let gelesen) = ablage.lesen() else { Issue.record("erwartet .daten"); return }
        #expect(try ablage.entsiegelt(gelesen) == Data("{\"titel\":\"Geheimes\"}".utf8))
    }

    @Test("Ohne Tresor ist ein Behälter nicht zu entsiegeln — und Klartext geht durch")
    func ohneTresor() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let t = try tresor()
        let behaelter = try t.versiegeln(Data("x".utf8), inhalt: .planung, ziel: .ablage)
        #expect(throws: Tresorfehler.self) { try ablage.entsiegelt(behaelter) }
        #expect(try ablage.entsiegelt(Data("{}".utf8)) == Data("{}".utf8))
    }

    @Test("Altbestände werden an Ort und Stelle versiegelt und wieder entsiegelt — nie gelöscht")
    func altbestaende() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        try ablage.schreiben(Data("{\"titel\":\"eins\"}".utf8))
        try ablage.schreiben(Data("{\"titel\":\"zwei\"}".utf8))   // → planung-vorher.json = eins
        let kaputt = ordner.appendingPathComponent("planung-beschaedigt-2026-09-04-1200-00.json")
        try Data("{kaputt".utf8).write(to: kaputt)
        let gestempelt = ordner.appendingPathComponent("planung-vorher-2026-09-04-1200-00.json")
        try Data("{\"titel\":\"alt\"}".utf8).write(to: gestempelt)
        let fremd = ordner.appendingPathComponent("notiz.txt")
        try Data("bleibt".utf8).write(to: fremd)

        let t = try tresor()
        ablage.tresor = t
        #expect(ablage.altbestaendeVersiegeln() == 3)
        for url in [ablage.vorherigeFassung, kaputt, gestempelt] {
            let roh = try Data(contentsOf: url)
            #expect(Tresor.istBehaelter(roh), Comment(rawValue: url.lastPathComponent))
            #expect(!String(decoding: roh, as: UTF8.self).contains("titel"))
        }
        #expect(try Tresor.kopfLesen(try Data(contentsOf: ablage.vorherigeFassung)).inhalt == "planung")
        #expect(try Tresor.kopfLesen(try Data(contentsOf: kaputt)).inhalt == "rohdaten")
        #expect(try Data(contentsOf: fremd) == Data("bleibt".utf8), "Fremdes bleibt unberührt")
        #expect(try ablage.entsiegelt(try Data(contentsOf: kaputt)) == Data("{kaputt".utf8))
        // Ein zweiter Lauf schreibt neu (frische Nonces), verliert aber nichts.
        #expect(ablage.altbestaendeVersiegeln() == 3)

        #expect(ablage.altbestaendeEntsiegeln(t) == 3)
        #expect(try Data(contentsOf: ablage.vorherigeFassung) == Data("{\"titel\":\"eins\"}".utf8))
        #expect(try Data(contentsOf: kaputt) == Data("{kaputt".utf8))
        let liegt = try FileManager.default.contentsOfDirectory(atPath: ordner.path).sorted()
        #expect(liegt.count == 5, "nichts gelöscht: \(liegt)")
    }

    @Test("Ein neuer Schlüssel versiegelt Altbestände des alten neu")
    func schluesselwechsel() throws {
        let (ablage, ordner) = try ablage()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let alter = try tresor()
        ablage.tresor = alter
        try ablage.schreiben(Data("{\"titel\":\"eins\"}".utf8))
        try ablage.schreiben(Data("{\"titel\":\"zwei\"}".utf8))
        let neuer = try tresor()
        ablage.tresor = neuer
        #expect(ablage.altbestaendeVersiegeln(alter: alter) == 1)
        #expect(try ablage.entsiegelt(try Data(contentsOf: ablage.vorherigeFassung))
                == Data("{\"titel\":\"eins\"}".utf8))
        // Ohne den alten Schlüssel bleibt ein fremder Behälter liegen, wie er ist.
        ablage.tresor = alter
        try ablage.schreiben(Data("{\"titel\":\"drei\"}".utf8))
        ablage.tresor = neuer
        #expect(ablage.altbestaendeVersiegeln(alter: nil) == 0)
    }
}
