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
                                                                             .init(name: "Ben Bauer", lernender: "l-2")])
        #expect(s.sitzplaene.setzen(plan, fuer: alt.klassen[0].id) == nil)
        try neuesSchuljahr(s)
        #expect(s.lernende.bestand?.lernende.map(\.id) == ["l-1"], "nur die Person der übernommenen Gruppe")
        let danach = try #require(s.sitzplaene.plaene.values.first)
        #expect(danach.tische.map(\.lernender) == ["l-1", ""] && danach.tische.map(\.name) == ["Anna Abel", "Ben Bauer"])
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

    @Test("⌘O im selben Schuljahr: „Andere Planung öffnen“, Namen bleiben; ein offenes Blatt nennt es so (E309)")
    func oeffnenGleichesSchuljahr() throws {
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
        s.importierenKlartext(daten, von: URL(fileURLWithPath: "/tmp/fremd.json"))
        #expect(s.meldungen.last?.text == "„Fremd 2026/27“ ist eine andere Planung desselben Schuljahrs und wurde nicht "
                + "geöffnet: Bitte zuerst das offene Blatt schließen, dann die Datei erneut öffnen.",
                Comment(rawValue: s.meldungen.last?.text ?? "—"))
    }
}
