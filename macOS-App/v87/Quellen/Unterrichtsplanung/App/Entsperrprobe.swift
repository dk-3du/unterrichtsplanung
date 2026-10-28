// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import LocalAuthentication

/// Das Freigabeblatt am echten Fenster, so wie VoiceOver es sieht.
@MainActor
enum Entsperrprobe {

    /// `--entsperrtest passphrase|wiederherstellung|gemischt|enklave|tot|uebernahme`: das
    /// Freigabeblatt am echten Fenster, so wie VoiceOver es sieht — haben die
    /// Felder eine Breite, schaltet Tippen den Knopf frei, entsperrt ⏎? Braucht
    /// eine versiegelte `planung.json` im PLANUNGSORDNER (`uebernahme`: einen leeren); Passphrase und
    /// Schlüssel kommen aus `ENTSPERRPROBE_PASSPHRASE` und
    /// `ENTSPERRPROBE_SCHLUESSEL`, Abbilder je Schritt nach `ENTSPERRBILD`
    /// (Pfadanfang), die ganze Elementliste mit `ENTSPERRPROBE_ALLES`.
    /// Die Knöpfe des Blatts sieht der eigene Prozess nicht (SwiftUI); ihre
    /// Freigabe wird am Verhalten gemessen — ⏎ leer löst nichts aus (E143, v66).
    /// `ENTSPERRPROBE_MERKEN=0|1` schaltet das Häkchen „Mit Touch ID öffnen“;
    /// mit `ENTSPERRPROBE_ENKLAVE=1` zählt die Enklave auch im Prüfstand:
    /// `enklave` erwartet zuerst die Systemabfrage ohne Blatt, bricht sie ab
    /// und will dann das Blatt; `tot` tippt wie `passphrase`, meldet aber den
    /// Hinweis auf die unbrauchbare Wicklung. `uebernahme` (E702, E707): ein frischer
    /// Mac ohne Planung und ohne Verschlüsselung öffnet die versiegelte Datei
    /// `ENTSPERRPROBE_DATEI` (außerhalb der Ablage) wie aus dem Finder — aus „Neue
    /// Planungsdatei“, mit `ENTSPERRPROBE_FRAGE1=1` aus Frage 1 der Ersteinrichtung
    /// (E716, Abbild `-frage1`) —, wartet, bis das Blatt „Planung übernehmen“
    /// (`.entsperren` mit `entsperrungUebernimmt`) steht, und geht dann den Weg
    /// `passphrase`; danach, ob Passphrase und Wiederherstellungsschlüssel der Datei
    /// die Ablage öffnen und ob der Titel irgendwo im Klartext liegt. Ein Befund
    /// vor dem Blatt beendet den Lauf (eine Ursache, ein ✗). `ENTSPERRPROBE_VORBEREITEN=1` bereitet vorher eine
    /// Verschlüsselung vor wie Frage 1 mit „Weiter zur Planung“ (E719) — schließt `ENTSPERRPROBE_FRAGE1` aus;
    /// `ENTSPERRPROBE_FRAGE2=1` öffnet nach der Übernahme die Ersteinrichtung, wie es auf einem frischen Mac die Kette
    /// tut, prüft die Zählung (mit Frage 1 oder Vorbereitung „Frage 2 von 4“, sonst „Frage 1 von 3“, E355) und den
    /// Hinweis auf die verworfene Vorbereitung (genau mit Vorbereitung, E720) und legt `-frage2` ab. Am Ende immer der
    /// Kopf der Ablage.
    static func laufenUndBeenden(_ speicher: Planungsspeicher, weg: String) {
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
            /// Ein Abbild, sobald das Blatt steht — früher ist das Bild weiß.
            @MainActor func ablegen(_ fenster: NSWindow, _ name: String) async {
                guard let bildanfang else { return }
                try? await Task.sleep(for: .milliseconds(900))
                Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: bildanfang + "-" + name + ".png"))
            }
            // Ein Befund, der das Abschicken verhindert — was danach scheitert, ist seine Folge (Z-AW1bN-06).
            var ursache = false
            // Ein Befund vor dem Blatt beendet den Lauf — über die Endstelle, die offene Blätter schließt
            // (Z-AW1b-02, -03): Danach gäbe es nur Folge-✗, womöglich an einem fremden Blatt.
            @MainActor func abbrechen(_ zeile: String) async {
                zeilen.append(zeile)
                print(zeilen.joined(separator: "\n"))
                await Pruefstaende.abschliessenUndBeenden(speicher)
            }
            // Ein Blatt steht, wenn der Speicher es führt und das Fenster es trägt. Ein neues kommt erst, wenn
            // das alte fort ist (`naechsterDialog`) — darum zählt der Dialog, nicht irgendein Blatt (Z-AW1b-04).
            @MainActor func steht(_ dialog: Dialogfenster) async -> NSWindow? {
                for _ in 0..<40 where speicher.offenerDialog != dialog || sichtbaresFenster()?.attachedSheet == nil {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                return speicher.offenerDialog == dialog ? sichtbaresFenster()?.attachedSheet : nil
            }
            if weg == "uebernahme" {
                // Im Prüfstand steht beim Start „Neue Planungsdatei“ (die Einrichtung ist dort nie fällig); beim ersten
                // Start auf einem frischen Mac steht Frage 1 — mit `ENTSPERRPROBE_FRAGE1=1` tritt sie an ihre Stelle (E716).
                let anfang = await steht(.neuePlanung)
                guard speicher.planung == nil, speicher.verschluesselungsstand == .aus, anfang != nil else {
                    await abbrechen("  vorher: keine Planung, keine Verschlüsselung, „Neue Planungsdatei“ ✗ — Stand "
                                    + "\(speicher.verschluesselungsstand), Blatt \(speicher.offenerDialog?.rawValue ?? "—")")
                    return
                }
                zeilen.append("  vorher: keine Planung, keine Verschlüsselung, „Neue Planungsdatei“ steht ✓")
                if umgebung["ENTSPERRPROBE_FRAGE1"] == "1" {
                    speicher.ersteinrichtungsschritt = .verschluesselung
                    speicher.dialogOeffnen(.ersteinrichtung)
                    guard let frage1 = await steht(.ersteinrichtung) else {
                        await abbrechen("  Frage 1 der Ersteinrichtung kam nicht ✗ — Blatt "
                                        + "\(speicher.offenerDialog?.rawValue ?? "—")")
                        return
                    }
                    zeilen.append("  Frage 1 der Ersteinrichtung steht, wie beim ersten Start ✓")
                    await ablegen(frage1, "frage1")
                }
                guard let datei = umgebung["ENTSPERRPROBE_DATEI"] else {
                    await abbrechen("  ENTSPERRPROBE_DATEI fehlt ✗")
                    return
                }
                if umgebung["ENTSPERRPROBE_VORBEREITEN"] == "1" {
                    // Der echte Weg: „Weiter zur Planung“ — vorbereitet, „Neue Planungsdatei“ steht (Z-AW1bM-03). Auf der
                    // ersten Seite von Frage 1 gibt es keine Vorbereitung.
                    guard umgebung["ENTSPERRPROBE_FRAGE1"] != "1" else {
                        await abbrechen("  ENTSPERRPROBE_VORBEREITEN und ENTSPERRPROBE_FRAGE1 schließen einander aus ✗")
                        return
                    }
                    let vorbereitet = (try? speicher.verschluesselungVorbereiten(passphrase: "Eigene Passphrase 2026")) != nil
                    if vorbereitet { speicher.verschluesselungsfrage = .vorbereitet }
                    zeilen.append("  Verschlüsselung vorbereitet wie mit „Weiter zur Planung“ (E719): " + (vorbereitet ? "ja ✓" : "nein ✗"))
                }
                speicher.importieren(von: URL(fileURLWithPath: datei))
                guard speicher.entsperrungUebernimmt else {
                    await abbrechen("  geöffnet „\((datei as NSString).lastPathComponent)“: keine Übernahme ✗ — „"
                                    + "\(speicher.meldungen.last?.text ?? "–")“")
                    return
                }
                zeilen.append("  geöffnet „\((datei as NSString).lastPathComponent)“: Übernahme begonnen ✓")
                guard await steht(.entsperren) != nil else {
                    await abbrechen("  das Blatt „Planung übernehmen“ kam nicht ✗ — Blatt "
                                    + "\(speicher.offenerDialog?.rawValue ?? "—")")
                    return
                }
            }
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
                    Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: bildanfang + "-leerzustand.png"))
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
                Pruefstaende.abschliessenUndBeenden()
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
            // Der Wicklungsbericht fand keinen lesbaren Kopf — eine spätere Zeile dazu ist seine Folge (Z-AW1bM-04).
            var kopfBefund = false
            @MainActor func wicklungsbericht() async {
                guard let roh = try? Data(contentsOf: speicher.sicherung.ablage.datei),
                      let kopf = try? Tresor.kopfLesen(roh) else {
                    kopfBefund = true
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
            // Die Knöpfe des Blatts („Entsperren“, „Abbrechen“, „Stattdessen …“)
            // sind SwiftUI-Knöpfe: Im Bedienungshilfen-Baum, wie der eigene
            // Prozess ihn sieht, erscheinen sie nur als Geometrie ohne Rolle und
            // Namen (gemessen 16.09.2026: `_FocusRingView` 90×24 zweimal, 359×24
            // einmal). Bis v65 suchte dieser Lauf einen `AXButton` „Entsperren“
            // und meldete dreimal je Runde „NICHT GEFUNDEN ✗“, ohne dass etwas
            // falsch war (seit v49). Seit v66 (E143) wird die Freigabe des Knopfs
            // am **Verhalten** gemessen: ⏎ bei leerem Feld löst nichts aus (der
            // gesperrte Knopf), ⏎ nach dem Tippen löst aus (`abschicken`).
            @MainActor func knopfgeometrie() -> String {
                var zahl = 0
                for e in elemente() {
                    let rolle = e.accessibilityRole()
                    guard rolle == nil || rolle == .unknown else { continue }
                    let r: NSRect = e.accessibilityFrame()
                    let knopfhoch: Bool = r.height > 20 && r.height < 30
                    let knopfbreit: Bool = r.width >= 60 && r.width < 400
                    if knopfhoch && knopfbreit { zahl += 1 }
                }
                return "\(zahl) Knopfrahmen ohne Rolle und Namen"
            }
            /// ⏎ bei leerem Feld: Der Knopf ist gesperrt, das Feld weist leere
            /// Eingabe ab — es darf kein Versuch entstehen und kein Fehlertext.
            @MainActor func leerAbschicken() async -> Bool {
                let fehlerVorher = speicher.entsperrungFehler
                let standVorher = speicher.verschluesselungsstand
                taste("\r", code: 36)
                try? await Task.sleep(for: .milliseconds(700))
                let nichts = speicher.verschluesselungsstand == standVorher
                    && speicher.entsperrungFehler == fehlerVorher && !speicher.entsperrungLaeuft
                if !nichts { ursache = true }
                zeilen.append("    ⏎ bei leerem Feld: " + (nichts ? "nichts geschieht ✓ (Knopf gesperrt)"
                    : "ETWAS GESCHIEHT ✗ — Stand \(speicher.verschluesselungsstand), Fehler „\(speicher.entsperrungFehler ?? "–")“, läuft \(speicher.entsperrungLaeuft)"))
                return nichts
            }
            /// Nach der Übernahme (E707): Stand und Planung, die Wicklungen der Datei in der Ablage, die
            /// Passphrase der Datei öffnet sie, und der Titel liegt nirgends im Klartext.
            @MainActor func uebernahmeBericht() async {
                guard let titel = speicher.planung?.titel, speicher.verschluesselungsstand == .an else {
                    // Eine Ursache, ein ✗: Verhinderte oben ein Befund das Abschicken, ist dies seine Folge (Z-AW1bN-06).
                    zeilen.append("  nicht übernommen — Stand \(speicher.verschluesselungsstand)"
                                  + (ursache ? " (Folge des Befunds oben)" : " ✗"))
                    return
                }
                zeilen.append("  übernommen: Planung „\(titel)“, Verschlüsselung an ✓")
                guard let roh = try? Data(contentsOf: speicher.sicherung.ablage.datei),
                      let kopf = try? Tresor.kopfLesen(roh) else {
                    // Hat der Wicklungsbericht davor es schon gemeldet, ist dies die Folge (Z-AW1bN-06, Z-AW1bM-04).
                    zeilen.append("  Ablage nicht versiegelt lesbar" + (kopfBefund ? " (Folge des Befunds oben)" : " ✗"))
                    return
                }
                zeilen.append("  Passphrase und Wiederherstellungsschlüssel in der Ablage: "
                              + (kopf.wicklung(Wicklung.passphrase) != nil && kopf.wicklung(Wicklung.wiederherstellung) != nil
                                 ? "ja ✓" : "nein ✗"))
                // Beide Geheimnisse der Datei öffnen die Ablage — gleich, womit übernommen wurde (Z-AW1b-06).
                let oeffnet: Bool = await Task.detached {
                    (try? Tresor.oeffnen(kopf: kopf, passphrase: passphrase)) != nil
                }.value
                zeilen.append("  die Passphrase der Datei öffnet die Ablage: " + (oeffnet ? "ja ✓" : "nein ✗"))
                if !schluessel.isEmpty {
                    let oeffnetBlatt: Bool = await Task.detached {
                        (try? Tresor.oeffnen(kopf: kopf, wiederherstellung: schluessel)) != nil
                    }.value
                    zeilen.append("  ihr Wiederherstellungsschlüssel öffnet die Ablage: " + (oeffnetBlatt ? "ja ✓" : "nein ✗"))
                }
                // Erst, was das entprellte Sichern noch schreibt (Z-AW1b-05).
                await speicher.sicherung.entprelltJetzt()
                let ordner = speicher.sicherung.ablage.ordner
                let dateien = (FileManager.default.enumerator(at: ordner, includingPropertiesForKeys: nil)?
                    .allObjects as? [URL]) ?? []
                let funde = dateien.filter { url in
                    guard let d = try? Data(contentsOf: url) else { return false }
                    return d.range(of: Data(titel.utf8)) != nil
                }
                zeilen.append("  der Titel im Klartext in der Ablage: "
                              + (funde.isEmpty ? "nirgends ✓" : funde.map(\.lastPathComponent).joined(separator: ", ") + " ✗"))
            }
            @MainActor func abbild(_ name: String) async {
                // Das Blatt wächst um den Fehlerabschnitt; `ablegen` wartet, früher ist das Bild weiß.
                await ablegen(blatt, name)
            }
            @MainActor func bestand(_ schritt: String) {
                zeilen.append("  \(schritt):")
                let liste = felder()
                for feld in liste { zeilen.append("    " + feldzeile(feld)) }
                if liste.isEmpty { zeilen.append("    kein beschreibbares Feld ✗") }
                zeilen.append("    Knöpfe des Blatts: SwiftUI, für den eigenen Prozess unsichtbar — "
                              + knopfgeometrie() + "; Freigabe am Verhalten gemessen (E143)")
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
            _ = await leerAbschicken()
            await abbild("start")

            switch weg {
            case "wiederherstellung":
                await umschalten()
                bestand("nach dem Umschalten")
                await abbild("wiederherstellung")
                if let feld = felder().first(where: { !($0 is NSSecureTextField) }) {
                    await tippen(feld, schluessel.lowercased().replacingOccurrences(of: "-", with: " "))
                    zeilen.append("  Schlüssel getippt (klein, mit Leerzeichen)")
                    _ = await abschicken("Wiederherstellungsschlüssel")
                } else {
                    ursache = true
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
                    zeilen.append("  Passphrase trotzdem getippt")
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
                    ursache = true
                    zeilen.append("  kein Passphrase-Feld ✗")
                    break
                }
                await tippen(feld, "falsch")
                zeilen.append("  „falsch“ getippt")
                _ = await abschicken("falsche Passphrase")
                await abbild("fehler")
                await tippen(feld, passphrase)
                zeilen.append("  richtige Passphrase getippt"
                              + (speicher.entsperrungFehler == nil ? " · Fehlertext weg ✓"
                                                                   : " · Fehlertext steht noch"))
                _ = await abschicken("richtige Passphrase")
            }
            if weg == "uebernahme" {
                // Ohne Übernahme liegt keine Ablage — kein zweites ✗ für dieselbe Ursache (Z-AW1b-02).
                if speicher.verschluesselungsstand == .an { await wicklungsbericht() }
                await uebernahmeBericht()
                // Auf einem frischen Mac öffnet die Kette nach der Übernahme die Ersteinrichtung bei Frage 2; im
                // Prüfstand ist sie nie fällig — darum hier von Hand (E355, E720).
                if umgebung["ENTSPERRPROBE_FRAGE2"] == "1", speicher.verschluesselungsstand == .an {
                    speicher.ersteinrichtungOeffnen()
                    if let frage2 = await steht(.ersteinrichtung) {
                        // Erwartet nach den Schaltern (Z-AW1bM-02): Stand Frage 1 oder lag eine Vorbereitung vor, ist die
                        // Sicherungskopie „Frage 2 von 4“, sonst „Frage 1 von 3“ (E355); der Hinweis genau mit Vorbereitung.
                        let mitVorbereitung = umgebung["ENTSPERRPROBE_VORBEREITEN"] == "1"
                        let soll = umgebung["ENTSPERRPROBE_FRAGE1"] == "1" || mitVorbereitung ? 4 : 3
                        let fragen = Planungsspeicher.ersteinrichtungFragen(schritt: speicher.ersteinrichtungsschritt,
                                                                            frage: speicher.verschluesselungsfrage)
                        let schritt = speicher.ersteinrichtungsschritt == .sicherung
                        zeilen.append("  danach die Sicherungskopie als Frage \(fragen - 2) von \(fragen): "
                                      + (schritt && fragen == soll ? "✓" : "✗ — erwartet von \(soll)"))
                        let hinweis = speicher.verschluesselungsfrage == .ersetzt
                        zeilen.append("  Hinweis auf die verworfene Vorbereitung: " + (hinweis ? "ja" : "nein")
                                      + (hinweis == mitVorbereitung ? " ✓" : " ✗"))
                        await ablegen(frage2, "frage2")
                    } else {
                        zeilen.append("  Frage 2 kam nicht ✗")
                    }
                }
            } else {
                await wicklungsbericht()
            }
            zeilen.append("  Ende: Stand \(speicher.verschluesselungsstand), Planung "
                          + (speicher.planung.map { "„\($0.titel)“" } ?? "fehlt"))
            print(zeilen.joined(separator: "\n"))
            await Pruefstaende.abschliessenUndBeenden(speicher)
        }
    }
}
