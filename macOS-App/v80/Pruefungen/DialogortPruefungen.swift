// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Wo ein Dialog aufgeht (E114–E116, v61).
///
/// Der Befund des Nutzers: Der Druckdialog stand als freies Fenster über dem
/// Sitzplan-Blatt und flackerte. Die Regel dagegen ist eine, nicht eine Liste
/// von Aufrufstellen: Ist das Schlüsselfenster ein Blatt, wird der Dialog ein
/// Bogen an diesem Blatt; ist es das Hauptfenster, bleibt der Dialog ein
/// freies Fenster wie bisher. Die Kette (Hauptfenster → Blatt → Rückfrage)
/// wird hier mit gestellten Elternteilen geprüft — `sheetParent` setzt allein
/// AppKit, und ein Prüfziel ohne sichtbare Fenster hängt keine Bögen an.
@Suite("Dialogort")
@MainActor
struct DialogortPruefungen {

    private func fenster(_ titel: String) -> NSWindow {
        let f = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                         styleMask: [.titled], backing: .buffered, defer: true)
        f.title = titel
        return f
    }

    @Test("Ist das Hauptfenster vorn, bleibt der Dialog frei")
    func hauptfensterFrei() {
        let haupt = fenster("Haupt")
        #expect(Dialogort.weg(fuer: haupt, elternVon: { _ in nil }) == .frei)
    }

    @Test("Ohne Schlüsselfenster bleibt der Dialog frei")
    func ohneSchluesselFrei() {
        #expect(Dialogort.weg(fuer: nil, elternVon: { _ in nil }) == .frei)
    }

    @Test("Ein Blatt am Hauptfenster bekommt den Dialog als Bogen")
    func blattBogen() {
        let haupt = fenster("Haupt")
        let blatt = fenster("Sitzplan")
        let eltern: [ObjectIdentifier: NSWindow] = [ObjectIdentifier(blatt): haupt]
        #expect(Dialogort.weg(fuer: blatt, elternVon: { eltern[ObjectIdentifier($0)] }) == .bogen(blatt))
    }

    @Test("Liegt eine Rückfrage auf dem Blatt, ist das Blatt das Ziel — nicht die Rückfrage (E116)")
    func rueckfrageObenaufTrifftDasBlatt() {
        let haupt = fenster("Haupt")
        let blatt = fenster("Sitzplan")
        let frage = fenster("Rückfrage")
        let eltern: [ObjectIdentifier: NSWindow] = [ObjectIdentifier(blatt): haupt,
                                                    ObjectIdentifier(frage): blatt]
        #expect(Dialogort.weg(fuer: frage, elternVon: { eltern[ObjectIdentifier($0)] }) == .bogen(blatt))
        // Und ein Blatt auf dem Blatt (Farbwahl über dem Klassen-Blatt) ebenso:
        // das oberste Blatt unter dem Hauptfenster ist immer das Ziel.
        let noch = fenster("noch eins")
        var tiefer = eltern; tiefer[ObjectIdentifier(noch)] = frage
        #expect(Dialogort.weg(fuer: noch, elternVon: { tiefer[ObjectIdentifier($0)] }) == .bogen(blatt))
    }

    @Test("Ein freies Fenster ohne Elternteil ist kein Blatt — auch wenn es vorn ist")
    func freiesFensterFrei() {
        let frei = fenster("frei")
        let haupt = fenster("Haupt")
        let eltern: [ObjectIdentifier: NSWindow] = [ObjectIdentifier(haupt): frei]
        // Das Hauptfenster hätte hier einen „Elternteil“ — gefragt wird aber nach `frei`.
        #expect(Dialogort.weg(fuer: frei, elternVon: { eltern[ObjectIdentifier($0)] }) == .frei)
    }

    @Test("Die Rückfragen des Blatts „Lernende“ hängen am Blatt — mit den Zahlen dessen, was geht (v80)")
    func lernendenRueckfragenAmBlatt() throws {
        let speicher = Planungsspeicher(vorschau: nil)
        let entwurf = RuecknahmeLernendenPruefungen.entwurf()
        var gereicht: Lernendenbestand?

        speicher.lerngruppeLoeschenFragen("g-1", in: entwurf) { gereicht = $0 }
        var frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.gefahr)
        #expect(frage.text.contains("„6a · Biologie“") && frage.text.contains("1 Mitteilung samt 1 Rücklauf"),
                Comment(rawValue: frage.text))
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht == entwurf.ohneGruppe("g-1").bestand)

        speicher.personLoeschenFragen("l-1", in: entwurf) { gereicht = $0 }
        frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.gefahr && frage.bestaetigung == "Endgültig löschen")
        #expect(frage.text.contains("„Abel, Anna“") && frage.text.contains("1 Rücklauf"), Comment(rawValue: frage.text))
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht == entwurf.ohnePerson("l-1").bestand)

        speicher.anliegenLoeschenFragen("m-1", in: entwurf) { gereicht = $0 }
        frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.gefahr && frage.bestaetigung == "Löschen")
        #expect(frage.text.contains("Die Mitteilung „Elternbrief“") && frage.text.contains("1 Rücklauf"),
                Comment(rawValue: frage.text))
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht == entwurf.ohneAnliegen("m-1").bestand)
        speicher.anliegenLoeschenFragen("m-2", in: entwurf) { gereicht = $0 }
        #expect(speicher.rueckfrage?.text.contains("Die Maßnahme „Nacharbeit“") == true)
        speicher.rueckfrageBeantworten(false)

        var verworfen = false
        speicher.lernendenVerwerfenFragen { verworfen = true }
        frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.ablehnung == "Weiter bearbeiten")
        speicher.rueckfrageBeantworten(false)
        #expect(!verworfen)
    }

    @Test("Termine in den Rückfragen (E290): „Den Termin … löschen?“, bei der Person eigens genannt, die Gruppe lässt sie stehen")
    func termineInRueckfragen() throws {
        let speicher = Planungsspeicher(vorschau: nil)
        // Die Vorlage trägt den Termin m-3 ohne Gruppe für Ben (l-2).
        let entwurf = RuecknahmeLernendenPruefungen.entwurf()
        var gereicht: Lernendenbestand?
        speicher.anliegenLoeschenFragen("m-3", in: entwurf) { gereicht = $0 }
        var frage = try #require(speicher.rueckfrage)
        #expect(frage.text.hasPrefix("Den Termin „Elterngespräch“ löschen?") && frage.text.contains("Mit ihm gehen 0 Rückläufe"),
                Comment(rawValue: frage.text))
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht == entwurf.ohneAnliegen("m-3").bestand)

        speicher.personLoeschenFragen("l-2", in: entwurf) { gereicht = $0 }
        frage = try #require(speicher.rueckfrage)
        #expect(frage.text.contains("1 Maßnahme, 1 Termin und "), Comment(rawValue: frage.text))
        speicher.rueckfrageBeantworten(false)
        speicher.personLoeschenFragen("l-1", in: entwurf) { gereicht = $0 }
        frage = try #require(speicher.rueckfrage)
        #expect(frage.text.contains("0 Maßnahmen und ") && !frage.text.contains("Termin"), "ohne Termine wie bisher")
        speicher.rueckfrageBeantworten(false)

        speicher.lerngruppeLoeschenFragen("g-1", in: entwurf) { gereicht = $0 }
        #expect(speicher.rueckfrage?.text.contains("ebenso ihre Maßnahmen und Termine") == true)
        speicher.rueckfrageBeantworten(false)
    }

    @Test("Die Löschungen im Archiv fragen am Blatt — mit Zahlen, endgültig (E276)")
    func archivLoeschungenFragen() throws {
        let speicher = Planungsspeicher(vorschau: nil)
        let start = try #require(Tag(iso: "2025-08-04"))
        let planung = Planung.leer(titel: "Prüfvektor 2025/26", start: start, wochen: 4, basis: "", klassen: [], fachfarben: [:])
        let jahr = Archivjahr(id: "j-1", schuljahr: "2025/26", archiviert: RuecknahmeLernendenPruefungen.stempel,
                              planung: planung, lernende: RuecknahmeLernendenPruefungen.entwurf())
        let archiv = Archivbestand(geaendert: "", jahre: [jahr])
        var gereicht: Archivbestand?

        speicher.archivJahrLoeschenFragen("j-1", in: archiv) { gereicht = $0 }
        var frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.gefahr && frage.bestaetigung == "Schuljahr löschen")
        #expect(frage.text.contains("Das Schuljahr 2025/26") && frage.text.contains("„Prüfvektor 2025/26“")
                && frage.text.contains("3 Personen") && frage.text.contains("nicht widerrufen"), Comment(rawValue: frage.text))
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht?.jahre.isEmpty == true)

        speicher.archivPersonLoeschenFragen("l-1", in: archiv) { gereicht = $0 }
        frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.gefahr && frage.bestaetigung == "In allen Schuljahren löschen")
        #expect(frage.text.contains("„Abel, Anna“") && frage.text.contains("allen archivierten Schuljahren")
                && frage.text.contains("1 Schuljahr") && frage.text.contains("1 Rücklauf"), Comment(rawValue: frage.text))
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht?.jahre.first?.lernende?.lernende.contains { $0.id == "l-1" } == false)

        speicher.archivAnliegenLoeschenFragen("m-1", imJahr: "j-1", in: archiv) { gereicht = $0 }
        frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.gefahr && frage.bestaetigung == "Löschen")
        #expect(frage.text.contains("Die Mitteilung „Elternbrief“ aus dem Schuljahr 2025/26") && frage.text.contains("1 Rücklauf"),
                Comment(rawValue: frage.text))
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht?.jahre.first?.lernende?.anliegen.contains { $0.id == "m-1" } == false)
    }

    @Test("Die Rückfrage vor „Neue Planung“ ohne Verschlüsselung hängt am Blatt „Neue Planung“ (E275)")
    func neuePlanungFragtAmBlatt() throws {
        let start = try #require(Tag(iso: "2026-08-03"))
        let speicher = Planungsspeicher(vorschau: Planung.leer(titel: "Bisher", start: start, wochen: 4, basis: "",
                                                               klassen: [], fachfarben: [:]))
        var angelegt = false
        speicher.neuePlanungFragen(ort: .neuePlanung) { angelegt = true }
        let frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .neuePlanung && frage.bestaetigung == "Ohne Archiv fortfahren")
        speicher.rueckfrageBeantworten(true)
        #expect(angelegt)
    }

    @Test("Im Prüfziel ohne Fenster meldet der wirkliche Weg „frei“")
    func wirklicherWegOhneFenster() {
        // Kein Schlüsselfenster im Prüfziel: der Weg, den `zeigen` nähme, ist frei —
        // genau der Weg, den die App bis v60 immer nahm.
        #expect(Dialogort.aktuell == .frei)
    }
}
