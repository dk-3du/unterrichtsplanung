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
        guard planung?.klasse(id) != nil else { return }
        if let hinweis = sitzplaene.sperrhinweis {
            melden(hinweis, .warnung)
            return
        }
        sitzplanKlasse = id
        sitzplanRueckweg = zurueck
        sitzplanEntwurf = sitzplaene.plan(fuer: id)
        dialogOeffnen(.sitzplan)
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
        let grund = sitzplaene.setzen(plan, fuer: plan.klasseId)
        if grund == nil {
            melden("Sitzplan übernommen — \(plan.tische.count) "
                   + (plan.tische.count == 1 ? "Platz." : "Plätze."))
        }
        return grund
    }

    /// Zweistufig, jederzeit: die Rückfrage vor dem endgültigen Löschen. Aus
    /// dem Editor (`ort: .sitzplan`) läuft `danach` nach dem Löschen — das
    /// Blatt schließt sich.
    func sitzplanEntfernen(klasse id: String, ort: Rueckfrageort,
                           danach: (@MainActor () -> Void)? = nil) {
        guard let klasse = planung?.klasse(id), sitzplaene.plan(fuer: id) != nil else { return }
        fragen("Den Sitzplan von „\(klasse.name)“ endgültig löschen?\n\n"
               + "Eine gesicherte PDF bleibt davon unberührt; die Namen lassen sich jederzeit neu eingeben.",
               bestaetigung: "Sitzplan löschen", gefahr: true, ort: ort) { [weak self] in
            guard let self else { return }
            if let grund = sitzplaene.setzen(nil, fuer: id) {
                melden("Der Sitzplan wurde entfernt, die Platte trägt ihn womöglich noch (\(grund)).", .warnung)
            } else {
                melden("Sitzplan von „\(klasse.name)“ gelöscht.")
            }
            danach?()
        }
    }

    // ── ⌘P und ⇧⌘P aus der Menüleiste, solange der Editor offen ist ───────

    func sitzplanDrucken() {
        guard let plan = sitzplanEntwurf, let klasse = sitzplanKlasseStand else { return }
        Sitzplandruck.drucken(plan, klasse: klasse, speicher: self)
    }

    func sitzplanAlsPDFSichern() {
        guard let plan = sitzplanEntwurf, let klasse = sitzplanKlasseStand else { return }
        Sitzplandruck.alsPDFSichern(plan, klasse: klasse, speicher: self, ort: .sitzplan)
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

    /// Gemeldet wird, was vom Gewöhnlichen abweicht — nie still.
    private func sitzplanbefundMelden(_ befund: Sitzplandienst.Ladebefund) {
        switch befund {
        case .geladen, .keine:
            break
        case .nachgeholt(let anzahl):
            melden("\(anzahl) \(anzahl == 1 ? "Sitzplan lag" : "Sitzpläne lagen") im Klartext neben der "
                   + "versiegelten Planung und \(anzahl == 1 ? "ist" : "sind") jetzt versiegelt.")
        case .beiseitegelegt(let grund, let rettung):
            melden("Die Sitzpläne galten nicht (\(grund)) und liegen als „\(rettung)“ neben der "
                   + "Planung — bitte neu anlegen.", .warnung)
        case .gesperrt(let grund):
            melden("Die Sitzpläne bleiben unangetastet (\(grund)). Bis der nächste Start sie liest, "
                   + "lässt sich kein Sitzplan öffnen.", .warnung)
        }
    }
}
