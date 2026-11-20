// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// v92, BD3: Ab dem 51. Tisch empfiehlt der Sitzplan, nicht mehr als 50 zu platzieren (E1052) — eine harte Grenze gibt es
/// nicht (E1051), Verschieben bleibt, wie es ist (E1050). Wo der Hinweis steht, zeigt das Abbild; dass er dort ankommt,
/// prüft `verdrahtet` am Quelltext.
@Suite("Sitzplan: Empfehlung ab dem 51. Tisch, keine Grenze (E1050–E1052)")
@MainActor
struct SitzplanEmpfehlungPruefungen {
    private static func plan(_ n: Int) -> Sitzplan {
        Sitzplan.anordnen(klasseId: "k", namen: (1...n).map { "Name \($0)" })
    }

    @Test("E1052: der Wortlaut, wie entschieden")
    func wortlaut() {
        #expect(SitzplanDialog.tischempfehlung == "Es wird empfohlen, nicht mehr als 50 Tische zu platzieren.")
    }

    @Test("E1052: bei 50 Tischen kein Hinweis, ab dem 51. der Hinweis — gleich, wie der Plan entstand (beim Öffnen: Abbild mit 51)")
    func abDem51() {
        #expect(SitzplanDialog.tischhinweis(nil) == nil, "ohne Plan keiner")
        for n in [1, 49, 50] {
            #expect(SitzplanDialog.tischhinweis(Self.plan(n)) == nil, "\(n) Tische")
        }
        for n in [51, 52, 88, 300] {
            #expect(SitzplanDialog.tischhinweis(Self.plan(n)) == SitzplanDialog.tischempfehlung, "\(n) Tische")
        }
    }

    @Test("E1052: Es zählen die Tische — der Lehrertisch nicht")
    func lehrertischZaehltNicht() throws {
        var p = Self.plan(50)
        try #require(p.lehrertisch != nil && p.tische.count == 50)
        #expect(SitzplanDialog.tischhinweis(p) == nil, "50 Tische und der Lehrertisch")
        p.lehrertisch = nil
        #expect(SitzplanDialog.tischhinweis(p.mitNeuemTisch(name: "Name")) == SitzplanDialog.tischempfehlung)
    }

    @Test("E1051: Der 51. und jeder weitere Tisch lässt sich hinzufügen, wie bisher — nichts wird abgelehnt")
    func nichtsAbgelehnt() {
        var p = Self.plan(50)
        #expect(SitzplanDialog.tischhinweis(p) == nil)
        for n in 51...120 {
            p = p.mitNeuemTisch(name: "Name")
            #expect(p.tische.count == n)
            #expect(SitzplanDialog.tischhinweis(p) == SitzplanDialog.tischempfehlung, "\(n) Tische")
        }
        #expect(Set(p.tische.map(\.id)).count == 120, "jeder neue Tisch mit eigener Kennung")
    }

    @Test("E1052: Zurück auf 50 Tische — der Hinweis geht")
    func zurueckAuf50() throws {
        let p = Self.plan(51)
        let letzter = try #require(p.tische.last)
        var weniger = p
        weniger.tische.removeAll { $0.id == letzter.id }
        #expect(weniger.tische.count == 50 && SitzplanDialog.tischhinweis(weniger) == nil)
    }

    @Test("R-BH8-W2-08 am Quelltext: „Verschlüsselung einrichten …“ übernimmt über `planUebernehmen` — mit der Warnung")
    func verschluesselungUebernimmtMitWarnung() throws {
        let quellen = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung")
        let dialog = try String(contentsOf: quellen.appending(path: "Oberflaeche/Dialoge/SitzplanDialog.swift"), encoding: .utf8)
        let knopf = try #require(dialog.range(of: "Button(\"Verschlüsselung einrichten …\") {"))
        let ende = try #require(dialog.range(of: "speicher.verschluesselungEinrichten()", range: knopf.upperBound..<dialog.endIndex))
        let imKnopf = dialog[knopf.upperBound..<ende.lowerBound]
        #expect(imKnopf.contains("veraendert { planUebernehmen(plan) }") && !imKnopf.contains("speicher.sitzplanUebernehmen("),
                "der Knopf übernimmt über `planUebernehmen`, nicht direkt am Speicher (R-BH8N-06, R-BH8N-08)")
        let weg = try #require(dialog.range(of: "private func planUebernehmen(_ plan: Sitzplan) {"))
        #expect(dialog[weg.upperBound...].prefix(400).contains("speicher.melden("),
                "`planUebernehmen` meldet einen Schreibfehler")
    }

    @Test("E1052 am Quelltext: Der Sitzplan gibt den Hinweis an den Kopf, der Kopf zeigt ihn")
    func verdrahtet() throws {
        let quellen = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung")
        let dialog = try String(contentsOf: quellen.appending(path: "Oberflaeche/Dialoge/SitzplanDialog.swift"), encoding: .utf8)
        let rahmen = try String(contentsOf: quellen.appending(path: "Gestaltung/Dialograhmen.swift"), encoding: .utf8)
        #expect(dialog.contains("hinweis: Self.tischhinweis(plan)"), "der Sitzplan gibt den Hinweis aus dem Entwurf")
        // Der Kopf mit Hinweis: von `if let unterzeile, let hinweis {` bis zum Zweig ohne Hinweis (H1-01).
        let anfang = try #require(rahmen.range(of: "if let unterzeile, let hinweis {"))
        let ende = try #require(rahmen.range(of: "} else if let unterzeile {", range: anfang.upperBound..<rahmen.endIndex))
        let kopf = rahmen[anfang.upperBound..<ende.lowerBound]
        #expect(kopf.contains("Text(hinweis)"), "der Kopf zeigt ihn")
        // E1060: mit Info-Zeichen, nicht mit dem Warnzeichen des Datenschutzhinweises.
        #expect(kopf.contains("Image(systemName: Zeichen.hinweis)") && !kopf.contains("Zeichen.warnung"))
        // E1059: die Ansage im Wechsel des Entwurfs — dort erreichen sie auch ⌘Z und das Öffnen, vorher kein Plan (H1-02).
        let wechsel = try #require(dialog.range(of: ".onChange(of: plan) { alt, neu in\n"))
        let schluss = try #require(dialog.range(of: "\n        }\n", range: wechsel.upperBound..<dialog.endIndex))
        #expect(dialog[wechsel.upperBound..<schluss.lowerBound].contains(
                    "if let ansage = Self.tischansage(vorher: alt, nachher: neu) {\n"
                    + "                Ansager.gemeinsam.ansagen([Ansageeintrag(id: UUID(), warnung: false, text: ansage)])"),
                "über den Ansager, der wartet, bis der Fokus ruht (B108)")
        // Zahl und Wortlaut gehen zusammen (H1-03).
        #expect(SitzplanDialog.tischempfehlung.contains("nicht mehr als \(SitzplanDialog.empfohleneTische) Tische"))
    }

    @Test("E1059: VoiceOver sagt die Empfehlung an — beim Wechsel auf mehr als 50 Tische und beim Öffnen eines solchen Plans, sonst nicht")
    func ansage() {
        let e = SitzplanDialog.tischempfehlung
        #expect(SitzplanDialog.tischansage(vorher: Self.plan(50), nachher: Self.plan(51)) == e, "50 → 51")
        #expect(SitzplanDialog.tischansage(vorher: nil, nachher: Self.plan(60)) == e, "beim Öffnen")
        #expect(SitzplanDialog.tischansage(vorher: Self.plan(51), nachher: Self.plan(52)) == nil, "schon darüber")
        #expect(SitzplanDialog.tischansage(vorher: Self.plan(51), nachher: Self.plan(50)) == nil, "zurück")
        #expect(SitzplanDialog.tischansage(vorher: nil, nachher: Self.plan(50)) == nil, "Öffnen mit 50")
        #expect(SitzplanDialog.tischansage(vorher: Self.plan(51), nachher: nil) == nil, "kein Plan")
    }

    @Test("Die Unterzeile zählt weiter nur die Plätze — der Hinweis steht daneben, nicht darin")
    func unterzeileUnveraendert() {
        #expect(SitzplanDialog.plaetzezeile(Self.plan(51)) == "51 Plätze · Lehrertisch")
    }
}
