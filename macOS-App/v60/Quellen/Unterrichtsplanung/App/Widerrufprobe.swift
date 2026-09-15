// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Widerrufen und Wiederholen am echten Fenster (S7).
///
/// Warum am gebauten Paket und nicht nur im Prüfziel: Das Menü kommt von
/// SwiftUI, die Freigabe eines Eintrags von AppKits Prüfung der Verantwortungs-
/// kette, und wem ⌘Z gehört, entscheidet der Ersthelfer der Tastatur (E87).
/// Keines davon gibt es im Prüflauf ohne Fenster — dieses Projekt hat mit genau
/// solchen Unterschieden Geschichte.
@MainActor
enum Widerrufprobe {

    /// `--widerruftest`: Menütitel und Freigabe, ⌘Z über das Menü, der Vorrang
    /// des Feldeditors, die Kappung und das Leeren beim Wechsel des
    /// Schauplatzes — und das Sitzplanblatt mit seinem eigenen Verlauf.
    /// Braucht eine gesäte `planung.json` mit mindestens einer Zeile.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            var zeilen = ["WIDERRUFTEST"]
            var bestanden = true
            func pruefen(_ gilt: Bool, _ text: String) {
                zeilen.append("  \(gilt ? "✓" : "✗") \(text)")
                if !gilt { bestanden = false }
            }
            // Die örtlichen Griffe tragen ihr `@MainActor` selbst: Swift 6.4
            // spricht es ihnen aus dem umgebenden `Task { @MainActor in }` nicht
            // mehr zu (zehn Warnungen in v58 unter Xcode 27).
            func ende() async {
                zeilen.append(bestanden ? "WIDERRUFTEST bestanden" : "WIDERRUFTEST mit Befund")
                print(zeilen.joined(separator: "\n"))
                fflush(stdout)
                await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
            }
            @MainActor func fenster() -> NSWindow? { NSApp.windows.first { $0.isVisible } }
            /// Die App nach vorn — und ihr Zeit lassen.
            ///
            /// Gemessen wird eine App, die vorn steht: Im Hintergrund hält
            /// SwiftUI seine Auffrischung an (der Menütitel bliebe stehen), und
            /// `NSApp.keyWindow` ist dann nichts. Beides hat diesen Lauf schon
            /// zweimal wackeln lassen.
            @MainActor func vorndran(_ millisekunden: Int = 400) async {
                NSApp.activate(ignoringOtherApps: true)
                fenster()?.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(millisekunden))
            }
            @MainActor func suchen<T: NSView>(_ ansicht: NSView?, _ art: T.Type) -> T? {
                guard let ansicht else { return nil }
                if let treffer = ansicht as? T { return treffer }
                for kind in ansicht.subviews {
                    if let treffer = suchen(kind, art) { return treffer }
                }
                return nil
            }

            // ── Das Menü, wie AppKit es führt ─────────────────────────────
            /// Der Eintrag aus dem Menü „Bearbeiten“ — gesucht am Kürzel, nicht
            /// am Titel: Der Titel ist ja gerade das, was geprüft wird.
            @MainActor func eintrag(umschalt: Bool) -> NSMenuItem? {
                Menuetitel.eintrag(umschalt: umschalt)
            }
            /// AppKit fragt beim Öffnen des Menüs, ob ein Eintrag gilt.
            @MainActor func freigegeben(_ eintrag: NSMenuItem?) -> Bool {
                guard let eintrag, let menue = eintrag.menu else { return false }
                menue.update()
                return eintrag.isEnabled
            }
            /// ⌘Z als Tastendruck durch die Menüleiste — der Weg, den auch
            /// eine Hand nimmt.
            @discardableResult
            @MainActor func kuerzel() -> Bool {
                guard let ereignis = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.command],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: fenster()?.windowNumber ?? 0, context: nil,
                    characters: "z", charactersIgnoringModifiers: "z",
                    isARepeat: false, keyCode: 6) else { return false }
                return NSApp.mainMenu?.performKeyEquivalent(with: ereignis) == true
            }

            /// ⇧⌘Z über den Eintrag selbst.
            ///
            /// Nicht als synthetischer Tastendruck: AppKit vergleicht bei
            /// Buchstaben das Zeichen mit der Umschalttaste zusammen, und ein
            /// gebautes Ereignis traf hier entweder den Eintrag mit ⌘Z (mit
            /// kleinem z) oder gar nichts (mit großem Z) — am Lauf gemessen.
            /// Was diese Probe prüfen soll, ist der Griff hinter dem Eintrag;
            /// dass die Menüleiste Kürzel zustellt, zeigt der Weg darüber.
            @MainActor @discardableResult
            func ueberDenEintrag(_ eintrag: NSMenuItem?) -> Bool {
                guard let eintrag, let griff = eintrag.action else { return false }
                return NSApp.sendAction(griff, to: eintrag.target, from: eintrag)
            }

            try? await Task.sleep(for: .seconds(2.5))
            guard let hauptfenster = fenster(), speicher.planung != nil else {
                pruefen(false, "kein Fenster oder keine Planung")
                await ende()
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            hauptfenster.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))

            let widerrufen = eintrag(umschalt: false)
            let wiederholen = eintrag(umschalt: true)
            pruefen(widerrufen != nil && wiederholen != nil,
                    "die Einträge stehen im Menü (⌘Z, ⇧⌘Z)")
            pruefen(widerrufen?.title == "Widerrufen" && wiederholen?.title == "Wiederholen",
                    "ohne Verlauf heißen sie schlicht „\(widerrufen?.title ?? "—")“ / "
                    + "„\(wiederholen?.title ?? "—")“")
            // Freigegeben bleiben sie immer: Ein abgeblendeter Eintrag schluckt
            // sein Kürzel, und ⌘Z käme dann auch im Textfeld nicht mehr an.
            // Entschieden wird beim Griff — hier: Es passiert nichts.
            pruefen(freigegeben(widerrufen), "sie bleiben freigegeben (entschieden wird beim Griff)")
            let unberuehrt = speicher.planung
            kuerzel()
            try? await Task.sleep(for: .milliseconds(300))
            pruefen(speicher.planung == unberuehrt, "⌘Z ohne Verlauf tut nichts")

            // ── Eine Änderung, ihr Name im Menü, ⌘Z über das Menü ─────────
            let titelVorher = speicher.planung?.titel ?? ""
            speicher.titelSetzen(titelVorher + " — geprüft")
            await vorndran()
            pruefen(widerrufen?.title == "Widerrufen: " + Schrittname.planungstitelAendern,
                    "der Name steht im Menü: „\(widerrufen?.title ?? "—")“")

            kuerzel()
            try? await Task.sleep(for: .milliseconds(400))
            pruefen(speicher.planung?.titel == titelVorher,
                    "⌘Z über das Menü nimmt zurück — Titel „\(speicher.planung?.titel ?? "—")“")
            pruefen(wiederholen?.title == "Wiederholen: " + Schrittname.planungstitelAendern,
                    "und „\(wiederholen?.title ?? "—")“ steht bereit")
            let angenommen = ueberDenEintrag(wiederholen)
            try? await Task.sleep(for: .milliseconds(400))
            pruefen(speicher.planung?.titel == titelVorher + " — geprüft" && angenommen,
                    "„Wiederholen“ stellt wieder her (über den Eintrag im Menü)")
            kuerzel()
            try? await Task.sleep(for: .milliseconds(300))

            // ── Der Vorrang des Feldeditors (E87) ─────────────────────────
            await vorndran()
            Suchfeldbefehl.fokussieren()
            try? await Task.sleep(for: .milliseconds(700))
            let ersthelfer = hauptfenster.firstResponder
            let feld = ersthelfer as? NSTextView
            pruefen(feld != nil, "das Suchfeld hat die Schreibmarke (\(type(of: ersthelfer)))")
            if let feld {
                feld.insertText("Bruch", replacementRange: NSRange(location: 0, length: 0))
                try? await Task.sleep(for: .milliseconds(400))
                let getippt = feld.string
                let standVorher = speicher.planung?.titel ?? ""
                // Gemessen wird die Weiche, nicht der Text: Ein Suchfeld hängt
                // an seiner Bindung und bekommt den Wert des Modells sofort
                // wieder — sein Feldeditor darf ⌘Z trotzdem bekommen.
                pruefen(Schreibmarke.feldeditor != nil,
                        "die Weiche zeigt auf den Feldeditor („\(getippt)“, Verlauf: "
                        + "\(feld.undoManager?.canUndo == true))")
                kuerzel()
                try? await Task.sleep(for: .milliseconds(500))
                pruefen(speicher.planung?.titel == standVorher,
                        "und ⌘Z lässt die Planung unberührt")
            }
            hauptfenster.makeFirstResponder(nil)
            try? await Task.sleep(for: .milliseconds(300))

            // ── Kappung und Leeren beim Wechsel ──────────────────────────
            speicher.verlauf.leeren()
            // Echte Handgriffe, jeder ein eigener Schritt: Zellen freischalten
            // trägt keine Kennung und wächst darum nicht zusammen.
            let wochen = speicher.planung?.wochenListe ?? []
            let kurs = speicher.planung?.klassen.first?.id
            if let kurs, wochen.count >= 4 {
                for lauf in 0..<(speicher.verlauf.tiefe + 5) {
                    speicher.zelleFreiSchalten(klasse: kurs, woche: wochen[lauf % wochen.count])
                }
                pruefen(speicher.verlauf.zurueck.count == speicher.verlauf.tiefe,
                        "der Verlauf hält genau \(speicher.verlauf.tiefe) Schritte "
                        + "(\(speicher.verlauf.zurueck.count))")
            }
            speicher.verlauf.leeren()

            // ── Das Sitzplanblatt mit eigenem Verlauf (E82) ───────────────
            if let klasse = speicher.planung?.klassen.first {
                speicher.sitzplanUebernehmen(
                    Sitzplan.anordnen(klasseId: klasse.id, namen: ["Ada", "Alan", "Grace"]))
                speicher.sitzplanOeffnen(klasse: klasse.id)
                for _ in 0..<40 where hauptfenster.attachedSheet == nil {
                    try? await Task.sleep(for: .milliseconds(150))
                }
                if let blatt = hauptfenster.attachedSheet,
                   let flaeche = suchen(blatt.contentView, Sitzplanansicht.self) {
                    pruefen(speicher.sitzplanblattOffen, "das Blatt steht und führt seinen Verlauf")
                    let vorher = flaeche.plan
                    let tisch = vorher.tische[0]
                    @MainActor func maus(_ art: NSEvent.EventType, _ punkt: NSPoint) {
                        guard let ereignis = NSEvent.mouseEvent(
                            with: art, location: punkt, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: blatt.windowNumber, context: nil, eventNumber: 0,
                            clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) else { return }
                        NSApp.postEvent(ereignis, atStart: false)
                    }
                    let mitte = flaeche.convert(CGPoint(x: tisch.rahmen.midX, y: tisch.rahmen.midY),
                                                to: nil)
                    // Die Ereignisse gehen durch die Warteschlange der App:
                    // Das Blatt muss vorn sein, und zwischen den Schritten
                    // braucht die Schleife ihren Durchlauf.
                    NSApp.activate(ignoringOtherApps: true)
                    blatt.makeKeyAndOrderFront(nil)
                    blatt.makeFirstResponder(flaeche)
                    try? await Task.sleep(for: .milliseconds(300))
                    maus(.leftMouseDown, mitte)
                    try? await Task.sleep(for: .milliseconds(120))
                    for schritt in 1...4 {
                        maus(.leftMouseDragged,
                             NSPoint(x: mitte.x + CGFloat(schritt) * 16, y: mitte.y))
                        try? await Task.sleep(for: .milliseconds(80))
                    }
                    maus(.leftMouseUp, NSPoint(x: mitte.x + 64, y: mitte.y))
                    try? await Task.sleep(for: .milliseconds(800))
                    NSApp.activate(ignoringOtherApps: true)
                    try? await Task.sleep(for: .milliseconds(400))
                    pruefen(speicher.sitzplanverlauf.zurueck.count == 1,
                            "ein Zug ist ein Schritt (\(speicher.sitzplanverlauf.zurueck.count))")
                    pruefen(eintrag(umschalt: false)?.title
                                == "Widerrufen: " + Schrittname.tischeVerschieben,
                            "im Menü steht „\(eintrag(umschalt: false)?.title ?? "—")“")
                    blatt.makeFirstResponder(flaeche)
                    kuerzel()
                    try? await Task.sleep(for: .milliseconds(600))
                    pruefen(speicher.sitzplanEntwurf?.tische.first?.x == vorher.tische[0].x,
                            "⌘Z legt den Tisch zurück")
                }
                speicher.alleDialogeSchliessen()
                for _ in 0..<40 where hauptfenster.attachedSheet != nil {
                    try? await Task.sleep(for: .milliseconds(150))
                }
                try? await Task.sleep(for: .milliseconds(400))
                pruefen(!speicher.sitzplanblattOffen && speicher.sitzplanverlauf.zurueck.isEmpty,
                        "nach dem Schließen ist der Verlauf des Blatts fort (E85) — Blatt offen: "
                        + "\(speicher.sitzplanblattOffen), Schritte: "
                        + "\(speicher.sitzplanverlauf.zurueck.count), Blatt am Fenster: "
                        + "\(hauptfenster.attachedSheet != nil), Dialog: "
                        + "\(String(describing: speicher.offenerDialog))")
            }

            await ende()
        }
    }
}
