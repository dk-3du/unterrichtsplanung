// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Die Planung, fertig für die Anzeige aufbereitet — einmal je Änderung.
///
/// Das Raster fragt beim Zeichnen bis zu achtzigmal je Bild, welche Vorhaben in
/// einer Zelle stehen; über `planung.eintraege` wäre jede Frage ein Durchgang
/// durch vierhundert Einträge. Die Momentaufnahme ist unveränderlich; `stand`
/// sagt der Rasteransicht, dass sie neu einlesen muss.
@MainActor
final class Rasterdaten {

    /// Was eine Kachel zu zeigen hat — alles vorab bestimmt.
    struct Kachelstand: Equatable {
        /// Verglichen wird nur, was aus der Datei stammt — die gesetzten Texte
        /// sind Objekte und wären stets ungleich.
        static func == (a: Kachelstand, b: Kachelstand) -> Bool {
            a.vorhaben == b.vorhaben && a.hoehe == b.hoehe
                && a.kannHoch == b.kannHoch && a.kannRunter == b.kannRunter
        }

        var istPruefung: Bool { vorhaben.pruefung }

        let vorhaben: Vorhaben
        let hoehe: CGFloat
        /// Hier ausgerechnet, nicht beim Zeichnen: Der Schlüssel des Messwerks
        /// enthält den **vollständigen** Text.
        let titelhoehe: CGFloat
        let texthoehe: CGFloat
        /// Fertig gesetzt: Ein `NSAttributedString` samt Absatzvorlage bei
        /// jedem Zeichnen neu aufzubauen kostet mehr als das Zeichnen selbst.
        let gesetzterTitel: NSAttributedString
        let gesetzterText: NSAttributedString?
        /// Der Prüfungshinweis über dem Titel — `nil`, wenn keine Prüfung.
        let gesetztePruefung: NSAttributedString?
        /// Das Datum über dem Titel — `nil`, wenn keines gesetzt ist.
        let gesetztesDatum: NSAttributedString?
        /// Die Stelle in der Liste dieser Zelle.
        let kannHoch: Bool
        let kannRunter: Bool
    }

    /// Eine Kurszeile.
    struct Zeilenstand {
        let klasse: Klasse
        let ton: Farbton
        let hoehe: CGFloat
        /// Oberkante der Zeile im Rollinhalt.
        let oben: CGFloat
        /// Woche → die Kacheln dieser Zelle, in der Reihenfolge der Datei.
        let kacheln: [Int: [Kachelstand]]
        /// Wochen, die nur für diesen Kurs unterrichtsfrei sind.
        let einzelfrei: Set<Int>
    }

    let stand: Int
    let spaltenbreite: CGFloat
    /// Wochenliste, Ferienlagen und Schulwochen — als ein Wert, damit die
    /// stellengleichen Listen nicht aus verschiedenen Quellen stammen können.
    let wochenstand: Wochenstand
    var wochen: [Woche] { wochenstand.wochen }
    /// Nur für die eigenen Nachschlagehilfen (`frei`, `lage`) — von außen
    /// führt der Weg über `lage(_:)` mit seinem Außerhalb-Rückfall.
    private var lagen: [Wochenlage] { wochenstand.lagen }
    let zeilen: [Zeilenstand]
    let gesamtbreite: CGFloat
    let gesamthoehe: CGFloat
    /// Vorhabenkennung → wo sie steht.
    private let ortNachVorhaben: [String: (zeile: Int, woche: Int)]

    // ── Vorrat ────────────────────────────────────────────────────────────

    private static var vorrat: Rasterdaten?

    /// Der Ansichtskörper des Rasters läuft auch dann, wenn nur die
    /// Hauptansicht neu ausgewertet wurde (Suchfeld, Fenstertitel, offenes
    /// Blatt) — ohne diesen Vorrat würde dabei alles neu vermessen.
    static func bereitstellen(_ planung: Planung, stand: Int, breite: CGFloat) -> Rasterdaten {
        if let vorrat, vorrat.stand == stand, vorrat.spaltenbreite == breite { return vorrat }
        let neu = Rasterdaten(planung, stand: stand, breite: breite, vorher: vorrat)
        vorrat = neu
        return neu
    }

    init(_ planung: Planung, stand: Int, breite: CGFloat, vorher: Rasterdaten? = nil) {
        self.stand = stand
        self.spaltenbreite = breite

        let wochen = planung.wochenListe
        self.wochenstand = planung.wochenstand(wochen)

        var nachKurs: [String: [Int: [Vorhaben]]] = [:]
        for eintrag in planung.eintraege {
            nachKurs[eintrag.klasseId, default: [:]][eintrag.woche, default: []].append(eintrag)
        }
        var freiNachKurs: [String: Set<Tag>] = [:]
        for zelle in planung.zellenfrei {
            freiNachKurs[zelle.klasseId, default: []].insert(zelle.woche)
        }
        // Schlüssel in der Datei ist das Datum des Montags, nicht die Wochennummer.
        var nummerNachMontag: [Tag: Int] = [:]
        for woche in wochen { nummerNachMontag[woche.montag] = woche.nummer }

        // Übernahme statt Neuvermessung: alles neu zu setzen kostete 22 ms je Handgriff.
        var altbestand: [String: Kachelstand] = [:]
        if let vorher, vorher.spaltenbreite == breite {
            altbestand.reserveCapacity(vorher.ortNachVorhaben.count)
            for zeile in vorher.zeilen {
                for staende in zeile.kacheln.values {
                    for stand in staende { altbestand[stand.vorhaben.id] = stand }
                }
            }
        }

        var zeilen: [Zeilenstand] = []
        var ortNachVorhaben: [String: (zeile: Int, woche: Int)] = [:]
        var oben: CGFloat = 0

        for (stelle, klasse) in planung.klassen.enumerated() {
            let eigene = nachKurs[klasse.id] ?? [:]
            var kacheln: [Int: [Kachelstand]] = [:]
            kacheln.reserveCapacity(eigene.count)
            var hoechste = max(Masse.zelleMinHoehe, Zellenmass.kopfhoehe(klasse))

            for (woche, eintraege) in eigene {
                var stand: [Kachelstand] = []
                stand.reserveCapacity(eintraege.count)
                let innen = breite - Zellenmass.polsterZelle * 2
                    - Zellenmass.kachelLinks - Zellenmass.kachelRechts
                for (i, vorhaben) in eintraege.enumerated() {
                    ortNachVorhaben[vorhaben.id] = (stelle, woche)
                    if let alt = altbestand[vorhaben.id], alt.vorhaben == vorhaben {
                        stand.append(alt.kannHoch == (i > 0)
                                     && alt.kannRunter == (i < eintraege.count - 1)
                                     ? alt
                                     : Kachelstand(vorhaben: alt.vorhaben, hoehe: alt.hoehe,
                                                   titelhoehe: alt.titelhoehe,
                                                   texthoehe: alt.texthoehe,
                                                   gesetzterTitel: alt.gesetzterTitel,
                                                   gesetzterText: alt.gesetzterText,
                                                   gesetztePruefung: alt.gesetztePruefung,
                                                   gesetztesDatum: alt.gesetztesDatum,
                                                   kannHoch: i > 0,
                                                   kannRunter: i < eintraege.count - 1))
                        continue
                    }
                    let titelhoehe = max(Zellenmass.hoeheHaken, Zellenmass.hoeheVonText(
                        vorhaben.anzeigeTitel, stil: .callout, gewicht: .medium,
                        breite: max(20, innen - Zellenmass.breiteHaken),
                        hoechstens: Zellenmass.zeilenGrenzeTitel))
                    let texthoehe = vorhaben.text.isEmpty ? 0 : Zellenmass.hoeheVonText(
                        vorhaben.text, stil: .caption1, gewicht: .regular,
                        breite: max(20, innen), hoechstens: 3)
                    stand.append(Kachelstand(
                        vorhaben: vorhaben,
                        hoehe: Zellenmass.kachelhoehe(vorhaben, breite: breite),
                        titelhoehe: titelhoehe, texthoehe: texthoehe,
                        gesetzterTitel: Textsatz.setzen(
                            vorhaben.anzeigeTitel, stil: .callout, gewicht: .medium,
                            farbe: Rasterfarben.schrift, durchgestrichen: vorhaben.erledigt),
                        gesetzterText: vorhaben.text.isEmpty ? nil : Textsatz.setzen(
                            vorhaben.text, stil: .caption1, gewicht: .regular,
                            farbe: Rasterfarben.schriftZweit, durchgestrichen: false),
                        gesetztePruefung: vorhaben.pruefung ? Textsatz.setzen(
                            vorhaben.pruefungstag.map { "Prüfung · " + $0.mitWochentag }
                                ?? "Prüfung · Termin offen",
                            stil: .caption2, gewicht: .semibold,
                            farbe: Rasterfarben.pruefung, durchgestrichen: false,
                            umbricht: false) : nil,
                        gesetztesDatum: vorhaben.datum.map { tag in
                            Textsatz.setzen("Datum · " + tag.mitWochentag,
                                            stil: .caption2, gewicht: .regular,
                                            farbe: Rasterfarben.schriftZweit,
                                            durchgestrichen: false, umbricht: false)
                        },
                        kannHoch: i > 0,
                        kannRunter: i < eintraege.count - 1))
                }
                kacheln[woche] = stand
                hoechste = max(hoechste, Zellenmass.zellenhoehe(hoehen: stand.map(\.hoehe)))
            }

            let freieTage = freiNachKurs[klasse.id] ?? []
            var einzelfrei = Set<Int>()
            for tag in freieTage {
                if let nummer = nummerNachMontag[tag] { einzelfrei.insert(nummer) }
            }

            zeilen.append(Zeilenstand(
                klasse: klasse, ton: Farbwelt.ton(klasse.farbe),
                hoehe: hoechste, oben: oben,
                kacheln: kacheln, einzelfrei: einzelfrei))
            oben += hoechste
        }

        self.zeilen = zeilen
        self.ortNachVorhaben = ortNachVorhaben
        self.gesamtbreite = breite * CGFloat(wochen.count)
        self.gesamthoehe = oben
    }

    // ── Nachschlagen ──────────────────────────────────────────────────────

    /// Sind die Höhen gleich, muss die Anordnung nicht verworfen werden — dann
    /// genügt es, die sichtbaren Zellen neu zu belegen.
    lazy var hoehenkennung: [CGFloat] = zeilen.map(\.hoehe)

    var zeilenzahl: Int { zeilen.count }
    var spaltenzahl: Int { wochen.count }

    func kacheln(zeile: Int, woche: Int) -> [Kachelstand] {
        guard zeilen.indices.contains(zeile) else { return [] }
        return zeilen[zeile].kacheln[woche] ?? []
    }

    func frei(zeile: Int, woche: Int) -> Bool {
        guard zeilen.indices.contains(zeile), lagen.indices.contains(woche) else { return false }
        return lagen[woche].frei || zeilen[zeile].einzelfrei.contains(woche)
    }

    func lage(_ woche: Int) -> Wochenlage {
        lagen.indices.contains(woche) ? lagen[woche] : .unterricht
    }

    func stelle(vorhaben id: String) -> (zeile: Int, woche: Int)? { ortNachVorhaben[id] }

}


// ── Textsatz ──────────────────────────────────────────────────────────────

/// Text so setzen, wie `Zellenmass` ihn gemessen hat. Entscheidend ist die
/// feste Zeilenhöhe: Nur mit derselben passt der Text in die Höhe der Zeile.
@MainActor
enum Textsatz {
    private struct Vorlage: Hashable {
        let stil: NSFont.TextStyle
        let gewicht: NSFont.Weight
        let durchgestrichen: Bool
        let umbricht: Bool
    }

    private static var merkmale: [Vorlage: [NSAttributedString.Key: Any]] = [:]

    /// `umbricht`: Messung und Zeichnung müssen denselben Umbruch verwenden.
    /// Mit `.byTruncatingTail` bricht der Text NICHT um — ein zweizeiliger Titel
    /// stand einzeilig mit Auslassungszeichen in seiner Höhe für zwei.
    static func setzen(_ text: String, stil: NSFont.TextStyle, gewicht: NSFont.Weight,
                       farbe: NSColor, durchgestrichen: Bool,
                       umbricht: Bool = true) -> NSAttributedString {
        let vorlage = Vorlage(stil: stil, gewicht: gewicht,
                              durchgestrichen: durchgestrichen, umbricht: umbricht)
        var fertig: [NSAttributedString.Key: Any]
        if let bekannt = merkmale[vorlage] {
            fertig = bekannt
        } else {
            let schrift = Zellenmass.schrift(stil, gewicht)
            let zeilenhoehe = Zellenmass.zeilenhoeheDerSchrift(schrift)
            let absatz = NSMutableParagraphStyle()
            absatz.lineBreakMode = umbricht ? .byWordWrapping : .byTruncatingTail
            absatz.minimumLineHeight = zeilenhoehe
            absatz.maximumLineHeight = zeilenhoehe
            fertig = [.font: schrift, .paragraphStyle: absatz]
            if durchgestrichen {
                fertig[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                fertig[.strikethroughColor] = Rasterfarben.schriftZweit
            }
            merkmale[vorlage] = fertig
        }
        fertig[.foregroundColor] = farbe
        return NSAttributedString(string: text, attributes: fertig)
    }
}
