// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Rollbereich, Wochenkopfzeile, Kursspalte und Ecke unter einem Dach von
/// AppKit.
///
/// `frame.origin` einer `NSHostingView` zu setzen verschiebt sie, ohne ihren
/// SwiftUI-Körper neu auszuwerten. Über einen beobachteten Rollstand kostete
/// dasselbe **2,7 ms je Rollbild**.
@MainActor
final class Rasterbuehne: NSView {

    let roller = NSScrollView()
    private let kopfrahmen = Ausschnitt()
    private let spaltenrahmen = Ausschnitt()
    private let eckrahmen = Ausschnitt()
    private var kopfzeile: NSHostingView<Wochenkopfzeile>?
    private var kursspalte: NSHostingView<Kursspalte>?
    private var ecke: NSHostingView<Ecke>?
    /// Das AppKit-Gegenstück zu `glassEffect`.
    private let kopfglas = NSGlassEffectView()
    private let eckglas = NSGlassEffectView()

    private var breite: CGFloat = 0
    private var gesamtbreite: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // `NSGlassEffectView` rundet von sich aus ab — sichtbar an der Ecke.
        kopfglas.cornerRadius = 0
        eckglas.cornerRadius = 0
        addSubview(roller)
        // Glas als Untergrund darunter: `contentView` verträgt keinen Ausschnitt.
        addSubview(kopfglas)
        addSubview(kopfrahmen)
        addSubview(spaltenrahmen)
        addSubview(eckglas)
        addSubview(eckrahmen)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht aus einer Datei geladen") }

    // ── Inhalt ────────────────────────────────────────────────────────────

    func koepfeSetzen(kopf: Wochenkopfzeile, spalte: Kursspalte, ecke neueEcke: Ecke,
                      breite neueBreite: CGFloat, gesamtbreite neueGesamtbreite: CGFloat) {
        breite = neueBreite
        gesamtbreite = neueGesamtbreite

        if let kopfzeile { kopfzeile.rootView = kopf } else {
            let neu = NSHostingView(rootView: kopf)
            kopfrahmen.addSubview(neu)
            kopfzeile = neu
        }
        if let kursspalte { kursspalte.rootView = spalte } else {
            let neu = NSHostingView(rootView: spalte)
            spaltenrahmen.addSubview(neu)
            kursspalte = neu
        }
        if let ecke { ecke.rootView = neueEcke } else {
            let neu = NSHostingView(rootView: neueEcke)
            eckrahmen.addSubview(neu)
            ecke = neu
        }
        needsLayout = true
    }

    // ── Anordnen ──────────────────────────────────────────────────────────

    override func layout() {
        super.layout()
        let innenbreite = max(0, bounds.width - Masse.spalteKlasse)
        let innenhoehe = max(0, bounds.height - Masse.wochenkopfHoehe)

        roller.frame = NSRect(x: Masse.spalteKlasse, y: Masse.wochenkopfHoehe,
                              width: innenbreite, height: innenhoehe)
        kopfglas.frame = NSRect(x: Masse.spalteKlasse, y: 0,
                                width: innenbreite, height: Masse.wochenkopfHoehe)
        // `.frame`, nicht `.bounds`: Der Ausschnitt ist ein Geschwister des Glases.
        kopfrahmen.frame = kopfglas.frame
        spaltenrahmen.frame = NSRect(x: 0, y: Masse.wochenkopfHoehe,
                                     width: Masse.spalteKlasse, height: innenhoehe)
        eckglas.frame = NSRect(x: 0, y: 0, width: Masse.spalteKlasse,
                               height: Masse.wochenkopfHoehe)
        eckrahmen.frame = eckglas.frame
        ecke?.frame = eckrahmen.bounds

        // Das Sammelblatt schaltet den waagerechten Rollbalken beim Einhängen ab.
        if !roller.hasHorizontalScroller { roller.hasHorizontalScroller = true }

        // Genau `gesamtbreite` — dieselbe Bezugsgröße wie die Zellen. Der
        // Wurzelkörper der Kopfzeile ist fest so breit; ein breiterer Wirt
        // zentrierte ihn und rückte den Kopf gegen die Spalten.
        kopfzeile?.frame.size = NSSize(width: gesamtbreite,
                                       height: Masse.wochenkopfHoehe)
        kursspalte?.frame.size = NSSize(width: Masse.spalteKlasse,
                                        height: max(kursspalte?.fittingSize.height ?? 0, innenhoehe))
        mitziehen()
    }

    /// Der ganze Rollpfad: zwei Zuweisungen.
    func mitziehen() {
        let ursprung = roller.contentView.bounds.origin
        let x = -max(0, ursprung.x)
        let y = -max(0, ursprung.y)
        if kopfzeile?.frame.origin.x != x { kopfzeile?.frame.origin.x = x }
        if kursspalte?.frame.origin.y != y { kursspalte?.frame.origin.y = y }
    }
}

private final class Ausschnitt: NSView {
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht aus einer Datei geladen") }
}

/// Wird von der Bühne verschoben und darf deshalb keinen beobachteten
/// Rollstand lesen.
struct Kursspalte: View {
    let zeilen: [Rasterdaten.Zeilenstand]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(zeilen, id: \.klasse.id) { zeile in
                Klassenkopf(klasse: zeile.klasse)
                    .frame(width: Masse.spalteKlasse, height: zeile.hoehe)
            }
            Spacer(minLength: 0)
        }
    }
}
