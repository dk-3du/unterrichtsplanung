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
        aendern(Schrittname.planungstitelAendern, kennung: "titel") { $0.titel = gekappt }
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
            guard let self, planung != nil else { return }
            aendern(Schrittname.einstellungenUebernehmen) { p in
                p.start = start.montagDerWoche
                p.wochen = anzahl
                p.ersterSchultag = ersterSchultag
                p.eintraege.removeAll { $0.woche >= anzahl }
                // `frei` und `zellenfrei` bleiben stehen wie `ferien` und
                // `sperrzeiten`: Sie hängen am Montagsdatum, nicht am Spaltenindex,
                // werden nur über die Wochenliste nachgeschlagen und sind
                // gedeckelt. Gefiltert verschwänden sie beim bloßen Verschieben des
                // Starts still und wären nicht zurückzuholen.

            }
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
        let frei = planung?.frei.contains(woche.montag) == true
        aendern(frei ? Schrittname.wocheUnterricht : Schrittname.wocheFrei) { p in
            if p.frei.contains(woche.montag) { p.frei.remove(woche.montag) }
            else { p.frei.insert(woche.montag) }
        }
    }

    func zelleFreiSchalten(klasse: String, woche: Woche) {
        let zelle = FreieZelle(klasseId: klasse, woche: woche.montag)
        let frei = planung?.zellenfrei.contains(zelle) == true
        aendern(frei ? Schrittname.zelleUnterricht : Schrittname.zelleFrei) { p in
            if p.zellenfrei.contains(zelle) { p.zellenfrei.remove(zelle) }
            else { p.zellenfrei.insert(zelle) }
        }
    }

    @discardableResult
    func ferienHinzufuegen() -> String? {
        guard let p = planung else { return nil }
        let letzte = p.ferien.map(\.bis).max()
        let start = letzte?.plus(tage: 7) ?? p.start
        let montag = start.montagDerWoche
        let neu = Ferienzeitraum(id: Kennung.neu("f"), name: "Ferien",
                                 von: montag, bis: montag.plus(tage: 4))
        aendern(Schrittname.ferienHinzufuegen) { $0.ferien.append(neu) }
        return neu.id
    }

    /// Nur den Namen: Ein entprellter Schreibvorgang trüge sonst den alten
    /// Zeitraum mit sich und nähme eine Datumsänderung zurück.
    func ferienNamenSetzen(id: String, name: String) {
        let gekappt = Planungsspeicher.aufNamenslaenge(name)
        aendern(Schrittname.ferienUmbenennen, kennung: id) { p in
            guard let stelle = p.ferien.firstIndex(where: { $0.id == id }) else { return }
            p.ferien[stelle].name = gekappt
        }
        if gekappt != name { kuerzungMelden("Die Bezeichnung des Ferienzeitraums") }
    }

    func ferienAendern(_ zeitraum: Ferienzeitraum) {
        // Mit Kennung: Ein Datumsfeld meldet beim Ziehen mehrfach (B12).
        aendern(Schrittname.ferienAendern, kennung: zeitraum.id) { p in
            guard let stelle = p.ferien.firstIndex(where: { $0.id == zeitraum.id }) else { return }
            p.ferien[stelle] = zeitraum
        }
    }

    func ferienEntfernen(_ id: String) {
        aendern(Schrittname.ferienEntfernen) { $0.ferien.removeAll { $0.id == id } }
    }

    // ── Klassen ───────────────────────────────────────────────────────────

    /// Liefert die Kennung, damit die Liste die Schreibmarke gleich in das
    /// Namensfeld setzen kann.
    @discardableResult
    func klasseHinzufuegen() -> String? {
        guard let p = planung else { return nil }
        guard p.klassen.count < Kennwerte.maxKlassen else {
            melden("Mehr als \(Kennwerte.maxKlassen) Klassen/Kurse sind nicht vorgesehen.",
                   .warnung)
            return nil
        }
        let neu = Klasse(
            id: Kennung.neu("k"), name: "", fach: "", notiz: "",
            farbe: Farbwelt.ohneFarbe, farbeManuell: false)
        aendern(Schrittname.kursHinzufuegen) { p in
            p.klassen.append(neu)
            p.farbenVervollstaendigen()
        }
        return neu.id
    }

    /// Die Fachfarbe zieht nach, solange sie nicht von Hand gesetzt wurde.
    /// Das Fachfeld ist entprellt und meldet auch Halbgetipptes („Mat“) — das
    /// darf nichts hinterlassen, deshalb entscheidet allein `farbeNachziehen`.
    func klasseAendern(id: String, name: String? = nil, fach: String? = nil, notiz: String? = nil) {
        // Je Feld ein Schritt, und je Feld eine eigene Schreibphase: Wer die
        // Bezeichnung tippt und dann das Fach, hat zwei Schritte, nicht zwölf.
        let feld = switch (name, fach, notiz) {
        case (.some, nil, nil): Schrittname.bezeichnungAendern
        case (nil, .some, nil): Schrittname.fachAendern
        case (nil, nil, .some): Schrittname.notizAendern
        default: Schrittname.kursAendern
        }
        // Der Leser kappt Bezeichnung, Fach und Notiz auf `maxNamenslaenge`;
        // ungekappt geschrieben verschwände der Überhang beim nächsten Start.
        var gekuerztes: String?
        func gekappt(_ wert: String?, _ feld: String) -> String? {
            guard let wert else { return nil }
            let kurz = Planungsspeicher.aufNamenslaenge(wert)
            if kurz != wert { gekuerztes = feld }
            return kurz
        }
        let neueBezeichnung = gekappt(name, "Die Bezeichnung")
        let neueNotiz = gekappt(notiz, "Die Notiz")
        let neuesFach = gekappt(fach, "Das Fach")
        aendern(feld, kennung: id + "·" + feld) { p in
            guard let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
            if let neueBezeichnung { p.klassen[stelle].name = neueBezeichnung }
            if let neueNotiz { p.klassen[stelle].notiz = neueNotiz }
            if let neuesFach { p.klassen[stelle].fach = neuesFach }
            p.farbeNachziehen(zeile: stelle)
        }
        // Ein Schreibvorgang, der nichts ändert, entsteht hier gar nicht mehr:
        // `aendern` vergleicht und lässt es dann. Früher verdrängte schon das
        // Befüllen der Felder beim Erscheinen die Vorgängerfassung.
        if let gekuerztes { kuerzungMelden(gekuerztes) }
    }

    /// Kreuzt einen Unterrichtstag an oder ab. Absichtlich ohne Blick auf die
    /// Vorhaben: Die Angabe hebt im Vorhaben-Dialog Wochentage hervor, sie
    /// weist keinem bestehenden Vorhaben einen Tag zu und nimmt keinem einen.
    func unterrichtstagSetzen(klasse id: String, tag: Wochentag, an: Bool) {
        aendern(an ? Schrittname.unterrichtstagHinzufuegen : Schrittname.unterrichtstagEntfernen) { p in
            guard let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
            if an { p.klassen[stelle].unterrichtstage.insert(tag) }
            else { p.klassen[stelle].unterrichtstage.remove(tag) }
        }
    }

    /// Samt der Klassen und Kurse, die das Fach tragen.
    func fachUmbenennen(von alt: String, nach rohNeu: String) {
        guard let bestand = planung else { return }
        var p = bestand
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
        aendern(Schrittname.fachUmbenennen, kennung: alterSchluessel) { $0 = p }
    }

    /// Nur für Fächer ohne Zeile — sonst stünde der Eintrag gleich wieder da.
    func fachEntfernen(_ schluessel: String) {
        guard let p = planung,
              !p.klassen.contains(where: { Farbwelt.fachSchluessel($0.fach) == schluessel })
        else { return }
        farbeSchreiben(fach: schluessel, ton: nil, name: Schrittname.fachEntfernen)
    }

    /// Setzt oder entfernt eine der beiden Dateien eines Kurses; hinterlegt
    /// wird wie bei den Materialien nur der Verweis.
    func kursdateiSetzen(klasse id: String, art: Kursdateiart, pfad: String?) {
        guard let basis = planung?.basis else { return }
        let wert = if let pfad, !pfad.trimmingCharacters(in: .whitespaces).isEmpty {
            Pfade.normalisieren(pfad, basis: basis)
        } else {
            ""
        }
        // Vier Wortlaute statt zusammengesetzter: Sie stehen im Menü, und der
        // Katalog trägt nur, was er auch sieht.
        let name = switch (art, wert.isEmpty) {
        case (.verwaltung, true): Schrittname.verwaltungsdateiEntfernen
        case (.verwaltung, false): Schrittname.verwaltungsdateiHinterlegen
        case (.curriculum, true): Schrittname.curriculumEntfernen
        case (.curriculum, false): Schrittname.curriculumHinterlegen
        }
        aendern(name) { p in
            guard let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
            switch art {
            case .verwaltung: p.klassen[stelle].verwaltung = wert
            case .curriculum: p.klassen[stelle].curriculum = wert
            }
        }
    }

    func kursdateiWaehlen(klasse id: String, art: Kursdateiart) {
        guard let gewaehlt = Systemzugriff.dateiWaehlen(start: planung?.basis ?? "",
                                                        titel: art.auswahltitel, zugriff: zugriff)
        else { return }
        kursdateiSetzen(klasse: id, art: art, pfad: gewaehlt)
    }

    func klassenTauschen(_ a: Int, _ b: Int) {
        aendern(Schrittname.kurseUmstellen) { p in
            guard p.klassen.indices.contains(a), p.klassen.indices.contains(b) else { return }
            p.klassen.swapAt(a, b)
        }
    }

    func klasseEntfernen(_ klasse: Klasse) {
        guard let p = planung else { return }
        let anzahl = p.anzahlVorhaben(klasse: klasse.id)
        var frage = anzahl > 0
            ? "„\(klasse.name)“ entfernen? Damit werden auch \(anzahl) Vorhaben gelöscht.\n\nVerknüpfte Dateien bleiben unangetastet."
            : "„\(klasse.name)“ entfernen?"
        // Der Sitzplan hängt an der Klasse — die Rückfrage nennt ihn. Er liegt
        // außerhalb der Planung und hat seinen eigenen Schauplatz (E82); damit
        // ein Widerrufen nicht den Kurs zurückbrächte und den Sitzplan nicht,
        // reist er als Beiwerk des Schrittes mit.
        if sitzplaene.plan(fuer: klasse.id) != nil {
            frage += anzahl > 0 ? " Der Sitzplan der Klasse wird mit entfernt."
                                : "\n\nDer Sitzplan der Klasse wird mit entfernt."
        }
        fragen(frage, bestaetigung: "Entfernen", gefahr: true, ort: .klassen) { [weak self] in
            guard let self, var p = planung else { return }
            // Vor dem Entfernen greifen: Danach ist er fort.
            let gewesenerSitzplan = sitzplaene.plan(fuer: klasse.id)
            sitzplaene.entfernen(klassen: [klasse.id])
            p.klassen.removeAll { $0.id == klasse.id }
            p.eintraege.removeAll { $0.klasseId == klasse.id }
            p.zellenfrei = p.zellenfrei.filter { $0.klasseId != klasse.id }
            // Fällt der letzte Kurs aus einer Sperre, gilt sie wieder für alle.
            for stelle in p.sperrzeiten.indices {
                p.sperrzeiten[stelle].kurse.removeAll { $0 == klasse.id }
            }
            let beiwerk = gewesenerSitzplan.map { plan in
                Ruecknahme<Planung>.Beiwerk(
                    moeglich: { [weak self] in
                        guard let self else { return "die Planung ist fort" }
                        return sitzplaene.schreibbar ? nil
                            : (sitzplaene.sperrhinweis ?? "die Sitzpläne sind gesperrt")
                    },
                    zurueck: { [weak self] in self?.sitzplanZurueck(plan, fuer: klasse.id) },
                    vor: { [weak self] in self?.sitzplaene.entfernen(klassen: [klasse.id]) })
            }
            aendern(Schrittname.kursEntfernen, beiwerk: beiwerk) { $0 = p }
        }
    }

    /// Den Sitzplan einer zurückgeholten Klasse wieder hinlegen. Gelingt das
    /// Schreiben nicht (gesperrte Ablage, offener Übergang), gilt er für diese
    /// Sitzung und wird nachgeholt — wie jeder Sitzplan, der noch nicht liegt.
    func sitzplanZurueck(_ plan: Sitzplan, fuer klasseId: String) {
        // Dass die Sitzpläne beschreibbar sind, hat `Beiwerk.moeglich` schon
        // gefragt; bleibt der Fall, dass das Schreiben selbst noch aussteht.
        guard let grund = sitzplaene.setzen(plan, fuer: klasseId) else { return }
        melden("Der Sitzplan ist zurück, liegt aber noch nicht auf der Platte (\(grund)) — "
               + "die App versucht es beim nächsten Schreiben erneut.", .warnung)
    }

    /// Ergänzt nur, was fehlt.
    func standardkurseErgaenzen() {
        guard let p = planung else { return }
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
        let zeilen = Standardkurse.aufbauen(Array(fehlend.prefix(platz)))
        aendern(Schrittname.standardlisteErgaenzen) { p in
            p.klassen.append(contentsOf: zeilen)
            p.farbenVervollstaendigen()
        }
        let zahl = min(fehlend.count, platz)
        melden("\(zahl) \(zahl == 1 ? "Zeile ergänzt." : "Zeilen ergänzt.")"
               + (fehlend.count > platz ? " \(fehlend.count - platz) passten nicht mehr." : ""))
    }

    // ── Farben ────────────────────────────────────────────────────────────

    func farbeSetzen(klasse id: String, farbe: Int) {
        aendern(Schrittname.farbeWaehlen, kennung: id) { p in
            guard let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
            p.klassen[stelle].farbe = farbe
            p.klassen[stelle].farbeManuell = true
        }
    }

    /// Erst die Farbe holen, dann das Merkmal löschen: Sonst zählte die Zeile
    /// als erste ihres Fachs und folgte ihrer eigenen Handauswahl.
    func farbeDemFachFolgen(klasse id: String) {
        aendern(Schrittname.farbeDemFachFolgen) { p in
            guard let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
            if let farbe = p.fachfarbe(p.klassen[stelle].fach) { p.klassen[stelle].farbe = farbe }
            p.klassen[stelle].farbeManuell = false
        }
    }

    /// Färbt alle Zeilen des Fachs nach — außer denen, deren Farbe von Hand
    /// gesetzt wurde.
    func fachfarbeSetzen(fach schluessel: String, ton: String?) {
        farbeSchreiben(fach: schluessel, ton: ton,
                       name: ton == nil ? Schrittname.fachfarbeEntfernen : Schrittname.fachfarbeWaehlen)
    }

    private func farbeSchreiben(fach schluessel: String, ton: String?, name: String) {
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
        aendern(name, kennung: schluessel) { $0 = p }
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
        guard let p = planung else { return nil }
        let letzte = p.sperrzeiten.map(\.bis).max()
        let montag = (letzte?.plus(tage: 7) ?? p.start).montagDerWoche
        let neu = Sperrzeitraum(id: Kennung.neu("s"), name: "Sperrzeitraum",
                                von: montag, bis: montag.plus(tage: 4))
        aendern(Schrittname.sperrzeitHinzufuegen) { $0.sperrzeiten.append(neu) }
        meldeGesperrteTermine()
        return neu.id
    }

    /// Nur den Namen — wie bei den Ferien (siehe `ferienNamenSetzen`).
    func sperrzeitNamenSetzen(id: String, name: String) {
        let gekappt = Planungsspeicher.aufNamenslaenge(name)
        aendern(Schrittname.sperrzeitUmbenennen, kennung: id) { p in
            guard let stelle = p.sperrzeiten.firstIndex(where: { $0.id == id }) else { return }
            p.sperrzeiten[stelle].name = gekappt
        }
        if gekappt != name { kuerzungMelden("Die Bezeichnung des Sperrzeitraums") }
    }

    func sperrzeitAendern(_ zeitraum: Sperrzeitraum) {
        aendern(Schrittname.sperrzeitAendern, kennung: zeitraum.id) { p in
            guard let stelle = p.sperrzeiten.firstIndex(where: { $0.id == zeitraum.id }) else { return }
            p.sperrzeiten[stelle] = zeitraum
        }
        meldeGesperrteTermine()
    }

    /// Leere Liste heißt: für alle. Die Reihenfolge folgt der Kursliste, nicht
    /// der des Anklickens.
    func sperrzeitKurseSetzen(id: String, kurse: Set<String>) {
        aendern(Schrittname.sperrzeitKurse, kennung: id) { p in
            guard let stelle = p.sperrzeiten.firstIndex(where: { $0.id == id }) else { return }
            p.sperrzeiten[stelle].kurse = p.klassen.map(\.id).filter(kurse.contains)
        }
        meldeGesperrteTermine()
    }

    func sperrzeitEntfernen(_ id: String) {
        aendern(Schrittname.sperrzeitEntfernen) { $0.sperrzeiten.removeAll { $0.id == id } }
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
        let name = an ? Schrittname.alsPruefungFuehren : Schrittname.pruefungEntfernen
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
        aendern(name) { $0 = p }
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
