// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Die Ansage des Melders für VoiceOver (B86, E422) ──────────────────────────────────────────────
// Kommen mehrere Meldungen in einer Änderung — vorgemerkte nach dem Schließen eines Blatts, mehrere
// Hinweise auf einmal —, sagt der Melder alle neuen in einer Ansage an, in ihrer Reihenfolge: VoiceOver
// unterbricht rasche Folgen einzelner Ansagen. Eine Warnung sagt, dass sie eine ist — Symbol und Farbe in der
// Kapsel hört niemand (E422, V3 b). Geprüft wird der Text als reine Funktion; das Sprechen selbst ist eine Handprobe.

@Suite("Ansage der Meldungen für VoiceOver: alle neuen in einer Ansage")
struct MeldungsansagePruefungen {

    @Test("Zwei Meldungen auf einmal: eine Ansage mit beiden, in ihrer Reihenfolge")
    func zweiAufEinmal() {
        let a = Meldung(text: "„Schuljahr 2026/27“ wurde nicht geöffnet, weil ein Blatt offen war.", art: .warnung)
        let b = Meldung(text: "„Schuljahr 2025/26“ wurde nicht geöffnet, weil ein Blatt offen war.", art: .warnung)
        let text = Melder.ansagetext(bisher: [], jetzt: [a, b])
        #expect(text == "Warnung: " + a.text + " Warnung: " + b.text)
    }

    @Test("Eine Warnung geht neben einem Hinweis nach ihr nicht verloren")
    func warnungVorHinweis() {
        let warnung = Meldung(text: "Die Sitzpläne ließen sich nicht sichern.", art: .warnung)
        let hinweis = Meldung(text: "Planung „Schuljahr 2026/27“ geladen.", art: .hinweis)
        let text = Melder.ansagetext(bisher: [], jetzt: [warnung, hinweis])
        #expect(text == "Warnung: " + warnung.text + " " + hinweis.text)
    }

    @Test("Ohne Satzzeichen am Ende trennt ein Punkt die Texte; der letzte bleibt wörtlich")
    func punktZwischen() {
        let a = Meldung(text: "3 Vorhaben eingefügt", art: .hinweis)
        let b = Meldung(text: "Die Sitzpläne ließen sich nicht sichern (Platte voll)", art: .warnung)
        let c = Meldung(text: "Sicherungskopie geschrieben: /Planung/kopie.json", art: .hinweis)
        let text = Melder.ansagetext(bisher: [], jetzt: [a, b, c])
        #expect(text == "3 Vorhaben eingefügt. Warnung: Die Sitzpläne ließen sich nicht sichern (Platte voll). "
                + "Sicherungskopie geschrieben: /Planung/kopie.json")
    }

    @Test("Derselbe Text in einer Änderung: einmal angesagt, an seiner ersten Stelle")
    func derselbeTextEinmal() {
        let a = Meldung(text: "Die Sitzpläne ließen sich nicht sichern.", art: .warnung)
        let b = Meldung(text: "Planung als JSON gesichert.", art: .hinweis)
        let c = Meldung(text: "Die Sitzpläne ließen sich nicht sichern.", art: .warnung)
        let text = Melder.ansagetext(bisher: [], jetzt: [a, b, c])
        #expect(text == "Warnung: " + a.text + " " + b.text)
    }

    @Test("Ein Hinweis und eine Warnung mit gleichem Text: zwei Teile — einmal gilt dem gesprochenen Text (Z-AU8-06)")
    func gleicherTextVerschiedeneArt() {
        let hinweis = Meldung(text: "Planung als JSON gesichert.", art: .hinweis)
        let warnung = Meldung(text: "Planung als JSON gesichert.", art: .warnung)
        let text = Melder.ansagetext(bisher: [], jetzt: [hinweis, warnung])
        #expect(text == "Planung als JSON gesichert. Warnung: Planung als JSON gesichert.")
    }

    @Test("Kommt eine neue, während eine alte verfällt, wird sie angesagt")
    func neueBeimVerfallen() {
        let alt = Meldung(text: "Planung als JSON gesichert.", art: .hinweis)
        let neu = Meldung(text: "Die Sitzpläne ließen sich nicht sichern.", art: .warnung)
        let text = Melder.ansagetext(bisher: [alt.id], jetzt: [neu])
        #expect(text == "Warnung: " + neu.text)
    }

    @Test("Eine schon angesagte Meldung kommt nicht noch einmal")
    func angesagteNichtNochmal() {
        let a = Meldung(text: "Die Sitzpläne ließen sich nicht sichern.", art: .warnung)
        let b = Meldung(text: "Planung als JSON gesichert.", art: .hinweis)
        let text = Melder.ansagetext(bisher: [a.id], jetzt: [a, b])
        #expect(text == b.text)
    }

    @Test("Verfällt eine nur oder steht keine, gibt es keine Ansage")
    func nurVerfallen() {
        let a = Meldung(text: "Die Sitzpläne ließen sich nicht sichern.", art: .warnung)
        let b = Meldung(text: "Planung als JSON gesichert.", art: .hinweis)
        let verfallen = Melder.ansagetext(bisher: [a.id, b.id], jetzt: [b])
        #expect(verfallen == nil)
        let leer = Melder.ansagetext(bisher: [], jetzt: [])
        #expect(leer == nil)
    }

    @Test("Ein einzelner Hinweis wird wörtlich angesagt, auch ohne Satzzeichen")
    func einzelneWoertlich() {
        let a = Meldung(text: "3 Vorhaben eingefügt", art: .hinweis)
        let text = Melder.ansagetext(bisher: [], jetzt: [a])
        #expect(text == "3 Vorhaben eingefügt")
    }

    @Test("Auch eine einzelne Warnung sagt, dass sie eine ist (E422, V3 b)")
    func einzelneWarnung() {
        let a = Meldung(text: "Die Sitzpläne ließen sich nicht sichern.", art: .warnung)
        let text = Melder.ansagetext(bisher: [], jetzt: [a])
        #expect(text == "Warnung: Die Sitzpläne ließen sich nicht sichern.")
    }

    @Test("Derselbe Text unter neuer Kennung, während die alte Kapsel noch steht: angesagt — einmal gilt nur in einer Änderung (Z-AU8-01)")
    func derselbeTextNeueKennung() {
        let alt = Meldung(text: "Planung als JSON gesichert.", art: .hinweis)
        let neu = Meldung(text: "Planung als JSON gesichert.", art: .hinweis)
        let text = Melder.ansagetext(bisher: [alt.id], jetzt: [alt, neu])
        #expect(text == neu.text)
    }

    @Test("Endet ein Text mit „?“ oder „…“, kommt kein Punkt dazu (Z-AU8-03)")
    func andereSatzzeichen() {
        let a = Meldung(text: "Wirklich gesichert?", art: .hinweis)
        let b = Meldung(text: "Die Sicherung läuft …", art: .hinweis)
        let c = Meldung(text: "Fertig", art: .hinweis)
        let text = Melder.ansagetext(bisher: [], jetzt: [a, b, c])
        #expect(text == "Wirklich gesichert? Die Sicherung läuft … Fertig")
    }
}
