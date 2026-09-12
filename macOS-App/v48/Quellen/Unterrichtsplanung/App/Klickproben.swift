// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Proben am echten Fenster mit echten Ereignissen: rollen, klicken, ziehen,
/// tippen, Menüs — was ein Prüfziel ohne Fenster nicht zeigen kann.
@MainActor
enum Klickproben {

    /// `--rolltest`: rollt das Raster über eine wiederkehrende Uhr und meldet
    /// die Zeit je Bild.
    static func rolltestUndBeenden(zerlegen: Bool) {
        Messzaehler.an = zerlegen
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let rollbereich = groesserRollbereich(in: fenster.contentView) else {
                print("ROLLTEST kein Rollbereich gefunden")
                NSApp.terminate(nil)
                return
            }

            let messung = Messung()
            messung.beginn = Date()
            messung.rechenzeitVorher = Messung.rechenzeit()
            let uhr = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
                MainActor.assumeIsolated {
                    rollbereich.contentView.scroll(
                        to: NSPoint(x: CGFloat((messung.schritt % 60) * 40), y: 0))
                    rollbereich.reflectScrolledClipView(rollbereich.contentView)
                    messung.schritt += 1
                    guard messung.schritt >= 120 else { return }
                    // Anhalten vor dem Auswerten: sonst schlüge die Uhr während
                    // des Nachlaufs weiter und riefe `fertig()` erneut auf.
                    messung.uhr?.invalidate()
                    messung.uhr = nil
                    messung.fertig()
                }
            }
            messung.uhr = uhr
            RunLoop.main.add(uhr, forMode: .common)
        }
    }

    /// `--klicktest`: misst einen Handgriff am echten Fenster in echter Größe —
    /// im Prüfstand ist es kleiner, und die Zahl fiele zu günstig aus.
    static func klicktestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard let planung = speicher.planung,
                  let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let klasse = planung.klassen.first else {
                print("KLICKTEST keine Planung")
                NSApp.terminate(nil)
                return
            }
            let wochen = planung.wochenListe
            // Rechenzeit statt Uhrzeit: SwiftUI trägt erst im nächsten Ablaufring nach.
            let laeufe = 10
            let vorher = Messung.rechenzeit()
            for lauf in 0..<laeufe {
                speicher.zelleFreiSchalten(klasse: klasse.id, woche: wochen[lauf % wochen.count])
                fenster.contentView?.layoutSubtreeIfNeeded()
                fenster.displayIfNeeded()
                try? await Task.sleep(for: .milliseconds(150))
            }
            let dauer = (Messung.rechenzeit() - vorher) / Double(laeufe) * 1000
            print(String(format: "KLICKTEST %.0f ms Rechenzeit je Handgriff (Fenster %.0f × %.0f, "
                         + "%d Klassen/Kurse, %d Wochen, %d Vorhaben)", dauer,
                         fenster.frame.width, fenster.frame.height,
                         planung.klassen.count, planung.wochen, planung.eintraege.count))
            // Hausaufgabe hinzufügen und entfernen wie aus dem Rechtsklickmenü —
            // an einem Vorhaben ohne; Entfernen nimmt die Zeile mit, danach
            // steht die Datei wieder wie vorher.
            if let ohne = planung.eintraege.first(where: { !$0.hausaufgabe }) {
                speicher.hausaufgabeUmschalten(ohne.id)
                fenster.contentView?.layoutSubtreeIfNeeded()
                fenster.displayIfNeeded()
                let an = speicher.planung?.eintraege.first { $0.id == ohne.id }?.hausaufgabe == true
                speicher.hausaufgabeUmschalten(ohne.id)
                let danach = speicher.planung?.eintraege.first { $0.id == ohne.id }
                let aus = danach?.hausaufgabe == false && danach?.hausaufgabenText == ""
                print("KLICKTEST Hausaufgabe an \(an ? "✓" : "✗"), aus \(aus ? "✓" : "✗")")
            } else {
                print("KLICKTEST Hausaufgabe: kein Vorhaben ohne — übersprungen")
            }
            NSApp.terminate(nil)
        }
    }

    /// `--auswahltest`: klickt wirklich ins Raster, auch mit ⌘ und ⇧ — ob eine
    /// Geste beim richtigen Empfänger ankommt, zeigt nur ein echtes Ereignis.
    static func auswahltestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let planung = speicher.planung else {
                print("AUSWAHLTEST kein Fenster")
                NSApp.terminate(nil)
                return
            }
            let breite = CGFloat(speicher.spaltenbreite)
            guard planung.klassen.count >= 3 else {
                print("AUSWAHLTEST zu wenige Klassen/Kurse")
                NSApp.terminate(nil)
                return
            }

            @MainActor func klicken(_ punkt: NSPoint, _ tasten: NSEvent.ModifierFlags) {
                for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let ereignis = NSEvent.mouseEvent(
                        with: art, location: punkt, modifierFlags: tasten,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: fenster.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0)
                    else { continue }
                    // Einreihen: `sendEvent` überspränge die Tastenstand-Beobachter.
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }

            // Ein Klick ins nicht aktive Fenster aktiviert es nur und wird verschluckt.
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            fenster.setContentSize(NSSize(width: 1800, height: 1000))
            // An den linken Rand zurück — die Klickpunkte sind ausgemessen.
            speicher.sprung = Rastersprung(woche: 0)
            try? await Task.sleep(for: .milliseconds(900))

            let inhalt = fenster.contentView!
            @MainActor func punkt(woche: Int) -> NSPoint {
                NSPoint(x: Masse.spalteKlasse + (CGFloat(woche) + 0.5) * breite,
                        y: inhalt.frame.maxY - 130)
            }

            var bericht: [String] = []
            @MainActor func festhalten(_ was: String, _ erwartet: [String]) async {
                // 700 ms Abstand: dichter aufeinander wertet AppKit als Doppelklick.
                try? await Task.sleep(for: .milliseconds(700))
                let ist = speicher.auswahl.sorted()
                let dialog = speicher.vorhabenDialog != nil ? " (Dialog offen!)" : ""
                bericht.append("\(was): [\(ist.joined(separator: ", "))]"
                               + (ist == erwartet.sorted() ? " ✓" : " ✗ erwartet ["
                                  + erwartet.sorted().joined(separator: ", ") + "]") + dialog)
                speicher.vorhabenDialog = nil
            }

            klicken(punkt(woche: 0), [])
            await festhalten("einfacher Klick", ["e0-0"])

            klicken(punkt(woche: 2), [.command])
            await festhalten("⌘ nimmt dazu", ["e0-0", "e0-2"])

            klicken(punkt(woche: 2), [.command])
            await festhalten("⌘ nimmt wieder weg", ["e0-0"])

            klicken(punkt(woche: 0), [])
            await festhalten("einfacher Klick setzt zurück", ["e0-0"])

            klicken(punkt(woche: 4), [.shift])
            await festhalten("⇧ nimmt die Spanne", ["e0-0", "e0-2", "e0-4"])

            print("AUSWAHLTEST\n  " + bericht.joined(separator: "\n  "))
            NSApp.terminate(nil)
        }
    }

    /// `--ziehtest`: Beim Fallenlassen kommt der Zeigerort in
    /// Fensterkoordinaten an (`NSDraggingInfo.draggingLocation`), gebraucht wird
    /// er in Zellenkoordinaten — ob die Umrechnung am gerollten Raster stimmt,
    /// zeigt nur das laufende Fenster.
    static func ziehtestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let planung = speicher.planung, let kurs = planung.klassen.first else {
                print("ZIEHTEST kein Fenster / keine Planung")
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            fenster.setContentSize(NSSize(width: 1800, height: 1000))
            speicher.sprung = Rastersprung(woche: 0)
            try? await Task.sleep(for: .milliseconds(900))

            var gefunden: Zellenkoerper?
            @MainActor func suchen(_ ansicht: NSView) {
                if let zelle = ansicht as? Zellenkoerper, zelle.zeile == 0, zelle.woche == 0 {
                    gefunden = zelle
                }
                ansicht.subviews.forEach(suchen)
            }
            if let inhalt = fenster.contentView { suchen(inhalt) }
            let kacheln = gefunden?.subviews.compactMap { $0 as? Kachelansicht } ?? []
            guard let zelle = gefunden, kacheln.count >= 2 else {
                print("ZIEHTEST braucht wenigstens zwei Kacheln in der ersten Zelle")
                NSApp.terminate(nil)
                return
            }

            // Genau der Weg, den `acceptDrop` geht.
            @MainActor func stelleBei(_ y: CGFloat) -> String {
                let imFenster = kacheln[0].convert(NSPoint(x: 10, y: y), to: nil)
                return zelle.einfuegestelle(bei: zelle.convert(imFenster, from: nil)).vorId
                    ?? "ans Ende"
            }
            let vorher = planung.vorhaben(klasse: kurs.id, woche: 0).map(\.id)
            let oben = stelleBei(2)
            let unten = stelleBei(kacheln[0].bounds.height - 2)

            guard let letztes = planung.vorhaben(klasse: kurs.id, woche: 0).last else { return }
            speicher.versetzen([letztes], nach: Zellenort(klasse: kurs.id, woche: 0),
                               verschieben: true, vor: vorher.first)
            let nachher = (speicher.planung?.vorhaben(klasse: kurs.id, woche: 0) ?? []).map(\.id)

            if let pfad = ProcessInfo.processInfo.environment["ZIEHBILD"] {
                zelle.zielSetzen(true, marke: 1)
                zelle.displayIfNeeded()
                try? await Task.sleep(for: .milliseconds(300))
                Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: pfad))
                zelle.zielSetzen(false)
            }

            print("ZIEHTEST")
            print("  über der Mitte der ersten Kachel → vor \(oben)"
                  + (oben == vorher.first ? "  ✓" : "  ✗ erwartet \(vorher[0])"))
            print("  unter ihrer Mitte → vor \(unten)"
                  + (unten == vorher[1] ? "  ✓" : "  ✗ erwartet \(vorher[1])"))
            print("  vorher:  " + vorher.joined(separator: ", "))
            print("  nachher: " + nachher.joined(separator: ", "))
            NSApp.terminate(nil)
        }
    }

    /// `--mischtest`: Der Speicher schließt aus, dass Zelle und Vorhaben
    /// zugleich angewählt sind — ob am Bildschirm trotzdem zwei Rahmen stehen
    /// (der Tastaturfokus zeichnet einen eigenen), zeigt nur das Fenster.
    static func mischtestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  speicher.planung != nil else {
                print("MISCHTEST kein Fenster — \(NSApp.windows.count) Fenster, "
                      + "Planung \(speicher.planung == nil ? "fehlt" : "da")")
                NSApp.terminate(nil)
                return
            }
            let breite = CGFloat(speicher.spaltenbreite)
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            fenster.setContentSize(NSSize(width: 1800, height: 1000))
            speicher.sprung = Rastersprung(woche: 0)
            try? await Task.sleep(for: .milliseconds(900))

            let inhalt = fenster.contentView!
            @MainActor func punkt(woche: Int) -> NSPoint {
                NSPoint(x: Masse.spalteKlasse + (CGFloat(woche) + 0.5) * breite,
                        y: inhalt.frame.maxY - 130)
            }
            @MainActor func klicken(_ punkt: NSPoint) {
                for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let ereignis = NSEvent.mouseEvent(
                        with: art, location: punkt, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: fenster.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0)
                    else { continue }
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }

            var bericht: [String] = []
            @MainActor func festhalten(_ was: String) async {
                try? await Task.sleep(for: .milliseconds(700))
                let gewaehlt = speicher.auswahl.sorted().joined(separator: ", ")
                let zelle = speicher.zielzelle.map { "\($0.klasse.suffix(5))/KW\($0.woche)" } ?? "—"
                let empfaenger = fenster.firstResponder.map { String(describing: type(of: $0)) } ?? "—"
                bericht.append("\(was): Vorhaben [\(gewaehlt)] · Zelle \(zelle) · Fokus \(empfaenger)")
                speicher.vorhabenDialog = nil
            }

            klicken(punkt(woche: 0))
            await festhalten("1. Klick auf Vorhaben (Zeile 0, KW 0)")

            klicken(punkt(woche: 1))
            await festhalten("2. Klick auf leere Zelle (Zeile 0, KW 1)")

            // Über die Umgebung: weitere Aufrufparameter deutet AppKit als Voreinstellungen.
            if let pfad = ProcessInfo.processInfo.environment["MISCHBILD"] {
                Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: pfad))
            }

            klicken(punkt(woche: 0))
            await festhalten("3. Klick zurück auf das Vorhaben")

            print("MISCHTEST\n  " + bericht.joined(separator: "\n  "))
            NSApp.terminate(nil)
        }
    }

    /// `--titeltest`: Schickt AppKit für den Fenstertitel
    /// `NSText.didBeginEditingNotification`? Ohne die Meldung löschte ⌫
    /// Vorhaben, während jemand den Titel korrigiert.
    static func titeltestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }) else {
                print("TITELTEST kein Fenster")
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))

            // Der Titel sitzt in der Rahmenansicht, nicht im Inhalt.
            var felder: [NSTextField] = []
            @MainActor func absuchen(_ ansicht: NSView) {
                if let feld = ansicht as? NSTextField, feld.isEditable { felder.append(feld) }
                ansicht.subviews.forEach(absuchen)
            }
            if let rahmen = fenster.contentView?.superview { absuchen(rahmen) }

            var bericht: [String] = ["beschreibbare Textfelder in der Fensterleiste: \(felder.count)"]
            bericht.append("vorher: schreibstelleAktiv = \(speicher.schreibstelleAktiv)")
            if let titelfeld = felder.first {
                fenster.makeFirstResponder(titelfeld)
                try? await Task.sleep(for: .milliseconds(400))
                bericht.append("Titelfeld hat die Schreibmarke: "
                               + "\(fenster.firstResponder is NSTextView)")
                bericht.append("beim Schreiben: schreibstelleAktiv = "
                               + "\(speicher.schreibstelleAktiv) "
                               + (speicher.schreibstelleAktiv ? "✓" : "✗ — ⌫ löschte hier Vorhaben"))
                fenster.makeFirstResponder(nil)
                try? await Task.sleep(for: .milliseconds(400))
                bericht.append("danach wieder: schreibstelleAktiv = "
                               + "\(speicher.schreibstelleAktiv) "
                               + (speicher.schreibstelleAktiv ? "✗ hängt fest" : "✓"))
            } else {
                bericht.append("✗ kein beschreibbares Titelfeld gefunden")
            }
            print("TITELTEST\n  " + bericht.joined(separator: "\n  "))
            NSApp.terminate(nil)
        }
    }

    /// `--menuetest`: In der Menüleiste können zwei Einträge dasselbe Kürzel
    /// tragen — welcher greift, zeigt nur die laufende Anwendung.
    static func menuetestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let planung = speicher.planung, planung.eintraege.count >= 2 else {
                print("MENUETEST keine Planung mit mindestens zwei Vorhaben")
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))

            speicher.anwaehlen(vorhaben: planung.eintraege[0].id)
            speicher.anwaehlen(vorhaben: planung.eintraege[1].id, erweitern: true)
            speicher.kopieren()
            try? await Task.sleep(for: .milliseconds(300))

            NSApp.mainMenu?.update()
            var zeilen: [String] = []
            zeilen.append("Auswahl \(speicher.auswahl.count) · Ablage "
                          + "\(speicher.ablage?.vorhaben.count ?? 0) · kannEinfuegen "
                          + "\(speicher.kannEinfuegen) · schreibstelleAktiv "
                          + "\(speicher.schreibstelleAktiv)")

            @MainActor func absuchen(_ menue: NSMenu, _ pfad: String) {
                for punkt in menue.items {
                    if let unter = punkt.submenu {
                        absuchen(unter, pfad.isEmpty ? punkt.title : pfad + " › " + punkt.title)
                        continue
                    }
                    let taste = punkt.keyEquivalent
                    guard ["c", "v", "x", "\u{8}", "\u{7f}"].contains(taste),
                          punkt.keyEquivalentModifierMask.contains(.command) || taste.count == 1,
                          !punkt.isSeparatorItem else { continue }
                    let name = taste == "\u{8}" || taste == "\u{7f}" ? "⌫" : "⌘" + taste.uppercased()
                    zeilen.append("  \(name)  „\(punkt.title)“ in [\(pfad)] · "
                                  + "aktiv \(punkt.isEnabled ? "ja" : "NEIN") · "
                                  + "Handlung \(punkt.action.map(String.init(describing:)) ?? "—")")
                }
            }
            if let haupt = NSApp.mainMenu { absuchen(haupt, "") }

            if let bearbeiten = NSApp.mainMenu?.items
                .first(where: { $0.title == "Bearbeiten" || $0.title == "Edit" })?.submenu {
                zeilen.append("Bearbeiten-Menü (\(bearbeiten.items.count) Einträge):")
                for punkt in bearbeiten.items {
                    let taste = punkt.keyEquivalent.isEmpty ? "—" : punkt.keyEquivalent
                    zeilen.append("  · „\(punkt.isSeparatorItem ? "———" : punkt.title)“ "
                                  + "Kürzel \(taste) · aktiv \(punkt.isEnabled ? "ja" : "nein")")
                }
            }

            var glied: NSResponder? = fenster.firstResponder
            var kette: [String] = []
            while let r = glied {
                var kann: [String] = []
                if r.responds(to: #selector(NSText.copy(_:))) { kann.append("copy") }
                if r.responds(to: #selector(NSText.paste(_:))) { kann.append("paste") }
                kette.append(String(describing: type(of: r))
                             + (kann.isEmpty ? "" : " ← \(kann.joined(separator: "/"))"))
                glied = r.nextResponder
            }
            zeilen.append("Antwortkette: " + kette.joined(separator: " → "))

            @MainActor func zustand(_ titel: String, soll: Bool) {
                @MainActor func finden(_ menue: NSMenu) -> NSMenuItem? {
                    for punkt in menue.items {
                        if punkt.title == titel { return punkt }
                        if let unter = punkt.submenu, let treffer = finden(unter) { return treffer }
                    }
                    return nil
                }
                guard let haupt = NSApp.mainMenu, let punkt = finden(haupt) else {
                    zeilen.append("  „\(titel)“ NICHT GEFUNDEN ✗"); return
                }
                zeilen.append("  „\(titel)“ ist \(punkt.isEnabled ? "aktiv" : "grau")"
                              + " · soll \(soll ? "aktiv" : "grau") sein"
                              + (punkt.isEnabled == soll ? " ✓" : " ✗"))
            }
            zeilen.append("Nachführung der Menüzustände (Planung geladen, \(speicher.auswahl.count) angewählt):")
            zustand("Vorhaben durchsuchen", soll: true)
            zustand("Klassen/Kurse und Fächer …", soll: true)
            zustand("Kopieren", soll: true)
            zustand("Einsetzen", soll: true)

            // Aktiv-Zustand allein trügt: SwiftUI-Einträge tragen keine prüfbare Handlung.
            zeilen.append("Wirkung der Tastenkürzel:")
            @MainActor func druecken(_ zeichen: String, _ name: String,
                                     _ tasten: NSEvent.ModifierFlags = [.command],
                                     wirkung: @MainActor () -> String) async {
                let vorher = wirkung()
                // Einreihen: `performKeyEquivalent` umginge den echten Tastenweg.
                for art in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let ereignis = NSEvent.keyEvent(
                        with: art, location: .zero, modifierFlags: tasten,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: fenster.windowNumber, context: nil,
                        characters: zeichen, charactersIgnoringModifiers: zeichen,
                        isARepeat: false, keyCode: 0) else { return }
                    NSApp.postEvent(ereignis, atStart: false)
                }
                try? await Task.sleep(for: .milliseconds(500))
                let nachher = wirkung()
                zeilen.append("  \(name): \(vorher) → \(nachher)"
                              + (vorher == nachher ? "  ✗ ohne Wirkung" : "  ✓"))
            }

            for (taste, name, welcher) in [("k", "⌘K (Klassen/Kurse)", "klassen"),
                                           ("e", "⌘E (Ferien)", "ferien"),
                                           (",", "⌘, (Einstellungen)", "einstellungen"),
                                           ("d", "⌘D (Tagesliste)", "heute")] {
                await druecken(taste, name) { "Dialog \(speicher.offenerDialog?.rawValue ?? "—")" }
                if speicher.offenerDialog?.rawValue != welcher {
                    zeilen.append("      erwartet war „\(welcher)“")
                }
                speicher.offenerDialog = nil
                try? await Task.sleep(for: .milliseconds(200))
            }

            speicher.sprung = nil
            await druecken("j", "⌘J (laufende Woche)") { "Sprung \(speicher.sprung?.woche ?? -1)" }

            speicher.anwaehlen(vorhaben: planung.eintraege[0].id)
            await druecken("a", "⌘A (alles wählen)") { "Auswahl \(speicher.auswahl.count)" }
            speicher.anwaehlen(vorhaben: planung.eintraege[0].id)
            speicher.anwaehlen(vorhaben: planung.eintraege[1].id, erweitern: true)

            speicher.ablageLeeren()
            await druecken("c", "⌘C (kopieren)") { "Ablage \(speicher.ablage?.vorhaben.count ?? 0)" }

            if speicher.ablage == nil { speicher.kopieren() }
            let ziel = planung.klassen.count > 1 ? planung.klassen[1].id : planung.klassen[0].id
            speicher.anwaehlen(zelle: Zellenort(klasse: ziel, woche: 6))
            await druecken("v", "⌘V (einfügen)") { "Vorhaben \(speicher.planung?.eintraege.count ?? 0)" }

            speicher.anwaehlen(vorhaben: planung.eintraege[0].id)
            await druecken("\u{8}", "⌫ (löschen)", []) {
                "Rückfrage \(speicher.rueckfrage == nil ? "nein" : "ja")"
            }

            // Rückfrage wegräumen — solange sie steht, ist sie das Schlüsselfenster.
            speicher.rueckfrageBeantworten(false)
            fenster.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))
            zeilen.append("Im Textfeld (Fenstertitel):")
            var felder: [NSTextField] = []
            @MainActor func absuchenFelder(_ ansicht: NSView) {
                if let feld = ansicht as? NSTextField, feld.isEditable { felder.append(feld) }
                ansicht.subviews.forEach(absuchenFelder)
            }
            if let rahmen = fenster.contentView?.superview { absuchenFelder(rahmen) }
            if let titelfeld = felder.first {
                NSPasteboard.general.clearContents()
                let titel = "Prüftext"
                fenster.makeFirstResponder(titelfeld)
                try? await Task.sleep(for: .milliseconds(300))
                titelfeld.currentEditor()?.string = titel
                try? await Task.sleep(for: .milliseconds(200))
                // Hier ist „gleich geblieben“ der Erfolg — daher die eigene Zeile.
                let vorherAuswahl = speicher.auswahl.count
                await druecken("a", "  ⌘A (nur ins Feld)") { "Feldeditor" }
                zeilen.removeLast()
                zeilen.append("    ⌘A greift nicht ins Raster: Auswahl "
                              + "\(vorherAuswahl) → \(speicher.auswahl.count)"
                              + (vorherAuswahl == speicher.auswahl.count ? "  ✓" : "  ✗"))
                await druecken("c", "  ⌘C im Titelfeld") {
                    "Zwischenablage „\(NSPasteboard.general.string(forType: .string) ?? "—")“"
                }
                let kopiert = NSPasteboard.general.string(forType: .string)
                zeilen.append("    Titel war „\(titel)“ · kopiert wurde "
                              + "„\(kopiert ?? "—")“"
                              + (kopiert == titel ? "  ✓" : "  ✗"))
                fenster.makeFirstResponder(nil)
            } else {
                zeilen.append("    kein Textfeld gefunden")
            }

            print("MENUETEST\n" + zeilen.joined(separator: "\n"))
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private final class Messung {
        var schritt = 0
        var beginn = Date()
        var rechenzeitVorher: Double = 0
        /// Die Uhr hängt hier, nicht am Blockbeiwert: `Timer` ist nicht
        /// `Sendable`, und Swift 6 weist das Durchreichen in den
        /// MainActor-Block ab.
        var uhr: Timer?

        /// Verbrauchte Rechenzeit — erfasst auch, was der Ablaufring später
        /// erledigt.
        nonisolated static func rechenzeit() -> Double {
            var nutzung = rusage()
            getrusage(RUSAGE_SELF, &nutzung)
            let benutzer = Double(nutzung.ru_utime.tv_sec) + Double(nutzung.ru_utime.tv_usec) / 1e6
            let system = Double(nutzung.ru_stime.tv_sec) + Double(nutzung.ru_stime.tv_usec) / 1e6
            return benutzer + system
        }

        func fertig() {
            let schritte = max(1, schritt)
            let dauer = Date().timeIntervalSince(beginn)
            Task { @MainActor in
                // Nachlauf abwarten: die Rechenzeit trägt der Ablaufring später nach.
                try? await Task.sleep(for: .milliseconds(400))
                let rechenzeit = Messung.rechenzeit() - rechenzeitVorher
                print(String(format: "ROLLTEST %d Schritte in %.2f s · Rechenzeit %.2f s "
                             + "· %.1f ms je Schritt", schritte, dauer, rechenzeit,
                             rechenzeit / Double(schritte) * 1000))
                if Messzaehler.an { print("  ZERLEGT " + Messzaehler.zeitbericht()) }
                NSApp.terminate(nil)
            }
        }
    }

    private static func groesserRollbereich(in wurzel: NSView?) -> NSScrollView? {
        guard let wurzel else { return nil }
        var gefunden: [NSScrollView] = []
        func absuchen(_ ansicht: NSView) {
            if let rollbereich = ansicht as? NSScrollView { gefunden.append(rollbereich) }
            ansicht.subviews.forEach(absuchen)
        }
        absuchen(wurzel)
        return gefunden.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}
