// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Tour durch die Oberfläche ────────────────────────────────────────────────
extension Planungsspeicher {

    /// Ein Schritt der Tour: woran die Karte hängt und was sie sagt. Die Texte
    /// stehen hier, nicht in der Ansicht, damit die Prüfungen sie lesen.
    enum Tourschritt: String, CaseIterable, Sendable {
        case dateien, woche, planung, ansicht, zelle, kacheln, anlegen, frei, kurszelle, lernende, ohneZeile

        /// Einträge der Werkzeugleiste (Beschriftung des `Label`, ersatzweise
        /// der Anfang des Hilfetexts, in dieser Reihenfolge), der erste
        /// Klassenkopf der Kursspalte (K3) — oder die Beispielzelle des
        /// Rasters. Der Breitenregler meldet AppKit keine Beschriftung; die
        /// Karte „Suchen, Breite, Darstellung“ hängt am Knopf daneben.
        enum Anker: Equatable, Sendable {
            case werkzeug([String])
            case kurszelle
            case zelle
        }

        var anker: Anker {
            switch self {
            case .dateien: .werkzeug(["Neue Planung"])
            case .woche: .werkzeug(["Zur laufenden Woche"])
            case .planung, .ohneZeile: .werkzeug(["Klassen/Kurse"])
            case .kurszelle, .lernende: .kurszelle
            case .ansicht: .werkzeug(["Darstellung umschalten"])
            case .zelle, .kacheln, .anlegen, .frei: .zelle
            }
        }

        /// Findet der Führer den Anker im Raster nicht (noch kein Klassenkopf
        /// angelegt), hängt die Karte ersatzweise hier — bei der Kurszelle am
        /// Werkzeug „Klassen/Kurse“, wo die Zeilen herkommen.
        var ersatzanker: Anker? {
            switch self {
            case .kurszelle, .lernende: .werkzeug(["Klassen/Kurse"])
            default: nil
            }
        }

        /// Wo im Raster die Karte hängt: am Klassenkopf, rechts an der Zelle, unter der Zelle oder unter einem ihrer
        /// beiden Knöpfe. Hier entschieden, nicht im Raster, damit die Prüfung jeden Schritt sieht (Z-GR2-01).
        enum Rasterstelle: Equatable, Sendable {
            case klassenkopf, zelle, kacheln, anlegenknopf, freiknopf
        }

        var rasterstelle: Rasterstelle? {
            switch self {
            case .kurszelle, .lernende: .klassenkopf
            case .zelle: .zelle
            case .kacheln: .kacheln
            case .anlegen: .anlegenknopf
            case .frei: .freiknopf
            case .dateien, .woche, .planung, .ansicht, .ohneZeile: nil
            }
        }

        /// Kurz und in der Folge, in der die Karten über die Oberfläche wandern (E842).
        var titel: String {
            switch self {
            case .dateien: "Planungsdateien"
            case .woche: "Woche und Tagesliste"
            case .planung: "Die Planung einrichten"
            case .ansicht: "Breite, Darstellung, Suche"
            case .zelle: "Das Raster"
            case .kacheln: "Die Kacheln"
            case .anlegen: "Ein Vorhaben anlegen"
            case .frei: "Unterrichtsfrei"
            case .kurszelle: "Die Kurszelle"
            case .lernende: "Lernende"
            case .ohneZeile: "Noch keine Zeile"
            }
        }

        /// `zelle` nennt die Beispielzelle („G6a, KW 33“), vom Raster gesetzt. Höchstens zwei kurze Sätze (E842).
        func text(zelle: String) -> String {
            switch self {
            case .dateien:
                "Ganz links: neue Planung (⌘N), Datei öffnen (⌘O), sichern (⌘S). Gesichert wird ohnehin laufend; "
                + "„Sichern“ legt eine Kopie zum Mitnehmen an."
            case .woche:
                "Zur laufenden Woche springen (⌘J) und die heute anstehenden Vorhaben zum Abhaken zeigen (⌘D)."
            case .planung:
                "Klassen und Kurse mit Fächern und Farben (⌘K), Ferien (⌘E), alle Prüfungstermine (⌘R) und die "
                + "Einstellungen (⌘,) mit Zeitraum, Sicherung und Verschlüsselung."
            case .ansicht:
                "Der Regler stellt die Spaltenbreite in drei Stufen (⌘+, ⌘−), der Knopf daneben hell oder dunkel. "
                + "Die Suche ganz rechts (⌘F) blendet Kacheln aus, die nicht passen."
            case .zelle:
                "Jede Zeile ist eine Klasse oder ein Kurs, jede Spalte eine Woche; oben stehen Kalender- und Schulwoche. "
                + "Diese Zelle gehört zu \(zelle.isEmpty ? "der ersten Zeile in ihrer ersten Woche" : zelle)."
            case .kacheln:
                "Jedes Vorhaben ist eine Kachel: Ein Klick wählt sie an, ein Doppelklick öffnet sie, Ziehen verschiebt "
                + "sie. Der Rechtsklick setzt etwa Wochentag, Prüfung oder Termin."
            case .anlegen:
                "„+ Vorhaben“ unten links, ein Doppelklick auf freie Fläche oder ⌘T öffnet das Vorhaben-Blatt: "
                + "Grundlegendes, Kommentar, Prüfung, Termin, Hausaufgabe, Material, Links."
            case .frei:
                "Der Schirm unten rechts stellt diese Klasse in dieser Woche frei, der im Spaltenkopf die ganze Woche. "
                + "Ein zweiter Klick nimmt es zurück; Ferien kommen über ⌘E."
            case .kurszelle:
                // V-AX6-2 (b): „Noten“ nur einmal, bei der Leistungsdokumentation.
                "Links je Zeile die Klasse oder der Kurs mit vier Verweisen: Verwaltungsdatei (Kursbuch, Listen), "
                + "Curriculum, Sitzplan, externe Leistungsdokumentation (Noten). Ein Klick öffnet, „+\u{00A0}…“ wählt."
            case .lernende:
                "⌘L öffnet die Lernenden: Lerngruppen mit Mitgliedern, Mitteilungen, Maßnahmen und Vereinbarungen. "
                + "Mit ⌘- oder ⇧-Klick lassen sich mehrere wählen."
            case .ohneZeile:
                "Das Raster bekommt seine Zeilen aus „Klassen/Kurse“ (⌘K). Danach zeigt die Tour dort Raster, Kacheln "
                + "und Kurszelle — Hilfe → Tour durch die Oberfläche."
            }
        }
    }

    var tourLaeuft: Bool { tourSchritt != nil }

    /// Ohne Zeile gibt es keine Beispielzelle — dann sagt der letzte Schritt, wo sie herkommt.
    var tourSchritte: [Tourschritt] {
        Self.tourSchritte(mitZeilen: !(planung?.klassen.isEmpty ?? true), mitLernenden: lernendenBlattAngeboten)
    }

    /// Der Weg über die Oberfläche (E842): die Werkzeugleiste von links nach rechts, dann die Beispielzelle von oben —
    /// Raster, Kacheln, unten links „+ Vorhaben“, unten rechts der Schirm —, zuletzt die Kurszelle am linken Rand;
    /// „Lernende“ nur bei offener Lernendenverwaltung.
    static func tourSchritte(mitZeilen: Bool, mitLernenden: Bool) -> [Tourschritt] {
        guard mitZeilen else { return [.dateien, .woche, .planung, .ansicht, .ohneZeile] }
        return [.dateien, .woche, .planung, .ansicht, .zelle, .kacheln, .anlegen, .frei, .kurszelle]
            + (mitLernenden ? [.lernende] : [])
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
        tourAngebotenInSitzung || Einstellungen.wert(Einstellungen.Schluessel.tourAngeboten) ?? false
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

    /// Die Meldung kommt einen Augenblick später: Erst geht die Karte zu, dann
    /// blendet die Glaskapsel ein — zugleich lief die Materialauflösung heiß.
    func tourBeenden(abgeschlossen: Bool = false) {
        guard tourLaeuft else { return }
        tourSchritt = nil
        tourZelle = ""
        takt.aufgabe(nach: .milliseconds(300)) { [weak self] in
            self?.melden(abgeschlossen
                         ? "Das war die Tour. Wiederholen: Hilfe → Tour durch die Oberfläche."
                         : "Tour beendet — jederzeit wieder unter Hilfe → Tour durch die Oberfläche.")
        }
    }
}
