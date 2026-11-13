// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Die Leiste eines Blatts mit Seitenleiste (v95, E1120): eine AppKit-Tabelle als
/// `NSViewRepresentable`, gezeichnet nach der Vorlage (E1120) — die ganze Leiste steckt in dieser
/// einen Datei.
///
/// Schnittstelle: `Seitenleiste(eintraege:auswahl:name:symbol:plakette:bezeichnung:)` — die Einträge in ihrer Folge, die
/// Auswahl als Bindung, je Eintrag Name, SF-Symbol und Plakette (nil für keine) und die Bedienhilfe der Leiste. Glasfläche,
/// Breite und Blattkopf gibt der Rahmen um sie herum; die Leiste zeichnet keinen Grund.
///
/// **Ruhe (E1120; die SwiftUI-Liste wobbelte):** feste Zeilen — `rowSizeStyle = .custom`, `rowHeight` 32, kein Zwischenraum,
/// `usesAutomaticRowHeights = false`, kein Rückruf für die Höhe einer Zeile. Laut `NSTableView.h` (SDK 27.2, Z. 204) ist
/// dann jede Zeile `rowHeight` + `intercellSpacing.height` hoch; kein Messen, keine Schätzung.
///
/// **Aussehen nach der Vorlage (E1120),** vermessen an ihrem Bild (2 px je pt):
/// - Schrift 13 pt regular, wie der Text im Formular — fest, nicht nach der Größenstufe der Seitenleisten (die gab
///   kleinere Schrift);
/// - Symbol einfarbig in Textfarbe, 13 pt, mittig 18,75 pt nach dem linken Rand der Wahlfläche; Text ab 36,5 pt;
/// - Wahlfläche: eine Zeile hoch, links und rechts 10 pt eingerückt, Ecken 8 pt, gefüllt in der Farbe gewählter Inhalte
///   (`selectedContentBackgroundColor`, folgt der Akzentfarbe), Text und Symbol darin weiß — solange die Leiste den
///   Fokus hat; sonst grau mit Text in Textfarbe (E1120);
/// - nicht gewählte Zeilen ohne Fläche.
///
/// Wie nativ: ↑/↓, Tippen eines Namens und die Bedienhilfen bringt die Tabelle mit. Die Auswahl gehört der Tabelle (wie in
/// der `Huelltabelle`): Die Bindung erfährt sie aus `tableViewSelectionDidChange`, und nur eine Änderung von außen
/// (Zurück/Vorwärts, Programm) schreibt die Tabelle nach. Kein Überschreiben von `mouseDown`, kein Ereignismonitor.
struct Seitenleiste<Eintrag: Hashable>: NSViewRepresentable {
    let eintraege: [Eintrag]
    @Binding var auswahl: Eintrag
    let name: (Eintrag) -> String
    let symbol: (Eintrag) -> String
    let plakette: (Eintrag) -> String?
    let bezeichnung: String

    init(eintraege: [Eintrag], auswahl: Binding<Eintrag>, name: @escaping (Eintrag) -> String,
         symbol: @escaping (Eintrag) -> String, plakette: @escaping (Eintrag) -> String? = { _ in nil },
         bezeichnung: String = "Zeigen") {
        self.eintraege = eintraege
        _auswahl = auswahl
        self.name = name
        self.symbol = symbol
        self.plakette = plakette
        self.bezeichnung = bezeichnung
    }

    func makeCoordinator() -> Seitenleistenkoordinator { Seitenleistenkoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tabelle = NSTableView()
        // Erst der Stil (`NSTableView.h`, Z. 88), dann alles, was er sonst wieder setzen könnte. `.plain`: keine Einzüge
        // und keine Wahlfläche von AppKit — beides zeichnet die Leiste selbst (`Seitenleistenreihe`).
        tabelle.style = .plain
        tabelle.rowSizeStyle = .custom
        tabelle.rowHeight = Seitenleistenvorlage.zeilenhoehe
        tabelle.intercellSpacing = .zero
        tabelle.usesAutomaticRowHeights = false
        tabelle.backgroundColor = .clear
        tabelle.gridStyleMask = []
        tabelle.selectionHighlightStyle = .regular
        tabelle.headerView = nil
        tabelle.focusRingType = .none
        tabelle.allowsEmptySelection = false
        tabelle.allowsMultipleSelection = false
        tabelle.allowsColumnReordering = false
        tabelle.allowsColumnResizing = false
        tabelle.allowsTypeSelect = true
        tabelle.floatsGroupRows = false
        tabelle.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let spalte = NSTableColumn(identifier: Seitenleistenkoordinator.spalte)
        spalte.resizingMask = .autoresizingMask
        tabelle.addTableColumn(spalte)
        tabelle.setAccessibilityLabel(bezeichnung)
        // Die Kennung, an der Dialogprobe und Prüfungen die Leiste finden.
        tabelle.identifier = NSUserInterfaceItemIdentifier("Seitenleiste")
        tabelle.dataSource = context.coordinator
        tabelle.delegate = context.coordinator
        context.coordinator.tabelle = tabelle

        let rolle = NSScrollView()
        rolle.documentView = tabelle
        rolle.hasVerticalScroller = true
        rolle.hasHorizontalScroller = false
        rolle.autohidesScrollers = true
        rolle.drawsBackground = false
        rolle.borderType = .noBorder
        // Kein Einzug vom Fenster her und kein Nachfedern: Die Lage der Zeilen hängt an nichts außer der Tabelle. Oben
        // 10 pt Luft über der ersten Zeile, wie in der Vorlage.
        rolle.automaticallyAdjustsContentInsets = false
        rolle.contentInsets = NSEdgeInsets(top: Seitenleistenvorlage.obenLuft, left: 0, bottom: 0, right: 0)
        rolle.verticalScrollElasticity = .none
        rolle.horizontalScrollElasticity = .none
        uebertragen(context.coordinator)
        return rolle
    }

    func updateNSView(_ rolle: NSScrollView, context: Context) {
        uebertragen(context.coordinator)
    }

    /// Den Stand der Leiste an den Koordinator; der schreibt ihn in die Tabelle — mitten in einer Meldung der Tabelle
    /// erst danach (wie die `Huelltabelle`, sonst meldet AppKit „reentrant operation“).
    private func uebertragen(_ k: Seitenleistenkoordinator) {
        let bindung = $auswahl
        let eintraege = eintraege
        k.gewaehlt = { stelle in
            guard stelle >= 0, stelle < eintraege.count, bindung.wrappedValue != eintraege[stelle] else { return }
            bindung.wrappedValue = eintraege[stelle]
        }
        k.tabelle?.setAccessibilityLabel(bezeichnung)
        k.vormerken(zeilen: eintraege.map { Seitenleistenzeile(name: name($0), symbol: symbol($0), plakette: plakette($0)) },
                    gewaehlt: eintraege.firstIndex(of: auswahl))
    }
}

/// Die Maße der Vorlage (E1120, vermessen bei 2 px je pt), in pt.
enum Seitenleistenvorlage {
    /// Zeilenabstand und Höhe der Wahlfläche.
    static let zeilenhoehe: CGFloat = 32
    /// Schriftgröße von Name und Plakette, regular — gleich dem Text im Formular.
    static let schrift: CGFloat = 13
    /// Einzug der Wahlfläche links und rechts vom Rand der Leiste.
    static let wahlEinzug: CGFloat = 10
    /// Eckradius der Wahlfläche.
    static let wahlEcke: CGFloat = 8
    /// Mitte des Symbols, vom linken Rand der Wahlfläche (Vorlage: Symbole 11,5–16 pt breit, Mitte stets 18,75 pt; die
    /// Symbole von SF tragen links etwas mehr Luft — im Bild stand die Mitte bei 18,75 gesetzt auf 18,2–18,5).
    static let symbolMitte: CGFloat = 19
    /// Beginn des Textfelds, vom linken Rand der Wahlfläche: In der Vorlage beginnt die Schrift bei 36,5 pt; im Bild
    /// begann sie 1,25 pt nach dem Rand des Textfelds (gemessen: Feld bei 34,25, Schrift bei 35,5).
    static let textBeginn: CGFloat = 35.25
    /// Abstand der Plakette vom rechten Rand der Wahlfläche.
    static let plaketteRand: CGFloat = 10
    /// Luft über der ersten Zeile.
    static let obenLuft: CGFloat = 10
}

/// Was eine Zeile der Leiste zeigt.
struct Seitenleistenzeile: Equatable {
    let name: String
    let symbol: String
    let plakette: String?
}

/// Datenquelle und Delegierter der Leiste — ohne Typparameter, nach Zeilennummer (wie der `Huellkoordinator`).
@MainActor
final class Seitenleistenkoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let spalte = NSUserInterfaceItemIdentifier("seitenleiste-spalte")

    weak var tabelle: NSTableView?
    /// Eine Zeile wurde in der Tabelle gewählt (Klick, ↑/↓, Tippen) — schreibt die Bindung.
    var gewaehlt: @MainActor (Int) -> Void = { _ in }
    private var zeilen: [Seitenleistenzeile] = []
    /// Der Koordinator schreibt gerade selbst in die Tabelle — keine Meldung zurück.
    private var uebernimmt = false
    /// Eine Meldung der Tabelle läuft gerade.
    private var imRueckruf = false
    private var vorgemerkt: (zeilen: [Seitenleistenzeile], gewaehlt: Int?)?

    /// Den neuen Stand übernehmen — sofort, oder nach der laufenden Meldung der Tabelle, einmal, mit dem neuesten Stand.
    func vormerken(zeilen neu: [Seitenleistenzeile], gewaehlt soll: Int?) {
        guard imRueckruf else {
            // Ein noch vorgemerkter älterer Stand darf den jetzt angewendeten nicht hinterher überschreiben (R95-03).
            vorgemerkt = nil
            anwenden(neu, soll)
            return
        }
        let schonVorgemerkt = vorgemerkt != nil
        vorgemerkt = (neu, soll)
        guard !schonVorgemerkt else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let stand = self.vorgemerkt else { return }
                self.vorgemerkt = nil
                self.anwenden(stand.zeilen, stand.gewaehlt)
            }
        }
    }

    /// Zeilen und Auswahl in die Tabelle. Neu geladen wird nur, wenn sich die Zahl der Zeilen ändert; ändert sich nur, was
    /// eine Zeile zeigt (eine Plakette), bekommt nur diese Zeile ihre Zelle neu. Die Auswahl wird nur geschrieben, wenn
    /// sie abweicht.
    private func anwenden(_ neu: [Seitenleistenzeile], _ soll: Int?) {
        guard let tabelle else { return }
        uebernimmt = true
        defer { uebernimmt = false }
        if neu.count != zeilen.count {
            zeilen = neu
            tabelle.reloadData()
        } else if neu != zeilen {
            let geaendert = IndexSet(neu.indices.filter { neu[$0] != zeilen[$0] })
            zeilen = neu
            tabelle.reloadData(forRowIndexes: geaendert, columnIndexes: IndexSet(integer: 0))
        }
        if let soll, soll < tabelle.numberOfRows, tabelle.selectedRow != soll {
            tabelle.selectRowIndexes(IndexSet(integer: soll), byExtendingSelection: false)
            tabelle.scrollRowToVisible(soll)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { zeilen.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < zeilen.count else { return nil }
        let zelle = (tableView.makeView(withIdentifier: Seitenleistenzelle.kennung, owner: nil) as? Seitenleistenzelle)
            ?? Seitenleistenzelle()
        zelle.setzen(zeilen[row])
        return zelle
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        (tableView.makeView(withIdentifier: Seitenleistenreihe.kennung, owner: nil) as? Seitenleistenreihe)
            ?? Seitenleistenreihe()
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        row < zeilen.count ? zeilen[row].name : nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !uebernimmt, let tabelle = notification.object as? NSTableView, tabelle.selectedRow >= 0 else { return }
        imRueckruf = true
        gewaehlt(tabelle.selectedRow)
        imRueckruf = false
    }
}

/// Eine Zeile der Leiste mit der Wahlfläche der Vorlage — gezeichnet in `drawSelection(in:)` (Muster von Apple DTS,
/// Forum 836753): eine Zeile hoch, 10 pt eingerückt, Ecken 8 pt.
///
/// **Betont nach AppKit (E1120):** Blau mit weißem Text und Symbol nur, solange die Tabelle der Leiste den Fokus hat
/// und das Blatt vorn ist; steht der Fokus im Formular oder ist das Fenster nicht vorn, grau mit Text und Symbol in der
/// normalen Textfarbe. Entscheidung des Nutzers (E1120): „Sie sollte dann grau werden. Blau signalisiert
/// immer die aktive Eingabe.“ Die Betonung setzt AppKit selbst (`isEmphasized` → `interiorBackgroundStyle` →
/// `backgroundStyle` der Zelle); die Zeile liest sie nur.
///
/// Ohne Vibranz (`allowsVibrancy` falsch): Die Leiste steht unter SwiftUI in einer vibranten Erscheinung; mit Vibranz
/// mischte AppKit die Fläche mit dem Glas darunter, und sie stünde nicht in der Farbe der Vorlage.
final class Seitenleistenreihe: NSTableRowView {
    static let kennung = NSUserInterfaceItemIdentifier("seitenleiste-reihe")

    init() {
        super.init(frame: .zero)
        identifier = Self.kennung
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var allowsVibrancy: Bool { false }

    override func drawSelection(in dirtyRect: NSRect) {
        let flaeche = bounds.insetBy(dx: Seitenleistenvorlage.wahlEinzug, dy: 0)
        let farbe: NSColor = isEmphasized ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor
        farbe.setFill()
        NSBezierPath(roundedRect: flaeche, xRadius: Seitenleistenvorlage.wahlEcke, yRadius: Seitenleistenvorlage.wahlEcke)
            .fill()
    }
}

/// Eine Zeile: Symbol, Name, rechts die Plakette in Ziffern gleicher Breite — Maße und Schrift nach der Vorlage, alles
/// mittig in der Höhe. Die Höhe gibt die Tabelle vor, nicht der Inhalt.
final class Seitenleistenzelle: NSTableCellView {
    static let kennung = NSUserInterfaceItemIdentifier("seitenleiste-zelle")
    private let plakettenfeld = NSTextField(labelWithString: "")

    override var allowsVibrancy: Bool { false }

    init() {
        super.init(frame: .zero)
        identifier = Self.kennung
        let v = Seitenleistenvorlage.self
        let bild = NSImageView()
        bild.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: v.schrift, weight: .regular, scale: .medium)
        bild.imageScaling = .scaleNone
        let text = NSTextField(labelWithString: "")
        text.font = .systemFont(ofSize: v.schrift, weight: .regular)
        text.lineBreakMode = .byTruncatingTail
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        plakettenfeld.font = .monospacedDigitSystemFont(ofSize: v.schrift, weight: .regular)
        plakettenfeld.alignment = .right
        plakettenfeld.setContentCompressionResistancePriority(.required, for: .horizontal)
        plakettenfeld.setContentHuggingPriority(.required, for: .horizontal)
        // Die Zeile ist ein Element der Bedienungshilfen mit Name und Plakette („Kommentar, •“); Symbol, Name und
        // Plakette darin sind keine eigenen — sonst hörte man nur den Namen (Diagnose der Dialogprobe, R-BG4-04).
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
        bild.setAccessibilityElement(false)
        text.setAccessibilityElement(false)
        plakettenfeld.setAccessibilityElement(false)
        for ansicht in [bild, text, plakettenfeld] as [NSView] {
            ansicht.translatesAutoresizingMaskIntoConstraints = false
            addSubview(ansicht)
        }
        imageView = bild
        textField = text
        NSLayoutConstraint.activate([
            bild.centerXAnchor.constraint(equalTo: leadingAnchor, constant: v.wahlEinzug + v.symbolMitte),
            bild.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: v.wahlEinzug + v.textBeginn),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            plakettenfeld.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 6),
            plakettenfeld.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(v.wahlEinzug + v.plaketteRand)),
            plakettenfeld.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        farbenSetzen()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Auf der betonten Wahlfläche weiß, sonst deckend in Textfarbe (`textColor`: hell schwarz, dunkel weiß; die Vorlage
    /// zeichnet Text und Symbole deckend schwarz, `labelColor` stünde in der vibranten Erscheinung der Leiste nur zu 70 %);
    /// Symbol einfarbig wie der Text, die Plakette gedämpft.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { farbenSetzen() }
    }

    private func farbenSetzen() {
        let betont = backgroundStyle == .emphasized
        textField?.textColor = betont ? .alternateSelectedControlTextColor : .textColor
        imageView?.contentTintColor = betont ? .alternateSelectedControlTextColor : .textColor
        plakettenfeld.textColor = betont ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }

    func setzen(_ zeile: Seitenleistenzeile) {
        imageView?.image = NSImage(systemSymbolName: zeile.symbol, accessibilityDescription: nil)
        textField?.stringValue = zeile.name
        plakettenfeld.stringValue = zeile.plakette ?? ""
        setAccessibilityLabel(zeile.plakette.map { "\(zeile.name), \($0)" } ?? zeile.name)
    }
}
