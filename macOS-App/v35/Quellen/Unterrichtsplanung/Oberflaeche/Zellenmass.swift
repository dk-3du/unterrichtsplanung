// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Wie hoch eine Zeile des Rasters wird — ausgerechnet, nicht ausgemessen.
///
/// Das Raster kann nur dann spaltenweise nachladen, wenn die Zeilenhöhe schon
/// feststeht, bevor die Zellen gebaut sind: Käme sie aus dem Layout, zuckte die
/// Zeile beim Rollen.
@MainActor
enum Zellenmass {

    private static let zellenpolster: CGFloat = 8      // ringsum
    private static let kachelabstand: CGFloat = 6      // zwischen Kacheln
    private static let fusshoehe: CGFloat = 20

    private static let kachelPolsterOben: CGFloat = 8
    private static let kachelPolsterLinks: CGFloat = 11
    private static let kachelPolsterRechts: CGFloat = 8
    private static let hakenbreite: CGFloat = 26       // Knopf samt Abstand
    private static let hakenhoehe: CGFloat = 15        // Knopf, mindestens so hoch
    private static let verweiszeile: CGFloat = 19.5    // eine Material- oder Linkzeile
    private static let verweisabstand: CGFloat = 3     // zwischen ihnen
    private static let mehrzeile: CGFloat = 13         // „+ n weitere“
    private static let pruefungszeile: CGFloat = 17    // Termin über dem Titel
    private static let pruefungsabstand: CGFloat = 4
    private static let datumszeile: CGFloat = 15       // Datum über dem Titel
    private static let datumsabstand: CGFloat = 3
    /// Notbremse gegen versehentlich riesige Eingaben.
    private static let titelZeilen = 20

    private static let kopfPolsterOben: CGFloat = 12
    private static let kopfPolsterSeite: CGFloat = 14
    private static let stiftbreite: CGFloat = 26
    private static let verwaltungszeile: CGFloat = 21

    static func kopfhoehe(_ klasse: Klasse) -> CGFloat {
        let innen = Masse.spalteKlasse - kopfPolsterSeite * 2 - stiftbreite
        var hoehe = kopfPolsterOben * 2
        hoehe += texthoehe(klasse.name.isEmpty ? "Ohne Bezeichnung" : klasse.name,
                           stil: .headline, gewicht: .semibold,
                           breite: max(20, innen), hoechstens: 3)
        if !klasse.fach.isEmpty {
            hoehe += 1 + texthoehe(klasse.fach, stil: .subheadline, gewicht: .regular,
                                   breite: max(20, innen), hoechstens: 2)
        }
        if !klasse.notiz.isEmpty {
            hoehe += 1 + texthoehe(klasse.notiz, stil: .caption1, gewicht: .regular,
                                   breite: max(20, innen), hoechstens: 2)
        }
        for art in Kursdateiart.allCases where klasse.hat(art) {
            hoehe += 1 + verwaltungszeile
        }
        return hoehe
    }

    /// Nimmt fertige Kachelhöhen entgegen: `Rasterdaten` bestimmt sie ohnehin
    /// einzeln.
    static func zellenhoehe(hoehen: [CGFloat]) -> CGFloat {
        guard !hoehen.isEmpty else { return Masse.zelleMinHoehe }
        let kacheln = hoehen.reduce(CGFloat(0), +)
        // n Kacheln, ein Abstandhalter und der Fuß — also n+1 Zwischenräume.
        let abstaende = kachelabstand * CGFloat(hoehen.count + 1)
        return max(Masse.zelleMinHoehe,
                   zellenpolster * 2 + kacheln + abstaende + fusshoehe)
    }

    // ── Maße, die auch die Zellenansicht braucht ──────────────────────────

    static var polsterZelle: CGFloat { zellenpolster }
    static var abstandKacheln: CGFloat { kachelabstand }
    static var hoeheFuss: CGFloat { fusshoehe }
    static var kachelOben: CGFloat { kachelPolsterOben }
    static var kachelLinks: CGFloat { kachelPolsterLinks }
    static var kachelRechts: CGFloat { kachelPolsterRechts }
    static var breiteHaken: CGFloat { hakenbreite }
    static var hoeheHaken: CGFloat { hakenhoehe }
    static var hoeheVerweiszeile: CGFloat { verweiszeile }
    static var abstandVerweise: CGFloat { verweisabstand }
    static var hoeheMehrzeile: CGFloat { mehrzeile }
    static var zeilenGrenzeTitel: Int { titelZeilen }
    static var hoehePruefungszeile: CGFloat { pruefungszeile }
    static var abstandPruefung: CGFloat { pruefungsabstand }
    static var hoeheDatumszeile: CGFloat { datumszeile }
    static var abstandDatum: CGFloat { datumsabstand }

    static func hoeheVonText(_ text: String, stil: NSFont.TextStyle,
                             gewicht: NSFont.Weight, breite: CGFloat,
                             hoechstens: Int) -> CGFloat {
        texthoehe(text, stil: stil, gewicht: gewicht, breite: breite, hoechstens: hoechstens)
    }

    /// Die Schrift, mit der gemessen wurde — die Ansicht braucht dieselbe.
    static func schrift(_ stil: NSFont.TextStyle, _ gewicht: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: stil).pointSize,
                          weight: gewicht)
    }

    /// Zeilenhöhe, mit der die Ansicht zeichnen muss, damit Messung und
    /// Darstellung übereinstimmen (siehe `texthoehe`).
    static func zeilenhoeheDerSchrift(_ schrift: NSFont) -> CGFloat {
        (Formatvorrat.zeilenhoehe(schrift) + 1).rounded(.up)
    }

    static func kachelhoehe(_ vorhaben: Vorhaben, breite: CGFloat) -> CGFloat {
        let innen = breite - zellenpolster * 2 - kachelPolsterLinks - kachelPolsterRechts
        var hoehe = kachelPolsterOben * 2

        if vorhaben.pruefung { hoehe += pruefungszeile + pruefungsabstand }
        if vorhaben.datum != nil { hoehe += datumszeile + datumsabstand }

        hoehe += max(hakenhoehe,
                     texthoehe(vorhaben.anzeigeTitel, stil: .callout, gewicht: .medium,
                               breite: max(20, innen - hakenbreite), hoechstens: titelZeilen))

        if !vorhaben.text.isEmpty {
            hoehe += 2 + texthoehe(vorhaben.text, stil: .caption1, gewicht: .regular,
                                   breite: max(20, innen), hoechstens: 3)
        }
        hoehe += verweisblock(vorhaben.materialien.count)
        hoehe += verweisblock(vorhaben.links.count)
        return hoehe
    }

    /// Material- oder Linkliste: höchstens drei Zeilen, dann ein Hinweis auf
    /// den Rest.
    private static func verweisblock(_ anzahl: Int) -> CGFloat {
        guard anzahl > 0 else { return 0 }
        let gezeigt = CGFloat(min(3, anzahl))
        var hoehe = kachelabstand + gezeigt * verweiszeile + (gezeigt - 1) * verweisabstand
        if anzahl > 3 { hoehe += verweisabstand + mehrzeile }
        return hoehe
    }

    // ── Textmaß ───────────────────────────────────────────────────────────

    private struct Schluessel: Hashable {
        let text: String
        let stil: NSFont.TextStyle
        let gewicht: NSFont.Weight
        let breite: CGFloat
        let hoechstens: Int
    }

    /// Der Schlüssel enthält den vollständigen Text; an der Grenze wird
    /// vollständig geleert statt einzeln verdrängt.
    private static var gemessen: [Schluessel: CGFloat] = [:]
    /// 75 Klassen/Kurse × 52 Wochen ergäben im dichtesten Fall gut 8 000 Texte.
    private static let hoechstensGemerkt = 20000

    private static func texthoehe(_ text: String, stil: NSFont.TextStyle,
                                  gewicht: NSFont.Weight, breite: CGFloat,
                                  hoechstens: Int) -> CGFloat {
        let schluessel = Schluessel(text: text, stil: stil, gewicht: gewicht,
                                    breite: breite.rounded(), hoechstens: hoechstens)
        if let bekannt = gemessen[schluessel] { return bekannt }

        let schrift = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: stil).pointSize,
                                        weight: gewicht)
        // Gezählt mit AppKits Maß, bemessen mit SwiftUIs: dessen Zeilenhöhe liegt
        // bis zu einen Punkt über `defaultLineHeight`.
        let appkitZeile = Formatvorrat.zeilenhoehe(schrift)
        let swiftZeile = (appkitZeile + 1).rounded(.up)
        let umbrochen = hoehe(von: text, schrift: schrift, breite: breite)

        // Runden, nicht aufrunden: der Kasten liegt oft Bruchteile über einem Vielfachen.
        let zeilen = max(1, min(hoechstens, Int((umbrochen / appkitZeile).rounded())))
        let ergebnis = CGFloat(zeilen) * swiftZeile
        if gemessen.count >= hoechstensGemerkt { gemessen.removeAll(keepingCapacity: true) }
        gemessen[schluessel] = ergebnis
        return ergebnis
    }

    private static func hoehe(von text: String, schrift: NSFont, breite: CGFloat) -> CGFloat {
        let absatz = NSMutableParagraphStyle()
        absatz.lineBreakMode = .byWordWrapping
        return (text as NSString).boundingRect(
            with: NSSize(width: breite, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: schrift, .paragraphStyle: absatz]).height
    }
}

@MainActor
private enum Formatvorrat {
    private static let setzer = NSLayoutManager()
    static func zeilenhoehe(_ schrift: NSFont) -> CGFloat {
        setzer.defaultLineHeight(for: schrift)
    }
}
