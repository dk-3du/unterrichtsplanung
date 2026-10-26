// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Schuljahreswechsel als Übergang (v80, AP5) ────────────────────────
// „Neue Planung“ mit eingeschalteter Verschlüsselung: Die bisherige Planung
// geht samt Jahresdatei ins Archiv, die neue Jahresdatei trägt die gewählten
// Gruppen — drei Dateien in einer Marke (`jahreswechsel`), alle alt oder alle
// neu. Ohne Verschlüsselung fragt die App vorher (E275); ⌘O mit einer Planung
// anderer Herkunft fragt und archiviert (E277).

@Suite("Schuljahreswechsel: drei Dateien in einem Übergang, Rückfragen")
@MainActor
struct JahreswechselPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private static let stempel = "2026-10-03T08:00:00.000Z"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "jahreswechsel-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie"), ("7b", "Chemie")]),
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Zellen",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    /// Zwei Gruppen an den beiden Klassen, je eine Person; eine offene Mitteilung in g-1.
    private func bestand(_ p: Planung) -> Lernendenbestand {
        let s = Self.stempel
        var b = Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-2", vorname: "Ben", nachname: "Bauer", angelegt: s, geaendert: s, archiviert: "")]
        b.lerngruppen = [
            Lerngruppe(id: "g-1", name: "6a", fach: "Biologie", art: .klasse, mitglieder: ["l-1"],
                       zeilen: [Zeilenbindung(planung: p.erstellt, klasseId: p.klassen[0].id)],
                       skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: ""),
            Lerngruppe(id: "g-2", name: "7b", fach: "Chemie", art: .klasse, mitglieder: ["l-2"],
                       zeilen: [Zeilenbindung(planung: p.erstellt, klasseId: p.klassen[1].id)],
                       skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: ""),
        ]
        b.anliegen = [Anliegen(id: "m-1", art: .mitteilung, titel: "Elternbrief", lerngruppe: "g-1", betroffene: ["l-1"],
                               datum: "2026-10-01", frist: "", notiz: "", angelegt: s, geaendert: s)]
        return b
    }

    /// Ein eingeschalteter Speicher mit Jahresdatei.
    private func speicher(_ ablage: URL) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        #expect(s.lernende.setzen(bestand(try #require(s.planung))) == nil)
        return s
    }

    /// „Neue Planung“ für 2027/28 mit Übernahme der Klasse 6a.
    private func neuesSchuljahr(_ s: Planungsspeicher) throws {
        let alt = try #require(s.planung)
        s.neuePlanung(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                      klassen: [], ersterSchultag: nil,
                      uebernahme: [Planung.Uebernahmewunsch(klasse: alt.klassen[0], mitVorhaben: false)])
    }

    private func keineSpur(_ ablage: URL) throws {
        let namen = try FileManager.default.contentsOfDirectory(atPath: ablage.path)
        #expect(!namen.contains(Uebergangsdienst.markenname) && !namen.contains(Uebergangsdienst.zweitschriftname), "\(namen)")
        #expect(!namen.contains { $0.hasSuffix(Uebergangsdienst.zwillingssuffix) || $0.hasSuffix(Uebergangsdienst.vorgaengersuffix) },
                "\(namen)")
    }

    @Test("Die Art des Übergangs hat einen Namen")
    func art() {
        #expect(Uebergangsart.jahreswechsel.rawValue == "jahreswechsel")
        #expect(Uebergangsart.jahreswechsel.beschreibung == "das Wechseln des Schuljahrs")
    }

    @Test("Neue Planung mit Verschlüsselung: bisherige Planung samt Jahresdatei im Archiv, neue Jahresdatei mit der übernommenen Gruppe")
    func neuePlanungArchiviert() async throws {
        let ablage = try ordner("neu")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let alt = try #require(s.planung)
        try neuesSchuljahr(s)
        let neu = try #require(s.planung)
        #expect(neu.titel == "Schuljahr 2027/28" && neu.erstellt != alt.erstellt)
        let jahresdatei = try #require(s.lernende.bestand)
        #expect(jahresdatei.planung == neu.erstellt && jahresdatei.schuljahr == "2027/28")
        #expect(jahresdatei.lerngruppen.map(\.id) == ["g-1"], "nur die Gruppe der übernommenen Klasse")
        #expect(jahresdatei.lerngruppen.first?.zeilen == [Zeilenbindung(planung: neu.erstellt, klasseId: try #require(neu.klassen.first).id)])
        #expect(jahresdatei.lernende.map(\.id) == ["l-1"] && jahresdatei.anliegen.map(\.id) == ["m-1"])
        guard case .gelesen(let archiv, _, _) = s.lernende.archivLesen(stempel: "p") else {
            Issue.record("das Archiv öffnet nicht")
            return
        }
        #expect(archiv.jahre.count == 1 && archiv.jahre.first?.schuljahr == "2026/27")
        #expect(archiv.jahre.first?.planung.titel == alt.titel && archiv.jahre.first?.lernende?.lernende.count == 2)
        #expect(s.meldungen.contains { $0.text.contains("im Archiv") }, "\(s.meldungen.map(\.text))")
        try keineSpur(ablage)

        // Ein zweiter Start findet alles drei im neuen Stand.
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablage))
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        #expect(zweiter.planung?.titel == "Schuljahr 2027/28")
        #expect(zweiter.lernende.bestand?.planung == neu.erstellt)
        if case .gelesen(let a, _, _) = zweiter.lernende.archivLesen(stempel: "p") {
            #expect(a.jahre.count == 1)
        } else {
            Issue.record("das Archiv öffnet nach dem Neustart nicht")
        }
    }

    @Test("Nach dem Wechsel trägt kein Tisch mehr eine Person, die die neue Jahresdatei nicht kennt (Z14c-04, E304)")
    func bindungenNachDemWechsel() throws {
        let ablage = try ordner("bindungen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let alt = try #require(s.planung)
        let plan = Sitzplan.anordnen(klasseId: alt.klassen[0].id, lernende: [.init(name: "Anna Abel", lernender: "l-1"),
                                                                             .init(name: "Ben Bauer", lernender: "l-2"),
                                                                             .init(name: "Person l-9", lernender: "l-9")])
        #expect(s.sitzplaene.setzen(plan, fuer: alt.klassen[0].id) == nil)
        let vorher = Set(s.meldungen.map(\.id))
        try neuesSchuljahr(s)
        #expect(s.lernende.bestand?.lernende.map(\.id) == ["l-1"], "nur die Person der übernommenen Gruppe")
        let danach = try #require(s.sitzplaene.plaene.values.first)
        #expect(danach.tische.map(\.lernender) == ["l-1", "", ""] && danach.tische.map(\.name) == ["Anna Abel", "Ben Bauer", "Person l-9"],
                Comment(rawValue: "\(danach.tische.map(\.lernender))"))
        // Ben still wie beim Wechsel, die ältere tote Bindung (l-9) mit genau einer Meldung (Z-AS5a-09).
        let gemeldet = s.meldungen.filter { !vorher.contains($0.id) && $0.text.contains("Zuordnung") }.map(\.text)
        #expect(gemeldet == [Self.geloestEins], Comment(rawValue: gemeldet.joined(separator: " | ")))
    }

    // ── AS5a: Abgleich der Sitzplanbindungen (C, E325, E345, E346) ─────────────

    private static let geloestEins = "Eine Zuordnung an einem Tisch wurde gelöst: Die Person steht nicht mehr in der "
        + "Lernendenverwaltung; der Name am Tisch bleibt."
    private static func geloest(_ n: Int) -> String {
        "\(n) Zuordnungen an Tischen wurden gelöst: Die Personen stehen nicht mehr in der Lernendenverwaltung; "
            + "die Namen an den Tischen bleiben."
    }

    /// Ein Plan an der ersten Klasse: Anna Abel (l-1) und Tische an Kennungen, die die Jahresdatei nicht trägt.
    private func planMitToten(_ s: Planungsspeicher, _ tote: [String]) throws -> String {
        let klasse = try #require(s.planung?.klassen.first?.id)
        let plan = Sitzplan.anordnen(klasseId: klasse, lernende: [.init(name: "Anna Abel", lernender: "l-1")]
                                     + tote.map { .init(name: "Person \($0)", lernender: $0) })
        #expect(s.sitzplaene.setzen(plan, fuer: klasse) == nil)
        return klasse
    }

    private func neu(_ s: Planungsspeicher, seit vorher: Int) -> [String] { s.meldungen.dropFirst(vorher).map(\.text) }

    @Test("Eine Bindung an eine Person, die die Jahresdatei nicht trägt, löst das Aufräumen — der Name bleibt, einmal gemeldet (C, E345, E346)")
    func toteBindungBeimAufraeumen() throws {
        let ablage = try ordner("tot-aufraeumen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let klasse = try planMitToten(s, ["l-9"])
        let vorher = s.meldungen.count
        s.sitzplaeneAufraeumen()  // wie nach dem Laden und nach dem Entsperren
        let plan = try #require(s.sitzplaene.plan(fuer: klasse))
        #expect(plan.tische.map(\.lernender) == ["l-1", ""] && plan.tische.map(\.name) == ["Anna Abel", "Person l-9"],
                Comment(rawValue: "\(plan.tische.map(\.lernender))"))
        #expect(neu(s, seit: vorher) == [Self.geloestEins], Comment(rawValue: neu(s, seit: vorher).joined(separator: " | ")))
    }

    @Test("Netz im Editor: Öffnen zeigt keine tote Bindung und meldet erst nach dem Schließen; Übernehmen schreibt keine zurück (C, E345, Z-AS5a-01, -04)")
    func toteBindungImEditor() async throws {
        let ablage = try ordner("tot-editor")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let klasse = try planMitToten(s, ["l-8", "l-9"])
        // Neue Meldungen über ihre Kennung — verfällt eine ältere, verrutscht kein Index (Z-AS5a-12).
        let vorher = Set(s.meldungen.map(\.id))
        func geloestNeu() -> [String] { s.meldungen.filter { !vorher.contains($0.id) && $0.text.contains("Zuordnung") }.map(\.text) }
        s.sitzplanOeffnen(klasse: klasse)
        #expect(s.sitzplanEntwurf?.tische.map(\.lernender) == ["l-1", "", ""],
                Comment(rawValue: "\(s.sitzplanEntwurf?.tische.map(\.lernender) ?? [])"))
        #expect(geloestNeu().isEmpty, "hinter dem Blatt noch nicht gemeldet")
        s.sitzplanDialogSchliessen()
        s.offenerDialog = nil  // das Blatt geht zu
        try await abwarten("die vorgemerkte Meldung") { !geloestNeu().isEmpty }
        #expect(geloestNeu() == [Self.geloest(2)], Comment(rawValue: geloestNeu().joined(separator: " | ")))
        var mitToter = try #require(s.sitzplaene.plan(fuer: klasse))
        mitToter.tische[1].lernender = "l-7"
        let davor = s.meldungen.count
        #expect(s.sitzplanUebernehmen(mitToter) == nil)
        #expect(s.sitzplaene.plan(fuer: klasse)?.tische.map(\.lernender) == ["l-1", "", ""],
                "das Übernehmen schreibt keine tote Bindung zurück")
        #expect(neu(s, seit: davor) == ["Sitzplan übernommen — 3 Plätze.", Self.geloestEins],
                Comment(rawValue: neu(s, seit: davor).joined(separator: " | ")))
    }

    @Test("Hauptweg von C: tote Bindung auf der Platte, Neustart, Entsperren — gelöst, der Name bleibt, einmal gemeldet (Z-AS5a-02)")
    func toteBindungNachNeustart() async throws {
        let ablage = try ordner("tot-neustart")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let klasse = try planMitToten(s, ["l-9"])
        s.jetztSichern()
        let zweiter = Planungsspeicher(ablage: Ablage(ordner: ablage))
        zweiter.starten()
        await zweiter.entsperren(passphrase: passphrase)
        let plan = try #require(zweiter.sitzplaene.plan(fuer: klasse))
        #expect(plan.tische.map(\.lernender) == ["l-1", ""] && plan.tische.map(\.name) == ["Anna Abel", "Person l-9"],
                Comment(rawValue: "\(plan.tische.map(\.lernender))"))
        #expect(zweiter.meldungen.map(\.text).filter { $0.contains("Zuordnung") } == [Self.geloestEins],
                Comment(rawValue: zweiter.meldungen.map(\.text).joined(separator: " | ")))
    }

    @Test("Eine archivierte Person bleibt gebunden — sie steht in der Jahresdatei (E252, Z-AS5a-03)")
    func archivierteBleibtGebunden() throws {
        let ablage = try ordner("tot-archiviert")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let p = try #require(s.planung)
        #expect(s.lernende.setzen(bestand(p).mitArchivierterPerson("l-2", jetzt: Self.stempel)) == nil)
        let klasse = try #require(p.klassen.first?.id)
        let plan = Sitzplan.anordnen(klasseId: klasse, lernende: [.init(name: "Anna Abel", lernender: "l-1"),
                                                                 .init(name: "Ben Bauer", lernender: "l-2"),
                                                                 .init(name: "Person l-9", lernender: "l-9")])
        #expect(s.sitzplaene.setzen(plan, fuer: klasse) == nil)
        let vorher = s.meldungen.count
        s.sitzplaeneAufraeumen()
        #expect(s.sitzplaene.plan(fuer: klasse)?.tische.map(\.lernender) == ["l-1", "l-2", ""], "die archivierte Person bleibt")
        #expect(neu(s, seit: vorher) == [Self.geloestEins], Comment(rawValue: neu(s, seit: vorher).joined(separator: " | ")))
    }

    @Test("Verwaiste Pläne ohne Klasse der Planung behalten ihre Bindungen — der Abgleich greift nur die Pläne der Klassen (Z-AS5a-05)")
    func verwaistePlaeneUnberuehrt() throws {
        let ablage = try ordner("tot-verwaist")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let plan = Sitzplan.anordnen(klasseId: "k-verwaist", lernende: [.init(name: "Person l-9", lernender: "l-9")])
        #expect(s.sitzplaene.setzen(plan, fuer: "k-verwaist") == nil)
        let vorher = s.meldungen.count
        s.sitzplanbindungenAbgleichen()
        #expect(s.sitzplaene.plan(fuer: "k-verwaist")?.tische.map(\.lernender) == ["l-9"])
        #expect(!neu(s, seit: vorher).contains { $0.contains("Zuordnung") })
    }

    @Test("⌘O mit Wechsel löst die Bindungen still wie „Neue Planung“ — keine Meldung, die Person liegt im Archiv (Z-AS5a-06)")
    func wechselStill() throws {
        let ablage = try ordner("tot-wechsel")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let alt = try #require(s.planung)
        let plan = Sitzplan.anordnen(klasseId: alt.klassen[0].id, lernende: [.init(name: "Anna Abel", lernender: "l-1"),
                                                                             .init(name: "Ben Bauer", lernender: "l-2"),
                                                                             .init(name: "Person l-9", lernender: "l-9")])
        #expect(s.sitzplaene.setzen(plan, fuer: alt.klassen[0].id) == nil)
        // Eine Planung anderer Herkunft mit derselben Klassenkennung — ihr Plan übersteht das Aufräumen.
        var fremd = Planung.leer(titel: "Fremd 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                                 klassen: [alt.klassen[0]], fachfarben: [:])
        fremd.erstellt = "2027-07-01T10:00:00.000Z"
        let vorher = Set(s.meldungen.map(\.id))
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "fremd.json"))
        s.schuljahrOeffnen(gruppen: ["g-1"])
        #expect(s.lernende.bestand?.lernende.map(\.id) == ["l-1"], "nur die Person der übernommenen Gruppe")
        #expect(s.sitzplaene.plan(fuer: alt.klassen[0].id)?.tische.map(\.lernender) == ["l-1", "", ""])
        // Ben still, die ältere tote Bindung (l-9) mit genau einer Meldung — wie „Neue Planung“ (Z-AS5a-09).
        let gemeldet = s.meldungen.filter { !vorher.contains($0.id) && $0.text.contains("Zuordnung") }.map(\.text)
        #expect(gemeldet == [Self.geloestEins], Comment(rawValue: gemeldet.joined(separator: " | ")))
    }

    @Test("Das stille Lösen beim Wechsel greift nur die Pläne der Klassen der Planung — verwaiste bleiben (Z-AS5a-10)")
    func wechselLoestNurPlaeneDerKlassen() throws {
        let ablage = try ordner("wechsel-verwaist")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let plan = Sitzplan.anordnen(klasseId: "k-verwaist", lernende: [.init(name: "Person l-9", lernender: "l-9")])
        #expect(s.sitzplaene.setzen(plan, fuer: "k-verwaist") == nil)
        s.bindungenNachWechselLoesen(["l-9"])
        #expect(s.sitzplaene.plan(fuer: "k-verwaist")?.tische.map(\.lernender) == ["l-9"])
    }

    @Test("Nach dem Einlesen einer Jahresdatei: Bindungen an Personen, die sie nicht trägt, gelöst (C, E345)")
    func toteBindungNachDemEinlesen() throws {
        let ablage = try ordner("tot-einlesen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let p = try #require(s.planung)
        let klasse = try planMitToten(s, ["l-9"])
        // Eingelesen wird nur in eine leere Verwaltung.
        #expect(s.lernende.setzen(Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: Self.stempel)) == nil)
        #expect(s.lernendenEinlesenKlartext(try Lernendendatei.schreiben(bestand(p)), von: URL(fileURLWithPath: "lernende.json")) == nil)
        #expect(s.sitzplaene.plan(fuer: klasse)?.tische.map(\.lernender) == ["l-1", ""])
        #expect(s.meldungen.last?.text == Self.geloestEins, Comment(rawValue: s.meldungen.last?.text ?? "—"))
    }

    @Test("Übereifer-Gegenprobe: Jahresdatei aus, zu, gesperrt, nicht gelesen oder fremd, Sitzpläne gesperrt — nichts gelöst, nichts gemeldet (C)")
    func abgleichNurMitSchranken() throws {
        func unberuehrt(_ s: Planungsspeicher, _ klasse: String, _ fall: String) {
            let vorher = s.meldungen.count
            s.sitzplaeneAufraeumen()
            #expect(s.sitzplaene.plan(fuer: klasse)?.tische.map(\.lernender) == ["l-1", "l-9"], Comment(rawValue: fall))
            // Ebenso das Netz im Editor: „Übernehmen“ löst über dieselbe Schranke (G2-03).
            if let plan = s.sitzplaene.plan(fuer: klasse) {
                s.sitzplanUebernehmen(plan)
                #expect(s.sitzplaene.plan(fuer: klasse)?.tische.map(\.lernender) == ["l-1", "l-9"],
                        Comment(rawValue: fall + ", Übernehmen im Editor"))
            } else {
                Issue.record(Comment(rawValue: fall + ": kein Sitzplan"))
            }
            #expect(!neu(s, seit: vorher).contains { $0.contains("Zuordnung") }, Comment(rawValue: fall))
        }
        // aus: ohne Verschlüsselung keine Lernendenverwaltung.
        let aus = try ordner("schranke-aus")
        defer { try? FileManager.default.removeItem(at: aus) }
        let ohne = Planungsspeicher(ablage: Ablage(ordner: aus))
        ohne.planung = try planung()
        ohne.jetztSichern()
        ohne.sitzplaeneLaden()
        unberuehrt(ohne, try planMitToten(ohne, ["l-9"]), "aus")
        // zu.
        let zuOrt = try ordner("schranke-zu")
        defer { try? FileManager.default.removeItem(at: zuOrt) }
        let zu = try speicher(zuOrt)
        let klasseZu = try planMitToten(zu, ["l-9"])
        zu.lernende.schliessen()
        unberuehrt(zu, klasseZu, "zu")
        // gesperrt: eine neuere Fassung der Jahresdatei.
        let gesperrtOrt = try ordner("schranke-gesperrt")
        defer { try? FileManager.default.removeItem(at: gesperrtOrt) }
        let gesperrt = try speicher(gesperrtOrt)
        let klasseGesperrt = try planMitToten(gesperrt, ["l-9"])
        let tresor = try #require(gesperrt.tresor)
        let planungGesperrt = try #require(gesperrt.planung)
        let objekt = try JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(bestand(planungGesperrt)))
        var neuer = try #require(objekt as? [String: Any])
        neuer["version"] = 2
        gesperrt.lernende.schliessen()
        try tresor.versiegeln(try JSONSerialization.data(withJSONObject: neuer), inhalt: .lernende, ziel: .ablage)
            .write(to: Ablage(ordner: gesperrtOrt).lernende)
        guard case .gesperrt = gesperrt.lernende.oeffnen(mit: tresor, stempel: "s") else {
            Issue.record("erwartet gesperrt")
            return
        }
        unberuehrt(gesperrt, klasseGesperrt, "gesperrt")
        // nicht gelesen: eingeschaltet, aber ohne Jahresdatei.
        let leerOrt = try ordner("schranke-leer")
        defer { try? FileManager.default.removeItem(at: leerOrt) }
        let leer = Planungsspeicher(ablage: Ablage(ordner: leerOrt))
        leer.planung = try planung()
        leer.jetztSichern()
        _ = try leer.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(leer.verschluesselungEinschalten().offenes.isEmpty)
        #expect(leer.lernende.schreibbar && leer.lernende.bestand == nil, "eingeschaltet, ohne Jahresdatei")
        unberuehrt(leer, try planMitToten(leer, ["l-9"]), "nicht gelesen")
        // fremd: die Jahresdatei einer anderen Planung.
        let fremdOrt = try ordner("schranke-fremd")
        defer { try? FileManager.default.removeItem(at: fremdOrt) }
        let fremd = try speicher(fremdOrt)
        let klasseFremd = try planMitToten(fremd, ["l-9"])
        var anderer = bestand(try #require(fremd.planung))
        anderer.planung = "2020-01-01T00:00:00.000Z"
        #expect(fremd.lernende.setzen(anderer) == nil)
        unberuehrt(fremd, klasseFremd, "fremd")
        // Sitzpläne gesperrt: die Datei bleibt, wie sie ist.
        let spOrt = try ordner("schranke-sitzplaene")
        defer { try? FileManager.default.removeItem(at: spOrt) }
        let sp = try speicher(spOrt)
        _ = try planMitToten(sp, ["l-9"])
        let spTresor = try #require(sp.tresor)
        let datei = Ablage(ordner: spOrt).sitzplaene
        try spTresor.versiegeln(Data("{\"typ\":\"unterrichtsplanung-sitzplaene\",\"version\":9,\"plaene\":{}}".utf8),
                                inhalt: .sitzplaene, ziel: .ablage).write(to: datei)
        sp.sitzplaeneOeffnen(spTresor)
        #expect(!sp.sitzplaene.schreibbar, "gesperrt")
        let roh = try Data(contentsOf: datei)
        let vorher = sp.meldungen.count
        sp.sitzplanbindungenAbgleichen()
        #expect(try Data(contentsOf: datei) == roh && !neu(sp, seit: vorher).contains { $0.contains("Zuordnung") }, "Sitzpläne gesperrt")
    }

    @Test("⌘O mit Wechsel: die Rettungskopie verwaister Sitzpläne trägt ihre Bindungen — wie das Archiv die Personen (Z14c-10)")
    func rettungskopieBehaeltBindungen() throws {
        let ablage = try ordner("rettung")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let alt = try #require(s.planung)
        let plan = Sitzplan.anordnen(klasseId: alt.klassen[1].id, lernende: [.init(name: "Ben Bauer", lernender: "l-2")])
        #expect(s.sitzplaene.setzen(plan, fuer: alt.klassen[1].id) == nil)
        var fremd = Planung.leer(titel: "Fremd 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                                 klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        fremd.erstellt = "2027-07-01T10:00:00.000Z"
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "fremd.json"))
        s.schuljahrOeffnen(gruppen: ["g-1"])
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: ablage.path)
            .first { $0.hasPrefix("sitzplaene-verwaist-") })
        let gerettet = try Sitzplandatei.lesen(try #require(s.tresor).oeffnen(try Data(contentsOf: ablage.appending(component: name))))
        #expect(gerettet[alt.klassen[1].id]?.tische.map(\.lernender) == ["l-2"], "die Kopie trägt die Bindung")
    }

    @Test("Abbruch an jeder Stelle: Planung, Jahresdatei und Archiv sind alle alt oder alle neu")
    func abbruchAnJederStelle() async throws {
        let ablage = try ordner("abbruch")
        var abbilder: [(schritt: Uebergangsdienst.Schritt, ort: URL)] = []
        defer { for o in [ablage] + abbilder.map(\.ort) { try? FileManager.default.removeItem(at: o) } }
        let s = try speicher(ablage)
        let alt = try #require(s.planung)
        s.sicherung.uebergang.haken = { schritt in
            guard let ziel = try? self.ordner("abbild-\(abbilder.count)") else { return }
            try? FileManager.default.removeItem(at: ziel)
            try? FileManager.default.copyItem(at: ablage, to: ziel)
            abbilder.append((schritt, ziel))
        }
        try neuesSchuljahr(s)
        let neu = try #require(s.planung)
        #expect(Set(abbilder.map(\.schritt)) == [.vorbereitet, .uebergeben, .einsetzen, .aufgeraeumt], "\(abbilder.map(\.schritt))")
        for (schritt, ort) in abbilder {
            let neuerStand = schritt != .vorbereitet
            let zweiter = Planungsspeicher(ablage: Ablage(ordner: ort))
            zweiter.starten()
            if !neuerStand {
                #expect(zweiter.blockadeOffen, "\(schritt): jede Spur sperrt")
                zweiter.blockadeRaeumenFragen()
                try #require(zweiter.rueckfrage).handlung()
            }
            await zweiter.entsperren(passphrase: passphrase)
            #expect(zweiter.verschluesselungsstand == .an, "\(schritt)")
            let planung = try #require(zweiter.planung)
            let jahresdatei = try #require(zweiter.lernende.bestand)
            guard case .gelesen(let archiv, _, _) = zweiter.lernende.archivLesen(stempel: "p") else {
                Issue.record("\(schritt): das Archiv öffnet nicht")
                continue
            }
            if neuerStand {
                #expect(planung.erstellt == neu.erstellt && jahresdatei.planung == neu.erstellt && archiv.jahre.count == 1,
                        "\(schritt): alle drei neu")
            } else {
                #expect(planung.erstellt == alt.erstellt && jahresdatei.planung == alt.erstellt && archiv.jahre.isEmpty,
                        "\(schritt): alle drei alt")
            }
        }
    }

    @Test("Ohne Verschlüsselung fragt „Neue Planung“ vorher — drei Antworten: fortfahren, Verschlüsselung, Abbrechen (E275)")
    func ohneVerschluesselungFragen() throws {
        let ablage = try ordner("ohne")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        var angelegt = 0
        s.neuePlanungFragen { angelegt += 1 }
        #expect(angelegt == 1 && s.rueckfrage == nil, "ohne bisherige Planung: nichts zu archivieren")

        s.planung = try planung()
        s.neuePlanungFragen { angelegt += 1 }
        let frage = try #require(s.rueckfrage)
        #expect(frage.text.contains("nur mit eingeschalteter Verschlüsselung"), Comment(rawValue: frage.text))
        #expect(frage.bestaetigung == "Ohne Archiv fortfahren" && frage.weitere == "Verschlüsselung einrichten …"
                && frage.ablehnung == "Abbrechen")
        #expect(angelegt == 1)
        // Abbrechen tut nichts.
        s.rueckfrageBeantworten(false)
        #expect(angelegt == 1 && s.rueckfrage == nil && s.offenerDialog == nil && s.naechsterDialog == nil)
        // Der dritte Knopf öffnet die Einrichtung der Verschlüsselung.
        s.neuePlanungFragen { angelegt += 1 }
        s.rueckfrageWeitere()
        #expect(angelegt == 1 && s.rueckfrage == nil
                && (s.offenerDialog == .verschluesselung || s.naechsterDialog == .verschluesselung))
        s.offenerDialog = nil
        s.neuePlanungFragen { angelegt += 1 }
        s.rueckfrageBeantworten(true)
        #expect(angelegt == 2)
    }

    @Test("⌘O mit einer Planung anderer Herkunft: das Blatt mit der Wahl der Lerngruppen, dann archiviert wie beim Wechsel; gleiche Herkunft ohne Archiv (E277, E305)")
    func oeffnenAndererHerkunft() throws {
        let ablage = try ordner("oeffnen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let alt = try #require(s.planung)
        // Dieselbe Herkunft (eine Sicherung derselben Planung): kein Archiv.
        var sicherung = alt
        sicherung.titel = "Sicherung"
        s.importierenKlartext(try Planungsdatei.schreiben(sicherung), von: URL(fileURLWithPath: "/tmp/sicherung.json"))
        let ersetzen = try #require(s.rueckfrage)
        #expect(!ersetzen.text.contains("Archiv"), Comment(rawValue: ersetzen.text))
        s.rueckfrageBeantworten(false)

        // Eine andere Planung: archivieren und öffnen.
        var fremd = Planung.leer(titel: "Fremd 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                                 klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        fremd.erstellt = "2027-07-01T10:00:00.000Z"
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "/tmp/fremd.json"))
        #expect(s.rueckfrage == nil && s.offenerDialog == .schuljahrOeffnen, "das Blatt „Neues Schuljahr öffnen“ (E305)")
        let wechsel = try #require(s.schuljahrwechsel)
        #expect(wechsel.titel == "Fremd 2027/28" && wechsel.bisher == alt.titel)
        #expect(wechsel.vorgabe == ["g-1"], "vorgewählt: die Gruppe, deren Zeile die geöffnete Planung unter gleichem Namen trägt")
        s.schuljahrOeffnenAbbrechen()
        #expect(s.schuljahrwechsel == nil && s.planung?.erstellt == alt.erstellt, "„Abbrechen“: nichts geschieht")
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "/tmp/fremd.json"))
        s.schuljahrOeffnen(gruppen: ["g-1", "g-2"])
        #expect(s.schuljahrwechsel == nil)
        #expect(s.planung?.erstellt == fremd.erstellt)
        let jahresdatei = try #require(s.lernende.bestand)
        #expect(jahresdatei.planung == fremd.erstellt)
        #expect(jahresdatei.lerngruppen.map(\.id) == ["g-1", "g-2"], "die gewählten Gruppen, gebunden, wo Name und Fach passen")
        #expect(jahresdatei.lerngruppen.first?.zeilen.map(\.klasseId) == [try #require(s.planung?.klassen.first?.id)])
        #expect(jahresdatei.lerngruppen.dropFirst().first?.zeilen.isEmpty == true)
        guard case .gelesen(let archiv, _, _) = s.lernende.archivLesen(stempel: "p") else {
            Issue.record("das Archiv öffnet nicht")
            return
        }
        #expect(archiv.jahre.map(\.planung.erstellt) == [alt.erstellt])
        try keineSpur(ablage)
    }

    @Test("„Neue Planung“ mit Namen und Zeilen aus dem Blatt: „6a · Biologie“ wird „7a · Informatik“ an einer eingetippten Zeile (E308, E310)")
    func neuePlanungMitZielen() throws {
        let ablage = try ordner("ziele")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let alt = try #require(s.planung)
        let eingetippt = Standardkurse.aufbauen([("7a", "Informatik")])
        s.neuePlanung(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                      klassen: eingetippt, ersterSchultag: nil,
                      uebernahme: [Planung.Uebernahmewunsch(klasse: alt.klassen[1], mitVorhaben: false)],
                      lerngruppen: ["g-1", "g-2"],
                      ziele: ["g-1": Gruppenwahl(name: "7a", zeile: .kennung(eingetippt[0].id)),
                              "g-2": Gruppenwahl(name: "8b", zeile: .uebernommen(alt.klassen[1].id))])
        let neu = try #require(s.planung)
        let uebernommen = try #require(neu.klassen.first { $0.name == "7b" })
        let jahresdatei = try #require(s.lernende.bestand)
        let g1 = jahresdatei.lerngruppen.first { $0.id == "g-1" }
        let g2 = jahresdatei.lerngruppen.first { $0.id == "g-2" }
        #expect(g1?.name == "7a" && g1?.fach == "Informatik"
                && g1?.zeilen == [Zeilenbindung(planung: neu.erstellt, klasseId: eingetippt[0].id)])
        #expect(g2?.name == "8b" && g2?.fach == "Chemie"
                && g2?.zeilen == [Zeilenbindung(planung: neu.erstellt, klasseId: uebernommen.id)])
    }

    @Test("⌘O ins nächste Schuljahr: Stufen, Zeilen, Vorbelegung und Wortlaut des Blatts; Name und Zeile kommen an (E307–E311)")
    func oeffnenMitHochstufen() throws {
        let ablage = try ordner("hochstufen")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        var fremd = Planung.leer(titel: "Fremd 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                                 klassen: Standardkurse.aufbauen([("7a", "Informatik"), ("7b", "Chemie")]), fachfarben: [:])
        fremd.erstellt = "2027-07-01T10:00:00.000Z"
        let f1 = fremd.klassen[0].id, f2 = fremd.klassen[1].id
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "/tmp/fremd.json"))
        let wechsel = try #require(s.schuljahrwechsel)
        #expect(wechsel.stufen == 1 && wechsel.bisherigesSchuljahr == "2026/27" && wechsel.neuesSchuljahr == "2027/28")
        #expect(wechsel.zeilen.map(\.id) == [f1, f2])
        #expect(wechsel.uebernommen == ["g-2": f2], "„7b · Chemie“ heißt in beiden gleich")
        #expect(wechsel.vorgabe == ["g-1", "g-2"], "„6a“ eine Stufe höher findet „7a“; „7b“ ihre gleichnamige Zeile")
        #expect(SchuljahrOeffnenDialog.titel(stufen: wechsel.stufen) == "Neues Schuljahr öffnen"
                && SchuljahrOeffnenDialog.unterzeile(wechsel)
                    == "„Fremd 2027/28“ (2027/28) gehört zu einem anderen Schuljahr als „Schuljahr 2026/27“ (2026/27)")
        s.schuljahrOeffnen(gruppen: ["g-1", "g-2"], ziele: ["g-1": Gruppenziel(name: "7a", zeile: f1),
                                                            "g-2": Gruppenziel(name: "8b", zeile: f2)])
        let jahresdatei = try #require(s.lernende.bestand)
        let g1 = jahresdatei.lerngruppen.first { $0.id == "g-1" }
        let g2 = jahresdatei.lerngruppen.first { $0.id == "g-2" }
        #expect(g1?.name == "7a" && g1?.fach == "Informatik" && g1?.zeilen.map(\.klasseId) == [f1])
        #expect(g2?.name == "8b" && g2?.fach == "Chemie" && g2?.zeilen.map(\.klasseId) == [f2])
    }

    @Test("⌘O mit einer Planung eines früheren Schuljahrs: „Früheres Schuljahr öffnen“, Namen bleiben (E314)")
    func oeffnenFrueheresSchuljahr() throws {
        let ablage = try ordner("frueher")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        var fremd = Planung.leer(titel: "Fremd 2025/26", start: try #require(Tag(iso: "2025-08-04")), wochen: 4, basis: "",
                                 klassen: Standardkurse.aufbauen([("6a", "Biologie"), ("7b", "Chemie")]), fachfarben: [:])
        fremd.erstellt = "2025-07-01T10:00:00.000Z"
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: URL(fileURLWithPath: "/tmp/fremd.json"))
        let wechsel = try #require(s.schuljahrwechsel)
        #expect(wechsel.stufen == -1 && wechsel.neuesSchuljahr == "2025/26")
        #expect(SchuljahrOeffnenDialog.titel(stufen: wechsel.stufen) == "Früheres Schuljahr öffnen")
        #expect(SchuljahrOeffnenDialog.unterzeile(wechsel)
                == "„Fremd 2025/26“ (2025/26) gehört zu einem anderen Schuljahr als „Schuljahr 2026/27“ (2026/27)")
        #expect(wechsel.vorgabe == ["g-1", "g-2"], "Namen bleiben, beide Zeilen heißen gleich")
    }

    @Test("„Neue Planung“: eine Zeile aus dem Blatt, die es in der neuen Planung nicht gibt, bindet nichts — der Name gilt (Z14c2-08)")
    func neuePlanungOhneTreffer() throws {
        let ablage = try ordner("ohne-treffer")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        let alt = try #require(s.planung)
        s.neuePlanung(titel: "Schuljahr 2027/28", start: try #require(Tag(iso: "2027-08-02")), wochen: 4, basis: "",
                      klassen: [], ersterSchultag: nil,
                      uebernahme: [Planung.Uebernahmewunsch(klasse: alt.klassen[1], mitVorhaben: false)],
                      lerngruppen: ["g-1", "g-2"],
                      ziele: ["g-1": Gruppenwahl(name: "7a", zeile: .kennung("k-weg")),
                              "g-2": Gruppenwahl(name: "8b", zeile: .uebernommen(alt.klassen[0].id))])
        let jahresdatei = try #require(s.lernende.bestand)
        let g1 = jahresdatei.lerngruppen.first { $0.id == "g-1" }
        let g2 = jahresdatei.lerngruppen.first { $0.id == "g-2" }
        #expect(g1?.name == "7a" && g1?.fach == "Biologie" && g1?.zeilen.isEmpty == true)
        #expect(g2?.name == "8b" && g2?.fach == "Chemie" && g2?.zeilen.isEmpty == true,
                "eine nicht übernommene Zeile bindet nicht; die vorbelegte ist ersetzt")
    }

    @Test("Ohne Schuljahr in der Jahresdatei gilt das der Planung (E307)")
    func bisherigesSchuljahrRueckfall() throws {
        let ablage = try ordner("rueckfall")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        #expect(s.bisherigesSchuljahr == "2026/27")
        var ohne = try #require(s.lernende.bestand)
        ohne.schuljahr = ""
        #expect(s.lernende.setzen(ohne) == nil)
        #expect(s.bisherigesSchuljahr == Lernendenbestand.schuljahr(fuer: try #require(s.planung).start))
    }

    @Test("⌘O im selben Schuljahr: „Andere Planung öffnen“, Namen bleiben; ein offenes Blatt nennt es so — wenn es zu ist (E309, E335, E391)")
    func oeffnenGleichesSchuljahr() async throws {
        let ablage = try ordner("gleich")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try speicher(ablage)
        var fremd = Planung.leer(titel: "Fremd 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                                 klassen: Standardkurse.aufbauen([("6a", "Biologie"), ("7b", "Chemie")]), fachfarben: [:])
        fremd.erstellt = "2026-09-01T10:00:00.000Z"
        let daten = try Planungsdatei.schreiben(fremd)
        s.importierenKlartext(daten, von: URL(fileURLWithPath: "/tmp/fremd.json"))
        let wechsel = try #require(s.schuljahrwechsel)
        #expect(wechsel.stufen == 0 && wechsel.neuesSchuljahr == "2026/27")
        #expect(SchuljahrOeffnenDialog.titel(stufen: 0) == "Andere Planung öffnen")
        #expect(SchuljahrOeffnenDialog.unterzeile(wechsel)
                == "„Fremd 2026/27“ und „Schuljahr 2026/27“ gehören beide zum Schuljahr 2026/27")
        #expect(wechsel.vorgabe == ["g-1", "g-2"], "beide Zeilen heißen gleich")
        s.schuljahrOeffnenAbbrechen()
        s.offenerDialog = .klassen
        let meldungen = s.meldungen.count
        let toene = s.systemtoene
        s.importierenKlartext(daten, von: URL(fileURLWithPath: "/tmp/fremd.json"))
        #expect(s.schuljahrwechsel == nil && s.meldungen.count == meldungen, "abgewiesen; hinter dem Blatt noch kein Text (E335)")
        #expect(s.systemtoene == toene + 1, "der Ton kommt sofort (E399)")
        s.offenerDialog = nil
        try await abwarten("nach dem Schließen des Blatts der Text") {
            s.meldungen.last?.text == "„Fremd 2026/27“ ist eine andere Planung desselben Schuljahrs und wurde nicht "
                + "geöffnet, weil ein Blatt offen war. Bitte die Datei erneut öffnen."
        }
    }
}
