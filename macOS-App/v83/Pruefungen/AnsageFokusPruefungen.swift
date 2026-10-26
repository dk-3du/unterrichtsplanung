// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Die Ansage wartet, bis der Fokus ruht (B108, E461) ────────────────────────────────────────────
// Erscheint eine Meldung im Augenblick eines Fokuswechsels — ein Dialog schließt, die App kommt aus dem
// Finder nach vorn —, spricht VoiceOver, was der Wechsel auslöst, und die Ansage entfällt, auch mit hohem
// Vorrang (Handprobe AV2). Geprüft werden die Bedingung und das Zusammenfügen als reine Funktionen; die
// Beobachter, das Warten und das Sprechen selbst belegt nur die Handprobe.

@Suite("Ansage der Meldungen: erst, wenn der Fokus ruht")
struct AnsageFokusPruefungen {

    @Test("Die App ist nicht vorn — etwa im Augenblick, in dem der Finder sie aufruft: noch keine Ansage")
    func appNichtVorn() {
        #expect(!Ansager.fokusRuht(appVorn: false, freieDialoge: 0, seitWechsel: 5))
    }

    @Test("Ein freier Dialog steht (Sichern, Öffnen): noch keine Ansage")
    func freierDialog() {
        #expect(!Ansager.fokusRuht(appVorn: true, freieDialoge: 1, seitWechsel: 5))
    }

    @Test("Der Fokus wechselte eben erst — ein Dialog schloss, ein Fenster wurde Schlüsselfenster: noch keine Ansage")
    func ebenGewechselt() {
        #expect(!Ansager.fokusRuht(appVorn: true, freieDialoge: 0, seitWechsel: Ansager.ruhe / 4))
    }

    @Test("App vorn, kein freier Dialog, der Wechsel liegt die Ruhezeit zurück: die Ansage geht hinaus")
    func ruht() {
        #expect(Ansager.fokusRuht(appVorn: true, freieDialoge: 0, seitWechsel: Ansager.ruhe))
        #expect(Ansager.fokusRuht(appVorn: true, freieDialoge: 0, seitWechsel: 60))
    }

    @Test("`zusammen` fügt mehrere Texte mit Satzende dazwischen zu einer Ansage")
    func zusammen() {
        #expect(Melder.zusammen(["Erste Meldung", "Warnung: Zweite."]) == "Erste Meldung. Warnung: Zweite.")
        #expect(Melder.zusammen(["Nur eine"]) == "Nur eine")
        #expect(Melder.zusammen([]) == "")
    }

    @Test("`ansagetexte` liefert die neuen gesprochenen Texte einzeln, ohne Doppel — zusammengefügt wird erst beim Hinausgeben")
    func einzeln() {
        let a = Meldung(text: "Planung gesichert.", art: .hinweis)
        let b = Meldung(text: "Die Datei ist kein lesbares JSON.", art: .warnung)
        let c = Meldung(text: "Planung gesichert.", art: .hinweis)
        #expect(Melder.ansagetexte(bisher: [], jetzt: [a, b, c])
                == ["Planung gesichert.", "Warnung: Die Datei ist kein lesbares JSON."])
        #expect(Melder.ansagetexte(bisher: [a.id, b.id, c.id], jetzt: [a, b, c]).isEmpty)
    }

    @Test("Steht die App hinten, wartet die Ansage ohne Takt — sie ruht, bis die App wieder vorn ist (E473, I2-05)")
    func hintenRuht() {
        #expect(Ansager.naechsterSchritt(appVorn: false, freieDialoge: 0, seitWechsel: 5, seitBeginn: 1) == .ruhen)
        #expect(Ansager.naechsterSchritt(appVorn: false, freieDialoge: 0, seitWechsel: 5, seitBeginn: Ansager.hoechstens * 4) == .ruhen)
    }

    @Test("Vorn wie bisher: sprechen, sobald der Fokus ruht, spätestens nach `hoechstens`; sonst warten")
    func vornWieBisher() {
        #expect(Ansager.naechsterSchritt(appVorn: true, freieDialoge: 0, seitWechsel: Ansager.ruhe, seitBeginn: 0) == .sprechen)
        #expect(Ansager.naechsterSchritt(appVorn: true, freieDialoge: 1, seitWechsel: 5, seitBeginn: 1) == .warten)
        #expect(Ansager.naechsterSchritt(appVorn: true, freieDialoge: 1, seitWechsel: 5, seitBeginn: Ansager.hoechstens) == .sprechen)
        #expect(Ansager.naechsterSchritt(appVorn: true, freieDialoge: 0, seitWechsel: 0, seitBeginn: 1) == .warten)
    }

    @Test("Nach dem Wiederaktivieren: Warnungen bleiben, ein Hinweis nur, solange seine Meldung steht (E473)")
    func hinweisVerfaellt() {
        let warnung = Ansageeintrag(id: UUID(), warnung: true, text: "Warnung: Die Sitzpläne ließen sich nicht sichern.")
        let steht = Ansageeintrag(id: UUID(), warnung: false, text: "Planung als PDF gesichert.")
        let fort = Ansageeintrag(id: UUID(), warnung: false, text: "Planung gesichert.")
        #expect(Ansager.nachDemAktivieren([warnung, steht, fort], stehend: [steht.id]) == [warnung, steht])
        // Derselbe Hinweis zweimal, der ältere verfallen, der jüngere steht: angesagt (Z-AV10-05).
        let alt = Ansageeintrag(id: UUID(), warnung: false, text: "Planung gesichert.")
        let jung = Ansageeintrag(id: UUID(), warnung: false, text: "Planung gesichert.")
        #expect(Ansager.nachDemAktivieren(Ansager.gesammelt([alt], [jung]), stehend: [jung.id]) == [jung])
    }

    @Test("Gesammelt wird ohne Doppel — derselbe gesprochene Text einmal, an seiner ersten Stelle, mit der jüngsten Meldung (I2-04, Z-AV10-05)")
    func gesammeltOhneDoppel() {
        let a = Ansageeintrag(id: UUID(), warnung: false, text: "Planung gesichert.")
        let b = Ansageeintrag(id: UUID(), warnung: true, text: "Warnung: Kein Zugriff.")
        let c = Ansageeintrag(id: UUID(), warnung: false, text: "Planung gesichert.")
        #expect(Ansager.gesammelt([a], [b, c]) == [c, b])
        #expect(Ansager.gesammelt([], []) == [])
    }
}
