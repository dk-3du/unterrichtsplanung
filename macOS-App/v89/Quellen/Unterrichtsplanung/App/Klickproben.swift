// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Proben am echten Fenster mit echten Ereignissen: rollen, klicken, ziehen,
/// tippen, Menüs — was ein Prüfziel ohne Fenster nicht zeigen kann.
@MainActor
enum Klickproben {

    /// `--rolltest`: rollt das Raster über eine wiederkehrende Uhr und meldet
    /// die Zeit je Bild.
    static func rolltestUndBeenden(zerlegen: Bool) {
        Messzaehler.an = zerlegen
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let rollbereich = groesserRollbereich(in: fenster.contentView) else {
                print("ROLLTEST ✗ kein Rollbereich gefunden")
                fflush(stdout)
                Pruefstaende.abschliessenUndBeenden()
                return
            }

            let messung = Messung()
            messung.beginn = Date()
            messung.rechenzeitVorher = Messung.rechenzeit()
            let uhr = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
                MainActor.assumeIsolated {
                    rollbereich.contentView.scroll(
                        to: NSPoint(x: CGFloat((messung.schritt % 60) * 40), y: 0))
                    rollbereich.reflectScrolledClipView(rollbereich.contentView)
                    messung.schritt += 1
                    guard messung.schritt >= 120 else { return }
                    // Anhalten vor dem Auswerten: Sonst schlüge die Uhr während
                    // des Nachlaufs weiter und riefe `fertig()` erneut auf.
                    messung.uhr?.invalidate()
                    messung.uhr = nil
                    messung.fertig()
                }
            }
            messung.uhr = uhr
            RunLoop.main.add(uhr, forMode: .common)
        }
    }

    /// `--klicktest`: misst einen Handgriff am echten Fenster in echter Größe —
    /// im Prüfstand ist es kleiner, und die Zahl fiele zu günstig aus.
    static func klicktestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            // Ein Frühausstieg sagt ✗, spült aus und endet über die Blätter (N67-01, v68):
            // Bis v67 stand hier nur der Text und `NSApp.terminate` — in einem leeren
            // Ordner wies das Blatt „Neue Planung“ das Beenden ab (Hänger bis zur
            // Frist, die Zeile blieb im Puffer), und mit einer Planung ohne Klassen
            // endete der Lauf still mit Rückgabe 0 — der Treiber zählte ihn grün.
            guard let planung = speicher.planung,
                  let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let klasse = planung.klassen.first else {
                print("KLICKTEST ✗ keine Planung")
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }
            let wochen = planung.wochenListe
            // Rechenzeit statt Uhrzeit: SwiftUI trägt erst im nächsten Ablaufring nach.
            let laeufe = 10
            let vorher = Messung.rechenzeit()
            for lauf in 0..<laeufe {
                speicher.zelleFreiSchalten(klasse: klasse.id, woche: wochen[lauf % wochen.count])
                fenster.contentView?.layoutSubtreeIfNeeded()
                fenster.displayIfNeeded()
                try? await Task.sleep(for: .milliseconds(150))
            }
            let dauer = (Messung.rechenzeit() - vorher) / Double(laeufe) * 1000
            print(String(format: "KLICKTEST %.0f ms Rechenzeit je Handgriff (Fenster %.0f × %.0f, "
                         + "%d Klassen/Kurse, %d Wochen, %d Vorhaben)", dauer,
                         fenster.frame.width, fenster.frame.height,
                         planung.klassen.count, planung.wochen, planung.eintraege.count))
            // An einem Vorhaben ohne Hausaufgabe: „Hausaufgabe hinzufügen …“ am Speicher, wie der Menüeintrag es ruft
            // (den Menüweg selbst geht die Lernendenprobe) — das Blatt auf „Hausaufgabe“ mit eingeschalteter Hausaufgabe
            // im Entwurf; ohne „Übernehmen“ geschlossen, bleibt nichts zurück (E653). Danach Hinzufügen und Entfernen am
            // Speicher; Entfernen wie aus dem Menü, ein Schritt, der die Zeile mitnimmt; die Datei steht wieder wie vorher.
            if let ohne = planung.eintraege.first(where: { !$0.hausaufgabe }) {
                speicher.vorhabenOeffnen(id: ohne.id, alsHausaufgabe: true)
                fenster.contentView?.layoutSubtreeIfNeeded()
                fenster.displayIfNeeded()
                // Zwei Bedingungen hinter einem Zeichen — die verfehlte beim Namen (G1-04).
                var abweichend: [String] = []
                if speicher.vorhabenDialog == nil {
                    abweichend.append("kein Vorhaben-Blatt")  // die Ursache, nicht ihre Folgen (Z-AX0b-08)
                } else {
                    if speicher.vorhabenReiter != .hausaufgabe { abweichend.append("nicht auf „Hausaufgabe“") }
                    if speicher.vorhabenDialog?.hausaufgabe != true { abweichend.append("Hausaufgabe im Entwurf aus") }
                }
                let blatt = abweichend.isEmpty
                speicher.vorhabenDialog = nil
                let nichts = speicher.planung?.eintraege.first { $0.id == ohne.id }?.hausaufgabe == false
                print("KLICKTEST Hausaufgabe hinzufügen …: Blatt auf „Hausaufgabe“ \(blatt ? "✓" : "✗")"
                      + (blatt ? "" : " (\(abweichend.joined(separator: "; ")))")
                      + ", ohne Übernehmen nichts zurück \(nichts ? "✓" : "✗")")
                speicher.hausaufgabeUmschalten(ohne.id)
                let an = speicher.planung?.eintraege.first { $0.id == ohne.id }?.hausaufgabe == true
                speicher.hausaufgabeUmschalten(ohne.id)
                let danach = speicher.planung?.eintraege.first { $0.id == ohne.id }
                let aus = danach?.hausaufgabe == false && danach?.hausaufgabenText == ""
                print("KLICKTEST Hausaufgabe an \(an ? "✓" : "✗"), aus \(aus ? "✓" : "✗")")
            } else {
                print("KLICKTEST Hausaufgabe: kein Vorhaben ohne — übersprungen")
            }
            // Die Gegenprobe der Runde (N67-01, v69): Hier, nach der ersten
            // Zusicherung und vor der Kurszelle, endet der Lauf regulär, wenn
            // PRUEFSTAND_FRUEHES_ENDE gesetzt ist — im Betrieb nie.
            Pruefstaende.fruehesEndeFallsVerlangt()
            // Das Merkmal Korrektur am Paket: aus der Datei gelesen — die Saat der
            // Runde führt eine, und `runde.py` verlangt diese Zeile —, dann
            // geschaltet wie aus dem Rechtsklickmenü. Nach dem frühen Ende, damit
            // die Gegenprobe ihr Szenario behält.
            korrekturProbe(speicher)
            // Kurszelle (v50, E34): Ein echter Klick auf „+ Sitzplan“ in der
            // ersten Zeile öffnet den Editor; mit Plan fragt „Sitzplan
            // entfernen“ zurück, Abbrechen lässt ihn. Der Wähler der
            // Dateizeilen ist ein modales Blatt — dort klickt der Prüfstand
            // nicht; der Weg ist derselbe wie in ⌘K (`kursdateiWaehlen`).
            await kurszelleProbe(speicher, fenster: fenster, klasse: klasse)
            ablegenProbe(speicher, fenster: fenster)
            Pruefstaende.abschliessenUndBeenden()
        }
    }

    /// Ablegen von außen auf eine Kachel (v88, AZ1; E904–E908, E913, E916). Datei und Link gehen über die Einstiege des
    /// Rasters — `draggingEntered`, `draggingUpdated`, `draggingExited`, `prepareForDragOperation`, `performDragOperation`,
    /// `concludeDragOperation`, `draggingEnded` — wie ein echtes Ziehen, nachdem AppKit das Ziel gewählt hat. Nachgebaut
    /// sind das Ziehen (`Ablageattrappe`) und die Zielwahl: Ziel ist die erste Ansicht unter dem Punkt, die einen Typ des
    /// Ziehens angemeldet hat. Die Zwischenablage hat die Form, die das Hilfsprogramm am 28.10.2026 gemessen hat (E917):
    /// der Finder je Datei `public.file-url` und `com.apple.finder.node` als Dateiverweis (`file:///.file/id=…`), Arten
    /// copy|link|generic|move|delete; Safari `public.url`, Titel, Text und Typen eines Dateiversprechens (hier verkürzt auf
    /// drei davon), Arten copy|link|generic|private; Mail eine fertige Datei als Pfad, Arten copy.
    /// Die Punkte kommen aus dem Layout des Rasters; aus den Rahmen der Ansichten gewählt, lagen sie am 28.10.2026, 19:47,
    /// neben dem Layout (unten in der Kachel, mitten in der leeren Zelle: keine Zelle). Ob der Zugriff aus der App Sandbox
    /// auf eine Datei außerhalb des Containers trägt, zeigt nur die Handprobe (AZ3). Eine Grundlinie geht voraus: ein
    /// Vorhaben verschoben, wie eine Kachel es zieht (Quelle die Kachel, Arten move|copy) — in eine leere Zelle und auf eine
    /// Kachel (Z-AZ1-05, Z-AZ1N-01). Jede Zeile trägt ✓ oder ✗; `runde.py` verlangt jede Marke genau einmal, alle grün.
    private static func ablegenProbe(_ speicher: Planungsspeicher, fenster: NSWindow) {
        let kopf = "KLICKTEST Ablegen auf eine Kachel:"
        func zeichen(_ gilt: Bool) -> String { gilt ? "✓" : "✗" }
        guard fenster.attachedSheet == nil, !speicher.blattVorDemSchauplatz else {
            print("\(kopf) ein Blatt steht vor dem Raster ✗")
            return
        }
        var gefunden: NSCollectionView?
        @MainActor func suchen(_ ansicht: NSView) {
            if gefunden == nil, let treffer = ansicht as? NSCollectionView, !treffer.isHiddenOrHasHiddenAncestor {
                gefunden = treffer
            }
            ansicht.subviews.forEach(suchen)
        }
        if let inhalt = fenster.contentView { suchen(inhalt) }
        // Aus dem sichtbaren Layout: der Rahmen der Zelle im Raster, geschnitten mit dem Sichtbaren. Die Kachel des Ziels
        // liegt ganz darin — sonst träfen „oben“ und „unten“ nicht ihre Hälften (Z-AZ1N-04).
        var kachel: Kachelansicht?
        var koerper: Zellenkoerper?
        var zielPfad: IndexPath?
        var kachelRahmen = NSRect.zero
        var zelleRahmen = NSRect.zero
        var leerPfad: IndexPath?
        var leerRahmen = NSRect.zero
        var kachelZu: [String: Kachelansicht] = [:]
        if let raster = gefunden {
            for pfad in raster.indexPathsForVisibleItems().sorted() {
                let rahmen = (raster.layoutAttributesForItem(at: pfad)?.frame ?? .zero).intersection(raster.visibleRect)
                guard rahmen.width > 20, rahmen.height > 20,
                      let zelle = (raster.item(at: pfad) as? Zellenelement)?.koerper else { continue }
                let kacheln = zelle.subviews.compactMap { $0 as? Kachelansicht }.filter { $0.stand != nil }
                for kandidat in kacheln { if let id = kandidat.stand?.vorhaben.id { kachelZu[id] = kandidat } }
                if kachel == nil, let ganz = kacheln.first(where: { kandidat in
                    let r = raster.convert(kandidat.bounds, from: kandidat)
                    return rahmen.contains(r) && r.height > 16
                }) {
                    (kachel, koerper, zielPfad, zelleRahmen) = (ganz, zelle, pfad, rahmen)
                    kachelRahmen = raster.convert(ganz.bounds, from: ganz)
                }
                if leerPfad == nil, kacheln.isEmpty { (leerPfad, leerRahmen) = (pfad, rahmen) }
            }
        }
        let ziel = kachel?.stand.flatMap { stand in speicher.planung?.eintraege.first { $0.id == stand.vorhaben.id } }
        let anderes = speicher.planung?.eintraege.first { $0.id != ziel?.id }
        // Jede verfehlte Bedingung beim Namen (G1-04, Z-AZ1-11).
        var fehlt: [String] = []
        if gefunden == nil { fehlt.append("kein Raster") }
        if ziel == nil { fehlt.append("keine Kachel ganz im Sichtbaren") }
        if leerPfad == nil { fehlt.append("keine sichtbare leere Zelle") }
        if anderes == nil { fehlt.append("kein zweites Vorhaben") }
        guard let raster = gefunden, let kachel, let koerper, let zielPfad, let leerPfad, let ziel, let anderes,
              speicher.planung != nil, let link = URL(string: "https://example.org/photosynthese") else {
            print("\(kopf) \(fehlt.isEmpty ? "keine Planung" : fehlt.joined(separator: "; ")) ✗")
            return
        }
        let datei = FileManager.default.temporaryDirectory.appending(component: "Ablageprobe-Arbeitsblatt.pdf")
        guard (try? Data("%PDF-1.4\n".utf8).write(to: datei)) != nil else {
            print("\(kopf) Probedatei nicht angelegt ✗")
            return
        }
        defer { try? FileManager.default.removeItem(at: datei) }
        // Über die Brücke nach Swift käme der Verweis als Pfad zurück — `perform` hält ihn als `file:///.file/id=…`.
        let verweis = ((datei as NSURL).perform(#selector(NSURL.fileReferenceURL))?.takeUnretainedValue() as? NSURL)?
            .absoluteString ?? ""
        let ablage = NSPasteboard(name: NSPasteboard.Name("org.3ducation.Unterrichtsplanung.Ablageprobe"))
        defer { ablage.releaseGlobally() }
        // Je Ziehen frische Einträge (ein Eintrag gehört höchstens einer Zwischenablage), in der gemessenen Form (E917).
        func mailEintrag() -> NSPasteboardItem {
            let eintrag = NSPasteboardItem()
            eintrag.setString(datei.absoluteString, forType: .fileURL)
            return eintrag
        }
        func finderEintrag() -> NSPasteboardItem {
            let eintrag = NSPasteboardItem()
            eintrag.setString(verweis, forType: .fileURL)
            eintrag.setString(verweis, forType: NSPasteboard.PasteboardType("com.apple.finder.node"))
            return eintrag
        }
        func safariEintrag() -> NSPasteboardItem {
            let eintrag = NSPasteboardItem()
            eintrag.setString(link.absoluteString, forType: .URL)
            eintrag.setString("Photosynthese", forType: NSPasteboard.PasteboardType("public.url-name"))
            eintrag.setString(link.absoluteString, forType: .string)
            eintrag.setData(Data(), forType: NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"))
            eintrag.setString("", forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-name"))
            eintrag.setString("com.apple.web-internet-location",
                              forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"))
            return eintrag
        }
        func kachelEintrag(_ id: String) -> NSPasteboardItem {
            let eintrag = NSPasteboardItem()
            if let nutzlast = try? JSONEncoder().encode(Vorhabenverweis(ids: [id])) {
                eintrag.setData(nutzlast, forType: NSPasteboard.PasteboardType(UTType.vorhabenverweis.identifier))
            }
            return eintrag
        }
        func belegen(_ eintraege: [NSPasteboardItem]) {
            ablage.clearContents()
            ablage.writeObjects(eintraege)
        }
        let finderArten: NSDragOperation = [.copy, .link, .generic, .move, .delete]
        let safariArten: NSDragOperation = [.copy, .link, .generic, .private]
        // Verglichen wird die ganze Planung, ohne den Stempel des letzten Sicherns — den setzt jedes Schreiben (Z-AZ1N-03).
        func gleich(_ a: Planung?, _ b: Planung?) -> Bool {
            guard var a, var b else { return a == nil && b == nil }
            a.geaendert = ""
            b.geaendert = ""
            return a == b
        }
        func ort(_ rahmen: NSRect, anteil: CGFloat) -> NSPoint {
            raster.convert(NSPoint(x: rahmen.midX, y: rahmen.minY + rahmen.height * anteil), to: nil)
        }
        func getroffen(_ punkt: NSPoint) -> NSView? { fenster.contentView?.superview?.hitTest(punkt) }
        // Wie AppKit: das Ziel ist die erste Ansicht unter dem Punkt, die einen Typ des Ziehens angemeldet hat (Z-AZ1N-07).
        func zielansicht(bei punkt: NSPoint) -> NSView? {
            let typen = Set(ablage.types ?? [])
            var ansicht = getroffen(punkt)
            while let jetzt = ansicht {
                if !typen.isDisjoint(with: jetzt.registeredDraggedTypes) { return jetzt }
                ansicht = jetzt.superview
            }
            return nil
        }
        // Unter dem Punkt heißt: Das Raster liegt dort in der Kette, und es sieht dort genau diese Zelle.
        func unter(_ punkt: NSPoint, _ pfad: IndexPath) -> Bool {
            var ansicht = getroffen(punkt)
            while let jetzt = ansicht, jetzt !== raster { ansicht = jetzt.superview }
            return ansicht != nil && raster.indexPathForItem(at: raster.convert(punkt, from: nil)) == pfad
        }
        // Was AppKit am Punkt sähe — nur bei ✗ in der Zeile: getroffene Ansichten, Zelle des Rasters (Abschnitt.Woche).
        func lage(_ punkt: NSPoint) -> String {
            var kette: [String] = []
            var ansicht = getroffen(punkt)
            while let jetzt = ansicht, kette.count < 4 {
                kette.append(String(describing: type(of: jetzt)))
                ansicht = jetzt.superview
            }
            let pfad = raster.indexPathForItem(at: raster.convert(punkt, from: nil))
            return " (getroffen: \(kette.isEmpty ? "nichts" : kette.joined(separator: " < ")); Raster: "
                + (pfad.map { "\($0.section).\($0.item)" } ?? "keine Zelle") + ")"
        }
        struct Ueberfahrt { let betreten: NSDragOperation; let bewegt: NSDragOperation; let erreicht: Bool; let grund: String }
        func ueberfahren(_ info: Ablageattrappe) -> Ueberfahrt {
            let ansicht = zielansicht(bei: info.draggingLocation)
            guard ansicht === raster else {
                let grund = ansicht.map { " (erreicht: \(String(describing: type(of: $0))) statt des Rasters)" }
                    ?? " (nicht erreicht: kein angemeldeter Typ auf der Ablage)"
                return Ueberfahrt(betreten: [], bewegt: [], erreicht: false, grund: grund)
            }
            return Ueberfahrt(betreten: raster.draggingEntered(info), bewegt: raster.draggingUpdated(info), erreicht: true,
                              grund: "")
        }
        func artenText(_ fahrt: Ueberfahrt) -> String {
            fahrt.erreicht ? " (Betreten \(fahrt.betreten.rawValue), Bewegen \(fahrt.bewegt.rawValue))" : fahrt.grund
        }
        func fallenlassen(_ info: Ablageattrappe) -> Bool {
            guard zielansicht(bei: info.draggingLocation) === raster else { return false }
            let getan = raster.prepareForDragOperation(info) && raster.performDragOperation(info)
            raster.concludeDragOperation(info)
            (raster as NSDraggingDestination).draggingEnded?(info)
            return getan
        }
        // Zurückgenommen wird nur nach genau einem neuen Schritt — dem eigenen (Z-AZ1-07, Z-AZ1N-09).
        func zuruecknehmen(_ neuerSchritt: Bool, davor: Planung?) -> Bool {
            guard neuerSchritt else { return false }
            speicher.widerrufen()
            return gleich(speicher.planung, davor)
        }

        // 1 · Grundlinie: „anderes“, gezogen wie von seiner Kachel — in die leere Zelle und auf die obere Hälfte der Kachel
        // des Ziels, dort über `einfuegestelle` vor das Ziel. Heute schon grün; nach AZ3 hält sie das Verschieben.
        func verschieben(_ wohin: String, pfad: IndexPath, punkt: NSPoint, versetzt pruefen: () -> Bool) {
            // Gezogen wird von der Kachel von „anderes“ — nie ersatzweise von der Kachel des Ziels (Z-AZ1N2-04).
            guard let quelle = kachelZu[anderes.id] else {
                print("\(kopf) Grundlinie \(wohin) — Kachel von „\(anderes.anzeigeTitel)“ nicht sichtbar ✗")
                return
            }
            belegen([kachelEintrag(anderes.id)])
            let davor = speicher.planung
            let schritte = speicher.verlauf.zurueck.count
            let info = Ablageattrappe(fenster: fenster, ort: punkt, ablage: ablage, arten: [.move, .copy], quelle: quelle)
            let darunter = unter(punkt, pfad)
            let fahrt = ueberfahren(info)
            let verschiebt = fahrt.betreten == .move && fahrt.bewegt == .move
            let abgelegt = fallenlassen(info)
            let versetzt = pruefen()
            let neuerSchritt = speicher.verlauf.zurueck.count == schritte + 1
            let hergestellt = zuruecknehmen(neuerSchritt, davor: davor)
            print("\(kopf) Grundlinie \(wohin) — „\(anderes.anzeigeTitel)“: Zelle unter dem Punkt \(zeichen(darunter))"
                  + "\(darunter ? "" : lage(punkt)), verschieben \(zeichen(verschiebt))\(verschiebt ? "" : artenText(fahrt)), "
                  + "abgelegt \(zeichen(abgelegt)), versetzt \(zeichen(versetzt)), ein neuer Schritt \(zeichen(neuerSchritt)), "
                  + "Widerrufen am Speicher stellt die Planung her \(zeichen(hergestellt))")
        }
        verschieben("in die leere Zelle", pfad: leerPfad, punkt: ort(leerRahmen, anteil: 0.5)) {
            let nachher = speicher.planung?.eintraege.first { $0.id == anderes.id }
            return nachher?.woche == leerPfad.item
                && nachher.map { $0.woche != anderes.woche || $0.klasseId != anderes.klasseId } == true
        }
        // „Direkt vor dem Ziel“ — nachher ja, vorher nein: sonst ginge ein Nichtzug grün durch (Z-AZ1N2-04).
        func direktVorDemZiel(_ planung: Planung?) -> Bool {
            let zelle = planung?.vorhaben(klasse: ziel.klasseId, woche: ziel.woche).map(\.id) ?? []
            guard let stelle = zelle.firstIndex(of: anderes.id) else { return false }
            return zelle.indices.contains(stelle + 1) && zelle[stelle + 1] == ziel.id
        }
        let vorDemZielSchon = direktVorDemZiel(speicher.planung)
        verschieben("auf die Kachel", pfad: zielPfad, punkt: ort(kachelRahmen, anteil: 0.25)) {
            !vorDemZielSchon && direktVorDemZiel(speicher.planung)
        }

        // 2 · Anmeldung und Lage: Datei, Link und Vorhaben angemeldet, kein Dateiversprechen (E913, Z-AZ1-10); zwei
        // Vorhaben angewählt — abgelegt wird trotzdem nur auf die Kachel unter dem Punkt (E906, Z-AZ1-03).
        let typen = Set(raster.registeredDraggedTypes.map(\.rawValue))
        let angemeldet = typen.isSuperset(of: [NSPasteboard.PasteboardType.fileURL.rawValue,
                                               NSPasteboard.PasteboardType.URL.rawValue, UTType.vorhabenverweis.identifier])
            && typen.isDisjoint(with: NSFilePromiseReceiver.readableDraggedTypes)
        speicher.anwaehlen(vorhaben: anderes.id)
        speicher.anwaehlen(vorhaben: ziel.id, erweitern: true)
        let zweiAngewaehlt = speicher.auswahl == [anderes.id, ziel.id]
        let wieFinder = verweis.hasPrefix("file:///.file/id=")
        // Am echten Bündel: Die Datei im eigenen Container gilt nicht als fremd (Z-AZ3-04).
        let eigeneNichtFremd = Planungsspeicher.fremderAblageort(datei.path) == nil
        print("\(kopf) Typen angemeldet (Datei, Link, Vorhaben; kein Dateiversprechen) \(zeichen(angemeldet)), "
              + "zwei Vorhaben angewählt \(zeichen(zweiAngewaehlt)), Dateiverweis wie aus dem Finder \(zeichen(wieFinder)), "
              + "eigene Datei nicht fremd \(zeichen(eigeneNichtFremd))")

        // 3 · Ablegen: oben Datei und Link (E905), unten nur eine Datei wie aus dem Finder, mittig nur ein Link wie aus
        // Safari (Z-AZ1N-02). Die Hälften so, wie `einfuegestelle` die Kachel teilt (Z-AZ1N-04).
        // Jede Art auch in der unteren Hälfte (Z-AZ1N2-03); dazu eine Datei in der Form aus Mail (Z-AZ1N2-05).
        let faelle: [(name: String, anteil: CGFloat, eintraege: () -> [NSPasteboardItem], datei: Bool, link: Bool,
                      arten: NSDragOperation, schritt: String)] = [
            ("oben, Datei und Link", 0.25, { [finderEintrag(), safariEintrag()] }, true, true, .every, "Material ablegen"),
            ("unten, nur Datei", 0.75, { [finderEintrag()] }, true, false, finderArten, "Material ablegen"),
            ("unten, nur Link", 0.75, { [safariEintrag()] }, false, true, safariArten, "Link ablegen"),  // E916
            ("oben, Datei wie aus Mail", 0.25, { [mailEintrag()] }, true, false, .copy, "Material ablegen"),
        ]
        for fall in faelle {
            belegen(fall.eintraege())
            let davor = speicher.planung
            let schritte = speicher.verlauf.zurueck.count
            let punkt = ort(kachelRahmen, anteil: fall.anteil)
            let imKoerper = koerper.convert(punkt, from: nil)
            let haelfte = fall.anteil < 0.5 ? imKoerper.y < kachel.frame.midY
                : fall.anteil > 0.5 ? imKoerper.y > kachel.frame.midY : true
            let darunter = unter(punkt, zielPfad) && kachel.frame.contains(imKoerper) && haelfte
            let info = Ablageattrappe(fenster: fenster, ort: punkt, ablage: ablage, arten: fall.arten, quelle: nil)
            let fahrt = ueberfahren(info)
            let nimmtAn = fahrt.betreten == .copy && fahrt.bewegt == .copy
            let hervorgehoben = kachel.ablageziel
            // Für die Sichtprüfung (AZ3): die hervorgehobene Kachel hell und dunkel — nur mit ABLAGEBILD.
            if fall.name == "oben, Datei und Link", let bild = ProcessInfo.processInfo.environment["ABLAGEBILD"] {
                fenster.displayIfNeeded()
                Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: bild + "-hell.png"))
                let bisher = fenster.appearance
                fenster.appearance = NSAppearance(named: .darkAqua)
                fenster.contentView?.needsDisplay = true
                fenster.displayIfNeeded()
                Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: bild + "-dunkel.png"))
                fenster.appearance = bisher
                fenster.displayIfNeeded()
            }
            let abgelegt = fallenlassen(info)
            let zurueckgenommen = !kachel.ablageziel
            // Die letzte Meldung ist die Bestätigung, ohne fremden Ort (E923) — nicht „seit davor“: Meldungen schließen
            // sich nach ihrer Zeit, die Liste schrumpft (Z-AZ3N-02).
            let letzte = speicher.meldungen.last
            let ohneFremdWarnung = letzte.map { $0.art == .hinweis && $0.text.hasPrefix("„\(ziel.anzeigeTitel)“")
                && !$0.text.contains("dort verschwinden") } == true
            // Genau das Neue am Ziel, und sonst nichts — am Ziel und in der ganzen Planung (Z-AZ1-02, Z-AZ1N-03).
            let nachher = speicher.planung
            // Verglichen mit dem Ziel unmittelbar davor, nicht vom Anfang der Probe (Z-AZ1N2-02).
            let zielDavor = davor?.eintraege.first { $0.id == ziel.id } ?? ziel
            let neu = nachher?.eintraege.first { $0.id == ziel.id }
            let neueMaterialien = neu?.materialien.filter { m in !zielDavor.materialien.contains { $0.pfad == m.pfad } } ?? []
            let neueLinks = neu?.links.filter { l in !zielDavor.links.contains { $0.adresse == l.adresse } } ?? []
            var rest = neu
            rest?.materialien.removeAll { m in neueMaterialien.contains { $0.id == m.id } }
            rest?.links.removeAll { l in neueLinks.contains { $0.id == l.id } }
            var ohneZiel = nachher
            if let stelle = ohneZiel?.eintraege.firstIndex(where: { $0.id == ziel.id }) {
                ohneZiel?.eintraege[stelle] = zielDavor
            }
            let genau = neueMaterialien.count == (fall.datei ? 1 : 0) && neueLinks.count == (fall.link ? 1 : 0)
                && neueMaterialien.allSatisfy { $0.pfad.hasSuffix("/" + datei.lastPathComponent) }
                && neueLinks.allSatisfy { $0.adresse == link.absoluteString }
                && rest == zielDavor && gleich(ohneZiel, davor)
            let neuerSchritt = speicher.verlauf.zurueck.count == schritte + 1
            let benannt = speicher.widerrufenTitel == "Widerrufen: \(fall.schritt)"  // die Namen nach E907, E916, wörtlich
            // Eine Meldung, kein Fenster: Die Datei der Probe liegt im eigenen Container, eine Warnung nach E918 käme nicht
            // — und ein Fenster hielte den Lauf an (Z-AZ1N2-05).
            let ohneFenster = Pruefstaende.alertfenster() == nil
            let hergestellt = zuruecknehmen(neuerSchritt, davor: davor)
            print("\(kopf) „\(ziel.anzeigeTitel)“ \(fall.name): Kachel unter dem Punkt \(zeichen(darunter))"
                  + "\(darunter ? "" : lage(punkt)), nimmt an (+) \(zeichen(nimmtAn))\(nimmtAn ? "" : artenText(fahrt)), "
                  + "hervorgehoben \(zeichen(hervorgehoben)), abgelegt \(zeichen(abgelegt)), danach zurückgenommen "
                  + "\(zeichen(zurueckgenommen)), keine Warnung zu fremden Orten \(zeichen(ohneFremdWarnung)), "
                  + "genau das Neue und nur an diesem Vorhaben \(zeichen(genau)), "
                  + "ein neuer Schritt \(zeichen(neuerSchritt)), „\(fall.schritt)“ \(zeichen(benannt)), "
                  + "kein Fenster \(zeichen(ohneFenster)), Widerrufen am Speicher stellt die Planung her \(zeichen(hergestellt))")
        }

        // 4 · Abgewiesen (E904, E908): kein „+“, und die Planung bleibt, wie sie unmittelbar davor war (Z-AZ1N-09).
        func weistAb(_ punkt: NSPoint, _ eintraege: [NSPasteboardItem], arten: NSDragOperation) -> (gilt: Bool, grund: String) {
            belegen(eintraege)
            let davor = speicher.planung
            let info = Ablageattrappe(fenster: fenster, ort: punkt, ablage: ablage, arten: arten, quelle: nil)
            let fahrt = ueberfahren(info)
            if fahrt.erreicht { raster.draggingExited(info) }
            // Abgewiesen heißt: Das Raster sagt nein, oder es gibt gar kein Ziel. Nimmt eine andere Ansicht an, sagt die Probe
            // nichts über die Abweisung — dann ✗ mit dem Namen (Z-AZ1N2-01).
            let ab = fahrt.erreicht ? fahrt.betreten.isEmpty && fahrt.bewegt.isEmpty : zielansicht(bei: punkt) == nil
            let geblieben = gleich(speicher.planung, davor)
            return (ab && geblieben, (ab ? "" : artenText(fahrt)) + (geblieben ? "" : " (Planung verändert)"))
        }
        // Das Blatt steht hier nur im Speicher — angehängt wird es erst im nächsten Ablaufring. Die Abweisung hängt also
        // an `blattVorDemSchauplatz`, nicht am Fenster (Z-AZ1N-06).
        speicher.vorhabenOeffnen(id: ziel.id)
        let blattOffen = speicher.blattVorDemSchauplatz
        let angehaengt = fenster.attachedSheet != nil
        let blatt = weistAb(ort(kachelRahmen, anteil: 0.5), [finderEintrag(), safariEintrag()], arten: .every)
        speicher.vorhabenDialog = nil
        // Im Fuß der Zelle des Ziels, wo keine Kachel liegt — dieselbe Zelle, nur nicht auf einer Kachel.
        let fussImRaster = NSPoint(x: zelleRahmen.midX, y: raster.isFlipped ? zelleRahmen.maxY - 6 : zelleRahmen.minY + 6)
        let fuss = raster.convert(fussImRaster, to: nil)
        let kachelnDort = koerper.subviews.compactMap { $0 as? Kachelansicht }.map { raster.convert($0.bounds, from: $0) }
        let frei = unter(fuss, zielPfad) && !kachelnDort.contains { $0.contains(fussImRaster) }
        let fussDatei = weistAb(fuss, [finderEintrag()], arten: finderArten)
        let fussLink = weistAb(fuss, [safariEintrag()], arten: safariArten)
        let leerpunkt = ort(leerRahmen, anteil: 0.5)
        let leerUnter = unter(leerpunkt, leerPfad)
        let leerDatei = weistAb(leerpunkt, [finderEintrag()], arten: finderArten)
        let leerLink = weistAb(leerpunkt, [safariEintrag()], arten: safariArten)
        // Verlassen räumt auf: über der Kachel hervorgehoben, nach dem Verlassen nicht mehr (E924, Z-AZ3-01).
        belegen([finderEintrag()])
        let verlassen = Ablageattrappe(fenster: fenster, ort: ort(kachelRahmen, anteil: 0.5), ablage: ablage,
                                       arten: finderArten, quelle: nil)
        _ = ueberfahren(verlassen)
        let warHervorgehoben = kachel.ablageziel
        raster.draggingExited(verlassen)
        let raeumtAuf = warHervorgehoben && !kachel.ablageziel
        let beiBlatt = blattOffen && blatt.gilt
        let blattGrund = beiBlatt ? "" : blattOffen ? blatt.grund + (angehaengt ? " (Blatt angehängt)" : "") : " (kein Blatt)"
        let fussGrund = frei ? fussDatei.grund : lage(fuss)
        let leerGrund = leerUnter ? leerDatei.grund : lage(leerpunkt)
        let teilBlatt = "abgewiesen bei offenem Vorhaben-Blatt \(zeichen(beiBlatt))\(blattGrund)"
        let teilFuss = "an der freien Stelle der belegten Zelle mit Datei \(zeichen(frei && fussDatei.gilt))\(fussGrund), "
            + "mit Link \(zeichen(frei && fussLink.gilt))\(fussLink.grund)"
        let teilLeer = "in der leeren Zelle mit Datei \(zeichen(leerUnter && leerDatei.gilt))\(leerGrund), "
            + "mit Link \(zeichen(leerUnter && leerLink.gilt))\(leerLink.grund)"
        let teilVerlassen = "Verlassen räumt auf \(zeichen(raeumtAuf))" + (warHervorgehoben ? "" : " (nicht hervorgehoben)")
        print("\(kopf) \(teilBlatt), \(teilFuss), \(teilLeer); \(teilVerlassen)")

        // 5 · Aufräumen und Art (Z-AZ3N-01): Verlassen und Ende räumen auch beim Verschieben auf, das Ende auch ohne
        // Verlassen — auf diesem Weg kommt ⎋, falls AppKit dabei kein Verlassen meldet (E924). Die Art folgt der Quelle:
        // ohne „kopieren“ allgemein oder verknüpfen; wer nur verschieben lässt, bekommt kein „+“ (Z-AZ3-06).
        let davorTeil5 = speicher.planung
        func zielring() -> Bool { raster.visibleItems().contains { ($0 as? Zellenelement)?.koerper.zielt == true } }
        func verschiebung() -> Ablageattrappe {
            belegen([kachelEintrag(anderes.id)])
            return Ablageattrappe(fenster: fenster, ort: ort(leerRahmen, anteil: 0.5), ablage: ablage,
                                  arten: [.move, .copy], quelle: kachelZu[anderes.id])
        }
        func aufgeraeumt(_ vorher: Bool, _ nachher: Bool) -> String {
            zeichen(vorher && !nachher) + (vorher ? "" : " (vorher nicht hervorgehoben)")
        }
        let wegVerlassen = verschiebung()
        _ = ueberfahren(wegVerlassen)
        let ringVorVerlassen = zielring()
        raster.draggingExited(wegVerlassen)
        let verschiebenVerlassen = aufgeraeumt(ringVorVerlassen, zielring())
        let wegEnde = verschiebung()
        _ = ueberfahren(wegEnde)
        let ringVorEnde = zielring()
        (raster as NSDraggingDestination).draggingEnded?(wegEnde)
        let verschiebenEnde = aufgeraeumt(ringVorEnde, zielring())
        belegen([finderEintrag()])
        let ablageEnde = Ablageattrappe(fenster: fenster, ort: ort(kachelRahmen, anteil: 0.5), ablage: ablage,
                                        arten: finderArten, quelle: nil)
        _ = ueberfahren(ablageEnde)
        let kachelVorEnde = kachel.ablageziel
        (raster as NSDraggingDestination).draggingEnded?(ablageEnde)
        let ablegenEnde = aufgeraeumt(kachelVorEnde, kachel.ablageziel)
        func art(_ arten: NSDragOperation, _ soll: NSDragOperation) -> String {
            belegen([finderEintrag()])
            let info = Ablageattrappe(fenster: fenster, ort: ort(kachelRahmen, anteil: 0.5), ablage: ablage, arten: arten,
                                      quelle: nil)
            let fahrt = ueberfahren(info)
            if fahrt.erreicht { raster.draggingExited(info) }
            let gilt = fahrt.erreicht && fahrt.betreten == soll && fahrt.bewegt == soll
            return zeichen(gilt) + (gilt ? "" : artenText(fahrt))
        }
        let allgemein = art([.generic, .link], .generic)
        let verknuepfen = art([.link], .link)
        let nurVerschieben = art([.move], [])
        let geblieben = gleich(speicher.planung, davorTeil5)
        print("\(kopf) Aufräumen und Art — beim Verschieben: nach dem Verlassen \(verschiebenVerlassen), am Ende ohne "
              + "Verlassen \(verschiebenEnde); beim Ablegen am Ende ohne Verlassen \(ablegenEnde); Art ohne „kopieren“: "
              + "allgemein \(allgemein), verknüpfen \(verknuepfen), nur verschieben ohne „+“ \(nurVerschieben); "
              + "Planung unverändert \(zeichen(geblieben))")
    }

    /// Liest, schaltet und hält die Regel „entweder Prüfung oder Korrektur“ —
    /// danach steht die Planung wie vorher.
    private static func korrekturProbe(_ speicher: Planungsspeicher) {
        guard let planung = speicher.planung else { return }
        func stand(_ id: String) -> Vorhaben? { speicher.planung?.eintraege.first { $0.id == id } }
        let gelesen = planung.eintraege.filter(\.korrektur)
        if let eine = gelesen.first {
            print("KLICKTEST Korrektur aus der Datei: \(gelesen.count) gelesen ✓")
            speicher.pruefungUmschalten(eine.id)
            let bleibt = stand(eine.id)?.korrektur == true && stand(eine.id)?.pruefung == false
            print("KLICKTEST an der Korrektur wird keine Prüfung \(bleibt ? "✓" : "✗")")
        } else {
            print("KLICKTEST Korrektur aus der Datei: keine in dieser Planung — übersprungen")
        }
        if let frei = planung.eintraege.first(where: { !$0.korrektur && !$0.pruefung }) {
            speicher.korrekturUmschalten(frei.id)
            let an = stand(frei.id)?.korrektur == true
            speicher.korrekturUmschalten(frei.id)
            let aus = stand(frei.id)?.korrektur == false
            print("KLICKTEST Korrektur an \(an ? "✓" : "✗"), aus \(aus ? "✓" : "✗")")
        }
    }

    /// Bis `gilt` zutrifft, höchstens `takte` × 150 ms — die eine Warteschleife der Kurszelle (AX7e: aus der Probe „+ Sitzplan“
    /// herausgelöst, auch für die Leistungsdokumentation).
    private static func bisGilt(_ takte: Int, _ gilt: @MainActor () -> Bool) async {
        for _ in 0..<takte where !gilt() {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    /// Klick am Fenster: Ereignisse einreihen, nicht senden — wie `--auswahltest`.
    private static func klicken(_ fenster: NSWindow, _ punkt: NSPoint) {
        for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let ereignis = NSEvent.mouseEvent(
                with: art, location: punkt, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: fenster.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0)
            else { continue }
            NSApp.postEvent(ereignis, atStart: false)
        }
    }

    private static func kurszelleProbe(_ speicher: Planungsspeicher, fenster: NSWindow,
                                       klasse: Klasse) async {
        var buehne: Rasterbuehne?
        @MainActor func suchen(_ ansicht: NSView) {
            if let treffer = ansicht as? Rasterbuehne { buehne = treffer }
            ansicht.subviews.forEach(suchen)
        }
        if let inhalt = fenster.contentView { suchen(inhalt) }
        guard let buehne else {
            print("KLICKTEST Kurszelle: keine Rasterbühne ✗")
            return
        }
        // AX7e: die Leistungsdokumentation schon hier hinterlegt — bis zu ihrem Kontextmenü unten hat die Zelle sie längst
        // gezeichnet. Sie hängt nicht am Sitzplan: Fällt dessen Teil aus, läuft sie trotzdem (Z-AX7-08).
        let ldVorher = speicher.planung?.klasse(klasse.id)?.leistungsdokumentation ?? ""
        let ldPfad = "Noten/\(klasse.name)-Leistungen.numbers"
        speicher.kursdateiSetzen(klasse: klasse.id, art: .leistungsdokumentation, pfad: ldPfad)
        NSApp.activate(ignoringOtherApps: true)
        fenster.makeKeyAndOrderFront(nil)
        speicher.sprung = Rastersprung(woche: 0)
        await sprungAbwarten(fenster)
        if speicher.sitzplaene.schreibbar, speicher.sitzplan(fuer: klasse.id) == nil {
            // Die dritte Verwaltungszeile („+ Sitzplan“) liegt über der vierten, untersten („+ Leistungsdokumentation“,
            // AX6, E662): Polster 12, Zeile 21 (`Zellenmass`); die Bühne ist gekippt, y läuft von oben.
            let kopf = Zellenmass.kopfhoehe(klasse)
            let punkt = buehne.convert(
                NSPoint(x: 14 + 24,
                        y: Masse.wochenkopfHoehe + kopf - 12 - Zellenmass.hoeheVerwaltungszeile * 1.5),
                to: nil)
            klicken(fenster, punkt)
            await bisGilt(12) { speicher.offenerDialog == .sitzplan }
            let editor = speicher.offenerDialog == .sitzplan && speicher.sitzplanKlasse == klasse.id
            print("KLICKTEST Kurszelle: Klick auf „+ Sitzplan“ öffnet den Editor "
                  + (editor ? "✓" : "✗ (Dialog \(speicher.offenerDialog?.rawValue ?? "—"))"))
            if speicher.offenerDialog != nil {
                speicher.alleDialogeSchliessen()
                await Planungsspeicher.blaetterAbloesenAbwarten()
            }
            speicher.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse.id,
                                                           namen: Sitzplanprobe.beispielnamen))
            fenster.contentView?.layoutSubtreeIfNeeded()
            fenster.displayIfNeeded()
            speicher.sitzplanEntfernen(klasse: klasse.id, ort: .hauptansicht)
            let gefragt = speicher.rueckfrage?.ort == .hauptansicht
            // Wie von Hand, nicht im Programm (B82, Z-AS1-12).
            if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) {
                print("KLICKTEST Kurszelle: ✗ Knopf „\(fehlt)“ im Alert gefunden")
            }
            for _ in 0..<16 where Pruefstaende.alertfenster() != nil { try? await Task.sleep(for: .milliseconds(125)) }
            let bleibt = speicher.sitzplan(fuer: klasse.id) != nil
            print("KLICKTEST Kurszelle: „Sitzplan entfernen“ fragt zurück \(gefragt ? "✓" : "✗"), "
                  + "Abbrechen lässt den Plan \(bleibt ? "✓" : "✗")")
            speicher.sitzplaene.setzen(nil, fuer: klasse.id)
        } else {
            print("KLICKTEST Kurszelle: „+ Sitzplan“ übersprungen — Sitzpläne "
                  + (speicher.sitzplaene.schreibbar ? "mit Plan für „\(klasse.name)“" : "nicht schreibbar"))
        }
        await leistungsdokumentationProbe(speicher, fenster: fenster, buehne: buehne, klasse: klasse, pfad: ldPfad)
        // Der Wert wie vor der Probe — gesetzt, nicht widerrufen: Dazwischen liegen Schritte des Sitzplans. Leer heißt
        // entfernen, derselbe Weg wie „Verweis entfernen“ (`pfad: nil`, Z-AX7-08).
        if speicher.planung?.klasse(klasse.id)?.leistungsdokumentation != ldVorher {
            speicher.kursdateiSetzen(klasse: klasse.id, art: .leistungsdokumentation, pfad: ldVorher.isEmpty ? nil : ldVorher)
        }
        let wieVorher = speicher.planung?.klasse(klasse.id)?.leistungsdokumentation == ldVorher
        print("KLICKTEST Kurszelle: Leistungsdokumentation wie vor der Probe " + (wieVorher ? "✓" : "✗"))
    }

    /// AX7e (v86; AX6, E662): eine gesetzte Leistungsdokumentation in der vierten, untersten Verwaltungszeile. Ein gebauter
    /// Rechtsklick öffnet das Kontextmenü von SwiftUI nicht (am Lauf gesehen, 24.10.) — gefragt wird die Ansicht unter dem
    /// Punkt nach ihrem Menü (`menu(for:)`), die Einträge gelesen, „Verweis entfernen“ über seine Handlung gewählt (Muster
    /// „über den Eintrag“ wie in der Widerrufprobe): ein Schritt „Leistungsdokumentation entfernen“, Widerrufen am Speicher
    /// bringt den Verweis. Der Wähler hinter „Andere Datei wählen …“ ist modal und bleibt ungeklickt. Eine Datei braucht es
    /// nicht: hinterlegt ist nur der Verweis. Den Rechtsklick selbst prüft die Hand.
    private static func leistungsdokumentationProbe(_ speicher: Planungsspeicher, fenster: NSWindow, buehne: Rasterbuehne,
                                                    klasse: Klasse, pfad: String) async {
        guard speicher.planung?.klasse(klasse.id)?.leistungsdokumentation.isEmpty == false else {
            print("KLICKTEST Kurszelle: Leistungsdokumentation hinterlegt ✗")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        fenster.makeKeyAndOrderFront(nil)
        let kopf = Zellenmass.kopfhoehe(klasse)
        let punkt = buehne.convert(
            NSPoint(x: 14 + 24, y: Masse.wochenkopfHoehe + kopf - 12 - Zellenmass.hoeheVerwaltungszeile * 0.5), to: nil)
        let schritte = speicher.verlauf.zurueck.count
        var titel: [String] = []
        if let ansicht = fenster.contentView?.superview?.hitTest(punkt), let ereignis = NSEvent.mouseEvent(
            with: .rightMouseDown, location: punkt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: fenster.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
           let menue = ansicht.menu(for: ereignis) {
            menue.update()
            titel = menue.items.map(\.title).filter { !$0.isEmpty }
            if let stelle = menue.items.firstIndex(where: { $0.title == "Verweis entfernen" }) {
                menue.performActionForItem(at: stelle)
            }
        }
        await bisGilt(20) { speicher.verlauf.naechsterName == Schrittname.leistungsdokumentationEntfernen }
        let erwartet = ["Öffnen", "Im Finder zeigen", "Vollständigen Pfad kopieren", "Andere Datei wählen …", "Verweis entfernen"]
        let entfernt = speicher.planung?.klasse(klasse.id)?.leistungsdokumentation == ""
            && speicher.verlauf.zurueck.count == schritte + 1
            && speicher.verlauf.naechsterName == Schrittname.leistungsdokumentationEntfernen
        let darunter = fenster.contentView?.superview?.hitTest(punkt).map { String(describing: type(of: $0)) } ?? "nichts"
        print("KLICKTEST Kurszelle: Kontextmenü der Leistungsdokumentation (über `menu(for:)`) — "
              + "\(titel.joined(separator: " · ")) " + (titel == erwartet ? "✓" : "✗ (unter dem Punkt: \(darunter))"))
        print("KLICKTEST Kurszelle: „Verweis entfernen“ ist ein Schritt „\(Schrittname.leistungsdokumentationEntfernen)“ "
              + (entfernt ? "✓" : "✗"))
        if entfernt {
            speicher.widerrufen()
            let zurueck = speicher.planung?.klasse(klasse.id)?.leistungsdokumentation == Pfade.ausDemSystem(pfad)
            print("KLICKTEST Kurszelle: Widerrufen am Speicher bringt den Verweis \(zurueck ? "✓" : "✗")")
        }
    }

    /// `--auswahltest`: klickt wirklich ins Raster, auch mit ⌘ und ⇧ — ob eine
    /// Geste beim richtigen Empfänger ankommt, zeigt nur ein echtes Ereignis.
    static func auswahltestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let planung = speicher.planung else {
                print("AUSWAHLTEST ✗ kein Fenster")
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }
            let breite = CGFloat(speicher.spaltenbreite)
            guard planung.klassen.count >= 3 else {
                print("AUSWAHLTEST ✗ zu wenige Klassen/Kurse")
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }

            @MainActor func klicken(_ punkt: NSPoint, _ tasten: NSEvent.ModifierFlags) {
                for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let ereignis = NSEvent.mouseEvent(
                        with: art, location: punkt, modifierFlags: tasten,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: fenster.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0)
                    else { continue }
                    // Einreihen: `sendEvent` überspränge die Tastenstand-Beobachter.
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }

            // Ein Klick ins nicht aktive Fenster aktiviert es nur und wird verschluckt.
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            fenster.setContentSize(NSSize(width: 1800, height: 1000))
            // An den linken Rand zurück — die Klickpunkte sind ausgemessen.
            speicher.sprung = Rastersprung(woche: 0)
            await sprungAbwarten(fenster)

            let inhalt = fenster.contentView!
            @MainActor func punkt(woche: Int) -> NSPoint {
                NSPoint(x: Masse.spalteKlasse + (CGFloat(woche) + 0.5) * breite,
                        y: inhalt.frame.maxY - 130)
            }

            var bericht: [String] = []
            @MainActor func festhalten(_ was: String, _ erwartet: [String]) async {
                // 700 ms Abstand: Dichter aufeinander wertet AppKit als Doppelklick.
                try? await Task.sleep(for: .milliseconds(700))
                let ist = speicher.auswahl.sorted()
                let dialog = speicher.vorhabenDialog != nil ? " (Dialog offen!)" : ""
                bericht.append("\(was): [\(ist.joined(separator: ", "))]"
                               + (ist == erwartet.sorted() ? " ✓" : " ✗ erwartet ["
                                  + erwartet.sorted().joined(separator: ", ") + "]") + dialog)
                speicher.vorhabenDialog = nil
            }

            klicken(punkt(woche: 0), [])
            await festhalten("einfacher Klick", ["e0-0"])

            klicken(punkt(woche: 2), [.command])
            await festhalten("⌘ nimmt dazu", ["e0-0", "e0-2"])

            klicken(punkt(woche: 2), [.command])
            await festhalten("⌘ nimmt wieder weg", ["e0-0"])

            klicken(punkt(woche: 0), [])
            await festhalten("einfacher Klick setzt zurück", ["e0-0"])

            klicken(punkt(woche: 4), [.shift])
            await festhalten("⇧ nimmt die Spanne", ["e0-0", "e0-2", "e0-4"])

            print("AUSWAHLTEST\n  " + bericht.joined(separator: "\n  "))
            Pruefstaende.abschliessenUndBeenden()
        }
    }

    /// `--ziehtest`: Beim Fallenlassen kommt der Zeigerort in
    /// Fensterkoordinaten an (`NSDraggingInfo.draggingLocation`), gebraucht wird
    /// er in Zellenkoordinaten — ob die Umrechnung am gerollten Raster stimmt,
    /// zeigt nur das laufende Fenster.
    static func ziehtestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let planung = speicher.planung, let kurs = planung.klassen.first else {
                print("ZIEHTEST ✗ kein Fenster / keine Planung")
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            fenster.setContentSize(NSSize(width: 1800, height: 1000))
            speicher.sprung = Rastersprung(woche: 0)
            await sprungAbwarten(fenster)

            var gefunden: Zellenkoerper?
            @MainActor func suchen(_ ansicht: NSView) {
                if let zelle = ansicht as? Zellenkoerper, zelle.zeile == 0, zelle.woche == 0 {
                    gefunden = zelle
                }
                ansicht.subviews.forEach(suchen)
            }
            if let inhalt = fenster.contentView { suchen(inhalt) }
            let kacheln = gefunden?.subviews.compactMap { $0 as? Kachelansicht } ?? []
            guard let zelle = gefunden, kacheln.count >= 2 else {
                print("ZIEHTEST ✗ braucht wenigstens zwei Kacheln in der ersten Zelle")
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }

            // Genau der Weg, den `acceptDrop` geht.
            @MainActor func stelleBei(_ y: CGFloat) -> String {
                let imFenster = kacheln[0].convert(NSPoint(x: 10, y: y), to: nil)
                return zelle.einfuegestelle(bei: zelle.convert(imFenster, from: nil)).vorId
                    ?? "ans Ende"
            }
            let vorher = planung.vorhaben(klasse: kurs.id, woche: 0).map(\.id)
            let oben = stelleBei(2)
            let unten = stelleBei(kacheln[0].bounds.height - 2)

            guard let letztes = planung.vorhaben(klasse: kurs.id, woche: 0).last else { return }
            speicher.versetzen([letztes], nach: Zellenort(klasse: kurs.id, woche: 0),
                               verschieben: true, vor: vorher.first)
            let nachher = (speicher.planung?.vorhaben(klasse: kurs.id, woche: 0) ?? []).map(\.id)

            if let pfad = ProcessInfo.processInfo.environment["ZIEHBILD"] {
                zelle.zielSetzen(true, marke: 1)
                zelle.displayIfNeeded()
                try? await Task.sleep(for: .milliseconds(300))
                Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: pfad))
                zelle.zielSetzen(false)
            }

            print("ZIEHTEST")
            print("  über der Mitte der ersten Kachel → vor \(oben)"
                  + (oben == vorher.first ? "  ✓" : "  ✗ erwartet \(vorher[0])"))
            print("  unter ihrer Mitte → vor \(unten)"
                  + (unten == vorher[1] ? "  ✓" : "  ✗ erwartet \(vorher[1])"))
            print("  vorher:  " + vorher.joined(separator: ", "))
            print("  nachher: " + nachher.joined(separator: ", "))
            Pruefstaende.abschliessenUndBeenden()
        }
    }

    /// `--mischtest`: Der Speicher schließt aus, dass Zelle und Vorhaben
    /// zugleich angewählt sind — ob am Bildschirm trotzdem zwei Rahmen stehen
    /// (der Tastaturfokus zeichnet einen eigenen), zeigt nur das Fenster.
    static func mischtestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  speicher.planung != nil else {
                print("MISCHTEST ✗ kein Fenster — \(NSApp.windows.count) Fenster, "
                      + "Planung \(speicher.planung == nil ? "fehlt" : "da")")
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }
            let breite = CGFloat(speicher.spaltenbreite)
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            fenster.setContentSize(NSSize(width: 1800, height: 1000))
            speicher.sprung = Rastersprung(woche: 0)
            await sprungAbwarten(fenster)

            let inhalt = fenster.contentView!
            @MainActor func punkt(woche: Int) -> NSPoint {
                NSPoint(x: Masse.spalteKlasse + (CGFloat(woche) + 0.5) * breite,
                        y: inhalt.frame.maxY - 130)
            }
            @MainActor func klicken(_ punkt: NSPoint) {
                for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let ereignis = NSEvent.mouseEvent(
                        with: art, location: punkt, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: fenster.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0)
                    else { continue }
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }

            var bericht: [String] = []
            @MainActor func festhalten(_ was: String) async {
                try? await Task.sleep(for: .milliseconds(700))
                let gewaehlt = speicher.auswahl.sorted().joined(separator: ", ")
                let zelle = speicher.zielzelle.map { "\($0.klasse.suffix(5))/KW\($0.woche)" } ?? "—"
                let empfaenger = fenster.firstResponder.map { String(describing: type(of: $0)) } ?? "—"
                bericht.append("\(was): Vorhaben [\(gewaehlt)] · Zelle \(zelle) · Fokus \(empfaenger)")
                speicher.vorhabenDialog = nil
            }

            klicken(punkt(woche: 0))
            await festhalten("1. Klick auf Vorhaben (Zeile 0, KW 0)")

            klicken(punkt(woche: 1))
            await festhalten("2. Klick auf leere Zelle (Zeile 0, KW 1)")

            // Über die Umgebung: weitere Aufrufparameter deutet AppKit als Voreinstellungen.
            if let pfad = ProcessInfo.processInfo.environment["MISCHBILD"] {
                Selbstabbild.ablegen(fenster, nach: URL(fileURLWithPath: pfad))
            }

            klicken(punkt(woche: 0))
            await festhalten("3. Klick zurück auf das Vorhaben")

            print("MISCHTEST\n  " + bericht.joined(separator: "\n  "))
            Pruefstaende.abschliessenUndBeenden()
        }
    }

    /// `--titeltest`: Schickt AppKit für den Fenstertitel
    /// `NSText.didBeginEditingNotification`? Ohne die Meldung löschte ⌫
    /// Vorhaben, während jemand den Titel korrigiert.
    static func titeltestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }) else {
                print("TITELTEST ✗ kein Fenster")
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))

            // Der Titel sitzt in der Rahmenansicht, nicht im Inhalt.
            var felder: [NSTextField] = []
            @MainActor func absuchen(_ ansicht: NSView) {
                if let feld = ansicht as? NSTextField, feld.isEditable { felder.append(feld) }
                ansicht.subviews.forEach(absuchen)
            }
            if let rahmen = fenster.contentView?.superview { absuchen(rahmen) }

            var bericht: [String] = ["beschreibbare Textfelder in der Fensterleiste: \(felder.count)"]
            bericht.append("vorher: schreibstelleAktiv = \(speicher.schreibstelleAktiv)")
            if let titelfeld = felder.first {
                fenster.makeFirstResponder(titelfeld)
                try? await Task.sleep(for: .milliseconds(400))
                bericht.append("Titelfeld hat die Schreibmarke: "
                               + "\(fenster.firstResponder is NSTextView)")
                bericht.append("beim Schreiben: schreibstelleAktiv = "
                               + "\(speicher.schreibstelleAktiv) "
                               + (speicher.schreibstelleAktiv ? "✓" : "✗ — ⌫ löschte hier Vorhaben"))
                fenster.makeFirstResponder(nil)
                try? await Task.sleep(for: .milliseconds(400))
                bericht.append("danach wieder: schreibstelleAktiv = "
                               + "\(speicher.schreibstelleAktiv) "
                               + (speicher.schreibstelleAktiv ? "✗ hängt fest" : "✓"))
            } else {
                bericht.append("✗ kein beschreibbares Titelfeld gefunden")
            }
            print("TITELTEST\n  " + bericht.joined(separator: "\n  "))
            Pruefstaende.abschliessenUndBeenden()
        }
    }

    /// `--menuetest`: In der Menüleiste können zwei Einträge dasselbe Kürzel
    /// tragen — welcher greift, zeigt nur die laufende Anwendung.
    static func menuetestUndBeenden(_ speicher: Planungsspeicher) {
        Task { @MainActor in
            for _ in 0..<40 where NSApp.windows.first(where: { $0.isVisible }) == nil
                || speicher.planung == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let fenster = NSApp.windows.first(where: { $0.isVisible }),
                  let planung = speicher.planung, planung.eintraege.count >= 2 else {
                print("MENUETEST ✗ keine Planung mit mindestens zwei Vorhaben")
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))

            speicher.anwaehlen(vorhaben: planung.eintraege[0].id)
            speicher.anwaehlen(vorhaben: planung.eintraege[1].id, erweitern: true)
            speicher.kopieren()
            try? await Task.sleep(for: .milliseconds(300))

            NSApp.mainMenu?.update()
            var zeilen: [String] = []
            zeilen.append("Auswahl \(speicher.auswahl.count) · Ablage "
                          + "\(speicher.ablage?.vorhaben.count ?? 0) · kannEinfuegen "
                          + "\(speicher.kannEinfuegen) · schreibstelleAktiv "
                          + "\(speicher.schreibstelleAktiv)")

            @MainActor func absuchen(_ menue: NSMenu, _ pfad: String) {
                for punkt in menue.items {
                    if let unter = punkt.submenu {
                        absuchen(unter, pfad.isEmpty ? punkt.title : pfad + " › " + punkt.title)
                        continue
                    }
                    let taste = punkt.keyEquivalent
                    guard ["c", "v", "x", "\u{8}", "\u{7f}"].contains(taste),
                          punkt.keyEquivalentModifierMask.contains(.command) || taste.count == 1,
                          !punkt.isSeparatorItem else { continue }
                    let name = taste == "\u{8}" || taste == "\u{7f}" ? "⌫" : "⌘" + taste.uppercased()
                    zeilen.append("  \(name)  „\(punkt.title)“ in [\(pfad)] · "
                                  + "aktiv \(punkt.isEnabled ? "ja" : "NEIN") · "
                                  + "Handlung \(punkt.action.map(String.init(describing:)) ?? "—")")
                }
            }
            if let haupt = NSApp.mainMenu { absuchen(haupt, "") }

            if let bearbeiten = NSApp.mainMenu?.items
                .first(where: { $0.title == "Bearbeiten" || $0.title == "Edit" })?.submenu {
                zeilen.append("Bearbeiten-Menü (\(bearbeiten.items.count) Einträge):")
                for punkt in bearbeiten.items {
                    let taste = punkt.keyEquivalent.isEmpty ? "—" : punkt.keyEquivalent
                    zeilen.append("  · „\(punkt.isSeparatorItem ? "———" : punkt.title)“ "
                                  + "Kürzel \(taste) · aktiv \(punkt.isEnabled ? "ja" : "nein")")
                }
            }

            var glied: NSResponder? = fenster.firstResponder
            var kette: [String] = []
            while let r = glied {
                var kann: [String] = []
                if r.responds(to: #selector(NSText.copy(_:))) { kann.append("copy") }
                if r.responds(to: #selector(NSText.paste(_:))) { kann.append("paste") }
                kette.append(String(describing: type(of: r))
                             + (kann.isEmpty ? "" : " ← \(kann.joined(separator: "/"))"))
                glied = r.nextResponder
            }
            zeilen.append("Antwortkette: " + kette.joined(separator: " → "))

            @MainActor func zustand(_ titel: String, soll: Bool) {
                @MainActor func finden(_ menue: NSMenu) -> NSMenuItem? {
                    for punkt in menue.items {
                        if punkt.title == titel { return punkt }
                        if let unter = punkt.submenu, let treffer = finden(unter) { return treffer }
                    }
                    return nil
                }
                guard let haupt = NSApp.mainMenu, let punkt = finden(haupt) else {
                    zeilen.append("  „\(titel)“ NICHT GEFUNDEN ✗"); return
                }
                zeilen.append("  „\(titel)“ ist \(punkt.isEnabled ? "aktiv" : "grau")"
                              + " · soll \(soll ? "aktiv" : "grau") sein"
                              + (punkt.isEnabled == soll ? " ✓" : " ✗"))
            }
            zeilen.append("Nachführung der Menüzustände (Planung geladen, \(speicher.auswahl.count) angewählt):")
            zustand("Vorhaben durchsuchen", soll: true)
            zustand("Lernende, Klassen/Kurse und Fächer …", soll: true)
            zustand("Kopieren", soll: true)
            zustand("Einsetzen", soll: true)

            // Aktiv-Zustand allein trügt: SwiftUI-Einträge tragen keine prüfbare Handlung.
            zeilen.append("Wirkung der Tastenkürzel:")
            @MainActor func druecken(_ zeichen: String, _ name: String,
                                     _ tasten: NSEvent.ModifierFlags = [.command],
                                     wirkung: @MainActor () -> String) async {
                let vorher = wirkung()
                // Einreihen: `performKeyEquivalent` umginge den echten Tastenweg.
                for art in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let ereignis = NSEvent.keyEvent(
                        with: art, location: .zero, modifierFlags: tasten,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: fenster.windowNumber, context: nil,
                        characters: zeichen, charactersIgnoringModifiers: zeichen,
                        isARepeat: false, keyCode: 0) else { return }
                    NSApp.postEvent(ereignis, atStart: false)
                }
                try? await Task.sleep(for: .milliseconds(500))
                let nachher = wirkung()
                zeilen.append("  \(name): \(vorher) → \(nachher)"
                              + (vorher == nachher ? "  ✗ ohne Wirkung" : "  ✓"))
            }

            for (taste, name, welcher) in [("k", "⌘K (Klassen/Kurse)", "klassen"),
                                           ("e", "⌘E (Ferien)", "ferien"),
                                           (",", "⌘, (Einstellungen)", "einstellungen"),
                                           ("d", "⌘D (Tagesliste)", "heute")] {
                await druecken(taste, name) { "Dialog \(speicher.offenerDialog?.rawValue ?? "—")" }
                if speicher.offenerDialog?.rawValue != welcher {
                    zeilen.append("      erwartet war „\(welcher)“")
                }
                speicher.offenerDialog = nil
                try? await Task.sleep(for: .milliseconds(200))
            }

            speicher.sprung = nil
            // ⌘J zählt nur, wenn die laufende Woche in der Planung liegt — die Saat endet im September (B76, E282).
            if planung.laufendeWoche != nil {
                await druecken("j", "⌘J (laufende Woche)") { "Sprung \(speicher.sprung?.woche ?? -1)" }
            } else {
                // Außerhalb: kein Sprung, aber der Hinweis (Z14d-07).
                let bisher = Set(speicher.meldungen.map(\.id))
                await druecken("j", "⌘J (laufende Woche außerhalb der Planung)") {
                    speicher.meldungen.contains {
                        !bisher.contains($0.id) && $0.text == "Die laufende Woche liegt außerhalb des geplanten Zeitraums."
                    } ? "Hinweis" : "kein Hinweis"
                }
            }

            speicher.anwaehlen(vorhaben: planung.eintraege[0].id)
            await druecken("a", "⌘A (alles wählen)") { "Auswahl \(speicher.auswahl.count)" }
            speicher.anwaehlen(vorhaben: planung.eintraege[0].id)
            speicher.anwaehlen(vorhaben: planung.eintraege[1].id, erweitern: true)

            speicher.ablageLeeren()
            await druecken("c", "⌘C (kopieren)") { "Ablage \(speicher.ablage?.vorhaben.count ?? 0)" }

            if speicher.ablage == nil { speicher.kopieren() }
            let ziel = planung.klassen.count > 1 ? planung.klassen[1].id : planung.klassen[0].id
            // Eine Woche, ab der die ganze Ablage in die Planung passt — die Saat hat sechs (B76, E282, Z14d-06).
            let abgelegt = speicher.ablage?.vorhaben.map(\.woche) ?? []
            let spanne = (abgelegt.max() ?? 0) - (abgelegt.min() ?? 0)
            speicher.anwaehlen(zelle: Zellenort(klasse: ziel, woche: max(0, min(6, planung.wochen - 1 - spanne))))
            let vorEinfuegen = speicher.planung?.eintraege.count ?? 0
            await druecken("v", "⌘V (einfügen)") { "Vorhaben \(speicher.planung?.eintraege.count ?? 0)" }
            let eingefuegt = (speicher.planung?.eintraege.count ?? 0) - vorEinfuegen
            zeilen.append("  ⌘V setzt die ganze Ablage ein: \(eingefuegt) von \(abgelegt.count)"
                          + (eingefuegt == abgelegt.count ? "  ✓" : "  ✗"))

            speicher.anwaehlen(vorhaben: planung.eintraege[0].id)
            await druecken("\u{8}", "⌫ (löschen)", []) {
                "Rückfrage \(speicher.rueckfrage == nil ? "nein" : "ja")"
            }

            // Rückfrage wegräumen — solange sie steht, ist sie das Schlüsselfenster. Wie von Hand (B82).
            if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) {
                zeilen.append("✗ Knopf „\(fehlt)“ im Alert gefunden")
            }
            fenster.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))
            zeilen.append("Im Textfeld (Fenstertitel):")
            var felder: [NSTextField] = []
            @MainActor func absuchenFelder(_ ansicht: NSView) {
                if let feld = ansicht as? NSTextField, feld.isEditable { felder.append(feld) }
                ansicht.subviews.forEach(absuchenFelder)
            }
            if let rahmen = fenster.contentView?.superview { absuchenFelder(rahmen) }
            if let titelfeld = felder.first {
                NSPasteboard.general.clearContents()
                let titel = "Prüftext"
                fenster.makeFirstResponder(titelfeld)
                try? await Task.sleep(for: .milliseconds(300))
                titelfeld.currentEditor()?.string = titel
                try? await Task.sleep(for: .milliseconds(200))
                // Hier ist „gleich geblieben“ der Erfolg — daher die eigene Zeile.
                let vorherAuswahl = speicher.auswahl.count
                await druecken("a", "  ⌘A (nur ins Feld)") { "Feldeditor" }
                zeilen.removeLast()
                zeilen.append("    ⌘A greift nicht ins Raster: Auswahl "
                              + "\(vorherAuswahl) → \(speicher.auswahl.count)"
                              + (vorherAuswahl == speicher.auswahl.count ? "  ✓" : "  ✗"))
                await druecken("c", "  ⌘C im Titelfeld") {
                    "Zwischenablage „\(NSPasteboard.general.string(forType: .string) ?? "—")“"
                }
                let kopiert = NSPasteboard.general.string(forType: .string)
                zeilen.append("    Titel war „\(titel)“ · kopiert wurde "
                              + "„\(kopiert ?? "—")“"
                              + (kopiert == titel ? "  ✓" : "  ✗"))
                fenster.makeFirstResponder(nil)
            } else {
                zeilen.append("    kein Textfeld gefunden")
            }

            print("MENUETEST\n" + zeilen.joined(separator: "\n"))
            Pruefstaende.abschliessenUndBeenden()
        }
    }

    @MainActor
    private final class Messung {
        var schritt = 0
        var beginn = Date()
        var rechenzeitVorher: Double = 0
        /// Die Uhr hängt hier, nicht am Blockbeiwert: `Timer` ist nicht
        /// `Sendable`, und Swift 6 weist das Durchreichen in den
        /// MainActor-Block ab.
        var uhr: Timer?

        /// Verbrauchte Rechenzeit — erfasst auch, was der Ablaufring später
        /// erledigt.
        nonisolated static func rechenzeit() -> Double {
            var nutzung = rusage()
            getrusage(RUSAGE_SELF, &nutzung)
            let benutzer = Double(nutzung.ru_utime.tv_sec) + Double(nutzung.ru_utime.tv_usec) / 1e6
            let system = Double(nutzung.ru_stime.tv_sec) + Double(nutzung.ru_stime.tv_usec) / 1e6
            return benutzer + system
        }

        func fertig() {
            let schritte = max(1, schritt)
            let dauer = Date().timeIntervalSince(beginn)
            Task { @MainActor in
                // Nachlauf abwarten: Die Rechenzeit trägt der Ablaufring später nach.
                try? await Task.sleep(for: .milliseconds(400))
                let rechenzeit = Messung.rechenzeit() - rechenzeitVorher
                print(String(format: "ROLLTEST %d Schritte in %.2f s · Rechenzeit %.2f s "
                             + "· %.1f ms je Schritt", schritte, dauer, rechenzeit,
                             rechenzeit / Double(schritte) * 1000))
                if Messzaehler.an { print("  ZERLEGT " + Messzaehler.zeitbericht()) }
                Pruefstaende.abschliessenUndBeenden()
            }
        }
    }

    /// Bis das Raster steht und der Sprung zu Woche 0 am linken Rand angekommen ist — nicht fest
    /// (Z14f-03). Ohne Rollbereich oder ohne Inhalt gilt nichts als angekommen (Z-AS1-05).
    @MainActor private static func sprungAbwarten(_ fenster: NSWindow) async {
        for _ in 0..<40 {
            if let rollbereich = groesserRollbereich(in: fenster.contentView),
               (rollbereich.documentView?.frame.width ?? 0) > 0, rollbereich.contentView.bounds.origin.x <= 0.5 { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Das Layout nach dem Sprung und nach `setContentSize` folgt im nächsten Durchgang.
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func groesserRollbereich(in wurzel: NSView?) -> NSScrollView? {
        guard let wurzel else { return nil }
        var gefunden: [NSScrollView] = []
        func absuchen(_ ansicht: NSView) {
            if let rollbereich = ansicht as? NSScrollView { gefunden.append(rollbereich) }
            ansicht.subviews.forEach(absuchen)
        }
        absuchen(wurzel)
        return gefunden.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}

/// Ein nachgebautes Ziehen für `Klickproben.ablegenProbe` (v88, AZ1): Ort, Zwischenablage, Arten und Quelle wie bei einem
/// Ziehen aus Finder, Safari oder von einer Kachel. Einträge zählt und reicht die Attrappe wie AppKit
/// (`numberOfValidItemsForDrop`, `enumerateDraggingItems`), jedes Ziehen hat seine eigene Nummer; leer ist nur das Bild.
/// Ohne Quelle gilt das Ziehen als fremd, wie eines aus Finder oder Safari (Z-AZ1-08, Z-AZ1N-01).
@MainActor
private final class Ablageattrappe: NSObject, @MainActor NSDraggingInfo {
    private static var zaehler = 0

    let draggingDestinationWindow: NSWindow?
    let draggingLocation: NSPoint
    let draggingPasteboard: NSPasteboard
    let draggingSourceOperationMask: NSDragOperation
    let draggingSource: Any?
    let draggingSequenceNumber: Int
    let springLoadingHighlight: NSSpringLoadingHighlight = .none
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop: Int

    init(fenster: NSWindow, ort: NSPoint, ablage: NSPasteboard, arten: NSDragOperation, quelle: Any?) {
        Self.zaehler += 1
        draggingDestinationWindow = fenster
        draggingLocation = ort
        draggingPasteboard = ablage
        draggingSourceOperationMask = arten
        draggingSource = quelle
        draggingSequenceNumber = Self.zaehler
        numberOfValidItemsForDrop = ablage.pasteboardItems?.count ?? 0
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let objekte = draggingPasteboard.readObjects(forClasses: classArray, options: searchOptions) ?? []
        var halt: ObjCBool = false
        for (stelle, objekt) in objekte.enumerated() {
            guard let schreiber = objekt as? NSPasteboardWriting else { continue }
            block(NSDraggingItem(pasteboardWriter: schreiber), stelle, &halt)
            if halt.boolValue { break }
        }
    }
    func resetSpringLoading() {}
}
