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

    /// Was ein Übergang des Schutzes auf die Platte gebracht hat — die
    /// Meldung kommt daraus, nicht aus der Absicht.
    struct Schutzergebnis: Equatable {
        enum Ablagebefund: Equatable {
            /// Geschrieben und zurückgelesen: Die Platte trägt den neuen Stand.
            case geschrieben
            /// Nicht geschrieben, die Platte trägt den alten Stand — die
            /// Sitzung ist auf ihn zurück.
            case zurueckgenommen(String)
            /// Geschrieben oder nicht — die Platte ließ sich nicht zurücklesen;
            /// die Sitzung behält den neuen Stand, die nächste Sicherung schreibt ihn.
            case ungeprueft(String)
            /// Eine Vorschau schreibt nicht.
            case vorschau
        }
        enum Aussenstelle: Equatable {
            case erledigt
            case nichtNoetig
            case offen(String)
        }
        var ablage: Ablagebefund
        var nebendateien = Ablage.Nebendateienbilanz()
        /// Die Lesezeichen samt Zielordner: in den Behälter, unter den neuen
        /// Schlüssel, oder zurück in die Einstellungen.
        var lesezeichen: Aussenstelle = .nichtNoetig
        var kopie: Aussenstelle = .nichtNoetig
        var statusdatei: Aussenstelle = .nichtNoetig

        /// Was benannt werden muss — leer heißt: alles erreicht.
        var offenes: [String] {
            var teile: [String] = []
            if !nebendateien.vollstaendig { teile.append("neben der Ablage: " + nebendateien.beschreibung) }
            if case .offen(let grund) = lesezeichen { teile.append("Lesezeichen (\(grund))") }
            if case .offen(let grund) = kopie { teile.append("Kopie außer Haus (\(grund))") }
            if case .offen(let grund) = statusdatei { teile.append("Statusdatei der Ansicht (\(grund))") }
            return teile
        }
    }

    /// Die Ablage sofort unter dem Schutz der Sitzung schreiben und
    /// zurücklesen. Liegt danach noch der alte Stand, geht die Sitzung auf den
    /// alten Schlüssel zurück; ist die Platte nicht lesbar, bleibt der neue —
    /// die nächste Sicherung schreibt ihn.
    private func ablageSchreibenGeprueft(alter: Tresor?, neu: Tresor?) -> Schutzergebnis.Ablagebefund {
        var grund = ""
        do {
            try sicherung.sofortSchreiben()
        } catch {
            switch error {
            case .vorschau: return .vorschau
            case .nichtsZuSchreiben: grund = "keine Planung geladen"
            case .gesperrt: grund = "die Ablage ist gesperrt, ein unlesbarer Stand liegt noch im Weg"
            case .schreiben(let text): grund = text
            }
        }
        let erwartet: Sicherungsdienst.Ablagelage = neu.map { .versiegelt(kennung: $0.kennung) } ?? .klartext
        let alt: Sicherungsdienst.Ablagelage = alter.map { .versiegelt(kennung: $0.kennung) } ?? .klartext
        // Nur die Hülle hat gewechselt (Passphrase geändert): Die Kennung bleibt,
        // das Rücklesen kann alt und neu nicht unterscheiden — dann zählt die
        // Rückkehr des Schreibens, und zurückgenommen wird nichts.
        if erwartet == alt { return grund.isEmpty ? .geschrieben : .ungeprueft(grund) }
        switch sicherung.ablagelage() {
        case erwartet:
            return .geschrieben
        case alt, .keine:
            tresorAnlegen(alter)
            sicherung.neuSchreibenErzwingen()
            return .zurueckgenommen(grund.isEmpty ? "die Platte trägt weiter den alten Stand" : grund)
        case .unlesbar(let text):
            return .ungeprueft(grund.isEmpty ? text : grund)
        default:
            return .ungeprueft(grund.isEmpty ? "auf der Platte liegt ein anderer Stand" : grund)
        }
    }

    /// Die Lesezeichen und der Zielordner unter den Schlüssel der Sitzung:
    /// beim Einschalten aus den Einstellungen in den Behälter, beim Erneuern
    /// unter den neuen Schlüssel. Misslingt es, bleibt alles, wie es war —
    /// und der Grund sagt, was das heißt.
    private func lesezeichenVersiegeln(unter neu: Tresor, alter: Tresor?) -> Schutzergebnis.Aussenstelle {
        guard !sicherung.istVorschau else { return .nichtNoetig }
        guard let grund = zugriff.versiegeln(unter: neu) else { return .erledigt }
        return .offen(grund + (alter == nil
                               ? " — sie bleiben unverschlüsselt in den Einstellungen"
                               : " — der nächste Start fragt nach den Ordnern"))
    }

    /// Kopie außer Haus und Statusdatei der Ansicht sofort nachziehen —
    /// nicht erst beim Beenden. Die Statusdatei wandert unter den neuen
    /// Schlüssel; ohne Schlüssel (Aufheben) bleibt sie, wie sie ist.
    private func aussenstellenNachziehen(alter: Tresor?, neu: Tresor?) -> (kopie: Schutzergebnis.Aussenstelle,
                                                                          statusdatei: Schutzergebnis.Aussenstelle) {
        guard !sicherung.istVorschau, !autoexportOrdner.isEmpty else { return (.nichtNoetig, .nichtNoetig) }
        var kopie: Schutzergebnis.Aussenstelle = .nichtNoetig
        if autoexportAktiv, neu != nil {
            do {
                _ = try sicherung.kopieSchreiben(sitzung, name: autoexportDateiname)
                kopie = .erledigt
            } catch {
                switch error {
                case .nichtsZuSchreiben, .keinTresor: kopie = .offen("nichts zu schreiben")
                case .zielordner(.keinZugriff): kopie = .offen("Zielordner noch nicht freigegeben")
                case .zielordner(.fehlt): kopie = .offen("Zielordner nicht erreichbar")
                case .schreiben(_, let fehler): kopie = .offen(fehler.localizedDescription)
                }
            }
        }
        var statusdatei: Schutzergebnis.Aussenstelle = .nichtNoetig
        if let neu {
            do {
                statusdatei = try sicherung.statusdateiNeuVersiegeln(alter: alter, neu: neu) ? .erledigt : .nichtNoetig
            } catch {
                statusdatei = .offen(error.text)
            }
        }
        return (kopie, statusdatei)
    }

    /// Die Meldung zu einem Übergang — drei Sätze, je nachdem, was die Platte trägt.
    private func schutzMelden(_ ergebnis: Schutzergebnis, getan: String, nichtGetan: String) {
        switch ergebnis.ablage {
        case .zurueckgenommen(let grund):
            melden("\(nichtGetan): Die Ablage ließ sich nicht schreiben (\(grund)). Die Planung bleibt, wie sie war.",
                   .warnung)
            return
        case .ungeprueft(let grund):
            melden("\(getan), aber die Ablage ließ sich nicht zurücklesen (\(grund)) — die nächste Sicherung "
                   + "schreibt sie im neuen Stand.", .warnung)
            return
        case .geschrieben, .vorschau:
            break
        }
        let alt = ergebnis.nebendateien.umgestellt.count
        var text = getan + " — die Ablage auf diesem Mac ist im neuen Stand"
            + (alt > 0 ? ", \(alt) ältere \(alt == 1 ? "Stand" : "Stände") daneben ebenfalls" : "")
            + (ergebnis.lesezeichen == .erledigt ? ", die Lesezeichen mit ihr" : "")
        var nachgezogen: [String] = []
        if ergebnis.kopie == .erledigt { nachgezogen.append("die Kopie außer Haus") }
        if ergebnis.statusdatei == .erledigt { nachgezogen.append("die Statusdatei der Ansicht") }
        if !nachgezogen.isEmpty { text += ", " + nachgezogen.joined(separator: " und ") + " sofort nachgezogen" }
        text += "."
        let offenes = ergebnis.offenes
        guard !offenes.isEmpty else { melden(text); return }
        text += " Offen: " + offenes.joined(separator: "; ") + ". Nebendateien holt die App beim nächsten "
            + "Start nach, die Kopie folgt beim nächsten Beenden; eine liegengebliebene Statusdatei wird "
            + "nicht mehr gelesen — bitte in der Ansicht die neue Kopie öffnen."
        melden(text, .warnung)
    }

    /// Schritt 2, nach dem bestätigten Blatt — der Übergang in fester
    /// Reihenfolge: erst den letzten Stand der Ansicht unter der alten Regel
    /// übernehmen, dann die Sitzung, die Ablage sofort und geprüft, die
    /// Nebendateien, die Kopie außer Haus und die Statusdatei — und eine
    /// Meldung aus dem Ergebnis. Scheitert die Ablage, bleibt alles beim Alten.
    @discardableResult
    func verschluesselungEinschalten() -> Schutzergebnis {
        guard let neu = vorbereitung else {
            return Schutzergebnis(ablage: .zurueckgenommen("keine Vorbereitung"))
        }
        vorbereitung = nil
        let alter = self.tresor
        statusUebernehmen()
        tresorAnlegen(neu)
        var ergebnis = Schutzergebnis(ablage: ablageSchreibenGeprueft(alter: alter, neu: neu))
        let getan = alter == nil ? "Verschlüsselung eingeschaltet" : "Schlüssel erneuert"
        let nichtGetan = alter == nil ? "Verschlüsselung nicht eingeschaltet" : "Schlüssel nicht erneuert"
        if case .zurueckgenommen = ergebnis.ablage {
            schutzMelden(ergebnis, getan: getan, nichtGetan: nichtGetan)
            nachEinrichtung = nil
            return ergebnis
        }
        if !sicherung.istVorschau {
            ergebnis.nebendateien = sicherung.ablage.altbestaendeVersiegeln(mit: neu, alter: alter)
        }
        ergebnis.lesezeichen = lesezeichenVersiegeln(unter: neu, alter: alter)
        (ergebnis.kopie, ergebnis.statusdatei) = aussenstellenNachziehen(alter: alter, neu: neu)
        schutzMelden(ergebnis, getan: getan, nichtGetan: nichtGetan)
        let fortsetzung = nachEinrichtung
        nachEinrichtung = nil
        fortsetzung?()
        return ergebnis
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
    /// Änderung an der Planung —, der Behälter der Lesezeichen mit denselben
    /// Wicklungen, die Kopie beim nächsten Beenden.
    func neuVersiegeln() {
        sicherung.neuSchreibenErzwingen()
        jetztSichern()
        zugriff.neuVersiegeln()
    }

    /// Der Rückweg — eine Einbahnstraße wäre bei einer Jahresplanung nicht zu
    /// verantworten. Die Kopie außer Haus gibt es danach nicht mehr; die
    /// Statusdatei im Zielordner bleibt, wie sie ist. Scheitert die Ablage,
    /// bleibt die Sitzung versiegelt.
    @discardableResult
    func verschluesselungAufheben() -> Schutzergebnis {
        guard let tresor else { return Schutzergebnis(ablage: .zurueckgenommen("nicht eingeschaltet")) }
        tresorAnlegen(nil)
        // Erst die Ablage im Klartext hinlegen — dabei wandert der versiegelte
        // Stand nach planung-vorher.json —, dann die Nebendateien entsiegeln.
        var ergebnis = Schutzergebnis(ablage: ablageSchreibenGeprueft(alter: tresor, neu: nil))
        if case .zurueckgenommen = ergebnis.ablage {
            schutzMelden(ergebnis, getan: "Verschlüsselung aufgehoben", nichtGetan: "Verschlüsselung nicht aufgehoben")
            return ergebnis
        }
        if !sicherung.istVorschau {
            ergebnis.nebendateien = sicherung.ablage.altbestaendeEntsiegeln(tresor)
            // Die Lesezeichen zurück in die Einstellungen, der Behälter weg.
            zugriff.entsiegeln()
            ergebnis.lesezeichen = .erledigt
        }
        let alt = ergebnis.nebendateien.umgestellt.count
        var text = "Verschlüsselung aufgehoben — die Ablage liegt wieder im Klartext"
            + (alt > 0 ? ", \(alt) ältere \(alt == 1 ? "Stand" : "Stände") daneben ebenfalls" : "")
            + (ergebnis.lesezeichen == .erledigt ? ", die Lesezeichen wieder in den Einstellungen" : "")
            + "."
        if case .ungeprueft(let grund) = ergebnis.ablage {
            text += " Die Ablage ließ sich nicht zurücklesen (\(grund)) — die nächste Sicherung schreibt sie im Klartext."
        }
        if !ergebnis.nebendateien.vollstaendig {
            text += " Noch versiegelt: \(ergebnis.nebendateien.beschreibung)."
        }
        if autoexportAktiv {
            autoexportAktiv = false
            text += " Die Sicherungskopie beim Beenden ist ausgeschaltet: Es gibt sie nur verschlüsselt."
        }
        melden(text, .warnung)
        return ergebnis
    }

    /// 32 Byte neu wickeln; die Kopie außer Haus folgt sofort — eine ältere
    /// Kopie in der Cloud kennt sonst noch die alte Passphrase. Statusdatei und
    /// Lesezeichen bleiben gültig: derselbe Datenschlüssel.
    @discardableResult
    func passphraseAendern(alt: String, neu: String) throws -> Schutzergebnis {
        guard let tresor else { return Schutzergebnis(ablage: .zurueckgenommen("nicht eingeschaltet")) }
        guard tresor.passphraseStimmt(alt) else {
            throw Tresorfehler(art: .falscherSchluessel, text: "Die bisherige Passphrase passt nicht.")
        }
        try tresor.passphraseSetzen(neu)
        var ergebnis = Schutzergebnis(ablage: ablageSchreibenGeprueft(alter: tresor, neu: tresor))
        if !sicherung.istVorschau {
            ergebnis.nebendateien = sicherung.ablage.altbestaendeVersiegeln(mit: tresor)
        }
        (ergebnis.kopie, _) = aussenstellenNachziehen(alter: tresor, neu: tresor)
        schutzMelden(ergebnis, getan: "Passphrase geändert", nichtGetan: "Passphrase geändert, aber")
        return ergebnis
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
                zugriff.schliessen()
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
        entsperrungsgeneration &+= 1
        if ziel.istAblage {
            sicherung.gesperrt = true
            sitzung = .gesperrt(ziel, kopf)
            // Bis zum Entsperren ist der Vorrat zu: Nichts fragt nach einem Ort.
            zugriff.schliessen()
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

    /// Passphrase oder Wiederherstellungsschlüssel — die Schlüsselableitung
    /// läuft abseits des Hauptstrangs (bis zu zehn Millionen Runden aus einer
    /// fremden Datei), das Blatt bleibt bedienbar. Ein Ergebnis, dessen Ziel
    /// inzwischen gewechselt hat oder abgebrochen wurde, wird verworfen.
    func entsperren(passphrase: String) async {
        await entsperren { kopf in try Tresor.oeffnen(kopf: kopf, passphrase: passphrase) }
    }

    func entsperren(wiederherstellung: String) async {
        await entsperren { kopf in try Tresor.oeffnen(kopf: kopf, wiederherstellung: wiederherstellung) }
    }

    private func entsperren(_ oeffnen: @escaping @Sendable (Behaelterkopf) throws -> Tresor) async {
        guard let kopf = gesperrterKopf, !entsperrungLaeuft else { return }
        entsperrungLaeuft = true
        entsperrungFehler = nil
        let generation = entsperrungsgeneration
        let ergebnis: Result<Tresor, Tresorfehler> = await Task.detached(priority: .userInitiated) {
            do { return .success(try oeffnen(kopf)) }
            catch let fehler as Tresorfehler { return .failure(fehler) }
            catch { return .failure(Tresorfehler(art: .beschaedigt, text: error.localizedDescription)) }
        }.value
        entsperrungLaeuft = false
        guard generation == entsperrungsgeneration, entsperrung != nil else { return }
        switch ergebnis {
        case .success(let tresor): entsperrt(mit: tresor, durchEnklave: false)
        case .failure(let fehler): entsperrungFehler = fehler.text
        }
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
        entsperrungsgeneration &+= 1
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
        entsperrungsgeneration &+= 1
        entsperrungFehler = nil
        if offenerDialog == .entsperren { offenerDialog = nil }
        switch ziel {
        case .ablage(let daten):
            tresorAnlegen(tresor)
            sicherung.gesperrt = false
            // Erst die Lesezeichen samt Zielordner, dann die Planung: Schon der
            // Statusabgleich beim Laden braucht den Zielordner.
            lesezeichenOeffnen(tresor)
            do {
                geladenAusKlartext(try tresor.oeffnen(daten))
                if !durchEnklave { enklaveAngleichen(tresor) }
                nebendateienNachholen()
            } catch { unlesbarenStandBehandeln(error) }
            lesezeichenNachruesten()
        case .vorige(let vorige, let grund):
            tresorAnlegen(tresor)
            lesezeichenOeffnen(tresor)
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
            lesezeichenNachruesten()
        case .datei(let daten, let url):
            dateiEntsperrung = nil
            do { importierenKlartext(try tresor.oeffnen(daten), von: url) }
            catch { melden(error.localizedDescription, .warnung) }
        }
    }

    /// Nach dem Entsperren: die Lesezeichen und den Zielordner aus dem Behälter
    /// neben der Ablage. Gemeldet wird, was vom Gewöhnlichen abweicht — der
    /// erste Start dieser Fassung, ein beschädigter Behälter, ein Fehlschlag —,
    /// nie still.
    private func lesezeichenOeffnen(_ tresor: Tresor) {
        switch zugriff.oeffnen(mit: tresor, stempel: Zeitrechnung.dateistempel()) {
        case .geoeffnet:
            break
        case .angelegt(let anzahl, let zielordner):
            guard anzahl > 0 || zielordner else { return }
            melden("Die Lesezeichen und der Zielordner der Sicherungskopie liegen jetzt versiegelt "
                   + "neben der Ablage — in den Einstellungen steht kein Pfad mehr im Klartext.")
        case .beiseitegelegt(let grund):
            melden("Der Behälter der Lesezeichen war nicht lesbar (\(grund)) und liegt als Rettungskopie "
                   + "neben der Ablage. Die App fragt nach den Ordnern, die sie kennt; den Zielordner "
                   + "der Sicherungskopie bitte unter „Einstellungen“ erneut wählen.", .warnung)
        case .klartextGeblieben(let grund):
            melden("Die Lesezeichen ließen sich nicht versiegeln (\(grund)) — sie bleiben vorerst "
                   + "unverschlüsselt in den Einstellungen; die App versucht es beim nächsten Start.", .warnung)
        case .unlesbar(let grund):
            melden("Der Behälter der Lesezeichen ließ sich nicht lesen (\(grund)) — die App fragt nach "
                   + "den Ordnern, die sie kennt.", .warnung)
        }
    }
}
