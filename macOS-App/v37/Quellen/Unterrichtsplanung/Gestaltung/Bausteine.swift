// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

enum Zeichen {
    static let raster = "square.grid.3x2"
    static let plus = "plus"
    static let export = "square.and.arrow.up"
    static let einfuhr = "square.and.arrow.down"
    static let ordner = "folder"
    static let kursdatei = "tablecells.badge.ellipsis"
    static let kursdateiGesetzt = "tablecells"
    static let curriculum = "book"
    static let curriculumGesetzt = "book.closed.fill"
    static let datei = "doc"
    static let klassen = "person.2"
    static let darstellung = "circle.lefthalf.filled"
    static let neuePlanung = "square.and.pencil"
    static let einstellungen = "gearshape"
    static let stift = "pencil"
    static let muell = "trash"
    static let haken = "checkmark"
    static let hoch = "arrow.up"
    static let runter = "arrow.down"
    static let ferien = "beach.umbrella"
    static let kalender = "calendar"
    static let kopie = "doc.on.doc"
    static let neu = "arrow.clockwise"
    static let tastatur = "keyboard"
    static let verweis = "link"
    static let auswaerts = "arrow.up.forward"
    static let warnung = "exclamationmark.triangle"
    static let hinweis = "info.circle"
    static let pruefung = "pencil.and.list.clipboard"
    static let tagesliste = "checklist"
    static let schloss = "lock"
    static let schlossOffen = "lock.open"
    static let schluessel = "key"
    static let drucker = "printer"
    static let touchID = "touchid"
}

/// Ein mehrzeiliges Textfeld in der Form, die alle Dialoge nutzen.
///
/// **Warum nicht `TextEditor`:** Der beschneidet in der ersten Zeile alles über
/// der Versalhöhe („UBUNG Ol Ahnlich“). Aus SwiftUI heraus nicht zu beheben —
/// es geht nur über `textContainerInset` der `NSTextView` darunter.
struct Textfeld: View {
    @Binding var text: String
    var mindesthoehe: CGFloat = 90
    /// Für die Sprachausgabe.
    var beschriftung: String?

    var body: some View {
        Textansicht(text: $text, beschriftung: beschriftung)
            .frame(minHeight: mindesthoehe)
            .padding(6)
            .background(.quinary, in: .rect(cornerRadius: 8))
    }
}

/// Die eingebettete `NSTextView` hinter `Textfeld`.
private struct Textansicht: NSViewRepresentable {
    @Binding var text: String
    var beschriftung: String?

    func makeNSView(context: Context) -> NSScrollView {
        let rollbereich = NSTextView.scrollableTextView()
        rollbereich.drawsBackground = false
        rollbereich.hasVerticalScroller = true
        rollbereich.autohidesScrollers = true

        guard let feld = rollbereich.documentView as? NSTextView else { return rollbereich }
        feld.delegate = context.coordinator
        feld.string = text
        feld.font = .preferredFont(forTextStyle: .body)
        feld.textColor = .labelColor
        feld.drawsBackground = false
        feld.allowsUndo = true
        feld.isRichText = false
        feld.usesFontPanel = false
        // Keine Ersetzungen — die Texte wandern in JSON und auf andere Geräte.
        feld.isAutomaticQuoteSubstitutionEnabled = false
        feld.isAutomaticDashSubstitutionEnabled = false
        feld.isAutomaticTextReplacementEnabled = false
        feld.isContinuousSpellCheckingEnabled = true
        feld.textContainerInset = NSSize(width: 0, height: 3)
        if let beschriftung { feld.setAccessibilityLabel(beschriftung) }
        return rollbereich
    }

    func updateNSView(_ rollbereich: NSScrollView, context: Context) {
        guard let feld = rollbereich.documentView as? NSTextView else { return }
        // Jede Zuweisung setzt die Schreibmarke ans Ende.
        if feld.string != text { feld.string = text }
        if let beschriftung { feld.setAccessibilityLabel(beschriftung) }
    }

    func makeCoordinator() -> Koordinator { Koordinator(text: $text) }

    @MainActor
    final class Koordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ nachricht: Notification) {
            guard let feld = nachricht.object as? NSTextView else { return }
            text.wrappedValue = feld.string
        }
    }
}

/// Ein Knopf, der erst beim Überfahren erscheint — beim Tabben aber ebenso.
/// Ihn nur beim Überfahren zu bauen nähme ihn aus der Tabulatorreihenfolge.
struct Einblendknopf<Inhalt: View>: View {
    let sichtbar: Bool
    let handlung: () -> Void
    @ViewBuilder let inhalt: Inhalt

    @FocusState private var fokussiert: Bool

    var body: some View {
        Button(action: handlung) { inhalt }
            .buttonStyle(.plain)
            .focused($fokussiert)
            .opacity(sichtbar || fokussiert ? 1 : 0)
    }
}

/// Ein Eingabefeld in einer Tabellenzeile: eigene Fläche je Feld, Beschriftung
/// einmal als `Spaltenkopf` — im gruppierten `Form` stoßen sonst Wert und
/// nächste Beschriftung aneinander.
struct Tabellenfeld: View {
    let hinweis: String
    @Binding var text: String
    /// Von außen nicht zu beobachten: `.focused(…)` auf diese Ansicht erreicht
    /// das `TextField` darin nicht mehr.
    var beimVerlassen: (() -> Void)?

    @State private var ueberfahren = false
    @FocusState private var fokussiert: Bool

    var body: some View {
        TextField(text: $text, prompt: Text(hinweis)) { Text(hinweis) }
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($fokussiert)
            .onChange(of: fokussiert) { _, hat in if !hat { beimVerlassen?() } }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(Systemfarben.feldflaeche, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(fokussiert ? Color.accentColor
                                             : Systemfarben.feldkante.opacity(ueberfahren ? 1 : 0.55),
                                  lineWidth: fokussiert ? 2 : 1)
            }
            .onHover { ueberfahren = $0 }
            .animation(.easeOut(duration: 0.12), value: ueberfahren)
    }
}

struct Spaltenkopf: View {
    let titel: String

    var body: some View {
        Text(titel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }
}

struct Farbpunkt: View {
    let ton: Farbton
    var groesse: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Kursfarben.farbe(ton))
            .frame(width: groesse, height: groesse)
    }
}

/// Der Durchgeführt-Haken als Knopf — **ein** Stand, **ein** Bild: gefüllter
/// grüner Kreis mit Häkchen bzw. leerer Kreis. Gemeinsam für die Tagesliste
/// und die Übernahme-Matrix; die AppKit-Fassung an der Kachel bleibt aus
/// Notwendigkeit eigenständig (`Kachelansicht`).
struct Hakenknopf: View {
    var aktiv: Bool
    var breite: CGFloat = 22
    var hilfe: String
    var kennzeichnung: String
    var wirken: () -> Void

    var body: some View {
        Button(action: wirken) {
            Image(systemName: aktiv ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(aktiv ? Color.green : Color.secondary)
                .frame(width: breite)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(hilfe)
        .accessibilityLabel(kennzeichnung)
        .accessibilityValue(aktiv ? "ja" : "nein")
        .accessibilityAddTraits(aktiv ? [.isSelected] : [])
    }
}

/// „dringlich“ in der Farbe des Kachelrahmens — als `Text`, damit es sich per
/// Interpolation einsetzen lässt. Gemeinsam für Tagesliste und Ausdruck.
enum Dringlichkeitsmarke {
    static var text: Text { Text("dringlich").foregroundStyle(Systemfarben.dringend) }
}

/// Eine Trennlinie an genau einer Kante. `Divider()` hilft in einer Überlagerung
/// nicht: Ohne Stapel-Zusammenhang zeichnet es waagerecht und mittig.
extension View {
    func trennlinie(_ kante: Edge) -> some View {
        overlay(alignment: kante == .top ? .top
                         : kante == .bottom ? .bottom
                         : kante == .leading ? .leading : .trailing) {
            if kante == .top || kante == .bottom {
                Systemfarben.trennlinie.frame(height: 1)
            } else {
                Systemfarben.trennlinie.frame(width: 1)
            }
        }
    }
}

// ── Sichere Bindung an ein Listenelement ──────────────────────────────────

extension Binding {
    /// Zugriff über die Kennung statt über die Stelle.
    ///
    /// `ForEach($liste)` reicht Bindungen durch, die über den Index greifen —
    /// nach dem Löschen einer Zeile greift ein nachmeldendes Textfeld hinter
    /// das Ende des Feldes und stürzt ab. Hier verfällt der Schreibversuch.
    subscript<Element: Identifiable & Sendable>(kennung id: Element.ID,
                                                letzterStand letzter: Element)
        -> Binding<Element> where Value == [Element], Element.ID: Sendable {
        Binding<Element>(
            get: { self.wrappedValue.first { $0.id == id } ?? letzter },
            set: { neu in
                guard let stelle = self.wrappedValue.firstIndex(where: { $0.id == id })
                else { return }
                self.wrappedValue[stelle] = neu
            })
    }
}

/// Beendet das Schreiben, sobald neben das Feld geklickt wird — in einem
/// `Form` gibt ein Textfeld die Schreibmarke von sich aus nicht her.
@MainActor
enum Schreibende {
    private static var beobachter: Any?

    static func beobachten() {
        guard beobachter == nil else { return }
        beobachter = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { ereignis in
            MainActor.assumeIsolated { pruefen(ereignis) }
            return ereignis
        }
    }

    private static func pruefen(_ ereignis: NSEvent) {
        guard let fenster = ereignis.window,
              let editor = fenster.firstResponder as? NSTextView,
              let inhalt = fenster.contentView else { return }
        // Der Feldeditor gehört dem Feld, das ihn gerade ausleiht.
        let feld = (editor.delegate as? NSView) ?? editor
        let rahmen = feld.convert(feld.bounds, to: inhalt).insetBy(dx: -3, dy: -3)
        guard !rahmen.contains(inhalt.convert(ereignis.locationInWindow, from: nil)) else { return }
        fenster.makeFirstResponder(nil)
    }
}
