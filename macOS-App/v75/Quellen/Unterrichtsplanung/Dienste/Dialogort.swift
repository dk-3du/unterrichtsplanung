// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Wo ein Druck- oder Dateidialog aufgeht (E114–E116, v61).
///
/// **Der Befund.** Der Druckdialog des Sitzplan-Editors ging als freies
/// Fenster über dem Blatt auf — gemessen: Fensterebene 8, Rahmen 780 × 941
/// über einem Blatt von 1000 × 720, 32–38 ms auf dem Schirm, bevor er
/// gezeichnet war; sein durchscheinender Rand lag auf zwei verschieden hellen
/// Untergründen und flackerte. Dasselbe galt für jeden Sichern- und
/// Öffnen-Dialog aus einem Blatt.
///
/// **Die Regel.** Eine, nicht eine Liste von Aufrufstellen: Ist das
/// Schlüsselfenster ein Blatt, wird der Dialog ein **Bogen an diesem Blatt**;
/// ist es das Hauptfenster, bleibt der Dialog ein freies Fenster, wie er
/// immer war. Dieselben Funktionen dienen beiden Seiten — die Kursdatei wird
/// aus dem Klassen-Blatt und aus der Kurszelle gewählt, ⌘P trifft den
/// Sitzplan-Editor über die Menüleiste —, darum entscheidet der Ort zur
/// Laufzeit, nicht der Aufrufer.
///
/// **Das Ziel ist das oberste Blatt der Kette.** Wenn der Dialog aufgeht, kann
/// eine Rückfrage — selbst ein Bogen — noch auf dem Blatt liegen (vor dem
/// PDF-Sichern einer versiegelten Planung etwa). Von `keyWindow` aus wird über
/// `sheetParent` aufgestiegen, bis der Elternteil selbst keinen mehr hat: Das
/// ist das Blatt, an dem der Nutzer arbeitet, und der Elternteil ohne
/// Elternteil ist das Hauptfenster.
///
/// **Rückrufe, nie anwendungsmodal am Bogen (E115).** Die Form der
/// abgewickelten 1.6.1 — `beginSheetModal` und dazu `NSApp.runModal(for:)`,
/// damit die Aufrufstellen synchron bleiben — ließ den Sichern-Dialog zweimal
/// am Bildschirm stehen. Hier bekommt jeder Dialog einen Abschluss: am Blatt
/// über `beginSheetModal(for:completionHandler:)`, ohne Blatt über
/// `runModal()` mit sofortigem Abschluss — das Hauptfenster verhält sich
/// damit Byte für Byte wie bisher.
@MainActor
enum Dialogort {

    enum Weg: Equatable {
        /// Als Bogen an diesem Blatt.
        case bogen(NSWindow)
        /// Ein freies Fenster — aus dem Hauptfenster, wie bisher.
        case frei
    }

    /// Der Weg für ein Schlüsselfenster. `elternVon` ist im Betrieb
    /// `sheetParent`; die Prüfungen stellen die Kette selbst — AppKit hängt
    /// im Prüfziel keine Bögen an.
    static func weg(fuer schluessel: NSWindow?,
                    elternVon: (NSWindow) -> NSWindow? = { $0.sheetParent }) -> Weg {
        guard var blatt = schluessel, var eltern = elternVon(blatt) else { return .frei }
        while let darueber = elternVon(eltern) {
            blatt = eltern
            eltern = darueber
        }
        return .bogen(blatt)
    }

    /// Der Weg, den ein Dialog jetzt nähme. Ohne Anwendung (im Prüfziel gibt
    /// es kein `NSApp`) ist er frei — `NSApp` ist implizit entpackt und wäre
    /// dort ein Absturz.
    static var aktuell: Weg { weg(fuer: (NSApp as NSApplication?)?.keyWindow) }

    /// Ein Sichern- oder Öffnen-Dialog (`NSOpenPanel` erbt von `NSSavePanel`):
    /// am Blatt als Bogen mit Abschluss, sonst frei — dann kommt der Abschluss
    /// sofort, noch aus diesem Aufruf heraus.
    static func zeigen(_ dialog: NSSavePanel,
                       _ abschluss: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        switch aktuell {
        case .bogen(let blatt):
            Task { @MainActor in
                await bogenFrei(blatt)
                dialog.beginSheetModal(for: blatt) { antwort in abschluss(antwort) }
            }
        case .frei:
            abschluss(dialog.runModal())
        }
    }

    /// Ein Fenster trägt genau einen Bogen. Geht der Dialog aus der Antwort auf
    /// eine Rückfrage auf (PDF-Sichern einer versiegelten Planung, der Zugriff
    /// auf Material), hängt die Rückfrage in diesem Augenblick noch am Blatt —
    /// ein zweiter `beginSheetModal` verhallte dann (am gebauten Paket gemessen:
    /// kein Bogen, nur das verwaiste Zusatzfenster des Sichern-Dialogs). Also
    /// erst warten, bis das Blatt frei ist; länger als zwei Sekunden nie.
    private static func bogenFrei(_ blatt: NSWindow) async {
        var versuche = 0
        while blatt.attachedSheet != nil, versuche < 40 {
            try? await Task.sleep(for: .milliseconds(50))
            versuche += 1
        }
    }

    // Ein Öffnen-Dialog kommt mit seiner gemerkten Breite (924 Punkt) und ist
    // damit breiter als das Klassen-Blatt (800) und das Vorhaben-Blatt (720);
    // AppKit hängt ihn trotzdem an und lässt ihn beidseitig zentriert
    // überstehen. Kleiner setzen lässt er sich nicht — vor wie nach dem
    // Anhängen bleibt seine Mindestbreite (am gebauten Paket gemessen,
    // --dialogtest). Das ist das Verhalten des Systems für jeden Bogen, der
    // breiter ist als sein Fenster, und kein freies Fenster: Er hängt, er
    // flackert nicht. Benannt, nicht bekämpft.

    /// Ein Druckvorgang: am Blatt dokumentmodal als Bogen (AppKit-eigen), sonst
    /// wie bisher `run()`. Ein Abschluss wird hier nicht gebraucht — der Druck
    /// selbst ist die Handlung, und nichts wartet auf ihn.
    static func drucken(_ vorgang: NSPrintOperation) {
        switch aktuell {
        case .bogen(let blatt):
            Task { @MainActor in
                await bogenFrei(blatt)
                vorgang.runModal(for: blatt, delegate: nil, didRun: nil, contextInfo: nil)
            }
        case .frei:
            vorgang.run()
        }
    }
}
