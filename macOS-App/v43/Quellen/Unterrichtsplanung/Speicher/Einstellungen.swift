// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Die vier Handgriffe, die der Vorrat der Lesezeichen an den Einstellungen
/// braucht — `UserDefaults` hat sie; Prüfungen bringen eine Attrappe im
/// Speicher mit, damit kein Prüflauf eine Datei unter `~/Library/Preferences`
/// hinterlässt. `Sendable`, weil der eine Speicher prozessweit gehalten wird —
/// `UserDefaults` ist threadsicher, eine Attrappe hält sich daran.
protocol Einstellungsspeicher: AnyObject, Sendable {
    func object(forKey defaultName: String) -> Any?
    func dictionary(forKey defaultName: String) -> [String: Any]?
    func string(forKey defaultName: String) -> String?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: Einstellungsspeicher {}

/// Einstellungen des Nutzers — gelesen und geschrieben nur außerhalb eines
/// Prüflaufs: Eine Prüfung darf nichts in den Einstellungen des Nutzers
/// hinterlassen und nichts von ihnen erben. Die eine Schranke dafür ist
/// `speicher`: `nil` im Prüflauf, sonst die Vorgaben des Nutzers — auch für
/// den Vorrat der Lesezeichen (`Ordnerzugriff`).
enum Einstellungen {
    static let speicher: (any Einstellungsspeicher)? = Ablage.istPruefstand ? nil : UserDefaults.standard

    /// Der Wert unter `schluessel` — `nil`, wo keiner liegt, er einen anderen
    /// Typ hat oder ein Prüflauf läuft.
    static func wert<T>(_ schluessel: String) -> T? {
        speicher?.object(forKey: schluessel) as? T
    }

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
        speicher?.set(wert, forKey: schluessel)
    }

    /// **Löschen ist auch Schreiben.** Als blankes
    /// `UserDefaults.standard.removeObject(…)` lief das an dieser Schranke
    /// vorbei, und ein Prüflauf verbrauchte die Warnung des Nutzers.
    static func entfernen(_ schluessel: String) {
        speicher?.removeObject(forKey: schluessel)
    }
}
