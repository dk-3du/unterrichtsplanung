// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Einstellungen des Nutzers — geschrieben nur außerhalb eines Prüflaufs:
/// Eine Prüfung darf nichts in den Einstellungen des Nutzers hinterlassen.
enum Einstellungen {
    enum Schluessel {
        static let spaltenbreite = "unterrichtsplanung.spaltenbreite"
        static let erscheinung = "unterrichtsplanung.erscheinung"
        static let autoexportAktiv = "unterrichtsplanung.autoexport.aktiv"
        static let autoexportOrdner = "unterrichtsplanung.autoexport.ordner"
        static let autoexportStand = "unterrichtsplanung.autoexport.stand"
        static let autoexportFehler = "unterrichtsplanung.autoexport.fehler"
        /// Das Lesezeichen ohne Sicherheitsbereich einer Einstellung von vor
        /// dem Sandbox — wird nur noch entfernt.
        static let autoexportLesezeichenAlt = "unterrichtsplanung.autoexport.lesezeichen"
        static let autoexportGefragt = "unterrichtsplanung.autoexport.gefragt"
        static let tourAngeboten = "unterrichtsplanung.tour.angeboten"
        static let updatesErlaubt = "unterrichtsplanung.updates.erlaubt"
        static let updateZuletzt = "unterrichtsplanung.updates.zuletzt"
        static let updateUebersprungen = "unterrichtsplanung.updates.uebersprungen"
        static let updateEtag = "unterrichtsplanung.updates.etag"
        static let updateAntwort = "unterrichtsplanung.updates.antwort"
    }

    static func setzen(_ wert: Any, _ schluessel: String) {
        guard !Ablage.istPruefstand else { return }
        UserDefaults.standard.set(wert, forKey: schluessel)
    }

    /// **Löschen ist auch Schreiben.** Als blankes
    /// `UserDefaults.standard.removeObject(…)` lief das an dieser Schranke
    /// vorbei, und ein Prüflauf verbrauchte die Warnung des Nutzers.
    static func entfernen(_ schluessel: String) {
        guard !Ablage.istPruefstand else { return }
        UserDefaults.standard.removeObject(forKey: schluessel)
    }
}
