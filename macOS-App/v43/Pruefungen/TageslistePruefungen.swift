// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

private typealias Tag = Unterrichtsplanung.Tag

// ── Tagesliste ────────────────────────────────────────────────────────────
//
// Gerechnet wird gegen einen festen Tag: mit `Tag.heute` hinge das Ergebnis am Wochentag.

@Suite("Heute anstehende Vorhaben")
@MainActor
struct TageslistePruefungen {

    /// Beginn 03.08.2026 (Montag), Prüftag der 12.08.2026 — ein Mittwoch in
    /// Woche 1 (10.–16.08.).
    private func planung() throws -> Planung {
        var planung = Planung.leer(
            titel: "Tagesliste", start: try #require(Tag(iso: "2026-08-03")), wochen: 12,
            basis: "", klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let a = planung.klassen[0].id
        let b = planung.klassen[1].id
        planung.eintraege = [
            vorhaben("woche-b", b, 1),
            vorhaben("woche-a", a, 1),
            vorhaben("heute", a, 1, datum: Tag(iso: "2026-08-12")),
            vorhaben("morgen", a, 1, datum: Tag(iso: "2026-08-13")),
            vorhaben("arbeit", b, 1, pruefung: true, pruefungstag: Tag(iso: "2026-08-12")),
            vorhaben("arbeit-fr", b, 1, pruefung: true, pruefungstag: Tag(iso: "2026-08-14")),
            vorhaben("andere-woche", a, 3),
        ]
        return planung
    }

    private func vorhaben(_ id: String, _ klasse: String, _ woche: Int,
                          datum: Tag? = nil, pruefung: Bool = false,
                          pruefungstag: Tag? = nil) -> Vorhaben {
        Vorhaben(id: id, klasseId: klasse, woche: woche, titel: id, text: "",
                 erledigt: false, materialien: [], links: [],
                 pruefung: pruefung, pruefungstag: pruefungstag, datum: datum)
    }

    private var pruefTag: Tag { get throws { try #require(Tag(iso: "2026-08-12")) } }

    @Test("Was für heute datiert ist und was heute geprüft wird, steht oben")
    func amTag() throws {
        let liste = try planung().tagesliste(am: try pruefTag)
        #expect(Set(liste.amTag.map(\.id)) == ["heute", "arbeit"])
        let arbeit = try #require(liste.amTag.first { $0.id == "arbeit" })
        #expect(arbeit.grund == .pruefung)
        let heute = try #require(liste.amTag.first { $0.id == "heute" })
        #expect(heute.grund == .datum)
    }

    @Test("Datiert und geprüft am selben Tag ergibt einen Posten, nicht zwei")
    func beides() throws {
        var p = try planung()
        let stelle = try #require(p.eintraege.firstIndex { $0.id == "heute" })
        p.eintraege[stelle].pruefung = true
        p.eintraege[stelle].pruefungstag = try pruefTag
        let liste = p.tagesliste(am: try pruefTag)
        #expect(liste.amTag.count(where: { $0.id == "heute" }) == 1)
        #expect(try #require(liste.amTag.first { $0.id == "heute" }).grund == .beides)
    }

    @Test("Ohne Tag zählt die Woche — ein bekannter anderer Tag schließt aus")
    func inDerWoche() throws {
        let liste = try planung().tagesliste(am: try pruefTag)
        #expect(Set(liste.inDerWoche.map(\.id)) == ["woche-a", "woche-b"])
        #expect(liste.inDerWoche.allSatisfy { $0.grund == .woche })
        #expect(!liste.alle.map(\.id).contains("andere-woche"))
    }

    @Test("Geordnet wird wie im Raster: erst der Kurs, dann die Zelle")
    func reihenfolge() throws {
        // „woche-b“ steht in der Eintragsliste vor „woche-a“, gehört aber zum zweiten Kurs.
        let liste = try planung().tagesliste(am: try pruefTag)
        #expect(liste.inDerWoche.map(\.id) == ["woche-a", "woche-b"])
        #expect(liste.amTag.map(\.id) == ["heute", "arbeit"])
    }

    @Test("Ein für die Woche freigestellter Kurs hat nichts vor")
    func freieZelle() throws {
        var p = try planung()
        let woche = try #require(p.wochenListe.first { $0.nummer == 1 })
        let a = p.klassen[0].id
        p.zellenfrei.insert(FreieZelle(klasseId: a, woche: woche.montag))
        let liste = p.tagesliste(am: try pruefTag)
        #expect(!liste.inDerWoche.map(\.id).contains("woche-a"))
        // Für heute Eingetragenes bleibt stehen — die genauere Angabe.
        #expect(liste.amTag.map(\.id).contains("heute"))
    }

    @Test("Liegt der Tag außerhalb des Zeitraums, gibt es keine Wochengruppe")
    func ausserhalb() throws {
        let liste = try planung().tagesliste(am: try #require(Tag(iso: "2027-03-03")))
        #expect(liste.woche == nil)
        #expect(liste.inDerWoche.isEmpty)
        #expect(liste.istLeer)
    }

    @Test("Ferien am Tag werden benannt")
    func ferien() throws {
        var p = try planung()
        p.ferien = [Ferienzeitraum(id: "f", name: "Sommerferien",
                                   von: try #require(Tag(iso: "2026-08-10")),
                                   bis: try #require(Tag(iso: "2026-08-16")))]
        let liste = p.tagesliste(am: try pruefTag)
        #expect(liste.ferientag == "Sommerferien")
        #expect(liste.lage.frei)
    }

    /// Die Freistellung gilt für die ganze Woche, nicht nur für die Zelle.
    /// Geprüft werden beide Wege dorthin: von Hand geführt und über Ferien.
    @Test("Eine unterrichtsfreie Woche hat keine Wochengruppe",
          arguments: [true, false])
    func freieWoche(vonHand: Bool) throws {
        var p = try planung()
        let montag = try #require(Tag(iso: "2026-08-10"))
        if vonHand {
            p.frei = [montag]
        } else {
            p.ferien = [Ferienzeitraum(id: "f", name: "Sommerferien", von: montag,
                                       bis: try #require(Tag(iso: "2026-08-16")))]
        }
        let liste = p.tagesliste(am: try pruefTag)
        #expect(liste.lage.frei, "die Vorbedingung: die Woche gilt als unterrichtsfrei")
        #expect(liste.inDerWoche.isEmpty)
        #expect(liste.amTag.map(\.id) == ["heute", "arbeit"])
    }

    @Test("Eine angeschnittene Woche bleibt eine Unterrichtswoche")
    func angeschnitteneWoche() throws {
        var p = try planung()
        p.ferien = [Ferienzeitraum(id: "f", name: "Praktikum",
                                   von: try #require(Tag(iso: "2026-08-10")),
                                   bis: try #require(Tag(iso: "2026-08-11")))]
        let liste = p.tagesliste(am: try pruefTag)
        #expect(!liste.lage.frei)
        #expect(liste.lage.teilweise)
        #expect(Set(liste.inDerWoche.map(\.id)) == ["woche-a", "woche-b"])
    }

    /// Eine Prüfung ohne Termin steht wegen ihrer Woche auf der Liste — „Prüfung
    /// heute“ wäre dafür falsch.
    @Test("Eine Prüfung ohne Termin kommt als Wochenposten, nicht als Termin")
    func pruefungOhneTermin() throws {
        var p = try planung()
        let stelle = try #require(p.eintraege.firstIndex { $0.id == "woche-a" })
        p.eintraege[stelle].pruefung = true
        p.eintraege[stelle].pruefungstag = nil
        let liste = p.tagesliste(am: try pruefTag)
        let posten = try #require(liste.inDerWoche.first { $0.id == "woche-a" })
        #expect(posten.grund == .woche)
        #expect(posten.vorhaben.pruefung)
        #expect(!posten.grund.pruefungHeute)
        #expect(try #require(liste.amTag.first { $0.id == "arbeit" }).grund.pruefungHeute)
    }

    /// Der Prüfungstermin bringt den Posten auf die Liste — dann muss auch er
    /// die Frage nach der Woche beantworten, nicht das leere Datumsfeld.
    @Test("Ein Termin außerhalb der Woche des Vorhabens fällt auf")
    func terminAusserhalbSeinerWoche() throws {
        var p = try planung()
        let stelle = try #require(p.eintraege.firstIndex { $0.id == "arbeit" })
        // Geschrieben wird heute, geplant ist das Vorhaben in Woche 4.
        p.eintraege[stelle].woche = 4
        let liste = p.tagesliste(am: try pruefTag)
        let posten = try #require(liste.amTag.first { $0.id == "arbeit" })
        #expect(posten.grund == .pruefung)
        #expect(posten.ausserhalbSeinerWoche(start: p.start))
        // Das Datumsfeld ist leer; wer nur danach fragte, fände nichts.
        #expect(posten.vorhaben.datum == nil)
        #expect(!posten.vorhaben.datumAusserhalb(start: p.start))
        // Umgekehrt: ein verirrter Termin sagt nichts über einen datumsbedingten Posten.
        var q = try planung()
        let andere = try #require(q.eintraege.firstIndex { $0.id == "heute" })
        q.eintraege[andere].pruefung = true
        let pruefungstag = try #require(Tag(iso: "2026-09-30"))
        q.eintraege[andere].pruefungstag = pruefungstag
        let datiert = try #require(q.tagesliste(am: try pruefTag).amTag
                                    .first { $0.id == "heute" })
        #expect(datiert.grund == .datum)
        #expect(datiert.vorhaben.terminAusserhalb(start: q.start))
        #expect(!datiert.ausserhalbSeinerWoche(start: q.start))
    }

    @Test("Offen und erledigt werden über beide Gruppen gezählt")
    func zaehlen() throws {
        var p = try planung()
        let stelle = try #require(p.eintraege.firstIndex { $0.id == "woche-a" })
        p.eintraege[stelle].erledigt = true
        let liste = p.tagesliste(am: try pruefTag)
        #expect(liste.anzahl == 4)
        #expect(liste.erledigt == 1)
        #expect(liste.offen == 3)
    }

    @Test("Der Haken im Dialog ist derselbe wie der an der Kachel")
    func einStand() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        // Hier zählt allein, dass die Liste den Stand der Planung wiedergibt, keinen eigenen.
        speicher.erledigtUmschalten("woche-a")
        let nachher = try #require(speicher.planung?.eintraege.first { $0.id == "woche-a" })
        #expect(nachher.erledigt)
        let liste = try #require(speicher.planung).tagesliste(am: try pruefTag)
        #expect(try #require(liste.alle.first { $0.id == "woche-a" }).vorhaben.erledigt)
    }
}
