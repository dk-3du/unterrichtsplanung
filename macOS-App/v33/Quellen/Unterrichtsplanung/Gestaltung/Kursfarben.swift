// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

enum Kursfarben {

    /// Fertig abgelegt: Zwei frisch erzeugte dynamische Farben gelten für
    /// SwiftUI als verschieden und lösen Neuzeichnen aus.
    private static let vorrat: [Farbstufen] = Farbwelt.toene.map(Farbstufen.init)

    private struct Farbstufen {
        let voll: Color
        let zeile: Color
        let flaeche: Color
        /// `NSColor` fürs Raster, `Color` für Dialoge und Kopfleiste — beide aus
        /// **derselben** dynamischen Farbe, sonst laufen sie auseinander.
        let vollNS: NSColor
        let zeileNS: NSColor
        let flaecheNS: NSColor

        init(_ ton: Farbton) {
            let grund = NSColor(name: nil) { erscheinung in
                let dunkel = erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return dunkel
                    ? NSColor(hsl: ton.h,
                              s: Farbwelt.saettigungDunkel + ton.ds,
                              l: Farbwelt.helligkeitDunkel + ton.dl)
                    : NSColor(hsl: ton.h,
                              s: Farbwelt.saettigungHell + ton.ds,
                              l: Farbwelt.helligkeitHell + ton.dl)
            }
            vollNS = grund
            zeileNS = grund.withAlphaComponent(0.08)
            flaecheNS = grund.withAlphaComponent(0.16)
            voll = Color(nsColor: grund)
            zeile = voll.opacity(0.08)
            flaeche = voll.opacity(0.16)
        }
    }

    private static func stufen(_ ton: Farbton) -> Farbstufen {
        vorrat.indices.contains(ton.stelle) ? vorrat[ton.stelle] : vorrat[0]
    }

    static func farbe(_ ton: Farbton) -> Color { stufen(ton).voll }
    static func zeile(_ ton: Farbton) -> Color { stufen(ton).zeile }
    static func flaeche(_ ton: Farbton) -> Color { stufen(ton).flaeche }

    // ── Dieselben Farben für AppKit ───────────────────────────────────────

    static func nsFarbe(_ ton: Farbton) -> NSColor { stufen(ton).vollNS }
    static func nsZeile(_ ton: Farbton) -> NSColor { stufen(ton).zeileNS }
    static func nsFlaeche(_ ton: Farbton) -> NSColor { stufen(ton).flaecheNS }
}

enum Rasterfarben {

    /// Abschwächen **multiplizierend** wie SwiftUIs `.opacity(_:)`, nicht
    /// ersetzend wie `withAlphaComponent(_:)` — alle `…LabelColor` sind bereits
    /// durchsichtig.
    private static func abgeschwaecht(_ farbe: NSColor, _ faktor: CGFloat) -> NSColor {
        NSColor(name: nil) { _ in
            guard let grund = farbe.usingColorSpace(.sRGB) else { return farbe }
            return grund.withAlphaComponent(grund.alphaComponent * faktor)
        }
    }

    static let trennlinie = NSColor.separatorColor
    static let fensterflaeche = NSColor.windowBackgroundColor
    static let freieZelle = abgeschwaecht(.quaternaryLabelColor, 0.22)
    static let verweiszeile = abgeschwaecht(.quaternaryLabelColor, 0.14)
    static let schraffur = abgeschwaecht(.secondaryLabelColor, 0.5)
    static let schraffurLeicht = abgeschwaecht(.secondaryLabelColor, 0.25)
    static let schrift = NSColor.labelColor
    static let schriftZweit = NSColor.secondaryLabelColor
    static let schriftDritt = NSColor.tertiaryLabelColor
    static let erledigt = NSColor.systemGreen
    static let pruefung = NSColor.systemRed
    static let pruefungflaeche = abgeschwaecht(.systemRed, 0.14)

    /// `NSColor.systemYellow` käme auf hellem Grund auf einen Kontrast von 1,4
    /// zu Weiß. Dieses abgedunkelte Gelb liegt bei 4,5 — wie das Rot der
    /// Prüfungen (5,5).
    private static func dringlich(_ deckkraft: CGFloat) -> NSColor {
        NSColor(name: nil) { erscheinung in
            let dunkel = erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hsl: dunkel ? 46 : 40, s: dunkel ? 92 : 96, l: dunkel ? 60 : 32)
                .withAlphaComponent(deckkraft)
        }
    }

    static let dringend = dringlich(0.8)
    static let dringendStark = dringlich(1)
}

private extension NSColor {
    /// CSS-`hsl()`: Farbton in Grad, Sättigung und Helligkeit in Prozent.
    convenience init(hsl h: Double, s: Double, l: Double) {
        let saettigung = min(100, max(0, s)) / 100
        let helligkeit = min(100, max(0, l)) / 100
        let c = (1 - abs(2 * helligkeit - 1)) * saettigung
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let m = helligkeit - c / 2

        let (r, g, b): (Double, Double, Double) = switch hh {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        self.init(srgbRed: r + m, green: g + m, blue: b + m, alpha: 1)
    }
}

enum Masse {
    static let spalteKlasse: CGFloat = 232
    static let wochenkopfHoehe: CGFloat = 62
    static let zelleMinHoehe: CGFloat = 84
    static let kachelradius: CGFloat = 10
}

/// Einmal angelegt: `Color(nsColor:)` überbrückt bei jedem Aufruf zwischen
/// AppKit und SwiftUI — im Raster bis zu 1500-mal je Durchgang.
enum Systemfarben {
    static let trennlinie = Color(nsColor: .separatorColor)
    static let fensterflaeche = Color(nsColor: .windowBackgroundColor)
    static let verweiszeile = Color(nsColor: .quaternaryLabelColor).opacity(0.14)
    static let verweiszeileAktiv = Color(nsColor: .quaternaryLabelColor).opacity(0.3)
    static let feldflaeche = Color(nsColor: .textBackgroundColor)
    static let feldkante = Color(nsColor: .separatorColor)
    static let pruefung = Color(nsColor: .systemRed)
    static let dringend = Color(nsColor: Rasterfarben.dringendStark)
}
