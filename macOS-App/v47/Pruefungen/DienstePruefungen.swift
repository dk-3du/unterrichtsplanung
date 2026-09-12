// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Die Dienste mit hereingereichter Ablage ───────────────────────────────
// Sicherung, Statusabgleich und Updates lassen sich mit einem Temp-Ordner
// prüfen — ohne `Ablage.shared`, ohne Speicher, ohne Fenster.

@Suite("Dienste: Sicherung, Statusabgleich, Updates")
@MainActor
struct DienstePruefungen {

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung(_ titel: String = "Dienst") throws -> Planung {
        var p = Planung.leer(titel: titel, start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Bits",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    private func tresor() throws -> Tresor {
        let t = Tresor.neu()
        try t.passphraseSetzen("Ein Satz, den man behält", runden: Tresor.rundenMindestens)
        return t
    }

    // ── Sicherungsdienst ──────────────────────────────────────────────────

    @Test("Sofort und entprellt landet die Sitzung in der hereingereichten Ablage — Klartext wie versiegelt")
    func sicherungInEigenerAblage() async throws {
        let ordner = try ordner("sicherung")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let ablage = Ablage(ordner: ordner)
        let dienst = Sicherungsdienst(ablage: ablage)
        var p = try planung("Sofort")
        p.geaendert = "2026-09-01T10:00:00.000Z"
        dienst.sitzungsquelle = { .klartext(p) }

        dienst.jetztSichern()
        #expect(try Planungsdatei.lesen(try Data(contentsOf: ablage.datei)).titel == "Sofort")
        #expect(dienst.gesicherterStand == p.geaendert)
        #expect(dienst.letzteSicherung != nil)
        #expect(!dienst.gestoert && !dienst.liegtStill)

        // Derselbe Stand geht nicht ein zweites Mal auf die Platte.
        dienst.jetztSichern()
        #expect(ablage.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse) == nil, "kein zweiter Schreibvorgang, keine Vorgängerfassung")

        // Ein neuer Stand, versiegelt, über den entprellten Weg.
        let t = try tresor()
        p.titel = "Versiegelt"
        p.geaendert = "2026-09-01T10:00:01.000Z"
        dienst.sitzungsquelle = { .verschluesselt(p, t) }
        dienst.sichern()
        for _ in 0..<60 where dienst.gesicherterStand != p.geaendert {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(dienst.gesicherterStand == p.geaendert)
        let roh = try Data(contentsOf: ablage.datei)
        #expect(Tresor.istBehaelter(roh))
        #expect(try Planungsdatei.lesen(try t.oeffnen(roh)).titel == "Versiegelt")
        #expect(ablage.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse) != nil, "der Klartext-Stand davor liegt daneben")

        // Die Hülle wechselt ohne Änderung an der Planung: erzwungen neu.
        dienst.neuSchreibenErzwingen()
        #expect(dienst.gesicherterStand == nil)
        dienst.jetztSichern()
        #expect(dienst.gesicherterStand == p.geaendert)
        #expect(Tresor.istBehaelter(try #require(ablage.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse))),
                "die Vorgängerfassung ist jetzt der versiegelte Stand")
    }

    @Test("Gesperrt, leer oder ohne Schlüssel wird nichts geschrieben; eine Vorschau liegt nicht still")
    func gesperrtSchreibtNicht() throws {
        let ordner = try ordner("gesperrt")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let ablage = Ablage(ordner: ordner)
        let dienst = Sicherungsdienst(ablage: ablage)
        let p = try planung()

        dienst.gesperrt = true
        dienst.sitzungsquelle = { .klartext(p) }
        dienst.jetztSichern()
        #expect(!FileManager.default.fileExists(atPath: ablage.datei.path))
        #expect(dienst.liegtStill)

        dienst.gesperrt = false
        dienst.sitzungsquelle = { .leer }
        dienst.jetztSichern()
        dienst.sitzungsquelle = { .gesperrt(.ablage(Data()), nil) }
        dienst.jetztSichern()
        #expect(!FileManager.default.fileExists(atPath: ablage.datei.path))
        #expect(!dienst.gestoert, "nichts zu schreiben ist keine Störung")

        let vorschau = Sicherungsdienst(ablage: ablage, vorschau: true)
        vorschau.gesperrt = true
        #expect(vorschau.istVorschau && !vorschau.liegtStill)
    }

    @Test("Eine Störung wird einmal gemeldet und mit dem nächsten Gelingen gelöscht")
    func stoerung() throws {
        let wurzel = try ordner("stoerung")
        defer { try? FileManager.default.removeItem(at: wurzel) }
        // Eine Datei, wo der Ordner der Ablage sein müsste: Schreiben scheitert.
        let versperrt = wurzel.appending(component: "ablage", directoryHint: .notDirectory)
        try Data("im Weg".utf8).write(to: versperrt)
        let dienst = Sicherungsdienst(ablage: Ablage(ordner: versperrt))
        var gemeldet = 0
        dienst.melden = { _, _ in gemeldet += 1 }
        var p = try planung()
        p.geaendert = "2026-09-01T10:00:00.000Z"
        dienst.sitzungsquelle = { .klartext(p) }

        dienst.jetztSichern()
        #expect(dienst.gestoert && dienst.liegtStill)
        #expect(gemeldet == 1)
        dienst.jetztSichern()
        #expect(gemeldet == 1, "einmal je Wechsel, kein Nachbohren")

        dienst.lageMelden(nil)
        #expect(!dienst.gestoert)
        dienst.lageMelden(.schreiben)
        #expect(gemeldet == 2)
        // Eine andere Art ist ein Wechsel; dieselbe mit anderer Größe nicht.
        dienst.lageMelden(.zuGross(1))
        dienst.lageMelden(.zuGross(2))
        #expect(gemeldet == 3 && dienst.stoerung == .zuGross(2))
        dienst.lageMelden(nil)
        #expect(!dienst.gestoert && dienst.stoerung == nil)
    }

    @Test("Die Startsperre hebt sich nur, wenn der unlesbare Stand beiseiteliegt — und die Fassung davor bekommt ihren Stempel")
    func startsperre() throws {
        let ordner = try ordner("startsperre")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let ablage = Ablage(ordner: ordner)
        try Data("{kein JSON".utf8).write(to: ablage.datei)
        try Planungsdatei.schreiben(try planung("Davor")).write(to: ablage.vorherigeFassung)
        let dienst = Sicherungsdienst(ablage: ablage)
        dienst.gesperrt = true
        dienst.startsperre = true

        dienst.startsperreAufheben()
        #expect(!dienst.startsperre && !dienst.gesperrt && !dienst.gestoert)
        let liegt = try FileManager.default.contentsOfDirectory(atPath: ordner.path).sorted()
        #expect(!liegt.contains("planung.json"), "der unlesbare Stand liegt beiseite")
        #expect(liegt.contains { $0.hasPrefix("planung-beschaedigt-") })
        #expect(liegt.contains { $0.hasPrefix("planung-vorher-") && $0 != "planung-vorher.json" },
                "die Fassung davor ist gestempelt kopiert")

        // Ohne Startsperre ist nichts zu heben.
        dienst.gesperrt = true
        dienst.startsperreAufheben()
        #expect(dienst.gesperrt)
    }

    @Test("Die Kopie außer Haus: nur verschlüsselt, in den Zielordner — jedes Hindernis hat einen Namen")
    func kopie() throws {
        let ablageOrdner = try ordner("kopie-ablage")
        let ziel = try ordner("kopie-ziel")
        defer {
            try? FileManager.default.removeItem(at: ablageOrdner)
            try? FileManager.default.removeItem(at: ziel)
        }
        let dienst = Sicherungsdienst(ablage: Ablage(ordner: ablageOrdner))
        dienst.kopieOrdner = ziel.path
        let p = try planung("Kopie")
        let t = try tresor()

        #expect(throws: Sicherungsdienst.Kopiehindernis.self) {
            try dienst.kopieSchreiben(.klartext(p), name: "Kopie.json")
        }
        do {
            _ = try dienst.kopieSchreiben(.klartext(p), name: "Kopie.json")
        } catch {
            guard case .keinTresor = error else { Issue.record("erwartet .keinTresor"); return }
        }
        do {
            _ = try dienst.kopieSchreiben(.leer, name: "Kopie.json")
        } catch {
            guard case .nichtsZuSchreiben = error else { Issue.record("erwartet .nichtsZuSchreiben"); return }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: ziel.path).isEmpty)

        let (datei, groesse) = try dienst.kopieSchreiben(.verschluesselt(p, t), name: "Kopie.json")
        #expect(datei.lastPathComponent == "Kopie.json")
        let roh = try Data(contentsOf: datei)
        #expect(Tresor.istBehaelter(roh) && groesse == roh.count, "die gemeldete Größe ist die der Datei")
        #expect(try Planungsdatei.lesen(try t.oeffnen(roh)).titel == "Kopie")
        #expect(dienst.letzteKopie != nil)

        dienst.kopieOrdner = ziel.appending(component: "gibt-es-nicht").path
        do {
            _ = try dienst.kopieSchreiben(.verschluesselt(p, t), name: "Kopie.json")
            Issue.record("ein fehlender Zielordner muss werfen")
        } catch {
            guard case .zielordner(.fehlt) = error else { Issue.record("erwartet .zielordner(.fehlt)"); return }
        }
    }

    @Test("Die Statusdatei aus dem Zielordner: keine, eine, eine zu große — ein fehlender Ordner bleibt still")
    func statusdatei() throws {
        let ablageOrdner = try ordner("status-ablage")
        let ziel = try ordner("status-ziel")
        defer {
            try? FileManager.default.removeItem(at: ablageOrdner)
            try? FileManager.default.removeItem(at: ziel)
        }
        let dienst = Sicherungsdienst(ablage: Ablage(ordner: ablageOrdner))
        dienst.kopieOrdner = ziel.path
        #expect(try dienst.statusdateiLesen() == nil)

        let datei = ziel.appending(component: Statusdatei.name)
        try Data("{}".utf8).write(to: datei)
        #expect(try dienst.statusdateiLesen() == Data("{}".utf8))

        try Data(count: Statusdatei.hoechstgroesse + 1).write(to: datei)
        #expect(throws: Sicherungsdienst.Statusdateilage.zuGross(Statusdatei.hoechstgroesse + 1)) {
            try dienst.statusdateiLesen()
        }

        dienst.kopieOrdner = ziel.appending(component: "weg").path
        #expect(try dienst.statusdateiLesen() == nil, "das meldet sich beim Schreiben der Kopie, nicht hier")
    }

    // ── Statusabgleich ────────────────────────────────────────────────────

    @Test("Entsiegeln: Klartext nur ohne Schlüssel; fremder Schlüssel, falscher Inhalt, fehlender Schlüssel und Klartext bei versiegelter Ablage werden benannt")
    func entsiegeln() throws {
        let stand = Statusstand(gespeichert: "2026-09-01T10:00:00.000Z", planungstitel: "Dienst",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "vom iPad")])
        let klar = try Statusdatei.schreiben(stand)
        let t = try tresor()

        #expect(try Statusabgleich.entsiegeln(klar, tresor: nil) == klar)
        #expect(throws: Statusabgleich.Hindernis.klartextNichtErlaubt) {
            try Statusabgleich.entsiegeln(klar, tresor: t)
        }

        let behaelter = try t.versiegeln(klar, inhalt: .status, ziel: .kopie)
        #expect(throws: Statusabgleich.Hindernis.verschluesseltOhneTresor) {
            try Statusabgleich.entsiegeln(behaelter, tresor: nil)
        }
        #expect(try Statusabgleich.entsiegeln(behaelter, tresor: t) == klar)

        let anderer = try tresor()
        #expect(throws: Statusabgleich.Hindernis.fremderSchluessel) {
            try Statusabgleich.entsiegeln(try anderer.versiegeln(klar, inhalt: .status, ziel: .kopie), tresor: t)
        }
        #expect(throws: Statusabgleich.Hindernis.keinStatus("planung")) {
            try Statusabgleich.entsiegeln(
                try t.versiegeln(try Planungsdatei.schreiben(try planung()), inhalt: .planung, ziel: .kopie),
                tresor: t)
        }

        // Eine Wicklung der Ansicht bleibt in der Datei — der Schlüsselkopf der
        // Ablage ändert sich durch einen Statusabgleich nie.
        let traeger = Tresor(schluessel: t.schluessel, kennung: t.kennung,
                             wicklungen: t.wicklungen + [Wicklung(art: "passkey", felder: ["kennung": .text("p-1")])])
        #expect(try Statusabgleich.entsiegeln(
            try traeger.versiegeln(klar, inhalt: .status, ziel: .kopie), tresor: t) == klar)
        #expect(!t.hat("passkey"))

        #expect(try Statusabgleich.lesen(klar) == stand)
        #expect(throws: Statusabgleich.Hindernis.self) { try Statusabgleich.lesen(Data("{kein".utf8)) }
        for hindernis: Statusabgleich.Hindernis in [.klartextNichtErlaubt, .verschluesseltOhneTresor,
                                                    .keinStatus("x"), .fremderSchluessel,
                                                    .nichtEntsiegelt("g"), .unlesbar("g")] {
            #expect(hindernis.text.contains("Statusdatei aus der iPad-Ansicht"))
        }
    }

    @Test("Klartext-Status bei versiegelter Ablage: bekannte Kennung, jüngerer Stempel — die Planung bleibt, wie sie ist")
    func klartextBeiTresorBleibtWirkungslos() throws {
        let ablageOrdner = try ordner("klartext-ablage")
        let ziel = try ordner("klartext-ziel")
        defer {
            try? FileManager.default.removeItem(at: ablageOrdner)
            try? FileManager.default.removeItem(at: ziel)
        }
        let speicher = Planungsspeicher(ablage: Ablage(ordner: ablageOrdner))
        speicher.sitzung = .verschluesselt(try planung(), try tresor())
        speicher.autoexportOrdner = ziel.path

        let stand = Statusstand(gespeichert: Zeitrechnung.jetztAlsZeitstempel(), planungstitel: "Dienst",
                                eintraege: ["e-1": .init(erledigt: true, kommentar: "untergeschoben")])
        try Statusdatei.schreiben(stand).write(to: ziel.appending(component: Statusdatei.name), options: [.atomic])
        speicher.statusUebernehmen()

        let eins = try #require(speicher.planung?.eintraege.first { $0.id == "e-1" })
        #expect(!eins.erledigt && eins.kommentar.isEmpty && eins.statusGeaendert.isEmpty)
        #expect(speicher.meldungen.contains { $0.art == .warnung && $0.text.contains("unverschlüsselt") })
        // Die Datei bleibt liegen, wie sie war.
        #expect(try Statusdatei.lesen(try Data(contentsOf: ziel.appending(component: Statusdatei.name))) == stand)
    }

    @Test("Anwenden: der jüngere Stand gilt, ein älterer nicht — und ein Stempel allein ist schon eine Änderung")
    func anwenden() throws {
        var p = try planung()
        let jung = Statusstand(gespeichert: "2026-09-01T10:00:00.000Z", planungstitel: "Dienst",
                               eintraege: ["e-1": .init(erledigt: true, kommentar: "vom iPad")])
        let erstes = Statusabgleich.anwenden(jung, auf: &p)
        #expect(erstes.erledigt == 1 && erstes.kommentare == 1 && erstes.geaendert)
        #expect(p.eintraege[0].erledigt && p.eintraege[0].kommentar == "vom iPad")
        #expect(p.eintraege[0].statusGeaendert == "2026-09-01T10:00:00.000Z")

        let nochmal = Statusabgleich.anwenden(jung, auf: &p)
        #expect(!nochmal.geaendert, "derselbe Stand ändert nichts mehr")

        let alt = Statusstand(gespeichert: "2026-08-01T10:00:00.000Z", planungstitel: "Dienst",
                              eintraege: ["e-1": .init(erledigt: false, kommentar: "")])
        #expect(!Statusabgleich.anwenden(alt, auf: &p).geaendert, "ein älterer Stand dreht nichts zurück")
        #expect(p.eintraege[0].erledigt)

        let zukunft = Statusstand(gespeichert: "2099-01-01T00:00:00.000Z", planungstitel: "Dienst",
                                  eintraege: ["e-1": .init(erledigt: false, kommentar: "")])
        #expect(!Statusabgleich.anwenden(zukunft, auf: &p).geaendert, "ein unbrauchbarer Stempel zählt nicht")

        // Nur der Stempel ist neu: gleiche Werte, aber die Schranke rückt vor.
        let gleich = Statusstand(gespeichert: "2026-09-02T10:00:00.000Z", planungstitel: "Dienst",
                                 eintraege: ["e-1": .init(erledigt: true, kommentar: "vom iPad")])
        let nurStempel = Statusabgleich.anwenden(gleich, auf: &p)
        #expect(nurStempel.erledigt == 0 && nurStempel.kommentare == 0 && nurStempel.geaendert)
        #expect(p.eintraege[0].statusGeaendert == "2026-09-02T10:00:00.000Z")
    }

    // ── Updatekoordinator ─────────────────────────────────────────────────

    @Test("Der Koordinator führt Einwilligung, Stand, Angebot und Meldung — und ruft zurück")
    func koordinator() throws {
        let k = Updatekoordinator(pruefstand: true, umgebung: [:])
        #expect(!k.gefragt && !k.erlaubt && k.angebot == nil && !k.laeuft)
        var angebote = 0
        k.beiAngebot = { angebote += 1 }
        var gesagt: [String] = []
        k.melden = { text, _ in gesagt.append(text) }

        k.erlauben(true)
        #expect(k.gefragt && k.erlaubt && !k.laeuft, "im Prüfstand geht nichts ins Netz")
        k.pruefen(erzwungen: true)
        #expect(gesagt.last?.contains("Prüfstand") == true)

        let ergebnis = Updateergebnis(befund: .neu(.probe), etag: "W/\"e\"", antwort: Data("{}".utf8))
        k.ergebnisUebernehmen(ergebnis, erzwungen: false)
        #expect(k.angebot == .probe && angebote == 1)
        #expect(k.meldung?.hasPrefix("Neu:") == true)
        #expect(k.stand.etag == "W/\"e\"" && k.stand.zuletzt != nil)
        k.spaeter()
        #expect(k.angebot == nil)

        k.vorgeben(.probe)
        k.ueberspringen()
        #expect(k.stand.uebersprungen == Veroeffentlichung.probe.build && k.angebot == nil)
        k.ergebnisUebernehmen(Updateergebnis(befund: .uebersprungen(.probe), etag: nil, antwort: nil), erzwungen: false)
        #expect(k.angebot == nil && angebote == 1, "übersprungen bleibt still")
        k.ergebnisUebernehmen(Updateergebnis(befund: .uebersprungen(.probe), etag: nil, antwort: nil), erzwungen: true)
        #expect(k.angebot == .probe && angebote == 2, "von Hand wird es gezeigt")
        #expect(k.seiteAbrufen() == Veroeffentlichung.probe.seite && k.angebot == nil)

        k.ergebnisUebernehmen(Updateergebnis(befund: .aktuell(.probe), etag: nil, antwort: nil), erzwungen: true)
        #expect(gesagt.last?.contains("neuesten Stand") == true)
        k.ergebnisUebernehmen(Updateergebnis(befund: .nichtErreichbar, etag: nil, antwort: nil), erzwungen: true)
        #expect(gesagt.last?.contains("GitHub") == true)

        #expect(!k.beimStartPruefen(hatPlanung: false))
        #expect(k.beimStartPruefen(hatPlanung: true))
        #expect(!k.beimStartPruefen(hatPlanung: true), "einmal je Start")
    }

    // ── Der Speicher mit eigener Ablage ───────────────────────────────────

    @Test("Ein Speicher mit eigener Ablage schreibt dorthin — ein zweiter am selben Ort liest es")
    func speicherMitEigenerAblage() throws {
        let ordner = try ordner("speicher")
        defer { try? FileManager.default.removeItem(at: ordner) }
        let ablage = Ablage(ordner: ordner)

        let erster = Planungsspeicher(ablage: ablage)
        erster.starten()
        #expect(erster.offenerDialog == .neuePlanung)
        erster.neuePlanung(titel: "Eigene Ablage", start: try #require(Tag(iso: "2026-08-10")),
                           wochen: 6, basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                           ersterSchultag: nil, uebernahme: [])
        erster.jetztSichern()
        #expect(try Planungsdatei.lesen(try Data(contentsOf: ablage.datei)).titel == "Eigene Ablage")
        #expect(erster.sicherung.ablage === ablage && !erster.sicherungLiegtStill)

        let zweiter = Planungsspeicher(ablage: ablage)
        zweiter.starten()
        #expect(zweiter.planung?.titel == "Eigene Ablage")
        #expect(zweiter.letzteSicherung != nil)
    }
}
