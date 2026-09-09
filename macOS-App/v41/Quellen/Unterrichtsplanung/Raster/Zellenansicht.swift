// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Eine Zelle des Rasters: ein Kurs in einer Woche.
///
/// Hintergrund, Schraffur, Trennlinien und Rahmen werden **gezeichnet**, nicht
/// aus Ansichten zusammengesetzt — in SwiftUI waren das über zweihundert
/// zusätzliche Knoten für ein paar Striche.
final class Zellenkoerper: NSView {

    struct Griffe {
        var zelleAnwaehlen: (Int, Int) -> Void = { _, _ in }
        var vorhabenAnlegen: (Int, Int) -> Void = { _, _ in }
        var freiUmschalten: (Int, Int) -> Void = { _, _ in }
        var zellenmenue: (Int, Int) -> NSMenu? = { _, _ in nil }
        var kachel = Kachelansicht.Griffe()
    }

    private(set) var zeile = -1
    private(set) var woche = -1
    private var daten: Rasterdaten?
    private var griffe = Griffe()
    private var angewaehlt = false
    private var zielt = false
    /// Vor welcher Kachel der Einfügestrich steht — `nil`, wenn keiner.
    private var marke: Int?

    private(set) var ueberfahren = false
    /// Von der Tour gehalten: Beide Knöpfe bleiben sichtbar, wo auch immer der
    /// Zeiger steht. Fällt beim Neubelegen mit einer anderen Zelle weg.
    private var hervorgehoben = false

    func hervorheben(_ neu: Bool) {
        guard neu != hervorgehoben else { return }
        hervorgehoben = neu
        nachfuehren()
    }

    /// Wo die Karte der Tour anzusetzen hat.
    var anlegenknopfRahmen: NSRect { anlegenknopf.frame }
    var freiknopfRahmen: NSRect { freiknopf.frame }

    /// Wird vom Sammelblatt gesetzt, nicht von einem eigenen
    /// Verfolgungsbereich (siehe `Rastersammelblatt`).
    func ueberfahrenSetzen(_ neu: Bool) {
        guard neu != ueberfahren else { return }
        ueberfahren = neu
        nachfuehren()
    }

    private let anlegenknopf = NSButton()
    private let freiknopf = NSButton()
    private var kacheln: [Kachelansicht] = []
    /// Wonach zuletzt gezeichnet wurde — der Vergleich, der die Arbeit spart.
    private var gezeigt: [Rasterdaten.Kachelstand] = []
    private var gezeigtFrei: Bool?
    private var gezeigtLage: Wochenlage?
    /// Farbe, Kursname und Kalenderwoche gehören in den Vergleich — ohne sie
    /// blieb eine wiederverwendete Zelle nach einem Farbwechsel im alten Ton.
    private var gezeigtTon: Farbton?
    private var gezeigtKurs: String?
    private var gezeigtKW: Int?
    /// Gefiltert wird an der ANZEIGE, nicht an den Daten — die Zeilenhöhen
    /// bleiben, wie sie sind.
    private var treffer: Set<String>?

    override var isFlipped: Bool { true }

    /// Erspart dem System, den Untergrund mitzuzeichnen. **Nicht** der Grund
    /// für ruhiges Rollen — `copiesOnScroll` ist seit macOS 11 wirkungslos.
    override var isOpaque: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Kein `wantsLayer`: eigener Bildspeicher je Ansicht — 271 MB und 13,5 ms je Rollbild.

        anlegenknopf.isBordered = false
        anlegenknopf.imagePosition = .imageLeading
        anlegenknopf.image = Symbolvorrat.bild(Zeichen.plus)
        anlegenknopf.attributedTitle = NSAttributedString(
            string: " Vorhaben",
            attributes: [.font: Zellenmass.schrift(.caption1, .regular),
                         .foregroundColor: Rasterfarben.schriftZweit])
        anlegenknopf.contentTintColor = Rasterfarben.schriftZweit
        anlegenknopf.target = self
        anlegenknopf.action = #selector(anlegenGedrueckt)
        anlegenknopf.isHidden = true
        addSubview(anlegenknopf)

        freiknopf.isBordered = false
        freiknopf.imagePosition = .imageOnly
        // Das Zeichen wechselt nie; in `nachfuehren()` bleibt allein die Färbung.
        freiknopf.image = Symbolvorrat.bild(Zeichen.ferien)
        freiknopf.target = self
        freiknopf.action = #selector(freiGedrueckt)
        freiknopf.isHidden = true
        addSubview(freiknopf)

        // Selbstgezeichnete Ansichten sind für VoiceOver erst mit beidem da;
        // ein Etikett allein bleibt unerreichbar.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht aus einer Datei geladen") }

    // ── Belegen ───────────────────────────────────────────────────────────

    func setzen(daten neueDaten: Rasterdaten, zeile neueZeile: Int, woche neueWoche: Int,
                angewaehlt neuAngewaehlt: Bool, auswahl: Set<String>,
                treffer neueTreffer: Set<String>?, griffe neueGriffe: Griffe) {
        let neueStaende = neueDaten.kacheln(zeile: neueZeile, woche: neueWoche)
        let neuFrei = neueDaten.frei(zeile: neueZeile, woche: neueWoche)
        let neueLage = neueDaten.lage(neueWoche)
        let neueZeilendaten = neueDaten.zeilen[safe: neueZeile]
        let neuerTon = neueZeilendaten?.ton
        let neuerKurs = neueZeilendaten?.klasse.name
        let neueKW = neueDaten.wochen[safe: neueWoche]?.kw
        if hervorgehoben, zeile != neueZeile || woche != neueWoche { hervorgehoben = false }
        let unveraendert = zeile == neueZeile && woche == neueWoche
            && gezeigt == neueStaende && gezeigtFrei == neuFrei && gezeigtLage == neueLage
            && treffer == neueTreffer && gezeigtTon == neuerTon
            && gezeigtKurs == neuerKurs && gezeigtKW == neueKW
        daten = neueDaten
        zeile = neueZeile
        woche = neueWoche
        griffe = neueGriffe
        if unveraendert {
            auswahlSetzen(auswahl, zelleAngewaehlt: neuAngewaehlt)
            return
        }
        gezeigt = neueStaende
        gezeigtFrei = neuFrei
        gezeigtLage = neueLage
        treffer = neueTreffer
        gezeigtTon = neuerTon
        gezeigtKurs = neuerKurs
        gezeigtKW = neueKW
        angewaehlt = neuAngewaehlt
        Messzaehler.messen("kacheln") { kachelnAufbauen(auswahl: auswahl) }
        nachfuehren()
        needsDisplay = true
        needsLayout = true
    }

    func auswahlSetzen(_ auswahl: Set<String>, zelleAngewaehlt: Bool) {
        if zelleAngewaehlt != angewaehlt {
            angewaehlt = zelleAngewaehlt
            needsDisplay = true
        }
        for kachel in kacheln {
            guard let id = kachel.stand?.vorhaben.id else { continue }
            kachel.auswahlSetzen(auswahl.contains(id))
        }
    }

    func zielSetzen(_ neu: Bool, marke neueMarke: Int? = nil) {
        guard neu != zielt || marke != neueMarke else { return }
        zielt = neu
        marke = neu ? neueMarke : nil
        needsDisplay = true
    }

    /// Wo eine fallengelassene Kachel landen würde: die Stelle für den Strich
    /// und das Vorhaben, VOR dem eingesetzt wird — `nil` heißt: ans Ende.
    ///
    /// Gefragt wird nach der Kennung statt nach der Stelle, weil bei laufender
    /// Suche nicht alle Vorhaben der Zelle als Kachel dastehen.
    func einfuegestelle(bei punkt: NSPoint) -> (stelle: Int, vorId: String?) {
        for (stelle, kachel) in kacheln.enumerated() where punkt.y < kachel.frame.midY {
            return (stelle, kachel.stand?.vorhaben.id)
        }
        return (kacheln.count, nil)
    }

    private func kachelnAufbauen(auswahl: Set<String>) {
        // `visibleItems()` liefert auch Elemente zu Zeilen, die es nicht mehr gibt.
        guard let daten, let zeilendaten = daten.zeilen[safe: zeile] else { return }
        var staende = daten.kacheln(zeile: zeile, woche: woche)
        if let treffer { staende = staende.filter { treffer.contains($0.vorhaben.id) } }
        while kacheln.count > staende.count { kacheln.removeLast().removeFromSuperview() }
        while kacheln.count < staende.count {
            let neue = Kachelansicht(frame: .zero)
            addSubview(neue)
            kacheln.append(neue)
        }
        let ton = zeilendaten.ton
        for (stelle, stand) in staende.enumerated() {
            kacheln[stelle].setzen(stand, ton: ton,
                                   angewaehlt: auswahl.contains(stand.vorhaben.id),
                                   griffe: griffe.kachel)
        }
    }

    private func nachfuehren() {
        guard let daten, daten.zeilen.indices.contains(zeile) else { return }
        let lage = daten.lage(woche)
        let einzelFrei = daten.zeilen[zeile].einzelfrei.contains(woche)

        let gezeigtWerden = ueberfahren || hervorgehoben
        anlegenknopf.isHidden = !gezeigtWerden
        freiknopf.isHidden = lage.frei || !(gezeigtWerden || einzelFrei)
        freiknopf.contentTintColor = einzelFrei ? NSColor.controlAccentColor : Rasterfarben.schriftZweit

        let name = daten.zeilen[zeile].klasse.name
        let kw = daten.wochen[safe: woche]?.kw ?? 0
        freiknopf.toolTip = einzelFrei
            ? "\(name) hat in KW \(kw) keinen Unterricht — Klick nimmt das zurück"
            : "Nur für \(name) als unterrichtsfrei kennzeichnen"
        freiknopf.setAccessibilityLabel(einzelFrei
            ? "\(name), KW \(kw) wieder als Unterricht führen"
            : "\(name), KW \(kw) als unterrichtsfrei kennzeichnen")
        anlegenknopf.setAccessibilityLabel("Vorhaben in \(name), KW \(kw) anlegen")
        setAccessibilityLabel("\(name), KW \(kw)")
    }

    // ── Anordnen ──────────────────────────────────────────────────────────

    override func layout() {
        Messzaehler.messen("Zelle.layout") { super.layout() }
        let polster = Zellenmass.polsterZelle
        let breite = max(0, bounds.width - polster * 2)
        var y = polster
        for kachel in kacheln {
            let hoehe = kachel.stand?.hoehe ?? 0
            kachel.frame = NSRect(x: polster, y: y, width: breite, height: hoehe)
            y += hoehe + Zellenmass.abstandKacheln
        }

        let fussY = bounds.height - polster - Zellenmass.hoeheFuss
        anlegenknopf.frame = NSRect(x: polster, y: fussY, width: 92, height: Zellenmass.hoeheFuss)
        freiknopf.frame = NSRect(x: bounds.width - polster - 20, y: fussY,
                                 width: 20, height: Zellenmass.hoeheFuss)
    }

    // ── Zeichnen ──────────────────────────────────────────────────────────

    override func draw(_ schmutzig: NSRect) {
        Messzaehler.messen("Zelle.draw") { zeichnen() }
    }

    private func zeichnen() {
        guard let daten, daten.zeilen.indices.contains(zeile) else { return }
        let lage = daten.lage(woche)
        let frei = daten.frei(zeile: zeile, woche: woche)

        // Beide Farben sind durchscheinend gedacht: erst deckende Fensterfläche, dann Tönung.
        Rasterfarben.fensterflaeche.setFill()
        bounds.fill()
        (frei ? Rasterfarben.freieZelle : Kursfarben.nsZeile(daten.zeilen[zeile].ton)).setFill()
        bounds.fill(using: .sourceOver)

        if frei || lage.teilweise {
            schraffieren(frei ? Rasterfarben.schraffur : Rasterfarben.schraffurLeicht)
        }

        Rasterfarben.trennlinie.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        if angewaehlt {
            NSColor.controlAccentColor.setStroke()
            let rahmen = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                      xRadius: 4, yRadius: 4)
            rahmen.lineWidth = 2
            rahmen.stroke()
        }
        if zielt {
            NSColor.controlAccentColor.setStroke()
            let rahmen = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3),
                                      xRadius: 6, yRadius: 6)
            rahmen.lineWidth = 2
            rahmen.stroke()
            if let marke { einfuegestrichZeichnen(marke) }
        }
    }

    private func einfuegestrichZeichnen(_ stelle: Int) {
        let polster = Zellenmass.polsterZelle
        let halb = Zellenmass.abstandKacheln / 2
        let y: CGFloat = if let kachel = kacheln[safe: stelle] {
            kachel.frame.minY - halb
        } else if let letzte = kacheln.last {
            letzte.frame.maxY + halb
        } else {
            polster
        }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: polster, y: y - 1.5,
                                         width: max(0, bounds.width - polster * 2), height: 3),
                     xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func schraffieren(_ farbe: NSColor) { Messzaehler.messen("schraffur") { schraffierenJetzt(farbe) } }

    private func schraffierenJetzt(_ farbe: NSColor) {
        // Beschnitt nötig: Die Striche laufen über die Zellenränder hinaus.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).setClip()

        let abstand: CGFloat = 10 * 1.4142
        let pfad = NSBezierPath()
        var x = -bounds.height
        while x < bounds.width + bounds.height {
            pfad.move(to: NSPoint(x: x, y: bounds.height))
            pfad.line(to: NSPoint(x: x + bounds.height, y: 0))
            x += abstand
        }
        farbe.setStroke()
        pfad.lineWidth = 1
        pfad.stroke()
    }

    // ── Maus ──────────────────────────────────────────────────────────────

    override func mouseDown(with ereignis: NSEvent) {
        guard zeile >= 0 else { return }
        if ereignis.clickCount == 2 {
            griffe.vorhabenAnlegen(zeile, woche)
        } else {
            griffe.zelleAnwaehlen(zeile, woche)
        }
    }

    override func menu(for ereignis: NSEvent) -> NSMenu? {
        guard zeile >= 0 else { return nil }
        griffe.zelleAnwaehlen(zeile, woche)
        return griffe.zellenmenue(zeile, woche)
    }

    /// Ohne Maus führt der Weg ins Zellenmenü über VoiceOver (VO-Umschalt-M);
    /// gebaut wird es auch hier erst beim Aufruf.
    override func accessibilityPerformShowMenu() -> Bool {
        guard zeile >= 0 else { return false }
        griffe.zelleAnwaehlen(zeile, woche)
        guard let menue = griffe.zellenmenue(zeile, woche) else { return false }
        return menue.popUp(positioning: nil,
                           at: NSPoint(x: bounds.midX, y: bounds.midY), in: self)
    }

    @objc private func anlegenGedrueckt() { griffe.vorhabenAnlegen(zeile, woche) }
    @objc private func freiGedrueckt() { griffe.freiUmschalten(zeile, woche) }
}

/// Der Träger, den `NSCollectionView` wiederverwendet.
final class Zellenelement: NSCollectionViewItem {
    static let kennung = NSUserInterfaceItemIdentifier("Zelle")

    var koerper: Zellenkoerper { view as! Zellenkoerper }

    override func loadView() { view = Zellenkoerper(frame: .zero) }

    /// Die eigene Auswahlkennzeichnung bleibt aus: Welche Zelle angewählt ist,
    /// weiß der Planungsspeicher.
    override var isSelected: Bool {
        get { false }
        set { _ = newValue }
    }
}
