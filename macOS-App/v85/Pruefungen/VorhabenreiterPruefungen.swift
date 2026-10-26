// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Reiter des Vorhaben-Blatts (E373–E375, AW3-neu) ───────────────────────
//
// Reine Funktionen am Entwurf: Folge und Namen der Reiter, was ein Reiter
// trägt, der Reiter des Grundes, wenn „Übernehmen“ abweist (E374, E732),
// der bestehende Termin ohne offene Verwaltung (E721), leere Linkzeilen
// (E722) und was die beiden Ablageflächen annehmen (E734).

@Suite("Reiter des Vorhaben-Blatts")
@MainActor
struct VorhabenreiterPruefungen {

    /// Ein neuer Entwurf ohne Inhalt.
    private func entwurf() -> VorhabenEntwurf {
        VorhabenEntwurf(klasseId: "k1", woche: 0)
    }

    private func link(_ adresse: String) -> Weblink {
        Weblink(titel: "", adresse: adresse)
    }

    private func material(_ pfad: String) -> Material {
        Material(titel: "", pfad: pfad)
    }

    /// „Elterngespräch“, schon ein Termin, geöffnet ohne offene Verwaltung: ohne Personen im Entwurf.
    private func bestehenderTermin() throws -> VorhabenEntwurf {
        var vorhaben = Vorhaben(id: "e1", klasseId: "k1", woche: 2, titel: "Elterngespräch", text: "",
                                erledigt: false, materialien: [], links: [])
        vorhaben.termin = "m-1"
        vorhaben.terminzeit = "07:45"
        // Erst als `Tag`: An ein Optional zugewiesen, prüfte `#require` nichts.
        let tag = try #require(Tag(iso: "2026-08-20"))
        vorhaben.datum = tag
        return VorhabenEntwurf(vorhaben, terminpersonen: [])
    }

    // ── Folge und Titel ───────────────────────────────────────────────────

    @Test("Sieben Reiter in fester Folge (Nutzer, 20.10.2026)")
    func folgeUndTitel() {
        #expect(Vorhabenreiter.allCases.map(\.titel) == [
            "Grundlegendes", "Kommentar", "Prüfung", "Termin", "Hausaufgabe", "Material", "Links",
        ])
    }

    // ── Kennzeichen (E373) ────────────────────────────────────────────────

    @Test("Kennzeichen je Reiter")
    func kennzeichenJeReiter() {
        var e = entwurf()
        e.kommentar = "Lief gut"
        e.termin = true
        e.terminpersonen = ["p1", "p2"]
        e.hausaufgabe = true
        e.materialien = [material("a.pdf"), material("b.pdf"), material("c.pdf")]
        e.links = [link("https://example.org"), link("https://3ducation.org/")]
        var pruefung = entwurf()
        pruefung.pruefung = true
        #expect(e.beschriftung(.kommentar) == "Kommentar •")
        #expect(pruefung.beschriftung(.pruefung) == "Prüfung ✓")
        #expect(e.beschriftung(.termin) == "Termin · 2")
        #expect(e.beschriftung(.hausaufgabe) == "Hausaufgabe ✓")
        #expect(e.beschriftung(.material) == "Material · 3")
        #expect(e.beschriftung(.links) == "Links · 2")
    }

    @Test("„Grundlegendes“ trägt kein Kennzeichen — auch mit Titel und Beschreibung")
    func grundlegendesOhneKennzeichen() {
        var e = entwurf()
        e.titel = "Stoffe"
        e.text = "Eigenschaften"
        #expect(!e.traegt(.grundlegendes))
        #expect(e.beschriftung(.grundlegendes) == "Grundlegendes")
    }

    @Test("Ohne Inhalt kein Kennzeichen")
    func ohneKennzeichen() {
        let e = entwurf()
        for reiter in Vorhabenreiter.allCases {
            #expect(!e.traegt(reiter))
            #expect(e.kennzeichen(reiter) == nil)
            #expect(e.beschriftung(reiter) == reiter.titel)
        }
    }

    @Test("Ein Kommentar nur aus Steuerzeichen und Leerraum trägt nicht — wie ihn das Sichern zuschneidet (Z-AW2a-05)")
    func kommentarSteuerzeichen() {
        var e = entwurf()
        e.kommentar = "\u{202E} \n\t\u{0007}"
        #expect(!e.traegt(.kommentar))
        #expect(e.kennzeichen(.kommentar) == nil)
    }

    @Test("Termin ohne Person: Termin · 0 (E572)")
    func terminOhnePerson() {
        var e = entwurf()
        e.termin = true
        #expect(e.beschriftung(.termin) == "Termin · 0")
    }

    @Test("Leere Linkzeile zählt nicht (E575)")
    func leereLinkzeile() {
        var e = entwurf()
        e.links = [link(""), link("  ")]
        #expect(!e.traegt(.links))
        #expect(e.kennzeichen(.links) == nil)
        // Eine Adresse zählt, gültig oder nicht.
        e.links.append(link("ftp://example.org"))
        #expect(e.beschriftung(.links) == "Links · 1")
    }

    @Test("Hausaufgabenzeile ohne Schalter trägt nicht")
    func hausaufgabeOhneSchalter() {
        var e = entwurf()
        e.hausaufgabenText = "S. 42"
        #expect(!e.traegt(.hausaufgabe))
        #expect(e.kennzeichen(.hausaufgabe) == nil)
    }

    // ── Bestehender Termin ohne offene Verwaltung (E721) ──────────────────

    @Test("Ohne offene Verwaltung: „Termin ✓“ statt „Termin · 0“ — die Zahl ist nicht bekannt (E721)")
    func terminOhneVerwaltungKennzeichen() throws {
        let e = try bestehenderTermin()
        #expect(e.beschriftung(.termin, verwaltungOffen: false) == "Termin ✓")
        #expect(e.beschriftung(.termin, verwaltungOffen: true) == "Termin · 0", "mit offener Verwaltung die Zahl")
    }

    @Test("Ohne offene Verwaltung prüft „Übernehmen“ die Personen eines bestehenden Termins nicht (E721)")
    func terminOhneVerwaltungPersonen() throws {
        var e = try bestehenderTermin()
        e.kommentar = "Nachtrag"
        #expect(e.terminFehlt(verwaltungOffen: false) == nil)
        #expect(e.reiterDesGrundes(verwaltungOffen: false) == nil)
        #expect(e.terminFehlt(verwaltungOffen: true) == "Ein Termin braucht mindestens eine Person.",
                "mit offener Verwaltung wie bisher")
    }

    @Test("Ein neuer Termin braucht auch ohne offene Verwaltung eine Person (E721 gilt nur für bestehende)")
    func neuerTerminOhneVerwaltung() {
        var e = entwurf()
        e.titel = "Elternabend"
        e.termin = true
        #expect(e.terminFehlt(verwaltungOffen: false) == "Ein Termin braucht mindestens eine Person.")
        #expect(e.beschriftung(.termin, verwaltungOffen: false) == "Termin · 0")
    }

    // ── Leere Linkzeilen und „leer“ (E722) ────────────────────────────────

    @Test("Leere Linkzeilen zählen für „leer“ nicht (E722)")
    func leerTrotzLeererLinkzeile() {
        var e = entwurf()
        e.links = [link(""), link("  ")]
        #expect(e.leer)
        #expect(e.reiterDesGrundes() == .grundlegendes, "abgewiesen wie ein ganz leerer Entwurf (E732)")
        e.links.append(link("https://example.org"))
        #expect(!e.leer, "eine Adresse genügt")
    }

    // ── Reiter des Grundes (E374, E732) ───────────────────────────────────

    @Test("Leerer Entwurf: Grundlegendes (E732)")
    func grundLeer() {
        var e = entwurf()
        e.termin = true
        #expect(e.leer)
        #expect(e.reiterDesGrundes() == .grundlegendes)
    }

    @Test("Ungültiger Link: Links")
    func grundLinks() {
        var e = entwurf()
        e.titel = "Stoffe"
        e.links = [link("ftp://example.org")]
        #expect(e.reiterDesGrundes() == .links)
    }

    @Test("Termin ohne Person: Termin")
    func grundTermin() {
        var e = entwurf()
        e.titel = "Elternabend"
        e.termin = true
        #expect(e.terminFehlt != nil)
        #expect(e.reiterDesGrundes() == .termin)
    }

    @Test("Termin ohne Tag: Grundlegendes — dort stehen die Wochentage (E732)")
    func grundTerminOhneTag() {
        var e = entwurf()
        e.titel = "Elternabend"
        e.termin = true
        e.terminpersonen = ["p-1"]
        e.datum = nil
        #expect(e.terminFehlt == "Ein Termin braucht einen Tag — bitte einen Wochentag wählen.")
        #expect(e.reiterDesGrundes() == .grundlegendes)
    }

    @Test("Termin mit ungültiger Uhrzeit: Termin")
    func grundTerminUhrzeit() throws {
        var e = entwurf()
        e.titel = "Elternabend"
        e.termin = true
        e.terminpersonen = ["p-1"]
        let tag = try #require(Tag(iso: "2026-08-20"))
        e.datum = tag
        e.terminzeit = "25:99"
        #expect(e.terminFehlt == "Die Uhrzeit bitte als hh:mm, etwa 07:45 — oder leer lassen.")
        #expect(e.reiterDesGrundes() == .termin)
    }

    @Test("Links vor Termin, wie beim Übernehmen")
    func grundFolge() {
        var e = entwurf()
        e.titel = "Elternabend"
        e.termin = true
        e.links = [link("ftp://example.org")]
        #expect(e.reiterDesGrundes() == .links)
    }

    @Test("Ohne Grund kein Reiter")
    func ohneGrund() {
        var e = entwurf()
        e.titel = "Stoffe"
        e.links = [link("https://example.org")]
        #expect(e.reiterDesGrundes() == nil)
    }

    // ── Ablageflächen (E375 b, E734) ──────────────────────────────────────

    private let datei = URL(fileURLWithPath: "/tmp/Arbeitsblatt.pdf")
    private let netz = URL(string: "https://3ducation.org/")!

    @Test("„Material“ nimmt nur Dateien; mitgezogene Links werden gemeldet (W3)")
    func ablageMaterial() {
        let gemischt = VorhabenDialog.ablage([datei, netz], art: .dateien)
        #expect(gemischt.dateien == [datei] && gemischt.links.isEmpty)
        #expect(gemischt.meldung == "Links gehören unter „Links“ — hier lassen sich nur Dateien ablegen.")
        #expect(VorhabenDialog.ablage([netz], art: .dateien).dateien.isEmpty)
        #expect(VorhabenDialog.ablage([datei], art: .dateien).meldung == nil)
        #expect(VorhabenDialog.ablage([], art: .dateien).meldung == "Keine Datei erkannt — bitte „Datei wählen …“ nutzen.")
    }

    @Test("„Links“ nimmt nur Links; mitgezogene Dateien werden gemeldet (W4)")
    func ablageLinks() {
        let gemischt = VorhabenDialog.ablage([netz, datei], art: .links)
        #expect(gemischt.links == ["https://3ducation.org/"] && gemischt.dateien.isEmpty)
        #expect(gemischt.meldung == "Dateien gehören unter „Material“ — hier lassen sich nur Links ablegen.")
        #expect(VorhabenDialog.ablage([datei], art: .links).links.isEmpty)
        #expect(VorhabenDialog.ablage([netz], art: .links).meldung == nil)
        #expect(VorhabenDialog.ablage([], art: .links).meldung
                == "Keine Webadresse erkannt — bitte „Link hinzufügen“ nutzen.")
    }
}
