// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Adressaten einer neuen Mitteilung (v91, BC4: V4) ──────────────────────
// Vorgegeben alle aktiven Mitglieder der Lerngruppe; wahlweise „Einzelne …“ — eine Mehrfachauswahl, eine Person ist eine
// Auswahl von einer. Festgehalten wird beim Anlegen: Wer danach in die Lerngruppe kommt, ist nicht betroffen; aufgenommen
// wird nur von Hand über „Auch an …“ (Nutzer: „kein Automatismus“). Reine Funktionen am Bestand und der Bogen am Blatt am
// Quelltext; den Bogen selbst zeigt das Abbild `mitteilungen-einzelne`.

@Suite("Mitteilungen: Adressaten — alle Mitglieder, einzelne, später Hinzukommende nicht betroffen (BC4)")
struct MitteilungsadressatenPruefungen {

    private static let s = "2026-08-20T08:00:00.000Z"
    private static let jetzt = "2026-11-02T09:00:00.000Z"
    private static let anna = "l-anna", ben = "l-ben", clara = "l-clara", david = "l-david", emil = "l-emil"

    private static func person(_ id: String, _ vorname: String, _ nachname: String, archiviert: String = "") -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: s, geaendert: s, archiviert: archiviert)
    }

    /// Die 5a: Anna, Ben, Clara, David (archiviert), Emil — noch ohne Mitteilung.
    private static func bestand() -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [person(anna, "Anna", "Adam"), person(ben, "Ben", "Brandt"), person(clara, "Clara", "Conrad"),
                      person(david, "David", "Dorn", archiviert: s), person(emil, "Emil", "Eck")]
        b.lerngruppen = [Lerngruppe(id: "g-5a", name: "5a", art: .klasse, mitglieder: [anna, ben, clara, david, emil],
                                    zeilen: [], skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        return b
    }

    /// Anlegen wie die Anlegezeile: die Betroffenen aus den Adressaten, heute, ohne Frist.
    private static func anlegen(_ b: Lernendenbestand, _ adressaten: Mitteilungsadressaten,
                                titel: String = "Wandertag") throws -> (bestand: Lernendenbestand, id: String) {
        let mitglieder = Lernendenverzeichnis(b).mitglieder("g-5a")
        return try #require(b.mitNeuemAnliegen(.mitteilung, titel: titel, lerngruppe: "g-5a",
                                               betroffene: adressaten.betroffene(mitglieder), datum: "2026-11-02", frist: "",
                                               jetzt: jetzt))
    }

    private static func betroffene(_ b: Lernendenbestand, _ id: String) -> [String]? {
        b.anliegen.first { $0.id == id }?.betroffene
    }

    // ── Standard: alle aktiven Mitglieder ─────────────────────────────────

    @Test("V4: Vorgegeben gehen neue Mitteilungen an alle aktiven Mitglieder — David, archiviert, nicht")
    func standardAlle() throws {
        let b = Self.bestand()
        let (neu, id) = try Self.anlegen(b, .alle)
        #expect(Self.betroffene(neu, id) == [Self.anna, Self.ben, Self.clara, Self.emil])
        #expect(Mitteilungsadressaten.alle.anlegbar([]), "an alle geht auch in einer Lerngruppe ohne Mitglieder — wie bisher")
    }

    // ── Einzelne: Mehrfachauswahl, eine Person ────────────────────────────

    @Test("V4: „Einzelne …“ — nur die Gewählten, in der Folge der Liste; Archivierte und Unbekannte nie; eine Person geht")
    func einzelne() throws {
        let b = Self.bestand()
        let mitglieder = Lernendenverzeichnis(b).mitglieder("g-5a", archivierte: true)
        let auswahl = Mitteilungsadressaten.einzelne([Self.clara, Self.anna, Self.david, "l-fremd"])
        #expect(auswahl.betroffene(mitglieder) == [Self.anna, Self.clara], "Folge der Liste, ohne David und Fremde")
        let (neu, id) = try Self.anlegen(b, auswahl)
        #expect(Self.betroffene(neu, id) == [Self.anna, Self.clara])
        let (eine, eineId) = try Self.anlegen(b, .einzelne([Self.ben]))
        #expect(Self.betroffene(eine, eineId) == [Self.ben], "an eine Person")
        #expect(!Mitteilungsadressaten.einzelne([]).anlegbar(mitglieder), "ohne Gewählte kein Anlegen")
        #expect(!Mitteilungsadressaten.einzelne([Self.david]).anlegbar(mitglieder), "nur Archivierte: kein Anlegen")
        #expect(Mitteilungsadressaten.einzelne([Self.ben]).gewaehlt == [Self.ben] && Mitteilungsadressaten.alle.gewaehlt.isEmpty)
    }

    // ── Wer später kommt, ist nicht betroffen ─────────────────────────────

    @Test("Wer nach dem Anlegen in die Lerngruppe kommt, ist nicht betroffen — nicht in der Tabelle, aber in „Auch an …“")
    func spaeterHinzukommende() throws {
        let (b0, id) = try Self.anlegen(Self.bestand(), .alle)
        // Fritz kommt von Hand dazu, Gina über die Namenseingabe.
        var b = b0
        b.lernende.append(Self.person("l-fritz", "Fritz", "Fuchs"))
        b = try #require(b.mitMitglied("l-fritz", inGruppe: "g-5a", jetzt: Self.jetzt))
        b = b.mitPersonen(Namenszeilen.lesen("Gans, Gina").namen, inGruppe: "g-5a", jetzt: Self.jetzt).bestand
        let gina = try #require(b.lernende.first { $0.nachname == "Gans" }).id
        #expect(Self.betroffene(b, id) == [Self.anna, Self.ben, Self.clara, Self.emil], "kein Automatismus")
        let v = Lernendenverzeichnis(b)
        let m = try #require(b.anliegen.first { $0.id == id })
        #expect(!Ruecklaufliste.zeilen(m, v.mitglieder("g-5a")).contains { ["l-fritz", gina].contains($0.id) })
        #expect(Ruecklaufliste.aufzunehmen(m, v.mitglieder("g-5a")).map(\.id).sorted() == ["l-fritz", gina].sorted(),
                "„Auch an …“ bietet beide an")
        // Auch Import und Zusammenführen nehmen niemanden von selbst auf (Z-BC4-04).
        let daten = ImportPruefungen.datei([ImportPruefungen.zeile("Hanna", "Holz", klasse: "5a")])
        let importiert = b.mitImport(try ImportPruefungen.lesung(daten), ziel: .gruppe("g-5a"), jetzt: Self.jetzt).bestand
        #expect(importiert.lernende.count == b.lernende.count + 1, "der Import nahm jemanden auf")
        #expect(Lernendenverzeichnis(importiert).mitglieder("g-5a").contains { $0.nachname == "Holz" },
                "Hanna kam in die Lerngruppe (W2-08)")
        #expect(Self.betroffene(importiert, id) == [Self.anna, Self.ben, Self.clara, Self.emil], "Import: kein Automatismus")
        var mitSechs = b
        mitSechs.lernende.append(Self.person("l-ida", "Ida", "Imhof"))
        mitSechs.lerngruppen.append(Lerngruppe(id: "g-6", name: "6", art: .klasse, mitglieder: ["l-ida"], zeilen: [],
                                               skalen: [:], halbjahreswechsel: "", geaendert: Self.s, archiviert: ""))
        let zusammen = mitSechs.mitZusammenfuehrung("g-6", in: "g-5a", jetzt: Self.jetzt).bestand
        #expect(Lernendenverzeichnis(zusammen).mitglieder("g-5a").contains { $0.id == "l-ida" }, "Ida kam dazu")
        #expect(Self.betroffene(zusammen, id) == [Self.anna, Self.ben, Self.clara, Self.emil],
                "Zusammenführen: kein Automatismus")
        // Von Hand aufgenommen: nur Fritz, nichts sonst.
        let mitFritz = b.mitBetroffenem(id, "l-fritz", true, jetzt: Self.jetzt)
        #expect(Self.betroffene(mitFritz, id) == [Self.anna, Self.ben, Self.clara, Self.emil, "l-fritz"])
        #expect(mitFritz.rueckmeldungen == b.rueckmeldungen)
    }

    @Test("An einzelne angelegt: Wer nicht gewählt war, bleibt außen vor — auch beim nächsten Anlegen an alle")
    func gewaehlteBleibenGetrennt() throws {
        let (b1, nurBen) = try Self.anlegen(Self.bestand(), .einzelne([Self.ben]), titel: "Nachfrage")
        let (b2, alle) = try Self.anlegen(b1, .alle, titel: "Elternabend")
        #expect(Self.betroffene(b2, nurBen) == [Self.ben])
        #expect(Self.betroffene(b2, alle) == [Self.anna, Self.ben, Self.clara, Self.emil])
    }

    // ── Wortlaute (V8 — Vorschläge für den Prototyp) ──────────────────────

    @Test("R-BH8-W2-01: „Einzelne …“ bleibt auf dem Blatt „Lernende“ rundum 40 pt kleiner — 600 bei voller Höhe")
    func bogenhoehe() {
        #expect(AdressatenBogen.hoehe(blatt: 820) == 600, "voll: wie bestellt")
        #expect(AdressatenBogen.hoehe(blatt: 660) == 580, "kleiner Bildschirm, anliegend")
        #expect(AdressatenBogen.hoehe(blatt: 552) == 472, "kleiner Bildschirm, das Fenster 60 pt tiefer")
        #expect(AdressatenBogen.hoehe(blatt: 480) == 400, "an der Untergrenze der Blätter")
    }

    @Test("Wortlaute: das Menü „an …“, „Einzelne …“, der Bogen, die Hilfe an „Anlegen“")
    func wortlaute() throws {
        let b = Self.bestand()
        let mitglieder = Lernendenverzeichnis(b).mitglieder("g-5a")
        #expect(Mitteilungsadressaten.alle.titel(mitglieder) == "an alle Mitglieder")
        #expect(Mitteilungsadressaten.einzelne([Self.ben]).titel(mitglieder) == "an Brandt, Ben", "eine Person mit Namen")
        #expect(Mitteilungsadressaten.einzelne([Self.ben, Self.anna, Self.david]).titel(mitglieder) == "an 2 Personen",
                "gezählt die aktiven")
        #expect(Mitteilungstext.einzelne == "Einzelne …" && Mitteilungstext.alleMitglieder == "Alle Mitglieder der Lerngruppe")
        #expect(Mitteilungstext.gewaehlt(3, von: 42) == "3 von 42 gewählt")
        #expect(Mitteilungstext.leer.contains("an alle Mitglieder oder an einzelne"))
        #expect(Knopfhilfe.mitteilungAnlegen == "Eine Mitteilung mit dem heutigen Tag anlegen — an alle Mitglieder dieser "
                + "Lerngruppe oder an die gewählten (⏎)")
        #expect(Lernendenvorgabe().adressaten == nil, "im Betrieb kein Bogen von selbst")
        // Wie im Prototyp (E994) — und „an niemanden“, wenn von der Auswahl niemand mehr aktiv ist (Z-BC4-02, -03).
        #expect(Mitteilungsadressaten.einzelne([Self.david]).titel(mitglieder) == "an niemanden")
        // Seit v96 nennen die Texte den Weg über das Zahnrad der Mitteilung (E1207, E1208).
        #expect(Mitteilungstext.ohneAdressaten == "Erst unter „Empfänger“ Mitglieder wählen")
        #expect(Mitteilungstext.anHilfe == "An wen die neue Mitteilung geht — vorgegeben alle Mitglieder der Lerngruppe. Wer "
                + "später hinzukommt, ist nicht betroffen; über das Zahnrad der Mitteilung („Weitere Empfänger“) lässt er "
                + "sich von Hand aufnehmen.")
        #expect(Mitteilungstext.niemandAuchAn == "Über das Zahnrad der Mitteilung („Weitere Empfänger“) lassen sich Mitglieder "
                + "aufnehmen.")
        #expect(Mitteilungstext.bogenTitel == "An einzelne Mitglieder")
        #expect(Mitteilungstext.bogenFuss == "Die neue Mitteilung betrifft nur die Gewählten. Wer später in die Lerngruppe "
                + "kommt, ist nicht betroffen — über das Zahnrad der Mitteilung („Weitere Empfänger“) lässt er sich von Hand "
                + "aufnehmen.")
    }

    // ── Der Bogen hängt am Blatt (E490) — am Quelltext ────────────────────

    @Test("Der Bogen „Einzelne …“ liegt auf „Neue Mitteilung“: Meldungen und die Frage beim Beenden stehen auf ihm, ⌘Q schließt mit")
    func bogenAmBlatt() throws {
        let datei = URL(filePath: #filePath)
            .deletingLastPathComponent()      // Pruefungen
            .deletingLastPathComponent()      // Fassungsordner
            .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Dialoge/LernendenDialog.swift")
        let text = try String(contentsOf: datei, encoding: .utf8)
        // Seit v96 auf dem Unterblatt (E1172): Das Blatt kennt das Unterblatt als Bogen, `bogenSchliessen` schließt es samt
        // „Einzelne …“ (R-BH5-02, R-BH5-03).
        #expect(text.contains("|| neueMitteilungOffen || mitteilungseinstellungenFuer != nil"), "`bogenDarauf` (E490)")
        #expect(text.contains("neueMitteilungOffen = false\n"), "`bogenSchliessen`")
        #expect(!text.contains("adressatenbogen"), "kein Bogen „Einzelne …“ mehr am Blatt")
        let ansicht = try String(contentsOf: datei.deletingLastPathComponent().appending(path: "AnliegenAnsicht.swift"),
                                 encoding: .utf8)
        let bogen = try #require(ansicht.range(
            of: "AdressatenBogen(vorlage: vorlage, hoehe: AdressatenBogen.hoehe(blatt: blatthoehe))"))
        let frage = try #require(ansicht.range(of: ".rueckfrageAmBogen(speicher)", range: bogen.upperBound..<ansicht.endIndex))
        #expect(ansicht.distance(from: bogen.upperBound, to: frage.lowerBound) < 120, "die Rückfrage steht auf dem Bogen")
        #expect(ansicht.contains(".rueckfrageAmBogen(speicher, zuoberst: einzelne == nil)"),
                "das Unterblatt fragt nur ohne den Bogen darauf")
        // Meldungen stehen auf dem Bogen: seine eigene Zeile — im schmalen Bogen über den Knöpfen statt in der Lücke im Fuß
        // (E855, E1061; Z-BC4-02).
        let bogendatei = datei.deletingLastPathComponent().appending(path: "AdressatenBogen.swift")
        let bogentext = try String(contentsOf: bogendatei, encoding: .utf8)
        #expect(bogentext.contains("meldungsblatt: .lernende") && bogentext.contains("Fussluecke()"),
                "der Bogen trägt die Meldungszeile des Blatts")
    }

    @Test("E1001 (seit v96): Jedes Unterblatt „Neue Mitteilung“ beginnt „an alle“; der Bogen zeigt die bisherige Auswahl")
    func zustand() throws {
        func quelle(_ name: String) throws -> String {
            let datei = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Dialoge/" + name)
            return try String(contentsOf: datei, encoding: .utf8).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        // Am Quelltext, Leerraum zusammengezogen (Z-BC4-01). Seit v96 hält das Unterblatt die Adressaten (E1172): Es entsteht
        // je „Neue Mitteilung …“ neu — nach dem Anlegen, nach einem Wechsel der Lerngruppe und beim Öffnen des Blatts gilt
        // wieder „an alle“; das Blatt hält keine Adressaten mehr (R-BH5-03).
        let ansicht = try quelle("AnliegenAnsicht.swift"), blatt = try quelle("LernendenDialog.swift")
        #expect(ansicht.contains("@State private var an: Mitteilungsadressaten = .alle"), "das Unterblatt beginnt „an alle“")
        #expect(!blatt.contains("Mitteilungsadressaten"), "keine Adressaten am Blatt")
        #expect(ansicht.contains("Adressatenvorlage(gruppe: gruppe, mitglieder: mitglieder, vorgewaehlt: an.gewaehlt)"),
                "der Bogen zeigt die bisherige Auswahl")
    }
}
