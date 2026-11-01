// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

private typealias Tag = Unterrichtsplanung.Tag

// ── Leerraum am Ende eines Dateinamens (v89, BA3b; E960 a) ────────────────
//
// Der Finder erlaubt „Bericht.pdf “. Bis v88 schnitt `Pfade.normalisieren` jeden Pfad an beiden Enden — auch den aus dem
// Ablegen und der Dateiwahl —, und der Verweis zeigte auf eine Datei, die es nicht gibt (Handprobe 30.10.2026: das Öffnen
// endete in der Rückfrage zum Zugriff). Pfade aus dem System bleiben jetzt, wie sie sind; eingefügter Text wird weiter
// geschnitten (`PfadPruefungen`), der Titel ebenso (E208, `AblegenPruefungen.titelZugeschnitten`). Dazu die Datei einer
// Zeile mit einem Steuer- oder Richtungszeichen im Pfad: abgelehnt mit Warnung — beim Lesen fiele es fort (E964, E966,
// E969).

@Suite("Leerraum am Ende eines Dateinamens: Pfade aus Ablegen und Dateiwahl bleiben unverkürzt (E960)")
@MainActor
struct PfadendePruefungen {

    private static let basis = "/Users/lehrkraft/Unterricht"
    private static let bericht = basis + "/Bio/Bericht.pdf "

    private func speicher() throws -> Planungsspeicher {
        var planung = Planung.leer(
            titel: "Pfadende", start: try #require(Tag(iso: "2026-08-10")), wochen: 8,
            basis: Self.basis, klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        planung.eintraege = [
            Vorhaben(id: "e1", klasseId: planung.klassen[0].id, woche: 2, titel: "Photosynthese", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        return Planungsspeicher(vorschau: planung)
    }

    @Test("Ins Blatt abgelegt oder gewählt: Der Verweis trägt das Leerzeichen am Ende, der Titel nicht")
    func blatt() throws {
        let s = try speicher()
        var entwurf = VorhabenEntwurf(try #require(s.planung?.eintraege.first))
        #expect(s.materialAufnehmen([Self.bericht], in: &entwurf) == 1)
        #expect(entwurf.materialien.map(\.pfad) == ["Bio/Bericht.pdf "], "der Verweis zeigt auf die Datei")
        #expect(entwurf.materialien.map(\.titel) == ["Bericht.pdf"], "der Titel geschnitten wie jeder Text (E208)")
    }

    @Test("Auf eine Kachel abgelegt: Der Verweis trägt das Leerzeichen am Ende, der Titel nicht")
    func kachel() throws {
        let s = try speicher()
        #expect(s.ablegen(dateien: [URL(fileURLWithPath: Self.bericht)], links: [], auf: "e1"))
        let materialien = try #require(s.planung?.eintraege.first?.materialien)
        #expect(materialien.map(\.pfad) == ["Bio/Bericht.pdf "], "der Verweis zeigt auf die Datei")
        #expect(materialien.map(\.titel) == ["Bericht.pdf"])
    }

    @Test("Die Datei einer Zeile: Der Verweis trägt das Leerzeichen am Ende")
    func zeile() throws {
        let s = try speicher()
        let id = try #require(s.planung?.klassen[0].id)
        let liste = Self.basis + "/Verwaltung/Liste.numbers "
        s.kursdateiSetzen(klasse: id, art: .verwaltung, pfad: liste)
        #expect(s.planung?.klasse(id)?.verwaltung == liste)
    }

    @Test("Pfade aus dem System: unverändert bis auf Schrägstriche am Ende — eingesetzter Text wird weiter geschnitten")
    func ausDemSystem() {
        #expect(Pfade.ausDemSystem(Self.bericht) == Self.bericht)
        #expect(Pfade.ausDemSystem(Self.basis + "/ Anfang.pdf") == Self.basis + "/ Anfang.pdf")
        #expect(Pfade.ausDemSystem(Self.basis + "/Zitat\"") == Self.basis + "/Zitat\"")
        #expect(Pfade.ausDemSystem(Self.basis + "/Ordner /") == Self.basis + "/Ordner ")
        #expect(Pfade.ausDemSystem("/") == "/")
        #expect(Pfade.normalisieren(Self.bericht, basis: Self.basis) == Self.basis + "/Bio/Bericht.pdf",
                "Text wie bisher")
    }

    @Test("Ein Steuer- oder Richtungszeichen im Pfad der Datei einer Zeile: abgelehnt mit Warnung, der Verweis bleibt — im Namen der Datei oder eines Ordners, mit der Art (E964, E966, E969)")
    func zeileMitSteuerzeichen() throws {
        let s = try speicher()
        let id = try #require(s.planung?.klassen[0].id)
        let gueltig = Self.basis + "/Verwaltung/Liste.numbers"
        s.kursdateiSetzen(klasse: id, art: .verwaltung, pfad: gueltig)
        let schritte = s.verlauf.zurueck.count
        for zeichen in ["\u{202E}", "\u{1}"] {
            s.kursdateiSetzen(klasse: id, art: .verwaltung,
                              pfad: Self.basis + "/Verwaltung/Liste" + zeichen + "x.numbers")
            #expect(s.planung?.klasse(id)?.verwaltung == gueltig, "der alte Verweis bleibt")
        }
        #expect(s.verlauf.zurueck.count == schritte, "abgelehnt: kein Schritt")
        let imNamen = "„Listex.numbers“ lässt sich nicht als Verwaltungsdatei hinterlegen — der Name enthält ein "
            + "Steuer- oder Richtungszeichen. Die Datei im Finder umbenennen und neu wählen."
        #expect(s.meldungen.filter { $0.text == imNamen && $0.art == .warnung }.count == 2,
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
        // Im Ordner: Die Warnung nennt ihn, ohne das Zeichen (E966), und die Art (E969).
        s.kursdateiSetzen(klasse: id, art: .leistungsdokumentation,
                          pfad: Self.basis + "/Verw\u{202E}altung/Noten.numbers")
        #expect(s.planung?.klasse(id)?.leistungsdokumentation == "")
        let imOrdner = "„Noten.numbers“ lässt sich nicht als externe Leistungsdokumentation hinterlegen — der Ordner "
            + "„Verwaltung“ auf dem Weg dorthin enthält ein Steuer- oder Richtungszeichen. Den Ordner im Finder "
            + "umbenennen und neu wählen."
        #expect(s.meldungen.contains { $0.text == imOrdner && $0.art == .warnung },
                Comment(rawValue: s.meldungen.map(\.text).joined(separator: " | ")))
        // Ein Leerzeichen am Ende bleibt erlaubt (E960).
        s.kursdateiSetzen(klasse: id, art: .verwaltung, pfad: Self.basis + "/Verwaltung/Liste.numbers ")
        #expect(s.planung?.klasse(id)?.verwaltung == Self.basis + "/Verwaltung/Liste.numbers ")
    }

    @Test("Ein Ordner, dessen Name auf ein Leerzeichen endet: im Blatt und auf der Kachel unverkürzt")
    func ordner() throws {
        let s = try speicher()
        var entwurf = VorhabenEntwurf(try #require(s.planung?.eintraege.first))
        #expect(s.materialAufnehmen([Self.basis + "/Bio/Unterlagen /"], in: &entwurf) == 1)
        #expect(entwurf.materialien.map(\.pfad) == ["Bio/Unterlagen "], "der Schrägstrich geht, das Leerzeichen bleibt")
        let ordner = URL(fileURLWithPath: Self.basis + "/Bio/Unterlagen ", isDirectory: true)
        #expect(s.ablegen(dateien: [ordner], links: [], auf: "e1"))
        #expect(s.planung?.eintraege.first?.materialien.map(\.pfad) == ["Bio/Unterlagen "])
    }

    @Test("Zweimal abgelegt: Der Verweis mit dem Leerzeichen ist schon verknüpft — kein zweiter Schritt, im Blatt nichts Neues")
    func entdoppeln() throws {
        let s = try speicher()
        let datei = URL(fileURLWithPath: Self.bericht)
        #expect(s.ablegen(dateien: [datei], links: [], auf: "e1"))
        #expect(!s.ablegen(dateien: [datei], links: [], auf: "e1"), "nichts Neues — kein Schritt")
        #expect(s.planung?.eintraege.first?.materialien.map(\.pfad) == ["Bio/Bericht.pdf "])
        var entwurf = VorhabenEntwurf(try #require(s.planung?.eintraege.first))
        #expect(s.materialAufnehmen([Self.bericht], in: &entwurf) == 0, "auch im Blatt schon verknüpft")
    }

    @Test("Ein Verweis aus 2.3.0 ohne das Leerzeichen bleibt neben dem neuen stehen — der Ausweg der LIESMICH: neu ablegen, den alten entfernen")
    func nebenDemAlten() throws {
        let s = try speicher()
        var entwurf = VorhabenEntwurf(try #require(s.planung?.eintraege.first))
        entwurf.materialien = [Material(titel: "Bericht.pdf", pfad: "Bio/Bericht.pdf")]
        #expect(s.materialAufnehmen([Self.bericht], in: &entwurf) == 1, "der neue ist kein Doppel des alten")
        #expect(entwurf.materialien.map(\.pfad) == ["Bio/Bericht.pdf", "Bio/Bericht.pdf "])
    }

    @Test("Der Verweis übersteht Schreiben und Lesen der Planungsdatei — der Leser schneidet nicht")
    func durchDieDatei() throws {
        let s = try speicher()
        let id = try #require(s.planung?.klassen[0].id)
        var planung = try #require(s.planung)
        planung.eintraege[0].materialien = [Material(titel: "Bericht.pdf", pfad: "Bio/Bericht.pdf ")]
        planung.klassen[0].verwaltung = Self.basis + "/Verwaltung/Liste.numbers "
        let gelesen = try Planungsdatei.lesen(try Planungsdatei.schreiben(planung))
        #expect(gelesen.eintraege.first?.materialien.map(\.pfad) == ["Bio/Bericht.pdf "])
        #expect(gelesen.klasse(id)?.verwaltung == Self.basis + "/Verwaltung/Liste.numbers ")
    }
}
