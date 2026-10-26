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

/// Das Menü der drei Stände an der Stelle des Klicks.
@MainActor
enum Standwahl {
    static func zeigen(_ stand: Rueckmeldestand, _ art: Anliegenart, _ waehlen: @escaping @MainActor (Rueckmeldestand) -> Void) {
        guard let ereignis = NSApp.currentEvent, let fenster = ereignis.window, let inhalt = fenster.contentView else { return }
        let ziel = Ziel(waehlen)
        let menue = NSMenu()
        menue.autoenablesItems = false
        for s in Rueckmeldestand.allCases {
            let eintrag = NSMenuItem(title: s.beschriftung(fuer: art), action: #selector(Ziel.gewaehlt(_:)), keyEquivalent: "")
            eintrag.target = ziel
            eintrag.representedObject = s.rawValue
            eintrag.state = s == stand ? .on : .off
            eintrag.image = NSImage(systemSymbolName: Anliegenbezug.zeichen(s), accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(hierarchicalColor: farbe(s)))
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
        let waehlen: @MainActor (Rueckmeldestand) -> Void
        init(_ waehlen: @escaping @MainActor (Rueckmeldestand) -> Void) { self.waehlen = waehlen }

        @objc func gewaehlt(_ eintrag: NSMenuItem) {
            guard let roh = eintrag.representedObject as? String, let stand = Rueckmeldestand(rawValue: roh) else { return }
            waehlen(stand)
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
                Button {
                    anlegen()
                } label: {
                    Label("Anlegen", systemImage: Zeichen.plus)
                }
                .disabled(neuerTitel.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Eine Mitteilung an alle Mitglieder dieser Lerngruppe anlegen, mit dem heutigen Tag (⏎)")
                Spacer(minLength: 0)
            }

            if mitteilungen.isEmpty {
                Text("Noch keine Mitteilung an diese Lerngruppe. Eine neue betrifft alle ihre Mitglieder; "
                     + "je Person lässt sich dann der Rücklauf eintragen — erledigt oder abgelehnt, mit Tag und Notiz.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Table(bezug.personen(gruppe), selection: $person) {
                    TableColumn("Name") { p in
                        Text(p.anzeigename).foregroundStyle(p.archiviert.isEmpty ? .primary : .secondary)
                    }
                    .width(min: 140, ideal: 180)
                    TableColumnForEach(mitteilungen) { m in
                        TableColumn(spaltentitel(m)) { p in zelle(m, p) }
                            .width(min: 90, ideal: 120)
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

    private func spaltentitel(_ m: Anliegen) -> String {
        Tag(iso: m.datum).map { "\(m.titel) · \($0.kurz)" } ?? m.titel
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
                    ForEach(mitteilungen) { Text(spaltentitel($0)).tag(Optional($0.id)) }
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

/// Eine Zeile: eine Maßnahme für eine Person — der Stand gilt je Person.
private struct Massnahmenzeile: Identifiable {
    let massnahme: Anliegen
    let person: Lernender
    var id: String { "\(massnahme.id)/\(person.id)" }
}

struct Massnahmenliste: View {
    let gruppe: Lerngruppe
    let bezug: Anliegenbezug
    var startZeile: String?

    @State private var zeile: String?
    @State private var neuerTitel = ""
    @State private var fuer: String?
    @State private var neueFrist = Tag.heute.plus(tage: 7)
    @State private var titel = ""
    @State private var notiz = ""
    @FocusState private var fokus: Feld?

    private enum Feld: Hashable { case neu, titel, notiz }

    private var mitglieder: [Lernender] { bezug.personen(gruppe) }

    private var zeilen: [Massnahmenzeile] {
        let personen = Dictionary(uniqueKeysWithValues: mitglieder.map { ($0.id, $0) })
        return bezug.verzeichnis.massnahmen(fuer: Set(personen.keys)).flatMap { m in
            m.betroffene.compactMap { personen[$0] }.map { Massnahmenzeile(massnahme: m, person: $0) }
        }
    }

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
                Button {
                    anlegen()
                } label: {
                    Label("Anlegen", systemImage: Zeichen.plus)
                }
                .disabled(neuerTitel.trimmingCharacters(in: .whitespaces).isEmpty || fuer == nil)
                .help("Eine Maßnahme mit Frist für die gewählte Person anlegen (⏎)")
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
                Table(zeilen, selection: $zeile) {
                    TableColumn("Person") { z in Text(z.person.anzeigename) }
                    TableColumn("Maßnahme") { z in Text(z.massnahme.titel) }
                    TableColumn("Frist") { z in fristtext(z) }
                        .width(110)
                    TableColumn("Stand") { z in
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
    /// Den Bogen öffnen — er hängt am Blatt.
    let bogen: @MainActor (Anliegenvorlage) -> Void

    @State private var auswahl: String?

    var body: some View {
        let liste = bezug.verzeichnis.anliegenOhneGruppe(von: person.id)
        let gewaehlt = liste.first { $0.id == auswahl }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Ohne Lerngruppe").font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                if let gewaehlt {
                    Button("Ändern …") { bogen(Anliegenvorlage(art: gewaehlt.art, person: person, anliegen: gewaehlt)) }
                        .help("Titel, Tag und Notiz ändern")
                    Button("Löschen …", role: .destructive) { bezug.loeschen(gewaehlt.id) }
                        .help("Samt Stand löschen — mit Rückfrage")
                }
                Button("Maßnahme …") { bogen(Anliegenvorlage(art: .massnahme, person: person)) }
                    .help("Eine Maßnahme mit Frist für diese Person, ohne Lerngruppe")
                Button("Termin …") { bogen(Anliegenvorlage(art: .termin, person: person)) }
                    .help("Einen Termin mit Tag und freier Uhrzeit für diese Person, ohne Lerngruppe")
            }
            if liste.isEmpty {
                Text("Keine Maßnahme und kein Termin ohne Lerngruppe.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Table(liste, selection: $auswahl) {
                    TableColumn("Art") { a in Text(a.art.titel) }
                        .width(80)
                    TableColumn("Titel") { a in
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
                    TableColumn("Tag") { a in Text(Self.tagtext(a)) }
                        .width(160)
                    TableColumn("Stand") { a in
                        let rueck = bezug.verzeichnis.rueckmeldung(a.id, person.id)
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
                    .width(130)
                }
                .frame(height: 110)
            }
        }
        .padding(8)
        .background(.quinary, in: .rect(cornerRadius: 8))
        .onChange(of: person.id) { _, _ in auswahl = nil }
    }

    /// „bis 11.10.2026“ bei einer Maßnahme, „20.10.2026, 07:45 Uhr“ bei einem Termin.
    static func tagtext(_ a: Anliegen) -> String {
        switch a.art {
        case .termin: Anliegenbezug.tagtext(a.datum) + (a.uhrzeit.isEmpty ? "" : ", \(a.uhrzeit) Uhr")
        default: Tag(iso: a.frist).map { "bis \($0.deutsch)" } ?? "—"
        }
    }
}

/// Der Bogen für eine Maßnahme oder einen Termin ohne Lerngruppe — am Blatt
/// „Lernende“. Geschrieben wird erst mit „Übernehmen“ des Blatts.
struct AnliegenBogen: View {
    let vorlage: Anliegenvorlage
    /// Titel, Tag (die Frist bei der Maßnahme), Uhrzeit, Notiz und die Zeile
    /// für ein neues Vorhaben (oder `nil`) — `false`: nichts geschah.
    let fertig: @MainActor (String, Tag, String, String, String?) -> Bool

    @Environment(\.dismiss) private var schliessen
    @State private var titel = ""
    @State private var tag = Tag.heute
    @State private var uhrzeit = ""
    @State private var notiz = ""
    /// „In der Planung eintragen“ — von Hand gewählt; `nil`: Es folgt dem
    /// Vorschlag (neuer Termin, Zeile vorbelegt, Tag in der Planung).
    @State private var eintragenGewaehlt: Bool?
    @State private var zeile: String?

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
        switch (termin, vorlage.anliegen == nil) {
        case (true, true): "Neuer Termin"
        case (true, false): "Termin ändern"
        case (false, true): "Neue Maßnahme"
        case (false, false): "Maßnahme ändern"
        }
    }

    var body: some View {
        Dialograhmen(titel: ueberschrift, unterzeile: vorlage.person.anzeigename + " · ohne Lerngruppe",
                     breite: 520, hoehe: vorlage.planung == nil ? 460 : 660) {
            // Der Rahmen legt die Abschnitte in seine gruppierte Form — keine zweite hier.
            Section("Titel") {
                TextField("Titel", text: $titel, prompt: Text(termin ? "etwa Elterngespräch" : "etwa Heft nachreichen"))
                    .labelsHidden()
            }
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
                        Text("Das Vorhaben trägt Titel, Tag und Uhrzeit, keinen Namen; beide Seiten bleiben synchron.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Notiz") {
                TextField("Notiz", text: $notiz, prompt: Text("freiwillig"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...5)
            }
        } fuss: {
            Spacer(minLength: 0)
            Button("Abbrechen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            Button(vorlage.anliegen == nil ? "Anlegen" : "Übernehmen") {
                if fertig(titel, tag, uhrzeit, notiz, eintragen ? zeile : nil) { schliessen() }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!bereit)
        }
        .onAppear {
            if let a = vorlage.anliegen {
                titel = a.titel
                tag = Tag(iso: termin ? a.datum : a.frist) ?? .heute
                uhrzeit = a.uhrzeit
                notiz = a.notiz
            } else {
                tag = termin ? .heute : Tag.heute.plus(tage: 7)
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
