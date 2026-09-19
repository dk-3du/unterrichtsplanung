// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Der Stand der Web App bei geöffneter App, am gesiegelten Paket (E216 d,
/// E218, v75).
@MainActor
enum Statusprobe {

    /// `--statustest`: legt einen Zielordner mit Lesezeichen an, schreibt die
    /// Statusdatei, wie die Web App sie ablegt, und sendet die Meldung des
    /// Aufwachens aus dem Ruhezustand selbst. Belegt wird, was die Prüfungen
    /// von `swift test` nicht zeigen: Die Meldung kommt im Sandbox-Paket beim
    /// Anwendungsdelegaten an, die Übernahme folgt 15 Sekunden nach der
    /// letzten Meldung (nicht nach der ersten, nicht vorher), der Zielordner
    /// ist über sein Lesezeichen erreichbar, ein offener Dialog lässt sie
    /// warten, bis er zu ist, und der Befehl „Stand der Web App abrufen“ liest
    /// sofort. Dazu der Eintrag „Stand der Web App abrufen“ im Menü: grau ohne
    /// Zielordner, aktiv mit, ohne Neustart, auch bei offenem Blatt, und ⎋ kommt
    /// im Blatt danach an (E223); grau ohne geöffnete Planung (E224). Ein echtes
    /// Aufwachen bleibt dem Live-Test.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            var bestanden = true
            @MainActor func pruefen(_ gilt: Bool, _ text: String) {
                print("STATUSTEST \(gilt ? "✓" : "✗") \(text)")
                fflush(stdout)
                if !gilt { bestanden = false }
            }
            @MainActor func warten(_ sekunden: Double) async {
                try? await Task.sleep(for: .seconds(sekunden))
            }
            @MainActor func erledigt(_ id: String) -> Bool {
                speicher.planung?.eintraege.first { $0.id == id }?.erledigt == true
            }
            @MainActor func gemeldet(_ teil: String) -> Int {
                speicher.meldungen.count { $0.text.contains(teil) }
            }
            @MainActor func aufwachen() {
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification,
                                                           object: NSWorkspace.shared)
            }

            for _ in 0..<40 where speicher.planung == nil { await warten(0.25) }
            let offen = speicher.planung?.eintraege.filter { !$0.erledigt }.map(\.id) ?? []
            guard let planung = speicher.planung, offen.count >= 2 else {
                pruefen(false, "keine Planung mit mindestens zwei offenen Vorhaben")
                print("STATUSTEST mit Befund")
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }

            // E223, E224: Der Eintrag „Stand der Web App abrufen“ folgt dem
            // Zielordner und der Planung — gemessen am Menü, wie es sich beim
            // Öffnen durch den Nutzer zeigt: erst `menuNeedsUpdate` des Delegaten,
            // dann `update()`. Mit `update()` allein bliebe der Stand vom Start.
            @MainActor func abrufEintrag() -> NSMenuItem? {
                NSApp.mainMenu?.items.first { $0.title == "Ablage" || $0.title == "File" }?
                    .submenu?.items.first { $0.title == "Stand der Web App abrufen" }
            }
            @MainActor func eintragAktiv(_ soll: Bool) async -> Bool? {
                var zuletzt: Bool?
                for _ in 0..<30 {
                    if let eintrag = abrufEintrag(), let menue = eintrag.menu {
                        // Wie beim Öffnen durch den Nutzer: erst der Delegat, dann die Prüfung der Einträge.
                        menue.delegate?.menuNeedsUpdate?(menue)
                        menue.update()
                        zuletzt = eintrag.isEnabled
                        if zuletzt == soll { return zuletzt }
                    }
                    await warten(0.1)
                }
                return zuletzt
            }
            @MainActor func zustand(_ aktiv: Bool?) -> String { aktiv.map { $0 ? "aktiv" : "grau" } ?? "fehlt" }

            pruefen(speicher.autoexportOrdner.isEmpty, "zu Beginn kein Zielordner gewählt")
            let anfangs = await eintragAktiv(false)
            pruefen(anfangs == false, "ohne Zielordner ist „Stand der Web App abrufen“ ausgegraut (\(zustand(anfangs)))")

            // Der Zielordner wie beim Nutzer: gewählt, mit Lesezeichen.
            let ziel = speicher.sicherung.ablage.ordner
                .appendingPathComponent("statustest-ziel", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
            } catch {
                pruefen(false, "Zielordner nicht angelegt: \(error.localizedDescription)")
            }
            speicher.autoexportZielSetzen(ziel.path)
            pruefen(!Ordnerzugriff.imSandbox || speicher.zugriff.zustaendig(fuer: ziel.path) != nil,
                    "Zielordner mit Lesezeichen gemerkt (Sandbox: \(Ordnerzugriff.imSandbox ? "an" : "aus"))")
            let gewaehlt = await eintragAktiv(true)
            pruefen(gewaehlt == true, "nach der Wahl des Zielordners aktiv, ohne Neustart (\(zustand(gewaehlt)))")

            /// Ein Stand für genau dieses Vorhaben — bei versiegelter Ablage
            /// versiegelt, wie die Web App ihn ablegt.
            @MainActor func schreiben(_ id: String, kommentar: String = "") {
                do {
                    let jetzt = Zeitrechnung.jetztAlsZeitstempel()
                    let stand = Statusstand(gespeichert: jetzt, planungstitel: planung.titel,
                                            eintraege: [id: .init(erledigt: true, kommentar: kommentar, geaendert: jetzt)])
                    var daten = try Statusdatei.schreiben(stand)
                    if let tresor = speicher.tresor {
                        daten = try tresor.versiegeln(daten, inhalt: .status, ziel: .kopie)
                    }
                    try speicher.sicherung.imZielordner { ordner in
                        try daten.write(to: ordner.appending(component: Statusdatei.name), options: [.atomic])
                    }
                } catch {
                    pruefen(false, "Statusdatei nicht geschrieben: \(error.localizedDescription)")
                }
            }

            // 1 Zweimal aufwachen, fünf Sekunden auseinander: gelesen wird einmal,
            //   15 Sekunden nach der zweiten Meldung. Gemessen wird der Zeitpunkt
            //   der Übernahme, nicht an festen Stellen geschaut — ein überzogener
            //   Schlaf in einer ausgelasteten VM verschöbe sonst das Urteil.
            schreiben(offen[0])
            let erste = ContinuousClock.now
            aufwachen()
            await warten(5)
            let zweite = ContinuousClock.now
            aufwachen()
            var nach: Duration?
            while ContinuousClock.now - zweite < .seconds(30) {
                if erledigt(offen[0]) { nach = ContinuousClock.now - zweite; break }
                await warten(0.25)
            }
            if let nach {
                let sekunden = Double(nach.components.seconds) + Double(nach.components.attoseconds) / 1e18
                let seitErster = ContinuousClock.now - erste
                pruefen(sekunden >= 14 && sekunden <= 25,
                        String(format: "übernommen %.1f s nach der zweiten Meldung (verlangt 14–25 s)", sekunden))
                pruefen(seitErster >= .seconds(19), "nicht schon 15 s nach der ersten Meldung — die zweite ersetzt sie")
            } else {
                pruefen(false, "30 s nach der zweiten Meldung nichts übernommen")
            }
            pruefen(gemeldet("übernommen: 1 Markierung") == 1, "einmal gemeldet: „… übernommen: 1 Markierung.“")

            // 2 Ein offener Dialog lässt die Übernahme warten, bis er zu ist.
            schreiben(offen[1])
            speicher.offenerDialog = .hilfe
            let dritte = ContinuousClock.now
            aufwachen()
            while !speicher.statusVorgemerkt, ContinuousClock.now - dritte < .seconds(30) { await warten(0.25) }
            pruefen(speicher.statusVorgemerkt, "offener Dialog: nach dem Aufwachen vorgemerkt")
            pruefen(!erledigt(offen[1]), "offener Dialog: nichts übernommen, solange er offen ist")
            speicher.offenerDialog = nil
            for _ in 0..<40 where !erledigt(offen[1]) { await warten(0.1) }
            pruefen(erledigt(offen[1]), "nach dem Schließen des Dialogs übernommen")

            // 3 Der Befehl „Stand der Web App abrufen“ liest sofort — hier einen
            //   Kommentar am ersten Vorhaben (die Saat hat zwei). Gelesen wird
            //   abseits des Hauptstrangs (R75-01, v76); gewartet wird auf das Ende.
            schreiben(offen[0], kommentar: "über den Befehl")
            _ = await speicher.statusAbrufen()?.value
            pruefen(speicher.planung?.eintraege.first { $0.id == offen[0] }?.kommentar == "über den Befehl",
                    "der Befehl liest sofort")
            let vorher = gemeldet("Von der Web App liegt nichts Neues vor.")
            _ = await speicher.statusAbrufen()?.value
            pruefen(gemeldet("Von der Web App liegt nichts Neues vor.") == vorher + 1,
                    "der Befehl ohne Neues antwortet: „Von der Web App liegt nichts Neues vor.“")

            // 4 Das Menü „Ablage“ der laufenden App, in seiner Folge — für die
            //   Sichtprüfung vor dem Bau, und der Befehl steht nach „Planung öffnen …“.
            if let ablage = NSApp.mainMenu?.items.first(where: { $0.title == "Ablage" || $0.title == "File" })?.submenu {
                ablage.delegate?.menuNeedsUpdate?(ablage)
                ablage.update()
                let eintraege = ablage.items.map { punkt -> String in
                    if punkt.isSeparatorItem { return "—" }
                    let taste = punkt.keyEquivalent.isEmpty ? "" : " "
                        + (punkt.keyEquivalentModifierMask.contains(.option) ? "⌥" : "")
                        + (punkt.keyEquivalentModifierMask.contains(.shift) ? "⇧" : "")
                        + "⌘" + punkt.keyEquivalent.uppercased()
                    return punkt.title + taste + (punkt.isEnabled ? "" : " (grau)")
                }
                print("STATUSTEST Menü „\(NSApp.mainMenu?.items.first { $0.submenu === ablage }?.title ?? "?")“: "
                      + eintraege.joined(separator: " · "))
                let titel = ablage.items.map(\.title)
                let oeffnen = titel.firstIndex(of: "Planung öffnen …")
                let abrufen = titel.firstIndex(of: "Stand der Web App abrufen")
                pruefen(oeffnen != nil && abrufen == oeffnen.map { $0 + 1 },
                        "„Stand der Web App abrufen“ steht im Menü „Ablage“ direkt nach „Planung öffnen …“")
            } else {
                pruefen(false, "kein Menü „Ablage“ gefunden")
            }

            // 5 E223 bei offenem Blatt: Der Zielordner wird entfernt, während die
            //   Einstellungen offen sind — das Menü wird neu gebaut, der Eintrag
            //   grau, und ⎋ kommt im Blatt weiter an, auf dem Weg des Nutzers
            //   (`Dialograhmen.onExitCommand`, wie in `--dialogtest`). (N04, v49:
            //   Ein Neubau des Menüs bei offenem Blatt ließ ⌘⏎ ins Leere gehen.)
            speicher.offenerDialog = .einstellungen
            var blatt: NSWindow?
            for _ in 0..<40 {
                blatt = NSApp.windows.lazy.compactMap(\.attachedSheet).first
                if blatt != nil { break }
                await warten(0.1)
            }
            if let blatt {
                speicher.autoexportOrdner = ""
                let entfernt = await eintragAktiv(false)
                pruefen(entfernt == false, "Zielordner bei offenem Blatt entfernt: ausgegraut, ohne Neustart (\(zustand(entfernt)))")
                NSApp.activate(ignoringOtherApps: true)
                blatt.makeKeyAndOrderFront(nil)
                await warten(0.5)
                if let taste = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: blatt.windowNumber, context: nil,
                    characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                    isARepeat: false, keyCode: 53) {
                    NSApp.postEvent(taste, atStart: false)
                }
                for _ in 0..<40 where speicher.offenerDialog != nil { await warten(0.1) }
                pruefen(speicher.offenerDialog == nil, "⎋ im Blatt „Einstellungen“ kommt nach dem Neubau des Menüs an")
            } else {
                pruefen(false, "Blatt „Einstellungen“ nicht erschienen")
                speicher.offenerDialog = nil
            }
            speicher.autoexportZielSetzen(ziel.path)
            let wieder = await eintragAktiv(true)
            pruefen(wieder == true, "Zielordner wieder gewählt: aktiv (\(zustand(wieder)))")

            // 6 E224: ohne geöffnete Planung grau, auch mit Zielordner — und mit
            //   ihr wieder aktiv.
            let geoeffnet = speicher.planung
            speicher.planung = nil
            let ohnePlanung = await eintragAktiv(false)
            pruefen(ohnePlanung == false, "ohne geöffnete Planung ausgegraut, auch mit Zielordner (\(zustand(ohnePlanung)))")
            speicher.planung = geoeffnet
            let mitPlanung = await eintragAktiv(true)
            pruefen(mitPlanung == true, "mit geöffneter Planung wieder aktiv (\(zustand(mitPlanung)))")

            print(bestanden ? "STATUSTEST bestanden" : "STATUSTEST mit Befund")
            fflush(stdout)
            await Pruefstaende.abschliessenUndBeenden(speicher)
        }
    }
}
