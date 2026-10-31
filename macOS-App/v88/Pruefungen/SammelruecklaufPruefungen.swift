// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Stand für mehrere bei den Mitteilungen (v88, AZ4: E903, E909, E910, E915, E929; AZ5: E937; AZ6a: E941–E943) ──
// Mehrere Gewählte in der Rücklaufliste einer Lerngruppe bekommen einen Stand für die gewählte Mitteilung: nur Betroffene,
// die nicht archiviert sind (E903); der Tag nach der Regel für eine Person (E910), die Notiz bleibt; ein Schritt, bei einer
// Person „Rücklauf eintragen“ (E915). Die Wortlaute nach E929, die Hilfe am Menü nach E937. Reine Funktionen am Bestand;
// den Weg über das Blatt prüft die Lernendenprobe.

@Suite("Stand für mehrere bei den Mitteilungen")
@MainActor
struct SammelruecklaufPruefungen {

    private static let s = "2026-08-20T08:00:00.000Z"
    private static let jetzt = "2026-10-29T08:30:00.000Z"
    private static let heute = "2026-10-29"

    private static let anna = "l-anna", ben = "l-ben", clara = "l-clara", david = "l-david", emil = "l-emil"

    private static func person(_ id: String, _ vorname: String, _ nachname: String, archiviert: String = "") -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: s, geaendert: s, archiviert: archiviert)
    }

    private static func rueck(_ person: String, _ stand: Rueckmeldestand, _ datum: String, _ notiz: String = "",
                              anliegen: String = "m-w") -> Rueckmeldung {
        Rueckmeldung(anliegen: anliegen, lernender: person, stand: stand, datum: datum, notiz: notiz, geaendert: s)
    }

    /// Das Beispiel aus E929: Die Klasse 5a; „Wandertag · 01.09.2026“ betrifft Anna, Ben, Clara und David. David ist
    /// archiviert, Emil kam später in die 5a und ist nicht betroffen. Anna hat „erledigt“ vom 03.09.2026, Ben und Clara
    /// stehen auf „offen“ ohne Tag. Dazu „Elternabend“ ohne Tag an alle und die Maßnahme „Nacharbeit“ für Ben.
    private static func bestand() -> Lernendenbestand { bestand([rueck(anna, .erledigt, "2026-09-03")]) }

    private static func bestand(_ rueckmeldungen: [Rueckmeldung]) -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [person(anna, "Anna", "Adam"), person(ben, "Ben", "Brandt"), person(clara, "Clara", "Conrad"),
                      person(david, "David", "Dorn", archiviert: s), person(emil, "Emil", "Eck")]
        b.lerngruppen = [Lerngruppe(id: "g-5a", name: "5a", art: .klasse, mitglieder: [anna, ben, clara, david, emil],
                                    zeilen: [], skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        b.anliegen = [
            Anliegen(id: "m-w", art: .mitteilung, titel: "Wandertag", lerngruppe: "g-5a",
                     betroffene: [anna, ben, clara, david], datum: "2026-09-01", frist: "", notiz: "", angelegt: s,
                     geaendert: s),
            Anliegen(id: "m-e", art: .mitteilung, titel: "Elternabend", lerngruppe: "g-5a",
                     betroffene: [anna, ben, clara, david, emil], datum: "", frist: "", notiz: "", angelegt: s,
                     geaendert: s),
            Anliegen(id: "m-n", art: .massnahme, titel: "Nacharbeit", lerngruppe: "g-5a", betroffene: [ben],
                     datum: "2026-10-01", frist: "2026-10-08", notiz: "", angelegt: s, geaendert: s),
        ]
        b.rueckmeldungen = rueckmeldungen
        return b
    }

    private static func r(_ b: Lernendenbestand, _ person: String, _ anliegen: String = "m-w") -> Rueckmeldung? {
        b.rueckmeldungen.first { $0.anliegen == anliegen && $0.lernender == person }
    }

    private static func setzen(_ b: Lernendenbestand, _ personen: [String], _ stand: Rueckmeldestand,
                               anliegen: String = "m-w") -> Lernendenbestand.Sammelergebnis {
        b.mitRuecklaeufen(anliegen, personen, stand: stand, heute: heute, jetzt: jetzt)
    }

    // ── Am Bestand ────────────────────────────────────────────────────────

    @Test("E929, Beispiel 1: Ben, Clara, Emil und David auf „erledigt“ — zwei mit dem heutigen Tag, zwei übergangen")
    func beispielEins() {
        let b = Self.bestand()
        let e = Self.setzen(b, [Self.ben, Self.clara, Self.emil, Self.david], .erledigt)
        #expect(e.zahl == 2 && e.uebergangen == 2 && e.grund == nil)
        for p in [Self.ben, Self.clara] {
            #expect(Self.r(e.bestand, p).map { [$0.stand.rawValue, $0.datum] } == ["erledigt", Self.heute], "\(p)")
        }
        #expect(Self.r(e.bestand, Self.emil) == nil && Self.r(e.bestand, Self.david) == nil)
        #expect(Self.r(e.bestand, Self.anna) == Self.r(b, Self.anna))
    }

    @Test("E910, Beispiel 2: Anna und Ben auf „erledigt“ — Anna behält den 03.09., Ben bekommt den heutigen; geändert nur Ben")
    func beispielZwei() {
        let e = Self.setzen(Self.bestand(), [Self.anna, Self.ben], .erledigt)
        #expect(e.zahl == 1 && e.uebergangen == 0)
        #expect(Self.r(e.bestand, Self.anna)?.datum == "2026-09-03")
        #expect(Self.r(e.bestand, Self.ben).map { [$0.stand.rawValue, $0.datum] } == ["erledigt", Self.heute])
    }

    @Test("E910: Die Notiz bleibt je Person — Claras „kommt nach“ auch nach „abgelehnt“")
    func notizBleibt() {
        let b = Self.bestand([Self.rueck(Self.anna, .erledigt, "2026-09-03"), Self.rueck(Self.clara, .offen, "", "kommt nach")])
        let e = Self.setzen(b, [Self.ben, Self.clara], .abgelehnt)
        #expect(e.zahl == 2)
        #expect(Self.r(e.bestand, Self.clara).map { [$0.stand.rawValue, $0.datum, $0.notiz] }
                == ["abgelehnt", Self.heute, "kommt nach"])
        #expect(Self.r(e.bestand, Self.ben)?.notiz == "")
    }

    @Test("E929, Beispiel 3: Anna und Ben auf „offen“ — wie bei einer Person: ohne Notiz geht Annas Rücklauf samt Tag, mit Notiz bleibt ihr Tag")
    func aufOffen() {
        let ohne = Self.setzen(Self.bestand(), [Self.anna, Self.ben], .offen)
        #expect(ohne.zahl == 1 && Self.r(ohne.bestand, Self.anna) == nil && Self.r(ohne.bestand, Self.ben) == nil)
        let mit = Self.setzen(Self.bestand([Self.rueck(Self.anna, .erledigt, "2026-09-03", "Zettel fehlt")]),
                              [Self.anna, Self.ben], .offen)
        #expect(mit.zahl == 1)
        #expect(Self.r(mit.bestand, Self.anna).map { [$0.stand.rawValue, $0.datum, $0.notiz] }
                == ["offen", "2026-09-03", "Zettel fehlt"])
    }

    @Test("E929, Fall 9: Haben alle den Stand schon, ändert sich nichts — kein Schritt, kein Hinweis")
    func schonSo() {
        let b = Self.bestand([Self.rueck(Self.anna, .erledigt, "2026-09-03"), Self.rueck(Self.ben, .erledigt, "2026-09-04")])
        let e = Self.setzen(b, [Self.anna, Self.ben], .erledigt)
        #expect(e.zahl == 0 && e.uebergangen == 0 && e.bestand == b)
    }

    @Test("E903: Archivierte, die betroffen sind, übergeht der Griff wie nicht Betroffene — David und Emil: nichts geändert")
    func archivierteUebergangen() {
        let b = Self.bestand()
        #expect(b.ruecklaufziel("m-w", [Self.david, Self.emil]).isEmpty)
        let e = Self.setzen(b, [Self.david, Self.emil], .erledigt)
        #expect(e.zahl == 0 && e.uebergangen == 2 && e.bestand == b)
        // Für „Elternabend“ ist Emil betroffen — David bleibt übergangen, weil archiviert.
        #expect(b.ruecklaufziel("m-e", [Self.david, Self.emil]) == [Self.emil])
    }

    @Test("Ein Griff wie je Person nacheinander — alle fünf gewählt, „abgelehnt“")
    func wieNacheinander() {
        let b = Self.bestand([Self.rueck(Self.anna, .erledigt, "2026-09-03"), Self.rueck(Self.clara, .offen, "", "kommt nach")])
        let alle = [Self.anna, Self.ben, Self.clara, Self.david, Self.emil]
        let erwartet = b.ruecklaufziel("m-w", alle).reduce(b) { stand, p in
            let alt = Self.r(stand, p)
            return stand.mitRuecklauf("m-w", p, stand: .abgelehnt,
                                      datum: Lernendenbestand.tagNachStand(.abgelehnt, bisher: alt?.datum ?? "",
                                                                           heute: Self.heute),
                                      notiz: alt?.notiz ?? "", jetzt: Self.jetzt)
        }
        let e = Self.setzen(b, alle, .abgelehnt)
        #expect(e.bestand == erwartet && e.zahl == 3 && e.uebergangen == 2)
    }

    @Test("E935: An der Grenze der Datei ganz oder gar nicht — reicht der Platz nicht für alle neuen Rückläufe, bleibt alles, und die Meldung nennt die Grenze statt der Übergangenen")
    func grenzeGanzOderGar() {
        let fuelle = (1..<(Lernendendatei.maxRueckmeldungen - 1)).map {
            Self.rueck("l-x\($0)", .erledigt, "2026-09-02", anliegen: "m-alt")
        }
        let b = Self.bestand([Self.rueck(Self.anna, .erledigt, "2026-09-03")] + fuelle)
        #expect(b.rueckmeldungen.count == Lernendendatei.maxRueckmeldungen - 1)
        let e = Self.setzen(b, [Self.ben, Self.clara, Self.emil], .erledigt)
        #expect(e.zahl == 0 && e.bestand == b && e.uebergangen == 0)
        #expect(e.grund == "Die Lernendendaten dieses Schuljahrs hätten 60\u{00A0}001 Rückläufe — höchstens 60\u{00A0}000. "
                + "Nichts ist geändert.")
        // Ein neuer passt noch.
        #expect(Self.setzen(b, [Self.ben], .erledigt).zahl == 1)
    }

    @Test("Nur an einer Mitteilung — eine Maßnahme ändert der Griff nicht")
    func nurMitteilung() {
        let b = Self.bestand()
        #expect(b.ruecklaufziel("m-n", [Self.ben]).isEmpty)
        let e = Self.setzen(b, [Self.ben, Self.clara], .erledigt, anliegen: "m-n")
        #expect(e.zahl == 0 && e.bestand == b)
    }

    @Test("Doppelte zählen einmal, die Folge bleibt die der Gewählten")
    func doppelte() {
        let b = Self.bestand()
        #expect(b.ruecklaufziel("m-w", [Self.clara, Self.ben, Self.clara]) == [Self.clara, Self.ben])
        #expect(Self.setzen(b, [Self.clara, Self.ben, Self.clara], .erledigt).uebergangen == 0)
    }

    @Test("E910: Die Tag-Regel — ohne Tag der heutige, „offen“ und ein vorhandener Tag behalten, was da ist")
    func tagregel() {
        #expect(Lernendenbestand.tagNachStand(.erledigt, bisher: "", heute: Self.heute) == Self.heute)
        #expect(Lernendenbestand.tagNachStand(.abgelehnt, bisher: "", heute: Self.heute) == Self.heute)
        #expect(Lernendenbestand.tagNachStand(.erledigt, bisher: "2026-09-03", heute: Self.heute) == "2026-09-03")
        #expect(Lernendenbestand.tagNachStand(.offen, bisher: "", heute: Self.heute) == "")
        #expect(Lernendenbestand.tagNachStand(.offen, bisher: "2026-09-03", heute: Self.heute) == "2026-09-03")
    }

    // ── Wortlaute (E929, E937) ────────────────────────────────────────────

    @Test("E929, E937: Kopf, Menü, Hilfe, Sperrgrund, Hinweis und Schritt — Wort für Wort")
    func wortlaute() throws {
        let b = Self.bestand()
        let wandertag = try #require(b.anliegen.first { $0.id == "m-w" })
        let elternabend = try #require(b.anliegen.first { $0.id == "m-e" })
        #expect(Lernendenblatt.sammelkopf(3) == "3 gewählt")
        #expect(Ruecklaufliste.standmenueTitel(wandertag) == "Stand für „Wandertag · 01.09.2026“")
        #expect(Ruecklaufliste.standmenueTitel(elternabend) == "Stand für „Elternabend“")
        // E937 (a): die Regel für „offen“ genannt (Z-AZ5-04) — statt „ohne Tag gilt der heutige; ein vorhandener Tag und
        // die Notizen bleiben“ (E929).
        #expect(Ruecklaufliste.standmenueHilfe == "Den Rücklauf der Gewählten zu dieser Mitteilung setzen — bei erledigt "
                + "oder abgelehnt gilt ohne Tag der heutige; „offen“ ohne Notiz nimmt den Rücklauf weg; sonst bleiben Tag "
                + "und Notizen")
        #expect(Ruecklaufliste.standmenueSperrgrund == "Erst eine betroffene, aktive Person wählen")
        #expect(Ruecklaufliste.uebergangenHinweis(0, wandertag) == nil)
        #expect(Ruecklaufliste.uebergangenHinweis(1, wandertag)
                == "1 gewählte Person ist von „Wandertag · 01.09.2026“ nicht betroffen oder archiviert und blieb unverändert.")
        #expect(Ruecklaufliste.uebergangenHinweis(2, wandertag)
                == "2 Gewählte sind von „Wandertag · 01.09.2026“ nicht betroffen oder archiviert und blieben unverändert.")
        #expect(Schrittname.ruecklaeufeAendern(1) == "Rücklauf eintragen")
        #expect(Schrittname.ruecklaeufeAendern(2) == "Rücklauf von 2 Personen ändern")
        #expect(Schrittname.alle.contains("Rücklauf von 2 Personen ändern"))
    }

    @Test("E935: Zahlen in Dreiergruppen mit geschütztem Leerzeichen")
    func tausender() {
        #expect(Lernendenbestand.tausender(0) == "0")
        #expect(Lernendenbestand.tausender(999) == "999")
        #expect(Lernendenbestand.tausender(1000) == "1\u{00A0}000")
        #expect(Lernendenbestand.tausender(60_001) == "60\u{00A0}001")
        #expect(Lernendenbestand.tausender(1_234_567) == "1\u{00A0}234\u{00A0}567")
        #expect(Lernendenbestand.tausender(-1000) == "-1\u{00A0}000")
        #expect(Lernendenbestand.tausender(.min) == "-9\u{00A0}223\u{00A0}372\u{00A0}036\u{00A0}854\u{00A0}775\u{00A0}808",
                "ohne Überlauf (Z-AZ4N-05)")
    }

    @Test("Z-AZ4-06: Haken und Sperre der Sammelleiste über die betroffenen, aktiven Gewählten — Anna und David: Haken bei „erledigt“; Emil und David: gesperrt")
    func sammelmenuelage() throws {
        let b = Self.bestand()
        let v = Lernendenverzeichnis(b)
        let m = try #require(b.anliegen.first { $0.id == "m-w" })
        #expect(Ruecklaufliste.sammelmenuelage(m, [Self.anna, Self.david], b, v) == Sammelmenuelage(haken: .erledigt, gesperrt: false),
                "David ist archiviert und zählt nicht")
        #expect(Ruecklaufliste.sammelmenuelage(m, [Self.emil, Self.david], b, v) == Sammelmenuelage(haken: nil, gesperrt: true))
        #expect(Ruecklaufliste.sammelmenuelage(m, [Self.ben, Self.clara], b, v) == Sammelmenuelage(haken: .offen, gesperrt: false))
        #expect(Ruecklaufliste.sammelmenuelage(m, [Self.anna, Self.ben], b, v) == Sammelmenuelage(haken: nil, gesperrt: false))
    }

    @Test("E929, Fall 5: Das Menü hakt einen Stand nur ab, wenn alle, die der Griff ändern darf, ihn haben")
    func haken() throws {
        let b = Self.bestand()
        let v = Lernendenverzeichnis(b)
        let m = try #require(b.anliegen.first { $0.id == "m-w" })
        #expect(Ruecklaufliste.gemeinsamerStand([Self.anna, Self.ben], m, v) == nil)
        #expect(Ruecklaufliste.gemeinsamerStand([Self.ben, Self.clara], m, v) == .offen)
        #expect(Ruecklaufliste.gemeinsamerStand([Self.anna], m, v) == .erledigt)
        #expect(Ruecklaufliste.gemeinsamerStand([], m, v) == nil)
    }

    // ── Die Probe am Menü der Sammelleiste (AZ6a, E941–E943) ──
    // Unter macOS 27 zeichnet SwiftUI das Menü selbst: Sein Titel steht dann an einem Knoten der Bedienungshilfen, der
    // sich nicht als `NSAccessibilityProtocol` ansprechen lässt — Rolle „statischer Text“, der Titel als Wert (Diagnose in
    // der VM 27.2, 29.10.2026). Unter macOS 26 ist es ein Knopf aus AppKit mit Titel.

    /// Ein Knoten wie der von SwiftUI unter macOS 27: kein `NSAccessibilityProtocol`, Rolle, Titel, Beschriftung und Wert nur
    /// als Selektoren — Titel und Beschriftung leer wie am echten Knoten.
    private final class Knoten: NSObject {
        let wert: Any?
        init(_ wert: Any?) { self.wert = wert }
        @objc func accessibilityRole() -> String { "AXStaticText" }
        @objc func accessibilityTitle() -> String? { nil }
        @objc func accessibilityLabel() -> String? { nil }
        @objc func accessibilityValue() -> Any? { wert }
    }

    /// Eine Gruppe mit Namen wie die Sammelleiste (`.accessibilityElement(children: .contain)`), ebenfalls ohne
    /// `NSAccessibilityProtocol`: ihre Kinder liest der Gang eine Stufe tiefer — eine Ansicht darunter nicht, die gehört
    /// zu den `subviews` (Z-AZ6a-03).
    private final class Gruppe: NSObject {
        let kinder: [Any]
        init(_ kinder: [Any]) { self.kinder = kinder }
        @objc func accessibilityLabel() -> String? { "3 gewählt" }
        @objc func accessibilityChildren() -> [Any]? { kinder }
    }

    /// Eine Methode mit dem Namen eines Selektors der Bedienungshilfen, aber mit einer Zahl als Rückgabe — `perform` läse
    /// sie als Zeiger (Z-AZ6a-04).
    private final class Zahlknoten: NSObject {
        @objc func accessibilityTitle() -> Int { 7 }
    }

    /// Das Menü, wie SwiftUI es unter macOS 27 baut, wenn eine Bedienungshilfe läuft: eine Menü-Taste, der Titel als
    /// formatierter Text (Diagnose in der VM 27.2 mit VoiceOver, 29.10.2026).
    private final class Menueknopf: NSObject {
        let titel: NSAttributedString
        init(_ titel: String) { self.titel = NSAttributedString(string: titel) }
        @objc func accessibilityRole() -> String { "AXMenuButton" }
        @objc func accessibilityTitle() -> Any? { titel }
    }

    /// Ein Knoten, der `accessibilityTitle` nicht als Methode hat, sondern an `ziel` weiterleitet — mit überschriebenem
    /// `responds(to:)` oder ohne. Ob der Knoten von SwiftUI unter macOS 27 so gebaut ist, ist offen; er antwortet dort auf
    /// `accessibilityTitle`, unter macOS 26 nicht (Z-AZ6aN-01, Z-AZ6aN2-01).
    private final class Weiterleiter: NSObject {
        let ziel: NSObject
        let antwortet: Bool
        init(_ ziel: NSObject, antwortet: Bool) { self.ziel = ziel; self.antwortet = antwortet }
        override func responds(to aSelector: Selector!) -> Bool {
            (antwortet && aSelector == NSSelectorFromString("accessibilityTitle")) || super.responds(to: aSelector)
        }
        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            aSelector == NSSelectorFromString("accessibilityTitle") ? ziel : super.forwardingTarget(for: aSelector)
        }
    }

    /// Ein Blatt, dessen Bedienungshilfen neben den Ansichten solche Knoten nennen.
    private final class Blatt: NSView {
        var knoten: [Any] = []
        override func accessibilityChildren() -> [Any]? { (super.accessibilityChildren() ?? []) + knoten }
    }

    @Test("E941: Den Titel des Menüs liest die Probe am Knopf aus AppKit (macOS 26) wie am Knoten von SwiftUI ohne NSAccessibilityProtocol (macOS 27)")
    func probeLiestMenuetitel() {
        let titel = "Stand für „Elternbrief Wandertag · 07.09.2026“"
        let mitKnopf = Blatt(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        mitKnopf.addSubview(NSButton(title: titel, target: nil, action: nil))
        #expect(Lernendenprobe.bedienungshilfenNamen(mitKnopf).contains(titel))
        let mitKnoten = Blatt(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        let ansicht = NSView(frame: .zero)
        ansicht.setAccessibilityLabel("Ansicht in der Gruppe")
        mitKnoten.knoten = [Gruppe([Knoten(titel), ansicht]), Knoten(nil), Knoten(NSNumber(value: 3)), Zahlknoten(), NSObject()]
        #expect(!(mitKnoten.knoten[1] is NSAccessibilityProtocol))
        let namen = Lernendenprobe.bedienungshilfenNamen(mitKnoten)
        #expect(namen.contains(titel))
        #expect(namen == ["3 gewählt", titel],
                "die Gruppe und ihr Knoten; ohne Text, mit einer Zahl als Wert oder als Rückgabe kein Name (Z-AZ6a-02 bis -04)")
    }

    @Test("E942/E943: Läuft eine Bedienungshilfe, trägt das Menü unter macOS 27 seinen Titel als formatierten Text — die Probe liest ihn wie eine Zeichenkette, ebenso den formatierten Wert eines Elements aus AppKit")
    func probeLiestFormatiertenTitel() {
        let titel = "Stand für „Elternbrief Wandertag · 07.09.2026“"
        let blatt = Blatt(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        let feld = NSView(frame: .zero)
        feld.setAccessibilityValue(NSAttributedString(string: "07.09.2026"))
        blatt.addSubview(feld)
        blatt.knoten = [Gruppe([Menueknopf(titel)])]
        #expect(Lernendenprobe.bedienungshilfenNamen(blatt) == ["07.09.2026", "3 gewählt", titel])
    }

    @Test("Z-AZ6aN-01: Ein weitergeleiteter Titel — die Probe folgt dem Ziel und prüft dort den Rückgabetyp; eine Zahl bringt keinen Namen")
    func probeFolgtWeiterleitung() {
        let titel = "Stand für „Elternbrief Wandertag · 07.09.2026“"
        func namen(_ knoten: NSObject) -> [String] {
            let blatt = Blatt(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
            blatt.knoten = [knoten]
            return Lernendenprobe.bedienungshilfenNamen(blatt)
        }
        #expect(namen(Weiterleiter(Menueknopf(titel), antwortet: true)) == [titel], "mit überschriebenem responds(to:)")
        #expect(namen(Weiterleiter(Menueknopf(titel), antwortet: false)) == [titel], "nur forwardingTarget(for:)")
        #expect(namen(Weiterleiter(Zahlknoten(), antwortet: true)).isEmpty, "das Ziel gibt eine Zahl zurück")
        // Bis vier Weiterleitungen folgt die Probe, darüber bringt die Kette keinen Namen (Z-AZ6aN3-01).
        var kurz: NSObject = Menueknopf(titel)
        for _ in 0..<3 { kurz = Weiterleiter(kurz, antwortet: true) }
        #expect(namen(kurz) == [titel], "drei Weiterleitungen bis zum Titel")
        var lang: NSObject = Zahlknoten()
        for _ in 0..<5 { lang = Weiterleiter(lang, antwortet: true) }
        #expect(namen(lang).isEmpty, "fünf Weiterleitungen bis zu einer Zahl")
    }
}
