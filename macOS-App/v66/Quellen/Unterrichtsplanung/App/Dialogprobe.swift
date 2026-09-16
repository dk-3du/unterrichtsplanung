// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Wo die Dialoge aufgehen — am echten Paket, mit Reißleine (E117, v61).
///
/// Der Befund des Nutzers ließ sich im Prüfziel nicht sehen: Ein Dialog, der
/// als freies Fenster über einem Blatt steht statt als Bogen daran, ist eine
/// Sache von AppKit, Fensterkette und Schlüsselfenster — und ein Dialog, der
/// stehen bleibt, ist genau der Fehler, den ich am eigenen Bildschirm nicht
/// sehe (E101: der Sichern-Dialog blieb zweimal stehen). Darum prüft dieser
/// Lauf jeden Weg am laufenden Fenster, schließt jeden Dialog selbst über
/// seinen sicheren Weg (`cancel`) und hat eine Reißleine: Läuft ein Schritt
/// über seine Frist, wird alles Offene abgebrochen und der Lauf endet mit
/// Befund. Nichts bleibt auf dem Bildschirm stehen.
@MainActor
enum Dialogprobe {

    /// `--dialogtest`: Sitzplan-Editor → „Als PDF sichern“ und „Drucken“,
    /// Klassen-Blatt → Kursdatei, Vorhaben-Blatt → Material — je ein Bogen am
    /// richtigen Blatt, im Blatt gelegen, genau einer, `cancel` schließt ihn,
    /// das Blatt steht noch; dazu die Gegenprobe am Hauptfenster: ⇧⌘P bleibt
    /// ein freies Fenster. Braucht eine gesäte `planung.json` mit einer Klasse;
    /// liegt sie versiegelt, die Passphrase in `ENTSPERRPROBE_PASSPHRASE` —
    /// dann geht dem PDF-Sichern eine Rückfrage voraus, und der Bogen muss
    /// trotzdem am Blatt hängen, nicht an der Rückfrage (E116).
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        // Die Reißleine: Kommt der Lauf nicht von selbst zum Ende, schließt sie
        // alles Offene und geht — mit Befund, nie mit stehendem Dialog.
        let reissleine = Task { @MainActor in
            try? await Task.sleep(for: .seconds(90))
            print("DIALOGTEST REISSLEINE — Frist verstrichen, alles Offene wird geschlossen ✗")
            fflush(stdout)
            allesSchliessen()
            try? await Task.sleep(for: .milliseconds(500))
            exit(3)
        }
        Task { @MainActor in
            var zeilen = ["DIALOGTEST"]
            var bestanden = true
            @MainActor func pruefen(_ gilt: Bool, _ text: String) {
                zeilen.append("  \(gilt ? "✓" : "✗") \(text)")
                if !gilt { bestanden = false }
                print(zeilen.last!)
                fflush(stdout)
            }
            @MainActor func ende() async {
                reissleine.cancel()
                allesSchliessen()
                zeilen.append(bestanden ? "DIALOGTEST bestanden" : "DIALOGTEST mit Befund")
                print(zeilen.last!)
                fflush(stdout)
                await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
            }
            @MainActor func hauptfenster() -> NSWindow? {
                NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && !($0 is NSSavePanel) }
            }
            /// Warten, bis etwas gilt — höchstens `frist` Sekunden.
            @MainActor func warten(_ frist: Double = 6, bis gilt: @MainActor () -> Bool) async -> Bool {
                let ende = Date().addingTimeInterval(frist)
                while Date() < ende {
                    if gilt() { return true }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                return gilt()
            }
            @MainActor func vorndran(_ fenster: NSWindow?) async {
                NSApp.activate(ignoringOtherApps: true)
                fenster?.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(500))
            }
            @MainActor func knopf(_ titel: [String], in ansicht: NSView?) -> NSButton? {
                guard let ansicht else { return nil }
                if let k = ansicht as? NSButton, titel.contains(k.title) { return k }
                for kind in ansicht.subviews {
                    if let k = knopf(titel, in: kind) { return k }
                }
                return nil
            }
            /// Was gerade auf dem Bildschirm steht — für einen Befund.
            @MainActor func fensterlage(_ titel: String) {
                var lage = ["  \(titel):"]
                for f in NSApp.windows where f.isVisible {
                    let art = String(describing: type(of: f))
                    let eltern = f.sheetParent.map { String(describing: type(of: $0)) + " „\($0.title)“" } ?? "—"
                    lage.append("    \(art) „\(f.title)“ \(Int(f.frame.width)) × \(Int(f.frame.height)) Ebene \(f.level.rawValue) "
                                + "Bogen an: \(eltern)\(f.isKeyWindow ? " · Schlüssel" : "")")
                }
                if let modal = NSApp.modalWindow { lage.append("    modal: \(String(describing: type(of: modal)))") }
                zeilen.append(contentsOf: lage)
                print(lage.joined(separator: "\n"))
                fflush(stdout)
            }
            @MainActor func bogenBeschreibung(_ bogen: NSWindow, an blatt: NSWindow) -> String {
                let r = bogen.frame, b = blatt.frame
                return "Rahmen \(Int(r.width)) × \(Int(r.height)) in Blatt \(Int(b.width)) × \(Int(b.height)), "
                    + "Ebene \(bogen.level.rawValue)/\(blatt.level.rawValue)"
            }

            /// Ein Bogen, der am Blatt hängt: liegt im Blatt, teilt dessen Ebene,
            /// ist der einzige seiner Art.
            @MainActor func bogenPruefen(_ bogen: NSWindow?, an blatt: NSWindow, _ name: String) {
                guard let bogen else { pruefen(false, "\(name): kein Bogen am Blatt"); return }
                pruefen(bogen.sheetParent === blatt, "\(name): Bogen am Blatt — \(bogenBeschreibung(bogen, an: blatt))")
                let r = bogen.frame, b = blatt.frame
                // Breiter als das Blatt darf ein Bogen sein — ein Öffnen-Dialog hat
                // eine Mindestbreite, und AppKit zentriert ihn dann über dem Blatt
                // (Systemverhalten, siehe `Dialogort`). Gemessen wird es; ✗ erst,
                // wenn er aus dem Hauptfenster ragte oder nicht mittig hinge.
                let mitte = abs(r.midX - b.midX) <= 1
                let imHauptfenster = hauptfenster().map { r.minX >= $0.frame.minX - 1 && r.maxX <= $0.frame.maxX + 1 } ?? true
                pruefen(mitte && imHauptfenster && r.maxY <= b.maxY + 1,
                        "\(name): der Bogen hängt mittig am Blatt"
                        + (r.width > b.width + 1 ? " und steht \(Int(r.width - b.width)) Punkt über (Mindestbreite des Dialogs)" : ""))
                pruefen(bogen.level == blatt.level, "\(name): dieselbe Fensterebene wie das Blatt")
                let freie = NSApp.windows.filter { $0.isVisible && $0 is NSSavePanel && $0.sheetParent == nil }
                pruefen(freie.isEmpty, "\(name): kein freier Dialog daneben")
            }

            /// Den Bogen über seinen sicheren Weg schließen: `cancel` am Panel,
            /// sonst der Abbrechen-Knopf, sonst `endSheet`.
            @MainActor func schliessen(_ bogen: NSWindow, an blatt: NSWindow) {
                if let panel = bogen as? NSSavePanel { panel.cancel(nil); return }
                if let k = knopf(["Abbrechen", "Cancel"], in: bogen.contentView) { k.performClick(nil); return }
                blatt.endSheet(bogen, returnCode: .cancel)
            }

            /// `erwartet` sagt, welcher Bogen gemeint ist — vor dem Sichern-Dialog
            /// einer versiegelten Planung steht erst die Rückfrage am Blatt.
            @MainActor func bogenSchritt(_ name: String, an blatt: NSWindow,
                                         erwartet: @escaping @MainActor (NSWindow) -> Bool = { _ in true },
                                         ausloesen: @MainActor () -> Void) async {
                ausloesen()
                let da = await warten(8) { blatt.attachedSheet.map(erwartet) ?? false }
                guard da, let bogen = blatt.attachedSheet, erwartet(bogen) else {
                    pruefen(false, "\(name): innerhalb der Frist ging kein Bogen auf")
                    fensterlage("\(name): Fensterlage")
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
                bogenPruefen(bogen, an: blatt, name)
                schliessen(bogen, an: blatt)
                let weg = await warten(4) { blatt.attachedSheet == nil }
                pruefen(weg, "\(name): Abbrechen schließt den Bogen")
                pruefen(blatt.isVisible, "\(name): das Blatt steht noch")
                if !weg { blatt.endSheet(bogen, returnCode: .cancel) }
                try? await Task.sleep(for: .milliseconds(300))
            }

            // ── Aufbau ─────────────────────────────────────────────────────
            try? await Task.sleep(for: .seconds(2.5))
            if speicher.verschluesselungsstand == .gesperrt {
                let passphrase = ProcessInfo.processInfo.environment["ENTSPERRPROBE_PASSPHRASE"] ?? ""
                await speicher.entsperren(passphrase: passphrase)
                try? await Task.sleep(for: .milliseconds(600))
            }
            guard let haupt = hauptfenster(), let planung = speicher.planung,
                  let klasse = planung.klassen.first else {
                pruefen(false, "kein Fenster, keine Planung oder keine Klasse")
                await ende()
                return
            }
            pruefen(true, "Planung „\(planung.titel)“ — Stand \(speicher.verschluesselungsstand)"
                    + (speicher.verschluesselt ? " (dem PDF-Sichern geht eine Rückfrage voraus)" : ""))
            await vorndran(haupt)
            pruefen(Dialogort.aktuell == .frei, "am Hauptfenster ist der Weg frei")

            // ── Sitzplan-Editor: Als PDF sichern, Drucken ──────────────────
            speicher.sitzplaene.setzen(Sitzplan.anordnen(klasseId: klasse.id, namen: ["Ada", "Alan", "Grace"]),
                                       fuer: klasse.id)
            speicher.sitzplanOeffnen(klasse: klasse.id)
            guard await warten(bis: { haupt.attachedSheet != nil }), let editor = haupt.attachedSheet else {
                pruefen(false, "der Sitzplan-Editor ging nicht auf")
                await ende()
                return
            }
            await vorndran(editor)
            pruefen(speicher.offenerDialog == .sitzplan && speicher.sitzplanEntwurf != nil,
                    "Sitzplan-Editor offen für „\(klasse.name)“, Entwurf mit \(speicher.sitzplanEntwurf?.tische.count ?? 0) Tischen")
            pruefen(Dialogort.aktuell == .bogen(editor), "am Editor ist der Weg der Bogen an diesem Blatt")

            await bogenSchritt("Sitzplan · Als PDF sichern", an: editor, erwartet: { $0 is NSSavePanel }) {
                speicher.sitzplanAlsPDFSichern()
                if speicher.verschluesselt {
                    // Die Rückfrage steht jetzt als Bogen auf dem Blatt; ihre
                    // Antwort öffnet den Dialog — der muss ans Blatt, nicht an sie (E116).
                    Task { @MainActor in
                        _ = await warten(3) { speicher.rueckfrage != nil }
                        try? await Task.sleep(for: .milliseconds(400))
                        zeilen.append("  Rückfrage steht — Weg jetzt: \(Dialogort.aktuell), Schlüssel: "
                                      + (NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "keins"))
                        print(zeilen.last!); fflush(stdout)
                        speicher.rueckfrageBeantworten(true)
                    }
                }
            }
            if speicher.verschluesselt {
                pruefen(editor.attachedSheet == nil, "Sitzplan · Als PDF sichern: auch die Rückfrage ist fort")
            }

            await bogenSchritt("Sitzplan · Drucken", an: editor) { speicher.sitzplanDrucken() }
            pruefen(NSPrintOperation.current == nil, "Sitzplan · Drucken: kein Druckvorgang mehr offen")

            speicher.alleDialogeSchliessen()
            _ = await warten(4) { haupt.attachedSheet == nil }
            pruefen(haupt.attachedSheet == nil, "der Sitzplan-Editor ist zu")

            // ── Klassen-Blatt: Kursdatei wählen ────────────────────────────
            speicher.dialogOeffnen(.klassen)
            if await warten(bis: { haupt.attachedSheet != nil }), let klassen = haupt.attachedSheet {
                await vorndran(klassen)
                await bogenSchritt("Klassen-Blatt · Kursdatei", an: klassen) {
                    speicher.kursdateiWaehlen(klasse: klasse.id, art: .verwaltung)
                }
                pruefen(planung.klasse(klasse.id)?.verwaltung == speicher.planung?.klasse(klasse.id)?.verwaltung,
                        "Klassen-Blatt · Kursdatei: nichts zugewiesen")
                speicher.alleDialogeSchliessen()
                _ = await warten(4) { haupt.attachedSheet == nil }
            } else {
                pruefen(false, "das Klassen-Blatt ging nicht auf")
            }

            // ── Vorhaben-Blatt: Material wählen ────────────────────────────
            speicher.vorhabenDialog = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
            if await warten(bis: { haupt.attachedSheet != nil }), let vorhaben = haupt.attachedSheet {
                await vorndran(vorhaben)
                var abschluss: [String]? = nil
                await bogenSchritt("Vorhaben-Blatt · Material", an: vorhaben) {
                    Systemzugriff.dateienWaehlen(start: "", zugriff: speicher.zugriff) { abschluss = $0 }
                }
                pruefen(abschluss == [], "Vorhaben-Blatt · Material: der Abschluss kam, mit leerer Wahl")
                speicher.vorhabenDialog = nil
                _ = await warten(4) { haupt.attachedSheet == nil }
            } else {
                pruefen(false, "das Vorhaben-Blatt ging nicht auf")
            }

            // ── Gegenprobe am Hauptfenster: ⇧⌘P bleibt ein freies Fenster ──
            await vorndran(haupt)
            pruefen(Dialogort.aktuell == .frei, "zurück am Hauptfenster ist der Weg frei")
            var freierDialog: NSWindow?
            // `runModal()` hält diesen Aufruf an; der Zeitgeber läuft im
            // Modalmodus weiter und bricht den Dialog ab (E115: das Hauptfenster
            // verhält sich wie bisher).
            let zeitgeber = Timer(timeInterval: 1.0, repeats: false) { _ in
                MainActor.assumeIsolated {
                    freierDialog = NSApp.windows.first { $0.isVisible && $0 is NSSavePanel }
                    (freierDialog as? NSSavePanel)?.cancel(nil)
                }
            }
            RunLoop.main.add(zeitgeber, forMode: .modalPanel)
            RunLoop.main.add(zeitgeber, forMode: .default)
            Drucken.alsPDFSichern(planung, speicher: speicher)
            try? await Task.sleep(for: .milliseconds(300))
            pruefen(freierDialog != nil && freierDialog?.sheetParent == nil,
                    "Hauptfenster · Als PDF sichern: ein freies Fenster wie bisher"
                    + (freierDialog.map { " (\(Int($0.frame.width)) × \(Int($0.frame.height)))" } ?? ""))
            pruefen(NSApp.windows.first { $0.isVisible && $0 is NSSavePanel } == nil,
                    "Hauptfenster · Als PDF sichern: Abbrechen schließt es")

            await ende()
        }
    }

    /// Alles Offene über den sicheren Weg schließen — Panels per `cancel`,
    /// Bögen per `endSheet`, eine Modalschleife per `abortModal`.
    static func allesSchliessen() {
        for fenster in NSApp.windows {
            if let bogen = fenster.attachedSheet {
                if let panel = bogen as? NSSavePanel { panel.cancel(nil) }
                else { fenster.endSheet(bogen, returnCode: .cancel) }
            }
            if let panel = fenster as? NSSavePanel, panel.isVisible, panel.sheetParent == nil { panel.cancel(nil) }
        }
        if NSApp.modalWindow != nil { NSApp.abortModal() }
    }
}
