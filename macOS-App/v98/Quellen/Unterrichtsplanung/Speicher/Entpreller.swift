// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Verzögert eine Handlung, bis eine Weile nichts mehr passiert ist.
///
/// Offene Handlungen sind in `vorgemerkt` gesammelt und werden vor dem Sichern
/// abgearbeitet — sonst ginge das zuletzt Getippte beim Beenden verloren.
@MainActor
final class Entpreller {
    private static var vorgemerkt: [ObjectIdentifier: Entpreller] = [:]

    private var auftrag: Task<Void, Never>?
    private var handlung: (@MainActor () -> Void)?

    /// Der Takt (AT6f-1, E548): der des Speichers für den Titel, sonst der Systemtakt.
    var takt: any Taktgeber

    init(takt: any Taktgeber = Systemtakt.gemeinsam) {
        self.takt = takt
    }

    func nach(_ millisekunden: Int, _ handlung: @escaping @MainActor () -> Void) {
        auftrag?.cancel()
        self.handlung = handlung
        Entpreller.vorgemerkt[ObjectIdentifier(self)] = self
        auftrag = takt.aufgabe(nach: .milliseconds(millisekunden)) { [weak self] in
            guard !Task.isCancelled else { return }
            self?.sofort()
        }
    }

    func sofort() {
        auftrag?.cancel()
        auftrag = nil
        let offen = handlung
        handlung = nil
        Entpreller.vorgemerkt.removeValue(forKey: ObjectIdentifier(self))
        offen?()
    }

    func abbrechen() {
        auftrag?.cancel()
        auftrag = nil
        handlung = nil
        Entpreller.vorgemerkt.removeValue(forKey: ObjectIdentifier(self))
    }

    /// Alles Offene **verwerfen** — für die Rücknahme: Ein entprellter
    /// Schreibvorgang trägt den Text von vor dem Widerrufen; ließe man ihn
    /// landen, schriebe er die Rücknahme zurück und räumte den Weg nach vorn
    /// (am gebauten Paket gemessen, S7-R3).
    static func allesAbbrechen() {
        let offene = vorgemerkt.values
        vorgemerkt.removeAll()
        for entpreller in offene { entpreller.abbrechen() }
    }

    static func allesUebernehmen() {
        let offene = vorgemerkt.values
        vorgemerkt.removeAll()
        for entpreller in offene { entpreller.sofort() }
    }
}
