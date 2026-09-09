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
        let vorige = try #require(Ablage(ordner: ablage).vorigeFassungLesen())
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
