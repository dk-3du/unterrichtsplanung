// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die Sitzpläne nach dem „Übernehmen“ (v84, E367, E390) ─────────────────
// Wer eine Lerngruppe verlässt, verlässt die Sitzpläne ihrer Zeilen — der Tisch geht samt Namen, mit Warnung
// (E367, E494); ein geänderter Name folgt an gebundenen Tischen, wo noch der übernommene steht (E390). Nur in diese
// Richtung: Der Sitzplan ändert die Lernendenverwaltung nie. Die Tische derer, die bleiben, und fremde Tische
// bleiben; gesperrte Pläne bleiben unangetastet, die Meldung sagt es. Die Frage beim Beenden nennt die Folgen (E495).

@Suite("Sitzpläne nach dem Übernehmen: verlassene Lerngruppe, nachgeführte Namen")
@MainActor
struct SitzplanfolgenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private let jetzt = "2026-09-01T08:00:00.000Z"

    private struct Stand {
        let s: Planungsspeicher
        let ablage: URL
        /// Die Zeilen „6a · Biologie“, „6b · Biologie“ und die Klassenleitung (ohne Gruppe).
        let k6a: String
        let k6b: String
        let kl = "k-kl"
        /// „6a“ an k6a gebunden (Anna, Ben), „6b“ an k6b (Cem, Dora ohne Tisch), „AG“ ohne Zeile (Anna).
        let g6a: String
        let g6b: String
        let ag: String
        let anna: String
        let ben: String
        let cem: String
        let dora: String
    }

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "sitzplanfolgen-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// Eine Planung mit drei Zeilen, verschlüsselt; drei Gruppen, zwei gebunden; Sitzpläne für alle drei Zeilen:
    /// k6a mit Anna, Ben und einem ungebundenen Tisch „Gast“, k6b mit Cem, die Klassenleitung mit Anna.
    private func stand(_ name: String) async throws -> Stand {
        let ablage = try ordner(name)
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 10,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie"), ("6b", "Biologie")]),
                             fachfarben: [:])
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.id = "k-kl"
        p.klassen += [leitung]
        p.farbenVervollstaendigen()
        s.planung = p
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let k6a = try #require(p.klassen.first { $0.name == "6a" }).id
        let k6b = try #require(p.klassen.first { $0.name == "6b" }).id

        let a = try #require(s.lernendenEntwurfBeginnen())
        let t = a.erstellt
        let (b, g6a) = try #require(a.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: t))
        let (c, g6b) = try #require(b.mitNeuerGruppe(name: "6b", art: .klasse, jetzt: t))
        let (d, ag) = try #require(c.mitNeuerGruppe(name: "AG", art: .kurs, jetzt: t))
        let e = d.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: g6a, jetzt: t).bestand
        let f = e.mitPersonen(Namenszeilen.lesen("Celik, Cem\nDietz, Dora").namen, inGruppe: g6b, jetzt: t).bestand
        let anna = try #require(f.lernende.first { $0.nachname == "Abel" }).id
        let ben = try #require(f.lernende.first { $0.nachname == "Bauer" }).id
        let cem = try #require(f.lernende.first { $0.nachname == "Celik" }).id
        let dora = try #require(f.lernende.first { $0.nachname == "Dietz" }).id
        let g = try #require(f.mitMitglied(anna, inGruppe: ag, jetzt: t))
        #expect(s.lernendenUebernehmen(g) == nil)
        #expect(s.lerngruppeBinden(g6a, an: k6a) == nil && s.lerngruppeBinden(g6b, an: k6b) == nil)

        #expect(s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: k6a, lernende: [
            .init(name: "Anna Abel", lernender: anna), .init(name: "Ben Bauer", lernender: ben),
            .init(name: "Gast", lernender: "")]), fuer: k6a) == nil)
        #expect(s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: k6b, lernende: [
            .init(name: "Cem Celik", lernender: cem)]), fuer: k6b) == nil)
        #expect(s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: "k-kl", lernende: [
            .init(name: "Anna Abel", lernender: anna)]), fuer: "k-kl") == nil)
        return Stand(s: s, ablage: ablage, k6a: k6a, k6b: k6b, g6a: g6a, g6b: g6b, ag: ag, anna: anna, ben: ben, cem: cem,
                     dora: dora)
    }

    private func tische(_ s: Planungsspeicher, _ klasse: String) -> [String] {
        (s.sitzplaene.plan(fuer: klasse)?.tische ?? []).map { "\($0.name)|\($0.lernender)" }
    }

    /// So auf der Platte — ein frischer Dienst liest die Datei.
    private func aufDerPlatte(_ st: Stand, _ klasse: String) throws -> [String] {
        let frisch = Sitzplandienst(ablage: Ablage(ordner: st.ablage))
        _ = frisch.oeffnen(mit: try #require(st.s.tresor), stempel: "probe")
        return (frisch.plan(fuer: klasse)?.tische ?? []).map { "\($0.name)|\($0.lernender)" }
    }

    private func neu(_ s: Planungsspeicher, seit vorher: Int) -> [Meldung] { Array(s.meldungen.dropFirst(vorher)) }

    private static let einePersonEinPlan = "Eine Person wurde mit dem Verlassen ihrer Lerngruppe auch aus dem Sitzplan "
        + "entfernt."

    @Test("Aus der Lerngruppe genommen: Der Tisch geht aus dem Sitzplan der gebundenen Zeile, mit Warnung (E367, E494)")
    func herausgenommen() async throws {
        let st = try await stand("heraus")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let b = try #require(st.s.lernende.bestand)
        let stempel6b = st.s.sitzplaene.plan(fuer: st.k6b)?.geaendert
        let stempelKl = st.s.sitzplaene.plan(fuer: st.kl)?.geaendert
        let vorher = st.s.meldungen.count
        #expect(st.s.lernendenUebernehmen(b.ohneMitglied(st.anna, ausGruppe: st.g6a, jetzt: jetzt)) == nil)
        #expect(tische(st.s, st.k6a) == ["Ben Bauer|\(st.ben)", "Gast|"], "Ben und der Gast bleiben")
        #expect(tische(st.s, st.kl) == ["Anna Abel|\(st.anna)"], "die Klassenleitung trägt keine Gruppe: Annas Tisch bleibt")
        #expect(tische(st.s, st.k6b) == ["Cem Celik|\(st.cem)"])
        #expect(st.s.sitzplaene.plan(fuer: st.k6b)?.geaendert == stempel6b
                && st.s.sitzplaene.plan(fuer: st.kl)?.geaendert == stempelKl, "unberührte Pläne behalten ihren Stempel")
        let meldungen = neu(st.s, seit: vorher)
        #expect(meldungen.map(\.text) == [Self.einePersonEinPlan] && meldungen.first?.art == .warnung,
                "genau eine Meldung, eine Warnung — keine zum Nachführen: \(meldungen.map(\.text))")
        #expect(try aufDerPlatte(st, st.k6a) == ["Ben Bauer|\(st.ben)", "Gast|"], "so auf der Platte")
    }

    @Test("Umgezogen: Der Tisch geht nur aus dem Sitzplan der alten Lerngruppe; in die neue kommt keiner (E367)")
    func umgezogen() async throws {
        let st = try await stand("umzug")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let b = try #require(st.s.lernende.bestand)
        let umzug = try #require(b.mitUmzug(st.anna, von: st.g6a, nach: st.g6b, jetzt: jetzt))
        let vorher = st.s.meldungen.count
        #expect(st.s.lernendenUebernehmen(umzug) == nil)
        #expect(tische(st.s, st.k6a) == ["Ben Bauer|\(st.ben)", "Gast|"])
        #expect(tische(st.s, st.k6b) == ["Cem Celik|\(st.cem)"], "kein Tisch von selbst — den setzt der Sitzplan")
        #expect(tische(st.s, st.kl) == ["Anna Abel|\(st.anna)"])
        #expect(neu(st.s, seit: vorher).map(\.text) == [Self.einePersonEinPlan])
    }

    @Test("Zwei Personen aus einem Plan: gezählt nach Personen, der Ort nach der Zahl der Pläne")
    func zweiPersonen() async throws {
        let st = try await stand("zwei")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let b = try #require(st.s.lernende.bestand)
        let vorher = st.s.meldungen.count
        #expect(st.s.lernendenUebernehmen(b.ohneMitglied(st.anna, ausGruppe: st.g6a, jetzt: jetzt)
            .ohneMitglied(st.ben, ausGruppe: st.g6a, jetzt: jetzt)) == nil)
        #expect(tische(st.s, st.k6a) == ["Gast|"])
        #expect(neu(st.s, seit: vorher).map(\.text)
                == ["2 Personen wurden mit dem Verlassen ihrer Lerngruppe auch aus dem Sitzplan entfernt."])
    }

    @Test("Gegenprobe gegen Übereifer: eine Gruppe ohne Zeile verlassen, nichts sonst — die Pläne bleiben bytegleich, keine Meldung")
    func uebereifer() async throws {
        let st = try await stand("uebereifer")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let datei = Ablage(ordner: st.ablage).sitzplaene
        let roh = try Data(contentsOf: datei)
        let b = try #require(st.s.lernende.bestand)
        let vorher = st.s.meldungen.count
        let ohne = b.ohneMitglied(st.anna, ausGruppe: st.ag, jetzt: jetzt)
            .mitGruppe(st.g6b, name: "6b neu", jetzt: jetzt)
        #expect(st.s.lernendenUebernehmen(ohne) == nil)
        #expect(try Data(contentsOf: datei) == roh, "die Pläne bleiben, wie sie sind")
        #expect(!neu(st.s, seit: vorher).contains { $0.text.contains("Sitzplan") }, "\(neu(st.s, seit: vorher).map(\.text))")
    }

    @Test("Folgen ohne getroffenen Tisch (Z-AT2-01): Dora verlässt 6b und bekommt einen Rufnamen, hat aber keinen Tisch — bytegleich, keine Meldung")
    func folgenOhneTisch() async throws {
        let st = try await stand("ohne-tisch")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let datei = Ablage(ordner: st.ablage).sitzplaene
        let roh = try Data(contentsOf: datei)
        let b = try #require(st.s.lernende.bestand)
        let neuerStand = b.ohneMitglied(st.dora, ausGruppe: st.g6b, jetzt: jetzt)
            .mitPerson(st.dora, vorname: "Dora", nachname: "Dietz", rufname: "Doro", jetzt: jetzt)
        let folgen = Sitzplanfolgen(vorher: b, nachher: neuerStand, planung: st.s.planung?.erstellt)
        #expect(!folgen.istLeer, "Folgen gibt es")
        let vorher = st.s.meldungen.count
        #expect(st.s.lernendenUebernehmen(neuerStand) == nil)
        #expect(try Data(contentsOf: datei) == roh, "kein Plan gestempelt, nichts geschrieben")
        #expect(!neu(st.s, seit: vorher).contains { $0.text.contains("Sitzplan") }, "\(neu(st.s, seit: vorher).map(\.text))")
    }

    @Test("Eine Bindung an eine Zeile einer anderen Planung zählt nicht (Z-AT2-08)")
    func anderePlanung() async throws {
        let st = try await stand("andere-planung")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let b = try #require(st.s.lernende.bestand)
        // 6a trägt zusätzlich eine Bindung an die Zeile k6b einer anderen Planung; Anna sitzt auch in k6b.
        let fremd = b.mitBindung(st.g6a, an: Zeilenbindung(planung: "2020-01-01T00:00:00.000Z", klasseId: st.k6b),
                                 jetzt: jetzt)
        #expect(st.s.lernendenUebernehmen(fremd) == nil)
        #expect(st.s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: st.k6b, lernende: [
            .init(name: "Cem Celik", lernender: st.cem), .init(name: "Anna Abel", lernender: st.anna)]), fuer: st.k6b) == nil)
        let c = try #require(st.s.lernende.bestand)
        #expect(st.s.lernendenUebernehmen(c.ohneMitglied(st.anna, ausGruppe: st.g6a, jetzt: jetzt)) == nil)
        #expect(tische(st.s, st.k6a) == ["Ben Bauer|\(st.ben)", "Gast|"])
        #expect(tische(st.s, st.k6b) == ["Cem Celik|\(st.cem)", "Anna Abel|\(st.anna)"], "k6b gehört hier 6b")
    }

    @Test("Aus einer archivierten Lerngruppe genommen: Der Tisch geht auch dann (E493 b)")
    func archivierteGruppe() async throws {
        let st = try await stand("archiviert")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let b = try #require(st.s.lernende.bestand).mitArchivierterGruppe(st.g6a, jetzt: jetzt)
        #expect(st.s.lernendenUebernehmen(b) == nil)
        let c = try #require(st.s.lernende.bestand)
        #expect(st.s.lernendenUebernehmen(c.ohneMitglied(st.anna, ausGruppe: st.g6a, jetzt: jetzt)) == nil)
        #expect(tische(st.s, st.k6a) == ["Ben Bauer|\(st.ben)", "Gast|"])
    }

    @Test("Sitzpläne gesperrt: Die Datei bleibt, wie sie ist — die Meldung sagt es")
    func gesperrt() async throws {
        let st = try await stand("gesperrt")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let tresor = try #require(st.s.tresor)
        let datei = Ablage(ordner: st.ablage).sitzplaene
        try tresor.versiegeln(Data("{\"typ\":\"unterrichtsplanung-sitzplaene\",\"version\":9,\"plaene\":{}}".utf8),
                              inhalt: .sitzplaene, ziel: .ablage).write(to: datei)
        st.s.sitzplaeneOeffnen(tresor)
        #expect(!st.s.sitzplaene.schreibbar, "gesperrt")
        let roh = try Data(contentsOf: datei)
        let b = try #require(st.s.lernende.bestand)
        let vorher = st.s.meldungen.count
        #expect(st.s.lernendenUebernehmen(b.ohneMitglied(st.anna, ausGruppe: st.g6a, jetzt: jetzt)) == nil)
        #expect(try Data(contentsOf: datei) == roh, "unangetastet")
        let text = "Die Sitzpläne sind gerade nicht verfügbar — Anpassungen in der Lernendenverwaltung konnten nicht "
            + "übertragen werden."
        #expect(neu(st.s, seit: vorher).contains { $0.text == text && $0.art == .warnung },
                "\(neu(st.s, seit: vorher).map(\.text))")
    }

    @Test("Rufname gesetzt: Gebundene Tische mit dem übernommenen Namen folgen, ein von Hand geänderter bleibt (E390)")
    func namenNachgefuehrt() async throws {
        let st = try await stand("namen")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        // Ben heißt am Tisch von Hand „Benni“ (E284).
        var plan = try #require(st.s.sitzplaene.plan(fuer: st.k6a))
        let stelle = try #require(plan.tische.firstIndex { $0.lernender == st.ben })
        plan.tische[stelle].name = "Benni"
        #expect(st.s.sitzplaene.setzen(plan, fuer: st.k6a) == nil)
        let b = try #require(st.s.lernende.bestand)
        let neuerStand = b.mitPerson(st.anna, vorname: "Anna", nachname: "Abel", rufname: "Anni", jetzt: jetzt)
            .mitPerson(st.ben, vorname: "Ben", nachname: "Baumann", rufname: "", jetzt: jetzt)
        let vorher = st.s.meldungen.count
        #expect(st.s.lernendenUebernehmen(neuerStand) == nil)
        #expect(tische(st.s, st.k6a) == ["Anni Abel|\(st.anna)", "Benni|\(st.ben)", "Gast|"])
        #expect(tische(st.s, st.kl) == ["Anni Abel|\(st.anna)"])
        // Eine Namensänderung (Anna), an Tischen zweier Pläne; Bens Name steht an keinem Tisch.
        let meldungen = neu(st.s, seit: vorher)
        #expect(meldungen.map(\.text) == ["Die Namensänderung wurde auch auf die Sitzpläne übertragen."]
                && meldungen.first?.art == .hinweis, "\(meldungen.map(\.text))")
        #expect(try aufDerPlatte(st, st.kl) == ["Anni Abel|\(st.anna)"], "so auf der Platte")
    }

    @Test("Verlassen und umbenannt im selben Übernehmen: erst entfernt, dann nachgeführt — je richtig gezählt")
    func beides() async throws {
        let st = try await stand("beides")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let b = try #require(st.s.lernende.bestand)
        let neuerStand = b.ohneMitglied(st.anna, ausGruppe: st.g6a, jetzt: jetzt)
            .mitPerson(st.anna, vorname: "Anna", nachname: "Abel", rufname: "Anni", jetzt: jetzt)
        let vorher = st.s.meldungen.count
        #expect(st.s.lernendenUebernehmen(neuerStand) == nil)
        #expect(tische(st.s, st.k6a) == ["Ben Bauer|\(st.ben)", "Gast|"])
        #expect(tische(st.s, st.kl) == ["Anni Abel|\(st.anna)"])
        #expect(neu(st.s, seit: vorher).map(\.text)
                == [Self.einePersonEinPlan, "Die Namensänderung wurde auch auf den Sitzplan übertragen."])
    }

    @Test("Die Frage beim Beenden nennt die Folgen, ohne etwas zu schreiben (E495)")
    func beendenFrage() async throws {
        let st = try await stand("beenden")
        defer { try? FileManager.default.removeItem(at: st.ablage) }
        let datei = Ablage(ordner: st.ablage).sitzplaene
        let roh = try Data(contentsOf: datei)
        let b = try #require(st.s.lernende.bestand)
        let geaendert = b.ohneMitglied(st.anna, ausGruppe: st.g6a, jetzt: jetzt)
            .ohneMitglied(st.ben, ausGruppe: st.g6a, jetzt: jetzt)
            .mitPerson(st.anna, vorname: "Anna", nachname: "Abel", rufname: "Anni", jetzt: jetzt)
        st.s.lernendenblattUebernimmt({ _ in }, griff: Lernendenblattgriff(aenderungen: { geaendert }))
        st.s.offenerDialog = .lernende  // Die Frage hängt am Blatt (E418).
        let gefragt = st.s.lernendenblattBeimBeendenFragen(dann: {})
        #expect(gefragt)
        let frage = try #require(st.s.rueckfrage)
        #expect(frage.text.hasSuffix("\n\nBeim Übernehmen werden 2 Personen aus dem Sitzplan entfernt, weil sie ihre "
                                     + "Lerngruppe verlassen haben; in einem Sitzplan wird eine Namensänderung vorgenommen."),
                Comment(rawValue: frage.text))
        #expect(try Data(contentsOf: datei) == roh, "gefragt, nicht geschrieben")
        st.s.rueckfrageBeantworten(false)
        st.s.lernendenblattGibtAb()
    }

    @Test("Die Wortlaute je Zahl und Ort — Personen und Namensänderungen, Plan oder Pläne")
    func wortlaute() {
        typealias F = Sitzplandienst.Folgen
        let eins = F(entfernt: ["a"], entferntIn: ["k1"], nachgefuehrt: ["a"], nachgefuehrtIn: ["k1"])
        let viele = F(entfernt: ["a", "b", "c"], entferntIn: ["k1", "k2"], nachgefuehrt: ["a", "b"], nachgefuehrtIn: ["k1", "k2"])
        let s = Planungsspeicher.self
        #expect(s.sitzplanfolgenEntfernt(F()) == nil && s.sitzplanfolgenNachgefuehrt(F()) == nil
                && s.sitzplanfolgenAbsatz(F()) == nil)
        #expect(s.sitzplanfolgenEntfernt(eins) == Self.einePersonEinPlan)
        #expect(s.sitzplanfolgenEntfernt(F(entfernt: ["a"], entferntIn: ["k1", "k2"]))
                == "Eine Person wurde mit dem Verlassen ihrer Lerngruppe auch aus den Sitzplänen entfernt.")
        #expect(s.sitzplanfolgenEntfernt(viele)
                == "3 Personen wurden mit dem Verlassen ihrer Lerngruppe auch aus den Sitzplänen entfernt.")
        #expect(s.sitzplanfolgenNachgefuehrt(eins) == "Die Namensänderung wurde auch auf den Sitzplan übertragen.")
        #expect(s.sitzplanfolgenNachgefuehrt(viele) == "Die 2 Namensänderungen wurden auch auf die Sitzpläne übertragen.")
        #expect(s.sitzplanfolgenAbsatz(F(entfernt: ["a"], entferntIn: ["k1"]))
                == "Beim Übernehmen wird eine Person aus dem Sitzplan entfernt, weil sie ihre Lerngruppe verlassen hat.")
        #expect(s.sitzplanfolgenAbsatz(F(nachgefuehrt: ["a"], nachgefuehrtIn: ["k1"]))
                == "Beim Übernehmen wird in einem Sitzplan eine Namensänderung vorgenommen.")
        #expect(s.sitzplanfolgenAbsatz(viele)
                == "Beim Übernehmen werden 3 Personen aus den Sitzplänen entfernt, weil sie ihre Lerngruppe verlassen "
                   + "haben; in den Sitzplänen werden 2 Namensänderungen vorgenommen.")
    }

    @Test("Hilfetext und Bedienungshilfe am Tisch nennen den Rufnamen (E390)")
    func tischhilfe() throws {
        let leer = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: "2026-08-01T00:00:00.000Z")
        let (b, g) = try #require(leer.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: leer.erstellt))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nBauer, Ben").namen, inGruppe: g, jetzt: leer.erstellt).bestand
        let anna = try #require(c.lernende.first { $0.nachname == "Abel" }).id
        let ben = try #require(c.lernende.first { $0.nachname == "Bauer" }).id
        let v = Lernendenverzeichnis(c.mitPerson(anna, vorname: "Anna", nachname: "Abel", rufname: "Anni", jetzt: leer.erstellt))
        #expect(SitzplanDialog.personenname(anna, in: v) == "Abel, Anna (Anni)")
        #expect(SitzplanDialog.personenname(ben, in: v) == "Bauer, Ben")
        #expect(SitzplanDialog.personenname("l-unbekannt", in: v) == nil && SitzplanDialog.personenname(anna, in: nil) == nil)
    }
}

// ── Die Personensuche der Termine (v84, E360, E481) ───────────────────────

@Suite("Terminsuche im Vorhaben-Blatt: dieselbe Regel wie die Suche im Blatt „Lernende“")
struct TerminsuchePruefungen {

    private func verzeichnis(_ namen: String) throws -> (Lernendenverzeichnis, Lernendenbestand, String) {
        let leer = Lernendenbestand.leer(planung: "p", schuljahr: "2026/27", jetzt: "2026-08-01T00:00:00.000Z")
        let (b, g) = try #require(leer.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: leer.erstellt))
        let c = b.mitPersonen(Namenszeilen.lesen(namen).namen, inGruppe: g, jetzt: leer.erstellt).bestand
        return (Lernendenverzeichnis(c), c, g)
    }

    @Test("Nachname, Vorname, Rufname; Groß/Klein und Akzente unerheblich; Wortteile in jeder Folge (E360)")
    func regel() throws {
        let (_, c, _) = try verzeichnis("Müller, Anna\nAbel, Ben\nÇelik, Cem")
        let anna = try #require(c.lernende.first { $0.vorname == "Anna" }).id
        let v = Lernendenverzeichnis(c.mitPerson(anna, vorname: "Anna", nachname: "Müller", rufname: "Anni",
                                                 jetzt: c.erstellt))
        func namen(_ suche: String) -> [String] {
            VorhabenDialog.treffer(suche, in: v, ausser: [], zuerst: []).map(\.vorname)
        }
        #expect(namen("muller") == ["Anna"], "ohne Akzent")
        #expect(namen("ANNI") == ["Anna"], "der Rufname")
        #expect(namen("anna mül") == ["Anna"], "Vorname vor Nachname, Wortteile")
        #expect(namen("celik") == ["Cem"])
        #expect(namen("abel, b") == ["Ben"])
        #expect(namen("ab") == ["Ben"])
    }

    @Test("Die Lerngruppe der Zeile zuerst, höchstens acht, ohne die schon Gewählten")
    func folge() throws {
        let liste = (1...10).map { "Abel\($0), Anna\($0)" }.joined(separator: "\n")
        let (v, c, _) = try verzeichnis(liste)
        let ids = c.lernende.map(\.id)
        let zuerst = Set([ids[9]])
        let treffer = VorhabenDialog.treffer("abel", in: v, ausser: [ids[0]], zuerst: zuerst)
        #expect(treffer.count == 8)
        #expect(treffer.first?.id == ids[9], "das Mitglied der Zeile vorn")
        #expect(!treffer.contains { $0.id == ids[0] }, "schon gewählt")
        #expect(VorhabenDialog.treffer("  ", in: v, ausser: [], zuerst: []).isEmpty, "leer: nichts")
    }
}
