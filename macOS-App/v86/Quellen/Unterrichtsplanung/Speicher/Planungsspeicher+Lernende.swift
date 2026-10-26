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
    /// Modul aus, zu oder gesperrt, entscheidet der Übergang selbst. Liest das
    /// Archiv — das kann es kopieren, melden und einmal schreiben (E465); darum
    /// nur aus einer Handlung rufen, nie aus dem Aufbau einer Ansicht (I1-05).
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
                    text += " Diese Kopie ist kein überholter Stand, sondern ließ sich nicht öffnen \(art); "
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
/// oder das Archiv — die Vorjahre und, oben, das Archivierte des laufenden Schuljahrs (E760).
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
    case mitglieder, mitteilungen, massnahmen, vereinbarungen

    var titel: String {
        switch self {
        case .mitglieder: "Mitglieder"
        case .mitteilungen: "Mitteilungen"
        case .massnahmen: "Maßnahmen"
        // Der vierte Teil (E741, Tabelle 7).
        case .vereinbarungen: "Vereinbarungen"
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
    /// Mehrere gewählt, wenn das Blatt aufgeht — in der Mitgliederliste oder in „Alle Lernenden“, mit der Sammelleiste
    /// (Prüfstand und Abbild, AX4). Unter 2, die es gibt, gilt die eine wie `person`.
    var mehrere: [String] = []
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
    /// Die Suche unter „Alle Lernenden“ und der Filter der Gruppenliste, schon getippt (Prüfstand und Abbild, E359).
    var suche: String?
    var gruppensuche: String?
    /// Die Ordnung der Tabelle „Alle Lernenden“ — wie ein Kopfklick auf diese Spalte (Prüfstand und Abbild, E362).
    var sortierung: Personenspalte?
    /// Die gewählte Person aus der gewählten Gruppe in diese umziehen, wenn das Blatt steht — wie im Menü
    /// „Lerngruppen“ (Prüfstand, E365).
    var umzug: String?
    /// Der Bogen „Zeilen wählen“ der gewählten Gruppe, sobald ihr Kopf erscheint — ohne Verzögerung (Prüfstand und Abbild, E678).
    var zeilenwahl = false
    /// Der Bogen „Rückmeldungsliste“ der gewählten Gruppe mit dieser Auswahl und diesem Kennwort — nur, wenn genau diese
    /// Gruppe beim Öffnen rechts mit dem Teil „Mitteilungen“ steht; beim ersten Erscheinen des Teils verbraucht, sonst
    /// verfällt sie und wartet nicht (Prüfstand und Abbild, AW5, Z-AW5a-06).
    var rueckmeldungsliste: Rueckmeldungsbogenvorgabe?
    /// Der Teil der Ansicht „Archiv“ beim Öffnen — etwa „Lerngruppen“ im Eintrag des laufenden Schuljahrs (Prüfstand und
    /// Abbild, E760).
    var archivteil: Archivteil = .personen
    /// Wohin es nach dem Blatt zurückgeht — aus ⌘K dorthin (E358, E505), sonst ins Hauptfenster.
    var zurueck: Dialogfenster?
}

// ── Suche, Ordnung und Menü „Lerngruppen“ im Blatt (v84, AT2b: F, G, H/I) ─

/// Die Spalten der Tabelle „Alle Lernenden“, nach denen ein Kopfklick ordnet (E362) — die Vorgabe für Prüfstand
/// und Abbild nennt eine davon.
enum Personenspalte: String, CaseIterable, Sendable {
    case nachname, vorname, rufname, lerngruppen, offene, angelegt

    /// Text lokalisiert, Zahlen als Zahl, der Zeitstempel als Text — lexikografisch zugleich zeitlich (E363).
    var vergleicher: KeyPathComparator<Personenzeile> {
        switch self {
        case .nachname: KeyPathComparator(\.nachname, comparator: .localizedStandard)
        case .vorname: KeyPathComparator(\.vorname, comparator: .localizedStandard)
        case .rufname: KeyPathComparator(\.rufname, comparator: .localizedStandard)
        case .lerngruppen: KeyPathComparator(\.lerngruppen, comparator: .localizedStandard)
        case .offene: KeyPathComparator(\.offene)
        case .angelegt: KeyPathComparator(\.angelegt, comparator: String.StandardComparator.lexical)
        }
    }

    /// Die Ordnung nach einem Kopfklick auf diese Spalte aus der Vorgabe heraus — sie vorn, die Vorgabe dahinter.
    var ordnung: [KeyPathComparator<Personenzeile>] {
        Tabellenordnung.mitVorigem([vergleicher], vorher: Personenzeile.vorgabe)
    }
}

/// Was das Blatt „Lernende“ zeigt — rein, damit die Suite es prüft.
enum Lernendenblatt {
    /// Je Zeile der Planung ihr Titel („6a · Biologie“) — wonach die Suche der Gruppenliste die verknüpften Zeilen
    /// trifft (E671). Ohne Planung keine.
    static func zeilentitel(_ planung: Planung?) -> [Zeilenbindung: String] {
        guard let p = planung else { return [:] }
        return Dictionary(p.klassen.map { (Zeilenbindung(planung: p.erstellt, klasseId: $0.id), $0.beschriftung) },
                          uniquingKeysWith: { erste, _ in erste })
    }

    /// Die Gruppenliste: aktive, mit dem Schalter auch archivierte, gefiltert nach Name und verknüpften Zeilen
    /// (E359, E480, E671; `zeilentitel` wie `zeilentitel(_:)`) und geordnet wie alle Listen.
    static func gruppenliste(_ bestand: Lernendenbestand, archivierte: Bool, suche: String,
                             zeilentitel: [Zeilenbindung: String] = [:]) -> [Lerngruppe] {
        bestand.lerngruppen
            .filter { g in
                (archivierte || g.archiviert.isEmpty)
                    && Lerngruppe.trifft(g, suche, zeilen: g.zeilen.compactMap { zeilentitel[$0] })
            }
            .sorted(by: Lerngruppe.vorgehen)
    }

    /// Die rechts gezeigte Lerngruppe (E685): nur, solange das Suchfeld sie in der Liste stehen lässt — wie „Alle Lernenden“.
    /// Archivierte zählen mit: Ob eine archivierte gewählt bleibt, regelt das Blatt selbst (`auswahlPruefen`, Z-AT15N-13).
    static func sichtbareWahl(_ gruppe: String?, in bestand: Lernendenbestand, suche: String,
                              zeilentitel: [Zeilenbindung: String]) -> String? {
        guard let gruppe else { return nil }
        return gruppenliste(bestand, archivierte: true, suche: suche, zeilentitel: zeilentitel).contains { $0.id == gruppe }
            ? gruppe : nil
    }

    /// Die Zeilen der Planung mit Sitzplan — nur an ihnen braucht es die eine Lerngruppe (E674, E689, Z-AT15N-01); Klassenleitung
    /// und „Weiteres“ tragen oft mehrere.
    static func sitzplanzeilen(_ planung: Planung?) -> Set<Zeilenbindung> {
        guard let planung else { return [] }
        return Set(planung.klassen.filter(\.erlaubtSitzplan).map { Zeilenbindung(planung: planung.erstellt, klasseId: $0.id) })
    }

    /// Im Menü „Zusammenführen mit“ die erste Zeile einer Lerngruppe — ohne Titel wie im Kopf (E683, Z-AT15N-09).
    static func ersteZeile(_ g: Lerngruppe, zeilentitel: [Zeilenbindung: String], planung: String?) -> String {
        if let erste = g.zeilen.lazy.compactMap({ zeilentitel[$0] }).first { return erste }
        if g.zeilen.isEmpty { return "keine Zeile" }
        let entfernt = planung.map { p in g.zeilen.filter { $0.planung == p }.count } ?? 0
        let aussen = g.zeilen.count - entfernt
        let teile = (entfernt > 0 ? ["\(entfernt) entfernte \(entfernt == 1 ? "Zeile" : "Zeilen")"] : [])
            + (aussen > 0 ? ["\(aussen) \(aussen == 1 ? "Zeile" : "Zeilen") außerhalb dieser Planung"] : [])
        return teile.joined(separator: " und ")
    }

    /// Das Suchfeld, wenn eine Lerngruppe rechts stehen soll (Z-AT15M-01, -02, Z-AT15L-02): leer, wenn es sie verdeckt, sonst wie
    /// es ist — wenn „Übernehmen“ die Namensliste nach vorn holt, und nach dem Anlegen (Z-AT15K-03).
    static func sucheFuerWahl(_ gruppe: String?, in bestand: Lernendenbestand, suche: String,
                              zeilentitel: [Zeilenbindung: String]) -> String {
        guard gruppe != nil, sichtbareWahl(gruppe, in: bestand, suche: suche, zeilentitel: zeilentitel) == nil else { return suche }
        return ""
    }

    /// Der Hinweis nach dem Zurückholen (E689), wenn Zeilen inzwischen mit anderen Lerngruppen verknüpft sind.
    static func zurueckgeholtHinweis(_ name: String, besetzt: [BesetzteZeile], zeilentitel: [Zeilenbindung: String]) -> String? {
        let genannt = besetzt.compactMap { b in zeilentitel[b.zeile].map { (titel: $0, andere: b.andere) } }
        guard let erste = genannt.first else { return nil }
        func namen(_ n: [String]) -> String { n.map { "„\($0)“" }.joined(separator: ", ") }
        if genannt.count == 1 {
            return "„\(name)“ ist zurückgeholt, ohne die Zeile „\(erste.titel)“ — dort \(erste.andere.count == 1 ? "ist" : "sind") "
                + "\(namen(erste.andere)) verknüpft."
        }
        return "„\(name)“ ist zurückgeholt, ohne die Zeilen \(namen(genannt.map(\.titel))) — dort sind inzwischen andere "
            + "Lerngruppen verknüpft."
    }

    /// „Zurückholen“ einer Lerngruppe — im Blatt und im Archiv des laufenden Schuljahrs derselbe Weg (E689, E760): der Stand
    /// danach und der Hinweis, wenn Zeilen mit Sitzplan inzwischen eine andere tragen. Der Name aus dem Stand, auf den es
    /// wirkt — er trägt einen eben getippten (Z-AT15N-08). Eine aktive Lerngruppe bleibt, wie sie ist: Sonst verlöre sie an
    /// einer geteilten Zeile ihre Bindung.
    static func gruppeZurueckholen(_ id: String, in entwurf: Lernendenbestand, planung: Planung?,
                                   jetzt: String) -> (bestand: Lernendenbestand, hinweis: String?) {
        guard let g = entwurf.lerngruppen.first(where: { $0.id == id }), !g.archiviert.isEmpty else { return (entwurf, nil) }
        let sitz = sitzplanzeilen(planung)
        let besetzt = entwurf.besetzteZeilen(von: id, unter: sitz)
        return (entwurf.mitZurueckgeholterGruppe(id, jetzt: jetzt, sitzplanzeilen: sitz),
                zurueckgeholtHinweis(g.name, besetzt: besetzt, zeilentitel: zeilentitel(planung)))
    }

    /// Die Zeilen von „Alle Lernenden“: erst gesucht (E360) und nach „Nur mit offenen Anliegen“ gefiltert, dann
    /// geordnet (E363) — die Kennung entscheidet zuletzt.
    static func uebersicht(_ verzeichnis: Lernendenverzeichnis, suche: String, archivierte: Bool, nurOffen: Bool,
                           ordnung: [KeyPathComparator<Personenzeile>]) -> [Personenzeile] {
        let personen = verzeichnis.suche(suche, archivierte: archivierte)
            .filter { !nurOffen || verzeichnis.offeneZahl(von: $0.id) > 0 }
        return Tabellenordnung.geordnet(verzeichnis.personenzeilen(personen, archivierteGruppen: archivierte), nach: ordnung)
    }

    /// Der Zusatz in der Mitgliederliste (E370): „auch in 6b · Chemie, AG“ — `nil` ohne weitere Gruppe.
    static func auchIn(_ gruppen: [Lerngruppe]) -> String? {
        gruppen.isEmpty ? nil : "auch in " + gruppen.map(\.beschriftung).joined(separator: ", ")
    }

    /// „12 Personen in 2 Lerngruppen“ — die Unterzeile des Blatts und die Zusammenfassung in ⌘K (E356, Z-AT4-03).
    static func zaehlzeile(personen: Int, gruppen: Int) -> String {
        "\(personen) \(personen == 1 ? "Person" : "Personen") in \(gruppen) " + (gruppen == 1 ? "Lerngruppe" : "Lerngruppen")
    }

    /// Der Zähler über der Tabelle „Alle Lernenden“: „12 Personen“, mit Suche oder Filter „3 von 12 Personen“.
    static func zaehler(treffer: Int, gesamt: Int, gefiltert: Bool) -> String {
        gefiltert ? "\(treffer) von \(gesamt) \(gesamt == 1 ? "Person" : "Personen")"
                  : "\(treffer) \(treffer == 1 ? "Person" : "Personen")"
    }

    /// „12 von 40 Plätzen“ unter der Mitgliederliste — archivierte belegen einen Platz wie in der Jahresdatei (E369,
    /// E499); sind sie ausgeblendet, sagt der Zusatz, wie viele es sind.
    static func plaetze(_ g: Lerngruppe, _ verzeichnis: Lernendenverzeichnis, archivierte: Bool) -> String {
        let alle = verzeichnis.mitglieder(g.id, archivierte: true).count
        let ausgeblendet = archivierte ? 0 : alle - verzeichnis.mitglieder(g.id, archivierte: false).count
        return "\(alle) von \(Kennwerte.maxMitgliederJeLerngruppe) Plätzen"
            + (ausgeblendet > 0 ? " (davon \(ausgeblendet) archiviert)" : "")
    }

    /// Was eine leere Liste sagt, wenn Suche oder Filter nichts übrig lassen — `nil` ohne beides.
    static func leerHinweis(suche: String, nurOffen: Bool) -> String? {
        let text = suche.trimmingCharacters(in: .whitespaces)
        if !Lernendenverzeichnis.suchworte(text).isEmpty { return "Nichts passt zu „\(text)“." }
        return nurOffen ? "Keine Person mit offenen Anliegen." : nil
    }

    /// Ob die Ordnung nach dieser Spalte vorn ordnet — ihr Kopf steht dann hervorgehoben (E498).
    static func vorn<Zeile>(_ ordnung: [KeyPathComparator<Zeile>], _ pfad: PartialKeyPath<Zeile>) -> Bool {
        ordnung.first?.keyPath == pfad
    }
}

extension Lernendenblatt {
    /// Der Kopf einer Lerngruppe (E669): „Verknüpft mit: 6a · Biologie, Klassenleitung · 6a“ in der Folge der Bindungen;
    /// Zeilen, die die geöffnete Planung nicht führt, als Zahl dahinter; ohne Bindung „Mit keiner Zeile verknüpft“.
    /// `planung`: die Herkunft der geöffneten Planung — Bindungen an Zeilen, die sie nicht mehr führt, heißen „entfernte
    /// Zeile“ (E683: Entfernen löst die Bindung nicht, damit ⌘Z sie zurückbringt); Zeilen anderer Planungen „außerhalb“.
    static func verknuepft(_ g: Lerngruppe, zeilentitel: [Zeilenbindung: String], planung: String? = nil) -> String {
        let titel = g.zeilen.compactMap { zeilentitel[$0] }
        let ohne = g.zeilen.filter { zeilentitel[$0] == nil }
        let entfernt = planung.map { p in ohne.filter { $0.planung == p }.count } ?? 0
        let aussen = ohne.count - entfernt
        var zusaetze: [String] = []
        if entfernt > 0 { zusaetze.append("\(entfernt) entfernte \(entfernt == 1 ? "Zeile" : "Zeilen")") }
        if aussen > 0 { zusaetze.append("\(aussen) \(aussen == 1 ? "Zeile" : "Zeilen") außerhalb dieser Planung") }
        if titel.isEmpty && zusaetze.isEmpty { return "Mit keiner Zeile verknüpft" }
        if titel.isEmpty && entfernt == 0 { return "Verknüpft mit " + zusaetze[0] }
        var text = titel.joined(separator: ", ")
        for (stelle, zusatz) in zusaetze.enumerated() {
            text += text.isEmpty ? zusatz : (stelle == zusaetze.count - 1 ? " und " : ", ") + zusatz
        }
        return "Verknüpft mit: " + text
    }

    /// Aktive Lerngruppen, die heißen wie `gruppe` — Groß/Klein und Leerraum am Rand unerheblich —, ohne sie selbst, in der
    /// Folge der Listen: die Kandidaten zum Zusammenführen (E667). Eine archivierte hat keine.
    static func gleichnamige(_ gruppe: String, in bestand: Lernendenbestand) -> [Lerngruppe] {
        func schluessel(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let g = bestand.lerngruppen.first(where: { $0.id == gruppe && $0.archiviert.isEmpty }) else { return [] }
        return bestand.lerngruppen
            .filter { $0.id != gruppe && $0.archiviert.isEmpty && schluessel($0.name) == schluessel(g.name) }
            .sorted(by: Lerngruppe.vorgehen)
    }

    /// Die Rückfrage vor dem Zusammenführen (E667, E672).
    static func zusammenfuehrenFrage(name: String, andere: Int) -> String {
        "Zwei Lerngruppen „\(name)“ zusammenführen?\n\nMitglieder, Zeilen, Mitteilungen und Maßnahmen der anderen „\(name)“ "
            + "(\(andere) \(andere == 1 ? "Mitglied" : "Mitglieder")) gehen auf diese über. Die andere wird archiviert, mit ihrer "
            + "Liste der Mitglieder."
    }
}

/// Der Bogen „Zeilen wählen“ (E669): je Zeile der Planung, die eine Lerngruppe tragen kann (nicht Vertretungen), ein
/// Kästchen — gewählt die Zeilen der Lerngruppe; andere aktive Lerngruppen an der Zeile als Hinweis (E670).
enum Zeilenwahl {
    struct Zeile: Identifiable, Equatable, Sendable {
        let id: String
        let titel: String
        let gewaehlt: Bool
        /// „auch: 6b, Bio-AG“ — `nil` ohne andere.
        let auch: String?
    }

    static func zeilen(_ planung: Planung, bestand: Lernendenbestand, gruppe: String) -> [Zeile] {
        let eigene = Set(bestand.lerngruppen.first { $0.id == gruppe }?.zeilen ?? [])
        return planung.klassen.filter { $0.erlaubt(.verwaltung) }.map { k in
            let z = Zeilenbindung(planung: planung.erstellt, klasseId: k.id)
            let andere = bestand.gruppen(an: z).filter { $0.id != gruppe }
            return Zeile(id: k.id, titel: k.beschriftung, gewaehlt: eigene.contains(z),
                         auch: andere.isEmpty ? nil : "auch: " + andere.map(\.beschriftung).joined(separator: ", "))
        }
    }
}

/// Was das Menü „Lerngruppen“ einer Person anbietet (E365, E369, E497): je aktiver Lerngruppe ein Häkchen; im Teil
/// „Lerngruppen“ dazu „Umziehen nach“ — nur in Gruppen, in denen die Person noch nicht ist. Volle Gruppen stehen
/// abgeblendet mit „(voll)“; archivierte stehen nicht im Menü.
struct Mitgliedschaftsmenue: Equatable, Sendable {
    struct Eintrag: Identifiable, Equatable, Sendable {
        let id: String
        let titel: String
        let mitglied: Bool
        let waehlbar: Bool
    }

    var haekchen: [Eintrag] = []
    /// Leer ohne Quelle (Teil „Alle Lernenden“) oder wenn die Person nicht in der Quelle steht.
    var umziehen: [Eintrag] = []

    init(person: String, aus quelle: String?, bestand: Lernendenbestand) {
        let aktiv = bestand.lernende.contains { $0.id == person && $0.archiviert.isEmpty }
        let gruppen = bestand.lerngruppen.filter { $0.archiviert.isEmpty }.sorted(by: Lerngruppe.vorgehen)
        func titel(_ g: Lerngruppe, voll: Bool) -> String { voll ? "\(g.beschriftung) (voll)" : g.beschriftung }
        haekchen = gruppen.map { g in
            let mitglied = g.mitglieder.contains(person)
            let voll = !mitglied && bestand.istVoll(g.id)
            // Nehmen geht immer; aufnehmen nur eine aktive Person in eine Gruppe mit Platz (E369).
            return Eintrag(id: g.id, titel: titel(g, voll: voll), mitglied: mitglied, waehlbar: mitglied || (aktiv && !voll))
        }
        guard let quelle, gruppen.first(where: { $0.id == quelle })?.mitglieder.contains(person) == true else { return }
        umziehen = gruppen.filter { $0.id != quelle && !$0.mitglieder.contains(person) }.map { g in
            let voll = bestand.istVoll(g.id)
            return Eintrag(id: g.id, titel: titel(g, voll: voll), mitglied: false, waehlbar: aktiv && !voll)
        }
    }
}

// ── Mehrere Gewählte: Auswahl, Sammelleiste, Menü (v86, AX4, E756–E759, Tabelle 13) ──

extension Lernendenblatt {
    /// Die Auswahl der Liste aus beidem: mehrere, sonst die eine Person wie bisher (E756 b). Die Liste wählt wie macOS-Tabellen:
    /// ⌘-Klick, ⇧-Klick, ⌘A.
    static func auswahl(person: String?, mehrere: Set<String>) -> Set<String> {
        return mehrere.count >= 2 ? mehrere : Set([person].compactMap { $0 })
    }

    /// Die Auswahl der Liste geteilt: ab 2 Gewählten `mehrere` und keine Person — sonst die eine wie heute.
    static func auswahlTeilen(_ neu: Set<String>) -> (person: String?, mehrere: Set<String>) {
        return neu.count >= 2 ? (nil, neu) : (neu.first, [])
    }

    /// Nach einem neuen Stand, Wechsel der Lerngruppe oder der Ansicht: gewählt bleibt nur, wer in der Liste steht. Bleibt
    /// 1, ist es die eine Person wie heute; `mehrere` leer heißt: nichts zu tun.
    static func auswahlNach(sichtbar: [String], mehrere: Set<String>) -> (person: String?, mehrere: Set<String>) {
        let bleiben = mehrere.intersection(sichtbar)
        return bleiben.count >= 2 ? (nil, bleiben) : (bleiben.first, [])
    }

    /// Die Gewählten in der Folge der Liste — `nil` unter 2: Dann steht die Leiste der einen Person wie heute.
    static func sammelauswahl(sichtbar: [String], mehrere: Set<String>) -> [String]? {
        let gewaehlt = sichtbar.filter(mehrere.contains)
        return gewaehlt.count >= 2 ? gewaehlt : nil
    }

    /// Die aktiven unter den Gewählten, in ihrer Folge — an ihnen wirken Aufnehmen, Umziehen, Herausnehmen und Archivieren
    /// (Vorlage 11). Sind es keine, sind diese Griffe gesperrt.
    static func aktive(_ gewaehlt: [String], in bestand: Lernendenbestand) -> [String] {
        let aktiv = Set(bestand.lernende.filter { $0.archiviert.isEmpty }.map(\.id))
        return gewaehlt.filter(aktiv.contains)
    }

    /// Wen „Endgültig löschen …“ der Sammelleiste nimmt: alle Gewählten, die es gibt, auch archivierte — wie bei einer
    /// Person (E839). In ihrer Folge, ohne Doppelte.
    static func zuLoeschen(_ gewaehlt: [String], in bestand: Lernendenbestand) -> [String] {
        let da = Set(bestand.lernende.map(\.id))
        var gesehen = Set<String>()
        return gewaehlt.filter { da.contains($0) && gesehen.insert($0).inserted }
    }

    /// Was ein Sammelgriff im Blatt auslöst (Z-AX4-01).
    enum Sammelausgang: Equatable, Sendable {
        /// Der Griff ändert nichts — kein Schritt.
        case nichts
        /// An der Grenze (E758 a): die Meldung, nichts geändert, kein Schritt.
        case meldung(String)
        /// Ein Schritt, der Name mit der Zahl der Personen, die er betrifft (E759).
        case schritt(name: String, bestand: Lernendenbestand)
    }

    static func sammelausgang(_ ergebnis: Lernendenbestand.Sammelergebnis, name: (Int) -> String) -> Sammelausgang {
        if let grund = ergebnis.grund { return .meldung(grund) }
        guard ergebnis.zahl > 0 else { return .nichts }
        return .schritt(name: name(ergebnis.zahl), bestand: ergebnis.bestand)
    }

    /// „3 gewählt“ — der Kopf der Sammelleiste (Tabelle 13).
    static func sammelkopf(_ zahl: Int) -> String { "\(zahl) gewählt" }

    /// Die Hilfe am Menü „Lerngruppen“ der Sammelleiste (Tabelle 13). In „Alle Lernenden“ ohne „Umziehen nach“ nur der
    /// erste Teil (E836). Gesperrt hat das Menü keine Hilfe, wie das Menü einer Person (E791, E845).
    static func sammelmenueHilfe(mitQuelle: Bool) -> String {
        mitQuelle ? "Die Gewählten in eine weitere Lerngruppe aufnehmen oder aus dieser in eine andere umziehen lassen"
            : "Die Gewählten in eine weitere Lerngruppe aufnehmen"
    }

    static let sammelHerausnehmenHilfe = "Die Gewählten verbleiben in der Lernendenverwaltung. Beim Übernehmen werden sie "
        + "auch aus dem Sitzplan dieser Lerngruppe entfernt."
    static let sammelArchivierenHilfe = "Die Gewählten aus den Listen nehmen — ihre Einträge bleiben"
    /// Nicht in Tabelle 13 — gebildet wie die Hilfe an einer Person (E837).
    static let sammelLoeschenHilfe = "Die Gewählten samt ihren Rückläufen und Einträgen dieses Schuljahrs löschen — mit "
        + "Rückfrage"

    /// Der Sperrgrund an „Aus der Lerngruppe nehmen“ und „Archivieren“ der Sammelleiste, wenn nur Archivierte gewählt sind
    /// (E845, wie E761).
    static let sammelSperrgrund = "Erst eine aktive Person wählen"

    /// Die Hilfe an „Aus der Lerngruppe nehmen“ und „Archivieren“ der Sammelleiste: frei ihr Wortlaut, gesperrt der
    /// Sperrgrund (E845).
    static func sammelhilfe(_ text: String, gesperrt: Bool) -> String {
        gesperrt ? sammelSperrgrund : text
    }
}

/// Was das Menü „Lerngruppen“ der Sammelleiste anbietet (E758 a, Tabelle 13): „Auch aufnehmen in“ jede aktive Lerngruppe, in
/// der noch nicht alle aktiven Gewählten stehen; „Umziehen nach“ nur mit Quelle (im Teil „Lerngruppen“) jede andere aktive,
/// in der noch nicht alle stehen. Volle stehen abgeblendet mit „(voll)“ wie bei einer Person (E369); ob der Platz für alle
/// reicht, sagt der Griff — sonst die Meldung, und nichts ist geändert.
struct Sammelmenue: Equatable, Sendable {
    var aufnehmen: [Mitgliedschaftsmenue.Eintrag] = []
    var umziehen: [Mitgliedschaftsmenue.Eintrag] = []

    init(personen: [String], aus quelle: String?, bestand: Lernendenbestand) {
        let aktiv = Set(bestand.lernende.filter { $0.archiviert.isEmpty }.map(\.id)).intersection(personen)
        guard !aktiv.isEmpty else { return }
        let gruppen = bestand.lerngruppen.filter { $0.archiviert.isEmpty }.sorted(by: Lerngruppe.vorgehen)
        func eintrag(_ g: Lerngruppe) -> Mitgliedschaftsmenue.Eintrag {
            let voll = bestand.istVoll(g.id)
            return .init(id: g.id, titel: voll ? "\(g.beschriftung) (voll)" : g.beschriftung, mitglied: false, waehlbar: !voll)
        }
        let offen = gruppen.filter { !aktiv.isSubset(of: $0.mitglieder) }
        aufnehmen = offen.map(eintrag)
        guard let quelle, gruppen.first(where: { $0.id == quelle }).map({ !aktiv.isDisjoint(with: $0.mitglieder) }) == true
        else { return }
        umziehen = offen.filter { $0.id != quelle }.map(eintrag)
    }
}

/// Was das Blatt „Lernende“ dem Speicher für die Fragen beim Beenden
/// hereinreicht (E300, E303) — Griffe in seinen Zustand.
@MainActor
struct Lernendenblattgriff {
    /// Bögen schließen und das Ausstehende aus den Feldern übernehmen.
    var vorbereiten: () -> Void = {}
    /// Ob ein Bogen (Import, Maßnahme/Termin, Zeilen wählen, Rückmeldungsliste) auf dem Blatt steht — und ihn schließen.
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

    /// Die Zusammenfassung neben „Lernende …“ in ⌘K (E356): gezählt wie die Unterzeile des Blatts — aktive Personen
    /// und Lerngruppen —, ohne offene Verwaltung der Grund.
    var lernendenZusammenfassung: String {
        switch lernende.quelle {
        case .behaelter:
            return Lernendenblatt.zaehlzeile(personen: lernende.verzeichnis?.alle.count ?? 0,
                                             gruppen: lernende.verzeichnis?.gruppen().count ?? 0)
        case .aus:
            return "keine Lernendenverwaltung — nur mit eingeschalteter Verschlüsselung"
        case .zu, .gesperrt:
            return lernende.sperrhinweis ?? ""
        }
    }

    /// Der Hilfetext am Knopf „Lernende …“ in ⌘K (E508).
    var lernendenKnopfhilfe: String {
        switch lernende.quelle {
        case .behaelter: "Die Lernendenverwaltung öffnen (⌘L)"
        case .aus: "Lernendenverwaltung — nur mit eingeschalteter Verschlüsselung"
        case .zu, .gesperrt: lernende.sperrhinweis ?? ""
        }
    }

    /// Der Hilfetext am Personen-Symbol einer Zeile, solange die Lernendenverwaltung nicht offen ist (E510).
    var lerngruppenhilfeOhneVerwaltung: String {
        lernende.quelle == .aus ? "Lerngruppe — nur mit eingeschalteter Verschlüsselung" : lernende.sperrhinweis ?? ""
    }

    /// Das Blatt „Lernende“ geht zu: den Rückweg vormerken (E358) — Muster `sitzplanDialogSchliessen`. Das
    /// Schließen selbst übernimmt das Blatt; ⌘Q und ein Sprung räumen die Vormerkung (`alleDialogeSchliessen`).
    /// Nur, solange das Blatt das offene ist: Ein zweites Schließen aus der Lücke nach einer Antwort fände ⌘K
    /// schon wieder vor (Z-AT4-01).
    func lernendenblattSchliessen(zurueck: Dialogfenster?) {
        guard offenerDialog == .lernende, let zurueck else { return }
        dialogVormerken(zurueck)
    }

    /// ⌘L — oder der Hinweis, warum nicht. `ort`: wo die Rückfrage hängt,
    /// wenn der Versuch aus einem Blatt kommt. `zurueck`: das Blatt, das nach
    /// dem Blatt „Lernende“ wieder aufgeht (E358).
    func lernendenBlattOeffnen(gruppe: String? = nil, ort: Rueckfrageort = .hauptansicht,
                               zurueck: Dialogfenster? = nil) {
        guard planung != nil else { return }
        switch lernende.quelle {
        case .behaelter:
            lernendenVorgabe = Lernendenvorgabe(gruppe: gruppe, zurueck: zurueck)
            dialogOeffnen(.lernende)
        case .aus:
            fragen(Self.lernendenSperrtext, bestaetigung: "Verschlüsselung einrichten …", ort: ort,
                   nachDemSchliessen: true) { [weak self] in
                self?.verschluesselungEinrichten()
            }
        case .zu, .gesperrt:
            let hinweis = lernende.sperrhinweis ?? "Die Lernendenverwaltung ist gerade nicht verfügbar."
            // Aus einem Blatt die Rückfrage an ihm — die Kapsel läge dahinter (E357, Z14c4-14).
            if ort == .hauptansicht {
                melden(hinweis, .warnung)
            } else {
                fragen(hinweis, bestaetigung: "Verstanden", ort: ort, ablehnung: "") {}
            }
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
    /// anfasste, behält den Stand der Sitzung (offener Punkt 3). `herkunftVersucht`: Der Aufrufer hat die Herkunft eben selbst
    /// zu sichern versucht und sagt das Ergebnis (E681).
    @discardableResult
    func lernendenUebernehmen(_ neu: Lernendenbestand, ausgang: Lernendenbestand? = nil,
                              herkunftVersucht: Bool = false) -> String? {
        termineUebernehmen(neu, ausgang: ausgang, herkunftVersucht: herkunftVersucht)
    }

    // ── Rückfragen am Blatt — mit den Zahlen dessen, was geht ─────────────

    private static func anzahl(_ n: Int, _ eins: String, _ mehr: String) -> String {
        "\(n) \(n == 1 ? eins : mehr)"
    }

    /// „1 Maßnahme“ — und „, 1 Vereinbarung“ und „, 2 Termine“ dahinter, wenn sie darunter sind (E290, Tabelle 13a).
    static func massnahmenUndTermine(_ zahl: Lernendenbestand.Loeschzahl) -> String {
        anzahl(zahl.anliegen - zahl.termine - zahl.vereinbarungen, "Maßnahme", "Maßnahmen")
            + (zahl.vereinbarungen > 0 ? ", " + anzahl(zahl.vereinbarungen, "Vereinbarung", "Vereinbarungen") : "")
            + (zahl.termine > 0 ? ", " + anzahl(zahl.termine, "Termin", "Termine") : "")
    }

    /// „Die Mitteilung“, „Die Maßnahme“, „Den Termin“ — und das Fürwort dazu.
    static func benennung(_ art: Anliegenart) -> (art: String, mit: String) {
        switch art {
        case .mitteilung: ("Die Mitteilung", "Mit ihr")
        case .massnahme: ("Die Maßnahme", "Mit ihr")
        case .termin: ("Den Termin", "Mit ihm")
        case .vereinbarung: ("Die Vereinbarung", "Mit ihr")
        }
    }

    /// E811 (statt E762): „Mit ihr gehen die Stände von 2 Personen.“ — ein Stand ist kein Rücklauf (E750).
    static func vereinbarungStaende(_ personen: Int) -> String {
        personen == 1 ? "Mit ihr geht der Stand von 1 Person."
            : "Mit ihr gehen die Stände von \(personen) Personen."
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
        // Die Tische der Person im Sitzplan lassen los (E304).
        let tische = sitzplaene.bindungen(an: [id])
        let text = "„\(person.anzeigename)“ endgültig löschen?\n\n"
            + "Mit der Person gehen in diesem Schuljahr ihre Mitgliedschaft in "
            + "\(Self.anzahl(gruppen, "Lerngruppe", "Lerngruppen")), "
            + "\(Self.anzahl(zahl.rueckmeldungen, "Rücklauf", "Rückläufe")), "
            + "\(Self.massnahmenUndTermine(zahl)) und "
            + "\(Self.anzahl(zahl.eintraege, "Eintrag", "Einträge")). Frühere Schuljahre im Archiv bleiben unberührt."
            + Self.vorhabenSatz(vorhaben) + Self.tischeSatz(tische)
            + "\n\nArchivieren nimmt die Person nur aus den Listen; alles bleibt."
        fragen(text, bestaetigung: "Endgültig löschen", gefahr: true, ort: .lernende, nachDemSchliessen: true) { dann(neu) }
    }

    /// Der Absatz zu den Vorhaben, die mit den Terminen gehen (E293, W2-05) — leer ohne.
    private static func vorhabenSatz(_ vorhaben: Int) -> String {
        vorhaben == 0 ? "" : "\n\nBeim „Übernehmen“ \(vorhaben == 1 ? "geht" : "gehen") auch \(vorhaben) Vorhaben in der Planung."
    }

    /// Der Absatz zu den Tischen im Sitzplan, die loslassen (E304) — leer ohne.
    private static func tischeSatz(_ tische: Int) -> String {
        tische == 0 ? "" : "\n\nAn \(tische == 1 ? "1 Tisch" : "\(tische) Tischen") im Sitzplan wird die "
            + "Zuordnung gelöst; der Name am Tisch bleibt."
    }

    /// Die Namen in der Rückfrage für mehrere (Tabelle 13): „„Abel, Ben“, „Çelik, Cem“, „Dietz, Dora“.“ — ab 6 die ersten 5
    /// und „und 7 weitere“.
    static func namensliste(_ namen: [String]) -> String {
        let gezeigt = namen.count >= 6 ? Array(namen.prefix(5)) : namen
        return gezeigt.map { "„\($0)“" }.joined(separator: ", ")
            + (namen.count >= 6 ? " und \(namen.count - 5) weitere" : "") + "."
    }

    /// „Endgültig löschen …“ für mehrere Gewählte (E757 c, Tabelle 13, 13a): eine Rückfrage für alle, die Zahlen über alle —
    /// Lerngruppen, in denen eine von ihnen Mitglied ist, je einmal. `ids` in der Folge der Liste. Bleibt 1, fragt es wie
    /// bei einer Person.
    func personenLoeschenFragen(_ ids: [String], in entwurf: Lernendenbestand,
                                dann: @escaping @MainActor (Lernendenbestand) -> Void) {
        var gesehen = Set<String>()
        let personen = ids.filter { gesehen.insert($0).inserted }.compactMap { id in entwurf.lernende.first { $0.id == id } }
        guard personen.count >= 2 else {
            if let eine = personen.first { personLoeschenFragen(eine.id, in: entwurf, dann: dann) }
            return
        }
        guard !frageSperrtBefehl() else { return }
        let menge = Set(personen.map(\.id))
        let gruppen = entwurf.lerngruppen.filter { !menge.isDisjoint(with: $0.mitglieder) }.count
        let (neu, zahl) = entwurf.ohnePersonen(personen.map(\.id))
        // Über eine Menge: Bei 2000 Anliegen wäre die Suche je Termin quadratisch (Z-AX4-02).
        let bleiben = Set(neu.anliegen.map(\.id))
        let vorhaben = entwurf.anliegen.filter { a in a.art == .termin && !bleiben.contains(a.id) && hatVorhaben(a.id) }.count
        let tische = sitzplaene.bindungen(an: menge)
        let text = "\(personen.count) Personen endgültig löschen?\n\n"
            + Self.namensliste(personen.map(\.anzeigename)) + "\n\n"
            + "Mit ihnen gehen in diesem Schuljahr ihre Mitgliedschaften in "
            + "\(Self.anzahl(gruppen, "Lerngruppe", "Lerngruppen")), "
            + "\(Self.anzahl(zahl.rueckmeldungen, "Rücklauf", "Rückläufe")), "
            + "\(Self.massnahmenUndTermine(zahl)) und "
            + "\(Self.anzahl(zahl.eintraege, "Eintrag", "Einträge")). Frühere Schuljahre im Archiv bleiben unberührt."
            + Self.vorhabenSatz(vorhaben) + Self.tischeSatz(tische)
            + "\n\nArchivieren nimmt die Personen nur aus den Listen; alles bleibt."
        fragen(text, bestaetigung: "Endgültig löschen", gefahr: true, ort: .lernende, nachDemSchliessen: true) { dann(neu) }
    }

    func anliegenLoeschenFragen(_ id: String, in entwurf: Lernendenbestand,
                                dann: @escaping @MainActor (Lernendenbestand) -> Void) {
        guard !frageSperrtBefehl(), let anliegen = entwurf.anliegen.first(where: { $0.id == id }) else { return }
        let (neu, zahl) = entwurf.ohneAnliegen(id)
        let (art, mit) = Self.benennung(anliegen.art)
        // Eine Vereinbarung nennt ihre Stände, keine Rückläufe (Tabelle 13a, E811).
        let folge = anliegen.art == .vereinbarung ? Self.vereinbarungStaende(anliegen.betroffene.count)
            : "\(mit) \(zahl.rueckmeldungen == 1 ? "geht" : "gehen") "
                + "\(Self.anzahl(zahl.rueckmeldungen, "Rücklauf", "Rückläufe"))."
        let text = "\(art) „\(anliegen.titel)“ löschen?\n\n" + folge
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
        guard let aenderungen = griff.aenderungen() else { return false }
        nachVornFuerFrage()
        // Die Folgen für die Sitzpläne stehen in der Frage — die Meldung danach ginge mit dem Beenden unter (E495).
        let absatz = Self.sitzplanfolgenAbsatz(sitzplanfolgenVorschau(aenderungen)).map { "\n\n" + $0 } ?? ""
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
               + "gehen seine Änderungen beim Beenden verloren." + absatz,
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

// ── Die Sitzpläne nach dem „Übernehmen“ (v84, E367, E390) ─────────────────

/// Was „Übernehmen“ an den Sitzplänen ändert — rein, damit die Suite es prüft. Nur für die Jahresdatei der
/// geltenden Planung; sonst nichts.
struct Sitzplanfolgen: Equatable, Sendable {
    /// Je Zeile der Planung die Personen, deren Tisch geht: Sie haben eine dort gebundene Lerngruppe verlassen und
    /// stehen in keiner anderen dort mehr (E670) —
    /// durch Umzug, „Aus der Lerngruppe nehmen“ oder den IServ-Import (E367, E368).
    var entfernen: [String: Set<String>] = [:]
    /// Je Person der Name am Tisch vor und nach der Änderung (E390).
    var namen: [String: Sitzplan.Namenswechsel] = [:]

    var istLeer: Bool { entfernen.isEmpty && namen.isEmpty }

    init(vorher: Lernendenbestand, nachher: Lernendenbestand, planung: String?) {
        guard let planung, nachher.planung == planung else { return }
        for (gruppe, personen) in Lernendenbestand.verlasseneMitgliedschaften(vorher: vorher, nachher: nachher) {
            guard let g = nachher.lerngruppen.first(where: { $0.id == gruppe }) else { continue }
            for zeile in g.zeilen where zeile.planung == planung {
                // Wer an dieser Zeile noch in einer anderen Lerngruppe steht, behält seinen Tisch.
                let bleiben = Set(nachher.gruppen(an: zeile).filter { $0.id != gruppe }.flatMap(\.mitglieder))
                let weg = Set(personen).subtracting(bleiben)
                if !weg.isEmpty { entfernen[zeile.klasseId, default: []].formUnion(weg) }
            }
        }
        namen = Lernendenbestand.tischnamenwechsel(vorher: vorher, nachher: nachher)
    }
}

extension Planungsspeicher {

    /// Nach dem „Übernehmen“: die Folgen an den Sitzplänen, mit Meldung. Sind die Pläne gesperrt, bleiben sie
    /// unangetastet, und die Meldung sagt es.
    func sitzplanfolgenAnwenden(_ folgen: Sitzplanfolgen) {
        guard !folgen.istLeer else { return }
        guard sitzplaene.schreibbar else {
            melden(Self.sitzplanfolgenGesperrt, .warnung)
            return
        }
        let f = sitzplaene.verwaltungFolgen(entfernen: folgen.entfernen, namen: folgen.namen)
        // Das Entfernen lässt sich nicht widerrufen — eine Warnung (E494); das Nachführen ein Hinweis.
        if let text = Self.sitzplanfolgenEntfernt(f) { melden(text, .warnung) }
        if let text = Self.sitzplanfolgenNachgefuehrt(f) { melden(text) }
    }

    /// Was „Übernehmen“ an den Sitzplänen ändern würde — für die Frage beim Beenden (E495); nichts geschrieben.
    func sitzplanfolgenVorschau(_ entwurf: Lernendenbestand) -> Sitzplandienst.Folgen {
        guard let sitzung = lernende.bestand else { return Sitzplandienst.Folgen() }
        let folgen = Sitzplanfolgen(vorher: sitzung, nachher: entwurf, planung: planung?.erstellt)
        return sitzplaene.verwaltungFolgenVorschau(entfernen: folgen.entfernen, namen: folgen.namen)
    }

    // Die Wortlaute des Nutzers (11.10.2026): gezählt nach Personen und Namensänderungen, der Ort nach der Zahl
    // der betroffenen Pläne.

    static let sitzplanfolgenGesperrt = "Die Sitzpläne sind gerade nicht verfügbar — Anpassungen in der "
        + "Lernendenverwaltung konnten nicht übertragen werden."

    static func sitzplanfolgenEntfernt(_ f: Sitzplandienst.Folgen) -> String? {
        let ort = f.entferntIn.count == 1 ? "dem Sitzplan" : "den Sitzplänen"
        switch f.entfernt.count {
        case 0: return nil
        case 1: return "Eine Person wurde mit dem Verlassen ihrer Lerngruppe auch aus \(ort) entfernt."
        case let n: return "\(n) Personen wurden mit dem Verlassen ihrer Lerngruppe auch aus \(ort) entfernt."
        }
    }

    static func sitzplanfolgenNachgefuehrt(_ f: Sitzplandienst.Folgen) -> String? {
        let ort = f.nachgefuehrtIn.count == 1 ? "den Sitzplan" : "die Sitzpläne"
        switch f.nachgefuehrt.count {
        case 0: return nil
        case 1: return "Die Namensänderung wurde auch auf \(ort) übertragen."
        case let n: return "Die \(n) Namensänderungen wurden auch auf \(ort) übertragen."
        }
    }

    /// Der Absatz der Frage beim Beenden (E495) — `nil` ohne Folgen.
    static func sitzplanfolgenAbsatz(_ f: Sitzplandienst.Folgen) -> String? {
        let entfernt: String? = switch f.entfernt.count {
        case 0: nil
        case 1: "wird eine Person aus \(f.entferntIn.count == 1 ? "dem Sitzplan" : "den Sitzplänen") entfernt, "
            + "weil sie ihre Lerngruppe verlassen hat"
        case let n: "werden \(n) Personen aus \(f.entferntIn.count == 1 ? "dem Sitzplan" : "den Sitzplänen") entfernt, "
            + "weil sie ihre Lerngruppe verlassen haben"
        }
        let ort = f.nachgefuehrtIn.count == 1 ? "in einem Sitzplan" : "in den Sitzplänen"
        let (verb, was) = f.nachgefuehrt.count == 1 ? ("wird", "eine Namensänderung")
                                                    : ("werden", "\(f.nachgefuehrt.count) Namensänderungen")
        switch (entfernt, f.nachgefuehrt.isEmpty) {
        case (nil, true): return nil
        case (let e?, true): return "Beim Übernehmen \(e)."
        case (nil, false): return "Beim Übernehmen \(verb) \(ort) \(was) vorgenommen."
        case (let e?, false): return "Beim Übernehmen \(e); \(ort) \(verb) \(was) vorgenommen."
        }
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
        // Was die Fortsetzung eben las, einmal genommen — sonst liest das Setzen selbst (B94, E454).
        let gelesen = archivVorgelesen
        archivVorgelesen = nil
        guard let grund = lernende.archivSetzen(neu, stempel: Zeitrechnung.dateistempel(), gelesen: gelesen) else {
            return nil
        }
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
            self?.archivLoeschenNachDerAntwort(archiv, was: "Das Schuljahr \(jahr.schuljahr)", dann: dann) {
                $0.ohneJahr(id, jetzt: Zeitrechnung.jetztAlsZeitstempel()).bestand
            }
        }
    }

    /// Eine bestätigte Löschung im Archiv: erst, wenn das Alert fort ist — das Schreiben baut
    /// die Ansicht um, und darunter schloss SwiftUI das schließende Alert-Blatt ein zweites Mal
    /// (B88, E392). Nie verworfen: Steht inzwischen eine andere Frage, nach deren Antwort
    /// (Z-AS2a-01); beim Beenden vorher (Z-AS2a-07). Angewandt auf das Archiv, das beim Schreiben
    /// gilt — nicht auf das beim Fragen gezeigte, sonst setzte eine zweite Löschung die erste
    /// zurück (Z-AS2a-02); ist es nicht lesbar, auf das gezeigte. Nichts ändert sich im Klick (Z-AS2a-05).
    /// Vor dem Schreiben nur einmal entschlüsselt: Das Schreiben in `dann` nimmt, was hier gelesen ist; die
    /// Rückprüfung danach bleibt (B94, E454).
    /// Findet die Löschung ihr Ziel im Archiv, wie es dann liegt, nicht mehr, wird nichts geschrieben und
    /// gesagt, was fehlte (`was`, Z-AV6-02) — sonst schriebe sie still das unveränderte Archiv.
    private func archivLoeschenNachDerAntwort(_ gezeigt: Archivbestand, was: String,
                                              dann: @escaping @MainActor (Archivbestand) -> Void,
                                              anwenden: @escaping (Archivbestand) -> Archivbestand) {
        let kennung = UUID()
        ausstehendeArchivloeschungen.append((kennung, { [weak self] in
            guard let self else { return }
            let befund = lernende.archivLesen(stempel: Zeitrechnung.dateistempel())
            let jetzt: Archivbestand
            switch befund {
            case .gelesen(let gelesen, let bilanz, let kopie) where kopie != nil || !(bilanz.verlust || bilanz.festzuschreiben):
                jetzt = gelesen
            default:
                // Nicht lesbar — oder bereinigt gelesen, ohne dass das Original bewahrt ist (das Schreiben war
                // gesperrt, E472): dann auf das gezeigte; das Setzen lehnt ab, nennt den Grund und zählt ihn
                // (Z-AV10-02) — sonst ginge die Löschung eines ersetzten Eintrags still ins Leere.
                jetzt = gezeigt
            }
            let neu = anwenden(jetzt)
            guard neu != jetzt else {
                melden("\(was) ließ sich im Archiv nicht mehr finden — gelöscht wurde nichts.", .warnung)
                return
            }
            archivVorgelesen = befund
            defer { archivVorgelesen = nil }
            dann(neu)
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
            self?.archivLoeschenNachDerAntwort(archiv, was: "„\(person.anzeigename)“", dann: dann) {
                $0.ohnePerson(id, jetzt: Zeitrechnung.jetztAlsZeitstempel()).bestand
            }
        }
    }

    func archivAnliegenLoeschenFragen(_ anliegen: String, imJahr jahr: String, in archiv: Archivbestand,
                                      dann: @escaping @MainActor (Archivbestand) -> Void) {
        guard let j = archiv.jahre.first(where: { $0.id == jahr }),
              let a = j.lernende?.anliegen.first(where: { $0.id == anliegen }) else { return }
        let zahl = archiv.ohneAnliegen(anliegen, imJahr: jahr, jetzt: Zeitrechnung.jetztAlsZeitstempel()).zahl
        let (art, mit) = Self.benennung(a.art)
        // Eine Vereinbarung nennt ihre Stände wie im Blatt (Tabelle 13a, E811).
        let folge = a.art == .vereinbarung ? Self.vereinbarungStaende(a.betroffene.count)
            : "\(mit) \(zahl.rueckmeldungen == 1 ? "geht" : "gehen") "
                + "\(Self.anzahlArchiv(zahl.rueckmeldungen, "Rücklauf", "Rückläufe"))."
        let text = "\(art) „\(a.titel)“ aus dem Schuljahr \(j.schuljahr) löschen?\n\n" + folge + "\n\n" + Self.archivEndgueltig
        fragen(text, bestaetigung: "Löschen", gefahr: true, ort: .lernende) { [weak self] in
            // Im Satz der Meldung Subjekt: „Der Termin“, nicht „Den Termin“ wie in der Frage.
            self?.archivLoeschenNachDerAntwort(archiv, was: "\(a.art == .termin ? "Der Termin" : art) „\(a.titel)“",
                                               dann: dann) {
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

    /// Die Lerngruppen an einer Zeile der offenen Planung, in der Folge der Listen (E670).
    func lerngruppen(fuerZeile klasseId: String) -> [Lerngruppe] {
        guard let zeile = zeilenbindung(klasseId) else { return [] }
        return lernende.bestand?.gruppen(an: zeile) ?? []
    }

    /// Wie eine Lerngruppe aus der Zeile heißt: wie die Klasse/der Kurs — die Klassenleitung trägt ihre Klasse im Fach.
    nonisolated static func lerngruppenname(_ klasse: Klasse) -> String {
        let fach = klasse.fach.trimmingCharacters(in: .whitespaces)
        return klasse.art == .klassenleitung && !fach.isEmpty ? fach : klasse.name
    }

    private static func namensschluessel(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Die erste aktive Lerngruppe, die heißt wie die Zeile (`lerngruppenname`) — ⌘K bietet sie vor „Lerngruppe aus der
    /// Zeile anlegen“ an, damit keine zweite entsteht (E667). Hängt schon eine dieses Namens an der Zeile, keine: Eine
    /// zweite gleichnamige daneben ließe den Sitzplan leer (Z-AT9b-16, E674).
    func gleichnamigeLerngruppe(fuerZeile klasseId: String) -> Lerngruppe? {
        guard let zeile = zeilenbindung(klasseId), let klasse = planung?.klassen.first(where: { $0.id == klasseId }),
              let bestand = lernende.bestand else { return nil }
        let name = Self.namensschluessel(Self.lerngruppenname(klasse))
        guard !name.isEmpty, !bestand.gruppen(an: zeile).contains(where: { Self.namensschluessel($0.name) == name }) else {
            return nil
        }
        return bestand.lerngruppen
            .filter { $0.archiviert.isEmpty && !$0.zeilen.contains(zeile) && Self.namensschluessel($0.name) == name }
            .sorted(by: Lerngruppe.vorgehen).first
    }

    /// „Lerngruppe aus der Zeile anlegen“ steht in ⌘K, solange keine Lerngruppe dieses Namens an der Zeile hängt — sonst
    /// entstünde eine zweite gleichnamige an derselben Zeile (E667).
    func lerngruppeAusZeileAngeboten(_ klasseId: String) -> Bool {
        guard let klasse = planung?.klassen.first(where: { $0.id == klasseId }) else { return false }
        let name = Self.namensschluessel(Self.lerngruppenname(klasse))
        return !lerngruppen(fuerZeile: klasseId).contains { Self.namensschluessel($0.name) == name }
    }

    /// Was „+ Lerngruppe“ in der Kurszelle tut (E680) — dieselbe Folge wie ⌘K (E667).
    enum Lerngruppenangebot: Equatable {
        /// Mit der Zeile ist schon eine Lerngruppe ihres Namens verknüpft: Sie bleibt, die übrigen gehen („Nur „6a““).
        case behalten(Lerngruppe)
        /// Eine Lerngruppe ihres Namens gibt es, mit dieser Zeile noch nicht verknüpft: Sie kommt dazu, die übrigen gehen
        /// („+ „6a““).
        case verknuepfen(Lerngruppe)
        /// Keine gleichnamige: eine neue, benannt wie die Zeile („+ Lerngruppe“, E673).
        case anlegen
    }

    func lerngruppenangebot(fuerZeile klasseId: String) -> Lerngruppenangebot {
        guard let klasse = planung?.klassen.first(where: { $0.id == klasseId }) else { return .anlegen }
        let name = Self.namensschluessel(Self.lerngruppenname(klasse))
        if !name.isEmpty, let da = lerngruppen(fuerZeile: klasseId).first(where: { Self.namensschluessel($0.name) == name }) {
            return .behalten(da)
        }
        if let g = gleichnamigeLerngruppe(fuerZeile: klasseId) { return .verknuepfen(g) }
        return .anlegen
    }

    /// Der Hinweis nach dem Klick in der Kurszelle (E700): welche Lerngruppen die Zeile verloren haben — an ihren anderen Zeilen
    /// bleiben sie.
    nonisolated static func kurszellenhinweis(_ angebot: Lerngruppenangebot, gruppen: [Lerngruppe], zeile: String) -> String? {
        let bleibt: String? = {
            switch angebot {
            case .behalten(let g): g.id
            case .verknuepfen, .anlegen: nil
            }
        }()
        let geloest = gruppen.filter { $0.id != bleibt }
        guard !geloest.isEmpty else { return nil }
        let eine = geloest.count == 1
        return geloest.map { "„\($0.name)“" }.joined(separator: ", ") + " \(eine ? "ist" : "sind") von der Zeile „\(zeile)“ gelöst "
            + "— an ihren anderen Zeilen \(eine ? "bleibt sie" : "bleiben sie")."
    }

    /// Was die Kurszelle zeigt (E680): Knopf, Hilfe und Bedienungshilfe je Angebot — Wortlaute wie entschieden.
    nonisolated static func kurszellentext(_ angebot: Lerngruppenangebot, klasse: String,
                                           gruppen: [Lerngruppe]) -> (knopf: String, hilfe: String, bedienung: String) {
        func namen(_ g: [Lerngruppe]) -> String { g.map { "„\($0.name)“" }.joined(separator: ", ") }
        let alle = namen(gruppen)
        switch angebot {
        case .behalten(let g):
            let andere = gruppen.filter { $0.id != g.id }
            let eine = andere.count == 1
            return ("Nur „\(g.name)“",
                    "An dieser Zeile: \(alle). Nur „\(g.name)“ an dieser Zeile behalten — \(namen(andere)) \(eine ? "geht" : "gehen") "
                        + "von dieser Zeile, an ihren anderen Zeilen \(eine ? "bleibt sie" : "bleiben sie")",
                    "Nur die Lerngruppe \(g.name) an dieser Zeile behalten, statt " + andere.map(\.name).joined(separator: ", "))
        case .verknuepfen(let g):
            return ("+ „\(g.name)“",
                    "An dieser Zeile: \(alle). Die Lerngruppe „\(g.name)“ mit dieser Zeile verknüpfen — sie ersetzt \(alle) an dieser "
                        + "Zeile, an ihren anderen Zeilen \(gruppen.count == 1 ? "bleibt sie" : "bleiben sie")",
                    "Die Lerngruppe \(g.name) mit dieser Zeile verknüpfen, statt " + gruppen.map(\.name).joined(separator: ", "))
        case .anlegen:
            return ("+ Lerngruppe",
                    "An dieser Zeile: \(alle). Eine eigene Lerngruppe für „\(klasse)“ anlegen — sie ersetzt \(alle) an dieser Zeile; "
                        + "die Mitglieder im Blatt „Lernende“ eintragen",
                    "Eigene Lerngruppe für \(klasse) anlegen, statt " + gruppen.map(\.name).joined(separator: ", "))
        }
    }

    /// Der Grund, wenn die gleichnamige schon an 20 Zeilen hängt (E680).
    static func lerngruppeVoll(_ name: String) -> String {
        "„\(name)“ ist schon mit \(Lernendendatei.maxZeilenJeGruppe) Zeilen verknüpft — höchstens \(Lernendendatei.maxZeilenJeGruppe) "
            + "je Lerngruppe."
    }

    /// Trägt eine Unterrichtszeile mehrere Lerngruppen — etwa „9a“ und „9b“ an einem Kurs —, legt die Kurszelle die eine fest,
    /// die der Sitzplan braucht (E674), in der Folge von ⌘K (E680, E667): Ist eine Lerngruppe ihres Namens schon mit der Zeile
    /// verknüpft, bleibt sie, und die übrigen gehen; gibt es eine, die mit ihr noch nicht verknüpft ist, kommt sie dazu, und die
    /// übrigen gehen; sonst eine neue, benannt wie die Zeile, ohne Mitglieder (E673). An ihren anderen Zeilen bleiben die übrigen
    /// (E676). Gibt den Grund zurück, wenn es nicht ging, sonst die Kennung der einen.
    @discardableResult
    func lerngruppeFuerZeileAnlegen(_ klasseId: String) -> (grund: String?, id: String?) {
        let klasse = planung?.klassen.first { $0.id == klasseId }
        let angebot = lerngruppenangebot(fuerZeile: klasseId)
        // Eine gleichnamige an schon 20 Zeilen käme nicht dazu — dann bleibt alles, und der Grund steht da.
        if case .verknuepfen(let g) = angebot, g.zeilen.count >= Lernendendatei.maxZeilenJeGruppe {
            return (Self.lerngruppeVoll(g.name), nil)
        }
        var gewaehlt: String?
        let grund = bindungAendern(klasseId) { bestand, zeile, jetzt in
            switch angebot {
            case .behalten(let g):
                gewaehlt = g.id
                // Nur die übrigen gehen, auch archivierte wie bei „+ Lerngruppe“ (Z-AT15N-05) — die Folge der Zeilen der einen
                // bleibt (die erste gibt das Fach, E648).
                return bestand.lerngruppen.filter { $0.id != g.id && $0.zeilen.contains(zeile) }
                    .reduce(bestand) { $0.ohneBindung($1.id, an: zeile, jetzt: jetzt) }
            case .verknuepfen(let g):
                gewaehlt = g.id
                return bestand.ohneBindung(zeile, jetzt: jetzt).mitBindung(g.id, an: zeile, jetzt: jetzt)
            case .anlegen:
                guard let klasse, let ergebnis = bestand.mitNeuerGruppe(name: Self.lerngruppenname(klasse), art: .klasse,
                                                                        jetzt: jetzt) else {
                    return nil
                }
                gewaehlt = ergebnis.id
                return ergebnis.bestand.ohneBindung(zeile, jetzt: jetzt).mitBindung(ergebnis.id, an: zeile, jetzt: jetzt)
            }
        }
        return (grund, grund == nil ? gewaehlt : nil)
    }

    /// Die eine Lerngruppe an einer Zeile der offenen Planung — `nil` ohne Bindung oder bei mehreren (E674).
    func lerngruppe(fuerZeile klasseId: String) -> Lerngruppe? {
        guard let zeile = zeilenbindung(klasseId) else { return nil }
        return lernende.bestand?.gruppe(an: zeile)
    }

    /// Was die Listenphase des Sitzplans aus der Lerngruppe anbietet (E255):
    /// die Gruppe der Zeile und die Plätze ihrer aktiven Mitglieder. `nil`
    /// ohne offene Lernendenverwaltung — dann gibt es den Knopf nicht (E249);
    /// ohne gebundene Gruppe — oder bei mehreren an der Zeile (E674) — keine Gruppe und keine Plätze.
    func sitzplatzangebot(fuer klasseId: String) -> (gruppe: Lerngruppe?, plaetze: [Sitzplan.Platzvorlage])? {
        guard lernende.quelle == .behaelter else { return nil }
        guard let gruppe = lerngruppe(fuerZeile: klasseId), let verzeichnis = lernende.verzeichnis else {
            return (nil, [])
        }
        return (gruppe, verzeichnis.sitzplatzvorlage(der: gruppe.id))
    }

    /// Eine Gruppe aus der Zeile: benannt wie die Zeile (`lerngruppenname`), an die Zeile gebunden — ohne Fach (E665).
    @discardableResult
    func lerngruppeAusZeileAnlegen(_ klasseId: String) -> String? {
        let klasse = planung?.klassen.first { $0.id == klasseId }
        return bindungAendern(klasseId) { bestand, zeile, jetzt in
            guard let klasse,
                  let ergebnis = bestand.mitNeuerGruppe(name: Self.lerngruppenname(klasse), art: .klasse, jetzt: jetzt)
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

    /// Eine Lerngruppe von der Zeile lösen — die übrigen bleiben (E670).
    @discardableResult
    func lerngruppeLoesen(_ klasseId: String, gruppe: String) -> String? {
        bindungAendern(klasseId) { $0.ohneBindung(gruppe, an: $1, jetzt: $2) }
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
        fragen("Die Datei wird unverschlüsselt geschrieben — mit den Namen aller Lernenden und ihren Lerngruppen — "
               + "und liegt im Klartext, wo immer sie hinkommt.\n\nFortfahren?",
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
