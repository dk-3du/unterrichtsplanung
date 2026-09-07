// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum Kennwerte {
    static let maxKlassen = 75
    static let dateiTyp = "unterrichtsplanung"
    /// 2: Der Farbwert bedeutet etwas anderes als in Version 1 (siehe `Altfarben`).
    static let dateiVersion = 2
    static let wochenStandard = 52
    static let wochenMax = 52
    // ── Spaltenbreite: drei Rasten von 210 bis 350 Punkt ──────────────────
    static let spalteMin: Double = 210
    static let spalteMax: Double = 350
    static let spalteStandard: Double = 280
    static let spalteStufen = 3
    static var spalteRaster: Double {
        (spalteMax - spalteMin) / Double(spalteStufen - 1)
    }

    /// Gerastert wird ab dem kleinsten Wert, nicht ab null — sonst träfe das
    /// Runden die Stufen nicht, sobald `spalteMin` kein Vielfaches der
    /// Rasterweite ist.
    static func spalteRasten(_ wert: Double) -> Double {
        let stufe = ((wert - spalteMin) / spalteRaster).rounded()
        return min(spalteMax, max(spalteMin, spalteMin + stufe * spalteRaster))
    }
}

/// Gespeichert wird **nur der Verweis** — Form siehe `Pfade`.
struct Material: Identifiable, Hashable, Sendable {
    var id = UUID()
    var titel: String
    var pfad: String

    var istAbsolut: Bool { Pfade.istAbsolut(pfad) }
}

/// Ein Weblink. `adresse` ist immer eine geprüfte http- oder https-Adresse.
struct Weblink: Identifiable, Hashable, Sendable {
    var id = UUID()
    var titel: String
    var adresse: String
}

struct Klasse: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var fach: String
    var notiz: String
    /// Stelle in `Farbwelt.toene`; `Farbwelt.ohneFarbe` heißt: noch keine.
    var farbe: Int
    /// Von Hand gesetzt — dann zieht die Fachfarbe nicht mehr nach.
    var farbeManuell: Bool
    /// Notenliste, Kursbuch — wie bei den Materialien nur der Pfad.
    var verwaltung: String = ""
    /// Lehrplan, Fachcurriculum — getrennt von der Verwaltungsdatei.
    var curriculum: String = ""
    /// An welchen Wochentagen laut Stundenplan regelmäßig Unterricht
    /// stattfindet (Montag bis Freitag). Leer heißt: nicht hinterlegt. Die
    /// Angabe hebt im Vorhaben-Dialog die Wochentage hervor — mehr nicht:
    /// Eine Änderung hier rührt kein bestehendes Vorhaben an.
    var unterrichtstage: Set<Wochentag> = []

    var beschriftung: String { name + (fach.isEmpty ? "" : " · " + fach) }
    var hatVerwaltung: Bool { !verwaltung.trimmingCharacters(in: .whitespaces).isEmpty }
    var hatCurriculum: Bool { !curriculum.trimmingCharacters(in: .whitespaces).isEmpty }

    func pfad(_ art: Kursdateiart) -> String {
        switch art {
        case .verwaltung: verwaltung
        case .curriculum: curriculum
        }
    }

    func hat(_ art: Kursdateiart) -> Bool {
        switch art {
        case .verwaltung: hatVerwaltung
        case .curriculum: hatCurriculum
        }
    }
}

/// Die beiden Dateien, die an einer Klasse bzw. einem Kurs hängen können.
enum Kursdateiart: String, CaseIterable, Identifiable, Sendable {
    case verwaltung, curriculum

    var id: String { rawValue }

    var beschriftung: String {
        switch self {
        case .verwaltung: "Verwaltung"
        case .curriculum: "Curriculum"
        }
    }

    var dateibeschriftung: String {
        switch self {
        case .verwaltung: "Verwaltungsdatei"
        case .curriculum: "Curriculumdatei"
        }
    }

    var auswahltitel: String { dateibeschriftung + " wählen" }

    var symbol: String {
        switch self {
        case .verwaltung: Zeichen.kursdatei
        case .curriculum: Zeichen.curriculum
        }
    }

    var symbolGesetzt: String {
        switch self {
        case .verwaltung: Zeichen.kursdateiGesetzt
        case .curriculum: Zeichen.curriculumGesetzt
        }
    }
}

/// Was für Ferien und Sperrzeiten gleichermaßen gilt — einmal geschrieben.
protocol Zeitspanne {
    var von: Tag { get set }
    var bis: Tag { get set }
}

extension Zeitspanne {
    /// „Ende vor Beginn“: überall wirkungslos, weil `tag >= von && tag <= bis`
    /// nie zutrifft. Gelesen wird so ein Zeitraum trotzdem roh — gedreht würde
    /// er nach einem Neustart stillschweigend wirksam (siehe `Planungsdatei`).
    var ungueltig: Bool { von > bis }

    /// Beim Setzen eines Datums zieht das andere mit. Beide Dialoge halten sich
    /// daran: Über die Oberfläche entsteht kein Zeitraum, der nichts bewirkt
    /// und dessen Wirkungslosigkeit nur an einer roten Beschriftung hinge.
    func mitBeginn(_ tag: Tag) -> Self {
        var geaendert = self
        geaendert.von = tag
        if geaendert.bis < tag { geaendert.bis = tag }
        return geaendert
    }

    func mitEnde(_ tag: Tag) -> Self {
        var geaendert = self
        geaendert.bis = tag
        if geaendert.von > tag { geaendert.von = tag }
        return geaendert
    }
}

struct Ferienzeitraum: Identifiable, Hashable, Sendable, Zeitspanne {
    var id: String
    var name: String
    var von: Tag
    var bis: Tag
}

/// Ein Zeitraum, in dem keine Prüfung liegen darf — getrennt von den Ferien:
/// Hier wird unterrichtet, nur nicht geprüft.
struct Sperrzeitraum: Identifiable, Hashable, Sendable, Zeitspanne {
    var id: String
    var name: String
    var von: Tag
    var bis: Tag
    /// Für welche Klassen und Kurse die Sperre gilt. **Leer heißt: für alle**
    /// — dorthin fällt auch eine Sperre zurück, deren Zeilen gelöscht wurden.
    var kurse: [String] = []

    var giltFuerAlle: Bool { kurse.isEmpty }

    func enthaelt(_ tag: Tag) -> Bool { tag >= von && tag <= bis }

    func gilt(fuer klasseId: String) -> Bool { kurse.isEmpty || kurse.contains(klasseId) }

    var abweisung: String {
        "Im Zeitraum vom \(von.deutsch) bis zum \(bis.deutsch) dürfen keine "
        + "Prüfungen eingetragen werden."
    }
}

/// Eine einzeln freigestellte Klasse bzw. ein Kurs in einer einzelnen Woche. Der Schlüssel ist
/// das ISO-Datum des Montags, nicht der Spaltenindex — so übersteht die
/// Markierung eine Verschiebung des Startdatums.
struct FreieZelle: Hashable, Sendable {
    var klasseId: String
    var woche: Tag
}

struct Vorhaben: Identifiable, Hashable, Sendable {
    var id: String
    var klasseId: String
    /// Spaltenindex, 0-basiert.
    var woche: Int
    var titel: String
    var text: String
    var erledigt: Bool
    var materialien: [Material]
    var links: [Weblink]
    /// Klassenarbeit, Test, Klausur.
    var pruefung: Bool = false
    /// Wann geschrieben wird — getrennt von der Woche, die sagt, wann geplant
    /// wird. `nil` heißt: gekennzeichnet, Termin offen.
    var pruefungstag: Tag? = nil
    /// Der Tag, an dem das Vorhaben stattfindet — getrennt vom Prüfungstermin,
    /// weil ein Sperrzeitraum Prüfungen verbietet, nicht den Unterricht.
    var datum: Tag? = nil
    var dringend: Bool = false
    /// Notiz aus dem Unterricht — auch in der Ansichtsfassung fürs iPad
    /// geschrieben und über `current_status.json` hereingereicht.
    ///
    /// Getrennt von `text`: Der Text sagt, was **geplant** ist, der Kommentar,
    /// wie es **gelaufen** ist.
    var kommentar: String = ""
    /// Wann `erledigt` oder `kommentar` zuletzt **hier** geändert wurden —
    /// die Vergleichsgröße gegen den Stempel aus der iPad-Ansicht. Leer heißt:
    /// nie angefasst, der hereinkommende Stand gilt.
    var statusGeaendert: String = ""

    var anzeigeTitel: String { titel.isEmpty ? "Ohne Titel" : titel }

    /// Der Wochentag des Vorhabens ist der seines Datums — **kein eigenes
    /// Feld**: Zwei Angaben, die dasselbe sagen, liefen auseinander (Datum an
    /// einem Mittwoch, Wochentag „Fr.“). Im Dialog setzt ein Klick auf „Mi.“
    /// das Datum auf den Mittwoch der gewählten Woche; ein getipptes Datum
    /// kreuzt seinen Wochentag an. `nil` ohne Datum und am Wochenende.
    var wochentag: Wochentag? { datum?.wochentag }

    /// Beim Wechsel in eine andere Woche verfallen Wochentag und Datum: Der
    /// alte Tag läge außerhalb, und dass der Unterricht in der neuen Woche
    /// auf denselben Wochentag fällt, ist nicht anzunehmen. Liefert, ob dabei
    /// ein Datum verfallen ist — die Meldung hängt daran.
    mutating func wocheWechseln(nach neueWoche: Int) -> Bool {
        let verfallen = neueWoche != woche && datum != nil
        woche = neueWoche
        if verfallen { datum = nil }
        return verfallen
    }

    /// Eine Kopie wird neu platziert und neu terminiert: Wochentag und Datum
    /// gehen nicht mit — auch nicht in dieselbe Woche. Liefert, ob dabei ein
    /// Datum verfallen ist.
    mutating func datumVerwerfen() -> Bool {
        guard datum != nil else { return false }
        datum = nil
        return true
    }

    /// Kein Fehler, aber eine Auffälligkeit — die Übersicht weist darauf hin.
    func terminAusserhalb(start: Tag) -> Bool {
        guard pruefung else { return false }
        return liegtAusserhalb(pruefungstag, start: start)
    }

    func datumAusserhalb(start: Tag) -> Bool { liegtAusserhalb(datum, start: start) }

    private func liegtAusserhalb(_ tag: Tag?, start: Tag) -> Bool {
        guard let tag else { return false }
        let montag = start.montagDerWoche.plus(tage: woche * 7)
        return tag < montag || tag > montag.plus(tage: 6)
    }

    /// Die Fassung für eine neue Planung: Der Inhalt bleibt, der
    /// Verlaufszustand nicht. Bewusst als **Voll-Kopie mit ausdrücklichem
    /// Zurücksetzen** gebaut — wie die Kopierwege beim Duplizieren und
    /// Einsetzen: Ein künftiges Feld wandert dann automatisch mit, und jedes
    /// Zurücksetzen steht hier schwarz auf weiß.
    ///
    /// Materialpfade werden über den Basisordner der alten Planung voll
    /// aufgelöst — die neue Planung hat keinen, relativ geführte Verweise
    /// zeigten sonst ins Leere.
    func uebernommen(klasseId neueKlasse: String, woche neueWoche: Int,
                     basis alteBasis: String) -> Vorhaben {
        var neu = self
        neu.id = Kennung.neu("e")
        neu.klasseId = neueKlasse
        neu.woche = neueWoche
        neu.erledigt = false
        neu.dringend = false
        neu.pruefungstag = nil
        neu.datum = nil
        neu.kommentar = ""
        neu.statusGeaendert = ""
        neu.materialien = materialien.map { material in
            var kopie = material
            if !kopie.pfad.isEmpty {
                kopie.pfad = Pfade.vollerPfad(kopie.pfad, basis: alteBasis)
            }
            return kopie
        }
        return neu
    }
}

/// Entspricht Feld für Feld der JSON-Datei der Web-Fassung, damit sich beide
/// dieselben Dateien teilen.
struct Planung: Hashable, Sendable {
    var titel: String
    var erstellt: String
    var geaendert: String
    var basis: String
    var start: Tag
    var wochen: Int
    /// Von Hand gesetzt beim Anlegen: Die 1. Schulwoche ist die Kalenderwoche,
    /// in die dieser Tag fällt. `nil` (ältere Dateien) heißt: Die Zählung
    /// leitet sich her — siehe `schulwochen`.
    var ersterSchultag: Tag? = nil
    /// Ganze Wochen, die von Hand als unterrichtsfrei geführt werden.
    var frei: Set<Tag>
    var ferien: [Ferienzeitraum]
    /// Fachschlüssel → Tonschlüssel, **nur ausdrücklich festgelegte Farben**.
    /// Alles Übrige leitet sich aus den Zeilen ab: `fachfarbenWirksam()`.
    var fachfarben: [String: String]
    var klassen: [Klasse]
    var zellenfrei: Set<FreieZelle>
    var eintraege: [Vorhaben]
    /// Zeiträume, in denen keine Prüfung liegen darf.
    var sperrzeiten: [Sperrzeitraum] = []

    static func leer(titel: String, start: Tag, wochen: Int, basis: String,
                     klassen: [Klasse], fachfarben: [String: String],
                     ersterSchultag: Tag? = nil) -> Planung {
        let jetzt = Zeitrechnung.jetztAlsZeitstempel()
        var neue = Planung(titel: titel, erstellt: jetzt, geaendert: jetzt, basis: basis,
                           start: start.montagDerWoche, wochen: wochen,
                           ersterSchultag: ersterSchultag, frei: [], ferien: [],
                           fachfarben: fachfarben, klassen: klassen, zellenfrei: [], eintraege: [],
                           sperrzeiten: [])
        neue.farbenVervollstaendigen()
        return neue
    }

    /// Was beim Anlegen aus der bisherigen Planung mitkommen soll: die Zeile
    /// (Klasse/Kurs und Fach) — wahlweise samt aller zugehörigen Vorhaben.
    struct Uebernahmewunsch: Hashable, Sendable {
        var klasse: Klasse
        var mitVorhaben: Bool
    }

    /// Was die Übernahme ergeben hat — für die Meldung an die Nutzenden.
    struct Uebernahmebilanz: Hashable, Sendable {
        var klassen = 0
        var vorhaben = 0
        /// Vorhaben ohne Schulwoche (volle Ferienwoche, vor Schulbeginn) oder
        /// mit einer Schulwoche jenseits der neuen Planung.
        var uebergangen = 0
    }

    /// Eine neue Planung samt Übernahme aus der bisherigen — rein gerechnet,
    /// damit prüfbar. Übernommene Zeilen behalten Farbe, Notiz und Dateien
    /// (Verweise voll aufgelöst über den alten Basisordner), bekommen aber
    /// eigene Kennungen; was übernommene Vorhaben behalten und was nicht,
    /// steht bei `Vorhaben.uebernommen`. Eingeordnet werden sie nach ihrer
    /// **Schulwoche**: Das Vorhaben der 5. Schulwoche der alten Planung liegt
    /// in der 5. zählbaren Woche der neuen — verankert an deren erstem
    /// Schultag (der Anlege-Dialog übergibt immer einen). `ersterSchultag`
    /// darf hier trotzdem auf `nil` vorbelegen: nil ist ein gültiger Zustand
    /// (hergeleitete Zählung, siehe `schulwochen`), und der einzige
    /// Produktiv-Zugang `Planungsspeicher.neuePlanung` erzwingt die Angabe.
    /// Die angezeigte Zählung richtet sich nach später eingetragenen Ferien.
    static func mitUebernahme(titel: String, start: Tag, wochen: Int, basis: String,
                              klassen: [Klasse], fachfarben: [String: String],
                              ersterSchultag: Tag? = nil,
                              von alte: Planung?, uebernahme: [Uebernahmewunsch])
        -> (planung: Planung, bilanz: Uebernahmebilanz) {

        // Jede Zeile höchstens einmal — sonst Doppelzeile samt doppelter Vorhaben.
        var gesehen = Set<String>()
        let wuensche = alte == nil ? [] : uebernahme.filter { gesehen.insert($0.klasse.id).inserted }

        var zuordnung: [String: String] = [:]   // alte Klassen-Kennung → neue
        var uebernommene: [Klasse] = []
        var vergeben = Set(klassen.map(\.id))
        for wunsch in wuensche {
            var kopie = wunsch.klasse
            repeat { kopie.id = Kennung.neu("k") } while vergeben.contains(kopie.id)
            vergeben.insert(kopie.id)
            if !kopie.verwaltung.isEmpty {
                kopie.verwaltung = Pfade.vollerPfad(kopie.verwaltung, basis: alte?.basis ?? "")
            }
            if !kopie.curriculum.isEmpty {
                kopie.curriculum = Pfade.vollerPfad(kopie.curriculum, basis: alte?.basis ?? "")
            }
            zuordnung[wunsch.klasse.id] = kopie.id
            uebernommene.append(kopie)
        }

        var neue = leer(titel: titel, start: start, wochen: wochen, basis: basis,
                        klassen: Array((klassen + uebernommene).prefix(Kennwerte.maxKlassen)),
                        fachfarben: fachfarben, ersterSchultag: ersterSchultag)
        var bilanz = Uebernahmebilanz()
        guard let alte, !wuensche.isEmpty else { return (neue, bilanz) }

        let aufgenommen = Set(neue.klassen.map(\.id))
        bilanz.klassen = uebernommene.count { aufgenommen.contains($0.id) }

        let alteSchulwochen = alte.wochenstand().schulwochen
        // Schulwoche → Spaltenindex der neuen Planung.
        var ziel: [Int: Int] = [:]
        for (stelle, sw) in neue.wochenstand().schulwochen.enumerated() {
            if let sw { ziel[sw] = stelle }
        }

        for wunsch in wuensche where wunsch.mitVorhaben {
            guard let neueKennung = zuordnung[wunsch.klasse.id] else { continue }
            let eigene = alte.eintraege.filter { $0.klasseId == wunsch.klasse.id }
            guard aufgenommen.contains(neueKennung) else {
                bilanz.uebergangen += eigene.count
                continue
            }
            for alt in eigene {
                guard alteSchulwochen.indices.contains(alt.woche),
                      let schulwoche = alteSchulwochen[alt.woche],
                      let zielWoche = ziel[schulwoche] else {
                    bilanz.uebergangen += 1
                    continue
                }
                neue.eintraege.append(alt.uebernommen(klasseId: neueKennung,
                                                      woche: zielWoche, basis: alte.basis))
                bilanz.vorhaben += 1
            }
        }
        return (neue, bilanz)
    }

    var wochenListe: [Woche] { Tag.wochenListe(start: start, anzahl: wochen) }

    func klasse(_ id: String) -> Klasse? { klassen.first { $0.id == id } }

    /// Der Sperrzeitraum, der dieser Klasse bzw. diesem Kurs an diesem Tag im
    /// Weg steht. Die Zeile ist Pflichtangabe: Eine Sperre kann schulweit oder
    /// nur für einzelne Klassen/Kurse gelten.
    func sperre(am tag: Tag, fuer klasseId: String) -> Sperrzeitraum? {
        sperrzeiten.first { !$0.ungueltig && $0.enthaelt(tag) && $0.gilt(fuer: klasseId) }
    }

    func vorhaben(klasse: String, woche: Int) -> [Vorhaben] {
        eintraege.filter { $0.klasseId == klasse && $0.woche == woche }
    }

    func anzahlVorhaben(klasse: String) -> Int {
        eintraege.count { $0.klasseId == klasse }
    }

    /// Nur erste und letzte Spalte werden gebaut — die ganze Wochenliste hieße
    /// 52 Kalenderrechnungen je Tastendruck im Suchfeld.
    var kennzahlen: String {
        guard wochen > 0 else { return "—" }
        let ersterMontag = start.montagDerWoche
        let erste = Woche(nummer: 0, montag: ersterMontag)
        let letzte = wochen == 1
            ? erste
            : Woche(nummer: wochen - 1, montag: ersterMontag.plus(tage: (wochen - 1) * 7))
        return "KW \(erste.kw)/\(erste.jahr) – KW \(letzte.kw)/\(letzte.jahr)"
            + " · \(wochen) Wochen · \(klassen.count) Klassen/Kurse"
            + " · \(eintraege.count) Vorhaben"
    }
}

// ── Farbvergabe ───────────────────────────────────────────────────────────

extension Planung {

    /// Wie oft jede Farbe vorkommt — festgelegte Fachfarben und Zeilen zusammen.
    var farbnutzung: [Int: Int] {
        var zaehler: [Int: Int] = [:]
        for wert in fachfarben.values {
            if let stelle = Farbwelt.stelle(wert) { zaehler[stelle, default: 0] += 1 }
        }
        for klasse in klassen where Farbwelt.istGueltig(klasse.farbe) {
            zaehler[klasse.farbe, default: 0] += 1
        }
        return zaehler
    }

    /// **Die eine Regel:** Die Farbe eines Fachs ist die festgelegte — sonst
    /// die seiner ersten Zeile, die sie nicht von Hand trägt. Nichts trägt ein
    /// Fach nach; deshalb bleibt keine Farbe an einem Fach hängen, das es nicht
    /// mehr gibt. `ohneZeile` blendet die Zeile aus, über die gerade entschieden
    /// wird — sie soll ihre eigene Fachfarbe nicht bestimmen.
    func fachfarbenWirksam(ohneZeile ausgeblendet: Int? = nil) -> [String: Int] {
        var karte: [String: Int] = [:]
        for (stelle, klasse) in klassen.enumerated()
        where stelle != ausgeblendet && !klasse.farbeManuell && Farbwelt.istGueltig(klasse.farbe) {
            let schluessel = Farbwelt.fachSchluessel(klasse.fach)
            guard !schluessel.isEmpty, karte[schluessel] == nil else { continue }
            karte[schluessel] = klasse.farbe
        }
        for (schluessel, wert) in fachfarben {
            if let stelle = Farbwelt.stelle(wert) { karte[schluessel] = stelle }
        }
        return karte
    }

    /// Die Farbe, der die Zeilen eines Fachs folgen.
    func fachfarbe(_ fach: String) -> Int? {
        fachfarbenWirksam()[Farbwelt.fachSchluessel(fach)]
    }

    /// Ob die Planung dieses Fach schon kennt — festgelegt oder an einer Zeile.
    /// Eine Frage nach dem Namen, nicht nach der Farbe: Nach einer Farbe zu
    /// fragen überginge ein Fach, dessen Zeilen alle von Hand gefärbt sind.
    func kenntFach(_ fach: String) -> Bool {
        let schluessel = Farbwelt.fachSchluessel(fach)
        guard !schluessel.isEmpty else { return false }
        return fachfarben[schluessel] != nil
            || klassen.contains { Farbwelt.fachSchluessel($0.fach) == schluessel }
    }

    /// Jede Zeile bekommt eine Farbe: die ihres Fachs, sonst die nächste freie.
    /// Wortgleich in der Ansichtsfassung.
    mutating func farbenVervollstaendigen() {
        var karte = fachfarbenWirksam()
        var nutzung = farbnutzung
        for stelle in klassen.indices where !Farbwelt.istGueltig(klassen[stelle].farbe) {
            let schluessel = Farbwelt.fachSchluessel(klassen[stelle].fach)
            let farbe = karte[schluessel] ?? Farbwelt.naechsteFreieFarbe(nutzung)
            klassen[stelle].farbe = farbe
            nutzung[farbe, default: 0] += 1
            if !schluessel.isEmpty, !klassen[stelle].farbeManuell, karte[schluessel] == nil {
                karte[schluessel] = farbe
            }
        }
    }

    /// Nach einer Änderung an einer Zeile: Sie folgt der Farbe ihres Fachs.
    /// Bestimmt sie diese selbst, trägt sie aber noch die eines anderen Fachs,
    /// weicht sie aus — sonst sähen zwei Fächer gleich aus.
    mutating func farbeNachziehen(zeile stelle: Int) {
        guard klassen.indices.contains(stelle), !klassen[stelle].farbeManuell else { return }
        let schluessel = Farbwelt.fachSchluessel(klassen[stelle].fach)
        let karte = fachfarbenWirksam(ohneZeile: stelle)
        if let farbe = karte[schluessel] {
            klassen[stelle].farbe = farbe
            return
        }
        let eigene = klassen[stelle].farbe
        let fremd = !schluessel.isEmpty && karte.values.contains(eigene)
        if !Farbwelt.istGueltig(eigene) || fremd {
            klassen[stelle].farbe = Farbwelt.naechsteFreieFarbe(farbnutzung)
        }
    }
}

// ── Zellenverzeichnis ─────────────────────────────────────────────────────

/// Die Vorhaben einer Planung, nach Klasse/Kurs und Woche vorsortiert —
/// `Planung.vorhaben(klasse:woche:)` geht je Frage die ganze Liste durch.
struct Zellenverzeichnis {
    private let nachKurs: [String: [Int: [Vorhaben]]]

    init(_ planung: Planung) {
        var karte: [String: [Int: [Vorhaben]]] = [:]
        for eintrag in planung.eintraege {
            karte[eintrag.klasseId, default: [:]][eintrag.woche, default: []].append(eintrag)
        }
        nachKurs = karte
    }

    subscript(klasse: String, woche: Int) -> [Vorhaben] { nachKurs[klasse]?[woche] ?? [] }

    func kurs(_ klasse: String) -> [Int: [Vorhaben]] { nachKurs[klasse] ?? [:] }
}

// ── Kennungen ─────────────────────────────────────────────────────────────

enum Kennung {
    /// Vorsatz, Zeitanteil, Zufallsanteil — eindeutig genug fürs Zusammenführen.
    static func neu(_ vorsatz: String) -> String {
        let zeit = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let zeichen = "abcdefghijklmnopqrstuvwxyz0123456789"
        let zufall = String((0..<5).map { _ in zeichen.randomElement() ?? "0" })
        return "\(vorsatz)-\(zeit)-\(zufall)"
    }
}

// ── Standarddatensatz ─────────────────────────────────────────────────────

/// Die hinterlegte Ausgangsliste.
enum Standardkurse {
    static let liste: [(name: String, fach: String)] = [
        ("F5b", "Biologie"),
        ("G5", "Biologie"),
        ("G6a", "Biologie"),
        ("G6a", "Geographie"),
        ("G6a", "Informatik"),
        ("G8", "Informatik"),
        ("G9", "Chemie"),
        ("H7a", "WPU Informatik"),
        ("H9", "WPU Informatik"),
        ("R7b", "Informatik"),
        ("R9a", "Informatik"),
        ("R9b", "Informatik"),
        ("AG", "LEGO-Robotik"),
    ]

    /// Ohne Farbe: Erst in einer Planung ist bekannt, welche schon vergeben
    /// sind — `farbenVervollstaendigen()` holt das nach.
    static func aufbauen(_ roh: [(name: String, fach: String)]) -> [Klasse] {
        return roh.prefix(Kennwerte.maxKlassen).map { eintrag in
            let name = eintrag.name.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Ohne Bezeichnung" : eintrag.name.trimmingCharacters(in: .whitespaces)
            return Klasse(id: Kennung.neu("k"), name: name,
                          fach: eintrag.fach.trimmingCharacters(in: .whitespaces), notiz: "",
                          farbe: Farbwelt.ohneFarbe, farbeManuell: false)
        }
    }
}

// ── Eingabezeilen ─────────────────────────────────────────────────────────

/// Je Zeile eine Klasse oder ein Kurs; ein Fach lässt sich mit „ – “ anhängen.
/// Die Leerzeichen um den Strich sind Pflicht — sonst bräche „AG – LEGO-Robotik“
/// falsch, und „7a-Sport“ verlöre seinen Bindestrich.
enum Kurszeilen {
    struct Fehler: Identifiable, Hashable, Sendable {
        var id: Int { nummer }
        let nummer: Int
        let zeile: String
        let grund: String
    }

    struct Ergebnis: Sendable {
        var kurse: [(name: String, fach: String)] = []
        var fehler: [Fehler] = []
    }

    private static let zeilenmuster = Zeilenmuster()
    private static let strichVorn = Muster(#"^[-–](\s|$)"#)
    private static let strichHinten = Muster(#"(\s|^)[-–]$"#)

    /// Eigener Halter, damit die übersetzte Form geteilt werden kann, ohne die
    /// Nebenläufigkeitsprüfung zu umgehen.
    private struct Zeilenmuster: @unchecked Sendable {
        let ausdruck = try? NSRegularExpression(pattern: #"^(.+?)\s+[-–]\s+(.+)$"#)
    }

    static func pruefen(_ text: String) -> Ergebnis {
        var ergebnis = Ergebnis()
        for (stelle, roh) in text.components(separatedBy: "\n").enumerated() {
            // .whitespacesAndNewlines wegen des \r aus Windows-Text.
            let zeile = roh.trimmingCharacters(in: .whitespacesAndNewlines)
            if zeile.isEmpty { continue }

            let bereich = NSRange(zeile.startIndex..., in: zeile)
            if let treffer = zeilenmuster.ausdruck?.firstMatch(in: zeile, range: bereich),
               let ersterBereich = Range(treffer.range(at: 1), in: zeile),
               let zweiterBereich = Range(treffer.range(at: 2), in: zeile) {
                let name = String(zeile[ersterBereich])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fach = String(zeile[zweiterBereich])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ergebnis.kurse.append((name, fach))
                continue
            }

            if strichVorn.trifft(zeile) {
                ergebnis.fehler.append(Fehler(
                    nummer: stelle + 1, zeile: zeile,
                    grund: "Vor dem Strich fehlt die Klasse bzw. der Kurs."))
                continue
            }
            if strichHinten.trifft(zeile) {
                ergebnis.fehler.append(Fehler(
                    nummer: stelle + 1, zeile: zeile,
                    grund: "Nach dem Strich fehlt das Fach. Ohne Fach genügt die "
                         + "Klasse bzw. der Kurs allein."))
                continue
            }

            ergebnis.kurse.append((zeile, ""))
        }
        return ergebnis
    }
}
