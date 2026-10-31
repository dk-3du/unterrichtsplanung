// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Der Leser einer Exportdatei der IServ-Benutzerverwaltung (Plan 4.4, AP13).
/// Reine Funktionen ohne AppKit — `abzug_pruefen.py` übersetzt das Modell
/// allein. Der Leser rät nicht: Er zeigt die Datei, die Spalten werden
/// zugeordnet. Übernommen werden nur Vorname, Nachname und Klasse/Information;
/// die übrigen Spalten übergeht das Lesen der Zeilen, und die Vorschau zeigt sie
/// nicht — die Spaltenwahl nennt nur die Namen einer erkannten Kopfzeile
/// (Nutzer, 02.10.2026; W1-10, W3-02). Keine Netzverbindung, kein Zugriff auf IServ.
enum IServImport {
    /// Größer liefert die Benutzerverwaltung keine Liste.
    static let hoechstgroesse = 4 * 1024 * 1024
    /// So viele Datenzeilen zeigt die Vorschau.
    static let vorschauzeilen = 10

    // ── Kodierung ─────────────────────────────────────────────────────────

    enum Kodierung: String, CaseIterable, Identifiable, Sendable {
        case utf8 = "UTF-8"
        case windows1252 = "Windows-1252"
        case iso885915 = "ISO-8859-15"

        var id: String { rawValue }

        var encoding: String.Encoding {
            switch self {
            case .utf8: .utf8
            case .windows1252: .windowsCP1252
            case .iso885915:
                String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.isoLatin9.rawValue)))
            }
        }
    }

    struct Text: Equatable, Sendable {
        let inhalt: String
        let kodierung: Kodierung
        let bom: Bool
    }

    /// Der BOM wird erkannt und abgelegt; dann UTF-8, bei ungültigen Folgen
    /// Windows-1252, zuletzt ISO-8859-15 (jedes Byte belegt). Gewählt gilt
    /// genau die eine — `nil`, wenn sie nicht passt.
    static func entschluesseln(_ daten: Data, kodierung gewaehlt: Kodierung? = nil) -> Text? {
        let bom = daten.starts(with: [0xEF, 0xBB, 0xBF])
        let rumpf = Data(bom ? daten.dropFirst(3) : daten[...])
        for kodierung in gewaehlt.map({ [$0] }) ?? Kodierung.allCases {
            if let inhalt = String(data: rumpf, encoding: kodierung.encoding) {
                return Text(inhalt: inhalt, kodierung: kodierung, bom: bom)
            }
        }
        return nil
    }

    // ── Trenner und Zerlegen ──────────────────────────────────────────────

    enum Trenner: String, CaseIterable, Identifiable, Sendable {
        case semikolon = ";"
        case komma = ","
        case tab = "\t"

        var id: String { rawValue }
        var name: String {
            switch self {
            case .semikolon: "Semikolon"
            case .komma: "Komma"
            case .tab: "Tabulator"
            }
        }
    }

    /// In den ersten zwanzig Zeilen gezählt, nach dem Zerlegen — Trenner in
    /// Anführungszeichen zählen also nicht: Es gewinnt der Trenner, mit dem die
    /// meisten Zeilen gleich viele Felder (mindestens zwei) haben; bei
    /// Gleichstand Semikolon vor Komma vor Tab. Zerlegt wird nur so weit —
    /// nicht die ganze Datei je Trenner (R86-04); nur ein offenes
    /// Anführungszeichen nimmt die Zerlegung bis zum Ende mit (H2-01). Erkennt genau ein Trenner die
    /// Kopfzeile von IServ, gilt er vor der Zählung (E890, Z-AY2-07): Ein offenes
    /// Anführungszeichen verschluckt unter dem richtigen Trenner den Rest, und ein
    /// Komma in einer Spalte ließe sonst den falschen gewinnen — dann griffe die
    /// Sperre nicht.
    static func trennerErkennen(_ text: String) -> Trenner {
        let anfaenge = Trenner.allCases.map { ($0, zerlegung(text, trenner: $0, hoechstens: 20).zeilen) }
        let mitKopf = anfaenge.filter { $0.1.first.flatMap(zuordnungAusKopf) != nil }
        if mitKopf.count == 1 { return mitKopf[0].0 }
        var bester = Trenner.semikolon
        var bestwert = 0
        for (trenner, anfang) in anfaenge {
            let zeilen = anfang.filter { !($0.count == 1 && $0[0].isEmpty) }
            var haeufigkeit: [Int: Int] = [:]
            for zeile in zeilen where zeile.count >= 2 { haeufigkeit[zeile.count, default: 0] += 1 }
            let wert = haeufigkeit.values.max() ?? 0
            if wert > bestwert {
                bester = trenner
                bestwert = wert
            }
        }
        return bester
    }

    /// Die Datensätze der Datei (`zeilen`) — und, öffnet ein Anführungszeichen ein Feld, das bis zum Ende der Datei nicht geschlossen
    /// wird, die Zeile der Datei, in der es öffnet, ab 1 mit der Kopfzeile gezählt; sonst `nil` (F-03, E871 a, Z-AY2a-01).
    struct Zerlegung: Equatable, Sendable {
        var zeilen: [[String]]
        var offenesAnfuehrungszeichen: Int?
        /// Die Zeile, in der das erste Anführungszeichen öffnet, dessen Feld über ein Zeilenende läuft — es schließt erst
        /// in einer späteren Zeile oder gar nicht (dann sagt `offenesAnfuehrungszeichen` mehr und geht vor, G2-03). In
        /// einer Datei aus IServ ein Fehler (E892 a); `nil`, wenn kein Feld über ein Zeilenende läuft.
        var feldUeberZeilenende: Int? = nil
    }

    /// Zählt im Prüfziel die Zerlegungen — ganze und nach Datensätzen begrenzte —, damit eine Prüfung festhält, wie oft
    /// der Bogen eine Datei zerlegt (R86-04). Außerhalb einer Prüfung ist keins gesetzt, und gezählt wird nichts.
    final class Zaehlwerk: @unchecked Sendable {
        private let sperre = NSLock()
        private var ganz = 0
        private var begrenzt = 0

        func zaehlen(begrenzt istBegrenzt: Bool) {
            sperre.withLock { if istBegrenzt { begrenzt += 1 } else { ganz += 1 } }
        }

        var ganzeZerlegungen: Int { sperre.withLock { ganz } }
        var begrenzteZerlegungen: Int { sperre.withLock { begrenzt } }
    }

    @TaskLocal static var zaehlwerk: Zaehlwerk?

    /// Die Zeilen allein — siehe `zerlegung`.
    static func zerlegen(_ text: String, trenner: Trenner) -> [[String]] {
        zerlegung(text, trenner: trenner).zeilen
    }

    /// RFC 4180: Ein Feld in Anführungszeichen darf Trenner und Zeilenwechsel
    /// tragen, `""` ist ein Anführungszeichen. Jeder Zeilenwechsel außerhalb
    /// (CRLF, LF, CR) beendet eine Zeile; eine leere Zeile bleibt als `[""]`
    /// stehen, damit die Zeilennummern der Bilanz stimmen. Ein offenes
    /// Anführungszeichen nimmt den Rest der Datei — und die Zerlegung nennt
    /// die Zeile, in der es öffnet. Ein Feld, das über ein Zeilenende läuft, nennt die
    /// Zerlegung ebenso (`feldUeberZeilenende`, E892 a) — IServ schreibt keins, der Bogen
    /// sperrt. Beide Nummern sind Zeilen der Datei, nicht Datensätze (Z-AY2a-01).
    /// `hoechstens`: nach so vielen Datensätzen aufhören — dann sagen
    /// `offenesAnfuehrungszeichen` und `feldUeberZeilenende` nichts über den Rest (Z-AY2-08).
    static func zerlegung(_ text: String, trenner: Trenner, hoechstens: Int = .max) -> Zerlegung {
        zaehlwerk?.zaehlen(begrenzt: hoechstens != .max)
        guard !text.isEmpty else { return Zerlegung(zeilen: [], offenesAnfuehrungszeichen: nil) }
        let trennzeichen = Character(trenner.rawValue)
        var zeilen: [[String]] = []
        var felder: [String] = []
        var feld = ""
        var inAnfuehrung = false
        var ueberZeilenende: Int?
        // Die Zeile der Datei, in der das Zeichen steht, und die, in der das laufende Anführungszeichen öffnete.
        var zeile = 1
        var anfuehrungAb = 1
        var zeichen = text.makeIterator()
        var vorgemerkt: Character?
        while let z = vorgemerkt ?? zeichen.next() {
            vorgemerkt = nil
            if inAnfuehrung {
                if z == "\"" {
                    if let folgt = zeichen.next() {
                        if folgt == "\"" { feld.append("\"") } else { inAnfuehrung = false; vorgemerkt = folgt }
                    } else {
                        inAnfuehrung = false
                    }
                } else {
                    if z.isNewline {
                        if ueberZeilenende == nil { ueberZeilenende = anfuehrungAb }
                        zeile += 1
                    }
                    feld.append(z)
                }
            } else if z == "\"" && feld.isEmpty {
                inAnfuehrung = true
                anfuehrungAb = zeile
            } else if z == trennzeichen {
                felder.append(feld)
                feld = ""
            } else if z.isNewline {
                felder.append(feld)
                zeilen.append(felder)
                felder = []
                feld = ""
                zeile += 1
                if zeilen.count >= hoechstens {
                    return Zerlegung(zeilen: zeilen, offenesAnfuehrungszeichen: nil, feldUeberZeilenende: ueberZeilenende)
                }
            } else {
                feld.append(z)
            }
        }
        // Ein Datensatz endet nie in Anführungszeichen — offen ist das zuletzt geöffnete, in der Zeile `anfuehrungAb`.
        let offen = inAnfuehrung ? anfuehrungAb : nil
        felder.append(feld)
        zeilen.append(felder)
        // Ein Zeilenwechsel am Ende eröffnet keine Zeile.
        if text.last?.isNewline == true, zeilen.last == [""] { zeilen.removeLast() }
        return Zerlegung(zeilen: zeilen, offenesAnfuehrungszeichen: offen, feldUeberZeilenende: ueberZeilenende)
    }

    // ── Kopfzeile und Zuordnung ───────────────────────────────────────────

    /// Welche Spalte was trägt — Vorname und Nachname sind Pflicht, Klasse
    /// freiwillig; nichts weiter.
    struct Zuordnung: Equatable, Sendable {
        var vorname: Int?
        var nachname: Int?
        var klasse: Int?

        var vollstaendig: Bool { vorname != nil && nachname != nil && vorname != nachname }
    }

    /// Erkannt an den Spaltennamen von IServ (Groß/Klein und Leerraum
    /// unerheblich) — `nil` heißt: keine Kopfzeile.
    static func zuordnungAusKopf(_ kopf: [String]) -> Zuordnung? {
        func stelle(_ name: String) -> Int? {
            kopf.firstIndex { $0.trimmingCharacters(in: .whitespaces).lowercased() == name.lowercased() }
        }
        let zuordnung = Zuordnung(vorname: stelle("Vorname"), nachname: stelle("Nachname"),
                                  klasse: stelle("Klasse/Information") ?? stelle("Klasse"))
        return zuordnung.vollstaendig ? zuordnung : nil
    }

    // ── Zeilen ────────────────────────────────────────────────────────────

    struct Zeile: Equatable, Sendable {
        /// Die Zeile in der Datei, ab 1 gezählt — mit Kopfzeile.
        let nummer: Int
        let vorname: String
        let nachname: String
        let klasse: String
    }

    /// Eine Zeile, die nicht übernommen wird — mit Nummer und Grund, die Form
    /// von `Kurszeilen.Fehler`.
    struct Fehler: Equatable, Sendable, Identifiable {
        var id: Int { nummer }
        let nummer: Int
        let grund: String
    }

    struct Lesung: Equatable, Sendable {
        var zeilen: [Zeile] = []
        var fehler: [Fehler] = []
    }

    /// Die Datenzeilen, bereinigt wie Namen am Tisch: ohne Steuerzeichen, eine
    /// Zeile, Leerraum zusammengefasst. Leere Zeilen werden still übergangen;
    /// eine Zeile ohne Vor- und Nachnamen und ein Name über der Grenze werden
    /// benannt, nicht gekürzt.
    static func lesen(_ tabelle: [[String]], kopfzeile: Bool, zuordnung: Zuordnung) -> Lesung {
        guard zuordnung.vollstaendig, let v = zuordnung.vorname, let n = zuordnung.nachname else { return Lesung() }
        var lesung = Lesung()
        for (stelle, felder) in tabelle.enumerated() {
            if kopfzeile && stelle == 0 { continue }
            let nummer = stelle + 1
            if felder.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            func feld(_ spalte: Int?) -> String {
                guard let spalte, felder.indices.contains(spalte) else { return "" }
                return Lernendenbestand.zeile(Planungsdatei.einzeilig(felder[spalte]), Int.max)
            }
            let vorname = feld(v)
            let nachname = feld(n)
            if vorname.isEmpty && nachname.isEmpty {
                lesung.fehler.append(Fehler(nummer: nummer, grund: "Kein Vor- und Nachname."))
                continue
            }
            if vorname.count > Kennwerte.maxLernendenname || nachname.count > Kennwerte.maxLernendenname {
                lesung.fehler.append(Fehler(nummer: nummer,
                                            grund: "Ein Name ist länger als \(Kennwerte.maxLernendenname) Zeichen."))
                continue
            }
            lesung.zeilen.append(Zeile(nummer: nummer, vorname: vorname, nachname: nachname,
                                       klasse: String(feld(zuordnung.klasse).prefix(Planungsdatei.maxNamenslaenge))))
        }
        return lesung
    }
}

// ── Der Abgleich mit der Zielgruppe (E254) ────────────────────────────────

/// Wohin der Import geht: eine bestehende Lerngruppe, eine neue, oder je
/// Klasse eine (die erste aktive Lerngruppe dieses Namens in der Folge der Listen, sonst neu — E353, V10).
enum Importziel: Equatable, Sendable {
    case gruppe(String)
    case neueGruppe(String)
    case jeKlasse
}

/// Eine Person, die in der Datei einer Zielgruppe fehlt, aber in einer anderen aktiven Lerngruppe steht (E368).
struct Fehlmitgliedschaft: Hashable, Sendable {
    var person: String
    var gruppe: String
}

struct Importbilanz: Equatable, Sendable {
    var neu: [IServImport.Zeile] = []
    /// Personen aus einer anderen Gruppe der Jahresdatei, jetzt auch in der Zielgruppe (E288).
    var zugeordnet: [IServImport.Zeile] = []
    /// Archivierte Mitglieder der Zielgruppe, die die Datei wieder nennt (E299).
    var zurueckgeholt: [IServImport.Zeile] = []
    var unveraendert: [IServImport.Zeile] = []
    var uebergangen: [IServImport.Fehler] = []
    var neueGruppen: [String] = []
    /// Die neuen Lerngruppen zum Zeigen — geordnet wie alle Listen (E343, Z-AS5-08); angelegt
    /// werden sie in der Folge der Datei.
    var neueGruppenGeordnet: [String] { neueGruppen.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    /// Aktive Mitglieder der Zielgruppen, die in der Datei fehlen und in keiner
    /// anderen aktiven Lerngruppe stehen — genannt, nie gelöscht; das Blatt
    /// bietet „archivieren“ an (E368).
    var fehlende: [String] = []
    /// Fehlen in der Datei, stehen aber in einer anderen aktiven Lerngruppe —
    /// sie werden nicht archiviert, nur aus der Zielgruppe genommen (E368).
    var fehlendeAnderswo: [Fehlmitgliedschaft] = []

    var kurz: String {
        "\(neu.count) neu" + (zugeordnet.isEmpty ? "" : " · \(zugeordnet.count) zugeordnet")
            + (zurueckgeholt.isEmpty ? "" : " · \(zurueckgeholt.count) zurückgeholt")
            + " · \(unveraendert.count) unverändert · \(uebergangen.count) übergangen"
    }

    /// Die Meldung nach dem Import (E523) — mit der Bindung nach Namen, wenn sie lief.
    func meldung(_ bindung: Namensbindung?) -> String {
        let anfang = "IServ-Import: \(kurz)"
        guard let bindung, bindung.gebunden + bindung.ohneZeile > 0 else { return anfang + "." }
        func gruppen(_ n: Int) -> String { "\(n) \(n == 1 ? "Lerngruppe" : "Lerngruppen")" }
        let ohne = "ohne freie Zeile gleichen Namens — binden unter „Lernende, Klassen/Kurse und Fächer“ (⌘K)"
        guard bindung.gebunden > 0 else { return anfang + "; \(gruppen(bindung.ohneZeile)) \(ohne)." }
        return anfang + "; \(gruppen(bindung.gebunden)) an ihre Zeilen gebunden"
            + (bindung.ohneZeile > 0 ? ", \(bindung.ohneZeile) \(ohne)" : "") + "."
    }
}

/// Was die Bindung nach Namen ausrichtete (E352, E521): Lerngruppen, die wenigstens eine freie Unterrichtszeile gleichen
/// Namens bekamen, und solche ohne.
struct Namensbindung: Equatable, Sendable {
    var gebunden = 0
    var ohneZeile = 0
}

extension Lernendenbestand {

    /// Der Import aus dem Bogen samt Bindung nach Namen (E352): nur bei „Je Klasse“ und nur die dabei neu angelegten
    /// Lerngruppen, an die Unterrichtszeilen `zeilen` der Planung `planung`. `zeilen == nil`: ohne Bindung.
    func mitImport(_ lesung: IServImport.Lesung, ziel: Importziel, binden zeilen: [Klasse]?, planung: String,
                   jetzt: String) -> (bestand: Lernendenbestand, bilanz: Importbilanz, bindung: Namensbindung?) {
        let (neu, bilanz) = mitImport(lesung, ziel: ziel, jetzt: jetzt)
        guard let zeilen, ziel == .jeKlasse else { return (neu, bilanz, nil) }
        let bisher = Set(lerngruppen.map(\.id))
        let angelegt = neu.lerngruppen.map(\.id).filter { !bisher.contains($0) }
        let (gebunden, bindung) = neu.mitBindungenNachNamen(angelegt, zeilen: zeilen, planung: planung, jetzt: jetzt)
        return (gebunden, bilanz, bindung)
    }

    /// Vorname und Nachname innerhalb der Zielgruppe gleich (Groß/Klein und
    /// Leerraum unerheblich) → unverändert; genau eine aktive Person dieses
    /// Namens anderswo in der Jahresdatei → zugeordnet (E288); sonst neu, mit
    /// dem Zeitpunkt des Imports als Importkennung (E251). Gleichnamige in der
    /// Datei, in der Gruppe oder im Schuljahr werden genannt, nichts geraten.
    /// Nie gelöscht.
    func mitImport(_ lesung: IServImport.Lesung, ziel: Importziel, jetzt: String) -> (bestand: Lernendenbestand, bilanz: Importbilanz) {
        var neu = self
        var bilanz = Importbilanz(uebergangen: lesung.fehler)

        // Die Zeilen je Zielgruppe, in der Reihenfolge der Datei.
        var verteilung: [(gruppe: String, zeilen: [IServImport.Zeile])] = []
        // Wer in der Datei einer Zielgruppe fehlt — getrennt erst nach dem ganzen Import (E368).
        var fehlendJe: [(gruppe: String, person: String)] = []
        func zuteilen(_ zeile: IServImport.Zeile, _ gruppe: String) {
            if let stelle = verteilung.firstIndex(where: { $0.gruppe == gruppe }) {
                verteilung[stelle].zeilen.append(zeile)
            } else {
                verteilung.append((gruppe, [zeile]))
            }
        }
        func gruppeAnlegen(_ name: String) -> String? {
            guard let angelegt = neu.mitNeuerGruppe(name: name, art: .klasse, jetzt: jetzt) else { return nil }
            neu = angelegt.bestand
            bilanz.neueGruppen.append(name)
            return angelegt.id
        }
        switch ziel {
        case .gruppe(let id):
            if neu.lerngruppen.contains(where: { $0.id == id && $0.archiviert.isEmpty }) {
                for zeile in lesung.zeilen { zuteilen(zeile, id) }
            } else {
                bilanz.uebergangen += lesung.zeilen.map { .init(nummer: $0.nummer, grund: "Die Zielgruppe fehlt.") }
            }
        case .neueGruppe(let name):
            if let id = gruppeAnlegen(name) {
                for zeile in lesung.zeilen { zuteilen(zeile, id) }
            } else {
                bilanz.uebergangen += lesung.zeilen.map { .init(nummer: $0.nummer, grund: "Keine neue Lerngruppe möglich.") }
            }
        case .jeKlasse:
            var angelegt: [String: String] = [:]
            for zeile in lesung.zeilen {
                guard !zeile.klasse.isEmpty else {
                    bilanz.uebergangen.append(.init(nummer: zeile.nummer, grund: "Keine Klasse angegeben."))
                    continue
                }
                let schluessel = zeile.klasse.lowercased()
                if let id = angelegt[schluessel] {
                    zuteilen(zeile, id)
                    continue
                }
                // Die erste aktive Lerngruppe dieses Namens (E353, V10) in der Folge der Listen — Name, dann Kennung, nicht die
                // Folge der Datei (Z-AT9a1-05); ein Fach unterscheidet sie nicht mehr (E665). Gesucht wird je Klasse einmal (Z-AT5-03).
                let gleichnamige = neu.lerngruppen.filter { $0.archiviert.isEmpty && $0.name.lowercased() == schluessel }
                    .sorted(by: Lerngruppe.vorgehen)
                if let getroffen = gleichnamige.first {
                    angelegt[schluessel] = getroffen.id
                    zuteilen(zeile, getroffen.id)
                } else if let id = gruppeAnlegen(zeile.klasse) {
                    angelegt[schluessel] = id
                    zuteilen(zeile, id)
                } else {
                    bilanz.uebergangen.append(.init(nummer: zeile.nummer, grund: "Keine neue Lerngruppe möglich."))
                }
            }
        }

        for (gruppe, zeilen) in verteilung {
            let beschriftung = neu.lerngruppen.first { $0.id == gruppe }?.beschriftung ?? ""
            func gleich(_ zeile: IServImport.Zeile, _ person: Lernender) -> Bool {
                Lernendenbestand.gleicherName(zeile.vorname, zeile.nachname, wie: person)
            }
            let mitglieder = (neu.lerngruppen.first { $0.id == gruppe }?.mitglieder ?? [])
                .compactMap { id in neu.lernende.first { $0.id == id } }
            var anzulegen: [IServImport.Zeile] = []
            var gefunden = Set<String>()
            // Gleichnamige der Datei über den Schlüssel zu `gleicherName` in einem Durchgang, in der Folge der Datei — nicht
            // jede Zeile mit jeder (Z-AY2-01: 1200 Zeilen waren 1,44 Mio. Vergleiche je Vorschau; Z-AY2N-02: eine Regel).
            func name(_ z: IServImport.Zeile) -> String { Lernendenbestand.namensschluessel(z.vorname, z.nachname) }
            var jeName: [String: [IServImport.Zeile]] = [:]
            for zeile in zeilen { jeName[name(zeile), default: []].append(zeile) }
            for zeile in zeilen {
                let inDatei = jeName[name(zeile)] ?? [zeile]
                if inDatei.count > 1 {
                    let nummern = inDatei.map { String($0.nummer) }
                    let liste = nummern.dropLast().joined(separator: ", ") + " und " + (nummern.last ?? "")
                    bilanz.uebergangen.append(.init(nummer: zeile.nummer,
                                                    grund: "Gleichnamig in der Datei (Zeilen \(liste)) — nichts geraten."))
                    // Wen die Datei nennt, der fehlt nicht — auch zweimal genannt (Z-AT1-01).
                    mitglieder.filter { gleich(zeile, $0) }.forEach { gefunden.insert($0.id) }
                    continue
                }
                let inGruppe = mitglieder.filter { gleich(zeile, $0) }
                // Eine aktive Person gilt vor einer archivierten gleichen Namens — wie bei der Eingabe von Hand (Z14c-03).
                let aktive = inGruppe.filter { $0.archiviert.isEmpty }
                let treffer = aktive.isEmpty ? inGruppe : aktive
                if treffer.count > 1 {
                    bilanz.uebergangen.append(.init(nummer: zeile.nummer,
                                                    grund: "Zwei Gleichnamige in „\(beschriftung)“ — nichts geraten."))
                    inGruppe.forEach { gefunden.insert($0.id) }
                } else if let person = treffer.first, !person.archiviert.isEmpty {
                    // Archiviert in der Zielgruppe, von der Datei wieder genannt — zurückgeholt (E299).
                    neu = neu.mitZurueckgeholterPerson(person.id, jetzt: jetzt)
                    bilanz.zurueckgeholt.append(zeile)
                    gefunden.insert(person.id)
                } else if let person = treffer.first {
                    bilanz.unveraendert.append(zeile)
                    gefunden.insert(person.id)
                } else {
                    anzulegen.append(zeile)
                }
            }
            let ergebnis = neu.mitPersonen(anzulegen.map { Namenszeilen.Name(vorname: $0.vorname, nachname: $0.nachname) },
                                           inGruppe: gruppe, jetzt: jetzt)
            neu = ergebnis.bestand
            for (zeile, ausgang) in zip(anzulegen, ergebnis.ausgaenge) {
                switch ausgang {
                case .neu: bilanz.neu.append(zeile)
                case .zugeordnet: bilanz.zugeordnet.append(zeile)
                case .zurueckgeholt: bilanz.zurueckgeholt.append(zeile)
                case .schonDa: bilanz.unveraendert.append(zeile)
                case .gleichnamig:
                    bilanz.uebergangen.append(.init(nummer: zeile.nummer,
                                                    grund: "Mehrere Gleichnamige in diesem Schuljahr — nichts geraten."))
                case .ueberGrenze:
                    bilanz.uebergangen.append(.init(nummer: zeile.nummer,
                                                    grund: "Über der Grenze von \(Kennwerte.maxMitgliederJeLerngruppe) je Lerngruppe."))
                case .leer:
                    bilanz.uebergangen.append(.init(nummer: zeile.nummer, grund: "Kein Vor- und Nachname."))
                }
            }
            fehlendJe += mitglieder.filter { $0.archiviert.isEmpty && !gefunden.contains($0.id) }.map { (gruppe: gruppe, person: $0.id) }
        }
        // E368: Wer nach dem Import noch in einer anderen aktiven Gruppe steht — einer, in der er nicht fehlt —,
        // wird nicht archiviert, nur aus der Zielgruppe genommen; die übrigen bietet das Blatt zum Archivieren an.
        var fehlgruppen: [String: Set<String>] = [:]
        for (gruppe, person) in fehlendJe { fehlgruppen[person, default: []].insert(gruppe) }
        for (gruppe, person) in fehlendJe {
            let anderswo = neu.lerngruppen.contains { g in
                g.archiviert.isEmpty && g.mitglieder.contains(person) && fehlgruppen[person]?.contains(g.id) != true
            }
            if anderswo {
                bilanz.fehlendeAnderswo.append(Fehlmitgliedschaft(person: person, gruppe: gruppe))
            } else if !bilanz.fehlende.contains(person) {
                bilanz.fehlende.append(person)
            }
        }
        bilanz.uebergangen.sort { $0.nummer < $1.nummer }
        bilanz.neu.sort { $0.nummer < $1.nummer }
        bilanz.zugeordnet.sort { $0.nummer < $1.nummer }
        bilanz.unveraendert.sort { $0.nummer < $1.nummer }
        return (neu, bilanz)
    }

    /// „Fehlende archivieren“ nach dem Import — ihre Einträge und
    /// Mitgliedschaften bleiben (E252).
    func mitArchiviertenPersonen(_ ids: [String], jetzt: String) -> Lernendenbestand {
        ids.reduce(self) { $0.mitArchivierterPerson($1, jetzt: jetzt) }
    }

    /// „Fehlende aus der Lerngruppe nehmen“ (E368): Nur die Mitgliedschaft in der Zielgruppe geht — die
    /// Person bleibt in den Listen und in ihren anderen Gruppen.
    func ohneMitgliedschaften(_ liste: [Fehlmitgliedschaft], jetzt: String) -> Lernendenbestand {
        liste.reduce(self) { $0.ohneMitglied($1.person, ausGruppe: $1.gruppe, jetzt: jetzt) }
    }
}
