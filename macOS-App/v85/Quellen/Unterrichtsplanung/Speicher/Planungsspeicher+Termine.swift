// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Ein Termin samt Rückläufen, dessen Vorhaben ein Handgriff nahm — bis sein
/// Widerrufen ihn zurückbringt.
struct Terminablage: Sendable {
    let anliegen: Anliegen
    let rueckmeldungen: [Rueckmeldung]
    /// Ein neuer Termin (Dialog, Kopie) statt eines zurückgelegten — für die Meldung.
    var neu = false
}

// ── Termin ↔ Vorhaben an der Sitzung (v80, E293) ──────────────────────────
// Die Planung führt, was sie ändert: Nach jeder Zuweisung zieht der Termin
// nach — Handgriff, Widerrufen, Wiederholen, ein Stand vom iPad. Verschwindet
// in der Sitzung ein Vorhaben, geht sein Termin mit und wird gemerkt; kommt es
// zurück, kommt er mit. Beim Öffnen der Verwaltung wird abgeglichen; ein
// Termin ohne sein Vorhaben verliert nur den Verweis und wird genannt.
extension Planungsspeicher {

    /// Die offene Jahresdatei derselben Planung — sonst nichts zu tun.
    private var terminbestand: (planung: Planung, bestand: Lernendenbestand)? {
        guard lernende.schreibbar, let p = planung, let b = lernende.bestand, b.planung == p.erstellt else { return nil }
        return (p, b)
    }

    /// Nach jeder Zuweisung der Planung. `inSitzung`: ein Handgriff oder eine
    /// Rücknahme — dann zählt, was zwischen den Ständen verschwand oder erschien.
    /// Liefert die Planung, wenn sie nachzuziehen ist: Kommt ein Termin mit
    /// weniger Personen zurück, folgt der Haken seines Vorhabens den Ständen,
    /// statt sie zu überschreiben (Z14a-01) — gesetzt vom Aufrufer im `didSet`.
    @discardableResult
    func termineNachfuehren(von alt: Planung?, inSitzung: Bool) -> Planung? {
        guard inSitzung, let alt else {
            termineAbgleichen()
            return nil
        }
        guard let (p, bestand) = terminbestand else { return nil }
        let jetzt = Zeitrechnung.jetztAlsZeitstempel()
        var neu = bestand
        for k in Terminabgleich.verschwunden(von: alt, zu: p).sorted() {
            guard let a = neu.anliegen.first(where: { $0.id == k && $0.art == .termin }) else { continue }
            terminablage[k] = Terminablage(anliegen: a, rueckmeldungen: neu.rueckmeldungen.filter { $0.anliegen == k })
            neu = neu.ohneAnliegen(k).bestand
        }
        var nichtZurueck: [String] = []
        var nachgezogen = p
        for k in Terminabgleich.erschienen(von: alt, zu: p).sorted() where !neu.anliegen.contains(where: { $0.id == k }) {
            guard let gemerkt = terminablage[k] else { continue }
            guard let zurueck = Self.zurueckgelegt(gemerkt, in: neu) else {
                // Bleibt gemerkt: Mit Platz bringt ein späteres ⌘Z ihn doch (Z14a-04).
                nichtZurueck.append(Self.nichtZurueck(gemerkt, in: neu))
                continue
            }
            terminablage[k] = nil
            neu = zurueck
            guard !gemerkt.neu, let a = neu.anliegen.first(where: { $0.id == k }),
                  let i = nachgezogen.eintraege.firstIndex(where: { $0.termin == k }) else { continue }
            let stattgefunden = Terminabgleich.stattgefunden(a, Lernendenverzeichnis(neu))
            if nachgezogen.eintraege[i].erledigt != stattgefunden {
                nachgezogen.eintraege[i].erledigt = stattgefunden
                nachgezogen.eintraege[i].statusGeaendert = jetzt
            }
        }
        neu = Terminabgleich.ausPlanung(nachgezogen, neu, jetzt: jetzt)
        if neu != bestand, let grund = lernende.setzen(neu) {
            melden("Der Termin ließ sich nicht nachführen: \(grund.satzanfang)", .warnung)
        }
        for text in nichtZurueck { melden(text, .warnung) }
        return nachgezogen == p ? nil : nachgezogen
    }

    /// Beim Öffnen der Verwaltung und bei jedem Wechsel des Schauplatzes:
    /// Planung → Termin; ein Termin, dessen Vorhaben fehlt, verliert nur den
    /// Verweis — gelöscht wird beim Öffnen nichts.
    func termineAbgleichen() {
        guard let (p, bestand) = terminbestand else { return }
        let verwaist = Terminabgleich.verwaiste(p, bestand)
        let neu = Terminabgleich.ausPlanung(p, Terminabgleich.ohneRueckverweis(verwaist, bestand),
                                            jetzt: Zeitrechnung.jetztAlsZeitstempel())
        guard neu != bestand else { return }
        if let grund = lernende.setzen(neu) {
            melden("Die Termine ließen sich nicht abgleichen: \(grund.satzanfang)", .warnung)
            return
        }
        if !verwaist.isEmpty {
            melden(verwaist.count == 1
                   ? "1 Termin hat sein Vorhaben in der Planung verloren und bleibt ohne Vorhaben."
                   : "\(verwaist.count) Termine haben ihr Vorhaben in der Planung verloren und bleiben ohne Vorhaben.",
                   .warnung)
        }
    }

    /// Ein gemerkter Termin zurück — nur mit den Personen, die es noch gibt,
    /// höchstens 40 (E279), und nur, solange die Grenze der Anliegen ihn trägt.
    /// `nil`: Er kommt nicht (W1-05, W1-02) — ein Termin ohne Person entsteht
    /// nie (E295), und über der Grenze ließe sich die Jahresdatei nicht mehr schreiben.
    private static func zurueckgelegt(_ gemerkt: Terminablage, in bestand: Lernendenbestand) -> Lernendenbestand? {
        let personen = Set(bestand.lernende.map(\.id))
        var a = gemerkt.anliegen
        a.betroffene = Array(a.betroffene.filter(personen.contains).prefix(Kennwerte.maxMitgliederJeLerngruppe))
        guard !a.betroffene.isEmpty, bestand.anliegen.count < Lernendendatei.maxAnliegen else { return nil }
        var neu = bestand
        neu.anliegen.append(a)
        neu.rueckmeldungen += gemerkt.rueckmeldungen.filter { a.betroffene.contains($0.lernender) }
        return neu
    }

    /// Warum ein gemerkter Termin nicht kam — das Vorhaben trägt seine Kennzeichnung weiter.
    private static func nichtZurueck(_ gemerkt: Terminablage, in bestand: Lernendenbestand) -> String {
        let personen = Set(bestand.lernende.map(\.id))
        let grund = gemerkt.anliegen.betroffene.contains(where: personen.contains)
            ? "Die Lernendenverwaltung trägt schon \(Lernendendatei.maxAnliegen) Mitteilungen, Maßnahmen und Termine."
            : "Seine Personen gibt es nicht mehr."
        return "Der Termin „\(gemerkt.anliegen.titel)“ \(gemerkt.neu ? "wurde nicht angelegt" : "kam nicht zurück"): "
            + "\(grund) Das Vorhaben bleibt als Termin gekennzeichnet; „Nicht mehr als Termin führen …“ entfernt die "
            + "Kennzeichnung."
    }

    /// Was aus der Kopie eines Vorhabens wurde (E294).
    enum Terminkopie { case keinTermin, termin, ohneTermin }

    /// Die Kopie eines Termin-Vorhabens wird ein eigener Termin (E294): dieselben
    /// Personen, Titel, Uhrzeit und Notiz, Stand offen, derselbe Wochentag in der
    /// Zielwoche. Der neue Termin wird in die Ablage gelegt — das Nachführen nach
    /// dem Einsetzen holt ihn von dort, ⌘Z nimmt ihn wieder mit. Ohne offene
    /// Verwaltung oder ohne Original-Termin bleibt eine gewöhnliche Kopie: ohne
    /// Termin, ohne Tag. `kopie` trägt schon ihre neue Kennung und Zielwoche.
    func terminkopie(_ kopie: inout Vorhaben, vonWoche alt: Int) -> Terminkopie {
        guard kopie.istTermin else { return .keinTermin }
        // An der Grenze der Anliegen — mitgezählt, was diese Kopien schon vorgemerkt haben — bleibt sie gewöhnlich (Z14a-03).
        let vorgemerkt = terminablage.values.filter(\.neu).count
        guard let (p, bestand) = terminbestand, let tag = kopie.datum,
              bestand.anliegen.count + vorgemerkt < Lernendendatei.maxAnliegen,
              let original = bestand.anliegen.first(where: { $0.id == kopie.termin && $0.art == .termin }) else {
            kopie.termin = ""
            kopie.terminzeit = ""
            return .ohneTermin
        }
        var id = Kennung.neu("m")
        while bestand.anliegen.contains(where: { $0.id == id }) || terminablage[id] != nil { id = Kennung.neu("m") }
        let neuerTag = tag.plus(tage: (kopie.woche - alt) * 7)
        let jetzt = Zeitrechnung.jetztAlsZeitstempel()
        var neu = original
        neu.id = id
        neu.datum = neuerTag.iso
        neu.angelegt = jetzt
        neu.geaendert = jetzt
        neu.planung = p.erstellt
        neu.vorhaben = kopie.id
        terminablage[id] = Terminablage(anliegen: neu, rueckmeldungen: [], neu: true)
        kopie.termin = id
        kopie.datum = neuerTag
        kopie.erledigt = false
        return .termin
    }

    /// Die Meldungen nach dem Einsetzen von Kopien (E294).
    func terminkopienMelden(termine: Int, ohneTermin: Int) {
        if termine > 0 {
            melden(termine == 1
                   ? "Die Kopie ist ein eigener Termin für dieselben Personen — am selben Wochentag der neuen Woche."
                   : "\(termine) Kopien sind eigene Termine für dieselben Personen — am selben Wochentag der neuen Woche.")
        }
        if ohneTermin > 0 {
            melden((ohneTermin == 1 ? "Die Kopie ist kein Termin" : "\(ohneTermin) Kopien sind keine Termine")
                   + ": Die Lernendenverwaltung ist nicht offen, der Termin besteht nicht mehr, oder die Grenze der "
                   + "Anliegen ist erreicht.", .warnung)
        }
    }

    // ── Vorhaben → Termin im Dialog (AP13c-2, E295) ───────────────────────

    /// Was das Vorhaben nach dem Dialog am Termin trägt — und, wenn sich die
    /// Personen änderten, ob danach alle stattgefunden haben.
    struct Terminstand {
        var kennung: String
        var zeit: String
        var erledigt: Bool?
    }

    /// Vor dem Schritt: ein neuer Termin über die Ablage (das Nachführen holt
    /// ihn, ⌘Z nimmt ihn mit), geänderte Personen direkt in die Jahresdatei,
    /// höchstens 40 (E279); abgeschaltet bleibt keine Kennung — das Nachführen
    /// nimmt den Termin, auch ohne offene Verwaltung wie im Kontextmenü (W2-02;
    /// der Termin verliert dann beim nächsten Öffnen seinen Verweis). Sonst
    /// bleibt ohne offene Verwaltung der Termin, wie er war.
    func terminVorbereiten(_ entwurf: VorhabenEntwurf, bisher: Vorhaben?, vorhaben: String,
                           titel: String) -> Terminstand {
        let ohne = Terminstand(kennung: "", zeit: "", erledigt: nil)
        guard entwurf.alsTermin else { return ohne }
        guard let (p, bestand) = terminbestand else {
            return Terminstand(kennung: bisher?.termin ?? "", zeit: bisher?.terminzeit ?? "", erledigt: nil)
        }
        guard let tag = entwurf.datum else { return ohne }
        let zeit = Lernendenbestand.uhrzeit(entwurf.terminzeit) ?? ""
        let jetzt = Zeitrechnung.jetztAlsZeitstempel()
        let personen = Array(entwurf.terminpersonen.filter { id in bestand.lernende.contains { $0.id == id } }
            .prefix(Kennwerte.maxMitgliederJeLerngruppe))
        if let k = bisher?.termin, !k.isEmpty, let t = bestand.anliegen.first(where: { $0.id == k && $0.art == .termin }) {
            var neu = bestand
            for person in t.betroffene where !personen.contains(person) { neu = neu.mitBetroffenem(k, person, false, jetzt: jetzt) }
            for person in personen where !t.betroffene.contains(person) { neu = neu.mitBetroffenem(k, person, true, jetzt: jetzt) }
            // Ein im Dialog geänderter Haken wirkt ausdrücklich, mit den Personen von jetzt —
            // nicht erraten aus der Abweichung, die neue Personen verdecken (E298, Z14a-02).
            if entwurf.hakenGeaendert, let jetzig = neu.anliegen.first(where: { $0.id == k }) {
                neu = Terminabgleich.mitHaken(entwurf.erledigt, jetzig, neu, jetzt: jetzt)
            }
            guard neu != bestand else { return Terminstand(kennung: k, zeit: zeit, erledigt: nil) }
            if let grund = lernende.setzen(neu) { melden("Die Personen des Termins ließen sich nicht schreiben: \(grund.satzanfang)", .warnung) }
            let erledigt = neu.anliegen.first { $0.id == k }.map { Terminabgleich.stattgefunden($0, Lernendenverzeichnis(neu)) }
            return Terminstand(kennung: k, zeit: zeit, erledigt: erledigt ?? false)
        }
        var id = Kennung.neu("m")
        while bestand.anliegen.contains(where: { $0.id == id }) || terminablage[id] != nil { id = Kennung.neu("m") }
        terminablage[id] = Terminablage(anliegen: Anliegen(
            id: id, art: .termin, titel: Lernendenbestand.zeile(titel, Lernendendatei.maxTitel), lerngruppe: "",
            betroffene: personen, datum: tag.iso, frist: "", uhrzeit: zeit, notiz: "", angelegt: jetzt, geaendert: jetzt,
            planung: p.erstellt, vorhaben: vorhaben), rueckmeldungen: [], neu: true)
        return Terminstand(kennung: id, zeit: zeit, erledigt: nil)
    }

    /// „Übernehmen“ im Vorhaben-Dialog: Was einem Termin fehlt, sagt die
    /// Meldung; wird ein Termin abgeschaltet, fragt die Rückfrage (E295).
    func vorhabenSichernFragen(_ entwurf: VorhabenEntwurf) {
        if let fehlt = entwurf.terminFehlt(verwaltungOffen: terminbestand != nil) {
            // Auf den Reiter, auf dem sich der Grund beheben lässt (E374, E732).
            if let reiter = entwurf.reiterDesGrundes(verwaltungOffen: terminbestand != nil) { vorhabenReiter = reiter }
            melden(fehlt, .warnung)
            return
        }
        let bisher = entwurf.vorhabenId.flatMap { id in planung?.eintraege.first { $0.id == id } }
        if entwurf.alsTermin, bisher?.istTermin != true, terminbestand == nil {
            melden("Termine gibt es nur mit offener Lernendenverwaltung.", .warnung)
            return
        }
        // Ein neuer Termin über der Grenze der Anliegen ließe die Jahresdatei
        // nicht mehr schreiben (W1-02) — der Dialog bleibt offen.
        if entwurf.alsTermin, bisher.map(hatTermin) != true,
           (lernende.bestand?.anliegen.count ?? 0) >= Lernendendatei.maxAnliegen {
            melden("Höchstens \(Lernendendatei.maxAnliegen) Mitteilungen, Maßnahmen und Termine je Schuljahr — der Termin "
                   + "wurde nicht angelegt.", .warnung)
            return
        }
        guard entwurf.terminAbgeschaltet, let bisher, hatTermin(bisher),
              let termin = lernende.bestand?.anliegen.first(where: { $0.id == bisher.termin }) else {
            vorhabenSichern(entwurf)
            return
        }
        fragen("Den Termin „\(termin.titel)“ in der Lernendenverwaltung löschen?\n\n"
               + "Das Vorhaben bleibt in der Planung. Mit dem Termin gehen die Stände seiner Personen.",
               bestaetigung: "Löschen", gefahr: true, ort: .vorhaben, nachDemSchliessen: true) { [weak self] in
            self?.vorhabenSichern(entwurf)
        }
    }

    /// Ob sich Vorhaben dieser Planung als Termin kennzeichnen lassen (E296).
    var termineMoeglich: Bool { terminbestand != nil }

    /// Aus dem Kontextmenü (E296): „Nicht mehr als Termin führen …“ — mit derselben
    /// Rückfrage wie im Dialog; der Termin geht mit, ⌘Z bringt beide.
    func terminkennzeichnungEntfernenFragen(_ id: String) {
        guard let v = planung?.eintraege.first(where: { $0.id == id }), v.istTermin else { return }
        let entfernen: @MainActor () -> Void = { [weak self] in
            self?.aendern(Schrittname.terminkennzeichnungEntfernen) { p in
                guard let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
                p.eintraege[stelle].termin = ""
                p.eintraege[stelle].terminzeit = ""
            }
        }
        guard hatTermin(v), let termin = lernende.bestand?.anliegen.first(where: { $0.id == v.termin }) else {
            entfernen()
            return
        }
        fragen("Den Termin „\(termin.titel)“ in der Lernendenverwaltung löschen?\n\n"
               + "Das Vorhaben bleibt in der Planung. Mit dem Termin gehen die Stände seiner Personen.",
               bestaetigung: "Löschen", gefahr: true, ort: .hauptansicht, nachDemSchliessen: true) { entfernen() }
    }

    /// Ob ein Vorhaben ein Termin der offenen Verwaltung ist — für die Rückfrage.
    func hatTermin(_ vorhaben: Vorhaben) -> Bool {
        vorhaben.istTermin && lernende.bestand?.anliegen.contains { $0.id == vorhaben.termin && $0.art == .termin } == true
    }

    /// Ob ein Termin ein Vorhaben in der Planung hat — für die Rückfrage im Blatt.
    func hatVorhaben(_ termin: String) -> Bool {
        planung?.eintraege.contains { $0.termin == termin } == true
    }

    /// „Übernehmen“ des Blatts mit den Terminen: erst die Jahresdatei samt
    /// Rückverweisen, dann die Planung als ein Schritt „Termine übernehmen“ —
    /// so findet das Nachführen danach beide Seiten gleich. Die Wünsche
    /// (neue Termine, die ein Vorhaben bekommen sollen) trägt der Stand selbst
    /// (W3-03); geschrieben wird er ohne sie.
    func termineUebernehmen(_ entwurf: Lernendenbestand, ausgang: Lernendenbestand? = nil,
                            herkunftVersucht: Bool = false) -> String? {
        let (wuensche, ohneWuensche) = entwurf.terminwuensche
        var neu = ohneWuensche
        let sitzung = lernende.bestand
        // Die erste Jahresdatei bindet sich an die Herkunft der Planung — die steht vorher auf der Platte (W1-06, A4).
        // Gelingt das nicht, gilt der Stand trotzdem für die Sitzung — gesagt, nicht verworfen (Z14c-01).
        if !herkunftVersucht, lernende.schreibbar, sitzung == nil, let p = planung, neu.planung == p.erstellt,
           herkunftSichern() != nil {
            melden("Die Herkunft der Planung steht noch nicht auf der Platte, weil sich die Planung nicht sichern ließ — "
                   + "die Lernendendaten finden erst nach einer gelungenen Sicherung der Planung verlässlich zu ihr zurück.",
                   .warnung)
        }
        // Was das Blatt an Terminen nicht anfasste, behält den Stand der Sitzung (offener Punkt 3).
        if let ausgang, let sitzung {
            neu = Terminabgleich.mitStandDerSitzung(neu, ausgang: ausgang.terminwuensche.bestand, sitzung: sitzung)
        }
        // Ein geänderter Bestand trägt den Stempel der Änderung (W1-09) — auch eine, die erst
        // der Abgleich mit der Planung bringt, etwa ein Rückverweis (Z14c-07).
        func gestempelt(_ b: Lernendenbestand) -> Lernendenbestand {
            guard let sitzung, b != sitzung else { return b }
            var gestempelt = b
            gestempelt.geaendert = Zeitrechnung.jetztAlsZeitstempel()
            return gestempelt
        }
        // Endgültig gelöschte Personen lassen ihre Tische los (E304) — der Name am Tisch bleibt. Wer eine Lerngruppe
        // verließ, verlässt die Sitzpläne ihrer Zeilen; geänderte Namen folgen an gebundenen Tischen (E367, E390).
        let geloescht = Set(sitzung?.lernende.map(\.id) ?? []).subtracting(neu.lernende.map(\.id))
        let folgen = sitzung.map { Sitzplanfolgen(vorher: $0, nachher: neu, planung: planung?.erstellt) }
        defer {
            sitzplaene.bindungenLoesen(geloescht)
            if let folgen { sitzplanfolgenAnwenden(folgen) }
        }
        guard let p = planung, neu.planung == p.erstellt, lernende.schreibbar else { return lernende.setzen(gestempelt(neu)) }
        let vorher = lernende.bestand ?? .leer(planung: neu.planung, schuljahr: neu.schuljahr, jetzt: neu.erstellt)
        let u = Terminabgleich.inPlanung(p, vorher: vorher, nachher: neu, wuensche: wuensche,
                                         jetzt: Zeitrechnung.jetztAlsZeitstempel())
        for k in u.entfernt {
            guard let a = vorher.anliegen.first(where: { $0.id == k }) else { continue }
            terminablage[k] = Terminablage(anliegen: a, rueckmeldungen: vorher.rueckmeldungen.filter { $0.anliegen == k })
        }
        // Was die Platte nicht trägt, gilt für die Sitzung — die Planung folgt
        // ihm trotzdem, sonst zeigten Termine auf Vorhaben, die es nicht gibt (W2-01).
        let grund = lernende.setzen(gestempelt(u.bestand))
        if u.planung != p { aendern(Schrittname.termineUebernehmen) { $0 = u.planung } }
        if u.ausserhalb > 0 {
            melden(u.ausserhalb == 1
                   ? "1 Termin liegt außerhalb der Planung: Ein neuer wird im Raster nicht eingetragen, ein verbundener "
                     + "behält den Tag seines Vorhabens."
                   : "\(u.ausserhalb) Termine liegen außerhalb der Planung: Neue werden im Raster nicht eingetragen, "
                     + "verbundene behalten den Tag ihres Vorhabens.", .warnung)
        }
        return grund
    }
}
