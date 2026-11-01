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

    /// Die Grenzen des Kennwortschutzes im PDF-Format, wie Core Graphics sie
    /// setzt: nur ASCII, und von dem nur die ersten 32 Byte (B18, E45). Nichts
    /// wird still gekürzt oder umkodiert — was außerhalb liegt, wird benannt.
    static let kennwortHoechstens = 32

    /// `nil`, wenn das Kennwort so schützt, wie es eingegeben wurde; sonst der
    /// Einwand für den Dialog. Ein leeres Kennwort heißt kein Schutz — das
    /// fragen die Aufrufer vorher ab; hier bekäme es den Einwand der Länge.
    /// Eine Regel für Sitzplan und Rückmeldungsliste (E872 c): mindestens 12
    /// Zeichen und nicht nur Leerraum wie die Passphrase (E406); keine
    /// Steuerzeichen — Core Graphics kürzt an einer NUL, „abc⟨NUL⟩def“ ging mit
    /// „abc“ auf, „⟨NUL⟩abc“ ohne Kennwort (nachgestellt 27.10.2026, R86-03);
    /// dazu die Grenzen des PDF-Formats (E45): nur ASCII, höchstens 32 Zeichen.
    static func kennwortEinwand(_ kennwort: String) -> String? {
        guard Tresor.passphraseZulaessig(kennwort) else {
            return kennwort.count < Tresor.passphraseMindestlaenge
                ? "Das Kennwort braucht mindestens \(Tresor.passphraseMindestlaenge) Zeichen."
                : "Ein Kennwort nur aus Leerraum gilt nicht."
        }
        if kennwort.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return "Das Kennwort darf keine Steuerzeichen enthalten."
        }
        if !kennwort.utf8.allSatisfy({ $0 < 0x80 }) {
            return "Der Kennwortschutz des PDF-Formats nimmt nur ASCII-Zeichen — keine Umlaute, kein ß, "
                + "keine Zeichen außerhalb von ASCII."
        }
        if kennwort.utf8.count > kennwortHoechstens {
            return "Der Kennwortschutz des PDF-Formats nimmt höchstens \(kennwortHoechstens) Zeichen — "
                + "dieses hat \(kennwort.utf8.count)."
        }
        return nil
    }

    /// Die Seite als PDF ohne Kennwort — für den Druck, das Sichern ohne Schutz und die Probe. Mit Kennwort entsteht
    /// ein Sitzplan-PDF nur über `geschuetztesPDF`, also nachgeprüft (Z-AY3-03).
    static func pdf(_ plan: Sitzplan, klasse: Klasse) -> Data? { zeichnen(plan, klasse: klasse, kennwort: nil) }

    /// Die Seite als vektorielles PDF — eine Seite in Blattgröße. Mit
    /// `kennwort` trägt sie den Kennwortschutz des PDF-Formats (E40):
    /// Nutzer- und Eigentümerkennwort, 128 Bit — Vorschau und andere Leser
    /// fragen danach. `nil`, wenn das Kennwort außerhalb der Grenzen liegt —
    /// das PDF entsteht dann gar nicht, statt anders geschützt als gedacht.
    private static func zeichnen(_ plan: Sitzplan, klasse: Klasse, kennwort: String?) -> Data? {
        if let kennwort, !kennwort.isEmpty, kennwortEinwand(kennwort) != nil { return nil }
        return Drucken.imHellen {
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

    /// Das Sitzplan-PDF mit Kennwortschutz — nachgeprüft wie die Rückmeldungsliste (E872 c, `Listensatz.verschluesselungBelegt`):
    /// verschlüsselt, AES, zu ohne Kennwort, offen mit genau diesem. Sonst kein PDF, sondern der Grund (E886). `nil`, wenn
    /// sich der Plan gar nicht zeichnen ließ — dafür gilt die Meldung wie bisher. `belegt` setzen nur die Prüfungen.
    static func geschuetztesPDF(_ plan: Sitzplan, klasse: Klasse, kennwort: String,
                                belegt: (Data, String) -> Bool = { Listensatz.verschluesselungBelegt($0, kennwort: $1) })
        -> Listensatz.Ausgabe? {
        if let einwand = kennwortEinwand(kennwort) { return .abgewiesen(einwand) }
        guard let daten = zeichnen(plan, klasse: klasse, kennwort: kennwort) else { return nil }
        guard belegt(daten, kennwort) else { return .abgewiesen(nichtVerschluesselt) }
        return .verschluesselt(daten)
    }

    /// Der Grund, wenn die Nachprüfung das PDF nicht trägt — nur hinter „Das PDF wurde nicht geschrieben: “ (E886, E897).
    static let nichtVerschluesselt = "Es ließ sich nicht wie verlangt verschlüsseln."

    /// Die Meldung, wenn mit Kennwort kein PDF entsteht: der Grund aus der Regel oder der Nachprüfung (E886, Z-AY3N-03;
    /// „das PDF“ nach E897).
    static func nichtGeschrieben(_ grund: String) -> String { "Das PDF wurde nicht geschrieben: " + grund }

    private static func dateiname(_ klasse: Klasse) -> String {
        Planungsdatei.exportName(titel: "Sitzplan " + klasse.name + (klasse.fach.isEmpty ? "" : " " + klasse.fach),
                                 endung: "pdf")
    }

    /// Als PDF sichern — ohne Rückfrage, auch bei eingeschalteter Verschlüsselung
    /// (E449): Der Sichern-Dialog wählt dann den Kennwortschutz vor (E40). Die
    /// Datei liegt, wo der Nutzer sie hinlegt, und trägt die Namen der Klasse;
    /// der Pfad wird nicht gemerkt. `sichern` setzen nur die Prüfungen — im
    /// Prüfziel geht kein Dialog auf.
    static func alsPDFSichern(_ plan: Sitzplan, klasse: Klasse, speicher: Planungsspeicher,
                              sichern: (@MainActor (Sitzplan, Klasse, Planungsspeicher) -> Void)? = nil) {
        // Bei sichtbarer Rückfrage oder schon hängendem Bogen nichts — auch von Knöpfen außerhalb des Menüs
        // (E318, Z14c4-04, E459).
        guard !gesperrt(speicher) else { return }
        (sichern ?? pdfSchreiben)(plan, klasse, speicher)
    }

    /// Ein Befehl des Sitzplans (PDF, Druck) prallt ab, solange eine Rückfrage steht (E318) oder am Blatt
    /// schon ein Bogen hängt — ein zweiter Sichern-Dialog verhallte und ließe sein Zusatzfenster verwaist
    /// stehen, ein zweiter Druckbogen hinge sich erst nach dem ersten an (B107, E459): der Systemton,
    /// sonst nichts.
    static func gesperrt(_ speicher: Planungsspeicher) -> Bool {
        if speicher.frageSperrtBefehl() { return true }
        guard speicher.bogenSichtbar() else { return false }
        speicher.systemton()
        return true
    }

    /// Der Zusatz im Sichern-Dialog — der Kennwortschutz vorgewählt, wenn die
    /// Planung verschlüsselt ist (E40).
    static func kennwortzusatz(fuer speicher: Planungsspeicher) -> Kennwortzusatz {
        Kennwortzusatz(vorgewaehlt: speicher.verschluesselt)
    }

    private static func pdfSchreiben(_ plan: Sitzplan, klasse: Klasse, speicher: Planungsspeicher) {
        let dialog = NSSavePanel()
        dialog.message = "Sitzplan als PDF sichern"
        dialog.nameFieldStringValue = dateiname(klasse)
        dialog.allowedContentTypes = [.pdf]
        dialog.canCreateDirectories = true
        dialog.isExtensionHidden = false
        let zusatz = kennwortzusatz(fuer: speicher)
        dialog.accessoryView = zusatz
        dialog.delegate = zusatz
        // Aus dem Sitzplan-Editor ein Bogen am Blatt, sonst frei (E114/E115).
        Dialogort.zeigen(dialog) { antwort in
            guard antwort == .OK, let ziel = dialog.url else { return }
            let kennwort = zusatz.gewaehltesKennwort
            var erfolg = false
            if let kennwort, !kennwort.isEmpty {
                // Mit Kennwort nur, was die Nachprüfung trägt (E872 c, E886).
                switch geschuetztesPDF(plan, klasse: klasse, kennwort: kennwort) {
                case .abgewiesen(let grund)?:
                    speicher.melden(nichtGeschrieben(grund), .warnung)
                    return
                case .verschluesselt(let daten)?:
                    erfolg = (try? daten.write(to: ziel, options: .atomic)) != nil
                case nil:
                    break
                }
            } else if let daten = pdf(plan, klasse: klasse) {
                erfolg = (try? daten.write(to: ziel, options: .atomic)) != nil
            }
            // Geschützt heißt: ein Kennwort, nicht nur der Schalter (Z-AY3-04) — wie der Zweig oben.
            let geschuetzt = kennwort?.isEmpty == false
            speicher.melden(erfolg ? (geschuetzt ? "Sitzplan als PDF gesichert — mit Kennwort geschützt."
                                                 : "Sitzplan als PDF gesichert.")
                                   : "Die PDF-Datei konnte nicht geschrieben werden.",
                            erfolg ? .hinweis : .warnung)
        }
    }

    /// Der Hinweis unter den Feldern des Zusatzes (E886) — Satz eins und drei des Hinweises der Rückmeldungsliste.
    static let kennwortHinweis = "Mindestens 12, höchstens 32 Zeichen, nur ASCII — keine Umlaute, kein ß. "
        + "Die App merkt sich das Kennwort nicht; getrennt vom PDF weitergeben."

    /// Der Zusatz im Sichern-Dialog (E40): „Mit Kennwort schützen“, Kennwort
    /// und Wiederholung, darunter die Regel (E886). Geprüft, bevor der Dialog
    /// schließt — leer, ungleich oder außerhalb der Regel (E872 c) hält ihn offen.
    @MainActor
    final class Kennwortzusatz: NSView, NSOpenSavePanelDelegate {
        private let schalter = NSButton(checkboxWithTitle: "Mit Kennwort schützen", target: nil, action: nil)
        private let kennwort = NSSecureTextField(frame: NSRect(x: 108, y: 84, width: 240, height: 24))
        private let wiederholung = NSSecureTextField(frame: NSRect(x: 108, y: 54, width: 240, height: 24))
        private let hinweis = NSTextField(wrappingLabelWithString: Sitzplandruck.kennwortHinweis)

        init(vorgewaehlt: Bool) {
            super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 146))
            schalter.frame = NSRect(x: 0, y: 116, width: 360, height: 20)
            schalter.state = vorgewaehlt ? .on : .off
            schalter.target = self
            schalter.action = #selector(umgeschaltet)
            addSubview(schalter)
            for (beschriftung, feld, y) in [("Kennwort:", kennwort, 86), ("Wiederholung:", wiederholung, 56)] {
                let etikett = NSTextField(labelWithString: beschriftung)
                etikett.frame = NSRect(x: 0, y: CGFloat(y), width: 100, height: 20)
                etikett.alignment = .right
                addSubview(etikett)
                feld.placeholderString = beschriftung == "Kennwort:" ? "für das PDF" : "noch einmal"
                feld.setAccessibilityLabel(beschriftung == "Kennwort:" ? "Kennwort für das PDF" : "Kennwort wiederholen")
                addSubview(feld)
            }
            hinweis.frame = NSRect(x: 0, y: 0, width: 360, height: 46)
            hinweis.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            hinweis.textColor = .secondaryLabelColor
            // Nur Text, kein Halt für Tab; VoiceOver liest ihn an den Feldern (Z-AY3-06).
            hinweis.isSelectable = false
            kennwort.setAccessibilityHelp(Sitzplandruck.kennwortHinweis)
            wiederholung.setAccessibilityHelp(Sitzplandruck.kennwortHinweis)
            addSubview(hinweis)
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
            if let einwand = Sitzplandruck.kennwortEinwand(gewaehlt) {
                throw NSError(domain: "Sitzplandruck", code: 3, userInfo: [NSLocalizedDescriptionKey: einwand])
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
        guard !gesperrt(speicher) else { return }
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
        // Aus dem Sitzplan-Editor ein dokumentmodaler Bogen am Blatt — der
        // Befund des Nutzers: Als freies Fenster über dem Blatt flackerte der
        // Druckdialog (E114/E115).
        Dialogort.drucken(vorgang)
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
