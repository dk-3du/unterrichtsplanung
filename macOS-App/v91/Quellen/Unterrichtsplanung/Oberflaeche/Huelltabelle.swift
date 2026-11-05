// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

// Die Hülle für die Tabellen der Lernendenverwaltung (v91, BC8; E1020, E1025): eine `NSTableView` mit eigener
// Datenquelle, die Zellen in SwiftUI. SwiftUIs `Table` leert die Auswahl, wenn eine Mehrfachauswahl durch eine einzige,
// schon gewählte Zeile ersetzt wird — beim Klick, mit ↓/↑ und über die Bedienungshilfen; die reine `NSTableView` wählt
// in jedem dieser Fälle richtig (Klassenmessung 2, S0, macOS 26.7.2 und 27.2).
//
// Die Auswahl gehört der Tabelle: Die Bindung erfährt sie aus `tableViewSelectionDidChange`, und nur eine Änderung von
// außen schreibt die Tabelle nach. Ebenso die Ordnung: Ein Kopfklick ordnet über die Ordnungsvorlagen von AppKit, die
// Bindung erfährt die neue Folge. Stil, Zeilenhöhe, Abstände, Breiten und Köpfe folgen der Ist-Aufnahme der SwiftUI-Tabelle
// (BC8).

/// Was die Tabelle wählen lässt.
enum Huellwahl<ID: Hashable> {
    /// Keine Zeile wählbar — wie `Table` ohne `selection`.
    case keine
    /// Höchstens eine.
    case eine(Binding<ID?>)
    /// Mehrere: ⌘-Klick, ⇧-Klick, ⌘A, ⇧↑/⇧↓.
    case mehrere(Binding<Set<ID>>)
}

/// Der Stil, wie ihn SwiftUI der Tabelle gibt (Ist-Aufnahme).
enum Huellstil {
    /// `.tableStyle(.bordered(alternatesRowBackgrounds: true))`: volle Breite, ein Linienrand.
    case umrandet
    /// Die Vorgabe: eingerückt, ohne Rand.
    case vorgabe
}

/// Eine Spalte: Titel, die Ordnung eines Kopfklicks (ohne: der Kopf ordnet nicht), die Breite, der Text der Zelle für die
/// Tippwahl und die Zelle in SwiftUI. Den Text meldet SwiftUIs Tabelle von selbst (der erste Text der Zelle); die Hülle
/// bekommt ihn ausdrücklich — ohne ihn überspringt die Tippwahl die Spalte.
struct Huellspalte<Zeile> {
    enum Breite: Equatable {
        /// Wie `TableColumn` ohne `.width`: ab 10 pt, wächst mit der Tabelle.
        case frei
        /// Wie `.width(_:)`: fest, auch von Hand nicht zu ändern.
        case fest(CGFloat)
        /// Wie `.width(min:ideal:max:)`.
        case bereich(min: CGFloat?, ideal: CGFloat?, max: CGFloat?)
    }

    let titel: String
    let ordnen: KeyPathComparator<Zeile>?
    let breite: Breite
    let text: (@MainActor (Zeile) -> String)?
    /// Die Zelle trägt eine Steuerung (Menü, Knopf): Ein Klick hier lässt eine Mehrfachauswahl, wie AppKit sie hält
    /// (E1029, Ausnahme).
    let bedienbar: Bool
    let zelle: @MainActor (Zeile) -> AnyView

    init<Inhalt: View>(_ titel: String, ordnen: KeyPathComparator<Zeile>? = nil, breite: Breite = .frei,
                       text: (@MainActor (Zeile) -> String)? = nil, bedienbar: Bool = false,
                       @ViewBuilder zelle: @escaping @MainActor (Zeile) -> Inhalt) {
        self.titel = titel
        self.ordnen = ordnen
        self.breite = breite
        self.text = text
        self.bedienbar = bedienbar
        self.zelle = { AnyView(zelle($0)) }
    }
}

/// Die Tabelle selbst. `ordnung` wie `sortOrder` von `Table`: Ein Kopfklick setzt die Folge, geordnet wird außerhalb —
/// die Zeilen kommen schon in der Folge der Anzeige.
struct Huelltabelle<Zeile: Identifiable>: NSViewRepresentable where Zeile.ID: Hashable {
    let zeilen: [Zeile]
    let wahl: Huellwahl<Zeile.ID>
    let ordnung: Binding<[KeyPathComparator<Zeile>]>?
    let kopf: Bool
    let stil: Huellstil
    let spalten: [Huellspalte<Zeile>]

    init(_ zeilen: [Zeile], wahl: Huellwahl<Zeile.ID> = .keine, ordnung: Binding<[KeyPathComparator<Zeile>]>? = nil,
         kopf: Bool = true, stil: Huellstil = .vorgabe, spalten: [Huellspalte<Zeile>]) {
        self.zeilen = zeilen
        self.wahl = wahl
        self.ordnung = ordnung
        self.kopf = kopf
        self.stil = stil
        self.spalten = spalten
    }

    func makeCoordinator() -> Huellkoordinator { Huellkoordinator() }

    /// Die Spalte, deren Kopf hervorgehoben steht (E498): die, nach der die Ordnung vorn ordnet — `pfade` sind die
    /// Schlüsselpfade der Spalten, `nil` bei einer Spalte ohne Ordnung. Ohne Ordnung keine.
    nonisolated static func vorneStelle(_ ordnung: [KeyPathComparator<Zeile>], _ pfade: [PartialKeyPath<Zeile>?]) -> Int? {
        guard let vorn = ordnung.first?.keyPath else { return nil }
        return pfade.firstIndex { $0 == vorn }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tabelle = Huellansicht()
        // Ist-Aufnahme (26.7.2): umrandet = volle Breite mit Linienrand, sonst eingerückt; beide mit abwechselnden Zeilen,
        // Zeilenhöhe nach dem Inhalt ab 24 pt, Abstand 17 × 0, gleichmäßige Spaltenanpassung, Breiten von Hand, kein
        // Umordnen der Spalten, Tippwahl. Die Zeilenhöhe misst die Hülle selbst (`zeilenhoehe`) und setzt sie fest: Mit
        // `usesAutomaticRowHeights` vermaß AppKit nach jeder Auswahl die Zellen über Auto Layout neu — im Profil der
        // Handprobe gut 1 s Mehrarbeit auf 12 s, die Auswahl wirkte träge.
        tabelle.style = stil == .umrandet ? .fullWidth : .inset
        tabelle.usesAlternatingRowBackgroundColors = true
        tabelle.usesAutomaticRowHeights = false
        tabelle.rowHeight = 24
        tabelle.intercellSpacing = NSSize(width: 17, height: 0)
        tabelle.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tabelle.allowsColumnReordering = false
        tabelle.allowsColumnResizing = true
        tabelle.allowsColumnSelection = false
        tabelle.allowsEmptySelection = true
        if case .mehrere = wahl { tabelle.allowsMultipleSelection = true } else { tabelle.allowsMultipleSelection = false }
        tabelle.allowsTypeSelect = true
        tabelle.floatsGroupRows = false
        if !kopf { tabelle.headerView = nil }
        for (stelle, spalte) in spalten.enumerated() {
            let s = NSTableColumn(identifier: Self.kennung(stelle))
            s.title = spalte.titel
            s.headerCell.alignment = .left
            switch spalte.breite {
            case .frei:
                s.minWidth = 10
                s.maxWidth = .infinity
            case .fest(let b):
                s.width = b
                s.minWidth = b
                s.maxWidth = b
                s.resizingMask = []
            case .bereich(let min, let ideal, let max):
                s.minWidth = min ?? 10
                s.maxWidth = max ?? .infinity
                s.width = ideal ?? min ?? 100
            }
            if spalte.ordnen != nil {
                s.sortDescriptorPrototype = NSSortDescriptor(key: Self.kennung(stelle).rawValue, ascending: true)
            }
            tabelle.addTableColumn(s)
        }
        tabelle.dataSource = context.coordinator
        tabelle.delegate = context.coordinator
        tabelle.bedienbareSpalten = IndexSet(spalten.indices.filter { spalten[$0].bedienbar })
        context.coordinator.tabelle = tabelle
        context.coordinator.kopfschrift = tabelle.tableColumns.first?.headerCell.font
        tabelle.erscheinungGeaendert = { [weak k = context.coordinator] in k?.koepfeSetzen() }
        // Rollt die Hand mit der Tastatur, gilt die Zeile nicht mehr, wie beim Rollen mit Rad oder Trackpad (U1-04).
        tabelle.tastaturGerollt = { [weak k = context.coordinator] in k?.imBild = nil }

        let rolle = NSScrollView()
        rolle.documentView = tabelle
        rolle.hasVerticalScroller = true
        rolle.hasHorizontalScroller = true
        rolle.autohidesScrollers = true
        rolle.drawsBackground = false
        rolle.borderType = stil == .umrandet ? .lineBorder : .noBorder
        // Ändert sich danach der Ausschnitt, bleibt eine von Hand allein gewählte Zeile im Bild (`ausschnittGeaendert`).
        rolle.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(Huellkoordinator.ausschnittGeaendert(_:)),
                                               name: NSView.frameDidChangeNotification, object: rolle.contentView)
        // Rollt die Hand selbst, gilt die Zeile nicht mehr (R8a-04).
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Huellkoordinator.selbstGerollt(_:)),
                                               name: NSScrollView.willStartLiveScrollNotification, object: rolle)
        // Die Köpfe tragen die Akzentfarbe fest aufgelöst; wechselt sie in den Systemeinstellungen, neu setzen (U1-03).
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Huellkoordinator.farbenGeaendert(_:)),
                                               name: NSColor.systemColorsDidChangeNotification, object: nil)
        return rolle
    }

    func updateNSView(_ rolle: NSScrollView, context: Context) {
        let k = context.coordinator
        k.zahl = { [zeilen] in zeilen.count }
        k.zelle = { [zeilen, spalten] stelle, zeile in
            guard zeile < zeilen.count, stelle < spalten.count else { return AnyView(EmptyView()) }
            return spalten[stelle].zelle(zeilen[zeile])
        }
        k.tipptext = { [zeilen, spalten] stelle, zeile in
            guard zeile < zeilen.count, stelle < spalten.count else { return nil }
            return spalten[stelle].text?(zeilen[zeile])
        }
        k.waehlbar = { if case .keine = wahl { false } else { true } }()
        k.wahlGemeldet = { [zeilen, wahl] gewaehlt in
            let ids = gewaehlt.compactMap { $0 < zeilen.count ? zeilen[$0].id : nil }
            switch wahl {
            case .keine: break
            case .eine(let b): if b.wrappedValue != ids.first { b.wrappedValue = ids.first }
            case .mehrere(let b): if b.wrappedValue != Set(ids) { b.wrappedValue = Set(ids) }
            }
        }
        k.ordnungGemeldet = { [spalten, ordnung] vorlagen in
            guard let ordnung else { return }
            let neu: [KeyPathComparator<Zeile>] = vorlagen.compactMap { v in
                guard let stelle = v.key.flatMap(Self.stelle), stelle < spalten.count,
                      var vergleicher = spalten[stelle].ordnen else { return nil }
                vergleicher.order = v.ascending ? .forward : .reverse
                return vergleicher
            }
            if neu != ordnung.wrappedValue { ordnung.wrappedValue = neu }
        }
        k.anwenden = { tabelle, k in anwenden(tabelle, k) }
        guard let tabelle = rolle.documentView as? NSTableView else { return }
        // Ruft SwiftUI dies mitten in einer Meldung der Tabelle (Auswahl, Ordnung), wartet das Nachschreiben bis danach —
        // sonst meldete AppKit „reentrant operation“.
        if k.imRueckruf { k.spaeterAnwenden() } else { anwenden(tabelle, k) }
    }

    private func anwenden(_ tabelle: NSTableView, _ k: Huellkoordinator) {
        // Die Köpfe: Ordnet eine Spalte vorn, steht ihr Titel halbfett in der Akzentfarbe (E498).
        let vorn = ordnung.flatMap { Self.vorneStelle($0.wrappedValue, spalten.map { $0.ordnen?.keyPath }) }
        let titel = spalten.map(\.titel)
        if !k.koepfeGesetzt || vorn != k.vorn || titel != k.kopftitel {
            k.vorn = vorn
            k.kopftitel = titel
            k.koepfeGesetzt = true
            k.koepfeSetzen()
        }
        // Die Zeilen: neu geladen nur, wenn sich die Folge der Kennungen ändert; sonst bekommen alle vorhandenen Zellen ihren
        // neuen Inhalt (Stand, Farbe, Handlungen) — auch die, die AppKit über den Ausschnitt hinaus fürs Rollen vorbereitet
        // hält; sie zeigten beim Hineinrollen sonst den Stand von vorher, und ihr Menü schriebe mit alten Werten (U1-01).
        let kennungen = zeilen.map { AnyHashable($0.id) }
        k.uebernimmt = true
        if kennungen != k.kennungen {
            k.kennungen = kennungen
            if !zeilen.isEmpty {
                let hoehe = zeilenhoehe(k)
                if tabelle.rowHeight != hoehe { tabelle.rowHeight = hoehe }
            }
            tabelle.reloadData()
        } else {
            tabelle.enumerateAvailableRowViews { zeilenansicht, zeile in
                for stelle in 0..<tabelle.numberOfColumns {
                    (zeilenansicht.view(atColumn: stelle) as? Huellzelle)?.setzen(k.zelle(stelle, zeile))
                }
            }
        }
        // Die Ordnung nach außen: die Pfeile im Kopf.
        let vorlagen: [NSSortDescriptor] = (ordnung?.wrappedValue ?? []).compactMap { v in
            spalten.firstIndex { $0.ordnen?.keyPath == v.keyPath }
                .map { NSSortDescriptor(key: Self.kennung($0).rawValue, ascending: v.order == .forward) }
        }
        if tabelle.sortDescriptors != vorlagen { tabelle.sortDescriptors = vorlagen }
        // Die Auswahl von außen.
        let gewaehlt: Set<AnyHashable>
        switch wahl {
        case .keine: gewaehlt = []
        case .eine(let b): gewaehlt = b.wrappedValue.map { [AnyHashable($0)] } ?? []
        case .mehrere(let b): gewaehlt = Set(b.wrappedValue.map { AnyHashable($0) })
        }
        let soll = IndexSet(kennungen.indices.filter { gewaehlt.contains(kennungen[$0]) })
        if tabelle.selectedRowIndexes != soll { tabelle.selectRowIndexes(soll, byExtendingSelection: false) }
        k.uebernimmt = false
    }

    /// Die Höhe einer Zeile: die größte Höhe, die eine Zelle der ersten Zeile mit ihrem Inhalt braucht, mindestens 24 pt —
    /// so hoch, wie SwiftUI die Zeile macht (einzeilig 24, zweizeilig 39). Gemessen an einer Zelle außerhalb der Tabelle,
    /// bei jedem Laden mit neuen Kennungen, nicht je Zeile: Alle Zeilen einer Tabelle sind gleich gebaut (E1027).
    private func zeilenhoehe(_ k: Huellkoordinator) -> CGFloat {
        var hoehe: CGFloat = 24
        for stelle in 0..<spalten.count {
            let probe = NSHostingView(rootView: Huellzelle.wurzel(k.zelle(stelle, 0), hervorgehoben: false))
            hoehe = max(hoehe, probe.fittingSize.height.rounded(.up))
        }
        return hoehe
    }

    static func kennung(_ stelle: Int) -> NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("huellspalte-\(stelle)") }

    static func stelle(_ kennung: String) -> Int? {
        kennung.hasPrefix("huellspalte-") ? Int(kennung.dropFirst("huellspalte-".count)) : nil
    }

}

/// Die AppKit-Tabelle der Hülle — eine eigene Klasse, damit Probe und Messung sie erkennen. Bei einem Wechsel von hell
/// und dunkel setzt sie die Köpfe neu, deren Farben fest aufgelöst sind.
final class Huellansicht: NSTableView {
    var erscheinungGeaendert: (() -> Void)?
    /// Die Tabelle rollt über die Tastatur, ohne die Auswahl zu ändern: Bild ↑ und Bild ↓, Pos1 und Ende (U1-04). ↓ und ↑
    /// wählen dagegen eine andere Zeile, die im Bild bleibt (E931).
    var tastaturGerollt: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        erscheinungGeaendert?()
    }

    /// Ein Klick ohne Taste auf eine von mehreren Gewählten lässt nur diese Zeile gewählt, gleich nach dem Loslassen (E1029).
    /// AppKit wartet dafür die Doppelklickzeit ab (gemessen 506–581 ms), weil ein Doppelklick alle Gewählten öffnen
    /// könnte; die Tabellen der Lernendenverwaltung haben keine Doppelklick-Handlung und kein Ziehen von Zeilen an einen
    /// anderen Ort. Zieht man von einer Gewählten aus eine Auswahl auf, wählt die Hülle nicht selbst (`vorschlagSeitKlick`).
    /// Die Spalten mit einer Steuerung (Menü „Stand“, „Zurückholen“) nimmt der Monitor aus (`bedienbar`, unten); dort bleibt
    /// die Auswahl, wie AppKit sie hält. Die Menübeobachtung ist nur eine Rückfallebene für eine Steuerung ohne Kennzeichen,
    /// unter 27.2 käme sie zu spät. Kommen Doppelklick, Ziehen von Zeilen an einen anderen Ort oder andere Steuerungen in
    /// Zellen einer Tabelle mit Mehrfachauswahl hinzu, ist das neu zu messen. Folge: Ein Doppelklick auf eine von mehreren
    /// Gewählten lässt nur diese Zeile gewählt.
    ///
    /// Über einen Ereignismonitor, nicht durch Überschreiben von `mouseDown`: Schon das bloße Überschreiben (nur `super`)
    /// lässt einen ⇧-Klick unter macOS 27.2 anders wählen als AppKit (Klassenmessung 2, K6, auch an einer reinen
    /// `NSTableView`). Der Monitor merkt sich den Klick und wählt, sobald die Ereignisschleife wieder im Standardmodus ist —
    /// erst nach dem Loslassen, denn solange AppKit die Maus verfolgt, läuft sie in einem eigenen Modus.
    ///
    /// Spalten mit einer Steuerung (`Huellspalte.bedienbar`) sind ausgenommen: Unter 27.2 öffnet SwiftUI das Menü einer
    /// Zelle erst nach diesem Augenblick, ein Blick auf das Menü käme also zu spät (K6-Messung, St1/St4).
    var bedienbareSpalten = IndexSet()
    private var monitor: Any?
    /// Hat AppKit seit dem letzten Klick, den der Monitor vormerkt, eine Auswahl vorgeschlagen? Beim Aufziehen schlägt es
    /// Zwischenstände vor, beim bloßen Klick auf eine von mehreren Gewählten nichts (Klassenmessung 2, K1–K4 und Z1–Z4,
    /// gemessen unter macOS 26.7.2; unter 27 zeigen es die Fensterfälle der Probe „vor der halben Doppelklickzeit“). Endet
    /// ein Aufziehen auf genau den Zeilen von vorher, sähe die Hülle sonst keine Änderung und wählte die gedrückte Zeile
    /// allein (R8a-03). Ein Ereignismonitor sieht das Ziehen nicht: Die Mausverfolgung der Tabelle holt die Ereignisse
    /// selbst.
    var vorschlagSeitKlick = false

    // Auch wenn die Tabelle mit dem Fenster freigegeben wird, ohne vorher herausgenommen zu werden (R8a-10).
    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] ereignis in
            MainActor.assumeIsolated {
                if ereignis.type == .keyDown { self?.rolltasteVormerken(ereignis) } else { self?.klickVormerken(ereignis) }
            }
            return ereignis
        }
    }

    /// Bild ↑ (116), Bild ↓ (121), Pos1 (115) und Ende (119) an dieser Tabelle oder an einem Ersthelfer in ihr: Danach rollt ein
    /// Größenwechsel nicht mehr zur allein gewählten Zeile zurück (U1-04). Der Monitor sieht die Taste, bevor die Tabelle rollt.
    /// Gemessen unter macOS 26.7.2: Bild ↓ ließ die Hülle schon vorher los, Ende nicht; Pos1 und Bild ↑ sind nicht gemessen.
    /// Andere Belegungen (⌃V, eigene Tastenbelegungen) und das Rollen über VoiceOver sieht der Monitor nicht.
    private func rolltasteVormerken(_ ereignis: NSEvent) {
        guard let fenster = window, ereignis.window === fenster, let ersthelfer = fenster.firstResponder as? NSView,
              ersthelfer === self || ersthelfer.isDescendant(of: self),
              [115, 116, 119, 121].contains(ereignis.keyCode) else { return }
        tastaturGerollt?()
    }

    private func klickVormerken(_ ereignis: NSEvent) {
        guard let fenster = window, ereignis.window === fenster, ereignis.clickCount == 1,
              ereignis.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty,
              let rahmen = fenster.contentView?.superview else { return }
        let punkt = convert(ereignis.locationInWindow, from: nil)
        // `hitTest` nimmt den Punkt im System der Oberansicht, beim Rahmen des Fensters also im Fenster. Im System des Inhalts
        // traf der Test im Blatt den Kopf der Tabelle: Der Inhalt eines Blatts ist eine gespiegelte SwiftUI-Ansicht
        // (Z-BC8a-03).
        guard visibleRect.contains(punkt), let getroffen = rahmen.hitTest(ereignis.locationInWindow),
              getroffen === self || getroffen.isDescendant(of: self) else { return }
        let zeile = row(at: punkt), spalte = column(at: punkt)
        guard zeile >= 0, !bedienbareSpalten.contains(spalte), selectedRowIndexes.count > 1,
              selectedRowIndexes.contains(zeile) else { return }
        let menue = Menuebeobachtung()
        // Gewählt wird nur, wenn AppKit die Auswahl beim Klick stehen ließ — nicht etwa nach einem Ziehen, das sie aufzog
        // (R8a-03).
        let vorher = selectedRowIndexes
        vorschlagSeitKlick = false
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                menue.ende()
                guard let self, !menue.offen, !self.vorschlagSeitKlick, self.selectedRowIndexes == vorher else { return }
                // AppKit hat für diesen Klick beim Loslassen seine eigene Wahl nach der Doppelklickzeit vorgemerkt. Sie wäre
                // erledigt und käme sonst noch nach einem schnellen ⌘A und wählte wieder nur diese Zeile (Z-BC8a-04). Das
                // nimmt alle Vormerkungen an der Tabelle zurück; nach diesem Klick ist es nur diese — gemessen merkt AppKit an
                // der Tabelle ab dem Klick nur `_delayedSelectRow` vor (Klassenmessung 2, U1-02, macOS 26.7.2), und die
                // Tippwahl geht danach weiter. Vor der eigenen Wahl, damit, was sie selbst vormerkt, bleibt (R8a-05).
                NSObject.cancelPreviousPerformRequests(withTarget: self)
                self.selectRowIndexes(IndexSet(integer: zeile), byExtendingSelection: false)
            }
        }
    }
}

/// Merkt, ob während eines Klicks ein Menü aufging.
@MainActor
private final class Menuebeobachtung {
    private(set) var offen = false
    private var beobachter: NSObjectProtocol?

    init() {
        // Ohne Warteschlange: gleich beim Senden, also noch während des Klicks.
        beobachter = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil,
                                                            queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.offen = true }
        }
    }

    func ende() {
        if let beobachter { NotificationCenter.default.removeObserver(beobachter) }
        beobachter = nil
    }
}

/// Datenquelle und Delegat, ohne Typparameter: Die Hülle reicht ihre Zeilen, Zellen und Meldewege als Funktionen herein.
@MainActor
final class Huellkoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    weak var tabelle: NSTableView?
    var zahl: @MainActor () -> Int = { 0 }
    var zelle: @MainActor (Int, Int) -> AnyView = { _, _ in AnyView(EmptyView()) }
    var tipptext: @MainActor (Int, Int) -> String? = { _, _ in nil }
    var waehlbar = true
    var wahlGemeldet: @MainActor (IndexSet) -> Void = { _ in }
    var ordnungGemeldet: @MainActor ([NSSortDescriptor]) -> Void = { _ in }
    /// Den Stand der Hülle in die Tabelle schreiben — nach jedem `updateNSView` die neueste Fassung.
    var anwenden: (@MainActor (NSTableView, Huellkoordinator) -> Void)?
    /// Die Titel der Köpfe, die Spalte, deren Kopf hervorgehoben steht, und die Schrift der Köpfe von AppKit.
    var kopftitel: [String] = []
    var vorn: Int?
    var kopfschrift: NSFont?
    var koepfeGesetzt = false
    private var vorgemerkt = false
    /// Die Folge der Kennungen beim letzten Laden.
    var kennungen: [AnyHashable] = []
    /// Die Hülle schreibt gerade selbst in die Tabelle — keine Meldung zurück.
    var uebernimmt = false
    /// Eine Meldung der Tabelle läuft gerade.
    var imRueckruf = false
    /// Die Zeile, die eine Wahl von Hand zuletzt allein gewählt hat; `nil` nach einer Wahl mehrerer oder keiner.
    var imBild: Int?

    /// Der Ausschnitt der Tabelle hat sich geändert. Steht die zuletzt von Hand allein gewählte Zeile noch allein gewählt,
    /// rollt die Tabelle sie ins Bild. Mit der Wahl einer Person tritt die höhere Leiste dieser Person an die Stelle der
    /// Sammelleiste, und der Ausschnitt schrumpft, nachdem AppKit zur Zeile gerollt hat. Ohne dies stünde etwa nach ⌘A und ↓
    /// die gewählte letzte Zeile unter dem Rand (E931–E934). Der frühere Umweg des Blatts wählte und rollte erst nach dem
    /// Umbau.
    @objc func ausschnittGeaendert(_ meldung: Notification) {
        guard let zeile = imBild, let tabelle, tabelle.selectedRowIndexes == IndexSet(integer: zeile) else { return }
        tabelle.scrollRowToVisible(zeile)
    }

    /// Die Hand rollt selbst mit Rad, Trackpad, Rollbalken oder Bild ↓ (gemessen unter macOS 26.7.2): Ein späterer
    /// Größenwechsel rollt nicht zur Gewählten zurück (R8a-04). Die übrigen Rolltasten meldet die Tabelle (`tastaturGerollt`,
    /// U1-04).
    @objc func selbstGerollt(_ meldung: Notification) {
        imBild = nil
    }

    /// Die Systemfarben wechselten (Akzentfarbe): die Köpfe neu (U1-03).
    @objc func farbenGeaendert(_ meldung: Notification) {
        if koepfeGesetzt { koepfeSetzen() }
    }

    /// Nach der laufenden Meldung der Tabelle, einmal, mit dem dann neuesten Stand.
    func spaeterAnwenden() {
        guard !vorgemerkt else { return }
        vorgemerkt = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.vorgemerkt = false
                if let tabelle = self.tabelle { self.anwenden?(tabelle, self) }
            }
        }
    }

    /// Die Köpfe, wie SwiftUI sie setzt (Ist-Aufnahme): die Schrift des Kopfes (11 pt), die Farbe der Beschriftung fest für
    /// die Darstellung der Tabelle aufgelöst; ordnet die Spalte vorn, halbfett und in der Akzentfarbe (E498). Nicht
    /// `NSFont.systemFont` (läuft anders) und keine dynamische Farbe (der Kopf zeichnet sie gedämpft): Beides wich im Abbild
    /// ab.
    func koepfeSetzen() {
        guard let tabelle else { return }
        let grund = kopfschrift ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let halbfett = NSFont(descriptor: grund.fontDescriptor.addingAttributes(
            [.traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.semibold]]), size: grund.pointSize) ?? grund
        var text = NSColor.labelColor, akzent = NSColor.controlAccentColor
        tabelle.effectiveAppearance.performAsCurrentDrawingAppearance {
            text = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
            akzent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        }
        for (stelle, s) in tabelle.tableColumns.enumerated() where stelle < kopftitel.count {
            s.headerCell.attributedStringValue = NSAttributedString(string: kopftitel[stelle], attributes: [
                .font: stelle == vorn ? halbfett : grund,
                .foregroundColor: stelle == vorn ? akzent : text,
            ])
        }
        tabelle.headerView?.needsDisplay = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { zahl() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let stelle = tableView.tableColumns.firstIndex(of: tableColumn) else { return nil }
        let z = (tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? Huellzelle)
            ?? Huellzelle(kennung: tableColumn.identifier)
        z.setzen(zelle(stelle, row))
        return z
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let kennung = NSUserInterfaceItemIdentifier("huellzeile")
        let z = (tableView.makeView(withIdentifier: kennung, owner: nil) as? Huellzeile) ?? Huellzeile()
        z.identifier = kennung
        z.eingerueckt = tableView.effectiveStyle == .inset
        return z
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard let tableColumn, let stelle = tableView.tableColumns.firstIndex(of: tableColumn) else { return nil }
        return tipptext(stelle, row)
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        (tableView as? Huellansicht)?.vorschlagSeitKlick = true
        return waehlbar ? proposed : []
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !uebernimmt, let tabelle = notification.object as? NSTableView else { return }
        imBild = tabelle.selectedRowIndexes.count == 1 ? tabelle.selectedRow : nil
        imRueckruf = true
        wahlGemeldet(tabelle.selectedRowIndexes)
        imRueckruf = false
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !uebernimmt else { return }
        imRueckruf = true
        ordnungGemeldet(tableView.sortDescriptors)
        imRueckruf = false
    }
}

/// Eine Zeile. Im eingerückten Stil rundet AppKit die Auswahl jeder Zeile für sich; SwiftUIs Tabelle verbindet
/// aneinanderliegende gewählte Zeilen zu einem Block (Klassenmessung 2, BC8, Abbild im Schlüsselfenster). Die Fuge wird
/// darum in der Farbe der Auswahl gefüllt, 10 pt eingerückt wie die Auswahl selbst.
final class Huellzeile: NSTableRowView {
    var eingerueckt = false

    override func drawSelection(in dirtyRect: NSRect) {
        super.drawSelection(in: dirtyRect)
        guard eingerueckt, selectionHighlightStyle != .none, isPreviousRowSelected || isNextRowSelected else { return }
        (isEmphasized ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
        let breite = bounds.insetBy(dx: 10, dy: 0)
        let oben = isFlipped ? bounds.minY : bounds.midY
        let unten = isFlipped ? bounds.midY : bounds.minY
        if isPreviousRowSelected { NSRect(x: breite.minX, y: oben, width: breite.width, height: bounds.height / 2).fill() }
        if isNextRowSelected { NSRect(x: breite.minX, y: unten, width: breite.width, height: bounds.height / 2).fill() }
    }

    override var isPreviousRowSelected: Bool { didSet { if oldValue != isPreviousRowSelected { needsDisplay = true } } }
    override var isNextRowSelected: Bool { didSet { if oldValue != isNextRowSelected { needsDisplay = true } } }
}

/// Eine Zelle: SwiftUI in einer `NSHostingView`. Gewählt und hervorgehoben (Schlüsselfenster) bekommt der Inhalt die
/// erhöhte Prominenz wie in SwiftUIs Tabelle — Text und Zeichen hell auf der Akzentfläche. Knöpfe ohne eigenen Stil
/// stehen randlos wie in SwiftUIs Tabellenzellen (Ist-Aufnahme). Die `NSHostingView` folgt dem Rahmen der Zelle ohne Auto
/// Layout und meldet keine eigene Größe: Sonst rechnete AppKit bei jedem neuen Inhalt Constraints und Zeilenhöhen neu.
/// Sie ist eine eigene Wurzel: Umgebung von außen (`.disabled`, Schrift, `@Environment`) kommt in der Zelle nicht an — eine
/// Zelle bekommt alles als Wert, und eine Sperre der ganzen Tabelle gehört an die Hülle, nicht darüber (U1-08).
final class Huellzelle: NSTableCellView {
    private var inhalt = AnyView(EmptyView())
    private let wirt = NSHostingView(rootView: AnyView(EmptyView()))

    init(kennung: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = kennung
        wirt.sizingOptions = []
        wirt.autoresizingMask = [.width, .height]
        wirt.frame = bounds
        addSubview(wirt)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht aus einer Datei") }

    func setzen(_ neu: AnyView) {
        inhalt = neu
        erneuern()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { if oldValue != backgroundStyle { erneuern() } }
    }

    private func erneuern() {
        wirt.rootView = Self.wurzel(inhalt, hervorgehoben: backgroundStyle == .emphasized)
    }

    /// Der Inhalt, wie SwiftUI ihn in eine Tabellenzelle setzt: 4 pt über und unter dem Inhalt, die Zeile mindestens
    /// 24 pt hoch (Ist-Aufnahme: einzeilig 24, zweizeilig 39, ein kleiner Knopf ohne Rand 24).
    static func wurzel(_ inhalt: AnyView, hervorgehoben: Bool) -> AnyView {
        AnyView(
            inhalt
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                .padding(.vertical, 4)
                .buttonStyle(.borderless)
                .environment(\.backgroundProminence, hervorgehoben ? .increased : .standard)
        )
    }
}
