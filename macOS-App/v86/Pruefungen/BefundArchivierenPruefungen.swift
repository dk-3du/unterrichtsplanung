// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Befund des Nutzers (14.10.2026), nachgestellt — seit v86 eine Prüfung (AX1) ──
// „Das Archivieren einer Lerngruppe … löscht die Lerngruppe. Die archivierte Lerngruppe findet sich nicht im
// Archiv.“ Der Weg wie am Blatt: Knopf „Archivieren“ (ein Handgriff am Entwurf), „Übernehmen“, die Datei frisch von
// der Platte gelesen; was die Gruppenliste und die Ansicht „Archiv“ zeigen; „Zurückholen“, „Übernehmen“.
// Aus der Befundprobe von v84, an die heutige Schnittstelle angepasst: Lerngruppen ohne Fach (E656), „Zurückholen“
// über den Weg des Blatts mit den Zeilen mit Sitzplan (E689) und der Eintrag des laufenden Schuljahrs in der Ansicht
// „Archiv“ (E643, E644, E760).

@Suite("Befund: Lerngruppe archivieren und zurückholen (nachgestellt)")
@MainActor
struct BefundArchivierenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand, "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private struct Stand {
        let s: Planungsspeicher
        let ablage: URL
        let zeile: Zeilenbindung
        let k6a: String
        let g6a: String
        let anna: String
        let ben: String
    }

    /// Eine Planung mit der Zeile „6a · Biologie“, verschlüsselt; die Gruppe „6a“ (Anna, Ben) an der Zeile, eine
    /// Mitteilung mit Annas Rücklauf, ein Sitzplan mit beiden.
    private func stand(_ name: String) async throws -> Stand {
        let wurzel = try #require(ProcessInfo.processInfo.environment["PLANUNGSORDNER"])
        let ablage = URL(filePath: wurzel).appending(component: "befund-\(name)-\(UUID().uuidString)",
                                                     directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ablage, withIntermediateDirectories: true)
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        p.farbenVervollstaendigen()
        s.planung = p
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let k6a = try #require(p.klassen.first { $0.name == "6a" }).id

        let a = try #require(s.lernendenEntwurfBeginnen())
        let t = a.erstellt
        let (b, g6a) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: t))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: g6a, jetzt: t).bestand
        let anna = try #require(c.lernende.first { $0.nachname == "Abel" }).id
        let ben = try #require(c.lernende.first { $0.nachname == "Bauer" }).id
        let (d, m) = try #require(c.mitNeuemAnliegen(.mitteilung, titel: "Elternbrief", lerngruppe: g6a,
                                                     betroffene: [anna, ben], datum: "2026-09-01", frist: "", jetzt: t))
        let e = d.mitRuecklauf(m, anna, stand: .erledigt, datum: "2026-09-02", notiz: "", jetzt: t)
        #expect(s.lernendenUebernehmen(e) == nil)
        #expect(s.lerngruppeBinden(g6a, an: k6a) == nil)
        #expect(s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: k6a, lernende: [
            .init(name: "Anna Abel", lernender: anna), .init(name: "Ben Bauer", lernender: ben)]), fuer: k6a) == nil)
        return Stand(s: s, ablage: ablage, zeile: Zeilenbindung(planung: p.erstellt, klasseId: k6a), k6a: k6a,
                     g6a: g6a, anna: anna, ben: ben)
    }

    /// So auf der Platte — ein frischer Dienst liest die Jahresdatei.
    private func aufDerPlatte(_ st: Stand) throws -> Lernendenbestand {
        let frisch = Lernendendienst(ablage: Ablage(ordner: st.ablage))
        _ = frisch.oeffnen(mit: try #require(st.s.tresor), stempel: "probe")
        return try #require(frisch.bestand, "die Jahresdatei liegt lesbar auf der Platte")
    }

    private func tische(_ st: Stand) -> [String] {
        (st.s.sitzplaene.plan(fuer: st.k6a)?.tische ?? []).map { "\($0.name)|\($0.lernender)" }
    }

    @Test("Archivieren, übernehmen, frisch lesen, Liste und Archiv, zurückholen")
    func weg() async throws {
        let st = try await stand("weg")
        let vorher = try aufDerPlatte(st)
        let gVorher = try #require(vorher.lerngruppen.first { $0.id == st.g6a })
        #expect(gVorher.mitglieder.sorted() == [st.anna, st.ben].sorted() && gVorher.zeilen == [st.zeile])
        let tischeVorher = tische(st)

        // Der Knopf „Archivieren“ — derselbe Handgriff wie am Blatt —, dann „Übernehmen“ mit dem Ausgang.
        let archiviert = vorher.mitArchivierterGruppe(st.g6a, jetzt: "2026-10-14T20:00:00.000Z")
        #expect(st.s.lernendenUebernehmen(archiviert, ausgang: vorher) == nil)
        let nach = try aufDerPlatte(st)
        let gNach = try #require(nach.lerngruppen.first { $0.id == st.g6a },
                                 "B-1: Die Gruppe steht nach dem Übernehmen noch in der Jahresdatei")
        #expect(gNach.archiviert == "2026-10-14T20:00:00.000Z", "B-2: mit dem Stempel des Archivierens")
        #expect(gNach.mitglieder == gVorher.mitglieder, "B-3: Mitglieder unverändert")
        #expect(gNach.zeilen == gVorher.zeilen, "B-4: Die Bindung an die Zeile steht weiter in der Datei")
        #expect(nach.anliegen == vorher.anliegen && nach.rueckmeldungen == vorher.rueckmeldungen,
                "B-5: Mitteilung und Rücklauf unverändert")
        #expect(nach.lernende.allSatisfy { $0.archiviert.isEmpty }, "B-6: Die Personen bleiben aktiv")
        #expect(nach.gruppe(an: st.zeile) == nil, "B-7: Die Zeile zeigt keine Gruppe (archiviert)")
        #expect(tische(st) == tischeVorher, "B-8: Der Sitzplan bleibt")

        // Was das Blatt zeigt.
        #expect(!Lernendenblatt.gruppenliste(nach, archivierte: false, suche: "").contains { $0.id == st.g6a },
                "B-9: Ohne „Archivierte zeigen“ fehlt die Gruppe in der Liste")
        #expect(Lernendenblatt.gruppenliste(nach, archivierte: true, suche: "").contains { $0.id == st.g6a },
                "B-10: Mit „Archivierte zeigen“ steht sie in der Liste")
        #expect(Lernendenverzeichnis(nach).mitglieder(st.g6a).map(\.id).sorted() == [st.anna, st.ben].sorted(),
                "B-11: … mit ihren Mitgliedern")
        // Die Archivdatei trägt nur die Vorjahre — die Gruppe steht dort nicht.
        switch st.s.lernende.archivLesen(stempel: "probe") {
        case .gelesen(let archiv, _, _):
            #expect(archiv.jahre.isEmpty, "B-12: Die Archivdatei hat kein Jahr — die Gruppe steht dort nicht")
        case .nichtLesbar(let grund):
            Issue.record("Archiv nicht lesbar: \(grund)")
        }
        // Seit v86 zeigt die Ansicht „Archiv“ oben das laufende Schuljahr — aus dem Entwurf (E643, E644, E760).
        #expect(LaufendesSchuljahr.gruppen(Lernendenverzeichnis(nach)).map { "\($0.id)/\($0.mitglieder)" } == ["\(st.g6a)/2"],
                "B-12a: Die Gruppe steht im Eintrag des laufenden Schuljahrs, mit ihren Mitgliedern")

        // „Zurückholen“ — derselbe Weg wie im Blatt und im Archiv (E689) —, „Übernehmen“.
        let (zurueck, hinweis) = Lernendenblatt.gruppeZurueckholen(st.g6a, in: nach, planung: st.s.planung,
                                                                   jetzt: "2026-10-14T21:00:00.000Z")
        #expect(hinweis == nil, "B-13a: Die Zeile ist frei — kein Hinweis")
        #expect(st.s.lernendenUebernehmen(zurueck, ausgang: nach) == nil)
        let wieder = try aufDerPlatte(st)
        let gWieder = try #require(wieder.lerngruppen.first { $0.id == st.g6a })
        #expect(gWieder.archiviert.isEmpty, "B-13: wieder aktiv")
        #expect(gWieder.mitglieder == gVorher.mitglieder, "B-14: mit denselben Mitgliedern")
        #expect(gWieder.zeilen == gVorher.zeilen && wieder.gruppe(an: st.zeile)?.id == st.g6a,
                "B-15: wieder an ihrer Zeile")
        #expect(wieder.anliegen == vorher.anliegen && wieder.rueckmeldungen == vorher.rueckmeldungen,
                "B-16: Mitteilung und Rücklauf wie vorher")
        #expect(tische(st) == tischeVorher, "B-17: Der Sitzplan wie vorher")
    }

    @Test("Während die Gruppe archiviert ist, bekommt ihre Zeile eine andere: Zurückgeholt kommt sie ohne diese Zeile (E689)")
    func zeileVergeben() async throws {
        let st = try await stand("zeile")
        let vorher = try aufDerPlatte(st)
        #expect(st.s.lernendenUebernehmen(vorher.mitArchivierterGruppe(st.g6a, jetzt: "2026-10-14T20:00:00.000Z"),
                                          ausgang: vorher) == nil)
        // Eine neue Gruppe an dieselbe Zeile — in ⌘K gilt die Zeile einer archivierten Gruppe als frei (E527).
        let a = try aufDerPlatte(st)
        let (b, neu) = try #require(a.mitNeuerGruppe(name: "6a neu", art: .klasse, jetzt: a.geaendert))
        #expect(st.s.lernendenUebernehmen(b, ausgang: a) == nil)
        #expect(st.s.lerngruppeBinden(neu, an: st.k6a) == nil)
        let c = try aufDerPlatte(st)
        // Angepasst (v84: „Die archivierte Gruppe verliert die Zeile“): Eine Zeile trägt mehrere (E670), die Bindung der
        // archivierten bleibt in der Datei (E683); die Zeile zeigt die neue.
        #expect(c.lerngruppen.first { $0.id == st.g6a }?.zeilen == [st.zeile] && c.gruppe(an: st.zeile)?.id == neu,
                "Z-1: Die archivierte behält die Bindung in der Datei, die Zeile zeigt die neue")
        // Zurückholen wie im Blatt und im Archiv.
        let (zurueck, hinweis) = Lernendenblatt.gruppeZurueckholen(st.g6a, in: c, planung: st.s.planung,
                                                                   jetzt: "2026-10-14T21:00:00.000Z")
        #expect(hinweis == "„6a“ ist zurückgeholt, ohne die Zeile „6a · Biologie“ — dort ist „6a neu“ verknüpft.",
                "Z-4: Der Hinweis nennt Zeile und Lerngruppe (E645, E689)")
        #expect(st.s.lernendenUebernehmen(zurueck, ausgang: c) == nil)
        let d = try aufDerPlatte(st)
        let g = try #require(d.lerngruppen.first { $0.id == st.g6a })
        #expect(g.archiviert.isEmpty && g.mitglieder.sorted() == [st.anna, st.ben].sorted(),
                "Z-2: zurück mit ihren Mitgliedern")
        #expect(g.zeilen.isEmpty && d.gruppe(an: st.zeile)?.id == neu, "Z-3: aber ohne Zeile — die trägt die neue")
    }
}
