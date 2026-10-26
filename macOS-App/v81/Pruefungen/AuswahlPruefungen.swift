// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import Unterrichtsplanung

/// Auswählen, kopieren, verschieben, löschen.
private typealias Tag = Unterrichtsplanung.Tag

@Suite("Auswahl und Zwischenablage")
@MainActor
struct AuswahlPruefungen {

    private func speicherMitPlanung() throws -> Planungsspeicher {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 10,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        planung.eintraege = [
            Vorhaben(id: "e1", klasseId: planung.klassen[0].id, woche: 0,
                     titel: "Zellen", text: "Mikroskopieren", erledigt: false,
                     materialien: [Material(titel: "AB", pfad: "AB.pdf")],
                     links: [Weblink(titel: "3ducation", adresse: "https://3ducation.org/")]),
        ]
        return Planungsspeicher(vorschau: planung)
    }

    @Test("Kopieren und Einfügen legt ein zweites Vorhaben mit eigener Kennung an")
    func kopieren() throws {
        let speicher = try speicherMitPlanung()
        let ziel = try #require(speicher.planung?.klassen[2].id)

        speicher.anwaehlen(vorhaben: "e1")
        speicher.kopieren()
        speicher.anwaehlen(zelle: Zellenort(klasse: ziel, woche: 4))
        speicher.einfuegen()

        let eintraege = try #require(speicher.planung?.eintraege)
        #expect(eintraege.count == 2)
        let kopie = try #require(eintraege.first { $0.id != "e1" })
        #expect(kopie.titel == "Zellen")
        #expect(kopie.klasseId == ziel)
        #expect(kopie.woche == 4)
        #expect(kopie.materialien.count == 1)
        #expect(kopie.links.count == 1)
        let erstes = try #require(eintraege.first { $0.id == "e1" })
        #expect(erstes.woche == 0)
        #expect(speicher.auswahl == [kopie.id])
    }

    @Test("Verschieben lässt das Vorhaben stehen, bis eingefügt wird")
    func verschieben() throws {
        let speicher = try speicherMitPlanung()
        let ziel = try #require(speicher.planung?.klassen[1].id)

        speicher.anwaehlen(vorhaben: "e1")
        speicher.verschiebenVormerken()
        #expect(speicher.planung?.eintraege.count == 1)
        #expect(speicher.planung?.eintraege[0].woche == 0)

        speicher.anwaehlen(zelle: Zellenort(klasse: ziel, woche: 7))
        speicher.einfuegen()

        let eintraege = try #require(speicher.planung?.eintraege)
        #expect(eintraege.count == 1)
        #expect(eintraege[0].id == "e1")
        #expect(eintraege[0].klasseId == ziel)
        #expect(eintraege[0].woche == 7)
        #expect(!speicher.kannEinfuegen)
    }

    @Test("Kopiertes lässt sich mehrfach einfügen")
    func mehrfachEinfuegen() throws {
        let speicher = try speicherMitPlanung()
        let ziel = try #require(speicher.planung?.klassen[1].id)
        speicher.anwaehlen(vorhaben: "e1")
        speicher.kopieren()
        for woche in [2, 3, 5] {
            speicher.anwaehlen(zelle: Zellenort(klasse: ziel, woche: woche))
            speicher.einfuegen()
        }
        #expect(speicher.planung?.eintraege.count == 4)
        #expect(Set(speicher.planung?.eintraege.map(\.id) ?? []).count == 4)
    }

    @Test("Einfügen außerhalb des Zeitraums bleibt wirkungslos")
    func zielAusserhalb() throws {
        let speicher = try speicherMitPlanung()
        let ziel = try #require(speicher.planung?.klassen[0].id)
        speicher.anwaehlen(vorhaben: "e1")
        speicher.kopieren()

        speicher.anwaehlen(zelle: Zellenort(klasse: ziel, woche: 99))
        speicher.einfuegen()
        #expect(speicher.planung?.eintraege.count == 1)

        speicher.anwaehlen(zelle: Zellenort(klasse: "gibtesnicht", woche: 1))
        speicher.einfuegen()
        #expect(speicher.planung?.eintraege.count == 1)
    }

    @Test("Löschen entfernt das Angewählte und wählt die Zelle an")
    func loeschen() throws {
        let speicher = try speicherMitPlanung()
        let kurs = try #require(speicher.planung?.klassen[0].id)
        speicher.anwaehlen(vorhaben: "e1")
        speicher.auswahlLoeschen()
        let frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .hauptansicht)
        speicher.rueckfrageBeantworten(true)

        #expect(speicher.planung?.eintraege.isEmpty == true)
        #expect(speicher.auswahl.isEmpty)
        #expect(speicher.zielzelle == Zellenort(klasse: kurs, woche: 0))
    }

    @Test("Ohne Auswahl tut sich nichts")
    func ohneAuswahl() throws {
        let speicher = try speicherMitPlanung()
        speicher.auswahlAufheben()
        speicher.kopieren()
        speicher.verschiebenVormerken()
        speicher.auswahlLoeschen()
        #expect(speicher.planung?.eintraege.count == 1)
        #expect(!speicher.kannEinfuegen)
    }

    @Test("Ein angewähltes Vorhaben ist selbst ein Einfügeziel")
    func zielIstVorhaben() throws {
        let speicher = try speicherMitPlanung()
        speicher.anwaehlen(vorhaben: "e1")
        speicher.kopieren()
        speicher.einfuegen()
        let eintraege = try #require(speicher.planung?.eintraege)
        #expect(eintraege.count == 2)
        #expect(eintraege.allSatisfy { $0.woche == 0 })
    }

    // ── Mehrfachauswahl ───────────────────────────────────────────────────

    /// Drei Vorhaben in zwei Kursen — Versatz über Zeilen und Wochen.
    private func speicherMitDreien() throws -> Planungsspeicher {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 12,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let k0 = planung.klassen[0].id, k1 = planung.klassen[1].id
        planung.eintraege = [
            Vorhaben(id: "a", klasseId: k0, woche: 1, titel: "A", text: "", erledigt: false,
                     materialien: [], links: []),
            Vorhaben(id: "b", klasseId: k0, woche: 3, titel: "B", text: "", erledigt: false,
                     materialien: [], links: []),
            Vorhaben(id: "c", klasseId: k1, woche: 2, titel: "C", text: "", erledigt: false,
                     materialien: [], links: []),
        ]
        return Planungsspeicher(vorschau: planung)
    }

    @Test("⌘-Klick nimmt dazu und wieder weg")
    func erweitern() throws {
        let speicher = try speicherMitDreien()
        speicher.anwaehlen(vorhaben: "a")
        #expect(speicher.auswahl == ["a"])
        speicher.anwaehlen(vorhaben: "c", erweitern: true)
        #expect(speicher.auswahl == ["a", "c"])
        speicher.anwaehlen(vorhaben: "a", erweitern: true)
        #expect(speicher.auswahl == ["c"])
        speicher.anwaehlen(vorhaben: "b")
        #expect(speicher.auswahl == ["b"])
    }

    @Test("⇧-Klick nimmt die Spanne in Rasterreihenfolge")
    func spanne() throws {
        let speicher = try speicherMitDreien()
        // Reihenfolge im Raster: a (Zeile 0, KW 1), b (Zeile 0, KW 3), c (Zeile 1, KW 2)
        speicher.anwaehlen(vorhaben: "a")
        speicher.anwaehlenBis(vorhaben: "c")
        #expect(speicher.auswahl == ["a", "b", "c"])

        speicher.anwaehlen(vorhaben: "b")
        speicher.anwaehlenBis(vorhaben: "c")
        #expect(speicher.auswahl == ["b", "c"])
    }

    @Test("Mehrere behalten beim Einfügen ihre Anordnung zueinander")
    func versatzBleibt() throws {
        let speicher = try speicherMitDreien()
        let planung = try #require(speicher.planung)
        let k0 = planung.klassen[0].id, k1 = planung.klassen[1].id, k2 = planung.klassen[2].id

        speicher.anwaehlen(vorhaben: "a")
        speicher.anwaehlen(vorhaben: "b", erweitern: true)
        speicher.anwaehlen(vorhaben: "c", erweitern: true)
        speicher.kopieren()

        speicher.anwaehlen(zelle: Zellenort(klasse: k1, woche: 5))
        speicher.einfuegen()

        let alle = try #require(speicher.planung?.eintraege)
        #expect(alle.count == 6)
        let neue = alle.filter { !["a", "b", "c"].contains($0.id) }
        #expect(neue.count == 3)
        // a → (k1, 5); b lag zwei Wochen später, c eine Zeile tiefer und eine Woche später.
        #expect(neue.contains { $0.titel == "A" && $0.klasseId == k1 && $0.woche == 5 })
        #expect(neue.contains { $0.titel == "B" && $0.klasseId == k1 && $0.woche == 7 })
        #expect(neue.contains { $0.titel == "C" && $0.klasseId == k2 && $0.woche == 6 })
        #expect(alle.contains { $0.id == "a" && $0.klasseId == k0 && $0.woche == 1 })
    }

    @Test("Was beim Einfügen aus dem Raster fiele, bleibt liegen")
    func ausserhalbBleibtLiegen() throws {
        let speicher = try speicherMitDreien()
        let planung = try #require(speicher.planung)
        let letzterKurs = try #require(planung.klassen.last?.id)

        speicher.anwaehlen(vorhaben: "a")
        speicher.anwaehlen(vorhaben: "c", erweitern: true)
        speicher.kopieren()

        // Ziel ist die letzte Kurszeile — „c“ läge eine Zeile darunter.
        speicher.anwaehlen(zelle: Zellenort(klasse: letzterKurs, woche: 0))
        speicher.einfuegen()

        let alle = try #require(speicher.planung?.eintraege)
        #expect(alle.count == 4)
        #expect(alle.filter { $0.klasseId == letzterKurs }.count == 1)
    }

    @Test("Mehrere verschieben versetzt sie gemeinsam")
    func mehrereVerschieben() throws {
        let speicher = try speicherMitDreien()
        let planung = try #require(speicher.planung)
        let k1 = planung.klassen[1].id

        speicher.anwaehlen(vorhaben: "a")
        speicher.anwaehlen(vorhaben: "b", erweitern: true)
        speicher.verschiebenVormerken()
        #expect(speicher.planung?.eintraege.count == 3)

        speicher.anwaehlen(zelle: Zellenort(klasse: k1, woche: 6))
        speicher.einfuegen()

        let alle = try #require(speicher.planung?.eintraege)
        #expect(alle.count == 3)
        let a = try #require(alle.first { $0.id == "a" })
        let b = try #require(alle.first { $0.id == "b" })
        #expect(a.klasseId == k1 && a.woche == 6)
        #expect(b.klasseId == k1 && b.woche == 8)
        let c = try #require(alle.first { $0.id == "c" })
        // „c“ war nicht ausgewählt — Kurszeile und Woche einzeln geprüft, damit
        // ein Versatz auf nur einer der beiden Achsen nicht durchrutscht.
        #expect(c.klasseId == k1)
        #expect(c.woche == 2)
        #expect(!speicher.kannEinfuegen)
    }

    /// Angewählt ist entweder eine Zelle oder es sind Vorhaben — nie beides.
    ///
    /// Hält die Bedingung im Speicher fest; der Tastaturfokus zeichnet einen
    /// eigenen Rahmen in derselben Farbe und wird am laufenden Fenster mit
    /// `--mischtest` nachgemessen.
    @Test("Zelle und Vorhaben sind nie gleichzeitig angewählt")
    func niemalsBeides() throws {
        let speicher = try speicherMitDreien()
        let k1 = try #require(speicher.planung?.klassen[1].id)

        func nurEines(_ schritt: String) {
            #expect(speicher.auswahl.isEmpty || speicher.zielzelle == nil,
                    "nach „\(schritt)“ war beides angewählt")
        }

        speicher.anwaehlen(vorhaben: "a")
        nurEines("Vorhaben anwählen")

        speicher.anwaehlen(zelle: Zellenort(klasse: k1, woche: 3))
        #expect(speicher.auswahl.isEmpty)
        nurEines("Zelle anwählen")

        speicher.anwaehlen(vorhaben: "b", erweitern: true)
        #expect(speicher.zielzelle == nil)
        nurEines("mit ⌘ erweitern")

        speicher.anwaehlen(zelle: Zellenort(klasse: k1, woche: 5))
        speicher.anwaehlenBis(vorhaben: "c")
        nurEines("Spanne mit ⇧")

        speicher.anwaehlen(vorhaben: "a")
        speicher.kopieren()
        speicher.anwaehlen(zelle: Zellenort(klasse: k1, woche: 6))
        speicher.einfuegen()
        nurEines("einfügen")

        speicher.versetzen([try #require(speicher.planung?.eintraege[0])],
                           nach: Zellenort(klasse: k1, woche: 7), verschieben: true)
        nurEines("verschieben")

        speicher.anwaehlen(vorhaben: "b")
        speicher.vorhabenLoeschen("b", ort: .hauptansicht)
        speicher.rueckfrageBeantworten(true)
        nurEines("löschen")
        #expect(speicher.auswahl.isEmpty)

        speicher.auswahlAufheben()
        #expect(speicher.auswahl.isEmpty && speicher.zielzelle == nil)
    }

    @Test("Alles auswählen nimmt jedes Vorhaben und hebt die Zellwahl auf")
    func allesAnwaehlen() throws {
        let speicher = try speicherMitDreien()
        let k1 = try #require(speicher.planung?.klassen[1].id)
        speicher.anwaehlen(zelle: Zellenort(klasse: k1, woche: 2))

        speicher.allesAnwaehlen()

        #expect(speicher.auswahl == ["a", "b", "c"])
        #expect(speicher.zielzelle == nil, "Zelle und Vorhaben nie gleichzeitig")
        let leer = Planungsspeicher(vorschau: Planung.leer(
            titel: "leer", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
            basis: "", klassen: [], fachfarben: [:]))
        leer.allesAnwaehlen()
        #expect(leer.auswahl.isEmpty)
    }

    @Test("Mehrere löschen fragt einmal und entfernt alle")
    func mehrereLoeschen() throws {
        let speicher = try speicherMitDreien()
        speicher.anwaehlen(vorhaben: "a")
        speicher.anwaehlen(vorhaben: "c", erweitern: true)
        speicher.auswahlLoeschen()

        let frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .hauptansicht)
        speicher.rueckfrageBeantworten(true)

        let alle = try #require(speicher.planung?.eintraege)
        #expect(alle.map(\.id) == ["b"])
        #expect(speicher.auswahl.isEmpty)
    }
}
