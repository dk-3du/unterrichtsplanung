// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Der Sitzplan-Editor am echten Fenster.
@MainActor
enum Sitzplanprobe {

    /// Erfundene Namen für Abbilder und Prüfstände.
    static let beispielnamen = [
        "Amira Yilmaz", "Ben Fischer", "Clara Weber", "David Schmidt", "Elif Kaya", "Finn Wagner",
        "Greta Becker", "Hannah Schulz", "Ida Hoffmann", "Jonas Koch", "Lea Richter", "Liam Klein",
        "Mara Wolf", "Mia Neumann", "Noah Braun", "Ole Krüger", "Paul Zimmermann", "Rosa Hartmann",
        "Samuel Lange", "Sofia Schröder", "Tom Krause", "Yara Meier", "Zoe Lehmann", "Emil Vogel",
    ]

    /// `--abbild --dialog sitzplan`: die Fläche mit vierundzwanzig Tischen;
    /// mit `ABBILD_SITZPLAN=namen` die leere Liste.
    static func abbildVorbereiten(_ speicher: Planungsspeicher) {
        guard let klasse = speicher.planung?.klassen.first else { return }
        if ProcessInfo.processInfo.environment["ABBILD_SITZPLAN"] != "namen" {
            speicher.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse.id, namen: beispielnamen))
        }
        speicher.sitzplanOeffnen(klasse: klasse.id)
    }

    /// `--sitzplantest`: entsperren, Editor öffnen, zehn Namen tippen, ⌘⏎
    /// anordnen, einen Tisch ziehen, zwei per Rechtsziehen auswählen und
    /// gemeinsam ziehen, „Sitzplan entfernen“ bis zur Rückfrage und
    /// abbrechen, übernehmen, die Datei prüfen, eine PDF in den Prüfordner
    /// schreiben und ihr Maß lesen. Braucht eine gesäte `planung.json`; liegt
    /// sie versiegelt, die Passphrase in `ENTSPERRPROBE_PASSPHRASE`.
    static func laufenUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            var zeilen = ["SITZPLANTEST"]
            var bestanden = true
            func pruefen(_ gilt: Bool, _ text: String) {
                zeilen.append("  \(gilt ? "✓" : "✗") \(text)")
                if !gilt { bestanden = false }
            }
            func ende() async {
                zeilen.append(bestanden ? "SITZPLANTEST bestanden" : "SITZPLANTEST mit Befund")
                print(zeilen.joined(separator: "\n"))
                await Pruefstaende.blaetterSchliessenUndBeenden(speicher)
            }
            @MainActor func sichtbaresFenster() -> NSWindow? { NSApp.windows.first { $0.isVisible } }
            @MainActor func suchen<T: NSView>(_ ansicht: NSView?, _ art: T.Type) -> T? {
                guard let ansicht else { return nil }
                if let treffer = ansicht as? T { return treffer }
                for kind in ansicht.subviews {
                    if let treffer = suchen(kind, art) { return treffer }
                }
                return nil
            }

            try? await Task.sleep(for: .seconds(2.5))
            if speicher.verschluesselungsstand == .gesperrt {
                let passphrase = ProcessInfo.processInfo.environment["ENTSPERRPROBE_PASSPHRASE"] ?? ""
                await speicher.entsperren(passphrase: passphrase)
                try? await Task.sleep(for: .milliseconds(600))
            }
            pruefen(speicher.planung != nil, "Planung geladen — Stand \(speicher.verschluesselungsstand)")
            guard let klasse = speicher.planung?.klassen.first else {
                pruefen(false, "keine Klasse")
                await ende()
                return
            }
            pruefen(speicher.sitzplaene.schreibbar, "Sitzpläne offen (\(speicher.sitzplaene.quelle))")
            if speicher.sitzplan(fuer: klasse.id) != nil {
                speicher.sitzplaene.setzen(nil, fuer: klasse.id)
                zeilen.append("  Rest aus einem vorigen Lauf entfernt")
            }

            speicher.sitzplanOeffnen(klasse: klasse.id)
            for _ in 0..<40 where sichtbaresFenster()?.attachedSheet == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = sichtbaresFenster(), let blatt = fenster.attachedSheet else {
                pruefen(false, "kein Blatt — Dialog \(speicher.offenerDialog?.rawValue ?? "—")")
                await ende()
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            blatt.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(800))
            pruefen(speicher.offenerDialog == .sitzplan, "Editor offen für „\(klasse.name)“")

            @MainActor func taste(_ zeichen: String, code: UInt16 = 0,
                                  _ tasten: NSEvent.ModifierFlags = []) {
                for art in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let ereignis = NSEvent.keyEvent(
                        with: art, location: .zero, modifierFlags: tasten,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: blatt.windowNumber, context: nil,
                        characters: zeichen, charactersIgnoringModifiers: zeichen,
                        isARepeat: false, keyCode: code) else { continue }
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }
            @MainActor func maus(_ art: NSEvent.EventType, _ punkt: NSPoint,
                                 _ tasten: NSEvent.ModifierFlags = [], klicks: Int = 1) {
                guard let ereignis = NSEvent.mouseEvent(
                    with: art, location: punkt, modifierFlags: tasten,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: blatt.windowNumber, context: nil,
                    eventNumber: 0, clickCount: klicks,
                    pressure: art == .leftMouseDown || art == .rightMouseDown ? 1 : 0) else { return }
                NSApp.postEvent(ereignis, atStart: false)
            }

            // Zehn Namen in die Liste tippen.
            guard let liste = suchen(blatt.contentView, NSTextView.self), liste.isEditable else {
                pruefen(false, "kein Textfeld für die Namen")
                await ende()
                return
            }
            blatt.makeFirstResponder(liste)
            try? await Task.sleep(for: .milliseconds(200))
            let namen = Array(beispielnamen.prefix(10))
            for (stelle, name) in namen.enumerated() {
                for zeichen in name { taste(String(zeichen)) }
                if stelle < namen.count - 1 { taste("\r", code: 36) }
            }
            try? await Task.sleep(for: .milliseconds(600))
            let getippt = liste.string.split(separator: "\n").count
            pruefen(getippt == namen.count, "\(getippt) Zeilen getippt")

            // ⌘⏎: Tische anordnen.
            taste("\r", code: 36, [.command])
            try? await Task.sleep(for: .milliseconds(900))
            guard let flaeche = suchen(blatt.contentView, Sitzplanansicht.self) else {
                pruefen(false, "keine Fläche nach ⌘⏎ — Entwurf \(speicher.sitzplanEntwurf?.tische.count ?? -1) Tische")
                await ende()
                return
            }
            pruefen(flaeche.plan.tische.count == namen.count,
                    "Fläche mit \(flaeche.plan.tische.count) Tischen, Lehrertisch "
                    + (flaeche.plan.lehrertisch == nil ? "fehlt" : "da"))
            let reihen = Set(flaeche.plan.tische.map(\.y)).sorted(by: >)
            pruefen(reihen.count == 2 && reihen.first == Sitzplanmasse.ersteReihe,
                    "zwei Reihen, die erste an der Tafel (y \(reihen.map { Int($0) }))")

            // Einen Tisch ziehen: 1 nach rechts, 143 nach oben (von der Tafel weg,
            // in eine leere Reihe) — eingerastet 0 und 144.
            @MainActor func imBlatt(_ punkt: CGPoint) -> NSPoint {
                flaeche.convert(punkt, to: nil)
            }
            let erster = flaeche.plan.tische[0]
            let mitte = CGPoint(x: erster.rahmen.midX, y: erster.rahmen.midY)
            maus(.leftMouseDown, imBlatt(mitte))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.leftMouseDragged, imBlatt(CGPoint(x: mitte.x, y: mitte.y - 70)))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.leftMouseDragged, imBlatt(CGPoint(x: mitte.x + 1, y: mitte.y - 143)))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.leftMouseUp, imBlatt(CGPoint(x: mitte.x + 1, y: mitte.y - 143)))
            try? await Task.sleep(for: .milliseconds(400))
            let gezogen = flaeche.plan.tische[0]
            pruefen(gezogen.x == erster.x && gezogen.y == erster.y - 144,
                    "Tisch gezogen und eingerastet: (\(Int(erster.x)), \(Int(erster.y))) → (\(Int(gezogen.x)), \(Int(gezogen.y)))")
            pruefen(speicher.sitzplanEntwurf?.tische[0].x == gezogen.x, "Entwurf im Speicher folgt")

            // Bereichsauswahl mit der rechten Maustaste über Tisch 2 und 3.
            let zweiter = flaeche.plan.tische[1], dritter = flaeche.plan.tische[2]
            let von = CGPoint(x: zweiter.rahmen.minX - 4, y: zweiter.rahmen.minY - 4)
            let bis = CGPoint(x: dritter.rahmen.maxX + 4, y: dritter.rahmen.maxY + 4)
            maus(.rightMouseDown, imBlatt(von))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.rightMouseDragged, imBlatt(CGPoint(x: (von.x + bis.x) / 2, y: (von.y + bis.y) / 2)))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.rightMouseDragged, imBlatt(bis))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.rightMouseUp, imBlatt(bis))
            try? await Task.sleep(for: .milliseconds(400))
            pruefen(flaeche.auswahl == [zweiter.id, dritter.id],
                    "Bereichsauswahl trifft Tisch 2 und 3 (\(flaeche.auswahl.count) angewählt)")

            // Die Gruppe gemeinsam ziehen: 16 nach rechts.
            let mitte2 = CGPoint(x: zweiter.rahmen.midX, y: zweiter.rahmen.midY)
            maus(.leftMouseDown, imBlatt(mitte2))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.leftMouseDragged, imBlatt(CGPoint(x: mitte2.x + 17, y: mitte2.y)))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.leftMouseUp, imBlatt(CGPoint(x: mitte2.x + 17, y: mitte2.y)))
            try? await Task.sleep(for: .milliseconds(400))
            let z2 = flaeche.plan.tische[1], z3 = flaeche.plan.tische[2]
            pruefen(z2.x == zweiter.x + 16 && z3.x == dritter.x + 16 && z2.y == zweiter.y,
                    "Gruppe gemeinsam verschoben (+16): Tisch 2 x \(Int(z2.x)), Tisch 3 x \(Int(z3.x))")

            // Pfeiltaste: die Gruppe 8 nach oben.
            blatt.makeFirstResponder(flaeche)
            taste("", code: 126)
            try? await Task.sleep(for: .milliseconds(300))
            pruefen(flaeche.plan.tische[1].y == zweiter.y - 8 && flaeche.plan.tische[2].y == dritter.y - 8,
                    "Pfeil nach oben: Gruppe um 8 nach oben")

            // Sitzplan entfernen — bis zur Rückfrage, dann abbrechen.
            let vorher = flaeche.plan
            speicher.sitzplanUebernehmen(vorher)
            speicher.sitzplanEntfernen(klasse: klasse.id, ort: .sitzplan) {}
            try? await Task.sleep(for: .milliseconds(300))
            pruefen(speicher.rueckfrage?.ort == .sitzplan, "„Sitzplan entfernen“ stellt die Rückfrage")
            speicher.rueckfrageBeantworten(false)
            try? await Task.sleep(for: .milliseconds(300))
            pruefen(speicher.sitzplan(fuer: klasse.id) != nil && flaeche.plan == vorher,
                    "abgebrochen — nichts geändert")

            // Übernehmen mit ⏎; bleibt das Blatt, über den Speicher.
            taste("\r", code: 36)
            for _ in 0..<8 where speicher.offenerDialog == .sitzplan {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if speicher.offenerDialog == .sitzplan {
                zeilen.append("  ⏎ erreichte den Übernehmen-Knopf nicht — übernommen über den Speicher")
                speicher.sitzplanUebernehmen(flaeche.plan)
                speicher.sitzplanDialogSchliessen()
                speicher.offenerDialog = nil
            } else {
                zeilen.append("  ⏎ hat übernommen und das Blatt geschlossen")
            }
            await Planungsspeicher.blaetterAbloesenAbwarten()
            let gespeichert = speicher.sitzplan(fuer: klasse.id)
            // Das Übernehmen stempelt `geaendert` neu — verglichen werden Tische und Lehrertisch.
            pruefen(gespeichert?.tische == vorher.tische && gespeichert?.lehrertisch == vorher.lehrertisch,
                    "Sitzplan im Speicher: \(gespeichert?.tische.count ?? 0) Tische, Lehrertisch "
                    + (gespeichert?.lehrertisch == nil ? "fehlt" : "da"))

            // Die Datei: Behälter oder Klartext, wie die Planung.
            let ablage = speicher.sicherung.ablage
            if let roh = try? Data(contentsOf: ablage.sitzplaene) {
                if let tresor = speicher.tresor {
                    let kopf = try? Tresor.kopfLesen(roh)
                    pruefen(Tresor.istBehaelter(roh) && kopf?.inhalt == "sitzplaene" && kopf?.kennung == tresor.kennung,
                            "sitzplaene.json ist ein Behälter mit Inhalt „sitzplaene“ unter dem Schlüssel der Sitzung")
                    pruefen((try? Sitzplandatei.lesen(try tresor.oeffnen(roh)))?[klasse.id] == gespeichert,
                            "Behälter geöffnet: derselbe Plan")
                } else {
                    pruefen(!Tresor.istBehaelter(roh) && (try? Sitzplandatei.lesen(roh))?[klasse.id] == gespeichert,
                            "sitzplaene.json liegt im Klartext neben der Klartext-Planung")
                }
                zeilen.append("  Datei \(roh.count) Byte")
            } else {
                pruefen(false, "sitzplaene.json fehlt")
            }
            // Ein frischer Dienst an derselben Ablage liest ihn wieder.
            let frisch = Sitzplandienst(ablage: ablage)
            let befund = speicher.tresor.map { frisch.oeffnen(mit: $0, stempel: "probe") }
                ?? frisch.laden(stempel: "probe")
            pruefen(befund == .geladen(1) && frisch.plan(fuer: klasse.id) == gespeichert,
                    "frischer Dienst: \(befund)")

            // PDF in den Prüfordner.
            if let plan = gespeichert, let daten = Sitzplandruck.pdf(plan, klasse: klasse) {
                let ziel = ablage.ordner.appendingPathComponent("sitzplan-probe.pdf", isDirectory: false)
                try? daten.write(to: ziel)
                if let quelle = CGDataProvider(data: daten as CFData), let pdf = CGPDFDocument(quelle),
                   let seite = pdf.page(at: 1) {
                    let kasten = seite.getBoxRect(.mediaBox)
                    pruefen(pdf.numberOfPages == 1 && Int(kasten.width) == 842 && Int(kasten.height) == 595,
                            "PDF: \(pdf.numberOfPages) Seite, \(Int(kasten.width)) × \(Int(kasten.height)) pt, "
                            + "\(daten.count) Byte → \(ziel.path)")
                } else {
                    pruefen(false, "PDF nicht lesbar")
                }
            } else {
                pruefen(false, "keine PDF")
            }

            await ende()
        }
    }
}
