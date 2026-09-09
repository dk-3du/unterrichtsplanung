// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Titel, Einstellungen, unterrichtsfreie Zeiten, Klassen, Farben, Prüfungen, Heute, Sperrzeiträume ───
extension Planungsspeicher {

    // ── Titel und Einstellungen ───────────────────────────────────────────

    /// Der Titel als Bindung für die Fensterleiste; entprellt geschrieben, weil
    /// jeder Tastendruck sonst einen Neuaufbau des Rasters nach sich zöge.
    var planungstitel: String {
        get { planung?.titel ?? "Unterrichtsplanung" }
        set {
            guard planung != nil else { return }
            titelentwurf = newValue
            titelentpreller.nach(400) { [weak self] in
                guard let self, let entwurf = titelentwurf else { return }
                titelentwurf = nil
                titelSetzen(entwurf)
            }
        }
    }

    func titelSetzen(_ titel: String) {
        let gekappt = Planungsspeicher.aufNamenslaenge(titel)
        guard planung != nil, planung?.titel != gekappt else { return }
        planung?.titel = gekappt
        sichern()
        if gekappt != titel { kuerzungMelden("Der Titel") }
    }

    /// Vorhaben hinter der neuen letzten Woche gehen verloren — deshalb vorher
    /// die Rückfrage.
    func einstellungenUebernehmen(start: Tag, wochen: Int, ersterSchultag: Tag?) {
        guard let aktuell = planung else { return }
        let anzahl = min(Kennwerte.wochenMax, max(1, wochen))
        let verlust = aktuell.eintraege.count { $0.woche >= anzahl }

        // Ein Tag außerhalb des Zeitraums ließe die Zählung still auf die Herleitung zurückfallen.
        if let erster = ersterSchultag, !erster.liegtImZeitraum(start: start, wochen: anzahl) {
            melden("Der erste Schultag liegt außerhalb des Planungszeitraums.", .warnung)
            return
        }

        let uebernehmen: @MainActor () -> Void = { [weak self] in
            guard let self, var p = planung else { return }
            p.start = start.montagDerWoche
            p.wochen = anzahl
            p.ersterSchultag = ersterSchultag
            p.eintraege.removeAll { $0.woche >= anzahl }
            // `frei` und `zellenfrei` bleiben stehen wie `ferien` und
            // `sperrzeiten`: Sie hängen am Montagsdatum, nicht am Spaltenindex,
            // werden nur über die Wochenliste nachgeschlagen und sind
            // gedeckelt. Gefiltert verschwänden sie beim bloßen Verschieben des
            // Starts still und wären nicht zurückzuholen.

            planung = p
            sichern()
            offenerDialog = nil
            melden("Einstellungen übernommen.")
        }

        if verlust > 0 {
            fragen("\(verlust) Vorhaben liegen hinter der neuen letzten Woche und werden entfernt. Fortfahren?",
                   bestaetigung: "Entfernen", gefahr: true, ort: .einstellungen,
                   handlung: uebernehmen)
        } else {
            uebernehmen()
        }
    }

    // ── Unterrichtsfreie Zeiten ───────────────────────────────────────────

    func wocheFreiSchalten(_ woche: Woche) {
        guard var p = planung else { return }
        if p.frei.contains(woche.montag) { p.frei.remove(woche.montag) }
        else { p.frei.insert(woche.montag) }
        planung = p
        sichern()
    }

    func zelleFreiSchalten(klasse: String, woche: Woche) {
        guard var p = planung else { return }
        let zelle = FreieZelle(klasseId: klasse, woche: woche.montag)
        if p.zellenfrei.contains(zelle) { p.zellenfrei.remove(zelle) }
        else { p.zellenfrei.insert(zelle) }
        planung = p
        sichern()
    }

    @discardableResult
    func ferienHinzufuegen() -> String? {
        guard var p = planung else { return nil }
        let letzte = p.ferien.map(\.bis).max()
        let start = letzte?.plus(tage: 7) ?? p.start
        let montag = start.montagDerWoche
        let neu = Ferienzeitraum(id: Kennung.neu("f"), name: "Ferien",
                                 von: montag, bis: montag.plus(tage: 4))
        p.ferien.append(neu)
        planung = p
        sichern()
        return neu.id
    }

    /// Nur den Namen: Ein entprellter Schreibvorgang trüge sonst den alten
    /// Zeitraum mit sich und nähme eine Datumsänderung zurück.
    func ferienNamenSetzen(id: String, name: String) {
        guard var p = planung, let stelle = p.ferien.firstIndex(where: { $0.id == id }) else { return }
        let gekappt = Planungsspeicher.aufNamenslaenge(name)
        guard p.ferien[stelle].name != gekappt else { return }
        p.ferien[stelle].name = gekappt
        planung = p
        sichern()
        if gekappt != name { kuerzungMelden("Die Bezeichnung des Ferienzeitraums") }
    }

    func ferienAendern(_ zeitraum: Ferienzeitraum) {
        guard var p = planung, let stelle = p.ferien.firstIndex(where: { $0.id == zeitraum.id }) else { return }
        p.ferien[stelle] = zeitraum
        planung = p
        sichern()
    }

    func ferienEntfernen(_ id: String) {
        guard var p = planung else { return }
        p.ferien.removeAll { $0.id == id }
        planung = p
        sichern()
    }

    // ── Klassen ───────────────────────────────────────────────────────────

    /// Liefert die Kennung, damit die Liste die Schreibmarke gleich in das
    /// Namensfeld setzen kann.
    @discardableResult
    func klasseHinzufuegen() -> String? {
        guard var p = planung else { return nil }
        guard p.klassen.count < Kennwerte.maxKlassen else {
            melden("Mehr als \(Kennwerte.maxKlassen) Klassen/Kurse sind nicht vorgesehen.",
                   .warnung)
            return nil
        }
        let neu = Klasse(
            id: Kennung.neu("k"), name: "", fach: "", notiz: "",
            farbe: Farbwelt.ohneFarbe, farbeManuell: false)
        p.klassen.append(neu)
        p.farbenVervollstaendigen()
        planung = p
        sichern()
        return neu.id
    }

    /// Die Fachfarbe zieht nach, solange sie nicht von Hand gesetzt wurde.
    /// Das Fachfeld ist entprellt und meldet auch Halbgetipptes („Mat“) — das
    /// darf nichts hinterlassen, deshalb entscheidet allein `farbeNachziehen`.
    func klasseAendern(id: String, name: String? = nil, fach: String? = nil, notiz: String? = nil) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
        let vorher = p.klassen[stelle]
        // Der Leser kappt Bezeichnung, Fach und Notiz auf `maxNamenslaenge`;
        // ungekappt geschrieben verschwände der Überhang beim nächsten Start.
        var gekuerztes: String?
        func gekappt(_ wert: String, _ feld: String) -> String {
            let kurz = Planungsspeicher.aufNamenslaenge(wert)
            if kurz != wert { gekuerztes = feld }
            return kurz
        }
        if let name { p.klassen[stelle].name = gekappt(name, "Die Bezeichnung") }
        if let notiz { p.klassen[stelle].notiz = gekappt(notiz, "Die Notiz") }
        if let fach { p.klassen[stelle].fach = gekappt(fach, "Das Fach") }
        p.farbeNachziehen(zeile: stelle)
        // Wie bei `ferienNamenSetzen`: Sonst löste schon das Befüllen der Felder
        // beim Erscheinen je Zeile einen Schreibvorgang aus, der die
        // Vorgängerfassung durch eine gleichlautende Kopie verdrängte.
        guard p.klassen[stelle] != vorher else { return }
        planung = p
        sichern()
        if let gekuerztes { kuerzungMelden(gekuerztes) }
    }

    /// Kreuzt einen Unterrichtstag an oder ab. Absichtlich ohne Blick auf die
    /// Vorhaben: Die Angabe hebt im Vorhaben-Dialog Wochentage hervor, sie
    /// weist keinem bestehenden Vorhaben einen Tag zu und nimmt keinem einen.
    func unterrichtstagSetzen(klasse id: String, tag: Wochentag, an: Bool) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
        let vorher = p.klassen[stelle].unterrichtstage
        if an { p.klassen[stelle].unterrichtstage.insert(tag) }
        else { p.klassen[stelle].unterrichtstage.remove(tag) }
        // Ein Klick, der nichts ändert, schreibt nichts — wie `klasseAendern`.
        guard p.klassen[stelle].unterrichtstage != vorher else { return }
        planung = p
        sichern()
    }

    /// Samt der Klassen und Kurse, die das Fach tragen.
    func fachUmbenennen(von alt: String, nach rohNeu: String) {
        guard var p = planung else { return }
        let neu = Planungsspeicher.aufNamenslaenge(rohNeu)
        let alterSchluessel = Farbwelt.fachSchluessel(alt)
        let neuerSchluessel = Farbwelt.fachSchluessel(neu)
        guard alterSchluessel != neuerSchluessel else { return }
        guard !neuerSchluessel.isEmpty else { return }
        // `fachfarben` genügt als Prüfung nicht: Die meisten Fächer hängen an ihren Zeilen.
        guard !p.kenntFach(neu) else {
            melden("„\(neu)“ steht bereits in der Liste.", .warnung)
            return
        }
        if let familie = p.fachfarben.removeValue(forKey: alterSchluessel) {
            p.fachfarben[neuerSchluessel] = familie
        }
        for stelle in p.klassen.indices
        where Farbwelt.fachSchluessel(p.klassen[stelle].fach) == alterSchluessel {
            p.klassen[stelle].fach = neu.trimmingCharacters(in: .whitespaces)
        }
        planung = p
        sichern()
    }

    /// Nur für Fächer ohne Zeile — sonst stünde der Eintrag gleich wieder da.
    func fachEntfernen(_ schluessel: String) {
        guard let p = planung,
              !p.klassen.contains(where: { Farbwelt.fachSchluessel($0.fach) == schluessel })
        else { return }
        fachfarbeSetzen(fach: schluessel, ton: nil)
    }

    /// Setzt oder entfernt eine der beiden Dateien eines Kurses; hinterlegt
    /// wird wie bei den Materialien nur der Verweis.
    func kursdateiSetzen(klasse id: String, art: Kursdateiart, pfad: String?) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else {
            return
        }
        let wert = if let pfad, !pfad.trimmingCharacters(in: .whitespaces).isEmpty {
            Pfade.normalisieren(pfad, basis: p.basis)
        } else {
            ""
        }
        switch art {
        case .verwaltung: p.klassen[stelle].verwaltung = wert
        case .curriculum: p.klassen[stelle].curriculum = wert
        }
        planung = p
        sichern()
    }

    func kursdateiWaehlen(klasse id: String, art: Kursdateiart) {
        guard let gewaehlt = Systemzugriff.dateiWaehlen(start: planung?.basis ?? "",
                                                        titel: art.auswahltitel, zugriff: zugriff)
        else { return }
        kursdateiSetzen(klasse: id, art: art, pfad: gewaehlt)
    }

    func klassenTauschen(_ a: Int, _ b: Int) {
        guard var p = planung, p.klassen.indices.contains(a), p.klassen.indices.contains(b) else { return }
        p.klassen.swapAt(a, b)
        planung = p
        sichern()
    }

    func klasseEntfernen(_ klasse: Klasse) {
        guard let p = planung else { return }
        let anzahl = p.anzahlVorhaben(klasse: klasse.id)
        let frage = anzahl > 0
            ? "„\(klasse.name)“ entfernen? Damit werden auch \(anzahl) Vorhaben gelöscht.\n\nVerknüpfte Dateien bleiben unangetastet."
            : "„\(klasse.name)“ entfernen?"
        fragen(frage, bestaetigung: "Entfernen", gefahr: true, ort: .klassen) { [weak self] in
            guard let self, var p = planung else { return }
            p.klassen.removeAll { $0.id == klasse.id }
            p.eintraege.removeAll { $0.klasseId == klasse.id }
            p.zellenfrei = p.zellenfrei.filter { $0.klasseId != klasse.id }
            // Fällt der letzte Kurs aus einer Sperre, gilt sie wieder für alle.
            for stelle in p.sperrzeiten.indices {
                p.sperrzeiten[stelle].kurse.removeAll { $0 == klasse.id }
            }
            planung = p
            sichern()
        }
    }

    /// Ergänzt nur, was fehlt.
    func standardkurseErgaenzen() {
        guard var p = planung else { return }
        let vorhanden = Set(p.klassen.map { ($0.name + "|" + $0.fach).lowercased() })
        let fehlend = Standardkurse.liste.filter { !vorhanden.contains(($0.name + "|" + $0.fach).lowercased()) }
        guard !fehlend.isEmpty else {
            melden("Die Standardliste ist bereits vollständig angelegt.")
            return
        }
        let platz = Kennwerte.maxKlassen - p.klassen.count
        guard platz > 0 else {
            melden("Kein Platz mehr — es sind höchstens \(Kennwerte.maxKlassen) "
                   + "Klassen/Kurse vorgesehen.", .warnung)
            return
        }
        p.klassen.append(contentsOf: Standardkurse.aufbauen(Array(fehlend.prefix(platz))))
        p.farbenVervollstaendigen()
        planung = p
        sichern()
        let zahl = min(fehlend.count, platz)
        melden("\(zahl) \(zahl == 1 ? "Zeile ergänzt." : "Zeilen ergänzt.")"
               + (fehlend.count > platz ? " \(fehlend.count - platz) passten nicht mehr." : ""))
    }

    // ── Farben ────────────────────────────────────────────────────────────

    func farbeSetzen(klasse id: String, farbe: Int) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
        p.klassen[stelle].farbe = farbe
        p.klassen[stelle].farbeManuell = true
        planung = p
        sichern()
    }

    /// Erst die Farbe holen, dann das Merkmal löschen: Sonst zählte die Zeile
    /// als erste ihres Fachs und folgte ihrer eigenen Handauswahl.
    func farbeDemFachFolgen(klasse id: String) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
        if let farbe = p.fachfarbe(p.klassen[stelle].fach) { p.klassen[stelle].farbe = farbe }
        p.klassen[stelle].farbeManuell = false
        planung = p
        sichern()
    }

    /// Färbt alle Zeilen des Fachs nach — außer denen, deren Farbe von Hand
    /// gesetzt wurde.
    func fachfarbeSetzen(fach schluessel: String, ton: String?) {
        guard var p = planung else { return }
        if let ton, Farbwelt.tonNachSchluessel[ton] != nil {
            // Der Leser kappt bei `maxFachfarben`; ein bereits belegtes Fach
            // darf seine Farbe auch am Rand der Grenze noch wechseln.
            guard p.fachfarben[schluessel] != nil
                    || p.fachfarben.count < Planungsdatei.maxFachfarben else {
                melden("Es sind bereits \(Planungsdatei.maxFachfarben) Fachfarben vergeben.",
                       .warnung)
                return
            }
            p.fachfarben[schluessel] = ton
        } else {
            p.fachfarben.removeValue(forKey: schluessel)
        }

        let betroffen = p.klassen.indices.filter {
            Farbwelt.fachSchluessel(p.klassen[$0].fach) == schluessel && !p.klassen[$0].farbeManuell
        }
        if let farbe = p.fachfarbenWirksam()[schluessel] {
            for stelle in betroffen { p.klassen[stelle].farbe = farbe }
        }
        planung = p
        sichern()
    }

    // ── Prüfungen ─────────────────────────────────────────────────────────

    /// Nach Termin geordnet, ohne Termin ans Ende; innerhalb desselben Tages
    /// nach Kurs, damit die Reihenfolge feststeht.
    var pruefungsliste: [(vorhaben: Vorhaben, klasse: Klasse)] {
        guard let p = planung else { return [] }
        var nachKurs: [String: Klasse] = [:]
        for klasse in p.klassen { nachKurs[klasse.id] = klasse }
        return p.eintraege
            .filter(\.pruefung)
            .compactMap { eintrag in
                nachKurs[eintrag.klasseId].map { (vorhaben: eintrag, klasse: $0) }
            }
            .sorted { a, b in
                switch (a.vorhaben.pruefungstag, b.vorhaben.pruefungstag) {
                case let (x?, y?) where x != y: x < y
                case (nil, _?): false
                case (_?, nil): true
                default: (a.klasse.name, a.vorhaben.anzeigeTitel)
                    < (b.klasse.name, b.vorhaben.anzeigeTitel)
                }
            }
    }

    // ── Heute ─────────────────────────────────────────────────────────────

    /// Was heute ansteht — bei jedem Abruf frisch gerechnet: Der Haken im
    /// Dialog ändert die Planung, eine gehaltene Kopie zeigte den alten Stand.
    var tagesliste: Tagesliste { planung?.tagesliste() ?? Tagesliste() }

    // ── Sperrzeiträume ────────────────────────────────────────────────────

    /// Die eine Stelle, an der die Frage beantwortet wird: Der Dialog fragt sie,
    /// bevor er ein Datum annimmt, das Sichern noch einmal.
    func sperre(am tag: Tag, fuer klasseId: String) -> Sperrzeitraum? {
        planung?.sperre(am: tag, fuer: klasseId)
    }

    /// Entsteht, wenn ein Sperrzeitraum **nachträglich** über einen Termin
    /// gelegt wird. Bestehende Eintragungen bleiben stehen.
    var gesperrteTermine: [(vorhaben: Vorhaben, sperre: Sperrzeitraum)] {
        guard let p = planung else { return [] }
        return p.eintraege.compactMap { eintrag in
            guard eintrag.pruefung, let tag = eintrag.pruefungstag,
                  let sperre = p.sperre(am: tag, fuer: eintrag.klasseId) else { return nil }
            return (eintrag, sperre)
        }
    }

    func sperrzeitHinzufuegen() -> String? {
        guard var p = planung else { return nil }
        let letzte = p.sperrzeiten.map(\.bis).max()
        let montag = (letzte?.plus(tage: 7) ?? p.start).montagDerWoche
        let neu = Sperrzeitraum(id: Kennung.neu("s"), name: "Sperrzeitraum",
                                von: montag, bis: montag.plus(tage: 4))
        p.sperrzeiten.append(neu)
        planung = p
        sichern()
        meldeGesperrteTermine()
        return neu.id
    }

    /// Nur den Namen — wie bei den Ferien (siehe `ferienNamenSetzen`).
    func sperrzeitNamenSetzen(id: String, name: String) {
        guard var p = planung, let stelle = p.sperrzeiten.firstIndex(where: { $0.id == id })
        else { return }
        let gekappt = Planungsspeicher.aufNamenslaenge(name)
        guard p.sperrzeiten[stelle].name != gekappt else { return }
        p.sperrzeiten[stelle].name = gekappt
        planung = p
        sichern()
        if gekappt != name { kuerzungMelden("Die Bezeichnung des Sperrzeitraums") }
    }

    func sperrzeitAendern(_ zeitraum: Sperrzeitraum) {
        guard var p = planung,
              let stelle = p.sperrzeiten.firstIndex(where: { $0.id == zeitraum.id }) else { return }
        p.sperrzeiten[stelle] = zeitraum
        planung = p
        sichern()
        meldeGesperrteTermine()
    }

    /// Leere Liste heißt: für alle. Die Reihenfolge folgt der Kursliste, nicht
    /// der des Anklickens.
    func sperrzeitKurseSetzen(id: String, kurse: Set<String>) {
        guard var p = planung, let stelle = p.sperrzeiten.firstIndex(where: { $0.id == id })
        else { return }
        let geordnet = p.klassen.map(\.id).filter(kurse.contains)
        guard p.sperrzeiten[stelle].kurse != geordnet else { return }
        p.sperrzeiten[stelle].kurse = geordnet
        planung = p
        sichern()
        meldeGesperrteTermine()
    }

    func sperrzeitEntfernen(_ id: String) {
        guard var p = planung else { return }
        p.sperrzeiten.removeAll { $0.id == id }
        planung = p
        sichern()
    }

    private func meldeGesperrteTermine() {
        let betroffen = gesperrteTermine
        guard !betroffen.isEmpty else { return }
        melden(betroffen.count == 1
               ? "Eine bereits eingetragene Prüfung liegt jetzt in einem Sperrzeitraum — "
                 + "sie steht in der Übersicht mit Hinweis."
               : "\(betroffen.count) bereits eingetragene Prüfungen liegen jetzt in einem "
                 + "Sperrzeitraum — sie stehen in der Übersicht mit Hinweis.", .warnung)
    }

    func zeigeVorhaben(_ id: String) {
        guard let p = planung, let eintrag = p.eintraege.first(where: { $0.id == id }) else { return }
        alleDialogeSchliessen()
        anwaehlen(vorhaben: id)
        sprung = Rastersprung(woche: eintrag.woche)
    }

    func pruefungUmschalten(_ id: String) {
        guard var p = planung, let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
        let an = !p.eintraege[stelle].pruefung
        p.eintraege[stelle].pruefung = an
        // Beim Ausschalten den Termin mitnehmen — sonst käme er beim erneuten Einschalten wieder.
        var hinweis: String?
        if an {
            let vorschlag = p.start.montagDerWoche.plus(tage: p.eintraege[stelle].woche * 7)
            if let gesperrt = p.sperre(am: vorschlag, fuer: p.eintraege[stelle].klasseId) {
                p.eintraege[stelle].pruefungstag = nil
                hinweis = gesperrt.abweisung + " Die Prüfung ist ohne Termin eingetragen."
            } else {
                p.eintraege[stelle].pruefungstag = vorschlag
            }
        } else {
            p.eintraege[stelle].pruefungstag = nil
        }
        planung = p
        sichern()
        if let hinweis { melden(hinweis, .warnung) }
    }

    // ── Namenslängen ──────────────────────────────────────────────────────

    /// Kappt eine Bezeichnung auf die Grenze, die `Planungsdatei` beim Lesen
    /// anlegt. Ohne Trimmen: Die Felder schreiben entprellt schon beim Tippen,
    /// ein weggenommenes Leerzeichen stünde gegen das, was im Feld steht.
    private static func aufNamenslaenge(_ wert: String) -> String {
        let sauber = Planungsdatei.ohneSteuerzeichen(wert)
        return sauber.count > Planungsdatei.maxNamenslaenge
            ? String(sauber.prefix(Planungsdatei.maxNamenslaenge)) : sauber
    }

    /// Erst **nach** dem Schreiben zu melden: Die entprellten Felder liefern
    /// den überlangen Wert bei jedem weiteren Tastendruck erneut, und erst der
    /// Vergleich mit dem schon gekappten Stand fängt die Wiederholung ab.
    private func kuerzungMelden(_ feld: String) {
        melden("\(feld) war länger als \(Planungsdatei.maxNamenslaenge) Zeichen "
               + "und wurde gekürzt.", .warnung)
    }
}
