// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI

/// Die Tour am echten Fenster: Anker, Karte, Tastatur, Neuaufbau.
@MainActor
enum Tourprobe {

    /// `--tourtest`: die Tour am echten Fenster — je Schritt Lage des Ankers
    /// und der Karte auf dem Bildschirm, dazu Abbilder von Fenster und Karte
    /// (`TOURBILD=<Pfadanfang>`; die Karte über `ImageRenderer`, weil ein
    /// Popover sich nicht abzeichnen lässt). Vorher die Einträge der
    /// Werkzeugleiste, wie SwiftUI sie AppKit meldet. Gedruckt wird sofort,
    /// damit ein Absturz nichts verschluckt. Braucht eine `planung.json` mit
    /// einer Zeile; versiegelt mit `ENTSPERRPROBE_PASSPHRASE` und Lernendendaten
    /// zeigt sie zehn Karten statt neun.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        let bildanfang = ProcessInfo.processInfo.environment["TOURBILD"]
        // Mit Passphrase: versiegelt mit Lernendendaten — zehn Karten statt neun (Z-GR2-01, Z-AX9N-01).
        let passphrase = ProcessInfo.processInfo.environment["ENTSPERRPROBE_PASSPHRASE"] ?? ""
        Task { @MainActor in
            var entsperrversuch = false
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                // Erst entsperren, dann kommt die Planung — ein Versuch (Z-AX9N-03).
                if !entsperrversuch, !passphrase.isEmpty, speicher.verschluesselungsstand == .gesperrt {
                    entsperrversuch = true
                    await speicher.entsperren(passphrase: passphrase)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  speicher.planung != nil else {
                print("TOURTEST ✗ kein Fenster / keine Planung"
                      + (passphrase.isEmpty ? "" : " — Verschlüsselung: \(speicher.verschluesselungsstand)"))
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            // 1250 Punkt: Bei dieser Breite kippte die Werkzeugleiste ohne die Behebung mit jeder Karte (H-AX9-06, E857) —
            // so ist die Zeile „Werkzeugleiste … gleich“ ein Wächter; `TOURBREITE` setzt eine andere.
            fenster.setContentSize(NSSize(width: Double(ProcessInfo.processInfo.environment["TOURBREITE"] ?? "") ?? 1250,
                                          height: 800))
            try? await Task.sleep(for: .milliseconds(900))

            @MainActor func sagen(_ zeile: String) {
                print(zeile)
                fflush(stdout)
            }
            sagen("TOURTEST")
            if !passphrase.isEmpty {
                sagen("  Entsperrt mit der Passphrase der Saat" + (speicher.verschluesselungsstand == .an ? " ✓" : " ✗"))
            }
            sagen(String(format: "Fenster %.0f,%.0f %.0f×%.0f", fenster.frame.minX,
                         fenster.frame.minY, fenster.frame.width, fenster.frame.height))
            sagen("Werkzeugleiste (\(fenster.toolbar?.items.count ?? 0) Einträge):")
            for eintrag in fenster.toolbar?.items ?? [] {
                let ansicht = eintrag.view
                let lage = ansicht.map { $0.convert($0.bounds, to: nil) } ?? .zero
                sagen("  „\(eintrag.label)“ · \(eintrag.toolTip ?? "—") · "
                      + (ansicht.map { "\(type(of: $0))" } ?? "ohne NSView")
                      + String(format: " %.0f,%.0f %.0f×%.0f", lage.minX, lage.minY,
                               lage.width, lage.height))
            }

            @MainActor func abbild(_ name: String) {
                guard let bildanfang else { return }
                Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: bildanfang + "-" + name + ".png"))
                let zeichner = ImageRenderer(content: Tourkarte().environment(speicher))
                zeichner.scale = 2
                if let bild = zeichner.cgImage {
                    let abzug = NSBitmapImageRep(cgImage: bild)
                    let ort = URL(fileURLWithPath: bildanfang + "-" + name + "-karte.png")
                    try? abzug.representation(using: .png, properties: [:])?.write(to: ort)
                }
            }
            var gezeigt = Set<Planungsspeicher.Tourschritt>()
            var kopfanker: NSRect?
            var leisten: [[String]] = []
            var kartenMitSchluessel = 0
            @MainActor func festhalten(_ was: String) async {
                try? await Task.sleep(for: .milliseconds(900))
                guard let schritt = speicher.tourSchritt else {
                    sagen("  \(was): Tour steht nicht ✗")
                    return
                }
                let lage = Tourfuehrer.shared.letzteLage
                let karte = Tourfuehrer.shared.kartenfenster
                let stelle = speicher.tourStelle
                sagen("  \(was): \(schritt.rawValue) (\(stelle.stelle) von \(stelle.zahl))"
                      + " · Zelle „\(speicher.tourZelle)“")
                gezeigt.insert(schritt)
                // Die Lage der Werkzeugleiste je Aufnahme (H-AX9-06): kippt sie, wechselt das Rechteck eines Eintrags
                // (Z-AX9T3-02: ganz, auch senkrecht); die Zahl der Einträge und die sichtbaren vorn, damit auch ein Eintrag
                // ohne eigene Ansicht oder im Überlaufmenü zählt (Z-AX9T3N-02).
                let sichtbar = (fenster.toolbar?.visibleItems ?? []).map(\.itemIdentifier.rawValue)
                let leiste = ["\(fenster.toolbar?.items.count ?? 0) Einträge, sichtbar: \(sichtbar.joined(separator: ","))"]
                    + (fenster.toolbar?.items ?? []).compactMap { e in
                        // Das Suchfeld hat als `NSSearchToolbarItem` keine eigene `view` — es zählt über sein Feld.
                        ((e as? NSSearchToolbarItem)?.searchField ?? e.view).map { v in
                            let r = v.convert(v.bounds, to: nil)
                            return String(format: "%@ %.0f,%.0f %.0f×%.0f", e.label.isEmpty ? "?" : e.label, r.minX, r.minY,
                                          r.width, r.height)
                        }
                    }
                leisten.append(leiste)
                // Wer den Schlüssel hat — die Karte, das Hauptfenster oder keines von beiden (Z-AX9T3-03); dazu die Art des
                // Schlüsselfensters der App.
                let schluessel = fenster.isKeyWindow ? "Hauptfenster"
                    : Tourfuehrer.shared.kartenfenster?.isKeyWindow == true ? "Karte" : "keines von beiden"
                if schluessel == "Karte" { kartenMitSchluessel += 1 }
                sagen("    Leiste: " + leiste.joined(separator: " · ") + " · Schlüsselfenster: " + schluessel
                      + " (\(NSApp.keyWindow.map { "\(type(of: $0))" } ?? "—"))")
                // Die Karten an der Kurszelle hängen am Klassenkopf, nicht an der Beispielzelle (Z-GR2-01).
                if schritt.rasterstelle == .klassenkopf {
                    var amKopf = !speicher.tourZelle.isEmpty && !speicher.tourZelle.contains(", KW")
                        && lage?.schritt == schritt
                    // „Lernende“ an derselben Stelle wie die Kurszelle — nicht am Ersatzanker (Z-AX9N-02).
                    if schritt == .kurszelle {
                        // Die Mitte des Ankers im Inhalt des Fensters, unter der Werkzeugleiste — sonst hinge die Karte
                        // am Ersatzanker (Z-AX9M-03). Der Anker liegt auf dem Bildschirm, der Inhalt im Fenster.
                        let inhalt = fenster.convertToScreen(fenster.contentLayoutRect)
                        amKopf = amKopf
                            && (lage.map { inhalt.contains(NSPoint(x: $0.anker.midX, y: $0.anker.midY)) } ?? false)
                        // Nur ein Anker, der selbst bestand, ist der Maßstab für „Lernende“ (Z-AX9M-03).
                        if amKopf { kopfanker = lage?.anker }
                    } else {
                        amKopf = amKopf && kopfanker != nil && lage?.anker.integral == kopfanker?.integral
                    }
                    sagen("    am Klassenkopf „\(speicher.tourZelle)“" + (amKopf ? " ✓" : " ✗"))
                }
                if let lage, lage.schritt == schritt {
                    sagen(String(format: "    Anker %.0f,%.0f %.0f×%.0f", lage.anker.minX,
                                 lage.anker.minY, lage.anker.width, lage.anker.height))
                } else {
                    sagen("    kein Anker ✗")
                }
                if let karte, karte.isVisible {
                    let r = karte.frame
                    let ok = lage.map { r.insetBy(dx: -40, dy: -40).intersects($0.anker) } ?? false
                    sagen(String(format: "    Karte %.0f,%.0f %.0f×%.0f", r.minX, r.minY,
                                 r.width, r.height) + (ok ? " · am Anker ✓" : " · fern vom Anker ✗"))
                } else {
                    sagen("    keine Karte ✗")
                }
                abbild(schritt.rawValue)
            }

            // Die Spur zu H-AX9-06 (E857): wann die Leiste neu ausgelegt wird — jede Änderung der Breite des Suchfelds,
            // dazwischen Popover und Kartenwechsel (Z-AX9R6-03). Nur Beobachter, keine Wartezeit.
            let spur = Tourspur(fenster)
            spur.merken("Beginn der Tour")
            speicher.tourBeginnen()
            await festhalten("Start")
            // Zwischen den Karten zählt (Z-AX9R3-02): Beginn und Ende der Tour geben den Schlüssel ab und zurück.
            let wechselNachDemStart = spur.wechsel
            var wechselVorDemEnde: Int?
            spur.merken("Weiter")
            speicher.tourWeiter()
            await festhalten("Weiter")
            spur.merken("Zurück")
            speicher.tourZurueck()
            await festhalten("Zurück")
            var runden = 0
            // Bis zu zehn Karten (E842) — mit Spielraum.
            while speicher.tourSchritt != nil, runden < 12 {
                if speicher.tourAmEnde { wechselVorDemEnde = spur.wechsel }
                spur.merken("Weiter")
                speicher.tourWeiter()
                runden += 1
                if speicher.tourSchritt != nil { await festhalten("Weiter") }
            }
            // Zehn Karten mit Lernendenverwaltung, neun ohne (E842, Z-GR3-05).
            let sollKarten = passphrase.isEmpty ? 9 : 10  // von außen, nicht aus der Bedingung der Tour (Z-AX9N-01)
            sagen("  Karten: \(gezeigt.count) gezeigt, \(sollKarten) erwartet (E842)"
                  + (gezeigt.count == sollKarten ? " ✓" : " ✗"))
            if !passphrase.isEmpty {
                sagen("  Karte „Lernende“ gezeigt" + (gezeigt.contains(.lernende) ? " ✓" : " ✗"))
            }
            // Die Leiste bleibt beim Wechsel der Karten stehen (H-AX9-06).
            // Nur eine gemessene Leiste zählt (Z-AX9T3-02); gezählt werden Aufnahmen, nicht Karten (Z-AX9T3-03).
            let lagen = Set(leisten.map { $0.joined(separator: " · ") })
            let gemessen = !leisten.isEmpty && leisten.allSatisfy { $0.count > 1 }  // vorn steht die Zahl der Einträge
            sagen("  Werkzeugleiste bei allen \(leisten.count) Aufnahmen gleich"
                  + (gemessen && lagen.count == 1 ? " ✓" : gemessen ? " ✗ (\(lagen.count) Lagen)" : " ✗ (nicht gemessen)"))
            try? await Task.sleep(for: .milliseconds(500))
            let offen = Tourfuehrer.shared.kartenfenster?.isVisible ?? false
            sagen("  Ende: Tour \(speicher.tourSchritt == nil ? "beendet ✓" : "läuft noch ✗")"
                  + ", Karte \(offen ? "steht noch ✗" : "weg ✓")"
                  + ", Meldung „\(speicher.meldungen.last?.text ?? "—")“")
            // Die Spur (E857): Breitenwechsel des Suchfelds zwischen den Karten — ohne die Behebung kippte es bei 1250 Punkt mit
            // jeder; Beginn und Ende nur als Auskunft. Die Schärfe hängt an der Leiste dieses Stands (Z-AX9R3-02).
            if spur.feldGefunden {
                let zwischen = (wechselVorDemEnde ?? spur.wechsel) - wechselNachDemStart
                sagen("  Suchfeld zwischen den Karten: \(zwischen) Breitenwechsel" + (zwischen == 0 ? " ✓" : " ✗")
                      + " (Beginn und Ende: \(spur.wechsel - zwischen))")
            } else {
                sagen("  Suchfeld nicht gefunden ✗")  // Z-AX9R3-03
            }
            // Nur Auskunft (Z-AX9R3-01, Z-AX9R4-01): Beurteilt werden Schlüssel und Leiste unten im Tastaturteil, über mehrere
            // Karten mit ⏎ — wie in der Handprobe D.
            sagen("  Karte bei \(kartenMitSchluessel) von \(leisten.count) Aufnahmen Schlüsselfenster (Auskunft)")

            // Tastatur an der Karte: ⏎ geht weiter, ⎋ beendet — und ein
            // Neuaufbau des Rasters (Spaltenbreite) lässt die Karte nicht hängen.
            @MainActor func taste(_ zeichen: String, code: UInt16, marke: String? = nil) {
                guard let karte = Tourfuehrer.shared.kartenfenster else {
                    if let marke { spur.merken(marke + " (keine Karte)") }
                    return
                }
                // Die Marke nur, wenn eine Karte da ist, an die die Taste geschickt wird (Z-AX9R7-01) — ohne Schlüssel mit
                // Vermerk, denn ob sie dann ankommt, ist offen (Z-AX9R8-01).
                if let marke { spur.merken(marke + (karte.isKeyWindow ? "" : " (Karte ohne Schlüssel)")) }
                for art in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let ereignis = NSEvent.keyEvent(
                        with: art, location: .zero, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: karte.windowNumber, context: nil,
                        characters: zeichen, charactersIgnoringModifiers: zeichen,
                        isARepeat: false, keyCode: code) else { continue }
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }
            try? await Task.sleep(for: .milliseconds(600))
            speicher.tourBeginnen()
            try? await Task.sleep(for: .milliseconds(900))
            let schluessel = Tourfuehrer.shared.kartenfenster?.isKeyWindow ?? false
            // Ab hier bis nach dem letzten ⏎ zählt die Spur: Ginge in `zeigen` die alte Karte vor dem Zeigen der neuen zu, kippte
            // die Leiste bei 1250 Punkt mit jedem Wechsel — so ist die Reihenfolge belegt, nicht nur der Endzustand
            // (Z-AX9R4-01; Gegenprobe: 10 Breitenwechsel).
            let wechselVorTastatur = spur.wechsel
            taste("\r", code: 36, marke: "⏎")
            try? await Task.sleep(for: .milliseconds(700))
            sagen("  Tastatur: Karte \(schluessel ? "ist" : "ist nicht") Schlüsselfenster; "
                  + "⏎ → \(speicher.tourSchritt?.rawValue ?? "—")"
                  + (schluessel && speicher.tourSchritt == .woche ? " ✓" : " ✗"))  // mit dem Schlüssel (Z-AX9R4-02)
            // Zwei weitere Karten mit ⏎ (H-AX9-06, Z-AX9R3-01): Die Karte dieses Schritts steht und hat den Schlüssel; ⏎ schaltet
            // genau einen Schritt weiter, auf eine neue Karte mit Schlüssel (Z-AX9R4-02). Gewartet wird begrenzt darauf.
            @MainActor func karteSteht(_ schritt: Planungsspeicher.Tourschritt?, nicht alte: NSWindow?) -> Bool {
                let karte = Tourfuehrer.shared.kartenfenster
                return karte != nil && karte !== alte && karte?.isKeyWindow == true
                    && Tourfuehrer.shared.letzteLage?.schritt == schritt
            }
            for _ in 0..<2 {
                guard let vorher = speicher.tourSchritt else { break }
                for _ in 0..<20 where !karteSteht(vorher, nicht: nil) { try? await Task.sleep(for: .milliseconds(50)) }
                let hatSchluessel = karteSteht(vorher, nicht: nil)
                let voriges = Tourfuehrer.shared.kartenfenster
                let vorigeStelle = speicher.tourStelle.stelle
                taste("\r", code: 36, marke: "⏎")
                for _ in 0..<20 where !karteSteht(speicher.tourSchritt, nicht: voriges) {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                let weiter = speicher.tourStelle.stelle == vorigeStelle + 1 && karteSteht(speicher.tourSchritt, nicht: voriges)
                // „steht mit Schlüssel“: Karte des Schritts, Anker und Schlüssel zusammen (Z-AX9R5-05).
                sagen("  Tastatur: Karte „\(vorher.rawValue)“ \(hatSchluessel ? "steht mit" : "steht nicht mit") Schlüssel; "
                      + "⏎ → \(speicher.tourSchritt?.rawValue ?? "—")" + (hatSchluessel && weiter ? " ✓" : " ✗"))
            }
            // Ohne eigene Wartezeit (Z-AX9R5-04): Die Wechsel der beiden ersten Karten liegen vor weiteren Wartestellen.
            let tastWechsel = spur.wechsel - wechselVorTastatur
            sagen("  Tastatur: zwischen den Karten \(tastWechsel) Breitenwechsel des Suchfelds"
                  + (spur.feldGefunden && tastWechsel == 0 ? " ✓" : " ✗"))
            spur.beenden()
            // Bei ✗ die Spur, damit die Folge der Vorgänge sichtbar ist (Z-AX9R5-01).
            if !spur.feldGefunden || tastWechsel != 0 {
                for zeile in spur.zeilen.suffix(24) { sagen("    Spur " + zeile) }
            }
            // Bis zum letzten Schritt (mit Zeile: die Karte an der Kurszelle, E842).
            var bisZumEnde = 0
            while speicher.tourLaeuft, !speicher.tourAmEnde, bisZumEnde < 12 {  // mit Obergrenze (Z-GR3-05)
                speicher.tourWeiter()
                bisZumEnde += 1
            }
            try? await Task.sleep(for: .milliseconds(900))
            let vorher = Tourfuehrer.shared.kartenfenster
            speicher.spaltenbreite += Kennwerte.spalteRaster
            try? await Task.sleep(for: .milliseconds(1200))
            let nachher = Tourfuehrer.shared.kartenfenster
            sagen("  Neuaufbau bei Schritt \(speicher.tourSchritt?.rawValue ?? "—"): Karte "
                  + ((nachher?.isVisible ?? false) ? "steht" : "fehlt ✗")
                  + (vorher !== nachher ? " (neu angehängt)" : " (dieselbe)")
                  + ((nachher?.isKeyWindow ?? false) ? ", Schlüsselfenster" : ", nicht Schlüsselfenster"))
            speicher.spaltenbreite -= Kennwerte.spalteRaster
            try? await Task.sleep(for: .milliseconds(900))
            taste("\u{1B}", code: 53)
            try? await Task.sleep(for: .milliseconds(700))
            sagen("  ⎋ → Tour \(speicher.tourSchritt == nil ? "beendet ✓" : "läuft noch ✗")")
            if speicher.tourLaeuft, let karte = Tourfuehrer.shared.kartenfenster {
                // Wie ein Klick in die Karte.
                karte.makeKey()
                taste("\u{1B}", code: 53)
                try? await Task.sleep(for: .milliseconds(700))
                sagen("  ⎋ nach Klick in die Karte → Tour "
                      + "\(speicher.tourSchritt == nil ? "beendet ✓" : "läuft noch ✗")")
            }
            await Pruefstaende.abschliessenUndBeenden(speicher)
        }
    }
}

/// Die Spur zu H-AX9-06 (E857): Änderungen der Breite des Suchfelds der Werkzeugleiste mit Zeitstempel und den Vorgängen
/// dazwischen — Kartenwechsel (von der Probe gemerkt), Popover. Nur Beobachter. (Beobachter auf den Schlüssel meldeten hier
/// nie etwas, auch wenn die Karte nachweislich Schlüssel wurde — darum keine; Z-AX9R5-01.)
@MainActor
final class Tourspur {
    private(set) var zeilen: [String] = []
    private let beginn = Date()
    private weak var feld: NSSearchField?
    private var breite: CGFloat?
    private var beobachter: [NSObjectProtocol] = []

    init(_ fenster: NSWindow) {
        feld = fenster.toolbar?.items.compactMap { ($0 as? NSSearchToolbarItem)?.searchField }.first
        feld?.postsFrameChangedNotifications = true
        breite = feld?.frame.width
        merken(String(format: "Suchfeld anfangs %.0f", breite ?? 0))
        let zentrale = NotificationCenter.default
        // Ohne Feld kein Beobachter — mit `object: nil` hörte er auf jede Ansicht der App (Z-AX9R3-03).
        if let feld {
            beobachter.append(zentrale.addObserver(forName: NSView.frameDidChangeNotification, object: feld, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.feldGeaendert() }
            })
        }
        for (name, text) in [(NSPopover.didShowNotification, "Popover gezeigt"), (NSPopover.didCloseNotification, "Popover zu")] {
            beobachter.append(zentrale.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.merken(text) }
            })
        }
    }

    func merken(_ vorgang: String) {
        zeilen.append(String(format: "%6.0f ms  ", Date().timeIntervalSince(beginn) * 1000) + vorgang)
    }

    func beenden() {
        beobachter.forEach(NotificationCenter.default.removeObserver)
        beobachter = []
    }

    /// Wie oft sich die Breite des Suchfelds änderte (je Bild einer Animation einmal).
    private(set) var wechsel = 0
    var feldGefunden: Bool { feld != nil }

    private func feldGeaendert() {
        guard let neu = feld?.frame.width, neu != breite else { return }
        merken(String(format: "Suchfeld %.0f → %.0f", breite ?? 0, neu))
        breite = neu
        wechsel += 1
    }
}
