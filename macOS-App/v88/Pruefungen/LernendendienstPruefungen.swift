// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Dienst der Lernendenverwaltung (v80, AP3) ─────────────────────────
// Zustände ohne Klartext (E249), Schreiben mit Rücklesen, Rettungskopien,
// Klartext unter dem Namen nie übernommen, Schreibsperre und Formwächter,
// das Archiv nur auf Abruf — und der Inhalt für die Generation eines
// Übergangs: nie entsiegelt.

@Suite("Lernendendienst: Zustände, Schreiben, Rettung, Archiv, Inhalt für den Übergang")
@MainActor
struct LernendendienstPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private static let stempel = "2026-10-03T08:00:00.000Z"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "lernende-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    private func bestand() -> Lernendenbestand {
        let s = Self.stempel
        var b = Lernendenbestand.leer(planung: "2026-08-10T09:00:00.000Z", schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-2", vorname: "Ömer", nachname: "Ünal", angelegt: s, geaendert: s, archiviert: "")]
        b.lerngruppen = [Lerngruppe(id: "g-1", name: "6a", art: .klasse, mitglieder: ["l-1", "l-2"],
                                    zeilen: [], skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        return b
    }

    private func versiegelt(_ b: Lernendenbestand, _ t: Tresor) throws -> Data {
        try t.versiegeln(try Lernendendatei.schreiben(b), inhalt: .lernende, ziel: .ablage)
    }

    private func kopf(_ url: URL) throws -> Behaelterkopf {
        try Tresor.kopfLesen(try Data(contentsOf: url))
    }

    // ── Zustände ──────────────────────────────────────────────────────────

    @Test("Zustände: aus ohne Schlüssel, zu bis zum Entsperren, Behälter danach — nie Klartext")
    func zustaende() throws {
        let ort = try ordner("zustaende")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let dienst = Lernendendienst(ablage: ablage)
        #expect(dienst.quelle == .aus && !dienst.schreibbar && dienst.bestand == nil)
        #expect(dienst.setzen(bestand()) != nil, "aus heißt: nichts nehmen")
        #expect(dienst.sperrhinweis?.contains("Verschlüsselung") == true)
        #expect(dienst.laden(stempel: "s") == .keine && dienst.quelle == .aus)
        #expect(!FileManager.default.fileExists(atPath: ablage.lernende.path))

        dienst.schliessen()
        #expect(dienst.quelle == .zu && !dienst.schreibbar && dienst.sperrhinweis?.contains("entsperren") == true)

        let t = try tresor()
        #expect(dienst.oeffnen(mit: t, stempel: "s") == .keine)
        #expect(dienst.quelle == .behaelter && dienst.schreibbar && dienst.bestand == nil && !dienst.traegtInhalt)
        let b = bestand()
        #expect(dienst.setzen(b) == nil)
        #expect(dienst.bestand == b && dienst.traegtInhalt)
        let k = try kopf(ablage.lernende)
        #expect(k.inhalt == "lernende" && k.kennung == t.kennung)
        #expect(try Lernendendatei.lesen(try t.oeffnen(kopf: k)) == b)

        let neustart = Lernendendienst(ablage: ablage)
        neustart.schliessen()
        #expect(neustart.oeffnen(mit: t, stempel: "s") == .geladen(2))
        #expect(neustart.bestand == b)

        neustart.umschalten(auf: nil)
        #expect(neustart.quelle == .aus && neustart.bestand == nil && !neustart.schreibbar)
        // Nach dem Einschalten: offen, noch ohne Datei.
        neustart.umschalten(auf: t)
        #expect(neustart.quelle == .behaelter && neustart.bestand == nil && neustart.schreibbar)
    }

    @Test("Klartext unter dem Namen wird beiseitegelegt und nie übernommen — beim Entsperren wie neben einer Klartext-Planung")
    func klartextNieUebernommen() throws {
        let ort = try ordner("klartext")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        try Lernendendatei.schreiben(bestand()).write(to: ablage.lernende)
        let dienst = Lernendendienst(ablage: ablage)
        #expect(dienst.oeffnen(mit: try tresor(), stempel: "s1") == .klartextBeiseitegelegt(rettung: "lernende-unerwartet-s1.json"))
        #expect(dienst.bestand == nil && dienst.quelle == .behaelter)
        #expect(!FileManager.default.fileExists(atPath: ablage.lernende.path))
        #expect(FileManager.default.fileExists(atPath: ort.appendingPathComponent("lernende-unerwartet-s1.json").path))

        try Lernendendatei.schreiben(bestand()).write(to: ablage.lernende)
        let ohneSchutz = Lernendendienst(ablage: ablage)
        #expect(ohneSchutz.laden(stempel: "s2") == .klartextBeiseitegelegt(rettung: "lernende-unerwartet-s2.json"))
        #expect(ohneSchutz.quelle == .aus && ohneSchutz.bestand == nil)
    }

    @Test("Fremd versiegelt, beschädigt, anderer Inhalt: beiseitegelegt; neuere Fassung: gesperrt und unangetastet")
    func beiseitelegenUndSperren() throws {
        let ort = try ordner("fremd")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let eigener = try tresor()
        let fremder = try tresor()

        try versiegelt(bestand(), fremder).write(to: ablage.lernende)
        guard case .beiseitegelegt(let grund, let rettung) = Lernendendienst(ablage: ablage).oeffnen(mit: eigener, stempel: "s1") else {
            Issue.record("erwartet beiseitegelegt")
            return
        }
        #expect(grund.contains("anderen Schlüssel") && rettung == "lernende-fremd-s1.json")

        try Data("kaputt".utf8).write(to: ablage.lernende)
        guard case .beiseitegelegt(_, let rettung2) = Lernendendienst(ablage: ablage).oeffnen(mit: eigener, stempel: "s2") else {
            Issue.record("erwartet beiseitegelegt")
            return
        }
        #expect(rettung2 == "lernende-beschaedigt-s2.json")

        let sitzplaene = try eigener.versiegeln(try Sitzplandatei.schreiben([:]), inhalt: .sitzplaene, ziel: .ablage)
        try sitzplaene.write(to: ablage.lernende)
        guard case .beiseitegelegt(let grund3, let rettung3) = Lernendendienst(ablage: ablage).oeffnen(mit: eigener, stempel: "s3") else {
            Issue.record("erwartet beiseitegelegt")
            return
        }
        #expect(grund3.contains("sitzplaene") && rettung3 == "lernende-beschaedigt-s3.json")

        var neuer = try #require(JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(bestand())) as? [String: Any])
        neuer["version"] = 2
        let neuere = try eigener.versiegeln(try JSONSerialization.data(withJSONObject: neuer), inhalt: .lernende, ziel: .ablage)
        try neuere.write(to: ablage.lernende)
        let gesperrt = Lernendendienst(ablage: ablage)
        guard case .gesperrt(let grund4) = gesperrt.oeffnen(mit: eigener, stempel: "s4") else {
            Issue.record("erwartet gesperrt")
            return
        }
        #expect(grund4.contains("aktualisieren") && !gesperrt.schreibbar)
        #expect(gesperrt.setzen(bestand()) != nil)
        #expect(try Data(contentsOf: ablage.lernende) == neuere, "eine neuere Fassung bleibt unangetastet")
    }

    @Test("Verlust beim Lesen: gemeldet, das Original als Rettungskopie bewahrt, bevor geschrieben wird")
    func verlustBewahrt() throws {
        let ort = try ordner("verlust")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        var roh = try #require(JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(bestand())) as? [String: Any])
        var gruppen = try #require(roh["lerngruppen"] as? [[String: Any]])
        gruppen[0]["mitglieder"] = ["l-1", "l-2", "l-9"]
        roh["lerngruppen"] = gruppen
        let original = try t.versiegeln(try JSONSerialization.data(withJSONObject: roh), inhalt: .lernende, ziel: .ablage)
        try original.write(to: ablage.lernende)
        let dienst = Lernendendienst(ablage: ablage)
        guard case .bereinigt(let anzahl, let bilanz, let kopie) = dienst.oeffnen(mit: t, stempel: "s1") else {
            Issue.record("erwartet bereinigt")
            return
        }
        #expect(anzahl == 2 && bilanz.verworfeneMitglieder == 1 && kopie == "lernende-bereinigt-s1.json")
        #expect(try Data(contentsOf: ort.appendingPathComponent("lernende-bereinigt-s1.json")) == original)
        #expect(dienst.setzen(bestand()) == nil)
        #expect(try Data(contentsOf: ort.appendingPathComponent("lernende-bereinigt-s1.json")) == original)
    }

    @Test("Schreibsperre und Formwächter: Nichts geht über die Datei, der Grund steht in ungesichert; nachholen schreibt")
    func sperreUndWaechter() throws {
        let ort = try ordner("sperre")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let dienst = Lernendendienst(ablage: ablage)
        _ = dienst.oeffnen(mit: t, stempel: "s")
        #expect(dienst.setzen(bestand()) == nil)
        let vorher = try Data(contentsOf: ablage.lernende)

        dienst.schreibsperre = { "ein Übergang ist offen" }
        var neu = bestand()
        neu.lernende[0].vorname = "Anne"
        #expect(dienst.setzen(neu)?.contains("Übergang") == true && dienst.ungesichert != nil)
        #expect(try Data(contentsOf: ablage.lernende) == vorher)
        #expect(dienst.bestand == neu, "der Stand gilt für die Sitzung")
        dienst.schreibsperre = nil
        dienst.nachholen()
        #expect(try dienst.ungesichert == nil && (Lernendendatei.lesen(try t.oeffnen(kopf: try kopf(ablage.lernende)))) == neu)

        // Ein Behälter unter fremdem Schlüssel liegt im Weg: Der Formwächter sperrt.
        let fremd = try versiegelt(bestand(), try tresor())
        try fremd.write(to: ablage.lernende)
        #expect(dienst.setzen(bestand())?.contains("anderen Schlüssel") == true)
        #expect(try Data(contentsOf: ablage.lernende) == fremd)
    }

    // ── Das Archiv: nur auf Abruf ─────────────────────────────────────────

    private func archiv() throws -> Archivbestand {
        let p = Planung.leer(titel: "2025/26", start: try #require(Tag(iso: "2025-08-04")), wochen: 4, basis: "",
                             klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        return Archivbestand.leer.mitJahr(planung: p, lernende: bestand(), jetzt: Self.stempel)
    }

    @Test("Archiv: ohne Datei leer; gesetzt als Behälter mit Inhalt archiv; zurückgelesen gleich")
    func archivSetzenUndLesen() throws {
        let ort = try ordner("archiv")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let dienst = Lernendendienst(ablage: ablage)
        if case .nichtLesbar = dienst.archivLesen(stempel: "s") {} else {
            Issue.record("ohne Schlüssel ist das Archiv nicht zu lesen")
        }
        _ = dienst.oeffnen(mit: t, stempel: "s")
        guard case .gelesen(let leer, _, _) = dienst.archivLesen(stempel: "s") else {
            Issue.record("erwartet gelesen")
            return
        }
        #expect(leer.jahre.isEmpty && !FileManager.default.fileExists(atPath: ablage.archiv.path))

        let a = try archiv()
        #expect(dienst.archivSetzen(a, stempel: "s") == nil)
        #expect(try kopf(ablage.archiv).inhalt == "archiv")
        guard case .gelesen(let gelesen, let bilanz, _) = Lernendendienst(ablage: ablage).mitOffenemSchluessel(t).archivLesen(stempel: "s") else {
            Issue.record("erwartet gelesen")
            return
        }
        #expect(try bilanz.istLeer && Archivdatei.schreiben(gelesen) == Archivdatei.schreiben(a))
    }

    @Test("Archiv unlesbar: Unangetastet, und kein neues Archiv geht darüber")
    func archivUnlesbar() throws {
        let ort = try ordner("archiv-kaputt")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let dienst = Lernendendienst(ablage: ablage)
        _ = dienst.oeffnen(mit: t, stempel: "s")
        let kaputt = try t.versiegeln(Data("{\"typ\":\"unterrichtsplanung-archiv\",\"version\":1,\"jahre\":{}}".utf8),
                                      inhalt: .archiv, ziel: .ablage)
        try kaputt.write(to: ablage.archiv)
        guard case .nichtLesbar(let grund) = dienst.archivLesen(stempel: "s") else {
            Issue.record("erwartet nicht lesbar")
            return
        }
        #expect(grund.contains("beschädigt"))
        #expect(dienst.archivSetzen(try archiv(), stempel: "s")?.contains("beschädigt") == true)
        #expect(try Data(contentsOf: ablage.archiv) == kaputt)
    }

    @Test("Archiv abseits des Hauptstrangs lesen (AP9): dasselbe wie auf dem Hauptstrang — leer, gelesen, nicht lesbar")
    func archivAsynchron() async throws {
        let ort = try ordner("archiv-asynchron")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let dienst = Lernendendienst(ablage: ablage)
        let ohneSchluessel = await dienst.archivLesenAsynchron(stempel: "s")
        #expect(ohneSchluessel == dienst.archivLesen(stempel: "s"), "ohne Schlüssel: nicht lesbar")
        _ = dienst.oeffnen(mit: t, stempel: "s")
        #expect(await dienst.archivLesenAsynchron(stempel: "s") == .gelesen(.leer, .init(), kopie: nil))
        #expect(dienst.archivGroesse() == nil, "ohne Datei keine Größe")
        let a = try archiv()
        #expect(dienst.archivSetzen(a, stempel: "s") == nil)
        let asynchron = await dienst.archivLesenAsynchron(stempel: "s")
        #expect(asynchron == dienst.archivLesen(stempel: "s"))
        guard case .gelesen(let gelesen, _, _) = asynchron else {
            Issue.record("erwartet gelesen")
            return
        }
        #expect(try Archivdatei.schreiben(gelesen) == Archivdatei.schreiben(a))
        #expect(dienst.archivGroesse() == (try Data(contentsOf: ablage.archiv)).count)
        try Data("kaputt".utf8).write(to: ablage.archiv)
        if case .nichtLesbar = await dienst.archivLesenAsynchron(stempel: "s") {} else {
            Issue.record("erwartet nicht lesbar")
        }
    }

    @Test("B71: Ein Archiv unter fremdem Schlüssel, mit anderem Inhalt oder im Klartext wird beim Entsperren beiseitegelegt — es hält keinen Übergang auf")
    func archivkopfBeimEntsperren() throws {
        let ort = try ordner("archivkopf")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let eigener = try tresor()
        let fremder = try tresor()
        let dienst = Lernendendienst(ablage: ablage)
        _ = dienst.oeffnen(mit: eigener, stempel: "s0")
        #expect(dienst.archivkopfPruefen(stempel: "s0") == nil, "ohne Archiv nichts zu tun")

        let a = try archiv()
        try fremder.versiegeln(try Archivdatei.schreiben(a), inhalt: .archiv, ziel: .ablage).write(to: ablage.archiv)
        #expect(dienst.archivkopfPruefen(stempel: "s1") == "archiv-fremd-s1.json")
        #expect(!FileManager.default.fileExists(atPath: ablage.archiv.path))
        #expect(try dienst.archivInhalt(unter: try tresor()) == nil, "nichts mehr im Weg des Übergangs")

        try eigener.versiegeln(Data("{}".utf8), inhalt: .sitzplaene, ziel: .ablage).write(to: ablage.archiv)
        #expect(dienst.archivkopfPruefen(stempel: "s2") == "archiv-beschaedigt-s2.json")
        try Archivdatei.schreiben(a).write(to: ablage.archiv)
        #expect(dienst.archivkopfPruefen(stempel: "s3") == "archiv-unerwartet-s3.json")

        // Ein eigenes Archiv bleibt, wo es ist.
        #expect(dienst.archivSetzen(a, stempel: "s4") == nil)
        #expect(dienst.archivkopfPruefen(stempel: "s4") == nil && FileManager.default.fileExists(atPath: ablage.archiv.path))
    }

    // ── Der Inhalt für die Generation eines Übergangs ─────────────────────

    @Test("Inhalt für den Übergang: unter dem neuen Schlüssel; entsiegelt nie — ohne Inhalt entfällt die Datei")
    func inhaltFuerDenUebergang() throws {
        let ort = try ordner("uebergang")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let alt = try tresor()
        let neu = try tresor()
        let dienst = Lernendendienst(ablage: ablage)
        _ = dienst.oeffnen(mit: alt, stempel: "s")
        #expect(try dienst.inhalt(unter: neu) == nil, "ohne Jahresdatei keine Datei")
        #expect(try dienst.archivInhalt(unter: neu) == nil, "ohne Archiv keine Datei")

        #expect(dienst.setzen(bestand()) == nil)
        let a = try archiv()
        #expect(dienst.archivSetzen(a, stempel: "s") == nil)
        let jahresdatei = try #require(try dienst.inhalt(unter: neu))
        let k = try Tresor.kopfLesen(jahresdatei)
        #expect(k.kennung == neu.kennung && k.inhalt == "lernende")
        #expect(try Lernendendatei.lesen(try neu.oeffnen(kopf: k)) == bestand())
        let archivdaten = try #require(try dienst.archivInhalt(unter: neu))
        let ka = try Tresor.kopfLesen(archivdaten)
        #expect(ka.kennung == neu.kennung && ka.inhalt == "archiv")
        #expect(try Archivdatei.schreiben(try Archivdatei.lesen(try neu.oeffnen(kopf: ka))) == (try Archivdatei.schreiben(a)))

        #expect(throws: Uebergangsfehler.self, "mit Inhalt nie entsiegeln") { try dienst.inhalt(unter: nil) }
        #expect(throws: Uebergangsfehler.self, "ein Archiv nie entsiegeln") { try dienst.archivInhalt(unter: nil) }

        // Eine leere Jahresdatei entfällt beim Aufheben.
        var leer = bestand()
        leer.lernende = []
        leer.lerngruppen = []
        #expect(dienst.setzen(leer) == nil && !dienst.traegtInhalt)
        #expect(try dienst.inhalt(unter: nil) == nil)

        dienst.umschalten(auf: neu)
        #expect(dienst.quelle == .behaelter)
        dienst.schliessen()
        #expect(throws: Uebergangsfehler.self, "zu: Die Datei gehört nicht in die Generation") { try dienst.inhalt(unter: neu) }
    }
}

extension Lernendendienst {
    /// Für die Prüfungen: ein frischer Dienst, entsperrt mit `tresor`.
    fileprivate func mitOffenemSchluessel(_ tresor: Tresor) -> Lernendendienst {
        schliessen()
        _ = oeffnen(mit: tresor, stempel: "p")
        return self
    }
}
