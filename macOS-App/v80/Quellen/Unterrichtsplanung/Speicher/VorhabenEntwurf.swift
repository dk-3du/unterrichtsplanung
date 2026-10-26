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

    /// Was einem Termin noch fehlt — `nil`, wenn er so geschrieben werden kann.
    var terminFehlt: String? {
        guard alsTermin else { return nil }
        if terminpersonen.isEmpty { return "Ein Termin braucht mindestens eine Person." }
        if terminpersonen.count > Kennwerte.maxMitgliederJeLerngruppe {
            return "Ein Termin hat höchstens \(Kennwerte.maxMitgliederJeLerngruppe) Personen."
        }
        if datum == nil { return "Ein Termin braucht einen Tag — bitte einen Wochentag wählen." }
        if Lernendenbestand.uhrzeit(terminzeit) == nil { return "Die Uhrzeit bitte als hh:mm, etwa 07:45 — oder leer lassen." }
        return nil
    }

    /// War das Vorhaben ein Termin und soll keiner mehr sein — dann geht der Termin (E295).
    var terminAbgeschaltet: Bool { ausgangsstand.termin && !alsTermin }

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

    var leer: Bool {
        titel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && materialien.isEmpty && links.isEmpty
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
