// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Der erste Start am echten Paket (B27).
///
/// Jeder andere Prüfstand bekommt seinen `PLANUNGSORDNER` angelegt — und damit
/// sah keiner je den Fall, den eine frisch eingerichtete App vorfindet: einen
/// Ablageordner, den es noch nicht gibt. Genau daran kam N54-02 vorbei. Dieser
/// Lauf verlangt das Gegenteil: **Der Ordner darf vor dem Start nicht liegen.**
@MainActor
enum Erststartprobe {

    /// `--erststarttest`: Der Ordner fehlt, die App läuft trotzdem an, fragt
    /// nach einer neuen Planung, legt vor dem ersten Schreiben nichts an — und
    /// die erste Sicherung legt Ordner und Datei an.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            var zeilen = ["ERSTSTARTTEST"]
            var bestanden = true
            func pruefen(_ gilt: Bool, _ text: String) {
                zeilen.append("  \(gilt ? "✓" : "✗") \(text)")
                if !gilt { bestanden = false }
            }
            let ablage = speicher.sicherung.ablage
            let verwaltung = FileManager.default

            pruefen(!verwaltung.fileExists(atPath: ablage.ordner.path),
                    "der Ablageordner liegt nicht — der Start hat keinen angelegt")
            pruefen(!speicher.blockadeOffen,
                    "keine Sperre: " + (speicher.sicherung.wiederanlaufBlockade ?? "—"))
            pruefen(speicher.planung == nil, "nichts geladen — es liegt ja nichts")
            pruefen(speicher.offenerDialog == .neuePlanung, "„Neue Planung“ steht offen")

            if let start = Tag(iso: "2026-08-03") {
                speicher.neuePlanung(titel: "Erster Start", start: start, wochen: 4, basis: "",
                                     klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                                     ersterSchultag: nil, uebernahme: [])
                // Eine neue Planung bietet die Tour an. Das Angebot ist ein Blatt
                // am Fenster, und ein angeheftetes Blatt weist `terminate` ab:
                // Der Lauf bliebe mit offenem Fenster stehen, nachdem er sein
                // Ergebnis schon gedruckt hat. Also abbestellen — die Tour selbst
                // prüft `--tourtest`.
                speicher.tourAnbieten = false
                speicher.jetztSichern()
                pruefen(!speicher.sicherungLiegtStill, "die Sicherung schreibt: \(speicher.sicherung.stillgrund)")
                pruefen(verwaltung.fileExists(atPath: ablage.datei.path),
                        "die erste Sicherung hat Ordner und Planung angelegt")
            } else {
                pruefen(false, "der Prüftag ließ sich nicht bilden")
            }

            // Was nach diesem Lauf noch ein Blatt öffnete, hielte die App fest:
            // `blaetterSchliessenUndBeenden` schließt, was jetzt offen ist — ein
            // danach aufgehendes Angebot weist `terminate` wieder ab. Das Blatt
            // „Neue Planung“ selbst ist hier regulär offen und wird geschlossen.
            pruefen(!speicher.tourAnbieten && speicher.rueckfrage == nil,
                    "nichts steht aus, was nach dem Lauf ein Blatt öffnen würde")

            zeilen.append(bestanden ? "ERSTSTARTTEST bestanden" : "ERSTSTARTTEST mit Befund")
            print(zeilen.joined(separator: "\n"))
            await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
        }
    }
}
