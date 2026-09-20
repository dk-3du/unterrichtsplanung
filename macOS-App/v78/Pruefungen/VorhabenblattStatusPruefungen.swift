// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Das Vorhaben-Blatt puffert seinen Entwurf. „Übernehmen“ schrieb Haken und
/// Kommentar aus dem Entwurf immer zurück — auch wenn niemand sie im Blatt
/// berührt hatte — und stempelte frisch, sobald sie vom Bestand abwichen. Ein
/// Stand vom iPad, der die Planung inzwischen erreicht hätte, wäre damit
/// überschrieben und ausgestempelt worden (elfte Review, Abschnitt 5; E122).
///
/// Jetzt gilt für die beiden Felder, die sich die App mit der Ansicht teilt,
/// dieselbe Regel wie für den Prüfungstermin: **Geschrieben wird nur, was der
/// Entwurf gegenüber seinem Ausgangsstand geändert hat.** Ein Bedienweg, auf
/// dem ein Status das offene Blatt unterläuft, ist nicht bekannt — die Schranke
/// steht für jeden, der noch kommt. Ohne Fenster: Entwurf öffnen, Stand
/// anwenden, Entwurf übernehmen.
@Suite("Vorhaben-Blatt: Status")
struct VorhabenblattStatusPruefungen {

    private static let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    private static func zeit(_ sekunden: Int) -> Date { t0.addingTimeInterval(Double(sekunden)) }
    private static func stempel(_ sekunden: Int) -> String {
        Pruefuhr.angehalten(zeit(sekunden)) { Zeitrechnung.jetztAlsZeitstempel() }
    }

    private static func iPad(_ id: String, erledigt: Bool, kommentar: String = "", bei sekunden: Int) -> Statusstand {
        Statusstand(gespeichert: stempel(sekunden), planungstitel: "Blatt",
                    eintraege: [id: .init(erledigt: erledigt, kommentar: kommentar, geaendert: stempel(sekunden))])
    }

    @MainActor
    private func speicher() throws -> (Planungsspeicher, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "blatt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        var p = Planung.leer(titel: "Blatt", start: try #require(Tag(iso: "2026-08-03")), wochen: 6,
                             basis: "", klassen: [
                                Klasse(id: "k1", name: "G6a", fach: "Informatik", notiz: "", farbe: 0,
                                       farbeManuell: false)],
                             fachfarben: [:])
        p.eintraege = [
            Vorhaben(id: "v1", klasseId: "k1", woche: 1, titel: "Erstes", text: "Text",
                     erledigt: false, materialien: [], links: [],
                     kommentar: "", statusGeaendert: VorhabenblattStatusPruefungen.stempel(0)),
        ]
        s.planung = p
        return (s, ordner)
    }

    @MainActor
    private func vorhaben(_ s: Planungsspeicher) throws -> Vorhaben {
        try #require(s.planung?.eintraege.first { $0.id == "v1" })
    }

    @MainActor
    @Test("Ein Haken vom iPad, der das offene Blatt erreicht, überlebt das Übernehmen — der Entwurf hat ihn nicht angefasst")
    func hakenVomiPadBleibt() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        var entwurf = VorhabenEntwurf(try vorhaben(s))
        s.statusAnwenden(VorhabenblattStatusPruefungen.iPad("v1", erledigt: true, bei: 1))
        #expect(try vorhaben(s).erledigt, "der Stand von T1 greift an der offenen Planung")

        entwurf.titel = "Neuer Titel"
        Pruefuhr.angehalten(VorhabenblattStatusPruefungen.zeit(2)) { s.vorhabenSichern(entwurf) }
        let v = try vorhaben(s)
        #expect(v.titel == "Neuer Titel")
        #expect(v.erledigt, "der Haken vom iPad bleibt — der Entwurf trug nur den Ausgangsstand")
        #expect(v.statusGeaendert == VorhabenblattStatusPruefungen.stempel(1), "und sein Stempel bleibt T1, nicht T2")
    }

    @MainActor
    @Test("Dasselbe für den Kommentar")
    func kommentarVomiPadBleibt() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        var entwurf = VorhabenEntwurf(try vorhaben(s))
        s.statusAnwenden(VorhabenblattStatusPruefungen.iPad("v1", erledigt: false, kommentar: "vom iPad", bei: 1))
        entwurf.text = "Andere Beschreibung"
        Pruefuhr.angehalten(VorhabenblattStatusPruefungen.zeit(2)) { s.vorhabenSichern(entwurf) }
        let v = try vorhaben(s)
        #expect(v.text == "Andere Beschreibung")
        #expect(v.kommentar == "vom iPad" && v.statusGeaendert == VorhabenblattStatusPruefungen.stempel(1))
    }

    @MainActor
    @Test("Was der Entwurf ändert, gewinnt und stempelt frisch — was er nicht ändert, bleibt vom iPad")
    func entwurfGewinntNurWoErAendert() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        var entwurf = VorhabenEntwurf(try vorhaben(s))
        s.statusAnwenden(VorhabenblattStatusPruefungen.iPad("v1", erledigt: false, kommentar: "vom iPad", bei: 1))
        entwurf.erledigt = true
        Pruefuhr.angehalten(VorhabenblattStatusPruefungen.zeit(2)) { s.vorhabenSichern(entwurf) }
        let v = try vorhaben(s)
        #expect(v.erledigt, "der Haken aus dem Blatt")
        #expect(v.kommentar == "vom iPad", "der Kommentar vom iPad — im Blatt nicht berührt")
        #expect(v.statusGeaendert == VorhabenblattStatusPruefungen.stempel(2), "die Entscheidung im Blatt ist die jüngere")
    }

    @MainActor
    @Test("Hin und zurück ist nicht geändert: Der Haken vom iPad bleibt")
    func hinUndZurueckIstKeineAenderung() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        var entwurf = VorhabenEntwurf(try vorhaben(s))
        entwurf.erledigt = true
        entwurf.erledigt = false
        #expect(!entwurf.hakenGeaendert && !entwurf.kommentarGeaendert)
        s.statusAnwenden(VorhabenblattStatusPruefungen.iPad("v1", erledigt: true, bei: 1))
        Pruefuhr.angehalten(VorhabenblattStatusPruefungen.zeit(2)) { s.vorhabenSichern(entwurf) }
        #expect(try vorhaben(s).erledigt && (try vorhaben(s).statusGeaendert) == VorhabenblattStatusPruefungen.stempel(1))
    }

    @MainActor
    @Test("Ohne Stand dazwischen schreibt das Blatt wie bisher — und ein neues Vorhaben trägt seinen Stempel, sobald es belegt ist")
    func ohneStandWieBisher() throws {
        let (s, ordner) = try speicher()
        defer { try? FileManager.default.removeItem(at: ordner) }
        var entwurf = VorhabenEntwurf(try vorhaben(s))
        entwurf.kommentar = "  am Mac notiert  "
        #expect(entwurf.kommentarGeaendert)
        Pruefuhr.angehalten(VorhabenblattStatusPruefungen.zeit(2)) { s.vorhabenSichern(entwurf) }
        #expect(try vorhaben(s).kommentar == "am Mac notiert" && (try vorhaben(s).statusGeaendert) == VorhabenblattStatusPruefungen.stempel(2))

        // Derselbe Kommentar noch einmal übernommen: inhaltlich gleich — kein neuer Stempel.
        var erneut = VorhabenEntwurf(try vorhaben(s))
        erneut.kommentar = "am Mac notiert "
        Pruefuhr.angehalten(VorhabenblattStatusPruefungen.zeit(3)) { s.vorhabenSichern(erneut) }
        #expect(try vorhaben(s).statusGeaendert == VorhabenblattStatusPruefungen.stempel(2), "gleicher Inhalt, gleicher Stempel")

        var neu = VorhabenEntwurf(klasseId: "k1", woche: 2)
        neu.titel = "Neu"
        neu.erledigt = true
        Pruefuhr.angehalten(VorhabenblattStatusPruefungen.zeit(4)) { s.vorhabenSichern(neu) }
        let angelegt = try #require(s.planung?.eintraege.first { $0.titel == "Neu" })
        #expect(angelegt.erledigt && angelegt.statusGeaendert == VorhabenblattStatusPruefungen.stempel(4))
    }
}
