// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Sicherungskopie beim Beenden ─────────────────────────────────────────────
// Geschrieben wird im Sicherungsdienst; hier stehen die Wahl des Ordners, der
// Schalter und die Sätze dazu.
extension Planungsspeicher {

    /// Sichtbar in den Einstellungen, damit klar ist, welche Datei die Ansicht
    /// öffnen soll.
    var autoexportDateiname: String {
        Planungsdatei.festerName(titel: planung?.titel ?? "Unterrichtsplanung")
    }

    /// Den Zielordner wählen — und sofort hinschreiben, damit ein Fehlschlag
    /// hier auffällt und nicht erst beim Beenden. `danach` sagt, ob die Kopie
    /// liegt (oder die Einrichtung übernommen hat); nach einem Abbruch kommt
    /// `false` — der Dialog hat einen Abschluss, keinen Rückgabewert (E115).
    func autoexportOrdnerWaehlen(_ danach: (@MainActor (Bool) -> Void)? = nil) {
        guard lesezeichenSchreibbar() else { danach?(false); return }
        Systemzugriff.ordnerWaehlen(start: autoexportOrdner, mehrere: false,
                                    titel: "Ordner für die Sicherungskopie wählen",
                                    zugriff: zugriff) { [weak self] wahl in
            guard let self, let gewaehlt = wahl.first else { danach?(false); return }
            // Die Kopie gibt es nur verschlüsselt: Ohne Tresor erst die Einrichtung,
            // dann Schalter und Probeschreibung.
            guard tresor != nil else {
                autoexportZielOhneTresor(gewaehlt)
                danach?(true)
                return
            }
            autoexportZielSetzen(gewaehlt)
            danach?(autoexportAusfuehren(vomNutzer: true))
        }
    }

    /// Der Zielordner steht, ein Schlüssel fehlt: erst die Einrichtung der
    /// Verschlüsselung, dann Schalter und Probeschreibung.
    ///
    /// **Eine Ablösung (B67, E239, v77):** `verschluesselungEinrichten` öffnet
    /// ein Blatt, und ein Fenster trägt nur eines — kommt die Wahl aus der
    /// Ersteinrichtung, ersetzt das neue Blatt deren Blatt nach der zweiten
    /// von vier Fragen. Bis 1.9.5 fielen die Fragen drei und vier damit auf
    /// die beiden Ersatzblätter zurück, die für ältere Planungen gedacht sind,
    /// und die Tour kam vor ihnen. Darum wird hier vorgemerkt, dass die
    /// Ersteinrichtung weitergeht; bei welchem Schritt, sagt sie selbst.
    /// Eigene Funktion, damit der Weg ohne den Ordnerdialog des Systems
    /// geprüft werden kann.
    func autoexportZielOhneTresor(_ gewaehlt: String) {
        if offenerDialog == .ersteinrichtung { ersteinrichtungFortsetzen = true }
        autoexportOrdner = gewaehlt
        autoexportAktiv = false
        sicherung.lesezeichenAblegen(URL(fileURLWithPath: gewaehlt, isDirectory: true))
        verschluesselungEinrichten { [weak self] in
            guard let self else { return }
            autoexportAktiv = true
            autoexportAusfuehren(vomNutzer: true)
        }
    }

    /// Der Schalter in den Einstellungen. Einschalten ohne Tresor richtet erst
    /// die Verschlüsselung ein und schaltet dann; ohne Zielordner wird der
    /// zuerst gewählt.
    func autoexportUmschalten(_ an: Bool) {
        guard an else { autoexportAktiv = false; return }
        guard !autoexportOrdner.isEmpty else { autoexportOrdnerWaehlen(); return }
        guard tresor != nil else {
            verschluesselungEinrichten { [weak self] in
                guard let self else { return }
                autoexportAktiv = true
                autoexportAusfuehren(vomNutzer: true)
            }
            return
        }
        autoexportAktiv = true
    }

    /// Pfad, Schalter und Lesezeichen zusammen — sie dürfen nie auseinanderlaufen.
    func autoexportZielSetzen(_ pfad: String) {
        guard lesezeichenSchreibbar() else { return }
        autoexportOrdner = pfad
        autoexportAktiv = true
        sicherung.lesezeichenAblegen(URL(fileURLWithPath: pfad, isDirectory: true))
        freigabenNachfuehren()
    }

    /// Solange der Vorrat der Lesezeichen gesperrt ist, lässt sich kein Ort
    /// merken — das sagt die Meldung, statt die Wahl still zu verwerfen.
    private func lesezeichenSchreibbar() -> Bool {
        guard let grund = zugriff.sperrgrund else { return true }
        melden("Der Zielordner lässt sich gerade nicht merken: Die Lesezeichen sind gesperrt (\(grund)). "
               + "Bitte die App neu starten.", .warnung)
        return false
    }

    /// Nachrüsten für eine Einstellung, die nur den Pfad kennt — und danach
    /// die Nachwahl nachführen, ob etwas offen bleibt.
    func lesezeichenNachruesten() {
        sicherung.lesezeichenNachruesten()
        freigabenNachfuehren()
    }

    /// Läuft beim Beenden: Nichts darf auf einen Ablaufwechsel warten, und ein
    /// Fehlschlag wird für den nächsten Start vorgemerkt.
    @discardableResult
    func autoexportAusfuehren(vomNutzer: Bool = false) -> Bool {
        guard planung != nil, autoexportAktiv || vomNutzer else { return false }
        guard !autoexportOrdner.isEmpty else {
            // Der Schalter ist an, der Ordner fort (mit dem Behälter der
            // Lesezeichen): nicht still ausfallen.
            if !vomNutzer, zugriff.schreibbar {
                sicherung.kopiefehlerVormerken("Für die Sicherungskopie ist kein Zielordner mehr gewählt — "
                                               + "bitte unter „Einstellungen“ einen wählen.")
            }
            return false
        }
        // Der Pfad steht nur in der Meldung, die gleich jemand liest — nie in
        // der Vormerkung, die bis zum nächsten Start in den Einstellungen liegt.
        let ort = vomNutzer ? " (\(autoexportOrdner))" : ""
        do {
            let (ziel, groesse) = try sicherung.kopieSchreiben(sitzung, name: autoexportDateiname)
            if vomNutzer { melden("Sicherungskopie geschrieben: \(ziel.path)") }
            // Geschrieben, aber jenseits der Lesegrenze: nicht still.
            if let hinweis = Planungsspeicher.lesegrenzeHinweis(groesse: groesse) {
                autoexportFehlerVormerken("Die Sicherungskopie wurde geschrieben, aber: " + hinweis,
                                          zeigen: vomNutzer)
            }
            return true
        } catch {
            switch error {
            case .nichtsZuSchreiben:
                break
            case .keinTresor:
                // Nur verschlüsselt; der Weg sagt, warum nichts kommt.
                autoexportFehlerVormerken(
                    "Die Sicherungskopie beim Beenden wird nur verschlüsselt "
                    + "geschrieben. Bitte unter „Einstellungen“ die Verschlüsselung einschalten — "
                    + "bis dahin wird keine Kopie geschrieben.", zeigen: vomNutzer)
            case .schreiben(_, let fehler):
                // Der Wortlaut des Systems nennt Datei und Ordner — er bleibt
                // der Sitzung; die Vormerkung trägt nur die Art.
                autoexportFehlerVormerken(
                    "Die Sicherungskopie ließ sich nicht in den Zielordner\(ort) schreiben"
                    + (vomNutzer ? ": \(fehler.localizedDescription)"
                                 : " — „Jetzt schreiben“ unter „Einstellungen“ nennt den Grund."),
                    zeigen: vomNutzer)
            case .zielordner(.keinZugriff):
                autoexportFehlerVormerken(
                    "Auf den Zielordner der Sicherungskopie\(ort) darf die App noch nicht zugreifen. "
                    + "Bitte den Ordner einmal wählen — unter „Einstellungen“ "
                    + "oder in der Frage beim Start; die App merkt sich die Wahl.", zeigen: vomNutzer)
            case .zielordner(.fehlt):
                autoexportFehlerVormerken(
                    "Der Zielordner der Sicherungskopie\(ort) ist nicht mehr da. "
                    + "Er wurde gelöscht, oder er liegt auf einem Datenträger, der gerade fehlt. "
                    + "Bitte unter „Einstellungen“ einen neuen wählen.", zeigen: vomNutzer)
            }
            return false
        }
    }

    /// Sofort zeigen, wo jemand davorsitzt — sonst für den nächsten Start
    /// vormerken.
    private func autoexportFehlerVormerken(_ text: String, zeigen: Bool) {
        if zeigen {
            melden(text, .warnung)
        } else {
            sicherung.kopiefehlerVormerken(text)
        }
    }
}
