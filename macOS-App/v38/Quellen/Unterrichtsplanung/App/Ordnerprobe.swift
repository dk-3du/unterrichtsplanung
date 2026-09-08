// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Lesezeichen mit Sicherheitsbereich im gesiegelten Paket — und der Beleg,
/// dass das Sandbox greift.
@MainActor
enum Ordnerprobe {

    /// `--ordnertest`: legt im Prüfordner ein Lesezeichen an, löst es auf,
    /// liest im Bereich, verschiebt den Ordner und löst erneut auf — im
    /// gesiegelten Paket mit Sicherheitsbereich, den das Prüfziel von `swift
    /// test` nicht hat. Dazu der Beleg, dass das Sandbox greift: Das
    /// Benutzerverzeichnis außerhalb des Containers ist nicht lesbar.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            var bestanden = true
            func pruefen(_ gilt: Bool, _ text: String) {
                print("ORDNERTEST \(gilt ? "✓" : "✗") \(text)")
                if !gilt { bestanden = false }
            }
            let verwaltung = FileManager.default
            let wurzel = speicher.sicherung.ablage.ordner.appendingPathComponent(
                "ordnertest-\(UUID().uuidString.prefix(8))", isDirectory: true)
            let vorher = wurzel.appendingPathComponent("vorher", isDirectory: true)
            let datei = vorher.appendingPathComponent("notiz.txt", isDirectory: false)
            print("ORDNERTEST Sandbox: \(Ordnerzugriff.imSandbox ? "an" : "aus"), Container: "
                  + "\(Ablage.container?.path ?? "—"), Prüfordner: \(speicher.sicherung.ablage.ordner.path)")
            do {
                try verwaltung.createDirectory(at: vorher, withIntermediateDirectories: true)
                try Data("Lesezeichen".utf8).write(to: datei)
                let eintrag = try Ordnerzugriff.merken(vorher)
                pruefen(Ordnerzugriff.zustaendig(fuer: datei.path) == eintrag,
                        "Lesezeichen angelegt: \(eintrag)")
                let gelesen = try Ordnerzugriff.mit(datei.path) {
                    try String(contentsOf: $0, encoding: .utf8)
                }
                pruefen(gelesen == "Lesezeichen", "im Sicherheitsbereich gelesen: „\(gelesen)“")
                let nachher = wurzel.appendingPathComponent("nachher", isDirectory: true)
                try verwaltung.moveItem(at: vorher, to: nachher)
                let verlegt = try Ordnerzugriff.aufloesen(datei.path)
                pruefen(verlegt.path.hasSuffix("/nachher/notiz.txt"),
                        "nach dem Verschieben aufgelöst: \(verlegt.path)")
                let nachgelesen = try Ordnerzugriff.mit(datei.path) {
                    try String(contentsOf: $0, encoding: .utf8)
                }
                pruefen(nachgelesen == "Lesezeichen", "nach dem Verschieben im Bereich gelesen")
                pruefen(Ordnerzugriff.zustaendig(fuer: nachher.path) != nil,
                        "Schlüssel nachgeführt: \(Ordnerzugriff.zustaendig(fuer: nachher.path) ?? "—")")
                // Beide Schlüssel: Der alte bleibt nach dem Verschieben als Zweitname.
                Ordnerzugriff.vergessen(nachher.path)
                Ordnerzugriff.vergessen(vorher.path)
                do {
                    _ = try Ordnerzugriff.aufloesen(datei.path)
                    pruefen(false, "ohne Lesezeichen aufgelöst — das darf nicht sein")
                } catch let fehler as Ordnerzugriff.Fehler {
                    pruefen(fehler.art == .keinLesezeichen, "ohne Lesezeichen benannt: \(fehler.text)")
                }
                let heimat = "/Users/\(NSUserName())/Library/Preferences"
                let verschlossen = !verwaltung.isReadableFile(atPath: heimat)
                pruefen(verschlossen == Ordnerzugriff.imSandbox,
                        "\(heimat) \(verschlossen ? "nicht lesbar" : "lesbar") — "
                        + "\(Ordnerzugriff.imSandbox ? "das Sandbox greift" : "ohne Sandbox")")
            } catch {
                pruefen(false, "Fehler: \(error)")
            }
            try? verwaltung.removeItem(at: wurzel)
            print(bestanden ? "ORDNERTEST bestanden ✓" : "ORDNERTEST NICHT bestanden ✗")
            await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
        }
    }
}
