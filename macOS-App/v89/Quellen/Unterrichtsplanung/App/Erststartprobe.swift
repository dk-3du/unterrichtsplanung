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

    /// `--erststarttest`: Der Ordner fehlt, die App läuft trotzdem an, fragt —
    /// am voreingestellten Ort erst nach der Verschlüsselung (v84, D1b) — nach
    /// einer neuen Planung, legt vor dem ersten Schreiben nichts an — und die
    /// erste Sicherung legt Ordner und Datei an.
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
            // Die eine Wartestelle dieses Laufs: höchstens 5 s, bis etwas eintritt (G3-02 nutzt sie mit).
            @MainActor func warten(bis gilt: @MainActor () -> Bool) async -> Bool {
                var versuche = 0
                while !gilt(), versuche < 100 {
                    try? await Task.sleep(for: .milliseconds(50))
                    versuche += 1
                }
                return gilt()
            }
            // Am voreingestellten Ort steht vor der Planung die Frage nach der Verschlüsselung (v84, AT6:
            // D1b, E349) — übersprungen, wie es nichts in den Schlüsselbund schreibt; dann „Neue Planung“,
            // sobald das Blatt der Einrichtung abgelöst ist. Nur wenn sie steht: Ein „Überspringen“ ohne
            // ihr Blatt merkte „Neue Planung“ als nächstes Blatt vor, und die Schlusszeile fiele mit.
            if amVoreingestelltenOrt {
                let frageEins = speicher.offenerDialog == .ersteinrichtung
                    && speicher.ersteinrichtungsschritt == .verschluesselung
                pruefen(frageEins, "vor der Planung steht die Frage nach der Verschlüsselung (Frage 1 von 4)")
                if frageEins {
                    // G3-02: „Planung öffnen …“ öffnet den echten Dateidialog am Blatt der Einrichtung; Abbrechen lässt
                    // Frage 1 stehen. Gerufen wie der Knopf — den SwiftUI-Knopf nicht über AppKit suchen (B83).
                    let haupt = NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && !($0 is NSSavePanel) }
                    let blattDa = await warten { haupt?.attachedSheet != nil }
                    if blattDa, let blatt = haupt?.attachedSheet {
                        // Nur, wenn der Dialog als Bogen an das Blatt ginge: Ist die Probe nicht vorn, gibt es kein
                        // Schlüsselfenster, der Dialog ginge frei auf und hielte den Lauf (am Lauf gesehen 24.10.2026,
                        // wie I3-01, Z-AW1-09). Vorn holen ohne feste Pause — gewartet wird, bis das Blatt Schlüssel ist.
                        NSApp.activate(ignoringOtherApps: true)
                        blatt.makeKeyAndOrderFront(nil)
                        let vorn = await warten { Dialogort.aktuell == .bogen(blatt) }
                        if vorn {
                            speicher.importDialog()
                            let dialogDa = await warten { blatt.attachedSheet is NSOpenPanel }
                            pruefen(dialogDa, "„Planung öffnen …“: der Dateidialog hängt am Blatt der Einrichtung "
                                        + "(gerufen wie der Knopf)")
                            (blatt.attachedSheet as? NSOpenPanel)?.cancel(nil)
                            // Ging er frei auf, hielte er den Lauf — jeden sichtbaren schließen (Z-GR3-06).
                            if !dialogDa {
                                NSApp.windows.compactMap { $0 as? NSOpenPanel }.filter(\.isVisible).forEach { $0.cancel(nil) }
                            }
                            var dialogWeg = await warten { blatt.attachedSheet == nil }
                            if !dialogWeg, let bogen = blatt.attachedSheet {
                                blatt.endSheet(bogen, returnCode: .cancel)
                                dialogWeg = await warten { blatt.attachedSheet == nil }
                            }
                            pruefen(dialogWeg && blatt.isVisible && speicher.offenerDialog == .ersteinrichtung
                                        && speicher.ersteinrichtungsschritt == .verschluesselung && speicher.planung == nil,
                                    "„Planung öffnen …“ abgebrochen: Frage 1 steht noch, nichts geladen")
                        } else {
                            pruefen(false, "„Planung öffnen …“: Das Blatt der Einrichtung ist nicht vorn "
                                        + "(\(Dialogort.aktuell)) — nicht gerufen")
                        }
                    } else {
                        pruefen(false, "„Planung öffnen …“: Das Blatt der Einrichtung hängt nicht am Hauptfenster")
                    }
                    speicher.ersteinrichtungUeberspringen()
                    // Die Hauptansicht wartet, bis das Blatt fort ist.
                    _ = await warten { speicher.offenerDialog == .neuePlanung }
                }
            }
            pruefen(speicher.offenerDialog == .neuePlanung, "„Neue Planung“ steht offen")

            if let start = Tag(iso: "2026-08-03") {
                speicher.neuePlanung(titel: "Erster Start", start: start, wochen: 4, basis: "",
                                     klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                                     ersterSchultag: nil, uebernahme: [], ohneMitglieder: [])  // ohne Vorjahr kein Wechsel
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
                    // Frage 1 stand vor der Planung und ist übersprungen: Der Merker legt den Beginn auf die
                    // Sicherungskopie (E355). Berechnet aus dem Zustand — das Blatt selbst geht im Lauf nicht auf.
                    let beginn = Planungsspeicher.ersteinrichtungBeginn(verschluesselt: speicher.verschluesselt,
                                                                       frage: speicher.verschluesselungsfrage)
                    pruefen(speicher.verschluesselungsfrage == .uebersprungen && beginn == .sicherung
                                && Planungsspeicher.ersteinrichtungFragen(schritt: beginn,
                                                                          frage: speicher.verschluesselungsfrage) == 4,
                            "Merker „übersprungen“: die Einrichtung begänne bei „Frage 2 von 4“")
                    speicher.ersteinrichtungBeantwortet()
                    // Und die dritte Frage („beim Öffnen nach Updates suchen?“):
                    // `updateSpaeter()` räumt nur ein Angebot weg, nicht die Frage.
                    // Unbeantwortet geht ihr Blatt nach dem Schließen wieder auf und
                    // weist `terminate` ab — nachgemessen, der Lauf blieb stehen.
                    // „Nein“ ist die Antwort, die nichts ins Netz schickt.
                    pruefen(!speicher.updatesGefragt, "die Frage nach den Updates steht noch offen")
                    speicher.updatesErlauben(false)
                    // Und die vierte Frage (Materialliste von 3ducation.org, v71):
                    // dieselbe Regel, dieselbe Antwort — „Nein“ schickt nichts ins Netz.
                    pruefen(!speicher.materialienGefragt, "die Frage nach der Materialliste steht noch offen")
                    speicher.materialienErlauben(false)
                    // Und der Hinweis gegen den Rückweg (v80, E286, E297): Nach einer
                    // Neuinstallation steht er hinter den Fragen an — gelesen, sonst
                    // ginge sein Blatt nach dem Schließen auf und hielte die App fest.
                    pruefen(Planungsspeicher.rueckwegHinweisFaellig(
                                pruefstand: Ablage.istPruefstand, hatPlanung: speicher.hatPlanung,
                                ersteinrichtungFaellig: speicher.ersteinrichtungFaellig,
                                gezeigt: speicher.rueckwegHinweisGezeigt),
                            "der Hinweis gegen den Rückweg steht nach den Fragen an — wie nach einer Neuinstallation")
                    speicher.rueckwegHinweisGelesen()
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
            let materialfrageOffen = Planungsspeicher.materialNachfrageFaellig(
                pruefstand: Ablage.istPruefstand, hatPlanung: speicher.hatPlanung,
                ersteinrichtungFaellig: speicher.ersteinrichtungFaellig,
                updateGefragt: speicher.updatesGefragt, gefragt: speicher.materialienGefragt)
            let rueckwegOffen = Planungsspeicher.rueckwegHinweisFaellig(
                pruefstand: Ablage.istPruefstand, hatPlanung: speicher.hatPlanung,
                ersteinrichtungFaellig: speicher.ersteinrichtungFaellig,
                gezeigt: speicher.rueckwegHinweisGezeigt)
            // Dazu (v84, AT6): kein vorgemerktes Blatt, keine liegende Vorbereitung der Verschlüsselung.
            pruefen(!speicher.tourAnbieten && speicher.rueckfrage == nil
                        && !speicher.ersteinrichtungFaellig && !speicher.ersteinrichtungFortsetzen
                        && !updatefrageOffen && !materialfrageOffen && !rueckwegOffen
                        && speicher.naechsterDialog == nil && speicher.vorbereitung == nil,
                    "nichts steht aus, was nach dem Lauf ein Blatt öffnen würde")

            zeilen.append(bestanden ? "ERSTSTARTTEST bestanden" : "ERSTSTARTTEST mit Befund")
            print(zeilen.joined(separator: "\n"))
            await Pruefstaende.abschliessenUndBeenden(speicher)
        }
    }
}
