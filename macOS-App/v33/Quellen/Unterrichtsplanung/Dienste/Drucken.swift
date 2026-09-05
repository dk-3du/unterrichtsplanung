// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Drucken und PDF — eine eigene, ruhige Fassung des Rasters: helle Flächen,
/// keine Schalter, jede Beschreibung vollständig.
@MainActor
enum Drucken {

    /// Gedruckt wird nicht die SwiftUI-Ansicht selbst.
    ///
    /// `NSPrintOperation` fragt beim Setzen der Seiten `draw(_:)` ab; eine
    /// `NSHostingView` zeichnet aber über Ebenen (`CALayer`) und antwortet dort
    /// mit nichts. Das Ergebnis war ein Stapel leerer Blätter — die Anordnung
    /// stimmte (die Seitenzahl passte auf den Inhalt), nur stand nichts darauf.
    /// Ein unsichtbares Fenster darum herum ändert daran nichts, geprüft.
    ///
    /// Deshalb derselbe Weg wie beim PDF-Sichern: Die Blätter werden vektoriell
    /// gezeichnet, und aufs Papier bringt sie eine schlichte Ansicht, die die
    /// fertige Seite mit Core Graphics zeichnet.
    static func drucken(_ planung: Planung, speicher: Planungsspeicher) {
        // ⌘P kann mitten in den 400 ms eines laufenden Entprellers fallen; die
        // gereichte Kopie trüge dann noch den alten Titel. Die Blätter entstehen
        // vor `run()` — im Druckdialog nachzuziehen wäre zu spät.
        Entpreller.allesUebernehmen()
        let aktuell = speicher.planung ?? planung

        let angaben = druckangaben()
        guard let blatt = Druckblatt(aktuell, mass: blattmass(angaben)) else {
            speicher.melden("Die Druckfassung ließ sich nicht zeichnen.", .warnung)
            return
        }

        let vorgang = NSPrintOperation(view: blatt, printInfo: angaben)
        vorgang.jobTitle = aktuell.titel
        vorgang.showsPrintPanel = true
        vorgang.showsProgressPanel = true
        vorgang.run()
    }

    /// Quer, mit schmalem Rand. Wo ein Blatt endet, entscheidet nicht AppKit,
    /// sondern `Druckblatt.knowsPageRange(_:)` — die Angaben zur Aufteilung
    /// stehen deshalb bewusst nicht hier.
    static func druckangaben() -> NSPrintInfo {
        let angaben = NSPrintInfo.shared.copy() as! NSPrintInfo
        angaben.orientation = .landscape
        // `NSPrintInfo.shared` trägt den Maßstab eines früheren Auftrags mit.
        angaben.scalingFactor = 1
        raender(angaben)
        return angaben
    }

    /// 24 Punkt Rand, mindestens aber so viel, wie der Drucker am jeweiligen
    /// Blattrand ohnehin frei lässt. Das hängt allein an Papier und Drucker und
    /// ist nach einer Änderung im Druckdialog erneut anzuwenden.
    static func raender(_ angaben: NSPrintInfo) {
        let papier = angaben.paperSize
        let bedruckbar = angaben.imageablePageBounds
        angaben.leftMargin = max(24, bedruckbar.minX)
        angaben.bottomMargin = max(24, bedruckbar.minY)
        angaben.rightMargin = max(24, papier.width - bedruckbar.maxX)
        angaben.topMargin = max(24, papier.height - bedruckbar.maxY)
    }

    static func alsPDFSichern(_ planung: Planung, speicher: Planungsspeicher) {
        let name = Planungsdatei.exportName(titel: planung.titel, endung: "pdf")
        let dialog = NSSavePanel()
        dialog.message = "Planung als PDF sichern"
        dialog.nameFieldStringValue = name
        dialog.allowedContentTypes = [.pdf]
        dialog.canCreateDirectories = true
        guard dialog.runModal() == .OK, let ziel = dialog.url else { return }

        // Die Modalschleife hält zwar diesen Aufruf an, lässt die Main-Queue
        // aber weiterlaufen: Ein Entpreller (Titel, Klassen-, Ferien-,
        // Prüfungsdialog) kann währenddessen feuern. Gezeichnet wird deshalb
        // nicht die vor dem Dialog gereichte Kopie, sondern der frische Stand.
        Entpreller.allesUebernehmen()
        let aktuell = speicher.planung ?? planung

        var erfolg = false
        if let (daten, _) = zeichnung(aktuell) {
            erfolg = (try? daten.write(to: ziel, options: .atomic)) != nil
        }
        speicher.melden(erfolg ? "Planung als PDF gesichert."
                               : "Die PDF-Datei konnte nicht geschrieben werden.",
                        erfolg ? .hinweis : .warnung)
    }

    /// Die ganze Planung als vektorielles PDF — eine einzige, beliebig große
    /// Seite. Von hier kommt ausschließlich „Als PDF sichern“; der Ausdruck
    /// entsteht blattweise in `blattzeichnung`.
    static func zeichnung(_ planung: Planung) -> (daten: Data, groesse: CGSize)? {
        imHellen {
            // 32 = die beiden 16-Punkt-Ränder der Druckansicht.
            let zeichner = ImageRenderer(content: Druckansicht(planung: planung)
                .environment(\.colorScheme, .light)
                .frame(width: Druckansicht.breite(planung) + 32))

            var ergebnis: (daten: Data, groesse: CGSize)?
            zeichner.render(rasterizationScale: 2) { groesse, zeichnen in
                var kasten = CGRect(origin: .zero, size: groesse)
                let puffer = NSMutableData()
                guard let verbraucher = CGDataConsumer(data: puffer),
                      let seite = CGContext(consumer: verbraucher, mediaBox: &kasten, nil) else { return }
                seite.beginPDFPage(nil)
                zeichnen(seite)
                seite.endPDFPage()
                seite.closePDF()
                ergebnis = (puffer as Data, groesse)
            }
            return ergebnis
        }
    }

    /// Kursfarben wechseln mit dem Erscheinungsbild des Systems; gedruckt und
    /// gesichert wird immer die helle Fassung — gleich, in welchem Modus die
    /// App gerade läuft.
    static func imHellen<T>(_ zeichnen: () -> T) -> T {
        guard let hell = NSAppearance(named: .aqua) else { return zeichnen() }
        var ergebnis: T!
        hell.performAsCurrentDrawingAppearance { ergebnis = zeichnen() }
        return ergebnis
    }

    // ── Der Ausdruck: Blatt für Blatt ─────────────────────────────────────
    // Die eine große Zeichnung zu kacheln ließ Kopfzeilen fehlen und schnitt Zellen durch.

    /// Was auf ein Blatt passt: Papier minus der eigenen Ränder, begrenzt auf
    /// das, was der Drucker überhaupt bedrucken kann. Die 300 sind nur noch
    /// der Auffangwert für entartete Angaben — kleines Papier bekommt kleine,
    /// aber vollständige Blätter statt abgeschnittener.
    static func blattmass(_ angaben: NSPrintInfo) -> CGSize {
        let papier = angaben.paperSize
        let bedruckbar = angaben.imageablePageBounds
        let breite = min(papier.width - angaben.leftMargin - angaben.rightMargin,
                         bedruckbar.width)
        let hoehe = min(papier.height - angaben.topMargin - angaben.bottomMargin,
                        bedruckbar.height)
        return CGSize(width: breite > 0 ? breite : 300,
                      height: hoehe > 0 ? hoehe : 300)
    }

    /// Die Höhe, die eine Ansicht bei dieser Breite wirklich einnimmt —
    /// gemessen mit demselben Anordner, der sie gleich zeichnet. Eine eigene
    /// Rechnung nebenher liefe der Anordnung über kurz oder lang davon.
    static func hoehe(_ ansicht: some View, breite: CGFloat) -> CGFloat {
        var gemessen: CGFloat = 0
        ImageRenderer(content: ansicht.frame(width: breite, alignment: .topLeading))
            .render { groesse, _ in gemessen = groesse.height }
        return gemessen
    }

    /// Erst die Wochen in Gruppen, die neben der Kursspalte auf ein Blatt
    /// passen, dann je Gruppe die Zeilen in Bänder, die keine Zeile
    /// durchschneiden.
    static func blaetter(_ planung: Planung, mass: CGSize) -> [Druckseite] {
        let stand = planung.wochenstand()
        let wochen = stand.wochen
        let inhalt = Zellenverzeichnis(planung)
        guard !wochen.isEmpty else { return [] }

        let jeBlatt = max(1, Int((mass.width - Druckmasse.spalteKlasse)
                                 / Druckmasse.spalteWoche))
        let spalteWoche = (mass.width - Druckmasse.spalteKlasse) / CGFloat(jeBlatt)

        func zeilenraster(_ gruppe: [Woche], _ klasse: Klasse) -> Druckraster {
            Druckraster(planung: planung, wochen: gruppe, stand: stand, klassen: [klasse],
                        inhalt: inhalt, spalteWoche: spalteWoche, mitKopfzeile: false)
        }

        var roh: [(wochen: [Woche], klassen: [Klasse])] = []
        for anfang in stride(from: 0, to: wochen.count, by: jeBlatt) {
            let gruppe = Array(wochen[anfang..<min(anfang + jeBlatt, wochen.count)])
            // Kopfhöhe am leeren Blatt gemessen statt geschätzt, Umbrüche inbegriffen.
            let kopfhoehe = hoehe(Druckseite(planung: planung, wochen: gruppe, stand: stand,
                                             klassen: [], inhalt: inhalt,
                                             spalteWoche: spalteWoche, blatt: 1, blaetter: 1),
                                  breite: mass.width)
            let platz = max(60, mass.height - kopfhoehe)

            let hoehen = planung.klassen.map {
                hoehe(zeilenraster(gruppe, $0), breite: mass.width)
            }
            // Ohne Zeilen bleibt ein Blatt mit Titel und Wochenköpfen.
            for band in hoehen.isEmpty ? [[]] : baender(hoehen, platz: platz) {
                roh.append((gruppe, band.map { planung.klassen[$0] }))
            }
        }

        return roh.enumerated().map { stelle, blatt in
            Druckseite(planung: planung, wochen: blatt.wochen, stand: stand,
                       klassen: blatt.klassen, inhalt: inhalt,
                       spalteWoche: spalteWoche, blatt: stelle + 1, blaetter: roh.count)
        }
    }

    /// Zeilen zu Bändern bündeln — **das höchste Band so niedrig wie möglich**.
    ///
    /// Der Reihe nach zu füllen, bis nichts mehr passt, lässt das letzte Band
    /// halb leer stehen: acht Zeilen auf dem einen Blatt, fünf auf dem nächsten,
    /// das sieht nach Versehen aus. Deshalb erst zählen, wie viele Bänder es
    /// mindestens braucht, und dann die kleinste Grenze suchen, mit der es bei
    /// dieser Zahl bleibt. Die Blattzahl ändert sich dadurch nicht, nur die
    /// Verteilung.
    static func baender(_ hoehen: [CGFloat], platz: CGFloat) -> [[Int]] {
        func fuellen(_ grenze: CGFloat) -> [[Int]] {
            var alle: [[Int]] = []
            var band: [Int] = []
            var stand: CGFloat = 0
            for (stelle, hoehe) in hoehen.enumerated() {
                if !band.isEmpty, stand + hoehe > grenze {
                    alle.append(band)
                    band = []
                    stand = 0
                }
                band.append(stelle)
                stand += hoehe
            }
            if !band.isEmpty { alle.append(band) }
            return alle
        }

        let erste = fuellen(platz)
        let noetig = erste.count
        guard noetig > 1 else { return erste }

        // Untergrenze ist die höchste Zeile: darunter entstünden überlaufende Bänder.
        var unten = min(hoehen.max() ?? platz, platz)
        var oben = platz
        for _ in 0..<20 {
            let mitte = (unten + oben) / 2
            if fuellen(mitte).count <= noetig { oben = mitte } else { unten = mitte }
        }
        return fuellen(oben)
    }

    /// Alle Blätter in **einem** PDF, jedes Blatt eine Seite in Papiergröße.
    ///
    /// Eine einzelne Zeile kann höher sein, als ein Blatt trägt (viele Vorhaben
    /// in einer Woche). Sie bekommt ihr eigenes Blatt und wird so weit
    /// verkleinert, dass sie ganz daraufpasst — lieber kleiner als
    /// abgeschnitten.
    static func blattzeichnung(_ planung: Planung, mass: CGSize) -> (daten: Data, blaetter: Int)? {
        let seiten = blaetter(planung, mass: mass)
        guard !seiten.isEmpty else { return nil }

        var kasten = CGRect(origin: .zero, size: mass)
        let puffer = NSMutableData()
        guard let verbraucher = CGDataConsumer(data: puffer),
              let feld = CGContext(consumer: verbraucher, mediaBox: &kasten, nil) else { return nil }

        imHellen {
            for seite in seiten {
                let natuerlich = hoehe(seite, breite: mass.width)
                let faktor = natuerlich > mass.height ? mass.height / natuerlich : 1
                let zeichner = ImageRenderer(content: seite
                    .frame(width: mass.width, alignment: .topLeading)
                    .scaleEffect(faktor, anchor: .topLeading)
                    .frame(width: mass.width, height: mass.height, alignment: .topLeading)
                    .background(Color.white))
                zeichner.render(rasterizationScale: 2) { _, zeichnen in
                    feld.beginPDFPage(nil)
                    zeichnen(feld)
                    feld.endPDFPage()
                }
            }
        }
        feld.closePDF()
        return (puffer as Data, seiten.count)
    }
}

/// Trägt die fertig gezeichneten Blätter aufs Papier: eine gewöhnliche
/// `NSView`, die in `draw(_:)` die jeweilige PDF-Seite zeichnet. Die Blätter
/// liegen darin untereinander; welches wohin gehört, sagt `rectForPage(_:)`.
final class Druckblatt: NSView {
    private let planung: Planung
    /// Beides behalten: Eine `CGPDFPage` gehört ihrem Schriftstück — wer nur
    /// die Seite festhält, zeichnet unter Umständen aus freigegebenem Speicher.
    private var schriftstueck: CGPDFDocument
    private var seiten: [CGPDFPage]
    private var blattmass: CGSize

    init?(_ planung: Planung, mass: CGSize) {
        guard let gezeichnet = Druckblatt.zeichnen(planung, mass: mass) else { return nil }
        self.planung = planung
        schriftstueck = gezeichnet.schriftstueck
        seiten = gezeichnet.seiten
        blattmass = mass
        super.init(frame: CGRect(x: 0, y: 0, width: mass.width,
                                 height: mass.height * CGFloat(gezeichnet.seiten.count)))
    }

    private static func zeichnen(_ planung: Planung, mass: CGSize)
        -> (schriftstueck: CGPDFDocument, seiten: [CGPDFPage])? {
        guard let (daten, anzahl) = Drucken.blattzeichnung(planung, mass: mass), anzahl > 0,
              let quelle = CGDataProvider(data: daten as CFData),
              let gelesen = CGPDFDocument(quelle) else { return nil }
        let gefunden = (1...gelesen.numberOfPages).compactMap { gelesen.page(at: $0) }
        guard !gefunden.isEmpty else { return nil }
        return (gelesen, gefunden)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht aus einer Datei geladen") }

    /// Der Ursprung unten links wie im PDF — sonst stünde alles auf dem Kopf.
    override var isFlipped: Bool { false }

    /// Die Aufteilung kommt von hier, nicht von AppKit: Wo ein Blatt endet,
    /// steht schon beim Zeichnen fest.
    ///
    /// Im Druckdialog lassen sich Drucker, Papier und Ausrichtung noch ändern.
    /// AppKit fragt danach erneut hier nach — der Ausdruck wird deshalb gegen
    /// die dann gültigen Angaben neu gezeichnet, statt in der Breite von vorhin
    /// über den Blattrand zu laufen.
    override func knowsPageRange(_ bereich: NSRangePointer) -> Bool {
        if let angaben = NSPrintOperation.current?.printInfo { nachziehen(angaben) }
        bereich.pointee = NSRange(location: 1, length: seiten.count)
        return true
    }

    /// Neu zeichnen, sobald der Auftrag ein anderes Blattmaß trägt. Bleibt es
    /// wie gehabt — der Regelfall —, geschieht nichts; die Vorschau des
    /// Druckdialogs fragt mehrfach nach.
    private func nachziehen(_ angaben: NSPrintInfo) {
        Drucken.raender(angaben)
        let mass = Drucken.blattmass(angaben)
        guard mass != blattmass,
              let gezeichnet = Druckblatt.zeichnen(planung, mass: mass) else { return }
        schriftstueck = gezeichnet.schriftstueck
        seiten = gezeichnet.seiten
        blattmass = mass
        setFrameSize(CGSize(width: mass.width,
                            height: mass.height * CGFloat(gezeichnet.seiten.count)))
    }

    override func rectForPage(_ nummer: Int) -> NSRect {
        NSRect(x: 0, y: bounds.height - CGFloat(nummer) * blattmass.height,
               width: blattmass.width, height: blattmass.height)
    }

    override func draw(_ ausschnitt: NSRect) {
        guard let zeichenfeld = NSGraphicsContext.current?.cgContext else { return }
        for (stelle, seite) in seiten.enumerated() {
            let platz = rectForPage(stelle + 1)
            guard platz.intersects(ausschnitt) else { continue }
            zeichenfeld.saveGState()
            zeichenfeld.translateBy(x: platz.minX, y: platz.minY)
            zeichenfeld.drawPDFPage(seite)
            zeichenfeld.restoreGState()
        }
    }
}

/// Die Maße der Druckfassung. Die Wochenspalte ist ein **Mindestmaß**: Auf dem
/// Blatt wird die überzählige Breite auf die Wochen verteilt, damit kein Streifen
/// Papier ungenutzt bleibt.
enum Druckmasse {
    static let spalteKlasse: CGFloat = 150
    static let spalteWoche: CGFloat = 190
}

/// Die ganze Planung an einem Stück — das ist es, was „Als PDF sichern“ ablegt:
/// eine einzige, beliebig breite Seite mit Titel darüber.
struct Druckansicht: View {
    let planung: Planung

    static func breite(_ planung: Planung) -> CGFloat {
        Druckmasse.spalteKlasse + Druckmasse.spalteWoche * CGFloat(max(1, planung.wochen))
    }

    var body: some View {
        let stand = planung.wochenstand()

        VStack(alignment: .leading, spacing: 0) {
            titelblock
            Druckraster(planung: planung, wochen: stand.wochen, stand: stand,
                        klassen: planung.klassen,
                        inhalt: Zellenverzeichnis(planung))
        }
        .padding(16)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var titelblock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(planung.titel).font(.system(size: 20, weight: .semibold))
            Text(planung.kennzahlen).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }
}

/// Ein einzelnes Blatt des Ausdrucks: ein Ausschnitt aus Wochen und Zeilen, für
/// sich lesbar. Kursspalte und Wochenkopf stehen auf **jedem** Blatt.
struct Druckseite: View {
    let planung: Planung
    let wochen: [Woche]
    let stand: Wochenstand
    let klassen: [Klasse]
    let inhalt: Zellenverzeichnis
    let spalteWoche: CGFloat
    let blatt: Int
    let blaetter: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kopf
            Druckraster(planung: planung, wochen: wochen, stand: stand, klassen: klassen,
                        inhalt: inhalt, spalteWoche: spalteWoche)
        }
        .padding(.bottom, 4)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    /// Eine Zeile Kopf: Titel links, Blattzählung rechts. Beim Zusammenlegen
    /// eines Stapels ist das die einzige Angabe, die von außen weiterhilft.
    private var kopf: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(planung.titel).font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            Text("Blatt \(blatt) von \(blaetter)")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 6)
    }
}

/// Kopfzeile und Zeilen — der Teil, den beide Fassungen gemeinsam haben.
struct Druckraster: View {
    let planung: Planung
    let wochen: [Woche]
    /// Lagen und Schulwochen der **ganzen** Planung — nachgeschlagen wird über
    /// `woche.nummer`, auch wenn auf dem Blatt nur ein Ausschnitt steht.
    let stand: Wochenstand
    let klassen: [Klasse]
    let inhalt: Zellenverzeichnis
    var spalteWoche: CGFloat = Druckmasse.spalteWoche
    var mitKopfzeile = true

    private var spalteKlasse: CGFloat { Druckmasse.spalteKlasse }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mitKopfzeile { kopfzeile }
            ForEach(klassen) { klasse in
                zeile(klasse: klasse)
            }
        }
    }

    private var kopfzeile: some View {
        HStack(spacing: 0) {
            Text("Klasse/Kurs")
                .font(.system(size: 10, weight: .semibold))
                .padding(6)
                .frame(width: spalteKlasse, alignment: .leading)
            ForEach(wochen) { woche in
                let lage = stand.lage(woche)
                VStack(alignment: .leading, spacing: 1) {
                    Text(woche.beschriftung(schulwoche: stand.schulwoche(woche)))
                        .font(.system(size: 11, weight: .semibold))
                    Text(woche.spanne).font(.system(size: 9)).foregroundStyle(.secondary)
                    if lage.frei || lage.teilweise {
                        Text(lage.name).font(.system(size: 8))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(6)
                .frame(width: spalteWoche, alignment: .leading)
            }
        }
        .overlay(alignment: .bottom) { Color.black.opacity(0.35).frame(height: 1) }
    }

    private func zeile(klasse: Klasse) -> some View {
        let ton = Farbwelt.ton(klasse.farbe)
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(klasse.name).font(.system(size: 11, weight: .semibold))
                if !klasse.fach.isEmpty {
                    Text(klasse.fach).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .frame(width: spalteKlasse, alignment: .topLeading)
            .overlay(alignment: .leading) { Kursfarben.farbe(ton).frame(width: 3) }

            ForEach(wochen) { woche in
                druckzelle(klasse: klasse, woche: woche, lage: stand.lage(woche), ton: ton,
                           eintraege: inhalt[klasse.id, woche.nummer])
            }
        }
        .overlay(alignment: .bottom) { Color.black.opacity(0.12).frame(height: 1) }
    }

    private func druckzelle(klasse: Klasse, woche: Woche, lage: Wochenlage, ton: Farbton,
                            eintraege: [Vorhaben]) -> some View {
        let frei = lage.frei || planung.istZelleFrei(klasse: klasse.id, woche: woche)
        return VStack(alignment: .leading, spacing: 4) {
            if frei, eintraege.isEmpty {
                Text("unterrichtsfrei").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            ForEach(eintraege) { eintrag in
                druckkachel(eintrag, ton: ton)
            }
        }
        .padding(5)
        .frame(width: spalteWoche, alignment: .topLeading)
        .frame(minHeight: 54, alignment: .topLeading)
        .background(frei ? Color.black.opacity(0.05) : Kursfarben.zeile(ton))
        .overlay(alignment: .trailing) { Color.black.opacity(0.12).frame(width: 1) }
    }

    /// Auf Papier gibt es kein Überfahren und keine Farbtiefe: Prüfung, Datum
    /// und Dringlichkeit stehen deshalb als Wort da, nicht nur als Rahmen.
    @ViewBuilder
    private func druckmarken(_ eintrag: Vorhaben) -> some View {
        if eintrag.pruefung || eintrag.datum != nil || eintrag.dringend {
            HStack(spacing: 6) {
                if eintrag.pruefung {
                    Text("Prüfung · " + (eintrag.pruefungstag?.mitWochentag ?? "Termin offen"))
                        .foregroundStyle(Color(nsColor: Rasterfarben.pruefung))
                }
                if let tag = eintrag.datum {
                    Text("Datum · " + tag.mitWochentag).foregroundStyle(.secondary)
                }
                if eintrag.dringend {
                    Dringlichkeitsmarke.text
                }
            }
            .font(.system(size: 8, weight: .semibold))
        }
    }

    private func druckkachel(_ eintrag: Vorhaben, ton: Farbton) -> some View {

        VStack(alignment: .leading, spacing: 2) {
            druckmarken(eintrag)
            HStack(alignment: .top, spacing: 3) {
                if eintrag.erledigt {
                    Image(systemName: Zeichen.haken).font(.system(size: 8, weight: .bold))
                }
                Text(eintrag.anzeigeTitel)
                    .font(.system(size: 10, weight: .medium))
                    .strikethrough(eintrag.erledigt)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !eintrag.text.isEmpty {
                Text(eintrag.text).font(.system(size: 8.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(eintrag.materialien) { material in
                Text("• " + (material.titel.isEmpty ? Pfade.dateiName(material.pfad) : material.titel))
                    .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
            ForEach(eintrag.links) { link in
                Text("↗ " + (link.titel.isEmpty ? Weblinks.name(link.adresse) : link.titel))
                    .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Kursfarben.flaeche(ton))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(eintrag.dringend
                                      ? Color(nsColor: Rasterfarben.dringendStark)
                                      : Kursfarben.farbe(ton).opacity(0.45),
                                      lineWidth: eintrag.dringend ? 1.2 : 0.7)
                }
        }
    }
}
