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
/// Zugriff auf Material etwa, „Auswählen …“). Von `keyWindow` aus wird über
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

    /// Wie viele Dialoge gerade frei am Hauptfenster stehen (`runModal()`,
    /// `run()`). Hinter ihnen läuft die Hauptschleife im Modalmodus weiter —
    /// und mit ihr jede Aufgabe des Hauptakteurs, auch die Übernahme nach dem
    /// Aufwachen (am Lauf gemessen, v76). Die Übernahme wartet darum auf null
    /// (B64, E227); ein Bogen am Blatt braucht das nicht, dort ist das Blatt offen.
    private(set) static var freieDialoge = 0

    /// Nach dem Schließen des letzten freien Dialogs: holt nach, was gewartet
    /// hat — jede Bedingung braucht ihren Anstoß (B62). Gesetzt vom
    /// Anwendungsdelegaten.
    static var nachDemSchliessen: (@MainActor () -> Void)?

    /// Ein freier Dialog, gezählt, solange er steht.
    static func frei<T>(_ zeigen: () -> T) -> T {
        freieDialoge += 1
        defer {
            freieDialoge -= 1
            if freieDialoge == 0 { nachDemSchliessen?() }
        }
        return zeigen()
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
                // Noch belegt: Der Bogen verhallte und ließe sein Zusatzfenster verwaist stehen (B107,
                // E459) — dann nichts, mit Ton, und der Abschluss sagt „abgebrochen“. Das Zusatzfenster
                // steht schon, seit das Zusatzfeld gesetzt ist; erst ein leeres Zusatzfeld nimmt es fort
                // (gemessen: `close`, `cancel` und `orderOut` am Dialog lassen es stehen).
                guard blatt.attachedSheet == nil else {
                    dialog.accessoryView = nil
                    ton()
                    abschluss(.cancel)
                    return
                }
                breiteAngleichen(dialog, an: blatt)
                dialog.beginSheetModal(for: blatt) { antwort in abschluss(antwort) }
            }
        case .frei:
            abschluss(frei { dialog.runModal() })
        }
    }

    /// Ein Fenster trägt genau einen Bogen. Geht der Dialog aus der Antwort auf
    /// eine Rückfrage auf (der Zugriff auf Material, „Auswählen …“), hängt die
    /// Rückfrage in diesem Augenblick noch am Blatt — ein zweiter
    /// `beginSheetModal` verhallte dann (am gebauten Paket gemessen: kein Bogen,
    /// nur das verwaiste Zusatzfenster des Sichern-Dialogs). Also erst warten,
    /// bis das Blatt frei ist; länger als zwei Sekunden nie — ist es dann noch
    /// belegt, hängen `zeigen` und `drucken` nichts an (B107).
    private static func bogenFrei(_ blatt: NSWindow) async {
        var versuche = 0
        while blatt.attachedSheet != nil, versuche < 40 {
            try? await Task.sleep(for: .milliseconds(50))  // E561: Zeitgeber (AppKit) — warten, bis das Blatt frei ist (B107)
            versuche += 1
        }
    }

    // Ein Öffnen- oder Sichern-Dialog kommt mit der Breite, die zuletzt von Hand
    // gezogen wurde (gemerkt unter `NSNavPanelExpandedSizeForOpenMode` bzw.
    // `…ForSaveMode`, Vorgabe 924 Punkt) — beim Nutzer um 1370, weit über jedem
    // Blatt (E627). `zeigen` setzt ihn darum vor dem Anhängen auf die Breite des
    // Blatts (`bogenbreite`), nie unter seine Mindestbreite: Die ist 924 (am
    // gebauten Paket gemessen, --dialogtest, E627). Schmalere Blätter — etwa das
    // Klassen-Blatt (800) — überragt er darum weiter
    // beidseitig zentriert: das Verhalten des Systems für jeden Bogen, der
    // breiter ist als sein Fenster, und kein freies Fenster. Er hängt, er
    // flackert nicht. Benannt, nicht bekämpft.

    /// Wie breit ein Öffnen- oder Sichern-Dialog als Bogen an einem Blatt sein soll (E627): nicht breiter als das
    /// Blatt — er kommt mit der Breite, die zuletzt von Hand gezogen wurde, und stünde sonst weit über —, nie
    /// schmaler als seine Mindestbreite. Rein gerechnet, damit prüfbar.
    nonisolated static func bogenbreite(dialog: CGFloat, mindest: CGFloat, blatt: CGFloat) -> CGFloat {
        max(mindest, min(dialog, blatt))
    }

    /// Vor dem Anhängen auf die Bogenbreite (E627); die Höhe bleibt, der Rahmen bleibt mittig.
    private static func breiteAngleichen(_ dialog: NSSavePanel, an blatt: NSWindow) {
        let breite = bogenbreite(dialog: dialog.frame.width, mindest: dialog.minSize.width, blatt: blatt.frame.width)
        guard breite < dialog.frame.width - 0.5 else { return }
        var rahmen = dialog.frame
        rahmen.origin.x += (rahmen.width - breite) / 2
        rahmen.size.width = breite
        dialog.setFrame(rahmen, display: false)
    }

    /// Wie oft das Netz tönte — auch im Prüflauf gezählt, wo der Ton stumm bleibt.
    private(set) static var toene = 0

    /// Der Ton des Netzes — wie `Planungsspeicher.systemton`, nie im Prüflauf.
    private static func ton() {
        toene += 1
        guard !Ablage.istPruefstand else { return }
        NSSound.beep()
    }

    /// Ein Druckvorgang: am Blatt dokumentmodal als Bogen (AppKit-eigen), sonst
    /// wie bisher `run()`. Ein Abschluss wird hier nicht gebraucht — der Druck
    /// selbst ist die Handlung, und nichts wartet auf ihn.
    static func drucken(_ vorgang: NSPrintOperation) {
        switch aktuell {
        case .bogen(let blatt):
            Task { @MainActor in
                await bogenFrei(blatt)
                guard blatt.attachedSheet == nil else {
                    ton()
                    return
                }
                vorgang.runModal(for: blatt, delegate: nil, didRun: nil, contextInfo: nil)
            }
        case .frei:
            _ = frei { vorgang.run() }
        }
    }
}
