// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Der Rollbereich des Rasters — ein `NSCollectionView` statt zweier
/// ineinanderliegender nachladender Stapel von SwiftUI.
///
/// In SwiftUI kostete das Rollen 10,0 ms je Bild (verfügbar sind bei ProMotion
/// 8,3 ms), auch mit auf ein Rechteck reduzierten Zellen noch 5,7 ms — es war
/// die Bauweise, nicht der Inhalt — zwei Versuche innerhalb von SwiftUI
/// scheiterten daran, darum AppKit.
struct Rasteransicht: NSViewRepresentable {
    let speicher: Planungsspeicher
    let daten: Rasterdaten
    let planung: Planung
    /// Wohin gesprungen werden soll — `nil`, wenn nichts ansteht.
    let sprung: Rastersprung?

    func makeCoordinator() -> Rasterkoordinator { Rasterkoordinator(speicher: speicher) }

    func makeNSView(context: Context) -> Rasterbuehne {
        let koordinator = context.coordinator
        let buehne = Rasterbuehne(frame: .zero)

        let sammelblatt = Rastersammelblatt()
        let anordnung = Rasterlayout()
        anordnung.daten = daten
        sammelblatt.collectionViewLayout = anordnung
        sammelblatt.dataSource = koordinator
        sammelblatt.delegate = koordinator
        sammelblatt.isSelectable = false
        sammelblatt.allowsMultipleSelection = false
        // Deckender Untergrund: sonst kopiert der Rollbereich beim Rollen nicht.
        sammelblatt.backgroundColors = [.windowBackgroundColor]
        sammelblatt.register(Zellenelement.self, forItemWithIdentifier: Zellenelement.kennung)
        sammelblatt.registerForDraggedTypes(
            [NSPasteboard.PasteboardType(UTType.vorhabenverweis.identifier)])
        sammelblatt.setDraggingSourceOperationMask(.move, forLocal: true)

        buehne.roller.documentView = sammelblatt
        // Erst das Dokument, dann die Roller: Zuweisen stellt die Rollbalken neu ein.
        buehne.roller.hasVerticalScroller = true
        buehne.roller.hasHorizontalScroller = true
        buehne.roller.autohidesScrollers = true
        buehne.roller.drawsBackground = true
        buehne.roller.backgroundColor = .windowBackgroundColor
        buehne.roller.contentView.postsBoundsChangedNotifications = true

        koordinator.sammelblatt = sammelblatt
        koordinator.buehne = buehne
        koordinator.daten = daten
        koordinator.anordnung = anordnung
        koordinator.rollenBeobachten()
        koordinator.groesseNachfuehren()
        koordinator.tourAnmelden()
        return buehne
    }

    func updateNSView(_ buehne: Rasterbuehne, context: Context) {
        context.coordinator.uebernehmen(daten: daten, planung: planung, sprung: sprung)
    }

    static func dismantleNSView(_ buehne: Rasterbuehne, coordinator: Rasterkoordinator) {
        coordinator.aufhoeren()
        coordinator.tourAbmelden()
    }
}

/// Ein Sammelblatt, das sich nicht schmaler machen lässt als sein Inhalt — und
/// das den Zeiger für alle seine Zellen verfolgt.
///
/// `NSCollectionView` klemmt seine Breite auf die des Sichtfensters und geht von
/// senkrechtem Rollen aus: Bei 52 Wochenspalten ließ sich **waagerecht gar nicht
/// rollen**. Von außen gesetzte Größen nimmt es beim nächsten Anordnen zurück —
/// deshalb steht die Untergrenze hier, wo beschnitten wird.
final class Rastersammelblatt: NSCollectionView {

    // ── Wo der Zeiger steht ───────────────────────────────────────────────
    // Ein Verfolgungsbereich fürs ganze Raster: `mouseExited` bleibt beim Rollen aus.

    private var beobachtung: NSTrackingArea?
    private weak var ueberfahreneZelle: Zellenkoerper?
    private weak var ueberfahreneKachel: Kachelansicht?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let beobachtung { removeTrackingArea(beobachtung) }
        let neue = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(neue)
        beobachtung = neue
    }

    override func mouseMoved(with ereignis: NSEvent) {
        zeigerNachfuehren(convert(ereignis.locationInWindow, from: nil))
    }

    override func mouseExited(with ereignis: NSEvent) { zeigerNachfuehren(nil) }

    /// Nach dem Rollen steht der Zeiger über einer anderen Zelle, ohne sich
    /// bewegt zu haben.
    func zeigerNachsehen() { Messzaehler.messen("zeiger") { zeigerNachsehenJetzt() } }

    private func zeigerNachsehenJetzt() {
        guard let fenster = window, fenster.isKeyWindow else {
            zeigerNachfuehren(nil)
            return
        }
        let imFenster = fenster.mouseLocationOutsideOfEventStream
        let punkt = convert(imFenster, from: nil)
        zeigerNachfuehren(visibleRect.contains(punkt) ? punkt : nil)
    }

    private func zeigerNachfuehren(_ punkt: NSPoint?) {
        var zelle: Zellenkoerper?
        var kachel: Kachelansicht?
        if let punkt, let getroffen = hitTest(convert(punkt, to: superview)) {
            var lauf: NSView? = getroffen
            while let a = lauf {
                if let k = a as? Kachelansicht, kachel == nil { kachel = k }
                if let z = a as? Zellenkoerper { zelle = z; break }
                lauf = a.superview
            }
        }
        if ueberfahreneZelle !== zelle {
            ueberfahreneZelle?.ueberfahrenSetzen(false)
            zelle?.ueberfahrenSetzen(true)
            ueberfahreneZelle = zelle
        }
        if ueberfahreneKachel !== kachel {
            ueberfahreneKachel?.ueberfahrenSetzen(false)
            kachel?.ueberfahrenSetzen(true)
            ueberfahreneKachel = kachel
        }
    }

    override func setFrameSize(_ neue: NSSize) {
        guard let inhalt = collectionViewLayout?.collectionViewContentSize,
              inhalt.width > 0 || inhalt.height > 0 else {
            super.setFrameSize(neue)
            return
        }
        super.setFrameSize(NSSize(width: max(neue.width, inhalt.width),
                                  height: max(neue.height, inhalt.height)))
    }
}

// ── Koordinator ───────────────────────────────────────────────────────────

@MainActor
final class Rasterkoordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private let speicher: Planungsspeicher
    fileprivate var sammelblatt: NSCollectionView?
    fileprivate var buehne: Rasterbuehne?
    fileprivate var anordnung: Rasterlayout?
    fileprivate var daten: Rasterdaten?

    private var beobachter: (any NSObjectProtocol)?
    private var letzterStand = -1
    private var letzteBreite: CGFloat = -1
    private var letzteAuswahl: Set<String> = []
    private var letzteZielzelle: Zellenort?
    private var letzterSprung: Rastersprung?
    private var zielelement: IndexPath?
    private var letzteHoehen: [CGFloat] = []
    private var letzteSpalten = -1
    private var letzteSuche: [String] = []
    private var treffer: Set<String>?
    /// Einmal gebaut und behalten — sonst vierzehn Abschlüsse je ausgegebener
    /// Zelle, achtzigfach je Rollbild.
    private lazy var gemerkteGriffe: Zellenkoerper.Griffe = griffe()

    init(speicher: Planungsspeicher) {
        self.speicher = speicher
        super.init()
    }

    // ── Aktualisieren ─────────────────────────────────────────────────────

    func uebernehmen(daten neueDaten: Rasterdaten, planung: Planung, sprung: Rastersprung?) {
        daten = neueDaten
        buehne?.koepfeSetzen(
            kopf: Wochenkopfzeile(stand: neueDaten.wochenstand,
                                  breite: neueDaten.spaltenbreite, vonHand: planung.frei,
                                  laufende: planung.laufendeWoche(in: neueDaten.wochen)),
            spalte: Kursspalte(zeilen: neueDaten.zeilen),
            ecke: Ecke(wochen: planung.wochen),
            breite: neueDaten.spaltenbreite, gesamtbreite: neueDaten.gesamtbreite)

        if neueDaten.stand != letzterStand || neueDaten.spaltenbreite != letzteBreite {
            // Trefferliste hängt auch an den Daten, nicht nur am Suchbegriff.
            if speicher.sucheLaeuft { treffer = trefferBestimmen(planung) }

            // Spaltenzahl in den Vergleich: Ein größerer Zeitraum ändert keine Zeilenhöhe.
            let anordnungGilt = neueDaten.spaltenbreite == letzteBreite
                && neueDaten.hoehenkennung == letzteHoehen
                && neueDaten.spaltenzahl == letzteSpalten
            letzterStand = neueDaten.stand
            letzteBreite = neueDaten.spaltenbreite
            letzteHoehen = neueDaten.hoehenkennung
            letzteSpalten = neueDaten.spaltenzahl
            anordnung?.daten = neueDaten
            groesseNachfuehren()

            if anordnungGilt {
                // Die Anordnung steht; `reloadData()` risse alles ab: 70 statt 20 ms.
                sichtbareBelegen(neueDaten)
            } else {
                sammelblatt?.reloadData()
            }
        }

        if speicher.suchworte != letzteSuche {
            letzteSuche = speicher.suchworte
            treffer = trefferBestimmen(planung)
            sichtbareBelegen(neueDaten)
        }

        let auswahl = speicher.auswahl
        let zielzelle = speicher.zielzelle
        if auswahl != letzteAuswahl || zielzelle != letzteZielzelle {
            letzteAuswahl = auswahl
            letzteZielzelle = zielzelle
            auswahlNachfuehren()
        }

        if let sprung, sprung != letzterSprung {
            letzterSprung = sprung
            springen(zu: sprung.woche)
        }
    }

    /// `nil`, wenn nicht gesucht wird — dann entfällt jede Prüfung an der Zelle.
    private func trefferBestimmen(_ planung: Planung) -> Set<String>? {
        guard speicher.sucheLaeuft else { return nil }
        var gefunden = Set<String>()
        for eintrag in planung.eintraege
        where speicher.trifft(eintrag, klasse: planung.klasse(eintrag.klasseId)) {
            gefunden.insert(eintrag.id)
        }
        return gefunden
    }

    /// Muss von Hand gesetzt werden, jedes Mal wenn sich die Anordnung ändert
    /// (siehe `Rastersammelblatt`).
    func groesseNachfuehren() {
        guard let sammelblatt, let anordnung else { return }
        let groesse = anordnung.collectionViewContentSize
        if sammelblatt.frame.size != groesse {
            sammelblatt.setFrameSize(groesse)
        }
        if let roller = sammelblatt.enclosingScrollView, !roller.hasHorizontalScroller {
            roller.hasHorizontalScroller = true
        }
    }

    private func sichtbareBelegen(_ daten: Rasterdaten) {
        guard let sammelblatt else { return }
        for element in sammelblatt.visibleItems() {
            guard let zelle = element as? Zellenelement,
                  let pfad = sammelblatt.indexPath(for: element),
                  daten.zeilen.indices.contains(pfad.section) else { continue }
            let ort = Zellenort(klasse: daten.zeilen[pfad.section].klasse.id, woche: pfad.item)
            zelle.koerper.setzen(daten: daten, zeile: pfad.section, woche: pfad.item,
                                 angewaehlt: speicher.zielzelle == ort,
                                 auswahl: speicher.auswahl, treffer: treffer,
                                 griffe: gemerkteGriffe)
        }
    }

    private func auswahlNachfuehren() {
        guard let sammelblatt, let daten else { return }
        for element in sammelblatt.visibleItems() {
            guard let zelle = element as? Zellenelement,
                  let pfad = sammelblatt.indexPath(for: element),
                  let zeile = daten.zeilen[safe: pfad.section] else { continue }
            let ort = Zellenort(klasse: zeile.klasse.id, woche: pfad.item)
            zelle.koerper.auswahlSetzen(letzteAuswahl, zelleAngewaehlt: letzteZielzelle == ort)
        }
    }

    private func springen(zu woche: Int) {
        rollen(zu: woche, zeile: sprungzeile(woche))
    }

    /// `zeile` nur, wenn sie nicht ohnehin im Bild steht.
    private func rollen(zu woche: Int, zeile: Int?) {
        guard let buehne, let daten else { return }
        let roller = buehne.roller
        let sichtbar = roller.contentView.bounds
        // Die Kursspalte liegt außerhalb des Rollbereichs — kein Versatz nötig.
        // Obergrenze nötig: `NSClipView.scroll(to:)` klemmt nicht von sich aus,
        // sonst bliebe hinter der letzten Spalte leere Fläche stehen.
        let x = min(max(0, CGFloat(woche) * daten.spaltenbreite),
                    max(0, daten.gesamtbreite - sichtbar.width))
        var y = sichtbar.origin.y
        if let zeile = zeile.flatMap({ daten.zeilen[safe: $0] }),
           zeile.oben < sichtbar.minY || zeile.oben + zeile.hoehe > sichtbar.maxY {
            y = min(max(0, zeile.oben), max(0, daten.gesamthoehe - sichtbar.height))
        }
        roller.contentView.scroll(to: NSPoint(x: x, y: y))
        roller.reflectScrolledClipView(roller.contentView)
        buehne.mitziehen()
    }

    // ── Tour: die Beispielzelle ───────────────────────────────────────────

    private weak var tourzelle: Zellenkoerper?

    func tourAnmelden() {
        Tourfuehrer.shared.zellenanker = { [weak self] schritt in self?.touranker(schritt) }
        Tourfuehrer.shared.zelleFreigeben = { [weak self] in self?.tourzelleFreigeben() }
    }

    func tourAbmelden() {
        Tourfuehrer.shared.zellenanker = nil
        Tourfuehrer.shared.zelleFreigeben = nil
        tourzelleFreigeben()
    }

    /// Erste Zeile, erste Woche mit Unterricht: dorthin rollen, die Zelle mit
    /// ihren beiden Knöpfen zeigen, die Stelle für die Karte nennen. `nil`,
    /// solange das Sammelblatt die Zelle noch nicht angelegt hat — der Führer
    /// fragt dann noch einmal.
    private func touranker(_ schritt: Planungsspeicher.Tourschritt) -> Tourfuehrer.Anker? {
        guard let sammelblatt, let daten, let zeile = daten.zeilen.first else { return nil }
        let woche = daten.wochen.indices.first { !daten.lage($0).frei } ?? 0
        rollen(zu: woche, zeile: 0)
        sammelblatt.layoutSubtreeIfNeeded()
        let pfad = IndexPath(item: woche, section: 0)
        guard let element = sammelblatt.item(at: pfad) as? Zellenelement else { return nil }
        let koerper = element.koerper
        if tourzelle !== koerper { tourzelle?.hervorheben(false) }
        tourzelle = koerper
        koerper.hervorheben(true)
        koerper.layoutSubtreeIfNeeded()
        speicher.tourZelle = "\(zeile.klasse.name), KW \(daten.wochen[safe: woche]?.kw ?? 0)"
        // Die Zelle ist gekippt: `maxY` ist unten.
        let rahmen: NSRect = switch schritt {
        case .anlegen: koerper.anlegenknopfRahmen
        case .frei: koerper.freiknopfRahmen
        default: koerper.bounds
        }
        return .init(ansicht: koerper, rahmen: rahmen,
                     kante: schritt == .zelle ? .maxX : .maxY)
    }

    private func tourzelleFreigeben() {
        tourzelle?.hervorheben(false)
        tourzelle = nil
    }

    /// Welche Zeile der Sprung meint — der Sprung selbst führt nur die Woche.
    /// Die Anwahl steht zu diesem Zeitpunkt schon (`zeigeVorhaben`); liegt sie
    /// in einer anderen Woche, gehört sie nicht zum Sprung.
    private func sprungzeile(_ woche: Int) -> Int? {
        guard let daten else { return nil }
        if let ziel = speicher.zielzelle, ziel.woche == woche {
            return daten.zeilen.firstIndex { $0.klasse.id == ziel.klasse }
        }
        for id in speicher.auswahl {
            if let stelle = daten.stelle(vorhaben: id), stelle.woche == woche {
                return stelle.zeile
            }
        }
        return nil
    }

    // ── Rollstand melden ──────────────────────────────────────────────────

    func rollenBeobachten() {
        guard let buehne, beobachter == nil else { return }
        beobachter = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: buehne.roller.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.buehne?.mitziehen()
                (self?.sammelblatt as? Rastersammelblatt)?.zeigerNachsehen()
            }
        }
    }

    func aufhoeren() {
        if let beobachter { NotificationCenter.default.removeObserver(beobachter) }
        beobachter = nil
    }

    // ── Inhalt ────────────────────────────────────────────────────────────

    func numberOfSections(in sammelblatt: NSCollectionView) -> Int {
        daten?.zeilenzahl ?? 0
    }

    func collectionView(_ sammelblatt: NSCollectionView,
                        numberOfItemsInSection abschnitt: Int) -> Int {
        daten?.spaltenzahl ?? 0
    }

    func collectionView(_ sammelblatt: NSCollectionView,
                        itemForRepresentedObjectAt pfad: IndexPath) -> NSCollectionViewItem {
        Messzaehler.messen("ausgeben") { ausgeben(sammelblatt, pfad) }
    }

    private func ausgeben(_ sammelblatt: NSCollectionView, _ pfad: IndexPath) -> NSCollectionViewItem {
        let element = Messzaehler.messen("dequeue") {
            sammelblatt.makeItem(withIdentifier: Zellenelement.kennung, for: pfad)
        }
        guard let zelle = element as? Zellenelement, let daten,
              daten.zeilen.indices.contains(pfad.section) else { return element }
        let ort = Zellenort(klasse: daten.zeilen[pfad.section].klasse.id, woche: pfad.item)
        Messzaehler.messen("setzen") {
            zelle.koerper.setzen(daten: daten, zeile: pfad.section, woche: pfad.item,
                                 angewaehlt: speicher.zielzelle == ort,
                                 auswahl: speicher.auswahl, treffer: treffer,
                                 griffe: gemerkteGriffe)
        }
        return element
    }

    // ── Fallenlassen ──────────────────────────────────────────────────────

    func collectionView(_ sammelblatt: NSCollectionView,
                        validateDrop info: any NSDraggingInfo,
                        proposedIndexPath pfad: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation art: UnsafeMutablePointer<NSCollectionView.DropOperation>)
    -> NSDragOperation {
        art.pointee = .on
        zielZeigen(pfad.pointee as IndexPath, ort: info.draggingLocation)
        return .move
    }

    func collectionView(_ sammelblatt: NSCollectionView,
                        draggingExited info: (any NSDraggingInfo)?) {
        zielZeigen(nil)
    }

    func collectionView(_ sammelblatt: NSCollectionView, acceptDrop info: any NSDraggingInfo,
                        indexPath pfad: IndexPath,
                        dropOperation art: NSCollectionView.DropOperation) -> Bool {
        // Vor dem Aufräumen: Die Einfügestelle steht in der Zelle unter dem Zeiger.
        let vor = (sammelblatt.item(at: pfad) as? Zellenelement).flatMap { element in
            element.koerper.einfuegestelle(
                bei: element.koerper.convert(info.draggingLocation, from: nil)).vorId
        }
        zielZeigen(nil)
        guard let daten, daten.zeilen.indices.contains(pfad.section),
              let rohdaten = info.draggingPasteboard.data(
                forType: NSPasteboard.PasteboardType(UTType.vorhabenverweis.identifier)),
              let verweis = try? JSONDecoder().decode(Vorhabenverweis.self, from: rohdaten),
              let planung = speicher.planung else { return false }
        let gezogen = planung.eintraege.filter { verweis.ids.contains($0.id) }
        guard !gezogen.isEmpty else { return false }
        let ziel = Zellenort(klasse: daten.zeilen[pfad.section].klasse.id, woche: pfad.item)
        speicher.versetzen(gezogen, nach: ziel, verschieben: true, vor: vor)
        return true
    }

    private func zielZeigen(_ pfad: IndexPath?, ort: NSPoint? = nil) {
        guard let sammelblatt else { return }
        // Über alle sichtbaren Zellen: `item(at:)` liefert nach dem Rollen nichts mehr.
        for element in sammelblatt.visibleItems() {
            guard let zelle = element as? Zellenelement else { continue }
            if sammelblatt.indexPath(for: element) != pfad { zelle.koerper.zielSetzen(false) }
        }
        zielelement = pfad
        if let pfad, let element = sammelblatt.item(at: pfad) as? Zellenelement {
            let marke = ort.map {
                element.koerper.einfuegestelle(bei: element.koerper.convert($0, from: nil)).stelle
            }
            element.koerper.zielSetzen(true, marke: marke)
        }
    }

    // ── Griffe für Zelle und Kachel ───────────────────────────────────────

    private func griffe() -> Zellenkoerper.Griffe {
        var g = Zellenkoerper.Griffe()
        g.zelleAnwaehlen = { [weak self] zeile, woche in
            guard let self, let id = self.daten?.zeilen[safe: zeile]?.klasse.id else { return }
            self.speicher.anwaehlen(zelle: Zellenort(klasse: id, woche: woche))
        }
        g.vorhabenAnlegen = { [weak self] zeile, woche in
            guard let self, let id = self.daten?.zeilen[safe: zeile]?.klasse.id else { return }
            self.speicher.vorhabenOeffnen(klasse: id, woche: woche)
        }
        g.freiUmschalten = { [weak self] zeile, woche in
            guard let self, let daten = self.daten,
                  let klasse = daten.zeilen[safe: zeile]?.klasse.id,
                  let w = daten.wochen[safe: woche] else { return }
            self.speicher.zelleFreiSchalten(klasse: klasse, woche: w)
        }
        g.zellenmenue = { [weak self] zeile, woche in self?.zellenmenue(zeile, woche) }

        g.kachel.anwaehlen = { [weak self] id, tasten in
            guard let self else { return }
            if tasten.contains(.shift) {
                self.speicher.anwaehlenBis(vorhaben: id)
            } else {
                self.speicher.anwaehlen(vorhaben: id, erweitern: tasten.contains(.command))
            }
        }
        g.kachel.istAngewaehlt = { [weak self] id in self?.speicher.istAngewaehlt(id) ?? false }
        g.kachel.oeffnen = { [weak self] id in self?.speicher.vorhabenOeffnen(id: id) }
        g.kachel.erledigtUmschalten = { [weak self] id in self?.speicher.erledigtUmschalten(id) }
        g.kachel.titelSetzen = { [weak self] id, titel in
            self?.speicher.titelSetzen(vorhaben: id, titel: titel)
        }
        g.kachel.menue = { [weak self] id, hoch, runter in
            self?.kachelmenue(id, kannHoch: hoch, kannRunter: runter)
        }
        g.kachel.ziehnutzlast = { [weak self] id in
            guard let self else { return [id] }
            return self.speicher.istAngewaehlt(id) && self.speicher.auswahl.count > 1
                ? Array(self.speicher.auswahl) : [id]
        }
        g.kachel.materialZeigen = { [weak self] pfad in self?.speicher.imFinderZeigen(pfad) }
        g.kachel.materialOeffnen = { [weak self] pfad in self?.speicher.dateiOeffnen(pfad) }
        g.kachel.adresseOeffnen = { adresse in Systemzugriff.adresseOeffnen(adresse) }
        g.kachel.vollerPfad = { [weak self] pfad in self?.speicher.vollerPfad(pfad) ?? pfad }
        return g
    }

    // ── Menüs ─────────────────────────────────────────────────────────────
    // Erst beim Rechtsklick gebaut: `contextMenu(menuItems:)` wertete sonst bei jeder Änderung aus.

    private func zellenmenue(_ zeile: Int, _ woche: Int) -> NSMenu? {
        guard let daten, let zeilendaten = daten.zeilen[safe: zeile] else { return nil }
        let klasse = zeilendaten.klasse.id
        let menue = NSMenu()
        menue.addItem(eintrag("Vorhaben anlegen") { [weak self] in
            self?.speicher.vorhabenOeffnen(klasse: klasse, woche: woche)
        })
        if let inhalt = speicher.ablage {
            let was = inhalt.vorhaben.count == 1 ? "" : " (\(inhalt.vorhaben.count))"
            let titel = (inhalt.verschieben ? "Hierher verschieben" : "Hier einfügen") + was
            menue.addItem(eintrag(titel) { [weak self] in
                self?.speicher.anwaehlen(zelle: Zellenort(klasse: klasse, woche: woche))
                self?.speicher.einfuegen()
            })
        }
        // Der einzige andere Weg dorthin ist der Knopf in der Zelle, den nur
        // der Mauszeiger hervorholt.
        if !daten.lage(woche).frei, let w = daten.wochen[safe: woche] {
            menue.addItem(.separator())
            menue.addItem(schalter(zeilendaten.einzelfrei.contains(woche),
                                   ein: "Wieder als Unterricht führen",
                                   aus: "Als unterrichtsfrei kennzeichnen") { [weak self] in
                self?.speicher.zelleFreiSchalten(klasse: klasse, woche: w)
            })
        }
        return menue
    }

    private func kachelmenue(_ id: String, kannHoch: Bool, kannRunter: Bool) -> NSMenu? {
        let menue = NSMenu()
        let betroffen = speicher.istAngewaehlt(id) ? max(1, speicher.auswahl.count) : 1
        func zusatz(_ titel: String) -> String {
            betroffen == 1 ? titel : "\(titel) (\(betroffen))"
        }

        if betroffen == 1 {
            menue.addItem(eintrag("Öffnen") { [weak self] in self?.speicher.vorhabenOeffnen(id: id) })
            menue.addItem(eintrag("Titel ändern") { [weak self] in self?.titelBearbeiten(id) })
            let vorhanden = speicher.planung?.eintraege.first { $0.id == id }
            menue.addItem(schalter(vorhanden?.pruefung == true,
                                   ein: "Nicht mehr als Prüfung führen",
                                   aus: "Als Prüfung führen") { [weak self] in
                self?.speicher.pruefungUmschalten(id)
            })
            menue.addItem(schalter(vorhanden?.dringend == true,
                                   ein: "Nicht mehr als dringlich führen",
                                   aus: "Als dringlich kennzeichnen") { [weak self] in
                self?.speicher.dringlichUmschalten(id)
            })
            menue.addItem(.separator())
            if kannHoch {
                menue.addItem(eintrag("Nach oben") { [weak self] in
                    self?.speicher.reihen(id, nachOben: true)
                })
            }
            if kannRunter {
                menue.addItem(eintrag("Nach unten") { [weak self] in
                    self?.speicher.reihen(id, nachOben: false)
                })
            }
            if kannHoch || kannRunter { menue.addItem(.separator()) }
        }
        menue.addItem(eintrag(zusatz("Kopieren")) { [weak self] in
            self?.sicherstellenAngewaehlt(id)
            self?.speicher.kopieren()
        })
        menue.addItem(eintrag(zusatz("Verschieben")) { [weak self] in
            self?.sicherstellenAngewaehlt(id)
            self?.speicher.verschiebenVormerken()
        })
        if let inhalt = speicher.ablage, let ort = speicher.planung?.eintraege
            .first(where: { $0.id == id })
            .map({ Zellenort(klasse: $0.klasseId, woche: $0.woche) }) {
            menue.addItem(eintrag(inhalt.verschieben ? "Hierher verschieben" : "Hier einfügen") {
                [weak self] in
                self?.speicher.anwaehlen(zelle: ort)
                self?.speicher.einfuegen()
            })
        }
        menue.addItem(.separator())
        menue.addItem(eintrag(zusatz("Löschen")) { [weak self] in
            self?.sicherstellenAngewaehlt(id)
            self?.speicher.auswahlLoeschen()
        })
        return menue
    }

    private func sicherstellenAngewaehlt(_ id: String) {
        if !speicher.istAngewaehlt(id) { speicher.anwaehlen(vorhaben: id) }
    }

    /// Die Kachel selbst muss das Feld aufmachen — sie weiß, wo sie liegt.
    private func titelBearbeiten(_ id: String) {
        guard let sammelblatt, let daten, let stelle = daten.stelle(vorhaben: id) else { return }
        let pfad = IndexPath(item: stelle.woche, section: stelle.zeile)
        guard let element = sammelblatt.item(at: pfad) as? Zellenelement else { return }
        for kachel in element.koerper.subviews.compactMap({ $0 as? Kachelansicht })
        where kachel.stand?.vorhaben.id == id {
            kachel.titelBearbeiten()
        }
    }

    private func schalter(_ gesetzt: Bool, ein: String, aus: String,
                          _ handlung: @escaping () -> Void) -> NSMenuItem {
        let punkt = eintrag(gesetzt ? ein : aus, handlung)
        punkt.state = gesetzt ? .on : .off
        return punkt
    }

    private func eintrag(_ titel: String, _ handlung: @escaping () -> Void) -> NSMenuItem {
        let element = NSMenuItem(title: titel, action: #selector(Menuebote.ausloesen), keyEquivalent: "")
        let bote = Menuebote(handlung)
        element.target = bote
        element.representedObject = bote   // hält den Boten am Leben
        return element
    }
}

/// `NSMenuItem` will ein Ziel und einen Auswahlnamen; ein Abschluss allein
/// genügt ihm nicht.
private final class Menuebote: NSObject {
    private let handlung: () -> Void
    init(_ handlung: @escaping () -> Void) { self.handlung = handlung }
    @objc func ausloesen() { handlung() }
}
