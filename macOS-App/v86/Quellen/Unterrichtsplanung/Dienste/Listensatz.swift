// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreText
import Foundation

// ── Der Listensatz (v84, AT16; E405, E406, E409, E411, E412) ──────────────
//
// Setzt eine `Liste` auf DIN A4 quer (E411): auf jeder Seite die Kopfzeile,
// die Namensspalte und „Seite n von m“; weitere Spalten auf Folgeseiten, die
// Legende unter jeder Tabelle, der Anhang auf eigenen Seiten (E409). Gesetzt
// mit Core Text in ein PDF im Speicher — für die Ausgabe von der ersten Seite
// an verschlüsselt (E405): Ein unverschlüsseltes PDF entsteht dafür nicht,
// weder auf der Platte noch im Speicher.

/// Welche Spalten und Zeilen auf welche Seite kommen — reine Rechnung an
/// Zahlen, ohne Schrift und ohne Zeichnen; der Satz hält sich daran.
enum Listenumbruch {
    /// Die Maße einer Seite in Punkt, von oben gezählt.
    struct Mass: Hashable, Sendable {
        /// DIN A4 quer (E411).
        var blatt = CGSize(width: 842, height: 595)
        var rand: CGFloat = 28
        var kopfhoehe: CGFloat = 28
        /// Bis zu drei Zeilen Titel und eine Unterzeile.
        var spaltenkopfhoehe: CGFloat = 46
        var zeilenhoehe: CGFloat = 14
        var legendenhoehe: CGFloat = 20
        var fusshoehe: CGFloat = 14
        var namensbreite: CGFloat = 200
        var spaltenbreite: CGFloat = 64
        /// Die Zeilen des Anhangs: Titel, Überschrift eines Abschnitts, Text.
        var anhangtitelhoehe: CGFloat = 24
        var anhangueberschrifthoehe: CGFloat = 20
        var anhangzeilenhoehe: CGFloat = 12

        static let a4quer = Mass()

        var breite: CGFloat { blatt.width - 2 * rand }
        /// Was zwischen Spaltenkopf und Legende für Zeilen bleibt.
        var tabellenhoehe: CGFloat {
            blatt.height - 2 * rand - kopfhoehe - spaltenkopfhoehe - legendenhoehe - fusshoehe
        }
        var anhanghoehe: CGFloat { blatt.height - 2 * rand - kopfhoehe - fusshoehe }
        var spaltenJeSeite: Int { Mass.anzahl(breite - namensbreite, je: spaltenbreite) }
        var zeilenJeSeite: Int { Mass.anzahl(tabellenhoehe, je: zeilenhoehe) }

        func hoehe(_ zeile: Anhangszeile) -> CGFloat {
            switch zeile {
            case .titel: anhangtitelhoehe
            case .ueberschrift: anhangueberschrifthoehe
            case .text: anhangzeilenhoehe
            }
        }

        /// Wie oft `je` in `platz` passt — mindestens einmal, sonst käme der Umbruch nie zum Ende.
        private static func anzahl(_ platz: CGFloat, je: CGFloat) -> Int {
            guard je > 0, platz.isFinite, platz >= je else { return 1 }
            return Int(min(platz / je, 10_000).rounded(.down))
        }
    }

    enum Anhangszeile: Hashable, Sendable { case titel, ueberschrift, text }

    /// Was auf einer Seite steht: Spalten und Zeilen der Tabelle — oder Zeilen des Anhangs.
    enum Inhalt: Hashable, Sendable {
        /// `zwischenzeile`: Das Band beginnt mit Ehemaligen — die Zwischenzeile steht oben noch einmal (E737).
        case tabelle(spalten: Range<Int>, zeilen: Range<Int>, zwischenzeile: Bool = false)
        case anhang(Range<Int>)
    }

    struct Seite: Hashable, Sendable {
        var inhalt: Inhalt
        /// „Seite n von m“, ab 1.
        var nummer: Int
        var von: Int
    }

    /// `anzahl` in möglichst gleich große Stücke zu höchstens `hoechstens`: 30 Zeilen bei 27 je
    /// Seite werden 15 und 15, nicht 27 und 3 — wie die Bänder des Ausdrucks (`Drucken.baender`).
    /// Ohne Elemente ein leeres Stück: Kopf und Namensspalte stehen trotzdem.
    static func stuecke(_ anzahl: Int, hoechstens: Int) -> [Range<Int>] {
        guard anzahl > 0 else { return [0..<0] }
        let je = max(1, hoechstens)
        return teilen(anzahl, in: anzahl / je + (anzahl % je == 0 ? 0 : 1))
    }

    /// `anzahl` in genau `zahl` möglichst gleich große Stücke, die längeren vorn.
    private static func teilen(_ anzahl: Int, in zahl: Int) -> [Range<Int>] {
        let grund = anzahl / zahl
        let rest = anzahl % zahl
        var stuecke: [Range<Int>] = []
        var anfang = 0
        for stelle in 0..<zahl {
            let laenge = grund + (stelle < rest ? 1 : 0)
            stuecke.append(anfang..<(anfang + laenge))
            anfang += laenge
        }
        return stuecke
    }

    /// Die Bänder der Zeilen wie `stuecke`, dazu zwei Regeln für die Zwischenzeile „nicht mehr in der Lerngruppe“
    /// (`trenner`): Sie steht nie als letzte eines Bands, sondern über den Zeilen unter ihr — das Band schließt eine Zeile
    /// früher (E687); und beginnt ein Band mit Ehemaligen, steht sie dort oben noch einmal — es trägt dann eine Zeile
    /// weniger (E737). Passt das nicht, ein Band mehr, wieder gleich geteilt; kein Band wird länger als `hoechstens`.
    static func baender(_ anzahl: Int, trenner: Int?, hoechstens: Int) -> [Range<Int>] {
        let ohne = stuecke(anzahl, hoechstens: hoechstens)
        guard let t = trenner, anzahl > 0, hoechstens > 1 else { return ohne }
        for zahl in ohne.count...anzahl {
            var baender = teilen(anzahl, in: zahl)
            if let i = baender.firstIndex(where: { $0.count > 1 && $0.upperBound - 1 == t }), i + 1 < baender.count {
                baender[i] = baender[i].lowerBound..<t
                baender[i + 1] = t..<baender[i + 1].upperBound
            }
            if baender.allSatisfy({ $0.count + (wiederholt($0, trenner: t, hoechstens: hoechstens) ? 1 : 0) <= hoechstens }) {
                return baender
            }
        }
        return ohne
    }

    /// Ob ein Band mit Ehemaligen beginnt und darum die Zwischenzeile oben noch einmal trägt (E737) — nicht bei einer
    /// Zeile je Seite: Dort ist kein Platz für sie.
    static func wiederholt(_ band: Range<Int>, trenner: Int?, hoechstens: Int) -> Bool {
        guard let trenner, hoechstens > 1 else { return false }
        return band.lowerBound > trenner
    }

    /// Die Seiten der Tabelle: die Spalten in Gruppen, je Gruppe die Zeilen in Bändern — auf jeder
    /// Seite die Namensspalte (E411). Erst alle Bänder der ersten Gruppe, dann die nächste — wie
    /// beim Ausdruck der Planung erst die Wochen, dann die Zeilen. `trenner`: die Zeile der Zwischenzeile (E687, E737).
    static func tabellenseiten(zeilen: Int, spalten: Int, mass: Mass, trenner: Int? = nil) -> [Inhalt] {
        let baender = Self.baender(zeilen, trenner: trenner, hoechstens: mass.zeilenJeSeite)
        return stuecke(spalten, hoechstens: mass.spaltenJeSeite).flatMap { gruppe in
            baender.map {
                Inhalt.tabelle(spalten: gruppe, zeilen: $0,
                               zwischenzeile: wiederholt($0, trenner: trenner, hoechstens: mass.zeilenJeSeite))
            }
        }
    }

    /// Die Zeilen des Anhangs auf Seiten, der Reihe nach. Eine Überschrift nimmt ihre erste
    /// Zeile mit — allein am Fuß einer Seite stünde sie verloren.
    static func anhangsseiten(_ zeilen: [Anhangszeile], mass: Mass) -> [Range<Int>] {
        var seiten: [Range<Int>] = []
        var anfang = 0
        var belegt: CGFloat = 0
        for (stelle, zeile) in zeilen.enumerated() {
            let hoehe = mass.hoehe(zeile)
            let braucht = zeile != .text && stelle + 1 < zeilen.count ? hoehe + mass.hoehe(zeilen[stelle + 1]) : hoehe
            if stelle > anfang, belegt + braucht > mass.anhanghoehe {
                seiten.append(anfang..<stelle)
                anfang = stelle
                belegt = 0
            }
            belegt += hoehe
        }
        if anfang < zeilen.count { seiten.append(anfang..<zeilen.count) }
        return seiten
    }

    /// Alle Seiten, gezählt: erst die Tabelle, dann der Anhang auf eigenen Seiten (E409, E411).
    static func seiten(zeilen: Int, spalten: Int, anhang: [Anhangszeile], mass: Mass, trenner: Int? = nil) -> [Seite] {
        let inhalte = tabellenseiten(zeilen: zeilen, spalten: spalten, mass: mass, trenner: trenner)
            + anhangsseiten(anhang, mass: mass).map { Inhalt.anhang($0) }
        return inhalte.enumerated().map { Seite(inhalt: $1, nummer: $0 + 1, von: inhalte.count) }
    }
}

/// Das PDF einer `Liste` — verschlüsselt zum Sichern, unverschlüsselt nur als
/// Schriftstück im Speicher für den Druck. Eine Ausgabe ohne Kennwort gibt es nicht.
@MainActor
enum Listensatz {
    /// Was `pdf(_:kennwort:)` liefert: das verschlüsselte PDF — oder den Grund, warum keines entstand.
    enum Ausgabe: Equatable, Sendable {
        case verschluesselt(Data)
        case abgewiesen(String)
    }

    /// `nil`, wenn das Kennwort taugt; sonst der Grund. Mindestens 12 Zeichen und nicht nur
    /// Leerraum wie die Passphrase (E406) — dazu die Grenzen des PDF-Formats wie beim Sitzplan
    /// (E45): nur ASCII, höchstens 32 Zeichen; nichts wird still gekürzt. Steuerzeichen nicht:
    /// Mancher Leser deutet sie anders, eine NUL könnte das Kennwort verkürzen (Z-AT16-01).
    static func kennwortEinwand(_ kennwort: String) -> String? {
        guard Tresor.passphraseZulaessig(kennwort) else {
            return kennwort.count < Tresor.passphraseMindestlaenge
                ? "Das Kennwort braucht mindestens \(Tresor.passphraseMindestlaenge) Zeichen."
                : "Ein Kennwort nur aus Leerraum gilt nicht."
        }
        if kennwort.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return "Das Kennwort darf keine Steuerzeichen enthalten."
        }
        return Sitzplandruck.kennwortEinwand(kennwort)
    }

    /// Das PDF, verschlüsselt mit dem getippten Kennwort (E405, E406) — Nutzer- und
    /// Eigentümerkennwort gleich, 128 Bit. Core Graphics schreibt damit `/V 4 /R 4` mit
    /// `/CFM /AESV2` (AES-128), gemessen wie bei PDFKit (macOS 26.7.1); die Suite hält es am
    /// Ergebnis fest. Mit unzulässigem Kennwort kein PDF, sondern der Grund.
    static func pdf(_ liste: Liste, kennwort: String, mass: Listenumbruch.Mass = .a4quer) -> Ausgabe {
        if let einwand = kennwortEinwand(kennwort) { return .abgewiesen(einwand) }
        let schutz: [CFString: Any] = [kCGPDFContextUserPassword: kennwort, kCGPDFContextOwnerPassword: kennwort,
                                       kCGPDFContextEncryptionKeyLength: 128]
        guard let daten = setzen(liste, mass: mass, schutz: schutz) else {
            return .abgewiesen("Die Liste ließ sich nicht setzen.")
        }
        guard verschluesselungBelegt(daten, kennwort: kennwort) else {
            return .abgewiesen("Das PDF ließ sich nicht wie verlangt verschlüsseln — es wird nicht ausgegeben.")
        }
        return .verschluesselt(daten)
    }

    /// Dieselben Seiten für den Druck (AT17, Muster `Sitzplandruck.drucken`) — unverschlüsselt,
    /// darum nur als Schriftstück im Speicher, nie als Daten, die sich schreiben ließen.
    static func druckschriftstueck(_ liste: Liste, mass: Listenumbruch.Mass = .a4quer) -> CGPDFDocument? {
        guard let daten = setzen(liste, mass: mass, schutz: nil),
              let quelle = CGDataProvider(data: daten as CFData) else { return nil }
        return CGPDFDocument(quelle)
    }

    /// Trägt `daten` wirklich, was E405 verlangt? Verschlüsselt, AES (`/AESV2`), zu ohne Kennwort, offen mit genau
    /// diesem (E483, Z-AT16-02) — nachgeprüft am Ergebnis, nicht vorausgesetzt.
    static func verschluesselungBelegt(_ daten: Data, kennwort: String) -> Bool {
        guard let quelle = CGDataProvider(data: daten as CFData), let dokument = CGPDFDocument(quelle),
              dokument.isEncrypted, !dokument.isUnlocked, dokument.unlockWithPassword(kennwort) else { return false }
        // Der Verschlüsselungseintrag selbst ist nie verschlüsselt — Verfahren und Filter stehen dort im Klartext;
        // gesucht wird nur in ihm, wie Core Graphics ihn schreibt (gemessen 11.10.2026, Z-NF-05).
        let roh = String(decoding: daten, as: Unicode.ASCII.self)
        guard let bereich = roh.range(of: #"/Filter\s*/Standard[\s\S]*?endobj"#, options: .regularExpression) else {
            return false
        }
        let eintrag = roh[bereich]
        return [#"/V\s+4\b"#, #"/R\s+4\b"#, #"/CFM\s*/AESV2"#, #"/StmF\s*/StdCF"#, #"/StrF\s*/StdCF"#].allSatisfy {
            eintrag.range(of: $0, options: .regularExpression) != nil
        }
    }

    private static func setzen(_ liste: Liste, mass: Listenumbruch.Mass, schutz: [CFString: Any]?) -> Data? {
        let satz = Satz(mass: mass)
        let anhang = satz.anhangszeilen(liste)
        let seiten = Listenumbruch.seiten(zeilen: liste.zeilen.count, spalten: liste.spalten.count,
                                          anhang: anhang.map(\.art), mass: mass,
                                          trenner: liste.zeilen.firstIndex(where: \.trenner))
        var kasten = CGRect(origin: .zero, size: mass.blatt)
        let puffer = NSMutableData()
        guard let verbraucher = CGDataConsumer(data: puffer),
              let feld = CGContext(consumer: verbraucher, mediaBox: &kasten, schutz.map { $0 as CFDictionary })
        else { return nil }
        for seite in seiten {
            feld.beginPDFPage(nil)
            feld.textMatrix = .identity
            satz.kopf(liste.kopf, in: feld)
            switch seite.inhalt {
            case .tabelle(let spalten, let zeilen, let zwischenzeile):
                // Eine Zwischenzeile je Liste — mehr kennt der Umbruch nicht (Z-AW5b-09).
                let wiederholt = zwischenzeile ? liste.zeilen.firstIndex(where: \.trenner).map { [$0] } ?? [] : []
                satz.tabelle(liste, spalten: spalten, reihen: wiederholt + Array(zeilen), in: feld)
            case .anhang(let bereich): satz.anhang(anhang[bereich], in: feld)
            }
            satz.fuss(seite, in: feld)
            feld.endPDFPage()
        }
        feld.closePDF()
        return puffer as Data
    }
}

// ── Das Zeichnen ──────────────────────────────────────────────────────────

/// Schriften, Zeilen und Striche einer Seite. Die Maße zählen von oben, Core
/// Graphics von unten — umgerechnet wird nur hier. Schwarz auf Weiß: Die
/// Zeichen unterscheiden sich in der Form, nicht in der Farbe.
private struct Satz {
    /// Eine fertig umbrochene Zeile des Anhangs.
    struct Anhangssatz {
        let art: Listenumbruch.Anhangszeile
        let zeile: CTLine
        let x: CGFloat
    }

    let mass: Listenumbruch.Mass
    let kopfschrift = Satz.schrift(11.5, fett: true)
    let spaltenschrift = Satz.schrift(8)
    let unterschrift = Satz.schrift(7.5)
    let namensschrift = Satz.schrift(9)
    let namenskopfschrift = Satz.schrift(9, fett: true)
    let zellenschrift = Satz.schrift(9.5)
    let kleinschrift = Satz.schrift(8)
    let kleinFett = Satz.schrift(8, fett: true)
    let anhangtitelschrift = Satz.schrift(11, fett: true)
    let ueberschriftschrift = Satz.schrift(9.5, fett: true)
    let anhangschrift = Satz.schrift(9)
    let anhangFett = Satz.schrift(9, fett: true)

    /// Einzug der Folgezeilen eines Eintrags im Anhang.
    let einzug: CGFloat = 12

    // ── Die Teile einer Seite ─────────────────────────────────────────────

    func kopf(_ teile: [String], in feld: CGContext) {
        let z = zeile(text(teile.joined(separator: " · "), kopfschrift), breite: mass.breite)
        zeichnen(z, x: mass.rand, grundlinie: mass.rand + 13, in: feld)
        strich(von: CGPoint(x: mass.rand, y: mass.rand + 19), bis: CGPoint(x: mass.rand + mass.breite, y: mass.rand + 19),
               grau: 0.6, staerke: 0.5, in: feld)
    }

    func fuss(_ seite: Listenumbruch.Seite, in feld: CGContext) {
        let z = zeile(text("Seite \(seite.nummer) von \(seite.von)", kleinschrift, grau: 0.35), breite: mass.breite)
        zeichnen(z, x: mass.rand + mass.breite - breite(z), grundlinie: mass.blatt.height - mass.rand - 3, in: feld)
    }

    /// Die Namensspalte, die Spalten der Gruppe, die Zeilen des Bands — `reihen`, in ihrer Folge, vorn vielleicht die
    /// wiederholte Zwischenzeile (E737); darunter die Legende.
    func tabelle(_ liste: Liste, spalten: Range<Int>, reihen: [Int], in feld: CGContext) {
        let x0 = mass.rand
        let y0 = mass.rand + mass.kopfhoehe
        let tabellenbreite = mass.namensbreite + CGFloat(spalten.count) * mass.spaltenbreite
        let koerper = y0 + mass.spaltenkopfhoehe
        let unten = koerper + CGFloat(reihen.count) * mass.zeilenhoehe

        flaeche(x0, y0, tabellenbreite, mass.spaltenkopfhoehe, grau: 0.92, in: feld)
        for stelle in 0..<reihen.count where stelle % 2 == 1 {
            flaeche(x0, koerper + CGFloat(stelle) * mass.zeilenhoehe, tabellenbreite, mass.zeilenhoehe, grau: 0.965, in: feld)
        }

        // Spaltenköpfe: unten bündig, die Unterzeile zuletzt.
        let fussKopf = koerper - 6
        zeichnen(zeile(text(liste.namensspalte, namenskopfschrift), breite: mass.namensbreite - 8),
                 x: x0 + 4, grundlinie: fussKopf, in: feld)
        for (stelle, spalte) in liste.spalten[spalten].enumerated() {
            let links = x0 + mass.namensbreite + CGFloat(stelle) * mass.spaltenbreite
            let platz = mass.spaltenbreite - 6
            var zeilenImKopf = umbrechen(text(spalte.titel, spaltenschrift), breite: platz, hoechstens: 3).map(\.zeile)
            if !spalte.unterzeile.isEmpty {
                zeilenImKopf.append(zeile(text(spalte.unterzeile, unterschrift, grau: 0.35), breite: platz))
            }
            for (nummer, z) in zeilenImKopf.reversed().enumerated() {
                zeichnen(z, x: links + (mass.spaltenbreite - breite(z)) / 2,
                         grundlinie: fussKopf - CGFloat(nummer) * 9.5, in: feld)
            }
        }

        // Die Zeilen: Name links, Zellen mittig; eine Zwischenzeile grau über die ganze Breite (E484).
        for (stelle, index) in reihen.enumerated() {
            let reihe = liste.zeilen[index]
            let oben = koerper + CGFloat(stelle) * mass.zeilenhoehe
            if reihe.trenner {
                zeichnen(zeile(text(reihe.name, kleinFett, grau: 0.35), breite: tabellenbreite - 8), x: x0 + 4,
                         grundlinie: mitte(oben, mass.zeilenhoehe, kleinFett), in: feld)
                continue
            }
            zeichnen(zeile(text(reihe.name, namensschrift), breite: mass.namensbreite - 8), x: x0 + 4,
                     grundlinie: mitte(oben, mass.zeilenhoehe, namensschrift), in: feld)
            for (spalte, inhalt) in spalten.enumerated() where inhalt < reihe.zellen.count && !reihe.zellen[inhalt].isEmpty {
                let z = zeile(text(reihe.zellen[inhalt], zellenschrift), breite: mass.spaltenbreite - 4)
                zeichnen(z, x: x0 + mass.namensbreite + CGFloat(spalte) * mass.spaltenbreite + (mass.spaltenbreite - breite(z)) / 2,
                         grundlinie: mitte(oben, mass.zeilenhoehe, zellenschrift), in: feld)
            }
        }

        // Linien: zwischen den Zeilen und Spalten fein, außen und unter dem Kopf kräftiger.
        for stelle in 1..<max(1, reihen.count) {
            let y = koerper + CGFloat(stelle) * mass.zeilenhoehe
            strich(von: CGPoint(x: x0, y: y), bis: CGPoint(x: x0 + tabellenbreite, y: y), grau: 0.8, staerke: 0.4, in: feld)
        }
        for stelle in 0..<spalten.count {
            let x = x0 + mass.namensbreite + CGFloat(stelle) * mass.spaltenbreite
            strich(von: CGPoint(x: x, y: y0), bis: CGPoint(x: x, y: unten), grau: 0.8, staerke: 0.4, in: feld)
        }
        strich(von: CGPoint(x: x0, y: koerper), bis: CGPoint(x: x0 + tabellenbreite, y: koerper), grau: 0.5, staerke: 0.6, in: feld)
        feld.setStrokeColor(gray: 0.5, alpha: 1)
        feld.setLineWidth(0.6)
        feld.stroke(rechteck(x0, y0, tabellenbreite, unten - y0))

        guard !liste.legende.isEmpty else { return }
        let legende = NSMutableAttributedString(attributedString: text("Legende:", kleinFett, grau: 0.2))
        for eintrag in liste.legende {
            legende.append(text("   " + eintrag.zeichen + " " + eintrag.bedeutung, kleinschrift, grau: 0.2))
        }
        zeichnen(zeile(legende, breite: mass.breite), x: x0, grundlinie: unten + 14, in: feld)
    }

    func anhang(_ zeilen: ArraySlice<Anhangssatz>, in feld: CGContext) {
        var oben = mass.rand + mass.kopfhoehe
        for z in zeilen {
            let hoehe = mass.hoehe(z.art)
            let abstand: CGFloat = switch z.art {
            case .titel: 7
            case .ueberschrift: 5
            case .text: 2.5
            }
            zeichnen(z.zeile, x: mass.rand + z.x, grundlinie: oben + hoehe - abstand, in: feld)
            oben += hoehe
        }
    }

    /// Der Anhang als fertige Zeilen: Titel, je Abschnitt die Überschrift, je Eintrag
    /// „Name: Text“ — umbrochen, die Folgezeilen und weiteren Absätze eingerückt.
    func anhangszeilen(_ liste: Liste) -> [Anhangssatz] {
        guard !liste.anhang.isEmpty else { return [] }
        var alle: [Anhangssatz] = []
        if !liste.anhangstitel.isEmpty {
            alle.append(Anhangssatz(art: .titel, zeile: zeile(text(liste.anhangstitel, anhangtitelschrift), breite: mass.breite), x: 0))
        }
        for abschnitt in liste.anhang {
            alle.append(Anhangssatz(art: .ueberschrift,
                                    zeile: zeile(text(abschnitt.ueberschrift, ueberschriftschrift), breite: mass.breite), x: 0))
            for eintrag in abschnitt.eintraege {
                let absaetze = eintrag.text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                for (nummer, absatz) in absaetze.enumerated() {
                    let inhalt = NSMutableAttributedString()
                    if nummer == 0 { inhalt.append(text(eintrag.name + ": ", anhangFett)) }
                    inhalt.append(text(String(absatz), anhangschrift))
                    let erste = nummer == 0 ? 0 : einzug
                    let gesetzt = umbrechen(inhalt, breite: mass.breite - erste, einzug: nummer == 0 ? einzug : 0)
                    if gesetzt.isEmpty {
                        alle.append(Anhangssatz(art: .text, zeile: zeile(text("", anhangschrift), breite: mass.breite), x: erste))
                    }
                    for z in gesetzt { alle.append(Anhangssatz(art: .text, zeile: z.zeile, x: erste + z.x)) }
                }
            }
        }
        return alle
    }

    // ── Text ──────────────────────────────────────────────────────────────

    static func schrift(_ groesse: CGFloat, fett: Bool = false) -> CTFont {
        CTFontCreateUIFontForLanguage(fett ? .emphasizedSystem : .system, groesse, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, groesse, nil)
    }

    func text(_ inhalt: String, _ schrift: CTFont, grau: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: inhalt, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): schrift,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: grau, alpha: 1),
        ])
    }

    /// Eine Zeile, die in `breite` passt — wo nötig mit „…“ gekürzt, nie abgeschnitten.
    func zeile(_ inhalt: NSAttributedString, breite: CGFloat) -> CTLine {
        let ganz = CTLineCreateWithAttributedString(inhalt)
        guard inhalt.length > 0, CGFloat(CTLineGetTypographicBounds(ganz, nil, nil, nil)) > breite else { return ganz }
        let auslassung = NSAttributedString(string: "\u{2026}",
                                            attributes: inhalt.attributes(at: inhalt.length - 1, effectiveRange: nil))
        return CTLineCreateTruncatedLine(ganz, Double(breite), .end, CTLineCreateWithAttributedString(auslassung)) ?? ganz
    }

    /// Text in Zeilen zu `breite`; die Folgezeilen um `einzug` eingerückt. Mit `hoechstens`
    /// nimmt die letzte erlaubte Zeile den Rest, gekürzt.
    func umbrechen(_ inhalt: NSAttributedString, breite: CGFloat, einzug: CGFloat = 0,
                   hoechstens: Int = .max) -> [(zeile: CTLine, x: CGFloat)] {
        guard inhalt.length > 0 else { return [] }
        let setzer = CTTypesetterCreateWithAttributedString(inhalt)
        var zeilen: [(zeile: CTLine, x: CGFloat)] = []
        var anfang = 0
        while anfang < inhalt.length {
            let x = zeilen.isEmpty ? 0 : einzug
            let platz = max(1, breite - x)
            if zeilen.count == hoechstens - 1 {
                let rest = inhalt.attributedSubstring(from: NSRange(location: anfang, length: inhalt.length - anfang))
                zeilen.append((zeile(rest, breite: platz), x))
                break
            }
            let laenge = CTTypesetterSuggestLineBreak(setzer, anfang, Double(platz))
            let genommen = laenge > 0 ? laenge : inhalt.length - anfang
            zeilen.append((CTTypesetterCreateLine(setzer, CFRange(location: anfang, length: genommen)), x))
            anfang += genommen
        }
        return zeilen
    }

    /// Die sichtbare Breite — ohne Leerraum am Ende.
    func breite(_ zeile: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(zeile, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(zeile))
    }

    /// Die Grundlinie, die eine Zeile dieser Schrift senkrecht mittig in den Streifen setzt.
    func mitte(_ oben: CGFloat, _ hoehe: CGFloat, _ schrift: CTFont) -> CGFloat {
        oben + (hoehe + CTFontGetAscent(schrift) - CTFontGetDescent(schrift)) / 2
    }

    // ── Zeichnen, von oben gezählt ────────────────────────────────────────

    func zeichnen(_ zeile: CTLine, x: CGFloat, grundlinie: CGFloat, in feld: CGContext) {
        feld.textPosition = CGPoint(x: x, y: mass.blatt.height - grundlinie)
        CTLineDraw(zeile, feld)
    }

    func rechteck(_ x: CGFloat, _ y: CGFloat, _ breite: CGFloat, _ hoehe: CGFloat) -> CGRect {
        CGRect(x: x, y: mass.blatt.height - y - hoehe, width: breite, height: hoehe)
    }

    func flaeche(_ x: CGFloat, _ y: CGFloat, _ breite: CGFloat, _ hoehe: CGFloat, grau: CGFloat, in feld: CGContext) {
        feld.setFillColor(gray: grau, alpha: 1)
        feld.fill(rechteck(x, y, breite, hoehe))
    }

    func strich(von: CGPoint, bis: CGPoint, grau: CGFloat, staerke: CGFloat, in feld: CGContext) {
        feld.setStrokeColor(gray: grau, alpha: 1)
        feld.setLineWidth(staerke)
        feld.strokeLineSegments(between: [CGPoint(x: von.x, y: mass.blatt.height - von.y),
                                          CGPoint(x: bis.x, y: mass.blatt.height - bis.y)])
    }
}
