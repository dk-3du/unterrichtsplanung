// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Wiederholbarer Zufall (LCG) — dieselben Fälle in jedem Lauf.
private struct Wuerfel {
    var zustand: UInt64
    mutating func naechste(_ n: Int) -> Int {
        zustand = zustand &* 6364136223846793005 &+ 1442695040888963407
        return Int((zustand >> 33) % UInt64(n))
    }
}

/// Titel um die Grenze, an der das Kappen den Namen der Kopie ändern kann: ein
/// Anfang aus Zeichen, die der Dateiname verwirft, knapp unter oder über
/// `maxNamenslaenge`, dann ein kurzes Ende mit Buchstaben. Liegt das Ende hinter
/// der Grenze, trägt der abgelegte Titel keinen Buchstaben mehr, die Eingabe schon.
private func erzeugterTitel(_ w: inout Wuerfel) -> String {
    let verworfen = ["!", "?", ".", " ", "\u{1F600}"]
    let ende = ["A", "b", "!", " "]
    let anfang = (0..<(Planungsdatei.maxNamenslaenge - 8 + w.naechste(16)))
        .map { _ in verworfen[w.naechste(verworfen.count)] }.joined()
    return anfang + (0..<w.naechste(8)).map { _ in ende[w.naechste(ende.count)] }.joined()
}

/// Die Warnung vor dem gleichen Namen der Sicherungskopie gilt dem Titel, den
/// die neue Planung trägt (E214, R74-01, v75). Bis 1.9.3 verglichen Dialog und
/// Speicher den eingegebenen Titel; die Kopie trägt den abgelegten — und das
/// Kappen auf `maxNamenslaenge` kann ihren Namen ändern: Bei einem Titel aus
/// 500 Satzzeichen und einem Buchstaben blieb die Kopie „Unterrichtsplanung.json“,
/// gewarnt wurde nicht.
@Suite("Sicherungskopie: die Warnung gilt dem Namen, den die Kopie tragen wird")
@MainActor
struct KopienamePruefungen {

    /// `autoexportAktiv` schreibt in die Einstellungen — nur mit eigenem Ablageort.
    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private func speicher(titel: String) throws -> (Planungsspeicher, URL) {
        let ziel = URL.temporaryDirectory
            .appending(component: "kopiename-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        let planung = Planung.leer(titel: titel, start: try #require(Tag(iso: "2026-08-10")), wochen: 6,
                                   basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                                   fachfarben: [:])
        let s = Planungsspeicher(vorschau: planung)
        s.autoexportOrdner = ziel.path
        s.autoexportAktiv = true
        return (s, ziel)
    }

    private func anlegen(_ s: Planungsspeicher, _ titel: String) throws {
        s.neuePlanung(titel: titel, start: try #require(Tag(iso: "2027-08-09")), wochen: 4, basis: "",
                      klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                      ersterSchultag: nil, uebernahme: [])
    }

    private func warnt(_ s: Planungsspeicher) -> Bool {
        s.meldungen.contains { $0.text.contains("Sicherungskopie heißt weiterhin") }
    }

    @Test("Das Beispiel der Review: Die Kopie behält ihren Namen — gewarnt wird")
    func beispielDerReview() throws {
        let (s, ziel) = try speicher(titel: "Unterrichtsplanung")
        defer { try? FileManager.default.removeItem(at: ziel) }
        let roh = String(repeating: "!", count: Planungsdatei.maxNamenslaenge) + "A"
        let vorher = s.autoexportDateiname
        #expect(s.kopienameBliebe(neuerTitel: roh), "der Dialog warnt")
        try anlegen(s, roh)
        #expect(s.autoexportDateiname == vorher, "die Kopie heißt weiter \(vorher)")
        #expect(warnt(s), "derselbe Name der Kopie — die Warnung gehört dazu")
    }

    @Test("Umgekehrt: Die Kopie wechselt ihren Namen — keine Warnung")
    func umgekehrt() throws {
        let (s, ziel) = try speicher(titel: "A")
        defer { try? FileManager.default.removeItem(at: ziel) }
        let roh = String(repeating: "!", count: Planungsdatei.maxNamenslaenge) + "A"
        let vorher = s.autoexportDateiname
        #expect(!s.kopienameBliebe(neuerTitel: roh), "der Dialog warnt nicht")
        try anlegen(s, roh)
        #expect(s.autoexportDateiname != vorher)
        #expect(!warnt(s), "ein anderer Name der Kopie — nichts zu warnen")
    }

    @Test("Invariante über 300 erzeugte Titel: Gewarnt wird genau dann, wenn die Kopie ihren Namen behält")
    func invariante() throws {
        var w = Wuerfel(zustand: 20260919)
        let bisherige = ["Unterrichtsplanung", "A", "Ab", "b", "bA"]
        var abweichend = 0, gleich = 0, dialog = 0
        for _ in 0..<300 {
            let (s, ziel) = try speicher(titel: bisherige[w.naechste(bisherige.count)])
            let roh = erzeugterTitel(&w)
            let vorher = s.autoexportDateiname
            let vorschau = s.kopienameBliebe(neuerTitel: roh)
            try anlegen(s, roh)
            let bleibt = s.autoexportDateiname == vorher
            if bleibt { gleich += 1 }
            if warnt(s) != bleibt { abweichend += 1 }
            if vorschau != bleibt { dialog += 1 }
            try? FileManager.default.removeItem(at: ziel)
        }
        #expect(gleich > 0, "die Fälle enthalten gleiche Namen")
        #expect(abweichend == 0, "\(abweichend) von 300: Warnung und Name der Kopie passen nicht zusammen")
        #expect(dialog == 0, "\(dialog) von 300: Vorschau des Dialogs und Name der Kopie passen nicht zusammen")
    }
}
