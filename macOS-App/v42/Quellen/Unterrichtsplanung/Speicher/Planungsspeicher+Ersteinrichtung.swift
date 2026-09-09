// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Ersteinrichtung ──────────────────────────────────────────────────────────
// Drei Fragen nach der ersten Planung, alle freiwillig: erst
// die Verschlüsselung — mit der Einrichtung gleich im Blatt —, dann die
// Sicherungskopie beim Beenden, zuletzt die Prüfung auf Updates.
extension Planungsspeicher {

    /// Wer den Ordner schon gewählt hat, wird nicht gefragt.
    var ersteinrichtungFaellig: Bool {
        Planungsspeicher.ersteinrichtungFaellig(
            pruefstand: Ablage.istPruefstand,
            ordner: autoexportOrdner,
            gefragt: UserDefaults.standard.bool(forKey: Einstellungen.Schluessel.autoexportGefragt))
    }

    /// Die Entscheidung ohne ihre drei Quellen — sonst ließe sie sich nicht
    /// prüfen: Im Prüflauf ist `Ablage.istPruefstand` gesetzt.
    static func ersteinrichtungFaellig(pruefstand: Bool, ordner: String, gefragt: Bool) -> Bool {
        !pruefstand && ordner.isEmpty && !gefragt
    }

    /// Die Stationen des Blatts: die Frage nach der Verschlüsselung, deren
    /// zwei Einrichtungsschritte, die Frage nach der Sicherungskopie, die Frage
    /// nach den Updates. Im Speicher statt im Blatt, damit Prüfungen und
    /// Abbilder jede erreichen.
    enum Ersteinrichtungsschritt: Equatable, Sendable {
        case verschluesselung
        case passphrase
        /// Mit dem Wiederherstellungsschlüssel, der nur hier gezeigt wird.
        case blatt(String)
        case sicherung
        /// Beim Öffnen nach Updates suchen? Nur mit Einwilligung.
        case updates
    }

    /// Die Frage kommt erst, wenn eine Planung da ist und kein anderes Blatt
    /// offen liegt — sonst nähme sie ihm das Fenster weg.
    func ersteinrichtungPruefen() {
        guard ersteinrichtungFaellig, hatPlanung, !dialogOffen else { return }
        ersteinrichtungOeffnen()
    }

    /// Das Blatt öffnen, ohne die Schranke — für Prüfungen und Prüfstände.
    /// Ist die Verschlüsselung schon eingeschaltet (eine versiegelte Datei als
    /// erste Planung), bleibt nur die zweite Frage.
    func ersteinrichtungOeffnen() {
        ersteinrichtungsschritt = verschluesselt ? .sicherung : .verschluesselung
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
    /// zur zweiten Frage, deren Kopie dann von Anfang an versiegelt ist.
    func ersteinrichtungEinschalten() {
        guard case .blatt = ersteinrichtungsschritt else { return }
        verschluesselungEinschalten()
        ersteinrichtungsschritt = .sicherung
    }

    /// „Abbrechen“ in der Einrichtung: zurück zur Frage; geschehen ist nichts.
    func ersteinrichtungAbbrechen() {
        verschluesselungVerwerfen()
        ersteinrichtungsschritt = .verschluesselung
    }

    /// „Überspringen“: Die Verschlüsselung bleibt aus — nachzuholen unter
    /// „Einstellungen“, spätestens mit der Kopie, die es nur versiegelt gibt.
    func ersteinrichtungUeberspringen() {
        ersteinrichtungsschritt = .sicherung
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

    /// Die Antwort auf die dritte Frage; damit ist die Ersteinrichtung durch.
    func ersteinrichtungUpdates(erlauben: Bool) {
        updatesErlauben(erlauben)
    }
}
