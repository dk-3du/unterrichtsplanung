// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@main
struct UnterrichtsplanungApp: App {
    @NSApplicationDelegateAdaptor(Anwendungsdelegat.self) private var delegat

    /// `--container`: den Container nennen und gehen — vor jedem Fenster, ohne
    /// die Ablage zu berühren. Für Skripte, die Prüfstände im Container säen.
    init() {
        if CommandLine.arguments.contains("--container") {
            print(Ablage.container?.path ?? "kein Sandbox")
            exit(0)
        }
    }

    var body: some Scene {
        // `Window` statt `WindowGroup`: ⌘N legt eine neue Planung an, kein Fenster.
        Window("Unterrichtsplanung", id: "planungsfenster") {
            Hauptansicht()
                .environment(delegat.speicher)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1480, height: 940)
        .commands { Befehle(speicher: delegat.speicher) }
    }
}

/// Nach dem Aufwachen des Macs aus dem Ruhezustand liest die App den Stand der
/// Web App einmal, 15 Sekunden danach (E216 d, v75). **Bewusst so** — kein
/// Takt, nicht beim Aufwachen des Bildschirms, keine Wiederholung: Jede
/// Übernahme, die etwas ändert, leert den Verlauf zum Widerrufen (E84, E217);
/// das Aufwachen trennt zwei Arbeitsphasen wie ein Neustart. Kommt die Datei
/// später, holt sie der Befehl „Stand der Web App abrufen“. Eine weitere
/// Meldung in den 15 Sekunden ersetzt die erste.
@MainActor
final class Aufwachabruf {
    static let verzoegerung: Duration = .seconds(15)

    private var beobachter: (any NSObjectProtocol)?
    private var ausstehend: Task<Void, Never>?

    /// Nur die Meldung des Macs (`didWakeNotification`), nicht die des
    /// Bildschirms (`screensDidWakeNotification`).
    func beobachten(_ speicher: Planungsspeicher) {
        guard beobachter == nil else { return }
        beobachter = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.aufgewacht(speicher) }
        }
    }

    private func aufgewacht(_ speicher: Planungsspeicher) {
        ausstehend?.cancel()
        ausstehend = Task { @MainActor in
            do { try await Task.sleep(for: Aufwachabruf.verzoegerung) } catch { return }  // E561: Zeitgeber (Aufwachabruf) — der Status 15 s nach dem Aufwachen
            speicher.statusNachAufwachen()
        }
    }
}

@MainActor
final class Anwendungsdelegat: NSObject, NSApplicationDelegate {
    /// Die einzige Stelle, die `Ablage.shared` kennt — der Speicher bekommt sie hereingereicht.
    let speicher = Planungsspeicher(ablage: Ablage.shared)

    private let aufwachabruf = Aufwachabruf()

    /// Das Beenden-Ereignis nimmt die App selbst entgegen: Der eingebaute Weg
    /// weist den Befehl ab, solange ein Blatt offen ist — noch bevor der Delegat
    /// gefragt wird. Betrifft Dock, AppleScript und das Abmelden.
    func applicationDidFinishLaunching(_ nachricht: Notification) {
        Schreibende.beobachten()
        // Vor dem Aktivieren: Sonst sähe die Ansage der Meldungen den ersten Fokuswechsel nicht (B108).
        Ansager.gemeinsam.beobachten()
        schreibstellenBeobachten()
        eingabenInDerLueckeSperren()
        // Hinter einem Dialog des Systems warten die Übernahme und vorgemerkte Meldungen;
        // beim Schließen holen sie nach (B64, Z-AS2-04).
        Dialogort.nachDemSchliessen = { [speicher] in
            speicher.statusNachholenWennFrei()
            speicher.vorgemerkteMeldungenZeigen()
        }
        // Ein Prüfstand je Lauf — der Verteiler liest die Argumente und prüft die Schranke.
        Pruefstaende.starten(speicher)
        // Im Betrieb und unter `--statustest`, in keinem anderen Prüfstand.
        if Pruefstaende.laufender == nil || Pruefstaende.laufender == .statustest {
            aufwachabruf.beobachten(speicher)
        }
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(beendenAngefordert(_:mitAntwort:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication))
    }

    /// In der Lücke nach einer Antwort nimmt die App keine Eingabe an: Tasten und Klicks in allen Fenstern
    /// prallen ab, mit Ton — ohne eine Fläche oder ein Blatt umzubauen (E437, Z-AU4c-01/-02). Menübefehle
    /// mit der Maus sperrt `Befehle`.
    private func eingabenInDerLueckeSperren() {
        lueckenmonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [speicher] ereignis in
            let wiederholt = ereignis.type == .keyDown && ereignis.isARepeat
            return MainActor.assumeIsolated {
                // Eine gehaltene Taste wiederholt sich: still schlucken, ein Ton genügt (Z-AU4c-16).
                guard !wiederholt else { return speicher.handlungAussteht }
                return speicher.eingabeSperrt()
            } ? nil : ereignis
        }
        // Ein geschluckter Klick nimmt dem Feld auch die Schreibmarke nicht (Z-AU4c-17).
        Schreibende.gesperrt = { [speicher] in speicher.handlungAussteht }
    }

    private var lueckenmonitor: Any?

    /// AppKit meldet das für jedes Feld mit Feldeditor — auch für den
    /// Fenstertitel, den SwiftUI selbst nicht meldet. Solange die Schreibmarke
    /// dort steht, dürfen ⌫, ⌘C und ⌘V nicht ins Raster greifen.
    private func schreibstellenBeobachten() {
        for (name, schreibt) in [(NSText.didBeginEditingNotification, true),
                                 (NSText.didEndEditingNotification, false)] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [speicher] _ in
                MainActor.assumeIsolated { speicher.textfeldAktiv = schreibt }
            }
        }
    }

    /// `beenden()` stellt bei gestörter Sicherung eine Rückfrage und geht dann
    /// nicht sofort. Wer per AppleScript beendet, bekommt das als Fehler
    /// gemeldet, statt ein Gelingen, das keines war.
    ///
    /// Ohne Blatt endet die App im Griff, und das Skript liest das als Gelingen. Bei
    /// offenem Blatt beendet `beenden()` erst nach dem Schließen der Blätter: Dann wartet
    /// die Antwort, bis das Beenden gelingt oder abgelehnt ist (B90, E416).
    @objc private func beendenAngefordert(_ ereignis: NSAppleEventDescriptor,
                                          mitAntwort antwort: NSAppleEventDescriptor) {
        let wartete = speicher.alertSteht
        speicher.beenden()
        guard !speicher.beendetGleich else {
            // Unterwegs: zurückgehalten bis zum Ende oder zur späten Ablehnung — die Aufgabe des Speichers
            // läuft erst nach diesem Griff. Gelingt das Zurückhalten nicht, bekommt das Skript gleich Gelingen.
            if let griff = NSAppleEventManager.shared().suspendCurrentAppleEvent() {
                wartendeBeenden.append(griff)
                speicher.beendenAbgelehnt = { [weak self] grund in self?.beendenBeantworten(grund: grund) }
            }
            return
        }
        // Der Grund folgt der Frage, die steht oder unter einem Bogen wartet (Z14b-03, E316, Z-AU3-12), der
        // Löschung im Archiv, an der es anhielt (Z-AS2a-11), oder dem Blatt, an dem AppKit ablehnte (E428).
        let grund = speicher.beendengrundJetzt(wartete: wartete)
        Self.fehlerEintragen(grund, in: antwort)
    }

    /// Skripte, die auf ein Beenden unterwegs warten — beantwortet beim Ende oder mit dem Grund der Ablehnung (B90, E416).
    private var wartendeBeenden: [NSAppleEventManager.SuspensionID] = []

    /// Beantwortet die wartenden Skripte: mit Grund als Fehler, ohne Grund als Gelingen.
    private func beendenBeantworten(grund: String?) {
        let verwaltung = NSAppleEventManager.shared()
        for griff in wartendeBeenden {
            if let grund { Self.fehlerEintragen(grund, in: verwaltung.replyAppleEvent(forSuspensionID: griff)) }
            verwaltung.resume(withSuspensionID: griff)
        }
        wartendeBeenden = []
    }

    private static func fehlerEintragen(_ grund: String, in antwort: NSAppleEventDescriptor) {
        antwort.setDescriptor(NSAppleEventDescriptor(int32: Int32(userCanceledErr)), forKeyword: keyErrorNumber)
        antwort.setDescriptor(NSAppleEventDescriptor(string: grund), forKeyword: keyErrorString)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ anwendung: NSApplication) -> Bool {
        speicher.beendenBeiLetztemFenster
    }

    /// Das Fenster kommt über das Dock-Symbol zurück — sonst bliebe die App
    /// nach `beendenBeiLetztemFenster == false` unerreichbar.
    func applicationShouldHandleReopen(_ anwendung: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool { true }

    /// Eine Planungsdatei per Doppelklick oder „Öffnen mit“.
    ///
    /// Erst `starten()`, dann öffnen: Der sonst beim Erscheinen der Ansicht
    /// nachgeholte Start überschriebe die Datei mit der Autosicherung.
    func application(_ anwendung: NSApplication, open urls: [URL]) {
        guard let erste = urls.first(where: \.isFileURL) else { return }
        speicher.starten()
        speicher.importieren(von: erste)
    }

    /// Erst sichern, dann gehen — gleichlaufend, damit das Beenden nie hängt.
    /// Die zusätzliche Sicherungskopie nur hier, nicht beim Wegschalten.
    ///
    /// Ließ sich nicht sichern, wird zurückgefragt statt still zu verlieren;
    /// die Rückfrage beendet die App selbst, sobald sie beantwortet ist.
    func applicationShouldTerminate(_ anwendung: NSApplication) -> NSApplication.TerminateReply {
        speicher.beendenErlauben() ? .terminateNow : .terminateCancel
    }

    func applicationDidResignActive(_ nachricht: Notification) {
        speicher.jetztSichern()
    }

    /// Ein Prüfstand beweist sein Ende (N67-01): die letzte Zeile „ENDE <Name>“.
    /// Wartende Skripte erfahren das Gelingen, ehe die App geht (B90, E416).
    func applicationWillTerminate(_ nachricht: Notification) {
        Pruefstaende.beendet()
        beendenBeantworten(grund: nil)
    }
}
