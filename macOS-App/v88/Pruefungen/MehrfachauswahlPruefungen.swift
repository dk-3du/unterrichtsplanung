// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Mehrfachauswahl und gesammelte Zuweisung (v86, AX4: E756–E759, Tabelle 13, 13a) ──
// Mehrere Gewählte in der Mitgliederliste und in „Alle Lernenden“ (E756 b); Sammelgriffe mit einer Rückfrage für alle
// (E757 c); „Auch aufnehmen in“ und „Umziehen nach“, ganz oder gar nicht (E758 a); die Schritte mit der Zahl (E759).
// Archivierte unter den Gewählten übergehen die Sammelgriffe (Vorlage 11) — außer beim endgültigen Löschen (E839). Reine
// Funktionen am Bestand und am Speicher; dazu das Nachfassen (Z-AX4-01, -07) und E835 im Archiv.

@Suite("Mehrfachauswahl: Sammelgriffe, Grenze, Rückfrage, Menü, Auswahl, Wortlaute")
@MainActor
struct MehrfachauswahlPruefungen {

    private static let s = "2026-10-03T08:00:00.000Z"
    private static let jetzt = "2026-10-24T09:00:00.000Z"

    private static func person(_ id: String, _ vorname: String, _ nachname: String, archiviert: String = "") -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: s, geaendert: s, archiviert: archiviert)
    }

    private static func gruppe(_ id: String, _ name: String, _ mitglieder: [String]) -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .kurs, mitglieder: mitglieder, zeilen: [], skalen: [:], halbjahreswechsel: "",
                   geaendert: s, archiviert: "")
    }

    /// Die 40 übrigen Personen, mit denen „Mathe-Förder“ und „Bio-AG“ sich füllen.
    private static let fuelle = (1...40).map { "f-\($0)" }

    /// „6a“ mit Ben Abel, Cem Çelik, Dora Dietz und Emil Ernst (archiviert). „Mathe-Förder“ hat 39 Mitglieder, Cem darunter
    /// (Vorlage 12); „Bio-AG“ ist mit 40 voll; „Chor“ ist leer. Die Mitteilung „Elternbrief“ an „6a“ mit den Rückläufen von
    /// Ben und Cem, die Maßnahme „Nacharbeit“ für Ben und Cem, die Vereinbarung „Handyregel“ für Dora, der Termin
    /// „Elterngespräch“ ohne Lerngruppe für Cem.
    private static func bestand(mathefoerder: Int = 39) -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [person("l-ben", "Ben", "Abel"), person("l-cem", "Cem", "Çelik"), person("l-dora", "Dora", "Dietz"),
                      person("l-emil", "Emil", "Ernst", archiviert: s)]
            + fuelle.map { person($0, "F", $0) }
        b.lerngruppen = [gruppe("g-6a", "6a", ["l-ben", "l-cem", "l-dora", "l-emil"]),
                         gruppe("g-mf", "Mathe-Förder", ["l-cem"] + fuelle.prefix(mathefoerder - 1)),
                         gruppe("g-bio", "Bio-AG", fuelle),
                         gruppe("g-chor", "Chor", [])]
        b.anliegen = [
            Anliegen(id: "m-1", art: .mitteilung, titel: "Elternbrief", lerngruppe: "g-6a",
                     betroffene: ["l-ben", "l-cem", "l-dora"], datum: "2026-10-01", frist: "", notiz: "", angelegt: s,
                     geaendert: s),
            Anliegen(id: "m-2", art: .massnahme, titel: "Nacharbeit", lerngruppe: "g-6a", betroffene: ["l-ben", "l-cem"],
                     datum: "2026-10-02", frist: "2026-10-09", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "v-1", art: .vereinbarung, titel: "Handyregel", lerngruppe: "g-6a", betroffene: ["l-dora"],
                     datum: "2026-10-02", frist: "", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "m-3", art: .termin, titel: "Elterngespräch", lerngruppe: "", betroffene: ["l-cem"],
                     datum: "2026-10-20", frist: "", uhrzeit: "07:45", notiz: "", angelegt: s, geaendert: s),
        ]
        b.rueckmeldungen = [Rueckmeldung(anliegen: "m-1", lernender: "l-ben", stand: .erledigt, datum: "2026-10-02", notiz: "",
                                         geaendert: s),
                            Rueckmeldung(anliegen: "m-1", lernender: "l-cem", stand: .erledigt, datum: "2026-10-02", notiz: "",
                                         geaendert: s)]
        return b
    }

    private static let drei = ["l-ben", "l-cem", "l-dora"]

    private static func mitglieder(_ b: Lernendenbestand, _ gruppe: String) -> [String] {
        b.lerngruppen.first { $0.id == gruppe }?.mitglieder ?? []
    }

    // ── Am Bestand ────────────────────────────────────────────────────────

    @Test("E758 a: „Auch aufnehmen in“ ganz oder gar nicht — über der Grenze die Meldung aus Tabelle 13, nichts geändert; sonst alle in einem, wer schon Mitglied ist, einmal")
    func aufnehmenGanzOderGar() {
        let voll = Self.bestand()
        let ueber = voll.mitMitgliedern(Self.drei + ["l-emil"], inGruppe: "g-mf", jetzt: Self.jetzt)
        #expect(ueber.grund == "„Mathe-Förder“ hätte 41 Mitglieder — höchstens 40 je Lerngruppe. Nichts ist geändert.")
        #expect(ueber.bestand == voll && ueber.zahl == 0, "nichts geändert")

        let platz = Self.bestand(mathefoerder: 38)
        let ergebnis = platz.mitMitgliedern(Self.drei + ["l-emil"], inGruppe: "g-mf", jetzt: Self.jetzt)
        #expect(ergebnis.grund == nil && ergebnis.zahl == 2, "Ben und Dora — Cem ist schon da, Emil ist archiviert")
        let mf = Self.mitglieder(ergebnis.bestand, "g-mf")
        #expect(mf.count == 40 && mf.suffix(2) == ["l-ben", "l-dora"] && mf.filter { $0 == "l-cem" }.count == 1)
        #expect(Self.mitglieder(ergebnis.bestand, "g-6a") == Self.mitglieder(platz, "g-6a"), "Mehrfachmitgliedschaft (E370)")
        #expect(ergebnis.bestand.lerngruppen.first { $0.id == "g-mf" }?.geaendert == Self.jetzt
                && ergebnis.bestand.geaendert == Self.jetzt)
        let schonAlle = platz.mitMitgliedern(["l-ben", "l-cem"], inGruppe: "g-6a", jetzt: Self.jetzt)
        #expect(schonAlle.bestand == platz && schonAlle.zahl == 0 && schonAlle.grund == nil, "alle schon Mitglied: nichts")
    }

    @Test("E758 a: „Umziehen nach“ — alle verlassen „6a“, Cem steht einmal in „Mathe-Förder“; über der Grenze nichts")
    func umziehen() {
        let platz = Self.bestand(mathefoerder: 38)
        let ergebnis = platz.mitUmzuegen(Self.drei + ["l-emil"], von: "g-6a", nach: "g-mf", jetzt: Self.jetzt)
        #expect(ergebnis.grund == nil && ergebnis.zahl == 3)
        #expect(Self.mitglieder(ergebnis.bestand, "g-6a") == ["l-emil"], "die archivierte bleibt")
        let mf = Self.mitglieder(ergebnis.bestand, "g-mf")
        #expect(mf.count == 40 && mf.filter { $0 == "l-cem" }.count == 1 && mf.suffix(2) == ["l-ben", "l-dora"])
        #expect(ergebnis.bestand.anliegen == platz.anliegen && ergebnis.bestand.rueckmeldungen == platz.rueckmeldungen,
                "Mitteilungen und Rückläufe bleiben (E366)")

        let voll = Self.bestand()
        let ueber = voll.mitUmzuegen(Self.drei, von: "g-6a", nach: "g-mf", jetzt: Self.jetzt)
        #expect(ueber.grund == "„Mathe-Förder“ hätte 41 Mitglieder — höchstens 40 je Lerngruppe. Nichts ist geändert.")
        #expect(ueber.bestand == voll && ueber.zahl == 0)
    }

    @Test("Vorlage 11: „Aus der Lerngruppe nehmen“ und „Archivieren“ für die aktiven Gewählten — die archivierte übergehen sie")
    func herausnehmenUndArchivieren() {
        let b = Self.bestand()
        let raus = b.ohneMitgliedern(["l-ben", "l-cem", "l-emil"], ausGruppe: "g-6a", jetzt: Self.jetzt)
        #expect(raus.zahl == 2 && Self.mitglieder(raus.bestand, "g-6a") == ["l-dora", "l-emil"])
        #expect(raus.bestand.lernende == b.lernende, "die Personen bleiben")
        let archiv = b.mitArchiviertenGewaehlten(["l-ben", "l-emil"], jetzt: Self.jetzt)
        #expect(archiv.zahl == 1)
        #expect(archiv.bestand.lernende.first { $0.id == "l-ben" }?.archiviert == Self.jetzt)
        #expect(archiv.bestand.geaendert == Self.jetzt, "der Stempel der Datei wie bei jedem Handgriff (Z-GR1-03)")
        #expect(archiv.bestand.lernende.first { $0.id == "l-emil" }?.archiviert == Self.s, "Emil bleibt, wie er war")
        #expect(archiv.bestand.lerngruppen == b.lerngruppen, "Mitgliedschaften bleiben (E252)")
    }

    @Test("E757 c, Tabelle 13a: Mehrere endgültig — gezählt über alle, was nur Gewählte betraf, einmal; wie einzeln nacheinander")
    func ohnePersonen() {
        let b = Self.bestand()
        let (neu, zahl) = b.ohnePersonen(Self.drei)
        #expect(zahl == Lernendenbestand.Loeschzahl(personen: 3, anliegen: 3, termine: 1, vereinbarungen: 1,
                                                    rueckmeldungen: 2, eintraege: 0))
        let einzeln = Self.drei.reduce(b) { $0.ohnePerson($1).bestand }
        #expect(neu == einzeln)
        let uebrig = neu.anliegen.map(\.id)
        #expect(uebrig == ["m-1"], "die Mitteilung bleibt für die anderen")
    }

    // ── Die Rückfrage ─────────────────────────────────────────────────────

    @Test("Tabelle 13: „3 Personen endgültig löschen?“ — die Namen, die Zahlen über alle, Lerngruppen je einmal; die Antwort reicht den Stand ohne alle drei")
    func rueckfrageMehrerer() throws {
        let speicher = Planungsspeicher(vorschau: nil)
        speicher.offenerDialog = .lernende  // Die Fragen hängen am Blatt (E418).
        let b = Self.bestand()
        var gereicht: Lernendenbestand?
        speicher.personenLoeschenFragen(Self.drei, in: b) { gereicht = $0 }
        let frageOderNil = speicher.rueckfrage
        let frage = try #require(frageOderNil)
        #expect(frage.text == "3 Personen endgültig löschen?\n\n„Abel, Ben“, „Çelik, Cem“, „Dietz, Dora“.\n\nMit ihnen gehen in "
                + "diesem Schuljahr ihre Mitgliedschaften in 2 Lerngruppen, 2 Rückläufe, 1 Maßnahme, 1 Vereinbarung, 1 Termin "
                + "und 0 Einträge. Frühere Schuljahre im Archiv bleiben unberührt.\n\nArchivieren nimmt die Personen nur aus "
                + "den Listen; alles bleibt.", Comment(rawValue: frage.text))
        #expect(frage.ort == .lernende && frage.gefahr && frage.bestaetigung == "Löschen")
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht == b.ohnePersonen(Self.drei).bestand)
    }

    @Test("Tabelle 13: ab 6 die ersten 5 Namen und „und … weitere“; bleibt 1, fragt es wie bei einer Person")
    func rueckfrageNamenUndEine() throws {
        let namen = ["A, 1", "B, 2", "C, 3", "D, 4", "E, 5", "F, 6", "G, 7"]
        #expect(Planungsspeicher.namensliste(namen) == "„A, 1“, „B, 2“, „C, 3“, „D, 4“, „E, 5“ und 2 weitere.")
        #expect(Planungsspeicher.namensliste(Array(namen.prefix(6))) == "„A, 1“, „B, 2“, „C, 3“, „D, 4“, „E, 5“ und 1 weitere.")
        #expect(Planungsspeicher.namensliste(Array(namen.prefix(5))) == "„A, 1“, „B, 2“, „C, 3“, „D, 4“, „E, 5“.")

        let speicher = Planungsspeicher(vorschau: nil)
        speicher.offenerDialog = .lernende
        let b = Self.bestand()
        speicher.personLoeschenFragen("l-ben", in: b) { _ in }
        let einzelnOderNil = speicher.rueckfrage?.text
        let einzeln = try #require(einzelnOderNil)
        speicher.rueckfrageBeantworten(false)
        speicher.personenLoeschenFragen(["l-ben", "l-ben"], in: b) { _ in }
        #expect(speicher.rueckfrage?.text == einzeln, "eine Person: ihr Wortlaut von heute")
        speicher.rueckfrageBeantworten(false)
    }

    // ── Menü, Auswahl, Wortlaute, Schritte ────────────────────────────────

    @Test("E758 a: Das Menü der Sammelleiste — „Auch aufnehmen in“ ohne die Lerngruppen, in denen alle schon stehen, volle gesperrt; „Umziehen nach“ nur mit Quelle")
    func sammelmenue() {
        let b = Self.bestand()
        let inDer6a = Sammelmenue(personen: Self.drei, aus: "g-6a", bestand: b)
        let titel = inDer6a.aufnehmen.map(\.titel)
        let waehlbar = inDer6a.aufnehmen.map(\.waehlbar)
        #expect(titel == ["Bio-AG (voll)", "Chor", "Mathe-Förder"])
        #expect(waehlbar == [false, true, true], "voll gesperrt wie heute; die Grenze sagt der Griff")
        #expect(inDer6a.umziehen == inDer6a.aufnehmen)
        let alle = Sammelmenue(personen: Self.drei, aus: nil, bestand: b)
        #expect(alle.aufnehmen == inDer6a.aufnehmen && alle.umziehen.isEmpty, "in „Alle Lernenden“ nur „Auch aufnehmen in“")
        let nurArchivierte = Sammelmenue(personen: ["l-emil"], aus: "g-6a", bestand: b)
        #expect(nurArchivierte.aufnehmen.isEmpty && nurArchivierte.umziehen.isEmpty)
    }

    @Test("E756 b: Die Auswahl — ab 2 mehrere, sonst die eine Person wie heute; gewählt bleibt, wer in der Liste steht")
    func auswahl() {
        #expect(Lernendenblatt.auswahl(person: "a", mehrere: []) == ["a"])
        #expect(Lernendenblatt.auswahl(person: nil, mehrere: []).isEmpty)
        #expect(Lernendenblatt.auswahl(person: "a", mehrere: ["b", "c"]) == ["b", "c"])
        let eine = Lernendenblatt.auswahlTeilen(["a"])
        #expect(eine.person == "a" && eine.mehrere.isEmpty)
        let keine = Lernendenblatt.auswahlTeilen([])
        #expect(keine.person == nil && keine.mehrere.isEmpty)
        let zwei = Lernendenblatt.auswahlTeilen(["a", "b"])
        #expect(zwei.person == nil && zwei.mehrere == ["a", "b"])
        let bleiben = Lernendenblatt.auswahlNach(sichtbar: ["a", "b", "c"], mehrere: ["a", "b", "x"])
        #expect(bleiben.person == nil && bleiben.mehrere == ["a", "b"])
        let einRest = Lernendenblatt.auswahlNach(sichtbar: ["a"], mehrere: ["a", "x"])
        #expect(einRest.person == "a" && einRest.mehrere.isEmpty, "bleibt 1, ist sie die eine Person")
        let fort = Lernendenblatt.auswahlNach(sichtbar: [], mehrere: ["a", "b"])
        #expect(fort.person == nil && fort.mehrere.isEmpty)
        #expect(Lernendenblatt.sammelauswahl(sichtbar: ["b", "c", "a"], mehrere: ["a", "b", "x"]) == ["b", "a"],
                "in der Folge der Liste")
        #expect(Lernendenblatt.sammelauswahl(sichtbar: ["a", "b"], mehrere: ["a"]) == nil)
    }

    @Test("E931–E934: Sind alle gewählt, merkt ↓ die letzte und ↑ die vorletzte Zeile der Anzeige — sonst nichts")
    func pfeilziel() {
        let zeilen = ["d", "b", "a", "c"]
        let alle: Set<String> = ["a", "b", "c", "d"]
        #expect(Lernendenblatt.pfeilziel(zeilen, gewaehlt: alle, runter: true, mitTasten: false) == "c")
        #expect(Lernendenblatt.pfeilziel(zeilen, gewaehlt: alle, runter: false, mitTasten: false) == "a",
                "wie die Mitgliederliste (E932)")
        #expect(Lernendenblatt.pfeilziel(["x", "y"], gewaehlt: ["x", "y"], runter: false, mitTasten: false) == "x",
                "bei zwei die erste")
        #expect(Lernendenblatt.pfeilziel(zeilen, gewaehlt: alle.union(["außer Sicht der Suche"]), runter: true, mitTasten: false)
                == "c", "Gewählte außerhalb der Anzeige stören nicht")
        #expect(Lernendenblatt.pfeilziel(zeilen, gewaehlt: ["a", "b", "c"], runter: true, mitTasten: false) == nil,
                "nicht alle gewählt: die Tabelle wie gewohnt")
        #expect(Lernendenblatt.pfeilziel(zeilen, gewaehlt: alle, runter: true, mitTasten: true) == nil, "mit ⇧, ⌘, ⌥ oder ⌃")
        #expect(Lernendenblatt.pfeilziel(["a"], gewaehlt: ["a"], runter: true, mitTasten: false) == nil, "eine Zeile")
        #expect(Lernendenblatt.pfeilziel([], gewaehlt: [], runter: true, mitTasten: false) == nil)
    }

    @Test("E933, Z-AZ4-02: Die gemerkte Zeile setzt nur das Leeren von mehreren auf keine beim Druck auf ↓/↑ — nicht ein Klick ins Leere, keine Suche, nicht von einer Person aus")
    func leerenNachPfeil() {
        #expect(Lernendenblatt.leerenNachPfeil(vorher: ["a", "b", "c"], neu: [], beimPfeil: true))
        #expect(!Lernendenblatt.leerenNachPfeil(vorher: ["a", "b", "c"], neu: [], beimPfeil: false),
                "ein Klick ins Leere oder eine Suche")
        #expect(!Lernendenblatt.leerenNachPfeil(vorher: ["a", "b", "c"], neu: ["c"], beimPfeil: true), "die Tabelle wählte selbst")
        #expect(!Lernendenblatt.leerenNachPfeil(vorher: ["a"], neu: [], beimPfeil: true), "von einer Person aus")
        #expect(!Lernendenblatt.leerenNachPfeil(vorher: [], neu: [], beimPfeil: true))
    }

    @Test("Tabelle 13: Kopf und Hilfen der Sammelleiste")
    func wortlaute() {
        #expect(Lernendenblatt.sammelkopf(3) == "3 gewählt" && Lernendenblatt.sammelkopf(2) == "2 gewählt")
        #expect(Lernendenblatt.sammelmenueHilfe(mitQuelle: true)
                == "Die Gewählten in eine weitere Lerngruppe aufnehmen oder aus dieser in eine andere umziehen lassen")
        #expect(Lernendenblatt.sammelHerausnehmenHilfe == "Die Gewählten verbleiben in der Lernendenverwaltung. Beim Übernehmen "
                + "werden sie auch aus dem Sitzplan dieser Lerngruppe entfernt.")
        #expect(Lernendenblatt.sammelArchivierenHilfe == "Die Gewählten aus den Listen nehmen — ihre Einträge bleiben")
        // Freigegeben mit E836 (Menü in „Alle Lernenden“) und E837 (Löschen):
        #expect(Lernendenblatt.sammelmenueHilfe(mitQuelle: false) == "Die Gewählten in eine weitere Lerngruppe aufnehmen")
        #expect(Lernendenblatt.sammelLoeschenHilfe == "Die Gewählten samt ihren Rückläufen und Einträgen dieses Schuljahrs "
                + "löschen — mit Rückfrage")
    }

    @Test("E759: Die Schritte tragen die Zahl — mit 1 der Name von heute; im Katalog die Form mit 2")
    func schrittnamen() {
        #expect(Schrittname.personenAufnehmen(3) == "3 Personen aufnehmen")
        #expect(Schrittname.personenUmziehen(3) == "3 Personen umziehen")
        #expect(Schrittname.personenAusLerngruppeNehmen(3) == "3 Personen aus der Lerngruppe nehmen")
        #expect(Schrittname.personenArchivieren(3) == "3 Personen archivieren")
        #expect(Schrittname.personenLoeschen(3) == "3 Personen endgültig löschen")
        #expect(Schrittname.personenUmziehen(2) == "2 Personen umziehen")
        #expect([Schrittname.personenAufnehmen(1), Schrittname.personenUmziehen(1), Schrittname.personenAusLerngruppeNehmen(1),
                 Schrittname.personenArchivieren(1), Schrittname.personenLoeschen(1)]
                == [Schrittname.inLerngruppeAufnehmen, Schrittname.inAndereLerngruppeUmziehen, Schrittname.ausLerngruppeNehmen,
                    Schrittname.personArchivieren, Schrittname.personLoeschen])
        let mitZwei = ["2 Personen aufnehmen", "2 Personen umziehen", "2 Personen aus der Lerngruppe nehmen",
                       "2 Personen archivieren", "2 Personen endgültig löschen"]
        #expect(mitZwei.allSatisfy(Schrittname.alle.contains))
    }

    // ── Nachfassen (Z-AX4-01, -07, E835, E839) ────────────────────────────

    @Test("Z-AX4-01: Was ein Sammelgriff im Blatt auslöst — an der Grenze die Meldung und kein Schritt, ohne Wirkung nichts, sonst der Name mit der Zahl und der Stand")
    func sammelausgang() {
        let voll = Self.bestand()
        let grenze = voll.mitMitgliedern(Self.drei, inGruppe: "g-mf", jetzt: Self.jetzt)
        #expect(Lernendenblatt.sammelausgang(grenze, name: Schrittname.personenAufnehmen)
                == .meldung("„Mathe-Förder“ hätte 41 Mitglieder — höchstens 40 je Lerngruppe. Nichts ist geändert."))
        let ohneWirkung = voll.mitMitgliedern(["l-ben", "l-cem"], inGruppe: "g-6a", jetzt: Self.jetzt)
        #expect(Lernendenblatt.sammelausgang(ohneWirkung, name: Schrittname.personenAufnehmen) == .nichts)
        let umzug = Self.bestand(mathefoerder: 38).mitUmzuegen(Self.drei, von: "g-6a", nach: "g-mf", jetzt: Self.jetzt)
        #expect(Lernendenblatt.sammelausgang(umzug, name: Schrittname.personenUmziehen)
                == .schritt(name: "3 Personen umziehen", bestand: umzug.bestand))
        let eine = voll.mitArchiviertenGewaehlten(["l-ben", "l-emil"], jetzt: Self.jetzt)
        #expect(Lernendenblatt.sammelausgang(eine, name: Schrittname.personenArchivieren)
                == .schritt(name: "Person archivieren", bestand: eine.bestand), "betrifft er 1, der Name von heute")
    }

    @Test("E839, Vorlage 11: Die Griffe wirken an den aktiven Gewählten, „Endgültig löschen …“ an allen — auch an archivierten")
    func aktiveUndLoeschen() {
        let b = Self.bestand()
        let gewaehlt = ["l-ben", "l-cem", "l-emil", "l-fort"]
        #expect(Lernendenblatt.aktive(gewaehlt, in: b) == ["l-ben", "l-cem"])
        #expect(Lernendenblatt.zuLoeschen(gewaehlt, in: b) == ["l-ben", "l-cem", "l-emil"], "wen es nicht gibt, fällt heraus")
        #expect(Lernendenblatt.zuLoeschen(["l-emil", "l-emil"], in: b) == ["l-emil"])
    }

    @Test("E839: „3 Personen endgültig löschen?“ mit der archivierten — „Abel, Ben“, „Çelik, Cem“, „Ernst, Emil“")
    func rueckfrageMitArchivierten() throws {
        let speicher = Planungsspeicher(vorschau: nil)
        speicher.offenerDialog = .lernende
        let b = Self.bestand()
        let weg = Lernendenblatt.zuLoeschen(["l-ben", "l-cem", "l-emil"], in: b)
        var gereicht: Lernendenbestand?
        speicher.personenLoeschenFragen(weg, in: b) { gereicht = $0 }
        let frageOderNil = speicher.rueckfrage
        let frage = try #require(frageOderNil)
        #expect(frage.text == "3 Personen endgültig löschen?\n\n„Abel, Ben“, „Çelik, Cem“, „Ernst, Emil“.\n\n"
                + "Mit ihnen gehen in diesem Schuljahr ihre Mitgliedschaften in 2 Lerngruppen, 2 Rückläufe, 1 Maßnahme, "
                + "1 Termin und 0 Einträge. Frühere Schuljahre im Archiv bleiben unberührt.\n\nArchivieren nimmt die "
                + "Personen nur aus den Listen; alles bleibt.", Comment(rawValue: frage.text))
        #expect(frage.weitere == nil && frage.beiWeitere == nil, "ohne gebundenen Tisch kein dritter Knopf (E882 a, Z-AY6a-03)")
        speicher.rueckfrageBeantworten(true)
        let geblieben = gereicht?.lernende.map(\.id).filter { $0.hasPrefix("l-") }
        #expect(geblieben == ["l-dora"], "Emil geht mit")
    }

    @Test("Z-AX4-07: Die Rückfrage für mehrere nennt die Vorhaben ihrer Termine und die Tische im Sitzplan, gezählt über alle")
    func rueckfrageMitVorhabenUndTischen() throws {
        let startOderNil = Unterrichtsplanung.Tag(iso: "2026-08-03")
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(startOderNil), wochen: 10, basis: "",
                             klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        let zeileOderNil = p.klassen.first?.id
        let zeile = try #require(zeileOderNil)
        p.eintraege = [Vorhaben(id: "e-1", klasseId: zeile, woche: 2, titel: "Elterngespräch", text: "", erledigt: false,
                                materialien: [], links: [], datum: Unterrichtsplanung.Tag(iso: "2026-10-20"),
                                termin: "m-3", terminzeit: "07:45")]
        let speicher = Planungsspeicher(vorschau: p)
        speicher.offenerDialog = .lernende
        let plan = Sitzplan.anordnen(klasseId: zeile, lernende: [.init(name: "Ben Abel", lernender: "l-ben"),
                                                                 .init(name: "Cem Çelik", lernender: "l-cem")])
        _ = speicher.sitzplaene.setzen(plan, fuer: zeile)
        speicher.personenLoeschenFragen(Self.drei, in: Self.bestand()) { _ in }
        let frageOderNil = speicher.rueckfrage
        let frage = try #require(frageOderNil)
        #expect(frage.text.hasSuffix("Frühere Schuljahre im Archiv bleiben unberührt.\n\nBeim „Übernehmen“ geht auch 1 "
                                     + "Vorhaben in der Planung.\n\nAn 2 Tischen im Sitzplan wird die Zuordnung gelöst; die "
                                     + "Namen an den Tischen bleiben — „Löschen und Tische entfernen“ nimmt zusätzlich die Tische aus dem "
                                     + "Sitzplan.\n\nArchivieren nimmt die Personen nur aus den Listen; alles bleibt."),
                Comment(rawValue: frage.text))
        speicher.rueckfrageBeantworten(false)
    }

    @Test("Z-AX4-07: Leere Auswahl bei allen Griffen, Umziehen in dieselbe Lerngruppe und in eine, in der alle schon stehen")
    func randfaelle() {
        let b = Self.bestand()
        let leer = [b.mitMitgliedern([], inGruppe: "g-chor", jetzt: Self.jetzt),
                    b.mitUmzuegen([], von: "g-6a", nach: "g-chor", jetzt: Self.jetzt),
                    b.ohneMitgliedern([], ausGruppe: "g-6a", jetzt: Self.jetzt),
                    b.mitArchiviertenGewaehlten([], jetzt: Self.jetzt)]
        #expect(leer.allSatisfy { $0.bestand == b && $0.zahl == 0 && $0.grund == nil }, "leere Auswahl: nichts")
        let (ohne, zahl) = b.ohnePersonen([])
        #expect(ohne == b && zahl == Lernendenbestand.Loeschzahl())
        let selbst = b.mitUmzuegen(Self.drei, von: "g-6a", nach: "g-6a", jetzt: Self.jetzt)
        #expect(selbst.bestand == b && selbst.zahl == 0 && selbst.grund == nil, "von gleich nach: nichts")
        var alleImChor = b
        let chorOderNil = alleImChor.lerngruppen.firstIndex { $0.id == "g-chor" }
        guard let chor = chorOderNil else {
            Issue.record("„Chor“ fehlt")
            return
        }
        alleImChor.lerngruppen[chor].mitglieder = Self.drei
        let umzug = alleImChor.mitUmzuegen(Self.drei, von: "g-6a", nach: "g-chor", jetzt: Self.jetzt)
        #expect(umzug.zahl == 3 && umzug.grund == nil)
        #expect(Self.mitglieder(umzug.bestand, "g-6a") == ["l-emil"] && Self.mitglieder(umzug.bestand, "g-chor") == Self.drei)
        #expect(umzug.bestand.lerngruppen.first { $0.id == "g-chor" }?.geaendert == Self.s, "das Ziel bleibt, wie es war")
    }

    @Test("E835: Im Archiv kein ⌘⌫ — die Hilfen der Löschknöpfe ohne „(⌘⌫)“")
    func archivOhneKuerzel() {
        #expect(ArchivAnsicht.personLoeschenHilfe
                == "Die Person in allen archivierten Schuljahren endgültig löschen — das laufende bleibt unberührt")
        #expect(ArchivAnsicht.anliegenLoeschenHilfe == "Das Anliegen samt seinen Rückläufen endgültig aus dem Archiv löschen")
    }

    // ── Zweites Nachfassen (E845, Z-AX4N-01, -07) ─────────────────────────

    @Test("E845: Sind nur Archivierte gewählt, zeigen „Aus der Lerngruppe nehmen“ und „Archivieren“ gesperrt den Sperrgrund")
    func sperrgrund() {
        #expect(Lernendenblatt.sammelSperrgrund == "Erst eine aktive Person wählen")
        for text in [Lernendenblatt.sammelHerausnehmenHilfe, Lernendenblatt.sammelArchivierenHilfe] {
            #expect(Lernendenblatt.sammelhilfe(text, gesperrt: true) == "Erst eine aktive Person wählen")
            #expect(Lernendenblatt.sammelhilfe(text, gesperrt: false) == text)
        }
        // Gesperrt sind beide, wenn keine aktive Person unter den Gewählten ist.
        let b = Self.bestand()
        #expect(Lernendenblatt.aktive(["l-emil"], in: b).isEmpty && !Lernendenblatt.aktive(["l-emil", "l-ben"], in: b).isEmpty)
    }

    /// `bestand()` dazu: die Maßnahme „Lesetagebuch“ für Ben und Dora mit beider Stand, die Vereinbarung „Pausenregel“ für
    /// Cem und Dora, für beide von Hand ungültig, der Termin „Nachprüfung“ nur für Emil (archiviert) und je ein Eintrag in den
    /// vier Listen für Ben und für Dora (Z-AX4N-01).
    private static func reich() -> Lernendenbestand {
        var b = bestand()
        b.anliegen += [
            Anliegen(id: "m-4", art: .massnahme, titel: "Lesetagebuch", lerngruppe: "g-6a", betroffene: ["l-ben", "l-dora"],
                     datum: "2026-10-02", frist: "2026-10-16", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "v-2", art: .vereinbarung, titel: "Pausenregel", lerngruppe: "g-6a", betroffene: ["l-cem", "l-dora"],
                     datum: "2026-10-02", frist: "", notiz: "", angelegt: s, geaendert: s, ungueltig: ["l-cem", "l-dora"]),
            Anliegen(id: "m-5", art: .termin, titel: "Nachprüfung", lerngruppe: "", betroffene: ["l-emil"],
                     datum: "2026-10-22", frist: "", uhrzeit: "08:00", notiz: "", angelegt: s, geaendert: s),
        ]
        for wer in ["l-ben", "l-dora"] {
            b.rueckmeldungen.append(Rueckmeldung(anliegen: "m-4", lernender: wer, stand: .erledigt, datum: "2026-10-10",
                                                 notiz: "", geaendert: s))
            b.erfassung.append(Erfassungseintrag(id: "e-\(wer)", lernender: wer, lerngruppe: "g-6a", planung: "p-1",
                                                 vorhaben: "", datum: "2026-10-05", art: .muendlich, wert: "2", notiz: "",
                                                 angelegt: s, geaendert: s))
            b.beurteilung.append(Beurteilung(id: "b-\(wer)", lernender: wer, lerngruppe: "g-6a", schuljahr: "2026/27",
                                             halbjahr: 1, zeugnisnote: "2", notiz: "", geaendert: s))
            b.verhalten.append(Verhalten(id: "h-\(wer)", lernender: wer, schuljahr: "2026/27", halbjahr: 1,
                                         arbeitsverhalten: "A", sozialverhalten: "A", notiz: "", geaendert: s))
            b.leistungen.append(Leistung(id: "n-\(wer)", lernender: wer, lerngruppe: "g-6a", schuljahr: "2026/27", halbjahr: 1,
                                         art: .schriftlich, titel: "LK 1", datum: "2026-10-07", wert: "2", notiz: "",
                                         planung: "", vorhaben: "", angelegt: s, geaendert: s))
        }
        return b
    }

    @Test("Z-AX4N-01: Ein Durchgang wie je Person nacheinander — an einem reichen Fall, mit Archivierter, doppelter und unbekannter Kennung; die Zahlen gleich der Summe")
    func ohnePersonenReich() throws {
        let b = Self.reich()
        let ids = ["l-ben", "l-cem", "l-emil", "l-ben", "l-unbekannt"]
        let (neu, zahl) = b.ohnePersonen(ids)
        var einzeln = b
        var summe = Lernendenbestand.Loeschzahl()
        for id in ids {
            let (danach, z) = einzeln.ohnePerson(id)
            einzeln = danach
            summe.personen += z.personen
            summe.anliegen += z.anliegen
            summe.termine += z.termine
            summe.vereinbarungen += z.vereinbarungen
            summe.rueckmeldungen += z.rueckmeldungen
            summe.eintraege += z.eintraege
        }
        #expect(neu == einzeln, "derselbe Bestand wie je Person nacheinander")
        #expect(zahl == summe, "die Zahlen gleich der Summe der Einzelzahlen")
        #expect(zahl == Lernendenbestand.Loeschzahl(personen: 3, anliegen: 3, termine: 2, vereinbarungen: 0,
                                                    rueckmeldungen: 3, eintraege: 4))
        // Was Bleibende betrifft, bleibt — für sie allein.
        let lesetagebuchOderNil = neu.anliegen.first { $0.id == "m-4" }
        let lesetagebuch = try #require(lesetagebuchOderNil)
        #expect(lesetagebuch.betroffene == ["l-dora"])
        let pausenregelOderNil = neu.anliegen.first { $0.id == "v-2" }
        let pausenregel = try #require(pausenregelOderNil)
        #expect(pausenregel.betroffene == ["l-dora"] && pausenregel.ungueltig == ["l-dora"])
        let uebrig = neu.anliegen.map(\.id)
        #expect(uebrig == ["m-1", "v-1", "m-4", "v-2"], "Nacharbeit, Elterngespräch und Nachprüfung gehen")
        let staende = neu.rueckmeldungen.map { "\($0.anliegen)/\($0.lernender)" }
        #expect(staende == ["m-4/l-dora"])
        let erfasst = neu.erfassung.map(\.lernender)
        #expect(neu.eintragszahl == 4 && erfasst == ["l-dora"], "Doras Einträge bleiben")
    }

    @Test("E835, Z-AX4N-07: An den Löschknöpfen des Archivs kein ⌘-Kürzel und keine Löschtaste U+007F — in der Quelle gelesen")
    func archivQuelleOhneKuerzel() throws {
        let datei = URL(filePath: #filePath)
            .deletingLastPathComponent()      // Pruefungen
            .deletingLastPathComponent()      // v86
            .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Dialoge/ArchivAnsicht.swift")
        let text = try String(contentsOf: datei, encoding: .utf8)
        // Auch die anderen Schreibweisen der Löschtaste (Z-AX9N-05) — das Archiv kennt keine.
        for form in ["0x7F", "0x7f", "u{7F}", "u{7f}", ".delete", "loeschtaste"] {
            #expect(!text.contains(form), Comment(rawValue: "keine Löschtaste: „\(form)“"))
        }
        let zeilen = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var knoepfe = 0
        for (stelle, zeile) in zeilen.enumerated()
        where zeile.contains("Button(\"In allen Schuljahren löschen …\"") || zeile.contains("Button(\"Löschen …\"") {
            knoepfe += 1
            // Die Kette des Knopfs bis zum nächsten Knopf — an Löschknöpfen ist gar kein Kürzel gewollt (E835, Z-AX9N-05).
            let kette = [zeilen[stelle]] + zeilen[(stelle + 1)...].prefix { !$0.contains("Button(") }
            let kuerzel = kette.filter { $0.contains("keyboardShortcut") }
            #expect(kuerzel.isEmpty, Comment(rawValue: kuerzel.joined(separator: "\n")))
        }
        #expect(knoepfe == 2, "beide Löschknöpfe gefunden")
    }
}
