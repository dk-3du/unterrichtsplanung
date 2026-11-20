// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Technische Grenzen mit Warnung (v90, BB4, E978) ──
// Es bleiben die Grenzen, die die Dateien tragen: 2 000 Personen je Schuljahr (archivierte eingeschlossen), 16 MB
// Lernendendaten, 128 MB Archiv, 1 MB Sitzpläne. Ab 90 % sagt eine Warnung es vorher, beim Erreichen lehnt die App mit
// Grund ab — nie still. Die Wortlaute wie freigegeben (BB4); den Weg der Lernendendaten und des Archivs prüft
// `JahreswechselPruefungen.warnungenAnDerSchwelle` am Speicher.

@Suite("v90 BB4: technische Grenzen — Warnung ab 90 %, Ablehnung mit Grund (E978)")
@MainActor
struct TechnischeGrenzenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand, "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private static let s = "2026-10-31T08:00:00.000Z"
    private static let jetzt = "2026-10-31T09:00:00.000Z"
    private static let mb = 1_048_576

    private static func bestand(personen: Int) -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = (0..<personen).map {
            Lernender(id: "p-\($0)", vorname: "V\($0)", nachname: "N\($0)", angelegt: s, geaendert: s, archiviert: "")
        }
        b.lerngruppen = [Lerngruppe(id: "g", name: "6a", art: .klasse, mitglieder: [], zeilen: [], skalen: [:],
                                    halbjahreswechsel: "", geaendert: s, archiviert: "")]
        return b
    }

    @Test("Personen je Schuljahr: ab 1 800 die Warnung, darunter keine")
    func schuljahrswarnung() {
        let t = Lernendenbestand.tausender
        #expect(Lernendenblatt.schuljahrswarnung(1_799) == nil)
        // Kurz, damit sie mit der Meldung in die zwei Zeilen eines Blatts passt (E984; der Hinweis auf archivierte entfällt).
        #expect(Lernendenblatt.schuljahrswarnung(1_800)
                == "Die Lernendenverwaltung umfasst jetzt \(t(1_800)) Personen — höchstens \(t(2_000)) je Schuljahr.")
        #expect(Lernendenblatt.schuljahrswarnung(2_000)?.contains("jetzt \(t(2_000)) Personen") == true)
    }

    @Test("Nach dem Eintragen ab 1 800: die Warnung allein, vor „mehrfach“, und nicht doppelt, wenn die Grenze schon genannt ist")
    func eintragsmeldung() {
        let b = Self.bestand(personen: 1_799)
        let eins = b.mitPersonen([Namenszeilen.Name(vorname: "Neu", nachname: "Eins")], inGruppe: "g", jetzt: Self.jetzt)
        #expect(LernendenDialog.eintragsmeldung(eins) != nil
                && LernendenDialog.eintragsmeldung(eins) == Lernendenblatt.schuljahrswarnung(1_800), "die Warnung allein")
        let klein = Self.bestand(personen: 10)
            .mitPersonen([Namenszeilen.Name(vorname: "Neu", nachname: "Eins")], inGruppe: "g", jetzt: Self.jetzt)
        #expect(LernendenDialog.eintragsmeldung(klein) == nil, "darunter nichts")
        let drei = Self.bestand(personen: Kennwerte.maxLernende - 1)
            .mitPersonen((1...3).map { Namenszeilen.Name(vorname: "Neu\($0)", nachname: "N") }, inGruppe: "g", jetzt: Self.jetzt)
        #expect(drei.ueberGrenze == 2 && LernendenDialog.eintragsmeldung(drei)?.contains("umfasst jetzt") == false,
                "die Grenze ist schon genannt")
        var c = b
        for i in 0..<2 {
            c.lernende.append(Lernender(id: "m-\(i)", vorname: "Max", nachname: "Mai", angelegt: Self.s, geaendert: Self.s,
                                        archiviert: ""))
        }
        let mehrfach = c.mitPersonen([Namenszeilen.Name(vorname: "Max", nachname: "Mai")], inGruppe: "g", jetzt: Self.jetzt)
        // Die Warnung vorn (E983): Die Meldungszeile eines Blatts kürzt nach zwei Zeilen — dahinter fiele sie weg; kurz
        // genug, dass auch „nicht eingetragen“ noch hineinpasst (E984).
        #expect(LernendenDialog.eintragsmeldung(mehrfach) == (Lernendenblatt.schuljahrswarnung(1_801) ?? "—")
                + " 0 eingetragen — 1 Name mehrfach vorhanden, daher nicht eingetragen.")
        for (i, (v, n)) in [("Eva", "Ek"), ("Ida", "Ilg")].enumerated() {
            for j in 0..<2 {
                c.lernende.append(Lernender(id: "m-\(i)-\(j)", vorname: v, nachname: n, angelegt: Self.s, geaendert: Self.s,
                                            archiviert: ""))
            }
        }
        let namen = [("Max", "Mai"), ("Eva", "Ek"), ("Ida", "Ilg")].map { Namenszeilen.Name(vorname: $0.0, nachname: $0.1) }
        let dreifach = c.mitPersonen(namen, inGruppe: "g", jetzt: Self.jetzt)
        #expect(dreifach.gleichnamig == 3, "Vorbedingung")
        #expect(LernendenDialog.eintragsmeldung(dreifach) == (Lernendenblatt.schuljahrswarnung(1_805) ?? "—")
                + " 0 eingetragen — 3 Namen mehrfach vorhanden, daher nicht eingetragen.")
    }

    @Test("Nach dem Import ab 1 800: die Warnung steht vor der Meldung des Imports und macht sie zur Warnung (E983)")
    func importmeldung() throws {
        // Z-BB8-W2-02: Fiel die Bindung aus, sagt es die Importmeldung selbst — als Warnung, mit und ohne Grenze.
        let ungebunden = Lernendenblatt.importmeldung("3 neu.", personen: 10, ohneBindung: true)
        #expect(Lernendenblatt.ohneBindungSatz == "Die neuen Lerngruppen sind nicht an ihre Zeilen gebunden — die Planung "
                    + "ließ sich nicht sichern.")
        // Vor dem Ergebnis — das zeigt der Importbogen selbst; gekürzt wird so nur dieses (NF-06).
        #expect(ungebunden.text == Lernendenblatt.ohneBindungSatz + " 3 neu." && ungebunden.art == .warnung)
        let vollUngebunden = Lernendenblatt.importmeldung("3 neu.", personen: 1_801, ohneBindung: true)
        #expect(vollUngebunden.text.hasPrefix("Die Lernendenverwaltung umfasst jetzt ")
                    && vollUngebunden.text.hasSuffix(Lernendenblatt.ohneBindungSatz + " 3 neu.") && vollUngebunden.art == .warnung)
        // Die Verdrahtung im Blatt: nur, wenn die Bindung ausfiel und neue Lerngruppen entstanden (NF-07 b, Quelltext).
        let blatt = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Oberflaeche/Dialoge/LernendenDialog.swift")
        #expect(try String(contentsOf: blatt, encoding: .utf8).contains("ohneBindung: grund != nil && !bilanz.neueGruppen.isEmpty"))
        let ohne = Lernendenblatt.importmeldung("3 neu.", personen: 1_799)
        #expect(ohne.text == "3 neu." && ohne.art == .hinweis)
        let mit = Lernendenblatt.importmeldung("3 neu.", personen: 1_800)
        #expect(mit.text == (Lernendenblatt.schuljahrswarnung(1_800) ?? "—") + " 3 neu." && mit.art == .warnung)
    }

    @Test("Lernendendaten: Warnung ab 14,4 MB, Ablehnung mit Grund — die Wortlaute")
    func lernendendaten() {
        let grenze = Lernendendienst.hoechstgroesse
        #expect(Lernendendienst.groessenwarnung(grenze / 10 * 9 - 1) == nil)
        #expect(Lernendendienst.groessenwarnung(Int(14.65 * Double(Self.mb)))
                == "Die Lernendendaten dieses Schuljahrs sind 14,6 MB groß — ab 16 MB lassen sie sich nicht mehr sichern.")
        #expect(Lernendendienst.groessengrund(Int(16.2 * Double(Self.mb)))
                == "die Lernendendaten wären mit 16,2 MB größer als die Grenze von 16 MB")
        // An den Rändern (Z-BB4-01): der Grund aufgerundet, die Warnung abgerundet.
        #expect(Lernendendienst.groessengrund(grenze + 1) == "die Lernendendaten wären mit 16,1 MB größer als die Grenze von 16 MB")
        #expect(Lernendendienst.groessenwarnung(grenze - 1)?.hasPrefix("Die Lernendendaten dieses Schuljahrs sind 15,9 MB") == true)
    }

    @Test("Archiv: Warnung ab 115 MB, Ablehnung mit Grund — die Wortlaute")
    func archiv() {
        let grenze = Lernendendienst.archivgroesse
        #expect(Lernendendienst.archivwarnung(grenze / 10 * 9 - 1) == nil)
        #expect(Lernendendienst.archivwarnung(117 * Self.mb) == "Das Archiv ist jetzt 117 MB groß — ab 128 MB nimmt es kein "
                + "weiteres Schuljahr auf; ältere Schuljahre lassen sich im Archiv löschen.")
        #expect(Lernendendienst.archivgrund(130 * Self.mb)
                == "das Archiv wäre mit 130 MB größer als die Grenze von 128 MB — ältere Schuljahre lassen sich im Archiv löschen")
        #expect(Lernendendienst.archivgrund(grenze + 1).hasPrefix("das Archiv wäre mit 129 MB größer als die Grenze von 128 MB"))
        #expect(Lernendendienst.archivwarnung(grenze - 1)?.hasPrefix("Das Archiv ist jetzt 127 MB groß") == true)
    }

    @Test("Sitzpläne: Warnung ab 0,9 MB, Ablehnung mit Grund — die Wortlaute")
    func sitzplaeneWortlaute() {
        #expect(Sitzplandienst.groessenwarnung(Sitzplandienst.hoechstgroesse / 10 * 9 - 1) == nil)
        #expect(Sitzplandienst.groessenwarnung(Int(0.935 * Double(Self.mb)))
                == "Die Sitzpläne sind zusammen 0,93 MB groß — ab 1 MB lassen sie sich nicht mehr sichern.")
        #expect(Sitzplandienst.groessengrund(Int(1.01 * Double(Self.mb)))
                == "die Sitzpläne wären mit 1,01 MB größer als die Grenze von 1 MB")
        #expect(Sitzplandienst.groessengrund(Sitzplandienst.hoechstgroesse + 1)
                == "die Sitzpläne wären mit 1,01 MB größer als die Grenze von 1 MB")
        #expect(Sitzplandienst.groessenwarnung(Sitzplandienst.hoechstgroesse - 1)?.hasPrefix("Die Sitzpläne sind zusammen 0,99 MB")
                == true)
    }

    @Test("Sitzpläne am Dienst: ab 90 % einmal je Sitzung die Warnung; über der Grenze abgelehnt mit Grund, nie still")
    func sitzplaeneAmDienst() throws {
        let ort = URL.temporaryDirectory.appending(component: "bb4-sitzplaene-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ort, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ort) }
        let dienst = Sitzplandienst(ablage: Ablage(ordner: ort))
        #expect(dienst.laden(stempel: "s") == .keine)
        var meldungen: [String] = []
        dienst.melden = { text, _ in meldungen.append(text) }
        let name = String(repeating: "x", count: Kennwerte.maxSitzplatzname)
        func plan(_ k: Int) -> Sitzplan {
            Sitzplan(klasseId: "k-\(k)", tische: (0..<45).map {
                Tisch(id: "t-" + String(format: "%06d%08d", k, $0), name: name, x: CGFloat($0 % 10) * 72,
                      y: CGFloat($0 / 10) * 72, lernender: "l-" + String(format: "%06d%08d", k, $0))
            }, lehrertisch: Sitzplanmasse.lehrertischStart, geaendert: Self.s)
        }
        // So viele Pläne, dass die Datei bei rund 95 % liegt — geschätzt aus einem und zwei Plänen.
        let einer = try Sitzplandatei.schreiben(["k-0": plan(0)]).count
        let jePlan = try Sitzplandatei.schreiben(["k-0": plan(0), "k-1": plan(1)]).count - einer
        let anzahl = (Sitzplandienst.hoechstgroesse * 95 / 100 - einer) / jePlan + 1
        // Die Warnung genau mit dem Schreiben, das die Schwelle erreicht — vorher keine (Z-BB4-04).
        var groessen: [Int] = []
        var gewarntBei: Int?
        for k in 0..<anzahl {
            #expect(dienst.setzen(plan(k), fuer: "k-\(k)") == nil, "Plan \(k)")
            groessen.append((try? Data(contentsOf: Ablage(ordner: ort).sitzplaene).count) ?? 0)
            if gewarntBei == nil, meldungen.contains(where: { $0.hasPrefix("Die Sitzpläne sind zusammen ") }) { gewarntBei = k }
        }
        #expect(gewarntBei != nil && gewarntBei == groessen.firstIndex { $0 >= Sitzplandienst.hoechstgroesse / 10 * 9 },
                "gewarnt bei \(gewarntBei.map(String.init) ?? "—"), Größen \(groessen.suffix(3))")
        #expect(meldungen.filter { $0.hasPrefix("Die Sitzpläne sind zusammen ") }.count == 1, "einmal je Sitzung: \(meldungen)")
        var grund: String?
        var k = anzahl
        while grund == nil && k < anzahl + 40 {
            grund = dienst.setzen(plan(k), fuer: "k-\(k)")
            k += 1
        }
        #expect(grund?.hasPrefix("die Sitzpläne wären mit ") == true
                && grund?.hasSuffix(" MB größer als die Grenze von 1 MB") == true, "\(grund ?? "nicht abgelehnt")")
        #expect(meldungen.contains { $0.hasPrefix("Die Sitzpläne ließen sich nicht sichern (die Sitzpläne wären mit ") },
                "nie still: \(meldungen.last ?? "")")
    }

    @Test("Sitzpläne: ein neues Schuljahr warnt neu — wie die Jahresdatei (Z-BB8-W1-B2, Z-BB4-05)")
    func sitzplaeneWarnenImNeuenSchuljahr() throws {
        let ort = URL.temporaryDirectory.appending(component: "bb8-sitzplaene-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ort, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ort) }
        let dienst = Sitzplandienst(ablage: Ablage(ordner: ort))
        #expect(dienst.laden(stempel: "s") == .keine)
        var meldungen: [String] = []
        dienst.melden = { text, _ in meldungen.append(text) }
        let name = String(repeating: "x", count: Kennwerte.maxSitzplatzname)
        func plan(_ k: Int) -> Sitzplan {
            Sitzplan(klasseId: "k-\(k)", tische: (0..<45).map {
                Tisch(id: "t-" + String(format: "%06d%08d", k, $0), name: name, x: CGFloat($0 % 10) * 72,
                      y: CGFloat($0 / 10) * 72, lernender: "l-" + String(format: "%06d%08d", k, $0))
            }, lehrertisch: Sitzplanmasse.lehrertischStart, geaendert: Self.s)
        }
        let einer = try Sitzplandatei.schreiben(["k-0": plan(0)]).count
        let jePlan = try Sitzplandatei.schreiben(["k-0": plan(0), "k-1": plan(1)]).count - einer
        let anzahl = (Sitzplandienst.hoechstgroesse * 92 / 100 - einer) / jePlan + 1
        for k in 0..<anzahl { #expect(dienst.setzen(plan(k), fuer: "k-\(k)") == nil, "Plan \(k)") }
        func warnungen() -> Int { meldungen.filter { $0.hasPrefix("Die Sitzpläne sind zusammen ") }.count }
        #expect(warnungen() == 1, "einmal in dieser Sitzung: \(meldungen)")
        #expect(dienst.setzen(plan(anzahl), fuer: "k-\(anzahl)") == nil)
        #expect(warnungen() == 1, "dasselbe Schuljahr warnt nicht noch einmal")
        dienst.nachJahreswechsel()
        #expect(dienst.setzen(plan(anzahl + 1), fuer: "k-\(anzahl + 1)") == nil)
        #expect(warnungen() == 2, "das neue Schuljahr warnt beim nächsten Schreiben neu: \(meldungen)")
        // Der Wechsel ruft es auf, gleich nach der Jahresdatei (NF-07 a, Quelltext — ein Wechsel mit 1 MB Sitzplänen wäre zu
        // schwer für die Suite).
        let wechsel = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Quellen/Unterrichtsplanung/Speicher/Planungsspeicher+Jahreswechsel.swift")
        #expect(try String(contentsOf: wechsel, encoding: .utf8)
            .contains("lernende.nachJahreswechsel(neuesJahr, groesse: jahresdatei)\n        sitzplaene.nachJahreswechsel()"))
    }

    @Test("„Lernende einlesen“ ab 1 800 Personen: die Warnung steht vor der Meldung des Einlesens (Z-BB4-07, E983)")
    func lernendeEinlesen() async throws {
        let ort = URL.temporaryDirectory.appending(component: "bb4-einlesen-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ort, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ort) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ort))
        s.planung = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                                 klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: "Ein Satz, den man behält"))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        var b = try #require(s.lernendenEntwurfBeginnen())
        b.lernende = (0..<1_800).map {
            Lernender(id: "l-\($0)", vorname: "V\($0)", nachname: "N\($0)", angelegt: Self.s, geaendert: Self.s, archiviert: "")
        }
        #expect(s.lernendenEinlesenKlartext(try Lernendendatei.schreiben(b), von: ort.appending(component: "export.json")) == nil)
        let m = try #require(s.meldungen.last)
        #expect(m.text.hasPrefix((Lernendenblatt.schuljahrswarnung(1_800) ?? "—") + " ") && m.art == .warnung, "\(m.text)")
        // Die Zahl dahinter wie in der Warnung geschrieben, nicht „1800 Personen in 1 Lerngruppen“ (Hinweis aus Z-BB4b).
        let zeile = Lernendenblatt.zaehlzeile(personen: 1_800, gruppen: b.lerngruppen.filter { $0.archiviert.isEmpty }.count)
        #expect(m.text.contains(" " + zeile + " eingelesen — ")
                && m.text.contains(" \(Lernendenbestand.tausender(1_800)) Personen in "), "\(m.text)")
    }
}
