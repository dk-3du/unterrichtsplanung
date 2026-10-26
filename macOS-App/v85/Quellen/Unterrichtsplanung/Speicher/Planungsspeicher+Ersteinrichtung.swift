// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Ersteinrichtung ──────────────────────────────────────────────────────────
// Vier Fragen, alle freiwillig: erst die Verschlüsselung — mit der
// Einrichtung gleich im Blatt; ohne Planung vor „Neue Planung“ (v84, D1b) —,
// nach der ersten Planung die Sicherungskopie beim Beenden, dann die Prüfung
// auf Updates, zuletzt die Materialliste von 3ducation.org (v71, E176).
extension Planungsspeicher {

    /// Wer den Ordner schon gewählt hat, wird nicht gefragt.
    var ersteinrichtungFaellig: Bool {
        Planungsspeicher.ersteinrichtungFaellig(
            pruefstand: Ablage.istPruefstand,
            ordner: autoexportOrdner,
            gefragt: Einstellungen.wert(Einstellungen.Schluessel.autoexportGefragt) ?? false)
    }

    /// Die Entscheidung ohne ihre drei Quellen — sonst ließe sie sich nicht
    /// prüfen: Im Prüflauf ist `Ablage.istPruefstand` gesetzt.
    static func ersteinrichtungFaellig(pruefstand: Bool, ordner: String, gefragt: Bool) -> Bool {
        !pruefstand && ordner.isEmpty && !gefragt
    }

    /// Die Stationen des Blatts: die Frage nach der Verschlüsselung, deren
    /// zwei Einrichtungsschritte, die Frage nach der Sicherungskopie, die Frage
    /// nach den Updates, die Frage nach der Materialliste. Im Speicher statt im
    /// Blatt, damit Prüfungen und Abbilder jede erreichen.
    enum Ersteinrichtungsschritt: Equatable, Sendable {
        case verschluesselung
        case passphrase
        /// Mit dem Wiederherstellungsschlüssel, der nur hier gezeigt wird.
        case blatt(String)
        case sicherung
        /// Beim Öffnen nach Updates suchen? Nur mit Einwilligung.
        case updates
        /// Die Materialliste von 3ducation.org im Vorhaben-Dialog anbieten?
        /// Nur mit Erlaubnis (v71, E176).
        case materialien
    }

    /// Wie Frage 1 vor der ersten Planung ausging (v84, AT6: D1b, E349). Die Frage steht dort vor „Neue Planung“, weil
    /// der Import aus IServ im Blatt eine eingeschaltete Verschlüsselung braucht. Nur in der Sitzung (E536): Nach
    /// einem Neustart fragt die Einrichtung wieder ab Frage 1 — wie nach jedem Beenden mitten in ihr.
    enum Verschluesselungsfrage: Equatable, Sendable {
        /// Nicht gestellt.
        case offen
        /// „Überspringen“: „Neue Planung“ ohne Verschlüsselung, nach der Planung weiter bei Frage 2.
        case uebersprungen
        /// Passphrase gewählt, Blatt bestätigt — eingeschaltet wird mit „Planung anlegen“ (E531).
        case vorbereitet
        /// Die Vorbereitung ist fort, ohne eingeschaltet zu haben: „Abbrechen“ in „Neue Planung“ (E477 b), eine
        /// geöffnete Datei statt „Planung anlegen“, ein zurückgenommenes Einschalten (E478). Frage 1 steht
        /// wieder und sagt, dass ein notierter Wiederherstellungsschlüssel nicht gilt.
        case verworfen
        /// Frage 1 stand, und statt einer Antwort wurde eine versiegelte Planung samt ihren Schlüsseln übernommen
        /// (E716, Z-AW1bN-05): weiter bei Frage 2.
        case uebernommen
        /// Die Übernahme hat eine Vorbereitung aus Frage 1 ersetzt (E719): weiter bei Frage 2, die sagt, dass ein
        /// notierter Wiederherstellungsschlüssel nicht gilt (E720).
        case ersetzt
    }

    // ── Frage 1 vor der ersten Planung (v84, AT6: D1b, E349, E355, E477 b, E531) ──

    /// Ohne Planung steht vor „Neue Planung“ die Frage nach der Verschlüsselung — beim ersten Start und wieder,
    /// nachdem eine Vorbereitung verworfen wurde (E477 b). Nie im Prüfstand: Dort ist die Einrichtung nicht fällig.
    /// Nur, wo „Planung anlegen“ anlegen darf (`anlegbar`) — sonst bliebe die Vorbereitung liegen (Z-AT6-01).
    static func verschluesselungsfrageVorDerPlanung(hatPlanung: Bool, faellig: Bool, verschluesselt: Bool,
                                                    frage: Verschluesselungsfrage, anlegbar: Bool) -> Bool {
        !hatPlanung && anlegbar && faellig && !verschluesselt && (frage == .offen || frage == .verworfen)
    }

    var verschluesselungsfrageVorDerPlanung: Bool {
        Planungsspeicher.verschluesselungsfrageVorDerPlanung(
            hatPlanung: hatPlanung, faellig: ersteinrichtungFaellig, verschluesselt: verschluesselt,
            frage: verschluesselungsfrage, anlegbar: planungAnlegbar)
    }

    /// Ob „Planung anlegen“ eine Planung anlegen darf — dieselbe Schranke wie in `neuePlanung`: keine gesperrte
    /// Ablage, keine offene Entsperrung, keine Blockade des Wiederanlaufs.
    var planungAnlegbar: Bool { !ablageGesperrt && !entsperrungOffen && !blockadeOffen }

    /// „Neue Planung“ — beim Start ohne Planung, aus dem Menü (⌘N), der Werkzeugleiste, dem Willkommen und dem
    /// Vorhaben ohne Planung: wenn nötig erst Frage 1.
    func neuePlanungOeffnen() {
        // Frage 1 schließt noch, „Neue Planung“ ist schon vorgemerkt (Z-AT6N-02).
        guard naechsterDialog != .neuePlanung else { return }
        guard verschluesselungsfrageVorDerPlanung else {
            offenerDialog = .neuePlanung
            return
        }
        ersteinrichtungsschritt = .verschluesselung
        offenerDialog = .ersteinrichtung
    }

    /// Ob „Planung anlegen“ einschaltet (E531): nur mit der Vorbereitung aus Frage 1, nur vor der ersten Planung
    /// — eine Vorbereitung, die anderswo liegen blieb, bleibt unberührt.
    var einschaltenBeimAnlegen: Bool { !hatPlanung && verschluesselungsfrage == .vorbereitet }

    /// „Abbrechen“ in „Neue Planung“: Was Frage 1 vorbereitet hat, wird verworfen (E477 b) — das nächste
    /// „Neue Planung“ führt wieder über Frage 1, und die sagt es.
    func neuePlanungAbbrechen() {
        guard einschaltenBeimAnlegen else { return }
        verschluesselungVerwerfen()
        verschluesselungsfrage = .verworfen
        ersteinrichtungsschritt = .verschluesselung
    }

    /// Vor der Planung führt Frage 1 zu „Neue Planung“, sobald ihr Blatt abgelöst ist. Der Schritt bleibt stehen,
    /// bis das Blatt fort ist — sonst wechselte es im Schließen den Inhalt.
    private func zurNeuenPlanung() {
        // Ein zweites „Überspringen“ oder „Weiter zur Planung“, während das Blatt noch schließt: schon vorgemerkt.
        guard offenerDialog != .neuePlanung, naechsterDialog != .neuePlanung else { return }
        if offenerDialog == .ersteinrichtung {
            dialogVormerken(.neuePlanung)
            offenerDialog = nil
        } else {
            dialogOeffnen(.neuePlanung)
        }
    }

    /// Wo das Blatt nach der Planung beginnt: bei der Sicherungskopie, wenn die Verschlüsselung eingeschaltet ist
    /// oder Frage 1 vor der Planung übersprungen wurde — sonst bei Frage 1.
    static func ersteinrichtungBeginn(verschluesselt: Bool, frage: Verschluesselungsfrage) -> Ersteinrichtungsschritt {
        verschluesselt || frage == .uebersprungen ? .sicherung : .verschluesselung
    }

    /// Wie viele Fragen das Blatt zählt (E355): drei nur, wenn es bei der Sicherungskopie beginnt, ohne dass
    /// Frage 1 gestellt wurde — die erste Planung war schon versiegelt. Stand Frage 1 vor der Planung, ist die
    /// Sicherungskopie „Frage 2 von 4“.
    static func ersteinrichtungFragen(schritt: Ersteinrichtungsschritt, frage: Verschluesselungsfrage) -> Int {
        schritt == .sicherung && frage == .offen ? 3 : 4
    }

    /// Was nach einer Planung von selbst aufgeht, in der Reihenfolge, in der
    /// es kommt: die Ersteinrichtung mit ihren vier Fragen, dann die beiden
    /// Ersatzblätter für Planungen, die älter sind als die dritte und vierte
    /// Frage, zuletzt das Angebot der Tour. Jeder Schritt prüft selbst, ob er
    /// fällig ist und ob gerade nichts offen ist; der erste, der zusagt,
    /// nimmt das Fenster, die übrigen kommen beim nächsten Schließen.
    ///
    /// **Die Tour steht am Ende (E239, v77):** sie ist ein Angebot, keine
    /// Frage. Bis 1.9.5 stand sie vor den beiden Ersatzblättern — auf dem Weg
    /// über die Verschlüsselung (B67) kam sie damit vor der Frage nach den
    /// Updates und der nach der Materialliste.
    ///
    /// Hier statt in der `Hauptansicht`, damit Prüfungen dieselbe Folge gehen
    /// wie die Oberfläche und nicht eine nachgebaute — **an einer Stelle, nicht
    /// an dreien**: Eine Folge, die zweimal geschrieben steht, läuft auseinander.
    ///
    /// `mitTour: false` beim Erscheinen des Fensters: Dort kommt die Tour
    /// nicht, weil sie zur **neuen** Planung gehört (`neuePlanung` setzt
    /// `tourAnbieten`, `Planungsspeicher+Dateien.swift`) und eine geladene
    /// keine neue ist. Der Schalter sagt das ausdrücklich, statt sich darauf
    /// zu verlassen, dass der Merker beim Start ohnehin falsch ist (v77).
    ///
    /// Der Hinweis gegen den Rückweg (E286, E297) steht nach den Fragen und
    /// vor der Tour: Er ist keine Frage, aber gelesen soll er sein, bevor die
    /// Tour das Fenster nimmt.
    func angeboteUndFragenPruefen(mitTour: Bool = true) {
        ersteinrichtungPruefen()
        updateNachfragePruefen()
        materialNachfragePruefen()
        rueckwegHinweisPruefen()
        if mitTour { tourAnbietenPruefen() }
    }

    // ── Kein Rückweg auf eine Vorversion (v80, E286, E297) ────────────────

    /// Einmal, mit Planung, nach der Einrichtung — nie im Prüflauf; auch ohne
    /// Verschlüsselung. Nach einem Update kommt er beim ersten Öffnen, nach
    /// einer Neuinstallation hinter den Fragen der Einrichtung.
    static func rueckwegHinweisFaellig(pruefstand: Bool, hatPlanung: Bool,
                                       ersteinrichtungFaellig: Bool, gezeigt: Bool) -> Bool {
        !pruefstand && hatPlanung && !ersteinrichtungFaellig && !gezeigt
    }

    /// Wie die Nachfragen: nie über ein offenes Blatt oder die Tour hinweg.
    func rueckwegHinweisPruefen() {
        guard Planungsspeicher.rueckwegHinweisFaellig(
                pruefstand: Ablage.istPruefstand, hatPlanung: hatPlanung,
                ersteinrichtungFaellig: ersteinrichtungFaellig, gezeigt: rueckwegHinweisGezeigt),
              !dialogOffen, !tourLaeuft else { return }
        offenerDialog = .rueckwegHinweis
    }

    /// Gelesen ist gelesen — auf jedem Weg, mit dem das Blatt schließt.
    func rueckwegHinweisGelesen() {
        rueckwegHinweisGezeigt = true
        Einstellungen.setzen(true, Einstellungen.Schluessel.rueckwegHinweis)
    }

    /// Die Frage kommt erst, wenn eine Planung da ist und kein anderes Blatt
    /// offen liegt — sonst nähme sie ihm das Fenster weg.
    func ersteinrichtungPruefen() {
        guard hatPlanung, !dialogOffen else { return }
        // Abgelöst, aber nicht zu Ende: dort weiter, wo sie stand — nicht über
        // `ersteinrichtungOeffnen()`, das den Schritt zurücksetzte, und ohne
        // `ersteinrichtungFaellig`, das nach der zweiten Antwort falsch ist
        // (B67, E239, v77). Der Merker fällt vor dem Öffnen, damit ein Blatt,
        // das der Nutzer ungefragt schließt, nicht wiederkehrt; die beiden
        // Ersatzblätter fangen die Fragen dann wie bei älteren Planungen.
        if ersteinrichtungFortsetzen {
            ersteinrichtungFortsetzen = false
            offenerDialog = .ersteinrichtung
            return
        }
        guard ersteinrichtungFaellig else { return }
        ersteinrichtungOeffnen()
    }

    /// Das Blatt öffnen, ohne die Schranke — für Prüfungen und Prüfstände.
    /// Ist die Verschlüsselung schon eingeschaltet (beim Anlegen oder eine
    /// versiegelte Datei als erste Planung) oder wurde Frage 1 vor der Planung
    /// übersprungen, beginnt es bei der zweiten Frage.
    func ersteinrichtungOeffnen() {
        // Eine Vorbereitung aus Frage 1, die „Planung anlegen“ nicht eingeschaltet hat — statt dessen wurde eine
        // Datei geöffnet, oder das Einschalten wurde zurückgenommen (E478): verworfen wie mit „Abbrechen“ (E477 b).
        if verschluesselungsfrage == .vorbereitet, vorbereitung != nil || !verschluesselt {
            verschluesselungVerwerfen()
            verschluesselungsfrage = .verworfen
        }
        ersteinrichtungsschritt = Planungsspeicher.ersteinrichtungBeginn(verschluesselt: verschluesselt,
                                                                       frage: verschluesselungsfrage)
        offenerDialog = .ersteinrichtung
    }

    /// „Verschlüsselung einrichten …“: Schritt 1, die Passphrase.
    func ersteinrichtungEinrichten() {
        ersteinrichtungsschritt = .passphrase
    }

    /// „Weiter“ nach der Passphrase: Datenschlüssel und Wicklungen liegen
    /// bereit, das Blatt mit dem Wiederherstellungsschlüssel folgt. Scharf ist
    /// noch nichts; eine zu kurze Passphrase wirft und lässt den Schritt stehen.
    func ersteinrichtungWeiter(passphrase: String) throws {
        ersteinrichtungsschritt = .blatt(try verschluesselungVorbereiten(passphrase: passphrase))
    }

    /// Dasselbe abseits des Hauptstrangs — für das Blatt; ein verworfenes
    /// Ergebnis lässt den Schritt stehen.
    func ersteinrichtungWeiterAsynchron(passphrase: String) async throws {
        guard let blatt = try await verschluesselungVorbereitenAsynchron(passphrase: passphrase),
              ersteinrichtungsschritt == .passphrase else { return }
        ersteinrichtungsschritt = .blatt(blatt)
    }

    /// „Verschlüsselung einschalten“ nach dem bestätigten Blatt — und weiter
    /// zur zweiten Frage, deren Kopie dann von Anfang an versiegelt ist. Wurde
    /// der Übergang zurückgenommen (die Ablage ließ sich nicht schreiben),
    /// steht wieder die Frage: Geschehen ist nichts, das Blatt sagt, warum.
    @discardableResult
    func ersteinrichtungEinschalten() -> Schutzergebnis {
        guard case .blatt = ersteinrichtungsschritt else {
            return Schutzergebnis(ablage: .zurueckgenommen("es gibt kein bestätigtes Blatt"))
        }
        let ergebnis = verschluesselungEinschalten()
        if case .zurueckgenommen = ergebnis.ablage {
            ersteinrichtungsschritt = .verschluesselung
        } else {
            ersteinrichtungsschritt = .sicherung
        }
        return ergebnis
    }

    /// „Abbrechen“ in der Einrichtung: zurück zur Frage; geschehen ist nichts.
    func ersteinrichtungAbbrechen() {
        // Nach „Weiter zur Planung“ schließt das Blatt schon: nichts mehr verwerfen (Z-AT6N-02).
        guard naechsterDialog != .neuePlanung else { return }
        verschluesselungVerwerfen()
        ersteinrichtungsschritt = .verschluesselung
    }

    /// „Weiter zur Planung“ nach dem bestätigten Blatt, vor der ersten Planung:
    /// Datenschlüssel und Wicklungen liegen bereit, eingeschaltet wird mit
    /// „Planung anlegen“ (D1b, E531) — eine Planung, die zu versiegeln wäre,
    /// gibt es noch nicht.
    func ersteinrichtungZurPlanung() {
        guard !hatPlanung, case .blatt = ersteinrichtungsschritt, vorbereitung != nil else { return }
        verschluesselungsfrage = .vorbereitet
        zurNeuenPlanung()
    }

    /// „Überspringen“: Die Verschlüsselung bleibt aus — nachzuholen unter
    /// „Einstellungen“, spätestens mit der Kopie, die es nur versiegelt gibt.
    /// Vor der ersten Planung geht es zu „Neue Planung“, danach zur zweiten Frage.
    func ersteinrichtungUeberspringen() {
        guard !hatPlanung else {
            ersteinrichtungsschritt = .sicherung
            return
        }
        verschluesselungsfrage = .uebersprungen
        zurNeuenPlanung()
    }

    /// Beantwortet ist beantwortet — auch „Später“; nachzuholen ist es unter
    /// „Einstellungen“.
    func ersteinrichtungBeantwortet() {
        Einstellungen.setzen(true, Einstellungen.Schluessel.autoexportGefragt)
    }

    /// Nach der Sicherungsfrage — „Später“ wie „Ordner wählen …“ — die dritte.
    func ersteinrichtungZuUpdates() {
        ersteinrichtungsschritt = .updates
    }

    /// Die Antwort auf die dritte Frage — und weiter zur vierten.
    func ersteinrichtungUpdates(erlauben: Bool) {
        updatesErlauben(erlauben)
        ersteinrichtungsschritt = .materialien
    }

    /// Die Antwort auf die vierte Frage; damit ist die Ersteinrichtung durch.
    func ersteinrichtungMaterialien(erlauben: Bool) {
        materialienErlauben(erlauben)
    }
}
