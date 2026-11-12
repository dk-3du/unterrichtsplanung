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
    /// Vorhaben-Blatt → die Leiste mit sieben Einträgen, beim Öffnen „Grundlegendes“ (E731) und die Schreibmarke im Titel
    /// (Z-AW3n-06), 980 × 820 (E1103; auf kleinem Bildschirm niedriger, E1150), Wahl per Klick wie von Hand, der Entwurf
    /// bleibt, das Kennzeichen als Plakette
    /// (E373, E1105), im Baum der Bedienungshilfen je Zeile eine Zelle mit Namen, ↑/↓ und Tippen eines Namens, blau nur mit
    /// dem Fokus der Leiste, ⌘[ und ⌘] (E1102), 66 Wechsel ohne Sprung einer Zeile (E1120); mit „Hausaufgabe“ geöffnet die
    /// Schreibmarke in deren Zeile und der Name ganz zu sehen neben der Plakette (v95; vorher die Reiter, v85, AW3-neu), mit
    /// Prüfung ein getippter Tag über den Sprung nach abgewiesenem „Übernehmen“ (E374, R-BG8n-03),
    /// Einstellungen → die Leiste mit sechs Einträgen, 780 × 640 (E1121), beim Öffnen „Zeitraum“ — auch nach einem anderen
    /// Eintrag (E1126) —, der Inhalt folgt der Wahl, ein getippter Tag übersteht den Wechsel, 66 Wechsel ohne Sprung,
    /// ⌘K → die Leiste mit drei Einträgen, 980 × 820 (E1136), beim Öffnen „Klassen/Kurse“ — auch nach „Farbe wählen“ und
    /// nach einem anderen Eintrag (E1133) —, der Inhalt folgt der Wahl, ein getippter Name übersteht den Wechsel, ein
    /// umbenanntes Fach ⌘[ (R-BG8-W2-01); die Rückwege aus ⌘L und dem Sitzplan-Editor von „Lernende“ bzw. „Fachfarben“ aus
    /// wieder auf „Klassen/Kurse“ (R-BG8-W2-02), die Höhe der Blätter am Fenster gemessen (E1150) und am verschobenen
    /// Hauptfenster auf kleinem Bildschirm (Vorhaben-Blatt und ⌘K 660, Einstellungen 640, Material-Bogen 580; ragt das
    /// Fenster unter den Rand, steht das Blatt mittig; die Verschlüsselung 744 breit, E1156, und ebenso begrenzt, E1154),
    /// seit v96 (BH3, E1166) dazu: die Plakette nach einem Klick mit getipptem Kommentar, ein ungültig getippter Tag, ↓/↑
    /// in der Leiste, der Material-Bogen über einem getippten Tag, ⌘Z nach dem Wechsel und ein Blatt am minimierten
    /// Hauptfenster (R-BG8bn-06); seit v96 (BH4, E1192) auch der Sitzplan-Editor: in voller Höhe rollt nichts, auch nach
    /// einer Änderung; am verschobenen Hauptfenster 820 breit, Höhe und Lage nach dem Muster, die Fläche in der Rollfläche
    /// erreichbar, die Höhe des Körpers (mindestens der Ausschnitt) als Auskunft (Fläche und Namensliste);
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
        // v85 (E735): Der Lauf mit Verschlüsselung brauchte mit E518 85 s. 180 s seit
        // v95 (E1143): Drei Blätter mit Leiste prüfen je 66 Klicks wie von Hand. 210 s seit BG8b (E1155): Mit dem
        // kleinen Bildschirm braucht der Lauf mit Verschlüsselung rund 160 s, seit v96 (BH4) 176 s — 34 s Reserve,
        // mindestens 30 s (R-BG8bn2-08, R-BH4-06, gemessen 10.11.2026). 225 s seit BH5 (E1173): dazu das Blatt „Lernende“
        // an beiden Lagen des kleinen Bildschirms, rund 8 s.
        let reissleine = Task { @MainActor in
            try? await Task.sleep(for: .seconds(225))
            // `try?` schluckt das Abbrechen aus `ende()` — ohne diese Zeile risse sie dort doch noch (E423).
            guard !Task.isCancelled else { return }
            print("DIALOGTEST REISSLEINE — Frist verstrichen, alles Offene wird geschlossen ✗")
            fflush(stdout)
            allesSchliessen()
            gemerktZuruecksetzen()
            // Lag das Hauptfenster für den kleinen Bildschirm verschoben, zurück an seinen Platz — vor und nach der Pause,
            // falls der Prüfablauf es dazwischen noch einmal legt (R-BG8bn-04, R-BG8bn2-01).
            if let rahmen = hauptfensterVorher { hauptfensterVerschoben?.setFrame(rahmen, display: true) }
            try? await Task.sleep(for: .milliseconds(500))
            if let rahmen = hauptfensterVorher { hauptfensterVerschoben?.setFrame(rahmen, display: true) }
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
            // In voller Höhe passt der Körper ohne Rollen, auch mit Datenschutzhinweis — die Bedienung steht hinter dem ⓘ
            // (E1191, E1192). Ist das Blatt niedriger (kleiner Bildschirm), entfällt die Zeile mit einer Auskunft.
            if let flaeche = Self.sitzplanansicht(editor), let rolle = flaeche.enclosingScrollView,
               let inhalt = rolle.documentView {
                let hoch = Int(inhalt.frame.height.rounded()), sichtbar = Int(rolle.contentView.bounds.height.rounded())
                // Der Körper ist mit Absicht genau so hoch wie sichtbar — darum auf 0,5 pt, nicht auf ganze Punkte (R-BH4N-04).
                let passt = inhalt.frame.height <= rolle.contentView.bounds.height + 0.5
                let balken = (rolle.verticalScroller?.isHidden ?? true) || !rolle.hasVerticalScroller ? "kein Rollbalken"
                    : "Rollbalken steht"
                if editor.contentRect(forFrameRect: editor.frame).height >= 699.5 {
                    pruefen(passt, "Sitzplan-Editor in voller Höhe (700): der Körper \(hoch) hoch, sichtbar \(sichtbar), "
                            + "\(balken) — nichts rollt (E1191)")
                    // Nach einer Änderung bleibt der Knopf im Datenschutzhinweis kurz (E1198; bis dahin „Übernehmen und
                    // Verschlüsselung einrichten …“, dreizeiliger Hinweis) — auch dann rollt nichts (R-BH4-02). Tab wählt
                    // einen Tisch, → schiebt ihn um 8 pt, ← zurück — danach gleicht der Entwurf wieder dem gespeicherten Plan.
                    if speicher.verschluesselungsstand == .aus {
                        if let vorher = speicher.sitzplanEntwurf, editor.makeFirstResponder(flaeche) {
                            Self.tastePosten(editor, "\t", code: 48)
                            Self.tastePosten(editor, "\u{F703}", code: 124)
                            let geaendert = await warten(2, bis: { speicher.sitzplanEntwurf != vorher })
                            // Uhr (Dialogprobe): Ein breiterer Knopf stünde erst im nächsten Durchgang — erst dann messen
                            // (Wache gegen die Rückkehr des langen Wortlauts, G597).
                            _ = await warten(0.3, bis: { false })
                            editor.contentView?.layoutSubtreeIfNeeded()
                            let nachher = Int(inhalt.frame.height.rounded())
                            let sichtNachher = Int(rolle.contentView.bounds.height.rounded())
                            pruefen(geaendert && inhalt.frame.height <= rolle.contentView.bounds.height + 0.5,
                                    "Sitzplan-Editor in voller Höhe, nach einer Änderung (der Knopf im Hinweis bleibt kurz, "
                                    + "E1198): der Körper \(nachher) hoch, sichtbar \(sichtNachher) — nichts rollt (R-BH4-02)"
                                    + (geaendert ? "" : " — die Änderung kam nicht an"))
                            Self.tastePosten(editor, "\u{F702}", code: 123)
                            pruefen(await warten(2, bis: { speicher.sitzplanEntwurf == vorher }),
                                    "Sitzplan-Editor: ← schiebt den Tisch zurück — der Entwurf gleicht wieder dem gespeicherten "
                                    + "Plan (R-BH4N-01)")
                            editor.makeFirstResponder(nil)
                        } else {
                            pruefen(false, "Sitzplan-Editor: ohne Entwurf, oder die Fläche nahm die Tastatur nicht an — der "
                                    + "Schritt nach einer Änderung entfällt (R-BH4N-01)")
                        }
                    }
                } else {
                    print("  Auskunft Sitzplan-Editor: niedriger als 700 — der Körper \(hoch) hoch, sichtbar \(sichtbar)")
                    fflush(stdout)
                }
            } else {
                pruefen(false, "Sitzplan-Editor: die Fläche liegt in keiner Rollfläche (E1158)")
            }

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
                        // Vorher auf „Lernende“, wo der Knopf steht — sonst stünde ⌘K schon auf dem Startwert, und
                        // „zurück auf Klassen/Kurse“ könnte nicht rot werden (R-BG8-W2-02).
                        _ = await warten(2) { Self.seitenleisteIn(haupt.attachedSheet)?.numberOfRows == 3 }
                        let klickLernende = Self.seitenleisteIn(haupt.attachedSheet).map { Self.zeileKlicken($0, 0) }
                            ?? "keine Leiste"
                        _ = await warten(2) { Self.leistenwahl(haupt.attachedSheet) == 0 }
                        let vonLernende = Self.leistenwahl(haupt.attachedSheet) == 0
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
                        if zurueck {
                            _ = await warten(2) { Self.leistenwahl(haupt.attachedSheet) == 1 }
                            pruefen(vonLernende && Self.leistenwahl(haupt.attachedSheet) == 1,
                                    "Klassen-Blatt · \(weg.name) im Blatt „Lernende“: von „Lernende“ aus zurück auf "
                                    + "„Klassen/Kurse“ (E1133)"
                                    + (vonLernende ? "" : " — vorher nicht auf „Lernende“\(klickLernende.map { ": \($0)" } ?? "")")
                                    + " — danach Zeile \(Self.leistenwahl(haupt.attachedSheet) + 1)")
                        }
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
                                // Auskunft: Die Schritte davor schlossen den Dialog am Klassen-Blatt — gemerkt ist seither die
                                // dort gesetzte Breite (bis v94 am Blatt von 800 gemessen {924, 600}, E712; seit v95 misst ⌘K
                                // 980, E1136); `bogenSchritt` gibt wieder die große vor.
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
                    // Vorher auf „Fachfarben“ — sonst stünde ⌘K schon auf dem Startwert (R-BG8-W2-02).
                    _ = await warten(2) { Self.seitenleisteIn(haupt.attachedSheet)?.numberOfRows == 3 }
                    let klickFachfarben = Self.seitenleisteIn(haupt.attachedSheet).map { Self.zeileKlicken($0, 2) }
                        ?? "keine Leiste"
                    _ = await warten(2) { Self.leistenwahl(haupt.attachedSheet) == 2 }
                    let vonFachfarben = Self.leistenwahl(haupt.attachedSheet) == 2
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
                    if zurueck {
                        _ = await warten(2) { Self.leistenwahl(haupt.attachedSheet) == 1 }
                        pruefen(vonFachfarben && Self.leistenwahl(haupt.attachedSheet) == 1,
                                "Klassen-Blatt · ⎋ im Sitzplan-Editor (\(runde). Mal): von „Fachfarben“ aus zurück auf "
                                + "„Klassen/Kurse“ (E1133)"
                                + (vonFachfarben ? "" : " — vorher nicht auf „Fachfarben“\(klickFachfarben.map { ": \($0)" } ?? "")")
                                + " — danach Zeile \(Self.leistenwahl(haupt.attachedSheet) + 1)")
                    }
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
                // die Frage (640) oder die Liste (900 × 740, E1108) zeigt, ⎋ schließt ihn und
                // nimmt den Schalter zurück. Ohne Erlaubnis die Frage; nichts geht
                // ins Netz: Im Prüfstand gibt es ohne MATERIAL_QUELLE keine Quelle.
                @MainActor func materialSchritt(_ name: String, breite: CGFloat, hoehe: CGFloat? = nil) async {
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
                    if let hoehe {
                        let innen = bogen.contentRect(forFrameRect: bogen.frame).height
                        pruefen(abs(innen - hoehe) <= 1, "\(name): Höhe \(Int(innen)) (Blatt − 80 = \(Int(hoehe)), E1108, E1150)")
                    }
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
                                      + (quelle.isEmpty ? ", ohne Quelle)" : ")"), breite: 900,
                                      hoehe: vorhaben.contentRect(forFrameRect: vorhaben.frame).height - 80)
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

            // ── Vorhaben-Blatt: die Leiste (v95, E1101–E1111, E1120; vorher die Reiter, v85, E731, E373) ──
            // Die Leiste ist eine Tabelle mit fester Zeilenhöhe, Kennung „Seitenleiste“ (E1120). Vorher ein anderer
            // Eintrag: Das Öffnen muss „Grundlegendes“ setzen (E731). Gewählt wird per Klick wie von Hand — ein Ereignis an
            // die Mitte der Zeile, das die Tabelle trifft: Fokus, Betonung und Verfolgen der Maus wie am Bildschirm; nur so
            // sprangen die Zeilen der früheren Liste (E1120). Ein Wort in „Kommentar zum Verlauf“, auf „Links“ und zurück
            // über die Bindung — der Entwurf bleibt, die Leiste folgt; das Kennzeichen steht als Plakette im Namen der
            // Zeile (E373, E1105), im Baum der Bedienungshilfen gelesen (R-BG5-11). ↑ und ↓ wählen in der Leiste, ebenso das
            // Tippen eines Namens; gewählt blau nur mit ihrem Fokus (E1120). ⌘[ und ⌘] gehen im Verlauf zurück und vor
            // (E1102, R-BG5-02). Beim Öffnen steht die Schreibmarke im Titel, mit „Hausaufgabe“ in deren Zeile (Z-AW3n-06,
            // R-BG5-03). Das Blatt ist 980 breit und 820 hoch (E1103), auf kleinem Bildschirm niedriger (E1150). Danach
            // „Leiste ruhig“ (`leisteRuhig`).
            @MainActor func suchen<T: NSView>(_ ansicht: NSView?, _ passt: (T) -> Bool) -> T? {
                guard let ansicht else { return nil }
                if let treffer = ansicht as? T, passt(treffer) { return treffer }
                for kind in ansicht.subviews {
                    if let treffer: T = suchen(kind, passt) { return treffer }
                }
                return nil
            }
            @MainActor func seitenleiste(_ blatt: NSWindow) -> NSTableView? {
                suchen(blatt.contentView) { (tabelle: NSTableView) in tabelle.identifier?.rawValue == "Seitenleiste" }
            }
            /// Der Name der Zeile für Bedienungshilfen — mit der Plakette, durch Komma getrennt.
            @MainActor func zeilenname(_ tabelle: NSTableView, _ zeile: Int) -> String {
                tabelle.view(atColumn: 0, row: zeile, makeIfNecessary: true)?.accessibilityLabel() ?? ""
            }
            /// Ein Klick auf die Mitte der Zeile, wie von Hand: Maus nieder und auf an das Fenster der Tabelle. Trifft der
            /// Punkt nicht die Tabelle, kein Klick — nur der Grund; sonst träfe er, was darüber liegt (R-BG5-04).
            @MainActor func klicken(_ tabelle: NSTableView, _ zeile: Int) async -> String? {
                Self.zeileKlicken(tabelle, zeile)
            }
            /// Eine Taste an das Fenster, wie getippt: ein Buchstabe für das Tippen eines Namens, mit `befehl` ein Kürzel
            /// (⌘[ Tastencode 33, ⌘] 30).
            @MainActor func taste(_ fenster: NSWindow, _ zeichen: String, code: UInt16, befehl: Bool = false) {
                if let ereignis = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: befehl ? [.command] : [],
                                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: fenster.windowNumber, context: nil, characters: zeichen,
                                                   charactersIgnoringModifiers: zeichen, isARepeat: false, keyCode: code) {
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }
            /// Der Name einer Zeile, wie ihn die Bedienungshilfen lesen: ab den Zeilen der Tabelle (`accessibilityRows`)
            /// über die Attribute — je Zeile „AXRow“ mit genau einer „AXCell“ und ihrer Beschreibung (R-BG5-11). Geprüft
            /// ist die Gestalt Zeile → Zelle; ob die Leiste vom Fenster aus erreicht wird, zeigt die Handprobe mit
            /// VoiceOver (R-BG5n-01).
            @MainActor func baumname(_ tabelle: NSTableView, _ zeile: Int) -> String {
                // Die Zeilen des Baums sind Stellvertreter (`NSTableRow`), die nur die Attribute der Bedienungshilfen
                // beantworten — gelesen wie ein Client: „AXChildren“, „AXRole“, „AXDescription“. Über den Selektor, nicht
                // über die veraltete Methode selbst.
                @MainActor func attribut(_ element: Any, _ name: String) -> Any? {
                    let wahl = NSSelectorFromString("accessibilityAttributeValue:")
                    guard let objekt = element as? NSObject, objekt.responds(to: wahl) else { return nil }
                    return objekt.perform(wahl, with: name)?.takeUnretainedValue()
                }
                let reihen = tabelle.accessibilityRows() ?? []
                guard zeile < reihen.count else { return "keine Zeile \(zeile + 1) im Baum (Zeilen \(reihen.count))" }
                let reihe = reihen[zeile]
                let rolle = attribut(reihe, "AXRole") as? String ?? "keine Rolle"
                let kinder = attribut(reihe, "AXChildren") as? [Any] ?? []
                let namen = kinder.map { kind -> String in
                    "\(attribut(kind, "AXRole") as? String ?? "?"): \(attribut(kind, "AXDescription") as? String ?? "")"
                }
                return rolle == "AXRow" && namen.count == 1 && namen[0].hasPrefix("AXCell: ")
                    ? String(namen[0].dropFirst("AXCell: ".count))
                    : "\(rolle) mit \(namen.isEmpty ? "keinen Kindern" : namen.joined(separator: " | "))"
            }
            /// Das Feld mit der Schreibmarke: der Feldeditor vorn im Blatt und sein Textfeld; sein Platzhalter.
            @MainActor func schreibmarke(_ blatt: NSWindow) -> String {
                guard let editor = blatt.firstResponder as? NSTextView else {
                    return "keine Schreibmarke (vorn: \(blatt.firstResponder.map { "\(type(of: $0))" } ?? "nichts"))"
                }
                guard editor.isFieldEditor, let feld = editor.delegate as? NSTextField else { return "ein Textbereich" }
                return feld.placeholderString ?? feld.placeholderAttributedString?.string ?? "Feld ohne Platzhalter"
            }
            /// Eine Pfeiltaste an das Fenster der Tabelle (↓ 125, ↑ 126).
            @MainActor func pfeil(_ tabelle: NSTableView, runter: Bool) {
                guard let fenster = tabelle.window,
                      let skalar = UnicodeScalar(UInt32(runter ? NSDownArrowFunctionKey : NSUpArrowFunctionKey)) else { return }
                let zeichen = String(Character(skalar))
                if let ereignis = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: fenster.windowNumber, context: nil, characters: zeichen,
                                                   charactersIgnoringModifiers: zeichen, isARepeat: false,
                                                   keyCode: runter ? 125 : 126) {
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }
            /// Wo jede Zeile steht, in Fensterkoordinaten: der Rahmen der Tabelle für die Zeile, ihre Zeilenansicht und
            /// ihre Zelle; dazu Rahmen und Versatz des Rollbereichs. Nicht angelegt heißt `.null` — anders als jede Lage.
            @MainActor func zeilenlage(_ tabelle: NSTableView) -> [CGRect] {
                // Auf 0,01 pt gerundet: Das Umrechnen in Fensterkoordinaten rauscht um 1e-13; das Wobbeln, das der Fall
                // fangen soll, waren 0,5 pt.
                func gerundet(_ r: CGRect) -> CGRect {
                    r.isNull ? r : CGRect(x: (r.minX * 100).rounded() / 100, y: (r.minY * 100).rounded() / 100,
                                          width: (r.width * 100).rounded() / 100, height: (r.height * 100).rounded() / 100)
                }
                return roheLage(tabelle).map(gerundet)
            }
            @MainActor func roheLage(_ tabelle: NSTableView) -> [CGRect] {
                var lage: [CGRect] = []
                for zeile in 0..<tabelle.numberOfRows {
                    lage.append(tabelle.convert(tabelle.rect(ofRow: zeile), to: nil))
                    lage.append(tabelle.rowView(atRow: zeile, makeIfNecessary: false).map { $0.convert($0.bounds, to: nil) } ?? .null)
                    lage.append(tabelle.view(atColumn: 0, row: zeile, makeIfNecessary: false).map { $0.convert($0.bounds, to: nil) } ?? .null)
                }
                if let rolle = tabelle.enclosingScrollView {
                    lage.append(rolle.convert(rolle.bounds, to: nil))
                    lage.append(CGRect(origin: rolle.contentView.bounds.origin, size: .zero))
                }
                return lage
            }
            /// Die Höhen aus den Zeilenansichten selbst — was steht, nicht was die Tabelle rechnet.
            @MainActor func zeilenhoehen(_ tabelle: NSTableView) -> [CGFloat] {
                (0..<tabelle.numberOfRows).map { tabelle.rowView(atRow: $0, makeIfNecessary: false)?.frame.height ?? -1 }
            }
            /// „Leiste ruhig“ (E1120): 66 Wechsel per Klick, darunter zehnmal `a` ↔ `b` (beim Vorhaben-Blatt Material ↔
            /// Links: dort sprangen die Zeilen der Liste); nach jedem Klick, sobald die Wahl angekommen ist, und nach zwei
            /// weiteren Pausen steht jede Zeile an ihrer Stelle und ist 32 pt hoch, die Wahl ist die geklickte. Nach drei
            /// Klicks daneben oder ohne Wirkung bricht der Fall ab — mit Grund, ehe die Reißleine reißt (R-BG5-04).
            @MainActor func leisteRuhig(_ tabelle: NSTableView, _ name: String, a: Int, b: Int,
                                        angekommen: @escaping @MainActor (Int) -> Bool) async {
                let zeilen = tabelle.numberOfRows
                guard zeilen > max(a, b) else {
                    pruefen(false, "\(name) ruhig: nur \(zeilen) Zeilen — so misst der Fall nichts")
                    return
                }
                let alleDa = (0..<zeilen).allSatisfy { tabelle.rowView(atRow: $0, makeIfNecessary: false) != nil }
                    && tabelle.visibleRect.insetBy(dx: -0.5, dy: -0.5).contains(tabelle.rect(ofRow: 0).union(tabelle.rect(ofRow: zeilen - 1)))
                guard alleDa else {
                    let fehlen = (0..<zeilen).filter { tabelle.rowView(atRow: $0, makeIfNecessary: false) == nil }
                    pruefen(false, "\(name) ruhig: nicht alle Zeilen angelegt und sichtbar — so misst der Fall nichts "
                            + "(ohne Zeilenansicht \(fehlen), sichtbar \(tabelle.visibleRect), Zeilen "
                            + "\(tabelle.rect(ofRow: 0).union(tabelle.rect(ofRow: zeilen - 1))))")
                    return
                }
                var folge = [a]
                for _ in 0..<10 { folge += [b, a] }
                var saat: UInt64 = 95
                while folge.count < 66 {
                    saat = saat &* 6364136223846793005 &+ 1442695040888963407
                    let zeile = Int((saat >> 33) % UInt64(zeilen))
                    if zeile != folge.last { folge.append(zeile) }
                }
                let bezug = zeilenlage(tabelle)
                var abweichend: [String] = []
                var verfehlt: [String] = []
                var ohneWirkung = 0
                var abbruch: Int?
                for (stelle, zeile) in folge.enumerated() {
                    if let fehler = await klicken(tabelle, zeile) {
                        verfehlt.append("Klick \(stelle + 1): \(fehler)")
                    } else {
                        let da = await warten(2) { angekommen(zeile) && tabelle.selectedRow == zeile }
                        if !da { ohneWirkung += 1 }
                    }
                    for pause in [0, 40, 120] {
                        if pause > 0 { try? await Task.sleep(for: .milliseconds(pause)) }  // Uhr: Anordnen und Zeichnen abwarten
                        let jetzt = zeilenlage(tabelle)
                        if (jetzt != bezug || tabelle.selectedRow != zeile), abweichend.count < 4 {
                            // Was sich bewegt hat: je Zeile Rahmen, Zeilenansicht, Zelle; dahinter Rollbereich und Versatz.
                            let arten = ["Zeile", "Zeilenansicht", "Zelle"]
                            let stelleAb = zip(jetzt, bezug).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                            let was = stelleAb.map { i in
                                (i < zeilen * 3 ? "\(arten[i % 3]) \(i / 3 + 1)" : (i == zeilen * 3 ? "Rollbereich" : "Versatz"))
                                    + " \(bezug[i]) → \(jetzt[i])"
                            } ?? (jetzt.count != bezug.count ? "Zahl \(bezug.count) → \(jetzt.count)" : "Wahl \(tabelle.selectedRow + 1)")
                            abweichend.append("Klick \(stelle + 1) → Zeile \(zeile + 1), +\(pause) ms: \(was)")
                        }
                    }
                    if verfehlt.count + ohneWirkung >= 3 {
                        abbruch = stelle + 1
                        break
                    }
                }
                let hoehen = Set(zeilenhoehen(tabelle))
                pruefen(abweichend.isEmpty && verfehlt.isEmpty && ohneWirkung == 0 && hoehen == [32],
                        "\(name) ruhig: \(abbruch.map { "abgebrochen nach Klick \($0) von \(folge.count)" } ?? "\(folge.count) Klicks") — "
                        + (abweichend.isEmpty ? "jede Zeile, Zelle und der Rollbereich in jeder Aufnahme an ihrer Stelle"
                                              : "verschoben: " + abweichend.joined(separator: "; "))
                        + (verfehlt.isEmpty ? "" : "; " + verfehlt.joined(separator: "; "))
                        + (ohneWirkung > 0 ? ", \(ohneWirkung) Klicks ohne Wirkung" : "")
                        + ", Höhen der Zeilenansichten \(hoehen.sorted())")
            }
            let name = "Vorhaben-Blatt · Leiste"
            speicher.vorhabenReiter = .links
            speicher.vorhabenDialog = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
            if await warten(bis: { haupt.attachedSheet != nil }), let blatt = haupt.attachedSheet {
                await vorndran(blatt)
                pruefen(speicher.vorhabenReiter == .grundlegendes, "\(name): beim Öffnen „Grundlegendes“ (E731)")
                let groesse = blatt.contentRect(forFrameRect: blatt.frame).size
                let hoeheV = Self.blatthoehe(blatt, bestellt: 820)
                pruefen(abs(groesse.width - 980) < 0.5 && hoeheV.gilt,
                        "\(name): das Blatt ist \(Int(groesse.width)) breit (980, E1103) und \(hoeheV.text)")
                // Die Schreibmarke beim Öffnen im Titel (Z-AW3n-06) — nicht in der Leiste, die selbst Fokus nehmen kann.
                _ = await warten(2) { schreibmarke(blatt).contains("Stoffe und ihre Eigenschaften") }
                pruefen(schreibmarke(blatt).contains("Stoffe und ihre Eigenschaften"),
                        "\(name): beim Öffnen die Schreibmarke im Titel (Z-AW3n-06): \(schreibmarke(blatt))")
                @MainActor func kommentarfeld() -> NSTextView? {
                    suchen(blatt.contentView) { (feld: NSTextView) in feld.accessibilityLabel() == "Kommentar zum Verlauf" }
                }
                _ = await warten(2) { seitenleiste(blatt) != nil }
                if let tabelle = seitenleiste(blatt), tabelle.numberOfRows == Vorhabenreiter.allCases.count {
                    let namen = (0..<tabelle.numberOfRows).map { zeilenname(tabelle, $0) }
                    pruefen(namen == Vorhabenreiter.allCases.map(\.titel) && tabelle.selectedRow == 0,
                            "\(name): \(namen.joined(separator: " · ")), gewählt der erste, ohne Plaketten im neuen Vorhaben")
                    pruefen(Set(zeilenhoehen(tabelle)) == [32], "\(name): jede Zeile 32 pt hoch (E1120): \(zeilenhoehen(tabelle))")
                    // Bedienungshilfen: die Leiste als Tabelle oder Liste, je Zeile ein Element mit dem Namen der Zeile, kein
                    // Name abgeschnitten.
                    let rolle = tabelle.accessibilityRole()
                    let zellen = (0..<tabelle.numberOfRows).compactMap { tabelle.view(atColumn: 0, row: $0, makeIfNecessary: true) }
                    let abgeschnitten = zellen.compactMap { ($0 as? NSTableCellView)?.textField }
                        .filter { $0.intrinsicContentSize.width > $0.frame.width + 0.5 }.map(\.stringValue)
                    let imBaum = (0..<tabelle.numberOfRows).map { baumname(tabelle, $0) }
                    pruefen(rolle.map { [.table, .list, .outline].contains($0) } == true && zellen.count == tabelle.numberOfRows
                            && imBaum == namen && abgeschnitten.isEmpty,
                            "\(name): Bedienungshilfen — Rolle \(rolle?.rawValue ?? "keine"), je Zeile eine Zelle mit dem Namen "
                            + "im Baum (\(imBaum.joined(separator: " · ")))"
                            + (abgeschnitten.isEmpty ? ", kein Name abgeschnitten" : ", abgeschnitten: \(abgeschnitten)"))
                    // Der Titel oben in der Leiste (E1104) zeigt das Abbild 11-vorhaben-grundlegendes und die Handprobe: Im
                    // Baum der Bedienungshilfen dieses Prozesses ist der Text von SwiftUI nicht zu finden (R-BG4-05).
                    // Eine Wahl in der Leiste per Klick: auf „Kommentar“.
                    let verfehlt = await klicken(tabelle, 1)
                    _ = await warten(2) { kommentarfeld() != nil }
                    pruefen(verfehlt == nil && speicher.vorhabenReiter == .kommentar && kommentarfeld() != nil,
                            "\(name): ein Klick in die Leiste zeigt „Kommentar“" + (verfehlt.map { " — \($0)" } ?? ""))
                    if let feld = kommentarfeld(), blatt.makeFirstResponder(feld) {
                        feld.insertText("Reiterprobe", replacementRange: feld.selectedRange())
                    }
                    _ = await warten(2) { zeilenname(tabelle, 1) == "Kommentar, •" && baumname(tabelle, 1) == "Kommentar, •" }
                    pruefen(zeilenname(tabelle, 1) == "Kommentar, •" && baumname(tabelle, 1) == "Kommentar, •",
                            "\(name): das Kennzeichen als Plakette an „Kommentar“ (E373, E1105), im Baum: „\(baumname(tabelle, 1))“")
                    _ = await klicken(tabelle, 6)
                    _ = await warten(2) { speicher.vorhabenReiter == .links && kommentarfeld() == nil }
                    pruefen(speicher.vorhabenReiter == .links && tabelle.selectedRow == 6 && kommentarfeld() == nil,
                            "\(name): auf „Links“ — gewählt, kein Kommentarfeld mehr")
                    speicher.vorhabenReiter = .kommentar
                    _ = await warten(2) { kommentarfeld() != nil && tabelle.selectedRow == 1 }
                    pruefen(tabelle.selectedRow == 1 && kommentarfeld()?.string == "Reiterprobe",
                            "\(name): über die Bindung zurück — die Leiste folgt, der Kommentar steht")
                    // ↑ und ↓ in der Leiste; gewählt blau nur mit ihrem Fokus (E1120).
                    _ = blatt.makeFirstResponder(tabelle)
                    pfeil(tabelle, runter: true)
                    _ = await warten(2) { speicher.vorhabenReiter == .pruefung && tabelle.selectedRow == 2 }
                    let betont = tabelle.rowView(atRow: 2, makeIfNecessary: false)?.isEmphasized == true
                    pfeil(tabelle, runter: false)
                    _ = await warten(2) { speicher.vorhabenReiter == .kommentar && tabelle.selectedRow == 1 }
                    pruefen(tabelle.selectedRow == 1 && speicher.vorhabenReiter == .kommentar && betont,
                            "\(name): ↓ wählt „Prüfung“, betont mit dem Fokus der Leiste, ↑ zurück auf „Kommentar“")
                    // Einen Namen tippen wählt ihn (R-BG5-11): „h“ → „Hausaufgabe“, der einzige Eintrag mit H.
                    taste(blatt, "h", code: 4)
                    _ = await warten(2) { speicher.vorhabenReiter == .hausaufgabe && tabelle.selectedRow == 4 }
                    pruefen(speicher.vorhabenReiter == .hausaufgabe && tabelle.selectedRow == 4,
                            "\(name): „h“ getippt wählt „Hausaufgabe“ (Tippen eines Namens)")
                    // Zurück und Vorwärts (E1102, R-BG5-02): ⌘[ zurück auf „Kommentar“, ⌘] wieder vor, ⌘[ zurück.
                    var schritte: [String] = []
                    for (zeichen, code, ziel) in [("[", UInt16(33), Vorhabenreiter.kommentar), ("]", 30, .hausaufgabe),
                                                  ("[", 33, .kommentar)] {
                        taste(blatt, zeichen, code: code, befehl: true)
                        let zeile = Vorhabenreiter.allCases.firstIndex(of: ziel) ?? -1
                        _ = await warten(2) { speicher.vorhabenReiter == ziel && tabelle.selectedRow == zeile }
                        schritte.append("⌘\(zeichen) → \(speicher.vorhabenReiter.titel)"
                                        + (tabelle.selectedRow == zeile ? "" : " (Leiste auf Zeile \(tabelle.selectedRow + 1))"))
                    }
                    pruefen(schritte == ["⌘[ → Kommentar", "⌘] → Hausaufgabe", "⌘[ → Kommentar"],
                            "\(name): Zurück und Vorwärts — \(schritte.joined(separator: ", "))")
                    if let feld = kommentarfeld() { _ = blatt.makeFirstResponder(feld) }
                    _ = await warten(2) { tabelle.rowView(atRow: 1, makeIfNecessary: false)?.isEmphasized == false }
                    pruefen(tabelle.rowView(atRow: 1, makeIfNecessary: false)?.isEmphasized == false,
                            "\(name): Fokus im Formular — die Wahl grau, nicht betont (E1120)")
                    await leisteRuhig(tabelle, "Vorhaben-Blatt · Leiste", a: 5, b: 6) { speicher.vorhabenReiter == Vorhabenreiter.allCases[$0] }
                } else {
                    pruefen(false, "\(name): die Leiste mit sieben Einträgen")
                }
                // Auf einem anderen Eintrag schließen: Das Schließen muss ihn zurücksetzen (Z-AW2b-04).
                speicher.vorhabenReiter = .links
                speicher.vorhabenDialog = nil
                _ = await warten(4) { haupt.attachedSheet == nil }
                pruefen(speicher.vorhabenReiter == .grundlegendes, "\(name): nach dem Schließen wieder „Grundlegendes“")
            } else {
                pruefen(false, "das Vorhaben-Blatt ging für die Leiste nicht auf")
            }
            do {
                // Mit Hausaufgabe, geöffnet wie „Hausaufgabe hinzufügen …“ (E653): auf „Hausaufgabe“, die Schreibmarke in deren
                // Zeile (Z-AW3n-06, R-BG5-03); „Hausaufgabe, ✓“ — Name und Plakette passen in die Zeile.
                var mitHausaufgabe = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
                mitHausaufgabe.hausaufgabe = true
                speicher.vorhabenDialog = mitHausaufgabe
                speicher.vorhabenReiter = .hausaufgabe
                // In derselben Frist auf die Leiste warten, nicht nur aufs Blatt — eine Ursache, ein ✗ (Z-AW3n-08).
                _ = await warten(bis: { haupt.attachedSheet.flatMap(seitenleiste) != nil })
                if let blatt = haupt.attachedSheet, let tabelle = seitenleiste(blatt), tabelle.numberOfRows > 4 {
                    await vorndran(blatt)
                    let feld = (tabelle.view(atColumn: 0, row: 4, makeIfNecessary: true) as? NSTableCellView)?.textField
                    let passt = feld.map { $0.intrinsicContentSize.width <= $0.frame.width + 0.5 } ?? false
                    pruefen(zeilenname(tabelle, 4) == "Hausaufgabe, ✓" && passt,
                            "\(name): „\(zeilenname(tabelle, 4))“ — der Name ganz zu sehen neben der Plakette")
                    _ = await warten(2) { schreibmarke(blatt).contains("S. 42, Nr. 3–5") }
                    pruefen(tabelle.selectedRow == 4 && schreibmarke(blatt).contains("S. 42, Nr. 3–5"),
                            "\(name): mit „Hausaufgabe“ geöffnet, die Schreibmarke in deren Zeile (Z-AW3n-06): \(schreibmarke(blatt))")
                } else {
                    pruefen(false, haupt.attachedSheet == nil ? "\(name): das Blatt mit Hausaufgabe ging nicht auf"
                                                              : "\(name): das Blatt mit Hausaufgabe steht, ohne Leiste")
                }
                speicher.vorhabenDialog = nil
                _ = await warten(4) { haupt.attachedSheet == nil }
            }
            // Der Sprung auf den Eintrag des Grundes, wenn „Übernehmen“ abweist (E374): ein Wechsel aus dem Programm, nicht
            // über Leiste oder Kapsel. Auch er zählt — ein getippter Tag ohne ⏎ geht nicht verloren (R-BG8-W2-03, E1149,
            // R-BG8n-03). Nachgestellt wie `uebernehmen()`: der Eintrag am Speicher, die Schreibmarke bleibt im Feld.
            if let start = speicher.planung?.start {
                let alt = start.plus(tage: 1), neu = start.plus(tage: 2).deutsch
                var mitPruefung = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
                mitPruefung.pruefung = true
                mitPruefung.pruefungstag = alt
                speicher.vorhabenDialog = mitPruefung
                speicher.vorhabenReiter = .pruefung
                _ = await warten(bis: { haupt.attachedSheet.flatMap(seitenleiste) != nil })
                if let blatt = haupt.attachedSheet, let tabelle = seitenleiste(blatt) {
                    await vorndran(blatt)
                    /// Das Feld des Prüfungstags auf „Prüfung“: bearbeitbar, mit dem erwarteten Tag.
                    @MainActor func tagfeld(_ wert: String) -> NSTextField? {
                        suchen(blatt.contentView) { (feld: NSTextField) in feld.isEditable && feld.stringValue == wert }
                    }
                    _ = await warten(2) { tabelle.selectedRow == 2 && tagfeld(alt.deutsch) != nil }
                    var getippt = ""
                    if let feld = tagfeld(alt.deutsch), blatt.makeFirstResponder(feld),
                       let editor = feld.currentEditor() as? NSTextView {
                        editor.selectAll(nil)
                        editor.insertText(neu, replacementRange: editor.selectedRange())
                        getippt = editor.string
                    }
                    speicher.vorhabenReiter = .grundlegendes
                    _ = await warten(2) { tabelle.selectedRow == 0 }
                    speicher.vorhabenReiter = .pruefung
                    _ = await warten(2) { tabelle.selectedRow == 2 && tagfeld(neu) != nil }
                    let danach = tagfeld(neu) != nil ? neu : (tagfeld(alt.deutsch) != nil ? alt.deutsch : "kein Feld")
                    pruefen(getippt == neu && danach == neu,
                            "\(name): ein getippter Tag ohne ⏎ übersteht den Sprung nach abgewiesenem „Übernehmen“ (E374, "
                            + "R-BG8n-03): getippt „\(getippt)“, danach „\(danach)“")
                } else {
                    pruefen(false, "\(name): das Blatt mit Prüfung ging nicht auf")
                }
                speicher.vorhabenDialog = nil
                _ = await warten(4) { haupt.attachedSheet == nil }
            }

            // ── Lücken beim Seitenwechsel mit offenem Feld (v96, BH3; V4 → E1166; Review GPTA6, Abschnitt 5) ──
            /// Die Hauptschlange zweimal leeren — ein vorgemerkter Block der Leiste (R95-03) ist dann gelaufen; ohne Uhr.
            @MainActor func schlangeLeeren() async {
                for _ in 0..<2 {
                    await withCheckedContinuation { (fertig: CheckedContinuation<Void, Never>) in
                        DispatchQueue.main.async { fertig.resume() }
                    }
                }
            }
            // Die Plakette nach einem Klick in die Leiste (E373, E1105): ein getippter Kommentar, dann „Grundlegendes“ — „•“
            // steht. Kein Beleg für R95-03: Kommentar und Linkadresse übernehmen live, die Vorbedingung (ein älterer Stand im
            // Rückruf) entsteht hier nie — G580 bleibt grün (R-BH3-01). R95-03 belegen die Prüfungen am Koordinator
            // (`SeitenleistePruefungen`). Ein getippter Tag ändert keine Plakette (`kennzeichen`).
            do {
                speicher.vorhabenDialog = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
                speicher.vorhabenReiter = .kommentar
                _ = await warten(bis: { haupt.attachedSheet.flatMap(seitenleiste) != nil })
                if let blatt = haupt.attachedSheet, let tabelle = seitenleiste(blatt) {
                    await vorndran(blatt)
                    _ = await warten(2) { tabelle.selectedRow == 1 }
                    var getippt = false
                    if let text: NSTextView = suchen(blatt.contentView, { (t: NSTextView) in
                        t.accessibilityLabel() == "Kommentar zum Verlauf" && t.string.isEmpty }),
                       blatt.makeFirstResponder(text) {
                        text.insertText("Lücke R95-03", replacementRange: text.selectedRange())
                        getippt = true
                    }
                    let grund = await klicken(tabelle, 0)
                    _ = await warten(2) { tabelle.selectedRow == 0 }
                    await schlangeLeeren()
                    let danach = zeilenname(tabelle, 1)
                    pruefen(getippt && grund == nil && danach == "Kommentar, •",
                            "\(name): ein getippter Kommentar, dann ein Klick auf „Grundlegendes“ — die Plakette "
                            + "„\(danach)“, erwartet „Kommentar, •“ (E373)" + (grund.map { " — \($0)" } ?? ""))
                } else {
                    pruefen(false, "\(name): das Blatt für die Plakette des Kommentars ging nicht auf")
                }
                speicher.vorhabenDialog = nil
                _ = await warten(4) { haupt.attachedSheet == nil }
            }
            // Vier Wege mit einem getippten Prüfungstag ohne ⏎ (V4): ungültig getippt, ↓/↑ in der Leiste, der Material-Bogen
            // darüber, ⌘Z nach dem Wechsel. Je ein eigenes Blatt, geöffnet wie oben mit Prüfung am Tag `alt`.
            if let start = speicher.planung?.start {
                let alt = start.plus(tage: 1)
                @MainActor func pruefungsblatt() async -> (NSWindow, NSTableView)? {
                    var mitPruefung = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
                    mitPruefung.pruefung = true
                    mitPruefung.pruefungstag = alt
                    speicher.vorhabenDialog = mitPruefung
                    speicher.vorhabenReiter = .pruefung
                    _ = await warten(bis: { haupt.attachedSheet.flatMap(seitenleiste) != nil })
                    guard let blatt = haupt.attachedSheet, let tabelle = seitenleiste(blatt) else { return nil }
                    await vorndran(blatt)
                    return (blatt, tabelle)
                }
                /// Im Feld, das gerade bearbeitet wird, gilt der Text des Feldeditors: `stringValue` riefe dort
                /// `validateEditing` und schriebe ihn vorab in die Zelle — die Probe verdeckte dann, was die App beim
                /// Verschwinden des Felds liest (R-BH3N-04).
                @MainActor func tagfeld(_ blatt: NSWindow, _ wert: String) -> NSTextField? {
                    suchen(blatt.contentView) { (feld: NSTextField) in
                        feld.isEditable && ((feld.currentEditor() as? NSTextView)?.string ?? feld.stringValue) == wert
                    }
                }
                /// Tippt `wert` in das Feld mit dem Tag `alt`, ohne ⏎ — zurück kommt, was im Feld steht.
                @MainActor func tippen(_ blatt: NSWindow, _ wert: String) -> String {
                    guard let feld = tagfeld(blatt, alt.deutsch), blatt.makeFirstResponder(feld),
                          let editor = feld.currentEditor() as? NSTextView else { return "" }
                    editor.selectAll(nil)
                    editor.insertText(wert, replacementRange: editor.selectedRange())
                    return editor.string
                }
                /// Was das Feld auf „Prüfung“ zeigt: `neu`, der bisherige Tag oder „kein Feld“.
                @MainActor func zeigt(_ blatt: NSWindow, _ neu: String) -> String {
                    tagfeld(blatt, neu) != nil ? neu : (tagfeld(blatt, alt.deutsch) != nil ? alt.deutsch : "kein Feld")
                }
                /// Ein Weg über „Grundlegendes“ und zurück auf „Prüfung“ — was das Feld danach zeigt.
                @MainActor func rundweg(_ blatt: NSWindow, _ tabelle: NSTableView, _ neu: String) async -> String {
                    speicher.vorhabenReiter = .grundlegendes
                    _ = await warten(2) { tabelle.selectedRow == 0 }
                    speicher.vorhabenReiter = .pruefung
                    _ = await warten(2) { tabelle.selectedRow == 2 && zeigt(blatt, neu) != "kein Feld" }
                    return zeigt(blatt, neu)
                }
                @MainActor func zu() async {
                    speicher.materialblattOffen = false
                    speicher.vorhabenDialog = nil
                    _ = await warten(4) { haupt.attachedSheet == nil }
                }
                // Ungültig getippt: Der Tag lässt sich nicht lesen — nach dem Wechsel gilt der bisherige.
                if let (blatt, tabelle) = await pruefungsblatt() {
                    _ = await warten(2) { tabelle.selectedRow == 2 && tagfeld(blatt, alt.deutsch) != nil }
                    let getippt = tippen(blatt, "99.99.")
                    let danach = await rundweg(blatt, tabelle, "99.99.")
                    pruefen(getippt == "99.99." && danach == alt.deutsch,
                            "\(name): ein ungültig getippter Tag vor dem Wechsel — danach „\(danach)“, erwartet der bisherige "
                            + "„\(alt.deutsch)“ (V4)")
                } else {
                    pruefen(false, "\(name): das Blatt mit Prüfung ging für den ungültigen Tag nicht auf")
                }
                await zu()
                // ↓ und ↑ in der Leiste: erst die Leiste nehmen (wie ein Klick oder ⇥), dann mit den Pfeilen hin und zurück.
                if let (blatt, tabelle) = await pruefungsblatt() {
                    let neu = start.plus(tage: 3).deutsch
                    _ = await warten(2) { tabelle.selectedRow == 2 && tagfeld(blatt, alt.deutsch) != nil }
                    let getippt = tippen(blatt, neu)
                    let leiste = blatt.makeFirstResponder(tabelle)
                    pfeil(tabelle, runter: true)
                    _ = await warten(2) { tabelle.selectedRow == 3 }
                    let weiter = tabelle.selectedRow
                    pfeil(tabelle, runter: false)
                    _ = await warten(2) { tabelle.selectedRow == 2 && zeigt(blatt, neu) != "kein Feld" }
                    let danach = zeigt(blatt, neu)
                    pruefen(getippt == neu && leiste && weiter == 3 && danach == neu,
                            "\(name): ein getippter Tag, dann ↓ und ↑ in der Leiste — Zeile \(weiter) (erwartet 3), danach "
                            + "„\(danach)“ (V4)")
                } else {
                    pruefen(false, "\(name): das Blatt mit Prüfung ging für ↓/↑ nicht auf")
                }
                await zu()
                // Der Material-Bogen über dem getippten Tag: auf und wieder zu — der Tag bleibt.
                if let (blatt, tabelle) = await pruefungsblatt() {
                    let neu = start.plus(tage: 4).deutsch
                    _ = await warten(2) { tabelle.selectedRow == 2 && tagfeld(blatt, alt.deutsch) != nil }
                    let getippt = tippen(blatt, neu)
                    speicher.materialblattOffen = true
                    let bogen = await warten(8) { blatt.attachedSheet != nil }
                    speicher.materialblattOffen = false
                    _ = await warten(8) { blatt.attachedSheet == nil }
                    // Direkt nach dem Bogen, vor jedem Seitenwechsel: Er selbst darf den Tag nicht kosten (R-BH3-04).
                    let nachBogen = zeigt(blatt, neu)
                    let danach = await rundweg(blatt, tabelle, neu)
                    pruefen(getippt == neu && bogen && nachBogen == neu && danach == neu,
                            "\(name): ein getippter Tag, darüber der Material-Bogen auf und zu — "
                            + (bogen ? "" : "der Bogen ging nicht auf, ")
                            + "gleich danach „\(nachBogen)“, nach einem Wechsel „\(danach)“ (V4)")
                } else {
                    pruefen(false, "\(name): das Blatt mit Prüfung ging für den Material-Bogen nicht auf")
                }
                await zu()
                // ⌘Z nach dem Wechsel: Das Getippte ist übernommen, das Feld neu aufgebaut — es gibt nichts zu widerrufen, und
                // das Feld zeigt danach den neuen Tag, auch nach einem Weg über „Grundlegendes“ (Laufergebnis 10.11.2026,
                // R-BH3N-01). Dass ⌘Z das Feld auf diesem Weg erreicht, belegt die Gegenprobe im selben Feld: ein angehängtes
                // Zeichen lässt sich widerrufen, und ⌘Z nimmt es zurück. Die Tasten kommen über die Ereignisschlange — der
                // Leseschritt wartet auf die Wirkung, und das erste ⌘Z ist verarbeitet, bevor das zweite ankommt.
                if let (blatt, tabelle) = await pruefungsblatt() {
                    let neu = start.plus(tage: 5).deutsch
                    _ = await warten(2) { tabelle.selectedRow == 2 && tagfeld(blatt, alt.deutsch) != nil }
                    let getippt = tippen(blatt, neu)
                    let gewechselt = await rundweg(blatt, tabelle, neu)
                    // Wie von Hand: zurück im Feld, dann ⌘Z (R-BH3-02).
                    let imFeld = tagfeld(blatt, neu).map { blatt.makeFirstResponder($0) } ?? false
                    let konnte = blatt.firstResponder?.undoManager?.canUndo ?? false
                    taste(blatt, "z", code: 6, befehl: true)
                    // Gegenprobe: ans Ende ein „x“ wie getippt — jetzt lässt sich widerrufen, ⌘Z nimmt es zurück.
                    let editor = blatt.firstResponder as? NSTextView
                    editor?.moveToEndOfDocument(nil)
                    if let editor { editor.insertText("x", replacementRange: editor.selectedRange()) }
                    let angehaengt = editor?.string ?? "kein Editor"
                    let gegenKonnte = blatt.firstResponder?.undoManager?.canUndo ?? false
                    taste(blatt, "z", code: 6, befehl: true)
                    let zurueck = await warten(2) { (blatt.firstResponder as? NSTextView)?.string == neu }
                    let sofort = zeigt(blatt, neu)
                    let danach = await rundweg(blatt, tabelle, neu)
                    pruefen(getippt == neu && gewechselt == neu && imFeld && !konnte && angehaengt == neu + "x"
                            && gegenKonnte && zurueck && sofort == neu && danach == neu,
                            "\(name): ⌘Z nach dem Wechsel, im Feld — Widerrufen \(konnte ? "möglich" : "nicht möglich") "
                            + "(erwartet: nicht möglich); Gegenprobe: „\(angehaengt)“, widerrufbar \(gegenKonnte), ⌘Z nimmt das „x“ "
                            + "zurück \(zurueck); das Feld zeigt „\(sofort)“, nach einem Weg über „Grundlegendes“ „\(danach)“ "
                            + "(V4, R-BH3N-01)")
                } else {
                    pruefen(false, "\(name): das Blatt mit Prüfung ging für ⌘Z nicht auf")
                }
                await zu()
            }

            // ── Einstellungen: die Leiste (v95, E1118, E1121, E1123–E1129) ──
            // Dieselbe Leiste im selben Rahmen: 780 × 640, sechs Einträge in der Folge des Nutzers, beim Öffnen
            // „Zeitraum“ (E1126), keine Plaketten (E1127), jede Zeile 32 pt. Gewählt per Klick wie von Hand; der Inhalt
            // folgt — das Datumsfeld gibt es genau auf „Zeitraum“ (R-BG5a-01). Ein getippter Tag ohne ⏎ übersteht den
            // Wechsel auf „Stand“ und zurück (R-BG5a-03). 66 Wechsel ohne Sprung einer Zeile, darunter zehnmal
            // Sicherungskopie ↔ Stand. Nach einem anderen Eintrag geschlossen, öffnet das Blatt wieder mit „Zeitraum“.
            do {
                let einst = "Einstellungen · Leiste"
                let eintraege = ["Zeitraum", "Sicherungskopie", "Verschlüsselung", "Updates", "3ducation.org", "Stand"]
                speicher.offenerDialog = .einstellungen
                if await warten(bis: { haupt.attachedSheet != nil }), let blatt = haupt.attachedSheet {
                    await vorndran(blatt)
                    let groesse = blatt.contentRect(forFrameRect: blatt.frame).size
                    let hoeheE = Self.blatthoehe(blatt, bestellt: 640)
                    pruefen(abs(groesse.width - 780) < 0.5 && hoeheE.gilt,
                            "\(einst): das Blatt ist \(Int(groesse.width)) breit (780, E1121) und \(hoeheE.text)")
                    _ = await warten(2) { seitenleiste(blatt) != nil }
                    /// Die Datumsfelder des Blatts, oben zuerst: bearbeitbare Felder, die ein Datum zeigen („03.08.2026“,
                    /// `Tag.deutsch`) — einen Platzhalter tragen sie nicht, im gruppierten `Form` wird der Titel zum
                    /// verborgenen Etikett.
                    @MainActor func datumsfelder() -> [NSTextField] {
                        var felder: [NSTextField] = []
                        @MainActor func sammeln(_ ansicht: NSView) {
                            if let feld = ansicht as? NSTextField, feld.isEditable,
                               (feld.currentEditor()?.string ?? feld.stringValue)
                                .range(of: #"^[0-9]{2}\.[0-9]{2}\.[0-9]{4}$"#, options: .regularExpression) != nil {
                                felder.append(feld)
                            }
                            ansicht.subviews.forEach(sammeln)
                        }
                        if let inhalt = blatt.contentView { sammeln(inhalt) }
                        return felder.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
                    }
                    if let tabelle = seitenleiste(blatt), tabelle.numberOfRows == eintraege.count {
                        let namen = (0..<tabelle.numberOfRows).map { zeilenname(tabelle, $0) }
                        pruefen(namen == eintraege && tabelle.selectedRow == 0,
                                "\(einst): \(namen.joined(separator: " · ")), gewählt der erste, ohne Plaketten (E1126, E1127)")
                        pruefen(Set(zeilenhoehen(tabelle)) == [32], "\(einst): jede Zeile 32 pt hoch (E1120): \(zeilenhoehen(tabelle))")
                        // R-BG5a-03, nachgestellt: einen Tag tippen ohne ⏎, auf „Stand“ klicken und zurück — der Tag steht.
                        if let feld = datumsfelder().first, let planung = speicher.planung {
                            let vorher = feld.stringValue
                            let neu = planung.start.plus(tage: 7).deutsch
                            var getippt = ""
                            if blatt.makeFirstResponder(feld), let editor = feld.currentEditor() as? NSTextView {
                                editor.selectAll(nil)
                                editor.insertText(neu, replacementRange: editor.selectedRange())
                                getippt = editor.string
                            }
                            _ = await klicken(tabelle, 5)
                            _ = await warten(2) { tabelle.selectedRow == 5 && datumsfelder().isEmpty }
                            _ = await klicken(tabelle, 0)
                            _ = await warten(2) { tabelle.selectedRow == 0 && !datumsfelder().isEmpty }
                            let danach = datumsfelder().first?.stringValue ?? "kein Feld"
                            pruefen(getippt == neu && danach == neu,
                                    "\(einst): ein getippter Tag ohne ⏎ übersteht den Wechsel auf „Stand“ und zurück "
                                    + "(R-BG5a-03): vorher „\(vorher)“, getippt „\(getippt)“, danach „\(danach)“")
                            // Ebenso über die Kapsel, deren Knöpfe den Fokus nicht nehmen (R-BG5d-01): tippen, ⌘[ zurück auf
                            // „Stand“, ⌘] vor auf „Zeitraum“.
                            let neu2 = planung.start.plus(tage: 14).deutsch
                            var getippt2 = ""
                            if let feld2 = datumsfelder().first, blatt.makeFirstResponder(feld2),
                               let editor = feld2.currentEditor() as? NSTextView {
                                editor.selectAll(nil)
                                editor.insertText(neu2, replacementRange: editor.selectedRange())
                                getippt2 = editor.string
                            }
                            taste(blatt, "[", code: 33, befehl: true)
                            _ = await warten(2) { tabelle.selectedRow == 5 && datumsfelder().isEmpty }
                            let zurueckAuf = tabelle.selectedRow
                            taste(blatt, "]", code: 30, befehl: true)
                            _ = await warten(2) { tabelle.selectedRow == 0 && datumsfelder().first?.stringValue == neu2 }
                            let danach2 = datumsfelder().first?.stringValue ?? "kein Feld"
                            pruefen(getippt2 == neu2 && zurueckAuf == 5 && danach2 == neu2,
                                    "\(einst): ein getippter Tag übersteht ⌘[ und ⌘] (R-BG5d-01): getippt „\(getippt2)“, "
                                    + "zurück auf Zeile \(zurueckAuf + 1), danach „\(danach2)“")
                        } else {
                            pruefen(false, "\(einst): kein Datumsfeld auf „Zeitraum“")
                        }
                        // Der Inhalt folgt der Wahl: das Datumsfeld genau auf „Zeitraum“ (R-BG5a-01).
                        await leisteRuhig(tabelle, "Einstellungen · Leiste", a: 1, b: 5) { zeile in
                            datumsfelder().isEmpty == (zeile != 0)
                        }
                        // Auf einem anderen Eintrag schließen: Das Blatt öffnet wieder mit „Zeitraum“ (E1126, R-BG5a-02).
                        _ = await klicken(tabelle, 3)
                        _ = await warten(2) { tabelle.selectedRow == 3 }
                        let geschlossenAuf = tabelle.selectedRow
                        speicher.offenerDialog = nil
                        _ = await warten(4) { haupt.attachedSheet == nil }
                        speicher.offenerDialog = .einstellungen
                        if await warten(bis: { haupt.attachedSheet.flatMap(seitenleiste) != nil }),
                           let wieder = haupt.attachedSheet, let leiste = seitenleiste(wieder) {
                            pruefen(geschlossenAuf == 3 && leiste.selectedRow == 0,
                                    "\(einst): auf „\(eintraege[max(0, geschlossenAuf)])“ geschlossen, wieder geöffnet — "
                                    + "gewählt „\(leiste.selectedRow >= 0 ? eintraege[leiste.selectedRow] : "nichts")“ (E1126)")
                        } else {
                            pruefen(false, "\(einst): die Einstellungen gingen ein zweites Mal nicht auf")
                        }
                    } else {
                        pruefen(false, "\(einst): die Leiste mit sechs Einträgen")
                    }
                    speicher.offenerDialog = nil
                    _ = await warten(4) { haupt.attachedSheet == nil }
                } else {
                    pruefen(false, "die Einstellungen gingen für die Leiste nicht auf")
                }
            }

            // ── ⌘K: die Leiste (v95, E1130–E1139) ──
            // Dieselbe Leiste im selben Rahmen: 980 × 820 (E1136), drei Einträge in der Folge des Nutzers, beim Öffnen
            // „Klassen/Kurse“ (E1133), keine Plaketten (E1134), jede Zeile 32 pt. Gewählt per Klick wie von Hand; der Inhalt
            // folgt — Felder „Klasse/Kurs“ gibt es genau auf „Klassen/Kurse“. Ein getippter Name übersteht den Wechsel auf
            // „Fachfarben“ und zurück (wie R-BG5a-03). 66 Wechsel ohne Sprung einer Zeile; nach dem Bogen „Farbe wählen“
            // und nach dem Schließen auf einem anderen Eintrag steht wieder „Klassen/Kurse“ (E1133).
            do {
                let kname = "⌘K · Leiste"
                let eintraege = ["Lernende", "Klassen/Kurse", "Fachfarben"]
                speicher.offenerDialog = .klassen
                if await warten(bis: { haupt.attachedSheet != nil }), let blatt = haupt.attachedSheet {
                    await vorndran(blatt)
                    let groesse = blatt.contentRect(forFrameRect: blatt.frame).size
                    let hoeheK = Self.blatthoehe(blatt, bestellt: 820)
                    pruefen(abs(groesse.width - 980) < 0.5 && hoeheK.gilt,
                            "\(kname): das Blatt ist \(Int(groesse.width)) breit (980, E1136) und \(hoeheK.text)")
                    _ = await warten(2) { seitenleiste(blatt) != nil }
                    /// Die Felder „Klasse/Kurs“ der Zeilen, oben zuerst.
                    @MainActor func namensfelder() -> [NSTextField] {
                        var felder: [NSTextField] = []
                        @MainActor func sammeln(_ ansicht: NSView) {
                            if let feld = ansicht as? NSTextField, feld.isEditable,
                               (feld.placeholderString ?? feld.placeholderAttributedString?.string) == "Klasse/Kurs" {
                                felder.append(feld)
                            }
                            ansicht.subviews.forEach(sammeln)
                        }
                        if let inhalt = blatt.contentView { sammeln(inhalt) }
                        return felder.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
                    }
                    if let tabelle = seitenleiste(blatt), tabelle.numberOfRows == eintraege.count {
                        let namen = (0..<tabelle.numberOfRows).map { zeilenname(tabelle, $0) }
                        pruefen(namen == eintraege && tabelle.selectedRow == 1,
                                "\(kname): \(namen.joined(separator: " · ")), gewählt „Klassen/Kurse“, ohne Plaketten (E1133, E1134)")
                        // Der Inhalt folgt der Wahl: Felder „Klasse/Kurs“ genau auf „Klassen/Kurse“ (R-BG5c-04). Die Texte von
                        // SwiftUI („Lernende …“, „Fachfarbe festlegen“) sind im Baum des eigenen Prozesses nicht zu lesen; dass
                        // „Lernende“ und „Fachfarben“ ihre eigene Seite zeigen, prüft `SeitenleistePruefungen.seitenZugeordnet`
                        // am Quelltext, die Abbilder je Eintrag zeigen es.
                        var gesehen: [String] = []
                        for zeile in [0, 2, 1] {
                            _ = await klicken(tabelle, zeile)
                            _ = await warten(2) { tabelle.selectedRow == zeile && namensfelder().isEmpty == (zeile != 1) }
                            gesehen.append("\(eintraege[zeile]) \(namensfelder().isEmpty ? "ohne" : "mit") Feldern")
                        }
                        pruefen(gesehen == ["Lernende ohne Feldern", "Fachfarben ohne Feldern", "Klassen/Kurse mit Feldern"],
                                "\(kname): der Inhalt folgt der Wahl — \(gesehen.joined(separator: ", "))")
                        // Auskunft: die Breite des Fachfelds (E1137 rechnet 150 samt Fläche) — für die Sichtung in der VM.
                        if let fachfeld = suchen(blatt.contentView, { (feld: NSTextField) in
                            (feld.placeholderString ?? feld.placeholderAttributedString?.string) == "Fach (optional)"
                        }) {
                            // `Tabellenfeld`: 8 pt Rand links und rechts um das Eingabefeld.
                            print("  Auskunft ⌘K: Eingabefeld „Fach (optional)“ \(Int(fachfeld.frame.width.rounded())) pt breit, "
                                  + "samt Fläche \(Int((fachfeld.frame.width + 16).rounded())) pt"); fflush(stdout)
                        }
                        pruefen(Set(zeilenhoehen(tabelle)) == [32], "\(kname): jede Zeile 32 pt hoch (E1120): \(zeilenhoehen(tabelle))")
                        // Ein getippter Name übersteht den Wechsel auf „Fachfarben“ und zurück; danach der alte Name zurück.
                        // Gespeichert über den Entpreller der Zeile — die Übernahme beim Verschwinden prüft das umbenannte
                        // Fach darunter (R-BG8-W2-01).
                        if let feld = namensfelder().first, let erste = speicher.planung?.klassen.first(where: { !$0.istSonderzeile }) {
                            let vorher = erste.name
                            let neu = vorher + " Probe"
                            var getippt = ""
                            if blatt.makeFirstResponder(feld), let editor = feld.currentEditor() as? NSTextView {
                                editor.selectAll(nil)
                                editor.insertText(neu, replacementRange: editor.selectedRange())
                                getippt = editor.string
                            }
                            _ = await klicken(tabelle, 2)
                            _ = await warten(2) { tabelle.selectedRow == 2 && namensfelder().isEmpty }
                            _ = await klicken(tabelle, 1)
                            _ = await warten(2) {
                                tabelle.selectedRow == 1 && namensfelder().first?.stringValue == neu
                                    && speicher.planung?.klassen.first { $0.id == erste.id }?.name == neu
                            }
                            let danach = namensfelder().first?.stringValue ?? "kein Feld"
                            let gespeichert = speicher.planung?.klassen.first { $0.id == erste.id }?.name ?? "keine Zeile"
                            pruefen(getippt == neu && danach == neu && gespeichert == neu,
                                    "\(kname): ein getippter Name übersteht den Wechsel auf „Fachfarben“ und zurück: getippt "
                                    + "„\(getippt)“, danach „\(danach)“, gespeichert „\(gespeichert)“")
                            // Erst alles Wartende übernehmen, dann den alten Namen zurück — sonst schriebe ein spät
                            // ankommender Entpreller „… Probe“ erneut (R-BG5c-06).
                            Entpreller.allesUebernehmen()
                            speicher.klasseAendern(id: erste.id, name: vorher, fach: erste.fach)
                            pruefen(speicher.planung?.klassen.first { $0.id == erste.id }?.name == vorher,
                                    "\(kname): der alte Name „\(vorher)“ steht wieder")
                        } else {
                            pruefen(false, "\(kname): kein Feld „Klasse/Kurs“ auf „Klassen/Kurse“")
                        }
                        // Ein umbenanntes Fach ohne Zeile übersteht ⌘[ ohne Klick: Die Schreibmarke bleibt im Feld, und
                        // `Fachname` hat keinen Entpreller — nur die Übernahme beim Verschwinden (`Tabellenfeld`, R-BG5c-01)
                        // rettet den Namen (R-BG8-W2-01). Von „Klassen/Kurse“ auf „Fachfarben“, dort tippen, ⌘[ zurück.
                        if let planung = speicher.planung {
                            let alt = "probefach alt", neu = "Probefach neu"
                            let altSchluessel = Farbwelt.fachSchluessel(alt), neuSchluessel = Farbwelt.fachSchluessel(neu)
                            speicher.fachfarbeSetzen(fach: altSchluessel,
                                                     ton: Farbwelt.ton(Farbwelt.naechsteFreieFarbe(planung.farbnutzung)).schluessel)
                            _ = await klicken(tabelle, 2)
                            /// Das Feld „Fach“ des neuen Fachs auf „Fachfarben“.
                            @MainActor func fachfeld() -> NSTextField? {
                                suchen(blatt.contentView) { (feld: NSTextField) in
                                    feld.isEditable && feld.stringValue == alt
                                        && (feld.placeholderString ?? feld.placeholderAttributedString?.string) == "Fach"
                                }
                            }
                            _ = await warten(2) { tabelle.selectedRow == 2 && fachfeld() != nil }
                            var getippt = ""
                            if let feld = fachfeld(), blatt.makeFirstResponder(feld),
                               let editor = feld.currentEditor() as? NSTextView {
                                editor.selectAll(nil)
                                editor.insertText(neu, replacementRange: editor.selectedRange())
                                getippt = editor.string
                            }
                            taste(blatt, "[", code: 33, befehl: true)
                            _ = await warten(2) { tabelle.selectedRow == 1 && speicher.planung?.fachfarben[neuSchluessel] != nil }
                            let zurueckAuf = tabelle.selectedRow
                            let umbenannt = speicher.planung?.fachfarben[neuSchluessel] != nil
                                && speicher.planung?.fachfarben[altSchluessel] == nil
                            pruefen(getippt == neu && zurueckAuf == 1 && umbenannt,
                                    "\(kname): ein umbenanntes Fach übersteht ⌘[ ohne Klick (R-BG5c-01, R-BG8-W2-01): getippt "
                                    + "„\(getippt)“, zurück auf Zeile \(zurueckAuf + 1), umbenannt \(umbenannt)")
                            for schluessel in [neuSchluessel, altSchluessel] where speicher.planung?.fachfarben[schluessel] != nil {
                                speicher.fachEntfernen(schluessel)
                            }
                        }
                        // Der Inhalt folgt der Wahl: Felder „Klasse/Kurs“ genau auf „Klassen/Kurse“.
                        await leisteRuhig(tabelle, "⌘K · Leiste", a: 0, b: 2) { zeile in
                            namensfelder().isEmpty == (zeile != 1)
                        }
                        // Der Bogen „Farbe wählen“ über dem Blatt und wieder zu: Er setzt den Eintrag nicht zurück — von
                        // „Klassen/Kurse“ aus steht danach „Klassen/Kurse“, von „Fachfarben“ aus „Fachfarben“ (E1133;
                        // R-BG5c-03: nur so kann die Prüfung rot werden).
                        if let erste = speicher.planung?.klassen.first,
                           let fach = speicher.planung?.klassen.first(where: { !$0.fach.isEmpty }).map({ Farbwelt.fachSchluessel($0.fach) }) {
                            var wege: [String] = []
                            for (zeile, ziel) in [(1, Farbwahlziel.kurs(erste.id)), (2, Farbwahlziel.fach(fach))] {
                                _ = await klicken(tabelle, zeile)
                                _ = await warten(2) { tabelle.selectedRow == zeile }
                                speicher.farbwahlFuer = ziel
                                let auf = await warten(4) { blatt.attachedSheet != nil }
                                speicher.farbwahlFuer = nil
                                let zu = await warten(4) { blatt.attachedSheet == nil }
                                let nachher = seitenleiste(blatt)?.selectedRow ?? -1
                                wege.append("von „\(eintraege[zeile])“: " + (auf ? "" : "Bogen nicht auf, ")
                                            + (zu ? "" : "Bogen nicht zu, ")
                                            + "danach „\(nachher >= 0 ? eintraege[nachher] : "nichts")“")
                            }
                            pruefen(wege == ["von „Klassen/Kurse“: danach „Klassen/Kurse“", "von „Fachfarben“: danach „Fachfarben“"],
                                    "\(kname): „Farbe wählen“ setzt den Eintrag nicht zurück (E1133) — \(wege.joined(separator: "; "))")
                        } else {
                            pruefen(false, "\(kname): keine Zeile oder kein Fach für „Farbe wählen“")
                        }
                        // Auf „Fachfarben“ schließen: ⌘K öffnet wieder mit „Klassen/Kurse“ (E1133).
                        if let leiste = seitenleiste(blatt) {
                            _ = await klicken(leiste, 2)
                            _ = await warten(2) { leiste.selectedRow == 2 }
                            let geschlossenAuf = leiste.selectedRow
                            speicher.offenerDialog = nil
                            _ = await warten(4) { haupt.attachedSheet == nil }
                            speicher.offenerDialog = .klassen
                            if await warten(bis: { haupt.attachedSheet.flatMap(seitenleiste) != nil }),
                               let wieder = haupt.attachedSheet, let neu = seitenleiste(wieder) {
                                pruefen(geschlossenAuf == 2 && neu.selectedRow == 1,
                                        "\(kname): auf „\(eintraege[max(0, geschlossenAuf)])“ geschlossen, wieder geöffnet — "
                                        + "gewählt „\(neu.selectedRow >= 0 ? eintraege[neu.selectedRow] : "nichts")“ (E1133)")
                            } else {
                                pruefen(false, "\(kname): ⌘K ging ein zweites Mal nicht auf")
                            }
                        }
                    } else {
                        pruefen(false, "\(kname): die Leiste mit drei Einträgen")
                    }
                    speicher.offenerDialog = nil
                    _ = await warten(4) { haupt.attachedSheet == nil }
                } else {
                    pruefen(false, "⌘K ging für die Leiste nicht auf")
                }
            }

            // ── Kleiner Bildschirm (v95, E1150) ──
            // Am echten Fenster nachgestellt (R-BG8b-02): Das Hauptfenster wird so gelegt, dass unter seinem Kopf 700 pt
            // bis zum unteren Rand der sichtbaren Fläche liegen (wie 1440 × 900 mit großem Dock, Fenster maximiert).
            // Vorhaben-Blatt, ⌘K und der Sitzplan-Editor (BH4, E1158) werden 660 hoch und liegen am Fensterkopf an, die
            // Einstellungen bleiben 640; im Vorhaben-Blatt rollt das Formular, und die Leiste steht ganz; im Sitzplan-Editor
            // ist die Fläche nach dem Rollen ganz zu sehen. Dann das Fenster zurück an seinen Platz und erst danach der
            // Material-Bogen: Er bleibt Blatt − 80 (E1108), das Blatt behält seine Höhe — beide haben sie beim Öffnen
            // festgelegt (R-BG8b-01). Zuletzt ragt das Fenster 60 pt unter die sichtbare Fläche: Vorhaben-Blatt,
            // Einstellungen, Verschlüsselung und Sitzplan-Editor stehen mittig im Fenster und enden 40 pt über dem Rand, die
            // Material-Frage bleibt in ihrem Blatt (R-BG8bn-01); im Sitzplan-Editor rollt der Körper, und die Unterkante der
            // Fläche ist erreichbar (BH4). Je Blatt die Lage nach dem gemessenen Muster (`blatthoehe`), gemessen erst,
            // wenn es steht, und erst, wenn es das erwartete Blatt ist (R-BG8bn2-02, -05). Braucht 700 pt und den Kopf an
            // sichtbarer Höhe — sonst entfällt er mit einer Auskunft samt Maß (R-BG8bn-02); lässt sich das Fenster nicht
            // legen, ein ✗ und die übrigen Zeilen dieser Lage entfallen (R-BG8bn2-03).
            do {
                let klein = "Kleiner Bildschirm"
                let vorher = haupt.frame
                let kopf = haupt.frame.height - haupt.contentLayoutRect.maxY
                let flaeche = haupt.screen?.visibleFrame ?? .zero
                let unten = flaeche.minY
                let platz = flaeche.height >= 700 + kopf + 1
                if !platz {
                    // Kein Befund am Produkt: Der Bildschirm dieses Rechners ist zu niedrig für die Lage des Falls.
                    print("  Auskunft \(klein): entfällt — sichtbar \(Int(flaeche.height)) pt hoch, der Fall braucht 700 + Kopf "
                          + "(\(Int((700 + kopf).rounded())))")
                    fflush(stdout)
                }
                /// Das Hauptfenster so, dass unter seinem Kopf `sichtbar` pt bis zum unteren Rand der sichtbaren Fläche
                /// liegen und es `darunter` pt unter diesen Rand ragt.
                @MainActor func legen(sichtbar: CGFloat, darunter: CGFloat) async -> Bool {
                    let rahmen = NSRect(x: vorher.minX, y: unten - darunter, width: vorher.width,
                                        height: sichtbar + darunter + kopf)
                    haupt.setFrame(rahmen, display: true)
                    return await warten(2) {
                        abs(haupt.frame.minY - rahmen.minY) < 1 && abs(haupt.frame.height - rahmen.height) < 1
                    }
                }
                /// Das Hauptfenster zurück an seinen Platz.
                @MainActor func zuruecklegen() async -> Bool {
                    haupt.setFrame(vorher, display: true)
                    return await warten(2) { abs(haupt.frame.minY - vorher.minY) < 1 && abs(haupt.frame.height - vorher.height) < 1 }
                }
                /// Die Höhe des Inhalts eines Fensters, gerundet.
                @MainActor func innen(_ fenster: NSWindow) -> Int {
                    Int(fenster.contentRect(forFrameRect: fenster.frame).height.rounded())
                }
                /// Ein Rollbereich außer der Leiste, dessen Inhalt höher ist als sichtbar.
                @MainActor func rollt(_ blatt: NSWindow) -> Bool {
                    suchen(blatt.contentView) { (rolle: NSScrollView) in
                        (rolle.documentView as? NSTableView)?.identifier?.rawValue != "Seitenleiste"
                            && (rolle.documentView?.frame.height ?? 0) > rolle.contentView.bounds.height + 1
                    } != nil
                }
                /// Ein Blatt am Hauptfenster nach seiner Gestalt — die Zahl der Zeilen in der Leiste, `nil` ohne Leiste —, damit
                /// nicht das vorige, stehen gebliebene gemessen wird (R-BG8bn2-02).
                @MainActor func blattMit(zeilen: Int?) -> NSWindow? {
                    guard let blatt = haupt.attachedSheet else { return nil }
                    return seitenleiste(blatt)?.numberOfRows == zeilen ? blatt : nil
                }
                /// Bis das Blatt steht: Lage nach dem Muster und erwartete Höhe (R-BG8bn2-05).
                @MainActor func steht(_ blatt: NSWindow, bestellt: CGFloat, soll: Int) async {
                    _ = await warten(2) { Self.blatthoehe(blatt, bestellt: bestellt).gilt && innen(blatt) == soll }
                }
                /// Der Sitzplan-Editor an diesem Fenster (v96, BH4, E1192): 820 × 700 bestellt und wie das Vorhaben-Blatt
                /// begrenzt (E1150, E1188). Die Fläche liegt in einer Rollfläche; nach dem Rollen ans Ende steht ihre Unterkante im
                /// sichtbaren Ausschnitt, mit `ganz` die ganze Fläche. Mit `muss` muss sie rollen — am tiefen Fenster ist der
                /// Ausschnitt niedriger als die Fläche. Die Höhe des Körpers (mindestens der Ausschnitt, E1194) steht in der
                /// Zeile.
                /// Das Blatt „Lernende“ an diesem Fenster (v96, BH5, E1173): 980 × 820 bestellt und wie das Vorhaben-Blatt
                /// begrenzt (E1150). Nur mit Lernendendaten (versiegelt) — im Klartext fragt ⌘L nach der Verschlüsselung,
                /// dann entfällt die Zeile mit einer Auskunft.
                @MainActor func lernendeKlein(_ ort: String, soll: Int) async {
                    guard speicher.lernende.quelle == .behaelter else {
                        print("  Auskunft \(ort): Blatt „Lernende“ entfällt — ohne Lernendendaten")
                        fflush(stdout)
                        return
                    }
                    speicher.lernendenBlattOeffnen()
                    guard await warten(bis: { speicher.offenerDialog == .lernende && haupt.attachedSheet != nil }),
                          let blatt = haupt.attachedSheet else {
                        pruefen(false, "\(ort): das Blatt „Lernende“ ging nicht auf")
                        return
                    }
                    await vorndran(blatt)
                    await steht(blatt, bestellt: 820, soll: soll)
                    let lage = Self.blatthoehe(blatt, bestellt: 820)
                    pruefen(innen(blatt) == soll && abs(blatt.frame.width - 980) < 1 && lage.gilt,
                            "\(ort): Blatt „Lernende“ \(Int(blatt.frame.width.rounded())) breit (soll 980, E1173), "
                            + "\(lage.text), erwartet \(soll)")
                    tasteAn(blatt, "\u{1B}", code: 53)
                    _ = await warten(4) { haupt.attachedSheet == nil }
                    if haupt.attachedSheet != nil {
                        pruefen(false, "\(ort): das Blatt „Lernende“ ging mit ⎋ nicht zu")
                        speicher.alleDialogeSchliessen()
                        _ = await warten(4) { haupt.attachedSheet == nil }
                    }
                    // Der Bogen „Einzelne …“ auf „Neue Mitteilung“ (v96, BH8, R-BH8-W2-01, R-BH8N-01): wie von Hand — erst das
                    // Unterblatt über die Vorgabe, dann, wenn es steht, „Einzelne …“ über den Griff wie die Wahl im Menü. (Über die
                    // Vorgabe `adressaten` öffnet der Bogen schon beim Erscheinen und steht gestaucht auf 254 pt.) Er endet
                    // mindestens 40 pt über dem Rand der sichtbaren Fläche (E1150).
                    guard let verzeichnis = speicher.lernende.verzeichnis,
                          let gruppe = verzeichnis.gruppen().first(where: { !verzeichnis.mitglieder($0.id).isEmpty }) else {
                        print("  Auskunft \(ort): Bogen „Einzelne …“ entfällt — keine Lerngruppe mit Mitgliedern")
                        fflush(stdout)
                        return
                    }
                    speicher.lernendenBlattOeffnen(gruppe: gruppe.id)
                    speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                    speicher.lernendenVorgabe?.neueMitteilung = true
                    _ = await warten(bis: { haupt.attachedSheet?.attachedSheet != nil })
                    /// Bis die Höhe zwei Abfragen lang gleich bleibt — eine Uhr: Frist 2 s, Abstand 100 ms (R-BH8N-07).
                    @MainActor func hoeheSteht(_ fenster: NSWindow) async {
                        var vorige: CGFloat = -1
                        _ = await warten(2) { let jetzt = fenster.frame.height; defer { vorige = jetzt }; return jetzt == vorige }
                    }
                    if let unter = haupt.attachedSheet?.attachedSheet {
                        await hoeheSteht(unter)
                        let angenommen = speicher.lernendenblattGriff?.einzelneImUnterblatt() == true
                        _ = await warten(bis: { unter.attachedSheet != nil })
                        if angenommen, let bogen = unter.attachedSheet {
                            await hoeheSteht(bogen)
                            let unten = bogen.screen?.visibleFrame.minY ?? 0
                            let ueberDock = (bogen.frame.minY - unten).rounded()
                            func spanne(_ f: NSWindow?) -> String {
                                guard let f else { return "—" }
                                return "\(Int(f.frame.height.rounded())) hoch, \(Int((f.frame.minY - unten).rounded()))…"
                                    + "\(Int((f.frame.maxY - unten).rounded()))"
                            }
                            // Die Höhe: rundum 40 pt kleiner als das Blatt „Lernende“, höchstens 600 (R-BH8-W2-01, wie E1108).
                            let sollH = AdressatenBogen.hoehe(blatt: haupt.attachedSheet?.frame.height ?? LernendenDialog.blatthoehe)
                            pruefen(ueberDock >= Seitenleistenmass.abstandUnten - 1 && abs(bogen.frame.height - sollH) <= 1,
                                    "\(ort): „Einzelne …“ von Hand auf „Neue Mitteilung“ \(Int(bogen.frame.height.rounded())) hoch "
                                        + "(soll \(Int(sollH))), endet \(Int(ueberDock)) pt über dem Rand der "
                                        + "sichtbaren Fläche (mindestens \(Int(Seitenleistenmass.abstandUnten)), E1150, R-BH8N-01) — Blatt "
                                        + "„Lernende“ \(spanne(haupt.attachedSheet)), „Neue Mitteilung“ \(spanne(unter)), „Einzelne …“ "
                                        + "\(spanne(bogen))")
                        } else {
                            pruefen(false, "\(ort): „Einzelne …“ ging auf dem stehenden Unterblatt nicht auf (R-BH8N-01)")
                        }
                    } else {
                        pruefen(false, "\(ort): das Unterblatt „Neue Mitteilung“ ging aus der Vorgabe nicht auf (R-BH8N-01)")
                    }
                    // Zurück wie von Hand: ⎋ auf jeder Ebene, von oben nach unten.
                    for _ in 0..<3 {
                        guard var oben = haupt.attachedSheet else { break }
                        while let darauf = oben.attachedSheet { oben = darauf }
                        tasteAn(oben, "\u{1B}", code: 53)
                        _ = await warten(4) { oben.sheetParent == nil || !oben.isVisible }
                    }
                    if haupt.attachedSheet != nil {
                        pruefen(false, "\(ort): nach dem Bogen „Einzelne …“ blieb ein Blatt offen")
                        speicher.alleDialogeSchliessen()
                        _ = await warten(4) { haupt.attachedSheet == nil }
                    }
                }
                @MainActor func sitzplanKlein(_ ort: String, soll: Int, ganz: Bool, muss: Bool) async {
                    speicher.sitzplaene.setzen(Sitzplan.anordnen(klasseId: klasse.id, namen: ["Ada", "Alan", "Grace"]),
                                               fuer: klasse.id)
                    speicher.sitzplanOeffnen(klasse: klasse.id)
                    guard await warten(bis: { haupt.attachedSheet.flatMap { suchen($0.contentView) { (_: Sitzplanansicht) in true } }
                                                != nil }),
                          let blatt = haupt.attachedSheet,
                          let flaeche = suchen(blatt.contentView, { (_: Sitzplanansicht) in true }) else {
                        pruefen(false, "\(ort): der Sitzplan-Editor ging nicht auf")
                        return
                    }
                    await vorndran(blatt)
                    await steht(blatt, bestellt: 700, soll: soll)
                    let lage = Self.blatthoehe(blatt, bestellt: 700)
                    let breite = Int(blatt.frame.width.rounded())
                    var erreichbar = false
                    var auskunft = "die Fläche liegt in keiner Rollfläche"
                    if let rolle = flaeche.enclosingScrollView, let inhalt = rolle.documentView {
                        let hoch = inhalt.frame.height, sichtbar = rolle.contentView.bounds.height
                        let rollt = hoch > sichtbar + 1
                        // Ans Ende rollen wie mit dem Rad, dann die Fläche im Ausschnitt suchen.
                        rolle.contentView.scroll(to: NSPoint(x: 0, y: inhalt.isFlipped ? max(0, hoch - sichtbar) : 0))
                        rolle.reflectScrolledClipView(rolle.contentView)
                        await schlangeLeeren()
                        let rahmen = flaeche.convert(flaeche.bounds, to: rolle.contentView)
                        let ausschnitt = rolle.contentView.bounds.insetBy(dx: -0.5, dy: -0.5)
                        let unterkante = rolle.contentView.isFlipped ? rahmen.maxY : rahmen.minY
                        let unten = unterkante >= ausschnitt.minY && unterkante <= ausschnitt.maxY
                        erreichbar = (ganz ? ausschnitt.contains(rahmen) : unten) && (!muss || rollt)
                        auskunft = "der Körper \(Int(hoch.rounded())) hoch (mindestens der Ausschnitt), sichtbar \(Int(sichtbar.rounded())), "
                            + "rollt \(rollt); nach dem Rollen ans Ende " + (ganz ? "die Fläche ganz" : "ihre Unterkante")
                            + " zu sehen \(ganz ? ausschnitt.contains(rahmen) : unten)"
                            + (speicher.verschluesselungsstand == .aus ? " (mit Datenschutzhinweis)" : " (ohne Datenschutzhinweis)")
                        rolle.contentView.scroll(to: NSPoint(x: 0, y: inhalt.isFlipped ? 0 : max(0, hoch - sichtbar)))
                        rolle.reflectScrolledClipView(rolle.contentView)
                    }
                    pruefen(innen(blatt) == soll && abs(blatt.frame.width - 820) < 1 && lage.gilt && erreichbar,
                            "\(ort): Sitzplan-Editor \(breite) breit (soll 820, E1192), \(lage.text), erwartet \(soll); "
                            + auskunft)
                    tasteAn(blatt, "\u{1B}", code: 53)
                    _ = await warten(4) { haupt.attachedSheet == nil }
                }
                if platz {
                    Self.hauptfensterVorher = vorher
                    Self.hauptfensterVerschoben = haupt
                    // Anliegend: 700 − 40; mittig wäre das Blatt mit 700 + Kopf − 80 begrenzt (`hoechstens`).
                    let sollAnliegend = Int(min(660, 620 + kopf).rounded())
                    if !(await legen(sichtbar: 700, darunter: 0)) {
                        pruefen(false, "\(klein): das Hauptfenster ließ sich nicht mit 700 pt unter dem Kopf an den Rand legen "
                                + "— die Zeilen dieser Lage entfallen")
                    } else {
                        speicher.vorhabenDialog = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
                        _ = await warten(bis: { blattMit(zeilen: 7) != nil })
                        if let blatt = blattMit(zeilen: 7), let tabelle = seitenleiste(blatt) {
                            await vorndran(blatt)
                            await steht(blatt, bestellt: 820, soll: sollAnliegend)
                            let lage = Self.blatthoehe(blatt, bestellt: 820)
                            let ganz = (0..<tabelle.numberOfRows).allSatisfy { zeile in
                                let rahmen = tabelle.rect(ofRow: zeile), sicht = tabelle.visibleRect
                                return rahmen.minY >= sicht.minY - 0.5 && rahmen.maxY <= sicht.maxY + 0.5
                            }
                            pruefen(innen(blatt) == sollAnliegend && lage.gilt && rollt(blatt) && ganz,
                                    "\(klein): Vorhaben-Blatt \(lage.text), erwartet \(sollAnliegend); das Formular rollt "
                                    + "\(rollt(blatt)), die Leiste mit \(tabelle.numberOfRows) Zeilen ganz \(ganz)")
                            // Das Fenster mit dem Blatt zurück an seinen Platz, dann der Bogen (R-BG8b-01): Bogen = gemessene
                            // Blatthöhe − 80, das Blatt unverändert (R-BG8bn2-03).
                            let blattVorher = innen(blatt)
                            let zurueck = await zuruecklegen()
                            speicher.materialienErlauben(true)
                            speicher.materialblattOffen = true
                            _ = await warten(8) { blatt.attachedSheet != nil }
                            _ = await warten(2) { blatt.attachedSheet.map(innen) == blattVorher - 80 }
                            let bogen = blatt.attachedSheet.map(innen) ?? 0
                            pruefen(zurueck && bogen == blattVorher - 80 && innen(blatt) == blattVorher,
                                    "\(klein): nachdem das Fenster wieder Platz hat (zurückgelegt \(zurueck)) — Blatt \(innen(blatt)) "
                                    + "wie beim Öffnen (\(blattVorher)), Material-Bogen \(bogen) hoch (Blatt − 80, E1108, R-BG8b-01)")
                            speicher.materialblattOffen = false
                            _ = await warten(4) { blatt.attachedSheet == nil }
                            speicher.materialienErlauben(false)
                        } else {
                            pruefen(false, "\(klein): das Vorhaben-Blatt mit seiner Leiste (7 Zeilen) ging nicht auf")
                        }
                        speicher.vorhabenDialog = nil
                        _ = await warten(4) { haupt.attachedSheet == nil }
                        if !(await legen(sichtbar: 700, darunter: 0)) {
                            pruefen(false, "\(klein): das Hauptfenster ließ sich nicht wieder an den Rand legen — ⌘K und die "
                                    + "Einstellungen entfallen")
                        } else {
                            speicher.offenerDialog = .klassen
                            if await warten(bis: { blattMit(zeilen: 3) != nil }), let blatt = blattMit(zeilen: 3) {
                                await steht(blatt, bestellt: 820, soll: sollAnliegend)
                                let lage = Self.blatthoehe(blatt, bestellt: 820)
                                pruefen(innen(blatt) == sollAnliegend && lage.gilt, "\(klein): ⌘K \(lage.text), erwartet \(sollAnliegend)")
                            } else {
                                pruefen(false, "\(klein): ⌘K (Leiste mit 3 Zeilen) ging nicht auf")
                            }
                            speicher.offenerDialog = nil
                            _ = await warten(4) { haupt.attachedSheet == nil }
                            speicher.offenerDialog = .einstellungen
                            if await warten(bis: { blattMit(zeilen: 6) != nil }), let blatt = blattMit(zeilen: 6) {
                                await steht(blatt, bestellt: 640, soll: 640)
                                let lage = Self.blatthoehe(blatt, bestellt: 640)
                                pruefen(innen(blatt) == 640 && lage.gilt, "\(klein): Einstellungen \(lage.text), erwartet 640")
                            } else {
                                pruefen(false, "\(klein): die Einstellungen (Leiste mit 6 Zeilen) gingen nicht auf")
                            }
                            speicher.offenerDialog = nil
                            _ = await warten(4) { haupt.attachedSheet == nil }
                            // Der Sitzplan-Editor wie das Vorhaben-Blatt (BH4, E1158): anliegend, die Fläche ganz zu sehen.
                            await sitzplanKlein(klein, soll: sollAnliegend, ganz: true, muss: false)
                            await lernendeKlein(klein, soll: sollAnliegend)
                            // Auskunft (BH4, E1158): die Höhe mit der Namensliste — an derselben Klasse, ihr Plan
                            // vorübergehend entfernt (die Planung der Probe hat nur sie; die nächste Lage setzt ihn neu).
                            do {
                                speicher.sitzplaene.setzen(nil, fuer: klasse.id)
                                speicher.sitzplanOeffnen(klasse: klasse.id)
                                if await warten(bis: { blattMit(zeilen: nil) != nil }), let blatt = blattMit(zeilen: nil) {
                                    /// Die Rollfläche des Körpers — nicht die des Namensfelds.
                                    @MainActor func koerper() -> NSScrollView? {
                                        suchen(blatt.contentView) { (rolle: NSScrollView) in
                                            rolle.documentView != nil && !(rolle.documentView is NSTextView)
                                        }
                                    }
                                    _ = await warten(2) { koerper() != nil }
                                    let text = koerper().flatMap { rolle in
                                        rolle.documentView.map { "\(Int($0.frame.height.rounded())) hoch (mindestens der Ausschnitt), sichtbar "
                                            + "\(Int(rolle.contentView.bounds.height.rounded()))" }
                                    } ?? "ohne Rollfläche"
                                    print("  Auskunft \(klein): Sitzplan-Editor mit der Namensliste — der Körper \(text)"
                                          + (speicher.verschluesselungsstand == .aus ? " (mit Datenschutzhinweis)"
                                                                                    : " (ohne Datenschutzhinweis)"))
                                    fflush(stdout)
                                    tasteAn(blatt, "\u{1B}", code: 53)
                                    _ = await warten(4) { haupt.attachedSheet == nil }
                                } else {
                                    print("  Auskunft \(klein): der Sitzplan-Editor mit der Namensliste ging nicht auf")
                                    fflush(stdout)
                                }
                            }
                            // Auskunft (R-BG8bn-06): Rollt die Verschlüsselung in voller Höhe schon? Dann stünde eine
                            // Fehlerzeile auch auf großem Bildschirm erst nach dem Rollen.
                            speicher.offenerDialog = .verschluesselung
                            if await warten(bis: { haupt.attachedSheet != nil && blattMit(zeilen: nil) != nil }),
                               let blatt = blattMit(zeilen: nil) {
                                await steht(blatt, bestellt: 640, soll: 640)
                                print("  Auskunft \(klein): Verschlüsselung \(innen(blatt)) hoch, das Formular rollt \(rollt(blatt)) "
                                      + "(\(speicher.verschluesselt ? "Übersicht" : "Schritt Passphrase"))")
                                fflush(stdout)
                            }
                            speicher.offenerDialog = nil
                            _ = await warten(4) { haupt.attachedSheet == nil }
                        }
                    }
                    // Das Fenster ragt 60 pt unter die sichtbare Fläche (unter dem Kopf 640 pt bis zum Rand): Die Blätter
                    // stehen mittig im Fenster, höchstens (Fensterunterkante + Fensteroberkante − 2 · Rand) − 80 = 500 + Kopf.
                    let sollMittig = Int(min(600, 500 + kopf).rounded())
                    let sollMittigKlein = Int(min(600, min(640, 500 + kopf)).rounded())
                    if !(await legen(sichtbar: 640, darunter: 60)) {
                        pruefen(false, "\(klein): das Hauptfenster ließ sich nicht 60 pt unter den Rand legen — die Zeilen dieser "
                                + "Lage entfallen")
                    } else {
                        speicher.vorhabenDialog = VorhabenEntwurf(klasseId: klasse.id, woche: 0)
                        _ = await warten(bis: { blattMit(zeilen: 7) != nil })
                        if let blatt = blattMit(zeilen: 7) {
                            await steht(blatt, bestellt: 820, soll: sollMittig)
                            let lage = Self.blatthoehe(blatt, bestellt: 820)
                            pruefen(innen(blatt) == sollMittig && lage.gilt,
                                    "\(klein), das Fenster 60 pt unter dem Rand: Vorhaben-Blatt \(lage.text), erwartet \(sollMittig)")
                            // Die Material-Frage bleibt in ihrem Blatt: 640 breit, höchstens gemessene Blatthöhe − 80
                            // (R-BG8bn-01, R-BG8bn2-03, -04).
                            speicher.materialienErlauben(false)
                            speicher.materialblattOffen = true
                            _ = await warten(8) { blatt.attachedSheet != nil }
                            // Der Bogen geht im Zustand „lädt“ breit auf und stellt erst danach auf die Frage um — erst messen,
                            // wenn sie steht (R-BG8bn3-01).
                            _ = await warten(2) { blatt.attachedSheet.map { abs($0.frame.width - 640) < 1 } == true }
                            let frage = blatt.attachedSheet.map(innen) ?? 0
                            let fragebreite = Int((blatt.attachedSheet?.frame.width ?? 0).rounded())
                            pruefen(fragebreite == 640 && frage > 0 && frage <= innen(blatt) - 80,
                                    "\(klein), das Fenster 60 pt unter dem Rand: Material-Frage \(fragebreite) × \(frage), höchstens "
                                    + "Blatt − 80 = \(innen(blatt) - 80) hoch (E1108, E1150; Kopf \(Int(kopf.rounded())) pt)")
                            speicher.materialblattOffen = false
                            _ = await warten(4) { blatt.attachedSheet == nil }
                        } else {
                            pruefen(false, "\(klein): das Vorhaben-Blatt mit seiner Leiste (7 Zeilen) ging am tiefen Fenster nicht auf")
                        }
                        speicher.vorhabenDialog = nil
                        _ = await warten(4) { haupt.attachedSheet == nil }
                        // Einstellungen und Verschlüsselung (beide 640 bestellt) ebenso begrenzt (R-BG8bn-01, E1154); die
                        // Einstellungen 780 breit (E1121), die Verschlüsselung 744 (E1156) — feste Sollwerte, nicht die
                        // Konstanten des Blatts (R-BG8c-05).
                        for (dialog, name, zeilen, breite, grund) in [
                            (Dialogfenster.einstellungen, "Einstellungen", Int?.some(6), CGFloat(780), "E1121"),
                            (Dialogfenster.verschluesselung, "Verschlüsselung", Int?.none, CGFloat(744), "E1156")] {
                            speicher.offenerDialog = dialog
                            if await warten(bis: { haupt.attachedSheet != nil && blattMit(zeilen: zeilen) != nil }),
                               let blatt = blattMit(zeilen: zeilen) {
                                await steht(blatt, bestellt: 640, soll: sollMittigKlein)
                                let lage = Self.blatthoehe(blatt, bestellt: 640)
                                pruefen(innen(blatt) == sollMittigKlein && abs(blatt.frame.width - breite) < 1 && lage.gilt,
                                        "\(klein), das Fenster 60 pt unter dem Rand: \(name) \(Int(blatt.frame.width.rounded())) breit "
                                        + "(soll \(Int(breite)), \(grund)), \(lage.text), erwartet \(sollMittigKlein) (E1154)")
                            } else {
                                pruefen(false, "\(klein): \(name) ging am tiefen Fenster nicht auf")
                            }
                            speicher.offenerDialog = nil
                            _ = await warten(4) { haupt.attachedSheet == nil }
                        }
                        // Der Sitzplan-Editor mittig im Fenster (BH4, E1158): Der Ausschnitt ist niedriger als die Fläche — sie
                        // rollt, und ihre Unterkante ist erreichbar.
                        await sitzplanKlein("\(klein), das Fenster 60 pt unter dem Rand", soll: sollMittig, ganz: false, muss: true)
                        await lernendeKlein("\(klein), das Fenster 60 pt unter dem Rand", soll: sollMittig)
                    }
                    let zurueckAmEnde = await zuruecklegen()
                    Self.hauptfensterVorher = nil
                    Self.hauptfensterVerschoben = nil
                    pruefen(zurueckAmEnde, "\(klein): das Hauptfenster liegt wieder an seinem Platz")
                }
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

            // ── Ein Blatt am minimierten Hauptfenster (R-BG8bn-06; v96, BH3, V4 → E1166) ──
            // Lage und Höhe nach dem Messmuster (E1150), gemessen, wenn das Blatt steht (R-BG8bn2-05, R-BH3N-03).
            // Das Blatt bleibt bestellt, bis das Fenster wieder da ist: Zeigt SwiftUI es erst nach dem Zurückholen, wird
            // dort gemessen (R-BH3-03). „Ausgeschlossen“ nur, wenn die App die Bestellung selbst zurücknimmt; bleibt sie
            // stehen und kommt auch nach dem Zurückholen kein Blatt, ist es verloren — ein ✗ (R-BH3N-02). Je Ursache ein
            // Grund (R-BH3-06).
            do {
                await vorndran(haupt)
                if let k = speicher.planung?.klassen.first {
                    haupt.miniaturize(nil)
                    if await warten(3, bis: { haupt.isMiniaturized }) {
                        speicher.vorhabenDialog = VorhabenEntwurf(klasseId: k.id, woche: 0)
                        let imDock = await warten(4) { haupt.attachedSheet != nil }
                        var auf = imDock
                        if !imDock {
                            haupt.deminiaturize(nil)
                            _ = await warten(3) { !haupt.isMiniaturized }
                            auf = await warten(6) { haupt.attachedSheet != nil }
                        }
                        if auf, let blatt = haupt.attachedSheet {
                            _ = await warten(2) { Self.blatthoehe(blatt, bestellt: 820).gilt }
                            let nochMinimiert = haupt.isMiniaturized
                            let lage = Self.blatthoehe(blatt, bestellt: 820)
                            pruefen(lage.gilt, "Dock · ein Blatt am minimierten Hauptfenster"
                                    + (imDock ? " (aufgegangen im Dock, gemessen "
                                                + (nochMinimiert ? "im Dock)" : "nach dem Zurückholen)")
                                              : " (erst nach dem Zurückholen)")
                                    + ": \(lage.text) (R-BG8bn-06)")
                        } else if speicher.vorhabenDialog == nil {
                            zeilen.append("  Dock · am minimierten Hauptfenster nimmt die App das Blatt zurück — Fall "
                                          + "ausgeschlossen (R-BG8bn-06)")
                            print(zeilen.last!); fflush(stdout)
                        } else {
                            pruefen(false, "Dock · das Blatt ist bestellt, steht aber auch 6 s nach dem Zurückholen nicht am "
                                    + "Hauptfenster — verloren (R-BH3N-02)")
                        }
                        speicher.vorhabenDialog = nil
                        if haupt.isMiniaturized { haupt.deminiaturize(nil); _ = await warten(3) { !haupt.isMiniaturized } }
                        pruefen(await warten(4, bis: { haupt.attachedSheet == nil }),
                                "Dock · nach dem Fall steht kein Blatt mehr am Hauptfenster (R-BG8bn-06)")
                    } else {
                        pruefen(false, "Dock · das Hauptfenster ließ sich für das Blatt nicht minimieren")
                    }
                    if haupt.isMiniaturized { haupt.deminiaturize(nil); _ = await warten(3) { !haupt.isMiniaturized } }
                } else {
                    pruefen(false, "Dock · keine Klasse für das Blatt am minimierten Hauptfenster")
                }
            }

            // ── ⌘Q holt das Fenster aus dem Dock (Z14c3-08, E329) ──────────────
            // Erst minimieren, dann fragen. Beendet wird nur, wenn die Frage
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

    /// Der Rahmen des Hauptfensters vor dem Fall „Kleiner Bildschirm“ und das Fenster selbst — für die Reißleine
    /// (R-BG8bn-04, R-BG8bn2-01).
    static var hauptfensterVorher: NSRect?
    static weak var hauptfensterVerschoben: NSWindow?

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

    /// Die Höhe eines Blatts nach E1150, am Fenster gemessen — nicht nachgerechnet: Das Blatt liegt, wo macOS es nach dem
    /// gemessenen Muster hinsetzt (mittig im ganzen Fenster, nie über der Unterkante des Fensterkopfs) — weicht ein System
    /// davon ab, stimmt die Rechnung der App dort nicht —, und es ist so hoch wie bestellt — dann mindestens 40 pt über
    /// dem unteren Rand der sichtbaren Fläche — oder endet genau 40 pt darüber (bzw. hat die Mindesthöhe).
    static func blatthoehe(_ blatt: NSWindow, bestellt: CGFloat) -> (gilt: Bool, text: String) {
        let innen = blatt.contentRect(forFrameRect: blatt.frame).height
        guard let eltern = blatt.sheetParent, let schirm = eltern.screen else {
            return (false, "\(Int(innen)) hoch, ohne Elternfenster oder Bildschirm (E1150)")
        }
        let abstand = Seitenleistenmass.abstandUnten
        let kopfUnten = eltern.frame.minY + eltern.contentLayoutRect.maxY
        let erwartetUnten = min(kopfUnten - blatt.frame.height, (eltern.frame.minY + eltern.frame.maxY - blatt.frame.height) / 2)
        let lageStimmt = abs(blatt.frame.minY - erwartetUnten) <= 1
        let ueberDock = blatt.frame.minY - schirm.visibleFrame.minY
        let voll = abs(innen - bestellt) < 0.5
        let passt = voll ? ueberDock >= abstand - 1
                         : abs(ueberDock - abstand) <= 1 || abs(innen - Seitenleistenmass.mindesthoehe) < 0.5
        return (lageStimmt && passt, "\(Int(innen)) hoch (bestellt \(Int(bestellt))), oben "
                + "\(Int((kopfUnten - blatt.frame.maxY).rounded())) pt unter dem Fensterkopf, unten "
                + "\(Int(ueberDock.rounded())) pt über dem Rand der sichtbaren Fläche"
                + (lageStimmt ? "" : ", Lage weicht vom Muster ab (unten erwartet \(Int(erwartetUnten.rounded())), "
                                   + "gemessen \(Int(blatt.frame.minY.rounded())))") + " (E1150)")
    }

    /// Ein Tastendruck an ein Fenster über die Ereignisschlange — wie `taste` im Lauf, der hier noch nicht erklärt ist
    /// (R-BH4-02).
    static func tastePosten(_ fenster: NSWindow, _ zeichen: String, code: UInt16) {
        if let ereignis = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: fenster.windowNumber,
                                           context: nil, characters: zeichen, charactersIgnoringModifiers: zeichen,
                                           isARepeat: false, keyCode: code) {
            NSApp.postEvent(ereignis, atStart: false)
        }
    }

    /// Die Sitzplanfläche in einem Blatt (BH4).
    static func sitzplanansicht(_ blatt: NSWindow?) -> Sitzplanansicht? {
        func suchen(_ ansicht: NSView?) -> Sitzplanansicht? {
            guard let ansicht else { return nil }
            if let flaeche = ansicht as? Sitzplanansicht { return flaeche }
            for kind in ansicht.subviews { if let flaeche = suchen(kind) { return flaeche } }
            return nil
        }
        return suchen(blatt?.contentView)
    }

    /// Die gewählte Zeile der Leiste im Blatt (Kennung „Seitenleiste“), −1 ohne Leiste — für die Rückwege nach ⌘K
    /// (E1133, R-BG5c-03).
    static func leistenwahl(_ blatt: NSWindow?) -> Int {
        seitenleisteIn(blatt)?.selectedRow ?? -1
    }

    /// Die Leiste eines Blatts — die Tabelle mit der Kennung „Seitenleiste“.
    static func seitenleisteIn(_ blatt: NSWindow?) -> NSTableView? {
        func suchen(_ ansicht: NSView?) -> NSTableView? {
            guard let ansicht else { return nil }
            if let tabelle = ansicht as? NSTableView, tabelle.identifier?.rawValue == "Seitenleiste" { return tabelle }
            for kind in ansicht.subviews { if let tabelle = suchen(kind) { return tabelle } }
            return nil
        }
        return suchen(blatt?.contentView)
    }

    /// Ein Klick auf die Mitte der Zeile, wie von Hand: Maus nieder und auf an das Fenster der Tabelle. Trifft der
    /// Punkt nicht die Tabelle, kein Klick — nur der Grund; sonst träfe er, was darüber liegt (R-BG5-04).
    static func zeileKlicken(_ tabelle: NSTableView, _ zeile: Int) -> String? {
        guard let fenster = tabelle.window, zeile < tabelle.numberOfRows else { return "keine Zeile \(zeile)" }
        let mitte = tabelle.rect(ofRow: zeile)
        let punkt = tabelle.convert(NSPoint(x: mitte.midX, y: mitte.midY), to: nil)
        let getroffen = fenster.contentView?.superview?.hitTest(punkt)
        guard getroffen?.isDescendant(of: tabelle) == true else {
            return "der Punkt trifft \(getroffen.map { "\(type(of: $0))" } ?? "nichts") statt der Tabelle"
        }
        for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: fenster.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                NSApp.postEvent(ereignis, atStart: false)
            }
        }
        return nil
    }
}
