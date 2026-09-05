// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Die Menüleiste.
///
/// Gesperrt wird beim **Griff**, nicht über `.disabled(…)`: `Befehle` entsteht
/// einmal im Rumpf der `App` und wird nie erneut ausgewertet — ein `.disabled`
/// friert den Stand vom Programmstart ein, als noch keine Planung geladen war.
struct Befehle: Commands {
    let speicher: Planungsspeicher

    private var gesperrt: Bool { speicher.dialogOffen }
    private func wenn(_ erlaubt: Bool, _ handlung: () -> Void) {
        if erlaubt { handlung() }
    }
    private var ohnePlanung: Bool { speicher.planung == nil || speicher.dialogOffen }

    /// Zeigt die Autosicherung im Finder — ersatzweise ihren Ordner, solange
    /// noch nichts geschrieben wurde.
    ///
    /// Statisch, damit der Stand-Dialog denselben Weg nimmt.
    static func autosicherungZeigen(_ speicher: Planungsspeicher) {
        let ablage = Ablage.shared
        if case .erledigt = Systemzugriff.imFinderZeigen(ablage.datei.path) { return }
        if case .erledigt = Systemzugriff.imFinderZeigen(ablage.ordner.path) {
            speicher.melden("Noch keine Autosicherung — der Ordner ist geöffnet.")
            return
        }
        speicher.melden("Die Autosicherung wird beim ersten Speichern angelegt.",
                        .warnung)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Über Unterrichtsplanung") { Ueber.zeigen() }
        }

        // Der eingebaute Befehl käme bei offenem Dialog nicht durch; nie sperren.
        CommandGroup(replacing: .appTermination) {
            Button("Unterrichtsplanung beenden") { speicher.beenden() }
                .keyboardShortcut("q")
        }

        CommandGroup(replacing: .newItem) {
            Button("Neue Planung …") { wenn(!gesperrt) { speicher.offenerDialog = .neuePlanung } }
                .keyboardShortcut("n")
            Button("Planung öffnen …") { wenn(!gesperrt) { speicher.importDialog() } }
                .keyboardShortcut("o")
            Divider()
            Button("Als JSON sichern …") { wenn(!ohnePlanung) { speicher.exportieren() } }
                .keyboardShortcut("s")
            // Der bewusste Weg zum Klartext — bei ausgeschalteter Verschlüsselung
            // dasselbe wie ⌘S, sonst mit Rückfrage.
            Button("Als Klartext-JSON sichern …") {
                wenn(!ohnePlanung) { speicher.exportierenKlartext() }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Ordner der Autosicherung zeigen") {
                Befehle.autosicherungZeigen(speicher)
            }
        }

        CommandGroup(replacing: .printItem) {
            Button("Drucken …") {
                guard !ohnePlanung, let planung = speicher.planung else { return }
                Drucken.drucken(planung, speicher: speicher)
            }
            .keyboardShortcut("p")

            Button("Als PDF sichern …") {
                guard !ohnePlanung, let planung = speicher.planung else { return }
                Drucken.alsPDFSichern(planung, speicher: speicher)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        // `replacing:` statt `after:`: doppelt vergebene Kürzel streicht SwiftUI ersatzlos.
        CommandGroup(replacing: .pasteboard) {
            Button("Ausschneiden") { verschieben() }
                .keyboardShortcut("x")
            Button("Kopieren") { kopieren() }
                .keyboardShortcut("c")
            Button("Einsetzen") { einfuegen() }
                .keyboardShortcut("v")
            Button("Löschen") { loeschen() }
                .keyboardShortcut(.delete, modifiers: [])
            Divider()
            Button("Alles auswählen") { allesWaehlen() }
                .keyboardShortcut("a")
        }

        CommandGroup(after: .textEditing) {
            Button("Vorhaben durchsuchen") { wenn(!ohnePlanung) { Suchfeldbefehl.fokussieren() } }
                .keyboardShortcut("f")
        }

        CommandMenu("Planung") {
            Button("Klassen/Kurse und Fächer …") { wenn(!ohnePlanung) { speicher.offenerDialog = .klassen } }
                .keyboardShortcut("k")
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
            string: "Erstellt mit Claude Code (Opus 5 & Fable 5/5.1)\n", attributes: leise))
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
