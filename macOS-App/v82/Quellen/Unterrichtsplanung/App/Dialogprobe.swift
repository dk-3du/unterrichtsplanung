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
    /// Klassen-Blatt → Kursdatei, Vorhaben-Blatt → Material und → Material von
    /// 3ducation.org (v71: ohne Erlaubnis die Frage, mit Erlaubnis die Liste aus
    /// `MATERIAL_QUELLE`) — je ein Bogen am richtigen Blatt, im Blatt gelegen,
    /// genau einer, `cancel` bzw. ⎋ schließt ihn,
    /// das Blatt steht noch; dazu die Gegenprobe am Hauptfenster: ⇧⌘P bleibt
    /// ein freies Fenster. Braucht eine gesäte `planung.json` mit einer Klasse;
    /// liegt sie versiegelt, die Passphrase in `ENTSPERRPROBE_PASSPHRASE` —
    /// dann geht dem PDF-Sichern eine Rückfrage voraus, und der Bogen muss
    /// trotzdem am Blatt hängen, nicht an der Rückfrage (E116). Zuletzt ⌘Q mit
    /// minimiertem Hauptfenster: Es kommt mit der stehenden Rückfrage aus dem Dock
    /// (E329); ob ein Fenster mit angeheftetem Blatt sich minimieren lässt, steht
    /// als Auskunft.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        // Die Reißleine: Kommt der Lauf nicht von selbst zum Ende, schließt sie
        // alles Offene und geht — mit Befund, nie mit stehendem Dialog.
        let reissleine = Task { @MainActor in
            try? await Task.sleep(for: .seconds(90))
            // `try?` schluckt das Abbrechen aus `ende()` — ohne diese Zeile risse sie dort doch noch (E423).
            guard !Task.isCancelled else { return }
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
                await Pruefstaende.abschliessenUndBeenden(speicher)
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
                        // Wie von Hand, nicht im Programm (B82).
                        if let fehlt = await Pruefstaende.vonHandAntworten(speicher, true) {
                            pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                        }
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

                // ── Vorhaben-Blatt: Material von 3ducation.org (v71, E177, E182) ──
                // Ein SwiftUI-Blatt als Bogen: keine NSButtons, also zählt, was
                // messbar ist — der Bogen hängt am Blatt, seine Breite sagt, ob er
                // die Frage (640) oder die Liste (720) zeigt, ⎋ schließt ihn und
                // nimmt den Schalter zurück. Ohne Erlaubnis die Frage; nichts geht
                // ins Netz: Im Prüfstand gibt es ohne MATERIAL_QUELLE keine Quelle.
                @MainActor func materialSchritt(_ name: String, breite: CGFloat) async {
                    speicher.materialblattOffen = true
                    let da = await warten(8) { vorhaben.attachedSheet != nil }
                    guard da, let bogen = vorhaben.attachedSheet else {
                        pruefen(false, "\(name): innerhalb der Frist ging kein Bogen auf")
                        fensterlage("\(name): Fensterlage")
                        speicher.materialblattOffen = false
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(800))
                    bogenPruefen(bogen, an: vorhaben, name)
                    pruefen(abs(bogen.frame.width - breite) <= 1,
                            "\(name): Breite \(Int(bogen.frame.width)) — "
                            + (breite < 700 ? "die Frage" : "die Liste"))
                    // ⎋ an den Bogen — der Weg des Nutzers (`Dialograhmen.onExitCommand`).
                    await vorndran(bogen)
                    if let taste = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: bogen.windowNumber, context: nil,
                                                    characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                                    isARepeat: false, keyCode: 53) {
                        NSApp.postEvent(taste, atStart: false)
                    }
                    var weg = await warten(4) { vorhaben.attachedSheet == nil }
                    pruefen(weg, "\(name): ⎋ schließt den Bogen")
                    pruefen(!speicher.materialblattOffen, "\(name): der Schalter ist zurück")
                    if !weg {
                        speicher.materialblattOffen = false
                        weg = await warten(4) { vorhaben.attachedSheet == nil }
                    }
                    pruefen(vorhaben.isVisible, "\(name): das Blatt steht noch")
                    try? await Task.sleep(for: .milliseconds(300))
                }
                speicher.materialienErlauben(false)
                await materialSchritt("Vorhaben-Blatt · Material von 3ducation.org (Frage)", breite: 640)
                pruefen(!speicher.materialienErlaubt, "Vorhaben-Blatt · Frage: ⎋ ließ die Erlaubnis bei Nein")
                // Mit Erlaubnis die Liste — aus MATERIAL_QUELLE, sonst „nicht
                // erreichbar“; in beiden Fällen der breite Bogen.
                speicher.materialienErlauben(true)
                let quelle = ProcessInfo.processInfo.environment["MATERIAL_QUELLE"] ?? ""
                await materialSchritt("Vorhaben-Blatt · Material von 3ducation.org (Liste"
                                      + (quelle.isEmpty ? ", ohne Quelle)" : ")"), breite: 720)
                speicher.materialienErlauben(false)

                // ── Vorhaben-Blatt: das eigene Alert (B95, AU4b, E433, E434) ──
                // Ein Wort in das erste Textfeld, ⎋ — „Die Änderungen an diesem Vorhaben verwerfen?“,
                // „Verwerfen“, gleich danach ⏎; das Blatt geht erst nach dem Alert und übernimmt bis dahin
                // nichts (Z-AU4b-02).
                @MainActor func taste(_ zeichen: String, code: UInt16) {
                    if let ereignis = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: vorhaben.windowNumber, context: nil,
                                                       characters: zeichen, charactersIgnoringModifiers: zeichen,
                                                       isARepeat: false, keyCode: code) {
                        NSApp.postEvent(ereignis, atStart: false)
                    }
                }
                @MainActor func textfeld(_ ansicht: NSView?) -> NSTextField? {
                    guard let ansicht else { return nil }
                    if let feld = ansicht as? NSTextField, feld.isEditable { return feld }
                    for kind in ansicht.subviews {
                        if let feld = textfeld(kind) { return feld }
                    }
                    return nil
                }
                let eintraege = speicher.planung?.eintraege.count
                await vorndran(vorhaben)
                if let feld = textfeld(vorhaben.contentView), vorhaben.makeFirstResponder(feld),
                   let editor = feld.currentEditor() as? NSTextView {
                    editor.insertText("Probe", replacementRange: editor.selectedRange())
                }
                try? await Task.sleep(for: .milliseconds(300))
                taste("\u{1B}", code: 53)
                let gefragt = await warten(3) { Pruefstaende.alertfenster() != nil }
                pruefen(gefragt, "Vorhaben-Blatt · geändert, ⎋: die Frage nach dem Verwerfen")
                if gefragt {
                    // Im Klick geschlossen, wäre das Blatt gleich danach abgemeldet (`dismiss` setzt die Bindung).
                    let imKlick = await Pruefstaende.eigenesAlertDruecken("Verwerfen") { speicher.vorhabenDialog != nil }
                    pruefen(imKlick == true, "Vorhaben-Blatt · „Verwerfen“: gleich nach dem Klick steht das Blatt noch"
                            + (imKlick == nil ? " (kein Knopf „Verwerfen“)" : ""))
                    // Gleich danach ⏎ — in der Lücke, ehe das Blatt geht: „Übernehmen“ legte das Vorhaben an.
                    taste("\r", code: 36)
                    let zu = await warten(4) { speicher.vorhabenDialog == nil && haupt.attachedSheet == nil }
                    pruefen(zu && Pruefstaende.alertfenster() == nil && speicher.planung?.eintraege.count == eintraege,
                            "Vorhaben-Blatt · „Verwerfen“, gleich danach ⏎: geschlossen, kein Vorhaben angelegt (Z-AU4b-02)")
                }

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

            // ── ⌘Q holt das Fenster aus dem Dock (Z14c3-08, E329) ──────────────
            // Wie in den Vorarbeiten: erst minimieren, dann fragen. Beendet wird nur, wenn die Frage
            // am minimierten Fenster als stehend gilt — sonst ginge `beenden()` durch (Z-AS4-01, -02).
            await vorndran(haupt)
            // Eine Ursache, ein ✗: „nicht gemessen“ nur, wenn der Schritt sonst keines hatte (Z-AS4-14).
            let fehlerVorher = zeilen.filter { $0.hasPrefix("  ✗") }.count
            haupt.miniaturize(nil)
            let minimiert = await warten(3) { haupt.isMiniaturized }
            try? await Task.sleep(for: .milliseconds(500))  // Die Animation ist sicher durch.
            pruefen(minimiert, "Dock · das Hauptfenster ist minimiert")
            speicher.fragen("Prüfstand: Fenster aus dem Dock?", bestaetigung: "Ja") {}
            let steht = await warten(3) { Pruefstaende.alertfenster() != nil }
            pruefen(steht, "Dock · die Rückfrage steht")
            // Holte das Anheften das Fenster selbst zurück, ist das erst nach der Animation zu sehen (Z-AS4-13).
            try? await Task.sleep(for: .milliseconds(500))
            // Gemessen ist E329 nur, wenn das Fenster vor ⌘Q noch im Dock liegt (Z-AS4-09).
            var gemessen = false
            if minimiert && steht && !haupt.isMiniaturized {
                zeilen.append("  Die Rückfrage holte das Fenster selbst aus dem Dock")
                print(zeilen.last!); fflush(stdout)
            } else if minimiert && steht {
                speicher.beenden()
                let zurueck = await warten(3) { !haupt.isMiniaturized }
                pruefen(zurueck && Pruefstaende.alertfenster() != nil, "⌘Q holt das Fenster aus dem Dock, die Frage steht")
                gemessen = true
            }
            if haupt.isMiniaturized { haupt.deminiaturize(nil); _ = await warten(3) { !haupt.isMiniaturized } }
            _ = await warten(3) { Pruefstaende.alertfenster() != nil }
            if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) { pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden") }
            _ = await warten(3) { Pruefstaende.alertfenster() == nil }

            // Zusatz: ob ein Fenster mit angeheftetem Blatt sich minimieren lässt — Auskunft, kein
            // Befund. Lässt es sich, holt ⌘Q es ebenso zurück.
            await vorndran(haupt)
            speicher.fragen("Prüfstand: Fenster mit Blatt in den Dock?", bestaetigung: "Ja") {}
            let stehtVorher = await warten(3) { Pruefstaende.alertfenster() != nil }
            pruefen(stehtVorher, "Dock · eine Rückfrage steht am Hauptfenster")
            if stehtVorher {
                haupt.miniaturize(nil)
                let minimierbar = await warten(3) { haupt.isMiniaturized }
                zeilen.append("  Fenster mit Blatt minimierbar: \(minimierbar ? "ja" : "nein")")
                print(zeilen.last!); fflush(stdout)
                if minimierbar {
                    try? await Task.sleep(for: .milliseconds(500))
                    if Pruefstaende.alertfenster() != nil && haupt.isMiniaturized {
                        speicher.beenden()
                        let zurueck = await warten(3) { !haupt.isMiniaturized }
                        pruefen(zurueck && Pruefstaende.alertfenster() != nil,
                                "⌘Q holt das Fenster mit Blatt aus dem Dock, die Frage steht")
                        gemessen = true
                        // Auskunft, kein Befund (Z-AS4-04): ob das zurückgeholte Fenster Tasten annimmt —
                        // gelesen, sobald AppKit es gesetzt haben kann (Z-AS4-10). Hier, denn bisher misst nur dieser Weg.
                        let tasten = await warten(1) { haupt.isKeyWindow || Pruefstaende.alertfenster()?.isKeyWindow == true }
                        zeilen.append("  Zurückgeholt mit Tastatur: \(tasten ? "ja" : "nein")")
                        print(zeilen.last!); fflush(stdout)
                    } else if haupt.isMiniaturized {
                        pruefen(false, "Dock · die Rückfrage gilt am minimierten Fenster nicht mehr als stehend")
                    } else {
                        zeilen.append("  Das Fenster mit Blatt kam nach dem Minimieren von selbst zurück")
                        print(zeilen.last!); fflush(stdout)
                    }
                    if haupt.isMiniaturized { haupt.deminiaturize(nil); _ = await warten(3) { !haupt.isMiniaturized } }
                }
            }
            if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) { pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden") }
            _ = await warten(3) { Pruefstaende.alertfenster() == nil }
            if !gemessen && zeilen.filter({ $0.hasPrefix("  ✗") }).count == fehlerVorher {
                pruefen(false, "E329 nicht gemessen: weder Hauptweg noch Zusatz fand das Fenster mit Frage im Dock")
            }

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
