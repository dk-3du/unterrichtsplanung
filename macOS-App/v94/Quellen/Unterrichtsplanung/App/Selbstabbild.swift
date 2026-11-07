// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// `--abbild <datei.png>`: startet, wartet auf das Fenster, legt es als PNG ab
/// und beendet sich. Liquid Glass zeichnet das Fenstersystem — abseits des
/// Bildschirms gezeichnete Ansichten zeigen davon nichts.
@MainActor
enum Selbstabbild {

    /// Der Prüfordner des Laufs — dorthin wandert ein Abbild, das im Sandbox
    /// außerhalb des Containers läge. Gesetzt vom Verteiler.
    static var pruefordner: URL?

    /// Mit `--dialog <name>` wird vorher der genannte Dialog abgebildet;
    /// `ABBILD_DUNKEL=1` schaltet die Darstellung vorher auf dunkel.
    static func ablegenUndBeenden(_ speicher: Planungsspeicher, ziel: URL,
                                  nach wartezeit: TimeInterval = 2.0) {
        Task { @MainActor in
            if ProcessInfo.processInfo.environment["ABBILD_DUNKEL"] == "1" { speicher.erscheinung = .dunkel }
            try? await Task.sleep(for: .seconds(wartezeit))
            let teile = ProcessInfo.processInfo.arguments
            // Eine versiegelte Saat mit `ENTSPERRPROBE_PASSPHRASE`: erst entsperren —
            // außer das Abbild gilt dem Entsperren selbst (v80).
            if ProcessInfo.processInfo.environment["ENTSPERRPROBE_PASSPHRASE"] != nil,
               speicher.verschluesselungsstand == .gesperrt, !teile.contains("entsperren") {
                await speicher.entsperren(passphrase: ProcessInfo.processInfo.environment["ENTSPERRPROBE_PASSPHRASE"] ?? "")
                try? await Task.sleep(for: .milliseconds(800))
            }
            if let stelle = teile.firstIndex(of: "--dialog"), stelle + 1 < teile.count {
                let name = teile[stelle + 1]
                // `ABBILD_MELDUNG=<Text>`: eine Warnung, während das Blatt steht — mit der Meldungszeile (E487).
                let meldung = ProcessInfo.processInfo.environment["ABBILD_MELDUNG"] ?? ""
                if name == "ueber" {
                    // Eigenes Fenster, kein Blatt — deshalb das Schlüsselfenster.
                    Ueber.zeigen()
                    try? await Task.sleep(for: .milliseconds(1200))
                    if let fenster = NSApp.keyWindow ?? NSApp.windows.last(where: \.isVisible) {
                        Selbstabbild.ablegen(fenster, nach: ziel)
                    }
                    await Pruefstaende.abschliessenUndBeenden(speicher)
                    return
                }
                if name == "vorhaben" || name == "material" {
                    let mitLink = speicher.planung?.eintraege.first { !$0.links.isEmpty }
                    if let mitLink { speicher.vorhabenOeffnen(id: mitLink.id) }
                    // `ABBILD_REITER=<reiter>` (v85): das Blatt auf diesem Reiter — `grundlegendes`, `kommentar`,
                    // `pruefung`, `termin`, `hausaufgabe`, `material` oder `links`.
                    if let wert = ProcessInfo.processInfo.environment["ABBILD_REITER"] {
                        if let reiter = Vorhabenreiter.allCases.first(where: { "\($0)" == wert }) {
                            speicher.vorhabenReiter = reiter
                        } else {
                            print("ABBILD_REITER=\(wert): kein Reiter (grundlegendes, kommentar, pruefung, termin, "
                                  + "hausaufgabe, material, links)")
                        }
                    }
                    // `--dialog material`: dazu das Material-Blatt als Bogen — mit
                    // der Liste aus `MATERIAL_QUELLE`; `MATERIAL_ZUSTAND=frage` zeigt
                    // die Frage (keine Erlaubnis), sonst gilt sie für dieses Abbild —
                    // gemerkt wird im Prüfstand nichts. Ins Netz geht das Abbild nie.
                    if name == "material" {
                        if ProcessInfo.processInfo.environment["MATERIAL_ZUSTAND"] != "frage" {
                            speicher.materialienErlauben(true)
                        }
                        try? await Task.sleep(for: .milliseconds(900))
                        speicher.materialblattOffen = true
                    }
                } else if name == "sitzplan" {
                    // Der Editor braucht seine Klasse — nicht nur das Blatt.
                    Sitzplanprobe.abbildVorbereiten(speicher)
                } else if name == "lernende" {
                    // Entsperren und die Lage des Blatts vorgeben.
                    await Lernendenprobe.abbildVorbereiten(speicher)
                } else if let welcher = Dialogfenster(rawValue: name) {
                    if welcher == .ersteinrichtung { ersteinrichtungVorbereiten(speicher) }
                    if welcher == .update { updateVorbereiten(speicher) }
                    if welcher == .nachwahl { nachwahlVorbereiten(speicher) }
                    if welcher == .schuljahrOeffnen { await Lernendenprobe.schuljahrOeffnenVorbereiten(speicher) }
                    if welcher == .neuePlanung, ProcessInfo.processInfo.environment["ABBILD_NEUEPLANUNG"] == "folgejahr" {
                        // `ABBILD_ZUORDNUNG_SAAT=b1`: dazu die Lerngruppen für das Abbild B1 (v86, R2-A2N).
                        if ProcessInfo.processInfo.environment["ABBILD_ZUORDNUNG_SAAT"] == "b1" {
                            Lernendenprobe.zuordnungSaatB1(speicher)
                        } else {
                            Lernendenprobe.neuePlanungVorbereiten(speicher)
                        }
                    }
                    // `ABBILD_NEUEPLANUNG=vorbereitet` (ohne Saat): Frage 1 „Einrichten“, die Passphrase, „Weiter zur
                    // Planung“ — das Blatt öffnet sich selbst, sobald die Einrichtung fort ist, mit vorbereiteter
                    // Verschlüsselung (E604).
                    // `ABBILD_FELD=voll`: 75 Zeilen im Feld — die Klassen der Musterdatei kommen dahinter, ohne Zeile, und der
                    // Hinweis aus E617 erscheint (Z-AT7N-03). Mit einer Saat; über die Ersteinrichtung leert ein zweites
                    // `vorbelegen` das Feld.
                    if welcher == .neuePlanung, ProcessInfo.processInfo.environment["ABBILD_FELD"] == "voll" {
                        speicher.neuePlanungVorgabe = Neuplanungsvorgabe(
                            start: Tag.laufendesSchuljahr,
                            kurstext: (1...Kennwerte.maxKlassen).map { "Kurs \($0)" }.joined(separator: "\n"), mitnehmen: [:])
                    }
                    if welcher == .neuePlanung, ProcessInfo.processInfo.environment["ABBILD_NEUEPLANUNG"] == "vorbereitet" {
                        speicher.ersteinrichtungEinrichten()
                        try? speicher.ersteinrichtungWeiter(passphrase: "Ein Satz, den man behält")
                        speicher.ersteinrichtungZurPlanung()
                    } else {
                        speicher.offenerDialog = welcher
                    }
                    // Die Schritte am stehenden Blatt, je nach derselben Ruhe wie die Meldung unten — bis zu fünfmal
                    // hintereinander, keine neue Frist. An „Neue Planung“: `ABBILD_RUECKFRAGE=1` die Rückfrage ohne
                    // Verschlüsselung (E275) — angelegt wird nichts; `ABBILD_IMPORT=bogen|zeile` (E610); `ABBILD_ZUORDNUNG`
                    // der Bogen „Lerngruppen zuordnen“ in einer Lage (E630). An ⌘O nur `ABBILD_ZUORDNUNG` (Z-AT8P-08).
                    if welcher == .neuePlanung || welcher == .schuljahrOeffnen {
                        for schritt in neuePlanungSchritte(speicher, nurZuordnung: welcher == .schuljahrOeffnen) {
                            try? await Task.sleep(for: .milliseconds(1200))
                            schritt()
                        }
                    }
                }
                // Nach jedem Blatt, auch Vorhaben, Sitzplan und Lernende.
                if !meldung.isEmpty {
                    try? await Task.sleep(for: .milliseconds(1200))
                    speicher.melden(meldung, .warnung)
                }
                try? await Task.sleep(for: .milliseconds(1800))
            }
            if teile.contains("--auswahl"), let eintraege = speicher.planung?.eintraege {
                for (stelle, eintrag) in eintraege.prefix(30).enumerated()
                where stelle % 27 == 0 || stelle == 1 {
                    speicher.anwaehlen(vorhaben: eintrag.id, erweitern: stelle > 0)
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
            if let fenster = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                // Das tiefste Blatt: ein Bogen am Blatt (Material-Blatt) vor dem Blatt.
                var blatt = fenster
                while let bogen = blatt.attachedSheet { blatt = bogen }
                // `ABBILD_ENDE=1`: ein langes Blatt bis ans Ende gerollt — für
                // die Abschnitte unter der Falz (das Vorhaben-Blatt zeigt sie seit
                // AW3-neu über `ABBILD_REITER`).
                if ProcessInfo.processInfo.environment["ABBILD_ENDE"] == "1",
                   let inhalt = blatt.contentView, zumEndeRollen(inhalt) {
                    try? await Task.sleep(for: .milliseconds(400))
                }
                // `ABBILD_ROLLEN=0.45`: ein Abschnitt in der Mitte eines langen Blatts.
                if let roh = ProcessInfo.processInfo.environment["ABBILD_ROLLEN"], let anteil = Double(roh),
                   let inhalt = blatt.contentView, zumEndeRollen(inhalt, anteil: min(max(anteil, 0), 1)) {
                    try? await Task.sleep(for: .milliseconds(400))
                }
                Selbstabbild.ablegen(blatt, nach: ziel)
            }
            await Pruefstaende.abschliessenUndBeenden(speicher)
        }
    }

    /// Rollt die erste senkrecht rollbare Ansicht unter `ansicht` ans Ende —
    /// oder an den Anteil `anteil` des Rollwegs. `false`, wenn es keine gibt.
    private static func zumEndeRollen(_ ansicht: NSView, anteil: Double = 1) -> Bool {
        if let rollen = ansicht as? NSScrollView, let dokument = rollen.documentView,
           dokument.bounds.height > rollen.contentView.bounds.height {
            let weg = (dokument.bounds.height - rollen.contentView.bounds.height) * anteil
            rollen.contentView.scroll(to: NSPoint(x: 0, y: dokument.isFlipped ? weg : dokument.bounds.height
                                                  - rollen.contentView.bounds.height - weg))
            rollen.reflectScrolledClipView(rollen.contentView)
            return true
        }
        for kind in ansicht.subviews where zumEndeRollen(kind, anteil: anteil) { return true }
        return false
    }

    /// `--dialog ersteinrichtung` mit `ABBILD_SCHRITT=frage|passphrase|blatt|
    /// sicherung|updates|materialien`: die Station der Ersteinrichtung (in
    /// Schritten), bevor das Blatt aufgeht. Die Passphrase ist ein
    /// Wegwerfwert. `materialien` ist die vierte Frage — seit v71 gibt es sie,
    /// abbildbar ist sie seit v77. Das Blatt sieht auf jedem Weg gleich aus;
    /// was B67 änderte, ist der Zeitpunkt, nicht das Bild.
    private static func ersteinrichtungVorbereiten(_ speicher: Planungsspeicher) {
        switch ProcessInfo.processInfo.environment["ABBILD_SCHRITT"] ?? "frage" {
        case "passphrase":
            speicher.ersteinrichtungEinrichten()
        case "blatt":
            speicher.ersteinrichtungEinrichten()
            try? speicher.ersteinrichtungWeiter(passphrase: "Ein Satz, den man behält")
            // Der Prüfstand meidet die Enklave — die Vorbereitung endet ehrlich
            // mit „nicht verfügbar“ (E139). Das Abbild soll aber den Betriebsfall
            // zeigen: Mit PRUEFSTAND_BIOMETRIE=0|1 wird das Ergebnis „angelegt“
            // nach dem gestellten Gerät gestellt; ohne Hebel bleibt die Wahrheit
            // des Prüfstands im Bild.
            if ProcessInfo.processInfo.environment["PRUEFSTAND_BIOMETRIE"] != nil {
                speicher.vorbereitungGeraet = .angelegt(biometrie: Tresor.biometrieEingerichtet)
            }
        case "sicherung":
            speicher.ersteinrichtungUeberspringen()
        case "updates":
            speicher.ersteinrichtungUeberspringen()
            speicher.ersteinrichtungZuUpdates()
        case "materialien":
            speicher.ersteinrichtungUeberspringen()
            speicher.ersteinrichtungZuUpdates()
            speicher.ersteinrichtungUpdates(erlauben: false)
        default:
            break
        }
        // `ABBILD_ERSETZT=1`: Eine Übernahme hat die Vorbereitung aus Frage 1 ersetzt — der Hinweis oben in Frage 2
        // (E719, E720; offene Sichtprüfung G3-05: das Abbild ohne Fenster kam weiß).
        if ProcessInfo.processInfo.environment["ABBILD_ERSETZT"] == "1" {
            speicher.verschluesselungsfrage = .ersetzt
        }
    }

    /// Was am stehenden Blatt „Neue Planung“ geschieht, Schritt für Schritt — an ⌘O nur `ABBILD_ZUORDNUNG` (ein ⏎ träfe dort
    /// „Archivieren und öffnen“, Z-AT8P-08): `ABBILD_ZUORDNUNG=vorschlag|verdraengt|ohne` der Bogen „Lerngruppen zuordnen“ in
    /// dieser Lage (E630; an beiden Blättern braucht er eine verschlüsselte Saat mit Lerngruppen, an „Neue Planung“ dazu
    /// `ABBILD_NEUEPLANUNG=folgejahr`);
    /// `ABBILD_RUECKFRAGE=1` die Rückfrage
    /// ohne Verschlüsselung (E275); `ABBILD_IMPORT=bogen` die Musterdatei wie aus dem Dateidialog — der Bogen „Aus IServ
    /// importieren“ (E610); `zeile` dazu ⏎ „Übernehmen“ — die Zeile nach dem Bogen, die Klassen im Feld. Nach
    /// `ABBILD_NEUEPLANUNG=vorbereitet` erst eine Ruhe mehr: Das Blatt kommt dort erst nach der Einrichtung.
    private static func neuePlanungSchritte(_ speicher: Planungsspeicher, nurZuordnung: Bool = false) -> [@MainActor () -> Void] {
        let umgebung = ProcessInfo.processInfo.environment
        var schritte: [@MainActor () -> Void] = []
        // Der Bogen „Lerngruppen zuordnen“ in einer Lage (E629, E630) — ein unbekannter Wert steht im Protokoll.
        if let wert = umgebung["ABBILD_ZUORDNUNG"] {
            if let lage = Zuordnungslage(rawValue: wert) {
                if nurZuordnung { return [{ speicher.zuordnungsbogenVorgabe = lage }] }
            } else {
                print("ABBILD_ZUORDNUNG=\(wert): keine Lage (vorschlag, verdraengt, ohne)")
            }
        }
        if nurZuordnung { return [] }
        if umgebung["ABBILD_NEUEPLANUNG"] == "vorbereitet" { schritte.append {} }
        if umgebung["ABBILD_RUECKFRAGE"] == "1" { schritte.append { speicher.neuePlanungFragen(ort: .neuePlanung) {} } }
        if let art = umgebung["ABBILD_IMPORT"], art == "bogen" || art == "zeile" {
            schritte.append {
                let datei = FileManager.default.temporaryDirectory.appending(component: "abbild-iserv.csv")
                try? Data(iservMuster.utf8).write(to: datei)
                speicher.neuePlanungImportdatei = datei
            }
            if art == "zeile" { schritte.append { eingabetaste() } }
        }
        // Der Bogen „Lerngruppen zuordnen“ in einer Lage (E629, E630) — hier an „Neue Planung“; an ⌘O oben.
        if let lage = umgebung["ABBILD_ZUORDNUNG"].flatMap(Zuordnungslage.init(rawValue:)) {
            schritte.append { speicher.zuordnungsbogenVorgabe = lage }
        }
        return schritte
    }

    /// Eine erfundene Liste der Benutzerverwaltung — nur Vorname, Nachname und Klasse.
    private static let iservMuster = """
        Vorname;Nachname;Klasse
        Anna;Becker;5a
        Ben;Schulz;5a
        Clara;Wagner;5a
        David;Hoffmann;5b
        Emma;Koch;5b
        Finn;Richter;5b
        Greta;Klein;6c
        Hannes;Wolf;6c
        Ida;Neumann;6c
        Jonas;Schröder;6c
        """

    /// ⏎ an das tiefste Blatt — der Weg des Nutzers.
    private static func eingabetaste() {
        guard var fenster = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil && $0.attachedSheet != nil })
        else { return }
        while let bogen = fenster.attachedSheet { fenster = bogen }
        fenster.makeFirstResponder(nil)
        if let ereignis = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: fenster.windowNumber, context: nil,
                                           characters: "\r", charactersIgnoringModifiers: "\r",
                                           isARepeat: false, keyCode: 36) {
            NSApp.postEvent(ereignis, atStart: false)
        }
    }

    /// `--dialog nachwahl`: das Blatt mit zwei vorgegebenen Ordnern, die der
    /// App nicht offenstehen — gemerkt wird nichts.
    private static func nachwahlVorbereiten(_ speicher: Planungsspeicher) {
        speicher.nachwahlVorgeben(
            zielordner: "/Users/lehrkraft/Library/Mobile Documents/com~apple~CloudDocs/Unterrichtsplanung",
            basis: "/Users/lehrkraft/Unterricht")
    }

    /// `--dialog update`: das Release aus `UPDATE_QUELLE` (eine gespeicherte
    /// Antwort der Schnittstelle), sonst das erfundene der Probe. Ins Netz
    /// geht der Prüfstand nie.
    private static func updateVorbereiten(_ speicher: Planungsspeicher) {
        if let pfad = ProcessInfo.processInfo.environment["UPDATE_QUELLE"], !pfad.isEmpty,
           let daten = try? Data(contentsOf: URL(fileURLWithPath: pfad)),
           let release = try? Veroeffentlichung.lesen(daten) {
            speicher.updateVorgeben(release)
        } else {
            speicher.updateVorgeben(.probe)
        }
    }

    /// Im Sandbox schreibt der Prüfstand nur in den Container: Ein Ziel
    /// außerhalb wandert in den Prüfordner, der Name bleibt — die Ausgabe
    /// nennt den Ort.
    static func abbildziel(_ gewuenscht: URL, container: URL?,
                           pruefordner: URL) -> URL {
        let ordner = gewuenscht.deletingLastPathComponent().path
        guard !Ablage.pruefordnerZulaessig(ordner, container: container) else { return gewuenscht }
        return pruefordner.appendingPathComponent(gewuenscht.lastPathComponent, isDirectory: false)
    }

    /// Legt zwei PNG ab: Der übergebene Pfad gibt Ordner und Grundnamen, die
    /// Dateien heißen `<Grundname>-rahmen.png` und `<Grundname>-inhalt.png`.
    static func ablegen(_ fenster: NSWindow, nach gewuenscht: URL) {
        let ziel = abbildziel(gewuenscht, container: Ablage.container,
                              pruefordner: pruefordner ?? gewuenscht.deletingLastPathComponent())
        if ziel != gewuenscht {
            print("ABBILD Ziel außerhalb des Containers — abgelegt im Prüfordner \(ziel.deletingLastPathComponent().path)")
        }
        // Abzeichnen statt Bildschirmaufnahme: Die bräuchte eine Erlaubnis.
        for (name, ansicht) in [("rahmen", fenster.contentView?.superview),
                                ("inhalt", fenster.contentView)] {
            guard let ansicht,
                  let abzug = ansicht.bitmapImageRepForCachingDisplay(in: ansicht.bounds)
            else { continue }
            ansicht.cacheDisplay(in: ansicht.bounds, to: abzug)
            guard let daten = abzug.representation(using: .png, properties: [:]) else { continue }
            let datei = ziel.deletingPathExtension().lastPathComponent + "-" + name + ".png"
            let ort = ziel.deletingLastPathComponent().appendingPathComponent(datei)
            do {
                try daten.write(to: ort)
                print("ABBILD abgelegt: \(ort.path)")
            } catch {
                print("ABBILD nicht ablegbar (\(ort.path)): \(error.localizedDescription)")
            }
        }
    }
}
