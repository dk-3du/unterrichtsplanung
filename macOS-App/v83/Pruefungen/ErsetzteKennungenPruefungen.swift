// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Die Schreibsperre der Ablage, von der Prüfung auf- und zugemacht — gelesen auf jedem Faden.
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

/// Was die Senke des Dienstes erreicht.
@MainActor
private final class Meldungsmerker {
    var texte: [String] = []
}

// ── Ersetzte Kennungen der Jahresdatei (B93, E419) ────────────────────────
// Eine Kennung, die leer, außerhalb des Musters oder doppelt ist, ersetzt das
// Lesen durch eine zufällige. Blieb die Datei, wie sie lag, würfelte jedes
// Lesen neu — und was an der Kennung hing (ein Tisch im Sitzplan), löste der
// Abgleich beim nächsten Start (C, E345). Wie beim Verlust wird das Original
// bewahrt (E46) und die Jahresdatei danach einmal geschrieben.

@Suite("Ersetzte Kennungen: einmal geschrieben, das Original bewahrt — die Bindung übersteht den Neustart (B93, E419)")
@MainActor
struct ErsetzteKennungenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private static let stempel = "2026-10-03T08:00:00.000Z"
    private static let herkunft = "2026-08-10T09:00:00.000Z"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "ersetzt-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func aufraeumen(_ ort: URL) { try? FileManager.default.removeItem(at: ort) }

    private func tresor() throws -> Tresor {
        let t = Tresor.neu()
        try t.passphraseSetzen(passphrase, runden: Tresor.rundenMindestens)
        return t
    }

    /// Anna (l-1) in der Gruppe 6a, Ben ohne Gruppe — nichts in der Datei zeigt auf Ben,
    /// das Ersetzen seiner Kennung ist kein Verlust.
    private func bestand(planung: String) -> Lernendenbestand {
        let s = Self.stempel
        var b = Lernendenbestand.leer(planung: planung, schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-2", vorname: "Ben", nachname: "Bauer", angelegt: s, geaendert: s, archiviert: "")]
        b.lerngruppen = [Lerngruppe(id: "g-1", name: "6a", fach: "Biologie", art: .klasse, mitglieder: ["l-1"],
                                    zeilen: [], skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        return b
    }

    /// Die Jahresdatei mit Ben unter einer anderen Kennung — so, wie sie von fremder Hand liegen kann.
    private func mitBen(_ kennung: String, planung: String) throws -> [String: Any] {
        var objekt = Lernendendatei.alsObjekt(bestand(planung: planung))
        var personen = try #require(objekt["lernende"] as? [[String: Any]])
        personen[1]["id"] = kennung
        objekt["lernende"] = personen
        return objekt
    }

    /// Versiegelt unter `t`, wie der Dienst schreibt.
    private func versiegelt(_ objekt: [String: Any], _ t: Tresor) throws -> Data {
        try t.versiegeln(try JSONSerialization.data(withJSONObject: objekt), inhalt: .lernende, ziel: .ablage)
    }

    /// Was auf der Platte steht, geöffnet und gelesen.
    private func platte(_ ablage: Ablage, _ t: Tresor) throws -> (bestand: Lernendenbestand, bilanz: Lernendendatei.Bilanz) {
        try Lernendendatei.lesenMitBilanz(try t.oeffnen(kopf: try Tresor.kopfLesen(try Data(contentsOf: ablage.lernende))))
    }

    private func kopie(_ ort: URL, _ stempel: String) -> Data? {
        try? Data(contentsOf: ort.appending(component: "lernende-bereinigt-\(stempel).json"))
    }

    private func texte(_ s: Planungsspeicher) -> String { s.meldungen.map(\.text).joined(separator: " | ") }

    // ── Der Dienst ────────────────────────────────────────────────────────

    @Test("Ersetzte Kennungen: das Original als Rettungskopie bewahrt, die Jahresdatei einmal geschrieben — der nächste Start liest dieselben (E419, E46)")
    func dienstSchreibtEinmal() throws {
        let ort = try ordner("dienst")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        // Ben doppelt (l-1), Cem außerhalb des Musters.
        var objekt = try mitBen("l-1", planung: Self.herkunft)
        var personen = try #require(objekt["lernende"] as? [[String: Any]])
        personen.append(["id": "c 3", "vorname": "Cem", "nachname": "Çelik"])
        objekt["lernende"] = personen
        let original = try versiegelt(objekt, t)
        try original.write(to: ablage.lernende)
        var erwartet = Lernendendatei.Bilanz()
        erwartet.ersetzteKennungen = 2

        let dienst = Lernendendienst(ablage: ablage)
        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        #expect(befund == .bereinigt(3, erwartet, kopie: "lernende-bereinigt-s1.json"), Comment(rawValue: "\(befund)"))
        #expect(kopie(ort, "s1") == original, "das Original liegt als Rettungskopie daneben (E46)")
        let gelesen = try #require(dienst.bestand)
        #expect(dienst.ungesichert == nil)
        let k = try Tresor.kopfLesen(try Data(contentsOf: ablage.lernende))
        #expect(k.inhalt == "lernende" && k.kennung == t.kennung, "ein Behälter unter dem Schlüssel der Sitzung")
        let (aufDerPlatte, bilanz) = try platte(ablage, t)
        #expect(aufDerPlatte == gelesen && bilanz.istLeer,
                Comment(rawValue: "die Platte trägt die ersetzten Kennungen — beim Lesen: \(bilanz.beschreibung)"))

        let neustart = Lernendendienst(ablage: ablage)
        neustart.schliessen()
        #expect(neustart.oeffnen(mit: t, stempel: "s2") == .geladen(3))
        #expect(neustart.bestand?.lernende.map(\.id) == gelesen.lernende.map(\.id), "dieselben Kennungen nach dem Neustart")
        #expect(kopie(ort, "s2") == nil, "keine zweite Rettungskopie")
    }

    // ── Der Hauptweg ──────────────────────────────────────────────────────

    /// Ein eingeschalteter Speicher mit einer Planung aus zwei Klassen.
    private func speicher(_ ort: URL) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                                 basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie"), ("7b", "Chemie")]),
                                 fachfarben: [:])
        s.jetztSichern()
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        return s
    }

    @Test("Hauptweg: ein Tisch an einer Person mit ersetzter Kennung, Neustart, Entsperren — die Bindung bleibt, nichts gelöst (B93)")
    func bindungUebersteht() async throws {
        let ort = try ordner("neustart")
        defer { aufraeumen(ort) }
        let s = try speicher(ort)
        let p = try #require(s.planung)
        let t = try #require(s.tresor)
        let klasse = try #require(p.klassen.first?.id)
        try versiegelt(try mitBen("b 2", planung: p.erstellt), t).write(to: Ablage(ordner: ort).lernende)
        s.jetztSichern()

        // Erster Start: Ben bekommt eine neue Kennung, ein Tisch wird an ihn gebunden.
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ort))
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        let benGelesen = zweiter.lernende.bestand?.lernende.first { $0.vorname == "Ben" }?.id
        let ben = try #require(benGelesen)
        let gemeldet = zweiter.meldungen.contains {
            $0.text.hasPrefix("Die Lernendendaten wurden beim Lesen bereinigt: 1 Kennung ersetzt — das Original liegt als „lernende-bereinigt-")
        }
        #expect(gemeldet, Comment(rawValue: texte(zweiter)))
        let plan = Sitzplan.anordnen(klasseId: klasse, lernende: [.init(name: "Anna Abel", lernender: "l-1"),
                                                                 .init(name: "Ben Bauer", lernender: ben)])
        #expect(zweiter.sitzplaene.setzen(plan, fuer: klasse) == nil)
        zweiter.jetztSichern()

        // Zweiter Start: dieselbe Kennung, der Tisch bleibt gebunden.
        let dritter = Planungsspeicher(ablage: Ablage(ordner: ort))
        dritter.starten()
        await dritter.entsperren(passphrase: passphrase)
        #expect(dritter.lernende.bestand?.lernende.map(\.id) == ["l-1", ben], "dieselbe Kennung nach dem Neustart")
        #expect(dritter.sitzplaene.plan(fuer: klasse)?.tische.map(\.lernender) == ["l-1", ben],
                Comment(rawValue: "\(dritter.sitzplaene.plan(fuer: klasse)?.tische.map(\.lernender) ?? [])"))
        let unerwartet = dritter.meldungen.contains { $0.text.contains("Zuordnung") || $0.text.contains("Lernendendaten") }
        #expect(!unerwartet, Comment(rawValue: texte(dritter)))
    }

    // ── Übereifer und Rettung ─────────────────────────────────────────────

    @Test("Übereifer-Gegenprobe: ohne ersetzte Kennungen und ohne Verlust schreibt das Lesen nicht — sauber oder nur normiert bleibt die Datei, wie sie liegt; mit Verlust erst die Kopie, dann einmal geschrieben (E46, B100)")
    func ohneErsetzteUnangetastet() throws {
        let ort = try ordner("unangetastet")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let sauber = Lernendendatei.alsObjekt(bestand(planung: Self.herkunft))
        var normiert = sauber
        normiert["geaendert"] = "gestern"  // geleert und gezählt, kein Verlust
        var verlust = sauber
        var gruppen = try #require(verlust["lerngruppen"] as? [[String: Any]])
        gruppen[0]["mitglieder"] = ["l-1", "l-9"]
        verlust["lerngruppen"] = gruppen
        let faelle: [(fall: String, objekt: [String: Any], kopie: Bool)] = [
            ("sauber", sauber, false), ("normiert", normiert, false), ("Verlust", verlust, true),
        ]
        for (fall, objekt, mitKopie) in faelle {
            let original = try versiegelt(objekt, t)
            try original.write(to: ablage.lernende)
            let befund = Lernendendienst(ablage: ablage).oeffnen(mit: t, stempel: fall)
            // Mit Verlust einmal geschrieben (B100, E456 a) — sonst bleibt die Datei, wie sie liegt.
            #expect((try Data(contentsOf: ablage.lernende) != original) == mitKopie,
                    Comment(rawValue: "\(fall): beim Lesen \(mitKopie ? "nicht " : "")geschrieben"))
            #expect((kopie(ort, fall) != nil) == mitKopie, Comment(rawValue: "\(fall): Rettungskopie"))
            if mitKopie { #expect(kopie(ort, fall) == original, Comment(rawValue: "\(fall): die Kopie ist das Original")) }
            // Der Befund dazu: geladen — beim Verlust bereinigt, mit der Kopie (Z-AU6-03).
            let passend = switch befund {
            case .geladen(2): !mitKopie
            case .bereinigt(2, _, let k): mitKopie && k == "lernende-bereinigt-\(fall).json"
            default: false
            }
            #expect(passend, Comment(rawValue: "\(fall): \(befund)"))
        }
    }

    @Test("Lässt sich das Original nicht bewahren, geht nichts über die Datei — der Grund steht still in ungesichert, das Nachholen schreibt nach der Kopie (E46, Z-AU6-01)")
    func kopieScheitert() throws {
        let ort = try ordner("kopie")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try versiegelt(try mitBen("l-1", planung: Self.herkunft), t)
        try original.write(to: ablage.lernende)
        let tor = Tor()
        ablage.schreibsperre = { tor.grund }
        let merker = Meldungsmerker()
        let dienst = Lernendendienst(ablage: ablage)
        dienst.melden = { text, _ in merker.texte.append(text) }
        var erwartet = Lernendendatei.Bilanz()
        erwartet.ersetzteKennungen = 1

        tor.schliessen()
        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        #expect(befund == .bereinigt(2, erwartet, kopie: nil), Comment(rawValue: "\(befund)"))
        #expect(try Data(contentsOf: ablage.lernende) == original, "ohne Kopie geht nichts über die Datei")
        #expect(dienst.ungesichert?.contains("Original") == true, Comment(rawValue: dienst.ungesichert ?? "—"))
        // Die Ursache sagt der Befund — keine zweite Warnung des Dienstes dazu (Z-AU6-01).
        #expect(merker.texte.isEmpty, Comment(rawValue: merker.texte.joined(separator: " | ")))

        tor.oeffnen()
        dienst.nachholen()
        #expect(dienst.ungesichert == nil)
        #expect(kopie(ort, "s1") == original, "erst die Kopie …")
        let (aufDerPlatte, bilanz) = try platte(ablage, t)
        #expect(aufDerPlatte == dienst.bestand && bilanz.istLeer, "… dann die Jahresdatei")
    }

    @Test("Gelingt die Kopie erst im zweiten Anlauf beim Schreiben, nennt der Befund sie — die Jahresdatei ist geschrieben, keine Warnung (Z-AU6-02)")
    func kopieImZweitenAnlauf() throws {
        let ort = try ordner("zweiter-anlauf")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try versiegelt(try mitBen("l-1", planung: Self.herkunft), t)
        try original.write(to: ablage.lernende)
        let tor = Zaehltor(abweisen: [1])
        ablage.schreibsperre = { tor.grund }
        let merker = Meldungsmerker()
        let dienst = Lernendendienst(ablage: ablage)
        dienst.melden = { text, _ in merker.texte.append(text) }
        var erwartet = Lernendendatei.Bilanz()
        erwartet.ersetzteKennungen = 1

        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        // Erste Kopie, zweite Kopie beim Schreiben, das Schreiben selbst (Z-AU6-09).
        #expect(tor.anfragen == 3, "Anfragen am Tor: \(tor.anfragen)")
        #expect(befund == .bereinigt(2, erwartet, kopie: "lernende-bereinigt-s1.json"), Comment(rawValue: "\(befund)"))
        #expect(kopie(ort, "s1") == original && dienst.ungesichert == nil, Comment(rawValue: dienst.ungesichert ?? "—"))
        #expect(merker.texte.isEmpty, Comment(rawValue: merker.texte.joined(separator: " | ")))
        let (aufDerPlatte, bilanz) = try platte(ablage, t)
        #expect(aufDerPlatte == dienst.bestand && bilanz.istLeer, "die Jahresdatei ist geschrieben")
    }

    @Test("Liegt die Kopie im zweiten Anlauf und scheitert dann das Schreiben, warnt der Dienst genau einmal — der Befund nennt die Kopie (Z-AU6-09)")
    func kopieImZweitenAnlaufSchreibenScheitert() throws {
        let ort = try ordner("zweiter-anlauf-schreiben")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try versiegelt(try mitBen("l-1", planung: Self.herkunft), t)
        try original.write(to: ablage.lernende)
        let tor = Zaehltor(abweisen: [1, 3])
        ablage.schreibsperre = { tor.grund }
        let merker = Meldungsmerker()
        let dienst = Lernendendienst(ablage: ablage)
        dienst.melden = { text, _ in merker.texte.append(text) }
        var erwartet = Lernendendatei.Bilanz()
        erwartet.ersetzteKennungen = 1

        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        #expect(tor.anfragen == 3, "Anfragen am Tor: \(tor.anfragen)")
        #expect(befund == .bereinigt(2, erwartet, kopie: "lernende-bereinigt-s1.json"), Comment(rawValue: "\(befund)"))
        #expect(kopie(ort, "s1") == original && dienst.ungesichert != nil, "die Kopie liegt, das Schreiben scheiterte")
        #expect(try Data(contentsOf: ablage.lernende) == original, "die Datei bleibt, wie sie lag")
        let einmal = merker.texte.count == 1
            && merker.texte.first?.hasPrefix("Die Lernendendaten ließen sich nicht sichern") == true
        #expect(einmal, Comment(rawValue: merker.texte.joined(separator: " | ")))
    }

    @Test("Verschwindet die Jahresdatei zwischen Lesen und Kopie, nennt der Befund keine Kopie — es gibt keine (Z-AU6-10)")
    func dateiVerschwindetVorDerKopie() throws {
        let ort = try ordner("verschwunden")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        try versiegelt(try mitBen("l-1", planung: Self.herkunft), t).write(to: ablage.lernende)
        // Die erste Kopie scheitert; vor dem zweiten Versuch ist die Datei fort.
        let tor = Zaehltor(abweisen: [1])
        ablage.schreibsperre = { tor.grund }
        let dienst = Lernendendienst(ablage: ablage)
        dienst.schreibsperre = { [ziel = ablage.lernende] in
            try? FileManager.default.removeItem(at: ziel)
            return nil
        }
        var erwartet = Lernendendatei.Bilanz()
        erwartet.ersetzteKennungen = 1

        let befund = dienst.oeffnen(mit: t, stempel: "s1")
        #expect(befund == .bereinigt(2, erwartet, kopie: nil), Comment(rawValue: "\(befund)"))
        #expect(kopie(ort, "s1") == nil, "keine Kopie")
    }
}
