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
    /// mit `ABBILD_SITZPLAN=namen` die leere Liste, mit `=gebunden` die Tische
    /// aus der Lerngruppe der Zeile, der erste Name gekürzt (E255, E284).
    /// Angelegt wird vor dem Öffnen: Nach dem Wechsel von der Liste zur Fläche
    /// im offenen Blatt zeichnet das Abbild nichts (gemessen, auch mit ⌘⏎ in v80).
    static func abbildVorbereiten(_ speicher: Planungsspeicher) {
        guard let klasse = speicher.planung?.klassen.first else { return }
        switch ProcessInfo.processInfo.environment["ABBILD_SITZPLAN"] {
        case "namen":
            break
        case "gebunden":
            var plan = Sitzplan.anordnen(klasseId: klasse.id,
                                         lernende: speicher.sitzplatzangebot(fuer: klasse.id)?.plaetze ?? [])
            if let erster = plan.tische.first {
                plan = plan.umbenannt(erster.id, name: erster.name.split(separator: " ").first.map(String.init) ?? erster.name)
            }
            speicher.sitzplanUebernehmen(plan)
        default:
            speicher.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse.id, namen: beispielnamen))
        }
        speicher.sitzplanOeffnen(klasse: klasse.id)
    }

    /// `--sitzplantest`: entsperren, Editor öffnen, zehn Namen tippen, ⌘⏎
    /// anordnen, einen Tisch ziehen, zwei per Rechtsziehen auswählen und
    /// gemeinsam ziehen, Pfeil, ⌫ und ⌥⏎ (B06), „Sitzplan entfernen“ bis zur
    /// Rückfrage und abbrechen, mit ⏎ übernehmen (B08 — kein stiller
    /// Rückfall mehr), die Datei prüfen, eine PDF in den Prüfordner schreiben
    /// und ihr Maß lesen; zuletzt neu öffnen, ändern, ⎋ und „Verwerfen“ im
    /// eigenen Alert (AU4b). Braucht eine gesäte `planung.json`; liegt
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
                await Pruefstaende.abschliessenUndBeenden(speicher)
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
            // Je warten, bis das Element steht — nicht fest (Z14f-03).
            for _ in 0..<40 where suchen(blatt.contentView, NSTextView.self)?.isEditable != true {
                try? await Task.sleep(for: .milliseconds(250))
            }
            pruefen(speicher.offenerDialog == .sitzplan, "Editor offen für „\(klasse.name)“")

            // `an`: ein anderes Blatt als das erste — der Editor, neu geöffnet (AU4b).
            @MainActor func taste(_ zeichen: String, code: UInt16 = 0,
                                  _ tasten: NSEvent.ModifierFlags = [], an ziel: NSWindow? = nil) {
                for art in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let ereignis = NSEvent.keyEvent(
                        with: art, location: .zero, modifierFlags: tasten,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: (ziel ?? blatt).windowNumber, context: nil,
                        characters: zeichen, charactersIgnoringModifiers: zeichen,
                        isARepeat: false, keyCode: code) else { continue }
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }
            @MainActor func maus(_ art: NSEvent.EventType, _ punkt: NSPoint,
                                 _ tasten: NSEvent.ModifierFlags = [], klicks: Int = 1, an ziel: NSWindow? = nil) {
                guard let ereignis = NSEvent.mouseEvent(
                    with: art, location: punkt, modifierFlags: tasten,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: (ziel ?? blatt).windowNumber, context: nil,
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
            // B84: Die Liste ist eine Liste von Namen wie im Blatt „Lernende“ (B73) — keine Korrektur,
            // keine Prüfung, keine Vorschläge; „van der Berg“ am Zeilenanfang soll klein bleiben.
            // Die vier Werte im Text — ein Rot zeigt, welcher fehlt (Z-AS5-06).
            pruefen(!liste.isContinuousSpellCheckingEnabled && !liste.isAutomaticSpellingCorrectionEnabled
                    && !liste.isAutomaticTextCompletionEnabled && liste.inlinePredictionType == .no,
                    "Namensliste ohne Korrektur, Prüfung und Vorschläge (B84) — Prüfung \(liste.isContinuousSpellCheckingEnabled), "
                    + "Korrektur \(liste.isAutomaticSpellingCorrectionEnabled), Ergänzung \(liste.isAutomaticTextCompletionEnabled), "
                    + "Vorschlag \(liste.inlinePredictionType == .no ? "aus" : "an")")
            let namen = Array(beispielnamen.prefix(9)) + ["van der Berg"]
            for (stelle, name) in namen.enumerated() {
                for zeichen in name { taste(String(zeichen)) }
                if stelle < namen.count - 1 { taste("\r", code: 36) }
            }
            for _ in 0..<20 where liste.string.count < namen.joined(separator: "\n").count {
                try? await Task.sleep(for: .milliseconds(150))
            }
            let getippt = liste.string.split(separator: "\n").count
            pruefen(getippt == namen.count, "\(getippt) Zeilen getippt")
            // Auskunft, kein Befund (Z-AS5-05): Am Mac unterscheidet das Getippte nicht — die Großschreibung
            // des Systems greift beim Tippen des Prüfstands nicht. Die Einstellung oben ist der Beleg.
            try? await Task.sleep(for: .milliseconds(600))
            let letzte = liste.string.split(separator: "\n").last.map(String.init) ?? ""
            zeilen.append("  Getippt: „\(letzte)“ — System: Korrektur \(NSSpellChecker.isAutomaticSpellingCorrectionEnabled ? "an" : "aus"), "
                          + "Großschreibung \(NSSpellChecker.isAutomaticCapitalizationEnabled ? "an" : "aus")")

            // ⌘⏎: Tische anordnen.
            taste("\r", code: 36, [.command])
            for _ in 0..<40 where (suchen(blatt.contentView, Sitzplanansicht.self)?.plan.tische.count ?? 0) < namen.count {
                try? await Task.sleep(for: .milliseconds(250))
            }
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

            // ⌫ entfernt den angewählten Tisch (B06): Tisch 4 anklicken, löschen.
            let vierter = flaeche.plan.tische[3]
            let mitte4 = CGPoint(x: vierter.rahmen.midX, y: vierter.rahmen.midY)
            maus(.leftMouseDown, imBlatt(mitte4))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.leftMouseUp, imBlatt(mitte4))
            try? await Task.sleep(for: .milliseconds(300))
            taste("", code: 51)
            try? await Task.sleep(for: .milliseconds(300))
            pruefen(flaeche.plan.tische.count == namen.count - 1 && flaeche.plan.tisch(vierter.id) == nil,
                    "⌫ entfernt den angewählten Tisch (\(flaeche.plan.tische.count) bleiben)")

            // ⌥⏎ benennt den angewählten Tisch um (B06): Tisch 1 anklicken, ⌥⏎, tippen, ⏎.
            let erster1 = flaeche.plan.tische[0]
            let mitte1 = CGPoint(x: erster1.rahmen.midX, y: erster1.rahmen.midY)
            maus(.leftMouseDown, imBlatt(mitte1))
            try? await Task.sleep(for: .milliseconds(120))
            maus(.leftMouseUp, imBlatt(mitte1))
            try? await Task.sleep(for: .milliseconds(300))
            taste("\r", code: 36, [.option])
            for _ in 0..<20 where !flaeche.subviews.contains(where: { $0 is NSTextField }) {
                try? await Task.sleep(for: .milliseconds(150))
            }
            let namensfeld = flaeche.subviews.first { $0 is NSTextField }
            pruefen(namensfeld != nil, "⌥⏎ öffnet das Namensfeld am Tisch")
            if namensfeld != nil {
                for zeichen in "Zoe Neu" { taste(String(zeichen)) }
                taste("\r", code: 36)
                for _ in 0..<20 where flaeche.plan.tische[0].name != "Zoe Neu" {
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            pruefen(flaeche.plan.tische[0].name == "Zoe Neu", "Name am Tisch: „\(flaeche.plan.tische[0].name)“")

            // Sitzplan entfernen — bis zur Rückfrage, dann abbrechen.
            let vorher = flaeche.plan
            speicher.sitzplanUebernehmen(vorher)
            speicher.sitzplanEntfernen(klasse: klasse.id, ort: .sitzplan) {}
            for _ in 0..<20 where speicher.rueckfrage == nil {
                try? await Task.sleep(for: .milliseconds(150))
            }
            pruefen(speicher.rueckfrage?.ort == .sitzplan, "„Sitzplan entfernen“ stellt die Rückfrage")
            // Wie von Hand, nicht im Programm (B82).
            if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) { pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden") }
            try? await Task.sleep(for: .milliseconds(300))
            pruefen(speicher.sitzplan(fuer: klasse.id) != nil && flaeche.plan == vorher,
                    "abgebrochen — nichts geändert")

            // Übernehmen mit ⏎ auf der Fläche — ein Befund, wenn das Blatt bleibt (B08);
            // dann über den Speicher, damit der Lauf die Datei noch prüfen kann.
            blatt.makeFirstResponder(flaeche)
            taste("\r", code: 36)
            for _ in 0..<8 where speicher.offenerDialog == .sitzplan {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if speicher.offenerDialog == .sitzplan {
                pruefen(false, "⏎ hat nicht übernommen — Blatt noch offen; übernommen über den Speicher, damit der Lauf weitergeht")
                speicher.sitzplanUebernehmen(flaeche.plan)
                speicher.sitzplanDialogSchliessen()
                speicher.offenerDialog = nil
            } else {
                pruefen(true, "⏎ hat übernommen und das Blatt geschlossen")
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

            // Das eigene Alert des Editors (B95, AU4b, E433, E434): neu geöffnet, ein Tisch nach oben, ⎋ —
            // „Die Änderungen am Sitzplan verwerfen?“, „Verwerfen“, gleich danach noch einmal ⎋; der Editor
            // geht erst nach dem Alert und fragt bis dahin nicht erneut (Z-AU4b-01).
            speicher.sitzplanOeffnen(klasse: klasse.id)
            var blatt2: NSWindow?
            var flaeche2: Sitzplanansicht?
            for _ in 0..<40 where flaeche2 == nil {
                try? await Task.sleep(for: .milliseconds(250))
                blatt2 = sichtbaresFenster()?.attachedSheet
                flaeche2 = suchen(blatt2?.contentView, Sitzplanansicht.self)
            }
            if let blatt2, let flaeche2, let tisch = flaeche2.plan.tische.first {
                NSApp.activate(ignoringOtherApps: true)
                blatt2.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(300))
                let punkt = flaeche2.convert(CGPoint(x: tisch.rahmen.midX, y: tisch.rahmen.midY), to: nil)
                maus(.leftMouseDown, punkt, an: blatt2)
                try? await Task.sleep(for: .milliseconds(120))
                maus(.leftMouseUp, punkt, an: blatt2)
                try? await Task.sleep(for: .milliseconds(300))
                let vorPfeil = speicher.sitzplanEntwurf
                blatt2.makeFirstResponder(flaeche2)
                taste("", code: 126, an: blatt2)
                for _ in 0..<12 where speicher.sitzplanEntwurf == vorPfeil {
                    try? await Task.sleep(for: .milliseconds(150))
                }
                pruefen(speicher.sitzplanEntwurf != nil && speicher.sitzplanEntwurf != vorPfeil,
                        "Editor neu geöffnet, ein Tisch nach oben")
                // ⎋ an das Blatt, nicht an die Fläche: Dort brachte es mit angewähltem Tisch kein Alert (gemessen AU4b).
                blatt2.makeFirstResponder(nil)
                taste("\u{1B}", code: 53, an: blatt2)
                var alertKam = false
                for _ in 0..<16 where !alertKam {
                    try? await Task.sleep(for: .milliseconds(125))
                    alertKam = Pruefstaende.alertfenster() != nil
                }
                pruefen(alertKam, "⎋: ein Alert")
                // Ohne Alert ein Befund, nicht vier (Z-AU4b-09).
                if alertKam {
                    // Im Klick zugemacht, wäre der Entwurf gleich danach fort (`zumachen`).
                    let imKlick = await Pruefstaende.eigenesAlertDruecken("Verwerfen") { speicher.sitzplanEntwurf != nil }
                    pruefen(imKlick == true, "„Verwerfen“: gleich nach dem Klick steht der Entwurf noch"
                            + (imKlick == nil ? " (kein Knopf „Verwerfen“)" : ""))
                    // Gleich danach noch einmal ⎋ — in der Lücke, ehe der Editor geht.
                    taste("\u{1B}", code: 53, an: blatt2)
                    var neueFrage = false
                    for _ in 0..<16 where speicher.offenerDialog == .sitzplan || sichtbaresFenster()?.attachedSheet != nil
                        || Pruefstaende.alertfenster() != nil {
                        if Pruefstaende.alertfenster() != nil { neueFrage = true }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    pruefen(!neueFrage, "⎋ gleich nach „Verwerfen“: keine neue Frage (Z-AU4b-01)")
                    let blattFort = sichtbaresFenster()?.attachedSheet == nil, alertFort = Pruefstaende.alertfenster() == nil
                    let planGleich = speicher.sitzplan(fuer: klasse.id) == gespeichert
                    pruefen(speicher.offenerDialog != .sitzplan && blattFort && alertFort && planGleich,
                            "„Verwerfen“: danach geschlossen, der Sitzplan wie gespeichert (Dialog \(speicher.offenerDialog?.rawValue ?? "zu"), "
                            + "Blatt \(blattFort ? "fort" : "steht"), Alert \(alertFort ? "fort" : "steht"), Plan \(planGleich ? "gleich" : "anders"))")
                }
            } else {
                pruefen(false, "Editor zum Verwerfen offen (Blatt \(blatt2 == nil ? "fehlt" : "da"), Fläche fehlt)")
            }

            await ende()
        }
    }
}
