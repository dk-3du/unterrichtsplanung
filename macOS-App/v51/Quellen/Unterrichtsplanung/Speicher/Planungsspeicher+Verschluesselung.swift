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

    /// Die Ablage liegt versiegelt und ist nicht offen — mit Kopf (zu
    /// entsperren) oder ohne (eine neuere Fassung hat versiegelt).
    var ablageGesperrt: Bool { sitzung.stand == .gesperrt }

    /// Warum ein Übergang des Schutzes gerade nicht beginnt: Die Ablage lässt
    /// sich nicht schreiben (Planung über der Schreibgrenze). Das Blatt zeigt
    /// den Grund und sperrt die Knöpfe; die Übergänge prüfen ihn selbst.
    var schutzuebergangGesperrt: String? { sicherung.schreibsperrgrund }

    /// Warum gerade nichts angelegt oder geöffnet werden darf.
    var sperrhinweis: String {
        sitzung.entsperrung != nil
            ? "Die Planung ist verschlüsselt und noch nicht entsperrt — bitte zuerst entsperren."
            : "Die Planung auf diesem Mac stammt aus einer neueren Fassung — bitte die App "
              + "aktualisieren; bis dahin wird nichts angelegt oder geöffnet."
    }

    /// Die Sitzung umstellen: Schlüssel setzen oder ablegen — die Planung
    /// bleibt, der Stand folgt (`.verschluesselt`, sonst `.klartext` oder
    /// `.leer`). Im Übergang erst nach der Marke. Aus `.gesperrt` führt das
    /// nur mit Schlüssel heraus; die Planung kommt danach von der Platte.
    private func tresorAnlegen(_ neu: Tresor?) {
        sitzung = sitzung.mit(tresor: neu)
        enklaveEingerichtet = neu?.hat(Wicklung.enklave) ?? false
        // Was noch für den vorigen Schlüssel rechnet, darf nichts mehr bewirken.
        schluesselarbeitVerwerfen()
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
    /// `enklaveImPruefstandAnlegen` öffnet den Weg für die eine Prüfung, die
    /// ihn braucht — je Speicher, nicht prozessweit.
    var enklaveMoeglich: Bool {
        (Tresor.enklaveVerfuegbar || (enklaveImPruefstandAnlegen && Tresor.enklaveVorhanden))
            && gesperrterKopf?.wicklung(Wicklung.enklave) != nil && entsperrungFuerAblage
    }

    /// Öffnet die Einrichtung; `danach` läuft, sobald eingeschaltet ist —
    /// etwa das Einschalten der Kopie beim Beenden.
    func verschluesselungEinrichten(danach: (@MainActor () -> Void)? = nil) {
        nachEinrichtung = danach
        dialogOeffnen(.verschluesselung)
    }

    // ── Schlüsselarbeit abseits des Hauptstrangs ──────────────────────────
    // PBKDF2 mit einer Million Runden dauert eine Sekunde und mehr; beim
    // Ändern und Erneuern läuft es zweimal. Wie das Entsperren: unveränderliche
    // Eingaben einsammeln, rechnen, das Ergebnis nur übernehmen, wenn der
    // Anlass noch gilt. Die Rechnung selbst steht in `nonisolated static`
    // Funktionen ohne Sitzung — dieselben für den synchronen Weg der
    // Prüfungen und Prüfstände.

    /// Datenschlüssel und Wicklungen — reine Schlüsselarbeit ohne Sitzung.
    nonisolated static func tresorVorbereiten(passphrase: String, enklave: Bool) throws
        -> (tresor: Tresor, blatt: String) {
        let tresor = Tresor.neu()
        try tresor.passphraseSetzen(passphrase)
        let blatt = try tresor.wiederherstellungAnlegen()
        if enklave { try tresor.enklaveAnlegen() }
        return (tresor, blatt)
    }

    /// Die bisherige Passphrase belegen und die neue Wicklung an einer Kopie
    /// des Tresors anlegen — der Tresor der Sitzung bleibt unberührt, bis der
    /// Hauptstrang sie übernimmt.
    nonisolated static func passphraseNeuWickeln(_ tresor: Tresor, alt: String, neu: String) throws -> Wicklung {
        try tresor.passphraseBelegen(alt)
        let kopie = Tresor(schluessel: tresor.schluessel, kennung: tresor.kennung)
        try kopie.passphraseSetzen(neu)
        guard let wicklung = kopie.wicklungen.first(where: { $0.art == Wicklung.passphrase }) else {
            throw Tresorfehler(art: .beschaedigt, text: "Die neue Wicklung ließ sich nicht anlegen.")
        }
        return wicklung
    }

    /// Erneuern: die bisherige belegen, die neue muss eine andere sein — dann
    /// ein frischer Tresor wie beim Einrichten.
    nonisolated static func erneuernVorbereiten(_ alter: Tresor, alt: String, neu: String,
                                                enklave: Bool) throws -> (tresor: Tresor, blatt: String) {
        try alter.passphraseBelegen(alt)
        guard neu != alt else {
            throw Tresorfehler(art: .falscherSchluessel,
                               text: "Die neue Passphrase muss sich von der bisherigen unterscheiden.")
        }
        return try tresorVorbereiten(passphrase: neu, enklave: enklave)
    }

    /// `arbeit` rechnet abseits des Hauptstrangs, `uebernehmen` läuft danach
    /// hier — nur, wenn die Generation noch gilt (kein Verwerfen dazwischen).
    /// Ein zweiter Aufruf, solange einer läuft, ist wirkungslos: `nil`.
    private func schluesselarbeit<Ergebnis: Sendable, Wert>(
        _ arbeit: @escaping @Sendable () throws -> Ergebnis,
        uebernehmen: (Ergebnis) throws -> Wert) async throws -> Wert? {
        guard !schluesselarbeitLaeuft else { return nil }
        schluesselarbeitLaeuft = true
        defer { schluesselarbeitLaeuft = false }
        let generation = schluesselgeneration
        let ergebnis: Result<Ergebnis, any Error> = await Task.detached(priority: .userInitiated) {
            Result { try arbeit() }
        }.value
        guard generation == schluesselgeneration else { return nil }
        return try uebernehmen(try ergebnis.get())
    }

    /// Was gerade rechnet, soll nichts mehr bewirken — Abbrechen, Blatt zu.
    func schluesselarbeitVerwerfen() {
        schluesselgeneration &+= 1
    }

    /// Schritt 1: Datenschlüssel und Wicklungen; liefert den Wiederherstellungs-
    /// schlüssel, der einmal gezeigt und nie gespeichert wird. Eingeschaltet ist
    /// damit noch nichts. Synchron — für Prüfungen und Prüfstände.
    func verschluesselungVorbereiten(passphrase: String) throws -> String {
        let (tresor, blatt) = try Planungsspeicher.tresorVorbereiten(
            passphrase: passphrase, enklave: Tresor.enklaveVerfuegbar)
        vorbereitung = tresor
        return blatt
    }

    /// Dasselbe abseits des Hauptstrangs — für die Blätter. `nil`: verworfen
    /// oder schon eine Rechnung im Gang.
    func verschluesselungVorbereitenAsynchron(passphrase: String) async throws -> String? {
        let enklave = Tresor.enklaveVerfuegbar
        return try await schluesselarbeit({
            try Planungsspeicher.tresorVorbereiten(passphrase: passphrase, enklave: enklave)
        }) { vorbereitet in
            vorbereitung = vorbereitet.tresor
            return vorbereitet.blatt
        }
    }

    /// Was ein Übergang des Schutzes auf die Platte gebracht hat — die
    /// Meldung kommt daraus, nicht aus der Absicht.
    struct Schutzergebnis: Equatable {
        enum Ablagebefund: Equatable {
            /// Die Generation ist eingesetzt: Die Platte trägt den neuen Stand.
            case geschrieben
            /// Nicht übergeben — die Platte trägt den alten Stand, die Sitzung auch.
            case zurueckgenommen(String)
            /// Übergeben, aber nicht jede Datei eingesetzt: Der neue Stand gilt,
            /// die Marke liegt, der nächste Start vollendet das Einsetzen.
            case unvollendet(String)
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
        /// Die Sitzpläne: versiegelt, unter den neuen Schlüssel, oder zurück
        /// in den Klartext — wie die Planung selbst.
        var sitzplaene: Aussenstelle = .nichtNoetig
        var kopie: Aussenstelle = .nichtNoetig
        var statusdatei: Aussenstelle = .nichtNoetig

        /// Was benannt werden muss — leer heißt: alles erreicht.
        var offenes: [String] {
            var teile: [String] = []
            if case .unvollendet(let grund) = ablage {
                teile.append("nicht jede Datei eingesetzt (\(grund.ohneSchlusspunkt)) — der nächste Start vollendet den Übergang")
            }
            if !nebendateien.vollstaendig { teile.append("neben der Ablage: " + nebendateien.beschreibung) }
            if case .offen(let grund) = lesezeichen { teile.append("Lesezeichen (\(grund))") }
            if case .offen(let grund) = sitzplaene { teile.append("Sitzpläne (\(grund))") }
            if case .offen(let grund) = kopie { teile.append("Kopie außer Haus (\(grund))") }
            if case .offen(let grund) = statusdatei { teile.append("Statusdatei der Ansicht (\(grund))") }
            return teile
        }
    }

    /// Der eine Weg jedes Übergangs (E47, E48): die Generation erzeugen —
    /// Ablage, Vorgängerfassung und Register vom Sicherungsdienst, der
    /// Behälter der Lesezeichen vom Ordnerzugriff, die Sitzpläne von ihrem
    /// Dienst —, die Zwillinge legen (*vorbereiten*), die Marke schreiben
    /// (*übergeben*), erst dann die Sitzung umstellen, dann *einsetzen* und
    /// die Außenstellen nachziehen (E51). Scheitert etwas vor der Marke, hat
    /// sich nichts geändert; danach gilt der neue Stand, und der nächste Start
    /// vollendet, was noch fehlt. `alter` und `neu` sind dasselbe Objekt, wenn
    /// nur die Hülle wechselt (Passphrase, Wicklung dieses Macs).
    private func uebergang(_ art: Uebergangsart, alter: Tresor?, neu: Tresor?, aussenstellen: Bool = true,
                           sitzungUmstellen: () -> Void) -> Schutzergebnis {
        // Vor der Marke hat sich nichts geändert — bis auf die Einstellungen des
        // Aufhebens, die hier zurückgenommen werden.
        func abgewiesen(_ grund: String) -> Schutzergebnis {
            if neu == nil { zugriff.entsiegelnVerwerfen() }
            return Schutzergebnis(ablage: .zurueckgenommen(grund))
        }
        if let grund = schutzuebergangGesperrt { return abgewiesen(grund) }
        if sicherung.istVorschau {
            sitzungUmstellen()
            return Schutzergebnis(ablage: .vorschau)
        }
        var ergebnis = Schutzergebnis(ablage: .geschrieben)
        var dateien: [String: Uebergangsdienst.Inhalt] = [:]
        // Die Ablage, die Vorgängerfassung, das Register.
        let nummer: Int
        let stand: String
        do {
            let generation = try sicherung.generationErzeugen(neu: neu, alter: alter)
            for (name, daten) in generation.dateien { dateien[name] = .daten(daten) }
            ergebnis.nebendateien = generation.bilanz
            nummer = generation.nummer
            stand = generation.stand
        } catch {
            let grund = switch error {
            case .vorschau: "eine Vorschau schreibt nicht"
            case .nichtsZuSchreiben: "keine Planung geladen"
            case .gesperrt: "die Ablage ist gesperrt, ein unlesbarer Stand liegt noch im Weg"
            case .schreiben(let text): text
            }
            return abgewiesen(grund)
        }
        // Die Lesezeichen: als Behälter unter dem neuen Schlüssel; beim Aufheben
        // zurück in die Einstellungen, der Behälter entfällt. Ein gesperrter
        // Vorrat ist aus dem Klartext kein Hindernis (B03) — der nächste Start
        // versiegelt ihn; beim Aufheben bleibt sein Behälter liegen; sonst wäre
        // er nach dem Wechsel fremd: Abweisung.
        let lesezeichen = sicherung.ablage.lesezeichen.lastPathComponent
        if zugriff.schreibbar {
            if let neu {
                do {
                    dateien[lesezeichen] = .daten(try zugriff.behaelter(unter: neu))
                    ergebnis.lesezeichen = .erledigt
                } catch {
                    return abgewiesen("die Lesezeichen ließen sich nicht versiegeln (\(error.localizedDescription.ohneSchlusspunkt))")
                }
            } else {
                if zugriff.quelle == .behaelter {
                    dateien[lesezeichen] = .entfernen
                    ergebnis.lesezeichen = .erledigt
                }
                zugriff.entsiegelnVorbereiten()
            }
        } else if let grund = zugriff.sperrgrund {
            switch art {
            case .einschalten:
                ergebnis.lesezeichen = .offen("die Datei bleibt liegen: \(grund.ohneSchlusspunkt) — beim nächsten "
                                              + "Start werden die Lesezeichen versiegelt")
            case .aufheben:
                ergebnis.lesezeichen = .offen("der Behälter bleibt liegen: \(grund.ohneSchlusspunkt)")
            default:
                return abgewiesen("die Lesezeichen sind gerade nicht lesbar (\(grund.ohneSchlusspunkt)) — nach einem Neustart erneut versuchen")
            }
        } else {
            return abgewiesen("die Lesezeichen sind noch nicht entsperrt")
        }
        // Die Sitzpläne: unter den neuen Schlüssel oder in den Klartext; ohne
        // Pläne entfällt die Datei. Gesperrt: aus dem Klartext kein Hindernis
        // (B03); beim Aufheben Abweisung — ohne Schlüssel wären sie für immer
        // zu (E38).
        let sitzplandatei = sicherung.ablage.sitzplaene
        if sitzplaene.schreibbar {
            do {
                if let daten = try sitzplaene.inhalt(unter: neu) {
                    dateien[sitzplandatei.lastPathComponent] = .daten(daten)
                    ergebnis.sitzplaene = .erledigt
                } else if FileManager.default.fileExists(atPath: sitzplandatei.path) {
                    dateien[sitzplandatei.lastPathComponent] = .entfernen
                }
            } catch {
                return abgewiesen("die Sitzpläne ließen sich nicht \(neu == nil ? "entsiegeln" : "versiegeln") "
                                  + "(\(error.localizedDescription.ohneSchlusspunkt))")
            }
        } else if let grund = sitzplaene.sperrgrund {
            guard art == .einschalten else {
                return abgewiesen("die Sitzpläne sind gerade nicht lesbar (\(grund.ohneSchlusspunkt)) — nach einem Neustart erneut versuchen")
            }
            ergebnis.sitzplaene = .offen("die Datei bleibt liegen: \(grund.ohneSchlusspunkt) — beim nächsten "
                                         + "Start werden die Sitzpläne versiegelt")
        } else {
            return abgewiesen("die Sitzpläne sind noch nicht entsperrt")
        }
        // Vorbereiten: die Zwillinge. Übergeben: die Marke — der eine Moment.
        let dienst = sicherung.uebergang
        if let grund = dienst.vorbereiten(art, kennung: neu?.kennung, stempel: Zeitrechnung.dateistempel(), dateien: dateien) {
            return abgewiesen("die Generation ließ sich nicht anlegen (\(grund.ohneSchlusspunkt))")
        }
        if let grund = dienst.uebergeben() {
            dienst.verwerfen()
            return abgewiesen("die Marke ließ sich nicht schreiben (\(grund.ohneSchlusspunkt))")
        }
        // Ab hier gilt der neue Stand: die Sitzung folgt, dann die Platte.
        sitzungUmstellen()
        zugriff.umschalten(auf: neu)
        sitzplaene.umschalten(auf: neu)
        if case .unvollendet(let grund) = sicherung.uebergangEinsetzen(nummer: nummer, stand: stand) {
            ergebnis.ablage = .unvollendet(grund)
        }
        if aussenstellen {
            (ergebnis.kopie, ergebnis.statusdatei) = aussenstellenNachziehen(alter: alter, neu: neu)
        }
        return ergebnis
    }

    /// Ein Übergang, der gar nicht erst beginnt: Die Ablage lässt sich nicht
    /// schreiben. Benannt wie eine Rücknahme — geschehen ist nichts.
    private func uebergangAbgewiesen(_ grund: String, nichtGetan: String) -> Schutzergebnis {
        let ergebnis = Schutzergebnis(ablage: .zurueckgenommen(grund))
        schutzMelden(ergebnis, getan: "", nichtGetan: nichtGetan)
        return ergebnis
    }

    /// Kopie außer Haus und Statusdatei der Ansicht sofort nachziehen —
    /// nicht erst beim Beenden (E51: Außenstellen, kein Teil der Generation).
    /// Die Statusdatei wandert unter den neuen Schlüssel; ohne Schlüssel
    /// (Aufheben) bleibt sie, wie sie ist.
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

    /// Die Meldung zu einem Übergang — je nachdem, was die Platte trägt.
    /// Intern statt privat: Die Prüfungen halten die Rücknahme-Meldung gegen
    /// ein Ergebnis mit offenen Sitzplänen (B17).
    func schutzMelden(_ ergebnis: Schutzergebnis, getan: String, nichtGetan: String) {
        switch ergebnis.ablage {
        case .zurueckgenommen(let grund):
            var text = "\(nichtGetan): \(grund). Die Planung bleibt, wie sie war."
            if case .offen(let lesezeichen) = ergebnis.lesezeichen { text += " Lesezeichen: \(lesezeichen)." }
            if case .offen(let sitzplaene) = ergebnis.sitzplaene { text += " Sitzpläne: \(sitzplaene)." }
            melden(text, .warnung)
            return
        case .geschrieben, .unvollendet, .vorschau:
            break
        }
        let alt = ergebnis.nebendateien.umgestellt.count
        var text = getan + " — die Ablage auf diesem Mac ist im neuen Stand"
            + (alt > 0 ? ", \(alt) \(alt == 1 ? "älterer Stand" : "ältere Stände") daneben ebenfalls" : "")
            + (ergebnis.lesezeichen == .erledigt ? ", die Lesezeichen mit ihr" : "")
            + (ergebnis.sitzplaene == .erledigt ? ", die Sitzpläne mit ihr" : "")
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

    /// Schritt 2, nach dem bestätigten Blatt: erst den letzten Stand der
    /// Ansicht unter der alten Regel übernehmen, dann der Übergang in einem
    /// Stand (Einschalten oder Erneuern) — und eine Meldung aus dem Ergebnis.
    @discardableResult
    func verschluesselungEinschalten() -> Schutzergebnis {
        guard let neu = vorbereitung else {
            return Schutzergebnis(ablage: .zurueckgenommen("keine Vorbereitung"))
        }
        vorbereitung = nil
        let alter = self.tresor
        let getan = alter == nil ? "Verschlüsselung eingeschaltet" : "Schlüssel erneuert"
        let nichtGetan = alter == nil ? "Verschlüsselung nicht eingeschaltet" : "Schlüssel nicht erneuert"
        if let grund = schutzuebergangGesperrt {
            nachEinrichtung = nil
            return uebergangAbgewiesen(grund, nichtGetan: nichtGetan)
        }
        statusUebernehmen()
        let ergebnis = uebergang(alter == nil ? .einschalten : .erneuern, alter: alter, neu: neu) { tresorAnlegen(neu) }
        schutzMelden(ergebnis, getan: getan, nichtGetan: nichtGetan)
        if case .zurueckgenommen = ergebnis.ablage {
            nachEinrichtung = nil
            return ergebnis
        }
        let fortsetzung = nachEinrichtung
        nachEinrichtung = nil
        fortsetzung?()
        return ergebnis
    }

    func verschluesselungVerwerfen() {
        vorbereitung = nil
        nachEinrichtung = nil
        schluesselarbeitVerwerfen()
    }

    /// Was neben einer versiegelten Ablage im Klartext liegt, wird beim
    /// nächsten Start nachgeholt (eine frühere Fassung, fremde Hand); was sich
    /// nicht versiegeln lässt oder unter einem fremden Schlüssel liegt, wird
    /// bei jedem Start benannt, bis es nicht mehr da ist.
    private func nebendateienNachholen() {
        guard !sicherung.istVorschau, let tresor else { return }
        let bilanz = sicherung.altbestaendeVersiegeln(mit: tresor, nurKlartext: true)
        guard !bilanz.umgestellt.isEmpty || !bilanz.vollstaendig else { return }
        var text = ""
        if !bilanz.umgestellt.isEmpty {
            let n = bilanz.umgestellt.count
            text = "\(n) \(n == 1 ? "älterer Stand" : "ältere Stände") neben der Ablage nachträglich versiegelt."
        }
        if !bilanz.vollstaendig {
            text += (text.isEmpty ? "" : " ") + "Übrig neben der Ablage: \(bilanz.beschreibung) — "
                + "bitte im Ordner der Ablage nachsehen."
        }
        melden(text, bilanz.vollstaendig ? .hinweis : .warnung)
    }

    /// Die Wicklung dieses Macs kam dazu oder fiel weg: alles, was sie trägt,
    /// in einem Stand neu versiegeln — Ablage, Vorgängerfassung, Register,
    /// Lesezeichen, Sitzpläne; Kopie und Statusdatei tragen sie nie. Liefert
    /// den Grund, wenn der Übergang nicht stattfand — dann gilt die Hülle auch
    /// in der Sitzung nicht, der Aufrufer nimmt die Wicklung zurück.
    func neuVersiegeln(_ art: Uebergangsart) -> String? {
        guard let tresor else { return "nicht eingeschaltet" }
        let ergebnis = uebergang(art, alter: tresor, neu: tresor, aussenstellen: false) {}
        if case .zurueckgenommen(let grund) = ergebnis.ablage { return grund }
        let offenes = ergebnis.offenes
        if !offenes.isEmpty {
            melden("Neu versiegelt — offen: " + offenes.joined(separator: "; ") + ". Bitte im Ordner der Ablage nachsehen.",
                   .warnung)
        }
        return nil
    }

    /// Der Rückweg — eine Einbahnstraße wäre bei einer Jahresplanung nicht zu
    /// verantworten. Ein Übergang in einem Stand wie das Einschalten: Ablage,
    /// Vorgängerfassung, Register und Sitzpläne kommen als Klartext in die
    /// Generation, der Behälter der Lesezeichen entfällt, ihr Vorrat geht in
    /// die Einstellungen. Die Kopie außer Haus gibt es danach nicht mehr; die
    /// Statusdatei im Zielordner bleibt, wie sie ist. Findet der Übergang nicht
    /// statt, bleibt die Sitzung versiegelt.
    @discardableResult
    func verschluesselungAufheben() -> Schutzergebnis {
        guard let tresor else { return Schutzergebnis(ablage: .zurueckgenommen("nicht eingeschaltet")) }
        if let grund = schutzuebergangGesperrt {
            return uebergangAbgewiesen(grund, nichtGetan: "Verschlüsselung nicht aufgehoben")
        }
        let ergebnis = uebergang(.aufheben, alter: tresor, neu: nil) { tresorAnlegen(nil) }
        if case .zurueckgenommen = ergebnis.ablage {
            schutzMelden(ergebnis, getan: "Verschlüsselung aufgehoben", nichtGetan: "Verschlüsselung nicht aufgehoben")
            return ergebnis
        }
        let alt = ergebnis.nebendateien.umgestellt.count
        var text = "Verschlüsselung aufgehoben — die Ablage liegt wieder im Klartext"
            + (alt > 0 ? ", \(alt) \(alt == 1 ? "älterer Stand" : "ältere Stände") daneben ebenfalls" : "")
            + (ergebnis.lesezeichen == .erledigt ? ", die Lesezeichen wieder in den Einstellungen" : "")
            + (ergebnis.sitzplaene == .erledigt ? ", die Sitzpläne ebenfalls im Klartext" : "")
            + "."
        if case .unvollendet(let grund) = ergebnis.ablage {
            text += " Nicht jede Datei ist schon eingesetzt (\(grund.ohneSchlusspunkt)) — der nächste Start vollendet den Übergang."
        }
        if !ergebnis.nebendateien.vollstaendig {
            text += " Noch versiegelt: \(ergebnis.nebendateien.beschreibung)."
        }
        if case .offen(let grund) = ergebnis.lesezeichen { text += " Lesezeichen: \(grund)." }
        if case .offen(let grund) = ergebnis.sitzplaene { text += " Sitzpläne: \(grund)." }
        if autoexportAktiv {
            autoexportAktiv = false
            text += " Die Sicherungskopie beim Beenden ist ausgeschaltet: Es gibt sie nur verschlüsselt."
        }
        melden(text, .warnung)
        return ergebnis
    }

    /// 32 Byte neu wickeln — und jede Datei, die diesen Datenschlüssel trägt,
    /// unter die neue Hülle: Ablage, Nebendateien, Lesezeichen, Sitzpläne in
    /// einem Stand, Kopie außer Haus und Statusdatei nachgezogen. Die alte
    /// Passphrase öffnet danach nichts mehr, was die App verwaltet; Kopien,
    /// die vorher jemand mitgenommen hat, erreicht das nicht — dafür ist das
    /// Erneuern da.
    @discardableResult
    func passphraseAendern(alt: String, neu: String) throws -> Schutzergebnis {
        guard let tresor else { return Schutzergebnis(ablage: .zurueckgenommen("nicht eingeschaltet")) }
        if let grund = schutzuebergangGesperrt { return uebergangAbgewiesen(grund, nichtGetan: "Passphrase nicht geändert") }
        return passphraseUebernehmen(try Planungsspeicher.passphraseNeuWickeln(tresor, alt: alt, neu: neu),
                                     fuer: tresor.kennung)
    }

    /// Dasselbe abseits des Hauptstrangs — für das Blatt.
    func passphraseAendernAsynchron(alt: String, neu: String) async throws -> Schutzergebnis? {
        guard let tresor else { return Schutzergebnis(ablage: .zurueckgenommen("nicht eingeschaltet")) }
        if let grund = schutzuebergangGesperrt { return uebergangAbgewiesen(grund, nichtGetan: "Passphrase nicht geändert") }
        let kennung = tresor.kennung
        return try await schluesselarbeit({
            try Planungsspeicher.passphraseNeuWickeln(tresor, alt: alt, neu: neu)
        }) { wicklung in passphraseUebernehmen(wicklung, fuer: kennung) }
    }

    /// Die neue Wicklung in den Tresor der Sitzung — sie prägt die Generation
    /// —, dann der Übergang; wird er nicht übergeben, kommt die bisherige
    /// Wicklung zurück, und nichts hat gewechselt. Gerechnet wurde sie für den
    /// Schlüssel `kennung` — trägt die Sitzung inzwischen einen anderen,
    /// gehört sie nirgends hinein.
    func passphraseUebernehmen(_ wicklung: Wicklung, fuer kennung: Data) -> Schutzergebnis {
        guard let tresor else { return Schutzergebnis(ablage: .zurueckgenommen("nicht eingeschaltet")) }
        guard tresor.kennung == kennung else {
            return Schutzergebnis(ablage: .zurueckgenommen("der Sitzungsschlüssel hat gewechselt"))
        }
        if let grund = schutzuebergangGesperrt { return uebergangAbgewiesen(grund, nichtGetan: "Passphrase nicht geändert") }
        guard let bisherige = tresor.wicklung(Wicklung.passphrase) else {
            return Schutzergebnis(ablage: .zurueckgenommen("der Schlüssel trägt keine Passphrase-Wicklung"))
        }
        tresor.wicklungUebernehmen(wicklung)
        let ergebnis = uebergang(.passphrase, alter: tresor, neu: tresor) {}
        if case .zurueckgenommen = ergebnis.ablage { tresor.wicklungUebernehmen(bisherige) }
        schutzMelden(ergebnis, getan: "Passphrase geändert", nichtGetan: "Passphrase nicht geändert")
        return ergebnis
    }

    /// Frischer Datenschlüssel, neue Passphrase, neues Blatt — die Antwort auf
    /// eine verbrannte Passphrase; scharf erst nach dem bestätigten Blatt.
    func schluesselErneuernVorbereiten(alt: String, neu: String) throws -> String {
        guard let alter = tresor else {
            throw Tresorfehler(art: .keineWicklung, text: "Die Verschlüsselung ist nicht eingeschaltet.")
        }
        let (tresor, blatt) = try Planungsspeicher.erneuernVorbereiten(
            alter, alt: alt, neu: neu, enklave: Tresor.enklaveVerfuegbar)
        vorbereitung = tresor
        return blatt
    }

    /// Dasselbe abseits des Hauptstrangs — für das Blatt.
    func schluesselErneuernVorbereitenAsynchron(alt: String, neu: String) async throws -> String? {
        guard let alter = tresor else {
            throw Tresorfehler(art: .keineWicklung, text: "Die Verschlüsselung ist nicht eingeschaltet.")
        }
        let enklave = Tresor.enklaveVerfuegbar
        return try await schluesselarbeit({
            try Planungsspeicher.erneuernVorbereiten(alter, alt: alt, neu: neu, enklave: enklave)
        }) { vorbereitet in
            vorbereitung = vorbereitet.tresor
            return vorbereitet.blatt
        }
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
                sitzplaene.schliessen()
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
                sicherung.lageMelden(.schreiben)
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
            // Bis zum Entsperren sind Vorrat und Sitzpläne zu.
            zugriff.schliessen()
            sitzplaene.schliessen()
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
            guard enklaveWicklungEntfernen(tresor) else { return }
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
            guard tresor.hat(Wicklung.enklave), enklaveWicklungEntfernen(tresor) else { return }
            melden("Die Wicklung dieses Macs ist entfernt — beim Start ist die Passphrase fällig.")
        }
    }

    /// Die Wicklung dieses Macs anlegen und alles damit neu versiegeln —
    /// findet der Übergang nicht statt, gilt sie auch in der Sitzung nicht: Es
    /// bleibt, was vorher war — keine oder die alte, nicht mehr passende Wicklung.
    private func enklaveWicklungAnlegen(_ tresor: Tresor) -> Bool {
        guard Tresor.enklaveVerfuegbar || enklaveImPruefstandAnlegen else { return false }
        if let grund = schutzuebergangGesperrt {
            melden("Die Wicklung für diesen Mac wird nicht angelegt: \(grund).", .warnung)
            return false
        }
        let bisherige = tresor.wicklung(Wicklung.enklave)
        do { try tresor.enklaveAnlegen(auchImPruefstand: enklaveImPruefstandAnlegen) }
        catch {
            melden("Die Wicklung für diesen Mac ließ sich nicht anlegen: " + error.localizedDescription, .warnung)
            return false
        }
        if let grund = neuVersiegeln(.wicklungAnlegen) {
            if let bisherige { tresor.wicklungUebernehmen(bisherige) } else { tresor.entfernen(art: Wicklung.enklave) }
            melden("Die Wicklung für diesen Mac wird nicht angelegt: \(grund).", .warnung)
            return false
        }
        enklaveEingerichtet = true
        return true
    }

    /// Der Rückweg — die Wicklung bleibt, wenn die Ablage nicht ohne sie
    /// geschrieben werden kann.
    private func enklaveWicklungEntfernen(_ tresor: Tresor) -> Bool {
        guard let bisherige = tresor.wicklung(Wicklung.enklave) else { return false }
        if let grund = schutzuebergangGesperrt {
            melden("Die Wicklung dieses Macs bleibt: \(grund).", .warnung)
            return false
        }
        tresor.entfernen(art: Wicklung.enklave)
        if let grund = neuVersiegeln(.wicklungEntfernen) {
            tresor.wicklungUebernehmen(bisherige)
            melden("Die Wicklung dieses Macs bleibt: \(grund).", .warnung)
            return false
        }
        enklaveEingerichtet = false
        return true
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
            // Die Sitzpläne ebenso vor der Planung: Sie hängen an keinem Ladeschritt,
            // und ein unlesbarer Stand danach soll sie nicht bis zum Neustart sperren.
            sitzplaeneOeffnen(tresor)
            do {
                geladenAusKlartext(try tresor.oeffnen(daten))
                guard !ablageGesperrt else { zugriff.schliessen(); sitzplaene.schliessen(); return }
                if !durchEnklave { enklaveAngleichen(tresor) }
                nebendateienNachholen()
                sitzplaeneAufraeumen()
            } catch { unlesbarenStandBehandeln(error) }
            lesezeichenNachruesten()
        case .vorige(let vorige, let grund):
            tresorAnlegen(tresor)
            // Die Lesezeichen erst, wenn feststeht, unter welchem Schlüssel die
            // Sitzung weitergeht — ein Behälter unter dem verlorenen Schlüssel
            // wird dann als fremd beiseitegelegt, nicht als beschädigt.
            if let klartext = try? tresor.oeffnen(vorige),
               let (gerettet, bilanz) = try? Planungsdatei.lesenMitBilanz(klartext) {
                vorigeRettung(gerettet, bilanz: bilanz, grund: grund)
                lesezeichenOeffnen(tresor)
                sitzplaeneOeffnen(tresor)
                sitzplaeneAufraeumen()
                if !durchEnklave { enklaveAngleichen(tresor) }
            } else {
                lesezeichenOeffnen(tresor)
                sitzplaeneOeffnen(tresor)
                sicherung.lageMelden(.schreiben)
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
        case .beiseitegelegt(let grund, let rettung, let versiegelt):
            melden("Der Behälter der Lesezeichen galt nicht (\(grund)) und liegt als „\(rettung)“ neben "
                   + "der Ablage. Neu versiegelt: "
                   + (versiegelt == 0 ? "kein Lesezeichen" : "\(versiegelt) Lesezeichen aus dieser Sitzung")
                   + " — nach den übrigen Ordnern fragt die App; den Zielordner der Sicherungskopie bitte "
                   + "unter „Einstellungen“ prüfen.", .warnung)
        case .ungesichert(let grund):
            melden("Die Lesezeichen ließen sich nicht versiegeln (\(grund)) — sie gelten für diese "
                   + "Sitzung; die App versucht es beim nächsten Schreiben und beim nächsten Start erneut.",
                   .warnung)
        case .gesperrt(let grund):
            melden("Der Behälter der Lesezeichen bleibt unangetastet (\(grund)). Bis der nächste Start "
                   + "ihn liest, öffnet die App keine Materialien außerhalb ihres Containers und "
                   + "schreibt keine Sicherungskopie.", .warnung)
        }
    }
}
