// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Ein Zustand, den ein Abschluss liest und die Prüfung umstellt — hier: das Alert blendet noch aus.
@MainActor
private final class Merker {
    var an = false
}

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
        speicher.offenerDialog = .lernende  // Die Fragen hängen am Blatt (E418).

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
        speicher.offenerDialog = .lernende  // Die Fragen hängen am Blatt (E418).
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

    @Test("Die Löschungen im Archiv fragen am Blatt — mit Zahlen, endgültig (E276); gelöscht wird erst, wenn das Alert fort ist (B88)")
    func archivLoeschungenFragen() async throws {
        let speicher = Planungsspeicher(vorschau: nil)
        // Das Alert hängt, solange die Frage steht — und während es nach der Antwort ausblendet.
        let blendetAus = Merker()
        speicher.rueckfrageSichtbar = { [weak speicher] in speicher?.rueckfrage != nil || blendetAus.an }
        let start = try #require(Tag(iso: "2025-08-04"))
        let planung = Planung.leer(titel: "Prüfvektor 2025/26", start: start, wochen: 4, basis: "", klassen: [], fachfarben: [:])
        let jahr = Archivjahr(id: "j-1", schuljahr: "2025/26", archiviert: RuecknahmeLernendenPruefungen.stempel,
                              planung: planung, lernende: RuecknahmeLernendenPruefungen.entwurf())
        let archiv = Archivbestand(geaendert: "", jahre: [jahr])
        var gereicht: Archivbestand?
        speicher.offenerDialog = .lernende  // Das Archiv steht im Blatt; dort hängen die Fragen (E418).

        speicher.archivJahrLoeschenFragen("j-1", in: archiv) { gereicht = $0 }
        var frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.gefahr && frage.bestaetigung == "Schuljahr löschen")
        #expect(frage.text.contains("Das Schuljahr 2025/26") && frage.text.contains("„Prüfvektor 2025/26“")
                && frage.text.contains("3 Personen") && frage.text.contains("nicht widerrufen"), Comment(rawValue: frage.text))
        // Schrieben die Handlungen noch im Klick, baute die Ansicht um, während das Alert schließt (B88).
        // Länger als der Verzug der Fortsetzung: Sie muss das ausblendende Alert sehen, nicht nur den Klick (Z-AS2a-03).
        blendetAus.an = true
        speicher.rueckfrageBeantworten(true)
        try await Task.sleep(for: .milliseconds(Int(Planungsspeicher.folgefrageVerzug * 1000) + 200))  // E145: Uhr — über den Verzug der Fortsetzung hinaus
        #expect(gereicht == nil, "Schuljahr: solange das Alert ausblendet, noch nicht gelöscht")
        blendetAus.an = false
        try await abwarten("Schuljahr gelöscht, wenn das Alert fort ist") { gereicht != nil }
        #expect(gereicht?.jahre.isEmpty == true && speicher.ausstehendeFortsetzungen == 0)
        gereicht = nil

        speicher.archivPersonLoeschenFragen("l-1", in: archiv) { gereicht = $0 }
        frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.gefahr && frage.bestaetigung == "In allen Schuljahren löschen")
        #expect(frage.text.contains("„Abel, Anna“") && frage.text.contains("allen archivierten Schuljahren")
                && frage.text.contains("1 Schuljahr") && frage.text.contains("1 Rücklauf"), Comment(rawValue: frage.text))
        blendetAus.an = true
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht == nil, "Person: solange das Alert ausblendet, noch nicht gelöscht")
        blendetAus.an = false
        try await abwarten("Person gelöscht, wenn das Alert fort ist") { gereicht != nil }
        #expect(gereicht?.jahre.first?.lernende?.lernende.contains { $0.id == "l-1" } == false)
        gereicht = nil

        speicher.archivAnliegenLoeschenFragen("m-1", imJahr: "j-1", in: archiv) { gereicht = $0 }
        frage = try #require(speicher.rueckfrage)
        #expect(frage.ort == .lernende && frage.gefahr && frage.bestaetigung == "Löschen")
        #expect(frage.text.contains("Die Mitteilung „Elternbrief“ aus dem Schuljahr 2025/26") && frage.text.contains("1 Rücklauf"),
                Comment(rawValue: frage.text))
        blendetAus.an = true
        speicher.rueckfrageBeantworten(true)
        #expect(gereicht == nil, "Anliegen: solange das Alert ausblendet, noch nicht gelöscht")
        blendetAus.an = false
        try await abwarten("Anliegen gelöscht, wenn das Alert fort ist") { gereicht != nil }
        #expect(gereicht?.jahre.first?.lernende?.anliegen.contains { $0.id == "m-1" } == false)
    }

    @Test("Eine bestätigte Löschung im Archiv geht nie verloren: Steht bis zur Fortsetzung eine andere Frage, geschieht sie nach deren Antwort (Z-AS2a-01)")
    func archivLoeschungNieVerworfen() async throws {
        let speicher = Planungsspeicher(vorschau: nil)
        let blendetAus = Merker()
        speicher.rueckfrageSichtbar = { [weak speicher] in speicher?.rueckfrage != nil || blendetAus.an }
        let start = try #require(Tag(iso: "2025-08-04"))
        let planung = Planung.leer(titel: "Prüfvektor 2025/26", start: start, wochen: 4, basis: "", klassen: [], fachfarben: [:])
        let jahr = Archivjahr(id: "j-1", schuljahr: "2025/26", archiviert: RuecknahmeLernendenPruefungen.stempel,
                              planung: planung, lernende: RuecknahmeLernendenPruefungen.entwurf())
        let archiv = Archivbestand(geaendert: "", jahre: [jahr])
        var gereicht: Archivbestand?
        speicher.offenerDialog = .lernende  // Das Archiv steht im Blatt; dort hängen die Fragen (E418).
        speicher.archivPersonLoeschenFragen("l-1", in: archiv) { gereicht = $0 }
        speicher.rueckfrageBeantworten(true)
        // Gleich danach, vor der Fortsetzung, eine andere Frage — wie ⎋ bei geändertem Entwurf.
        speicher.fragen("Die Änderungen an den Lernenden verwerfen?", bestaetigung: "Verwerfen", ort: .lernende) {}
        try await Task.sleep(for: .milliseconds(Int(Planungsspeicher.folgefrageVerzug * 1000) + 200))  // E145: Uhr — über den Verzug der Fortsetzung hinaus
        #expect(gereicht == nil, "unter der anderen Frage noch nicht gelöscht — aber nicht verworfen")
        // Auch nach ihrer Antwort erst, wenn ihr Alert fort ist — nicht im Klick (Z-AS2a-06).
        blendetAus.an = true
        speicher.rueckfrageBeantworten(false)
        try await Task.sleep(for: .milliseconds(Int(Planungsspeicher.folgefrageVerzug * 1000) + 200))  // E145: Uhr — über den Verzug der Fortsetzung hinaus
        #expect(gereicht == nil, "solange ihr Alert ausblendet, noch nicht gelöscht")
        blendetAus.an = false
        try await abwarten("nach ihrer Antwort gelöscht") { gereicht != nil }
        #expect(gereicht?.jahre.first?.lernende?.lernende.contains { $0.id == "l-1" } == false
                && speicher.ausstehendeFortsetzungen == 0)
    }

    @Test("Die Rückfrage vor „Neue Planung“ ohne Verschlüsselung hängt am Blatt „Neue Planung“ (E275)")
    func neuePlanungFragtAmBlatt() throws {
        let start = try #require(Tag(iso: "2026-08-03"))
        let speicher = Planungsspeicher(vorschau: Planung.leer(titel: "Bisher", start: start, wochen: 4, basis: "",
                                                               klassen: [], fachfarben: [:]))
        var angelegt = false
        speicher.offenerDialog = .neuePlanung  // Aus dem Blatt, an dem die Frage hängt (E418).
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
