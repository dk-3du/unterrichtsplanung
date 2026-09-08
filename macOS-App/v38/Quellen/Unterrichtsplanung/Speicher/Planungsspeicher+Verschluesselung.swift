// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import LocalAuthentication

// ── Verschlüsselung und die Wicklung dieses Macs ─────────────────────────────
// Ein Datenschlüssel, offene Wicklungsliste, kein Klartext an keiner Stelle.
extension Planungsspeicher {

    // ── Verschlüsselung ───────────────────────────────────────────────────

    /// Der Hinweis zur Datenverwaltung — wortgleich im Ersteinrichtungsdialog
    /// und im Beipackzettel des DMG (bauen.sh).
    static let datenschutzhinweis =
        "Hinweis zur Datenverwaltung: Die Sicherungskopie beim Beenden wird nur "
        + "verschlüsselt geschrieben (AES-256) — mit der Wahl eines Zielordners wird die "
        + "Verschlüsselung eingerichtet, mit Passphrase und Wiederherstellungsschlüssel. Die "
        + "laufende Sicherung auf diesem Rechner ist unverschlüsselt, solange die "
        + "Verschlüsselung unter „Einstellungen“ nicht eingeschaltet ist; FileVault schützt "
        + "sie unabhängig davon. Ältere Kopien, Schnappschüsse und Sicherungen des Systems "
        + "bleiben von einem späteren Einschalten unberührt."

    enum Verschluesselungsstand: Sendable { case aus, gesperrt, an }

    /// Aus, gesperrt oder an — abgeleitet aus der Sitzung, nicht daneben geführt.
    var verschluesselungsstand: Verschluesselungsstand { sitzung.stand }

    var verschluesselt: Bool { verschluesselungsstand != .aus }

    /// Der Datenschlüssel der Sitzung. Jede Sitzung führt ihren eigenen — auch
    /// eine Vorschau in den Prüfungen; einen prozessweiten gibt es nicht mehr.
    var tresor: Tresor? { sitzung.tresor }

    /// Die ausstehende Freigabe: die der gesperrten Ablage oder die einer Datei
    /// von außen. Der Kopf des Behälters steht darin.
    var entsperrung: Entsperrung? { sitzung.entsperrung ?? dateiEntsperrung }

    var gesperrterKopf: Behaelterkopf? { entsperrung?.kopf }

    var entsperrungOffen: Bool { entsperrung != nil }

    /// Übergang: Schlüssel setzen oder ablegen — die Planung bleibt, der Stand
    /// folgt (`.verschluesselt`, sonst `.klartext` oder `.leer`). Aus
    /// `.gesperrt` führt das nur mit Schlüssel heraus; die Planung kommt danach
    /// von der Platte.
    private func tresorAnlegen(_ neu: Tresor?) {
        sitzung = sitzung.mit(tresor: neu)
        enklaveEingerichtet = neu?.hat(Wicklung.enklave) ?? false
    }

    /// Ablage beim Start, Vorgängerfassung nach unlesbarem Stand, oder eine
    /// von außen geöffnete Datei unter fremdem Schlüssel.
    enum Entsperrungsziel: Sendable {
        case ablage(Data)
        case vorige(Data, String)
        case datei(Data, URL)
        var daten: Data {
            switch self {
            case .ablage(let d), .vorige(let d, _), .datei(let d, _): d
            }
        }
        var istAblage: Bool { if case .datei = self { false } else { true } }
    }

    /// Welches Feld das Blatt zeigt — wie in der Ansicht immer nur eines, damit
    /// die Eingabe eindeutig ist. Im Speicher statt im Blatt, damit der Prüfstand
    /// `--entsperrtest` umschalten kann.
    enum Entsperrungsweg: Hashable, Sendable { case passphrase, wiederherstellung }

    /// Ob es um die Ablage geht (Touch ID, Leerzustand) oder um eine Datei.
    var entsperrungFuerAblage: Bool { entsperrung?.ziel.istAblage ?? true }

    /// Die Wicklungen der Ablage — auch im gesperrten Zustand, aus dem Kopf.
    var wicklungen: [Wicklung] {
        tresor?.wicklungen ?? gesperrterKopf?.wicklungen ?? []
    }

    /// Touch ID ist möglich, wenn der Kopf eine Wicklung für diesen Mac trägt.
    var enklaveMoeglich: Bool {
        Tresor.enklaveVerfuegbar && gesperrterKopf?.wicklung(Wicklung.enklave) != nil
            && entsperrungFuerAblage
    }

    /// Öffnet die Einrichtung; `danach` läuft, sobald eingeschaltet ist —
    /// etwa das Einschalten der Kopie beim Beenden.
    func verschluesselungEinrichten(danach: (@MainActor () -> Void)? = nil) {
        nachEinrichtung = danach
        dialogOeffnen(.verschluesselung)
    }

    /// Schritt 1: Datenschlüssel und Wicklungen; liefert den Wiederherstellungs-
    /// schlüssel, der einmal gezeigt und nie gespeichert wird. Eingeschaltet ist
    /// damit noch nichts.
    func verschluesselungVorbereiten(passphrase: String) throws -> String {
        let tresor = Tresor.neu()
        try tresor.passphraseSetzen(passphrase)
        let blatt = try tresor.wiederherstellungAnlegen()
        if Tresor.enklaveVerfuegbar { try tresor.enklaveAnlegen() }
        vorbereitung = tresor
        return blatt
    }

    /// Schritt 2, nach dem bestätigten Blatt: Ablage und Nebendateien sofort,
    /// die Kopie beim nächsten Beenden.
    func verschluesselungEinschalten() {
        guard let tresor = vorbereitung else { return }
        vorbereitung = nil
        let alter = self.tresor
        tresorAnlegen(tresor)
        neuVersiegeln()
        let bilanz = sicherung.istVorschau
            ? Ablage.Nebendateienbilanz()
            : sicherung.ablage.altbestaendeVersiegeln(mit: tresor, alter: alter)
        let alt = bilanz.umgestellt.count
        var text = (alter == nil ? "Verschlüsselung eingeschaltet." : "Schlüssel erneuert.")
            + " Die Ablage auf diesem Mac ist versiegelt"
            + (alt > 0 ? ", \(alt) ältere \(alt == 1 ? "Stand" : "Stände") daneben ebenfalls" : "")
            // In der Ersteinrichtung gibt es die Kopie noch nicht — dann kein Versprechen.
            + (autoexportAktiv ? ". Die Kopie beim Beenden folgt beim nächsten Beenden." : ".")
        // Was liegen blieb, wird benannt — die Meldung verspricht nicht mehr, als da ist.
        if !bilanz.vollstaendig {
            text += " Nicht versiegelt: \(bilanz.beschreibung). Die App versucht es beim nächsten Start erneut."
        }
        melden(text, bilanz.vollstaendig ? .hinweis : .warnung)
        let fortsetzung = nachEinrichtung
        nachEinrichtung = nil
        fortsetzung?()
    }

    func verschluesselungVerwerfen() {
        vorbereitung = nil
        nachEinrichtung = nil
    }

    /// Was beim Einschalten liegen blieb, wird beim nächsten Start nachgeholt:
    /// Klartext-Nebendateien neben einer versiegelten Ablage werden versiegelt;
    /// was sich nicht versiegeln lässt oder unter einem fremden Schlüssel liegt,
    /// wird bei jedem Start benannt, bis es nicht mehr da ist.
    private func nebendateienNachholen() {
        guard !sicherung.istVorschau, let tresor else { return }
        let bilanz = sicherung.ablage.altbestaendeVersiegeln(mit: tresor, nurKlartext: true)
        guard !bilanz.umgestellt.isEmpty || !bilanz.vollstaendig else { return }
        var text = ""
        if !bilanz.umgestellt.isEmpty {
            let n = bilanz.umgestellt.count
            text = "\(n) ältere \(n == 1 ? "Stand" : "Stände") neben der Ablage nachträglich versiegelt."
        }
        if !bilanz.vollstaendig {
            text += (text.isEmpty ? "" : " ") + "Übrig neben der Ablage: \(bilanz.beschreibung) — "
                + "bitte im Ordner der Ablage nachsehen."
        }
        melden(text, bilanz.vollstaendig ? .hinweis : .warnung)
    }

    /// Alles neu versiegeln, was die App erreicht: die Ablage jetzt — auch ohne
    /// Änderung an der Planung —, die Kopie beim nächsten Beenden.
    func neuVersiegeln() {
        sicherung.neuSchreibenErzwingen()
        jetztSichern()
    }

    /// Der Rückweg — eine Einbahnstraße wäre bei einer Jahresplanung nicht zu
    /// verantworten. Die Kopie außer Haus gibt es danach nicht mehr.
    func verschluesselungAufheben() {
        guard let tresor else { return }
        tresorAnlegen(nil)
        // Erst die Ablage im Klartext hinlegen — dabei wandert der versiegelte
        // Stand nach planung-vorher.json —, dann die Nebendateien entsiegeln.
        neuVersiegeln()
        let bilanz = sicherung.istVorschau ? Ablage.Nebendateienbilanz() : sicherung.ablage.altbestaendeEntsiegeln(tresor)
        let alt = bilanz.umgestellt.count
        var text = "Verschlüsselung aufgehoben — die Ablage liegt wieder im Klartext"
            + (alt > 0 ? ", \(alt) ältere \(alt == 1 ? "Stand" : "Stände") daneben ebenfalls" : "")
            + "."
        if !bilanz.vollstaendig {
            text += " Noch versiegelt: \(bilanz.beschreibung)."
        }
        if autoexportAktiv {
            autoexportAktiv = false
            text += " Die Sicherungskopie beim Beenden ist ausgeschaltet: Es gibt sie nur verschlüsselt."
        }
        melden(text, .warnung)
    }

    /// 32 Byte neu wickeln; eine ältere Kopie in der Cloud kennt noch die alte Passphrase.
    func passphraseAendern(alt: String, neu: String) throws {
        guard let tresor else { return }
        guard tresor.passphraseStimmt(alt) else {
            throw Tresorfehler(art: .falscherSchluessel, text: "Die bisherige Passphrase passt nicht.")
        }
        try tresor.passphraseSetzen(neu)
        neuVersiegeln()
        let bilanz = sicherung.istVorschau ? Ablage.Nebendateienbilanz() : sicherung.ablage.altbestaendeVersiegeln(mit: tresor)
        melden("Passphrase geändert. Sie gilt für die Ablage sofort und für die Kopie beim "
               + "nächsten Beenden."
               + (bilanz.vollstaendig ? "" : " Nicht neu gewickelt: \(bilanz.beschreibung)."),
               bilanz.vollstaendig ? .hinweis : .warnung)
    }

    /// Frischer Datenschlüssel samt neuem Blatt, wenn die alte Passphrase als
    /// verbrannt gilt; scharf erst nach dem bestätigten Blatt.
    func schluesselErneuernVorbereiten(passphrase: String) throws -> String {
        guard let alter = tresor else {
            throw Tresorfehler(art: .keineWicklung, text: "Die Verschlüsselung ist nicht eingeschaltet.")
        }
        guard alter.passphraseStimmt(passphrase) else {
            throw Tresorfehler(art: .falscherSchluessel, text: "Die Passphrase passt nicht.")
        }
        return try verschluesselungVorbereiten(passphrase: passphrase)
    }

    // Entsperren — beim Start, nach einem unlesbaren Stand, für eine fremde Datei

    func entsperrungBeginnen(_ ziel: Entsperrungsziel) {
        let kopf: Behaelterkopf
        do {
            kopf = try Tresor.kopfLesen(ziel.daten)
        } catch let fehler as Tresorfehler where fehler.art == .neuereFassung {
            // Eine neuere Fassung hat geschrieben: nichts anfassen, nichts
            // beiseitelegen — nur sagen, was zu tun ist.
            if ziel.istAblage {
                sicherung.gesperrt = true
                sitzung = .gesperrt(ziel, nil)
            }
            melden(fehler.text, .warnung)
            return
        } catch {
            switch ziel {
            case .ablage:
                // Ein Behälter, dessen Kopf nicht zu lesen ist, ist ein unlesbarer
                // Stand: beiseitelegen und die Fassung davor retten.
                unlesbarenStandBehandeln(Tresorfehler(
                    art: .beschaedigt, text: "der verschlüsselte Behälter ist beschädigt"))
            case .vorige(_, let grund):
                sicherung.lageMelden(geklappt: false)
                melden("Die Autosicherung ließ sich nicht lesen (\(grund)), und auch die "
                       + "Fassung davor ist beschädigt. Es wird nichts überschrieben, bis eine "
                       + "Planung angelegt oder geöffnet wird.", .warnung)
                offenerDialog = .neuePlanung
            case .datei:
                melden("Die Datei ist ein beschädigter verschlüsselter Behälter.", .warnung)
            }
            return
        }
        // Übergang: Die Ablage wird zur gesperrten Sitzung; eine Datei von
        // außen wartet daneben, die Sitzung bleibt, wie sie ist.
        if ziel.istAblage {
            sicherung.gesperrt = true
            sitzung = .gesperrt(ziel, kopf)
        } else {
            dateiEntsperrung = Entsperrung(ziel: ziel, kopf: kopf)
        }
        entsperrungFehler = nil
        entsperrungsweg = .passphrase
        enklaveWicklungPasstNicht = false
        // Vorgabe wie bei Numbers: Häkchen gesetzt, wo eine Enklave da ist.
        enklaveMerken = ziel.istAblage && Tresor.enklaveVerfuegbar
        freigabeAnfordern()
    }

    /// Wie bei Numbers: Trägt der Kopf eine Wicklung für diesen Mac, steht
    /// zuerst allein die Systemabfrage — das Blatt kommt erst, wenn sie ohne
    /// Ergebnis endet. Sonst gleich das Blatt.
    private func freigabeAnfordern() {
        if enklaveMoeglich { entsperrenMitEnklave() } else { dialogOeffnen(.entsperren) }
    }

    /// Hält den `LAContext` über die abgesetzte Aufgabe hinweg, damit
    /// `invalidate()` die stehende Abfrage abbrechen kann. `LAContext` ist
    /// nicht `Sendable`; benutzt wird er nur in der einen Aufgabe.
    final class Freigabegriff: @unchecked Sendable {
        let kontext = LAContext()
    }

    /// Touch ID abseits des Hauptstrangs — der Aufruf blockiert bis zur Antwort.
    /// Endet die Abfrage ohne Freigabe, kommt sofort das Blatt; passt die
    /// Wicklung nicht mehr, sagt es das
    /// dazu. Ein Abbruch ist kein Fehler und bekommt keine Warnung.
    func entsperrenMitEnklave() {
        guard let kopf = gesperrterKopf, enklaveMoeglich, !entsperrungLaeuft else { return }
        entsperrungLaeuft = true
        entsperrungFehler = nil
        freigabeStillAbgebrochen = false
        let griff = Freigabegriff()
        griff.kontext.localizedReason = "die Planung zu entsperren"
        freigabegriff = griff
        Task { [weak self] in
            let ergebnis: Result<Tresor, Tresorfehler> = await Task.detached(priority: .userInitiated) {
                do { return .success(try Tresor.oeffnen(kopf: kopf, enklave: griff.kontext)) }
                catch let fehler as Tresorfehler { return .failure(fehler) }
                catch { return .failure(Tresorfehler(art: .abgebrochen, text: error.localizedDescription)) }
            }.value
            guard let self else { return }
            entsperrungLaeuft = false
            if freigabegriff === griff { freigabegriff = nil }
            switch ergebnis {
            case .success(let tresor):
                entsperrt(mit: tresor, durchEnklave: true)
            case .failure(let fehler):
                guard entsperrung != nil, !freigabeStillAbgebrochen else {
                    freigabeStillAbgebrochen = false
                    return
                }
                enklaveWicklungPasstNicht = fehler.art != .abgebrochen
                entsperrungFehler = fehler.art == .abgebrochen ? nil : fehler.text
                if offenerDialog != .entsperren { dialogOeffnen(.entsperren) }
            }
        }
    }

    /// Die stehende Systemabfrage abbrechen — sie endet dann wie „Abbrechen“
    /// darin, und das Blatt kommt. Für den Prüfstand.
    func freigabeAbbrechen() {
        freigabegriff?.kontext.invalidate()
    }

    func entsperren(passphrase: String) {
        guard let kopf = gesperrterKopf else { return }
        do { entsperrt(mit: try Tresor.oeffnen(kopf: kopf, passphrase: passphrase), durchEnklave: false) }
        catch { entsperrungFehler = (error as? Tresorfehler)?.text ?? error.localizedDescription }
    }

    func entsperren(wiederherstellung: String) {
        guard let kopf = gesperrterKopf else { return }
        do { entsperrt(mit: try Tresor.oeffnen(kopf: kopf, wiederherstellung: wiederherstellung), durchEnklave: false) }
        catch { entsperrungFehler = (error as? Tresorfehler)?.text ?? error.localizedDescription }
    }

    func entsperrungswegWechseln() {
        entsperrungsweg = entsperrungsweg == .passphrase ? .wiederherstellung : .passphrase
        entsperrungFehler = nil
    }

    /// Sobald neu getippt wird, ist der alte Fehlertext hinfällig.
    func entsperrungFehlerVerwerfen() {
        entsperrungFehler = nil
    }

    /// Ohne Freigabe geschlossen: Die Ablage bleibt zu (der Leerzustand bietet
    /// das Entsperren weiter an), eine fremde Datei bleibt ungeöffnet.
    func entsperrungAbbrechen() {
        guard let ziel = entsperrung?.ziel else { return }
        if entsperrungLaeuft {
            freigabeStillAbgebrochen = true
            freigabeAbbrechen()
        }
        if offenerDialog == .entsperren { offenerDialog = nil }
        guard ziel.istAblage else {
            dateiEntsperrung = nil
            return
        }
    }

    /// Aus dem Leerzustand: Touch ID zuerst, sonst das Blatt.
    func entsperrungFortsetzen() {
        guard entsperrung != nil, !entsperrungLaeuft else { return }
        entsperrungFehler = nil
        freigabeAnfordern()
    }

    /// Aus dem Leerzustand gleich zur Passphrase — an der Enklave vorbei.
    func entsperrungMitBlatt() {
        guard entsperrung != nil, !entsperrungLaeuft else { return }
        entsperrungFehler = nil
        dialogOeffnen(.entsperren)
    }

    // ── Die Wicklung dieses Macs ──────────────────────────────────────────

    /// Das Häkchen nach einer Freigabe ohne die Enklave: Wicklung dieses Macs
    /// anlegen — auch anstelle einer, die nicht mehr passt — oder entfernen,
    /// und die Ablage neu versiegeln, damit der nächste Start sie so vorfindet.
    /// Eine Wicklung, die trägt, bleibt unangetastet: Wer Touch ID nur diesmal
    /// abgebrochen hat, bekommt keinen neuen Schlüssel. Die Kopie außer Haus
    /// trägt diese Wicklung ohnehin nie.
    private func enklaveAngleichen(_ tresor: Tresor) {
        defer { enklaveWicklungPasstNicht = false }
        if enklaveMerken {
            guard !tresor.hat(Wicklung.enklave) || enklaveWicklungPasstNicht else { return }
            guard enklaveWicklungAnlegen(tresor) else { return }
            melden(enklaveWicklungPasstNicht
                   ? "Dieser Mac ist neu eingerichtet — Touch ID oder das Anmeldepasswort "
                     + "öffnen die Planung wieder."
                   : "Touch ID oder das Anmeldepasswort öffnen die Planung ab jetzt auf diesem Mac.")
        } else if tresor.hat(Wicklung.enklave) {
            enklaveWicklungEntfernen(tresor)
            melden("Die Wicklung dieses Macs ist entfernt — beim Start ist die Passphrase fällig.")
        }
    }

    /// Der Schalter unter „Einstellungen“ bei offener Planung.
    func enklaveAufDiesemMac(_ an: Bool) {
        guard let tresor, verschluesselungsstand == .an else { return }
        if an {
            guard !tresor.hat(Wicklung.enklave), enklaveWicklungAnlegen(tresor) else { return }
            melden("Touch ID oder das Anmeldepasswort öffnen die Planung ab jetzt auf diesem Mac.")
        } else {
            guard tresor.hat(Wicklung.enklave) else { return }
            enklaveWicklungEntfernen(tresor)
            melden("Die Wicklung dieses Macs ist entfernt — beim Start ist die Passphrase fällig.")
        }
    }

    private func enklaveWicklungAnlegen(_ tresor: Tresor) -> Bool {
        guard Tresor.enklaveVerfuegbar || enklaveImPruefstandAnlegen else { return false }
        do { try tresor.enklaveAnlegen(auchImPruefstand: enklaveImPruefstandAnlegen) }
        catch {
            melden("Die Wicklung für diesen Mac ließ sich nicht anlegen: "
                   + ((error as? Tresorfehler)?.text ?? error.localizedDescription), .warnung)
            return false
        }
        enklaveEingerichtet = true
        neuVersiegeln()
        return true
    }

    private func enklaveWicklungEntfernen(_ tresor: Tresor) {
        tresor.entfernen(art: Wicklung.enklave)
        enklaveEingerichtet = false
        neuVersiegeln()
    }

    /// Übergang nach der Freigabe: Aus `.gesperrt` wird `.verschluesselt` mit
    /// dem Schlüssel, die Planung folgt von der Platte; für eine Datei von
    /// außen bleibt die Sitzung, die Datei wird unter ihrem Schlüssel gelesen.
    private func entsperrt(mit tresor: Tresor, durchEnklave: Bool) {
        guard let ziel = entsperrung?.ziel else { return }
        entsperrungFehler = nil
        if offenerDialog == .entsperren { offenerDialog = nil }
        switch ziel {
        case .ablage(let daten):
            tresorAnlegen(tresor)
            sicherung.gesperrt = false
            do {
                geladenAusKlartext(try tresor.oeffnen(daten))
                if !durchEnklave { enklaveAngleichen(tresor) }
                nebendateienNachholen()
            } catch { unlesbarenStandBehandeln(error) }
        case .vorige(let vorige, let grund):
            tresorAnlegen(tresor)
            if let klartext = try? tresor.oeffnen(vorige),
               let (gerettet, bilanz) = try? Planungsdatei.lesenMitBilanz(klartext) {
                vorigeRettung(gerettet, bilanz: bilanz, grund: grund)
                if !durchEnklave { enklaveAngleichen(tresor) }
            } else {
                sicherung.lageMelden(geklappt: false)
                melden("Die Autosicherung ließ sich nicht lesen (\(grund)), und auch die "
                       + "Fassung davor ließ sich nicht entsiegeln. Es wird nichts überschrieben, "
                       + "bis eine Planung angelegt oder geöffnet wird.", .warnung)
                offenerDialog = .neuePlanung
            }
        case .datei(let daten, let url):
            dateiEntsperrung = nil
            do { importierenKlartext(try tresor.oeffnen(daten), von: url) }
            catch { melden(error.localizedDescription, .warnung) }
        }
    }
}
