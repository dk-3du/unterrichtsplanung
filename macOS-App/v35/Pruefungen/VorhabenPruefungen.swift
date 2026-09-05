// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Reihenfolge in der Zelle ──────────────────────────────────────────────

@Suite("Reihenfolge der Vorhaben in einer Zelle")
@MainActor
struct ReihenfolgePruefungen {

    /// Zwei Zellen mit je drei Vorhaben, in der Eintragsliste verschränkt
    /// abgelegt — nur so zeigt sich, ob mit dem Nachbarn **derselben Zelle**
    /// getauscht wird.
    private func speicherMitZelle() throws -> Planungsspeicher {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 10,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let a = planung.klassen[0].id
        let b = planung.klassen[1].id
        planung.eintraege = [
            vorhaben("a1", a, 0), vorhaben("b1", b, 0),
            vorhaben("a2", a, 0), vorhaben("b2", b, 0),
            vorhaben("a3", a, 0),
        ]
        return Planungsspeicher(vorschau: planung)
    }

    private func vorhaben(_ id: String, _ kurs: String, _ woche: Int) -> Vorhaben {
        Vorhaben(id: id, klasseId: kurs, woche: woche, titel: id, text: "",
                 erledigt: false, materialien: [], links: [])
    }

    /// Die Reihenfolge, in der die Zelle ihre Kacheln zeigt.
    private func inZelle(_ speicher: Planungsspeicher, kurs: Int) throws -> [String] {
        let planung = try #require(speicher.planung)
        let id = planung.klassen[kurs].id
        return Zellenverzeichnis(planung)[id, 0].map(\.id)
    }

    @Test("Die Zelle zeigt die Vorhaben in der Reihenfolge der Datei, nicht sortiert")
    func ausgangsreihenfolge() throws {
        let speicher = try speicherMitZelle()
        #expect(try inZelle(speicher, kurs: 0) == ["a1", "a2", "a3"])
        #expect(try inZelle(speicher, kurs: 1) == ["b1", "b2"])
    }

    @Test("Nach oben tauscht mit dem Nachbarn DERSELBEN Zelle")
    func nachOben() throws {
        let speicher = try speicherMitZelle()
        speicher.reihen("a3", nachOben: true)
        #expect(try inZelle(speicher, kurs: 0) == ["a1", "a3", "a2"])
        #expect(try inZelle(speicher, kurs: 1) == ["b1", "b2"])
    }

    @Test("Nach unten ebenso")
    func nachUnten() throws {
        let speicher = try speicherMitZelle()
        speicher.reihen("a1", nachOben: false)
        #expect(try inZelle(speicher, kurs: 0) == ["a2", "a1", "a3"])
        #expect(try inZelle(speicher, kurs: 1) == ["b1", "b2"])
    }

    @Test("Am Rand der Zelle geht nichts mehr")
    func amRand() throws {
        let speicher = try speicherMitZelle()
        #expect(speicher.kannReihen("a1", nachOben: true) == false)
        #expect(speicher.kannReihen("a3", nachOben: false) == false)
        #expect(speicher.kannReihen("a1", nachOben: false))
        #expect(speicher.kannReihen("a3", nachOben: true))

        speicher.reihen("a1", nachOben: true)
        #expect(try inZelle(speicher, kurs: 0) == ["a1", "a2", "a3"])
    }

    @Test("Ein einzelnes Vorhaben in seiner Zelle lässt sich nicht rücken")
    func alleine() throws {
        let speicher = try speicherMitZelle()
        speicher.versetzen([try #require(speicher.planung?.eintraege.first { $0.id == "a2" })],
                           nach: Zellenort(klasse: try #require(speicher.planung?.klassen[3].id),
                                           woche: 5),
                           verschieben: true)
        #expect(speicher.kannReihen("a2", nachOben: true) == false)
        #expect(speicher.kannReihen("a2", nachOben: false) == false)
    }

    @Test("Über die Menüleiste nur bei genau einem angewählten Vorhaben")
    func ueberDieAuswahl() throws {
        let speicher = try speicherMitZelle()
        speicher.anwaehlen(vorhaben: "a3")
        #expect(speicher.kannAuswahlReihen.hoch)
        speicher.auswahlReihen(nachOben: true)
        #expect(try inZelle(speicher, kurs: 0) == ["a1", "a3", "a2"])

        speicher.anwaehlen(vorhaben: "a1", erweitern: true)
        #expect(speicher.kannAuswahlReihen.hoch == false)
        #expect(speicher.kannAuswahlReihen.runter == false)
        speicher.auswahlReihen(nachOben: true)
        #expect(try inZelle(speicher, kurs: 0) == ["a1", "a3", "a2"])
    }

    // ── Umordnen per Ziehen ───────────────────────────────────────────────

    private func gezogen(_ speicher: Planungsspeicher, _ ids: [String]) throws -> [Vorhaben] {
        let planung = try #require(speicher.planung)
        return ids.compactMap { kennung in planung.eintraege.first { $0.id == kennung } }
    }

    private func zelle(_ speicher: Planungsspeicher, kurs: Int) throws -> Zellenort {
        Zellenort(klasse: try #require(speicher.planung?.klassen[kurs].id), woche: 0)
    }

    @Test("Vor eine Kachel derselben Zelle gezogen, steht es davor")
    func vorEineKachel() throws {
        let speicher = try speicherMitZelle()
        speicher.versetzen(try gezogen(speicher, ["a3"]), nach: try zelle(speicher, kurs: 0),
                           verschieben: true, vor: "a1")
        #expect(try inZelle(speicher, kurs: 0) == ["a3", "a1", "a2"])
        #expect(try inZelle(speicher, kurs: 1) == ["b1", "b2"])
    }

    @Test("Ohne Vorgänger landet es am Ende der Zelle, nicht am Ende der Datei")
    func ansZellenende() throws {
        let speicher = try speicherMitZelle()
        speicher.versetzen(try gezogen(speicher, ["a1"]), nach: try zelle(speicher, kurs: 0),
                           verschieben: true, vor: nil)
        #expect(try inZelle(speicher, kurs: 0) == ["a2", "a3", "a1"])
        #expect(try inZelle(speicher, kurs: 1) == ["b1", "b2"])
    }

    /// Ein Zug, der nichts verschiebt, darf weder sichern noch melden.
    @Test("Auf die eigene Stelle gezogen ändert sich nichts")
    func aufSichSelbst() throws {
        let speicher = try speicherMitZelle()
        let vorher = try #require(speicher.planung?.eintraege)
        let meldungen = speicher.meldungen.count
        speicher.versetzen(try gezogen(speicher, ["a2"]), nach: try zelle(speicher, kurs: 0),
                           verschieben: true, vor: "a2")
        #expect(speicher.planung?.eintraege == vorher)
        #expect(speicher.meldungen.count == meldungen)
    }

    @Test("Mehrere behalten beim Umordnen ihre Reihenfolge zueinander")
    func mehrereUmordnen() throws {
        let speicher = try speicherMitZelle()
        speicher.versetzen(try gezogen(speicher, ["a3", "a1"]), nach: try zelle(speicher, kurs: 0),
                           verschieben: true, vor: "a2")
        #expect(try inZelle(speicher, kurs: 0) == ["a1", "a3", "a2"])
    }

    @Test("In eine andere Zelle gezogen landet es an der gewählten Stelle")
    func inEineAndereZelle() throws {
        let speicher = try speicherMitZelle()
        speicher.versetzen(try gezogen(speicher, ["a1"]), nach: try zelle(speicher, kurs: 1),
                           verschieben: true, vor: "b2")
        #expect(try inZelle(speicher, kurs: 0) == ["a2", "a3"])
        #expect(try inZelle(speicher, kurs: 1) == ["b1", "a1", "b2"])
    }

    /// Die Zwischenablage hält Abzüge von vorhin — ein nach dem Vormerken
    /// geänderter Titel darf durchs Einfügen nicht zurückfallen.
    @Test("Eingefügt wird der aktuelle Stand, nicht der vorgemerkte Abzug")
    func aktuellerStand() throws {
        let speicher = try speicherMitZelle()
        speicher.anwaehlen(vorhaben: "a2")
        speicher.verschiebenVormerken()
        speicher.titelSetzen(vorhaben: "a2", titel: "später geändert")
        speicher.anwaehlen(zelle: try zelle(speicher, kurs: 1))
        speicher.einfuegen()

        let versetzt = try #require(speicher.planung?.eintraege.first { $0.id == "a2" })
        #expect(versetzt.titel == "später geändert")
        #expect(versetzt.klasseId == speicher.planung?.klassen[1].id)
    }

    /// Aus mehreren Zellen gezogen zählt die Anordnung zueinander — sonst fiele
    /// eine Mehrfachauswahl in eine einzige Zelle.
    @Test("Der Einfügepunkt zählt nur, wenn alles aus einer Zelle stammt")
    func nurAusEinerZelle() throws {
        let speicher = try speicherMitZelle()
        speicher.versetzen(try gezogen(speicher, ["a1", "b1"]), nach: try zelle(speicher, kurs: 1),
                           verschieben: true, vor: "b2")
        let planung = try #require(speicher.planung)
        #expect(planung.eintraege.first { $0.id == "a1" }?.klasseId == planung.klassen[1].id)
        #expect(planung.eintraege.first { $0.id == "b1" }?.klasseId == planung.klassen[2].id)
    }
}

// ── Titel an der Kachel ───────────────────────────────────────────────────

@Suite("Titel eines Vorhabens ändern")
@MainActor
struct TitelPruefungen {

    private func speicherMitVorhaben() throws -> Planungsspeicher {
        var planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 10,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        planung.eintraege = [
            Vorhaben(id: "e1", klasseId: planung.klassen[0].id, woche: 0,
                     titel: "Zellen", text: "Mikroskopieren", erledigt: false,
                     materialien: [], links: []),
        ]
        return Planungsspeicher(vorschau: planung)
    }

    @Test("Der neue Titel steht in der Planung, alles andere bleibt")
    func setzen() throws {
        let speicher = try speicherMitVorhaben()
        speicher.titelSetzen(vorhaben: "e1", titel: "Zellen und Gewebe")
        let eintrag = try #require(speicher.planung?.eintraege.first)
        #expect(eintrag.titel == "Zellen und Gewebe")
        #expect(eintrag.text == "Mikroskopieren")
    }

    @Test("Leerraum am Rand fällt weg")
    func beschnitten() throws {
        let speicher = try speicherMitVorhaben()
        speicher.titelSetzen(vorhaben: "e1", titel: "  Vom Bau der Zelle \n")
        #expect(speicher.planung?.eintraege.first?.titel == "Vom Bau der Zelle")
    }

    @Test("Ein leerer Titel ist erlaubt und zeigt sich als „Ohne Titel“")
    func leer() throws {
        let speicher = try speicherMitVorhaben()
        speicher.titelSetzen(vorhaben: "e1", titel: "   ")
        let eintrag = try #require(speicher.planung?.eintraege.first)
        #expect(eintrag.titel.isEmpty)
        #expect(eintrag.anzeigeTitel == "Ohne Titel")
    }

    @Test("Eine unbekannte Kennung ändert nichts")
    func unbekannt() throws {
        let speicher = try speicherMitVorhaben()
        speicher.titelSetzen(vorhaben: "gibtsnicht", titel: "Etwas")
        #expect(speicher.planung?.eintraege.first?.titel == "Zellen")
    }
}

// ── Curriculum am Kurs ────────────────────────────────────────────────────

@Suite("Kursverwaltung und Curriculum")
@MainActor
struct KursdateiPruefungen {

    private func speicherMitKursen() throws -> Planungsspeicher {
        let planung = Planung.leer(
            titel: "Prüfung", start: try #require(Tag(iso: "2026-08-10")), wochen: 10,
            basis: "/Users/lehrkraft/Unterricht",
            klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        return Planungsspeicher(vorschau: planung)
    }

    @Test("Beide Dateien hängen unabhängig voneinander am Kurs")
    func unabhaengig() throws {
        let speicher = try speicherMitKursen()
        let id = try #require(speicher.planung?.klassen[0].id)

        speicher.kursdateiSetzen(klasse: id, art: .verwaltung, pfad: "Kurse/Noten.numbers")
        speicher.kursdateiSetzen(klasse: id, art: .curriculum, pfad: "Kurse/Lehrplan.pdf")
        var klasse = try #require(speicher.planung?.klassen.first { $0.id == id })
        #expect(klasse.hatVerwaltung)
        #expect(klasse.hatCurriculum)
        #expect(klasse.pfad(.curriculum).hasSuffix("Lehrplan.pdf"))

        speicher.kursdateiSetzen(klasse: id, art: .verwaltung, pfad: nil)
        klasse = try #require(speicher.planung?.klassen.first { $0.id == id })
        #expect(klasse.hatVerwaltung == false)
        #expect(klasse.hatCurriculum)
    }

    @Test("Beide überstehen Schreiben und Lesen der Planungsdatei")
    func durchDieDatei() throws {
        let speicher = try speicherMitKursen()
        let id = try #require(speicher.planung?.klassen[0].id)
        speicher.kursdateiSetzen(klasse: id, art: .verwaltung, pfad: "Kurse/Noten.numbers")
        speicher.kursdateiSetzen(klasse: id, art: .curriculum, pfad: "Kurse/Lehrplan.pdf")

        let daten = try Planungsdatei.schreiben(try #require(speicher.planung))
        let gelesen = try Planungsdatei.lesen(daten)
        let klasse = try #require(gelesen.klassen.first { $0.id == id })
        #expect(klasse.verwaltung.hasSuffix("Noten.numbers"))
        #expect(klasse.curriculum.hasSuffix("Lehrplan.pdf"))
    }

    @Test("Eine Datei ohne Curriculum-Feld liest sich weiterhin")
    func alteDatei() throws {
        let roh = """
        {"typ":"unterrichtsplanung","wochen":10,"start":"2026-08-10",
         "klassen":[{"id":"k1","name":"5a","fach":"Biologie","verwaltung":"Noten.numbers"}],
         "eintraege":[]}
        """
        let gelesen = try Planungsdatei.lesen(try #require(roh.data(using: .utf8)))
        let klasse = try #require(gelesen.klassen.first)
        #expect(klasse.verwaltung == "Noten.numbers")
        #expect(klasse.curriculum.isEmpty)
        #expect(klasse.hatCurriculum == false)
    }

    @Test("Jede gesetzte Datei bekommt in der Kursspalte eine eigene Zeile")
    func kopfhoehe() throws {
        var ohne = Klasse(id: "k1", name: "5a", fach: "Biologie", notiz: "",
                          farbe: 0, farbeManuell: false)
        let leer = Zellenmass.kopfhoehe(ohne)

        ohne.verwaltung = "Noten.numbers"
        let mitEiner = Zellenmass.kopfhoehe(ohne)
        #expect(mitEiner > leer)

        ohne.curriculum = "Lehrplan.pdf"
        let mitBeiden = Zellenmass.kopfhoehe(ohne)
        // Gleiches Maß je Zeile — sonst schnitte die Kursspalte das Curriculum ab.
        #expect(mitBeiden - mitEiner == mitEiner - leer)
    }
}
