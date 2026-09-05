// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import LocalAuthentication
import Foundation
import SwiftUI

/// Die Schranke vor den Prüfständen.
///
/// Ohne `PLANUNGSORDNER` liefe jeder Prüfstand gegen die echte Planung:
/// `--klicktest`, `--messreihe`, `--menuetest`, `--dauertest` und `--ziehtest`
/// änderten sie, die lesenden Stände (`--abbild`, `--rolltest`,
/// `--rastermasse`, `--auswahltest`, `--mischtest`, `--titeltest`,
/// `--entsperrtest`, `--tourtest`) bildeten sie ungefragt ab. Darum stehen alle
/// hinter derselben Schranke.
@MainActor
enum Pruefstandsschranke {
    static func eigenerOrdnerVerlangt(_ name: String) -> Bool {
        guard Ablage.istPruefstand else {
            print("\(name) abgebrochen: PLANUNGSORDNER ist nicht gesetzt. Prüfstände "
                  + "laufen nur gegen eine eigene Ablage, nie gegen die echte Planung.")
            NSApp.terminate(nil)
            return false
        }
        return true
    }
}

/// `--abbild <datei.png>`: startet, wartet auf das Fenster, legt es als PNG ab
/// und beendet sich. Liquid Glass zeichnet das Fenstersystem — abseits des
/// Bildschirms gezeichnete Ansichten zeigen davon nichts.
@MainActor
enum Selbstabbild {

    static var angefordert: URL? {
        let teile = ProcessInfo.processInfo.arguments
        guard let stelle = teile.firstIndex(of: "--abbild"), stelle + 1 < teile.count else {
            return nil
        }
        return URL(fileURLWithPath: teile[stelle + 1])
    }

    /// Mit `--dialog <name>` wird vorher der genannte Dialog abgebildet.
    static func ablegenUndBeenden(_ speicher: Planungsspeicher,
                                  nach wartezeit: TimeInterval = 2.0) {
        guard let ziel = angefordert,
              !ProcessInfo.processInfo.arguments.contains("--mischtest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("ABBILD") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(wartezeit))
            let teile = ProcessInfo.processInfo.arguments
            if let stelle = teile.firstIndex(of: "--dialog"), stelle + 1 < teile.count {
                let name = teile[stelle + 1]
                if name == "ueber" {
                    // Eigenes Fenster, kein Blatt — deshalb das Schlüsselfenster.
                    Ueber.zeigen()
                    try? await Task.sleep(for: .milliseconds(1200))
                    if let fenster = NSApp.keyWindow ?? NSApp.windows.last(where: \.isVisible) {
                        ablegen(fenster, nach: ziel)
                    }
                    await blaetterSchliessenUndBeenden(speicher)
                    return
                }
                if name == "vorhaben" {
                    let mitLink = speicher.planung?.eintraege.first { !$0.links.isEmpty }
                    if let mitLink { speicher.vorhabenOeffnen(id: mitLink.id) }
                } else if let welcher = Dialogfenster(rawValue: name) {
                    if welcher == .ersteinrichtung { ersteinrichtungVorbereiten(speicher) }
                    speicher.offenerDialog = welcher
                }
                try? await Task.sleep(for: .milliseconds(1800))
            }
            if teile.contains("--auswahl"), let eintraege = speicher.planung?.eintraege {
                for (stelle, eintrag) in eintraege.prefix(30).enumerated()
                where stelle % 27 == 0 || stelle == 1 {
                    speicher.anwaehlen(vorhaben: eintrag.id, erweitern: stelle > 0)
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
            if let fenster = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                ablegen(fenster.attachedSheet ?? fenster, nach: ziel)
            }
            await blaetterSchliessenUndBeenden(speicher)
        }
    }

    /// `--dialog ersteinrichtung` mit `ABBILD_SCHRITT=frage|passphrase|blatt|
    /// sicherung`: die Station der Ersteinrichtung (in Schritten),
    /// bevor das Blatt aufgeht. Die Passphrase ist ein Wegwerfwert.
    private static func ersteinrichtungVorbereiten(_ speicher: Planungsspeicher) {
        switch ProcessInfo.processInfo.environment["ABBILD_SCHRITT"] ?? "frage" {
        case "passphrase":
            speicher.ersteinrichtungEinrichten()
        case "blatt":
            speicher.ersteinrichtungEinrichten()
            try? speicher.ersteinrichtungWeiter(passphrase: "Ein Satz, den man behält")
        case "sicherung":
            speicher.ersteinrichtungUeberspringen()
        default:
            break
        }
    }

    /// Ein angeheftetes Blatt lässt AppKit `terminate` abweisen, noch bevor
    /// der Delegat gefragt wird. Ohne diese Stelle bliebe der Prüfstand nach
    /// `--dialog …` mit fertigen Abbildern stehen. Also erst die
    /// Blätter schließen, das Ablösen abwarten, dann gehen.
    private static func blaetterSchliessenUndBeenden(_ speicher: Planungsspeicher) async {
        speicher.alleDialogeSchliessen()
        await Planungsspeicher.blaetterAbloesenAbwarten()
        NSApp.terminate(nil)
    }

    /// `--rolltest`: rollt das Raster über eine wiederkehrende Uhr und meldet
    /// die Zeit je Bild.
    static func rolltestUndBeenden() {
        guard ProcessInfo.processInfo.arguments.contains("--rolltest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("ROLLTEST") else { return }
        Messzaehler.an = ProcessInfo.processInfo.arguments.contains("--zerlegen")
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
        guard ProcessInfo.processInfo.arguments.contains("--klicktest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("KLICKTEST") else { return }
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
            NSApp.terminate(nil)
        }
    }

    /// `--auswahltest`: klickt wirklich ins Raster, auch mit ⌘ und ⇧ — ob eine
    /// Geste beim richtigen Empfänger ankommt, zeigt nur ein echtes Ereignis.
    static func auswahltestUndBeenden(_ speicher: Planungsspeicher) {
        guard ProcessInfo.processInfo.arguments.contains("--auswahltest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("AUSWAHLTEST") else { return }
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
        guard ProcessInfo.processInfo.arguments.contains("--ziehtest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("ZIEHTEST") else { return }
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
                ablegen(fenster, nach: URL(fileURLWithPath: pfad))
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
        guard ProcessInfo.processInfo.arguments.contains("--mischtest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("MISCHTEST") else { return }
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
                ablegen(fenster, nach: URL(fileURLWithPath: pfad))
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
        guard ProcessInfo.processInfo.arguments.contains("--titeltest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("TITELTEST") else { return }
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

    /// `--entsperrtest passphrase|wiederherstellung|gemischt|enklave|tot`: das
    /// Freigabeblatt am echten Fenster, so wie VoiceOver es sieht — haben die
    /// Felder eine Breite, schaltet Tippen den Knopf frei, entsperrt ⏎? Braucht
    /// eine versiegelte `planung.json` im PLANUNGSORDNER; Passphrase und
    /// Schlüssel kommen aus `ENTSPERRPROBE_PASSPHRASE` und
    /// `ENTSPERRPROBE_SCHLUESSEL`, Abbilder je Schritt nach `ENTSPERRBILD`
    /// (Pfadanfang), die ganze Elementliste mit `ENTSPERRPROBE_ALLES`.
    /// `ENTSPERRPROBE_MERKEN=0|1` schaltet das Häkchen „Mit Touch ID öffnen“;
    /// mit `ENTSPERRPROBE_ENKLAVE=1` zählt die Enklave auch im Prüfstand:
    /// `enklave` erwartet zuerst die Systemabfrage ohne Blatt, bricht sie ab
    /// und will dann das Blatt; `tot` tippt wie `passphrase`, meldet aber den
    /// Hinweis auf die unbrauchbare Wicklung. Am Ende immer der Kopf der Ablage.
    static func entsperrtestUndBeenden(_ speicher: Planungsspeicher) {
        let teile = ProcessInfo.processInfo.arguments
        guard let stelle = teile.firstIndex(of: "--entsperrtest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("ENTSPERRTEST") else { return }
        let weg = stelle + 1 < teile.count ? teile[stelle + 1] : "passphrase"
        let umgebung = ProcessInfo.processInfo.environment
        let passphrase = umgebung["ENTSPERRPROBE_PASSPHRASE"] ?? ""
        let schluessel = umgebung["ENTSPERRPROBE_SCHLUESSEL"] ?? ""
        let bildanfang = umgebung["ENTSPERRBILD"]
        let alles = umgebung["ENTSPERRPROBE_ALLES"] != nil
        let merken = umgebung["ENTSPERRPROBE_MERKEN"]
        Task { @MainActor in
            var zeilen = ["ENTSPERRTEST (\(weg))"]
            @MainActor func sichtbaresFenster() -> NSWindow? { NSApp.windows.first { $0.isVisible } }
            let blobVorher = speicher.gesperrterKopf?.wicklung(Wicklung.enklave)?.daten("geraet")
            if weg == "enklave" {
                // Wie bei Numbers: Die Systemabfrage steht allein, kein Blatt dabei.
                for _ in 0..<20 where !speicher.entsperrungLaeuft {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                try? await Task.sleep(for: .milliseconds(1200))
                zeilen.append("  Systemabfrage läuft: \(speicher.entsperrungLaeuft ? "ja ✓" : "nein ✗")"
                              + ", Blatt dabei: \(sichtbaresFenster()?.attachedSheet == nil ? "keins ✓" : "JA ✗")"
                              + ", Dialog \(speicher.offenerDialog?.rawValue ?? "—")")
                if let bildanfang, let fenster = sichtbaresFenster() {
                    ablegen(fenster, nach: URL(fileURLWithPath: bildanfang + "-leerzustand.png"))
                }
                speicher.freigabeAbbrechen()
                zeilen.append("  Abfrage abgebrochen (invalidate) — jetzt soll das Blatt kommen")
            }
            for _ in 0..<40 where sichtbaresFenster()?.attachedSheet == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = sichtbaresFenster(), let blatt = fenster.attachedSheet else {
                zeilen.append("  kein Blatt ✗ — Stand \(speicher.verschluesselungsstand), "
                              + "Dialog \(speicher.offenerDialog?.rawValue ?? "—")")
                print(zeilen.joined(separator: "\n"))
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            blatt.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(800))
            zeilen.append("  Blatt da — Hinweis „Schlüssel passt nicht“: "
                          + (speicher.enklaveWicklungPasstNicht ? "ja" : "nein")
                          + (speicher.entsperrungFehler.map { " — „\($0)“" } ?? "")
                          + "; Häkchen vorgegeben: \(speicher.enklaveMerken ? "an" : "aus")")
            if let merken {
                speicher.enklaveMerken = merken == "1"
                zeilen.append("  Häkchen „Mit Touch ID öffnen“ gesetzt: \(speicher.enklaveMerken ? "an" : "aus")")
            }
            @MainActor func wicklungsbericht() async {
                guard let roh = try? Data(contentsOf: Ablage.shared.datei),
                      let kopf = try? Tresor.kopfLesen(roh) else {
                    zeilen.append("  Kopf der Ablage nicht lesbar ✗")
                    return
                }
                zeilen.append("  Wicklungen auf der Platte: "
                              + kopf.wicklungen.map(\.art).sorted().joined(separator: ", "))
                guard let w = kopf.wicklung(Wicklung.enklave) else { return }
                let blob = w.daten("geraet") ?? Data()
                zeilen.append("  Blob dieses Macs: \(blob.prefix(6).hex)… — "
                              + (blobVorher == nil ? "neu angelegt" : blob == blobVorher ? "unverändert" : "ersetzt"))
                let befund: String = await Task.detached {
                    let kontext = LAContext()
                    kontext.interactionNotAllowed = true
                    do {
                        _ = try Tresor.oeffnen(kopf: kopf, enklave: kontext)
                        return "öffnete OHNE Freigabe ✗"
                    } catch {
                        return "verlangt Freigabe ✓ („\((error as? Tresorfehler)?.text ?? "\(error)")“)"
                    }
                }.value
                zeilen.append("  Enklaven-Wicklung \(befund)")
            }

            // Erst die Ansichten (SwiftUI legt seine Textfelder als NSTextField an),
            // dann, was die Bedienungshilfen darunter noch kennen.
            @MainActor func elemente() -> [NSAccessibilityProtocol] {
                var liste: [NSAccessibilityProtocol] = []
                @MainActor func sammeln(_ element: Any, _ tiefe: Int) {
                    guard tiefe < 40, let e = element as? NSAccessibilityProtocol else { return }
                    liste.append(e)
                    if let ansicht = e as? NSView {
                        for kind in ansicht.subviews { sammeln(kind, tiefe + 1) }
                    }
                    for kind in e.accessibilityChildren() ?? [] where !(kind is NSView) {
                        sammeln(kind, tiefe + 1)
                    }
                }
                if let inhalt = blatt.contentView { sammeln(inhalt, 0) }
                return liste
            }
            @MainActor func name(_ e: NSAccessibilityProtocol) -> String {
                let titel = e.accessibilityTitle() ?? ""
                if !titel.isEmpty { return titel }
                let beschriftung = e.accessibilityLabel() ?? ""
                if !beschriftung.isEmpty { return beschriftung }
                return (e.accessibilityValue() as? String) ?? ""
            }
            @MainActor func knopf(_ anfang: String) -> NSAccessibilityProtocol? {
                elemente().first { $0.accessibilityRole() == .button && name($0).hasPrefix(anfang) }
            }
            @MainActor func felder() -> [NSTextField] {
                elemente().compactMap { $0 as? NSTextField }.filter(\.isEditable)
            }
            @MainActor func feldzeile(_ feld: NSTextField) -> String {
                let r = feld.frame
                return (feld is NSSecureTextField ? "Passphrase-Feld" : "Textfeld")
                    + " \(Int(r.width)) × \(Int(r.height)) Punkte"
                    + (feld.placeholderString.map { " · Platzhalter „\($0)“" } ?? "")
                    + (r.width < 200 ? "  ✗ zu schmal" : "  ✓")
            }
            @MainActor func knopfzustand(_ titel: String) -> String {
                guard let k = knopf(titel) else { return "„\(titel)“ NICHT GEFUNDEN ✗" }
                return "„\(titel)“ \(k.isAccessibilityEnabled() ? "aktiv" : "grau")"
            }
            @MainActor func taste(_ zeichen: String, code: UInt16 = 0,
                                  _ tasten: NSEvent.ModifierFlags = []) {
                for art in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let ereignis = NSEvent.keyEvent(
                        with: art, location: .zero, modifierFlags: tasten,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: blatt.windowNumber, context: nil,
                        characters: zeichen, charactersIgnoringModifiers: zeichen,
                        isARepeat: false, keyCode: code) else { continue }
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }
            @MainActor func tippen(_ feld: NSTextField, _ text: String) async {
                blatt.makeFirstResponder(feld)
                try? await Task.sleep(for: .milliseconds(200))
                taste("a", code: 0, [.command])
                for zeichen in text { taste(String(zeichen)) }
                try? await Task.sleep(for: .milliseconds(400))
            }
            @MainActor func abschicken(_ was: String) async -> Bool {
                let fehlerVorher = speicher.entsperrungFehler
                taste("\r", code: 36)
                for _ in 0..<16 where speicher.verschluesselungsstand != .an
                    && speicher.entsperrungFehler == fehlerVorher {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                let offen = speicher.verschluesselungsstand == .an
                zeilen.append("  ⏎ \(was): "
                              + (offen ? "entsperrt ✓"
                                 : "noch gesperrt" + (speicher.entsperrungFehler.map { " — „\($0)“" } ?? "")))
                return offen
            }
            @MainActor func abbild(_ name: String) async {
                guard let bildanfang else { return }
                // Das Blatt wächst um den Fehlerabschnitt; früher ist das Bild weiß.
                try? await Task.sleep(for: .milliseconds(900))
                ablegen(blatt, nach: URL(fileURLWithPath: bildanfang + "-" + name + ".png"))
            }
            @MainActor func bestand(_ schritt: String) {
                zeilen.append("  \(schritt):")
                let liste = felder()
                for feld in liste { zeilen.append("    " + feldzeile(feld)) }
                if liste.isEmpty { zeilen.append("    kein beschreibbares Feld ✗") }
                zeilen.append("    " + knopfzustand("Entsperren"))
                zeilen.append("    " + (knopf("Stattdessen").map { "„\(name($0))“ da" }
                                        ?? "kein „Stattdessen“-Knopf"))
                if alles {
                    for e in elemente() {
                        let rolle = e.accessibilityRole()?.rawValue ?? "?"
                        let r = e.accessibilityFrame()
                        zeilen.append("      \(type(of: e)) \(rolle) „\(name(e).prefix(60))“ "
                                      + "\(Int(r.width))×\(Int(r.height))")
                    }
                }
            }
            // SwiftUI-Knöpfe sind für den eigenen Prozess unsichtbar: Umschalten
            // per Klick auf einen ausgemessenen Punkt (`ENTSPERRPROBE_KLICK=x,y`,
            // Punkte von links oben im Blatt), sonst über den Speicher.
            @MainActor func umschalten() async {
                let klick = umgebung["ENTSPERRPROBE_KLICK"]?.split(separator: ",")
                    .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? []
                if klick.count == 2, let inhalt = blatt.contentView {
                    let punkt = NSPoint(x: klick[0], y: inhalt.frame.height - klick[1])
                    for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        guard let ereignis = NSEvent.mouseEvent(
                            with: art, location: punkt, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: blatt.windowNumber, context: nil,
                            eventNumber: 0, clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0)
                        else { continue }
                        NSApp.postEvent(ereignis, atStart: false)
                    }
                    zeilen.append("  Klick bei \(Int(klick[0])), \(Int(klick[1]))")
                } else {
                    speicher.entsperrungswegWechseln()
                    zeilen.append("  umgeschaltet auf \(speicher.entsperrungsweg)")
                }
                try? await Task.sleep(for: .milliseconds(700))
            }

            bestand("Blatt beim Öffnen")
            await abbild("start")

            switch weg {
            case "wiederherstellung":
                await umschalten()
                bestand("nach dem Umschalten")
                await abbild("wiederherstellung")
                if let feld = felder().first(where: { !($0 is NSSecureTextField) }) {
                    await tippen(feld, schluessel.lowercased().replacingOccurrences(of: "-", with: " "))
                    zeilen.append("  Schlüssel getippt (klein, mit Leerzeichen): "
                                  + knopfzustand("Entsperren"))
                    _ = await abschicken("Wiederherstellungsschlüssel")
                } else {
                    zeilen.append("  kein Textfeld für den Schlüssel ✗")
                }
            case "gemischt":
                // Der gemischte Weg: erst den Wiederherstellungsschlüssel
                // aufklappen, dann doch die Passphrase tippen.
                await umschalten()
                bestand("nach dem Umschalten")
                await abbild("gemischt")
                if let feld = felder().first(where: { $0 is NSSecureTextField }) {
                    await tippen(feld, passphrase)
                    zeilen.append("  Passphrase trotzdem getippt: " + knopfzustand("Entsperren"))
                    if await abschicken("Passphrase im aufgeklappten Zustand") { break }
                } else {
                    zeilen.append("  kein Passphrase-Feld mehr — die Eingabe ist eindeutig ✓")
                }
                await umschalten()
                bestand("zurückgeschaltet")
                if let feld = felder().first(where: { $0 is NSSecureTextField }) {
                    await tippen(feld, passphrase)
                    _ = await abschicken("Passphrase")
                }
            default:
                guard let feld = felder().first(where: { $0 is NSSecureTextField }) else {
                    zeilen.append("  kein Passphrase-Feld ✗")
                    break
                }
                await tippen(feld, "falsch")
                zeilen.append("  „falsch“ getippt: " + knopfzustand("Entsperren"))
                _ = await abschicken("falsche Passphrase")
                await abbild("fehler")
                await tippen(feld, passphrase)
                zeilen.append("  richtige Passphrase getippt: " + knopfzustand("Entsperren")
                              + (speicher.entsperrungFehler == nil ? " · Fehlertext weg ✓"
                                                                   : " · Fehlertext steht noch"))
                _ = await abschicken("richtige Passphrase")
            }
            await wicklungsbericht()
            zeilen.append("  Ende: Stand \(speicher.verschluesselungsstand), Planung "
                          + (speicher.planung.map { "„\($0.titel)“" } ?? "fehlt"))
            print(zeilen.joined(separator: "\n"))
            await blaetterSchliessenUndBeenden(speicher)
        }
    }

    /// `--tourtest`: die Tour am echten Fenster — je Schritt Lage des Ankers
    /// und der Karte auf dem Bildschirm, dazu Abbilder von Fenster und Karte
    /// (`TOURBILD=<Pfadanfang>`; die Karte über `ImageRenderer`, weil ein
    /// Popover sich nicht abzeichnen lässt). Vorher die Einträge der
    /// Werkzeugleiste, wie SwiftUI sie AppKit meldet. Gedruckt wird sofort,
    /// damit ein Absturz nichts verschluckt. Braucht eine `planung.json` mit
    /// einer Zeile.
    static func tourtestUndBeenden(_ speicher: Planungsspeicher) {
        guard ProcessInfo.processInfo.arguments.contains("--tourtest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("TOURTEST") else { return }
        let bildanfang = ProcessInfo.processInfo.environment["TOURBILD"]
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  speicher.planung != nil else {
                print("TOURTEST kein Fenster / keine Planung")
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            fenster.setContentSize(NSSize(width: 1400, height: 800))
            try? await Task.sleep(for: .milliseconds(900))

            @MainActor func sagen(_ zeile: String) {
                print(zeile)
                fflush(stdout)
            }
            sagen("TOURTEST")
            sagen(String(format: "Fenster %.0f,%.0f %.0f×%.0f", fenster.frame.minX,
                         fenster.frame.minY, fenster.frame.width, fenster.frame.height))
            sagen("Werkzeugleiste (\(fenster.toolbar?.items.count ?? 0) Einträge):")
            for eintrag in fenster.toolbar?.items ?? [] {
                let ansicht = eintrag.view
                let lage = ansicht.map { $0.convert($0.bounds, to: nil) } ?? .zero
                sagen("  „\(eintrag.label)“ · \(eintrag.toolTip ?? "—") · "
                      + (ansicht.map { "\(type(of: $0))" } ?? "ohne Ansicht")
                      + String(format: " %.0f,%.0f %.0f×%.0f", lage.minX, lage.minY,
                               lage.width, lage.height))
            }

            @MainActor func abbild(_ name: String) {
                guard let bildanfang else { return }
                ablegen(fenster, nach: URL(fileURLWithPath: bildanfang + "-" + name + ".png"))
                let zeichner = ImageRenderer(content: Tourkarte().environment(speicher))
                zeichner.scale = 2
                if let bild = zeichner.cgImage {
                    let abzug = NSBitmapImageRep(cgImage: bild)
                    let ort = URL(fileURLWithPath: bildanfang + "-" + name + "-karte.png")
                    try? abzug.representation(using: .png, properties: [:])?.write(to: ort)
                }
            }
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

            speicher.tourBeginnen()
            await festhalten("Start")
            speicher.tourWeiter()
            await festhalten("Weiter")
            speicher.tourZurueck()
            await festhalten("Zurück")
            var runden = 0
            while speicher.tourSchritt != nil, runden < 10 {
                speicher.tourWeiter()
                runden += 1
                if speicher.tourSchritt != nil { await festhalten("Weiter") }
            }
            try? await Task.sleep(for: .milliseconds(500))
            let offen = Tourfuehrer.shared.kartenfenster?.isVisible ?? false
            sagen("  Ende: Tour \(speicher.tourSchritt == nil ? "beendet ✓" : "läuft noch ✗")"
                  + ", Karte \(offen ? "steht noch ✗" : "weg ✓")"
                  + ", Meldung „\(speicher.meldungen.last?.text ?? "—")“")

            // Tastatur an der Karte: ⏎ geht weiter, ⎋ beendet — und ein
            // Neuaufbau des Rasters (Spaltenbreite) lässt die Karte nicht hängen.
            @MainActor func taste(_ zeichen: String, code: UInt16) {
                guard let karte = Tourfuehrer.shared.kartenfenster else { return }
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
            taste("\r", code: 36)
            try? await Task.sleep(for: .milliseconds(700))
            sagen("  Tastatur: Karte \(schluessel ? "ist" : "ist nicht") Schlüsselfenster; "
                  + "⏎ → \(speicher.tourSchritt?.rawValue ?? "—")"
                  + (speicher.tourSchritt == .planung ? " ✓" : " ✗"))
            // Bis zum letzten Schritt (mit Zeile: die Karte an der Zelle).
            while speicher.tourLaeuft, !speicher.tourAmEnde { speicher.tourWeiter() }
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
            await blaetterSchliessenUndBeenden(speicher)
        }
    }

    /// `--menuetest`: In der Menüleiste können zwei Einträge dasselbe Kürzel
    /// tragen — welcher greift, zeigt nur die laufende Anwendung.
    static func menuetestUndBeenden(_ speicher: Planungsspeicher) {
        guard ProcessInfo.processInfo.arguments.contains("--menuetest") else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt("MENUETEST") else { return }
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

    /// Legt zwei PNG ab: Der übergebene Pfad gibt Ordner und Grundnamen, die
    /// Dateien heißen `<Grundname>-rahmen.png` und `<Grundname>-inhalt.png`.
    private static func ablegen(_ fenster: NSWindow, nach ziel: URL) {
        // Abzeichnen statt Bildschirmaufnahme: die bräuchte eine Erlaubnis.
        for (name, ansicht) in [("rahmen", fenster.contentView?.superview),
                                ("inhalt", fenster.contentView)] {
            guard let ansicht,
                  let abzug = ansicht.bitmapImageRepForCachingDisplay(in: ansicht.bounds)
            else { continue }
            ansicht.cacheDisplay(in: ansicht.bounds, to: abzug)
            guard let daten = abzug.representation(using: .png, properties: [:]) else { continue }
            let datei = ziel.deletingPathExtension().lastPathComponent + "-" + name + ".png"
            let ort = ziel.deletingLastPathComponent().appendingPathComponent(datei)
            do {
                try daten.write(to: ort)
                print("ABBILD abgelegt: \(ort.path)")
            } catch {
                print("ABBILD nicht ablegbar (\(ort.path)): \(error.localizedDescription)")
            }
        }
    }
}
