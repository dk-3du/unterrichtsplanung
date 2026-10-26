// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Erststart: Frage 1 vor „Neue Planung“ (v84, AT6: D1b, E349, E355, E477 b, E531, E535–E538) ──
// Ohne Planung kommt zuerst die Frage nach der Verschlüsselung; „Überspringen“ und das bestätigte Blatt führen zu
// „Neue Planung“, eingeschaltet wird mit „Planung anlegen“. Danach beginnt die Einrichtung bei „Frage 2 von 4“.
// „Abbrechen“ in „Neue Planung“, eine geöffnete Datei statt der neuen Planung und ein zurückgenommenes Einschalten
// verwerfen die Vorbereitung; Frage 1 steht dann wieder. Im Prüfstand ist die Einrichtung nie fällig — die Wege
// am echten ersten Start geht `--erststarttest` (Lauf 02 der Runde).

@Suite("Erststart: Frage 1 vor „Neue Planung“, Merker, Nummerierung")
@MainActor
struct ErststartFolgePruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "erststart-folge-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    /// Ein Speicher wie beim ersten Start, das Blatt „Neue Planung“ zu.
    private func ersterStart(_ ordner: URL) -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        s.starten()
        s.offenerDialog = nil
        return s
    }

    /// Frage 1 vor der Planung, wie `neuePlanungOeffnen()` sie am echten ersten Start aufschlägt.
    private func frageEins(_ s: Planungsspeicher) {
        s.ersteinrichtungsschritt = .verschluesselung
        s.offenerDialog = .ersteinrichtung
    }

    /// Frage 1 → „Verschlüsselung einrichten …“ → Passphrase → bestätigtes Blatt → „Weiter zur Planung“.
    private func vorbereiten(_ s: Planungsspeicher) throws {
        frageEins(s)
        s.ersteinrichtungEinrichten()
        try s.ersteinrichtungWeiter(passphrase: passphrase)
        guard case .blatt = s.ersteinrichtungsschritt else {
            Issue.record("erwartet: Blatt, war \(s.ersteinrichtungsschritt)")
            return
        }
        s.ersteinrichtungZurPlanung()
    }

    /// „Planung anlegen“ wie im Blatt: Eingeschaltet wird, was Frage 1 vorbereitet hat (E531).
    private func anlegen(_ s: Planungsspeicher) throws {
        s.neuePlanung(titel: "Erststart", start: try #require(Tag(iso: "2026-08-10")), wochen: 6, basis: "",
                      klassen: Standardkurse.aufbauen([("05G", "Biologie")]), ersterSchultag: nil, uebernahme: [],
                      einschalten: s.einschaltenBeimAnlegen)
    }

    /// Wie viele Fragen das Blatt beim Öffnen zählt — die Unterzeile „Frage n von …“.
    private func fragen(_ s: Planungsspeicher) -> Int {
        Planungsspeicher.ersteinrichtungFragen(schritt: s.ersteinrichtungsschritt, frage: s.verschluesselungsfrage)
    }

    /// Ein Ordner, dessen Wiederanlauf blockiert (E67) — wie in `FrageortPruefungen`.
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
        for name in [Uebergangsdienst.markenname, Uebergangsdienst.zweitschriftname] {
            try Data("{\"typ\":\"unterrichtsplanung-uebergang\",\"version\":9".utf8)
                .write(to: ablage.appending(component: name))
        }
    }

    @Test("Ohne Planung bei fälliger Einrichtung erst Frage 1 — beim ersten Start und nach einem Verwerfen")
    func vorDerPlanung() {
        let f = Planungsspeicher.verschluesselungsfrageVorDerPlanung
        #expect(f(false, true, false, .offen, true), "erster Start")
        #expect(f(false, true, false, .verworfen, true), "nach dem Verwerfen (E477 b)")
        #expect(!f(true, true, false, .offen, true), "mit Planung fragt die Einrichtung danach")
        #expect(!f(false, false, false, .offen, true), "im Prüfstand oder nach der Einrichtung")
        #expect(!f(false, true, true, .offen, true), "schon verschlüsselt")
        #expect(!f(false, true, false, .uebersprungen, true), "übersprungen: gleich „Neue Planung“")
        #expect(!f(false, true, false, .vorbereitet, true), "vorbereitet: gleich „Neue Planung“")
        #expect(!f(false, true, false, .offen, false), "„Planung anlegen“ dürfte nicht anlegen (Z-AT6-01)")
    }

    @Test("Im Prüfstand öffnet „Neue Planung“ wie bisher ohne Frage 1")
    func imPruefstandGleichNeuePlanung() throws {
        let ordner = try ordner("pruefstand")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        s.neuePlanungOeffnen()
        #expect(s.offenerDialog == .neuePlanung)
        #expect(s.verschluesselungsfrage == .offen)
    }

    @Test("„Überspringen“ vor der Planung führt zu „Neue Planung“; danach „Frage 2 von 4“ (E355)")
    func ueberspringenZurPlanung() throws {
        let ordner = try ordner("ueberspringen")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        frageEins(s)
        s.ersteinrichtungUeberspringen()
        #expect(s.verschluesselungsfrage == .uebersprungen)
        #expect(s.offenerDialog == nil && s.naechsterDialog == .neuePlanung,
                "das Blatt der Einrichtung geht, „Neue Planung“ kommt danach")
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == .neuePlanung)
        #expect(!s.einschaltenBeimAnlegen, "übersprungen: nichts einzuschalten")
        try anlegen(s)
        #expect(s.planung != nil && !s.verschluesselt)
        s.offenerDialog = nil
        s.ersteinrichtungOeffnen()
        #expect(s.ersteinrichtungsschritt == .sicherung, "nach der Planung weiter bei der Sicherungskopie")
        #expect(fragen(s) == 4, "„Frage 2 von 4“")
    }

    @Test("Vorbereitet vor der Planung: „Planung anlegen“ schaltet ein (E531); danach „Frage 2 von 4“")
    func vorbereitetEingeschaltet() throws {
        let ordner = try ordner("vorbereitet")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        try vorbereiten(s)
        #expect(s.verschluesselungsfrage == .vorbereitet && s.vorbereitung != nil, "vorbereitet")
        #expect(s.tresor == nil, "eingeschaltet ist noch nichts")
        #expect(s.offenerDialog == nil && s.naechsterDialog == .neuePlanung, "weiter zu „Neue Planung“")
        s.naechstenDialogOeffnen()
        #expect(s.einschaltenBeimAnlegen, "„Planung anlegen“ schaltet ein")
        try anlegen(s)
        #expect(s.verschluesselt && s.vorbereitung == nil, "eingeschaltet beim Anlegen")
        #expect(!s.einschaltenBeimAnlegen, "mit Planung nie mehr")
        s.offenerDialog = nil
        s.ersteinrichtungOeffnen()
        #expect(s.ersteinrichtungsschritt == .sicherung && fragen(s) == 4, "„Frage 2 von 4“")
    }

    @Test("„Abbrechen“ in „Neue Planung“ verwirft die Vorbereitung; das nächste „Neue Planung“ führt über Frage 1 (E477 b)")
    func abbrechenVerwirft() throws {
        let ordner = try ordner("abbrechen")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        try vorbereiten(s)
        s.naechstenDialogOeffnen()
        s.neuePlanungAbbrechen()
        #expect(s.vorbereitung == nil && s.verschluesselungsfrage == .verworfen, "verworfen")
        #expect(Planungsspeicher.verschluesselungsfrageVorDerPlanung(
                    hatPlanung: s.hatPlanung, faellig: true, verschluesselt: s.verschluesselt,
                    frage: s.verschluesselungsfrage, anlegbar: s.planungAnlegbar),
                "das nächste „Neue Planung“ führt über Frage 1")
        #expect(!s.einschaltenBeimAnlegen)
        s.offenerDialog = nil
        try anlegen(s)
        #expect(s.planung != nil && !s.verschluesselt, "ohne Vorbereitung im Klartext")
        #expect(s.verschluesselungEinschalten().ablage == .zurueckgenommen("es liegt keine Vorbereitung vor"),
                "ein Einschalten danach findet keine Vorbereitung")
    }

    @Test("„Abbrechen“ verwirft nur, was Frage 1 vorbereitet hat (E531)")
    func abbrechenLaesstAndereVorbereitung() throws {
        let ordner = try ordner("andere")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        // Eine Vorbereitung, die nicht aus Frage 1 stammt — schon vor der Planung (Z-AT6-05).
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        s.offenerDialog = .neuePlanung
        #expect(!s.einschaltenBeimAnlegen, "eine liegende Vorbereitung schaltet nicht ein")
        s.neuePlanungAbbrechen()
        #expect(s.vorbereitung != nil && s.verschluesselungsfrage == .offen, "unberührt")
        try anlegen(s)
        #expect(s.planung != nil && !s.verschluesselt && s.vorbereitung != nil, "angelegt im Klartext, die Vorbereitung liegt")
        s.offenerDialog = .neuePlanung
        s.neuePlanungAbbrechen()
        #expect(s.vorbereitung != nil && s.verschluesselungsfrage == .offen, "auch mit Planung unberührt")
    }

    @Test("Eine Datei statt „Planung anlegen“ (⌘O): Verworfen, Frage 1 steht wieder (E477 b)")
    func dateiStattPlanung() throws {
        let ordner = try ordner("datei")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        try vorbereiten(s)
        s.naechstenDialogOeffnen()
        let fremd = Planung.leer(titel: "Fremd", start: try #require(Tag(iso: "2026-08-10")), wochen: 4,
                                 basis: "", klassen: Standardkurse.aufbauen([("6a", "")]), fachfarben: [:])
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "fremd.json"))
        #expect(s.planung?.titel == "Fremd" && !s.verschluesselt, "geladen, nicht eingeschaltet")
        s.offenerDialog = nil
        s.ersteinrichtungOeffnen()
        #expect(s.vorbereitung == nil && s.verschluesselungsfrage == .verworfen, "verworfen")
        #expect(s.ersteinrichtungsschritt == .verschluesselung && fragen(s) == 4, "„Frage 1 von 4“ mit dem Satz")
    }

    @Test("Zurückgenommenes Einschalten beim Anlegen (E478): Danach steht Frage 1 wieder, mit dem Satz")
    func ruecknahme() throws {
        let ordner = try ordner("ruecknahme")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ordner.path)
            try? FileManager.default.removeItem(at: ordner)
        }
        let s = ersterStart(ordner)
        try vorbereiten(s)
        s.naechstenDialogOeffnen()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ordner.path)
        try anlegen(s)
        #expect(s.planung != nil && !s.verschluesselt, "angelegt, nicht eingeschaltet")
        s.offenerDialog = nil
        s.ersteinrichtungOeffnen()
        #expect(s.verschluesselungsfrage == .verworfen && s.ersteinrichtungsschritt == .verschluesselung,
                "Frage 1 steht wieder, mit dem Satz")
    }

    @Test("Keine Frage 1, wo „Planung anlegen“ nicht anlegen darf: bei einer Blockade des Wiederanlaufs (Z-AT6-01)")
    func blockadeOhneFrageEins() throws {
        let ablage = try ordner("blockade")
        defer { try? FileManager.default.removeItem(at: ablage) }
        try blockierenderOrdner(ablage)
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.starten()
        #expect(s.blockadeOffen && !s.hatPlanung && !s.verschluesselt, "blockiert, ohne Planung, im Klartext")
        #expect(!s.planungAnlegbar, "„Planung anlegen“ würde abgewiesen")
        let f = Planungsspeicher.verschluesselungsfrageVorDerPlanung
        #expect(f(s.hatPlanung, true, s.verschluesselt, .offen, true), "ohne die Schranke käme hier Frage 1")
        #expect(!f(s.hatPlanung, true, s.verschluesselt, .offen, s.planungAnlegbar),
                "mit ihr: ⌘N geht gleich zu „Neue Planung“, wie vor AT6")
        try anlegen(s)
        #expect(s.planung == nil, "„Planung anlegen“ wird abgewiesen — dieselbe Schranke")
        // Dass der Getter `verschluesselungsfrageVorDerPlanung` die Schranke weitergibt, prüft keine Prüfung: Im Prüfstand
        // ist die Einrichtung nie fällig (Z-AT6N-01).
    }

    @Test("Ein zweites „Überspringen“, während Frage 1 noch schließt, öffnet „Neue Planung“ nicht mitten im Schließen (Z-AT6-02)")
    func zweimalUeberspringen() throws {
        let ordner = try ordner("zweimal")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        frageEins(s)
        s.ersteinrichtungUeberspringen()
        s.ersteinrichtungUeberspringen()
        #expect(s.offenerDialog == nil && s.naechsterDialog == .neuePlanung,
                "vorgemerkt, nicht mitten im Schließen geöffnet: \(String(describing: s.offenerDialog))")
        s.naechstenDialogOeffnen()
        #expect(s.offenerDialog == .neuePlanung && s.naechsterDialog == nil, "einmal geöffnet, nichts mehr vorgemerkt")
    }

    @Test("Während Frage 1 nach „Weiter zur Planung“ schließt, ändern „Abbrechen“ und ⌘N nichts (Z-AT6N-02)")
    func imSchliessenNichts() throws {
        let ordner = try ordner("im-schliessen")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = ersterStart(ordner)
        try vorbereiten(s)
        #expect(s.offenerDialog == nil && s.naechsterDialog == .neuePlanung, "das Blatt schließt, „Neue Planung“ vorgemerkt")
        s.ersteinrichtungAbbrechen()
        var blatt = false
        if case .blatt = s.ersteinrichtungsschritt { blatt = true }
        #expect(s.vorbereitung != nil && s.verschluesselungsfrage == .vorbereitet && blatt,
                "„Abbrechen“ im schließenden Blatt verwirft nichts und wechselt nicht den Inhalt")
        s.neuePlanungOeffnen()
        #expect(s.offenerDialog == nil && s.naechsterDialog == .neuePlanung,
                "⌘N im Schließen: schon vorgemerkt — \(String(describing: s.offenerDialog))")
    }

    @Test("Beginn und Zahl der Fragen nach der Planung (E355)")
    func beginnUndFragen() {
        let b = Planungsspeicher.ersteinrichtungBeginn
        #expect(b(false, .offen) == .verschluesselung, "Bestand ohne Frage 1 vorweg")
        #expect(b(false, .uebersprungen) == .sicherung, "übersprungen vor der Planung")
        #expect(b(true, .vorbereitet) == .sicherung, "beim Anlegen eingeschaltet")
        #expect(b(false, .verworfen) == .verschluesselung, "verworfen: Frage 1 wieder")
        #expect(b(true, .offen) == .sicherung, "versiegelte erste Planung, wie bisher")
        let f = Planungsspeicher.ersteinrichtungFragen
        #expect(f(.sicherung, .offen) == 3, "versiegelte erste Planung ohne Frage 1: drei Fragen, wie bisher")
        #expect(f(.sicherung, .uebersprungen) == 4)
        #expect(f(.sicherung, .vorbereitet) == 4)
        #expect(f(.sicherung, .verworfen) == 4)
        #expect(f(.verschluesselung, .offen) == 4)
    }
}
