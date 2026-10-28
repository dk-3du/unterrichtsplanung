// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Unterrichtsplanung

// ── Der Import aus IServ: Last im Bogen und offenes Anführungszeichen (v87, AY2) ──
// R86-04: Der Bogen zerlegte eine Datei bei jedem Zugriff auf seine Tabelle neu — je Aufbau Dutzende Male, bei einer
// schulweiten Liste rund eine Sekunde. F-03, E871 a: Ein Anführungszeichen, das bis zum Ende der Datei offen bleibt,
// nahm den Rest still in ein Feld; jetzt nennt die Zerlegung die Zeile, in der es öffnet, und der Bogen importiert nichts
// (E885). E892 a (AY2a): ebenso ein Feld, das erst in einer späteren Zeile schließt.

@Suite("Import: Last im Bogen und offenes Anführungszeichen (R86-04, F-03, E871 a)")
@MainActor
struct ImportLastPruefungen {

    /// Eine Schulliste wie aus der Benutzerverwaltung: Kopfzeile mit IServ-Namen, `konten` Zeilen, 12 Spalten.
    nonisolated static func schulliste(konten: Int = 1200) -> Data {
        var text = "Account;Vorname;Nachname;E-Mail;Klasse/Information;Gruppen;Status;Erstellt;Letzter Login;Quota;Rolle;Notiz\r\n"
        for i in 0..<konten {
            text += "konto.\(i);Vorname\(i);Nachname\(i);konto.\(i)@schule.example;\(5 + i % 8)\(["a", "b", "c"][i % 3]);"
                + "Schueler, Klasse \(5 + i % 8);aktiv;2025-08-01;2026-10-20;500 MB;Schüler;\r\n"
        }
        return Data(text.utf8)
    }

    @Test("Zerlegung: Ein offenes Anführungszeichen nennt die Zeile, in der es öffnet, und nimmt den Rest; geschlossene nennen nichts")
    func offenesAnfuehrungszeichen() {
        let offen = IServImport.zerlegung("Nachname;Vorname;Klasse\nAbel;Anna;7b\n\"Hasan;Gül;7b\nBauer;Ben;7b\n",
                                          trenner: .semikolon)
        #expect(offen.offenesAnfuehrungszeichen == 3, "Zeile 3, gezählt mit der Kopfzeile")
        #expect(offen.zeilen.count == 3 && offen.zeilen[2] == ["Hasan;Gül;7b\nBauer;Ben;7b\n"], "der Rest in einem Feld")
        #expect(IServImport.zerlegung("\"Abel; Anna\";7b\n\"x\"", trenner: .semikolon).offenesAnfuehrungszeichen == nil)
        #expect(IServImport.zerlegung("\"offen", trenner: .semikolon).offenesAnfuehrungszeichen == 1)
        #expect(IServImport.zerlegung("", trenner: .semikolon) == .init(zeilen: [], offenesAnfuehrungszeichen: nil))
        #expect(IServImport.zerlegen("\"offen", trenner: .semikolon) == [["offen"]], "die Zeilen allein wie bisher")
    }

    @Test("E892 a: Ein Feld über ein Zeilenende nennt die Zeile, in der es öffnet — auch mit CRLF und BOM über den Bogen; ein bis zum Ende offenes Anführungszeichen geht vor")
    func feldUeberZeilenende() {
        // Wie in AY2 nachgestellt: In Annas Zeile beginnt die E-Mail mit „"“, das erst am „"Administrator"“ der nächsten
        // Zeile schließt — gelesen würden Anna und Cem, Ben fehlte still.
        let text = "Nachname;Vorname;Klasse;E-Mail\nAbel;Anna;7b;\"anna@schule.example\nBauer;Ben;7b;\"\"Administrator\"\n"
            + "Çelik;Cem;7b;cem@schule.example\n"
        let z = IServImport.zerlegung(text, trenner: .semikolon)
        #expect(z.feldUeberZeilenende == 2 && z.offenesAnfuehrungszeichen == nil, Comment(rawValue: "\(z)"))
        let crlf = IServImport.zerlegung(text.replacingOccurrences(of: "\n", with: "\r\n"), trenner: .semikolon)
        #expect(crlf.feldUeberZeilenende == 2, "auch mit CRLF")
        let auswertung = Importvorrat().auswertung(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8), kodierung: nil, trenner: nil)
        #expect(auswertung.zerlegung.feldUeberZeilenende == 2, "über den Bogen, mit BOM")
        #expect(IServImport.zerlegung("Nachname;Vorname\n\"Abel\";\"Anna\"\n", trenner: .semikolon).feldUeberZeilenende == nil,
                "geschlossen in derselben Zeile")
        let sperre = ImportBogen.sperrtexte(z)
        #expect(sperre?.fuss == ImportBogen.ueberZeilenendeTexte(2).fuss && sperre?.zeile == ImportBogen.ueberZeilenendeTexte(2).zeile
                && sperre?.hilfe == ImportBogen.ueberZeilenendeTexte(2).hilfe, "der Bogen sperrt mit den Wortlauten nach E892")
        let offen = IServImport.zerlegung("Nachname;Vorname;Klasse\nAbel;Anna;7b\n\"Hasan;Gül;7b\nBauer;Ben;7b\n", trenner: .semikolon)
        #expect(ImportBogen.sperrtexte(offen)?.fuss == ImportBogen.offenTexte(3).fuss, "bis zum Ende offen geht vor")
        #expect(ImportBogen.sperrtexte(IServImport.zerlegung("a;b\nc;d\n", trenner: .semikolon)) == nil)
        // Beide Nummern sind Zeilen der Datei, nicht Datensätze (Z-AY2a-01): Nach einem Feld über ein Zeilenende steht das
        // bis zum Ende offene Anführungszeichen in Zeile 4, obwohl es der dritte Datensatz ist.
        let beide = IServImport.zerlegung("Nachname;Vorname\nA;\"x\nB;y\"\nC;\"z\nD;w\n", trenner: .semikolon)
        #expect(beide.feldUeberZeilenende == 2 && beide.offenesAnfuehrungszeichen == 4, Comment(rawValue: "\(beide)"))
    }

    @Test("Wortlaute bei einem Feld über ein Zeilenende — wie freigegeben (E892 a)")
    func ueberZeilenendeWortlaute() {
        let t = ImportBogen.ueberZeilenendeTexte(2)
        #expect(t.fuss == "Zeile 2 öffnet ein Anführungszeichen, das erst in einer späteren Zeile schließt — die Zeilen "
                + "dazwischen stünden in einem einzigen Feld. Bitte die Datei prüfen; so wird nichts importiert.")
        #expect(t.zeile == "Anführungszeichen über das Zeilenende in Zeile 2 — nichts wird importiert.")
        #expect(t.hilfe == "Die Datei öffnet in Zeile 2 ein Anführungszeichen, das erst in einer späteren Zeile schließt.")
    }

    @Test("Trenner erkennen: je Trenner höchstens zwanzig Datensätze, keine ganze Zerlegung (R86-04)")
    func trennerBegrenzt() {
        let text = String(decoding: Self.schulliste(konten: 200), as: UTF8.self)
        let zaehlwerk = IServImport.Zaehlwerk()
        let trenner = IServImport.$zaehlwerk.withValue(zaehlwerk) { IServImport.trennerErkennen(text) }
        #expect(trenner == .semikolon)
        #expect(zaehlwerk.ganzeZerlegungen == 0 && zaehlwerk.begrenzteZerlegungen == 3,
                "ganz \(zaehlwerk.ganzeZerlegungen), begrenzt \(zaehlwerk.begrenzteZerlegungen)")
    }

    @Test("Der Bogen zerlegt eine Schulliste beim Aufbau einmal ganz — nicht je Zugriff auf seine Tabelle (R86-04)")
    func bogenZerlegtEinmal() {
        let bogen = ImportBogen(quelle: Importquelle(name: "schule.csv", daten: Self.schulliste()), gruppen: [], vorwahl: nil,
                                vorschau: { _, _ in Importbilanz() }, importieren: { _, _, _ in Importbilanz() },
                                archivieren: { _ in }, herausnehmen: { _ in }, personenname: { $0 })
        let zaehlwerk = IServImport.Zaehlwerk()
        IServImport.$zaehlwerk.withValue(zaehlwerk) {
            let ansicht = NSHostingView(rootView: bogen.frame(width: 820, height: 640))
            let fenster = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 820, height: 640), styleMask: [.borderless],
                                   backing: .buffered, defer: true)
            fenster.isReleasedWhenClosed = false
            fenster.contentView = ansicht
            ansicht.layoutSubtreeIfNeeded()
            fenster.contentView = nil
        }
        // Eine Auswertung: einmal ganz, dazu die Trennererkennung mit je einem begrenzten Anfang je Trenner (Z-AY2-04).
        #expect(zaehlwerk.ganzeZerlegungen == 1 && zaehlwerk.begrenzteZerlegungen == 3,
                "ganz \(zaehlwerk.ganzeZerlegungen), begrenzt \(zaehlwerk.begrenzteZerlegungen)")
    }

    /// Zählt, wie oft der Bogen die Bilanz der Vorschau rechnen lässt.
    final class Vorschauzaehler { var zahl = 0 }

    @Test("Der Vorrat rechnet die Bilanz der Vorschau einmal je Auswertung, Kopfzeile, Zuordnung und Ziel (Z-AY2-01)")
    func vorratVorschau() {
        let daten = Self.schulliste(konten: 30)
        let vorrat = Importvorrat()
        let zaehler = Vorschauzaehler()
        let zuordnung = IServImport.Zuordnung(vorname: 1, nachname: 2, klasse: 4)
        let a = vorrat.auswertung(daten, kodierung: nil, trenner: nil)
        func rechnen() -> Importbilanz { zaehler.zahl += 1; return Importbilanz() }
        _ = vorrat.vorschau(a, kopfzeile: true, zuordnung: zuordnung, ziel: .gruppe("g-1"), rechnen: rechnen)
        _ = vorrat.vorschau(a, kopfzeile: true, zuordnung: zuordnung, ziel: .gruppe("g-1"), rechnen: rechnen)
        #expect(zaehler.zahl == 1, "gemerkt")
        _ = vorrat.vorschau(a, kopfzeile: true, zuordnung: zuordnung, ziel: .jeKlasse, rechnen: rechnen)
        _ = vorrat.vorschau(a, kopfzeile: false, zuordnung: zuordnung, ziel: .jeKlasse, rechnen: rechnen)
        let b = vorrat.auswertung(daten, kodierung: nil, trenner: .komma)
        _ = vorrat.vorschau(b, kopfzeile: false, zuordnung: zuordnung, ziel: .jeKlasse, rechnen: rechnen)
        #expect(zaehler.zahl == 4, "neu nach Ziel, Kopfzeile und Auswertung")
    }

    @Test("Trenner: Eine erkannte IServ-Kopfzeile gilt vor der Zählung — sonst ließe ein Komma in einer Spalte bei offenem Anführungszeichen den falschen gewinnen (E890, Z-AY2-07)")
    func trennerMitKopf() {
        var text = "Account;Vorname;Nachname;E-Mail;Klasse/Information;Gruppen;Status;Erstellt;Letzter Login;Quota;Rolle;Notiz\r\n"
        for i in 0..<30 {
            text += "konto.\(i);Vorname\(i);Nachname\(i);konto.\(i)@schule.example;\(5 + i % 8)a;Schueler, Klasse \(5 + i % 8);"
                + "aktiv;2025-08-01;2026-10-20;500 MB;Schüler;\(i == 5 ? "\"Kalle" : "")\r\n"
        }
        #expect(IServImport.trennerErkennen(text) == .semikolon, "vorher: Komma")
        #expect(IServImport.zerlegung(text, trenner: .semikolon).offenesAnfuehrungszeichen == 7, "die Sperre greift")
        // Wie aus dem Bogen: mit Byte-Reihenfolge-Zeichen und CRLF, Kodierung und Trenner erkannt (H2-03).
        let auswertung = Importvorrat().auswertung(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8), kodierung: nil, trenner: nil)
        #expect(auswertung.erkannterTrenner == .semikolon && auswertung.zerlegung.offenesAnfuehrungszeichen == 7,
                "auch mit BOM über den Bogen")
        #expect(IServImport.trennerErkennen(text.replacingOccurrences(of: "\"Kalle", with: "Kalle")) == .semikolon,
                "gültig wie bisher")
        #expect(IServImport.trennerErkennen("a,b,c\nd,e,f") == .komma, "ohne IServ-Kopf zählt die Zählung wie bisher")
    }

    @Test("Gleichnamige der Datei nach derselben Regel wie `gleicherName`: Groß/Klein und Leerraum unerheblich (Z-AY2N-02)")
    func gleichnamigeEineRegel() throws {
        typealias I = ImportPruefungen
        // Schlüssel gleich genau dann, wenn `gleicherName` gleich sagt — auch mit dem Trenner U+001F in der Eingabe.
        let paare: [((String, String), (String, String))] = [
            (("Max", "Mai"), (" max ", "MAI")), (("Max", "Mai"), ("Max Mai", "")), (("Max", "Mai"), ("Max", "Mai-Abel")),
            (("a\u{1F}b", "c"), ("a", "b\u{1F}c")), (("Anna\tLena", "Abel"), ("anna lena", "ABEL")),
        ]
        for ((v1, n1), (v2, n2)) in paare {
            let person = Lernender(id: "l-x", vorname: v2, nachname: n2, angelegt: I.stempel, geaendert: I.stempel, archiviert: "")
            let schluesselGleich: Bool = Lernendenbestand.namensschluessel(v1, n1) == Lernendenbestand.namensschluessel(v2, n2)
            let nameGleich: Bool = Lernendenbestand.gleicherName(v1, n1, wie: person)
            #expect(schluesselGleich == nameGleich, "\(v1)|\(n1) gegen \(v2)|\(n2)")
        }
        #expect(Lernendenbestand.namensschluessel("Max", "Mai") == Lernendenbestand.namensschluessel(" max ", "MAI"))
        #expect(Lernendenbestand.namensschluessel("a\u{1F}b", "c") != Lernendenbestand.namensschluessel("a", "b\u{1F}c"))
        let daten = I.datei([I.zeile("Max", "Mai"), I.zeile("Ben", "Bauer"), I.zeile("max ", "  MAI")])
        let bilanz = I.bestand().mitImport(try I.lesung(daten), ziel: .gruppe("g-1"), jetzt: I.jetzt).bilanz
        #expect(bilanz.uebergangen.map(\.nummer) == [2, 4] && bilanz.uebergangen[0].grund.contains("Zeilen 2 und 4"),
                "\(bilanz.uebergangen.map(\.grund))")
    }

    @Test("Wortlaute bei offenem Anführungszeichen — wie freigegeben (E885)")
    func offenWortlaute() {
        let t = ImportBogen.offenTexte(7)
        #expect(t.fuss == "Zeile 7 öffnet ein Anführungszeichen, das bis zum Ende der Datei nicht geschlossen wird — der Rest "
                + "der Datei stünde in einem einzigen Feld. Bitte die Datei prüfen; so wird nichts importiert.")
        #expect(t.zeile == "Offenes Anführungszeichen in Zeile 7 — nichts wird importiert.")
        #expect(t.hilfe == "Die Datei öffnet in Zeile 7 ein Anführungszeichen, das nicht geschlossen wird.")
    }

    @Test("Der Vorrat zerlegt erst nach einem Wechsel von Kodierung oder Trenner neu; die Lesung nach Kopfzeile oder Zuordnung")
    func vorratWechselt() {
        let daten = Self.schulliste(konten: 30)
        let vorrat = Importvorrat()
        let zaehlwerk = IServImport.Zaehlwerk()
        IServImport.$zaehlwerk.withValue(zaehlwerk) {
            let a = vorrat.auswertung(daten, kodierung: nil, trenner: nil)
            _ = vorrat.auswertung(daten, kodierung: nil, trenner: nil)
            #expect(zaehlwerk.ganzeZerlegungen == 1 && a.erkannterTrenner == .semikolon && a.spaltenzahl == 12)
            let zuordnung = IServImport.Zuordnung(vorname: 1, nachname: 2, klasse: 4)
            let komma = vorrat.auswertung(daten, kodierung: nil, trenner: .komma)
            #expect(zaehlwerk.ganzeZerlegungen == 2 && komma.zerlegung.zeilen.first?.count == 1, "neu zerlegt mit Komma")
            #expect(vorrat.lesung(komma, kopfzeile: true, zuordnung: zuordnung).zeilen.first?.nachname != "Nachname0",
                    "unter Komma andere Felder")
            // Derselbe Kopf, dieselbe Zuordnung — nach dem Wechsel des Trenners trotzdem neu gelesen (Z-AY2-02).
            let semikolon = vorrat.auswertung(daten, kodierung: nil, trenner: .semikolon)
            let l1 = vorrat.lesung(semikolon, kopfzeile: true, zuordnung: zuordnung)
            let l2 = vorrat.lesung(semikolon, kopfzeile: false, zuordnung: zuordnung)
            #expect(l1.zeilen.count == 30 && l1.zeilen.first?.nachname == "Nachname0", "unter Semikolon die Namen")
            #expect(l2.zeilen.count == 31, "die Kopfzeile wechselt die Lesung")
            _ = vorrat.auswertung(daten, kodierung: .windows1252, trenner: .semikolon)
            #expect(zaehlwerk.ganzeZerlegungen == 4, "ein Wechsel der Kodierung zerlegt neu")
        }
    }
}
