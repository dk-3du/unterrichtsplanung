// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Die Naht der Prüfungen am Lesen der Statusdatei (R75-01, v76): hält das
/// Lesen an wie ein langsamer Speicher. Gesetzt nur in den Prüfungen; im
/// Betrieb ist sie nil, und `Pruefziel.ja` ist falsch.
enum Statusnaht {
    @TaskLocal static var halten: (@Sendable () -> Void)?
    /// Dieselbe Naht eine Stufe früher: hält beim Auflösen des Lesezeichens
    /// an, vor dem Lesen (R76-02, v77). Die alte Naht liegt dahinter und
    /// könnte über diese Stufe nichts aussagen.
    @TaskLocal static var haltenBeimZugang: (@Sendable () -> Void)?
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

    /// Stufe 2: auflösen, lesen, entsiegeln, deuten. Berührt weder die Sitzung
    /// noch die Oberfläche. Seit 1.9.6 gehört das Auflösen des Lesezeichens
    /// dazu (R76-02, E237) — auch es fasst den Zielordner an.
    ///
    /// Zurück kommt neben der Lesung, was der Hauptstrang danach nachzuführen
    /// hat: der Pfad eines umbenannten Ordners und ein erneuertes Lesezeichen.
    /// `nil` heißt, dass schon das Auflösen scheiterte — dann gibt es nichts
    /// nachzuführen.
    nonisolated static func statusLesen(_ zugang: Sicherungsdienst.Statuszugang, tresor: Tresor?,
                                        beimZugang: (@Sendable () -> Void)? = nil)
        -> (lesung: Statuslesung, nachfuehrung: Sicherungsdienst.Nachfuehrung?) {
        beimZugang?()
        let bereich: Ordnerzugriff.Bereich?
        let nachfuehrung: Sicherungsdienst.Nachfuehrung?
        do {
            (bereich, nachfuehrung) = try Sicherungsdienst.statuszugriff(zugang)
        } catch {
            // Aus dem Zugang kommt nur `.zielordner`: kein Lesezeichen, nicht
            // aufzulösen, kein Zugriff.
            return (.zielordner, nil)
        }
        return (statusDeuten(bereich: bereich, ordner: zugang.ordner, tresor: tresor), nachfuehrung)
    }

    /// Stufe 2b: lesen, entsiegeln, deuten — im aufgelösten Bereich.
    nonisolated private static func statusDeuten(bereich: Ordnerzugriff.Bereich?, ordner: URL,
                                                 tresor: Tresor?) -> Statuslesung {
        let roh: Data?
        do {
            roh = try Sicherungsdienst.statusdateiLesen(bereich: bereich, ordner: ordner)
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
        let (lesung, nachfuehrung) = Planungsspeicher.statusLesen(
            zugang, tresor: tresor, beimZugang: Pruefziel.ja ? Statusnaht.haltenBeimZugang : nil)
        if case .zielordner = lesung {} else { sicherung.nachfuehren(nachfuehrung) }
        return statusUebernehmen(aus: lesung)
    }

    /// Nach dem Aufwachen und auf Befehl (R75-01, E226 a): Lesen, Entsiegeln und
    /// Deuten abseits des Hauptstrangs — ein langsamer Speicherort hält die App
    /// nicht an. Gelesen wird auf einer Warteschlange von GCD, nicht im
    /// Fadenvorrat der Nebenläufigkeit: Ein hängender Speicher hält dort einen
    /// Faden fest, und davon hat der Vorrat nur so viele wie Kerne; GCD legt nach.
    /// Vor dem Anwenden wird geprüft, ob es noch gilt: die jüngste Anfrage und
    /// dieselbe Sitzung — sonst verworfen. Die **Marke der Sitzung** deckt
    /// Planung, Schlüssel und Zielordner in einer Zahl (`sitzungsmarke`,
    /// E236, v77); bis 1.9.5 standen hier `planung?.erstellt`, `tresor ===`
    /// und der Ordner einzeln, und der Zeitstempel aus der Datei hielt nicht,
    /// was er versprach. Beim Laden und beim Übergang des Schutzes liest die
    /// App die Datei ohnehin auf ihrem eigenen Weg, sonst beim nächsten
    /// Abruf. Ist dann etwas offen, wird vorgemerkt. `nil`: verworfen oder
    /// vorgemerkt.
    func statusUebernehmenImHintergrund() async -> Statusuebernahme? {
        guard planung != nil, !autoexportOrdner.isEmpty else { return .nichtsNeues }
        // Es liest einer zugleich (R76-03, E238, v77). Jede weitere Anfrage
        // bündelt sich zu **einer** Wiederholung: Bis 1.9.5 legte jede einen
        // weiteren Leser an, und gegen einen hängenden Speicher hielt jeder
        // einen Faden und einen Sicherheitsbereich fest (gemessen: 40
        // Anfragen, 40 hängende Leser). Der Merker ist derselbe, der auch
        // hinter Blättern vormerkt — `statusNachholenWennFrei` holt beides.
        guard !statusLaeuft else {
            statusVorgemerkt = true
            return nil
        }
        statusLaeuft = true
        defer {
            statusLaeuft = false
            statusNachholenWennFrei()
        }
        statusAnfrage &+= 1
        let nummer = statusAnfrage
        let markeVorher = sitzungsmarke
        let tresorVorher = tresor
        let zugang: Sicherungsdienst.Statuszugang
        do { zugang = try sicherung.statuszugang() } catch { return .zielordnerFehlt }
        let halten = Pruefziel.ja ? Statusnaht.halten : nil
        let beimZugang = Pruefziel.ja ? Statusnaht.haltenBeimZugang : nil
        let ergebnis = await withCheckedContinuation { fortsetzung in
            DispatchQueue.global(qos: .userInitiated).async {
                halten?()
                fortsetzung.resume(returning: Planungsspeicher.statusLesen(
                    zugang, tresor: tresorVorher, beimZugang: beimZugang))
            }
        }
        // **Kein Wächter auf `Task.isCancelled` — bewusst so** (R77-01, E242,
        // v78): Eine zugelassene Übernahme läuft zu Ende. Im Betrieb bricht
        // niemand ab; der Menübefehl und der Anwendungsdelegat verwerfen die
        // Aufgabe, und der Abbruch im `Aufwachabruf` trifft die Wartezeit von
        // 15 Sekunden, nach der gar nicht mehr gelesen wird. Ein Wächter
        // brächte auch nichts ein: Gelesen wird in einem Block auf einer
        // Warteschlange von GCD hinter `withCheckedContinuation`, und der ist
        // nicht abbruchfähig — unterdrückt würde das Anwenden, während Faden
        // und Sicherheitsbereich weiter hingen. Verworfen wird nach der Lage,
        // nicht nach dem Willen des Aufrufers: Anfragenummer und Marke der
        // Sitzung. Festgehalten in `StatusAbrufPruefungen`, „Ein Abbruch …“.
        guard nummer == statusAnfrage, sitzungsmarke == markeVorher else { return nil }
        guard !statusMussWarten else {
            statusVorgemerkt = true
            return nil
        }
        // Erst hinter dem Wächter: Auch ein erneuertes Lesezeichen gehört zur
        // Lage, in der gefragt wurde (E237).
        if case .zielordner = ergebnis.lesung {} else { sicherung.nachfuehren(ergebnis.nachfuehrung) }
        return statusUebernehmen(aus: ergebnis.lesung)
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
    /// zurück, damit Prüfungen auf ihr Ende warten können — sie ist eine
    /// **Wartemarke, kein Griff zum Abbrechen** (E242; die Politik steht
    /// in `statusUebernehmenImHintergrund`).
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
        guard statusVorgemerkt, !statusMussWarten, !statusLaeuft else { return }
        Task { @MainActor [weak self] in
            guard let self, statusVorgemerkt, !statusMussWarten, !statusLaeuft else { return }
            statusVorgemerkt = false
            guard planung != nil, !autoexportOrdner.isEmpty else { return }
            _ = await statusUebernehmenImHintergrund()
        }
    }

    /// Ob „Stand der Web App abrufen“ im Menü angeboten wird oder ausgegraut
    /// ist — die eine Stelle, die `StatusAbrufBefehl` liest: eine Planung ist
    /// offen (E224), ein Zielordner gewählt (E223), und es liest gerade
    /// niemand (E238, v77 — solange gelesen wird, täte ein Griff ins Menü
    /// nichts; grau sagt das). Gelesen wird nur, was sich selten ändert:
    /// `hatPlanung` wechselt, wenn eine Planung kommt oder geht, nicht bei
    /// jeder Bearbeitung (`planung` selbst zu lesen, hieße: das Menü bei jeder
    /// Änderung neu bauen, N04).
    var statusAbrufAngeboten: Bool { hatPlanung && !autoexportOrdner.isEmpty && !statusLaeuft }

    /// „Stand der Web App abrufen“ im Menü „Ablage“: sofort — und mit Antwort
    /// auch dann, wenn nichts kam; gelesen abseits des Hauptstrangs. Die
    /// Aufgabe gibt es zurück, damit Prüfungen auf ihr Ende warten können —
    /// sie ist eine **Wartemarke, kein Griff zum Abbrechen** (E242; die
    /// Politik steht in `statusUebernehmenImHintergrund`).
    @discardableResult
    func statusAbrufen() -> Task<Statusuebernahme?, Never>? {
        guard planung != nil else { return nil }
        guard !autoexportOrdner.isEmpty else {
            melden("Für den Stand der Web App ist kein Zielordner gewählt — unter „Einstellungen“ festlegen.",
                   .warnung)
            return nil
        }
        // Läuft schon ein Lesen, sagt der Befehl es (B68, v77). Das Grau am
        // Menüeintrag deckt den Normalfall; es wird aber beim **Öffnen** des
        // Menüs ausgewertet, und eine Aufgabe des Hauptakteurs läuft bei
        // offenem Menü weiter (v76 gemessen) — wer während eines anlaufenden
        // Abrufs klickt, bekäme sonst gar keine Antwort, und der Befehl sagt
        // seit 1.9.4 eine zu (B61).
        //
        // **Die Anfrage bleibt bestehen** (E238): Sie bündelt sich wie jede
        // andere zu einer Wiederholung. Das laufende Lesen hat die Datei
        // womöglich geöffnet, bevor das Gerät geschrieben hat — wer jetzt
        // fragt, will den Stand von jetzt.
        guard !statusLaeuft else {
            melden("Der Stand der Web App wird gerade gelesen.")
            statusVorgemerkt = true
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
