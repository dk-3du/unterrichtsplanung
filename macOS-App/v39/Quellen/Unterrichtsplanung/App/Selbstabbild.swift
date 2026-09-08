// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// `--abbild <datei.png>`: startet, wartet auf das Fenster, legt es als PNG ab
/// und beendet sich. Liquid Glass zeichnet das Fenstersystem — abseits des
/// Bildschirms gezeichnete Ansichten zeigen davon nichts.
@MainActor
enum Selbstabbild {

    /// Der Prüfordner des Laufs — dorthin wandert ein Abbild, das im Sandbox
    /// außerhalb des Containers läge. Gesetzt vom Verteiler.
    static var pruefordner: URL?

    /// Mit `--dialog <name>` wird vorher der genannte Dialog abgebildet.
    static func ablegenUndBeenden(_ speicher: Planungsspeicher, ziel: URL,
                                  nach wartezeit: TimeInterval = 2.0) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(wartezeit))
            let teile = ProcessInfo.processInfo.arguments
            if let stelle = teile.firstIndex(of: "--dialog"), stelle + 1 < teile.count {
                let name = teile[stelle + 1]
                if name == "ueber" {
                    // Eigenes Fenster, kein Blatt — deshalb das Schlüsselfenster.
                    Ueber.zeigen()
                    try? await Task.sleep(for: .milliseconds(1200))
                    if let fenster = NSApp.keyWindow ?? NSApp.windows.last(where: \.isVisible) {
                        Selbstabbild.ablegen(fenster, nach: ziel)
                    }
                    await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
                    return
                }
                if name == "vorhaben" {
                    let mitLink = speicher.planung?.eintraege.first { !$0.links.isEmpty }
                    if let mitLink { speicher.vorhabenOeffnen(id: mitLink.id) }
                } else if let welcher = Dialogfenster(rawValue: name) {
                    if welcher == .ersteinrichtung { ersteinrichtungVorbereiten(speicher) }
                    if welcher == .update { updateVorbereiten(speicher) }
                    if welcher == .nachwahl { nachwahlVorbereiten(speicher) }
                    speicher.offenerDialog = welcher
                }
                try? await Task.sleep(for: .milliseconds(1800))
            }
            if teile.contains("--auswahl"), let eintraege = speicher.planung?.eintraege {
                for (stelle, eintrag) in eintraege.prefix(30).enumerated()
                where stelle % 27 == 0 || stelle == 1 {
                    speicher.anwaehlen(vorhaben: eintrag.id, erweitern: stelle > 0)
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
            if let fenster = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                Selbstabbild.ablegen(fenster.attachedSheet ?? fenster, nach: ziel)
            }
            await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
        }
    }

    /// `--dialog ersteinrichtung` mit `ABBILD_SCHRITT=frage|passphrase|blatt|
    /// sicherung|updates`: die Station der Ersteinrichtung (in Schritten),
    /// bevor das Blatt aufgeht. Die Passphrase ist ein Wegwerfwert.
    private static func ersteinrichtungVorbereiten(_ speicher: Planungsspeicher) {
        switch ProcessInfo.processInfo.environment["ABBILD_SCHRITT"] ?? "frage" {
        case "passphrase":
            speicher.ersteinrichtungEinrichten()
        case "blatt":
            speicher.ersteinrichtungEinrichten()
            try? speicher.ersteinrichtungWeiter(passphrase: "Ein Satz, den man behält")
        case "sicherung":
            speicher.ersteinrichtungUeberspringen()
        case "updates":
            speicher.ersteinrichtungUeberspringen()
            speicher.ersteinrichtungZuUpdates()
        default:
            break
        }
    }

    /// `--dialog nachwahl`: das Blatt mit zwei vorgegebenen Ordnern, die der
    /// App nicht offenstehen — gemerkt wird nichts.
    private static func nachwahlVorbereiten(_ speicher: Planungsspeicher) {
        speicher.nachwahlVorgeben(
            zielordner: "/Users/lehrkraft/Library/Mobile Documents/com~apple~CloudDocs/Unterrichtsplanung",
            basis: "/Users/lehrkraft/Unterricht")
    }

    /// `--dialog update`: das Release aus `UPDATE_QUELLE` (eine gespeicherte
    /// Antwort der Schnittstelle), sonst das erfundene der Probe. Ins Netz
    /// geht der Prüfstand nie.
    private static func updateVorbereiten(_ speicher: Planungsspeicher) {
        if let pfad = ProcessInfo.processInfo.environment["UPDATE_QUELLE"], !pfad.isEmpty,
           let daten = try? Data(contentsOf: URL(fileURLWithPath: pfad)),
           let release = try? Veroeffentlichung.lesen(daten) {
            speicher.updateVorgeben(release)
        } else {
            speicher.updateVorgeben(.probe)
        }
    }

    /// Im Sandbox schreibt der Prüfstand nur in den Container: Ein Ziel
    /// außerhalb wandert in den Prüfordner, der Name bleibt — die Ausgabe
    /// nennt den Ort.
    static func abbildziel(_ gewuenscht: URL, container: URL?,
                           pruefordner: URL) -> URL {
        let ordner = gewuenscht.deletingLastPathComponent().path
        guard !Ablage.pruefordnerZulaessig(ordner, container: container) else { return gewuenscht }
        return pruefordner.appendingPathComponent(gewuenscht.lastPathComponent, isDirectory: false)
    }

    /// Legt zwei PNG ab: Der übergebene Pfad gibt Ordner und Grundnamen, die
    /// Dateien heißen `<Grundname>-rahmen.png` und `<Grundname>-inhalt.png`.
    static func ablegen(_ fenster: NSWindow, nach gewuenscht: URL) {
        let ziel = abbildziel(gewuenscht, container: Ablage.container,
                              pruefordner: pruefordner ?? gewuenscht.deletingLastPathComponent())
        if ziel != gewuenscht {
            print("ABBILD Ziel außerhalb des Containers — abgelegt im Prüfordner \(ziel.deletingLastPathComponent().path)")
        }
        // Abzeichnen statt Bildschirmaufnahme: die bräuchte eine Erlaubnis.
        for (name, ansicht) in [("rahmen", fenster.contentView?.superview),
                                ("inhalt", fenster.contentView)] {
            guard let ansicht,
                  let abzug = ansicht.bitmapImageRepForCachingDisplay(in: ansicht.bounds)
            else { continue }
            ansicht.cacheDisplay(in: ansicht.bounds, to: abzug)
            guard let daten = abzug.representation(using: .png, properties: [:]) else { continue }
            let datei = ziel.deletingPathExtension().lastPathComponent + "-" + name + ".png"
            let ort = ziel.deletingLastPathComponent().appendingPathComponent(datei)
            do {
                try daten.write(to: ort)
                print("ABBILD abgelegt: \(ort.path)")
            } catch {
                print("ABBILD nicht ablegbar (\(ort.path)): \(error.localizedDescription)")
            }
        }
    }
}
