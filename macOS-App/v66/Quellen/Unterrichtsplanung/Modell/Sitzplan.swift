// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

// `CoreGraphics` ausdrücklich: `abzug_pruefen.py` übersetzt das Modell allein
// mit `swiftc`, und `CGRect.maxY` kommt nicht über Foundation herein.
import CoreGraphics
import Foundation

/// Die Maße der Sitzplanfläche — in Punkten, 1:1 auf dem Blatt (A4 quer).
/// Alles liegt auf dem unsichtbaren 8-Punkt-Raster, an dem die Tische beim
/// Ziehen einrasten; die Tafel steht **unten** (E25): Wer den Plan liest,
/// steht vorn und blickt in die Klasse. Eine Reihe fasst **zehn Plätze**, die
/// Anfangsanordnung belegt die mittleren acht — so lassen sich bis zu zwei
/// Gänge aussparen, ohne das Raster zu verlassen (Nachtrag 12.09.2026).
enum Sitzplanmasse {
    static let breite: CGFloat = 760
    static let hoehe: CGFloat = 456
    static let tischbreite: CGFloat = 64
    static let tischhoehe: CGFloat = 48
    static let lehrertischbreite: CGFloat = 96
    static let lehrertischhoehe: CGFloat = 48
    /// Die feste Leiste unten, mittig — halb so breit wie die Reihen
    /// (Nachtrag des Nutzers, 12.09.2026).
    static let tafel = CGRect(x: 266, y: 416, width: 228, height: 24)
    static let fangraster: CGFloat = 8
    /// Wo Tische stehen dürfen: über der Tafel und dem Lehrertisch, mit Abstand.
    static let tischbereich = CGRect(x: 0, y: 0, width: 760, height: 384)
    /// Der Lehrertisch darf bis an die Unterkante — vorn seitlich neben der Tafel.
    static let lehrertischbereich = CGRect(x: 0, y: 0, width: 760, height: 440)
    static let lehrertischStart = CGPoint(x: 24, y: 392)
    /// Plätze je Reihe auf dem Raster — und wie viele die Anfangsanordnung
    /// (E24) davon belegt: die mittleren acht, je ein Platz am Rand frei.
    static let plaetzeJeReihe = 10
    static let spalten = 8
    static let rand: CGFloat = 24
    static let spaltenschritt: CGFloat = 72
    /// Der erste Platz der Anfangsanordnung: ein Platz vom Rand frei.
    static let reihenanfang: CGFloat = rand + spaltenschritt
    static let reihenschritt: CGFloat = 72
    /// Oberkante der Reihe, die der Tafel am nächsten steht.
    static let ersteReihe: CGFloat = 336
    static let reihenHoechstens = 5

    /// Die Plätze einer Reihe in der Reihenfolge, in der eine freie Stelle
    /// gesucht wird: erst die acht der Anfangsanordnung, dann die beiden am
    /// Rand — die bleiben für die Gänge frei, solange es geht.
    static let platzfolge: [Int] = Array(1...8) + [0, 9]

    static func platz(_ stelle: Int) -> CGFloat { rand + CGFloat(stelle) * spaltenschritt }
}

/// Ein Tisch mit einem Namen — die Lage ist die linke obere Ecke in
/// Flächeneinheiten. Paare und Gruppen entstehen durch die Lage, nicht durch
/// ein Tischmodell.
struct Tisch: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var x: CGFloat
    var y: CGFloat

    var rahmen: CGRect {
        CGRect(x: x, y: y, width: Sitzplanmasse.tischbreite, height: Sitzplanmasse.tischhoehe)
    }
}

/// Der Sitzplan einer Klasse bzw. eines Kurses — genau einer je Kennung (E28).
struct Sitzplan: Hashable, Sendable {
    /// Der Lehrertisch in Auswahl und Verschiebung — kein Tisch, aber ein Element.
    static let lehrertischKennung = "lehrertisch"

    var klasseId: String
    var tische: [Tisch]
    /// `nil` heißt entfernt.
    var lehrertisch: CGPoint?
    var geaendert: String

    func tisch(_ id: String) -> Tisch? { tische.first { $0.id == id } }

    var lehrertischRahmen: CGRect? {
        lehrertisch.map {
            CGRect(x: $0.x, y: $0.y, width: Sitzplanmasse.lehrertischbreite,
                   height: Sitzplanmasse.lehrertischhoehe)
        }
    }

    /// Alle Elemente in Reihenfolge: die Tische, dann der Lehrertisch.
    var elementKennungen: [String] {
        tische.map(\.id) + (lehrertisch == nil ? [] : [Sitzplan.lehrertischKennung])
    }

    // ── Die Namensliste ───────────────────────────────────────────────────

    struct Zeilenfehler: Identifiable, Hashable, Sendable {
        var id: Int { nummer }
        let nummer: Int
        let zeile: String
        let grund: String
    }

    struct Namensliste: Sendable {
        var namen: [String] = []
        var fehler: [Zeilenfehler] = []
    }

    /// Eine Zeile je Name, wie bei der Anlage der Klassen (`Kurszeilen`), ohne
    /// Fach-Teil: leere Zeilen übergangen, Windows-Zeilenenden erlaubt,
    /// Doppelte erlaubt (zwei „Max“). Die 36. Zeile und ein Name über der
    /// Grenze werden benannt, nicht still gekürzt.
    static func namenLesen(_ text: String) -> Namensliste {
        var liste = Namensliste()
        // Jeder Zeilenwechsel trennt — `\r`, `\r\n`, U+2028 wie `\n` (B01); leere
        // Zeilen bleiben gezählt, damit die Zeilennummer der Fehlerliste stimmt.
        for (stelle, roh) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let zeile = Planungsdatei.ohneSteuerzeichen(String(roh))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if zeile.isEmpty { continue }
            if zeile.count > Kennwerte.maxSitzplatzname {
                liste.fehler.append(Zeilenfehler(
                    nummer: stelle + 1, zeile: String(zeile.prefix(40)) + "…",
                    grund: "Der Name ist länger als \(Kennwerte.maxSitzplatzname) Zeichen."))
                continue
            }
            if liste.namen.count >= Kennwerte.maxSitzplaetze {
                liste.fehler.append(Zeilenfehler(
                    nummer: stelle + 1, zeile: zeile,
                    grund: "Über der Grenze von \(Kennwerte.maxSitzplaetze) Plätzen."))
                continue
            }
            liste.namen.append(zeile)
        }
        return liste
    }

    /// Die Namen, wie sie ins Textfeld zurückgehen — eine Zeile je Tisch.
    var namenstext: String { tische.map(\.name).joined(separator: "\n") }

    // ── Die Anfangsanordnung ──────────────────────────────────────────────

    /// Deterministisch aus der Namensliste (E24): Einzeltische in Reihen zu
    /// acht auf den mittleren Plätzen des Zehnerrasters, die erste Reihe an
    /// der Tafel, jede weitere dahinter; ab dem 33. Namen eine fünfte Reihe.
    /// Der Lehrertisch steht vorn links neben der Tafel. Reine Funktion,
    /// prüfbar ohne Fenster.
    static func anordnen(klasseId: String, namen: [String]) -> Sitzplan {
        var tische: [Tisch] = []
        var vergeben = Set<String>()
        for (stelle, name) in namen.prefix(Kennwerte.maxSitzplaetze).enumerated() {
            let reihe = stelle / Sitzplanmasse.spalten
            let spalte = stelle % Sitzplanmasse.spalten
            var id = Kennung.neu("t")
            while vergeben.contains(id) { id = Kennung.neu("t") }
            vergeben.insert(id)
            tische.append(Tisch(
                id: id, name: name,
                x: Sitzplanmasse.reihenanfang + CGFloat(spalte) * Sitzplanmasse.spaltenschritt,
                y: Sitzplanmasse.ersteReihe - CGFloat(reihe) * Sitzplanmasse.reihenschritt))
        }
        return Sitzplan(klasseId: klasseId, tische: tische,
                        lehrertisch: Sitzplanmasse.lehrertischStart,
                        geaendert: Zeitrechnung.jetztAlsZeitstempel())
    }

    // ── Bewegen ───────────────────────────────────────────────────────────

    private static func eingerastet(_ wert: CGFloat) -> CGFloat {
        (wert / Sitzplanmasse.fangraster).rounded() * Sitzplanmasse.fangraster
    }

    private static func bereich(fuer id: String) -> CGRect {
        id == lehrertischKennung ? Sitzplanmasse.lehrertischbereich : Sitzplanmasse.tischbereich
    }

    private static func groesse(fuer id: String) -> CGSize {
        id == lehrertischKennung
            ? CGSize(width: Sitzplanmasse.lehrertischbreite, height: Sitzplanmasse.lehrertischhoehe)
            : CGSize(width: Sitzplanmasse.tischbreite, height: Sitzplanmasse.tischhoehe)
    }

    private func lage(_ id: String) -> CGPoint? {
        if id == Sitzplan.lehrertischKennung { return lehrertisch }
        return tisch(id).map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// Die genannten Elemente um `delta` verschieben — gemeinsam, die
    /// Abstände bleiben. Mit `fangen` rastet der Anker (das Element unter dem
    /// Zeiger) auf dem 8-Punkt-Raster ein und nimmt die anderen um denselben
    /// Weg mit; ohne (⌥) zählt der Punkt. Niemand verlässt die Fläche: Der
    /// Weg wird so weit gekürzt, dass auch der äußerste im Bereich bleibt.
    /// Lagen sind ganze Punkte.
    func verschoben(_ ids: Set<String>, um delta: CGPoint, anker: String? = nil,
                    fangen: Bool = true) -> Sitzplan {
        let bewegte = elementKennungen.filter { ids.contains($0) }
        guard !bewegte.isEmpty else { return self }

        var weg = delta
        if fangen, let ankerId = anker ?? bewegte.first, let start = lage(ankerId) {
            weg = CGPoint(x: Sitzplan.eingerastet(start.x + delta.x) - start.x,
                          y: Sitzplan.eingerastet(start.y + delta.y) - start.y)
        }
        var mindestensX = -CGFloat.greatestFiniteMagnitude
        var hoechstensX = CGFloat.greatestFiniteMagnitude
        var mindestensY = -CGFloat.greatestFiniteMagnitude
        var hoechstensY = CGFloat.greatestFiniteMagnitude
        for id in bewegte {
            guard let start = lage(id) else { continue }
            let bereich = Sitzplan.bereich(fuer: id)
            let groesse = Sitzplan.groesse(fuer: id)
            mindestensX = max(mindestensX, bereich.minX - start.x)
            hoechstensX = min(hoechstensX, bereich.maxX - groesse.width - start.x)
            mindestensY = max(mindestensY, bereich.minY - start.y)
            hoechstensY = min(hoechstensY, bereich.maxY - groesse.height - start.y)
        }
        weg.x = min(max(weg.x, mindestensX), hoechstensX).rounded()
        weg.y = min(max(weg.y, mindestensY), hoechstensY).rounded()
        guard weg != .zero else { return self }

        var neu = self
        for stelle in neu.tische.indices where ids.contains(neu.tische[stelle].id) {
            neu.tische[stelle].x += weg.x
            neu.tische[stelle].y += weg.y
        }
        if ids.contains(Sitzplan.lehrertischKennung), let alt = lehrertisch {
            neu.lehrertisch = CGPoint(x: alt.x + weg.x, y: alt.y + weg.y)
        }
        return neu
    }

    /// Was ein Rechteck trifft — die Bereichsauswahl mit der rechten Maustaste.
    func imBereich(_ rechteck: CGRect) -> Set<String> {
        var treffer = Set(tische.filter { $0.rahmen.intersects(rechteck) }.map(\.id))
        if let rahmen = lehrertischRahmen, rahmen.intersects(rechteck) {
            treffer.insert(Sitzplan.lehrertischKennung)
        }
        return treffer
    }

    /// Das Element unter einem Punkt — in umgekehrter Zeichenreihenfolge: die
    /// Tische liegen über dem Lehrertisch, der zuletzt gezeichnete Tisch zuoberst (B07).
    func element(bei punkt: CGPoint) -> String? {
        if let tisch = tische.last(where: { $0.rahmen.contains(punkt) }) { return tisch.id }
        if let rahmen = lehrertischRahmen, rahmen.contains(punkt) { return Sitzplan.lehrertischKennung }
        return nil
    }

    // ── Ändern ────────────────────────────────────────────────────────────

    /// Ein Name, wie er an den Tisch darf: ohne Steuerzeichen, gestutzt, in
    /// der Grenze; leer heißt: bleibt, wie er war.
    static func bereinigterName(_ roh: String) -> String? {
        // Ein eingesetzter Absatz wird eine Zeile — wie die Hausaufgabe (B01).
        let sauber = Planungsdatei.einzeilig(Planungsdatei.ohneSteuerzeichen(roh))
        guard !sauber.isEmpty else { return nil }
        return String(sauber.prefix(Kennwerte.maxSitzplatzname))
    }

    func umbenannt(_ id: String, name roh: String) -> Sitzplan {
        guard let name = Sitzplan.bereinigterName(roh),
              let stelle = tische.firstIndex(where: { $0.id == id }),
              tische[stelle].name != name else { return self }
        var neu = self
        neu.tische[stelle].name = name
        return neu
    }

    func ohne(_ id: String) -> Sitzplan {
        var neu = self
        if id == Sitzplan.lehrertischKennung { neu.lehrertisch = nil }
        else { neu.tische.removeAll { $0.id == id } }
        return neu
    }

    func mitLehrertisch() -> Sitzplan {
        guard lehrertisch == nil else { return self }
        var neu = self
        neu.lehrertisch = Sitzplanmasse.lehrertischStart
        return neu
    }

    /// Ein neuer Tisch an einer freien Stelle: zuerst die Plätze der
    /// Anfangsanordnung (von der Tafel weg), dann die Randplätze, dann das
    /// ganze Raster. `nil`, wenn die Grenze erreicht ist.
    func mitNeuemTisch(name roh: String) -> Sitzplan? {
        guard tische.count < Kennwerte.maxSitzplaetze else { return nil }
        let name = Sitzplan.bereinigterName(roh) ?? "Name"
        var vergeben = Set(tische.map(\.id))
        var id = Kennung.neu("t")
        while vergeben.contains(id) { id = Kennung.neu("t") }
        vergeben.insert(id)
        let lage = freieStelle()
        var neu = self
        neu.tische.append(Tisch(id: id, name: name, x: lage.x, y: lage.y))
        return neu
    }

    private func freieStelle() -> CGPoint {
        let groesse = CGSize(width: Sitzplanmasse.tischbreite, height: Sitzplanmasse.tischhoehe)
        func frei(_ punkt: CGPoint) -> Bool {
            let rahmen = CGRect(origin: punkt, size: groesse)
            guard Sitzplanmasse.tischbereich.contains(rahmen) else { return false }
            if let lehrer = lehrertischRahmen, lehrer.intersects(rahmen) { return false }
            return !tische.contains { $0.rahmen.intersects(rahmen) }
        }
        for plaetze in [Array(Sitzplanmasse.platzfolge.prefix(Sitzplanmasse.spalten)),
                        Array(Sitzplanmasse.platzfolge.dropFirst(Sitzplanmasse.spalten))] {
            for reihe in 0..<Sitzplanmasse.reihenHoechstens {
                for stelle in plaetze {
                    let punkt = CGPoint(
                        x: Sitzplanmasse.platz(stelle),
                        y: Sitzplanmasse.ersteReihe - CGFloat(reihe) * Sitzplanmasse.reihenschritt)
                    if frei(punkt) { return punkt }
                }
            }
        }
        let schritt = Sitzplanmasse.fangraster
        var y: CGFloat = 0
        while y + groesse.height <= Sitzplanmasse.tischbereich.maxY {
            var x: CGFloat = 0
            while x + groesse.width <= Sitzplanmasse.tischbereich.maxX {
                let punkt = CGPoint(x: x, y: y)
                if frei(punkt) { return punkt }
                x += schritt
            }
            y += schritt
        }
        return .zero
    }

    /// Ein Plan mit anderer Klassen-Kennung — bei „Neue Planung“ mit Übernahme.
    func mitKlasse(_ id: String) -> Sitzplan {
        var neu = self
        neu.klasseId = id
        return neu
    }
}

/// Die Datei `sitzplaene.json` im Container — alle Sitzpläne in einem Objekt,
/// je Klassen-Kennung einer. Gelesen mit derselben Vorsicht wie die
/// Planungsdatei: Typen geprüft, Grenzen gekappt, Lagen in den Rand geklemmt,
/// Kennungen ersetzt; geschrieben kanonisch. Was das Lesen dabei wegnahm oder
/// änderte, steht in der `Bilanz` (B14) — der Dienst meldet Verluste und
/// bewahrt das Original, bevor die bereinigte Fassung beim nächsten Schreiben
/// darüber geht.
enum Sitzplandatei {
    static let typ = "unterrichtsplanung-sitzplaene"
    static let version = 1
    /// Fünfundsiebzig Klassen mit je fünfunddreißig Tischen wiegen rund
    /// 300 KB; darüber hat diese App nicht geschrieben.
    static let hoechstgroesse = 1024 * 1024

    struct Fehler: LocalizedError, Sendable {
        enum Art: Sendable { case beschaedigt, neuereFassung }
        let art: Art
        let text: String
        var errorDescription: String? { text }
    }

    /// Was das Lesen bereinigt oder verworfen hat. `verlust` heißt: Klassen,
    /// Tische oder Namen sind weg oder gekürzt — das wird gemeldet, das
    /// Original bewahrt. Das Übrige ist Normierung: Lagen in die Fläche
    /// geholt, Kennungen ersetzt, ein unlesbarer Zeitstempel geleert.
    struct Bilanz: Equatable, Sendable {
        var verworfeneKlassen = 0
        var verworfeneTische = 0
        var gekuerzteNamen = 0
        var geklemmteLagen = 0
        var ersetzteKennungen = 0
        var bereinigteStempel = 0
        /// Ein Feld war da, aber nicht in lesbarer Form (etwa `lehrertisch` als
        /// Text) und wurde übergangen — benannt, nicht still (B23).
        var verworfeneFelder = 0

        var verlust: Bool { verworfeneKlassen + verworfeneTische + gekuerzteNamen > 0 }
        var istLeer: Bool {
            !verlust && geklemmteLagen == 0 && ersetzteKennungen == 0 && bereinigteStempel == 0
                && verworfeneFelder == 0
        }

        var beschreibung: String {
            var teile: [String] = []
            func satz(_ zahl: Int, _ eins: String, _ mehr: String) {
                if zahl == 1 { teile.append("1 " + eins) } else if zahl > 1 { teile.append("\(zahl) " + mehr) }
            }
            satz(verworfeneKlassen, "Klasse ohne gültige Kennung übergangen", "Klassen ohne gültige Kennung übergangen")
            satz(verworfeneTische, "Tisch ohne Namen oder über der Grenze übergangen",
                 "Tische ohne Namen oder über der Grenze übergangen")
            satz(gekuerzteNamen, "Name gekürzt", "Namen gekürzt")
            satz(geklemmteLagen, "Lage in die Fläche geholt", "Lagen in die Fläche geholt")
            satz(ersetzteKennungen, "Kennung ersetzt", "Kennungen ersetzt")
            satz(bereinigteStempel, "Zeitstempel geleert", "Zeitstempel geleert")
            satz(verworfeneFelder, "Feld ohne lesbare Form übergangen", "Felder ohne lesbare Form übergangen")
            return teile.joined(separator: ", ")
        }
    }

    static func lesen(_ daten: Data) throws -> [String: Sitzplan] {
        try lesenMitBilanz(daten).plaene
    }

    static func lesenMitBilanz(_ daten: Data) throws -> (plaene: [String: Sitzplan], bilanz: Bilanz) {
        guard let objekt = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any],
              objekt["typ"] as? String == typ
        else { throw Fehler(art: .beschaedigt, text: "Die Sitzpläne sind kein lesbares JSON.") }
        guard let fassung = Planungsdatei.ganzzahl(objekt["version"]), fassung >= 1 else {
            throw Fehler(art: .beschaedigt, text: "Die Sitzpläne tragen keine Fassungsnummer.")
        }
        guard fassung <= version else {
            throw Fehler(art: .neuereFassung,
                         text: "Die Sitzpläne stammen aus einer neueren Fassung der App (Fassung "
                             + "\(fassung)) — bitte die App aktualisieren.")
        }
        guard let rohePlaene = objekt["plaene"] as? [String: Any] else {
            throw Fehler(art: .beschaedigt, text: "Die Sitzpläne sind beschädigt.")
        }
        var bilanz = Bilanz()
        var plaene: [String: Sitzplan] = [:]
        for (klasseId, wert) in rohePlaene {
            guard Kennung.istGueltig(klasseId), let roh = wert as? [String: Any] else {
                bilanz.verworfeneKlassen += 1
                continue
            }
            // Ein Plan, dessen Tischliste keine ist, wird verworfen — nicht
            // still zum leeren Plan (B23); die Bilanz zählt ihn als Klasse.
            if let plan = plan(aus: roh, klasseId: klasseId, bilanz: &bilanz) {
                plaene[klasseId] = plan
            } else {
                bilanz.verworfeneKlassen += 1
            }
        }
        return (plaene, bilanz)
    }

    /// Nur Zahlen — `JSONSerialization` liefert auch `true` als `NSNumber`.
    private static func zahl(_ wert: Any?) -> CGFloat? {
        guard let z = wert as? NSNumber, CFGetTypeID(z) != CFBooleanGetTypeID() else { return nil }
        let d = z.doubleValue
        guard d.isFinite else { return nil }
        return CGFloat(d.rounded())
    }

    /// In den Bereich geklemmt; eine fehlende Lage zählt wie eine außerhalb.
    private static func geklemmt(_ x: CGFloat?, _ y: CGFloat?, in bereich: CGRect, groesse: CGSize,
                                 bilanz: inout Bilanz) -> CGPoint {
        let punkt = CGPoint(x: min(max(x ?? 0, bereich.minX), bereich.maxX - groesse.width),
                            y: min(max(y ?? 0, bereich.minY), bereich.maxY - groesse.height))
        if punkt.x != x || punkt.y != y { bilanz.geklemmteLagen += 1 }
        return punkt
    }

    /// `nil`, wenn `tische` da ist, aber keine Liste — fehlt der Schlüssel,
    /// ist der Plan leer und gültig.
    private static func plan(aus roh: [String: Any], klasseId: String, bilanz: inout Bilanz) -> Sitzplan? {
        var tische: [Tisch] = []
        var belegt = Set<String>()
        let eintraege: [Any]
        switch roh["tische"] {
        case nil: eintraege = []
        case let liste as [Any]: eintraege = liste
        default: return nil
        }
        if eintraege.count > Kennwerte.maxSitzplaetze {
            bilanz.verworfeneTische += eintraege.count - Kennwerte.maxSitzplaetze
        }
        for eintrag in eintraege.prefix(Kennwerte.maxSitzplaetze) {
            guard let t = eintrag as? [String: Any] else { bilanz.verworfeneTische += 1; continue }
            let sauber = Planungsdatei.einzeilig(Planungsdatei.ohneSteuerzeichen(Planungsdatei.text(t["name"])))
            guard !sauber.isEmpty else { bilanz.verworfeneTische += 1; continue }
            var name = sauber
            if name.count > Kennwerte.maxSitzplatzname {
                name = String(name.prefix(Kennwerte.maxSitzplatzname))
                bilanz.gekuerzteNamen += 1
            }
            var id = Planungsdatei.text(t["id"])
            if !Kennung.istGueltig(id) || belegt.contains(id) {
                repeat { id = Kennung.neu("t") } while belegt.contains(id)
                bilanz.ersetzteKennungen += 1
            }
            belegt.insert(id)
            let lage = geklemmt(zahl(t["x"]), zahl(t["y"]), in: Sitzplanmasse.tischbereich,
                                groesse: CGSize(width: Sitzplanmasse.tischbreite, height: Sitzplanmasse.tischhoehe),
                                bilanz: &bilanz)
            tische.append(Tisch(id: id, name: name, x: lage.x, y: lage.y))
        }
        var lehrertisch: CGPoint?
        switch roh["lehrertisch"] {
        case nil, is NSNull:
            break
        case let l as [String: Any]:
            lehrertisch = geklemmt(zahl(l["x"]), zahl(l["y"]), in: Sitzplanmasse.lehrertischbereich,
                                   groesse: CGSize(width: Sitzplanmasse.lehrertischbreite,
                                                   height: Sitzplanmasse.lehrertischhoehe),
                                   bilanz: &bilanz)
        default:
            bilanz.verworfeneFelder += 1
        }
        // Nur ein Stempel, den die App lesen kann (H01); sonst leer — die
        // Kopfzeile nimmt dann den Tag des Drucks.
        let stempel = Planungsdatei.ohneSteuerzeichen(Planungsdatei.text(roh["geaendert"]))
        let geaendert: String
        if stempel.isEmpty || Zeitrechnung.zeitpunkt(aus: stempel) != nil {
            geaendert = stempel
        } else {
            geaendert = ""
            bilanz.bereinigteStempel += 1
        }
        return Sitzplan(klasseId: klasseId, tische: tische, lehrertisch: lehrertisch, geaendert: geaendert)
    }

    static func schreiben(_ plaene: [String: Sitzplan]) throws -> Data {
        var rohePlaene: [String: Any] = [:]
        for (klasseId, plan) in plaene {
            var objekt: [String: Any] = [
                "tische": plan.tische.map { tisch -> [String: Any] in
                    ["id": tisch.id, "name": tisch.name, "x": Int(tisch.x), "y": Int(tisch.y)]
                },
                "geaendert": plan.geaendert,
            ]
            objekt["lehrertisch"] = plan.lehrertisch.map { ["x": Int($0.x), "y": Int($0.y)] } ?? NSNull()
            rohePlaene[klasseId] = objekt
        }
        return try JSONSerialization.data(
            withJSONObject: ["typ": typ, "version": version, "plaene": rohePlaene],
            options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
