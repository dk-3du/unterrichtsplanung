// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Die Planungsdatei mit ersetzten Kennungen (v83, AV7: B102, E456 a) ──
// Eine Kennung, die leer, doppelt oder außerhalb des Musters ist, ersetzt das
// Lesen durch eine neue — bei jedem Lesen eine andere, solange die Datei nicht
// geschrieben wird. Ein Sitzplan an der neuen Kennung ging so beim nächsten
// Start verloren. Jetzt: erst das Original bewahren
// (`planung-bereinigt-<Stempel>.json`), dann einmal schreiben — auf beiden
// Wegen (Klartext, versiegelt); die Kopie gehört zur Generation des Schutzes,
// die Fassung davor bleibt gestempelt. Keine Kopie bei reinem Verlust, über der
// Schreibgrenze oder wenn die Datei nicht mehr trägt, was gelesen wurde.

@Suite("Planungsdatei mit ersetzten Kennungen: Original bewahrt, einmal geschrieben (B102)")
@MainActor
struct PlanungErsetzteKennungenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "planung-kennungen-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func aufraeumen(_ ort: URL) { try? FileManager.default.removeItem(at: ort) }

    private func planung() throws -> Planung {
        Planung.leer(titel: "Kennungen", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                     basis: "", klassen: Standardkurse.aufbauen([("7a", "Mathematik"), ("G9", "Chemie")]),
                     fachfarben: [:])
    }

    /// Die Planung als JSON, in der ersten Klasse `feld` auf `wert` gesetzt.
    private func datei(_ p: Planung? = nil, feld: String = "id", wert: String) throws -> Data {
        var roh = try #require(try JSONSerialization.jsonObject(with: try Planungsdatei.schreiben(p ?? planung()))
                                   as? [String: Any])
        var klassen = try #require(roh["klassen"] as? [[String: Any]])
        klassen[0][feld] = wert
        roh["klassen"] = klassen
        return try JSONSerialization.data(withJSONObject: roh)
    }

    /// Die Planung als JSON, die erste Klasse mit der Kennung `kennung` — außerhalb des Musters.
    private func datei(mitKennung kennung: String) throws -> Data {
        try datei(wert: kennung)
    }

    private func dateien(_ ort: URL, _ vorsatz: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: ort.path)) ?? [])
            .filter { $0.hasPrefix(vorsatz) }.sorted()
    }

    private func kopien(_ ort: URL) -> [String] { dateien(ort, "planung-bereinigt-") }

    private func lesen(_ ort: URL, _ name: String) -> Data? {
        try? Data(contentsOf: ort.appending(component: name))
    }

    private func ladetexte(_ s: Planungsspeicher) -> [String] {
        s.meldungen.map(\.text).filter { $0.hasPrefix("Beim Laden der Autosicherung") }
    }

    @Test("Klartext: das Original bewahrt, einmal geschrieben — Kennung und Sitzplan überstehen den Neustart, keine zweite Kopie")
    func klartext() throws {
        let ort = try ordner("klartext")
        defer { aufraeumen(ort) }
        let original = try datei(mitKennung: "ungültig!")
        let davor = try Planungsdatei.schreiben(try planung())
        try original.write(to: Ablage(ordner: ort).datei)
        try davor.write(to: Ablage(ordner: ort).vorherigeFassung)

        let erster = Planungsspeicher(ablage: Ablage(ordner: ort))
        erster.starten()
        let klasse = try #require(erster.planung?.klassen.first?.id)
        #expect(Kennung.istGueltig(klasse) && klasse != "ungültig!")
        // Schon beim Laden geschrieben, nicht erst mit dem nächsten Anlass (Z-AV7-01).
        let platte = try Data(contentsOf: Ablage(ordner: ort).datei)
        #expect(platte != original && (try? Planungsdatei.lesen(platte))?.klassen.first?.id == klasse,
                "beim Laden mit der neuen Kennung geschrieben")
        #expect(lesen(ort, "planung-vorher.json") == original, "die Fassung davor ist jetzt das Original")
        let gestempelt = dateien(ort, "planung-vorher-")
        #expect(gestempelt.count == 1 && gestempelt.first.flatMap { lesen(ort, $0) } == davor,
                "die bisherige Fassung davor bleibt, gestempelt (Z-AV7-03)")
        _ = erster.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse, namen: ["Ada", "Alan"]))
        erster.jetztSichern()
        let bewahrt = kopien(ort)
        #expect(bewahrt.count == 1, Comment(rawValue: bewahrt.joined(separator: ", ")))
        #expect(bewahrt.first.flatMap { try? Data(contentsOf: ort.appending(component: $0)) } == original,
                "die Kopie ist das Original")
        let texte = ladetexte(erster)
        #expect(texte.count == 1 && bewahrt.first.map { name in texte.first?.hasSuffix("Das Original liegt als „\(name)“ neben der Planung.") == true } == true,
                Comment(rawValue: texte.joined(separator: " | ")))

        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ort))
        zweiter.starten()
        #expect(zweiter.planung?.klassen.first?.id == klasse, "dieselbe Kennung nach dem Neustart")
        #expect(zweiter.sitzplan(fuer: klasse)?.tische.count == 2, "der Sitzplan übersteht den Neustart")
        #expect(kopien(ort) == bewahrt && ladetexte(zweiter).isEmpty, "der zweite Start liest sauber")
    }

    @Test("Versiegelt: derselbe Weg nach dem Entsperren — Original bewahrt (versiegelt), Kennung und Sitzplan überstehen den Neustart")
    func versiegelt() async throws {
        let ort = try ordner("versiegelt")
        defer { aufraeumen(ort) }
        let vorbereitung = Planungsspeicher(ablage: Ablage(ordner: ort))
        vorbereitung.planung = try planung()
        _ = try vorbereitung.verschluesselungVorbereiten(passphrase: passphrase)
        _ = vorbereitung.verschluesselungEinschalten()
        vorbereitung.jetztSichern()
        let t = try #require(vorbereitung.tresor)
        let original = try t.versiegeln(try datei(mitKennung: "ungültig!"), inhalt: .planung, ziel: .ablage)
        try original.write(to: Ablage(ordner: ort).datei)

        let erster = Planungsspeicher(ablage: Ablage(ordner: ort))
        erster.starten()
        await erster.entsperren(passphrase: passphrase)
        let klasse = try #require(erster.planung?.klassen.first?.id)
        #expect(Kennung.istGueltig(klasse) && klasse != "ungültig!")
        let platte = try Data(contentsOf: Ablage(ordner: ort).datei)
        #expect(platte != original && (try? Planungsdatei.lesen(try t.oeffnen(platte)))?.klassen.first?.id == klasse,
                "beim Entsperren mit der neuen Kennung geschrieben (Z-AV7-01)")
        _ = erster.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse, namen: ["Ada", "Alan"]))
        erster.jetztSichern()
        let bewahrt = kopien(ort)
        #expect(bewahrt.count == 1, Comment(rawValue: bewahrt.joined(separator: ", ")))
        #expect(bewahrt.first.flatMap { try? Data(contentsOf: ort.appending(component: $0)) } == original,
                "die Kopie ist das Original, versiegelt")

        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ort))
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        #expect(zweiter.planung?.klassen.first?.id == klasse, "dieselbe Kennung nach dem Neustart")
        #expect(zweiter.sitzplan(fuer: klasse)?.tische.count == 2, "der Sitzplan übersteht den Neustart")
        #expect(kopien(ort) == bewahrt, "keine zweite Kopie")
    }

    @Test("Die Kopie gehört zur Generation: Einschalten versiegelt auch „planung-bereinigt-…“")
    func kopieInDerGeneration() throws {
        let ort = try ordner("generation")
        defer { aufraeumen(ort) }
        let original = try datei(mitKennung: "ungültig!")
        let davor = try Planungsdatei.schreiben(try planung())
        try original.write(to: Ablage(ordner: ort).datei)
        try davor.write(to: Ablage(ordner: ort).vorherigeFassung)
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.starten()
        let name = try #require(kopien(ort).first, "eine Kopie liegt")
        let gestempelt = try #require(dateien(ort, "planung-vorher-").first, "die Fassung davor liegt gestempelt")
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().ablage == .geschrieben)
        let versiegelt = try Data(contentsOf: ort.appending(component: name))
        #expect(Tresor.istBehaelter(versiegelt), "die Kopie liegt danach versiegelt, nicht im Klartext daneben")
        #expect((try? Tresor.kopfLesen(versiegelt))?.inhalt == Tresor.Inhalt.planung.rawValue
                && (try? s.tresor?.oeffnen(versiegelt)) == original,
                "als Planung versiegelt, mit dem Original darin — ⌘O öffnet sie (Z-AV7-05)")
        // Ebenso die gestempelte Fassung davor (I1-01).
        let fassung = try Data(contentsOf: ort.appending(component: gestempelt))
        #expect((try? Tresor.kopfLesen(fassung))?.inhalt == Tresor.Inhalt.planung.rawValue
                && (try? s.tresor?.oeffnen(fassung)) == davor,
                "die gestempelte Fassung davor als Planung versiegelt (I1-01)")
    }

    @Test("Reiner Verlust, gültige Kennungen: keine Kopie, nichts geschrieben, die Fassung davor bleibt — die Warnung wie bisher (Z-AV7-06)")
    func reinerVerlust() throws {
        let ort = try ordner("verlust")
        defer { aufraeumen(ort) }
        let original = try datei(feld: "name", wert: String(repeating: "x", count: 5_000))
        let davor = try Planungsdatei.schreiben(try planung())
        try original.write(to: Ablage(ordner: ort).datei)
        try davor.write(to: Ablage(ordner: ort).vorherigeFassung)
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.starten()
        #expect(s.planung?.klassen.first?.name.count ?? 0 < 5_000, "Vorbedingung: gekürzt gelesen")
        #expect(kopien(ort).isEmpty && dateien(ort, "planung-vorher-").isEmpty)
        #expect(lesen(ort, "planung.json") == original && lesen(ort, "planung-vorher.json") == davor,
                "nichts geschrieben, die Fassung davor unberührt")
        let texte = ladetexte(s)
        #expect(texte.count == 1 && texte.first?.hasSuffix("Die Fassung davor liegt als planung-vorher.json daneben.") == true,
                Comment(rawValue: texte.joined(separator: " | ")))
        #expect(!s.verlustDroht)
    }

    @Test("Über der Schreibgrenze (Bestand aus ≤ v42): keine Kopie — sie entstünde bei jedem Start, und das Beenden fragte (Z-AV7-02)")
    func ueberDerSchreibgrenze() throws {
        let ort = try ordner("schreibgrenze")
        defer { aufraeumen(ort) }
        var p = try planung()
        let text = String(repeating: "x", count: Planungsdatei.maxTextlaenge)
        p.eintraege = (0..<1_700).map {
            Vorhaben(id: "r-\($0)", klasseId: p.klassen[1].id, woche: $0 % 4, titel: "Riese \($0)",
                     text: text, erledigt: false, materialien: [], links: [])
        }
        let original = try datei(p, wert: "ungültig!")
        #expect(original.count > Sicherungsdienst.schreibgrenze && original.count < Sicherungsdienst.lesedecke)
        try original.write(to: Ablage(ordner: ort).datei)
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.starten()
        #expect(s.planung?.eintraege.count == 1_700 && s.sicherung.stoerung == .zuGross(original.count))
        #expect(kopien(ort).isEmpty, Comment(rawValue: kopien(ort).joined(separator: ", ")))
        #expect(!s.verlustDroht, "niemand hat geändert — nichts geht beim Beenden verloren")
    }

    @Test("Versiegelt, die Datei zwischen Start und Entsperren ersetzt: keine Kopie, nichts geschrieben — die Kopie trüge nicht, was gelesen wurde (Z-AV7-04)")
    func ersetztVorDemEntsperren() async throws {
        let ort = try ordner("ersetzt")
        defer { aufraeumen(ort) }
        let vorbereitung = Planungsspeicher(ablage: Ablage(ordner: ort))
        vorbereitung.planung = try planung()
        _ = try vorbereitung.verschluesselungVorbereiten(passphrase: passphrase)
        _ = vorbereitung.verschluesselungEinschalten()
        vorbereitung.jetztSichern()
        let t = try #require(vorbereitung.tresor)
        try t.versiegeln(try datei(mitKennung: "ungültig!"), inhalt: .planung, ziel: .ablage)
            .write(to: Ablage(ordner: ort).datei)

        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.starten()
        // Während die Passphrase aussteht, legt jemand eine andere Fassung hin.
        let andere = try t.versiegeln(try datei(mitKennung: "auch ungültig!"), inhalt: .planung, ziel: .ablage)
        try andere.write(to: Ablage(ordner: ort).datei)
        await s.entsperren(passphrase: passphrase)
        #expect(s.planung != nil)
        #expect(kopien(ort).isEmpty, Comment(rawValue: kopien(ort).joined(separator: ", ")))
        #expect(lesen(ort, "planung.json") == andere, "nichts über die andere Fassung geschrieben")
        let texte = ladetexte(s)
        #expect(texte.count == 1 && texte.first?.hasSuffix("Die Fassung davor liegt als planung-vorher.json daneben.") == true,
                Comment(rawValue: texte.joined(separator: " | ")))
    }
}
