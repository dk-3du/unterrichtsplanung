// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Wochentag im Kachelmenü (v86, AX5, E655) ─────────────────────────────
// Das Untermenü „Wochentag“ mit „Mo.“ … „Fr.“ im Rechtsklickmenü einer Kachel: der gesetzte Tag mit Häkchen, ein Klick
// setzt das Datum dieses Wochentags in der Woche des Vorhabens, ein Klick auf den gesetzten nimmt es — ein Schritt, ⌘Z.
// Ein Termin wechselt seinen Tag nur (E293), über das Nachführen (`TerminkopplungPruefungen`); an einer Prüfung wandert
// der Prüfungstermin mit, wenn er auf dem Datum lag (E803) oder das Vorhaben kein Datum hat (E824), mit der Schranke des
// Blatts, sofern sich der Prüfungstermin ändert (Z-AX5-02). Die Unterrichtstage stehen im gebauten Menü halbfett (E781 a).

@Suite("Wochentag im Kachelmenü (E655)")
@MainActor
struct WochentagImKachelmenuePruefungen {

    private func vorhaben(_ s: Planungsspeicher, _ id: String) -> Vorhaben? {
        s.planung?.eintraege.first { $0.id == id }
    }

    /// „G6a“ mit Unterricht Mo. und Mi.; „Brüche“ in Woche 1 (10.–14.08.2026) ohne Datum, „Arbeit“ als Prüfung am Montag;
    /// am Donnerstag 13.08. ein Sperrzeitraum für alle Zeilen.
    private func speicher() throws -> (Planungsspeicher, URL) {
        let ordner = URL.temporaryDirectory
            .appending(component: "wochentag-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        var klasse = Klasse(id: "k1", name: "G6a", fach: "Mathematik", notiz: "", farbe: 0, farbeManuell: false)
        klasse.unterrichtstage = [.montag, .mittwoch]
        var p = Planung.leer(titel: "Wochentag", start: try #require(Tag(iso: "2026-08-03")), wochen: 6, basis: "",
                             klassen: [klasse], fachfarben: [:])
        let montag = try #require(Tag(iso: "2026-08-10"))
        let donnerstag = try #require(Tag(iso: "2026-08-13"))
        var arbeit = Vorhaben(id: "v2", klasseId: "k1", woche: 1, titel: "Arbeit", text: "", erledigt: false,
                              materialien: [], links: [])
        arbeit.pruefung = true
        arbeit.pruefungstag = montag
        arbeit.datum = montag
        p.eintraege = [
            Vorhaben(id: "v1", klasseId: "k1", woche: 1, titel: "Brüche", text: "", erledigt: false,
                     materialien: [], links: []),
            arbeit,
        ]
        p.sperrzeiten = [Sperrzeitraum(id: "s1", name: "Projekttag", von: donnerstag, bis: donnerstag)]
        s.planung = p
        return (s, ordner)
    }

    // ── Die Zeilen des Untermenüs ─────────────────────────────────────────

    @Test("Die Zeilen: „Mo.“ … „Fr.“, der gesetzte Tag mit Häkchen, die Unterrichtstage als Merkmal; ein Termin nimmt seinen Tag nicht")
    func zeilen() throws {
        let montag = try #require(Tag(iso: "2026-08-10"))
        var v = Vorhaben(id: "v", klasseId: "k1", woche: 1, titel: "Brüche", text: "", erledigt: false,
                         materialien: [], links: [])
        let ohne = Rasterkoordinator.wochentagzeilen(v, wochenmontag: montag, unterrichtstage: [.montag, .mittwoch])
        let titel = ohne.map { $0.titel }
        let unterricht = ohne.map { $0.unterricht }
        #expect(titel == ["Mo.", "Di.", "Mi.", "Do.", "Fr."])
        #expect(unterricht == [true, false, true, false, false])
        #expect(ohne.allSatisfy { !$0.gesetzt && !$0.gesperrt }, "ohne Datum: nichts gesetzt, alles wählbar")

        v.datum = Tag(iso: "2026-08-12")
        let mittwoch = Rasterkoordinator.wochentagzeilen(v, wochenmontag: montag, unterrichtstage: [])
        let gesetzt = mittwoch.map { $0.gesetzt }
        #expect(gesetzt == [false, false, true, false, false])
        #expect(mittwoch.allSatisfy { !$0.gesperrt }, "der gesetzte Tag lässt sich nehmen")

        v.datum = Tag(iso: "2026-08-19")
        #expect(Rasterkoordinator.wochentagzeilen(v, wochenmontag: montag, unterrichtstage: []).allSatisfy { !$0.gesetzt },
                "ein Datum außerhalb der Woche kreuzt keinen Tag an")

        // Ein Termin braucht einen Tag (E293): Sein Tag lässt sich wechseln, nicht nehmen.
        v.datum = Tag(iso: "2026-08-12")
        v.termin = "m-1"
        let termin = Rasterkoordinator.wochentagzeilen(v, wochenmontag: montag, unterrichtstage: [])
        let gesperrt = termin.map { $0.gesperrt }
        #expect(gesperrt == [false, false, true, false, false])

        #expect(Rasterkoordinator.wochentagzeilen(v, wochenmontag: nil, unterrichtstage: []).allSatisfy { $0.gesperrt },
                "ohne Woche ist nichts wählbar")
        #expect(Rasterkoordinator.wochentagzeilen(nil, wochenmontag: montag, unterrichtstage: []).allSatisfy { $0.gesperrt },
                "ohne Vorhaben ebenso")
    }

    /// Halbfett am gebauten Menü — gelesen aus dem Gewicht der Schrift im `attributedTitle`.
    private func halbfett(_ punkt: NSMenuItem) -> Bool {
        guard let titel = punkt.attributedTitle, titel.length > 0,
              let schrift = titel.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return false }
        let merkmale = schrift.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let gewicht = merkmale?[.weight] as? CGFloat ?? 0
        return abs(gewicht - NSFont.Weight.semibold.rawValue) < 0.01
    }

    @Test("E781 (a): Im gebauten Untermenü stehen genau die Unterrichtstage halbfett; Titel, Häkchen und Sperre bleiben")
    func unterrichtstageHalbfett() throws {
        let montag = try #require(Tag(iso: "2026-08-10"))
        var v = Vorhaben(id: "v", klasseId: "k1", woche: 1, titel: "Brüche", text: "", erledigt: false,
                         materialien: [], links: [])
        v.datum = Tag(iso: "2026-08-12")
        v.termin = "m-1"
        let zeilen = Rasterkoordinator.wochentagzeilen(v, wochenmontag: montag, unterrichtstage: [.montag, .mittwoch])
        let punkte = Rasterkoordinator.tagmenue(zeilen) { _ in }.items
        let titel = punkte.map { $0.title }
        let fett = punkte.map { halbfett($0) }
        let haekchen = punkte.map { $0.state == .on }
        let gesperrt = punkte.map { $0.action == nil }
        let sichtbar = punkte.map { $0.attributedTitle?.string ?? $0.title }
        #expect(titel == ["Mo.", "Di.", "Mi.", "Do.", "Fr."])
        #expect(fett == [true, false, true, false, false], "halbfett genau die Unterrichtstage Mo. und Mi.")
        #expect(haekchen == [false, false, true, false, false])
        #expect(gesperrt == [false, false, true, false, false], "der Tag des Termins bleibt grau")
        #expect(sichtbar == titel, "der sichtbare Text bleibt der Titel")
        // Die Bedienungshilfen bekommen den ganzen Tag, wie an den Kästchen der Unterrichtstage (Z-GR2-03).
        #expect(punkte.map { $0.accessibilityLabel() } == ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag"])
    }

    // ── Am Speicher ───────────────────────────────────────────────────────

    @Test("Am Speicher: ein Klick setzt den Tag der Woche, ein zweiter nimmt ihn — je ein Schritt mit ⌘Z und ⇧⌘Z")
    func setzenUndNehmen() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let vorher = try #require(s.planung)
            s.wochentagUmschalten("v1", .mittwoch)
            #expect(vorhaben(s, "v1")?.datum == Tag(iso: "2026-08-12"), "der Mittwoch der Woche des Vorhabens")
            #expect(s.verlauf.naechsterName == Schrittname.wochentagSetzen)
            let gesetzt = try #require(s.planung)
            s.widerrufen()
            #expect(s.planung == vorher)
            s.wiederholen()
            #expect(s.planung == gesetzt)

            s.wochentagUmschalten("v1", .mittwoch)
            #expect(vorhaben(s, "v1")?.datum == nil, "ein Klick auf den gesetzten nimmt ihn")
            #expect(s.verlauf.naechsterName == Schrittname.wochentagEntfernen)
            s.widerrufen()
            #expect(s.planung == gesetzt)

            s.wochentagUmschalten("v1", .freitag)
            #expect(vorhaben(s, "v1")?.datum == Tag(iso: "2026-08-14"), "ein anderer Tag wechselt")

            // Sperrzeiträume gelten nur für Prüfungen (Z-AX5-02): „Brüche“ darf auf den Projekttag.
            let meldungen = s.meldungen.count
            s.wochentagUmschalten("v1", .donnerstag)
            #expect(vorhaben(s, "v1")?.datum == Tag(iso: "2026-08-13") && s.meldungen.count == meldungen,
                    "kein Prüfungsvorhaben — der Sperrzeitraum hält es nicht auf")
        }
    }

    @Test("An einer Prüfung wandert der Prüfungstermin mit; im Sperrzeitraum bleibt alles, die Meldung des Blatts nennt ihn")
    func pruefungWandertMit() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            s.wochentagUmschalten("v2", .mittwoch)
            #expect(vorhaben(s, "v2")?.datum == Tag(iso: "2026-08-12") && vorhaben(s, "v2")?.pruefungstag == Tag(iso: "2026-08-12"),
                    "verlegt: Datum und Prüfungstermin")
            // Beide Felder in einem Schritt (Z-AX5-05).
            let verlegt = try #require(s.planung)
            s.widerrufen()
            #expect(vorhaben(s, "v2")?.datum == Tag(iso: "2026-08-10") && vorhaben(s, "v2")?.pruefungstag == Tag(iso: "2026-08-10"),
                    "⌘Z nimmt beide Felder zurück")
            s.wiederholen()
            #expect(s.planung == verlegt, "⇧⌘Z bringt beide wieder")

            let vorher = try #require(s.planung)
            let schritt = s.verlauf.naechsterName
            s.wochentagUmschalten("v2", .donnerstag)
            #expect(s.planung == vorher && s.verlauf.naechsterName == schritt, "im Sperrzeitraum bleibt alles, kein Schritt")
            #expect(s.meldungen.last?.text
                    == "Im Zeitraum vom 13.08.2026 bis zum 13.08.2026 dürfen keine Prüfungen eingetragen werden.",
                    Comment(rawValue: s.meldungen.last?.text ?? "—"))

            // Der gesetzte Tag nimmt nur das Datum — nie still den Prüfungstermin.
            s.wochentagUmschalten("v2", .mittwoch)
            #expect(vorhaben(s, "v2")?.datum == nil && vorhaben(s, "v2")?.pruefungstag == Tag(iso: "2026-08-12"))

            // Lag der Prüfungstermin nicht auf dem (gesetzten) Datum, wandert er nicht mit (E803, E824); dass er selbst im
            // Sperrzeitraum liegt — die Sperre kam später —, hält das Datum nicht auf (Z-AX5-02).
            let sperrtag = try #require(Tag(iso: "2026-08-13"))
            var spaeter = try #require(s.planung)
            var nachschreiben = Vorhaben(id: "v3", klasseId: "k1", woche: 1, titel: "Nachschreiben", text: "", erledigt: false,
                                         materialien: [], links: [])
            nachschreiben.pruefung = true
            nachschreiben.pruefungstag = sperrtag
            nachschreiben.datum = Tag(iso: "2026-08-10")
            spaeter.eintraege.append(nachschreiben)
            s.planung = spaeter
            let meldungen = s.meldungen.count
            s.wochentagUmschalten("v3", .donnerstag)
            #expect(vorhaben(s, "v3")?.datum == sperrtag && vorhaben(s, "v3")?.pruefungstag == sperrtag,
                    "der Tag des Prüfungstermins — keine Abweisung")
            #expect(s.meldungen.count == meldungen && s.verlauf.naechsterName == Schrittname.wochentagSetzen)
        }
    }

    @Test("E824: Datum genommen, dann neu gesetzt — der Prüfungstermin wandert mit, wie beim direkten Wechsel; samt Sperre und ⌘Z")
    func pruefungsterminNachGenommenemDatum() throws {
        try Pruefuhr.angehalten {
            // Der direkte Weg: „Arbeit“ Mi./Mi., dann Fr.
            let (direkt, ordner1) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner1) }
            direkt.wochentagUmschalten("v2", .mittwoch)
            direkt.wochentagUmschalten("v2", .freitag)
            // Der Umweg aus dem Review (Z-R2B1-01): Mi./Mi., Mi. nehmen, dann Fr.
            let (s, ordner2) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner2) }
            let mittwoch = try #require(Tag(iso: "2026-08-12"))
            let freitag = try #require(Tag(iso: "2026-08-14"))
            s.wochentagUmschalten("v2", .mittwoch)
            s.wochentagUmschalten("v2", .mittwoch)
            #expect(vorhaben(s, "v2")?.datum == nil && vorhaben(s, "v2")?.pruefungstag == mittwoch, "nur das Datum genommen")
            let genommen = try #require(s.planung)

            // Im Sperrzeitraum auf diesem Weg: abgewiesen wie im Blatt, kein Schritt.
            let schritt = s.verlauf.naechsterName
            s.wochentagUmschalten("v2", .donnerstag)
            #expect(s.planung == genommen && s.verlauf.naechsterName == schritt, "im Sperrzeitraum bleibt alles")
            #expect(s.meldungen.last?.text
                    == "Im Zeitraum vom 13.08.2026 bis zum 13.08.2026 dürfen keine Prüfungen eingetragen werden.",
                    Comment(rawValue: s.meldungen.last?.text ?? "—"))

            s.wochentagUmschalten("v2", .freitag)
            #expect(vorhaben(s, "v2")?.datum == freitag && vorhaben(s, "v2")?.pruefungstag == freitag,
                    "das Setzen nimmt den Prüfungstermin mit (E824)")
            #expect(vorhaben(s, "v2") == vorhaben(direkt, "v2"), "endet wie der direkte Klick Mi. → Fr.")
            #expect(s.verlauf.naechsterName == Schrittname.wochentagSetzen)
            let gesetzt = try #require(s.planung)
            s.widerrufen()
            #expect(s.planung == genommen, "⌘Z: wieder ohne Datum, der Prüfungstermin am Mittwoch")
            s.wiederholen()
            #expect(s.planung == gesetzt, "⇧⌘Z: beide am Freitag")
        }
    }

    @Test("Z-R2B1N-01: Ohne Datum, der Prüfungstermin schon am Sperrtag — das Setzen dieses Tages geht durch, ein Schritt")
    func ohneDatumAmSperrtag() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let donnerstag = try #require(Tag(iso: "2026-08-13"))
            var p = try #require(s.planung)
            var nachschreiben = Vorhaben(id: "v7", klasseId: "k1", woche: 1, titel: "Nachschreiben", text: "",
                                         erledigt: false, materialien: [], links: [])
            nachschreiben.pruefung = true
            nachschreiben.pruefungstag = donnerstag
            p.eintraege.append(nachschreiben)
            s.planung = p
            let meldungen = s.meldungen.count
            // Am Prüfungstermin ändert sich nichts — geprüft wird, was sich ändert (Z-AX5-02, `zulaessigerTermin`).
            s.wochentagUmschalten("v7", .donnerstag)
            #expect(vorhaben(s, "v7")?.datum == donnerstag && vorhaben(s, "v7")?.pruefungstag == donnerstag,
                    "Do./Do.")
            #expect(s.meldungen.count == meldungen, "keine Meldung")
            #expect(s.verlauf.naechsterName == Schrittname.wochentagSetzen, "ein Schritt")
        }
    }

    @Test("E803: Bei gesetztem Datum wandert der Prüfungstermin nur mit, wenn er darauf lag — ohne ihn bleibt er offen, ein abweichender bleibt")
    func pruefungsterminNurAufDemDatum() throws {
        try Pruefuhr.angehalten {
            let (s, ordner) = try speicher()
            defer { try? FileManager.default.removeItem(at: ordner) }
            let montag = try #require(Tag(iso: "2026-08-10"))
            let mittwoch = try #require(Tag(iso: "2026-08-12"))
            let donnerstag = try #require(Tag(iso: "2026-08-13"))
            let freitag = try #require(Tag(iso: "2026-08-14"))
            var p = try #require(s.planung)
            var ohne = Vorhaben(id: "v4", klasseId: "k1", woche: 1, titel: "Test", text: "", erledigt: false,
                                materialien: [], links: [])
            ohne.pruefung = true
            ohne.datum = montag
            var abweichend = Vorhaben(id: "v5", klasseId: "k1", woche: 1, titel: "Klausur", text: "", erledigt: false,
                                      materialien: [], links: [])
            abweichend.pruefung = true
            abweichend.datum = montag
            abweichend.pruefungstag = freitag
            // Weder Datum noch Prüfungstermin (Z-R2B1N-02): Nichts wandert mit, und der Sperrzeitraum hält nichts auf.
            var leer = Vorhaben(id: "v6", klasseId: "k1", woche: 1, titel: "Probe", text: "", erledigt: false,
                                materialien: [], links: [])
            leer.pruefung = true
            p.eintraege += [ohne, abweichend, leer]
            s.planung = p

            s.wochentagUmschalten("v4", .mittwoch)
            #expect(vorhaben(s, "v4")?.datum == mittwoch && vorhaben(s, "v4")?.pruefungstag == nil,
                    "ohne Prüfungstermin bleibt er offen")
            s.wochentagUmschalten("v5", .mittwoch)
            #expect(vorhaben(s, "v5")?.datum == mittwoch && vorhaben(s, "v5")?.pruefungstag == freitag,
                    "ein abweichender Prüfungstermin bleibt")
            let meldungen = s.meldungen.count
            s.wochentagUmschalten("v5", .donnerstag)
            #expect(vorhaben(s, "v5")?.datum == donnerstag && vorhaben(s, "v5")?.pruefungstag == freitag
                    && s.meldungen.count == meldungen, "nur das Datum — der Sperrzeitraum gilt dem Prüfungstermin")

            s.wochentagUmschalten("v6", .mittwoch)
            #expect(vorhaben(s, "v6")?.datum == mittwoch && vorhaben(s, "v6")?.pruefungstag == nil,
                    "ohne Datum und ohne Prüfungstermin: nur das Datum")
            s.wochentagUmschalten("v6", .donnerstag)
            #expect(vorhaben(s, "v6")?.datum == donnerstag && vorhaben(s, "v6")?.pruefungstag == nil
                    && s.meldungen.count == meldungen, "der Sperrtag geht ohne Meldung durch")
        }
    }
}
