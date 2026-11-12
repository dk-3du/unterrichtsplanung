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
    /// `loeschfrage` die Rückfrage „endgültig löschen“ für Hübner mit gebundenem Tisch, `loeschfrage-mehrere` für Hübner und
    /// Dietz mit zwei Tischen — der dritte Knopf „Löschen und Tisch(e) entfernen“ (v87, AY6a, E882–E884).
    /// `loeschfrage-kopien` wie `loeschfrage`, dazu vorher eine weitere Kopie aus der Umstellung auf Fassung 2 unter festem
    /// Namen (v92, E1049). Die Saat liegt in Fassung 1: Schon beim Lesen entstehen Umstellungskopien, darum nennen auch
    /// `loeschfrage` und `loeschfrage-mehrere` sie — so ist es im Betrieb nach einem Update von vor 2.5.0.
    /// `suche` „Alle Lernenden“ mit der Suche „Hüb“, `sortiert` nach dem Vornamen geordnet, `gruppenfilter` die
    /// Gruppenliste mit dem Filter „Inf“ (v84, AT2b: E359–E363).
    /// `rueckmeldungsliste` der Bogen „Rückmeldungsliste“ am Teil „Mitteilungen“ von g-2, leer wie im Betrieb,
    /// `rueckmeldungsliste-gefuellt` mit gewählter Mitteilung und getipptem Kennwort (v85, AW5), `rueckmeldungsliste-alle`
    /// ebenso, dazu „alle Mitglieder“ statt der Vorgabe (v92, E1044).
    /// v91 (BC1, Prototyp): `mitteilungen-saat` an der ersten Lerngruppe die Mitteilungen aus `mitteilungssaat`, gewählt die
    /// jüngste (V7); `mitteilungen-teil` die an drei; `mitteilungen-frist` die mit verstrichener Frist und eine offene Person
    /// mit ihrer Leiste; `mitteilungen-einzelne` der Bogen „Einzelne …“ mit drei Gewählten (BC4; seit v96 auf dem
    /// Unterblatt „Neue Mitteilung“);
    /// `vereinbarungen-zweizeilig` der Teil „Vereinbarungen“ mit einem langen Namen in der Wahl „für“,
    /// `massnahmen-langer-name` derselbe Name im Teil „Maßnahmen“ (Z-BC5-04).
    /// Mit `ABBILD_MITGLIEDER=42` die Lage der Handprobe.
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

    /// `ABBILD_ZUORDNUNG_SAAT=b1` (v86, Abbild B1 nach R2-A2N): zur Saat drei Zeilen und drei Lerngruppen —
    /// „Mathe-Förder“ (Kurs ohne Stufe, also „mit Mitgliedern“ aus; 12 Lernende, 3 davon auch in der ersten Lerngruppe:
    /// „9 Lernende bleiben im Archiv“, E797), „Chor“ und „Bio-AG Schulgarten“ (ohne Zeile in der neuen Planung: gesperrt,
    /// E796); die neue Planung trägt „Mathe-Förder“ als Zeile. Nur im Speicher des Abbilds, angelegt wird nichts.
    static func zuordnungSaatB1(_ speicher: Planungsspeicher) {
        guard var planung = speicher.planung, var bestand = speicher.lernende.bestand,
              let start = Tag(iso: "2027-08-02") else { return }
        let jetzt = Zeitrechnung.jetztAlsZeitstempel()
        let zeilen = [("k-b1-mf", "Mathe-Förder"), ("k-b1-chor", "Chor"), ("k-b1-bio", "Bio-AG Schulgarten")]
        for (id, name) in zeilen where !planung.klassen.contains(where: { $0.id == id }) {
            planung.klassen.append(Klasse(id: id, name: name, fach: "", notiz: "", farbe: 0, farbeManuell: false))
        }
        speicher.planung = planung
        let erste = bestand.lerngruppen.first?.mitglieder ?? []
        var neueIds: [String] = []
        for nummer in 1...13 {
            let id = "l-b1-\(nummer)"
            neueIds.append(id)
            bestand.lernende.append(Lernender(id: id, vorname: "Probe \(nummer)", nachname: "Abbild", angelegt: jetzt,
                                              geaendert: jetzt, archiviert: ""))
        }
        let herkunft = bestand.planung
        func gruppe(_ id: String, _ name: String, _ mitglieder: [String], _ zeile: String) -> Lerngruppe {
            Lerngruppe(id: id, name: name, art: .kurs, mitglieder: mitglieder,
                       zeilen: [Zeilenbindung(planung: herkunft, klasseId: zeile)], skalen: [:],
                       halbjahreswechsel: "", geaendert: jetzt, archiviert: "")
        }
        bestand.lerngruppen.append(gruppe("g-b1-mf", "Mathe-Förder", Array(erste.prefix(3)) + Array(neueIds.prefix(9)),
                                          "k-b1-mf"))
        bestand.lerngruppen.append(gruppe("g-b1-chor", "Chor", Array(erste.dropFirst(3).prefix(5)), "k-b1-chor"))
        bestand.lerngruppen.append(gruppe("g-b1-bio", "Bio-AG Schulgarten", Array(neueIds.suffix(4)), "k-b1-bio"))
        _ = speicher.lernendenUebernehmen(bestand)
        let leitung = speicher.planung?.klassen.first { $0.art == .klassenleitung }
        speicher.neuePlanungVorgabe = Neuplanungsvorgabe(start: start,
                                                         kurstext: "G7a - Informatik\nG7a - Mathematik\nMathe-Förder",
                                                         mitnehmen: leitung.map { [$0.id: false] } ?? [:])
    }

    /// v90 (Sichtprüfung BB2–BB4): `ABBILD_MITGLIEDER=<n>` füllt die erste Lerngruppe auf n Mitglieder, die ersten zwei neuen
    /// archiviert; `ABBILD_PERSONEN=<n>` füllt das Schuljahr auf n Personen ohne Lerngruppe — für die Grenze des Schuljahrs.
    /// v91 (BC6b): `ABBILD_LERNGRUPPEN=<n>` füllt es auf n Lerngruppen ohne Mitglieder — für die Liste links (E1005);
    /// `ABBILD_GRUPPE=letzte` öffnet das Blatt mit der untersten Lerngruppe der Liste (Z-BC6b-01).
    private static func groesseVorbereiten(_ speicher: Planungsspeicher, gruppe: String?) {
        let umgebung = ProcessInfo.processInfo.environment
        guard let b = speicher.lernende.bestand else { return }
        var neu = b
        let s = Zeitrechnung.jetztAlsZeitstempel()
        if let n = umgebung["ABBILD_MITGLIEDER"].flatMap(Int.init),
           let stelle = neu.lerngruppen.firstIndex(where: { $0.id == gruppe }) {
            let dazu = (0..<max(0, n - neu.lerngruppen[stelle].mitglieder.count)).map { i in
                Lernender(id: Kennung.neu("l"), vorname: "Vorname\(i + 1)", nachname: "Nachname\(i + 1)", angelegt: s, geaendert: s,
                          archiviert: i < 2 ? s : "")
            }
            neu.lernende += dazu
            neu.lerngruppen[stelle].mitglieder += dazu.map(\.id)
        }
        if let n = umgebung["ABBILD_PERSONEN"].flatMap(Int.init), neu.lernende.count < n {
            neu.lernende += (neu.lernende.count..<n).map { i in
                Lernender(id: Kennung.neu("l"), vorname: "V\(i)", nachname: "N\(i)", angelegt: s, geaendert: s, archiviert: "")
            }
        }
        // Höchstens so viele, wie die App zulässt; Kennungen wie beim Anlegen, ohne Zusammenstoß (Z-BC6b-04).
        if let n = umgebung["ABBILD_LERNGRUPPEN"].flatMap(Int.init), neu.lerngruppen.count < min(n, Kennwerte.maxLerngruppen) {
            for i in neu.lerngruppen.count..<min(n, Kennwerte.maxLerngruppen) {
                let id = neu.neueKennung("g", belegt: Set(neu.lerngruppen.map(\.id)))
                neu.lerngruppen.append(Lerngruppe(id: id, name: "Gruppe \(i + 1)", art: .klasse, mitglieder: [], zeilen: [],
                                                  skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: ""))
            }
        }
        if neu != b { _ = speicher.lernende.setzen(neu) }
    }

    /// v91 (BC1, Prototyp und Handprobe): Mitteilungen an der Lerngruppe `gruppe` — „Elternbrief Wandertag“ an alle aktiven
    /// Mitglieder, die Rückmeldefrist vor sieben Tagen verstrichen, ein Drittel erledigt und eine abgelehnt; „Einverständnis
    /// Fotos“ an die ersten drei, Frist in vier Tagen; „Elternabend“ an alle, ohne Frist. Danach kommt „Neu, Nora“ in die
    /// Lerngruppe und ist von keiner betroffen — aufgenommen wird nur von Hand (BC4). Rein am Bestand, damit die Suite es
    /// prüft; `nil` ohne die Lerngruppe, mit weniger als vier aktiven Mitgliedern (mit drei wäre „an drei“ dasselbe wie
    /// „an alle“) oder wenn Nora nicht in die Lerngruppe kommt.
    nonisolated static func mitteilungssaat(_ b: Lernendenbestand, gruppe: String, heute: Tag,
                                            jetzt: String) -> Lernendenbestand? {
        let verzeichnis = Lernendenverzeichnis(b, heute: heute)
        let aktive = verzeichnis.mitglieder(gruppe).map(\.id)
        guard verzeichnis.gruppe(gruppe) != nil, aktive.count >= 4,
              let brief = b.mitNeuemAnliegen(.mitteilung, titel: "Elternbrief Wandertag", lerngruppe: gruppe,
                                             betroffene: aktive, datum: heute.plus(tage: -14).iso,
                                             frist: heute.plus(tage: -7).iso, jetzt: jetzt),
              let fotos = brief.bestand.mitNeuemAnliegen(.mitteilung, titel: "Einverständnis Fotos", lerngruppe: gruppe,
                                                         betroffene: Array(aktive.prefix(3)),
                                                         datum: heute.plus(tage: -3).iso, frist: heute.plus(tage: 4).iso,
                                                         jetzt: jetzt),
              let abend = fotos.bestand.mitNeuemAnliegen(.mitteilung, titel: "Elternabend", lerngruppe: gruppe,
                                                         betroffene: aktive, datum: heute.plus(tage: -1).iso, frist: "",
                                                         jetzt: jetzt) else { return nil }
        // Am Wandertag ein Drittel erledigt, die letzte abgelehnt — die übrigen offen, ihre Frist verstrichen.
        var c = abend.bestand
        for p in aktive.prefix(max(1, aktive.count / 3)) {
            c = c.mitRuecklauf(brief.id, p, stand: .erledigt, datum: heute.plus(tage: -9).iso, notiz: "", jetzt: jetzt)
        }
        if let p = aktive.last {
            c = c.mitRuecklauf(brief.id, p, stand: .abgelehnt, datum: heute.plus(tage: -8).iso, notiz: "Kein Bus",
                               jetzt: jetzt)
        }
        let nora = c.neueKennung("l", belegt: Set(c.lernende.map(\.id)))
        c.lernende.append(Lernender(id: nora, vorname: "Nora", nachname: "Neu", angelegt: jetzt, geaendert: jetzt,
                                    archiviert: ""))
        return c.mitMitglied(nora, inGruppe: gruppe, jetzt: jetzt)
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
        let mitG2 = ["mitteilungen", "mitteilungen-mehrere", "mitteilungen-mehrere-lang", "rueckmeldungsliste",
                     "rueckmeldungsliste-gefuellt", "rueckmeldungsliste-alle"].contains(lage)
        // Z-AZ4-03: ein langer Titel an „m-1“ (150 Zeichen) — das Menü der Sammelleiste kürzt, die Spalte bleibt.
        if lage == "mitteilungen-mehrere-lang", let b = bestand, let m = b.anliegen.first(where: { $0.id == "m-1" }) {
            _ = speicher.lernende.setzen(b.mitAnliegen("m-1", titel: "Elternbrief zum Wandertag an den Edersee mit Hinweisen zu Proviant, wetterfester Kleidung, festem Schuhwerk, Sonnenschutz und den Abholzeiten am Abend",
                                                       datum: m.datum, frist: m.frist, notiz: m.notiz,
                                                       jetzt: Zeitrechnung.jetztAlsZeitstempel()))
        }
        groesseVorbereiten(speicher, gruppe: gruppe?.id)
        // v91 (BC1): die Saat an der ersten Lerngruppe — nach `ABBILD_MITGLIEDER`, damit sie alle Mitglieder trifft.
        if ["mitteilungen-saat", "mitteilungen-teil", "mitteilungen-frist", "mitteilungen-einzelne"].contains(lage),
           let g = gruppe?.id,
           let b = speicher.lernende.bestand,
           let neu = mitteilungssaat(b, gruppe: g, heute: .heute, jetzt: Zeitrechnung.jetztAlsZeitstempel()) {
            _ = speicher.lernendenUebernehmen(neu)
        }
        let unterste = ProcessInfo.processInfo.environment["ABBILD_GRUPPE"] == "letzte"
            ? speicher.lernende.bestand.flatMap { Lernendenblatt.gruppenliste($0, archivierte: false, suche: "").last?.id }
            : nil
        speicher.lernendenBlattOeffnen(gruppe: mitG2 ? "g-2" : unterste ?? gruppe?.id)
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
        case "loeschfrage", "loeschfrage-mehrere", "loeschfrage-kopien":
            // AY6a (E882–E884): die Rückfrage „endgültig löschen“ mit gebundenen Tischen und dem dritten Knopf „Löschen und
            // Tisch entfernen“ bzw. „… Tische entfernen“. In der Kopie der Probe: ein Sitzplan der ersten Zeile, die einen
            // trägt, mit Tischen für Hübner (und Dietz) und einem ungebundenen „Gast“; gelöscht wird nichts.
            // „-kopien“ (E1049): dazu eine Kopie der Jahresdatei unter festem Namen — ein Stempel der Uhr fiele womöglich mit dem
            // der Kopie beim Lesen zusammen und überschriebe sie (R-BD5-01).
            let namen = lage == "loeschfrage-mehrere" ? ["Hübner", "Dietz"] : ["Hübner"]
            if lage == "loeschfrage-kopien" {
                let ablage = speicher.sicherung.ablage
                _ = ablage.dateiKopieren(ablage.lernende, als: "lernende-fassung1-2026-09-01-074500.json")
            }
            let personen = namen.compactMap { n in bestand?.lernende.first { $0.nachname == n } }
            if let zeile = speicher.planung?.klassen.first(where: \.erlaubtSitzplan)?.id {
                let tische: [Sitzplan.Platzvorlage] = personen.map { .init(name: $0.anzeigename, lernender: $0.id) }
                    + [.init(name: "Gast", lernender: "")]
                _ = speicher.sitzplaene.setzen(Sitzplan.anordnen(klasseId: zeile, lernende: tische), fuer: zeile)
            }
            speicher.lernendenVorgabe?.ansicht = .alle
            Task { @MainActor in
                // Erst, wenn das Blatt steht — die Frage hängt am Blatt (E418).
                @MainActor func blatt() -> NSWindow? { NSApp.windows.first { $0.isVisible && $0.parent == nil }?.attachedSheet }
                for _ in 0..<30 where blatt() == nil || !speicher.lernendenblattOffen {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard blatt() != nil, let jetzt = speicher.lernende.bestand else { return }
                try? await Task.sleep(for: .milliseconds(300))
                speicher.personenLoeschenFragen(personen.map(\.id), in: jetzt) { _ in }
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
               let alle = speicher.lernende.verzeichnis?.alle,
               case let personen = ProcessInfo.processInfo.environment["ABBILD_TERMINPERSONEN"].flatMap(Int.init)
                   .map({ Array(alle.prefix($0)) }) ?? alle.filter({ ["Hübner", "Iversen"].contains($0.nachname) }) {
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
        case "mitteilungen-saat":
            // v91 (BC1, V7): ohne Vorgabe der Mitteilung — gewählt ist die jüngste, „Elternabend“ an alle.
            speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
        case "mitteilungen-teil", "mitteilungen-frist":
            // v91 (BC1): „Einverständnis Fotos“ an drei, bzw. „Elternbrief Wandertag“ mit verstrichener Frist und dazu eine
            // Person, die noch offen steht — ihre Leiste unter der Tabelle.
            speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
            let titel = lage == "mitteilungen-teil" ? "Einverständnis Fotos" : "Elternbrief Wandertag"
            let saat = speicher.lernende.bestand
            if let m = saat?.anliegen.last(where: { $0.art == .mitteilung && $0.titel == titel }) {
                speicher.lernendenVorgabe?.anliegen = m.id
                if lage == "mitteilungen-frist" {
                    let zurueck = Set(saat?.rueckmeldungen.filter { $0.anliegen == m.id }.map(\.lernender) ?? [])
                    speicher.lernendenVorgabe?.person = m.betroffene.first { !zurueck.contains($0) }
                }
            }
        case "mitteilungen-einzelne":
            // v91 (BC1, BC4): der Bogen „Einzelne …“ mit den ersten drei aktiven Mitgliedern gewählt — angelegt wird nichts;
            // seit v96 auf dem Unterblatt „Neue Mitteilung“ (R-BH5-03).
            speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
            speicher.lernendenVorgabe?.adressaten = gruppe.flatMap { g in
                speicher.lernende.verzeichnis?.mitglieder(g.id).prefix(3).map(\.id)
            }
        case "vereinbarungen-zweizeilig", "massnahmen-langer-name":
            // v91 (BC1, BC5): ein langer Name in der ersten Lerngruppe, nach Namen vorn — „für“ zeigt ihn, höchstens 280
            // breit und gekürzt (W3-08). Die Zeile „Neue Vereinbarung“ trägt das Feld dennoch lesbar, darunter „gültig bis
            // einschließlich“ und „Anlegen“. `massnahmen-langer-name` zeigt denselben Namen im Teil „Maßnahmen“ (Z-BC5-04).
            if let g = gruppe?.id, var b = speicher.lernende.bestand {
                let s = Zeitrechnung.jetztAlsZeitstempel()
                let id = b.neueKennung("l", belegt: Set(b.lernende.map(\.id)))
                b.lernende.append(Lernender(id: id, vorname: "Anna-Katharina Friederike", nachname: "Abendroth-Schöneberger",
                                            angelegt: s, geaendert: s, archiviert: ""))
                _ = speicher.lernendenUebernehmen(b.mitMitglied(id, inGruppe: g, jetzt: s) ?? b)
            }
            speicher.lernendenVorgabe?.gruppenteil = lage == "massnahmen-langer-name" ? .massnahmen : .vereinbarungen
        case "mitteilungen-mehrere", "mitteilungen-mehrere-lang":
            // v88, AZ4 (E929): die Sammelleiste — alle Mitglieder von g-2 an „m-1“ gewählt.
            speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
            speicher.lernendenVorgabe?.anliegen = "m-1"
            speicher.lernendenVorgabe?.mehrere = bestand?.lerngruppen.first { $0.id == "g-2" }?.mitglieder ?? []
        case "rueckmeldungsliste", "rueckmeldungsliste-gefuellt", "rueckmeldungsliste-alle":
            // AW5 (E401, E408): der Bogen am Teil „Mitteilungen“ — leer wie im Betrieb, oder mit der gewählten Mitteilung
            // und getipptem Kennwort; „-alle“ dazu mit „alle Mitglieder“ statt der Vorgabe (E1044).
            speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
            let kennwort = "Elternbriefe 2026"
            speicher.lernendenVorgabe?.rueckmeldungsliste = lage == "rueckmeldungsliste" ? Rueckmeldungsbogenvorgabe()
                : Rueckmeldungsbogenvorgabe(auswahl: ["m-1"], kennwort: kennwort, wiederholung: kennwort,
                                            umfang: lage == "rueckmeldungsliste-alle" ? .alleMitglieder : .nurBetroffene)
        case "archiv":
            speicher.lernendenVorgabe?.ansicht = .archiv
        case "archiv-laufend", "archiv-laufend-gruppen":
            // E643, E644, E760 (AX1): in der Kopie der Probe eine Lerngruppe und eine Person archiviert — der Eintrag des
            // laufenden Schuljahrs, Teil „Personen“ bzw. „Lerngruppen“.
            if let bestand, let g = bestand.lerngruppen.first, let p = bestand.lernende.first(where: { $0.nachname == "Hübner" }) {
                let jetzt = Zeitrechnung.jetztAlsZeitstempel()
                _ = speicher.lernendenUebernehmen(bestand.mitArchivierterGruppe(g.id, jetzt: jetzt)
                    .mitArchivierterPerson(p.id, jetzt: jetzt))
            }
            speicher.lernendenVorgabe?.ansicht = .archiv
            speicher.lernendenVorgabe?.archivteil = lage == "archiv-laufend" ? .personen : .lerngruppen
        case "vereinbarungen", "vereinbarungen-alle":
            // E851–E854: in der Kopie der Probe zwei Vereinbarungen der ersten Lerngruppe — „Handyregel“ für die
            // ersten beiden Mitglieder, bis einschließlich in vier Wochen, das zweite von Hand ungültig; „Sitzplatz am Fenster“
            // für das erste ohne Datum — und eine ohne Lerngruppe. Gewählt: das erste Mitglied an der „Handyregel“, im Teil
            // „Vereinbarungen“ bzw. unter „Alle Lernenden“.
            if let bestand, let g = gruppe, g.mitglieder.count >= 2 {
                let erste = g.mitglieder[0], zweite = g.mitglieder[1]
                let jetzt = Zeitrechnung.jetztAlsZeitstempel()
                if let regel = bestand.mitNeuemAnliegen(.vereinbarung, titel: "Handyregel", lerngruppe: g.id,
                                                        betroffene: [erste, zweite], datum: Tag.heute.iso,
                                                        frist: Tag.heute.plus(tage: 28).iso, jetzt: jetzt),
                   let platz = regel.bestand.mitNeuemAnliegen(.vereinbarung, titel: "Sitzplatz am Fenster", lerngruppe: g.id,
                                                              betroffene: [erste], datum: Tag.heute.iso, frist: "", jetzt: jetzt),
                   let ohne = platz.bestand.mitNeuemAnliegen(.vereinbarung, titel: "Nachreichen per Mail", lerngruppe: "",
                                                             betroffene: [erste], datum: Tag.heute.iso, frist: "", jetzt: jetzt) {
                    let mitInhalt = ohne.bestand.mitAnliegen(regel.id, titel: "Handyregel", datum: Tag.heute.iso,
                                                             frist: Tag.heute.plus(tage: 28).iso,
                                                             notiz: "Das Handy bleibt im Unterricht in der Tasche.", jetzt: jetzt)
                    _ = speicher.lernendenUebernehmen(mitInhalt.mitGueltigkeit(regel.id, zweite, .ungueltig, heute: .heute,
                                                                               jetzt: jetzt).bestand)
                    speicher.lernendenVorgabe?.anliegen = regel.id
                }
                speicher.lernendenVorgabe?.person = erste
            }
            if lage == "vereinbarungen" {
                speicher.lernendenVorgabe?.gruppenteil = .vereinbarungen
            } else {
                speicher.lernendenVorgabe?.ansicht = .alle
            }
        case "archiv-laufend-leer":
            // Nichts archiviert, mit Vorjahr: ein Satz (E760).
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
    /// Die Frist der Reißleine in Sekunden — unter der des Treibers (420 s); der längste Lauf braucht am Mac rund 170 s
    /// („lernende-versiegelt“, 11.11.2026, mit 208 Zeilen; E413, Z-GR3-07, R-BH8-W2-06), die VM länger — das wird in
    /// F56 vermerkt.
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
            /// Ein Mausklick, eingereiht wie von der Maus: Drücken, nach `halten` ms Loslassen — eine Hand hält etwa 100 ms, und
            /// in der Zeit läuft die Mausverfolgung der Tabelle (aus BC7c, R7c-01). Danach ebenso lange Ruhe, wie zwischen zwei Klicks
            /// einer Hand: Die AppKit-Tabelle zeigt die neue Wahl schon beim Drücken, SwiftUI zeichnet erst nach dem Loslassen —
            /// ein Klick davor würde überschrieben, und die Warteschleife danach sähe nur die Tabelle.
            @MainActor func klicken(_ punkt: NSPoint, in fenster: NSWindow, _ tasten: NSEvent.ModifierFlags = [],
                                    halten: Int = 120) async {
                for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if art == .leftMouseUp { await warten(halten) }
                    if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: tasten,
                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: fenster.windowNumber, context: nil, eventNumber: 0,
                                                         clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                        NSApp.postEvent(ereignis, atStart: false)
                    }
                }
                await warten(halten)
            }
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
                    // Zuoberst: seit v96 bis zu drei Ebenen — Blatt → Unterblatt → Bogen (R-BH5-04).
                    var oben = blatt
                    while let darauf = oben.attachedSheet { oben = darauf }
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
                                     ziele: ["g-1": Gruppenwahl(name: "G7a", zeilen: [.kennung(getippt[0].id)])],
                                     // Wie das Blatt ohne geöffneten Bogen: die Vorbelegung — „G6a“ trägt eine Stufe, kommt also
                                     // mit Mitgliedern (E708; Z-AX2-01).
                                     ohneMitglieder: Hochstufung.ohneMitglieder(
                                         speicher.lernende.bestand?.lerngruppen.filter { $0.id == "g-1" } ?? []))
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

                // Was ein Schritt einem späteren lässt (E951): die Werte als Variablen des Blocks, gesetzt im gebenden Schritt —
                // AP8 für die Rückmeldungsliste, das Archiv (AP9) für AX7b, AP13b für AP13c-1 —, die Hilfen vor den Schritten.
                var mitteilung: Anliegen?
                var gruppeDerMitteilung: Lerngruppe?
                var vorSaatAX7b: Lernendenbestand?
                var saatAX7b: [String] = []
                var blatt3: NSWindow!
                var rahmenOben = NSRect.zero
                var laufend = "—"
                var wahlVorher: NSPopUpButton?
                var terminperson: Lernender?

                /// Einen Umschalter so bedienen, wie ein Klick es täte: Segment wählen, Handlung senden.
                @MainActor func waehlen(_ schalter: NSSegmentedControl, _ beschriftung: String) -> Bool {
                    guard let stelle = (0..<schalter.segmentCount).first(where: { schalter.label(forSegment: $0) == beschriftung })
                    else { return false }
                    schalter.selectedSegment = stelle
                    return schalter.sendAction(schalter.action, to: schalter.target)
                }
                @MainActor func namensliste() -> [String] {
                    (speicher.lernende.bestand?.lernende ?? []).map { "\($0.id)|\($0.nachname)|\($0.vorname)" }
                }
                // Das Menü der Wahl wie von Hand (`menueAmPunkt`): ein Klick in die Zeile unter dem oberen Umschalter, links
                // und abseits der Knöpfe, abgetastet, bis sich ein Menü öffnet. „2025/26“ muss darin stehen und
                // angehakt sein. Geschlossen wird ohne Wahl (`cancelTracking`) — die Klassenmessung zeigt den Weg
                // unter macOS 26 (SwiftUIMenu) und 27 (NSMenu, die Wahl ohne eigene AppKit-Ansicht). Kein blindes ⎋
                // — im Blatt hieße es „Abbrechen“.
                /// `waehlen`: Diesen Eintrag wählen, statt das Menü ohne Wahl zu schließen (E788 — die Wahl steht beim Öffnen
                /// auf dem laufenden Schuljahr; zum Vorjahr wird gewählt wie von Hand).
                @MainActor func menueDerWahl(waehlen: String? = nil) async -> (titel: [String], angehakt: [String], ort: String)? {
                    // Erst nach AP9 gerufen, das `blatt3` setzt; ohne Blatt kein Menü statt eines Absturzes (G2-01).
                    guard let blatt3 else { return nil }
                    // Die Mitte zuerst: Die Wahl ist 24 pt hoch, die Zeilenmitte liegt 36 pt unter der des
                    // Umschalters (Klassenmessung, beide Systeme); 24 und 48 sind ihre Kanten (Z14f-10).
                    let raster = [36.0, 30.0, 42.0, 24.0, 48.0].flatMap { dy in [110.0, 80.0, 140.0].map { dx in (dx: dx, dy: dy) } }
                    let punkte = raster.map { NSPoint(x: rahmenOben.minX + $0.dx, y: rahmenOben.midY - $0.dy) }
                    let menue = await menueAmPunkt(blatt3, punkte, passt: { $0.contains("2025/26") },
                                                   waehlen: waehlen.map { eintragMitTitel($0) })
                    guard let stelle = menue.punkt else { return nil }
                    // Ein Menü, das offen blieb, schluckte ⌘⌫ und ⎋ der folgenden Schritte (Z14f-11); `menueAmPunkt` schloss es.
                    return (menue.titel, menue.angehakt, "+\(Int(raster[stelle].dx)) pt, −\(Int(raster[stelle].dy)) pt"
                                + (menue.bliebOffen ? ", blieb offen und wurde geschlossen" : ""))
                }
                @MainActor func bogenfeld(_ passt: (NSTextField) -> Bool) -> NSTextField? {
                    suchen(hauptfenster()?.attachedSheet?.attachedSheet?.contentView, NSTextField.self, passt)
                }
                @MainActor func gebundeneInDatei() -> [String]? {
                    (try? Data(contentsOf: ablage.sitzplaene)).flatMap { try? tresor.oeffnen($0) }
                        .flatMap { try? Sitzplandatei.lesen($0) }?["k-1"]?.tische.map(\.lernender)
                }

                @MainActor func schrittBlattLernende() async -> Bool {
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
                    return false
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
                    return false
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
                    return false
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
                return true
                }
                guard await schrittBlattLernende() else { return }

                @MainActor func schrittUebernehmenGetippt() async {
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
                                // Oben drei Teile („Alle Lernenden“), in der Lerngruppe seit v86 vier („Mitteilungen“, AX3).
                                [3, 4].contains($0.segmentCount) && $0.label(forSegment: 1) == beschriftung }),
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
                }
                await schrittUebernehmenGetippt()

                @MainActor func schrittRuecklauf() async -> Bool {
                // ── Rücklauf (AP8): Mitteilung anlegen, drei Rückläufe eintragen ──
                let namenVorher = namensliste()
                taste("l", code: 37, [.command], in: hauptfenster())
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                guard var blatt2 = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende else {
                    pruefen(false, "⌘L öffnet das Blatt ein zweites Mal")
                    await ende()
                    return false
                }
                blatt2.makeKeyAndOrderFront(nil)
                // Je warten, bis das Element steht — nicht fest (Z14f-03).
                @MainActor func teilwahl() -> NSSegmentedControl? {
                    // Vier Teile seit v86 (E741, AX3): „Vereinbarungen“ dazu.
                    suchen(blatt2.contentView, NSSegmentedControl.self, { $0.segmentCount == 4 && $0.label(forSegment: 1) == "Mitteilungen" })
                }
                for _ in 0..<40 where teilwahl() == nil { await warten(250) }
                guard let teil = teilwahl(), waehlen(teil, "Mitteilungen") else {
                    pruefen(false, "Umschalter „Mitglieder / Mitteilungen / Maßnahmen / Vereinbarungen“ gefunden und bedient")
                    await ende()
                    return false
                }
                // Seit v96 keine Anlegezeile: „Neue Mitteilung …“ öffnet ein Unterblatt (E1172). Der Knopf ist kein
                // `NSButton` — die Probe öffnet das Unterblatt über die Vorgabe (wie E678): Das Blatt geht zu und kommt
                // mit derselben (ersten) Gruppe, dem Teil „Mitteilungen“ und dem Unterblatt wieder.
                guard await blattSchliessen() else {
                    pruefen(false, "Blatt vor „Neue Mitteilung …“ geschlossen")
                    await ende()
                    return false
                }
                speicher.lernendenBlattOeffnen()
                speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                speicher.lernendenVorgabe?.neueMitteilung = true
                for _ in 0..<40 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                guard let wieder = hauptfenster()?.attachedSheet, let unterblatt = wieder.attachedSheet,
                      let neuFeld = suchen(unterblatt.contentView, NSTextField.self, {
                          $0.placeholderString == "z. B. Elternbrief Wandertag" }) else {
                    pruefen(false, "Unterblatt „Neue Mitteilung“ mit dem Feld „Titel“ am Blatt (E1172)")
                    await ende()
                    return false
                }
                blatt2 = wieder
                pruefen(true, "Unterblatt „Neue Mitteilung“ am Blatt, Feld „Titel“ gefunden (E1172)")
                let befundNeu = await Lernendenprobe.unterblattBeimBeenden(speicher, unterblatt, warten: warten)
                pruefen(befundNeu == nil, "⌘Q bei offenem Unterblatt „Neue Mitteilung“: die Frage auf ihm, „Weiter bearbeiten“ "
                            + "lässt es stehen (R-BH5-02)" + (befundNeu.map { " — " + $0 } ?? ""))
                unterblatt.makeKeyAndOrderFront(nil)
                unterblatt.makeFirstResponder(neuFeld)
                await warten(200)
                tippen("Rücklauf Probe\n", in: unterblatt)
                @MainActor func ruecklaufliste() -> NSTableView? {
                    suchen(blatt2.contentView, NSTableView.self, { Lernendenprobe.istMitteilungstabelle($0) })
                }
                for _ in 0..<40 where speicher.lernendenverlauf.naechsterName != Schrittname.mitteilungAnlegen
                    || ruecklaufliste() == nil { await warten(250) }
                pruefen(speicher.lernendenverlauf.naechsterName == Schrittname.mitteilungAnlegen,
                        "Mitteilung „Rücklauf Probe“ mit ⏎ angelegt (\(speicher.lernendenverlauf.naechsterName ?? "—"))")
                // Mit dem heutigen Tag — ein Tagesfeld hat das Unterblatt nicht (E1172).
                let neueM = speicher.lernendenblattGriff?.aenderungen()?.anliegen.first { $0.titel == "Rücklauf Probe" }
                pruefen(neueM?.datum == Tag.heute.iso, "„Rücklauf Probe“ trägt den heutigen Tag (\(neueM?.datum ?? "—"), E1172)")
                guard let tabelle = ruecklaufliste() else {
                    var gesehen: [String] = []
                    @MainActor func sammeln(_ a: NSView) {
                        if let t = a as? NSTableView { gesehen.append(t.tableColumns.map(\.title).joined(separator: "|")) }
                        a.subviews.forEach(sammeln)
                    }
                    if let inhalt = blatt2.contentView { sammeln(inhalt) }
                    pruefen(false, "Rücklaufliste gefunden (Tabellen: \(gesehen))")
                    await ende()
                    return false
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
                // v91 (BC2, V1–V3): eine Tabelle der gewählten Mitteilung — Person · Mitteilung · Frist · Stand wie bei den
                // Maßnahmen, die Stand-Spalte fest 130 breit (E641); gewählt ist die neue (V7), je Betroffener unter den
                // Mitgliedern eine Zeile (V2).
                let spalten = tabelle.tableColumns.map(\.title)
                let staende = tabelle.tableColumns.last.map { Int($0.width.rounded()) }
                let entwurfJetzt = speicher.lernendenblattGriff?.aenderungen()
                let neue = entwurfJetzt?.anliegen.last { $0.titel == "Rücklauf Probe" && $0.art == .mitteilung }
                let zeilenSoll = entwurfJetzt.flatMap { e in
                    neue.map { Ruecklaufliste.zeilen($0, Lernendenverzeichnis(e).mitglieder($0.lerngruppe)).count }
                }
                pruefen(spalten == Lernendenprobe.mitteilungsspalten && staende == 130 && tabelle.numberOfRows == zeilenSoll,
                        "Tabelle der gewählten Mitteilung: Spalten \(spalten), „Stand“ \(staende.map(String.init) ?? "—") breit, "
                        + "\(tabelle.numberOfRows) Zeilen — erwartet die Betroffenen unter den Mitgliedern: "
                        + "\(zeilenSoll.map(String.init) ?? "—") (V1–V3)")
                // Das Auswahlfeld über der Tabelle zeigt die neue (V1, V7). Unter macOS 26 ist es ein NSPopUpButton; unter
                // macOS 27 hat es keine eigene AppKit-Ansicht, und die Probe öffnet sein Menü wie von Hand mit einem Klick über
                // die Tabelle — angehakt ist die gezeigte (K2, E1019). Unter 26 läuft dieser Weg zur Auskunft mit, wie bei der
                // Schuljahreswahl im Archiv. Die Schritte danach gehen denselben Weg wie hier (`auswahlknopf`).
                let auswahlknopf = neue.flatMap { n in
                    suchen(blatt2.contentView, NSPopUpButton.self, { $0.itemTitles.contains(Ruecklaufliste.wahltitel(n)) })
                }
                if let neue {
                    let soll = Ruecklaufliste.wahltitel(neue)
                    if let wahl = auswahlknopf {
                        pruefen(wahl.titleOfSelectedItem == soll,
                                "das Auswahlfeld über der Tabelle zeigt die neue Mitteilung: „\(wahl.titleOfSelectedItem ?? "—")“")
                    }
                    let menue = await menueAmPunkt(blatt2, Menueanker.auswahlfeld(tabelle), passt: { $0.contains(soll) })
                    let wieVonHand = menue.gefunden ? "Menü \(menue.eintraege), angehakt \(menue.angehakt)"
                        : "kein Menü (" + menue.verlauf.joined(separator: "; ") + ")"
                    if auswahlknopf != nil {
                        zeilen.append("  Auskunft, Weg ohne NSPopUpButton: \(wieVonHand) — trüge "
                                      + (menue.angehakt == [soll] ? "ja" : "nein"))
                    } else {
                        pruefen(menue.angehakt == [soll],
                                "das Auswahlfeld über der Tabelle zeigt die neue Mitteilung, wie von Hand: \(wieVonHand) (K2)")
                    }
                }
                // E280: Ein echter Klick auf den Stand in der Tabelle öffnet die drei Stände —
                // vierte Zeile, Spalte „Stand“ (die letzte). Gewählt wird im
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
                // v91 (Z-BC2-01): Wechselt links die Lerngruppe, zeigt die Rücklaufliste die jüngste Mitteilung der neuen
                // (E993) — Auswahlfeld und Tabelle; zurück wieder die der ersten. Ein echter Klick in die Gruppenliste (E303).
                @MainActor func gruppenliste() -> NSTableView? {
                    var tabellen: [NSTableView] = []
                    @MainActor func sammeln(_ a: NSView) {
                        if let t = a as? NSTableView, !t.isHiddenOrHasHiddenAncestor { tabellen.append(t) }
                        a.subviews.forEach(sammeln)
                    }
                    if let inhalt = blatt2.contentView { sammeln(inhalt) }
                    return tabellen.min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
                }
                @MainActor func gruppeKlicken(_ zeile: Int) {
                    guard let links = gruppenliste(), zeile < links.numberOfRows else { return }
                    let r = links.rect(ofRow: zeile)
                    let punkt = links.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
                    for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                                             windowNumber: blatt2.windowNumber, context: nil, eventNumber: 0,
                                                             clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                            NSApp.postEvent(ereignis, atStart: false)
                        }
                    }
                }
                /// Die jüngste Mitteilung einer Gruppe im Entwurf, die Zahl ihrer Zeilen und alle Einträge des Auswahlfelds.
                @MainActor func erwartet(_ gruppe: String) -> (titel: String, zeilen: Int, alle: [String])? {
                    guard let e = speicher.lernendenblattGriff?.aenderungen() else { return nil }
                    let v = Lernendenverzeichnis(e)
                    let ms = v.mitteilungen(der: gruppe)
                    guard let id = Ruecklaufliste.startwahl(nil, ms), let m = ms.first(where: { $0.id == id }) else { return nil }
                    return (Ruecklaufliste.wahltitel(m), Ruecklaufliste.zeilen(m, v.mitglieder(gruppe)).count,
                            ms.map(Ruecklaufliste.wahltitel))
                }
                /// Das Auswahlfeld mit genau diesen Einträgen und die Tabelle (Z-BC2N-04).
                @MainActor func auswahlfeld(_ alle: [String]) -> NSPopUpButton? {
                    suchen(blatt2.contentView, NSPopUpButton.self, { !alle.isEmpty && $0.itemTitles == alle })
                }
                /// Was das Auswahlfeld zeigt, und die Zeilen der Tabelle: am NSPopUpButton mit genau diesen Einträgen, sonst am
                /// Haken seines Menüs, wie von Hand (K2).
                // Ging beim letzten Blick wie von Hand an keinem Punkt ein Menü auf, fragt `gezeigtWarten` nicht weiter
                // (R8d-11): Jede Frage kostet bis zu fünf Klicks.
                var auswahlStumm = false
                @MainActor func gezeigt(_ alle: [String]) async -> (titel: String, zeilen: Int)? {
                    guard let t = ruecklaufliste() else { return nil }
                    if auswahlknopf != nil {
                        guard let titel = auswahlfeld(alle)?.titleOfSelectedItem else { return nil }
                        return (titel, t.numberOfRows)
                    }
                    // Ging das Feld auf, passte aber nicht (es zeigt noch die vorige Lerngruppe), fragt `gezeigtWarten` nach
                    // 250 ms neu, statt die übrigen Punkte abzuklicken (U2-03).
                    let menue = await menueAmPunkt(blatt2, Menueanker.auswahlfeld(t), passt: { !alle.isEmpty && $0 == alle },
                                                   einMenueGenuegt: true)
                    auswahlStumm = !menue.menueGesehen
                    guard menue.angehakt.count == 1 else { return nil }
                    // Die Zeilen nach dem Blick: Ersetzt SwiftUI die Tabelle beim Wechsel, gälte sonst die alte (U2-07).
                    return (menue.angehakt[0], ruecklaufliste()?.numberOfRows ?? t.numberOfRows)
                }
                /// Bis das Auswahlfeld zeigt, was `soll` nennt — wie von Hand seltener gefragt, denn jede Frage öffnet das Menü.
                @MainActor func gezeigtWarten(_ soll: (titel: String, zeilen: Int, alle: [String])?) async
                    -> (titel: String, zeilen: Int)? {
                    var ist = await gezeigt(soll?.alle ?? [])
                    for _ in 0..<(auswahlknopf != nil ? 16 : 4) where (ist.map({ $0.titel != soll?.titel }) ?? true) && !auswahlStumm {
                        await warten(250)
                        ist = await gezeigt(soll?.alle ?? [])
                    }
                    return ist
                }
                // Die Gruppe der geklickten Zeile — in der Folge der Liste (Z-BC2N-04).
                let liste = entwurfJetzt.map { Lernendenblatt.gruppenliste($0, archivierte: false, suche: "") } ?? []
                if let links = gruppenliste(), links.numberOfRows > 1, links.numberOfRows == liste.count,
                   let erste = neue?.lerngruppe {
                    let schritteVorWechsel = speicher.lernendenverlauf.zurueck.count
                    let vorher = links.selectedRow
                    let ziel = vorher == 0 ? 1 : 0
                    gruppeKlicken(ziel)
                    let soll = erwartet(liste[ziel].id)
                    let ist = await gezeigtWarten(soll)
                    pruefen(soll != nil && ist?.titel == soll?.titel && ist?.zeilen == soll?.zeilen,
                            "Lerngruppe gewechselt: die Rücklaufliste zeigt die jüngste der neuen — „\(ist?.titel ?? "nichts")“, "
                                + "\(ist?.zeilen ?? 0) Zeilen, erwartet „\(soll?.titel ?? "—")“, \(soll?.zeilen ?? 0) (Z-BC2-01)")
                    gruppeKlicken(vorher)
                    let zurueckSoll = erwartet(erste)
                    let zurueck = await gezeigtWarten(zurueckSoll)
                    let schritteNachWechsel = speicher.lernendenverlauf.zurueck.count
                    pruefen(zurueck?.titel == zurueckSoll?.titel && zurueck?.zeilen == zurueckSoll?.zeilen
                                && schritteNachWechsel == schritteVorWechsel,
                            "zurück zur ersten Lerngruppe: wieder ihre jüngste — „\(zurueck?.titel ?? "nichts")“; der Wechsel ist "
                                + "kein Schritt (\(schritteVorWechsel) → \(schritteNachWechsel), Z-BC2-01)")
                    // Z-BC2N-01 entfällt seit v96: Unter der Tabelle steht kein Titelfeld mehr — Titel, Tag, Frist und
                    // „Auch an …“ ändert das Unterblatt „Einstellungen der Mitteilung“ auf einer Kopie, erst „Fertig“ schreibt
                    // (E1175). Den Weg prüft der Schritt der Unterblätter (BH5).
                    zeilen.append("  Auskunft: Z-BC2N-01 entfällt — kein Titelfeld unter der Tabelle mehr (E1175)")
                    // Die Frist über die Oberfläche prüft die Suite (Z-BC3-01): Kästchen von SwiftUI sind unter macOS 26
                    // keine NSButton, und der Weg über die Bedienungshilfen ist zwischen 26 und 27 verschieden.
                } else {
                    pruefen(false, "Gruppenliste wie im Blatt für den Wechsel gefunden — \(liste.count) Gruppen (Z-BC2-01)")
                }
                blatt2.makeFirstResponder(nil)
                taste("\r", code: 36, in: blatt2)
                for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                let mitRuecklauf = speicher.lernende.bestand
                mitteilung = mitRuecklauf?.anliegen.first { $0.titel == "Rücklauf Probe" }
                gruppeDerMitteilung = mitRuecklauf?.lerngruppen.first { $0.id == mitteilung?.lerngruppe }
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
                return true
                }
                guard await schrittRuecklauf() else { return }

                @MainActor func schrittRueckmeldungsliste() async {
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
                                // Jede verfehlte Bedingung beim Namen (G2-03).
                                var abweichend: [String] = []
                                if panel.sheetParent !== blattB { abweichend.append("hängt nicht am Blatt") }
                                if panel.nameFieldStringValue != name { abweichend.append("Name „\(panel.nameFieldStringValue)“ statt „\(name)“") }
                                if panel.message != Rueckmeldungslistenbogen.sichernNachricht { abweichend.append("Nachricht „\(panel.message ?? "")“") }
                                pruefen(abweichend.isEmpty,
                                        "⏎ „\(Rueckmeldungslistenbogen.sichernTitel)“: Der Bogen geht, das Sichern-Fenster "
                                        + "hängt am Blatt — „\(panel.nameFieldStringValue)“"
                                        + (abweichend.isEmpty ? "" : " (\(abweichend.joined(separator: "; ")))"))
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
                            // Zwei Ursachen, je beim Namen (Z-AW10N-07). Ob ⎋ die Lücke traf, ist nur Auskunft: Die Lücke
                            // selbst belegt Teil C2 mit dem Prüfweg (Z-AW10N-06, E784); Teil C bleibt der Wächter der Hand.
                            var ursachen: [String] = []
                            if !angekommenC { ursachen.append("⏎ kam nicht an") }
                            if verwaist { ursachen.append("ein Sichern-Fenster hängt am Blatt, dessen Dialog zu ist") }
                            pruefen(ursachen.isEmpty,
                                    "⏎ „\(Rueckmeldungslistenbogen.sichernTitel)“ und sofort ⎋: kein Sichern-Fenster an einem Blatt, "
                                    + "dessen Dialog zu ist (B-AW5-01) — Blatt \(blattC.isVisible ? "steht" : "fort"), Sichern-Fenster "
                                    + "\(fensterAmBlatt ? "am Blatt" : "keins"), Dialog \(speicher.offenerDialog.map { "\($0)" } ?? "—"), "
                                    + "⎋ in der Lücke \(inDerLuecke ? "ja" : "nein")"
                                    + (ursachen.isEmpty ? "" : " (\(ursachen.joined(separator: "; ")))"))
                            (blattC.attachedSheet as? NSSavePanel)?.cancel(nil)
                            for _ in 0..<12 where blattC.attachedSheet != nil { await warten(250) }
                            if blattC.isVisible, speicher.offenerDialog != .lernende { hauptfenster()?.endSheet(blattC) }
                            for _ in 0..<12 where blattC.isVisible && speicher.offenerDialog != .lernende { await warten(250) }
                        } else {
                            pruefen(false, "Bogen „Rückmeldungsliste“ für Teil C — \(lage())")
                        }
                        await schliessenUndMerken("nach Teil C")
                        // Teil C2 (G2-01, E784): das Blatt genau in der Lücke geschlossen — der Bogen ist fort, das
                        // Sichern-Fenster hängt noch nicht. Ein Prüfweg in `Dialogort` schließt es dort mit ⎋, wie eine
                        // schnelle Hand. Danach darf nichts an ihm hängen, und ein Ton sagt es. `bisFort`: Der Prüfweg wartet,
                        // bis das Blatt unsichtbar ist (C2); sonst kehrt er zurück, sobald das Modell es geschlossen hat — das
                        // schließende, womöglich noch sichtbare Blatt (C2b, Z-AX0b-01).
                        @MainActor func inDerLueckeSchliessen(_ teil: String, bisFort: Bool) async {
                            guard case let (blattD, bogenD)? = await listenbogenOeffnen(Rueckmeldungsbogenvorgabe(
                                auswahl: [mitteilung.id], kennwort: kennwort, wiederholung: kennwort)) else {
                                pruefen(false, "Bogen „Rückmeldungsliste“ für Teil \(teil) — \(lage())")
                                return
                            }
                            let luecke = Lueckenvermerk()
                            Dialogort.inDerLuecke = { blatt in
                                Dialogort.inDerLuecke = nil
                                luecke.gelaufen = true
                                taste("\u{1B}", code: 53, in: blatt)
                                // Bis das Blatt fort ist bzw. das Modell es geschlossen hat (Eintreten, mit Obergrenze).
                                if bisFort {
                                    for _ in 0..<12 where blatt.isVisible { await warten(250) }
                                } else {
                                    for _ in 0..<60 where speicher.offenerDialog == .lernende { await warten(50) }
                                }
                                luecke.blattFort = bisFort ? !blatt.isVisible : speicher.offenerDialog != .lernende
                                luecke.sichtbar = blatt.isVisible
                                luecke.amHauptfenster = blatt.sheetParent != nil
                            }
                            let toene = Dialogort.toene
                            @MainActor func sichernFenster() -> [NSWindow] { NSApp.windows.filter { $0 is NSSavePanel && $0.isVisible } }
                            /// Der Prüfweg lief, und `Dialogort` hat entschieden: ein Ton oder ein Sichern-Fenster.
                            @MainActor func entschieden() -> Bool { luecke.gelaufen && (Dialogort.toene != toene || !sichernFenster().isEmpty) }
                            let angekommenD = await eingabe(an: bogenD).oben
                            for _ in 0..<24 where angekommenD && !entschieden() { await warten(250) }
                            Dialogort.inDerLuecke = nil
                            // Bis das Blatt ganz fort ist oder ein Sichern-Fenster steht (Eintreten, mit Obergrenze).
                            for _ in 0..<12 where blattD.isVisible && sichernFenster().isEmpty { await warten(250) }
                            let haengend = sichernFenster()
                            var fehlt: [String] = []
                            if !angekommenD { fehlt.append("⏎ kam nicht an") }
                            if !luecke.gelaufen { fehlt.append("der Prüfweg lief nicht") }
                            if luecke.gelaufen && !luecke.blattFort { fehlt.append("das Blatt ging in der Lücke nicht") }
                            if !haengend.isEmpty {
                                fehlt.append("ein Sichern-Fenster steht"
                                             + (blattD.attachedSheet is NSSavePanel ? " am geschlossenen Blatt" : " frei"))
                            }
                            if Dialogort.toene != toene + 1 { fehlt.append("Töne \(Dialogort.toene - toene) statt 1") }
                            let beimEntscheiden = bisFort ? ""
                                : " — beim Entscheiden sichtbar \(luecke.sichtbar ? "ja" : "nein"), am Hauptfenster \(luecke.amHauptfenster ? "ja" : "nein")"
                            pruefen(fehlt.isEmpty, "Blatt in der Lücke \(bisFort ? "geschlossen" : "im Schließen"): kein Sichern-Fenster, "
                                    + "ein Ton (G2-01\(bisFort ? "" : ", Z-AX0b-01"))\(beimEntscheiden)"
                                    + (fehlt.isEmpty ? "" : " — \(fehlt.joined(separator: "; ")) — \(lage())"))
                            for fenster in haengend { (fenster as? NSSavePanel)?.cancel(nil) }
                            for _ in 0..<12 where !sichernFenster().isEmpty { await warten(250) }
                            if blattD.isVisible, speicher.offenerDialog != .lernende { hauptfenster()?.endSheet(blattD) }
                            for _ in 0..<12 where blattD.isVisible && speicher.offenerDialog != .lernende { await warten(250) }
                        }
                        await inDerLueckeSchliessen("C2", bisFort: true)
                        await schliessenUndMerken("nach Teil C2")
                        await inDerLueckeSchliessen("C2b", bisFort: false)
                        await schliessenUndMerken("nach Teil C2b")
                        // Teil E (G2-07, E776): ⌘Z, während der Bogen steht — erst gemessen, ob der Befehl ankommt. Ein
                        // Schritt im Verlauf des Blatts (nur der Stempel anders), dann ⌘Z an den Bogen: Bleibt der Schritt und
                        // kommt ein Ton, ist ⌘Z abgewiesen; geht der Schritt, nahm ⌘Z unter dem Bogen zurück.
                        if case let (_, bogenE)? = await listenbogenOeffnen(Rueckmeldungsbogenvorgabe()),
                           let stand = speicher.lernendenblattGriff?.ausgang() {
                            var frueher = stand
                            frueher.geaendert = "2000-01-01T00:00:00Z"
                            speicher.lernendenverlauf.anmelden(Schrittname.lerngruppeAnlegen, vorher: frueher, nachher: stand)
                            let schritte = speicher.lernendenverlauf.zurueck.count
                            let toene = speicher.systemtoene
                            // Nur die neue Sperre zählt — nicht ein Ton der Rückfragesperre (Z-AX0b-05).
                            let abgeprallt = speicher.gesperrteBefehle
                            bogenE.makeKeyAndOrderFront(nil)
                            for _ in 0..<12 where !bogenE.isKeyWindow { await warten(50) }
                            // Steht die Schreibmarke in einem Feld des Bogens, gehört ⌘Z dem Feld (E87) — gemessen wird ohne sie.
                            let imFeld = Schreibmarke.feldeditor != nil
                            bogenE.makeFirstResponder(nil)
                            taste("z", code: 6, [.command], in: bogenE)
                            for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count == schritte && speicher.systemtoene == toene {
                                await warten(250)
                            }
                            let genommen = speicher.lernendenverlauf.zurueck.count < schritte
                            let ton = speicher.systemtoene == toene + 1 && speicher.gesperrteBefehle == abgeprallt
                            pruefen(!genommen && ton, "⌘Z bei offenem Bogen: nichts zurückgenommen, ein Ton (G2-07, E776)"
                                    + (genommen ? " — der Schritt ging unter dem Bogen" : ton ? "" : " — ⌘Z kam nicht an (kein Ton)")
                                    + " — Schreibmarke vorher im Feld: \(imFeld ? "ja" : "nein")")
                            // E841: Bei offenem Bogen nennt das Menü keinen Schritt. Der Griff des Blatts ist der Beobachtung
                            // verborgen — die Titel kommen, sobald ein Menü aufgeht; die Probe meldet das Aufgehen selbst.
                            NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSApp.mainMenu)
                            let titelMenue = Menuetitel.eintrag(umschalt: false)?.title ?? "—"
                            // Paarweise wie bei AppKit: Kein Beobachter bleibt im Zustand „Menü offen“ (Z-GR3-02).
                            NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSApp.mainMenu)
                            pruefen(speicher.widerrufenTitel == "Widerrufen" && titelMenue == "Widerrufen",
                                    "Bei offenem Bogen nennt das Menü keinen Schritt (E841): „\(titelMenue)“ "
                                        + "(Aufgehen des Menüs von der Probe gemeldet)")
                            // Der Entwurf wie vorher: Ging der Schritt, kommt er wieder — erst ohne Bogen, sonst wiese die Sperre
                            // auch ⇧⌘Z ab (Z-AX0b-04); blieb er, ist der Entwurf ohnehin unverändert.
                            if genommen {
                                speicher.lernendenblattGriff?.bogenSchliessen()
                                for _ in 0..<12 where speicher.lernendenblattGriff?.bogenOffen() == true { await warten(250) }
                                speicher.wiederholen()
                            }
                        } else {
                            pruefen(false, "Bogen „Rückmeldungsliste“ für Teil E — \(lage())")
                        }
                        await schliessenUndMerken("nach Teil E")
                    } else {
                        pruefen(false, "Bogen „Rückmeldungsliste“ am Blatt „Lernende“ aus der Vorgabe — \(lage())")
                        await schliessenUndMerken("nach dem Fehlschlag")
                    }
                    pruefen(entwurfUnveraendert && speicher.lernende.bestand == vorListe,
                            "Öffnen, Bogen und Sichern-Fenster ändern weder Entwurf noch Jahresdatei")
                }
                }
                await schrittRueckmeldungsliste()

                @MainActor func schrittUnterblaetter() async {
                // ── ⌘L · Unterblätter (v96, BH5, E1169): Das Zahnrad der gewählten Lerngruppe — rechts in ihrer Zeile —
                // öffnet „Einstellungen der Lerngruppe“ am Blatt; „Bezeichnung“ mit ⏎ (= „Fertig“) benennt um, ein Schritt;
                // ⌘Z nimmt ihn zurück. Der Klick wie von Hand in die Zelle der Hülle. ──
                speicher.lernendenBlattOeffnen()
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil
                    || speicher.lernendenblattGriff?.gewaehlteGruppe() == nil { await warten(250) }
                guard let blatt = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende,
                      let gid = speicher.lernendenblattGriff?.gewaehlteGruppe() else {
                    pruefen(false, "Unterblätter: Blatt „Lernende“ mit gewählter Lerngruppe (E1169)")
                    _ = await blattSchliessen()
                    return
                }
                blatt.makeKeyAndOrderFront(nil)
                @MainActor func liste() -> NSTableView? {
                    suchen(blatt.contentView, NSTableView.self, { $0.tableColumns.first?.title == "Lerngruppe" })
                }
                for _ in 0..<20 where (liste()?.selectedRow ?? -1) < 0 { await warten(250) }
                guard let t = liste(), t.selectedRow >= 0 else {
                    pruefen(false, "Unterblätter: Gruppenliste mit gewählter Zeile (E1169)")
                    _ = await blattSchliessen()
                    return
                }
                let zelle = t.frameOfCell(atColumn: 0, row: t.selectedRow)
                let zeileVorKlick = t.selectedRow
                // Das Zahnrad steht rechts in der Zelle; die Stelle nacheinander 8, 14 und 20 pt vom Rand — mit Auskunft,
                // was getroffen wurde, wenn keine trägt.
                var getroffen: [String] = []
                var zahnradPunkt: NSPoint?
                for abstand in [8.0, 14.0, 20.0] where blatt.attachedSheet == nil {
                    let punkt = t.convert(NSPoint(x: zelle.maxX - abstand, y: zelle.midY), to: nil)
                    // `hitTest` nimmt den Punkt im Raum der übergeordneten Ansicht (R-BH5z-01).
                    let ziel = blatt.contentView?.hitTest(blatt.contentView?.superview?.convert(punkt, from: nil) ?? punkt)
                    getroffen.append("\(Int(abstand)) pt: " + (ziel.map { String(describing: type(of: $0)) } ?? "nichts"))
                    await klicken(punkt, in: blatt)
                    for _ in 0..<8 where blatt.attachedSheet == nil { await warten(250) }
                    if blatt.attachedSheet != nil { zahnradPunkt = punkt }
                }
                // Im gruppierten Formular steht „Bezeichnung“ als Beschriftung, nicht als Platzhalter — das Feld am Inhalt.
                let nameVorher = (speicher.lernendenblattGriff?.aenderungen() ?? speicher.lernendenblattGriff?.ausgang())
                    .flatMap { Lernendenverzeichnis($0).gruppe(gid)?.name }
                guard let unter = blatt.attachedSheet,
                      let feld = suchen(unter.contentView, NSTextField.self, { $0.isEditable && $0.stringValue == nameVorher }) else {
                    zeilen.append("  Auskunft: Zahnrad — Zeile \(t.selectedRow + 1) gewählt, Zelle \(Int(zelle.minX))…\(Int(zelle.maxX)) × "
                                  + "\(Int(zelle.minY))…\(Int(zelle.maxY)), getroffen: \(getroffen.joined(separator: "; "))")
                    pruefen(false, "Zahnrad der gewählten Lerngruppe öffnet „Einstellungen der Lerngruppe“ am Blatt (E1169)")
                    _ = await blattSchliessen()
                    return
                }
                pruefen(true, "Zahnrad der gewählten Lerngruppe öffnet „Einstellungen der Lerngruppe“ am Blatt (E1169)")
                // Scheiterkriterium: Der Klick aufs Zahnrad lässt die Auswahl, wie sie ist (v96, BH5, R-BH5-05).
                pruefen(t.selectedRow == zeileVorKlick && speicher.lernendenblattGriff?.gewaehlteGruppe() == gid,
                        "Zahnrad: die Auswahl der Gruppenliste bleibt (Zeile \(zeileVorKlick + 1) → \(t.selectedRow + 1)) (R-BH5-05)")
                let befundGruppe = await Lernendenprobe.unterblattBeimBeenden(speicher, unter, warten: warten)
                pruefen(befundGruppe == nil, "⌘Q bei offenem Unterblatt „Einstellungen der Lerngruppe“: die Frage auf ihm, "
                            + "„Weiter bearbeiten“ lässt es stehen (R-BH5-01)" + (befundGruppe.map { " — " + $0 } ?? ""))
                @MainActor func gruppenname() -> String? {
                    (speicher.lernendenblattGriff?.aenderungen() ?? speicher.lernendenblattGriff?.ausgang())
                        .flatMap { Lernendenverzeichnis($0).gruppe(gid)?.name }
                }
                let alterName = gruppenname() ?? feld.stringValue
                let vorher = speicher.lernendenverlauf.zurueck.count
                unter.makeKeyAndOrderFront(nil)
                unter.makeFirstResponder(feld)
                await warten(200)
                feld.currentEditor()?.selectAll(nil)
                tippen(alterName + " B\r", in: unter)
                for _ in 0..<20 where blatt.attachedSheet != nil
                    || speicher.lernendenverlauf.zurueck.count == vorher { await warten(250) }
                let umbenannt = gruppenname()
                pruefen(blatt.attachedSheet == nil && speicher.lernendenverlauf.zurueck.count == vorher + 1
                            && umbenannt == alterName + " B",
                        "„Bezeichnung“ mit ⏎ (= „Fertig“): „\(alterName)“ → „\(umbenannt ?? "—")“, ein Schritt "
                            + "(\(speicher.lernendenverlauf.zurueck.count - vorher)), das Unterblatt zu (E1169)")
                pruefen(t.selectedRow >= 0 && speicher.lernendenblattGriff?.gewaehlteGruppe() == gid,
                        "nach „Fertig“ bleibt die umbenannte Gruppe gewählt (R-BH5-05)")
                blatt.makeFirstResponder(nil)
                taste("z", code: 6, [.command], in: blatt)
                for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count > vorher { await warten(250) }
                pruefen(speicher.lernendenverlauf.zurueck.count == vorher && gruppenname() == alterName,
                        "⌘Z nimmt die Umbenennung zurück — „\(gruppenname() ?? "—")“ (E1169)")
                // „Verwerfen“ beim Beenden schließt die Bögen über `bogenSchliessen` — auch dieses Unterblatt, das Blatt bleibt
                // (R-BH8-W2-03, R-BH5-01).
                if let zahnradPunkt {
                    blatt.makeKeyAndOrderFront(nil)
                    await klicken(zahnradPunkt, in: blatt)
                    for _ in 0..<12 where blatt.attachedSheet == nil { await warten(250) }
                    let unterG = blatt.attachedSheet
                    speicher.lernendenblattGriff?.bogenSchliessen()
                    for _ in 0..<20 where blatt.attachedSheet != nil { await warten(250) }
                    pruefen(unterG != nil && blatt.attachedSheet == nil && hauptfenster()?.attachedSheet === blatt
                                && speicher.lernendenblattGriff?.bogenOffen() == false,
                            "„Verwerfen“ beim Beenden (Bogen schließen) nimmt „Einstellungen der Lerngruppe“ fort, das Blatt bleibt "
                                + "(R-BH8-W2-03)" + (unterG == nil ? " — das Unterblatt ging nicht auf" : ""))
                }
                // R-BH5-04: „Zeilen wählen …“ im Unterblatt — es schließt, der Bogen „Zeilen wählen“ (520 breit, das Unterblatt 460)
                // öffnet am Blatt. Das Unterblatt wie von Hand übers Zahnrad; sein Knopf ist kein `NSButton` — die Handlung über
                // den Griff, als wäre er geklickt (`handlungImUnterblatt`), erst wenn das Unterblatt steht.
                @MainActor func bogenbreite() -> Int? { blatt.attachedSheet?.contentView.map { Int($0.frame.width.rounded()) } }
                var breiten: [Int] = []
                if let zahnradPunkt {
                    blatt.makeKeyAndOrderFront(nil)
                    await klicken(zahnradPunkt, in: blatt)
                    for _ in 0..<12 where blatt.attachedSheet == nil { await warten(250) }
                    if let b = bogenbreite() { breiten.append(b) }
                    let angenommen = blatt.attachedSheet != nil
                        && speicher.lernendenblattGriff?.handlungImUnterblatt(.zeilenWaehlen) == true
                    for _ in 0..<40 where angenommen && bogenbreite() != 520 {
                        if let b = bogenbreite(), breiten.last != b { breiten.append(b) }
                        if bogenbreite() == nil, breiten.last != 0 { breiten.append(0) }
                        await warten(250)
                    }
                    if let b = bogenbreite(), breiten.last != b { breiten.append(b) }
                }
                pruefen(breiten.first == 460 && breiten.last == 520 && speicher.lernendenblattGriff?.bogenOffen() == true,
                        "„Zeilen wählen …“ im Unterblatt: es schließt, der Bogen „Zeilen wählen“ steht am Blatt — Breiten "
                            + "\(breiten.map(String.init).joined(separator: " → ")) (R-BH5-04)")
                if !(await blattSchliessen()) { zeilen.append("  Blatt nach den Unterblättern nicht geschlossen") }
                // Das Zahnrad der Mitteilung per Klick (v96, BH5z, E1221, E1222): Der Griff meldet, wo SwiftUI es neben der
                // Auswahl gezeichnet hat (`.global`, oben links in der Wurzel des Blatts); die Probe klickt dort wie von Hand.
                // Erwartet: das Unterblatt „Einstellungen der Mitteilung“ mit dem Titel der gewählten Mitteilung.
                if let mitteilung, let gruppeDerMitteilung {
                    speicher.lernendenBlattOeffnen(gruppe: gruppeDerMitteilung.id)
                    speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                    speicher.lernendenVorgabe?.anliegen = mitteilung.id
                    for _ in 0..<40 where hauptfenster()?.attachedSheet == nil
                        || speicher.lernendenblattGriff?.zahnradDerMitteilung() == nil { await warten(250) }
                    if let blattZ = hauptfenster()?.attachedSheet, let inhalt = blattZ.contentView,
                       speicher.lernendenblattGriff?.zahnradDerMitteilung() != nil {
                        blattZ.makeKeyAndOrderFront(nil)
                        for _ in 0..<12 where !blattZ.isKeyWindow { await warten(50) }
                        // `.global` ist der Raum der Wurzel von SwiftUI — die erste Hosting-Ansicht ab dem Inhalt (R-BH5z-02), aber
                        // nur, wenn sie den Inhalt deckt; sonst wäre es die einer Zelle (R-BH5z-06), und es gilt der Inhalt.
                        @MainActor func wurzel(_ ansicht: NSView) -> NSView? {
                            if String(describing: type(of: ansicht)).contains("HostingView") { return ansicht }
                            for kind in ansicht.subviews { if let gefunden = wurzel(kind) { return gefunden } }
                            return nil
                        }
                        let raum: NSView = wurzel(inhalt).flatMap { kandidat in
                            let r = kandidat.convert(kandidat.bounds, to: nil)
                            return abs(r.width - inhalt.bounds.width) <= 1 && abs(r.height - inhalt.bounds.height) <= 1 ? kandidat : nil
                        } ?? inhalt
                        // Die Lage frisch nach dem Vorholen — geklickt wird nur, wenn sie wie ein Zahnrad aussieht (R-BH5z-03).
                        let rahmen = speicher.lernendenblattGriff?.zahnradDerMitteilung() ?? .zero
                        let innen = NSPoint(x: rahmen.midX, y: raum.isFlipped ? rahmen.midY : raum.bounds.height - rahmen.midY)
                        let punkt = raum.convert(innen, to: nil)
                        // `hitTest` nimmt den Punkt im Raum der übergeordneten Ansicht (R-BH5z-01).
                        let ziel = inhalt.hitTest(inhalt.superview?.convert(punkt, from: nil) ?? punkt)
                            .map { String(describing: type(of: $0)) } ?? "nichts"
                        let raumImFenster = raum.convert(raum.bounds, to: nil)
                        zeilen.append("  Auskunft: Zahnrad der Mitteilung \(Int(rahmen.minX))…\(Int(rahmen.maxX)) × "
                                      + "\(Int(rahmen.minY))…\(Int(rahmen.maxY)) in \(String(describing: type(of: raum))) (gespiegelt "
                                      + "\(raum.isFlipped ? "ja" : "nein"), im Fenster ab \(Int(raumImFenster.minX)), \(Int(raumImFenster.minY)), "
                                      + "\(Int(raumImFenster.width)) × \(Int(raumImFenster.height)); Inhalt \(Int(inhalt.bounds.width)) × "
                                      + "\(Int(inhalt.bounds.height))), Klick bei \(Int(punkt.x)), \(Int(punkt.y)) — getroffen: \(ziel)")
                        let plausibel = (8...40).contains(rahmen.width) && (8...40).contains(rahmen.height)
                            && raum.bounds.contains(innen)
                        if plausibel {
                            await klicken(punkt, in: blattZ)
                            for _ in 0..<12 where blattZ.attachedSheet == nil { await warten(250) }
                        }
                        let titelZ = blattZ.attachedSheet.flatMap { unter in
                            suchen(unter.contentView, NSTextField.self, { $0.isEditable && $0.stringValue == mitteilung.titel })
                        }
                        if titelZ == nil {
                            let danach = speicher.lernendenblattGriff?.zahnradDerMitteilung()
                            zeilen.append("  Auskunft: " + (plausibel ? "nach dem Klick" : "ohne Klick") + " Lage "
                                          + (danach.map { "\(Int($0.minX)), \(Int($0.minY))" } ?? "keine (Teil gewechselt?)")
                                          + ", Unterblatt " + (blattZ.attachedSheet.map { "„\($0.title)“" } ?? "keines"))
                        }
                        pruefen(titelZ != nil, "Klick aufs Zahnrad der Mitteilung öffnet „Einstellungen der Mitteilung“ mit "
                                    + "„\(mitteilung.titel)“ (E1221)"
                                    + (!plausibel ? " — Lage unplausibel, nicht geklickt"
                                        : blattZ.attachedSheet == nil ? " — kein Unterblatt" : ""))
                        // „Verwerfen“ beim Beenden über `bogenSchliessen` auch an diesem Unterblatt (R-BH8-W2-03, R-BH5-02).
                        if titelZ != nil {
                            speicher.lernendenblattGriff?.bogenSchliessen()
                            for _ in 0..<20 where blattZ.attachedSheet != nil { await warten(250) }
                            pruefen(blattZ.attachedSheet == nil && hauptfenster()?.attachedSheet === blattZ
                                        && speicher.lernendenblattGriff?.bogenOffen() == false,
                                    "„Verwerfen“ beim Beenden (Bogen schließen) nimmt „Einstellungen der Mitteilung“ fort, das Blatt "
                                        + "bleibt (R-BH8-W2-03)")
                        }
                    } else {
                        pruefen(false, "Zahnrad der Mitteilung: keine Lage gemeldet — Blatt "
                                    + "\(hauptfenster()?.attachedSheet != nil ? "da" : "fehlt") (E1222)")
                    }
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Zahnrad der Mitteilung nicht geschlossen") }
                }
                // „Einstellungen der Mitteilung“ (E1175): Tag und Titel geändert, „Fertig“ (⏎) — ein Schritt, ⌘Z zurück. Über die
                // Vorgabe; Frist und „Auch an …“ sind SwiftUI-Kästchen und -Menü und für die Probe nicht greifbar.
                if let mitteilung, let gruppeDerMitteilung {
                    speicher.lernendenBlattOeffnen(gruppe: gruppeDerMitteilung.id)
                    speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                    speicher.lernendenVorgabe?.anliegen = mitteilung.id
                    speicher.lernendenVorgabe?.mitteilungseinstellungen = true
                    for _ in 0..<40 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                    let alterTag = Tag(iso: mitteilung.datum) ?? .heute
                    if let blattM = hauptfenster()?.attachedSheet, let unterM = blattM.attachedSheet,
                       let titelfeld = suchen(unterM.contentView, NSTextField.self, {
                           $0.isEditable && $0.stringValue == mitteilung.titel }),
                       let tagfeld = suchen(unterM.contentView, NSTextField.self, {
                           $0.isEditable && $0.stringValue == alterTag.deutsch }) {
                        let befundM = await Lernendenprobe.unterblattBeimBeenden(speicher, unterM, warten: warten)
                        pruefen(befundM == nil, "⌘Q bei offenem Unterblatt „Einstellungen der Mitteilung“: die Frage auf ihm, "
                                    + "„Weiter bearbeiten“ lässt es stehen (R-BH5-02)" + (befundM.map { " — " + $0 } ?? ""))
                        let vorherM = speicher.lernendenverlauf.zurueck.count
                        let neuerTag = alterTag.plus(tage: -1)
                        unterM.makeKeyAndOrderFront(nil)
                        unterM.makeFirstResponder(titelfeld)
                        await warten(200)
                        titelfeld.currentEditor()?.selectAll(nil)
                        // Die Tasten kommen über die Schlange — erst weiter, wenn das Feld sie zeigt, sonst landeten sie im
                        // nächsten Feld.
                        let neuerTitel = mitteilung.titel + " geändert"
                        tippen(neuerTitel, in: unterM)
                        for _ in 0..<20 where (titelfeld.currentEditor() as? NSTextView)?.string != neuerTitel { await warten(50) }
                        unterM.makeFirstResponder(tagfeld)
                        await warten(200)
                        tagfeld.currentEditor()?.selectAll(nil)
                        tippen(neuerTag.deutsch, in: unterM)
                        for _ in 0..<20 where (tagfeld.currentEditor() as? NSTextView)?.string != neuerTag.deutsch { await warten(50) }
                        // Das Datumsfeld übernimmt beim Verlassen — erst danach „Fertig“ (⏎), wie von Hand. Eine Uhr: Das Übernehmen
                        // beim Verlassen zeigt sich an keinem Feld, auf das sich warten ließe (R-BH8-W2-06).
                        unterM.makeFirstResponder(titelfeld)
                        await warten(500)
                        tippen("\r", in: unterM)
                        for _ in 0..<20 where blattM.attachedSheet != nil
                            || speicher.lernendenverlauf.zurueck.count == vorherM { await warten(250) }
                        let jetzt = speicher.lernendenblattGriff?.aenderungen()?.anliegen.first { $0.id == mitteilung.id }
                        pruefen(blattM.attachedSheet == nil && speicher.lernendenverlauf.zurueck.count == vorherM + 1
                                    && jetzt?.titel == mitteilung.titel + " geändert" && jetzt?.datum == neuerTag.iso,
                                "„Einstellungen der Mitteilung“: Tag \(jetzt?.datum ?? "—") und Titel „\(jetzt?.titel ?? "—")“ mit "
                                    + "„Fertig“ (⏎) — \(speicher.lernendenverlauf.zurueck.count - vorherM) Schritt (E1175)")
                        blattM.makeFirstResponder(nil)
                        taste("z", code: 6, [.command], in: blattM)
                        for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count > vorherM { await warten(250) }
                        let zurueckM = (speicher.lernendenblattGriff?.aenderungen() ?? speicher.lernendenblattGriff?.ausgang())?
                            .anliegen.first { $0.id == mitteilung.id }
                        pruefen(speicher.lernendenverlauf.zurueck.count == vorherM && zurueckM?.titel == mitteilung.titel
                                    && zurueckM?.datum == mitteilung.datum,
                                "⌘Z nimmt Tag und Titel zusammen zurück (E1175)")
                    } else {
                        pruefen(false, "„Einstellungen der Mitteilung“ mit Titel und Tag am Blatt (E1175)")
                    }
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach „Einstellungen der Mitteilung“ nicht geschlossen") }
                    // R-BH5-07 nachgestellt, R-BH5N-01: Tag getippt, dann „Fertig“ — mit der Maus, gehalten wie von Hand und kurz wie
                    // ein Tippen auf dem Trackpad, und mit ⏎ im Tagfeld selbst; nie ein Fokuswechsel davor. Der Klick daneben löst die
                    // Schreibmarke (`Schreibende`), ⏎ übernimmt im Feld (`onSubmit`). Je Weg gilt der getippte Tag, in einem Schritt;
                    // schließt ⏎ das Unterblatt nicht, folgt der Klick auf „Fertig“ — verloren gehen darf nichts. „Fertig“ ist ein
                    // SwiftUI-Knopf, für die Probe unsichtbar: der Punkt 40 pt vor dem rechten Rand, 28 pt über dem unteren — im Fuß
                    // (20 pt Rand, 16 pt unten) auf dem rechten Knopf.
                    let tagVorher = Tag(iso: mitteilung.datum) ?? .heute
                    for (weg, versatz) in [("Klick", -2), ("kurzer Klick", -3), ("⏎ im Tagfeld", -4)] {
                        speicher.lernendenBlattOeffnen(gruppe: gruppeDerMitteilung.id)
                        speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                        speicher.lernendenVorgabe?.anliegen = mitteilung.id
                        speicher.lernendenVorgabe?.mitteilungseinstellungen = true
                        for _ in 0..<40 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                        if let blattK = hauptfenster()?.attachedSheet, let unterK = blattK.attachedSheet, let inhaltK = unterK.contentView,
                           let tagfeldK = suchen(inhaltK, NSTextField.self, { $0.isEditable && $0.stringValue == tagVorher.deutsch }) {
                            let getippt = tagVorher.plus(tage: versatz)
                            let fertigPunkt = NSPoint(x: inhaltK.frame.width - 40, y: 28)
                            unterK.makeKeyAndOrderFront(nil)
                            unterK.makeFirstResponder(tagfeldK)
                            await warten(200)
                            tagfeldK.currentEditor()?.selectAll(nil)
                            tippen(getippt.deutsch, in: unterK)
                            for _ in 0..<20 where (tagfeldK.currentEditor() as? NSTextView)?.string != getippt.deutsch { await warten(50) }
                            let vorherK = speicher.lernendenverlauf.zurueck.count
                            var nurUebernommen = false
                            switch weg {
                            case "⏎ im Tagfeld":
                                tippen("\r", in: unterK)
                                for _ in 0..<8 where blattK.attachedSheet != nil { await warten(250) }
                                if blattK.attachedSheet != nil {
                                    nurUebernommen = true
                                    await klicken(fertigPunkt, in: unterK)
                                }
                            case "kurzer Klick":
                                await klicken(fertigPunkt, in: unterK, halten: 10)
                            default:
                                await klicken(fertigPunkt, in: unterK)
                            }
                            for _ in 0..<20 where blattK.attachedSheet != nil
                                || speicher.lernendenverlauf.zurueck.count == vorherK { await warten(250) }
                            let datumK = speicher.lernendenblattGriff?.aenderungen()?.anliegen.first { $0.id == mitteilung.id }?.datum
                            let schritteK = speicher.lernendenverlauf.zurueck.count - vorherK
                            if blattK.attachedSheet != nil {
                                zeilen.append("  Auskunft: der Klick 40 pt vor dem rechten, 28 pt über dem unteren Rand traf „Fertig“ "
                                              + "nicht (Unterblatt \(Int(inhaltK.frame.width)) × \(Int(inhaltK.frame.height)))")
                            }
                            if nurUebernommen {
                                zeilen.append("  Auskunft: ⏎ im Tagfeld übernahm den Tag, ohne „Fertig“ auszulösen — danach der Klick")
                            }
                            pruefen(blattK.attachedSheet == nil && datumK == getippt.iso && schritteK == 1,
                                    "getippter Tag, dann „Fertig“ (\(weg), ohne Fokuswechsel): gilt — getippt \(getippt.iso), in der "
                                        + "Mitteilung \(datumK ?? "—"), \(schritteK) Schritt (R-BH5-07, R-BH5N-01)")
                        } else {
                            pruefen(false, "„Einstellungen der Mitteilung“ mit dem Tag am Blatt (\(weg), R-BH5N-01)")
                        }
                        if !(await blattSchliessen()) { zeilen.append("  Blatt nach „Fertig“ (\(weg)) nicht geschlossen") }
                    }
                    // R-BH5-03/04: „Einzelne …“ auf „Neue Mitteilung“ — Blatt → Unterblatt → Bogen; ⌘Q fragt auf dem Bogen (R-BH5-02).
                    let drei = Array((speicher.lernende.verzeichnis?.mitglieder(gruppeDerMitteilung.id) ?? []).prefix(3).map(\.id))
                    speicher.lernendenBlattOeffnen(gruppe: gruppeDerMitteilung.id)
                    speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                    speicher.lernendenVorgabe?.adressaten = drei
                    for _ in 0..<40 where hauptfenster()?.attachedSheet?.attachedSheet?.attachedSheet == nil { await warten(250) }
                    if !drei.isEmpty, let bogenE = hauptfenster()?.attachedSheet?.attachedSheet?.attachedSheet {
                        // Der Bogen selbst, kein Alert: 520 breit wie „Einzelne …“, das Unterblatt darunter 460 (R-BH5N-07).
                        let breiteE = Int((bogenE.contentView?.frame.width ?? 0).rounded())
                        pruefen(!Planungsspeicher.istAlert(bogenE) && breiteE == 520,
                                "„Einzelne …“ liegt auf dem Unterblatt „Neue Mitteilung“ — Blatt → Unterblatt → Bogen, \(breiteE) breit "
                                    + "(R-BH5-04)")
                        let befundE = await Lernendenprobe.unterblattBeimBeenden(speicher, bogenE, warten: warten)
                        pruefen(befundE == nil, "⌘Q bei offenem „Einzelne …“ auf dem Unterblatt: die Frage auf dem Bogen, "
                                    + "„Weiter bearbeiten“ lässt ihn stehen (R-BH5-02)" + (befundE.map { " — " + $0 } ?? ""))
                        // „Verwerfen“ beim Beenden schließt den Bogen über `bogenSchliessen` — hier ohne das Beenden selbst: Unterblatt
                        // und „Einzelne …“ gehen zusammen, das Blatt bleibt (R-BH5N-08).
                        if let blattE = hauptfenster()?.attachedSheet {
                            speicher.lernendenblattGriff?.bogenSchliessen()
                            for _ in 0..<20 where blattE.attachedSheet != nil { await warten(250) }
                            pruefen(blattE.attachedSheet == nil && bogenE.isVisible == false && hauptfenster()?.attachedSheet === blattE
                                        && speicher.lernendenblattGriff?.bogenOffen() == false,
                                    "„Verwerfen“ beim Beenden (Bogen schließen) nimmt Unterblatt und „Einzelne …“ zusammen fort, das Blatt "
                                        + "bleibt (R-BH5N-08)")
                        }
                    } else {
                        pruefen(false, "„Einzelne …“ auf dem Unterblatt aus der Vorgabe (\(drei.count) Mitglieder, R-BH5-04)")
                    }
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach „Einzelne …“ nicht geschlossen") }
                    // „Einzelne …“ wie von Hand (R-BH8N-01, E1204): erst „Neue Mitteilung“, dann, wenn es steht, der Bogen über den
                    // Griff wie die Wahl im Menü — er steht voll, 600 hoch. (Über die Vorgabe `adressaten` oben öffnet er beim
                    // Erscheinen des Unterblatts und steht gestaucht.)
                    speicher.lernendenBlattOeffnen(gruppe: gruppeDerMitteilung.id)
                    speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                    speicher.lernendenVorgabe?.neueMitteilung = true
                    for _ in 0..<40 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                    if let unterH = hauptfenster()?.attachedSheet?.attachedSheet {
                        // Bis die Höhe zweimal gleich gelesen ist — eine Uhr: höchstens 2 s, je 100 ms (R-BH8N-07).
                        var vorige: CGFloat = -1
                        for _ in 0..<20 where unterH.frame.height != vorige { vorige = unterH.frame.height; await warten(100) }
                        let angenommen = speicher.lernendenblattGriff?.einzelneImUnterblatt() == true
                        for _ in 0..<20 where unterH.attachedSheet == nil { await warten(250) }
                        if angenommen, let bogenH = unterH.attachedSheet {
                            vorige = -1
                            for _ in 0..<20 where bogenH.frame.height != vorige { vorige = bogenH.frame.height; await warten(100) }
                            // Das Soll nach der Höhe des Blatts — am großen Bildschirm 600, in einer niedrigeren VM weniger
                            // (R-BH8N-10).
                            let hoehe = Int(bogenH.frame.height.rounded())
                            let soll = Int(AdressatenBogen.hoehe(blatt: hauptfenster()?.attachedSheet?.frame.height
                                                                     ?? LernendenDialog.blatthoehe).rounded())
                            pruefen(abs(hoehe - soll) <= 1,
                                    "„Einzelne …“ von Hand auf „Neue Mitteilung“ steht ungestaucht: \(hoehe) hoch (soll \(soll); "
                                        + "„Neue Mitteilung“ \(Int(unterH.frame.height.rounded())); E1204, R-BH8N-01)")
                        } else {
                            pruefen(false, "„Einzelne …“ ging auf dem stehenden Unterblatt nicht auf (R-BH8N-01)")
                        }
                    } else {
                        pruefen(false, "„Neue Mitteilung“ ging aus der Vorgabe nicht auf (R-BH8N-01)")
                    }
                    if !(await blattSchliessen()) { zeilen.append("  Blatt nach „Einzelne …“ von Hand nicht geschlossen") }
                }
                }
                await schrittUnterblaetter()

                @MainActor func schrittArchiv() async -> Bool {
                // ── Archiv (AP9): das Vorjahr lesen, eine Person in allen Schuljahren löschen ──
                // Saat für AX7b (v86; E760, E799): die ersten beiden Lerngruppen der Listen archiviert — die erste heute, die
                // zweite vor drei Tagen. Ein Kopfklick auf „Archiviert“ stellt dann die zweite nach oben. Nach dem Blatt geht
                // der Stand zurück.
                vorSaatAX7b = speicher.lernende.bestand
                if let bestand = vorSaatAX7b {
                    let zwei = Array(Lernendenverzeichnis(bestand).gruppen().prefix(2).map(\.id))
                    if zwei.count == 2 {
                        // In der Form von `jetztAlsZeitstempel` (ISO 8601, Bruchteile, UTC).
                        let form = ISO8601DateFormatter()
                        form.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        form.timeZone = TimeZone(secondsFromGMT: 0)
                        let heute = Zeitrechnung.jetztAlsZeitstempel()
                        let frueher = form.string(from: Pruefuhr.jetzt.addingTimeInterval(-3 * 86_400))
                        _ = speicher.lernendenUebernehmen(bestand.mitArchivierterGruppe(zwei[0], jetzt: heute)
                            .mitArchivierterGruppe(zwei[1], jetzt: frueher))
                        if speicher.lernende.bestand?.lerngruppen.filter({ !$0.archiviert.isEmpty }).map(\.id).sorted() == zwei.sorted() {
                            saatAX7b = zwei
                        }
                    }
                }
                pruefen(saatAX7b.count == 2, "Saat AX7b: zwei Lerngruppen im laufenden Schuljahr archiviert")
                taste("l", code: 37, [.command], in: hauptfenster())
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                blatt3 = hauptfenster()?.attachedSheet
                guard blatt3 != nil, speicher.offenerDialog == .lernende else {
                    pruefen(false, "⌘L öffnet das Blatt ein drittes Mal")
                    await ende()
                    return false
                }
                blatt3.makeKeyAndOrderFront(nil)
                for _ in 0..<40 where suchen(blatt3.contentView, NSSegmentedControl.self, {
                    $0.segmentCount == 3 && $0.label(forSegment: 2) == "Archiv" }) == nil { await warten(250) }
                guard let oben = suchen(blatt3.contentView, NSSegmentedControl.self, {
                    $0.segmentCount == 3 && $0.label(forSegment: 2) == "Archiv" }), waehlen(oben, "Archiv") else {
                    pruefen(false, "Umschalter „Lerngruppen / Alle Lernenden / Archiv“ gefunden und bedient")
                    await ende()
                    return false
                }
                rahmenOben = oben.convert(oben.bounds, to: nil)
                // Der Eintrag des laufenden Schuljahrs (E643, E788): oben und beim Öffnen gewählt — an der NSPopUpButton
                // (macOS 26) oder wie von Hand an ihrem Menü (macOS 27). Danach wird das Vorjahr gewählt, und es geht wie
                // bisher weiter.
                laufend = speicher.lernende.bestand.map {
                    LaufendesSchuljahr.titel(LaufendesSchuljahr.schuljahr($0, planung: speicher.planung))
                } ?? "—"
                for _ in 0..<40 where wahlVorher == nil {
                    wahlVorher = suchen(blatt3.contentView, NSPopUpButton.self, { $0.itemTitles.contains("2025/26") })
                    if wahlVorher == nil, suchen(blatt3.contentView, NSTableView.self, { $0.tableColumns.first?.title == "Nachname" }) != nil {
                        break
                    }
                    await warten(250)
                }
                return true
                }
                guard await schrittArchiv() else { return }
                // Das Blatt „Archiv“ aus AP9 (`blatt3`) steht noch: Dieser Schritt trägt auch den Rest von AP9 — das Vorjahr
                // lesen, eine Person in allen Schuljahren löschen, ⎋, die Saat zurück (Z-BA0a-02).
                @MainActor func schrittLaufendesSchuljahr() async {
                // ── AX7b (v86; AX1, R2-A2; E760, E799): im Eintrag des laufenden Schuljahrs der Teil „Lerngruppen“ — Spalten,
                // Kopfklick „Archiviert“, „Zurückholen“ mit Schritt und ⌘Z. Geklickt wird wie von Hand in Kopf und Zelle; den
                // Knopf selbst sucht die Probe nicht (B83). Danach zurück auf „Personen“: Der gewählte Teil gälte sonst auch im
                // Vorjahr, und das Folgende liest dort die Personen.
                if saatAX7b.count == 2 {
                    @MainActor func klick(_ punkt: NSPoint) {
                        for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                            if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                                 windowNumber: blatt3.windowNumber, context: nil, eventNumber: 0,
                                                                 clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                                NSApp.postEvent(ereignis, atStart: false)
                            }
                        }
                    }
                    /// Der Stand der beiden Lerngruppen im Entwurf: `true` = archiviert (ohne Änderung gilt der Ausgang).
                    @MainActor func archiviert() -> [Bool] {
                        let entwurf = speicher.lernendenblattGriff?.aenderungen() ?? speicher.lernendenblattGriff?.ausgang()
                        return saatAX7b.map { id in entwurf?.lerngruppen.first { $0.id == id }.map { !$0.archiviert.isEmpty } ?? false }
                    }
                    var teile: NSSegmentedControl?
                    for _ in 0..<20 where teile == nil {
                        teile = suchen(blatt3.contentView, NSSegmentedControl.self, {
                            $0.segmentCount == 2 && $0.label(forSegment: 0) == "Personen" && $0.label(forSegment: 1) == "Lerngruppen" })
                        if teile == nil { await warten(250) }
                    }
                    if let teile, waehlen(teile, "Lerngruppen") {
                        var gruppentabelle: NSTableView?
                        for _ in 0..<20 where gruppentabelle == nil {
                            gruppentabelle = suchen(blatt3.contentView, NSTableView.self, {
                                $0.tableColumns.first?.title == "Lerngruppe" && $0.numberOfRows == 2 })
                            if gruppentabelle == nil { await warten(250) }
                        }
                        if let tabelle = gruppentabelle {
                            let spalten = tabelle.tableColumns.map(\.title)
                            pruefen(spalten == ["Lerngruppe", "Mitglieder", "Archiviert", ""],
                                    "Archiv, laufendes Schuljahr, Teil „Lerngruppen“: Spalten \(spalten), zwei Zeilen (E760, E799)")
                            // Kopfklick „Archiviert“: aufsteigend nach dem Tag — die vor drei Tagen archivierte zuerst.
                            let ordnungVorher = tabelle.sortDescriptors
                            if let kopf = tabelle.headerView, let stelle = spalten.firstIndex(of: "Archiviert") {
                                let r = kopf.headerRect(ofColumn: stelle)
                                klick(kopf.convert(NSPoint(x: r.midX, y: r.midY), to: nil))
                                for _ in 0..<12 where tabelle.sortDescriptors == ordnungVorher { await warten(250) }
                            }
                            let ordnungNach = tabelle.sortDescriptors.map { "\($0.key ?? "—") \($0.ascending ? "↑" : "↓")" }
                            // „Zurückholen“ in der obersten Zeile: ein Klick in die Spalte des Knopfs, nahe ihrer linken Kante.
                            let schritte = speicher.lernendenverlauf.zurueck.count
                            let zelle = tabelle.frameOfCell(atColumn: 3, row: 0)
                            let punkt = tabelle.convert(NSPoint(x: zelle.minX + 30, y: zelle.midY), to: nil)
                            let getroffen = blatt3.contentView?.superview?.hitTest(punkt)?.isDescendant(of: tabelle) == true
                            klick(punkt)
                            for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count == schritte { await warten(250) }
                            for _ in 0..<12 where tabelle.numberOfRows == 2 { await warten(250) }
                            let nachKlick = archiviert()
                            pruefen(getroffen && speicher.lernendenverlauf.zurueck.count == schritte + 1
                                        && speicher.lernendenverlauf.naechsterName == Schrittname.lerngruppeZurueckholen
                                        && nachKlick == [true, false] && tabelle.numberOfRows == 1,
                                    "Kopfklick „Archiviert“ (\(ordnungNach)), dann „Zurückholen“ in der obersten Zeile: die früher "
                                        + "archivierte Lerngruppe kommt zurück, ein Schritt „Lerngruppe zurückholen“, eine Zeile bleibt "
                                        + "— archiviert \(nachKlick), \(tabelle.numberOfRows) Zeilen, Klickpunkt in der Tabelle: "
                                        + (getroffen ? "ja" : "nein"))
                            // ⌘Z am Blatt, ohne Schreibmarke in einem Feld: Die Zeile ist wieder da, der Entwurf wie beim Öffnen.
                            if speicher.lernendenverlauf.zurueck.count == schritte + 1 {
                                blatt3.makeKeyAndOrderFront(nil)
                                blatt3.makeFirstResponder(nil)
                                taste("z", code: 6, [.command], in: blatt3)
                                for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count > schritte { await warten(250) }
                                for _ in 0..<12 where tabelle.numberOfRows == 1 { await warten(250) }
                                pruefen(speicher.lernendenverlauf.zurueck.count == schritte && archiviert() == [true, true]
                                            && tabelle.numberOfRows == 2 && speicher.lernendenblattGriff?.aenderungen() == nil,
                                        "⌘Z: Die Lerngruppe ist wieder archiviert, zwei Zeilen, der Entwurf wie beim Öffnen")
                            }
                        } else {
                            pruefen(false, "Archiv, laufendes Schuljahr, Teil „Lerngruppen“: Tabelle „Lerngruppe“ mit zwei Zeilen")
                        }
                        _ = waehlen(teile, "Personen")
                        for _ in 0..<12 where suchen(blatt3.contentView, NSTableView.self, {
                            $0.tableColumns.first?.title == "Lerngruppe" }) != nil { await warten(250) }
                    } else {
                        pruefen(false, "Archiv, laufendes Schuljahr: Umschalter „Personen / Lerngruppen“ (ohne „Anliegen“, E760)")
                    }
                }
                if let w = wahlVorher {
                    pruefen(w.itemTitles.first == laufend && w.titleOfSelectedItem == laufend && w.itemTitles.contains("2025/26"),
                            "Archiv: oben „\(laufend)“, beim Öffnen gewählt, darunter „2025/26“ (E643, E788) — "
                            + "\(w.itemTitles), gewählt \(w.titleOfSelectedItem ?? "—")")
                    // Gewählt wird über das Menü wie von Hand — `selectItem` an der NSPopUpButton änderte nur ihre
                    // Anzeige, nicht die Wahl dahinter (am Lauf gesehen, 23.10.2026).
                    _ = await menueDerWahl(waehlen: "2025/26")
                } else {
                    let vorher = await menueDerWahl(waehlen: "2025/26")
                    pruefen(vorher.map { $0.titel.first == laufend && $0.angehakt == [laufend] && $0.titel.contains("2025/26") } ?? false,
                            "Archiv: oben „\(laufend)“, beim Öffnen gewählt, darunter „2025/26“ (E643, E788) — wie von Hand: "
                            + (vorher.map { "\($0.titel), angehakt \($0.angehakt)" } ?? "kein Menü"))
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
                    // „In allen Schuljahren löschen …“ wie von Hand: Seit E835 gibt es kein ⌘⌫ mehr. Die Bedienungshilfe
                    // zeigt SwiftUIs Knöpfe im eigenen Prozess nicht (gemessen: zwei Elemente), und der Knopf wird nicht über
                    // AppKit gesucht (B83) — geklickt wird in seine Leiste unter der Tabelle (8 pt Abstand, 8 pt Polster),
                    // nahe ihrem rechten Rand, wo der Knopf steht. Die Leiste gibt es erst mit der Auswahl; bleibt die Frage
                    // aus, die nächste Höhe (Z14f-03).
                    var klickpunkt = "—"
                    var fremd: [String] = []
                    if let rahmen = tabelle.enclosingScrollView.map({ $0.convert($0.bounds, to: nil) }) {
                        for dy in [27.0, 22.0, 32.0, 17.0, 37.0] where speicher.rueckfrage == nil && fremd.isEmpty {
                            let punkt = NSPoint(x: rahmen.maxX - 48, y: rahmen.minY - dy)
                            klickpunkt = "−\(Int(dy)) pt unter der Tabelle"
                            for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                                if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                                                     windowNumber: blatt3.windowNumber, context: nil, eventNumber: 0,
                                                                     clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                                    NSApp.postEvent(ereignis, atStart: false)
                                }
                            }
                            for _ in 0..<8 where speicher.rueckfrage == nil { await warten(150) }
                            // Traf der Klick einen anderen Knopf der Leiste, kann ein Dateidialog stehen: gleich schließen,
                            // nennen und nicht weiterklicken (Z-GR3-04, Z-AX9N-07).
                            let dialoge = NSApp.windows.compactMap { $0 as? NSSavePanel }.filter(\.isVisible)
                            dialoge.forEach { $0.cancel(nil) }
                            fremd = dialoge.map { "\(type(of: $0))" }
                        }
                    }
                    // „ohne Rückfrage“ nur, wenn keine steht; ein geschlossener Dateidialog wird auch neben ihr genannt
                    // (Z-AX9M-04).
                    if speicher.rueckfrage == nil {
                        zeilen.append("      Klick ohne Rückfrage — gewählte Zeile \(tabelle.selectedRow)"
                                      + (fremd.isEmpty ? "" : ", geschlossen: \(fremd.joined(separator: ", "))"))
                    } else if !fremd.isEmpty {
                        zeilen.append("      Klick mit Rückfrage — geschlossen: \(fremd.joined(separator: ", "))")
                    }
                    let frage = speicher.rueckfrage
                    pruefen(frage?.ort == .lernende
                            && frage?.text.contains("„Bauer, Ben“ in allen archivierten Schuljahren") == true,
                            "Klick auf „In allen Schuljahren löschen …“ fragt am Blatt — mit Name und Zahlen (E276, E835; "
                                + "\(klickpunkt))")
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
                // Ein Dateidialog, der erst nach dem letzten Nachsehen aufging — nach der letzten Höhe oder hinter einer
                // Rückfrage, die das Warten sofort beendete —, bliebe sonst stehen: ohne Wartezeit noch einmal (Z-AX9M-04).
                let spaete = NSApp.windows.compactMap { $0 as? NSSavePanel }.filter(\.isVisible)
                spaete.forEach { $0.cancel(nil) }
                if !spaete.isEmpty {
                    zeilen.append("      Dateidialog vor ⎋ geschlossen: \(spaete.map { "\(type(of: $0))" }.joined(separator: ", "))")
                    // Tastenereignisse gehen ans Schlüsselfenster — das war eben der Dialog (Z-AX9T3-04).
                    blatt3.makeKeyAndOrderFront(nil)
                }
                taste("\u{1B}", code: 53, in: blatt3)
                for _ in 0..<20 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                pruefen(speicher.offenerDialog == nil, "Escape schließt das Blatt — die Löschung galt schon, ohne „Übernehmen“")
                // Die Saat von AX7b zurück: Die beiden Lerngruppen stehen wieder in den Listen, wie vor dem Blatt. Hängt das
                // Blatt noch (etwa nach einem Fehlschlag mit „verwerfen?“), erst schließen — nur „Verwerfen“ (Z-AX7-04).
                if saatAX7b.count == 2, let vorSaatAX7b {
                    if hauptfenster()?.attachedSheet != nil, !(await blattSchliessen()) {
                        zeilen.append("  Blatt vor der Rücknahme der Saat AX7b nicht geschlossen")
                    }
                    if speicher.offenerDialog == nil { _ = speicher.lernendenUebernehmen(vorSaatAX7b) }
                    pruefen(speicher.offenerDialog == nil
                                && speicher.lernende.bestand?.lerngruppen.allSatisfy { $0.archiviert.isEmpty } == true,
                            "Saat AX7b zurückgenommen: keine Lerngruppe mehr archiviert")
                }
                }
                await schrittLaufendesSchuljahr()
                @MainActor func schrittVereinbarungen() async {
                // ── Vereinbarungen (v86, AX7c; AX3, R2-A1: E741, E746, E751, E806, E815) ──
                // Saat: eine Vereinbarung, die gestern ablief, für die zweite Person einer Lerngruppe. Im Teil „Vereinbarungen“
                // steht sie „ungültig“ (abgeleitet, E806); „gültig“ hebt den Ablauf auf, mit Hinweis (E751, E815), ⌘Z bringt ihn.
                // Dann „Handyregel“ mit ⏎ im Titelfeld, Stand von Hand „ungültig“, ⌘Z und ⇧⌘Z. Kästchen und Datumsfeld sind
                // SwiftUI-Schalter — sie bleiben der Hand (B83). Am Ende ist der Entwurf wie beim Öffnen, ⎋ schließt still, die
                // Saat geht zurück.
                let vorSaatAX7c = speicher.lernende.bestand
                var saatAX7c: (gruppe: String, person: String, vereinbarung: String, gestern: String)?
                if let bestand = vorSaatAX7c, hauptfenster()?.attachedSheet == nil {
                    let v = Lernendenverzeichnis(bestand)
                    if let g = v.gruppen().first(where: { v.mitglieder($0.id).count >= 2 }), v.mitglieder(g.id).count >= 2 {
                        let person = v.mitglieder(g.id)[1].id
                        let gestern = Tag.heute.plus(tage: -1).iso
                        if let neu = bestand.mitNeuemAnliegen(.vereinbarung, titel: "Ablaufprobe", lerngruppe: g.id, betroffene: [person],
                                                              datum: Tag.heute.plus(tage: -30).iso, frist: gestern,
                                                              jetzt: Zeitrechnung.jetztAlsZeitstempel()) {
                            _ = speicher.lernendenUebernehmen(neu.bestand)
                            if speicher.lernende.bestand?.anliegen.contains(where: { $0.id == neu.id && $0.frist == gestern }) == true {
                                saatAX7c = (g.id, person, neu.id, gestern)
                            }
                        }
                    }
                }
                pruefen(saatAX7c != nil, "Saat AX7c: eine gestern abgelaufene Vereinbarung in einer Lerngruppe (kein Blatt hängt)")
                if let saat = saatAX7c {
                    speicher.lernendenBlattOeffnen(gruppe: saat.gruppe)
                    speicher.lernendenVorgabe?.gruppenteil = .vereinbarungen
                    for _ in 0..<24 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                    if let blatt = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende {
                        blatt.makeKeyAndOrderFront(nil)
                        @MainActor func entwurf() -> Lernendenbestand? {
                            speicher.lernendenblattGriff?.aenderungen() ?? speicher.lernendenblattGriff?.ausgang()
                        }
                        @MainActor func tabelle() -> NSTableView? {
                            suchen(blatt.contentView, NSTableView.self, {
                                $0.tableColumns.count >= 2 && $0.tableColumns[0].title == "Person"
                                    && $0.tableColumns[1].title == Vereinbarungstext.spalteVereinbarung })
                        }
                        /// Die Stand-Wahl der Leiste: „gültig | ungültig“ (E746).
                        @MainActor func standwahl() -> NSSegmentedControl? {
                            suchen(blatt.contentView, NSSegmentedControl.self, {
                                $0.segmentCount == 2 && $0.label(forSegment: 0) == Gueltigkeit.gueltig.beschriftung
                                    && $0.label(forSegment: 1) == Gueltigkeit.ungueltig.beschriftung })
                        }
                        /// ⌘Z oder ⇧⌘Z am Blatt, ohne Schreibmarke in einem Feld; wartet, bis der Verlauf sich bewegt. Bei ⇧⌘Z:
                        /// der Titel des Eintrags und ob `sendAction` ihn zustellte (Z-AX7-05).
                        var wiederholenAuskunft = "—"
                        @MainActor func zurueck(_ wieder: Bool = false) async {
                            let vorher = speicher.lernendenverlauf.zurueck.count
                            blatt.makeKeyAndOrderFront(nil)
                            blatt.makeFirstResponder(nil)
                            if wieder {
                                // ⇧⌘Z über den Eintrag selbst, wie die Widerrufprobe: Ein gebautes ⇧⌘Z trifft den Eintrag
                                // „Wiederholen“ nicht (dort am Lauf gemessen, hier am 24.10. bestätigt).
                                if let eintrag = Menuetitel.eintrag(umschalt: true), let griff = eintrag.action {
                                    eintrag.menu?.update()
                                    let titel = eintrag.title
                                    let zugestellt = NSApp.sendAction(griff, to: eintrag.target, from: eintrag)
                                    wiederholenAuskunft = "„\(titel)“, \(zugestellt ? "zugestellt" : "nicht zugestellt")"
                                } else {
                                    wiederholenAuskunft = "kein Eintrag „Wiederholen“"
                                }
                            } else {
                                taste("z", code: 6, [.command], in: blatt)
                            }
                            for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count == vorher { await warten(250) }
                        }
                        for _ in 0..<24 where tabelle()?.numberOfRows != 1 { await warten(250) }
                        let schritte = speicher.lernendenverlauf.zurueck.count
                        // 1. Die abgelaufene: gewählt, steht „ungültig“; „gültig“ hebt den Ablauf auf.
                        if let t = tabelle(), t.numberOfRows == 1 {
                            t.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                            for _ in 0..<24 where standwahl() == nil { await warten(250) }
                            let wahl = standwahl()
                            pruefen(wahl?.selectedSegment == 1,
                                    "Vereinbarung, gestern abgelaufen: Die Leiste zeigt „ungültig“ (abgeleitet, E806) — "
                                        + "gewählt \(wahl.map { $0.selectedSegment == -1 ? "nichts" : $0.label(forSegment: $0.selectedSegment) ?? "—" } ?? "keine Wahl")")
                            let meldungenVorher = Set(speicher.meldungen.map(\.id))
                            if let wahl, waehlen(wahl, Gueltigkeit.gueltig.beschriftung) {
                                for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count == schritte { await warten(250) }
                                let frist = entwurf()?.anliegen.first { $0.id == saat.vereinbarung }?.frist
                                let hinweis = speicher.meldungen.first { !meldungenVorher.contains($0.id) }
                                pruefen(speicher.lernendenverlauf.zurueck.count == schritte + 1
                                            && speicher.lernendenverlauf.naechsterName == Schrittname.gueltigkeitAendern
                                            && frist == "" && hinweis?.art == .hinweis,
                                        "„gültig“ an der abgelaufenen: ein Schritt „Gültigkeit ändern“, der Ablauf ist aufgehoben, "
                                            + "ein Hinweis (E751, E815) — „\(hinweis?.text ?? "kein Hinweis")“")
                                // ⌘Z nur, wenn der Schritt entstand — sonst belegte die Zeile nichts (Z-AX7-05).
                                if speicher.lernendenverlauf.zurueck.count == schritte + 1 {
                                    await zurueck()
                                    pruefen(speicher.lernendenverlauf.zurueck.count == schritte
                                                && entwurf()?.anliegen.first { $0.id == saat.vereinbarung }?.frist == saat.gestern,
                                            "⌘Z: der Ablauf wieder gestern")
                                }
                            } else {
                                pruefen(false, "Stand-Wahl „gültig | ungültig“ in der Leiste der Vereinbarung")
                            }
                        } else {
                            pruefen(false, "Teil „Vereinbarungen“: Tabelle „Person / Vereinbarung“ mit der Vereinbarung der Saat "
                                    + "(\(tabelle()?.numberOfRows ?? -1) Zeilen)")
                        }
                        // 2. „Handyregel“ mit ⏎ im Titelfeld: für die erste Person, ohne Ablauf (das Kästchen steht aus).
                        let vorAnlegen = speicher.lernendenverlauf.zurueck.count
                        let bekannt = Set(entwurf()?.anliegen.map(\.id) ?? [])
                        if let feld = suchen(blatt.contentView, NSTextField.self, { $0.placeholderString == Vereinbarungstext.neue }) {
                            blatt.makeFirstResponder(feld)
                            for _ in 0..<12 where (blatt.firstResponder as? NSTextView)?.delegate !== feld { await warten(50) }
                        }
                        // Ohne Schreibmarke im Feld wäre ⏎ „Übernehmen“ (B106) — dann nicht tippen (Z-GR3-03).
                        if let feld = suchen(blatt.contentView, NSTextField.self, { $0.placeholderString == Vereinbarungstext.neue }),
                           (blatt.firstResponder as? NSTextView)?.delegate === feld {
                            tippen("Handyregel", in: blatt)
                            for _ in 0..<12 where (blatt.firstResponder as? NSTextView)?.string != "Handyregel" { await warten(50) }
                            taste("\r", code: 36, in: blatt)
                            for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count == vorAnlegen { await warten(250) }
                            let neu = entwurf()?.anliegen.first { !bekannt.contains($0.id) }
                            let mitglieder = entwurf().map { Set(Lernendenverzeichnis($0).mitglieder(saat.gruppe).map(\.id)) } ?? []
                            for _ in 0..<12 where tabelle()?.numberOfRows != 2 { await warten(250) }
                            pruefen(speicher.lernendenverlauf.zurueck.count == vorAnlegen + 1
                                        && speicher.lernendenverlauf.naechsterName == Schrittname.vereinbarungAnlegen
                                        && neu?.art == .vereinbarung && neu?.titel == "Handyregel" && neu?.frist == ""
                                        && neu?.betroffene.count == 1 && neu.map { mitglieder.isSuperset(of: $0.betroffene) } == true
                                        && tabelle()?.numberOfRows == 2,
                                    "⏎ im Feld „Neue Vereinbarung“: „Handyregel“ angelegt, ohne Ablauf, für eine Person der "
                                        + "Lerngruppe, ein Schritt „Vereinbarung anlegen“, zwei Zeilen")
                            // Die neue Zeile ist gewählt: Stand „gültig“, von Hand „ungültig“ (E746).
                            for _ in 0..<24 where standwahl()?.selectedSegment != 0 { await warten(250) }
                            if let neu, let wahl = standwahl(), wahl.selectedSegment == 0,
                               waehlen(wahl, Gueltigkeit.ungueltig.beschriftung) {
                                for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count == vorAnlegen + 1 { await warten(250) }
                                let ungueltig = entwurf()?.anliegen.first { $0.id == neu.id }?.ungueltig ?? []
                                pruefen(speicher.lernendenverlauf.zurueck.count == vorAnlegen + 2
                                            && speicher.lernendenverlauf.naechsterName == Schrittname.gueltigkeitAendern
                                            && ungueltig == neu.betroffene,
                                        "„ungültig“ von Hand an der neuen: ein Schritt „Gültigkeit ändern“, die Person ungültig (E746)")
                                // Nur die eigenen Schritte zurück — höchstens zwei (Z-AX7-05).
                                let eigene = max(0, min(speicher.lernendenverlauf.zurueck.count - vorAnlegen, 2))
                                for _ in 0..<eigene { await zurueck() }
                                let weg = eigene == 2 && entwurf()?.anliegen.contains { $0.id == neu.id } == false
                                var wieder = false
                                if weg {
                                    await zurueck(true)
                                    wieder = entwurf()?.anliegen.contains { $0.id == neu.id } == true
                                    if wieder { await zurueck() }
                                }
                                let titelRichtig = wiederholenAuskunft.hasPrefix("„Wiederholen: \(Schrittname.vereinbarungAnlegen)“, zugestellt")
                                pruefen(weg && wieder && titelRichtig && speicher.lernendenverlauf.zurueck.count == vorAnlegen,
                                        "⌘Z zweimal nimmt Stand und Vereinbarung, ⇧⌘Z (über den Eintrag) bringt sie, ⌘Z nimmt sie wieder — "
                                            + "nach ⌘Z ⌘Z fort: \(weg ? "ja" : "nein"), Eintrag \(wiederholenAuskunft), "
                                            + "nach ⇧⌘Z da: \(wieder ? "ja" : "nein"), "
                                            + "Schritte \(speicher.lernendenverlauf.zurueck.count) statt \(vorAnlegen)")
                            } else {
                                pruefen(false, "Leiste der neuen Vereinbarung mit „gültig“ gewählt")
                                // Auch hier nur die eigenen Schritte zurück (Z-GR3-03).
                                let eigene = max(0, min(speicher.lernendenverlauf.zurueck.count - vorAnlegen, 2))
                                for _ in 0..<eigene { await zurueck() }
                            }
                        } else {
                            pruefen(false, "Feld „Neue Vereinbarung“ im Teil „Vereinbarungen“ mit der Schreibmarke")
                        }
                        // ⎋: Der Entwurf ist wie beim Öffnen — das Blatt schließt still.
                        // Nur mit Blatt: Ohne Griff wäre `nil == nil` wahr (Z-GR3-03).
                        let unveraendert = speicher.lernendenblattGriff != nil && speicher.lernendenblattGriff?.aenderungen() == nil
                        blatt.makeFirstResponder(nil)
                        taste("\u{1B}", code: 53, in: blatt)
                        for _ in 0..<20 where hauptfenster()?.attachedSheet != nil && Pruefstaende.alertfenster() == nil {
                            await warten(250)
                        }
                        let frage = Pruefstaende.alertfenster() != nil
                        let gefragt = speicher.rueckfrage?.text
                        // Kam eine Frage, schließt `blattSchliessen` — es bestätigt nur „Verwerfen“ (Z-AS1-02, Z-AX7-04).
                        if frage || hauptfenster()?.attachedSheet != nil, !(await blattSchliessen()) {
                            zeilen.append("  Blatt nach AX7c nicht geschlossen")
                        }
                        pruefen(unveraendert && !frage && speicher.offenerDialog == nil,
                                "⎋: Das Blatt schließt still, der Entwurf wie beim Öffnen"
                                    + (frage ? " — es fragte „\(gefragt ?? "…")“" : ""))
                    } else {
                        pruefen(false, "Blatt „Lernende“ an der Lerngruppe der Saat, Teil „Vereinbarungen“")
                        if !(await blattSchliessen()) { zeilen.append("  Blatt nach dem Fehlschlag nicht geschlossen") }
                    }
                    if let vorSaatAX7c {
                        if hauptfenster()?.attachedSheet != nil { await blattSchliessen() }
                        if speicher.offenerDialog == nil { _ = speicher.lernendenUebernehmen(vorSaatAX7c) }
                        pruefen(speicher.offenerDialog == nil
                                    && speicher.lernende.bestand?.anliegen.contains { $0.id == saat.vereinbarung } == false,
                                "Saat AX7c zurückgenommen: keine Vereinbarung der Saat mehr")
                    }
                }
                }
                await schrittVereinbarungen()
                @MainActor func schrittMehrfachauswahl() async {
                // ── Mehrfachauswahl (v86, AX4; E756–E759, Z-AX4-01) ──
                // In der Mitgliederliste einer Lerngruppe wie von Hand: Klick, ⌘-Klick, ⌘-Klick — drei gewählt. Das Menü
                // „Lerngruppen“ der Sammelleiste wie von Hand, ein Klick an seinen Platz unter der Liste (K2; unter macOS 26
                // legt SwiftUI seine Einträge erst beim Öffnen an, unter 27 zeichnet es das Menü selbst, E941), „Umziehen
                // nach“ im Untermenü: ein Schritt „3 Personen umziehen“, ⌘Z, ⇧⌘Z über den Eintrag, ⌘Z. Dann ⌘A in der Liste:
                // alle gewählt, das Raster dahinter bleibt unberührt. Am Ende ist der Entwurf wie beim Öffnen, ⎋ schließt still.
                if hauptfenster()?.attachedSheet != nil { await blattSchliessen() }
                let mfVerzeichnis = speicher.lernende.bestand.map { Lernendenverzeichnis($0) }
                let mfQuelle = mfVerzeichnis.flatMap { v in v.gruppen().first { v.mitglieder($0.id).count >= 3 } }
                let mfZiel = mfVerzeichnis.flatMap { v in
                    v.gruppen().first { $0.id != mfQuelle?.id }
                }
                // E1020 (BC8a): „Alle Lernenden“ — nach ⌘A wählt ein Klick auf eine Zeile genau sie. SwiftUIs Tabelle leerte die
                // Auswahl (so schon in 2.5.0); die AppKit-Hülle wählt wie AppKit. Ein eigenes Blatt in dieser Ansicht, ohne
                // Änderung; ⎋ schließt still.
                if let gA = mfQuelle?.id {
                    speicher.lernendenBlattOeffnen(gruppe: gA)
                    speicher.lernendenVorgabe?.ansicht = .alle
                    for _ in 0..<24 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                    if let blattA = hauptfenster()?.attachedSheet {
                        blattA.makeKeyAndOrderFront(nil)
                        /// Die Tabelle „Alle Lernenden“ an ihren Spalten: sechs, vorn „Nachname“ — die Mitgliederliste hat eine
                        /// ohne Kopf (R7c-03).
                        @MainActor func alleTabelle() -> NSTableView? {
                            suchen(blattA.contentView, NSTableView.self, {
                                $0.numberOfColumns == 6 && $0.tableColumns[0].title.hasPrefix("Nachname")
                            })
                        }
                        /// Die Leiste einer Person: ihr Feld „Nachname“, gefüllt (R7c-02).
                        @MainActor func leisteA() -> Bool {
                            suchen(blattA.contentView, NSTextField.self, {
                                $0.placeholderString == "Nachname" && !$0.stringValue.isEmpty
                            }) != nil
                        }
                        for _ in 0..<20 where (alleTabelle()?.numberOfRows ?? 0) < 3 { await warten(250) }
                        if let t = alleTabelle(), t.numberOfRows >= 3 {
                            blattA.makeFirstResponder(t)
                            taste("a", code: 0, [.command], in: blattA)
                            for _ in 0..<12 where t.selectedRowIndexes.count != t.numberOfRows { await warten(100) }
                            let alleZahl = t.selectedRowIndexes.count
                            let ohneLeiste = !leisteA()
                            let r = t.rect(ofRow: 1)
                            await klicken(t.convert(NSPoint(x: r.midX, y: r.midY), to: nil), in: blattA)
                            for _ in 0..<12 where t.selectedRowIndexes != IndexSet([1]) || !leisteA() { await warten(100) }
                            pruefen(alleZahl == t.numberOfRows && ohneLeiste && t.selectedRowIndexes == IndexSet([1]) && leisteA(),
                                    "„Alle Lernenden“: nach ⌘A (\(alleZahl) von \(t.numberOfRows) gewählt, "
                                        + "\(ohneLeiste ? "Sammelleiste" : "Leiste einer Person")) wählt ein Klick die Zeile mit "
                                        + "ihrer Leiste (E1020) — gewählt "
                                        + Array(t.selectedRowIndexes).prefix(4).map { "\($0 + 1)" }.joined(separator: ", ")
                                        + ", Leiste \(leisteA() ? "da" : "fehlt")")
                            // E1032 (R8a-03): Von einer Gewählten aus eine Auswahl aufziehen, die auf genau denselben Zeilen endet,
                            // abwärts und aufwärts. AppKit lässt die Auswahl stehen; die Hülle wählte danach die gedrückte Zeile
                            // allein, weil sie keine Änderung sah (Klassenmessung 2, Z2/Z4). Gezogen wie mit der Maus: Drücken,
                            // über jede Zeile, Loslassen; geprüft über die Doppelklickzeit hinaus. Dass das Ziehen die Tabelle
                            // erreichte, zeigt der Vorschlag von AppKit an der Hülle (R8a2-05).
                            if t.numberOfRows >= 4, t.window === blattA, alleTabelle() === t {
                                @MainActor func mitte(_ zeile: Int) -> NSPoint {
                                    let r = t.rect(ofRow: zeile)
                                    return t.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
                                }
                                @MainActor func senden(_ art: NSEvent.EventType, _ punkt: NSPoint) {
                                    if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                                         windowNumber: blattA.windowNumber, context: nil,
                                                                         eventNumber: 0, clickCount: 1,
                                                                         pressure: art == .leftMouseUp ? 0 : 1) {
                                        NSApp.postEvent(ereignis, atStart: false)
                                    }
                                }
                                var gezogen: [String] = []
                                var angekommen = true
                                for (von, bis) in [(1, 3), (3, 1)] {
                                    t.selectRowIndexes(IndexSet([1, 2, 3]), byExtendingSelection: false)
                                    // Bis statt der Leiste einer Person die Sammelleiste steht (R8a2-06).
                                    for _ in 0..<12 where leisteA() { await warten(50) }
                                    // Je Richtung frisch: Sonst bewiese der Vorschlag der ersten Richtung auch die zweite (U2-02).
                                    (t as? Huellansicht)?.vorschlagSeitKlick = false
                                    senden(.leftMouseDown, mitte(von))
                                    for zeile in stride(from: von, through: bis, by: von <= bis ? 1 : -1) {
                                        let p = mitte(zeile)
                                        senden(.leftMouseDragged, NSPoint(x: p.x + 3, y: p.y + 4))
                                        senden(.leftMouseDragged, p)
                                    }
                                    senden(.leftMouseUp, mitte(bis))
                                    await warten(Int(NSEvent.doubleClickInterval * 1000) + 250)
                                    angekommen = angekommen && (t as? Huellansicht)?.vorschlagSeitKlick == true
                                    gezogen.append("\(von + 1) → \(bis + 1): "
                                                   + Array(t.selectedRowIndexes).map { "\($0 + 1)" }.joined(separator: ", "))
                                }
                                pruefen(angekommen && gezogen.allSatisfy { $0.hasSuffix(": 2, 3, 4") },
                                        "„Alle Lernenden“: Zeilen 2–4 gewählt, von einer Gewählten aus genau sie aufgezogen — die "
                                            + "Auswahl bleibt wie bei AppKit (E1032, R8a-03): " + gezogen.joined(separator: "; ")
                                            + "; das Ziehen kam \(angekommen ? "an" : "nicht an")")
                            } else {
                                pruefen(false, "„Alle Lernenden“: mindestens vier Zeilen in der Tabelle des Blatts für das Aufziehen "
                                            + "(\(t.numberOfRows) Zeilen; E1032)")
                            }
                        } else {
                            pruefen(false, "„Alle Lernenden“: die Tabelle (sechs Spalten, vorn „Nachname“) mit mindestens drei "
                                        + "Zeilen (E1020)")
                        }
                        taste("\u{1B}", code: 53, in: blattA)
                        for _ in 0..<12 where hauptfenster()?.attachedSheet != nil { await warten(250) }
                        if hauptfenster()?.attachedSheet != nil { await blattSchliessen() }
                    } else {
                        pruefen(false, "„Alle Lernenden“: Blatt offen (E1020)")
                    }
                }
                if let mfVerzeichnis, let quelle = mfQuelle, let ziel = mfZiel {
                    speicher.lernendenBlattOeffnen(gruppe: quelle.id)
                    for _ in 0..<24 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                    if let blatt = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende {
                        blatt.makeKeyAndOrderFront(nil)
                        let zahl = mfVerzeichnis.mitglieder(quelle.id).count
                        @MainActor func entwurf() -> Lernendenbestand? {
                            speicher.lernendenblattGriff?.aenderungen() ?? speicher.lernendenblattGriff?.ausgang()
                        }
                        @MainActor func mitglieder(_ g: String) -> Set<String> {
                            Set(entwurf()?.lerngruppen.first { $0.id == g }?.mitglieder ?? [])
                        }
                        /// Die Mitgliederliste ist eine Tabelle mit einer Spalte ohne Kopf — wie die Liste der Lerngruppen links
                        /// (E1005); gewählt wird die mit `zahl` Zeilen, die im Fenster am weitesten rechts liegt.
                        @MainActor func liste() -> NSTableView? {
                            var treffer: [NSTableView] = []
                            @MainActor func sammeln(_ ansicht: NSView) {
                                if let tab = ansicht as? NSTableView, tab.numberOfRows == zahl { treffer.append(tab) }
                                ansicht.subviews.forEach(sammeln)
                            }
                            if let inhalt = blatt.contentView { sammeln(inhalt) }
                            return treffer.max { $0.convert($0.bounds, to: nil).midX < $1.convert($1.bounds, to: nil).midX }
                        }
                        for _ in 0..<24 where liste() == nil { await warten(250) }
                        if let t = liste() {
                            @MainActor func klick(_ zeile: Int, _ tasten: NSEvent.ModifierFlags) {
                                let zelle = t.frameOfCell(atColumn: 0, row: zeile)
                                let punkt = t.convert(NSPoint(x: zelle.midX, y: zelle.midY), to: nil)
                                for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                                    if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: tasten,
                                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                                         windowNumber: blatt.windowNumber, context: nil, eventNumber: 0,
                                                                         clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                                        NSApp.postEvent(ereignis, atStart: false)
                                    }
                                }
                            }
                            klick(0, [])
                            for _ in 0..<12 where t.selectedRowIndexes != IndexSet([0]) { await warten(100) }
                            klick(1, [.command])
                            for _ in 0..<12 where t.selectedRowIndexes.count != 2 { await warten(100) }
                            klick(2, [.command])
                            for _ in 0..<12 where t.selectedRowIndexes.count != 3 { await warten(100) }
                            pruefen(t.selectedRowIndexes == IndexSet([0, 1, 2]),
                                    "Mitgliederliste „\(quelle.name)“: Klick, ⌘-Klick, ⌘-Klick — drei gewählt (E756)")
                            // Das Menü „Lerngruppen“ der Sammelleiste wie von Hand (K2, E1019): ein Klick an seinen Platz unter der
                            // Mitgliederliste, erkannt an den Untermenüs „Auch aufnehmen in“ und „Umziehen nach“. Gewählt wird im
                            // Untermenü ein Ziel, das es anbietet — jede andere aktive Lerngruppe, in der noch nicht alle drei stehen
                            // (`Sammelmenue`) —, das gesuchte, sonst das erste. Geklickt wird erst, wenn drei gewählt sind und statt
                            // der Leiste einer Person (ihr Feld „Nachname“) die Sammelleiste steht: Rechts neben dem Menü stehen
                            // „Aus der Lerngruppe nehmen“, „Archivieren“ und „Endgültig löschen …“. Traf ein Klick doch einen Knopf
                            // (ein Schritt mehr, eine Rückfrage), klickt die Probe nicht weiter; die Rückfrage lehnt sie ab, und ⌘Z
                            // nimmt den Schritt zurück. Den Text „3 gewählt“ zeigen die Bedienungshilfen im eigenen Prozess nicht;
                            // ihr Menü „Lerngruppen“ schon.
                            @MainActor func personenleiste() -> Bool {
                                suchen(blatt.contentView, NSTextField.self, {
                                    $0.placeholderString == "Nachname" && !$0.stringValue.isEmpty
                                }) != nil
                            }
                            for _ in 0..<12 where personenleiste() { await warten(250) }
                            for _ in 0..<12 where !Lernendenprobe.bedienungshilfenNamen(blatt.contentView).contains("Lerngruppen") {
                                await warten(125)
                            }
                            let leisteDa = t.selectedRowIndexes.count == 3 && !personenleiste()
                            let vorUmzug = speicher.lernendenverlauf.zurueck.count
                            let quelleVorher = mitglieder(quelle.id)
                            // Wer gewählt ist, an den Namen der Zeilen.
                            let gewaehlte = personenDerZeilen(t, t.selectedRowIndexes, entwurf())
                            var sammel = Menuewahl()
                            if leisteDa {
                                sammel = await menueAmPunkt(blatt, Menueanker.lerngruppen(t), passt: {
                                    $0.contains("Auch aufnehmen in") && $0.contains("Umziehen nach")
                                }, waehlen: { menue in
                                    guard let unter = menue.items.first(where: { $0.title == "Umziehen nach" })?.submenu else {
                                        return nil
                                    }
                                    unter.update()
                                    let angeboten = unter.items.indices.filter {
                                        unter.items[$0].action != nil && unter.items[$0].isEnabled
                                    }
                                    return (angeboten.first { unter.items[$0].title.contains(ziel.name) } ?? angeboten.first)
                                        .map { (menue: unter, stelle: $0) }
                                }, halt: { speicher.lernendenverlauf.zurueck.count != vorUmzug })
                            }
                            if sammel.gewaehlt != nil {
                                for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count == vorUmzug { await warten(250) }
                                let gingen = quelleVorher.subtracting(mitglieder(quelle.id))
                                let zielGruppe = entwurf()?.lerngruppen.first { $0.beschriftung == sammel.gewaehlt }
                                let imZiel = zielGruppe.map { mitglieder($0.id).isSuperset(of: gingen) } == true
                                pruefen(speicher.lernendenverlauf.zurueck.count == vorUmzug + 1
                                            && speicher.lernendenverlauf.naechsterName == Schrittname.personenUmziehen(3)
                                            && gingen.count == 3 && gingen == gewaehlte && imZiel,
                                        "„Lerngruppen“ → „Umziehen nach“ → „\(sammel.gewaehlt ?? "—")“: ein Schritt "
                                            + "„\(Schrittname.personenUmziehen(3))“, die drei Gewählten ziehen um (E758, E759) — "
                                            + "\(gingen.count) umgezogen, \(gingen == gewaehlte ? "die gewählten" : "nicht die gewählten")"
                                            + " (wie von Hand, K2)")
                                if speicher.lernendenverlauf.zurueck.count == vorUmzug + 1 {
                                    blatt.makeFirstResponder(nil)
                                    taste("z", code: 6, [.command], in: blatt)
                                    for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count > vorUmzug { await warten(250) }
                                    let zurueck = mitglieder(quelle.id) == quelleVorher
                                    // ⇧⌘Z über den Eintrag (ein gebautes ⇧⌘Z trifft ihn nicht, AX7c).
                                    if let eintrag = Menuetitel.eintrag(umschalt: true), let griff = eintrag.action {
                                        eintrag.menu?.update()
                                        NSApp.sendAction(griff, to: eintrag.target, from: eintrag)
                                    }
                                    for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count == vorUmzug { await warten(250) }
                                    let wieder = mitglieder(quelle.id).count == quelleVorher.count - 3
                                    blatt.makeFirstResponder(nil)
                                    taste("z", code: 6, [.command], in: blatt)
                                    for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count > vorUmzug { await warten(250) }
                                    pruefen(zurueck && wieder && mitglieder(quelle.id) == quelleVorher,
                                            "⌘Z bringt alle drei zurück, ⇧⌘Z zieht sie wieder um, ⌘Z zurück — "
                                                + "zurück \(zurueck ? "ja" : "nein"), wieder \(wieder ? "ja" : "nein")")
                                }
                            } else {
                                // Traf ein Klick einen Knopf statt des Menüs: eine Rückfrage ablehnen und den Schritt zurücknehmen,
                                // ehe es weitergeht (U2-05).
                                if sammel.halt, speicher.rueckfrage != nil { _ = await Pruefstaende.vonHandAntworten(speicher, false) }
                                if speicher.lernendenverlauf.zurueck.count > vorUmzug {
                                    blatt.makeFirstResponder(nil)
                                    taste("z", code: 6, [.command], in: blatt)
                                    for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count > vorUmzug { await warten(250) }
                                }
                                pruefen(false, "„Lerngruppen“ → „Umziehen nach“ wie von Hand, gesucht „\(ziel.name)“ (E758, K2): "
                                            + (!leisteDa ? "keine Sammelleiste mit drei Gewählten (\(t.selectedRowIndexes.count) "
                                                + "gewählt, Leiste einer Person \(personenleiste() ? "da" : "fort"))"
                                               : sammel.gefunden ? "Menü \(sammel.eintraege), nichts gewählt"
                                               : "kein Menü — " + sammel.verlauf.joined(separator: "; ")))
                            }
                            // ⌘A in der Liste: alle gewählt — und nicht die Vorhaben im Raster hinter dem Blatt (Z-AX4-01).
                            let rasterVorher = speicher.auswahl
                            if let t2 = liste() {
                                blatt.makeFirstResponder(t2)
                                taste("a", code: 0, [.command], in: blatt)
                                for _ in 0..<12 where t2.selectedRowIndexes.count != t2.numberOfRows { await warten(100) }
                                pruefen(t2.selectedRowIndexes.count == t2.numberOfRows && speicher.auswahl == rasterVorher,
                                        "⌘A in der Mitgliederliste: alle \(t2.numberOfRows) gewählt, das Raster dahinter unberührt "
                                            + "(\(t2.selectedRowIndexes.count) gewählt)")
                                // ↓/↑ nach ⌘A wie in „Alle Lernenden“ (Z-BC6b-02): In der AppKit-Hülle wählt AppKit selbst ↓ die
                                // letzte und ↑ die vorletzte Zeile (E1020). Die Liste der Probe passt ganz ins Bild — geprüft wird
                                // die Wahl, das Rollen zeigen die Mitteilungen und „Alle Lernenden“.
                                for runter in [true, false] {
                                    if t2.selectedRowIndexes.count != t2.numberOfRows {
                                        taste("a", code: 0, [.command], in: blatt)
                                        for _ in 0..<12 where t2.selectedRowIndexes.count != t2.numberOfRows { await warten(100) }
                                    }
                                    let alle = t2.selectedRowIndexes.count == t2.numberOfRows
                                    // ↓ und ↑ sind in AppKit die Zeichen U+F701 und U+F700.
                                    taste(String(Character(UnicodeScalar(runter ? 0xF701 : 0xF700)!)), code: runter ? 125 : 126,
                                          in: blatt)
                                    for _ in 0..<20 where t2.selectedRowIndexes.count != 1 { await warten(100) }
                                    let soll = t2.numberOfRows - (runter ? 1 : 2)
                                    let gewaehlt = Array(t2.selectedRowIndexes).prefix(4).map { "\($0 + 1)" }
                                    pruefen(alle && Array(t2.selectedRowIndexes) == [soll],
                                            "nach ⌘A in der Mitgliederliste wählt "
                                                + (runter ? "↓ die letzte" : "↑ die vorletzte") + " Zeile (E932, E1005) — gewählt "
                                                + gewaehlt.joined(separator: ", "))
                                }
                                // E1020 (BC8a): Nach ⌘A wählt ein Klick auf eine Zeile genau sie — SwiftUIs Tabelle leerte die
                                // Auswahl (die `List` von 2.5.0 wählte richtig); die AppKit-Hülle wählt wie AppKit.
                                taste("a", code: 0, [.command], in: blatt)
                                for _ in 0..<12 where t2.selectedRowIndexes.count != t2.numberOfRows { await warten(100) }
                                @MainActor func gewaehltE() -> String {
                                    Array(t2.selectedRowIndexes).prefix(6).map { "\($0 + 1)" }.joined(separator: ", ")
                                }
                                /// Die Leiste einer Person: ihr Feld „Nachname“, gefüllt (R7c-02).
                                @MainActor func leisteE() -> Bool {
                                    suchen(blatt.contentView, NSTextField.self, {
                                        $0.placeholderString == "Nachname" && !$0.stringValue.isEmpty
                                    }) != nil
                                }
                                /// Ein Klick wie von Hand auf eine Zeile der Liste (R7c-01).
                                @MainActor func klickE(_ zeile: Int, _ tasten: NSEvent.ModifierFlags = [],
                                                       halten: Int = 120) async {
                                    let zelle = t2.frameOfCell(atColumn: 0, row: zeile)
                                    await klicken(t2.convert(NSPoint(x: zelle.midX, y: zelle.midY), to: nil), in: blatt, tasten,
                                                  halten: halten)
                                }
                                let alleE = t2.selectedRowIndexes.count == t2.numberOfRows && !leisteE()
                                await klickE(1)
                                for _ in 0..<12 where t2.selectedRowIndexes != IndexSet([1]) || !leisteE() { await warten(100) }
                                pruefen(alleE && t2.selectedRowIndexes == IndexSet([1]) && leisteE(),
                                        "nach ⌘A in der Mitgliederliste wählt ein Klick die Zeile mit ihrer Leiste (E1020) "
                                            + "— gewählt " + gewaehltE() + ", Leiste \(leisteE() ? "da" : "fehlt")")
                                // E1029: Die Hülle wählt gleich nach dem Loslassen, nicht erst nach AppKits Doppelklickzeit — geprüft
                                // vor deren Hälfte, gezählt ab dem Loslassen. Dieselbe Zeile wie eben, der Anker für ⇧-Klick bleibt.
                                taste("a", code: 0, [.command], in: blatt)
                                for _ in 0..<12 where t2.selectedRowIndexes.count != t2.numberOfRows { await warten(100) }
                                let alleS = t2.selectedRowIndexes.count == t2.numberOfRows
                                let zelleS = t2.frameOfCell(atColumn: 0, row: 1)
                                await klicken(t2.convert(NSPoint(x: zelleS.midX, y: zelleS.midY), to: nil), in: blatt, halten: 0)
                                let frist = Int(NSEvent.doubleClickInterval * 500)
                                for _ in 0..<(frist / 50) where t2.selectedRowIndexes != IndexSet([1]) { await warten(50) }
                                let sofort = t2.selectedRowIndexes == IndexSet([1])
                                for _ in 0..<12 where t2.selectedRowIndexes != IndexSet([1]) || !leisteE() { await warten(100) }
                                pruefen(alleS && sofort && leisteE(),
                                        "nach ⌘A wählt ein Klick die Zeile vor der halben Doppelklickzeit (\(frist) ms; E1029) — "
                                            + (sofort ? "gewählt" : "noch nicht gewählt") + ", danach " + gewaehltE())
                                // Z-BC8a-04: ⌘A, ein Klick, und sobald er gewählt hat, ⌘A — ohne auf die Leiste zu warten (R8a-02).
                                // Alle bleiben gewählt, auch über die Doppelklickzeit hinaus; AppKits vorgemerkte Wahl der einen Zeile
                                // kommt nicht mehr. Kam das ⌘A erst nach der Doppelklickzeit, sagt der Fall nichts und ist rot.
                                // Danach wieder Zeile 2 allein, als Anker.
                                taste("a", code: 0, [.command], in: blatt)
                                for _ in 0..<12 where t2.selectedRowIndexes.count != t2.numberOfRows { await warten(100) }
                                let beginnV = ProcessInfo.processInfo.systemUptime
                                await klicken(t2.convert(NSPoint(x: zelleS.midX, y: zelleS.midY), to: nil), in: blatt, halten: 0)
                                for _ in 0..<(frist / 50) where t2.selectedRowIndexes != IndexSet([1]) { await warten(50) }
                                taste("a", code: 0, [.command], in: blatt)
                                let abstand = Int((ProcessInfo.processInfo.systemUptime - beginnV) * 1000)
                                let doppel = Int(NSEvent.doubleClickInterval * 1000)
                                await warten(doppel + 250)
                                let bleiben = t2.selectedRowIndexes.count == t2.numberOfRows
                                pruefen(bleiben && abstand < doppel,
                                        "Klick, gleich danach ⌘A (nach \(abstand) ms): nach der Doppelklickzeit noch alle "
                                            + "\(t2.numberOfRows) gewählt (Z-BC8a-04) — gewählt \(t2.selectedRowIndexes.count)"
                                            + (abstand < doppel ? "" : ", ⌘A erst nach der Doppelklickzeit: nicht aussagekräftig"))
                                // U1-02 (E1037): Nach einem Klick auf eine von mehreren Gewählten nimmt die Hülle die
                                // Vormerkungen der Tabelle zurück. Die Tippwahl gleich danach geht weiter: ⌘A, Klick auf
                                // Zeile 2, sobald sie gewählt ist, den Anfang eines anderen Namens tippen — die Auswahl springt
                                // zu ihm. Ziel ist die letzte Zeile, deren Anfang aus Buchstaben (2 bis 6) keine andere Zeile hat.
                                if let spalteT = t2.tableColumns.first, t2.numberOfRows >= 3 {
                                    let texte = (0..<t2.numberOfRows).map {
                                        t2.delegate?.tableView?(t2, typeSelectStringFor: spalteT, row: $0) ?? ""
                                    }
                                    var zielT: Int?
                                    var anfangT = ""
                                    suche: for laenge in 2...6 {
                                        for z in (0..<texte.count).reversed() where z != 1 {
                                            let anfang = String(texte[z].prefix(laenge))
                                            guard anfang.count == laenge, anfang.allSatisfy(\.isLetter) else { continue }
                                            // Wie die Tippwahl: ohne Groß/klein und ohne Akzente (R8g-05).
                                            let falten: (String) -> String = {
                                                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                                            }
                                            if texte.filter({ falten($0).hasPrefix(falten(anfang)) }).count == 1 {
                                                zielT = z
                                                anfangT = anfang
                                                break suche
                                            }
                                        }
                                    }
                                    taste("a", code: 0, [.command], in: blatt)
                                    for _ in 0..<12 where t2.selectedRowIndexes.count != t2.numberOfRows { await warten(100) }
                                    let alleT = t2.selectedRowIndexes.count == t2.numberOfRows
                                    let punktT = t2.convert(NSPoint(x: zelleS.midX, y: zelleS.midY), to: nil)
                                    await klicken(punktT, in: blatt, halten: 0)
                                    for _ in 0..<(frist / 50) where t2.selectedRowIndexes != IndexSet([1]) {
                                        await warten(50)
                                    }
                                    let einzelnT = t2.selectedRowIndexes == IndexSet([1])
                                    if zielT != nil { tippen(anfangT, in: blatt) }
                                    for _ in 0..<12 where zielT.map({ t2.selectedRowIndexes != IndexSet([$0]) }) ?? false {
                                        await warten(100)
                                    }
                                    let gesprungenT = zielT != nil && t2.selectedRowIndexes == IndexSet([zielT ?? -1])
                                    // Und nach der Doppelklickzeit noch dort — was die Hand am Ende sieht (R8g-05).
                                    await warten(Int(NSEvent.doubleClickInterval * 1000) + 100)
                                    let bleibtT = zielT != nil && t2.selectedRowIndexes == IndexSet([zielT ?? -1])
                                    pruefen(alleT && einzelnT && gesprungenT && bleibtT,
                                            zielT == nil
                                                ? "Tippwahl nach dem Klick (U1-02): kein eindeutiger Anfang (2–6 Buchstaben)"
                                                : "nach ⌘A und Klick auf Zeile 2 springt die Tippwahl „\(anfangT)“ zu Zeile "
                                                    + "\((zielT ?? -2) + 1) und bleibt (U1-02, E1037) — " + gewaehltE())
                                } else {
                                    pruefen(false, "Tippwahl nach dem Klick (U1-02): Mitgliederliste mit Spalte und "
                                                + "mindestens drei Zeilen")
                                }
                                await klickE(1)
                                for _ in 0..<12 where t2.selectedRowIndexes != IndexSet([1]) { await warten(100) }
                                await warten(Int(NSEvent.doubleClickInterval * 1000) + 100)
                                if t2.numberOfRows >= 5 {
                                    // R7c-01: Der Anker für ⇧-Klick ist danach die geklickte Zeile.
                                    await klickE(3, [.shift])
                                    for _ in 0..<12 where t2.selectedRowIndexes != IndexSet(1...3) { await warten(100) }
                                    pruefen(t2.selectedRowIndexes == IndexSet(1...3),
                                            "danach ⇧-Klick auf Zeile 4: Zeilen 2–4 gewählt (E1020) — gewählt " + gewaehltE())
                                    // Mehrere, nicht alle: Klick, ⌘-Klick, ⌘-Klick, dann ein Klick auf eine Gewählte — nur sie.
                                    await klickE(0)
                                    for _ in 0..<12 where t2.selectedRowIndexes != IndexSet([0]) { await warten(100) }
                                    let schritt1 = gewaehltE()
                                    await klickE(2, [.command])
                                    for _ in 0..<12 where t2.selectedRowIndexes.count != 2 { await warten(100) }
                                    let schritt2 = gewaehltE()
                                    await klickE(3, [.command])
                                    for _ in 0..<12 where t2.selectedRowIndexes.count != 3 { await warten(100) }
                                    let teil = t2.selectedRowIndexes == IndexSet([0, 2, 3])
                                    let schritt3 = gewaehltE()
                                    await klickE(2)
                                    for _ in 0..<12 where t2.selectedRowIndexes != IndexSet([2]) { await warten(100) }
                                    pruefen(teil && t2.selectedRowIndexes == IndexSet([2]),
                                            "Klick auf Zeile 1 (gewählt \(schritt1)), ⌘-Klick 3 (\(schritt2)), "
                                                + "⌘-Klick 4 (\(schritt3)) von \(t2.numberOfRows); "
                                                + "Klick auf Zeile 3: nur sie (E1020) — gewählt " + gewaehltE())
                                    // Aus BC7d (E1012): Klick, ⇧-Klick zwei weiter, Klick auf die mittlere, sechsmal mit Haltezeiten
                                    // von 20 bis 80 ms — mit SwiftUIs Tabelle leerte der letzte Klick mitunter die Auswahl. Nach jedem
                                    // Klick 500 ms Ruhe, nach dem letzten bis 1 s auf Zeile und Leiste.
                                    var e1012: [String] = []
                                    for (nummer, halten) in [20, 40, 80, 20, 40, 80].enumerated() {
                                        let erste = nummer % 3
                                        let folge: [(Int, NSEvent.ModifierFlags)] = [(erste, []), (erste + 2, [.shift]),
                                                                                     (erste + 1, [])]
                                        for (zeile, tasten) in folge {
                                            await klickE(zeile, tasten, halten: halten)
                                            await warten(500)
                                        }
                                        for _ in 0..<10 where t2.selectedRowIndexes != IndexSet([erste + 1]) || !leisteE() {
                                            await warten(100)
                                        }
                                        if t2.selectedRowIndexes != IndexSet([erste + 1]) || !leisteE() {
                                            e1012.append("\(nummer + 1) (\(halten) ms): gewählt \(gewaehltE()), Leiste "
                                                         + (leisteE() ? "da" : "fehlt"))
                                        }
                                    }
                                    pruefen(e1012.isEmpty, "Klick, ⇧-Klick, Klick auf die mittlere: sechsmal nur sie mit "
                                                + "ihrer Leiste (E1020)"
                                                + (e1012.isEmpty ? "" : " — abweichend: " + e1012.joined(separator: "; ")))
                                } else {
                                    pruefen(false, "Mitgliederliste mit mindestens fünf Zeilen für ⇧-Klick und Teilauswahl (E1020)")
                                }
                                // R7c-01: ⌘A und ein Klick neben die Zeilen — die Auswahl bleibt leer, nachgewählt wird nichts.
                                taste("a", code: 0, [.command], in: blatt)
                                for _ in 0..<12 where t2.selectedRowIndexes.count != t2.numberOfRows { await warten(100) }
                                let alleL = t2.selectedRowIndexes.count == t2.numberOfRows
                                let unten = t2.rect(ofRow: t2.numberOfRows - 1).maxY + 10
                                if unten < t2.visibleRect.maxY - 4 {
                                    await klicken(t2.convert(NSPoint(x: t2.visibleRect.midX, y: unten), to: nil), in: blatt)
                                    for _ in 0..<12 where !t2.selectedRowIndexes.isEmpty { await warten(100) }
                                    // Ob nichts nachgewählt wird, zeigt erst ein Durchlauf nach dem Leeren.
                                    await warten(300)
                                    pruefen(alleL && t2.selectedRowIndexes.isEmpty,
                                            "⌘A, Klick neben die Zeilen: keine gewählt (E1020) — gewählt " + gewaehltE())
                                } else {
                                    pruefen(false, "Mitgliederliste: keine freie Fläche unter \(t2.numberOfRows) Zeilen (E1020)")
                                }
                            } else {
                                pruefen(false, "⌘A: Mitgliederliste mit \(zahl) Zeilen nach dem Umzug nicht wieder da")
                            }
                        } else {
                            // Zur Ursache: alle Tabellen des Blatts mit Spalten und Zeilen.
                            var tabellen: [String] = []
                            @MainActor func sammeln(_ ansicht: NSView) {
                                if let tab = ansicht as? NSTableView {
                                    tabellen.append("[\(tab.tableColumns.map(\.title).joined(separator: ", "))] \(tab.numberOfRows) Zeilen")
                                }
                                ansicht.subviews.forEach(sammeln)
                            }
                            if let inhalt = blatt.contentView { sammeln(inhalt) }
                            pruefen(false, "Mitgliederliste „\(quelle.name)“ mit \(zahl) Zeilen — gefunden: "
                                    + (tabellen.isEmpty ? "keine Tabelle" : tabellen.joined(separator: " · ")))
                        }
                        // ⎋: Der Entwurf ist wie beim Öffnen — das Blatt schließt still; sonst nur „Verwerfen“.
                        // Nur mit Blatt: Ohne Griff wäre `nil == nil` wahr (Z-GR3-03).
                        let unveraendert = speicher.lernendenblattGriff != nil && speicher.lernendenblattGriff?.aenderungen() == nil
                        blatt.makeFirstResponder(nil)
                        taste("\u{1B}", code: 53, in: blatt)
                        for _ in 0..<20 where hauptfenster()?.attachedSheet != nil && Pruefstaende.alertfenster() == nil {
                            await warten(250)
                        }
                        let frage = Pruefstaende.alertfenster() != nil
                        if frage || hauptfenster()?.attachedSheet != nil { await blattSchliessen() }
                        pruefen(unveraendert && !frage && speicher.offenerDialog == nil,
                                "Mehrfachauswahl: ⎋ schließt das Blatt still, der Entwurf wie beim Öffnen")
                    } else {
                        pruefen(false, "Blatt „Lernende“ an „\(quelle.name)“ für die Mehrfachauswahl")
                        await blattSchliessen()
                    }
                } else {
                    pruefen(false, "Mehrfachauswahl: eine Lerngruppe mit drei Mitgliedern und ein Ziel mit Platz")
                }
                }
                await schrittMehrfachauswahl()
                @MainActor func schrittSammelleiste() async {
                // ── Sammelleiste der Mitteilungen (v88, AZ4; E929) ──
                // Im Teil „Mitteilungen“ an „Rücklauf Probe“ (AP8) wie von Hand in der Spalte „Person“: ein Klick — die Leiste der
                // Person —, dann ⌘-Klick, ⌘-Klick — drei gewählt, statt der Leiste die Sammelleiste mit dem Menü „Stand für „…““.
                // Gesehen über Steuerelemente: das Menü (über die Bedienungshilfen) und der Umschalter „offen | erledigt |
                // abgelehnt“ der Leiste einer Person; die Texte der Leisten („3 gewählt“) prüft die Probe nicht. Das Menü
                // bedient sie wie von Hand, mit einem Klick an seinen Platz unter der Tabelle (K2; SwiftUI: unter macOS 26 ein
                // NSPopUpButton ohne Einträge bis zum Öffnen, unter macOS 27 selbst gezeichnet, der Titel nur an einem Knoten der
                // Bedienungshilfen; E941): ein Stand für die drei, ein Schritt, ⌘Z. Die Regeln dahinter prüft die Suite
                // (`SammelruecklaufPruefungen`); „3 gewählt“ und VoiceOver bleiben der Hand. ⌘A wählt alle;
                // danach ↓ die letzte, ↑ die vorletzte Zeile, im Bild (E931–E934) — ebenso in „Alle Lernenden“. Am Ende ist der
                // Entwurf wie beim Öffnen, ⎋ schließt still. In die Spalte „Stand“ klickt die Probe nicht: Dort öffnet ein Klick
                // das Menü der Zelle. Die Tabelle zeigt die jüngste Mitteilung (V7) — „Rücklauf Probe“, angelegt in AP8.
                if hauptfenster()?.attachedSheet != nil { await blattSchliessen() }
                let srBestand = speicher.lernende.bestand
                let srMitteilung = srBestand?.anliegen.first { $0.titel == "Rücklauf Probe" && $0.art == .mitteilung }
                if let srBestand, let srm = srMitteilung,
                   let srGruppe = srBestand.lerngruppen.first(where: { $0.id == srm.lerngruppe }),
                   let aktiveMitteilung = Lernendenverzeichnis(srBestand).mitteilungen(der: srGruppe.id).last {
                    // R-BH5-06: Im 820er-Blatt (E1173) passen alle Zeilen — fürs Rollen (E932, U1-04) 24 weitere Mitglieder der
                    // Gruppe, betroffen von „Rücklauf Probe“; am Ende des Schritts zurück (wie die Saat AX7b).
                    let jetztR = Zeitrechnung.jetztAlsZeitstempel()
                    let eintragR = srBestand.mitPersonen((1...24).map { Namenszeilen.Name(vorname: "Rolle", nachname: String(format: "Probe%02d", $0)) },
                                                         inGruppe: srGruppe.id, jetzt: jetztR)
                    var saatR = eintragR.bestand
                    for p in eintragR.neu { saatR = saatR.mitBetroffenem(srm.id, p, true, jetzt: jetztR) }
                    if eintragR.neu.count == 24 { _ = speicher.lernendenUebernehmen(saatR) }
                    let gesaetR = speicher.lernende.bestand?.anliegen.first { $0.id == srm.id }?.betroffene.count
                    pruefen(gesaetR == srm.betroffene.count + 24,
                            "Saat R-BH5-06: 24 weitere Mitglieder in „Rücklauf Probe“ (\(gesaetR ?? 0) Betroffene) — damit es rollt")
                    // Mit gelungener Saat muss gerollt werden — „nichts zu rollen“ ist dann ein Befund (R-BH5N-06).
                    let saatGilt = gesaetR == srm.betroffene.count + 24
                    speicher.lernendenBlattOeffnen(gruppe: srGruppe.id)
                    for _ in 0..<24 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                    if let blatt = hauptfenster()?.attachedSheet, speicher.offenerDialog == .lernende {
                        blatt.makeKeyAndOrderFront(nil)
                        @MainActor func teilwahl() -> NSSegmentedControl? {
                            suchen(blatt.contentView, NSSegmentedControl.self, { $0.segmentCount == 4 && $0.label(forSegment: 1) == "Mitteilungen" })
                        }
                        for _ in 0..<40 where teilwahl() == nil { await warten(250) }
                        let imTeil = teilwahl().map { waehlen($0, "Mitteilungen") } ?? false
                        /// Die Tabelle der gewählten Mitteilung (v91, BC2): Person · Mitteilung · Frist · Stand.
                        @MainActor func tabelle() -> NSTableView? {
                            suchen(blatt.contentView, NSTableView.self, { Lernendenprobe.istMitteilungstabelle($0) })
                        }
                        for _ in 0..<24 where tabelle() == nil { await warten(250) }
                        /// Die Namen der Elemente der Bedienungshilfen im Blatt (`bedienungshilfenNamen`).
                        @MainActor func namen() -> [String] { Lernendenprobe.bedienungshilfenNamen(blatt.contentView) }
                        let menuetitel = Ruecklaufliste.standmenueTitel(aktiveMitteilung)
                        /// Die Sammelleiste: ihr Menü. Die Leiste einer Person: ihr Umschalter „offen | erledigt | abgelehnt“.
                        @MainActor func sammelmenue() -> Bool { namen().contains(menuetitel) }
                        @MainActor func personenleiste() -> Bool {
                            suchen(blatt.contentView, NSSegmentedControl.self, { s in
                                s.segmentCount == 3 && (0..<3).map { s.label(forSegment: $0) } == ["offen", "erledigt", "abgelehnt"]
                            }) != nil
                        }
                        /// ↓ oder ↑ an einer Tabelle, in der alle gewählt sind: die gewählte Zeile, wenn vorher wirklich alle
                        /// gewählt waren, danach genau eine gewählt ist, die Tabelle zu ihr gerollt hat, sie im Bild steht und
                        /// die Sammelleiste fort ist — sonst `nil`, und eine Auskunft nennt, was stand (E931–E934, Z-AZ4N-02);
                        /// `stand` sagt, woran die Sammelleiste erkannt ist, je Merkmal (Z-AZ6a-01).
                        @MainActor func pfeilNachAlle(_ tv: NSTableView, runter: Bool, sammelleiste: @MainActor () -> Bool,
                                                      stand: @MainActor () -> String) async -> Int? {
                            let vorher = tv.selectedRowIndexes.count
                            // Gerollt muss werden: Der Ausschnitt verschiebt sich durch den Druck — gemessen an seiner Oberkante,
                            // nicht an der ersten (vielleicht angeschnittenen) Zeile. In „Alle Lernenden“ steht die Zielzeile mit
                            // der kleinen Sammelleiste noch im Bild und fällt mit der größeren Leiste einer Person heraus, wenn
                            // niemand rollt. Ohne Verschiebung prüfte „im Bild“ das Rollen nicht (Z-AZ4N-02, Z-AZ4N2-01).
                            let obenVorher = tv.visibleRect.minY
                            // Seit v96 ist das Blatt 820 hoch (E1173): Passen alle Zeilen in den Ausschnitt, gibt es nichts zu
                            // rollen — dann prüft der Schritt Auswahl und Leiste, das Rollen entfällt mit einer Auskunft.
                            let nichtsZuRollen = (tv.enclosingScrollView?.documentView?.frame.height ?? 0)
                                <= (tv.enclosingScrollView?.contentView.bounds.height ?? 0) + 0.5
                            // ↓ und ↑ sind in AppKit die Zeichen U+F701 und U+F700.
                            taste(String(Character(UnicodeScalar(runter ? 0xF701 : 0xF700)!)), code: runter ? 125 : 126, in: blatt)
                            for _ in 0..<20 where tv.selectedRowIndexes.count != 1 { await warten(100) }
                            for _ in 0..<12 where sammelleiste() { await warten(250) }
                            // Gerollt wird beim nächsten Neuaufbau nach der Auswahl — bis die Zeile im Bild ist.
                            @MainActor func imBild() -> Bool {
                                let s = tv.rows(in: tv.visibleRect)
                                return tv.selectedRowIndexes.count == 1 && s.contains(tv.selectedRow)
                            }
                            for _ in 0..<12 where !imBild() { await warten(100) }
                            let sichtbar = tv.rows(in: tv.visibleRect)
                            let gewaehlt = Array(tv.selectedRowIndexes)
                            // Nur, wenn vorher wirklich alle gewählt waren — sonst prüfte ein gewöhnliches ↓/↑ (Z-AZ4-01).
                            let gerollt = tv.visibleRect.minY != obenVorher
                            guard vorher == tv.numberOfRows, gerollt || (nichtsZuRollen && !saatGilt), gewaehlt.count == 1,
                                  sichtbar.contains(gewaehlt[0]), !sammelleiste() else {
                                zeilen.append("  Auskunft: \(runter ? "↓" : "↑") nach \(vorher) gewählt → \(gewaehlt.count) gewählt ("
                                              + gewaehlt.prefix(4).map { "\($0 + 1)" }.joined(separator: ", ") + "), sichtbar "
                                              + "\(sichtbar.location + 1)–\(sichtbar.location + sichtbar.length), Sammelleiste "
                                              + (sammelleiste() ? "da" : "fort") + " (\(stand()))"
                                              + (gerollt ? "" : " — nichts gerollt, Rollen nicht geprüft"))
                                return nil
                            }
                            if nichtsZuRollen && !gerollt {
                                zeilen.append("  Auskunft: \(runter ? "↓" : "↑") nach \(vorher) gewählt — alle \(tv.numberOfRows) "
                                              + "Zeilen im Bild, nichts zu rollen; Rollen entfällt (E1173)")
                            }
                            return gewaehlt[0]
                        }
                        if imTeil, let t = tabelle(), t.numberOfRows >= 3 {
                            @MainActor func zeilenklick(_ zeile: Int, _ tasten: NSEvent.ModifierFlags) {
                                let zelle = t.frameOfCell(atColumn: 0, row: zeile)
                                let punkt = t.convert(NSPoint(x: zelle.midX, y: zelle.midY), to: nil)
                                for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                                    if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: tasten,
                                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                                         windowNumber: blatt.windowNumber, context: nil, eventNumber: 0,
                                                                         clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                                        NSApp.postEvent(ereignis, atStart: false)
                                    }
                                }
                            }
                            zeilenklick(0, [])
                            for _ in 0..<12 where t.selectedRowIndexes != IndexSet([0]) { await warten(100) }
                            for _ in 0..<12 where !personenleiste() { await warten(250) }
                            let vorher = personenleiste() && !sammelmenue()
                            zeilenklick(1, [.command])
                            for _ in 0..<12 where t.selectedRowIndexes.count != 2 { await warten(100) }
                            zeilenklick(2, [.command])
                            for _ in 0..<12 where t.selectedRowIndexes.count != 3 { await warten(100) }
                            for _ in 0..<12 where !sammelmenue() { await warten(250) }
                            let menue = sammelmenue(), leiste = personenleiste()
                            pruefen(vorher && t.selectedRowIndexes == IndexSet([0, 1, 2]) && menue && !leiste,
                                    "Mitteilungen von „\(srGruppe.beschriftung)“: erst eine gewählt mit ihrer Leiste, dann ⌘-Klick, "
                                        + "⌘-Klick — drei gewählt, statt der Leiste die Sammelleiste mit „\(menuetitel)“ (E929; "
                                        + "\(t.selectedRowIndexes.count) gewählt, Menü \(menue ? "da" : "fehlt"), "
                                        + "Leiste einer Person \(leiste ? "noch da" : "fort"))")
                            // Das Menü wie von Hand (K2, E1019): ein Klick an seinen Platz rechts unter der Tabelle, erkannt an den
                            // drei Ständen — nur, wenn die Sammelleiste steht; sonst lägen dort Umschalter und Datumsfeld der Leiste
                            // einer Person. Gewählt wird ein Stand, den nicht alle drei schon tragen (der Haken steht nur am
                            // gemeinsamen, E929): ein Schritt für die Gewählten, deren Rücklauf sich ändert (E915); ⌘Z nimmt ihn
                            // zurück.
                            let staende = Rueckmeldestand.allCases.map { $0.beschriftung(fuer: .mitteilung) }
                            @MainActor func entwurfS() -> Lernendenbestand? {
                                speicher.lernendenblattGriff?.aenderungen() ?? speicher.lernendenblattGriff?.ausgang()
                            }
                            @MainActor func staendeJetzt() -> [String: Rueckmeldestand] {
                                guard let e = entwurfS() else { return [:] }
                                let v = Lernendenverzeichnis(e)
                                // Die Betroffenen aus dem Stand — mit der Saat R-BH5-06 auch die 24 (R-BH5N-05).
                                let betroffen = e.anliegen.first { $0.id == aktiveMitteilung.id }?.betroffene ?? aktiveMitteilung.betroffene
                                return Dictionary(betroffen.map { ($0, v.stand(aktiveMitteilung.id, $0)) },
                                                  uniquingKeysWith: { erster, _ in erster })
                            }
                            if menue && !leiste && t.selectedRowIndexes.count == 3 {
                                let vorStand = speicher.lernendenverlauf.zurueck.count
                                let staendeVorher = staendeJetzt()
                                // Wer gewählt ist, an den Namen der Zeilen.
                                let gewaehlte = personenDerZeilen(t, t.selectedRowIndexes, entwurfS())
                                let standwahl = await menueAmPunkt(blatt, Menueanker.standFuer(t), passt: { $0 == staende },
                                                                   waehlen: { menue in
                                    let haken = menue.items.first { $0.state == .on }?.title
                                    let ziel = haken == staende[2] ? staende[1] : staende[2]
                                    return menue.items.firstIndex { $0.title == ziel }.map { (menue: menue, stelle: $0) }
                                }, halt: { speicher.lernendenverlauf.zurueck.count != vorStand })
                                for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count == vorStand { await warten(250) }
                                let geaendert = staendeJetzt().filter { staendeVorher[$0.key] != $0.value }
                                let nurGewaehlte = !geaendert.isEmpty && gewaehlte.count == 3
                                    && Set(geaendert.keys).isSubset(of: gewaehlte)
                                let schritt = speicher.lernendenverlauf.naechsterName
                                pruefen(standwahl.gewaehlt != nil && nurGewaehlte
                                            && geaendert.values.allSatisfy { $0.beschriftung(fuer: .mitteilung) == standwahl.gewaehlt }
                                            && speicher.lernendenverlauf.zurueck.count == vorStand + 1
                                            && schritt == Schrittname.ruecklaeufeAendern(geaendert.count)
                                            && t.selectedRowIndexes.count == 3,
                                        "„\(menuetitel)“ wie von Hand: "
                                            + (standwahl.gefunden
                                               ? "Menü \(standwahl.eintraege), angehakt \(standwahl.angehakt), "
                                                 + "„\(standwahl.gewaehlt ?? "nichts")“ gewählt — \(geaendert.count) geändert, "
                                                 + (nurGewaehlte ? "nur Gewählte" : "nicht nur Gewählte")
                                                 + ", Schritt „\(schritt ?? "—")“, "
                                                 + "\(t.selectedRowIndexes.count) gewählt"
                                               : "kein Menü — " + standwahl.verlauf.joined(separator: "; "))
                                            + " (E929, E915, K2)")
                                if standwahl.halt, speicher.rueckfrage != nil {
                                    _ = await Pruefstaende.vonHandAntworten(speicher, false)
                                }
                                if speicher.lernendenverlauf.zurueck.count > vorStand {
                                    blatt.makeFirstResponder(nil)
                                    taste("z", code: 6, [.command], in: blatt)
                                    for _ in 0..<12 where speicher.lernendenverlauf.zurueck.count > vorStand { await warten(250) }
                                    pruefen(speicher.lernendenverlauf.zurueck.count == vorStand && staendeJetzt() == staendeVorher,
                                            "⌘Z nimmt den Stand für die drei zurück")
                                }
                            } else {
                                pruefen(false, "„\(menuetitel)“ wie von Hand: nicht geklickt — keine Sammelleiste mit drei Gewählten "
                                            + "(E929, K2)")
                            }
                            blatt.makeFirstResponder(t)
                            taste("a", code: 0, [.command], in: blatt)
                            let alle = t.numberOfRows
                            for _ in 0..<12 where t.selectedRowIndexes.count != alle { await warten(100) }
                            pruefen(t.selectedRowIndexes.count == alle && sammelmenue() && !personenleiste(),
                                    "⌘A in den Mitteilungen: alle \(alle) gewählt, die Sammelleiste steht "
                                        + "(\(t.selectedRowIndexes.count) gewählt)")
                            // Zurück zu einer Person mit ↓/↑ (E931–E934): ↓ die letzte, ↑ die vorletzte Zeile, im Bild. SwiftUIs
                            // Tabelle leerte hier die Auswahl; die AppKit-Hülle wählt wie AppKit (E1020). Den Klick nach ⌘A prüft
                            // die Probe weiter unten an derselben Tabelle.
                            // Statt der Sammelleiste die Leiste einer Person — nicht nur „Menü fort“ (Z-AZ4-01).
                            @MainActor func keinePersonenleiste() -> Bool { sammelmenue() || !personenleiste() }
                            @MainActor func merkmale() -> String {
                                "Menü \(sammelmenue() ? "da" : "fort"), Umschalter \(personenleiste() ? "da" : "fort")"
                            }
                            let unten = await pfeilNachAlle(t, runter: true, sammelleiste: keinePersonenleiste, stand: merkmale)
                            pruefen(unten == alle - 1,
                                    "nach ⌘A wählt ↓ die letzte Zeile, hingerollt und im Bild — die Sammelleiste ist fort (E932)")
                            // Wieder oben anfangen, damit „im Bild“ das Rollen prüft (Z-AZ4-01).
                            t.scrollRowToVisible(0)
                            blatt.makeFirstResponder(t)
                            taste("a", code: 0, [.command], in: blatt)
                            for _ in 0..<12 where t.selectedRowIndexes.count != alle { await warten(100) }
                            let darueber = await pfeilNachAlle(t, runter: false, sammelleiste: keinePersonenleiste, stand: merkmale)
                            pruefen(darueber == alle - 2,
                                    "nach ⌘A wählt ↑ die vorletzte Zeile, hingerollt und im Bild — die Sammelleiste ist fort (E932)")
                            // „Alle Lernenden“ — seit v86 dieselbe Tabelle mit Mehrfachauswahl: ⌘A, ↓ und ↑ ebenso (E931). Die
                            // Leiste einer Person trägt das Feld „Nachname“, die Sammelleiste nicht.
                            if let oben = suchen(blatt.contentView, NSSegmentedControl.self, {
                                   $0.segmentCount == 3 && $0.label(forSegment: 1) == "Alle Lernenden" }),
                               waehlen(oben, "Alle Lernenden") {
                                @MainActor func uebersicht() -> NSTableView? {
                                    suchen(blatt.contentView, NSTableView.self, { $0.tableColumns.first?.title.hasPrefix("Nachname") == true })
                                }
                                for _ in 0..<20 where uebersicht() == nil { await warten(250) }
                                @MainActor func sammelleisteAlle() -> Bool {
                                    suchen(blatt.contentView, NSTextField.self, { $0.placeholderString == "Nachname" }) == nil
                                }
                                @MainActor func merkmaleAlle() -> String { "Feld „Nachname“ \(sammelleisteAlle() ? "fort" : "da")" }
                                if let u = uebersicht(), u.numberOfRows >= 3 {
                                    let n = u.numberOfRows
                                    blatt.makeFirstResponder(u)
                                    taste("a", code: 0, [.command], in: blatt)
                                    for _ in 0..<12 where u.selectedRowIndexes.count != n { await warten(100) }
                                    for _ in 0..<12 where !sammelleisteAlle() { await warten(250) }
                                    let alleGewaehlt = u.selectedRowIndexes.count == n && sammelleisteAlle()
                                    let untenAlle = await pfeilNachAlle(u, runter: true, sammelleiste: sammelleisteAlle,
                                                                        stand: merkmaleAlle)
                                    u.scrollRowToVisible(0)
                                    blatt.makeFirstResponder(u)
                                    taste("a", code: 0, [.command], in: blatt)
                                    for _ in 0..<12 where u.selectedRowIndexes.count != n { await warten(100) }
                                    let darueberAlle = await pfeilNachAlle(u, runter: false, sammelleiste: sammelleisteAlle,
                                                                           stand: merkmaleAlle)
                                    pruefen(alleGewaehlt && untenAlle == n - 1 && darueberAlle == n - 2,
                                            "„Alle Lernenden“ (\(n) Zeilen): ⌘A wählt alle mit Sammelleiste, ↓ die letzte, ↑ die vorletzte "
                                                + "Zeile, hingerollt und im Bild (E931, E932)")
                                    // U1-04 (E1035): Zeile 2 allein gewählt, mit Ende gerollt, dann der Ausschnitt der Tabelle
                                    // 60 pt flacher und wieder so hoch wie vorher — die Tabelle rollt nicht zur Gewählten zurück,
                                    // wie nach dem Rollen mit Rad oder Trackpad (R8a-04); vorher tat sie es. Wohin AppKit den
                                    // Ausschnitt bei der künstlichen Änderung schiebt, ist seine Sache (gemessen 57 → 112 pt); die
                                    // Lage bei einem echten Größenwechsel misst die Klassenmessung 2. Bild ↓ ließ die Hülle schon
                                    // vorher los (gemessen unter macOS 26.7.2), Ende nicht; Pos1 und Bild ↑ sind nicht gemessen.
                                    // Das Blatt selbst lässt sich nicht von außen verkleinern; geändert wird der Rahmen der Rolle,
                                    // wie ihn ein Größenwechsel ändert, und die Probe stellt ihn wieder her.
                                    // Seit v96 (E1173) 820 hoch: Die Saat R-BH5-06 gibt 24 Zeilen mehr, damit „Ende“ rollt; passten
                                    // dennoch alle, entfiele U1-04 mit einer Auskunft.
                                    let rolleU = u.enclosingScrollView
                                    if (rolleU?.documentView?.frame.height ?? 0) <= (rolleU?.contentView.bounds.height ?? 0) + 0.5 {
                                        if saatGilt {
                                            pruefen(false, "U1-04: trotz Saat R-BH5-06 alle \(n) Zeilen von „Alle Lernenden“ im Bild — "
                                                    + "nichts zu rollen (R-BH5N-06)")
                                        } else {
                                            zeilen.append("  Auskunft: U1-04 entfällt — alle \(n) Zeilen von „Alle Lernenden“ im Bild, "
                                                          + "nichts zu rollen (E1173)")
                                        }
                                    } else {
                                    u.scrollRowToVisible(0)
                                    let zelleR = u.frameOfCell(atColumn: 0, row: 1)
                                    await klicken(u.convert(NSPoint(x: zelleR.midX, y: zelleR.midY), to: nil), in: blatt)
                                    for _ in 0..<12 where u.selectedRowIndexes != IndexSet([1]) || sammelleisteAlle() {
                                        await warten(100)
                                    }
                                    await warten(300)
                                    let obenR = u.visibleRect.minY
                                    // Ende ist in AppKit das Zeichen U+F72B.
                                    taste("\u{F72B}", code: 119, [.function], in: blatt)
                                    for _ in 0..<12 where u.visibleRect.minY == obenR { await warten(100) }
                                    let gerolltR = u.visibleRect.minY
                                    var geschrumpftR = false
                                    var wiederR = false
                                    if let rolleR = u.enclosingScrollView {
                                        let rahmenR = rolleR.frame
                                        let hoeheR = rolleR.contentView.frame.height
                                        rolleR.frame = NSRect(x: rahmenR.minX, y: rahmenR.minY, width: rahmenR.width,
                                                              height: rahmenR.height - 60)
                                        geschrumpftR = rolleR.contentView.frame.height < hoeheR
                                        await warten(300)
                                        rolleR.frame = rahmenR
                                        await warten(300)
                                        wiederR = rolleR.frame == rahmenR && rolleR.contentView.frame.height == hoeheR
                                    }
                                    let danachR = u.visibleRect.minY
                                    let zeile2R = u.visibleRect.contains(u.rect(ofRow: 1))
                                    pruefen(u.selectedRowIndexes == IndexSet([1]) && gerolltR > obenR && geschrumpftR && wiederR
                                                && danachR >= gerolltR && !zeile2R,
                                            "„Alle Lernenden“: Zeile 2 allein gewählt, mit Ende gerollt, der Ausschnitt flacher "
                                                + "und zurück — die Tabelle rollt nicht zur Gewählten zurück (U1-04, E1035): oben "
                                                + "\(Int(obenR)) → "
                                                + "\(Int(gerolltR)) → \(Int(danachR)) pt, Ausschnitt "
                                                + (geschrumpftR ? "geschrumpft" : "NICHT geschrumpft")
                                                + (wiederR ? " und wiederhergestellt" : ", NICHT wiederhergestellt")
                                                + ", Zeile 2 " + (zeile2R ? "im Bild" : "nicht im Bild"))
                                    }
                                } else {
                                    pruefen(false, "„Alle Lernenden“: Tabelle mit mindestens drei Zeilen")
                                }
                            } else {
                                pruefen(false, "Umschalter „Alle Lernenden“ gefunden und bedient")
                            }
                        } else {
                            pruefen(false, "Mitteilungen von „\(srGruppe.beschriftung)“: Teil gewählt \(imTeil ? "ja" : "nein"), "
                                    + "Rücklauftabelle \(tabelle().map { "mit \($0.numberOfRows) Zeilen" } ?? "nicht gefunden")")
                        }
                        let unveraendert = speicher.lernendenblattGriff != nil && speicher.lernendenblattGriff?.aenderungen() == nil
                        blatt.makeFirstResponder(nil)
                        taste("\u{1B}", code: 53, in: blatt)
                        for _ in 0..<20 where hauptfenster()?.attachedSheet != nil && Pruefstaende.alertfenster() == nil {
                            await warten(250)
                        }
                        let frage = Pruefstaende.alertfenster() != nil
                        if frage || hauptfenster()?.attachedSheet != nil { await blattSchliessen() }
                        pruefen(unveraendert && !frage && speicher.offenerDialog == nil,
                                "Sammelleiste der Mitteilungen: ⎋ schließt das Blatt still, der Entwurf wie beim Öffnen")
                    } else {
                        pruefen(false, "Blatt „Lernende“ an „\(srGruppe.beschriftung)“ für die Sammelleiste der Mitteilungen")
                        await blattSchliessen()
                    }
                    // Die Saat R-BH5-06 zurück — erst das Blatt zu, dann zurücknehmen, immer mit Ergebnis (wie AX7b; R-BH5N-05).
                    if saatGilt {
                        if hauptfenster()?.attachedSheet != nil, !(await blattSchliessen()) {
                            zeilen.append("  Blatt vor der Rücknahme der Saat R-BH5-06 nicht geschlossen")
                        }
                        if speicher.offenerDialog == nil { _ = speicher.lernendenUebernehmen(srBestand) }
                        pruefen(speicher.offenerDialog == nil && speicher.lernende.bestand?.lernende.count == srBestand.lernende.count,
                                "Saat R-BH5-06 zurückgenommen (\(speicher.lernende.bestand?.lernende.count ?? 0) Lernende)")
                    }
                } else {
                    pruefen(false, "Sammelleiste der Mitteilungen: „Rücklauf Probe“ aus AP8 mit ihrer Lerngruppe")
                }
                }
                await schrittSammelleiste()
                @MainActor func schrittKurszelle() async {
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
                    // Ein Fach trägt die Lerngruppe nicht mehr (E665): der Name der an k-1 gebundenen. Seit v96 steht der
                    // Name im Unterblatt der Lerngruppe (E1169) — welche gewählt ist, sagt der Griff des Blatts.
                    for _ in 0..<30 where speicher.lernendenblattGriff?.gewaehlteGruppe() == nil { await warten(150) }
                    let gebundeneGruppe = speicher.lerngruppe(fuerZeile: "k-1")
                    let gewaehlt = speicher.lernendenblattGriff?.gewaehlteGruppe()
                    let name = gewaehlt != nil && gewaehlt == gebundeneGruppe?.id ? gebundeneGruppe?.name : nil
                    let gebunden = gebundeneGruppe?.name
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
                }
                await schrittKurszelle()
                @MainActor func schrittRufname() async {
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
                }
                await schrittRufname()

                @MainActor func schrittSitzplan() async {
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
                }
                await schrittSitzplan()
                @MainActor func schrittExport() async {
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
                }
                await schrittExport()
                @MainActor func schrittImportbogen() async {
                // ── Z-AY2N2-02 (v87): ⌘⏎ am Importbogen, dahinter eine getippte Liste — das Blatt darunter trägt nichts
                // ein, solange der Bogen steht (sonst zeigte die gemerkte Vorschau einen alten Stand); ohne Bogen trägt
                // dieselbe Taste ein (Gegenprobe). Danach ⌘Z bis zum Stand beim Öffnen und ⎋ (E995), die Jahresdatei bleibt.
                let vorEintrag = speicher.lernende.bestand
                speicher.lernendenBlattOeffnen(gruppe: "g-1")
                speicher.lernendenVorgabe?.namenstext = "Bogen, Bert"
                speicher.lernendenVorgabe?.importdatei = ablage.ordner.appending(component: "iserv-muster.csv")
                for _ in 0..<24 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                if let blattN = hauptfenster()?.attachedSheet, let bogenN = blattN.attachedSheet {
                    let schritteN = speicher.lernendenverlauf.zurueck.count
                    bogenN.makeKeyAndOrderFront(nil)
                    for _ in 0..<12 where !bogenN.isKeyWindow { await warten(50) }
                    bogenN.makeFirstResponder(nil)
                    taste("\r", code: 36, [.command], in: bogenN)
                    for _ in 0..<8 where speicher.lernendenverlauf.zurueck.count == schritteN { await warten(250) }
                    let unberuehrt: Bool = speicher.lernendenverlauf.zurueck.count == schritteN
                    let bogenSteht: Bool = blattN.attachedSheet === bogenN
                    let listeSteht: Bool = speicher.lernendenblattGriff?.namenOffen() == true
                    let schrittN: String = speicher.lernendenverlauf.naechsterName ?? "—"
                    let zusatzN: String = unberuehrt ? "" : " — Schritt „\(schrittN)“"
                    pruefen(unberuehrt && bogenSteht && listeSteht,
                            "⌘⏎ am Importbogen, dahinter eine getippte Liste: nichts eingetragen, der Bogen steht (Z-AY2N2-02)"
                                + zusatzN)
                    taste("\u{1B}", code: 53, in: bogenN)
                    for _ in 0..<12 where blattN.attachedSheet != nil { await warten(250) }
                    blattN.makeKeyAndOrderFront(nil)
                    for _ in 0..<12 where !blattN.isKeyWindow { await warten(50) }
                    let schritteOhne = speicher.lernendenverlauf.zurueck.count
                    taste("\r", code: 36, [.command], in: blattN)
                    for _ in 0..<8 where speicher.lernendenverlauf.zurueck.count == schritteOhne { await warten(250) }
                    let schrittOhne: String = speicher.lernendenverlauf.naechsterName ?? "—"
                    pruefen(blattN.attachedSheet == nil && schrittOhne == Schrittname.namenEintragen,
                            "Gegenprobe: ohne Bogen trägt ⌘⏎ die Liste ein (\(schrittOhne))")
                    // Zum Stand beim Öffnen zurück, dann ⎋ ohne Rückfrage — kein „Verwerfen“ per Klick im Alert: Ein Klick dort
                    // brachte den Lauf gelegentlich zum Absturz (E995). Fragt ⎋ doch (⌘Z erreichte den Stand nicht), antwortet
                    // `blattSchliessen()` per Klick — nur im Fehlerfall, die Prüfzeile ist dann ohnehin ✗ (W3-10).
                    blattN.makeFirstResponder(nil)
                    for _ in 0..<4 where speicher.lernendenverlauf.zurueck.count > schritteN {
                        let vor = speicher.lernendenverlauf.zurueck.count
                        taste("z", code: 6, [.command], in: blattN)
                        for _ in 0..<8 where speicher.lernendenverlauf.zurueck.count == vor { await warten(250) }
                    }
                    taste("\u{1B}", code: 53, in: blattN)
                    for _ in 0..<12 where hauptfenster()?.attachedSheet != nil && Pruefstaende.alertfenster() == nil {
                        await warten(250)
                    }
                    pruefen(hauptfenster()?.attachedSheet == nil && Pruefstaende.alertfenster() == nil,
                            "Importbogen: ⌘Z bis zum Stand beim Öffnen, dann ⎋ — das Blatt schließt ohne Rückfrage (E995)")
                } else {
                    pruefen(false, "Bogen „Aus IServ importieren“ mit getippter Liste am Blatt „Lernende“")
                }
                if !(await blattSchliessen()) { zeilen.append("  Blatt nach Z-AY2N2-02 nicht geschlossen") }
                pruefen(speicher.lernende.bestand == vorEintrag, "nach Z-AY2N2-02: die Jahresdatei wie vorher")
                }
                await schrittImportbogen()
                @MainActor func schrittIServImport() async {
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
                }
                await schrittIServImport()
                @MainActor func schrittTerminOhneLerngruppe() async {
                // ── Termin ohne Lerngruppe (AP13b, E290): unter „Alle Lernenden“ im Bogen anlegen, ⏎, übernehmen ──
                terminperson = speicher.lernende.verzeichnis?.alle.first { $0.nachname == "Hübner" }
                speicher.lernendenBlattOeffnen()
                speicher.lernendenVorgabe?.ansicht = .alle
                speicher.lernendenVorgabe?.person = terminperson?.id
                speicher.lernendenVorgabe?.anliegenbogen = .termin
                for _ in 0..<24 where hauptfenster()?.attachedSheet?.attachedSheet == nil { await warten(250) }
                // Bis die Felder im Bogen stehen — nicht fest (Z14f-03).
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
                }
                await schrittTerminOhneLerngruppe()
                @MainActor func schrittTerminVorhaben() async {
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
                }
                await schrittTerminVorhaben()
                @MainActor func schrittVorhabenTermin() async {
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
                }
                await schrittVorhabenTermin()
                @MainActor func schrittKachelmenue() async {
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
                    /// Rechtsklick auf die Kachel, im Menü `eintrag` wählen — wie von Hand; wartet, bis ein Blatt hängt oder das
                    /// Menü ohne Wahl zu ist. `Menuekasten.nurLesen`: das Menü nur lesen und gleich schließen (AX7a, Z-AX7-01).
                    @MainActor func kachelmenue(_ eintrag: String) async -> Menuekasten {
                        let punkt = kachelmitte(kachel)
                        let kasten = Menuekasten()
                        let auf = NotificationCenter.default.addObserver(
                            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { meldung in
                            nonisolated(unsafe) let menue = meldung.object as? NSMenu
                            MainActor.assumeIsolated { if let menue { kasten.bedienen(menue, eintrag) } }
                        }
                        // Zu ist nur das erste Menü — ein Untermenü, das unterwegs auf- und zugeht, zählt nicht (Z-AX7-01).
                        let zu = NotificationCenter.default.addObserver(
                            forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { meldung in
                            nonisolated(unsafe) let menue = meldung.object as? NSMenu
                            MainActor.assumeIsolated { if menue != nil, menue === kasten.menue { kasten.zu = true } }
                        }
                        for art in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
                            if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                                 windowNumber: fenster.windowNumber, context: nil, eventNumber: 0,
                                                                 clickCount: 1, pressure: art == .rightMouseDown ? 1 : 0) {
                                NSApp.postEvent(ereignis, atStart: false)
                            }
                        }
                        // Bis ein Blatt hängt — oder das Menü ohne Wahl zu ist: Dann kommt keines (AX7a).
                        for _ in 0..<24 where fenster.attachedSheet == nil && !(kasten.zu && !kasten.gewaehlt) { await warten(250) }
                        // Blieb es offen, schluckte es die Tasten der folgenden Schritte (Z14f-11, Z-AX7-01).
                        if let offen = kasten.menue, !kasten.zu { offen.cancelTrackingWithoutAnimation() }
                        NotificationCenter.default.removeObserver(auf)
                        NotificationCenter.default.removeObserver(zu)
                        await warten(600)
                        return kasten
                    }
                    /// ⎋ an das Blatt, wie von Hand: Ohne Eingabe schließt es still, ohne „verwerfen?“ (G1-02, E786, E296).
                    /// Kam doch eine Frage, wird sie verworfen — sonst hinge der Rest der Probe an ihr.
                    @MainActor func escOhneEingabe(_ was: String) async {
                        guard let blatt = fenster.attachedSheet else { return }
                        blatt.makeKeyAndOrderFront(nil)
                        for _ in 0..<12 where !blatt.isKeyWindow { await warten(50) }
                        taste("\u{1B}", code: 53, in: blatt)
                        for _ in 0..<12 where fenster.attachedSheet != nil && Pruefstaende.alertfenster() == nil { await warten(250) }
                        let frage = Pruefstaende.alertfenster() != nil
                        pruefen(!frage && fenster.attachedSheet == nil, "\(was), dann ⎋ ohne Eingabe: Das Blatt schließt still (G1-02, E786)"
                                + (frage ? " — es fragt „\(speicher.rueckfrage?.text ?? "…")“"
                                         : fenster.attachedSheet != nil ? " — das Blatt steht noch" : ""))
                        if frage { _ = await Pruefstaende.vonHandAntworten(speicher, true) }
                        if fenster.attachedSheet != nil { speicher.vorhabenDialog = nil }
                        for _ in 0..<12 where fenster.attachedSheet != nil { await warten(250) }
                    }
                    let kasten = await kachelmenue("Als Termin führen …")
                    // „Wochentag“ zwischen „Als Termin führen …“ und „Hausaufgabe hinzufügen …“ (E655, Z-AX5-03).
                    // Die Vorbereitung zwischen dringlich und Korrektur (v93, E1074).
                    let erwartet = ["Öffnen", "Titel ändern", "Als dringlich kennzeichnen", "Als Vorbereitung kennzeichnen",
                                    "Als Korrektur kennzeichnen", "Als Prüfung führen", "Als Termin führen …", "Wochentag",
                                    "Hausaufgabe hinzufügen …"]
                    let folge = kasten.titel.filter { erwartet.contains($0) }
                    pruefen(kasten.gewaehlt && folge == erwartet && speicher.vorhabenDialog?.termin == true
                            && speicher.vorhabenDialog?.datum != nil,
                            "Kontextmenü der Kachel: " + kasten.titel.filter { !$0.isEmpty }.joined(separator: " · ")
                            + " — „Als Termin führen …“ öffnet den Dialog eingeschaltet, mit Tag")
                    if kasten.gewaehlt && speicher.vorhabenDialog?.termin == true {
                        await escOhneEingabe("„Als Termin führen …“")
                    } else {
                        speicher.vorhabenDialog = nil
                        for _ in 0..<12 where fenster.attachedSheet != nil { await warten(250) }
                    }
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
                        if offen {
                            await escOhneEingabe("„Hausaufgabe hinzufügen …“")
                        } else {
                            speicher.vorhabenDialog = nil
                            for _ in 0..<12 where fenster.attachedSheet != nil { await warten(250) }
                        }
                        if offen {
                            pruefen(hatHausaufgabe() == false, "„Hausaufgabe hinzufügen …“ ohne „Übernehmen“: nichts bleibt zurück (E653)")
                        }
                    } else {
                        pruefen(false, "Kachel „Bits und Bytes“ ohne Hausaufgabe für „Hausaufgabe hinzufügen …“")
                    }
                    // ── Wochentag im Kachelmenü (v86, AX7a: E655, E781, E801; Z-AX5-03) ──
                    // Das Menü per Rechtsklick wie von Hand, beim Öffnen gelesen und gleich geschlossen; das Untermenü
                    // „Wochentag“: „Mo.“ … „Fr.“, das Häkchen am gesetzten Tag. Ein Tag wird über die Handlung seines Eintrags
                    // ausgelöst — so ist der Weg vom Menü zum Speicher belegt; der Tastenweg ins Untermenü bleibt der Hand.
                    // Die Woche rechnet die Probe wie die App; dass ein Datum außerhalb der Woche keinen Tag ankreuzt, prüft
                    // die Suite (`WochentagImKachelmenuePruefungen`, Z-AX7-03). Widerrufen wird am Speicher.
                    /// Rechtsklick wie oben, nur gelesen: das Untermenü „Wochentag“ — `nil`, wenn ein Blatt hängt, die Kachel
                    /// verdeckt ist oder sie inzwischen ein anderes Vorhaben zeigt.
                    @MainActor func untermenueWochentag() async -> NSMenu? {
                        guard fenster.attachedSheet == nil, kachel.stand?.vorhaben.id == kennung,
                              kachelrahmen?.hitTest(kachelmitte(kachel))?.isDescendant(of: kachel) == true else { return nil }
                        let gelesen = await kachelmenue(Menuekasten.nurLesen)
                        // Vor dem Lesen nachführen: Heute baut `tagmenue` vorab; das schützt, falls ein Untermenü einmal erst
                        // beim Öffnen entsteht (Z-GR3-04, Z-AX9N-08).
                        let tage = gelesen.menue?.items.first { $0.title == "Wochentag" }?.submenu
                        tage?.update()
                        return tage
                    }
                    @MainActor func datum() -> Tag? {
                        kennung.flatMap { id in speicher.planung?.eintraege.first { $0.id == id } }?.datum
                    }
                    // Der Montag der Woche des Vorhabens: Gesetzt ist nur ein Datum in dieser Woche (`wochentagzeilen`).
                    let montag = kennung.flatMap { id in speicher.planung?.eintraege.first { $0.id == id } }
                        .flatMap { v in speicher.planung.map { $0.start.montagDerWoche.plus(tage: v.woche * 7) } }
                    @MainActor func tagDerWoche(_ stelle: Int) -> Tag? {
                        guard Wochentag.allCases.indices.contains(stelle) else { return nil }
                        return montag.map { Wochentag.allCases[stelle].datum(inWocheVon: $0) }
                    }
                    if let tage = await untermenueWochentag() {
                        let titel = tage.items.map(\.title)
                        let vorher = datum()
                        let gesetzt = tage.items.indices.filter { tage.items[$0].state == .on }
                        let soll = Wochentag.allCases.indices.filter { vorher != nil && tagDerWoche($0) == vorher }
                        pruefen(titel == ["Mo.", "Di.", "Mi.", "Do.", "Fr."] && montag != nil && gesetzt == soll,
                                "Kachelmenü „Wochentag“: \(titel.joined(separator: " ")), Häkchen an \(gesetzt.map { titel[$0] }) "
                                    + "— der Tag des Vorhabens in seiner Woche (\(vorher?.deutsch ?? "ohne Datum"))")
                        // Ein nicht gesetzter, wählbarer Tag: setzen (ein Schritt), dann am neuen Menü nehmen, ⌘Z zweimal.
                        if let stelle = tage.items.indices.first(where: { tage.items[$0].state != .on && tage.items[$0].action != nil }) {
                            // ⌘Z nimmt nur zurück, was hier entstand — nie einen älteren Schritt der Probe.
                            let schritteVorher = speicher.verlauf.zurueck.count
                            tage.performActionForItem(at: stelle)
                            // Auf den Schritt warten, mit Obergrenze — reicht SwiftUI die Handlung später (Z-GR3-04).
                            for _ in 0..<12 where speicher.verlauf.zurueck.count == schritteVorher { await warten(50) }
                            let neu = datum()
                            pruefen(neu != nil && neu == tagDerWoche(stelle)
                                        && speicher.verlauf.naechsterName == Schrittname.wochentagSetzen,
                                    "„Wochentag“ → „\(titel[stelle])“ setzt den Tag (\(neu?.deutsch ?? "—")), Schritt „Wochentag setzen“ "
                                        + "(über die Handlung des Eintrags)")
                            if let wieder = await untermenueWochentag(), wieder.items.indices.contains(stelle) {
                                pruefen(wieder.items[stelle].state == .on,
                                        "„Wochentag“ beim zweiten Öffnen: Häkchen an „\(titel[stelle])“")
                                let vorNehmen = speicher.verlauf.zurueck.count
                                wieder.performActionForItem(at: stelle)
                                for _ in 0..<12 where speicher.verlauf.zurueck.count == vorNehmen { await warten(50) }
                                pruefen(datum() == nil && speicher.verlauf.naechsterName == Schrittname.wochentagEntfernen,
                                        "„\(titel[stelle])“ mit Häkchen nimmt den Tag, Schritt „Wochentag entfernen“ (über die Handlung des Eintrags)")
                                let neueSchritte = speicher.verlauf.zurueck.count - schritteVorher
                                for _ in 0..<max(0, min(neueSchritte, 2)) { speicher.widerrufen() }
                                pruefen(neueSchritte == 2 && datum() == vorher && speicher.verlauf.zurueck.count == schritteVorher,
                                        "Widerrufen am Speicher, zweimal: der Tag wie vorher (\(vorher?.deutsch ?? "ohne Datum")) — "
                                            + "\(neueSchritte) neue Schritte")
                            } else {
                                pruefen(false, "„Wochentag“ ließ sich kein zweites Mal öffnen")
                                // Was hier entstand, wieder fort — der Rest der Probe läuft auf dem Vorhaben wie vorher (Z-AX7-02).
                                let neueSchritte = speicher.verlauf.zurueck.count - schritteVorher
                                for _ in 0..<max(0, min(neueSchritte, 2)) { speicher.widerrufen() }
                            }
                        } else {
                            pruefen(false, "„Wochentag“: kein wählbarer, nicht gesetzter Tag")
                        }
                    } else {
                        pruefen(false, "Kachelmenü ohne Untermenü „Wochentag“ (oder ein Blatt hängt, oder die Kachel ist verdeckt)")
                    }
                } else {
                    pruefen(false, "Kachel „Bits und Bytes“ unter dem Klickpunkt (\(kacheln.count) Kacheln)")
                }
                }
                await schrittKachelmenue()
                @MainActor func schrittSucheUndUmzug() async {
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
                }
                await schrittSucheUndUmzug()
                @MainActor func schrittE304() async {
                // ── E304 am Paket: eine Person mit Tisch endgültig gelöscht und übernommen — die Datei trägt sie nicht mehr ──
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
                }
                await schrittE304()
                @MainActor func schrittTischEntfernen() async {
                // ── AY6a (v87, E882–E884 b): „Löschen und Tisch entfernen“ im echten Alert am Blatt. Eine eigene Person mit
                // eigenem Tisch in k-1, damit sich kein späterer Schritt verschiebt: Ihr Tisch geht aus dem Sitzplan, die
                // übrigen bleiben, wie sie sind; sitzplaene.json trägt ihn nicht mehr. ──
                if let bestand = speicher.lernende.bestand, let gruppe = bestand.lerngruppen.first?.id,
                   let planVorher = speicher.sitzplan(fuer: "k-1") {
                    let eintrag = bestand.mitPersonen(Namenszeilen.lesen("Tischfort, Tim").namen, inGruppe: gruppe,
                                                      jetzt: Zeitrechnung.jetztAlsZeitstempel())
                    let neuePerson = eintrag.bestand.lernende.first { $0.nachname == "Tischfort" }?.id
                    if let neuePerson, speicher.lernendenUebernehmen(eintrag.bestand) == nil {
                        var mitTisch = planVorher
                        mitTisch.tische.append(Tisch(id: "t-tischfort", name: "Tim Tischfort", x: 40, y: 40, lernender: neuePerson))
                        _ = speicher.sitzplaene.setzen(mitTisch, fuer: "k-1")
                        speicher.lernendenBlattOeffnen()
                        speicher.lernendenVorgabe?.ansicht = .alle
                        for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                        var gewaehlt: Lernendenbestand?
                        if let jetzt = speicher.lernende.bestand {
                            speicher.personLoeschenFragen(neuePerson, in: jetzt) { gewaehlt = $0 }
                        }
                        for _ in 0..<16 where Pruefstaende.alertfenster() == nil { await warten(125) }
                        // E894 (3), Z-AY6a-01: Keiner der beiden roten Knöpfe trägt ⏎ — eine bewusste Wahl, kein Enter.
                        @MainActor func knopf(_ titel: String) -> NSButton? {
                            Pruefstaende.alertfenster().flatMap { suchen($0.contentView, NSButton.self, { $0.title == titel }) }
                        }
                        @MainActor func tasteVon(_ titel: String) -> String? { knopf(titel)?.keyEquivalent }
                        let tasteMitTisch = tasteVon("Löschen und Tisch entfernen"), tasteNur = tasteVon("Löschen")
                        // E894 (2), (4), Z-AY6aN-04: „Löschen“ steht über dem dritten Knopf; beide tragen die Gefahr. Ist die
                        // Rückfrage breit — etwa mit dem Absatz über ältere Kopien, den die Saat in Fassung 1 auslöst —, stehen die
                        // Knöpfe nebeneinander, „Löschen und Tisch entfernen“ links von „Löschen“ (E1067).
                        if let k1 = knopf("Löschen"), let k2 = knopf("Löschen und Tisch entfernen") {
                            let r1 = k1.convert(k1.bounds, to: nil), r2 = k2.convert(k2.bounds, to: nil)
                            let nebeneinander = abs(r1.midY - r2.midY) < 2
                            let richtig: Bool = nebeneinander ? r2.maxX <= r1.minX : r1.minY > r2.minY
                            pruefen(richtig, nebeneinander
                                ? "AY6a: breit — „Löschen und Tisch entfernen“ links von „Löschen“ (E894, E1067)"
                                : "AY6a: „Löschen“ steht über „Löschen und Tisch entfernen“ (E894)")
                            pruefen(k1.hasDestructiveAction && k2.hasDestructiveAction,
                                    "AY6a: beide Knöpfe tragen die Gefahr (rot, E894) — Löschen \(k1.hasDestructiveAction), "
                                    + "mit Tisch \(k2.hasDestructiveAction)")
                        }
                        pruefen(tasteMitTisch != nil && tasteNur != nil && tasteMitTisch != "\r" && tasteNur != "\r",
                                "AY6a: Die Rückfrage trägt „Löschen und Tisch entfernen“ und „Löschen“ (E882 a, E894), ⏎ auf keinem "
                                + "der beiden — Tasten: \((tasteMitTisch ?? "—").debugDescription), \((tasteNur ?? "—").debugDescription)")
                        if let fehlt = await Pruefstaende.vonHandWeitere(speicher) { pruefen(false, "AY6a: Knopf „\(fehlt)“ im Alert gefunden") }
                        for _ in 0..<16 where gewaehlt == nil { await warten(125) }
                        if !(await blattSchliessen()) { zeilen.append("  Blatt nach AY6a nicht geschlossen") }
                        let uebernommen: Bool = gewaehlt.map { speicher.lernendenUebernehmen($0) == nil } ?? false
                        let danach: [Tisch] = speicher.sitzplan(fuer: "k-1")?.tische ?? []
                        let inDatei: Bool = gebundeneInDatei().map { !$0.contains(neuePerson) && $0.count == planVorher.tische.count } == true
                        let fort: Bool = speicher.lernende.bestand?.lernende.contains { $0.id == neuePerson } == false
                        pruefen(uebernommen && danach == planVorher.tische && inDatei && fort,
                                "AY6a: „Löschen und Tisch entfernen“ — der Tisch von Tim Tischfort ist fort, die "
                                + "\(planVorher.tische.count) übrigen stehen unverändert; sitzplaene.json trägt ihn nicht mehr (E884 b)")
                    } else {
                        pruefen(false, "Vorbedingung AY6a: Tim Tischfort angelegt")
                    }
                    // Was auch kam: Tim und sein Tisch sind danach fort — kein späterer Schritt soll sich verschieben (Z-AY6a-05,
                    // Z-AY6aN-02): die Person, und unabhängig davon ein Tisch, der noch steht.
                    if let neuePerson, let rest = speicher.lernende.bestand, rest.lernende.contains(where: { $0.id == neuePerson }) {
                        _ = speicher.lernendenUebernehmen(rest.ohnePerson(neuePerson).bestand.mitTischenFort([neuePerson], true))
                        zeilen.append("  AY6a: Tim Tischfort im Programm entfernt")
                    }
                    if var plan = speicher.sitzplan(fuer: "k-1"), plan.tische.contains(where: { $0.id == "t-tischfort" }) {
                        plan.tische.removeAll { $0.id == "t-tischfort" }
                        _ = speicher.sitzplaene.setzen(plan, fuer: "k-1")
                        zeilen.append("  AY6a: der Tisch „Tim Tischfort“ im Programm entfernt")
                    }
                } else {
                    pruefen(false, "Vorbedingung AY6a: Jahresdatei, eine Lerngruppe und der Sitzplan von k-1")
                }
                }
                await schrittTischEntfernen()
                @MainActor func schrittAuswahlfeld() async {
                // ── BC7 (W1-02, W1-03; N7-02, N7-03): das Auswahlfeld im Teil „Mitteilungen“. Gewählte, die die gezeigte
                // Mitteilung nicht betrifft, bleiben gewählt (E999); ein getippter, nicht bestätigter Tag — der Mitteilung
                // oder des Rücklaufs einer Person — wandert beim Wechsel nicht in die neu gewählte. Eine eigene Mitteilung
                // „Auswahlprobe“ an die aktiven Betroffenen der vollsten Mitteilung außer dem letzten, dazu ein Rücklauf der
                // ersten Person in beiden; danach wieder wie vorher — kein späterer Schritt verschiebt sich. Geschlossen wird
                // ohne Klick in eine Rückfrage: ⌘Z bis zum Stand beim Öffnen, dann ⎋ (E995). ──
                guard let b = speicher.lernende.bestand, let g = b.lerngruppen.first?.id else {
                    pruefen(false, "Vorbedingung Auswahlfeld: Jahresdatei und Lerngruppe")
                    return
                }
                let aktive = Lernendenverzeichnis(b).mitglieder(g).map(\.id)
                // Die Mitteilung mit den meisten aktiven Betroffenen — wer später in die Lerngruppe kam, ist nie von selbst
                // betroffen (E1001).
                func betroffen(_ m: Anliegen) -> [String] { aktive.filter(Set(m.betroffene).contains) }
                let vorhandene = Lernendenverzeichnis(b).mitteilungen(der: g)
                let s = Zeitrechnung.jetztAlsZeitstempel()
                guard let voll = vorhandene.max(by: { betroffen($0).count < betroffen($1).count }),
                      betroffen(voll).count >= 3,
                      let neu = b.mitNeuemAnliegen(.mitteilung, titel: "Auswahlprobe", lerngruppe: g,
                                                   betroffene: Array(betroffen(voll).dropLast()), datum: Tag.heute.iso,
                                                   frist: "", jetzt: s) else {
                    pruefen(false, "Vorbedingung Auswahlfeld: eine Mitteilung mit drei aktiven Betroffenen, "
                                + "„Auswahlprobe“ angelegt")
                    return
                }
                let x = betroffen(voll)[0]
                // Ein Tag für die Rückläufe, den weder Tag noch Frist der Mitteilung tragen — die Suche greift sonst ihr Feld.
                let rueckTag = ["2026-10-20", "2026-10-21", "2026-10-22"].first { $0 != voll.datum && $0 != voll.frist } ?? ""
                // Ebenso der getippte Tag, den keines der Felder schon zeigt — sonst bliebe die Probe leer.
                let getipptTag = ["2026-10-03", "2026-10-04", "2026-10-05"]
                    .first { $0 != voll.datum && $0 != voll.frist && $0 != Tag.heute.iso }.flatMap { Tag(iso: $0)?.deutsch } ?? ""
                let vorherRueck = Lernendenverzeichnis(b).rueckmeldung(voll.id, x)
                let mitRueck = neu.bestand.mitRuecklauf(voll.id, x, stand: .erledigt, datum: rueckTag, notiz: "", jetzt: s)
                    .mitRuecklauf(neu.id, x, stand: .erledigt, datum: rueckTag, notiz: "", jetzt: s)
                guard speicher.lernendenUebernehmen(mitRueck) == nil else {
                    pruefen(false, "Vorbedingung Auswahlfeld: „Auswahlprobe“ und Rückläufe übernommen")
                    return
                }
                let zahl = betroffen(voll).count
                defer {
                    if var rest = speicher.lernende.bestand {
                        if rest.anliegen.contains(where: { $0.id == neu.id }) { rest = rest.ohneAnliegen(neu.id).bestand }
                        // Der Rücklauf der ersten Person wie vorher — „offen“ ohne Notiz nimmt ihn weg.
                        rest = rest.mitRuecklauf(voll.id, x, stand: vorherRueck?.stand ?? .offen, datum: vorherRueck?.datum ?? "",
                                                 notiz: vorherRueck?.notiz ?? "", jetzt: Zeitrechnung.jetztAlsZeitstempel())
                        _ = speicher.lernendenUebernehmen(rest)
                    }
                }
                let v = Lernendenverzeichnis(mitRueck)
                let ms = v.mitteilungen(der: g)
                guard let probe = ms.first(where: { $0.id == neu.id }) else {
                    pruefen(false, "Vorbedingung Auswahlfeld: „Auswahlprobe“ in der Lerngruppe")
                    return
                }
                speicher.lernendenBlattOeffnen(gruppe: g)
                speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                guard let blatt = hauptfenster()?.attachedSheet else {
                    pruefen(false, "Auswahlfeld: Blatt „Lernende“ offen")
                    return
                }
                blatt.makeKeyAndOrderFront(nil)
                let alle = ms.map(Ruecklaufliste.wahltitel)
                @MainActor func tabelle() -> NSTableView? {
                    suchen(blatt.contentView, NSTableView.self, { Lernendenprobe.istMitteilungstabelle($0) })
                }
                // Unter macOS 26 ein NSPopUpButton mit genau diesen Einträgen. Ohne ihn (macOS 27) nicht die ganze Frist warten —
                // zwei Sekunden nach der Tabelle genügen —, dann sein Menü wie von Hand über der Tabelle, erkannt an den
                // Einträgen (K2).
                var wahl: NSPopUpButton?
                var tabelleSeit: Int?
                var bisTakt = 0
                for takt in 0..<20 where wahl == nil {
                    bisTakt = takt
                    wahl = suchen(blatt.contentView, NSPopUpButton.self, { $0.itemTitles == alle })
                    if tabelleSeit == nil, tabelle() != nil { tabelleSeit = takt }
                    if wahl == nil, let ab = tabelleSeit, takt >= ab + 8 { break }
                    if wahl == nil { await warten(250) }
                }
                var wieVonHand = false
                if wahl == nil, let t = tabelle() {
                    let menue = await menueAmPunkt(blatt, Menueanker.auswahlfeld(t), passt: { $0 == alle })
                    wieVonHand = menue.gefunden
                    // Auch unter macOS 26 sichtbar, wenn der Schritt diesen Weg nimmt (R8d-06).
                    zeilen.append("  Auskunft: Auswahlfeld ohne NSPopUpButton (Tabelle ab Takt \(tabelleSeit.map(String.init) ?? "—"), "
                                  + "gesucht bis Takt \(bisTakt), je 250 ms) — "
                                  + (wieVonHand ? "Weg wie von Hand" : "kein passendes Menü über der Tabelle: "
                                     + menue.verlauf.joined(separator: "; ")))
                }
                /// Der Eintrag einer Mitteilung im Auswahlfeld nach dem jetzigen Stand. Wie von Hand verlässt ein Klick ein
                /// Datumsfeld, und ein dort getippter Tag gilt (W1-02) — der Eintrag trägt den Tag der Mitteilung und heißt dann
                /// anders.
                @MainActor func eintrag(_ m: Anliegen) -> String {
                    Ruecklaufliste.wahltitel(speicher.lernendenblattGriff?.aenderungen()?.anliegen.first { $0.id == m.id } ?? m)
                }
                /// Das Menü des Auswahlfelds: so viele Einträge wie Mitteilungen, darunter der gesuchte — auch wenn ein Eintrag
                /// beim Öffnen noch den Tag von vorher trägt.
                func istAuswahl(_ ziel: String) -> ([String]) -> Bool { { $0.count == alle.count && $0.contains(ziel) } }
                /// Wechselt das Auswahlfeld — `true`, wenn es die Mitteilung zeigt und die Tabelle ihre Zeilen hat (N7-03). Ohne
                /// NSPopUpButton wie von Hand: der Eintrag im Menü, danach sein Haken (K2).
                @MainActor func waehlen(_ m: Anliegen) async -> Bool {
                    let ziel = wahl == nil ? eintrag(m) : Ruecklaufliste.wahltitel(m)
                    if let wahl {
                        let stelle = wahl.indexOfItem(withTitle: ziel)
                        // Über den Eintrag des Menüs wie ein Klick — die Wahl hängt am Eintrag (Z-BC2N-01).
                        if stelle >= 0 { wahl.menu?.performActionForItem(at: stelle) }
                    } else if wieVonHand, let t = tabelle() {
                        _ = await menueAmPunkt(blatt, Menueanker.auswahlfeld(t), passt: istAuswahl(ziel),
                                               waehlen: eintragMitTitel(ziel))
                    } else {
                        return false
                    }
                    let soll = m.id == probe.id ? zahl - 1 : zahl
                    @MainActor func da() -> Bool {
                        (wahl.map { $0.titleOfSelectedItem == ziel } ?? true) && tabelle()?.numberOfRows == soll
                    }
                    for _ in 0..<16 where !da() { await warten(125) }
                    await warten(300)
                    guard wahl == nil, da(), let t = tabelle() else { return da() }
                    return await menueAmPunkt(blatt, Menueanker.auswahlfeld(t), passt: istAuswahl(ziel)).angehakt == [ziel]
                }
                /// Tippt `wert` ohne ⏎ in das Datumsfeld, das `steht` zeigt — `true`, wenn es danach im Feld steht.
                @MainActor func datumTippen(_ steht: String, _ wert: String) async -> Bool {
                    @MainActor func feldSuchen() -> NSTextField? {
                        suchen(blatt.contentView, NSTextField.self, {
                            $0.placeholderString == "TT.MM.JJJJ" && $0.isEnabled && $0.stringValue == steht
                        })
                    }
                    for _ in 0..<12 where feldSuchen() == nil { await warten(125) }
                    guard let feld = feldSuchen() else { return false }
                    blatt.makeFirstResponder(feld)
                    await warten(300)
                    feld.currentEditor()?.selectAll(nil)
                    tippen(wert, in: blatt)
                    await warten(300)
                    return (blatt.firstResponder as? NSTextView)?.string == wert
                }
                if wahl != nil || wieVonHand {
                    // W1-03 (E999): alle gewählt in der vollsten Mitteilung, dann die „Auswahlprobe“ ohne den letzten und zurück.
                    if await waehlen(voll), let t = tabelle() {
                        blatt.makeFirstResponder(t)
                        taste("a", code: 0, [.command], in: blatt)
                        for _ in 0..<12 where t.selectedRowIndexes.count != t.numberOfRows { await warten(100) }
                        let vorher = t.selectedRowIndexes.count
                        let hin = await waehlen(probe)
                        let dort = tabelle()?.selectedRowIndexes.count ?? -1
                        let zurueck = await waehlen(voll)
                        let wieder = tabelle()?.selectedRowIndexes.count ?? -1
                        pruefen(hin && zurueck && vorher == zahl && dort == zahl - 1 && wieder == zahl,
                                "Auswahlfeld: alle \(vorher) gewählt, „Auswahlprobe“ (\(hin ? "gezeigt" : "nicht gezeigt"), dort "
                                    + "\(dort) markiert) und zurück — wieder \(wieder) markiert (E999, W1-03)")
                    } else {
                        pruefen(false, "Auswahlfeld: „\(voll.titel)“ mit \(zahl) Zeilen gezeigt")
                    }
                    // W1-02 entfällt seit v96: Den Tag der Mitteilung ändert das Unterblatt „Einstellungen der Mitteilung“ auf
                    // einer Kopie (E1175) — unter der Tabelle steht kein Tagesfeld mehr, das beim Wechsel wandern könnte.
                    zeilen.append("  Auskunft: W1-02 entfällt — kein Tagesfeld der Mitteilung unter der Tabelle mehr (E1175)")
                    // E1020 (BC8a): Nach „alle gewählt“ (hier zurück auf der vollsten, E999) wählt ein Klick auf eine Zeile genau
                    // sie, mit ihrer Leiste. SwiftUIs Tabelle leerte die ganze Auswahl; die AppKit-Hülle wählt wie AppKit, und zwar
                    // vor der halben Doppelklickzeit (E1029) — in einer Tabelle mit Kopf, an dem der Treffertest des Monitors
                    // vorbeimuss (Z-BC8a-03).
                    if await waehlen(voll), let t = tabelle(), t.numberOfRows >= 2 {
                        let vorher = t.selectedRowIndexes.count
                        let r = t.rect(ofRow: 1)
                        await klicken(t.convert(NSPoint(x: r.midX, y: r.midY), to: nil), in: blatt, halten: 0)
                        let frist = Int(NSEvent.doubleClickInterval * 500)
                        for _ in 0..<(frist / 50) where t.selectedRowIndexes != IndexSet([1]) { await warten(50) }
                        let sofort = t.selectedRowIndexes == IndexSet([1])
                        for _ in 0..<12 where t.selectedRowIndexes != IndexSet([1]) { await warten(125) }
                        await warten(300)
                        let leiste = suchen(blatt.contentView, NSSegmentedControl.self, {
                            $0.segmentCount == 3 && $0.label(forSegment: 0) == "offen"
                        }) != nil
                        pruefen(vorher == t.numberOfRows && sofort && t.selectedRowIndexes == IndexSet([1]) && leiste,
                                "Mitteilungstabelle: alle \(vorher) gewählt, Klick auf Zeile 2 — "
                                    + (sofort ? "vor \(frist) ms gewählt" : "nicht vor \(frist) ms gewählt") + ", danach "
                                    + Array(t.selectedRowIndexes).prefix(4).map { "\($0 + 1)" }.joined(separator: ", ")
                                    + ", Leiste \(leiste ? "da" : "fehlt") (E1020, E1029)")
                    } else {
                        pruefen(false, "Mitteilungstabelle: „\(voll.titel)“ für den Klick nach ⌘A (E1020)")
                    }
                    // E280, E1029: Das Menü „Stand“ in der Zelle einer von mehreren Gewählten geht auf, und die Auswahl bleibt — die
                    // Spalte trägt eine Steuerung und ist von der Wahl beim Loslassen ausgenommen. Erst ⌘A (der Fall davor ließ eine
                    // gewählt), dann ein Klick auf das Wort der Marke — 14 pt traf die Lücke zwischen Symbol und Wort, und der Klick
                    // ging an die Tabelle; drei Punkte über `menueAmPunkt`. Geschlossen wird ohne Wahl. Trug nicht der erste Punkt,
                    // nennt eine Auskunft, was die Klicks trafen.
                    if let t = tabelle(), t.numberOfRows >= 2,
                       let spalte = t.tableColumns.firstIndex(where: { $0.title == Mitteilungstext.spalteStand }) {
                        taste("a", code: 0, [.command], in: blatt)
                        for _ in 0..<12 where t.selectedRowIndexes.count != t.numberOfRows { await warten(100) }
                        let vorher = t.selectedRowIndexes.count
                        if vorher != t.numberOfRows {
                            let erster = blatt.firstResponder.map { String(describing: type(of: $0)) } ?? "keiner"
                            zeilen.append("  Auskunft: ⌘A wählte \(vorher) von \(t.numberOfRows) — Tastaturfokus \(erster), Tabelle im Blatt "
                                          + "\(t.window === blatt ? "ja" : "nein"), dieselbe wie gesucht \(tabelle() === t ? "ja" : "nein")")
                        }
                        let zelle = t.frameOfCell(atColumn: spalte, row: 1)
                        let staende = Rueckmeldestand.allCases.map { $0.beschriftung(fuer: .mitteilung) }
                        let abstaende = [30, 22, 8]
                        let punkte = abstaende.map { t.convert(NSPoint(x: zelle.minX + CGFloat($0), y: zelle.midY), to: nil) }
                        // Was unter den Punkten liegt — für die Auskunft, wenn nicht der erste trägt.
                        let getroffen = punkte.map { p in
                            blatt.contentView?.superview?.hitTest(p).map { String(describing: type(of: $0)) } ?? "nichts"
                        }
                        // Vor jedem weiteren Punkt wieder alle: Ein Fehlversuch traf die Zeile, und AppKit wählte sie (R8a-06).
                        let standmenue = await menueAmPunkt(blatt, punkte, passt: { $0 == staende }, vorJedemWeiteren: {
                            taste("a", code: 0, [.command], in: blatt)
                            for _ in 0..<12 where t.selectedRowIndexes.count != t.numberOfRows { await warten(100) }
                        })
                        let eintraege = standmenue.eintraege
                        // Hätte die Tabelle den Klick bekommen, käme AppKits Wahl nach der Doppelklickzeit jetzt: bis über sie hinaus.
                        await warten(Int(NSEvent.doubleClickInterval * 1000) + 250)
                        let leiste = suchen(blatt.contentView, NSSegmentedControl.self, {
                            $0.segmentCount == 3 && $0.label(forSegment: 0) == "offen"
                        }) != nil
                        if standmenue.punkt != 0 {
                            zeilen.append("  Auskunft: Menü „Stand“ — " + standmenue.verlauf.joined(separator: "; ") + "; getroffen "
                                          + zip(abstaende, getroffen).map { "+\($0) pt: \($1)" }.joined(separator: "; "))
                        }
                        pruefen(vorher == t.numberOfRows && standmenue.gefunden && eintraege == staende
                                    && t.selectedRowIndexes.count == t.numberOfRows && !leiste,
                                "Mitteilungstabelle: alle \(vorher) gewählt, Menü „Stand“ in Zeile 2 — "
                                    + (eintraege.isEmpty ? "kein Menü" : "Menü " + eintraege.joined(separator: ", "))
                                    + ", danach \(t.selectedRowIndexes.count) gewählt" + (leiste ? ", Leiste einer Person" : "")
                                    + " (E280, E1029)")
                    } else {
                        pruefen(false, "Mitteilungstabelle: Spalte „\(Mitteilungstext.spalteStand)“ für das Menü (E1029)")
                    }
                } else {
                    pruefen(false, "Auswahlfeld mit den Mitteilungen der ersten Lerngruppe gefunden (\(alle.count))")
                }
                // Schließen ohne Klick in eine Rückfrage (E995): ⌘Z bis zum Stand beim Öffnen, dann ⎋.
                blatt.makeFirstResponder(nil)
                for _ in 0..<4 where speicher.lernendenblattGriff?.aenderungen() != nil {
                    taste("z", code: 6, [.command], in: blatt)
                    await warten(400)
                }
                taste("\u{1B}", code: 53, in: blatt)
                for _ in 0..<12 where hauptfenster()?.attachedSheet != nil && Pruefstaende.alertfenster() == nil {
                    await warten(250)
                }
                if hauptfenster()?.attachedSheet != nil, !(await blattSchliessen()) {
                    zeilen.append("  Auswahlfeld: Blatt nicht geschlossen")
                }
                // N7-02: der Tag des Rücklaufs der ersten Person, getippt ohne ⏎, dann Wechsel — ihr Rücklauf in der
                // „Auswahlprobe“ behält seinen Tag. Ein eigenes Blatt, geöffnet auf die vollste Mitteilung und die Person: Ihre
                // Leiste steht ohne Zeilenwahl (nach ⌘A ließ die Wahl einer Zeile in zwei Läufen keine Leiste stehen).
                speicher.lernendenBlattOeffnen(gruppe: g)
                speicher.lernendenVorgabe?.gruppenteil = .mitteilungen
                speicher.lernendenVorgabe?.anliegen = voll.id
                speicher.lernendenVorgabe?.person = x
                for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                if let blatt2 = hauptfenster()?.attachedSheet {
                    blatt2.makeKeyAndOrderFront(nil)
                    let tagR = Tag(iso: rueckTag)?.deutsch ?? ""
                    @MainActor func feldR() -> NSTextField? {
                        suchen(blatt2.contentView, NSTextField.self, {
                            $0.placeholderString == "TT.MM.JJJJ" && $0.isEnabled && $0.stringValue == tagR
                        })
                    }
                    for _ in 0..<20 where feldR() == nil { await warten(250) }
                    let schritteVorR = speicher.lernendenverlauf.zurueck.count
                    let vorR = speicher.lernendenblattGriff?.aenderungen() ?? speicher.lernendenblattGriff?.ausgang()
                    var getipptR = false
                    if let feld = feldR() {
                        blatt2.makeFirstResponder(feld)
                        await warten(300)
                        feld.currentEditor()?.selectAll(nil)
                        tippen(getipptTag, in: blatt2)
                        await warten(300)
                        getipptR = (blatt2.firstResponder as? NSTextView)?.string == getipptTag
                    }
                    let wahl2 = suchen(blatt2.contentView, NSPopUpButton.self, { $0.itemTitles == alle })
                    let ziel = Ruecklaufliste.wahltitel(probe)
                    var hinR = false
                    if wahl2 != nil || !wieVonHand {
                        if let stelle = wahl2?.indexOfItem(withTitle: ziel), stelle >= 0 {
                            wahl2?.menu?.performActionForItem(at: stelle)
                        }
                        for _ in 0..<16 where wahl2?.titleOfSelectedItem != ziel { await warten(125) }
                        hinR = wahl2?.titleOfSelectedItem == ziel
                    } else if let t = suchen(blatt2.contentView, NSTableView.self, { Lernendenprobe.istMitteilungstabelle($0) }) {
                        // Ohne NSPopUpButton wie von Hand: ein Klick über die Tabelle, der Eintrag im Menü, danach sein Haken (K2).
                        _ = await menueAmPunkt(blatt2, Menueanker.auswahlfeld(t), passt: { $0 == alle },
                                               waehlen: eintragMitTitel(ziel))
                        // Bis die Tabelle die Zeilen der neu gewählten zeigt (U2-06).
                        @MainActor func zeilenR() -> Int {
                            let tabelleR = suchen(blatt2.contentView, NSTableView.self, { Lernendenprobe.istMitteilungstabelle($0) })
                            return tabelleR?.numberOfRows ?? -1
                        }
                        for _ in 0..<16 where zeilenR() != zahl - 1 { await warten(125) }
                        let tR = suchen(blatt2.contentView, NSTableView.self, { Lernendenprobe.istMitteilungstabelle($0) }) ?? t
                        hinR = await menueAmPunkt(blatt2, Menueanker.auswahlfeld(tR), passt: { $0 == alle }).angehakt == [ziel]
                    }
                    blatt2.makeFirstResponder(nil)
                    await warten(600)
                    if wahl2 != nil || !wieVonHand {
                        let unveraendertR = speicher.lernendenblattGriff?.aenderungen() == nil
                        pruefen(getipptR && hinR && unveraendertR,
                                "Tag des Rücklaufs „\(getipptTag)“ getippt ohne ⏎ (\(getipptR ? "im Feld" : "nicht im Feld")), "
                                    + "Wechsel (\(hinR ? "gelungen" : "nicht gelungen")): nichts geschrieben "
                                    + "(\(unveraendertR ? "ja" : "nein"); N7-02)")
                    } else {
                        // Wie W1-02 von Hand (E1017): Der getippte Tag gilt für den bisherigen Rücklauf, ein Schritt. Der Rücklauf
                        // in der neu gewählten bleibt ganz, der Rest ohne Zeitstempel ebenso.
                        let nachR = speicher.lernendenblattGriff?.aenderungen() ?? speicher.lernendenblattGriff?.ausgang()
                        let vVor = vorR.map { Lernendenverzeichnis($0) }
                        let vNach = nachR.map { Lernendenverzeichnis($0) }
                        let tagVorherR = vVor?.rueckmeldung(voll.id, x)?.datum ?? rueckTag
                        let rueckBisher = vNach?.rueckmeldung(voll.id, x)?.datum ?? "fehlt"
                        let neuGleichR = vNach?.rueckmeldung(probe.id, x) == vVor?.rueckmeldung(probe.id, x)
                        let restGleichR = vergleichsstand(nachR, ohneRuecklauf: (voll.id, x))
                            == vergleichsstand(vorR, ohneRuecklauf: (voll.id, x))
                        let getipptIsoR = Tag(deutsch: getipptTag)?.iso
                        let schritteR = speicher.lernendenverlauf.zurueck.count - schritteVorR
                        let geaendertR = rueckBisher != tagVorherR
                        let bisherWieR = rueckBisher == getipptIsoR ? "der getippte" : !geaendertR ? "ihr" : "ein anderer"
                        pruefen(getipptR && hinR && neuGleichR && restGleichR && geaendertR && rueckBisher == getipptIsoR
                                    && schritteR == 1,
                                "Tag des Rücklaufs „\(getipptTag)“ getippt ohne ⏎ (\(getipptR ? "im Feld" : "nicht im Feld")), "
                                    + "Wechsel wie von Hand (\(hinR ? "gelungen" : "nicht gelungen")): in der neu gewählten "
                                    + (neuGleichR ? "unverändert" : "geändert") + ", in der bisherigen \(bisherWieR) Tag "
                                    + "\(rueckBisher), sonst \(restGleichR ? "nichts" : "mehr") geändert; \(schritteR) Schritt "
                                    + "(N7-02, K2)")
                    }
                    for _ in 0..<4 where speicher.lernendenblattGriff?.aenderungen() != nil {
                        taste("z", code: 6, [.command], in: blatt2)
                        await warten(400)
                    }
                    taste("\u{1B}", code: 53, in: blatt2)
                    for _ in 0..<12 where hauptfenster()?.attachedSheet != nil && Pruefstaende.alertfenster() == nil {
                        await warten(250)
                    }
                    if hauptfenster()?.attachedSheet != nil, !(await blattSchliessen()) {
                        zeilen.append("  Tag des Rücklaufs: Blatt nicht geschlossen")
                    }
                } else {
                    pruefen(false, "Tag des Rücklaufs: Blatt „Lernende“ offen")
                }
                }
                await schrittAuswahlfeld()
                @MainActor func schrittGruppenwechselLeiste() async {
                // ── BC7b: Maßnahmen und Vereinbarungen gelten je Person — wer in zwei Lerngruppen steht, hat seine Zeile in
                // beiden Tabellen. Gewählt ist eine solche Zeile mit Notiz bzw. Inhalt; ein Klick auf die andere Lerngruppe
                // darf nichts ändern (W1-01, BC7b-00). Dazu eine Person nur der ersten Lerngruppe mit Notiz bzw. Inhalt, ohne ⏎
                // getippt: Beim Wechsel wird genau das Getippte übernommen (N7-05) — steht die Person in beiden, übernimmt es
                // schon der Fokuswechsel. Eigene Einträge, danach wieder fort; geschlossen mit ⌘Z und ⎋ (E995). ──
                guard let b = speicher.lernende.bestand else {
                    pruefen(false, "Vorbedingung Gruppenwechsel: Jahresdatei")
                    return
                }
                let v = Lernendenverzeichnis(b)
                let liste = Lernendenblatt.gruppenliste(b, archivierte: false, suche: "")
                var paar: (g1: String, g2: String, p: String, q: String)?
                suche: for g1 in liste {
                    for g2 in liste where g2.id != g1.id {
                        let zweite = Set(v.mitglieder(g2.id).map(\.id))
                        let erste = v.mitglieder(g1.id)
                        if let p = erste.first(where: { zweite.contains($0.id) }),
                           let q = erste.first(where: { !zweite.contains($0.id) }) {
                            paar = (g1.id, g2.id, p.id, q.id)
                            break suche
                        }
                    }
                }
                let s = Zeitrechnung.jetztAlsZeitstempel()
                guard let (g1, g2, p, q) = paar,
                      let mass = b.mitNeuemAnliegen(.massnahme, titel: "Leistenprobe Maßnahme", lerngruppe: g1, betroffene: [p],
                                                    datum: Tag.heute.iso, frist: Tag.heute.plus(tage: 7).iso, jetzt: s),
                      let ver = mass.bestand.mitRuecklauf(mass.id, p, stand: .offen, datum: "", notiz: "Notizprobe", jetzt: s)
                          .mitNeuemAnliegen(.vereinbarung, titel: "Leistenprobe Vereinbarung", lerngruppe: g1, betroffene: [p],
                                            datum: Tag.heute.iso, frist: "", jetzt: s) else {
                    pruefen(false, "Vorbedingung Gruppenwechsel: eine Person in zwei Lerngruppen, eine nur in der ersten, "
                                + "Maßnahme und Vereinbarung")
                    return
                }
                let mitInhalt = ver.bestand.mitAnliegen(ver.id, titel: "Leistenprobe Vereinbarung", datum: Tag.heute.iso, frist: "",
                                                        notiz: "Inhaltprobe", jetzt: s)
                guard let mass2 = mitInhalt.mitNeuemAnliegen(.massnahme, titel: "Leistenprobe Maßnahme 2", lerngruppe: g1,
                                                             betroffene: [q], datum: Tag.heute.iso,
                                                             frist: Tag.heute.plus(tage: 7).iso, jetzt: s),
                      let ver2 = mass2.bestand.mitRuecklauf(mass2.id, q, stand: .offen, datum: "", notiz: "Notizprobe", jetzt: s)
                          .mitNeuemAnliegen(.vereinbarung, titel: "Leistenprobe Vereinbarung 2", lerngruppe: g1,
                                            betroffene: [q], datum: Tag.heute.iso, frist: "", jetzt: s) else {
                    pruefen(false, "Vorbedingung Gruppenwechsel: Maßnahme und Vereinbarung der Person nur der ersten Lerngruppe")
                    return
                }
                let alles = ver2.bestand.mitAnliegen(ver2.id, titel: "Leistenprobe Vereinbarung 2", datum: Tag.heute.iso,
                                                     frist: "", notiz: "Inhaltprobe", jetzt: s)
                guard speicher.lernendenUebernehmen(alles) == nil else {
                    pruefen(false, "Vorbedingung Gruppenwechsel: Einträge übernommen")
                    return
                }
                defer {
                    if var rest = speicher.lernende.bestand {
                        for id in [mass.id, ver.id, mass2.id, ver2.id] where rest.anliegen.contains(where: { $0.id == id }) {
                            rest = rest.ohneAnliegen(id).bestand
                        }
                        _ = speicher.lernendenUebernehmen(rest)
                    }
                }
                let zielzeile = liste.firstIndex { $0.id == g2 } ?? -1
                // Ohne Tippen nichts geändert (BC7b-00); mit Tippen ohne ⏎ genau das Getippte (N7-05).
                let faelle: [(Gruppenteil, String, String, String, String?)] = [
                    (.massnahmen, mass.id, p, "Maßnahme mit Notiz", nil),
                    (.vereinbarungen, ver.id, p, "Vereinbarung mit Inhalt", nil),
                    (.massnahmen, mass2.id, q, "Maßnahme, Notiz getippt", "Notizneu"),
                    (.vereinbarungen, ver2.id, q, "Vereinbarung, Inhalt getippt", "Inhaltneu")]
                for (teil, anliegen, person, name, getippt) in faelle {
                    let (mid, vid) = person == p ? (mass.id, ver.id) : (mass2.id, ver2.id)
                    speicher.lernendenBlattOeffnen(gruppe: g1)
                    speicher.lernendenVorgabe?.gruppenteil = teil
                    speicher.lernendenVorgabe?.anliegen = anliegen
                    speicher.lernendenVorgabe?.person = person
                    for _ in 0..<20 where hauptfenster()?.attachedSheet == nil { await warten(250) }
                    guard let blatt = hauptfenster()?.attachedSheet else {
                        pruefen(false, "Gruppenwechsel: Blatt „Lernende“ offen (\(name))")
                        continue
                    }
                    blatt.makeKeyAndOrderFront(nil)
                    await warten(800)
                    var tabellen: [NSTableView] = []
                    @MainActor func sammeln(_ a: NSView) {
                        if let t = a as? NSTableView, !t.isHiddenOrHasHiddenAncestor { tabellen.append(t) }
                        a.subviews.forEach(sammeln)
                    }
                    if let inhalt = blatt.contentView { sammeln(inhalt) }
                    let links = tabellen.min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
                    var imFeld = true
                    if let getippt {
                        let vorher = teil == .massnahmen ? "Notizprobe" : "Inhaltprobe"
                        if let feld = suchen(blatt.contentView, NSTextField.self, { $0.isEditable && $0.stringValue == vorher }) {
                            blatt.makeFirstResponder(feld)
                            await warten(300)
                            feld.currentEditor()?.selectAll(nil)
                            tippen(getippt, in: blatt)
                            await warten(400)
                        }
                        imFeld = (blatt.firstResponder as? NSTextView)?.string == getippt
                    }
                    let schritte = speicher.lernendenverlauf.zurueck.count
                    if let links, zielzeile >= 0, zielzeile < links.numberOfRows {
                        let r = links.rect(ofRow: zielzeile)
                        let punkt = links.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
                        for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                            if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                                 windowNumber: blatt.windowNumber, context: nil, eventNumber: 0,
                                                                 clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                                NSApp.postEvent(ereignis, atStart: false)
                            }
                        }
                        for _ in 0..<12 where links.selectedRow != zielzeile { await warten(125) }
                        await warten(1000)
                        let geaendert = speicher.lernendenblattGriff?.aenderungen()
                        let notiz = geaendert.flatMap { e in Lernendenverzeichnis(e).rueckmeldung(mid, person)?.notiz }
                        let inhalt = geaendert?.anliegen.first { $0.id == vid }?.notiz
                        let gut = getippt.map { imFeld && (teil == .massnahmen ? notiz : inhalt) == $0 } ?? (geaendert == nil)
                        pruefen(links.selectedRow == zielzeile && gut,
                                "Gruppenwechsel mit gewählter \(name): "
                                    + (getippt.map { "„\($0)“ übernommen\(imFeld ? "" : " (nicht im Feld)")" } ?? "nichts geändert")
                                    + " — Schritte \(schritte) → \(speicher.lernendenverlauf.zurueck.count), Notiz "
                                    + "„\(notiz ?? "unverändert")“, Inhalt „\(inhalt ?? "unverändert")“ "
                                    + "(\(getippt == nil ? "W1-01, BC7b-00" : "N7-05"))")
                    } else {
                        pruefen(false, "Gruppenwechsel: Gruppenliste mit der zweiten Lerngruppe (\(name))")
                    }
                    blatt.makeFirstResponder(nil)
                    for _ in 0..<4 where speicher.lernendenblattGriff?.aenderungen() != nil {
                        taste("z", code: 6, [.command], in: blatt)
                        await warten(400)
                    }
                    taste("\u{1B}", code: 53, in: blatt)
                    for _ in 0..<12 where hauptfenster()?.attachedSheet != nil && Pruefstaende.alertfenster() == nil {
                        await warten(250)
                    }
                    if hauptfenster()?.attachedSheet != nil, !(await blattSchliessen()) {
                        zeilen.append("  Gruppenwechsel: Blatt nicht geschlossen (\(name))")
                    }
                }
                }
                await schrittGruppenwechselLeiste()
                @MainActor func schrittImportJeKlasse() async {
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
                }
                await schrittImportJeKlasse()
                @MainActor func schrittVerlustfrage() async {
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
                }
                await schrittVerlustfrage()
                @MainActor func schrittSchluss() async {
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
                await schrittSchluss()
            }
            await ende()
        }
    }

    /// Die Köpfe der Tabelle einer Mitteilung (v91, BC2, V3) — wie bei den Maßnahmen.
    static let mitteilungsspalten = [Mitteilungstext.spaltePerson, Mitteilungstext.spalteMitteilung,
                                     Mitteilungstext.spalteFrist, Mitteilungstext.spalteStand]

    /// ⌘Q bei offenem Unterblatt (v96, BH5, R-BH5-01, R-BH5-02): Es zählt als Bogen auf dem Blatt (⌘Z prallt daran ab,
    /// G2-07), „Den offenen Bogen verwerfen?“ steht auf ihm; „Weiter bearbeiten“ wie von Hand — danach steht es noch.
    /// `nil`, wenn alles stimmt, sonst der Befund. Ohne Bogen wird nicht beendet: Die App ginge sonst mitten im Lauf.
    /// Gewartet wird mit dem `warten` des Laufs — kein eigener Zeitgeber (E561).
    @MainActor static func unterblattBeimBeenden(_ speicher: Planungsspeicher, _ unter: NSWindow,
                                                warten: (Int) async -> Void) async -> String? {
        guard speicher.lernendenblattGriff?.bogenOffen() == true else { return "es zählt nicht als Bogen auf dem Blatt" }
        speicher.beenden()
        for _ in 0..<16 where Planungsspeicher.alertfenster() == nil { await warten(125) }
        let frage = speicher.rueckfrage
        let amUnterblatt = unter.attachedSheet.map(Planungsspeicher.istAlert) == true
        let fehlt = await Pruefstaende.vonHandAntworten(speicher, false)
        for _ in 0..<16 where speicher.rueckfrage != nil { await warten(125) }
        // Die Lücke nach der Antwort abwarten, ehe der Lauf weitertippt (E436).
        for _ in 0..<16 where speicher.frageSperrtBefehl() { await warten(125) }
        guard frage?.ort == .bogen, frage?.text == "Den offenen Bogen verwerfen?" else {
            return "keine Frage am Bogen („\(frage?.text ?? "keine")“)"
        }
        if let fehlt { return "Knopf „\(fehlt)“ in keinem Alert" }
        guard amUnterblatt else { return "die Frage steht nicht auf dem Unterblatt" }
        guard unter.isVisible, speicher.lernendenblattGriff?.bogenOffen() == true else {
            return "nach „Weiter bearbeiten“ ist das Unterblatt fort"
        }
        return nil
    }

    /// Die Tabelle der gewählten Mitteilung im Teil „Mitteilungen“ (v91, BC2): vorn „Person“, dann „Mitteilung“ — die
    /// Maßnahmen tragen dort „Maßnahme“, die Vereinbarungen „Vereinbarung“.
    static func istMitteilungstabelle(_ t: NSTableView) -> Bool {
        t.numberOfColumns >= 2 && t.tableColumns[0].title.hasPrefix(Mitteilungstext.spaltePerson)
            && t.tableColumns[1].title == Mitteilungstext.spalteMitteilung
    }

    /// Die Namen der Elemente der Bedienungshilfen unter `inhalt` — Titel, Beschriftung und Wert, jeder nicht leere.
    ///
    /// Unter macOS 27 zeichnet SwiftUI manche Steuerelemente selbst, das Menü der Sammelleiste etwa. Sein Titel steht dann
    /// an einem Knoten von SwiftUI, der sich nicht als `NSAccessibilityProtocol` ansprechen lässt: Rolle „statischer Text“,
    /// der Titel als Wert (Diagnose in der VM 27.2, E941). Läuft eine Bedienungshilfe wie VoiceOver, ist es eine Menü-Taste,
    /// der Titel formatierter Text (E942/E943). Solche Knoten liest die Probe über ihre Selektoren.
    static func bedienungshilfenNamen(_ inhalt: NSView?) -> [String] {
        var liste: [String] = []
        if let inhalt { namenSammeln(inhalt, 0, &liste) }
        return liste
    }

    private static func namenSammeln(_ element: Any, _ tiefe: Int, _ liste: inout [String]) {
        guard tiefe < 40 else { return }
        guard let e = element as? NSAccessibilityProtocol else {
            guard let knoten = element as? NSObject else { return }
            let selektoren: [String] = ["accessibilityTitle", "accessibilityLabel", "accessibilityValue"]
            for selektor in selektoren {
                if let text = bedienungshilfentext(bedienungshilfe(knoten, selektor)), !text.isEmpty { liste.append(text) }
            }
            let kinder: [Any] = (bedienungshilfe(knoten, "accessibilityChildren") as? [Any]) ?? []
            for kind in kinder where !(kind is NSView) { namenSammeln(kind, tiefe + 1, &liste) }
            return
        }
        for name in [e.accessibilityTitle(), e.accessibilityLabel(), bedienungshilfentext(e.accessibilityValue())] {
            if let name, !name.isEmpty { liste.append(name) }
        }
        if let ansicht = e as? NSView { for kind in ansicht.subviews { namenSammeln(kind, tiefe + 1, &liste) } }
        for kind in e.accessibilityChildren() ?? [] where !(kind is NSView) { namenSammeln(kind, tiefe + 1, &liste) }
    }

    /// Ein Text der Bedienungshilfen: eine Zeichenkette oder formatierter Text — so trägt das Menü unter macOS 27 seinen
    /// Titel, wenn eine Bedienungshilfe läuft (Diagnose in der VM 27.2 mit VoiceOver, E942/E943).
    private static func bedienungshilfentext(_ wert: Any?) -> String? {
        if let text = wert as? String { return text }
        if let formatiert = wert as? NSAttributedString { return formatiert.string }
        return nil
    }

    /// Eine Eigenschaft der Bedienungshilfen über ihren Selektor — `nil`, wenn der Knoten ihn nicht kennt oder die Methode
    /// dieses Namens an seiner Klasse kein Objekt zurückgibt: `perform` läse eine Zahl als Zeiger (Z-AZ6a-04). Leitet er
    /// weiter, folgt die Probe dem Ziel und prüft dort (Z-AZ6aN-01, Z-AZ6aN2-02) — bis zu vier Weiterleitungen; eine längere
    /// Kette oder ein Ziel, das kein NSObject ist, bringt keinen Namen (Z-AZ6aN3-01). Nur was allein über
    /// `forwardInvocation:` antwortet, nimmt sie nach dem Vertrag der Bedienungshilfen als Objekt. Unter macOS 26 kennt
    /// der Knoten von SwiftUI `accessibilityTitle` nicht, unter macOS 27 antwortet er darauf — wie, ist offen.
    private static func bedienungshilfe(_ knoten: NSObject, _ selektor: String, _ stufe: Int = 0) -> AnyObject? {
        let wahl = NSSelectorFromString(selektor)
        if let methode = class_getInstanceMethod(object_getClass(knoten), wahl) {
            let art = method_copyReturnType(methode)
            defer { free(art) }
            guard knoten.responds(to: wahl), art.pointee == CChar(UInt8(ascii: "@")) else { return nil }
            return knoten.perform(wahl)?.takeUnretainedValue()
        }
        if let weiter = knoten.forwardingTarget(for: wahl), (weiter as AnyObject) !== knoten {
            guard stufe < 4, let ziel = weiter as? NSObject else { return nil }
            return bedienungshilfe(ziel, selektor, stufe + 1)
        }
        guard knoten.responds(to: wahl) else { return nil }
        return knoten.perform(wahl)?.takeUnretainedValue()
    }
}

/// Was ein Klick an Menü zutage brachte — Einträge, Haken, geschlossen (B83).
@MainActor
private final class Menuefang {
    var titel: [String] = []
    var angehakt: [String] = []
    var zu = false
    /// Das Menü selbst — falls es offen bliebe, wird es ohne Wahl geschlossen (Z14f-11).
    var menue: NSMenu?
    /// Für `menueAmPunkt`: ob das Menü das gesuchte ist (an seinen Einträgen ohne die leeren), welcher Eintrag zu wählen ist
    /// (im Menü selbst oder in einem Untermenü), was dabei geschah, und ob der Punkt schon vorbei ist.
    var passt: ([String]) -> Bool = { _ in true }
    var wahl: (@MainActor (NSMenu) -> (menue: NSMenu, stelle: Int)?)?
    var passend = false
    var gewaehlt: String?
    var abgelaufen = false

    /// Das erste Menü, das aufgeht: lesen, gegebenenfalls wählen, schließen — im nächsten Durchlauf, denn das Menü läuft in
    /// seinem eigenen Modus. Gewählt wird der Eintrag selbst, wieder gesucht im Menü; nach dem Ende des Punkts nichts mehr.
    func geoeffnet(_ menue: NSMenu) {
        guard self.menue == nil else { return }
        self.menue = menue
        titel = menue.items.map(\.title)
        angehakt = menue.items.filter { $0.state == .on }.map(\.title)
        passend = passt(titel.filter { !$0.isEmpty })
        let ziel = passend ? wahl?(menue) : nil
        nonisolated(unsafe) let offen = menue
        nonisolated(unsafe) let unter = ziel?.menue
        nonisolated(unsafe) let eintrag = ziel.flatMap { z in z.stelle < z.menue.numberOfItems ? z.menue.item(at: z.stelle) : nil }
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                if !self.abgelaufen, let unter, let eintrag {
                    let stelle = unter.index(of: eintrag)
                    if stelle >= 0 {
                        self.gewaehlt = eintrag.title
                        unter.performActionForItem(at: stelle)
                    }
                }
                offen.cancelTracking()
            }
        }
    }
}

/// Was `menueAmPunkt` fängt, über die ganze Dauer eines Aufrufs: das Menü des laufenden Punkts und jedes spätere.
@MainActor
private final class Menuewache {
    var fang: Menuefang?
    var spaet: [String] = []
}

/// Was `menueAmPunkt` fand.
private struct Menuewahl {
    /// Einträge und Haken des Menüs, das aufging und passte — leer, wenn keins passte.
    var titel: [String] = []
    var angehakt: [String] = []
    /// Der Punkt (ab 0), an dem es aufging; `nil`: an keinem.
    var punkt: Int?
    /// Der Eintrag, der gewählt wurde.
    var gewaehlt: String?
    /// Das Menü blieb offen und wurde ohne Wahl geschlossen.
    var bliebOffen = false
    /// Die Reihe hielt an, weil ein Klick ohne Menü einen Bogen öffnete oder einen Schritt auslöste.
    var halt = false
    /// Ging an irgendeinem Punkt ein Menü auf, auch eins, das nicht passte?
    var menueGesehen = false
    /// Je Punkt, was geschah — für Auskünfte.
    var verlauf: [String] = []
    var gefunden: Bool { punkt != nil }
    var eintraege: [String] { titel.filter { !$0.isEmpty } }
}

/// Die einzige Wartestelle der Helfer hier — eine Uhr (E595).
private func ruhen(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

/// Ein SwiftUI-Auswahlfeld oder -Menü wie von Hand (K2, E1019). Unter macOS 27 hat es keine eigene AppKit-Ansicht; die Probe
/// klickt dorthin, wo es neben einer AppKit-Ansicht steht (`Menueanker`) — an den Punkten nacheinander, im System des
/// Fensters, bis ein Menü aufgeht, das `passt`. Gelesen werden Einträge und Haken; `waehlen` nennt den Eintrag, sonst
/// schließt es ohne Wahl (`cancelTracking`). Ein Menü, das nicht passt, schließt ebenso, und der nächste Punkt folgt; vor
/// ihm läuft `vorJedemWeiteren`. Ging an einem Punkt kein Menü auf und hängt danach ein Bogen am Fenster oder gilt `halt`
/// (etwa: ein Schritt mehr — der Klick traf einen Knopf daneben), klickt die Probe nicht weiter (`halt`). Mit
/// `einMenueGenuegt` endet die Reihe auch an einem Menü, das nicht passt. Ein Menü, das erst nach seinem Punkt aufgeht,
/// schließt die Wache und vermerkt es. Unter macOS 26 trifft derselbe Klick den NSPopUpButton.
@MainActor private func menueAmPunkt(_ fenster: NSWindow, _ punkte: [NSPoint], passt: @escaping ([String]) -> Bool = { _ in true },
                                     waehlen: (@MainActor (NSMenu) -> (menue: NSMenu, stelle: Int)?)? = nil,
                                     halt: () -> Bool = { false }, einMenueGenuegt: Bool = false,
                                     vorJedemWeiteren: (@MainActor () async -> Void)? = nil) async -> Menuewahl {
    var ergebnis = Menuewahl()
    let wache = Menuewache()
    // Ein Menü, das aufgeht: das des laufenden Punkts, wenn er noch keins hat; sonst ein spätes oder fremdes — es schließt.
    // Untermenüs des gefangenen zählen nicht.
    let beginnt = NotificationCenter.default.addObserver(
        forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { meldung in
        // Gemeldet auf dem Hauptstrang, der das Menü führt.
        nonisolated(unsafe) let menue = meldung.object as? NSMenu
        MainActor.assumeIsolated {
            guard let menue else { return }
            if let fang = wache.fang, fang.menue == nil, !fang.abgelaufen {
                fang.geoeffnet(menue)
            } else if menue !== wache.fang?.menue, menue.supermenu == nil {
                wache.spaet.append(menue.items.map(\.title).filter { !$0.isEmpty }.prefix(4).joined(separator: ", "))
                nonisolated(unsafe) let offen = menue
                RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { offen.cancelTracking() } }
            }
        }
    }
    // Zu ist nur das gefangene Menü selbst, kein Untermenü (wie Z-AX7-01).
    let endet = NotificationCenter.default.addObserver(
        forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { meldung in
        nonisolated(unsafe) let menue = meldung.object as? NSMenu
        MainActor.assumeIsolated {
            if let fang = wache.fang, let menue, menue === fang.menue { fang.zu = true }
        }
    }
    defer {
        NotificationCenter.default.removeObserver(beginnt)
        NotificationCenter.default.removeObserver(endet)
    }
    for (stelle, punkt) in punkte.enumerated() {
        if stelle > 0, let vorJedemWeiteren { await vorJedemWeiteren() }
        let fang = Menuefang()
        fang.passt = passt
        fang.wahl = waehlen
        wache.fang = fang
        for art in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: fenster.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: art == .leftMouseDown ? 1 : 0) {
                NSApp.postEvent(ereignis, atStart: false)
            }
        }
        for _ in 0..<6 where fang.menue == nil { await ruhen(150) }
        if fang.menue != nil { for _ in 0..<20 where !fang.zu { await ruhen(150) } }
        fang.abgelaufen = true
        // Blieb es offen, schluckte es die Tasten der folgenden Schritte (Z14f-11).
        let offen = fang.menue != nil && !fang.zu
        if offen { fang.menue?.cancelTrackingWithoutAnimation() }
        let ort = "Punkt \(stelle + 1) bei (\(Int(punkt.x)), \(Int(punkt.y)))"
        guard fang.menue != nil else {
            ergebnis.verlauf.append("\(ort): kein Menü")
            if fenster.attachedSheet != nil || halt() {
                ergebnis.verlauf.append("danach Halt")
                ergebnis.halt = true
                break
            }
            continue
        }
        ergebnis.menueGesehen = true
        // Erst wenn das System den Klick hinter sich hat, geht es weiter.
        await ruhen(400)
        guard fang.passend else {
            ergebnis.verlauf.append("\(ort): Menü \(fang.titel.filter { !$0.isEmpty }.prefix(6)) passt nicht")
            if einMenueGenuegt { break }
            continue
        }
        ergebnis.titel = fang.titel
        ergebnis.angehakt = fang.angehakt
        ergebnis.punkt = stelle
        ergebnis.gewaehlt = fang.gewaehlt
        ergebnis.bliebOffen = offen
        ergebnis.verlauf.append("\(ort): Menü")
        if !wache.spaet.isEmpty { ergebnis.verlauf.append("spät geschlossen: \(wache.spaet)") }
        return ergebnis
    }
    // Ein Menü, das erst jetzt aufgeht, schließt die Wache noch.
    wache.fang = nil
    await ruhen(300)
    if !wache.spaet.isEmpty { ergebnis.verlauf.append("spät geschlossen: \(wache.spaet)") }
    return ergebnis
}

/// Für `menueAmPunkt`: den Eintrag mit genau diesem Titel wählen.
@MainActor private func eintragMitTitel(_ titel: String) -> @MainActor (NSMenu) -> (menue: NSMenu, stelle: Int)? {
    { menue in menue.items.firstIndex { $0.title == titel }.map { (menue: menue, stelle: $0) } }
}

/// Die Personen in den Zeilen einer Hülle, an ihrem Namen, wie ihn die erste Spalte zeigt (der Text der Tippwahl).
@MainActor private func personenDerZeilen(_ t: NSTableView, _ zeilen: IndexSet, _ bestand: Lernendenbestand?) -> Set<String> {
    guard let spalte = t.tableColumns.first, let bestand else { return [] }
    let namen = Set(zeilen.compactMap { t.delegate?.tableView?(t, typeSelectStringFor: spalte, row: $0) ?? nil })
    return Set(bestand.lernende.filter { namen.contains($0.anzeigename) }.map(\.id))
}

/// Ein Bestand zum Vergleich: ohne Zeitstempel, in fester Folge, ohne den Tag des Anliegens `ohneTag` bzw. des Rücklaufs
/// `ohneRuecklauf` — was ein getippter Tag ändern darf (W1-02, N7-02).
private func vergleichsstand(_ b: Lernendenbestand?, ohneTag anliegen: String? = nil,
                             ohneRuecklauf: (anliegen: String, person: String)? = nil) -> Lernendenbestand? {
    guard var k = b else { return nil }
    k.geaendert = ""
    k.anliegen = k.anliegen.map { a in
        var a = a
        a.geaendert = ""
        if a.id == anliegen { a.datum = "" }
        return a
    }.sorted { $0.id < $1.id }
    k.rueckmeldungen = k.rueckmeldungen.map { r in
        var r = r
        r.geaendert = ""
        if let o = ohneRuecklauf, r.anliegen == o.anliegen, r.lernender == o.person { r.datum = "" }
        return r
    }.sorted { ($0.anliegen, $0.lernender) < ($1.anliegen, $1.lernender) }
    return k
}

/// Wo die SwiftUI-Auswahlfelder und -Menüs der Lernendenverwaltung neben AppKit-Ansichten stehen — gemessen an der Lage ihres
/// NSPopUpButton unter macOS 26, im System des Fensters (y nach oben). Die Mitte zuerst, dann waagrecht und senkrecht
/// daneben; alle Punkte im gemessenen Rahmen.
@MainActor
private enum Menueanker {
    /// Das Auswahlfeld der Mitteilungen (313 × 24): links bündig über der Tabelle der Mitteilung, die Mitte 22 pt über ihr.
    static func auswahlfeld(_ tabelle: NSTableView) -> [NSPoint] {
        guard let r = rahmen(tabelle) else { return [] }
        return um(NSPoint(x: r.minX + 150, y: r.maxY + 22), dx: [-90, 100], dy: [-6, 6])
    }

    /// „Lerngruppen“ der Sammelleiste (125 × 24): unter der Mitgliederliste, die Mitte 30 pt unter ihr. Es steht hinter einem
    /// Zwischenraum vor drei Knöpfen fester Größe, also gemessen vom rechten Rand: die Mitte 531 pt davor (bei 704 pt Breite
    /// x +111 … +236).
    static func lerngruppen(_ liste: NSTableView) -> [NSPoint] {
        guard let r = rahmen(liste) else { return [] }
        return um(NSPoint(x: r.maxX - 531, y: r.minY - 30), dx: [-43, 47], dy: [6, -6])
    }

    /// „Stand für …“ der Sammelleiste (288 × 24): rechts bündig unter der Tabelle der Mitteilung, 8 pt vor ihrem rechten Rand,
    /// die Mitte 66 pt unter ihr.
    static func standFuer(_ tabelle: NSTableView) -> [NSPoint] {
        guard let r = rahmen(tabelle) else { return [] }
        return um(NSPoint(x: r.maxX - 152, y: r.minY - 66), dx: [92, -98], dy: [6, -6])
    }

    /// Der Rahmen des Rollbereichs der Tabelle im Fenster.
    private static func rahmen(_ tabelle: NSTableView) -> NSRect? {
        tabelle.enclosingScrollView.map { $0.convert($0.bounds, to: nil) }
    }

    private static func um(_ mitte: NSPoint, dx: [CGFloat], dy: [CGFloat]) -> [NSPoint] {
        [mitte] + dx.map { NSPoint(x: mitte.x + $0, y: mitte.y) } + dy.map { NSPoint(x: mitte.x, y: mitte.y + $0) }
    }
}

/// Was der Prüfweg in der Lücke tat — für Teil C2 des Schritts „Rückmeldungsliste“ (G2-01, E784).
@MainActor
private final class Lueckenvermerk {
    var gelaufen = false
    var blattFort = false
    /// Der Stand des Blatts, als der Prüfweg zurückkehrte — für C2b (Z-AX0b-01).
    var sichtbar = false
    var amHauptfenster = false
}

/// Ob das Loslassen einer Taste ankam — für den Schritt „Rückmeldungsliste“ (Z-AW5a-02).
@MainActor
private final class Tastenvermerk {
    var oben = false
    /// Der Stand beim Loslassen: Steht der Bogen noch — im Blatt (`nil` ohne Griff) und als Fenster am Blatt?
    var bogenOffen: Bool?
    var bogenAmBlatt = false
}

/// Ein offenes Menü, bedient wie mit der Tastatur: ↓, bis der Eintrag
/// hervorgehoben ist, dann ⏎ — getaktet von einem Zeitgeber in allen
/// Laufmodi, denn das Menü läuft in seinem eigenen. Nach so vielen Takten,
/// wie das Menü Einträge hat (ohne Trennstriche), und zwei weiteren ohne
/// Treffer schließt Escape das Menü.
@MainActor
private final class Menuekasten {
    var titel: [String] = []
    var gewaehlt = false
    var zu = false
    /// Das Menü selbst — zum Lesen der Untermenüs und Auslösen eines Eintrags über seine Handlung (AX7a, Z-AX5-03).
    var menue: NSMenu?
    private var takte = 0

    /// Kein Eintrag: das Menü beim Öffnen lesen und gleich schließen, wie die Schuljahreswahl (Z-AX7-01).
    static let nurLesen = ""

    func bedienen(_ menue: NSMenu, _ eintrag: String) {
        // Nur das erste Menü: Ein Untermenü, das unterwegs aufgeht, meldet sich auch — es ersetzt weder Titel noch Menü.
        guard self.menue == nil else { return }
        self.menue = menue
        titel = menue.items.map(\.title)
        nonisolated(unsafe) let offen = menue
        if eintrag == Self.nurLesen {
            RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { offen.cancelTracking() } }
            return
        }
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
        // So viele Schritte, wie das Menü Einträge hat — fest 8 reichte bis v92; mit der Vorbereitung (v93) steht
        // „Hausaufgabe hinzufügen …“ an 9. Stelle. Trennstriche überspringt ↓, sie zählen nicht (H2-02).
        if takte > menue.items.filter({ !$0.isSeparatorItem }).count + 2 {
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
