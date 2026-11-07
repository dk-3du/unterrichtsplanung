// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Eine versiegelte Planung auf einem frischen Mac übernehmen (v85, AW1b; E702, E707, E715) ──
// Ohne Planung und ohne eingeschaltete Verschlüsselung wies ⌘O eine versiegelte Planung ab und verwies auf „Einstellungen“,
// die es ohne Planung nicht gibt. Jetzt kommt das Entsperr-Blatt; mit Passphrase oder Wiederherstellungsschlüssel der Datei
// werden deren Schlüssel die der Ablage — wie nach einem Umzug mit dem Container. Abbrechen ändert nichts.

@Suite("Versiegelte Planung auf einem frischen Mac übernehmen (E702, E707, E715)")
@MainActor
struct PlanungUebernehmenPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Fremde Passphrase 2026"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "uebernehmen-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Biologie 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Zellgewebe",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    /// Eine versiegelte Planung wie aus „Planung sichern …“ eines anderen Macs — mit Passphrase und Wiederherstellungsschlüssel.
    private func fremdeDatei(_ quelle: URL) throws -> (datei: URL, wiederherstellung: String) {
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen(passphrase, runden: Tresor.rundenMindestens)
        let blatt = try fremder.wiederherstellungAnlegen()
        let datei = quelle.appending(component: "Biologie 2026-27.json")
        try fremder.versiegeln(try Planungsdatei.schreiben(try planung()), inhalt: .planung, ziel: .export).write(to: datei)
        return (datei, blatt)
    }

    /// Ein Speicher wie beim ersten Start, das Blatt „Neue Planung“ zu.
    private func ersterStart(_ ordner: URL) -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        s.starten()
        s.offenerDialog = nil
        return s
    }

    /// Die Ablage ist versiegelt; Passphrase **und** Wiederherstellungsschlüssel der Datei öffnen sie — gleich, womit übernommen
    /// wurde (Z-AW1b-06) —, und nirgends steht das Vorhaben im Klartext, auch nach dem entprellten Sichern (Z-AW1b-08).
    private func versiegeltUnterDenSchluesselnDerDatei(_ s: Planungsspeicher, _ ablage: URL,
                                                        wiederherstellung: String) async throws {
        await s.sicherung.entprelltJetzt()
        s.jetztSichern()
        let gelesen = try? Data(contentsOf: s.sicherung.ablage.datei)
        let roh = try #require(gelesen, "die Planung liegt in der Ablage")
        #expect(Tresor.istBehaelter(roh), "die Planung liegt versiegelt in der Ablage")
        let kopf = try #require(try? Tresor.kopfLesen(roh), "der Kopf der Ablage ist lesbar")
        let mitPassphrase = try? Tresor.oeffnen(kopf: kopf, passphrase: passphrase)
        let mitBlatt = try? Tresor.oeffnen(kopf: kopf, wiederherstellung: wiederherstellung)
        #expect(mitPassphrase != nil, "die Passphrase der Datei öffnet die Ablage")
        #expect(mitBlatt != nil, "ihr Wiederherstellungsschlüssel ebenso")
        let spuren = klartextSpuren(ablage)
        #expect(spuren.isEmpty, "nichts im Klartext auf der Platte: \(spuren)")
    }

    private func klartextSpuren(_ ablage: URL) -> [String] {
        (FileManager.default.enumerator(at: ablage, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { url in
                guard let d = try? Data(contentsOf: url) else { return false }
                return NeuePlanungImportPruefungen.traegtWort(String(decoding: d, as: UTF8.self), "Zellgewebe")
            }
            .map(\.lastPathComponent)
    }

    @Test("⌘O ohne Planung und ohne Verschlüsselung: Das Entsperr-Blatt kommt, um die Planung zu übernehmen — keine Abweisung")
    func beginntUebernahme() throws {
        let ablage = try ordner("beginnt"), quelle = try ordner("beginnt-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        s.importieren(von: try fremdeDatei(quelle).datei)
        #expect(s.entsperrungUebernimmt, "das Entsperren gilt der Übernahme")
        #expect(s.offenerDialog == .entsperren, "das Blatt steht")
        #expect(s.tresor == nil && s.planung == nil, "vor der Passphrase ist nichts übernommen")
    }

    @Test("Mit der Passphrase der Datei: Die Planung ist da, die Ablage versiegelt unter ihrem Schlüssel, nichts im Klartext")
    func uebernimmtMitPassphrase() async throws {
        let ablage = try ordner("passphrase"), quelle = try ordner("passphrase-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let (datei, blatt) = try fremdeDatei(quelle)
        s.importieren(von: datei)
        await s.entsperren(passphrase: passphrase)
        #expect(s.planung?.titel == "Biologie 2026/27", "die Planung ist übernommen")
        #expect(s.tresor != nil, "die Verschlüsselung ist eingeschaltet")
        #expect(s.meldungen.contains { $0.text == "Planung „Biologie 2026/27“ geöffnet. Die Ablage auf diesem Mac ist jetzt "
                    + "verschlüsselt — mit der Passphrase und dem Wiederherstellungsschlüssel der Datei." }, "die Meldung (E715)")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("Verschlüsselung eingeschaltet") }, "nicht die allgemeine des Übergangs")
        #expect(s.verschluesselungsfrage == .offen, "ohne Frage 1 bleibt sie offen — die Sicherungskopie ist „Frage 1 von 3“ (E355)")
        try await versiegeltUnterDenSchluesselnDerDatei(s, ablage, wiederherstellung: blatt)
    }

    @Test("Mit dem Wiederherstellungsschlüssel der Datei ebenso — er öffnet danach auch die Ablage")
    func uebernimmtMitWiederherstellung() async throws {
        let ablage = try ordner("blatt"), quelle = try ordner("blatt-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let (datei, blatt) = try fremdeDatei(quelle)
        s.importieren(von: datei)
        await s.entsperren(wiederherstellung: blatt)
        #expect(s.planung?.titel == "Biologie 2026/27", "die Planung ist übernommen")
        #expect(s.tresor != nil, "die Verschlüsselung ist eingeschaltet")
        try await versiegeltUnterDenSchluesselnDerDatei(s, ablage, wiederherstellung: blatt)
    }

    @Test("Mit einer Vorbereitung aus Frage 1: Die Schlüssel der Datei gelten, die vorbereiteten nicht, und die Meldung sagt es (E719, Z-AW1b-07)")
    func uebernimmtMitVorbereitung() async throws {
        let ablage = try ordner("vorbereitet"), quelle = try ordner("vorbereitet-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let eigenesBlatt = try s.verschluesselungVorbereiten(passphrase: "Eigene Passphrase 2026")
        // Wie nach „Weiter zur Planung“ in Frage 1 (Z-AW1bM-03).
        s.verschluesselungsfrage = .vorbereitet
        s.offenerDialog = .neuePlanung
        let (datei, blatt) = try fremdeDatei(quelle)
        s.importieren(von: datei)
        await s.entsperren(passphrase: passphrase)
        #expect(s.planung?.titel == "Biologie 2026/27" && s.tresor != nil, "übernommen und eingeschaltet")
        #expect(s.vorbereitung == nil, "die Vorbereitung ist fort")
        #expect(s.verschluesselungsfrage == .ersetzt, "Frage 2 sagt, dass die Vorbereitung verworfen ist (E720)")
        #expect(Planungsspeicher.ersteinrichtungFragen(schritt: .sicherung, frage: s.verschluesselungsfrage) == 4,
                "die Sicherungskopie ist „Frage 2 von 4“ (E355)")
        #expect(s.meldungen.contains { $0.text == "Planung „Biologie 2026/27“ geöffnet. Die Ablage auf diesem Mac ist jetzt "
                    + "verschlüsselt — mit der Passphrase und dem Wiederherstellungsschlüssel der Datei. Der beim Einrichten "
                    + "notierte Wiederherstellungsschlüssel gilt nicht." }, "die Meldung (E719)")
        try await versiegeltUnterDenSchluesselnDerDatei(s, ablage, wiederherstellung: blatt)
        let gelesen = try? Data(contentsOf: s.sicherung.ablage.datei)
        let kopf = try #require(gelesen.flatMap { try? Tresor.kopfLesen($0) })
        let eigene = try? Tresor.oeffnen(kopf: kopf, passphrase: "Eigene Passphrase 2026")
        let eigenesOeffnet = try? Tresor.oeffnen(kopf: kopf, wiederherstellung: eigenesBlatt)
        #expect(eigene == nil, "die vorbereitete Passphrase öffnet die Ablage nicht")
        #expect(eigenesOeffnet == nil, "der beim Einrichten notierte Wiederherstellungsschlüssel ebenso wenig (Z-AW1bN-04)")
    }

    @Test("Frage 1 der Ersteinrichtung auf ihrer ersten Seite zählt wie „Neue Planungsdatei“: Die Übernahme beginnt, ohne Ton (E716)")
    func ausFrage1() async throws {
        let ablage = try ordner("frage1"), quelle = try ordner("frage1-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        s.ersteinrichtungsschritt = .verschluesselung
        s.offenerDialog = .ersteinrichtung
        let toene = s.systemtoene
        s.importieren(von: try fremdeDatei(quelle).datei)
        #expect(s.entsperrungUebernimmt, "die Übernahme beginnt")
        #expect(s.systemtoene == toene, "ohne Ton")
        #expect(s.offenerDialog == nil && s.naechsterDialog == .entsperren, "Frage 1 weicht dem Blatt „Planung übernehmen“")
        await s.entsperren(passphrase: passphrase)
        #expect(s.tresor != nil, "übernommen")
        let beginn = Planungsspeicher.ersteinrichtungBeginn(verschluesselt: s.verschluesselt, frage: s.verschluesselungsfrage)
        #expect(beginn == .sicherung && Planungsspeicher.ersteinrichtungFragen(schritt: beginn, frage: s.verschluesselungsfrage) == 4,
                "danach „Frage 2 von 4“ — Frage 1 stand schon (E355, Z-AW1bN-05)")
        #expect(s.verschluesselungsfrage == .uebernommen && !s.uebernahmeAusFrage1, "Frage 1 ist mit der Übernahme beantwortet")
    }

    @Test("Aus Frage 1 begonnen, abgebrochen, später aus dem Leerzustand übernommen: Frage 1 stand — „Frage 2 von 4“ (Z-AW1bM-01, E355)")
    func ausFrage1NachAbbrechen() async throws {
        let ablage = try ordner("frage1-abbrechen"), quelle = try ordner("frage1-abbrechen-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let datei = try fremdeDatei(quelle).datei
        s.ersteinrichtungsschritt = .verschluesselung
        s.offenerDialog = .ersteinrichtung
        s.importieren(von: datei)
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == .entsperren, "das Blatt „Planung übernehmen“ steht")
        s.entsperrungAbbrechen()
        #expect(s.offenerDialog == nil && s.entsperrung == nil, "abgebrochen — der Leerzustand")
        s.importieren(von: datei)
        await s.entsperren(passphrase: passphrase)
        #expect(s.tresor != nil, "übernommen")
        #expect(Planungsspeicher.ersteinrichtungFragen(schritt: .sicherung, frage: s.verschluesselungsfrage) == 4,
                "Frage 1 stand — die Sicherungskopie ist „Frage 2 von 4“")
    }

    @Test("Ein Dateifehler in Frage 1 bleibt wie hinter jedem Blatt: Ton sofort, der Text nach dem Blatt — Frage 1 zeigt keine Meldungen (Z-AW1bN-01)")
    func dateifehlerInFrage1() async throws {
        let ablage = try ordner("frage1-fehler"), quelle = try ordner("frage1-fehler-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.ersteinrichtungsschritt = .verschluesselung
        s.offenerDialog = .ersteinrichtung
        let toene = s.systemtoene
        s.importieren(von: quelle.appending(component: "fort.json"))
        #expect(s.systemtoene == toene + 1, "der Ton sofort")
        #expect(!s.meldungen.contains { $0.text.contains("fort.json") }, "unter dem Blatt noch kein Text")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.last?.text == "„fort.json“ ist nicht mehr da und wurde nicht geöffnet."
        }, hoechstens: .seconds(1))
        #expect(gesehen, "nach dem Blatt der Text")
    }

    @Test("G3-01: Eine Planung im Klartext aus Frage 1 — die Meldung erst nach dem Blatt, wie ein Dateifehler (Z-AW1bM-05)")
    func klartextAusFrage1() async throws {
        let ablage = try ordner("frage1-klartext"), quelle = try ordner("frage1-klartext-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.ersteinrichtungsschritt = .verschluesselung
        s.offenerDialog = .ersteinrichtung
        let datei = quelle.appending(component: "Biologie 2026-27.json")
        try Planungsdatei.schreiben(try planung()).write(to: datei)
        s.importieren(von: datei)
        #expect(s.planung?.titel == "Biologie 2026/27", "die Planung ist da")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("Planung „Biologie 2026/27“ geladen.") }, "unter Frage 1 noch kein Text")
        #expect(s.verlustUnterDerErsteinrichtung == nil, "ohne Verlust keine Zeile im Blatt (E779)")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.contains { $0.text.hasPrefix("Planung „Biologie 2026/27“ geladen.") }
        }, hoechstens: .seconds(1))
        #expect(gesehen, "nach dem Blatt der Text")
    }

    @Test("Z-AW10N-03: Nach einer Planung im Klartext aus Frage 1 führt „Überspringen“ zu Frage 2 im selben Blatt, nicht zu „Neue Planung“")
    func klartextAusFrage1WeiterZuFrage2() throws {
        let ablage = try ordner("frage1-weiter"), quelle = try ordner("frage1-weiter-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        s.ersteinrichtungsschritt = .verschluesselung
        s.offenerDialog = .ersteinrichtung
        let datei = quelle.appending(component: "Biologie 2026-27.json")
        try Planungsdatei.schreiben(try planung()).write(to: datei)
        s.importieren(von: datei)
        s.ersteinrichtungUeberspringen()
        #expect(s.ersteinrichtungsschritt == .sicherung && s.offenerDialog == .ersteinrichtung,
                "weiter mit der Sicherungskopie im selben Blatt")
    }

    /// Eine Planung im Klartext mit einem Vorhaben, dessen Zeile es nicht gibt — beim Lesen übergangen („1 Vorhaben“).
    private func dateiMitVerlust(_ quelle: URL) throws -> URL {
        let geschrieben = try JSONSerialization.jsonObject(with: try Planungsdatei.schreiben(try planung()))
        var objekt = try #require(geschrieben as? [String: Any])
        var eintraege = try #require(objekt["eintraege"] as? [Any])
        eintraege.append(["id": "e-fremd", "klasseId": "k-gibt-es-nicht", "woche": 1, "titel": "Ohne Zeile"])
        objekt["eintraege"] = eintraege
        let datei = quelle.appending(component: "Biologie 2026-27.json")
        try JSONSerialization.data(withJSONObject: objekt).write(to: datei)
        return datei
    }

    @Test("E779: Eine Planung mit Verlust aus Frage 1 — sofort eine Zeile im Blatt, die Meldung nach dem Blatt (Z-AW10N-04)")
    func verlustzeileAusFrage1() async throws {
        let ablage = try ordner("frage1-verlust"), quelle = try ordner("frage1-verlust-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.ersteinrichtungsschritt = .verschluesselung
        s.offenerDialog = .ersteinrichtung
        s.importieren(von: try dateiMitVerlust(quelle))
        #expect(s.planung?.titel == "Biologie 2026/27", "die Planung ist da")
        #expect(s.verlustUnterDerErsteinrichtung == "Biologie 2026/27", "die Zeile im Blatt nennt die Planung")
        #expect(Planungsspeicher.verlustzeileErsteinrichtung("Biologie 2026/27")
                == "Beim Öffnen von „Biologie 2026/27“ ist etwas übergangen — die Meldung folgt nach diesem Blatt.",
                "der Wortlaut (E779)")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("Planung „Biologie 2026/27“ geladen.") }, "unter Frage 1 noch kein Text")
        s.offenerDialog = nil
        #expect(s.verlustUnterDerErsteinrichtung == nil, "mit dem Blatt geht die Zeile")
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.contains { $0.text.hasPrefix("Planung „Biologie 2026/27“ geladen. Übergangen: 1 Vorhaben.") }
        }, hoechstens: .seconds(1))
        #expect(gesehen, "nach dem Blatt die Meldung mit dem Verlust")
    }

    @Test("Z-AW10N-05: Ist die Ersteinrichtung erst vorgemerkt, wartet die Meldung ebenso bis nach dem Blatt")
    func klartextVorDerErsteinrichtung() async throws {
        let ablage = try ordner("vor-frage1"), quelle = try ordner("vor-frage1-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.ersteinrichtungsschritt = .verschluesselung
        s.dialogVormerken(.ersteinrichtung)
        let datei = quelle.appending(component: "Biologie 2026-27.json")
        try Planungsdatei.schreiben(try planung()).write(to: datei)
        s.importieren(von: datei)
        #expect(s.planung?.titel == "Biologie 2026/27", "die Planung ist da")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("Planung „Biologie 2026/27“ geladen.") },
                "das kommende Blatt verdeckte den Text — er wartet")
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == .ersteinrichtung, "das Blatt steht")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.contains { $0.text.hasPrefix("Planung „Biologie 2026/27“ geladen.") }
        }, hoechstens: .seconds(1))
        #expect(gesehen, "nach dem Blatt der Text")
    }

    @Test("E849, Z-AX0b-03: Solange ein Blatt vorgemerkt ist, öffnet die Prüfung die Ersteinrichtung nicht selbst — sie käme sonst doppelt")
    func ersteinrichtungNichtUeberVorgemerktes() throws {
        let ablage = try ordner("vorgemerkt-schranke")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = ersterStart(ablage)
        s.planung = try planung()
        s.ersteinrichtungFortsetzen = true
        s.dialogVormerken(.ersteinrichtung)
        s.ersteinrichtungPruefen()
        #expect(s.offenerDialog == nil && s.naechsterDialog == .ersteinrichtung,
                "nichts direkt geöffnet, die Einrichtung bleibt vorgemerkt")
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == .ersteinrichtung, "das Blatt steht")
        s.offenerDialog = nil
        #expect(s.naechsterDialog == nil, "kein zweites Mal")
        // Der Merker fiel mit dem Aufgehen — sonst öffnete die nächste Prüfung das Blatt noch einmal (Z-AX9M-01).
        s.ersteinrichtungPruefen()
        #expect(s.offenerDialog == nil, "auch die nächste Prüfung öffnet es nicht wieder (Z-AX9M-01)")
    }

    @Test("Z-AX9T3-01: In der Folge der Hauptansicht — erst das Vorgemerkte öffnen, dann prüfen — nimmt die Einrichtung die Fortsetzung mit; sie kommt nicht ein zweites Mal")
    func ersteinrichtungVorgemerktInDerFolgeDerHauptansicht() throws {
        let ablage = try ordner("vorgemerkt-folge")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = ersterStart(ablage)
        s.planung = try planung()
        s.ersteinrichtungFortsetzen = true
        s.dialogVormerken(.ersteinrichtung)
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == .ersteinrichtung, "das Blatt steht")
        s.ersteinrichtungPruefen()
        s.offenerDialog = nil
        s.ersteinrichtungPruefen()
        #expect(s.offenerDialog == nil, "nach dem Schließen kein zweites Mal")
    }

    @Test("E849: Ist die Einrichtung fällig, schließt „Neue Planungsdatei“ mit ihr als nächstem Blatt, nach „Überspringen“ bei Frage 2, eine Fortsetzung bei ihrem Schritt — sonst nur zu (Z-AX9M-02)")
    func neuePlanungSchliessenFaellig() throws {
        let ablage = try ordner("neue-schliessen-faellig"), andere = try ordner("neue-schliessen-nicht-faellig")
        let weiter = try ordner("neue-schliessen-fortsetzung")
        defer {
            try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: andere)
            try? FileManager.default.removeItem(at: weiter)
        }
        let s = ersterStart(ablage)
        s.verschluesselungsfrage = .uebersprungen
        s.ersteinrichtungsschritt = .passphrase
        s.offenerDialog = .neuePlanung
        s.neuePlanungSchliessen(ersteinrichtungFaellig: true)
        #expect(s.offenerDialog == nil && s.naechsterDialog == .ersteinrichtung, "die Einrichtung ist vorgemerkt")
        #expect(s.ersteinrichtungsschritt == .sicherung, "nach „Überspringen“ beginnt sie bei Frage 2")
        let t = ersterStart(andere)
        t.offenerDialog = .neuePlanung
        t.neuePlanungSchliessen(ersteinrichtungFaellig: false)
        #expect(t.offenerDialog == nil && t.naechsterDialog == nil, "nicht fällig: nur zu")
        // Eine Fortsetzung geht vor, auch wenn die Einrichtung fällig ist: dort weiter, wo sie stand (Z-AX9M-02).
        let u = ersterStart(weiter)
        u.ersteinrichtungFortsetzen = true
        u.ersteinrichtungsschritt = .updates
        u.offenerDialog = .neuePlanung
        u.neuePlanungSchliessen(ersteinrichtungFaellig: true)
        #expect(u.ersteinrichtungsschritt == .updates, "die Fortsetzung bleibt bei ihrem Schritt")
        #expect(u.offenerDialog == nil && u.naechsterDialog == .ersteinrichtung, "die Einrichtung ist vorgemerkt")
        // Der Merker steht, bis sie aufgeht — fiele die Vormerkung weg, ginge die Fortsetzung sonst verloren (Z-AX9T3N-01).
        #expect(u.ersteinrichtungFortsetzen, "der Merker steht bis zum Aufgehen")
        u.naechstenDialogOeffnen()
        #expect(u.offenerDialog == .ersteinrichtung && !u.ersteinrichtungFortsetzen, "aufgegangen, der Merker fällt")
    }

    /// Im Prüflauf ist die Ersteinrichtung nie fällig (`Ablage.istPruefstand`); die Fortsetzung steht hier für „sie kommt
    /// gleich“ — wie in `ersteinrichtungPruefen` öffnet sie das Blatt ohne die Schranke `ersteinrichtungFaellig`.
    @Test("E849, Z-AX0b-03: Nach „Neue Planungsdatei“ eine Datei mit Verlust — die Ersteinrichtung ist schon vorgemerkt: Zeile im Blatt, Meldung danach")
    func neuePlanungDannErsteinrichtung() async throws {
        let ablage = try ordner("neue-dann-einrichtung"), quelle = try ordner("neue-dann-einrichtung-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.offenerDialog = .neuePlanung
        s.ersteinrichtungFortsetzen = true
        s.importieren(von: try dateiMitVerlust(quelle))
        #expect(s.planung?.titel == "Biologie 2026/27", "die Planung ist da")
        #expect(s.offenerDialog == nil && s.naechsterDialog == .ersteinrichtung, "die Einrichtung ist vorgemerkt")
        #expect(s.verlustUnterDerErsteinrichtung == "Biologie 2026/27", "die Zeile im Blatt (E779)")
        #expect(!s.meldungen.contains { $0.text.hasPrefix("Planung „Biologie 2026/27“ geladen.") }, "die Meldung wartet")
        // Wie der Wechsel auf „Planung da“ in der Hauptansicht: Der Merker steht noch, bis die Einrichtung aufgeht — die
        // Schranke hält sie zurück, solange sie vorgemerkt ist (Z-AX9M-02, Z-AX9T3N-01).
        s.angeboteUndFragenPruefen()
        #expect(s.offenerDialog == nil, "nichts direkt geöffnet")
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == .ersteinrichtung, "das Blatt steht")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.contains { $0.text.hasPrefix("Planung „Biologie 2026/27“ geladen. Übergangen: 1 Vorhaben.") }
        }, hoechstens: .seconds(1))
        #expect(gesehen, "nach dem Blatt die Meldung mit dem Verlust")
    }

    @Test("Z-AX0b-02: Fällt eine vorgemerkte Ersteinrichtung weg, geht die Zeile mit der Meldung — keine veraltete Zusage im nächsten Blatt")
    func verlustzeileMitDerMeldung() async throws {
        let ablage = try ordner("vorgemerkt-weg"), quelle = try ordner("vorgemerkt-weg-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.ersteinrichtungsschritt = .verschluesselung
        s.dialogVormerken(.ersteinrichtung)
        s.importieren(von: try dateiMitVerlust(quelle))
        try #require(s.verlustUnterDerErsteinrichtung == "Biologie 2026/27", "die Zeile steht")
        s.alleDialogeSchliessen()
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.contains { $0.text.hasPrefix("Planung „Biologie 2026/27“ geladen. Übergangen: 1 Vorhaben.") }
        }, hoechstens: .seconds(1))
        #expect(gesehen, "die Meldung kommt")
        #expect(s.verlustUnterDerErsteinrichtung == nil, "mit ihr geht die Zeile")
    }

    @Test("E777: Ohne Planung erklärt der Fuß von Frage 1 „Planung öffnen …“; mit Planung bleibt er (G3-03)")
    func frage1Fuss() {
        #expect(ErsteinrichtungDialog.frage1Fuss(vorDerPlanung: true)
                == "Eingeschaltet wird erst mit „Planung anlegen“ im nächsten Blatt; bis dahin ist nichts geschehen. "
                   + "„Planung öffnen …“ übernimmt stattdessen eine Planung eines anderen Macs — eine versiegelte mit "
                   + "ihrer Passphrase und ihrem Wiederherstellungsschlüssel. Der Rückweg bleibt offen: "
                   + "„Verschlüsselung aufheben“ unter „Einstellungen“.")
        #expect(ErsteinrichtungDialog.frage1Fuss(vorDerPlanung: false)
                == "Eingeschaltet ist erst nach dem bestätigten Wiederherstellungsblatt; bis dahin ist nichts geschehen. "
                   + "Der Rückweg bleibt offen: „Verschlüsselung aufheben“ unter „Einstellungen“.")
    }

    @Test("Ohne Planung hinter einem anderen Blatt — Frage 1 schon bei der Passphrase: abgewiesen wie hinter jedem Blatt, nichts begonnen (Z-AW1b-10)")
    func hinterAnderemBlatt() async throws {
        let ablage = try ordner("hinter-blatt"), quelle = try ordner("hinter-blatt-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        s.ersteinrichtungsschritt = .passphrase
        s.offenerDialog = .ersteinrichtung
        let toene = s.systemtoene
        s.importieren(von: try fremdeDatei(quelle).datei)
        #expect(!s.entsperrungOffen && s.offenerDialog == .ersteinrichtung, "nichts begonnen, das Blatt bleibt")
        #expect(s.systemtoene == toene + 1, "der Ton sofort")
        #expect(!s.meldungen.contains { $0.text.contains("Biologie 2026-27.json") }, "hinter dem Blatt noch kein Text")
        s.offenerDialog = nil
        let gesehen = await uhr.vorruecken(bis: {
            s.meldungen.last?.text == "„Biologie 2026-27.json“ wurde nicht geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen."
        }, hoechstens: .seconds(1))
        #expect(gesehen, "nach dem Blatt der Text")
    }

    @Test("Dieselbe Datei erneut geöffnet, während das Übernahme-Blatt steht: nur der Ton, kein Text — auch nach „Abbrechen“ (Z-AW1b-09, wie Z-AS3-01)")
    func dieselbeDateiStill() async throws {
        let ablage = try ordner("dieselbe"), quelle = try ordner("dieselbe-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        let uhr = Stelluhr()
        s.takt = uhr
        defer { uhr.abraeumen() }
        let datei = try fremdeDatei(quelle).datei
        s.importieren(von: datei)
        #expect(s.entsperrungUebernimmt && s.offenerDialog == .entsperren)
        let toene = s.systemtoene
        s.importieren(von: datei)
        s.importieren(von: quelle.appending(component: "andere.json"))
        #expect(s.systemtoene == toene + 2, "je der Ton sofort")
        s.entsperrungAbbrechen()
        // Die Gegenprobe im selben Lauf: Eine andere Datei bekommt ihren Text nach dem Blatt (wie Z-AS3-01).
        let andere = await uhr.vorruecken(bis: {
            s.meldungen.last?.text == "„andere.json“ wurde nicht geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen."
        }, hoechstens: .seconds(1))
        #expect(andere, "nach dem Blatt der Text zur anderen Datei")
        let erschienen = await uhr.vorruecken(bis: { s.meldungen.contains { $0.text.hasPrefix("„Biologie 2026-27.json“") } },
                                              hoechstens: .seconds(1))
        #expect(!erschienen, "kein Text zur selben Datei")
    }

    @Test("Abbrechen aus „Neue Planungsdatei“ mit einer Vorbereitung aus Frage 1: keine Planung, kein Schlüssel, die Vorbereitung liegt weiter bereit (Z-AW1b-10)")
    func abbrechenAusNeuerPlanungsdatei() throws {
        let ablage = try ordner("abbrechen-neu"), quelle = try ordner("abbrechen-neu-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        _ = try s.verschluesselungVorbereiten(passphrase: "Eigene Passphrase 2026")
        let vorbereitet = try #require(s.vorbereitung)
        s.verschluesselungsfrage = .vorbereitet
        s.offenerDialog = .neuePlanung
        s.importieren(von: try fremdeDatei(quelle).datei)
        #expect(s.entsperrungUebernimmt, "die Übernahme beginnt")
        s.entsperrungAbbrechen()
        #expect(s.planung == nil && s.tresor == nil && s.entsperrung == nil, "nichts übernommen")
        #expect(s.vorbereitung === vorbereitet, "die Vorbereitung liegt weiter bereit")
    }

    @Test("Einschalten scheitert (Ordner schreibgeschützt): nicht geöffnet, nichts geschrieben, die Vorbereitung aus Frage 1 bleibt")
    func einschaltenScheitert() async throws {
        let ablage = try ordner("scheitert"), quelle = try ordner("scheitert-quelle")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ablage.path)
            try? FileManager.default.removeItem(at: ablage)
            try? FileManager.default.removeItem(at: quelle)
        }
        let s = ersterStart(ablage)
        _ = try s.verschluesselungVorbereiten(passphrase: "Eigene Passphrase 2026")
        let vorbereitet = try #require(s.vorbereitung)
        _ = try #require(s.vorbereitungGeraet, "die Vorbereitung trägt ihr Gerät")
        s.nachEinrichtung = {}
        // Wie nach „Weiter zur Planung“ in Frage 1 (Z-AW1bM-03).
        s.verschluesselungsfrage = .vorbereitet
        s.offenerDialog = .neuePlanung
        s.importieren(von: try fremdeDatei(quelle).datei)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ablage.path)
        await s.entsperren(passphrase: passphrase)
        #expect(s.planung == nil && s.tresor == nil, "nichts geöffnet, nichts eingeschaltet")
        #expect(s.vorbereitung === vorbereitet, "die Vorbereitung aus Frage 1 liegt wieder bereit")
        #expect(s.vorbereitungGeraet != nil, "samt ihrem Gerät")
        #expect(s.nachEinrichtung != nil, "und der Fortsetzung")
        #expect(s.verschluesselungsfrage == .vorbereitet, "Frage 1 bleibt vorbereitet")
        #expect(s.meldungsfang == nil, "der Fang ist wieder zu")
        let warnungen = s.meldungen.filter { $0.art == .warnung }.map(\.text)
        #expect(warnungen.count == 1
                && warnungen.first?.hasPrefix("„Biologie 2026/27“ wurde nicht geöffnet — die Verschlüsselung ließ sich "
                                              + "nicht einschalten (") == true
                && warnungen.first?.hasSuffix("). Auf diesem Mac bleibt alles, wie es war.") == true, "\(warnungen)")
        #expect(!FileManager.default.fileExists(atPath: s.sicherung.ablage.datei.path), "keine Planung in der Ablage")
    }

    @Test("Abbrechen lässt alles, wie es war: keine Planung, keine Verschlüsselung, nichts in der Ablage")
    func abbrechenAendertNichts() throws {
        let ablage = try ordner("abbrechen"), quelle = try ordner("abbrechen-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        s.importieren(von: try fremdeDatei(quelle).datei)
        s.entsperrungAbbrechen()
        #expect(s.planung == nil && s.tresor == nil && s.entsperrung == nil, "nichts übernommen")
        #expect(!FileManager.default.fileExists(atPath: s.sicherung.ablage.datei.path), "keine Planung in der Ablage")
    }

    @Test("Ist eine Planung im Klartext offen, bleibt die Abweisung mit dem Weg über „Einstellungen“")
    func mitPlanungAbgewiesen() throws {
        let ablage = try ordner("klartext"), quelle = try ordner("klartext-quelle")
        defer { try? FileManager.default.removeItem(at: ablage); try? FileManager.default.removeItem(at: quelle) }
        let s = ersterStart(ablage)
        s.planung = try planung()
        s.jetztSichern()
        s.importieren(von: try fremdeDatei(quelle).datei)
        #expect(!s.entsperrungUebernimmt && s.tresor == nil, "keine Übernahme über einer offenen Planung")
        #expect(s.meldungen.last?.text == "Die Datei ist verschlüsselt, die Ablage auf diesem Mac ist es nicht. "
                + "Bitte zuerst unter „Einstellungen“ die Verschlüsselung einschalten, dann die Datei erneut öffnen.")
    }
}
