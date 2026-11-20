// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Die Materialliste von 3ducation.org am gebauten Paket (v71, E182).
@MainActor
enum Materialprobe {

    /// `--materialtest`: liest die Liste aus `MATERIAL_QUELLE` — oder, ohne
    /// Datei und nur auf diesen Aufruf hin, von der Website — und meldet
    /// Kategorien, Kacheln, Übergangene und Adressen. Liegt in
    /// `MATERIAL_ERWARTET` das erwartete JSON der Vorlage (aus
    /// `katalog_pruefen.py --erzeugen`), werden die Zahlen dagegen gehalten:
    /// Die Sollzahlen stammen aus der Vorlage, nie aus dem Code — die
    /// Kachelzahl der Website steigt. Erlaubnis und Einstellungen des Nutzers
    /// bleiben unberührt: Der Lader wird direkt gerufen, wie beim Update-Prüfstand.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        let umgebung = ProcessInfo.processInfo.environment
        let quelle = Materiallader.quelle(umgebung: umgebung, pruefstand: false) ?? Materiallader.schnittstelle
        let lader = Materiallader(quelle: quelle, installiert: Updates.installierterBuild)
        Task { @MainActor in
            var bestanden = true
            func pruefen(_ gilt: Bool, _ text: String) {
                print("  \(gilt ? "✓" : "✗") \(text)")
                if !gilt { bestanden = false }
            }
            print("MATERIALTEST Quelle: \(quelle.absoluteString)")
            let befund = await lader.laden()
            switch befund {
            case .geladen(let katalog):
                let kacheln = katalog.kategorien.flatMap(\.kacheln)
                let https = kacheln.filter { $0.adresse.hasPrefix("https://") }.count
                print("MATERIALTEST Befund: geladen — \(katalog.kategorien.count) Kategorien, "
                      + "\(katalog.kacheln) Kacheln, \(katalog.uebergangen) übergangen")
                print("MATERIALTEST Adressen: \(kacheln.count), davon https \(https)")
                pruefen(!katalog.kategorien.isEmpty, "die Liste hat Kategorien")
                pruefen(kacheln.allSatisfy { Weblinks.pruefen($0.adresse) == $0.adresse },
                        "jede Adresse ist geprüft (http oder https)")
                pruefen(kacheln.allSatisfy { !$0.titel.isEmpty }, "jede Kachel hat einen Titel")
                if let pfad = umgebung["MATERIAL_ERWARTET"], !pfad.isEmpty {
                    if let daten = try? Data(contentsOf: URL(fileURLWithPath: pfad)),
                       let erwartet = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
                       let kategorien = erwartet["kategorien"] as? Int, let alle = erwartet["kacheln"] as? Int {
                        pruefen(katalog.kategorien.count == kategorien,
                                "Kategorien wie erwartet: \(katalog.kategorien.count) = \(kategorien)")
                        pruefen(katalog.kacheln + katalog.uebergangen == alle,
                                "Kacheln wie erwartet: \(katalog.kacheln) + \(katalog.uebergangen) übergangen = \(alle)")
                    } else {
                        pruefen(false, "MATERIAL_ERWARTET ließ sich nicht lesen: \(pfad)")
                    }
                }
            case .nichtErreichbar:
                print("MATERIALTEST Befund: nicht erreichbar")
                pruefen(false, "die Quelle ist nicht erreichbar")
            case .unlesbar(let grund):
                print("MATERIALTEST Befund: unlesbar — \(grund)")
                pruefen(false, "die Liste ließ sich nicht lesen")
            case .keineErlaubnis:
                print("MATERIALTEST Befund: keine Erlaubnis")
                pruefen(false, "der Lader fragt nicht nach der Erlaubnis — das tut der Koordinator")
            }
            print(bestanden ? "MATERIALTEST bestanden" : "MATERIALTEST mit Befund")
            fflush(stdout)
            await Pruefstaende.abschliessenUndBeenden(speicher)
        }
    }
}
