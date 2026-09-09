// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Stand aus der Ansicht fürs iPad ──────────────────────────────────────────
// Gelesen wird im Sicherungsdienst, entziffert und verglichen im
// `Statusabgleich`; hier stehen die Reihenfolge und die Sätze dazu.
extension Planungsspeicher {

    /// Sucht die Statusdatei im Ordner der Sicherungskopie und übernimmt sie.
    /// Gemeldet wird nur, was sich geändert hat, und ein Fehler in der Datei.
    func statusUebernehmen() {
        guard planung != nil, !autoexportOrdner.isEmpty else { return }
        // Ein Ordner, der gerade fehlt oder noch nicht gewählt ist, meldet sich
        // beim Schreiben der Kopie — hier bleibt es still.
        let gelesen: Data?
        do {
            gelesen = try sicherung.statusdateiLesen()
        } catch {
            // Was an der Datei selbst liegt, wird benannt; ein Zielordner, der
            // fehlt oder noch nicht freigegeben ist, meldet sich beim Schreiben
            // der Kopie oder beim Übergang des Schutzes.
            switch error {
            case .zuGross(let groesse):
                melden("Die Statusdatei aus der iPad-Ansicht ist ungewöhnlich groß "
                       + "(\(groesse / 1024 / 1024) MB) und wurde nicht eingelesen.", .warnung)
            case .schreiben(let grund):
                melden("Die Statusdatei aus der iPad-Ansicht ließ sich nicht lesen (\(grund)) "
                       + "und wurde nicht eingelesen.", .warnung)
            case .zielordner, .fremderSchluessel, .keinStatus:
                break
            }
            return
        }
        guard let roh = gelesen else { return }

        let daten: Data
        do {
            daten = try Statusabgleich.entsiegeln(roh, tresor: tresor)
        } catch {
            melden(error.text, .warnung)
            return
        }

        do {
            let stand = try Statusabgleich.lesen(daten)
            // Welcher Eintrag zählt, entscheidet der Abgleich je Vorhaben —
            // eine Schranke über die ganze Datei bräuchte einen gemerkten Stempel,
            // und ein einziger falscher sperrte damit jeden späteren Stand aus.
            if !Statusabgleich.zeitstempelBrauchbar(stand.gespeichert) {
                melden("Die Statusdatei aus der iPad-Ansicht trägt keinen brauchbaren "
                       + "Zeitpunkt. Bitte Datum und Uhrzeit des iPads prüfen — sonst "
                       + "bleiben Einträge ohne eigenen Stempel liegen.", .warnung)
            }

            let (haken, notizen) = statusAnwenden(stand)
            guard haken > 0 || notizen > 0 else { return }
            melden("Aus der Ansicht fürs iPad übernommen: "
                   + [haken > 0 ? "\(haken) \(haken == 1 ? "Markierung" : "Markierungen")" : nil,
                      notizen > 0 ? "\(notizen) \(notizen == 1 ? "Kommentar" : "Kommentare")" : nil]
                        .compactMap { $0 }.joined(separator: " und ") + ".")
        } catch {
            melden(error.text, .warnung)
        }
    }

    /// Der Abgleich an der Planung der Sitzung; geschrieben wird, sobald sich
    /// etwas geändert hat — auch nur ein Stempel.
    @discardableResult
    func statusAnwenden(_ stand: Statusstand) -> (erledigt: Int, kommentare: Int) {
        guard var p = planung else { return (0, 0) }
        let (haken, notizen, geaendert) = Statusabgleich.anwenden(stand, auf: &p)
        guard geaendert else { return (0, 0) }
        planung = p
        sichern()
        return (haken, notizen)
    }

    /// Taugt der Zeitstempel als Schranke zwischen beiden Fassungen? Die Regel
    /// steht im `Statusabgleich`.
    static func zeitstempelBrauchbar(_ wert: String, jetzt: Date = Date()) -> Bool {
        Statusabgleich.zeitstempelBrauchbar(wert, jetzt: jetzt)
    }
}
