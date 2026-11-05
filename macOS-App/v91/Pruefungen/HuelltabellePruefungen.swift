// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

/// Die AppKit-Hülle der Tabellen (E1020): am Quelltext, was ihr Verhalten trägt. Das Verhalten selbst prüft die
/// Lernendenprobe am Fenster — ⌘A und Klick, Teilauswahl, ⇧-Klick, Klick neben die Zeilen, ↓/↑, Leiste.
@Suite("Hülle der Tabellen: Quelltext (E1020)")
struct HuelltabellePruefungen {
    static func quelle(_ pfad: String) throws -> String {
        let datei = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/" + pfad)
        return try String(contentsOf: datei, encoding: .utf8)
    }

    /// Der Code ohne Kommentare: Zeilen, die nur Kommentar sind, fallen weg, ein Kommentar am Zeilenende („ // “) ebenso — gezählt
    /// wird im Code (U3-05).
    static func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .map { zeile in zeile.range(of: " // ").map { String(zeile[..<$0.lowerBound]) } ?? String(zeile) }
            .joined(separator: "\n")
    }

    /// Die Dialoge der Lernendenverwaltung und ihre Zahl an Tabellen: Lerngruppen, Mitglieder, „Alle Lernenden“; Tabelle einer
    /// Mitteilung, Maßnahmen, Vereinbarungen, Anliegen einer Person; im Archiv Personen und Lerngruppen des laufenden
    /// Schuljahrs, Personen, Lerngruppen und Anliegen eines Vorjahrs.
    static let dialoge = [("Oberflaeche/Dialoge/LernendenDialog.swift", 3), ("Oberflaeche/Dialoge/AnliegenAnsicht.swift", 4),
                          ("Oberflaeche/Dialoge/ArchivAnsicht.swift", 5)]

    @Test("E1020: Alle zwölf Tabellen der Lernendenverwaltung sind Hüllen — keine `Table`, keine `TableColumn`")
    func alleTabellen() throws {
        for (pfad, zahl) in Self.dialoge {
            let text = try Self.quelle(pfad)
            #expect(text.range(of: #"\bTable\s*\("#, options: .regularExpression) == nil, "\(pfad): keine `Table`")
            #expect(!text.contains("TableColumn"), "\(pfad): keine `TableColumn`")
            #expect(text.components(separatedBy: "Huelltabelle(").count - 1 == zahl, "\(pfad): \(zahl) Hüllen")
            // U3-04: Jede Spalte nennt ihren Text — ohne ihn überspringt die Tippwahl die Spalte.
            let code = Self.code(text)
            #expect(code.components(separatedBy: "Huellspalte(").count == code.components(separatedBy: "text: {").count,
                    "\(pfad): jede Spalte mit `text:`")
        }
    }

    @Test("E1020: Die Wege um SwiftUIs Tabelle sind fort — keine Pfeiltastenwahl, kein eigener Ordnungskopf")
    func wegeFort() throws {
        let wurzel = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung")
        let dateien = try #require(FileManager.default.enumerator(at: wurzel, includingPropertiesForKeys: nil))
        var gelesen = 0
        for case let datei as URL in dateien where datei.pathExtension == "swift" {
            let text = try String(contentsOf: datei, encoding: .utf8)
            gelesen += 1
            let treffer = text.range(of: #"\b(pfeiltastenNachAlle|Pfeiltastenwahl|pfeilwunsch|pfeilMerken|pfeilziel|"#
                                     + #"leerenNachPfeil|Ordnungskopf)\b"#, options: .regularExpression)
            #expect(treffer == nil, "\(datei.lastPathComponent): \(treffer.map { String(text[$0]) } ?? "")")
        }
        #expect(gelesen > 100, "die Quellen gefunden (\(gelesen) Dateien)")
    }

    @Test("E1029: Die Hülle wählt nach dem Loslassen über einen Ereignismonitor — `mouseDown` bleibt AppKits (K6, macOS 27)")
    func klickUeberMonitor() throws {
        let text = try Self.quelle("Oberflaeche/Huelltabelle.swift")
        #expect(text.range(of: #"override\s+func\s+mouse(Down|Up|Dragged)\b"#, options: .regularExpression) == nil,
                "kein Überschreiben der Mausereignisse")
        #expect(text.contains("NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown])"), "ein lokaler Monitor")
        #expect(text.contains("} else { self?.klickVormerken(ereignis) }"), "Klicks gehen an klickVormerken")
        #expect(text.contains("RunLoop.main.perform(inModes: [.default])"), "gewählt erst nach dem Loslassen")
        #expect(text.contains("!bedienbareSpalten.contains(spalte)"), "Spalten mit Steuerung ausgenommen")
        // Z-BC8a-03: der Treffertest im System der Oberansicht — im Blatt traf er sonst den Kopf der Tabelle.
        #expect(text.contains("let getroffen = rahmen.hitTest(ereignis.locationInWindow)"), "Treffertest im Fenster")
        #expect(!text.contains("inhalt.hitTest("), "nicht im System des Inhalts")
        // Z-BC8a-04, R8a-01: AppKits vorgemerkte Wahl unmittelbar vor der eigenen zurückgenommen, im Code, nicht im Kommentar.
        #expect(text.contains("                NSObject.cancelPreviousPerformRequests(withTarget: self)\n"
                              + "                self.selectRowIndexes(IndexSet(integer: zeile), byExtendingSelection: false)"),
                "vor der eigenen Wahl")
        // R8a-03: nur, wenn AppKit die Auswahl beim Klick stehen ließ.
        #expect(text.contains("let vorher = selectedRowIndexes"))
        #expect(text.contains("guard let self, !menue.offen, !self.vorschlagSeitKlick, "
                              + "self.selectedRowIndexes == vorher else { return }"))
        // E1032 (R8a-03): Hat AppKit seit dem Klick eine Auswahl vorgeschlagen (Aufziehen), wählt die Hülle nicht selbst —
        // auch wenn das Aufziehen auf denselben Zeilen endet. Zurückgesetzt bei jedem Klick, den der Monitor vormerkt;
        // gesetzt beim Vorschlag.
        #expect(text.contains("        vorschlagSeitKlick = false\n        RunLoop.main.perform(inModes: [.default])"))
        #expect(text.contains("        (tableView as? Huellansicht)?.vorschlagSeitKlick = true\n"
                              + "        return waehlbar ? proposed : []"))
        #expect(text.components(separatedBy: "vorschlagSeitKlick = ").count - 1 == 3,
                "angelegt, zurückgesetzt, gesetzt — sonst nirgends")
        // U3-03: wann der Monitor vormerkt — ein Klick ohne Taste im eigenen Fenster auf eine von mehreren Gewählten.
        #expect(text.contains("guard let fenster = window, ereignis.window === fenster, ereignis.clickCount == 1,"))
        #expect(text.contains("ereignis.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty,"))
        #expect(text.contains("guard zeile >= 0, !bedienbareSpalten.contains(spalte), selectedRowIndexes.count > 1,\n"
                              + "              selectedRowIndexes.contains(zeile) else { return }"))
        // R8a-01: die Steuerspalten kommen bei der Tabelle an.
        #expect(text.contains("tabelle.bedienbareSpalten = IndexSet(spalten.indices.filter { spalten[$0].bedienbar })"))
        // R8a-10: der Monitor auch beim Freigeben abgemeldet.
        #expect(text.contains("isolated deinit {\n        if let monitor { NSEvent.removeMonitor(monitor) }"))
    }

    @Test("U1-04: Rollt die Hand mit der Tastatur (Bild ↑/↓, Pos1, Ende), hält die Hülle die Gewählte nicht mehr im Bild")
    func rolltastenLassenLos() throws {
        let text = HuelltabellePruefungen.code(try Self.quelle("Oberflaeche/Huelltabelle.swift"))
        #expect(text.contains("monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown])"))
        // Der Zweig nach der Ereignisart, und das Ereignis geht unverändert weiter (R8g-02).
        #expect(text.contains("if ereignis.type == .keyDown { self?.rolltasteVormerken(ereignis) } else { "
                              + "self?.klickVormerken(ereignis) }\n            }\n            return ereignis\n"))
        // Nur im eigenen Fenster, nur an der Tabelle oder in ihr, nur die vier Rolltasten — und erst danach die Meldung.
        #expect(text.contains("guard let fenster = window, ereignis.window === fenster, let ersthelfer = fenster.firstResponder "
                              + "as? NSView,\n              ersthelfer === self || ersthelfer.isDescendant(of: self),\n"
                              + "              [115, 116, 119, 121].contains(ereignis.keyCode) else { return }\n"
                              + "        tastaturGerollt?()\n    }"))
        #expect(text.contains("tabelle.tastaturGerollt = { [weak k = context.coordinator] in k?.imBild = nil }"))
    }

    @Test("U1-01: Ohne Neuladen bekommen alle vorhandenen Zeilen ihren neuen Inhalt, nicht nur die sichtbaren")
    func alleZeilenErneuert() throws {
        let text = HuelltabellePruefungen.code(try Self.quelle("Oberflaeche/Huelltabelle.swift"))
        #expect(text.contains("tabelle.enumerateAvailableRowViews { zeilenansicht, zeile in"))
        #expect(!text.contains("tabelle.rows(in: tabelle.visibleRect)"), "nicht nur die sichtbaren")
        // U1-03: die Köpfe auch nach einem Wechsel der Akzentfarbe.
        #expect(text.contains("name: NSColor.systemColorsDidChangeNotification"))
    }

    @Test("E498: Der Kopf der vorn ordnenden Spalte ist hervorgehoben — die Hülle rechnet und zeichnet ihn")
    func vornHervorgehoben() throws {
        let text = try Self.quelle("Oberflaeche/Huelltabelle.swift")
        #expect(text.contains("let vorn = ordnung.flatMap { Self.vorneStelle($0.wrappedValue, spalten.map { $0.ordnen?.keyPath }) }"))
        #expect(text.contains(".font: stelle == vorn ? halbfett : grund,"))
        #expect(text.contains(".foregroundColor: stelle == vorn ? akzent : text,"))
    }

    @Test("E1029: Spalten mit einer Steuerung sind gekennzeichnet — „Stand“ viermal, „Zurückholen“ zweimal")
    func bedienbareSpalten() throws {
        for (pfad, zahl) in [("Oberflaeche/Dialoge/LernendenDialog.swift", 0), ("Oberflaeche/Dialoge/AnliegenAnsicht.swift", 4),
                             ("Oberflaeche/Dialoge/ArchivAnsicht.swift", 2)] {
            let text = Self.code(try Self.quelle(pfad))
            #expect(text.components(separatedBy: "bedienbar: true").count - 1 == zahl, "\(pfad): \(zahl)")
            // U3-01: nur an „Stand“ und „Zurückholen“.
            for spalte in text.components(separatedBy: "Huellspalte(").dropFirst() where spalte.contains("bedienbar: true") {
                let erlaubt = spalte.hasPrefix("Mitteilungstext.spalteStand,") || spalte.hasPrefix("\"Stand\",")
                    || (spalte.hasPrefix("\"\",") && spalte.contains("LaufendesSchuljahr.zurueckholen"))
                #expect(erlaubt, "\(pfad): `bedienbar` an \(spalte.prefix(40))")
            }
        }
    }

    @Test("E931–E934: Eine von Hand allein gewählte Zeile bleibt im Bild, wenn danach der Ausschnitt schrumpft")
    func gewaehlteImBild() throws {
        let text = try Self.quelle("Oberflaeche/Huelltabelle.swift")
        #expect(text.contains("rolle.contentView.postsFrameChangedNotifications = true"), "der Ausschnitt meldet sich")
        #expect(text.contains("name: NSView.frameDidChangeNotification, object: rolle.contentView)"))
        #expect(text.contains("imBild = tabelle.selectedRowIndexes.count == 1 ? tabelle.selectedRow : nil"),
                "gemerkt nur bei genau einer, von Hand")
        #expect(text.contains("tabelle.selectedRowIndexes == IndexSet(integer: zeile) else { return }\n"
                              + "        tabelle.scrollRowToVisible(zeile)"), "gerollt nur, solange sie allein gewählt ist")
        // R8a-04: Rollt die Hand selbst, gilt die Zeile nicht mehr.
        #expect(text.contains("name: NSScrollView.willStartLiveScrollNotification, object: rolle)"))
        #expect(text.contains("@objc func selbstGerollt(_ meldung: Notification) {\n        imBild = nil"))
    }

    @Test("E1027: feste, gemessene Zeilenhöhe — AppKit vermisst die Zellen nicht nach jeder Auswahl neu")
    func festeZeilenhoehe() throws {
        let text = try Self.quelle("Oberflaeche/Huelltabelle.swift")
        #expect(text.contains("tabelle.usesAutomaticRowHeights = false"))
        // R8a-09: Zeilen im Wechsel wie `.bordered(alternatesRowBackgrounds: true)` zuvor.
        #expect(text.contains("tabelle.usesAlternatingRowBackgroundColors = true"))
        #expect(text.contains("wirt.sizingOptions = []"), "die Zellen ohne Auto Layout")
    }
}
