// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Sitzplan je Klasse — der Weg vom Speicher zum Dienst ─────────────────────
// Die Pläne liegen im Sitzplandienst neben der Planung, unter ihrem Schutz;
// hier stehen Editor-Zustand, Rückfragen und die Haken der Übergänge.
extension Planungsspeicher {

    /// Der Hinweis im Editor, solange die Verschlüsselung nicht eingeschaltet
    /// ist (E22) — Wortlaut des Nutzers.
    static let sitzplanDatenschutzhinweis =
        "Das Aktivieren der Verschlüsselung wird vor Verwendung dieser Funktion empfohlen, "
        + "um dem Datenschutz vollumfänglich Rechnung zu tragen."

    func sitzplan(fuer klasseId: String) -> Sitzplan? {
        sitzplaene.plan(fuer: klasseId)
    }

    /// Die Klasse, deren Sitzplan der Editor zeigt.
    var sitzplanKlasseStand: Klasse? {
        sitzplanKlasse.flatMap { planung?.klasse($0) }
    }

    /// Den Editor öffnen — aus ⌘K mit Rückweg dorthin, aus der Kurszelle ohne.
    func sitzplanOeffnen(klasse id: String, zurueck: Dialogfenster? = nil) {
        guard let zeile = planung?.klasse(id) else { return }
        // Eine Sonderzeile hat keinen Sitzplan (E161) — die Oberfläche bietet ihn nicht an.
        guard zeile.erlaubtSitzplan else {
            melden("Für „\(zeile.name)“ ist kein Sitzplan vorgesehen.", .warnung)
            return
        }
        if let hinweis = sitzplaene.sperrhinweis {
            melden(hinweis, .warnung)
            return
        }
        // Netz: Der Editor zeigt keine Bindung an eine Person, die es nicht mehr gibt (E345 c) —
        // gemeldet, wenn das Blatt zu ist; hinter ihm verfiele die Meldung (Z-AS5a-01, wie E334).
        // Ebenso ein Schreibfehler der Sitzpläne dabei: aufgefangen statt gleich gesagt (B96, E420).
        let fang = Meldungsfang()
        let geloest = {
            let senke = sitzplaene.melden
            sitzplaene.melden = { text, art in fang.meldungen.append((text, art)) }
            defer { sitzplaene.melden = senke }  // auf jedem Weg zurück (Z-AU7-06)
            return sitzplanbindungenStillLoesen()
        }()
        sitzplanKlasse = id
        sitzplanRueckweg = zurueck
        sitzplanEntwurf = sitzplaene.plan(fuer: id)
        dialogOeffnen(.sitzplan)
        for meldung in fang.meldungen { spaeterMelden(meldung.text, meldung.art) }
        if geloest > 0 { spaeterMelden(Self.bindungenGeloest(geloest)) }
    }

    /// Das Blatt geht zu: Entwurf weg, Rückweg vormerken. Das Schließen
    /// selbst übernimmt das Blatt (`dismiss`).
    func sitzplanDialogSchliessen() {
        sitzplanEntwurf = nil
        if let zurueck = sitzplanRueckweg { dialogVormerken(zurueck) }
        sitzplanRueckweg = nil
    }

    /// Den Entwurf übernehmen — liefert den Grund, wenn die Platte ihn nicht
    /// trägt (er gilt dann für die Sitzung).
    @discardableResult
    func sitzplanUebernehmen(_ plan: Sitzplan) -> String? {
        // Netz: Ein Entwurf schreibt keine Bindung an eine Person zurück, die es nicht mehr gibt (E345 c) —
        // gelöst vor dem Schreiben: ein Schreiben, ein Grund (Z-AS5a-04).
        var plan = plan
        var geloest = 0
        if let bekannt = bekannteKennungenFuerAbgleich {
            for stelle in plan.tische.indices where !plan.tische[stelle].lernender.isEmpty
                && !bekannt.contains(plan.tische[stelle].lernender) {
                plan.tische[stelle].lernender = ""
                geloest += 1
            }
        }
        let grund = sitzplaene.setzen(plan, fuer: plan.klasseId)
        if grund == nil {
            melden("Sitzplan übernommen — \(plan.tische.count) "
                   + (plan.tische.count == 1 ? "Platz." : "Plätze."))
        }
        if geloest > 0 { melden(Self.bindungenGeloest(geloest)) }
        return grund
    }

    /// Zweistufig, jederzeit: die Rückfrage vor dem endgültigen Löschen. Aus
    /// dem Editor (`ort: .sitzplan`) läuft `danach` nach dem Löschen — das
    /// Blatt schließt sich.
    func sitzplanEntfernen(klasse id: String, ort: Rueckfrageort,
                           danach: (@MainActor () -> Void)? = nil) {
        guard let klasse = planung?.klasse(id), sitzplaene.plan(fuer: id) != nil else { return }
        fragen("Den Sitzplan von „\(klasse.name)“ endgültig löschen?\n\n"
               + "Ein gesichertes PDF bleibt davon unberührt; die Namen lassen sich jederzeit neu eingeben.",
               bestaetigung: "Sitzplan löschen", gefahr: true, ort: ort, nachDemSchliessen: true) { [weak self] in
            guard let self else { return }
            // Die Tasche vor dem Entfernen füllen — danach ist er fort; er reist
            // als Beiwerk eines Schrittes mit, damit ⌘Z ihn zurückholt (S6) und
            // ⇧⌘Z den nimmt, der dann liegt (N58-02, E110).
            let beiwerk = sitzplanBeiwerk(fuer: id)
            if let grund = sitzplaene.setzen(nil, fuer: id) {
                melden("Der Sitzplan wurde entfernt, die Platte trägt ihn womöglich noch (\(grund)).", .warnung)
            } else {
                melden("Sitzplan von „\(klasse.name)“ gelöscht.")
            }
            nurBeiwerkAnmelden(Schrittname.sitzplanEntfernen, beiwerk: beiwerk)
            danach?()
        }
    }

    // ── ⌘P und ⇧⌘P aus der Menüleiste, solange der Editor offen ist ───────

    func sitzplanDrucken() {
        guard !frageSperrtBefehl() else { return }
        guard let plan = sitzplanEntwurf, let klasse = sitzplanKlasseStand else {
            listenphaseMelden()
            return
        }
        Sitzplandruck.drucken(plan, klasse: klasse, speicher: self)
    }

    func sitzplanAlsPDFSichern() {
        guard !frageSperrtBefehl() else { return }
        guard let plan = sitzplanEntwurf, let klasse = sitzplanKlasseStand else {
            listenphaseMelden()
            return
        }
        Sitzplandruck.alsPDFSichern(plan, klasse: klasse, speicher: self)
    }

    /// ⌘P oder ⇧⌘P in der Listenphase des Editors: nichts still übergehen (H04) —
    /// eine Sperre am Menübefehl ginge nicht (N04, siehe `Befehle`).
    private func listenphaseMelden() {
        guard offenerDialog == .sitzplan else { return }
        melden("Noch kein Sitzplan zum Drucken — zuerst „Tische anordnen“.")
    }

    // ── Die Haken des Schutzes ────────────────────────────────────────────

    /// Beim Start neben einer Klartext-Planung.
    func sitzplaeneLaden() {
        sitzplanbefundMelden(sitzplaene.laden(stempel: Zeitrechnung.dateistempel()))
    }

    /// Nach dem Entsperren.
    func sitzplaeneOeffnen(_ tresor: Tresor) {
        sitzplanbefundMelden(sitzplaene.oeffnen(mit: tresor, stempel: Zeitrechnung.dateistempel()))
    }

    /// Pläne ohne Klasse (E41): entfernt, aber als Rettungskopie im Register
    /// bewahrt — nach dem Laden einer Planung beim Start, nach dem Entsperren
    /// und nach dem Import; „Neue Planung“ schreibt die Pläne selbst um.
    /// Danach der Abgleich der Bindungen (C, E345) — außer beim Wechsel des
    /// Schuljahrs, der seine Bindungen still löst (`abgleichen: false`, Z-AS5a-06).
    func sitzplaeneAufraeumen(abgleichen: Bool = true) {
        // Nur gegen die geltende Planung — nicht gegen einen geretteten oder
        // gesperrten Stand, dem Klassen fehlen könnten.
        // Und nicht, solange eine Klartextdatei auf die Antwort des Nutzers
        // wartet (E43 (b)) — das Aufräumen käme nach „Versiegeln“ noch einmal.
        guard let planung, sitzplaene.schreibbar, !ablageGesperrt, !sitzplaene.klartextUnbestaetigt else { return }
        let (entfernt, kopie) = sitzplaene.aufraeumen(behalte: Set(planung.klassen.map(\.id)),
                                                      stempel: Zeitrechnung.dateistempel())
        if entfernt > 0 {
            melden((entfernt == 1 ? "Ein Sitzplan ohne Klasse wurde entfernt" : "\(entfernt) Sitzpläne ohne Klasse wurden entfernt")
                   + (kopie.map { " und \(entfernt == 1 ? "liegt" : "liegen") als „\($0)“ neben der Planung" } ?? "")
                   + ".", .warnung)
        }
        // Danach die Bindungen — nach dem Laden, nach dem Entsperren, nach dem Import (E345); die
        // Rettungskopie trägt sie noch wie das Archiv die Personen (Z14c-10).
        if abgleichen { sitzplanbindungenAbgleichen() }
    }

    /// Bindungen an Personen, die die Jahresdatei nicht trägt, lösen — der Name am Tisch bleibt (C, E325);
    /// nach dem Aufräumen, nach dem Einlesen und nach einem Wechsel des Schuljahrs (E345); einmal gemeldet (E346).
    /// Der Editor löst beim Öffnen still und meldet nach dem Schließen, beim Übernehmen vor dem Schreiben.
    ///
    /// **Nur mit gelesener, schreibbarer Jahresdatei der geltenden Planung und schreibbaren Sitzplänen:**
    /// Ist die Verwaltung aus, zu, gesperrt oder fremd, gingen sonst alle Bindungen. Archivierte Personen
    /// stehen in der Jahresdatei und zählen als bekannt (E252).
    func sitzplanbindungenAbgleichen() {
        let geloest = sitzplanbindungenStillLoesen()
        if geloest > 0 { melden(Self.bindungenGeloest(geloest)) }
    }

    /// Die Kennungen der Jahresdatei — oder `nil`, wenn nicht abgeglichen wird.
    private var bekannteKennungenFuerAbgleich: Set<String>? {
        guard lernende.schreibbar, let bestand = lernende.bestand, bestand.planung == planung?.erstellt,
              sitzplaene.schreibbar, !ablageGesperrt, !sitzplaene.klartextUnbestaetigt else { return nil }
        return Set(bestand.lernende.map(\.id))
    }

    /// Löst ohne Meldung und liefert die Zahl der gelösten Tische — die Meldung folgt beim Aufrufer. Nur
    /// Pläne der Klassen der geltenden Planung; verwaiste, deren Rettungskopie scheiterte, bleiben (Z-AS5a-05).
    @discardableResult
    private func sitzplanbindungenStillLoesen() -> Int {
        guard let bekannt = bekannteKennungenFuerAbgleich, let planung else { return 0 }
        let klassen = Set(planung.klassen.map(\.id))
        let tot = sitzplaene.gebundene(in: klassen).subtracting(bekannt)
        let anzahl = sitzplaene.bindungen(an: tot, in: klassen)
        guard anzahl > 0 else { return 0 }
        sitzplaene.bindungenLoesen(tot, in: klassen)
        return anzahl
    }

    /// Der Wortlaut aus E346.
    static func bindungenGeloest(_ anzahl: Int) -> String {
        anzahl == 1
            ? "Eine Zuordnung an einem Tisch wurde gelöst: Die Person steht nicht mehr in der Lernendenverwaltung; "
              + "der Name am Tisch bleibt."
            : "\(anzahl) Zuordnungen an Tischen wurden gelöst: Die Personen stehen nicht mehr in der "
              + "Lernendenverwaltung; die Namen an den Tischen bleiben."
    }

    /// E43 (b): Klartext neben der versiegelten Planung wird nicht still
    /// übernommen — der Nutzer versiegelt oder legt beiseite; Beiseitegelegtes
    /// bleibt als Rettungskopie im Register.
    private func klartextFragen(_ anzahl: Int, bilanz: Sitzplandatei.Bilanz, kopie: String?) {
        var text = "\(anzahl) \(anzahl == 1 ? "Sitzplan liegt" : "Sitzpläne liegen") im Klartext neben der "
            + "versiegelten Planung — aus einer früheren Fassung oder von fremder Hand. "
            + "Jetzt versiegeln oder beiseitelegen?"
        if bilanz.verlust {
            text += "\n\nBeim Lesen bereinigt: \(bilanz.beschreibung)"
                + (kopie.map { "; das Original liegt als „\($0)“ neben der Planung" } ?? "") + "."
        }
        text += "\n\nBeiseitegelegtes bleibt als Rettungskopie neben der Planung."
        // „Beiseitelegen“ leert die Sitzpläne der Hauptfläche; „Versiegeln“ geht denselben Weg (B95, Z-AU4-02).
        fragen(text, bestaetigung: "Versiegeln", ort: .hauptansicht, ablehnung: "Beiseitelegen",
               beiAblehnung: { [weak self] in
            self?.klartextBeiseitelegen()
            self?.sitzplanantwortFortsetzen()
        }, nachDemSchliessen: true) { [weak self] in
            guard let self else { return }
            sitzplaene.klartextVersiegeln()
            if sitzplaene.ungesichert == nil {
                melden("\(anzahl) \(anzahl == 1 ? "Sitzplan ist" : "Sitzpläne sind") jetzt versiegelt.")
            }
            sitzplaeneAufraeumen()
            sitzplanantwortFortsetzen()
        }
    }

    /// Was auf die Antwort wartete (das Angleichen der Wicklung dieses Macs,
    /// F04), läuft jetzt — nur wenn die Frage wirklich beantwortet ist. Blieb
    /// die Datei im Weg, steht die Frage beim nächsten Start wieder, und die
    /// Wicklung wartet bis dahin.
    private func sitzplanantwortFortsetzen() {
        guard !sitzplaene.klartextUnbestaetigt, let fortsetzung = nachSitzplanantwort else { return }
        nachSitzplanantwort = nil
        fortsetzung()
    }

    private func klartextBeiseitelegen() {
        if let name = sitzplaene.klartextBeiseitelegen(stempel: Zeitrechnung.dateistempel()) {
            melden("Die Sitzpläne wurden beiseitegelegt und liegen als „\(name)“ neben der Planung.")
        } else {
            melden("Die Sitzplandatei ließ sich nicht beiseitelegen — sie bleibt liegen; die App fragt "
                   + "beim nächsten Start erneut.", .warnung)
        }
    }

    /// Gemeldet wird, was vom Gewöhnlichen abweicht — nie still.
    private func sitzplanbefundMelden(_ befund: Sitzplandienst.Ladebefund) {
        switch befund {
        case .geladen, .keine:
            break
        case .bereinigt(let anzahl, let bilanz, let kopie):
            melden("Die Sitzpläne (\(anzahl)) wurden beim Lesen bereinigt: \(bilanz.beschreibung). "
                   + (kopie.map { "Das Original liegt als „\($0)“ neben der Planung." }
                      ?? "Eine Kopie des Originals ließ sich nicht anlegen; bis es gelingt, "
                         + "wird nichts darüber geschrieben."), .warnung)
        case .klartextGefunden(let anzahl, let bilanz, let kopie):
            klartextFragen(anzahl, bilanz: bilanz, kopie: kopie)
        case .beiseitegelegt(let grund, let rettung):
            melden("Die Sitzpläne galten nicht (\(grund)) und liegen als „\(rettung)“ neben der "
                   + "Planung — bitte neu anlegen.", .warnung)
        case .gesperrt(let grund):
            melden("Die Sitzpläne bleiben unangetastet (\(grund)). Bis der nächste Start sie liest, "
                   + "lässt sich kein Sitzplan öffnen.", .warnung)
        }
    }
}

/// Was der Sitzplandienst beim Öffnen des Editors meldet — aufgefangen, damit es nach dem Blatt kommt (B96).
@MainActor
private final class Meldungsfang {
    var meldungen: [(text: String, art: Meldung.Art)] = []
}
