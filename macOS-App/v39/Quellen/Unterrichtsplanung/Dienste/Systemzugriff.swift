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
        /// Der Ort ist der App im Sandbox noch nicht gezeigt worden — die
        /// Oberfläche bittet um die Wahl und versucht es dann noch einmal.
        case keinZugriff(String)
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

    /// Führt eine Aliasdatei auf das zurück, worauf sie zeigt — oder auf
    /// nichts, wenn sich das nicht sicher sagen lässt.
    ///
    /// `resolvingSymlinksInPath()` erfasst nur echte Symlinks. Eine Aliasdatei
    /// trägt weder Endung noch Inhaltstyp ihres Ziels, `NSWorkspace.open`
    /// startet über sie aber das Ziel — ein Alias auf ein Programm kam so an
    /// der Sperre vorbei. Ein Alias, der sich nicht auflösen lässt, ein Ring
    /// und eine Kette über acht Stufen liefern `nil`: Was nicht geprüft werden
    /// kann, wird nicht geöffnet.
    static func aufgeloest(_ ziel: URL) -> URL? {
        var lauf = ziel.standardizedFileURL.resolvingSymlinksInPath()
        var besucht: Set<String> = []
        for _ in 0..<8 {
            guard besucht.insert(lauf.path).inserted else { return nil }
            let werte = try? lauf.resourceValues(forKeys: [.isAliasFileKey])
            guard werte?.isAliasFile == true else { return lauf }
            guard let naechstes = try? URL(resolvingAliasFileAt: lauf,
                                           options: [.withoutUI, .withoutMounting])
            else { return nil }
            lauf = naechstes.standardizedFileURL.resolvingSymlinksInPath()
        }
        return nil
    }

    /// Die Arbeit im Sicherheitsbereich des zuständigen Lesezeichens — oder
    /// ohne, wo keines nötig ist: ohne Sandbox, im Container, an Orten, die
    /// dem Sandbox offenstehen. Ein Ort ohne Lesezeichen, der sich nicht
    /// lesen lässt, ist im Sandbox „kein Zugriff“, nicht „nicht gefunden“.
    private static func imBereich(_ pfad: String, _ arbeit: (URL) -> Ergebnis) -> Ergebnis {
        let roh = vereinheitlicht(pfad)
        if Ordnerzugriff.zustaendig(fuer: roh.path) != nil {
            do {
                return try Ordnerzugriff.mit(roh.path) { ziel in arbeit(vereinheitlicht(ziel.path)) }
            } catch let fehler as Ordnerzugriff.Fehler {
                return .keinZugriff(fehler.text)
            } catch {
                return .keinZugriff(error.localizedDescription)
            }
        }
        if Ordnerzugriff.imSandbox, !FileManager.default.isReadableFile(atPath: roh.path) {
            return .keinZugriff(Ordnerzugriff.Fehler(.keinLesezeichen, pfad: pfad).text)
        }
        return arbeit(roh)
    }

    static func imFinderZeigen(_ pfad: String) -> Ergebnis {
        imBereich(pfad) { ziel in
            guard FileManager.default.fileExists(atPath: ziel.path) else {
                return .fehlt("Nicht gefunden: " + Pfade.dateiName(pfad))
            }
            NSWorkspace.shared.activateFileViewerSelecting([ziel])
            return .erledigt
        }
    }

    static func dateiOeffnen(_ pfad: String) -> Ergebnis {
        imBereich(pfad) { roh in dateiOeffnen(roh, name: Pfade.dateiName(pfad)) }
    }

    private static func dateiOeffnen(_ roh: URL, name: String) -> Ergebnis {
        guard FileManager.default.fileExists(atPath: roh.path) else {
            return .fehlt("Nicht gefunden: " + name)
        }
        // Einmal aufgelöst, dann geprüft, dann genau dieses Ziel geöffnet — sonst
        // fielen Prüfung und Wirkung auseinander.
        guard let ziel = aufgeloest(roh) else {
            return .abgewiesen("Der Verweis ließ sich nicht auflösen — im Finder zeigen geht weiterhin.")
        }
        guard zielErlaubt(ziel) else {
            return .abgewiesen("Ausführbare Dateien werden nicht geöffnet — im Finder zeigen geht weiterhin.")
        }
        guard NSWorkspace.shared.open(ziel) else {
            return .fehlt("Ließ sich nicht öffnen: " + name + " — im Finder zeigen geht weiterhin.")
        }
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
        guard let ziel = aufgeloest(roh) else { return false }
        return zielErlaubt(ziel)
    }

    /// Die Prüfung am aufgelösten Ziel — nie an einem Alias.
    private static func zielErlaubt(_ ziel: URL) -> Bool {
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
    // Im Sandbox der Weg, Zugriff zu bekommen: Aus jeder Wahl entsteht sofort
    // ein Lesezeichen, damit sie den Neustart übersteht.

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
        // Auch ein Ordner, der der App noch nicht offensteht: Der Dialog läuft
        // außerhalb des Sandbox und zeigt ihn.
        if !start.isEmpty { dialog.directoryURL = URL(fileURLWithPath: start, isDirectory: true) }
        guard dialog.runModal() == .OK else { return [] }
        return gemerkt(dialog.urls).map(\.path)
    }

    /// Die Wahl festhalten — Ordner wie Dateien. Ein Ort, der sich nicht
    /// merken lässt, bleibt für die Sitzung nutzbar; beim nächsten Start
    /// fragt die App nach ihm.
    private static func gemerkt(_ urls: [URL]) -> [URL] {
        for url in urls { _ = try? Ordnerzugriff.merken(url) }
        return urls
    }

    /// Ein Ort, den die App noch nicht erreichen darf: die Datei selbst oder
    /// einen Ordner darüber wählen — ein Ordner gilt für alles darin. Der
    /// Dialog steht schon dort, wo die Datei liegt.
    static func zugriffWaehlen(fuer pfad: String) -> URL? {
        let dialog = NSOpenPanel()
        dialog.message = "Zugriff erlauben: „\(Pfade.dateiName(pfad))“ wählen — oder den Ordner, "
            + "in dem es liegt; ein Ordner gilt für alles darin."
        dialog.prompt = "Erlauben"
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false
        dialog.resolvesAliases = true
        dialog.showsHiddenFiles = false
        dialog.directoryURL = URL(fileURLWithPath: pfad).deletingLastPathComponent()
        guard dialog.runModal() == .OK, let url = dialog.url else { return nil }
        return gemerkt([url]).first
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
