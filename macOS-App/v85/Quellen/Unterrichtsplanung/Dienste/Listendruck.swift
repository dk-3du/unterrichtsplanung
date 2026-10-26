// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import UniformTypeIdentifiers

// ── Eine Liste auf Papier und als Datei (E401, E405, E407, E411) ──────────
//
// Gedruckt wird über das Schriftstück im Speicher (`Listensatz.druckschriftstueck`):
// Seite für Seite, eingepasst ins Bedruckbare wie der Sitzplan. Gesichert wird nur
// das verschlüsselte PDF (`Listensatz.pdf`). Der Druckdialog bietet daneben PDF-Wege
// an — „Als PDF sichern“, „In Vorschau öffnen“, Arbeitsabläufe —, die unverschlüsselt
// ablegten; eine Option, sie auszublenden, gibt es nicht. Nach dem Dialog steht fest,
// wohin der Auftrag geht: Nur an einen Drucker gibt das Blatt Seiten her (E407).

@MainActor
enum Listendruck {

    /// Wohin ein Druckauftrag nach dem Dialog geht.
    enum Druckweg: Equatable, Sendable {
        /// An einen Drucker — der einzige Weg, auf dem Seiten entstehen.
        case drucker
        /// Ein PDF-Weg des Druckdialogs oder ein Ziel, das sich nicht bestimmen lässt.
        case pdfWeg
        /// Im Dialog abgebrochen.
        case abgebrochen
    }

    /// Das Ziel des Auftrags, wie das Drucksystem es nennt (`PMDestinationType`).
    enum Druckziel: Equatable, Sendable {
        case drucker, datei, fax, vorschau, pdfArbeitsablauf, unbekannt

        init(pm typ: PMDestinationType) {
            switch Int(typ) {
            case Int(kPMDestinationPrinter): self = .drucker
            case Int(kPMDestinationFile): self = .datei
            case Int(kPMDestinationFax): self = .fax
            case Int(kPMDestinationPreview): self = .vorschau
            case Int(kPMDestinationProcessPDF): self = .pdfArbeitsablauf
            default: self = .unbekannt
            }
        }
    }

    /// Nur ein Auftrag an den Drucker darf Seiten bekommen; alles andere gilt als PDF-Weg —
    /// auch ein Ziel, das sich nicht bestimmen lässt (E407).
    static func druckweg(auftrag: NSPrintInfo.JobDisposition, ziel: Druckziel) -> Druckweg {
        if auftrag == .cancel { return .abgebrochen }
        return auftrag == .spool && ziel == .drucker ? .drucker : .pdfWeg
    }

    /// Der Weg des laufenden Druckvorgangs — ohne Vorgang ein PDF-Weg: Gezeichnet wird dann nichts.
    static func wegDesAuftrags() -> Druckweg {
        guard let angaben = NSPrintOperation.current?.printInfo else { return .pdfWeg }
        return druckweg(auftrag: angaben.jobDisposition, ziel: ziel(angaben))
    }

    /// Das Ziel aus den Einstellungen des Drucksystems — `unbekannt`, wenn es sich nicht lesen lässt.
    static func ziel(_ angaben: NSPrintInfo) -> Druckziel {
        var typ = PMDestinationType(0)
        let sitzung = OpaquePointer(angaben.pmPrintSession())
        let einstellungen = OpaquePointer(angaben.pmPrintSettings())
        guard PMSessionGetDestinationType(sitzung, einstellungen, &typ) == 0 else { return .unbekannt }
        return Druckziel(pm: typ)
    }

    /// Was das Blatt mit einem Auftrag tut.
    enum Behandlung: Equatable, Sendable {
        /// Die Seiten zeichnen.
        case zeichnen
        /// Den Auftrag abbrechen, bevor eine Ausgabe entsteht, und es melden — gezeichnet wird nichts.
        case abweisen
        /// Nichts zeichnen, nichts melden — der Auftrag ist schon abgebrochen.
        case nichts
    }

    static func behandlung(_ weg: Druckweg) -> Behandlung {
        switch weg {
        case .drucker: .zeichnen
        case .pdfWeg: .abweisen
        case .abgebrochen: .nichts
        }
    }

    /// Wo Seite `nummer` (ab 1) im Blatt liegt: untereinander, die erste oben.
    static func seitenrahmen(_ nummer: Int, seiten: Int, mass: CGSize) -> NSRect {
        NSRect(x: 0, y: CGFloat(seiten - nummer) * mass.height, width: mass.width, height: mass.height)
    }

    /// Die Abbildung, die eine Seite mit `kasten` in `platz` einpasst — Seitenverhältnis gewahrt, mittig,
    /// wie beim Sitzplan.
    static func einpassung(_ kasten: CGRect, in platz: CGRect) -> CGAffineTransform {
        guard kasten.width > 0, kasten.height > 0 else { return .identity }
        let faktor = min(platz.width / kasten.width, platz.height / kasten.height)
        return CGAffineTransform(translationX: platz.minX + (platz.width - kasten.width * faktor) / 2,
                                 y: platz.minY + (platz.height - kasten.height * faktor) / 2)
            .scaledBy(x: faktor, y: faktor)
            .translatedBy(x: -kasten.minX, y: -kasten.minY)
    }

    /// Ein Druckvorgang mit dem Druckdialog — `nil`, wenn sich die Liste nicht setzen lässt. Der Auftrag
    /// beginnt als Auftrag an den Drucker; `abgewiesen` meldet einen PDF-Weg, einmal je Vorgang.
    static func vorgang(_ liste: Liste, titel: String, angaben: NSPrintInfo = Drucken.druckangaben(),
                        abgewiesen: @escaping @MainActor () -> Void) -> NSPrintOperation? {
        // Die Vorschau im Dialog zeigt die Seiten nur für einen Auftrag an den Drucker — so beginnt er.
        angaben.jobDisposition = .spool
        guard let dokument = Listensatz.druckschriftstueck(liste),
              let blatt = Listenblatt(dokument, mass: Drucken.blattmass(angaben), abgewiesen: abgewiesen) else { return nil }
        let vorgang = NSPrintOperation(view: blatt, printInfo: angaben)
        vorgang.jobTitle = titel
        vorgang.showsPrintPanel = true
        vorgang.showsProgressPanel = true
        return vorgang
    }

    /// Das verschlüsselte PDF an den Ort des Sichern-Dialogs — ohne Rückfrage; abgebrochen heißt: nichts.
    static func sichern(_ daten: Data, dateiname: String, gruppe: String, speicher: Planungsspeicher) {
        Systemzugriff.zielWaehlen(name: dateiname, nachricht: Rueckmeldungslistenbogen.sichernNachricht,
                                  typ: .pdf) { ziel in
            guard let ziel else { return }
            let meldung = schreiben(daten, nach: ziel, gruppe: gruppe)
            speicher.melden(meldung.text, meldung.art)
        }
    }

    /// Schreibt `daten` — das verschlüsselte PDF — und sagt, wie es ging.
    static func schreiben(_ daten: Data, nach ziel: URL, gruppe: String) -> (text: String, art: Meldung.Art) {
        do {
            try daten.write(to: ziel, options: .atomic)
            return (Rueckmeldungslistenbogen.gesichert(gruppe), .hinweis)
        } catch {
            return ("Die PDF-Datei konnte nicht geschrieben werden: " + error.localizedDescription, .warnung)
        }
    }
}

/// Trägt die Seiten des Schriftstücks aufs Papier — untereinander, je Seite eingepasst ins
/// Bedruckbare. Gezeichnet wird nur für einen Auftrag an den Drucker (E407).
final class Listenblatt: NSView {
    /// Beides behalten: Eine `CGPDFPage` gehört ihrem Schriftstück.
    private let schriftstueck: CGPDFDocument
    private let seiten: [CGPDFPage]
    private var blattmass: CGSize
    private let abgewiesen: @MainActor () -> Void
    private var abweisungGemeldet = false

    /// Wohin der laufende Auftrag geht — im Betrieb aus dem Druckvorgang; die Suite gibt es vor.
    var wegLesen: @MainActor () -> Listendruck.Druckweg = { Listendruck.wegDesAuftrags() }

    init?(_ dokument: CGPDFDocument, mass: CGSize, abgewiesen: @escaping @MainActor () -> Void) {
        let gefunden = dokument.numberOfPages > 0 ? (1...dokument.numberOfPages).compactMap { dokument.page(at: $0) } : []
        guard !gefunden.isEmpty else { return nil }
        schriftstueck = dokument
        seiten = gefunden
        blattmass = mass
        self.abgewiesen = abgewiesen
        super.init(frame: CGRect(x: 0, y: 0, width: mass.width, height: mass.height * CGFloat(gefunden.count)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht aus einer Datei geladen") }

    /// Der Ursprung unten links wie im PDF.
    override var isFlipped: Bool { false }

    var seitenzahl: Int { seiten.count }

    /// Nach dem Dialog steht der Weg fest. Ein PDF-Weg wird abgebrochen, bevor eine Ausgabe entsteht, und einmal
    /// gemeldet. Die Seiten nennt das Blatt immer alle: Ohne Seiten zeigt AppKit einen Fehler (gemessen).
    /// Ändert der Dialog Papier oder Ränder, wird das Blattmaß nachgezogen.
    override func knowsPageRange(_ bereich: NSRangePointer) -> Bool {
        let vorgang = NSPrintOperation.current
        if let angaben = vorgang?.printInfo { nachziehen(angaben) }
        bereich.pointee = NSRange(location: 1, length: seiten.count)
        guard Listendruck.behandlung(wegLesen()) == .abweisen else { return true }
        vorgang?.printInfo.jobDisposition = .cancel
        if !abweisungGemeldet {
            abweisungGemeldet = true
            abgewiesen()
        }
        return true
    }

    private func nachziehen(_ angaben: NSPrintInfo) {
        Drucken.raender(angaben)
        let mass = Drucken.blattmass(angaben)
        guard mass != blattmass else { return }
        blattmass = mass
        setFrameSize(CGSize(width: mass.width, height: mass.height * CGFloat(seiten.count)))
    }

    override func rectForPage(_ nummer: Int) -> NSRect {
        Listendruck.seitenrahmen(nummer, seiten: seiten.count, mass: blattmass)
    }

    override func draw(_ ausschnitt: NSRect) {
        guard Listendruck.behandlung(wegLesen()) == .zeichnen, let feld = NSGraphicsContext.current?.cgContext else { return }
        _ = schriftstueck
        for (stelle, seite) in seiten.enumerated() {
            let platz = rectForPage(stelle + 1)
            guard platz.intersects(ausschnitt) else { continue }
            feld.saveGState()
            feld.concatenate(Listendruck.einpassung(seite.getBoxRect(.mediaBox), in: platz))
            feld.drawPDFPage(seite)
            feld.restoreGState()
        }
    }
}
