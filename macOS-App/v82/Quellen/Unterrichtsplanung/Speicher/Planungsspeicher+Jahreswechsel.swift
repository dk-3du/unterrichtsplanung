// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Der Schuljahreswechsel (v80, E246, E271, E275, E277) ──────────────────
extension Planungsspeicher {

    /// „Neue Planung“ über einer bisherigen: Ohne eingeschaltete
    /// Verschlüsselung gibt es kein Archiv — die App sagt das vorher und
    /// bietet an, sie zuerst einzuschalten (E275). Mit Verschlüsselung oder
    /// ohne bisherige Planung wird gleich angelegt.
    func neuePlanungFragen(ort: Rueckfrageort = .hauptansicht, _ anlegen: @escaping @MainActor () -> Void) {
        guard tresor == nil, let bisherige = planung else {
            anlegen()
            return
        }
        // Das Blatt „Verschlüsselung“ löst „Neue Planung“ ab; dessen Eingaben gehen (E302, W3-04).
        fragen("Die bisherige Planung „\(bisherige.titel)“ wird nur mit eingeschalteter Verschlüsselung archiviert — "
               + "ohne sie ersetzt die neue Planung die bisherige, wie bisher. Mit dem Einrichten der Verschlüsselung "
               + "beginnt das Anlegen einer neuen Planung ohne Übernahme der bisherigen Eingaben.\n\nZuerst die "
               + "Verschlüsselung einrichten oder ohne Archiv fortfahren?",
               bestaetigung: "Ohne Archiv fortfahren", gefahr: true, ort: ort,
               weitere: "Verschlüsselung einrichten …",
               beiWeitere: { [weak self] in self?.dialogOeffnen(.verschluesselung) },
               nachDemSchliessen: true, handlung: anlegen)
    }

    /// Die Personen der Jahresdatei — vor einem Wechsel gemerkt.
    var lernendenKennungen: Set<String> { Set(lernende.bestand?.lernende.map(\.id) ?? []) }

    /// Nach einem gelungenen Wechsel: Wen die neue Jahresdatei nicht trägt, lässt
    /// seine Tische los, der Name bleibt (E304, Z14c-04). Gerufen nach dem
    /// Umschreiben bzw. Aufräumen der Sitzpläne (Z14c-10). Nur Pläne der Klassen der
    /// Planung — verwaiste, deren Rettungskopie scheiterte, bleiben (Z-AS5a-10).
    func bindungenNachWechselLoesen(_ bisherige: Set<String>) {
        sitzplaene.bindungenLoesen(bisherige.subtracting(lernendenKennungen),
                                   in: planung.map { Set($0.klassen.map(\.id)) })
    }

    /// „Archivieren und öffnen“ im Blatt „Neues Schuljahr öffnen“ (E305) —
    /// `ziele`: Name und Zeile je Gruppe (E308, E310).
    func schuljahrOeffnen(gruppen: Set<String>, ziele: [String: Gruppenziel] = [:]) {
        guard let wechsel = schuljahrwechsel else { return }
        schuljahrwechsel = nil
        if offenerDialog == .schuljahrOeffnen { offenerDialog = nil }
        wechsel.oeffnen(gruppen, ziele)
    }

    /// Das Schuljahr der Jahresdatei — ohne Eintrag das der Planung (E307).
    var bisherigesSchuljahr: String {
        if let s = lernende.bestand?.schuljahr, !s.isEmpty { return s }
        return planung.map { Lernendenbestand.schuljahr(fuer: $0.start) } ?? ""
    }

    /// Die Lerngruppen, die ins neue Schuljahr wählbar sind — in der Folge,
    /// in der die Blätter sie zeigen und die Zuteilung sie bedient (E311).
    var lerngruppenZurWahl: [Lerngruppe] {
        // Eindeutig: Bei gleichem Namen entscheidet die Folge, wer eine Zeile bekommt.
        (lernende.bestand?.lerngruppen ?? []).filter { $0.archiviert.isEmpty }.sorted(by: Lerngruppe.vorgehen)
    }

    /// Was das Blatt „Neues Schuljahr öffnen“ zum Hochstufen und Zuordnen
    /// braucht (E307–E311): die Schuljahre und Stufen, die Zeilen der
    /// geöffneten Planung, je Gruppe die gleichnamige Zeile (E277) und die
    /// Gruppen, für die sich eine Zeile findet — mit den Namen, die der
    /// Schalter vorgibt.
    func hochstufungsvorgabe(zu geladen: Planung, zuordnung: [String: String]) -> Schuljahrwechsel.Vorgabe {
        let bisher = bisherigesSchuljahr
        let neu = Lernendenbestand.schuljahr(fuer: geladen.start)
        let stufen = Hochstufung.stufen(von: bisher, zu: neu) ?? 0
        let gruppen = lerngruppenZurWahl
        let zeilen = geladen.klassen.map { Hochstufung.Zeile($0) }
        let herkunft = lernende.bestand?.planung ?? ""
        var uebernommen: [String: String] = [:]
        var namen: [String: String] = [:]
        for g in gruppen {
            uebernommen[g.id] = Hochstufung.uebernommeneZeile(g, planung: herkunft, zuordnung: zuordnung)
            namen[g.id] = Hochstufung.name(g.name, um: stufen)
        }
        let zuteilung = Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: uebernommen, zeilen: zeilen,
                                              gewaehlt: [:])
        return .init(bisherigesSchuljahr: bisher, neuesSchuljahr: neu, stufen: stufen, zeilen: zeilen,
                     uebernommen: uebernommen, vorgabe: Set(zuteilung.keys))
    }

    /// „Abbrechen“ im Blatt „Neues Schuljahr öffnen“: nichts geschieht (E305).
    func schuljahrOeffnenAbbrechen() {
        schuljahrwechsel = nil
        if offenerDialog == .schuljahrOeffnen { offenerDialog = nil }
    }

    /// Die Lerngruppen, die ohne eigene Wahl mitgehen: die, deren Zeile der
    /// laufenden Planung übernommen wird (E271) — wenn das Blatt keine Wahl mitgibt.
    func lerngruppenDerUebernahme(_ zuordnung: [String: String]) -> Set<String> {
        lerngruppenVorgabe(fuerZeilen: Set(zuordnung.keys))
    }

    /// Die Gruppen, deren Zeile übernommen wird — die Vorgabe im Blatt „Neue
    /// Planung“, ehe von Hand gewählt wird (E271).
    func lerngruppenVorgabe(fuerZeilen zeilen: Set<String>) -> Set<String> {
        guard let bestand = lernende.bestand else { return [] }
        return Set(bestand.lerngruppen.filter { gruppe in
            gruppe.archiviert.isEmpty
                && gruppe.zeilen.contains { $0.planung == bestand.planung && zeilen.contains($0.klasseId) }
        }.map(\.id))
    }

    /// Zeilen zweier Planungen, die zueinander passen — gleicher Name, gleiches
    /// Fach, gleiche Art, und nur eindeutige Paare. Für ⌘O, wo keine Übernahme
    /// die Zuordnung liefert (E277).
    static func zuordnungNachNamen(von alt: Planung, zu neu: Planung) -> [String: String] {
        func schluessel(_ k: Klasse) -> String {
            [k.name, k.fach, k.art.rawValue].map { $0.lowercased() }.joined(separator: "\u{1F}")
        }
        var neuNach: [String: [String]] = [:]
        for k in neu.klassen { neuNach[schluessel(k), default: []].append(k.id) }
        var altNach: [String: [String]] = [:]
        for k in alt.klassen { altNach[schluessel(k), default: []].append(k.id) }
        var zuordnung: [String: String] = [:]
        for (s, alte) in altNach where alte.count == 1 {
            if let neue = neuNach[s], neue.count == 1 { zuordnung[alte[0]] = neue[0] }
        }
        return zuordnung
    }

    /// Der Schuljahreswechsel (E246): Die bisherige Planung geht samt ihrer
    /// Jahresdatei ins Archiv, `neue` wird die Planung, die neue Jahresdatei
    /// trägt die gewählten Gruppen (E271) — Planung, Jahresdatei und Archiv in
    /// **einem** Übergang (`jahreswechsel`), alle oder keine. Die Generation
    /// nimmt die Planung aus der Sitzung; misslingt der Übergang, kehrt die
    /// bisherige zurück. Nur mit eingeschalteter Verschlüsselung. `nil`: gelungen.
    func jahreswechsel(zu neue: Planung, zuordnung: [String: String], gruppen: Set<String>,
                       ziele: [String: Gruppenziel] = [:]) -> String? {
        guard let tresor, let alt = planung else { return "keine verschlüsselte Planung geladen" }
        if let grund = schutzuebergangGesperrt { return grund }
        guard lernende.schreibbar else {
            return (lernende.sperrhinweis ?? "die Lernendenverwaltung ist nicht offen").ohneSchlusspunkt
        }
        let jetzt = Zeitrechnung.jetztAlsZeitstempel()
        let stempel = Zeitrechnung.dateistempel()
        let archiv: Archivbestand
        switch lernende.archivLesen(stempel: stempel) {
        case .gelesen(let gelesen, _, _): archiv = gelesen
        case .nichtLesbar(let grund): return "das Archiv lässt sich nicht lesen (\(grund.ohneSchlusspunkt))"
        }
        let bisherige = lernende.bestand
        let neuesArchiv = archiv.mitJahr(planung: alt, lernende: bisherige, jetzt: jetzt)
        let neuesJahr = (bisherige ?? .leer(planung: alt.erstellt, schuljahr: "", jetzt: jetzt))
            .neuesJahr(gruppen: gruppen, zuordnung: zuordnung, planung: neue.erstellt,
                       schuljahr: Lernendenbestand.schuljahr(fuer: neue.start), jetzt: jetzt,
                       ziele: ziele, zeilen: neue.klassen)
        var dateien: [String: Uebergangsdienst.Inhalt] = [:]
        do {
            dateien[sicherung.ablage.lernende.lastPathComponent] = .daten(try lernende.jahresdatei(neuesJahr))
            dateien[sicherung.ablage.archiv.lastPathComponent] = .daten(try lernende.archivdatei(neuesArchiv))
        } catch {
            return error.localizedDescription.ohneSchlusspunkt
        }
        // Die neue Planung in die Sitzung — die Generation nimmt sie von dort. Vorläufig:
        // Scheitert der Wechsel, gilt die bisherige samt ihrem Verlauf (W2-09).
        planungVorlaeufigSetzen(neue)
        if let grund = jahreswechselEinsetzen(tresor: tresor, dateien: dateien) {
            planungVorlaeufigSetzen(alt)
            return grund
        }
        schauplatzGewechselt()
        lernende.nachJahreswechsel(neuesJahr)
        return nil
    }

    /// Vorbereiten, Übergeben, Einsetzen — derselbe Übergabestand wie beim
    /// Schutz, unter demselben Schlüssel. `nil`: Die Marke liegt, der neue
    /// Stand gilt (ein unvollendetes Einsetzen vollendet jeder Anlass).
    private func jahreswechselEinsetzen(tresor: Tresor, dateien: [String: Uebergangsdienst.Inhalt]) -> String? {
        var alle = dateien
        let generation: (dateien: [String: Data], bilanz: Ablage.Nebendateienbilanz, nummer: Int, stand: String, abdruck: Data)
        do {
            generation = try sicherung.generationErzeugen(neu: tresor, alter: tresor)
        } catch {
            return switch error {
            case .vorschau: "eine Vorschau schreibt nicht"
            case .nichtsZuSchreiben: "keine Planung geladen"
            case .gesperrt: "die Ablage ist gesperrt, ein unlesbarer Stand liegt noch im Weg"
            case .schreiben(let text): text
            }
        }
        for (name, daten) in generation.dateien { alle[name] = .daten(daten) }
        let dienst = sicherung.uebergang
        if let grund = dienst.vorbereiten(.jahreswechsel, kennung: tresor.kennung, stempel: Zeitrechnung.dateistempel(),
                                          dateien: alle) {
            return "die Generation ließ sich nicht anlegen (\(grund.ohneSchlusspunkt))"
        }
        if let grund = dienst.uebergeben() {
            dienst.verwerfen()
            return "die Marke ließ sich nicht schreiben (\(grund.ohneSchlusspunkt))"
        }
        if case .unvollendet(let grund) = sicherung.uebergangEinsetzen(nummer: generation.nummer, stand: generation.stand,
                                                                        abdruck: generation.abdruck) {
            melden("Nicht jede Datei des Schuljahreswechsels ist schon eingesetzt (\(grund.ohneSchlusspunkt)) — die "
                   + "Autosicherung ruht, bis er eingesetzt ist; jeder Schreibanlass versucht es erneut, der nächste "
                   + "Start vollendet ihn.", .warnung)
        }
        return nil
    }
}
