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
    /// Gleichstand Semikolon vor Komma vor Tab.
    static func trennerErkennen(_ text: String) -> Trenner {
        var bester = Trenner.semikolon
        var bestwert = 0
        for trenner in Trenner.allCases {
            let zeilen = zerlegen(text, trenner: trenner).prefix(20).filter { !($0.count == 1 && $0[0].isEmpty) }
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

    /// RFC 4180: Ein Feld in Anführungszeichen darf Trenner und Zeilenwechsel
    /// tragen, `""` ist ein Anführungszeichen. Jeder Zeilenwechsel außerhalb
    /// (CRLF, LF, CR) beendet eine Zeile; eine leere Zeile bleibt als `[""]`
    /// stehen, damit die Zeilennummern der Bilanz stimmen. Ein offenes
    /// Anführungszeichen nimmt den Rest der Datei.
    static func zerlegen(_ text: String, trenner: Trenner) -> [[String]] {
        guard !text.isEmpty else { return [] }
        let trennzeichen = Character(trenner.rawValue)
        var zeilen: [[String]] = []
        var felder: [String] = []
        var feld = ""
        var inAnfuehrung = false
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
                    feld.append(z)
                }
            } else if z == "\"" && feld.isEmpty {
                inAnfuehrung = true
            } else if z == trennzeichen {
                felder.append(feld)
                feld = ""
            } else if z.isNewline {
                felder.append(feld)
                zeilen.append(felder)
                felder = []
                feld = ""
            } else {
                feld.append(z)
            }
        }
        felder.append(feld)
        zeilen.append(felder)
        // Ein Zeilenwechsel am Ende eröffnet keine Zeile.
        if text.last?.isNewline == true, zeilen.last == [""] { zeilen.removeLast() }
        return zeilen
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
/// Klasse eine (eine Klassengruppe ohne Fach dieses Namens, sonst neu).
enum Importziel: Equatable, Sendable {
    case gruppe(String)
    case neueGruppe(String)
    case jeKlasse
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
    /// Aktive Mitglieder der Zielgruppen, die in der Datei fehlen — genannt,
    /// nie gelöscht; das Blatt bietet „archivieren“ an.
    var fehlende: [String] = []

    var kurz: String {
        "\(neu.count) neu" + (zugeordnet.isEmpty ? "" : " · \(zugeordnet.count) zugeordnet")
            + (zurueckgeholt.isEmpty ? "" : " · \(zurueckgeholt.count) zurückgeholt")
            + " · \(unveraendert.count) unverändert · \(uebergangen.count) übergangen"
    }
}

extension Lernendenbestand {

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
        func zuteilen(_ zeile: IServImport.Zeile, _ gruppe: String) {
            if let stelle = verteilung.firstIndex(where: { $0.gruppe == gruppe }) {
                verteilung[stelle].zeilen.append(zeile)
            } else {
                verteilung.append((gruppe, [zeile]))
            }
        }
        func gruppeAnlegen(_ name: String) -> String? {
            guard let angelegt = neu.mitNeuerGruppe(name: name, fach: "", art: .klasse, jetzt: jetzt) else { return nil }
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
                if let id = angelegt[schluessel]
                    ?? neu.lerngruppen.first(where: { $0.archiviert.isEmpty && $0.fach.isEmpty
                                                        && $0.name.lowercased() == schluessel })?.id {
                    angelegt[schluessel] = id
                    zuteilen(zeile, id)
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
            for zeile in zeilen {
                let inDatei = zeilen.filter { andere in
                    Lernendenbestand.gleicherName(andere.vorname, andere.nachname,
                                                  wie: Lernender(id: "", vorname: zeile.vorname, nachname: zeile.nachname,
                                                                 angelegt: "", geaendert: "", archiviert: ""))
                }
                if inDatei.count > 1 {
                    let nummern = inDatei.map { String($0.nummer) }
                    let liste = nummern.dropLast().joined(separator: ", ") + " und " + (nummern.last ?? "")
                    bilanz.uebergangen.append(.init(nummer: zeile.nummer,
                                                    grund: "Gleichnamig in der Datei (Zeilen \(liste)) — nichts geraten."))
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
            bilanz.fehlende += mitglieder.filter { $0.archiviert.isEmpty && !gefunden.contains($0.id) }.map(\.id)
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
}
