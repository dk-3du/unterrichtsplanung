// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Wo die Dialoge aufgehen — am echten Paket, mit Reißleine (E117, v61).
///
/// Der Befund des Nutzers ließ sich im Prüfziel nicht sehen: Ein Dialog, der
/// als freies Fenster über einem Blatt steht statt als Bogen daran, ist eine
/// Sache von AppKit, Fensterkette und Schlüsselfenster — und ein Dialog, der
/// stehen bleibt, ist genau der Fehler, den ich am eigenen Bildschirm nicht
/// sehe (E101: Der Sichern-Dialog blieb zweimal stehen). Darum prüft dieser
/// Lauf jeden Weg am laufenden Fenster, schließt jeden Dialog selbst über
/// seinen sicheren Weg (`cancel`) und hat eine Reißleine: Läuft ein Schritt
/// über seine Frist, wird alles Offene abgebrochen und der Lauf endet mit
/// Befund. Nichts bleibt auf dem Bildschirm stehen.
@MainActor
enum Dialogprobe {

    /// `--dialogtest`: Sitzplan-Editor → „Als PDF sichern“ und „Drucken“, auch
    /// je bei schon hängendem Bogen des anderen (B107: Ton, kein zweiter Bogen),
    /// Klassen-Blatt → Kursdatei, auch aus der Antwort auf eine Rückfrage (E116),
    /// Klassen-Blatt → „Lernende …“ und mit ⎋ zurück (E358; im Klartext die
    /// Rückfrage an ⌘K), verschlüsselt dazu der Bogen „Zeilen wählen“ am Blatt „Lernende“ über die Vorgabe, sobald
    /// der Kopf steht (E669, E678; ohne Lerngruppe entfällt der Schritt), und dort das Finder-Blatt „Aus IServ importieren“
    /// so breit wie das Blatt (E627), dreimal Sitzplan-Editor aus ⌘K und mit ⎋ zurück (E513),
    /// Schließknopf und ⌘W bei angeheftetem Blatt „Lernende“ bzw. Sitzplan-Editor — das Blatt bleibt angemeldet (E518),
    /// Blatt „Neue Planung“ → „Aus IServ importieren“ über die Vorgabe (E603, E610:
    /// versiegelt der Bogen am Blatt, ⎋ schließt ihn; im Klartext öffnet sie keinen),
    /// verschlüsselt mit Lerngruppen der Bogen „Lerngruppen zuordnen“ an „Neue Planung“
    /// und an ⌘O über die Vorgabe der Lage (E628, E629) — ohne Lerngruppen (Klartext,
    /// `DIALOGPROBE_OHNE_JAHRESDATEI=1`) öffnet die Vorgabe an „Neue Planung“ keinen
    /// (E631, E632; an ⌘O nicht geprüft, Z-AT8P-12),
    /// Vorhaben-Blatt → die Leiste mit sieben Reitern, beim Öffnen „Grundlegendes“ (E731), Wechsel über die Leiste,
    /// der Entwurf bleibt, die Leiste behält ihre Breite mit Kennzeichen (v85, AW3-neu),
    /// Vorhaben-Blatt → Material und → Material von
    /// 3ducation.org (v71: ohne Erlaubnis die Frage, mit Erlaubnis die Liste aus
    /// `MATERIAL_QUELLE`) — je ein Bogen am richtigen Blatt, im Blatt gelegen
    /// (ein Finder-Blatt höchstens bis zu seiner Mindestbreite darüber, auch mit
    /// einer großen gemerkten Breite, E627), genau einer, `cancel` bzw. ⎋ schließt ihn,
    /// das Blatt steht noch; dazu die Gegenprobe am Hauptfenster: ⇧⌘P bleibt
    /// ein freies Fenster. Braucht eine gesäte `planung.json` mit einer Klasse;
    /// liegt sie versiegelt, die Passphrase in `ENTSPERRPROBE_PASSPHRASE` —
    /// dann kommt der Sichern-Dialog des Sitzplans ohne Rückfrage (E449) mit
    /// vorgewähltem Kennwortschutz, im Klartext ohne (E40). Zuletzt ⌘Q mit
    /// minimiertem Hauptfenster: Es kommt mit der stehenden Rückfrage aus dem Dock
    /// (E329); ob ein Fenster mit angeheftetem Blatt sich minimieren lässt, steht
    /// als Auskunft.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        // Die Reißleine: Kommt der Lauf nicht von selbst zum Ende, schließt sie
        // alles Offene und geht — mit Befund, nie mit stehendem Dialog. 120 s seit
        // v85 (E735): Der Lauf mit Verschlüsselung brauchte mit E518 85 s.
        let reissleine = Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            // `try?` schluckt das Abbrechen aus `ende()` — ohne diese Zeile risse sie dort doch noch (E423).
            guard !Task.isCancelled else { return }
            print("DIALOGTEST REISSLEINE — Frist verstrichen, alles Offene wird geschlossen ✗")
            fflush(stdout)
            allesSchliessen()
            gemerktZuruecksetzen()
            try? await Task.sleep(for: .milliseconds(500))
            // Der abgebrochene Dialog schreibt seine Breite womöglich erst jetzt (Z-AW1-06) — und geschrieben sein muss
            // es vor dem Beenden (Z-AW1N-02).
            gemerktZuruecksetzen()
            UserDefaults.standard.synchronize()
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
            @MainActor func ende() async {
                reissleine.cancel()
                allesSchliessen()
                gemerktZuruecksetzen()
                // Ein abgebrochener Dialog schreibt seine Breite womöglich erst beim Gehen (Z-AW1-06) — darum, wenn er
                // fort ist, noch einmal, wie an der Reißleine (G3-07).
                _ = await warten(2, bis: { !NSApp.windows.contains { $0 is NSSavePanel && $0.isVisible } })
                gemerktZuruecksetzen()
                zeilen.append(bestanden ? "DIALOGTEST bestanden" : "DIALOGTEST mit Befund")
                print(zeilen.last!)
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
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
                    + ((bogen as? NSSavePanel).map { ", Mindestbreite \(Int($0.minSize.width))" } ?? "")
            }

            /// Ein Bogen, der am Blatt hängt: liegt im Blatt, teilt dessen Ebene,
            /// ist der einzige seiner Art.
            @MainActor func bogenPruefen(_ bogen: NSWindow?, an blatt: NSWindow, _ name: String) {
                guard let bogen else { pruefen(false, "\(name): kein Bogen am Blatt"); return }
                pruefen(bogen.sheetParent === blatt, "\(name): Bogen am Blatt — \(bogenBeschreibung(bogen, an: blatt))")
                let r = bogen.frame, b = blatt.frame
                // Breiter als das Blatt darf nur ein Öffnen- oder Sichern-Dialog sein — er
                // hat eine Mindestbreite, und AppKit zentriert ihn dann über dem Blatt
                // (Systemverhalten, siehe `Dialogort`). Ein eigener Bogen steht nie über
                // (Z-AT7-06). Gemessen wird es; ✗ auch, wenn er aus dem Hauptfenster
                // ragte oder nicht mittig hinge.
                let mitte = abs(r.midX - b.midX) <= 1
                let imHauptfenster = hauptfenster().map { r.minX >= $0.frame.minX - 1 && r.maxX <= $0.frame.maxX + 1 } ?? true
                let ueberstand = r.width > b.width + 1
                // Überstehen darf ein Öffnen- oder Sichern-Dialog nur bis zu seiner Mindestbreite — nie mit der Breite,
                // die zuletzt von Hand gezogen und gemerkt wurde (E627).
                let mindestbreite = (bogen as? NSSavePanel)?.minSize.width ?? 0
                let nurMindestbreite = bogen is NSSavePanel && r.width <= max(b.width, mindestbreite) + 1
                let lageStimmt = mitte && imHauptfenster && r.maxY <= b.maxY + 1 && (!ueberstand || nurMindestbreite)
                pruefen(lageStimmt,
                        "\(name): Der Bogen hängt mittig am Blatt"
                        + (!ueberstand ? "" : " und steht \(Int(r.width - b.width)) Punkt über"
                           + (bogen is NSSavePanel ? " (Breite \(Int(r.width)), Mindestbreite des Dialogs \(Int(mindestbreite)))"
                              : " — ein eigener Bogen darf das nicht")))
                // Griff die Vorgabe? Dann ist ein Finder-Blatt so breit, wie `Dialogort` es aus der großen Breite rechnet —
                // sonst bliebe E627 ungeprüft, und jeder Schritt wäre trotzdem ✓ (Z-AW1N-01). Nur, wenn die Lage stimmt:
                // Steht der Dialog über, hat die Zeile davor schon ihr ✗ — eine Ursache, ein ✗ (Z-AS4-14, Z-AW1M-01).
                if lageStimmt, let panel = bogen as? NSSavePanel {
                    let soll = Dialogort.bogenbreite(dialog: grosseBreite, mindest: panel.minSize.width, blatt: b.width)
                    pruefen(abs(r.width - soll) <= 1,
                            "\(name): Breite \(Int(r.width)), gerechnet aus der Vorgabe \(Int(grosseBreite)): \(Int(soll))")
                }
                pruefen(bogen.level == blatt.level, "\(name): dieselbe Fensterebene wie das Blatt")
                let freie = NSApp.windows.filter { $0.isVisible && $0 is NSSavePanel && $0.sheetParent == nil }
                pruefen(freie.isEmpty, "\(name): kein freier Dialog daneben")
            }

            /// Den Bogen über seinen sicheren Weg schließen: `cancel` am Panel,
            /// sonst der Abbrechen-Knopf, sonst `endSheet`. `false`: ohne eigenes Abbrechen, über das Blatt — so bei
            /// SwiftUI-Bögen, deren Knöpfe der Fensterlauf nicht erreicht (E678); die Zeile sagt es (E697).
            @discardableResult
            @MainActor func schliessen(_ bogen: NSWindow, an blatt: NSWindow) -> Bool {
                if let panel = bogen as? NSSavePanel { panel.cancel(nil); return true }
                if let k = knopf(["Abbrechen", "Cancel"], in: bogen.contentView) { k.performClick(nil); return true }
                blatt.endSheet(bogen, returnCode: .cancel)
                return false
            }

            /// `erwartet` sagt, welcher Bogen gemeint ist.
            @MainActor func bogenSchritt(_ name: String, an blatt: NSWindow,
                                         erwartet: @escaping @MainActor (NSWindow) -> Bool = { _ in true },
                                         ausloesen: @MainActor () -> Void) async {
                // Jeder Schritt sieht die große gemerkte Breite — ein Dialog merkt sich beim Schließen seine (Z-AW1-08, E712).
                grossVorgeben()
                ausloesen()
                let da = await warten(8) { blatt.attachedSheet.map(erwartet) ?? false }
                guard da, let bogen = blatt.attachedSheet, erwartet(bogen) else {
                    pruefen(false, "\(name): Innerhalb der Frist ging kein Bogen auf")
                    fensterlage("\(name): Fensterlage")
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
                bogenPruefen(bogen, an: blatt, name)
                let mitKnopf = schliessen(bogen, an: blatt)
                let weg = await warten(4) { blatt.attachedSheet == nil }
                pruefen(weg, mitKnopf ? "\(name): Abbrechen schließt den Bogen"
                        : "\(name): Der Bogen ist geschlossen — über das Blatt, kein Knopf „Abbrechen“ erreichbar")
                pruefen(blatt.isVisible, "\(name): Das Blatt steht noch")
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
            pruefen(true, "Planung „\(planung.titel)“ — Stand \(speicher.verschluesselungsstand)")
            // Mit Passphrase gesät heißt versiegelt: Sonst bliebe der Zweig „vorgewählt“ unbemerkt ungeprüft.
            if !(ProcessInfo.processInfo.environment["ENTSPERRPROBE_PASSPHRASE"] ?? "").isEmpty {
                pruefen(speicher.verschluesselt, "die versiegelte Saat ist entsperrt — die Planung ist verschlüsselt")
            }
            await vorndran(haupt)
            pruefen(Dialogort.aktuell == .frei, "am Hauptfenster ist der Weg frei")
            // Wer einen Finder-Dialog einmal breit zieht, bekommt ihn so wieder — auch als Bogen an einem schmaleren
            // Blatt (Bildschirmfotos des Nutzers, um 1370 Punkt; E627). Vorgegeben wie von Hand, der Sichern-Dialog
            // aufgeklappt — eingeklappt griffe die Breite nicht (Z-AW1-01).
            grossVorgeben()
            pruefen(grossVorgegeben, "gemerkte Größe der Finder-Blätter 1400 × 600, Sichern aufgeklappt, vorgegeben (E627)")

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

            // Ohne Rückfrage, auch versiegelt (E449); der Kennwortschutz ist vorgewählt, wenn verschlüsselt (E40).
            var sichernGefunden = false
            var vorgewaehlt: Bool?
            await bogenSchritt("Sitzplan · Als PDF sichern", an: editor, erwartet: { bogen in
                guard let dialog = bogen as? NSSavePanel else { return false }
                sichernGefunden = true
                vorgewaehlt = (dialog.accessoryView as? Sitzplandruck.Kennwortzusatz).map { $0.gewaehltesKennwort != nil }
                return true
            }) {
                speicher.sitzplanAlsPDFSichern()
            }
            pruefen(speicher.rueckfrage == nil && speicher.wartendeRueckfragen.isEmpty,
                    "Sitzplan · Als PDF sichern: keine Rückfrage")
            // Ging der Dialog nicht auf, hat das schon sein ✗ — eine Ursache, ein ✗ (Z-AS4-14).
            if sichernGefunden {
                pruefen(vorgewaehlt == speicher.verschluesselt,
                        "Sitzplan · Als PDF sichern: Kennwortschutz "
                        + (vorgewaehlt.map { $0 ? "vorgewählt" : "nicht vorgewählt" } ?? "nicht zu lesen")
                        + (speicher.verschluesselt ? " (verschlüsselt)" : " (Klartext)"))
            }

            // Ein stehendes Alert ist nicht der Druckbogen.
            await bogenSchritt("Sitzplan · Drucken", an: editor, erwartet: { !Planungsspeicher.istAlert($0) }) {
                speicher.sitzplanDrucken()
            }
            pruefen(NSPrintOperation.current == nil, "Sitzplan · Drucken: kein Druckvorgang mehr offen")

            // ── Ein zweiter Bogen am Editor (B107, E459) ───────────────────
            // Hängt schon ein Bogen am Blatt, verhallte ein zweiter und ließe sein Zusatzfenster
            // verwaist stehen. Darum der Ton und sonst nichts — und das Netz in `Dialogort.zeigen`
            // hängt an ein noch belegtes Blatt nichts an.
            @MainActor func verwaist() -> Int {
                NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("AccessoryView") }.count
            }
            let verwaistVorher = verwaist()
            speicher.sitzplanDrucken()
            if await warten(8, bis: { editor.attachedSheet.map { !Planungsspeicher.istAlert($0) && !($0 is NSSavePanel) } ?? false }),
               let druckbogen = editor.attachedSheet {
                try? await Task.sleep(for: .milliseconds(400))
                let toene = speicher.systemtoene
                speicher.sitzplanAlsPDFSichern()
                pruefen(speicher.systemtoene == toene + 1, "⌘P, dann ⇧⌘P: der Systemton, sonst nichts")
                // Das Netz selbst: ein Sichern-Dialog an das belegte Blatt, an der Sperre vorbei — nur, solange die
                // Probe vorn ist; sonst ginge er frei auf und hielte den Lauf bis zur Reißleine (I3-01).
                if Dialogort.aktuell == .bogen(editor) {
                    var antwort: NSApplication.ModalResponse?
                    let netzToene = Dialogort.toene
                    let netz = NSSavePanel()
                    netz.accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
                    Dialogort.zeigen(netz) { antwort = $0 }
                    _ = await warten(5) { antwort != nil }
                    try? await Task.sleep(for: .milliseconds(500))  // Ein verhallender Bogen hätte sein Zusatzfenster jetzt gezeigt.
                    // Wenigstens ein Ton: Versagte vorher die Sperre, tönt auch deren Netz — dafür steht schon ein ✗ (I3-02).
                    pruefen(antwort == .cancel && Dialogort.toene >= netzToene + 1,
                            "Netz (Sichern): An einem belegten Blatt geht der Dialog nicht auf — Ton (\(Dialogort.toene - netzToene)), "
                            + "Abschluss „abgebrochen“")
                } else {
                    pruefen(false, "Netz (Sichern): Die Probe ist nicht vorn (\(Dialogort.aktuell)) — nicht gerufen")
                }
                pruefen(editor.attachedSheet === druckbogen, "⌘P, dann ⇧⌘P: Am Editor hängt weiter nur der Druckbogen")
                pruefen(verwaist() == verwaistVorher, "⌘P, dann ⇧⌘P: kein verwaistes Zusatzfenster")
                schliessen(druckbogen, an: editor)
                _ = await warten(4) { editor.attachedSheet == nil }
                try? await Task.sleep(for: .seconds(1))
                pruefen(editor.attachedSheet == nil && verwaist() == verwaistVorher && NSPrintOperation.current == nil,
                        "⌘P, dann ⇧⌘P: Nach dem Abbrechen des Druckbogens ist nichts mehr offen")
                if let rest = editor.attachedSheet { schliessen(rest, an: editor) }
            } else {
                pruefen(false, "⌘P, dann ⇧⌘P: Der Druckbogen ging nicht auf")
            }
            speicher.sitzplanAlsPDFSichern()
            if await warten(8, bis: { editor.attachedSheet is NSSavePanel }), let sichernBogen = editor.attachedSheet {
                try? await Task.sleep(for: .milliseconds(400))
                let toene = speicher.systemtoene
                speicher.sitzplanDrucken()
                pruefen(speicher.systemtoene == toene + 1, "⇧⌘P, dann ⌘P: der Systemton, sonst nichts")
                // Das Netz selbst: ein Druckvorgang an das belegte Blatt, an der Sperre vorbei — nur, solange die Probe
                // vorn ist (I3-01).
                if Dialogort.aktuell == .bogen(editor) {
                    let netzToene = Dialogort.toene
                    Dialogort.drucken(NSPrintOperation(view: NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))))
                    let getoent = await warten(5) { Dialogort.toene >= netzToene + 1 }
                    try? await Task.sleep(for: .milliseconds(500))
                    pruefen(getoent, "Netz (Druck): An einem belegten Blatt geht der Druckbogen nicht auf — Ton")
                } else {
                    pruefen(false, "Netz (Druck): Die Probe ist nicht vorn (\(Dialogort.aktuell)) — nicht gerufen")
                }
                pruefen(editor.attachedSheet === sichernBogen && NSPrintOperation.current == nil,
                        "⇧⌘P, dann ⌘P: Kein Druckvorgang, am Editor hängt weiter nur der Sichern-Dialog")
                schliessen(sichernBogen, an: editor)
                _ = await warten(4) { editor.attachedSheet == nil }
                try? await Task.sleep(for: .seconds(1))
                pruefen(editor.attachedSheet == nil && NSPrintOperation.current == nil,
                        "⇧⌘P, dann ⌘P: Nach dem Abbrechen des Sichern-Dialogs ist nichts mehr offen")
                if let rest = editor.attachedSheet { schliessen(rest, an: editor) }
            } else {
                pruefen(false, "⇧⌘P, dann ⌘P: Der Sichern-Dialog ging nicht auf")
            }

            speicher.alleDialogeSchliessen()
            _ = await warten(4) { haupt.attachedSheet == nil }
            pruefen(haupt.attachedSheet == nil, "der Sitzplan-Editor ist zu")

            // ── Klassen-Blatt: Kursdatei wählen ────────────────────────────
            speicher.dialogOeffnen(.klassen)
            if await warten(bis: { haupt.attachedSheet != nil }), let klassen = haupt.attachedSheet {
                await vorndran(klassen)
                // Erwartet wird der Wähler selbst — ein Alert am Blatt wäre sonst auch ein Bogen (Z-AX7-09).
                await bogenSchritt("Klassen-Blatt · Kursdatei", an: klassen, erwartet: { $0 is NSOpenPanel }) {
                    speicher.kursdateiWaehlen(klasse: klasse.id, art: .verwaltung)
                }
                pruefen(planung.klasse(klasse.id)?.verwaltung == speicher.planung?.klasse(klasse.id)?.verwaltung,
                        "Klassen-Blatt · Kursdatei: nichts zugewiesen")
                // Derselbe Weg für die Leistungsdokumentation (v86, AX7e, E662): Der Wähler hängt am Blatt, abgebrochen
                // bleibt nichts.
                await bogenSchritt("Klassen-Blatt · Leistungsdokumentation", an: klassen, erwartet: { $0 is NSOpenPanel }) {
                    speicher.kursdateiWaehlen(klasse: klasse.id, art: .leistungsdokumentation)
                }
                pruefen(planung.klasse(klasse.id)?.leistungsdokumentation
                            == speicher.planung?.klasse(klasse.id)?.leistungsdokumentation,
                        "Klassen-Blatt · Leistungsdokumentation: nichts zugewiesen")
                // Ein Dialog aus der Antwort auf eine Rückfrage: Die Rückfrage hängt noch als Bogen am
                // Blatt, wenn er aufgeht — er muss ans Blatt, nicht an sie, und darf nicht verhallen (E116).
                await bogenSchritt("Klassen-Blatt · Dialog aus einer Antwort", an: klassen,
                                   erwartet: { $0 is NSSavePanel }) {
                    speicher.fragen("Prüfstand: Dialog aus der Antwort?", bestaetigung: "Ja", ort: .klassen) {
                        speicher.kursdateiWaehlen(klasse: klasse.id, art: .verwaltung)
                    }
                    Task { @MainActor in
                        _ = await warten(3) { speicher.rueckfrage != nil }
                        try? await Task.sleep(for: .milliseconds(400))
                        // Wie von Hand, nicht im Programm (B82).
                        if let fehlt = await Pruefstaende.vonHandAntworten(speicher, true) {
                            pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                        }
                    }
                }
                pruefen(klassen.attachedSheet == nil, "Klassen-Blatt · Dialog aus einer Antwort: Auch die Rückfrage ist fort")
                pruefen(planung.klasse(klasse.id)?.verwaltung == speicher.planung?.klasse(klasse.id)?.verwaltung,
                        "Klassen-Blatt · Dialog aus einer Antwort: nichts zugewiesen")
                speicher.alleDialogeSchliessen()
                _ = await warten(4) { haupt.attachedSheet == nil }
            } else {
                pruefen(false, "das Klassen-Blatt ging nicht auf")
            }

            // ── Klassen-Blatt: der Weg zur Lernendenverwaltung (v84, E356–E358) ──
            // Am Speicher wie der Knopf „Lernende …“. Verschlüsselt: ⌘K geht, das Blatt „Lernende“ kommt; jeder seiner
            // Schließwege wie von Hand — ⎋, ⏎ („Übernehmen“), ⎋ mit getippter Liste und „Verwerfen“ — führt zurück zu
            // ⌘K (Z-AT4-02). Im Klartext: Die Frage „Verschlüsselung einrichten …“ an ⌘K, nach „Abbrechen“ steht ⌘K
            // weiter (Z-AT4-04).
            @MainActor func tasteAn(_ fenster: NSWindow, _ zeichen: String, code: UInt16) {
                // Ohne Schreibmarke: Ein Textfeld behielte ⏎ (Z-AT2b-06), eine Textansicht nähme ⎋ als Vervollständigen.
                fenster.makeFirstResponder(nil)
                if let ereignis = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: fenster.windowNumber, context: nil,
                                                   characters: zeichen, charactersIgnoringModifiers: zeichen,
                                                   isARepeat: false, keyCode: code) {
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }
            speicher.dialogOeffnen(.klassen)
            if await warten(bis: { haupt.attachedSheet != nil && speicher.offenerDialog == .klassen }),
               let klassen = haupt.attachedSheet {
                await vorndran(klassen)
                switch speicher.lernende.quelle {
                case .behaelter:
                    let wege: [(name: String, zeichen: String, code: UInt16, liste: String?)] = [
                        ("⎋", "\u{1B}", 53, nil), ("⏎ („Übernehmen“)", "\r", 36, nil),
                        ("⎋ mit getippter Liste, „Verwerfen“", "\u{1B}", 53, "Abel, Anna")]
                    for weg in wege {
                        speicher.lernendenBlattOeffnen(ort: .klassen, zurueck: .klassen)
                        if let liste = weg.liste { speicher.lernendenVorgabe?.namenstext = liste }
                        let da = await warten { speicher.offenerDialog == .lernende && speicher.lernendenblattOffen
                            && haupt.attachedSheet != nil }
                        pruefen(da, "Klassen-Blatt · „Lernende …“ (\(weg.name)): ⌘K ist fort, das Blatt „Lernende“ steht")
                        if !da {
                            // Auskunft für den Befund: der Stand am Speicher und was auf dem Bildschirm steht.
                            let lage = "    Stand: offen \(speicher.offenerDialog.map(\.rawValue) ?? "—"), vorgemerkt "
                                + "\(speicher.naechsterDialog.map(\.rawValue) ?? "—"), Blatt „Lernende“ angemeldet "
                                + "\(speicher.lernendenblattOffen), Vorgabe \(speicher.lernendenVorgabe != nil), Rückfrage "
                                + "\(speicher.rueckfrage?.text.prefix(60) ?? "—"), Bogen am Hauptfenster \(haupt.attachedSheet != nil)"
                            zeilen.append(lage)
                            print(lage)
                            fflush(stdout)
                            fensterlage("Klassen-Blatt · \(weg.name): Fensterlage")
                        }
                        guard da, let blatt = haupt.attachedSheet else { break }
                        await vorndran(blatt)
                        // Ein verspätetes Abmelden kommt auch nach der ersten Abfrage — darum nach einer Ruhe noch
                        // einmal, unmittelbar vor der Taste (Z-AT4a-01).
                        try? await Task.sleep(for: .seconds(1))
                        pruefen(speicher.offenerDialog == .lernende && speicher.lernendenblattOffen,
                                "Klassen-Blatt · „Lernende …“ (\(weg.name)): nach 1 s Ruhe noch angemeldet")
                        tasteAn(blatt, weg.zeichen, code: weg.code)
                        if weg.liste != nil {
                            let gefragt = await warten(3) { speicher.rueckfrage != nil && Pruefstaende.alertfenster() != nil }
                            pruefen(gefragt && speicher.rueckfrage?.bestaetigung == "Verwerfen",
                                    "Klassen-Blatt · \(weg.name): erst die Frage nach dem Verwerfen")
                            if gefragt, let fehlt = await Pruefstaende.vonHandAntworten(speicher, true) {
                                pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                            }
                        }
                        let zurueck = await warten { speicher.offenerDialog == .klassen && !speicher.lernendenblattOffen
                            && haupt.attachedSheet != nil }
                        pruefen(zurueck && Pruefstaende.alertfenster() == nil && speicher.naechsterDialog == nil,
                                "Klassen-Blatt · \(weg.name) im Blatt „Lernende“: ⌘K steht wieder, nichts mehr vorgemerkt (E358)")
                        guard zurueck else { break }
                        await vorndran(haupt.attachedSheet)
                    }
                    // Der Bogen „Zeilen wählen“ am Blatt „Lernende“ (v84, AT9a-2, E669, E678): aus der Vorgabe, sobald der Kopf der
                    // gewählten Lerngruppe steht; ⎋ schließt ihn, dann das Blatt — zurück zu ⌘K. Nur, wenn ⌘K wieder vorn steht
                    // (sonst eine Ursache, mehrere ✗, Z-AS4-14); ohne aktive Lerngruppe (Lauf ohne Jahresdatei) gibt es keinen
                    // Kopf — dann die Gegenprobe „kein Bogen“ (Z-AT9a2-10).
                    let mitGruppe = speicher.lernende.bestand?.lerngruppen.contains { $0.archiviert.isEmpty } == true
                    if speicher.offenerDialog == .klassen && !speicher.lernendenblattOffen && haupt.attachedSheet != nil {
                        speicher.lernendenBlattOeffnen(ort: .klassen, zurueck: .klassen)
                        // Der Knopf im SwiftUI-Kopf ist kein NSButton — der Bogen kommt aus der Vorgabe, sobald der Kopf steht (E678).
                        speicher.lernendenVorgabe?.zeilenwahl = mitGruppe
                        if await warten(bis: { speicher.offenerDialog == .lernende && speicher.lernendenblattOffen
                            && haupt.attachedSheet != nil }), let blatt = haupt.attachedSheet {
                            let name = "Blatt „Lernende“ · Zeilen wählen"
                            var bogenBleibt = false
                            if !mitGruppe {
                                // Ohne Lerngruppe kein Kopf, also keine Vorgabe, die greifen könnte — eine Auskunft, keine Frist
                                // (Z-AT9a2-18).
                                zeilen.append("  \(name) ohne Lerngruppe: kein Kopf, der Schritt entfällt")
                                print(zeilen.last!); fflush(stdout)
                            } else if await warten(8, bis: { blatt.attachedSheet != nil }), let bogen = blatt.attachedSheet {
                                bogenPruefen(bogen, an: blatt, name)
                                // Das Merkmal des Bogens: kein Alert, 520 breit (Z-AT9a2-19).
                                pruefen(Pruefstaende.alertfenster() == nil && abs(bogen.frame.width - 520) <= 1,
                                        "\(name): Breite \(Int(bogen.frame.width)) — der Bogen „Zeilen wählen“")
                                tasteAn(bogen, "\u{1B}", code: 53)
                                let zu = await warten(4) { blatt.attachedSheet == nil }
                                pruefen(zu && blatt.isVisible, "\(name): ⎋ schließt den Bogen, das Blatt steht noch")
                                bogenBleibt = !zu
                            } else {
                                pruefen(false, "\(name): Innerhalb der Frist ging kein Bogen auf")
                                fensterlage("\(name): Fensterlage")
                            }
                            // Hängt der Bogen noch, räumt das Aufräumen unten auf — kein zweites ✗ aus einer Ursache (Z-AT9a2-20).
                            if !bogenBleibt {
                                // Das Finder-Blatt am Blatt „Lernende“ (1000, breiter als die Mindestbreite 924): so breit wie das
                                // Blatt, nicht wie gemerkt (E627) — über dieselbe Funktion wie der Knopf „Aus IServ importieren …“,
                                // der als SwiftUI-Knopf kein NSButton ist.
                                await vorndran(blatt)
                                // Auskunft: Die Schritte davor schlossen den Dialog am schmaleren Klassen-Blatt — gemerkt ist
                                // seither dessen Breite (gemessen: {924, 600}, E712); `bogenSchritt` gibt wieder die große vor.
                                zeilen.append("  Gemerkte Größe nach den Schritten am Klassen-Blatt: "
                                              + (UserDefaults.standard.string(forKey: groessenSchluessel[0]) ?? "—"))
                                print(zeilen.last!); fflush(stdout)
                                // Nur an ein freies Blatt, an dem die Probe vorn steht — sonst ginge der Dialog frei auf und hielte
                                // den Lauf bis zur Reißleine (wie I3-01, Z-AW1-09).
                                let iserv = "Blatt „Lernende“ · Aus IServ importieren"
                                if blatt.attachedSheet == nil && Dialogort.aktuell == .bogen(blatt) {
                                    await bogenSchritt(iserv, an: blatt, erwartet: { $0 is NSOpenPanel }) {
                                        Systemzugriff.quelleWaehlen(nachricht: "Exportdatei der IServ-Benutzerverwaltung wählen",
                                                                    typen: [.commaSeparatedText, .tabSeparatedText, .plainText]) { _ in }
                                    }
                                } else {
                                    pruefen(false, "\(iserv): Das Blatt ist nicht frei oder die Probe nicht vorn (\(Dialogort.aktuell)) — nicht gerufen")
                                    fensterlage("\(iserv): Fensterlage")
                                }
                                await vorndran(blatt)
                                tasteAn(blatt, "\u{1B}", code: 53)
                                let zurueck = await warten { speicher.offenerDialog == .klassen && !speicher.lernendenblattOffen
                                    && haupt.attachedSheet != nil }
                                pruefen(zurueck && Pruefstaende.alertfenster() == nil && speicher.naechsterDialog == nil,
                                        "Blatt „Lernende“: ⎋ schließt danach das Blatt, ⌘K steht wieder, nichts vorgemerkt")
                                await vorndran(haupt.attachedSheet)
                            }
                        } else {
                            pruefen(false, "Blatt „Lernende“ · Zeilen wählen: Das Blatt ging nicht auf")
                        }
                    }
                case .aus:
                    speicher.lernendenBlattOeffnen(ort: .klassen, zurueck: .klassen)
                    let gefragt = await warten(3) { speicher.rueckfrage != nil && klassen.attachedSheet != nil }
                    pruefen(gefragt && speicher.rueckfrage?.ort == .klassen
                            && speicher.rueckfrage?.bestaetigung == "Verschlüsselung einrichten …",
                            "Klassen-Blatt · „Lernende …“ ohne Verschlüsselung: „Verschlüsselung einrichten …“ hängt an ⌘K")
                    if gefragt {
                        if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) {
                            pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                        }
                        let weg = await warten(3) { klassen.attachedSheet == nil && speicher.rueckfrage == nil }
                        pruefen(weg && speicher.offenerDialog == .klassen && haupt.attachedSheet === klassen,
                                "Klassen-Blatt · „Abbrechen“: ⌘K steht weiter, keine Einrichtung der Verschlüsselung")
                    }
                case .zu, .gesperrt:
                    pruefen(false, "Klassen-Blatt · „Lernende …“: Die Lernendenverwaltung ist versiegelt oder gesperrt — "
                            + "die Saat ist weder Klartext noch entsperrt")
                }
                // Steht im roten Lauf noch eine Rückfrage, dann wie von Hand beantwortet — nicht im Programm (B82, Z-AT4-05).
                if speicher.rueckfrage != nil { _ = await Pruefstaende.vonHandAntworten(speicher, false) }
                speicher.alleDialogeSchliessen()
                _ = await warten(4) { haupt.attachedSheet == nil }
            } else {
                pruefen(false, "das Klassen-Blatt ging für „Lernende …“ nicht auf")
            }

            // ── Klassen-Blatt: Sitzplan-Editor hin und zurück (v84, AT4a, E513) ──
            // Dreimal ⌘K → Sitzplan-Editor (am Speicher wie das Menü der Zeile, mit Rückweg) → ⎋ → ⌘K: Jedes Mal muss der
            // Editor angemeldet stehen — ein verspätetes `onDisappear` des vorigen meldete ihn sonst ab (wie D-AT4-01).
            speicher.dialogOeffnen(.klassen)
            if await warten(bis: { haupt.attachedSheet != nil && speicher.offenerDialog == .klassen }) {
                await vorndran(haupt.attachedSheet)
                for runde in 1...3 {
                    speicher.sitzplanOeffnen(klasse: klasse.id, zurueck: .klassen)
                    let da = await warten { speicher.offenerDialog == .sitzplan && speicher.sitzplanblattOffen
                        && haupt.attachedSheet != nil }
                    pruefen(da, "Klassen-Blatt · Sitzplan-Editor (\(runde). Mal): ⌘K ist fort, der Editor steht angemeldet")
                    if !da {
                        let lage = "    Stand: offen \(speicher.offenerDialog.map(\.rawValue) ?? "—"), vorgemerkt "
                            + "\(speicher.naechsterDialog.map(\.rawValue) ?? "—"), Editor angemeldet \(speicher.sitzplanblattOffen), "
                            + "Entwurf \(speicher.sitzplanEntwurf != nil), Bogen am Hauptfenster \(haupt.attachedSheet != nil)"
                        zeilen.append(lage)
                        print(lage)
                        fflush(stdout)
                        fensterlage("Klassen-Blatt · Sitzplan-Editor (\(runde). Mal): Fensterlage")
                    }
                    guard da, let blatt = haupt.attachedSheet else { break }
                    await vorndran(blatt)
                    // Nach einer Ruhe noch einmal, unmittelbar vor der Taste (Z-AT4a-01).
                    try? await Task.sleep(for: .seconds(1))
                    pruefen(speicher.offenerDialog == .sitzplan && speicher.sitzplanblattOffen,
                            "Klassen-Blatt · Sitzplan-Editor (\(runde). Mal): nach 1 s Ruhe noch angemeldet")
                    tasteAn(blatt, "\u{1B}", code: 53)
                    let zurueck = await warten { speicher.offenerDialog == .klassen && !speicher.sitzplanblattOffen
                        && haupt.attachedSheet != nil }
                    pruefen(zurueck && Pruefstaende.alertfenster() == nil && speicher.naechsterDialog == nil,
                            "Klassen-Blatt · ⎋ im Sitzplan-Editor (\(runde). Mal): ⌘K steht wieder, nichts mehr vorgemerkt")
                    guard zurueck else { break }
                    await vorndran(haupt.attachedSheet)
                }
                if speicher.rueckfrage != nil { _ = await Pruefstaende.vonHandAntworten(speicher, false) }
                speicher.alleDialogeSchliessen()
                _ = await warten(4) { haupt.attachedSheet == nil }
            } else {
                pruefen(false, "das Klassen-Blatt ging für den Sitzplan-Editor nicht auf")
            }

            // ── Hauptfenster mit angeheftetem Blatt schließen (v85, AW4; E518, E516) ──
            // Zwei Reize wie von Hand, während das Blatt „Lernende“ bzw. der Sitzplan-Editor am Hauptfenster hängt: der
            // Schließknopf (`performClose` am Hauptfenster) und ⌘W (die Taste an das Schlüsselfenster — das Blatt —, über das
            // Menü „Schließen“, Z-AW4-01). Erwartet: Fenster, Blatt und Anmeldung bleiben. Ginge das Blatt doch, müsste die
            // Anmeldung mitgehen — sonst gehörte ⌘Z einem Blatt, das fort ist (E516). Grün: E516 entfällt.
            /// Was Beobachter während des Schritts vermerken: ob ⌘W ankam, ob das Hauptfenster gehen wollte.
            @MainActor final class Schliessvermerk {
                var taste = false
                var fensterGeht = false
            }
            /// Der Menüeintrag zu einer Taste mit ⌘ — für die Auskunft, wohin ⌘W geht.
            @MainActor func menuepunkt(_ menue: NSMenu?, _ taste: String) -> NSMenuItem? {
                for punkt in menue?.items ?? [] {
                    if punkt.keyEquivalent == taste && punkt.keyEquivalentModifierMask == .command { return punkt }
                    if let fund = menuepunkt(punkt.submenu, taste) { return fund }
                }
                return nil
            }
            @MainActor func zeile(_ text: String) {
                zeilen.append("  \(text)")
                print(zeilen.last!); fflush(stdout)
            }
            /// Grün nur, wenn nach jedem Reiz Fenster, Blatt und Anmeldung bleiben (E518) — jeder andere Ausgang ist ein Befund
            /// (Z-AW4N-01). `false`, wenn das Hauptfenster danach fort ist: Dann endet der Lauf (Z-AW4N-06).
            @MainActor func schliessenVersuchen(_ name: String, dialog: Dialogfenster, angemeldet: @escaping @MainActor () -> Bool,
                                                oeffnen: () -> Void) async -> Bool {
                let vermerk = Schliessvermerk()
                // Synchron beim Schließen: Mit dem letzten Fenster beendete AppKit die App, ehe eine Prüfzeile käme (Z-AW4N-05).
                let beobachter = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: haupt,
                                                                        queue: .main) { _ in
                    MainActor.assumeIsolated {
                        vermerk.fensterGeht = true
                        print("  Auskunft: \(name) — das Hauptfenster schließt samt Blatt")
                        fflush(stdout)
                    }
                }
                // Ob ⌘W ankam — sonst prüfte die Zeile nichts (Z-AW4N-02).
                let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ereignis in
                    if ereignis.keyCode == 13, ereignis.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                        MainActor.assumeIsolated { vermerk.taste = true }
                    }
                    return ereignis
                }
                defer {
                    NotificationCenter.default.removeObserver(beobachter)
                    if let monitor { NSEvent.removeMonitor(monitor) }
                }
                oeffnen()
                let offen = await warten(bis: { speicher.offenerDialog == dialog && angemeldet() && haupt.attachedSheet != nil })
                if offen, let blatt = haupt.attachedSheet {
                    @MainActor func nachDemReiz(_ reiz: String, taste: Bool = false) async -> Bool {
                        // Eine Frist für ein Ereignis, das nicht kommen soll: Die Frist endet früh, sobald sich etwas ändert.
                        // Kurz — der Reiz wirkt binnen Millisekunden.
                        _ = await warten(0.5) {
                            vermerk.fensterGeht || !haupt.isVisible || haupt.attachedSheet !== blatt || !angemeldet()
                        }
                        let fenster = !vermerk.fensterGeht && haupt.isVisible
                        let bleibt = fenster && haupt.attachedSheet === blatt && speicher.offenerDialog == dialog && angemeldet()
                        let gilt = bleibt && (!taste || vermerk.taste)
                        pruefen(gilt, "\(name), \(reiz): " + (gilt
                            ? "Fenster und Blatt bleiben, das Blatt bleibt angemeldet (E518)"
                            : taste && bleibt ? "Die Taste kam nicht an — nichts geprüft"
                            : "Fenster \(fenster ? "steht" : "fort"), Blatt \(haupt.attachedSheet === blatt ? "steht" : "fort"), "
                              + "angemeldet \(angemeldet() ? "ja" : "nein") — erwartet: alles bleibt (E518, E516)"))
                        return gilt
                    }
                    haupt.performClose(nil)
                    if await nachDemReiz("Schließknopf") {
                        await vorndran(blatt)
                        if let punkt = menuepunkt(NSApp.mainMenu, "w"), let aktion = punkt.action {
                            let ziel = NSApp.target(forAction: aktion, to: punkt.target, from: punkt) as AnyObject?
                            zeile("Auskunft: ⌘W im Menü „\(punkt.title)“ → \(NSStringFromSelector(aktion)), Ziel "
                                  + (ziel === blatt ? "das Blatt" : ziel === haupt ? "das Hauptfenster"
                                     : ziel.map { "\(type(of: $0))" } ?? "keines"))
                        } else {
                            zeile("Auskunft: kein Menüeintrag mit ⌘W")
                        }
                        // Nur an das Blatt als Schlüsselfenster und ohne gesperrte Eingabe — sonst prüfte der Reiz nichts.
                        if NSApp.isActive && NSApp.keyWindow === blatt && !speicher.handlungAussteht,
                           let taste = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: blatt.windowNumber, context: nil,
                                                        characters: "w", charactersIgnoringModifiers: "w",
                                                        isARepeat: false, keyCode: 13) {
                            NSApp.postEvent(taste, atStart: false)
                            _ = await nachDemReiz("⌘W", taste: true)
                        } else {
                            pruefen(false, "\(name), ⌘W: nicht gesendet — Probe aktiv \(NSApp.isActive ? "ja" : "nein"), "
                                    + "Blatt Schlüsselfenster \(NSApp.keyWindow === blatt ? "ja" : "nein"), "
                                    + "Eingabe gesperrt \(speicher.handlungAussteht ? "ja" : "nein")")
                        }
                    } else {
                        zeile("Auskunft: \(name), ⌘W entfällt — nach dem Schließknopf stand nicht mehr alles (Z-AW4N-04)")
                    }
                } else {
                    pruefen(false, "\(name): Das Blatt ging nicht auf")
                    fensterlage("\(name): Fensterlage")
                }
                let steht = haupt.isVisible && !vermerk.fensterGeht
                // Aufräumen in jedem Fall — ein Rest trüge sich sonst als zweites ✗ in den nächsten Schritt (Z-AW4-04).
                if speicher.rueckfrage != nil { _ = await Pruefstaende.vonHandAntworten(speicher, false) }
                speicher.alleDialogeSchliessen()
                _ = await warten(4) { haupt.attachedSheet == nil }
                return steht
            }
            if case .behaelter = speicher.lernende.quelle {
                guard await schliessenVersuchen("Blatt „Lernende“ am Hauptfenster", dialog: .lernende,
                                                angemeldet: { speicher.lernendenblattOffen }, oeffnen: {
                    speicher.lernendenBlattOeffnen()
                }) else { await ende(); return }
            } else {
                zeile("Blatt „Lernende“ am Hauptfenster: ohne offene Lernendenverwaltung entfällt der Schritt")
            }
            guard await schliessenVersuchen("Sitzplan-Editor am Hauptfenster", dialog: .sitzplan,
                                            angemeldet: { speicher.sitzplanblattOffen }, oeffnen: {
                speicher.sitzplanOeffnen(klasse: klasse.id)
            }) else { await ende(); return }

            // ── Blatt „Neue Planung“: der Bogen „Aus IServ importieren“ (v84, AT7, E603, E610) ──
            // Am Speicher wie der Knopf: Die Datei gibt der Prüfstand vor, wenn das Blatt steht — ohne Dateidialog und
            // ohne Frist im Programm (E610). Mit Verschlüsselung der Bogen am Blatt, genau einer; ⎋ schließt ihn, das
            // Blatt steht noch, angelegt ist nichts. Im Klartext ist der Knopf grau (E350) — es geht kein Bogen auf.
            let iservDatei = FileManager.default.temporaryDirectory.appending(component: "dialogprobe-iserv.csv")
            try? Data("Vorname;Nachname;Klasse\nAda;Probe;5a\nAlan;Probe;5b\n".utf8).write(to: iservDatei)
            let erstelltVorher = speicher.planung?.erstellt
            speicher.neuePlanungOeffnen()
            if await warten(bis: { speicher.offenerDialog == .neuePlanung && haupt.attachedSheet != nil }),
               let neuePlanung = haupt.attachedSheet {
                await vorndran(neuePlanung)
                let name = "Neue Planung · Aus IServ importieren"
                speicher.neuePlanungImportdatei = iservDatei
                if speicher.tresor != nil {
                    if await warten(8, bis: { neuePlanung.attachedSheet != nil }), let bogen = neuePlanung.attachedSheet {
                        await vorndran(bogen)
                        bogenPruefen(bogen, an: neuePlanung, name)
                        // Am Blatt so breit wie das Blatt, 720 — daran ist der Import-Bogen zu erkennen (E605, Z-AT7-06).
                        pruefen(abs(bogen.frame.width - 720) <= 1,
                                "\(name): Breite \(Int(bogen.frame.width)) — der Import-Bogen")
                        // ⎋ an den Bogen — der Weg des Nutzers (`Dialograhmen.onExitCommand`).
                        tasteAn(bogen, "\u{1B}", code: 53)
                        let weg = await warten(4) { neuePlanung.attachedSheet == nil }
                        pruefen(weg, "\(name): ⎋ schließt den Bogen")
                        if !weg { neuePlanung.endSheet(bogen, returnCode: .cancel) }
                        pruefen(neuePlanung.isVisible && speicher.offenerDialog == .neuePlanung, "\(name): Das Blatt steht noch")
                    } else {
                        pruefen(false, "\(name): Innerhalb der Frist ging kein Bogen auf")
                        fensterlage("\(name): Fensterlage")
                    }
                } else {
                    _ = await warten(2) { neuePlanung.attachedSheet != nil }
                    pruefen(neuePlanung.attachedSheet == nil, "\(name) im Klartext: Die Vorgabe öffnet keinen Bogen (E350)")
                }
                pruefen(speicher.planung?.erstellt == erstelltVorher && speicher.neuePlanungImportdatei == nil,
                        "\(name): Nichts angelegt, die Vorgabe ist verbraucht")
                speicher.alleDialogeSchliessen()
                _ = await warten(4) { haupt.attachedSheet == nil }
            } else {
                pruefen(false, "das Blatt „Neue Planung“ ging nicht auf")
            }
            try? FileManager.default.removeItem(at: iservDatei)

            // ── Blatt „Neue Planung“ und ⌘O: der Bogen „Lerngruppen zuordnen“ (v84, AT8, E628–E630) ──
            // Nur verschlüsselt mit Lerngruppen — sonst gibt es den Knopf nicht; im Lauf dialog-versiegelt bringt die Saat
            // sie mit (E628). Am Speicher wie der Knopf: Die Lage gibt der Prüfstand vor (E629), das Blatt öffnet den
            // Bogen — am Blatt, mittig, der einzige; ⎋ schließt ihn, das Blatt steht noch, die Vorgabe ist verbraucht.
            // Frist 4 s: Zwei Schritte ohne Bogen kosten sonst 16 s, die Reißleine liegt bei 120 s (E735).
            // Gezählt wird nur ein eigener Bogen — kein Alert einer Rückfrage (Z-AT8P-03), kein Dateidialog am Blatt
            // (Z-AT8P-14); „Das Blatt steht noch“ heißt auch im Speicher: Das Blatt ist offen, bei ⌘O steht der Wechsel
            // noch (Z-AT8P-01).
            @MainActor func zuordnungsSchritt(_ name: String, an blatt: NSWindow, dialog: Dialogfenster,
                                              steht: @escaping @MainActor () -> Bool = { true }) async {
                speicher.zuordnungsbogenVorgabe = .vorschlag
                if await warten(4, bis: { blatt.attachedSheet.map { !Planungsspeicher.istAlert($0) && !($0 is NSSavePanel) } ?? false }),
                   let bogen = blatt.attachedSheet {
                    await vorndran(bogen)
                    bogenPruefen(bogen, an: blatt, name)
                    // Das Merkmal des Bogens: 720 breit wie das Blatt (E388 b, Z-AT8P-14).
                    pruefen(abs(bogen.frame.width - ZuordnungsBogen.breite) <= 1,
                            "\(name): Breite \(Int(bogen.frame.width)) — der Bogen „Lerngruppen zuordnen“")
                    tasteAn(bogen, "\u{1B}", code: 53)
                    let weg = await warten(4) { blatt.attachedSheet == nil }
                    pruefen(weg, "\(name): ⎋ schließt den Bogen")
                    if !weg { blatt.endSheet(bogen, returnCode: .cancel) }
                    pruefen(blatt.isVisible && speicher.offenerDialog == dialog && steht(), "\(name): Das Blatt steht noch")
                } else {
                    pruefen(false, "\(name): Innerhalb der Frist ging kein Bogen auf")
                    fensterlage("\(name): Fensterlage")
                }
                pruefen(speicher.zuordnungsbogenVorgabe == nil, "\(name): Die Vorgabe ist verbraucht")
                speicher.zuordnungsbogenVorgabe = nil
            }
            // Die Lage der Saat: verschlüsselt mit Jahresdatei und Lerngruppen (E628) oder ohne Jahresdatei
            // (`DIALOGPROBE_OHNE_JAHRESDATEI=1`, Lauf dialog-versiegelt-leer, E632); im Klartext gibt es keine.
            let ohneJahresdatei = ProcessInfo.processInfo.environment["DIALOGPROBE_OHNE_JAHRESDATEI"] == "1"
            if speicher.tresor != nil {
                pruefen(ohneJahresdatei == speicher.lerngruppenZurWahl.isEmpty,
                        ohneJahresdatei ? "Vorbedingung: Ohne Jahresdatei gibt es keine Lerngruppen zur Wahl"
                                        : "Vorbedingung: Lerngruppen zur Wahl (Saat mit Jahresdatei)")
            }
            let mitLerngruppen = speicher.tresor != nil && !ohneJahresdatei && !speicher.lerngruppenZurWahl.isEmpty
            // In jeder Lage dasselbe Blatt (Folgejahr, zwei Zeilen): Die Läufe unterscheiden sich nur in der Lage, und ohne
            // Lerngruppen ist die Zeile die Gegenprobe zum Bogen (Z-AT8P-11). Angelegt wird nichts.
            Lernendenprobe.neuePlanungVorbereiten(speicher)
            speicher.neuePlanungOeffnen()
            if await warten(bis: { speicher.offenerDialog == .neuePlanung && haupt.attachedSheet != nil }),
               let neuePlanung = haupt.attachedSheet {
                await vorndran(neuePlanung)
                if mitLerngruppen {
                    await zuordnungsSchritt("Neue Planung · Lerngruppen zuordnen", an: neuePlanung, dialog: .neuePlanung)
                } else {
                    // Ohne Lerngruppen gibt es den Knopf nicht — im Klartext (E631) wie ohne Jahresdatei (E632). Frist
                    // 2 s wie beim Import im Klartext (E350): Das Ausbleiben eines Bogens misst nur eine Frist.
                    speicher.zuordnungsbogenVorgabe = .vorschlag
                    _ = await warten(2) { neuePlanung.attachedSheet != nil }
                    pruefen(neuePlanung.attachedSheet == nil, "Neue Planung · Lerngruppen zuordnen "
                            + (speicher.tresor == nil ? "im Klartext" : "ohne Jahresdatei") + ": Die Vorgabe öffnet keinen Bogen")
                    // Verbraucht wird sie immer — das Blatt beobachtet sie auch ohne Lerngruppen (Z-AT9B-04).
                    pruefen(speicher.zuordnungsbogenVorgabe == nil, "Neue Planung · Lerngruppen zuordnen "
                            + (speicher.tresor == nil ? "im Klartext" : "ohne Jahresdatei") + ": Die Vorgabe ist verbraucht")
                    speicher.zuordnungsbogenVorgabe = nil
                }
            } else {
                pruefen(false, "das Blatt „Neue Planung“ ging für den Bogen „Lerngruppen zuordnen“ nicht auf")
            }
            speicher.alleDialogeSchliessen()
            _ = await warten(4) { haupt.attachedSheet == nil }

            // ── Vorhaben-Blatt: Material wählen ────────────────────────────
            speicher.vorhabenDialog = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
            if await warten(bis: { haupt.attachedSheet != nil }), let vorhaben = haupt.attachedSheet {
                await vorndran(vorhaben)
                var abschluss: [String]? = nil
                await bogenSchritt("Vorhaben-Blatt · Material", an: vorhaben) {
                    Systemzugriff.dateienWaehlen(start: "", zugriff: speicher.zugriff) { abschluss = $0 }
                }
                pruefen(abschluss == [], "Vorhaben-Blatt · Material: Der Abschluss kam, mit leerer Wahl")

                // ── Vorhaben-Blatt: Material von 3ducation.org (v71, E177, E182) ──
                // Ein SwiftUI-Blatt als Bogen: Keine NSButtons, also zählt, was
                // messbar ist — der Bogen hängt am Blatt, seine Breite sagt, ob er
                // die Frage (640) oder die Liste (1000, AW3-neu) zeigt, ⎋ schließt ihn und
                // nimmt den Schalter zurück. Ohne Erlaubnis die Frage; nichts geht
                // ins Netz: Im Prüfstand gibt es ohne MATERIAL_QUELLE keine Quelle.
                @MainActor func materialSchritt(_ name: String, breite: CGFloat) async {
                    speicher.materialblattOffen = true
                    let da = await warten(8) { vorhaben.attachedSheet != nil }
                    guard da, let bogen = vorhaben.attachedSheet else {
                        pruefen(false, "\(name): Innerhalb der Frist ging kein Bogen auf")
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
                    pruefen(!speicher.materialblattOffen, "\(name): Der Schalter ist zurück")
                    if !weg {
                        speicher.materialblattOffen = false
                        weg = await warten(4) { vorhaben.attachedSheet == nil }
                    }
                    pruefen(vorhaben.isVisible, "\(name): Das Blatt steht noch")
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
                                      + (quelle.isEmpty ? ", ohne Quelle)" : ")"), breite: 1000)
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
                    pruefen(imKlick == true, "Vorhaben-Blatt · „Verwerfen“: Gleich nach dem Klick steht das Blatt noch"
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

            // ── Vorhaben-Blatt: die Leiste der Reiter (v85, AW3-neu; E731, E373) ──
            // Vorher ein anderer Reiter: Das Öffnen muss „Grundlegendes“ setzen (E731, Z-AW2b-04). Die Leiste über ihre
            // Segmentzahl (B83: NSSegmentedControl ausgenommen), ein Klick über ihre Aktion wie von Hand. Ein Wort in
            // „Kommentar zum Verlauf“, auf „Links“ und zurück — der Entwurf bleibt. Danach ein zweites Blatt mit
            // Hausaufgabe: „Hausaufgabe ✓“ ist das breiteste Kennzeichen — die Leiste behält ihre Breite (U+2009 an
            // „Grundlegendes“, gemessen 117 zu 116 pt).
            @MainActor func suchen<T: NSView>(_ ansicht: NSView?, _ passt: (T) -> Bool) -> T? {
                guard let ansicht else { return nil }
                if let treffer = ansicht as? T, passt(treffer) { return treffer }
                for kind in ansicht.subviews {
                    if let treffer: T = suchen(kind, passt) { return treffer }
                }
                return nil
            }
            @MainActor func reiterleiste(_ blatt: NSWindow) -> NSSegmentedControl? {
                suchen(blatt.contentView) { (leiste: NSSegmentedControl) in leiste.segmentCount == Vorhabenreiter.allCases.count }
            }
            let name = "Vorhaben-Blatt · Reiter"
            var leistenbreite: CGFloat?
            speicher.vorhabenReiter = .links
            speicher.vorhabenDialog = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
            if await warten(bis: { haupt.attachedSheet != nil }), let blatt = haupt.attachedSheet {
                await vorndran(blatt)
                pruefen(speicher.vorhabenReiter == .grundlegendes, "\(name): beim Öffnen „Grundlegendes“ (E731)")
                @MainActor func kommentarfeld() -> NSTextView? {
                    suchen(blatt.contentView) { (feld: NSTextView) in feld.accessibilityLabel() == "Kommentar zum Verlauf" }
                }
                let leiste = reiterleiste(blatt)
                pruefen(leiste != nil, "\(name): die Leiste mit sieben Reitern")
                if let leiste {
                    leistenbreite = leiste.frame.width
                    let titel = (0..<leiste.segmentCount).map {
                        (leiste.label(forSegment: $0) ?? "").trimmingCharacters(in: .whitespaces)
                    }
                    pruefen(titel == Vorhabenreiter.allCases.map(\.titel) && leiste.selectedSegment == 0,
                            "\(name): \(titel.joined(separator: " · ")), gewählt das erste")
                    // Ein Klick in die Leiste, wie von Hand: auf „Kommentar“.
                    leiste.selectedSegment = 1
                    leiste.sendAction(leiste.action, to: leiste.target)
                    _ = await warten(2) { kommentarfeld() != nil }
                    pruefen(speicher.vorhabenReiter == .kommentar && kommentarfeld() != nil,
                            "\(name): ein Klick in die Leiste wählt „Kommentar“")
                    if let feld = kommentarfeld(), blatt.makeFirstResponder(feld) {
                        feld.insertText("Reiterprobe", replacementRange: feld.selectedRange())
                    }
                    _ = await warten(2) { leiste.label(forSegment: 1) == "Kommentar •" }
                    pruefen(leiste.label(forSegment: 1) == "Kommentar •", "\(name): das Kennzeichen „Kommentar •“ (E373)")
                    speicher.vorhabenReiter = .links
                    _ = await warten(2) { leiste.selectedSegment == 6 }
                    pruefen(leiste.selectedSegment == 6 && kommentarfeld() == nil,
                            "\(name): auf „Links“ — gewählt, kein Kommentarfeld mehr")
                    speicher.vorhabenReiter = .kommentar
                    _ = await warten(2) { kommentarfeld() != nil }
                    pruefen(kommentarfeld()?.string == "Reiterprobe", "\(name): der Kommentar steht — nach „Links“ und zurück")
                }
                // Auf einem anderen Reiter schließen: Das Schließen muss ihn zurücksetzen (Z-AW2b-04).
                speicher.vorhabenReiter = .links
                speicher.vorhabenDialog = nil
                _ = await warten(4) { haupt.attachedSheet == nil }
                pruefen(speicher.vorhabenReiter == .grundlegendes, "\(name): nach dem Schließen wieder „Grundlegendes“")
            } else {
                pruefen(false, "das Vorhaben-Blatt ging für die Reiter nicht auf")
            }
            if let leistenbreite {
                var mitHausaufgabe = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
                mitHausaufgabe.hausaufgabe = true
                speicher.vorhabenDialog = mitHausaufgabe
                // In derselben Frist auf die Leiste warten, nicht nur aufs Blatt — eine Ursache, ein ✗ (Z-AW3n-08).
                _ = await warten(bis: { haupt.attachedSheet.flatMap(reiterleiste) != nil })
                if let blatt = haupt.attachedSheet, let leiste = reiterleiste(blatt) {
                    await vorndran(blatt)
                    pruefen(leiste.label(forSegment: 4) == "Hausaufgabe ✓"
                            && abs(leiste.frame.width - leistenbreite) < 0.5,
                            "\(name): „\(leiste.label(forSegment: 4) ?? "")“ — die Leiste behält ihre Breite "
                            + "(\(Int(leistenbreite)) → \(Int(leiste.frame.width)) pt)")
                } else {
                    pruefen(false, haupt.attachedSheet == nil ? "\(name): das Blatt mit Hausaufgabe ging nicht auf"
                                                              : "\(name): das Blatt mit Hausaufgabe steht, ohne Leiste")
                }
                speicher.vorhabenDialog = nil
                _ = await warten(4) { haupt.attachedSheet == nil }
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

            // ── ⌘O mit einer fremden Planung: der Bogen „Lerngruppen zuordnen“ (v84, AT8, E628) ──
            // Am Ende, damit der Import keinen früheren Schritt berührt; ⎋ bricht ab wie von Hand — nichts geöffnet,
            // die Planung bleibt.
            if mitLerngruppen {
                let erstelltVorher = speicher.planung?.erstellt
                await Lernendenprobe.schuljahrOeffnenVorbereiten(speicher)
                if await warten(bis: { speicher.offenerDialog == .schuljahrOeffnen && haupt.attachedSheet != nil }),
                   let oeffnen = haupt.attachedSheet {
                    await vorndran(oeffnen)
                    await zuordnungsSchritt("⌘O · Lerngruppen zuordnen", an: oeffnen, dialog: .schuljahrOeffnen,
                                            steht: { speicher.schuljahrwechsel != nil })
                    // ⎋ nur an einem Blatt, das noch hängt (Z-AT8P-13) — sonst bleibt das Aufräumen unten.
                    if haupt.attachedSheet === oeffnen {
                        await vorndran(oeffnen)
                        tasteAn(oeffnen, "\u{1B}", code: 53)
                    }
                    let zu = await warten(4) { haupt.attachedSheet == nil && speicher.schuljahrwechsel == nil }
                    pruefen(zu && speicher.planung?.erstellt == erstelltVorher, "⌘O · ⎋: Nichts geöffnet, die Planung bleibt")
                    if !zu {
                        speicher.schuljahrOeffnenAbbrechen()
                        speicher.alleDialogeSchliessen()
                        _ = await warten(4) { haupt.attachedSheet == nil }
                    }
                } else {
                    pruefen(false, "das Blatt „Neues Schuljahr öffnen“ ging für den Bogen „Lerngruppen zuordnen“ nicht auf")
                    // Kommt es verspätet, hinge es im ⌘Q-Schritt — darum hier zurück (Z-AT8P-02).
                    fensterlage("⌘O · Lerngruppen zuordnen: Fensterlage")
                    speicher.schuljahrOeffnenAbbrechen()
                    speicher.alleDialogeSchliessen()
                    _ = await warten(4) { haupt.attachedSheet == nil }
                }
            }

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
                pruefen(false, "E329 nicht gemessen: Weder Hauptweg noch Zusatz fand das Fenster mit Frage im Dock")
            }

            await ende()
        }
    }

    /// Die gemerkte Größe der Finder-Blätter (E627): im Aufbau und vor jedem Schritt groß vorgegeben, der Sichern-Dialog
    /// aufgeklappt (Z-AW1-01); am Ende und an der Reißleine wieder wie vorher — die übrigen Läufe der Runde teilen den
    /// Container der Probe. Der Vorher-Stand nur aus dem eigenen Bereich der App, nicht aus den systemweiten
    /// Einstellungen (Z-AW1-05).
    static let groessenSchluessel = ["NSNavPanelExpandedSizeForOpenMode", "NSNavPanelExpandedSizeForSaveMode"]
    static let aufgeklapptSchluessel = "NSNavPanelExpandedStateForSaveMode"
    static let grosseBreite: CGFloat = 1400
    static let grosseGroesse = "{\(Int(grosseBreite)), 600}"
    static var gemerktVorher: [Any?]?

    static func grossVorgeben() {
        let schluessel = groessenSchluessel + [aufgeklapptSchluessel]
        if gemerktVorher == nil {
            let eigen = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            gemerktVorher = schluessel.map { eigen?[$0] }
        }
        for s in groessenSchluessel { UserDefaults.standard.set(grosseGroesse, forKey: s) }
        UserDefaults.standard.set(true, forKey: aufgeklapptSchluessel)
    }

    static var grossVorgegeben: Bool {
        groessenSchluessel.allSatisfy { UserDefaults.standard.string(forKey: $0) == grosseGroesse }
            && UserDefaults.standard.bool(forKey: aufgeklapptSchluessel)
    }

    /// Wieder wie vorher — mehrfach aufrufbar (Z-AW1-06).
    static func gemerktZuruecksetzen() {
        guard let vorher = gemerktVorher else { return }
        for (s, wert) in zip(groessenSchluessel + [aufgeklapptSchluessel], vorher) {
            if let wert { UserDefaults.standard.set(wert, forKey: s) }
            else { UserDefaults.standard.removeObject(forKey: s) }
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
