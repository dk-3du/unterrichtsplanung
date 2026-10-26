// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Der dritte Schauplatz: der Entwurf im Blatt „Lernende“ (v80, AP7). Wie im
/// Sitzplanblatt ein eigener Verlauf auf dem Entwurf; „Übernehmen“ schreibt,
/// „Abbrechen“ verwirft (E82).
@Suite("Rücknahme: Lernende")
struct RuecknahmeLernendenPruefungen {

    struct Fall: Sendable {
        let name: String
        /// Der Handgriff am Entwurf — genau die Funktionen, die auch das Blatt ruft.
        let tun: @Sendable (Lernendenbestand) -> Lernendenbestand
        var kennung: String?
        /// Der Stand, an dem der Handgriff ansetzt — ohne Angabe `entwurf()` (Z-AX3-03).
        var ausgang: Lernendenbestand?
    }

    static let stempel = "2026-10-03T08:00:00.000Z"

    /// Zwei Gruppen (g-2 archiviert), drei Personen (l-3 archiviert), eine
    /// Mitteilung an g-1 mit einem Rücklauf, eine Maßnahme für l-2 und ein
    /// Termin ohne Gruppe für l-2 (E290).
    static func entwurf() -> Lernendenbestand {
        let s = stempel
        var b = Lernendenbestand.leer(planung: "2026-08-10T09:00:00.000Z", schuljahr: "2026/27", jetzt: s)
        b.lernende = [Lernender(id: "l-1", vorname: "Anna", nachname: "Abel", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-2", vorname: "Ben", nachname: "Bauer", angelegt: s, geaendert: s, archiviert: ""),
                      Lernender(id: "l-3", vorname: "Cem", nachname: "Celik", angelegt: s, geaendert: s, archiviert: s)]
        b.lerngruppen = [
            Lerngruppe(id: "g-1", name: "6a", art: .klasse, mitglieder: ["l-1", "l-2"],
                       zeilen: [], skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: ""),
            Lerngruppe(id: "g-2", name: "AG Garten", art: .kurs, mitglieder: ["l-3"],
                       zeilen: [], skalen: [:], halbjahreswechsel: "", geaendert: s, archiviert: s),
        ]
        b.anliegen = [Anliegen(id: "m-1", art: .mitteilung, titel: "Elternbrief", lerngruppe: "g-1",
                               betroffene: ["l-1", "l-2"], datum: "2026-10-01", frist: "", notiz: "",
                               angelegt: s, geaendert: s),
                      Anliegen(id: "m-2", art: .massnahme, titel: "Nacharbeit", lerngruppe: "g-1",
                               betroffene: ["l-2"], datum: "2026-10-02", frist: "2026-10-09", notiz: "",
                               angelegt: s, geaendert: s),
                      Anliegen(id: "m-3", art: .termin, titel: "Elterngespräch", lerngruppe: "",
                               betroffene: ["l-2"], datum: "2026-10-20", frist: "", uhrzeit: "07:45", notiz: "",
                               angelegt: s, geaendert: s)]
        b.rueckmeldungen = [Rueckmeldung(anliegen: "m-1", lernender: "l-1", stand: .erledigt,
                                         datum: "2026-10-02", notiz: "", geaendert: s)]
        return b
    }

    /// Der Tag, gegen den die Vereinbarung in `mitVereinbarung()` abgelaufen ist — fest, nicht die Wanduhr (Z-AX3-03).
    static let nachDemAblauf = "2026-11-05"

    /// `entwurf()` mit der Vereinbarung „Handyregel“ (v-1) an g-1 für Anna und Ben, gültig bis einschließlich 31.10.2026 —
    /// gegen `nachDemAblauf` abgelaufen; Ben ist von Hand ungültig (Z-AX3-03).
    static func mitVereinbarung() -> Lernendenbestand {
        var b = entwurf()
        b.anliegen.append(Anliegen(id: "v-1", art: .vereinbarung, titel: "Handyregel", lerngruppe: "g-1",
                                   betroffene: ["l-1", "l-2"], datum: "2026-10-01", frist: "2026-10-31",
                                   notiz: "Das Handy bleibt in der Tasche.", angelegt: stempel, geaendert: stempel,
                                   ungueltig: ["l-2"]))
        return b
    }

    static let faelle: [Fall] = [
        Fall(name: Schrittname.lerngruppeAnlegen) { b in
            b.mitNeuerGruppe(name: "7c", art: .kurs, jetzt: stempel)?.bestand ?? b
        },
        Fall(name: Schrittname.lerngruppeUmbenennen, tun: { b in
            b.mitGruppe("g-1", name: "6a (neu)", jetzt: stempel)
        }, kennung: "g-1"),
        Fall(name: Schrittname.lerngruppeArchivieren) { b in b.mitArchivierterGruppe("g-1", jetzt: stempel) },
        Fall(name: Schrittname.lerngruppeZurueckholen) { b in b.mitZurueckgeholterGruppe("g-2", jetzt: "2026-10-05T08:00:00.000Z", sitzplanzeilen: []) },
        Fall(name: Schrittname.lerngruppeLoeschen) { b in b.ohneGruppe("g-1").bestand },
        Fall(name: Schrittname.namenEintragen) { b in
            b.mitPersonen(Namenszeilen.lesen("Weber, Clara\nDavid Ernst").namen, inGruppe: "g-1", jetzt: stempel).bestand
        },
        Fall(name: Schrittname.nameAendern, tun: { b in
            b.mitPerson("l-1", vorname: "Anne", nachname: "Abel", jetzt: stempel)
        }, kennung: "l-1"),
        Fall(name: Schrittname.personArchivieren) { b in b.mitArchivierterPerson("l-1", jetzt: stempel) },
        Fall(name: Schrittname.personZurueckholen) { b in b.mitZurueckgeholterPerson("l-3", jetzt: "2026-10-05T08:00:00.000Z") },
        Fall(name: Schrittname.personLoeschen) { b in b.ohnePerson("l-1").bestand },
        Fall(name: Schrittname.ausLerngruppeNehmen) { b in b.ohneMitglied("l-1", ausGruppe: "g-1", jetzt: stempel) },
        // Das Menü „Lerngruppen“ (v84, E365): g-2 ist archiviert — die aktive zweite Gruppe entsteht im selben Fall.
        Fall(name: Schrittname.inLerngruppeAufnehmen) { b in
            guard let (c, id) = b.mitNeuerGruppe(name: "7c", art: .kurs, jetzt: stempel) else { return b }
            return c.mitMitglied("l-1", inGruppe: id, jetzt: stempel) ?? b
        },
        Fall(name: Schrittname.inAndereLerngruppeUmziehen) { b in
            guard let (c, id) = b.mitNeuerGruppe(name: "7c", art: .kurs, jetzt: stempel) else { return b }
            return c.mitUmzug("l-1", von: "g-1", nach: id, jetzt: stempel) ?? b
        },
        // Kopf der Lerngruppe (v84, AT9a-2): Zeilen wählen (E669) — an zwei Zeilen der Planung; zusammenführen (E667, E672) —
        // die zweite „6a“ entsteht im selben Fall.
        Fall(name: Schrittname.zeilenWaehlen) { b in
            let zeilen = [Klasse(id: "k-1", name: "6a", fach: "Biologie", notiz: "", farbe: Farbwelt.ohneFarbe, farbeManuell: false),
                          Klasse(id: "k-2", name: "6a", fach: "Chemie", notiz: "", farbe: Farbwelt.ohneFarbe, farbeManuell: false)]
            return b.mitZeilen("g-1", ["k-1", "k-2"], zeilen: zeilen, planung: b.planung, jetzt: stempel)
        },
        Fall(name: Schrittname.lerngruppenZusammenfuehren) { b in
            guard let (c, id) = b.mitNeuerGruppe(name: "6a", art: .klasse, jetzt: stempel),
                  let d = c.mitNeuemAnliegen(.mitteilung, titel: "Ausflug", lerngruppe: id, betroffene: [], datum: "2026-10-05",
                                             frist: "", jetzt: stempel)?.bestand else { return b }
            let e = d.mitPersonen(Namenszeilen.lesen("Weber, Clara").namen, inGruppe: id, jetzt: stempel).bestand
            return e.mitZusammenfuehrung(id, in: "g-1", jetzt: stempel).bestand
        },
        // Anliegen (AP8)
        Fall(name: Schrittname.mitteilungAnlegen) { b in
            b.mitNeuemAnliegen(.mitteilung, titel: "Ausflug", lerngruppe: "g-1", betroffene: ["l-1", "l-2"],
                               datum: "2026-10-05", frist: "", jetzt: stempel)?.bestand ?? b
        },
        Fall(name: Schrittname.massnahmeAnlegen) { b in
            b.mitNeuemAnliegen(.massnahme, titel: "Heft nachreichen", lerngruppe: "g-1", betroffene: ["l-1"],
                               datum: "2026-10-05", frist: "2026-10-12", jetzt: stempel)?.bestand ?? b
        },
        Fall(name: Schrittname.mitteilungAendern, tun: { b in
            b.mitAnliegen("m-1", titel: "Elternbrief Wandertag", datum: "2026-10-01", frist: "", notiz: "", jetzt: stempel)
        }, kennung: "m-1"),
        Fall(name: Schrittname.massnahmeAendern, tun: { b in
            b.mitAnliegen("m-2", titel: "Nacharbeit", datum: "2026-10-02", frist: "2026-10-16", notiz: "", jetzt: stempel)
        }, kennung: "m-2"),
        Fall(name: Schrittname.mitteilungLoeschen) { b in b.ohneAnliegen("m-1").bestand },
        Fall(name: Schrittname.massnahmeLoeschen) { b in b.ohneAnliegen("m-2").bestand },
        // E290: Termine ohne Gruppe an der Person.
        Fall(name: Schrittname.terminAnlegen) { b in
            b.mitNeuemAnliegen(.termin, titel: "Elterngespräch", lerngruppe: "", betroffene: ["l-1"], datum: "2026-10-21",
                               frist: "", uhrzeit: "7:45", jetzt: stempel)?.bestand ?? b
        },
        Fall(name: Schrittname.terminAendern, tun: { b in
            b.mitAnliegen("m-3", titel: "Elterngespräch", datum: "2026-10-22", frist: "", notiz: "", uhrzeit: "08:00",
                          jetzt: stempel)
        }, kennung: "m-3"),
        Fall(name: Schrittname.terminLoeschen) { b in b.ohneAnliegen("m-3").bestand },
        Fall(name: Schrittname.betroffeneAendern) { b in b.mitBetroffenem("m-1", "l-2", false, jetzt: stempel) },
        Fall(name: Schrittname.ruecklaufEintragen, tun: { b in
            b.mitRuecklauf("m-1", "l-2", stand: .abgelehnt, datum: "2026-10-03", notiz: "kein Einverständnis", jetzt: stempel)
        }, kennung: "m-1/l-2"),
        // Strang A (AX3): Vereinbarungen (E741, E751) — die neue entsteht im selben Fall; Löschen und Gültigkeit setzen an
        // der bestehenden in `mitVereinbarung()` an (Z-AX3-03).
        Fall(name: Schrittname.vereinbarungAnlegen) { b in
            b.mitNeuemAnliegen(.vereinbarung, titel: "Handyregel", lerngruppe: "g-1", betroffene: ["l-2"],
                               datum: "2026-10-03", frist: "2026-10-31", jetzt: stempel)?.bestand ?? b
        },
        Fall(name: Schrittname.vereinbarungAendern) { b in
            guard let (c, id) = b.mitNeuemAnliegen(.vereinbarung, titel: "Handyregel", lerngruppe: "g-1", betroffene: ["l-2"],
                                                   datum: "2026-10-03", frist: "", jetzt: stempel) else { return b }
            return c.mitAnliegen(id, titel: "Handyregel", datum: "2026-10-03", frist: "2026-11-30",
                                 notiz: "Das Handy bleibt in der Tasche.", jetzt: stempel)
        },
        Fall(name: Schrittname.vereinbarungLoeschen, tun: { b in b.ohneAnliegen("v-1").bestand },
             ausgang: mitVereinbarung()),
        // Der Weg nach E751: „gültig“ für Anna nach dem Ablauf hebt die Gültigkeit bis einschließlich auf.
        Fall(name: Schrittname.gueltigkeitAendern, tun: { b in
            guard let heute = Unterrichtsplanung.Tag(iso: nachDemAblauf) else { return b }
            return b.mitGueltigkeit("v-1", "l-1", .gueltig, heute: heute, jetzt: stempel).bestand
        }, ausgang: mitVereinbarung()),
        // AP13: der Import als ein Schritt — neue Person in g-1, eine neue Gruppe je Klasse.
        Fall(name: Schrittname.ausIServImportieren) { b in
            let lesung = IServImport.Lesung(zeilen: [
                IServImport.Zeile(nummer: 2, vorname: "Dora", nachname: "Dietz", klasse: "7b"),
                IServImport.Zeile(nummer: 3, vorname: "Anna", nachname: "Abel", klasse: "7b")])
            return b.mitImport(lesung, ziel: .jeKlasse, jetzt: stempel).bestand
        },
        Fall(name: Schrittname.fehlendeArchivieren) { b in b.mitArchiviertenPersonen(["l-1", "l-2"], jetzt: stempel) },
        // Strang A (AX4): die Sammelgriffe mit Anna und Ben — je ein Schritt, der Name mit 2 (E757, E759). Die neue Gruppe
        // für Aufnehmen und Umziehen entsteht im selben Fall.
        Fall(name: Schrittname.personenAufnehmen(2)) { b in
            guard let (c, id) = b.mitNeuerGruppe(name: "7c", art: .kurs, jetzt: stempel) else { return b }
            return c.mitMitgliedern(["l-1", "l-2"], inGruppe: id, jetzt: stempel).bestand
        },
        Fall(name: Schrittname.personenUmziehen(2)) { b in
            guard let (c, id) = b.mitNeuerGruppe(name: "7c", art: .kurs, jetzt: stempel) else { return b }
            return c.mitUmzuegen(["l-1", "l-2"], von: "g-1", nach: id, jetzt: stempel).bestand
        },
        Fall(name: Schrittname.personenAusLerngruppeNehmen(2)) { b in
            b.ohneMitgliedern(["l-1", "l-2"], ausGruppe: "g-1", jetzt: stempel).bestand
        },
        Fall(name: Schrittname.personenArchivieren(2)) { b in
            b.mitArchiviertenGewaehlten(["l-1", "l-2"], jetzt: stempel).bestand
        },
        Fall(name: Schrittname.personenLoeschen(2)) { b in b.ohnePersonen(["l-1", "l-2"]).bestand },
    ]

    @MainActor
    @Test("Tun, widerrufen, wiederholen — über alle Handgriffe am Entwurf",
          arguments: RuecknahmeLernendenPruefungen.faelle.indices)
    func hinUndZurueck(_ nummer: Int) throws {
        try Pruefuhr.angehalten {
            let fall = RuecknahmeLernendenPruefungen.faelle[nummer]
            let verlauf = Ruecknahme<Lernendenbestand>()
            let vorher = fall.ausgang ?? RuecknahmeLernendenPruefungen.entwurf()
            let nachher = fall.tun(vorher)
            #expect(nachher != vorher, Comment(rawValue: "\(fall.name): Der Handgriff muss etwas ändern"))

            verlauf.anmelden(fall.name, kennung: fall.kennung, vorher: vorher, nachher: nachher)
            #expect(verlauf.naechsterName == fall.name)
            let zurueck = try #require(verlauf.zuruecknehmen())
            #expect(zurueck.vorher == vorher, Comment(rawValue: "\(fall.name): Person für Person wie vorher"))
            let vor = try #require(verlauf.wiederholen())
            #expect(vor.nachher == nachher, Comment(rawValue: "\(fall.name): und wie danach"))
        }
    }

    /// Derselbe Handgriff durch das Blatt: ⌘Z und ⇧⌘Z über den Speicher setzen den
    /// Entwurf des Blatts — so, wie das Blatt ihn bekommt (W4-07).
    @MainActor
    @Test("Tun, widerrufen, wiederholen — durch das Blatt: Der Speicher setzt den Entwurf zurück und wieder vor",
          arguments: RuecknahmeLernendenPruefungen.faelle.indices)
    func durchDasBlatt(_ nummer: Int) throws {
        try #require(Ablage.istPruefstand, "die Prüfung braucht einen eigenen Ablageort (PLANUNGSORDNER)")
        let ordner = URL.temporaryDirectory
            .appending(component: "ruecknahme-blatt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let fall = RuecknahmeLernendenPruefungen.faelle[nummer]
        let speicher = Planungsspeicher(ablage: Ablage(ordner: ordner))
        let vorher = fall.ausgang ?? RuecknahmeLernendenPruefungen.entwurf()
        var imBlatt = vorher
        speicher.lernendenblattUebernimmt({ imBlatt = $0 })
        Pruefuhr.angehalten {
            let nachher = fall.tun(vorher)
            imBlatt = nachher
            speicher.lernendenverlauf.anmelden(fall.name, kennung: fall.kennung, vorher: vorher, nachher: nachher)
            speicher.widerrufen()
            #expect(imBlatt == vorher, Comment(rawValue: "\(fall.name): ⌘Z setzt das Blatt auf den Stand davor"))
            speicher.wiederholen()
            #expect(imBlatt == nachher, Comment(rawValue: "\(fall.name): ⇧⌘Z wieder auf den danach"))
        }
    }

    @MainActor
    @Test("Umbenennen in einer Schreibphase ist ein Schritt, zwei Gruppen sind zwei")
    func schreibphase() {
        let verlauf = Ruecknahme<Lernendenbestand>()
        let anfang = RuecknahmeLernendenPruefungen.entwurf()
        Pruefuhr.angehalten {
            var stand = anfang
            for name in ["6", "6a", "6a B"] {
                let neu = stand.mitGruppe("g-1", name: name, jetzt: Self.stempel)
                verlauf.anmelden(Schrittname.lerngruppeUmbenennen, kennung: "g-1", vorher: stand, nachher: neu)
                stand = neu
            }
            #expect(verlauf.zurueck.count == 1)
            let andere = stand.mitGruppe("g-2", name: "AG Beet", jetzt: Self.stempel)
            verlauf.anmelden(Schrittname.lerngruppeUmbenennen, kennung: "g-2", vorher: stand, nachher: andere)
        }
        #expect(verlauf.zurueck.count == 2)
        #expect(verlauf.zurueck.first?.vorher == anfang)
    }

    @Test("Die Fälle des Menüs „Lerngruppen“ tun, was ihr Name sagt — nicht nur die neue Gruppe anlegen (Z-AT2b-11)")
    func menuefaelle() throws {
        let anfang = Self.entwurf()
        for name in [Schrittname.inLerngruppeAufnehmen, Schrittname.inAndereLerngruppeUmziehen] {
            let fall = try #require(Self.faelle.first { $0.name == name })
            let danach = fall.tun(anfang)
            let neu = try #require(danach.lerngruppen.first { g in !anfang.lerngruppen.contains { $0.id == g.id } })
            #expect(neu.mitglieder == ["l-1"], "\(name): l-1 in der neuen Gruppe")
            let g1 = danach.lerngruppen.first { $0.id == "g-1" }?.mitglieder.contains("l-1")
            #expect(g1 == (name == Schrittname.inLerngruppeAufnehmen), "\(name): in g-1 nur beim Aufnehmen")
        }
    }

    @Test("Die Sammelfälle tun, was ihr Name sagt — beide Personen in einem Schritt (AX4)")
    func sammelfaelle() throws {
        let anfang = Self.entwurf()
        func danach(_ name: String) throws -> Lernendenbestand {
            let fallOderNil = Self.faelle.first { $0.name == name }
            let fall = try #require(fallOderNil)
            return fall.tun(anfang)
        }
        let aufgenommen = try danach(Schrittname.personenAufnehmen(2))
        let neuOderNil = aufgenommen.lerngruppen.first { g in !anfang.lerngruppen.contains { $0.id == g.id } }
        let neu = try #require(neuOderNil)
        #expect(neu.mitglieder == ["l-1", "l-2"] && aufgenommen.lerngruppen.first { $0.id == "g-1" }?.mitglieder == ["l-1", "l-2"])
        let umgezogen = try danach(Schrittname.personenUmziehen(2))
        let zielOderNil = umgezogen.lerngruppen.first { g in !anfang.lerngruppen.contains { $0.id == g.id } }
        let ziel = try #require(zielOderNil)
        #expect(ziel.mitglieder == ["l-1", "l-2"] && umgezogen.lerngruppen.first { $0.id == "g-1" }?.mitglieder == [])
        let heraus = try danach(Schrittname.personenAusLerngruppeNehmen(2))
        #expect(heraus.lerngruppen.first { $0.id == "g-1" }?.mitglieder == [] && heraus.lernende == anfang.lernende)
        let archiviert = try danach(Schrittname.personenArchivieren(2))
        let zeiten = archiviert.lernende.filter { ["l-1", "l-2"].contains($0.id) }.map(\.archiviert)
        #expect(zeiten == [Self.stempel, Self.stempel])
        let geloescht = try danach(Schrittname.personenLoeschen(2))
        let uebrig = geloescht.lernende.map(\.id)
        #expect(uebrig == ["l-3"])
    }

    @Test("Der Fall „Lerngruppen zusammenführen“ tut, was sein Name sagt — die neue „6a“ archiviert, ihr Mitglied und ihre Mitteilung bei g-1 (Z-AT9a2-13)")
    func zusammenfuehrenFall() throws {
        let anfang = Self.entwurf()
        let fall = try #require(Self.faelle.first { $0.name == Schrittname.lerngruppenZusammenfuehren })
        let danach = fall.tun(anfang)
        let neu = try #require(danach.lerngruppen.first { g in !anfang.lerngruppen.contains { $0.id == g.id } })
        #expect(!neu.archiviert.isEmpty, "die neue „6a“ ist archiviert")
        let clara = try #require(danach.lernende.first { $0.vorname == "Clara" })
        #expect(danach.lerngruppen.first { $0.id == "g-1" }?.mitglieder.contains(clara.id) == true, "Clara in g-1")
        #expect(danach.anliegen.first { $0.titel == "Ausflug" }?.lerngruppe == "g-1", "die Mitteilung an g-1")
    }

    @MainActor
    // ⌘Z und ⇧⌘Z durch das Blatt trägt `durchDasBlatt` für beide Fälle — mit ihrem eigenen Ausgangsstand (Z-R2A2-06).
    @Test("Die Fälle der Vereinbarung tun, was ihr Name sagt — Löschen nimmt genau sie, „Gültigkeit ändern“ hebt nach dem Ablauf das Datum auf; ⌘Z durch das Blatt prüft `durchDasBlatt` (Z-AX3-03)")
    func vereinbarungsfaelle() throws {
        let loeschenOderNil = Self.faelle.first { $0.name == Schrittname.vereinbarungLoeschen }
        let loeschen = try #require(loeschenOderNil)
        let ausgangLoeschen = loeschen.ausgang
        let ohne = loeschen.tun(try #require(ausgangLoeschen)).anliegen.map(\.id)
        #expect(ohne == ["m-1", "m-2", "m-3"], "nur die Vereinbarung geht")
        let aendernOderNil = Self.faelle.first { $0.name == Schrittname.gueltigkeitAendern }
        let aendern = try #require(aendernOderNil)
        let ausgangAendern = aendern.ausgang
        let danach = aendern.tun(try #require(ausgangAendern))
        let vOderNil = danach.anliegen.first { $0.id == "v-1" }
        let v = try #require(vOderNil)
        #expect(v.frist.isEmpty && v.ungueltig == ["l-2"], "das Datum aufgehoben, Ben bleibt von Hand ungültig")
        let tagOderNil = Unterrichtsplanung.Tag(iso: Self.nachDemAblauf)
        let heute = try #require(tagOderNil)
        #expect(Lernendenbestand.gueltigkeit(v, "l-1", heute: heute) == .gueltig, "Anna gilt sie wieder")
    }
}
