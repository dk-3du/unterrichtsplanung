// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Eine Schreibsperre der Ablage, die nur die genannten Anfragen abweist (gezählt ab 1) — gelesen auf jedem Faden.
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

// ── Ersetzte Kennungen und Verlust im Archiv (B101, E456 a) ───────────────
// Das Lesen ersetzt eine Kennung, die leer, außerhalb des Musters oder
// doppelt ist, durch eine zufällige — im Archiv die eines Schuljahrs, in der
// Jahresdatei eines Schuljahrs die einer Person (dort als bereinigtes Jahr
// gezählt, ein Verlust). Blieb das Archiv, wie es lag, würfelte jedes Lesen
// neu, und eine Löschung nach Kennung ging beim ersten Versuch ins Leere.
// Wie bei der Jahresdatei (B93, E419): erst das Original bewahren, dann das
// Archiv einmal schreiben.

@Suite("Archiv mit Verlust oder ersetzten Kennungen: das Original bewahrt, einmal geschrieben — die Löschung trifft (B101, E456)")
@MainActor
struct ArchivErsetzteKennungenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private static let stempel = "2026-10-03T08:00:00.000Z"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "archiv-ersetzt-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func aufraeumen(_ ort: URL) { try? FileManager.default.removeItem(at: ort) }

    private func tresor() throws -> Tresor {
        let t = Tresor.neu()
        try t.passphraseSetzen(passphrase, runden: Tresor.rundenMindestens)
        return t
    }

    /// Zwei Schuljahre (`j-1` 2024/25, `j-2` 2025/26), je mit der Jahresdatei des Prüfentwurfs — als Objekt,
    /// wie es von fremder Hand liegen kann.
    private func archivObjekt() throws -> [String: Any] {
        func jahr(_ id: String, _ schuljahr: String, _ beginn: String) throws -> Archivjahr {
            let planung = Planung.leer(titel: "Prüfvektor \(schuljahr)", start: try #require(Tag(iso: beginn)), wochen: 4,
                                       basis: "", klassen: [], fachfarben: [:])
            return Archivjahr(id: id, schuljahr: schuljahr, archiviert: Self.stempel, planung: planung,
                              lernende: RuecknahmeLernendenPruefungen.entwurf())
        }
        let archiv = Archivbestand(geaendert: Self.stempel, jahre: [try jahr("j-1", "2024/25", "2024-08-05"),
                                                                    try jahr("j-2", "2025/26", "2025-08-04")])
        return try #require(JSONSerialization.jsonObject(with: try Archivdatei.schreiben(archiv)) as? [String: Any])
    }

    /// Ein Schuljahr des Objekts ändern.
    private func jahrAendern(_ objekt: inout [String: Any], _ stelle: Int, _ aendern: (inout [String: Any]) -> Void) throws {
        var jahre = try #require(objekt["jahre"] as? [[String: Any]])
        aendern(&jahre[stelle])
        objekt["jahre"] = jahre
    }

    /// Die Kennung des ersten Schuljahrs außerhalb des Musters — ersetzt, kein Verlust.
    private func jahrErsetzt() throws -> [String: Any] {
        var objekt = try archivObjekt()
        try jahrAendern(&objekt, 0) { $0["id"] = "j 1" }
        return objekt
    }

    /// Ben im ersten Schuljahr unter einer Kennung außerhalb des Musters — das Jahr gilt als bereinigt (Verlust).
    private func personErsetzt() throws -> [String: Any] {
        var objekt = try archivObjekt()
        try jahrAendern(&objekt, 0) {
            var lernende = $0["lernende"] as? [String: Any] ?? [:]
            var personen = lernende["lernende"] as? [[String: Any]] ?? []
            personen[1]["id"] = "b 2"
            lernende["lernende"] = personen
            $0["lernende"] = lernende
        }
        return objekt
    }

    private func versiegelt(_ objekt: [String: Any], _ t: Tresor) throws -> Data {
        try t.versiegeln(try JSONSerialization.data(withJSONObject: objekt), inhalt: .archiv, ziel: .ablage)
    }

    /// Was auf der Platte steht, geöffnet und gelesen.
    private func platte(_ ort: URL, _ t: Tresor) throws -> (bestand: Archivbestand, bilanz: Archivdatei.Bilanz) {
        let roh = try Data(contentsOf: Ablage(ordner: ort).archiv)
        return try Archivdatei.lesenMitBilanz(try t.oeffnen(kopf: try Tresor.kopfLesen(roh)))
    }

    private func archivmeldungen(_ s: Planungsspeicher) -> [String] {
        s.meldungen.map(\.text).filter { $0.hasPrefix("Das Archiv wurde beim Lesen bereinigt") }
    }

    private func kopie(_ ort: URL, _ stempel: String) -> Data? {
        try? Data(contentsOf: ort.appending(component: "archiv-bereinigt-\(stempel).json"))
    }

    private func kopien(_ ort: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: ort.path)) ?? []).filter { $0.hasPrefix("archiv-bereinigt-") }
    }

    // ── Der Hauptweg: die Löschung im Blatt ───────────────────────────────

    /// Eingeschaltet, mit dem Archiv `objekt` unter dem Schlüssel der Sitzung; das Archiv steht im Blatt,
    /// dort hängt die Frage (E418). Liefert auch das Original, wie es lag.
    private func speicher(_ ort: URL, archiv objekt: [String: Any]) async throws -> (Planungsspeicher, original: Data) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                                 basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let original = try versiegelt(objekt, try #require(s.tresor))
        try original.write(to: Ablage(ordner: ort).archiv)
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        s.offenerDialog = .lernende
        return (s, original)
    }

    /// Wie das Blatt das Archiv liest: abseits des Hauptstrangs — `nil`, wenn es sich nicht lesen lässt.
    private func gezeigt(_ s: Planungsspeicher) async -> Archivbestand? {
        guard case .gelesen(let archiv, _, _) = await s.lernende.archivLesenAsynchron(stempel: Zeitrechnung.dateistempel()) else {
            return nil
        }
        return archiv
    }

    @Test("Ein Schuljahr mit ersetzter Kennung: Die Löschung trifft beim ersten Versuch, das Original liegt einmal bewahrt (B101)")
    func jahrLoeschungTrifft() async throws {
        let ort = try ordner("jahr")
        defer { aufraeumen(ort) }
        let (s, original) = try await speicher(ort, archiv: try jahrErsetzt())
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let t = try #require(s.tresor)
        let archiv = try #require(await gezeigt(s), "das Archiv ist lesbar")
        let ziel = try #require(archiv.jahre.first { $0.schuljahr == "2024/25" }).id
        var geschrieben = 0
        var grund: String?
        let vorher = s.lernende.archivEntschluesselungen
        s.archivJahrLoeschenFragen(ziel, in: archiv) { neu in grund = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let loeschungGeschrieben = await uhr.vorruecken(bis: { geschrieben == 1 }, hoechstens: .seconds(1))
        try #require(loeschungGeschrieben, "die Löschung ist geschrieben")
        let zahl = s.lernende.archivEntschluesselungen - vorher
        let danach = try platte(ort, t)
        #expect(grund == nil, Comment(rawValue: grund ?? "—"))
        #expect(danach.bestand.jahre.map(\.schuljahr) == ["2025/26"],
                Comment(rawValue: "Schuljahre danach: \(danach.bestand.jahre.map(\.schuljahr))"))
        let bewahrt = kopien(ort)
        #expect(bewahrt.count == 1 && bewahrt.first.flatMap { try? Data(contentsOf: ort.appending(component: $0)) } == original,
                Comment(rawValue: "Rettungskopien: \(bewahrt)"))
        // Das Zusammenspiel mit B94: Die Löschung selbst entschlüsselt zweimal — gelesen abseits (F-02), zurückgeprüft auf
        // dem Hauptstrang; gezählt wird dort.
        #expect(zahl == 1, Comment(rawValue: "Entschlüsselungen der Löschung auf dem Hauptstrang: \(zahl)"))
    }

    @Test("Eine Person mit ersetzter Kennung (bereinigtes Jahr): Die Löschung trifft beim ersten Versuch (B101)")
    func personLoeschungTrifft() async throws {
        let ort = try ordner("person")
        defer { aufraeumen(ort) }
        let (s, original) = try await speicher(ort, archiv: try personErsetzt())
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let t = try #require(s.tresor)
        let archiv = try #require(await gezeigt(s), "das Archiv ist lesbar")
        let ben = try #require(archiv.jahre.first?.lernende?.lernende.first { $0.vorname == "Ben" }).id
        var geschrieben = 0
        var grund: String?
        s.archivPersonLoeschenFragen(ben, in: archiv) { neu in grund = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let loeschungGeschrieben = await uhr.vorruecken(bis: { geschrieben == 1 }, hoechstens: .seconds(1))
        try #require(loeschungGeschrieben, "die Löschung ist geschrieben")
        let danach = try platte(ort, t).bestand
        let personen = danach.jahre.first?.lernende?.lernende.map(\.vorname) ?? []
        #expect(grund == nil, Comment(rawValue: grund ?? "—"))
        #expect(personen == ["Anna", "Cem"], Comment(rawValue: "Personen im ersten Schuljahr danach: \(personen)"))
        let bewahrt = kopien(ort)
        #expect(bewahrt.count == 1 && bewahrt.first.flatMap { try? Data(contentsOf: ort.appending(component: $0)) } == original,
                Comment(rawValue: "Rettungskopien: \(bewahrt)"))
    }

    // ── Der Dienst ────────────────────────────────────────────────────────

    @Test("Ersetzte Kennung oder Verlust: das Original als Rettungskopie bewahrt, das Archiv einmal geschrieben — ein zweites Lesen vergibt keine neuen (E46, E456)")
    func dienstSchreibtEinmal() throws {
        var verlust = try archivObjekt()
        try jahrAendern(&verlust, 1) { $0["planung"] = "keine Planung" }  // ein Jahr übergangen
        let faelle: [(fall: String, objekt: [String: Any])] = [
            ("jahr-ersetzt", try jahrErsetzt()), ("person-ersetzt", try personErsetzt()), ("verlust", verlust),
        ]
        for (fall, objekt) in faelle {
            let ort = try ordner(fall)
            defer { aufraeumen(ort) }
            let ablage = Ablage(ordner: ort)
            let t = try tresor()
            let original = try versiegelt(objekt, t)
            try original.write(to: ablage.archiv)
            let dienst = Lernendendienst(ablage: ablage)
            _ = dienst.oeffnen(mit: t, stempel: "s0")

            let erster = dienst.archivLesen(stempel: "s1")
            guard case .gelesen(let gelesen, let bilanz, let k) = erster else {
                Issue.record("\(fall): erwartet gelesen — \(erster)")
                continue
            }
            #expect(!bilanz.istLeer && k == "archiv-bereinigt-s1.json", Comment(rawValue: "\(fall): \(erster)"))
            #expect(kopie(ort, "s1") == original, Comment(rawValue: "\(fall): Das Original liegt als Rettungskopie daneben (E46)"))
            let (aufDerPlatte, bilanzDort) = try platte(ort, t)
            #expect(try Archivdatei.schreiben(aufDerPlatte) == Archivdatei.schreiben(gelesen) && bilanzDort.istLeer,
                    Comment(rawValue: "\(fall): Die Platte trägt, was gelesen wurde — dort: \(bilanzDort.beschreibung)"))

            let zweiter = dienst.archivLesen(stempel: "s2")
            guard case .gelesen(let wieder, let bilanz2, let k2) = zweiter else {
                Issue.record("\(fall): erwartet gelesen — \(zweiter)")
                continue
            }
            #expect(bilanz2.istLeer && k2 == nil && kopie(ort, "s2") == nil, Comment(rawValue: "\(fall): \(zweiter)"))
            #expect(try Archivdatei.schreiben(wieder) == Archivdatei.schreiben(gelesen),
                    Comment(rawValue: "\(fall): dieselben Kennungen beim zweiten Lesen"))
        }
    }

    @Test("Übereifer-Gegenprobe: sauber oder nur ein geleerter Zeitstempel — das Lesen schreibt nicht und kopiert nicht (E46)")
    func ohneBefundUnangetastet() throws {
        let sauber = try archivObjekt()
        var normiert = sauber
        normiert["geaendert"] = "gestern"  // geleert und gezählt, kein Verlust
        for (fall, objekt) in [("sauber", sauber), ("normiert", normiert)] {
            let ort = try ordner(fall)
            defer { aufraeumen(ort) }
            let ablage = Ablage(ordner: ort)
            let t = try tresor()
            let original = try versiegelt(objekt, t)
            try original.write(to: ablage.archiv)
            let dienst = Lernendendienst(ablage: ablage)
            _ = dienst.oeffnen(mit: t, stempel: "s0")
            let befund = dienst.archivLesen(stempel: "s1")
            guard case .gelesen(_, let bilanz, let k) = befund else {
                Issue.record("\(fall): erwartet gelesen — \(befund)")
                continue
            }
            #expect(bilanz.istLeer == (fall == "sauber") && k == nil, Comment(rawValue: "\(fall): \(befund)"))
            #expect(try Data(contentsOf: ablage.archiv) == original, Comment(rawValue: "\(fall): beim Lesen geschrieben"))
            #expect(kopien(ort).isEmpty, Comment(rawValue: "\(fall): Rettungskopien \(kopien(ort))"))
        }
    }

    @Test("Lässt sich das Original nicht bewahren, gilt das Archiv als nicht lesbar — nichts geht darüber (E46)")
    func kopieScheitert() throws {
        for (fall, objekt) in [("jahr-ersetzt", try jahrErsetzt()), ("person-ersetzt", try personErsetzt())] {
            let ort = try ordner("kopie-\(fall)")
            defer { aufraeumen(ort) }
            let ablage = Ablage(ordner: ort)
            let t = try tresor()
            let original = try versiegelt(objekt, t)
            try original.write(to: ablage.archiv)
            let dienst = Lernendendienst(ablage: ablage)
            _ = dienst.oeffnen(mit: t, stempel: "s0")
            // Nur die Kopie scheitert, das Schreiben bliebe offen (Z-AV6-04): Am Ort der Kopie liegt ein Ordner mit
            // einer unveränderlichen Datei, den `dateiKopieren` weder entfernen noch überschreiben kann.
            let sperrort = ort.appending(component: "archiv-bereinigt-s1.json", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: sperrort, withIntermediateDirectories: true)
            let fest = sperrort.appending(component: "fest")
            try Data("fest".utf8).write(to: fest)
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: fest.path)
            defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: fest.path) }
            let befund = dienst.archivLesen(stempel: "s1")
            if case .nichtLesbar(let grund) = befund {
                #expect(grund.contains("Original ließ sich nicht bewahren"), Comment(rawValue: "\(fall): \(grund)"))
            } else {
                Issue.record("\(fall): erwartet nicht lesbar — \(befund)")
            }
            #expect(try Data(contentsOf: ablage.archiv) == original, Comment(rawValue: "\(fall): Ohne Kopie geht nichts über die Datei"))
            #expect((try? FileManager.default.contentsOfDirectory(atPath: sperrort.path)) == ["fest"], "keine Kopie entstanden")
        }
    }

    @Test("Ist das Schreiben gesperrt (ein Übergang offen: Ablage und Dienst zugleich), wird gelesen, wie es liegt — keine Kopie, keine Meldung, auch beim zweiten Lesen (E472, I2-01)")
    func schreibenGesperrt() throws {
        let ort = try ordner("gesperrt")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try versiegelt(try jahrErsetzt(), t)
        try original.write(to: ablage.archiv)
        let dienst = Lernendendienst(ablage: ablage)
        _ = dienst.oeffnen(mit: t, stempel: "s0")
        let merker = Meldungsmerker()
        dienst.melden = { text, _ in merker.texte.append(text) }
        ablage.schreibsperre = { "eine Prüfsperre" }
        dienst.schreibsperre = { "eine Prüfsperre" }
        for stempel in ["s1", "s2"] {
            let befund = dienst.archivLesen(stempel: stempel)
            var ohneKopie = false
            if case .gelesen(_, let bilanz, nil) = befund, bilanz.ersetzteKennungen == 1 { ohneKopie = true }
            #expect(ohneKopie, Comment(rawValue: "\(stempel): erwartet gelesen ohne Kopie — \(befund)"))
        }
        let liegt = (try? FileManager.default.contentsOfDirectory(atPath: ort.path)) ?? []
        #expect(!liegt.contains { $0.hasPrefix("archiv-bereinigt-") } && merker.texte.isEmpty,
                Comment(rawValue: "\(liegt) · \(merker.texte)"))
        #expect(try Data(contentsOf: ablage.archiv) == original, "die Datei bleibt, wie sie lag")
    }

    @Test("Ein bereinigtes Lesen ohne Kopie (das Schreiben war gesperrt) gibt das Schreiben nicht frei — auch wenn die Sperre inzwischen offen ist (E456, Z-AV10-01)")
    func setzenOhneBewahrtesOriginal() throws {
        let ort = try ordner("ohne-kopie")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try versiegelt(try jahrErsetzt(), t)
        try original.write(to: ablage.archiv)
        let dienst = Lernendendienst(ablage: ablage)
        _ = dienst.oeffnen(mit: t, stempel: "s0")
        ablage.schreibsperre = { "eine Prüfsperre" }
        dienst.schreibsperre = { "eine Prüfsperre" }
        let befund = dienst.archivLesen(stempel: "s1")
        guard case .gelesen(let archiv, _, nil) = befund else {
            Issue.record("erwartet gelesen ohne Kopie — \(befund)")
            return
        }
        // Das Nachholen in der Sperre vollendet den Übergang — beim Setzen ist sie offen.
        ablage.schreibsperre = nil
        dienst.schreibsperre = nil
        let grund = dienst.archivSetzen(Archivbestand(geaendert: Self.stempel, jahre: Array(archiv.jahre.prefix(1))),
                                        stempel: "s2", gelesen: befund)
        #expect(grund?.contains("Original") == true, Comment(rawValue: grund ?? "—"))
        #expect(try Data(contentsOf: ablage.archiv) == original, "nichts geschrieben")
        #expect(kopie(ort, "s2") == nil)
    }

    @Test("Ist das Schreiben gesperrt, scheitert eine bestätigte Löschung mit dem Grund der Sperre und zählt — auch für einen Eintrag mit ersetzter Kennung (Z-AV10-02, E464)")
    func loeschungUnterSperre() async throws {
        let ort = try ordner("loeschung-gesperrt")
        defer { aufraeumen(ort) }
        let (s, original) = try await speicher(ort, archiv: try jahrErsetzt())
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.sicherung.ablage.schreibsperre = { "eine Prüfsperre" }
        s.lernende.schreibsperre = { "eine Prüfsperre" }
        let archiv = try #require(await gezeigt(s), "das Archiv ist zu sehen")
        let ziel = try #require(archiv.jahre.first { $0.schuljahr == "2024/25" }).id
        let fehlerVorher = s.archivSchreibfehler
        var geschrieben = 0
        var grund: String?
        s.archivJahrLoeschenFragen(ziel, in: archiv) { neu in grund = s.archivSchreiben(neu); geschrieben += 1 }
        s.rueckfrageBeantworten(true)
        let versucht = await uhr.vorruecken(bis: {
            geschrieben == 1 || s.meldungen.contains { $0.text.contains("nicht mehr finden") }
        }, hoechstens: .seconds(1))
        try #require(versucht, "die Löschung ist versucht")
        #expect(grund?.contains("Prüfsperre") == true && s.archivSchreibfehler == fehlerVorher + 1,
                Comment(rawValue: "\(grund ?? "—") · Schreibfehler \(s.archivSchreibfehler - fehlerVorher)"))
        #expect(!s.meldungen.contains { $0.text.contains("nicht mehr finden") },
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.contains("nicht mehr finden") } }, hoechstens: .seconds(1))
        #expect(!erschienen, "auch danach nicht")
        #expect(geschrieben == 1 && s.archivSchreibfehler == fehlerVorher + 1, "auch danach ein Versuch")
        #expect(try Data(contentsOf: Ablage(ordner: ort).archiv) == original, "nichts geschrieben")
    }

    @Test("Liegt die Kopie und misslingt dann das Schreiben, bleibt das Archiv, wie es lag — die Warnung nennt den Grund (E472, I1-02)")
    func schreibenMisslingtNachDerKopie() throws {
        let ort = try ordner("schreiben")
        defer { aufraeumen(ort) }
        let ablage = Ablage(ordner: ort)
        let t = try tresor()
        let original = try versiegelt(try jahrErsetzt(), t)
        try original.write(to: ablage.archiv)
        let dienst = Lernendendienst(ablage: ablage)
        _ = dienst.oeffnen(mit: t, stempel: "s0")
        let merker = Meldungsmerker()
        dienst.melden = { text, _ in merker.texte.append(text) }
        // Die erste Anfrage am Tor stellt die Kopie, die zweite das Schreiben.
        let tor = Zaehltor(abweisen: [2])
        ablage.schreibsperre = { tor.grund }
        let befund = dienst.archivLesen(stempel: "s1")
        guard case .gelesen(_, let bilanz, let k) = befund else {
            Issue.record("erwartet gelesen — \(befund)")
            return
        }
        #expect(bilanz.ersetzteKennungen == 1 && k == "archiv-bereinigt-s1.json" && tor.anfragen == 2,
                Comment(rawValue: "\(befund) · Anfragen \(tor.anfragen)"))
        #expect(kopie(ort, "s1") == original)
        #expect(try Data(contentsOf: ablage.archiv) == original, "die Datei bleibt, wie sie lag")
        let einmal = merker.texte.count == 1
            && merker.texte[0].hasPrefix("Das Archiv wurde beim Lesen bereinigt — das Original liegt als „archiv-bereinigt-s1.json“ "
                                         + "neben der Planung. Das bereinigte Archiv ließ sich nicht schreiben (")
            && merker.texte[0].contains("Prüfsperre") && merker.texte[0].hasSuffix("das nächste Lesen versucht es erneut.")
        #expect(einmal, Comment(rawValue: merker.texte.joined(separator: " | ")))
    }

    @Test("Ein Lesen abseits des Hauptstrangs bewahrt und schreibt nur, wenn es nicht abgebrochen ist und die Datei seit dem Lesen unverändert liegt (Z-AV6-01)")
    func festschreibenNurAmGelesenen() {
        let stand = Lernendendienst.Dateistand(groesse: 10, geaendert: Date(timeIntervalSince1970: 1), knoten: 7)
        #expect(Lernendendienst.darfFestschreiben(abgebrochen: false, vorher: stand, jetzt: stand))
        #expect(!Lernendendienst.darfFestschreiben(abgebrochen: true, vorher: stand, jetzt: stand), "abgebrochen — das Blatt ist fort")
        #expect(!Lernendendienst.darfFestschreiben(abgebrochen: false, vorher: stand,
                                                   jetzt: .init(groesse: 10, geaendert: Date(timeIntervalSince1970: 2), knoten: 7)),
                "inzwischen geschrieben")
        #expect(!Lernendendienst.darfFestschreiben(abgebrochen: false, vorher: stand,
                                                   jetzt: .init(groesse: 10, geaendert: Date(timeIntervalSince1970: 1), knoten: 8)),
                "inzwischen ersetzt")
        #expect(!Lernendendienst.darfFestschreiben(abgebrochen: false, vorher: nil, jetzt: stand), "vorher nicht zu bestimmen")
        #expect(!Lernendendienst.darfFestschreiben(abgebrochen: false, vorher: stand, jetzt: nil), "inzwischen fort")
    }

    @Test("Bereinigt ein Lesen das Archiv, meldet es das einmal, wo die Kopie entsteht — auf jedem Weg, auch beim Prüfen vor „Verschlüsselung aufheben“ (Z-AV6-03)")
    func bereinigungGemeldet() async throws {
        for (fall, objekt) in [("jahr-ersetzt", try jahrErsetzt()), ("person-ersetzt", try personErsetzt())] {
            let ort = try ordner("meldung-\(fall)")
            defer { aufraeumen(ort) }
            let (s, _) = try await speicher(ort, archiv: objekt)
            let vorher = s.meldungen.count
            guard case .gelesen(_, _, let kopie?) = s.lernende.archivLesen(stempel: "s1") else {
                Issue.record("\(fall): nicht bereinigt gelesen")
                continue
            }
            #expect(s.meldungen.dropFirst(vorher).map(\.text)
                    == ["Das Archiv wurde beim Lesen bereinigt — das Original liegt als „\(kopie)“ neben der Planung."],
                    Comment(rawValue: "\(fall): \(s.meldungen.map(\.text))"))
            _ = s.lernende.archivLesen(stempel: "s2")
            #expect(s.meldungen.count == vorher + 1, "\(fall): einmal — das zweite Lesen ist sauber")
        }
    }

    @Test("Auch das Blatt meldet die Bereinigung — über den Weg abseits des Hauptstrangs, einmal (Z-AV6-03, I2-08)")
    func bereinigungGemeldetAsynchron() async throws {
        let ort = try ordner("meldung-asynchron")
        defer { aufraeumen(ort) }
        let (s, original) = try await speicher(ort, archiv: try jahrErsetzt())
        guard case .gelesen(_, _, let kopie?) = await s.lernende.archivLesenAsynchron(stempel: "s1") else {
            Issue.record("nicht bereinigt gelesen")
            return
        }
        // Gezählt werden nur Archivmeldungen — ältere Hinweise verfallen derweil (2,8 s).
        #expect(archivmeldungen(s)
                == ["Das Archiv wurde beim Lesen bereinigt — das Original liegt als „\(kopie)“ neben der Planung."],
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
        #expect((try? Data(contentsOf: ort.appending(component: kopie))) == original)
    }

    @Test("Ein verlassenes Lesen abseits des Hauptstrangs bewahrt nichts, schreibt nichts und meldet nichts (Z-AV6-01, I2-08)")
    func verlassenesLesenStill() async throws {
        let ort = try ordner("verlassen")
        defer { aufraeumen(ort) }
        let (s, original) = try await speicher(ort, archiv: try jahrErsetzt())
        let dienst = s.lernende
        let aufgabe = Task { @MainActor in await dienst.archivLesenAsynchron(stempel: "s1") }
        aufgabe.cancel()
        let befund = await aufgabe.value
        var ohneKopie = false
        if case .gelesen(_, _, nil) = befund { ohneKopie = true }
        #expect(ohneKopie, Comment(rawValue: "\(befund)"))
        #expect(archivmeldungen(s).isEmpty && kopie(ort, "s1") == nil, Comment(rawValue: archivmeldungen(s).joined(separator: " | ")))
        #expect(try Data(contentsOf: Ablage(ordner: ort).archiv) == original, "nichts geschrieben")
    }
}
