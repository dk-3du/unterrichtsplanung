// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Unterrichtsplanung

/// Die Zelle der Hülle erfährt die Auswahl ihrer Zeile sofort (v96, BH5, E1183): AppKit hebt beim Drücken hervor,
/// `tableViewSelectionDidChange` käme erst beim Loslassen — das Zahnrad der gewählten Lerngruppe hängt an
/// `huellzeileGewaehlt`. Am Verhalten: eine echte Zeile, eine echte Zelle, eine Anzeige, die den Wert meldet.
@Suite("Hülle der Tabellen: Auswahl in der Zelle (E1183)", .serialized)
@MainActor
struct HuelltabelleAuswahlPruefungen {
    /// Was die Zelle zuletzt über `huellzeileGewaehlt` zeigte.
    final class Fuehler {
        var zuletzt: Bool?
    }

    struct Anzeige: View {
        @Environment(\.huellzeileGewaehlt) private var gewaehlt
        let fuehler: Fuehler

        var body: some View {
            Text(gewaehlt ? "gewählt" : "frei")
                .onChange(of: gewaehlt, initial: true) { _, neu in fuehler.zuletzt = neu }
        }
    }

    /// Anordnen und zeichnen lassen, ohne Uhr und ohne Ereignisschleife (E145): Die Hülle erneuert ihre Anzeige beim
    /// Anordnen.
    private func zeichnen(_ fenster: NSWindow) {
        for _ in 0..<3 {
            fenster.contentView?.layoutSubtreeIfNeeded()
            fenster.displayIfNeeded()
        }
    }

    @Test("E1183: Die Zelle erfährt die Auswahl ihrer Zeile sofort — auch in eine andere Zeile wiederverwendet")
    func zelleErfaehrtAuswahl() throws {
        let anwendung = NSApplication.shared
        if anwendung.activationPolicy() != .accessory { anwendung.setActivationPolicy(.accessory) }
        let fenster = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.borderless],
                               backing: .buffered, defer: false)
        let wurzel = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 120))
        fenster.contentView = wurzel
        fenster.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        fenster.orderFrontRegardless()
        defer {
            fenster.orderOut(nil)
            fenster.contentView = nil
        }
        let erste = Huellzeile(frame: CGRect(x: 0, y: 0, width: 300, height: 24))
        let zweite = Huellzeile(frame: CGRect(x: 0, y: 40, width: 300, height: 24))
        wurzel.addSubview(erste)
        wurzel.addSubview(zweite)
        let fuehler = Fuehler()
        let zelle = Huellzelle(kennung: NSUserInterfaceItemIdentifier("Probe"))
        zelle.meldetAuswahl = true
        zelle.frame = CGRect(x: 0, y: 0, width: 300, height: 24)
        zelle.setzen(AnyView(Anzeige(fuehler: fuehler)))
        erste.addSubview(zelle)
        zeichnen(fenster)
        #expect(fuehler.zuletzt == false, "vor der Wahl: \(String(describing: fuehler.zuletzt))")

        erste.isSelected = true
        zeichnen(fenster)
        #expect(fuehler.zuletzt == true, "die Zeile gewählt — die Zelle weiß es sofort")

        zelle.removeFromSuperview()
        zweite.addSubview(zelle)
        zeichnen(fenster)
        #expect(fuehler.zuletzt == false, "in eine nicht gewählte Zeile wiederverwendet — nicht mehr gewählt")

        zelle.removeFromSuperview()
        erste.addSubview(zelle)
        zeichnen(fenster)
        #expect(fuehler.zuletzt == true, "zurück in die gewählte Zeile — wieder gewählt")

        // Ohne den Schalter der Spalte erfährt die Zelle nichts — und wird beim Auswahlwechsel nicht neu gebaut (R-BH5-12).
        let fuehlerOhne = Fuehler()
        let ohne = Huellzelle(kennung: NSUserInterfaceItemIdentifier("Ohne"))
        ohne.frame = CGRect(x: 0, y: 0, width: 300, height: 24)
        ohne.setzen(AnyView(Anzeige(fuehler: fuehlerOhne)))
        erste.addSubview(ohne)
        zeichnen(fenster)
        #expect(fuehlerOhne.zuletzt == false, "ohne Schalter in der gewählten Zeile: nicht gewählt (R-BH5-12)")
    }
}
