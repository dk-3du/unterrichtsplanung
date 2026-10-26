// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Die Lernendenverwaltung: die Jahresdatei (v80, E246) ───────────────────
//
// Je Schuljahr eine Datei `lernende.json`, gebunden an die Herkunft
// (`Planung.erstellt`) der Planung dieses Jahres; im Container stets ein
// Behälter (E249) — dieses Modell kennt nur den Inhalt. Flache Listen mit
// Verweisen über Kennungen (E247); was beim Lesen keinen Halt findet, wird
// verworfen und in der `Bilanz` gezählt, nie still. Fassung 1 trägt schon die
// Listen der Erfassung (2.2.0), der Leistungen, des Verhaltens und der
// Beurteilung (2.3.0, E290): In 2.0.0 sind sie leer, werden aber gelesen,
// geprüft und unverändert zurückgeschrieben.
// Reines Modell ohne AppKit — `abzug_pruefen.py` übersetzt es allein.

/// Eine Person. `angelegt` ist der Zeitpunkt der Anlage in dieser App — die
/// Importkennung (E251): beim Import der Zeitpunkt des Imports, nichts aus IServ.
struct Lernender: Identifiable, Hashable, Sendable {
    var id: String
    var vorname: String
    var nachname: String
    /// Freiwillig: der Name, mit dem die Person gerufen wird — statt des
    /// Vornamens im Sitzplan (E285). Kein Import liefert ihn; leer heißt keiner.
    var rufname: String = ""
    var angelegt: String
    var geaendert: String
    /// Zeitstempel; leer heißt: in den Listen. Archiviert verschwindet die
    /// Person aus Listen und Angeboten, ihre Einträge bleiben (E252).
    var archiviert: String

    /// „Nachname, Vorname“ — oder der eine Teil, der da ist.
    var anzeigename: String {
        if vorname.isEmpty { return nachname }
        if nachname.isEmpty { return vorname }
        return "\(nachname), \(vorname)"
    }
}

enum Lerngruppenart: String, CaseIterable, Sendable {
    case klasse, kurs
}

/// Eine Zeile der Planung, an die sich eine Lerngruppe bindet: welche Planung
/// (ihre Herkunft) und welche Klasse/welcher Kurs darin (E248).
struct Zeilenbindung: Hashable, Sendable {
    var planung: String
    var klasseId: String
}

/// Eine Zeile, mit der inzwischen eine andere aktive Lerngruppe verknüpft ist (E689) — mit deren Namen.
struct BesetzteZeile: Equatable, Sendable {
    var zeile: Zeilenbindung
    var andere: [String]
}

struct Lerngruppe: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// Steht in der Datei; gezeigt wird sie nicht mehr (E666). Ein Fach trägt eine Lerngruppe nicht — es kommt nur
    /// über die verknüpften Zeilen (E656, E665).
    var art: Lerngruppenart
    var mitglieder: [String]
    var zeilen: [Zeilenbindung]
    /// Die Skalen der Erfassung (2.2.0, E258–E260) — Schlüssel und Wert als
    /// Text. 2.0.0 deutet sie nicht, bewahrt sie aber.
    var skalen: [String: String]
    /// ISO-Tag oder leer (2.3.0, E266).
    var halbjahreswechsel: String
    var geaendert: String
    var archiviert: String

    /// Wie eine Lerngruppe überall heißt: ihr Name (E665, V7).
    var beschriftung: String { name }

    /// Name, dann Kennung — wie der Finder ordnet (E342, E665): Ziffernfolgen als Zahl,
    /// Buchstaben ohne Ansehen der Schreibung; „05G“ vor „06F-b“ vor „9b“ vor „10a“, „AG“ hinter allen
    /// Namen, die mit Ziffern beginnen. Unterscheiden sich zwei Namen nur in der Schreibung („ag“, „AG“),
    /// entscheidet sie (Z-AS5-04). Die eine Ordnung aller Listen (E343, E344); die
    /// Jahresdatei bleibt in Anlegefolge.
    static func vorgehen(_ a: Lerngruppe, _ b: Lerngruppe) -> Bool {
        let name = a.name.localizedStandardCompare(b.name)
        if name != .orderedSame { return name == .orderedAscending }
        return a.id < b.id
    }
}

/// Mitteilung an eine Lerngruppe (Rücklauf je Person, etwa ein Elternbrief),
/// Maßnahme für einzelne Personen mit Frist (E256, E272) oder Termin mit Tag
/// und freier Uhrzeit (E290). Nur die Mitteilung braucht ihre Gruppe.
enum Anliegenart: String, CaseIterable, Sendable {
    case mitteilung, massnahme, termin

    var titel: String {
        switch self {
        case .mitteilung: "Mitteilung"
        case .massnahme: "Maßnahme"
        case .termin: "Termin"
        }
    }
}

struct Anliegen: Identifiable, Hashable, Sendable {
    var id: String
    var art: Anliegenart
    var titel: String
    /// Bei einer Mitteilung Pflicht; bei Maßnahme und Termin die Gruppe, in
    /// der sie entstanden, oder leer.
    var lerngruppe: String
    var betroffene: [String]
    /// ISO-Tage; die Frist darf leer sein, der Tag eines Termins nicht.
    var datum: String
    var frist: String
    /// „07:45“ oder leer — geschrieben nur, wo gesetzt.
    var uhrzeit: String = ""
    var notiz: String
    var angelegt: String
    var geaendert: String
    /// Der Rückverweis eines Termins auf sein Vorhaben (E293): Herkunft der
    /// Planung und Kennung des Vorhabens — beide oder keins, nur am Termin.
    var planung: String = ""
    var vorhaben: String = ""
    /// Nur im Blatt, nie geschrieben (W3-03): die Zeile, in der ein Termin beim
    /// „Übernehmen“ sein Vorhaben bekommen soll. Als Teil des Stands nehmen ⌘Z
    /// und ⇧⌘Z den Wunsch mit; `terminwuensche` nimmt ihn vor dem Schreiben heraus.
    var wunschzeile: String = ""
}

/// Drei Stände (E272). Fehlt der Rücklauf einer betroffenen Person, gilt
/// `offen` — so bleibt die Datei klein.
enum Rueckmeldestand: String, CaseIterable, Sendable {
    case offen, erledigt, abgelehnt

    /// Bei einer Mitteilung „erledigt/abgelehnt“, bei einer Maßnahme
    /// „erfüllt/nicht erfüllt“, bei einem Termin „stattgefunden/abgesagt“.
    func beschriftung(fuer art: Anliegenart) -> String {
        switch (self, art) {
        case (.offen, _): "offen"
        case (.erledigt, .mitteilung): "erledigt"
        case (.erledigt, .massnahme): "erfüllt"
        case (.erledigt, .termin): "stattgefunden"
        case (.abgelehnt, .mitteilung): "abgelehnt"
        case (.abgelehnt, .massnahme): "nicht erfüllt"
        case (.abgelehnt, .termin): "abgesagt"
        }
    }
}

/// Der Stand eines Anliegens für eine Person — höchstens einer je Paar.
struct Rueckmeldung: Hashable, Sendable {
    var anliegen: String
    var lernender: String
    var stand: Rueckmeldestand
    var datum: String
    var notiz: String
    var geaendert: String
}

/// Die Arten der Erfassung (2.2.0, Roadmap a–e). Der Wert ist Text in fester
/// Form; seine Skala bestimmt 2.2.0 — 2.0.0 prüft nur Form und Länge.
enum Erfassungsart: String, CaseIterable, Sendable {
    case muendlich, test, pruefung, frei, abwesenheit
}

struct Erfassungseintrag: Identifiable, Hashable, Sendable {
    var id: String
    var lernender: String
    /// Leer: eine allgemeine Notiz zur Person (E290) — dann Art `frei`, ohne
    /// Vorhaben, ohne Planung, ohne Wert.
    var lerngruppe: String
    var planung: String
    /// Kennung eines Vorhabens oder leer.
    var vorhaben: String
    var datum: String
    var art: Erfassungsart
    var wert: String
    var notiz: String
    var angelegt: String
    var geaendert: String
}

/// Die Beurteilung je Person, Gruppe und Halbjahr (2.3.0): die Zeugnisnote,
/// gesetzt von der Lehrkraft — keine Rechnung (Roadmap, E290).
struct Beurteilung: Identifiable, Hashable, Sendable {
    var id: String
    var lernender: String
    var lerngruppe: String
    var schuljahr: String
    var halbjahr: Int
    var zeugnisnote: String
    var notiz: String
    var geaendert: String
}

/// Arbeits- und Sozialverhalten je Person, Schuljahr und Halbjahr — einmal,
/// gruppenunabhängig (E289, E290). Die Skala bestimmt 2.3.0.
struct Verhalten: Identifiable, Hashable, Sendable {
    var id: String
    var lernender: String
    var schuljahr: String
    var halbjahr: Int
    var arbeitsverhalten: String
    var sozialverhalten: String
    var notiz: String
    var geaendert: String
}

enum Leistungsart: String, CaseIterable, Sendable {
    case muendlich, schriftlich
}

/// Eine Leistungsnote je Person, Gruppe, Schuljahr und Halbjahr — beliebig
/// viele, keine Gesamtnote, keine Rechnung (E290). Das Ergebnis einer
/// Klassenarbeit oder Lernkontrolle steht hier einmal, als schriftliche
/// Leistung mit Verweis auf ihr Vorhaben.
struct Leistung: Identifiable, Hashable, Sendable {
    var id: String
    var lernender: String
    var lerngruppe: String
    var schuljahr: String
    var halbjahr: Int
    var art: Leistungsart
    var titel: String
    /// ISO-Tag oder leer.
    var datum: String
    var wert: String
    var notiz: String
    /// Herkunft der Planung und Kennung des Vorhabens — oder beide leer.
    var planung: String
    var vorhaben: String
    var angelegt: String
    var geaendert: String
}

/// Was aus einem Namen der Eingabe wurde (E273, E288).
enum Namensausgang: Equatable, Sendable {
    /// Eine neue Person, ihre Kennung.
    case neu(String)
    /// Eine Person aus einer anderen Gruppe der Jahresdatei, jetzt auch hier.
    case zugeordnet(String)
    /// Eine archivierte Person dieser Gruppe gleichen Namens — wieder in den Listen (E299).
    case zurueckgeholt(String)
    case schonDa
    /// Mehrere aktive Personen dieses Namens im Schuljahr — nichts geraten.
    case gleichnamig
    case ueberGrenze
    case leer
}

/// Der Bestand nach dem Eintragen und je Name sein Ausgang, in der Reihenfolge der Eingabe.
struct Namenseintrag: Sendable {
    let bestand: Lernendenbestand
    let ausgaenge: [Namensausgang]

    var neu: [String] { ausgaenge.compactMap { if case .neu(let id) = $0 { id } else { nil } } }
    var zugeordnet: [String] { ausgaenge.compactMap { if case .zugeordnet(let id) = $0 { id } else { nil } } }
    var zurueckgeholt: [String] { ausgaenge.compactMap { if case .zurueckgeholt(let id) = $0 { id } else { nil } } }
    var schonDa: Int { ausgaenge.filter { $0 == .schonDa }.count }
    var gleichnamig: Int { ausgaenge.filter { $0 == .gleichnamig }.count }
    var ueberGrenze: Int { ausgaenge.filter { $0 == .ueberGrenze }.count }
}

/// Der Inhalt einer Jahresdatei.
struct Lernendenbestand: Hashable, Sendable {
    /// Die Herkunft der Planung dieses Schuljahrs (`Planung.erstellt`).
    var planung: String
    /// „2026/27“.
    var schuljahr: String
    var erstellt: String
    var geaendert: String
    var lernende: [Lernender]
    var lerngruppen: [Lerngruppe]
    var anliegen: [Anliegen]
    var rueckmeldungen: [Rueckmeldung]
    var erfassung: [Erfassungseintrag]
    var beurteilung: [Beurteilung]
    var verhalten: [Verhalten] = []
    var leistungen: [Leistung] = []

    static func leer(planung: String, schuljahr: String, jetzt: String) -> Lernendenbestand {
        Lernendenbestand(planung: planung, schuljahr: schuljahr, erstellt: jetzt, geaendert: jetzt,
                         lernende: [], lerngruppen: [], anliegen: [], rueckmeldungen: [],
                         erfassung: [], beurteilung: [])
    }

    /// Das Schuljahr, in dem eine Planung beginnt: ab Juli das neue — die
    /// erste Woche eines Schuljahrs kann Ende Juli anfangen.
    static func schuljahr(fuer beginn: Tag) -> String {
        let jahr = beginn.monat >= 7 ? beginn.jahr : beginn.jahr - 1
        return String(format: "%04d/%02d", jahr, (jahr + 1) % 100)
    }

    /// Die Form eines Schuljahrs: vier Ziffern, Schrägstrich, zwei Ziffern.
    static func istSchuljahr(_ wert: String) -> Bool {
        let teile = wert.split(separator: "/", omittingEmptySubsequences: false)
        return teile.count == 2 && teile[0].count == 4 && teile[1].count == 2
            && teile.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    // ── Archivieren und Löschen (E252, E276) ──────────────────────────────

    /// Was ein Löschen mitgenommen hat — die Rückfrage nennt diese Zahlen.
    struct Loeschzahl: Equatable, Sendable {
        var personen = 0
        var gruppen = 0
        var anliegen = 0
        /// Davon Termine — die Rückfrage nennt sie eigens.
        var termine = 0
        var rueckmeldungen = 0
        /// Erfassung, Beurteilung, Verhalten und Leistungen.
        var eintraege = 0
        /// Archivierte Schuljahre — nur beim Löschen eines ganzen Jahres.
        var jahre = 0
    }

    func mitArchivierterPerson(_ id: String, jetzt: String) -> Lernendenbestand {
        var neu = self
        guard let stelle = neu.lernende.firstIndex(where: { $0.id == id }) else { return self }
        neu.lernende[stelle].archiviert = jetzt
        neu.lernende[stelle].geaendert = jetzt
        return neu
    }

    func mitZurueckgeholterPerson(_ id: String, jetzt: String) -> Lernendenbestand {
        var neu = self
        guard let stelle = neu.lernende.firstIndex(where: { $0.id == id }) else { return self }
        neu.lernende[stelle].archiviert = ""
        neu.lernende[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    /// Eine Person endgültig: ihr Datensatz, ihre Mitgliedschaften, ihre
    /// Betroffenheit, ihre Rückläufe, ihre Einträge. Eine Maßnahme oder ein
    /// Termin, die nur sie betrafen, gehen mit; eine Mitteilung bleibt für die anderen.
    func ohnePerson(_ id: String) -> (bestand: Lernendenbestand, zahl: Loeschzahl) {
        guard lernende.contains(where: { $0.id == id }) else { return (self, Loeschzahl()) }
        var neu = self
        var zahl = Loeschzahl()
        neu.lernende.removeAll { $0.id == id }
        zahl.personen = 1
        for stelle in neu.lerngruppen.indices { neu.lerngruppen[stelle].mitglieder.removeAll { $0 == id } }
        var entfallen = Set<String>()
        for stelle in neu.anliegen.indices { neu.anliegen[stelle].betroffene.removeAll { $0 == id } }
        for anliegen in neu.anliegen where anliegen.art != .mitteilung && anliegen.betroffene.isEmpty
            && self.anliegen.contains(where: { $0.id == anliegen.id && $0.betroffene.contains(id) }) {
            entfallen.insert(anliegen.id)
        }
        zahl.termine = neu.anliegen.filter { entfallen.contains($0.id) && $0.art == .termin }.count
        neu.anliegen.removeAll { entfallen.contains($0.id) }
        zahl.anliegen = entfallen.count
        let vorher = neu.rueckmeldungen.count
        neu.rueckmeldungen.removeAll { $0.lernender == id || entfallen.contains($0.anliegen) }
        zahl.rueckmeldungen = vorher - neu.rueckmeldungen.count
        let eintraege = neu.eintragszahl
        neu.erfassung.removeAll { $0.lernender == id }
        neu.beurteilung.removeAll { $0.lernender == id }
        neu.verhalten.removeAll { $0.lernender == id }
        neu.leistungen.removeAll { $0.lernender == id }
        zahl.eintraege = eintraege - neu.eintragszahl
        return (neu, zahl)
    }

    /// Eine Gruppe samt ihren Mitteilungen (mit Rückläufen) und ihren
    /// Einträgen, Leistungen und Beurteilungen. Personen bleiben; Maßnahmen
    /// und Termine bleiben ohne Gruppe — sie gehören zur Person, nicht zur
    /// Gruppe; ebenso Verhalten und Notizen ohne Gruppe.
    func ohneGruppe(_ id: String) -> (bestand: Lernendenbestand, zahl: Loeschzahl) {
        guard lerngruppen.contains(where: { $0.id == id }) else { return (self, Loeschzahl()) }
        var neu = self
        var zahl = Loeschzahl()
        neu.lerngruppen.removeAll { $0.id == id }
        zahl.gruppen = 1
        let entfallen = Set(neu.anliegen.filter { $0.art == .mitteilung && $0.lerngruppe == id }.map(\.id))
        neu.anliegen.removeAll { entfallen.contains($0.id) }
        zahl.anliegen = entfallen.count
        for stelle in neu.anliegen.indices where neu.anliegen[stelle].lerngruppe == id {
            neu.anliegen[stelle].lerngruppe = ""
        }
        let vorher = neu.rueckmeldungen.count
        neu.rueckmeldungen.removeAll { entfallen.contains($0.anliegen) }
        zahl.rueckmeldungen = vorher - neu.rueckmeldungen.count
        let eintraege = neu.eintragszahl
        neu.erfassung.removeAll { $0.lerngruppe == id }
        neu.beurteilung.removeAll { $0.lerngruppe == id }
        neu.leistungen.removeAll { $0.lerngruppe == id }
        zahl.eintraege = eintraege - neu.eintragszahl
        return (neu, zahl)
    }

    /// Ein Anliegen samt seinen Rückläufen.
    func ohneAnliegen(_ id: String) -> (bestand: Lernendenbestand, zahl: Loeschzahl) {
        guard anliegen.contains(where: { $0.id == id }) else { return (self, Loeschzahl()) }
        var neu = self
        neu.anliegen.removeAll { $0.id == id }
        let vorher = neu.rueckmeldungen.count
        neu.rueckmeldungen.removeAll { $0.anliegen == id }
        return (neu, Loeschzahl(anliegen: 1, rueckmeldungen: vorher - neu.rueckmeldungen.count))
    }

    /// Ein Eintrag der Erfassung, der Beurteilung, des Verhaltens oder der Leistungen.
    func ohneEintrag(_ id: String) -> (bestand: Lernendenbestand, zahl: Loeschzahl) {
        var neu = self
        neu.erfassung.removeAll { $0.id == id }
        neu.beurteilung.removeAll { $0.id == id }
        neu.verhalten.removeAll { $0.id == id }
        neu.leistungen.removeAll { $0.id == id }
        return (neu, Loeschzahl(eintraege: eintragszahl - neu.eintragszahl))
    }

    /// Die Einträge aller vier Listen — was die Löschzahl `eintraege` zählt.
    var eintragszahl: Int { erfassung.count + beurteilung.count + verhalten.count + leistungen.count }
}

// ── Ändern im Blatt (AP7) — reine Funktionen am Wert ─────────────────────

extension Lernendenbestand {
    /// Eine Zeile Text, wie die Datei sie trägt: ohne Steuerzeichen und
    /// Zeilenumbrüche, Leerraum zusammengezogen, gekappt.
    static func zeile(_ roh: String, _ grenze: Int) -> String {
        let woerter = Planungsdatei.ohneSteuerzeichen(roh).split(whereSeparator: \.isWhitespace)
        return String(woerter.joined(separator: " ").prefix(grenze)).trimmingCharacters(in: .whitespaces)
    }

    /// Derselbe Name (E254): Vor- und Nachname gleich, Groß/Klein und Leerraum unerheblich.
    static func gleicherName(_ vorname: String, _ nachname: String, wie person: Lernender) -> Bool {
        zeile(vorname, Kennwerte.maxLernendenname).lowercased() == zeile(person.vorname, Kennwerte.maxLernendenname).lowercased()
            && zeile(nachname, Kennwerte.maxLernendenname).lowercased() == zeile(person.nachname, Kennwerte.maxLernendenname).lowercased()
    }

    func neueKennung(_ vorsatz: String, belegt: Set<String>) -> String {
        var id = Kennung.neu(vorsatz)
        while belegt.contains(id) { id = Kennung.neu(vorsatz) }
        return id
    }

    /// Eine neue Lerngruppe — `nil` ohne Namen oder an der Grenze.
    func mitNeuerGruppe(name: String, art: Lerngruppenart, jetzt: String) -> (bestand: Lernendenbestand, id: String)? {
        let sauber = Lernendenbestand.zeile(name, Planungsdatei.maxNamenslaenge)
        guard !sauber.isEmpty, lerngruppen.count < Kennwerte.maxLerngruppen else { return nil }
        var neu = self
        let id = neueKennung("g", belegt: Set(lerngruppen.map(\.id)))
        neu.lerngruppen.append(Lerngruppe(id: id, name: sauber, art: art, mitglieder: [], zeilen: [], skalen: [:], halbjahreswechsel: "",
                                          geaendert: jetzt, archiviert: ""))
        neu.geaendert = jetzt
        return (neu, id)
    }

    /// Der Name einer Gruppe — ein leerer Name ändert nichts, derselbe auch nicht.
    func mitGruppe(_ id: String, name: String, jetzt: String) -> Lernendenbestand {
        let sauber = Lernendenbestand.zeile(name, Planungsdatei.maxNamenslaenge)
        guard !sauber.isEmpty, let stelle = lerngruppen.firstIndex(where: { $0.id == id }),
              sauber != lerngruppen[stelle].name else { return self }
        var neu = self
        neu.lerngruppen[stelle].name = sauber
        neu.lerngruppen[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    func mitArchivierterGruppe(_ id: String, jetzt: String) -> Lernendenbestand {
        guard let stelle = lerngruppen.firstIndex(where: { $0.id == id }) else { return self }
        var neu = self
        neu.lerngruppen[stelle].archiviert = jetzt
        neu.lerngruppen[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    /// Die Zeilen einer Lerngruppe unter `zeilen` (die mit Sitzplan, Z-AT15N-01), mit denen eine andere aktive verknüpft ist —
    /// je Zeile deren Namen (E689). Klassenleitung und „Weiteres“ tragen oft mehrere; dort zählt keine als besetzt.
    func besetzteZeilen(von id: String, unter zeilen: Set<Zeilenbindung>) -> [BesetzteZeile] {
        guard let g = lerngruppen.first(where: { $0.id == id }) else { return [] }
        return g.zeilen.filter(zeilen.contains).compactMap { zeile in
            let andere = gruppen(an: zeile).filter { $0.id != id }.map(\.name)
            return andere.isEmpty ? nil : BesetzteZeile(zeile: zeile, andere: andere)
        }
    }

    /// Zurückholen (E689): An Zeilen mit Sitzplan (`sitzplanzeilen`), mit denen inzwischen eine andere aktive Lerngruppe verknüpft
    /// ist, wird sie nicht wieder verknüpft — die Zeile behält die eine, die ihr Sitzplan braucht; an den übrigen wie bisher
    /// (Z-AT15N-01). Mit leerem `sitzplanzeilen` wie vor E689 — jeder Aufrufer entscheidet es ausdrücklich (Z-AT15M-04).
    func mitZurueckgeholterGruppe(_ id: String, jetzt: String, sitzplanzeilen: Set<Zeilenbindung>) -> Lernendenbestand {
        guard let stelle = lerngruppen.firstIndex(where: { $0.id == id }) else { return self }
        let besetzt = Set(besetzteZeilen(von: id, unter: sitzplanzeilen).map(\.zeile))
        var neu = self
        neu.lerngruppen[stelle].archiviert = ""
        neu.lerngruppen[stelle].zeilen.removeAll { besetzt.contains($0) }
        neu.lerngruppen[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    /// Namen in eine Gruppe — von Hand (E273) und beim Import (AP13). Je Name
    /// genau ein Ausgang: Wer dort schon mit demselben Namen steht, ist schon
    /// da; steht genau eine aktive Person dieses Namens anderswo in der
    /// Jahresdatei, wird sie zugeordnet — dieselbe Person, keine neue (E288);
    /// bei mehreren wird nichts geraten. Neue Personen tragen den Zeitpunkt als
    /// Importkennung (E251). Was über die Grenze geht, wird gezählt.
    func mitPersonen(_ namen: [Namenszeilen.Name], inGruppe gruppe: String, jetzt: String) -> Namenseintrag {
        guard let stelle = lerngruppen.firstIndex(where: { $0.id == gruppe }) else {
            return Namenseintrag(bestand: self, ausgaenge: [])
        }
        var neu = self
        var belegt = Set(lernende.map(\.id))
        var ausgaenge: [Namensausgang] = []
        for name in namen {
            let mitglieder = Set(neu.lerngruppen[stelle].mitglieder)
            let gleich = neu.lernende.filter { mitglieder.contains($0.id)
                                               && Lernendenbestand.gleicherName(name.vorname, name.nachname, wie: $0) }
            if gleich.contains(where: { $0.archiviert.isEmpty }) {
                ausgaenge.append(.schonDa)
                continue
            }
            // Archiviert in dieser Gruppe — wieder in die Listen, dieselbe Person (E299).
            if let archiviert = gleich.first {
                neu = neu.mitZurueckgeholterPerson(archiviert.id, jetzt: jetzt)
                ausgaenge.append(.zurueckgeholt(archiviert.id))
                continue
            }
            let anderswo = neu.lernende.filter { $0.archiviert.isEmpty && !mitglieder.contains($0.id)
                                                 && Lernendenbestand.gleicherName(name.vorname, name.nachname, wie: $0) }
            if anderswo.count > 1 {
                ausgaenge.append(.gleichnamig)
                continue
            }
            guard neu.lerngruppen[stelle].mitglieder.count < Kennwerte.maxMitgliederJeLerngruppe,
                  anderswo.count == 1 || neu.lernende.count < Kennwerte.maxLernende else {
                ausgaenge.append(.ueberGrenze)
                continue
            }
            if let person = anderswo.first {
                neu.lerngruppen[stelle].mitglieder.append(person.id)
                ausgaenge.append(.zugeordnet(person.id))
                continue
            }
            let vorname = Lernendenbestand.zeile(name.vorname, Kennwerte.maxLernendenname)
            let nachname = Lernendenbestand.zeile(name.nachname, Kennwerte.maxLernendenname)
            guard !vorname.isEmpty || !nachname.isEmpty else {
                ausgaenge.append(.leer)
                continue
            }
            let id = neueKennung("l", belegt: belegt)
            belegt.insert(id)
            neu.lernende.append(Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: jetzt,
                                          geaendert: jetzt, archiviert: ""))
            neu.lerngruppen[stelle].mitglieder.append(id)
            ausgaenge.append(.neu(id))
        }
        if neu.lerngruppen[stelle].mitglieder != lerngruppen[stelle].mitglieder {
            neu.lerngruppen[stelle].geaendert = jetzt
            neu.geaendert = jetzt
        }
        return Namenseintrag(bestand: neu, ausgaenge: ausgaenge)
    }

    /// Vor- und Nachname einer Person, auf Wunsch auch der Rufname (`nil`:
    /// bleibt) — ohne Vor- und Nachname ändert sich nichts, mit denselben
    /// auch nicht. Die Importkennung (`angelegt`) bleibt.
    func mitPerson(_ id: String, vorname: String, nachname: String, rufname: String? = nil,
                   jetzt: String) -> Lernendenbestand {
        let v = Lernendenbestand.zeile(vorname, Kennwerte.maxLernendenname)
        let n = Lernendenbestand.zeile(nachname, Kennwerte.maxLernendenname)
        guard !v.isEmpty || !n.isEmpty, let stelle = lernende.firstIndex(where: { $0.id == id }) else { return self }
        let r = rufname.map { Lernendenbestand.zeile($0, Kennwerte.maxLernendenname) } ?? lernende[stelle].rufname
        guard v != lernende[stelle].vorname || n != lernende[stelle].nachname || r != lernende[stelle].rufname else {
            return self
        }
        var neu = self
        neu.lernende[stelle].vorname = v
        neu.lernende[stelle].nachname = n
        neu.lernende[stelle].rufname = r
        neu.lernende[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    /// Eine Person aus einer Gruppe nehmen — sie bleibt, ihre Einträge bleiben. Mit `jetzt` gestempelt,
    /// Gruppe und Bestand, wie jede Änderung der Mitgliedschaft (v84); ohne Mitgliedschaft ändert sich nichts.
    func ohneMitglied(_ person: String, ausGruppe gruppe: String, jetzt: String? = nil) -> Lernendenbestand {
        guard let stelle = lerngruppen.firstIndex(where: { $0.id == gruppe }),
              lerngruppen[stelle].mitglieder.contains(person) else { return self }
        var neu = self
        neu.lerngruppen[stelle].mitglieder.removeAll { $0 == person }
        if let jetzt {
            neu.lerngruppen[stelle].geaendert = jetzt
            neu.geaendert = jetzt
        }
        return neu
    }

    // ── Mitgliedschaft per Auswahl (v84, E365, H/I) ───────────────────────

    /// Voll ist eine Gruppe mit `Kennwerte.maxMitgliederJeLerngruppe` Mitgliedern — archivierte zählen mit,
    /// wie bei `mitPersonen` (E369).
    func istVoll(_ gruppe: String) -> Bool {
        guard let g = lerngruppen.first(where: { $0.id == gruppe }) else { return false }
        return g.mitglieder.count >= Kennwerte.maxMitgliederJeLerngruppe
    }

    /// Eine Person per Kennung in eine Gruppe aufnehmen — auch bei Gleichnamigen. `nil`: Person oder Gruppe
    /// unbekannt oder archiviert, oder die Gruppe ist voll (E369). Schon Mitglied: unverändert.
    func mitMitglied(_ person: String, inGruppe gruppe: String, jetzt: String) -> Lernendenbestand? {
        guard lernende.contains(where: { $0.id == person && $0.archiviert.isEmpty }),
              let stelle = lerngruppen.firstIndex(where: { $0.id == gruppe && $0.archiviert.isEmpty }) else { return nil }
        if lerngruppen[stelle].mitglieder.contains(person) { return self }
        guard !istVoll(gruppe) else { return nil }
        var neu = self
        neu.lerngruppen[stelle].mitglieder.append(person)
        neu.lerngruppen[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    /// Umziehen in einem Schritt: in `nach` aufnehmen, aus `von` nehmen. Mitteilungen und Rückläufe von `von`
    /// bleiben (E366). `nil`: Die Person steht nicht in `von`, `von` ist `nach`, oder die Aufnahme scheitert —
    /// dann bleibt alles.
    func mitUmzug(_ person: String, von: String, nach: String, jetzt: String) -> Lernendenbestand? {
        guard von != nach, lerngruppen.first(where: { $0.id == von })?.mitglieder.contains(person) == true,
              let aufgenommen = mitMitglied(person, inGruppe: nach, jetzt: jetzt) else { return nil }
        return aufgenommen.ohneMitglied(person, ausGruppe: von, jetzt: jetzt)
    }

    /// Wer seit `vorher` eine Lerngruppe verlassen hat (E367) — je Gruppe, die es in beiden Ständen gibt, die
    /// Personen, die vorher Mitglied waren und es nicht mehr sind. Gelöschte Personen nicht: Für sie gilt
    /// E304 (Bindung lösen, der Name bleibt).
    static func verlasseneMitgliedschaften(vorher: Lernendenbestand,
                                           nachher: Lernendenbestand) -> [String: [String]] {
        let personen = Set(nachher.lernende.map(\.id))
        var ergebnis: [String: [String]] = [:]
        for alt in vorher.lerngruppen {
            guard let neu = nachher.lerngruppen.first(where: { $0.id == alt.id }) else { continue }
            let bleiben = Set(neu.mitglieder)
            let gegangen = alt.mitglieder.filter { !bleiben.contains($0) && personen.contains($0) }
            if !gegangen.isEmpty { ergebnis[alt.id] = gegangen }
        }
        return ergebnis
    }

    /// Die Namen am Tisch, die mit dem Stand wechseln (E390): je Person, deren Name im Sitzplan
    /// (`Lernendenverzeichnis.sitzplatzname`) sich geändert hat, der alte und der neue — gelöschte nicht.
    static func tischnamenwechsel(vorher: Lernendenbestand,
                                  nachher: Lernendenbestand) -> [String: Sitzplan.Namenswechsel] {
        var alt: [String: Lernender] = [:]
        for p in vorher.lernende { alt[p.id] = p }
        var ergebnis: [String: Sitzplan.Namenswechsel] = [:]
        for p in nachher.lernende {
            guard let a = alt[p.id] else { continue }
            let vorName = Lernendenverzeichnis.sitzplatzname(a)
            let nachName = Lernendenverzeichnis.sitzplatzname(p)
            if vorName != nachName { ergebnis[p.id] = Sitzplan.Namenswechsel(alt: vorName, neu: nachName) }
        }
        return ergebnis
    }
}

// ── Bindung an Zeilen der Planung (AP10, E248) ───────────────────────────

extension Lernendenbestand {
    /// Die Lerngruppen an einer Zeile, in der Folge der Listen — eine Zeile kann mehrere tragen (E670); eine
    /// archivierte zeigt keine Zeile.
    func gruppen(an zeile: Zeilenbindung) -> [Lerngruppe] {
        lerngruppen.filter { $0.archiviert.isEmpty && $0.zeilen.contains(zeile) }.sorted(by: Lerngruppe.vorgehen)
    }

    /// Die eine Lerngruppe an einer Zeile — `nil` ohne oder bei mehreren (E674: dann gibt die Zeile keine vor).
    func gruppe(an zeile: Zeilenbindung) -> Lerngruppe? {
        let gruppen = gruppen(an: zeile)
        return gruppen.count == 1 ? gruppen[0] : nil
    }

    /// Eine Lerngruppe an eine Zeile binden — sie kommt hinzu; eine Zeile kann mehrere tragen, keiner anderen wird
    /// etwas genommen (E670). Höchstens 20 Zeilen je Lerngruppe.
    func mitBindung(_ gruppe: String, an zeile: Zeilenbindung, jetzt: String) -> Lernendenbestand {
        guard let stelle = lerngruppen.firstIndex(where: { $0.id == gruppe }),
              !lerngruppen[stelle].zeilen.contains(zeile),
              lerngruppen[stelle].zeilen.count < Lernendendatei.maxZeilenJeGruppe else { return self }
        var neu = self
        neu.lerngruppen[stelle].zeilen.append(zeile)
        neu.lerngruppen[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    /// Eine Lerngruppe von einer Zeile lösen — die übrigen an der Zeile bleiben (E670).
    func ohneBindung(_ gruppe: String, an zeile: Zeilenbindung, jetzt: String) -> Lernendenbestand {
        guard let stelle = lerngruppen.firstIndex(where: { $0.id == gruppe && $0.zeilen.contains(zeile) }) else { return self }
        var neu = self
        neu.lerngruppen[stelle].zeilen.removeAll { $0 == zeile }
        neu.lerngruppen[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    /// Alle Lerngruppen von einer Zeile lösen.
    func ohneBindung(_ zeile: Zeilenbindung, jetzt: String) -> Lernendenbestand {
        guard lerngruppen.contains(where: { $0.zeilen.contains(zeile) }) else { return self }
        var neu = self
        for stelle in neu.lerngruppen.indices where neu.lerngruppen[stelle].zeilen.contains(zeile) {
            neu.lerngruppen[stelle].zeilen.removeAll { $0 == zeile }
            neu.lerngruppen[stelle].geaendert = jetzt
        }
        neu.geaendert = jetzt
        return neu
    }

    /// Bindung nach Namen (E352, E521): je Lerngruppe aus `gruppen` alle Unterrichtszeilen gleichen Namens — Groß/Klein
    /// und Leerraum am Rand unerheblich, das Fach der Zeile beliebig —, aber nur Zeilen ohne aktive Lerngruppe und nie
    /// Sonderzeilen: Eine Zeile, die schon eine trägt, bleibt, wie sie ist — der Import fügt keine hinzu (Lesung AT9a,
    /// Abschnitt 6); weitere bindet nur die Hand (⌘K, E670). Eine an einer archivierten gilt als frei (E527).
    func mitBindungenNachNamen(_ gruppen: [String], zeilen: [Klasse], planung: String,
                               jetzt: String) -> (bestand: Lernendenbestand, bindung: Namensbindung) {
        var neu = self
        var bindung = Namensbindung()
        for id in gruppen {
            guard let gruppe = neu.lerngruppen.first(where: { $0.id == id && $0.archiviert.isEmpty }) else { continue }
            let name = gruppe.name.trimmingCharacters(in: .whitespaces).lowercased()
            var getroffen = false
            for zeile in zeilen where !zeile.istSonderzeile
                && zeile.name.trimmingCharacters(in: .whitespaces).lowercased() == name {
                let ziel = Zeilenbindung(planung: planung, klasseId: zeile.id)
                guard neu.gruppen(an: ziel).isEmpty else { continue }
                let vorher = neu
                neu = neu.mitBindung(id, an: ziel, jetzt: jetzt)
                // Höchstens 20 Zeilen je Gruppe — darüber bindet `mitBindung` nicht.
                if neu != vorher { getroffen = true }
            }
            if getroffen { bindung.gebunden += 1 } else { bindung.ohneZeile += 1 }
        }
        return (neu, bindung)
    }
}

// ── Kopf der Lerngruppe: Zeilen wählen, Zusammenführen (AT9a-2; E667, E669, E670, E672) ──

extension Lernendenbestand {
    /// „Zeilen wählen …“ (E669): Die Zeilen der Lerngruppe in dieser Planung sind danach genau die gewählten — nur Zeilen,
    /// die eine Lerngruppe tragen können (nicht Vertretungen, E161). Bindungen an Zeilen, die die Planung nicht führt,
    /// bleiben; behaltene in ihrer Folge, neue in der Folge der Planung dahinter, höchstens 20. Keiner anderen
    /// Lerngruppe wird etwas genommen (E670). Eine archivierte bekommt keine (Z-AT9a2-05).
    func mitZeilen(_ gruppe: String, _ gewaehlt: Set<String>, zeilen: [Klasse], planung: String, jetzt: String) -> Lernendenbestand {
        guard let stelle = lerngruppen.firstIndex(where: { $0.id == gruppe && $0.archiviert.isEmpty }) else { return self }
        let hier = Set(zeilen.map { Zeilenbindung(planung: planung, klasseId: $0.id) })
        let ziel = zeilen.filter { $0.erlaubt(.verwaltung) && gewaehlt.contains($0.id) }
            .map { Zeilenbindung(planung: planung, klasseId: $0.id) }
        let alt = lerngruppen[stelle].zeilen
        var neu = alt.filter { !hier.contains($0) || ziel.contains($0) }
        for z in ziel where !neu.contains(z) && neu.count < Lernendendatei.maxZeilenJeGruppe { neu.append(z) }
        guard neu != alt else { return self }
        var b = self
        b.lerngruppen[stelle].zeilen = neu
        b.lerngruppen[stelle].geaendert = jetzt
        b.geaendert = jetzt
        return b
    }

    /// Zwei gleichnamige zusammenführen (E667, E672): Mitglieder und Zeilen der anderen gehen auf `gruppe` über (die eigenen
    /// zuerst), ebenso alle Anliegen, Einträge, Leistungen und Beurteilungen mit ihr; die andere wird archiviert — mit ihrer
    /// Mitgliederliste, ohne Zeilen. Über 40 Mitglieder oder 20 Zeilen geht es nicht: dann der Grund, und alles bleibt.
    /// Beide müssen aktiv sein.
    func mitZusammenfuehrung(_ andere: String, in gruppe: String, jetzt: String) -> (bestand: Lernendenbestand, grund: String?) {
        guard andere != gruppe,
              let a = lerngruppen.firstIndex(where: { $0.id == gruppe && $0.archiviert.isEmpty }),
              let b = lerngruppen.firstIndex(where: { $0.id == andere && $0.archiviert.isEmpty }) else { return (self, nil) }
        let eigene = lerngruppen[a]
        let mitglieder = eigene.mitglieder + lerngruppen[b].mitglieder.filter { !eigene.mitglieder.contains($0) }
        let zeilen = eigene.zeilen + lerngruppen[b].zeilen.filter { !eigene.zeilen.contains($0) }
        if mitglieder.count > Kennwerte.maxMitgliederJeLerngruppe {
            // Archivierte belegen einen Platz wie in der Jahresdatei (E369) — die Meldung nennt sie, sonst ginge sie nicht auf.
            let archivierte = Set(lernende.filter { !$0.archiviert.isEmpty }.map(\.id))
            let davon = mitglieder.count { archivierte.contains($0) }
            return (self, "Zusammen wären es \(mitglieder.count) Mitglieder" + (davon > 0 ? ", davon \(davon) archiviert" : "")
                    + " — höchstens \(Kennwerte.maxMitgliederJeLerngruppe) je Lerngruppe.")
        }
        if zeilen.count > Lernendendatei.maxZeilenJeGruppe {
            return (self, "Zusammen wären es \(zeilen.count) Zeilen — höchstens \(Lernendendatei.maxZeilenJeGruppe) je Lerngruppe.")
        }
        var neu = self
        neu.lerngruppen[a].mitglieder = mitglieder
        neu.lerngruppen[a].zeilen = zeilen
        neu.lerngruppen[a].geaendert = jetzt
        neu.lerngruppen[b].zeilen = []
        neu.lerngruppen[b].archiviert = jetzt
        neu.lerngruppen[b].geaendert = jetzt
        for i in neu.anliegen.indices where neu.anliegen[i].lerngruppe == andere { neu.anliegen[i].lerngruppe = gruppe }
        for i in neu.erfassung.indices where neu.erfassung[i].lerngruppe == andere { neu.erfassung[i].lerngruppe = gruppe }
        for i in neu.beurteilung.indices where neu.beurteilung[i].lerngruppe == andere { neu.beurteilung[i].lerngruppe = gruppe }
        for i in neu.leistungen.indices where neu.leistungen[i].lerngruppe == andere { neu.leistungen[i].lerngruppe = gruppe }
        neu.geaendert = jetzt
        return (neu, nil)
    }
}

// ── Anliegen im Blatt (AP8) — reine Funktionen am Wert ───────────────────

extension Lernendenbestand {
    /// Ein ISO-Tag, wie ihn der Leser nimmt — sonst leer.
    static func tagOderLeer(_ wert: String) -> String { Tag(iso: wert) != nil ? wert : "" }

    /// Eine Uhrzeit in der Form der Datei: „7.30“ und „7:30“ werden „07:30“;
    /// leer bleibt leer, alles andere ist keine (`nil`).
    static func uhrzeit(_ roh: String) -> String? {
        let text = roh.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return "" }
        let teile = text.split(separator: text.contains(":") ? ":" : ".", omittingEmptySubsequences: false)
        guard teile.count == 2, (1...2).contains(teile[0].count), teile[1].count == 2,
              teile.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let stunde = Int(teile[0]), let minute = Int(teile[1]), stunde < 24, minute < 60 else { return nil }
        return String(format: "%02d:%02d", stunde, minute)
    }

    /// Eine Notiz, wie sie die Datei trägt: Absätze bleiben, Steuerzeichen nicht, gekappt.
    static func notiztext(_ roh: String) -> String {
        String(Planungsdatei.ohneSteuerzeichen(roh).trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Lernendendatei.maxNotiz)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Eine Mitteilung an eine Lerngruppe, eine Maßnahme (E272) oder ein
    /// Termin (E290) — `nil` ohne Titel, eine Mitteilung ohne ihre Gruppe, ein
    /// Termin ohne Tag oder an der Grenze. Betroffen ist nur, wen es gibt,
    /// jede Person einmal; eine Uhrzeit ohne lesbare Form bleibt leer.
    func mitNeuemAnliegen(_ art: Anliegenart, titel: String, lerngruppe: String, betroffene: [String],
                          datum: String, frist: String, uhrzeit: String = "",
                          jetzt: String) -> (bestand: Lernendenbestand, id: String)? {
        let sauber = Lernendenbestand.zeile(titel, Lernendendatei.maxTitel)
        let gruppeDa = lerngruppen.contains { $0.id == lerngruppe }
        guard !sauber.isEmpty, anliegen.count < Lernendendatei.maxAnliegen, art != .mitteilung || gruppeDa,
              art != .termin || Tag(iso: datum) != nil else { return nil }
        let bekannt = Set(lernende.map(\.id))
        var gesehen = Set<String>()
        let liste = betroffene.filter { bekannt.contains($0) && gesehen.insert($0).inserted }
            .prefix(Kennwerte.maxMitgliederJeLerngruppe)
        var neu = self
        let id = neueKennung("m", belegt: Set(anliegen.map(\.id)))
        neu.anliegen.append(Anliegen(id: id, art: art, titel: sauber, lerngruppe: gruppeDa ? lerngruppe : "",
                                     betroffene: Array(liste), datum: Lernendenbestand.tagOderLeer(datum),
                                     frist: Lernendenbestand.tagOderLeer(frist),
                                     uhrzeit: Lernendenbestand.uhrzeit(uhrzeit) ?? "", notiz: "",
                                     angelegt: jetzt, geaendert: jetzt))
        neu.geaendert = jetzt
        return (neu, id)
    }

    /// Titel, Tag, Frist, Notiz, auf Wunsch die Uhrzeit (`nil`: bleibt) — ein
    /// leerer Titel ändert nichts, ein Termin ohne Tag auch nicht, dieselben
    /// Werte auch nicht.
    func mitAnliegen(_ id: String, titel: String, datum: String, frist: String, notiz: String,
                     uhrzeit: String? = nil, jetzt: String) -> Lernendenbestand {
        let t = Lernendenbestand.zeile(titel, Lernendendatei.maxTitel)
        guard !t.isEmpty, let stelle = anliegen.firstIndex(where: { $0.id == id }) else { return self }
        let d = Lernendenbestand.tagOderLeer(datum)
        let f = Lernendenbestand.tagOderLeer(frist)
        let n = Lernendenbestand.notiztext(notiz)
        let alt = anliegen[stelle]
        let u = uhrzeit.map { Lernendenbestand.uhrzeit($0) ?? "" } ?? alt.uhrzeit
        guard alt.art != .termin || !d.isEmpty,
              t != alt.titel || d != alt.datum || f != alt.frist || n != alt.notiz || u != alt.uhrzeit else { return self }
        var neu = self
        neu.anliegen[stelle].titel = t
        neu.anliegen[stelle].datum = d
        neu.anliegen[stelle].frist = f
        neu.anliegen[stelle].uhrzeit = u
        neu.anliegen[stelle].notiz = n
        neu.anliegen[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    /// Der Wunsch des Blatts an einem Termin (W3-03): `zeile` nil nimmt ihn zurück.
    func mitTerminwunsch(_ id: String, zeile: String?) -> Lernendenbestand {
        guard let stelle = anliegen.firstIndex(where: { $0.id == id && $0.art == .termin }) else { return self }
        var neu = self
        neu.anliegen[stelle].wunschzeile = zeile ?? ""
        return neu
    }

    /// Die Wünsche des Blatts (Kennung → Zeile) und der Stand ohne sie — so, wie er geschrieben wird.
    var terminwuensche: (wuensche: [String: String], bestand: Lernendenbestand) {
        var wuensche: [String: String] = [:]
        var ohne = self
        for stelle in ohne.anliegen.indices where !ohne.anliegen[stelle].wunschzeile.isEmpty {
            wuensche[ohne.anliegen[stelle].id] = ohne.anliegen[stelle].wunschzeile
            ohne.anliegen[stelle].wunschzeile = ""
        }
        return (wuensche, ohne)
    }

    /// Eine Person in ein Anliegen aufnehmen oder herausnehmen — wer
    /// herausgeht, verliert seinen Rücklauf.
    func mitBetroffenem(_ anliegenId: String, _ person: String, _ betroffen: Bool, jetzt: String) -> Lernendenbestand {
        guard let stelle = anliegen.firstIndex(where: { $0.id == anliegenId }),
              lernende.contains(where: { $0.id == person }),
              anliegen[stelle].betroffene.contains(person) != betroffen,
              !betroffen || anliegen[stelle].betroffene.count < Kennwerte.maxMitgliederJeLerngruppe else { return self }
        var neu = self
        if betroffen {
            neu.anliegen[stelle].betroffene.append(person)
        } else {
            neu.anliegen[stelle].betroffene.removeAll { $0 == person }
            neu.rueckmeldungen.removeAll { $0.anliegen == anliegenId && $0.lernender == person }
        }
        neu.anliegen[stelle].geaendert = jetzt
        neu.geaendert = jetzt
        return neu
    }

    /// Der Rücklauf einer Person (E272). „Offen“ ohne Notiz ist kein Eintrag —
    /// ohne Rücklauf gilt „offen“, so bleibt die Datei klein.
    func mitRuecklauf(_ anliegenId: String, _ person: String, stand: Rueckmeldestand, datum: String, notiz: String,
                      jetzt: String) -> Lernendenbestand {
        guard anliegen.first(where: { $0.id == anliegenId })?.betroffene.contains(person) == true else { return self }
        let d = Lernendenbestand.tagOderLeer(datum)
        let n = Lernendenbestand.notiztext(notiz)
        let stelle = rueckmeldungen.firstIndex { $0.anliegen == anliegenId && $0.lernender == person }
        let eintrag = Rueckmeldung(anliegen: anliegenId, lernender: person, stand: stand, datum: d, notiz: n, geaendert: jetzt)
        var neu = self
        if stand == .offen && n.isEmpty {
            guard let stelle else { return self }
            neu.rueckmeldungen.remove(at: stelle)
        } else if let stelle {
            let alt = rueckmeldungen[stelle]
            guard alt.stand != stand || alt.datum != d || alt.notiz != n else { return self }
            neu.rueckmeldungen[stelle] = eintrag
        } else {
            guard rueckmeldungen.count < Lernendendatei.maxRueckmeldungen else { return self }
            neu.rueckmeldungen.append(eintrag)
        }
        neu.geaendert = jetzt
        return neu
    }
}

// ── Die Datei ─────────────────────────────────────────────────────────────

/// Die Datei `lernende.json` — gelesen mit derselben Vorsicht wie die
/// Sitzpläne: Typen geprüft, Texte bereinigt und gekappt, Kennungen ersetzt,
/// Waisen verworfen, Grenzen gekappt; geschrieben kanonisch. Was das Lesen
/// wegnahm oder änderte, steht in der `Bilanz`; der Dienst meldet Verluste
/// und ersetzte Kennungen und bewahrt das Original.
enum Lernendendatei {
    static let typ = "unterrichtsplanung-lernende"
    static let version = 1
    /// Eine Jahresdatei wiegt bei vollen Listen einige Megabyte; über 16 MB
    /// wird sie weder gelesen noch geschrieben. Einen Hinweis davor bringt die
    /// Fassung, die sie wachsen lässt (Erfassung, 2.2.0; E336).
    static let hoechstgroesse = 16 * 1024 * 1024
    // Grenzen je Schuljahr — eigene Festwerte, die Ansicht kennt sie nicht.
    static let maxAnliegen = 2_000
    static let maxRueckmeldungen = 60_000
    static let maxErfassung = 30_000
    static let maxBeurteilungen = 5_000
    /// Zwei Halbjahre je Person.
    static let maxVerhalten = 2 * Kennwerte.maxLernende
    static let maxLeistungen = 30_000
    static let maxTitel = 200
    static let maxNotiz = 2_000
    static let maxWert = 32
    static let maxZeilenJeGruppe = 20
    static let maxSkalen = 16

    struct Fehler: LocalizedError, Sendable {
        enum Art: Sendable { case beschaedigt, neuereFassung }
        let art: Art
        let text: String
        var errorDescription: String? { text }
    }

    /// Was das Lesen bereinigt oder verworfen hat. `verlust`: Etwas ist weg,
    /// gekürzt oder hat seinen Bezug verloren — gemeldet, das Original
    /// bewahrt. `festzuschreiben`: Kennungen sind ersetzt, zufällig — jedes
    /// Lesen gäbe neue; gemeldet, das Original bewahrt, die Datei einmal
    /// geschrieben (B93, E419). Das Übrige ist Normierung.
    struct Bilanz: Equatable, Sendable {
        var verworfeneLernende = 0
        var verworfeneGruppen = 0
        var verworfeneMitglieder = 0
        var verworfeneZeilen = 0
        var verworfeneAnliegen = 0
        var verworfeneBetroffene = 0
        var verworfeneRueckmeldungen = 0
        var verworfeneEintraege = 0
        var gekuerzteTexte = 0
        /// Ein Verweis, der ins Leere zeigte, wurde geleert — die Herkunft der
        /// Planung, die Gruppe einer Maßnahme.
        var bereinigteBezuege = 0
        var verworfeneFelder = 0
        var ersetzteKennungen = 0
        var bereinigteStempel = 0
        var bereinigteTage = 0

        var verlust: Bool {
            verworfeneLernende + verworfeneGruppen + verworfeneMitglieder + verworfeneZeilen
                + verworfeneAnliegen + verworfeneBetroffene + verworfeneRueckmeldungen + verworfeneEintraege
                + gekuerzteTexte + bereinigteBezuege + verworfeneFelder > 0
        }
        var festzuschreiben: Bool { ersetzteKennungen > 0 }
        var istLeer: Bool { !verlust && ersetzteKennungen + bereinigteStempel + bereinigteTage == 0 }

        var beschreibung: String {
            var teile: [String] = []
            func satz(_ zahl: Int, _ eins: String, _ mehr: String) {
                if zahl == 1 { teile.append("1 " + eins) } else if zahl > 1 { teile.append("\(zahl) " + mehr) }
            }
            satz(verworfeneLernende, "Person übergangen", "Personen übergangen")
            satz(verworfeneGruppen, "Lerngruppe übergangen", "Lerngruppen übergangen")
            satz(verworfeneMitglieder, "Mitgliedschaft übergangen", "Mitgliedschaften übergangen")
            satz(verworfeneZeilen, "Bindung an eine Zeile übergangen", "Bindungen an Zeilen übergangen")
            satz(verworfeneAnliegen, "Anliegen übergangen", "Anliegen übergangen")
            satz(verworfeneBetroffene, "Betroffene übergangen", "Betroffene übergangen")
            satz(verworfeneRueckmeldungen, "Rücklauf übergangen", "Rückläufe übergangen")
            satz(verworfeneEintraege, "Eintrag übergangen", "Einträge übergangen")
            satz(gekuerzteTexte, "Text gekürzt", "Texte gekürzt")
            satz(bereinigteBezuege, "Bezug geleert", "Bezüge geleert")
            satz(verworfeneFelder, "Feld ohne lesbare Form übergangen", "Felder ohne lesbare Form übergangen")
            satz(ersetzteKennungen, "Kennung ersetzt", "Kennungen ersetzt")
            satz(bereinigteStempel, "Zeitstempel geleert", "Zeitstempel geleert")
            satz(bereinigteTage, "Datum geleert", "Daten geleert")
            return teile.joined(separator: ", ")
        }
    }

    static func lesen(_ daten: Data) throws -> Lernendenbestand {
        try lesenMitBilanz(daten).bestand
    }

    static func lesenMitBilanz(_ daten: Data) throws -> (bestand: Lernendenbestand, bilanz: Bilanz) {
        guard daten.count <= hoechstgroesse else {
            throw Fehler(art: .beschaedigt, text: "Die Lernendendatei ist größer als 16 MB.")
        }
        guard let objekt = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any] else {
            throw Fehler(art: .beschaedigt, text: "Die Lernendendatei ist kein lesbares JSON.")
        }
        return try ausObjektMitBilanz(objekt)
    }

    /// Aus dem Objekt, wie es auch im Archiv steht.
    static func ausObjektMitBilanz(_ objekt: [String: Any]) throws -> (bestand: Lernendenbestand, bilanz: Bilanz) {
        guard objekt["typ"] as? String == typ else {
            throw Fehler(art: .beschaedigt, text: "Die Lernendendatei ist beschädigt.")
        }
        guard let fassung = Planungsdatei.ganzzahl(objekt["version"]), fassung >= 1 else {
            throw Fehler(art: .beschaedigt, text: "Die Lernendendatei trägt keine Fassungsnummer.")
        }
        guard fassung <= version else {
            throw Fehler(art: .neuereFassung,
                         text: "Die Lernendendatei stammt aus einer neueren Fassung der App (Fassung "
                             + "\(fassung)) — bitte die App aktualisieren.")
        }
        var leser = Leser()
        let bestand = try leser.bestand(objekt)
        return (bestand, leser.bilanz)
    }

    static func schreiben(_ bestand: Lernendenbestand) throws -> Data {
        try JSONSerialization.data(withJSONObject: alsObjekt(bestand), options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Der Dateiname, den die Dialoge vorschlagen: „Lernende 2026-27.json“.
    static func exportName(schuljahr: String, endung: String) -> String {
        "Lernende \(schuljahr.replacingOccurrences(of: "/", with: "-")).\(endung)"
    }

    /// Die Form der CSV-Datei (E257): UTF-8 mit BOM, Semikolon, CRLF — eine
    /// Zeile je aktiver Person in der Ordnung des Verzeichnisses, mit Rufname
    /// und den aktiven Lerngruppen. Felder mit Semikolon oder Anführungszeichen
    /// stehen in Anführungszeichen.
    static func csv(_ bestand: Lernendenbestand) -> Data {
        func feld(_ text: String) -> String {
            guard text.contains(where: { $0 == ";" || $0 == "\"" || $0.isNewline }) else { return text }
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let verzeichnis = Lernendenverzeichnis(bestand)
        var zeilen = ["Nachname;Vorname;Rufname;Lerngruppen"]
        for p in verzeichnis.alle {
            let gruppen = verzeichnis.gruppen(von: p.id).filter { $0.archiviert.isEmpty }.map(\.beschriftung)
            zeilen.append([p.nachname, p.vorname, p.rufname, gruppen.joined(separator: ", ")].map(feld).joined(separator: ";"))
        }
        return Data([0xEF, 0xBB, 0xBF]) + Data((zeilen.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func alsObjekt(_ b: Lernendenbestand) -> [String: Any] {
        [
            "typ": typ, "version": version,
            "planung": b.planung, "schuljahr": b.schuljahr, "erstellt": b.erstellt, "geaendert": b.geaendert,
            "lernende": b.lernende.map { l -> [String: Any] in
                var person: [String: Any] = ["id": l.id, "vorname": l.vorname, "nachname": l.nachname,
                                             "angelegt": l.angelegt, "geaendert": l.geaendert, "archiviert": l.archiviert]
                // Nur, wo gesetzt (E285) — wie `lernender` am Tisch.
                if !l.rufname.isEmpty { person["rufname"] = l.rufname }
                return person
            },
            // Das Fach steht leer: 2.0.3 liest den Schlüssel, eine Lerngruppe trägt keins (E665).
            "lerngruppen": b.lerngruppen.map { g -> [String: Any] in
                ["id": g.id, "name": g.name, "fach": "", "art": g.art.rawValue, "mitglieder": g.mitglieder,
                 "zeilen": g.zeilen.map { ["planung": $0.planung, "klasseId": $0.klasseId] },
                 "skalen": g.skalen, "halbjahreswechsel": g.halbjahreswechsel,
                 "geaendert": g.geaendert, "archiviert": g.archiviert]
            },
            "anliegen": b.anliegen.map { a -> [String: Any] in
                var anliegen: [String: Any] = ["id": a.id, "art": a.art.rawValue, "titel": a.titel,
                                               "lerngruppe": a.lerngruppe, "betroffene": a.betroffene,
                                               "datum": a.datum, "frist": a.frist, "notiz": a.notiz,
                                               "angelegt": a.angelegt, "geaendert": a.geaendert]
                // Nur, wo gesetzt — wie der Rufname.
                if !a.uhrzeit.isEmpty { anliegen["uhrzeit"] = a.uhrzeit }
                if !a.vorhaben.isEmpty {
                    anliegen["planung"] = a.planung
                    anliegen["vorhaben"] = a.vorhaben
                }
                return anliegen
            },
            "rueckmeldungen": b.rueckmeldungen.map { r -> [String: Any] in
                ["anliegen": r.anliegen, "lernender": r.lernender, "stand": r.stand.rawValue,
                 "datum": r.datum, "notiz": r.notiz, "geaendert": r.geaendert]
            },
            "erfassung": b.erfassung.map { e -> [String: Any] in
                ["id": e.id, "lernender": e.lernender, "lerngruppe": e.lerngruppe, "planung": e.planung,
                 "vorhaben": e.vorhaben, "datum": e.datum, "art": e.art.rawValue, "wert": e.wert,
                 "notiz": e.notiz, "angelegt": e.angelegt, "geaendert": e.geaendert]
            },
            "beurteilung": b.beurteilung.map { u -> [String: Any] in
                ["id": u.id, "lernender": u.lernender, "lerngruppe": u.lerngruppe, "schuljahr": u.schuljahr,
                 "halbjahr": u.halbjahr, "zeugnisnote": u.zeugnisnote, "notiz": u.notiz, "geaendert": u.geaendert]
            },
            "verhalten": b.verhalten.map { v -> [String: Any] in
                ["id": v.id, "lernender": v.lernender, "schuljahr": v.schuljahr, "halbjahr": v.halbjahr,
                 "arbeitsverhalten": v.arbeitsverhalten, "sozialverhalten": v.sozialverhalten,
                 "notiz": v.notiz, "geaendert": v.geaendert]
            },
            "leistungen": b.leistungen.map { n -> [String: Any] in
                ["id": n.id, "lernender": n.lernender, "lerngruppe": n.lerngruppe, "schuljahr": n.schuljahr,
                 "halbjahr": n.halbjahr, "art": n.art.rawValue, "titel": n.titel, "datum": n.datum, "wert": n.wert,
                 "notiz": n.notiz, "planung": n.planung, "vorhaben": n.vorhaben,
                 "angelegt": n.angelegt, "geaendert": n.geaendert]
            },
        ]
    }

    // ── Der Leser ─────────────────────────────────────────────────────────

    /// Liest in der Reihenfolge der Verweise: Personen, Gruppen, Anliegen,
    /// Rückläufe, Einträge, Verhalten, Leistungen — so kennt jede Liste die,
    /// auf die sie zeigt.
    private struct Leser {
        var bilanz = Bilanz()

        /// Eine Liste: Fehlt sie, ist sie leer; ist sie keine, ist die Datei beschädigt.
        func liste(_ wert: Any?, _ name: String) throws -> [Any] {
            switch wert {
            case nil: return []
            case let l as [Any]: return l
            default: throw Fehler(art: .beschaedigt, text: "Die Lernendendatei ist beschädigt („\(name)“).")
            }
        }

        /// Über der Grenze: gekappt und gezählt.
        func gekappt(_ eintraege: [Any], _ grenze: Int, _ zaehler: inout Int) -> ArraySlice<Any> {
            if eintraege.count > grenze { zaehler += eintraege.count - grenze }
            return eintraege.prefix(grenze)
        }

        /// Eine Zeile Text: ohne Steuerzeichen und Zeilenumbrüche, gekappt.
        mutating func zeile(_ wert: Any?, _ grenze: Int) -> String {
            kappen(Planungsdatei.einzeilig(Planungsdatei.ohneSteuerzeichen(Planungsdatei.text(wert))), grenze)
        }

        /// Eine Notiz: Absätze bleiben, Steuerzeichen nicht.
        mutating func notiz(_ wert: Any?) -> String {
            kappen(Planungsdatei.ohneSteuerzeichen(Planungsdatei.text(wert))
                .trimmingCharacters(in: .whitespacesAndNewlines), maxNotiz)
        }

        mutating func kappen(_ text: String, _ grenze: Int) -> String {
            guard text.count > grenze else { return text }
            bilanz.gekuerzteTexte += 1
            return String(text.prefix(grenze)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        mutating func stempel(_ wert: Any?) -> String {
            let text = Planungsdatei.text(wert)
            if text.isEmpty || Zeitrechnung.istZeitstempel(text) { return text }
            bilanz.bereinigteStempel += 1
            return ""
        }

        mutating func tag(_ wert: Any?) -> String {
            let text = Planungsdatei.text(wert)
            if text.isEmpty || Tag(iso: text) != nil { return text }
            bilanz.bereinigteTage += 1
            return ""
        }

        /// Die Uhrzeit in fester Form „07:45“ — sonst geleert und gezählt wie ein Tag.
        mutating func uhrzeit(_ wert: Any?) -> String {
            let text = Planungsdatei.text(wert)
            if text.isEmpty || Lernendenbestand.uhrzeit(text) == text { return text }
            bilanz.bereinigteTage += 1
            return ""
        }

        /// Die Kennung eines Vorhabens oder leer — eine fremde Form wird geleert und gezählt.
        mutating func vorhaben(_ wert: Any?) -> String {
            let text = Planungsdatei.text(wert)
            if text.isEmpty || Kennung.istGueltig(text) { return text }
            bilanz.bereinigteBezuege += 1
            return ""
        }

        /// Die Herkunft einer Planung: eine Zeile, höchstens so lang wie eine
        /// Kennung — sonst geleert und gezählt.
        mutating func herkunft(_ wert: Any?) -> String {
            let text = Planungsdatei.einzeilig(Planungsdatei.ohneSteuerzeichen(Planungsdatei.text(wert)))
            guard text.count > Planungsdatei.maxKennungslaenge else { return text }
            bilanz.bereinigteBezuege += 1
            return ""
        }

        /// Kennung prüfen; leer, ungültig oder schon vergeben bekommt eine neue.
        mutating func kennung(_ wert: Any?, _ vorsatz: String, belegt: inout Set<String>) -> String {
            var id = Planungsdatei.text(wert)
            if !Kennung.istGueltig(id) || belegt.contains(id) {
                repeat { id = Kennung.neu(vorsatz) } while belegt.contains(id)
                bilanz.ersetzteKennungen += 1
            }
            belegt.insert(id)
            return id
        }

        /// Verweise auf Personen: vorhanden, einmalig, in der Grenze.
        func verweise(_ wert: Any?, auf bekannt: Set<String>, grenze: Int, _ zaehler: inout Int) -> [String] {
            guard let roh = wert as? [Any] else {
                if wert != nil { zaehler += 1 }
                return []
            }
            var aus: [String] = []
            var gesehen = Set<String>()
            for eintrag in roh {
                guard let id = eintrag as? String, bekannt.contains(id), !gesehen.contains(id), aus.count < grenze else {
                    zaehler += 1
                    continue
                }
                gesehen.insert(id)
                aus.append(id)
            }
            return aus
        }

        mutating func bestand(_ o: [String: Any]) throws -> Lernendenbestand {
            let schuljahr: String
            let rohesJahr = Planungsdatei.text(o["schuljahr"])
            if rohesJahr.isEmpty || Lernendenbestand.istSchuljahr(rohesJahr) {
                schuljahr = rohesJahr
            } else {
                schuljahr = ""
                bilanz.verworfeneFelder += 1
            }
            let lernende = personen(try liste(o["lernende"], "lernende"))
            let personenIds = Set(lernende.map(\.id))
            let gruppen = lerngruppen(try liste(o["lerngruppen"], "lerngruppen"), personen: personenIds)
            let gruppenIds = Set(gruppen.map(\.id))
            let anliegen = anliegen(try liste(o["anliegen"], "anliegen"), personen: personenIds, gruppen: gruppenIds)
            let rueckmeldungen = rueckmeldungen(try liste(o["rueckmeldungen"], "rueckmeldungen"), anliegen: anliegen)
            let erfassung = erfassung(try liste(o["erfassung"], "erfassung"), personen: personenIds, gruppen: gruppenIds)
            let beurteilung = beurteilung(try liste(o["beurteilung"], "beurteilung"),
                                          personen: personenIds, gruppen: gruppenIds)
            let verhalten = verhalten(try liste(o["verhalten"], "verhalten"), personen: personenIds)
            let leistungen = leistungen(try liste(o["leistungen"], "leistungen"), personen: personenIds, gruppen: gruppenIds)
            return Lernendenbestand(
                planung: herkunft(o["planung"]), schuljahr: schuljahr,
                erstellt: stempel(o["erstellt"]), geaendert: stempel(o["geaendert"]),
                lernende: lernende, lerngruppen: gruppen, anliegen: anliegen, rueckmeldungen: rueckmeldungen,
                erfassung: erfassung, beurteilung: beurteilung, verhalten: verhalten, leistungen: leistungen)
        }

        mutating func personen(_ roh: [Any]) -> [Lernender] {
            var aus: [Lernender] = []
            var belegt = Set<String>()
            for eintrag in gekappt(roh, Kennwerte.maxLernende, &bilanz.verworfeneLernende) {
                guard let p = eintrag as? [String: Any] else { bilanz.verworfeneLernende += 1; continue }
                let vorname = zeile(p["vorname"], Kennwerte.maxLernendenname)
                let nachname = zeile(p["nachname"], Kennwerte.maxLernendenname)
                guard !vorname.isEmpty || !nachname.isEmpty else { bilanz.verworfeneLernende += 1; continue }
                aus.append(Lernender(id: kennung(p["id"], "l", belegt: &belegt), vorname: vorname, nachname: nachname,
                                     rufname: zeile(p["rufname"], Kennwerte.maxLernendenname),
                                     angelegt: stempel(p["angelegt"]), geaendert: stempel(p["geaendert"]),
                                     archiviert: stempel(p["archiviert"])))
            }
            return aus
        }

        mutating func lerngruppen(_ roh: [Any], personen: Set<String>) -> [Lerngruppe] {
            var aus: [Lerngruppe] = []
            var belegt = Set<String>()
            for eintrag in gekappt(roh, Kennwerte.maxLerngruppen, &bilanz.verworfeneGruppen) {
                guard let g = eintrag as? [String: Any] else { bilanz.verworfeneGruppen += 1; continue }
                let name = zeile(g["name"], Planungsdatei.maxNamenslaenge)
                guard !name.isEmpty else { bilanz.verworfeneGruppen += 1; continue }
                let art: Lerngruppenart
                if let gelesen = Lerngruppenart(rawValue: Planungsdatei.text(g["art"])) {
                    art = gelesen
                } else {
                    art = .klasse
                    bilanz.verworfeneFelder += 1
                }
                let mitglieder = verweise(g["mitglieder"], auf: personen, grenze: Kennwerte.maxMitgliederJeLerngruppe,
                                          &bilanz.verworfeneMitglieder)
                // Ein Fach aus einer älteren Datei gilt nicht (E665).
                aus.append(Lerngruppe(
                    id: kennung(g["id"], "g", belegt: &belegt), name: name,
                    art: art, mitglieder: mitglieder,
                    zeilen: zeilen(g["zeilen"]), skalen: skalen(g["skalen"]),
                    halbjahreswechsel: tag(g["halbjahreswechsel"]),
                    geaendert: stempel(g["geaendert"]), archiviert: stempel(g["archiviert"])))
            }
            return aus
        }

        mutating func zeilen(_ wert: Any?) -> [Zeilenbindung] {
            guard let roh = wert as? [Any] else {
                if wert != nil { bilanz.verworfeneZeilen += 1 }
                return []
            }
            var aus: [Zeilenbindung] = []
            for eintrag in roh {
                guard let z = eintrag as? [String: Any], aus.count < maxZeilenJeGruppe else {
                    bilanz.verworfeneZeilen += 1
                    continue
                }
                let planung = Planungsdatei.einzeilig(Planungsdatei.ohneSteuerzeichen(Planungsdatei.text(z["planung"])))
                let klasse = Planungsdatei.text(z["klasseId"])
                let bindung = Zeilenbindung(planung: planung, klasseId: klasse)
                guard !planung.isEmpty, planung.count <= Planungsdatei.maxKennungslaenge,
                      Kennung.istGueltig(klasse), !aus.contains(bindung) else {
                    bilanz.verworfeneZeilen += 1
                    continue
                }
                aus.append(bindung)
            }
            return aus
        }

        mutating func skalen(_ wert: Any?) -> [String: String] {
            guard let roh = wert as? [String: Any] else {
                if wert != nil { bilanz.verworfeneFelder += 1 }
                return [:]
            }
            var aus: [String: String] = [:]
            // Sortiert, damit dieselbe Datei immer dieselben behält.
            for schluessel in roh.keys.sorted() {
                let text = Planungsdatei.einzeilig(Planungsdatei.ohneSteuerzeichen(Planungsdatei.text(roh[schluessel])))
                guard Kennung.istGueltig(schluessel), !text.isEmpty, text.count <= 64,
                      aus.count < maxSkalen else {
                    bilanz.verworfeneFelder += 1
                    continue
                }
                aus[schluessel] = text
            }
            return aus
        }

        mutating func anliegen(_ roh: [Any], personen: Set<String>, gruppen: Set<String>) -> [Anliegen] {
            var aus: [Anliegen] = []
            var belegt = Set<String>()
            for eintrag in gekappt(roh, maxAnliegen, &bilanz.verworfeneAnliegen) {
                guard let a = eintrag as? [String: Any],
                      let art = Anliegenart(rawValue: Planungsdatei.text(a["art"])) else {
                    bilanz.verworfeneAnliegen += 1
                    continue
                }
                // Ein Termin ohne Tag ist keiner.
                if art == .termin, Tag(iso: Planungsdatei.text(a["datum"])) == nil {
                    bilanz.verworfeneAnliegen += 1
                    continue
                }
                let titel = zeile(a["titel"], maxTitel)
                var gruppe = Planungsdatei.text(a["lerngruppe"])
                if !gruppe.isEmpty, !gruppen.contains(gruppe) {
                    // Eine Mitteilung ohne ihre Gruppe ist niemandes Rücklauf;
                    // Maßnahme und Termin gehören der Person und bleiben.
                    if art == .mitteilung { bilanz.verworfeneAnliegen += 1; continue }
                    bilanz.bereinigteBezuege += 1
                    gruppe = ""
                }
                guard !titel.isEmpty, art != .mitteilung || !gruppe.isEmpty else {
                    bilanz.verworfeneAnliegen += 1
                    continue
                }
                // Der Rückverweis (E293): nur am Termin, nur beide zusammen, in fester Form.
                let rohePlanung = Planungsdatei.text(a["planung"])
                let rohesVorhaben = Planungsdatei.text(a["vorhaben"])
                var rueckverweis = (planung: "", vorhaben: "")
                if !rohePlanung.isEmpty || !rohesVorhaben.isEmpty {
                    if art == .termin, Kennung.istGueltig(rohesVorhaben), !rohePlanung.isEmpty,
                       rohePlanung.count <= Planungsdatei.maxKennungslaenge,
                       Planungsdatei.einzeilig(Planungsdatei.ohneSteuerzeichen(rohePlanung)) == rohePlanung {
                        rueckverweis = (rohePlanung, rohesVorhaben)
                    } else {
                        bilanz.bereinigteBezuege += 1
                    }
                }
                aus.append(Anliegen(
                    id: kennung(a["id"], "m", belegt: &belegt), art: art, titel: titel, lerngruppe: gruppe,
                    betroffene: verweise(a["betroffene"], auf: personen, grenze: Kennwerte.maxMitgliederJeLerngruppe,
                                         &bilanz.verworfeneBetroffene),
                    datum: tag(a["datum"]), frist: tag(a["frist"]), uhrzeit: uhrzeit(a["uhrzeit"]),
                    notiz: notiz(a["notiz"]), angelegt: stempel(a["angelegt"]), geaendert: stempel(a["geaendert"]),
                    planung: rueckverweis.planung, vorhaben: rueckverweis.vorhaben))
            }
            return aus
        }

        mutating func rueckmeldungen(_ roh: [Any], anliegen: [Anliegen]) -> [Rueckmeldung] {
            var betroffen: [String: Set<String>] = [:]
            for a in anliegen { betroffen[a.id] = Set(a.betroffene) }
            var aus: [Rueckmeldung] = []
            var gesehen = Set<String>()
            for eintrag in gekappt(roh, maxRueckmeldungen, &bilanz.verworfeneRueckmeldungen) {
                guard let r = eintrag as? [String: Any],
                      let stand = Rueckmeldestand(rawValue: Planungsdatei.text(r["stand"])) else {
                    bilanz.verworfeneRueckmeldungen += 1
                    continue
                }
                let anliegenId = Planungsdatei.text(r["anliegen"])
                let person = Planungsdatei.text(r["lernender"])
                let paar = anliegenId + "\u{1F}" + person
                guard betroffen[anliegenId]?.contains(person) == true, !gesehen.contains(paar) else {
                    bilanz.verworfeneRueckmeldungen += 1
                    continue
                }
                gesehen.insert(paar)
                aus.append(Rueckmeldung(anliegen: anliegenId, lernender: person, stand: stand, datum: tag(r["datum"]),
                                        notiz: notiz(r["notiz"]), geaendert: stempel(r["geaendert"])))
            }
            return aus
        }

        mutating func erfassung(_ roh: [Any], personen: Set<String>, gruppen: Set<String>) -> [Erfassungseintrag] {
            var aus: [Erfassungseintrag] = []
            var belegt = Set<String>()
            for eintrag in gekappt(roh, maxErfassung, &bilanz.verworfeneEintraege) {
                guard let e = eintrag as? [String: Any],
                      let art = Erfassungsart(rawValue: Planungsdatei.text(e["art"])),
                      personen.contains(Planungsdatei.text(e["lernender"])),
                      Tag(iso: Planungsdatei.text(e["datum"])) != nil else {
                    bilanz.verworfeneEintraege += 1
                    continue
                }
                // Ohne Gruppe nur die allgemeine Notiz (E290).
                let gruppe = Planungsdatei.text(e["lerngruppe"])
                guard gruppe.isEmpty ? art == .frei : gruppen.contains(gruppe) else {
                    bilanz.verworfeneEintraege += 1
                    continue
                }
                var vorhaben = vorhaben(e["vorhaben"])
                var planung = herkunft(e["planung"])
                var wert = zeile(e["wert"], maxWert)
                if gruppe.isEmpty {
                    if !vorhaben.isEmpty { vorhaben = ""; bilanz.bereinigteBezuege += 1 }
                    if !planung.isEmpty { planung = ""; bilanz.bereinigteBezuege += 1 }
                    if !wert.isEmpty { wert = ""; bilanz.verworfeneFelder += 1 }
                }
                aus.append(Erfassungseintrag(
                    id: kennung(e["id"], "a", belegt: &belegt), lernender: Planungsdatei.text(e["lernender"]),
                    lerngruppe: gruppe, planung: planung, vorhaben: vorhaben,
                    datum: Planungsdatei.text(e["datum"]), art: art, wert: wert, notiz: notiz(e["notiz"]),
                    angelegt: stempel(e["angelegt"]), geaendert: stempel(e["geaendert"])))
            }
            return aus
        }

        mutating func beurteilung(_ roh: [Any], personen: Set<String>, gruppen: Set<String>) -> [Beurteilung] {
            var aus: [Beurteilung] = []
            var belegt = Set<String>()
            for eintrag in gekappt(roh, maxBeurteilungen, &bilanz.verworfeneEintraege) {
                guard let u = eintrag as? [String: Any],
                      let halbjahr = Planungsdatei.ganzzahl(u["halbjahr"]), halbjahr == 1 || halbjahr == 2,
                      personen.contains(Planungsdatei.text(u["lernender"])),
                      gruppen.contains(Planungsdatei.text(u["lerngruppe"])),
                      Lernendenbestand.istSchuljahr(Planungsdatei.text(u["schuljahr"])) else {
                    bilanz.verworfeneEintraege += 1
                    continue
                }
                aus.append(Beurteilung(
                    id: kennung(u["id"], "b", belegt: &belegt), lernender: Planungsdatei.text(u["lernender"]),
                    lerngruppe: Planungsdatei.text(u["lerngruppe"]), schuljahr: Planungsdatei.text(u["schuljahr"]),
                    halbjahr: halbjahr, zeugnisnote: zeile(u["zeugnisnote"], maxWert),
                    notiz: notiz(u["notiz"]), geaendert: stempel(u["geaendert"])))
            }
            return aus
        }

        /// Höchstens ein Eintrag je Person, Schuljahr und Halbjahr — der erste gilt.
        mutating func verhalten(_ roh: [Any], personen: Set<String>) -> [Verhalten] {
            var aus: [Verhalten] = []
            var belegt = Set<String>()
            var gesehen = Set<String>()
            for eintrag in gekappt(roh, maxVerhalten, &bilanz.verworfeneEintraege) {
                guard let v = eintrag as? [String: Any],
                      let halbjahr = Planungsdatei.ganzzahl(v["halbjahr"]), halbjahr == 1 || halbjahr == 2,
                      personen.contains(Planungsdatei.text(v["lernender"])),
                      Lernendenbestand.istSchuljahr(Planungsdatei.text(v["schuljahr"])),
                      gesehen.insert(Planungsdatei.text(v["lernender"]) + "\u{1F}" + Planungsdatei.text(v["schuljahr"])
                                     + "\u{1F}\(halbjahr)").inserted else {
                    bilanz.verworfeneEintraege += 1
                    continue
                }
                aus.append(Verhalten(
                    id: kennung(v["id"], "v", belegt: &belegt), lernender: Planungsdatei.text(v["lernender"]),
                    schuljahr: Planungsdatei.text(v["schuljahr"]), halbjahr: halbjahr,
                    arbeitsverhalten: zeile(v["arbeitsverhalten"], maxWert),
                    sozialverhalten: zeile(v["sozialverhalten"], maxWert),
                    notiz: notiz(v["notiz"]), geaendert: stempel(v["geaendert"])))
            }
            return aus
        }

        mutating func leistungen(_ roh: [Any], personen: Set<String>, gruppen: Set<String>) -> [Leistung] {
            var aus: [Leistung] = []
            var belegt = Set<String>()
            for eintrag in gekappt(roh, maxLeistungen, &bilanz.verworfeneEintraege) {
                guard let n = eintrag as? [String: Any],
                      let art = Leistungsart(rawValue: Planungsdatei.text(n["art"])),
                      let halbjahr = Planungsdatei.ganzzahl(n["halbjahr"]), halbjahr == 1 || halbjahr == 2,
                      personen.contains(Planungsdatei.text(n["lernender"])),
                      gruppen.contains(Planungsdatei.text(n["lerngruppe"])),
                      Lernendenbestand.istSchuljahr(Planungsdatei.text(n["schuljahr"])) else {
                    bilanz.verworfeneEintraege += 1
                    continue
                }
                aus.append(Leistung(
                    id: kennung(n["id"], "n", belegt: &belegt), lernender: Planungsdatei.text(n["lernender"]),
                    lerngruppe: Planungsdatei.text(n["lerngruppe"]), schuljahr: Planungsdatei.text(n["schuljahr"]),
                    halbjahr: halbjahr, art: art, titel: zeile(n["titel"], maxTitel), datum: tag(n["datum"]),
                    wert: zeile(n["wert"], maxWert), notiz: notiz(n["notiz"]), planung: herkunft(n["planung"]),
                    vorhaben: vorhaben(n["vorhaben"]), angelegt: stempel(n["angelegt"]), geaendert: stempel(n["geaendert"])))
            }
            return aus
        }
    }
}

// ── Das Verzeichnis ───────────────────────────────────────────────────────

/// Fragen über alle Personen, beantwortet aus Verzeichnissen im Speicher —
/// gebaut je Stand, nicht je Frage (nach dem Muster von `Zellenverzeichnis`).
struct Lernendenverzeichnis {
    private let personen: [String: Lernender]
    private let gruppenNachId: [String: Lerngruppe]
    private let gruppenfolge: [Lerngruppe]
    private let anliegenfolge: [Anliegen]
    private let ruecklaeufe: [String: [String: Rueckmeldung]]
    /// Offene Anliegen je Person — gezählt beim Bauen, für Spalte und Filter.
    private let offen: [String: Int]
    /// Mitglieder ohne die archivierten, je Gruppe — gezählt, nicht sortiert.
    private let zahlen: [String: Int]
    /// Alle Personen in Anzeigereihenfolge, archivierte eingeschlossen.
    private let geordnet: [Lernender]
    /// Die Gruppen je Person in der Folge der Listen — einmal gebaut, nicht je Frage (Z-AT1-06: Die Tabelle
    /// „Alle Lernenden“ fragt für jede Person).
    private let gruppenJePerson: [String: [Lerngruppe]]

    init(_ bestand: Lernendenbestand) {
        var personen: [String: Lernender] = [:]
        for p in bestand.lernende { personen[p.id] = p }
        self.personen = personen
        var gruppen: [String: Lerngruppe] = [:]
        for g in bestand.lerngruppen { gruppen[g.id] = g }
        gruppenNachId = gruppen
        let folge = bestand.lerngruppen.sorted(by: Lerngruppe.vorgehen)
        gruppenfolge = folge
        var jePerson: [String: [Lerngruppe]] = [:]
        for g in folge {
            for p in Set(g.mitglieder) { jePerson[p, default: []].append(g) }
        }
        gruppenJePerson = jePerson
        anliegenfolge = bestand.anliegen
        var ruecklaeufe: [String: [String: Rueckmeldung]] = [:]
        for r in bestand.rueckmeldungen { ruecklaeufe[r.anliegen, default: [:]][r.lernender] = r }
        self.ruecklaeufe = ruecklaeufe
        var offen: [String: Int] = [:]
        for a in bestand.anliegen {
            for p in a.betroffene where (ruecklaeufe[a.id]?[p]?.stand ?? .offen) == .offen { offen[p, default: 0] += 1 }
        }
        self.offen = offen
        var zahlen: [String: Int] = [:]
        for g in bestand.lerngruppen {
            zahlen[g.id] = g.mitglieder.reduce(0) { $0 + (personen[$1]?.archiviert.isEmpty == true ? 1 : 0) }
        }
        self.zahlen = zahlen
        geordnet = bestand.lernende.sorted(by: Lernendenverzeichnis.vorgehen)
    }

    /// Nachname, dann Vorname — wie der Finder ordnet; bei Gleichstand die Kennung.
    static func vorgehen(_ a: Lernender, _ b: Lernender) -> Bool {
        let nach = a.nachname.localizedStandardCompare(b.nachname)
        if nach != .orderedSame { return nach == .orderedAscending }
        let vor = a.vorname.localizedStandardCompare(b.vorname)
        if vor != .orderedSame { return vor == .orderedAscending }
        return a.id < b.id
    }

    /// Alle Personen ohne die archivierten, geordnet.
    var alle: [Lernender] { geordnet.filter { $0.archiviert.isEmpty } }
    var alleMitArchivierten: [Lernender] { geordnet }

    func person(_ id: String) -> Lernender? { personen[id] }
    func gruppe(_ id: String) -> Lerngruppe? { gruppenNachId[id] }

    func mitglieder(_ gruppe: String, archivierte: Bool = false) -> [Lernender] {
        guard let g = gruppenNachId[gruppe] else { return [] }
        return g.mitglieder.compactMap { personen[$0] }
            .filter { archivierte || $0.archiviert.isEmpty }
            .sorted(by: Lernendenverzeichnis.vorgehen)
    }

    func mitgliederzahl(_ gruppe: String) -> Int { zahlen[gruppe] ?? 0 }

    func gruppen(von person: String) -> [Lerngruppe] {
        gruppenJePerson[person] ?? []
    }

    /// Die Lerngruppen eines Stands, geordnet — für ⌘K und das Archiv; ohne die archivierten, wenn
    /// nicht verlangt. Was am Entwurf eines Blatts ordnet, nimmt `Lerngruppe.vorgehen` selbst.
    func gruppen(archivierte: Bool = false) -> [Lerngruppe] {
        gruppenfolge.filter { archivierte || $0.archiviert.isEmpty }
    }

    /// Ohne Rücklauf gilt `offen`.
    func stand(_ anliegen: String, _ person: String) -> Rueckmeldestand {
        ruecklaeufe[anliegen]?[person]?.stand ?? .offen
    }

    func rueckmeldung(_ anliegen: String, _ person: String) -> Rueckmeldung? { ruecklaeufe[anliegen]?[person] }

    func offeneZahl(von person: String) -> Int { offen[person] ?? 0 }

    func mitteilungen(der gruppe: String) -> [Anliegen] {
        anliegenfolge.filter { $0.art == .mitteilung && $0.lerngruppe == gruppe }
    }

    /// Die Maßnahmen, die eine der Personen betreffen.
    func massnahmen(fuer personen: Set<String>) -> [Anliegen] {
        anliegenfolge.filter { $0.art == .massnahme && $0.betroffene.contains(where: personen.contains) }
    }

    func offeneAnliegen(von person: String) -> [Anliegen] {
        anliegenfolge.filter { $0.betroffene.contains(person) && stand($0.id, person) == .offen }
    }

    func anliegen(der gruppe: String) -> [Anliegen] {
        anliegenfolge.filter { $0.lerngruppe == gruppe }
    }

    /// Maßnahmen und Termine ohne Gruppe, die die Person betreffen — was das
    /// Blatt an der Person unter „Alle Lernenden“ führt (E290).
    func anliegenOhneGruppe(von person: String) -> [Anliegen] {
        anliegenfolge.filter { $0.art != .mitteilung && $0.lerngruppe.isEmpty && $0.betroffene.contains(person) }
    }

    /// Die Plätze für „Namen aus der Lerngruppe übernehmen“ (E255): die aktiven
    /// Mitglieder in der Ordnung des Verzeichnisses, je „Vorname Nachname“ wie
    /// in der Namensliste des Sitzplans, der Rufname statt des Vornamens (E285) —
    /// Archivierte gehören nicht ins Angebot (E252).
    func sitzplatzvorlage(der gruppe: String) -> [Sitzplan.Platzvorlage] {
        mitglieder(gruppe).map { Sitzplan.Platzvorlage(name: Lernendenverzeichnis.sitzplatzname($0), lernender: $0.id) }
    }

    /// Der Name am Tisch: „Vorname Nachname“, der Rufname statt des Vornamens (E285), gekürzt auf die
    /// Grenze des Sitzplans — derselbe beim Übernehmen und beim Nachführen (E390).
    static func sitzplatzname(_ p: Lernender) -> String {
        let name = [p.rufname.isEmpty ? p.vorname : p.rufname, p.nachname].filter { !$0.isEmpty }.joined(separator: " ")
        return String(name.prefix(Kennwerte.maxSitzplatzname))
    }

    /// Die offenen Anliegen einer Gruppe, wie ihr Blatt sie zeigt — ihre
    /// Mitteilungen und die Maßnahmen ihrer Mitglieder, bei denen noch jemand
    /// offen steht; es zählen nur die aktiven Mitglieder, seit v84 auch bei
    /// Mitteilungen (E366: Wer die Gruppe verließ, behält seinen Rücklauf,
    /// zählt hier aber nicht mehr; ein archiviertes Mitglied zeigt die Gruppe
    /// ebenso wenig, Z-AT1-04). Die Zahl der Verwaltungszeile (E256):
    /// Anliegen, nicht Einträge je Person.
    func offeneAnliegenzahl(der gruppe: String) -> Int {
        let personen = Set(mitglieder(gruppe).map(\.id))
        let mitteilungen = mitteilungen(der: gruppe).filter { a in
            a.betroffene.contains { personen.contains($0) && stand(a.id, $0) == .offen }
        }
        let massnahmen = massnahmen(fuer: personen).filter { a in
            a.betroffene.contains { personen.contains($0) && stand(a.id, $0) == .offen }
        }
        return mitteilungen.count + massnahmen.count
    }

    // ── Suche und Zusatz (v84, E359, E360, E370) ──────────────────────────

    /// Trifft die Eingabe die Person? Jedes Wort steckt in Nachname, Vorname oder Rufname — Groß/Klein und
    /// Akzente unerheblich, Wortteile genügen (E360). Leer trifft jede.
    static func trifft(_ p: Lernender, _ suche: String) -> Bool {
        suchworte(suche).allSatisfy { wort in
            [p.nachname, p.vorname, p.rufname].contains { $0.localizedStandardContains(wort) }
        }
    }

    /// Die Wörter einer Eingabe — getrennt an Leerraum, Komma („Abel, Anna“) und dem Punkt der Beschriftung
    /// („6a · Biologie“).
    static func suchworte(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0 == "," || $0 == "·" }.map(String.init)
    }

    /// Die Personen, die die Eingabe trifft, in der Ordnung des Verzeichnisses — archivierte nur auf Wunsch.
    func suche(_ text: String, archivierte: Bool = false) -> [Lernender] {
        (archivierte ? alleMitArchivierten : alle).filter { Lernendenverzeichnis.trifft($0, text) }
    }

    /// Die übrigen aktiven Lerngruppen einer Person, geordnet — für den Zusatz „auch in …“ (E370).
    func auchIn(_ person: String, ausser gruppe: String) -> [Lerngruppe] {
        gruppen(von: person).filter { $0.id != gruppe && $0.archiviert.isEmpty }
    }

    /// Die Zeilen der Tabelle „Alle Lernenden“ (E362): je Person die Felder, nach denen ein Kopfklick ordnet.
    /// `archivierteGruppen`: Die Spalte „Lerngruppen“ nennt auch archivierte Gruppen.
    func personenzeilen(_ personen: [Lernender], archivierteGruppen: Bool = false) -> [Personenzeile] {
        personen.map { p in
            Personenzeile(id: p.id, nachname: p.nachname, vorname: p.vorname, rufname: p.rufname,
                          lerngruppen: gruppen(von: p.id).filter { archivierteGruppen || $0.archiviert.isEmpty }
                              .map(\.beschriftung).joined(separator: ", "),
                          offene: offeneZahl(von: p.id), angelegt: p.angelegt)
        }
    }
}

extension Lerngruppe {
    /// Der Filter der Gruppenliste (E359, E671): jedes Wort steckt im Namen oder in einer verknüpften Zeile (`zeilen`,
    /// wie „6a · Biologie“), wie `Lernendenverzeichnis.trifft`.
    static func trifft(_ g: Lerngruppe, _ suche: String, zeilen: [String] = []) -> Bool {
        Lernendenverzeichnis.suchworte(suche).allSatisfy { wort in
            g.name.localizedStandardContains(wort) || zeilen.contains { $0.localizedStandardContains(wort) }
        }
    }
}

// ── Die Ordnung der Tabellen (v84, E362–E364) ─────────────────────────────

/// Eine Zeile der Tabelle „Alle Lernenden“ — Felder statt Ableitungen, damit ein Kopfklick nach jeder
/// Spalte ordnen kann. `angelegt` ist der Zeitstempel: lexikografisch geordnet zugleich zeitlich.
struct Personenzeile: Identifiable, Hashable, Sendable {
    let id: String
    let nachname: String
    let vorname: String
    let rufname: String
    let lerngruppen: String
    let offene: Int
    let angelegt: String

    /// Wie das Verzeichnis ordnet: Nachname, dann Vorname (E363: Text lokalisiert).
    static var vorgabe: [KeyPathComparator<Personenzeile>] {
        [KeyPathComparator(\.nachname, comparator: .localizedStandard),
         KeyPathComparator(\.vorname, comparator: .localizedStandard)]
    }
}

/// Die Ordnung je Sitzung (E364): Text lokalisiert, Zahlen als Zahl, Tage als ISO-Text; der vorige Schlüssel
/// bleibt Zweitschlüssel, die Kennung entscheidet zuletzt (E363).
enum Tabellenordnung {
    /// Ein Kopfklick macht seine Spalte zum ersten Schlüssel — die vorigen bleiben dahinter, jede Spalte einmal.
    static func mitVorigem<Zeile>(_ jetzt: [KeyPathComparator<Zeile>],
                                  vorher: [KeyPathComparator<Zeile>]) -> [KeyPathComparator<Zeile>] {
        var ergebnis: [KeyPathComparator<Zeile>] = []
        for schluessel in jetzt + vorher where !ergebnis.contains(where: { $0.keyPath == schluessel.keyPath }) {
            ergebnis.append(schluessel)
        }
        return ergebnis
    }

    /// Die Zeilen in der Ordnung, zuletzt nach der Kennung wie im Verzeichnis (`<`) — so steht die Folge auch bei
    /// Gleichstand fest, unabhängig von der Folge der Eingabe.
    static func geordnet<Zeile: Identifiable>(_ zeilen: [Zeile], nach ordnung: [KeyPathComparator<Zeile>]) -> [Zeile]
        where Zeile.ID == String {
        zeilen.sorted { a, b in
            for schluessel in ordnung {
                switch schluessel.compare(a, b) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return a.id < b.id
        }
    }
}

// ── Eingabe von Hand (E273) ───────────────────────────────────────────────

/// Je Zeile eine Person: „Nachname, Vorname“ mit Komma ist eindeutig; ohne
/// Komma gilt das letzte Wort als Nachname. Leere Zeilen werden übergangen,
/// zählen aber für die Zeilennummer; jeder Zeilenwechsel trennt, auch CRLF.
enum Namenszeilen {
    struct Name: Hashable, Sendable {
        let vorname: String
        let nachname: String
    }

    struct Fehler: Identifiable, Hashable, Sendable {
        var id: Int { nummer }
        let nummer: Int
        let zeile: String
        let grund: String
    }

    struct Ergebnis: Sendable {
        var namen: [Name] = []
        var fehler: [Fehler] = []
    }

    static func lesen(_ text: String) -> Ergebnis {
        var ergebnis = Ergebnis()
        let grenze = Kennwerte.maxLernendenname
        for (stelle, roh) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let zeile = Planungsdatei.ohneSteuerzeichen(String(roh)).trimmingCharacters(in: .whitespacesAndNewlines)
            if zeile.isEmpty { continue }
            func fehler(_ grund: String) {
                let gezeigt = zeile.count > 40 ? String(zeile.prefix(40)) + "…" : zeile
                ergebnis.fehler.append(Fehler(nummer: stelle + 1, zeile: gezeigt, grund: grund))
            }
            guard ergebnis.namen.count < Kennwerte.maxMitgliederJeLerngruppe else {
                fehler("Über der Grenze von \(Kennwerte.maxMitgliederJeLerngruppe) Personen je Eingabe.")
                continue
            }
            let vorname: String
            let nachname: String
            let teile = zeile.split(separator: ",", omittingEmptySubsequences: false)
            if teile.count > 2 {
                fehler("Mehr als ein Komma — bitte „Nachname, Vorname“.")
                continue
            } else if teile.count == 2 {
                nachname = Planungsdatei.einzeilig(String(teile[0]))
                vorname = Planungsdatei.einzeilig(String(teile[1]))
                guard !nachname.isEmpty || !vorname.isEmpty else {
                    fehler("Vor und nach dem Komma steht kein Name.")
                    continue
                }
            } else {
                let woerter = zeile.split(whereSeparator: \.isWhitespace).map(String.init)
                guard woerter.count >= 2 else {
                    fehler("Nur ein Wort — mit Komma ist es eindeutig: „Nachname, Vorname“ oder „Nachname,“.")
                    continue
                }
                nachname = woerter[woerter.count - 1]
                vorname = woerter.dropLast().joined(separator: " ")
            }
            guard vorname.count <= grenze, nachname.count <= grenze else {
                fehler("Ein Name ist länger als \(grenze) Zeichen.")
                continue
            }
            ergebnis.namen.append(Name(vorname: vorname, nachname: nachname))
        }
        return ergebnis
    }
}
