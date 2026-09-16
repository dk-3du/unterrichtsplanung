// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI

/// Die Tour am echten Fenster: Anker, Karte, Tastatur, Neuaufbau.
@MainActor
enum Tourprobe {

    /// `--tourtest`: die Tour am echten Fenster — je Schritt Lage des Ankers
    /// und der Karte auf dem Bildschirm, dazu Abbilder von Fenster und Karte
    /// (`TOURBILD=<Pfadanfang>`; die Karte über `ImageRenderer`, weil ein
    /// Popover sich nicht abzeichnen lässt). Vorher die Einträge der
    /// Werkzeugleiste, wie SwiftUI sie AppKit meldet. Gedruckt wird sofort,
    /// damit ein Absturz nichts verschluckt. Braucht eine `planung.json` mit
    /// einer Zeile.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        let bildanfang = ProcessInfo.processInfo.environment["TOURBILD"]
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  speicher.planung != nil else {
                print("TOURTEST kein Fenster / keine Planung")
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            fenster.setContentSize(NSSize(width: 1400, height: 800))
            try? await Task.sleep(for: .milliseconds(900))

            @MainActor func sagen(_ zeile: String) {
                print(zeile)
                fflush(stdout)
            }
            sagen("TOURTEST")
            sagen(String(format: "Fenster %.0f,%.0f %.0f×%.0f", fenster.frame.minX,
                         fenster.frame.minY, fenster.frame.width, fenster.frame.height))
            sagen("Werkzeugleiste (\(fenster.toolbar?.items.count ?? 0) Einträge):")
            for eintrag in fenster.toolbar?.items ?? [] {
                let ansicht = eintrag.view
                let lage = ansicht.map { $0.convert($0.bounds, to: nil) } ?? .zero
                sagen("  „\(eintrag.label)“ · \(eintrag.toolTip ?? "—") · "
                      + (ansicht.map { "\(type(of: $0))" } ?? "ohne Ansicht")
                      + String(format: " %.0f,%.0f %.0f×%.0f", lage.minX, lage.minY,
                               lage.width, lage.height))
            }

            @MainActor func abbild(_ name: String) {
                guard let bildanfang else { return }
                Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: bildanfang + "-" + name + ".png"))
                let zeichner = ImageRenderer(content: Tourkarte().environment(speicher))
                zeichner.scale = 2
                if let bild = zeichner.cgImage {
                    let abzug = NSBitmapImageRep(cgImage: bild)
                    let ort = URL(fileURLWithPath: bildanfang + "-" + name + "-karte.png")
                    try? abzug.representation(using: .png, properties: [:])?.write(to: ort)
                }
            }
            @MainActor func festhalten(_ was: String) async {
                try? await Task.sleep(for: .milliseconds(900))
                guard let schritt = speicher.tourSchritt else {
                    sagen("  \(was): Tour steht nicht ✗")
                    return
                }
                let lage = Tourfuehrer.shared.letzteLage
                let karte = Tourfuehrer.shared.kartenfenster
                let stelle = speicher.tourStelle
                sagen("  \(was): \(schritt.rawValue) (\(stelle.stelle) von \(stelle.zahl))"
                      + " · Zelle „\(speicher.tourZelle)“")
                if let lage, lage.schritt == schritt {
                    sagen(String(format: "    Anker %.0f,%.0f %.0f×%.0f", lage.anker.minX,
                                 lage.anker.minY, lage.anker.width, lage.anker.height))
                } else {
                    sagen("    kein Anker ✗")
                }
                if let karte, karte.isVisible {
                    let r = karte.frame
                    let ok = lage.map { r.insetBy(dx: -40, dy: -40).intersects($0.anker) } ?? false
                    sagen(String(format: "    Karte %.0f,%.0f %.0f×%.0f", r.minX, r.minY,
                                 r.width, r.height) + (ok ? " · am Anker ✓" : " · fern vom Anker ✗"))
                } else {
                    sagen("    keine Karte ✗")
                }
                abbild(schritt.rawValue)
            }

            speicher.tourBeginnen()
            await festhalten("Start")
            speicher.tourWeiter()
            await festhalten("Weiter")
            speicher.tourZurueck()
            await festhalten("Zurück")
            var runden = 0
            while speicher.tourSchritt != nil, runden < 10 {
                speicher.tourWeiter()
                runden += 1
                if speicher.tourSchritt != nil { await festhalten("Weiter") }
            }
            try? await Task.sleep(for: .milliseconds(500))
            let offen = Tourfuehrer.shared.kartenfenster?.isVisible ?? false
            sagen("  Ende: Tour \(speicher.tourSchritt == nil ? "beendet ✓" : "läuft noch ✗")"
                  + ", Karte \(offen ? "steht noch ✗" : "weg ✓")"
                  + ", Meldung „\(speicher.meldungen.last?.text ?? "—")“")

            // Tastatur an der Karte: ⏎ geht weiter, ⎋ beendet — und ein
            // Neuaufbau des Rasters (Spaltenbreite) lässt die Karte nicht hängen.
            @MainActor func taste(_ zeichen: String, code: UInt16) {
                guard let karte = Tourfuehrer.shared.kartenfenster else { return }
                for art in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let ereignis = NSEvent.keyEvent(
                        with: art, location: .zero, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: karte.windowNumber, context: nil,
                        characters: zeichen, charactersIgnoringModifiers: zeichen,
                        isARepeat: false, keyCode: code) else { continue }
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }
            try? await Task.sleep(for: .milliseconds(600))
            speicher.tourBeginnen()
            try? await Task.sleep(for: .milliseconds(900))
            let schluessel = Tourfuehrer.shared.kartenfenster?.isKeyWindow ?? false
            taste("\r", code: 36)
            try? await Task.sleep(for: .milliseconds(700))
            sagen("  Tastatur: Karte \(schluessel ? "ist" : "ist nicht") Schlüsselfenster; "
                  + "⏎ → \(speicher.tourSchritt?.rawValue ?? "—")"
                  + (speicher.tourSchritt == .planung ? " ✓" : " ✗"))
            // Bis zum letzten Schritt (mit Zeile: die Karte an der Zelle).
            while speicher.tourLaeuft, !speicher.tourAmEnde { speicher.tourWeiter() }
            try? await Task.sleep(for: .milliseconds(900))
            let vorher = Tourfuehrer.shared.kartenfenster
            speicher.spaltenbreite += Kennwerte.spalteRaster
            try? await Task.sleep(for: .milliseconds(1200))
            let nachher = Tourfuehrer.shared.kartenfenster
            sagen("  Neuaufbau bei Schritt \(speicher.tourSchritt?.rawValue ?? "—"): Karte "
                  + ((nachher?.isVisible ?? false) ? "steht" : "fehlt ✗")
                  + (vorher !== nachher ? " (neu angehängt)" : " (dieselbe)")
                  + ((nachher?.isKeyWindow ?? false) ? ", Schlüsselfenster" : ", nicht Schlüsselfenster"))
            speicher.spaltenbreite -= Kennwerte.spalteRaster
            try? await Task.sleep(for: .milliseconds(900))
            taste("\u{1B}", code: 53)
            try? await Task.sleep(for: .milliseconds(700))
            sagen("  ⎋ → Tour \(speicher.tourSchritt == nil ? "beendet ✓" : "läuft noch ✗")")
            if speicher.tourLaeuft, let karte = Tourfuehrer.shared.kartenfenster {
                // Wie ein Klick in die Karte.
                karte.makeKey()
                taste("\u{1B}", code: 53)
                try? await Task.sleep(for: .milliseconds(700))
                sagen("  ⎋ nach Klick in die Karte → Tour "
                      + "\(speicher.tourSchritt == nil ? "beendet ✓" : "läuft noch ✗")")
            }
            await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
        }
    }
}
