// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Das Archiv der Vorjahre und der Schuljahreswechsel (v80, E246) ────────
//
// Ein Behälter `archiv.json` für alle Vorjahre: je Jahr die Planung, wie sie
// war, und ihre Jahresdatei. Schreibgeschützt bis auf drei Löschungen (E276):
// ein ganzes Jahr, eine Person in allen Jahren, ein einzelnes Anliegen oder
// ein einzelner Eintrag. Der Wechsel selbst ist hier eine reine Funktion —
// archivieren und die neue Jahresdatei bilden (E271); dass Planung,
// Jahresdatei und Archiv gemeinsam oder gar nicht wechseln, sichert der
// Übergang (AP5). Reines Modell ohne AppKit.

/// Ein archiviertes Schuljahr. `lernende` fehlt, wenn es in jenem Jahr keine
/// Jahresdatei gab — archiviert wird die Planung trotzdem (E246, E275).
struct Archivjahr: Identifiable, Hashable, Sendable {
    var id: String
    var schuljahr: String
    var archiviert: String
    var planung: Planung
    var lernende: Lernendenbestand?
}

struct Archivbestand: Hashable, Sendable {
    var geaendert: String
    var jahre: [Archivjahr]

    static let leer = Archivbestand(geaendert: "", jahre: [])

    /// Das laufende Jahr ins Archiv. Das Schuljahr nennt die Jahresdatei;
    /// ohne sie folgt es aus dem Beginn der Planung.
    func mitJahr(planung: Planung, lernende: Lernendenbestand?, jetzt: String) -> Archivbestand {
        var neu = self
        let belegt = Set(jahre.map(\.id))
        var id = Kennung.neu("j")
        while belegt.contains(id) { id = Kennung.neu("j") }
        let schuljahr = lernende.map(\.schuljahr).flatMap { $0.isEmpty ? nil : $0 }
            ?? Lernendenbestand.schuljahr(fuer: planung.start)
        neu.jahre.append(Archivjahr(id: id, schuljahr: schuljahr, archiviert: jetzt,
                                    planung: planung, lernende: lernende))
        neu.geaendert = jetzt
        return neu
    }

    /// Ein ganzes Jahr samt Planung und Lernendendaten. Die Zahl nennt, was
    /// darin war — für die Rückfrage.
    func ohneJahr(_ id: String, jetzt: String) -> (bestand: Archivbestand, zahl: Lernendenbestand.Loeschzahl) {
        guard let jahr = jahre.first(where: { $0.id == id }) else { return (self, .init()) }
        var neu = self
        neu.jahre.removeAll { $0.id == id }
        neu.geaendert = jetzt
        var zahl = Lernendenbestand.Loeschzahl(jahre: 1)
        if let l = jahr.lernende {
            zahl.personen = l.lernende.count
            zahl.gruppen = l.lerngruppen.count
            zahl.anliegen = l.anliegen.count
            zahl.termine = l.anliegen.filter { $0.art == .termin }.count
            zahl.rueckmeldungen = l.rueckmeldungen.count
            zahl.eintraege = l.eintragszahl
        }
        return (neu, zahl)
    }

    /// Eine Person in allen Jahren — die Kennung bleibt über die Jahre gleich
    /// (E271), darum findet sie sich. Die Zahlen sind über alle Jahre summiert.
    func ohnePerson(_ id: String, jetzt: String) -> (bestand: Archivbestand, zahl: Lernendenbestand.Loeschzahl) {
        var neu = self
        var summe = Lernendenbestand.Loeschzahl()
        for stelle in neu.jahre.indices {
            guard let l = neu.jahre[stelle].lernende else { continue }
            let (ohne, zahl) = l.ohnePerson(id)
            guard zahl != .init() else { continue }
            neu.jahre[stelle].lernende = ohne
            summe = summe + zahl
        }
        if summe != .init() { neu.geaendert = jetzt }
        return (neu, summe)
    }

    /// Ein Anliegen samt Rückläufen in einem Jahr.
    func ohneAnliegen(_ anliegen: String, imJahr jahr: String,
                      jetzt: String) -> (bestand: Archivbestand, zahl: Lernendenbestand.Loeschzahl) {
        aendern(jahr, jetzt: jetzt) { $0.ohneAnliegen(anliegen) }
    }

    /// Ein Eintrag der Erfassung, Beurteilung, des Verhaltens oder der Leistungen in einem Jahr.
    func ohneEintrag(_ eintrag: String, imJahr jahr: String,
                     jetzt: String) -> (bestand: Archivbestand, zahl: Lernendenbestand.Loeschzahl) {
        aendern(jahr, jetzt: jetzt) { $0.ohneEintrag(eintrag) }
    }

    private func aendern(_ jahr: String, jetzt: String,
                         _ schritt: (Lernendenbestand) -> (bestand: Lernendenbestand, zahl: Lernendenbestand.Loeschzahl))
        -> (bestand: Archivbestand, zahl: Lernendenbestand.Loeschzahl) {
        guard let stelle = jahre.firstIndex(where: { $0.id == jahr }), let l = jahre[stelle].lernende else {
            return (self, .init())
        }
        let (ohne, zahl) = schritt(l)
        guard zahl != .init() else { return (self, zahl) }
        var neu = self
        neu.jahre[stelle].lernende = ohne
        neu.geaendert = jetzt
        return (neu, zahl)
    }
}

extension Lernendenbestand.Loeschzahl {
    static func + (a: Self, b: Self) -> Self {
        .init(personen: a.personen + b.personen, gruppen: a.gruppen + b.gruppen, anliegen: a.anliegen + b.anliegen,
              termine: a.termine + b.termine, vereinbarungen: a.vereinbarungen + b.vereinbarungen,
              rueckmeldungen: a.rueckmeldungen + b.rueckmeldungen,
              eintraege: a.eintraege + b.eintraege, jahre: a.jahre + b.jahre)
    }
}

// ── Der Schuljahreswechsel als Funktion (E271) ────────────────────────────

/// Welche Termine beim Wechsel mitkommen (E830): beim echten Wechsel ins nächste Schuljahr die ab dem neuen Schuljahr,
/// welchen Stand sie auch haben (E816, E826); bei „Andere Planung öffnen“ und „Früheres Schuljahr öffnen“ nur offene, wie
/// Maßnahmen; ebenso bei „Neue Planung“ mit Beginn im selben oder einem früheren Schuljahr (E832). Ohne Vorgabe in
/// `neuesJahr` — jeder Aufrufer sagt, welcher Weg es ist.
enum Terminwahl: Sendable {
    case abDemNeuenSchuljahr, nurOffene
}

extension Lernendenbestand {
    /// Die Wahl nach den Stufen zwischen bisherigem und neuem Schuljahr — wie die Blätter sie zählen (E307): mehr als 0 ist
    /// der echte Wechsel, 0 eine andere Planung desselben Schuljahrs, weniger ein früheres (E830).
    static func terminwahl(stufen: Int) -> Terminwahl {
        stufen > 0 ? .abDemNeuenSchuljahr : .nurOffene
    }

    /// Die Jahresdatei des neuen Schuljahrs aus der bisherigen: nur die
    /// gewählten Gruppen; ihre nicht archivierten Mitglieder mit **derselben
    /// Kennung** und derselben Importkennung; die Bindung an die Zeilen der
    /// neuen Planung über die Zuordnung alt→neu von „Neue Planung“; dazu die
    /// Anliegen, die für eine übernommene Person noch offen sind — nur dieser
    /// offene Teil —, die Termine nach `termine` (beim echten Wechsel ab dem
    /// neuen Schuljahr `schuljahr`, E816, E826; sonst nur offene, E830) und die
    /// geltenden Vereinbarungen; Maßnahmen, Termine und Vereinbarungen ohne ihre
    /// Gruppe, wenn sie nicht mitkommt. Nicht offene Mitteilungen und Maßnahmen,
    /// frühere oder nicht offene Termine (je nach `termine`), ungültige
    /// Vereinbarungen, die Erfassung, Leistungen, Verhalten und Beurteilung
    /// bleiben im Archiv.
    /// `ohneMitglieder`: gewählte Gruppen, die ohne Mitglieder mitkommen (E699,
    /// E708) — mit Namen, Zeilen und Skalen, die Mitgliederliste leer; ihre
    /// Mitglieder bleiben in der Vorjahresplanung im Archiv. Personen kommen nur
    /// über Gruppen mit Mitgliedern mit. Für Anliegen zählen sie wie Gruppen,
    /// die nicht mitkommen (E763, E764). Leer (Vorgabe): alle mit Mitgliedern.
    func neuesJahr(gruppen gewaehlt: Set<String>, zuordnung: [String: String], planung herkunft: String,
                   schuljahr: String, termine: Terminwahl, jetzt: String,
                   ziele: [String: Gruppenziel] = [:], zeilen: [Klasse] = [],
                   ohneMitglieder: Set<String> = []) -> Lernendenbestand {
        let verzeichnis = Lernendenverzeichnis(self)
        let archivierte = Set(lernende.filter { !$0.archiviert.isEmpty }.map(\.id))
        let gruppen = lerngruppen.filter { gewaehlt.contains($0.id) && $0.archiviert.isEmpty }
        let gruppenIds = Set(gruppen.map(\.id))
        // Personen nur über Gruppen mit Mitgliedern (E699, E708): Wer nur in einer ohne steckt, bleibt im Archiv.
        var uebernommen = Set<String>()
        for g in gruppen where !ohneMitglieder.contains(g.id) {
            uebernommen.formUnion(g.mitglieder.filter { !archivierte.contains($0) })
        }

        var neu = Lernendenbestand.leer(planung: herkunft, schuljahr: schuljahr, jetzt: jetzt)
        neu.lernende = lernende.filter { uebernommen.contains($0.id) }
        // Eine Zeile kann mehrere Lerngruppen tragen (E670): Jede Gruppe behält, was ihre Wahl nennt — ohne Ziel ihre
        // übernommenen Bindungen.
        neu.lerngruppen = gruppen.map { g in
            var z: [Zeilenbindung] = []
            for alt in g.zeilen where alt.planung == planung {
                guard let klasse = zuordnung[alt.klasseId] else { continue }
                let bindung = Zeilenbindung(planung: herkunft, klasseId: klasse)
                if !z.contains(bindung) { z.append(bindung) }
            }
            var name = g.name
            if let ziel = ziele[g.id] {
                // Die Wahl ist vollständig (E649, E650) und nennt auch die übernommenen Zeilen, die bleiben sollen —
                // was sie nicht nennt, geht.
                z = []
                for id in ziel.zeilen where zeilen.contains(where: { $0.id == id }) {
                    let bindung = Zeilenbindung(planung: herkunft, klasseId: id)
                    if !z.contains(bindung) { z.append(bindung) }
                }
                // Kein Fach von selbst: Das Fach steht an den Zeilen, nicht an der Gruppe (E656).
                // Ein leeres Feld heißt: der bisherige Name (Voreinstellung 5).
                let sauber = Lernendenbestand.zeile(ziel.name, Planungsdatei.maxNamenslaenge)
                if !sauber.isEmpty { name = sauber }
            }
            // Ohne Mitglieder: Auch wer über eine andere Gruppe mitkommt, ist hier kein Mitglied (E699).
            return Lerngruppe(id: g.id, name: name, art: g.art,
                              mitglieder: ohneMitglieder.contains(g.id) ? [] : g.mitglieder.filter { uebernommen.contains($0) },
                              zeilen: Array(z.prefix(Lernendendatei.maxZeilenJeGruppe)),
                              skalen: g.skalen, halbjahreswechsel: "", geaendert: jetzt, archiviert: "")
        }
        // Für Anliegen zählt eine Lerngruppe ohne Mitglieder wie eine, die nicht mitkommt (E763, E764): Ihre Mitteilung
        // bleibt im Archiv, Maßnahme und Termin kommen mit der Person, ohne Lerngruppe.
        let mitAnliegen = gruppenIds.subtracting(ohneMitglieder)
        // Eine Vereinbarung folgt der Person wie eine Maßnahme (E271), solange sie für sie gilt — abgeleitet am Tag des
        // Wechsels (E743), an ihrem letzten gültigen Tag noch gültig (E806); eine ungültige bleibt im Archiv.
        let tag = Zeitrechnung.zeitpunkt(aus: jetzt).map { Tag($0) } ?? .heute
        // Termine ab dem neuen Schuljahr (E826): Die Form „2027/28“ ordnet als Text wie die Jahre — nur mit einem Schuljahr
        // in dieser Form; ein leeres oder fremdes nähme sonst beliebige Termine mit (Z-R2A2-01), so bleibt jeder im Archiv.
        let schuljahrGueltig = Lernendenbestand.istSchuljahr(schuljahr)
        for a in anliegen {
            let kommen = a.betroffene.filter { p in
                guard uebernommen.contains(p) else { return false }
                switch a.art {
                case .vereinbarung: return Lernendenbestand.gueltigkeit(a, p, heute: tag) == .gueltig
                // Beim echten Wechsel entscheidet beim Termin nur sein Datum (E816, ändert E271): liegt es im neuen
                // Schuljahr oder später (E826) — nach der Regel der App, ab Juli das neue —, kommt er mit, welchen Stand er
                // auch hat; ein früherer bleibt im Archiv. Bei einer anderen oder früheren Planung nur offene (E830).
                case .termin:
                    switch termine {
                    case .nurOffene:
                        return verzeichnis.stand(a.id, p) == .offen
                    case .abDemNeuenSchuljahr:
                        guard schuljahrGueltig, let datum = Tag(iso: a.datum) else { return false }
                        return Lernendenbestand.schuljahr(fuer: datum) >= schuljahr
                    }
                case .mitteilung, .massnahme: return verzeichnis.stand(a.id, p) == .offen
                }
            }
            guard !kommen.isEmpty else { continue }
            var kopie = a
            switch a.art {
            case .mitteilung:
                guard mitAnliegen.contains(a.lerngruppe) else { continue }
            case .massnahme, .termin, .vereinbarung:
                if !mitAnliegen.contains(a.lerngruppe) { kopie.lerngruppe = "" }
            }
            // Ein Termin wandert ohne sein Vorhaben: Das bleibt in der archivierten Planung.
            kopie.planung = ""
            kopie.vorhaben = ""
            kopie.betroffene = kommen
            kopie.ungueltig = []
            neu.anliegen.append(kopie)
        }
        let paare = Set(neu.anliegen.flatMap { a in a.betroffene.map { a.id + "\u{1F}" + $0 } })
        neu.rueckmeldungen = rueckmeldungen.filter { paare.contains($0.anliegen + "\u{1F}" + $0.lernender) }
        return neu
    }

    /// Die Zeilen der Planung `herkunft` (Kennungen), an denen nur Lerngruppen ohne Mitglieder hängen — wenigstens eine
    /// (E765). Am neuen Jahr gefragt: Dort lassen alle Tische los, Namen und Tischordnung bleiben; eine Zeile mit einer
    /// Lerngruppe mit Mitgliedern bleibt, wie sie ist.
    func zeilenNurOhneMitglieder(planung herkunft: String) -> Set<String> {
        var mit = Set<String>()
        var ohne = Set<String>()
        for g in lerngruppen where g.archiviert.isEmpty {
            for zeile in g.zeilen where zeile.planung == herkunft {
                if g.mitglieder.isEmpty { ohne.insert(zeile.klasseId) } else { mit.insert(zeile.klasseId) }
            }
        }
        return ohne.subtracting(mit)
    }
}

// ── Die Datei ─────────────────────────────────────────────────────────────

/// Die Datei `archiv.json`. Gelesen nur auf Abruf; jedes Jahr mit dem Leser
/// seiner Art — die Planung wie eine Planungsdatei, die Lernenden wie eine
/// Jahresdatei. Ein Jahr, das sich nicht lesen lässt, wird übergangen und
/// gezählt: Verlust, das Original bewahrt der Dienst. Stammt ein Teil aus
/// einer neueren Fassung, wird das ganze Archiv nicht gedeutet — wer es
/// zurückschriebe, verlöre, was er nicht kennt.
enum Archivdatei {
    static let typ = "unterrichtsplanung-archiv"
    static let version = 1
    /// Grenze 128 MB, Hinweis ab 64 MB (Vertrag v80, gemessen in AP9).
    static let hoechstgroesse = 128 * 1024 * 1024
    static let hinweisgroesse = 64 * 1024 * 1024
    static let maxJahre = 100

    struct Fehler: LocalizedError, Sendable {
        enum Art: Sendable { case beschaedigt, neuereFassung }
        let art: Art
        let text: String
        var errorDescription: String? { text }
    }

    struct Bilanz: Equatable, Sendable {
        /// Ein Jahr ließ sich nicht lesen und ist übergangen.
        var verworfeneJahre = 0
        /// Ein Jahr wurde gelesen, aber bereinigt — seine Planung oder seine
        /// Jahresdatei meldete etwas.
        var bereinigteJahre = 0
        var ersetzteKennungen = 0
        var bereinigteStempel = 0

        var verlust: Bool { verworfeneJahre + bereinigteJahre > 0 }
        /// Kennungen von Schuljahren sind ersetzt, zufällig — jedes Lesen gäbe neue (B101).
        var festzuschreiben: Bool { ersetzteKennungen > 0 }
        var istLeer: Bool { !verlust && ersetzteKennungen + bereinigteStempel == 0 }

        var beschreibung: String {
            var teile: [String] = []
            func satz(_ zahl: Int, _ eins: String, _ mehr: String) {
                if zahl == 1 { teile.append("1 " + eins) } else if zahl > 1 { teile.append("\(zahl) " + mehr) }
            }
            satz(verworfeneJahre, "Schuljahr übergangen", "Schuljahre übergangen")
            satz(bereinigteJahre, "Schuljahr bereinigt", "Schuljahre bereinigt")
            satz(ersetzteKennungen, "Kennung ersetzt", "Kennungen ersetzt")
            satz(bereinigteStempel, "Zeitstempel geleert", "Zeitstempel geleert")
            return teile.joined(separator: ", ")
        }
    }

    static func lesen(_ daten: Data) throws -> Archivbestand {
        try lesenMitBilanz(daten).bestand
    }

    static func lesenMitBilanz(_ daten: Data) throws -> (bestand: Archivbestand, bilanz: Bilanz) {
        guard daten.count <= hoechstgroesse else {
            throw Fehler(art: .beschaedigt, text: "Das Archiv ist größer als 128 MB.")
        }
        guard let o = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any],
              o["typ"] as? String == typ else {
            throw Fehler(art: .beschaedigt, text: "Das Archiv ist kein lesbares JSON.")
        }
        guard let fassung = Planungsdatei.ganzzahl(o["version"]), fassung >= 1 else {
            throw Fehler(art: .beschaedigt, text: "Das Archiv trägt keine Fassungsnummer.")
        }
        guard fassung <= version else { throw neuere(fassung) }
        let roh: [Any]
        switch o["jahre"] {
        case nil: roh = []
        case let liste as [Any]: roh = liste
        default: throw Fehler(art: .beschaedigt, text: "Das Archiv ist beschädigt („jahre“).")
        }
        var bilanz = Bilanz()
        if roh.count > maxJahre { bilanz.verworfeneJahre += roh.count - maxJahre }
        var jahre: [Archivjahr] = []
        var belegt = Set<String>()
        for eintrag in roh.prefix(maxJahre) {
            guard let j = eintrag as? [String: Any], let planungRoh = j["planung"] else {
                bilanz.verworfeneJahre += 1
                continue
            }
            let planung: Planung
            var bereinigt = false
            do {
                let (p, b) = try Planungsdatei.pruefenMitBilanz(planungRoh)
                planung = p
                bereinigt = !b.istLeer
            } catch let fehler as Planungsfehler where fehler.art == .neuereFassung {
                throw neuere(nil)
            } catch {
                bilanz.verworfeneJahre += 1
                continue
            }
            var lernende: Lernendenbestand?
            switch j["lernende"] {
            case nil, is NSNull:
                break
            case let l as [String: Any]:
                do {
                    let (b, lb) = try Lernendendatei.ausObjektMitBilanz(l)
                    lernende = b
                    bereinigt = bereinigt || !lb.istLeer
                } catch let fehler as Lernendendatei.Fehler where fehler.art == .neuereFassung {
                    throw neuere(nil)
                } catch {
                    bilanz.verworfeneJahre += 1
                    continue
                }
            default:
                bilanz.verworfeneJahre += 1
                continue
            }
            var schuljahr = Planungsdatei.text(j["schuljahr"])
            if !Lernendenbestand.istSchuljahr(schuljahr) {
                schuljahr = lernende.map(\.schuljahr).flatMap { $0.isEmpty ? nil : $0 }
                    ?? Lernendenbestand.schuljahr(fuer: planung.start)
                bereinigt = true
            }
            var id = Planungsdatei.text(j["id"])
            if !Kennung.istGueltig(id) || belegt.contains(id) {
                repeat { id = Kennung.neu("j") } while belegt.contains(id)
                bilanz.ersetzteKennungen += 1
            }
            belegt.insert(id)
            var archiviert = Planungsdatei.text(j["archiviert"])
            if !archiviert.isEmpty, !Zeitrechnung.istZeitstempel(archiviert) {
                archiviert = ""
                bilanz.bereinigteStempel += 1
            }
            if bereinigt { bilanz.bereinigteJahre += 1 }
            jahre.append(Archivjahr(id: id, schuljahr: schuljahr, archiviert: archiviert,
                                    planung: planung, lernende: lernende))
        }
        var geaendert = Planungsdatei.text(o["geaendert"])
        if !geaendert.isEmpty, !Zeitrechnung.istZeitstempel(geaendert) {
            geaendert = ""
            bilanz.bereinigteStempel += 1
        }
        return (Archivbestand(geaendert: geaendert, jahre: jahre), bilanz)
    }

    private static func neuere(_ fassung: Int?) -> Fehler {
        Fehler(art: .neuereFassung,
               text: "Das Archiv stammt aus einer neueren Fassung der App"
                   + (fassung.map { " (Fassung \($0))" } ?? "") + " — bitte die App aktualisieren.")
    }

    static func schreiben(_ a: Archivbestand) throws -> Data {
        let jahre = a.jahre.map { j -> [String: Any] in
            ["id": j.id, "schuljahr": j.schuljahr, "archiviert": j.archiviert,
             "planung": Planungsdatei.alsObjekt(j.planung),
             "lernende": j.lernende.map { Lernendendatei.alsObjekt($0) as Any } ?? NSNull()]
        }
        return try JSONSerialization.data(
            withJSONObject: ["typ": typ, "version": version, "geaendert": a.geaendert, "jahre": jahre],
            options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
