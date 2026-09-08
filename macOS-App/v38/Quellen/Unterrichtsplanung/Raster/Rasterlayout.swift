// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Wo welche Zelle liegt — ausgerechnet, nicht abgelegt.
///
/// Ein `NSCollectionViewFlowLayout` hielte für 3 900 Zellen ebenso viele
/// Anordnungsobjekte vor. Hier ist die Lage Arithmetik (gleich breite Spalten,
/// Zeilenhöhen aus `Rasterdaten`), die Antwort kostet O(sichtbare Zellen).
final class Rasterlayout: NSCollectionViewLayout {

    var daten: Rasterdaten? {
        didSet { invalidateLayout() }
    }

    override var collectionViewContentSize: NSSize {
        guard let daten else { return .zero }
        return NSSize(width: daten.gesamtbreite, height: daten.gesamthoehe)
    }

    /// Ohne dieses `false` würfe AppKit bei jedem Rollbild die ganze Anordnung
    /// weg — die Größe hängt nur an `Rasterdaten`, nicht am Sichtfenster.
    override func shouldInvalidateLayout(forBoundsChange neueGrenzen: NSRect) -> Bool { false }

    override func layoutAttributesForItem(at pfad: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let daten, daten.zeilen.indices.contains(pfad.section),
              pfad.item >= 0, pfad.item < daten.spaltenzahl else { return nil }
        let zeile = daten.zeilen[pfad.section]
        let angabe = NSCollectionViewLayoutAttributes(forItemWith: pfad)
        angabe.frame = NSRect(x: CGFloat(pfad.item) * daten.spaltenbreite,
                              y: zeile.oben,
                              width: daten.spaltenbreite,
                              height: zeile.hoehe)
        return angabe
    }

    override func layoutAttributesForElements(in bereich: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard let daten, daten.spaltenbreite > 0 else { return [] }

        let ersteSpalte = max(0, Int(floor(bereich.minX / daten.spaltenbreite)))
        let letzteSpalte = min(daten.spaltenzahl - 1,
                               Int(ceil(bereich.maxX / daten.spaltenbreite)))
        guard ersteSpalte <= letzteSpalte else { return [] }

        var angaben: [NSCollectionViewLayoutAttributes] = []
        angaben.reserveCapacity((letzteSpalte - ersteSpalte + 1) * 4)

        for (stelle, zeile) in daten.zeilen.enumerated() {
            // Die Zeilen liegen der Reihe nach, also darf abgebrochen werden.
            if zeile.oben + zeile.hoehe <= bereich.minY { continue }
            if zeile.oben >= bereich.maxY { break }
            for spalte in ersteSpalte...letzteSpalte {
                let angabe = NSCollectionViewLayoutAttributes(
                    forItemWith: IndexPath(item: spalte, section: stelle))
                angabe.frame = NSRect(x: CGFloat(spalte) * daten.spaltenbreite,
                                      y: zeile.oben,
                                      width: daten.spaltenbreite,
                                      height: zeile.hoehe)
                angaben.append(angabe)
            }
        }
        return angaben
    }
}
