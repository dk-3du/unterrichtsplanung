// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Die Lernendenverwaltung an der Sitzung (v80) ──────────────────────────
// Die Haken des Schutzes: aus neben einer Klartext-Planung, offen nach dem
// Entsperren, zu bis dahin — und was das Lesen fand, kommt einmal zur Sprache.
extension Planungsspeicher {

    /// Beim Start neben einer Klartext-Planung: Das Modul ist aus (E249).
    func lernendeLaden() {
        lernendenbefundMelden(lernende.laden(stempel: Zeitrechnung.dateistempel()))
        termineAbgleichen()
    }

    /// Nach dem Entsperren.
    func lernendeOeffnen(_ tresor: Tresor) {
        let stempel = Zeitrechnung.dateistempel()
        lernendenbefundMelden(lernende.oeffnen(mit: tresor, stempel: stempel))
        // Das Archiv nur am Kopf — Fremdes hielte sonst jeden Übergang auf (B71).
        if let rettung = lernende.archivkopfPruefen(stempel: stempel) {
            melden("Das Archiv der Lernendenverwaltung liegt nicht als Archiv unter dem Schlüssel dieser Planung und "
                   + "wurde nicht übernommen — es liegt als „\(rettung)“ neben der Planung.", .warnung)
        }
        termineAbgleichen()
    }

    // ── Aufheben der Verschlüsselung (E250, E278) ─────────────────────────

    /// Aufheben geht nicht, solange Jahresdatei oder Archiv etwas tragen —
    /// der Satz, was zu tun ist; `nil`, wenn nichts im Weg steht. Ist das
    /// Modul aus, zu oder gesperrt, entscheidet der Übergang selbst.
    var lernendenAufhebenSperre: String? {
        guard lernende.schreibbar else { return nil }
        if lernende.traegtInhalt {
            return "Die Lernendenverwaltung ist nicht leer — zuerst exportieren und löschen, dann aufheben."
        }
        switch lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) {
        case .gelesen(let archiv, _, _) where !archiv.jahre.isEmpty:
            return "Das Archiv der Lernendenverwaltung ist nicht leer — zuerst exportieren und löschen, dann aufheben."
        case .gelesen:
            return nil
        case .nichtLesbar(let grund):
            return "Das Archiv der Lernendenverwaltung lässt sich nicht lesen (\(grund.ohneSchlusspunkt)) — die "
                + "Verschlüsselung bleibt, bis es lesbar ist."
        }
    }

    /// Die Rettungskopien der Lernendendaten neben der Planung — das Aufheben
    /// löscht sie nach der Rückfrage, entsiegelt werden sie nie (E278).
    var lernendenkopien: [String] {
        ((try? sicherung.ablage.nebendateien()) ?? []).map(\.lastPathComponent)
            .filter { $0.hasPrefix("lernende-") || $0.hasPrefix("archiv-") }
    }

    /// Die Rückfrage vor dem Aufheben — mit den Rettungskopien, die dabei gehen.
    var aufhebenRueckfrage: String {
        var text = "Die Ablage auf diesem Mac wird wieder im Klartext geschrieben, ebenso die "
            + "Nebendateien. Die Sicherungskopie beim Beenden wird ausgeschaltet — es "
            + "gibt sie nur verschlüsselt."
        let kopien = lernendenkopien
        if !kopien.isEmpty {
            text += "\n\n" + (kopien.count == 1 ? "Eine Rettungskopie der Lernendendaten wird"
                                               : "\(kopien.count) Rettungskopien der Lernendendaten werden")
                + " dabei endgültig gelöscht — Lernendendaten werden nie entsiegelt."
            // Überholt ist nur der Stand vor einer Bereinigung; fremde, beschädigte
            // oder im Klartext abgelegte Kopien können die einzige Fassung sein (E301).
            let andere = kopien.filter { !$0.contains("-bereinigt-") }.count
            if andere > 0 {
                let art = "(unter einem anderen Schlüssel, beschädigt oder im Klartext abgelegt)"
                if kopien.count == 1 {
                    text += " Sie ist kein überholter Stand, sondern eine Kopie, die sich nicht öffnen ließ \(art); "
                        + "sie kann die einzige Fassung dieser Daten sein."
                } else if andere == 1 {
                    text += " Davon ist 1 kein überholter Stand, sondern eine Kopie, die sich nicht öffnen ließ \(art); "
                        + "sie kann die einzige Fassung dieser Daten sein."
                } else {
                    text += " Davon sind \(andere) keine überholten Stände, sondern Kopien, die sich nicht öffnen ließen "
                        + "\(art); sie können die einzige Fassung dieser Daten sein."
                }
            }
        }
        return text + "\n\nFortfahren?"
    }

    private func lernendenbefundMelden(_ befund: Lernendendienst.Ladebefund) {
        switch befund {
        case .keine, .geladen:
            break
        case .bereinigt(_, let bilanz, let kopie):
            melden("Die Lernendendaten wurden beim Lesen bereinigt: \(bilanz.beschreibung)"
                   + (kopie.map { " — das Original liegt als „\($0)“ neben der Planung." }
                      ?? " — das Original ließ sich nicht bewahren; bis es gelingt, wird nichts darüber geschrieben."),
                   .warnung)
        case .beiseitegelegt(let grund, let rettung):
            melden("Die Lernendendatei ließ sich nicht öffnen (\(grund.ohneSchlusspunkt)) und liegt als „\(rettung)“ "
                   + "neben der Planung.", .warnung)
        case .klartextBeiseitegelegt(let rettung):
            melden("Unter dem Namen der Lernendendatei lag eine unverschlüsselte Datei — sie wurde nicht übernommen "
                   + "und liegt als „\(rettung)“ neben der Planung.", .warnung)
        case .gesperrt(let grund):
            melden("Die Lernendenverwaltung ist gerade nicht verfügbar (\(grund.ohneSchlusspunkt)).", .warnung)
        }
    }
}

// ── Das Blatt „Lernende“ (AP7) ────────────────────────────────────────────

/// Was das Blatt zeigt: die Lerngruppen mit ihren Mitgliedern, alle Personen
/// oder das Archiv der Vorjahre.
enum Lernendenansicht: String, CaseIterable, Sendable {
    case gruppen, alle, archiv

    var titel: String {
        switch self {
        case .gruppen: "Lerngruppen"
        case .alle: "Alle Lernenden"
        case .archiv: "Archiv"
        }
    }
}

/// Was die Gruppenansicht rechts zeigt: die Mitglieder, die Rücklaufliste
/// der Mitteilungen oder die Maßnahmen (E272).
enum Gruppenteil: String, CaseIterable, Sendable {
    case mitglieder, mitteilungen, massnahmen

    var titel: String {
        switch self {
        case .mitglieder: "Mitglieder"
        case .mitteilungen: "Mitteilungen"
        case .massnahmen: "Maßnahmen"
        }
    }
}

/// Womit das Blatt aufgeht — die Gruppe aus ⌘K oder der Kurszelle; Abbild
/// und Prüfstand geben dazu Ansicht, Teil, Auswahl und Eingabe vor.
struct Lernendenvorgabe: Equatable, Sendable {
    var ansicht: Lernendenansicht = .gruppen
    var gruppe: String?
    var namenstext: String?
    var gruppenteil: Gruppenteil = .mitglieder
    var person: String?
    var anliegen: String?
    var nurOffen = false
    /// Eine Datei für den IServ-Import — der Bogen öffnet mit ihr, ohne
    /// Dateiwahl (Prüfstand und Abbild).
    var importdatei: URL?
    /// Der Bogen einer Maßnahme oder eines Termins ohne Gruppe an `person` —
    /// mit `anliegen` zum Ändern (Prüfstand und Abbild, E290).
    var anliegenbogen: Anliegenart?
    /// Der Tag, den ein neuer Termin im Bogen vorgeschlagen bekommt (Prüfstand und Abbild).
    var anliegentag: Tag?
    /// Ein Klick auf diese Gruppe, wenn das Blatt steht — wie in der Liste (Prüfstand und Abbild, E303).
    var gruppenwechsel: String?
}

/// Was das Blatt „Lernende“ dem Speicher für die Fragen beim Beenden
/// hereinreicht (E300, E303) — Griffe in seinen Zustand.
@MainActor
struct Lernendenblattgriff {
    /// Bögen schließen und das Ausstehende aus den Feldern übernehmen.
    var vorbereiten: () -> Void = {}
    /// Ob ein Bogen (Import, Maßnahme/Termin) auf dem Blatt steht — und ihn schließen.
    var bogenOffen: () -> Bool = { false }
    var bogenSchliessen: () -> Void = {}
    /// Ob die gewählte Gruppe in diesem Stand sichtbar bliebe — für ⌘Z/⇧⌘Z bei getippter Liste.
    var gruppeBleibt: (Lernendenbestand) -> Bool = { _ in true }
    /// Der Stand, mit dem das Blatt begann.
    var ausgang: () -> Lernendenbestand? = { nil }
    /// Ob eine getippte, noch nicht eingetragene Namensliste steht.
    var namenOffen: () -> Bool = { false }
    var namenVerwerfen: () -> Void = {}
    /// Der geänderte Entwurf — `nil` ohne Änderungen.
    var aenderungen: () -> Lernendenbestand? = { nil }
}

extension Planungsspeicher {

    /// Der Hinweis beim Versuch ohne Verschlüsselung (E249).
    static let lernendenSperrtext = "Die Lernendenverwaltung ist nur mit eingeschalteter Verschlüsselung "
        + "verfügbar — bitte zuerst unter „Planung → Verschlüsselung …“ einschalten."

    /// Ob „Planung → Lernende …“ gilt: mit Planung und offener Lernendenverwaltung.
    var lernendenBlattAngeboten: Bool { planung != nil && lernende.schreibbar }

    /// ⌘L — oder der Hinweis, warum nicht. `ort`: wo die Rückfrage hängt,
    /// wenn der Versuch aus einem Blatt kommt.
    func lernendenBlattOeffnen(gruppe: String? = nil, ort: Rueckfrageort = .hauptansicht) {
        guard planung != nil else { return }
        switch lernende.quelle {
        case .behaelter:
            lernendenVorgabe = Lernendenvorgabe(gruppe: gruppe)
            dialogOeffnen(.lernende)
        case .aus:
            fragen(Self.lernendenSperrtext, bestaetigung: "Verschlüsselung einrichten …", ort: ort,
                   nachDemSchliessen: true) { [weak self] in
                self?.verschluesselungEinrichten()
            }
        case .zu, .gesperrt:
            melden(lernende.sperrhinweis ?? "Die Lernendenverwaltung ist gerade nicht verfügbar.", .warnung)
        }
    }

    /// Der Stand, mit dem das Blatt beginnt — ohne Jahresdatei leer für das
    /// Schuljahr der Planung. Geschrieben wird erst beim „Übernehmen“.
    func lernendenEntwurfBeginnen() -> Lernendenbestand? {
        guard let planung, lernende.schreibbar else { return nil }
        return lernende.bestand ?? .leer(planung: planung.erstellt,
                                         schuljahr: Lernendenbestand.schuljahr(fuer: planung.start),
                                         jetzt: Zeitrechnung.jetztAlsZeitstempel())
    }

    /// „Übernehmen“ — der Grund, wenn die Platte den Stand nicht trägt.
    /// Wünsche „In der Planung eintragen“ trägt der Stand selbst (E293, W3-03).
    /// `ausgang`: der Stand, mit dem das Blatt begann — was es an Terminen nicht
    /// anfasste, behält den Stand der Sitzung (offener Punkt 3).
    @discardableResult
    func lernendenUebernehmen(_ neu: Lernendenbestand, ausgang: Lernendenbestand? = nil) -> String? {
        termineUebernehmen(neu, ausgang: ausgang)
    }

    // ── Rückfragen am Blatt — mit den Zahlen dessen, was geht ─────────────

    private static func anzahl(_ n: Int, _ eins: String, _ mehr: String) -> String {
        "\(n) \(n == 1 ? eins : mehr)"
    }

    /// „1 Maßnahme“ — und „, 2 Termine“ dahinter, wenn Termine darunter sind (E290).
    static func massnahmenUndTermine(_ zahl: Lernendenbestand.Loeschzahl) -> String {
        anzahl(zahl.anliegen - zahl.termine, "Maßnahme", "Maßnahmen")
            + (zahl.termine > 0 ? ", " + anzahl(zahl.termine, "Termin", "Termine") : "")
    }

    /// „Die Mitteilung“, „Die Maßnahme“, „Den Termin“ — und das Fürwort dazu.
    static func benennung(_ art: Anliegenart) -> (art: String, mit: String) {
        switch art {
        case .mitteilung: ("Die Mitteilung", "Mit ihr")
        case .massnahme: ("Die Maßnahme", "Mit ihr")
        case .termin: ("Den Termin", "Mit ihm")
        }
    }

    func lerngruppeLoeschenFragen(_ id: String, in entwurf: Lernendenbestand,
                                  dann: @escaping @MainActor (Lernendenbestand) -> Void) {
        // In der Lücke nach einer Antwort keine neue Frage auf den alten Entwurf (E437, Z-AU4a-02).
        guard !frageSperrtBefehl(), let gruppe = entwurf.lerngruppen.first(where: { $0.id == id }) else { return }
        let (neu, zahl) = entwurf.ohneGruppe(id)
        let text = "Die Lerngruppe „\(gruppe.beschriftung)“ löschen?\n\n"
            + "Mit ihr gehen \(Self.anzahl(zahl.anliegen, "Mitteilung", "Mitteilungen")) samt "
            + "\(Self.anzahl(zahl.rueckmeldungen, "Rücklauf", "Rückläufen")) und "
            + "\(Self.anzahl(zahl.eintraege, "Eintrag", "Einträge")). Die Personen bleiben, ebenso ihre Maßnahmen und Termine.\n\n"
            + "Archivieren nimmt die Gruppe nur aus den Listen."
        fragen(text, bestaetigung: "Löschen", gefahr: true, ort: .lernende, nachDemSchliessen: true) { dann(neu) }
    }

    func personLoeschenFragen(_ id: String, in entwurf: Lernendenbestand,
                              dann: @escaping @MainActor (Lernendenbestand) -> Void) {
        guard !frageSperrtBefehl(), let person = entwurf.lernende.first(where: { $0.id == id }) else { return }
        let gruppen = entwurf.lerngruppen.filter { $0.mitglieder.contains(id) }.count
        let (neu, zahl) = entwurf.ohnePerson(id)
        // Termine, die mit ihr gehen, nehmen beim „Übernehmen“ ihr Vorhaben mit (E293, W2-05).
        let vorhaben = entwurf.anliegen.filter { a in
            a.art == .termin && !neu.anliegen.contains { $0.id == a.id } && hatVorhaben(a.id)
        }.count
        // Ihre Tische im Sitzplan lassen los (E304).
        let tische = sitzplaene.bindungen(an: [id])
        let text = "„\(person.anzeigename)“ endgültig löschen?\n\n"
            + "Mit der Person gehen in diesem Schuljahr ihre Mitgliedschaft in "
            + "\(Self.anzahl(gruppen, "Lerngruppe", "Lerngruppen")), "
            + "\(Self.anzahl(zahl.rueckmeldungen, "Rücklauf", "Rückläufe")), "
            + "\(Self.massnahmenUndTermine(zahl)) und "
            + "\(Self.anzahl(zahl.eintraege, "Eintrag", "Einträge")). Frühere Schuljahre im Archiv bleiben unberührt."
            + (vorhaben == 0 ? "" : "\n\nBeim „Übernehmen“ \(vorhaben == 1 ? "geht" : "gehen") auch "
                                    + "\(vorhaben) Vorhaben in der Planung.")
            + (tische == 0 ? "" : "\n\nAn \(tische == 1 ? "1 Tisch" : "\(tische) Tischen") im Sitzplan wird die "
                                  + "Zuordnung gelöst; der Name am Tisch bleibt.")
            + "\n\nArchivieren nimmt die Person nur aus den Listen; alles bleibt."
        fragen(text, bestaetigung: "Endgültig löschen", gefahr: true, ort: .lernende, nachDemSchliessen: true) { dann(neu) }
    }

    func anliegenLoeschenFragen(_ id: String, in entwurf: Lernendenbestand,
                                dann: @escaping @MainActor (Lernendenbestand) -> Void) {
        guard !frageSperrtBefehl(), let anliegen = entwurf.anliegen.first(where: { $0.id == id }) else { return }
        let (neu, zahl) = entwurf.ohneAnliegen(id)
        let (art, mit) = Self.benennung(anliegen.art)
        let text = "\(art) „\(anliegen.titel)“ löschen?\n\n"
            + "\(mit) \(zahl.rueckmeldungen == 1 ? "geht" : "gehen") "
            + "\(Self.anzahl(zahl.rueckmeldungen, "Rücklauf", "Rückläufe"))."
            + (hatVorhaben(id) ? "\n\nBeim „Übernehmen“ geht auch sein Vorhaben in der Planung." : "")
        fragen(text, bestaetigung: "Löschen", gefahr: true, ort: .lernende, nachDemSchliessen: true) { dann(neu) }
    }

    /// Beim Beenden mit geändertem Blatt „Lernende“ (E300): `true`, wenn die
    /// Frage steht — `dann` setzt das Beenden nach der Antwort fort.
    func lernendenblattBeimBeendenFragen(dann: @escaping @MainActor () -> Void) -> Bool {
        guard let griff = lernendenblattGriff else { return false }
        // Ein offener Bogen zuerst — gefragt am Bogen, wo er steht (offener Punkt 2).
        if griff.bogenOffen() {
            nachVornFuerFrage()
            fragen("Den offenen Bogen verwerfen?", bestaetigung: "Verwerfen", gefahr: true, ort: .bogen,
                   ablehnung: "Weiter bearbeiten", nachDemSchliessen: true) { [weak self] in
                griff.bogenSchliessen()
                self?.nachDerAntwort(dann)
            }
            return true
        }
        griff.vorbereiten()
        // Eine getippte, nicht eingetragene Namensliste zuerst — wie beim Wechsel der Gruppe (E303, Z14b-02).
        if griff.namenOffen() {
            nachVornFuerFrage()
            fragen("Die eingegebenen Namen verwerfen?", bestaetigung: "Verwerfen", gefahr: true, ort: .lernende,
                   ablehnung: "Weiter bearbeiten", nachDemSchliessen: true) { [weak self] in
                griff.namenVerwerfen()
                self?.nachDerAntwort(dann)
            }
            return true
        }
        guard griff.aenderungen() != nil else { return false }
        nachVornFuerFrage()
        // Einmal gefragt: Danach geht das Beenden weiter, auch wenn das Blatt noch steht — erst,
        // wenn das Alert fort ist (E319). Den Griff sofort abgeben: Ein zweites ⌘Q fragt nicht erneut.
        // Entfällt das Beenden, weil inzwischen eine andere Frage steht (Z14b-11), meldet sich der Griff
        // wieder an — ein späteres ⌘Q fragt wieder (Z-AU4a-12).
        let wiederAnmelden: @MainActor (Lernendenblattgriff) -> Void = { [weak self] wieder in
            guard let self, lernendenblattOffen, lernendenblattGriff == nil else { return }
            lernendenblattGriff = wieder
        }
        let weiter: @MainActor () -> Void = { [weak self] in
            self?.lernendenblattGriff = nil
            self?.nachDerAntwort(entfaellt: { wiederAnmelden(griff) }, dann)
        }
        fragen("Die Änderungen an den Lernenden übernehmen?\n\nDas Blatt „Lernende“ ist noch offen; ohne „Übernehmen“ "
               + "gehen seine Änderungen beim Beenden verloren.",
               bestaetigung: "Übernehmen", ort: .lernende, weitere: "Verwerfen", beiWeitere: weiter) { [weak self] in
            guard let self else { return }
            // Der Griff geht sofort wie bei „Verwerfen“; das Übernehmen baut die Hauptfläche um — erst nach dem
            // Schließen des Alerts, danach das Beenden (B95, Z-AU4-03). Bis dahin prallt ein zweites ⌘Q ab (E436).
            // Entfällt das Beenden danach, meldet sich der Griff wieder an — gefragt wird nur nach dem, was sich
            // seit dem Übernehmen änderte (Z-AU4c-11, Z-AU4c-19).
            lernendenblattGriff = nil
            nachDemSchliessenAusfuehren { [weak self] in
                // Der Entwurf der Antwort, nicht der Frage: Wartete sie unter einem Bogen, kann er ihn
                // derweil geändert haben (Z-AU5-01) — auch ganz zurück; dann ist nichts zu übernehmen (Z-AU5-10).
                guard let jetzt = griff.aenderungen() else {
                    self?.nachDerAntwort(entfaellt: { wiederAnmelden(griff) }, dann)
                    return
                }
                self?.lernendenUebernehmen(jetzt, ausgang: griff.ausgang())
                var danach = griff
                danach.ausgang = { jetzt }
                danach.aenderungen = { griff.aenderungen().flatMap { $0 == jetzt ? nil : $0 } }
                self?.nachDerAntwort(entfaellt: { wiederAnmelden(danach) }, dann)
            }()
        }
        return true
    }

    func lernendenVerwerfenFragen(dann: @escaping @MainActor () -> Void) {
        fragen("Die Änderungen an den Lernenden verwerfen?", bestaetigung: "Verwerfen", gefahr: true,
               ort: .lernende, ablehnung: "Weiter bearbeiten", nachDemSchliessen: true, handlung: dann)
    }
}

// ── Das Archiv im Blatt (AP9) — sichern (E274), drei Löschungen (E276) ────

extension Planungsspeicher {

    /// Die Löschungen im Archiv gehen nicht über den Entwurf des Blatts.
    static let archivEndgueltig = "Das gilt sofort, unabhängig von „Übernehmen“, und lässt sich nicht widerrufen."

    private static func anzahlArchiv(_ n: Int, _ eins: String, _ mehr: String) -> String {
        "\(n) \(n == 1 ? eins : mehr)"
    }

    /// Eine Planung aus dem Archiv als Datei — versiegelt wie ⌘S, unverändert,
    /// ohne neuen Zeitstempel. Liefert die Größe des Geschriebenen.
    @discardableResult
    func archivPlanungSchreiben(_ planung: Planung, nach ziel: URL) throws -> Int {
        guard let tresor else { throw Uebergangsfehler(text: "ohne Verschlüsselung gibt es kein Archiv") }
        let daten = try tresor.versiegeln(try Planungsdatei.schreiben(planung), inhalt: .planung, ziel: .export)
        try daten.write(to: ziel, options: [.atomic])
        return daten.count
    }

    /// „Planung sichern …“ — derselbe Dialog wie ⌘S (E274).
    func archivPlanungSichern(_ jahr: Archivjahr) {
        Systemzugriff.zielWaehlen(name: Planungsdatei.exportName(titel: jahr.planung.titel)) { [weak self] ziel in
            guard let self, let ziel else { return }
            do {
                let groesse = try archivPlanungSchreiben(jahr.planung, nach: ziel)
                melden("Die Planung „\(jahr.planung.titel)“ (\(jahr.schuljahr)) ist als verschlüsselte JSON-Datei "
                       + "gesichert — sie öffnet mit der Passphrase oder dem Wiederherstellungsschlüssel, auch in der Web App.")
                if let hinweis = Planungsspeicher.lesegrenzeHinweis(groesse: groesse) { melden(hinweis, .warnung) }
            } catch {
                melden("Die Datei konnte nicht geschrieben werden: \(error.localizedDescription)", .warnung)
            }
        }
    }

    /// Eine Löschung ins Archiv schreiben — `nil`, wenn es gelang; sonst ist der Grund gemeldet.
    @discardableResult
    func archivSchreiben(_ neu: Archivbestand) -> String? {
        guard let grund = lernende.archivSetzen(neu, stempel: Zeitrechnung.dateistempel()) else { return nil }
        archivSchreibfehler += 1
        melden("Das Archiv ließ sich nicht ändern (\(grund.ohneSchlusspunkt)) — es bleibt, wie es war.", .warnung)
        return grund
    }

    func archivJahrLoeschenFragen(_ id: String, in archiv: Archivbestand,
                                  dann: @escaping @MainActor (Archivbestand) -> Void) {
        guard let jahr = archiv.jahre.first(where: { $0.id == id }) else { return }
        let zahl = archiv.ohneJahr(id, jetzt: Zeitrechnung.jetztAlsZeitstempel()).zahl
        let inhalt = jahr.lernende == nil
            ? "Mit ihm geht die Planung „\(jahr.planung.titel)“; Lernendendaten gab es in diesem Jahr nicht."
            : "Mit ihm gehen die Planung „\(jahr.planung.titel)“ und die Lernendendaten dieses Jahres: "
                + "\(Self.anzahlArchiv(zahl.personen, "Person", "Personen")), "
                + "\(Self.anzahlArchiv(zahl.gruppen, "Lerngruppe", "Lerngruppen")), "
                + "\(Self.anzahlArchiv(zahl.anliegen, "Anliegen", "Anliegen")) samt "
                + "\(Self.anzahlArchiv(zahl.rueckmeldungen, "Rücklauf", "Rückläufen")) und "
                + "\(Self.anzahlArchiv(zahl.eintraege, "Eintrag", "Einträge"))."
        fragen("Das Schuljahr \(jahr.schuljahr) aus dem Archiv löschen?\n\n\(inhalt)\n\n\(Self.archivEndgueltig)",
               bestaetigung: "Schuljahr löschen", gefahr: true, ort: .lernende) { [weak self] in
            self?.archivLoeschenNachDerAntwort(archiv, dann: dann) { $0.ohneJahr(id, jetzt: Zeitrechnung.jetztAlsZeitstempel()).bestand }
        }
    }

    /// Eine bestätigte Löschung im Archiv: erst, wenn das Alert fort ist — das Schreiben baut
    /// die Ansicht um, und darunter schloss SwiftUI das schließende Alert-Blatt ein zweites Mal
    /// (B88, E392). Nie verworfen: Steht inzwischen eine andere Frage, nach deren Antwort
    /// (Z-AS2a-01); beim Beenden vorher (Z-AS2a-07). Angewandt auf das Archiv, das beim Schreiben
    /// gilt — nicht auf das beim Fragen gezeigte, sonst setzte eine zweite Löschung die erste
    /// zurück (Z-AS2a-02); ist es nicht lesbar, auf das gezeigte. Nichts ändert sich im Klick (Z-AS2a-05).
    private func archivLoeschenNachDerAntwort(_ gezeigt: Archivbestand, dann: @escaping @MainActor (Archivbestand) -> Void,
                                              anwenden: @escaping (Archivbestand) -> Archivbestand) {
        let kennung = UUID()
        ausstehendeArchivloeschungen.append((kennung, { [weak self] in
            guard let self else { return }
            let jetzt: Archivbestand
            if case .gelesen(let gelesen, _, _) = lernende.archivLesen(stempel: Zeitrechnung.dateistempel()) {
                jetzt = gelesen
            } else {
                jetzt = gezeigt
            }
            dann(anwenden(jetzt))
        }))
        nachDerAntwort(immer: true) { [weak self] in self?.archivloeschungAusfuehren(kennung) }
    }

    /// Genau einmal — aus der Fortsetzung oder vor dem Beenden, was zuerst kommt.
    private func archivloeschungAusfuehren(_ kennung: UUID) {
        guard let stelle = ausstehendeArchivloeschungen.firstIndex(where: { $0.kennung == kennung }) else { return }
        ausstehendeArchivloeschungen.remove(at: stelle).loeschen()
    }

    /// Vor dem Beenden: Was bestätigt ist, geschieht noch (Z-AS2a-07). `false`, wenn sich das
    /// Archiv dabei nicht schreiben ließ (Z-AS2a-08).
    func archivloeschungenJetztAusfuehren() -> Bool {
        let vorher = archivSchreibfehler
        for kennung in ausstehendeArchivloeschungen.map(\.kennung) { archivloeschungAusfuehren(kennung) }
        return archivSchreibfehler == vorher
    }

    func archivPersonLoeschenFragen(_ id: String, in archiv: Archivbestand,
                                    dann: @escaping @MainActor (Archivbestand) -> Void) {
        let jahre = archiv.jahre.filter { $0.lernende?.lernende.contains { $0.id == id } == true }
        guard let person = jahre.last?.lernende?.lernende.first(where: { $0.id == id }) else { return }
        let gruppen = jahre.reduce(0) { summe, jahr in
            summe + (jahr.lernende?.lerngruppen.filter { $0.mitglieder.contains(id) }.count ?? 0)
        }
        let zahl = archiv.ohnePerson(id, jetzt: Zeitrechnung.jetztAlsZeitstempel()).zahl
        let text = "„\(person.anzeigename)“ in allen archivierten Schuljahren löschen?\n\n"
            + "Die Person steht in \(Self.anzahlArchiv(jahre.count, "Schuljahr", "Schuljahren")) des Archivs. "
            + "Mit ihr gehen dort ihre Mitgliedschaft in \(Self.anzahlArchiv(gruppen, "Lerngruppe", "Lerngruppen")), "
            + "\(Self.anzahlArchiv(zahl.rueckmeldungen, "Rücklauf", "Rückläufe")), "
            + "\(Self.massnahmenUndTermine(zahl)) und "
            + "\(Self.anzahlArchiv(zahl.eintraege, "Eintrag", "Einträge")). Das laufende Schuljahr bleibt unberührt.\n\n"
            + Self.archivEndgueltig
        fragen(text, bestaetigung: "In allen Schuljahren löschen", gefahr: true, ort: .lernende) { [weak self] in
            self?.archivLoeschenNachDerAntwort(archiv, dann: dann) { $0.ohnePerson(id, jetzt: Zeitrechnung.jetztAlsZeitstempel()).bestand }
        }
    }

    func archivAnliegenLoeschenFragen(_ anliegen: String, imJahr jahr: String, in archiv: Archivbestand,
                                      dann: @escaping @MainActor (Archivbestand) -> Void) {
        guard let j = archiv.jahre.first(where: { $0.id == jahr }),
              let a = j.lernende?.anliegen.first(where: { $0.id == anliegen }) else { return }
        let zahl = archiv.ohneAnliegen(anliegen, imJahr: jahr, jetzt: Zeitrechnung.jetztAlsZeitstempel()).zahl
        let (art, mit) = Self.benennung(a.art)
        let text = "\(art) „\(a.titel)“ aus dem Schuljahr \(j.schuljahr) löschen?\n\n"
            + "\(mit) \(zahl.rueckmeldungen == 1 ? "geht" : "gehen") "
            + "\(Self.anzahlArchiv(zahl.rueckmeldungen, "Rücklauf", "Rückläufe")).\n\n" + Self.archivEndgueltig
        fragen(text, bestaetigung: "Löschen", gefahr: true, ort: .lernende) { [weak self] in
            self?.archivLoeschenNachDerAntwort(archiv, dann: dann) {
                $0.ohneAnliegen(anliegen, imJahr: jahr, jetzt: Zeitrechnung.jetztAlsZeitstempel()).bestand
            }
        }
    }
}

// ── Lerngruppe an Zeilen der Planung (AP10, E248, E256) ──────────────────
// Gebunden wird in der Jahresdatei, an die Herkunft der Planung und die
// Kennung der Zeile — für Unterricht, Klassenleitung und Weiteres.

extension Planungsspeicher {

    private func zeilenbindung(_ klasseId: String) -> Zeilenbindung? {
        planung.map { Zeilenbindung(planung: $0.erstellt, klasseId: klasseId) }
    }

    /// Die Gruppe an einer Zeile der offenen Planung — `nil` ohne Bindung.
    func lerngruppe(fuerZeile klasseId: String) -> Lerngruppe? {
        guard let zeile = zeilenbindung(klasseId) else { return nil }
        return lernende.bestand?.gruppe(an: zeile)
    }

    /// Was die Listenphase des Sitzplans aus der Lerngruppe anbietet (E255):
    /// die Gruppe der Zeile und die Plätze ihrer aktiven Mitglieder. `nil`
    /// ohne offene Lernendenverwaltung — dann gibt es den Knopf nicht (E249);
    /// ohne gebundene Gruppe keine Gruppe und keine Plätze.
    func sitzplatzangebot(fuer klasseId: String) -> (gruppe: Lerngruppe?, plaetze: [Sitzplan.Platzvorlage])? {
        guard lernende.quelle == .behaelter else { return nil }
        guard let gruppe = lerngruppe(fuerZeile: klasseId), let verzeichnis = lernende.verzeichnis else {
            return (nil, [])
        }
        return (gruppe, verzeichnis.sitzplatzvorlage(der: gruppe.id))
    }

    /// Eine Gruppe aus der Zeile: ihr Name und Fach, an die Zeile gebunden.
    @discardableResult
    func lerngruppeAusZeileAnlegen(_ klasseId: String) -> String? {
        let klasse = planung?.klassen.first { $0.id == klasseId }
        return bindungAendern(klasseId) { bestand, zeile, jetzt in
            guard let klasse,
                  let ergebnis = bestand.mitNeuerGruppe(name: klasse.name, fach: klasse.fach, art: .klasse, jetzt: jetzt)
            else { return nil }
            return ergebnis.bestand.mitBindung(ergebnis.id, an: zeile, jetzt: jetzt)
        }
    }

    @discardableResult
    func lerngruppeBinden(_ gruppe: String, an klasseId: String) -> String? {
        bindungAendern(klasseId) { $0.mitBindung(gruppe, an: $1, jetzt: $2) }
    }

    /// Die Zeile zeigt danach wieder, was die Planung trägt — eine
    /// Verwaltungsdatei oder das Angebot (E256).
    @discardableResult
    func lerngruppeLoesen(_ klasseId: String) -> String? {
        bindungAendern(klasseId) { $0.ohneBindung($1, jetzt: $2) }
    }

    /// Der eine Weg: erst die Herkunft der Planung auf der Platte (A4), dann
    /// die Jahresdatei. `nil`, wenn es gelang; sonst der Grund.
    private func bindungAendern(_ klasseId: String,
                                _ aendern: (Lernendenbestand, Zeilenbindung, String) -> Lernendenbestand?) -> String? {
        guard lernende.schreibbar else { return lernende.sperrhinweis ?? Self.lernendenSperrtext }
        guard planung?.klassen.contains(where: { $0.id == klasseId }) == true else { return "Die Zeile gibt es nicht mehr." }
        if let grund = herkunftSichern() { return grund }
        guard let zeile = zeilenbindung(klasseId), let start = lernendenEntwurfBeginnen() else {
            return "Die Lernendenverwaltung ist gerade nicht verfügbar."
        }
        guard let neu = aendern(start, zeile, Zeitrechnung.jetztAlsZeitstempel()) else {
            return "Die Lerngruppe ließ sich nicht anlegen — höchstens \(Kennwerte.maxLerngruppen) je Schuljahr."
        }
        guard neu != start else { return nil }
        return lernendenUebernehmen(neu)
    }

    /// A4: Steht die Herkunft der Planung auf der Platte? Sonst wird vorher
    /// gesichert — eine Bindung aus dieser Sitzung zeigte nach dem Neustart
    /// ins Leere, denn eine Planung ohne `erstellt` bekommt beim Lesen jedes
    /// Mal eine neue Herkunft. `nil`, wenn sie dort steht; sonst der Grund.
    func herkunftSichern() -> String? {
        guard var neu = planung else { return "Es ist keine Planung geöffnet." }
        if herkunftAufDerPlatte(neu.erstellt) { return nil }
        // Die Sicherung schreibt nur, was sich geändert hat — darum der Stempel.
        neu.geaendert = Zeitrechnung.jetztAlsZeitstempel()
        stempelEinsetzen(neu)
        jetztSichern()
        return herkunftAufDerPlatte(neu.erstellt) ? nil
            : "Die Planung ließ sich nicht sichern — gebunden wird erst, wenn ihre Herkunft auf der Platte steht."
    }

    private func herkunftAufDerPlatte(_ erstellt: String) -> Bool {
        guard let roh = try? Data(contentsOf: sicherung.ablage.datei) else { return false }
        let klartext: Data? = Tresor.istBehaelter(roh) ? (try? tresor?.oeffnen(roh)) ?? nil : roh
        guard let klartext, let gelesen = try? Planungsdatei.lesen(klartext) else { return false }
        return gelesen.erstellt == erstellt
    }
}


// ── Export und Einlesen (AP12, E257, E287) ────────────────────────────────

extension Planungsspeicher {

    /// Eingelesen wird nur in eine leere Lernendenverwaltung (E287).
    var lernendenLeer: Bool {
        guard let b = lernende.bestand else { return true }
        return b.lernende.isEmpty && b.lerngruppen.isEmpty && b.anliegen.isEmpty && b.rueckmeldungen.isEmpty
            && b.erfassung.isEmpty && b.beurteilung.isEmpty
    }

    /// Die Einträge unter „Ablage“: Export und CSV, wenn es etwas gibt; Einlesen
    /// in eine leere Verwaltung — beides nur offen und verschlüsselt (E249).
    var lernendenExportAngeboten: Bool {
        planung != nil && tresor != nil && lernende.quelle == .behaelter && !lernendenLeer
    }
    var lernendenEinlesenAngeboten: Bool {
        planung != nil && tresor != nil && lernende.quelle == .behaelter && lernendenLeer
    }

    /// Die Jahresdatei als Behälter fürs Ziel export — Passphrase und
    /// Wiederherstellung, nie die Enklave (E257). Liefert die Größe.
    @discardableResult
    func lernendenExportSchreiben(nach ziel: URL) throws -> Int {
        guard let tresor, lernende.quelle == .behaelter, let bestand = lernende.bestand else {
            throw Uebergangsfehler(text: "die Lernendenverwaltung ist nicht offen")
        }
        let daten = try tresor.versiegeln(try Lernendendatei.schreiben(bestand), inhalt: .lernende, ziel: .export)
        try daten.write(to: ziel, options: [.atomic])
        return daten.count
    }

    /// „Lernende exportieren …“
    func lernendenExportieren() {
        guard lernendenExportAngeboten, let schuljahr = lernende.bestand?.schuljahr else {
            melden(Planungsspeicher.lernendenSperrtext, .hinweis)
            return
        }
        Systemzugriff.zielWaehlen(name: Lernendendatei.exportName(schuljahr: schuljahr, endung: "json"),
                                  nachricht: "Lernende als verschlüsselte Datei sichern") { [weak self] ziel in
            guard let self, let ziel else { return }
            do {
                try lernendenExportSchreiben(nach: ziel)
                melden("Die Lernenden (\(schuljahr)) sind als verschlüsselte Datei gesichert — sie öffnet mit der "
                       + "Passphrase oder dem Wiederherstellungsschlüssel; „Lernende einlesen …“ liest sie wieder ein.")
            } catch {
                melden("Die Datei konnte nicht geschrieben werden: \(error.localizedDescription)", .warnung)
            }
        }
    }

    /// Die CSV im Klartext — nur nach der Rückfrage (E257).
    @discardableResult
    func lernendenCSVSchreiben(nach ziel: URL) throws -> Int {
        guard lernende.quelle == .behaelter, let bestand = lernende.bestand else {
            throw Uebergangsfehler(text: "die Lernendenverwaltung ist nicht offen")
        }
        let daten = Lernendendatei.csv(bestand)
        try daten.write(to: ziel, options: [.atomic])
        return daten.count
    }

    /// „Lernende als CSV sichern …“ — im Ton des Klartext-Exports.
    func lernendenAlsCSVSichern() {
        guard lernendenExportAngeboten, let schuljahr = lernende.bestand?.schuljahr else {
            melden(Planungsspeicher.lernendenSperrtext, .hinweis)
            return
        }
        fragen("Die Datei wird unverschlüsselt geschrieben — mit den Namen aller Lernenden und ihren Lerngruppen. "
               + "Sie ist für das Zeugnisprogramm der Schule gedacht und liegt im Klartext, wo immer sie "
               + "hinkommt.\n\nFortfahren?",
               bestaetigung: "Als CSV sichern", gefahr: true) { [weak self] in
            self?.lernendenCSVZielWaehlen(schuljahr)
        }
    }

    private func lernendenCSVZielWaehlen(_ schuljahr: String) {
        Systemzugriff.zielWaehlen(name: Lernendendatei.exportName(schuljahr: schuljahr, endung: "csv"),
                                  nachricht: "Lernende als CSV-Datei sichern (unverschlüsselt)",
                                  typ: .commaSeparatedText) { [weak self] ziel in
            guard let self, let ziel else { return }
            do {
                try lernendenCSVSchreiben(nach: ziel)
                melden("Die Lernenden (\(schuljahr)) sind als CSV gesichert — unverschlüsselt.")
            } catch {
                melden("Die Datei konnte nicht geschrieben werden: \(error.localizedDescription)", .warnung)
            }
        }
    }

    /// „Lernende einlesen …“
    func lernendenEinlesenWaehlen() {
        Systemzugriff.quelleWaehlen(nachricht: "Exportierte Lernende einlesen") { [weak self] url in
            guard let self, let url else { return }
            lernendenEinlesen(von: url)
        }
    }

    func lernendenEinlesen(von url: URL) {
        switch Ablage.gebundenLesen(url, hoechstens: Lernendendatei.hoechstgroesse) {
        case .daten(let daten): lernendenEinlesen(daten: daten, von: url)
        case .keine: melden("„\(url.lastPathComponent)“ ist nicht mehr da und wurde nicht eingelesen.", .warnung)
        case .zuGross(let groesse):
            melden("Die Datei ist mit \(groesse / 1024 / 1024) MB zu groß für die Lernendenverwaltung.", .warnung)
        case .unlesbar(let fehler):
            melden(fehler.localizedDescription.ohneSchlusspunkt + " — die Datei wurde nicht eingelesen.", .warnung)
        }
    }

    /// Was ein Einlesen von vornherein ausschließt — `nil`, wenn es gehen kann. Auch vor der Schranke eines
    /// Blatts gefragt, damit danach gleich der wahre Grund kommt (B98, E421 b).
    var lernendenEinlesenAusgeschlossen: (text: String, art: Meldung.Art)? {
        guard tresor != nil, lernende.quelle == .behaelter else { return (Planungsspeicher.lernendenSperrtext, .hinweis) }
        guard lernendenLeer else {
            return ("Die Lernendenverwaltung ist nicht leer — eingelesen wird nur in eine leere.", .warnung)
        }
        return nil
    }

    /// Nur in eine leere Lernendenverwaltung — gefragt, bevor eine Passphrase
    /// nötig wird; unter fremdem Schlüssel über die Freigabe der Datei (E287).
    func lernendenEinlesen(daten: Data, von url: URL) {
        if let grund = lernendenEinlesenAusgeschlossen {
            melden(grund.text, grund.art)
            return
        }
        guard Tresor.istBehaelter(daten), let kopf = try? Tresor.kopfLesen(daten),
              kopf.inhalt == Tresor.Inhalt.lernende.rawValue else {
            melden("„\(url.lastPathComponent)“ ist kein Export der Lernendenverwaltung.", .warnung)
            return
        }
        if let tresor, tresor.passt(zu: kopf) {
            do { lernendenEinlesenKlartext(try tresor.oeffnen(kopf: kopf), von: url) }
            catch { melden(error.localizedDescription, .warnung) }
            return
        }
        entsperrungBeginnen(.datei(daten, url))
    }

    /// Der geöffnete Inhalt: nur, wenn er zur offenen Planung gehört und die
    /// Verwaltung leer ist. `nil`, wenn eingelesen; sonst der gemeldete Grund.
    @discardableResult
    func lernendenEinlesenKlartext(_ klartext: Data, von url: URL) -> String? {
        let grund: String
        do {
            let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(klartext)
            if planung?.erstellt != gelesen.planung {
                grund = "Die Datei gehört zu einer anderen Planung (Schuljahr \(gelesen.schuljahr)) — eingelesen wird "
                    + "nur in die Planung, aus der sie stammt."
            } else if !lernendenLeer {
                grund = "Die Lernendenverwaltung ist nicht leer — eingelesen wird nur in eine leere."
            } else if let fehler = lernendenUebernehmen(gelesen) {
                grund = "Die Lernenden ließen sich nicht sichern (\(fehler.ohneSchlusspunkt))."
            } else {
                let gruppen = gelesen.lerngruppen.filter { $0.archiviert.isEmpty }.count
                melden("\(gelesen.lernende.count) Personen in \(gruppen) Lerngruppen eingelesen — sie liegen jetzt unter "
                       + "dem Schlüssel dieser Ablage."
                       + (bilanz.istLeer ? "" : " Beim Lesen bereinigt: \(bilanz.beschreibung)."))
                // Bindungen an Personen, die die eingelesene Datei nicht trägt (E345 b).
                sitzplanbindungenAbgleichen()
                // Wurde dieselbe Datei vorher abgewiesen, wäre deren „nicht geöffnet“ jetzt falsch (Z-AS7a-03, wie Z-AS2-01).
                vorgemerkteMeldungenVerwerfen(datei: url)
                return nil
            }
        } catch {
            grund = error.localizedDescription
        }
        melden(grund, .warnung)
        return grund
    }
}
