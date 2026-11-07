// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Was ein Ziehen von außen auf eine Kachel mitbringt (v88, AZ3; E905, E913, E917): Dateien und Ordner, die es schon
/// gibt, und http(s)-Adressen. Gelesen werden nur die URL-Einträge der Zwischenablage, je Eintrag einer. Einen
/// Dateiverweis, wie ihn der Finder schreibt (`file:///.file/id=…`), löst `filePathURL` auf; ein Anhang aus Mail kommt
/// schon als Pfad. Dateiversprechen bleiben außen vor — Safari legt neben dem Link auch eines bei (gemessen am
/// 28.10.2026), das hindert den Link nicht.
enum Ziehinhalt {
    /// Die Typen, für die sich das Raster anmeldet — neben dem eigenen Verweis auf Vorhaben.
    static let typen: [NSPasteboard.PasteboardType] = [.fileURL, .URL]

    static func lesen(_ ablage: NSPasteboard) -> (dateien: [URL], links: [String]) {
        let gelesen = ablage.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] ?? []
        var dateien: [URL] = []
        var links: [String] = []
        for adresse in gelesen {
            if adresse.isFileURL {
                if let datei = adresse.filePathURL { dateien.append(datei) }
            } else if let schema = adresse.scheme?.lowercased(), schema == "http" || schema == "https",
                      let text = adresse.absoluteString {
                links.append(text)
            }
        }
        return (dateien, links)
    }
}
