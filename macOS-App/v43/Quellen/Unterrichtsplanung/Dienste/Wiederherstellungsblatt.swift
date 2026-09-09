// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Das Blatt mit dem Wiederherstellungsschlüssel — gedruckt oder als PDF,
/// nie in der App gespeichert. Derselbe Weg wie beim Ausdruck: vektoriell
/// gezeichnet, aufs Papier von einer schlichten `NSView` (siehe `Drucken`).
@MainActor
enum Wiederherstellungsblatt {

    /// A4 hochkant in Punkt; der Rand kommt vom Drucker (`Drucken.raender`).
    static let seite = CGSize(width: 595, height: 842)

    static func drucken(schluessel: String, planungstitel: String, speicher: Planungsspeicher) {
        let angaben = Drucken.druckangaben()
        angaben.orientation = .portrait
        Drucken.raender(angaben)
        guard let blatt = Einzelblatt(pdf: zeichnung(schluessel: schluessel, planungstitel: planungstitel),
                                      mass: Drucken.blattmass(angaben)) else {
            speicher.melden("Das Wiederherstellungsblatt ließ sich nicht zeichnen.", .warnung)
            return
        }
        let vorgang = NSPrintOperation(view: blatt, printInfo: angaben)
        vorgang.jobTitle = "Wiederherstellungsschlüssel — " + planungstitel
        vorgang.showsPrintPanel = true
        vorgang.showsProgressPanel = true
        vorgang.run()
    }

    static func alsPDFSichern(schluessel: String, planungstitel: String, speicher: Planungsspeicher) {
        let dialog = NSSavePanel()
        dialog.message = "Wiederherstellungsblatt als PDF sichern"
        dialog.nameFieldStringValue = Planungsdatei.exportName(
            titel: "Wiederherstellungsschluessel " + planungstitel, endung: "pdf")
        dialog.allowedContentTypes = [.pdf]
        dialog.canCreateDirectories = true
        guard dialog.runModal() == .OK, let ziel = dialog.url else { return }
        let erfolg = zeichnung(schluessel: schluessel, planungstitel: planungstitel)
            .map { (try? $0.write(to: ziel, options: .atomic)) != nil } ?? false
        speicher.melden(erfolg ? "Wiederherstellungsblatt als PDF gesichert — bitte an einem "
                                 + "sicheren Ort verwahren, nicht neben der Planung."
                               : "Die PDF-Datei konnte nicht geschrieben werden.",
                        erfolg ? .hinweis : .warnung)
    }

    /// Eine A4-Seite als vektorielles PDF.
    static func zeichnung(schluessel: String, planungstitel: String) -> Data? {
        Drucken.imHellen {
            let zeichner = ImageRenderer(content: Blattansicht(schluessel: schluessel,
                                                               planungstitel: planungstitel)
                .frame(width: seite.width, height: seite.height, alignment: .topLeading)
                .environment(\.colorScheme, .light))
            var ergebnis: Data?
            zeichner.render(rasterizationScale: 2) { groesse, zeichnen in
                var kasten = CGRect(origin: .zero, size: groesse)
                let puffer = NSMutableData()
                guard let verbraucher = CGDataConsumer(data: puffer),
                      let feld = CGContext(consumer: verbraucher, mediaBox: &kasten, nil) else { return }
                feld.beginPDFPage(nil)
                zeichnen(feld)
                feld.endPDFPage()
                feld.closePDF()
                ergebnis = puffer as Data
            }
            return ergebnis
        }
    }
}

/// Der Inhalt des Blattes.
struct Blattansicht: View {
    let schluessel: String
    let planungstitel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Wiederherstellungsschlüssel")
                .font(.system(size: 22, weight: .semibold))
            Text("Unterrichtsplanung — „\(planungstitel)“ · erzeugt am "
                 + Tag.heute.deutsch)
                .font(.system(size: 12)).foregroundStyle(.secondary)

            Text(schluessel)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .kerning(1.5)
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.black.opacity(0.4), lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text("Dieser Schlüssel öffnet die verschlüsselte Planung, wenn die Passphrase "
                     + "vergessen ist — die Ablage auf dem Mac, die Kopie im Zielordner und "
                     + "jede exportierte Datei. Er wird nirgends gespeichert: Ohne dieses "
                     + "Blatt und ohne Passphrase ist die Planung nicht mehr zu öffnen.")
                Text("Bitte an einem sicheren Ort verwahren — nicht im selben Ordner wie die "
                     + "Planung und nicht in der Cloud, in der die Kopie liegt.")
                Text("Groß- und Kleinschreibung, Bindestriche und Leerzeichen spielen beim "
                     + "Eingeben keine Rolle; die Ziffern 0 und 1 kommen nicht vor.")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(48)
        .background(Color.white)
    }
}

/// Eine PDF-Seite aufs Papier — `Druckblatt` für ein Blatt ohne Planung.
final class Einzelblatt: NSView {
    /// Die Seite gehört ihrem Schriftstück; beides behalten.
    private let schriftstueck: CGPDFDocument
    private let seite: CGPDFPage
    private let mass: CGSize

    init?(pdf: Data?, mass: CGSize) {
        guard let pdf, let quelle = CGDataProvider(data: pdf as CFData),
              let gelesen = CGPDFDocument(quelle), let erste = gelesen.page(at: 1) else { return nil }
        schriftstueck = gelesen
        seite = erste
        self.mass = mass
        super.init(frame: CGRect(origin: .zero, size: mass))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht aus einer Datei geladen") }

    override var isFlipped: Bool { false }

    override func knowsPageRange(_ bereich: NSRangePointer) -> Bool {
        bereich.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ nummer: Int) -> NSRect { bounds }

    /// Die A4-Zeichnung wird auf das bedruckbare Maß verkleinert — lieber
    /// kleiner als abgeschnitten.
    override func draw(_ ausschnitt: NSRect) {
        guard let feld = NSGraphicsContext.current?.cgContext else { return }
        let kasten = seite.getBoxRect(.mediaBox)
        let faktor = min(mass.width / kasten.width, mass.height / kasten.height, 1)
        feld.saveGState()
        feld.translateBy(x: 0, y: mass.height - kasten.height * faktor)
        feld.scaleBy(x: faktor, y: faktor)
        feld.drawPDFPage(seite)
        feld.restoreGState()
    }
}
