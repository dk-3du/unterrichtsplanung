// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Der Übergabestand am echten Paket (E52).
@MainActor
enum Uebergangsprobe {

    /// `--uebergangstest einschalten|erneuern|passphrase|wicklung|aufheben|pruefen`:
    /// führt den Übergang an der gesäten Planung aus — vorher liegen ein
    /// Lesezeichen (Ordner `material` im Prüfordner) und ein Sitzplan, damit
    /// die Generation alle Dateien trägt — und prüft danach, dass der Ordner
    /// einen Stand trägt: keine Marke, kein Zwilling, keine Rettungskopie.
    /// Mit `UEBERGANG_ABBRUCH=vorbereitet|uebergeben|einsetzen` bricht die
    /// App im Dienst hart ab (`exit 3`); der zweite Start mit `pruefen` zeigt
    /// den Befund des Wiederanlaufs. Passphrasen aus `UEBERGANG_PASSPHRASE`
    /// (Vorgabe „Ein Satz, den man behält“) und `UEBERGANG_PASSPHRASE_NEU`
    /// (Vorgabe „Ein anderer Satz, den man behält“); liegt die Planung
    /// versiegelt, entsperrt der Prüfstand mit `ENTSPERRPROBE_PASSPHRASE`,
    /// sonst mit der Passphrase, die nach dem Übergang gilt.
    static func laufenUndBeenden(_ speicher: Planungsspeicher, art: String) {
        let umgebung = ProcessInfo.processInfo.environment
        let passphrase = umgebung["UEBERGANG_PASSPHRASE"] ?? "Ein Satz, den man behält"
        let neue = umgebung["UEBERGANG_PASSPHRASE_NEU"] ?? "Ein anderer Satz, den man behält"
        Task { @MainActor in
            var zeilen = ["UEBERGANGSTEST (\(art))"]
            var bestanden = true
            func pruefen(_ gilt: Bool, _ text: String) {
                zeilen.append("  \(gilt ? "✓" : "✗") \(text)")
                if !gilt { bestanden = false }
            }
            func ende() async {
                zeilen.append(bestanden ? "UEBERGANGSTEST bestanden" : "UEBERGANGSTEST mit Befund")
                print(zeilen.joined(separator: "\n"))
                await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
            }
            let ablage = speicher.sicherung.ablage
            func inventar() -> [String] {
                ((try? FileManager.default.contentsOfDirectory(atPath: ablage.ordner.path)) ?? [])
                    .filter { $0.hasSuffix(".json") || $0.hasSuffix(Uebergangsdienst.zwillingssuffix) }.sorted()
            }
            func einStand() {
                let namen = inventar()
                pruefen(!namen.contains(Uebergangsdienst.markenname), "keine Marke")
                pruefen(!namen.contains { $0.hasSuffix(Uebergangsdienst.zwillingssuffix) }, "kein Zwilling")
                pruefen(!namen.contains { $0.contains("-fremd-") || $0.contains("-beschaedigt-") || $0.contains("-uebergang-") },
                        "keine Rettungskopie")
                zeilen.append("  Dateien: " + namen.joined(separator: ", "))
            }
            func kopfzeile() {
                guard let roh = try? Data(contentsOf: ablage.datei) else {
                    zeilen.append("  planung.json fehlt")
                    return
                }
                if Tresor.istBehaelter(roh), let kopf = try? Tresor.kopfLesen(roh) {
                    zeilen.append("  planung.json: Behälter, Kennung \(kopf.kennungHex.prefix(8))…, Wicklungen "
                                  + kopf.wicklungen.map(\.art).sorted().joined(separator: ", "))
                } else {
                    zeilen.append("  planung.json: Klartext, \(roh.count) Byte")
                }
            }

            try? await Task.sleep(for: .seconds(2.5))
            // Was der Start gemeldet hat — beim zweiten Start der Befund des Wiederanlaufs.
            for meldung in speicher.meldungen {
                zeilen.append("  Start meldet: " + meldung.text)
            }
            if speicher.verschluesselungsstand == .gesperrt {
                // Beim zweiten Start gilt die neue Passphrase, wenn die Marke lag — sonst die bisherige.
                let kandidaten = umgebung["ENTSPERRPROBE_PASSPHRASE"].map { [$0] }
                    ?? (art == "pruefen" ? [neue, passphrase] : [passphrase])
                for kandidat in kandidaten where speicher.verschluesselungsstand == .gesperrt {
                    await speicher.entsperren(passphrase: kandidat)
                    try? await Task.sleep(for: .milliseconds(600))
                }
                pruefen(speicher.verschluesselungsstand == .an, "entsperrt")
            }
            pruefen(speicher.planung != nil, "Planung geladen — Stand \(speicher.verschluesselungsstand)")
            guard let klasse = speicher.planung?.klassen.first else {
                pruefen(false, "keine Klasse")
                await ende()
                return
            }
            kopfzeile()
            let material = ablage.ordner.appendingPathComponent("material", isDirectory: true)

            if art == "pruefen" {
                // Der zweite Start: alles offen, ein Stand.
                pruefen(speicher.zugriff.schreibbar, "Lesezeichen offen (\(speicher.zugriff.quelle))")
                pruefen(speicher.sitzplaene.schreibbar, "Sitzpläne offen (\(speicher.sitzplaene.quelle))")
                pruefen(speicher.sitzplan(fuer: klasse.id) != nil, "der Sitzplan von „\(klasse.name)“ liegt vor")
                if speicher.zugriff.quelle == .behaelter {
                    pruefen(speicher.zugriff.zustaendig(fuer: material.path) != nil, "das Lesezeichen auf „material“ gilt")
                } else {
                    // Im Klartext liegen die Lesezeichen in den Einstellungen — ein Prüflauf
                    // hat keinen Einstellungsspeicher, über den Neustart trägt sie nichts.
                    zeilen.append("  Lesezeichen im Klartext: in den Einstellungen — im Prüflauf ohne Einstellungsspeicher nicht prüfbar")
                }
                einStand()
                pruefen(!speicher.meldungen.contains { $0.text.contains("galt nicht") || $0.text.contains("galten nicht") },
                        "nichts beiseitegelegt")
                await ende()
                return
            }

            // Saat: ein Lesezeichen und ein Sitzplan, damit die Generation alle Dateien trägt.
            try? FileManager.default.createDirectory(at: material, withIntermediateDirectories: true)
            if speicher.zugriff.zustaendig(fuer: material.path) == nil {
                pruefen((try? speicher.zugriff.merken(material)) != nil, "Lesezeichen auf „material“ gemerkt")
            }
            if speicher.sitzplan(fuer: klasse.id) == nil {
                let plan = Sitzplan.anordnen(klasseId: klasse.id, namen: Array(Sitzplanprobe.beispielnamen.prefix(12)))
                pruefen(speicher.sitzplanUebernehmen(plan) == nil, "Sitzplan mit 12 Plätzen übernommen")
            }
            speicher.jetztSichern()
            zeilen.append("  vor dem Übergang: " + inventar().joined(separator: ", "))

            // Der Übergang — mit UEBERGANG_ABBRUCH endet der Prozess im Dienst.
            if let abbruch = umgebung["UEBERGANG_ABBRUCH"] {
                zeilen.append("  UEBERGANG_ABBRUCH=\(abbruch): der Prozess endet nach diesem Schritt")
                print(zeilen.joined(separator: "\n"))
                fflush(stdout)
            }
            let ergebnis: Planungsspeicher.Schutzergebnis
            do {
                switch art {
                case "einschalten":
                    _ = try speicher.verschluesselungVorbereiten(passphrase: passphrase)
                    ergebnis = speicher.verschluesselungEinschalten()
                case "erneuern":
                    _ = try speicher.schluesselErneuernVorbereiten(alt: passphrase, neu: neue)
                    ergebnis = speicher.verschluesselungEinschalten()
                case "passphrase":
                    ergebnis = try speicher.passphraseAendern(alt: passphrase, neu: neue)
                case "wicklung":
                    speicher.enklaveImPruefstandAnlegen = true
                    let vorher = speicher.enklaveEingerichtet
                    speicher.enklaveAufDiesemMac(!vorher)
                    ergebnis = Planungsspeicher.Schutzergebnis(
                        ablage: speicher.enklaveEingerichtet != vorher ? .geschrieben : .zurueckgenommen("Wicklung unverändert"))
                    zeilen.append("  Wicklung dieses Macs: \(vorher ? "entfernt" : "angelegt")")
                case "aufheben":
                    ergebnis = speicher.verschluesselungAufheben()
                default:
                    pruefen(false, "unbekannte Art „\(art)“ — einschalten|erneuern|passphrase|wicklung|aufheben|pruefen")
                    await ende()
                    return
                }
            } catch {
                pruefen(false, "Vorbereitung: \(error.localizedDescription)")
                await ende()
                return
            }
            pruefen(ergebnis.ablage == .geschrieben, "Übergang: \(ergebnis.ablage)")
            pruefen(ergebnis.offenes.isEmpty, "nichts offen" + (ergebnis.offenes.isEmpty ? "" : ": " + ergebnis.offenes.joined(separator: "; ")))
            if let letzte = speicher.meldungen.last { zeilen.append("  Meldung: " + letzte.text) }
            kopfzeile()
            einStand()
            pruefen(speicher.zugriff.schreibbar && speicher.zugriff.zustaendig(fuer: material.path) != nil,
                    "Lesezeichen offen (\(speicher.zugriff.quelle))")
            pruefen(speicher.sitzplaene.schreibbar && speicher.sitzplan(fuer: klasse.id) != nil,
                    "Sitzpläne offen (\(speicher.sitzplaene.quelle))")
            await ende()
        }
    }
}
