// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Der Arbeitsstand des Vorhaben-Dialogs. Erst „Übernehmen“ schreibt ihn in die
/// Planung zurück.
struct VorhabenEntwurf: Identifiable, Equatable {
    /// Kennung dieser **Bearbeitung**, nicht die des Vorhabens — damit der
    /// Dialog auch beim zweiten neuen Vorhaben wieder aufgeht.
    let id = UUID()
    /// Kennung des bearbeiteten Vorhabens; nil bei einem neuen.
    let vorhabenId: String?
    var titel: String
    var text: String
    var klasseId: String
    var woche: Int
    var erledigt: Bool
    var materialien: [Material]
    var links: [Weblink]
    var pruefung: Bool
    var pruefungstag: Tag?
    var datum: Tag?
    var dringend: Bool
    var korrektur: Bool
    var kommentar: String
    var hausaufgabe: Bool
    var hausaufgabenText: String
    /// „Als Termin führen“ (E293, E295) — mit Uhrzeit und Personen aus der
    /// Lernendenverwaltung; geschrieben wird der Termin beim Übernehmen.
    var termin: Bool
    var terminzeit: String
    var terminpersonen: [String]

    private let ausgangsstand: Stand

    private struct Stand: Equatable {
        var titel: String
        var text: String
        var klasseId: String
        var woche: Int
        var erledigt: Bool
        var materialien: [Material]
        var links: [Weblink]
        var pruefung: Bool
        var pruefungstag: Tag?
        var datum: Tag?
        var dringend: Bool
        var korrektur: Bool
        var kommentar: String
        var hausaufgabe: Bool
        var hausaufgabenText: String
        var termin: Bool
        var terminzeit: String
        var terminpersonen: [String]
    }

    /// `terminpersonen`: die Personen des Termins, wenn das Vorhaben einer ist.
    init(_ vorhaben: Vorhaben, terminpersonen: [String] = []) {
        vorhabenId = vorhaben.id
        titel = vorhaben.titel
        text = vorhaben.text
        klasseId = vorhaben.klasseId
        woche = vorhaben.woche
        erledigt = vorhaben.erledigt
        materialien = vorhaben.materialien
        links = vorhaben.links
        pruefung = vorhaben.pruefung
        pruefungstag = vorhaben.pruefungstag
        datum = vorhaben.datum
        dringend = vorhaben.dringend
        korrektur = vorhaben.korrektur
        kommentar = vorhaben.kommentar
        hausaufgabe = vorhaben.hausaufgabe
        hausaufgabenText = vorhaben.hausaufgabenText
        termin = vorhaben.istTermin
        terminzeit = vorhaben.terminzeit
        self.terminpersonen = vorhaben.istTermin ? terminpersonen : []
        ausgangsstand = Stand(titel: titel, text: text, klasseId: klasseId, woche: woche,
                              erledigt: erledigt, materialien: materialien, links: links,
                              pruefung: pruefung, pruefungstag: pruefungstag,
                              datum: datum, dringend: dringend, korrektur: korrektur, kommentar: kommentar,
                              hausaufgabe: hausaufgabe, hausaufgabenText: hausaufgabenText,
                              termin: termin, terminzeit: terminzeit, terminpersonen: self.terminpersonen)
    }

    init(klasseId: String, woche: Int) {
        vorhabenId = nil
        titel = ""
        text = ""
        self.klasseId = klasseId
        self.woche = woche
        erledigt = false
        materialien = []
        links = []
        pruefung = false
        pruefungstag = nil
        datum = nil
        dringend = false
        korrektur = false
        kommentar = ""
        hausaufgabe = false
        hausaufgabenText = ""
        termin = false
        terminzeit = ""
        terminpersonen = []
        ausgangsstand = Stand(titel: "", text: "", klasseId: klasseId, woche: woche,
                              erledigt: false, materialien: [], links: [],
                              pruefung: false, pruefungstag: nil,
                              datum: nil, dringend: false, korrektur: false, kommentar: "",
                              hausaufgabe: false, hausaufgabenText: "",
                              termin: false, terminzeit: "", terminpersonen: [])
    }

    var istNeu: Bool { vorhabenId == nil }

    /// Ob das Vorhaben als Termin geschrieben wird: Prüfung und Korrektur gehen vor (E293).
    var alsTermin: Bool { termin && !pruefung && !korrektur }

    /// Der Grund, der in „Grundlegendes“ zu beheben ist — dort stehen die Wochentage (E732).
    static let terminOhneTag = "Ein Termin braucht einen Tag — bitte einen Wochentag wählen."

    /// Was einem Termin noch fehlt — `nil`, wenn er so geschrieben werden kann.
    var terminFehlt: String? { terminFehlt(verwaltungOffen: true) }

    /// Was einem Termin noch fehlt, je nachdem, ob die Lernendenverwaltung offen ist. Ohne sie kennt das Blatt die
    /// Personen eines schon bestehenden Termins nicht — sie werden nicht geprüft, der Termin bleibt, wie er war (E721).
    func terminFehlt(verwaltungOffen: Bool) -> String? {
        guard alsTermin else { return nil }
        if verwaltungOffen || !ausgangsstand.termin {
            if terminpersonen.isEmpty { return "Ein Termin braucht mindestens eine Person." }
            if terminpersonen.count > Kennwerte.maxMitgliederJeLerngruppe {
                return "Ein Termin hat höchstens \(Kennwerte.maxMitgliederJeLerngruppe) Personen."
            }
        }
        if datum == nil { return Self.terminOhneTag }
        if Lernendenbestand.uhrzeit(terminzeit) == nil { return "Die Uhrzeit bitte als hh:mm, etwa 07:45 — oder leer lassen." }
        return nil
    }

    /// War das Vorhaben ein Termin und soll keiner mehr sein — dann geht der Termin (E295).
    var terminAbgeschaltet: Bool { ausgangsstand.termin && !alsTermin }

    /// War das Vorhaben beim Öffnen schon ein Termin — ohne offene Verwaltung bleibt er, wie er war (E721).
    var warTermin: Bool { ausgangsstand.termin }

    /// Ob der Schalter „Als Termin führen“ gesperrt ist: mit Prüfung oder Korrektur (entweder–oder), ohne offene
    /// Verwaltung nur für ein Vorhaben, das kein Termin war — ein bestehender lässt sich aus- und wieder einschalten
    /// (E721, G1-01).
    func terminSchalterGesperrt(verwaltungOffen: Bool) -> Bool {
        pruefung || korrektur || (!verwaltungOffen && !termin && !warTermin)
    }

    /// Ob das Blatt den Haken bzw. den Kommentar gegenüber seinem Ausgangsstand
    /// geändert hat — die beiden Felder, die sich die App mit der Ansicht fürs
    /// iPad teilt. `vorhabenSichern` schreibt sie nur dann (E122): Ein Stand
    /// vom iPad, der die Planung erreicht, während das Blatt offen ist, wird
    /// sonst vom unberührten Ausgangsstand überschrieben und ausgestempelt.
    var hakenGeaendert: Bool { erledigt != ausgangsstand.erledigt }
    var kommentarGeaendert: Bool { kommentar != ausgangsstand.kommentar }

    /// Wie `Vorhaben.wochentag`: abgeleitet aus dem Datum, kein eigener Stand.
    var wochentag: Wochentag? { datum?.wochentag }

    /// Escape schließt einen Dialog von Haus aus ohne Rückfrage — eine eben
    /// getippte Beschreibung wäre damit verloren.
    var veraendert: Bool {
        Stand(titel: titel, text: text, klasseId: klasseId, woche: woche,
              erledigt: erledigt, materialien: materialien, links: links,
              pruefung: pruefung, pruefungstag: pruefungstag,
              datum: datum, dringend: dringend, korrektur: korrektur, kommentar: kommentar,
              hausaufgabe: hausaufgabe, hausaufgabenText: hausaufgabenText,
              termin: termin, terminzeit: terminzeit, terminpersonen: terminpersonen) != ausgangsstand
    }

    /// Leere Linkzeilen zählen nicht (E722): Sie fallen beim Sichern still weg.
    var leer: Bool {
        titel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && materialien.isEmpty && linksMitAdresse == 0
    }

    /// Leere Zeilen stillschweigend fallen lassen, ungültige Adressen benennen.
    func ungueltigeLinks() -> [String] {
        links.compactMap { link in
            let roh = link.adresse.trimmingCharacters(in: .whitespaces)
            if roh.isEmpty { return nil }
            return Weblinks.pruefen(roh) == nil ? roh : nil
        }
    }

    /// Nur die gültigen Adressen, geprüft. Die Bezeichnung ordnet
    /// `bezeichnung(_:ersatz:)` beim Sichern — eine Reihenfolge für alle.
    func gereinigteLinks() -> [Weblink] {
        links.compactMap { link in
            guard let adresse = Weblinks.pruefen(link.adresse) else { return nil }
            return Weblink(id: link.id, titel: link.titel, adresse: adresse)
        }
    }

    /// Die Bezeichnung eines Links oder Materials, wie sie in die Datei geht
    /// (E200, R72-04, B48, v73): Steuerzeichen heraus, Leerraum an den Rändern
    /// weg, bei leer der Name, den der Leser nähme (Rechnername, Dateiname) —
    /// ebenso bereinigt —, dann gekappt. So zeigt die App nach dem Sichern, was
    /// sie beim nächsten Öffnen liest. `gekuerzt` nur, wenn die eigene
    /// Bezeichnung zu lang war. Der Zuschnitt ist `Planungsdatei.zugeschnitten`
    /// (E208, R73-02, v74): Was das Kappen am Ende freilegt, fällt gleich weg —
    /// ein zweites Sichern ändert nichts.
    static func bezeichnung(_ wert: String, ersatz: @autoclosure () -> String) -> (text: String, gekuerzt: Bool) {
        let grenze = Planungsdatei.maxNamenslaenge
        let eigene = Planungsdatei.zugeschnitten(wert, grenze: grenze)
        guard eigene.text.isEmpty else { return eigene }
        return (Planungsdatei.zugeschnitten(ersatz(), grenze: grenze).text, false)
    }
}

// ── Reiter des Vorhaben-Blatts (E372–E375, AW3-neu) ───────────────────────

/// Die sieben Reiter des Vorhaben-Blatts in ihrer Folge (Nutzer, 20.10.2026):
/// „Grundlegendes“ trägt alles vor dem Kommentar, „Links“ auch den Knopf für
/// das Material von 3ducation.org. Nur in der Sitzung, kein Feld in einer Datei.
enum Vorhabenreiter: CaseIterable, Identifiable, Sendable {
    case grundlegendes, kommentar, pruefung, termin, hausaufgabe, material, links

    var id: Self { self }

    var titel: String {
        switch self {
        case .grundlegendes: return "Grundlegendes"
        case .kommentar: return "Kommentar"
        case .pruefung: return "Prüfung"
        case .termin: return "Termin"
        case .hausaufgabe: return "Hausaufgabe"
        case .material: return "Material"
        case .links: return "Links"
        }
    }
}

extension VorhabenEntwurf {
    /// Ob ein Reiter etwas trägt (E373) — dieselben Schalter und Listen, die
    /// das Blatt auf dem Reiter zeigt. Ein Kommentar nur aus Leerraum und
    /// Steuerzeichen trägt nicht: Das Sichern schneidet ihn zu leer
    /// (`Planungsdatei.zugeschnitten`, Z-AW2a-05). „Grundlegendes“ trägt kein
    /// Kennzeichen.
    func traegt(_ reiter: Vorhabenreiter) -> Bool {
        switch reiter {
        case .grundlegendes: return false
        case .kommentar:
            return !Planungsdatei.ohneSteuerzeichen(kommentar).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .pruefung: return pruefung
        case .termin: return termin
        case .hausaufgabe: return hausaufgabe
        case .material: return !materialien.isEmpty
        case .links: return linksMitAdresse > 0
        }
    }

    /// Das Kennzeichen hinter dem Namen des Reiters (E373): „•“ am Kommentar,
    /// „✓“ an Prüfung und Hausaufgabe, die Anzahl an Termin (Personen, auch
    /// „· 0“, E572), Material und Links; nil, solange der Reiter nichts trägt.
    /// Ohne offene Verwaltung ist die Zahl eines bestehenden Termins nicht
    /// bekannt — dann „✓“ (E721).
    func kennzeichen(_ reiter: Vorhabenreiter, verwaltungOffen: Bool = true) -> String? {
        guard traegt(reiter) else { return nil }
        switch reiter {
        case .grundlegendes: return nil
        case .kommentar: return "•"
        case .pruefung, .hausaufgabe: return "✓"
        case .termin: return !verwaltungOffen && ausgangsstand.termin ? "✓" : "· \(terminpersonen.count)"
        case .material: return "· \(materialien.count)"
        case .links: return "· \(linksMitAdresse)"
        }
    }

    /// Die Linkzeilen mit einer Adresse, gültig oder nicht (E575) — eine leere
    /// Zeile zählt nicht, wie beim Prüfen (`ungueltigeLinks`).
    private var linksMitAdresse: Int {
        links.filter { !$0.adresse.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// Der Reiter mit Kennzeichen, etwa „Termin · 2“.
    func beschriftung(_ reiter: Vorhabenreiter, verwaltungOffen: Bool = true) -> String {
        kennzeichen(reiter, verwaltungOffen: verwaltungOffen).map { reiter.titel + " " + $0 } ?? reiter.titel
    }

    /// Der Reiter, auf den das Blatt wechselt, wenn „Übernehmen“ abweist
    /// (E374, E732) — in der Folge der Prüfungen beim Übernehmen: erst der
    /// leere Entwurf, dann ungültige Links, dann was dem Termin fehlt. Was in
    /// „Grundlegendes“ zu beheben ist — Titel, Beschreibung, der Tag eines
    /// Termins —, führt dorthin. nil, wenn nichts abweist.
    func reiterDesGrundes(verwaltungOffen: Bool = true) -> Vorhabenreiter? {
        if leer { return .grundlegendes }
        if !ungueltigeLinks().isEmpty { return .links }
        if let fehlt = terminFehlt(verwaltungOffen: verwaltungOffen) {
            return fehlt == Self.terminOhneTag ? .grundlegendes : .termin
        }
        return nil
    }
}
