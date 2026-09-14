// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Aliasdateien und die Sperre für Startbares — an einem eigenen Ordner; es
/// wird nichts geöffnet, nur geprüft.
@Suite("Systemzugriff: Aliasdateien")
@MainActor
struct SystemzugriffPruefungen {

    private let zugriff = Ordnerzugriff(ablage: .shared)

    private func ordner() throws -> URL {
        let o = URL.temporaryDirectory
            .appending(component: "zugriff-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        return o
    }

    /// Eine Aliasdatei des Finders — ein Lesezeichen in Dateiform.
    private func alias(auf ziel: URL, in ordner: URL, name: String) throws -> URL {
        let daten = try ziel.bookmarkData(options: .suitableForBookmarkFile,
                                          includingResourceValuesForKeys: nil, relativeTo: nil)
        let alias = ordner.appending(component: name)
        try URL.writeBookmarkData(daten, to: alias)
        return alias
    }

    @Test("Ein Alias wird einmal aufgelöst — geprüft wird das Ziel, nicht der Verweis")
    func aliasAufgeloest() throws {
        let o = try ordner()
        defer { try? FileManager.default.removeItem(at: o) }
        let text = o.appending(component: "Notiz.txt")
        try Data("x".utf8).write(to: text)
        let programm = o.appending(component: "Rechner.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: programm, withIntermediateDirectories: true)

        let aufText = try alias(auf: text, in: o, name: "Notiz")
        let aufProgramm = try alias(auf: programm, in: o, name: "Rechner")
        #expect(Systemzugriff.aufgeloest(aufText) == text.standardizedFileURL.resolvingSymlinksInPath())
        #expect(Systemzugriff.oeffnenErlaubt(aufText))
        #expect(Systemzugriff.oeffnenErlaubt(text))
        #expect(!Systemzugriff.oeffnenErlaubt(programm))
        #expect(!Systemzugriff.oeffnenErlaubt(aufProgramm), "ein Alias auf ein Programm bleibt gesperrt")
        guard case .abgewiesen = Systemzugriff.dateiOeffnen(aufProgramm.path, zugriff: zugriff) else {
            Issue.record("erwartet war .abgewiesen")
            return
        }
    }

    @Test("Ein unauflösbarer Alias wird abgewiesen, nicht geöffnet")
    func aliasUnaufloesbar() throws {
        let o = try ordner()
        defer { try? FileManager.default.removeItem(at: o) }
        let weg = o.appending(component: "weg.txt")
        try Data("x".utf8).write(to: weg)
        let verweis = try alias(auf: weg, in: o, name: "Verweis")
        try FileManager.default.removeItem(at: weg)
        #expect(Systemzugriff.aufgeloest(verweis) == nil)
        #expect(!Systemzugriff.oeffnenErlaubt(verweis))
        guard case .abgewiesen(let text) = Systemzugriff.dateiOeffnen(verweis.path, zugriff: zugriff) else {
            Issue.record("erwartet war .abgewiesen")
            return
        }
        #expect(text.contains("auflösen"))
        // Eine gewöhnliche Datei bleibt, was sie ist; eine fehlende wird benannt.
        #expect(Systemzugriff.aufgeloest(o) == o.standardizedFileURL.resolvingSymlinksInPath())
        guard case .fehlt = Systemzugriff.dateiOeffnen(o.appending(component: "nie.txt").path, zugriff: zugriff) else {
            Issue.record("erwartet war .fehlt")
            return
        }
    }
}
