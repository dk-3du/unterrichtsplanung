// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Lerngruppen ohne Fach (v84, AT9a-1; E656, E665, E671, V6, V10, V11) ──────
// Eine Lerngruppe trägt kein Fach; das Fach kommt nur über die verknüpften Zeilen. Ein Fach, das eine ältere Jahresdatei
// noch trägt, gilt nirgends mehr und wird beim nächsten Schreiben geleert. Lerngruppen entstehen hier ohne Fach; das alte
// Fach steht nur in der gelesenen Datei.

@Suite("Lerngruppen ohne Fach: Datei, Beschriftung, Ordnung, Suche über Zeilen, Import, erste Zeile")
struct LerngruppeOhneFachPruefungen {

    private static let herkunft = "2026-08-10T09:00:00.000Z"
    private static let stempel = "2026-10-03T08:00:00.000Z"

    private static func gruppe(_ id: String, _ name: String, mitglieder: [String] = [], zeilen: [String] = []) -> Lerngruppe {
        Lerngruppe(id: id, name: name, art: .klasse, mitglieder: mitglieder,
                   zeilen: zeilen.map { Zeilenbindung(planung: herkunft, klasseId: $0) }, skalen: [:],
                   halbjahreswechsel: "", geaendert: stempel, archiviert: "")
    }

    private static func bestand(_ gruppen: [Lerngruppe]) -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: herkunft, schuljahr: "2026/27", jetzt: stempel)
        let s = stempel
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-2", vorname: "Ben", nachname: "Bauer", angelegt: s, geaendert: s, archiviert: "")]
        b.lerngruppen = gruppen
        return b
    }

    /// Wie eine ältere Jahresdatei: je Lerngruppe ein Fach in der Datei — dann gelesen.
    private static func ausAlterDatei(_ b: Lernendenbestand, faecher: [String: String]) throws -> Lernendenbestand {
        var objekt = try #require(JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(b)) as? [String: Any])
        var gruppen = try #require(objekt["lerngruppen"] as? [[String: Any]])
        for i in gruppen.indices { if let id = gruppen[i]["id"] as? String, let fach = faecher[id] { gruppen[i]["fach"] = fach } }
        objekt["lerngruppen"] = gruppen
        return try Lernendendatei.lesen(try JSONSerialization.data(withJSONObject: objekt))
    }

    @Test("E665: Ein Fach aus einer älteren Jahresdatei gilt nicht — beim nächsten Schreiben steht es leer, der Schlüssel bleibt für 2.0.3")
    func fachBeimSchreibenLeer() throws {
        let gelesen = try Self.ausAlterDatei(Self.bestand([Self.gruppe("g-1", "6a")]), faecher: ["g-1": "Biologie"])
        let objekt = try #require(JSONSerialization.jsonObject(with: try Lernendendatei.schreiben(gelesen)) as? [String: Any])
        let gruppe = try #require((objekt["lerngruppen"] as? [[String: Any]])?.first)
        #expect(gruppe["fach"] as? String == "", "\(gruppe["fach"] ?? "fehlt")")
    }

    @Test("E665: Ein altes Fach liest sich ohne Bilanz — auch ein überlanges; nichts gilt als verworfen oder gekürzt")
    func altesFachOhneBilanz() throws {
        for fach in ["Biologie", String(repeating: "x", count: Planungsdatei.maxNamenslaenge + 1)] {
            var objekt = try #require(JSONSerialization.jsonObject(
                with: try Lernendendatei.schreiben(Self.bestand([Self.gruppe("g-1", "6a")]))) as? [String: Any])
            var gruppen = try #require(objekt["lerngruppen"] as? [[String: Any]])
            gruppen[0]["fach"] = fach
            objekt["lerngruppen"] = gruppen
            let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(try JSONSerialization.data(withJSONObject: objekt))
            #expect(bilanz.istLeer, "\(fach.count) Zeichen: \(bilanz.beschreibung)")
            #expect(gelesen.lerngruppen.map(\.beschriftung) == ["6a"])
        }
    }

    @Test("V7: Die Beschriftung einer Lerngruppe ist ihr Name — auch wenn die Datei noch ein Fach trug")
    func beschriftungNurName() throws {
        let gelesen = try Self.ausAlterDatei(Self.bestand([Self.gruppe("g-1", "6a")]), faecher: ["g-1": "Biologie"])
        #expect(gelesen.lerngruppen.map(\.beschriftung) == ["6a"])
    }

    @Test("Ordnung ohne Fach: gleiche Namen nach der Kennung")
    func ordnungOhneFach() throws {
        let gelesen = try Self.ausAlterDatei(Self.bestand([Self.gruppe("g-1", "6a"), Self.gruppe("g-2", "6a")]),
                                             faecher: ["g-1": "Chemie", "g-2": "Biologie"])
        #expect(gelesen.lerngruppen.sorted(by: Lerngruppe.vorgehen).map(\.id) == ["g-1", "g-2"])
    }

    @Test("E671: Die Suche in der Liste trifft Name und verknüpfte Zeilen — „Bio“ findet die Lerngruppe an „6a · Biologie“, ein altes Fach zählt nicht")
    func sucheUeberZeilen() throws {
        let b = try Self.ausAlterDatei(Self.bestand([Self.gruppe("g-1", "6a", zeilen: ["k-1"]), Self.gruppe("g-2", "Bio-AG"),
                                                     Self.gruppe("g-3", "7b", zeilen: ["k-2"])]),
                                       faecher: ["g-1": "Biologie"])
        let titel = [Zeilenbindung(planung: Self.herkunft, klasseId: "k-1"): "6a · Biologie",
                     Zeilenbindung(planung: Self.herkunft, klasseId: "k-2"): "7b · Chemie"]
        #expect(Lernendenblatt.gruppenliste(b, archivierte: false, suche: "Bio", zeilentitel: titel).map(\.id) == ["g-1", "g-2"])
        #expect(Lernendenblatt.gruppenliste(b, archivierte: false, suche: "Chemie", zeilentitel: titel).map(\.id) == ["g-3"])
        #expect(Lernendenblatt.gruppenliste(b, archivierte: false, suche: "Bio").map(\.id) == ["g-2"],
                "ohne Zeilen nur der Name — das alte Fach „Biologie“ zählt nicht")
    }

    @Test("E671: Die Titel der Zeilen, nach denen die Suche geht — je Zeile der geöffneten Planung „Name · Fach“; ohne Planung keine")
    func zeilentitelDerPlanung() throws {
        let p = Planung.leer(titel: "Schuljahr 2026/27", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                             klassen: Standardkurse.aufbauen([("6a", "Biologie"), ("Q1", "")]), fachfarben: [:])
        let titel = Lernendenblatt.zeilentitel(p)
        #expect(titel.count == 2)
        #expect(titel[Zeilenbindung(planung: p.erstellt, klasseId: p.klassen[0].id)] == "6a · Biologie")
        #expect(titel[Zeilenbindung(planung: p.erstellt, klasseId: p.klassen[1].id)] == "Q1")
        #expect(titel[Zeilenbindung(planung: "andere", klasseId: p.klassen[0].id)] == nil, "nur die Zeilen dieser Planung")
        #expect(Lernendenblatt.zeilentitel(nil).isEmpty)
    }

    @Test("V10: „Je Klasse“ trifft die erste gleichnamige Lerngruppe — auch wenn die Datei zwei mit verschiedenem Fach trug; keine neue")
    func importTrifftErsteGleichnamige() throws {
        let b = try Self.ausAlterDatei(Self.bestand([Self.gruppe("g-1", "7a", mitglieder: ["l-1"]),
                                                     Self.gruppe("g-2", "7a", mitglieder: ["l-2"])]),
                                       faecher: ["g-1": "Biologie", "g-2": "Chemie"])
        let lesung = try ImportPruefungen.lesung(ImportPruefungen.datei([ImportPruefungen.zeile("Hana", "Huber", klasse: "7a")]))
        let (nachher, bilanz) = b.mitImport(lesung, ziel: .jeKlasse, jetzt: Self.stempel)
        #expect(bilanz.neueGruppen.isEmpty, "\(bilanz.neueGruppen)")
        #expect(nachher.lerngruppen.first { $0.id == "g-1" }?.mitglieder.count == 2)
        // In der Folge der Listen (Name, dann Kennung), nicht der Datei: g-2 zuerst angelegt, getroffen wird g-1 (Z-AT9a1-05).
        let vertauscht = Self.bestand([Self.gruppe("g-2", "7a", mitglieder: ["l-2"]), Self.gruppe("g-1", "7a", mitglieder: ["l-1"])])
        let (danach, zweite) = vertauscht.mitImport(lesung, ziel: .jeKlasse, jetzt: Self.stempel)
        #expect(zweite.neueGruppen.isEmpty && danach.lerngruppen.first { $0.id == "g-1" }?.mitglieder.count == 2,
                "\(danach.lerngruppen.map { "\($0.id): \($0.mitglieder.count)" })")
    }

    @Test("V11: Die erste Zeile beim Jahreswechsel ohne Fach — bei mehreren des Namens die erste des Angebots")
    func vorgabeOhneFach() {
        let zeilen = [Hochstufung.Zeile(id: "n-1", name: "7a", fach: "Biologie", art: .unterricht, titel: "7a · Biologie"),
                      Hochstufung.Zeile(id: "n-2", name: "7a", fach: "Chemie", art: .unterricht, titel: "7a · Chemie")]
        #expect(Hochstufung.vorgabe(name: "7a", uebernommen: nil, zeilen: zeilen) == "n-1")
        #expect(Hochstufung.vorgabe(name: "7a", uebernommen: "n-2", zeilen: zeilen) == "n-2",
                "die übernommene geht vor")
    }
}
