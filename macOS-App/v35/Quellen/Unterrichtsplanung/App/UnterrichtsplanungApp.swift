// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@main
struct UnterrichtsplanungApp: App {
    @NSApplicationDelegateAdaptor(Anwendungsdelegat.self) private var delegat

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

@MainActor
final class Anwendungsdelegat: NSObject, NSApplicationDelegate {
    let speicher = Planungsspeicher()

    /// Das Beenden-Ereignis nimmt die App selbst entgegen: Der eingebaute Weg
    /// weist den Befehl ab, solange ein Blatt offen ist — noch bevor der Delegat
    /// gefragt wird. Betrifft Dock, AppleScript und das Abmelden.
    func applicationDidFinishLaunching(_ nachricht: Notification) {
        Schreibende.beobachten()
        schreibstellenBeobachten()
        Selbstabbild.ablegenUndBeenden(speicher)
        Selbstabbild.rolltestUndBeenden()
        Selbstabbild.klicktestUndBeenden(speicher)
        Selbstabbild.auswahltestUndBeenden(speicher)
        Selbstabbild.mischtestUndBeenden(speicher)
        Selbstabbild.ziehtestUndBeenden(speicher)
        Selbstabbild.titeltestUndBeenden(speicher)
        Selbstabbild.menuetestUndBeenden(speicher)
        Selbstabbild.entsperrtestUndBeenden(speicher)
        Selbstabbild.tourtestUndBeenden(speicher)
        Selbstabbild.updatetestUndBeenden()
        Messreihe.laufenUndBeenden(speicher)
        Messreihe.masseUndBeenden()
        Dauerprobe.laufenUndBeenden(speicher)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(beendenAngefordert(_:mitAntwort:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication))
    }

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
    @objc private func beendenAngefordert(_ ereignis: NSAppleEventDescriptor,
                                          mitAntwort antwort: NSAppleEventDescriptor) {
        speicher.beenden()
        guard !speicher.beendetGleich else { return }
        antwort.setDescriptor(NSAppleEventDescriptor(int32: Int32(userCanceledErr)),
                              forKeyword: keyErrorNumber)
        antwort.setDescriptor(NSAppleEventDescriptor(
            string: "Die Planung ließ sich nicht sichern; das Beenden wartet auf eine Antwort."),
                              forKeyword: keyErrorString)
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
}
