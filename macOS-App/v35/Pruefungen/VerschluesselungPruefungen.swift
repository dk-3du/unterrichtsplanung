// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import LocalAuthentication
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

extension Planungsspeicher {
    /// Die Einrichtung ohne Dialog: Passphrase setzen, Blatt „bestätigen“,
    /// einschalten. Liefert den Wiederherstellungsschlüssel.
    @discardableResult
    func pruefverschluesselung(_ passphrase: String = "Ein Satz, den man behält") throws -> String {
        let blatt = try verschluesselungVorbereiten(passphrase: passphrase)
        verschluesselungEinschalten()
        return blatt
    }
}

// ── Der Sicherungsweg mit Verschlüsselung ─────────────────────────────────
// In derselben, serialisierten Reihe wie der Klartext-Sicherungsweg: Beide
// gehen über `Ablage.shared`, und der Tresor darin ist prozessweit.

extension SicherungswegPruefungen {

    private func ablageLeerenUndEntsperren() {
        Ablage.shared.tresor = nil
        let verwaltung = FileManager.default
        for name in (try? verwaltung.contentsOfDirectory(atPath: Ablage.shared.ordner.path)) ?? []
        where name.hasPrefix("planung") && name.hasSuffix(".json") {
            try? verwaltung.removeItem(at: Ablage.shared.ordner.appendingPathComponent(name))
        }
    }

    private func planungAnlegen(_ speicher: Planungsspeicher, titel: String) throws {
        speicher.neuePlanung(titel: titel, start: try #require(Tag(iso: "2026-08-10")),
                             wochen: 6, basis: "",
                             klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             ersterSchultag: nil, uebernahme: [])
    }

    private func rohAufDerPlatte() throws -> Data {
        try Data(contentsOf: Ablage.shared.datei)
    }

    @Test("Einschalten versiegelt die Ablage sofort, samt Vorgängerfassung")
    func einschalten() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        try planungAnlegen(speicher, titel: "Wird versiegelt")
        speicher.jetztSichern()
        Thread.sleep(forTimeInterval: 0.003)
        speicher.titelSetzen("Zweiter Stand")
        speicher.jetztSichern()
        #expect(!Tresor.istBehaelter(try rohAufDerPlatte()))
        #expect(Ablage.shared.vorigeFassungLesen() != nil)

        let blatt = try speicher.pruefverschluesselung()
        #expect(blatt.count == 39)
        #expect(speicher.verschluesselungsstand == .an)
        #expect(Ablage.shared.tresor != nil)
        #expect(Tresor.istBehaelter(try rohAufDerPlatte()))
        #expect(Tresor.istBehaelter(try #require(Ablage.shared.vorigeFassungLesen())),
                "die Vorgängerfassung wird an Ort und Stelle versiegelt")
        let text = String(decoding: try rohAufDerPlatte(), as: UTF8.self)
        #expect(!text.contains("Zweiter Stand"))
        // Ohne Enklave im Prüfstand: zwei Wicklungen.
        #expect(speicher.wicklungen.map(\.art).sorted() == ["passphrase", "wiederherstellung"])
        #expect(speicher.meldungen.contains { $0.text.contains("eingeschaltet") })
    }

    @Test("Der Start mit versiegelter Ablage wartet auf die Freigabe — Passphrase öffnet, falsche nicht")
    func startGesperrt() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let einrichtung = Planungsspeicher()
        einrichtung.starten()
        try planungAnlegen(einrichtung, titel: "Hinter Schloss")
        einrichtung.jetztSichern()
        let blatt = try einrichtung.pruefverschluesselung("Passphrase mit Umlaut ä")
        // Neuer Prozessstart nachgestellt: kein Tresor mehr im Speicher.
        Ablage.shared.tresor = nil

        let speicher = Planungsspeicher()
        speicher.starten()
        #expect(speicher.planung == nil)
        #expect(speicher.verschluesselungsstand == .gesperrt)
        #expect(speicher.entsperrungOffen)
        #expect(speicher.offenerDialog == .entsperren)
        #expect(!speicher.enklaveMoeglich, "im Prüfstand keine Enklave")
        #expect(speicher.sicherungLiegtStill)

        speicher.entsperren(passphrase: "falsche Passphrase")
        #expect(speicher.planung == nil)
        #expect(speicher.entsperrungFehler?.contains("passt nicht") == true)
        #expect(speicher.verschluesselungsstand == .gesperrt)

        // Auch eine neue Planung darf die gesperrte Ablage nicht überfahren.
        try planungAnlegen(speicher, titel: "Überfahren?")
        #expect(speicher.planung == nil)

        speicher.entsperren(passphrase: "Passphrase mit Umlaut a\u{0308}")
        #expect(speicher.planung?.titel == "Hinter Schloss")
        #expect(speicher.verschluesselungsstand == .an)
        #expect(!speicher.entsperrungOffen)
        #expect(speicher.offenerDialog == nil)
        #expect(!speicher.sicherungLiegtStill)

        // Und mit dem Wiederherstellungsschlüssel, nach erneutem „Neustart“.
        Ablage.shared.tresor = nil
        let dritter = Planungsspeicher()
        dritter.starten()
        dritter.entsperren(wiederherstellung: blatt.lowercased())
        #expect(dritter.planung?.titel == "Hinter Schloss")
    }

    @Test("Abbrechen lässt die Ablage zu; Fortsetzen öffnet das Blatt erneut")
    func abbrechen() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let einrichtung = Planungsspeicher()
        einrichtung.starten()
        try planungAnlegen(einrichtung, titel: "Bleibt zu")
        einrichtung.jetztSichern()
        try einrichtung.pruefverschluesselung()
        Ablage.shared.tresor = nil

        let speicher = Planungsspeicher()
        speicher.starten()
        speicher.entsperrungAbbrechen()
        #expect(speicher.offenerDialog == nil)
        #expect(speicher.verschluesselungsstand == .gesperrt)
        #expect(speicher.entsperrungOffen)
        speicher.entsperrungFortsetzen()
        #expect(speicher.offenerDialog == .entsperren)
        speicher.entsperren(passphrase: "Ein Satz, den man behält")
        #expect(speicher.planung?.titel == "Bleibt zu")
    }

    @Test("Aufheben schreibt Ablage und Vorgängerfassung wieder als Klartext")
    func aufheben() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        try planungAnlegen(speicher, titel: "Wieder offen")
        speicher.jetztSichern()
        try speicher.pruefverschluesselung()
        #expect(Tresor.istBehaelter(try rohAufDerPlatte()))

        speicher.verschluesselungAufheben()
        #expect(speicher.verschluesselungsstand == .aus)
        #expect(Ablage.shared.tresor == nil)
        #expect(!Tresor.istBehaelter(try rohAufDerPlatte()))
        #expect(try Planungsdatei.lesen(try rohAufDerPlatte()).titel == "Wieder offen")
        if let vorige = Ablage.shared.vorigeFassungLesen() {
            #expect(!Tresor.istBehaelter(vorige))
        }
    }

    @Test("Passphrase ändern und Schlüssel erneuern lassen die Planung unberührt")
    func aendernUndErneuern() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        try planungAnlegen(speicher, titel: "Bleibt gleich")
        speicher.jetztSichern()
        try speicher.pruefverschluesselung("Ein Satz, den man behält")
        let alteKennung = try #require(Ablage.shared.tresor?.kennung)

        #expect(throws: Tresorfehler.self) {
            try speicher.passphraseAendern(alt: "nicht die richtige", neu: "Ein ganz neuer Satz")
        }
        try speicher.passphraseAendern(alt: "Ein Satz, den man behält", neu: "Ein ganz neuer Satz")
        #expect(Ablage.shared.tresor?.kennung == alteKennung, "nur die Wicklung wechselt")
        var kopf = try Tresor.kopfLesen(try rohAufDerPlatte())
        #expect(throws: Tresorfehler.self) { try Tresor.oeffnen(kopf: kopf, passphrase: "Ein Satz, den man behält") }
        #expect(try Tresor.oeffnen(kopf: kopf, passphrase: "Ein ganz neuer Satz").kennung == alteKennung)

        #expect(throws: Tresorfehler.self) {
            try speicher.schluesselErneuernVorbereiten(passphrase: "nicht die richtige")
        }
        let blatt = try speicher.schluesselErneuernVorbereiten(passphrase: "Ein ganz neuer Satz")
        #expect(Ablage.shared.tresor?.kennung == alteKennung, "vor der Bestätigung geschieht nichts")
        speicher.verschluesselungEinschalten()
        let neueKennung = try #require(Ablage.shared.tresor?.kennung)
        #expect(neueKennung != alteKennung)
        kopf = try Tresor.kopfLesen(try rohAufDerPlatte())
        #expect(kopf.kennung == neueKennung)
        #expect(try Tresor.oeffnen(kopf: kopf, wiederherstellung: blatt).kennung == neueKennung)
        #expect(speicher.planung?.titel == "Bleibt gleich")
        // Die Vorgängerfassung ist unter dem neuen Schlüssel versiegelt.
        let vorige = try #require(Ablage.shared.vorigeFassungLesen())
        #expect(try Tresor.kopfLesen(vorige).kennung == neueKennung)
    }

    @Test("Eine verschlüsselte Datei von außen öffnet mit dem eigenen Schlüssel — oder fragt nach dem fremden")
    func oeffnenVonAussen() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        try planungAnlegen(speicher, titel: "Eigene")
        speicher.jetztSichern()
        try speicher.pruefverschluesselung()
        let eigener = try #require(Ablage.shared.tresor)

        var p = Planung.leer(titel: "Von draußen", start: try #require(Tag(iso: "2026-08-03")),
                             wochen: 6, basis: "",
                             klassen: Standardkurse.aufbauen([("G6a", "Informatik")]), fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 2, titel: "Bits",
                                text: "", erledigt: false, materialien: [], links: [])]
        let klartext = try Planungsdatei.schreiben(p)

        // Unter dem eigenen Schlüssel: ohne Nachfrage.
        let eigene = URL.temporaryDirectory.appending(component: "eigene-\(UUID().uuidString).json")
        try eigener.versiegeln(klartext, inhalt: .planung, ziel: .export).write(to: eigene)
        defer { try? FileManager.default.removeItem(at: eigene) }
        speicher.importieren(von: eigene)
        speicher.rueckfrageBeantworten(true)
        #expect(speicher.planung?.titel == "Von draußen")
        #expect(!speicher.entsperrungOffen)

        // Unter fremdem Schlüssel: das Blatt fragt, die Ablage bleibt offen.
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        let fremde = URL.temporaryDirectory.appending(component: "fremde-\(UUID().uuidString).json")
        p.titel = "Von noch weiter draußen"
        try fremder.versiegeln(try Planungsdatei.schreiben(p), inhalt: .planung, ziel: .export).write(to: fremde)
        defer { try? FileManager.default.removeItem(at: fremde) }
        speicher.importieren(von: fremde)
        #expect(speicher.entsperrungOffen)
        #expect(!speicher.entsperrungFuerAblage)
        #expect(speicher.offenerDialog == .entsperren)
        #expect(!speicher.sicherungLiegtStill, "die Ablage bleibt offen")
        speicher.entsperren(passphrase: "Fremde Passphrase 2026")
        speicher.rueckfrageBeantworten(true)
        #expect(speicher.planung?.titel == "Von noch weiter draußen")
        #expect(!speicher.entsperrungOffen)
        // Und auf der Platte liegt sie unter dem eigenen Schlüssel.
        speicher.jetztSichern()
        #expect(try Tresor.kopfLesen(try rohAufDerPlatte()).kennung == eigener.kennung)
    }

    @Test("Ohne Verschlüsselung weist die Ablage eine verschlüsselte Datei ab")
    func oeffnenOhneTresor() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        let p = Planung.leer(titel: "Verschlossen", start: try #require(Tag(iso: "2026-08-03")),
                             wochen: 6, basis: "", klassen: [], fachfarben: [:])
        let datei = URL.temporaryDirectory.appending(component: "zu-\(UUID().uuidString).json")
        try fremder.versiegeln(try Planungsdatei.schreiben(p), inhalt: .planung, ziel: .export).write(to: datei)
        defer { try? FileManager.default.removeItem(at: datei) }
        speicher.importieren(von: datei)
        #expect(speicher.planung == nil)
        #expect(!speicher.entsperrungOffen)
        #expect(speicher.meldungen.contains { $0.text.contains("Verschlüsselung einschalten") })
    }

    @Test("Ein beschädigter Behälter wird beiseitegelegt und die versiegelte Vorgängerfassung gerettet")
    func beschaedigterBehaelter() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let speicher = Planungsspeicher()
        speicher.starten()
        try planungAnlegen(speicher, titel: "Die Rettung")
        speicher.jetztSichern()
        try speicher.pruefverschluesselung()
        Thread.sleep(forTimeInterval: 0.003)
        speicher.titelSetzen("Zweiter Stand")
        speicher.jetztSichern()
        // planung.json und planung-vorher.json sind Behälter; die Nutzlast des ersten wird zerstört.
        var roh = try rohAufDerPlatte()
        let stelle = roh.count - 30
        roh[stelle] = roh[stelle] == UInt8(ascii: "A") ? UInt8(ascii: "B") : UInt8(ascii: "A")
        try roh.write(to: Ablage.shared.datei)
        Ablage.shared.tresor = nil

        let zweiter = Planungsspeicher()
        zweiter.starten()
        #expect(zweiter.verschluesselungsstand == .gesperrt)
        zweiter.entsperren(passphrase: "Ein Satz, den man behält")
        #expect(zweiter.planung?.titel == "Die Rettung", "die Fassung davor")
        #expect(zweiter.meldungen.contains { $0.text.contains("Fassung davor") })
        let liegt = try FileManager.default.contentsOfDirectory(atPath: Ablage.shared.ordner.path)
        #expect(liegt.contains { $0.hasPrefix("planung-beschaedigt-") })
        // Alles, was liegt, ist versiegelt — auch die Rettungskopie war es schon.
        for name in liegt where name.hasPrefix("planung") && name.hasSuffix(".json") {
            let inhalt = try Data(contentsOf: Ablage.shared.ordner.appendingPathComponent(name))
            #expect(Tresor.istBehaelter(inhalt), Comment(rawValue: name))
        }
    }
    // ── Freigabe wie bei iWork ──────────────────────────────────────

    /// Die Wicklung dieses Macs auf der Platte — aus dem Kopf der Ablage.
    private func enklaveAufDerPlatte() throws -> Wicklung? {
        try Tresor.kopfLesen(try rohAufDerPlatte()).wicklung(Wicklung.enklave)
    }

    @Test("Häkchen „Mit Touch ID öffnen“: die Passphrase richtet diesen Mac ein, der Schlüssel verlangt Freigabe")
    func haekchenRichtetEin() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let einrichtung = Planungsspeicher()
        einrichtung.starten()
        try planungAnlegen(einrichtung, titel: "Mit Häkchen")
        einrichtung.jetztSichern()
        try einrichtung.pruefverschluesselung()
        #expect(try enklaveAufDerPlatte() == nil, "im Prüfstand legt das Einschalten keine Enklaven-Wicklung an")
        Ablage.shared.tresor = nil

        let speicher = Planungsspeicher()
        speicher.starten()
        #expect(speicher.offenerDialog == .entsperren, "ohne Wicklung kommt das Blatt sofort")
        #expect(!speicher.enklaveMerken, "im Prüfstand keine Enklave, also kein Häkchen")
        speicher.enklaveImPruefstandAnlegen = true
        speicher.enklaveMerken = true
        speicher.entsperren(passphrase: "Ein Satz, den man behält")
        #expect(speicher.planung?.titel == "Mit Häkchen")
        #expect(speicher.enklaveEingerichtet)
        #expect(try enklaveAufDerPlatte() != nil, "die Wicklung liegt auf der Platte")
        #expect(speicher.meldungen.last?.text.contains("Touch ID") == true)

        // Der neue Schlüssel gibt ohne Freigabe nichts her — und fragt hier nicht.
        let kontext = LAContext()
        kontext.interactionNotAllowed = true
        let kopf = try Tresor.kopfLesen(try rohAufDerPlatte())
        #expect(throws: Tresorfehler.self) { try Tresor.oeffnen(kopf: kopf, enklave: kontext) }

        // Ein zweites Entsperren per Passphrase lässt eine tragende Wicklung stehen.
        let blob = try #require(try enklaveAufDerPlatte()?.daten("geraet"))
        Ablage.shared.tresor = nil
        let zweiter = Planungsspeicher()
        zweiter.starten()
        zweiter.enklaveImPruefstandAnlegen = true
        zweiter.enklaveMerken = true
        zweiter.entsperren(passphrase: "Ein Satz, den man behält")
        #expect(try enklaveAufDerPlatte()?.daten("geraet") == blob, "kein neuer Schlüssel ohne Not")
    }

    @Test("Ohne Häkchen verliert dieser Mac seine Wicklung; der Schalter unter „Einstellungen“ holt sie zurück")
    func ohneHaekchen() throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let einrichtung = Planungsspeicher()
        einrichtung.starten()
        try planungAnlegen(einrichtung, titel: "Ohne Häkchen")
        einrichtung.jetztSichern()
        try einrichtung.pruefverschluesselung()
        einrichtung.enklaveImPruefstandAnlegen = true
        einrichtung.enklaveAufDiesemMac(true)
        #expect(einrichtung.enklaveEingerichtet)
        #expect(try enklaveAufDerPlatte() != nil)
        Ablage.shared.tresor = nil

        let speicher = Planungsspeicher()
        speicher.starten()
        #expect(!speicher.enklaveMoeglich, "im Prüfstand keine Enklave — das Blatt kommt sofort")
        #expect(speicher.offenerDialog == .entsperren)
        speicher.enklaveMerken = false
        speicher.entsperren(passphrase: "Ein Satz, den man behält")
        #expect(speicher.planung?.titel == "Ohne Häkchen")
        #expect(!speicher.enklaveEingerichtet)
        #expect(try enklaveAufDerPlatte() == nil, "die Wicklung ist von der Platte")
        #expect(speicher.meldungen.last?.text.contains("entfernt") == true)

        speicher.enklaveImPruefstandAnlegen = true
        speicher.enklaveAufDiesemMac(true)
        #expect(speicher.enklaveEingerichtet)
        #expect(try enklaveAufDerPlatte() != nil)
        speicher.enklaveAufDiesemMac(false)
        #expect(!speicher.enklaveEingerichtet)
        #expect(try enklaveAufDerPlatte() == nil)
    }

    @Test("Passt die Wicklung dieses Macs nicht mehr, kommt das Blatt mit Hinweis — das Häkchen richtet neu ein")
    func toteWicklung() async throws {
        ablageLeerenUndEntsperren()
        defer { ablageLeerenUndEntsperren() }
        let einrichtung = Planungsspeicher()
        einrichtung.starten()
        try planungAnlegen(einrichtung, titel: "Neuer Mac")
        einrichtung.jetztSichern()
        try einrichtung.pruefverschluesselung()
        einrichtung.enklaveImPruefstandAnlegen = true
        einrichtung.enklaveAufDiesemMac(true)
        Ablage.shared.tresor = nil
        // Der Blob eines anderen Macs, nachgestellt: unbrauchbare Bytes — die
        // Enklave weist ihn ab, ohne je nachzufragen.
        var objekt = try #require(JSONSerialization.jsonObject(with: rohAufDerPlatte()) as? [String: Any])
        var wicklungen = try #require(objekt["wicklungen"] as? [[String: Any]])
        for i in wicklungen.indices where wicklungen[i]["art"] as? String == Wicklung.enklave {
            wicklungen[i]["geraet"] = Data(repeating: 7, count: 10).base64EncodedString()
        }
        objekt["wicklungen"] = wicklungen
        try JSONSerialization.data(withJSONObject: objekt).write(to: Ablage.shared.datei)
        let alterBlob = try #require(try enklaveAufDerPlatte()?.daten("geraet"))

        Ablage.enklaveImPruefstand = true
        defer { Ablage.enklaveImPruefstand = false }
        let speicher = Planungsspeicher()
        speicher.starten()
        #expect(speicher.enklaveMoeglich)
        #expect(speicher.entsperrungLaeuft, "die Enklave läuft zuerst")
        #expect(speicher.offenerDialog == nil, "kein Blatt, solange die Abfrage steht")
        for _ in 0..<50 where speicher.offenerDialog != .entsperren {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(speicher.offenerDialog == .entsperren, "das Blatt kommt, sobald die Abfrage ohne Ergebnis endet")
        #expect(!speicher.entsperrungLaeuft)
        #expect(speicher.enklaveWicklungPasstNicht)
        #expect(speicher.entsperrungFehler?.contains("anderen Gerät") == true)

        speicher.enklaveImPruefstandAnlegen = true
        speicher.enklaveMerken = true
        speicher.entsperren(passphrase: "Ein Satz, den man behält")
        #expect(speicher.planung?.titel == "Neuer Mac")
        #expect(!speicher.enklaveWicklungPasstNicht)
        #expect(speicher.enklaveEingerichtet)
        let neuerBlob = try #require(try enklaveAufDerPlatte()?.daten("geraet"))
        #expect(neuerBlob != alterBlob, "die Wicklung ist ersetzt")
        #expect(speicher.meldungen.last?.text.contains("neu eingerichtet") == true)
    }

}

// ── Die Kopie beim Beenden und die Statusdatei ────────────────────────────

@Suite("Kopie und Status, verschlüsselt")
@MainActor
struct KopieVerschluesseltPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private func ordner() throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "kopie-tresor-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Kopie & Tresor", start: try #require(Tag(iso: "2026-08-03")),
                             wochen: 4, basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1,
                                titel: "Bits und Bytes", text: "", erledigt: false,
                                materialien: [], links: [])]
        return p
    }

    @Test("Ohne Verschlüsselung gibt es keine Kopie — und die Meldung sagt, warum")
    func keineKopieOhneTresor() throws {
        let ziel = try ordner()
        defer { try? FileManager.default.removeItem(at: ziel) }
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportOrdner = ziel.path
        speicher.autoexportAktiv = true
        #expect(!speicher.autoexportAusfuehren(vomNutzer: true))
        #expect(try FileManager.default.contentsOfDirectory(atPath: ziel.path).isEmpty)
        #expect(speicher.meldungen.contains { $0.text.contains("nur verschlüsselt") })
    }

    @Test("Die Kopie ist ein Behälter mit Passphrase- und Wiederherstellungswicklung und überschreibt den Klartext")
    func kopieVersiegelt() throws {
        let ziel = try ordner()
        defer { try? FileManager.default.removeItem(at: ziel) }
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportOrdner = ziel.path
        speicher.autoexportAktiv = true
        let datei = ziel.appending(component: "Kopie_Tresor.json")
        // Die Klartextkopie einer älteren Fassung liegt schon dort.
        try Planungsdatei.schreiben(try planung()).write(to: datei)

        try speicher.pruefverschluesselung()
        #expect(speicher.autoexportAusfuehren())
        let roh = try Data(contentsOf: datei)
        #expect(Tresor.istBehaelter(roh))
        #expect(!String(decoding: roh, as: UTF8.self).contains("Bits und Bytes"))
        let kopf = try Tresor.kopfLesen(roh)
        #expect(kopf.wicklungen.map(\.art).sorted() == ["passphrase", "wiederherstellung"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: ziel.path).count == 1,
                "überschrieben, nicht danebengeschrieben")
        let offen = try Tresor.oeffnen(kopf: kopf, passphrase: "Ein Satz, den man behält")
        #expect(try Planungsdatei.lesen(try offen.oeffnen(kopf: kopf)).titel == "Kopie & Tresor")
    }

    @Test("Die versiegelte Statusdatei wird übernommen — eine unter fremdem Schlüssel nicht")
    func statusVersiegelt() throws {
        let ziel = try ordner()
        defer { try? FileManager.default.removeItem(at: ziel) }
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportZielSetzen(ziel.path)
        try speicher.pruefverschluesselung()
        let tresor = try #require(speicher.tresor)

        let stand = Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(),
                                planungstitel: "Kopie & Tresor",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "aus dem Tresor")])
        let statusdatei = ziel.appending(component: Statusdatei.name)
        try tresor.versiegeln(try Statusdatei.schreiben(stand), inhalt: .status, ziel: .kopie)
            .write(to: statusdatei, options: [.atomic])
        #expect(!String(decoding: try Data(contentsOf: statusdatei), as: UTF8.self)
                    .contains("aus dem Tresor"))

        speicher.statusUebernehmen()
        let eins = try #require(speicher.planung?.eintraege.first { $0.id == "e-1" })
        #expect(eins.erledigt)
        #expect(eins.kommentar == "aus dem Tresor")

        // Fremder Schlüssel: benannt, nicht übernommen.
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        let fremd = Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(),
                                planungstitel: "Kopie & Tresor",
                                eintraege: ["e-1": .init(erledigt: false, kommentar: "fremd")])
        try fremder.versiegeln(try Statusdatei.schreiben(fremd), inhalt: .status, ziel: .kopie)
            .write(to: statusdatei, options: [.atomic])
        speicher.statusUebernehmen()
        let danach = try #require(speicher.planung?.eintraege.first { $0.id == "e-1" })
        #expect(danach.kommentar == "aus dem Tresor")
        #expect(speicher.meldungen.contains { $0.text.contains("anderen Schlüssel") })
    }

    @Test("Ein Behälter mit anderem Inhalt gilt nicht als Statusdatei")
    func falscherInhalt() throws {
        let ziel = try ordner()
        defer { try? FileManager.default.removeItem(at: ziel) }
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportZielSetzen(ziel.path)
        try speicher.pruefverschluesselung()
        let tresor = try #require(speicher.tresor)
        // Eine Planung als current_status.json abgelegt — unter dem eigenen Schlüssel.
        try tresor.versiegeln(try Planungsdatei.schreiben(try planung()), inhalt: .planung, ziel: .kopie)
            .write(to: ziel.appending(component: Statusdatei.name), options: [.atomic])
        speicher.statusUebernehmen()
        #expect(speicher.meldungen.contains { $0.text.contains("kein Status") })
    }

    @Test("Eine Klartext-Statusdatei wird noch gelesen — mit Hinweis")
    func statusKlartext() throws {
        let ziel = try ordner()
        defer { try? FileManager.default.removeItem(at: ziel) }
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportZielSetzen(ziel.path)
        try speicher.pruefverschluesselung()
        let stand = Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(),
                                planungstitel: "Kopie & Tresor",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "im Klartext")])
        try Statusdatei.schreiben(stand)
            .write(to: ziel.appending(component: Statusdatei.name), options: [.atomic])
        speicher.statusUebernehmen()
        #expect(speicher.planung?.eintraege.first { $0.id == "e-1" }?.kommentar == "im Klartext")
        #expect(speicher.meldungen.contains { $0.text.contains("unverschlüsselt an") })
    }

    @Test("Eine Wicklung aus der Statusdatei reist in die nächste Kopie")
    func fremdeWicklungReist() throws {
        let ziel = try ordner()
        defer { try? FileManager.default.removeItem(at: ziel) }
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.autoexportZielSetzen(ziel.path)
        try speicher.pruefverschluesselung()
        let tresor = try #require(speicher.tresor)

        // Die Ansicht legt eine Wicklung an und trägt sie in die Statusdatei.
        let traeger = Tresor(schluessel: tresor.schluessel, kennung: tresor.kennung,
                             wicklungen: tresor.wicklungen
                             + [Wicklung(art: "passkey", felder: ["kennung": .text("p-1")])])
        let stand = Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(),
                                planungstitel: "Kopie & Tresor",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "")])
        try traeger.versiegeln(try Statusdatei.schreiben(stand), inhalt: .status, ziel: .kopie)
            .write(to: ziel.appending(component: Statusdatei.name), options: [.atomic])
        speicher.statusUebernehmen()
        #expect(tresor.hat("passkey"))

        #expect(speicher.autoexportAusfuehren())
        let kopf = try Tresor.kopfLesen(try Data(contentsOf: ziel.appending(component: "Kopie_Tresor.json")))
        #expect(kopf.wicklung("passkey")?.text("kennung") == "p-1")
    }
}
