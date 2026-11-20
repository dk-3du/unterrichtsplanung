// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die Leistungsdokumentation an der Zeile (v85, AW8a, E662, E709, E710; Oberfläche v86, AX6) ──
// Ein vierter Dateiverweis je Zeile, unter dem Sitzplan, an jeder Zeilenart —
// auch an Klassenleitung, Weiteres und Vertretungen. Die Datei liegt außerhalb
// der App; gemerkt wird nur der Pfad, wie bei Verwaltungsdatei und Curriculum.
// In der Planungsdatei steht er nur, wo gesetzt (die Fassung bleibt 2, E709);
// beim Schuljahreswechsel kommt er nicht mit (E710). Die Fälle zum Lesen stehen
// wortgleich in `Web-App/vNN/leser_pruefen.py` („Leistungsdokumentation: …“).

@Suite("Leistungsdokumentation an der Zeile (E662, E709, E710)")
@MainActor
struct LeistungsdokumentationPruefungen {

    // ── Die Arten und die Oberfläche ──────────────────────────────────────

    @Test("Über dem Sitzplan bleiben Verwaltungsdatei und Curriculum; die Leistungsdokumentation steht darunter (E662)")
    func artenUmDenSitzplan() {
        #expect(Kursdateiart.ueberDemSitzplan == [.verwaltung, .curriculum])
        #expect(Kursdateiart.unterDemSitzplan == [.leistungsdokumentation])
        #expect(Kursdateiart.alle == [.verwaltung, .curriculum, .leistungsdokumentation])
        #expect(Set(Kursdateiart.alle).count == Kursdateiart.alle.count, "jede Art einmal")
    }

    /// Die Kurszelle (`Klassenkopf` in Raster.swift) stellt die Leistungsdokumentation unter den Sitzplan, ⌘K
    /// (`KlassenDialog`) die Menüspalte nach ihm; `Zellenmass` zählt die vierte Zeile mit (AX6, E774).
    @Test("Kurszelle mit vier Zeilen (E774): allCases heißt wieder alle; ein gesetzter Verweis ändert die Höhe nicht")
    func vierZeilen() {
        #expect(Kursdateiart.allCases == Kursdateiart.alle, "keine Übergangszeile mehr")
        #expect(Zellenmass.verwaltungszeilen == 4, "Verwaltungsdatei, Curriculum, Sitzplan, Leistungsdokumentation")
        var klasse = Klasse(id: "k1", name: "5a", fach: "Biologie", notiz: "", farbe: 0, farbeManuell: false)
        let ohne = Zellenmass.kopfhoehe(klasse)
        klasse.leistungsdokumentation = "Noten/5a.numbers"
        #expect(Zellenmass.kopfhoehe(klasse) == ohne, "ein gesetzter Verweis ändert die Höhe nicht")
    }

    @Test("Gesperrte Zeile der Kurszelle: „keine Verwaltungsdatei“, aber „kein Sitzplan“ — der Artikel folgt dem Wort")
    func gesperrtMitArtikel() {
        let verneint = Kursdateiart.alle.map { $0.verneint }
        #expect(verneint == ["keine Verwaltungsdatei", "keine Curriculumdatei", "keine externe Leistungsdokumentation"])
        #expect(Klassenkopf.gesperrtHilfe(zeile: "Vertretungen", verneint: Kursdateiart.curriculum.verneint)
                == "Für „Vertretungen“ ist keine Curriculumdatei vorgesehen")
        #expect(Klassenkopf.gesperrtHilfe(zeile: "Weiteres", verneint: Klassenkopf.keinSitzplan)
                == "Für „Weiteres“ ist kein Sitzplan vorgesehen")
    }

    @Test("Ein Satz für die gesperrte Zeile (Z-AX6-06): Kurszelle und Meldung bilden ihn über `nichtVorgesehen` — je Art (⌘K: `kommandoK…`)")
    func einSatzFuerAlleStellen() throws {
        let erwartet = ["Für „Vertretungen“ ist keine Verwaltungsdatei vorgesehen",
                        "Für „Vertretungen“ ist keine Curriculumdatei vorgesehen",
                        "Für „Vertretungen“ ist keine externe Leistungsdokumentation vorgesehen"]
        let saetze = Kursdateiart.alle.map { $0.nichtVorgesehen(an: "Vertretungen") }
        #expect(saetze == erwartet)
        let hilfen = Kursdateiart.alle.map { Klassenkopf.gesperrtHilfe(zeile: "Vertretungen", verneint: $0.verneint) }
        #expect(hilfen == erwartet, "die Kurszelle")
        // Die Meldung, wenn ein Weg an der Oberfläche vorbei eine Art an eine Zeile setzen will, die sie nicht trägt.
        let p = Planung.leer(titel: "Satz", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
                             klassen: Zeilenart.sonderzeilen.map(Klasse.sonderzeile), fachfarben: [:])
        let s = Planungsspeicher(vorschau: p)
        let kl = try #require(p.klassen.first { $0.art == .klassenleitung }).id
        let ve = try #require(p.klassen.first { $0.art == .vertretungen }).id
        #expect(!s.erlaubtAnZeile(ve, .verwaltung))
        #expect(s.meldungen.last?.text == "Für „Vertretungen“ ist keine Verwaltungsdatei vorgesehen.",
                Comment(rawValue: s.meldungen.last?.text ?? "—"))
        #expect(!s.erlaubtAnZeile(kl, .curriculum))
        #expect(s.meldungen.last?.text == Kursdateiart.curriculum.nichtVorgesehen(an: "Klassenleitung") + ".",
                Comment(rawValue: s.meldungen.last?.text ?? "—"))
        // Die Leistungsdokumentation trägt jede Zeile (E662): kein Satz, keine Meldung.
        let zahl = s.meldungen.count
        #expect(s.erlaubtAnZeile(ve, .leistungsdokumentation) && s.meldungen.count == zahl)
    }

    // ── ⌘K: Hilfen an gesperrten Spalten und Fuß (Z-AX6N-02, -03, E800) ──
    // Die Wortlaute sind die von heute; neu ist nur, dass sie aus reinen Funktionen kommen und hier geprüft werden.

    @Test("⌘K, Kursdateien: dieselben Sätze wie heute und wie in der Kurszelle — je Art (Z-AX6N-02)")
    func kommandoKKursdateien() {
        let erwartet = ["Für „Vertretungen“ ist keine Verwaltungsdatei vorgesehen",
                        "Für „Vertretungen“ ist keine Curriculumdatei vorgesehen",
                        "Für „Vertretungen“ ist keine externe Leistungsdokumentation vorgesehen"]
        let kommandoK = Kursdateiart.alle.map { KlassenDialog.gesperrtHilfe($0, zeile: "Vertretungen") }
        let kurszelle = Kursdateiart.alle.map { Klassenkopf.gesperrtHilfe(zeile: "Vertretungen", verneint: $0.verneint) }
        #expect(kommandoK == erwartet)
        #expect(kommandoK == kurszelle, "⌘K und Kurszelle bilden denselben Satz")
    }

    @Test("⌘K, Sitzplan: „kein Sitzplan“ wie heute und wie in der Kurszelle (Z-AX6N-03)")
    func kommandoKSitzplan() {
        let hilfe = KlassenDialog.sitzplanGesperrtHilfe(zeile: "Weiteres")
        #expect(hilfe == "Für „Weiteres“ ist kein Sitzplan vorgesehen")
        #expect(hilfe == Klassenkopf.gesperrtHilfe(zeile: "Weiteres", verneint: Klassenkopf.keinSitzplan))
    }

    @Test("⌘K, Lerngruppe: „keine Lerngruppe“ wie heute")
    func kommandoKLerngruppe() {
        #expect(KlassenDialog.lerngruppeGesperrtHilfe(zeile: "Vertretungen")
                == "Für „Vertretungen“ ist keine Lerngruppe vorgesehen")
    }

    @Test("⌘K, Fach: „kein Fach“ wie heute")
    func kommandoKFach() {
        #expect(KlassenDialog.fachGesperrtHilfe(zeile: "Weiteres") == "Für „Weiteres“ ist kein Fach vorgesehen")
    }

    @Test("E881: Die fertigen Sätze von `Kursdateiart` für Kurszelle und ⌘K wörtlich wie in der Tabelle (Z-AY6-01)")
    func saetzeWieInDerTabelle() {
        // Dass Raster.swift (Hilfe, VoiceOver, Wählen) und KlassenDialog.swift (Hilfe, VoiceOver in ⌘K) diese Sätze
        // aufrufen, ist durch Lesen gesichert, nicht durch diese Prüfung (Z-AY6N-01).
        let art = Kursdateiart.leistungsdokumentation
        #expect(art.oeffnenHilfe("/Noten/7b.xlsx") == "Externe Leistungsdokumentation öffnen: /Noten/7b.xlsx")
        #expect(art.oeffnenBedienung("7b") == "Externe Leistungsdokumentation von 7b öffnen")
        #expect(art.waehlenHilfe("7b") == "Externe Leistungsdokumentation für 7b wählen")
        #expect(art.zuweisenHilfe(gesetzt: "/Noten/7b.xlsx") == "Externe Leistungsdokumentation: /Noten/7b.xlsx")
        #expect(art.zuweisenHilfe(gesetzt: nil) == "Externe Leistungsdokumentation zuweisen")
        #expect(art.zuweisenBedienung("7b", gesetzt: true) == "Externe Leistungsdokumentation von 7b")
        #expect(art.zuweisenBedienung("7b", gesetzt: false) == "Externe Leistungsdokumentation für 7b zuweisen")
        #expect(Kursdateiart.curriculum.waehlenHilfe("7b") == "Curriculumdatei für 7b wählen", "die übrigen Arten wie bisher")
        #expect(Kursdateiart.verwaltung.oeffnenHilfe("/x") == "Verwaltung öffnen: /x")
    }

    @Test("⌘K, Fuß (E800, E881): nach „… Vertretungen keines von dreien.“ der Satz „Die externe Leistungsdokumentation trägt jede Zeile.“")
    func kommandoKFuss() {
        #expect(KlassenDialog.fussKlassen.contains("keinen Sitzplan; Vertretungen keines von dreien. Die externe Leistungsdokumentation "
                                                   + "trägt jede Zeile. Ein Fach trägt neben den Klassen/Kursen"),
                Comment(rawValue: KlassenDialog.fussKlassen))
        // E825: Die Unterrichtstage hebt auch das Untermenü „Wochentag“ hervor (E781).
        #expect(KlassenDialog.fussKlassen.contains("regelmäßig Unterricht stattfindet; der Vorhaben-Dialog und das Untermenü "
                                                   + "„Wochentag“ der Kachel heben sie hervor. Eine Änderung hier"),
                Comment(rawValue: KlassenDialog.fussKlassen))
    }

    /// Der Klassenkopf im unsichtbaren Fenster, ohne Ereignisschleife und ohne Uhr gemessen (Z-AX6-01). Bei einzeiligen
    /// Bezeichnungen ist er gezeichnet 1 Punkt niedriger als gerechnet (gemessen 23.10.2026 am Mac: „5a“ 143 zu 144,
    /// „Vertretungen“ 128 zu 129) — die Reserve, die `Zellenmass.texthoehe` einrechnet, weil SwiftUIs Zeile bis zu einen
    /// Punkt über `defaultLineHeight` liegt; die Zeile im Raster trägt ihn ganz. Fehlte eine der vier Zeilen, fehlten 22.
    /// Mehrzeilige Bezeichnungen und andere Umgebungen (VM, ohne Bildschirm) misst die Prüfung nicht (Z-AX6N-04). Die
    /// Folge der Zeilen (die Leistungsdokumentation unter dem Sitzplan) zeigt die Messung nicht.
    @Test("Kurszelle gemessen (Z-AX6-01): Die gezeichnete Höhe passt in die gerechnete, höchstens 1 Punkt Luft — Unterricht und Vertretungen")
    func kurszelleGemessen() throws {
        let p = Planung.leer(titel: "Mass", start: try #require(Tag(iso: "2026-08-10")), wochen: 4, basis: "",
                             klassen: Standardkurse.aufbauen([("5a", "Biologie")]) + [Klasse.sonderzeile(.vertretungen)],
                             fachfarben: [:])
        let s = Planungsspeicher(vorschau: p)
        var gemessen: [String] = []
        for klasse in p.klassen {
            let ansicht = NSHostingView(rootView: Klassenkopf(klasse: klasse).environment(s)
                .frame(width: Masse.spalteKlasse))
            let fenster = NSWindow(contentRect: CGRect(x: 0, y: 0, width: Masse.spalteKlasse, height: 400),
                                   styleMask: [.borderless], backing: .buffered, defer: true)
            fenster.isReleasedWhenClosed = false
            fenster.contentView = ansicht
            ansicht.layoutSubtreeIfNeeded()
            let hoehe = ansicht.fittingSize.height
            gemessen.append("\(klasse.name): \(hoehe) / \(Zellenmass.kopfhoehe(klasse))")
            let luft = Zellenmass.kopfhoehe(klasse) - hoehe
            #expect(luft >= 0 && luft <= 1, Comment(rawValue: gemessen.last ?? ""))
            fenster.contentView = nil
        }
    }

    @Test("An jeder Zeilenart erlaubt — auch an den Vertretungen; was die Zeile sonst kann, bleibt (E161, E662)")
    func erlaubtUeberall() {
        for art in Zeilenart.allCases {
            #expect(art.erlaubt(.leistungsdokumentation), Comment(rawValue: art.rawValue))
        }
        for art in Zeilenart.sonderzeilen {
            #expect(Klasse.sonderzeile(art).erlaubt(.leistungsdokumentation), Comment(rawValue: art.titel))
        }
        // `erlaubt(.verwaltung)` heißt zugleich: Die Zeile kann eine Lerngruppe tragen — unverändert.
        #expect(Zeilenart.allCases.map { $0.erlaubt(.verwaltung) } == [true, true, true, false])
        #expect(Zeilenart.allCases.map { $0.erlaubt(.curriculum) } == [true, false, false, false])
        #expect(Zeilenart.allCases.map(\.erlaubtSitzplan) == [true, false, false, false])
    }

    @Test("Wortlaute, Zeichen und Schrittnamen nach dem Muster von Verwaltungsdatei und Curriculum (E769, E770)")
    func wortlaute() {
        let art = Kursdateiart.leistungsdokumentation
        #expect(art.rawValue == "leistungsdokumentation")
        #expect(art.angebot == "+ Leistungsdokumentation", "bleibt (E881, Nutzer)")
        #expect(art.beschriftung == "Externe Leistungsdokumentation")
        #expect(art.dateibeschriftung == "Externe Leistungsdokumentation")
        #expect(art.auswahltitel == "Externe Leistungsdokumentation wählen")
        #expect(art.symbol == Zeichen.leistungsdokumentation
                && art.symbolGesetzt == Zeichen.leistungsdokumentationGesetzt)
        #expect(art.symbol != art.symbolGesetzt, "gesetzt und Angebot unterscheiden sich")
        for name in [art.symbol, art.symbolGesetzt] {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                    Comment(rawValue: "kein SF-Zeichen: „\(name)“"))
        }
        let vergeben = [Zeichen.kursdatei, Zeichen.kursdateiGesetzt, Zeichen.curriculum, Zeichen.curriculumGesetzt,
                        Zeichen.sitzplan, Zeichen.sitzplanGesetzt, Zeichen.datei, Zeichen.pruefung, Zeichen.tagesliste]
        #expect(Set([art.symbol, art.symbolGesetzt]).isDisjoint(with: vergeben),
                "nicht mit den anderen Verweisen der Zeile zu verwechseln")
        // Die beiden bisherigen bleiben wortgleich.
        #expect(Kursdateiart.verwaltung.angebot == "+ Verwaltungsdatei" && Kursdateiart.curriculum.angebot == "+ Curriculum")
        #expect(Kursdateiart.verwaltung.auswahltitel == "Verwaltungsdatei wählen"
                && Kursdateiart.curriculum.auswahltitel == "Curriculumdatei wählen")
        #expect(Schrittname.leistungsdokumentationHinterlegen == "Externe Leistungsdokumentation hinterlegen")
        #expect(Schrittname.leistungsdokumentationEntfernen == "Externe Leistungsdokumentation entfernen")
        #expect(Schrittname.alle.contains(Schrittname.leistungsdokumentationHinterlegen)
                && Schrittname.alle.contains(Schrittname.leistungsdokumentationEntfernen))
    }

    @Test("Pfad und Angabe an der Zeile — unabhängig von Verwaltungsdatei und Curriculum")
    func pfadUndAngabe() {
        var k = Klasse(id: "k1", name: "5a", fach: "Biologie", notiz: "", farbe: 0, farbeManuell: false)
        #expect(!k.hat(.leistungsdokumentation) && k.pfad(.leistungsdokumentation).isEmpty)
        k.leistungsdokumentation = "Noten/5a.numbers"
        #expect(k.hat(.leistungsdokumentation) && k.hatLeistungsdokumentation)
        #expect(k.pfad(.leistungsdokumentation) == "Noten/5a.numbers")
        #expect(!k.hat(.verwaltung) && !k.hat(.curriculum), "die beiden anderen bleiben leer")
        k.leistungsdokumentation = " \t"
        #expect(!k.hat(.leistungsdokumentation), "nur Leerraum ist keine Angabe — wie bei den anderen")
    }

    // ── Die Datei (E709) ──────────────────────────────────────────────────

    /// Zwei Kurse und die drei Sonderzeilen; gesetzt an allen außer „6b“.
    private func planungMitAllenArten() throws -> Planung {
        var p = Planung.leer(titel: "Probe", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
                             basis: "/Users/lehrkraft/Unterricht",
                             klassen: Standardkurse.aufbauen([("5a", "Biologie"), ("6b", "Chemie")])
                                 + Zeilenart.sonderzeilen.map(Klasse.sonderzeile),
                             fachfarben: [:])
        p.klassen[0].leistungsdokumentation = "Noten/5a.numbers"
        p.klassen[2].leistungsdokumentation = "/Users/lehrkraft/Klassenleitung/7a-Noten.numbers"
        p.klassen[3].leistungsdokumentation = "AG/Bewertung.pdf"
        p.klassen[4].leistungsdokumentation = "Vertretungen/Mitschrift.numbers"
        return p
    }

    private static let gesetzt: [String] = ["Noten/5a.numbers", "", "/Users/lehrkraft/Klassenleitung/7a-Noten.numbers",
                                            "AG/Bewertung.pdf", "Vertretungen/Mitschrift.numbers"]

    private func klassenObjekte(_ daten: Data) throws -> [[String: Any]] {
        let objekt = try #require(JSONSerialization.jsonObject(with: daten) as? [String: Any])
        return try #require(objekt["klassen"] as? [[String: Any]])
    }

    @Test("Rundweg durch die Datei: an jeder Zeilenart, nur wo gesetzt, leere Bilanz; die Fassung bleibt 2 (E709)")
    func rundweg() throws {
        let p = try planungMitAllenArten()
        let daten = try Planungsdatei.schreiben(p)
        let (gelesen, bilanz) = try Planungsdatei.lesenMitBilanz(daten)
        #expect(gelesen.klassen.map(\.leistungsdokumentation) == Self.gesetzt)
        #expect(gelesen.klassen.map(\.art) == [.unterricht, .unterricht, .klassenleitung, .weiteres, .vertretungen])
        #expect(bilanz.istLeer)
        let zeilen = try klassenObjekte(daten)
        #expect(zeilen.map { $0["leistungsdokumentation"] as? String } == Self.gesetzt.map { (wert: String) -> String? in wert.isEmpty ? nil : wert },
                "nur, wo gesetzt")
        let objekt = try #require(JSONSerialization.jsonObject(with: daten) as? [String: Any])
        #expect(objekt["version"] as? Int == 2, "E709: kein Sprung der Fassung")
        let wieder = try Planungsdatei.schreiben(gelesen)
        #expect(wieder == daten, "ein zweiter Rundweg ändert nichts")
    }

    /// Geschrieben vom bisherigen Schreiber (Stand AW0-fertig; übersetzt aus dem
    /// unveränderten Modell, AW8a): eine Planung ohne Leistungsdokumentation mit
    /// allen Zeilenarten und den beiden bisherigen Dateiverweisen.
    private static let dateiOhneLeistungsdokumentation = #"""
        {
          "basis" : "/Users/lehrkraft/Unterricht",
          "eintraege" : [
            {
              "datum" : "",
              "dringend" : false,
              "erledigt" : false,
              "hausaufgabe" : false,
              "hausaufgabenText" : "",
              "id" : "e-1",
              "klasseId" : "k-5a",
              "kommentar" : "",
              "korrektur" : false,
              "links" : [],
              "materialien" : [
                {
                  "pfad" : "Bio/AB.pdf",
                  "titel" : "AB"
                }
              ],
              "pruefung" : false,
              "pruefungstag" : "",
              "statusGeaendert" : "",
              "text" : "Einstieg",
              "titel" : "Zelle",
              "woche" : 1
            }
          ],
          "erstellt" : "2026-08-01T09:00:00.000Z",
          "ersterSchultag" : "2026-08-10",
          "fachfarben" : {
            "biologie" : "blau-mittel"
          },
          "ferien" : [
            {
              "bis" : "2026-10-16",
              "id" : "f-herbst",
              "name" : "Herbstferien",
              "von" : "2026-10-05"
            }
          ],
          "frei" : [],
          "geaendert" : "2026-08-02T10:30:00.000Z",
          "klassen" : [
            {
              "art" : "unterricht",
              "curriculum" : "/Lehrplaene/Bio.pdf",
              "fach" : "Biologie",
              "farbe" : 0,
              "farbeManuell" : false,
              "id" : "k-5a",
              "name" : "5a",
              "notiz" : "Doppelstunde",
              "unterrichtstage" : [
                1,
                3
              ],
              "verwaltung" : "Listen/5a.numbers"
            },
            {
              "art" : "unterricht",
              "curriculum" : "",
              "fach" : "Chemie",
              "farbe" : 3,
              "farbeManuell" : true,
              "id" : "k-6b",
              "name" : "6b",
              "notiz" : "",
              "unterrichtstage" : [],
              "verwaltung" : ""
            },
            {
              "art" : "klassenleitung",
              "curriculum" : "",
              "fach" : "7a",
              "farbe" : 5,
              "farbeManuell" : false,
              "id" : "k-kl",
              "name" : "Klassenleitung",
              "notiz" : "",
              "unterrichtstage" : [],
              "verwaltung" : "KL/7a.numbers"
            },
            {
              "art" : "weiteres",
              "curriculum" : "",
              "fach" : "",
              "farbe" : 6,
              "farbeManuell" : false,
              "id" : "k-we",
              "name" : "Weiteres",
              "notiz" : "AG",
              "unterrichtstage" : [],
              "verwaltung" : ""
            },
            {
              "art" : "vertretungen",
              "curriculum" : "",
              "fach" : "",
              "farbe" : 7,
              "farbeManuell" : false,
              "id" : "k-ve",
              "name" : "Vertretungen",
              "notiz" : "",
              "unterrichtstage" : [],
              "verwaltung" : ""
            }
          ],
          "sperrzeiten" : [],
          "start" : "2026-08-10",
          "titel" : "Schuljahr 2026/27",
          "typ" : "unterrichtsplanung",
          "version" : 2,
          "wochen" : 6,
          "zellenfrei" : []
        }
        """#

    @Test("Nur geschrieben, wo gesetzt: Eine Datei ohne Leistungsdokumentation liest und schreibt sich Byte für Byte gleich (E709, wie der Termin E293)")
    func alteDateiBytegleich() throws {
        let alt = Data(Self.dateiOhneLeistungsdokumentation.utf8)
        let (gelesen, bilanz) = try Planungsdatei.lesenMitBilanz(alt)
        #expect(bilanz.istLeer)
        #expect(gelesen.klassen.allSatisfy { $0.leistungsdokumentation.isEmpty })
        let neu = try Planungsdatei.schreiben(gelesen)
        #expect(neu == alt, "Byte für Byte, wie der bisherige Schreiber sie schrieb")

        // Eine gesetzt: genau ein Schlüssel mehr, an dieser Zeile — und wieder entfernt, die alten Bytes.
        var mit = gelesen
        mit.klassen[4].leistungsdokumentation = "Vertretungen/Mitschrift.numbers"
        let zeilenAlt = try klassenObjekte(alt)
        let zeilenMit = try klassenObjekte(try Planungsdatei.schreiben(mit))
        let hinzu = zip(zeilenAlt, zeilenMit).map { Set($1.keys).subtracting($0.keys).sorted() }
        #expect(hinzu == [[], [], [], [], ["leistungsdokumentation"]])
        mit.klassen[4].leistungsdokumentation = ""
        let ohne = try Planungsdatei.schreiben(mit)
        #expect(ohne == alt, "entfernt, schreibt sie sich wieder wie zuvor")
    }

    /// Wortgleich in `leser_pruefen.py`: dieselben Rohdaten, dieselbe Meldung.
    private func lesen(_ klassen: String) throws -> (planung: Planung, uebergangen: String) {
        let roh = #"{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","wochen":4,"klassen":["#
            + klassen + "]}"
        let (planung, bilanz) = try Planungsdatei.lesenMitBilanz(Data(roh.utf8))
        let teile = bilanz.verworfenes + bilanz.hinweise
        return (planung, teile.isEmpty ? "" : "Übergangen: " + teile.joined(separator: ", ") + ".")
    }

    @Test("Lesen wie die Web App: Pfadlänge, Bereinigung und Zählung wie bei den anderen Dateiverweisen")
    func lesenWieDieWebApp() throws {
        let langerPfad = String(repeating: "p", count: Planungsdatei.maxPfadlaenge + 200)
        let lang = try lesen(#"{"id":"k1","name":"5a","leistungsdokumentation":"\#(langerPfad)"}"#)
        #expect(lang.planung.klassen[0].leistungsdokumentation.count == Planungsdatei.maxPfadlaenge)
        #expect(lang.uebergangen == "Übergangen: 1 gekürzter Text.")

        let jede = try lesen(#"{"id":"k1","name":"7a","leistungsdokumentation":"a.numbers"},"#
            + #"{"id":"k2","art":"klassenleitung","leistungsdokumentation":"b.numbers"},"#
            + #"{"id":"k3","art":"weiteres","leistungsdokumentation":"c.numbers"},"#
            + #"{"id":"k4","art":"vertretungen","leistungsdokumentation":"d.numbers"}"#)
        #expect(jede.planung.klassen.map(\.leistungsdokumentation) == ["a.numbers", "b.numbers", "c.numbers", "d.numbers"])
        #expect(jede.uebergangen == "", "an keiner Zeilenart verworfen")

        let steuer = try lesen(#"{"id":"k1","name":"5a","leistungsdokumentation":"Noten\#("\u{202E}")5a.numbers"}"#)
        #expect(steuer.planung.klassen[0].leistungsdokumentation == "Noten5a.numbers")
        #expect(steuer.uebergangen == "Übergangen: 1 bereinigter Text.")

        let kein = try lesen(#"{"id":"k1","name":"5a","leistungsdokumentation":7},"#
            + #"{"id":"k2","name":"5b","leistungsdokumentation":true},{"id":"k3","name":"5c","leistungsdokumentation":{}}"#)
        #expect(kein.planung.klassen.map(\.leistungsdokumentation) == ["", "", ""], "nur Text ist ein Pfad")
        #expect(kein.uebergangen == "")
    }

    // ── Der Schuljahreswechsel (E710) ─────────────────────────────────────

    @Test("Schuljahreswechsel (E710): Die Leistungsdokumentation kommt nicht mit — Verwaltungsdatei und Curriculum wie bisher")
    func wechselOhneLeistungsdokumentation() throws {
        var alt = try planungMitAllenArten()
        alt.klassen[0].verwaltung = "Listen/5a.numbers"
        alt.klassen[0].curriculum = "Lehrplaene/Bio.pdf"
        alt.klassen[2].verwaltung = "KL/7a.numbers"
        let (neu, bilanz) = Planung.mitUebernahme(
            titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4,
            basis: "/Users/lehrkraft/Unterricht", klassen: [], fachfarben: [:], von: alt,
            uebernahme: alt.klassen.map { .init(klasse: $0, mitVorhaben: false) })
        #expect(bilanz.klassen == 5)
        #expect(neu.klassen.map(\.leistungsdokumentation) == ["", "", "", "", ""], "im neuen Jahr leer")
        #expect(neu.klassen.map(\.verwaltung) == ["/Users/lehrkraft/Unterricht/Listen/5a.numbers", "",
                                                  "/Users/lehrkraft/Unterricht/KL/7a.numbers", "", ""])
        #expect(neu.klassen[0].curriculum == "/Users/lehrkraft/Unterricht/Lehrplaene/Bio.pdf")
    }

    @Test("Auch über den Speicher: „Neue Planung“ mit übernommenen Zeilen bringt keine Leistungsdokumentation mit (E710)")
    func neuePlanungAmSpeicher() throws {
        let alt = try planungMitAllenArten()
        let speicher = Planungsspeicher(vorschau: alt)
        speicher.neuePlanung(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4,
                             basis: "/Users/lehrkraft/Unterricht", klassen: [], ersterSchultag: nil,
                             uebernahme: alt.klassen.map { .init(klasse: $0, mitVorhaben: false) }, ohneMitglieder: [])
        let neu = try #require(speicher.planung)
        #expect(neu.titel == "Schuljahr 2027/28", "die neue Planung gilt")
        #expect(neu.klassen.count == 5)
        #expect(neu.klassen.allSatisfy { $0.leistungsdokumentation.isEmpty })
    }

    // ── Am Speicher: setzen, entfernen, ⌘Z ────────────────────────────────

    private static func speicherMitVertretungen() throws -> (Planungsspeicher, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "leistung-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        s.planung = Planung.leer(
            titel: "Leistung", start: try #require(Tag(iso: "2026-08-03")), wochen: 8, basis: "",
            klassen: [Klasse(id: "k1", name: "G6a", fach: "Informatik", notiz: "", farbe: 0, farbeManuell: false),
                      Klasse(id: "kv", name: "Vertretungen", fach: "", notiz: "", farbe: 1, farbeManuell: false,
                             art: .vertretungen)],
            fachfarben: [:])
        return (s, ordner)
    }

    @Test("Am Speicher: setzen und entfernen mit eigenem Schrittnamen, ⌘Z und ⇧⌘Z — am Kurs und an den Vertretungen")
    func amSpeicher() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try Self.speicherMitVertretungen()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let meldungenVorher = s.meldungen.count
            for id in ["k1", "kv"] {
                #expect(s.erlaubtAnZeile(id, .leistungsdokumentation), Comment(rawValue: id))
                let vorher = try #require(s.planung)
                s.kursdateiSetzen(klasse: id, art: .leistungsdokumentation, pfad: "/tmp/leistung-\(id).numbers")
                let gesetzt = try #require(s.planung)
                #expect(gesetzt.klasse(id)?.leistungsdokumentation == "/tmp/leistung-\(id).numbers", Comment(rawValue: id))
                #expect(gesetzt.klasse(id)?.verwaltung == vorher.klasse(id)?.verwaltung
                        && gesetzt.klasse(id)?.curriculum == vorher.klasse(id)?.curriculum,
                        Comment(rawValue: "\(id): Verwaltungsdatei und Curriculum bleiben"))
                #expect(s.verlauf.naechsterName == Schrittname.leistungsdokumentationHinterlegen, Comment(rawValue: id))
                s.widerrufen()
                #expect(s.planung == vorher, Comment(rawValue: id))
                s.wiederholen()
                #expect(s.planung == gesetzt, Comment(rawValue: id))

                s.kursdateiSetzen(klasse: id, art: .leistungsdokumentation, pfad: nil)
                #expect(s.planung?.klasse(id)?.leistungsdokumentation == "", Comment(rawValue: id))
                #expect(s.verlauf.naechsterName == Schrittname.leistungsdokumentationEntfernen, Comment(rawValue: id))
                s.widerrufen()
                #expect(s.planung == gesetzt, Comment(rawValue: id))
            }
            #expect(s.meldungen.count == meldungenVorher, "nichts zu melden — die Art ist an jeder Zeile vorgesehen")
        }
    }
}
