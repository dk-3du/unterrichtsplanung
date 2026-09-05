// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Ein Kalendertag ohne Uhrzeit.
///
/// Speicherform ist die ISO-Schreibweise `JJJJ-MM-TT`; ihre lexikalische
/// Ordnung entspricht der zeitlichen. Darauf stützt sich die Web-Fassung mit
/// ihren reinen Zeichenkettenvergleichen.
struct Tag: Hashable, Comparable, Sendable, Codable {
    var jahr: Int
    var monat: Int
    var tagImMonat: Int

    init(jahr: Int, monat: Int, tagImMonat: Int) {
        self.jahr = jahr
        self.monat = monat
        self.tagImMonat = tagImMonat
    }

    /// Ausschließlich die strenge Form `JJJJ-MM-TT` — wie
    /// `/^\d{4}-\d{2}-\d{2}$/` in der Web-Fassung —, nur im Jahresbereich
    /// 1900–2999 und nur, wenn der Tag im Kalender wirklich existiert. Der
    /// 31. Februar ist kein Datum.
    init?(iso: String) {
        let teile = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard teile.count == 3,
              teile[0].count == 4, teile[1].count == 2, teile[2].count == 2,
              teile.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let j = Int(teile[0]), let m = Int(teile[1]), let t = Int(teile[2])
        else { return nil }
        // Vor dem Kalender und kalenderfrei, dieselbe Schranke wie in
        // `Tag(deutsch:)`: Bis 1899 deuten der Foundation-Kalender (Ären — der
        // 01.01.0000 ist ihm das Jahr 1 der Ära 0 — und die Lücke vom 5. bis
        // 14.10.1582) und das `Date.UTC` der Ansichtsfassung (julianische
        // Schalttage, Jahr 0000) dieselbe Zeichenkette verschieden.
        guard (1900...2999).contains(j) else { return nil }
        // Der Kalender rollt Unmögliches stillschweigend weiter (31.02. →
        // 03.03.); nur was die Rückrechnung unverändert übersteht, gilt.
        let kandidat = Tag(jahr: j, monat: m, tagImMonat: t)
        guard Tag(kandidat.datum) == kandidat else { return nil }
        self = kandidat
    }

    init(_ datum: Date) {
        let teile = Zeitrechnung.kalender.dateComponents([.year, .month, .day], from: datum)
        self.init(jahr: teile.year ?? 1970, monat: teile.month ?? 1, tagImMonat: teile.day ?? 1)
    }

    var iso: String {
        String(format: "%04d-%02d-%02d", jahr, monat, tagImMonat)
    }

    /// Mittag statt Mitternacht: So kann keine Zeitumstellung einen Tag
    /// verschieben, wenn ein Datum über `Date` hin- und hergerechnet wird.
    var datum: Date {
        var teile = DateComponents()
        teile.year = jahr
        teile.month = monat
        teile.day = tagImMonat
        teile.hour = 12
        return Zeitrechnung.kalender.date(from: teile) ?? .distantPast
    }

    func plus(tage: Int) -> Tag {
        Tag(Zeitrechnung.kalender.date(byAdding: .day, value: tage, to: datum) ?? datum)
    }

    /// Montag der Woche, in der dieser Tag liegt.
    var montagDerWoche: Tag {
        // Foundation zählt 1 = Sonntag … 7 = Samstag.
        let wochentag = Zeitrechnung.kalender.component(.weekday, from: datum)
        return plus(tage: -((wochentag + 5) % 7))
    }

    /// Kalenderwoche und zugehöriges Wochenjahr nach ISO 8601.
    var kalenderwoche: (kw: Int, jahr: Int) {
        let teile = Zeitrechnung.kalender.dateComponents([.weekOfYear, .yearForWeekOfYear], from: datum)
        return (teile.weekOfYear ?? 1, teile.yearForWeekOfYear ?? jahr)
    }

    /// „12.08.“
    var kurz: String {
        String(format: "%02d.%02d.", tagImMonat, monat)
    }

    func tageBis(_ anderer: Tag) -> Int {
        Zeitrechnung.kalender.dateComponents([.day], from: datum, to: anderer.datum).day ?? 0
    }

    /// „Mo“, „Di“ … — fest verdrahtet statt über einen `DateFormatter`: Der
    /// Termin steht in bis zu vierhundert Kacheln.
    var wochentagKurz: String {
        let namen = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let stelle = Zeitrechnung.kalender.component(.weekday, from: datum) - 1
        return namen.indices.contains(stelle) ? namen[stelle] : ""
    }

    /// „Montag“, „Dienstag“ …
    var wochentagLang: String {
        let namen = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag",
                     "Freitag", "Samstag"]
        let stelle = Zeitrechnung.kalender.component(.weekday, from: datum) - 1
        return namen.indices.contains(stelle) ? namen[stelle] : ""
    }

    /// „Do 17.09.“
    var mitWochentag: String { wochentagKurz + " " + kurz }

    /// Montag bis Freitag als `Wochentag`; `nil` am Wochenende. Foundation
    /// zählt 1 = Sonntag … 7 = Samstag, ISO 8601 zählt 1 = Montag … 7 = Sonntag.
    var wochentag: Wochentag? {
        let foundation = Zeitrechnung.kalender.component(.weekday, from: datum)
        return Wochentag(rawValue: (foundation + 5) % 7 + 1)
    }

    /// „03.08.2026“
    var deutsch: String {
        String(format: "%02d.%02d.%04d", tagImMonat, monat, jahr)
    }

    /// „3.8.2026“, „3.8.26“, auch mit Leerzeichen oder Bindestrichen;
    /// zweistellige Jahre gehen ins laufende Jahrhundert.
    init?(deutsch text: String) {
        let teile = text
            .replacingOccurrences(of: "-", with: ".")
            .replacingOccurrences(of: "/", with: ".")
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard teile.count == 3, let t = Int(teile[0]), let m = Int(teile[1]),
              var j = Int(teile[2]), teile.allSatisfy({ !$0.isEmpty })
        else { return nil }
        if teile[2].count <= 2 { j += 2000 }
        guard (1...31).contains(t), (1...12).contains(m), (1900...2999).contains(j)
        else { return nil }
        // Der 31. Februar wird auf den Monatsletzten gezogen, nicht verworfen.
        let gezogen = Tag(jahr: j, monat: m, tagImMonat: 1)
        let laenge = Zeitrechnung.kalender.range(of: .day, in: .month, for: gezogen.datum)?.count ?? 31
        self.init(jahr: j, monat: m, tagImMonat: min(t, laenge))
    }

    static var heute: Tag { Tag(Date()) }

    /// Die erste Woche des Schuljahres, in dem dieser Tag liegt: Ein Schuljahr
    /// beginnt am 1. August, bis Ende Juli gehört ein Tag noch zum Vorjahr.
    var schuljahresbeginn: Tag {
        let schuljahr = monat >= 8 ? jahr : jahr - 1
        let erster = Tag(jahr: schuljahr, monat: 8, tagImMonat: 1)
        return erster.montagDerWoche
    }

    static var laufendesSchuljahr: Tag { heute.schuljahresbeginn }

    static func < (links: Tag, rechts: Tag) -> Bool {
        (links.jahr, links.monat, links.tagImMonat) < (rechts.jahr, rechts.monat, rechts.tagImMonat)
    }

    init(from decoder: any Decoder) throws {
        let wert = try decoder.singleValueContainer().decode(String.self)
        guard let tag = Tag(iso: wert) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Kein Datum der Form JJJJ-MM-TT: \(wert)"))
        }
        self = tag
    }

    func encode(to encoder: any Encoder) throws {
        var behälter = encoder.singleValueContainer()
        try behälter.encode(iso)
    }
}

/// Die fünf Unterrichtstage Montag bis Freitag, nach ISO 8601 gezählt
/// (Montag = 1). In der Datei steht die Zahl; beschriftet wird „Mo.“ … „Fr.“.
/// Wortgleich in der Ansichtsfassung (`WOCHENTAGE`).
enum Wochentag: Int, CaseIterable, Identifiable, Hashable, Comparable, Sendable {
    case montag = 1, dienstag, mittwoch, donnerstag, freitag

    var id: Int { rawValue }

    /// „Mo.“ — mit Punkt, wie in den Dialogen beschriftet; `Tag.wochentagKurz`
    /// („Mo“) bleibt die Form der Kacheln.
    var kurz: String { ["Mo.", "Di.", "Mi.", "Do.", "Fr."][rawValue - 1] }

    var lang: String {
        ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag"][rawValue - 1]
    }

    static func < (links: Wochentag, rechts: Wochentag) -> Bool {
        links.rawValue < rechts.rawValue
    }

    /// Der Tag dieses Wochentags in der Woche, in der `tag` liegt — die eine
    /// Stelle, an der aus „Mi.“ ein Datum wird; Dialog und `Woche.tag` rufen sie.
    func datum(inWocheVon tag: Tag) -> Tag {
        tag.montagDerWoche.plus(tage: rawValue - 1)
    }
}

extension Set<Wochentag> {
    /// „Mo., Mi., Fr.“ in Wochenreihenfolge; leer bleibt leer.
    var beschriftung: String { sorted().map(\.kurz).joined(separator: ", ") }

    /// Die Form in der Datei: aufsteigend, jede Zahl einmal.
    var gespeichert: [Int] { sorted().map(\.rawValue) }
}

/// Die eine Zeitrechnung der App: ISO 8601, Montag als erster Wochentag.
enum Zeitrechnung {
    static let kalender: Calendar = {
        var k = Calendar(identifier: .iso8601)
        k.timeZone = .current
        k.locale = Locale(identifier: "de_DE")
        return k
    }()

    /// „September 2026“
    static func monatUndJahr(_ tag: Tag) -> String {
        let namen = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
                     "August", "September", "Oktober", "November", "Dezember"]
        let stelle = tag.monat - 1
        let name = namen.indices.contains(stelle) ? namen[stelle] : ""
        return name + " " + String(tag.jahr)
    }

    /// „12.8.2026, 17:56:12“
    static func zeitpunktLang(_ iso: String) -> String {
        guard let d = zeitpunkt(aus: iso) else { return "unbekannt" }
        return Formatvorrat.gemeinsam.lang(d)
    }

    static func zeitpunktLang(_ datum: Date) -> String {
        Formatvorrat.gemeinsam.lang(datum)
    }

    static func zeitpunkt(aus iso: String) -> Date? {
        Formatvorrat.gemeinsam.datum(aus: iso)
    }

    /// Genau die Form von `new Date().toISOString()` — damit sich die Stände
    /// beider Fassungen vergleichen lassen.
    static func jetztAlsZeitstempel() -> String {
        Formatvorrat.gemeinsam.zeitstempel(Date())
    }

    /// „2026-08-27-231205“ — für Dateinamen, die sich nicht überschreiben
    /// sollen. Mit Uhrzeit, weil an einem Tag mehrere Rettungskopien anfallen.
    static func dateistempel() -> String {
        let iso = jetztAlsZeitstempel()
        return iso.prefix(19)
            .replacingOccurrences(of: "T", with: "-")
            .replacingOccurrences(of: ":", with: "")
    }
}

/// Datumsformatierer sind teuer im Aufbau und nicht nebenläufigkeitssicher —
/// einmal angelegt und hinter einer Sperre geteilt.
private final class Formatvorrat: @unchecked Sendable {
    static let gemeinsam = Formatvorrat()

    private let sperre = NSLock()
    private let mitBruchteilen: ISO8601DateFormatter
    private let ohneBruchteile: ISO8601DateFormatter
    private let volleUhr: DateFormatter

    private init() {
        mitBruchteilen = ISO8601DateFormatter()
        mitBruchteilen.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        mitBruchteilen.timeZone = TimeZone(secondsFromGMT: 0)

        ohneBruchteile = ISO8601DateFormatter()
        ohneBruchteile.formatOptions = [.withInternetDateTime]
        ohneBruchteile.timeZone = TimeZone(secondsFromGMT: 0)

        volleUhr = Formatvorrat.uhr("d.M.yyyy, HH:mm:ss")
    }

    func zeitstempel(_ datum: Date) -> String {
        sperre.withLock { mitBruchteilen.string(from: datum) }
    }

    func datum(aus iso: String) -> Date? {
        sperre.withLock { mitBruchteilen.date(from: iso) ?? ohneBruchteile.date(from: iso) }
    }

    func lang(_ datum: Date) -> String { sperre.withLock { volleUhr.string(from: datum) } }

    private static func uhr(_ muster: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = .current
        f.dateFormat = muster
        return f
    }
}

/// Eine Spalte des Rasters: die Unterrichtswoche.
struct Woche: Identifiable, Hashable, Sendable {
    let nummer: Int          // Spaltenindex, 0-basiert
    let montag: Tag
    let freitag: Tag
    let kw: Int
    let jahr: Int
    /// Montag bis Freitag — bewusst **berechnet und nicht gespeichert**, weil
    /// `Woche` in jede der bis zu 780 Zellen kopiert wird. Kostet fünf
    /// Kalenderrechnungen je Zugriff.
    var unterrichtstage: [Tag] { (0...4).map { montag.plus(tage: $0) } }

    /// Gespeichert, nicht berechnet: `ForEach` holt die Kennung über einen
    /// Schlüsselpfad — berechnet ginge das über eine global gesperrte Tabelle
    /// der Laufzeit, bei 780 Zellen je Größenanfrage.
    let id: Int
    var iso: String { montag.iso }
    var spanne: String { montag.kurz + "–" + freitag.kurz }
    var beschriftung: String { "KW \(kw)" }

    /// Die Beschriftung samt Schulwoche — `nil` (volle Ferienwoche oder vor
    /// Schulbeginn, siehe `Planung.schulwochen`) lässt sie unverändert.
    func beschriftung(schulwoche: Int?) -> String {
        schulwoche.map { beschriftung + " / \($0). Schulwoche" } ?? beschriftung
    }

    /// Der Tag dieser Woche, der auf den Wochentag fällt.
    func tag(_ wochentag: Wochentag) -> Tag { wochentag.datum(inWocheVon: montag) }

    init(nummer: Int, montag: Tag) {
        self.id = nummer
        self.nummer = nummer
        self.montag = montag
        self.freitag = montag.plus(tage: 4)
        let kw = montag.kalenderwoche
        self.kw = kw.kw
        self.jahr = kw.jahr
    }

    static func == (a: Woche, b: Woche) -> Bool {
        a.nummer == b.nummer && a.montag == b.montag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(nummer)
        hasher.combine(montag)
    }
}

extension Tag {
    static func wochenListe(start: Tag, anzahl: Int) -> [Woche] {
        let ersterMontag = start.montagDerWoche
        return (0..<max(0, anzahl)).map { Woche(nummer: $0, montag: ersterMontag.plus(tage: $0 * 7)) }
    }
}
