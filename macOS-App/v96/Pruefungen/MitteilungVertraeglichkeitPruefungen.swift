// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Mitteilungen mit Frist und an Einzelne — ohne neue Fassung (v91, BC1) ──
// 2.6.0 schreibt an einer Mitteilung die Rückmeldefrist in `frist` und die Adressaten in `betroffene`; beide Felder trägt
// Fassung 2 schon für jede Art. Der Leser liest sie ohne Verlust, der Schreiber schreibt sie bytegleich zurück, und an einer
// Mitteilung entsteht kein Schlüssel, den 2.5.0 nicht kennt — sonst ginge er beim Zurückschreiben durch 2.5.0 verloren.
// Die Probe mit dem Paket 2.5.0 selbst geht über einen Lauf, nicht über diese Suite. Dazu die Saat des Prototyps
// (`Lernendenprobe.mitteilungssaat`).

@Suite("Mitteilungen mit Frist und an Einzelne: Fassung 2 trägt sie, 2.5.0 liest und schreibt ohne Verlust (BC1)")
struct MitteilungVertraeglichkeitPruefungen {

    private static let s = "2026-11-02T08:00:00.000Z"

    /// Die Schlüssel einer Mitteilung, wie 2.5.0 sie schreibt — ohne Uhrzeit, „ungueltig“ und Rückverweis, die nur wo
    /// gesetzt stehen und an einer Mitteilung nie.
    private static let schluesselZweiFuenf: Set<String> = ["angelegt", "art", "betroffene", "datum", "frist", "geaendert",
                                                           "id", "lerngruppe", "notiz", "titel"]

    /// Die oberste Ebene und ein Rücklauf, wie 2.5.0 sie schreibt (Z-BC1-01).
    private static let obenZweiFuenf: Set<String> = ["anliegen", "beurteilung", "erfassung", "erstellt", "geaendert",
                                                     "leistungen", "lerngruppen", "lernende", "planung", "rueckmeldungen",
                                                     "schuljahr", "typ", "verhalten", "version"]
    private static let ruecklaufZweiFuenf: Set<String> = ["anliegen", "datum", "geaendert", "lernender", "notiz", "stand"]

    /// SHA-256 der Datei, die der Schreiber von 2.5.0 aus `bestand()` macht — eingefroren am Schreiber von v91 vor BC2, der
    /// dem von 2.5.0 gleicht (Z-BC1-01). Ändert ein späterer Zug die Form, wird das hier rot und muss begründet werden.
    private static let eingefroren = "9e7b7983e5b3980ab6f3f0f3c1cca486c7214b462872f3dc34088d4c8439786d"

    private static func person(_ id: String, _ vorname: String, _ nachname: String) -> Lernender {
        Lernender(id: id, vorname: vorname, nachname: nachname, angelegt: s, geaendert: s, archiviert: "")
    }

    /// „5a“ mit Anna, Ben, Clara und Emil; „Wandertag“ an alle mit Frist, „Fotos“ an Anna und Clara mit Frist,
    /// „Elternabend“ an Ben ohne Frist — Rückläufe nur von Betroffenen.
    private static func bestand() -> Lernendenbestand {
        var b = Lernendenbestand.leer(planung: "p-1", schuljahr: "2026/27", jetzt: s)
        b.lernende = [person("l-anna", "Anna", "Adam"), person("l-ben", "Ben", "Brandt"),
                      person("l-clara", "Clara", "Conrad"), person("l-emil", "Emil", "Eck")]
        b.lerngruppen = [Lerngruppe(id: "g-5a", name: "5a", art: .klasse, mitglieder: b.lernende.map(\.id), zeilen: [],
                                    skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: "")]
        b.anliegen = [
            Anliegen(id: "m-w", art: .mitteilung, titel: "Wandertag", lerngruppe: "g-5a", betroffene: b.lernende.map(\.id),
                     datum: "2026-09-01", frist: "2026-09-08", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "m-f", art: .mitteilung, titel: "Fotos", lerngruppe: "g-5a", betroffene: ["l-anna", "l-clara"],
                     datum: "2026-09-03", frist: "2026-09-10", notiz: "", angelegt: s, geaendert: s),
            Anliegen(id: "m-e", art: .mitteilung, titel: "Elternabend", lerngruppe: "g-5a", betroffene: ["l-ben"],
                     datum: "2026-09-05", frist: "", notiz: "", angelegt: s, geaendert: s),
        ]
        b.rueckmeldungen = [
            Rueckmeldung(anliegen: "m-f", lernender: "l-clara", stand: .erledigt, datum: "2026-09-04", notiz: "",
                         geaendert: s),
            Rueckmeldung(anliegen: "m-w", lernender: "l-emil", stand: .abgelehnt, datum: "2026-09-09", notiz: "krank",
                         geaendert: s),
        ]
        return b
    }

    @Test("Frist und Teil-Betroffene einer Mitteilung: gelesen ohne Verlust, bytegleich zurückgeschrieben, Fassung 2")
    func ohneVerlust() throws {
        let b = Self.bestand()
        let daten = try Lernendendatei.schreiben(b)
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(daten)
        #expect(gelesen == b, "der Stand, wie er geschrieben wurde")
        #expect(bilanz.istLeer && !bilanz.verlust && !bilanz.umzuschreiben, "\(bilanz.beschreibung)")
        #expect(gelesen.anliegen.map(\.frist) == ["2026-09-08", "2026-09-10", ""], "die Fristen")
        #expect(gelesen.anliegen.map(\.betroffene)
                == [["l-anna", "l-ben", "l-clara", "l-emil"], ["l-anna", "l-clara"], ["l-ben"]], "die Adressaten")
        #expect(try Lernendendatei.schreiben(gelesen) == daten, "bytegleich zurück")
        let objekt = try #require(JSONSerialization.jsonObject(with: daten) as? [String: Any])
        #expect(Planungsdatei.ganzzahl(objekt["version"]) == 2, "keine neue Fassung")
    }

    @Test("An einer Mitteilung kein Schlüssel, den 2.5.0 nicht kennt — sonst ginge er beim Zurückschreiben durch 2.5.0 verloren")
    func keineNeuenSchluessel() throws {
        let daten = try Lernendendatei.schreiben(Self.bestand())
        let objekt = try #require(JSONSerialization.jsonObject(with: daten) as? [String: Any])
        let anliegen = try #require(objekt["anliegen"] as? [[String: Any]])
        #expect(anliegen.count == 3)
        for a in anliegen {
            let schluessel = Set(a.keys)
            #expect(schluessel == Self.schluesselZweiFuenf,
                    "\(a["id"] ?? "—"): \(schluessel.symmetricDifference(Self.schluesselZweiFuenf).sorted())")
        }
        // Auch oben und am Rücklauf nichts Neues (Z-BC1-01).
        let oben = Set(objekt.keys)
        #expect(oben == Self.obenZweiFuenf, "oben: \(oben.symmetricDifference(Self.obenZweiFuenf).sorted())")
        let rueck = try #require(objekt["rueckmeldungen"] as? [[String: Any]])
        #expect(rueck.count == 2)
        for r in rueck {
            let schluessel = Set(r.keys)
            #expect(schluessel == Self.ruecklaufZweiFuenf,
                    "Rücklauf: \(schluessel.symmetricDifference(Self.ruecklaufZweiFuenf).sorted())")
        }
    }

    @Test("Die Datei aus Frist und Teil-Betroffenen bleibt Byte für Byte die von 2.5.0 — eingefroren vor BC2 (Z-BC1-01)")
    func eingefroren() throws {
        let daten = try Lernendendatei.schreiben(Self.bestand())
        let summe = SHA256.hash(data: daten).map { String(format: "%02x", $0) }.joined()
        #expect(summe == Self.eingefroren, "jetzt: \(summe)")
    }

    @Test("Aus dem Anlegeweg von 2.6.0 — an einzelne, mit Frist: kein neuer Schlüssel, ohne Verlust gelesen (Z-BC1-01, BC4)")
    func ausDemAnlegeweg() throws {
        let b = Self.bestand()
        let mitglieder = Lernendenverzeichnis(b).mitglieder("g-5a")
        let tag = try #require(Tag(iso: "2026-11-09"))
        let an = Mitteilungsadressaten.einzelne(["l-ben", "l-emil"]).betroffene(mitglieder)
        let frist = Ruecklaufliste.fristBeimAnlegen(mitFrist: true, tag)
        let neu = try #require(b.mitNeuemAnliegen(.mitteilung, titel: "Ausflug", lerngruppe: "g-5a", betroffene: an,
                                                  datum: "2026-11-02", frist: frist, jetzt: Self.s)).bestand
        let daten = try Lernendendatei.schreiben(neu)
        let objekt = try #require(JSONSerialization.jsonObject(with: daten) as? [String: Any])
        let anliegen = try #require(objekt["anliegen"] as? [[String: Any]])
        let a = try #require(anliegen.first { ($0["titel"] as? String) == "Ausflug" })
        let schluessel = Set(a.keys)
        #expect(schluessel == Self.schluesselZweiFuenf, "\(schluessel.symmetricDifference(Self.schluesselZweiFuenf).sorted())")
        #expect(a["frist"] as? String == "2026-11-09", "die Frist als Tag")
        #expect(a["betroffene"] as? [String] == ["l-ben", "l-emil"], "nur die Gewählten, in der Folge der Liste")
        #expect(Set(objekt.keys) == Self.obenZweiFuenf)
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(daten)
        #expect(gelesen == neu && bilanz.istLeer, "\(bilanz.beschreibung)")
    }

    @Test("Ein Rücklauf einer Person, die die Mitteilung nicht betrifft, verwirft der Leser — wie in 2.5.0, gezählt")
    func ruecklaufNurVonBetroffenen() throws {
        var b = Self.bestand()
        b.rueckmeldungen.append(Rueckmeldung(anliegen: "m-f", lernender: "l-ben", stand: .erledigt, datum: "2026-09-04",
                                             notiz: "", geaendert: Self.s))
        let (gelesen, bilanz) = try Lernendendatei.lesenMitBilanz(try Lernendendatei.schreiben(b))
        #expect(!gelesen.rueckmeldungen.contains { $0.anliegen == "m-f" && $0.lernender == "l-ben" })
        #expect(bilanz.verworfeneRueckmeldungen == 1)
    }

    @Test("Saat des Prototyps: an alle mit verstrichener Frist, an drei, ohne Frist; die später Gekommene nicht betroffen")
    func saat() throws {
        let heute = try #require(Tag(iso: "2026-11-02"))
        var b = Self.bestand()
        // Eine Archivierte in der Lerngruppe — die Saat richtet sich nur an die aktiven Mitglieder (Z-BC1-02).
        b.lernende.append(Lernender(id: "l-dora", vorname: "Dora", nachname: "Dorn", angelegt: Self.s, geaendert: Self.s,
                                    archiviert: Self.s))
        b.lerngruppen[0].mitglieder.append("l-dora")
        let neu = try #require(Lernendenprobe.mitteilungssaat(b, gruppe: "g-5a", heute: heute, jetzt: Self.s))
        let v = Lernendenverzeichnis(neu, heute: heute)
        let saat = Array(v.mitteilungen(der: "g-5a").suffix(3))
        #expect(saat.map(\.titel) == ["Elternbrief Wandertag", "Einverständnis Fotos", "Elternabend"])
        let aktive = ["l-anna", "l-ben", "l-clara", "l-emil"]
        #expect(saat.map(\.betroffene) == [aktive, Array(aktive.prefix(3)), aktive], "an alle, an drei, an alle")
        #expect(saat.map(\.datum) == ["2026-10-19", "2026-10-30", "2026-11-01"], "vor 14, 3 und 1 Tag")
        #expect(saat.map(\.frist) == ["2026-10-26", "2026-11-06", ""], "verstrichen, in vier Tagen, ohne")
        let nora = try #require(neu.lernende.first { $0.nachname == "Neu" }).id
        #expect(v.mitglieder("g-5a").contains { $0.id == nora }, "Nora ist Mitglied")
        #expect(!saat.contains { $0.betroffene.contains(nora) }, "… und von keiner Mitteilung betroffen")
        let brief = try #require(saat.first)
        #expect(brief.betroffene.map { v.stand(brief.id, $0) } == [.erledigt, .offen, .offen, .abgelehnt])
        #expect(neu.rueckmeldungen.filter { $0.anliegen == brief.id }.map(\.datum) == ["2026-10-24", "2026-10-25"],
                "erledigt vor 9, abgelehnt vor 8 Tagen")
        #expect(Lernendenprobe.mitteilungssaat(b, gruppe: "g-xx", heute: heute, jetzt: Self.s) == nil,
                "ohne die Lerngruppe nichts")
        // Mit drei Aktiven wäre „an drei“ dasselbe wie „an alle“ — dann keine Saat (Z-BC1-02).
        var drei = b
        drei.lernende[3].archiviert = Self.s
        #expect(Lernendenprobe.mitteilungssaat(drei, gruppe: "g-5a", heute: heute, jetzt: Self.s) == nil,
                "mit drei Aktiven nichts")
    }
}
