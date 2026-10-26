// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import PDFKit
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die Rückmeldungsliste (v84, AT16) ─────────────────────────────────────
// Die Tabelle je Lerngruppe als reine Funktion (E402, E408–E410), der
// Seitenumbruch als reine Rechnung (E411), das PDF im Speicher, verschlüsselt
// mit dem getippten Kennwort (E405, E406) — und eine zweite, künstliche
// Tabelle über denselben Listensatz (E412).

@Suite("Rückmeldungsliste: Tabelle, Umbruch, verschlüsseltes PDF, zweite Tabelle")
@MainActor
struct RueckmeldungslistePruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let kennwort = "Elternbriefe 2026"
    private let stand = Tag(jahr: 2026, monat: 10, tagImMonat: 11)

    // ── Der Bestand ───────────────────────────────────────────────────────

    private func person(_ id: String, _ vorname: String, _ nachname: String, rufname: String = "",
                        archiviert: String = "") -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, rufname: rufname, angelegt: "", geaendert: "",
                  archiviert: archiviert)
    }

    private func gruppe(_ id: String, _ name: String, _ mitglieder: [String]) -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: mitglieder, zeilen: [], skalen: [:],
                   halbjahreswechsel: "", geaendert: "", archiviert: "")
    }

    private func anliegen(_ id: String, _ art: Anliegenart, _ titel: String, gruppe: String, datum: String,
                          _ betroffene: [String]) -> Anliegen {
        Anliegen(id: id, art: art, titel: titel, lerngruppe: gruppe, betroffene: betroffene, datum: datum, frist: "",
                 notiz: "", angelegt: "", geaendert: "")
    }

    private func ruecklauf(_ anliegen: String, _ person: String, _ stand: Rueckmeldestand, datum: String = "",
                           notiz: String = "") -> Rueckmeldung {
        Rueckmeldung(anliegen: anliegen, lernender: person, stand: stand, datum: datum, notiz: notiz, geaendert: "")
    }

    /// Lerngruppe „6a“: Anna (Rufname Anni), Ben, Can, Ada; Mia archiviert; Olaf
    /// nur in der Förderkurs-Gruppe, aber von „Wandertag“ betroffen. Can kam
    /// nach „Fotos“ dazu. Dazu eine Mitteilung einer anderen Gruppe und eine
    /// Maßnahme in 6a.
    private func bestand() -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p1", schuljahr: "2026/27", jetzt: "")
        b.lernende = [person("ada", "Ada", "Zimmer"), person("ben", "Ben", "Abel"),
                      person("anna", "Anna", "Abel", rufname: "Anni"), person("can", "Can", "Becker"),
                      person("mia", "Mia", "Adam", archiviert: "2026-09-20T10:00:00Z"), person("olaf", "Olaf", "Ost")]
        b.lerngruppen = [gruppe("g1", "6a", ["ada", "ben", "anna", "can", "mia"]),
                         gruppe("g2", "Förderkurs", ["olaf"])]
        b.anliegen = [anliegen("m1", .mitteilung, "Wandertag", gruppe: "g1", datum: "2026-09-01",
                               ["anna", "ben", "can", "ada", "mia", "olaf"]),
                      anliegen("m3", .mitteilung, "Ausflug", gruppe: "g2", datum: "2026-09-05", ["olaf"]),
                      anliegen("n1", .massnahme, "Nacharbeit", gruppe: "g1", datum: "2026-09-10", ["ben"]),
                      anliegen("m2", .mitteilung, "Fotos", gruppe: "g1", datum: "2026-09-15", ["anna", "ben", "ada"])]
        b.rueckmeldungen = [ruecklauf("m1", "anna", .erledigt, datum: "2026-09-02", notiz: "Unterschrift der Mutter"),
                            ruecklauf("m1", "ben", .abgelehnt, datum: "2026-09-03"),
                            ruecklauf("m1", "ada", .offen, notiz: "fragt nach"),
                            ruecklauf("m1", "mia", .erledigt, datum: "2026-09-02"),
                            ruecklauf("m1", "olaf", .erledigt, datum: "2026-09-02", notiz: "nicht mehr in der Gruppe"),
                            ruecklauf("m2", "anna", .erledigt), ruecklauf("m2", "ben", .erledigt),
                            ruecklauf("m2", "ada", .erledigt)]
        return b
    }

    private func z(_ s: Rueckmeldestand) -> String { Rueckmeldungsliste.zeichen(s) }

    // ── Die Tabelle (E402, E408–E410) ─────────────────────────────────────

    @Test("E410/E408: Zeilen nur aktive Mitglieder nach Nachname und Vorname, Rufname in Klammern; Spalten in der Folge des Blatts, nur Mitteilungen der Gruppe")
    func zeilenUndSpalten() throws {
        let liste = try #require(Rueckmeldungsliste.liste(bestand(), gruppe: "g1",
                                                          mitteilungen: ["m2", "m1", "m3", "n1"], stand: stand))
        #expect(liste.zeilen.map(\.name) == ["Abel, Anna (Anni)", "Abel, Ben", "Becker, Can", "Zimmer, Ada",
                                             "nicht mehr in der Lerngruppe", "Ost, Olaf"],
                "nach Nachname, nicht Vorname; ohne die archivierte Mia; Olaf — betroffen, nicht mehr Mitglied — unten (E484)")
        #expect(liste.zeilen.map(\.trenner) == [false, false, false, false, true, false])
        #expect(liste.spalten.map(\.titel) == ["Wandertag", "Fotos"],
                "Folge des Blatts statt Folge der Wahl; die fremde Mitteilung und die Maßnahme nicht")
        #expect(liste.spalten.map(\.unterzeile) == ["01.09.2026", "15.09.2026"])
        #expect(liste.namensspalte == "Name")
        #expect(liste.zeilen.filter { !$0.trenner }.allSatisfy { $0.zellen.count == 2 })
    }

    @Test("E409/E272/E408: der Stand als Zeichen — ohne Rücklauf offen, nicht betroffen ein Strich, Notiz mit Stern; alle Rückläufe, nichts ausgesiebt")
    func zellen() throws {
        let liste = try #require(Rueckmeldungsliste.liste(bestand(), gruppe: "g1", mitteilungen: ["m1", "m2"],
                                                          stand: stand))
        let stern = Rueckmeldungsliste.mitNotiz
        #expect(liste.zeilen.map(\.zellen) == [[z(.erledigt) + stern, z(.erledigt)],
                                                [z(.abgelehnt), z(.erledigt)],
                                                [z(.offen), Rueckmeldungsliste.nichtBetroffen],
                                                [z(.offen) + stern, z(.erledigt)],
                                                [],
                                                [z(.erledigt) + stern, Rueckmeldungsliste.nichtBetroffen]])
        let zeichen = Rueckmeldestand.allCases.map(z) + [Rueckmeldungsliste.nichtBetroffen]
        #expect(Set(zeichen).count == 4 && zeichen.allSatisfy { !$0.isEmpty }, "vier verschiedene Zeichen")
        #expect(!stern.isEmpty && zeichen.allSatisfy { !$0.contains(stern) })
    }

    @Test("E409: Legende mit den Wörtern der Mitteilung, Notizen im Anhang — je Mitteilung in Spaltenfolge, je Person in Zeilenfolge")
    func legendeUndAnhang() throws {
        let liste = try #require(Rueckmeldungsliste.liste(bestand(), gruppe: "g1", mitteilungen: ["m1", "m2"],
                                                          stand: stand))
        #expect(liste.legende.map(\.zeichen) == [z(.offen), z(.erledigt), z(.abgelehnt),
                                                 Rueckmeldungsliste.nichtBetroffen, Rueckmeldungsliste.mitNotiz])
        #expect(liste.legende.map(\.bedeutung) == ["offen", "erledigt", "abgelehnt", "nicht betroffen", "Notiz im Anhang"])
        #expect(liste.anhangstitel == "Notizen")
        #expect(liste.anhang.map(\.ueberschrift) == ["Wandertag · 01.09.2026"])
        #expect(liste.anhang.first?.eintraege == [.init(name: "Abel, Anna (Anni)", text: "erledigt, 02.09.2026: Unterschrift der Mutter"),
                                                  .init(name: "Zimmer, Ada", text: "offen: fragt nach"),
                                                  .init(name: "Ost, Olaf", text: "erledigt, 02.09.2026: nicht mehr in der Gruppe")],
                "Olafs Notiz nach den Mitgliedern, wie seine Zeile (E484)")
        let ohneNotiz = try #require(Rueckmeldungsliste.liste(bestand(), gruppe: "g1", mitteilungen: ["m2"], stand: stand))
        #expect(ohneNotiz.anhang.isEmpty && !ohneNotiz.legende.contains { $0.zeichen == Rueckmeldungsliste.mitNotiz })
    }

    @Test("E411/E408: Kopf mit Lerngruppe, Schuljahr und Stand — ohne Fach (E665); keine Liste ohne Gruppe oder ohne gewählte Mitteilung der Gruppe")
    func kopfUndOhne() throws {
        let liste = try #require(Rueckmeldungsliste.liste(bestand(), gruppe: "g1", mitteilungen: ["m1"], stand: stand))
        #expect(liste.kopf == ["6a", "Rückmeldungsliste", "Schuljahr 2026/27", "Stand 11.10.2026"])
        var ohneJahr = bestand()
        ohneJahr.schuljahr = ""
        #expect(Rueckmeldungsliste.liste(ohneJahr, gruppe: "g1", mitteilungen: ["m1"], stand: stand)?.kopf
                == ["6a", "Rückmeldungsliste", "Stand 11.10.2026"], "ohne Schuljahr kein leerer Teil (Z-AT16-03)")
        let foerderkurs = try #require(Rueckmeldungsliste.liste(bestand(), gruppe: "g2", mitteilungen: ["m3"], stand: stand))
        #expect(foerderkurs.kopf == ["Förderkurs", "Rückmeldungsliste", "Schuljahr 2026/27", "Stand 11.10.2026"])
        #expect(foerderkurs.zeilen.map(\.name) == ["Ost, Olaf"] && foerderkurs.zeilen.first?.zellen == [z(.offen)],
                "Olafs Rücklauf mit Notiz gehört zu „Wandertag“, nicht zu „Ausflug“")
        #expect(Rueckmeldungsliste.liste(bestand(), gruppe: "fehlt", mitteilungen: ["m1"], stand: stand) == nil)
        #expect(Rueckmeldungsliste.liste(bestand(), gruppe: "g1", mitteilungen: [], stand: stand) == nil)
        #expect(Rueckmeldungsliste.liste(bestand(), gruppe: "g1", mitteilungen: ["m3", "n1"], stand: stand) == nil)
    }

    // ── Der Umbruch (E411) ────────────────────────────────────────────────

    @Test("E411: gleich große Stücke — 30 Zeilen bei 27 je Seite werden 15 und 15; ohne Zeilen ein leeres Stück")
    func stuecke() {
        #expect(Listenumbruch.stuecke(30, hoechstens: 27) == [0..<15, 15..<30])
        #expect(Listenumbruch.stuecke(27, hoechstens: 27) == [0..<27])
        #expect(Listenumbruch.stuecke(19, hoechstens: 9) == [0..<7, 7..<13, 13..<19])
        #expect(Listenumbruch.stuecke(0, hoechstens: 9) == [0..<0])
        #expect(Listenumbruch.stuecke(3, hoechstens: 0) == [0..<1, 1..<2, 2..<3])
    }

    @Test("E411: A4 quer; die Namensspalte auf jeder Seite — Spaltengruppen außen, Zeilenbänder innen")
    func tabellenseiten() {
        let m = Listenumbruch.Mass.a4quer
        #expect(m.blatt == CGSize(width: 842, height: 595))
        #expect(m.spaltenJeSeite == 9 && m.zeilenJeSeite == 30)
        #expect(Listenumbruch.tabellenseiten(zeilen: 35, spalten: 10, mass: m)
                == [.tabelle(spalten: 0..<5, zeilen: 0..<18), .tabelle(spalten: 0..<5, zeilen: 18..<35),
                    .tabelle(spalten: 5..<10, zeilen: 0..<18), .tabelle(spalten: 5..<10, zeilen: 18..<35)])
        #expect(Listenumbruch.tabellenseiten(zeilen: 0, spalten: 0, mass: m) == [.tabelle(spalten: 0..<0, zeilen: 0..<0)])
        #expect(Listenumbruch.tabellenseiten(zeilen: 30, spalten: 9, mass: m).count == 1)
    }

    @Test("E409: der Anhang auf eigenen Seiten — eine Überschrift steht nie allein am Fuß")
    func anhangsseiten() {
        var m = Listenumbruch.Mass.a4quer
        m.blatt.height = 100 + 2 * m.rand + m.kopfhoehe + m.fusshoehe
        #expect(m.anhanghoehe == 100)
        // Titel 24 + vier Zeilen 48 = 72; die Überschrift (20) passte noch, ihre erste Zeile (12) nicht mehr.
        #expect(Listenumbruch.anhangsseiten([.titel, .text, .text, .text, .text, .ueberschrift, .text, .text], mass: m)
                == [0..<5, 5..<8])
        #expect(Listenumbruch.anhangsseiten([.titel] + Array(repeating: .text, count: 10), mass: m) == [0..<7, 7..<11])
        #expect(Listenumbruch.anhangsseiten([], mass: m).isEmpty)
    }

    @Test("E411: Seite n von m — erst die Tabelle, dann der Anhang")
    func seitenGezaehlt() {
        let s = Listenumbruch.seiten(zeilen: 35, spalten: 10, anhang: [.titel, .ueberschrift, .text], mass: .a4quer)
        #expect(s.count == 5)
        #expect(s.map(\.nummer) == [1, 2, 3, 4, 5])
        #expect(s.map(\.von) == [5, 5, 5, 5, 5])
        #expect(s.first?.inhalt == .tabelle(spalten: 0..<5, zeilen: 0..<18))
        #expect(s.last?.inhalt == .anhang(0..<3))
        #expect(Listenumbruch.seiten(zeilen: 3, spalten: 2, anhang: [], mass: .a4quer)
                == [.init(inhalt: .tabelle(spalten: 0..<2, zeilen: 0..<3), nummer: 1, von: 1)])
    }

    // ── Das PDF (E405, E406, E411) ────────────────────────────────────────

    private func pdfDaten(_ ausgabe: Listensatz.Ausgabe) -> Data? {
        if case .verschluesselt(let d) = ausgabe { return d }
        return nil
    }

    /// Eine kleine Liste von Hand — der Listensatz, unabhängig von der Rückmeldungsliste.
    private func kleineListe() -> Liste {
        Liste(kopf: ["6b", "Chemie", "Probe"], namensspalte: "Name",
              spalten: [.init(titel: "Eins", unterzeile: "01.10.2026"), .init(titel: "Zwei")],
              zeilen: [.init(name: "Abel, Anna (Anni)", zellen: ["x", "y"]), .init(name: "Bauer, Ben", zellen: ["", "z"])],
              legende: [.init(zeichen: "x", bedeutung: "eine Probe")])
    }

    /// Der Text jeder Seite, nach dem Entsperren.
    private func seitentexte(_ daten: Data) throws -> [String] {
        let pdf = try #require(PDFDocument(data: daten))
        #expect(pdf.isLocked)
        #expect(pdf.unlock(withPassword: kennwort))
        return (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
    }

    @Test("E406/E45: Kennwort mindestens 12 Zeichen, nicht nur Leerraum; im PDF-Format nur ASCII, höchstens 32 — sonst kein PDF, mit Grund")
    func kennwortregel() {
        let liste = kleineListe()
        let abgewiesen = ["", "elf Zeichen", String(repeating: " ", count: 12), "Straße-am-Meer-12",
                          String(repeating: "a", count: 33),
                          // Steuerzeichen — nur druckbares ASCII (Z-AT16-01).
                          "Elternbriefe\u{07}2026", "Elternbriefe 2026\u{7F}", "Eltern\u{00}briefe 2026"]
        for k in abgewiesen {
            #expect(Listensatz.kennwortEinwand(k) != nil, "„\(k)“")
            #expect(pdfDaten(Listensatz.pdf(liste, kennwort: k)) == nil, "kein PDF mit „\(k)“")
        }
        #expect(Listensatz.kennwortEinwand("elf Zeichen")?.contains("12") == true)
        #expect(Listensatz.kennwortEinwand(String(repeating: " ", count: 12))?.contains("Leerraum") == true)
        #expect(Listensatz.kennwortEinwand("Straße-am-Meer-12")?.contains("ASCII") == true)
        #expect(Listensatz.kennwortEinwand(String(repeating: "a", count: 33))?.contains("32") == true)
        #expect(Listensatz.kennwortEinwand("Elternbriefe\u{07}2026")?.contains("Steuerzeichen") == true)
        for k in ["123456789012", "Ein langes Kennwort", String(repeating: "a", count: 32)] {
            #expect(Listensatz.kennwortEinwand(k) == nil, "„\(k)“")
            #expect(pdfDaten(Listensatz.pdf(liste, kennwort: k)) != nil, "ein PDF mit „\(k)“")
        }
    }

    @Test("E405: verschlüsselt — /Encrypt mit /V 4 /R 4 und /AESV2 (AES-128); ohne Kennwort nicht lesbar, mit Kennwort lesbar")
    func verschluesselt() throws {
        let daten = try #require(pdfDaten(Listensatz.pdf(kleineListe(), kennwort: kennwort)))
        let roh = String(decoding: daten, as: Unicode.ASCII.self)
        #expect(roh.hasPrefix("%PDF-"))
        #expect(roh.range(of: #"/Encrypt\s"#, options: .regularExpression) != nil)
        // Die Muster nur im Verschlüsselungseintrag — „/Length 128“ könnte sonst die Länge eines Datenstroms sein (Z-AT16-05).
        let eintrag = try #require(roh.range(of: #"/Filter\s*/Standard[\s\S]*?endobj"#, options: .regularExpression)
            .map { String(roh[$0]) })
        for muster in [#"/V\s+4\b"#, #"/R\s+4\b"#, #"/CFM\s*/AESV2"#, #"/Length\s+128\b"#] {
            #expect(eintrag.range(of: muster, options: .regularExpression) != nil, "\(muster)")
        }
        let quelle = try #require(CGDataProvider(data: daten as CFData))
        let cg = try #require(CGPDFDocument(quelle))
        #expect(cg.isEncrypted && !cg.isUnlocked)
        #expect(!cg.unlockWithPassword(""), "ohne Kennwort nicht lesbar")
        #expect(!cg.unlockWithPassword("Elternbriefe 2025"))
        let texte = try seitentexte(daten)
        #expect(texte.count == 1 && texte.first?.contains("Abel, Anna (Anni)") == true, "mit Kennwort lesbar")
    }

    @Test("E411: A4 quer, Kopf und Namensspalte auf jeder Seite, „Seite n von m“; die Notizen auf der Folgeseite")
    func seitenImPDF() throws {
        var b = bestand()
        let kinder = (1...35).map { person(String(format: "k%02d", $0), "Vera", String(format: "Kind %02d", $0)) }
        b.lernende += kinder
        b.lerngruppen[0].mitglieder = kinder.map(\.id)
        let titel = "ABCDEFGHIJ".map { "Brief \($0)" }
        b.anliegen = titel.enumerated().map { stelle, t in
            anliegen("b\(stelle)", .mitteilung, t, gruppe: "g1", datum: "2026-09-0\(stelle % 9 + 1)", kinder.map(\.id))
        }
        b.rueckmeldungen = [ruecklauf("b0", "k01", .erledigt, datum: "2026-09-02", notiz: "kommt mit dem Bus")]
        let liste = try #require(Rueckmeldungsliste.liste(b, gruppe: "g1", mitteilungen: Set(b.anliegen.map(\.id)),
                                                          stand: stand))
        let daten = try #require(pdfDaten(Listensatz.pdf(liste, kennwort: kennwort)))
        let pdf = try #require(PDFDocument(data: daten))
        #expect(pdf.isLocked, "zu ohne Kennwort — `unlock` allein wäre auch an einem offenen PDF wahr (Z-AT16-05)")
        #expect(pdf.unlock(withPassword: kennwort))
        #expect(pdf.pageCount == 5, "zwei Spaltengruppen mal zwei Bänder, dann der Anhang")
        let namen = kinder.map { "\($0.nachname), \($0.vorname)" }
        for nummer in 1...pdf.pageCount {
            let seite = try #require(pdf.page(at: nummer - 1))
            #expect(seite.bounds(for: .mediaBox).size == CGSize(width: 842, height: 595), "A4 quer, Seite \(nummer)")
            let text = seite.string ?? ""
            #expect(text.contains("6a · Rückmeldungsliste · Schuljahr 2026/27 · Stand 11.10.2026"), "Kopf, Seite \(nummer)")
            #expect(text.contains("Seite \(nummer) von 5"))
            guard nummer <= 4 else { continue }
            let band = nummer % 2 == 1 ? 0..<18 : 18..<35
            let gruppe = nummer <= 2 ? 0..<5 : 5..<10
            #expect(text.contains("Name") && text.contains("Legende"), "Seite \(nummer)")
            #expect(band.allSatisfy { text.contains(namen[$0]) }, "die Namensspalte auf Seite \(nummer)")
            #expect(!namen.indices.filter { !band.contains($0) }.contains { text.contains(namen[$0]) })
            #expect(titel.indices.allSatisfy { gruppe.contains($0) == text.contains(titel[$0]) }, "Spalten, Seite \(nummer)")
        }
        let anhang = try #require(pdf.page(at: 4)?.string)
        #expect(anhang.contains("Notizen") && anhang.contains("Kind 01, Vera") && anhang.contains("kommt mit dem Bus"))
        #expect(!anhang.contains("Legende"))
    }

    @Test("E483/Z-AT16-02: vor der Ausgabe nachgeprüft — verschlüsselt, AESV2, öffnet nur mit genau dem Kennwort; sonst kein PDF")
    func nachpruefung() throws {
        func probe(_ zusatz: [CFString: Any]?) throws -> Data {
            let puffer = NSMutableData()
            var kasten = CGRect(x: 0, y: 0, width: 100, height: 100)
            let verbraucher = try #require(CGDataConsumer(data: puffer))
            let feld = try #require(CGContext(consumer: verbraucher, mediaBox: &kasten, zusatz.map { $0 as CFDictionary }))
            feld.beginPDFPage(nil)
            feld.endPDFPage()
            feld.closePDF()
            return puffer as Data
        }
        func schutz(_ k: String, bit: Int) -> [CFString: Any] {
            [kCGPDFContextUserPassword: k, kCGPDFContextOwnerPassword: k, kCGPDFContextEncryptionKeyLength: bit]
        }
        #expect(!Listensatz.verschluesselungBelegt(try probe(nil), kennwort: kennwort), "unverschlüsselt")
        #expect(!Listensatz.verschluesselungBelegt(try probe(schutz(kennwort, bit: 40)), kennwort: kennwort), "RC4, 40 Bit")
        #expect(!Listensatz.verschluesselungBelegt(try probe(schutz("anderes Kennwort", bit: 128)), kennwort: kennwort),
                "ein anderes Kennwort")
        // Nur ein Eigentümerkennwort: AESV2, mit dem Kennwort zu öffnen — aber ohne Kennwort schon offen (Z-NF-04).
        #expect(!Listensatz.verschluesselungBelegt(
            try probe([kCGPDFContextOwnerPassword: kennwort, kCGPDFContextEncryptionKeyLength: 128]), kennwort: kennwort),
                "nur ein Eigentümerkennwort")
        let echt = try #require(pdfDaten(Listensatz.pdf(kleineListe(), kennwort: kennwort)))
        #expect(Listensatz.verschluesselungBelegt(echt, kennwort: kennwort))
    }

    @Test("E484 im PDF (Z-NF-03): die Zwischenzeile nach den Mitgliedern, darunter wer nicht mehr Mitglied ist")
    func zwischenzeileImPDF() throws {
        let liste = try #require(Rueckmeldungsliste.liste(bestand(), gruppe: "g1", mitteilungen: ["m1"], stand: stand))
        let daten = try #require(pdfDaten(Listensatz.pdf(liste, kennwort: kennwort)))
        let text = try #require(try seitentexte(daten).first)
        let ada = try #require(text.range(of: "Zimmer, Ada"))
        let trenner = try #require(text.range(of: Rueckmeldungsliste.nichtMehrMitglied))
        let olaf = try #require(text.range(of: "Ost, Olaf"))
        #expect(ada.upperBound <= trenner.lowerBound && trenner.upperBound <= olaf.lowerBound)
    }

    @Test("Z-AT16-05: genau das getippte Kennwort — 32 Zeichen öffnen, 31 nicht; Leerraum am Rand zählt mit")
    func genauesKennwort() throws {
        for (richtig, falsch) in [(String(repeating: "a", count: 32), String(repeating: "a", count: 31)),
                                  ("  Elternbriefe 2026  ", "Elternbriefe 2026")] {
            let daten = try #require(pdfDaten(Listensatz.pdf(kleineListe(), kennwort: richtig)), "„\(richtig)“")
            let quelle = try #require(CGDataProvider(data: daten as CFData))
            let cg = try #require(CGPDFDocument(quelle))
            #expect(!cg.unlockWithPassword(falsch), "„\(falsch)“ öffnet nicht")
            #expect(cg.unlockWithPassword(richtig), "„\(richtig)“ öffnet")
        }
    }

    @Test("Z-AT16-04: Spalten in der Folge des Blatts, nicht nach Tag oder Kennung; der Anhang je Mitteilung in Spaltenfolge, je Person in Zeilenfolge — gleich, wie die Rückläufe in der Datei stehen")
    func folgen() throws {
        var b = Lernendenbestand.leer(planung: "p1", schuljahr: "2026/27", jetzt: "")
        b.lernende = [person("p1", "Ada", "Zimmer"), person("p2", "Anna", "Abel")]
        b.lerngruppen = [gruppe("g1", "7c", ["p1", "p2"])]
        b.anliegen = [anliegen("m9", .mitteilung, "Zeugnis", gruppe: "g1", datum: "2026-10-20", ["p1", "p2"]),
                      anliegen("m0", .mitteilung, "Ausflug", gruppe: "g1", datum: "2026-09-01", ["p1", "p2"])]
        b.rueckmeldungen = [ruecklauf("m0", "p1", .erledigt, notiz: "Ada zum Ausflug"),
                            ruecklauf("m0", "p2", .offen, notiz: "Anna zum Ausflug"),
                            ruecklauf("m9", "p1", .erledigt, notiz: "Ada zum Zeugnis"),
                            ruecklauf("m9", "p2", .abgelehnt, notiz: "Anna zum Zeugnis")]
        let liste = try #require(Rueckmeldungsliste.liste(b, gruppe: "g1", mitteilungen: ["m0", "m9"], stand: stand))
        #expect(liste.spalten.map(\.titel) == ["Zeugnis", "Ausflug"], "Folge des Blatts — später im Kalender, größere Kennung")
        #expect(liste.anhang.map(\.ueberschrift) == ["Zeugnis · 20.10.2026", "Ausflug · 01.09.2026"])
        #expect(liste.anhang.map { $0.eintraege.map(\.name) } == [["Abel, Anna", "Zimmer, Ada"], ["Abel, Anna", "Zimmer, Ada"]],
                "in Zeilenfolge, nicht in der Folge der Datei")
    }

    // ── Die zweite, künstliche Tabelle (E412) ─────────────────────────────

    @Test("E412: eine zweite, künstliche Tabelle (Noten) über denselben Listensatz — und dieselben Seiten für den Druck")
    func zweiteTabelle() throws {
        let spalten = "ABCDEFGHIJKLMNOPQRST".map { Liste.Spalte(titel: "Leistung \($0)") }
        let noten = ["1", "2+", "3-", "", "4"]
        let zeilen = (1...40).map { i in
            Liste.Zeile(name: String(format: "Schüler %02d, Sam", i), zellen: spalten.indices.map { noten[(i + $0) % noten.count] })
        }
        let lang = String(repeating: "Mündlich stark, schriftlich mit Luft nach oben. ", count: 12)
        let liste = Liste(kopf: ["Q1", "Mathematik", "Notenliste", "Schuljahr 2026/27", "Stand 11.10.2026"],
                          namensspalte: "Name", spalten: spalten, zeilen: zeilen,
                          legende: [.init(zeichen: "+/-", bedeutung: "Tendenz")],
                          anhangstitel: "Bemerkungen",
                          anhang: [.init(ueberschrift: "Leistung A", eintraege: [.init(name: "Schüler 01, Sam", text: lang)])])
        let daten = try #require(pdfDaten(Listensatz.pdf(liste, kennwort: kennwort)))
        let texte = try seitentexte(daten)
        #expect(texte.count == 7, "drei Spaltengruppen mal zwei Bänder, dann der Anhang")
        for (stelle, text) in texte.enumerated() {
            #expect(text.contains("Q1 · Mathematik · Notenliste") && text.contains("Seite \(stelle + 1) von 7"))
            if stelle < 6 {
                let erster = stelle % 2 == 0 ? "Schüler 01, Sam" : "Schüler 21, Sam"
                #expect(text.contains("Name") && text.contains(erster) && text.contains("Tendenz"), "Seite \(stelle + 1)")
            }
        }
        #expect(texte.last?.contains("Bemerkungen") == true && texte.last?.contains("Luft nach oben") == true)
        let druck = try #require(Listensatz.druckschriftstueck(liste))
        #expect(druck.numberOfPages == 7 && !druck.isEncrypted, "dieselben Seiten für den Druck, nur im Speicher")
    }
}
