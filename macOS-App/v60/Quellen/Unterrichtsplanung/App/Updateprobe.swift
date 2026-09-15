// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Die Prüfung auf Updates gegen die Schnittstelle — die einzige Stelle, an
/// der ein Prüfstand ins Netz geht.
@MainActor
enum Updateprobe {

    /// `--updatetest`: fragt die Schnittstelle — oder die Datei aus
    /// `UPDATE_QUELLE` — und meldet den Befund auf der Standardausgabe. Die
    /// einzige Stelle, an der ein Prüfstand ins Netz geht, und nur auf diesen
    /// Aufruf hin; Einstellungen und Planung des Nutzers bleiben unberührt.
    /// Beendet über die Blätter: Ein leerer Prüfordner öffnet „Neue Planung“,
    /// und ein angeheftetes Blatt hielte AppKit am Beenden fest.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        let quelle = Updatepruefer.quelle(umgebung: ProcessInfo.processInfo.environment,
                                          pruefstand: false) ?? Updatepruefer.schnittstelle
        let pruefer = Updatepruefer(quelle: quelle, installiert: Updates.installierterBuild)
        Task { @MainActor in
            let ergebnis = await pruefer.pruefen()
            print("UPDATETEST Quelle: \(quelle.absoluteString)")
            print("UPDATETEST installiert: \(Updates.installierteFassung)")
            switch ergebnis.befund {
            case .aktuell(let release):
                print("UPDATETEST Befund: aktuell — jüngstes Release \(release.titel) (\(release.tagName))")
            case .neu(let release):
                print("UPDATETEST Befund: neu — \(release.titel) (\(release.tagName)), Seite \(release.seite?.absoluteString ?? "–")")
            case .uebersprungen(let release):
                print("UPDATETEST Befund: übersprungen — \(release.titel)")
            case .nichtErreichbar:
                print("UPDATETEST Befund: nicht erreichbar")
            case .unlesbar:
                print("UPDATETEST Befund: unlesbar")
            }
            print("UPDATETEST ETag: \(ergebnis.etag ?? "–"), Antwort: \(ergebnis.antwort?.count ?? 0) Byte")
            await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
        }
    }
}
