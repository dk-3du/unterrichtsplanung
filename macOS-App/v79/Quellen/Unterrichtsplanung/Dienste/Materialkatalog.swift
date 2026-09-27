// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Die Materialliste von 3ducation.org ──────────────────────────────────
// Die Website führt ihre Kacheln in `inhalte.js` — JavaScript, kein JSON:
// `const KATEGORIEN = [ { titel, beschreibung, kacheln: [ { titel, beschreibung,
// meta, schlagworte, lizenz, link, download, qr, qrMin } ] } ];`. Die App führt
// keinen fremden Code aus (Hardened Runtime ohne JIT, `Berechtigungen.plist`).
// Darum liest sie die Datei mit einem eigenen Leser der **Literal-Teilmenge**:
// Felder, Objekte, Zeichenketten in "…" oder '…' mit Escapes, Zahlen,
// `true`/`false`/`null`, Kommentare, Nachkommas, Schlüssel nackt (nur ASCII)
// oder in Anführungszeichen, die Deklaration `const KATEGORIEN =` (auch `let`,
// `var` oder ohne) und ein `;` am Ende. Leerraum und Zeilenenden wie in
// ECMAScript: `//` endet an LF, CR, U+2028 und U+2029 (v73). Was darüber
// hinausgeht, ist ein Fehler mit Zeile und Spalte — nie geraten.
// Ob der Leser dasselbe sieht wie eine JavaScript-Maschine, beweist das
// Prüfwerk gegen `jsc` (`katalog_pruefen.py`, E183). Die Kachelzahl der
// Website steigt; nichts hier hängt an einer Zahl — die Grenzen sind Schutz.

/// Ein Wert der Literal-Teilmenge.
indirect enum Literal: Equatable, Sendable {
    struct Eintrag: Equatable, Sendable {
        let schluessel: String
        let wert: Literal
        init(_ schluessel: String, _ wert: Literal) {
            self.schluessel = schluessel
            self.wert = wert
        }
    }

    case zeichenkette(String)
    case zahl(Double)
    case wahrheit(Bool)
    case nichts
    case feld([Literal])
    /// In der Reihenfolge der Datei; bei doppeltem Schlüssel gilt der letzte —
    /// wie in JavaScript.
    case objekt([Eintrag])

    /// Der Wert zu einem Schlüssel — der letzte, wenn er mehrfach steht.
    subscript(_ schluessel: String) -> Literal? {
        guard case .objekt(let eintraege) = self else { return nil }
        return eintraege.last { $0.schluessel == schluessel }?.wert
    }

    var text: String? {
        if case .zeichenkette(let s) = self { return s }
        return nil
    }

    var liste: [Literal]? {
        if case .feld(let f) = self { return f }
        return nil
    }

    /// Als Foundation-Wert, wie `JSONSerialization` ihn liest — für den
    /// Vergleich mit dem JSON aus `jsc`.
    var alsFoundation: Any {
        switch self {
        case .zeichenkette(let s): s
        case .zahl(let z): z
        case .wahrheit(let w): w
        case .nichts: NSNull()
        case .feld(let f): f.map(\.alsFoundation)
        case .objekt(let eintraege):
            eintraege.reduce(into: [String: Any]()) { $0[$1.schluessel] = $1.wert.alsFoundation }
        }
    }
}

/// Eine Kachel der Website — mit geprüfter, absoluter Adresse.
struct Materialkachel: Identifiable, Hashable, Sendable {
    /// Fortlaufend in der Reihenfolge der Datei — Titel und Adressen dürfen
    /// sich wiederholen.
    let id: Int
    let titel: String
    let beschreibung: String
    /// „Chemie · 1. Lernjahr“
    let meta: String
    let lizenz: String
    let schlagworte: [String]
    /// Immer eine geprüfte http- oder https-Adresse (`Weblinks.pruefen`).
    let adresse: String

    /// Wie die Suche der Startseite: **jedes** Wort muss vorkommen — in Titel,
    /// Beschreibung, Meta, Lizenz oder einem Schlagwort; Groß und klein gleich.
    func passt(_ suche: String) -> Bool {
        let worte = suche.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        if worte.isEmpty { return true }
        let text = ([titel, beschreibung, meta, lizenz] + schlagworte).joined(separator: "\n").lowercased()
        return worte.allSatisfy { text.contains($0) }
    }
}

struct Materialkategorie: Identifiable, Hashable, Sendable {
    let id: Int
    let titel: String
    let beschreibung: String
    let kacheln: [Materialkachel]
}

/// Die gelesene Liste: Kategorien mit Kacheln, dazu die Zahl der Kacheln, die
/// ohne Titel oder ohne gültige Adresse übergangen wurden.
struct Materialkatalog: Hashable, Sendable {
    let kategorien: [Materialkategorie]
    let uebergangen: Int

    var kacheln: Int { kategorien.reduce(0) { $0 + $1.kacheln.count } }

    /// Die Wurzel der Website — relative Adressen der Kacheln enden darunter,
    /// wie im Browser auf der Startseite.
    static let basis = "https://3ducation.org/"
    /// Mehr als das ist keine Materialliste, die diese App deuten will (heute
    /// rund 21 KB).
    static let hoechstens = 1024 * 1024
    /// Kategorie 1, ihr Objekt 2, `kacheln` 3, Kachel 4, `schlagworte` 5 —
    /// drei Ebenen Luft.
    static let tiefeHoechstens = 8
    static let kachelnHoechstens = 2000

    enum Fehler: Error, Equatable, Sendable, CustomStringConvertible {
        case zuGross(Int)
        case keinUTF8
        /// Etwas außerhalb der Teilmenge — mit Zeile, Spalte und dem, was da stand.
        case unerwartet(zeile: Int, spalte: Int, String)
        case zuTief
        case keineListe
        case zuViele

        var description: String {
            switch self {
            case .zuGross(let bytes): "die Datei ist zu groß (\(bytes) Byte, höchstens \(Materialkatalog.hoechstens))"
            case .keinUTF8: "die Datei ist kein UTF-8"
            case .unerwartet(let zeile, let spalte, let was): "Zeile \(zeile), Spalte \(spalte): \(was)"
            case .zuTief: "tiefer als \(Materialkatalog.tiefeHoechstens) Ebenen verschachtelt"
            case .keineListe: "die Datei enthält keine Liste von Kategorien"
            case .zuViele: "mehr als \(Materialkatalog.kachelnHoechstens) Kacheln"
            }
        }
    }

    /// Der Name der Liste in der Datei — so liest die Startseite sie. Eine
    /// Datei, die sie anders nennt oder gar nicht deklariert, ist für die
    /// Website keine Liste; der Leser weist sie ab (E198, B47, v73).
    static let variable = "KATEGORIEN"

    /// Nur das Literal — für die Parität mit `jsc`. Ohne `deklaration` ein
    /// bloßer Wert (wie jsc ihn in Klammern liest) oder die Deklaration von
    /// `KATEGORIEN`; mit `deklaration` nur diese — der Weg jeder geladenen Liste.
    static func literal(_ text: String, deklaration: Bool = false) throws -> Literal {
        var leser = Literalleser(text)
        return try leser.lesen(deklarationVerlangt: deklaration)
    }

    /// Größe, UTF-8, Literal, Liste — dann der Katalog.
    static func lesen(_ daten: Data, basis: String = basis) throws -> Materialkatalog {
        guard daten.count <= hoechstens else { throw Fehler.zuGross(daten.count) }
        guard var text = String(data: daten, encoding: .utf8) else { throw Fehler.keinUTF8 }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        guard case .feld(let roheKategorien) = try literal(text, deklaration: true) else { throw Fehler.keineListe }

        var kategorien: [Materialkategorie] = []
        var uebergangen = 0
        var gezaehlt = 0
        var kachelId = 0
        for rohe in roheKategorien {
            // Ohne Kachel-Feld ist es keine Kategorie; der Titel darf fehlen.
            guard let roheKacheln = rohe["kacheln"]?.liste else { continue }
            gezaehlt += roheKacheln.count
            guard gezaehlt <= kachelnHoechstens else { throw Fehler.zuViele }
            var kacheln: [Materialkachel] = []
            for roheKachel in roheKacheln {
                let titel = zeile(roheKachel["titel"])
                guard !titel.isEmpty,
                      let adresse = adresse(roheKachel["link"]?.text ?? "", basis: basis)
                else { uebergangen += 1; continue }
                let schlagworte = (roheKachel["schlagworte"]?.liste ?? []).compactMap(\.text).map(zeile)
                kacheln.append(Materialkachel(
                    id: kachelId, titel: titel,
                    beschreibung: absatz(roheKachel["beschreibung"]),
                    meta: zeile(roheKachel["meta"]),
                    lizenz: zeile(roheKachel["lizenz"]),
                    schlagworte: schlagworte, adresse: adresse))
                kachelId += 1
            }
            kategorien.append(Materialkategorie(
                id: kategorien.count, titel: zeile(rohe["titel"]),
                beschreibung: absatz(rohe["beschreibung"]), kacheln: kacheln))
        }
        return Materialkatalog(kategorien: kategorien, uebergangen: uebergangen)
    }

    /// Ein Anzeigefeld der Liste: ohne Steuerzeichen und in einer Zeile — wie
    /// der Dateileser eine Bezeichnung liest. Der Titel wird die Bezeichnung
    /// eines Links; was hier bliebe, müsste der Leser beim nächsten Start
    /// bereinigen und melden.
    static func zeile(_ feld: Literal?) -> String { zeile(feld?.text ?? "") }

    static func zeile(_ text: String) -> String {
        Planungsdatei.einzeilig(Planungsdatei.ohneSteuerzeichen(text))
    }

    /// Eine Beschreibung darf Zeilen haben — nur die Steuerzeichen gehen.
    static func absatz(_ feld: Literal?) -> String {
        Planungsdatei.ohneSteuerzeichen(feld?.text ?? "")
    }

    /// Das Feld `link` einer Kachel als geprüfte Adresse: mit Schema wie es
    /// ist (`Weblinks.pruefen` lässt nur http und https durch), ohne Schema
    /// nach den Regeln für Adressen gegen die Wurzel der Website aufgelöst —
    /// wie der Browser es von der Startseite aus tut: `a/../b.html` wird
    /// `/b.html`, `//rechner/pfad` behält seinen Rechner und bekommt das
    /// Schema der Website. Leer, `javascript:`, `mailto:`, ein
    /// Gegenschrägstrich, kein Rechner: `nil`, die Kachel wird übergangen.
    static func adresse(_ link: String, basis: String = basis) -> String? {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if hatSchema(text) { return Weblinks.pruefen(text) }
        // Ein Gegenschrägstrich ist im Browser ein Schrägstrich, hier ein Zeichen
        // im Pfad — also weder noch: übergangen.
        guard !text.contains("\\"),
              let wurzel = URL(string: basis),
              let ziel = URL(string: text, relativeTo: wurzel)?.absoluteURL,
              let rechner = ziel.host(), !rechner.isEmpty
        else { return nil }
        return Weblinks.pruefen(ziel.absoluteString)
    }

    /// `^[A-Za-z][A-Za-z0-9+.-]*:` — dieselbe Regel wie `Weblinks`.
    private static func hatSchema(_ text: String) -> Bool {
        var erstes = true
        for zeichen in text {
            if erstes {
                guard zeichen.isASCII, zeichen.isLetter else { return false }
                erstes = false
            } else if zeichen == ":" {
                return true
            } else {
                guard zeichen.isASCII,
                      zeichen.isLetter || zeichen.isNumber || zeichen == "+" || zeichen == "." || zeichen == "-"
                else { return false }
            }
        }
        return false
    }

    /// Nur die Kategorien mit passenden Kacheln, in der Reihenfolge der Datei.
    func passend(_ suche: String) -> [Materialkategorie] {
        kategorien.compactMap { kategorie in
            let treffer = kategorie.kacheln.filter { $0.passt(suche) }
            guard !treffer.isEmpty else { return nil }
            return Materialkategorie(id: kategorie.id, titel: kategorie.titel,
                                     beschreibung: kategorie.beschreibung, kacheln: treffer)
        }
    }
}

// ── Der Leser ─────────────────────────────────────────────────────────────

/// Ein Durchgang über die Unicode-Skalare, ohne Rückweg. Jeder Fehler nennt
/// Zeile und Spalte der Stelle, an der er auffiel.
private struct Literalleser {
    private let zeichen: [Unicode.Scalar]
    private var stelle = 0

    init(_ text: String) {
        zeichen = Array(text.unicodeScalars)
    }

    private var aktuell: Unicode.Scalar? { stelle < zeichen.count ? zeichen[stelle] : nil }

    private func naechstes(_ abstand: Int = 1) -> Unicode.Scalar? {
        stelle + abstand < zeichen.count ? zeichen[stelle + abstand] : nil
    }

    /// Zeilen zählen wie in JavaScript: LF, CR, U+2028 und U+2029 beenden eine
    /// Zeile, CRLF zählt als eine. Die Spalte zählt Unicode-Skalare.
    private func fehler(_ was: String, bei: Int? = nil) -> Materialkatalog.Fehler {
        let ort = min(bei ?? stelle, zeichen.count)
        var zeile = 1
        var zeilenanfang = 0
        var i = 0
        while i < ort {
            if Literalleser.zeilenende(zeichen[i]) {
                if zeichen[i] == "\r", i + 1 < ort, zeichen[i + 1] == "\n" { i += 1 }
                zeile += 1
                zeilenanfang = i + 1
            }
            i += 1
        }
        return .unerwartet(zeile: zeile, spalte: ort - zeilenanfang + 1, was)
    }

    private func beschreibung(_ s: Unicode.Scalar?) -> String {
        guard let s else { return "das Ende der Datei" }
        return "„\(Character(s))“"
    }

    // ── Aufbau ────────────────────────────────────────────────────────────

    /// `[const|let|var] KATEGORIEN = <Wert> [;]` und sonst nichts — ohne
    /// `deklarationVerlangt` darf es auch der bloße Wert sein. Ein anderer Name
    /// wird abgewiesen: Die Startseite liest `KATEGORIEN`, und jeder andere
    /// wäre für sie keine Liste oder, wie `if`, gar kein Skript (B47, v73).
    mutating func lesen(deklarationVerlangt: Bool) throws -> Literal {
        try beiwerkUeberspringen()
        let anfang = stelle
        if let name = bezeichner(), !["true", "false", "null"].contains(name) {
            stelle += name.unicodeScalars.count
            try beiwerkUeberspringen()
            var variable = name
            var namensstelle = anfang
            if ["const", "let", "var"].contains(name) {
                namensstelle = stelle
                guard let deklariert = bezeichner() else { throw fehler("nach „\(name)“ fehlt der Name") }
                variable = deklariert
                stelle += deklariert.unicodeScalars.count
                try beiwerkUeberspringen()
            }
            guard variable == Materialkatalog.variable else {
                throw fehler("die Liste heißt „\(Materialkatalog.variable)“ — so liest sie die Startseite, "
                             + "nicht „\(variable)“", bei: namensstelle)
            }
            guard aktuell == "=" else { throw fehler("nach „\(variable)“ wird „=“ erwartet, nicht \(beschreibung(aktuell))") }
            stelle += 1
            try beiwerkUeberspringen()
        } else if deklarationVerlangt {
            throw fehler("die Datei deklariert keine Liste „\(Materialkatalog.variable)“ — so liest sie die Startseite",
                         bei: anfang)
        }
        let wert = try wertLesen(tiefe: 0)
        try beiwerkUeberspringen()
        if aktuell == ";" {
            stelle += 1
            try beiwerkUeberspringen()
        }
        guard aktuell == nil else { throw fehler("nach der Liste steht noch etwas: \(beschreibung(aktuell))") }
        return wert
    }

    private mutating func wertLesen(tiefe: Int) throws -> Literal {
        guard let z = aktuell else { throw fehler("ein Wert fehlt — das Ende der Datei") }
        switch z {
        case "[":
            guard tiefe < Materialkatalog.tiefeHoechstens else { throw Materialkatalog.Fehler.zuTief }
            return try feldLesen(tiefe: tiefe + 1)
        case "{":
            guard tiefe < Materialkatalog.tiefeHoechstens else { throw Materialkatalog.Fehler.zuTief }
            return try objektLesen(tiefe: tiefe + 1)
        case "\"", "'":
            return .zeichenkette(try zeichenketteLesen())
        case "-", ".", "0"..."9":
            return try zahlLesen()
        default:
            if let name = bezeichner() {
                switch name {
                case "true": stelle += 4; return .wahrheit(true)
                case "false": stelle += 5; return .wahrheit(false)
                case "null": stelle += 4; return .nichts
                default: throw fehler("„\(name)“ ist kein Wert der Teilmenge")
                }
            }
            throw fehler("unerwartetes Zeichen \(beschreibung(z))")
        }
    }

    private mutating func feldLesen(tiefe: Int) throws -> Literal {
        let anfang = stelle
        stelle += 1
        var werte: [Literal] = []
        while true {
            try beiwerkUeberspringen()
            guard let z = aktuell else { throw fehler("das Feld ist nicht geschlossen", bei: anfang) }
            if z == "]" { stelle += 1; return .feld(werte) }
            werte.append(try wertLesen(tiefe: tiefe))
            try beiwerkUeberspringen()
            switch aktuell {
            case ",": stelle += 1
            case "]": continue
            default: throw fehler("im Feld wird „,“ oder „]“ erwartet, nicht \(beschreibung(aktuell))")
            }
        }
    }

    private mutating func objektLesen(tiefe: Int) throws -> Literal {
        let anfang = stelle
        stelle += 1
        var eintraege: [Literal.Eintrag] = []
        while true {
            try beiwerkUeberspringen()
            guard let z = aktuell else { throw fehler("das Objekt ist nicht geschlossen", bei: anfang) }
            if z == "}" { stelle += 1; return .objekt(eintraege) }
            let schluesselanfang = stelle
            let schluessel: String
            if z == "\"" || z == "'" {
                schluessel = try zeichenketteLesen()
            } else if let name = bezeichner() {
                schluessel = name
                stelle += name.unicodeScalars.count
            } else {
                throw fehler("ein Schlüssel wird erwartet, nicht \(beschreibung(z))")
            }
            // JavaScript setzt damit den Prototyp, statt ein Feld anzulegen.
            guard schluessel != "__proto__" else {
                throw fehler("den Schlüssel „__proto__“ liest JavaScript nicht als Feld", bei: schluesselanfang)
            }
            try beiwerkUeberspringen()
            guard aktuell == ":" else { throw fehler("nach „\(schluessel)“ wird „:“ erwartet, nicht \(beschreibung(aktuell))") }
            stelle += 1
            try beiwerkUeberspringen()
            eintraege.append(.init(schluessel, try wertLesen(tiefe: tiefe)))
            try beiwerkUeberspringen()
            switch aktuell {
            case ",": stelle += 1
            case "}": continue
            default: throw fehler("im Objekt wird „,“ oder „}“ erwartet, nicht \(beschreibung(aktuell))")
            }
        }
    }

    // ── Zeichenketten, Zahlen, Bezeichner, Beiwerk ────────────────────────

    /// `"…"` oder `'…'` mit den Escapes von JavaScript; ein Zeilenumbruch in
    /// der Zeichenkette ist ein Fehler, `\` vor dem Umbruch eine Fortsetzung.
    ///
    /// **Annehmen heißt dasselbe lesen.** Was JavaScript anders läse, wird
    /// abgewiesen statt umgedeutet: die Oktal-Escapes (`\1`–`\7`, `\0` vor
    /// einer Ziffer; `\8`, `\9` gleich mit) und ein einzelnes Ersatzzeichen,
    /// das eine Swift-Zeichenkette nicht tragen kann.
    private mutating func zeichenketteLesen() throws -> String {
        let anfang = stelle
        let ende = zeichen[stelle]
        stelle += 1
        var skalare = String.UnicodeScalarView()
        while true {
            guard let z = aktuell else { throw fehler("die Zeichenkette ist nicht geschlossen", bei: anfang) }
            stelle += 1
            if z == ende { return String(skalare) }
            if z == "\n" || z == "\r" { throw fehler("Zeilenumbruch in der Zeichenkette", bei: stelle - 1) }
            guard z == "\\" else { skalare.append(z); continue }
            guard let e = aktuell else { throw fehler("die Zeichenkette ist nicht geschlossen", bei: anfang) }
            stelle += 1
            switch e {
            case "n": skalare.append("\n")
            case "t": skalare.append("\t")
            case "r": skalare.append("\r")
            case "b": skalare.append("\u{8}")
            case "f": skalare.append("\u{C}")
            case "v": skalare.append("\u{B}")
            case "0":
                if let z = aktuell, ("0"..."9").contains(z) {
                    throw fehler("ein Oktal-Escape — JavaScript läse es anders", bei: stelle - 2)
                }
                skalare.append("\u{0}")
            case "1"..."9":
                throw fehler("ein Oktal-Escape — JavaScript läse es anders", bei: stelle - 2)
            case "\n", "\u{2028}", "\u{2029}": break            // Fortsetzung
            case "\r": if aktuell == "\n" { stelle += 1 }      // Fortsetzung, Windows
            case "x": skalare.append(try hexSkalar(stellen: 2))
            case "u":
                let escapeanfang = stelle - 2
                if aktuell == "{" {
                    stelle += 1
                    skalare.append(try codepunktLesen(anfang: escapeanfang))
                    continue
                }
                let erstes = try hexWert(stellen: 4)
                if (0xD800...0xDBFF).contains(erstes), aktuell == "\\", naechstes() == "u" {
                    stelle += 2
                    let zweites = try hexWert(stellen: 4)
                    if (0xDC00...0xDFFF).contains(zweites),
                       let paar = Unicode.Scalar(0x10000 + ((erstes - 0xD800) << 10) + (zweites - 0xDC00)) {
                        skalare.append(paar)
                        continue
                    }
                }
                guard let skalar = Unicode.Scalar(erstes) else {
                    throw fehler("ein einzelnes Ersatzzeichen", bei: escapeanfang)
                }
                skalare.append(skalar)
            default: skalare.append(e)                         // \" \' \\ \/ und alles Unbekannte
            }
        }
    }

    /// `\u{…}` nach der Klammer: Hexziffern (führende Nullen beliebig),
    /// höchstens U+10FFFF, kein Ersatzzeichen.
    private mutating func codepunktLesen(anfang: Int) throws -> Unicode.Scalar {
        var wert: UInt32 = 0
        var ziffern = 0
        while let z = aktuell, let ziffer = Literalleser.hexziffer(z) {
            wert = wert * 16 + ziffer
            ziffern += 1
            stelle += 1
            guard wert <= 0x10FFFF else { throw fehler("der Codepunkt ist zu groß", bei: anfang) }
        }
        guard ziffern > 0, aktuell == "}" else {
            throw fehler("im Codepunkt werden Hexziffern und „}“ erwartet, nicht \(beschreibung(aktuell))")
        }
        stelle += 1
        guard let skalar = Unicode.Scalar(wert) else { throw fehler("ein einzelnes Ersatzzeichen", bei: anfang) }
        return skalar
    }

    /// Nur die ASCII-Hexziffern — `Character.hexDigitValue` nähme auch die
    /// Formen in voller Breite (U+FF10 …), die JavaScript nicht kennt.
    private static func hexziffer(_ z: Unicode.Scalar) -> UInt32? {
        switch z {
        case "0"..."9": z.value - 48
        case "a"..."f": z.value - 87
        case "A"..."F": z.value - 55
        default: nil
        }
    }

    private mutating func hexWert(stellen: Int) throws -> UInt32 {
        var wert: UInt32 = 0
        for _ in 0..<stellen {
            guard let z = aktuell, let ziffer = Literalleser.hexziffer(z) else {
                throw fehler("eine Hexziffer wird erwartet, nicht \(beschreibung(aktuell))")
            }
            wert = wert * 16 + ziffer
            stelle += 1
        }
        return wert
    }

    private mutating func hexSkalar(stellen: Int) throws -> Unicode.Scalar {
        Unicode.Scalar(try hexWert(stellen: stellen)) ?? "\u{FFFD}"
    }

    /// `-? Ziffern? (. Ziffern?)? ([eE] [+-]? Ziffern)?` — keine Hexzahlen,
    /// kein Unendlich, keine führende Null vor einer Ziffer: `010` ist in
    /// JavaScript acht.
    private mutating func zahlLesen() throws -> Literal {
        let anfang = stelle
        var text = ""
        func ziffern() -> Int {
            var n = 0
            while let z = aktuell, ("0"..."9").contains(z) { text.unicodeScalars.append(z); stelle += 1; n += 1 }
            return n
        }
        if aktuell == "-" { text = "-"; stelle += 1 }
        let vor = ziffern()
        if vor > 1, text.drop(while: { $0 == "-" }).hasPrefix("0") {
            throw fehler("eine Zahl mit führender Null — JavaScript läse sie anders", bei: anfang)
        }
        var nach = 0
        if aktuell == "." {
            text += "."
            stelle += 1
            nach = ziffern()
        }
        guard vor + nach > 0 else { throw fehler("eine Zahl wird erwartet", bei: anfang) }
        if let e = aktuell, e == "e" || e == "E" {
            text += "e"
            stelle += 1
            if let v = aktuell, v == "+" || v == "-" { text.unicodeScalars.append(v); stelle += 1 }
            guard ziffern() > 0 else { throw fehler("dem Exponenten fehlen die Ziffern", bei: anfang) }
        }
        // `1.` und `.5` kennt Double nicht: ergänzen.
        if text.hasSuffix(".") { text += "0" }
        if text.hasPrefix(".") { text = "0" + text }
        if text.hasPrefix("-.") { text = "-0" + text.dropFirst() }
        guard let zahl = Double(text), zahl.isFinite else { throw fehler("„\(text)“ ist keine Zahl", bei: anfang) }
        return .zahl(zahl)
    }

    /// Der Bezeichner an der Stelle — ohne ihn zu verbrauchen. Nur ASCII:
    /// Buchstaben, Ziffern, `_` und `$`. Was JavaScript darüber hinaus als Namen
    /// liest und was nicht, hängt an den Unicode-Tabellen der Maschine
    /// (`isAlphabetic` ist nicht ID_Start: `ⓐ` nahm der Leser an, JavaScript
    /// nicht) — ein anderes Zeichen beendet den Namen, und die Stelle wird
    /// abgewiesen (B47, v73).
    private func bezeichner() -> String? {
        guard let erstes = aktuell, Literalleser.namensanfang(erstes) else { return nil }
        var name = String.UnicodeScalarView()
        var i = stelle
        while i < zeichen.count {
            let z = zeichen[i]
            guard Literalleser.namensanfang(z) || ("0"..."9").contains(z) else { break }
            name.append(z)
            i += 1
        }
        return String(name)
    }

    private static func namensanfang(_ z: Unicode.Scalar) -> Bool {
        switch z {
        case "a"..."z", "A"..."Z", "_", "$": true
        default: false
        }
    }

    /// Die Zeilenenden von ECMAScript: LF, CR, U+2028, U+2029.
    static func zeilenende(_ z: Unicode.Scalar) -> Bool {
        z == "\n" || z == "\r" || z == "\u{2028}" || z == "\u{2029}"
    }

    /// Der Leerraum von ECMAScript: Tabulator, VT, FF, U+FEFF, jedes Zeichen der
    /// Kategorie Zs (Leerzeichen, NBSP, U+1680, U+2000–U+200A, U+202F, U+205F,
    /// U+3000) und die Zeilenenden — nicht NEL (U+0085), den Swift mitzählt.
    static func leerraum(_ z: Unicode.Scalar) -> Bool {
        switch z {
        case "\t", "\u{B}", "\u{C}", "\u{FEFF}": true
        default: zeilenende(z) || z.properties.generalCategory == .spaceSeparator
        }
    }

    /// Leerraum und Kommentare, beide Arten — wie ECMAScript sie abgrenzt: `//`
    /// endet an jedem Zeilenende, nicht nur an LF (R72-02, v73).
    private mutating func beiwerkUeberspringen() throws {
        while let z = aktuell {
            if Literalleser.leerraum(z) {
                stelle += 1
            } else if z == "/", naechstes() == "/" {
                while let w = aktuell, !Literalleser.zeilenende(w) { stelle += 1 }
            } else if z == "/", naechstes() == "*" {
                let anfang = stelle
                stelle += 2
                while true {
                    guard aktuell != nil else { throw fehler("der Kommentar ist nicht geschlossen", bei: anfang) }
                    if aktuell == "*", naechstes() == "/" { stelle += 2; break }
                    stelle += 1
                }
            } else {
                return
            }
        }
    }
}

// ── Der Lader ─────────────────────────────────────────────────────────────

/// Was das Laden ergab.
enum Materialbefund: Equatable, Sendable {
    case geladen(Materialkatalog)
    /// Keine Verbindung, Zeitüberschreitung, eine andere Antwort als 200.
    case nichtErreichbar
    /// Eine Antwort, die der Leser nicht versteht — mit dem Grund in Worten.
    case unlesbar(String)
    /// Die Frage ist unbeantwortet oder mit Nein beantwortet: keine Anfrage.
    case keineErlaubnis
}

/// Holt die `inhalte.js` — von der Website oder, für Prüfstand und Abbild, aus
/// einer Datei — und liest sie. Ohne Zustand: nichts wird gemerkt, kein ETag,
/// keine Antwort; die Liste wird bei jedem Öffnen frisch geladen (E178).
struct Materiallader: Sendable {
    static let schnittstelle = URL(string: "https://3ducation.org/inhalte.js")!
    static let zeitueberschreitung: TimeInterval = 10

    let quelle: URL
    /// `CFBundleVersion` der laufenden App — steht im User-Agent, wie beim Update.
    let installiert: Int
    /// Dieselbe flüchtige Sitzung wie die Prüfung auf Updates: keine Cookies,
    /// kein Zwischenspeicher.
    var sitzung: URLSession = Updatepruefer.standardSitzung
    /// Wie lange die Anfrage auf Daten wartet. Im Betrieb die 10 s oben; die
    /// Prüfungen, die eine Anfrage festhalten, setzen mehr (B66, v76).
    var zeitgrenze: TimeInterval = Materiallader.zeitueberschreitung

    /// Woher die Liste kommt: `MATERIAL_QUELLE` — nur eine Datei (`file:`-URL
    /// oder absoluter Pfad), für Prüfstand und Abbild —, sonst die Website. Im
    /// Prüfstand ohne Datei: gar nicht; kein Prüflauf geht ins Netz.
    static func quelle(umgebung: [String: String], pruefstand: Bool) -> URL? {
        if let wert = umgebung["MATERIAL_QUELLE"], !wert.isEmpty {
            if let url = URL(string: wert), url.isFileURL { return url }
            if wert.hasPrefix("/") { return URL(fileURLWithPath: wert) }
        }
        return pruefstand ? nil : schnittstelle
    }

    /// Was die Anfrage trägt — und damit alles, was übertragen wird: die
    /// Fassung der App im User-Agent. Sonst nichts.
    var anfrage: URLRequest {
        var anfrage = URLRequest(url: quelle)
        anfrage.setValue("text/javascript, application/javascript;q=0.9, */*;q=0.1", forHTTPHeaderField: "Accept")
        anfrage.setValue("Unterrichtsplanung/\(installiert)", forHTTPHeaderField: "User-Agent")
        anfrage.setValue("de", forHTTPHeaderField: "Accept-Language")
        anfrage.cachePolicy = .reloadIgnoringLocalCacheData
        anfrage.timeoutInterval = zeitgrenze
        return anfrage
    }

    /// Wirft nie — jeder Fehler ist ein Befund. Gebunden gelesen wie beim
    /// Update: an `Content-Length`, wo vorhanden, und an der Bytezahl.
    func laden() async -> Materialbefund {
        var daten = Data()
        let antwort: URLResponse
        do {
            // Weiterleitungen nur zum selben Rechner über https (`Weiterleitung`).
            let (bytes, empfangen) = try await sitzung.bytes(for: anfrage, delegate: Weiterleitung.waechter)
            antwort = empfangen
            let grenze = Materialkatalog.hoechstens
            guard antwort.expectedContentLength <= Int64(grenze) else {
                return .unlesbar(Materialkatalog.Fehler.zuGross(Int(antwort.expectedContentLength)).description)
            }
            for try await byte in bytes {
                daten.append(byte)
                guard daten.count <= grenze else {
                    return .unlesbar(Materialkatalog.Fehler.zuGross(daten.count).description)
                }
            }
        } catch {
            return .nichtErreichbar
        }
        if let http = antwort as? HTTPURLResponse, http.statusCode != 200 {
            return .nichtErreichbar
        }
        do {
            return .geladen(try Materialkatalog.lesen(daten))
        } catch let fehler as Materialkatalog.Fehler {
            return .unlesbar(fehler.description)
        } catch {
            return .unlesbar(error.localizedDescription)
        }
    }
}

/// Was die Oberfläche über die Materialliste sagt — die Wortlaute des Nutzers
/// (17.09.2026), wörtlich in Frage, Nachfrage, Blatt und Einstellungen.
enum Materialien {
    static let titel = "Materialien von 3ducation.org"
    static let einstellungsort = "Einstellungen → Materialien von 3ducation.org"

    /// Worum es geht.
    static let worumEsGeht =
        "Im Vorhaben-Dialog kann die App die Materialliste der Website 3ducation.org anbieten — "
        + "die Lernumgebungen, Frage-, Reflexions- und Auswertungsbögen sowie Tools. Ein Klick "
        + "fügt einem Vorhaben das gewählte Material als Link direkt hinzu."

    /// Was dabei übertragen wird — der Grund, warum es eine Erlaubnis braucht.
    static let datenschutzhinweis =
        "Beim Öffnen des Blatts lädt die App die Materialliste von 3ducation.org. Übertragen "
        + "werden dabei die IP-Adresse dieses Rechners und die Versionsnummer der App — sonst "
        + "nichts: keine Planungsdaten, keine Gerätekennung, keine Cookies. Gespeichert wird "
        + "nichts; die Liste wird bei jedem Öffnen neu geladen. Ausgeschaltet geht dafür nichts "
        + "ins Netz."
}
