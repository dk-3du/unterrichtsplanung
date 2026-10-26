// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Meldungen hinter einem Blatt (B96, B98, E420, E421) ───────────────────
// Hinter einem Blatt verfiele ein Text ungelesen (E334). Der Schreibfehler der Sitzpläne beim Öffnen des
// Editors kommt nach dessen Schließen; Dateifehler beim Öffnen aus dem Finder geben den Ton sofort und den
// Text nach dem Blatt (E391, E399); ein Lernenden-Export, den das Einlesen ohnehin abwiese, nennt nach dem
// Blatt gleich den wahren Grund statt „erneut öffnen“ (Z-AS7a-02).

@Suite("Meldungen hinter einem Blatt: Schreibfehler der Sitzpläne beim Öffnen des Editors, Dateifehler beim Öffnen, Vorbedingungen des Lernenden-Exports")
@MainActor
struct HinterDemBlattPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"
    private static let stempel = "2026-10-03T08:00:00.000Z"
    private static let schreibfehlerAnfang = "Die Sitzpläne ließen sich nicht sichern (eine Prüfsperre) — "
    private static let geloestEins = "Eine Zuordnung an einem Tisch wurde gelöst: Die Person steht nicht mehr in der "
        + "Lernendenverwaltung; der Name am Tisch bleibt."

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "hinterblatt-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        var p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                             basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
        p.eintraege = [Vorhaben(id: "e-1", klasseId: p.klassen[0].id, woche: 1, titel: "Zellen",
                                text: "", erledigt: false, materialien: [], links: [])]
        return p
    }

    /// Im Klartext — die Ablage ist nicht verschlüsselt, die Lernendenverwaltung aus.
    private func klartext(_ ablage: URL) throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        s.rueckfrageSichtbar = { [weak s] in s?.rueckfrage != nil }
        return s
    }

    /// Eingeschaltet, mit Jahresdatei: Anna (l-1) in der Lerngruppe der Klasse.
    private func eingeschaltet(_ ablage: URL) throws -> Planungsspeicher {
        let s = try klartext(ablage)
        _ = try s.verschluesselungVorbereiten(passphrase: passphrase)
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        let p = try #require(s.planung)
        var b = Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: Self.stempel)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: Self.stempel,
                                geaendert: Self.stempel, archiviert: "")]
        b.lerngruppen = [Lerngruppe(id: "g-1", name: "6a", fach: "Biologie", art: .klasse, mitglieder: ["l-1"],
                                    zeilen: [Zeilenbindung(planung: p.erstellt, klasseId: p.klassen[0].id)],
                                    skalen: [:], halbjahreswechsel: "", geaendert: Self.stempel, archiviert: "")]
        #expect(s.lernende.setzen(b) == nil)
        return s
    }

    /// Die Dateifehler beim Öffnen, je mit ihrem Text: nicht mehr da, zu groß, unlesbar, ein Behälter mit
    /// fremdem Inhalt, ein Behälter in eine unverschlüsselte Ablage, Klartext einer anderen Anwendung, ein
    /// beschädigter Behälter.
    private func fehlerhafteDateien(_ quelle: URL) throws -> [(datei: URL, text: String)] {
        let fort = quelle.appending(component: "fort.json")
        let gross = quelle.appending(component: "gross.json")
        #expect(FileManager.default.createFile(atPath: gross.path, contents: nil))
        let griff = try FileHandle(forWritingTo: gross)
        try griff.truncate(atOffset: UInt64(Planungsdatei.hoechstgroesse + 1))  // dünn: gemessen, nicht geschrieben
        try griff.close()
        let verzeichnis = quelle.appending(component: "verzeichnis.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: verzeichnis, withIntermediateDirectories: true)
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        let klartext = try Planungsdatei.schreiben(try planung())
        let sitzplaene = quelle.appending(component: "sitzplaene.json")
        try fremder.versiegeln(klartext, inhalt: .sitzplaene, ziel: .export).write(to: sitzplaene)
        let versiegelt = quelle.appending(component: "versiegelt.json")
        try fremder.versiegeln(klartext, inhalt: .planung, ziel: .export).write(to: versiegelt)
        let andere = quelle.appending(component: "andere.json")
        try Data(#"{"typ":"etwas anderes"}"#.utf8).write(to: andere)
        let beschaedigt = quelle.appending(component: "beschaedigt.json")
        try Data(#"{"typ":"unterrichtsplanung-tresor"}"#.utf8).write(to: beschaedigt)
        return [
            (fort, "„fort.json“ ist nicht mehr da und wurde nicht geöffnet."),
            (gross, "Die Datei ist mit \(Planungsdatei.hoechstgroesse / 1024 / 1024) MB zu groß für eine "
                + "Planungsdatei und wurde nicht geöffnet."),
            (verzeichnis, "„verzeichnis.json“ ist keine reguläre Datei — die Datei wurde nicht geöffnet."),
            (sitzplaene, "Die Datei ist ein verschlüsselter Behälter mit Inhalt „sitzplaene“, keine Planung."),
            (versiegelt, "Die Datei ist verschlüsselt, die Ablage auf diesem Mac ist es nicht. Bitte zuerst unter "
                + "„Einstellungen“ die Verschlüsselung einschalten, dann die Datei erneut öffnen."),
            (andere, "Die Datei gehört zu einer anderen Anwendung."),
            (beschaedigt, "Der verschlüsselte Behälter ist beschädigt."),
        ]
    }

    // ── B96, E420 (a): nur beim Öffnen des Editors ────────────────────────

    @Test("Ein Schreibfehler der Sitzpläne beim Öffnen des Editors steht nicht hinter dem Blatt — er kommt nach dem Schließen, vor den gelösten Zuordnungen; danach meldet der Dienst wieder sofort (B96, E420)")
    func schreibfehlerBeimOeffnenDesEditors() async throws {
        let ablage = try ordner("editor")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try eingeschaltet(ablage)
        let klasse = try #require(s.planung?.klassen.first?.id)
        // Anna und eine Kennung, die die Jahresdatei nicht trägt: Das Öffnen löst sie und schreibt.
        let plan = Sitzplan.anordnen(klasseId: klasse, lernende: [.init(name: "Anna Abel", lernender: "l-1"),
                                                                 .init(name: "Person l-9", lernender: "l-9")])
        #expect(s.sitzplaene.setzen(plan, fuer: klasse) == nil)
        let sperre = s.sitzplaene.schreibsperre
        defer { s.sitzplaene.schreibsperre = sperre }
        s.sitzplaene.schreibsperre = { "eine Prüfsperre" }
        let vorher = Set(s.meldungen.map(\.id))
        func neu() -> [String] { s.meldungen.filter { !vorher.contains($0.id) }.map(\.text) }
        s.sitzplanOeffnen(klasse: klasse)
        try #require(s.offenerDialog == .sitzplan && s.sitzplaene.ungesichert != nil, "das Blatt steht, das Schreiben scheiterte")
        #expect(s.sitzplanEntwurf?.tische.map(\.lernender) == ["l-1", ""], "der Editor zeigt die Bindung gelöst")
        #expect(neu().isEmpty, "hinter dem Blatt noch kein Text: \(neu())")
        s.sitzplanDialogSchliessen()
        s.offenerDialog = nil  // das Blatt geht zu
        try await abwarten("nach dem Blatt beide Texte") { neu().count >= 2 }
        let texte = neu()
        #expect(texte.count == 2 && texte.first?.hasPrefix(Self.schreibfehlerAnfang) == true && texte.last == Self.geloestEins,
                "\(texte)")
        // Danach spricht wieder die Senke des Speichers: Ein neuer Schreibfehler ohne Blatt steht sofort.
        s.sitzplaene.schreibsperre = sperre
        s.sitzplaene.nachholen()
        try #require(s.sitzplaene.ungesichert == nil, "wieder gesichert")
        s.sitzplaene.schreibsperre = { "eine Prüfsperre" }
        let davor = Set(s.meldungen.map(\.id))
        #expect(s.sitzplaene.setzen(plan, fuer: klasse) != nil)
        let sofort = s.meldungen.filter { !davor.contains($0.id) }.map(\.text)
        #expect(sofort.count == 1 && sofort.first?.hasPrefix(Self.schreibfehlerAnfang) == true, "ohne Blatt sofort: \(sofort)")
    }

    // ── B98, E421 (a): Dateifehler beim Öffnen ─────────────────────────────

    @Test("Dateifehler beim Öffnen aus dem Finder hinter einem Blatt: der Ton sofort, der Text erst nach dem Blatt, je einmal — mit dem Namen der Datei vorn (B98, E421, E391, E399, Z-AU7-02)")
    func dateifehlerHinterBlatt() async throws {
        let ablage = try ordner("dateifehler")
        let quelle = try ordner("dateifehler-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let s = try klartext(ablage)
        for (datei, ohneNamen) in try fehlerhafteDateien(quelle) {
            let name = datei.lastPathComponent
            // Nachgeholt steht der Text ohne seinen Anlass da: Er nennt seine Datei, wenn er sie nicht schon nennt (Z-AU7-02).
            let text = ohneNamen.contains("„\(name)“") ? ohneNamen : "„\(name)“: \(ohneNamen)"
            s.offenerDialog = .einstellungen
            let toene = s.systemtoene
            s.importieren(von: datei)
            let gleich = s.meldungen.map(\.text).contains(text)
            #expect(s.systemtoene == toene + 1, "der Ton kommt sofort — \(name)")
            #expect(!gleich, "hinter dem Blatt noch kein Text — \(name)")
            s.offenerDialog = nil
            try await abwarten("nach dem Blatt der Text zu \(name)") { s.meldungen.map(\.text).contains(text) }
            let anzahl = s.meldungen.map(\.text).filter { $0 == text }.count
            #expect(anzahl == 1, "einmal — \(name)")
            #expect(s.meldungen.last { $0.text == text }?.art == .warnung, "als Warnung — \(name)")
        }
        #expect(s.planung?.titel == "Schuljahr 2026/27", "die Planung bleibt")
    }

    @Test("Ohne Blatt kommen dieselben Dateifehler gleich und ohne Ton (B98, E421)")
    func dateifehlerOhneBlatt() throws {
        let ablage = try ordner("dateifehler-frei")
        let quelle = try ordner("dateifehler-frei-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let s = try klartext(ablage)
        for (datei, text) in try fehlerhafteDateien(quelle) {
            let toene = s.systemtoene
            s.importieren(von: datei)
            #expect(s.meldungen.last?.text == text, "gleich — \(datei.lastPathComponent): \(s.meldungen.last?.text ?? "—")")
            #expect(s.systemtoene == toene, "ohne Ton — \(datei.lastPathComponent)")
        }
        #expect(s.planung?.titel == "Schuljahr 2026/27", "die Planung bleibt")
    }

    @Test("Ohne Planung, nur „Neue Planungsdatei“, die zum Öffnen auffordert: jeder Dateifehler kommt gleich, ohne Ton und ohne vorangestellten Namen — wie beim Öffnen dort (E331, Z-AS7a-04, Z-AU7-11)")
    func dateifehlerBeiNeuerPlanungsdatei() throws {
        let ablage = try ordner("dateifehler-neu")
        let quelle = try ordner("dateifehler-neu-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let s = try klartext(ablage)
        let dateien = try fehlerhafteDateien(quelle)
        s.planung = nil
        s.offenerDialog = .neuePlanung
        for (datei, text) in dateien {
            let toene = s.systemtoene
            s.importieren(von: datei)
            #expect(s.meldungen.last?.text == text, "gleich — \(datei.lastPathComponent): \(s.meldungen.last?.text ?? "—")")
            #expect(s.systemtoene == toene, "ohne Ton — \(datei.lastPathComponent)")
        }
        #expect(s.offenerDialog == .neuePlanung, "das Blatt bleibt")
    }

    @Test("Nennt der Text seine Datei schon — vorn oder mittendrin —, kommt ihr Name nachgeholt nicht noch einmal davor (Z-AU7-10)")
    func nameNichtDoppelt() {
        let datei = URL(fileURLWithPath: "/tmp/x.json")
        let mittendrin = "Die Größe von „x.json“ ließ sich nicht bestimmen. — die Datei wurde nicht geöffnet."
        #expect(Planungsspeicher.nachgeholterDateifehler(mittendrin, datei: datei) == mittendrin)
        let vorn = "„x.json“ ist keine reguläre Datei — die Datei wurde nicht geöffnet."
        #expect(Planungsspeicher.nachgeholterDateifehler(vorn, datei: datei) == vorn)
        #expect(Planungsspeicher.nachgeholterDateifehler("Die Datei gehört zu einer anderen Anwendung.", datei: datei)
                == "„x.json“: Die Datei gehört zu einer anderen Anwendung.")
        // Ein Systemtext in englischer Schreibung setzt den Namen in “…” (AU11).
        let englisch = "The file “x.json” couldn’t be opened."
        #expect(Planungsspeicher.nachgeholterDateifehler(englisch, datei: datei) == englisch)
        // Blendet der Finder die Endung aus, nennt ein Systemtext den Anzeigenamen (Z-AU11-04) — gezählt nur in
        // Anführungszeichen, ohne Endung steckte er sonst in manchem Wort.
        let ohneEndung = "Die Datei „x“ konnte nicht geöffnet werden."
        #expect(Planungsspeicher.nachgeholterDateifehler(ohneEndung, datei: datei, anzeigename: { "x" }) == ohneEndung)
        #expect(Planungsspeicher.nachgeholterDateifehler("Fehler x beim Lesen.", datei: datei, anzeigename: { "x" })
                == "„x.json“: Fehler x beim Lesen.")
        // Ohne Anzeigenamen — ein eigener Text — zählt nur der Dateiname (Z-AU11-07).
        #expect(Planungsspeicher.nachgeholterDateifehler(ohneEndung, datei: datei) == "„x.json“: " + ohneEndung)
    }

    @Test("Nennt der nachgeholte Dateifehler die Datei schon, fragt er nicht nach ihrem Anzeigenamen (Z-AU11-06)")
    func anzeigenameNurWennNoetig() async throws {
        let ablage = try ordner("anzeigename-noetig")
        let quelle = try ordner("anzeigename-noetig-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let s = try klartext(ablage)
        var gefragt = 0
        s.anzeigenameVon = { _ in
            gefragt += 1
            return "fort"
        }
        // Ein Ordner unter dem Namen: Der Lesefehler geht als Systemtext und nennt die Datei schon.
        let verzeichnis = quelle.appending(component: "verzeichnis.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: verzeichnis, withIntermediateDirectories: true)
        s.offenerDialog = .einstellungen
        s.importieren(von: verzeichnis)
        s.offenerDialog = nil
        let text = "„verzeichnis.json“ ist keine reguläre Datei — die Datei wurde nicht geöffnet."
        try await abwarten("nach dem Blatt der Text") { s.meldungen.map(\.text).contains(text) }
        #expect(gefragt == 0, "der Dateiname steht schon im Text: \(gefragt)")
    }

    @Test("Ein eigener Text sucht den Anzeigenamen nicht — „Einstellungen“ meint dort das Blatt, nicht die Datei (Z-AU11-07)")
    func eigenerTextOhneAnzeigename() async throws {
        let ablage = try ordner("anzeigename-eigen")
        let quelle = try ordner("anzeigename-eigen-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let s = try klartext(ablage)
        // Der Finder blendet „.json“ aus.
        s.anzeigenameVon = { _ in "Einstellungen" }
        let fremder = Tresor.neu()
        try fremder.passphraseSetzen("Fremde Passphrase 2026", runden: Tresor.rundenMindestens)
        let datei = quelle.appending(component: "Einstellungen.json")
        try fremder.versiegeln(try Planungsdatei.schreiben(try planung()), inhalt: .planung, ziel: .export).write(to: datei)
        s.offenerDialog = .einstellungen
        s.importieren(von: datei)
        s.offenerDialog = nil
        let text = "„Einstellungen.json“: Die Datei ist verschlüsselt, die Ablage auf diesem Mac ist es nicht. Bitte zuerst "
            + "unter „Einstellungen“ die Verschlüsselung einschalten, dann die Datei erneut öffnen."
        try await abwarten("nach dem Blatt der Text mit dem Dateinamen vorn") { s.meldungen.map(\.text).contains(text) }
    }

    // ── B98, E421 (b): die Vorbedingungen des Lernenden-Exports vor der Schranke ──

    @Test("Ein Lernenden-Export hinter dem Blatt „Lernende“, die Verwaltung ist nicht leer: Ton sofort, nach dem Blatt gleich der wahre Grund, kein „erneut öffnen“ (B98, E421 b, Z-AS7a-02)")
    func lernendenExportNichtLeerHinterBlatt() async throws {
        let ablage = try ordner("export-nicht-leer")
        let quelle = try ordner("export-nicht-leer-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let s = try eingeschaltet(ablage)
        let datei = quelle.appending(component: "lernende-export.json")
        try s.lernendenExportSchreiben(nach: datei)
        try #require(!s.lernendenLeer)
        s.offenerDialog = .lernende
        let toene = s.systemtoene
        let vorher = Set(s.meldungen.map(\.id))
        func neu() -> [String] { s.meldungen.filter { !vorher.contains($0.id) }.map(\.text) }
        s.importieren(von: datei)
        #expect(s.systemtoene == toene + 1, "der Ton kommt sofort (E399)")
        #expect(neu().isEmpty && !s.entsperrungOffen, "hinter dem Blatt noch kein Text, kein Entsperren")
        s.offenerDialog = nil
        try await abwarten("nach dem Blatt ein Text") { !neu().isEmpty }
        #expect(neu() == ["Die Lernendenverwaltung ist nicht leer — eingelesen wird nur in eine leere."], "\(neu())")
        let arten = s.meldungen.filter { !vorher.contains($0.id) }.map(\.art)
        #expect(arten == [.warnung], "als Warnung, wie beim Einlesen (Z-AU7-05)")
    }

    @Test("Ein Lernenden-Export hinter einem Blatt, die Ablage ist nicht verschlüsselt: nach dem Blatt der Hinweis zur Verschlüsselung, kein „erneut öffnen“ (B98, E421 b)")
    func lernendenExportOhneVerschluesselungHinterBlatt() async throws {
        let herkunft = try ordner("export-herkunft")
        let ablage = try ordner("export-klartext")
        let quelle = try ordner("export-klartext-quelle")
        defer { for o in [herkunft, ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let datei = quelle.appending(component: "lernende-export.json")
        try eingeschaltet(herkunft).lernendenExportSchreiben(nach: datei)
        let s = try klartext(ablage)
        s.offenerDialog = .einstellungen
        let toene = s.systemtoene
        let vorher = Set(s.meldungen.map(\.id))
        func neu() -> [String] { s.meldungen.filter { !vorher.contains($0.id) }.map(\.text) }
        s.importieren(von: datei)
        #expect(s.systemtoene == toene + 1, "der Ton kommt sofort (E399)")
        #expect(neu().isEmpty, "hinter dem Blatt noch kein Text")
        s.offenerDialog = nil
        try await abwarten("nach dem Blatt ein Text") { !neu().isEmpty }
        #expect(neu() == [Planungsspeicher.lernendenSperrtext], "\(neu())")
        let arten = s.meldungen.filter { !vorher.contains($0.id) }.map(\.art)
        #expect(arten == [.hinweis], "als Hinweis, wie beim Einlesen (Z-AU7-05)")
    }

    @Test("Dieselbe Datei, über deren Schuljahreswechsel das Blatt entscheidet, erneut geöffnet und nicht mehr da: nur der Ton, kein Text — eine andere bekommt ihren (Z-AS2-10, Z-AU7-12)")
    func dateifehlerMitAnstehenderEntscheidung() async throws {
        let ablage = try ordner("entscheidung")
        let quelle = try ordner("entscheidung-quelle")
        defer { for o in [ablage, quelle] { try? FileManager.default.removeItem(at: o) } }
        let s = try eingeschaltet(ablage)
        let datei = quelle.appending(component: "fort.json")
        let andere = quelle.appending(component: "auch-fort.json")
        // Eine Planung anderer Herkunft aus `datei`: das Blatt „Neues Schuljahr öffnen“ entscheidet über sie (E305).
        var fremd = try planung()
        fremd.titel = "Fremd 2027/28"
        fremd.erstellt = "2027-07-01T10:00:00.000Z"
        s.importierenKlartext(try Planungsdatei.schreiben(fremd), von: datei)
        try #require(s.offenerDialog == .schuljahrOeffnen && s.entscheidungSteht(ueber: datei), "das Blatt entscheidet")
        // Inzwischen ist die Datei fort; beide werden erneut geöffnet.
        let toene = s.systemtoene
        s.importieren(von: datei)
        s.importieren(von: andere)
        #expect(s.systemtoene == toene + 2, "der Ton je Datei")
        s.schuljahrOeffnenAbbrechen()
        s.offenerDialog = nil
        let text = "„auch-fort.json“ ist nicht mehr da und wurde nicht geöffnet."
        try await abwarten("nach dem Blatt der Text der anderen") { s.meldungen.map(\.text).contains(text) }
        let eigene = s.meldungen.map(\.text).filter { $0.contains("„fort.json“") }
        #expect(eigene.isEmpty, "zur Datei in Entscheidung kein Text: \(eigene)")
    }
}
