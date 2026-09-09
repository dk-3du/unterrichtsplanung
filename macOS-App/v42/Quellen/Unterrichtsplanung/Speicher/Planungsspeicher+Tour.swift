// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Tour durch die Oberfläche ────────────────────────────────────────────────
extension Planungsspeicher {

    /// Ein Schritt der Tour: woran die Karte hängt und was sie sagt. Die Texte
    /// stehen hier, nicht in der Ansicht, damit die Prüfungen sie lesen.
    enum Tourschritt: String, CaseIterable, Sendable {
        case dateien, planung, ansicht, zelle, anlegen, frei, ohneZeile

        /// Einträge der Werkzeugleiste (Beschriftung des `Label`, ersatzweise
        /// der Anfang des Hilfetexts, in dieser Reihenfolge) — oder die
        /// Beispielzelle des Rasters. Der Breitenregler meldet AppKit keine
        /// Beschriftung; die dritte Karte hängt am Knopf daneben.
        enum Anker: Equatable, Sendable {
            case werkzeug([String])
            case zelle
        }

        var anker: Anker {
            switch self {
            case .dateien: .werkzeug(["Neue Planung"])
            case .planung, .ohneZeile: .werkzeug(["Klassen/Kurse"])
            case .ansicht: .werkzeug(["Darstellung umschalten"])
            case .zelle, .anlegen, .frei: .zelle
            }
        }

        var titel: String {
            switch self {
            case .dateien: "Planungsdateien"
            case .planung: "Die Planung einrichten"
            case .ansicht: "Suchen, Breite, Darstellung"
            case .zelle: "Das Raster"
            case .anlegen: "Ein Vorhaben anlegen"
            case .frei: "Unterrichtsfrei kennzeichnen"
            case .ohneZeile: "Noch keine Zeile"
            }
        }

        /// `zelle` nennt die Beispielzelle („G6a, KW 33“), vom Raster gesetzt.
        func text(zelle: String) -> String {
            switch self {
            case .dateien:
                "Ganz links: eine neue Planung anlegen (⌘N), eine gesicherte Datei öffnen "
                + "(⌘O) und die aktuelle als JSON-Datei sichern (⌘S). Gesichert wird ohnehin "
                + "laufend auf diesem Mac — der Export ist die Kopie zum Mitnehmen oder "
                + "Weitergeben."
            case .planung:
                "Diese Gruppe führt durch die Planung: zur laufenden Woche springen (⌘J), "
                + "die Tagesliste zum Abhaken (⌘D), Klassen/Kurse mit Fächern und Farben "
                + "(⌘K), Ferien und unterrichtsfreie Zeiten (⌘E), alle Prüfungstermine (⌘R) "
                + "und die Einstellungen mit Zeitraum, Sicherungskopie und Verschlüsselung (⌘,)."
            case .ansicht:
                "Rechts: Das Suchfeld (⌘F) blendet alle Kacheln aus, die nicht passen — "
                + "Escape leert es. Der Regler stellt die Spaltenbreite in drei Stufen (⌘+ "
                + "und ⌘−), der Knopf daneben schaltet zwischen heller und dunkler Darstellung."
            case .zelle:
                "Jede Zeile ist eine Klasse oder ein Kurs, jede Spalte eine Woche — im "
                + "Spaltenkopf stehen Kalenderwoche und Schulwoche. Diese Zelle sammelt die "
                + "Vorhaben von \(zelle.isEmpty ? "der ersten Zeile in ihrer ersten Woche" : zelle)"
                + ". Ein Klick wählt sie an; Kacheln lassen sich anwählen, öffnen und in "
                + "andere Zellen ziehen."
            case .anlegen:
                "Beim Überfahren zeigt jede Zelle unten links „+ Vorhaben“ — ein Klick öffnet "
                + "den Dialog mit Titel, Beschreibung, Materialien, Links, Wochentag und "
                + "Prüfungskennzeichen. Genauso: Doppelklick auf freie Fläche, ⌘T oder das "
                + "Rechtsklickmenü der Zelle."
            case .frei:
                "Das Schirmsymbol unten rechts stellt nur diese Klasse in dieser Woche frei — "
                + "etwa bei Exkursion oder Praktikum; die Zelle wird schraffiert, ein zweiter "
                + "Klick nimmt es zurück. Dasselbe Symbol im Spaltenkopf stellt die ganze Woche "
                + "frei; Ferien kommen über ⌘E."
            case .ohneZeile:
                "Das Raster bekommt seine Zeilen aus „Klassen/Kurse“ (⌘K). Sobald eine Zeile "
                + "da ist, zeigt die Tour dort, wie ein Vorhaben entsteht und wie eine Zelle "
                + "unterrichtsfrei wird — Hilfe → Tour durch die Oberfläche."
            }
        }
    }

    var tourLaeuft: Bool { tourSchritt != nil }

    /// Ohne Zeile gibt es keine Beispielzelle — dann sagt der letzte Schritt, wo sie herkommt.
    var tourSchritte: [Tourschritt] {
        (planung?.klassen.isEmpty ?? true)
            ? [.dateien, .planung, .ansicht, .ohneZeile]
            : [.dateien, .planung, .ansicht, .zelle, .anlegen, .frei]
    }

    /// Für „Schritt n von N“.
    var tourStelle: (stelle: Int, zahl: Int) {
        let schritte = tourSchritte
        let stelle = tourSchritt.flatMap { schritte.firstIndex(of: $0) } ?? 0
        return (stelle + 1, schritte.count)
    }

    var tourAmAnfang: Bool { tourSchritt == tourSchritte.first }

    var tourAmEnde: Bool { tourSchritt == tourSchritte.last }

    var tourAngeboten: Bool {
        tourAngebotenInSitzung || UserDefaults.standard.bool(forKey: Einstellungen.Schluessel.tourAngeboten)
    }

    /// Gefragt wird genau einmal, und nie über ein offenes Blatt hinweg.
    func tourAnbietenPruefen() {
        guard tourAnbieten, hatPlanung, !dialogOffen, !tourLaeuft, !tourAngeboten else { return }
        tourAnbieten = false
        tourAngebotenInSitzung = true
        Einstellungen.setzen(true, Einstellungen.Schluessel.tourAngeboten)
        offenerDialog = .tour
    }

    /// Aus dem Angebot, dem Hilfe-Menü oder der Kurzanleitung — auch aus einem
    /// Blatt heraus: Die Karte kommt erst, wenn das Blatt abgelöst ist.
    func tourStarten() {
        tourAnbieten = false
        Task { @MainActor [weak self] in
            await Planungsspeicher.blaetterAbloesenAbwarten()
            self?.tourBeginnen()
        }
    }

    /// Der erste Schritt, sofort — für die Prüfungen ohne Fenster.
    func tourBeginnen() {
        guard hatPlanung else {
            melden("Die Tour braucht eine Planung — zuerst eine anlegen oder öffnen.", .warnung)
            return
        }
        guard !dialogOffen else { return }
        tourSchritt = tourSchritte.first
    }

    func tourWeiter() {
        guard let aktuell = tourSchritt else { return }
        let schritte = tourSchritte
        guard let stelle = schritte.firstIndex(of: aktuell), stelle + 1 < schritte.count else {
            tourBeenden(abgeschlossen: true)
            return
        }
        tourSchritt = schritte[stelle + 1]
    }

    func tourZurueck() {
        guard let aktuell = tourSchritt,
              let stelle = tourSchritte.firstIndex(of: aktuell), stelle > 0 else { return }
        tourSchritt = tourSchritte[stelle - 1]
    }

    /// Die Meldung kommt einen Augenblick später: erst geht die Karte zu, dann
    /// blendet die Glaskapsel ein — zugleich lief die Materialauflösung heiß.
    func tourBeenden(abgeschlossen: Bool = false) {
        guard tourLaeuft else { return }
        tourSchritt = nil
        tourZelle = ""
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.melden(abgeschlossen
                         ? "Das war die Tour. Wiederholen: Hilfe → Tour durch die Oberfläche."
                         : "Tour beendet — jederzeit wieder unter Hilfe → Tour durch die Oberfläche.")
        }
    }
}
