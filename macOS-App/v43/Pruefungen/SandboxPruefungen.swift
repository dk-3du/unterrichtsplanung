// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

/// Das App Sandbox: die Lesezeichen (hier ohne Sicherheitsbereich — das
/// Prüfziel trägt das Entitlement nicht; den Bereich belegt `--ordnertest` am
/// gesiegelten Paket), der Container, die Prüfstände darin und die Nachwahl.
@Suite("Sandbox: Ordnerzugriff, Container, Nachwahl")
@MainActor
struct SandboxPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    /// Ein eigener Vorrat je Prüfung — wie ihn jeder Sicherungsdienst führt;
    /// im Prüflauf bleibt er im Speicher.
    private let zugriff = Ordnerzugriff(ablage: .shared)

    /// Ein eigener Ordner je Prüfung; das Lesezeichen dazu wird am Ende vergessen.
    private func ordner(_ name: String = "zugriff") throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func aufraeumen(_ orte: URL...) {
        for ort in orte {
            zugriff.vergessen(ort.path)
            try? FileManager.default.removeItem(at: ort)
        }
    }

    // ── Ohne Sandbox ────────────────────────────────────────────────

    @Test("Das Prüfziel läuft ohne Sandbox — und sagt es so")
    func ohneSandbox() {
        #expect(!Ordnerzugriff.imSandbox)
        #expect(Ablage.container == nil)
        #expect(Ablage.pruefordnerZulaessig)
        #expect(zugriff.erreichbar("/nicht/da/\(UUID().uuidString).pdf"),
                "ohne Sandbox ist jeder Ort erreichbar — ob er existiert, sagt das nicht")
        // Kein „kein Zugriff“ ohne Sandbox: Ein fehlender Ort fehlt.
        if case .fehlt = Systemzugriff.dateiOeffnen("/nicht/da/\(UUID().uuidString).pdf", zugriff: zugriff) {} else {
            Issue.record("ohne Sandbox heißt ein fehlender Ort „nicht gefunden“")
        }
    }

    // ── Lesezeichen ─────────────────────────────────────────────────

    @Test("Ein Lesezeichen deckt den Ordner und alles darunter; das nächstliegende gilt")
    func zustaendig() throws {
        let wurzel = try ordner()
        let unten = wurzel.appending(component: "unten", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unten, withIntermediateDirectories: true)
        defer { aufraeumen(unten, wurzel) }

        let datei = unten.path + "/datei.pdf"
        #expect(zugriff.zustaendig(fuer: datei) == nil)

        let eintrag = try zugriff.merken(wurzel)
        #expect(eintrag == Ordnerzugriff.kanonisch(wurzel.path))
        #expect(zugriff.zustaendig(fuer: datei) == eintrag)
        #expect(zugriff.zustaendig(fuer: wurzel.path + "/") == eintrag, "Endschrägstrich zählt nicht")
        #expect(zugriff.zustaendig(fuer: wurzel.path + "-anderer/x.pdf") == nil,
                "ein gleicher Anfang im Namen ist kein Unterordner")
        #expect(zugriff.zustaendig(fuer: unten.path + "/../oben.pdf") == eintrag,
                "`..` wird zusammengefasst")

        let untenEintrag = try zugriff.merken(unten)
        #expect(zugriff.zustaendig(fuer: datei) == untenEintrag, "das nächstliegende Lesezeichen")
        #expect(zugriff.zustaendig(fuer: wurzel.path + "/oben.pdf") == eintrag)
        #expect(zugriff.alle.contains(eintrag) && zugriff.alle.contains(untenEintrag))
    }

    @Test("Auflösen liefert den Pfad; die Arbeit läuft mit ihm")
    func aufloesenUndMit() throws {
        let wurzel = try ordner()
        defer { aufraeumen(wurzel) }
        let datei = wurzel.appending(component: "notiz.txt")
        try Data("Inhalt".utf8).write(to: datei)

        try zugriff.merken(wurzel)
        #expect(try zugriff.aufloesen(datei.path).path == Ordnerzugriff.kanonisch(datei.path))
        let gelesen = try zugriff.mit(datei.path) { try String(contentsOf: $0, encoding: .utf8) }
        #expect(gelesen == "Inhalt")
    }

    @Test("Ein verschobener Ordner wird über das Lesezeichen wiedergefunden, der Schlüssel nachgeführt")
    func verschobenerOrdner() throws {
        let wurzel = try ordner("wandert")
        let vorher = wurzel.appending(component: "vorher", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vorher, withIntermediateDirectories: true)
        let datei = vorher.appending(component: "notiz.txt")
        try Data("Inhalt".utf8).write(to: datei)
        let nachher = wurzel.appending(component: "nachher", directoryHint: .isDirectory)
        defer { aufraeumen(nachher, vorher, wurzel) }

        let alterEintrag = try zugriff.merken(vorher)
        try FileManager.default.moveItem(at: vorher, to: nachher)

        let verlegt = try zugriff.aufloesen(datei.path)
        #expect(verlegt.path == Ordnerzugriff.kanonisch(nachher.path) + "/notiz.txt")
        #expect(try zugriff.mit(datei.path) { try String(contentsOf: $0, encoding: .utf8) }
                == "Inhalt")
        #expect(zugriff.zustaendig(fuer: nachher.path) != nil, "der neue Ort hat sein Lesezeichen")
        #expect(zugriff.alle.contains(alterEintrag),
                "der alte Schlüssel bleibt als Zweitname — die Planungsdatei kennt den alten Pfad")
    }

    @Test("Ohne Lesezeichen ein benannter Fehler — und ein gelöschter Ordner ebenso")
    func benannteFehler() throws {
        let fremd = "/nicht/da/\(UUID().uuidString)/datei.pdf"
        #expect(throws: Ordnerzugriff.Fehler.self) { try zugriff.aufloesen(fremd) }
        do {
            _ = try zugriff.aufloesen(fremd)
        } catch let fehler as Ordnerzugriff.Fehler {
            #expect(fehler.art == .keinLesezeichen)
            #expect(fehler.text.contains("noch nicht zugreifen"))
            #expect(fehler.text.contains("datei.pdf"))
        }

        let wurzel = try ordner("weg")
        try zugriff.merken(wurzel)
        try FileManager.default.removeItem(at: wurzel)
        defer { zugriff.vergessen(wurzel.path) }
        do {
            _ = try zugriff.aufloesen(wurzel.path + "/x.pdf")
            Issue.record("ein gelöschter Ordner löst nicht auf")
        } catch let fehler as Ordnerzugriff.Fehler {
            #expect(fehler.art == .unaufloesbar)
            #expect(fehler.text.contains("nicht wiederfinden"))
        }
    }

    @Test("Ein Ort, der nicht existiert, lässt sich nicht merken")
    func merkenScheitertBenannt() {
        let fremd = URL(fileURLWithPath: "/nicht/da/\(UUID().uuidString)", isDirectory: true)
        #expect(throws: Ordnerzugriff.Fehler.self) { try zugriff.merken(fremd) }
    }

    @Test("Im Prüflauf bleiben Lesezeichen und Zielordner im Speicher, nicht in den Einstellungen")
    func prueflaufSchreibtNichts() throws {
        let wurzel = try ordner()
        defer { aufraeumen(wurzel) }
        try zugriff.merken(wurzel)
        zugriff.zielordner = wurzel.path
        #expect(zugriff.zielordner == wurzel.path && zugriff.quelle == .einstellungen)
        #expect(!zugriff.hatEinstellungsspeicher, "ein Prüflauf bekommt keinen Einstellungsspeicher")
    }

    // ── Container und Prüfstände ────────────────────────────────────

    @Test("Ein Prüfordner zählt im Sandbox nur unterhalb des Containers")
    func pruefordnerImContainer() throws {
        let container = try ordner("Container")
        defer { try? FileManager.default.removeItem(at: container) }
        let innen = container.path + "/tmp/pruefung"
        let aussen = URL.temporaryDirectory.path + "/anderswo"

        #expect(Ablage.pruefordnerZulaessig("", container: container), "ohne Prüfordner gilt nichts")
        #expect(Ablage.pruefordnerZulaessig(aussen, container: nil), "ohne Sandbox überall")
        #expect(Ablage.pruefordnerZulaessig(innen, container: container))
        #expect(Ablage.pruefordnerZulaessig(container.path, container: container))
        #expect(!Ablage.pruefordnerZulaessig(aussen, container: container))
        #expect(!Ablage.pruefordnerZulaessig(container.path + "-daneben/x", container: container))
        // `/var` und `/private/var` sind derselbe Ort.
        let privat = container.path.hasPrefix("/private") ? String(container.path.dropFirst(8)) : "/private" + container.path
        #expect(Ablage.pruefordnerZulaessig(privat + "/tmp", container: container))
    }

    @Test("Ein Abbild außerhalb des Containers wandert in den Prüfordner")
    func abbildziel() throws {
        let container = try ordner("Container")
        defer { try? FileManager.default.removeItem(at: container) }
        let pruefordner = container.appending(component: "tmp/pruefung", directoryHint: .isDirectory)
        let innen = container.appending(component: "tmp/abbild.png")
        let aussen = URL(fileURLWithPath: "/Users/lehrkraft/Schreibtisch/abbild.png")

        #expect(Selbstabbild.abbildziel(innen, container: container, pruefordner: pruefordner) == innen)
        #expect(Selbstabbild.abbildziel(aussen, container: container, pruefordner: pruefordner)
                == pruefordner.appendingPathComponent("abbild.png", isDirectory: false))
        #expect(Selbstabbild.abbildziel(aussen, container: nil, pruefordner: pruefordner) == aussen,
                "ohne Sandbox bleibt der Wunsch")
    }

    // ── Nachwahl ────────────────────────────────────────────────────

    private func planung(basis: String) throws -> Planung {
        Planung.leer(titel: "Nachwahl", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                     basis: basis, klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                     fachfarben: [:])
    }

    @Test("Ohne Sandbox und ohne Vorgabe steht nichts aus")
    func nichtsAusstehend() throws {
        let speicher = Planungsspeicher(vorschau: try planung(basis: "/Users/lehrkraft/Unterricht"))
        speicher.nachwahlPruefen()
        #expect(speicher.ausstehendeFreigaben.isEmpty)
        #expect(speicher.offenerDialog == nil)
    }

    @Test("Vorgegebene Ordner ohne Lesezeichen öffnen das Blatt — „Später“ gilt für die Sitzung")
    func nachwahlBlatt() throws {
        let speicher = Planungsspeicher(vorschau: try planung(basis: ""))
        speicher.nachwahlVorgeben(zielordner: "/Users/lehrkraft/Kopie", basis: "/Users/lehrkraft/Unterricht")
        #expect(speicher.ausstehendeFreigaben.map(\.pfad)
                == ["/Users/lehrkraft/Kopie", "/Users/lehrkraft/Unterricht"])
        #expect(speicher.ausstehendeFreigaben.map(\.titel)
                == ["Ordner der Sicherungskopie", "Basisordner der Materialien"])

        speicher.nachwahlPruefen()
        #expect(speicher.offenerDialog == .nachwahl)

        speicher.nachwahlSpaeter()
        #expect(speicher.offenerDialog == nil)
        speicher.nachwahlPruefen()
        #expect(speicher.offenerDialog == nil, "in dieser Sitzung nicht noch einmal")
        #expect(!speicher.ausstehendeFreigaben.isEmpty, "ausstehend bleibt es")
    }

    @Test("Ein gemerkter Ordner steht nicht mehr aus — auch ein Ordner darüber deckt ihn")
    func freigabeErteilt() throws {
        let wurzel = try ordner("basis")
        let basis = wurzel.appending(component: "Unterricht", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: basis, withIntermediateDirectories: true)
        defer { aufraeumen(basis, wurzel) }

        let speicher = Planungsspeicher(vorschau: try planung(basis: ""))
        speicher.nachwahlVorgeben(zielordner: "", basis: basis.path)
        #expect(speicher.ausstehendeFreigaben.map(\.zweck) == [.basisordner])

        try speicher.zugriff.merken(wurzel)
        speicher.nachwahlPruefen()
        #expect(speicher.ausstehendeFreigaben.isEmpty, "der Ordner darüber gilt für alles darin")
        #expect(speicher.offenerDialog == nil)
    }

    @Test("Der Zielordner der Kopie: ohne Sandbox reicht der Pfad, ein Lesezeichen kommt beim Setzen")
    func zielordnerLesezeichen() throws {
        let ziel = try ordner("kopie")
        defer { aufraeumen(ziel) }
        let speicher = Planungsspeicher(vorschau: try planung(basis: ""))
        speicher.autoexportZielSetzen(ziel.path)
        #expect(speicher.zugriff.zustaendig(fuer: ziel.path) != nil)
        #expect(speicher.ausstehendeFreigaben.isEmpty)
    }
}
