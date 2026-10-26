// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Das Blatt „Lernende“ am Speicher (v80, AP7) ───────────────────────────
// Geöffnet nur mit Planung und offener Lernendenverwaltung; ohne
// Verschlüsselung der Hinweis mit „Verschlüsselung einrichten …“ (E249).
// Solange das Blatt steht, gehört ⌘Z seinem Verlauf; „Übernehmen“ schreibt
// über den Dienst — versiegelt.

@Suite("Blatt „Lernende“: Öffnen, Sperre, eigener Verlauf, Übernehmen")
@MainActor
struct LernendenblattPruefungen {

    init() throws {
        try #require(Ablage.istPruefstand,
                     "die Prüfungen brauchen einen eigenen Ablageort (PLANUNGSORDNER)")
    }

    private let passphrase = "Ein Satz, den man behält"

    private func ordner(_ name: String) throws -> URL {
        let ziel = URL.temporaryDirectory
            .appending(component: "lernendenblatt-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        return ziel
    }

    private func planung() throws -> Planung {
        Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                     basis: "", klassen: Standardkurse.aufbauen([("6a", "Biologie")]), fachfarben: [:])
    }

    /// Ein eingeschalteter Speicher, noch ohne Jahresdatei.
    private func speicher(_ ablage: URL) async throws -> Planungsspeicher {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        s.jetztSichern()
        _ = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: passphrase))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        return s
    }

    @Test("Ohne Planung: weder Blatt noch Hinweis")
    func ohnePlanung() throws {
        let ablage = try ordner("ohne")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        #expect(!s.lernendenBlattAngeboten)
        s.lernendenBlattOeffnen()
        #expect(s.offenerDialog == nil && s.rueckfrage == nil)
    }

    @Test("Ohne Verschlüsselung: kein Blatt, sondern der Hinweis mit „Verschlüsselung einrichten …“ (E249)")
    func ohneVerschluesselung() throws {
        let ablage = try ordner("aus")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        #expect(s.lernende.quelle == .aus && !s.lernendenBlattAngeboten)
        s.lernendenBlattOeffnen()
        #expect(s.offenerDialog == nil)
        let frage = try #require(s.rueckfrage)
        #expect(frage.text == Planungsspeicher.lernendenSperrtext)
        #expect(frage.bestaetigung == "Verschlüsselung einrichten …" && frage.ort == .hauptansicht)
        s.rueckfrageBeantworten(true)
        #expect(s.offenerDialog == .verschluesselung)
        #expect(!FileManager.default.fileExists(atPath: Ablage(ordner: ablage).lernende.path))
    }

    @Test("Mit Verschlüsselung öffnet das Blatt; ohne Jahresdatei beginnt der Entwurf leer fürs Schuljahr der Planung")
    func oeffnen() async throws {
        let ablage = try ordner("auf")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        #expect(s.lernendenBlattAngeboten)
        s.lernendenBlattOeffnen(gruppe: "g-9")
        #expect(s.offenerDialog == .lernende && s.rueckfrage == nil)
        #expect(s.lernendenVorgabe?.gruppe == "g-9", "die Gruppe, mit der das Blatt aufgeht")
        let entwurf = try #require(s.lernendenEntwurfBeginnen())
        let p = try #require(s.planung)
        #expect(entwurf.planung == p.erstellt && entwurf.schuljahr == "2026/27" && entwurf.lernende.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: Ablage(ordner: ablage).lernende.path), "Öffnen schreibt nichts")
    }

    @Test("Solange das Blatt steht, gehört ⌘Z seinem Verlauf — die Planung dahinter bleibt; mit dem Blatt endet er")
    func eigenerVerlauf() async throws {
        let ablage = try ordner("verlauf")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        _ = s.aendern(Schrittname.planungstitelAendern) { $0.titel = "Geändert" }
        s.offenerDialog = .lernende
        var gesetzt: Lernendenbestand?
        s.lernendenblattUebernimmt { gesetzt = $0 }
        let a = try #require(s.lernendenEntwurfBeginnen())
        let b = try #require(a.mitNeuerGruppe(name: "7c", art: .kurs, jetzt: a.erstellt)).bestand
        s.lernendenverlauf.anmelden(Schrittname.lerngruppeAnlegen, vorher: a, nachher: b)
        #expect(s.kannWiderrufen && s.widerrufenTitel == "Widerrufen: Lerngruppe anlegen")
        s.widerrufen()
        #expect(gesetzt == a && s.planung?.titel == "Geändert")
        #expect(s.wiederholenTitel == "Wiederholen: Lerngruppe anlegen")
        s.wiederholen()
        #expect(gesetzt == b)

        s.offenerDialog = nil
        #expect(!s.lernendenblattOffen && !s.lernendenverlauf.kannZurueck && !s.lernendenverlauf.kannVor)
        #expect(s.widerrufenTitel == "Widerrufen: \(Schrittname.planungstitelAendern)", "der Hauptverlauf gilt wieder")
    }

    @Test("„Übernehmen“ schreibt über den Dienst — versiegelt, und ein frischer Dienst liest denselben Stand")
    func uebernehmen() async throws {
        let ablage = try ordner("schreiben")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        let a = try #require(s.lernendenEntwurfBeginnen())
        let (b, gruppe) = try #require(a.mitNeuerGruppe(name: "7c", art: .kurs, jetzt: a.erstellt))
        let c = b.mitPersonen(Namenszeilen.lesen("Abel, Anna\nMax Mustermann").namen, inGruppe: gruppe, jetzt: a.erstellt).bestand
        #expect(s.lernendenUebernehmen(c) == nil)
        #expect(s.lernende.bestand == c)
        let roh = try Data(contentsOf: Ablage(ordner: ablage).lernende)
        let kopf = try Tresor.kopfLesen(roh)
        #expect(Tresor.istBehaelter(roh) && kopf.inhalt == "lernende")
        let frisch = Lernendendienst(ablage: Ablage(ordner: ablage))
        _ = frisch.oeffnen(mit: try #require(s.tresor), stempel: "probe")
        #expect(frisch.bestand == c)
    }

    @Test("Planung aus dem Archiv sichern (E274): versiegelt wie ⌘S, öffnet mit dem Schlüssel, unverändert")
    func archivPlanungSichern() async throws {
        let ablage = try ordner("archiv-sichern")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        var alt = try planung()
        alt.titel = "Schuljahr 2025/26"
        let ziel = ablage.appending(component: "export-2025-26.json")
        let groesse = try s.archivPlanungSchreiben(alt, nach: ziel)
        let roh = try Data(contentsOf: ziel)
        #expect(roh.count == groesse && Tresor.istBehaelter(roh))
        #expect(try Tresor.kopfLesen(roh).inhalt == "planung")
        let gelesen = try Planungsdatei.lesen(try #require(s.tresor).oeffnen(roh))
        #expect(gelesen == alt, "die Planung, wie sie war — ohne neuen Zeitstempel")
    }

    // ── Lerngruppe an Zeilen der Planung (AP10) ───────────────────────────

    @Test("Lerngruppe aus einer Zeile anlegen, eine andere binden, lösen — geschrieben in die Jahresdatei")
    func bindenAmSpeicher() async throws {
        let ablage = try ordner("binden")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        let klasse = try #require(s.planung?.klassen.first)
        #expect(s.lerngruppen(fuerZeile: klasse.id).isEmpty)
        #expect(s.lerngruppeAusZeileAngeboten(klasse.id))
        #expect(s.lerngruppeAusZeileAnlegen(klasse.id) == nil)
        #expect(!s.lerngruppeAusZeileAngeboten(klasse.id), "„6a“ hängt schon an der Zeile — keine zweite aus der Zeile (E667)")
        let gruppe = try #require(s.lerngruppe(fuerZeile: klasse.id))
        #expect(!klasse.fach.isEmpty && gruppe.name == klasse.name && gruppe.beschriftung == klasse.name,
                "aus der Zeile „6a · Biologie“ die Lerngruppe „6a“ — ohne Fach (E665)")
        #expect(Lernendendienst(ablage: Ablage(ordner: ablage)).mitSchluessel(try #require(s.tresor)).bestand?.lerngruppen.count == 1,
                "geschrieben, versiegelt")
        #expect(s.lerngruppeLoesen(klasse.id) == nil && s.lerngruppen(fuerZeile: klasse.id).isEmpty)
        #expect(s.lerngruppeBinden(gruppe.id, an: klasse.id) == nil && s.lerngruppe(fuerZeile: klasse.id)?.id == gruppe.id)
    }

    @Test("E670, E673–E676, E667, E680: Zwei Lerngruppen an einer Zeile — Sitzplan leer; ⌘K bietet die gleichnamige an; „Nur „6a““ behält die gleichnamige an der Zeile")
    func mehrereAnEinerZeile() async throws {
        let ablage = try ordner("mehrere")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        let p = try #require(s.planung)
        let klasse = try #require(p.klassen.first)
        let jetzt = "2026-10-15T08:00:00.000Z"
        var b = Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: jetzt)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: jetzt, geaendert: jetzt, archiviert: "")]
        let andere = Zeilenbindung(planung: p.erstellt, klasseId: "k-andere")
        b.lerngruppen = [Lerngruppe(id: "g-6a", name: "6a", art: .klasse, mitglieder: ["l-1"], zeilen: [andere], skalen: [:],
                                    halbjahreswechsel: "", geaendert: jetzt, archiviert: ""),
                         Lerngruppe(id: "g-9b", name: "9b", art: .klasse, mitglieder: [], zeilen: [], skalen: [:],
                                    halbjahreswechsel: "", geaendert: jetzt, archiviert: "")]
        #expect(s.lernende.setzen(b) == nil)
        #expect(s.gleichnamigeLerngruppe(fuerZeile: klasse.id)?.id == "g-6a", "die Zeile „6a · Biologie“: ⌘K bietet „6a“ zuerst an (E667)")
        #expect(s.lerngruppeBinden("g-6a", an: klasse.id) == nil && s.lerngruppeBinden("g-9b", an: klasse.id) == nil)
        #expect(s.lerngruppen(fuerZeile: klasse.id).map(\.id) == ["g-6a", "g-9b"], "beide an der Zeile (E670)")
        #expect(s.gleichnamigeLerngruppe(fuerZeile: klasse.id) == nil, "schon gebunden — kein Angebot")
        #expect(s.lerngruppe(fuerZeile: klasse.id) == nil, "zwei: nicht die eine Lerngruppe der Zeile")
        let angebot = try #require(s.sitzplatzangebot(fuer: klasse.id))
        #expect(angebot.gruppe == nil && angebot.plaetze.isEmpty, "der Sitzplan bleibt leer (E674)")
        let zeile = Zeilenbindung(planung: p.erstellt, klasseId: klasse.id)
        let sechsA = try #require(s.lernende.bestand?.lerngruppen.first { $0.id == "g-6a" })
        #expect(s.lerngruppenangebot(fuerZeile: klasse.id) == .behalten(sechsA), "die Kurszelle zeigt „Nur „6a““ (E680)")
        let (grund, neu) = s.lerngruppeFuerZeileAnlegen(klasse.id)
        #expect(grund == nil && neu == "g-6a", "behalten, nichts angelegt (E680)")
        #expect(s.lerngruppen(fuerZeile: klasse.id).map(\.id) == ["g-6a"], "nur „9b“ geht von der Zeile")
        #expect(s.lernende.bestand?.lerngruppen.count == 2, "keine zweite „6a“")
        #expect(s.lernende.bestand?.lerngruppen.first { $0.id == "g-6a" }?.zeilen == [andere, zeile],
                "die Folge der Zeilen bleibt — die erste gibt das Fach (E648)")
        #expect(s.lernende.bestand?.lerngruppen.first { $0.id == "g-9b" }?.zeilen.isEmpty == true)
    }

    @Test("E680: „+ „6a““ verknüpft eine gleichnamige, die mit der Zeile noch nicht verknüpft ist; ohne gleichnamige „+ Lerngruppe“ wie bisher (E673); eine gleichnamige mit 20 Zeilen nennt den Grund")
    func kurszelleWieKlassenblatt() async throws {
        let ablage = try ordner("kurszelle-e680")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        let p = try #require(s.planung)
        let klasse = try #require(p.klassen.first)
        let jetzt = "2026-10-16T08:00:00.000Z"
        let zeile = Zeilenbindung(planung: p.erstellt, klasseId: klasse.id)
        let andere = Zeilenbindung(planung: p.erstellt, klasseId: "k-andere")
        func gruppe(_ id: String, _ name: String, _ zeilen: [Zeilenbindung]) -> Lerngruppe {
            Lerngruppe(id: id, name: name, art: .klasse, mitglieder: [], zeilen: zeilen, skalen: [:], halbjahreswechsel: "",
                       geaendert: jetzt, archiviert: "")
        }
        var b = Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: jetzt)
        // Fall B: die gleichnamige nur an einer anderen Zeile, an dieser „9a“, „9b“ und eine archivierte (Z-AT15M-07).
        var archiviertB = gruppe("g-arch", "Chor", [zeile])
        archiviertB.archiviert = jetzt
        b.lerngruppen = [gruppe("g-6a", klasse.name, [andere]), gruppe("g-9a", "9a", [zeile]), gruppe("g-9b", "9b", [zeile]),
                         archiviertB]
        #expect(s.lernende.setzen(b) == nil)
        #expect(s.lerngruppenangebot(fuerZeile: klasse.id) == .verknuepfen(b.lerngruppen[0]), "„+ „6a““")
        let (grund, id) = s.lerngruppeFuerZeileAnlegen(klasse.id)
        #expect(grund == nil && id == "g-6a")
        #expect(s.lerngruppen(fuerZeile: klasse.id).map(\.id) == ["g-6a"], "„9a“ und „9b“ gehen von dieser Zeile")
        #expect(s.lernende.bestand?.lerngruppen.count == 4, "nichts angelegt")
        #expect(s.lernende.bestand?.lerngruppen.first { $0.id == "g-arch" }?.zeilen.isEmpty == true,
                "auch die archivierte geht von der Zeile (Z-AT15N-05, -M-07)")
        #expect(s.lernende.bestand?.lerngruppen.first { $0.id == "g-6a" }?.zeilen == [andere, zeile], "an der anderen bleibt sie")
        // Fall A, die Zeile zuerst: „Nur „6a““ lässt die Folge der Zeilen der behaltenen, wie sie ist (E648).
        var alt = gruppe("g-alt", "Bio-AG", [zeile])
        alt.archiviert = jetzt
        b.lerngruppen = [gruppe("g-6a", klasse.name, [zeile, andere]), gruppe("g-9a", "9a", [zeile]), alt]
        #expect(s.lernende.setzen(b) == nil)
        #expect(s.lerngruppeFuerZeileAnlegen(klasse.id).id == "g-6a")
        #expect(s.lernende.bestand?.lerngruppen.first { $0.id == "g-6a" }?.zeilen == [zeile, andere], "die erste bleibt die erste")
        #expect(s.lernende.bestand?.lerngruppen.first { $0.id == "g-alt" }?.zeilen.isEmpty == true,
                "auch eine archivierte geht von der Zeile — wie bei „+ Lerngruppe“ (Z-AT15N-05)")
        // Fall C: ohne gleichnamige wie bisher eine neue (E673).
        b.lerngruppen = [gruppe("g-9a", "9a", [zeile]), gruppe("g-9b", "9b", [zeile])]
        #expect(s.lernende.setzen(b) == nil)
        #expect(s.lerngruppenangebot(fuerZeile: klasse.id) == .anlegen)
        let neu = s.lerngruppeFuerZeileAnlegen(klasse.id)
        let neuId = try #require(neu.id)
        #expect(neu.grund == nil && s.lerngruppen(fuerZeile: klasse.id).map(\.id) == [neuId])
        #expect(s.lernende.bestand?.lerngruppen.count == 3)
        #expect(s.lerngruppe(fuerZeile: klasse.id)?.name == klasse.name && s.lerngruppe(fuerZeile: klasse.id)?.mitglieder.isEmpty == true,
                "benannt wie die Zeile, ohne Mitglieder (E673, Z-AT15N-14)")
        // Die gleichnamige hängt schon an 20 Zeilen: der Grund, nichts geändert.
        let zwanzig = (1...Lernendendatei.maxZeilenJeGruppe).map { Zeilenbindung(planung: p.erstellt, klasseId: "k-\($0)") }
        b.lerngruppen = [gruppe("g-6a", klasse.name, zwanzig), gruppe("g-9a", "9a", [zeile]), gruppe("g-9b", "9b", [zeile])]
        #expect(s.lernende.setzen(b) == nil)
        let voll = s.lerngruppeFuerZeileAnlegen(klasse.id)
        #expect(voll.id == nil && voll.grund == Planungsspeicher.lerngruppeVoll(klasse.name))
        #expect(s.lerngruppen(fuerZeile: klasse.id).map(\.id) == ["g-9a", "g-9b"], "beide bleiben an der Zeile")
    }

    @Test("E667: Hängt eine „6a“ an der Zeile, bietet ⌘K keine zweite „6a“ an — weder binden noch anlegen (Z-AT9b-16); die Klassenleitung „6a“ findet und benennt über ihre Klasse (Z-AT9b-18)")
    func gleichnamigeAmSpeicher() async throws {
        let ablage = try ordner("gleichnamige")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        var p = try #require(s.planung)
        let bio = try #require(p.klassen.first)
        var leitung = Klasse.sonderzeile(.klassenleitung)
        leitung.fach = "6a"
        p.klassen.append(leitung)
        s.planung = p
        let jetzt = "2026-10-15T08:00:00.000Z"
        var b = Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: jetzt)
        b.lerngruppen = ["g-a", "g-b"].map { id in
            Lerngruppe(id: id, name: "6a", art: .klasse, mitglieder: [],
                       zeilen: id == "g-a" ? [Zeilenbindung(planung: p.erstellt, klasseId: bio.id)] : [], skalen: [:],
                       halbjahreswechsel: "", geaendert: jetzt, archiviert: "")
        }
        #expect(s.lernende.setzen(b) == nil)
        #expect(s.gleichnamigeLerngruppe(fuerZeile: bio.id) == nil, "„6a“ (g-a) hängt schon an „6a · Biologie“ — g-b nicht dazu")
        #expect(!s.lerngruppeAusZeileAngeboten(bio.id))
        #expect(s.gleichnamigeLerngruppe(fuerZeile: leitung.id)?.id == "g-a", "die Klassenleitung „6a“: die erste „6a“")
        #expect(s.lerngruppeAusZeileAngeboten(leitung.id))
        // Ohne „6a“ im Schuljahr legt ⌘K an der Klassenleitung die eine „6a“ an.
        #expect(s.lernende.setzen(Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: jetzt)) == nil)
        #expect(s.lerngruppeAusZeileAnlegen(leitung.id) == nil)
        #expect(s.lerngruppen(fuerZeile: leitung.id).map(\.name) == ["6a"], "aus der Klassenleitung „6a“, nicht „Klassenleitung“")
        #expect(!s.lerngruppeAusZeileAngeboten(leitung.id), "„6a“ hängt jetzt an der Zeile")
    }

    @Test("„+ Lerngruppe“ mit Grund: eine Zeile, die es nicht mehr gibt, und die Grenze der Lerngruppen — dann bleibt alles (Z-AT9b-06)")
    func eigeneLerngruppeMitGrund() async throws {
        let ablage = try ordner("mehrere-grund")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        let p = try #require(s.planung)
        let klasse = try #require(p.klassen.first)
        let jetzt = "2026-10-15T08:00:00.000Z"
        let zeile = Zeilenbindung(planung: p.erstellt, klasseId: klasse.id)
        var b = Lernendenbestand.leer(planung: p.erstellt, schuljahr: "2026/27", jetzt: jetzt)
        b.lerngruppen = (1...Kennwerte.maxLerngruppen).map { i in
            Lerngruppe(id: "g-\(i)", name: "G\(i)", art: .klasse, mitglieder: [], zeilen: i <= 2 ? [zeile] : [], skalen: [:],
                       halbjahreswechsel: "", geaendert: jetzt, archiviert: "")
        }
        #expect(s.lernende.setzen(b) == nil)
        let gibtEsNicht = s.lerngruppeFuerZeileAnlegen("k-gibt-es-nicht")
        #expect(gibtEsNicht.grund == "Die Zeile gibt es nicht mehr." && gibtEsNicht.id == nil)
        let voll = s.lerngruppeFuerZeileAnlegen(klasse.id)
        #expect(voll.grund == "Die Lerngruppe ließ sich nicht anlegen — höchstens \(Kennwerte.maxLerngruppen) je Schuljahr."
                && voll.id == nil)
        #expect(s.lerngruppen(fuerZeile: klasse.id).map(\.id) == ["g-1", "g-2"], "beide bleiben an der Zeile")
        #expect(s.lernende.bestand?.lerngruppen.count == Kennwerte.maxLerngruppen, "keine angelegt")
    }

    @Test("Ohne Verschlüsselung bindet nichts — der Grund ist der Hinweis (E249)")
    func bindenOhneVerschluesselung() throws {
        let ablage = try ordner("binden-aus")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = try planung()
        let klasse = try #require(s.planung?.klassen.first)
        #expect(s.lerngruppeAusZeileAnlegen(klasse.id)?.contains("Verschlüsselung") == true)
        #expect(!FileManager.default.fileExists(atPath: Ablage(ordner: ablage).lernende.path))
    }

    @Test("Angebot für den Sitzplan: ohne Verschlüsselung keins, ohne Bindung leer, gebunden die aktiven Mitglieder (E249, E252, E255)")
    func sitzplatzangebot() async throws {
        let aus = try ordner("angebot-aus")
        defer { try? FileManager.default.removeItem(at: aus) }
        let ohne = Planungsspeicher(ablage: Ablage(ordner: aus))
        ohne.planung = try planung()
        #expect(ohne.sitzplatzangebot(fuer: try #require(ohne.planung?.klassen.first).id) == nil)

        let ablage = try ordner("angebot")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        let klasse = try #require(s.planung?.klassen.first).id
        let leer = try #require(s.sitzplatzangebot(fuer: klasse))
        #expect(leer.gruppe == nil && leer.plaetze.isEmpty)
        #expect(s.lerngruppeAusZeileAnlegen(klasse) == nil)
        let gruppe = try #require(s.lerngruppe(fuerZeile: klasse))
        let jetzt = "2026-10-04T08:00:00.000Z"
        let namen = [Namenszeilen.Name(vorname: "Zoe", nachname: "Zander"),
                     Namenszeilen.Name(vorname: "Anna", nachname: "Abel"),
                     Namenszeilen.Name(vorname: "Ben", nachname: "Bauer")]
        let mit = try #require(s.lernende.bestand).mitPersonen(namen, inGruppe: gruppe.id, jetzt: jetzt)
        let ben = try #require(mit.bestand.lernende.first { $0.nachname == "Bauer" }).id
        #expect(s.lernendenUebernehmen(mit.bestand.mitArchivierterPerson(ben, jetzt: jetzt)) == nil)
        let angebot = try #require(s.sitzplatzangebot(fuer: klasse))
        #expect(angebot.gruppe?.id == gruppe.id)
        #expect(angebot.plaetze.map(\.name) == ["Anna Abel", "Zoe Zander"], "nach Nachname, ohne Archivierte")
        #expect(Set(angebot.plaetze.map(\.lernender)).count == 2 && !angebot.plaetze.contains { $0.lernender == ben })
    }

    // ── Export und Einlesen (AP12, E257, E287) ─────────────────────────────

    /// Ein eingeschalteter Speicher wie `speicher(_:)`, dazu das Blatt mit dem
    /// Wiederherstellungsschlüssel.
    private func speicherMitBlatt(_ ablage: URL, planung p: Planung, passphrase satz: String) async throws -> (Planungsspeicher, String) {
        let s = Planungsspeicher(ablage: Ablage(ordner: ablage))
        s.planung = p
        s.jetztSichern()
        let blatt = try #require(await s.verschluesselungVorbereitenAsynchron(passphrase: satz))
        #expect(s.verschluesselungEinschalten().offenes.isEmpty)
        return (s, blatt)
    }

    @Test("Export (E257): Behälter „lernende“ fürs Ziel export — nur Passphrase und Wiederherstellung, beide öffnen ihn; der Inhalt ist die Jahresdatei")
    func export() async throws {
        let ablage = try ordner("export")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let (s, blatt) = try await speicherMitBlatt(ablage, planung: try planung(), passphrase: passphrase)
        #expect(s.lerngruppeAusZeileAnlegen(try #require(s.planung?.klassen.first).id) == nil)
        let ziel = ablage.appending(component: "lernende-export.json")
        let groesse = try s.lernendenExportSchreiben(nach: ziel)
        let roh = try Data(contentsOf: ziel)
        #expect(roh.count == groesse && Tresor.istBehaelter(roh))
        let kopf = try Tresor.kopfLesen(roh)
        #expect(kopf.inhalt == "lernende")
        #expect(Set(kopf.wicklungen.map(\.art)) == [Wicklung.passphrase, Wicklung.wiederherstellung], "nie die Enklave")
        let bestand = try #require(s.lernende.bestand)
        #expect(try Lernendendatei.lesen(try Tresor.oeffnen(kopf: kopf, passphrase: passphrase).oeffnen(kopf: kopf)) == bestand)
        #expect(try Lernendendatei.lesen(try Tresor.oeffnen(kopf: kopf, wiederherstellung: blatt).oeffnen(kopf: kopf)) == bestand)
        // Ohne Verschlüsselung gibt es nichts zu exportieren (E249).
        let aus = try ordner("export-aus")
        defer { try? FileManager.default.removeItem(at: aus) }
        let ohne = Planungsspeicher(ablage: Ablage(ordner: aus))
        ohne.planung = try planung()
        #expect(throws: (any Error).self) { try ohne.lernendenExportSchreiben(nach: aus.appending(component: "x.json")) }
    }

    @Test("CSV: erst die Rückfrage am Ort, dann die Datei — im Klartext, wie die Rückfrage sagt")
    func csvRueckfrage() async throws {
        let ablage = try ordner("csv")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        #expect(s.lerngruppeAusZeileAnlegen(try #require(s.planung?.klassen.first).id) == nil)
        s.lernendenAlsCSVSichern()
        let frage = try #require(s.rueckfrage)
        #expect(frage.bestaetigung == "Als CSV sichern" && frage.gefahr && frage.text.contains("unverschlüsselt"))
        #expect(!frage.text.localizedCaseInsensitiveContains("zeugnis"), "nennt kein Zeugnisprogramm (E587)")
        s.rueckfrageBeantworten(false)
        let ziel = ablage.appending(component: "lernende.csv")
        #expect(try s.lernendenCSVSchreiben(nach: ziel) == (try Data(contentsOf: ziel)).count)
        #expect(try Data(contentsOf: ziel) == Lernendendatei.csv(try #require(s.lernende.bestand)))
    }

    @Test("Einlesen (E287): ⌘O mit dem Export unter fremdem Schlüssel — die Freigabe, dann gilt er unter dem eigenen; nur in eine leere Verwaltung derselben Planung")
    func einlesen() async throws {
        let quelle = try ordner("einlesen-quelle")
        let ziel = try ordner("einlesen-ziel")
        let fremd = try ordner("einlesen-fremd")
        defer { for o in [quelle, ziel, fremd] { try? FileManager.default.removeItem(at: o) } }
        let p = try planung()
        let (a, _) = try await speicherMitBlatt(quelle, planung: p, passphrase: passphrase)
        #expect(a.lerngruppeAusZeileAnlegen(try #require(p.klassen.first).id) == nil)
        let datei = quelle.appending(component: "lernende-export.json")
        try a.lernendenExportSchreiben(nach: datei)
        let gesucht = try #require(a.lernende.bestand)

        // Dieselbe Planung (Herkunft), ein anderer Schlüssel, noch leer: ⌘O fragt nach der Datei.
        let (b, _) = try await speicherMitBlatt(ziel, planung: try #require(a.planung), passphrase: "Ein ganz anderer Satz")
        b.importieren(von: datei)
        #expect(b.entsperrungOffen && !b.entsperrungFuerAblage)
        await b.entsperren(passphrase: passphrase)
        #expect(!b.entsperrungOffen)
        #expect(b.lernende.bestand?.lerngruppen == gesucht.lerngruppen && b.lernende.bestand?.planung == gesucht.planung)
        let kopf = try Tresor.kopfLesen(try Data(contentsOf: Ablage(ordner: ziel).lernende))
        #expect(kopf.kennungHex == b.tresor?.kennungHex, "danach unter dem eigenen Schlüssel")

        // Nicht leer: abgewiesen, bevor eine Passphrase gefragt wird.
        b.lernendenEinlesen(von: datei)
        #expect(!b.entsperrungOffen && b.meldungen.last?.text.contains("nicht leer") == true)

        // Eine andere Planung (andere Herkunft): abgewiesen nach dem Öffnen, nichts übernommen.
        var andere = p
        andere.erstellt = "2026-10-04T09:00:00.000Z"
        let (c, _) = try await speicherMitBlatt(fremd, planung: andere, passphrase: passphrase)
        #expect(c.lernendenEinlesenKlartext(try Lernendendatei.schreiben(gesucht), von: datei)?.contains("anderen Planung") == true)
        #expect(c.lernende.bestand.map { $0.lerngruppen.isEmpty } ?? true)
    }

    @Test("A4: Ohne gesicherte Herkunft sichert das Binden vorher — die Platte trägt die Herkunft der Bindung")
    func bindenSichertHerkunft() async throws {
        let ablage = try ordner("a4")
        defer { try? FileManager.default.removeItem(at: ablage) }
        let s = try await speicher(ablage)
        var p = try #require(s.planung)
        // Eine Herkunft, die die Platte nicht trägt — wie nach dem Lesen einer Datei ohne `erstellt`.
        p.erstellt = "2026-10-03T09:00:00.000Z"
        s.stempelEinsetzen(p)
        let klasse = try #require(p.klassen.first).id
        #expect(s.lerngruppeAusZeileAnlegen(klasse) == nil)
        let gruppe = try #require(s.lernende.bestand?.lerngruppen.first)
        #expect(gruppe.zeilen == [Zeilenbindung(planung: "2026-10-03T09:00:00.000Z", klasseId: klasse)])
        let roh = try Data(contentsOf: Ablage(ordner: ablage).datei)
        let gelesen = try Planungsdatei.lesen(try #require(s.tresor).oeffnen(roh))
        #expect(gelesen.erstellt == "2026-10-03T09:00:00.000Z", "die Platte trägt die Herkunft der Bindung")
    }
}

extension Lernendendienst {
    /// Ein frischer Dienst an derselben Ablage, geöffnet mit dem Schlüssel.
    fileprivate func mitSchluessel(_ tresor: Tresor) -> Lernendendienst {
        _ = oeffnen(mit: tresor, stempel: "probe")
        return self
    }
}

