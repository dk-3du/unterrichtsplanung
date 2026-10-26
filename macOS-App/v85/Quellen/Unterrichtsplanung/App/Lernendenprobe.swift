// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Die Lernendenverwaltung am echten Paket (v80, AP6).
///
/// `--lernendentest versiegelt` (Vorgabe): an der gesäten, versiegelten Planung
/// samt Jahresdatei, Archiv und IServ-Muster (`tresor_pruefen.py --erzeugen`);
/// entsperrt mit `ENTSPERRPROBE_PASSPHRASE`. `--lernendentest gesperrt`: an
/// einer Planung im Klartext — das Modul ist aus (E249). `--lernendentest
/// jahreswechsel`: „Neue Planung“ über der gesäten — Planung, Jahresdatei und
/// Archiv wechseln in einem Übergang (E246); `jahreswechsel-pruefen`: der
/// zweite Start nach seinem Abbruch (E306). `--lernendentest e300verwerfen`
/// bzw. `e300uebernehmen`: ⌘Q mit geändertem Blatt, dann der Knopf — die App
/// endet über ihren eigenen Weg (E319).
///
/// Werkzeug vor der Oberfläche: Schritte, deren Blatt erst ein späterer Zug
/// baut, stehen als ✗ mit dem Zug, der sie bringt — der Lauf ist rot genau
/// dort, wo es vorhergesagt ist, und jeder Zug ersetzt seine Zeile durch die
/// Prüfung.
@MainActor
enum Lernendenprobe {

    /// `--abbild --dialog lernende`: entsperren (`ENTSPERRPROBE_PASSPHRASE`)
    /// und das Blatt öffnen — `ABBILD_LERNENDE=gruppe` (Vorgabe) die erste
    /// Lerngruppe mit ihren Mitgliedern, `mitglied` dazu ihr erstes Mitglied gewählt — die
    /// Personenzeile im Teil „Lerngruppen“ (Punkt 9), `uebersicht` alle Personen, `eingabe`
    /// die Eingabe von Hand mit Vorschau samt einem Namen, der schon dasteht;
    /// `mitteilungen` die Rücklaufliste, `massnahmen` die Maßnahmen, `offen`
    /// die Übersicht mit dem Filter „offen“ (AP8), `archiv` das Archiv (AP9);
    /// `personenanliegen` an einer Person einen Termin und eine Maßnahme ohne
    /// Lerngruppe, `terminbogen` dazu den Bogen „Termin ändern“ (AP13b, E290);
    /// `terminplanung` den Bogen „Neuer Termin“ mit Zeile, `terminraster` das
    /// Raster mit dem Vorhaben eines Termins (AP13c-1, E293); `vorhabentermin`
    /// den Vorhaben-Dialog mit „Als Termin führen“ und zwei Personen (AP13c-2, E295).
    /// `namenverwerfen` getippte Namen und einen Klick auf eine andere Gruppe —
    /// die Rückfrage „Die eingegebenen Namen verwerfen?“ (AP14b, E303);
    /// `bogenbeenden` den Bogen „Neuer Termin“ und ⌘Q — „Den offenen Bogen verwerfen?“ (AP14c).
    /// `suche` „Alle Lernenden“ mit der Suche „Hüb“, `sortiert` nach dem Vornamen geordnet, `gruppenfilter` die
    /// Gruppenliste mit dem Filter „Inf“ (v84, AT2b: E359–E363).
    /// `rueckmeldungsliste` der Bogen „Rückmeldungsliste“ am Teil „Mitteilungen“ von g-2, leer wie im Betrieb,
    /// `rueckmeldungsliste-gefuellt` mit gewählter Mitteilung und getipptem Kennwort (v85, AW5).
    /// Liegt die Planung im Klartext, zeigt das Abbild den Hinweis (E249).
    /// `--abbild --dialog schuljahrOeffnen`: entsperren, dann eine Planung anderer
    /// Herkunft anbieten, wie ⌘O sie öffnen will (AP14c, E305) — geöffnet wird nichts.
    /// Die angebotene Planung beginnt ein Jahr später, ihre Zeilen heißen „G7a“ (E307–E311);
    /// `ABBILD_SCHULJAHR=gleich`: dasselbe Schuljahr, dieselben Zeilen (E309). Auch die Dialogprobe nimmt diesen Weg
    /// für den Bogen „Lerngruppen zuordnen“ an ⌘O (E628) — dort ohne `ABBILD_SCHULJAHR`.
    static func schuljahrOeffnenVorbereiten(_ speicher: Planungsspeicher) async {
        if speicher.verschluesselungsstand == .gesperrt {
            await speicher.entsperren(passphrase: ProcessInfo.processInfo.environment["ENTSPERRPROBE_PASSPHRASE"]
                                      ?? "Ein Satz, den man behält")
            try? await Task.sleep(for: .milliseconds(600))
        }
        guard var fremd = speicher.planung else { return }
        let gleich = ProcessInfo.processInfo.environment["ABBILD_SCHULJAHR"] == "gleich"
        fremd.titel = gleich ? "Unterrichtsplanung 2026/27 (neu)" : "Unterrichtsplanung 2027/28"
        fremd.erstellt = gleich ? "2026-09-30T10:00:00.000Z" : "2027-07-01T10:00:00.000Z"
        if !gleich {
            fremd.start = fremd.start.plus(tage: 364)
            fremd.ersterSchultag = fremd.ersterSchultag?.plus(tage: 364)
            for i in fremd.klassen.indices {
                fremd.klassen[i].name = fremd.klassen[i].name.replacingOccurrences(of: "G6a", with: "G7a")
                fremd.klassen[i].fach = fremd.klassen[i].fach.replacingOccurrences(of: "G6a", with: "G7a")
            }
        }
        guard let daten = try? Planungsdatei.schreiben(fremd) else { return }
        speicher.importierenKlartext(daten, von: URL(fileURLWithPath: fremd.titel.replacingOccurrences(of: "/", with: "-") + ".json"))
    }

    /// `--abbild --dialog neuePlanung` mit `ABBILD_NEUEPLANUNG=folgejahr`: das
    /// Blatt für 2027/28 mit zwei eingetippten Zeilen und der übernommenen
    /// Klassenleitung — Hochstufen und Zuordnen (AP14c-2). Angelegt wird nichts. Auch die Dialogprobe nimmt
    /// diesen Weg für den Bogen „Lerngruppen zuordnen“, in jeder Lage (E628, Z-AT8P-11).
    static func neuePlanungVorbereiten(_ speicher: Planungsspeicher) {
        guard let start = Tag(iso: "2027-08-02") else { return }
        let leitung = speicher.planung?.klassen.first { $0.art == .klassenleitung }
        speicher.neuePlanungVorgabe = Neuplanungsvorgabe(start: start, kurstext: "G7a - Informatik\nG7a - Mathematik",
                                                         mitnehmen: leitung.map { [$0.id: false] } ?? [:])
    }

    static func abbildVorbereiten(_ speicher: Planungsspeicher) async {
        if speicher.verschluesselungsstand == .gesperrt {
            await speicher.entsperren(passphrase: ProcessInfo.processInfo.environment["ENTSPERRPROBE_PASSPHRASE"]
                                      ?? "Ein Satz, den man behält")
            try? await Task.sleep(for: .milliseconds(600))
        }
        let bestand = speicher.lernende.bestand
        let gruppe = bestand?.lerngruppen.first
        let lage = ProcessInfo.processInfo.environment["ABBILD_LERNENDE"] ?? "gruppe"
        // Die Saat: Mitteilung m-1 an g-2 mit drei Rückläufen, Maßnahme m-3 für l-4 (AP6).
        let mitG2 = ["mitteilungen", "rueckmeldungsliste", "rueckmeldungsliste-gefuellt"].contains(lage)
        speicher.lernendenBlattOeffnen(gruppe: mitG2 ? "g-2" : gruppe?.id)
        guard speicher.lernendenVorgabe != nil else { return }
        switch lage {
        case "uebersicht":
            speicher.lernendenVorgabe?.ansicht = .alle
        case "mitglied":
            // Punkt 9: die Personenzeile im Teil „Lerngruppen“ — die erste Gruppe der Jahresdatei,
            // ihr erstes Mitglied in Anlegefolge (nicht die oberste Zeile der geordneten Liste).
            speicher.lernendenVorgabe?.person = gruppe?.mitglieder.first
        case "import":
            // AP13: der Bogen mit der Musterdatei der Saat, Ziel die gewählte Gruppe.
            speicher.lernendenVorgabe?.importdatei = speicher.sicherung.ablage.ordner.appending(component: "iserv-muster.csv")
        case "import-jeklasse":
            // AT5 (E352, E524): derselbe Bogen ohne gewählte Gruppe — unter „Alle Lernenden“ —, Ziel „Je Klasse“ mit Schalter.
            speicher.lernendenVorgabe?.ansicht = .alle
            speicher.lernendenVorgabe?.importdatei = speicher.sicherung.ablage.ordner.appending(component: "iserv-muster.csv")
        case "rufname":
            // E285: eine Person mit Rufname, gewählt unter „Alle Lernenden“ — in der Kopie der Probe.
            if let bestand, let p = bestand.lernende.first(where: { $0.nachname == "Hübner" }) {
                _ = speicher.lernendenUebernehmen(bestand.mitPerson(p.id, vorname: p.vorname, nachname: p.nachname,
                                                                    rufname: "Hans", jetzt: Zeitrechnung.jetztAlsZeitstempel()))
                speicher.lernendenVorgabe?.person = p.id
            }
            speicher.lernendenVorgabe?.ansicht = .alle
        case "personenanliegen", "terminbogen":
            // E290: in der Kopie der Probe — ein offener Termin, eine erfüllte Maßnahme, beide ohne Gruppe.
            if let bestand, let p = bestand.lernende.first(where: { $0.nachname == "Hübner" }) {
                let jetzt = Zeitrechnung.jetztAlsZeitstempel()
                let termin = bestand.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [p.id],
                                                      datum: Tag.heute.plus(tage: 3).iso, frist: "", uhrzeit: "07:45",
                                                      jetzt: jetzt)
                let massnahme = termin?.bestand.mitNeuemAnliegen(.massnahme, titel: "Lesetagebuch nachreichen",
                                                                 lerngruppe: "", betroffene: [p.id], datum: Tag.heute.iso,
                                                                 frist: Tag.heute.plus(tage: 7).iso, jetzt: jetzt)
                if let termin, let massnahme {
                    let mitNotiz = massnahme.bestand.mitAnliegen(termin.id, titel: "Elterngespräch",
                                                                 datum: Tag.heute.plus(tage: 3).iso, frist: "",
                                                                 notiz: "Mit der Mutter, im Besprechungsraum.", jetzt: jetzt)
                    _ = speicher.lernendenUebernehmen(mitNotiz.mitRuecklauf(massnahme.id, p.id, stand: .erledigt,
                                                                            datum: Tag.heute.iso, notiz: "", jetzt: jetzt))
                    if lage == "terminbogen" {
                        speicher.lernendenVorgabe?.anliegenbogen = .termin
                        speicher.lernendenVorgabe?.anliegen = termin.id
                    }
                }
                speicher.lernendenVorgabe?.person = p.id
            }
            speicher.lernendenVorgabe?.ansicht = .alle
        case "bogenbeenden":
            // Offener Punkt 2: ⌘Q bei offenem Bogen — die Frage steht auf dem Bogen; beendet wird nichts.
            // Der Bogen hängt an „Alle Lernenden“ — wie im Schritt der Runde (E290).
            if let p = bestand?.lernende.first(where: { $0.nachname == "Hübner" }) {
                speicher.lernendenVorgabe?.ansicht = .alle
                speicher.lernendenVorgabe?.person = p.id
                speicher.lernendenVorgabe?.anliegenbogen = .termin
                speicher.lernendenVorgabe?.anliegentag = Tag(iso: "2026-09-03")
            }
            Task { @MainActor in
                // Erst, wenn der Bogen am Blatt steht — `bogenOffen()` gilt schon vorher.
                @MainActor func bogen() -> NSWindow? {
                    NSApp.windows.first { $0.isVisible && $0.parent == nil }?.attachedSheet?.attachedSheet
                }
                for _ in 0..<30 where bogen() == nil {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard bogen() != nil, speicher.lernendenblattGriff?.bogenOffen() == true else { return }
                speicher.beenden()
            }
        case "terminplanung":
            // E293: Hübner steht in der Lerngruppe der Klassenleitung — vorbelegt, der Tag in der Planung.
            if let p = bestand?.lernende.first(where: { $0.nachname == "Hübner" }) {
                speicher.lernendenVorgabe?.person = p.id
                speicher.lernendenVorgabe?.anliegenbogen = .termin
                speicher.lernendenVorgabe?.anliegentag = Tag(iso: "2026-09-03")
            }
            speicher.lernendenVorgabe?.ansicht = .alle
        case "terminraster":
            // E293: ein Termin mit Vorhaben in der Klassenleitung, in der Kopie der Probe — dann das Raster.
            if let bestand, let p = bestand.lernende.first(where: { $0.nachname == "Hübner" }),
               let termin = bestand.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [p.id],
                                                     datum: "2026-08-20", frist: "", uhrzeit: "07:45",
                                                     jetzt: Zeitrechnung.jetztAlsZeitstempel()),
               let zeile = speicher.planung.flatMap({ Terminabgleich.vorbelegteZeile(fuer: p.id, planung: $0, bestand: bestand) }) {
                _ = speicher.lernendenUebernehmen(termin.bestand.mitTerminwunsch(termin.id, zeile: zeile))
            }
            speicher.lernendenVorgabe = nil
            speicher.offenerDialog = nil
        case "vorhabentermin":
            // E295: kein Blatt „Lernende“, sondern der Vorhaben-Dialog — ein Fenster trägt einen Bogen.
            speicher.lernendenVorgabe = nil
            speicher.offenerDialog = nil
            try? await Task.sleep(for: .milliseconds(900))
            if let v = speicher.planung?.eintraege.first(where: { $0.titel == "Bits und Bytes" }),
               let personen = speicher.lernende.verzeichnis?.alle.filter({ ["Hübner", "Iversen"].contains($0.nachname) }) {
                var e = VorhabenEntwurf(v)
                e.termin = true
                e.terminzeit = "10:30"
                e.terminpersonen = personen.map(\.id)
                e.datum = e.datum ?? speicher.planung.map { $0.start.montagDerWoche.plus(tage: v.woche * 7 + 2) }
                speicher.vorhabenDialog = e
                // Das Blatt öffnet auf „Grundlegendes“ (E731) — der Termin steht auf seinem Reiter (Z-AW3n-03).
                speicher.vorhabenReiter = .termin
            }
        case "offen":
            speicher.lernendenVorgabe?.ansicht = .alle
            speicher.lernendenVorgabe?.nurOffen = true
            speicher.lernendenVorgabe?.person = "l-4"
        case "mitteilungen":
            speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
            speicher.lernendenVorgabe?.anliegen = "m-1"
            speicher.lernendenVorgabe?.person = "l-3"
        case "rueckmeldungsliste", "rueckmeldungsliste-gefuellt":
            // AW5 (E401, E408): der Bogen am Teil „Mitteilungen“ — leer wie im Betrieb, oder mit der gewählten Mitteilung
            // und getipptem Kennwort.
            speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
            let kennwort = "Elternbriefe 2026"
            speicher.lernendenVorgabe?.rueckmeldungsliste = lage == "rueckmeldungsliste" ? Rueckmeldungsbogenvorgabe()
                : Rueckmeldungsbogenvorgabe(auswahl: ["m-1"], kennwort: kennwort, wiederholung: kennwort)
        case "archiv":
            speicher.lernendenVorgabe?.ansicht = .archiv
        case "suche":
            // AT2b (E360): unter „Alle Lernenden“ gesucht — der Zähler „1 von 12 Personen“.
            speicher.lernendenVorgabe?.ansicht = .alle
            speicher.lernendenVorgabe?.suche = "Hüb"
        case "sortiert":
            // AT2b (E362, E363): nach dem Vornamen geordnet, der Pfeil im Kopf.
            speicher.lernendenVorgabe?.ansicht = .alle
            speicher.lernendenVorgabe?.sortierung = .vorname
        case "gruppenfilter":
            // AT2b (E359, E480, E671): die Gruppenliste nach Name und verknüpften Zeilen gefiltert.
            speicher.lernendenVorgabe?.gruppensuche = "Inf"
        case "massnahmen":
            speicher.lernendenVorgabe?.gruppenteil = .massnahmen
            speicher.lernendenVorgabe?.anliegen = "m-3"
            speicher.lernendenVorgabe?.person = "l-4"
        case "eingabe":
            let schonDa = gruppe?.mitglieder.first.flatMap { id in bestand?.lernende.first { $0.id == id } }
            speicher.lernendenVorgabe?.namenstext = "Okafor, Chidi\nJonas Petersen\nvan der Berg, Lena"
                + (schonDa.map { "\n\($0.nachname), \($0.vorname)" } ?? "")
        case "namenverwerfen":
            // E303: getippte Namen, dann ein Klick auf eine andere Gruppe — die Rückfrage steht.
            speicher.lernendenVorgabe?.namenstext = "Okafor, Chidi\nJonas Petersen"
            speicher.lernendenVorgabe?.gruppenwechsel = bestand?.lerngruppen.first { $0.id != gruppe?.id }?.id
        default:
            break
        }
    }

    /// Die Zeilen des Laufs — außerhalb der Aufgabe, damit die Reißleine das Bisherige drucken kann (B97).
    private static var zeilen: [String] = []
    /// Die Frist der Reißleine in Sekunden — unter der des Treibers (420 s); der längste Lauf braucht rund 50 s (E413).
    static let reissleinenfrist = 300

    static func laufenUndBeenden(_ speicher: Planungsspeicher, art: String) {
        let umgebung = ProcessInfo.processInfo.environment
        zeilen = ["LERNENDENTEST (\(art))"]
        // Die Reißleine wie in der Dialogprobe (B97, E413): Kommt der Lauf nicht bis zur Endstelle, druckt sie das
        // Bisherige mit ✗ und geht — `exit(3)` nimmt jedes offene Fenster mit.
        let reissleine = Task { @MainActor in
            try? await Task.sleep(for: .seconds(reissleinenfrist))
            // `try?` schluckt das Abbrechen — ohne diese Zeile risse sie nach `ende()` doch noch (E423).
            guard !Task.isCancelled else { return }
            zeilen.append("LERNENDENTEST (\(art)) REISSLEINE — Frist von \(reissleinenfrist) s verstrichen ✗")
            print(zeilen.joined(separator: "\n"))
            fflush(stdout)
            exit(3)
        }
        Task { @MainActor in
            @MainActor func pruefen(_ gilt: Bool, _ text: String) {
                zeilen.append("  \(gilt ? "✓" : "✗") \(text)")
            }
            @MainActor func ende() async {
                reissleine.cancel()
                print(zeilen.joined(separator: "\n"))
                fflush(stdout)
                await Pruefstaende.abschliessenUndBeenden(speicher)
            }
            let ablage = speicher.sicherung.ablage
            func kennung(_ url: URL) -> (inhalt: String, kennung: String)? {
                guard let roh = try? Data(contentsOf: url), let kopf = try? Tresor.kopfLesen(roh) else { return nil }
                return (kopf.inhalt, kopf.kennungHex)
            }
            @MainActor func einStand() {
                let namen = ((try? FileManager.default.contentsOfDirectory(atPath: ablage.ordner.path)) ?? []).sorted()
                // Alle Spuren, wie der Dienst sie kennt: Marke, Zweitschrift, Zwillinge, Vorgänger (Z14d-08).
                let spuren = (try? Uebergangsdienst.spuren(in: ablage.ordner)) ?? ["Ordner nicht lesbar"]
                pruefen(spuren.isEmpty, "keine Spur des Übergangs" + (spuren.isEmpty ? "" : " (\(spuren.joined(separator: ", ")))"))
                pruefen(!namen.contains { $0.contains("-fremd-") || $0.contains("-beschaedigt-") || $0.contains("-unerwartet-") },
                        "keine Rettungskopie")
                zeilen.append("  Dateien: " + namen.filter { $0.hasSuffix(".json") || $0.hasSuffix(".csv") }.joined(separator: ", "))
            }

            // ── Menü und Tasten, wie AppKit sie führt ─────────────────────
            @MainActor func hauptfenster() -> NSWindow? { NSApp.windows.first { $0.isVisible && $0.parent == nil } }
            /// „Planung → Lernende …“, nachgeführt wie beim Öffnen durch den
            /// Nutzer: erst der Delegat, dann die Prüfung der Einträge.
            @MainActor func eintragAktiv() -> Bool? {
                guard let eintrag = NSApp.mainMenu?.items.first(where: { $0.title == "Planung" })?
                        .submenu?.items.first(where: { $0.title == "Lernende …" }),
                      let menue = eintrag.menu else { return nil }
                menue.delegate?.menuNeedsUpdate?(menue)
                menue.update()
                return eintrag.isEnabled
            }
            /// Ein Tastendruck, eingereiht wie von der Tastatur.
            @MainActor func taste(_ zeichen: String, code: UInt16, _ tasten: NSEvent.ModifierFlags = [],
                                  in fenster: NSWindow?) {
                for art in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let ereignis = NSEvent.keyEvent(
                        with: art, location: .zero, modifierFlags: tasten,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: fenster?.windowNumber ?? 0, context: nil,
                        characters: zeichen, charactersIgnoringModifiers: zeichen,
                        isARepeat: false, keyCode: code) else { continue }
                    NSApp.postEvent(ereignis, atStart: false)
                }
            }
            @MainActor func tippen(_ text: String, in fenster: NSWindow) {
                for zeichen in text {
                    if zeichen == "\n" { taste("\r", code: 36, in: fenster) } else { taste(String(zeichen), code: 0, in: fenster) }
                }
            }
            @MainActor func suchen<T: NSView>(_ ansicht: NSView?, _ art: T.Type, _ passt: (T) -> Bool) -> T? {
                guard let ansicht else { return nil }
                if let treffer = ansicht as? T, passt(treffer) { return treffer }
                for kind in ansicht.subviews {
                    if let treffer = suchen(kind, art, passt) { return treffer }
                }
                return nil
            }
            func warten(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
            /// Die Inhalte aller Textfelder — nur zur Meldung, wenn ein Bogen nicht schließt.
            @MainActor func sammelnTextfelder(_ ansicht: NSView?) -> [String] {
                guard let ansicht else { return [] }
                var aus: [String] = []
                if let feld = ansicht as? NSTextField, feld.isEditable { aus.append("„\(feld.stringValue)“") }
                for kind in ansicht.subviews { aus += sammelnTextfelder(kind) }
                return aus
            }
            /// Nach einem ✗ Blatt und Bogen schließen wie von Hand — ⎋, und „Verwerfen“, falls gefragt —;
            /// sonst landet der nächste Schritt im falschen Fenster, und aus einer Ursache werden mehrere ✗ (Z14f-04).
            /// Bestätigt wird nur „Verwerfen“, jede andere Frage abgelehnt (Z-AS1-02). `false`: Ein Blatt blieb.
            @discardableResult @MainActor func blattSchliessen() async -> Bool {
                for _ in 0..<6 {
                    guard let blatt = hauptfenster()?.attachedSheet else { return true }
                    if let alert = Pruefstaende.alertfenster() {
                        if let frage = speicher.rueckfrage {
                            // Nur die Frage, die ⎋ am Blatt selbst stellt — „Verwerfen“ beim Beenden setzte
                            // das Beenden fort (Z-AS1-17).
                            _ = await Pruefstaende.vonHandAntworten(speicher, frage.text == "Die Änderungen an den Lernenden verwerfen?")
                        } else if let knopf = suchen(alert.contentView, NSButton.self, { $0.title == "Verwerfen" })
                                    ?? suchen(alert.contentView, NSButton.self, { $0.keyEquivalent == "\u{1B}" })
                                    ?? suchen(alert.contentView, NSButton.self, { $0.title == "Abbrechen" }) {
                            // Ein eigener Alert ohne „Verwerfen“ wird abgebrochen, danach erneut ⎋ (Z-AS1-03).
                            knopf.performClick(nil)
                        }
                        for _ in 0..<16 where Pruefstaende.alertfenster() != nil { await warten(125) }
                        // Schloss die Antwort das Blatt, nicht noch ein ⎋ an das abblendende (Z-AS1-04).
                        for _ in 0..<12 where hauptfenster()?.attachedSheet === blatt { await warten(250) }
                        continue
                    }
                    let oben = blatt.attachedSheet ?? blatt
                    oben.makeKeyAndOrderFront(nil)
                    taste("\u{1B}", code: 53, in: oben)
                    for _ in 0..<12 where oben.isVisible && Pruefstaende.alertfenster() == nil { await warten(250) }
                }
                return hauptfenster()?.attachedSheet == nil
            }

            try? await Task.sleep(for: .seconds(2.5))
            for meldung in speicher.meldungen { zeilen.append("  Start meldet: " + meldung.text) }
            // Der zweite Start nach einem Abbruch vor dem Übergeben: Jede Spur sperrt die Ablage —
            // beiseitelegen wie von Hand, dann entsperren (E306, wie die Suite `abbruchAnJederStelle`).
            let sperrteBeimStart = speicher.blockadeOffen
            if art == "jahreswechsel-pruefen", sperrteBeimStart {
                speicher.blockadeRaeumenFragen()
                for _ in 0..<20 where speicher.rueckfrage == nil { await warten(150) }
                if let fehlt = await Pruefstaende.vonHandAntworten(speicher, true) {
                    pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                }
                for _ in 0..<20 where speicher.blockadeOffen { await warten(150) }
                pruefen(!speicher.blockadeOffen, "die Sperre der Ablage ist beiseitegelegt")
            }
            if speicher.verschluesselungsstand == .gesperrt {
                await speicher.entsperren(passphrase: umgebung["ENTSPERRPROBE_PASSPHRASE"] ?? "Ein Satz, den man behält")
                try? await Task.sleep(for: .milliseconds(600))
                pruefen(speicher.verschluesselungsstand == .an, "entsperrt")
            }
            pruefen(!speicher.meldungen.contains { $0.text.contains("Lernendendaten wurden beim Lesen bereinigt")
                                                   || $0.text.contains("Lernendendatei ließ sich nicht öffnen")
                                                   || $0.text.contains("Archiv der Lernendenverwaltung") },
                    "nichts zur Lernendenverwaltung gemeldet, nichts beiseitegelegt")

            switch art {
            case "gesperrt":
                pruefen(speicher.verschluesselungsstand == .aus, "die Planung liegt im Klartext")
                pruefen(speicher.lernende.quelle == .aus, "die Lernendenverwaltung ist aus (\(speicher.lernende.quelle))")
                pruefen(speicher.lernende.sperrhinweis?.contains("Verschlüsselung") == true, "der Hinweis nennt die Verschlüsselung")
                pruefen(!FileManager.default.fileExists(atPath: ablage.lernende.path), "keine Lernendendatei")
                NSApp.activate(ignoringOtherApps: true)
                hauptfenster()?.makeKeyAndOrderFront(nil)
                await warten(400)
                taste("l", code: 37, [.command], in: hauptfenster())
                await warten(800)
                pruefen(speicher.offenerDialog == nil && hauptfenster()?.attachedSheet == nil, "⌘L öffnet kein Blatt")
                let aktiv = eintragAktiv()
                pruefen(aktiv == false, "Menüeintrag „Planung → Lernende …“ grau (\(aktiv.map { $0 ? "aktiv" : "grau" } ?? "fehlt"))")
                // Der Versuch auf anderem Weg (⌘K, Kurszelle): der Hinweis mit Knopf.
                speicher.lernendenBlattOeffnen()
                pruefen(speicher.rueckfrage?.text == Planungsspeicher.lernendenSperrtext
                        && speicher.rueckfrage?.bestaetigung == "Verschlüsselung einrichten …"
                        && speicher.offenerDialog == nil,
                        "der Versuch zeigt den Hinweis mit „Verschlüsselung einrichten …“, kein Blatt")
                // Wie von Hand, nicht im Programm (B82, Z14c3-10).
                if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) {
                    pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                }

            case "jahreswechsel-pruefen":
                // Der zweite Start nach einem Abbruch des Schuljahreswechsels (E306): Planung, Jahresdatei
                // und Archiv sind alle alt (Abbruch vor dem Übergeben) oder alle neu — nie gemischt.
                let erwartet = umgebung["JAHRESWECHSEL_ERWARTET"] ?? "?"
                let planung = speicher.planung
                let jahresdatei = speicher.lernende.bestand
                var jahre: [String]?
                if case .gelesen(let archiv, _, _) = speicher.lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) {
                    jahre = archiv.jahre.map(\.schuljahr)
                }
                let neu = planung?.titel == "Prüfvektor 2027/28"
                let gebunden = jahresdatei?.planung != nil && jahresdatei?.planung == planung?.erstellt
                let alleNeu = neu && gebunden && jahresdatei?.schuljahr == "2027/28" && jahre == ["2025/26", "2026/27"]
                let alleAlt = !neu && gebunden && jahresdatei?.schuljahr == "2026/27" && jahre == ["2025/26"]
                pruefen(erwartet == "neu" ? alleNeu : erwartet == "alt" ? alleAlt : false,
                        "nach dem Abbruch alle drei \(erwartet): Planung „\(planung?.titel ?? "—")“, Jahresdatei "
                        + "\(jahresdatei?.schuljahr ?? "—") (gebunden \(gebunden)), Archiv \(jahre ?? [])")
                // Vor dem Übergeben sperrt jede Spur (die Suite sichert es zu); danach vollendet der Start (Z14d-03).
                if erwartet == "alt" {
                    pruefen(sperrteBeimStart, "der zweite Start sperrte die Ablage, beiseitegelegt wie von Hand")
                } else {
                    zeilen.append("  Sperre beim zweiten Start: \(sperrteBeimStart ? "ja, beiseitegelegt" : "nein")")
                }
                pruefen(speicher.lernende.schreibbar, "die Lernendenverwaltung ist offen")
                einStand()

            case "jahreswechsel":
                guard let alt = speicher.planung, let zeile = alt.klassen.first(where: { $0.id == "k-1" }),
                      let tresor = speicher.tresor else {
                    pruefen(false, "gesäte Planung mit Zeile k-1, entsperrt")
                    await ende()
                    return
                }
                pruefen(speicher.lernende.bestand?.lernende.count == 12, "Jahresdatei mit 12 Personen geladen")
                // Mit UEBERGANG_ABBRUCH endet der Prozess im Dienst — das Bisherige vorher ins Protokoll (E306, Z14d-01),
                // dann geleert: Endet er doch nicht, druckten `ende()` und die Reißleine es sonst noch einmal (Z-AU1-03).
                if let abbruch = umgebung["UEBERGANG_ABBRUCH"] {
                    zeilen.append("  UEBERGANG_ABBRUCH=\(abbruch): Der Prozess endet nach diesem Schritt")
                    print(zeilen.joined(separator: "\n"))
                    fflush(stdout)
                    zeilen.removeAll()
                }
                // „G6a“ (g-1) eine Stufe höher an eine eingetippte Zeile (AP14c-2, E308, E310).
                let getippt = Standardkurse.aufbauen([("G7a", "Informatik")])
                speicher.neuePlanung(titel: "Prüfvektor 2027/28", start: Tag(iso: "2027-08-09") ?? alt.start, wochen: 6,
                                     basis: "", klassen: getippt, ersterSchultag: nil,
                                     uebernahme: [Planung.Uebernahmewunsch(klasse: zeile, mitVorhaben: false)],
                                     lerngruppen: ["g-1"],
                                     ziele: ["g-1": Gruppenwahl(name: "G7a", zeilen: [.kennung(getippt[0].id)])])
                let neu = speicher.planung
                pruefen(neu?.titel == "Prüfvektor 2027/28" && neu?.erstellt != alt.erstellt, "neue Planung angelegt")
                let jahresdatei = speicher.lernende.bestand
                pruefen(jahresdatei?.planung == neu?.erstellt && jahresdatei?.schuljahr == "2027/28",
                        "neue Jahresdatei an die neue Planung gebunden (2027/28)")
                pruefen(jahresdatei?.lerngruppen.map(\.id) == ["g-1"], "die Gruppe der übernommenen Zeile — nur sie")
                let hochgestuft = jahresdatei?.lerngruppen.first
                pruefen(hochgestuft?.name == "G7a"
                        && hochgestuft?.zeilen == [Zeilenbindung(planung: neu?.erstellt ?? "", klasseId: getippt[0].id)],
                        "„G6a“ heißt „G7a“ und hängt an der eingetippten Zeile (E308, E310)")
                pruefen(jahresdatei?.lernende.count == 12, "ihre zwölf Personen mit derselben Kennung")
                if case .gelesen(let archiv, _, _) = speicher.lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) {
                    pruefen(archiv.jahre.map(\.schuljahr) == ["2025/26", "2026/27"], "das Archiv trägt Vorjahr und bisheriges Jahr")
                    pruefen(archiv.jahre.last?.planung.erstellt == alt.erstellt, "die bisherige Planung liegt im Archiv")
                } else {
                    pruefen(false, "das Archiv öffnet")
                }
                for (url, inhalt) in [(ablage.lernende, "lernende"), (ablage.archiv, "archiv"), (ablage.datei, "planung")] {
                    let kopf = kennung(url)
                    pruefen(kopf?.inhalt == inhalt && kopf?.kennung == tresor.kennungHex,
                            "\(url.lastPathComponent): Behälter „\(inhalt)“ unter dem Schlüssel der Sitzung")
                }
                einStand()

            case "e300verwerfen", "e300uebernehmen":
                // E319: ⌘Q mit geändertem Blatt „Lernende“, dann „Verwerfen“ bzw. „Übernehmen“ wie von Hand —
                // danach geht das Beenden weiter, und die App endet über ihren eigenen Weg.
                let uebernehmen = art == "e300uebernehmen"
                let knopf = uebernehmen ? "Übernehmen" : "Verwerfen"
                NSApp.activate(ignoringOtherApps: true)
                hauptfenster()?.makeKeyAndOrderFront(nil)
                await warten(400)
                speicher.lernendenBlattOeffnen()
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                guard let blatt = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende else {
                    pruefen(false, "Blatt „Lernende“ offen (Dialog \(speicher.offenerDialog?.rawValue ?? "—"))")
                    await ende()
                    return
                }
                blatt.makeKeyAndOrderFront(nil)
                for _ in 0..<20 where suchen(blatt.contentView, NSTextField.self, { $0.placeholderString == "Neue Lerngruppe" }) == nil {
                    await warten(150)
                }
                guard let feld = suchen(blatt.contentView, NSTextField.self, { $0.placeholderString == "Neue Lerngruppe" }) else {
                    pruefen(false, "Feld „Neue Lerngruppe“ gefunden")
                    await ende()
                    return
                }
                blatt.makeFirstResponder(feld)
                await warten(200)
                tippen("Probe E300\n", in: blatt)
                for _ in 0..<20 where speicher.lernendenverlauf.naechsterName != Schrittname.lerngruppeAnlegen { await warten(150) }
                // Ohne Änderung fragte ⌘Q nicht — die App ginge, und das Protokoll bräche ab (Z14d2-05).
                guard speicher.lernendenverlauf.naechsterName == Schrittname.lerngruppeAnlegen else {
                    pruefen(false, "Gruppe „Probe E300“ im Blatt angelegt (\(speicher.lernendenverlauf.naechsterName ?? "—"))")
                    await ende()
                    return
                }
                pruefen(true, "Gruppe „Probe E300“ im Blatt angelegt — das Blatt ist geändert")
                speicher.beenden()
                for _ in 0..<8 where speicher.rueckfrage == nil { await warten(250) }
                pruefen(speicher.rueckfrage?.text.hasPrefix("Die Änderungen an den Lernenden übernehmen?") == true
                        && speicher.rueckfrage?.weitere == "Verwerfen",
                        "⌘Q mit geändertem Blatt: „Die Änderungen an den Lernenden übernehmen?“ (E300)")
                // Was beim Beenden gilt, sichert der Delegat zu — vor der Schlusszeile.
                Pruefstaende.schlusspruefung = { [speicher] in
                    let gruppe = speicher.lernende.bestand?.lerngruppen.contains { $0.name == "Probe E300" } == true
                    return ["  \(gruppe == uebernehmen ? "✓" : "✗") beim Beenden: „Probe E300“ "
                            + (gruppe ? "übernommen" : "nicht übernommen") + " („\(knopf)“)",
                            "  \(speicher.lernende.ungesichert == nil ? "✓" : "✗") die Lernendendaten sind gesichert"]
                }
                zeilen.append("  Klick auf „\(knopf)“ — danach muss die App von selbst enden (E319)")
                print(zeilen.joined(separator: "\n"))
                fflush(stdout)
                zeilen.removeAll()
                Pruefstaende.abschliessen()
                let fehlt = uebernehmen ? await Pruefstaende.vonHandAntworten(speicher, true)
                                        : await Pruefstaende.vonHandWeitere(speicher)
                if let fehlt {
                    // Sofort gedruckt: Die Ersatzantwort beendet die App womöglich, ehe `ende()` druckt (Z14d2-01).
                    print("  ✗ Knopf „\(fehlt)“ im Alert gefunden")
                    fflush(stdout)
                }
                // Endet die App nicht binnen 6 s, lief das Beenden nach der Antwort nicht weiter — das Übernehmen
                // wartet höchstens 0,35 + 2,5 s auf das Alert, das Beenden danach 0,35 s, das Ablösen der Blätter
                // 1,2 s (Z14d2-04, Z-AU4a-08).
                for _ in 0..<24 { await warten(250) }
                Pruefstaende.schlusspruefung = nil
                pruefen(false, "nach „\(knopf)“ endet die App von selbst — sie läuft 6 s nach dem Klick noch (Blatt "
                        + "\(speicher.offenerDialog?.rawValue ?? "zu"), Rückfrage \(speicher.rueckfrage == nil ? "keine" : "steht"))")

            default:
                guard let tresor = speicher.tresor else {
                    pruefen(false, "entsperrt mit Schlüssel")
                    await ende()
                    return
                }
                let jahresdatei = speicher.lernende.bestand
                pruefen(speicher.lernende.quelle == .behaelter, "die Lernendenverwaltung ist offen")
                pruefen(jahresdatei?.lernende.count == 12 && jahresdatei?.lerngruppen.count == 2,
                        "Jahresdatei geladen: 12 Personen in 2 Gruppen")
                pruefen(jahresdatei?.anliegen.count == 3 && jahresdatei?.rueckmeldungen.count == 3,
                        "drei Anliegen, drei Rückläufe")
                let kopf = kennung(ablage.lernende)
                pruefen(kopf?.inhalt == "lernende" && kopf?.kennung == tresor.kennungHex,
                        "lernende.json ist ein Behälter mit Inhalt „lernende“ unter dem Schlüssel der Sitzung")
                if case .gelesen(let archiv, _, _) = speicher.lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) {
                    pruefen(archiv.jahre.map(\.schuljahr) == ["2025/26"], "das Archiv trägt das Vorjahr 2025/26")
                } else {
                    pruefen(false, "das Archiv öffnet")
                }
                pruefen(FileManager.default.fileExists(atPath: ablage.ordner.appendingPathComponent("iserv-muster.csv").path),
                        "die IServ-Musterdatei liegt bereit")

                // ── Das Blatt „Lernende“ (AP7): ⌘L, Gruppe anlegen, Namen von Hand ──
                // ⌘L als Tastendruck, ohne das Menü vorher zu öffnen: Der graue
                // Stand vom Start darf das Kürzel nicht schlucken.
                NSApp.activate(ignoringOtherApps: true)
                hauptfenster()?.makeKeyAndOrderFront(nil)
                await warten(400)
                let hauptschritt = speicher.verlauf.naechsterName
                /// Der Eintrag, wie er gerade steht — ohne ihn nachzuführen.
                @MainActor func eintragJetzt() -> String {
                    guard let eintrag = NSApp.mainMenu?.items.first(where: { $0.title == "Planung" })?
                            .submenu?.items.first(where: { $0.title == "Lernende …" }) else { return "Eintrag fehlt" }
                    return "Eintrag \(eintrag.isEnabled ? "aktiv" : "grau"), Kürzel ⌘\(eintrag.keyEquivalent)"
                }
                let vorKuerzel = "App \(NSApp.isActive ? "vorn" : "hinten"), Schlüsselfenster "
                    + "\(NSApp.keyWindow === hauptfenster() ? "Hauptfenster" : "anderes"), " + eintragJetzt()
                taste("l", code: 37, [.command], in: hauptfenster())
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                if hauptfenster()?.attachedSheet == nil {
                    pruefen(false, "⌘L öffnet das Blatt „Lernende“ — vor dem Kürzel: \(vorKuerzel)")
                    // Nachgestellt: das Menü nachführen wie beim Öffnen, dann noch einmal.
                    let nachgefuehrt = eintragAktiv()
                    taste("l", code: 37, [.command], in: hauptfenster())
                    for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                    zeilen.append("      nach dem Nachführen des Menüs: Eintrag \(nachgefuehrt.map { $0 ? "aktiv" : "grau" } ?? "fehlt"), "
                                  + "⌘L öffnet \(hauptfenster()?.attachedSheet == nil ? "wieder nichts" : "das Blatt")")
                }
                guard let blatt = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende else {
                    pruefen(false, "Blatt „Lernende“ offen (Dialog \(speicher.offenerDialog?.rawValue ?? "—"))")
                    await ende()
                    return
                }
                blatt.makeKeyAndOrderFront(nil)
                // Warten, bis das Feld steht — nicht eine feste Zeit (B81, W4-05).
                for _ in 0..<20 where suchen(blatt.contentView, NSTextField.self, { $0.placeholderString == "Neue Lerngruppe" }) == nil {
                    await warten(150)
                }
                pruefen(speicher.lernendenblattOffen, "das Blatt „Lernende“ führt seinen Verlauf")

                guard let feld = suchen(blatt.contentView, NSTextField.self, { $0.placeholderString == "Neue Lerngruppe" }) else {
                    pruefen(false, "Feld „Neue Lerngruppe“ gefunden")
                    await ende()
                    return
                }
                blatt.makeFirstResponder(feld)
                await warten(200)
                tippen("Probe 7c\n", in: blatt)
                for _ in 0..<20 where speicher.lernendenverlauf.naechsterName != Schrittname.lerngruppeAnlegen { await warten(150) }
                pruefen(speicher.lernendenverlauf.naechsterName == Schrittname.lerngruppeAnlegen
                        && speicher.offenerDialog == .lernende,
                        "Gruppe „Probe 7c“ mit ⏎ angelegt — ein Schritt im Verlauf des Blatts, das Blatt bleibt")

                // Die Eingabe der Namen erscheint mit der neuen Gruppe — warten, bis sie steht (Z14f-02).
                var namensfeld: NSTextView?
                for _ in 0..<20 {
                    namensfeld = suchen(blatt.contentView, NSTextView.self, { $0.isEditable && !$0.isFieldEditor })
                    if namensfeld != nil { break }
                    await warten(150)
                }
                guard let liste = namensfeld else {
                    pruefen(false, "Eingabe der Namen steht")
                    await ende()
                    return
                }
                blatt.makeFirstResponder(liste)
                await warten(200)
                tippen("Abel, Anna\nMax Mustermann\nvan der Berg, Lena", in: blatt)
                await warten(600)
                pruefen(liste.string.split(separator: "\n").count == 3, "drei Zeilen getippt")

                // E303 (Z14b-06): Ein echter Klick auf eine andere Gruppe fragt zuerst; „Weiter bearbeiten“ lässt alles.
                var tabellen: [NSTableView] = []
                @MainActor func tabellenSammeln(_ ansicht: NSView) {
                    if let tabelle = ansicht as? NSTableView, !tabelle.isHiddenOrHasHiddenAncestor { tabellen.append(tabelle) }
                    ansicht.subviews.forEach(tabellenSammeln)
                }
                if let inhalt = blatt.contentView { tabellenSammeln(inhalt) }
                // Die Gruppenliste steht links im Blatt.
                if let gruppentabelle = tabellen.min(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }),
                   gruppentabelle.numberOfRows > 1 {
                    let vorher = gruppentabelle.selectedRow
                    let zeile = gruppentabelle.rect(ofRow: vorher == 0 ? 1 : 0)
                    let punkt = gruppentabelle.convert(NSPoint(x: zeile.midX, y: zeile.midY), to: nil)
                    let getroffen = blatt.contentView?.superview?.hitTest(punkt)?.isDescendant(of: gruppentabelle) == true
                    for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                                             windowNumber: blatt.windowNumber, context: nil, eventNumber: 0,
                                                             clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                            NSApp.postEvent(ereignis, atStart: false)
                        }
                    }
                    for _ in 0..<12 where speicher.rueckfrage == nil { await warten(250) }
                    pruefen(getroffen && speicher.rueckfrage?.text == "Die eingegebenen Namen verwerfen?"
                            && speicher.rueckfrage?.ablehnung == "Weiter bearbeiten",
                            "Klick auf eine andere Gruppe bei getippter Liste: erst „Die eingegebenen Namen verwerfen?“ (E303)")
                    // ⌘Q, während die Frage als Alert steht: Die Frage bleibt, die App auch (E315, B82).
                    let stehend = speicher.rueckfrage?.id
                    speicher.beenden()
                    await warten(400)
                    pruefen(stehend != nil && speicher.rueckfrage?.id == stehend && speicher.offenerDialog == .lernende
                            && Pruefstaende.alertfenster() != nil,
                            "⌘Q bei stehender Rückfrage: Die Rückfrage bleibt stehen, das Blatt auch (E315)")
                    pruefen(Pruefstaende.alertfenster() != nil && !Planungsspeicher.bogenAmBlatt(),
                            "die Rückfrage am Blatt zählt nicht als Bogen (Z-AS3-14)")
                    // ⌘Z über das Menü, während die Frage steht: Nichts geschieht — keine zweite Frage,
                    // die getippten Namen bleiben (E317, E318).
                    let abgeprallt = speicher.gesperrteBefehle
                    taste("z", code: 6, [.command], in: Pruefstaende.alertfenster())
                    await warten(500)
                    // Der Zähler belegt, dass ⌘Z die Sperre erreichte — nicht nur, dass nichts geschah (Z14c4-05).
                    pruefen(speicher.gesperrteBefehle == abgeprallt + 1
                            && speicher.rueckfrage?.id == stehend && speicher.wartendeRueckfragen.isEmpty
                            && liste.string.split(separator: "\n").count == 3 && Pruefstaende.alertfenster() != nil,
                            "⌘Z bei sichtbarer Rückfrage: Nichts geschieht, die Namen bleiben (E317)")
                    if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) { pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden") }
                    await warten(500)
                    pruefen(getroffen && gruppentabelle.selectedRow == vorher && liste.string.split(separator: "\n").count == 3,
                            "„Weiter bearbeiten“: Die Gruppe bleibt gewählt, die Namen stehen")
                } else {
                    pruefen(false, "Gruppenliste im Blatt gefunden (\(tabellen.count) Tabellen)")
                }

                // E300 mit getippter Liste (Z14b-02, Z14b-14): ⌘Q fragt zuerst nach den Namen; „Verwerfen“ führt —
                // nach dem Schließen dieser Frage — zur Frage nach den Änderungen; „Abbrechen“: Blatt und App bleiben.
                speicher.beenden()
                for _ in 0..<8 where speicher.rueckfrage == nil { await warten(250) }
                pruefen(speicher.rueckfrage?.text == "Die eingegebenen Namen verwerfen?" && speicher.offenerDialog == .lernende,
                        "⌘Q mit getippter Liste: Erst die Frage nach den Namen, das Blatt steht")
                if let fehlt = await Pruefstaende.vonHandAntworten(speicher, true) { pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden") }
                // Im Klick hing das Alert noch — verworfen wird erst nach seinem Schließen (B95, E431, Z-AU4a-04).
                // Am Zustand gelesen: Der Text des Feldes folgt ihm erst im nächsten Durchlauf (Z-AU4a-09).
                pruefen(speicher.lernendenblattGriff?.namenOffen() == true,
                        "⌘Q, „Verwerfen“: im Klick noch nicht verworfen — erst nach dem Schließen des Alerts")
                // Verwerfen nach dem Alert, dann die Fortsetzung: höchstens 0,35 + 2,5 + 0,35 s (Z-AU4a-08).
                for _ in 0..<16 where speicher.rueckfrage?.text.hasPrefix("Die Änderungen an den Lernenden") != true {
                    await warten(250)
                }
                pruefen(speicher.rueckfrage?.text.hasPrefix("Die Änderungen an den Lernenden übernehmen?") == true,
                        "„Verwerfen“: danach die Frage nach den Änderungen (E300)")
                if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) { pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden") }
                await warten(400)
                pruefen(speicher.offenerDialog == .lernende && liste.string.isEmpty, "„Abbrechen“: Das Blatt steht, die Namen sind verworfen")
                // Die Namen noch einmal, für das Eintragen — das Feld neu gesucht, falls es neu entstand.
                let neueListe = suchen(blatt.contentView, NSTextView.self, { $0.isEditable && !$0.isFieldEditor }) ?? liste
                blatt.makeFirstResponder(neueListe)
                await warten(200)
                tippen("Abel, Anna\nMax Mustermann\nvan der Berg, Lena", in: blatt)
                await warten(600)
                pruefen(neueListe.string.split(separator: "\n").count == 3, "drei Zeilen neu getippt")
                taste("\r", code: 36, [.command], in: blatt)
                await warten(900)
                pruefen(speicher.lernendenverlauf.naechsterName == Schrittname.namenEintragen,
                        "⌘⏎ trägt die Namen ein (\(speicher.lernendenverlauf.naechsterName ?? "—"))")

                // E300 (Z14b-06): ⌘Q mit geändertem Blatt — Übernehmen, Verwerfen oder Abbrechen; „Abbrechen“: Alles bleibt.
                speicher.beenden()
                for _ in 0..<8 where speicher.rueckfrage == nil { await warten(250) }
                pruefen(speicher.rueckfrage?.text.hasPrefix("Die Änderungen an den Lernenden übernehmen?") == true
                        && speicher.rueckfrage?.weitere == "Verwerfen" && speicher.rueckfrage?.ablehnung == "Abbrechen",
                        "⌘Q mit geändertem Blatt: „Die Änderungen an den Lernenden übernehmen?“ (E300)")
                if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) { pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden") }
                await warten(400)
                pruefen(speicher.offenerDialog == .lernende && speicher.lernendenblattOffen, "„Abbrechen“: Blatt und App bleiben")

                // ⌘Z gehört dem Blatt, nicht der Planung dahinter.
                blatt.makeFirstResponder(nil)
                await warten(200)
                taste("z", code: 6, [.command], in: blatt)
                await warten(600)
                pruefen(speicher.wiederholenTitel == "Wiederholen: \(Schrittname.namenEintragen)"
                        && speicher.verlauf.naechsterName == hauptschritt,
                        "⌘Z nimmt „Namen eintragen“ im Blatt zurück, die Planung bleibt")
                speicher.wiederholen()
                await warten(400)
                pruefen(speicher.widerrufenTitel == "Widerrufen: \(Schrittname.namenEintragen)", "und wiederholt")

                // ⏎ übernimmt.
                blatt.makeFirstResponder(nil)
                taste("\r", code: 36, in: blatt)
                for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                pruefen(speicher.offenerDialog == nil && !speicher.lernendenblattOffen && !speicher.lernendenverlauf.kannZurueck,
                        "⏎ übernimmt; das Blatt geht, sein Verlauf mit")
                let neu = speicher.lernende.bestand
                let gruppe = neu?.lerngruppen.first { $0.name == "Probe 7c" }
                let namen = Set((gruppe?.mitglieder ?? []).compactMap { id in
                    neu?.lernende.first { $0.id == id }.map { "\($0.vorname)|\($0.nachname)" }
                })
                pruefen(gruppe?.art == .klasse && namen == ["Anna|Abel", "Max|Mustermann", "Lena|van der Berg"],
                        "Jahresdatei: „Probe 7c“ mit Anna Abel, Max Mustermann, Lena van der Berg (\(namen.sorted()))")
                pruefen(neu?.lernende.count == 15, "15 Personen (\(neu?.lernende.count ?? 0))")
                let nachher = kennung(ablage.lernende)
                pruefen(nachher?.inhalt == "lernende" && nachher?.kennung == tresor.kennungHex,
                        "geschrieben als Behälter „lernende“ unter dem Schlüssel der Sitzung")
                let frisch = Lernendendienst(ablage: ablage)
                _ = frisch.oeffnen(mit: tresor, stempel: "probe")
                pruefen(frisch.bestand == neu, "ein frischer Dienst liest denselben Stand")
                pruefen(!speicher.verlauf.zurueck.contains { $0.name == Schrittname.namenEintragen }
                        && speicher.verlauf.naechsterName == hauptschritt,
                        "der Verlauf der Planung trägt keinen Schritt des Blatts")
                let aktiv = eintragAktiv()
                pruefen(aktiv == true, "Menüeintrag „Planung → Lernende …“ aktiv (\(aktiv.map { $0 ? "aktiv" : "grau" } ?? "fehlt"))")

                /// Einen Umschalter so bedienen, wie ein Klick es täte: Segment wählen, Handlung senden.
                @MainActor func waehlen(_ schalter: NSSegmentedControl, _ beschriftung: String) -> Bool {
                    guard let stelle = (0..<schalter.segmentCount).first(where: { schalter.label(forSegment: $0) == beschriftung })
                    else { return false }
                    schalter.selectedSegment = stelle
                    return schalter.sendAction(schalter.action, to: schalter.target)
                }

                // ── „Übernehmen“ mit getippter Liste (B106, E457, E458): in einer neuen Gruppe erst mit fehlerhafter
                // Zeile — das Blatt bleibt, die Liste auch, eine Warnung nennt die Zeile —, dann verdeckt: Die Liste
                // kommt nach vorn (Z-AV2a-01), dann lesbar: eingetragen und übernommen, keine Frage. Die Schreibmarke
                // geht vorher aus der Liste (dort machte ⏎ eine neue Zeile), dann drückt ⏎ „Übernehmen“ — gleich
                // einem Klick bei Schreibmarke in der Liste, weil diese ihren Text bei jedem Tastendruck in die
                // Bindung schreibt (Z-AV2a-04). ──
                taste("l", code: 37, [.command], in: hauptfenster())
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                if let blatt10 = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende {
                    blatt10.makeKeyAndOrderFront(nil)
                    for _ in 0..<20 where suchen(blatt10.contentView, NSTextField.self, { $0.placeholderString == "Neue Lerngruppe" }) == nil {
                        await warten(150)
                    }
                    if let feld10 = suchen(blatt10.contentView, NSTextField.self, { $0.placeholderString == "Neue Lerngruppe" }) {
                        blatt10.makeFirstResponder(feld10)
                        await warten(200)
                        tippen("Probe 7d\n", in: blatt10)
                        for _ in 0..<20 where speicher.lernendenverlauf.naechsterName != Schrittname.lerngruppeAnlegen { await warten(150) }
                    }
                    // Die Eingabe der Namen erscheint mit der neuen Gruppe — warten, bis sie steht (Z14f-02).
                    var namensfeld10: NSTextView?
                    for _ in 0..<20 where speicher.lernendenverlauf.naechsterName == Schrittname.lerngruppeAnlegen {
                        namensfeld10 = suchen(blatt10.contentView, NSTextView.self, { $0.isEditable && !$0.isFieldEditor })
                        if namensfeld10 != nil { break }
                        await warten(150)
                    }
                    if let liste10 = namensfeld10 {
                        // Teil 1: Zeile 2 ist nur ein Wort — die Vorschau zeigt sie rot, „Eintragen“ ist gesperrt.
                        let fehlerhaft = "Okafor, Chidi\nPetersen"
                        blatt10.makeFirstResponder(liste10)
                        await warten(200)
                        tippen(fehlerhaft, in: blatt10)
                        await warten(600)
                        let bekannt = Set(speicher.meldungen.map(\.id))
                        let schritte = speicher.lernendenverlauf.zurueck.count
                        blatt10.makeFirstResponder(nil)
                        await warten(200)
                        taste("\r", code: 36, in: blatt10)
                        for _ in 0..<12 where speicher.rueckfrage == nil && speicher.meldungen.allSatisfy({ bekannt.contains($0.id) }) {
                            await warten(250)
                        }
                        // Folgte doch eine Frage, stünde sie jetzt.
                        await warten(600)
                        let warnung = speicher.meldungen.first { !bekannt.contains($0.id) }
                        let gefragt1 = speicher.rueckfrage?.text
                        pruefen(gefragt1 == nil && hauptfenster()?.attachedSheet === blatt10 && speicher.offenerDialog == .lernende
                                && liste10.string == fehlerhaft && speicher.lernendenverlauf.zurueck.count == schritte
                                && speicher.lernende.bestand?.lerngruppen.contains { $0.name == "Probe 7d" } == false,
                                "„Übernehmen“ mit fehlerhafter Zeile: Das Blatt bleibt, die Liste unverändert, nichts eingetragen "
                                + "oder übernommen, keine Frage (E458)" + (gefragt1.map { " — gefragt: „\($0)“" } ?? ""))
                        pruefen(warnung?.art == .warnung && warnung?.text == "Zeile 2 lässt sich nicht eintragen — nichts übernommen.",
                                "… die Warnung nennt die Zeile: „\(warnung?.text ?? "keine")“")
                        // Kam doch eine Frage: „Weiter bearbeiten“ wie von Hand — die Liste bleibt.
                        if gefragt1 != nil, let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) {
                            pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                        }
                        await warten(400)
                        @MainActor func eingabe10() -> NSTextView? {
                            suchen(blatt10.contentView, NSTextView.self, { $0.isEditable && !$0.isFieldEditor })
                        }
                        /// Die Liste verdecken, dann ⏎: ob sie davor verdeckt war, die neue Meldung, die Liste danach.
                        @MainActor func verdecktUebernehmen(_ beschriftung: String) async
                            -> (verdeckt: Bool, meldung: Meldung?, liste: String?) {
                            guard let schalter = suchen(blatt10.contentView, NSSegmentedControl.self, {
                                $0.segmentCount == 3 && $0.label(forSegment: 1) == beschriftung }),
                                  waehlen(schalter, beschriftung) else { return (false, nil, nil) }
                            for _ in 0..<20 where eingabe10() != nil { await warten(150) }
                            let verdeckt = eingabe10() == nil
                            let vorher = Set(speicher.meldungen.map(\.id))
                            blatt10.makeFirstResponder(nil)
                            await warten(200)
                            taste("\r", code: 36, in: blatt10)
                            for _ in 0..<12 where speicher.rueckfrage == nil && speicher.meldungen.allSatisfy({ vorher.contains($0.id) }) {
                                await warten(250)
                            }
                            for _ in 0..<20 where eingabe10() == nil { await warten(150) }
                            await warten(600)
                            return (verdeckt, speicher.meldungen.first { !vorher.contains($0.id) }, eingabe10()?.string)
                        }
                        // Teil 1a: dieselbe Liste hinter „Alle Lernenden“ — „Übernehmen“ holt die rote Zeile nach vorn.
                        let teil1a = await verdecktUebernehmen("Alle Lernenden")
                        let gefragt1a = speicher.rueckfrage?.text
                        pruefen(teil1a.verdeckt && teil1a.liste == fehlerhaft && gefragt1a == nil && hauptfenster()?.attachedSheet === blatt10
                                && speicher.lernendenverlauf.zurueck.count == schritte,
                                "„Übernehmen“ mit verdeckter fehlerhafter Liste: wieder vorn, nichts eingetragen, keine Frage "
                                + "(Z-AV2a-01)" + (teil1a.verdeckt ? "" : " — nicht verdeckt") + (gefragt1a.map { " — gefragt: „\($0)“" } ?? ""))
                        pruefen(teil1a.meldung?.art == .warnung && teil1a.meldung?.text == "Zeile 2 lässt sich nicht eintragen — nichts übernommen.",
                                "… dieselbe Warnung: „\(teil1a.meldung?.text ?? "keine")“")
                        if gefragt1a != nil, let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) {
                            pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                        }
                        await warten(400)
                        // Teil 1b: die Liste lesbar hinter „Mitteilungen“ — „Übernehmen“ holt sie nach vorn und sagt es,
                        // eingetragen wird nichts.
                        let lesbar = "Okafor, Chidi\nJonas Petersen"
                        let liste10b = eingabe10() ?? liste10
                        blatt10.makeFirstResponder(liste10b)
                        await warten(200)
                        liste10b.selectAll(nil)
                        tippen(lesbar, in: blatt10)
                        await warten(600)
                        let teil1b = await verdecktUebernehmen("Mitteilungen")
                        let gefragt1b = speicher.rueckfrage?.text
                        pruefen(teil1b.verdeckt && teil1b.liste == lesbar && gefragt1b == nil && hauptfenster()?.attachedSheet === blatt10
                                && speicher.lernendenverlauf.zurueck.count == schritte
                                && speicher.lernende.bestand?.lerngruppen.contains { $0.name == "Probe 7d" } == false,
                                "„Übernehmen“ mit verdeckter lesbarer Liste: wieder vorn, nichts eingetragen oder übernommen, "
                                + "keine Frage (Z-AV2a-01)" + (teil1b.verdeckt ? "" : " — nicht verdeckt")
                                + (gefragt1b.map { " — gefragt: „\($0)“" } ?? ""))
                        pruefen(teil1b.meldung?.art == .hinweis
                                && teil1b.meldung?.text == "Die getippten Namen sind noch nicht eingetragen — „Übernehmen“ trägt sie ein.",
                                "… der Hinweis: „\(teil1b.meldung?.text ?? "keiner")“")
                        if gefragt1b != nil, let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) {
                            pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                        }
                        await warten(400)
                        // Teil 2: Die Liste steht vorn — „Übernehmen“ trägt ein und übernimmt (E457).
                        let getippt = eingabe10()?.string
                        blatt10.makeFirstResponder(nil)
                        await warten(200)
                        var gefragt2: String?
                        taste("\r", code: 36, in: blatt10)
                        for _ in 0..<20 where hauptfenster()?.attachedSheet != nil {
                            if let frage = speicher.rueckfrage?.text {
                                gefragt2 = frage
                                break
                            }
                            await warten(250)
                        }
                        let nach10 = speicher.lernende.bestand
                        let gruppe10 = nach10?.lerngruppen.first { $0.name == "Probe 7d" }
                        let namen10 = (gruppe10?.mitglieder ?? []).compactMap { id in
                            nach10?.lernende.first { $0.id == id }.map { "\($0.vorname) \($0.nachname)" }
                        }
                        let frisch10 = Lernendendienst(ablage: ablage)
                        _ = frisch10.oeffnen(mit: tresor, stempel: "probe-e457")
                        pruefen(getippt == lesbar && gefragt2 == nil && speicher.rueckfrage == nil && speicher.offenerDialog == nil
                                && hauptfenster()?.attachedSheet == nil && !speicher.lernendenblattOffen,
                                "„Übernehmen“ mit lesbarer Liste: Keine Frage, das Blatt geht (E457)"
                                + (gefragt2.map { " — gefragt: „\($0)“" } ?? ""))
                        pruefen(namen10 == ["Chidi Okafor", "Jonas Petersen"] && nach10?.lernende.count == 17 && frisch10.bestand == nach10,
                                "… eingetragen und übernommen: „Probe 7d“ mit \(namen10) — \(nach10?.lernende.count ?? 0) Personen, "
                                + "ein frischer Dienst liest denselben Stand")
                        // Wie vor E457 gefragt: „Weiter bearbeiten“, dann das Blatt schließen — der Lauf geht weiter wie bisher.
                        if gefragt2 != nil || hauptfenster()?.attachedSheet != nil {
                            if speicher.rueckfrage != nil, let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) {
                                pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                            }
                            if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                        }
                    } else {
                        pruefen(false, "Gruppe „Probe 7d“ angelegt, Eingabe der Namen steht "
                                + "(\(speicher.lernendenverlauf.naechsterName ?? "—"))")
                        if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                    }
                } else {
                    pruefen(false, "⌘L öffnet das Blatt für „Übernehmen“ mit getippter Liste")
                }

                // ── Rücklauf (AP8): Mitteilung anlegen, drei Rückläufe eintragen ──
                @MainActor func namensliste() -> [String] {
                    (speicher.lernende.bestand?.lernende ?? []).map { "\($0.id)|\($0.nachname)|\($0.vorname)" }
                }
                let namenVorher = namensliste()
                taste("l", code: 37, [.command], in: hauptfenster())
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                guard let blatt2 = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende else {
                    pruefen(false, "⌘L öffnet das Blatt ein zweites Mal")
                    await ende()
                    return
                }
                blatt2.makeKeyAndOrderFront(nil)
                // Je warten, bis das Element steht — nicht fest (Z14f-03).
                @MainActor func teilwahl() -> NSSegmentedControl? {
                    suchen(blatt2.contentView, NSSegmentedControl.self, { $0.segmentCount == 3 && $0.label(forSegment: 1) == "Mitteilungen" })
                }
                for _ in 0..<40 where teilwahl() == nil { await warten(250) }
                guard let teil = teilwahl(), waehlen(teil, "Mitteilungen") else {
                    pruefen(false, "Umschalter „Mitglieder / Mitteilungen / Maßnahmen“ gefunden und bedient")
                    await ende()
                    return
                }
                for _ in 0..<40 where suchen(blatt2.contentView, NSTextField.self, { $0.placeholderString == "Neue Mitteilung" }) == nil {
                    await warten(250)
                }
                guard let neuFeld = suchen(blatt2.contentView, NSTextField.self, { $0.placeholderString == "Neue Mitteilung" }) else {
                    pruefen(false, "Feld „Neue Mitteilung“ gefunden")
                    await ende()
                    return
                }
                blatt2.makeFirstResponder(neuFeld)
                await warten(200)
                tippen("Rücklauf Probe\n", in: blatt2)
                @MainActor func ruecklaufliste() -> NSTableView? {
                    suchen(blatt2.contentView, NSTableView.self, { $0.numberOfColumns >= 2 && $0.tableColumns.first?.title == "Name" })
                }
                for _ in 0..<40 where speicher.lernendenverlauf.naechsterName != Schrittname.mitteilungAnlegen
                    || ruecklaufliste() == nil { await warten(250) }
                pruefen(speicher.lernendenverlauf.naechsterName == Schrittname.mitteilungAnlegen,
                        "Mitteilung „Rücklauf Probe“ mit ⏎ angelegt (\(speicher.lernendenverlauf.naechsterName ?? "—"))")
                guard let tabelle = ruecklaufliste() else {
                    var gesehen: [String] = []
                    @MainActor func sammeln(_ a: NSView) {
                        if let t = a as? NSTableView { gesehen.append(t.tableColumns.map(\.title).joined(separator: "|")) }
                        a.subviews.forEach(sammeln)
                    }
                    if let inhalt = blatt2.contentView { sammeln(inhalt) }
                    pruefen(false, "Rücklaufliste gefunden (Tabellen: \(gesehen))")
                    await ende()
                    return
                }
                var vorigeKennung: String?
                for (zeile, stand) in [(0, "erledigt"), (1, "abgelehnt"), (2, "erledigt")] {
                    tabelle.selectRowIndexes(IndexSet(integer: zeile), byExtendingSelection: false)
                    // Die Leiste gehört erst zur gewählten Zeile, wenn sie deren Stand zeigt: Alle drei
                    // stehen noch auf „offen“, die vorige nicht mehr (Z14f-03).
                    @MainActor func standwahl() -> NSSegmentedControl? {
                        suchen(blatt2.contentView, NSSegmentedControl.self, { $0.segmentCount == 3 && $0.label(forSegment: 0) == "offen" })
                    }
                    for _ in 0..<24 where standwahl()?.selectedSegment != 0 { await warten(250) }
                    let vorher = speicher.lernendenverlauf.zurueck.count
                    guard let schalter = standwahl(), schalter.selectedSegment == 0, waehlen(schalter, stand) else {
                        pruefen(false, "Stand „\(stand)“ in Zeile \(zeile + 1) gewählt")
                        continue
                    }
                    for _ in 0..<20 where speicher.lernendenverlauf.zurueck.count == vorher { await warten(150) }
                    // Eine neue Zeile — nicht die vorige noch einmal, deren Leiste nach einem ✗ wieder „offen“ zeigt (Z-AS1-15).
                    let kennung = speicher.lernendenverlauf.zurueck.last?.kennung
                    pruefen(speicher.lernendenverlauf.zurueck.count == vorher + 1 && kennung != nil && kennung != vorigeKennung,
                            "Stand „\(stand)“ in Zeile \(zeile + 1) eingetragen")
                    vorigeKennung = kennung
                }
                let schritte = speicher.lernendenverlauf.zurueck.suffix(3).map(\.name)
                pruefen(schritte == Array(repeating: Schrittname.ruecklaufEintragen, count: 3),
                        "drei Rückläufe über die Leiste eingetragen — drei Schritte im Verlauf des Blatts (\(schritte))")
                // Je Mitteilung der Gruppe eine Spalte, jede fest 130 breit wie die Stand-Spalten der Maßnahmen (E641) — ob
                // „abgelehnt“ hineinpasst, zeigen Abbild und Sichtprüfung (Z-AW5b-04).
                let breiten = tabelle.tableColumns.dropFirst().map { Int($0.width.rounded()) }
                let entwurfJetzt = speicher.lernendenblattGriff?.aenderungen()
                let gruppeJetzt = entwurfJetzt?.anliegen.first { $0.titel == "Rücklauf Probe" }?.lerngruppe
                let spaltenSoll = entwurfJetzt.flatMap { e in gruppeJetzt.map { Lernendenverzeichnis(e).mitteilungen(der: $0).count } }
                pruefen(breiten.count == spaltenSoll && breiten.allSatisfy { $0 == 130 },
                        "je Mitteilung eine Spalte, fest 130 breit wie die Stand-Spalten der Maßnahmen (E641): \(breiten), "
                        + "Mitteilungen der Gruppe: \(spaltenSoll.map(String.init) ?? "—")")
                // Der Kopf der neuen Mitteilung (die letzte Spalte) mit dem Tag vorn (E739, Z-AW5bN-02).
                let kopfSoll = entwurfJetzt?.anliegen.first { $0.titel == "Rücklauf Probe" }.map(Ruecklaufliste.kopftitel)
                let kopfIst = tabelle.tableColumns.last?.title
                pruefen(kopfSoll != nil && kopfIst == kopfSoll,
                        "Kopf der neuen Mitteilung mit dem Tag vorn (E739): „\(kopfIst ?? "—")“, erwartet „\(kopfSoll ?? "—")“")
                // E280: Ein echter Klick auf den Stand in der Tabelle öffnet die drei Stände —
                // vierte Zeile, Spalte der neuen Mitteilung (die letzte). Gewählt wird im
                // offenen Menü, sobald AppKit es meldet, wie mit der Hand.
                let vorKlick = speicher.lernendenverlauf.zurueck.count
                let kasten = Menuekasten()
                let beobachter = NotificationCenter.default.addObserver(
                    forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { meldung in
                    // Gemeldet auf dem Hauptstrang, der das Menü führt.
                    nonisolated(unsafe) let menue = meldung.object as? NSMenu
                    MainActor.assumeIsolated { if let menue { kasten.bedienen(menue, "erledigt") } }
                }
                let endet = NotificationCenter.default.addObserver(
                    forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { _ in
                    MainActor.assumeIsolated { kasten.zu = true }
                }
                // Der Klickpunkt liegt in der Zelle des Stands — per hitTest geprüft, nicht geraten (W4-05).
                // Ob er die Marke trifft, beweist erst das Menü danach (Z14d-02).
                let rahmen = tabelle.convert(tabelle.frameOfCell(atColumn: tabelle.numberOfColumns - 1, row: 3), to: nil)
                let wurzel = blatt2.contentView?.superview
                let zelle = tabelle.view(atColumn: tabelle.numberOfColumns - 1, row: 3, makeIfNecessary: false)
                @MainActor func inDerZelle(_ p: NSPoint) -> Bool {
                    guard let zelle, let treffer = wurzel?.hitTest(p) else { return false }
                    return treffer === zelle || treffer.isDescendant(of: zelle)
                }
                let punkt = [rahmen.minX + 24, rahmen.midX, rahmen.minX + 12].map { NSPoint(x: $0, y: rahmen.midY) }
                    .first(where: inDerZelle) ?? NSPoint(x: rahmen.minX + 24, y: rahmen.midY)
                pruefen(inDerZelle(punkt),
                        "der Klickpunkt liegt in der Zelle des Stands, Zeile 4 (\(wurzel?.hitTest(punkt).map { String(describing: type(of: $0)) } ?? "nichts"))")
                for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: blatt2.windowNumber, context: nil, eventNumber: 0,
                                                         clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                        NSApp.postEvent(ereignis, atStart: false)
                    }
                }
                for _ in 0..<20 where !kasten.zu || speicher.lernendenverlauf.zurueck.count == vorKlick { await warten(250) }
                await warten(400)
                NotificationCenter.default.removeObserver(beobachter)
                NotificationCenter.default.removeObserver(endet)
                pruefen(kasten.gewaehlt && kasten.zu && speicher.lernendenverlauf.zurueck.count == vorKlick + 1
                        && speicher.lernendenverlauf.naechsterName == Schrittname.ruecklaufEintragen,
                        "Klick auf den Stand in der Tabelle: Menü \(kasten.titel), mit ↓ und ⏎ „erledigt“ gewählt, "
                        + "gilt sofort (E280) — gewählt \(kasten.gewaehlt), zu \(kasten.zu), Schritte "
                        + "\(vorKlick) → \(speicher.lernendenverlauf.zurueck.count): "
                        + speicher.lernendenverlauf.zurueck.dropFirst(vorKlick).map { "\($0.name) [\($0.kennung ?? "—")]" }
                            .joined(separator: ", "))
                blatt2.makeFirstResponder(nil)
                taste("\r", code: 36, in: blatt2)
                for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                let mitRuecklauf = speicher.lernende.bestand
                let mitteilung = mitRuecklauf?.anliegen.first { $0.titel == "Rücklauf Probe" }
                let gruppeDerMitteilung = mitRuecklauf?.lerngruppen.first { $0.id == mitteilung?.lerngruppe }
                pruefen(mitteilung?.art == .mitteilung && mitteilung?.datum == Tag.heute.iso
                        && mitteilung?.betroffene.count == gruppeDerMitteilung?.mitglieder.count,
                        "Mitteilung mit dem heutigen Tag an alle \(gruppeDerMitteilung?.mitglieder.count ?? 0) Mitglieder "
                        + "von „\(gruppeDerMitteilung?.beschriftung ?? "—")“")
                let rueck = mitRuecklauf?.rueckmeldungen.filter { $0.anliegen == mitteilung?.id } ?? []
                pruefen(rueck.count == 4 && rueck.filter { $0.stand == .erledigt }.count == 3
                        && rueck.filter { $0.stand == .abgelehnt }.count == 1 && rueck.allSatisfy { $0.datum == Tag.heute.iso },
                        "Mitteilung mit drei Rückläufen und einem per Klick: 3 erledigt, 1 abgelehnt, je mit dem heutigen Tag "
                        + "— übernommen und versiegelt (\(rueck.count))")
                let geaendert = zip(namenVorher, namensliste()).filter { $0 != $1 }.map { "\($0.0) → \($0.1)" }
                pruefen(geaendert.isEmpty && namenVorher.count == namensliste().count,
                        "die Namen aller Personen sind unverändert (B74)\(geaendert.isEmpty ? "" : ": \(geaendert)")")
                let frischer = Lernendendienst(ablage: ablage)
                _ = frischer.oeffnen(mit: tresor, stempel: "probe-ap8")
                pruefen(frischer.bestand == mitRuecklauf, "ein frischer Dienst liest auch die Rückläufe")

                // ── Rückmeldungsliste (AW5, E401, E408): der Bogen am Blatt; ohne Auswahl bewirkt ⏎ nichts, ⎋ schließt;
                // mit Auswahl und Kennwort folgt auf ⏎ das Sichern-Fenster am Blatt — abgebrochen, keine Datei ──
                if let mitteilung, let gruppeDerMitteilung {
                    let kennwort = "Probe-Liste-2026"
                    /// Was gerade am Hauptfenster hängt — für ein ✗ (Z-AW5a-08).
                    @MainActor func lage() -> String {
                        let art = { (f: NSWindow?) in f.map { String(describing: type(of: $0)) } ?? "nichts" }
                        let blatt = hauptfenster()?.attachedSheet
                        let griff = speicher.lernendenblattGriff.map { $0.bogenOffen() ? "Bogen offen" : "kein Bogen" } ?? "kein Griff"
                        return "Blatt: \(art(blatt)), darauf: \(art(blatt?.attachedSheet)), Griff: \(griff), Rückfrage "
                            + "\(Pruefstaende.alertfenster() != nil ? "steht" : "keine"), Dialog \(speicher.offenerDialog.map { "\($0)" } ?? "—")"
                    }
                    /// Das Blatt mit der Gruppe der Mitteilung und dem Bogen aus der Vorgabe — statt des Knopfs im Teil
                    /// „Mitteilungen“ über die Vorgabe (Z-AW5a-07). Bis der Bogen steht, nicht fest (Z14f-03).
                    @MainActor func listenbogenOeffnen(_ vorgabe: Rueckmeldungsbogenvorgabe) async -> (NSWindow, NSWindow)? {
                        speicher.lernendenBlattOeffnen(gruppe: gruppeDerMitteilung.id)
                        speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                        speicher.lernendenVorgabe?.rueckmeldungsliste = vorgabe
                        for _ in 0..<24 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                        guard let blatt = hauptfenster()?.attachedSheet, let bogen = blatt.attachedSheet,
                              !(bogen is NSSavePanel), Pruefstaende.alertfenster() == nil else { return nil }
                        return (blatt, bogen)
                    }
                    /// ⏎ an den Bogen, sobald er Schlüsselfenster ist (Z-AW5a-03), und der Stand beim Loslassen der Taste:
                    /// Es folgt dem Drücken in derselben Schlange — die Handlung des Knopfs ist dann gelaufen; ein
                    /// Sichern-Fenster käme erst danach (Z-AW5a-02, Z-AW5aN-01).
                    @MainActor func eingabe(an bogen: NSWindow) async -> Tastenvermerk {
                        let vermerk = Tastenvermerk()
                        bogen.makeKeyAndOrderFront(nil)
                        for _ in 0..<12 where !bogen.isKeyWindow { await warten(50) }
                        guard bogen.isKeyWindow else { return vermerk }
                        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { ereignis in
                            if ereignis.keyCode == 36 {
                                MainActor.assumeIsolated {
                                    vermerk.oben = true
                                    vermerk.bogenOffen = speicher.lernendenblattGriff?.bogenOffen()
                                    vermerk.bogenAmBlatt = bogen.sheetParent?.attachedSheet === bogen
                                }
                            }
                            return ereignis
                        }
                        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
                        taste("\r", code: 36, in: bogen)
                        for _ in 0..<40 where !vermerk.oben { await warten(50) }
                        return vermerk
                    }
                    /// Tat ⏎ doch etwas, kommt das Sichern-Fenster erst nach dem Bogen — abwarten und abbrechen, ehe das Blatt
                    /// geht: Sonst hinge es am schließenden Blatt, und aus einer Ursache würden viele ✗ (Gegenprobe zu Z-AW5a-01).
                    @MainActor func sichernFensterAbbrechen(_ blatt: NSWindow) async {
                        for _ in 0..<24 where !(blatt.attachedSheet is NSSavePanel) { await warten(250) }
                        (blatt.attachedSheet as? NSSavePanel)?.cancel(nil)
                        for _ in 0..<12 where blatt.attachedSheet != nil { await warten(250) }
                    }
                    let vorListe = speicher.lernende.bestand
                    // Ob Öffnen, Bogen und Sichern-Fenster den Entwurf änderten — vor jedem Schließen gelesen, das verwürfe (Z-AW5a-05).
                    var entwurfUnveraendert = true
                    @MainActor func schliessenUndMerken(_ wenn: String) async {
                        entwurfUnveraendert = entwurfUnveraendert && speicher.lernendenblattGriff?.aenderungen() == nil
                        if !(await blattSchliessen()) { zeilen.append("  Blatt \(wenn) nicht geschlossen") }
                    }
                    // Teil A: mit gültigem Kennwort, nichts gewählt — sonst sperrte schon das Kennwort „Als PDF sichern“ (Z-AW5a-01).
                    if case let (blatt, bogen)? = await listenbogenOeffnen(Rueckmeldungsbogenvorgabe(kennwort: kennwort,
                                                                                                  wiederholung: kennwort)) {
                        pruefen(bogen.sheetParent === blatt && Int(bogen.frame.width) == 560,
                                "Bogen „Rückmeldungsliste“ am Blatt „Lernende“, \(Int(bogen.frame.width)) breit")
                        // Auch eine Meldung wäre eine Wirkung — etwa, wenn die Sperre am Knopf fehlte (Z-AW5aN-02).
                        speicher.meldungsfang = []
                        let los = await eingabe(an: bogen)
                        let gefangenA = speicher.meldungsfang ?? []
                        speicher.meldungsfang = nil
                        let angekommen = los.oben
                        let nichts = angekommen && los.bogenOffen == true && los.bogenAmBlatt && gefangenA.isEmpty
                        pruefen(nichts, "nichts vorgewählt: ⏎ bewirkt nichts, kein Sichern-Fenster (E408)" + (nichts ? ""
                            : !angekommen ? " — ⏎ kam nicht an (Schlüsselfenster \(bogen.isKeyWindow ? "ja" : "nein"))"
                            : " — beim Loslassen: Bogen offen \(los.bogenOffen.map { $0 ? "ja" : "nein" } ?? "kein Griff"), "
                              + "am Blatt \(los.bogenAmBlatt ? "ja" : "nein")"
                              + (gefangenA.isEmpty ? "" : ", gemeldet: \(gefangenA.map(\.text))") + " — \(lage())"))
                        // ⎋ nur, wenn ⏎ nichts tat — sonst stünde das Sichern-Fenster, und aus einer Ursache würden zwei ✗.
                        if nichts {
                            taste("\u{1B}", code: 53, in: bogen)
                            for _ in 0..<12 where blatt.attachedSheet != nil { await warten(250) }
                            let zu = blatt.attachedSheet == nil && hauptfenster()?.attachedSheet === blatt
                                && speicher.offenerDialog == .lernende
                            pruefen(zu, "⎋ schließt den Bogen, das Blatt bleibt" + (zu ? "" : " — \(lage())"))
                        } else if angekommen, speicher.lernendenblattGriff?.bogenOffen() != true {
                            // Nur, wenn der Bogen fort ist — sonst kommt kein Sichern-Fenster (Z-AW5aN-04).
                            await sichernFensterAbbrechen(blatt)
                        }
                        await schliessenUndMerken("nach dem Bogen")
                        // Teil B: die Mitteilung gewählt.
                        if case let (blattB, bogenB)? = await listenbogenOeffnen(Rueckmeldungsbogenvorgabe(
                            auswahl: [mitteilung.id], kennwort: kennwort, wiederholung: kennwort)) {
                            let angekommenB = await eingabe(an: bogenB).oben
                            for _ in 0..<24 where angekommenB && !(blattB.attachedSheet is NSSavePanel) { await warten(250) }
                            let name = Rueckmeldungslistenbogen.dateiname(gruppeDerMitteilung)
                            if let panel = blattB.attachedSheet as? NSSavePanel {
                                pruefen(panel.sheetParent === blattB && panel.nameFieldStringValue == name
                                        && panel.message == Rueckmeldungslistenbogen.sichernNachricht,
                                        "⏎ „\(Rueckmeldungslistenbogen.sichernTitel)“: Der Bogen geht, das Sichern-Fenster "
                                        + "hängt am Blatt — „\(panel.nameFieldStringValue)“")
                                // Der Stand der Datei im Ordner des Fensters vorher und nachher; die Meldungen im Fang —
                                // dort verfällt keine (Z-AW5a-04).
                                let datei = panel.directoryURL?.appending(component: name)
                                /// `nil`: keine Datei.
                                @MainActor func dateistand() -> Date? {
                                    guard let datei, FileManager.default.fileExists(atPath: datei.path) else { return nil }
                                    return (try? FileManager.default.attributesOfItem(atPath: datei.path))?[.modificationDate] as? Date
                                        ?? .distantPast
                                }
                                let vorher = dateistand()
                                speicher.meldungsfang = []
                                panel.cancel(nil)
                                for _ in 0..<12 where blattB.attachedSheet != nil { await warten(250) }
                                let gefangen = speicher.meldungsfang ?? []
                                speicher.meldungsfang = nil
                                // Jede verfehlte Bedingung beim Namen (Z-AW5aN-03).
                                var fehlt: [String] = []
                                if datei == nil { fehlt.append("das Sichern-Fenster nennt keinen Ordner") }
                                if blattB.attachedSheet != nil { fehlt.append("das Fenster hängt noch") }
                                if hauptfenster()?.attachedSheet !== blattB { fehlt.append("das Blatt ist nicht mehr oben") }
                                if dateistand() != vorher { fehlt.append("die Datei hat sich geändert") }
                                if !gefangen.isEmpty { fehlt.append("gemeldet: \(gefangen.map(\.text))") }
                                pruefen(fehlt.isEmpty, "abgebrochen: keine Datei, keine Meldung — das Blatt bleibt"
                                        + (fehlt.isEmpty ? "" : " (\(fehlt.joined(separator: "; ")))"))
                            } else {
                                pruefen(false, "Sichern-Fenster am Blatt nach ⏎"
                                        + (angekommenB ? " — \(lage())" : " — ⏎ kam nicht an (Schlüsselfenster \(bogenB.isKeyWindow ? "ja" : "nein"))"))
                                if angekommenB, speicher.lernendenblattGriff?.bogenOffen() != true { await sichernFensterAbbrechen(blattB) }
                            }
                        } else {
                            pruefen(false, "Bogen „Rückmeldungsliste“ mit gewählter Mitteilung am Blatt „Lernende“ — \(lage())")
                        }
                        await schliessenUndMerken("nach dem Sichern-Fenster")
                        // Teil C (B-AW5-01): ⏎ „Als PDF sichern“ und sofort ⎋ — wie eine schnelle Hand. Das Blatt geht oder
                        // bleibt; ein Sichern-Fenster darf nie an einem Blatt hängen, dessen Dialog schon zu ist.
                        if case let (blattC, bogenC)? = await listenbogenOeffnen(Rueckmeldungsbogenvorgabe(
                            auswahl: [mitteilung.id], kennwort: kennwort, wiederholung: kennwort)) {
                            let angekommenC = await eingabe(an: bogenC).oben
                            // In die Lücke: Der Bogen ist fort, das Sichern-Fenster noch nicht da — wie eine Hand, die nach ⏎
                            // kurz zögert. Ein sofortiges ⎋ träfe noch den schließenden Bogen (am Lauf gesehen).
                            // Gezielt: Der Bogen ist vom Blatt gelöst, das Sichern-Fenster hängt noch nicht (G2-02).
                            for _ in 0..<80 where blattC.attachedSheet != nil && !(blattC.attachedSheet is NSSavePanel) { await warten(25) }
                            let inDerLuecke = blattC.attachedSheet == nil
                            taste("\u{1B}", code: 53, in: blattC)
                            // Bis sich etwas setzt: das Blatt fort oder ein Sichern-Fenster an ihm (Eintreten, mit Obergrenze).
                            for _ in 0..<24 where blattC.isVisible && !(blattC.attachedSheet is NSSavePanel) { await warten(250) }
                            let fensterAmBlatt = blattC.attachedSheet is NSSavePanel
                            let verwaist = fensterAmBlatt && speicher.offenerDialog != .lernende
                            pruefen(angekommenC && !verwaist,
                                    "⏎ „\(Rueckmeldungslistenbogen.sichernTitel)“ und sofort ⎋: kein Sichern-Fenster an einem Blatt, "
                                    + "dessen Dialog zu ist (B-AW5-01) — Blatt \(blattC.isVisible ? "steht" : "fort"), Sichern-Fenster "
                                    + "\(fensterAmBlatt ? "am Blatt" : "keins"), Dialog \(speicher.offenerDialog.map { "\($0)" } ?? "—"), "
                                    + "⎋ in der Lücke \(inDerLuecke ? "ja" : "nein")")
                            (blattC.attachedSheet as? NSSavePanel)?.cancel(nil)
                            for _ in 0..<12 where blattC.attachedSheet != nil { await warten(250) }
                            if blattC.isVisible, speicher.offenerDialog != .lernende { hauptfenster()?.endSheet(blattC) }
                            for _ in 0..<12 where blattC.isVisible && speicher.offenerDialog != .lernende { await warten(250) }
                        } else {
                            pruefen(false, "Bogen „Rückmeldungsliste“ für Teil C — \(lage())")
                        }
                        await schliessenUndMerken("nach Teil C")
                    } else {
                        pruefen(false, "Bogen „Rückmeldungsliste“ am Blatt „Lernende“ aus der Vorgabe — \(lage())")
                        await schliessenUndMerken("nach dem Fehlschlag")
                    }
                    pruefen(entwurfUnveraendert && speicher.lernende.bestand == vorListe,
                            "Öffnen, Bogen und Sichern-Fenster ändern weder Entwurf noch Jahresdatei")
                }

                // ── Archiv (AP9): das Vorjahr lesen, eine Person in allen Schuljahren löschen ──
                taste("l", code: 37, [.command], in: hauptfenster())
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                guard let blatt3 = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende else {
                    pruefen(false, "⌘L öffnet das Blatt ein drittes Mal")
                    await ende()
                    return
                }
                blatt3.makeKeyAndOrderFront(nil)
                for _ in 0..<40 where suchen(blatt3.contentView, NSSegmentedControl.self, {
                    $0.segmentCount == 3 && $0.label(forSegment: 2) == "Archiv" }) == nil { await warten(250) }
                guard let oben = suchen(blatt3.contentView, NSSegmentedControl.self, {
                    $0.segmentCount == 3 && $0.label(forSegment: 2) == "Archiv" }), waehlen(oben, "Archiv") else {
                    pruefen(false, "Umschalter „Lerngruppen / Alle Lernenden / Archiv“ gefunden und bedient")
                    await ende()
                    return
                }
                // Warten, bis Tabelle und Schuljahreswahl stehen (B83). Die Wahl baut das System je nach Fassung
                // anders: unter macOS 26 ein NSPopUpButton, unter macOS 27.0 nicht (VM-Runde 121904: „kein
                // Auswahlfeld im Blatt“; Bildschirmfoto des Nutzers: Die Wahl steht auf „2025/26“). Ohne
                // NSPopUpButton wird sie wie von Hand geprüft — ein Klick öffnet ihr Menü (unten).
                var archivtabelle: NSTableView?
                var jahrwahl: NSPopUpButton?
                var tabelleNach: Int?
                var wahlNach: Int?
                for takt in 0..<40 {
                    archivtabelle = suchen(blatt3.contentView, NSTableView.self, {
                        $0.tableColumns.first?.title == "Nachname" && $0.numberOfRows > 0 })
                    if archivtabelle != nil && tabelleNach == nil { tabelleNach = takt }
                    jahrwahl = suchen(blatt3.contentView, NSPopUpButton.self, { $0.itemTitles.contains("2025/26") })
                    if jahrwahl?.titleOfSelectedItem == "2025/26" && wahlNach == nil { wahlNach = takt }
                    if archivtabelle != nil && wahlNach != nil { break }
                    // Ohne NSPopUpButton nicht die ganze Frist warten — eine Sekunde nach der Tabelle genügt.
                    if let ab = tabelleNach, jahrwahl == nil, takt >= ab + 4 { break }
                    await warten(250)
                }
                // Das Menü der Wahl wie von Hand: ein Klick in die Zeile unter dem oberen Umschalter, links und
                // abseits der Knöpfe, abgetastet, bis sich ein Menü öffnet. „2025/26“ muss darin stehen und
                // angehakt sein. Geschlossen wird ohne Wahl (`cancelTracking`) — die Klassenmessung zeigt den Weg
                // unter macOS 26 (SwiftUIMenu) und 27 (NSMenu, die Wahl ohne eigene AppKit-Ansicht). Kein blindes ⎋
                // — im Blatt hieße es „Abbrechen“.
                let rahmenOben = oben.convert(oben.bounds, to: nil)
                @MainActor func menueDerWahl() async -> (titel: [String], angehakt: [String], ort: String)? {
                    // Die Mitte zuerst: Die Wahl ist 24 pt hoch, die Zeilenmitte liegt 36 pt unter der des
                    // Umschalters (Klassenmessung, beide Systeme); 24 und 48 sind ihre Kanten (Z14f-10).
                    for dy in [36.0, 30.0, 42.0, 24.0, 48.0] {
                        for dx in [110.0, 80.0, 140.0] {
                            let punkt = NSPoint(x: rahmenOben.minX + dx, y: rahmenOben.midY - dy)
                            let fang = Menuefang()
                            let beginnt = NotificationCenter.default.addObserver(
                                forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { meldung in
                                // Gemeldet auf dem Hauptstrang, der das Menü führt.
                                nonisolated(unsafe) let menue = meldung.object as? NSMenu
                                MainActor.assumeIsolated {
                                    guard let menue else { return }
                                    fang.menue = menue
                                    fang.titel = menue.items.map(\.title)
                                    fang.angehakt = menue.items.filter { $0.state == .on }.map(\.title)
                                    nonisolated(unsafe) let offen = menue
                                    RunLoop.main.perform(inModes: [.common]) {
                                        MainActor.assumeIsolated { offen.cancelTracking() }
                                    }
                                }
                            }
                            let endet = NotificationCenter.default.addObserver(
                                forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { _ in
                                MainActor.assumeIsolated { fang.zu = true }
                            }
                            for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                                if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                                                     windowNumber: blatt3.windowNumber, context: nil, eventNumber: 0,
                                                                     clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                                    NSApp.postEvent(ereignis, atStart: false)
                                }
                            }
                            for _ in 0..<5 where fang.titel.isEmpty { await warten(150) }
                            if !fang.titel.isEmpty {
                                for _ in 0..<20 where !fang.zu { await warten(150) }
                            }
                            NotificationCenter.default.removeObserver(beginnt)
                            NotificationCenter.default.removeObserver(endet)
                            if !fang.titel.isEmpty {
                                // Blieb es offen, schluckte es ⌘⌫ und ⎋ der folgenden Schritte (Z14f-11).
                                var ort = "+\(Int(dx)) pt, −\(Int(dy)) pt"
                                if !fang.zu {
                                    fang.menue?.cancelTrackingWithoutAnimation()
                                    ort += ", blieb offen und wurde geschlossen"
                                }
                                await warten(400)
                                return (fang.titel, fang.angehakt, ort)
                            }
                        }
                    }
                    return nil
                }
                let menue = await menueDerWahl()
                // Ohne Menü: was unter dem Mittelpunkt liegt und wo der Umschalter steht (Z14f-12).
                let wahlmitte = NSPoint(x: rahmenOben.minX + 110, y: rahmenOben.midY - 36)
                let darunter = blatt3.contentView?.superview?.hitTest(wahlmitte).map { String(describing: type(of: $0)) } ?? "nichts"
                let menuetext = menue.map { "Menü bei \($0.ort): \($0.titel), angehakt \($0.angehakt)" }
                    ?? "kein Menü an 15 Punkten — unter der Mitte \(darunter), Umschalter bei (\(Int(rahmenOben.minX)), "
                    + "\(Int(rahmenOben.minY)), \(Int(rahmenOben.width))×\(Int(rahmenOben.height)))"
                let menueTraegt = menue.map { $0.titel.contains("2025/26") && $0.angehakt == ["2025/26"] } ?? false
                blatt3.makeKeyAndOrderFront(nil)
                let takte = "Tabelle nach Takt \(tabelleNach.map(String.init) ?? "—"), "
                    + "Wahl nach Takt \(wahlNach.map(String.init) ?? "—"), je 250 ms"
                if let w = jahrwahl {
                    pruefen(archivtabelle?.numberOfRows == 3 && w.titleOfSelectedItem == "2025/26",
                            "Archivansicht zeigt das Vorjahr 2025/26 mit drei Personen — gelesen abseits des Hauptstrangs "
                            + "(\(archivtabelle?.numberOfRows ?? 0) Zeilen, Schuljahr \(w.titleOfSelectedItem ?? "—") über "
                            + "NSPopUpButton, \(w.numberOfItems) Einträge; \(takte))")
                    // Zur Auskunft, ohne Wertung: der Weg, der unter macOS 27 prüft, hier am Mac erprobt.
                    let lage = w.convert(w.bounds, to: nil)
                    zeilen.append("  Auskunft, Weg ohne NSPopUpButton: \(menuetext) — trüge \(menueTraegt ? "ja" : "nein"); "
                                  + "NSPopUpButton bei +\(Int(lage.minX - rahmenOben.minX)) bis +\(Int(lage.maxX - rahmenOben.minX)) pt, "
                                  + "−\(Int(rahmenOben.midY - lage.midY)) pt")
                } else {
                    pruefen(archivtabelle?.numberOfRows == 3 && menueTraegt,
                            "Archivansicht zeigt das Vorjahr 2025/26 mit drei Personen — gelesen abseits des Hauptstrangs "
                            + "(\(archivtabelle?.numberOfRows ?? 0) Zeilen; kein NSPopUpButton, Schuljahreswahl wie von Hand: "
                            + "\(menuetext); \(takte))")
                }
                if let tabelle = archivtabelle {
                    tabelle.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    await warten(700)
                    // ⌘⌫ wie von der Tastatur — die Bedienungshilfe zeigt SwiftUIs Knöpfe
                    // im eigenen Prozess nicht (gemessen: zwei Elemente). Den Knopf mit dem Kürzel gibt es erst
                    // mit der Auswahl — bleibt die Frage aus, noch einmal (Z14f-03).
                    for _ in 0..<3 where speicher.rueckfrage == nil {
                        taste("\u{7F}", code: 51, [.command], in: blatt3)
                        for _ in 0..<14 where speicher.rueckfrage == nil { await warten(150) }
                    }
                    if speicher.rueckfrage == nil {
                        zeilen.append("      ⌘⌫ ohne Rückfrage — gewählte Zeile \(tabelle.selectedRow)")
                    }
                    let frage = speicher.rueckfrage
                    pruefen(frage?.ort == .lernende
                            && frage?.text.contains("„Bauer, Ben“ in allen archivierten Schuljahren") == true,
                            "⌘⌫ „In allen Schuljahren löschen …“ fragt am Blatt — mit Name und Zahlen (E276)")
                    if let fehlt = await Pruefstaende.vonHandAntworten(speicher, true) { pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden") }
                    for _ in 0..<12 where tabelle.numberOfRows == 3 { await warten(250) }
                    pruefen(tabelle.numberOfRows == 2, "das Blatt zeigt danach zwei Personen")
                    if case .gelesen(let archiv, _, _) = speicher.lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) {
                        let personen = archiv.jahre.first?.lernende?.lernende ?? []
                        pruefen(personen.count == 2 && !personen.contains { $0.nachname == "Bauer" },
                                "archiv.json trägt die Person nicht mehr")
                        if let vorjahr = archiv.jahre.first {
                            let ziel = ablage.ordner.appendingPathComponent("sicherung-vorjahr-probe.json")
                            let gesichert = (try? speicher.archivPlanungSchreiben(vorjahr.planung, nach: ziel)) ?? 0
                            let zurueck = (try? Data(contentsOf: ziel)).flatMap { try? Planungsdatei.lesen(try tresor.oeffnen($0)) }
                            pruefen(gesichert > 0 && zurueck == vorjahr.planung,
                                    "„Planung sichern …“: die Planung des Vorjahres als verschlüsselte Datei, unverändert (E274)")
                        }
                    } else {
                        pruefen(false, "das Archiv liest sich nach der Löschung")
                    }
                    pruefen(speicher.lernende.bestand?.lernende.contains { $0.nachname == "Bauer" } == true,
                            "das laufende Schuljahr bleibt unberührt")
                }
                taste("\u{1B}", code: 53, in: blatt3)
                for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                pruefen(speicher.offenerDialog == nil, "Escape schließt das Blatt — die Löschung galt schon, ohne „Übernehmen“")
                // ── Kurszelle (AP10): Rechtsklick in die Zeile k-1, „Lernende …“ öffnet ihre Gruppe ──
                // Eine Zelle der ersten Zeile ohne Vorhaben, die der Klickpunkt auch trifft. Die Mitte
                // aus Rahmen ∩ Sichtfläche des Sammelblatts: `visibleRect` der Zelle nennt hier die
                // Sichtfläche des ganzen Sammelblatts.
                var zellen: [Zellenkoerper] = []
                @MainActor func sammeln(_ ansicht: NSView) {
                    if let zelle = ansicht as? Zellenkoerper, zelle.zeile == 0, !zelle.isHiddenOrHasHiddenAncestor,
                       !zelle.subviews.contains(where: { $0 is Kachelansicht }) {
                        zellen.append(zelle)
                    }
                    ansicht.subviews.forEach(sammeln)
                }
                NSApp.activate(ignoringOtherApps: true)
                hauptfenster()?.makeKeyAndOrderFront(nil)
                await warten(400)
                if let inhalt = hauptfenster()?.contentView { sammeln(inhalt) }
                @MainActor func mitte(_ zelle: Zellenkoerper) -> NSPoint {
                    guard let blatt = zelle.superview else { return .zero }
                    let sichtbar = zelle.frame.intersection(blatt.visibleRect)
                    guard !sichtbar.isEmpty else { return .zero }
                    return blatt.convert(NSPoint(x: sichtbar.midX, y: sichtbar.midY), to: nil)
                }
                let rahmenansicht = hauptfenster()?.contentView?.superview
                if speicher.planung?.klassen.first?.id == "k-1",
                   let zelle = zellen.first(where: { rahmenansicht?.hitTest(mitte($0))?.isDescendant(of: $0) == true }),
                   let fenster = hauptfenster() {
                    let punkt = mitte(zelle)
                    let menuekasten = Menuekasten()
                    let auf = NotificationCenter.default.addObserver(
                        forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { meldung in
                        nonisolated(unsafe) let menue = meldung.object as? NSMenu
                        MainActor.assumeIsolated { if let menue { menuekasten.bedienen(menue, "Lernende …") } }
                    }
                    let zu = NotificationCenter.default.addObserver(
                        forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { _ in
                        MainActor.assumeIsolated { menuekasten.zu = true }
                    }
                    for art in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
                        if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                                             windowNumber: fenster.windowNumber, context: nil, eventNumber: 0,
                                                             clickCount: 1, pressure: art == .rightMouseDown ? 1 : 0) {
                            NSApp.postEvent(ereignis, atStart: false)
                        }
                    }
                    for _ in 0..<24 where fenster.attachedSheet == nil { await warten(250) }
                    NotificationCenter.default.removeObserver(auf)
                    NotificationCenter.default.removeObserver(zu)
                    // Warten, bis das Feld „Name“ steht und gefüllt ist (B81) — gemessen fehlte es einmal nach 800 ms.
                    // Ein Fach trägt die Lerngruppe nicht mehr (E665): der Name der an k-1 gebundenen.
                    @MainActor func namensfeld() -> NSTextField? {
                        fenster.attachedSheet.flatMap { suchen($0.contentView, NSTextField.self, { $0.placeholderString == "Name" }) }
                    }
                    for _ in 0..<30 where namensfeld()?.stringValue.isEmpty != false { await warten(150) }
                    let name = namensfeld()?.stringValue
                    let gebunden = speicher.lerngruppe(fuerZeile: "k-1")?.name
                    pruefen(menuekasten.gewaehlt && speicher.offenerDialog == .lernende && name != nil && name == gebunden,
                            "Rechtsklick in die Zeile: Menü \(menuekasten.titel) — „Lernende …“ öffnet das Blatt mit der "
                            + "gebundenen Gruppe („\(name ?? "—")“; Woche \(zelle.woche))")
                    // Der Kopf nennt die verknüpften Zeilen (E669) — so unterscheiden sich gleichnamige (Z-AT9a1-10). Am Modell, wie
                    // das Blatt ihn zeichnet: SwiftUI-Text ist im Fensterlauf nicht lesbar (E678); den Bogen prüft die Dialogprobe.
                    let zeilentitel = speicher.planung?.klassen.first { $0.id == "k-1" }?.beschriftung ?? "—"
                    let kopf = speicher.lerngruppe(fuerZeile: "k-1").map {
                        Lernendenblatt.verknuepft($0, zeilentitel: Lernendenblatt.zeilentitel(speicher.planung))
                    } ?? "—"
                    pruefen(kopf.contains(zeilentitel),
                            "Der Kopf der Lerngruppe nennt ihre Zeile „\(zeilentitel)“ (am Modell, E678): „\(kopf)“")
                    if let blatt4 = fenster.attachedSheet {
                        taste("\u{1B}", code: 53, in: blatt4)
                        for _ in 0..<20 where fenster.attachedSheet != nil { await warten(250) }
                    }
                    pruefen(fenster.attachedSheet == nil && speicher.rueckfrage == nil, "⎋ schließt das Blatt ohne Frage — nichts geändert")
                } else {
                    pruefen(false, "Rasterzelle der Zeile k-1 unter dem Klickpunkt (\(zellen.count) sichtbare ohne Vorhaben, "
                            + "getroffen: \(zellen.prefix(3).map { rahmenansicht?.hitTest(mitte($0)).map { String(describing: type(of: $0)) } ?? "nichts" }))")
                }
                // ── Rufname (E285): im Blatt unter „Alle Lernenden“ eintragen ──
                let gerufen = speicher.lernende.verzeichnis?.alle.first { $0.nachname == "Hübner" }
                let zeile6 = speicher.lernende.verzeichnis?.alle.firstIndex { $0.nachname == "Hübner" }
                let namenVorRuf = namensliste()
                taste("l", code: 37, [.command], in: hauptfenster())
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                if let blatt6 = hauptfenster()?.attachedSheet, let gerufen, let zeile6,
                   let oben = suchen(blatt6.contentView, NSSegmentedControl.self, {
                       $0.segmentCount == 3 && $0.label(forSegment: 1) == "Alle Lernenden" }),
                   waehlen(oben, "Alle Lernenden") {
                    blatt6.makeKeyAndOrderFront(nil)
                    // Tabelle und Feld „Rufname“ — je warten, bis sie stehen, nicht fest (Z14f-02).
                    var tabelle6: NSTableView?
                    for _ in 0..<20 {
                        tabelle6 = suchen(blatt6.contentView, NSTableView.self, {
                            $0.tableColumns.first?.title == "Nachname" && $0.numberOfRows > zeile6 })
                        if tabelle6 != nil { break }
                        await warten(250)
                    }
                    var rufnamenfeld: NSTextField?
                    if let tabelle = tabelle6 {
                        tabelle.selectRowIndexes(IndexSet(integer: zeile6), byExtendingSelection: false)
                        // Das Feld gehört der Leiste, nicht der Person: Es gilt ihr erst, wenn die Leiste die
                        // gewählte Person trägt (Feld „Nachname“) und die Zeile gewählt bleibt (Z14f-06).
                        @MainActor func gebunden() -> Bool {
                            suchen(blatt6.contentView, NSTextField.self, {
                                $0.placeholderString == "Nachname" && $0.stringValue == gerufen.nachname }) != nil
                                && tabelle.selectedRow == zeile6
                        }
                        for _ in 0..<20 where !gebunden() { await warten(150) }
                        // Getippt wird nur in die Leiste der gewählten Person (Z-AS1-01).
                        if gebunden() {
                            rufnamenfeld = suchen(blatt6.contentView, NSTextField.self, { $0.placeholderString == "Rufname" })
                        }
                        pruefen(rufnamenfeld != nil, "Feld „Rufname“ in der Leiste von „\(gerufen.anzeigename)“ (Leiste trägt die Person: \(gebunden()))")
                    } else {
                        pruefen(false, "Tabelle „Alle Lernenden“ mit Zeile \(zeile6 + 1) gefunden")
                    }
                    if let feld = rufnamenfeld {
                        blatt6.makeFirstResponder(feld)
                        await warten(200)
                        tippen("Hans\n", in: blatt6)
                        await warten(600)
                    }
                    blatt6.makeFirstResponder(nil)
                    taste("\r", code: 36, in: blatt6)
                    for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                    let person = speicher.lernende.bestand?.lernende.first { $0.id == gerufen.id }
                    pruefen(speicher.offenerDialog == nil && person?.rufname == "Hans",
                            "Rufname „\(person?.rufname ?? "—")“ für „\(gerufen.anzeigename)“ im Blatt eingetragen und übernommen")
                    pruefen(namensliste() == namenVorRuf, "Vor- und Nachnamen aller Personen unverändert (B74)")
                } else {
                    pruefen(false, "Blatt „Lernende“ mit „Alle Lernenden“ geöffnet")
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                }

                // ── Sitzplan aus der Gruppe (AP11, E255, E284): ⇧⌘L ordnet an, ⌥⏎ kürzt, die Person bleibt, ⏎ ──
                let soll = speicher.lernende.verzeichnis?.sitzplatzvorlage(der: "g-1") ?? []
                speicher.sitzplanOeffnen(klasse: "k-1")
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                for _ in 0..<24 where suchen(hauptfenster()?.attachedSheet?.contentView, NSTextView.self, { $0.isEditable }) == nil {
                    await warten(250)
                }
                if let blatt5 = hauptfenster()?.attachedSheet,
                   let liste = suchen(blatt5.contentView, NSTextView.self, { $0.isEditable }) {
                    blatt5.makeFirstResponder(liste)
                    await warten(300)
                    // Wie die Taste es schickt (gemessen): Zeichen „l“, ohne Modifikatoren „L“.
                    for art in [NSEvent.EventType.keyDown, .keyUp] {
                        if let ereignis = NSEvent.keyEvent(
                            with: art, location: .zero, modifierFlags: [.command, .shift],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: blatt5.windowNumber,
                            context: nil, characters: "l", charactersIgnoringModifiers: "L",
                            isARepeat: false, keyCode: 37) {
                            NSApp.postEvent(ereignis, atStart: false)
                        }
                    }
                    for _ in 0..<20 where (suchen(blatt5.contentView, Sitzplanansicht.self, { _ in true })?.plan.tische.count ?? 0) < soll.count {
                        await warten(150)
                    }
                    if let flaeche = suchen(blatt5.contentView, Sitzplanansicht.self, { _ in true }) {
                        let angeordnet = flaeche.plan.tische.map { Sitzplan.Platzvorlage(name: $0.name, lernender: $0.lernender) }
                        pruefen(soll.count == 12 && angeordnet == soll && soll.contains { $0.name == "Hans Hübner" },
                                "⇧⌘L ordnet \(angeordnet.count) Tische aus „G6a“ an — jeder mit seiner Person, "
                                + "der Rufname statt des Vornamens („Hans Hübner“)")
                        // ⌥⏎ am ersten Tisch: kürzen — die Person bleibt (E284).
                        let erster = flaeche.plan.tische[0]
                        let punkt = flaeche.convert(CGPoint(x: erster.rahmen.midX, y: erster.rahmen.midY), to: nil)
                        for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                            if let ereignis = NSEvent.mouseEvent(
                                with: art, location: punkt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                windowNumber: blatt5.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                pressure: art == .leftMouseDown ? 1 : 0) {
                                NSApp.postEvent(ereignis, atStart: false)
                            }
                        }
                        await warten(300)
                        taste("\r", code: 36, [.option], in: blatt5)
                        for _ in 0..<20 where !flaeche.subviews.contains(where: { $0 is NSTextField }) { await warten(150) }
                        // Ohne Namensfeld hieße ⏎ auf der Fläche „Übernehmen“ (Z-AS1-16).
                        if flaeche.subviews.contains(where: { $0 is NSTextField }) {
                            tippen("Kurz", in: blatt5)
                            taste("\r", code: 36, in: blatt5)
                            for _ in 0..<20 where flaeche.plan.tische[0].name != "Kurz" { await warten(150) }
                        } else {
                            pruefen(false, "⌥⏎ öffnet das Namensfeld am Tisch")
                        }
                        let gekuerzt = flaeche.plan.tische[0]
                        pruefen(gekuerzt.name == "Kurz" && !erster.lernender.isEmpty && gekuerzt.lernender == erster.lernender,
                                "⌥⏎ kürzt „\(erster.name)“ zu „\(gekuerzt.name)“ — die Person bleibt (E284)")
                        blatt5.makeFirstResponder(flaeche)
                        taste("\r", code: 36, in: blatt5)
                    } else {
                        pruefen(false, "⇧⌘L ordnet die Tische an — keine Fläche")
                        if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                    }
                    for _ in 0..<12 where speicher.offenerDialog == .sitzplan { await warten(250) }
                    await Planungsspeicher.blaetterAbloesenAbwarten()
                    let plan = speicher.sitzplan(fuer: "k-1")
                    pruefen(speicher.offenerDialog == nil && plan?.tische.map(\.lernender) == soll.map(\.lernender)
                            && plan?.tische.first?.name == "Kurz",
                            "⏎ übernimmt: \(plan?.tische.count ?? 0) Tische mit ihrer Person, der erste „\(plan?.tische.first?.name ?? "—")“")
                    let kopf5 = kennung(ablage.sitzplaene)
                    let gelesen = (try? Data(contentsOf: ablage.sitzplaene))
                        .flatMap { try? tresor.oeffnen($0) }
                        .flatMap { try? Sitzplandatei.lesen($0) }?["k-1"]?.tische.map(\.lernender)
                    pruefen(kopf5?.inhalt == "sitzplaene" && kopf5?.kennung == tresor.kennungHex
                            && gelesen == soll.map(\.lernender),
                            "sitzplaene.json ist ein Behälter unter dem Schlüssel der Sitzung und trägt die zwölf Bindungen")
                } else {
                    pruefen(false, "Sitzplan-Blatt mit Namensliste geöffnet")
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                }
                // ── Export (AP12, E257): „Ablage“ bietet ihn an, der Behälter öffnet mit der Passphrase ──
                let ablagemenue = NSApp.mainMenu?.items.first { $0.title == "Ablage" }?.submenu
                if let ablagemenue {
                    ablagemenue.delegate?.menuNeedsUpdate?(ablagemenue)
                    ablagemenue.update()
                }
                let ablageaktiv = ["Lernende exportieren …", "Lernende als CSV sichern …", "Lernende einlesen …"].map { titel in
                    ablagemenue?.items.first { $0.title == titel }?.isEnabled
                }
                pruefen(ablageaktiv == [true, true, false],
                        "„Ablage“: Exportieren und CSV aktiv, Einlesen grau — die Verwaltung ist nicht leer (\(ablageaktiv))")
                let exportdatei = ablage.ordner.appending(component: "lernende-export-probe.json")
                let geschrieben = try? speicher.lernendenExportSchreiben(nach: exportdatei)
                let kopfE = (try? Data(contentsOf: exportdatei)).flatMap { try? Tresor.kopfLesen($0) }
                let geoeffnet = kopfE.flatMap { kopf in
                    umgebung["ENTSPERRPROBE_PASSPHRASE"].flatMap { try? Tresor.oeffnen(kopf: kopf, passphrase: $0) }
                        .flatMap { try? $0.oeffnen(kopf: kopf) }
                }.flatMap { try? Lernendendatei.lesen($0) }
                pruefen(geschrieben != nil && kopfE?.inhalt == "lernende"
                        && Set(kopfE?.wicklungen.map(\.art) ?? []) == [Wicklung.passphrase, Wicklung.wiederherstellung]
                        && geoeffnet != nil && geoeffnet == speicher.lernende.bestand,
                        "Export: Behälter „lernende“, nur Passphrase und Wiederherstellung — mit der Passphrase geöffnet "
                        + "dieselbe Jahresdatei")
                // ── IServ-Import (AP13): die Musterdatei der Saat in „G6a“ (g-1) ──
                let musterdatei = ablage.ordner.appending(component: "iserv-muster.csv")
                let vorImport = speicher.lernende.bestand
                speicher.lernendenBlattOeffnen(gruppe: "g-1")
                speicher.lernendenVorgabe?.importdatei = musterdatei
                for _ in 0..<24 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                if let blatt7 = hauptfenster()?.attachedSheet, let bogen = blatt7.attachedSheet {
                    // Die echte Erkennung eines Bogens am Blatt — das Prüfziel kennt keine Fenster (Z-AS3-14).
                    pruefen(Planungsspeicher.bogenAmBlatt(), "der Bogen am Blatt „Lernende“ zählt als Bogen")
                    bogen.makeKeyAndOrderFront(nil)
                    // ⏎ „Importieren“ greift erst, wenn der Bogen die Datei gelesen hat — bleibt der Schritt
                    // aus und steht der Bogen noch, noch einmal (Z-AS1-08).
                    for _ in 0..<4 where speicher.lernendenverlauf.naechsterName != Schrittname.ausIServImportieren
                        && blatt7.attachedSheet === bogen {
                        await warten(300)
                        taste("\r", code: 36, in: bogen)
                        for _ in 0..<8 where speicher.lernendenverlauf.naechsterName != Schrittname.ausIServImportieren {
                            await warten(250)
                        }
                    }
                    let meldung = speicher.meldungen.last?.text ?? "—"
                    pruefen(speicher.lernendenverlauf.naechsterName == Schrittname.ausIServImportieren
                            && meldung == "IServ-Import: 3 neu · 1 unverändert · 1 übergangen.",
                            "⏎ „Importieren“: ein Schritt im Verlauf des Blatts — \(meldung)")
                    taste("\r", code: 36, in: bogen)
                    for _ in 0..<12 where blatt7.attachedSheet != nil { await warten(250) }
                    pruefen(blatt7.attachedSheet == nil && !Planungsspeicher.bogenAmBlatt(), "das Blatt allein trägt keinen Bogen")
                    blatt7.makeKeyAndOrderFront(nil)
                    blatt7.makeFirstResponder(nil)
                    await warten(300)
                    taste("\r", code: 36, in: blatt7)
                    for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                    let nachher = speicher.lernende.bestand
                    let neu = (nachher?.lernende ?? []).filter { p in !(vorImport?.lernende ?? []).contains { $0.id == p.id } }
                    let g1 = nachher?.lerngruppen.first { $0.id == "g-1" }
                    pruefen(speicher.offenerDialog == nil && neu.count == 3
                            && neu.allSatisfy { p in g1?.mitglieder.contains(p.id) == true && !p.angelegt.isEmpty
                                && p.angelegt > (vorImport?.geaendert ?? "") }
                            && nachher?.lernende.filter { $0.nachname == "Yilmaz" }.count == 1,
                            "„Übernehmen“: \(neu.count) neue Personen in „G6a“ mit dem Zeitpunkt des Imports "
                            + "(E251), „Amira Yilmaz“ einmal")
                } else {
                    pruefen(false, "Bogen „Aus IServ importieren“ am Blatt „Lernende“")
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                }
                // ── Termin ohne Lerngruppe (AP13b, E290): unter „Alle Lernenden“ im Bogen anlegen, ⏎, übernehmen ──
                let terminperson = speicher.lernende.verzeichnis?.alle.first { $0.nachname == "Hübner" }
                speicher.lernendenBlattOeffnen()
                speicher.lernendenVorgabe?.ansicht = .alle
                speicher.lernendenVorgabe?.person = terminperson?.id
                speicher.lernendenVorgabe?.anliegenbogen = .termin
                for _ in 0..<24 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                // Bis die Felder im Bogen stehen — nicht fest (Z14f-03).
                @MainActor func bogenfeld(_ passt: (NSTextField) -> Bool) -> NSTextField? {
                    suchen(hauptfenster()?.attachedSheet?.attachedSheet?.contentView, NSTextField.self, passt)
                }
                for _ in 0..<24 where bogenfeld({ $0.placeholderString == "etwa Elterngespräch" }) == nil
                    || bogenfeld({ $0.placeholderString == "hh:mm" }) == nil { await warten(250) }
                if let blatt8 = hauptfenster()?.attachedSheet, let bogen = blatt8.attachedSheet, let terminperson,
                   let titelfeld = suchen(bogen.contentView, NSTextField.self, { $0.placeholderString == "etwa Elterngespräch" }),
                   let zeitfeld = suchen(bogen.contentView, NSTextField.self, { $0.placeholderString == "hh:mm" }) {
                    bogen.makeKeyAndOrderFront(nil)
                    bogen.makeFirstResponder(titelfeld)
                    await warten(200)
                    tippen("Elterngespräch", in: bogen)
                    await warten(300)
                    bogen.makeFirstResponder(zeitfeld)
                    await warten(200)
                    tippen("7.45", in: bogen)
                    await warten(300)
                    taste("\r", code: 36, in: bogen)
                    for _ in 0..<12 where blatt8.attachedSheet != nil { await warten(250) }
                    await warten(300)
                    pruefen(blatt8.attachedSheet == nil && speicher.lernendenverlauf.naechsterName == Schrittname.terminAnlegen,
                            "⏎ „Anlegen“: Der Bogen schließt, „Termin anlegen“ ist ein Schritt im Verlauf des Blatts")
                    // Die Liste nimmt den neuen Termin nach dem Schließen des Bogens auf — warten (Z14f-02).
                    var liste: NSTableView?
                    for _ in 0..<20 {
                        liste = suchen(blatt8.contentView, NSTableView.self, { $0.tableColumns.first?.title == "Art" })
                        if liste?.numberOfRows == 1 { break }
                        await warten(150)
                    }
                    pruefen(liste?.numberOfRows == 1, "„Ohne Lerngruppe“ an „\(terminperson.anzeigename)“ zeigt eine Zeile "
                            + "(\(liste?.numberOfRows ?? -1))")
                    blatt8.makeKeyAndOrderFront(nil)
                    blatt8.makeFirstResponder(nil)
                    await warten(300)
                    taste("\r", code: 36, in: blatt8)
                    for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                    let termin = speicher.lernende.bestand?.anliegen.first { $0.art == .termin }
                    let gelesen = (try? Data(contentsOf: ablage.lernende)).flatMap { try? tresor.oeffnen($0) }
                        .flatMap { try? Lernendendatei.lesen($0) }
                    pruefen(speicher.offenerDialog == nil && termin?.titel == "Elterngespräch" && termin?.uhrzeit == "07:45"
                            && termin?.datum == Tag.heute.iso && termin?.lerngruppe == ""
                            && termin?.betroffene == [terminperson.id] && termin.flatMap { t in gelesen?.anliegen.contains(t) } == true
                            && speicher.lernende.verzeichnis?.stand(termin?.id ?? "", terminperson.id) == .offen,
                            "„Übernehmen“: Termin „\(termin?.titel ?? "—")“ am \(Anliegenbezug.tagtext(termin?.datum ?? "")) "
                            + "um \(termin?.uhrzeit ?? "—") Uhr für „\(terminperson.anzeigename)“, ohne Lerngruppe, offen — "
                            + "so in der Jahresdatei")
                } else {
                    pruefen(false, "Bogen „Neuer Termin“ am Blatt „Lernende“ mit Titel- und Uhrzeitfeld")
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                }
                // ── Termin ↔ Vorhaben (AP13c-1, E293): im Bogen mit Zeile anlegen, übernehmen, dann die Planung führen ──
                speicher.lernendenBlattOeffnen()
                speicher.lernendenVorgabe?.ansicht = .alle
                speicher.lernendenVorgabe?.person = terminperson?.id
                speicher.lernendenVorgabe?.anliegenbogen = .termin
                for _ in 0..<24 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                for _ in 0..<24 where bogenfeld({ $0.placeholderString == "etwa Elterngespräch" }) == nil
                    || bogenfeld({ $0.isEditable && $0.stringValue == Tag.heute.deutsch }) == nil
                    || bogenfeld({ $0.placeholderString == "hh:mm" }) == nil { await warten(250) }
                let vorKopplung = Set(speicher.lernende.bestand?.anliegen.map(\.id) ?? [])
                let bogen9 = hauptfenster()?.attachedSheet?.attachedSheet
                let titelfeld9 = suchen(bogen9?.contentView, NSTextField.self, { $0.placeholderString == "etwa Elterngespräch" })
                // Das Tagesfeld trägt in der gruppierten Form keinen Platzhalter — gefunden am vorgeschlagenen Tag.
                let tagfeld9 = suchen(bogen9?.contentView, NSTextField.self, { $0.isEditable && $0.stringValue == Tag.heute.deutsch })
                let zeitfeld9 = suchen(bogen9?.contentView, NSTextField.self, { $0.placeholderString == "hh:mm" })
                if let blatt9 = hauptfenster()?.attachedSheet, let bogen = bogen9, let terminperson,
                   titelfeld9 != nil, tagfeld9 != nil, zeitfeld9 != nil {
                    // Jedes Feld frisch gesucht: Übernimmt der Bogen den Tag, erscheint die Zeile —
                    // SwiftUI baut die Form neu, ein gemerktes Feld gehört dann nicht mehr zum Fenster.
                    @MainActor func feld(_ passt: (NSTextField) -> Bool) -> NSTextField? { suchen(bogen.contentView, NSTextField.self, passt) }
                    bogen.makeKeyAndOrderFront(nil)
                    if let f = feld({ $0.placeholderString == "etwa Elterngespräch" }) { bogen.makeFirstResponder(f) }
                    await warten(200)
                    tippen("Hospitation", in: bogen)
                    await warten(200)
                    if let f = feld({ $0.placeholderString == "hh:mm" }) { bogen.makeFirstResponder(f) }
                    await warten(200)
                    tippen("8.00", in: bogen)
                    await warten(200)
                    if let f = feld({ $0.isEditable && $0.stringValue == Tag.heute.deutsch }) { bogen.makeFirstResponder(f) }
                    await warten(200)
                    (bogen.firstResponder as? NSTextView)?.selectAll(nil)
                    tippen("03.09.2026", in: bogen)
                    await warten(300)
                    // Der Wechsel des Felds übernimmt den Tag; der Schalter folgt dem Vorschlag.
                    if let f = feld({ $0.placeholderString == "hh:mm" || $0.stringValue == "8.00" }) { bogen.makeFirstResponder(f) }
                    await warten(500)
                    taste("\r", code: 36, in: bogen)
                    for _ in 0..<12 where blatt9.attachedSheet != nil { await warten(250) }
                    if blatt9.attachedSheet != nil {
                        let werte = sammelnTextfelder(bogen.contentView)
                        zeilen.append("  Bogen noch offen — Felder: " + werte.joined(separator: " | "))
                    }
                    blatt9.makeKeyAndOrderFront(nil)
                    blatt9.makeFirstResponder(nil)
                    await warten(300)
                    taste("\r", code: 36, in: blatt9)
                    for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                    let neu = speicher.lernende.bestand?.anliegen.first { !vorKopplung.contains($0.id) && $0.art == .termin }
                    let vh = neu.flatMap { t in speicher.planung?.eintraege.first { $0.termin == t.id } }
                    pruefen(neu?.titel == "Hospitation" && vh?.klasseId == "k-2" && vh?.datum == Tag(iso: "2026-09-03")
                            && vh?.terminzeit == "08:00" && vh?.titel == "Hospitation" && neu?.vorhaben == vh?.id
                            && speicher.verlauf.naechsterName == Schrittname.termineUebernehmen,
                            "„Übernehmen“: Termin „\(neu?.titel ?? "—")“ mit Vorhaben in „Klassenleitung“ am "
                            + "\(vh?.datum?.deutsch ?? "—") um \(vh?.terminzeit ?? "—") — Schritt „Termine übernehmen“ im Verlauf")
                    // Die Planung schreibt entprellt — für den Blick in die Datei jetzt.
                    speicher.jetztSichern()
                    let klartext = (try? Data(contentsOf: ablage.datei)).flatMap { try? tresor.oeffnen($0) }
                        .map { String(decoding: $0, as: UTF8.self) } ?? ""
                    let mitKennung = neu.map { klartext.contains("\"\($0.id)\"") } == true
                    pruefen(mitKennung && !klartext.contains(terminperson.nachname),
                            "planung.json trägt die Kennung des Termins (\(mitKennung)), keinen Namen "
                            + "(\(!klartext.contains(terminperson.nachname)))")
                    if let neu, let vh {
                        speicher.vorhabenVerschieben(vh.id, klasse: vh.klasseId, woche: vh.woche + 1)
                        speicher.erledigtUmschalten(vh.id)
                        let t2 = speicher.lernende.bestand?.anliegen.first { $0.id == neu.id }
                        pruefen(t2?.datum == "2026-09-10" && speicher.lernende.verzeichnis?.stand(neu.id, terminperson.id) == .erledigt,
                                "Verschieben und Haken in der Planung: Der Termin folgt (10.09.2026, „stattgefunden“)")
                        speicher.vorhabenLoeschen(vh.id, ort: .hauptansicht)
                        let frage = speicher.rueckfrage?.text ?? ""
                        // Wie von Hand (B82, Z14c3-10); ⌘Z erst, wenn das Alert fort und das Vorhaben gelöscht ist (E318).
                        if let fehlt = await Pruefstaende.vonHandAntworten(speicher, true) {
                            pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                        }
                        // Im Klick hing das Alert noch — gelöscht wird erst nach seinem Schließen (B95, E431).
                        pruefen(speicher.planung?.eintraege.contains { $0.id == vh.id } == true,
                                "Vorhaben löschen: Im Klick hängt das Alert noch, das Vorhaben steht bis zu seinem Schließen")
                        for _ in 0..<16 where Pruefstaende.alertfenster() != nil { await warten(125) }
                        for _ in 0..<24 where speicher.planung?.eintraege.contains(where: { $0.id == vh.id }) == true {
                            await warten(125)
                        }
                        let weg = speicher.lernende.bestand?.anliegen.contains { $0.id == neu.id } == false
                        speicher.widerrufen()
                        let zurueck = speicher.lernende.bestand?.anliegen.contains { $0.id == neu.id } == true
                            && speicher.planung?.eintraege.contains { $0.id == vh.id } == true
                        pruefen(frage.contains("Mit dem Vorhaben geht sein Termin") && weg && zurueck,
                                "Vorhaben löschen: Die Rückfrage nennt den Termin, beide gehen; ⌘Z bringt beide")
                    }
                } else {
                    pruefen(false, "Bogen „Neuer Termin“ mit Tag, Titel und Uhrzeit (Bogen \(bogen9 != nil), Titel \(titelfeld9 != nil), "
                            + "Tag \(tagfeld9 != nil), Uhrzeit \(zeitfeld9 != nil))")
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                }
                // ── Vorhaben → Termin (AP13c-2, E295): der Dialog mit „Als Termin führen“ und zwei Personen, ⏎; dann abschalten ──
                let zwei = speicher.lernende.verzeichnis?.alle.filter { ["Hübner", "Iversen"].contains($0.nachname) }.map(\.id) ?? []
                if let vorlage = speicher.planung?.eintraege.first(where: { $0.titel == "Bits und Bytes" }), zwei.count == 2,
                   let p = speicher.planung {
                    var e = VorhabenEntwurf(vorlage)
                    e.termin = true
                    e.terminzeit = "10.30"
                    e.terminpersonen = zwei
                    e.datum = e.datum ?? p.start.montagDerWoche.plus(tage: vorlage.woche * 7 + 2)
                    speicher.vorhabenDialog = e
                    for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                    if let dialog = hauptfenster()?.attachedSheet {
                        dialog.makeKeyAndOrderFront(nil)
                        dialog.makeFirstResponder(nil)
                        // ⏎ greift erst, wenn der Dialog steht — bleibt er im Speicher offen, noch einmal; am
                        // Modell, nicht am Bild: Ein abblendendes Blatt ist schon gesichert (Z14f-03, Z-AS1-10).
                        for _ in 0..<4 where speicher.vorhabenDialog != nil {
                            await warten(300)
                            taste("\r", code: 36, in: dialog)
                            for _ in 0..<8 where speicher.vorhabenDialog != nil { await warten(250) }
                        }
                        for _ in 0..<12 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                    }
                    let v = speicher.planung?.eintraege.first { $0.id == vorlage.id }
                    let t = v.flatMap { v in speicher.lernende.bestand?.anliegen.first { $0.id == v.termin } }
                    pruefen(v?.istTermin == true && v?.terminzeit == "10:30" && t?.betroffene == zwei && t?.lerngruppe == ""
                            && t?.vorhaben == vorlage.id && t?.titel == "Bits und Bytes",
                            "Vorhaben-Dialog, ⏎: „Bits und Bytes“ ist ein Termin um \(v?.terminzeit ?? "—") für zwei Personen, "
                            + "ohne Lerngruppe")
                    if let v, let t {
                        var aus = VorhabenEntwurf(v, terminpersonen: t.betroffene)
                        aus.termin = false
                        speicher.vorhabenDialog = aus
                        for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                        if let dialog = hauptfenster()?.attachedSheet {
                            dialog.makeKeyAndOrderFront(nil)
                            dialog.makeFirstResponder(nil)
                            // ⏎ bis die Rückfrage zum Abschalten steht — nie über sie hinweg (Z14f-03).
                            for _ in 0..<4 where speicher.rueckfrage == nil && hauptfenster()?.attachedSheet === dialog {
                                await warten(300)
                                taste("\r", code: 36, in: dialog)
                                for _ in 0..<8 where speicher.rueckfrage == nil { await warten(250) }
                            }
                        }
                        let frage = speicher.rueckfrage?.text ?? ""
                        if let fehlt = await Pruefstaende.vonHandAntworten(speicher, true) { pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden") }
                        for _ in 0..<12 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                        let danach = speicher.planung?.eintraege.first { $0.id == v.id }
                        pruefen(frage.hasPrefix("Den Termin „Bits und Bytes“ in der Lernendenverwaltung löschen?")
                                && danach?.istTermin == false && speicher.lernende.bestand?.anliegen.contains { $0.id == t.id } == false,
                                "Abschalten: Die Rückfrage nennt den Termin; er geht, das Vorhaben bleibt")
                    }
                } else {
                    pruefen(false, "„Bits und Bytes“ und zwei Personen für den Vorhaben-Termin")
                }
                // ── Kontextmenü der Kachel (E296): „Als Termin führen …“ nach „Als Prüfung führen“, öffnet den Dialog eingeschaltet;
                // „Hausaufgabe hinzufügen …“ öffnet das Blatt auf „Hausaufgabe“ (E653) ──
                NSApp.activate(ignoringOtherApps: true)
                hauptfenster()?.makeKeyAndOrderFront(nil)
                await warten(500)
                var kacheln: [Kachelansicht] = []
                @MainActor func kachelnSammeln(_ ansicht: NSView) {
                    if let k = ansicht as? Kachelansicht, !k.isHiddenOrHasHiddenAncestor { kacheln.append(k) }
                    ansicht.subviews.forEach(kachelnSammeln)
                }
                if let inhalt = hauptfenster()?.contentView { kachelnSammeln(inhalt) }
                @MainActor func kachelmitte(_ k: Kachelansicht) -> NSPoint {
                    guard let ober = k.superview else { return .zero }
                    let sichtbar = k.frame.intersection(ober.visibleRect)
                    guard !sichtbar.isEmpty else { return .zero }
                    return ober.convert(NSPoint(x: sichtbar.midX, y: sichtbar.midY), to: nil)
                }
                let kachelrahmen = hauptfenster()?.contentView?.superview
                if let kachel = kacheln.first(where: { $0.stand?.vorhaben.titel == "Bits und Bytes"
                                                       && kachelrahmen?.hitTest(kachelmitte($0))?.isDescendant(of: $0) == true }),
                   let fenster = hauptfenster() {
                    /// Rechtsklick auf die Kachel, im Menü `eintrag` wählen — wie von Hand; wartet, bis ein Blatt hängt.
                    @MainActor func kachelmenue(_ eintrag: String) async -> Menuekasten {
                        let punkt = kachelmitte(kachel)
                        let kasten = Menuekasten()
                        let auf = NotificationCenter.default.addObserver(
                            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { meldung in
                            nonisolated(unsafe) let menue = meldung.object as? NSMenu
                            MainActor.assumeIsolated { if let menue { kasten.bedienen(menue, eintrag) } }
                        }
                        let zu = NotificationCenter.default.addObserver(
                            forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { _ in
                            MainActor.assumeIsolated { kasten.zu = true }
                        }
                        for art in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
                            if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                                 windowNumber: fenster.windowNumber, context: nil, eventNumber: 0,
                                                                 clickCount: 1, pressure: art == .rightMouseDown ? 1 : 0) {
                                NSApp.postEvent(ereignis, atStart: false)
                            }
                        }
                        for _ in 0..<24 where fenster.attachedSheet == nil { await warten(250) }
                        NotificationCenter.default.removeObserver(auf)
                        NotificationCenter.default.removeObserver(zu)
                        await warten(600)
                        return kasten
                    }
                    let kasten = await kachelmenue("Als Termin führen …")
                    let erwartet = ["Öffnen", "Titel ändern", "Als dringlich kennzeichnen", "Als Korrektur kennzeichnen",
                                    "Als Prüfung führen", "Als Termin führen …", "Hausaufgabe hinzufügen …"]
                    let folge = kasten.titel.filter { erwartet.contains($0) }
                    pruefen(kasten.gewaehlt && folge == erwartet && speicher.vorhabenDialog?.termin == true
                            && speicher.vorhabenDialog?.datum != nil,
                            "Kontextmenü der Kachel: " + kasten.titel.filter { !$0.isEmpty }.joined(separator: " · ")
                            + " — „Als Termin führen …“ öffnet den Dialog eingeschaltet, mit Tag")
                    speicher.vorhabenDialog = nil
                    for _ in 0..<12 where fenster.attachedSheet != nil { await warten(250) }
                    // „Hausaufgabe hinzufügen …“ an derselben Kachel, solange sie keine trägt (E653): das Blatt hängt, auf
                    // „Hausaufgabe“, die Hausaufgabe im Entwurf eingeschaltet; ohne „Übernehmen“ zu, bleibt nichts zurück.
                    let kennung = kachel.stand?.vorhaben.id
                    @MainActor func hatHausaufgabe() -> Bool? {
                        kennung.flatMap { id in speicher.planung?.eintraege.first { $0.id == id } }?.hausaufgabe
                    }
                    // Eine Ursache, ein ✗ (Z-AW2c-01, -02): Ging schon das erste Menü nicht auf, nennt dessen ✗ die Ursache;
                    // hängt das erste Blatt noch oder ist die Kachel verdeckt, sagt es eine eigene Zeile.
                    let blattZu = fenster.attachedSheet == nil
                    let kachelFrei = kachelrahmen?.hitTest(kachelmitte(kachel))?.isDescendant(of: kachel) == true
                    if kasten.titel.isEmpty {
                        // kein zweiter Durchgang
                    } else if !blattZu || !kachelFrei {
                        pruefen(false, "zweiter Rechtsklick: " + (blattZu ? "die Kachel „Bits und Bytes“ ist verdeckt"
                                                                          : "das Blatt des ersten Durchgangs hängt noch"))
                    } else if hatHausaufgabe() == false {
                        let wahl = await kachelmenue("Hausaufgabe hinzufügen …")
                        let offen = wahl.gewaehlt && fenster.attachedSheet != nil && speicher.vorhabenDialog?.hausaufgabe == true
                            && speicher.vorhabenReiter == .hausaufgabe
                        pruefen(offen,
                                "Kontextmenü der Kachel: „Hausaufgabe hinzufügen …“ öffnet das Blatt auf „Hausaufgabe“, eingeschaltet (E653)")
                        speicher.vorhabenDialog = nil
                        for _ in 0..<12 where fenster.attachedSheet != nil { await warten(250) }
                        if offen {
                            pruefen(hatHausaufgabe() == false, "„Hausaufgabe hinzufügen …“ ohne „Übernehmen“: nichts bleibt zurück (E653)")
                        }
                    } else {
                        pruefen(false, "Kachel „Bits und Bytes“ ohne Hausaufgabe für „Hausaufgabe hinzufügen …“")
                    }
                } else {
                    pruefen(false, "Kachel „Bits und Bytes“ unter dem Klickpunkt (\(kacheln.count) Kacheln)")
                }
                // ── Suche, ⌘F, Ordnung, Umzug im Blatt (v84, AT2b: F, G, H; E360–E367) ──
                // Suche: Vorgabe „Hüb“ unter „Alle Lernenden“ — die Tabelle zählt eine Zeile; ⌘F setzt die Schreibmarke
                // ins Suchfeld, wenn das Kürzel das Blatt vor dem Menü erreicht (E361).
                speicher.lernendenBlattOeffnen()
                speicher.lernendenVorgabe?.ansicht = .alle
                speicher.lernendenVorgabe?.suche = "Hüb"
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                if let blatt8 = hauptfenster()?.attachedSheet {
                    blatt8.makeKeyAndOrderFront(nil)
                    var tabelle8: NSTableView?
                    for _ in 0..<20 {
                        tabelle8 = suchen(blatt8.contentView, NSTableView.self, { $0.tableColumns.first?.title == "Nachname" })
                        if tabelle8?.numberOfRows == 1 { break }
                        await warten(250)
                    }
                    pruefen(tabelle8?.numberOfRows == 1, "Vorgabe Suche „Hüb“ unter „Alle Lernenden“: Die Tabelle zählt "
                            + "\(tabelle8?.numberOfRows ?? -1) Zeilen, erwartet 1 (E360)")
                    blatt8.makeFirstResponder(nil)
                    await warten(200)
                    @MainActor func feldImFokus(_ blatt: NSWindow) -> String? {
                        ((blatt.firstResponder as? NSTextView)?.delegate as? NSTextField)?.placeholderString
                    }
                    let vorKuerzel8 = feldImFokus(blatt8)
                    taste("f", code: 3, [.command], in: blatt8)
                    await warten(500)
                    pruefen(vorKuerzel8 == nil && feldImFokus(blatt8) == "Nachname, Vorname oder Rufname",
                            "⌘F unter „Alle Lernenden“ setzt die Schreibmarke ins Suchfeld (E361) — vorher "
                            + "\(vorKuerzel8 ?? "kein Feld"), danach \(feldImFokus(blatt8) ?? "kein Feld")")
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach der Suche nicht geschlossen") }
                    // Unter „Lerngruppen“ in den Filter der Liste.
                    speicher.lernendenBlattOeffnen()
                    for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                    if let blatt8b = hauptfenster()?.attachedSheet {
                        blatt8b.makeKeyAndOrderFront(nil)
                        await warten(400)
                        blatt8b.makeFirstResponder(nil)
                        await warten(200)
                        let vorKuerzel8b = feldImFokus(blatt8b)
                        taste("f", code: 3, [.command], in: blatt8b)
                        await warten(500)
                        pruefen(vorKuerzel8b == nil && feldImFokus(blatt8b) == "Lerngruppe suchen",
                                "⌘F unter „Lerngruppen“ setzt die Schreibmarke in den Filter der Liste — danach "
                                + "\(feldImFokus(blatt8b) ?? "kein Feld")")
                        if !(await blattSchliessen()) { zeilen.append("  Blatt nach ⌘F nicht geschlossen") }
                    } else {
                        pruefen(false, "Blatt „Lernende“ für ⌘F unter „Lerngruppen“ geöffnet")
                    }
                } else {
                    pruefen(false, "Blatt „Lernende“ mit Vorgabe Suche geöffnet")
                }
                // Ordnung: Vorgabe Vorname — die erste Zeile ist die Person, die nach dem Vornamen vorn steht (E362, E363).
                let nachVorname = speicher.lernende.verzeichnis.flatMap {
                    Lernendenblatt.uebersicht($0, suche: "", archivierte: false, nurOffen: false,
                                              ordnung: Personenspalte.vorname.ordnung).first
                }
                let nachNachname = speicher.lernende.verzeichnis?.alle.first
                speicher.lernendenBlattOeffnen()
                speicher.lernendenVorgabe?.ansicht = .alle
                speicher.lernendenVorgabe?.sortierung = .vorname
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                if let blatt9 = hauptfenster()?.attachedSheet, let erste = nachVorname, erste.id != nachNachname?.id {
                    blatt9.makeKeyAndOrderFront(nil)
                    var tabelle9: NSTableView?
                    for _ in 0..<20 {
                        tabelle9 = suchen(blatt9.contentView, NSTableView.self, {
                            $0.tableColumns.first?.title == "Nachname" && $0.numberOfRows > 0 })
                        if tabelle9 != nil { break }
                        await warten(250)
                    }
                    tabelle9?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    @MainActor func nachnamenfeld() -> String? {
                        suchen(blatt9.contentView, NSTextField.self, { $0.placeholderString == "Nachname" })?.stringValue
                    }
                    for _ in 0..<20 where (nachnamenfeld() ?? "").isEmpty { await warten(150) }
                    pruefen(nachnamenfeld() == erste.nachname, "Vorgabe Ordnung nach Vorname: Die erste Zeile ist "
                            + "„\(nachnamenfeld() ?? "—")“, erwartet „\(erste.nachname)“ (E363)")
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach der Ordnung nicht geschlossen") }
                } else {
                    pruefen(false, "Vorbedingung für die Ordnung: Blatt offen, nach Vorname eine andere Person vorn als nach "
                            + "Nachname")
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                }
                // Umzug: eine Person mit Rücklauf und Tisch aus „G6a“ (g-1) nach „Probe 7c“ — ein Schritt,
                // „Übernehmen“; die Jahresdatei trägt sie nur noch dort, ihr Rücklauf bleibt (E366), ihr Tisch geht aus dem
                // Sitzplan von k-1 (E367), die übrigen Tische bleiben. Dietz und Lange braucht der nächste Schritt.
                @MainActor func jahresdateiAufDerPlatte() -> Lernendenbestand? {
                    (try? Data(contentsOf: ablage.lernende)).flatMap { try? tresor.oeffnen($0) }
                        .flatMap { try? Lernendendatei.lesen($0) }
                }
                if let bestand = speicher.lernende.bestand, let plan = speicher.sitzplan(fuer: "k-1"),
                   let g1 = bestand.lerngruppen.first(where: { $0.id == "g-1" }),
                   let wer = bestand.lernende.first(where: { p in
                       !["Dietz", "Lange"].contains(p.nachname) && g1.mitglieder.contains(p.id)
                           && bestand.rueckmeldungen.contains { $0.lernender == p.id }
                           && plan.tische.contains { $0.lernender == p.id } }),
                   let ziel = bestand.lerngruppen.first(where: { $0.name == "Probe 7c" })?.id,
                   speicher.lerngruppe(fuerZeile: "k-1")?.id == "g-1" {
                    let koenig = wer.id
                    let ruecklaeufe = bestand.rueckmeldungen.filter { $0.lernender == koenig }
                    let andereTische = plan.tische.filter { $0.lernender != koenig }.map { "\($0.name)|\($0.lernender)" }
                    let bekannt = Set(speicher.meldungen.map(\.id))
                    speicher.lernendenBlattOeffnen(gruppe: "g-1")
                    speicher.lernendenVorgabe?.person = koenig
                    speicher.lernendenVorgabe?.umzug = ziel
                    for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                    for _ in 0..<16 where speicher.lernendenverlauf.naechsterName != Schrittname.inAndereLerngruppeUmziehen {
                        await warten(250)
                    }
                    let schritt = speicher.lernendenverlauf.naechsterName
                    if let blatt10 = hauptfenster()?.attachedSheet {
                        blatt10.makeKeyAndOrderFront(nil)
                        blatt10.makeFirstResponder(nil)
                        await warten(300)
                        taste("\r", code: 36, in: blatt10)
                        for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                    }
                    let datei = jahresdateiAufDerPlatte()
                    let warnung = speicher.meldungen.first { !bekannt.contains($0.id) && $0.text
                        == "Eine Person wurde mit dem Verlassen ihrer Lerngruppe auch aus dem Sitzplan entfernt." }
                    pruefen(schritt == Schrittname.inAndereLerngruppeUmziehen && speicher.offenerDialog == nil
                            && datei?.lerngruppen.first { $0.id == "g-1" }?.mitglieder.contains(koenig) == false
                            && datei?.lerngruppen.first { $0.id == ziel }?.mitglieder.contains(koenig) == true
                            && datei?.rueckmeldungen.filter { $0.lernender == koenig } == ruecklaeufe,
                            "Vorgabe Umzug: \(wer.anzeigename) von „G6a“ nach „Probe 7c“ — Schritt „\(schritt ?? "—")“; "
                            + "lernende.json trägt sie nur noch dort, ihre \(ruecklaeufe.count) Rückläufe bleiben (E365, E366)")
                    let danach = speicher.sitzplan(fuer: "k-1")?.tische ?? []
                    pruefen(!danach.contains { $0.lernender == koenig }
                            && danach.map { "\($0.name)|\($0.lernender)" } == andereTische && warnung?.art == .warnung,
                            "… ihr Tisch ging aus dem Sitzplan von k-1, die \(andereTische.count) übrigen blieben, mit Warnung "
                            + "(E367, E494)")
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Umzug nicht geschlossen") }
                } else {
                    pruefen(false, "Vorbedingung für den Umzug: eine Person in g-1 mit Rücklauf und Tisch in k-1 (nicht Dietz "
                            + "oder Lange), g-1 an k-1 gebunden, Gruppe „Probe 7c“")
                }
                // ── E304 am Paket: eine Person mit Tisch endgültig gelöscht und übernommen — die Datei trägt sie nicht mehr ──
                @MainActor func gebundeneInDatei() -> [String]? {
                    (try? Data(contentsOf: ablage.sitzplaene)).flatMap { try? tresor.oeffnen($0) }
                        .flatMap { try? Sitzplandatei.lesen($0) }?["k-1"]?.tische.map(\.lernender)
                }
                @MainActor func kennungVon(nachname: String) -> String? {
                    speicher.lernende.bestand?.lernende.first { $0.nachname == nachname }?.id
                }
                // Nach Namen gewählt, ohne Termin — kein späterer Schritt kennt sie (Z-AS5a-07).
                let vorPlan = speicher.sitzplan(fuer: "k-1")
                if let vorPlan, let bestand = speicher.lernende.bestand,
                   let geloescht = kennungVon(nachname: "Dietz"), let tot = kennungVon(nachname: "Lange"),
                   vorPlan.tische.contains(where: { $0.lernender == geloescht }), vorPlan.tische.contains(where: { $0.lernender == tot }) {
                    let namen = vorPlan.tische.map(\.name)
                    pruefen(speicher.lernendenUebernehmen(bestand.ohnePerson(geloescht).bestand) == nil
                            && gebundeneInDatei().map { !$0.contains(geloescht) && $0.count == namen.count } == true
                            && speicher.sitzplan(fuer: "k-1")?.tische.map(\.name) == namen,
                            "E304 am Paket: Dietz mit Tisch endgültig gelöscht — sitzplaene.json trägt „\(geloescht)“ nicht mehr, "
                            + "der Name am Tisch bleibt")
                    // ── Tote Bindung (C, E325, E345): Lange aus der Jahresdatei ohne E304, wie nach gesperrten Sitzplänen ──
                    if let ohne = speicher.lernende.bestand?.ohnePerson(tot).bestand {
                        speicher.lernende.setzen(ohne)
                        pruefen(gebundeneInDatei()?.contains(tot) == true, "Vorbedingung: sitzplaene.json trägt die tote Bindung „\(tot)“")
                        let bekannt = Set(speicher.meldungen.map(\.id))
                        @MainActor func geloestGemeldet() -> [Meldung] {
                            speicher.meldungen.filter { !bekannt.contains($0.id) && $0.text.hasPrefix("Eine Zuordnung an einem Tisch wurde gelöst") }
                        }
                        speicher.sitzplanOeffnen(klasse: "k-1")
                        for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                        pruefen(speicher.sitzplanEntwurf.map { !$0.tische.contains { $0.lernender == tot } } == true
                                && gebundeneInDatei().map { !$0.contains(tot) && $0.count == namen.count } == true
                                && speicher.sitzplan(fuer: "k-1")?.tische.map(\.name) == namen,
                                "Tote Bindung: Der Editor zeigt sie nicht, sitzplaene.json trägt „\(tot)“ nicht mehr, die Namen bleiben")
                        let hinterDemBlatt = geloestGemeldet().count
                        if !(await blattSchliessen()) { zeilen.append("  Blatt nach der toten Bindung nicht geschlossen") }
                        await Planungsspeicher.blaetterAbloesenAbwarten()
                        for _ in 0..<16 where geloestGemeldet().isEmpty { await warten(125) }
                        pruefen(hinterDemBlatt == 0 && geloestGemeldet().count == 1,
                                "… gemeldet genau einmal, wenn das Blatt zu ist (E346, Z-AS5a-01) — vorher \(hinterDemBlatt), "
                                + "danach \(geloestGemeldet().count)")
                    } else {
                        pruefen(false, "Vorbedingung: Jahresdatei nach dem Löschen von Dietz gelesen")
                    }
                } else {
                    pruefen(false, "Vorbedingung für E304 und die tote Bindung: Dietz und Lange an Tischen von „k-1“")
                }
                // ── ⌘L-Import „Je Klasse“ mit Bindung (v84, AT7, E523, E528) ──
                // Am Ende, damit die neue Zeile und Gruppe keinen früheren Schritt verschieben: eine freie Zeile „Klasse1“,
                // dann die Musterdatei ohne gewählte Gruppe — „Je Klasse“, der Schalter an. Die neue Lerngruppe „Klasse1“
                // ist an die gleichnamige Zeile gebunden, die Meldung sagt es; „G6a“ trifft bestehende Gruppen.
                speicher.aendern(Schrittname.kursHinzufuegen) { $0.klassen += Standardkurse.aufbauen([("Klasse1", "Mathematik")]) }
                if let zeile = speicher.planung?.klassen.first(where: { $0.name == "Klasse1" }), let herkunft = speicher.planung?.erstellt {
                    speicher.lernendenBlattOeffnen()
                    speicher.lernendenVorgabe?.ansicht = .alle
                    speicher.lernendenVorgabe?.importdatei = speicher.sicherung.ablage.ordner.appending(component: "iserv-muster.csv")
                    for _ in 0..<24 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                    if let blatt = hauptfenster()?.attachedSheet, let bogen = blatt.attachedSheet {
                        bogen.makeKeyAndOrderFront(nil)
                        // ⏎ „Importieren“ greift erst, wenn der Bogen die Datei gelesen hat (wie AP13, Z-AS1-08).
                        for _ in 0..<4 where speicher.lernendenverlauf.naechsterName != Schrittname.ausIServImportieren
                            && blatt.attachedSheet === bogen {
                            await warten(300)
                            taste("\r", code: 36, in: bogen)
                            for _ in 0..<8 where speicher.lernendenverlauf.naechsterName != Schrittname.ausIServImportieren {
                                await warten(250)
                            }
                        }
                        let meldung = speicher.meldungen.last?.text ?? "—"
                        pruefen(speicher.lernendenverlauf.naechsterName == Schrittname.ausIServImportieren
                                && meldung.hasSuffix("; 1 Lerngruppe an ihre Zeilen gebunden."),
                                "⌘L-Import „Je Klasse“ mit Bindung: ein Schritt im Verlauf — \(meldung)")
                        taste("\r", code: 36, in: bogen)
                        for _ in 0..<12 where blatt.attachedSheet != nil { await warten(250) }
                        blatt.makeKeyAndOrderFront(nil)
                        blatt.makeFirstResponder(nil)
                        await warten(300)
                        taste("\r", code: 36, in: blatt)
                        for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                        let gruppe = speicher.lernende.bestand?.lerngruppen.first { $0.name == "Klasse1" && $0.archiviert.isEmpty }
                        let gebunden = speicher.lernende.bestand?.gruppe(an: Zeilenbindung(planung: herkunft, klasseId: zeile.id))
                        pruefen(gruppe != nil && gebunden?.id == gruppe?.id,
                                "„Übernehmen“: die neue Lerngruppe „Klasse1“ an die gleichnamige Zeile gebunden (E523)")
                    } else {
                        pruefen(false, "Bogen „Aus IServ importieren“ (Je Klasse) am Blatt „Lernende“")
                        if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                    }
                } else {
                    pruefen(false, "Vorbedingung: Die freie Zeile „Klasse1“ ist angelegt")
                }
                // ── ⌘M, gestörte Sicherung, ⌘Q (Z14c3-08, E329, Z-AS4-05): Die Verlustfrage holt das Fenster aus dem Dock ──
                // Gesperrt wird nur die Lernendendatei, nur hier; danach gilt wieder die Sperre der Sitzung.
                if let fenster = hauptfenster(), fenster.attachedSheet == nil, !speicher.dialogOffen,
                   speicher.rueckfrage == nil, let bestand = speicher.lernende.bestand {
                    let sperre = speicher.lernende.schreibsperre
                    speicher.lernende.schreibsperre = { "Prüfstand: gesperrt" }
                    speicher.lernende.setzen(bestand)
                    fenster.miniaturize(nil)
                    for _ in 0..<12 where !fenster.isMiniaturized { await warten(250) }
                    await warten(500)
                    // Nur mit drohendem Verlust und minimiertem Fenster — sonst ginge `beenden()` durch.
                    if speicher.verlustDroht, fenster.isMiniaturized {
                        speicher.beenden()
                        for _ in 0..<12 where fenster.isMiniaturized || Pruefstaende.alertfenster() == nil { await warten(250) }
                        pruefen(!fenster.isMiniaturized && Pruefstaende.alertfenster() != nil
                                && speicher.rueckfrage?.bestaetigung == "Trotzdem beenden",
                                "⌘M, gestörte Sicherung, ⌘Q: Das Fenster kommt mit der Verlustfrage aus dem Dock")
                        pruefen(speicher.rueckfrage?.skriptgrund
                                == "Die Lernendendaten ließen sich nicht sichern; das Beenden wartet auf eine Antwort.",
                                "ein Skript erführe den Grund: die Lernendendaten")
                        if let fehlt = await Pruefstaende.vonHandAntworten(speicher, false) {
                            pruefen(false, "Knopf „\(fehlt)“ im Alert gefunden")
                        }
                        for _ in 0..<12 where Pruefstaende.alertfenster() != nil { await warten(250) }
                    } else {
                        pruefen(false, "Vorbedingung: Sicherung gestört (\(speicher.verlustDroht ? "ja" : "nein")), "
                                + "Fenster minimiert (\(fenster.isMiniaturized ? "ja" : "nein"))")
                    }
                    if fenster.isMiniaturized {
                        fenster.deminiaturize(nil)
                        for _ in 0..<12 where fenster.isMiniaturized { await warten(250) }
                    }
                    speicher.lernende.schreibsperre = sperre
                    speicher.jetztSichern()
                    pruefen(speicher.lernende.ungesichert == nil && !speicher.verlustDroht,
                            "ohne die Sperre liegen die Lernendendaten wieder auf der Platte")
                } else {
                    pruefen(false, "Vorbedingung für ⌘M und ⌘Q: Hauptfenster ohne Blatt, keine Frage, Lernendendaten geladen")
                }
                einStand()
                // ── Zum Schluss mit gestörter Sicherung (Z-AS4-06, Z-AS4-12): Die Endstelle trifft beim Beenden auf
                // die Verlustfrage und bestätigt „Trotzdem beenden“ wie von Hand — dann muss die App von selbst gehen. ──
                speicher.lernende.schreibsperre = { "Prüfstand: gesperrt" }
                if let bestand = speicher.lernende.bestand { speicher.lernende.setzen(bestand) }
                pruefen(speicher.verlustDroht, "zum Schluss ist die Sicherung gestört — die Endstelle trifft auf die Verlustfrage")
                if speicher.verlustDroht {
                    Pruefstaende.verlustfrageErwartet = true
                    Pruefstaende.schlusspruefung = {
                        let geklickt = Pruefstaende.verlustfrageGeklickt, erneut = Pruefstaende.erneutBeendet
                        return ["  \(geklickt && !erneut ? "✓" : "✗") „Trotzdem beenden“ beendet beim ersten Klick (Z-AS4-06)"
                                + (!geklickt ? " — die Verlustfrage wurde nicht per Klick bestätigt"
                                   : erneut ? " — erst ein weiteres Beenden der Endstelle beendete" : "")]
                    }
                }
            }
            await ende()
        }
    }
}

/// Ein offenes Menü, bedient wie mit der Tastatur: ↓, bis der Eintrag
/// hervorgehoben ist, dann ⏎ — getaktet von einem Zeitgeber in allen
/// Laufmodi, denn das Menü läuft in seinem eigenen. Nach acht Takten ohne
/// Treffer schließt Escape das Menü.
/// Was ein Klick an Menü zutage brachte — Einträge, Haken, geschlossen (B83).
@MainActor
private final class Menuefang {
    var titel: [String] = []
    var angehakt: [String] = []
    var zu = false
    /// Das Menü selbst — falls es offen bliebe, wird es ohne Wahl geschlossen (Z14f-11).
    var menue: NSMenu?
}

/// Ob das Loslassen einer Taste ankam — für den Schritt „Rückmeldungsliste“ (Z-AW5a-02).
@MainActor
private final class Tastenvermerk {
    var oben = false
    /// Der Stand beim Loslassen: Steht der Bogen noch — im Blatt (`nil` ohne Griff) und als Fenster am Blatt?
    var bogenOffen: Bool?
    var bogenAmBlatt = false
}

@MainActor
private final class Menuekasten {
    var titel: [String] = []
    var gewaehlt = false
    var zu = false
    private var takte = 0

    func bedienen(_ menue: NSMenu, _ eintrag: String) {
        titel = menue.items.map(\.title)
        nonisolated(unsafe) let offen = menue
        let zeitgeber = Timer(timeInterval: 0.25, repeats: true) { [weak self] uhr in
            let fertig = MainActor.assumeIsolated { self?.takt(offen, eintrag) ?? true }
            if fertig { uhr.invalidate() }
        }
        RunLoop.main.add(zeitgeber, forMode: .common)
    }

    private func takt(_ menue: NSMenu, _ eintrag: String) -> Bool {
        takte += 1
        if menue.highlightedItem?.title == eintrag {
            gewaehlt = true
            Menuekasten.taste("\r", 36)
            return true
        }
        if takte > 8 {
            Menuekasten.taste("\u{1B}", 53)
            return true
        }
        // ↓ ist in AppKit das Zeichen U+F701 (NSDownArrowFunctionKey).
        Menuekasten.taste(String(Character(UnicodeScalar(0xF701)!)), 125)
        return false
    }

    private static func taste(_ zeichen: String, _ code: UInt16) {
        for art in [NSEvent.EventType.keyDown, .keyUp] {
            guard let ereignis = NSEvent.keyEvent(
                with: art, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, characters: zeichen, charactersIgnoringModifiers: zeichen,
                isARepeat: false, keyCode: code) else { continue }
            NSApp.postEvent(ereignis, atStart: false)
        }
    }
}
