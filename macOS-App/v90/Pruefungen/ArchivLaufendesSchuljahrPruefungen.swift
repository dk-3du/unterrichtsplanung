// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Das Archiv des laufenden Schuljahrs (v86, AX1: E643, E644, E760) ──────
// In der Ansicht „Archiv“ des Blatts „Lernende“ steht oben in der Wahl „Schuljahr“ ein Eintrag für das laufende Schuljahr —
// die Zahl aus der Jahresdatei der geltenden Planung, auch ohne Vorjahre. Er zeigt die archivierten Personen und Lerngruppen
// aus dem Entwurf des Blatts, nicht aus der Archivdatei; „Zurückholen“ wirkt am Entwurf, derselbe Weg wie im Blatt (E689).
// Was nur die Oberfläche zeigt, über reine Funktionen.

@Suite("Archiv des laufenden Schuljahrs: Eintrag, Inhalt aus dem Entwurf, Zurückholen, Leer-Texte")
struct ArchivLaufendesSchuljahrPruefungen {

    private static let stempel = "2026-10-23T19:00:00.000Z"
    private static let spaeter = "2026-10-23T20:00:00.000Z"

    /// „6a · Biologie“ und „7b · Chemie“ — Unterrichtszeilen, also mit Sitzplan.
    private static func planung(_ start: String = "2026-08-03") throws -> Planung {
        Planung.leer(titel: "Schuljahr", start: try #require(Tag(iso: start)), wochen: 4, basis: "",
                     klassen: Standardkurse.aufbauen([("6a", "Biologie"), ("7b", "Chemie")]), fachfarben: [:])
    }

    private static func zeile(_ p: Planung, _ stelle: Int) -> Zeilenbindung {
        Zeilenbindung(planung: p.erstellt, klasseId: p.klassen[stelle].id)
    }

    private static func person(_ id: String, _ vorname: String, _ nachname: String, archiviert: String = "") -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: "2026-09-01T07:00:00.000Z", geaendert: stempel,
                  archiviert: archiviert)
    }

    private static func gruppe(_ id: String, _ name: String, _ mitglieder: [String], zeilen: [Zeilenbindung] = [],
                               archiviert: String = "") -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: mitglieder, zeilen: zeilen, skalen: [:],
                   halbjahreswechsel: "", geaendert: stempel, archiviert: archiviert)
    }

    /// Der Entwurf des Blatts: „6a“ aktiv (Anna, Ben, Emil) an „6a · Biologie“; „Bio-AG“ archiviert (Anna, Cem) an
    /// „6a · Biologie“ und „7b · Chemie“ — „6a · Biologie“ trägt inzwischen „6a“; „Chor“ archiviert, ohne Mitglieder.
    /// Archivierte Personen: Dora (in keiner Lerngruppe) und Emil (in „6a“).
    private static func entwurf(_ p: Planung) -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: stempel)
        b.lernende = [person("l-1", "Anna", "Abel"), person("l-2", "Ben", "Bauer"), person("l-3", "Cem", "Çelik"),
                      person("l-4", "Dora", "Dietz", archiviert: stempel), person("l-5", "Emil", "Ernst", archiviert: stempel)]
        b.lerngruppen = [gruppe("g-1", "6a", ["l-1", "l-2", "l-5"], zeilen: [zeile(p, 0)]),
                         gruppe("g-2", "Bio-AG", ["l-1", "l-3"], zeilen: [zeile(p, 0), zeile(p, 1)], archiviert: stempel),
                         gruppe("g-3", "Chor", [], archiviert: stempel)]
        return b
    }

    @Test("E760: Der Eintrag heißt „2026/27 (laufendes Schuljahr)“ — die Zahl aus der Jahresdatei, ohne sie aus dem Beginn der Planung")
    func beschriftung() throws {
        #expect(LaufendesSchuljahr.titel("2026/27") == "2026/27 (laufendes Schuljahr)")
        let p = try Self.planung()
        let b = Self.entwurf(p)
        #expect(LaufendesSchuljahr.schuljahr(b, planung: p) == "2026/27")
        var ohne = b
        ohne.schuljahr = ""
        #expect(LaufendesSchuljahr.schuljahr(ohne, planung: try Self.planung("2027-08-02")) == "2027/28",
                "ohne Schuljahr in der Jahresdatei aus dem Beginn der Planung — wie beim Archivieren")
        var anders = b
        anders.schuljahr = "2025/26"
        #expect(LaufendesSchuljahr.schuljahr(anders, planung: p) == "2025/26", "die Jahresdatei gilt vor dem Beginn")
    }

    @Test("E760: Die Wahl — oben das laufende Schuljahr, darunter die Vorjahre, das jüngste zuerst; auch ohne Vorjahre und ehe das Archiv gelesen ist")
    func wahl() throws {
        let archiv = Archivbestand.leer.mitJahr(planung: try Self.planung("2024-08-05"), lernende: nil, jetzt: Self.stempel)
            .mitJahr(planung: try Self.planung("2025-08-04"), lernende: nil, jetzt: Self.stempel)
        let eintraege = Archivwahl.eintraege(laufend: "2026/27 (laufendes Schuljahr)", archiv: archiv)
        #expect(eintraege.map(\.titel) == ["2026/27 (laufendes Schuljahr)", "2025/26", "2024/25"])
        #expect(eintraege.map(\.wahl) == [.laufend, .vorjahr(archiv.jahre[1].id), .vorjahr(archiv.jahre[0].id)])
        #expect(Archivwahl.eintraege(laufend: "2026/27 (laufendes Schuljahr)", archiv: .leer).map(\.wahl) == [.laufend],
                "auch ohne Vorjahre")
        #expect(Archivwahl.eintraege(laufend: "2026/27 (laufendes Schuljahr)", archiv: nil).map(\.wahl) == [.laufend],
                "ehe das Archiv gelesen ist — oder wenn es sich nicht lesen lässt")
        #expect(Archivwahl.vorwahl == .laufend, "beim Öffnen gewählt: der oberste Eintrag")
    }

    @Test("Nach dem Lesen und nach einer Löschung: Die Wahl bleibt; ein gelöschtes Vorjahr weicht dem jüngsten übrigen, ohne Vorjahr dem laufenden")
    func nachLesen() throws {
        let archiv = Archivbestand.leer.mitJahr(planung: try Self.planung("2024-08-05"), lernende: nil, jetzt: Self.stempel)
            .mitJahr(planung: try Self.planung("2025-08-04"), lernende: nil, jetzt: Self.stempel)
        let alt = archiv.jahre[0].id, neu = archiv.jahre[1].id
        #expect(Archivwahl.nachLesen(.laufend, archiv: archiv) == .laufend)
        #expect(Archivwahl.nachLesen(.vorjahr(alt), archiv: archiv) == .vorjahr(alt))
        #expect(Archivwahl.nachLesen(.vorjahr("j-geloescht"), archiv: archiv) == .vorjahr(neu), "wie bisher: das jüngste")
        #expect(Archivwahl.nachLesen(.vorjahr("j-geloescht"), archiv: .leer) == .laufend, "kein Vorjahr mehr")
    }

    @Test("E643, E644: Der Inhalt kommt aus dem Entwurf — archivierte Personen und Lerngruppen mit ihren Mitgliedern; kein Teil „Anliegen“")
    func inhaltAusDemEntwurf() throws {
        let v = Lernendenverzeichnis(Self.entwurf(try Self.planung()))
        let personen = LaufendesSchuljahr.personen(v)
        #expect(personen.map(\.id) == ["l-4", "l-5"], "nur die archivierten, in der Folge der Listen")
        #expect(personen.map(\.lerngruppen) == ["", "6a"], "Emil steht in „6a“, Dora in keiner")
        let gruppen = LaufendesSchuljahr.gruppen(v)
        #expect(gruppen.map(\.id) == ["g-2", "g-3"], "nur die archivierten")
        #expect(gruppen.map(\.mitglieder) == [2, 0], "mit ihren Mitgliedern")
        #expect(Archivteil.teile(.laufend) == [.personen, .lerngruppen], "kein Teil „Anliegen“")
        #expect(Archivteil.teile(.vorjahr("j-1")) == Archivteil.allCases, "ein Vorjahr wie bisher")
    }

    @Test("Z-AX1-01: Die Zahl der Mitglieder zählt wie das Blatt nur aktive — „Zurückholen“ bringt archivierte Personen nicht wieder")
    func mitgliederzahlNurAktive() throws {
        var e = Self.entwurf(try Self.planung())
        e.lerngruppen.append(Self.gruppe("g-4", "Theater-AG", ["l-1", "l-5"], archiviert: Self.stempel))
        let zeile = LaufendesSchuljahr.gruppen(Lernendenverzeichnis(e)).first { $0.id == "g-4" }
        #expect(zeile?.mitglieder == 1, "Anna aktiv, Emil archiviert — 1 wie danach im Blatt")
    }

    @Test("E689 im Archiv: Zurückholen wirkt am Entwurf — die Lerngruppe mit Mitgliedern, ohne die besetzte Zeile, mit Hinweis; eine Person; danach nicht mehr im Eintrag")
    func zurueckholen() throws {
        let p = try Self.planung()
        let b = Self.entwurf(p)
        let bio = Self.zeile(p, 0), chemie = Self.zeile(p, 1)

        let (zurueck, hinweis) = Lernendenblatt.gruppeZurueckholen("g-2", in: b, planung: p, jetzt: Self.spaeter)
        let g = try #require(zurueck.lerngruppen.first { $0.id == "g-2" })
        #expect(g.archiviert.isEmpty && g.mitglieder == ["l-1", "l-3"], "wieder in den Listen, mit ihren Mitgliedern")
        #expect(g.zeilen == [chemie], "„6a · Biologie“ trägt inzwischen „6a“ — dort nicht wieder (E689)")
        #expect(hinweis == "„Bio-AG“ ist zurückgeholt, ohne die Zeile „6a · Biologie“ — dort ist „6a“ verknüpft.")
        #expect(zurueck.lernende == b.lernende, "die Personen bleiben, wie sie sind")
        #expect(LaufendesSchuljahr.gruppen(Lernendenverzeichnis(zurueck)).map(\.id) == ["g-3"], "nicht mehr im Eintrag")

        let (chor, ohneHinweis) = Lernendenblatt.gruppeZurueckholen("g-3", in: b, planung: p, jetzt: Self.spaeter)
        #expect(chor.lerngruppen.first { $0.id == "g-3" }?.archiviert.isEmpty == true && ohneHinweis == nil,
                "ohne besetzte Zeile kein Hinweis")
        let (ohnePlanung, keiner) = Lernendenblatt.gruppeZurueckholen("g-2", in: b, planung: nil, jetzt: Self.spaeter)
        let g2 = ohnePlanung.lerngruppen.first { $0.id == "g-2" }
        #expect(g2?.archiviert.isEmpty == true && g2?.zeilen == [bio, chemie] && keiner == nil,
                "ohne Planung keine Zeile mit Sitzplan — alle Zeilen bleiben")
        let (aktiv, nichts) = Lernendenblatt.gruppeZurueckholen("g-1", in: b, planung: p, jetzt: Self.spaeter)
        #expect(aktiv == b && nichts == nil, "eine aktive Lerngruppe bleibt, wie sie ist — auch an einer geteilten Zeile")

        let person = b.mitZurueckgeholterPerson("l-5", jetzt: Self.spaeter)
        #expect(LaufendesSchuljahr.personen(Lernendenverzeichnis(person)).map(\.id) == ["l-4"],
                "„Zurückholen“ an einer Person — danach nicht mehr im Eintrag")
    }

    @Test("E799: Die archivierten Lerngruppen tragen den Tag ihrer Archivierung — die Spalte „Archiviert“, geordnet wie „Angelegt“")
    func spalteArchiviert() throws {
        var e = Self.entwurf(try Self.planung())
        let frueher = "2026-09-15T10:00:00.000Z"
        if let stelle = e.lerngruppen.firstIndex(where: { $0.id == "g-3" }) { e.lerngruppen[stelle].archiviert = frueher }
        let gruppen = LaufendesSchuljahr.gruppen(Lernendenverzeichnis(e))
        let archiviert = gruppen.map(\.archiviert)
        #expect(archiviert == [Self.stempel, frueher], "„Bio-AG“ und „Chor“ mit ihrem Zeitstempel")
        #expect(ArchivAnsicht.tag(Self.stempel) == "23.10.2026" && ArchivAnsicht.tag("") == "—", "gezeigt als Tag")
        let geordnet = Tabellenordnung.geordnet(gruppen, nach: [ArchivAnsicht.archiviertOrdnung]).map(\.id)
        #expect(geordnet == ["g-3", "g-2"], "der Zeitstempel ordnet zugleich nach dem Tag")
    }

    @Test("Z-R2A2-04: Die Lerngruppen des laufenden Schuljahrs ordnen für sich — ein Klick auf „Archiviert“ wirkt nicht in der Tabelle eines Vorjahrs, und umgekehrt")
    func eigeneOrdnungLaufend() {
        var ordnung = Archivordnung()
        ordnung.gruppenordnungSetzen([ArchivAnsicht.archiviertOrdnung], fuer: .laufend)
        let vorjahr = ordnung.gruppenordnung(.vorjahr("j-1")).count
        let laufend = ordnung.gruppenordnung(.laufend).count
        #expect(vorjahr == 0 && laufend == 1)
        ordnung.gruppenordnungSetzen([KeyPathComparator(\Archivgruppenzeile.name, comparator: .localizedStandard)],
                                     fuer: .vorjahr("j-1"))
        let beide = [ordnung.gruppenordnung(.laufend).count, ordnung.gruppenordnung(.vorjahr("j-2")).count]
        #expect(beide == [1, 1], "die Vorjahre teilen eine Ordnung wie bisher; das laufende behält seine")
    }

    @Test("Z-R2A2-05: Die Spalte „Tag“ im Archiv wird nur in einem Jahr mit Vereinbarung breiter — sonst bleibt sie bei 90")
    func tagspalte() throws {
        var b = Self.entwurf(try Self.planung())
        #expect(!ArchivAnsicht.tagspalteBreit(b), "ohne Anliegen")
        b.anliegen = [Anliegen(id: "m-1", art: .massnahme, titel: "Heft", lerngruppe: "g-1", betroffene: ["l-1"],
                               datum: "2026-10-01", frist: "2026-10-16", notiz: "", angelegt: Self.stempel, geaendert: Self.stempel)]
        #expect(!ArchivAnsicht.tagspalteBreit(b), "eine Maßnahme zeigt nur den Tag")
        b.anliegen.append(Anliegen(id: "v-1", art: .vereinbarung, titel: "Handyregel", lerngruppe: "g-1", betroffene: ["l-1"],
                                   datum: "2026-10-01", frist: "2026-10-31", notiz: "", angelegt: Self.stempel,
                                   geaendert: Self.stempel))
        #expect(ArchivAnsicht.tagspalteBreit(b), "mit einer Vereinbarung „gültig bis einschließlich …“")
    }

    @Test("E798: Die Größenwarnung auch unter dem Eintrag des laufenden Schuljahrs — „… unter ihrem Eintrag löschen.“; unter einem Vorjahr wie bisher „… hier löschen.“")
    func groessenwarnung() {
        let mb = 1024 * 1024
        #expect(ArchivAnsicht.groessenwarnung(70 * mb, laufend: true) == "Das Archiv ist 70 MB groß; ab 128 MB nimmt es kein "
                + "weiteres Schuljahr auf — ältere Schuljahre lassen sich unter ihrem Eintrag löschen.")
        #expect(ArchivAnsicht.groessenwarnung(70 * mb, laufend: false) == "Das Archiv ist 70 MB groß; ab 128 MB nimmt es kein "
                + "weiteres Schuljahr auf — ältere Schuljahre lassen sich hier löschen.")
        #expect(ArchivAnsicht.groessenwarnung(Archivdatei.hinweisgroesse - 1, laufend: true) == nil, "unter 64 MB keine")
        #expect(ArchivAnsicht.groessenwarnung(Archivdatei.hinweisgroesse, laufend: true) != nil, "ab 64 MB")
        #expect(ArchivAnsicht.groessenwarnung(nil, laufend: true) == nil, "ohne Datei keine")
    }

    @Test("E760: Wortlaute und Leer-Texte — „nichts archiviert“, dazu „Das Archiv ist leer …“ nur ohne Vorjahr")
    func leerUndWortlaute() {
        #expect(LaufendesSchuljahr.hinweis == "Archivierte Lerngruppen und Personen des laufenden Schuljahrs. „Zurückholen“ "
                + "nimmt sie wieder in die Listen; gesichert wird mit „Übernehmen“.")
        #expect(LaufendesSchuljahr.nichtsArchiviert == "Im laufenden Schuljahr ist nichts archiviert.")
        #expect(LaufendesSchuljahr.archivLeer == "Das Archiv ist leer. Beim Wechsel ins nächste Schuljahr („Neue Planung“) "
                + "kommt das laufende hierher — samt seiner Planung.")
        #expect(LaufendesSchuljahr.zurueckholen == "Zurückholen")
        #expect(LaufendesSchuljahr.gruppeHilfe == "Wieder in die Listen — mit ihren Mitgliedern")
        #expect(LaufendesSchuljahr.personHilfe == "Wieder in die Listen")
        let nichts = "Im laufenden Schuljahr ist nichts archiviert."
        let leer = "Das Archiv ist leer. Beim Wechsel ins nächste Schuljahr („Neue Planung“) kommt das laufende hierher — "
            + "samt seiner Planung."
        #expect(LaufendesSchuljahr.leer(personen: 0, gruppen: 0, vorjahre: 0) == [nichts, leer], "auch kein Vorjahr")
        #expect(LaufendesSchuljahr.leer(personen: 0, gruppen: 0, vorjahre: 2) == [nichts])
        #expect(LaufendesSchuljahr.leer(personen: 0, gruppen: 0, vorjahre: nil) == [nichts],
                "ehe das Archiv gelesen ist, ist die Zahl der Vorjahre unbekannt")
        #expect(LaufendesSchuljahr.leer(personen: 1, gruppen: 0, vorjahre: 0).isEmpty)
        #expect(LaufendesSchuljahr.leer(personen: 0, gruppen: 1, vorjahre: nil).isEmpty)
    }
}
