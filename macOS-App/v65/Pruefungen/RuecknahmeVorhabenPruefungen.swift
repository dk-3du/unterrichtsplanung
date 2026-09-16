// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Jede Handlung an einem Vorhaben lässt sich zurücknehmen (S3).
///
/// Geprüft wird je Handlung dasselbe: tun → widerrufen → **Wert für Wert** wie
/// vorher; wiederholen → Wert für Wert wie danach. Der Vergleich nimmt die
/// ganze Planung, nicht das eine Feld — so fällt auch auf, was eine Handlung
/// nebenbei anfasst. Die Uhr steht dabei (E81): Sonst unterschiede allein der
/// Zeitstempel zwei Stände, die gleich sein müssen.
///
/// **Bis auf den Statusstempel** (N58-01, E109): Ein Widerrufen legt den Inhalt
/// zurück, aber keine veraltete Autorität gegenüber dem Stand vom iPad — ein
/// Vorhaben, dessen Haken oder Kommentar die Rücknahme ändert, trägt danach
/// einen frischen `statusGeaendert`. Der Vergleich „Wert für Wert“ lässt
/// diesen einen Stempel darum aus; dass er stimmt, prüft der Abschnitt
/// „Statusautorität“ mit fortschreitender Uhr.
@Suite("Rücknahme: Vorhaben")
struct RuecknahmeVorhabenPruefungen {

    /// Die Planung ohne die Statusstempel ihrer Vorhaben — für den Vergleich
    /// „Wert für Wert“ (siehe oben).
    static func bisAufDenStempel(_ p: Planung?) -> Planung? {
        guard var p else { return nil }
        for stelle in p.eintraege.indices { p.eintraege[stelle].statusGeaendert = "" }
        return p
    }

    struct Fall: Sendable {
        /// Der Name, der im Menü stehen muss.
        let name: String
        /// Was vor der Momentaufnahme geschehen muss — für die Gegenrichtung
        /// eines Schalters: erst hinzufügen, dann entfernen.
        var vorbereiten: (@Sendable @MainActor (Planungsspeicher, String) -> Void)?
        let tun: @Sendable @MainActor (Planungsspeicher, String) -> Void
    }

    static let faelle: [Fall] = [
        Fall(name: Schrittname.titelAendern) { s, id in
            s.titelSetzen(vorhaben: id, titel: "Ganz neuer Titel")
        },
        Fall(name: Schrittname.vorhabenUmstellen) { s, id in s.reihen(id, nachOben: false) },
        Fall(name: Schrittname.vorhabenAbhaken) { s, id in s.erledigtUmschalten(id) },
        Fall(name: Schrittname.hakenEntfernen,
             vorbereiten: { s, id in s.erledigtUmschalten(id) }) { s, id in
            s.erledigtUmschalten(id)
        },
        Fall(name: Schrittname.dringlichKennzeichnen) { s, id in s.dringlichUmschalten(id) },
        Fall(name: Schrittname.dringlichkeitEntfernen,
             vorbereiten: { s, id in s.dringlichUmschalten(id) }) { s, id in
            s.dringlichUmschalten(id)
        },
        Fall(name: Schrittname.hausaufgabeHinzufuegen) { s, id in s.hausaufgabeUmschalten(id) },
        Fall(name: Schrittname.hausaufgabeEntfernen,
             vorbereiten: { s, id in s.hausaufgabeUmschalten(id) }) { s, id in
            s.hausaufgabeUmschalten(id)
        },
        Fall(name: Schrittname.alsPruefungFuehren) { s, id in s.pruefungUmschalten(id) },
        Fall(name: Schrittname.pruefungEntfernen,
             vorbereiten: { s, id in s.pruefungUmschalten(id) }) { s, id in
            s.pruefungUmschalten(id)
        },
        Fall(name: Schrittname.vorhabenVerschieben) { s, id in
            s.vorhabenVerschieben(id, klasse: "k2", woche: 2)
        },
        Fall(name: Schrittname.vorhabenAendern) { s, id in
            guard let vorhaben = s.planung?.eintraege.first(where: { $0.id == id }) else { return }
            var entwurf = VorhabenEntwurf(vorhaben)
            entwurf.text = "Aus dem Dialog geändert"
            entwurf.dringend = true
            s.vorhabenSichern(entwurf)
        },
        Fall(name: Schrittname.vorhabenHinzufuegen) { s, _ in
            var entwurf = VorhabenEntwurf(klasseId: "k1", woche: 3)
            entwurf.titel = "Neu aus dem Dialog"
            s.vorhabenSichern(entwurf)
        },
        Fall(name: Schrittname.vorhabenEntfernen) { s, id in
            s.vorhabenLoeschen(id, ort: .hauptansicht)
            s.rueckfrageBeantworten(true)
        },
    ]

    @MainActor
    private func speicher() throws -> (Planungsspeicher, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "vorhaben-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        var p = Planung.leer(titel: "Vorhaben", start: try #require(Tag(iso: "2026-08-03")), wochen: 6,
                             basis: "", klassen: [
                                Klasse(id: "k1", name: "G6a", fach: "Informatik", notiz: "", farbe: 0,
                                       farbeManuell: false),
                                Klasse(id: "k2", name: "G7b", fach: "Mathematik", notiz: "", farbe: 1,
                                       farbeManuell: false)],
                             fachfarben: [:])
        // Zwei in derselben Zelle — sonst ließe sich nichts umstellen.
        p.eintraege = [
            Vorhaben(id: "v1", klasseId: "k1", woche: 1, titel: "Erstes", text: "Text",
                     erledigt: false, materialien: [], links: []),
            Vorhaben(id: "v2", klasseId: "k1", woche: 1, titel: "Zweites", text: "Text",
                     erledigt: false, materialien: [], links: []),
        ]
        s.planung = p
        return (s, ordner)
    }

    @MainActor
    @Test("Tun, widerrufen, wiederholen — über alle Handlungen",
          arguments: RuecknahmeVorhabenPruefungen.faelle.indices)
    func hinUndZurueck(_ nummer: Int) throws {
        // Aufbau und Handlung unter derselben angehaltenen Uhr: `sichern()`
        // stempelt auch beim Widerrufen, und ein Stempel von vorhin machte
        // zwei Stände ungleich, die gleich sein müssen.
        try Pruefuhr.angehalten {
            let fall = RuecknahmeVorhabenPruefungen.faelle[nummer]
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }

            fall.vorbereiten?(s, "v1")
            let vorher = try #require(s.planung)
            fall.tun(s, "v1")
            let nachher = try #require(s.planung)
            #expect(nachher != vorher, Comment(rawValue: "\(fall.name): die Handlung muss etwas ändern"))
            #expect(s.verlauf.naechsterName == fall.name,
                    Comment(rawValue: "\(fall.name): im Menü steht „\(s.widerrufenTitel)“"))

            s.widerrufen()
            #expect(RuecknahmeVorhabenPruefungen.bisAufDenStempel(s.planung)
                    == RuecknahmeVorhabenPruefungen.bisAufDenStempel(vorher),
                    Comment(rawValue: "\(fall.name): Wert für Wert wie vorher"))

            s.wiederholen()
            #expect(RuecknahmeVorhabenPruefungen.bisAufDenStempel(s.planung)
                    == RuecknahmeVorhabenPruefungen.bisAufDenStempel(nachher),
                    Comment(rawValue: "\(fall.name): Wert für Wert wie danach"))
        }
    }

    @MainActor
    @Test("Jede Handlung ist ein eigener Schritt — keine fasst die andere ein")
    func jedeHandlungEinSchritt() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        Pruefuhr.angehalten {
            s.erledigtUmschalten("v1")
            s.dringlichUmschalten("v1")
            s.hausaufgabeUmschalten("v1")
        }
        #expect(s.verlauf.zurueck.count == 3, "drei Handgriffe, drei Schritte")
        #expect(s.verlauf.zurueck.map(\.name)
                == [Schrittname.vorhabenAbhaken, Schrittname.dringlichKennzeichnen,
                    Schrittname.hausaufgabeHinzufuegen])
    }

    @MainActor
    @Test("Der Titel an der Kachel bleibt ein Schritt, so lange daran getippt wird (E88)")
    func titelIstEineSchreibphase() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let vorher = try #require(s.planung)
            s.titelSetzen(vorhaben: "v1", titel: "E")
            s.titelSetzen(vorhaben: "v1", titel: "Er")
            s.titelSetzen(vorhaben: "v1", titel: "Erst")
            s.titelSetzen(vorhaben: "v1", titel: "Erstens")
            #expect(s.verlauf.zurueck.count == 1, "ein Titel, ein Schritt")
            s.widerrufen()
            #expect(s.planung == vorher, "und zurück geht es bis vor den ersten Tastendruck — ein Titel trägt keinen Statusstempel")
        }
    }

    @MainActor
    @Test("Zwei Titel an zwei Kacheln sind zwei Schritte")
    func zweiKachelnZweiSchritte() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        Pruefuhr.angehalten {
            s.titelSetzen(vorhaben: "v1", titel: "Eins")
            s.titelSetzen(vorhaben: "v2", titel: "Zwei")
        }
        #expect(s.verlauf.zurueck.count == 2)
    }

    @MainActor
    @Test("Die Auswahl steht nach einer Rücknahme auf dem, was wieder da ist")
    func auswahlNachDerRuecknahme() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        s.anwaehlen(vorhaben: "v1")
        s.vorhabenLoeschen("v1", ort: .hauptansicht)
        s.rueckfrageBeantworten(true)
        #expect(s.planung?.eintraege.contains { $0.id == "v1" } == false)
        #expect(!s.auswahl.contains("v1"), "was fort ist, bleibt nicht angewählt")

        s.widerrufen()
        #expect(s.planung?.eintraege.contains { $0.id == "v1" } == true, "und ist wieder da")
    }

    // ── Statusautorität nach der Rücknahme (N58-01, E109) ─────────────────
    //
    // Der Statusabgleich misst je Vorhaben gegen `statusGeaendert`. Legte das
    // Widerrufen mit der Momentaufnahme auch den alten Stempel zurück, gewänne
    // ein liegengebliebener iPad-Stand (T1) gegen ein Widerrufen bei T3 — und
    // `statusAnwenden` schriebe das. Mit fortschreitender Uhr (E81), ohne zu
    // warten (E105).

    /// Eine Uhr in der Vergangenheit — Stempel aus der Zukunft weist der
    /// Abgleich als unbrauchbar ab.
    private static let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    private static func zeit(_ sekunden: Int) -> Date { t0.addingTimeInterval(Double(sekunden)) }
    private static func stempel(_ sekunden: Int) -> String {
        Pruefuhr.angehalten(zeit(sekunden)) { Zeitrechnung.jetztAlsZeitstempel() }
    }

    @MainActor
    private func vorhaben(_ s: Planungsspeicher, _ id: String) throws -> Vorhaben {
        try #require(s.planung?.eintraege.first { $0.id == id })
    }

    /// Ein Stand vom iPad zum Zeitpunkt `sekunden`: `erledigt` und Kommentar für ein Vorhaben.
    private static func iPad(_ id: String, erledigt: Bool, kommentar: String = "", bei sekunden: Int) -> Statusstand {
        Statusstand(gespeichert: stempel(sekunden), planungstitel: "Vorhaben",
                    eintraege: [id: .init(erledigt: erledigt, kommentar: kommentar, geaendert: stempel(sekunden))])
    }

    @MainActor
    @Test("Ein Widerrufen bei T3 schlägt einen iPad-Stand von T1 — der Haken bleibt fort (N58-01)")
    func widerrufenSchlaegtAelterenStand() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        var p = try #require(s.planung)
        p.eintraege[0].statusGeaendert = RuecknahmeVorhabenPruefungen.stempel(0)
        s.planung = p
        let vomiPad = RuecknahmeVorhabenPruefungen.iPad("v1", erledigt: true, bei: 1)

        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(2)) { s.erledigtUmschalten("v1") }
        #expect(try vorhaben(s, "v1").erledigt && (try vorhaben(s, "v1").statusGeaendert) == RuecknahmeVorhabenPruefungen.stempel(2))

        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(3)) { s.widerrufen() }
        #expect(!(try vorhaben(s, "v1").erledigt), "der Haken ist zurückgenommen")
        #expect(try vorhaben(s, "v1").statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(3),
                "und das Widerrufen ist die jüngste Entscheidung — nicht T0 aus der Momentaufnahme")

        s.statusAnwenden(vomiPad)
        #expect(!(try vorhaben(s, "v1").erledigt), "T1 ist älter als T3: der iPad-Stand greift nicht")

        // Sichern und lesen: Der Stempel überlebt die Datei.
        let gelesen = try Planungsdatei.lesenMitBilanz(try Planungsdatei.schreiben(try #require(s.planung))).0
        #expect(gelesen.eintraege.first { $0.id == "v1" }?.statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(3))
    }

    @MainActor
    @Test("Auch das Wiederholen ist eine Entscheidung — und der Kommentar zählt wie der Haken")
    func wiederholenUndKommentar() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }

        // Wiederholen bei T4 gegen einen iPad-Stand „offen“ von T3,5.
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(2)) { s.erledigtUmschalten("v1") }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(3)) { s.widerrufen() }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(4)) { s.wiederholen() }
        #expect(try vorhaben(s, "v1").erledigt)
        #expect(try vorhaben(s, "v1").statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(4))
        s.statusAnwenden(RuecknahmeVorhabenPruefungen.iPad("v1", erledigt: false, bei: 3))
        #expect(try vorhaben(s, "v1").erledigt, "der Haken vom Wiederholen bleibt")

        // Der Kommentar aus dem Dialog, widerrufen bei T6, gegen einen iPad-Kommentar von T5.
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(5)) {
            var entwurf = VorhabenEntwurf(try! vorhaben(s, "v2"))
            entwurf.kommentar = "am Mac notiert"
            s.vorhabenSichern(entwurf)
        }
        #expect(try vorhaben(s, "v2").kommentar == "am Mac notiert")
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(6)) { s.widerrufen() }
        #expect(try vorhaben(s, "v2").kommentar == "" && (try vorhaben(s, "v2").statusGeaendert) == RuecknahmeVorhabenPruefungen.stempel(6))
        s.statusAnwenden(RuecknahmeVorhabenPruefungen.iPad("v2", erledigt: false, kommentar: "vom iPad", bei: 5))
        #expect(try vorhaben(s, "v2").kommentar == "", "der iPad-Kommentar von T5 ist älter als das Widerrufen bei T6")
    }

    @MainActor
    @Test("Unberührte und wiederhergestellte Vorhaben behalten ihren Stempel — ein anstehender iPad-Stand greift dort (E109 (a))")
    func unberuehrteBehaltenIhrenStempel() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }

        // v2 bleibt unberührt, während v1 abgehakt und widerrufen wird.
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(2)) { s.erledigtUmschalten("v1") }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(3)) { s.widerrufen() }
        #expect(try vorhaben(s, "v2").statusGeaendert == "", "nie angefasst — und das bleibt so")
        s.statusAnwenden(RuecknahmeVorhabenPruefungen.iPad("v2", erledigt: true, bei: 1))
        #expect(try vorhaben(s, "v2").erledigt, "der iPad-Stand zu v2 ist berechtigt")

        // v1 wird gelöscht und mit ⌘Z wiederhergestellt: Es wurde nicht entschieden,
        // nur zurückgeholt — sein Stempel ist der aus der Momentaufnahme.
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(4)) {
            s.vorhabenLoeschen("v1", ort: .hauptansicht)
            s.rueckfrageBeantworten(true)
        }
        #expect(s.planung?.eintraege.contains { $0.id == "v1" } == false)
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(5)) { s.widerrufen() }
        #expect(try vorhaben(s, "v1").statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(3),
                "wiederhergestellt, nicht neu entschieden")
        s.statusAnwenden(RuecknahmeVorhabenPruefungen.iPad("v1", erledigt: true, bei: 4))
        #expect(try vorhaben(s, "v1").erledigt, "ein iPad-Stand von T4 greift an dem Vorhaben, das seit T3 nicht angefasst wurde")
    }

    @MainActor
    @Test("Der Stempel geht nie rückwärts — auch wenn die Uhr es tut")
    func stempelNieRueckwaerts() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(20)) { s.erledigtUmschalten("v1") }
        // Die Uhr springt zurück (falsch gestellt, Zeitzone, NTP): Das Widerrufen
        // darf den Stempel nicht unter den letzten gesetzten fallen lassen.
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(10)) { s.widerrufen() }
        #expect(try vorhaben(s, "v1").statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(20))
    }

    // ── Kein Zurücklegen senkt einen Stempel (N58-01, Rest; E120, E121) ───
    //
    // E109 stempelte, was die Rücknahme an Haken oder Kommentar ändert. Ein
    // Vorhaben, das gleich bleibt, kam mit dem Stempel der Momentaufnahme
    // zurück — auch wenn es inzwischen einen jüngeren trug. Ein zweites,
    // sachfremdes Widerrufen (der Titel) legte so den Stempel von T4 auf T0
    // zurück, und der iPad-Stand von T1 gewann wieder (elfte Review, v61).

    @MainActor
    @Test("Ein zweites, sachfremdes Widerrufen lässt den Stempel stehen — der iPad-Stand von T1 bleibt abgewiesen (N58-01, Rest)")
    func zweitesWiderrufenSenktNichts() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        var p = try #require(s.planung)
        p.eintraege[0].statusGeaendert = RuecknahmeVorhabenPruefungen.stempel(0)
        s.planung = p
        let vomiPad = RuecknahmeVorhabenPruefungen.iPad("v1", erledigt: true, bei: 1)

        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(2)) { s.titelSetzen(vorhaben: "v1", titel: "Umbenannt") }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(3)) { s.erledigtUmschalten("v1") }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(4)) { s.widerrufen() }
        let nachErstem = try vorhaben(s, "v1")
        #expect(!nachErstem.erledigt && nachErstem.statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(4),
                "das erste Widerrufen stempelt frisch (E109)")

        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(5)) { s.widerrufen() }
        #expect(try vorhaben(s, "v1").titel == "Erstes", "der Titel ist zurück")
        #expect(try vorhaben(s, "v1").statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(4),
                "Haken und Kommentar blieben gleich — der Stempel bleibt der jüngere (T4), nicht T0 aus der Momentaufnahme")

        s.statusAnwenden(vomiPad)
        #expect(!(try vorhaben(s, "v1").erledigt), "T1 ist älter als T4: der iPad-Stand greift auch nach dem zweiten Widerrufen nicht")

        // Und durch die Datei: Der Stempel überlebt Schreiben und Lesen, dann erst der Stand.
        var gelesen = try Planungsdatei.lesenMitBilanz(try Planungsdatei.schreiben(try #require(s.planung))).0
        #expect(gelesen.eintraege.first { $0.id == "v1" }?.statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(4))
        _ = Statusabgleich.anwenden(vomiPad, auf: &gelesen, jetzt: RuecknahmeVorhabenPruefungen.zeit(6))
        #expect(gelesen.eintraege.first { $0.id == "v1" }?.erledigt == false)
    }

    @MainActor
    @Test("Dasselbe mit dem Kommentar — und mit dem Wiederholen")
    func kommentarUndWiederholenSenkenNichts() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }

        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(2)) { s.titelSetzen(vorhaben: "v2", titel: "Umbenannt") }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(3)) {
            var entwurf = VorhabenEntwurf(try! vorhaben(s, "v2"))
            entwurf.kommentar = "am Mac notiert"
            s.vorhabenSichern(entwurf)
        }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(4)) { s.widerrufen() }
        #expect(try vorhaben(s, "v2").kommentar == "" && (try vorhaben(s, "v2").statusGeaendert) == RuecknahmeVorhabenPruefungen.stempel(4))
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(5)) { s.widerrufen() }
        #expect(try vorhaben(s, "v2").statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(4), "der Titel geht zurück, der Stempel nicht")
        s.statusAnwenden(RuecknahmeVorhabenPruefungen.iPad("v2", erledigt: false, kommentar: "vom iPad", bei: 1))
        #expect(try vorhaben(s, "v2").kommentar == "", "der iPad-Kommentar von T1 ist älter als T4")

        // Wiederholen des Titels bei T6: die Momentaufnahme „nachher“ von T2 trägt keinen Stempel — T4 bleibt.
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(6)) { s.wiederholen() }
        #expect(try vorhaben(s, "v2").titel == "Umbenannt" && (try vorhaben(s, "v2").statusGeaendert) == RuecknahmeVorhabenPruefungen.stempel(4))
        // Wiederholen des Kommentars bei T7: geändert → frisch.
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(7)) { s.wiederholen() }
        #expect(try vorhaben(s, "v2").kommentar == "am Mac notiert" && (try vorhaben(s, "v2").statusGeaendert) == RuecknahmeVorhabenPruefungen.stempel(7))
    }

    @MainActor
    @Test("Verschränkt über zwei Vorhaben: die Rücknahme am einen lässt den Stempel des anderen, wie er ist")
    func verschraenktBleibtJedesBeiSeinem() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(2)) { s.erledigtUmschalten("v1") }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(3)) { s.titelSetzen(vorhaben: "v2", titel: "Anders") }
        Pruefuhr.angehalten(RuecknahmeVorhabenPruefungen.zeit(4)) { s.widerrufen() }
        #expect(try vorhaben(s, "v2").titel == "Zweites")
        #expect(try vorhaben(s, "v1").statusGeaendert == RuecknahmeVorhabenPruefungen.stempel(2), "v1 wurde nicht angefasst: sein Stempel bleibt T2")
        #expect(try vorhaben(s, "v2").statusGeaendert == "", "v2 trug keinen Stempel und bekommt keinen")
        s.statusAnwenden(RuecknahmeVorhabenPruefungen.iPad("v1", erledigt: false, bei: 1))
        #expect(try vorhaben(s, "v1").erledigt, "der Haken von T2 hält gegen den iPad-Stand von T1")
    }

    /// Ein kleiner, gesäter Zufall (SplitMix64) — dieselbe Saat, dieselbe
    /// Folge; `SystemRandomNumberGenerator` ließe einen Verstoß nicht wiederholen.
    private struct Saat: RandomNumberGenerator {
        var zustand: UInt64
        mutating func next() -> UInt64 {
            zustand &+= 0x9E37_79B9_7F4A_7C15
            var z = zustand
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @MainActor
    @Test("Eigenschaft: In 200 gesäten Folgen senkt keine Rücknahme den Stempel eines Vorhabens, das bleibt (E121)")
    func keineRuecknahmeSenktEinenStempel() throws {
        for saat in 1...200 {
            var zufall = Saat(zustand: UInt64(saat))
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            var folge: [String] = []
            for schritt in 1...10 {
                let jetzt = RuecknahmeVorhabenPruefungen.zeit(schritt)
                let id = Bool.random(using: &zufall) ? "v1" : "v2"
                let vorher = try #require(s.planung).eintraege
                let handlung = Int.random(in: 0..<6, using: &zufall)
                switch handlung {
                case 0, 1:
                    folge.append("Haken \(id)")
                    Pruefuhr.angehalten(jetzt) { s.erledigtUmschalten(id) }
                case 2:
                    folge.append("Titel \(id)")
                    Pruefuhr.angehalten(jetzt) { s.titelSetzen(vorhaben: id, titel: "Titel \(schritt)") }
                case 3:
                    folge.append("Kommentar \(id)")
                    Pruefuhr.angehalten(jetzt) {
                        guard let v = s.planung?.eintraege.first(where: { $0.id == id }) else { return }
                        var entwurf = VorhabenEntwurf(v)
                        entwurf.kommentar = "K\(schritt)"
                        s.vorhabenSichern(entwurf)
                    }
                default:
                    let zurueck = handlung == 4
                    folge.append(zurueck ? "⌘Z" : "⇧⌘Z")
                    Pruefuhr.angehalten(jetzt) { if zurueck { s.widerrufen() } else { s.wiederholen() } }
                    let nachher = try #require(s.planung).eintraege
                    let frisch = RuecknahmeVorhabenPruefungen.stempel(schritt)
                    for alt in vorher {
                        guard let neu = nachher.first(where: { $0.id == alt.id }) else { continue }
                        let beschreibung = "Saat \(saat), Folge \(folge.joined(separator: " → ")), Vorhaben \(alt.id)"
                        #expect(neu.statusGeaendert >= alt.statusGeaendert, "\(beschreibung): Stempel gesunken")
                        if neu.erledigt != alt.erledigt || neu.kommentar != alt.kommentar {
                            #expect(neu.statusGeaendert == frisch, "\(beschreibung): geändert, aber nicht frisch gestempelt")
                        }
                    }
                }
            }
        }
    }

    // ── Ein Blatt vor dem Schauplatz (E112, E118) ─────────────────────────
    //
    // Das Vorhaben-Blatt puffert seinen Entwurf; ⌘Z änderte derweil die Planung
    // hinter dem Blatt, und „Übernehmen“ schrieb den Entwurf über den
    // zurückgelegten Stand. Jetzt ruht der Hauptverlauf, solange ein Blatt
    // außer dem Sitzplan-Editor offen ist — er wird nicht geleert, er wartet.

    @MainActor
    @Test("Solange das Vorhaben-Blatt offen ist, ruht der Hauptverlauf — und gilt danach wieder (E112)")
    func vorhabenBlattLaesstDenVerlaufRuhen() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            s.erledigtUmschalten("v1")
            #expect(s.kannWiderrufen && s.widerrufenTitel == "Widerrufen: " + Schrittname.vorhabenAbhaken)

            s.vorhabenDialog = VorhabenEntwurf(klasseId: "k1", woche: 1)
            #expect(!s.kannWiderrufen && !s.kannWiederholen, "vor dem Blatt ist nichts zurückzunehmen")
            #expect(s.widerrufenTitel == "Widerrufen" && s.wiederholenTitel == "Wiederholen",
                    "und das Menü verspricht keinen Schritt: „\(s.widerrufenTitel)“")
            s.widerrufen()
            #expect(try vorhaben(s, "v1").erledigt, "⌘Z ändert nichts hinter dem Blatt")
            #expect(s.verlauf.zurueck.count == 1, "der Verlauf ruht — er ist nicht geleert")

            s.vorhabenDialog = nil
            #expect(s.kannWiderrufen, "Blatt zu: der Schritt ist wieder da")
            s.widerrufen()
            #expect(!(try vorhaben(s, "v1").erledigt), "und geht zurück")
            #expect(s.kannWiederholen)
            s.vorhabenDialog = VorhabenEntwurf(klasseId: "k1", woche: 1)
            s.wiederholen()
            #expect(!(try vorhaben(s, "v1").erledigt), "auch das Wiederholen ruht vor dem Blatt")
            s.vorhabenDialog = nil
            s.wiederholen()
            #expect(try vorhaben(s, "v1").erledigt)
        }
    }

    @MainActor
    @Test("Jedes andere Blatt lässt den Hauptverlauf ruhen — der Sitzplan-Editor nicht, er hat seinen eigenen")
    func andereBlaetterRuhenSitzplanNicht() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            s.erledigtUmschalten("v1")
            for blatt in [Dialogfenster.klassen, .ferien, .pruefungen, .einstellungen, .hilfe] {
                s.dialogOeffnen(blatt)
                #expect(!s.kannWiderrufen, Comment(rawValue: "\(blatt.rawValue): der Hauptverlauf ruht"))
                s.widerrufen()
                #expect(try vorhaben(s, "v1").erledigt, Comment(rawValue: "\(blatt.rawValue): ⌘Z ändert nichts"))
                s.alleDialogeSchliessen()
                #expect(s.kannWiderrufen, Comment(rawValue: "\(blatt.rawValue): zu — der Schritt ist wieder da"))
            }
            // Der Sitzplan-Editor hat seinen eigenen Verlauf (E82) — solange das
            // Blatt ihn führt, gilt der; im Prüfziel ohne Blatt bleibt der
            // Hauptverlauf frei, wie bisher.
            s.dialogOeffnen(.sitzplan)
            #expect(s.kannWiderrufen, "der Sitzplan-Editor lässt den Hauptverlauf nicht ruhen")
            s.alleDialogeSchliessen()
        }
    }
}
