// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Die Menüleiste.
///
/// Gesperrt wird beim **Griff**, nicht über `.disabled(…)`: `Befehle` entsteht
/// einmal im Rumpf der `App` und wird nie erneut ausgewertet — ein `.disabled`
/// friert den Stand vom Programmstart ein, als noch keine Planung geladen war.
/// Eine Ausnahme: `StatusAbrufBefehl` — eine eigene Ansicht im Menü, die SwiftUI
/// beim Öffnen des Menüs nachführt (E223, am Paket gemessen).
struct Befehle: Commands {
    let speicher: Planungsspeicher

    private var gesperrt: Bool { speicher.dialogOffen }
    /// In der Lücke nach einer Antwort prallt auch ein Befehl aus dem Menü ab, mit Ton; Tastenkürzel fängt
    /// schon der Ereignis-Monitor (Z-AU4c-05).
    private func wenn(_ erlaubt: Bool, _ handlung: () -> Void) {
        if erlaubt, !speicher.eingabeSperrt() { handlung() }
    }
    private var ohnePlanung: Bool { speicher.planung == nil || speicher.dialogOffen }

    /// Zeigt die Autosicherung im Finder — ersatzweise ihren Ordner, solange
    /// noch nichts geschrieben wurde.
    ///
    /// Statisch, damit der Stand-Dialog denselben Weg nimmt.
    static func autosicherungZeigen(_ speicher: Planungsspeicher) {
        let ablage = speicher.sicherung.ablage
        if case .erledigt = Systemzugriff.imFinderZeigen(ablage.datei.path, zugriff: speicher.zugriff) { return }
        if case .erledigt = Systemzugriff.imFinderZeigen(ablage.ordner.path, zugriff: speicher.zugriff) {
            speicher.melden("Noch keine Autosicherung — der Ordner ist geöffnet.")
            return
        }
        speicher.melden("Die Autosicherung wird beim ersten Speichern angelegt.",
                        .warnung)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Über Unterrichtsplanung") { Ueber.zeigen() }
            // Von Hand: ohne Einwilligung und ohne Wochenfrist, mit Rückmeldung.
            Button(Updates.menuebefehl) { wenn(!gesperrt) { speicher.updatesPruefen(erzwungen: true) } }
        }

        // Der eingebaute Befehl käme bei offenem Dialog nicht durch; nie sperren.
        CommandGroup(replacing: .appTermination) {
            Button("Unterrichtsplanung beenden") { speicher.beenden() }
                .keyboardShortcut("q")
        }

        CommandGroup(replacing: .newItem) {
            Button("Neue Planung …") { wenn(!gesperrt) { speicher.neuePlanungOeffnen() } }
                .keyboardShortcut("n")
            Button("Planung öffnen …") { wenn(!gesperrt) { speicher.importDialog() } }
                .keyboardShortcut("o")
            // Haken und Kommentare aus der Web App, jetzt statt erst beim nächsten
            // Aufwachen oder Start (E216 d); ausgegraut ohne Zielordner (E223).
            StatusAbrufBefehl(speicher: speicher)
            Divider()
            Button("Als JSON sichern …") { wenn(!ohnePlanung) { speicher.exportieren() } }
                .keyboardShortcut("s")
            // Der bewusste Weg zum Klartext — bei ausgeschalteter Verschlüsselung
            // dasselbe wie ⌘S, sonst mit Rückfrage.
            Button("Als Klartext-JSON sichern …") {
                wenn(!ohnePlanung) { speicher.exportierenKlartext() }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            LernendenAblageBefehle(speicher: speicher)
            Divider()
            Button("Ordner der Autosicherung zeigen") {
                Befehle.autosicherungZeigen(speicher)
            }
            // Nur sichtbar, wenn der Wiederanlauf keinen stimmigen Stand
            // feststellen konnte: der eine Weg aus der Sperre (E67).
            if speicher.blockadeOffen {
                Divider()
                Button("Unterbrochenen Übergang beiseitelegen …") {
                    wenn(true) { speicher.blockadeRaeumenFragen() }
                }
            }
        }

        CommandGroup(replacing: .printItem) {
            // Im Sitzplan-Editor gilt der Befehl dem Sitzplan, der gerade auf
            // der Fläche steht — die Menüleiste sieht das Blatt nicht.
            // Keine `.disabled`-Bedingung an diesen Befehlen: Hängt sie am Zustand des
            // Blatts, baut SwiftUI das Menü beim Öffnen neu, und ⌘⏎ im Blatt kommt
            // nicht mehr an (N04, v49). In der Listenphase meldet der Speicher stattdessen.
            Button("Drucken …") {
                // In der Lücke nach einer Antwort prallt auch der Menübefehl ab (Z-AU4c-14).
                guard !speicher.eingabeSperrt() else { return }
                if speicher.offenerDialog == .sitzplan { speicher.sitzplanDrucken(); return }
                guard !ohnePlanung, let planung = speicher.planung else { return }
                Drucken.drucken(planung, speicher: speicher)
            }
            .keyboardShortcut("p")

            Button("Als PDF sichern …") {
                guard !speicher.eingabeSperrt() else { return }
                if speicher.offenerDialog == .sitzplan { speicher.sitzplanAlsPDFSichern(); return }
                guard !ohnePlanung, let planung = speicher.planung else { return }
                Drucken.alsPDFSichern(planung, speicher: speicher)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        // Widerrufen und Wiederholen (E82, E87). Die Gruppe von SwiftUI zeigt in
        // die Verantwortungskette und blieb blass, weil dort nie jemand eine
        // Rücknahme anmeldete; sie wird ersetzt, wie die Zwischenablage auch.
        //
        // **Ohne `.disabled` und mit festem Titel** — aus demselben Grund wie
        // oben: Dieser Rumpf läuft einmal. Ein `.disabled` fröre den Stand vom
        // Programmstart ein (am gebauten Paket gemessen: Der Eintrag blieb
        // blass, und ⌘Z kam nirgends an, weil ein abgeblendeter Eintrag sein
        // Kürzel schluckt). Entschieden wird darum beim Griff, und den Namen
        // des Schrittes trägt `Menuetitel` nach.
        CommandGroup(replacing: .undoRedo) {
            // `wenn`: In der Lücke nach einer Antwort prallt auch der Weg zum Feldeditor ab (H1-03).
            Button("Widerrufen") { wenn(true) { widerrufen() } }
                .keyboardShortcut("z")
            Button("Wiederholen") { wenn(true) { wiederholen() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        // `replacing:` statt `after:`: doppelt vergebene Kürzel streicht SwiftUI ersatzlos.
        CommandGroup(replacing: .pasteboard) {
            Button("Ausschneiden") { wenn(true) { verschieben() } }
                .keyboardShortcut("x")
            Button("Kopieren") { wenn(true) { kopieren() } }
                .keyboardShortcut("c")
            Button("Einsetzen") { wenn(true) { einfuegen() } }
                .keyboardShortcut("v")
            Button("Löschen") { wenn(true) { loeschen() } }
                .keyboardShortcut(.delete, modifiers: [])
            Divider()
            Button("Alles auswählen") { wenn(true) { allesWaehlen() } }
                .keyboardShortcut("a")
        }

        CommandGroup(after: .textEditing) {
            Button("Vorhaben durchsuchen") { wenn(!ohnePlanung) { Suchfeldbefehl.fokussieren() } }
                .keyboardShortcut("f")
        }

        CommandMenu("Planung") {
            Button("Lernende, Klassen/Kurse und Fächer …") { wenn(!ohnePlanung) { speicher.offenerDialog = .klassen } }
                .keyboardShortcut("k")
            LernendenBefehl(speicher: speicher)
            Button("Ferien und unterrichtsfreie Zeiten …") { wenn(!ohnePlanung) { speicher.offenerDialog = .ferien } }
                .keyboardShortcut("e")
            Button("Prüfungen …") { wenn(!ohnePlanung) { speicher.offenerDialog = .pruefungen } }
                .keyboardShortcut("r")
            Button("Einstellungen …") { wenn(!ohnePlanung) { speicher.offenerDialog = .einstellungen } }
                .keyboardShortcut(",")
            Button("Verschlüsselung …") {
                wenn(!ohnePlanung) { speicher.dialogOeffnen(.verschluesselung) }
            }
            Divider()
            Button("Neues Vorhaben …") {
                wenn(!ohnePlanung) {
                    speicher.vorhabenOeffnen(woche: speicher.planung?.laufendeWoche ?? 0)
                }
            }
            .keyboardShortcut("t")
            Button("Zur laufenden Woche") { wenn(!ohnePlanung) { speicher.zurLaufendenWoche() } }
                .keyboardShortcut("j")
            Button("Heute anstehende Vorhaben …") {
                wenn(!ohnePlanung) { speicher.offenerDialog = .heute }
            }
            .keyboardShortcut("d")

            Divider()

            Button("In der Zelle nach oben") {
                wenn(!gesperrt) { speicher.auswahlReihen(nachOben: true) }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("In der Zelle nach unten") {
                wenn(!gesperrt) { speicher.auswahlReihen(nachOben: false) }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }

        CommandGroup(after: .toolbar) {
            Picker("Darstellung", selection: Binding(
                get: { speicher.erscheinung },
                set: { speicher.erscheinung = $0 })) {
                    ForEach(Planungsspeicher.Erscheinung.allCases) { fall in
                        Text(fall.beschriftung).tag(fall)
                    }
                }
            Divider()
            Button("Spalten breiter") {
                wenn(!ohnePlanung) { speicher.spaltenbreite += Kennwerte.spalteRaster }
            }
            .keyboardShortcut("+")
            Button("Spalten schmaler") {
                wenn(!ohnePlanung) { speicher.spaltenbreite -= Kennwerte.spalteRaster }
            }
            .keyboardShortcut("-")
        }

        CommandGroup(replacing: .help) {
            Button("Kurzanleitung") { wenn(!gesperrt) { speicher.offenerDialog = .hilfe } }
            Button("Tour durch die Oberfläche") { wenn(!gesperrt) { speicher.tourStarten() } }
        }
    }
}

// ── Bearbeiten: Raster oder Textfeld ──────────────────────────────────────
extension Befehle {

    private var imText: Bool { speicher.schreibstelleAktiv }

    /// `to: nil` heißt: dem ersten, der sich zuständig fühlt — bei stehender
    /// Schreibmarke also dem Feldeditor.
    private func weiterreichen(_ griff: Selector) {
        NSApp.sendAction(griff, to: nil, from: nil)
    }

    func kopieren() {
        if imText || speicher.auswahl.isEmpty {
            weiterreichen(#selector(NSText.copy(_:)))
        } else {
            speicher.kopieren()
        }
    }

    /// ⌘Z gehört dem Feldeditor, wenn einer die Schreibmarke hat (E87) — sonst
    /// dem Schauplatz. `schreibstelleAktiv` taugt dafür nicht: Es zählt jedes
    /// offene Blatt als Text, und gerade dort entstehen die feinen Schritte.
    func widerrufen() {
        if let feld = Schreibmarke.feldeditor {
            if feld.undoManager?.canUndo == true { feld.undoManager?.undo() }
            return
        }
        speicher.widerrufen()
    }

    func wiederholen() {
        if let feld = Schreibmarke.feldeditor {
            if feld.undoManager?.canRedo == true { feld.undoManager?.redo() }
            return
        }
        speicher.wiederholen()
    }

    /// Merkt zum Verschieben vor — versetzt wird erst beim Einfügen.
    func verschieben() {
        if imText || speicher.auswahl.isEmpty {
            weiterreichen(#selector(NSText.cut(_:)))
        } else {
            speicher.verschiebenVormerken()
        }
    }

    func einfuegen() {
        if imText || !speicher.kannEinfuegen {
            weiterreichen(#selector(NSText.paste(_:)))
        } else {
            speicher.einfuegen()
        }
    }

    func loeschen() {
        if imText || speicher.auswahl.isEmpty {
            weiterreichen(#selector(NSText.delete(_:)))
        } else {
            speicher.auswahlLoeschen()
        }
    }

    func allesWaehlen() {
        if imText || speicher.planung == nil {
            weiterreichen(#selector(NSText.selectAll(_:)))
        } else {
            speicher.allesAnwaehlen()
        }
    }
}

/// „Stand der Web App abrufen“ — ausgegraut, solange `statusAbrufAngeboten`
/// nicht gilt (E223, Wunsch des Nutzers). Die eine Ausnahme von der Regel oben
/// („gesperrt wird beim Griff“): eine eigene Ansicht, deren Rumpf SwiftUI neu
/// auswertet, wenn sich die Bedingung ändert — `Befehle` selbst läuft nur
/// einmal. Nachgeführt wird beim Öffnen des Menüs (`menuNeedsUpdate`), nicht
/// sofort; das sieht der Nutzer, und so misst es `--statustest`. Kein Kürzel,
/// das ein blasser Eintrag schlucken könnte, und keine Bedingung am Zustand
/// eines Blatts (N04). Gewählt, aber nicht erreichbar, bleibt der Zielordner
/// angeboten: Das weiß die App erst beim Lesen (B61).
struct StatusAbrufBefehl: View {
    let speicher: Planungsspeicher

    var body: some View {
        Button("Stand der Web App abrufen") {
            guard speicher.planung != nil, !speicher.dialogOffen, !speicher.eingabeSperrt() else { return }
            speicher.statusAbrufen()
        }
        .disabled(!speicher.statusAbrufAngeboten)
    }
}

/// „Lernende …“ (⌘L) — grau ohne Planung oder ohne offene Lernendenverwaltung
/// (E249). Eine eigene Ansicht wie `StatusAbrufBefehl`, damit der graue Stand
/// dem Zustand folgt. Gesperrt wird trotzdem beim Griff: Ein offenes Blatt ist
/// keine Bedingung des grauen Stands (N04). Das Kürzel darf der graue Eintrag
/// schlucken — ⌘L hat keinen anderen Empfänger.
struct LernendenBefehl: View {
    let speicher: Planungsspeicher

    var body: some View {
        Button("Lernende …") {
            guard speicher.planung != nil, !speicher.dialogOffen, !speicher.eingabeSperrt() else { return }
            speicher.lernendenBlattOeffnen()
        }
        .keyboardShortcut("l")
        .disabled(!speicher.lernendenBlattAngeboten)
    }

    /// Ein Kürzel trifft den Eintrag, wie er zuletzt nachgeführt wurde — ohne
    /// Öffnen des Menüs also im grauen Stand vom Start, und ⌘L verpuffte nach
    /// dem Entsperren (B72). Darum wird das Menü „Planung“ nachgeführt wie beim
    /// Öffnen, sobald sich die Bedingung ändert.
    static func nachfuehren() {
        guard let menue = NSApp.mainMenu?.items.first(where: { $0.title == "Planung" })?.submenu else { return }
        menue.delegate?.menuNeedsUpdate?(menue)
        menue.update()
    }
}

/// Export, CSV und Einlesen der Lernendenverwaltung (E257, E287) — eine eigene
/// Ansicht im Menü wie `StatusAbrufBefehl`, die SwiftUI beim Öffnen nachführt;
/// ohne Kürzel, darum ohne Nachführen von Hand (B72 betraf ein Kürzel).
struct LernendenAblageBefehle: View {
    let speicher: Planungsspeicher

    var body: some View {
        Button("Lernende exportieren …") {
            guard !speicher.dialogOffen, !speicher.eingabeSperrt() else { return }
            speicher.lernendenExportieren()
        }
        .disabled(!speicher.lernendenExportAngeboten)
        Button("Lernende als CSV sichern …") {
            guard !speicher.dialogOffen, !speicher.eingabeSperrt() else { return }
            speicher.lernendenAlsCSVSichern()
        }
        .disabled(!speicher.lernendenExportAngeboten)
        Button("Lernende einlesen …") {
            guard !speicher.dialogOffen, !speicher.eingabeSperrt() else { return }
            speicher.lernendenEinlesenWaehlen()
        }
        .disabled(!speicher.lernendenEinlesenAngeboten)
    }
}

/// „Widerrufen: Vorhaben entfernen“ — der Name des Schrittes im Menü.
///
/// Er kann nicht aus dem Rumpf von `Befehle` kommen: Der läuft einmal. Also
/// wird der Titel am `NSMenuItem` nachgeführt, sobald sich der Verlauf ändert.
/// Gefunden werden die beiden Einträge am Tastenkürzel, nicht am Titel — den
/// ändern wir ja gerade.
@MainActor
enum Menuetitel {
    static func nachfuehren(_ speicher: Planungsspeicher) {
        eintrag(umschalt: false)?.title = speicher.widerrufenTitel
        eintrag(umschalt: true)?.title = speicher.wiederholenTitel
    }

    static func eintrag(umschalt: Bool) -> NSMenuItem? {
        for oben in NSApp.mainMenu?.items ?? [] {
            for eintrag in oben.submenu?.items ?? []
            where eintrag.keyEquivalent == "z"
                && eintrag.keyEquivalentModifierMask.contains(.shift) == umschalt {
                return eintrag
            }
        }
        return nil
    }
}

/// Wer die Schreibmarke hat (E87).
///
/// Ein Textfeld bearbeitet AppKit durch den Feldeditor des Fensters — eine
/// `NSTextView`, die als Ersthelfer einspringt. Nur wenn dort wirklich
/// geschrieben wird, gehört ⌘Z dem Feld; alles andere gehört dem Schauplatz.
@MainActor
enum Schreibmarke {
    static var feldeditor: NSTextView? {
        guard let feld = NSApp.keyWindow?.firstResponder as? NSTextView, feld.allowsUndo else {
            return nil
        }
        return feld
    }
}

/// Das Suchfeld gehört zur Werkzeugleiste des Systems; der Menübefehl erreicht
/// es über eine Nachricht, damit die Ansicht die Schreibmarke selbst setzt.
enum Suchfeldbefehl {
    static let name = Notification.Name("unterrichtsplanung.suchfeld.fokus")
    @MainActor static func fokussieren() {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

/// Der „Über“-Dialog. Was er über Herkunft und Lizenz sagt, steht hier; die
/// Adresse des Quelltextes kommt aus der `Info.plist` (Schlüssel `UPQuelltext`),
/// damit `bauen.sh` für den Beipackzettel des DMG dieselbe liest.
@MainActor
enum Ueber {
    static let lizenz = "GNU General Public License, Version 3 oder neuer"
    static let lizenzKennung = "GPL-3.0-or-later"
    static let lizenzAdresse = "https://www.gnu.org/licenses/gpl-3.0.html"

    /// Wo der Quelltext zu haben ist — `nil`, solange das Repository nicht
    /// veröffentlicht ist; die Zeile bleibt dann im Dialog weg.
    static var quelltextAdresse: URL? {
        guard let wert = Bundle.main.infoDictionary?["UPQuelltext"] as? String,
              !wert.isEmpty else { return nil }
        return URL(string: wert)
    }

    static func zeigen() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let schrift = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let mitte = NSMutableParagraphStyle()
        mitte.alignment = .center
        let leise: [NSAttributedString.Key: Any] = [
            .font: schrift, .paragraphStyle: mitte,
            .foregroundColor: NSColor.secondaryLabelColor]
        func verweis(_ ziel: URL) -> [NSAttributedString.Key: Any] {
            [.font: schrift, .paragraphStyle: mitte, .link: ziel]
        }

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: "Erstellt mit Claude Code (Opus 5/5.5 & Fable 5/5.1)\n", attributes: leise))
        text.append(NSAttributedString(string: "Freie Software unter der ", attributes: leise))
        if let ziel = URL(string: lizenzAdresse) {
            text.append(NSAttributedString(string: lizenz, attributes: verweis(ziel)))
        } else {
            text.append(NSAttributedString(string: lizenz, attributes: leise))
        }
        text.append(NSAttributedString(
            string: " — ohne Gewährleistung. Der Lizenztext liegt der App bei.",
            attributes: leise))
        if let ziel = quelltextAdresse {
            text.append(NSAttributedString(string: "\nQuelltext: ", attributes: leise))
            text.append(NSAttributedString(string: ziel.absoluteString, attributes: verweis(ziel)))
        }
        return text
    }
}
