// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

// ── Das Angebot ───────────────────────────────────────────────────────────

/// Nach der ersten Planung, einmal: Soll die App ihre Oberfläche zeigen?
/// „Überspringen“ zählt als Antwort; die Tour bleibt unter „Hilfe“ erreichbar.
struct TourDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        Dialograhmen(titel: "Kurze Tour durch die Oberfläche",
                     unterzeile: "\(speicher.tourSchritte.count) Schritte, jederzeit abzubrechen",
                     breite: 560, hoehe: 420) {
            Section {
                Text("Die Tour zeigt die Werkzeugleiste am oberen Fensterrand und an einer "
                     + "Zelle des Rasters, wie ein Vorhaben entsteht und wie eine Zelle "
                     + "unterrichtsfrei wird.")
                Text("Jeder Schritt ist eine kleine Karte mit „Weiter“ und „Zurück“; "
                     + "„Tour beenden“ oder ⎋ bricht ab. Später lässt sich die Tour jederzeit "
                     + "über „Hilfe → Tour durch die Oberfläche“ starten.")
            } header: {
                Text("Was die Tour zeigt")
            }
        } fuss: {
            Button("Überspringen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button("Tour starten") {
                schliessen()
                speicher.tourStarten()
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// ── Die Karte ─────────────────────────────────────────────────────────────

/// Die Karte eines Schritts — dieselbe an der Werkzeugleiste wie an der Zelle.
struct Tourkarte: View {
    @Environment(Planungsspeicher.self) private var speicher
    /// Der zuletzt gezeigte Schritt bleibt stehen, bis das Popover zu ist:
    /// Ein leerer Inhalt ließ die Glasfläche des Popovers in eine endlose
    /// Materialauflösung laufen.
    @State private var zuletzt: Planungsspeicher.Tourschritt?

    var body: some View {
        if let schritt = speicher.tourSchritt ?? zuletzt {
            let stelle = speicher.tourStelle
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(schritt.titel).font(.headline)
                    Spacer(minLength: 12)
                    Text("Schritt \(stelle.stelle) von \(stelle.zahl)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(schritt.text(zelle: speicher.tourZelle))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    // ⎋ wie in den Dialogen als Kürzel: `onExitCommand` fand im
                    // Popover keinen Antwortenden.
                    Button("Tour beenden") { speicher.tourBeenden() }
                        .keyboardShortcut(.cancelAction)
                    Spacer(minLength: 0)
                    if !speicher.tourAmAnfang {
                        Button("Zurück") { speicher.tourZurueck() }
                    }
                    // Kein Glas in der Karte: Das Popover ist selbst eine Glasfläche,
                    // und die Materialauflösung lief sich beim sechsten Öffnen in
                    // eine endlose Rekursion.
                    Button(speicher.tourAmEnde ? "Fertig" : "Weiter") { speicher.tourWeiter() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(width: 380)
            .onAppear { zuletzt = schritt }
            .onChange(of: speicher.tourSchritt) { _, neu in if let neu { zuletzt = neu } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tour, Schritt \(stelle.stelle) von \(stelle.zahl): \(schritt.titel)")
        }
    }
}

// ── Der Führer ────────────────────────────────────────────────────────────

/// Hängt die Karte als `NSPopover` an ihr Ziel: einen Eintrag der
/// Werkzeugleiste oder die Beispielzelle im Raster. `.applicationDefined` —
/// ein Klick daneben beendet die Tour nicht still; das tun nur „Tour
/// beenden“, ⎋ und ein Blatt, das sich öffnet. Geht das Popover von sich aus
/// zu (die Zelle wurde beim Neuaufbau des Rasters ersetzt, das Fenster ist
/// weg), hängt der Führer die Karte neu an, statt die Tour ohne Karte
/// stehenzulassen.
@MainActor
final class Tourfuehrer: NSObject, NSPopoverDelegate {
    static let shared = Tourfuehrer()

    struct Anker {
        let ansicht: NSView
        let rahmen: NSRect
        let kante: NSRectEdge
    }

    /// Vom Rasterkoordinator gesetzt, solange das Raster steht: rollt zur
    /// Beispielzelle, hält ihre Knöpfe sichtbar und nennt die Stelle der Karte.
    var zellenanker: (@MainActor (Planungsspeicher.Tourschritt) -> Anker?)?
    /// Nimmt die Hervorhebung der Zelle zurück, sobald die Tour sie verlässt.
    var zelleFreigeben: (@MainActor () -> Void)?

    /// Für den Prüfstand: Schritt und Lage des letzten Ankers auf dem Bildschirm.
    private(set) var letzteLage: (schritt: Planungsspeicher.Tourschritt, anker: NSRect)?
    /// Für den Prüfstand: das Fenster der Karte.
    var kartenfenster: NSWindow? { popover?.contentViewController?.view.window }

    private var popover: NSPopover?
    private weak var speicher: Planungsspeicher?
    /// Wir schließen selbst — der Delegat soll das nicht als Verlust deuten.
    private var schliesstSelbst = false
    private var versuche = 0
    private var versuchterSchritt: Planungsspeicher.Tourschritt?

    private override init() {}

    /// Nach jedem Schrittwechsel: Karte zeigen, versetzen oder schließen.
    func nachfuehren(_ speicher: Planungsspeicher) {
        self.speicher = speicher
        guard let schritt = speicher.tourSchritt else {
            schliessen()
            return
        }
        if schritt.anker != .zelle { zelleFreigeben?() }
        if versuchterSchritt != schritt {
            versuchterSchritt = schritt
            versuche = 0
        }
        guard let anker = anker(fuer: schritt) else {
            // Das Raster hat die Zelle vielleicht noch nicht angelegt; ein Eintrag
            // der Werkzeugleiste kann im Überlaufmenü stehen. Kurz warten, dann
            // den Schritt auslassen statt die Tour hängen zu lassen.
            versuche += 1
            if versuche <= 8 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(80))
                    guard speicher.tourSchritt == schritt else { return }
                    self?.nachfuehren(speicher)
                }
            } else {
                versuche = 0
                speicher.tourWeiter()
            }
            return
        }
        versuche = 0
        zeigen(speicher, an: anker)
        let imFenster = anker.ansicht.convert(anker.rahmen, to: nil)
        letzteLage = (schritt, anker.ansicht.window?.convertToScreen(imFenster) ?? .zero)
    }

    func schliessen() {
        zelleFreigeben?()
        popover?.animates = false
        schliesstSelbst = true
        popover?.close()
        schliesstSelbst = false
        popover = nil
        letzteLage = nil
        versuche = 0
        versuchterSchritt = nil
    }

    /// Nicht von uns geschlossen: neu anhängen, solange die Tour läuft.
    func popoverDidClose(_ nachricht: Notification) {
        guard !schliesstSelbst, let speicher, speicher.tourLaeuft,
              (nachricht.object as? NSPopover) === popover else { return }
        popover = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            self?.nachfuehren(speicher)
        }
    }

    private func anker(fuer schritt: Planungsspeicher.Tourschritt) -> Anker? {
        switch schritt.anker {
        case .werkzeug(let namen): werkzeuganker(namen)
        case .zelle: zellenanker?(schritt)
        }
    }

    /// Die Einträge der Werkzeugleiste kommen von SwiftUI; ihre `NSToolbarItem`s
    /// tragen die Beschriftung des `Label` und den Hilfetext. Die Kante hängt
    /// an der Ausrichtung der Ansicht: Für eine gekippte ist `maxY` unten.
    private func werkzeuganker(_ namen: [String]) -> Anker? {
        guard let fenster = hauptfenster(), let leiste = fenster.toolbar else { return nil }
        for name in namen {
            let eintrag = leiste.items.first {
                $0.label == name || ($0.toolTip?.hasPrefix(name) ?? false)
            }
            if let ansicht = eintrag?.view, ansicht.window === fenster {
                return Anker(ansicht: ansicht, rahmen: ansicht.bounds,
                             kante: ansicht.isFlipped ? .maxY : .minY)
            }
        }
        return nil
    }

    private func hauptfenster() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.toolbar != nil && !($0 is NSPanel) }
    }

    /// Versetzen kennt `NSPopover` nicht — und ein wiederverwendetes stürzte
    /// beim sechsten Öffnen in der Materialauflösung ab. Also je
    /// Schritt ein frisches; das alte geht ohne Ausblendung zu.
    private func zeigen(_ speicher: Planungsspeicher, an anker: Anker) {
        if let altes = popover {
            altes.animates = false
            schliesstSelbst = true
            altes.close()
            schliesstSelbst = false
        }
        let neu = NSPopover()
        neu.behavior = .applicationDefined
        neu.animates = popover == nil
        neu.delegate = self
        let inhalt = NSHostingController(rootView: Tourkarte().environment(speicher))
        inhalt.sizingOptions = [.preferredContentSize]
        neu.contentViewController = inhalt
        popover = neu
        neu.show(relativeTo: anker.rahmen, of: anker.ansicht, preferredEdge: anker.kante)
        // Schlüsselfenster mit der Karte als erstem Antwortenden: sonst ginge
        // ⏎ ans Hauptfenster, und ⎋ fände `onExitCommand` nicht.
        if let fenster = inhalt.view.window {
            fenster.makeKey()
            fenster.makeFirstResponder(inhalt.view)
        }
    }
}
