// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Die Naht der Prüfungen am Lesen der Statusdatei (R75-01, v76): hält das
/// Lesen an wie ein langsamer Speicher. Gesetzt nur in den Prüfungen; im
/// Betrieb ist sie nil, und `Pruefziel.ja` ist falsch.
enum Statusnaht {
    @TaskLocal static var halten: (@Sendable () -> Void)?
}

// ── Stand aus der Ansicht fürs iPad ──────────────────────────────────────────
// Gelesen wird im Sicherungsdienst, entziffert und verglichen im
// `Statusabgleich`; hier stehen die Reihenfolge und die Sätze dazu. Drei
// Stufen, ein Weg (R75-01, E226 a, v76): der Zugang auf dem Hauptstrang, das
// Lesen samt Entsiegeln und Deuten — nach dem Aufwachen und auf Befehl abseits
// des Hauptstrangs, sonst gleich —, das Anwenden auf dem Hauptstrang.
extension Planungsspeicher {

    /// Was eine Übernahme ergab — der Befehl „Stand der Web App abrufen“
    /// antwortet danach auch dann, wenn nichts kam.
    enum Statusuebernahme: Equatable { case uebernommen, nichtsNeues, hindernis, zielordnerFehlt }

    /// Was das Lesen ergab — ohne Planung und ohne Meldung, darum gleich oder
    /// abseits des Hauptstrangs zu gewinnen.
    enum Statuslesung: Sendable {
        case keine
        case zielordner
        /// Etwas an der Datei: der Satz, der gemeldet wird — oder keiner.
        case hindernis(String?)
        case stand(Statusstand)
    }

    /// Stufe 2: lesen, entsiegeln, deuten. Berührt weder die Sitzung noch die
    /// Oberfläche.
    nonisolated static func statusLesen(_ zugang: Sicherungsdienst.Statuszugang, tresor: Tresor?) -> Statuslesung {
        let roh: Data?
        do {
            roh = try Sicherungsdienst.statusdateiLesen(zugang)
        } catch {
            // Was an der Datei selbst liegt, wird benannt; ein Zielordner, der
            // fehlt oder noch nicht freigegeben ist, meldet sich beim Schreiben
            // der Kopie oder beim Übergang des Schutzes — und beim Befehl (B61).
            switch error {
            case .zuGross(let groesse):
                return .hindernis("Die Statusdatei der Web App ist ungewöhnlich groß "
                                  + "(\(groesse / 1024 / 1024) MB) und wurde nicht eingelesen.")
            case .schreiben(let grund):
                return .hindernis("Die Statusdatei der Web App ließ sich nicht lesen (\(grund)) "
                                  + "und wurde nicht eingelesen.")
            case .zielordner:
                return .zielordner
            case .fremderSchluessel, .keinStatus:
                return .hindernis(nil)
            }
        }
        guard let roh else { return .keine }
        do {
            let daten = try Statusabgleich.entsiegeln(roh, tresor: tresor)
            return .stand(try Statusabgleich.lesen(daten))
        } catch {
            return .hindernis(error.text)
        }
    }

    /// Stufe 3, auf dem Hauptstrang: anwenden und melden. Gemeldet wird nur,
    /// was sich geändert hat, und ein Fehler in der Datei.
    private func statusUebernehmen(aus lesung: Statuslesung) -> Statusuebernahme {
        switch lesung {
        case .keine:
            return .nichtsNeues
        case .zielordner:
            return .zielordnerFehlt
        case .hindernis(let satz):
            if let satz { melden(satz, .warnung) }
            return .hindernis
        case .stand(let stand):
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
        }
    }

    /// Gleichlaufend — beim Laden (Start, nach dem Entsperren), beim Übergang
    /// des Schutzes und nach der Nachwahl: Dort wartet der Nutzer ohnehin, und
    /// die Folge ist festgelegt (E226 a). Dieselben drei Stufen wie im
    /// Hintergrund, hintereinander.
    @discardableResult
    func statusUebernehmen() -> Statusuebernahme {
        guard planung != nil, !autoexportOrdner.isEmpty else { return .nichtsNeues }
        let zugang: Sicherungsdienst.Statuszugang
        do { zugang = try sicherung.statuszugang() } catch { return .zielordnerFehlt }
        if Pruefziel.ja { Statusnaht.halten?() }
        let lesung = Planungsspeicher.statusLesen(zugang, tresor: tresor)
        if case .zielordner = lesung {} else { sicherung.nachfuehren(zugang) }
        return statusUebernehmen(aus: lesung)
    }

    /// Nach dem Aufwachen und auf Befehl (R75-01, E226 a): Lesen, Entsiegeln und
    /// Deuten abseits des Hauptstrangs — ein langsamer Speicherort hält die App
    /// nicht an. Gelesen wird auf einer Warteschlange von GCD, nicht im
    /// Fadenvorrat der Nebenläufigkeit: Ein hängender Speicher hält dort einen
    /// Faden fest, und davon hat der Vorrat nur so viele wie Kerne; GCD legt nach.
    /// Vor dem Anwenden wird geprüft, ob es noch gilt: die jüngste Anfrage,
    /// dieselbe Planung, derselbe Schlüssel, derselbe Zielordner — sonst
    /// verworfen. Beim Laden und beim Übergang des Schutzes liest die App die
    /// Datei ohnehin auf ihrem eigenen Weg, sonst beim nächsten Abruf. Ist dann
    /// etwas offen, wird vorgemerkt. `nil`: verworfen oder vorgemerkt.
    func statusUebernehmenImHintergrund() async -> Statusuebernahme? {
        guard planung != nil, !autoexportOrdner.isEmpty else { return .nichtsNeues }
        statusAnfrage &+= 1
        let nummer = statusAnfrage
        let planungVorher = planung?.erstellt
        let tresorVorher = tresor
        let ordnerVorher = autoexportOrdner
        let zugang: Sicherungsdienst.Statuszugang
        do { zugang = try sicherung.statuszugang() } catch { return .zielordnerFehlt }
        let halten = Pruefziel.ja ? Statusnaht.halten : nil
        let lesung: Statuslesung = await withCheckedContinuation { fortsetzung in
            DispatchQueue.global(qos: .userInitiated).async {
                halten?()
                fortsetzung.resume(returning: Planungsspeicher.statusLesen(zugang, tresor: tresorVorher))
            }
        }
        guard nummer == statusAnfrage, planung?.erstellt == planungVorher,
              tresor === tresorVorher, autoexportOrdner == ordnerVorher else { return nil }
        guard !statusMussWarten else {
            statusVorgemerkt = true
            return nil
        }
        if case .zielordner = lesung {} else { sicherung.nachfuehren(zugang) }
        return statusUebernehmen(aus: lesung)
    }

    /// Hinter einem offenen Blatt, Dialog oder einer Rückfrage soll sich die
    /// Planung nicht ändern — ebenso nicht beim Entsperren und während einer
    /// Schlüsselarbeit (E216 d), und nicht hinter einem Dialog des Systems am
    /// Hauptfenster (B64, v76).
    var statusMussWarten: Bool {
        dialogOffen || naechsterDialog != nil || entsperrungOffen || schluesselarbeitLaeuft
            || Dialogort.freieDialoge > 0
    }

    /// Nach dem Aufwachen des Macs aus dem Ruhezustand: Der Anwendungsdelegat
    /// ruft das einmal, 15 Sekunden danach (E216 d). **Bewusst so** — kein
    /// Takt, nicht beim Aufwachen des Bildschirms, keine Wiederholung; siehe
    /// CHANGELOG 1.9.4, „Bewusst so entschieden“. Ist dann etwas offen, wird
    /// vorgemerkt und beim Schließen einmal nachgeholt. Die Aufgabe gibt es
    /// zurück, damit Prüfungen auf ihr Ende warten können.
    @discardableResult
    func statusNachAufwachen() -> Task<Statusuebernahme?, Never>? {
        guard planung != nil, !autoexportOrdner.isEmpty else { return nil }
        guard !statusMussWarten else {
            statusVorgemerkt = true
            return nil
        }
        return Task { @MainActor [weak self] in await self?.statusUebernehmenImHintergrund() }
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
            _ = await statusUebernehmenImHintergrund()
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
    /// auch dann, wenn nichts kam; gelesen abseits des Hauptstrangs. Die
    /// Aufgabe gibt es zurück, damit Prüfungen auf ihr Ende warten können.
    @discardableResult
    func statusAbrufen() -> Task<Statusuebernahme?, Never>? {
        guard planung != nil else { return nil }
        guard !autoexportOrdner.isEmpty else {
            melden("Für den Stand der Web App ist kein Zielordner gewählt — unter „Einstellungen“ festlegen.",
                   .warnung)
            return nil
        }
        statusVorgemerkt = false
        return Task { @MainActor [weak self] in
            guard let self, let ergebnis = await statusUebernehmenImHintergrund() else { return nil }
            switch ergebnis {
            case .nichtsNeues:
                melden("Von der Web App liegt nichts Neues vor.")
            case .zielordnerFehlt:
                melden("Der Zielordner ist gerade nicht erreichbar — der Stand der Web App wurde nicht gelesen.",
                       .warnung)
            case .uebernommen, .hindernis:
                break
            }
            return ergebnis
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
