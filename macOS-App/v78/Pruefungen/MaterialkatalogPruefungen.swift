// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Die Vorlagen ──────────────────────────────────────────────────────────
// `Pruefungen/Vorlagen/inhalte-*.js` samt erwartetem JSON aus jsc
// (`katalog_pruefen.py --erzeugen`, E183). Gelesen über #filePath — die
// Vorlagen sind keine Ressourcen des Bündels (Package.swift: exclude).

private let vorlagenordner = URL(filePath: #filePath)
    .deletingLastPathComponent()      // Pruefungen
    .appending(path: "Vorlagen")

private struct Vorlage {
    let name: String
    let js: Data
    /// `daten` des erwarteten JSON, wie JSONSerialization sie liest.
    let erwartet: NSArray
    let kategorien: Int
    let kacheln: Int

    struct Unlesbar: Error {}

    init(_ name: String) throws {
        self.name = name
        js = try Data(contentsOf: vorlagenordner.appending(path: name + ".js"))
        let json = try Data(contentsOf: vorlagenordner.appending(path: name + ".erwartet.json"))
        guard let objekt = try JSONSerialization.jsonObject(with: json) as? NSDictionary,
              let daten = objekt["daten"] as? NSArray,
              let kategorien = objekt["kategorien"] as? Int,
              let kacheln = objekt["kacheln"] as? Int,
              objekt["vorlage"] as? String == name + ".js"
        else { throw Unlesbar() }
        erwartet = daten
        self.kategorien = kategorien
        self.kacheln = kacheln
    }
}

/// Die Vorlage des Tages ist die Live-Datei der Website; die synthetische
/// enthält, was die Teilmenge sonst noch kennt.
private let vorlagennamen = ["inhalte-2026-09-17", "inhalte-synthetisch"]

/// Die Deklaration, die jede geladene Liste trägt — so liest die Startseite
/// sie (E198, v73).
private let kopf = "const KATEGORIEN = "

private func katalog(_ text: String) throws -> Materialkatalog {
    try Materialkatalog.lesen(Data((kopf + text).utf8))
}

@Suite("Materialkatalog: der Leser der inhalte.js ohne Skriptausführung")
struct MaterialkatalogPruefungen {

    // ── Parität mit jsc ───────────────────────────────────────────────────

    @Test("Der Leser sieht jede Vorlage wie jsc — Feld für Feld", arguments: vorlagennamen)
    func paritaet(name: String) throws {
        let vorlage = try Vorlage(name)
        let text = try #require(String(data: vorlage.js, encoding: .utf8))
        let literal = try Materialkatalog.literal(text)
        let ist = try #require(literal.alsFoundation as? NSArray)
        #expect(ist.isEqual(vorlage.erwartet),
                "\(name): der Leser und jsc sehen die Vorlage verschieden")
    }

    @Test("Die Zahlen des Katalogs stammen aus der Vorlage, nicht aus dem Code",
          arguments: vorlagennamen)
    func zahlen(name: String) throws {
        let vorlage = try Vorlage(name)
        let katalog = try Materialkatalog.lesen(vorlage.js)
        #expect(katalog.kategorien.count == vorlage.kategorien)
        #expect(katalog.kacheln + katalog.uebergangen == vorlage.kacheln,
                "jede Kachel der Vorlage ist entweder im Katalog oder gezählt übergangen")
        // Reihenfolge und Kennungen: wie in der Datei, fortlaufend.
        #expect(katalog.kategorien.map(\.id) == Array(0..<katalog.kategorien.count))
        let kennungen = katalog.kategorien.flatMap { $0.kacheln.map(\.id) }
        #expect(kennungen == Array(0..<kennungen.count))
    }

    @Test("Die Live-Vorlage: alles hat eine https-Adresse, nichts wird übergangen")
    func liveVorlage() throws {
        let vorlage = try Vorlage("inhalte-2026-09-17")
        let katalog = try Materialkatalog.lesen(vorlage.js)
        #expect(katalog.uebergangen == 0)
        #expect(katalog.kacheln == vorlage.kacheln)
        for kachel in katalog.kategorien.flatMap(\.kacheln) {
            #expect(kachel.adresse.hasPrefix("https://"), Comment(rawValue: kachel.titel))
            #expect(!kachel.titel.isEmpty)
            #expect(Weblinks.pruefen(kachel.adresse) == kachel.adresse, "die Adresse ist schon geprüft")
        }
        // Relative Pfade der Website enden unter ihrer Wurzel.
        let dichte = try #require(katalog.kategorien.flatMap(\.kacheln)
                                    .first { $0.titel == "Lernumgebung: Dichte" })
        #expect(dichte.adresse == "https://3ducation.org/chemie/dichte.html")
        #expect(dichte.meta == "Chemie · 1. Lernjahr")
        #expect(dichte.lizenz == "CC BY-NC-SA 4.0")
        #expect(dichte.schlagworte.contains("Dichte"))
    }

    // ── Die synthetische Vorlage: die Teilmenge ───────────────────────────

    @Test("Die synthetische Vorlage: Kommentare, Anführungszeichen, Escapes, Nachkommas, Übergangenes")
    func synthetisch() throws {
        let vorlage = try Vorlage("inhalte-synthetisch")
        let katalog = try Materialkatalog.lesen(vorlage.js)
        #expect(katalog.kategorien.count == 3)
        #expect(katalog.uebergangen == 3, "ohne Adresse, javascript:, ohne Titel")
        let a = katalog.kategorien[0]
        #expect(a.titel == "Kategorie A")
        #expect(a.beschreibung == "Einfache Anführungszeichen — mit „Gänsefüßchen“ und 'Apostroph'")
        #expect(a.kacheln.count == 2)
        let a1 = a.kacheln[0]
        #expect(a1.titel == "Kachel A1 (relativ)")
        #expect(a1.beschreibung == "Zeile 1\nZeile 2 mit Tab\tund Backslash \\ und \"Zitat\" und äöü")
        #expect(a1.adresse == "https://3ducation.org/ordner/unterordner/datei.html")
        #expect(a1.schlagworte == ["a", "b", "c"], "Nachkomma im Feld")
        let a2 = a.kacheln[1]
        #expect(a2.adresse == "http://example.org/material?x=1&y=2#abschnitt", "http bleibt http, wie bei jedem Link")
        #expect(a2.beschreibung.isEmpty && a2.meta.isEmpty && a2.lizenz.isEmpty && a2.schlagworte.isEmpty)
        let b = katalog.kategorien[1]
        #expect(b.titel == "Kategorie B (leer)" && b.kacheln.isEmpty)
        let c = katalog.kategorien[2]
        #expect(c.kacheln.count == 1)
        #expect(c.kacheln[0].adresse == "https://3ducation.org/c/1.html", "absolut bleibt, wie es ist")
        #expect(c.kacheln[0].titel == "Kachel C1 (Adresse zuerst)")
    }

    @Test("Die Literal-Teilmenge im Kleinen")
    func literale() throws {
        let l: (String) throws -> Literal = { try Materialkatalog.literal($0) }
        #expect(try l("[]") == .feld([]))
        #expect(try l(" const KATEGORIEN = [ 1 , -2.5 , .5 , 1e3 , true , false , null ] ; ")
                == .feld([.zahl(1), .zahl(-2.5), .zahl(0.5), .zahl(1000), .wahrheit(true),
                          .wahrheit(false), .nichts]))
        #expect(try l("[{a: 1, 'b': 2, \"c\": 3,},]")
                == .feld([.objekt([.init("a", .zahl(1)), .init("b", .zahl(2)), .init("c", .zahl(3))])]))
        #expect(try l("// nur ein Kommentar\n/* und noch\n einer */ [ /* drin */ ]") == .feld([]))
        #expect(try l(#"["\u00e4\n\t\"\\\/\'x\b"]"#)
                == .feld([.zeichenkette("ä\n\t\"\\/'x\u{8}")]))
        #expect(try l("['a\\\nb']") == .feld([.zeichenkette("ab")]), "Zeilenfortsetzung")
        #expect(try l("[\"\\uD83D\\uDE00\"]") == .feld([.zeichenkette("😀")]), "Ersatzzeichenpaar")
        #expect(try l("[\"\\q\"]") == .feld([.zeichenkette("q")]), "unbekannte Escapes fallen auf das Zeichen zurück")
    }

    @Test("Was der Leser abweist — mit Zeile und Spalte, nie geraten")
    func fehler() throws {
        typealias F = Materialkatalog.Fehler
        func wirft(_ text: String, mitKopf: Bool = true, _ erwartet: (F) -> Bool, _ kommentar: String) {
            let fehler = #expect(throws: F.self, Comment(rawValue: kommentar)) {
                try Materialkatalog.lesen(Data(((mitKopf ? kopf : "") + text).utf8))
            }
            if let fehler {
                #expect(erwartet(fehler), Comment(rawValue: "\(kommentar): \(fehler)"))
            }
        }
        wirft("[\"offen", { if case .unerwartet = $0 { true } else { false } }, "offene Zeichenkette")
        wirft("[\"Zeile\nUmbruch\"]", { if case .unerwartet = $0 { true } else { false } }, "Umbruch in der Zeichenkette")
        wirft("[@]", { if case .unerwartet(zeile: 1, spalte: kopf.count + 2, _) = $0 { true } else { false } }, "unbekanntes Zeichen mit Stelle")
        wirft("[1, 2", { if case .unerwartet = $0 { true } else { false } }, "Feld ohne Ende")
        wirft("{titel: 1}", { $0 == .keineListe }, "ein Objekt ist keine Liste")
        wirft("\"x\"", { $0 == .keineListe }, "eine Zeichenkette ist keine Liste")
        wirft("[]; foo", { if case .unerwartet = $0 { true } else { false } }, "Rest nach der Liste")
        wirft("[] []", { if case .unerwartet = $0 { true } else { false } }, "zwei Listen")
        wirft("[0x10]", { if case .unerwartet = $0 { true } else { false } }, "Hexzahlen kennt die Teilmenge nicht")
        wirft("[x]", { if case .unerwartet = $0 { true } else { false } }, "ein Bezeichner ist kein Wert")
        wirft("[[[[[[[[[1]]]]]]]]]", { $0 == .zuTief }, "Tiefe 9")
        // Eine Liste der Website heißt KATEGORIEN (E198, B47): anders benannt
        // oder ohne Deklaration ist sie für die Startseite keine.
        wirft("[]", mitKopf: false, { if case .unerwartet(zeile: 1, spalte: 1, _) = $0 { true } else { false } }, "ohne Deklaration")
        wirft("const X = []", mitKopf: false, { if case .unerwartet(zeile: 1, spalte: 7, _) = $0 { true } else { false } }, "anderer Name")
        wirft("var if = []", mitKopf: false, { if case .unerwartet = $0 { true } else { false } }, "ein reserviertes Wort als Name")
    }

    @Test("Zeile und Spalte der Meldung: Zeilenenden wie in JavaScript — LF, CR, U+2028, U+2029, CRLF als eines")
    func zeilen() throws {
        func stelle(_ text: String) -> (zeile: Int, spalte: Int)? {
            do {
                _ = try Materialkatalog.literal(text)
                return nil
            } catch Materialkatalog.Fehler.unerwartet(let zeile, let spalte, _) {
                return (zeile, spalte)
            } catch {
                return nil
            }
        }
        for (text, zeile, spalte, name) in [("[1,\n\n@]", 3, 1, "LF"), ("[1,\r\r@]", 3, 1, "CR"),
                                            ("[1,\r\n\r\n@]", 3, 1, "CRLF"),
                                            ("[1,\u{2028}\u{2029}@]", 3, 1, "U+2028, U+2029"),
                                            ("[1,\r\n @]", 2, 2, "Spalte nach CRLF"),
                                            ("// x\r[@]", 2, 2, "Kommentar endet an CR")] {
            let ist = stelle(text)
            #expect(ist?.zeile == zeile && ist?.spalte == spalte,
                    Comment(rawValue: "\(name): \(String(describing: ist))"))
        }
    }

    @Test("Die Grenzen: Größe, UTF-8, Tiefe, Zahl der Kacheln")
    func grenzen() throws {
        let zuGross = Data(repeating: 0x20, count: Materialkatalog.hoechstens + 1)
        #expect(throws: Materialkatalog.Fehler.zuGross(Materialkatalog.hoechstens + 1)) {
            try Materialkatalog.lesen(zuGross)
        }
        #expect(throws: Materialkatalog.Fehler.keinUTF8) {
            try Materialkatalog.lesen(Data([0x5B, 0xFF, 0xFE, 0x5D]))
        }
        // Tiefe 8 geht durch (die Kategorie ist Tiefe 1, ihr Objekt 2, kacheln 3, Kachel 4, schlagworte 5).
        #expect(try Materialkatalog.literal("[[[[[[[[1]]]]]]]]") == .feld([.feld([.feld([.feld([.feld([.feld([.feld([.feld([.zahl(1)])])])])])])])]))
        // Zu viele Kacheln: eine Kategorie mit 2001 Kacheln.
        let kachel = "{titel:\"t\",link:\"a.html\"}"
        let viele = "[{titel:\"K\",kacheln:[" + Array(repeating: kachel, count: Materialkatalog.kachelnHoechstens + 1)
            .joined(separator: ",") + "]}]"
        #expect(throws: Materialkatalog.Fehler.zuViele) { try katalog(viele) }
        let gerade = "[{titel:\"K\",kacheln:[" + Array(repeating: kachel, count: Materialkatalog.kachelnHoechstens)
            .joined(separator: ",") + "]}]"
        #expect(try katalog(gerade).kacheln == Materialkatalog.kachelnHoechstens)
    }

    // ── Grenzfälle: annehmen heißt dasselbe lesen ───────────────────────

    /// Eine Sammlung von Grenzfällen gegen ihr erwartetes JSON aus jsc: Was der
    /// Leser annimmt, liest er wie jsc; alles andere weist er ab. Die Literale
    /// als bloßer Wert (jsc liest sie in Klammern), die Dateien mit Deklaration
    /// — auf dem Weg jeder geladenen Liste.
    private func sammlung(_ datei: String, deklaration: Bool) throws -> (anzahl: Int, gleich: Int, abgewiesen: Int) {
        let json = try Data(contentsOf: vorlagenordner.appending(path: datei))
        let objekt = try #require(try JSONSerialization.jsonObject(with: json) as? NSDictionary)
        let faelle = try #require(objekt["faelle"] as? [NSDictionary])
        var gleich = 0, abgewiesen = 0
        for fall in faelle {
            let name = try #require(fall["name"] as? String)
            let quelle = try #require(fall["quelle"] as? String)
            let soll = try #require(fall["leser"] as? String)
            let jsc = try #require(fall["jsc"] as? NSDictionary)
            let gelesen = try? Materialkatalog.literal(quelle, deklaration: deklaration)
            switch soll {
            case "gleich":
                let wert = try #require(jsc["wert"], Comment(rawValue: "\(name): jsc liefert einen Wert"))
                gleich += 1
                // Jeder Fall meldet sich selbst — ein Abbruch am ersten verdeckte die übrigen.
                guard let literal = gelesen else {
                    Issue.record(Comment(rawValue: "\(name): der Leser nimmt es an"))
                    continue
                }
                #expect(([literal.alsFoundation] as NSArray).isEqual([wert] as NSArray),
                        Comment(rawValue: "\(name): gelesen wie jsc"))
            case "abgewiesen":
                #expect(gelesen == nil, Comment(rawValue: "\(name): abgewiesen — JavaScript läse es anders oder gar nicht"))
                abgewiesen += 1
            default:
                Issue.record("\(name): unbekannte Erwartung \(soll)")
            }
        }
        return (faelle.count, gleich, abgewiesen)
    }

    @Test("Grenzfälle: Der Leser liest jedes Literal wie jsc — oder weist es ab")
    func grenzfaelle() throws {
        let (anzahl, gleich, abgewiesen) = try sammlung("literale-grenzfaelle.erwartet.json", deklaration: false)
        #expect(anzahl >= 90, "die Vorlage ist da")
        #expect(gleich >= 35 && abgewiesen >= 50)
    }

    @Test("Datei-Grenzfälle: Deklaration, Kommentare, Zeilenenden — wie jsc die Datei liest, oder abgewiesen")
    func dateiGrenzfaelle() throws {
        let (anzahl, gleich, abgewiesen) = try sammlung("datei-grenzfaelle.erwartet.json", deklaration: true)
        #expect(anzahl >= 25, "die Vorlage ist da")
        #expect(gleich >= 10 && abgewiesen >= 15)
    }

    @Test("Steuerzeichen: Was das Blatt zeigt und was ein Link wird, ist bereinigt wie beim Dateileser")
    func steuerzeichen() throws {
        let k = try katalog("""
            [{titel: "Kat\\u202Eegorie", beschreibung: "B\\u0007",
              kacheln: [{titel: "Dichte\\u202Efdp.exe\\u0007", beschreibung: "be\\u2066schrieben", meta: "Che\\u0001mie",
                         lizenz: "CC\\u202C BY", schlagworte: ["a\\u202Eb"], link: "a.html"},
                        {titel: "Zeile\\nzwei", link: "b.html"},
                        {titel: "مرحبا שלום", link: "c.html"}]}]
            """)
        let kategorie = try #require(k.kategorien.first)
        #expect(kategorie.titel == "Kategorie" && kategorie.beschreibung == "B")
        let kachel = try #require(kategorie.kacheln.first)
        #expect(kachel.titel == "Dichtefdp.exe")
        #expect(kachel.beschreibung == "beschrieben" && kachel.meta == "Chemie" && kachel.lizenz == "CC BY")
        #expect(kachel.schlagworte == ["ab"])
        #expect(kategorie.kacheln[1].titel == "Zeile zwei", "ein Titel ist eine Zeile")
        #expect(kategorie.kacheln[2].titel == "مرحبا שלום", "Schrift von rechts nach links bleibt, wie sie ist")
    }

    // ── Adressen ──────────────────────────────────────────────────────────

    @Test("Adressen: relativ zur Wurzel der Website, absolut wie sie sind, sonst übergangen")
    func adressen() throws {
        func adresse(_ link: String) throws -> String? {
            let k = try katalog("[{titel:\"K\",kacheln:[{titel:\"t\",link:\(link.debugDescription)}]}]")
            return k.kategorien.first?.kacheln.first?.adresse
        }
        #expect(try adresse("chemie/dichte.html") == "https://3ducation.org/chemie/dichte.html")
        #expect(try adresse("/chemie/dichte.html") == "https://3ducation.org/chemie/dichte.html", "führender Schrägstrich")
        #expect(try adresse("./chemie/dichte.html") == "https://3ducation.org/chemie/dichte.html")
        #expect(try adresse("skills/lab-o5.zip") == "https://3ducation.org/skills/lab-o5.zip")
        #expect(try adresse("https://github.com/dk-3du/unterrichtsplanung") == "https://github.com/dk-3du/unterrichtsplanung")
        #expect(try adresse("http://example.org/x") == "http://example.org/x")
        #expect(try adresse("app.ais-chat.schule/x") == "https://3ducation.org/app.ais-chat.schule/x",
                "ohne Schema ist es ein Pfad der Website — wie im Browser")
        #expect(try adresse("dw/zwischen den räumen.html") == "https://3ducation.org/dw/zwischen%20den%20r%C3%A4umen.html",
                "Leerzeichen und Umlaute werden kodiert wie bei jedem Link")
        // Nach den Regeln für Adressen aufgelöst — wie der Browser von der Startseite aus.
        #expect(try adresse("//cdn.example/material.html") == "https://cdn.example/material.html",
                "ohne Schema, mit Rechner: das Schema der Website, der Rechner der Adresse")
        #expect(try adresse("../chemie/dichte.html") == "https://3ducation.org/chemie/dichte.html", "über die Wurzel geht es nicht hinaus")
        #expect(try adresse("chemie/../bio/zelle.html") == "https://3ducation.org/bio/zelle.html")
        #expect(try adresse("chemie/./dichte.html") == "https://3ducation.org/chemie/dichte.html")
        #expect(try adresse("chemie/dichte.html?x=1#y") == "https://3ducation.org/chemie/dichte.html?x=1#y")
        #expect(try adresse("?q=1") == "https://3ducation.org/?q=1")
        #expect(try adresse("#x") == "https://3ducation.org/#x")
        #expect(try adresse("//") == nil, "ohne Rechner — übergangen")
        #expect(try adresse("///x") == nil)
        #expect(try adresse("//nutzer:geheim@cdn.example/x") == Weblinks.pruefen("https://nutzer:geheim@cdn.example/x"),
                "danach gilt die Schranke jedes Links — die Liste hat keine eigene Regel")
        #expect(try adresse("") == nil, "leer — übergangen")
        #expect(try adresse("   ") == nil)
        #expect(try adresse("javascript:alert(1)") == nil)
        #expect(try adresse("mailto:x@example.org") == nil)
        #expect(try adresse("file:///etc/passwd") == nil)
        #expect(try adresse("a\\b.html") == nil, "Gegenschrägstrich — wie Weblinks.pruefen")
        let ohneTitel = try katalog("[{titel:\"K\",kacheln:[{titel:\"  \",link:\"a.html\"},{link:\"b.html\"}]}]")
        #expect(ohneTitel.kacheln == 0 && ohneTitel.uebergangen == 2)
        let ohneKacheln = try katalog("[{titel:\"K\"},{titel:\"L\",kacheln:\"keins\"},{kacheln:[{titel:\"t\",link:\"a.html\"}]}]")
        #expect(ohneKacheln.kategorien.count == 1, "ohne Kachel-Feld ist es keine Kategorie")
        #expect(ohneKacheln.kategorien[0].titel.isEmpty, "der Titel darf fehlen")
        #expect(ohneKacheln.kacheln == 1)
    }

    // ── Die Suche ─────────────────────────────────────────────────────────

    @Test("Die Suche: jedes Wort muss passen — in Titel, Beschreibung, Meta, Lizenz oder Schlagwort")
    func suche() throws {
        let vorlage = try Vorlage("inhalte-2026-09-17")
        let katalog = try Materialkatalog.lesen(vorlage.js)
        let alle = katalog.kategorien.flatMap(\.kacheln)
        #expect(alle.allSatisfy { $0.passt("") }, "leer passt auf alles")
        #expect(alle.allSatisfy { $0.passt("   ") })
        #expect(alle.allSatisfy { $0.passt($0.titel) }, "der eigene Titel passt")
        #expect(alle.allSatisfy { !$0.passt("xyzzy") })
        #expect(alle.filter { $0.passt("GHS") }.count == 1)
        #expect(alle.filter { $0.passt("ghs") }.count == 1, "Groß und klein gleich")
        #expect(alle.filter { $0.passt("Chemie Lernjahr") }.count == 2, "beide Worte müssen passen")
        #expect(alle.filter { $0.passt("Chemie Biologie") }.isEmpty)
        #expect(alle.filter { $0.passt("CC0") }.isEmpty && !alle.filter { $0.passt("CC BY-NC-SA") }.isEmpty,
                "die Lizenz zählt mit")
        // Gefiltert bleibt die Struktur: Kategorien ohne Treffer fallen weg, die Reihenfolge bleibt.
        let chemie = katalog.passend("Chemie")
        #expect(chemie.map(\.titel) == ["Chemie"])
        #expect(katalog.passend("").map(\.titel) == katalog.kategorien.map(\.titel))
        #expect(katalog.passend("xyzzy").isEmpty)
    }
}
