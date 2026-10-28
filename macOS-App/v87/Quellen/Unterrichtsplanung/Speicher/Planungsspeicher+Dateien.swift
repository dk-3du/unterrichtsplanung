// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

// ── Planung anlegen, laden, sichern ──────────────────────────────────────────
extension Planungsspeicher {

    /// Die eine Warnung, wenn das Einschalten beim Anlegen zurückgenommen wird (E478, E522) — statt der allgemeinen des
    /// Übergangs, die für eine eben angelegte Planung „bleibt, wie sie war“ sagte.
    static func einschaltenZurueckgenommen(_ grund: String, mitImport: Bool, zusatz: String = "") -> String {
        "Die Planung ist angelegt, die Verschlüsselung aber nicht eingeschaltet (\(grund.ohneSchlusspunkt))"
            + (mitImport ? " — der Import aus IServ unterblieb, die gelesenen Namen sind verworfen." : ".")
            + " Der notierte Wiederherstellungsschlüssel gilt nicht; einrichten lässt sich die Verschlüsselung unter "
            + "„Planung → Verschlüsselung …“." + zusatz
    }

    /// Trennt die allgemeine Warnung des Übergangs von den übrigen gefangenen Meldungen (E529); ihr Zusatz
    /// („ Lesezeichen: …“, „ Sitzpläne: …“) kommt an die Warnung aus E478 (E532). Erkannt an ihrem Anfang, wie
    /// `schutzMelden` ihn bei einer Rücknahme bildet — mit demselben Grund.
    static func allgemeineAbtrennen(_ gefangen: [(text: String, art: Meldung.Art)],
                                    grund: String) -> (uebrige: [(text: String, art: Meldung.Art)], zusatz: String) {
        let kopf = "Verschlüsselung nicht eingeschaltet: \(grund.satzanfang). Die Planung bleibt, wie sie war."
        var zusatz = ""
        let uebrige = gefangen.filter { meldung in
            guard meldung.text.hasPrefix(kopf) else { return true }
            zusatz += String(meldung.text.dropFirst(kopf.count))
            return false
        }
        return (uebrige, zusatz)
    }

    /// Eine versiegelte Datei über einer Planung im Klartext: Der Weg führt über „Einstellungen“.
    static let verschluesseltOhneAblage = "Die Datei ist verschlüsselt, die Ablage auf diesem Mac ist es nicht. "
        + "Bitte zuerst unter „Einstellungen“ die Verschlüsselung einschalten, dann die Datei erneut öffnen."

    /// Eine gelesene IServ-Datei, aber keine Verschlüsselung (E530) — über die Oberfläche nicht erreichbar (E350).
    static let iservOhneVerschluesselung = "Die Planung ist angelegt; der Import aus IServ unterblieb, die gelesenen "
        + "Namen sind verworfen — die Lernendenverwaltung gibt es nur mit eingeschalteter Verschlüsselung."

    /// Verschlüsselt, aber die Lernendenverwaltung ist gesperrt (E533).
    static func iservGesperrt(_ sperrhinweis: String) -> String {
        "Die Planung ist angelegt; der Import aus IServ unterblieb, die gelesenen Namen sind verworfen. " + sperrhinweis
    }

    /// Mit eingeschalteter Verschlüsselung ist „Neue Planung“ über einer
    /// bisherigen der Schuljahreswechsel (E246): Die bisherige geht samt ihrer
    /// Jahresdatei ins Archiv, die neue Jahresdatei trägt `lerngruppen` — ohne
    /// Angabe die Gruppen der übernommenen Zeilen (E271); `ohneMitglieder` die davon, die ohne Mitglieder mitkommen
    /// (E699, E708 — das Blatt gibt die Menge immer mit, leer: alle mit). `einschalten`: die
    /// vorbereitete Verschlüsselung beim Anlegen einschalten (D1b, E349, E531);
    /// `iserv`: eine gelesene IServ-Datei, die danach in die Jahresdatei kommt (D).
    func neuePlanung(titel: String, start: Tag, wochen: Int, basis: String,
                     klassen: [Klasse], ersterSchultag: Tag?,
                     uebernahme: [Planung.Uebernahmewunsch], lerngruppen: Set<String>? = nil,
                     ziele: [String: Gruppenwahl] = [:], ohneMitglieder: Set<String>,
                     iserv: (lesung: IServImport.Lesung, ziel: Importziel)? = nil, einschalten: Bool = false) {
        if let erster = ersterSchultag, !erster.liegtImZeitraum(start: start, wochen: wochen) {
            melden("Der erste Schultag liegt außerhalb des Planungszeitraums.", .warnung)
            return
        }
        guard !ablageGesperrt, !entsperrungOffen, !blockadeOffen else {
            melden(sperrhinweis, .warnung)
            return
        }
        sicherung.startsperreAufheben()
        // Gleicher fester Dateiname: Die neue Planung überschreibt die Sicherung der bisherigen.
        let nameKollidiert = kopienameBliebe(neuerTitel: titel)

        let fachfarben = planung?.fachfarben ?? [:]
        // Auf die Lesegrenzen kappen: Was der Leser beim nächsten Start kürzte,
        // soll gar nicht erst entstehen.
        // Zugeschnitten wie jede Schranke (E208, v74); hier nur Leerzeichen und Tabulator.
        let gekappt = Planungsdatei.planungstitel(titel)
        let sauberekurse = klassen.map { kurs -> Klasse in
            var k = kurs
            k.name = String(Planungsdatei.ohneSteuerzeichen(k.name).prefix(Planungsdatei.maxNamenslaenge))
            k.fach = String(Planungsdatei.ohneSteuerzeichen(k.fach).prefix(Planungsdatei.maxNamenslaenge))
            return k
        }
        let (neue, bilanz) = Planung.mitUebernahme(
            titel: gekappt,
            start: start, wochen: wochen,
            basis: Pfade.normalisieren(basis, basis: basis),
            klassen: sauberekurse, fachfarben: fachfarben,
            ersterSchultag: ersterSchultag,
            von: planung, uebernahme: uebernahme)
        let archiviert = tresor != nil && planung != nil
        let bisherigePersonen = lernendenKennungen
        if archiviert {
            let gruppen = lerngruppen ?? lerngruppenDerUebernahme(bilanz.zuordnung)
            // Name und Zeilen je Gruppe aus dem Blatt (E308, E310, E649) — übernommene Zeilen an ihrer neuen Kennung,
            // in ihrer Folge, jede einmal.
            var gruppenziele: [String: Gruppenziel] = [:]
            for (id, wahl) in ziele {
                var zeilen: [String] = []
                for ziel in wahl.zeilen {
                    let zeile: String? = switch ziel {
                    case .keine: nil
                    case .kennung(let k): neue.klassen.contains { $0.id == k } ? k : nil
                    case .uebernommen(let alt): bilanz.zuordnung[alt]
                    }
                    if let zeile, !zeilen.contains(zeile) { zeilen.append(zeile) }
                }
                gruppenziele[id] = Gruppenziel(name: wahl.name, zeilen: zeilen)
            }
            if let grund = jahreswechsel(zu: neue, zuordnung: bilanz.zuordnung, gruppen: gruppen, ziele: gruppenziele,
                                         ohneMitglieder: ohneMitglieder) {
                melden("Die neue Planung wurde nicht angelegt (\(grund.ohneSchlusspunkt)) — die bisherige gilt weiter.",
                       .warnung)
                return
            }
        } else {
            planung = neue
        }
        // Die Sitzpläne folgen ihren Klassen unter die neue Kennung; die der
        // übrigen Klassen werden entfernt (E28: einer je Klasse, an ihrer Kennung).
        sitzplaene.umschreiben(zuordnung: bilanz.zuordnung)
        // Beim Wechsel still, danach der Abgleich für Älteres — wie bei ⌘O (Z-AS5a-06, -09).
        if archiviert {
            bindungenNachWechselLoesen(bisherigePersonen)
            sitzplanbindungenAbgleichen()
        }
        // D1b (E349): Auf ausdrücklichen Wunsch (E531) die vorbereitete Verschlüsselung jetzt einschalten — im selben
        // Schritt des Hauptstrangs, bevor das entprellte Sichern die Planung im Klartext schriebe. Ohne Wunsch bleibt eine
        // liegende Vorbereitung unberührt. Die Meldungen des Übergangs gehen durch den Fang (E529): Wird das Einschalten
        // zurückgenommen — auch ohne Vorbereitung —, ersetzt die Warnung aus E478 die allgemeine, samt deren Zusatz
        // (E532); alle übrigen kommen wie gefangen.
        var nichtEingeschaltet: (grund: String, zusatz: String)?
        if einschalten, !archiviert, tresor == nil {
            meldungsfang = []
            let ergebnis = verschluesselungEinschalten()
            var gefangen = meldungsfang ?? []
            meldungsfang = nil
            if case .zurueckgenommen(let grund) = ergebnis.ablage {
                let (uebrige, zusatz) = Self.allgemeineAbtrennen(gefangen, grund: grund)
                gefangen = uebrige
                nichtEingeschaltet = (grund, zusatz)
            }
            for m in gefangen { melden(m.text, m.art) }
        }
        suchbegriff = ""
        sichern()
        zurLaufendenWoche()
        var meldung = "\(wochen) Wochen angelegt"
            + (neue.klassen.isEmpty ? "."
               : " für \(neue.unterrichtszeilen) Klassen/Kurse"
                 + (neue.sonderzeilenzahl > 0 ? " und \(neue.sonderzeilenzahl) Sonderzeilen." : "."))
        if bilanz.klassen > 0 {
            meldung += " Übernommen: \(bilanz.klassen) "
                + (bilanz.klassen == 1 ? "Zeile" : "Zeilen")
                + (bilanz.vorhaben > 0 ? " mit \(bilanz.vorhaben) Vorhaben" : "") + "."
        }
        if bilanz.uebergangen > 0 {
            meldung += " \(bilanz.uebergangen) Vorhaben ohne passende Schulwoche übergangen."
        }
        if archiviert { meldung += " Die bisherige Planung liegt samt ihren Lernendendaten im Archiv." }
        melden(meldung, bilanz.uebergangen > 0 ? .warnung : .hinweis)
        // Der Import aus IServ (D): in die versiegelte Jahresdatei, an die Zeilen gleichen Namens gebunden (E351, E521).
        if let nicht = nichtEingeschaltet {
            melden(Self.einschaltenZurueckgenommen(nicht.grund, mitImport: iserv != nil, zusatz: nicht.zusatz), .warnung)
        } else if let iserv {
            iservUebernehmen(iserv)
        }
        if nameKollidiert, autoexportAktiv, !autoexportOrdner.isEmpty {
            melden("Die Sicherungskopie heißt weiterhin „\(autoexportDateiname)“ — beim "
                   + "Beenden ersetzt sie die der bisherigen Planung. Für ein zweites "
                   + "Schuljahr besser einen anderen Titel wählen.", .warnung)
        }
        if neue.klassen.isEmpty { offenerDialog = .klassen }
        tourAnbieten = true
    }

    /// Der Import beim Anlegen (D): erst die Herkunft der Planung auf die Platte (A4, E525), dann Import und Bindung nach
    /// Namen in einem Schritt — nur mit offener Lernendenverwaltung, sonst unterbleibt er (E530).
    /// Die eine Warnung, wenn sich die Planung beim Import nicht sichern ließ (E681).
    static let iservOhneHerkunft = "Die Planung ließ sich nicht sichern — die Lerngruppen werden erst an Zeilen gebunden, wenn "
        + "ihre Herkunft auf der Platte steht, und die Lernendendaten finden erst nach einer gelungenen Sicherung verlässlich zu "
        + "ihr zurück."

    func iservUebernehmen(_ iserv: (lesung: IServImport.Lesung, ziel: Importziel)) {
        guard lernende.schreibbar, let p = planung, let start = lernendenEntwurfBeginnen() else {
            // Ohne Verschlüsselung E530, sonst der Grund der Sperre (E533).
            melden(tresor == nil ? Self.iservOhneVerschluesselung
                   : Self.iservGesperrt(lernende.sperrhinweis ?? "Die Lernendenverwaltung ist gerade nicht verfügbar."),
                   .warnung)
            return
        }
        let fehlt = herkunftSichern()
        let (neu, bilanz, bindung) = start.mitImport(iserv.lesung, ziel: iserv.ziel, binden: fehlt == nil ? p.klassen : nil,
                                                    planung: p.erstellt, jetzt: Zeitrechnung.jetztAlsZeitstempel())
        // Die Herkunft ist eben zu sichern versucht — „Übernehmen“ versucht es nicht noch einmal; eine Warnung nennt beide Folgen
        // (E681).
        lernendenUebernehmen(neu, ausgang: start, herkunftVersucht: true)
        melden(bilanz.meldung(bindung))
        if fehlt != nil { melden(Self.iservOhneHerkunft, .warnung) }
    }

    /// Trüge eine neue Planung mit diesem Titel dieselbe Sicherungskopie wie die
    /// bisherige? Verglichen wird der Name, den die Kopie tragen wird — aus dem
    /// Titel, den `neuePlanung` ablegt, nicht aus der Eingabe (E214, R74-01).
    /// Dialog und Anlegen fragen beide hier.
    func kopienameBliebe(neuerTitel: String) -> Bool {
        guard let bisher = planung?.titel else { return false }
        return Planungsdatei.festerName(titel: bisher)
            == Planungsdatei.festerName(titel: Planungsdatei.planungstitel(neuerTitel))
    }

    /// Die Zeile im Blatt der Ersteinrichtung, wenn beim Öffnen einer Planung etwas übergangen wurde (E779).
    static func verlustzeileErsteinrichtung(_ titel: String) -> String {
        "Beim Öffnen von „\(titel)“ ist etwas übergangen — die Meldung folgt nach diesem Blatt."
    }

    /// Satz über das, was beim Lesen wegfiel — leer, wenn nichts wegfiel.
    static func verlusttext(_ bilanz: Planungsdatei.Verlustbilanz) -> String {
        guard !bilanz.istLeer else { return "" }
        let teile = bilanz.verworfenes + bilanz.hinweise
        return " Übergangen: " + teile.joined(separator: ", ") + "."
    }

    func importieren(von url: URL) {
        // Per Finder oder Dock geöffnet, während eine Rückfrage sichtbar steht: Nichts
        // öffnet darunter und kein Blatt schließt unter ihr (Z14c4-03, E317). Der Ton
        // kommt sofort, der Text, sobald weder Frage noch Blatt offen ist — darunter
        // verfiele er ungelesen (E334).
        guard !frageSperrtBefehl() else {
            // Die eigene Frage dieser Datei: still — die Entscheidung über sie steht an (Z-AS2-10).
            if !entscheidungSteht(ueber: url) {
                // In der Lücke steht keine Frage mehr, eine bestätigte Handlung läuft gleich (Z-AU4c-12).
                let grund = alertSteht ? "weil eine Rückfrage stand" : "weil eine bestätigte Handlung noch lief"
                spaeterMelden("„\(url.lastPathComponent)“ wurde nicht geöffnet, \(grund). "
                              + "Bitte die Datei erneut öffnen.", .warnung, datei: url)
            }
            return
        }
        guard !ablageGesperrt, !entsperrungOffen, !blockadeOffen else {
            // Hinter dem Blatt zum Entsperren läge der Hinweis ungelesen: Ton sofort, der Text,
            // wenn das Blatt zu ist (B87, E393). Wartet dort eine fremde Datei, gilt für eine andere
            // der Text aus E391; dieselbe bleibt still — über sie wird schon entschieden (Z-AS3-01).
            if offenerDialog == .entsperren {
                systemton()
                if entsperrungFuerAblage {
                    spaeterMelden("„\(url.lastPathComponent)“ wurde nicht geöffnet, weil die Planung noch nicht entsperrt war. "
                                  + "Bitte die Datei erneut öffnen.", .warnung, datei: url)
                } else if let wartend = entsperrung?.ziel.datei,
                          Planungsspeicher.dateischluessel(wartend) == Planungsspeicher.dateischluessel(url) {
                    // Dieselbe Datei — still.
                } else {
                    spaeterMelden("„\(url.lastPathComponent)“ wurde nicht geöffnet, weil ein Blatt offen war. "
                                  + "Bitte die Datei erneut öffnen.", .warnung, datei: url)
                }
            } else {
                melden(sperrhinweis, .warnung)
            }
            return
        }
        // Gebunden gelesen: Art und Größe am geöffneten Objekt, nie mehr als
        // die Grenze im Speicher — was keine Planung sein kann, wird nicht geöffnet.
        // Ein Dateifehler hinter einem Blatt: Ton sofort, Text danach (B98, E421).
        let daten: Data
        switch Ablage.gebundenLesen(url, hoechstens: Planungsdatei.hoechstgroesse) {
        case .keine:
            dateifehlerMelden("„\(url.lastPathComponent)“ ist nicht mehr da und wurde nicht geöffnet.", von: url)
            return
        case .zuGross(let groesse):
            dateifehlerMelden("Die Datei ist mit \(groesse / 1024 / 1024) MB zu groß für eine "
                              + "Planungsdatei und wurde nicht geöffnet.", von: url)
            return
        case .unlesbar(let fehler):
            dateifehlerMelden(fehler.localizedDescription.ohneSchlusspunkt + " — die Datei wurde nicht geöffnet.", von: url,
                              systemtext: true)
            return
        case .daten(let gelesen):
            daten = gelesen
        }
        do {
            guard Tresor.istBehaelter(daten) else {
                importierenKlartext(daten, von: url)
                return
            }
            let kopf = try Tresor.kopfLesen(daten)
            // Ein Export der Lernendenverwaltung: eingelesen, nicht als Planung (E287).
            if kopf.inhalt == Tresor.Inhalt.lernende.rawValue {
                // Nicht hinter einem Blatt: Das Blatt „Lernende“ schriebe beim „Übernehmen“ seinen Entwurf
                // über das Eingelesene, und das Entsperren schlösse das Blatt (G1-01, G1-E1, E398). Was das
                // Einlesen ohnehin abwiese, nennt dort gleich seinen Grund statt „erneut öffnen“ (B98, E421 b).
                guard ortAngezeigt(.hauptansicht) else {
                    let grund = lernendenEinlesenAusgeschlossen
                    hinterBlattAbweisen(url, text: grund?.text, art: grund?.art ?? .warnung)
                    return
                }
                lernendenEinlesen(daten: daten, von: url)
                return
            }
            guard kopf.inhalt == Tresor.Inhalt.planung.rawValue else {
                dateifehlerMelden("Die Datei ist ein verschlüsselter Behälter mit Inhalt „\(kopf.inhalt)“, "
                                  + "keine Planung.", von: url)
                return
            }
            if let tresor, tresor.passt(zu: kopf) {
                importierenKlartext(try tresor.oeffnen(kopf: kopf), von: url)
                return
            }
            guard tresor != nil else {
                // Ohne Planung gibt es keine „Einstellungen“: Die Datei wird die Planung dieses Macs, mit ihrer
                // Passphrase und ihrem Wiederherstellungsschlüssel — wie nach einem Umzug (E702, E707). Nicht hinter
                // einem Blatt, wie unten; „Neue Planungsdatei“ und Frage 1 auf ihrer ersten Seite zählen nicht (E716).
                if planung == nil {
                    guard ortAngezeigt(.hauptansicht) || nurNeuePlanungsdatei || frage1AufErsterSeite else {
                        hinterBlattAbweisen(url)
                        return
                    }
                    // Stand Frage 1 einmal, bleibt es dabei — auch über ein „Abbrechen“ hinweg (Z-AW1bM-01).
                    uebernahmeAusFrage1 = uebernahmeAusFrage1 || frage1AufErsterSeite
                    entsperrungBeginnen(.uebernahme(daten, url))
                    return
                }
                // Über einer Planung im Klartext läge die geöffnete danach im Klartext —
                // das entscheidet der Nutzer vorher.
                dateifehlerMelden(Self.verschluesseltOhneAblage, von: url)
                return
            }
            // Fremder Schlüssel: Passphrase oder Wiederherstellungsschlüssel der Datei — nicht hinter
            // einem Blatt, das Entsperren schlösse es samt Eingaben (G1-E1, E398). Steht ohne Planung nur
            // „Neue Planungsdatei“, die zum Öffnen auffordert, wie im Klartext (E331, Z-AS7a-04).
            guard ortAngezeigt(.hauptansicht) || nurNeuePlanungsdatei else { hinterBlattAbweisen(url); return }
            entsperrungBeginnen(.datei(daten, url))
        } catch {
            dateifehlerMelden(error.localizedDescription, von: url, systemtext: true)
        }
    }

    /// Hinter einem Blatt abgewiesen: der Ton sofort, der Text, wenn das Blatt zu ist (E391, E398, E399) —
    /// „… weil ein Blatt offen war“ oder der Grund, aus dem die Datei ohnehin nicht aufginge (B98, E421).
    private func hinterBlattAbweisen(_ url: URL, text: String? = nil, art: Meldung.Art = .warnung) {
        systemton()
        guard !entscheidungSteht(ueber: url) else { return }
        spaeterMelden(text ?? "„\(url.lastPathComponent)“ wurde nicht geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen.",
                      art, datei: url)
    }

    /// Ein Dateifehler beim Öffnen — hinter einem Blatt abgewiesen wie dort, ohne Blatt gleich und ohne Ton (B98, E421);
    /// „Neue Planungsdatei“ ohne Planung zählt nicht als Blatt, wie beim Öffnen selbst. `systemtext`: Der Text kommt
    /// vom System und kann die Datei mit ihrem Anzeigenamen nennen (Z-AU11-04, Z-AU11-07).
    private func dateifehlerMelden(_ text: String, _ art: Meldung.Art = .warnung, von url: URL, systemtext: Bool = false) {
        guard ortAngezeigt(.hauptansicht) || nurNeuePlanungsdatei else {
            var anzeigename: (@MainActor () -> String)?
            if systemtext {
                let fragen = anzeigenameVon
                anzeigename = { fragen(url) }
            }
            hinterBlattAbweisen(url, text: Self.nachgeholterDateifehler(text, datei: url, anzeigename: anzeigename), art: art)
            return
        }
        melden(text, art)
    }

    /// Nachgeholt steht ein Dateifehler ohne seinen Anlass da: Er nennt seine Datei vorn (Z-AU7-02) — außer er
    /// nennt sie schon, vorn oder mittendrin, in welchen Anführungszeichen auch immer (Z-AU7-10, AU11), oder ein
    /// Systemtext nennt ihren Anzeigenamen, wenn der Finder die Endung ausblendet (`anzeigename`, Z-AU11-04). Der
    /// Anzeigename zählt nur in Anführungszeichen — ohne Endung steckte er sonst in manchem Wort — und wird erst
    /// erfragt, wenn der Dateiname fehlt (Z-AU11-06). Eigene Texte fragen ihn nicht: „Einstellungen“ meint dort
    /// das Blatt (Z-AU11-07).
    static func nachgeholterDateifehler(_ text: String, datei url: URL, anzeigename: (@MainActor () -> String)? = nil) -> String {
        let name = url.lastPathComponent
        guard !text.contains(name) else { return text }
        if let angezeigt = anzeigename?(),
           ["„\(angezeigt)“", "“\(angezeigt)”", "\"\(angezeigt)\""].contains(where: { text.contains($0) }) {
            return text
        }
        return "„\(name)“: \(text)"
    }

    /// Ohne Planung steht nur „Neue Planungsdatei“ und fordert zum Öffnen auf (E331, Z-AS7a-04).
    private var nurNeuePlanungsdatei: Bool { planung == nil && offenerDialog == .neuePlanung }

    /// Frage 1 der Ersteinrichtung auf ihrer ersten Seite, mit „Planung öffnen …“ (E716): Eingegeben ist dort noch
    /// nichts — für die Übernahme einer versiegelten Planung zählt sie wie „Neue Planungsdatei“. Dateifehler und alles
    /// Übrige bleiben hinter ihr wie hinter jedem Blatt: Sie zeigt keine Meldungen (Z-AW1bN-01).
    private var frage1AufErsterSeite: Bool {
        planung == nil && offenerDialog == .ersteinrichtung && ersteinrichtungsschritt == .verschluesselung
    }

    func importierenKlartext(_ daten: Data, von url: URL) {
        do {
            let (geladen, bilanz) = try Planungsdatei.lesenMitBilanz(daten)
            // Eine Planung anderer Herkunft bei eingeschalteter Verschlüsselung:
            // ein Schuljahreswechsel — die bisherige samt Lernenden ins Archiv (E277).
            let wechsel = tresor != nil && planung.map { $0.erstellt != geladen.erstellt } == true
            // `gruppen`: die Lerngruppen, die beim Wechsel mitkommen (E305), `ohne` die davon ohne Mitglieder (E699, E708) —
            // sonst ohne Bedeutung.
            let uebernehmen: @MainActor (Set<String>, [String: Gruppenziel], Set<String>) -> Void = { [weak self] gruppen, ziele, ohne in
                guard let self else { return }
                sicherung.startsperreAufheben()
                let bisherigePersonen = lernendenKennungen
                if wechsel, let bisherige = planung {
                    if let grund = jahreswechsel(zu: geladen, zuordnung: Planungsspeicher.zuordnungNachNamen(von: bisherige, zu: geladen),
                                                 gruppen: gruppen, ziele: ziele, ohneMitglieder: ohne) {
                        melden("„\(geladen.titel)“ wurde nicht geöffnet (\(grund.ohneSchlusspunkt)) — die bisherige "
                               + "Planung gilt weiter.", .warnung)
                        return
                    }
                } else {
                    planung = geladen
                }
                // Sitzpläne, deren Klasse die eingelesene Planung nicht kennt (E41) — beim Wechsel ohne Abgleich.
                sitzplaeneAufraeumen(abgleichen: !wechsel)
                // Erst danach die Bindungen — die Rettungskopie trägt sie wie das Archiv die Personen (Z14c-10);
                // beim Wechsel still, danach der Abgleich für Älteres — wie bei „Neue Planung“ (Z-AS5a-06, -09).
                if wechsel {
                    bindungenNachWechselLoesen(bisherigePersonen)
                    sitzplanbindungenAbgleichen()
                }
                // „Neue Planungsdatei“ steht beim Start offen und läge sonst über der Planung. Steht die Einrichtung an,
                // ist sie danach vorgemerkt — die Meldung unten wartet dann hinter ihr (E849, Z-AX0b-03).
                neuePlanungSchliessen(ersteinrichtungFaellig: ersteinrichtungFaellig)
                // Wurde dieselbe Datei inzwischen ein zweites Mal geöffnet und abgewiesen,
                // wäre deren „nicht geöffnet“ jetzt falsch (Z-AS2-01).
                vorgemerkteMeldungenVerwerfen(datei: url)
                sichern()
                zurLaufendenWoche()
                let verlust = Planungsspeicher.verlusttext(bilanz)
                let nachsatz = verlust.isEmpty
                    ? ""
                    : verlust + " Die geöffnete Datei selbst bleibt unverändert."
                let text = "Planung „\(geladen.titel)“ geladen."
                    + (wechsel ? " Die bisherige Planung liegt samt ihren Lernendendaten im Archiv." : "") + nachsatz
                let art: Meldung.Art = verlust.isEmpty ? .hinweis : .warnung
                // Unter Frage 1 der Ersteinrichtung zeigt das Blatt keine Meldungen — der Text kommt nach dem Blatt,
                // auch eine Verlustwarnung (G3-01, Z-AW1bM-05); ebenso, wenn das Blatt erst kommt (Z-AW10N-05). Ein
                // Verlust wartete sonst drei Fragen lang: Das Blatt zeigt sofort eine Zeile (E779, Z-AW10N-04).
                if offenerDialog == .ersteinrichtung || naechsterDialog == .ersteinrichtung {
                    spaeterMelden(text, art)
                    if !verlust.isEmpty { verlustUnterDerErsteinrichtung = geladen.titel }
                } else {
                    melden(text, art)
                }
            }
            if wechsel, let vorhanden = planung {
                let zuordnung = Planungsspeicher.zuordnungNachNamen(von: vorhanden, zu: geladen)
                let hochstufen = hochstufungsvorgabe(zu: geladen, zuordnung: zuordnung)
                // Ein offenes Blatt verlöre beim Wechsel seine Eingaben — erst schließen (Z14c-02, Z14c-09).
                // Gesagt wird es, wenn das Blatt zu ist: Dahinter verfiele der Text (E335, E391).
                guard ortAngezeigt(.hauptansicht) else {  // auch ein Blatt im Kommen (Z-AS3-04)
                    systemton()  // sofort, wie hinter dem Entsperren (E334, E399)
                    // Das eigene Blatt dieser Datei („Neues Schuljahr öffnen“): ohne Text (Z-AS2-10).
                    guard !entscheidungSteht(ueber: url) else { return }
                    spaeterMelden("„\(geladen.titel)“ "
                                  + (hochstufen.stufen == 0 ? "ist eine andere Planung desselben Schuljahrs"
                                                            : "gehört zu einem anderen Schuljahr")
                                  + " und wurde nicht geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen.",
                                  .warnung, datei: url)
                    return
                }
                // Das Blatt „Neues Schuljahr öffnen“ mit der Wahl der Lerngruppen wie bei
                // „Neue Planung“ (E305), dazu Hochstufen und Zuordnen (E307–E311).
                schuljahrwechsel = Schuljahrwechsel(titel: geladen.titel, bisher: vorhanden.titel,
                                                    hochstufen: hochstufen, oeffnen: uebernehmen)
                dialogOeffnen(.schuljahrOeffnen)
                dateiInEntscheidung = (Planungsspeicher.dateischluessel(url), nil)
            } else if let vorhanden = planung, !vorhanden.eintraege.isEmpty {
                // Hinter einem offenen Blatt bliebe die Frage „… wird ersetzt“ unsichtbar und sperrte das
                // Menü still — abweisen wie im Wechsel-Zweig (Z14c4-06, E331, E391).
                guard ortAngezeigt(.hauptansicht) else {  // auch ein Blatt im Kommen (Z-AS3-04)
                    systemton()  // sofort, wie hinter dem Entsperren (E334, E399)
                    guard !entscheidungSteht(ueber: url) else { return }
                    spaeterMelden("„\(geladen.titel)“ wurde nicht geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen.",
                                  .warnung, datei: url)
                    return
                }
                // Selbst gebaut, damit ihre Kennung bekannt ist (Z-AS2-10); ersetzt wird erst nach dem
                // Schließen des Alerts — das Ersetzen baut die Hauptfläche um (B95, E417).
                let frage = Rueckfrage(text: "Die geöffnete Planung „\(vorhanden.titel)“ mit \(vorhanden.eintraege.count) "
                                             + "Vorhaben wird ersetzt.\n\nFortfahren? (Vorher ggf. exportieren.)",
                                       bestaetigung: "Ersetzen", gefahr: true,
                                       handlung: nachDemSchliessenAusfuehren { uebernehmen([], [:], []) })
                frageStellen(frage)
                dateiInEntscheidung = (Planungsspeicher.dateischluessel(url), frage.id)
            } else {
                uebernehmen([], [:], [])
            }
        } catch {
            dateifehlerMelden(error.localizedDescription, von: url, systemtext: true)
        }
    }

    func importDialog() {
        Systemzugriff.quelleWaehlen { [weak self] url in
            guard let self, let url else { return }
            importieren(von: url)
        }
    }

    /// ⌘S — bei eingeschalteter Verschlüsselung als Behälter mit Passphrase-
    /// und Wiederherstellungswicklung, sonst Klartext wie bisher.
    func exportieren() {
        exportSchreiben(klartext: false)
    }

    /// Der bewusste Weg zum Klartext: die Datei, die in zehn Jahren jedes
    /// Programm liest — mit Rückfrage, damit sie niemand versehentlich schreibt.
    func exportierenKlartext() {
        guard planung != nil else { return }
        guard tresor != nil else { exportSchreiben(klartext: true); return }
        fragen("Die Datei wird unverschlüsselt geschrieben: als Fassung, die in zehn "
               + "Jahren jedes Programm liest — und im Klartext, wo immer sie "
               + "hinkommt.\n\nFortfahren?",
               bestaetigung: "Als Klartext sichern", gefahr: true) { [weak self] in
            self?.exportSchreiben(klartext: true)
        }
    }

    private func exportSchreiben(klartext: Bool) {
        // AppKit führt NSModalPanelRunLoopMode als gemeinsamen Modus: Während
        // `runModal()` feuern Entpreller weiter. Deshalb vorher übernehmen — sonst
        // trüge die Datei einen überholten Titel — und danach neu lesen.
        Entpreller.allesUebernehmen()
        guard let titel = planung?.titel else { return }
        // Erst fragen, dann den Zeitstempel anheben: Sonst bliebe nach Abbruch eine Scheinänderung.
        Systemzugriff.zielWaehlen(name: Planungsdatei.exportName(titel: titel)) { [weak self] ziel in
            guard let self, let ziel, var aktuell = planung else { return }
            aktuell.geaendert = Zeitrechnung.jetztAlsZeitstempel()
            planung = aktuell
            do {
                var daten = try Planungsdatei.schreiben(aktuell)
                let tresor = klartext ? nil : self.tresor
                if let tresor { daten = try tresor.versiegeln(daten, inhalt: .planung, ziel: .export) }
                try daten.write(to: ziel, options: [.atomic])
                // Sonst gingen Autosicherung und Exportdatei auseinander.
                jetztSichern()
                melden(tresor == nil
                       ? "Planung als JSON gesichert."
                       : "Planung als verschlüsselte JSON-Datei gesichert — sie öffnet mit der "
                         + "Passphrase oder dem Wiederherstellungsschlüssel.")
                // Geschrieben wird sie trotzdem — aber nicht still: Kein Leser
                // dieses Projekts öffnet sie, und der Nutzer soll das jetzt hören.
                if let hinweis = Planungsspeicher.lesegrenzeHinweis(groesse: daten.count) {
                    melden(hinweis, .warnung)
                }
            } catch {
                melden("Die Datei konnte nicht geschrieben werden: \(error.localizedDescription)", .warnung)
            }
        }
    }

    /// Eine geschriebene Datei jenseits der Lesegrenze — `nil`, solange sie
    /// darunter bleibt. Für Export und Sicherungskopie.
    static func lesegrenzeHinweis(groesse: Int) -> String? {
        guard groesse > Planungsdatei.hoechstgroesse else { return nil }
        return "Die Datei ist mit \(groesse / 1024 / 1024) MB größer als die Lesegrenze von App und "
            + "Web App (\(Planungsdatei.hoechstgroesse / 1024 / 1024) MB) — so lässt sie sich nicht "
            + "mehr öffnen. Bitte Beschreibungen und Kommentare kürzen."
    }

    /// Auch die erste Woche ist eine Woche: Eine Untergrenze hier ließe den
    /// Sprung genau dann still verpuffen, wenn heute im ersten Zeitraum liegt.
    func zurLaufendenWoche() {
        guard let nummer = planung?.laufendeWoche else {
            melden("Die laufende Woche liegt außerhalb des geplanten Zeitraums.", .hinweis)
            return
        }
        sprung = Rastersprung(woche: nummer)
    }
}
