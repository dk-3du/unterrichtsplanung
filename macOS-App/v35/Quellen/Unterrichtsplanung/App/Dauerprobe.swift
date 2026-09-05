// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// `--dauertest` — wird die App mit der Zeit träger?
///
/// Dieselbe Bedienung hundertfach, verglichen wird die Zeit **je Block**.
/// Gemeldet werden Rechenzeit je Handgriff, belegter Speicher und die Zahl der
/// überfahrenen Zellen — bleiben alle drei flach, häuft sich nichts an.
@MainActor
enum Dauerprobe {

    private static let bloecke = 12
    private static let handgriffeJeBlock = 12

    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        guard ProcessInfo.processInfo.arguments.contains("--dauertest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("DAUERTEST") else { return }
        Task { @MainActor in
            for _ in 0..<60 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let planung = speicher.planung, let klasse = planung.klassen.first else {
                print("DAUERTEST kein Fenster / keine Planung")
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(2))

            let wochen = planung.wochenListe
            let eintraege = planung.eintraege
            let rollbereich = groesserRollbereich(in: fenster.contentView)
            print("DAUERTEST Fenster \(Int(fenster.frame.width))×\(Int(fenster.frame.height)) · "
                  + "\(planung.klassen.count) Klassen/Kurse · \(planung.eintraege.count) Vorhaben")
            print("  Block   ms/Handgriff   Speicher   überfahren")

            var ersteZeit: Double = 0
            for block in 1...bloecke {
                let vorher = rechenzeit()
                for schritt in 0..<handgriffeJeBlock {
                    let lauf = (block - 1) * handgriffeJeBlock + schritt
                    switch lauf % 3 {
                    case 0:
                        speicher.zelleFreiSchalten(klasse: klasse.id,
                                                   woche: wochen[lauf % wochen.count])
                    case 1:
                        if !eintraege.isEmpty {
                            speicher.anwaehlen(vorhaben: eintraege[lauf % eintraege.count].id)
                        }
                    default:
                        if !eintraege.isEmpty {
                            speicher.erledigtUmschalten(eintraege[lauf % eintraege.count].id)
                        }
                    }
                    fenster.contentView?.layoutSubtreeIfNeeded()
                    fenster.displayIfNeeded()
                    try? await Task.sleep(for: .milliseconds(60))
                }
                if let rollbereich {
                    for i in 0..<30 {
                        rollbereich.contentView.scroll(
                            to: NSPoint(x: CGFloat((block * 7 + i) % 40) * 120,
                                        y: CGFloat(i % 10) * 90))
                        rollbereich.reflectScrolledClipView(rollbereich.contentView)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
                let jeHandgriff = (rechenzeit() - vorher) / Double(handgriffeJeBlock) * 1000
                if block == 1 { ersteZeit = jeHandgriff }
                print(String(format: "  %5d   %10.1f   %7.1f MB   %5d", block, jeHandgriff,
                             speicherbedarf(), ueberfahreneZellen(fenster)))
            }

            print(String(format: "DAUERTEST erster Block %.1f ms je Handgriff — "
                         + "läuft der letzte deutlich darüber, häuft sich etwas an.", ersteZeit))
            NSApp.terminate(nil)
        }
    }

    /// Höchstens eine ist richtig — beim Rollen häuften sie sich an.
    @MainActor
    private static func ueberfahreneZellen(_ fenster: NSWindow) -> Int {
        var zahl = 0
        func zaehlen(_ ansicht: NSView) {
            if let zelle = ansicht as? Zellenkoerper, zelle.ueberfahren { zahl += 1 }
            ansicht.subviews.forEach(zaehlen)
        }
        if let inhalt = fenster.contentView { zaehlen(inhalt) }
        return zahl
    }

    private static func rechenzeit() -> Double {
        var nutzung = rusage()
        getrusage(RUSAGE_SELF, &nutzung)
        return Double(nutzung.ru_utime.tv_sec) + Double(nutzung.ru_utime.tv_usec) / 1e6
             + Double(nutzung.ru_stime.tv_sec) + Double(nutzung.ru_stime.tv_usec) / 1e6
    }

    private static func speicherbedarf() -> Double {
        var info = task_vm_info_data_t()
        var anzahl = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let ergebnis = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(anzahl)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &anzahl)
            }
        }
        return ergebnis == KERN_SUCCESS ? Double(info.phys_footprint) / 1024 / 1024 : 0
    }

    private static func groesserRollbereich(in wurzel: NSView?) -> NSScrollView? {
        guard let wurzel else { return nil }
        var gefunden: [NSScrollView] = []
        func absuchen(_ ansicht: NSView) {
            if let rollbereich = ansicht as? NSScrollView { gefunden.append(rollbereich) }
            ansicht.subviews.forEach(absuchen)
        }
        absuchen(wurzel)
        return gefunden.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}
