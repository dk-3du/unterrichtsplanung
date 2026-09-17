// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Der erste Start am echten Paket (B27, E78).
///
/// Jeder andere Prüfstand bekommt seinen `PLANUNGSORDNER` angelegt — und damit
/// sah keiner je den Fall, den eine frisch eingerichtete App vorfindet: einen
/// Ablageordner, den es noch nicht gibt. Genau daran kam N54-02 vorbei. Dieser
/// Lauf verlangt das Gegenteil: **Der Ordner darf vor dem Start nicht liegen.**
///
/// Zwei Wege, beide gehören in die Runde (E78):
/// * mit `PLANUNGSORDNER` auf einen Ordner, den es nicht gibt — schnell, überall;
/// * im **Probepaket ohne** `PLANUNGSORDNER` — dann liegt der Ablageort dort,
///   wo ihn eine frisch eingerichtete App sucht: `Application Support` im
///   Container. Dieser Weg ist der einzige, der `URL.applicationSupportDirectory`
///   im Sandbox wirklich anfasst, und er sieht auch die Ersteinrichtung, die
///   ein Prüflauf sonst nie zu Gesicht bekommt.
///
/// **Was auch dieser Lauf nicht deckt — ausdrücklich festgehalten.** Das
/// Probepaket trägt eine eigene Kennung, ist ad hoc signiert und hat **kein
/// Umzugsmanifest**. Damit bleiben außen vor: der Umzug einer Ablage aus der
/// Zeit vor dem App Sandbox (`Beiwerk/container-migration.plist`), die
/// Beglaubigung, Gatekeeper und die Quarantäne eines geladenen Abbilds. Für
/// eine frische Einrichtung ist der Umzug ein Leerlauf — *geprüft* ist er
/// damit nicht. **Die Erstinstallation der ausgelieferten, beglaubigten App in
/// einem frischen Benutzerkonto lässt sich hier nicht nachbilden**; sie bleibt
/// Handarbeit an einem eigenen Konto oder einer eigenen Maschine. Dieser
/// Prüfstand deckt den Programmweg, nicht die Auslieferung.
///
/// **Wiederholbarkeit.** Der Lauf verlangt einen Stand wie nach der
/// Einrichtung — und den Container zu löschen genügt dafür nicht: `cfprefsd`
/// hält die Einstellungen des gelöschten Containers im Zwischenspeicher und
/// reicht sie dem nächsten Lauf weiter; die Ersteinrichtung galt dann als
/// schon beantwortet (nachgemessen 14.09.2026, der Lauf meldete einen Befund).
/// Zurückgesetzt wird, indem man im Container des Probepakets den Ablageordner
/// (`Library/Application Support/Unterrichtsplanung`) und die Domänendatei
/// (`Library/Preferences/<Kennung>.plist`) beiseitelegt **und** `killall
/// cfprefsd` ruft; beides geht ohne den Finder.
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
            // Welcher Ort es war, gehört ins Protokoll: Nur so ist hinterher zu
            // sagen, ob ein Befund am Ort oder am Zustand lag (E78).
            let amVoreingestelltenOrt = !Ablage.istPruefstand
            zeilen.append("  Ablageort: \(ablage.ordner.path)")
            zeilen.append("  Container: \(Ablage.container?.path ?? "keiner (ohne Sandbox)")")
            zeilen.append("  Weg: " + (amVoreingestelltenOrt
                                       ? "voreingestellt, ohne PLANUNGSORDNER — wie eine frische Einrichtung"
                                       : "PLANUNGSORDNER"))

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
                // Am voreingestellten Ort ist der Lauf kein Prüfstand mehr: Die
                // Ersteinrichtung fragt, wie sie es beim echten ersten Start tut.
                // Erst feststellen, dass sie ansteht — dann beantworten, sonst
                // ginge ihr Blatt nach dem Schließen wieder auf (wie bei der Tour).
                if amVoreingestelltenOrt {
                    pruefen(speicher.ersteinrichtungFaellig,
                            "die Ersteinrichtung steht an — wie beim echten ersten Start")
                    speicher.ersteinrichtungBeantwortet()
                    // Und die dritte Frage („beim Öffnen nach Updates suchen?“):
                    // `updateSpaeter()` räumt nur ein Angebot weg, nicht die Frage.
                    // Unbeantwortet geht ihr Blatt nach dem Schließen wieder auf und
                    // weist `terminate` ab — nachgemessen, der Lauf blieb stehen.
                    // „Nein“ ist die Antwort, die nichts ins Netz schickt.
                    pruefen(!speicher.updatesGefragt, "die Frage nach den Updates steht noch offen")
                    speicher.updatesErlauben(false)
                } else {
                    pruefen(!speicher.ersteinrichtungFaellig,
                            "im Prüfstand mit eigenem Ordner fragt die Ersteinrichtung nicht")
                }
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
            // Jede stehende Frage wird hier gegen die Regel geprüft, nach der die
            // App sie stellt — nicht gegen eine zweite Regel. Kommt eine Frage
            // hinzu, gehört sie in diese Zeile, sonst bleibt der Lauf stehen,
            // nachdem er sein Ergebnis schon gedruckt hat.
            let updatefrageOffen = Planungsspeicher.updateNachfrageFaellig(
                pruefstand: Ablage.istPruefstand, hatPlanung: speicher.hatPlanung,
                ersteinrichtungFaellig: speicher.ersteinrichtungFaellig,
                gefragt: speicher.updatesGefragt)
            pruefen(!speicher.tourAnbieten && speicher.rueckfrage == nil
                        && !speicher.ersteinrichtungFaellig && !updatefrageOffen,
                    "nichts steht aus, was nach dem Lauf ein Blatt öffnen würde")

            zeilen.append(bestanden ? "ERSTSTARTTEST bestanden" : "ERSTSTARTTEST mit Befund")
            print(zeilen.joined(separator: "\n"))
            await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
        }
    }
}
