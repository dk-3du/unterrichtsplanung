// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die Lesezeichen als Behälter ──────────────────────────────────────────
// Bei eingeschalteter Verschlüsselung liegen Lesezeichen und Zielordner
// versiegelt neben der Ablage: hin und zurück ohne Verlust, unter den neuen
// Schlüssel, beschädigt beiseite, zu bis zum Entsperren.

@Suite("Lesezeichen versiegelt: Behälter, Übergänge, Start hinter versiegelter Ablage")
@MainActor
struct LesezeichenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "lesezeichen-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    /// Ein Zugriff mit einem Lesezeichen und einem Zielordner — im Klartext.
    private func vorrat(_ ablage: Ablage, material: URL, ziel: URL) throws -> (Ordnerzugriff, String) {
        let zugriff = Ordnerzugriff(ablage: ablage)
        let eintrag = try zugriff.merken(material)
        zugriff.zielordner = ziel.path
        return (zugriff, eintrag)
    }

    private func behaelterKopf(_ ablage: Ablage) throws -> Behaelterkopf {
        try Tresor.kopfLesen(try Data(contentsOf: ablage.lesezeichen))
    }

    // ── Die Nutzlast ────────────────────────────────────────────────

    @Test("Die Nutzlast geht Byte für Byte hin und zurück; Unbrauchbares wird benannt")
    func nutzlast() throws {
        let eintraege = ["/Users/lehrkraft/Unterricht": Data([1, 2, 3, 250]), "/Volumes/Stick": Data()]
        let daten = try Ordnerzugriff.nutzlast(eintraege: eintraege, zielordner: "/Users/lehrkraft/Kopie")
        let gelesen = try Ordnerzugriff.nutzlastLesen(daten)
        #expect(gelesen.eintraege == eintraege && gelesen.zielordner == "/Users/lehrkraft/Kopie")
        #expect(String(decoding: daten, as: UTF8.self).contains("\"version\":1"))
        for kaputt in ["{}", "[]", "kein JSON",
                       "{\"version\":true,\"lesezeichen\":{},\"zielordner\":\"\"}",
                       "{\"version\":2,\"lesezeichen\":{},\"zielordner\":\"\"}",
                       "{\"version\":1,\"lesezeichen\":{\"/x\":\"%%%\"},\"zielordner\":\"\"}",
                       "{\"version\":1,\"lesezeichen\":{\"\":\"AA==\"},\"zielordner\":\"\"}",
                       "{\"version\":1,\"lesezeichen\":[],\"zielordner\":\"\"}",
                       "{\"version\":1,\"lesezeichen\":{},\"zielordner\":1}"] {
            #expect(throws: Tresorfehler.self, "\(kaputt)") { try Ordnerzugriff.nutzlastLesen(Data(kaputt.utf8)) }
        }
    }

    // ── Übergänge am Zugriff ────────────────────────────────────────

    @Test("Versiegeln, schließen, öffnen, entsiegeln: der Vorrat bleibt Byte für Byte, der Behälter kommt und geht")
    func hinUndZurueck() throws {
        let ablageOrdner = try ordner("ablage")
        let ziel = try ordner("ziel")
        let material = try ordner("material")
        defer { aufraeumen(ablageOrdner, ziel, material) }
        let ablage = Ablage(ordner: ablageOrdner)
        let (zugriff, eintrag) = try vorrat(ablage, material: material, ziel: ziel)
        #expect(zugriff.quelle == .einstellungen)
        let bytesVorher = zugriff.eintraege
        let t = try tresor()

        #expect(zugriff.versiegeln(unter: t) == nil)
        #expect(zugriff.quelle == .behaelter)
        #expect(zugriff.zustaendig(fuer: material.path + "/x.pdf") == eintrag, "offen bleibt offen")
        #expect(zugriff.zielordner == ziel.path)
        let kopf = try behaelterKopf(ablage)
        #expect(kopf.inhalt == "lesezeichen" && kopf.kennung == t.kennung)
        let nutzlast = try Ordnerzugriff.nutzlastLesen(try t.oeffnen(kopf: kopf))
        #expect(nutzlast.eintraege == bytesVorher && nutzlast.zielordner == ziel.path)

        // Ein Merken im Behälter-Zustand schreibt den Behälter neu.
        let zweites = try ordner("zweites")
        defer { aufraeumen(zweites) }
        let zweiterEintrag = try zugriff.merken(zweites)
        #expect(try Ordnerzugriff.nutzlastLesen(try t.oeffnen(kopf: try behaelterKopf(ablage)))
                    .eintraege.keys.sorted() == [eintrag, zweiterEintrag].sorted())

        // Wie nach einem Neustart: ein frischer Zugriff an derselben Ablage — zu, bis der Schlüssel da ist.
        let neustart = Ordnerzugriff(ablage: ablage)
        neustart.schliessen()
        #expect(neustart.quelle == .zu)
        #expect(neustart.zustaendig(fuer: material.path) == nil && neustart.zielordner.isEmpty && neustart.alle.isEmpty)
        #expect(throws: Ordnerzugriff.Fehler.self) { try neustart.merken(material) }
        #expect(throws: Ordnerzugriff.Fehler.self) { try neustart.aufloesen(material.path) }
        do {
            _ = try neustart.aufloesen(material.path)
        } catch let fehler as Ordnerzugriff.Fehler {
            #expect(fehler.art == .versiegelt && fehler.text.contains("entsperren"))
        }
        neustart.zielordner = "/anderswo"
        #expect(neustart.zielordner.isEmpty, "zu heißt: nichts nehmen, nichts zeigen")

        #expect(neustart.oeffnen(mit: t, stempel: "s") == .geoeffnet(2))
        #expect(neustart.quelle == .behaelter && neustart.zielordner == ziel.path)
        #expect(neustart.eintraege == zugriff.eintraege, "Byte für Byte, was vorher da war")
        #expect(try neustart.aufloesen(material.path).path == Ordnerzugriff.kanonisch(material.path))

        // Entsiegeln: zurück in die Einstellungen, der Behälter weg — der Vorrat bleibt.
        neustart.entsiegeln()
        #expect(neustart.quelle == .einstellungen)
        #expect(!FileManager.default.fileExists(atPath: ablage.lesezeichen.path))
        #expect(neustart.eintraege == bytesVorher.merging(zugriff.eintraege) { _, b in b })
        #expect(neustart.zustaendig(fuer: material.path) == eintrag && neustart.zielordner == ziel.path)
        #expect(UserDefaults.standard.dictionary(forKey: "unterrichtsplanung.lesezeichen") == nil,
                "im Prüflauf nichts in den Einstellungen")
    }

    @Test("Erneuern: der Behälter wandert unter den neuen Schlüssel; der alte öffnet ihn nicht mehr")
    func erneuern() throws {
        let ablageOrdner = try ordner("ablage")
        let ziel = try ordner("ziel")
        let material = try ordner("material")
        defer { aufraeumen(ablageOrdner, ziel, material) }
        let ablage = Ablage(ordner: ablageOrdner)
        let (zugriff, eintrag) = try vorrat(ablage, material: material, ziel: ziel)
        let alter = try tresor()
        let neuer = try tresor()
        #expect(zugriff.versiegeln(unter: alter) == nil)
        let vorher = zugriff.eintraege

        #expect(zugriff.versiegeln(unter: neuer) == nil)
        let kopf = try behaelterKopf(ablage)
        #expect(kopf.kennung == neuer.kennung)
        #expect(throws: Tresorfehler.self) { try alter.oeffnen(kopf: kopf) }
        let gelesen = try Ordnerzugriff.nutzlastLesen(try neuer.oeffnen(kopf: kopf))
        #expect(gelesen.eintraege == vorher && gelesen.zielordner == ziel.path)
        #expect(zugriff.zustaendig(fuer: material.path) == eintrag)
    }

    @Test("Beschädigt, fremd versiegelt oder falscher Inhalt: beiseitegelegt, leer neu angelegt — mit Namen")
    func beschaedigt() throws {
        let ablageOrdner = try ordner("ablage")
        defer { aufraeumen(ablageOrdner) }
        let ablage = Ablage(ordner: ablageOrdner)
        let t = try tresor()
        let fremder = try tresor()
        let faelle: [(String, Data, String)] = [
            ("Unsinn", Data("kein Behälter, kein JSON".utf8), "kein Behälter"),
            ("fremder Schlüssel",
             try fremder.versiegeln(try Ordnerzugriff.nutzlast(eintraege: [:], zielordner: ""),
                                    inhalt: .lesezeichen, ziel: .ablage),
             "anderen Schlüssel"),
            ("falscher Inhalt",
             try t.versiegeln(Data("{}".utf8), inhalt: .planung, ziel: .ablage), "Inhalt „planung“"),
            ("Nutzlast beschädigt",
             try t.versiegeln(Data("{\"version\":1}".utf8), inhalt: .lesezeichen, ziel: .ablage), "Nutzlast"),
        ]
        for (nummer, (name, roh, erwartet)) in faelle.enumerated() {
            try roh.write(to: ablage.lesezeichen)
            let zugriff = Ordnerzugriff(ablage: ablage)
            zugriff.schliessen()
            let befund = zugriff.oeffnen(mit: t, stempel: "fall-\(nummer)")
            guard case .beiseitegelegt(let grund, let rettung, let versiegelt) = befund else {
                Issue.record("\(name): erwartet beiseitegelegt, war \(befund)")
                continue
            }
            #expect(grund.contains(erwartet), "\(name): \(grund)")
            // Ein fremder Schlüssel ist keine Beschädigung — der Name sagt es.
            let art = name == "fremder Schlüssel" ? "fremd" : "beschaedigt"
            #expect(rettung == "lesezeichen-\(art)-fall-\(nummer).json" && versiegelt == 0, "\(name): \(rettung)")
            #expect(try Data(contentsOf: ablageOrdner.appending(component: rettung)) == roh,
                    "\(name): die Rettungskopie ist das Original")
            #expect(zugriff.quelle == .behaelter && zugriff.alle.isEmpty && zugriff.zielordner.isEmpty)
            let frisch = try behaelterKopf(ablage)
            #expect(frisch.kennung == t.kennung, "\(name): ein leerer Behälter unter dem eigenen Schlüssel")
            #expect(try Ordnerzugriff.nutzlastLesen(try t.oeffnen(kopf: frisch)).eintraege.isEmpty)
        }
        // Die Rettungskopien stehen im Register der Nebendateien — jeder
        // Wechsel der Hülle zieht sie nach.
        #expect(try ablage.nebendateien().count == faelle.count)
    }

    /// Die eine Frage der Nachwahl — statt `zustaendig == nil`, das vier Lagen mischt.
    @Test("zugang(fuer:) nennt offen, nie gewählt und noch zu")
    func zugang() throws {
        let ablageOrdner = try ordner("ablage")
        let material = try ordner("material")
        let anderes = try ordner("anderes")
        defer { aufraeumen(ablageOrdner, material, anderes) }
        let zugriff = Ordnerzugriff(ablage: Ablage(ordner: ablageOrdner))
        #expect(zugriff.zugang(fuer: material.path) == .nieGewaehlt)
        let eintrag = try zugriff.merken(material)
        #expect(zugriff.zugang(fuer: material.appending(component: "tief/er.pdf").path) == .offen(eintrag))
        #expect(zugriff.zugang(fuer: anderes.path) == .nieGewaehlt)
        zugriff.schliessen()
        #expect(zugriff.zugang(fuer: material.path) == .nochZu)
    }

    /// Der Schlüssel eines Ortes ist lexikalisch: Symlinks bleiben, wie gewählt
    /// — das Auflösen bräuchte Zugriff, den der nächste Start noch nicht hat.
    @Test("Der Schlüssel eines Ortes ist lexikalisch — ein Symlink bleibt, wie gewählt")
    func kanonischLexikalisch() throws {
        #expect(Ordnerzugriff.kanonisch("/tmp/a/./b/../c/") == "/tmp/a/c")
        #expect(Ordnerzugriff.kanonisch("/private/tmp/x") == "/tmp/x")
        #expect(Ordnerzugriff.kanonisch("/private/var/folders/y/") == "/var/folders/y")
        #expect(Ordnerzugriff.kanonisch("/private/etc") == "/etc")
        #expect(Ordnerzugriff.kanonisch("/privateer/x") == "/privateer/x")
        #expect(Ordnerzugriff.kanonisch("/") == "/" && Ordnerzugriff.kanonisch("/..") == "/")

        let wurzel = try ordner("symlink")
        defer { aufraeumen(wurzel) }
        let echt = wurzel.appending(component: "echt", directoryHint: .isDirectory)
        let link = wurzel.appending(component: "link", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: echt, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: echt)
        try Data("dahinter".utf8).write(to: echt.appending(component: "notiz.txt"))
        #expect(Ordnerzugriff.kanonisch(link.path).hasSuffix("/link"), "nicht aufgelöst")
        #expect(Ablage.vergleichbar(link.path).hasSuffix("/echt"), "die Schranke des Prüfordners löst weiter auf")

        let zugriff = Ordnerzugriff(ablage: Ablage(ordner: wurzel))
        let eintrag = try zugriff.merken(link)
        #expect(eintrag == Ordnerzugriff.kanonisch(link.path))
        let datei = link.appending(component: "notiz.txt").path
        #expect(zugriff.zustaendig(fuer: datei) == eintrag)
        #expect(zugriff.zustaendig(fuer: echt.path) == nil, "der wirkliche Ort ist ein anderer Schlüssel")
        #expect(try zugriff.mit(datei) { try String(contentsOf: $0, encoding: .utf8) } == "dahinter")
    }

    @Test("Unlesbar oder aus einer neueren Fassung: der Behälter bleibt liegen, der Vorrat ist gesperrt")
    func gesperrt() throws {
        let ablageOrdner = try ordner("ablage")
        let material = try ordner("material")
        defer { aufraeumen(ablageOrdner, material) }
        let ablage = Ablage(ordner: ablageOrdner)
        let t = try tresor()
        let gueltig = try t.versiegeln(try Ordnerzugriff.nutzlast(eintraege: [:], zielordner: ""),
                                       inhalt: .lesezeichen, ziel: .ablage)
        let neuer = Data(String(decoding: gueltig, as: UTF8.self)
                            .replacingOccurrences(of: "\"version\":1", with: "\"version\":2").utf8)
        try neuer.write(to: ablage.lesezeichen)

        let zugriff = Ordnerzugriff(ablage: ablage)
        zugriff.schliessen()
        guard case .gesperrt(let grund) = zugriff.oeffnen(mit: t, stempel: "s") else {
            Issue.record("erwartet gesperrt"); return
        }
        #expect(grund.contains("neueren Fassung") && zugriff.sperrgrund == grund && !zugriff.schreibbar)
        #expect(zugriff.zugang(fuer: material.path) == .gesperrt(grund))
        #expect(try Data(contentsOf: ablage.lesezeichen) == neuer, "unangetastet")
        #expect(zugriff.zustaendig(fuer: material.path) == nil && zugriff.alle.isEmpty)
        #expect(throws: Ordnerzugriff.Fehler.self) { try zugriff.merken(material) }
        do { _ = try zugriff.merken(material) } catch let fehler as Ordnerzugriff.Fehler {
            #expect(fehler.art == .gesperrt && fehler.text.contains("nächsten Start"))
        }
        zugriff.zielordner = "/anderswo"
        #expect(zugriff.zielordner.isEmpty && zugriff.versiegeln(unter: t) != nil)
        #expect(try Data(contentsOf: ablage.lesezeichen) == neuer, "auch danach unangetastet")
        // Aufheben lässt den Behälter liegen — er trägt Chiffrat unter einem fremden Schlüssel.
        #expect(!zugriff.entsiegeln() && zugriff.quelle == .einstellungen)
        #expect(FileManager.default.fileExists(atPath: ablage.lesezeichen.path))
    }

    @Test("Kein Behälter beim Öffnen: der Klartext-Vorrat wird versiegelt — der erste Start dieser Fassung")
    func nachruesten() throws {
        let ablageOrdner = try ordner("ablage")
        let ziel = try ordner("ziel")
        let material = try ordner("material")
        defer { aufraeumen(ablageOrdner, ziel, material) }
        let ablage = Ablage(ordner: ablageOrdner)
        let (zugriff, eintrag) = try vorrat(ablage, material: material, ziel: ziel)
        let t = try tresor()

        zugriff.schliessen()
        #expect(zugriff.zustaendig(fuer: material.path) == nil, "zu, obwohl der Klartext im Speicher liegt")
        #expect(zugriff.oeffnen(mit: t, stempel: "s") == .angelegt(1, zielordner: true))
        #expect(zugriff.quelle == .behaelter && zugriff.zustaendig(fuer: material.path) == eintrag)
        let gelesen = try Ordnerzugriff.nutzlastLesen(try t.oeffnen(kopf: try behaelterKopf(ablage)))
        #expect(gelesen.eintraege == zugriff.eintraege && gelesen.zielordner == ziel.path)

        // Ohne alles: angelegt, aber nichts zu melden.
        let leerOrdner = try ordner("leer")
        defer { aufraeumen(leerOrdner) }
        let leer = Ordnerzugriff(ablage: Ablage(ordner: leerOrdner))
        leer.schliessen()
        #expect(leer.oeffnen(mit: t, stempel: "s") == .angelegt(0, zielordner: false))
    }

    @Test("Lässt sich der Behälter nicht schreiben, bleibt nichts im Klartext: der Vorrat gilt für die Sitzung, ungesichert")
    func schreibenScheitert() throws {
        let ablageOrdner = try ordner("ablage-zu")
        let material = try ordner("material")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ablageOrdner.path)
            aufraeumen(ablageOrdner, material)
        }
        let ablage = Ablage(ordner: ablageOrdner)
        let zugriff = Ordnerzugriff(ablage: ablage)
        let eintrag = try zugriff.merken(material)
        let t = try tresor()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ablageOrdner.path)

        let grund = zugriff.versiegeln(unter: t)
        #expect(grund != nil && !(grund ?? "").isEmpty)
        #expect(zugriff.quelle == .einstellungen && zugriff.zustaendig(fuer: material.path) == eintrag)
        #expect(!FileManager.default.fileExists(atPath: ablage.lesezeichen.path))

        zugriff.schliessen()
        guard case .ungesichert = zugriff.oeffnen(mit: t, stempel: "s") else {
            Issue.record("erwartet: ungesichert")
            return
        }
        #expect(zugriff.quelle == .behaelter && zugriff.ungesichert != nil, "kein Rückfall in den Klartext")
        #expect(zugriff.zustaendig(fuer: material.path) == eintrag, "gilt für die Sitzung")

        // Im Behälter-Zustand: das Merken gilt für die Sitzung, die Störung wird gemeldet.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ablageOrdner.path)
        #expect(zugriff.versiegeln(unter: t) == nil && zugriff.ungesichert == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ablageOrdner.path)
        var gemeldet: [String] = []
        zugriff.melden = { text, _ in gemeldet.append(text) }
        let zweites = try ordner("zweites")
        defer { aufraeumen(zweites) }
        let zweiterEintrag = try zugriff.merken(zweites)
        #expect(zugriff.zustaendig(fuer: zweites.path) == zweiterEintrag, "gilt für die Sitzung")
        #expect(gemeldet.count == 1 && gemeldet[0].contains("nicht versiegelt sichern"))
    }

    /// Einstellungen im Speicher — kein Prüflauf hinterlässt eine Datei unter `~/Library/Preferences`.
    private final class Einstellungsattrappe: Einstellungsspeicher, @unchecked Sendable {
        var werte: [String: Any] = [:]
        func object(forKey defaultName: String) -> Any? { werte[defaultName] }
        func dictionary(forKey defaultName: String) -> [String: Any]? { werte[defaultName] as? [String: Any] }
        func string(forKey defaultName: String) -> String? { werte[defaultName] as? String }
        func set(_ value: Any?, forKey defaultName: String) { werte[defaultName] = value }
        func removeObject(forKey defaultName: String) { werte.removeValue(forKey: defaultName) }
    }

    @Test("Mit Einstellungen: der Klartext-Vorrat steht dort, verschwindet beim Versiegeln und kommt beim Entsiegeln zurück")
    func einstellungen() throws {
        let ablageOrdner = try ordner("ablage")
        let ziel = try ordner("ziel")
        let material = try ordner("material")
        let einstellungen = Einstellungsattrappe()
        defer { aufraeumen(ablageOrdner, ziel, material) }
        let ablage = Ablage(ordner: ablageOrdner)
        let zugriff = Ordnerzugriff(ablage: ablage, einstellungen: einstellungen)
        let eintrag = try zugriff.merken(material)
        zugriff.zielordner = ziel.path
        #expect(einstellungen.dictionary(forKey: "unterrichtsplanung.lesezeichen")?.keys.sorted() == [eintrag])
        #expect(einstellungen.string(forKey: Einstellungen.Schluessel.autoexportOrdner) == ziel.path)

        // Ein zweiter Zugriff liest die Einstellungen — wie nach einem Neustart im Klartext.
        let neustart = Ordnerzugriff(ablage: ablage, einstellungen: einstellungen)
        #expect(neustart.eintraege == zugriff.eintraege && neustart.zielordner == ziel.path)

        let t = try tresor()
        #expect(zugriff.versiegeln(unter: t) == nil)
        #expect(einstellungen.dictionary(forKey: "unterrichtsplanung.lesezeichen") == nil, "kein Lesezeichen im Klartext")
        #expect(einstellungen.string(forKey: Einstellungen.Schluessel.autoexportOrdner) == nil, "kein Pfad im Klartext")
        try zugriff.merken(ziel)
        #expect(einstellungen.dictionary(forKey: "unterrichtsplanung.lesezeichen") == nil, "auch später nicht")

        zugriff.entsiegeln()
        #expect(einstellungen.dictionary(forKey: "unterrichtsplanung.lesezeichen")?.count == 2)
        #expect(einstellungen.string(forKey: Einstellungen.Schluessel.autoexportOrdner) == ziel.path)

        // Der erste Start dieser Fassung: aus den Einstellungen in den Behälter, die Einstellungen leer.
        let dritter = Ordnerzugriff(ablage: ablage, einstellungen: einstellungen)
        dritter.schliessen()
        #expect(dritter.oeffnen(mit: t, stempel: "s") == .angelegt(2, zielordner: true))
        #expect(einstellungen.dictionary(forKey: "unterrichtsplanung.lesezeichen") == nil)
        #expect(einstellungen.string(forKey: Einstellungen.Schluessel.autoexportOrdner) == nil)
        #expect(dritter.zielordner == ziel.path && dritter.eintraege == zugriff.eintraege)
    }

    // ── Der Speicher hinter versiegelter Ablage ─────────────────────

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Versiegelt", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Bits",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    @Test("Start hinter versiegelter Ablage: zu bis zum Entsperren, dann aus dem Behälter — ohne Nachwahl")
    func startGesperrt() async throws {
        let ablageOrdner = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { aufraeumen(ablageOrdner, ziel) }
        // Einrichten: Planung, Zielordner samt Lesezeichen, Verschlüsselung an.
        let erster = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        erster.planung = try planung()
        erster.autoexportZielSetzen(ziel.path)
        _ = try erster.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(erster.verschluesselungEinschalten().lesezeichen == .erledigt)
        let lesezeichenVorher = erster.zugriff.eintraege
        #expect(!lesezeichenVorher.isEmpty)

        // Neuer Prozessstart nachgestellt: ein zweiter Speicher an derselben Ablage kennt nichts.
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        zweiter.nachwahlProbe = true
        zweiter.starten()
        #expect(zweiter.verschluesselungsstand == .gesperrt)
        #expect(zweiter.zugriff.quelle == .zu)
        #expect(zweiter.autoexportOrdner.isEmpty, "vor dem Entsperren kein Zielordner")
        #expect(zweiter.zugriff.zustaendig(fuer: ziel.path) == nil)
        #expect(zweiter.ausstehendeFreigaben.isEmpty, "nichts fragt vor dem Entsperren nach einem Ort")

        await zweiter.entsperren(passphrase: passphrase)
        #expect(zweiter.verschluesselungsstand == .an && zweiter.planung?.titel == "Versiegelt")
        #expect(zweiter.zugriff.quelle == .behaelter)
        #expect(zweiter.autoexportOrdner == ziel.path, "der Zielordner kommt aus dem Behälter")
        #expect(zweiter.zugriff.eintraege == lesezeichenVorher, "die Lesezeichen Byte für Byte")
        #expect(zweiter.zugriff.zustaendig(fuer: ziel.path) != nil)
        #expect(zweiter.ausstehendeFreigaben.isEmpty, "keine Nachwahl: alles liegt im Behälter")
        #expect(!zweiter.meldungen.contains { $0.art == .warnung }, "nichts zu warnen")

        // Aufheben und wieder einschalten: die Lesezeichen gehen mit — hin und zurück.
        zweiter.verschluesselungAufheben()
        #expect(zweiter.zugriff.quelle == .einstellungen && zweiter.zugriff.eintraege == lesezeichenVorher)
        _ = try zweiter.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(zweiter.verschluesselungEinschalten().lesezeichen == .erledigt)
        #expect(zweiter.zugriff.quelle == .behaelter && zweiter.zugriff.eintraege == lesezeichenVorher)
    }

    @Test("Der erste Start dieser Fassung hinter versiegelter Ablage: der Klartext-Vorrat zieht in den Behälter")
    func startMitKlartextVorrat() async throws {
        let ablageOrdner = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { aufraeumen(ablageOrdner, ziel) }
        let erster = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        erster.planung = try planung()
        _ = try erster.verschluesselungVorbereiten(passphrase: passphrase)
        erster.verschluesselungEinschalten()
        // Wie eine ältere Fassung: Ablage versiegelt, Lesezeichen noch im Klartext, kein Behälter.
        Ablage(ordner: ablageOrdner).lesezeichenEntfernen()

        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        zweiter.nachwahlProbe = true
        // Der Klartext-Vorrat, wie ihn die Einstellungen trügen — im Prüflauf im Speicher.
        try zweiter.zugriff.merken(ziel)
        zweiter.zugriff.zielordner = ziel.path
        zweiter.starten()
        #expect(zweiter.zugriff.quelle == .zu && zweiter.autoexportOrdner.isEmpty)

        await zweiter.entsperren(passphrase: passphrase)
        #expect(zweiter.zugriff.quelle == .behaelter && zweiter.autoexportOrdner == ziel.path)
        #expect(FileManager.default.fileExists(atPath: Ablage(ordner: ablageOrdner).lesezeichen.path))
        #expect(zweiter.meldungen.contains { $0.text.contains("liegen jetzt versiegelt") && $0.art == .hinweis })
        #expect(zweiter.ausstehendeFreigaben.isEmpty)
    }

    @Test("Ein beschädigter Behälter beim Start wird benannt und beiseitegelegt; die Planung öffnet trotzdem")
    func startMitBeschaedigtemBehaelter() async throws {
        let ablageOrdner = try ordner("ablage")
        defer { aufraeumen(ablageOrdner) }
        let erster = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        erster.planung = try planung()
        _ = try erster.verschluesselungVorbereiten(passphrase: passphrase)
        erster.verschluesselungEinschalten()
        try Data("Unsinn".utf8).write(to: Ablage(ordner: ablageOrdner).lesezeichen)

        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        #expect(zweiter.planung?.titel == "Versiegelt" && zweiter.zugriff.quelle == .behaelter)
        let warnung = try #require(zweiter.meldungen.first { $0.text.contains("Behälter der Lesezeichen") })
        #expect(warnung.art == .warnung && warnung.text.contains("lesezeichen-beschaedigt-"))
        let rettungen = try FileManager.default.contentsOfDirectory(atPath: ablageOrdner.path)
            .filter { $0.hasPrefix("lesezeichen-beschaedigt-") }
        #expect(rettungen.count == 1)
    }
}
