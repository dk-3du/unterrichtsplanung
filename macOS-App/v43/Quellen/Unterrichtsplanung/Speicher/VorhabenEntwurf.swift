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
    var kommentar: String

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
        var kommentar: String
    }

    init(_ vorhaben: Vorhaben) {
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
        kommentar = vorhaben.kommentar
        ausgangsstand = Stand(titel: titel, text: text, klasseId: klasseId, woche: woche,
                              erledigt: erledigt, materialien: materialien, links: links,
                              pruefung: pruefung, pruefungstag: pruefungstag,
                              datum: datum, dringend: dringend, kommentar: kommentar)
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
        kommentar = ""
        ausgangsstand = Stand(titel: "", text: "", klasseId: klasseId, woche: woche,
                              erledigt: false, materialien: [], links: [],
                              pruefung: false, pruefungstag: nil,
                              datum: nil, dringend: false, kommentar: "")
    }

    var istNeu: Bool { vorhabenId == nil }

    /// Wie `Vorhaben.wochentag`: abgeleitet aus dem Datum, kein eigener Stand.
    var wochentag: Wochentag? { datum?.wochentag }

    /// Escape schließt einen Dialog von Haus aus ohne Rückfrage — eine eben
    /// getippte Beschreibung wäre damit verloren.
    var veraendert: Bool {
        Stand(titel: titel, text: text, klasseId: klasseId, woche: woche,
              erledigt: erledigt, materialien: materialien, links: links,
              pruefung: pruefung, pruefungstag: pruefungstag,
              datum: datum, dringend: dringend, kommentar: kommentar) != ausgangsstand
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

    func gereinigteLinks() -> [Weblink] {
        links.compactMap { link in
            guard let adresse = Weblinks.pruefen(link.adresse) else { return nil }
            let titel = link.titel.trimmingCharacters(in: .whitespaces)
            return Weblink(id: link.id, titel: titel.isEmpty ? Weblinks.name(adresse) : titel,
                           adresse: adresse)
        }
    }
}
