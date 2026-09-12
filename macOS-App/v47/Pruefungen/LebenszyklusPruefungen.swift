// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Schlüssellebenszyklus ─────────────────────────────────────────────
// Nach jedem Übergang wird jede Datei, die den Datenschlüssel trägt, gegen
// alte und neue Schlüssel gehalten: Ablage, Vorgängerfassung, Rettungskopien
// beider Arten, Behälter der Lesezeichen, Kopie außer Haus, Statusdatei.

@Suite("Schlüssellebenszyklus: alte Schlüssel öffnen nichts mehr, neue alles")
@MainActor
struct LebenszyklusPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let alt = "Ein Satz, den man behält"
    private let neu = "Ein anderer Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "lebenszyklus-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func aufraeumen(_ orte: URL...) {
        for ort in orte { try? FileManager.default.removeItem(at: ort) }
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Lebenszyklus", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Bits",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    /// Ein eingeschalteter Speicher mit Zielordner, Kopie, Statusdatei,
    /// Vorgängerfassung und je einer Rettungskopie beider Arten.
    private func eingeschaltet(ablage: URL, ziel: URL) throws -> (Planungsspeicher, blatt: String) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        s.autoexportZielSetzen(ziel.path)
        let blatt = try s.verschluesselungVorbereiten(passphrase: alt)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let tresor = try #require(s.tresor)
        let stand = Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(), planungstitel: "Lebenszyklus",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "vom iPad")])
        try tresor.versiegeln(try Statusdatei.schreiben(stand), inhalt: .status, ziel: .kopie)
            .write(to: ziel.appending(component: Statusdatei.name), options: [.atomic])
        try Data("kein JSON".utf8).write(to: ablage.appending(component: "planung-beschaedigt-2026-01-01-000000.json"))
        try tresor.versiegeln(try Ordnerzugriff.nutzlast(eintraege: [:], zielordner: ""),
                              inhalt: .lesezeichen, ziel: .ablage)
            .write(to: ablage.appending(component: "lesezeichen-fremd-2026-01-01-000000.json"))
        return (s, blatt)
    }

    /// Alles, was den Datenschlüssel trägt.
    private func dateien(ablage: URL, ziel: URL, kopie: String) throws -> [URL] {
        let a = Ablage(ordner: ablage)
        return try [a.datei, a.vorherigeFassung, a.lesezeichen, ziel.appending(component: kopie),
                    ziel.appending(component: Statusdatei.name)] + a.nebendateien()
    }

    @Test("Passphrase ändern: die alte öffnet keine Datei mehr, die neue jede")
    func passphraseAendern() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { aufraeumen(ablage, ziel) }
        let (s, _) = try eingeschaltet(ablage: ablage, ziel: ziel)
        let tresor = try #require(s.tresor)

        let ergebnis = try s.passphraseAendern(alt: alt, neu: neu)
        #expect(ergebnis.offenes.isEmpty, "\(ergebnis.offenes)")
        for datei in try dateien(ablage: ablage, ziel: ziel, kopie: s.autoexportDateiname) {
            let name = datei.lastPathComponent
            let kopf = try Tresor.kopfLesen(try Data(contentsOf: datei))
            #expect(kopf.kennung == tresor.kennung, "\(name): derselbe Datenschlüssel")
            #expect(throws: Tresorfehler.self, "\(name): die alte Passphrase") { try Tresor.oeffnen(kopf: kopf, passphrase: alt) }
            #expect(try Tresor.oeffnen(kopf: kopf, passphrase: neu).kennung == tresor.kennung, "\(name)")
        }
    }

    @Test("Schlüssel erneuern: weder alte Passphrase noch alter Datenschlüssel noch altes Blatt öffnen eine Datei")
    func erneuern() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { aufraeumen(ablage, ziel) }
        let (s, altesBlatt) = try eingeschaltet(ablage: ablage, ziel: ziel)
        let alter = try #require(s.tresor)

        _ = try s.schluesselErneuernVorbereiten(alt: alt, neu: neu)
        let ergebnis = s.verschluesselungEinschalten()
        #expect(ergebnis.offenes.isEmpty, "\(ergebnis.offenes)")
        let neuer = try #require(s.tresor)
        #expect(neuer.kennung != alter.kennung)
        for datei in try dateien(ablage: ablage, ziel: ziel, kopie: s.autoexportDateiname) {
            let name = datei.lastPathComponent
            let kopf = try Tresor.kopfLesen(try Data(contentsOf: datei))
            #expect(kopf.kennung == neuer.kennung, "\(name)")
            #expect(throws: Tresorfehler.self, "\(name): alte Passphrase") { try Tresor.oeffnen(kopf: kopf, passphrase: alt) }
            #expect(throws: Tresorfehler.self, "\(name): alter Datenschlüssel") { try alter.oeffnen(kopf: kopf) }
            #expect(throws: Tresorfehler.self, "\(name): altes Blatt") {
                try Tresor.oeffnen(kopf: kopf, wiederherstellung: altesBlatt)
            }
            #expect(try Tresor.oeffnen(kopf: kopf, passphrase: neu).kennung == neuer.kennung, "\(name)")
        }
    }

    @Test("Ein Wechsel der Hülle erreicht die Vorgängerfassung — sofort und beim nächsten Start")
    func huellenwechsel() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { aufraeumen(ablage, ziel) }
        let (s, _) = try eingeschaltet(ablage: ablage, ziel: ziel)
        let tresor = try #require(s.tresor)
        let vorige = Ablage(ordner: ablage).vorherigeFassung

        // Wie beim Abschalten von Touch ID: Die Hülle wechselt am Tresor, dann
        // versiegelt der Speicher neu — und die eben fortgeschriebene
        // Vorgängerfassung darf die alte Hülle nicht behalten.
        try tresor.passphraseSetzen(neu, runden: Tresor.rundenMindestens)
        _ = s.neuVersiegeln()
        for datei in [Ablage(ordner: ablage).datei, vorige, Ablage(ordner: ablage).lesezeichen] {
            let kopf = try Tresor.kopfLesen(try Data(contentsOf: datei))
            #expect(tresor.huelleGleich(kopf, ziel: .ablage), "\(datei.lastPathComponent)")
        }

        // Ein zweiter Wechsel ohne Nachziehen — der nächste Start holt ihn nach.
        let dritte = "Ein dritter Satz, den man behält"
        try tresor.passphraseSetzen(dritte, runden: Tresor.rundenMindestens)
        s.sicherung.neuSchreibenErzwingen()
        s.jetztSichern()
        #expect(!tresor.huelleGleich(try Tresor.kopfLesen(try Data(contentsOf: vorige)), ziel: .ablage))
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablage))
        zweiter.starten()
        await zweiter.entsperren(passphrase: dritte)
        let neuerTresor = try #require(zweiter.tresor)
        #expect(neuerTresor.huelleGleich(try Tresor.kopfLesen(try Data(contentsOf: vorige)), ziel: .ablage),
                "beim Start nachgezogen")
    }

    @Test("Touch ID aus und wieder an: Ablage, Vorgängerfassung und Behälter der Lesezeichen tragen dieselbe Hülle")
    func enklaveSchalter() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { aufraeumen(ablage, ziel) }
        let (s, _) = try eingeschaltet(ablage: ablage, ziel: ziel)
        let tresor = try #require(s.tresor)
        guard Tresor.enklaveVorhanden else { return }
        s.enklaveImPruefstandAnlegen = true
        let a = Ablage(ordner: ablage)
        let dateien = [a.datei, a.vorherigeFassung, a.lesezeichen]

        s.enklaveAufDiesemMac(true)
        #expect(tresor.hat(Wicklung.enklave) && s.enklaveEingerichtet)
        for datei in dateien {
            let kopf = try Tresor.kopfLesen(try Data(contentsOf: datei))
            #expect(kopf.wicklung(Wicklung.enklave) != nil && tresor.huelleGleich(kopf, ziel: .ablage),
                    "\(datei.lastPathComponent): mit Wicklung dieses Macs")
        }
        s.enklaveAufDiesemMac(false)
        #expect(!tresor.hat(Wicklung.enklave) && !s.enklaveEingerichtet)
        for datei in dateien {
            let kopf = try Tresor.kopfLesen(try Data(contentsOf: datei))
            #expect(kopf.wicklung(Wicklung.enklave) == nil && tresor.huelleGleich(kopf, ziel: .ablage),
                    "\(datei.lastPathComponent): ohne Wicklung dieses Macs")
        }
    }

    @Test("Aufheben entsiegelt auch die Rettungskopien beider Arten; der Behälter der Lesezeichen geht")
    func aufheben() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { aufraeumen(ablage, ziel) }
        let (s, _) = try eingeschaltet(ablage: ablage, ziel: ziel)

        let ergebnis = s.verschluesselungAufheben()
        #expect(ergebnis.nebendateien.vollstaendig && ergebnis.lesezeichen == .erledigt)
        let a = Ablage(ordner: ablage)
        #expect(try a.nebendateien().count == 3, "Vorgängerfassung und zwei Rettungskopien")
        for datei in try [a.datei] + a.nebendateien() {
            #expect(!Tresor.istBehaelter(try Data(contentsOf: datei)), "\(datei.lastPathComponent)")
        }
        #expect(!FileManager.default.fileExists(atPath: a.lesezeichen.path))
    }

    @Test("Lässt sich der Behälter der Lesezeichen nicht anlegen, wird nicht eingeschaltet")
    func einschaltenScheitertAmBehaelter() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { aufraeumen(ablage, ziel) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        s.autoexportZielSetzen(ziel.path)
        let vorher = try Data(contentsOf: Ablage(ordner: ablage).datei)
        // Ein Ordner, wo der Behälter hin soll: Das Schreiben scheitert, die Ablage bliebe schreibbar.
        try FileManager.default.createDirectory(at: Ablage(ordner: ablage).lesezeichen, withIntermediateDirectories: false)

        _ = try s.verschluesselungVorbereiten(passphrase: alt)
        let ergebnis = s.verschluesselungEinschalten()
        guard case .zurueckgenommen(let grund) = ergebnis.ablage else {
            Issue.record("erwartet zurückgenommen, war \(ergebnis.ablage)"); return
        }
        #expect(grund.contains("Lesezeichen"))
        #expect(s.tresor == nil && s.verschluesselungsstand == .aus)
        #expect(try Data(contentsOf: Ablage(ordner: ablage).datei) == vorher, "die Ablage blieb unangetastet")
        #expect(s.zugriff.quelle == .einstellungen && s.autoexportOrdner == ziel.path)
        #expect(s.meldungen.last?.text.contains("nicht eingeschaltet") == true)
    }

    @Test("Eine Planung aus einer neueren Fassung bleibt liegen: gesperrt ohne Kopf, nichts wird angelegt")
    func neuereFassung() throws {
        let ablage = try ordner("ablage")
        defer { aufraeumen(ablage) }
        var objekt = try #require(JSONSerialization.jsonObject(with: try Planungsdatei.schreiben(try planung()))
                                    as? [String: Any])
        objekt["version"] = Kennwerte.dateiVersion + 1
        let neuer = try JSONSerialization.data(withJSONObject: objekt)
        try neuer.write(to: Ablage(ordner: ablage).datei)

        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.starten()
        #expect(s.ablageGesperrt && s.sitzung.entsperrung == nil && s.planung == nil)
        #expect(s.zugriff.quelle == .zu)
        #expect(s.meldungen.last?.text.contains("neueren Fassung") == true)
        s.neuePlanung(titel: "Trotzdem", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                      klassen: [], ersterSchultag: nil, uebernahme: [])
        #expect(s.planung == nil && s.meldungen.last?.text.contains("neueren Fassung") == true,
                "nichts angelegt, nichts still verworfen")
        #expect(try Data(contentsOf: Ablage(ordner: ablage).datei) == neuer, "die Datei bleibt unangetastet")
        #expect(try Ablage(ordner: ablage).nebendateien().isEmpty, "nichts beiseitegelegt")
    }

    @Test("Eine Passphrase aus Leerraum wird beim Anlegen abgewiesen; beim Erneuern muss die neue eine andere sein")
    func passphraseRegeln() throws {
        #expect(throws: Tresorfehler.self) { try Tresor.neu().passphraseSetzen(String(repeating: " ", count: 12)) }
        #expect(throws: Tresorfehler.self) { try Tresor.neu().passphraseSetzen("zu kurz") }
        #expect(!Passphrasenwahl.vollstaendig("            ", "            "))
        #expect(!Passphrasenwahl.vollstaendig(" mit Rand am Anfang", " mit Rand am Ende"))
        #expect(Passphrasenwahl.vollstaendig(" mit Rand am Anfang", " mit Rand am Anfang"))
        #expect(!Passphrasenwahl.vollstaendig(alt, alt, bisherige: alt), "erneuern: dieselbe gilt nicht")
        #expect(!Passphrasenwahl.vollstaendig(neu, neu, bisherige: ""), "erneuern: bisherige belegen")
        #expect(Passphrasenwahl.vollstaendig(neu, neu, bisherige: alt))
    }

    @Test("Geht der Zielordner mit dem Behälter verloren, fragt die Nachwahl — auch ohne Pfad")
    func zielordnerVerloren() async throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { aufraeumen(ablage, ziel) }
        let (s, _) = try eingeschaltet(ablage: ablage, ziel: ziel)
        _ = s
        try Data("Unsinn".utf8).write(to: Ablage(ordner: ablage).lesezeichen)

        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablage))
        zweiter.nachwahlProbe = true
        zweiter.starten()
        await zweiter.entsperren(passphrase: alt)
        #expect(zweiter.verschluesselungsstand == .an && zweiter.autoexportOrdner.isEmpty)
        zweiter.autoexportAktiv = true
        zweiter.freigabenNachfuehren()
        #expect(zweiter.ausstehendeFreigaben == [.init(zweck: .zielordner, pfad: "")])
        #expect(zweiter.ausstehendeFreigaben.first?.titel == "Ordner der Sicherungskopie")
    }
}
