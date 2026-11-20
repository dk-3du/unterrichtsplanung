// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import Unterrichtsplanung

/// Zurück und Vorwärts der Blätter mit Seitenleiste (v95, E1102, R-BG5-02): der Verlauf ohne Fenster — wie der Rahmen ihn
/// führt: Jeder Wechsel der Auswahl kommt über `onChange` mit alt und neu herein, ein Schritt im Verlauf setzt die Auswahl.
/// ⌘[ und ⌘] am Fenster prüft die Dialogprobe („Vorhaben-Blatt · Leiste“).
@Suite("Verlauf der Blätter mit Seitenleiste")
struct BlaetterverlaufPruefungen {

    /// Ein Blatt im Kleinen: die Auswahl und ihr Verlauf.
    private struct Blatt {
        var verlauf = Blaetterverlauf<String>()
        var auswahl = "A"

        /// Die Auswahl ändert sich; `onChange` meldet alt und neu.
        mutating func waehlen(_ neu: String) {
            let alt = auswahl
            auswahl = neu
            verlauf.gewechselt(von: alt, zu: neu)
        }

        /// Zurück bzw. Vorwärts wie der Knopf: das Ziel setzt die Auswahl, ihr Wechsel kommt herein.
        mutating func zurueck() -> Bool {
            guard let ziel = verlauf.schrittZurueck(von: auswahl) else { return false }
            waehlen(ziel)
            return true
        }

        mutating func vor() -> Bool {
            guard let ziel = verlauf.schrittVorwaerts(von: auswahl) else { return false }
            waehlen(ziel)
            return true
        }
    }

    @Test("Beim Öffnen leer: Zurück und Vorwärts gesperrt, ein Schritt ins Leere lässt nichts zurück")
    func leer() {
        var blatt = Blatt()
        #expect(!blatt.verlauf.kannZurueck && !blatt.verlauf.kannVorwaerts)
        #expect(!blatt.zurueck() && !blatt.vor() && blatt.auswahl == "A")
        #expect(!blatt.verlauf.kannZurueck && !blatt.verlauf.kannVorwaerts)
    }

    @Test("A → B → C, zweimal zurück, einmal vor: B, A, B — ein Schritt im Verlauf wird nicht noch einmal vermerkt")
    func folge() {
        var blatt = Blatt()
        blatt.waehlen("B")
        blatt.waehlen("C")
        #expect(blatt.zurueck() && blatt.auswahl == "B")
        #expect(blatt.zurueck() && blatt.auswahl == "A")
        #expect(!blatt.verlauf.kannZurueck && blatt.verlauf.kannVorwaerts)
        #expect(blatt.vor() && blatt.auswahl == "B")
        #expect(blatt.verlauf.rueckwaerts == ["A"] && blatt.verlauf.vorwaerts == ["C"])
        #expect(blatt.vor() && blatt.auswahl == "C" && !blatt.verlauf.kannVorwaerts)
    }

    @Test("Ein neuer Wechsel nach einem Schritt zurück leert Vorwärts")
    func neuerWechsel() {
        var blatt = Blatt()
        blatt.waehlen("B")
        blatt.waehlen("C")
        #expect(blatt.zurueck() && blatt.auswahl == "B")
        blatt.waehlen("D")
        #expect(!blatt.verlauf.kannVorwaerts)
        #expect(blatt.verlauf.rueckwaerts == ["A", "B"])
        #expect(blatt.zurueck() && blatt.auswahl == "B")
    }

    @Test("Zwei Schritte zurück, ehe der erste Wechsel ankommt: ein Wechsel C → A, nichts doppelt vermerkt")
    func zweiSchritteVorDemWechsel() {
        var verlauf = Blaetterverlauf<String>()
        verlauf.gewechselt(von: "A", zu: "B")
        verlauf.gewechselt(von: "B", zu: "C")
        let erstes = verlauf.schrittZurueck(von: "C")
        let zweites = verlauf.schrittZurueck(von: erstes ?? "")
        #expect(erstes == "B" && zweites == "A")
        verlauf.gewechselt(von: "C", zu: "A")
        #expect(verlauf.rueckwaerts.isEmpty && verlauf.vorwaerts == ["C", "B"])
    }

    @Test("Seitenwechsel: das erste Zeichnen zählt nicht, dieselbe Auswahl nicht, jede andere einmal (R-BG8-W2-03)")
    @MainActor
    func seitenwechselZaehlt() {
        let zaehler = Seitenwechsel()
        zaehler.zeichnet("A")
        zaehler.zeichnet("A")
        #expect(zaehler.stand == 0)
        zaehler.zeichnet("B")
        zaehler.zeichnet("B")
        zaehler.zeichnet("A")
        #expect(zaehler.stand == 2)
    }

    @Test("Ohne Obergrenze: nach 500 Wechseln führen 500 Schritte zurück an den Anfang")
    func ohneObergrenze() {
        var blatt = Blatt()
        for stelle in 1...500 { blatt.waehlen("E\(stelle)") }
        var schritte = 0
        // Höchstens ein Schritt zu viel — vermerkte der Verlauf seine eigenen Schritte, liefe er sonst ohne Ende.
        while schritte <= 500, blatt.zurueck() { schritte += 1 }
        #expect(schritte == 500 && blatt.auswahl == "A")
    }
}
