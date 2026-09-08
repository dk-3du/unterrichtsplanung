// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Lesezeichen mit Sicherheitsbereich im gesiegelten Paket — und der Beleg,
/// dass das Sandbox greift.
@MainActor
enum Ordnerprobe {

    /// `--ordnertest`: legt im Prüfordner ein Lesezeichen an, löst es auf,
    /// liest im Bereich, verschiebt den Ordner und löst erneut auf — im
    /// gesiegelten Paket mit Sicherheitsbereich, den das Prüfziel von `swift
    /// test` nicht hat. Dazu der Beleg, dass das Sandbox greift: Das
    /// Benutzerverzeichnis außerhalb des Containers ist nicht lesbar.
    ///
    /// Liegt die Ablage versiegelt (`planung.json` als Behälter, Passphrase in
    /// `ENTSPERRPROBE_PASSPHRASE`), prüft der Stand vorher, dass der Vorrat zu
    /// ist, entsperrt, und belegt danach den Behälter `lesezeichen.json`: das
    /// neue Lesezeichen darin, nichts im Klartext, ein frischer Zugriff liest
    /// es wieder. Ein Lesezeichen samt Zielordner bleibt für den nächsten
    /// Lauf liegen — der zweite Lauf derselben Ablage findet beides wieder,
    /// ohne Nachwahl.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            var bestanden = true
            func pruefen(_ gilt: Bool, _ text: String) {
                print("ORDNERTEST \(gilt ? "✓" : "✗") \(text)")
                if !gilt { bestanden = false }
            }
            let verwaltung = FileManager.default
            let zugriff = speicher.zugriff
            let ablage = speicher.sicherung.ablage
            let wurzel = ablage.ordner.appendingPathComponent(
                "ordnertest-\(UUID().uuidString.prefix(8))", isDirectory: true)
            let vorher = wurzel.appendingPathComponent("vorher", isDirectory: true)
            let datei = vorher.appendingPathComponent("notiz.txt", isDirectory: false)
            print("ORDNERTEST Sandbox: \(Ordnerzugriff.imSandbox ? "an" : "aus"), Container: "
                  + "\(Ablage.container?.path ?? "—"), Prüfordner: \(ablage.ordner.path), "
                  + "Ablage: \(speicher.verschluesselungsstand)")
            let versiegelt = speicher.verschluesselungsstand == .gesperrt
            do {
                if versiegelt {
                    pruefen(zugriff.quelle == .zu, "vor dem Entsperren: Vorrat zu (\(zugriff.quelle))")
                    pruefen(speicher.autoexportOrdner.isEmpty, "vor dem Entsperren: kein Zielordner sichtbar")
                    pruefen(speicher.ausstehendeFreigaben.isEmpty, "vor dem Entsperren: keine Nachwahl")
                    let passphrase = ProcessInfo.processInfo.environment["ENTSPERRPROBE_PASSPHRASE"] ?? ""
                    await speicher.entsperren(passphrase: passphrase)
                    pruefen(speicher.verschluesselungsstand == .an,
                            "entsperrt: \(speicher.verschluesselungsstand), Planung „\(speicher.planung?.titel ?? "—")“")
                    pruefen(zugriff.quelle == .behaelter, "nach dem Entsperren: Vorrat aus dem Behälter (\(zugriff.quelle))")
                    // Aus dem vorigen Lauf derselben Ablage?
                    let bleibt = ablage.ordner.appendingPathComponent("ordnertest-bleibt", isDirectory: true)
                    if zugriff.zustaendig(fuer: bleibt.path) != nil {
                        pruefen(true, "Neustart: Lesezeichen aus dem vorigen Lauf gefunden")
                        pruefen(Ordnerzugriff.kanonisch(speicher.autoexportOrdner) == Ordnerzugriff.kanonisch(bleibt.path),
                                "Neustart: Zielordner aus dem Behälter: \(speicher.autoexportOrdner)")
                        pruefen(speicher.ausstehendeFreigaben.isEmpty, "Neustart: keine Nachwahl")
                    } else {
                        print("ORDNERTEST Neustart: erster Lauf — Lesezeichen und Zielordner bleiben für den nächsten liegen")
                        try verwaltung.createDirectory(at: bleibt, withIntermediateDirectories: true)
                        speicher.autoexportZielSetzen(bleibt.path)
                        pruefen(zugriff.zustaendig(fuer: bleibt.path) != nil, "Zielordner gemerkt: \(bleibt.path)")
                    }
                }
                try verwaltung.createDirectory(at: vorher, withIntermediateDirectories: true)
                try Data("Lesezeichen".utf8).write(to: datei)
                let eintrag = try zugriff.merken(vorher)
                pruefen(zugriff.zustaendig(fuer: datei.path) == eintrag,
                        "Lesezeichen angelegt: \(eintrag)")
                let gelesen = try zugriff.mit(datei.path) {
                    try String(contentsOf: $0, encoding: .utf8)
                }
                pruefen(gelesen == "Lesezeichen", "im Sicherheitsbereich gelesen: „\(gelesen)“")
                if versiegelt, let tresor = speicher.tresor {
                    // Der Behälter auf der Platte trägt das neue Lesezeichen; im Klartext liegt nichts.
                    if case .daten(let roh) = ablage.lesezeichenLesen(), let kopf = try? Tresor.kopfLesen(roh),
                       let nutzlast = try? Ordnerzugriff.nutzlastLesen(try tresor.oeffnen(kopf: kopf)) {
                        pruefen(kopf.inhalt == Tresor.Inhalt.lesezeichen.rawValue && kopf.kennung == tresor.kennung,
                                "lesezeichen.json: Inhalt \(kopf.inhalt), Wicklungen "
                                + kopf.wicklungen.map(\.art).sorted().joined(separator: ", ")
                                + ", \(nutzlast.eintraege.count) Lesezeichen, Zielordner „\(Pfade.dateiName(nutzlast.zielordner))“")
                        pruefen(nutzlast.eintraege[eintrag] != nil, "das neue Lesezeichen liegt im Behälter")
                    } else {
                        pruefen(false, "lesezeichen.json nicht lesbar")
                    }
                    pruefen(UserDefaults.standard.dictionary(forKey: "unterrichtsplanung.lesezeichen") == nil,
                            "Einstellungen ohne Klartext-Vorrat")
                    pruefen(UserDefaults.standard.string(forKey: Einstellungen.Schluessel.autoexportOrdner) == nil,
                            "Einstellungen ohne Zielordner-Pfad")
                    // Wie nach einem Neustart: ein frischer Zugriff an derselben Ablage.
                    let frisch = Ordnerzugriff(ablage: ablage)
                    frisch.schliessen()
                    pruefen(frisch.zustaendig(fuer: datei.path) == nil && frisch.zielordner.isEmpty,
                            "frischer Zugriff zu: nichts zuständig, kein Zielordner")
                    let befund = frisch.oeffnen(mit: tresor, stempel: "probe")
                    pruefen(befund == .geoeffnet(frisch.alle.count), "frischer Zugriff geöffnet: \(befund)")
                    pruefen(frisch.zustaendig(fuer: datei.path) == eintrag, "aus dem Behälter zuständig")
                    let nochmal = try frisch.mit(datei.path) { try String(contentsOf: $0, encoding: .utf8) }
                    pruefen(nochmal == "Lesezeichen", "aus dem Behälter im Sicherheitsbereich gelesen")
                }
                let nachher = wurzel.appendingPathComponent("nachher", isDirectory: true)
                try verwaltung.moveItem(at: vorher, to: nachher)
                let verlegt = try zugriff.aufloesen(datei.path)
                pruefen(verlegt.path.hasSuffix("/nachher/notiz.txt"),
                        "nach dem Verschieben aufgelöst: \(verlegt.path)")
                let nachgelesen = try zugriff.mit(datei.path) {
                    try String(contentsOf: $0, encoding: .utf8)
                }
                pruefen(nachgelesen == "Lesezeichen", "nach dem Verschieben im Bereich gelesen")
                pruefen(zugriff.zustaendig(fuer: nachher.path) != nil,
                        "Schlüssel nachgeführt: \(zugriff.zustaendig(fuer: nachher.path) ?? "—")")
                // Beide Schlüssel: Der alte bleibt nach dem Verschieben als Zweitname.
                zugriff.vergessen(nachher.path)
                zugriff.vergessen(vorher.path)
                do {
                    _ = try zugriff.aufloesen(datei.path)
                    pruefen(false, "ohne Lesezeichen aufgelöst — das darf nicht sein")
                } catch let fehler as Ordnerzugriff.Fehler {
                    pruefen(fehler.art == .keinLesezeichen, "ohne Lesezeichen benannt: \(fehler.text)")
                }
                let heimat = "/Users/\(NSUserName())/Library/Preferences"
                let verschlossen = !verwaltung.isReadableFile(atPath: heimat)
                pruefen(verschlossen == Ordnerzugriff.imSandbox,
                        "\(heimat) \(verschlossen ? "nicht lesbar" : "lesbar") — "
                        + "\(Ordnerzugriff.imSandbox ? "das Sandbox greift" : "ohne Sandbox")")
            } catch {
                pruefen(false, "Fehler: \(error)")
            }
            try? verwaltung.removeItem(at: wurzel)
            print(bestanden ? "ORDNERTEST bestanden ✓" : "ORDNERTEST NICHT bestanden ✗")
            await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
        }
    }
}
