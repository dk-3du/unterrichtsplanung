// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Nachwahl: Zugriff auf bisher genutzte Ordner ─────────────────────────────
// Im Sandbox kennt die App den Zielordner der Kopie und den Basisordner
// der Materialien nur als Pfad, bis der Nutzer sie einmal gewählt hat.
extension Planungsspeicher {

    struct Ordnerfreigabe: Identifiable, Equatable, Sendable {
        enum Zweck: Sendable { case zielordner, basisordner }
        let zweck: Zweck
        let pfad: String
        var id: String { (zweck == .zielordner ? "ziel:" : "basis:") + pfad }
        var titel: String {
            zweck == .zielordner ? "Ordner der Sicherungskopie" : "Basisordner der Materialien"
        }
    }

    /// Gefragt wird nur, was sich auch merken lässt: Solange der Vorrat zu
    /// oder gesperrt ist, bleibt die Liste leer. Ein leerer Pfad steht für
    /// den Zielordner, der mit einem Behälter verloren ging, während die Kopie
    /// eingeschaltet blieb.
    func freigabenNachfuehren() {
        guard Ordnerzugriff.imSandbox || nachwahlProbe, zugriff.schreibbar else {
            if !ausstehendeFreigaben.isEmpty { ausstehendeFreigaben = [] }
            return
        }
        var liste: [Ordnerfreigabe] = []
        if !autoexportOrdner.isEmpty, zugriff.zustaendig(fuer: autoexportOrdner) == nil {
            liste.append(Ordnerfreigabe(zweck: .zielordner, pfad: autoexportOrdner))
        } else if autoexportOrdner.isEmpty, autoexportAktiv {
            liste.append(Ordnerfreigabe(zweck: .zielordner, pfad: ""))
        }
        if let basis = planung?.basis, !basis.isEmpty, zugriff.zustaendig(fuer: basis) == nil {
            liste.append(Ordnerfreigabe(zweck: .basisordner, pfad: basis))
        }
        if liste != ausstehendeFreigaben { ausstehendeFreigaben = liste }
    }

    /// Wie die Ersteinrichtung: erst mit Planung, nie über ein offenes Blatt,
    /// nie im Prüflauf — außer er gibt die Ordner vor.
    func nachwahlPruefen() {
        guard !Ablage.istPruefstand || nachwahlProbe else { return }
        freigabenNachfuehren()
        guard hatPlanung, !dialogOffen, !nachwahlVerschoben, !ausstehendeFreigaben.isEmpty
        else { return }
        offenerDialog = .nachwahl
    }

    /// Das Blatt mit vorgegebenen Ordnern — für `--abbild --dialog nachwahl`
    /// und die Abbild-Suite; gemerkt wird davon nichts.
    func nachwahlVorgeben(zielordner: String, basis: String) {
        nachwahlProbe = true
        autoexportOrdner = zielordner
        if var p = planung { p.basis = basis; planung = p }
        freigabenNachfuehren()
    }

    func nachwahlSpaeter() {
        nachwahlVerschoben = true
        if offenerDialog == .nachwahl { offenerDialog = nil }
    }

    /// „Wählen …“ zu einem Ordner: Der Dialog steht auf dem gespeicherten
    /// Pfad; gewählt wird der Ordner selbst oder einer darüber. Ein anderer
    /// Ordner für die Kopie ist ab dann ihr Zielordner; ein anderer Ordner
    /// für die Materialien deckt sie nicht und wird benannt.
    func nachwahlWaehlen(_ freigabe: Ordnerfreigabe) {
        let titel = freigabe.pfad.isEmpty
            ? "Ordner für die Sicherungskopie wählen"
            : "Zugriff erlauben: „\(Pfade.dateiName(freigabe.pfad))“ wählen — oder einen "
              + "Ordner darüber; er gilt dann für alles darin"
        guard let gewaehlt = Systemzugriff.ordnerWaehlen(start: freigabe.pfad, mehrere: false,
                                                        titel: titel, zugriff: zugriff).first
        else { return }
        if !freigabe.pfad.isEmpty, zugriff.zustaendig(fuer: freigabe.pfad) != nil {
            melden("Zugriff erteilt: \(freigabe.titel).")
            if freigabe.zweck == .zielordner { statusUebernehmen() }
        } else if freigabe.zweck == .zielordner {
            autoexportZielSetzen(gewaehlt)
            _ = autoexportAusfuehren(vomNutzer: true)
            statusUebernehmen()
        } else {
            melden("„\(Pfade.dateiName(gewaehlt))“ enthält den Basisordner nicht — die Materialien "
                   + "darin bleiben unerreichbar, bis er selbst oder ein Ordner darüber gewählt ist.",
                   .warnung)
        }
        freigabenNachfuehren()
        if ausstehendeFreigaben.isEmpty, offenerDialog == .nachwahl { offenerDialog = nil }
    }
}
