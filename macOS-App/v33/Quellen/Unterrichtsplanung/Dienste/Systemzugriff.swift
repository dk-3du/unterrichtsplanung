// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Alles, was die App vom Rechner braucht.
@MainActor
enum Systemzugriff {

    /// Dateitypen, die „öffnen“ hieße: ausführen. Im Finder zeigen geht weiter.
    /// Die Liste trägt, was der Typ nicht hergibt: `.term`
    /// (`com.apple.terminal.session`) führt den hinterlegten Befehl aus, `.tcl`
    /// startet Wish, die Profile gehen an ProfileHelper — alle erben von nichts
    /// Gesperrtem. Die Abbild-Endungen bleiben neben `public.disk-image`
    /// stehen, weil die Endung auch ohne ermittelbaren Inhaltstyp greift.
    static let ausfuehrbareEndungen: Set<String> = [
        "app", "command", "sh", "bash", "zsh", "csh", "py", "rb", "pl", "tcl",
        "scpt", "scptd", "applescript", "workflow", "wflow", "action", "osax",
        "term", "terminal",
        "pkg", "mpkg", "jar", "shortcut", "prefpane", "plugin",
        "mobileconfig", "mobile", "configprofile", "provisionprofile",
        "dmg", "udif", "dmgpart", "iso", "img", "cdr", "smi", "toast",
        "sparseimage", "sparsebundle", "asif", "dvdr", "xip",
    ]

    enum Ergebnis: Sendable {
        case erledigt
        case fehlt(String)
        case abgewiesen(String)
    }

    // ── Finder ────────────────────────────────────────────────────────────

    /// Vereinheitlichte Form eines Pfades — geprüft und geöffnet wird nur sie.
    ///
    /// Sonst ließe sich die Sperre unterlaufen: `…/Rechner.app/.` und
    /// `…/Rechner.app/Contents/..` tragen keine Endung, zeigen aber auf
    /// dasselbe Programmbündel.
    static func vereinheitlicht(_ pfad: String) -> URL {
        URL(fileURLWithPath: pfad).standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Führt eine Aliasdatei auf das zurück, worauf sie zeigt.
    ///
    /// `resolvingSymlinksInPath()` erfasst nur echte Symlinks. Eine Aliasdatei
    /// trägt weder Endung noch Inhaltstyp ihres Ziels, `NSWorkspace.open`
    /// startet über sie aber das Ziel — ein Alias auf ein Programm kam so an
    /// der Sperre vorbei. Die Kette ist begrenzt, damit ein Ring nicht anhält.
    static func aufgeloest(_ ziel: URL) -> URL {
        var lauf = ziel.standardizedFileURL
        for _ in 0..<8 {
            guard let naechstes = try? URL(resolvingAliasFileAt: lauf,
                                           options: [.withoutUI, .withoutMounting])
            else { break }
            let gerichtet = naechstes.standardizedFileURL.resolvingSymlinksInPath()
            if gerichtet == lauf { break }
            lauf = gerichtet
        }
        return lauf
    }

    static func imFinderZeigen(_ pfad: String) -> Ergebnis {
        let ziel = vereinheitlicht(pfad)
        guard FileManager.default.fileExists(atPath: ziel.path) else {
            return .fehlt("Nicht gefunden: " + Pfade.dateiName(pfad))
        }
        NSWorkspace.shared.activateFileViewerSelecting([ziel])
        return .erledigt
    }

    static func dateiOeffnen(_ pfad: String) -> Ergebnis {
        let ziel = vereinheitlicht(pfad)
        guard FileManager.default.fileExists(atPath: ziel.path) else {
            return .fehlt("Nicht gefunden: " + Pfade.dateiName(pfad))
        }
        guard oeffnenErlaubt(ziel) else {
            return .abgewiesen("Ausführbare Dateien werden nicht geöffnet — im Finder zeigen geht weiterhin.")
        }
        // Geöffnet wird genau das geprüfte Ziel, sonst fielen Prüfung und Wirkung auseinander.
        NSWorkspace.shared.open(aufgeloest(ziel))
        return .erledigt
    }

    /// Ordner ja, gewöhnliche Dateien ja — alles Startbare nein.
    ///
    /// Die Reihenfolge zählt: erst die Endung, dann der Ordner-Ausstieg — sonst
    /// kämen `.workflow`, `.prefpane`, `.plugin`, `.action` und `.osax` nie an
    /// der Liste an, denn sie sind allesamt Ordner.
    static func oeffnenErlaubt(_ pfad: String) -> Bool {
        oeffnenErlaubt(vereinheitlicht(pfad))
    }

    static func oeffnenErlaubt(_ roh: URL) -> Bool {
        let ziel = aufgeloest(roh)
        if ausfuehrbareEndungen.contains(ziel.pathExtension.lowercased()) { return false }

        let werte = try? ziel.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey,
                                                       .isApplicationKey, .contentTypeKey])
        if werte?.isPackage == true || werte?.isApplication == true { return false }
        if werte?.isDirectory == true { return true }

        // Nach dem Typ, nicht nach dem POSIX-Ausführungsbit: das trägt in Netz- und FAT-Ordnern jede Datei.
        if let typ = werte?.contentType {
            for gefaehrlich in startbareTypen where typ.conforms(to: gefaehrlich) { return false }
            return true
        }
        return !FileManager.default.isExecutableFile(atPath: ziel.path)
    }

    /// Typen, die zu öffnen hieße: auszuführen.
    ///
    /// `public.stored-url` fasst die Verweisdateien (`.webloc`, `.fileloc`,
    /// `.inetloc`, `.url`): Sie tragen eine Adresse statt eines Inhalts, und die
    /// kann auf alles zeigen — geöffnet würde nicht die geprüfte Datei.
    /// `public.disk-image` fasst die Abbilder, die DiskImageMounter einhängt,
    /// und wächst mit — `.asif`, `.udif`, `.dmgpart` und `.dvdr` kamen so hinzu.
    private static let startbareTypen: [UTType] = [
        .executable, .application, .unixExecutable, .script, .shellScript,
        .osaScript, .osaScriptBundle, .applicationBundle, .systemPreferencesPane,
    ] + ["public.stored-url", "public.disk-image"].compactMap { UTType($0) }

    static func adresseOeffnen(_ adresse: String) {
        guard let url = URL(string: adresse),
              url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
        else { return }
        NSWorkspace.shared.open(url)
    }

    // ── Auswahldialoge ────────────────────────────────────────────────────

    static func dateienWaehlen(start: String) -> [String] {
        auswahl(ordner: false, mehrere: true, start: start,
                titel: "Material auswählen", knopf: "Verknüpfen")
    }

    static func dateiWaehlen(start: String, titel: String) -> String? {
        auswahl(ordner: false, mehrere: false, start: start,
                titel: titel, knopf: "Zuweisen").first
    }

    /// Der Titel sagt, wofür der Ordner gebraucht wird: Materialien oder
    /// Zielordner der Sicherungskopie.
    static func ordnerWaehlen(start: String, mehrere: Bool = true,
                              titel: String = "Ordner für die Unterrichtsmaterialien wählen")
    -> [String] {
        auswahl(ordner: true, mehrere: mehrere, start: start, titel: titel, knopf: "Wählen")
    }

    private static func auswahl(ordner: Bool, mehrere: Bool, start: String,
                                titel: String, knopf: String) -> [String] {
        let dialog = NSOpenPanel()
        dialog.message = titel
        dialog.prompt = knopf
        dialog.canChooseFiles = !ordner
        dialog.canChooseDirectories = ordner
        dialog.allowsMultipleSelection = mehrere
        dialog.resolvesAliases = true
        dialog.showsHiddenFiles = false
        if !start.isEmpty,
           let werte = try? URL(fileURLWithPath: start).resourceValues(forKeys: [.isDirectoryKey]),
           werte.isDirectory == true {
            dialog.directoryURL = URL(fileURLWithPath: start)
        }
        guard dialog.runModal() == .OK else { return [] }
        return dialog.urls.map(\.path)
    }

    static func zielWaehlen(name: String) -> URL? {
        let dialog = NSSavePanel()
        dialog.message = "Planung als JSON-Datei sichern"
        dialog.nameFieldStringValue = name
        dialog.allowedContentTypes = [.json]
        dialog.canCreateDirectories = true
        dialog.isExtensionHidden = false
        return dialog.runModal() == .OK ? dialog.url : nil
    }

    static func quelleWaehlen() -> URL? {
        let dialog = NSOpenPanel()
        dialog.message = "Planungsdatei öffnen"
        dialog.prompt = "Öffnen"
        dialog.allowedContentTypes = [.json]
        dialog.allowsMultipleSelection = false
        dialog.canChooseDirectories = false
        return dialog.runModal() == .OK ? dialog.url : nil
    }

    // ── Zwischenablage ────────────────────────────────────────────────────

    @discardableResult
    static func inZwischenablage(_ text: String) -> Bool {
        let brett = NSPasteboard.general
        brett.clearContents()
        return brett.setString(text, forType: .string)
    }

    static func ausZwischenablage() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }
}
