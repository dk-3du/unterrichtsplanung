// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Die Schreibsperre der Ablage, von der Prüfung zugemacht und wieder geöffnet — gelesen auf jedem Faden.
private final class Tor: @unchecked Sendable {
    private let sperre = NSLock()
    private var zu = false
    func schliessen() { sperre.withLock { zu = true } }
    func oeffnen() { sperre.withLock { zu = false } }
    var grund: String? { sperre.withLock { zu ? "eine Prüfsperre" : nil } }
}

/// Eine Schreibsperre, die nur die genannten Anfragen abweist (gezählt ab 1) — und festhält, wie viele kamen.
private final class Zaehltor: @unchecked Sendable {
    private let sperre = NSLock()
    private let abweisen: Set<Int>
    private var gezaehlt = 0
    init(abweisen: Set<Int>) { self.abweisen = abweisen }
    var anfragen: Int { sperre.withLock { gezaehlt } }
    var grund: String? {
        sperre.withLock {
            gezaehlt += 1
            return abweisen.contains(gezaehlt) ? "eine Prüfsperre" : nil
        }
    }
}

/// Was die Senke eines Dienstes erreicht.
@MainActor
private final class Meldungsmerker {
    var meldungen: [(String, Meldung.Art)] = []
}

// ── Fassung 2: keine Obergrenze in den Dateien (v90, BB1, E970, E978, E979) ──
// Jahresdatei, Archivjahre und Sitzplandatei tragen Fassung 2: Der Leser kappt dort nicht mehr bei 40 Personen je
// Lerngruppe und Anliegen und nicht bei 40 Tischen. Fassung 1 liest sich wie bisher und wird beim ersten Lesen einmal
// umgeschrieben — das Original bleibt bytegleich als `*-fassung1-<Stempel>.json` daneben; ohne bewahrtes Original
// wird nichts darüber geschrieben (E46).

@Suite("Fassung 2: keine Obergrenze in den Dateien, Fassung 1 einmal umgeschrieben, das Original bewahrt (E970, E978, E979)")
@MainActor
struct FassungZweiPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private static let stempel = "2026-10-31T08:00:00.000Z"
    private static let herkunft = "2026-08-10T09:00:00.000Z"
    /// Mehr als die 40, die bis 2.4.0 galten.
    private static let viele = 45

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "fassung2-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func aufraeumen(_ orte: URL...) {
        for ort in orte { try? FileManager.default.removeItem(at: ort) }
    }

    private func tresor() throws -> Tresor {
        let t = Tresor.neu()
        try t.passphraseSetzen(passphrase, runden: Tresor.rundenMindestens)
        return t
    }

    private func kopie(_ ort: URL, _ name: String) -> Data? {
        try? Data(contentsOf: ort.appendingPathComponent(name, isDirectory: false))
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("7b", "Biologie")]), fachfarben: [:])
        p.erstellt = Self.herkunft
        return p
    }

    /// `zahl` Personen in einer Klasse, eine Mitteilung an alle und ein Termin mit allen.
    private func bestand(_ zahl: Int, planung: String = Self.herkunft) -> Lernendenbestand {
        let s = Self.stempel
        var b = Lernendenbestand.leer(planung: planung, schuljahr: "2026/27", jetzt: s)
        let ids = (1...zahl).map { "l-\($0)" }
        b.lernende = ids.map {
            Lernender(id: $0, vorname: "Vorname \($0)", nachname: "Nachname", angelegt: s, geaendert: s, archiviert: "")
        }
        b.lerngruppen = [Lerngruppe(id: "g-1", name: "7b", art: .klasse, mitglieder: ids, zeilen: [], skalen: [:],
                                    halbjahreswechsel: "", geaendert: s, archiviert: "")]
        b.anliegen = [Anliegen(id: "a-1", art: .mitteilung, titel: "Elternbrief Wandertag", lerngruppe: "g-1",
                               betroffene: ids, datum: "2026-09-07", frist: "", notiz: "", angelegt: s, geaendert: s),
                      Anliegen(id: "a-2", art: .termin, titel: "Elternabend", lerngruppe: "", betroffene: ids,
                               datum: "2026-09-10", frist: "", uhrzeit: "19:00", notiz: "", angelegt: s, geaendert: s),
                      Anliegen(id: "a-3", art: .vereinbarung, titel: "Handyregel", lerngruppe: "g-1", betroffene: ids,
                               datum: "2026-09-01", frist: "", notiz: "", angelegt: s, geaendert: s, ungueltig: ids)]
        return b
    }

    private func objekt(_ daten: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: daten) as? [String: Any])
    }

    /// Dieselbe Datei in Fassung 1 — so, wie 2.4.0 sie schrieb.
    private func inFassungEins(_ daten: Data) throws -> Data {
        var o = try objekt(daten)
        o["version"] = 1
        return try JSONSerialization.data(withJSONObject: o)
    }

    private func sitzplan(_ zahl: Int) -> Sitzplan {
        let tische = (1...zahl).map { n in
            Tisch(id: "t-\(n)", name: "Platz \(n)", x: CGFloat(40 + 90 * (n % 8)), y: CGFloat(40 + 60 * (n / 8)))
        }
        return Sitzplan(klasseId: "k-eins", tische: tische, lehrertisch: nil, geaendert: Self.stempel)
    }

    // ── Modell ────────────────────────────────────────────────────────────

    @Test("Die Jahresdatei schreibt Fassung 2; Klasse, Mitteilung und Termin mit 45 Personen lesen sich ohne Verlust")
    func jahresdateiOhneGrenze() throws {
        let daten = try Lernendendatei.schreiben(bestand(Self.viele))
        #expect(Planungsdatei.ganzzahl(try objekt(daten)["version"]) == 2, "Fassung 2")
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(daten)
        #expect(gelesen.lerngruppen.first?.mitglieder.count == Self.viele, "alle Mitglieder")
        #expect(gelesen.anliegen.map(\.betroffene.count) == [Self.viele, Self.viele, Self.viele],
                "alle Betroffenen und Personen")
        #expect(gelesen.anliegen.last?.ungueltig.count == Self.viele, "alle „ungültig“ an der Vereinbarung")
        #expect(!bilanz.verlust && !bilanz.umzuschreiben, "\(bilanz.beschreibung)")
    }

    @Test("Fassung 1 liest sich wie bisher — höchstens 40 je Lerngruppe und Anliegen — und ist umzuschreiben")
    func fassungEinsWieBisher() throws {
        let alt = try inFassungEins(try Lernendendatei.schreiben(bestand(Self.viele)))
        let (gross, bilanzGross) = try Lernendendatei.lesenMitBilanz(alt)
        #expect(gross.lerngruppen.first?.mitglieder.count == Lernendendatei.grenzeFassungEins)
        #expect(bilanzGross.verworfeneMitglieder == Self.viele - Lernendendatei.grenzeFassungEins)
        #expect(gross.anliegen.map(\.betroffene.count) == Array(repeating: Lernendendatei.grenzeFassungEins, count: 3),
                "je Anliegen höchstens 40 in Fassung 1")
        #expect(bilanzGross.umzuschreiben, "Fassung 1 wird einmal umgeschrieben")

        let (_, bilanz) = try Lernendendatei.lesenMitBilanz(try inFassungEins(try Lernendendatei.schreiben(bestand(2))))
        #expect(bilanz.umzuschreiben && !bilanz.verlust && bilanz.istLeer, "ohne Verlust, aber umzuschreiben")
    }

    @Test("Eine Fassung über 2 sperrt — Jahresdatei, Archivjahr und Sitzpläne")
    func fassungDreiSperrt() throws {
        var lernende = try objekt(try Lernendendatei.schreiben(bestand(2)))
        lernende["version"] = 3
        #expect(throws: Lernendendatei.Fehler.self) {
            try Lernendendatei.lesen(try JSONSerialization.data(withJSONObject: lernende))
        }
        var archiv = try objekt(try Archivdatei.schreiben(
            Archivbestand.leer.mitJahr(planung: try planung(), lernende: bestand(2), jetzt: Self.stempel)))
        var jahre = try #require(archiv["jahre"] as? [[String: Any]])
        var jahr = try #require(jahre.first?["lernende"] as? [String: Any])
        jahr["version"] = 3
        jahre[0]["lernende"] = jahr
        archiv["jahre"] = jahre
        do {
            _ = try Archivdatei.lesen(try JSONSerialization.data(withJSONObject: archiv))
            Issue.record("ein Archivjahr in Fassung 3 muss das Archiv sperren")
        } catch let fehler as Archivdatei.Fehler {
            #expect(fehler.art == .neuereFassung)
        }
        var plaene = try objekt(try Sitzplandatei.schreiben(["k-eins": sitzplan(2)]))
        plaene["version"] = 3
        do {
            _ = try Sitzplandatei.lesen(try JSONSerialization.data(withJSONObject: plaene))
            Issue.record("Sitzpläne in Fassung 3 müssen gesperrt sein")
        } catch let fehler as Sitzplandatei.Fehler {
            #expect(fehler.art == .neuereFassung)
        }
    }

    @Test("Ein Archivjahr trägt Fassung 2 und liest sich ohne Verlust; ein Jahr in Fassung 1 ist umzuschreiben")
    func archivjahrFassungZwei() throws {
        let archiv = Archivbestand.leer.mitJahr(planung: try planung(), lernende: bestand(Self.viele),
                                                jetzt: Self.stempel)
        let daten = try Archivdatei.schreiben(archiv)
        var o = try objekt(daten)
        var jahre = try #require(o["jahre"] as? [[String: Any]])
        var jahr = try #require(jahre.first?["lernende"] as? [String: Any])
        #expect(Planungsdatei.ganzzahl(jahr["version"]) == 2, "das Jahr trägt Fassung 2")
        let (gelesen, bilanz) = try Archivdatei.lesenMitBilanz(daten)
        #expect(gelesen.jahre.first?.lernende?.lerngruppen.first?.mitglieder.count == Self.viele)
        #expect(!bilanz.verlust && !bilanz.umzuschreiben, "\(bilanz.beschreibung)")

        let klein = try objekt(try Lernendendatei.schreiben(bestand(2)))
        jahr = klein
        jahr["version"] = 1
        jahre[0]["lernende"] = jahr
        o["jahre"] = jahre
        let (_, bilanzAlt) = try Archivdatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: o))
        #expect(bilanzAlt.umzuschreiben && !bilanzAlt.verlust, "ein Jahr in Fassung 1: umzuschreiben, ohne Verlust")
    }

    @Test("Die Sitzplandatei schreibt Fassung 2; 45 Tische lesen sich ohne Verlust; Fassung 1 wie bisher, umzuschreiben")
    func sitzplaeneOhneGrenze() throws {
        let daten = try Sitzplandatei.schreiben(["k-eins": sitzplan(Self.viele)])
        #expect(Planungsdatei.ganzzahl(try objekt(daten)["version"]) == 2, "Fassung 2")
        let (plaene, bilanz) = try Sitzplandatei.lesenMitBilanz(daten)
        #expect(plaene["k-eins"]?.tische.count == Self.viele, "alle Tische")
        #expect(!bilanz.verlust && !bilanz.umzuschreiben, "\(bilanz.beschreibung)")

        let (alt, bilanzAlt) = try Sitzplandatei.lesenMitBilanz(try inFassungEins(daten))
        #expect(alt["k-eins"]?.tische.count == Sitzplandatei.grenzeFassungEins)
        #expect(bilanzAlt.verworfeneTische == Self.viele - Sitzplandatei.grenzeFassungEins && bilanzAlt.umzuschreiben)
    }

    // ── Dienste ───────────────────────────────────────────────────────────

    @Test("Eine Jahresdatei der Fassung 1 wird beim Öffnen einmal umgeschrieben; das Original liegt bytegleich daneben")
    func jahresdateiUmgeschrieben() throws {
        let ort = try ordner("jahresdatei")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try t.versiegeln(try inFassungEins(try Lernendendatei.schreiben(bestand(2))),
                                        inhalt: .lernende, ziel: .ablage)
        try original.write(to: ablage.lernende)

        let erster = Lernendendienst(ablage: ablage).oeffnen(mit: t, stempel: "s1")
        #expect(erster == .umgeschrieben(2, kopie: "lernende-fassung1-s1.json"), "\(erster)")
        #expect(kopie(ort, "lernende-fassung1-s1.json") == original, "das Original bytegleich bewahrt")
        #expect(try Data(contentsOf: ablage.lernende) != original, "umgeschrieben")
        let zweiter = Lernendendienst(ablage: ablage).oeffnen(mit: t, stempel: "s2")
        #expect(zweiter == .geladen(2), "der zweite Start liest Fassung 2 — \(zweiter)")
        #expect(kopie(ort, "lernende-fassung1-s2.json") == nil, "keine zweite Kopie")
    }

    @Test("Ohne bewahrtes Original wird die Jahresdatei nicht umgeschrieben — erst, wenn die Kopie gelingt")
    func jahresdateiOhneKopieNicht() throws {
        let ort = try ordner("ohne-kopie")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try t.versiegeln(try inFassungEins(try Lernendendatei.schreiben(bestand(2))),
                                        inhalt: .lernende, ziel: .ablage)
        try original.write(to: ablage.lernende)
        // Nur die beiden Kopien abweisen (beim Lesen und vor dem Schreiben) — das Schreiben selbst ginge durch: Bliebe
        // die Datei trotzdem, wie sie lag, hält sie der Riegel `originalBewahren` (E46), nicht die Sperre (Z-BB1-05).
        let tor = Zaehltor(abweisen: [1, 2])
        ablage.schreibsperre = { tor.grund }

        let dienst = Lernendendienst(ablage: ablage)
        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        #expect(befund == .umgeschrieben(2, kopie: nil), "\(befund)")
        #expect(tor.anfragen == 2, "die Kopie zweimal versucht, kein Schreiben — Anfragen: \(tor.anfragen)")
        #expect(dienst.ausstehendeKopie == "lernende-fassung1-s1.json")
        #expect(try Data(contentsOf: ablage.lernende) == original, "nichts darüber geschrieben")

        let gesichert = try #require(dienst.bestand)
        #expect(dienst.setzen(gesichert) == nil)
        #expect(kopie(ort, "lernende-fassung1-s1.json") == original, "erst die Kopie, dann das Schreiben")
        #expect(Lernendendienst(ablage: ablage).oeffnen(mit: t, stempel: "s2") == .geladen(2))
    }

    @Test("Ein Archiv mit einem Jahr der Fassung 1 wird beim ersten Lesen einmal umgeschrieben; das Original liegt daneben")
    func archivUmgeschrieben() throws {
        let ort = try ordner("archiv")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        try t.versiegeln(try Lernendendatei.schreiben(bestand(2)), inhalt: .lernende, ziel: .ablage)
            .write(to: ablage.lernende)
        var o = try objekt(try Archivdatei.schreiben(
            Archivbestand.leer.mitJahr(planung: try planung(), lernende: bestand(2), jetzt: Self.stempel)))
        var jahre = try #require(o["jahre"] as? [[String: Any]])
        var jahr = try #require(jahre.first?["lernende"] as? [String: Any])
        jahr["version"] = 1
        jahre[0]["lernende"] = jahr
        o["jahre"] = jahre
        let original = try t.versiegeln(try JSONSerialization.data(withJSONObject: o), inhalt: .archiv, ziel: .ablage)
        try original.write(to: ablage.archiv)

        let dienst = Lernendendienst(ablage: ablage)
        let merker = Meldungsmerker()
        dienst.melden = { text, art in merker.meldungen.append((text, art)) }
        #expect(dienst.oeffnen(mit: t, stempel: "s0") == .geladen(2))
        guard case .gelesen(_, let bilanz, let name) = dienst.archivLesen(stempel: "s1") else {
            Issue.record("erwartet gelesen")
            return
        }
        #expect(bilanz.umzuschreiben && name == "archiv-fassung1-s1.json", "\(bilanz) \(String(describing: name))")
        let erwartet = "Das Archiv liegt jetzt in der neuen Fassung von 2.5.0 — das Original liegt als "
            + "„archiv-fassung1-s1.json“ neben der Planung."
        #expect(merker.meldungen.count == 1 && merker.meldungen.first?.0 == erwartet
                && merker.meldungen.first?.1 == .hinweis, "\(merker.meldungen.map(\.0))")
        #expect(kopie(ort, "archiv-fassung1-s1.json") == original, "das Original bytegleich bewahrt")
        guard case .gelesen(_, let wieder, nil) = dienst.archivLesen(stempel: "s2") else {
            Issue.record("das zweite Lesen: erwartet gelesen ohne Kopie")
            return
        }
        #expect(!wieder.umzuschreiben && kopie(ort, "archiv-fassung1-s2.json") == nil,
                "umgeschrieben, keine zweite Kopie")
    }

    @Test("Ohne bewahrtes Original gibt ein Archiv der Fassung 1 kein Schreiben frei")
    func archivOhneKopieKeineFreigabe() throws {
        let ort = try ordner("archiv-ohne-kopie")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        try t.versiegeln(try Lernendendatei.schreiben(bestand(2)), inhalt: .lernende, ziel: .ablage)
            .write(to: ablage.lernende)
        var o = try objekt(try Archivdatei.schreiben(
            Archivbestand.leer.mitJahr(planung: try planung(), lernende: bestand(2), jetzt: Self.stempel)))
        var jahre = try #require(o["jahre"] as? [[String: Any]])
        var jahr = try #require(jahre.first?["lernende"] as? [String: Any])
        jahr["version"] = 1
        jahre[0]["lernende"] = jahr
        o["jahre"] = jahre
        let original = try t.versiegeln(try JSONSerialization.data(withJSONObject: o), inhalt: .archiv, ziel: .ablage)
        try original.write(to: ablage.archiv)

        let dienst = Lernendendienst(ablage: ablage)
        #expect(dienst.oeffnen(mit: t, stempel: "s0") == .geladen(2))
        let tor = Tor()
        tor.schliessen()
        ablage.schreibsperre = { tor.grund }
        dienst.schreibsperre = { tor.grund }
        let befund = dienst.archivLesen(stempel: "s1")
        guard case .gelesen(let archiv, let bilanz, nil) = befund, bilanz.umzuschreiben else {
            Issue.record("erwartet gelesen, umzuschreiben, ohne Kopie — \(befund)")
            return
        }
        tor.oeffnen()
        let grund = dienst.archivSetzen(archiv, stempel: "s2", gelesen: befund)
        #expect(grund?.contains("nicht bewahrt") == true, "\(String(describing: grund))")
        #expect(try Data(contentsOf: ablage.archiv) == original, "nichts darüber geschrieben")
    }

    @Test("Sitzpläne der Fassung 1 werden beim Öffnen einmal umgeschrieben; das Original liegt bytegleich daneben")
    func sitzplaeneUmgeschrieben() throws {
        let ort = try ordner("sitzplaene")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try t.versiegeln(try inFassungEins(try Sitzplandatei.schreiben(["k-eins": sitzplan(2)])),
                                        inhalt: .sitzplaene, ziel: .ablage)
        try original.write(to: ablage.sitzplaene)

        let erster = Sitzplandienst(ablage: ablage).oeffnen(mit: t, stempel: "s1")
        #expect(erster == .umgeschrieben(1, kopie: "sitzplaene-fassung1-s1.json"), "\(erster)")
        #expect(kopie(ort, "sitzplaene-fassung1-s1.json") == original, "das Original bytegleich bewahrt")
        #expect(try Data(contentsOf: ablage.sitzplaene) != original, "umgeschrieben")
        let zweiter = Sitzplandienst(ablage: ablage).oeffnen(mit: t, stempel: "s2")
        #expect(zweiter == .geladen(1), "der zweite Start liest Fassung 2 — \(zweiter)")
        #expect(kopie(ort, "sitzplaene-fassung1-s2.json") == nil, "keine zweite Kopie")
    }

    @Test("Sitzpläne der Fassung 1 im Klartext, ohne Verschlüsselung: einmal umgeschrieben, Original daneben (Z-BB8-W1-B5 f)")
    func sitzplaeneKlartextUmgeschrieben() throws {
        let ort = try ordner("sitzplaene-klartext")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let original = try inFassungEins(try Sitzplandatei.schreiben(["k-eins": sitzplan(2)]))
        try original.write(to: ablage.sitzplaene)
        let erster = Sitzplandienst(ablage: ablage).laden(stempel: "s1")
        #expect(erster == .umgeschrieben(1, kopie: "sitzplaene-fassung1-s1.json"), "\(erster)")
        #expect(kopie(ort, "sitzplaene-fassung1-s1.json") == original, "das Original bytegleich bewahrt")
        #expect(try Data(contentsOf: ablage.sitzplaene) != original, "umgeschrieben")
        let zweiter = Sitzplandienst(ablage: ablage).laden(stempel: "s2")
        #expect(zweiter == .geladen(1), "der zweite Start liest Fassung 2 — \(zweiter)")
    }

    @Test("Sitzpläne der Fassung 1 mit Verlust (41 Tische): Original als „-bereinigt-“, keine „-fassung1-“ (Z-BB8-W1-B5 a)")
    func sitzplaeneFassungEinsMitVerlust() throws {
        let ort = try ordner("sitzplaene-verlust")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try t.versiegeln(try inFassungEins(try Sitzplandatei.schreiben(["k-eins": sitzplan(41)])),
                                        inhalt: .sitzplaene, ziel: .ablage)
        try original.write(to: ablage.sitzplaene)
        guard case .bereinigt(1, let bilanz, kopie: "sitzplaene-bereinigt-s1.json") = Sitzplandienst(ablage: ablage)
                .oeffnen(mit: t, stempel: "s1") else {
            Issue.record("erwartet bereinigt mit der Kopie „-bereinigt-“")
            return
        }
        #expect(bilanz.verlust && bilanz.umzuschreiben)
        #expect(kopie(ort, "sitzplaene-bereinigt-s1.json") == original && kopie(ort, "sitzplaene-fassung1-s1.json") == nil)
        #expect(Sitzplandienst(ablage: ablage).oeffnen(mit: t, stempel: "s2") == .geladen(1), "der zweite Start liest sauber")
    }

    // ── Nachgefasst nach der Zug-Review (Z-BB1-01 bis -08) ──────────────────

    @Test("Fassung 1 mit Verlust: das Original als „-bereinigt-“, Befund bereinigt; der zweite Start liest sauber (Z-BB1-04)")
    func fassungEinsMitVerlust() throws {
        let ort = try ordner("fassung1-verlust")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        var o = try objekt(try inFassungEins(try Lernendendatei.schreiben(bestand(2))))
        var gruppen = try #require(o["lerngruppen"] as? [[String: Any]])
        gruppen[0]["mitglieder"] = ["l-1", "l-2", "l-9"]
        o["lerngruppen"] = gruppen
        let original = try t.versiegeln(try JSONSerialization.data(withJSONObject: o), inhalt: .lernende, ziel: .ablage)
        try original.write(to: ablage.lernende)

        guard case .bereinigt(2, let bilanz, kopie: "lernende-bereinigt-s1.json") = Lernendendienst(ablage: ablage)
                .oeffnen(mit: t, stempel: "s1") else {
            Issue.record("erwartet bereinigt mit der Kopie „-bereinigt-“")
            return
        }
        #expect(bilanz.verlust && bilanz.umzuschreiben)
        #expect(kopie(ort, "lernende-bereinigt-s1.json") == original && kopie(ort, "lernende-fassung1-s1.json") == nil)
        #expect(Lernendendienst(ablage: ablage).oeffnen(mit: t, stempel: "s2") == .geladen(2))
    }

    @Test("Die Meldungen beim Öffnen: Lernendendaten und Sitzpläne „liegen jetzt in der neuen Fassung“ — als Hinweis")
    func meldungenBeimOeffnen() throws {
        let ort = try ordner("meldungen")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        try t.versiegeln(try inFassungEins(try Lernendendatei.schreiben(bestand(2))), inhalt: .lernende, ziel: .ablage)
            .write(to: ablage.lernende)
        try t.versiegeln(try inFassungEins(try Sitzplandatei.schreiben(["k-eins": sitzplan(2)])), inhalt: .sitzplaene,
                         ziel: .ablage).write(to: ablage.sitzplaene)
        let s = Planungsspeicher(ablage: ablage)
        s.lernendeOeffnen(t)
        s.sitzplaeneOeffnen(t)
        let texte = s.meldungen.map(\.text)
        let lernende = "Die Lernendendaten liegen jetzt in der neuen Fassung von 2.5.0 — das Original liegt als "
            + "„lernende-fassung1-"
        let sitzplaene = "Die Sitzpläne (1) liegen jetzt in der neuen Fassung von 2.5.0 — das Original liegt als "
            + "„sitzplaene-fassung1-"
        #expect(s.meldungen.contains { $0.text.hasPrefix(lernende) && $0.text.hasSuffix(".json“ neben der Planung.")
                                       && $0.art == .hinweis }, "\(texte)")
        #expect(s.meldungen.contains { $0.text.hasPrefix(sitzplaene) && $0.art == .hinweis }, "\(texte)")
    }

    @Test("Liegt die Kopie, misslingt aber das Schreiben, sagt keine Meldung „liegen jetzt“ (Z-BB1-02)")
    func meldungOhneSchreiben() throws {
        let ort = try ordner("meldung-ohne-schreiben")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try t.versiegeln(try inFassungEins(try Lernendendatei.schreiben(bestand(2))),
                                        inhalt: .lernende, ziel: .ablage)
        try original.write(to: ablage.lernende)
        // Die Kopie gelingt (Anfrage 1), alles danach nicht. Erst nach dem Speicher gesetzt — der Sicherungsdienst
        // knüpft beim Anlegen seine eigene Sperre an die Ablage.
        let tor = Zaehltor(abweisen: Set(2...50))
        let s = Planungsspeicher(ablage: ablage)
        s.sicherung.ablage.schreibsperre = { tor.grund }
        s.lernendeOeffnen(t)
        let texte = s.meldungen.map(\.text)
        let namen = try FileManager.default.contentsOfDirectory(atPath: ort.path)
        #expect(namen.contains { $0.hasPrefix("lernende-fassung1-") }, "die Kopie liegt")
        #expect(!texte.contains { $0.contains("liegen jetzt") }, "\(texte)")
        #expect(texte.contains { $0.hasPrefix("Die Lernendendaten kommen in die neue Fassung von 2.5.0, sobald") },
                "\(texte)")
        #expect(try Data(contentsOf: ablage.lernende) == original, "nicht geschrieben")
    }

    @Test("Sitzpläne der Fassung 1 ohne bewahrtes Original: nicht umgeschrieben — erst, wenn die Kopie gelingt")
    func sitzplaeneOhneKopieNicht() throws {
        let ort = try ordner("sitzplaene-ohne-kopie")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try t.versiegeln(try inFassungEins(try Sitzplandatei.schreiben(["k-eins": sitzplan(2)])),
                                        inhalt: .sitzplaene, ziel: .ablage)
        try original.write(to: ablage.sitzplaene)
        let tor = Zaehltor(abweisen: [1, 2])
        ablage.schreibsperre = { tor.grund }

        let dienst = Sitzplandienst(ablage: ablage)
        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        #expect(befund == .umgeschrieben(1, kopie: nil), "\(befund)")
        #expect(dienst.ausstehendeKopie == "sitzplaene-fassung1-s1.json")
        #expect(try Data(contentsOf: ablage.sitzplaene) == original, "nichts darüber geschrieben")

        #expect(dienst.setzen(sitzplan(3), fuer: "k-eins") == nil)
        #expect(kopie(ort, "sitzplaene-fassung1-s1.json") == original, "erst die Kopie, dann das Schreiben")
        #expect(Sitzplandienst(ablage: ablage).oeffnen(mit: t, stempel: "s2") == .geladen(1))
    }

    @Test("Ein Archiv der Fassung 1, dessen Original sich nicht bewahren lässt, bleibt lesbar — mit Warnung (Z-BB1-08)")
    func archivOhneKopieBleibtLesbar() throws {
        let ort = try ordner("archiv-lesbar")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        try t.versiegeln(try Lernendendatei.schreiben(bestand(2)), inhalt: .lernende, ziel: .ablage)
            .write(to: ablage.lernende)
        var o = try objekt(try Archivdatei.schreiben(
            Archivbestand.leer.mitJahr(planung: try planung(), lernende: bestand(2), jetzt: Self.stempel)))
        var jahre = try #require(o["jahre"] as? [[String: Any]])
        var jahr = try #require(jahre.first?["lernende"] as? [String: Any])
        jahr["version"] = 1
        jahre[0]["lernende"] = jahr
        o["jahre"] = jahre
        let original = try t.versiegeln(try JSONSerialization.data(withJSONObject: o), inhalt: .archiv, ziel: .ablage)
        try original.write(to: ablage.archiv)

        let dienst = Lernendendienst(ablage: ablage)
        let merker = Meldungsmerker()
        dienst.melden = { text, art in merker.meldungen.append((text, art)) }
        #expect(dienst.oeffnen(mit: t, stempel: "s0") == .geladen(2))
        let tor = Tor()
        tor.schliessen()
        ablage.schreibsperre = { tor.grund }
        guard case .gelesen(let archiv, let bilanz, nil) = dienst.archivLesen(stempel: "s1") else {
            Issue.record("erwartet gelesen ohne Kopie")
            return
        }
        #expect(bilanz.umzuschreiben && archiv.jahre.count == 1, "das Archiv bleibt zu sehen")
        let warnung = "Das Archiv liegt in einer älteren Fassung, und das Original"
        #expect(merker.meldungen.contains { $0.0.hasPrefix(warnung) && $0.1 == .warnung },
                "\(merker.meldungen.map(\.0))")
        #expect(try Data(contentsOf: ablage.archiv) == original, "nichts darüber geschrieben")
    }

    @Test("Sitzpläne der Fassung 1 im Klartext neben einer versiegelten Ablage: die Frage nennt die Kopie (Z-BB1-03)")
    func klartextFassungEinsNenntKopie() throws {
        let ort = try ordner("klartext-fassung1")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        try inFassungEins(try Sitzplandatei.schreiben(["k-eins": sitzplan(2)])).write(to: ablage.sitzplaene)
        let s = Planungsspeicher(ablage: ablage)
        s.sitzplaeneOeffnen(t)
        let text = s.rueckfrage?.text ?? "keine Frage"
        let erwartet = "Die Sitzpläne stammen aus einer älteren Fassung; das Original liegt als „sitzplaene-fassung1-"
        #expect(text.contains(erwartet), "\(text)")
    }

    @Test("Die Rückfrage vor dem Aufheben zählt die Kopien vor dem Umschreiben als überholt (Z-BB1-01)")
    func aufhebenZaehltFassungEinsAlsUeberholt() throws {
        let ort = try ordner("aufheben")
        defer { aufraeumen(ort) }
        for name in ["lernende-fassung1-s1.json", "archiv-fassung1-s1.json"] {
            try Data("{}".utf8).write(to: ort.appendingPathComponent(name, isDirectory: false))
        }
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        let text = s.aufhebenRueckfrage
        #expect(text.contains("2 Rettungskopien der Lernendendaten werden dabei endgültig gelöscht"), "\(text)")
        #expect(!text.contains("überholt"), "keine als „kein überholter Stand“ genannt — \(text)")
    }
}
