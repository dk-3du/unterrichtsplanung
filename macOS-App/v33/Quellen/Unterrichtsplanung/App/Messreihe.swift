// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Zählt, wie oft ein Ansichtskörper wirklich ausgewertet wird.
@MainActor
enum Messzaehler {
    static var werte: [String: Int] = [:]
    static var an = false
    static func zuruecksetzen() { werte.removeAll(); zeiten.removeAll() }

    static var zeiten: [String: Double] = [:]

    @inline(__always)
    static func messen<T>(_ was: String, _ arbeit: () -> T) -> T {
        guard an else { return arbeit() }
        let anfang = DispatchTime.now().uptimeNanoseconds
        let ergebnis = arbeit()
        zeiten[was, default: 0] += Double(DispatchTime.now().uptimeNanoseconds - anfang) / 1e6
        werte[was, default: 0] += 1
        return ergebnis
    }

    static func zeitbericht() -> String {
        zeiten.sorted { $0.value > $1.value }
            .map { String(format: "%@ %.1f ms (%dx)", $0.key, $0.value, werte[$0.key] ?? 0) }
            .joined(separator: ", ")
    }
    static func stand() -> String {
        werte.isEmpty ? "—"
            : werte.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
                .joined(separator: ", ")
    }
}

/// `--messreihe` — misst einzelne Handgriffe.
///
/// Gemessen wird die Rechenzeit des Hauptstrangs, nicht die Uhrzeit; dazu die
/// Zahl der ausgewerteten Ansichtskörper — sie sagt, warum eine Zahl hoch ist.
@MainActor
enum Messreihe {

    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        guard ProcessInfo.processInfo.arguments.contains("--messreihe") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("MESSREIHE") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard let planung = speicher.planung,
                  let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let klasse = planung.klassen.first,
                  !planung.eintraege.isEmpty, !planung.wochenListe.isEmpty else {
                print("MESSREIHE braucht eine Planung mit mindestens einer Klasse, "
                      + "einer Woche und einem Vorhaben")
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            speicher.sprung = Rastersprung(woche: 0)
            try? await Task.sleep(for: .milliseconds(800))

            let wochen = planung.wochenListe
            // Gemessen wird an den Vorhaben im sichtbaren Bereich; liegt dort
            // keines, an allen.
            let sichtbare = planung.eintraege.filter { $0.woche < 6 }
            let messbare = sichtbare.isEmpty ? planung.eintraege : sichtbare
            let einVorhaben = messbare[0]

            Messzaehler.an = true
            var zeilen: [String] = []

            @MainActor func messen(_ name: String, _ laeufe: Int,
                                   _ handgriff: @MainActor (Int) -> Void) async {
                // Einlaufen lassen, damit einmalige Kosten nicht mitzählen.
                handgriff(0)
                fenster.contentView?.layoutSubtreeIfNeeded()
                fenster.displayIfNeeded()
                try? await Task.sleep(for: .milliseconds(200))

                Messzaehler.zuruecksetzen()
                let vorher = rechenzeit()
                for lauf in 0..<laeufe {
                    handgriff(lauf + 1)
                    fenster.contentView?.layoutSubtreeIfNeeded()
                    fenster.displayIfNeeded()
                    try? await Task.sleep(for: .milliseconds(120))
                }
                let ms = (rechenzeit() - vorher) / Double(laeufe) * 1000
                let koerper = Messzaehler.werte.values.reduce(0, +) / max(1, laeufe)
                // Von Hand auffüllen: `%-26s` zählt Bytes, Umlaute verschöben die Spalten.
                let beschriftung = name.padding(toLength: max(name.count, 30),
                                                withPad: " ", startingAt: 0)
                zeilen.append(beschriftung + String(format: "%7.1f ms  %5d Körper  ", ms, koerper)
                              + Messzaehler.stand())
            }

            await messen("Zelle freischalten", 8) { lauf in
                speicher.zelleFreiSchalten(klasse: klasse.id,
                                           woche: wochen[lauf % wochen.count])
            }

            await messen("Kachel anwählen", 10) { lauf in
                let e = messbare[lauf % messbare.count]
                speicher.anwaehlen(vorhaben: e.id)
            }

            await messen("Zelle anwählen", 10) { lauf in
                speicher.anwaehlen(zelle: Zellenort(klasse: klasse.id,
                                                    woche: lauf % wochen.count))
            }

            await messen("Häkchen umschalten", 10) { _ in
                speicher.erledigtUmschalten(einVorhaben.id)
            }

            let wort = "Zellatmung"
            await messen("Suchfeld tippen (1 Zeichen)", wort.count) { lauf in
                speicher.suchbegriff = String(wort.prefix(max(1, lauf)))
            }
            speicher.suchbegriff = ""

            let breiteAnfang = speicher.spaltenbreite
            await messen("Spaltenbreite ändern", 4) { lauf in
                speicher.spaltenbreite = lauf % 2 == 0 ? 210 : 350
            }
            speicher.spaltenbreite = breiteAnfang

            await messen("Dialog auf und zu", 4) { lauf in
                speicher.offenerDialog = lauf % 2 == 0 ? .ferien : nil
            }
            speicher.offenerDialog = nil
            // Sonst wiese AppKit das Beenden unten ab, solange das Blatt noch
            // angeheftet ist — sonst hinge der Prüfstand mit fertigem Ergebnis.
            await Planungsspeicher.blaetterAbloesenAbwarten()

            Messzaehler.an = false
            print("MESSREIHE (Fenster \(Int(fenster.frame.width)) × \(Int(fenster.frame.height)), "
                  + "\(planung.klassen.count) Klassen/Kurse, \(planung.wochen) Wochen, "
                  + "\(planung.eintraege.count) Vorhaben)")
            print(zeilen.joined(separator: "\n"))
            print(String(format: "  Speicherabdruck            %6.0f MB", speicherAbdruck()))
            NSApp.terminate(nil)
        }
    }

    /// `--rastermasse` — was der Rollbereich wirklich für Maße hat.
    static func masseUndBeenden() {
        guard ProcessInfo.processInfo.arguments.contains("--rastermasse") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("RASTERMASSE") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }) else {
                print("RASTERMASSE kein Fenster"); NSApp.terminate(nil); return
            }
            var roller: NSScrollView?
            @MainActor func suchen(_ a: NSView) {
                if let r = a as? NSScrollView, r.documentView is NSCollectionView { roller = r }
                a.subviews.forEach(suchen)
            }
            if let inhalt = fenster.contentView { suchen(inhalt) }
            guard let roller, let dok = roller.documentView else {
                print("RASTERMASSE kein Sammelblatt gefunden"); NSApp.terminate(nil); return
            }
            print(String(format: "RASTERMASSE Roller %.0f x %.0f · Klemme %.0f x %.0f · Dokument %.0f x %.0f",
                         roller.frame.width, roller.frame.height,
                         roller.contentView.bounds.width, roller.contentView.bounds.height,
                         dok.frame.width, dok.frame.height))
            print("  Autogrösse Dokument: \(dok.autoresizingMask.rawValue)")
            print("  waagerechter Roller: \(roller.hasHorizontalScroller), sichtbar: \(roller.horizontalScroller?.isHidden == false)")
            if let sammelblatt = dok as? NSCollectionView {
                print(String(format: "  Anordnung meldet %.0f x %.0f",
                             sammelblatt.collectionViewLayout?.collectionViewContentSize.width ?? -1,
                             sammelblatt.collectionViewLayout?.collectionViewContentSize.height ?? -1))
            }
            let klemme = roller.contentView
            let wunsch = NSRect(x: 1200, y: 300, width: klemme.bounds.width,
                                height: klemme.bounds.height)
            let erlaubt = klemme.constrainBoundsRect(wunsch)
            print(String(format: "  Rollwunsch x=1200 y=300 → erlaubt x=%.0f y=%.0f  %@",
                         erlaubt.origin.x, erlaubt.origin.y,
                         erlaubt.origin.x >= 1200 ? "✓ waagerecht rollbar" : "✗ waagerecht GEKLEMMT"))
            klemme.scroll(to: NSPoint(x: 1200, y: 300))
            roller.reflectScrolledClipView(klemme)
            try? await Task.sleep(for: .milliseconds(300))
            var kopf: NSView?
            @MainActor func kopfSuchen(_ a: NSView) {
                if String(describing: type(of: a)).contains("NSHostingView"), a.frame.width > 5000 { kopf = a }
                a.subviews.forEach(kopfSuchen)
            }
            if let inhalt = fenster.contentView { kopfSuchen(inhalt) }
            print(String(format: "  Wochenkopfzeile steht bei x=%.0f (erwartet -1200)",
                         kopf?.frame.origin.x ?? .nan))

            var ueberfahrene = 0, sichtbare = 0
            @MainActor func zaehlen(_ a: NSView) {
                if let zelle = a as? Zellenkoerper {
                    sichtbare += 1
                    if zelle.ueberfahren { ueberfahrene += 1 }
                }
                a.subviews.forEach(zaehlen)
            }
            if let inhalt = fenster.contentView { zaehlen(inhalt) }
            print("  überfahrene Zellen: \(ueberfahrene) von \(sichtbare) sichtbaren "
                  + (ueberfahrene <= 1 ? "✓" : "✗ (mehr als eine!)"))
            NSApp.terminate(nil)
        }
    }

    static func rechenzeit() -> Double {
        var nutzung = rusage()
        guard getrusage(RUSAGE_SELF, &nutzung) == 0 else { return 0 }
        return Double(nutzung.ru_utime.tv_sec) + Double(nutzung.ru_utime.tv_usec) / 1e6
             + Double(nutzung.ru_stime.tv_sec) + Double(nutzung.ru_stime.tv_usec) / 1e6
    }

    static func speicherAbdruck() -> Double {
        var info = task_vm_info_data_t()
        var anzahl = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let ergebnis = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(anzahl)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &anzahl)
            }
        }
        guard ergebnis == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024 / 1024
    }
}
