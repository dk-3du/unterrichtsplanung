// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

// ── Rückmeldungen und Anliegen im Blatt „Lernende“ (E272) ────────────────
// Die Rücklaufliste einer Lerngruppe — Mitteilungen als Spalten, je Person ein
// Stand mit Tag und Notiz — und ihre Maßnahmen mit Frist je Person. Beide
// ändern nur den Entwurf des Blatts, über dessen einen Weg (`handgriff`).

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
}

// ── Hilfetexte an Knöpfen, auch gesperrt (v86, AX1: E761, G2-06, Z-AW5bN-06) ─

/// Die Hilfetexte nach E761 — an einer Stelle, damit die Suite sie prüft: am Bogen „Rückmeldungsliste“, gesperrt mit
/// eigenen Texten; „Anlegen“ (neue Mitteilung) und „Zeilen wählen …“ behalten ihren Wortlaut und zeigen ihn auch gesperrt.
enum Knopfhilfe {
    static let alleWaehlen = "Alle Mitteilungen der Lerngruppe wählen"
    static let auswahlAufheben = "Keine Mitteilung wählen"
    static let mitteilungAnlegen = "Eine Mitteilung an alle Mitglieder dieser Lerngruppe anlegen, mit dem heutigen Tag (⏎)"
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

// ── Die Rücklaufliste ─────────────────────────────────────────────────────

struct Ruecklaufliste: View {
    let gruppe: Lerngruppe
    let bezug: Anliegenbezug
    @Binding var person: String?
    /// Die Mitteilung, die beim Erscheinen gewählt ist.
    var startAnliegen: String?
    /// Die Ordnung nach „Name“ — am Blatt gehalten (E362, E364).
    @Binding var ordnung: [KeyPathComparator<Lernender>]
    /// „Rückmeldungsliste …“: der Bogen für diese Gruppe (E401) — am Blatt, das ihn trägt.
    let listeOeffnen: () -> Void

    /// Die Mitteilung, deren Rücklauf die Leiste unten bearbeitet.
    @State private var aktiv: String?
    @State private var neuerTitel = ""
    @State private var titel = ""
    @State private var notiz = ""
    /// Wozu die Felder geladen sind — dorthin wird geschrieben, auch wenn
    /// Mitteilung und Person zugleich wechseln (ein Klick in eine Zelle).
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Neue Mitteilung", text: $neuerTitel)
                    .focused($fokus, equals: .neu)
                    .onSubmit { anlegen() }
                    .frame(maxWidth: 360)
                let ohneTitel = neuerTitel.trimmingCharacters(in: .whitespaces).isEmpty
                Button {
                    anlegen()
                } label: {
                    Label("Anlegen", systemImage: Zeichen.plus)
                }
                .disabled(ohneTitel)
                // Gesperrt sichtbar wie H1 (E761, Z-AW5bN-06).
                .hilfe(Knopfhilfe.mitteilungAnlegen, gesperrt: ohneTitel)
                Spacer(minLength: 0)
                // Rechts in der Zeile der neuen Mitteilung, nur in diesem Teil (E633).
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

            if mitteilungen.isEmpty {
                Text("Noch keine Mitteilung an diese Lerngruppe. Eine neue betrifft alle ihre Mitglieder; "
                     + "je Person lässt sich dann der Rücklauf eintragen — erledigt oder abgelehnt, mit Tag und Notiz.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Table(Tabellenordnung.geordnet(bezug.personen(gruppe), nach: ordnung), selection: $person,
                      sortOrder: Binding(get: { ordnung }, set: { ordnung = Tabellenordnung.mitVorigem($0, vorher: ordnung) })) {
                    TableColumn(Ordnungskopf.text("Name", vorn: Lernendenblatt.vorn(ordnung, \.self)),
                                value: \.self, comparator: Namensfolge()) { p in
                        Text(p.anzeigename).foregroundStyle(p.archiviert.isEmpty ? .primary : .secondary)
                    }
                    .width(min: 140, ideal: 180)
                    TableColumnForEach(mitteilungen) { m in
                        // Fest breit wie die Stand-Spalten der Maßnahmen: jede gleich, jede trägt „abgelehnt“ (E641).
                        TableColumn(Self.kopftitel(m)) { p in zelle(m, p) }
                            .width(130)
                    }
                }
                if let m = aktive {
                    mitteilungsleiste(m)
                    if let id = person, let p = bezug.verzeichnis.person(id) {
                        ruecklaufleiste(m, p)
                    }
                }
            }
        }
        .onAppear {
            aktiv = startAnliegen.flatMap { id in mitteilungen.first { $0.id == id }?.id } ?? mitteilungen.last?.id
            felderLaden()
        }
        .onChange(of: aktiv) { _, _ in
            titelUebernehmen()
            notizUebernehmen()
            felderLaden()
        }
        .onChange(of: person) { _, _ in
            notizUebernehmen()
            felderLaden()
        }
        .onChange(of: bezug.entwurf) { _, _ in
            if aktiv == nil || aktive == nil { aktiv = mitteilungen.last?.id }
            felderLaden()
        }
        .onChange(of: fokus) { alt, _ in
            if alt == .titel { titelUebernehmen() }
            if alt == .notiz { notizUebernehmen() }
        }
    }

    /// „Wandertag · 01.09.2026“ — Titel · Tag mit Jahr, für die Wahl unter der Tabelle und die Zeile im Bogen
    /// „Rückmeldungsliste“ (E775); ohne Tag nur der Titel.
    nonisolated static func wahltitel(_ m: Anliegen) -> String {
        Tag(iso: m.datum).map { "\(m.titel) · \($0.deutsch)" } ?? m.titel
    }

    /// Der Kopf einer Spalte: der Tag vorn, ohne Jahr, dann der Titel — in der festen Breite wird der Titel gekürzt, nicht der
    /// Tag (E739). Nur hier; sonst überall „Titel · Tag“ mit Jahr (E775, `wahltitel`).
    nonisolated static func kopftitel(_ m: Anliegen) -> String {
        Tag(iso: m.datum).map { "\($0.kurz) · \(m.titel)" } ?? m.titel
    }

    @ViewBuilder
    private func zelle(_ m: Anliegen, _ p: Lernender) -> some View {
        if m.betroffene.contains(p.id) {
            let rueck = bezug.verzeichnis.rueckmeldung(m.id, p.id)
            Standmenue(stand: rueck?.stand ?? .offen, art: .mitteilung) { neu in
                // Erst das Ausstehende, dann die Leiste auf diese Zelle (E280). Gehört
                // die getippte Notiz zu eben dieser Zelle, kommt sie mit.
                let paar = Paar(anliegen: m.id, person: p.id)
                let neueNotiz = notizFuer == paar ? notiz : (rueck?.notiz ?? "")
                if notizFuer != paar { notizUebernehmen() }
                titelUebernehmen()
                aktiv = m.id
                person = p.id
                eintragen(m, p, stand: neu, datum: tagNachStand(neu, rueck), notiz: neueNotiz)
            }
        } else {
            Text("—").foregroundStyle(.tertiary).help("Nicht betroffen")
                .accessibilityLabel("nicht betroffen")
        }
    }

    /// Die gewählte Mitteilung: wählen, Zahl der Rückläufe, löschen — darunter Titel und Tag.
    private func mitteilungsleiste(_ m: Anliegen) -> some View {
        let zurueck = m.betroffene.filter { bezug.verzeichnis.stand(m.id, $0) != .offen }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("Mitteilung", selection: $aktiv) {
                    ForEach(mitteilungen) { Text(Self.wahltitel($0)).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .frame(maxWidth: 300, alignment: .leading)
                .help("Die Mitteilung, deren Rücklauf unten eingetragen wird")
                Text("\(zurueck) von \(m.betroffene.count) zurück")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer(minLength: 0)
                Button("Löschen …", role: .destructive) { bezug.loeschen(m.id) }
                    .fixedSize()
                    .help("Die Mitteilung samt ihren Rückläufen löschen — mit Rückfrage")
            }
            HStack(spacing: 8) {
                TextField("Titel", text: $titel)
                    .focused($fokus, equals: .titel)
                    .onSubmit { titelUebernehmen() }
                Datumsfeld(tag: Binding(
                    get: { Tag(iso: m.datum) ?? .heute },
                    set: { tag in
                        bezug.handgriff(Schrittname.mitteilungAendern, m.id) {
                            $0.mitAnliegen(m.id, titel: m.titel, datum: tag.iso, frist: m.frist, notiz: m.notiz,
                                           jetzt: bezug.jetzt)
                        }
                    }))
                    .frame(width: 130)
                    .accessibilityLabel("Tag der Mitteilung")
            }
        }
    }

    /// Der Rücklauf der gewählten Person: Stand und Tag — darunter die Notiz.
    private func ruecklaufleiste(_ m: Anliegen, _ p: Lernender) -> some View {
        let betroffen = m.betroffene.contains(p.id)
        let rueck = bezug.verzeichnis.rueckmeldung(m.id, p.id)
        let stand = rueck?.stand ?? .offen
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(p.anzeigename)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if betroffen {
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
                            .accessibilityLabel("Tag des Rücklaufs")
                    }
                    Spacer(minLength: 0)
                } else {
                    Text("ist von dieser Mitteilung nicht betroffen").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("In die Mitteilung aufnehmen") {
                        bezug.handgriff(Schrittname.betroffeneAendern, nil) { $0.mitBetroffenem(m.id, p.id, true, jetzt: bezug.jetzt) }
                    }
                    .fixedSize()
                }
            }
            if betroffen {
                HStack(spacing: 8) {
                    TextField("Notiz", text: $notiz)
                        .focused($fokus, equals: .notiz)
                        .onSubmit { notizUebernehmen() }
                    Button("Aus der Mitteilung nehmen") {
                        bezug.handgriff(Schrittname.betroffeneAendern, nil) { $0.mitBetroffenem(m.id, p.id, false, jetzt: bezug.jetzt) }
                    }
                    .fixedSize()
                    .help("Die Mitteilung betrifft diese Person nicht — ihr Rücklauf geht mit")
                }
            }
        }
        .padding(8)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }

    /// Ein Stand ohne Tag bekommt den heutigen; „offen“ behält, was da ist.
    private func tagNachStand(_ stand: Rueckmeldestand, _ rueck: Rueckmeldung?) -> String {
        let bisher = rueck?.datum ?? ""
        return stand != .offen && bisher.isEmpty ? Tag.heute.iso : bisher
    }

    private func eintragen(_ m: Anliegen, _ p: Lernender, stand: Rueckmeldestand, datum: String, notiz: String) {
        bezug.handgriff(Schrittname.ruecklaufEintragen, "\(m.id)/\(p.id)") {
            $0.mitRuecklauf(m.id, p.id, stand: stand, datum: datum, notiz: notiz, jetzt: bezug.jetzt)
        }
    }

    private func anlegen() {
        let personen = bezug.verzeichnis.mitglieder(gruppe.id).map(\.id)
        guard let id = bezug.anlegen(.mitteilung, neuerTitel, personen, Tag.heute.iso, "") else { return }
        neuerTitel = ""
        aktiv = id
    }

    private func felderLaden() {
        if fokus != .titel {
            titel = aktive?.titel ?? ""
            titelFuer = aktive?.id
        }
        if fokus != .notiz {
            let paar = aktiv.flatMap { a in person.map { Paar(anliegen: a, person: $0) } }
            notiz = paar.flatMap { bezug.verzeichnis.rueckmeldung($0.anliegen, $0.person)?.notiz } ?? ""
            notizFuer = paar
        }
    }

    private func titelUebernehmen() {
        guard let id = titelFuer, let m = mitteilungen.first(where: { $0.id == id }),
              !titel.trimmingCharacters(in: .whitespaces).isEmpty,
              Lernendenbestand.zeile(titel, Lernendendatei.maxTitel) != m.titel else { return }
        // Kein Nachladen hier: Der Stand dieser Ansicht ist noch der alte, und
        // eine ausstehende Notiz ginge verloren — nachgeladen wird mit dem neuen.
        bezug.handgriff(Schrittname.mitteilungAendern, id) {
            $0.mitAnliegen(id, titel: titel, datum: m.datum, frist: m.frist, notiz: m.notiz, jetzt: bezug.jetzt)
        }
    }

    private func notizUebernehmen() {
        guard let paar = notizFuer, let m = mitteilungen.first(where: { $0.id == paar.anliegen }),
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
/// leer heißt: die Folge wie bisher. Die Rücklaufliste ordnet nur nach „Name“ (E362).
struct Anliegenordnung: Equatable {
    var ruecklauf = [KeyPathComparator(\Lernender.self, comparator: Namensfolge())]
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
            HStack(spacing: 8) {
                TextField("Neue Maßnahme", text: $neuerTitel)
                    .focused($fokus, equals: .neu)
                    .onSubmit { anlegen() }
                    .frame(maxWidth: 280)
                Picker("für", selection: $fuer) {
                    Text("—").tag(String?.none)
                    ForEach(mitglieder) { Text($0.anzeigename).tag(Optional($0.id)) }
                }
                .fixedSize()
                Text("Frist").foregroundStyle(.secondary)
                Datumsfeld(tag: $neueFrist)
                    .frame(width: 130)
                    .accessibilityLabel("Frist der neuen Maßnahme")
                let gesperrt = neuerTitel.trimmingCharacters(in: .whitespaces).isEmpty || fuer == nil
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

            if zeilen.isEmpty {
                Text("Noch keine Maßnahme für Mitglieder dieser Lerngruppe. Eine Maßnahme betrifft eine oder wenige "
                     + "Personen und trägt eine Frist; ihr Stand ist offen, erfüllt oder nicht erfüllt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Table(Self.geordnet(zeilen, ordnung), selection: $zeile,
                      sortOrder: Binding(get: { ordnung }, set: { ordnung = Tabellenordnung.mitVorigem($0, vorher: ordnung) })) {
                    TableColumn(Ordnungskopf.text("Person", vorn: Lernendenblatt.vorn(ordnung, \.person)), value: \.person,
                                comparator: Namensfolge()) { z in Text(z.name) }
                    TableColumn(Ordnungskopf.text("Maßnahme", vorn: Lernendenblatt.vorn(ordnung, \.titel)), value: \.titel,
                                comparator: .localizedStandard) { z in Text(z.titel) }
                    TableColumn(Ordnungskopf.text("Frist", vorn: Lernendenblatt.vorn(ordnung, \.frist)), value: \.frist,
                                comparator: String.StandardComparator.lexical) { z in fristtext(z) }
                        .width(110)
                    TableColumn(Ordnungskopf.text("Stand", vorn: Lernendenblatt.vorn(ordnung, \.stand)), value: \.stand) { z in
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
                    }
                    .width(130)
                }
                if let z = gewaehlt { leiste(z) }
            }
        }
        .onAppear {
            zeile = startZeile
            fuer = mitglieder.first?.id
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

    /// Die Frist — orange, wenn sie verstrichen und die Maßnahme noch offen ist.
    private func fristtext(_ z: Massnahmenzeile) -> some View {
        let frist = Tag(iso: z.massnahme.frist)
        let verstrichen = frist.map { $0 < .heute } == true
            && bezug.verzeichnis.stand(z.massnahme.id, z.person.id) == .offen
        return Text(frist?.deutsch ?? "—")
            .foregroundStyle(verstrichen ? Color.orange : Color.primary)
            .help(verstrichen ? "Die Frist ist verstrichen" : "")
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
        guard let fuer, let id = bezug.anlegen(.massnahme, neuerTitel, [fuer], Tag.heute.iso, neueFrist.iso) else { return }
        neuerTitel = ""
        zeile = "\(id)/\(fuer)"
    }

    private func felderLaden() {
        let z = gewaehlt
        if fokus != .titel { titel = z?.massnahme.titel ?? "" }
        if fokus != .notiz { notiz = z.flatMap { bezug.verzeichnis.rueckmeldung($0.massnahme.id, $0.person.id)?.notiz } ?? "" }
    }

    /// Titel und Notiz der Zeile `id`, wie sie in den Feldern stehen — nichts, wenn sie gleich sind.
    private func uebernehmen(_ id: String?) {
        guard let id, let z = zeilen.first(where: { $0.id == id }) else { return }
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
    // VoiceOver am Datum (E819): in der Anlegezeile und in der Leiste.
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
            HStack(spacing: 8) {
                TextField(Vereinbarungstext.neue, text: $neuerTitel)
                    .focused($fokus, equals: .neu)
                    .onSubmit { anlegen() }
                    .frame(maxWidth: 260)
                Picker("für", selection: $fuer) {
                    Text("—").tag(String?.none)
                    ForEach(mitglieder) { Text($0.anzeigename).tag(Optional($0.id)) }
                }
                .fixedSize()
                Toggle(Vereinbarungstext.gueltigBis, isOn: $mitAblauf)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Datumsfeld(tag: $neuerAblauf)
                    .frame(width: 130)
                    .disabled(!mitAblauf)
                    .accessibilityLabel(Vereinbarungstext.datumNeuBezeichnung)
                let gesperrt = neuerTitel.trimmingCharacters(in: .whitespaces).isEmpty || fuer == nil
                Button {
                    anlegen()
                } label: {
                    Label("Anlegen", systemImage: Zeichen.plus)
                }
                .disabled(gesperrt)
                .hilfe(Vereinbarungstext.anlegenHilfe, gesperrt: gesperrt)
                Spacer(minLength: 0)
            }

            if zeilen.isEmpty {
                Text(Vereinbarungstext.leer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Table(Massnahmenliste.geordnet(zeilen, ordnung), selection: $zeile,
                      sortOrder: Binding(get: { ordnung }, set: { ordnung = Tabellenordnung.mitVorigem($0, vorher: ordnung) })) {
                    TableColumn(Ordnungskopf.text("Person", vorn: Lernendenblatt.vorn(ordnung, \.person)), value: \.person,
                                comparator: Namensfolge()) { z in Text(z.name) }
                    TableColumn(Ordnungskopf.text(Vereinbarungstext.spalteVereinbarung, vorn: Lernendenblatt.vorn(ordnung, \.titel)),
                                value: \.titel, comparator: .localizedStandard) { z in Text(z.titel) }
                    TableColumn(Ordnungskopf.text(Vereinbarungstext.spalteGueltigBis, vorn: Lernendenblatt.vorn(ordnung, \.ablauf)),
                                value: \.ablauf, comparator: String.StandardComparator.lexical) { z in
                        Text(Tag(iso: z.ablauf)?.deutsch ?? "—")
                    }
                    .width(110)
                    TableColumn(Ordnungskopf.text("Stand", vorn: Lernendenblatt.vorn(ordnung, \.stand)), value: \.stand) { z in
                        standmenue(z)
                    }
                    .width(130)
                }
                if let z = gewaehlt { leiste(z) }
            }
        }
        .onAppear {
            zeile = startZeile
            fuer = mitglieder.first?.id
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
        guard let fuer, let id = bezug.anlegen(.vereinbarung, neuerTitel, [fuer], Tag.heute.iso,
                                                mitAblauf ? neuerAblauf.iso : "") else { return }
        neuerTitel = ""
        zeile = "\(id)/\(fuer)"
    }

    private func felderLaden() {
        let z = gewaehlt
        if fokus != .titel { titel = z?.vereinbarung.titel ?? "" }
        if fokus != .inhalt { inhalt = z?.vereinbarung.notiz ?? "" }
    }

    /// Titel und Inhalt der Zeile `id`, wie sie in den Feldern stehen — nichts, wenn sie gleich sind; ein Schritt. Gesetzt
    /// wird nur, was in den Feldern anders steht; alles Übrige aus dem Stand, auf den der Schritt trifft (Z-AX3-08).
    private func uebernehmen(_ id: String?) {
        guard let id, let z = zeilen.first(where: { $0.id == id }) else { return }
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
                Table(liste, selection: $auswahl,
                      sortOrder: Binding(get: { ordnung }, set: { ordnung = Tabellenordnung.mitVorigem($0, vorher: ordnung) })) {
                    TableColumn(Ordnungskopf.text("Art", vorn: Lernendenblatt.vorn(ordnung, \.art)), value: \.art,
                                comparator: .localizedStandard) { z in Text(z.art) }
                        .width(80)
                    TableColumn(Ordnungskopf.text("Titel", vorn: Lernendenblatt.vorn(ordnung, \.titel)), value: \.titel,
                                comparator: .localizedStandard) { z in
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
                    }
                    TableColumn(Ordnungskopf.text("Tag", vorn: Lernendenblatt.vorn(ordnung, \.tag)), value: \.tag,
                                comparator: String.StandardComparator.lexical) { z in Text(Self.tagtext(z.anliegen)) }
                        // „gültig bis einschließlich 31.10.2026“ (E807) braucht mehr als die 160 pt eines Termins.
                        .width(min: 160, ideal: 230)
                    TableColumn(Ordnungskopf.text("Stand", vorn: Lernendenblatt.vorn(ordnung, \.stand)), value: \.stand) { z in
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
                    }
                    .width(130)
                }
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
