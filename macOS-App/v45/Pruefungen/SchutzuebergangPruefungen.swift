// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Übergang des Schutzes ─────────────────────────────────────────────
// Einschalten, Erneuern, Passphrase ändern, Aufheben — mit eigener Ablage und
// eigenem Zielordner: Die Meldung kommt aus dem, was die Platte danach trägt.

@Suite("Schutzübergang: Einschalten, Erneuern, Passphrase, Aufheben")
@MainActor
struct SchutzuebergangPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

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

        let meldung = try #require(s.meldungen.first { $0.text.contains("eingeschaltet") })
        #expect(meldung.art == .hinweis && !meldung.text.contains("Offen"))
        #expect(meldung.text.contains("Kopie außer Haus") && meldung.text.contains("Statusdatei"))
        #expect(meldung.text.contains("die Lesezeichen mit ihr"))
    }

    @Test("Einschalten ohne Schreibrecht: nichts eingeschaltet, die Sitzung bleibt Klartext, keine Kopie")
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
        let meldung = try #require(s.meldungen.last)
        #expect(meldung.art == .warnung && meldung.text.contains("nicht eingeschaltet"))
        // Der Systemtext steht in der Klammer, ohne seinen Schlusspunkt — ein Satz.
        // Hier scheitert schon der Behälter der Lesezeichen, vor der Ablage.
        #expect(meldung.text.contains(": die Lesezeichen ließen sich nicht versiegeln ("), "\(meldung.text)")
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

        let neue = "Ein anderer Satz, den man behält"
        _ = try s.schluesselErneuernVorbereiten(alt: passphrase, neu: neue)
        let ergebnis = s.verschluesselungEinschalten()
        let neuer = try #require(s.tresor)
        #expect(neuer.kennung != alter.kennung)
        #expect(ergebnis.ablage == .geschrieben && ergebnis.kopie == .erledigt && ergebnis.statusdatei == .erledigt)
        #expect(ergebnis.lesezeichen == .erledigt)
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
        #expect(s.meldungen.last?.text.contains("Schlüssel erneuert") == true)
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
        let neue = "Ein anderer Satz, den man behält"

        let lesezeichenVorher = try Data(contentsOf: Ablage(ordner: ablage).lesezeichen)
        let ergebnis = try s.passphraseAendern(alt: passphrase, neu: neue)
        #expect(ergebnis.ablage == .geschrieben && ergebnis.kopie == .erledigt)
        #expect(ergebnis.lesezeichen == .erledigt && ergebnis.statusdatei == .erledigt)
        #expect(try Data(contentsOf: Ablage(ordner: ablage).lesezeichen) != lesezeichenVorher,
                "derselbe Datenschlüssel, aber die neue Hülle")
        let dateien = [Ablage(ordner: ablage).datei, Ablage(ordner: ablage).vorherigeFassung,
                       Ablage(ordner: ablage).lesezeichen, kopie, statusdatei(ziel)]
        for datei in dateien {
            let kopf = try Tresor.kopfLesen(try Data(contentsOf: datei))
            #expect(throws: Tresorfehler.self, "\(datei.lastPathComponent): die alte Passphrase öffnet nicht mehr") {
                try Tresor.oeffnen(kopf: kopf, passphrase: passphrase)
            }
            #expect(try Tresor.oeffnen(kopf: kopf, passphrase: neue).kennung == tresor.kennung, "\(datei.lastPathComponent)")
        }
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

    @Test("Aufheben: die Ablage liegt wieder im Klartext, die Statusdatei bleibt, wie sie ist")
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
        #expect(try Data(contentsOf: statusdatei(ziel)) == statusVorher)
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
        let neue = "Ein anderer Satz, den man behält"
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

    // ── Schreibfehler: die neue Hülle gilt erst, wenn die Platte sie trägt ─

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
        let neue = "Ein anderer Satz, den man behält"

        try schreibrecht(ablage, false)
        let ergebnis = try s.passphraseAendern(alt: passphrase, neu: neue)
        guard case .zurueckgenommen = ergebnis.ablage else {
            Issue.record("erwartet: zurückgenommen, war \(ergebnis.ablage)")
            return
        }
        #expect(tresor.passphraseStimmt(passphrase) && !tresor.passphraseStimmt(neue))
        try oeffnenNurMit(passphrase, nicht: neue, dateien, kennung: tresor.kennung)
        let abgewiesen = try #require(s.meldungen.last?.text)
        #expect(abgewiesen.hasPrefix("Passphrase nicht geändert: die Ablage lässt sich nicht schreiben ("), "\(abgewiesen)")
        #expect(!abgewiesen.contains(".."), "\(abgewiesen)")

        try schreibrecht(ablage, true)
        #expect(try s.passphraseAendern(alt: passphrase, neu: neue).ablage == .geschrieben)
        #expect(tresor.passphraseStimmt(neue))
        try oeffnenNurMit(neue, nicht: passphrase, dateien, kennung: tresor.kennung)
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
        #expect(abgewiesen.contains("wird nicht angelegt: die Ablage lässt sich nicht schreiben (") && !abgewiesen.contains(".."), "\(abgewiesen)")
        #expect(try aufDerPlatte() == nil)

        try schreibrecht(ablage, true)
        s.enklaveAufDiesemMac(true)
        #expect(s.enklaveEingerichtet && tresor.hat(Wicklung.enklave))
        #expect(try aufDerPlatte() != nil)

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

    /// Ein Ordner an der Stelle der Ablage: Das Schreiben scheitert, und das
    /// Rücklesen kann die Platte nicht deuten — der eine Weg zu `.ungeprueft`
    /// mit einem Schreibfehler als Grund.
    private func ablageVerbauen(_ ablage: URL) throws {
        let datei = Ablage(ordner: ablage).datei
        try? FileManager.default.removeItem(at: datei)
        try FileManager.default.createDirectory(at: datei, withIntermediateDirectories: true)
    }

    @Test("Schreibfehler und unlesbare Ablage beim Einschalten: ungeprüft, der Grund ein Satz ohne Klammer in der Klammer")
    func ungeprueftEinschalten() throws {
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
        guard case .ungeprueft(let grund) = ergebnis.ablage else {
            Issue.record("erwartet: ungeprüft, war \(ergebnis.ablage)")
            return
        }
        #expect(grund.hasPrefix("die Ablage lässt sich nicht schreiben ("), "\(grund)")
        let meldung = try #require(s.meldungen.last?.text)
        #expect(meldung.contains("eingeschaltet, aber die Ablage ließ sich nicht zurücklesen: die Ablage lässt sich nicht schreiben ("), "\(meldung)")
        #expect(!meldung.contains("((") && !meldung.contains(".."), "\(meldung)")
    }

    @Test("Schreibfehler und unlesbare Ablage beim Aufheben: ungeprüft, der Grund ein Satz ohne Klammer in der Klammer")
    func ungeprueftAufheben() throws {
        let ablage = try ordner("ablage")
        let ziel = try ordner("ziel")
        defer {
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: ziel)
        }
        let s = try speicher(ablage: ablage, ziel: ziel)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().ablage == .geschrieben)
        try ablageVerbauen(ablage)

        let ergebnis = s.verschluesselungAufheben()
        guard case .ungeprueft(let grund) = ergebnis.ablage else {
            Issue.record("erwartet: ungeprüft, war \(ergebnis.ablage)")
            return
        }
        #expect(grund.hasPrefix("die Ablage lässt sich nicht schreiben ("), "\(grund)")
        let meldung = try #require(s.meldungen.last?.text)
        #expect(meldung.contains("Die Ablage ließ sich nicht zurücklesen: die Ablage lässt sich nicht schreiben ("), "\(meldung)")
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
}
