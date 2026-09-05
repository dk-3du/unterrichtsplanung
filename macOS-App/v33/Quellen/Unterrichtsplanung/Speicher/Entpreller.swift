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

    init() {}

    func nach(_ millisekunden: Int, _ handlung: @escaping @MainActor () -> Void) {
        auftrag?.cancel()
        self.handlung = handlung
        Entpreller.vorgemerkt[ObjectIdentifier(self)] = self
        auftrag = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(millisekunden))
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

    static func allesUebernehmen() {
        let offene = vorgemerkt.values
        vorgemerkt.removeAll()
        for entpreller in offene { entpreller.sofort() }
    }
}
