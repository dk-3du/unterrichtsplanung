// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Wo ein Dialog aufgeht (E114–E116, v61).
///
/// Der Befund des Nutzers: Der Druckdialog stand als freies Fenster über dem
/// Sitzplan-Blatt und flackerte. Die Regel dagegen ist eine, nicht eine Liste
/// von Aufrufstellen: Ist das Schlüsselfenster ein Blatt, wird der Dialog ein
/// Bogen an diesem Blatt; ist es das Hauptfenster, bleibt der Dialog ein
/// freies Fenster wie bisher. Die Kette (Hauptfenster → Blatt → Rückfrage)
/// wird hier mit gestellten Elternteilen geprüft — `sheetParent` setzt allein
/// AppKit, und ein Prüfziel ohne sichtbare Fenster hängt keine Bögen an.
@Suite("Dialogort")
@MainActor
struct DialogortPruefungen {

    private func fenster(_ titel: String) -> NSWindow {
        let f = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                         styleMask: [.titled], backing: .buffered, defer: true)
        f.title = titel
        return f
    }

    @Test("Ist das Hauptfenster vorn, bleibt der Dialog frei")
    func hauptfensterFrei() {
        let haupt = fenster("Haupt")
        #expect(Dialogort.weg(fuer: haupt, elternVon: { _ in nil }) == .frei)
    }

    @Test("Ohne Schlüsselfenster bleibt der Dialog frei")
    func ohneSchluesselFrei() {
        #expect(Dialogort.weg(fuer: nil, elternVon: { _ in nil }) == .frei)
    }

    @Test("Ein Blatt am Hauptfenster bekommt den Dialog als Bogen")
    func blattBogen() {
        let haupt = fenster("Haupt")
        let blatt = fenster("Sitzplan")
        let eltern: [ObjectIdentifier: NSWindow] = [ObjectIdentifier(blatt): haupt]
        #expect(Dialogort.weg(fuer: blatt, elternVon: { eltern[ObjectIdentifier($0)] }) == .bogen(blatt))
    }

    @Test("Liegt eine Rückfrage auf dem Blatt, ist das Blatt das Ziel — nicht die Rückfrage (E116)")
    func rueckfrageObenaufTrifftDasBlatt() {
        let haupt = fenster("Haupt")
        let blatt = fenster("Sitzplan")
        let frage = fenster("Rückfrage")
        let eltern: [ObjectIdentifier: NSWindow] = [ObjectIdentifier(blatt): haupt,
                                                    ObjectIdentifier(frage): blatt]
        #expect(Dialogort.weg(fuer: frage, elternVon: { eltern[ObjectIdentifier($0)] }) == .bogen(blatt))
        // Und ein Blatt auf dem Blatt (Farbwahl über dem Klassen-Blatt) ebenso:
        // das oberste Blatt unter dem Hauptfenster ist immer das Ziel.
        let noch = fenster("noch eins")
        var tiefer = eltern; tiefer[ObjectIdentifier(noch)] = frage
        #expect(Dialogort.weg(fuer: noch, elternVon: { tiefer[ObjectIdentifier($0)] }) == .bogen(blatt))
    }

    @Test("Ein freies Fenster ohne Elternteil ist kein Blatt — auch wenn es vorn ist")
    func freiesFensterFrei() {
        let frei = fenster("frei")
        let haupt = fenster("Haupt")
        let eltern: [ObjectIdentifier: NSWindow] = [ObjectIdentifier(haupt): frei]
        // Das Hauptfenster hätte hier einen „Elternteil“ — gefragt wird aber nach `frei`.
        #expect(Dialogort.weg(fuer: frei, elternVon: { eltern[ObjectIdentifier($0)] }) == .frei)
    }

    @Test("Im Prüfziel ohne Fenster meldet der wirkliche Weg „frei“")
    func wirklicherWegOhneFenster() {
        // Kein Schlüsselfenster im Prüfziel: der Weg, den `zeigen` nähme, ist frei —
        // genau der Weg, den die App bis v60 immer nahm.
        #expect(Dialogort.aktuell == .frei)
    }
}
