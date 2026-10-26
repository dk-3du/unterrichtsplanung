// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Termin ↔ Vorhaben am Speicher (v80, AP13c-1, E293) ───────────────────
// „Übernehmen“ des Blatts legt das Vorhaben an und zieht es nach; jede
// Änderung der Planung zieht den Termin nach — Widerrufen und Wiederholen
// eingeschlossen; gelöscht gehen immer beide; das Öffnen gleicht ab.

@Suite("Termin ↔ Vorhaben am Speicher: Übernehmen, Nachführen, Widerrufen, Löschen, Abgleich beim Öffnen")
@MainActor
struct TerminkopplungPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "terminkopplung-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// Ein eingeschalteter Speicher: 6a, Klassenleitung und Weiteres über zehn
    /// Wochen ab 3. August 2026; in der Jahresdatei Anna und Ben in der Lerngruppe
    /// der Klassenleitung und ein Termin für Anna — mit Wunsch übernommen.
    private func speicher(_ ablage: URL) throws -> (Planungsspeicher, termin: String, vorhaben: String) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.id = "k-kl"
        var weiteres = Klasse.sonderzeile(.weiteres)
        weiteres.id = "k-we"
        p.klassen += [leitung, weiteres]
        s.planung = p
        s.jetztSichern()
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let s0 = a.erstellt
        let (b, gruppe) = try #require(a.mitNeuerGruppe(name: "Klassenleitung 6a", fach: "", art: .klasse, jetzt: s0))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: gruppe, jetzt: s0).bestand
            .mitBindung(gruppe, an: Zeilenbindung(planung: a.planung, klasseId: "k-kl"), jetzt: s0)
        let anna = try #require(c.lernende.first).id
        #expect(Terminabgleich.vorbelegteZeile(fuer: anna, planung: try #require(s.planung), bestand: c) == "k-kl")
        let (d, termin) = try #require(c.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: [anna],
                                                          datum: "2026-08-20", frist: "", uhrzeit: "07:45", jetzt: s0))
        #expect(s.lernendenUebernehmen(d.mitTerminwunsch(termin, zeile: "k-kl")) == nil)
        let vorhaben = try #require(s.planung?.eintraege.first { $0.termin == termin }).id
        return (s, termin, vorhaben)
    }

    private func termin(_ s: Planungsspeicher, _ id: String) -> Anliegen? {
        s.lernende.bestand?.anliegen.first { $0.id == id }
    }

    private func vorhaben(_ s: Planungsspeicher, _ id: String) -> Vorhaben? {
        s.planung?.eintraege.first { $0.id == id }
    }

    @Test("„Übernehmen“ mit Wunsch: ein Schritt „Termine übernehmen“; ⌘Z nimmt Vorhaben und Termin, ⇧⌘Z bringt beide")
    func uebernehmenUndWiderrufen() throws {
        let ablage = try ordner("uebernehmen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        let vh = try #require(vorhaben(s, v))
        #expect(vh.klasseId == "k-kl" && vh.woche == 2 && vh.datum == Tag(iso: "2026-08-20") && vh.terminzeit == "07:45")
        #expect(termin(s, t)?.vorhaben == v && termin(s, t)?.planung == s.planung?.erstellt)
        #expect(s.verlauf.naechsterName == Schrittname.termineUebernehmen)
        let frisch = Lernendendienst(ablage: Ablage(ordner: ablage))
        _ = frisch.oeffnen(mit: try #require(s.tresor), stempel: "probe")
        #expect(frisch.bestand?.anliegen.first { $0.id == t }?.vorhaben == v, "so in der Datei")

        s.widerrufen()
        #expect(vorhaben(s, v) == nil && termin(s, t) == nil, "immer beide")
        s.wiederholen()
        #expect(vorhaben(s, v)?.termin == t && termin(s, t)?.uhrzeit == "07:45", "beide zurück")
    }

    @Test("Verschieben, Haken und Titel in der Planung ziehen den Termin sofort nach — auch beim Widerrufen")
    func planungZiehtNach() throws {
        let ablage = try ordner("nachziehen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        s.vorhabenVerschieben(v, klasse: "k-we", woche: 3)
        #expect(vorhaben(s, v)?.datum == Tag(iso: "2026-08-27") && termin(s, t)?.datum == "2026-08-27",
                "der Wochentag bleibt, der Termin folgt")
        s.erledigtUmschalten(v)
        let anna = try #require(termin(s, t)?.betroffene.first)
        #expect(s.lernende.verzeichnis?.stand(t, anna) == .erledigt, "der Haken setzt „stattgefunden“")
        s.aendern(Schrittname.titelAendern, kennung: v) { p in
            if let i = p.eintraege.firstIndex(where: { $0.id == v }) { p.eintraege[i].titel = "Gespräch" }
        }
        #expect(termin(s, t)?.titel == "Gespräch")
        s.widerrufen()
        s.widerrufen()
        s.widerrufen()
        #expect(termin(s, t)?.datum == "2026-08-20" && termin(s, t)?.titel == "Elterngespräch")
        #expect(s.lernende.verzeichnis?.stand(t, anna) == .offen)
    }

    @Test("Im Blatt geändert: beim „Übernehmen“ zieht das Vorhaben nach; im Blatt gelöscht: das Vorhaben geht mit")
    func blattZiehtNach() throws {
        let ablage = try ordner("blatt")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        let bestand = try #require(s.lernende.bestand)
        let geaendert = bestand.mitAnliegen(t, titel: "Gespräch", datum: "2026-09-08", frist: "", notiz: "", uhrzeit: "09:30",
                                            jetzt: bestand.geaendert)
        #expect(s.lernendenUebernehmen(geaendert) == nil)
        let vh = try #require(vorhaben(s, v))
        #expect(vh.woche == 5 && vh.datum == Tag(iso: "2026-09-08") && vh.terminzeit == "09:30" && vh.titel == "Gespräch")

        #expect(s.lernendenUebernehmen(try #require(s.lernende.bestand).ohneAnliegen(t).bestand) == nil)
        #expect(vorhaben(s, v) == nil, "immer beide")
        s.widerrufen()
        #expect(vorhaben(s, v) != nil && termin(s, t)?.titel == "Gespräch", "⌘Z bringt beide")
    }

    @Test("Vorhaben löschen: die Rückfrage nennt den Termin, und er geht mit")
    func vorhabenLoeschen() throws {
        let ablage = try ordner("loeschen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        s.vorhabenOeffnen(id: v)  // Aus dem Blatt, an dem die Frage hängt (E418).
        s.vorhabenLoeschen(v)
        let frage = try #require(s.rueckfrage)
        #expect(frage.text.contains("Mit dem Vorhaben geht sein Termin in der Lernendenverwaltung."), Comment(rawValue: frage.text))
        s.rueckfrageBeantworten(true)
        #expect(vorhaben(s, v) == nil && termin(s, t) == nil)

        // Am offenen Blatt „Lernende“: Gäbe es den Termin, stünde die Frage (Z-AU5-05).
        s.offenerDialog = .lernende
        try #require(s.ortAngezeigt(.lernende), "eine Frage am Blatt wäre zu sehen")
        s.anliegenLoeschenFragen(t, in: try #require(s.lernende.bestand)) { _ in }
        #expect(s.rueckfrage == nil && s.wartendeRueckfragen.isEmpty, "den Termin gibt es nicht mehr")
    }

    @Test("Zeile entfernen: die Rückfrage nennt den Termin unter ihren Vorhaben, er geht mit, ⌘Z bringt ihn")
    func zeileEntfernen() throws {
        let ablage = try ordner("zeile")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        let leitung = try #require(s.planung?.klassen.first { $0.id == "k-kl" })
        s.offenerDialog = .klassen  // Aus dem Blatt, an dem die Frage hängt (E418).
        s.klasseEntfernen(leitung)
        let frage = try #require(s.rueckfrage)
        #expect(frage.text.contains("Damit werden auch 1 Vorhaben gelöscht, darunter 1 Termin, der in der Lernendenverwaltung "
                                    + "mitgeht."), Comment(rawValue: frage.text))
        s.rueckfrageBeantworten(true)
        s.offenerDialog = nil  // Das Blatt ist zu; ⌘Z gilt der Planung.
        #expect(vorhaben(s, v) == nil && termin(s, t) == nil)
        s.widerrufen()
        #expect(vorhaben(s, v) != nil && termin(s, t) != nil)
    }

    @Test("Kopie eines Termin-Vorhabens (E294): ein eigener Termin für dieselben Personen, offen, am selben Wochentag der Zielwoche; ⌘Z nimmt beide")
    func kopieAlsTermin() throws {
        let ablage = try ordner("kopie")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        s.erledigtUmschalten(v)
        let original = try #require(vorhaben(s, v))
        let anna = try #require(termin(s, t)?.betroffene.first)
        s.versetzen([original], nach: Zellenort(klasse: "k-we", woche: 4), verschieben: false)
        let kopie = try #require(s.planung?.eintraege.first { $0.istTermin && $0.id != v })
        let neu = try #require(termin(s, kopie.termin))
        #expect(kopie.klasseId == "k-we" && kopie.datum == Tag(iso: "2026-09-03") && kopie.terminzeit == "07:45" && !kopie.erledigt)
        #expect(neu.id != t && neu.titel == "Elterngespräch" && neu.uhrzeit == "07:45" && neu.datum == "2026-09-03"
                && neu.betroffene == [anna] && neu.vorhaben == kopie.id)
        #expect(s.lernende.verzeichnis?.stand(neu.id, anna) == .offen, "die Kopie ist offen")
        #expect(s.lernende.verzeichnis?.stand(t, anna) == .erledigt, "das Original bleibt, wie es war")
        #expect(s.meldungen.contains { $0.text == "Die Kopie ist ein eigener Termin für dieselben Personen — am selben "
                                       + "Wochentag der neuen Woche." })
        s.widerrufen()
        #expect(termin(s, neu.id) == nil && s.planung?.eintraege.contains { $0.id == kopie.id } == false, "⌘Z nimmt beide")
        s.wiederholen()
        #expect(termin(s, neu.id) != nil && s.planung?.eintraege.contains { $0.id == kopie.id } == true, "⇧⌘Z bringt beide")
        #expect(termin(s, t) != nil && vorhaben(s, v)?.termin == t)
    }

    @Test("Kopie ohne ihren Termin (E294): eine gewöhnliche Kopie ohne Tag, und die Meldung sagt es")
    func kopieOhneTermin() throws {
        let ablage = try ordner("kopie-ohne")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        // Der Termin fehlt in der Jahresdatei, das Vorhaben trägt noch seine Kennung.
        #expect(s.lernende.setzen(try #require(s.lernende.bestand).ohneAnliegen(t).bestand) == nil)
        let original = try #require(vorhaben(s, v))
        s.versetzen([original], nach: Zellenort(klasse: "k-we", woche: 4), verschieben: false)
        let kopie = try #require(s.planung?.eintraege.first { $0.id != v && $0.klasseId == "k-we" })
        #expect(!kopie.istTermin && kopie.terminzeit.isEmpty && kopie.datum == nil)
        #expect(s.meldungen.contains { $0.text == "Die Kopie ist kein Termin: Die Lernendenverwaltung ist nicht offen, der "
                                       + "Termin besteht nicht mehr, oder die Grenze der Anliegen ist erreicht." })
    }

    // ── Vorhaben → Termin im Dialog (AP13c-2, E295) ──────────────────────

    private func personen(_ s: Planungsspeicher) throws -> (anna: String, ben: String) {
        let ids = try #require(s.lernende.bestand).lernende.map(\.id)
        return (ids[0], ids[1])
    }

    @Test("Als Termin führen (E295): Kennzeichnen legt den Termin für die gewählten Personen an, ohne Lerngruppe; ⌘Z nimmt beide")
    func kennzeichnen() throws {
        let ablage = try ordner("kennzeichnen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        let (anna, ben) = try personen(s)
        s.vorhabenOeffnen(klasse: "k-we", woche: 1)
        var e = try #require(s.vorhabenDialog)
        e.titel = "Hospitation"
        e.datum = Tag(iso: "2026-08-12")
        e.termin = true
        e.terminzeit = "9.15"
        e.terminpersonen = [anna, ben]
        s.vorhabenSichernFragen(e)
        #expect(s.rueckfrage == nil)
        let v = try #require(s.planung?.eintraege.first { $0.titel == "Hospitation" })
        #expect(v.istTermin && v.terminzeit == "09:15" && v.datum == Tag(iso: "2026-08-12"))
        let t = try #require(termin(s, v.termin))
        #expect(t.betroffene == [anna, ben] && t.titel == "Hospitation" && t.datum == "2026-08-12" && t.uhrzeit == "09:15"
                && t.lerngruppe.isEmpty && t.vorhaben == v.id)
        s.widerrufen()
        #expect(termin(s, v.termin) == nil && vorhaben(s, v.id) == nil, "⌘Z nimmt beide")
        s.wiederholen()
        #expect(termin(s, v.termin)?.betroffene == [anna, ben] && vorhaben(s, v.id)?.istTermin == true)
    }

    @Test("Personen im Dialog (E295): hinzu und heraus, direkt geschrieben; wer herausgeht, verliert seinen Stand; der Haken folgt")
    func personenAendern() throws {
        let ablage = try ordner("personen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        let (anna, ben) = try personen(s)
        s.erledigtUmschalten(v)
        s.vorhabenOeffnen(id: v)
        var e = try #require(s.vorhabenDialog)
        #expect(e.termin && e.terminpersonen == [anna] && e.terminzeit == "07:45")
        e.terminpersonen = [ben]
        s.vorhabenSichernFragen(e)
        #expect(termin(s, t)?.betroffene == [ben])
        #expect(s.lernende.bestand?.rueckmeldungen.contains { $0.anliegen == t && $0.lernender == anna } == false)
        #expect(vorhaben(s, v)?.erledigt == false, "Ben ist offen — der Haken geht")
        #expect(s.lernende.verzeichnis?.stand(t, ben) == .offen)
    }

    @Test("Abschalten (E295): die Rückfrage nennt den Termin; er geht, das Vorhaben bleibt; ⌘Z bringt ihn")
    func abschalten() throws {
        let ablage = try ordner("abschalten")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        s.vorhabenOeffnen(id: v)
        var e = try #require(s.vorhabenDialog)
        e.termin = false
        s.vorhabenSichernFragen(e)
        let frage = try #require(s.rueckfrage)
        #expect(frage.text.hasPrefix("Den Termin „Elterngespräch“ in der Lernendenverwaltung löschen?")
                && frage.text.contains("Das Vorhaben bleibt in der Planung."), Comment(rawValue: frage.text))
        s.rueckfrageBeantworten(true)
        #expect(vorhaben(s, v)?.istTermin == false && vorhaben(s, v)?.terminzeit == "" && termin(s, t) == nil)
        s.widerrufen()
        #expect(vorhaben(s, v)?.termin == t && termin(s, t) != nil, "⌘Z bringt beide")
    }

    @Test("Schranken (E293, E295): Prüfung oder Korrektur schließen den Termin aus; ohne Tag oder Person kein Termin — gemeldet")
    func schranken() throws {
        let ablage = try ordner("schranken")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, v) = try speicher(ablage)
        let (anna, _) = try personen(s)
        let vorher = s.planung
        s.pruefungUmschalten(v)
        s.korrekturUmschalten(v)
        #expect(s.planung == vorher, "an einem Termin werden weder Prüfung noch Korrektur")
        let menue = Rasterkoordinator.merkmalzeilen(vorhaben(s, v))
        #expect(menue.map(\.merkmal) == [.dringlich, .korrektur, .pruefung, .termin], "die Folge des Blatts bleibt")
        #expect(menue.filter(\.gesperrt).map(\.merkmal) == [.korrektur, .pruefung], "im Menü ausgegraut")
        #expect(menue.last?.gesetzt == true)

        s.vorhabenOeffnen(klasse: "k-we", woche: 1)
        var e = try #require(s.vorhabenDialog)
        e.titel = "Klassenarbeit"
        e.datum = Tag(iso: "2026-08-12")
        e.pruefung = true
        e.termin = true
        e.terminpersonen = [anna]
        s.vorhabenSichernFragen(e)
        let arbeit = s.planung?.eintraege.first { $0.titel == "Klassenarbeit" }
        #expect(arbeit?.pruefung == true && arbeit?.istTermin == false, "die Prüfung gilt")

        s.vorhabenOeffnen(klasse: "k-we", woche: 1)
        var f = try #require(s.vorhabenDialog)
        f.titel = "Ohne Person"
        f.datum = Tag(iso: "2026-08-12")
        f.termin = true
        s.vorhabenSichernFragen(f)
        #expect(s.planung?.eintraege.contains { $0.titel == "Ohne Person" } == false)
        #expect(s.meldungen.last?.text == "Ein Termin braucht mindestens eine Person.")
        f.terminpersonen = [anna]
        f.datum = nil
        s.vorhabenSichernFragen(f)
        #expect(s.planung?.eintraege.contains { $0.titel == "Ohne Person" } == false)
        #expect(s.meldungen.last?.text == "Ein Termin braucht einen Tag — bitte einen Wochentag wählen.")
    }

    @Test("Kontextmenü (E296): „Als Termin führen …“ öffnet den Dialog eingeschaltet, mit Tag; „Nicht mehr als Termin führen …“ fragt")
    func kontextmenue() throws {
        let ablage = try ordner("menue")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        // Ohne offene Verwaltung ist der Eintrag grau.
        #expect(Rasterkoordinator.merkmalzeilen(nil, termineMoeglich: false).last?.gesperrt == true)
        s.vorhabenOeffnen(klasse: "k-we", woche: 1)
        var e = try #require(s.vorhabenDialog)
        e.titel = "Sprechstunde"
        s.vorhabenSichernFragen(e)
        let neu = try #require(s.planung?.eintraege.first { $0.titel == "Sprechstunde" })
        s.vorhabenOeffnen(id: neu.id, alsTermin: true)
        let entwurf = try #require(s.vorhabenDialog)
        #expect(entwurf.termin && entwurf.datum != nil && entwurf.terminpersonen.isEmpty, "eingeschaltet, mit vorgeschlagenem Tag")
        s.vorhabenDialog = nil

        s.terminkennzeichnungEntfernenFragen(v)
        let frage = try #require(s.rueckfrage)
        #expect(frage.text.hasPrefix("Den Termin „Elterngespräch“ in der Lernendenverwaltung löschen?"), Comment(rawValue: frage.text))
        s.rueckfrageBeantworten(true)
        #expect(vorhaben(s, v)?.istTermin == false && termin(s, t) == nil)
        #expect(s.verlauf.naechsterName == Schrittname.terminkennzeichnungEntfernen)
        s.widerrufen()
        #expect(vorhaben(s, v)?.termin == t && termin(s, t) != nil, "⌘Z bringt beide")
    }

    @Test("Termin im Blatt löschen: die Rückfrage nennt das Vorhaben in der Planung")
    func terminLoeschenFrage() throws {
        let ablage = try ordner("terminfrage")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, _) = try speicher(ablage)
        s.offenerDialog = .lernende  // Die Frage hängt am Blatt (E418).
        s.anliegenLoeschenFragen(t, in: try #require(s.lernende.bestand)) { _ in }
        let frage = try #require(s.rueckfrage)
        #expect(frage.text.contains("Beim „Übernehmen“ geht auch sein Vorhaben in der Planung."), Comment(rawValue: frage.text))
        s.rueckfrageBeantworten(false)
    }

    @Test("Abgleich beim Öffnen: Planung → Termin; ein Termin ohne sein Vorhaben verliert nur den Verweis und wird gemeldet")
    func abgleichBeimOeffnen() throws {
        let ablage = try ordner("abgleich")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        // Wie eine Jahresdatei, die eine ohne offene Verwaltung bearbeitete Planung
        // trifft: der Titel veraltet, das Vorhaben eines zweiten Termins fehlt.
        var bestand = try #require(s.lernende.bestand)
        if let i = bestand.anliegen.firstIndex(where: { $0.id == t }) { bestand.anliegen[i].titel = "Veraltet" }
        let zweiter = try #require(bestand.mitNeuemAnliegen(.termin, titel: "Zweiter", lerngruppe: "",
                                                            betroffene: bestand.lernende.map(\.id), datum: "2026-08-21",
                                                            frist: "", jetzt: bestand.geaendert))
        var mitVerweis = zweiter.bestand
        if let i = mitVerweis.anliegen.firstIndex(where: { $0.id == zweiter.id }) {
            mitVerweis.anliegen[i].planung = bestand.planung
            mitVerweis.anliegen[i].vorhaben = "e-fehlt"
        }
        #expect(s.lernende.setzen(mitVerweis) == nil)
        s.termineAbgleichen()
        #expect(termin(s, t)?.titel == "Elterngespräch" && vorhaben(s, v)?.titel == "Elterngespräch", "das Vorhaben führt")
        #expect(termin(s, zweiter.id)?.vorhaben == "" && termin(s, zweiter.id) != nil, "gelöst, nicht gelöscht")
        #expect(s.meldungen.contains { $0.text == "1 Termin hat sein Vorhaben in der Planung verloren und bleibt ohne Vorhaben." })
    }

    // ── Nach der Review (AP14a) ──────────────────────────────────────────

    @Test("Höchstens 40 Personen je Termin (E279, W1-02): der Dialog weist mehr ab, der Speicher kappt — die Jahresdatei bleibt schreibbar")
    func hoechstensVierzig() throws {
        let ablage = try ordner("vierzig")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        var b = try #require(s.lernende.bestand)
        let jetzt = b.geaendert
        for i in 0..<40 {
            b.lernende.append(Lernender(id: Kennung.neu("l"), vorname: "V\(i)", nachname: "N\(i)", angelegt: jetzt,
                                        geaendert: jetzt, archiviert: ""))
        }
        #expect(s.lernende.setzen(b) == nil)
        s.vorhabenOeffnen(klasse: "k-we", woche: 1)
        var e = try #require(s.vorhabenDialog)
        e.titel = "Elternabend"
        e.datum = Tag(iso: "2026-08-12")
        e.termin = true
        e.terminpersonen = b.lernende.map(\.id)
        #expect(e.terminFehlt == "Ein Termin hat höchstens \(Kennwerte.maxMitgliederJeLerngruppe) Personen.")
        s.vorhabenSichernFragen(e)
        #expect(s.planung?.eintraege.contains { $0.titel == "Elternabend" } == false, "abgewiesen")
        #expect(s.lernende.ungesichert == nil, "die Jahresdatei bleibt schreibbar")
        let stand = s.terminVorbereiten(e, bisher: nil, vorhaben: "e-probe", titel: "Elternabend")
        #expect(s.terminablage[stand.kennung]?.anliegen.betroffene.count == Kennwerte.maxMitgliederJeLerngruppe,
                "der Speicher kappt auch ohne Dialog")
    }

    @Test("Die Grenze der Anliegen gilt auch für einen neuen Termin aus dem Dialog — abgewiesen und gesagt (W1-02)")
    func grenzeDerAnliegen() throws {
        let ablage = try ordner("grenze")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        let (anna, _) = try personen(s)
        var b = try #require(s.lernende.bestand)
        let jetzt = b.geaendert
        var belegt = Set(b.anliegen.map(\.id))
        while b.anliegen.count < Lernendendatei.maxAnliegen {
            var id = Kennung.neu("m")
            while belegt.contains(id) { id = Kennung.neu("m") }
            belegt.insert(id)
            b.anliegen.append(Anliegen(id: id, art: .massnahme, titel: "Nacharbeit", lerngruppe: "", betroffene: [anna],
                                       datum: "2026-08-20", frist: "", notiz: "", angelegt: jetzt, geaendert: jetzt))
        }
        #expect(s.lernende.setzen(b) == nil)
        s.vorhabenOeffnen(klasse: "k-we", woche: 1)
        var e = try #require(s.vorhabenDialog)
        e.titel = "Sprechtag"
        e.datum = Tag(iso: "2026-08-12")
        e.termin = true
        e.terminpersonen = [anna]
        s.vorhabenSichernFragen(e)
        #expect(s.planung?.eintraege.contains { $0.titel == "Sprechtag" } == false, "abgewiesen")
        #expect(s.meldungen.last?.text == "Höchstens \(Lernendendatei.maxAnliegen) Mitteilungen, Maßnahmen und Termine je "
                + "Schuljahr — der Termin wurde nicht angelegt.")
        #expect(s.lernende.ungesichert == nil, "die Jahresdatei bleibt schreibbar")
    }

    @Test("Scheitert das Schreiben der Jahresdatei, folgt die Planung trotzdem dem Stand der Sitzung (W2-01)")
    func schreibenScheitert() throws {
        let ablage = try ordner("schreiben")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        s.lernende.schreibsperre = { "Probe: gesperrt" }
        defer { s.lernende.schreibsperre = nil }
        let grund = s.lernendenUebernehmen(try #require(s.lernende.bestand).ohneAnliegen(t).bestand)
        #expect(grund != nil, "der Grund kommt zurück")
        #expect(termin(s, t) == nil, "die Sitzung trägt den Stand")
        #expect(vorhaben(s, v) == nil, "die Planung folgt — das Vorhaben des gelöschten Termins geht")
    }

    @Test("⌘Z nach dem Löschen einer Person: ihr Termin kommt nicht ohne Personen zurück — die Meldung sagt es (W1-05)")
    func zurueckOhnePersonen() throws {
        let ablage = try ordner("ohne-personen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        let (anna, _) = try personen(s)
        #expect(s.lernendenUebernehmen(try #require(s.lernende.bestand).ohnePerson(anna).bestand) == nil)
        #expect(termin(s, t) == nil && vorhaben(s, v) == nil, "mit der Person gehen Termin und Vorhaben")
        s.widerrufen()
        #expect(vorhaben(s, v) != nil, "⌘Z bringt das Vorhaben")
        #expect(termin(s, t) == nil, "ein Termin ohne Personen kommt nicht zurück")
        #expect(s.meldungen.last?.text.hasPrefix("Der Termin „Elterngespräch“ kam nicht zurück: Seine Personen gibt es "
                                                  + "nicht mehr.") == true, Comment(rawValue: s.meldungen.last?.text ?? "—"))
    }

    @Test("Abschalten ohne offene Verwaltung wirkt wie im Kontextmenü: die Kennzeichnung geht (W2-02)")
    func abschaltenOhneVerwaltung() throws {
        let ablage = try ordner("ohne-verwaltung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, v) = try speicher(ablage)
        s.vorhabenOeffnen(id: v)
        var e = try #require(s.vorhabenDialog)
        s.lernende.schliessen()
        e.termin = false
        s.vorhabenSichernFragen(e)
        #expect(s.rueckfrage == nil, "ohne offene Verwaltung nichts zu fragen")
        #expect(vorhaben(s, v)?.istTermin == false && vorhaben(s, v)?.terminzeit == "", "die Kennzeichnung geht")
    }

    @Test("Der Wunsch „In der Planung eintragen“ gehört zum Stand (W3-03): ein Schritt, nie geschrieben; ohne ihn kein Vorhaben")
    func wunschImStand() throws {
        let ablage = try ordner("wunsch")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, _) = try speicher(ablage)
        let (_, ben) = try personen(s)
        let b = try #require(s.lernende.bestand)
        let (c, id) = try #require(b.mitNeuemAnliegen(.termin, titel: "Sprechstunde", lerngruppe: "", betroffene: [ben],
                                                       datum: "2026-08-21", frist: "", uhrzeit: "", jetzt: b.geaendert))
        let mitWunsch = c.mitTerminwunsch(id, zeile: "k-we")
        #expect(mitWunsch != c, "ein Wunsch ist eine Änderung — ein Schritt im Verlauf des Blatts")
        #expect(mitWunsch.terminwuensche.wuensche == [id: "k-we"] && mitWunsch.terminwuensche.bestand == c)
        #expect(try Lernendendatei.lesen(try Lernendendatei.schreiben(mitWunsch)) == c, "geschrieben wird er nie")
        #expect(!String(decoding: try Lernendendatei.schreiben(mitWunsch), as: UTF8.self).contains("wunschzeile"),
                "auch nicht als Schlüssel, den der Leser übergeht (Z14a-05)")
        // ⌘Z im Blatt setzt den Stand vor dem Wunsch ein: übernommen ohne Vorhaben.
        #expect(s.lernendenUebernehmen(c) == nil)
        #expect(s.planung?.eintraege.contains { $0.termin == id } == false)
        #expect(s.lernendenUebernehmen(mitWunsch) == nil)
        #expect(s.planung?.eintraege.first { $0.termin == id }?.klasseId == "k-we", "mit Wunsch bekommt er sein Vorhaben")
        #expect(s.lernende.bestand?.anliegen.allSatisfy { $0.wunschzeile.isEmpty } == true, "die Jahresdatei trägt keinen Wunsch")
    }

    // ── Nach der Review des Zugs AP14a ───────────────────────────────────

    @Test("⌘Z bringt einen Termin mit weniger Personen zurück: seine Stände bleiben, der Haken folgt ihnen (Z14a-01)")
    func zurueckMitWenigerPersonen() throws {
        let ablage = try ordner("weniger")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        let (anna, ben) = try personen(s)
        s.vorhabenOeffnen(id: v)
        var e = try #require(s.vorhabenDialog)
        e.terminpersonen = [anna, ben]
        s.vorhabenSichernFragen(e)
        let b = try #require(s.lernende.bestand)
        #expect(s.lernendenUebernehmen(b.mitRuecklauf(t, anna, stand: .erledigt, datum: "2026-08-20", notiz: "",
                                                      jetzt: b.geaendert)) == nil)
        #expect(vorhaben(s, v)?.erledigt == false, "gemischt: kein Haken")
        s.vorhabenOeffnen(id: v)  // Aus dem Blatt, an dem die Frage hängt (E418).
        s.vorhabenLoeschen(v)
        s.rueckfrageBeantworten(true)
        #expect(s.lernendenUebernehmen(try #require(s.lernende.bestand).ohnePerson(ben).bestand) == nil)
        s.widerrufen()
        #expect(s.lernende.verzeichnis?.stand(t, anna) == .erledigt, "der Stand bleibt")
        #expect(vorhaben(s, v)?.erledigt == true, "der Haken folgt den Ständen: alle haben stattgefunden")
    }

    @Test("Haken im Dialog entfernt und Person hinzugefügt: das Entfernen kommt an (Z14a-02)")
    func hakenUndPersonImDialog() throws {
        let ablage = try ordner("haken-person")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        let (anna, ben) = try personen(s)
        s.erledigtUmschalten(v)
        #expect(s.lernende.verzeichnis?.stand(t, anna) == .erledigt)
        s.vorhabenOeffnen(id: v)
        var e = try #require(s.vorhabenDialog)
        e.erledigt = false
        e.terminpersonen = [anna, ben]
        s.vorhabenSichernFragen(e)
        #expect(vorhaben(s, v)?.erledigt == false)
        #expect(s.lernende.verzeichnis?.stand(t, anna) == .offen, "der entfernte Haken nimmt „stattgefunden“")
    }

    /// Bis zur Grenze der Anliegen auffüllen — Maßnahmen für eine Person.
    private func auffuellen(_ s: Planungsspeicher, fuer person: String) throws {
        var b = try #require(s.lernende.bestand)
        var belegt = Set(b.anliegen.map(\.id)).union(s.terminablage.keys)
        while b.anliegen.count < Lernendendatei.maxAnliegen {
            var id = Kennung.neu("m")
            while belegt.contains(id) { id = Kennung.neu("m") }
            belegt.insert(id)
            b.anliegen.append(Anliegen(id: id, art: .massnahme, titel: "Nacharbeit", lerngruppe: "", betroffene: [person],
                                       datum: "2026-08-20", frist: "", notiz: "", angelegt: b.geaendert, geaendert: b.geaendert))
        }
        #expect(s.lernende.setzen(b) == nil)
    }

    @Test("Kopie an der Grenze der Anliegen: eine gewöhnliche Kopie und eine Meldung, die das sagt (Z14a-03)")
    func kopieAnDerGrenze() throws {
        let ablage = try ordner("kopie-grenze")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, _, v) = try speicher(ablage)
        let (anna, _) = try personen(s)
        try auffuellen(s, fuer: anna)
        let original = try #require(vorhaben(s, v))
        s.versetzen([original], nach: Zellenort(klasse: "k-we", woche: 4), verschieben: false)
        let kopie = try #require(s.planung?.eintraege.first { $0.id != v && $0.klasseId == "k-we" })
        #expect(!kopie.istTermin, "keine Kennzeichnung ohne Termin")
        #expect(s.meldungen.contains { $0.text == "Die Kopie ist kein Termin: Die Lernendenverwaltung ist nicht offen, der "
                                       + "Termin besteht nicht mehr, oder die Grenze der Anliegen ist erreicht." })
        #expect(!s.meldungen.contains { $0.text.hasPrefix("Die Kopie ist ein eigener Termin") }, "keine zweite, widersprechende")
    }

    @Test("Ein Termin, der an der Grenze nicht zurückkam, kommt nach Platz und erneutem ⌘Z doch (Z14a-04)")
    func spaeterZurueck() throws {
        let ablage = try ordner("spaeter")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        let (anna, _) = try personen(s)
        s.vorhabenOeffnen(id: v)  // Aus dem Blatt, an dem die Frage hängt (E418).
        s.vorhabenLoeschen(v)
        s.rueckfrageBeantworten(true)
        try auffuellen(s, fuer: anna)
        s.widerrufen()
        #expect(vorhaben(s, v) != nil && termin(s, t) == nil)
        #expect(s.meldungen.last?.text.hasPrefix("Der Termin „Elterngespräch“ kam nicht zurück: Die Lernendenverwaltung trägt "
                                                  + "schon") == true, Comment(rawValue: s.meldungen.last?.text ?? "—"))
        var b = try #require(s.lernende.bestand)
        b.anliegen.removeLast()
        #expect(s.lernende.setzen(b) == nil)
        s.wiederholen()
        s.widerrufen()
        #expect(termin(s, t) != nil, "mit Platz kommt er zurück")
    }

    @Test("Abgeschaltet und ohne Tag: das Vorhaben verliert sein Datum, wie gewählt (W2-03)")
    func abschaltenOhneTag() throws {
        let ablage = try ordner("ohne-tag")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, t, v) = try speicher(ablage)
        s.vorhabenOeffnen(id: v)
        var e = try #require(s.vorhabenDialog)
        e.termin = false
        e.datum = nil
        s.vorhabenSichernFragen(e)
        s.rueckfrageBeantworten(true)
        #expect(termin(s, t) == nil && vorhaben(s, v)?.istTermin == false)
        #expect(vorhaben(s, v)?.datum == nil, "der Tag geht, wie gewählt")
    }
}
