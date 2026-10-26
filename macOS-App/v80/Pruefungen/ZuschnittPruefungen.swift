// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Wiederholbarer Zufall (LCG) — dieselben Fälle in jedem Lauf.
private struct Wuerfel {
    var zustand: UInt64
    mutating func naechste(_ n: Int) -> Int {
        zustand = zustand &* 6364136223846793005 &+ 1442695040888963407
        return Int((zustand >> 33) % UInt64(n))
    }
}

/// Die Bausteine an der Grenze: jede Art Leerraum, die `trimmingCharacters`
/// kennt, ein Zeilenpaar, kombinierende Zeichen, Steuerzeichen, ein Emoji aus
/// mehreren Skalaren — und Buchstaben dazwischen.
private let bausteine: [String] = [
    "a", "b", " ", "\t", "\n", "\r\n", "\r", "\u{00A0}", "\u{2028}", "\u{3000}", "\u{0085}",
    "\u{0301}", "\u{7}", "\u{202E}", "\u{FEFF}", "é", "\u{1F469}\u{200D}\u{1F4BB}",
]

/// Ein Text, der die Grenze knapp überschreitet oder knapp darunter bleibt:
/// `grenze - 0…5` Buchstaben, dann ein Ende aus 1–8 Bausteinen.
private func anDerGrenze(_ w: inout Wuerfel, grenze: Int) -> String {
    let ende = (0..<(1 + w.naechste(8))).map { _ in bausteine[w.naechste(bausteine.count)] }.joined()
    return String(repeating: "a", count: grenze - w.naechste(6)) + ende
}

/// Der Zuschnitt an der Schranke vor der Datei ist idempotent (E208, R73-02,
/// v74): Was einmal zugeschnitten ist, kommt beim nächsten Sichern unverändert
/// heraus. Bis 1.9.2 wurde getrimmt und dann gekappt — das Kappen legte
/// Leerraum am Ende frei, und das nächste Sichern nahm ihn still weg.
@Suite("Zuschnitt: einmal zugeschnitten, bleibt es beim nächsten Sichern")
@MainActor
struct ZuschnittPruefungen {

    private func speicher() throws -> Planungsspeicher {
        let planung = Planung.leer(titel: "Zuschnitt", start: try #require(Tag(iso: "2026-08-10")),
                                   wochen: 6, basis: "",
                                   klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                                   fachfarben: [:])
        return Planungsspeicher(vorschau: planung)
    }

    @Test("Das Beispiel der Review: N−1 Buchstaben, Leerraum, ein Buchstabe — bei jeder Art Leerraum")
    func beispielDerReview() {
        let n = Planungsdatei.maxNamenslaenge
        for rand in [" ", "\t", "\n", "\r\n", "\u{00A0}", "\u{2028}", "\u{3000}", "\u{0085}"] {
            let eingabe = String(repeating: "a", count: n - 1) + rand + "b"
            let erst = VorhabenEntwurf.bezeichnung(eingabe, ersatz: "Ersatz")
            let zweit = VorhabenEntwurf.bezeichnung(erst.text, ersatz: "Ersatz")
            #expect(erst.text == zweit.text, "Leerraum U+\(String(rand.unicodeScalars.first!.value, radix: 16))")
            #expect(erst.gekuerzt && !zweit.gekuerzt, "gekürzt heißt: die Grenze griff — beim ersten Mal, nicht beim zweiten")
        }
    }

    @Test("Die Funktion selbst: idempotent für beide Zeichenmengen, gekürzt nur beim ersten Mal", arguments: [
        CharacterSet.whitespacesAndNewlines, CharacterSet.whitespaces,
    ])
    func funktion(leerraum: CharacterSet) {
        var w = Wuerfel(zustand: 74)
        var abweichend = 0, zweimalGekuerzt = 0
        for _ in 0..<1000 {
            let grenze = 5 + w.naechste(20)
            let einmal = Planungsdatei.zugeschnitten(anDerGrenze(&w, grenze: grenze), grenze: grenze, leerraum: leerraum)
            let zweimal = Planungsdatei.zugeschnitten(einmal.text, grenze: grenze, leerraum: leerraum)
            if zweimal.text != einmal.text { abweichend += 1 }
            if zweimal.gekuerzt { zweimalGekuerzt += 1 }
            #expect(einmal.text.count <= grenze)
        }
        #expect(abweichend == 0 && zweimalGekuerzt == 0,
                "\(abweichend) abweichend, \(zweimalGekuerzt) beim zweiten Mal gekürzt, von 1 000")
    }

    @Test("Invariante über 1 000 erzeugte Bezeichnungen: zweimal zugeschnitten ist einmal zugeschnitten")
    func invarianteBezeichnung() {
        var w = Wuerfel(zustand: 20260918)
        var abweichend = 0
        for _ in 0..<1000 {
            let einmal = VorhabenEntwurf.bezeichnung(anDerGrenze(&w, grenze: Planungsdatei.maxNamenslaenge),
                                                     ersatz: "Ersatz").text
            if VorhabenEntwurf.bezeichnung(einmal, ersatz: "Ersatz").text != einmal { abweichend += 1 }
        }
        #expect(abweichend == 0, "\(abweichend) von 1 000 änderten sich beim zweiten Mal")
    }

    @Test("Invariante über 1 000 erzeugte Titel: Sichern, im Blatt öffnen, unverändert sichern")
    func invarianteSichern() throws {
        let s = try speicher()
        let kurs = try #require(s.planung?.klassen.first?.id)
        var w = Wuerfel(zustand: 20260919)
        var abweichend = 0
        for _ in 0..<1000 {
            var entwurf = VorhabenEntwurf(klasseId: kurs, woche: 0)
            entwurf.titel = anDerGrenze(&w, grenze: Planungsdatei.maxNamenslaenge)
            s.vorhabenSichern(entwurf)
            let erst = try #require(s.planung?.eintraege.last)
            s.vorhabenSichern(VorhabenEntwurf(erst))
            if s.planung?.eintraege.last?.titel != erst.titel { abweichend += 1 }
        }
        #expect(abweichend == 0, "\(abweichend) von 1 000 Titeln änderten sich beim zweiten Sichern")
    }

    @Test("Zweimal sichern: kein Feld ändert sich, „gekürzt“ meldet nur das erste Sichern")
    func zweimalSichern() throws {
        let s = try speicher()
        let n = Planungsdatei.maxNamenslaenge
        let t = Planungsdatei.maxTextlaenge
        var entwurf = VorhabenEntwurf(klasseId: try #require(s.planung?.klassen.first?.id), woche: 0)
        entwurf.titel = String(repeating: "a", count: n - 1) + " b"
        entwurf.text = String(repeating: "a", count: t - 1) + "\nb"
        entwurf.kommentar = String(repeating: "a", count: t - 1) + " b"
        entwurf.hausaufgabe = true
        entwurf.hausaufgabenText = String(repeating: "a", count: n - 1) + " b"
        entwurf.links = [Weblink(titel: String(repeating: "a", count: n - 1) + " b", adresse: "https://example.org/")]
        entwurf.materialien = [Material(titel: String(repeating: "a", count: n - 1) + "\tb", pfad: "/tmp/blatt.pdf")]
        let vorher = s.meldungen.count
        s.vorhabenSichern(entwurf)
        let erst = try #require(s.planung?.eintraege.first)
        let nachErst = s.meldungen.count
        s.vorhabenSichern(VorhabenEntwurf(erst))
        let zweit = try #require(s.planung?.eintraege.first)
        #expect(zweit.titel == erst.titel && erst.titel.count == n - 1, "Titel")
        #expect(zweit.text == erst.text && erst.text.count == t - 1, "Beschreibung")
        #expect(zweit.kommentar == erst.kommentar && erst.kommentar.count == t - 1, "Kommentar")
        #expect(zweit.hausaufgabenText == erst.hausaufgabenText && erst.hausaufgabenText.count == n - 1, "Hausaufgabe")
        #expect(zweit.links.map(\.titel) == erst.links.map(\.titel) && erst.links.first?.titel.count == n - 1, "Link")
        #expect(zweit.materialien.map(\.titel) == erst.materialien.map(\.titel)
                && erst.materialien.first?.titel.count == n - 1, "Material")
        #expect(nachErst > vorher, "das erste Sichern meldet das Kürzen")
        #expect(s.meldungen.count == nachErst, "das zweite Sichern hat nichts zu melden")
    }
}
