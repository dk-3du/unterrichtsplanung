// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

// ── Rückmeldungen und Anliegen im Blatt „Lernende“ (E272) ────────────────
// Die Rücklaufliste einer Lerngruppe — eine Mitteilung je Ansicht, gewählt über das
// Auswahlfeld, je betroffener Person ein Stand mit Tag und Notiz — und ihre Maßnahmen
// mit Frist je Person. Beide ändern nur den Entwurf des Blatts, über dessen einen Weg
// (`handgriff`).

/// Haken und Sperre des Menüs der Sammelleiste bei den Mitteilungen (E929, Z-AZ4-06).
struct Sammelmenuelage: Equatable, Sendable {
    let haken: Rueckmeldestand?
    let gesperrt: Bool
}

/// Was die Ansichten der Anliegen vom Blatt brauchen: den Stand und die Wege,
/// ihn zu ändern.
struct Anliegenbezug {
    let entwurf: Lernendenbestand
    let verzeichnis: Lernendenverzeichnis
    let archivierteZeigen: Bool
    /// Ein Handgriff am Entwurf — Name des Schritts, Kennung fürs Zusammenwachsen.
    let handgriff: @MainActor (String, String?, (Lernendenbestand) -> Lernendenbestand) -> Void
    /// Anlegen (Art, Titel, Betroffene, Tag, Frist) — die Kennung des Neuen.
    let anlegen: @MainActor (Anliegenart, String, [String], String, String) -> String?
    /// Löschen mit Rückfrage und Zahl.
    let loeschen: @MainActor (String) -> Void
    /// Ein Hinweis am Blatt — etwa nach dem Wiedergelten einer Vereinbarung (Tabelle 9).
    var melden: @MainActor (String) -> Void = { _ in }
    /// Der Entwurf, wie er jetzt ist — nach dem Ausstehenden aus den Feldern; `entwurf` ist der Stand beim Zeichnen
    /// (Z-AZ4-04).
    var aktuell: @MainActor () -> Lernendenbestand? = { nil }
    /// Eine Warnung am Blatt — etwa an der Grenze der Datei (E935).
    var warnen: @MainActor (String) -> Void = { _ in }

    var jetzt: String { Zeitrechnung.jetztAlsZeitstempel() }

    func personen(_ gruppe: Lerngruppe) -> [Lernender] {
        verzeichnis.mitglieder(gruppe.id, archivierte: archivierteZeigen)
    }

    static func zeichen(_ stand: Rueckmeldestand) -> String {
        switch stand {
        case .offen: Zeichen.standOffen
        case .erledigt: Zeichen.standErledigt
        case .abgelehnt: Zeichen.standAbgelehnt
        }
    }

    static func farbe(_ stand: Rueckmeldestand) -> Color {
        switch stand {
        case .offen: .secondary
        case .erledigt: .green
        case .abgelehnt: .red
        }
    }

    /// „03.10.2026“ aus einem ISO-Tag — oder ein Strich.
    static func tagtext(_ iso: String) -> String { Tag(iso: iso)?.deutsch ?? "—" }

    /// Die Hilfe an einer verstrichenen Frist — bei Maßnahmen und Mitteilungen.
    static let fristVerstrichen = "Die Frist ist verstrichen"

    /// Ob eine Frist verstrichen ist und die Person noch offen steht — dann steht sie orange, bei Maßnahmen wie bei
    /// Mitteilungen (v91, BC3). Am Tag der Frist selbst ist sie nicht verstrichen; ohne Frist nie.
    static func verstrichen(_ frist: String, _ stand: Rueckmeldestand, heute: Tag) -> Bool {
        stand == .offen && Tag(iso: frist).map { $0 < heute } == true
    }

    /// Die Person in „für“ einer neuen Maßnahme oder Vereinbarung, wenn sie unter `mitglieder` steht — sonst keine. Nach
    /// dem Wechsel der Lerngruppe zeigte „für“ sonst auf eine Person der vorigen (W1-01).
    static func fuerGueltig(_ fuer: String?, _ mitglieder: [Lernender]) -> String? {
        mitglieder.contains { $0.id == fuer } ? fuer : nil
    }

    /// Ein offenes Anliegen in der Zeile „Offen: …“ unter „Alle Lernenden“: „Elternbrief (Mitteilung vom 07.09.2026,
    /// Rückmeldung bis 14.09.2026)“, „Nacharbeit (Maßnahme bis 14.09.2026)“, „Elterngespräch (Termin am 20.10.2026, 07:45
    /// Uhr)“. Die Frist einer Mitteilung nur, wo gesetzt (v91, BC3, V5).
    static func offenerEintrag(_ a: Anliegen) -> String {
        switch a.art {
        case .mitteilung:
            let teile = [Tag(iso: a.datum).map { "Mitteilung vom \($0.deutsch)" } ?? "Mitteilung"]
                + (Tag(iso: a.frist).map { ["\(Mitteilungstext.rueckmeldungBis) \($0.deutsch)"] } ?? [])
            return a.titel + " (" + teile.joined(separator: ", ") + ")"
        case .massnahme:
            return a.titel + (Tag(iso: a.frist).map { " (Maßnahme bis \($0.deutsch))" } ?? " (Maßnahme)")
        case .termin:
            return a.titel + " (Termin am " + tagtext(a.datum) + (a.uhrzeit.isEmpty ? "" : ", \(a.uhrzeit) Uhr") + ")"
        // Eine Vereinbarung ist kein offenes Anliegen (E804) und steht dort nie; der Zweig nur der Vollständigkeit halber.
        case .vereinbarung:
            return a.titel
        }
    }
}

// ── Hilfetexte an Knöpfen, auch gesperrt (v86, AX1: E761, G2-06, Z-AW5bN-06) ─

/// Die Hilfetexte nach E761 — an einer Stelle, damit die Suite sie prüft: am Bogen „Rückmeldungsliste“, gesperrt mit
/// eigenen Texten; „Zeilen wählen …“ behält seinen Wortlaut auch gesperrt; „Anlegen“ (neue Mitteilung) nennt ohne
/// Adressaten den Grund, bei einer Lerngruppe ohne aktives Mitglied diesen (BC4, W1-10, N7-01).
enum Knopfhilfe {
    static let alleWaehlen = "Alle Mitteilungen der Lerngruppe wählen"
    static let auswahlAufheben = "Keine Mitteilung wählen"
    /// v91 (BC4, V4): an alle Mitglieder oder an die unter „an …“ gewählten.
    static let mitteilungAnlegen = "Eine Mitteilung mit dem heutigen Tag anlegen — an alle Mitglieder dieser Lerngruppe oder "
        + "an die gewählten (⏎)"
    static let zeilenWaehlen = "Die Zeilen dieser Planung wählen, mit denen die Lerngruppe verknüpft ist — eine Zeile kann "
        + "mehrere tragen"

    /// „Drucken …“ im Bogen — gesperrt ohne gewählte Mitteilung (E408).
    static func drucken(gesperrt: Bool) -> String {
        gesperrt ? "Erst eine Mitteilung wählen"
                 : "Die Liste der gewählten Mitteilungen auf Papier — die PDF-Wege des Druckdialogs weist die App ab"
    }

    /// „Als PDF sichern (verschlüsselt) …“ im Bogen — gesperrt ohne Mitteilung oder ohne zweimal gleiches Kennwort (E406).
    static func sichern(gesperrt: Bool) -> String {
        gesperrt ? "Erst eine Mitteilung wählen und das Kennwort zweimal gleich eingeben"
                 : "Die Liste als PDF, verschlüsselt mit dem Kennwort oben"
    }
}

extension View {
    /// Die Hilfe am Knopf — gesperrt zeigt SwiftUI unter macOS keinen Hilfetext, dann trägt ihn eine durchsichtige Fläche
    /// (H1, Sichtprüfung AW5; Z-AW5bN-06). Für Bedienhilfen ist die Fläche nicht da: Den Hinweis trägt der Knopf selbst
    /// (Z-AW5bN-04). Hinter `.disabled(_:)` setzen — sonst wäre die Fläche mit gesperrt.
    func hilfe(_ text: String, gesperrt: Bool) -> some View {
        help(text)
            .overlay {
                if gesperrt { Color.clear.contentShape(Rectangle()).help(text).accessibilityHidden(true) }
            }
    }
}

/// Ein Stand als Zeichen mit Wort — farbig, damit die Liste auf einen Blick lesbar ist.
private struct Standmarke: View {
    let stand: Rueckmeldestand
    let art: Anliegenart

    var body: some View {
        Label(stand.beschriftung(fuer: art), systemImage: Anliegenbezug.zeichen(stand))
            .foregroundStyle(Anliegenbezug.farbe(stand))
    }
}

/// Der Stand in der Tabelle — ein Klick öffnet die drei Stände, die Wahl gilt
/// sofort (E280). Die Zelle bleibt die farbige Marke; das Menü ist eines von
/// AppKit: SwiftUIs `Menu` zeichnete die Beschriftung im Fenster einfarbig und
/// füllte sein Menü erst beim Öffnen (am Paket gemessen).
private struct Standmenue: View {
    let stand: Rueckmeldestand
    let art: Anliegenart
    let waehlen: @MainActor (Rueckmeldestand) -> Void

    var body: some View {
        Button { Standwahl.zeigen(stand, art, waehlen) } label: {
            Standmarke(stand: stand, art: art)
        }
        .buttonStyle(.plain)
        .help("Stand ändern")
    }
}

/// Der Stand einer Vereinbarung unter „Ohne Lerngruppe“ (E746, E813, Z-AX3-10) — wie `Standmenue` ein Menü von AppKit, mit
/// den zwei Ständen und dem Häkchen am geltenden; die Zelle zeigt den Stand wie der Teil „Vereinbarungen“.
private struct Gueltigkeitsmenue: View {
    let stand: Gueltigkeit
    /// „Stand ändern“ — an einer abgelaufenen die Hilfe nach E808 (`Vereinbarungstext.standmenueHilfe`, Z-R2A1-03).
    let hilfe: String
    let waehlen: @MainActor (Gueltigkeit) -> Void

    var body: some View {
        Button { Standwahl.zeigen(stand, waehlen) } label: {
            Text(stand.beschriftung)
                .foregroundStyle(stand == .gueltig ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(hilfe)
    }
}

/// Das Menü der Stände an der Stelle des Klicks — die drei eines Rücklaufs oder die zwei einer Vereinbarung.
@MainActor
enum Standwahl {
    static func zeigen(_ stand: Rueckmeldestand, _ art: Anliegenart, _ waehlen: @escaping @MainActor (Rueckmeldestand) -> Void) {
        zeigen(Rueckmeldestand.allCases.map { s in
            let eintrag = NSMenuItem(title: s.beschriftung(fuer: art), action: #selector(Ziel.gewaehlt(_:)), keyEquivalent: "")
            eintrag.representedObject = s.rawValue
            eintrag.state = s == stand ? .on : .off
            eintrag.image = NSImage(systemSymbolName: Anliegenbezug.zeichen(s), accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(hierarchicalColor: farbe(s)))
            return eintrag
        }) { roh in
            if let s = Rueckmeldestand(rawValue: roh) { waehlen(s) }
        }
    }

    /// Die Einträge des Menüs einer Vereinbarung: beide Stände, das Häkchen am geltenden (E813, Z-AX3-10). Gewählt wird
    /// auch der geltende — „ungültig“ an einer abgelaufenen trägt die Person von Hand ein (E813).
    static func eintraege(_ stand: Gueltigkeit) -> [(titel: String, haken: Bool)] {
        Gueltigkeit.allCases.map { ($0.beschriftung, $0 == stand) }
    }

    static func zeigen(_ stand: Gueltigkeit, _ waehlen: @escaping @MainActor (Gueltigkeit) -> Void) {
        zeigen(zip(Gueltigkeit.allCases, eintraege(stand)).map { g, e in
            let eintrag = NSMenuItem(title: e.titel, action: #selector(Ziel.gewaehlt(_:)), keyEquivalent: "")
            eintrag.representedObject = g.rawValue
            eintrag.state = e.haken ? .on : .off
            return eintrag
        }) { roh in
            if let g = Gueltigkeit(rawValue: roh) { waehlen(g) }
        }
    }

    private static func zeigen(_ eintraege: [NSMenuItem], _ gewaehlt: @escaping @MainActor (String) -> Void) {
        guard let ereignis = NSApp.currentEvent, let fenster = ereignis.window, let inhalt = fenster.contentView else { return }
        let ziel = Ziel(gewaehlt)
        let menue = NSMenu()
        menue.autoenablesItems = false
        for eintrag in eintraege {
            eintrag.target = ziel
            menue.addItem(eintrag)
        }
        let punkt = inhalt.convert(ereignis.locationInWindow, from: nil)
        withExtendedLifetime(ziel) {
            _ = menue.popUp(positioning: menue.items.first { $0.state == .on }, at: punkt, in: inhalt)
        }
    }

    private static func farbe(_ stand: Rueckmeldestand) -> NSColor {
        switch stand {
        case .offen: .secondaryLabelColor
        case .erledigt: .systemGreen
        case .abgelehnt: .systemRed
        }
    }

    @MainActor
    private final class Ziel: NSObject {
        /// Bekommt den Rohwert des gewählten Stands.
        let waehlen: @MainActor (String) -> Void
        init(_ waehlen: @escaping @MainActor (String) -> Void) { self.waehlen = waehlen }

        @objc func gewaehlt(_ eintrag: NSMenuItem) {
            guard let roh = eintrag.representedObject as? String else { return }
            waehlen(roh)
        }
    }
}

// ── Die Rücklaufliste (v91, BC2: eine Mitteilung je Ansicht) ────────────

/// Die Wortlaute der Mitteilungen (v91, BC2–BC4) — an einer Stelle, damit die Suite sie prüft. Wie im Prototyp (E994)
/// (V8); die Spalten wie bei den Maßnahmen (V1–V3).
enum Mitteilungstext {
    static let spaltePerson = "Person"
    static let spalteMitteilung = "Mitteilung"
    static let spalteFrist = "Frist"
    static let spalteStand = "Stand"
    /// Das Auswahlfeld über der Tabelle (V1) wählt, was die Tabelle zeigt und „Löschen …“ betrifft.
    static let auswahlBezeichnung = "Mitteilung"
    static let auswahlHilfe = "Die Mitteilung, die die Tabelle zeigt und „Löschen …“ betrifft"
    static let loeschenHilfe = "Die gewählte Mitteilung samt ihren Rückläufen löschen — mit Rückfrage"
    static let leer = "Noch keine Mitteilung an diese Lerngruppe. Eine neue geht an alle Mitglieder oder an einzelne; je "
        + "Person lässt sich dann der Rücklauf eintragen — erledigt oder abgelehnt, mit Tag und Notiz."
    /// Die gewählte Mitteilung betrifft kein Mitglied (mehr) — sie bleibt stehen, bis sie jemand löscht (V10).
    static let niemand = "Diese Mitteilung betrifft kein angezeigtes Mitglied der Lerngruppe."
    /// Nur, wenn „Auch an …“ jemanden anbietet (Z-BC2-05).
    static let niemandAuchAn = "„Auch an …“ nimmt Mitglieder auf."
    /// Unter der Tabelle, wie „Auch für …“ der Maßnahmen: von Hand aufnehmen — auch, wer später in die Lerngruppe kam.
    static let auchAn = "Auch an …"
    static let auchAnHilfe = "Die Mitteilung geht auch an weitere Mitglieder dieser Lerngruppe"
    /// Oben im Menü „Auch an …“, ab zwei Aufzunehmenden — wie „Auch für …“ der Vereinbarungen (E853).
    static let auchAnAlle = "Alle Mitglieder der Lerngruppe"
    static let ausNehmen = "Aus der Mitteilung nehmen"
    static let ausNehmenHilfe = "Die Mitteilung betrifft diese Person nicht — ihr Rücklauf geht mit"
    static let titelBezeichnung = "Titel der Mitteilung"
    static let tagBezeichnung = "Tag der Mitteilung"
    // Die Rückmeldefrist (v91, BC3: V5, V6) — wahlweise wie „gültig bis einschließlich“ der Vereinbarungen.
    /// Das Kästchen der Anlegezeile und das der Leiste — ein Wortlaut; ohne Haken keine Frist (alte Mitteilungen: „—“).
    static let rueckmeldungBis = "Rückmeldung bis"
    // VoiceOver am Datum: in der Anlegezeile und in der Leiste.
    static let fristNeuBezeichnung = "Rückmeldung bis — neue Mitteilung"
    static let fristBezeichnung = "Rückmeldung bis"
    /// Die Frist, wenn das Kästchen gesetzt wird — eine Woche, wie die Vorgabe einer Maßnahme.
    static let fristTage = 7

    // Die Adressaten (v91, BC4: V4) — vorgegeben alle Mitglieder, wahlweise einzelne.
    /// Das Menü „an …“ in der Anlegezeile, wenn alle gemeint sind.
    static let anAlle = "an alle Mitglieder"
    /// Der Eintrag im Menü „an …“ — derselbe Wortlaut wie oben in „Auch an …“.
    static let alleMitglieder = auchAnAlle
    static let einzelne = "Einzelne …"
    static let anHilfe = "An wen die neue Mitteilung geht — vorgegeben alle Mitglieder der Lerngruppe. Wer später "
        + "hinzukommt, ist nicht betroffen; „Auch an …“ nimmt von Hand auf."
    /// „Anlegen“ gesperrt: „Einzelne …“ ohne ein aktives gewähltes Mitglied (etwa nach dem Archivieren).
    static let ohneAdressaten = "Erst unter „an …“ Mitglieder wählen"
    /// Der Titel des Menüs, wenn von der Auswahl kein aktives Mitglied mehr übrig ist (Z-BC4-03).
    static let anNiemanden = "an niemanden"
    /// „Anlegen“ gesperrt, weil die Lerngruppe kein aktives Mitglied hat (W1-10).
    static let ohneMitglieder = "Die Lerngruppe hat kein aktives Mitglied"
    /// Die Hilfe an „Anlegen“: ohne Adressaten der Grund — bei einer Lerngruppe ohne aktives Mitglied dieser —, sonst die
    /// gewohnte. „an alle“ ist auch in einer leeren Lerngruppe anlegbar, dann sperrt nichts (N7-01).
    static func anlegenHilfe(ohneAdressaten: Bool, keinAktives: Bool) -> String {
        guard ohneAdressaten else { return Knopfhilfe.mitteilungAnlegen }
        return keinAktives ? Self.ohneMitglieder : Self.ohneAdressaten
    }
    // Der Bogen „Einzelne …“
    static let bogenTitel = "An einzelne Mitglieder"
    static let bogenAbschnitt = "Mitglieder"
    static let bogenFuss = "Die neue Mitteilung betrifft nur die Gewählten. Wer später in die Lerngruppe kommt, ist nicht "
        + "betroffen — „Auch an …“ nimmt von Hand auf."
    static let bogenAlle = "Alle wählen"
    static let bogenKeine = "Auswahl aufheben"
    // Die Hilfen am Bogen, gesperrt wie H1 (E761; W2-03).
    static let bogenAlleHilfe = "Alle aktiven Mitglieder wählen"
    static let bogenKeineHilfe = "Kein Mitglied wählen"
    static let bogenUebernehmenHilfe = "Die Gewählten als Adressaten der neuen Mitteilung übernehmen — angelegt wird mit "
        + "„Anlegen“ (⏎)"
    static let bogenUebernehmenGesperrt = "Erst ein Mitglied wählen"

    /// „3 von 42 gewählt“ im Bogen „Einzelne …“.
    static func gewaehlt(_ zahl: Int, von: Int) -> String { "\(zahl) von \(von) gewählt" }

    /// Die Spalte „Tag“ im Archiv (V5): „01.09.2026, Rückmeldung bis 08.09.2026“ — ohne Frist nur der Tag, ohne beides „—“.
    static func archivtag(_ a: Anliegen) -> String {
        let teile = (Tag(iso: a.datum).map { [$0.deutsch] } ?? [])
            + (Tag(iso: a.frist).map { ["\(rueckmeldungBis) \($0.deutsch)"] } ?? [])
        return teile.isEmpty ? "—" : teile.joined(separator: ", ")
    }

    /// „3 von 12 zurück“ — über alle Betroffenen, auch wer die Lerngruppe inzwischen verließ (wie bisher).
    static func zurueck(_ m: Anliegen, _ verzeichnis: Lernendenverzeichnis) -> String {
        "\(m.betroffene.filter { verzeichnis.stand(m.id, $0) != .offen }.count) von \(m.betroffene.count) zurück"
    }
}

/// An wen eine neue Mitteilung geht (v91, BC4, V4): alle aktiven Mitglieder (Standard) oder eine Auswahl — eine Person ist
/// eine Auswahl von einer. Festgehalten wird beim Anlegen; wer danach in die Lerngruppe kommt, ist nicht betroffen und wird
/// nur von Hand aufgenommen („Auch an …“), nie von selbst.
enum Mitteilungsadressaten: Equatable, Sendable {
    case alle
    case einzelne(Set<String>)

    /// Die Gewählten — bei „alle“ keine.
    var gewaehlt: Set<String> {
        if case .einzelne(let auswahl) = self { return auswahl }
        return []
    }

    /// Die Betroffenen beim Anlegen, in der Folge der Liste: die aktiven Mitglieder, bei einer Auswahl die gewählten unter
    /// ihnen — Archivierte und Unbekannte nie.
    func betroffene(_ mitglieder: [Lernender]) -> [String] {
        let aktive = mitglieder.filter { $0.archiviert.isEmpty }.map(\.id)
        switch self {
        case .alle: return aktive
        case .einzelne(let auswahl): return aktive.filter(auswahl.contains)
        }
    }

    /// Ob „Anlegen“ geht: an alle immer — wie bisher auch in einer Lerngruppe ohne Mitglieder —, an einzelne nur mit
    /// wenigstens einem aktiven Gewählten.
    func anlegbar(_ mitglieder: [Lernender]) -> Bool { self == .alle || !betroffene(mitglieder).isEmpty }

    /// Der Titel des Menüs „an …“: „an alle Mitglieder“, „an Abel, Anna“, „an 3 Personen“.
    func titel(_ mitglieder: [Lernender]) -> String {
        guard self != .alle else { return Mitteilungstext.anAlle }
        let ids = betroffene(mitglieder)
        if ids.isEmpty { return Mitteilungstext.anNiemanden }
        if ids.count == 1, let p = mitglieder.first(where: { $0.id == ids[0] }) { return "an \(p.anzeigename)" }
        return "an \(ids.count) Personen"
    }
}

/// Eine Zeile der Tabelle einer Mitteilung: die Person und der Rang ihres Stands — nach ihm ordnet der Kopf „Stand“ wie bei
/// den Maßnahmen (E1008). `id` ist die der Person: Die Auswahl des Blatts bleibt dieselbe.
struct Ruecklaufzeile: Identifiable {
    let person: Lernender
    let stand: Int
    var id: String { person.id }
}

struct Ruecklaufliste: View {
    let gruppe: Lerngruppe
    let bezug: Anliegenbezug
    @Binding var person: String?
    /// Die Auswahl der Tabelle — die des Blatts, wie in der Mitgliederliste: ab 2 mehrere, sonst die eine Person (v88, AZ4).
    /// Gewählte, die die gezeigte Mitteilung nicht betrifft, stehen nicht in der Tabelle und bleiben gewählt: Wechselt das
    /// Auswahlfeld zu einer, die sie betrifft, sind sie wieder markiert.
    let auswahl: Binding<Set<String>>
    /// Die Mitteilung, die beim Erscheinen gewählt ist — ohne sie die jüngste (V7).
    var startAnliegen: String?
    /// Die Ordnung nach „Person“ oder „Stand“ (E1008) — am Blatt gehalten (E362, E364).
    @Binding var ordnung: [KeyPathComparator<Ruecklaufzeile>]
    /// „Rückmeldungsliste …“: der Bogen für diese Gruppe (E401) — am Blatt, das ihn trägt.
    let listeOeffnen: () -> Void
    /// An wen die nächste Mitteilung geht (BC4) — am Blatt gehalten, weil der Bogen „Einzelne …“ dort hängt.
    @Binding var adressaten: Mitteilungsadressaten
    /// „Einzelne …“: der Bogen am Blatt (ein Fenster trägt einen Bogen).
    var einzelneWaehlen: @MainActor () -> Void = {}

    /// Die Mitteilung, die das Auswahlfeld gewählt hat: Die Tabelle zeigt sie, „Löschen …“ betrifft sie (V1).
    @State private var aktiv: String?
    @State private var neuerTitel = ""
    /// „Rückmeldung bis“ in der Anlegezeile — wahlweise (V6); Kästchen und Datum bleiben nach dem Anlegen stehen, wie
    /// „gültig bis“ der Vereinbarungen.
    @State private var mitFrist = false
    @State private var neueFrist = Tag.heute.plus(tage: Mitteilungstext.fristTage)
    @State private var titel = ""
    @State private var notiz = ""
    /// Wozu die Felder geladen sind — dorthin wird geschrieben, auch wenn
    /// Mitteilung und Person zugleich wechseln.
    @State private var titelFuer: String?
    @State private var notizFuer: Paar?
    @FocusState private var fokus: Feld?

    private enum Feld: Hashable { case neu, titel, notiz }

    private struct Paar: Equatable {
        let anliegen: String
        let person: String
    }

    private var mitteilungen: [Anliegen] { bezug.verzeichnis.mitteilungen(der: gruppe.id) }
    private var aktive: Anliegen? { mitteilungen.first { $0.id == aktiv } }
    /// Die aktiven Mitglieder, in der Folge der Liste — an sie geht eine neue Mitteilung.
    private var aktiveMitglieder: [Lernender] { bezug.verzeichnis.mitglieder(gruppe.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            anlegezeile
            auswahlzeile
            if let m = aktive {
                // Die Personen einmal je Durchgang — Zeilen, Hinweis und Leiste nehmen dieselben (W1-06).
                let personen = bezug.personen(gruppe)
                let zeilen = Tabellenordnung.geordnet(Self.reihen(m, Self.zeilen(m, personen), bezug.verzeichnis), nach: ordnung)
                if zeilen.isEmpty {
                    let weitere = !Self.aufzunehmen(m, personen).isEmpty
                    Text(weitere ? Mitteilungstext.niemand + " " + Mitteilungstext.niemandAuchAn : Mitteilungstext.niemand)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    mitteilungsleiste(m, personen)
                    Spacer(minLength: 0)
                } else {
                    tabelle(m, zeilen)
                    mitteilungsleiste(m, personen)
                    if let gewaehlt = Lernendenblatt.sammelauswahl(sichtbar: zeilen.map(\.id), mehrere: auswahl.wrappedValue) {
                        sammelleiste(m, gewaehlt)
                    } else if let id = Self.leistenperson(person, gewaehlt: auswahl.wrappedValue, sichtbar: zeilen.map(\.id)),
                              let z = zeilen.first(where: { $0.id == id }) {
                        ruecklaufleiste(m, z.person)
                    }
                }
            } else {
                Text(Mitteilungstext.leer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            aktiv = Self.startwahl(startAnliegen, mitteilungen)
            felderLaden()
        }
        .onChange(of: aktiv) { _, _ in
            titelUebernehmen()
            notizUebernehmen()
            // Das Auswahlfeld nimmt den Fokus nicht: Titel und Notiz zeigen sonst die vorige (Z-BC2-07). Geladen wird ohne Blick
            // auf den Fokus — `@FocusState` meldet den neuen Wert erst nach dem nächsten Durchgang (Z-BC2N-01).
            if fokus == .titel || fokus == .notiz { fokus = nil }
            felderLaden(trotzFokus: true)
        }
        // Eine andere Lerngruppe: ihre jüngste (E993) — das Blatt behält diese Ansicht, `onAppear` kommt nicht (Z-BC2-01).
        .onChange(of: gruppe.id) { _, _ in
            titelUebernehmen()
            notizUebernehmen()
            if fokus == .titel || fokus == .notiz { fokus = nil }
            aktiv = Self.startwahl(nil, mitteilungen)
            felderLaden(trotzFokus: true)
        }
        .onChange(of: leistenId) { _, _ in
            notizUebernehmen()
            felderLaden()
        }
        .onChange(of: bezug.entwurf) { alt, neu in
            // Kehrt eine Mitteilung dieser Lerngruppe zurück — ⌘Z nach „Löschen“, ⇧⌘Z nach „Anlegen“ —, ist sie gewählt.
            if let zurueck = Self.neuErschienen(alt: alt, neu: neu, gruppe: gruppe.id) { aktiv = zurueck }
            if aktiv == nil || aktive == nil { aktiv = mitteilungen.last?.id }
            felderLaden()
        }
        .onChange(of: fokus) { alt, _ in
            if alt == .titel { titelUebernehmen() }
            if alt == .notiz { notizUebernehmen() }
        }
    }

    // ── Rein, damit die Suite es prüft (v91, BC2) ─────────────────────────

    /// Die Zeilen der Tabelle (V2): die Betroffenen der gewählten Mitteilung unter `personen` — den Mitgliedern, mit dem
    /// Schalter auch den archivierten —, in deren Folge. Wer betroffen ist, die Lerngruppe aber verließ, steht wie bei den
    /// Maßnahmen nicht darin; der Bogen „Rückmeldungsliste“ führt ihn unter „nicht mehr in der Lerngruppe“ (E484).
    nonisolated static func zeilen(_ m: Anliegen, _ personen: [Lernender]) -> [Lernender] {
        let betroffen = Set(m.betroffene)
        return personen.filter { betroffen.contains($0.id) }
    }

    /// Wessen Leiste unter der Tabelle steht (E999, Z-BC2-02): die gewählte Person, wenn sie eine Zeile ist — sonst, wenn von
    /// mehreren Gewählten genau eine in der Tabelle steht, diese; sonst keine.
    nonisolated static func leistenperson(_ person: String?, gewaehlt: Set<String>, sichtbar: [String]) -> String? {
        if let person, sichtbar.contains(person) { return person }
        let da = sichtbar.filter(gewaehlt.contains)
        return da.count == 1 ? da[0] : nil
    }

    /// Die Zeilen der Tabelle samt dem Rang des Stands je Person — wie `Massnahmenzeile.stand` (E1008).
    nonisolated static func reihen(_ m: Anliegen, _ personen: [Lernender], _ v: Lernendenverzeichnis) -> [Ruecklaufzeile] {
        personen.map { Ruecklaufzeile(person: $0, stand: v.stand(m.id, $0.id).rang) }
    }

    /// Die eine Mitteilung der Lerngruppe, die im neuen Stand dazukam — nach ⌘Z eines Löschens oder ⇧⌘Z eines Anlegens
    /// (W1-07); `nil`, wenn keine oder mehrere dazukamen.
    nonisolated static func neuErschienen(alt: Lernendenbestand, neu: Lernendenbestand, gruppe: String) -> String? {
        // Über alle Anliegen: Eine beim Zusammenführen übergegangene Mitteilung ist nicht neu (N7-04).
        let vorher = Set(alt.anliegen.map(\.id))
        let dazu = neu.anliegen.filter { $0.art == .mitteilung && $0.lerngruppe == gruppe && !vorher.contains($0.id) }
        return dazu.count == 1 ? dazu[0].id : nil
    }

    /// Die Frist einer neuen Mitteilung aus der Anlegezeile (E992): mit Haken das Datum, sonst keine (Z-BC3-01).
    nonisolated static func fristBeimAnlegen(mitFrist: Bool, _ tag: Tag) -> String { mitFrist ? tag.iso : "" }

    /// Die Frist nach einem Klick auf das Kästchen der Leiste (E992): an — eine Woche ab heute, aus — keine (Z-BC3-01).
    nonisolated static func fristNachKaestchen(_ an: Bool, heute: Tag) -> String {
        an ? heute.plus(tage: Mitteilungstext.fristTage).iso : ""
    }

    /// Die Mitteilung beim Erscheinen (V7): die vorgegebene, wenn sie zur Gruppe gehört — sonst die jüngste.
    nonisolated static func startwahl(_ vorgabe: String?, _ mitteilungen: [Anliegen]) -> String? {
        vorgabe.flatMap { id in mitteilungen.first { $0.id == id }?.id } ?? mitteilungen.last?.id
    }

    /// Wen „Auch an …“ anbietet: die angezeigten Mitglieder, die die Mitteilung nicht betrifft, in der Folge der Liste — auch,
    /// wer nach dem Anlegen in die Lerngruppe kam (aufgenommen nur von Hand, BC4); Archivierte nur mit dem Schalter, wie
    /// „Auch für …“ der Vereinbarungen und das frühere „In die Mitteilung aufnehmen“ (Z-BC2-06).
    nonisolated static func aufzunehmen(_ m: Anliegen, _ personen: [Lernender]) -> [Lernender] {
        let betroffen = Set(m.betroffene)
        return personen.filter { !betroffen.contains($0.id) }
    }

    /// „Alle Mitglieder der Lerngruppe“: die aktiven unter den Aufzunehmenden — erst ab zweien, sonst keiner (wie E853).
    nonisolated static func alleAufzunehmen(_ weitere: [Lernender]) -> [String] {
        let aktive = weitere.filter { $0.archiviert.isEmpty }.map(\.id)
        return aktive.count > 1 ? aktive : []
    }

    /// „Alle Mitglieder der Lerngruppe“ aus „Auch an …“: die Aufzunehmenden in einem Schritt hinten an die Betroffenen — am
    /// Stand, auf den der Schritt trifft, über `mitBetroffenen`.
    nonisolated static func alleAufnehmen(_ stand: Lernendenbestand, _ id: String, _ ids: [String],
                                          jetzt: String) -> Lernendenbestand {
        guard let m = stand.anliegen.first(where: { $0.id == id }) else { return stand }
        return stand.mitBetroffenen(id, m.betroffene + ids, jetzt: jetzt)
    }

    /// „Wandertag · 01.09.2026“ — Titel · Tag mit Jahr, für das Auswahlfeld über der Tabelle und die Zeile im Bogen
    /// „Rückmeldungsliste“ (E775); ohne Tag nur der Titel.
    nonisolated static func wahltitel(_ m: Anliegen) -> String {
        Tag(iso: m.datum).map { "\(m.titel) · \($0.deutsch)" } ?? m.titel
    }

    // ── Die Zeilen über der Tabelle ───────────────────────────────────────

    /// „Neue Mitteilung“ und „an …“ (V4); darunter „Rückmeldung bis“ (wahlweise, V6), das Datum und „Anlegen“ — zwei Zeilen
    /// wie die der Vereinbarungen (BC5).
    private var anlegezeile: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Einmal je Durchgang (W1-06).
            let gruppenmitglieder = aktiveMitglieder
            HStack(spacing: 8) {
                TextField("Neue Mitteilung", text: $neuerTitel)
                    .focused($fokus, equals: .neu)
                    .onSubmit { anlegen() }
                    .frame(maxWidth: .infinity)
                // V4 (a): „an alle Mitglieder“ vorgegeben, „Einzelne …“ öffnet die Liste mit Häkchen.
                Menu(adressaten.titel(gruppenmitglieder)) {
                    Toggle(Mitteilungstext.alleMitglieder, isOn: Binding(get: { adressaten == .alle },
                                                                         set: { _ in adressaten = .alle }))
                    Button(Mitteilungstext.einzelne) { einzelneWaehlen() }
                        // Ohne aktive Mitglieder gäbe es im Bogen nichts zu wählen (Z-BC4-06).
                        .disabled(gruppenmitglieder.isEmpty)
                }
                // Ein langer Name im Titel wird gekürzt, nicht die Zeile verbreitert (wie Z-AZ4-03); rechts bündig wie dort.
                .frame(maxWidth: 260, alignment: .trailing)
                .help(Mitteilungstext.anHilfe)
            }
            HStack(spacing: 8) {
                Toggle(Mitteilungstext.rueckmeldungBis, isOn: $mitFrist)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    // Für VoiceOver vom Kästchen der Leiste unterschieden (Z-BC3-06).
                    .accessibilityLabel(Mitteilungstext.fristNeuBezeichnung)
                Datumsfeld(tag: $neueFrist)
                    .frame(width: 130)
                    .disabled(!mitFrist)
                    .accessibilityLabel(Mitteilungstext.fristNeuBezeichnung)
                let ohneTitel = neuerTitel.trimmingCharacters(in: .whitespaces).isEmpty
                let ohneAdressaten = !adressaten.anlegbar(gruppenmitglieder)
                Button {
                    anlegen()
                } label: {
                    Label("Anlegen", systemImage: Zeichen.plus)
                }
                .disabled(ohneTitel || ohneAdressaten)
                // Gesperrt sichtbar wie H1 (E761, Z-AW5bN-06) — ohne Adressaten mit eigenem Grund, ohne aktives Mitglied
                // mit diesem: „Einzelne …“ ist dann ebenfalls gesperrt (W1-10).
                .hilfe(Mitteilungstext.anlegenHilfe(ohneAdressaten: ohneAdressaten, keinAktives: gruppenmitglieder.isEmpty),
                       gesperrt: ohneTitel || ohneAdressaten)
                Spacer(minLength: 0)
            }
        }
    }

    /// Über der Tabelle (V1): das Auswahlfeld — es wählt Anzeige und „Löschen …“ zugleich —, die Zahl der Rückläufe,
    /// „Löschen …“ und rechts „Rückmeldungsliste …“ (E633), grau ohne Mitteilung.
    private var auswahlzeile: some View {
        HStack(spacing: 8) {
            if let m = aktive {
                Picker(Mitteilungstext.auswahlBezeichnung, selection: $aktiv) {
                    ForEach(mitteilungen) { Text(Self.wahltitel($0)).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .frame(maxWidth: 360, alignment: .leading)
                .help(Mitteilungstext.auswahlHilfe)
                Text(Mitteilungstext.zurueck(m, bezug.verzeichnis))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            if let m = aktive {
                Button("Löschen …", role: .destructive) { bezug.loeschen(m.id) }
                    .fixedSize()
                    .help(Mitteilungstext.loeschenHilfe)
            }
            let knopf = Rueckmeldungslistenbogen.knopf(mitteilungen: mitteilungen.count)
            Button(Rueckmeldungslistenbogen.knopftitel) {
                // Getippter Titel und getippte Notiz kommen in die Liste — der Klick nimmt den Fokus nicht mit.
                titelUebernehmen()
                notizUebernehmen()
                listeOeffnen()
            }
            .fixedSize()
            .disabled(knopf.gesperrt)
            // Gesperrt zeigt SwiftUI unter macOS keinen Hilfetext — eine durchsichtige Fläche trägt ihn (H1, Sichtprüfung AW5).
            .hilfe(knopf.hilfe, gesperrt: knopf.gesperrt)
        }
    }

    /// Die Tabelle der gewählten Mitteilung (V2, V3), wie die der Maßnahmen: je Betroffener eine Zeile — Person, der Titel,
    /// die Frist, der Stand als Menü (E280). Mehrere wie in macOS-Tabellen: ⌘-Klick, ⇧-Klick, ⌘A (v88, AZ4). Geordnet
    /// wird nach „Person“ (E362) und nach dem Stand wie bei den Maßnahmen (E1008) — Titel und Frist sind in jeder Zeile
    /// dieselben.
    private func tabelle(_ m: Anliegen, _ zeilen: [Ruecklaufzeile]) -> some View {
        Huelltabelle(zeilen, wahl: .mehrere(auswahl),
                     ordnung: Binding(get: { ordnung }, set: { ordnung = Tabellenordnung.mitVorigem($0, vorher: ordnung) }),
                     spalten: [
            Huellspalte(Mitteilungstext.spaltePerson, ordnen: KeyPathComparator(\.person, comparator: Namensfolge()),
                        breite: .bereich(min: 140, ideal: 180, max: nil), text: { $0.person.anzeigename }) { z in
                Text(z.person.anzeigename).foregroundStyle(z.person.archiviert.isEmpty ? .primary : .secondary)
            },
            Huellspalte(Mitteilungstext.spalteMitteilung, text: { _ in m.titel }) { _ in Text(m.titel).help(m.titel) },
            Huellspalte(Mitteilungstext.spalteFrist, breite: .fest(110),
                        text: { _ in Anliegenbezug.tagtext(m.frist) }) { z in fristtext(m, z.person) },
            // Fest breit wie die Stand-Spalte der Maßnahmen: Sie trägt „abgelehnt“ (E641); ordnet wie dort (E1008).
            Huellspalte(Mitteilungstext.spalteStand, ordnen: KeyPathComparator(\.stand), breite: .fest(130),
                        text: { bezug.verzeichnis.stand(m.id, $0.person.id).beschriftung(fuer: .mitteilung) },
                        bedienbar: true) { z in
                zelle(m, z.person)
            },
        ])
    }

    // ── Die Sammelleiste (v88, AZ4; E909, E929; AZ5: E937) ────────────────

    /// „Stand für „Wandertag · 01.09.2026““ — das Menü der Sammelleiste; die Mitteilung wie im Auswahlfeld (E775).
    nonisolated static func standmenueTitel(_ m: Anliegen) -> String { "Stand für „\(wahltitel(m))“" }

    /// E937 (a): nennt die Regel für „offen“ wie `tagNachStand` und `mitRuecklauf` (Z-AZ5-04).
    nonisolated static let standmenueHilfe = "Den Rücklauf der Gewählten zu dieser Mitteilung setzen — bei erledigt oder "
        + "abgelehnt gilt ohne Tag der heutige; „offen“ ohne Notiz nimmt den Rücklauf weg; sonst bleiben Tag und Notizen"

    /// Gesperrt, wenn keine der Gewählten betroffen und aktiv ist — wie „Archivieren“ der Mitgliederliste (E845).
    nonisolated static let standmenueSperrgrund = "Erst eine betroffene, aktive Person wählen"

    /// Der Hinweis nach dem Griff, wenn er Gewählte übergeht — `nil` ohne Übergangene.
    nonisolated static func uebergangenHinweis(_ zahl: Int, _ m: Anliegen) -> String? {
        guard zahl > 0 else { return nil }
        let titel = wahltitel(m)
        return zahl == 1
            ? "1 gewählte Person ist von „\(titel)“ nicht betroffen oder archiviert und blieb unverändert."
            : "\(zahl) Gewählte sind von „\(titel)“ nicht betroffen oder archiviert und blieben unverändert."
    }

    /// Haken und Sperre des Menüs der Sammelleiste (E929, Fälle 5 und 12) — über die betroffenen, aktiven Gewählten
    /// (`ruecklaufziel`), nicht über alle Gewählten (Z-AZ4-06).
    nonisolated static func sammelmenuelage(_ m: Anliegen, _ gewaehlt: [String], _ entwurf: Lernendenbestand,
                                            _ verzeichnis: Lernendenverzeichnis) -> Sammelmenuelage {
        let ziel = entwurf.ruecklaufziel(m.id, gewaehlt)
        return Sammelmenuelage(haken: gemeinsamerStand(ziel, m, verzeichnis), gesperrt: ziel.isEmpty)
    }

    /// Der Stand, den das Menü abhakt — nur, wenn alle, die der Griff ändern darf, ihn schon haben (wie das Menü einer Zelle).
    nonisolated static func gemeinsamerStand(_ ziel: [String], _ m: Anliegen,
                                             _ verzeichnis: Lernendenverzeichnis) -> Rueckmeldestand? {
        let staende = Set(ziel.map { verzeichnis.stand(m.id, $0) })
        return staende.count == 1 ? staende.first : nil
    }

    /// Der Stand einer Person als Menü (E280): Die Wahl gilt sofort und setzt die Leiste auf diese Zeile — erst das
    /// Ausstehende; gehört die getippte Notiz zu eben dieser Zeile, kommt sie mit. Jede Zeile ist betroffen (V2).
    private func zelle(_ m: Anliegen, _ p: Lernender) -> some View {
        let rueck = bezug.verzeichnis.rueckmeldung(m.id, p.id)
        return Standmenue(stand: rueck?.stand ?? .offen, art: .mitteilung) { neu in
            let paar = Paar(anliegen: m.id, person: p.id)
            let neueNotiz = notizFuer == paar ? notiz : (rueck?.notiz ?? "")
            if notizFuer != paar { notizUebernehmen() }
            titelUebernehmen()
            person = p.id
            eintragen(m, p, stand: neu, datum: tagNachStand(neu, rueck), notiz: neueNotiz)
        }
    }

    /// Die Frist — orange, wenn sie verstrichen ist und die Person noch offen steht, wie bei den Maßnahmen (BC3).
    private func fristtext(_ m: Anliegen, _ p: Lernender) -> some View {
        let verstrichen = Anliegenbezug.verstrichen(m.frist, bezug.verzeichnis.stand(m.id, p.id),
                                                    heute: bezug.verzeichnis.heute)
        return Text(Anliegenbezug.tagtext(m.frist))
            .foregroundStyle(verstrichen ? Color.orange : Color.primary)
            .help(verstrichen ? Anliegenbezug.fristVerstrichen : "")
    }

    // ── Unter der Tabelle ─────────────────────────────────────────────────

    /// Die gewählte Mitteilung selbst: Titel, Tag und „Rückmeldung bis“ (BC3), rechts „Auch an …“ — von Hand aufnehmen,
    /// auch wer nach dem Anlegen in die Lerngruppe kam; von selbst geschieht das nie (BC4).
    private func mitteilungsleiste(_ m: Anliegen, _ personen: [Lernender]) -> some View {
        let weitere = Self.aufzunehmen(m, personen)
        let alle = Self.alleAufzunehmen(weitere)
        return HStack(spacing: 8) {
            TextField("Titel", text: $titel)
                .focused($fokus, equals: .titel)
                .onSubmit { titelUebernehmen() }
                .accessibilityLabel(Mitteilungstext.titelBezeichnung)
            // Je Mitteilung ein eigenes Feld: Getipptes ohne ⏎ wandert beim Wechsel im Auswahlfeld nicht weiter (W1-02).
            Datumsfeld(tag: Binding(get: { Tag(iso: m.datum) ?? .heute },
                                    set: { mitteilungSetzen(m.id, datum: $0.iso, kennung: m.id) }))
                .frame(width: 130)
                .id(m.id)
                .accessibilityLabel(Mitteilungstext.tagBezeichnung)
            // Das Kästchen ist ein eigener Schritt (wie Z-AX3-07); Änderungen an einem Datum fassen sich über die Kennung
            // zusammen — Tag und Frist je für sich (W1-04).
            Toggle(Mitteilungstext.rueckmeldungBis, isOn: Binding(get: { !m.frist.isEmpty }, set: { an in
                mitteilungSetzen(m.id, frist: Self.fristNachKaestchen(an, heute: .heute), kennung: nil)
            }))
            .toggleStyle(.checkbox)
            .fixedSize()
            // Gesperrt zeigt es, was der Haken setzen würde (W1-05).
            Datumsfeld(tag: Binding(get: { Tag(iso: m.frist) ?? .heute.plus(tage: Mitteilungstext.fristTage) },
                                    set: { mitteilungSetzen(m.id, frist: $0.iso, kennung: "\(m.id)/frist") }))
                .frame(width: 130)
                .disabled(m.frist.isEmpty)
                .id(m.id)
                .accessibilityLabel(Mitteilungstext.fristBezeichnung)
            if !weitere.isEmpty {
                Menu(Mitteilungstext.auchAn) {
                    if !alle.isEmpty {
                        Button(Mitteilungstext.auchAnAlle) {
                            bezug.handgriff(Schrittname.betroffeneAendern, nil) {
                                Self.alleAufnehmen($0, m.id, alle, jetzt: bezug.jetzt)
                            }
                        }
                        Divider()
                    }
                    ForEach(weitere) { w in
                        Button(w.anzeigename) {
                            bezug.handgriff(Schrittname.betroffeneAendern, nil) {
                                $0.mitBetroffenem(m.id, w.id, true, jetzt: bezug.jetzt)
                            }
                        }
                    }
                }
                .fixedSize()
                .help(Mitteilungstext.auchAnHilfe)
            }
        }
    }

    /// Der Rücklauf der gewählten Person — sie ist betroffen, sonst stünde sie nicht in der Tabelle (V2): Stand und Tag,
    /// darunter die Notiz und „Aus der Mitteilung nehmen“.
    private func ruecklaufleiste(_ m: Anliegen, _ p: Lernender) -> some View {
        let rueck = bezug.verzeichnis.rueckmeldung(m.id, p.id)
        let stand = rueck?.stand ?? .offen
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(p.anzeigename)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Picker("Stand", selection: Binding(
                    get: { stand },
                    set: { neu in eintragen(m, p, stand: neu, datum: tagNachStand(neu, rueck), notiz: rueck?.notiz ?? "") })) {
                    ForEach(Rueckmeldestand.allCases, id: \.self) { Text($0.beschriftung(fuer: .mitteilung)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if stand != .offen {
                    Datumsfeld(tag: Binding(
                        get: { Tag(iso: rueck?.datum ?? "") ?? .heute },
                        set: { tag in eintragen(m, p, stand: stand, datum: tag.iso, notiz: rueck?.notiz ?? "") }))
                        .frame(width: 130)
                        // Je Mitteilung und Person ein eigenes Feld — wie Tag und Frist der Mitteilung (W1-02, N7-02).
                        .id("\(m.id)/\(p.id)")
                        .accessibilityLabel("Tag des Rücklaufs")
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                TextField("Notiz", text: $notiz)
                    .focused($fokus, equals: .notiz)
                    .onSubmit { notizUebernehmen() }
                Button(Mitteilungstext.ausNehmen) {
                    bezug.handgriff(Schrittname.betroffeneAendern, nil) { $0.mitBetroffenem(m.id, p.id, false, jetzt: bezug.jetzt) }
                }
                .fixedSize()
                .help(Mitteilungstext.ausNehmenHilfe)
            }
        }
        .padding(8)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }

    /// Ab zwei Gewählten statt der Leiste einer Person (E929): „3 gewählt“ und das Menü mit dem Stand für die gewählte
    /// Mitteilung — gesperrt mit Grund, wenn keine der Gewählten betroffen und aktiv ist (wie E845).
    private func sammelleiste(_ m: Anliegen, _ gewaehlt: [String]) -> some View {
        let lage = Self.sammelmenuelage(m, gewaehlt, bezug.entwurf, bezug.verzeichnis)
        return HStack(spacing: 8) {
            Text(Lernendenblatt.sammelkopf(gewaehlt.count))
                .font(.callout.weight(.semibold))
                .fixedSize()
            Spacer(minLength: 0)
            Menu(Self.standmenueTitel(m)) {
                ForEach(Rueckmeldestand.allCases, id: \.self) { s in
                    // Ein Haken nur am gemeinsamen Stand; jede Wahl setzt ihn (Fall 5).
                    Toggle(s.beschriftung(fuer: .mitteilung), isOn: Binding(
                        get: { lage.haken == s },
                        set: { _ in standFuerGewaehlte(m.id, gewaehlt, s) }))
                }
            }
            // Ein Titel trägt bis zu 200 Zeichen: gekürzt im Menü, nicht über die Spalte hinaus (Z-AZ4-03).
            .frame(maxWidth: 420, alignment: .trailing)
            .disabled(lage.gesperrt)
            .hilfe(lage.gesperrt ? Self.standmenueSperrgrund : Self.standmenueHilfe, gesperrt: lage.gesperrt)
        }
        .padding(8)
        .background(.quinary, in: .rect(cornerRadius: 8))
        // Für VoiceOver eine Gruppe mit Namen, wie die Sammelleiste der Mitgliederliste (Z-AX4-08).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Lernendenblatt.sammelkopf(gewaehlt.count))
    }

    /// Der Stand für die Gewählten: erst das Ausstehende aus den Feldern (E280), dann am Entwurf, wie er danach ist
    /// (Z-AZ4-04), ein Schritt mit der Zahl der Personen, deren Rücklauf sich ändert (E915) — ohne Änderung keiner; übergangene
    /// Gewählte nennt der Hinweis (E929), die Grenze der Datei eine Warnung ohne Schritt (E935).
    private func standFuerGewaehlte(_ id: String, _ gewaehlt: [String], _ stand: Rueckmeldestand) {
        titelUebernehmen()
        notizUebernehmen()
        let entwurf = bezug.aktuell() ?? bezug.entwurf
        guard let m = entwurf.anliegen.first(where: { $0.id == id }) else { return }
        let heute = Tag.heute.iso
        let jetzt = bezug.jetzt
        let ergebnis = entwurf.mitRuecklaeufen(id, gewaehlt, stand: stand, heute: heute, jetzt: jetzt)
        if let grund = ergebnis.grund {
            bezug.warnen(grund)
            return
        }
        if ergebnis.zahl > 0 {
            // Einmal gerechnet (R89-05): Ist der Entwurf im Handgriff derselbe, gilt das Ergebnis von eben.
            bezug.handgriff(Schrittname.ruecklaeufeAendern(ergebnis.zahl), nil) {
                $0 == entwurf ? ergebnis.bestand
                    : $0.mitRuecklaeufen(id, gewaehlt, stand: stand, heute: heute, jetzt: jetzt).bestand
            }
        }
        if let hinweis = Self.uebergangenHinweis(ergebnis.uebergangen, m) { bezug.melden(hinweis) }
    }

    /// Ein Stand ohne Tag bekommt den heutigen; „offen“ behält, was da ist — dieselbe Regel wie für mehrere (E910).
    private func tagNachStand(_ stand: Rueckmeldestand, _ rueck: Rueckmeldung?) -> String {
        Lernendenbestand.tagNachStand(stand, bisher: rueck?.datum ?? "", heute: Tag.heute.iso)
    }

    private func eintragen(_ m: Anliegen, _ p: Lernender, stand: Rueckmeldestand, datum: String, notiz: String) {
        bezug.handgriff(Schrittname.ruecklaufEintragen, "\(m.id)/\(p.id)") {
            $0.mitRuecklauf(m.id, p.id, stand: stand, datum: datum, notiz: notiz, jetzt: bezug.jetzt)
        }
    }

    /// Nur Tag oder Frist — Titel und Notiz aus dem Stand, auf den der Schritt trifft, nicht aus dem gezeichneten (wie
    /// Z-AX3-08). `kennung` fasst Änderungen am Datum zusammen; das Kästchen geht ohne.
    private func mitteilungSetzen(_ id: String, datum: String? = nil, frist: String? = nil, kennung: String?) {
        bezug.handgriff(Schrittname.mitteilungAendern, kennung) { stand in
            guard let m = stand.anliegen.first(where: { $0.id == id }) else { return stand }
            return stand.mitAnliegen(id, titel: m.titel, datum: datum ?? m.datum, frist: frist ?? m.frist, notiz: m.notiz,
                                     jetzt: bezug.jetzt)
        }
    }

    /// An die Adressaten der Anlegezeile (V4) — festgehalten in diesem Augenblick; danach wieder „an alle Mitglieder“, damit
    /// die nächste nicht versehentlich nur an die Gewählten geht.
    private func anlegen() {
        guard adressaten.anlegbar(aktiveMitglieder) else { return }
        let personen = adressaten.betroffene(aktiveMitglieder)
        guard let id = bezug.anlegen(.mitteilung, neuerTitel, personen, Tag.heute.iso,
                                     Self.fristBeimAnlegen(mitFrist: mitFrist, neueFrist))
        else { return }
        neuerTitel = ""
        adressaten = .alle
        aktiv = id
    }

    /// Die Person der Leiste (Z-BC2-02) — dieselbe Regel wie im Körper.
    private var leistenId: String? {
        guard let m = aktive else { return nil }
        return Self.leistenperson(person, gewaehlt: auswahl.wrappedValue,
                                  sichtbar: Self.zeilen(m, bezug.personen(gruppe)).map(\.id))
    }

    /// Titel und Notiz der gezeigten Mitteilung in die Felder — ein Feld mit dem Fokus nur mit `trotzFokus` (nach einem
    /// Wechsel der Mitteilung oder der Lerngruppe, wenn das Getippte schon übernommen ist).
    private func felderLaden(trotzFokus: Bool = false) {
        if trotzFokus || fokus != .titel {
            titel = aktive?.titel ?? ""
            titelFuer = aktive?.id
        }
        if trotzFokus || fokus != .notiz {
            let paar = aktiv.flatMap { a in leistenId.map { Paar(anliegen: a, person: $0) } }
            notiz = paar.flatMap { bezug.verzeichnis.rueckmeldung($0.anliegen, $0.person)?.notiz } ?? ""
            notizFuer = paar
        }
    }

    private func titelUebernehmen() {
        guard let id = titelFuer, let m = bezug.entwurf.anliegen.first(where: { $0.id == id && $0.art == .mitteilung }),
              !titel.trimmingCharacters(in: .whitespaces).isEmpty,
              Lernendenbestand.zeile(titel, Lernendendatei.maxTitel) != m.titel else { return }
        // Kein Nachladen hier: Der Stand dieser Ansicht ist noch der alte, und
        // eine ausstehende Notiz ginge verloren — nachgeladen wird mit dem neuen.
        bezug.handgriff(Schrittname.mitteilungAendern, id) { stand in
            // Tag, Frist und Notiz aus dem Stand, auf den der Schritt trifft — nicht aus dem gezeichneten (Z-BC3-03).
            guard let a = stand.anliegen.first(where: { $0.id == id }) else { return stand }
            return stand.mitAnliegen(id, titel: titel, datum: a.datum, frist: a.frist, notiz: a.notiz, jetzt: bezug.jetzt)
        }
    }

    private func notizUebernehmen() {
        guard let paar = notizFuer,
              let m = bezug.entwurf.anliegen.first(where: { $0.id == paar.anliegen && $0.art == .mitteilung }),
              let p = bezug.verzeichnis.person(paar.person), m.betroffene.contains(paar.person) else { return }
        let anliegen = paar.anliegen
        let person = paar.person
        let rueck = bezug.verzeichnis.rueckmeldung(anliegen, person)
        guard Lernendenbestand.notiztext(notiz) != (rueck?.notiz ?? "") else { return }
        eintragen(m, p, stand: rueck?.stand ?? .offen, datum: rueck?.datum ?? "", notiz: notiz)
    }
}

// ── Die Maßnahmen ─────────────────────────────────────────────────────────

/// Eine Zeile: eine Maßnahme für eine Person — der Stand gilt je Person. Dazu die Felder, nach denen ein Kopfklick
/// ordnet (E362, E363): Name, Titel, Frist als ISO-Tag, der Stand als Rang (offen, erfüllt, nicht erfüllt).
struct Massnahmenzeile: Identifiable {
    let massnahme: Anliegen
    let person: Lernender
    let name: String
    let titel: String
    let frist: String
    let stand: Int
    var id: String { "\(massnahme.id)/\(person.id)" }
}

/// Eine Maßnahme oder ein Termin ohne Lerngruppe an der Person, mit den Feldern für die Ordnung (E362): `tag` ist bei
/// einer Maßnahme die Frist, bei einem Termin Tag und Uhrzeit — als Text zugleich zeitlich geordnet.
struct Personenanliegenzeile: Identifiable {
    let anliegen: Anliegen
    let art: String
    let titel: String
    let tag: String
    let stand: Int
    var id: String { anliegen.id }
}

/// Die Ordnung der drei Tabellen der Anliegen — am Blatt gehalten, damit sie erst mit ihm verfällt (E364, E501);
/// leer heißt: die Folge wie bisher. Die Rücklaufliste ordnet nach „Person“ (Vorgabe, E362) und nach „Stand“ (E1008).
struct Anliegenordnung: Equatable {
    var ruecklauf = [KeyPathComparator(\Ruecklaufzeile.person, comparator: Namensfolge())]
    var massnahmen: [KeyPathComparator<Massnahmenzeile>] = []
    var vereinbarungen: [KeyPathComparator<Vereinbarungszeile>] = []
    var personenanliegen: [KeyPathComparator<Personenanliegenzeile>] = []
}

/// „Name“ ordnet wie alle Listen: Nachname, dann Vorname (`Lernendenverzeichnis.vorgehen`) — nicht nach dem
/// angezeigten Text, der „Meier Schulz“ vor „Meier, Anna“ stellt (Z-AT3-01).
struct Namensfolge: SortComparator {
    var order: SortOrder = .forward

    func compare(_ a: Lernender, _ b: Lernender) -> ComparisonResult {
        guard a.id != b.id else { return .orderedSame }
        return Lernendenverzeichnis.vorgehen(a, b) == (order == .forward) ? .orderedAscending : .orderedDescending
    }
}

extension Rueckmeldestand {
    /// Der Rang für die Ordnung: offen, erledigt (erfüllt, stattgefunden), abgelehnt (nicht erfüllt, abgesagt).
    var rang: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

extension Massnahmenliste {
    /// Geordnet nach dem Kopfklick — ohne Klick in der Folge wie bisher.
    nonisolated static func geordnet<Zeile: Identifiable>(_ zeilen: [Zeile], _ ordnung: [KeyPathComparator<Zeile>]) -> [Zeile]
        where Zeile.ID == String {
        ordnung.isEmpty ? zeilen : Tabellenordnung.geordnet(zeilen, nach: ordnung)
    }

    /// Die Zeilen der Maßnahmen der Mitglieder — in der Folge der Jahresdatei.
    nonisolated static func zeilen(_ mitglieder: [Lernender], _ verzeichnis: Lernendenverzeichnis) -> [Massnahmenzeile] {
        let personen = Dictionary(uniqueKeysWithValues: mitglieder.map { ($0.id, $0) })
        return verzeichnis.massnahmen(fuer: Set(personen.keys)).flatMap { m in
            m.betroffene.compactMap { personen[$0] }.map { p in
                Massnahmenzeile(massnahme: m, person: p, name: p.anzeigename, titel: m.titel, frist: m.frist,
                                stand: verzeichnis.stand(m.id, p.id).rang)
            }
        }
    }
}

extension Personenanliegen {
    /// Die Zeilen der Maßnahmen und Termine ohne Lerngruppe einer Person — in der Folge der Jahresdatei.
    nonisolated static func zeilen(_ person: String, _ verzeichnis: Lernendenverzeichnis) -> [Personenanliegenzeile] {
        verzeichnis.anliegenOhneGruppe(von: person).map { a in
            Personenanliegenzeile(anliegen: a, art: a.art.titel, titel: a.titel,
                                  tag: a.art == .massnahme || a.art == .vereinbarung ? a.frist
                                      : a.datum + (a.uhrzeit.isEmpty ? "" : " " + a.uhrzeit),
                                  stand: a.art == .vereinbarung
                                      ? Rueckmeldestand.allCases.count + (Gueltigkeit.allCases.firstIndex(of: verzeichnis.gueltigkeit(a, person)) ?? 0)
                                      : verzeichnis.stand(a.id, person).rang)
        }
    }
}

struct Massnahmenliste: View {
    let gruppe: Lerngruppe
    let bezug: Anliegenbezug
    var startZeile: String?
    /// Die Ordnung der Tabelle — am Blatt gehalten (E362, E364); leer: die Folge wie bisher.
    @Binding var ordnung: [KeyPathComparator<Massnahmenzeile>]

    @State private var zeile: String?
    @State private var neuerTitel = ""
    @State private var fuer: String?
    @State private var neueFrist = Tag.heute.plus(tage: 7)
    @State private var titel = ""
    @State private var notiz = ""
    @FocusState private var fokus: Feld?

    private enum Feld: Hashable { case neu, titel, notiz }

    private var mitglieder: [Lernender] { bezug.personen(gruppe) }

    private var zeilen: [Massnahmenzeile] { Self.zeilen(mitglieder, bezug.verzeichnis) }

    private var gewaehlt: Massnahmenzeile? { zeilen.first { $0.id == zeile } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Zwei Zeilen wie „Neue Vereinbarung“ (v91, Z-BC5-04): In einer Zeile machte `.fixedSize()` die Wahl „für“ so
            // breit wie der längste Name — das Feld schrumpfte auf „Neue M…“, „Anlegen“ auf „…“.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Neue Maßnahme", text: $neuerTitel)
                        .focused($fokus, equals: .neu)
                        .onSubmit { anlegen() }
                        .frame(maxWidth: .infinity)
                    Picker("für", selection: $fuer) {
                        Text("—").tag(String?.none)
                        ForEach(mitglieder) { Text($0.anzeigename).tag(Optional($0.id)) }
                    }
                    // Höchstens 280 breit und rechts bündig wie bei den Vereinbarungen; ein längerer Name wird gekürzt.
                    .frame(maxWidth: 280, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Text("Frist").foregroundStyle(.secondary)
                    Datumsfeld(tag: $neueFrist)
                        .frame(width: 130)
                        .accessibilityLabel("Frist der neuen Maßnahme")
                    let gesperrt = neuerTitel.trimmingCharacters(in: .whitespaces).isEmpty
                        || Anliegenbezug.fuerGueltig(fuer, mitglieder) == nil
                    Button {
                        anlegen()
                    } label: {
                        Label("Anlegen", systemImage: Zeichen.plus)
                    }
                    .disabled(gesperrt)
                    // Gesperrt sichtbar wie „Anlegen“ der Mitteilung (Z-AW5bN-06).
                    .hilfe("Eine Maßnahme mit Frist für die gewählte Person anlegen (⏎)", gesperrt: gesperrt)
                    Spacer(minLength: 0)
                }
            }

            if zeilen.isEmpty {
                Text("Noch keine Maßnahme für Mitglieder dieser Lerngruppe. Eine Maßnahme betrifft eine oder wenige "
                     + "Personen und trägt eine Frist; ihr Stand ist offen, erfüllt oder nicht erfüllt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Huelltabelle(Self.geordnet(zeilen, ordnung), wahl: .eine($zeile),
                             ordnung: Binding(get: { ordnung }, set: { ordnung = Tabellenordnung.mitVorigem($0, vorher: ordnung) }),
                             spalten: [
                    Huellspalte("Person", ordnen: KeyPathComparator(\.person, comparator: Namensfolge()),
                                text: { $0.name }) { z in Text(z.name) },
                    Huellspalte("Maßnahme", ordnen: KeyPathComparator(\.titel, comparator: .localizedStandard),
                                text: { $0.titel }) { z in Text(z.titel) },
                    Huellspalte("Frist", ordnen: KeyPathComparator(\.frist, comparator: String.StandardComparator.lexical),
                                breite: .fest(110), text: { Anliegenbezug.tagtext($0.massnahme.frist) }) { z in fristtext(z) },
                    Huellspalte("Stand", ordnen: KeyPathComparator(\.stand), breite: .fest(130), text: { z in
                        bezug.verzeichnis.stand(z.massnahme.id, z.person.id).beschriftung(fuer: .massnahme)
                    }, bedienbar: true) { z in
                        let rueck = bezug.verzeichnis.rueckmeldung(z.massnahme.id, z.person.id)
                        Standmenue(stand: rueck?.stand ?? .offen, art: .massnahme) { neu in
                            // Gehört die getippte Notiz zu eben dieser Zeile, kommt sie mit;
                            // sonst übernimmt der Wechsel der Zeile die der vorigen.
                            let neueNotiz = zeile == z.id ? notiz : (rueck?.notiz ?? "")
                            zeile = z.id
                            let bisher = rueck?.datum ?? ""
                            eintragen(z.massnahme, z.person, stand: neu,
                                      datum: neu != .offen && bisher.isEmpty ? Tag.heute.iso : bisher, notiz: neueNotiz)
                        }
                    },
                ])
                if let z = gewaehlt { leiste(z) }
            }
        }
        .onAppear {
            zeile = startZeile
            fuer = mitglieder.first?.id
            felderLaden()
        }
        // Eine andere Lerngruppe: erst das Getippte in die Zeile der vorigen (N7-05), dann „für“ auf ihr erstes Mitglied,
        // keine Zeile — das Blatt behält diese Ansicht, `onAppear` kommt nicht (W1-01, wie Z-BC2-01).
        .onChange(of: gruppe.id) { _, _ in
            uebernehmen(zeile, ueberAlle: true)
            if fokus == .titel || fokus == .notiz { fokus = nil }
            fuer = mitglieder.first?.id
            zeile = nil
            felderLaden()
        }
        .onChange(of: zeile) { alt, _ in
            uebernehmen(alt)
            felderLaden()
        }
        .onChange(of: bezug.entwurf) { _, _ in felderLaden() }
        .onChange(of: fokus) { alt, _ in
            if alt == .titel || alt == .notiz { uebernehmen(zeile) }
        }
    }

    /// Die Frist — orange, wenn sie verstrichen und die Maßnahme noch offen ist; dieselbe Regel wie bei den Mitteilungen
    /// (`Anliegenbezug.verstrichen`, v91), am Tag des Verzeichnisses.
    private func fristtext(_ z: Massnahmenzeile) -> some View {
        let verstrichen = Anliegenbezug.verstrichen(z.massnahme.frist, bezug.verzeichnis.stand(z.massnahme.id, z.person.id),
                                                    heute: bezug.verzeichnis.heute)
        return Text(Anliegenbezug.tagtext(z.massnahme.frist))
            .foregroundStyle(verstrichen ? Color.orange : Color.primary)
            .help(verstrichen ? Anliegenbezug.fristVerstrichen : "")
    }

    private func leiste(_ z: Massnahmenzeile) -> some View {
        let m = z.massnahme
        let p = z.person
        let rueck = bezug.verzeichnis.rueckmeldung(m.id, p.id)
        let stand = rueck?.stand ?? .offen
        let weitere = mitglieder.filter { !m.betroffene.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(p.anzeigename).font(.callout.weight(.semibold))
                Picker("Stand", selection: Binding(
                    get: { stand },
                    set: { neu in
                        let bisher = rueck?.datum ?? ""
                        eintragen(m, p, stand: neu, datum: neu != .offen && bisher.isEmpty ? Tag.heute.iso : bisher,
                                  notiz: rueck?.notiz ?? "")
                    })) {
                    ForEach(Rueckmeldestand.allCases, id: \.self) { Text($0.beschriftung(fuer: .massnahme)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if stand != .offen {
                    Datumsfeld(tag: Binding(
                        get: { Tag(iso: rueck?.datum ?? "") ?? .heute },
                        set: { tag in eintragen(m, p, stand: stand, datum: tag.iso, notiz: rueck?.notiz ?? "") }))
                        .frame(width: 130)
                        .accessibilityLabel("Tag der Erfüllung")
                }
                TextField("Notiz", text: $notiz)
                    .focused($fokus, equals: .notiz)
                    .onSubmit { uebernehmen(z.id) }
            }
            HStack(spacing: 8) {
                TextField("Titel", text: $titel)
                    .focused($fokus, equals: .titel)
                    .onSubmit { uebernehmen(z.id) }
                    .frame(width: 260)
                Text("Frist").foregroundStyle(.secondary)
                Datumsfeld(tag: Binding(
                    get: { Tag(iso: m.frist) ?? .heute },
                    set: { tag in
                        bezug.handgriff(Schrittname.massnahmeAendern, m.id) {
                            $0.mitAnliegen(m.id, titel: m.titel, datum: m.datum, frist: tag.iso, notiz: m.notiz,
                                           jetzt: bezug.jetzt)
                        }
                    }))
                    .frame(width: 130)
                    .accessibilityLabel("Frist")
                Spacer(minLength: 0)
                if !weitere.isEmpty {
                    Menu("Auch für …") {
                        ForEach(weitere) { w in
                            Button(w.anzeigename) {
                                bezug.handgriff(Schrittname.betroffeneAendern, nil) {
                                    $0.mitBetroffenem(m.id, w.id, true, jetzt: bezug.jetzt)
                                }
                            }
                        }
                    }
                    .fixedSize()
                    .help("Die Maßnahme gilt auch für eine weitere Person dieser Lerngruppe")
                }
                if m.betroffene.count > 1 {
                    Button("Für diese Person entfernen") {
                        bezug.handgriff(Schrittname.betroffeneAendern, nil) { $0.mitBetroffenem(m.id, p.id, false, jetzt: bezug.jetzt) }
                    }
                }
                Button("Löschen …", role: .destructive) { bezug.loeschen(m.id) }
                    .help("Die Maßnahme samt ihren Ständen löschen — mit Rückfrage")
            }
        }
        .padding(8)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }

    private func eintragen(_ m: Anliegen, _ p: Lernender, stand: Rueckmeldestand, datum: String, notiz: String) {
        bezug.handgriff(Schrittname.ruecklaufEintragen, "\(m.id)/\(p.id)") {
            $0.mitRuecklauf(m.id, p.id, stand: stand, datum: datum, notiz: notiz, jetzt: bezug.jetzt)
        }
    }

    private func anlegen() {
        guard let fuer = Anliegenbezug.fuerGueltig(fuer, mitglieder),
              let id = bezug.anlegen(.massnahme, neuerTitel, [fuer], Tag.heute.iso, neueFrist.iso) else { return }
        neuerTitel = ""
        zeile = "\(id)/\(fuer)"
    }

    /// Für welche Zeile die Felder geladen sind — nur in sie schreibt `uebernehmen` (BC7b).
    @State private var geladenFuer: String?

    private func felderLaden() {
        let z = gewaehlt
        if fokus != .titel { titel = z?.massnahme.titel ?? "" }
        if fokus != .notiz { notiz = z.flatMap { bezug.verzeichnis.rueckmeldung($0.massnahme.id, $0.person.id)?.notiz } ?? "" }
        geladenFuer = z?.id
    }

    /// Titel und Notiz der Zeile `id`, wie sie in den Feldern stehen — nichts, wenn sie gleich sind. Nur in die Zeile, für
    /// die die Felder geladen sind: Geleerte Felder gingen sonst in die Zeile, die die Person auch in einer anderen
    /// Lerngruppe hat (BC7b). `ueberAlle`: die Zeile auch außerhalb der gezeigten Lerngruppe — beim Wechsel (N7-05).
    private func uebernehmen(_ id: String?, ueberAlle: Bool = false) {
        guard let id, id == geladenFuer,
              let z = zeilen.first(where: { $0.id == id })
                ?? (ueberAlle ? Self.zeilen(bezug.entwurf.lernende, bezug.verzeichnis).first(where: { $0.id == id }) : nil)
        else { return }
        let m = z.massnahme
        if Lernendenbestand.zeile(titel, Lernendendatei.maxTitel) != m.titel, !titel.trimmingCharacters(in: .whitespaces).isEmpty {
            bezug.handgriff(Schrittname.massnahmeAendern, m.id) {
                $0.mitAnliegen(m.id, titel: titel, datum: m.datum, frist: m.frist, notiz: m.notiz, jetzt: bezug.jetzt)
            }
        }
        let rueck = bezug.verzeichnis.rueckmeldung(m.id, z.person.id)
        if Lernendenbestand.notiztext(notiz) != (rueck?.notiz ?? "") {
            eintragen(m, z.person, stand: rueck?.stand ?? .offen, datum: rueck?.datum ?? "", notiz: notiz)
        }
    }
}

// ── Die Vereinbarungen (v86, AX3: E741, E743, E745, E746, E751, E753–E755; R2-A1: E804, E806–E808, E812, E819) ──

/// Die Wortlaute der Vereinbarung (Tabellen 7, 8 und 9 in der Entscheidungsrunde AX0, bei Datum und Fuß nach E806–E808) —
/// an einer Stelle, damit die Suite sie prüft.
enum Vereinbarungstext {
    // Teil „Vereinbarungen“ der Lerngruppe (Tabelle 7, E753, E807)
    static let neue = "Neue Vereinbarung"
    /// Das Kästchen der Anlegezeile und das der Leiste — ein Wortlaut (E807).
    static let gueltigBis = "gültig bis einschließlich"
    static let anlegenHilfe = "Eine Vereinbarung für die gewählte Person anlegen (⏎)"
    static let leer = "Noch keine Vereinbarung für Mitglieder dieser Lerngruppe. Eine Vereinbarung betrifft eine oder wenige "
        + "Personen und gilt, bis sie abläuft oder ungültig gesetzt wird; ihr Stand ist gültig oder ungültig."
    static let spalteVereinbarung = "Vereinbarung"
    static let spalteGueltigBis = "Gültig bis"
    static let inhalt = "Inhalt der Vereinbarung"
    static let auchFuerHilfe = "Die Vereinbarung gilt auch für eine weitere Person dieser Lerngruppe"
    /// Oben im Menü „Auch für …“ (E853): alle aktiven Mitglieder, die noch nicht betroffen sind, in einem Schritt.
    static let auchFuerAlle = "Alle Mitglieder der Lerngruppe"
    static let loeschenHilfe = "Die Vereinbarung samt ihren Ständen löschen — mit Rückfrage"
    /// E808: „Abgelaufen — gültig bis einschließlich 31.10.2026“.
    static func abgelaufenHilfe(_ bis: Tag) -> String { "Abgelaufen — gültig bis einschließlich \(bis.deutsch)" }
    // VoiceOver (E819): `datumNeuBezeichnung` am Kästchen und am Datum der Anlegezeile, `datumBezeichnung` am Datum der Leiste.
    static let datumNeuBezeichnung = "Gültig bis einschließlich — neue Vereinbarung"
    static let datumBezeichnung = "Gültig bis einschließlich"
    // Der Bogen in „Alle Lernenden“ (Tabelle 8, E754, E807)
    static let knopf = "Vereinbarung …"
    static let knopfHilfe = "Eine Vereinbarung für diese Person, ohne Lerngruppe"
    static let titelAendern = "Vereinbarung ändern"
    static let platzhalter = "etwa Handyregel"
    static let gueltigBisBogen = "Gültig bis einschließlich"
    static let fuss = "Ohne Datum gilt die Vereinbarung, bis sie ungültig gesetzt wird; mit Datum gilt sie bis einschließlich "
        + "dieses Tages. Der Stand: gültig oder ungültig."
    // „Ohne Lerngruppe“, Filter, Archiv (Tabelle 9, E755, E807, E812)
    static let ohneLerngruppeLeer = "Keine Maßnahme, keine Vereinbarung und kein Termin ohne Lerngruppe."
    /// „Ändern …“ an einer Vereinbarung (E812); Maßnahme und Termin behalten „Titel, Tag und Notiz ändern“.
    static let aendernHilfe = "Titel, Gültigkeit und Inhalt ändern"
    /// Eine Vereinbarung ist kein offenes Anliegen (E804) — die Hilfe des Filters nennt sie nicht.
    static let filterHilfe = "Nur Personen mit offenen Mitteilungen, Maßnahmen oder Terminen zeigen"

    /// Die Spalte „Tag“ unter „Ohne Lerngruppe“ (E807): „gültig bis einschließlich 31.10.2026“, ohne Datum „—“.
    static func tag(_ a: Anliegen) -> String { Tag(iso: a.frist).map { "gültig bis einschließlich \($0.deutsch)" } ?? "—" }

    /// Die Hilfe am Stand einer abgelaufenen (E808): „Abgelaufen — gültig bis einschließlich 31.10.2026“ — nicht, wenn die
    /// Person von Hand ungültig ist; sonst keine. Im Teil „Vereinbarungen“ und unter „Ohne Lerngruppe“ (Z-R2A1-03).
    static func standHilfe(_ a: Anliegen, _ person: String, heute: Tag) -> String? {
        guard Lernendenbestand.abgelaufen(a, heute: heute), !a.ungueltig.contains(person), let bis = Tag(iso: a.frist) else {
            return nil
        }
        return abgelaufenHilfe(bis)
    }

    /// Unter „Ohne Lerngruppe“ ist der Stand ein Menü: an einer abgelaufenen die Hilfe nach E808, sonst „Stand ändern“.
    static func standmenueHilfe(_ a: Anliegen, _ person: String, heute: Tag) -> String {
        standHilfe(a, person, heute: heute) ?? "Stand ändern"
    }

    /// Unter „Alle Lernenden“ an der gewählten Person (E854): „Vereinbarungen: Handyregel (G6a, gültig) ·
    /// Sitzplatz (ohne Lerngruppe, ungültig)“ — alle ihre Vereinbarungen mit Lerngruppe und Stand; keine: nil.
    static func personenzeile(_ person: String, _ verzeichnis: Lernendenverzeichnis) -> String? {
        let liste = verzeichnis.vereinbarungen(fuer: [person])
        guard !liste.isEmpty else { return nil }
        return "Vereinbarungen: " + liste.map { a in
            let gruppe = verzeichnis.gruppe(a.lerngruppe)?.name ?? "ohne Lerngruppe"
            return "\(a.titel) (\(gruppe), \(verzeichnis.gueltigkeit(a, person).beschriftung))"
        }.joined(separator: " · ")
    }

    /// Der Stand im Archiv: „1 gültig · 1 ungültig“ — ohne die Zahlen null.
    static func standtext(gueltig: Int, ungueltig: Int) -> String {
        [(gueltig, Gueltigkeit.gueltig), (ungueltig, Gueltigkeit.ungueltig)].compactMap { zahl, g in
            zahl == 0 ? nil : "\(zahl) \(g.beschriftung)"
        }.joined(separator: " · ")
    }
}

/// Eine Zeile: eine Vereinbarung für eine Person — der Stand gilt je Person, „gültig bis“ für alle (E751, E807). Felder für
/// die Ordnung per Kopfklick wie bei den Maßnahmen (E362): der letzte gültige Tag als ISO-Tag, der Stand als Rang (gültig,
/// ungültig).
struct Vereinbarungszeile: Identifiable {
    let vereinbarung: Anliegen
    let person: Lernender
    let name: String
    let titel: String
    let ablauf: String
    let stand: Int
    var id: String { "\(vereinbarung.id)/\(person.id)" }
}

extension Vereinbarungsliste {
    /// „Alle Mitglieder der Lerngruppe“ (E853): die aktiven Mitglieder, die die Vereinbarung noch nicht betrifft — wie die
    /// Sammelleiste ohne Archivierte; erst ab zweien, sonst steht der eine Name schon darunter. Nur an einer Vereinbarung
    /// dieser Lerngruppe — die Tabelle zeigt auch die ihrer Mitglieder aus anderen Lerngruppen und ohne Lerngruppe
    /// (Z-AX9R2-03). Leer: kein Eintrag.
    nonisolated static func alleAufzunehmen(_ mitglieder: [Lernender], _ v: Anliegen, gruppe: String) -> [String] {
        guard v.lerngruppe == gruppe else { return [] }
        let ids = mitglieder.filter { $0.archiviert.isEmpty && !v.betroffene.contains($0.id) }.map(\.id)
        return ids.count > 1 ? ids : []
    }

    /// Die Umformung des Eintrags — ein Bestand, also ein Schritt „Betroffene ändern“ (E853, Z-AX9R2-06).
    nonisolated static func alleAufnehmen(_ stand: Lernendenbestand, _ id: String, _ ids: [String], jetzt: String)
        -> Lernendenbestand {
        ids.reduce(stand) { $0.mitBetroffenem(id, $1, true, jetzt: jetzt) }
    }

    /// Die Zeilen der Vereinbarungen der Mitglieder — in der Folge der Jahresdatei, der Stand abgeleitet am Tag des
    /// Verzeichnisses (E743).
    nonisolated static func zeilen(_ mitglieder: [Lernender], _ verzeichnis: Lernendenverzeichnis) -> [Vereinbarungszeile] {
        let personen = Dictionary(uniqueKeysWithValues: mitglieder.map { ($0.id, $0) })
        return verzeichnis.vereinbarungen(fuer: Set(personen.keys)).flatMap { v in
            v.betroffene.compactMap { personen[$0] }.map { p in
                Vereinbarungszeile(vereinbarung: v, person: p, name: p.anzeigename, titel: v.titel, ablauf: v.frist,
                                   stand: Gueltigkeit.allCases.firstIndex(of: verzeichnis.gueltigkeit(v, p.id)) ?? 0)
            }
        }
    }
}

/// Der Teil „Vereinbarungen“ der Lerngruppe (E741, E745): wie „Maßnahmen“ — eine Zeile je Vereinbarung und Person; angelegt
/// für eine Person der Lerngruppe, mit „Auch für …“ weitere. Der Stand „gültig“/„ungültig“ je Person (E746); ab dem Tag nach
/// „gültig bis einschließlich“ abgeleitet „ungültig“ (E743, E806).
struct Vereinbarungsliste: View {
    let gruppe: Lerngruppe
    let bezug: Anliegenbezug
    /// Die anfangs gewählte Zeile „Vereinbarung/Person“ — wie bei den Maßnahmen (für das Abbild, E851).
    var startZeile: String?
    /// Die Ordnung der Tabelle — am Blatt gehalten (E362, E364); leer: die Folge wie bisher.
    @Binding var ordnung: [KeyPathComparator<Vereinbarungszeile>]

    @State private var zeile: String?
    @State private var neuerTitel = ""
    @State private var fuer: String?
    @State private var mitAblauf = false
    @State private var neuerAblauf = Tag.heute.plus(tage: 28)
    @State private var titel = ""
    @State private var inhalt = ""
    @FocusState private var fokus: Feld?

    private enum Feld: Hashable { case neu, titel, inhalt }

    private var mitglieder: [Lernender] { bezug.personen(gruppe) }
    private var zeilen: [Vereinbarungszeile] { Self.zeilen(mitglieder, bezug.verzeichnis) }
    private var gewaehlt: Vereinbarungszeile? { zeilen.first { $0.id == zeile } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Zwei Zeilen (v91, BC5): oben das Feld in der Breite der Zeile und „für“ — eine lange Wahl „für“ drückte es in
            // einer Zeile auf „Neue Vere…“ zusammen —, darunter „gültig bis einschließlich“, das Datum und „Anlegen“.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField(Vereinbarungstext.neue, text: $neuerTitel)
                        .focused($fokus, equals: .neu)
                        .onSubmit { anlegen() }
                        .frame(maxWidth: .infinity)
                    Picker("für", selection: $fuer) {
                        Text("—").tag(String?.none)
                        ForEach(mitglieder) { Text($0.anzeigename).tag(Optional($0.id)) }
                    }
                    // Höchstens 280 breit und rechts bündig — mit „für“ etwa so breit wie „an …“ bei den Mitteilungen (260);
                    // ein längerer Name wird gekürzt, das Feld behält seinen Platz (Z-BC5-02).
                    .frame(maxWidth: 280, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Toggle(Vereinbarungstext.gueltigBis, isOn: $mitAblauf)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        // Für VoiceOver vom Kästchen der Leiste unterschieden — wie bei den Mitteilungen.
                        .accessibilityLabel(Vereinbarungstext.datumNeuBezeichnung)
                    Datumsfeld(tag: $neuerAblauf)
                        .frame(width: 130)
                        .disabled(!mitAblauf)
                        .accessibilityLabel(Vereinbarungstext.datumNeuBezeichnung)
                    let gesperrt = neuerTitel.trimmingCharacters(in: .whitespaces).isEmpty
                        || Anliegenbezug.fuerGueltig(fuer, mitglieder) == nil
                    Button {
                        anlegen()
                    } label: {
                        Label("Anlegen", systemImage: Zeichen.plus)
                    }
                    .disabled(gesperrt)
                    .hilfe(Vereinbarungstext.anlegenHilfe, gesperrt: gesperrt)
                    Spacer(minLength: 0)
                }
            }

            if zeilen.isEmpty {
                Text(Vereinbarungstext.leer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Huelltabelle(Massnahmenliste.geordnet(zeilen, ordnung), wahl: .eine($zeile),
                             ordnung: Binding(get: { ordnung }, set: { ordnung = Tabellenordnung.mitVorigem($0, vorher: ordnung) }),
                             spalten: [
                    Huellspalte("Person", ordnen: KeyPathComparator(\.person, comparator: Namensfolge()),
                                text: { $0.name }) { z in Text(z.name) },
                    Huellspalte(Vereinbarungstext.spalteVereinbarung,
                                ordnen: KeyPathComparator(\.titel, comparator: .localizedStandard),
                                text: { $0.titel }) { z in Text(z.titel) },
                    Huellspalte(Vereinbarungstext.spalteGueltigBis,
                                ordnen: KeyPathComparator(\.ablauf, comparator: String.StandardComparator.lexical),
                                breite: .fest(110), text: { Tag(iso: $0.ablauf)?.deutsch ?? "—" }) { z in
                        Text(Tag(iso: z.ablauf)?.deutsch ?? "—")
                    },
                    Huellspalte("Stand", ordnen: KeyPathComparator(\.stand), breite: .fest(130),
                                text: { bezug.verzeichnis.gueltigkeit($0.vereinbarung, $0.person.id).beschriftung },
                                bedienbar: true) { z in
                        standmenue(z)
                    },
                ])
                if let z = gewaehlt { leiste(z) }
            }
        }
        .onAppear {
            zeile = startZeile
            fuer = mitglieder.first?.id
            felderLaden()
        }
        // Eine andere Lerngruppe: wie bei den Maßnahmen (W1-01, N7-05).
        .onChange(of: gruppe.id) { _, _ in
            uebernehmen(zeile, ueberAlle: true)
            if fokus == .titel || fokus == .inhalt { fokus = nil }
            fuer = mitglieder.first?.id
            zeile = nil
            felderLaden()
        }
        .onChange(of: zeile) { alt, _ in
            uebernehmen(alt)
            felderLaden()
        }
        .onChange(of: bezug.entwurf) { _, _ in felderLaden() }
        .onChange(of: fokus) { alt, _ in
            if alt == .titel || alt == .inhalt { uebernehmen(zeile) }
        }
    }

    /// Der Stand in der Tabelle als Menü wie unter „Mitteilungen“ und „Ohne Lerngruppe“ (E852) — die Wahl gilt
    /// sofort und wählt die Zeile; abgelaufen „ungültig“ mit der Hilfe „Abgelaufen — gültig bis einschließlich …“ (E808).
    private func standmenue(_ z: Vereinbarungszeile) -> some View {
        let v = z.vereinbarung
        let p = z.person
        return Gueltigkeitsmenue(stand: bezug.verzeichnis.gueltigkeit(v, p.id),
                                 hilfe: Vereinbarungstext.standmenueHilfe(v, p.id, heute: bezug.verzeichnis.heute)) { g in
            zeile = z.id
            gueltigkeitSetzen(v, p, g)
        }
    }

    /// Die Leiste der gewählten Zeile in drei Zeilen (E851): Person, Stand und Inhalt; Titel in voller Breite
    /// mit „gültig bis einschließlich“; darunter rechts die Knöpfe ungekürzt.
    private func leiste(_ z: Vereinbarungszeile) -> some View {
        let v = z.vereinbarung
        let p = z.person
        let stand = bezug.verzeichnis.gueltigkeit(v, p.id)
        let weitere = mitglieder.filter { !v.betroffene.contains($0.id) }
        let alleWeiteren = Self.alleAufzunehmen(mitglieder, v, gruppe: gruppe.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(p.anzeigename).font(.callout.weight(.semibold))
                Picker("Stand", selection: Binding(get: { stand }, set: { neu in gueltigkeitSetzen(v, p, neu) })) {
                    ForEach(Gueltigkeit.allCases, id: \.self) { Text($0.beschriftung).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                // Für alle Betroffenen, keine Notiz je Person (Tabelle 7).
                TextField(Vereinbarungstext.inhalt, text: $inhalt)
                    .focused($fokus, equals: .inhalt)
                    .onSubmit { uebernehmen(z.id) }
            }
            HStack(spacing: 8) {
                TextField("Titel", text: $titel)
                    .focused($fokus, equals: .titel)
                    .onSubmit { uebernehmen(z.id) }
                // Das Kästchen ist ein eigener Schritt (Z-AX3-07); Änderungen am Datum fassen sich in 2 s zusammen.
                Toggle(Vereinbarungstext.gueltigBis, isOn: Binding(get: { !v.frist.isEmpty }, set: { an in
                    ablaufSetzen(v.id, an ? Tag.heute.plus(tage: 28).iso : "", kennung: nil)
                }))
                .toggleStyle(.checkbox)
                .fixedSize()
                Datumsfeld(tag: Binding(get: { Tag(iso: v.frist) ?? .heute }, set: { ablaufSetzen(v.id, $0.iso, kennung: v.id) }))
                    .frame(width: 130)
                    .disabled(v.frist.isEmpty)
                    .accessibilityLabel(Vereinbarungstext.datumBezeichnung)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if !weitere.isEmpty {
                    Menu("Auch für …") {
                        if !alleWeiteren.isEmpty {
                            Button(Vereinbarungstext.auchFuerAlle) {
                                bezug.handgriff(Schrittname.betroffeneAendern, nil) {
                                    Self.alleAufnehmen($0, v.id, alleWeiteren, jetzt: bezug.jetzt)
                                }
                            }
                            Divider()
                        }
                        ForEach(weitere) { w in
                            Button(w.anzeigename) {
                                bezug.handgriff(Schrittname.betroffeneAendern, nil) {
                                    $0.mitBetroffenem(v.id, w.id, true, jetzt: bezug.jetzt)
                                }
                            }
                        }
                    }
                    .fixedSize()
                    .help(Vereinbarungstext.auchFuerHilfe)
                }
                if v.betroffene.count > 1 {
                    Button("Für diese Person entfernen") {
                        bezug.handgriff(Schrittname.betroffeneAendern, nil) { $0.mitBetroffenem(v.id, p.id, false, jetzt: bezug.jetzt) }
                    }
                }
                Button("Löschen …", role: .destructive) { bezug.loeschen(v.id) }
                    .help(Vereinbarungstext.loeschenHilfe)
            }
        }
        .padding(8)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }

    /// Ein Schritt (E751): Wird eine abgelaufene von Hand „gültig“, ist die Gültigkeit bis einschließlich für die ganze
    /// Vereinbarung aufgehoben — der Hinweis nennt alle, für die sie wieder gilt (E815).
    private func gueltigkeitSetzen(_ v: Anliegen, _ p: Lernender, _ neu: Gueltigkeit) {
        var hinweis: String?
        bezug.handgriff(Schrittname.gueltigkeitAendern, "\(v.id)/\(p.id)") { stand in
            let ergebnis = stand.mitGueltigkeit(v.id, p.id, neu, heute: bezug.verzeichnis.heute, jetzt: bezug.jetzt)
            hinweis = ergebnis.hinweis
            return ergebnis.bestand
        }
        if let hinweis { bezug.melden(hinweis) }
    }

    /// Nur das Datum — Titel, Tag und Inhalt aus dem Stand, auf den der Schritt trifft, nicht aus dem gezeichneten
    /// (Z-AX3-08).
    private func ablaufSetzen(_ id: String, _ frist: String, kennung: String?) {
        bezug.handgriff(Schrittname.vereinbarungAendern, kennung) { stand in
            guard let v = stand.anliegen.first(where: { $0.id == id }) else { return stand }
            return stand.mitAnliegen(id, titel: v.titel, datum: v.datum, frist: frist, notiz: v.notiz, jetzt: bezug.jetzt)
        }
    }

    private func anlegen() {
        guard let fuer = Anliegenbezug.fuerGueltig(fuer, mitglieder),
              let id = bezug.anlegen(.vereinbarung, neuerTitel, [fuer], Tag.heute.iso, mitAblauf ? neuerAblauf.iso : "")
        else { return }
        neuerTitel = ""
        zeile = "\(id)/\(fuer)"
    }

    /// Für welche Zeile die Felder geladen sind — nur in sie schreibt `uebernehmen` (BC7b).
    @State private var geladenFuer: String?

    private func felderLaden() {
        let z = gewaehlt
        if fokus != .titel { titel = z?.vereinbarung.titel ?? "" }
        if fokus != .inhalt { inhalt = z?.vereinbarung.notiz ?? "" }
        geladenFuer = z?.id
    }

    /// Titel und Inhalt der Zeile `id`, wie sie in den Feldern stehen — nichts, wenn sie gleich sind; ein Schritt. Gesetzt
    /// wird nur, was in den Feldern anders steht; alles Übrige aus dem Stand, auf den der Schritt trifft (Z-AX3-08). Nur in
    /// die Zeile, für die die Felder geladen sind; `ueberAlle` wie bei den Maßnahmen (BC7b, N7-05).
    private func uebernehmen(_ id: String?, ueberAlle: Bool = false) {
        guard let id, id == geladenFuer,
              let z = zeilen.first(where: { $0.id == id })
                ?? (ueberAlle ? Self.zeilen(bezug.entwurf.lernende, bezug.verzeichnis).first(where: { $0.id == id }) : nil)
        else { return }
        let v = z.vereinbarung
        let getippt = titel.trimmingCharacters(in: .whitespaces).isEmpty ? v.titel : titel
        let titelGeaendert = Lernendenbestand.zeile(getippt, Lernendendatei.maxTitel) != v.titel ? getippt : nil
        let inhaltGeaendert = Lernendenbestand.notiztext(inhalt) != v.notiz ? inhalt : nil
        guard titelGeaendert != nil || inhaltGeaendert != nil else { return }
        bezug.handgriff(Schrittname.vereinbarungAendern, v.id) { stand in
            guard let jetzig = stand.anliegen.first(where: { $0.id == v.id }) else { return stand }
            return stand.mitAnliegen(v.id, titel: titelGeaendert ?? jetzig.titel, datum: jetzig.datum, frist: jetzig.frist,
                                     notiz: inhaltGeaendert ?? jetzig.notiz, jetzt: bezug.jetzt)
        }
    }
}

// ── Maßnahmen und Termine ohne Lerngruppe an der Person (E290) ────────────

/// Was der Bogen anlegt oder ändert: Art, Person und — beim Ändern — das Anliegen.
struct Anliegenvorlage: Identifiable {
    let id = UUID()
    let art: Anliegenart
    let person: Lernender
    var anliegen: Anliegen?
    /// Bei einem Termin, wenn es eine Planung gibt (E293).
    var planung: Terminplanung?
    /// Ein vorgeschlagener Tag statt heute — Prüfstand und Abbild.
    var tag: Tag?
}

/// Was der Bogen eines Termins über die Planung wissen muss (E291, E293).
struct Terminplanung {
    struct Zeile: Identifiable, Hashable {
        let id: String
        let titel: String
    }
    let zeilen: [Zeile]
    /// Vorgeschlagen: die Klassenleitung der Person, sonst „Weiteres“.
    let vorbelegt: String?
    /// Die Zeile des Vorhabens, wenn der Termin schon eines hat.
    let verbunden: String?
    let erster: Tag
    let letzter: Tag

    func enthaelt(_ tag: Tag) -> Bool { tag >= erster && tag <= letzter }
    func titel(_ zeile: String?) -> String { zeilen.first { $0.id == zeile }?.titel ?? "—" }
}

/// Unter „Alle Lernenden“ an der gewählten Person: ihre Maßnahmen und
/// Termine ohne Lerngruppe mit Stand — anlegen und ändern im Bogen.
struct Personenanliegen: View {
    let person: Lernender
    let bezug: Anliegenbezug
    /// Die Ordnung der Tabelle — am Blatt gehalten (E362, E364); leer: die Folge wie bisher.
    @Binding var ordnung: [KeyPathComparator<Personenanliegenzeile>]
    /// Den Bogen öffnen — er hängt am Blatt.
    let bogen: @MainActor (Anliegenvorlage) -> Void

    @State private var auswahl: String?

    var body: some View {
        let liste = Massnahmenliste.geordnet(Self.zeilen(person.id, bezug.verzeichnis), ordnung)
        let gewaehlt = liste.first { $0.id == auswahl }?.anliegen
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Ohne Lerngruppe").font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                if let gewaehlt {
                    Button("Ändern …") { bogen(Anliegenvorlage(art: gewaehlt.art, person: person, anliegen: gewaehlt)) }
                        .help(gewaehlt.art == .vereinbarung ? Vereinbarungstext.aendernHilfe : "Titel, Tag und Notiz ändern")
                    Button("Löschen …", role: .destructive) { bezug.loeschen(gewaehlt.id) }
                        .help("Samt Stand löschen — mit Rückfrage")
                }
                Button("Maßnahme …") { bogen(Anliegenvorlage(art: .massnahme, person: person)) }
                    .help("Eine Maßnahme mit Frist für diese Person, ohne Lerngruppe")
                // Zwischen „Maßnahme …“ und „Termin …“ (E741).
                Button(Vereinbarungstext.knopf) { bogen(Anliegenvorlage(art: .vereinbarung, person: person)) }
                    .help(Vereinbarungstext.knopfHilfe)
                Button("Termin …") { bogen(Anliegenvorlage(art: .termin, person: person)) }
                    .help("Einen Termin mit Tag und freier Uhrzeit für diese Person, ohne Lerngruppe")
            }
            if liste.isEmpty {
                Text(Vereinbarungstext.ohneLerngruppeLeer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Huelltabelle(liste, wahl: .eine($auswahl),
                             ordnung: Binding(get: { ordnung }, set: { ordnung = Tabellenordnung.mitVorigem($0, vorher: ordnung) }),
                             spalten: [
                    Huellspalte("Art", ordnen: KeyPathComparator(\.art, comparator: .localizedStandard), breite: .fest(80),
                                text: { $0.art }) { z in Text(z.art) },
                    Huellspalte("Titel", ordnen: KeyPathComparator(\.titel, comparator: .localizedStandard),
                                text: { $0.anliegen.titel }) { z in
                        let a = z.anliegen
                        HStack(spacing: 4) {
                            Text(a.titel)
                            if !a.vorhaben.isEmpty {
                                Image(systemName: Zeichen.kalender)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .help("Steht als Vorhaben in der Planung")
                                    .accessibilityLabel("in der Planung")
                            }
                        }
                    },
                    Huellspalte("Tag", ordnen: KeyPathComparator(\.tag, comparator: String.StandardComparator.lexical),
                                // „gültig bis einschließlich 31.10.2026“ (E807) braucht mehr als die 160 pt eines Termins.
                                breite: .bereich(min: 160, ideal: 230, max: nil),
                                text: { Self.tagtext($0.anliegen) }) { z in Text(Self.tagtext(z.anliegen)) },
                    Huellspalte("Stand", ordnen: KeyPathComparator(\.stand), breite: .fest(130), text: { z in
                        z.anliegen.art == .vereinbarung
                            ? bezug.verzeichnis.gueltigkeit(z.anliegen, person.id).beschriftung
                            : bezug.verzeichnis.stand(z.anliegen.id, person.id).beschriftung(fuer: z.anliegen.art)
                    }, bedienbar: true) { z in
                        let a = z.anliegen
                        let rueck = bezug.verzeichnis.rueckmeldung(a.id, person.id)
                        if a.art == .vereinbarung {
                            // Der Stand einer Vereinbarung (E746, E751) — auch ohne Lerngruppe von Hand zu setzen; das Menü
                            // von AppKit mit Häkchen am geltenden Stand (Z-AX3-10, E813).
                            Gueltigkeitsmenue(stand: bezug.verzeichnis.gueltigkeit(a, person.id),
                                              hilfe: Vereinbarungstext.standmenueHilfe(a, person.id,
                                                                                       heute: bezug.verzeichnis.heute)) { g in
                                auswahl = a.id
                                var hinweis: String?
                                bezug.handgriff(Schrittname.gueltigkeitAendern, "\(a.id)/\(person.id)") { stand in
                                    let ergebnis = stand.mitGueltigkeit(a.id, person.id, g, heute: bezug.verzeichnis.heute,
                                                                        jetzt: bezug.jetzt)
                                    hinweis = ergebnis.hinweis
                                    return ergebnis.bestand
                                }
                                if let hinweis { bezug.melden(hinweis) }
                            }
                        } else {
                            Standmenue(stand: rueck?.stand ?? .offen, art: a.art) { neu in
                                auswahl = a.id
                                let bisher = rueck?.datum ?? ""
                                bezug.handgriff(Schrittname.ruecklaufEintragen, "\(a.id)/\(person.id)") {
                                    $0.mitRuecklauf(a.id, person.id, stand: neu,
                                                    datum: neu != .offen && bisher.isEmpty ? Tag.heute.iso : bisher,
                                                    notiz: rueck?.notiz ?? "", jetzt: bezug.jetzt)
                                }
                            }
                        }
                    },
                ])
                .frame(height: 110)
            }
        }
        .padding(8)
        .background(.quinary, in: .rect(cornerRadius: 8))
        .onChange(of: person.id) { _, _ in auswahl = nil }
    }

    /// „bis 11.10.2026“ bei einer Maßnahme, „20.10.2026, 07:45 Uhr“ bei einem Termin, „gültig bis einschließlich 31.10.2026“
    /// bei einer Vereinbarung (E807).
    static func tagtext(_ a: Anliegen) -> String {
        switch a.art {
        case .termin: Anliegenbezug.tagtext(a.datum) + (a.uhrzeit.isEmpty ? "" : ", \(a.uhrzeit) Uhr")
        case .vereinbarung: Vereinbarungstext.tag(a)
        default: Tag(iso: a.frist).map { "bis \($0.deutsch)" } ?? "—"
        }
    }
}

/// Der Bogen für eine Maßnahme oder einen Termin ohne Lerngruppe — am Blatt
/// „Lernende“. Geschrieben wird erst mit „Übernehmen“ des Blatts.
struct AnliegenBogen: View {
    /// Der Fuß, wenn der Termin ein Vorhaben trägt oder tragen soll (R-01, E874): was das Vorhaben trägt.
    nonisolated static let terminFuss = "Das Vorhaben trägt Titel, Tag und Uhrzeit, aber keine Personen — ein Name im "
        + "Titel steht damit auch in der Planung und in der Web App. Beide Seiten bleiben synchron."

    let vorlage: Anliegenvorlage
    /// Titel, Tag (die Frist bei der Maßnahme, bei der Vereinbarung der letzte gültige Tag — `nil` ohne), Uhrzeit, Notiz
    /// (der Inhalt der Vereinbarung) und die Zeile für ein neues Vorhaben (oder `nil`) — `false`: Nichts geschah.
    let fertig: @MainActor (String, Tag?, String, String, String?) -> Bool

    @Environment(\.dismiss) private var schliessen
    @State private var titel = ""
    @State private var tag = Tag.heute
    @State private var uhrzeit = ""
    @State private var notiz = ""
    /// „In der Planung eintragen“ — von Hand gewählt; `nil`: Es folgt dem
    /// Vorschlag (neuer Termin, Zeile vorbelegt, Tag in der Planung).
    @State private var eintragenGewaehlt: Bool?
    @State private var zeile: String?
    /// Nur bei einer Vereinbarung (E741, E807): „Gültig bis einschließlich“ ist freiwillig.
    @State private var mitAblauf = false

    private var vereinbarung: Bool { vorlage.art == .vereinbarung }

    private var eintragen: Bool {
        if let eintragenGewaehlt { return eintragenGewaehlt }
        guard let planung = vorlage.planung, vorlage.anliegen == nil, planung.verbunden == nil else { return false }
        return planung.vorbelegt != nil && planung.enthaelt(tag)
    }

    private var termin: Bool { vorlage.art == .termin }
    private var uhrzeitLesbar: Bool { Lernendenbestand.uhrzeit(uhrzeit) != nil }
    /// Ein Termin mit Vorhaben braucht einen Tag in der Planung.
    private var tagInDerPlanung: Bool {
        guard let planung = vorlage.planung, planung.verbunden != nil || eintragen else { return true }
        return planung.enthaelt(tag)
    }
    private var bereit: Bool {
        !titel.trimmingCharacters(in: .whitespaces).isEmpty && uhrzeitLesbar && tagInDerPlanung
            && (!eintragen || zeile != nil)
    }

    private var ueberschrift: String {
        if vereinbarung { return vorlage.anliegen == nil ? Vereinbarungstext.neue : Vereinbarungstext.titelAendern }
        return switch (termin, vorlage.anliegen == nil) {
        case (true, true): "Neuer Termin"
        case (true, false): "Termin ändern"
        case (false, true): "Neue Maßnahme"
        case (false, false): "Maßnahme ändern"
        }
    }

    var body: some View {
        // Der Bogen liegt auf dem Blatt „Lernende“ und zeigt dessen Zeile (E490).
        Dialograhmen(titel: ueberschrift, unterzeile: vorlage.person.anzeigename + " · ohne Lerngruppe",
                     breite: 520, hoehe: vorlage.planung == nil ? 460 : 660, meldungsblatt: .lernende) {
            // Der Rahmen legt die Abschnitte in seine gruppierte Form — keine zweite hier.
            Section("Titel") {
                TextField("Titel", text: $titel, prompt: Text(termin ? "etwa Elterngespräch"
                                                              : vereinbarung ? Vereinbarungstext.platzhalter : "etwa Heft nachreichen"))
                    .labelsHidden()
            }
            if vereinbarung {
                // Das Datum freiwillig, gesperrt bis angekreuzt — in der Zeile des Kästchens (Tabelle 8, E807, Z-AX3-09).
                Section {
                    HStack(spacing: 8) {
                        Toggle(Vereinbarungstext.gueltigBisBogen, isOn: $mitAblauf)
                            .toggleStyle(.checkbox)
                        Spacer(minLength: 0)
                        Datumsfeld(tag: $tag)
                            .disabled(!mitAblauf)
                            .accessibilityLabel(Vereinbarungstext.datumBezeichnung)
                    }
                } footer: {
                    Text(Vereinbarungstext.fuss).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    LabeledContent(termin ? "Tag" : "Frist") {
                        Datumsfeld(tag: $tag)
                    }
                    if termin {
                        LabeledContent("Uhrzeit") {
                            TextField("Uhrzeit", text: $uhrzeit, prompt: Text("hh:mm"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                } footer: {
                    if termin && !uhrzeitLesbar {
                        Text("Die Uhrzeit bitte als hh:mm, etwa 07:45 — oder leer lassen.")
                            .foregroundStyle(.orange)
                    } else if termin {
                        Text("Die Uhrzeit ist freiwillig. Der Stand: offen, stattgefunden oder abgesagt.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Der Stand: offen, erfüllt oder nicht erfüllt.")
                            .foregroundStyle(.secondary)
                    }
                }
                if termin, let planung = vorlage.planung {
                    Section {
                        if let verbunden = planung.verbunden {
                            LabeledContent("Zeile") { Text(planung.titel(verbunden)) }
                        } else {
                            Toggle("In der Planung eintragen", isOn: Binding(
                                get: { eintragen }, set: { eintragenGewaehlt = $0 }))
                            if eintragen {
                                Picker("Zeile", selection: $zeile) {
                                    Text("—").tag(String?.none)
                                    ForEach(planung.zeilen) { Text($0.titel).tag(Optional($0.id)) }
                                }
                            }
                        }
                    } header: {
                        Text("In der Planung")
                    } footer: {
                        if !tagInDerPlanung {
                            Text("Der Tag liegt außerhalb der Planung (\(planung.erster.deutsch) bis \(planung.letzter.deutsch)).")
                                .foregroundStyle(.orange)
                        } else if planung.verbunden != nil || eintragen {
                            Text(Self.terminFuss)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(vereinbarung ? Vereinbarungstext.inhalt : "Notiz") {
                TextField(vereinbarung ? Vereinbarungstext.inhalt : "Notiz", text: $notiz, prompt: Text("freiwillig"),
                          axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...5)
            }
        } fuss: {
            Fussluecke()
            Button("Abbrechen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            Button(vorlage.anliegen == nil ? "Anlegen" : "Übernehmen") {
                if fertig(titel, vereinbarung && !mitAblauf ? nil : tag, uhrzeit, notiz, eintragen ? zeile : nil) {
                    schliessen()
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!bereit)
        }
        .onAppear {
            if let a = vorlage.anliegen {
                titel = a.titel
                tag = Tag(iso: termin ? a.datum : a.frist) ?? (vereinbarung ? Tag.heute.plus(tage: 28) : .heute)
                uhrzeit = a.uhrzeit
                notiz = a.notiz
                mitAblauf = !a.frist.isEmpty
            } else {
                tag = termin ? .heute : Tag.heute.plus(tage: vereinbarung ? 28 : 7)
            }
            if let vorschlag = vorlage.tag, vorlage.anliegen == nil { tag = vorschlag }
            // Vorgeschlagen ist die Zeile immer; eingeschaltet folgt der Schalter dem Vorschlag (E291).
            if termin, let planung = vorlage.planung, planung.verbunden == nil {
                zeile = planung.vorbelegt
                // Ein Wunsch aus dieser Sitzung des Blatts steht wieder da (W3-03).
                if let wunsch = vorlage.anliegen?.wunschzeile, !wunsch.isEmpty {
                    zeile = wunsch
                    eintragenGewaehlt = true
                }
            }
        }
    }
}
