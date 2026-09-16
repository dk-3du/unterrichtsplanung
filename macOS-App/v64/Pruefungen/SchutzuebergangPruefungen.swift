// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Übergang des Schutzes ─────────────────────────────────────────────
// Einschalten, Erneuern, Passphrase ändern, Wicklung, Aufheben — jeder in
// einem Stand über den Übergabestand (E47): mit eigener Ablage und eigenem
// Zielordner; die Meldung kommt aus dem, was die Platte danach trägt. Und
// jeder Abbruch nach jedem Schritt: Der nächste Start findet einen Stand.

@Suite("Schutzübergang: Einschalten, Erneuern, Passphrase, Wicklung, Aufheben — in einem Stand")
@MainActor
struct SchutzuebergangPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private let neue = "Ein anderer Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "uebergang-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Übergang", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Bits",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    /// Ein Speicher mit eigener Ablage und Zielordner, die Planung im Klartext.
    private func speicher(ablage: URL, ziel: URL) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.autoexportZielSetzen(ziel.path)
        return s
    }

    private func status(_ kommentar: String) -> Statusstand {
        Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(), planungstitel: "Übergang",
                    eintraege: ["e-1": .init(erledigt: true, kommentar: kommentar)])
    }

    private func statusdatei(_ ziel: URL) -> URL { ziel.appending(component: Statusdatei.name) }

    /// Eine Planung über der Schreibgrenze — wie `AblagePruefungen.riesenplanung`,
    /// mit frischem Stempel, damit die Sicherung sie auch schreiben will.
    private func riesenplanung() throws -> Planung {
        var p = try planung()
        let text = String(repeating: "x", count: Planungsdatei.maxTextlaenge)
        p.eintraege = (0..<1_700).map {
            Vorhaben(id: "r-\($0)", klasseId: p.klassen[0].id, woche: $0 % 4, titel: "Riese \($0)",
                     text: text, erledigt: false, materialien: [], links: [])
        }
        Thread.sleep(forTimeInterval: 0.003)
        p.geaendert = Zeitrechnung.jetztAlsZeitstempel()
        return p
    }

    private func schreibrecht(_ ordner: URL, _ an: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: an ? 0o700 : 0o500], ofItemAtPath: ordner.path)
    }

    /// Jede Datei geht mit `passphrase` auf — und mit keiner anderen.
    private func oeffnenNurMit(_ passphrase: String, nicht andere: String, _ dateien: [URL], kennung: Data) throws {
        for datei in dateien {
            let kopf = try Tresor.kopfLesen(try Data(contentsOf: datei))
            #expect(try Tresor.oeffnen(kopf: kopf, passphrase: passphrase).kennung == kennung, "\(datei.lastPathComponent)")
            #expect(throws: Tresorfehler.self, "\(datei.lastPathComponent)") {
                try Tresor.oeffnen(kopf: kopf, passphrase: andere)
            }
        }
    }

    /// Weder Marke noch Zwillinge, keine Rettungskopie — ein Stand.
    /// Keine offene Spur eines Übergangs mehr — was der Ausweg gestempelt ins
    /// Register gelegt hat, darf daneben liegen (E67, E73).
    private func keineOffeneSpur(_ ablage: URL) throws {
        let namen = try FileManager.default.contentsOfDirectory(atPath: ablage.path).sorted()
        #expect(!namen.contains(Uebergangsdienst.markenname), "\(namen)")
        #expect(!namen.contains(Uebergangsdienst.zweitschriftname), "\(namen)")
        #expect(!namen.contains { $0.hasSuffix(Uebergangsdienst.zwillingssuffix) || $0.hasSuffix(Uebergangsdienst.vorgaengersuffix) }, "\(namen)")
    }

    private func einStand(_ ablage: URL) throws {
        try keineOffeneSpur(ablage)
        let namen = try FileManager.default.contentsOfDirectory(atPath: ablage.path).sorted()
        #expect(!namen.contains { $0.contains("-fremd-") || $0.contains("-beschaedigt-")
                                 || $0.contains("-uebergang-") || $0.contains("-vorgaenger-") }, "\(namen)")
    }

    @Test("Einschalten: Ablage versiegelt und zurückgelesen, Kopie sofort, Statusdatei erst übernommen, dann neu versiegelt")
    func einschalten() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        // Ein Klartext-Status der Ansicht mit einem noch nicht übernommenen Haken.
        let stand = status("vom iPad")
        try Statusdatei.schreiben(stand).write(to: statusdatei(ziel), options: [.atomic])

        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        let tresor = try #require(s.tresor)
        #expect(ergebnis.ablage == .geschrieben)
        #expect(ergebnis.kopie == .erledigt && ergebnis.statusdatei == .erledigt)
        #expect(ergebnis.lesezeichen == .erledigt)
        #expect(ergebnis.offenes.isEmpty)
        try einStand(ablage)
        // Die Lesezeichen samt Zielordner liegen jetzt als Behälter neben der Ablage.
        #expect(s.zugriff.quelle == .behaelter)
        let lesezeichen = try Data(contentsOf: Ablage(ordner: ablage).lesezeichen)
        let lesezeichenKopf = try Tresor.kopfLesen(lesezeichen)
        #expect(lesezeichenKopf.inhalt == "lesezeichen" && lesezeichenKopf.kennung == tresor.kennung)
        let nutzlast = try Ordnerzugriff.nutzlastLesen(try tresor.oeffnen(kopf: lesezeichenKopf))
        #expect(nutzlast.zielordner == ziel.path && nutzlast.eintraege.count == 1)
        #expect(s.autoexportOrdner == ziel.path && s.zugriff.zustaendig(fuer: ziel.path) != nil)

        let roh = try Data(contentsOf: Ablage(ordner: ablage).datei)
        #expect(Tresor.istBehaelter(roh))
        #expect(try Tresor.kopfLesen(roh).kennung == tresor.kennung)
        // Der Haken kam vor dem Wechsel noch an.
        #expect(s.planung?.eintraege.first { $0.id == "e-1" }?.kommentar == "vom iPad")
        // Die Kopie liegt sofort, nicht erst beim Beenden.
        let kopie = ziel.appending(component: s.autoexportDateiname)
        #expect(Tresor.istBehaelter(try Data(contentsOf: kopie)))
        // Die Statusdatei ist jetzt ein Behälter unter dem eigenen Schlüssel, Inhalt unverändert.
        let statusRoh = try Data(contentsOf: statusdatei(ziel))
        #expect(Tresor.istBehaelter(statusRoh))
        #expect(try Statusdatei.lesen(try tresor.oeffnen(statusRoh)) == stand)
        // Und sie wird wieder gelesen — als Behälter.
        s.statusUebernehmen()
        #expect(!s.meldungen.contains { $0.text.contains("unverschlüsselt") })
        // Die Sicherung hält den Stand der Platte: kein zweites Schreiben nötig.
        #expect(s.sicherung.gesicherterStand == s.planung?.geaendert && !s.sicherungLiegtStill)

        let meldung = try #require(s.meldungen.first { $0.text.contains("eingeschaltet") })
        #expect(meldung.art == .hinweis && !meldung.text.contains("Offen"))
        #expect(meldung.text.contains("Kopie außer Haus") && meldung.text.contains("Statusdatei"))
        #expect(meldung.text.contains("die Lesezeichen mit ihr"))
    }

    @Test("Einschalten ohne Schreibrecht: kein Zwilling, keine Marke — die Sitzung bleibt Klartext, keine Kopie")
    func einschaltenScheitert() throws {
        let ablage = try ordner("ablage-zu")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ablage.path)
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        s.jetztSichern()
        let vorher = try Data(contentsOf: Ablage(ordner: ablage).datei)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ablage.path)

        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        guard case .zurueckgenommen = ergebnis.ablage else {
            Issue.record("erwartet: zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(s.tresor == nil && s.verschluesselungsstand == .aus)
        #expect(try Data(contentsOf: Ablage(ordner: ablage).datei) == vorher, "die Platte trägt den alten Stand")
        #expect(try FileManager.default.contentsOfDirectory(atPath: ziel.path).isEmpty, "keine Kopie ohne Ablage")
        #expect(s.zugriff.quelle == .einstellungen && s.autoexportOrdner == ziel.path,
                "die Lesezeichen bleiben, wo sie waren")
        #expect(!FileManager.default.fileExists(atPath: Ablage(ordner: ablage).lesezeichen.path))
        try einStand(ablage)
        let meldung = try #require(s.meldungen.last)
        #expect(meldung.art == .warnung && meldung.text.contains("nicht eingeschaltet"))
        // Der Systemtext steht in der Klammer, ohne seinen Schlusspunkt — ein Satz.
        #expect(meldung.text.contains(": die Generation ließ sich nicht anlegen ("), "\(meldung.text)")
        #expect(!meldung.text.contains(".."), "\(meldung.text)")
    }

    @Test("Erneuern: Statusdatei und Kopie wandern sofort unter den neuen Schlüssel")
    func erneuern() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        s.verschluesselungEinschalten()
        let alter = try #require(s.tresor)
        let stand = status("unter dem alten Schlüssel")
        try alter.versiegeln(try Statusdatei.schreiben(stand), inhalt: .status, ziel: .kopie)
            .write(to: statusdatei(ziel), options: [.atomic])

        _ = try s.schluesselErneuernVorbereiten(alt: passphrase, neu: neue)
        let ergebnis = s.verschluesselungEinschalten()
        let neuer = try #require(s.tresor)
        #expect(neuer.kennung != alter.kennung)
        #expect(ergebnis.ablage == .geschrieben && ergebnis.kopie == .erledigt && ergebnis.statusdatei == .erledigt)
        #expect(ergebnis.lesezeichen == .erledigt)
        try einStand(ablage)
        let lesezeichen = try Tresor.kopfLesen(try Data(contentsOf: Ablage(ordner: ablage).lesezeichen))
        #expect(lesezeichen.kennung == neuer.kennung, "der Behälter der Lesezeichen wandert mit")
        #expect(throws: Tresorfehler.self, "die alte Passphrase öffnet nichts mehr") {
            try Tresor.oeffnen(kopf: lesezeichen, passphrase: passphrase)
        }
        #expect(try Tresor.oeffnen(kopf: lesezeichen, passphrase: neue).kennung == neuer.kennung)
        #expect(s.autoexportOrdner == ziel.path)
        #expect(s.planung?.eintraege.first { $0.id == "e-1" }?.kommentar == "unter dem alten Schlüssel",
                "erst übernommen, dann gewechselt")

        let statusRoh = try Data(contentsOf: statusdatei(ziel))
        #expect(try Tresor.kopfLesen(statusRoh).kennung == neuer.kennung)
        #expect(try Statusdatei.lesen(try neuer.oeffnen(statusRoh)) == stand)
        let kopie = ziel.appending(component: s.autoexportDateiname)
        #expect(try Tresor.kopfLesen(try Data(contentsOf: kopie)).kennung == neuer.kennung)
        let vorige = try #require(Ablage(ordner: ablage).vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse))
        #expect(try Tresor.kopfLesen(vorige).kennung == neuer.kennung, "die Vorgängerfassung ebenfalls")
        #expect(try Planungsdatei.lesen(try neuer.oeffnen(vorige)).titel == "Übergang", "sie trägt den Stand vor dem Übergang")
        #expect(s.meldungen.last?.text.contains("Schlüssel erneuert") == true)
    }

    @Test("Erneuern mit einem Ordner an der Stelle der Lesezeichen: zurückgenommen vor der Marke, nichts hat sich geändert")
    func erneuernScheitertAmBehaelter() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        let material = try ordner("material")
        defer { for o in [ablage, ziel, material] { try? FileManager.default.removeItem(at: o) } }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        s.verschluesselungEinschalten()
        let alter = try #require(s.tresor)
        let behaelter = Ablage(ordner: ablage).lesezeichen
        #expect(try Tresor.kopfLesen(try Data(contentsOf: behaelter)).kennung == alter.kennung)
        // Ein Ordner an der Stelle des Behälters: Die Generation entsteht nicht.
        try FileManager.default.removeItem(at: behaelter)
        try FileManager.default.createDirectory(at: behaelter, withIntermediateDirectories: true)

        _ = try s.schluesselErneuernVorbereiten(alt: passphrase, neu: neue)
        let ergebnis = s.verschluesselungEinschalten()
        guard case .zurueckgenommen(let grund) = ergebnis.ablage else {
            Issue.record("erwartet: zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(grund.contains("lesezeichen.json") && grund.contains("Ordner"), "\(grund)")
        #expect(s.tresor?.kennung == alter.kennung, "die Sitzung bleibt auf dem alten Schlüssel")
        #expect(s.zugriff.quelle == .behaelter && s.zugriff.ungesichert == nil, "der Vorrat gilt, nichts hat sich geändert")
        #expect(try Tresor.kopfLesen(try Data(contentsOf: Ablage(ordner: ablage).datei)).kennung == alter.kennung)
        let namen = try FileManager.default.contentsOfDirectory(atPath: ablage.path)
        #expect(!namen.contains { $0.hasSuffix(Uebergangsdienst.zwillingssuffix) || $0 == Uebergangsdienst.markenname })

        // Hindernis weg, ein Ort gemerkt: Der Behälter trägt den Schlüssel der Sitzung — nicht den abgewiesenen.
        try FileManager.default.removeItem(at: behaelter)
        try s.zugriff.merken(material)
        #expect(s.zugriff.ungesichert == nil)
        #expect(try Tresor.kopfLesen(try Data(contentsOf: behaelter)).kennung == alter.kennung,
                "der Behälter liegt unter dem geltenden Schlüssel")
        // Der nächste Start öffnet ihn, statt ihn beiseitezulegen.
        s.zugriff.schliessen()
        guard case .geoeffnet = s.zugriff.oeffnen(mit: alter, stempel: "s") else {
            Issue.record("erwartet: geöffnet")
            return
        }
        #expect(s.zugriff.zustaendig(fuer: material.path) != nil && s.zugriff.zielordner == ziel.path)
    }

    @Test("Erneuern mit unveränderbarer Ablage: zurückgenommen vor der Marke — Ablage und Lesezeichen beim alten Schlüssel")
    func erneuernScheitertAnDerAblage() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        let datei = Ablage(ordner: ablage).datei
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: datei.path)
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        s.verschluesselungEinschalten()
        let alter = try #require(s.tresor)
        let behaelter = Ablage(ordner: ablage).lesezeichen
        // Die Ablage unveränderbar: Sie ließe sich nach der Marke nicht ersetzen — also keine Marke.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: datei.path)

        _ = try s.schluesselErneuernVorbereiten(alt: passphrase, neu: neue)
        let ergebnis = s.verschluesselungEinschalten()
        guard case .zurueckgenommen(let grund) = ergebnis.ablage else {
            Issue.record("erwartet: zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(grund.contains("planung.json") && grund.contains("nicht ersetzen"), "\(grund)")
        #expect(s.tresor?.kennung == alter.kennung)
        #expect(try Tresor.kopfLesen(try Data(contentsOf: behaelter)).kennung == alter.kennung,
                "der Behälter blieb, wie er war")
        #expect(s.zugriff.ungesichert == nil && ergebnis.lesezeichen == .nichtNoetig)
        try einStand(ablage)
        let meldung = try #require(s.meldungen.last)
        #expect(meldung.text.contains("Schlüssel nicht erneuert") && !meldung.text.contains("Lesezeichen:"), "\(meldung.text)")
    }

    @Test("Passphrase ändern: Kopie, Lesezeichen, Vorgängerfassung und Statusdatei tragen die neue Wicklung sofort")
    func passphraseAendern() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        s.verschluesselungEinschalten()
        let tresor = try #require(s.tresor)
        try tresor.versiegeln(try Statusdatei.schreiben(status("bleibt")), inhalt: .status, ziel: .kopie)
            .write(to: statusdatei(ziel), options: [.atomic])
        let kopie = ziel.appending(component: s.autoexportDateiname)

        let lesezeichenVorher = try Data(contentsOf: Ablage(ordner: ablage).lesezeichen)
        let ergebnis = try s.passphraseAendern(alt: passphrase, neu: neue)
        #expect(ergebnis.ablage == .geschrieben && ergebnis.kopie == .erledigt)
        #expect(ergebnis.lesezeichen == .erledigt && ergebnis.statusdatei == .erledigt)
        try einStand(ablage)
        #expect(try Data(contentsOf: Ablage(ordner: ablage).lesezeichen) != lesezeichenVorher,
                "derselbe Datenschlüssel, aber die neue Hülle")
        let dateien = [Ablage(ordner: ablage).datei, Ablage(ordner: ablage).vorherigeFassung,
                       Ablage(ordner: ablage).lesezeichen, kopie, statusdatei(ziel)]
        try oeffnenNurMit(neue, nicht: passphrase, dateien, kennung: tresor.kennung)
        #expect(s.meldungen.last?.text.contains("Passphrase geändert") == true)
    }

    @Test("Zielordner nicht erreichbar: die Ablage ist versiegelt, Kopie und Statusdatei stehen als offen in der Meldung")
    func zielordnerFehlt() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        s.autoexportOrdner = ziel.appending(component: "weg").path

        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        #expect(ergebnis.ablage == .geschrieben)
        #expect(ergebnis.kopie == .offen("Zielordner nicht erreichbar"))
        #expect(ergebnis.statusdatei == .offen("Zielordner nicht erreichbar"))
        #expect(s.tresor != nil)
        let meldung = try #require(s.meldungen.last)
        #expect(meldung.art == .warnung && meldung.text.contains("Offen:") && meldung.text.contains("Kopie außer Haus"))
    }

    @Test("Aufheben: die Ablage liegt wieder im Klartext, der Behälter der Lesezeichen ist fort, die Statusdatei bleibt, wie sie ist")
    func aufheben() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        s.verschluesselungEinschalten()
        let tresor = try #require(s.tresor)
        try tresor.versiegeln(try Statusdatei.schreiben(status("bleibt")), inhalt: .status, ziel: .kopie)
            .write(to: statusdatei(ziel), options: [.atomic])
        let statusVorher = try Data(contentsOf: statusdatei(ziel))

        let lesezeichenVorher = s.zugriff.eintraege
        let ergebnis = s.verschluesselungAufheben()
        #expect(ergebnis.ablage == .geschrieben && ergebnis.lesezeichen == .erledigt)
        #expect(s.tresor == nil && !s.autoexportAktiv)
        #expect(!Tresor.istBehaelter(try Data(contentsOf: Ablage(ordner: ablage).datei)))
        let vorige = try #require(Ablage(ordner: ablage).vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse))
        #expect(!Tresor.istBehaelter(vorige), "die Vorgängerfassung ebenfalls im Klartext")
        #expect(try Data(contentsOf: statusdatei(ziel)) == statusVorher)
        try einStand(ablage)
        // Die Lesezeichen sind zurück in den Einstellungen, der Behälter ist weg.
        #expect(s.zugriff.quelle == .einstellungen && s.zugriff.eintraege == lesezeichenVorher)
        #expect(s.autoexportOrdner == ziel.path)
        #expect(!FileManager.default.fileExists(atPath: Ablage(ordner: ablage).lesezeichen.path))
        #expect(s.meldungen.last?.text.contains("Lesezeichen wieder in den Einstellungen") == true)
    }

    // ── Über der Schreibgrenze: kein Übergang beginnt ────────────────────

    @Test("Über der Schreibgrenze beginnt kein Übergang: der Grund steht im Blatt, die Platte bleibt, wie sie ist")
    func schreibgrenzeEinschalten() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        s.jetztSichern()
        let vorher = try Data(contentsOf: Ablage(ordner: ablage).datei)
        s.planung = try riesenplanung()
        s.jetztSichern()
        guard case .zuGross = s.sicherung.stoerung else {
            Issue.record("erwartet: Störung zu groß, war \(String(describing: s.sicherung.stoerung))")
            return
        }
        let grund = try #require(s.schutzuebergangGesperrt)
        #expect(grund.contains("über der Schreibgrenze von 32 MB"), "\(grund)")

        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        #expect(ergebnis.ablage == .zurueckgenommen(grund))
        #expect(s.tresor == nil && s.verschluesselungsstand == .aus)
        #expect(try Data(contentsOf: Ablage(ordner: ablage).datei) == vorher, "die Platte trägt den alten Stand")
        #expect(s.zugriff.quelle == .einstellungen)
        #expect(!FileManager.default.fileExists(atPath: Ablage(ordner: ablage).lesezeichen.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: ziel.path).isEmpty, "keine Kopie")
        let warnungen = s.meldungen.filter { $0.art == .warnung }
        #expect(warnungen.count(where: { $0.text.contains("zugleich die Lesegrenze") }) == 1, "der lange Satz einmal")
        let letzte = try #require(warnungen.last?.text)
        #expect(letzte.hasPrefix("Verschlüsselung nicht eingeschaltet: die Planung ist mit"), "\(letzte)")
        #expect(letzte.contains("Schreibgrenze") && !letzte.contains("zugleich die Lesegrenze"), "\(letzte)")

        // Gekürzt: Die Sicherung schreibt, der Übergang steht wieder offen.
        s.planung?.eintraege.removeAll()
        Thread.sleep(forTimeInterval: 0.003)
        s.planung?.geaendert = Zeitrechnung.jetztAlsZeitstempel()
        s.jetztSichern()
        #expect(s.schutzuebergangGesperrt == nil)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().ablage == .geschrieben)
    }

    @Test("Bei stehender Größensperre: Passphrase ändern wird abgewiesen, die Touch-ID-Wicklung nicht angelegt")
    func schreibgrenzeVerwalten() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        s.verschluesselungEinschalten()
        let tresor = try #require(s.tresor)
        try tresor.versiegeln(try Statusdatei.schreiben(status("bleibt")), inhalt: .status, ziel: .kopie)
            .write(to: statusdatei(ziel), options: [.atomic])
        let dateien = [Ablage(ordner: ablage).datei, Ablage(ordner: ablage).lesezeichen,
                       ziel.appending(component: s.autoexportDateiname), statusdatei(ziel)]

        s.planung = try riesenplanung()
        s.jetztSichern()
        let grund = try #require(s.schutzuebergangGesperrt)
        let ergebnis = try s.passphraseAendern(alt: passphrase, neu: neue)
        #expect(ergebnis.ablage == .zurueckgenommen(grund))
        #expect(tresor.passphraseStimmt(passphrase) && !tresor.passphraseStimmt(neue), "die Sitzung behält die alte Wicklung")
        try oeffnenNurMit(passphrase, nicht: neue, dateien, kennung: tresor.kennung)
        #expect(s.meldungen.last?.text.hasPrefix("Passphrase nicht geändert: die Planung ist mit") == true)

        s.enklaveImPruefstandAnlegen = true
        s.enklaveAufDiesemMac(true)
        #expect(!s.enklaveEingerichtet && !tresor.hat(Wicklung.enklave))
        #expect(s.meldungen.last?.text.contains("wird nicht angelegt") == true)
        #expect(try Tresor.kopfLesen(try Data(contentsOf: Ablage(ordner: ablage).datei)).wicklung(Wicklung.enklave) == nil)
        #expect(s.verschluesselungAufheben().ablage == .zurueckgenommen(grund))
        #expect(s.tresor === tresor, "die Sitzung bleibt versiegelt")
    }

    // ── Schreibfehler: die neue Hülle gilt erst mit der Marke ─────────────

    @Test("Passphrase ändern ohne Schreibrecht: zurückgenommen, die bisherige öffnet weiter — mit Schreibrecht gelingt es")
    func passphraseAendernScheitert() throws {
        let ablage = try ordner("ablage-zu")
        let ziel = try ordner("ziel")
        defer {
            try? schreibrecht(ablage, true)
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        s.verschluesselungEinschalten()
        let tresor = try #require(s.tresor)
        try tresor.versiegeln(try Statusdatei.schreiben(status("bleibt")), inhalt: .status, ziel: .kopie)
            .write(to: statusdatei(ziel), options: [.atomic])
        let dateien = [Ablage(ordner: ablage).datei, Ablage(ordner: ablage).lesezeichen,
                       ziel.appending(component: s.autoexportDateiname), statusdatei(ziel)]

        try schreibrecht(ablage, false)
        let ergebnis = try s.passphraseAendern(alt: passphrase, neu: neue)
        guard case .zurueckgenommen = ergebnis.ablage else {
            Issue.record("erwartet: zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(tresor.passphraseStimmt(passphrase) && !tresor.passphraseStimmt(neue))
        try oeffnenNurMit(passphrase, nicht: neue, dateien, kennung: tresor.kennung)
        let abgewiesen = try #require(s.meldungen.last?.text)
        #expect(abgewiesen.hasPrefix("Passphrase nicht geändert: die Generation ließ sich nicht anlegen ("), "\(abgewiesen)")
        #expect(!abgewiesen.contains(".."), "\(abgewiesen)")

        try schreibrecht(ablage, true)
        #expect(try s.passphraseAendern(alt: passphrase, neu: neue).ablage == .geschrieben)
        #expect(tresor.passphraseStimmt(neue))
        try oeffnenNurMit(neue, nicht: passphrase, dateien, kennung: tresor.kennung)
        try einStand(ablage)
    }

    @Test("Touch-ID-Wicklung ohne Schreibrecht: die Sitzung nimmt sie zurück; der Rückweg lässt sie stehen")
    func enklaveScheitert() throws {
        let ablage = try ordner("ablage-zu")
        let ziel = try ordner("ziel")
        defer {
            try? schreibrecht(ablage, true)
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        s.verschluesselungEinschalten()
        let tresor = try #require(s.tresor)
        func aufDerPlatte() throws -> Wicklung? {
            try Tresor.kopfLesen(try Data(contentsOf: Ablage(ordner: ablage).datei)).wicklung(Wicklung.enklave)
        }
        s.enklaveImPruefstandAnlegen = true

        try schreibrecht(ablage, false)
        s.enklaveAufDiesemMac(true)
        #expect(!s.enklaveEingerichtet && !tresor.hat(Wicklung.enklave))
        let abgewiesen = try #require(s.meldungen.last?.text)
        #expect(abgewiesen.contains("wird nicht angelegt: die Generation ließ sich nicht anlegen (") && !abgewiesen.contains(".."), "\(abgewiesen)")
        #expect(try aufDerPlatte() == nil)

        try schreibrecht(ablage, true)
        s.enklaveAufDiesemMac(true)
        #expect(s.enklaveEingerichtet && tresor.hat(Wicklung.enklave))
        #expect(try aufDerPlatte() != nil)
        // Auch die Vorgängerfassung und die Lesezeichen tragen die Wicklung jetzt.
        for datei in [Ablage(ordner: ablage).vorherigeFassung, Ablage(ordner: ablage).lesezeichen] {
            #expect(try Tresor.kopfLesen(try Data(contentsOf: datei)).wicklung(Wicklung.enklave) != nil, "\(datei.lastPathComponent)")
        }
        try einStand(ablage)

        try schreibrecht(ablage, false)
        s.enklaveAufDiesemMac(false)
        #expect(s.enklaveEingerichtet && tresor.hat(Wicklung.enklave), "ohne Schreibrecht bleibt die Wicklung")
        #expect(s.meldungen.last?.text.contains("bleibt") == true)
        try schreibrecht(ablage, true)
        #expect(try aufDerPlatte() != nil)
        s.enklaveAufDiesemMac(false)
        #expect(!s.enklaveEingerichtet)
        #expect(try aufDerPlatte() == nil)
    }

    @Test("Ersteinrichtung über der Schreibgrenze: das Einschalten wird zurückgenommen, die Frage steht wieder")
    func ersteinrichtungSchreibgrenze() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        s.jetztSichern()
        s.planung = try riesenplanung()
        s.jetztSichern()
        let grund = try #require(s.schutzuebergangGesperrt)

        s.ersteinrichtungOeffnen()
        #expect(s.ersteinrichtungsschritt == .verschluesselung)
        s.ersteinrichtungEinrichten()
        try s.ersteinrichtungWeiter(passphrase: passphrase)
        guard case .blatt = s.ersteinrichtungsschritt else {
            Issue.record("erwartet: Blatt, war \(s.ersteinrichtungsschritt)")
            return
        }
        let ergebnis = s.ersteinrichtungEinschalten()
        #expect(ergebnis.ablage == .zurueckgenommen(grund))
        #expect(s.ersteinrichtungsschritt == .verschluesselung, "zurück zur Frage, nicht weiter zur Kopie")
        #expect(s.tresor == nil && s.verschluesselungsstand == .aus)
        #expect(!Tresor.istBehaelter(try Data(contentsOf: Ablage(ordner: ablage).datei)))

        // Gekürzt: die Einrichtung geht durch.
        s.planung?.eintraege.removeAll()
        Thread.sleep(forTimeInterval: 0.003)
        s.planung?.geaendert = Zeitrechnung.jetztAlsZeitstempel()
        s.jetztSichern()
        s.ersteinrichtungEinrichten()
        try s.ersteinrichtungWeiter(passphrase: passphrase)
        #expect(s.ersteinrichtungEinschalten().ablage == .geschrieben)
        #expect(s.ersteinrichtungsschritt == .sicherung && s.tresor != nil)
    }

    /// Ein Ordner an der Stelle der Ablage: Die Generation entsteht nicht —
    /// zurückgenommen vor der Marke, der Grund ein Satz ohne Klammer in der Klammer.
    private func ablageVerbauen(_ ablage: URL) throws {
        let datei = Ablage(ordner: ablage).datei
        try? FileManager.default.removeItem(at: datei)
        try FileManager.default.createDirectory(at: datei, withIntermediateDirectories: true)
    }

    @Test("Ein Ordner an der Stelle der Ablage beim Einschalten: zurückgenommen, der Grund nennt die Datei")
    func ablageVerbautEinschalten() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        try ablageVerbauen(ablage)

        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        guard case .zurueckgenommen(let grund) = ergebnis.ablage else {
            Issue.record("erwartet: zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(grund.hasPrefix("die Generation ließ sich nicht anlegen (an der Stelle von „planung.json“ liegt ein Ordner)"), "\(grund)")
        #expect(s.tresor == nil)
        let meldung = try #require(s.meldungen.last?.text)
        #expect(meldung.hasPrefix("Verschlüsselung nicht eingeschaltet: die Generation ließ sich nicht anlegen ("), "\(meldung)")
        #expect(!meldung.contains("((") && !meldung.contains(".."), "\(meldung)")
    }

    @Test("Ein Ordner an der Stelle der Ablage beim Aufheben: zurückgenommen, die Sitzung bleibt versiegelt")
    func ablageVerbautAufheben() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().ablage == .geschrieben)
        let tresor = try #require(s.tresor)
        try ablageVerbauen(ablage)

        let ergebnis = s.verschluesselungAufheben()
        guard case .zurueckgenommen(let grund) = ergebnis.ablage else {
            Issue.record("erwartet: zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(grund.contains("planung.json") && grund.contains("Ordner"), "\(grund)")
        #expect(s.tresor === tresor && s.zugriff.quelle == .behaelter)
        let meldung = try #require(s.meldungen.last?.text)
        #expect(meldung.hasPrefix("Verschlüsselung nicht aufgehoben: die Generation ließ sich nicht anlegen ("), "\(meldung)")
        #expect(!meldung.contains("((") && !meldung.contains(".."), "\(meldung)")
    }

    @Test("Eine Vorschau schreibt nicht — der Übergang gilt nur für die Sitzung")
    func vorschau() throws {
        let s = Planungsspeicher(vorschau: try planung())
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        #expect(ergebnis.ablage == .vorschau && s.tresor != nil)
        #expect(ergebnis.lesezeichen == .nichtNoetig && s.zugriff.quelle == .einstellungen)
        #expect(s.meldungen.last?.art == .hinweis)
    }

    // ── Jeder Abbruch nach jedem Schritt: der nächste Start findet einen Stand ──
    // Das Abnahmekriterium zu F03: Kein Ende des Prozesses lässt zwei
    // Schutzstände nebeneinander; Lesezeichen und Sitzpläne öffnen, nichts
    // wird beiseitegelegt. Der Haken des Dienstes hält den Ordner nach jedem
    // Schritt fest, wie ein Abbruch ihn hinterließe — ein zweiter Speicher
    // startet darauf.

    enum Uebergangsprobe: CaseIterable {
        case einschalten, erneuern, passphrase, wicklung, aufheben
    }

    /// Ein eingeschalteter Speicher mit Lesezeichen, Zielordner, Sitzplan,
    /// Vorgängerfassung — oder im Klartext für das Einschalten.
    @Test("Eine Bewahrungskopie, die erst im Übergang gelingt, gehört zur Generation — nicht als Klartext daneben (N51-03)")
    func bewahrungskopieImUebergang() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? schreibrecht(ablage, true)
            for o in [ablage, ziel] { try? FileManager.default.removeItem(at: o) }
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        s.jetztSichern()
        let klasse = try #require(s.planung?.klassen.first?.id)
        // Eine Datei, die das Lesen mit Verlust bereinigt: ein zweiter Plan ohne Tischliste.
        let roh = #"{"typ":"\#(Sitzplandatei.typ)","version":\#(Sitzplandatei.version),"plaene":{"\#(klasse)":{"tische":[]},"k-zwei":{"tische":7}}}"#
        try Data(roh.utf8).write(to: Ablage(ordner: ablage).sitzplaene, options: [.atomic])
        // Beim Laden scheitert die Kopie des Originals (Ordner ohne Schreibrecht).
        try schreibrecht(ablage, false)
        s.sitzplaeneLaden()
        let ausstehend = try #require(s.sitzplaene.ausstehendeKopie)
        #expect(ausstehend.hasPrefix("sitzplaene-bereinigt-") && s.sitzplaene.plan(fuer: klasse) != nil)
        try schreibrecht(ablage, true)

        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        let ergebnis = s.verschluesselungEinschalten()
        #expect(ergebnis.ablage == .geschrieben && ergebnis.offenes.isEmpty, "\(ergebnis)")
        #expect(s.sitzplaene.ausstehendeKopie == nil, "im Übergang nachgeholt")
        #expect(ergebnis.nebendateien.umgestellt.contains(ausstehend), "\(ergebnis.nebendateien.umgestellt)")
        let tresor = try #require(s.tresor)
        let kopie = try Data(contentsOf: ablage.appending(component: ausstehend))
        #expect(Tresor.istBehaelter(kopie), "die Kopie trägt den neuen Schutz")
        let kopfDerKopie = try Tresor.kopfLesen(kopie)
        #expect(kopfDerKopie.kennung == tresor.kennung, "unter dem neuen Schlüssel")
        let bewahrt = try tresor.oeffnen(kopie)
        #expect(bewahrt == Data(roh.utf8), "und bewahrt das Original")
        try einStand(ablage)
    }

    @Test("Klartext-Sitzpläne beim Entsperren: das Angleichen der Wicklung wartet auf die Antwort — nichts wird vorher versiegelt (F04)",
          arguments: [false, true])
    func klartextfrageVorDerWicklung(_ versiegeln: Bool) async throws {
        guard Tresor.enklaveVorhanden else { return }
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer { for o in [ablage, ziel] { try? FileManager.default.removeItem(at: o) } }
        let s = try speicher(ablage: ablage, ziel: ziel)
        s.jetztSichern()
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        s.enklaveImPruefstandAnlegen = true
        s.enklaveAufDiesemMac(true)
        #expect(s.enklaveEingerichtet)
        let klasse = try #require(s.planung?.klassen.first?.id)
        // Klartext-Sitzpläne fremder Hand neben der versiegelten Planung.
        let klartext = try Sitzplandatei.schreiben([klasse: Sitzplan.anordnen(klasseId: klasse, namen: ["Amira", "Ben"])])
        try klartext.write(to: Ablage(ordner: ablage).sitzplaene, options: [.atomic])

        // Entsperren per Passphrase ohne Häkchen: Die Wicklung dieses Macs soll fallen.
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablage))
        zweiter.starten()
        zweiter.enklaveMerken = false
        await zweiter.entsperren(passphrase: passphrase)
        #expect(zweiter.verschluesselungsstand == .an)
        let frage = try #require(zweiter.rueckfrage)
        #expect(frage.text.contains("im Klartext") && zweiter.sitzplaene.klartextUnbestaetigt)
        // Vor der Antwort: die Datei unangetastet, kein Übergang, die Wicklung noch da.
        #expect(try Data(contentsOf: Ablage(ordner: ablage).sitzplaene) == klartext)
        try einStand(ablage)
        let tresor = try #require(zweiter.tresor)
        #expect(tresor.hat(Wicklung.enklave) && zweiter.enklaveEingerichtet)
        #expect(try Tresor.kopfLesen(try Data(contentsOf: Ablage(ordner: ablage).datei)).wicklung(Wicklung.enklave) != nil)

        zweiter.rueckfrageBeantworten(versiegeln)
        #expect(!zweiter.sitzplaene.klartextUnbestaetigt && zweiter.rueckfrage == nil)
        let namen = try FileManager.default.contentsOfDirectory(atPath: ablage.path)
        if versiegeln {
            #expect(Tresor.istBehaelter(try Data(contentsOf: Ablage(ordner: ablage).sitzplaene)))
            #expect(!namen.contains { $0.hasPrefix("sitzplaene-unerwartet-") })
            #expect(zweiter.sitzplan(fuer: klasse)?.tische.count == 2)
        } else {
            // Beiseitegelegt — als Rettungskopie im Register, die der Übergang
            // gleich mit unter den Schlüssel nimmt; ihr Inhalt ist das Original.
            let kopie = try #require(namen.first { $0.hasPrefix("sitzplaene-unerwartet-") })
            let daten = try Data(contentsOf: ablage.appending(component: kopie))
            #expect(Tresor.istBehaelter(daten), "die Rettungskopie geht mit unter den Schlüssel")
            let bewahrt = try tresor.oeffnen(daten)
            #expect(bewahrt == klartext, "die Kopie ist das Original")
            #expect(!FileManager.default.fileExists(atPath: Ablage(ordner: ablage).sitzplaene.path))
            #expect(zweiter.sitzplan(fuer: klasse) == nil)
        }
        // Erst jetzt fällt die Wicklung — als Übergang in einem Stand.
        #expect(!tresor.hat(Wicklung.enklave) && !zweiter.enklaveEingerichtet)
        #expect(try Tresor.kopfLesen(try Data(contentsOf: Ablage(ordner: ablage).datei)).wicklung(Wicklung.enklave) == nil)
        #expect(zweiter.meldungen.contains { $0.text.contains("Wicklung dieses Macs ist entfernt") }, "\(zweiter.meldungen.map(\.text))")
        try einStand(ablage)
    }

    private func vorbereiteterSpeicher(_ probe: Uebergangsprobe, ablage: URL, ziel: URL, material: URL) throws -> Planungsspeicher {
        let s = try speicher(ablage: ablage, ziel: ziel)
        s.jetztSichern()
        try s.zugriff.merken(material)
        s.sitzplaeneLaden()
        let klasse = try #require(s.planung?.klassen.first?.id)
        #expect(s.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse, namen: ["Amira", "Ben", "Clara"])) == nil)
        s.titelSetzen("Übergang, zweiter Stand")
        s.jetztSichern()
        guard probe != .einschalten else { return s }
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        return s
    }

    /// Den Übergang der Probe auslösen.
    private func ausloesen(_ probe: Uebergangsprobe, _ s: Planungsspeicher) throws -> Planungsspeicher.Schutzergebnis {
        switch probe {
        case .einschalten:
            _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
            return s.verschluesselungEinschalten()
        case .erneuern:
            _ = try s.schluesselErneuernVorbereiten(alt: passphrase, neu: neue)
            return s.verschluesselungEinschalten()
        case .passphrase:
            return try s.passphraseAendern(alt: passphrase, neu: neue)
        case .wicklung:
            s.enklaveImPruefstandAnlegen = true
            s.enklaveAufDiesemMac(true)
            return Planungsspeicher.Schutzergebnis(ablage: s.enklaveEingerichtet ? .geschrieben : .zurueckgenommen("Wicklung nicht angelegt"))
        case .aufheben:
            return s.verschluesselungAufheben()
        }
    }


    /// Eine Datei unveränderbar machen und wieder freigeben — anders als der
    /// Entzug des Schreibrechts am Ordner trifft das genau einen Eintrag: Der
    /// Übergang bleibt offen, und der Ordner bleibt beschreibbar. Nur so lässt
    /// sich zeigen, dass die Ablage am Tor scheitert und nicht am Recht.
    private func unveraenderbar(_ datei: URL, _ an: Bool) {
        _ = datei.withUnsafeFileSystemRepresentation { pfad in
            chflags(pfad, an ? UInt32(UF_IMMUTABLE) : 0)
        }
    }

    @Test("Offener Übergang: auch abseits des Hauptstrangs ändert die Ablage nichts — Nebendateien, Beiseitelegen, Rettungskopien (N52-03, B25, E62)")
    func nebenwegeAmOffenenUebergang() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        let material = try ordner("material")
        let sitzplaene = Ablage(ordner: ablage).sitzplaene
        defer {
            unveraenderbar(sitzplaene, false)
            for o in [ablage, ziel, material] { try? FileManager.default.removeItem(at: o) }
        }
        let s = try vorbereiteterSpeicher(.erneuern, ablage: ablage, ziel: ziel, material: material)
        // Nach der Marke wird die Sitzplandatei unveränderbar: Ihr Tausch
        // scheitert, der Übergang bleibt übergeben und nicht eingesetzt.
        s.sicherung.uebergang.haken = { [self] schritt in
            if schritt == .uebergeben { unveraenderbar(sitzplaene, true) }
        }
        _ = try s.schluesselErneuernVorbereiten(alt: passphrase, neu: neue)
        _ = s.verschluesselungEinschalten()
        #expect(s.sicherung.uebergang.istUebergeben, "der Übergang ist offen")
        #expect(s.sicherung.liegtStill)

        let verwaltung = FileManager.default
        let namen = try verwaltung.contentsOfDirectory(atPath: ablage.path).sorted()
        let abdruck = try namen.map { try Data(contentsOf: ablage.appending(component: $0)) }

        // Die Wege, die bisher am Tor vorbeischrieben.
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Ein dritter Satz, den man behält", runden: Tresor.rundenMindestens)
        let bilanz = s.sicherung.altbestaendeVersiegeln(mit: fremder)
        #expect(bilanz.umgestellt.isEmpty && !bilanz.vollstaendig, "keine Nebendatei angefasst")
        #expect(bilanz.uebrig.map(\.name) == [ablage.lastPathComponent], "der Grund hängt am Ordner, nicht an einer Datei")
        #expect(!s.sicherung.ablage.beschaedigtenStandBeiseitelegen(stempel: "probe"), "nichts beiseitegelegt")
        #expect(s.sicherung.ablage.sitzplaeneKopieren(als: "sitzplaene-bereinigt-probe.json") == nil, "keine Rettungskopie")

        #expect(try verwaltung.contentsOfDirectory(atPath: ablage.path).sorted() == namen, "kein Name kam dazu")
        #expect(try namen.map { try Data(contentsOf: ablage.appending(component: $0)) } == abdruck,
                "keine Datei wurde geändert")

        // Freigegeben: Derselbe Weg holt zuerst das Einsetzen nach und arbeitet dann.
        unveraenderbar(sitzplaene, false)
        let nachher = s.sicherung.altbestaendeVersiegeln(mit: fremder)
        #expect(!s.sicherung.uebergang.istUebergeben && s.sicherung.uebergang.laufend == nil,
                "das Einsetzen wurde nachgeholt")
        #expect(nachher.uebrig.first?.name != ablage.lastPathComponent,
                "der Grund ist nicht mehr das Tor, sondern der fremde Schlüssel je Datei")
        #expect(!s.sicherung.liegtStill, Comment(rawValue: s.sicherung.stillgrund))
        try einStand(ablage)
    }


    // ── Die Lage der Ablage (Phase O) ─────────────────────────────────────

    /// Ein Ordner, in dem ein Übergang nach der Marke stecken blieb und die
    /// Marke danach unbrauchbar wurde: `planung.json` trägt den neuen Stand
    /// und hat ihren Vorgänger, die übrigen Zwillinge warten.
    private func blockierenderOrdner(_ ablage: URL) throws {
        try Data("{\"typ\":\"unterrichtsplanung\",\"version\":2,\"titel\":\"alt\"}".utf8)
            .write(to: ablage.appending(component: "planung.json"))
        try Data("alt".utf8).write(to: ablage.appending(component: "sitzplaene.json"))
        let dienst = Uebergangsdienst(ordner: ablage)
        #expect(dienst.vorbereiten(.erneuern, kennung: Data([3]), stempel: "s",
                                   dateien: ["planung.json": .daten(Data("neu-planung".utf8)),
                                             "sitzplaene.json": .daten(Data("neu-sitzplaene".utf8))]) == nil)
        #expect(dienst.uebergeben() == nil)
        _ = try FileManager.default.replaceItemAt(ablage.appending(component: "planung.json"),
                                                  withItemAt: ablage.appending(component: "planung.json.uebergang"),
                                                  backupItemName: "planung.json.vorgaenger",
                                                  options: [.withoutDeletingBackupItem])
        // Weder Marke noch Zweitschrift lassen sich noch deuten (E68).
        for name in [Uebergangsdienst.markenname, Uebergangsdienst.zweitschriftname] {
            try Data("{\"typ\":\"unterrichtsplanung-uebergang\",\"version\":9".utf8)
                .write(to: ablage.appending(component: name))
        }
    }

    private func abdruck(_ ordner: URL) throws -> [String: Data] {
        var stand: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: ordner.path) {
            let url = ordner.appending(component: name)
            var istOrdner: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &istOrdner)
            if !istOrdner.boolValue { stand[name] = try Data(contentsOf: url) }
        }
        return stand
    }

    @Test("Blockierter Start: kein Weg schreibt mehr in den Ordner — auch Sitzplan, Lesezeichen und Rettungskopien nicht (N53-01)")
    func blockierterStartSperrtJedenWeg() throws {
        let ablage = try ordner("blockiert")
        let material = try ordner("material")
        defer { for o in [ablage, material] { try? FileManager.default.removeItem(at: o) } }
        try blockierenderOrdner(ablage)
        let vorher = try abdruck(ablage)

        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.starten()
        #expect(s.sicherungLiegtStill, "der Start blockiert")
        #expect(s.planung == nil, "nichts geladen")

        // Der Weg des Berichts: neue Planung anlegen, Sitzplan übernehmen. In
        // einem blockierten Ordner wird schon das Anlegen abgewiesen (R1) —
        // sonst stünde Arbeit im Speicher, die sich nicht sichern ließe.
        s.neuePlanung(titel: "Ersatz", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                      klassen: Standardkurse.aufbauen([("G6a", "Informatik")]), ersterSchultag: nil,
                      uebernahme: [])
        #expect(s.planung == nil, "keine Planung in einer gesperrten Ablage")
        #expect(s.sperrhinweis.contains("beiseitelegen"), Comment(rawValue: s.sperrhinweis))
        // Und auch am Dienst vorbei geht nichts.
        #expect(s.sitzplaene.setzen(Sitzplan.anordnen(klasseId: "G6a", namen: ["Dana", "Emil"]),
                                    fuer: "G6a") != nil, "der Sitzplan wird abgewiesen")
        s.jetztSichern()
        _ = try? s.zugriff.merken(material)
        #expect(!s.sicherung.ablage.beschaedigtenStandBeiseitelegen(stempel: "probe"))
        #expect(s.sicherung.ablage.sitzplaeneKopieren(als: "sitzplaene-bereinigt-probe.json") == nil)
        let tresor = Tresor.neu()
        try tresor.passphraseSetzen(passphrase, runden: Tresor.rundenMindestens)
        #expect(!s.sicherung.altbestaendeVersiegeln(mit: tresor).vollstaendig)

        #expect(try abdruck(ablage) == vorher, "kein Byte im Ordner hat sich geändert")
    }

    @Test("Der Ausweg aus der Blockade: die Rückfrage zählt auf, das Räumen löscht nichts, danach schreibt die App wieder (E67)")
    func ausweiWegAusDerBlockade() throws {
        let ablage = try ordner("ausweg")
        defer { try? FileManager.default.removeItem(at: ablage) }
        try blockierenderOrdner(ablage)
        let vorher = try abdruck(ablage)

        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.starten()
        #expect(s.blockadeOffen, "blockiert")
        #expect(s.sicherung.blockadespuren == ["planung.json.vorgaenger", "sitzplaene.json.uebergang",
                                               Uebergangsdienst.markenname,
                                               Uebergangsdienst.zweitschriftname].sorted(),
                "\(s.sicherung.blockadespuren)")

        s.blockadeRaeumenFragen()
        let frage = try #require(s.rueckfrage)
        #expect(frage.bestaetigung == "Beiseitelegen")
        #expect(frage.text.contains("Gelöscht wird nichts"))
        #expect(frage.text.contains("planung.json.vorgaenger"))
        #expect(try abdruck(ablage) == vorher, "die Frage allein ändert nichts")

        frage.handlung()
        #expect(!s.blockadeOffen, "die Sperre ist fort")
        let namen = try FileManager.default.contentsOfDirectory(atPath: ablage.path).sorted()
        #expect(!namen.contains(Uebergangsdienst.markenname))
        #expect(!namen.contains { $0.hasSuffix(Uebergangsdienst.zwillingssuffix)
                                  || $0.hasSuffix(Uebergangsdienst.vorgaengersuffix) }, "\(namen)")
        #expect(namen.contains { $0.hasPrefix("planung-vorgaenger-") }, "\(namen)")
        #expect(namen.contains { $0.hasPrefix("sitzplaene-uebergang-") }, "\(namen)")
        #expect(namen.contains { $0.hasPrefix("uebergang-") && $0.hasSuffix(".json") }, "\(namen)")
        #expect(namen.contains { $0.hasPrefix("uebergang-zweitschrift-") }, "\(namen)")
        // Nichts ist verloren: Jede Datei von vorher liegt noch, unter altem
        // oder unter neuem Namen.
        let jetzt = try abdruck(ablage)
        for (_, inhalt) in vorher {
            #expect(jetzt.values.contains(inhalt), "ein Inhalt ging verloren")
        }
        // Und die App schreibt wieder.
        s.neuePlanung(titel: "Weiter", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                      klassen: Standardkurse.aufbauen([("G6a", "Informatik")]), ersterSchultag: nil,
                      uebernahme: [])
        s.jetztSichern()
        #expect(!s.sicherungLiegtStill, Comment(rawValue: s.sicherung.stillgrund))
        #expect(s.sicherung.gesicherterStand != nil)
    }

    @Test("Bleibt ein Stück im Weg, bleibt die Sperre (E67)")
    func ausweiGescheitert() throws {
        let ablage = try ordner("ausweg-fehler")
        let marke = ablage.appending(component: Uebergangsdienst.markenname)
        defer {
            unveraenderbar(marke, false)
            try? schreibrecht(ablage, true)
            try? FileManager.default.removeItem(at: ablage)
        }
        try blockierenderOrdner(ablage)
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.starten()
        #expect(s.blockadeOffen)

        unveraenderbar(marke, true)
        s.blockadeRaeumenFragen()
        try #require(s.rueckfrage).handlung()
        unveraenderbar(marke, false)
        #expect(s.blockadeOffen, "die Sperre bleibt, solange ein Stück im Weg liegt")
        #expect(FileManager.default.fileExists(atPath: marke.path), "die Marke liegt noch")
    }

    @Test("Ohne Befund gibt der Start frei: danach schreibt alles wie gewohnt")
    func freierStartSchreibtWieGewohnt() throws {
        let ablage = try ordner("frei")
        let ziel = try ordner("ziel")
        defer { for o in [ablage, ziel] { try? FileManager.default.removeItem(at: o) } }
        let s = try speicher(ablage: ablage, ziel: ziel)
        s.jetztSichern()
        #expect(!s.sicherungLiegtStill)
        #expect(FileManager.default.fileExists(atPath: Ablage(ordner: ablage).datei.path))
        let klasse = try #require(s.planung?.klassen.first?.id)
        #expect(s.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse, namen: ["Dana"])) == nil)
        #expect(FileManager.default.fileExists(atPath: Ablage(ordner: ablage).sitzplaene.path))
    }

    // ── Zug 2 von Phase P: der Ausweg nimmt den Stand wieder auf ──────────

    /// Eine Spur ohne Marke, die keine Datei der Generation anfasst: Der
    /// Wiederanlauf blockiert (E68), und alles, was liegt, liegt unversehrt.
    private func spurOhneMarke(_ ablage: URL) throws {
        try Data("uralt".utf8).write(to: ablage.appending(component: "lesezeichen.json.vorgaenger"))
    }

    @Test("Nach dem Ausweg ist der bisherige Stand eingelesen — nicht eine leere Sitzung (N54-01)")
    func auswegNimmtDenStandWiederAuf() throws {
        let ablage = try ordner("ausweg-stand")
        let ziel = try ordner("ausweg-stand-ziel")
        defer { for o in [ablage, ziel] { try? FileManager.default.removeItem(at: o) } }
        let erster = try speicher(ablage: ablage, ziel: ziel)
        erster.jetztSichern()
        let klasse = try #require(erster.planung?.klassen.first?.id)
        #expect(erster.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse, namen: ["Dana"])) == nil)
        try spurOhneMarke(ablage)
        let vorher = try abdruck(ablage)

        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.starten()
        #expect(s.blockadeOffen)
        #expect(s.planung == nil, "solange gesperrt ist, wird nichts geladen")

        s.blockadeRaeumenFragen()
        try #require(s.rueckfrage).handlung()
        #expect(!s.blockadeOffen, "die Sperre ist fort")
        #expect(s.planung?.titel == "Übergang", "der Stand von der Platte ist eingelesen")
        #expect(s.sitzplaene.hatPlaene, "die Sitzpläne sind mitgekommen")
        for (name, inhalt) in vorher where !name.hasSuffix(".vorgaenger") {
            #expect(try Data(contentsOf: ablage.appending(component: name)) == inhalt,
                    Comment(rawValue: "„\(name)“ wurde angerührt"))
        }
    }

    @Test("Nach dem Ausweg bleibt ein Behälter ein Behälter — die Sitzung schreibt keinen Klartext darüber (N54-01)")
    func auswegUeberVersiegelterAblage() throws {
        let ablage = try ordner("ausweg-versiegelt")
        let ziel = try ordner("ausweg-versiegelt-ziel")
        defer { for o in [ablage, ziel] { try? FileManager.default.removeItem(at: o) } }
        let erster = try speicher(ablage: ablage, ziel: ziel)
        let klasse = try #require(erster.planung?.klassen.first?.id)
        #expect(erster.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse, namen: ["Dana"])) == nil)
        _ = try erster.verschluesselungVorbereiten(passphrase: passphrase)
        erster.verschluesselungEinschalten()
        let dateien = Ablage(ordner: ablage)
        #expect(Tresor.istBehaelter(try Data(contentsOf: dateien.datei)), "die Planung liegt versiegelt")
        #expect(Tresor.istBehaelter(try Data(contentsOf: dateien.sitzplaene)), "die Sitzpläne liegen versiegelt")
        try spurOhneMarke(ablage)
        let vorher = try abdruck(ablage)

        // Eine neue Sitzung: kein Schlüssel, nichts geladen — und eine Sperre.
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.starten()
        #expect(s.blockadeOffen)

        s.blockadeRaeumenFragen()
        try #require(s.rueckfrage).handlung()
        // Der Ausweg gibt den Ordner frei — der Stand darüber ist aber versiegelt:
        // Die App fragt nach dem Entsperren und schreibt bis dahin nichts.
        #expect(!s.blockadeOffen, "die Sperre der Blockade ist fort")
        #expect(s.verschluesselungsstand == .gesperrt, "der Behälter wartet auf das Entsperren")
        #expect(s.entsperrungOffen, "die Entsperrung steht offen")
        #expect(s.planung == nil)

        // Und jetzt alles, was schreiben könnte.
        s.neuePlanung(titel: "Fremd", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                      klassen: Standardkurse.aufbauen([("G6a", "Informatik")]), ersterSchultag: nil,
                      uebernahme: [])
        s.jetztSichern()
        _ = s.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse, namen: ["Fremd"]))
        s.lesezeichenNachruesten()

        for (name, inhalt) in vorher where !name.hasSuffix(".vorgaenger") {
            #expect(try Data(contentsOf: ablage.appending(component: name)) == inhalt,
                    Comment(rawValue: "„\(name)“ wurde ersetzt"))
        }
        #expect(Tresor.istBehaelter(try Data(contentsOf: dateien.datei)), "die Planung ist noch versiegelt")
        #expect(Tresor.istBehaelter(try Data(contentsOf: dateien.sitzplaene)), "die Sitzpläne sind noch versiegelt")
    }

    @Test("Legt eine fremde Hand einen Behälter hin, ruht die Autosicherung mit Grund (E72)")
    func formsperreWirdGemeldet() throws {
        let ablage = try ordner("formsperre")
        let ziel = try ordner("formsperre-ziel")
        defer { for o in [ablage, ziel] { try? FileManager.default.removeItem(at: o) } }
        let s = try speicher(ablage: ablage, ziel: ziel)
        s.jetztSichern()
        #expect(!s.sicherungLiegtStill)

        // Eine Wiederherstellung, ein Abgleichdienst, eine fremde Hand: An der
        // Stelle der Planung liegt jetzt ein Behälter, zu dem die Sitzung
        // keinen Schlüssel hat.
        let fremd = try Tresor.neu().versiegeln(Data("geheim".utf8), inhalt: .planung, ziel: .ablage)
        try fremd.write(to: Ablage(ordner: ablage).datei)

        // Der Stand muss sich ändern, sonst gilt das Schreiben als unnötig und
        // der Wächter käme gar nicht dran (zwei Sicherungen in derselben
        // Sekunde tragen denselben Stempel).
        s.titelSetzen("weiter")
        s.planung?.geaendert = "2030-01-01T00:00:00Z"
        s.jetztSichern()
        #expect(s.sicherungLiegtStill, "die Autosicherung ruht")
        #expect(s.sicherung.stillgrund.contains("anderer Schutz"),
                Comment(rawValue: s.sicherung.stillgrund))
        #expect(try Data(contentsOf: Ablage(ordner: ablage).datei) == fremd,
                "der Behälter liegt unberührt — kein Klartext darüber")
    }

    @Test("Der erste Start legt keinen Ordner an und sperrt auch nicht (N54-02)")
    func ersterStartOhneOrdner() throws {
        // Kein `ordner(_:)`: Dieser Ordner soll gerade nicht liegen — so wie die
        // Ablage im Container einer frisch installierten App.
        let ablage = URL.temporaryDirectory.appending(component: "erststart-\(UUID().uuidString)",
                                                      directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: ablage) }
        #expect(!FileManager.default.fileExists(atPath: ablage.path))

        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.starten()
        #expect(!s.blockadeOffen, Comment(rawValue: s.sicherung.wiederanlaufBlockade ?? ""))
        #expect(s.offenerDialog == .neuePlanung, "der erste Start fragt nach einer neuen Planung")
        #expect(!FileManager.default.fileExists(atPath: ablage.path), "angelegt wird erst beim Schreiben")

        s.neuePlanung(titel: "Erst", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                      klassen: Standardkurse.aufbauen([("G6a", "Informatik")]), ersterSchultag: nil,
                      uebernahme: [])
        s.jetztSichern()
        #expect(!s.sicherungLiegtStill, Comment(rawValue: s.sicherung.stillgrund))
        #expect(FileManager.default.fileExists(atPath: Ablage(ordner: ablage).datei.path),
                "die erste Sicherung legt den Ordner an")
    }

    @Test("Ein Ordner, der liegt, sich aber nicht auflisten lässt, sperrt weiterhin (N53-02, N54-02)")
    func unlesbarerOrdnerSperrtWeiterhin() throws {
        let ablage = try ordner("unlesbar")
        defer {
            try? schreibrecht(ablage, true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ablage.path)
            try? FileManager.default.removeItem(at: ablage)
        }
        try Data("{\"typ\":\"unterrichtsplanung\",\"version\":2,\"titel\":\"alt\"}".utf8)
            .write(to: ablage.appending(component: "planung.json"))
        // Nur ausführbar: bekannte Dateien lassen sich öffnen, der Ordner nicht auflisten.
        try FileManager.default.setAttributes([.posixPermissions: 0o100], ofItemAtPath: ablage.path)

        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.starten()
        #expect(s.blockadeOffen, "über diesen Ordner ist nichts bekannt")
        #expect(s.planung == nil, "geladen wird nichts")
    }

    /// Ein Abbild des Ordners — so, wie ein Abbruch ihn hinterließe.
    private func abbild(_ ablage: URL, _ name: String) throws -> URL {
        let ziel = try ordner("abbild-\(name)")
        try FileManager.default.removeItem(at: ziel)
        try FileManager.default.copyItem(at: ablage, to: ziel)
        return ziel
    }

    /// Ein zweiter Speicher auf dem Abbild: Er findet einen Stand — den alten
    /// (vor der Marke) oder den neuen (ab der Marke) —, entsperrt ihn mit der
    /// passenden Passphrase, öffnet Lesezeichen und Sitzpläne, legt nichts beiseite.
    private func wiederanlaufPruefen(_ probe: Uebergangsprobe, schritt: Uebergangsdienst.Schritt,
                                     abbild: URL, ziel: URL, material: URL) async throws {
        let neuerStand = schritt != .vorbereitet
        let kennzeichen = "\(probe) nach \(schritt.rawValue)"
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: abbild))
        zweiter.starten()
        if !neuerStand {
            // Vor der Marke abgebrochen: Zwillinge ohne Marke sperren seit E73,
            // statt still zu verschwinden — der Nutzer geht über den Ausweg, und
            // erst danach steht der alte Stand wieder offen.
            #expect(zweiter.blockadeOffen, Comment(rawValue: "\(kennzeichen): jede Spur sperrt"))
            zweiter.blockadeRaeumenFragen()
            try #require(zweiter.rueckfrage).handlung()
            #expect(!zweiter.blockadeOffen, Comment(rawValue: "\(kennzeichen): der Ausweg räumt"))
        }
        if probe == .wicklung, neuerStand {
            // Vor dem Entsperren (ohne Touch ID nimmt es die Wicklung wieder fort): Ablage und
            // Vorgängerfassung tragen die Wicklung dieses Macs — in einem Stand.
            for datei in [Ablage(ordner: abbild).datei, Ablage(ordner: abbild).vorherigeFassung] {
                let wicklung = try Tresor.kopfLesen(try Data(contentsOf: datei)).wicklung(Wicklung.enklave)
                #expect(wicklung != nil, "\(kennzeichen): \(datei.lastPathComponent)")
            }
        }
        let versiegelt: Bool = switch probe {
        case .einschalten: neuerStand
        case .aufheben: !neuerStand
        case .erneuern, .passphrase, .wicklung: true
        }
        let gilt: String = switch probe {
        case .erneuern, .passphrase: neuerStand ? neue : passphrase
        default: passphrase
        }
        if versiegelt {
            #expect(zweiter.verschluesselungsstand == .gesperrt, Comment(rawValue: kennzeichen))
            await zweiter.entsperren(passphrase: gilt)
            #expect(zweiter.verschluesselungsstand == .an, "\(kennzeichen): entsperrt mit „\(gilt)“")
            #expect(zweiter.zugriff.quelle == .behaelter, Comment(rawValue: kennzeichen))
            #expect(zweiter.sitzplaene.quelle == .behaelter, Comment(rawValue: kennzeichen))
        } else {
            #expect(zweiter.verschluesselungsstand == .aus, Comment(rawValue: kennzeichen))
            #expect(zweiter.zugriff.quelle == .einstellungen, Comment(rawValue: kennzeichen))
            #expect(zweiter.sitzplaene.quelle == .klartext, Comment(rawValue: kennzeichen))
        }
        #expect(zweiter.planung?.titel == "Übergang, zweiter Stand", Comment(rawValue: kennzeichen))
        let klasse = try #require(zweiter.planung?.klassen.first?.id)
        #expect(zweiter.sitzplan(fuer: klasse)?.tische.count == 3, "\(kennzeichen): die Sitzpläne öffnen")
        #expect(zweiter.zugriff.zustaendig(fuer: material.path) != nil || !versiegelt,
                "\(kennzeichen): die Lesezeichen öffnen")
        if versiegelt {
            #expect(zweiter.zugriff.zielordner == ziel.path, Comment(rawValue: kennzeichen))
            let tresor = try #require(zweiter.tresor)
            let vorige = try #require(Ablage(ordner: abbild).vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse))
            #expect(try Tresor.kopfLesen(vorige).kennung == tresor.kennung, "\(kennzeichen): die Vorgängerfassung im selben Stand")
        }
        if neuerStand { try einStand(abbild) } else { try keineOffeneSpur(abbild) }
        #expect(!zweiter.meldungen.contains { $0.text.contains("galt nicht") || $0.text.contains("galten nicht") },
                "\(kennzeichen): nichts beiseitegelegt — \(zweiter.meldungen.map(\.text))")
        if neuerStand {
            #expect(zweiter.meldungen.contains { $0.text.contains("jetzt vollendet") },
                    "\(kennzeichen): der Wiederanlauf meldet sich — \(zweiter.meldungen.map(\.text))")
        } else {
            #expect(zweiter.meldungen.contains { $0.text.contains("neben der Planung") },
                    "\(kennzeichen): der Ausweg sagt, was er getan hat — \(zweiter.meldungen.map(\.text))")
        }
        // Der zweite Speicher arbeitet weiter: Ein Schreiben landet im geltenden Stand.
        zweiter.titelSetzen("weiter")
        zweiter.jetztSichern()
        let roh = try Data(contentsOf: Ablage(ordner: abbild).datei)
        #expect(Tresor.istBehaelter(roh) == versiegelt, Comment(rawValue: kennzeichen))
    }

    @Test("Übergeben, nicht eingesetzt: nichts schreibt daran vorbei — jeder Anlass holt das Einsetzen nach, dann gilt der Stand der Sitzung (N51-01, E54)",
          arguments: Uebergangsprobe.allCases)
    func uebergebenNichtEingesetzt(_ probe: Uebergangsprobe) async throws {
        if probe == .wicklung, !Tresor.enklaveVorhanden { return }
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        let material = try ordner("material")
        let weiteres = try ordner("weiteres")
        defer {
            try? schreibrecht(ablage, true)
            for o in [ablage, ziel, material, weiteres] { try? FileManager.default.removeItem(at: o) }
        }
        let s = try vorbereiteterSpeicher(probe, ablage: ablage, ziel: ziel, material: material)
        let vorher = try Data(contentsOf: Ablage(ordner: ablage).datei)
        // Nach dem ersten Tausch verliert der Ordner das Schreibrecht: Der Rest scheitert.
        var getauscht = 0
        s.sicherung.uebergang.haken = { schritt in
            guard schritt == .einsetzen else { return }
            getauscht += 1
            if getauscht == 1 { try? self.schreibrecht(ablage, false) }
        }
        let ergebnis = try ausloesen(probe, s)
        if probe != .wicklung {
            guard case .unvollendet = ergebnis.ablage else {
                Issue.record("\(probe): erwartet unvollendet — \(ergebnis.ablage)")
                return
            }
        }
        #expect(getauscht == 1, "\(probe): kein weiterer Tausch ohne Schreibrecht (\(getauscht))")
        #expect(s.sicherung.uebergang.istUebergeben, Comment(rawValue: "\(probe)"))
        #expect(s.sicherung.liegtStill && s.sicherung.stillgrund.contains("eingesetzt"), "\(probe): \(s.sicherung.stillgrund)")
        #expect(try Data(contentsOf: Ablage(ordner: ablage).datei) == vorher, "\(probe): die Ablage ist noch nicht getauscht")

        // Gewöhnliche Schreibanlässe kommen nicht am Übergang vorbei, solange das Einsetzen nicht gelingt.
        s.titelSetzen("weiter")
        s.jetztSichern()
        #expect(try Data(contentsOf: Ablage(ordner: ablage).datei) == vorher, "\(probe): die Sicherung schreibt nicht am Übergang vorbei")
        #expect(s.sicherung.gesicherterStand == nil, Comment(rawValue: "\(probe)"))
        let klasse = try #require(s.planung?.klassen.first?.id)
        #expect(s.sitzplanUebernehmen(Sitzplan.anordnen(klasseId: klasse, namen: ["Dana", "Emil"])) != nil, "\(probe): die Sitzpläne warten")
        if probe != .aufheben {
            _ = try? s.zugriff.merken(weiteres)
            #expect(s.zugriff.ungesichert != nil, "\(probe): die Lesezeichen warten")
        }
        #expect(s.sicherung.liegtStill, Comment(rawValue: "\(probe)"))

        // Der Ordner ist wieder schreibbar: Der nächste Anlass holt das Einsetzen nach und schreibt.
        try schreibrecht(ablage, true)
        s.jetztSichern()
        #expect(!s.sicherung.liegtStill && s.sicherung.stoerung == nil, "\(probe): \(s.sicherung.stillgrund)")
        #expect(!s.sicherung.uebergang.istUebergeben && s.sicherung.uebergang.laufend == nil, Comment(rawValue: "\(probe)"))
        s.sitzplaene.nachholen()
        #expect(s.sitzplaene.ungesichert == nil, Comment(rawValue: "\(probe)"))
        try einStand(ablage)

        // Der zweite Speicher findet einen Stand — den der Sitzung, nicht den der Generation.
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablage))
        zweiter.starten()
        if probe != .aufheben {
            #expect(zweiter.verschluesselungsstand == .gesperrt, Comment(rawValue: "\(probe)"))
            await zweiter.entsperren(passphrase: probe == .erneuern || probe == .passphrase ? neue : passphrase)
            #expect(zweiter.verschluesselungsstand == .an, Comment(rawValue: "\(probe)"))
        }
        #expect(zweiter.planung?.titel == "weiter", "\(probe): \(String(describing: zweiter.planung?.titel))")
        #expect(zweiter.sitzplan(fuer: klasse)?.tische.count == 2, "\(probe): die Sitzpläne der Sitzung")
        #expect(!zweiter.meldungen.contains { $0.text.contains("galt nicht") || $0.text.contains("galten nicht") || $0.text.contains("nicht abgeschlossen") },
                "\(probe): \(zweiter.meldungen.map(\.text))")
        try einStand(ablage)
    }

    @Test("Abbruch nach dem Vorbereiten, nach dem Übergeben und mitten im Einsetzen — für jeden Übergang: ein Stand, nichts beiseitegelegt",
          arguments: Uebergangsprobe.allCases)
    func abbruchUndWiederanlauf(_ probe: Uebergangsprobe) async throws {
        if probe == .wicklung, !Tresor.enklaveVorhanden { return }
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        let material = try ordner("material")
        // Ein Abbild je Schritt — beim Einsetzen je Tauschgrenze (N51-01).
        var abbilder: [(schritt: Uebergangsdienst.Schritt, abbild: URL)] = []
        defer {
            for o in [ablage, ziel, material] + abbilder.map(\.abbild) { try? FileManager.default.removeItem(at: o) }
        }
        let s = try vorbereiteterSpeicher(probe, ablage: ablage, ziel: ziel, material: material)
        s.sicherung.uebergang.haken = { schritt in
            if let abbild = try? self.abbild(ablage, "\(probe)-\(schritt.rawValue)-\(abbilder.count)") {
                abbilder.append((schritt, abbild))
            }
        }
        let ergebnis = try ausloesen(probe, s)
        #expect(ergebnis.ablage == .geschrieben, "\(probe): \(ergebnis.ablage)")
        try einStand(ablage)
        #expect(Set(abbilder.map(\.schritt)) == [.vorbereitet, .uebergeben, .einsetzen, .aufgeraeumt],
                "\(probe): \(abbilder.map(\.schritt))")
        #expect(abbilder.filter { $0.schritt == .einsetzen }.count >= 3, "\(probe): jede Tauschgrenze — \(abbilder.map(\.schritt))")
        for (schritt, abbild) in abbilder {
            let namen = try FileManager.default.contentsOfDirectory(atPath: abbild.path)
            switch schritt {
            case .vorbereitet:
                #expect(!namen.contains(Uebergangsdienst.markenname) && namen.contains { $0.hasSuffix(".uebergang") }, "\(probe): \(namen)")
            case .uebergeben:
                #expect(namen.contains(Uebergangsdienst.markenname) && namen.contains { $0.hasSuffix(".uebergang") }, "\(probe): \(namen)")
            case .einsetzen:
                #expect(namen.contains(Uebergangsdienst.markenname), "\(probe): \(namen)")
            case .aufgeraeumt:
                // Alles getauscht, die Vorgänger fort, die Marke liegt noch (E60).
                #expect(namen.contains(Uebergangsdienst.markenname), "\(probe): \(namen)")
                #expect(!namen.contains { $0.hasSuffix(Uebergangsdienst.vorgaengersuffix) }, "\(probe): \(namen)")
                #expect(!namen.contains { $0.hasSuffix(Uebergangsdienst.zwillingssuffix) }, "\(probe): \(namen)")
            }
            try await wiederanlaufPruefen(probe, schritt: schritt, abbild: abbild, ziel: ziel, material: material)
        }
    }
}
