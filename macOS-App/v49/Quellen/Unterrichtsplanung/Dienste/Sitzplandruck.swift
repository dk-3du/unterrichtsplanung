// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Der Sitzplan auf Papier — eine Seite DIN A4 quer (E29): Kopfzeile
/// „Klasse/Kurs · Fach · Sitzplan · Stand“, darunter die Fläche 1:1, die
/// Tafel unten. Gezeichnet vektoriell wie die Planung (`Drucken`); PDF und
/// Ausdruck nehmen dieselbe Seite.
@MainActor
enum Sitzplandruck {

    /// DIN A4 quer in Punkten.
    static let blatt = CGSize(width: 842, height: 595)

    static func kopfzeile(_ klasse: Klasse, plan: Sitzplan) -> String {
        let stand = Zeitrechnung.zeitpunkt(aus: plan.geaendert).map { Tag($0).deutsch } ?? Tag.heute.deutsch
        var teile = [klasse.name]
        if !klasse.fach.isEmpty { teile.append(klasse.fach) }
        teile.append("Sitzplan")
        teile.append("Stand " + stand)
        return teile.joined(separator: " · ")
    }

    /// Die Seite als vektorielles PDF — eine Seite in Blattgröße. Mit
    /// `kennwort` trägt sie den Kennwortschutz des PDF-Formats (E40):
    /// Nutzer- und Eigentümerkennwort, 128 Bit — Vorschau und andere Leser
    /// fragen danach.
    static func pdf(_ plan: Sitzplan, klasse: Klasse, kennwort: String? = nil) -> Data? {
        Drucken.imHellen {
            let zeichner = ImageRenderer(content: Sitzplanseite(plan: plan, klasse: klasse)
                .environment(\.colorScheme, .light))
            var ergebnis: Data?
            zeichner.render(rasterizationScale: 2) { _, zeichnen in
                var kasten = CGRect(origin: .zero, size: blatt)
                let puffer = NSMutableData()
                var zusatz: [CFString: Any] = [:]
                if let kennwort, !kennwort.isEmpty {
                    zusatz[kCGPDFContextUserPassword] = kennwort
                    zusatz[kCGPDFContextOwnerPassword] = kennwort
                    zusatz[kCGPDFContextEncryptionKeyLength] = 128
                }
                guard let verbraucher = CGDataConsumer(data: puffer),
                      let seite = CGContext(consumer: verbraucher, mediaBox: &kasten,
                                            zusatz.isEmpty ? nil : zusatz as CFDictionary) else { return }
                seite.beginPDFPage(nil)
                zeichnen(seite)
                seite.endPDFPage()
                seite.closePDF()
                ergebnis = puffer as Data
            }
            return ergebnis
        }
    }

    private static func dateiname(_ klasse: Klasse) -> String {
        Planungsdatei.exportName(titel: "Sitzplan " + klasse.name + (klasse.fach.isEmpty ? "" : " " + klasse.fach),
                                 endung: "pdf")
    }

    /// Als PDF sichern — bei eingeschalteter Verschlüsselung mit Rückfrage:
    /// Die Datei liegt im Klartext, wo der Nutzer sie hinlegt, und trägt die
    /// Namen der Klasse; im Sichern-Dialog lässt sie sich mit einem Kennwort
    /// schützen (E40). Der Pfad wird nicht gemerkt.
    static func alsPDFSichern(_ plan: Sitzplan, klasse: Klasse, speicher: Planungsspeicher,
                              ort: Rueckfrageort) {
        guard speicher.verschluesselt else {
            pdfSchreiben(plan, klasse: klasse, speicher: speicher)
            return
        }
        speicher.fragen("Die PDF trägt die Namen der Klasse im Klartext, wo immer sie hinkommt — "
                        + "im Sichern-Dialog lässt sie sich mit einem Kennwort schützen.\n\nFortfahren?",
                        bestaetigung: "Als PDF sichern", gefahr: true, ort: ort) {
            pdfSchreiben(plan, klasse: klasse, speicher: speicher)
        }
    }

    private static func pdfSchreiben(_ plan: Sitzplan, klasse: Klasse, speicher: Planungsspeicher) {
        let dialog = NSSavePanel()
        dialog.message = "Sitzplan als PDF sichern"
        dialog.nameFieldStringValue = dateiname(klasse)
        dialog.allowedContentTypes = [.pdf]
        dialog.canCreateDirectories = true
        dialog.isExtensionHidden = false
        // Der Kennwortschutz — vorgewählt, wenn die Planung verschlüsselt ist.
        let zusatz = Kennwortzusatz(vorgewaehlt: speicher.verschluesselt)
        dialog.accessoryView = zusatz
        dialog.delegate = zusatz
        guard dialog.runModal() == .OK, let ziel = dialog.url else { return }
        let kennwort = zusatz.gewaehltesKennwort
        var erfolg = false
        if let daten = pdf(plan, klasse: klasse, kennwort: kennwort) {
            erfolg = (try? daten.write(to: ziel, options: .atomic)) != nil
        }
        speicher.melden(erfolg ? (kennwort == nil ? "Sitzplan als PDF gesichert."
                                                  : "Sitzplan als PDF gesichert — mit Kennwort geschützt.")
                               : "Die PDF-Datei konnte nicht geschrieben werden.",
                        erfolg ? .hinweis : .warnung)
    }

    /// Der Zusatz im Sichern-Dialog (E40): „Mit Kennwort schützen“, Kennwort
    /// und Wiederholung. Geprüft, bevor der Dialog schließt — leer oder
    /// ungleich hält ihn offen.
    @MainActor
    final class Kennwortzusatz: NSView, NSOpenSavePanelDelegate {
        private let schalter = NSButton(checkboxWithTitle: "Mit Kennwort schützen", target: nil, action: nil)
        private let kennwort = NSSecureTextField(frame: NSRect(x: 108, y: 34, width: 240, height: 24))
        private let wiederholung = NSSecureTextField(frame: NSRect(x: 108, y: 4, width: 240, height: 24))

        init(vorgewaehlt: Bool) {
            super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 96))
            schalter.frame = NSRect(x: 0, y: 66, width: 360, height: 20)
            schalter.state = vorgewaehlt ? .on : .off
            schalter.target = self
            schalter.action = #selector(umgeschaltet)
            addSubview(schalter)
            for (beschriftung, feld, y) in [("Kennwort:", kennwort, 36), ("Wiederholung:", wiederholung, 6)] {
                let etikett = NSTextField(labelWithString: beschriftung)
                etikett.frame = NSRect(x: 0, y: CGFloat(y), width: 100, height: 20)
                etikett.alignment = .right
                addSubview(etikett)
                feld.placeholderString = beschriftung == "Kennwort:" ? "für die PDF" : "noch einmal"
                feld.setAccessibilityLabel(beschriftung == "Kennwort:" ? "Kennwort für die PDF" : "Kennwort wiederholen")
                addSubview(feld)
            }
            umgeschaltet()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("nicht aus einer Datei geladen") }

        @objc private func umgeschaltet() {
            let an = schalter.state == .on
            kennwort.isEnabled = an
            wiederholung.isEnabled = an
        }

        /// `nil`, wenn kein Schutz gewählt ist.
        var gewaehltesKennwort: String? {
            schalter.state == .on ? kennwort.stringValue : nil
        }

        func panel(_ sender: Any, validate url: URL) throws {
            guard schalter.state == .on else { return }
            let gewaehlt = kennwort.stringValue
            if gewaehlt.isEmpty {
                throw NSError(domain: "Sitzplandruck", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Bitte ein Kennwort eingeben — oder „Mit Kennwort schützen“ abwählen."])
            }
            if gewaehlt != wiederholung.stringValue {
                throw NSError(domain: "Sitzplandruck", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Die Wiederholung stimmt nicht mit dem Kennwort überein."])
            }
        }
    }

    /// Drucken über dieselbe Seite: Das Blatt trägt die PDF-Seite und passt
    /// sie ins Bedruckbare ein.
    static func drucken(_ plan: Sitzplan, klasse: Klasse, speicher: Planungsspeicher) {
        let angaben = Drucken.druckangaben()
        guard let daten = pdf(plan, klasse: klasse),
              let blatt = Sitzplanblatt(daten, mass: Drucken.blattmass(angaben)) else {
            speicher.melden("Der Sitzplan ließ sich nicht zeichnen.", .warnung)
            return
        }
        let vorgang = NSPrintOperation(view: blatt, printInfo: angaben)
        vorgang.jobTitle = "Sitzplan " + klasse.beschriftung
        vorgang.showsPrintPanel = true
        vorgang.showsProgressPanel = true
        vorgang.run()
    }
}

/// Die eine Seite: Kopfzeile, darunter die Fläche in den Maßen des Editors —
/// Tafel, Lehrertisch, Tische mit Namen.
struct Sitzplanseite: View {
    let plan: Sitzplan
    let klasse: Klasse

    var body: some View {
        let ton = Farbwelt.ton(klasse.farbe)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Sitzplandruck.kopfzeile(klasse, plan: plan))
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(plan.tische.count) " + (plan.tische.count == 1 ? "Platz" : "Plätze"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: Sitzplanmasse.breite)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.black.opacity(0.3), lineWidth: 0.8)
                    .frame(width: Sitzplanmasse.breite, height: Sitzplanmasse.hoehe)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.18))
                    .frame(width: Sitzplanmasse.tafel.width, height: Sitzplanmasse.tafel.height)
                    .overlay { Text("Tafel").font(.system(size: 10)) }
                    .offset(x: Sitzplanmasse.tafel.minX, y: Sitzplanmasse.tafel.minY)

                if let rahmen = plan.lehrertischRahmen {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                        .foregroundStyle(Color.black.opacity(0.5))
                        .frame(width: rahmen.width, height: rahmen.height)
                        .overlay { Text("Lehrertisch").font(.system(size: 9)).foregroundStyle(.secondary) }
                        .offset(x: rahmen.minX, y: rahmen.minY)
                }

                ForEach(plan.tische) { tisch in
                    Text(tisch.name)
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 2)
                        .frame(width: tisch.rahmen.width, height: tisch.rahmen.height)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Kursfarben.flaeche(ton))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Kursfarben.farbe(ton).opacity(0.5), lineWidth: 0.8)
                                }
                        }
                        .offset(x: tisch.x, y: tisch.y)
                }
            }
            .frame(width: Sitzplanmasse.breite, height: Sitzplanmasse.hoehe)
        }
        .frame(width: Sitzplandruck.blatt.width, height: Sitzplandruck.blatt.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

/// Trägt die PDF-Seite aufs Papier — eingepasst ins Bedruckbare, Seitenverhältnis gewahrt.
final class Sitzplanblatt: NSView {
    private let schriftstueck: CGPDFDocument
    private let seite: CGPDFPage

    init?(_ daten: Data, mass: CGSize) {
        guard let quelle = CGDataProvider(data: daten as CFData),
              let gelesen = CGPDFDocument(quelle), let erste = gelesen.page(at: 1) else { return nil }
        schriftstueck = gelesen
        seite = erste
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

    override func draw(_ ausschnitt: NSRect) {
        guard let zeichenfeld = NSGraphicsContext.current?.cgContext else { return }
        _ = schriftstueck
        let kasten = seite.getBoxRect(.mediaBox)
        let faktor = min(bounds.width / kasten.width, bounds.height / kasten.height)
        zeichenfeld.saveGState()
        zeichenfeld.translateBy(x: (bounds.width - kasten.width * faktor) / 2,
                                y: (bounds.height - kasten.height * faktor) / 2)
        zeichenfeld.scaleBy(x: faktor, y: faktor)
        zeichenfeld.drawPDFPage(seite)
        zeichenfeld.restoreGState()
    }
}
