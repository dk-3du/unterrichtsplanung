// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import UniformTypeIdentifiers

/// Ein Unterrichtsvorhaben im Raster — gezeichnet statt zusammengesetzt.
///
/// In SwiftUI bestand eine Kachel aus rund vierzig Ansichtsknoten, das Raster
/// kam auf über tausend. Hier ist die Kachel **eine** Ansicht; eigene
/// Bedienelemente bekommen nur die Stellen, die man anfassen kann.
final class Kachelansicht: NSView {

    /// Was die Kachel nach außen meldet.
    struct Griffe {
        var anwaehlen: (String, NSEvent.ModifierFlags) -> Void = { _, _ in }
        var istAngewaehlt: (String) -> Bool = { _ in false }
        var oeffnen: (String) -> Void = { _ in }
        var erledigtUmschalten: (String) -> Void = { _ in }
        var titelSetzen: (String, String) -> Void = { _, _ in }
        var menue: (String, Bool, Bool) -> NSMenu? = { _, _, _ in nil }
        var ziehnutzlast: (String) -> [String] = { [$0] }
        var materialZeigen: (String) -> Void = { _ in }
        var materialOeffnen: (String) -> Void = { _ in }
        var adresseOeffnen: (String) -> Void = { _ in }
        var vollerPfad: (String) -> String = { $0 }
    }

    private(set) var stand: Rasterdaten.Kachelstand?
    private var ton: Farbton = Farbwelt.ton(0)
    private var angewaehlt = false
    private var griffe = Griffe()

    private(set) var ueberfahren = false

    /// Wird vom Sammelblatt gesetzt (siehe `Zellenkoerper.ueberfahrenSetzen`).
    func ueberfahrenSetzen(_ neu: Bool) {
        guard neu != ueberfahren else { return }
        ueberfahren = neu
        nachfuehren()
    }

    /// Höchstens drei Verweiszeilen je Art — wie in der Höhenrechnung.
    private static let hoechstensVerweise = 3

    private let hakenknopf = NSButton()
    private var materialknoepfe: [(zeile: NSButton, oeffnen: NSButton)] = []
    private var linkknoepfe: [NSButton] = []
    private var titelfeld: NSTextField?
    /// Beim Anordnen bestimmt, beim Zeichnen gebraucht: Die Flächen liegen
    /// unter den Knöpfen, damit zwischen Symbol und Kante Luft bleibt.
    private var verweisfelder: [NSRect] = []
    /// Wo der Inhalt endet — von `layout()` gesetzt für die Prüfung „passt in
    /// die vorausberechnete Höhe“; gezeichneter Text ist von außen nicht
    /// ablesbar.
    private(set) var inhaltsende: CGFloat = 0
    /// Luft zwischen der grauen Fläche und dem, was darin steht.
    private static let verweispolster: CGFloat = 7

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // ── Aufbau ────────────────────────────────────────────────────────────

    override init(frame: NSRect) {
        super.init(frame: frame)
        hakenknopf.isBordered = false
        hakenknopf.bezelStyle = .inline
        hakenknopf.imagePosition = .imageOnly
        hakenknopf.target = self
        hakenknopf.action = #selector(hakenGedrueckt)
        hakenknopf.isHidden = true
        addSubview(hakenknopf)

        // Selbstgezeichnete Ansichten sind für VoiceOver erst mit beidem da;
        // ein Etikett allein bleibt unerreichbar.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht aus einer Datei geladen") }

    func setzen(_ neuerStand: Rasterdaten.Kachelstand, ton neuerTon: Farbton,
                angewaehlt neuAngewaehlt: Bool, griffe neueGriffe: Griffe) {
        // Ganzer Stand, nicht nur das Vorhaben: `kannHoch`/`kannRunter` hängen an der Zelle.
        let gleich = stand == neuerStand && ton == neuerTon
        griffe = neueGriffe
        if gleich {
            if angewaehlt != neuAngewaehlt { angewaehlt = neuAngewaehlt; needsDisplay = true }
            return
        }
        let anderesVorhaben = stand?.vorhaben.id != neuerStand.vorhaben.id
        stand = neuerStand
        ton = neuerTon
        angewaehlt = neuAngewaehlt
        if anderesVorhaben { titelBearbeitenAbbrechen() }
        knoepfeAufbauen()
        nachfuehren()
    }

    /// Nur neu zeichnen, nicht neu aufbauen.
    func auswahlSetzen(_ neu: Bool) {
        guard neu != angewaehlt else { return }
        angewaehlt = neu
        needsDisplay = true
        // Kein `makeFirstResponder(nil)`: Den Fokusring mitzunehmen zerstörte die Auswahl.
    }

    private func nachfuehren() {
        needsDisplay = true
        needsLayout = true
        hakenknopf.isHidden = !(ueberfahren || stand?.vorhaben.erledigt == true)
        for (zeile, oeffnen) in materialknoepfe {
            _ = zeile
            oeffnen.isHidden = !ueberfahren
        }
    }

    // ── Bedienelemente ────────────────────────────────────────────────────

    private func knoepfeAufbauen() { Messzaehler.messen("knoepfe") { knoepfeJetzt() } }

    private func knoepfeJetzt() {
        guard let vorhaben = stand?.vorhaben else { return }

        let erledigt = vorhaben.erledigt
        hakenknopf.image = Symbolvorrat.bild(erledigt ? "checkmark.circle.fill" : "circle")
        hakenknopf.contentTintColor = erledigt ? Rasterfarben.erledigt : Rasterfarben.schriftZweit
        hakenknopf.toolTip = erledigt ? "Als noch offen führen" : "Als durchgeführt kennzeichnen"
        hakenknopf.setAccessibilityLabel(
            vorhaben.anzeigeTitel + (erledigt ? " als offen führen" : " als durchgeführt kennzeichnen"))

        let materialien = Array(vorhaben.materialien.prefix(Self.hoechstensVerweise))
        while materialknoepfe.count > materialien.count {
            let paar = materialknoepfe.removeLast()
            paar.zeile.removeFromSuperview()
            paar.oeffnen.removeFromSuperview()
        }
        while materialknoepfe.count < materialien.count {
            let zeile = verweisknopf(#selector(materialGedrueckt))
            let oeffnen = symbolknopf(Zeichen.datei, #selector(materialOeffnenGedrueckt))
            addSubview(zeile)
            addSubview(oeffnen)
            materialknoepfe.append((zeile, oeffnen))
        }
        for (stelle, material) in materialien.enumerated() {
            let paar = materialknoepfe[stelle]
            let name = material.titel.isEmpty ? Pfade.dateiName(material.pfad) : material.titel
            paar.zeile.tag = stelle
            paar.oeffnen.tag = stelle
            beschriften(paar.zeile, symbol: Zeichen.ordner, text: name)
            paar.zeile.toolTip = "Im Finder zeigen: " + griffe.vollerPfad(material.pfad)
            paar.zeile.setAccessibilityLabel("Im Finder zeigen: " + name)
            paar.oeffnen.toolTip = "Datei öffnen: " + griffe.vollerPfad(material.pfad)
            paar.oeffnen.setAccessibilityLabel("Datei öffnen: " + name)
        }

        let links = Array(vorhaben.links.prefix(Self.hoechstensVerweise))
        while linkknoepfe.count > links.count { linkknoepfe.removeLast().removeFromSuperview() }
        while linkknoepfe.count < links.count {
            let knopf = verweisknopf(#selector(linkGedrueckt))
            addSubview(knopf)
            linkknoepfe.append(knopf)
        }
        for (stelle, link) in links.enumerated() {
            let knopf = linkknoepfe[stelle]
            let name = link.titel.isEmpty ? Weblinks.name(link.adresse) : link.titel
            knopf.tag = stelle
            beschriften(knopf, symbol: Zeichen.verweis, text: name)
            knopf.toolTip = link.adresse
            knopf.setAccessibilityLabel("Im Browser öffnen: " + name)
        }

        var beschriftung = "Vorhaben " + vorhaben.anzeigeTitel
        if erledigt { beschriftung += ", durchgeführt" }
        if vorhaben.pruefung {
            beschriftung += ", Prüfung"
            if let tag = vorhaben.pruefungstag { beschriftung += " am " + tag.deutsch }
            else { beschriftung += " ohne Termin" }
        }
        if let tag = vorhaben.datum { beschriftung += ", Datum " + tag.deutsch }
        if vorhaben.dringend { beschriftung += ", dringlich" }
        setAccessibilityLabel(beschriftung)
    }

    private func verweisknopf(_ handlung: Selector) -> NSButton {
        let knopf = NSButton()
        knopf.isBordered = false
        knopf.alignment = .left
        knopf.target = self
        knopf.action = handlung
        knopf.imagePosition = .imageLeading
        knopf.imageHugsTitle = true
        return knopf
    }

    private func symbolknopf(_ name: String, _ handlung: Selector) -> NSButton {
        let knopf = NSButton()
        knopf.isBordered = false
        knopf.imagePosition = .imageOnly
        knopf.image = Symbolvorrat.bild(name)
        knopf.contentTintColor = Rasterfarben.schriftZweit
        knopf.target = self
        knopf.action = handlung
        knopf.isHidden = true
        return knopf
    }

    private func beschriften(_ knopf: NSButton, symbol: String, text: String) {
        knopf.image = Symbolvorrat.bild(symbol, klein: true)
        knopf.contentTintColor = Rasterfarben.schriftZweit
        knopf.attributedTitle = NSAttributedString(string: " " + text,
                                                   attributes: Symbolvorrat.verweismerkmale)
    }

    // ── Anordnen ──────────────────────────────────────────────────────────

    override func layout() {
        super.layout()
        guard let stand else { return }
        let innen = bounds.width - Zellenmass.kachelLinks - Zellenmass.kachelRechts
        var y = Zellenmass.kachelOben
        if stand.istPruefung { y += Zellenmass.hoehePruefungszeile + Zellenmass.abstandPruefung }
        if stand.gesetztesDatum != nil {
            y += Zellenmass.hoeheDatumszeile + Zellenmass.abstandDatum
        }

        let titelhoehe = stand.titelhoehe
        hakenknopf.frame = NSRect(x: bounds.width - Zellenmass.kachelRechts - 16,
                                  y: y, width: 16, height: 16)
        titelfeld?.frame = NSRect(x: Zellenmass.kachelLinks - 4, y: y - 1,
                                  width: innen - Zellenmass.breiteHaken + 4,
                                  height: max(18, titelhoehe))
        y += titelhoehe

        if stand.texthoehe > 0 { y += 2 + stand.texthoehe }

        verweisfelder.removeAll(keepingCapacity: true)
        y = verweiseAnordnen(materialknoepfe.map(\.zeile), oeffnen: materialknoepfe.map(\.oeffnen),
                             ab: y, innen: innen,
                             gesamt: stand.vorhaben.materialien.count)
        y = verweiseAnordnen(linkknoepfe, oeffnen: [], ab: y, innen: innen,
                             gesamt: stand.vorhaben.links.count)
        inhaltsende = y + Zellenmass.kachelOben
    }

    private func verweiseAnordnen(_ zeilen: [NSButton], oeffnen: [NSButton],
                                  ab start: CGFloat, innen: CGFloat,
                                  gesamt: Int) -> CGFloat {
        guard !zeilen.isEmpty else { return start }
        var y = start + Zellenmass.abstandKacheln
        let knopfbreite: CGFloat = oeffnen.isEmpty ? 0 : 20
        let polster = Self.verweispolster
        for (stelle, zeile) in zeilen.enumerated() {
            let feld = NSRect(x: Zellenmass.kachelLinks, y: y,
                              width: max(20, innen - knopfbreite - 2),
                              height: Zellenmass.hoeheVerweiszeile)
            verweisfelder.append(feld)
            zeile.frame = feld.insetBy(dx: polster, dy: 0)
            if oeffnen.indices.contains(stelle) {
                oeffnen[stelle].frame = NSRect(x: Zellenmass.kachelLinks + innen - knopfbreite,
                                               y: y, width: knopfbreite,
                                               height: Zellenmass.hoeheVerweiszeile)
            }
            y += Zellenmass.hoeheVerweiszeile
            if stelle < zeilen.count - 1 { y += Zellenmass.abstandVerweise }
        }
        if gesamt > Self.hoechstensVerweise {
            y += Zellenmass.abstandVerweise + Zellenmass.hoeheMehrzeile
        }
        return y
    }

    // ── Zeichnen ──────────────────────────────────────────────────────────

    override func draw(_ schmutzig: NSRect) {
        Messzaehler.messen("Kachel.draw") { zeichnenJetzt() }
    }

    private func zeichnenJetzt() {
        guard let stand else { return }
        let vorhaben = stand.vorhaben
        let deckkraft: CGFloat = vorhaben.erledigt ? 0.62 : 1
        NSGraphicsContext.current?.cgContext.setAlpha(deckkraft)

        let karte = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: Masse.kachelradius, yRadius: Masse.kachelradius)
        Kursfarben.nsFlaeche(ton).setFill()
        karte.fill()

        if angewaehlt {
            NSColor.controlAccentColor.setStroke()
            karte.lineWidth = 2.5
        } else if vorhaben.dringend {
            (ueberfahren ? Rasterfarben.dringendStark : Rasterfarben.dringend).setStroke()
            karte.lineWidth = 2
        } else if stand.istPruefung {
            Rasterfarben.pruefung.withAlphaComponent(ueberfahren ? 0.95 : 0.7).setStroke()
            karte.lineWidth = 1.5
        } else {
            Kursfarben.nsFarbe(ton).withAlphaComponent(ueberfahren ? 0.7 : 0.35).setStroke()
            karte.lineWidth = 1
        }
        karte.stroke()

        let streifen = NSBezierPath(roundedRect: NSRect(x: 0, y: 8, width: 3,
                                                        height: max(0, bounds.height - 16)),
                                    xRadius: 1.5, yRadius: 1.5)
        Kursfarben.nsFarbe(ton).setFill()
        streifen.fill()

        let innen = bounds.width - Zellenmass.kachelLinks - Zellenmass.kachelRechts
        var y = Zellenmass.kachelOben

        if let hinweis = stand.gesetztePruefung {
            let zeile = NSRect(x: Zellenmass.kachelLinks, y: y, width: innen,
                               height: Zellenmass.hoehePruefungszeile)
            Rasterfarben.pruefungflaeche.setFill()
            NSBezierPath(roundedRect: zeile, xRadius: 5, yRadius: 5).fill()
            hinweis.draw(with: zeile.insetBy(dx: 6, dy: 1),
                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            y += Zellenmass.hoehePruefungszeile + Zellenmass.abstandPruefung
        }

        if let datum = stand.gesetztesDatum {
            datum.draw(with: NSRect(x: Zellenmass.kachelLinks, y: y, width: innen,
                                    height: Zellenmass.hoeheDatumszeile),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            y += Zellenmass.hoeheDatumszeile + Zellenmass.abstandDatum
        }

        let titelbreite = max(20, innen - Zellenmass.breiteHaken)
        let titelhoehe = stand.titelhoehe
        if titelfeld == nil {
            stand.gesetzterTitel.draw(
                with: NSRect(x: Zellenmass.kachelLinks, y: y, width: titelbreite,
                             height: titelhoehe),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        y += titelhoehe

        if let gesetzt = stand.gesetzterText {
            gesetzt.draw(with: NSRect(x: Zellenmass.kachelLinks, y: y + 2,
                                      width: innen, height: stand.texthoehe),
                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            y += 2 + stand.texthoehe
        }

        for feld in verweisfelder {
            Rasterfarben.verweiszeile.setFill()
            NSBezierPath(roundedRect: feld, xRadius: 6, yRadius: 6).fill()
        }

        y = mehrzeileZeichnen(anzahl: vorhaben.materialien.count, gezeigt: materialknoepfe.count,
                              ab: y, innen: innen, text: "weitere")
        _ = mehrzeileZeichnen(anzahl: vorhaben.links.count, gezeigt: linkknoepfe.count,
                              ab: y, innen: innen, text: "weitere Links")
    }

    private func mehrzeileZeichnen(anzahl: Int, gezeigt: Int, ab start: CGFloat,
                                   innen: CGFloat, text: String) -> CGFloat {
        guard gezeigt > 0 else { return start }
        var y = start + Zellenmass.abstandKacheln
            + CGFloat(gezeigt) * Zellenmass.hoeheVerweiszeile
            + CGFloat(gezeigt - 1) * Zellenmass.abstandVerweise
        guard anzahl > Self.hoechstensVerweise else { return y }
        y += Zellenmass.abstandVerweise
        Textsatz.setzen("+ \(anzahl - Self.hoechstensVerweise) \(text)", stil: .caption2,
                        gewicht: .regular, farbe: Rasterfarben.schriftDritt,
                        durchgestrichen: false, umbricht: false)
            .draw(with: NSRect(x: Zellenmass.kachelLinks, y: y, width: innen,
                               height: Zellenmass.hoeheMehrzeile),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        return y + Zellenmass.hoeheMehrzeile
    }

    // ── Maus ──────────────────────────────────────────────────────────────

    private var zugAnfang: NSPoint?
    /// Ein Klick auf eine bereits angewählte Kachel wählt erst beim LOSLASSEN
    /// allein an — sonst schmölze die Mehrfachauswahl vor dem Zug ein.
    private var anwahlBeimLoslassen: String?

    override func mouseDown(with ereignis: NSEvent) {
        guard let id = stand?.vorhaben.id, titelfeld == nil else {
            super.mouseDown(with: ereignis)
            return
        }
        window?.makeFirstResponder(self)
        if ereignis.clickCount == 2 {
            griffe.oeffnen(id)
            zugAnfang = nil
            return
        }
        let tasten = ereignis.modifierFlags.intersection([.command, .shift])
        if tasten.isEmpty, griffe.istAngewaehlt(id) {
            anwahlBeimLoslassen = id
        } else {
            griffe.anwaehlen(id, tasten)
        }
        zugAnfang = ereignis.locationInWindow
    }

    override func mouseDragged(with ereignis: NSEvent) {
        guard let anfang = zugAnfang, let id = stand?.vorhaben.id else { return }
        let weg = hypot(ereignis.locationInWindow.x - anfang.x,
                        ereignis.locationInWindow.y - anfang.y)
        guard weg > 4 else { return }
        zugAnfang = nil
        anwahlBeimLoslassen = nil
        ziehen(id, ereignis: ereignis)
    }

    override func mouseUp(with ereignis: NSEvent) {
        zugAnfang = nil
        if let id = anwahlBeimLoslassen {
            anwahlBeimLoslassen = nil
            griffe.anwaehlen(id, [])
        }
    }

    private func ziehen(_ id: String, ereignis: NSEvent) {
        let kennungen = griffe.ziehnutzlast(id)
        guard let daten = try? JSONEncoder().encode(Vorhabenverweis(ids: kennungen)) else { return }
        let eintrag = NSPasteboardItem()
        eintrag.setData(daten, forType: NSPasteboard.PasteboardType(UTType.vorhabenverweis.identifier))
        let gegenstand = NSDraggingItem(pasteboardWriter: eintrag)

        let abbild = abzeichnen()
        gegenstand.setDraggingFrame(bounds, contents: abbild)
        let sitzung = beginDraggingSession(with: [gegenstand], event: ereignis, source: self)
        sitzung.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func abzeichnen() -> NSImage? {
        guard let abzug = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: abzug)
        let bild = NSImage(size: bounds.size)
        bild.addRepresentation(abzug)
        return bild
    }

    override func menu(for ereignis: NSEvent) -> NSMenu? {
        guard let stand else { return nil }
        // Sonst schmölze ein Rechtsklick jede Mehrfachauswahl ein.
        if !griffe.istAngewaehlt(stand.vorhaben.id) {
            griffe.anwaehlen(stand.vorhaben.id, [])
        }
        return griffe.menue(stand.vorhaben.id, stand.kannHoch, stand.kannRunter)
    }

    // ── Tastatur ──────────────────────────────────────────────────────────

    override func keyDown(with ereignis: NSEvent) {
        guard let id = stand?.vorhaben.id else {
            super.keyDown(with: ereignis)
            return
        }
        switch ereignis.keyCode {
        case 36, 76:   // ⏎ und ⌤
            if ereignis.modifierFlags.contains(.option) { titelBearbeiten() } else { griffe.oeffnen(id) }
        default:
            super.keyDown(with: ereignis)
        }
    }

    /// Beim Tabben wandert die Auswahl mit — beim Klicken **nicht**.
    ///
    /// AppKit macht die getroffene Ansicht zum Ersthelfer, BEVOR es ihr
    /// `mouseDown` schickt. Unbesehen angewählt höbe ein ⌘-Klick die eigene
    /// Anwahl wieder auf, und ein ⇧-Klick spannte von sich selbst bis zu sich.
    override func becomeFirstResponder() -> Bool {
        let vomKlick = switch NSApp.currentEvent?.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: true
        default: false
        }
        guard !vomKlick, let id = stand?.vorhaben.id else { return super.becomeFirstResponder() }
        griffe.anwaehlen(id, [])
        return super.becomeFirstResponder()
    }

    // ── Titel an Ort und Stelle ───────────────────────────────────────────

    func titelBearbeiten() {
        guard titelfeld == nil, let vorhaben = stand?.vorhaben else { return }
        let feld = NSTextField(string: vorhaben.titel)
        feld.font = Zellenmass.schrift(.callout, .medium)
        feld.isBordered = true
        feld.bezelStyle = .roundedBezel
        feld.focusRingType = .exterior
        feld.lineBreakMode = .byTruncatingTail
        feld.delegate = self
        feld.setAccessibilityLabel("Titel des Vorhabens ändern")
        addSubview(feld)
        titelfeld = feld
        needsLayout = true
        needsDisplay = true
        window?.makeFirstResponder(feld)
    }

    private func titelBearbeitenAbbrechen() {
        // Erst abmelden, dann entfernen: `removeFromSuperview()` schickt noch `controlTextDidEndEditing`.
        let feld = titelfeld
        titelfeld = nil
        feld?.delegate = nil
        feld?.removeFromSuperview()
        needsDisplay = true
    }

    private func titelUebernehmen() {
        guard let feld = titelfeld, let id = stand?.vorhaben.id else { return }
        let text = feld.stringValue
        titelBearbeitenAbbrechen()
        window?.makeFirstResponder(self)
        griffe.titelSetzen(id, text)
    }

    // ── Handlungen ────────────────────────────────────────────────────────

    @objc private func hakenGedrueckt() {
        guard let id = stand?.vorhaben.id else { return }
        griffe.erledigtUmschalten(id)
    }

    @objc private func materialGedrueckt(_ absender: NSButton) {
        guard let material = stand?.vorhaben.materialien[safe: absender.tag] else { return }
        griffe.materialZeigen(material.pfad)
    }

    @objc private func materialOeffnenGedrueckt(_ absender: NSButton) {
        guard let material = stand?.vorhaben.materialien[safe: absender.tag] else { return }
        griffe.materialOeffnen(material.pfad)
    }

    @objc private func linkGedrueckt(_ absender: NSButton) {
        guard let link = stand?.vorhaben.links[safe: absender.tag] else { return }
        griffe.adresseOeffnen(link.adresse)
    }
}

// ── Ziehquelle ────────────────────────────────────────────────────────────

extension Kachelansicht: NSDraggingSource {
    func draggingSession(_ sitzung: NSDraggingSession,
                         sourceOperationMaskFor ziel: NSDraggingContext) -> NSDragOperation {
        ziel == .withinApplication ? [.move, .copy] : []
    }
}

// ── Schreiben ─────────────────────────────────────────────────────────────

extension Kachelansicht: NSTextFieldDelegate {
    /// ⏎ übernimmt, ⎋ verwirft, ein Klick daneben übernimmt ebenfalls.
    func control(_ steuerung: NSControl, textView: NSTextView,
                 doCommandBy befehl: Selector) -> Bool {
        switch befehl {
        case #selector(NSResponder.insertNewline(_:)):
            titelUebernehmen()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            titelBearbeitenAbbrechen()
            window?.makeFirstResponder(self)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ meldung: Notification) {
        guard titelfeld != nil else { return }
        titelUebernehmen()
    }
}

extension Array {
    subscript(safe stelle: Int) -> Element? {
        indices.contains(stelle) ? self[stelle] : nil
    }
}


// ── Symbolvorrat ──────────────────────────────────────────────────────────

/// Einmal geladen: `NSImage(systemSymbolName:)` schlägt bei jedem Aufruf in der
/// Symbolbibliothek nach und legt ein neues Bild an.
@MainActor
enum Symbolvorrat {
    private static var vorrat: [String: NSImage] = [:]

    static func bild(_ name: String, klein: Bool = false) -> NSImage? {
        let schluessel = klein ? name + "|klein" : name
        if let bekannt = vorrat[schluessel] { return bekannt }
        var bild = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        if klein {
            let schrift = Zellenmass.schrift(.caption1, .regular)
            bild = bild?.withSymbolConfiguration(
                .init(pointSize: schrift.pointSize - 1, weight: .regular))
        }
        if let bild { vorrat[schluessel] = bild }
        return bild
    }

    static let verweismerkmale: [NSAttributedString.Key: Any] = {
        let absatz = NSMutableParagraphStyle()
        absatz.lineBreakMode = .byTruncatingMiddle
        return [.font: Zellenmass.schrift(.caption1, .regular),
                .foregroundColor: Rasterfarben.schrift,
                .paragraphStyle: absatz]
    }()
}
