// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Blätter mit Seitenleiste (v95, E1101–E1120): Die Größe kommt aus dem Blatt selbst, fest in beiden Richtungen, gleich
/// welcher Eintrag gewählt ist; die Leiste ist eine Tabelle mit einer einzigen, festen Zeilenhöhe. Was sich nur am Fenster
/// zeigt (Wahl, Kennzeichen, Ruhe der Zeilen über viele Wechsel), prüft die Dialogprobe.
@Suite("Blätter mit Seitenleiste", .serialized)
@MainActor
struct SeitenleistePruefungen {

    init() throws {
        try #require(Ablage.istPruefstand, "die Blätter brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private static func planung() throws -> Planung {
        var planung = Planung.leer(titel: "Seitenleiste", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
                                   basis: "/Users/lehrkraft/Unterricht",
                                   klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        planung.eintraege.append(Vorhaben(id: Kennung.neu("e"), klasseId: planung.klassen[0].id, woche: 0,
                                          titel: "Zellen unter dem Mikroskop", text: "", erledigt: false,
                                          materialien: [], links: []))
        return planung
    }

    /// Die Größe, die das Blatt selbst vorgibt — ohne Fenster, aus `sizeThatFits` bei einem viel zu kleinen und einem
    /// viel zu großen Vorschlag: Nur ein in beiden Richtungen festes Blatt antwortet beide Male gleich (R-BG4-07).
    static func groesse(_ ansicht: some View) -> CGSize {
        let steuerung = NSHostingController(rootView: AnyView(ansicht))
        let klein = steuerung.sizeThatFits(in: CGSize(width: 1, height: 1))
        let gross = steuerung.sizeThatFits(in: CGSize(width: 4000, height: 4000))
        return klein == gross ? klein : CGSize(width: -1, height: -1)
    }

    @Test("E1103: Das Vorhaben-Blatt misst 980 × 820 auf jedem Eintrag der Leiste, fest in beiden Richtungen")
    func vorhabenblatt() throws {
        let planung = try Self.planung()
        let speicher = Planungsspeicher(vorschau: planung)
        let entwurf = VorhabenEntwurf(planung.eintraege[0])
        for reiter in Vorhabenreiter.allCases {
            speicher.vorhabenReiter = reiter
            let groesse = Self.groesse(VorhabenDialog(start: entwurf).environment(speicher))
            #expect(abs(groesse.width - 980) < 0.5 && abs(groesse.height - 820) < 0.5,
                    "\(reiter.titel): \(Int(groesse.width)) × \(Int(groesse.height))")
        }
        speicher.vorhabenReiter = .grundlegendes
    }

    @Test("E1108: Das Blatt „Material von 3ducation.org“ (die Liste) misst 900 × 740, fest in beiden Richtungen")
    func materialblatt() throws {
        let planung = try Self.planung()
        let speicher = Planungsspeicher(vorschau: planung)
        let entwurf = VorhabenEntwurf(planung.eintraege[0])
        // Ohne Fenster läuft kein `.task`: Das Blatt steht im Zustand „lädt“, dem breiten Bogen der Liste.
        let groesse = Self.groesse(MaterialDialog(entwurf: .constant(entwurf), vorgabe: .laedt).environment(speicher))
        #expect(abs(groesse.width - 900) < 0.5 && abs(groesse.height - 740) < 0.5,
                "\(Int(groesse.width)) × \(Int(groesse.height))")
        // Drei Spalten (E654 a, E1108): das Raster mit genau drei biegsamen Spalten.
        let datei = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Dialoge/MaterialDialog.swift")
        let text = try String(contentsOf: datei, encoding: .utf8)
        #expect(text.components(separatedBy: "GridItem(.flexible()").count - 1 == 3, "drei Spalten im Raster der Kacheln")
    }

    @Test("E1121: Die Einstellungen messen 780 × 640")
    func einstellungen() throws {
        let speicher = Planungsspeicher(vorschau: try Self.planung())
        for bereich in Einstellungsbereich.allCases {
            let groesse = Self.groesse(EinstellungenDialog(bereich: bereich).environment(speicher))
            #expect(abs(groesse.width - 780) < 0.5 && abs(groesse.height - 640) < 0.5,
                    "\(bereich.titel): \(Int(groesse.width)) × \(Int(groesse.height))")
        }
    }

    @Test("E1154, E1156: Die Verschlüsselung misst 744 × 640 — hoch wie die Einstellungen, fest in beiden Richtungen")
    func verschluesselung() throws {
        let speicher = Planungsspeicher(vorschau: try Self.planung())
        let groesse = Self.groesse(VerschluesselungDialog().environment(speicher))
        #expect(abs(groesse.width - 744) < 0.5 && abs(groesse.height - 640) < 0.5,
                "\(Int(groesse.width)) × \(Int(groesse.height))")
    }

    @Test("E1151–E1153, E1156: Prüfungen, Ferien, Heute und der Import-Bogen am Blatt „Lernende“ sind 744 breit, höchstens 700 hoch (Import-Bogen 640)")
    func breiteBlaetter() throws {
        let speicher = Planungsspeicher(vorschau: try Self.planung())
        let importbogen = ImportBogen(quelle: Importquelle(name: "schule.csv", daten: ImportLastPruefungen.schulliste(konten: 8)),
                                      gruppen: [], vorwahl: nil,
                                      vorschau: { _, _ in Importbilanz() }, importieren: { _, _, _ in Importbilanz() },
                                      archivieren: { _ in }, herausnehmen: { _ in }, personenname: { $0 })
        let blaetter: [(String, AnyView, CGFloat)] = [("Prüfungen", AnyView(PruefungsDialog().environment(speicher)), 700),
                                                      ("Ferien", AnyView(FerienDialog().environment(speicher)), 700),
                                                      ("Heute", AnyView(HeuteDialog().environment(speicher)), 700),
                                                      ("Import-Bogen", AnyView(importbogen.environment(speicher)), 640)]
        for (name, blatt, hoechstens) in blaetter {
            // Nur die Breite ist fest; die Höhe richtet sich bis zur bestellten nach dem Inhalt (R-BG8bn-07, R-BG8c-04).
            let gross = NSHostingController(rootView: blatt).sizeThatFits(in: CGSize(width: 4000, height: 4000))
            #expect(abs(gross.width - 744) < 0.5 && gross.height <= hoechstens + 0.5,
                    "\(name): \(Int(gross.width)) × \(Int(gross.height)), soll 744 × höchstens \(Int(hoechstens))")
        }
    }

    @Test("E1156: Zeilen mit festen Spalten passen in den Kasten (684 pt) — Sperr- und Ferienzeile gemessen; Papierkorb; Dauer-Spalte")
    func zeilenImKasten() throws {
        // Ohne diese Prüfung bliebe `breiteBlaetter` auch mit überbreiten Zeilen grün: Das Blatt erzwingt seine Breite
        // selbst (R-BG8c-02).
        #expect(Formblatt.breite == 744 && Formblatt.zeile == 684)
        #expect(Sperrspalten.zeile <= Formblatt.zeile, "Sperrzeile (Summe) \(Sperrspalten.zeile) pt")
        #expect(Ferienspalten.zeile <= Formblatt.zeile, "Ferienzeile (Summe) \(Ferienspalten.zeile) pt")
        // Die Zeilen selbst gemessen, nicht nur die Summe ihrer Konstanten (R-BG8cn-01): Jedes Glied hat eine feste
        // Breite, der Spacer keine Mindestbreite — bei einem Vorschlag von 0 pt ist die Antwort die Zeile.
        let planung = try Self.planung()
        let speicher = Planungsspeicher(vorschau: planung)
        let von = try #require(Tag(iso: "2026-09-21")), bis = try #require(Tag(iso: "2026-09-25"))
        let sperrzeile = NSHostingController(rootView: Sperrzeilenhuelle(
            zeitraum: Sperrzeitraum(id: "s", name: "Projektwoche", von: von, bis: bis)).environment(speicher))
            .sizeThatFits(in: CGSize(width: 0, height: 400)).width
        let ferienzeile = NSHostingController(rootView: Ferienzeilenhuelle(
            zeitraum: Ferienzeitraum(id: "f", name: "Herbstferien", von: von, bis: bis), planung: planung).environment(speicher))
            .sizeThatFits(in: CGSize(width: 0, height: 400)).width
        #expect(abs(sperrzeile - Sperrspalten.zeile) < 0.5 && sperrzeile <= Formblatt.zeile + 0.5,
                "Sperrzeile gemessen \(sperrzeile) pt, Summe \(Sperrspalten.zeile), Platz \(Formblatt.zeile)")
        #expect(abs(ferienzeile - Ferienspalten.zeile) < 0.5 && ferienzeile <= Formblatt.zeile + 0.5,
                "Ferienzeile gemessen \(ferienzeile) pt, Summe \(Ferienspalten.zeile), Platz \(Formblatt.zeile)")
        // Der Papierkorb braucht nicht mehr, als beide Zeilen ihm geben — gemessen am Baustein beider Zeilen (R-BG8cn-04,
        // R-BG8cn2-01).
        let knopf = NSHostingController(rootView: Papierkorbknopf(hilfe: "", kennzeichnung: "") {})
            .sizeThatFits(in: CGSize(width: 400, height: 400)).width
        #expect(knopf <= min(Ferienspalten.knopf, Sperrspalten.papierkorb) + 0.5,
                "Papierkorb \(knopf) pt, Ferien \(Ferienspalten.knopf), Sperren \(Sperrspalten.papierkorb)")
        // Die Dauer-Spalte, gemessen an ihrer View (R-BG8cn2-01): jede Dauer bis 999 Tage in natürlicher Breite einzeilig;
        // vertippte Spannen bis „888888 Tage“ verkleinert (R-BG8cn2-02) — gemessen in der Schrift des kleinsten Maßstabs,
        // weil kleiner gesetzte Schrift weiter läuft, als die Rechnung annimmt (R-BG8cn3-02, BG8cn4-01); „Ende vor Beginn“
        // ohne Zeilengrenze nicht höher als in der Spalte mit ihrer Grenze (R-BG8c-01).
        let messer = NSHostingController(rootView: AnyView(EmptyView()))
        func groesse(_ ansicht: some View) -> CGSize {
            messer.rootView = AnyView(ansicht)
            return messer.sizeThatFits(in: CGSize(width: 400, height: 400))
        }
        let breiteste = (1...999).map { ($0, groesse(Sperrdauer(ungueltig: false, tage: $0).fixedSize()).width) }
            .max { $0.1 < $1.1 }
        let (tage, breite) = try #require(breiteste)
        #expect(breite <= Sperrspalten.dauer + 0.5,
                "„\(Sperrdauer.text(tage: tage))“ \(breite) pt in \(Sperrspalten.dauer)")
        // Die Schrift der View misst wie die Systemschrift in `schriftgroesse` — änderte sich die eine ohne die andere,
        // mäße die Zeile darunter an der falschen Größe (R-BH3N-05).
        let inSchrift = groesse(Text(Sperrdauer.text(tage: 888_888)).font(Sperrdauer.schrift).fixedSize()).width
        let inGroesse = groesse(Text(Sperrdauer.text(tage: 888_888))
            .font(.system(size: Sperrdauer.schriftgroesse)).fixedSize()).width
        #expect(abs(inSchrift - inGroesse) <= 0.5,
                "„888888 Tage“ in `Sperrdauer.schrift` \(inSchrift) pt, in \(Sperrdauer.schriftgroesse) pt \(inGroesse) pt")
        let klein = Sperrdauer.schriftgroesse * Sperrdauer.kleinsterMassstab
        let lang = groesse(Text(Sperrdauer.text(tage: 888_888)).font(.system(size: klein)).fixedSize()).width
        #expect(lang <= Sperrspalten.dauer,
                "„888888 Tage“ in \(klein) pt: \(lang) pt in \(Sperrspalten.dauer)")
        // Dass die View wirklich verkleinert (R-BG8cn3-01): In der Spalte wird die lange Dauer niedriger als eine kurze —
        // ohne `minimumScaleFactor` bliebe sie gleich hoch und würde abgeschnitten.
        let kurzInSpalte = groesse(Sperrdauer(ungueltig: false, tage: 5).frame(width: Sperrspalten.dauer)).height
        let langInSpalte = groesse(Sperrdauer(ungueltig: false, tage: 888_888).frame(width: Sperrspalten.dauer)).height
        #expect(langInSpalte < kurzInSpalte - 1,
                "in der Spalte: „5 Tage“ \(kurzInSpalte) pt, „888888 Tage“ \(langInSpalte) pt hoch")
        let inSpalte = groesse(Sperrdauer(ungueltig: true, tage: 0)
            .frame(width: Sperrspalten.dauer)).height
        let ohneGrenze = groesse(Sperrdauer(ungueltig: true, tage: 0, warnzeilen: nil)
            .frame(width: Sperrspalten.dauer)).height
        #expect(ohneGrenze <= inSpalte + 0.5,
                "„\(Sperrspalten.warnung)“ braucht \(ohneGrenze) pt, die Spalte zeigt \(inSpalte) pt")
    }

    /// Die Zeilen, die der Koordinator gerade führt — privat, über `Mirror` gelesen (R95-03).
    private func leistenzeilen(_ k: Seitenleistenkoordinator) -> [Seitenleistenzeile] {
        Mirror(reflecting: k).children.first { $0.label == "zeilen" }?.value as? [Seitenleistenzeile] ?? []
    }

    /// Die Hauptschlange bis hinter alles leeren, was schon in ihr steht — der Reihe nach, ohne Uhr.
    private func hauptschlangeLeeren() async {
        await withCheckedContinuation { (fertig: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { fertig.resume() } }
    }

    private func leistenkoordinator() -> (Seitenleistenkoordinator, NSTableView) {
        let k = Seitenleistenkoordinator()
        let tabelle = NSTableView()
        tabelle.addTableColumn(NSTableColumn(identifier: Seitenleistenkoordinator.spalte))
        tabelle.dataSource = k
        tabelle.delegate = k
        k.tabelle = tabelle
        return (k, tabelle)
    }

    @Test("R95-03: Ein im Rückruf vorgemerkter älterer Stand überschreibt einen danach sofort angewendeten neueren nicht")
    func neuererStandGewinnt() async {
        let (k, tabelle) = leistenkoordinator()
        let alt = [Seitenleistenzeile(name: "Termin", symbol: "calendar", plakette: nil),
                   Seitenleistenzeile(name: "Hausaufgabe", symbol: "backpack", plakette: nil)]
        let neu = [Seitenleistenzeile(name: "Termin", symbol: "calendar", plakette: "1"), alt[1]]
        k.vormerken(zeilen: alt, gewaehlt: 0)
        #expect(tabelle.numberOfRows == 2 && tabelle.selectedRow == 0)
        // Wahl wie von Hand: Im Rückruf liefert SwiftUI den Stand vor dem Übernehmen des Felds (alte Plakette).
        k.gewaehlt = { stelle in k.vormerken(zeilen: alt, gewaehlt: stelle) }
        tabelle.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        // Nach dem Rückruf, noch vor dem vorgemerkten Block: der neuere Stand (das Feld hat übernommen).
        k.vormerken(zeilen: neu, gewaehlt: 1)
        #expect(leistenzeilen(k) == neu, "sofort angewendet")
        await hauptschlangeLeeren()
        #expect(leistenzeilen(k) == neu,
                "nach dem vorgemerkten Block: Plakette „\(leistenzeilen(k).first?.plakette ?? "—")“ statt „1“")
        #expect(tabelle.selectedRow == 1)
    }

    @Test("R95-03: Mehrere Vormerkungen im Rückruf, danach ein Sofortstand — der Sofortstand bleibt")
    func mehrereVormerkungenDannSofort() async {
        let (k, tabelle) = leistenkoordinator()
        let z = { (plakette: String?) in [Seitenleistenzeile(name: "Termin", symbol: "calendar", plakette: plakette),
                                          Seitenleistenzeile(name: "Material", symbol: "paperclip", plakette: nil)] }
        k.vormerken(zeilen: z(nil), gewaehlt: 0)
        k.gewaehlt = { stelle in
            k.vormerken(zeilen: z("a"), gewaehlt: stelle)
            k.vormerken(zeilen: z("b"), gewaehlt: stelle)
        }
        tabelle.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        k.vormerken(zeilen: z("c"), gewaehlt: 1)
        await hauptschlangeLeeren()
        #expect(leistenzeilen(k) == z("c"), "Plakette „\(leistenzeilen(k).first?.plakette ?? "—")“ statt „c“")
        #expect(tabelle.selectedRow == 1)
    }

    @Test("E1136: ⌘K „Lernende, Klassen/Kurse und Fächer“ misst 980 × 820 wie das Vorhaben-Blatt")
    func klassenblatt() throws {
        let speicher = Planungsspeicher(vorschau: try Self.planung())
        for bereich in Klassenbereich.allCases {
            let groesse = Self.groesse(KlassenDialog(bereich: bereich).environment(speicher))
            #expect(abs(groesse.width - 980) < 0.5 && abs(groesse.height - 820) < 0.5,
                    "\(bereich.titel): \(Int(groesse.width)) × \(Int(groesse.height))")
        }
    }

    @Test("E1120: Die Leiste ist eine Tabelle mit fester Zeilenhöhe 32 pt — keine automatischen Höhen, keine Liste")
    func leisteFest() throws {
        // Am Quelltext, weil das Wobbeln nur im Fenster entsteht (E1120): Mit automatischen Zeilenhöhen ist
        // `rowHeight` nur eine Schätzung, und jede Zeile springt nach einem Klick zwischen Schätzung und Maß. Die Ruhe am
        // Fenster misst die Dialogprobe („Leiste ruhig“).
        let datei = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Gestaltung/Seitenleiste.swift")
        let text = try String(contentsOf: datei, encoding: .utf8)
        #expect(text.contains("tabelle.usesAutomaticRowHeights = false"))
        #expect(text.contains("tabelle.rowHeight = Seitenleistenvorlage.zeilenhoehe"))
        #expect(text.contains("static let zeilenhoehe: CGFloat = 32"))
        #expect(text.contains("tabelle.rowSizeStyle = .custom"))
        #expect(text.contains("NSUserInterfaceItemIdentifier(\"Seitenleiste\")"), "die Kennung, an der die Dialogprobe sie findet")
        #expect(!text.contains("List("), "keine SwiftUI-Liste: deren Zellen messen eine andere Höhe als die Tabelle schätzt")
        #expect(text.contains("tabelle.intercellSpacing = .zero"), "kein Zwischenraum: jede Zeile genau `rowHeight`")
        #expect(!text.contains("heightOfRow"), "kein Rückruf für die Höhe einer Zeile — der brächte das Messen zurück")
    }

    @Test("R-BG5c-04: Jeder Eintrag zeigt seine eigene Seite — ⌘K, Einstellungen und Vorhaben-Blatt")
    func seitenZugeordnet() throws {
        // Am Quelltext: Die Texte der Seiten sind am Fenster im Baum der Bedienungshilfen des eigenen Prozesses nicht zu
        // lesen; die Dialogprobe sieht nur die Felder „Klasse/Kurs“. Eine vertauschte Seite bliebe dort grün.
        let ordner = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Dialoge")
        let erwartet: [(String, [String])] = [
            ("KlassenDialog.swift", ["case .lernende: Seitenform { lernende }",
                                     "case .klassen: Seitenform { klassenUndKurse(planung) }",
                                     "case .fachfarben: Seitenform { fachfarben(planung) }"]),
            ("WeitereDialoge.swift", ["case .zeitraum: Seitenform { zeitraum }",
                                      "case .sicherungskopie: Seitenform { sicherungskopie }",
                                      "case .verschluesselung: Seitenform { verschluesselung }",
                                      "case .updates: Seitenform { updates }",
                                      "case .materialien: Seitenform { materialien }",
                                      "case .stand: Seitenform { if let planung { kennzahlen(planung) } }"]),
            ("VorhabenDialog.swift", ["case .grundlegendes: blattform { grundlegendes(stand) }",
                                      "case .kommentar: blattform { kommentarbereich }",
                                      "case .pruefung: blattform { pruefungsbereich }",
                                      "case .termin: blattform { terminbereich }",
                                      "case .hausaufgabe: blattform { hausaufgabenbereich }",
                                      "case .material: blattform { materialbereich }"]),
        ]
        for (datei, zeilen) in erwartet {
            let text = try String(contentsOf: ordner.appending(path: datei), encoding: .utf8)
            for zeile in zeilen {
                #expect(text.components(separatedBy: zeile).count - 1 == 1, Comment(rawValue: "\(datei): \(zeile)"))
            }
        }
    }

    @Test("E1150: die bestellte Höhe, solange der Platz reicht; sonst 40 pt über dem Dock, nie unter 480")
    func blatthoeheBegrenzt() {
        #expect(Seitenleistenmass.begrenzt(820, hoechstens: 2000) == 820)
        #expect(Seitenleistenmass.begrenzt(820, hoechstens: 660) == 660)
        #expect(Seitenleistenmass.begrenzt(640, hoechstens: 660) == 640)
        #expect(Seitenleistenmass.begrenzt(820, hoechstens: 300) == 480)
        // Fenster füllt die sichtbare Fläche (0 … 776, Kopf 52; etwa 1440 × 900 mit großem Dock): Das Blatt liegt am
        // Fensterkopf an und endet 40 pt über dem Dock — 724 − 40.
        #expect(Seitenleistenmass.hoechstens(kopfUnten: 724, fensterOben: 776, fensterUnten: 0, sichtbarUnten: 0) == 684)
        // Großer Bildschirm, Fenster oben (Inhalt 900): weit mehr als 820 frei — es bleibt bei 820.
        #expect(Seitenleistenmass.hoechstens(kopfUnten: 1363, fensterOben: 1415, fensterUnten: 463, sichtbarUnten: 0)
                == 1323)
        // Fenster ragt 100 pt unter das Dock: Das Blatt steht mittig im Fenster und endet bei (−100 + 776 − h) / 2 —
        // 40 pt über dem Dock bei h = 596.
        #expect(Seitenleistenmass.hoechstens(kopfUnten: 724, fensterOben: 776, fensterUnten: -100, sichtbarUnten: 0) == 596)
        // Laptop mit Dock unten, Fenster maximiert (sichtbar 0 … 875, R-BG8b-04): 823 − 40 — das Blatt wird 783 hoch.
        #expect(Seitenleistenmass.begrenzt(820, hoechstens: Seitenleistenmass.hoechstens(
            kopfUnten: 823, fensterOben: 875, fensterUnten: 0, sichtbarUnten: 0)) == 783)
    }

    @Test("Was nur dem Messen der Vorarbeit diente, steht nicht in den Quellen")
    func ohneMessgeruest() throws {
        let ordner = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung")
        let aufzaehlung = try #require(FileManager.default.enumerator(at: ordner, includingPropertiesForKeys: nil))
        var funde: [String] = []
        for case let datei as URL in aufzaehlung where datei.pathExtension == "swift" {
            // Die gesperrten Dateien werden hier nicht gelesen — sie tragen keine Oberfläche.
            guard !["Tresor.swift", "Uebergang.swift", "Planungsspeicher+Verschluesselung.swift"]
                .contains(datei.lastPathComponent) else { continue }
            let text = try String(contentsOf: datei, encoding: .utf8)
            for marke in ["PROTOTYP", "Messanzeige", "Blattsonde", "Leistenprotokoll", "Klassentest", "Einstellungstest"]
            where text.contains(marke) {
                funde.append("\(datei.lastPathComponent): \(marke)")
            }
        }
        #expect(funde.isEmpty, "\(funde)")
    }
}

/// Hüllen mit eigenem Fokus: Die Zeilen erwarten eine Bindung (R-BG8cn-01).
private struct Sperrzeilenhuelle: View {
    let zeitraum: Sperrzeitraum
    @FocusState private var fokus: String?
    var body: some View { Sperrposten(zeitraum: zeitraum, fokus: $fokus) }
}

private struct Ferienzeilenhuelle: View {
    let zeitraum: Ferienzeitraum
    let planung: Planung
    @FocusState private var fokus: String?
    var body: some View { Ferienposten(zeitraum: zeitraum, planung: planung, fokus: $fokus) }
}
