// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Stand aus der Ansicht fürs iPad ──────────────────────────────────────────
// Gelesen wird im Sicherungsdienst, entziffert und verglichen im
// `Statusabgleich`; hier stehen die Reihenfolge und die Sätze dazu.
extension Planungsspeicher {

    /// Was eine Übernahme ergab — der Befehl „Stand der Web App abrufen“
    /// antwortet danach auch dann, wenn nichts kam.
    enum Statusuebernahme: Equatable { case uebernommen, nichtsNeues, hindernis, zielordnerFehlt }

    /// Sucht die Statusdatei im Ordner der Sicherungskopie und übernimmt sie.
    /// Gemeldet wird nur, was sich geändert hat, und ein Fehler in der Datei.
    @discardableResult
    func statusUebernehmen() -> Statusuebernahme {
        guard planung != nil, !autoexportOrdner.isEmpty else { return .nichtsNeues }
        // Ein Ordner, der gerade fehlt oder noch nicht gewählt ist, meldet sich
        // beim Schreiben der Kopie — hier bleibt es still.
        let gelesen: Data?
        do {
            gelesen = try sicherung.statusdateiLesen()
        } catch {
            // Was an der Datei selbst liegt, wird benannt; ein Zielordner, der
            // fehlt oder noch nicht freigegeben ist, meldet sich beim Schreiben
            // der Kopie oder beim Übergang des Schutzes — und beim Befehl (B61).
            switch error {
            case .zuGross(let groesse):
                melden("Die Statusdatei der Web App ist ungewöhnlich groß "
                       + "(\(groesse / 1024 / 1024) MB) und wurde nicht eingelesen.", .warnung)
                return .hindernis
            case .schreiben(let grund):
                melden("Die Statusdatei der Web App ließ sich nicht lesen (\(grund)) "
                       + "und wurde nicht eingelesen.", .warnung)
                return .hindernis
            case .zielordner:
                return .zielordnerFehlt
            case .fremderSchluessel, .keinStatus:
                return .hindernis
            }
        }
        guard let roh = gelesen else { return .nichtsNeues }

        let daten: Data
        do {
            daten = try Statusabgleich.entsiegeln(roh, tresor: tresor)
        } catch {
            melden(error.text, .warnung)
            return .hindernis
        }

        do {
            let stand = try Statusabgleich.lesen(daten)
            // Welcher Eintrag zählt, entscheidet der Abgleich je Vorhaben —
            // eine Schranke über die ganze Datei bräuchte einen gemerkten Stempel,
            // und ein einziger falscher sperrte damit jeden späteren Stand aus.
            if !Statusabgleich.zeitstempelBrauchbar(stand.gespeichert) {
                melden("Die Statusdatei der Web App trägt keinen brauchbaren "
                       + "Zeitpunkt. Bitte Datum und Uhrzeit des Geräts mit der Web App prüfen — sonst "
                       + "bleiben Einträge ohne eigenen Stempel liegen.", .warnung)
            }

            // Kommen Haken oder Kommentare, beginnt der Verlauf neu (E84, E217);
            // die Meldung sagt es, wenn es etwas zu widerrufen gab.
            let hatteVerlauf = verlauf.kannZurueck || verlauf.kannVor
            let (haken, notizen) = statusAnwenden(stand)
            guard haken > 0 || notizen > 0 else { return .nichtsNeues }
            melden("Aus der Web App übernommen: "
                   + [haken > 0 ? "\(haken) \(haken == 1 ? "Markierung" : "Markierungen")" : nil,
                      notizen > 0 ? "\(notizen) \(notizen == 1 ? "Kommentar" : "Kommentare")" : nil]
                        .compactMap { $0 }.joined(separator: " und ") + "."
                   + (hatteVerlauf ? " Widerrufen beginnt hier neu." : ""))
            return .uebernommen
        } catch {
            melden(error.text, .warnung)
            return .hindernis
        }
    }

    /// Hinter einem offenen Blatt, Dialog oder einer Rückfrage soll sich die
    /// Planung nicht ändern — ebenso nicht beim Entsperren und während einer
    /// Schlüsselarbeit (E216 d).
    var statusMussWarten: Bool {
        dialogOffen || naechsterDialog != nil || entsperrungOffen || schluesselarbeitLaeuft
    }

    /// Nach dem Aufwachen des Macs aus dem Ruhezustand: Der Anwendungsdelegat
    /// ruft das einmal, 15 Sekunden danach (E216 d). **Bewusst so** — kein
    /// Takt, nicht beim Aufwachen des Bildschirms, keine Wiederholung; siehe
    /// LIESMICH, „Bewusst so entschieden“. Ist dann etwas offen, wird
    /// vorgemerkt und beim Schließen einmal nachgeholt.
    func statusNachAufwachen() {
        guard planung != nil, !autoexportOrdner.isEmpty else { return }
        guard !statusMussWarten else {
            statusVorgemerkt = true
            return
        }
        statusUebernehmen()
    }

    /// Aus den Settern der Blätter, Dialoge und Rückfragen und aus der Sitzung —
    /// jede Bedingung von `statusMussWarten` hat ihren Anstoß, sonst wartete die
    /// Übernahme auf die nächste Änderung (B62, v75). Ist alles zu, holt die App
    /// den vorgemerkten Stand nach — gleich danach,
    /// nicht im Setter: Eine Zuweisung an die Planung in einem `didSet`
    /// übersprünge dort die Beobachter der Sitzung.
    func statusNachholenWennFrei() {
        guard statusVorgemerkt, !statusMussWarten else { return }
        Task { @MainActor [weak self] in
            guard let self, statusVorgemerkt, !statusMussWarten else { return }
            statusVorgemerkt = false
            guard planung != nil, !autoexportOrdner.isEmpty else { return }
            statusUebernehmen()
        }
    }

    /// Ob „Stand der Web App abrufen“ im Menü angeboten wird oder ausgegraut
    /// ist — die eine Stelle, die `StatusAbrufBefehl` liest: eine Planung ist
    /// offen (E224) und ein Zielordner gewählt (E223). Gelesen wird nur, was
    /// sich selten ändert: `hatPlanung` wechselt, wenn eine Planung kommt oder
    /// geht, nicht bei jeder Bearbeitung (`planung` selbst zu lesen, hieße: das
    /// Menü bei jeder Änderung neu bauen, N04).
    var statusAbrufAngeboten: Bool { hatPlanung && !autoexportOrdner.isEmpty }

    /// „Stand der Web App abrufen“ im Menü „Ablage“: sofort — und mit Antwort
    /// auch dann, wenn nichts kam.
    func statusAbrufen() {
        guard planung != nil else { return }
        guard !autoexportOrdner.isEmpty else {
            melden("Für den Stand der Web App ist kein Zielordner gewählt — unter „Einstellungen“ festlegen.",
                   .warnung)
            return
        }
        statusVorgemerkt = false
        switch statusUebernehmen() {
        case .nichtsNeues:
            melden("Von der Web App liegt nichts Neues vor.")
        case .zielordnerFehlt:
            melden("Der Zielordner ist gerade nicht erreichbar — der Stand der Web App wurde nicht gelesen.",
                   .warnung)
        case .uebernommen, .hindernis:
            break
        }
    }

    /// Der Abgleich an der Planung der Sitzung; geschrieben wird, sobald sich
    /// etwas geändert hat — auch nur ein Stempel.
    @discardableResult
    func statusAnwenden(_ stand: Statusstand) -> (erledigt: Int, kommentare: Int) {
        guard var p = planung else { return (0, 0) }
        let (haken, notizen, geaendert) = Statusabgleich.anwenden(stand, auf: &p)
        guard geaendert else { return (0, 0) }
        if haken > 0 || notizen > 0 {
            // Von außen: ein neuer Schauplatz, der Verlauf beginnt neu (E84).
            planung = p
        } else {
            // Nur Stempel — nichts, was man sieht (B59, v75).
            stempelEinsetzen(p)
        }
        sichern()
        return (haken, notizen)
    }
}
