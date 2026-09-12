// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Die Fläche des Sitzplan-Editors — eine `NSView`, weil Ziehen, Gummiband,
/// Kontextmenü und Tastatur dort unmittelbar sind. Sie zeichnet Tafel,
/// Lehrertisch und Tische; verändert wird der Plan nur über die reinen
/// Funktionen des Modells (`verschoben`, `umbenannt`, `ohne` …), und jede
/// Änderung geht als Ganzes an das Blatt zurück.
///
/// Bedienung: Linke Maustaste wählt an und zieht — einen Tisch oder alle
/// angewählten gemeinsam; ⇧ und ⌘ nehmen dazu. Rechte Maustaste gezogen
/// zieht eine Bereichsauswahl auf, kurz gedrückt öffnet sie das Kontextmenü.
/// Doppelklick benennt um. Pfeile verschieben um 8 Punkt, mit ⇧ um 1; Tab
/// wechselt den Tisch; Escape hebt die Auswahl auf. Fangen am unsichtbaren
/// 8-Punkt-Raster, ⌥ beim Ziehen hebt es auf (E26).
@MainActor
final class Sitzplanansicht: NSView, NSTextFieldDelegate {

    var plan: Sitzplan {
        didSet { if plan != oldValue { needsDisplay = true } }
    }
    var auswahl: Set<String> = [] {
        didSet { if auswahl != oldValue { needsDisplay = true } }
    }
    var ton: Farbton {
        didSet { needsDisplay = true }
    }
    /// Der Plan hat sich geändert — als Ganzes, nach jedem Handgriff.
    var beiAenderung: (Sitzplan) -> Void = { _ in }
    var beiAuswahl: (Set<String>) -> Void = { _ in }

    /// Wo das Ziehen begann, was darunter lag und der Stand davor: Der Weg
    /// wird vom Anfang gerechnet, nicht Schritt für Schritt aufsummiert.
    private var ziehanker: String?
    private var ziehstart: NSPoint?
    private var planBeimDruecken: Sitzplan?
    private var bewegt = false

    private var rechtsstart: NSPoint?
    private var gummiband: NSRect?

    private var umbenennfeld: NSTextField?
    private var umbenennTisch: String?

    init(plan: Sitzplan, ton: Farbton) {
        self.plan = plan
        self.ton = ton
        super.init(frame: NSRect(x: 0, y: 0, width: Sitzplanmasse.breite, height: Sitzplanmasse.hoehe))
        setAccessibilityRole(.group)
        setAccessibilityLabel("Sitzplanfläche")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht aus einer Datei geladen") }

    /// Ursprung oben links wie im Modell und auf dem Blatt.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: Sitzplanmasse.breite, height: Sitzplanmasse.hoehe)
    }

    // ── Zeichnen ──────────────────────────────────────────────────────────

    private static let namensschrift = NSFont.systemFont(ofSize: 10, weight: .medium)
    private static let beschriftungsschrift = NSFont.systemFont(ofSize: 10)
    /// Die Zeilenhöhe, wie der Satz sie nimmt — `boundingRectForFont` liegt
    /// einen Bruchteil darunter, und zwei Zeilen passten dann nicht mehr.
    private static let zeilenhoehe = NSLayoutManager().defaultLineHeight(for: namensschrift)

    private func text(_ wert: String, schrift: NSFont, farbe: NSColor, in rahmen: NSRect, zeilen: Int) {
        let absatz = NSMutableParagraphStyle()
        absatz.alignment = .center
        // Umbrechen, nicht kürzen — gekürzt wird erst die letzte sichtbare Zeile.
        absatz.lineBreakMode = .byWordWrapping
        let attribute: [NSAttributedString.Key: Any] = [
            .font: schrift, .foregroundColor: farbe, .paragraphStyle: absatz]
        let inhalt = NSAttributedString(string: wert, attributes: attribute)
        let innen = rahmen.insetBy(dx: 2, dy: 3)
        // Etwas Luft über den Zeilen, aber weniger als eine dritte Zeile.
        let hoechstens = CGFloat(zeilen) * Sitzplanansicht.zeilenhoehe + 2
        let gemessen = inhalt.boundingRect(
            with: NSSize(width: innen.width, height: min(innen.height, hoechstens)),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        let hoehe = min(innen.height, ceil(gemessen.height))
        let ziel = NSRect(x: innen.minX, y: innen.midY - hoehe / 2, width: innen.width, height: hoehe)
        inhalt.draw(with: ziel, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func draw(_ ausschnitt: NSRect) {
        let flaeche = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.06).setFill()
        flaeche.fill()
        NSColor.separatorColor.setStroke()
        flaeche.lineWidth = 1
        flaeche.stroke()

        // Die Tafel — die feste Leiste unten.
        let tafel = NSBezierPath(roundedRect: Sitzplanmasse.tafel, xRadius: 4, yRadius: 4)
        NSColor.secondaryLabelColor.withAlphaComponent(0.35).setFill()
        tafel.fill()
        text("Tafel", schrift: Sitzplanansicht.beschriftungsschrift, farbe: .labelColor,
             in: Sitzplanmasse.tafel, zeilen: 1)

        if let rahmen = plan.lehrertischRahmen {
            let gewaehlt = auswahl.contains(Sitzplan.lehrertischKennung)
            let pfad = NSBezierPath(roundedRect: rahmen, xRadius: 6, yRadius: 6)
            NSColor.quaternaryLabelColor.withAlphaComponent(0.12).setFill()
            pfad.fill()
            pfad.lineWidth = gewaehlt ? 2 : 1
            pfad.setLineDash([4, 3], count: 2, phase: 0)
            (gewaehlt ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setStroke()
            pfad.stroke()
            text("Lehrertisch", schrift: Sitzplanansicht.beschriftungsschrift,
                 farbe: .secondaryLabelColor, in: rahmen, zeilen: 1)
        }

        for tisch in plan.tische {
            let gewaehlt = auswahl.contains(tisch.id)
            let pfad = NSBezierPath(roundedRect: tisch.rahmen, xRadius: 6, yRadius: 6)
            (gewaehlt ? NSColor.controlAccentColor.withAlphaComponent(0.22)
                      : Kursfarben.nsFlaeche(ton)).setFill()
            pfad.fill()
            pfad.lineWidth = gewaehlt ? 2 : 1
            (gewaehlt ? NSColor.controlAccentColor : Kursfarben.nsFarbe(ton).withAlphaComponent(0.6)).setStroke()
            pfad.stroke()
            if umbenennTisch != tisch.id {
                text(tisch.name, schrift: Sitzplanansicht.namensschrift, farbe: .labelColor,
                     in: tisch.rahmen, zeilen: 2)
            }
        }

        if let gummiband {
            let pfad = NSBezierPath(rect: gummiband)
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            pfad.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke()
            pfad.lineWidth = 1
            pfad.stroke()
        }
    }

    // ── Auswahl ───────────────────────────────────────────────────────────

    private func auswaehlen(_ neu: Set<String>) {
        guard neu != auswahl else { return }
        auswahl = neu
        beiAuswahl(neu)
    }

    private func planAendern(_ neu: Sitzplan) {
        guard neu != plan else { return }
        plan = neu
        beiAenderung(neu)
    }

    // ── Linke Maustaste: anwählen und ziehen ──────────────────────────────

    override func mouseDown(with ereignis: NSEvent) {
        window?.makeFirstResponder(self)
        umbenennenBeenden(uebernehmen: true)
        let punkt = convert(ereignis.locationInWindow, from: nil)
        let getroffen = plan.element(bei: punkt)
        if ereignis.clickCount == 2, let id = getroffen, id != Sitzplan.lehrertischKennung {
            umbenennenBeginnen(id)
            return
        }
        var neu = auswahl
        if let id = getroffen {
            if ereignis.modifierFlags.contains(.shift) || ereignis.modifierFlags.contains(.command) {
                if neu.contains(id) { neu.remove(id) } else { neu.insert(id) }
            } else if !neu.contains(id) {
                neu = [id]
            }
        } else {
            neu = []
        }
        auswaehlen(neu)
        ziehanker = getroffen
        ziehstart = punkt
        planBeimDruecken = plan
        bewegt = false
    }

    override func mouseDragged(with ereignis: NSEvent) {
        guard let start = ziehstart, let ausgang = planBeimDruecken, let anker = ziehanker,
              auswahl.contains(anker) else { return }
        let punkt = convert(ereignis.locationInWindow, from: nil)
        let weg = CGPoint(x: punkt.x - start.x, y: punkt.y - start.y)
        let fangen = !ereignis.modifierFlags.contains(.option)
        let neu = ausgang.verschoben(auswahl, um: weg, anker: anker, fangen: fangen)
        if neu != plan {
            plan = neu
            bewegt = true
        }
    }

    override func mouseUp(with ereignis: NSEvent) {
        if bewegt { beiAenderung(plan) }
        ziehstart = nil
        ziehanker = nil
        planBeimDruecken = nil
        bewegt = false
    }

    // ── Rechte Maustaste: Bereichsauswahl oder Kontextmenü ────────────────

    override func rightMouseDown(with ereignis: NSEvent) {
        window?.makeFirstResponder(self)
        umbenennenBeenden(uebernehmen: true)
        rechtsstart = convert(ereignis.locationInWindow, from: nil)
        gummiband = nil
    }

    override func rightMouseDragged(with ereignis: NSEvent) {
        guard let start = rechtsstart else { return }
        let punkt = convert(ereignis.locationInWindow, from: nil)
        guard abs(punkt.x - start.x) > 3 || abs(punkt.y - start.y) > 3 else { return }
        let bereich = NSRect(x: min(start.x, punkt.x), y: min(start.y, punkt.y),
                             width: abs(punkt.x - start.x), height: abs(punkt.y - start.y))
        gummiband = bereich
        needsDisplay = true
    }

    override func rightMouseUp(with ereignis: NSEvent) {
        defer {
            rechtsstart = nil
            gummiband = nil
            needsDisplay = true
        }
        guard rechtsstart != nil else { return }
        let punkt = convert(ereignis.locationInWindow, from: nil)
        guard let bereich = gummiband else {
            kontextmenue(bei: punkt, ereignis: ereignis)
            return
        }
        var neu = ereignis.modifierFlags.contains(.shift) ? auswahl : []
        neu.formUnion(plan.imBereich(bereich))
        auswaehlen(neu)
    }

    private func kontextmenue(bei punkt: NSPoint, ereignis: NSEvent) {
        let menue = NSMenu()
        if let id = plan.element(bei: punkt) {
            if !auswahl.contains(id) { auswaehlen([id]) }
            if id == Sitzplan.lehrertischKennung {
                let entfernen = NSMenuItem(title: "Lehrertisch entfernen", action: #selector(elementEntfernen(_:)),
                                           keyEquivalent: "")
                entfernen.representedObject = id
                menue.addItem(entfernen)
            } else {
                let umbenennen = NSMenuItem(title: "Umbenennen", action: #selector(tischUmbenennen(_:)),
                                            keyEquivalent: "")
                umbenennen.representedObject = id
                menue.addItem(umbenennen)
                let entfernen = NSMenuItem(title: auswahl.count > 1 ? "\(auswahl.count) Tische entfernen" : "Tisch entfernen",
                                           action: #selector(elementEntfernen(_:)), keyEquivalent: "")
                entfernen.representedObject = id
                menue.addItem(entfernen)
            }
        } else if plan.lehrertisch == nil {
            menue.addItem(NSMenuItem(title: "Lehrertisch hinzufügen", action: #selector(lehrertischHinzufuegen(_:)),
                                     keyEquivalent: ""))
        } else {
            return
        }
        for eintrag in menue.items { eintrag.target = self }
        NSMenu.popUpContextMenu(menue, with: ereignis, for: self)
    }

    @objc private func tischUmbenennen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        umbenennenBeginnen(id)
    }

    @objc private func elementEntfernen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let weg = auswahl.contains(id) ? auswahl : [id]
        var neu = plan
        for kennung in weg { neu = neu.ohne(kennung) }
        auswaehlen([])
        planAendern(neu)
    }

    @objc private func lehrertischHinzufuegen(_ sender: NSMenuItem) {
        planAendern(plan.mitLehrertisch())
    }

    // ── Tastatur ──────────────────────────────────────────────────────────

    override func keyDown(with ereignis: NSEvent) {
        guard umbenennfeld == nil else { super.keyDown(with: ereignis); return }
        let schritt: CGFloat = ereignis.modifierFlags.contains(.shift) ? 1 : Sitzplanmasse.fangraster
        switch ereignis.keyCode {
        case 123, 124, 125, 126:
            guard !auswahl.isEmpty else { super.keyDown(with: ereignis); return }
            let weg: CGPoint = switch ereignis.keyCode {
            case 123: CGPoint(x: -schritt, y: 0)
            case 124: CGPoint(x: schritt, y: 0)
            case 125: CGPoint(x: 0, y: schritt)
            default: CGPoint(x: 0, y: -schritt)
            }
            planAendern(plan.verschoben(auswahl, um: weg, fangen: false))
        case 48:
            let reihe = plan.elementKennungen
            guard !reihe.isEmpty else { super.keyDown(with: ereignis); return }
            let rueckwaerts = ereignis.modifierFlags.contains(.shift)
            let stelle = auswahl.count == 1 ? reihe.firstIndex(of: auswahl.first ?? "") : nil
            let naechste: Int = if let stelle {
                (stelle + (rueckwaerts ? reihe.count - 1 : 1)) % reihe.count
            } else {
                rueckwaerts ? reihe.count - 1 : 0
            }
            auswaehlen([reihe[naechste]])
        case 53:
            guard !auswahl.isEmpty else { super.keyDown(with: ereignis); return }
            auswaehlen([])
        default:
            super.keyDown(with: ereignis)
        }
    }

    // ── Umbenennen am Tisch ───────────────────────────────────────────────

    func umbenennenBeginnen(_ id: String) {
        guard let tisch = plan.tisch(id) else { return }
        umbenennenBeenden(uebernehmen: true)
        let feld = NSTextField(frame: tisch.rahmen.insetBy(dx: 3, dy: 12))
        feld.stringValue = tisch.name
        feld.font = Sitzplanansicht.namensschrift
        feld.alignment = .center
        feld.isBezeled = true
        feld.bezelStyle = .roundedBezel
        feld.focusRingType = .none
        feld.delegate = self
        feld.setAccessibilityLabel("Name am Tisch")
        addSubview(feld)
        umbenennfeld = feld
        umbenennTisch = id
        needsDisplay = true
        window?.makeFirstResponder(feld)
        feld.currentEditor()?.selectAll(nil)
    }

    private func umbenennenBeenden(uebernehmen: Bool) {
        guard let feld = umbenennfeld, let id = umbenennTisch else { return }
        let neu = feld.stringValue
        umbenennfeld = nil
        umbenennTisch = nil
        feld.removeFromSuperview()
        if uebernehmen { planAendern(plan.umbenannt(id, name: neu)) }
        needsDisplay = true
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
    }

    func controlTextDidEndEditing(_ nachricht: Notification) {
        umbenennenBeenden(uebernehmen: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy befehl: Selector) -> Bool {
        if befehl == #selector(NSResponder.cancelOperation(_:)) {
            umbenennenBeenden(uebernehmen: false)
            return true
        }
        if befehl == #selector(NSResponder.insertNewline(_:)) {
            umbenennenBeenden(uebernehmen: true)
            return true
        }
        return false
    }

    // ── Bedienungshilfen: jeder Tisch ein Element mit Name und Lage ───────

    override func accessibilityChildren() -> [Any]? {
        guard let fenster = window else { return nil }
        func element(_ rahmen: NSRect, _ beschriftung: String) -> NSAccessibilityElement {
            let bildschirm = fenster.convertToScreen(convert(rahmen, to: nil))
            let e = NSAccessibilityElement.element(withRole: .staticText, frame: bildschirm,
                                                   label: beschriftung, parent: self)
            return e as! NSAccessibilityElement
        }
        var kinder: [Any] = plan.tische.map {
            element($0.rahmen, "Tisch: \($0.name), Lage \(Int($0.x)), \(Int($0.y))")
        }
        if let rahmen = plan.lehrertischRahmen {
            kinder.append(element(rahmen, "Lehrertisch, Lage \(Int(rahmen.minX)), \(Int(rahmen.minY))"))
        }
        kinder.append(element(Sitzplanmasse.tafel, "Tafel"))
        return kinder
    }
}

/// Die Fläche im Blatt — Plan und Auswahl als Bindungen, ein Umbenennen-Wunsch
/// von außen („Tisch hinzufügen“ öffnet gleich das Feld).
struct Sitzplanflaeche: NSViewRepresentable {
    @Binding var plan: Sitzplan
    @Binding var auswahl: Set<String>
    @Binding var umbenennen: String?
    let ton: Farbton

    func makeNSView(context: Context) -> Sitzplanansicht {
        let ansicht = Sitzplanansicht(plan: plan, ton: ton)
        ansicht.beiAenderung = { neu in context.coordinator.plan.wrappedValue = neu }
        ansicht.beiAuswahl = { neu in context.coordinator.auswahl.wrappedValue = neu }
        return ansicht
    }

    func updateNSView(_ ansicht: Sitzplanansicht, context: Context) {
        if ansicht.plan != plan { ansicht.plan = plan }
        if ansicht.auswahl != auswahl { ansicht.auswahl = auswahl }
        if ansicht.ton != ton { ansicht.ton = ton }
        if let id = umbenennen {
            // Erst nach dem Durchlauf: Das Feld will die Schreibmarke, und ein
            // Zustand darf sich nicht mitten im Aufbau der Ansicht ändern.
            let wunsch = context.coordinator.umbenennen
            DispatchQueue.main.async {
                ansicht.umbenennenBeginnen(id)
                wunsch.wrappedValue = nil
            }
        }
    }

    func sizeThatFits(_ vorschlag: ProposedViewSize, nsView: Sitzplanansicht, context: Context) -> CGSize? {
        CGSize(width: Sitzplanmasse.breite, height: Sitzplanmasse.hoehe)
    }

    func makeCoordinator() -> Koordinator {
        Koordinator(plan: $plan, auswahl: $auswahl, umbenennen: $umbenennen)
    }

    @MainActor
    final class Koordinator {
        let plan: Binding<Sitzplan>
        let auswahl: Binding<Set<String>>
        let umbenennen: Binding<String?>

        init(plan: Binding<Sitzplan>, auswahl: Binding<Set<String>>, umbenennen: Binding<String?>) {
            self.plan = plan
            self.auswahl = auswahl
            self.umbenennen = umbenennen
        }
    }
}
