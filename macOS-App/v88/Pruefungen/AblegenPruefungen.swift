// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

private typealias Tag = Unterrichtsplanung.Tag

// ── Ablegen auf ein Vorhaben am Speicher (v88, AZ2; E904–E907) ────────────
//
// Dateien und Links, die auf eine Kachel fallen, nimmt `ablegen(dateien:links:auf:)` in einem Schritt auf — mit dem
// Kern, den auch das Vorhaben-Blatt nutzt (entdoppeln, relativ zum Basisordner, Grenzen). Der Schritt heißt nach dem,
// was neu dazukam (E916, E921); die Meldung nennt das Vorhaben mit Zeile, Fach und Woche vorn (E907, E914); die
// Warnungen sind die des Blatts, dazu die zu fremden Orten (E918–E920). Den Weg vom Raster her prüft die Klickprobe (AZ1, AZ3).

@Suite("Ablegen auf ein Vorhaben am Speicher")
@MainActor
struct AblegenPruefungen {

    private static let basis = "/Users/lehrkraft/Unterricht"
    private static let datei = URL(fileURLWithPath: basis + "/Bio/Arbeitsblatt.pdf")
    private static let link = "https://example.org/photosynthese"

    private func planung(materialien: [Material] = []) throws -> Planung {
        var planung = Planung.leer(
            titel: "Ablegen", start: try #require(Tag(iso: "2026-08-10")), wochen: 8,
            basis: Self.basis, klassen: Standardkurse.aufbauen(Standardkurse.liste), fachfarben: [:])
        let a = planung.klassen[0].id
        planung.eintraege = [
            Vorhaben(id: "e1", klasseId: a, woche: 2, titel: "Photosynthese", text: "",
                     erledigt: false, materialien: materialien, links: []),
            Vorhaben(id: "e2", klasseId: a, woche: 2, titel: "Test", text: "",
                     erledigt: false, materialien: [], links: []),
        ]
        return planung
    }

    /// Wert für Wert ohne die Stempel, die jedes Schreiben setzt (`geaendert`, `statusGeaendert`) — sonst hinge der
    /// Vergleich am Takt (gemessen: rot nur in der gedehnten Verzögerungsprobe, 28.10.2026).
    private func ohneStempel(_ p: Planung?) -> Planung? {
        guard var p = RuecknahmeVorhabenPruefungen.bisAufDenStempel(p) else { return nil }
        p.geaendert = ""
        return p
    }

    private func eintrag(_ speicher: Planungsspeicher, _ id: String) throws -> Vorhaben {
        try #require(speicher.planung?.eintraege.first { $0.id == id })
    }

    @Test("Datei und Link in einem Schritt „Material ablegen“: nur am Ziel, relativ zum Basisordner; ⌘Z nimmt alles")
    func dateiUndLink() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let vorher = try #require(speicher.planung)
        let schritte = speicher.verlauf.zurueck.count
        let getan = speicher.ablegen(dateien: [Self.datei], links: [Self.link], auf: "e1")
        #expect(getan)
        let e1 = try eintrag(speicher, "e1")
        #expect(e1.materialien.map(\.pfad) == ["Bio/Arbeitsblatt.pdf"], "relativ zum Basisordner wie im Blatt")
        #expect(e1.materialien.map(\.titel) == ["Arbeitsblatt.pdf"])
        #expect(e1.links.map(\.adresse) == [Self.link])
        #expect(try eintrag(speicher, "e2") == vorher.eintraege[1], "das andere Vorhaben bleibt, wie es ist")
        #expect(speicher.verlauf.zurueck.count == schritte + 1, "genau ein Schritt")
        #expect(speicher.widerrufenTitel == "Widerrufen: Material ablegen")
        #expect(speicher.meldungen.last?.text == "„Photosynthese“ (F5b Biologie · KW 35): 1 Material verknüpft, 1 Link hinterlegt.")
        speicher.widerrufen()
        #expect(ohneStempel(speicher.planung) == ohneStempel(vorher), "⌘Z nimmt Datei und Link in einem")
    }

    @Test("Wortlaute nach E907: Mehrzahl, nur Links, alles schon da (ohne Schritt)")
    func wortlaute() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let zweiDateien = [Self.datei, URL(fileURLWithPath: Self.basis + "/Bio/Folie.key")]
        speicher.ablegen(dateien: zweiDateien, links: [Self.link], auf: "e1")
        #expect(speicher.meldungen.last?.text == "„Photosynthese“ (F5b Biologie · KW 35): 2 Materialien verknüpft, 1 Link hinterlegt.")
        speicher.ablegen(dateien: [], links: ["https://example.org/a", "https://example.org/b"], auf: "e2")
        #expect(speicher.meldungen.last?.text == "„Test“ (F5b Biologie · KW 35): 2 Links hinterlegt.")
        let schritte = speicher.verlauf.zurueck.count
        let nochmal = speicher.ablegen(dateien: zweiDateien, links: [Self.link], auf: "e1")
        #expect(!nochmal, "nichts Neues ändert nichts")
        #expect(speicher.verlauf.zurueck.count == schritte, "ohne Änderung kein Schritt")
        #expect(speicher.meldungen.last?.text == "„Photosynthese“ (F5b Biologie · KW 35): nichts Neues — alles war schon verknüpft.")
    }

    @Test("Die Grenze und abgewiesene Adressen warnen wie im Blatt; bei Warnungen keine Zeile „nichts Neues“")
    func grenzeUndAbgewiesen() throws {
        let voll = (0..<Planungsdatei.maxMaterialien).map { Material(titel: "M\($0)", pfad: "Bio/M\($0).pdf") }
        let speicher = Planungsspeicher(vorschau: try planung(materialien: voll))
        let getan = speicher.ablegen(dateien: [Self.datei], links: ["ftp://example.org/x"], auf: "e1")
        #expect(!getan)
        let texte = speicher.meldungen.map(\.text)
        #expect(texte.contains("Höchstens \(Planungsdatei.maxMaterialien) Materialien je Vorhaben — 1 Datei blieb außen vor."))
        #expect(texte.contains("Eine Adresse wurde abgewiesen — nur http und https sind zugelassen."))
        #expect(!texte.contains { $0.contains("nichts Neues") }, "die Warnungen sagen, was war")
        #expect(try eintrag(speicher, "e1").materialien.count == Planungsdatei.maxMaterialien)
    }

    @Test("Auf ein Vorhaben, das es nicht gibt, geschieht nichts")
    func unbekanntesVorhaben() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let vorher = try #require(speicher.planung)
        let schritte = speicher.verlauf.zurueck.count
        #expect(!speicher.ablegen(dateien: [Self.datei], links: [Self.link], auf: "gibt-es-nicht"))
        #expect(ohneStempel(speicher.planung) == ohneStempel(vorher))
        #expect(speicher.verlauf.zurueck.count == schritte)
        #expect(speicher.meldungen.isEmpty, "keine Meldung")
    }

    @Test("Das Blatt meldet wie bisher: „1 Material verknüpft.“, „Link hinterlegt.“, „2 Links hinterlegt.“")
    func blattUnveraendert() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        var entwurf = VorhabenEntwurf(try eintrag(speicher, "e1"))
        #expect(speicher.materialAufnehmen([Self.datei.path], in: &entwurf) == 1)
        #expect(speicher.meldungen.last?.text == "1 Material verknüpft.")
        #expect(speicher.linksAufnehmen([Self.link], in: &entwurf) == 1)
        #expect(speicher.meldungen.last?.text == "Link hinterlegt.")
        #expect(speicher.linksAufnehmen(["https://example.org/a", "https://example.org/b"], in: &entwurf) == 2)
        #expect(speicher.meldungen.last?.text == "2 Links hinterlegt.")
        #expect(entwurf.materialien.map(\.pfad) == ["Bio/Arbeitsblatt.pdf"])
    }

    @Test("Der Schritt heißt nach dem Inhalt (E916): mit Datei „Material ablegen“, ein Link „Link ablegen“, mehrere „Links ablegen“")
    func schrittnamen() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.ablegen(dateien: [], links: [Self.link], auf: "e1")
        #expect(speicher.widerrufenTitel == "Widerrufen: Link ablegen")
        speicher.ablegen(dateien: [], links: ["https://example.org/a", "https://example.org/b"], auf: "e1")
        #expect(speicher.widerrufenTitel == "Widerrufen: Links ablegen")
        speicher.ablegen(dateien: [Self.datei], links: ["https://example.org/c"], auf: "e1")
        #expect(speicher.widerrufenTitel == "Widerrufen: Material ablegen")
    }

    @Test("Eine Datei aus dem Download-Ordner von Mail wird verknüpft, mit Warnung (E918) — in Raster und Blatt")
    func ausMail() throws {
        let mail = URL(fileURLWithPath: "/Users/lehrkraft/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/"
                       + "2F2E/logo.png")
        let warnung = "„logo.png“ liegt im Download-Ordner von Mail und kann dort verschwinden — sicherer zuerst im Finder "
            + "sichern und neu verknüpfen."
        let speicher = Planungsspeicher(vorschau: try planung())
        #expect(speicher.ablegen(dateien: [mail], links: [], auf: "e1"))
        #expect(try eintrag(speicher, "e1").materialien.map(\.pfad) == [mail.path], "außerhalb des Basisordners: absolut")
        #expect(speicher.meldungen.last?.text == "„Photosynthese“ (F5b Biologie · KW 35): 1 Material verknüpft — "
                + "„logo.png“ liegt im Download-Ordner von Mail und kann dort verschwinden; sicherer zuerst im Finder "
                + "sichern und neu verknüpfen.",
                "auf der Kachel Bestätigung und Warnung in einer Zeile (E923)")
        var entwurf = VorhabenEntwurf(try eintrag(speicher, "e2"))
        #expect(speicher.materialAufnehmen([mail.path], in: &entwurf) == 1)
        #expect(speicher.meldungen.last?.text == warnung, "das Blatt warnt ebenso")
    }

    @Test("Der fremde Ablageort — mit und ohne Sandbox gleich: Mail, andere App, Group Container, temporär; eigener Container und gewöhnlicher Ordner nicht")
    func fremderAblageort() {
        let eigen = "org.3ducation.Unterrichtsplanung"
        #expect(Planungsspeicher.fremderAblageort("/Users/x/Library/Containers/com.apple.mail/Data/a.png",
                                                  eigeneKennung: eigen) == "im Download-Ordner von Mail")
        #expect(Planungsspeicher.fremderAblageort("/Users/x/Library/Containers/com.apple.MobileSMS/Data/a.png",
                                                  eigeneKennung: eigen) == "im Ordner einer anderen App")
        #expect(Planungsspeicher.fremderAblageort("/Users/x/Library/Group Containers/UBF8T346G9.Office/a.docx",
                                                  eigeneKennung: eigen) == "im Ordner einer anderen App")
        #expect(Planungsspeicher.fremderAblageort("/private/var/folders/ab/cd/T/a.pdf", eigeneKennung: eigen)
                == "in einem temporären Ordner")
        #expect(Planungsspeicher.fremderAblageort("/Users/x/Library/Containers/\(eigen)/Data/tmp/a.pdf",
                                                  eigeneKennung: eigen) == nil, "der eigene Container")
        #expect(Planungsspeicher.fremderAblageort("/Users/x/Unterricht/a.pdf", eigeneKennung: eigen) == nil)
    }

    @Test("Verschiedene fremde Orte: ein Sammelwortlaut (E919, E922); ein Ort: der Ort — auf der Kachel in einer Zeile (E923)")
    func sammelwortlaut() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let mail = URL(fileURLWithPath: "/Users/lehrkraft/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/A/a.png")
        let gruppe = URL(fileURLWithPath: "/Users/lehrkraft/Library/Group Containers/G.Office/b.docx")
        speicher.ablegen(dateien: [mail, gruppe], links: [], auf: "e1")
        #expect(speicher.meldungen.last?.text == "„Photosynthese“ (F5b Biologie · KW 35): 2 Materialien verknüpft — "
                + "2 Dateien liegen in Ordnern anderer Apps und können dort verschwinden; sicherer zuerst im Finder "
                + "sichern und neu verknüpfen.")
        let mails = "/Users/lehrkraft/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/"
        let mail2 = URL(fileURLWithPath: mails + "B/c.png")
        let mail3 = URL(fileURLWithPath: mails + "C/d.png")
        speicher.ablegen(dateien: [mail2, mail3], links: [], auf: "e2")
        #expect(speicher.meldungen.last?.text == "„Test“ (F5b Biologie · KW 35): 2 Materialien verknüpft — "
                + "2 Dateien liegen im Download-Ordner von Mail und können dort verschwinden; sicherer zuerst im Finder "
                + "sichern und neu verknüpfen.")
        // E922: mit einem temporären Ordner „… oder des Systems“, mehrere aus anderen Apps in der Mehrzahl.
        #expect(Planungsspeicher.fremderOrtSatz([("a.png", "im Download-Ordner von Mail"),
                                                 ("b.pdf", "in einem temporären Ordner")])
                == "2 Dateien liegen in Ordnern anderer Apps oder des Systems und können dort verschwinden")
        #expect(Planungsspeicher.fremderOrtSatz([("a.png", "im Ordner einer anderen App"),
                                                 ("b.pdf", "im Ordner einer anderen App")])
                == "2 Dateien liegen in Ordnern anderer Apps und können dort verschwinden")
        // Nur temporäre Ordner: deren Mehrzahl (Z-AZ3N-03).
        #expect(Planungsspeicher.fremderOrtSatz([("a.pdf", "in einem temporären Ordner"),
                                                 ("b.pdf", "in einem temporären Ordner")])
                == "2 Dateien liegen in temporären Ordnern und können dort verschwinden")
    }

    @Test("Der Schritt heißt nach dem Neuen (E921): eine schon verknüpfte Datei und ein neuer Link sind „Link ablegen“")
    func schrittNachDemNeuen() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        speicher.ablegen(dateien: [Self.datei], links: [], auf: "e1")
        speicher.ablegen(dateien: [Self.datei], links: [Self.link], auf: "e1")
        #expect(speicher.widerrufenTitel == "Widerrufen: Link ablegen")
        #expect(speicher.meldungen.last?.text == "„Photosynthese“ (F5b Biologie · KW 35): 1 Link hinterlegt.")
    }

    @Test("Eine Zeile ohne Fach nennt nur ihren Namen (E914)")
    func ohneFach() throws {
        var ohne = try planung()
        ohne.klassen[0].fach = ""
        let speicher = Planungsspeicher(vorschau: ohne)
        speicher.ablegen(dateien: [], links: [Self.link], auf: "e1")
        #expect(speicher.meldungen.last?.text == "„Photosynthese“ (F5b · KW 35): 1 Link hinterlegt.")
    }

    // ── Nach der Gesamtreview (AZ6) ──────────────────────────────────────

    @Test("Der Titel geht zugeschnitten in die Planung wie beim Sichern im Blatt — ohne Steuerzeichen und Rand (G1-01, E208)")
    func titelZugeschnitten() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let name = " \u{202E}Bericht.pdf "
        speicher.ablegen(dateien: [URL(fileURLWithPath: Self.basis + "/Bio/" + name)], links: [], auf: "e1")
        let titel = try eintrag(speicher, "e1").materialien.map(\.titel)
        #expect(titel == ["Bericht.pdf"])
        #expect(titel == [VorhabenEntwurf.bezeichnung(name, ersatz: name).text], "dieselbe Schranke wie das Blatt")
    }

    @Test("Der fremde Ablageort auch bei einem Benutzerordner außerhalb von /Users (G1-02)")
    func fremderAblageortVerlegt() {
        let eigen = "org.3ducation.Unterrichtsplanung"
        #expect(Planungsspeicher.fremderAblageort("/Network/Users/x/Library/Containers/com.apple.mail/Data/a.png",
                                                  eigeneKennung: eigen) == "im Download-Ordner von Mail")
        #expect(Planungsspeicher.fremderAblageort("/Volumes/Daten/Benutzer/x/Library/Group Containers/G.Office/b.docx",
                                                  eigeneKennung: eigen) == "im Ordner einer anderen App")
        #expect(Planungsspeicher.fremderAblageort("/Network/Users/x/Library/Containers/\(eigen)/Data/tmp/a.pdf",
                                                  eigeneKennung: eigen) == nil, "der eigene Container")
        #expect(Planungsspeicher.fremderAblageort("/Network/Users/x/Unterricht/a.pdf", eigeneKennung: eigen) == nil)
    }

    @Test("Ein Ordner kommt nach „Material“ wie eine Datei (G1-03)")
    func ordner() throws {
        let speicher = Planungsspeicher(vorschau: try planung())
        let ordner = URL(fileURLWithPath: Self.basis + "/Bio/Versuch", isDirectory: true)
        speicher.ablegen(dateien: [ordner], links: [], auf: "e1")
        let e1 = try eintrag(speicher, "e1")
        #expect(e1.materialien.map(\.pfad) == ["Bio/Versuch"])
        #expect(e1.materialien.map(\.titel) == ["Versuch"])
        #expect(speicher.widerrufenTitel == "Widerrufen: Material ablegen")
    }

    @Test("Der Ring geht nicht mit, wenn eine Kachel beim Rollen ein anderes Vorhaben zeigt (G1-04)")
    func ringBeimWiederverwenden() throws {
        let planung = try planung()
        let kacheln = Rasterdaten(planung, stand: 1, breite: 280).kacheln(zeile: 0, woche: 2)
        try #require(kacheln.count == 2)
        let e1 = try #require(kacheln.first { $0.vorhaben.id == "e1" })
        let e2 = try #require(kacheln.first { $0.vorhaben.id == "e2" })
        // Dasselbe Vorhaben in einem anderen Stand (ein Material mehr) — sonst endete `setzen` schon am gleichen Stand
        // und die Unterscheidung nach dem Vorhaben bliebe ungeprüft (Z-AZ6N-04).
        var mehr = planung
        mehr.eintraege[0].materialien = [Material(titel: "Arbeitsblatt.pdf", pfad: "Bio/Arbeitsblatt.pdf")]
        let e1mehr = try #require(Rasterdaten(mehr, stand: 2, breite: 280).kacheln(zeile: 0, woche: 2)
            .first { $0.vorhaben.id == "e1" })
        try #require(e1mehr != e1)
        let ton = Farbwelt.ton(planung.klassen[0].farbe)
        let ansicht = Kachelansicht(frame: .zero)
        ansicht.setzen(e1, ton: ton, angewaehlt: false, griffe: .init())
        ansicht.ablagezielSetzen(true)
        ansicht.setzen(e1mehr, ton: ton, angewaehlt: false, griffe: .init())
        #expect(ansicht.ablageziel, "dasselbe Vorhaben, anderer Stand: der Ring bleibt")
        ansicht.setzen(e2, ton: ton, angewaehlt: false, griffe: .init())
        #expect(!ansicht.ablageziel, "ein anderes Vorhaben: kein Ring, bis das Ziehen ihn neu setzt")
    }

    @Test("Ein Steuerzeichen im Rechnernamen kommt nie in einen Linktitel: Die Prüfung der Adresse weist es ab (Z-AZ6N-02)")
    func linkMitSteuerzeichen() throws {
        // Kodiert und unkodiert — `Weblinks.pruefen` lässt keine der beiden Formen durch; darum braucht `linkKern` keinen
        // Zuschnitt wie `materialKern` (G1-01).
        for adresse in ["https://%E2%80%AEexample.org/", "https://\u{202E}example.org/"] {
            #expect(Weblinks.pruefen(adresse) == nil, Comment(rawValue: adresse))
            let speicher = Planungsspeicher(vorschau: try planung())
            speicher.ablegen(dateien: [], links: [adresse], auf: "e1")
            #expect(try eintrag(speicher, "e1").links.isEmpty)
            #expect(speicher.meldungen.last?.text == "Eine Adresse wurde abgewiesen — nur http und https sind zugelassen.")
        }
    }
}
