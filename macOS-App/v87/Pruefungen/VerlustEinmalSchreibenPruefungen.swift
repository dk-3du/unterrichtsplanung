// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

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
    var texte: [String] = []
}

// ── Verlust: einmal schreiben, eine Meldung (B100, B103, E456 a) ──────────
// Die Jahresdatei bewahrte bei reinem Verlust das Original, schrieb aber
// nicht — jeder Start las erneut mit Verlust und legte eine neue Kopie an.
// Wie bei ersetzten Kennungen (B93, E419) wird sie nun einmal geschrieben.
// Die Sitzpläne schrieben bei Verlust und älterer Hülle schon; misslang dabei
// die Kopie, kamen zwei Meldungen, und der Befund nannte nur die Kopie aus
// dem ersten Versuch — nun wie im Lernendendienst (Z-AU6-01, Z-AU6-02). Seit
// E467 werden auch sie bei reinem Verlust einmal geschrieben (Z-AV5-01).

@Suite("Verlust: die Jahresdatei einmal geschrieben, die Sitzpläne mit einer Meldung und der gelungenen Kopie (B100, B103, E456)")
@MainActor
struct VerlustEinmalSchreibenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private let zweite = "Ein zweiter Satz, den man behält"
    private static let stempel = "2026-10-03T08:00:00.000Z"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "verlust-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func aufraeumen(_ ort: URL) { try? FileManager.default.removeItem(at: ort) }

    private func tresor() throws -> Tresor {
        let t = Tresor.neu()
        try t.passphraseSetzen(passphrase, runden: Tresor.rundenMindestens)
        return t
    }

    // ── Die Jahresdatei (B100) ────────────────────────────────────────────

    /// Anna und Ben in der Gruppe 6a — und ein Mitglied, das es nicht gibt: reiner Verlust, keine ersetzte Kennung.
    private func jahresdatei(_ t: Tresor) throws -> Data {
        let s = Self.stempel
        var b = Lernendenbestand.leer(planung: "2026-08-10T09:00:00.000Z", schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-2", vorname: "Ben", nachname: "Bauer", angelegt: s, geaendert: s, archiviert: "")]
        b.lerngruppen = [Lerngruppe(id: "g-1", name: "6a", art: .klasse, mitglieder: ["l-1", "l-2"],
                                    zeilen: [], skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        var objekt = Lernendendatei.alsObjekt(b)
        var gruppen = try #require(objekt["lerngruppen"] as? [[String: Any]])
        gruppen[0]["mitglieder"] = ["l-1", "l-2", "l-9"]
        objekt["lerngruppen"] = gruppen
        return try t.versiegeln(try JSONSerialization.data(withJSONObject: objekt), inhalt: .lernende, ziel: .ablage)
    }

    /// Was auf der Platte steht, geöffnet und gelesen.
    private func platte(_ ablage: Ablage, _ t: Tresor) throws -> (bestand: Lernendenbestand, bilanz: Lernendendatei.Bilanz) {
        try Lernendendatei.lesenMitBilanz(try t.oeffnen(kopf: try Tresor.kopfLesen(try Data(contentsOf: ablage.lernende))))
    }

    private func kopie(_ ort: URL, _ name: String) -> Data? {
        try? Data(contentsOf: ort.appending(component: name))
    }

    @Test("Reiner Verlust: das Original bewahrt, die Jahresdatei einmal geschrieben — der zweite Start liest sauber und kopiert nicht erneut (B100)")
    func zweiterStartKopiertNicht() throws {
        let ort = try ordner("zweiter-start")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try jahresdatei(t)
        try original.write(to: ablage.lernende)
        let merker = Meldungsmerker()
        let dienst = Lernendendienst(ablage: ablage)
        dienst.melden = { text, _ in merker.texte.append(text) }

        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        guard case .bereinigt(2, let bilanz, kopie: "lernende-bereinigt-s1.json") = befund, bilanz.verlust,
              !bilanz.festzuschreiben else {
            Issue.record("erwartet bereinigt mit Kopie — \(befund)")
            return
        }
        #expect(kopie(ort, "lernende-bereinigt-s1.json") == original, "das Original liegt als Rettungskopie daneben (E46)")
        let (aufDerPlatte, bilanzDort) = try platte(ablage, t)
        #expect(aufDerPlatte == dienst.bestand && bilanzDort.istLeer,
                Comment(rawValue: "die Platte trägt den bereinigten Stand — dort: \(bilanzDort.beschreibung)"))
        #expect(dienst.ungesichert == nil && merker.texte.isEmpty, Comment(rawValue: merker.texte.joined(separator: " | ")))

        let neustart = Lernendendienst(ablage: ablage)
        neustart.schliessen()
        let zweiter = neustart.oeffnen(mit: t, stempel: "s2")
        #expect(zweiter == .geladen(2), Comment(rawValue: "zweiter Start: \(zweiter)"))
        #expect(kopie(ort, "lernende-bereinigt-s2.json") == nil, "keine zweite Rettungskopie")
        #expect(neustart.bestand == dienst.bestand)
    }

    @Test("Reiner Verlust, die Kopie gelingt erst im zweiten Anlauf beim Schreiben: Der Befund nennt sie, die Jahresdatei ist geschrieben, keine Warnung (B100, Z-AU6-02)")
    func kopieImZweitenAnlauf() throws {
        let ort = try ordner("zweiter-anlauf")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try jahresdatei(t)
        try original.write(to: ablage.lernende)
        let tor = Zaehltor(abweisen: [1])
        ablage.schreibsperre = { tor.grund }
        let merker = Meldungsmerker()
        let dienst = Lernendendienst(ablage: ablage)
        dienst.melden = { text, _ in merker.texte.append(text) }

        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        // Erste Kopie, zweite Kopie beim Schreiben, das Schreiben selbst.
        #expect(tor.anfragen == 3, "Anfragen am Tor: \(tor.anfragen)")
        guard case .bereinigt(2, _, kopie: "lernende-bereinigt-s1.json") = befund else {
            Issue.record("erwartet bereinigt mit der Kopie aus dem zweiten Anlauf — \(befund)")
            return
        }
        #expect(kopie(ort, "lernende-bereinigt-s1.json") == original && dienst.ungesichert == nil,
                Comment(rawValue: dienst.ungesichert ?? "—"))
        #expect(merker.texte.isEmpty, Comment(rawValue: merker.texte.joined(separator: " | ")))
        let (aufDerPlatte, bilanz) = try platte(ablage, t)
        #expect(aufDerPlatte == dienst.bestand && bilanz.istLeer, "die Jahresdatei ist geschrieben")
    }

    @Test("Reiner Verlust, die Kopie misslingt: Nichts geht über die Datei, der Grund steht still in ungesichert — das Nachholen schreibt nach der Kopie (B100, E46, Z-AU6-01)")
    func kopieScheitertStill() throws {
        let ort = try ordner("kopie")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try jahresdatei(t)
        try original.write(to: ablage.lernende)
        let tor = Tor()
        ablage.schreibsperre = { tor.grund }
        let merker = Meldungsmerker()
        let dienst = Lernendendienst(ablage: ablage)
        dienst.melden = { text, _ in merker.texte.append(text) }

        tor.schliessen()
        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        guard case .bereinigt(2, _, kopie: nil) = befund else {
            Issue.record("erwartet bereinigt ohne Kopie — \(befund)")
            return
        }
        #expect(try Data(contentsOf: ablage.lernende) == original, "ohne Kopie geht nichts über die Datei")
        #expect(dienst.ungesichert?.contains("Original") == true, Comment(rawValue: dienst.ungesichert ?? "—"))
        #expect(merker.texte.isEmpty, Comment(rawValue: merker.texte.joined(separator: " | ")))

        tor.oeffnen()
        dienst.nachholen()
        #expect(dienst.ungesichert == nil)
        #expect(kopie(ort, "lernende-bereinigt-s1.json") == original, "erst die Kopie …")
        let (aufDerPlatte, bilanz) = try platte(ablage, t)
        #expect(aufDerPlatte == dienst.bestand && bilanz.istLeer, "… dann die Jahresdatei")
    }

    // ── Die Sitzpläne (B103) ──────────────────────────────────────────────

    /// Ein Plan mit einem zu langen Namen und einem Tisch ohne Namen — mit Verlust zu lesen —, versiegelt unter
    /// der Hülle, die `t` jetzt trägt; danach wechselt die Hülle, die Datei liegt unter der älteren.
    private func sitzplaeneUnterAeltererHuelle(_ t: Tresor) throws -> Data {
        let roh: [String: Any] = ["typ": Sitzplandatei.typ, "version": 1, "plaene": [
            "k-eins": ["tische": [["id": "t-1", "name": String(repeating: "q", count: 120), "x": 40, "y": 336],
                                  ["id": "t-2", "name": "", "x": 40, "y": 200]]]]]
        let daten = try t.versiegeln(try JSONSerialization.data(withJSONObject: roh), inhalt: .sitzplaene, ziel: .ablage)
        try t.passphraseSetzen(zweite, runden: Tresor.rundenMindestens)
        #expect(!t.huelleGleich(try Tresor.kopfLesen(daten), ziel: .ablage), "die Datei liegt unter der älteren Hülle")
        return daten
    }

    private func sitzplantexte(_ s: Planungsspeicher) -> [String] {
        s.meldungen.map(\.text).filter { $0.contains("Sitzpläne") }
    }

    @Test("Verlust und ältere Hülle, die Kopie misslingt zweimal: eine Meldung — nichts geht über die Datei (B103, E46)")
    func sitzplaeneEineMeldung() throws {
        let ort = try ordner("sitzplaene-eine")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let s = Planungsspeicher(ablage: ablage)
        let t = try tresor()
        let original = try sitzplaeneUnterAeltererHuelle(t)
        try original.write(to: ablage.sitzplaene)
        let tor = Tor()
        tor.schliessen()
        ablage.schreibsperre = { tor.grund }

        s.sitzplaeneOeffnen(t)
        let texte = sitzplantexte(s)
        #expect(texte.count == 1 && texte.first?.hasPrefix("Die Sitzpläne (1) wurden beim Lesen bereinigt") == true
                    && texte.first?.hasSuffix("Eine Kopie des Originals ließ sich nicht anlegen; bis es gelingt, "
                                              + "wird nichts darüber geschrieben.") == true,
                Comment(rawValue: texte.joined(separator: " | ")))
        #expect(try Data(contentsOf: ablage.sitzplaene) == original, "ohne Kopie geht nichts über die Datei")
        #expect(s.sitzplaene.ungesichert?.contains("Original") == true && s.sitzplaene.ausstehendeKopie != nil,
                Comment(rawValue: s.sitzplaene.ungesichert ?? "—"))
    }

    @Test("Sitzpläne, reiner Verlust unter der jetzigen Hülle: das Original bewahrt, einmal geschrieben — der zweite Start liest sauber und kopiert nicht erneut (Z-AV5-01, E456)")
    func sitzplaeneZweiterStartKopiertNicht() throws {
        let ort = try ordner("sitzplaene-verlust")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let roh: [String: Any] = ["typ": Sitzplandatei.typ, "version": 1, "plaene": [
            "k-eins": ["tische": [["id": "t-1", "name": String(repeating: "q", count: 120), "x": 40, "y": 336],
                                  ["id": "t-2", "name": "", "x": 40, "y": 200]]]]]
        let original = try t.versiegeln(try JSONSerialization.data(withJSONObject: roh), inhalt: .sitzplaene, ziel: .ablage)
        try original.write(to: ablage.sitzplaene)
        let erster = Sitzplandienst(ablage: ablage).oeffnen(mit: t, stempel: "s1")
        guard case .bereinigt(1, _, kopie: "sitzplaene-bereinigt-s1.json") = erster else {
            Issue.record("erster Start: erwartet bereinigt mit Kopie — \(erster)")
            return
        }
        #expect(kopie(ort, "sitzplaene-bereinigt-s1.json") == original, "das Original bewahrt")
        #expect(try Data(contentsOf: ablage.sitzplaene) != original, "einmal geschrieben")
        let zweiter = Sitzplandienst(ablage: ablage).oeffnen(mit: t, stempel: "s2")
        guard case .geladen(1) = zweiter else {
            Issue.record("zweiter Start: erwartet sauber geladen — \(zweiter)")
            return
        }
        #expect(kopie(ort, "sitzplaene-bereinigt-s2.json") == nil, "keine zweite Kopie")
    }

    @Test("Ein neues Lesen beginnt ohne ausstehende Kopie: Liest es sauber, hängt kein Name aus dem vorigen Lesen nach (Z-AV5-05)")
    func sitzplaeneNeuesLesenOhneAlteKopie() throws {
        let ort = try ordner("sitzplaene-neu")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        func datei(_ name: String) throws -> Data {
            let roh: [String: Any] = ["typ": Sitzplandatei.typ, "version": 1, "plaene": [
                "k-eins": ["tische": [["id": "t-1", "name": name, "x": 40, "y": 336]]]]]
            return try t.versiegeln(try JSONSerialization.data(withJSONObject: roh), inhalt: .sitzplaene, ziel: .ablage)
        }
        try datei(String(repeating: "q", count: 120)).write(to: ablage.sitzplaene)
        let tor = Tor()
        tor.schliessen()
        ablage.schreibsperre = { tor.grund }
        let dienst = Sitzplandienst(ablage: ablage)
        guard case .bereinigt(1, _, kopie: nil) = dienst.oeffnen(mit: t, stempel: "s1") else {
            Issue.record("erstes Lesen: erwartet bereinigt ohne Kopie")
            return
        }
        #expect(dienst.ausstehendeKopie == "sitzplaene-bereinigt-s1.json")
        tor.oeffnen()
        try datei("Anna").write(to: ablage.sitzplaene)
        guard case .geladen(1) = dienst.oeffnen(mit: t, stempel: "s2") else {
            Issue.record("zweites Lesen: erwartet sauber geladen")
            return
        }
        #expect(dienst.ausstehendeKopie == nil, Comment(rawValue: dienst.ausstehendeKopie ?? "—"))
    }

    @Test("Verlust und ältere Hülle, die Kopie gelingt erst im zweiten Anlauf: Der Befund nennt sie, die Datei ist unter der neuen Hülle geschrieben, keine Warnung (B103, Z-AU6-02)")
    func sitzplaeneKopieAusDemZweitenAnlauf() throws {
        let ort = try ordner("sitzplaene-zweiter")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try sitzplaeneUnterAeltererHuelle(t)
        try original.write(to: ablage.sitzplaene)
        let tor = Zaehltor(abweisen: [1])
        ablage.schreibsperre = { tor.grund }
        let merker = Meldungsmerker()
        let dienst = Sitzplandienst(ablage: ablage)
        dienst.melden = { text, _ in merker.texte.append(text) }

        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        #expect(tor.anfragen == 3, "Anfragen am Tor: \(tor.anfragen)")
        guard case .bereinigt(1, _, kopie: "sitzplaene-bereinigt-s1.json") = befund else {
            Issue.record("erwartet bereinigt mit der Kopie aus dem zweiten Anlauf — \(befund)")
            return
        }
        #expect(kopie(ort, "sitzplaene-bereinigt-s1.json") == original && dienst.ungesichert == nil,
                Comment(rawValue: dienst.ungesichert ?? "—"))
        #expect(merker.texte.isEmpty, Comment(rawValue: merker.texte.joined(separator: " | ")))
        #expect(t.huelleGleich(try Tresor.kopfLesen(try Data(contentsOf: ablage.sitzplaene)), ziel: .ablage),
                "unter der neuen Hülle geschrieben")
    }

    @Test("Liegt die Kopie im zweiten Anlauf und scheitert dann das Schreiben, warnt der Sitzplandienst genau einmal — der Befund nennt die Kopie (B103, Z-AU6-09)")
    func sitzplaeneSchreibenScheitert() throws {
        let ort = try ordner("sitzplaene-schreiben")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try sitzplaeneUnterAeltererHuelle(t)
        try original.write(to: ablage.sitzplaene)
        let tor = Zaehltor(abweisen: [1, 3])
        ablage.schreibsperre = { tor.grund }
        let merker = Meldungsmerker()
        let dienst = Sitzplandienst(ablage: ablage)
        dienst.melden = { text, _ in merker.texte.append(text) }

        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        #expect(tor.anfragen == 3, "Anfragen am Tor: \(tor.anfragen)")
        guard case .bereinigt(1, _, kopie: "sitzplaene-bereinigt-s1.json") = befund else {
            Issue.record("erwartet bereinigt mit der Kopie aus dem zweiten Anlauf — \(befund)")
            return
        }
        #expect(kopie(ort, "sitzplaene-bereinigt-s1.json") == original && dienst.ungesichert != nil,
                "die Kopie liegt, das Schreiben scheiterte")
        #expect(try Data(contentsOf: ablage.sitzplaene) == original, "die Datei bleibt, wie sie lag")
        let einmal = merker.texte.count == 1 && merker.texte.first?.hasPrefix("Die Sitzpläne ließen sich nicht sichern") == true
        #expect(einmal, Comment(rawValue: merker.texte.joined(separator: " | ")))
    }
}
