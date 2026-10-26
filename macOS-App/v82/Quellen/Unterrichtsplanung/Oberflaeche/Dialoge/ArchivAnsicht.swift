// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// ── Das Archiv im Blatt „Lernende“ (E246, E274, E276) ────────────────────
// Die Vorjahre, schreibgeschützt: Schuljahr wählen, Personen, Lerngruppen und
// Anliegen mit Stand lesen. Ändern lässt es sich nur durch die drei
// Löschungen — sie gelten sofort, nicht erst mit „Übernehmen“. Die Planung
// eines Jahres lässt sich wie mit ⌘S als Datei sichern; die Web App zeigt sie.
// Gelesen wird das Archiv erst, wenn diese Ansicht erscheint, und abseits des
// Hauptstrangs.

/// Was die Archivansicht zu einem Schuljahr zeigt.
enum Archivteil: String, CaseIterable, Sendable {
    case personen, lerngruppen, anliegen

    var titel: String {
        switch self {
        case .personen: "Personen"
        case .lerngruppen: "Lerngruppen"
        case .anliegen: "Anliegen"
        }
    }
}

struct ArchivAnsicht: View {
    @Environment(Planungsspeicher.self) private var speicher

    private enum Lage: Equatable {
        case liest
        case gelesen(Archivbestand)
        case nichtLesbar(String)
    }

    @State private var lage: Lage = .liest
    @State private var jahr: String?
    @State private var teil: Archivteil = .personen
    @State private var person: String?
    @State private var anliegen: String?
    @State private var groesse: Int?
    /// Je gewähltem Jahr gebaut, nicht je Auswertung des Körpers.
    @State private var verzeichnis: Lernendenverzeichnis?

    var body: some View {
        Group {
            switch lage {
            case .liest:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Das Archiv wird gelesen …").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .nichtLesbar(let grund):
                Text("Das Archiv lässt sich nicht lesen (\(grund.ohneSchlusspunkt)). Es bleibt unangetastet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .gelesen(let archiv):
                if archiv.jahre.isEmpty {
                    Text("Das Archiv ist leer. Beim Wechsel ins nächste Schuljahr („Neue Planung“) kommt das "
                         + "laufende hierher — samt seiner Planung.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    inhalt(archiv)
                }
            }
        }
        .task { await laden() }
    }

    // ── Lesen und Schreiben ───────────────────────────────────────────────

    private func laden() async {
        let befund = await speicher.lernende.archivLesenAsynchron(stempel: Zeitrechnung.dateistempel())
        switch befund {
        case .nichtLesbar(let grund):
            lage = .nichtLesbar(grund)
        case .gelesen(let archiv, let bilanz, let kopie):
            if bilanz.verlust {
                speicher.melden("Das Archiv wurde beim Lesen bereinigt"
                                + (kopie.map { " — das Original liegt als „\($0)“ neben der Planung." } ?? "."), .warnung)
            }
            uebernehmen(archiv)
        }
        groesse = speicher.lernende.archivGroesse()
    }

    /// Ein Stand des Archivs — gelesen oder nach einer Löschung.
    private func uebernehmen(_ archiv: Archivbestand) {
        lage = .gelesen(archiv)
        let jahre = Self.geordnet(archiv)
        if jahr == nil || !jahre.contains(where: { $0.id == jahr }) { jahr = jahre.first?.id }
        jahrLaden(archiv)
    }

    private func jahrLaden(_ archiv: Archivbestand) {
        let gewaehlt = archiv.jahre.first { $0.id == jahr }
        verzeichnis = gewaehlt?.lernende.map(Lernendenverzeichnis.init)
        if let id = person, verzeichnis?.person(id) == nil { person = nil }
        if let id = anliegen, gewaehlt?.lernende?.anliegen.contains(where: { $0.id == id }) != true { anliegen = nil }
    }

    private func schreiben(_ neu: Archivbestand) {
        guard speicher.archivSchreiben(neu) == nil else { return }
        uebernehmen(neu)
        groesse = speicher.lernende.archivGroesse()
    }

    /// Das jüngste Schuljahr zuerst.
    private static func geordnet(_ archiv: Archivbestand) -> [Archivjahr] {
        archiv.jahre.sorted { $0.schuljahr > $1.schuljahr }
    }

    // ── Ein Schuljahr ─────────────────────────────────────────────────────

    private func inhalt(_ archiv: Archivbestand) -> some View {
        let jahre = Self.geordnet(archiv)
        let gewaehlt = jahre.first { $0.id == jahr } ?? jahre[0]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Schuljahr", selection: $jahr) {
                    ForEach(jahre) { Text($0.schuljahr).tag(Optional($0.id)) }
                }
                .fixedSize()
                Text("archiviert am \(Self.tag(gewaehlt.archiviert)) · Planung „\(gewaehlt.planung.titel)“")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Planung sichern …") { speicher.archivPlanungSichern(gewaehlt) }
                    .fixedSize()
                    .help("Die Planung dieses Schuljahrs als verschlüsselte Datei sichern — wie ⌘S; "
                          + "sie öffnet mit der Passphrase, auch in der Web App")
                Button("Schuljahr löschen …", role: .destructive) {
                    speicher.archivJahrLoeschenFragen(gewaehlt.id, in: archiv) { schreiben($0) }
                }
                .fixedSize()
                .help("Das ganze Schuljahr samt Planung und Lernendendaten endgültig löschen — mit Rückfrage")
            }
            Text(hinweis)
                .font(.caption)
                .foregroundStyle(groesseGross ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let lernende = gewaehlt.lernende, let verzeichnis {
                Picker("Teil des Archivs", selection: $teil) {
                    ForEach(Archivteil.allCases, id: \.self) { Text($0.titel).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                switch teil {
                case .personen: personen(archiv, verzeichnis)
                case .lerngruppen: lerngruppen(lernende, verzeichnis)
                case .anliegen: anliegenliste(archiv, gewaehlt, lernende, verzeichnis)
                }
            } else {
                Text("In diesem Schuljahr gab es keine Lernendendaten — archiviert ist nur die Planung.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .onChange(of: jahr) { _, _ in jahrLaden(archiv) }
    }

    /// ⌫ so, wie die Taste es schickt: U+007F. SwiftUIs `.delete` ist U+0008 und
    /// löste im Blatt nicht aus — gemessen am Paket (AP9).
    static let loeschtaste = KeyEquivalent(Character(UnicodeScalar(0x7F)))

    private var groesseGross: Bool { (groesse ?? 0) >= Archivdatei.hinweisgroesse }

    private var hinweis: String {
        var text = "Schreibgeschützt — ändern lässt sich das Archiv nur durch Löschen: ein Schuljahr, eine Person "
            + "in allen Schuljahren oder ein Anliegen."
        if groesseGross, let groesse {
            text += " Das Archiv ist \(groesse / 1024 / 1024) MB groß; ab \(Archivdatei.hoechstgroesse / 1024 / 1024) MB "
                + "nimmt es kein weiteres Schuljahr auf — ältere Schuljahre lassen sich hier löschen."
        }
        return text
    }

    private static func tag(_ stempel: String) -> String {
        Zeitrechnung.zeitpunkt(aus: stempel).map { Tag($0).deutsch } ?? "—"
    }

    // ── Personen ──────────────────────────────────────────────────────────

    private func personen(_ archiv: Archivbestand, _ verzeichnis: Lernendenverzeichnis) -> some View {
        let liste = verzeichnis.alleMitArchivierten
        return VStack(alignment: .leading, spacing: 8) {
            Table(liste, selection: $person) {
                TableColumn("Nachname", value: \.nachname)
                TableColumn("Vorname", value: \.vorname)
                TableColumn("Lerngruppen") { p in
                    let gruppen = verzeichnis.gruppen(von: p.id)
                    Text(gruppen.isEmpty ? "—" : gruppen.map(\.beschriftung).joined(separator: ", "))
                }
                TableColumn("Angelegt") { p in Text(Self.tag(p.angelegt)) }
                    .width(90)
            }
            if let id = person, let p = verzeichnis.person(id) {
                HStack(spacing: 8) {
                    Text(p.anzeigename).font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("In allen Schuljahren löschen …", role: .destructive) {
                        speicher.archivPersonLoeschenFragen(p.id, in: archiv) { schreiben($0) }
                    }
                    .keyboardShortcut(Self.loeschtaste, modifiers: .command)
                    .help("Die Person in allen archivierten Schuljahren endgültig löschen — das laufende bleibt unberührt (⌘⌫)")
                }
                .padding(8)
                .background(.quinary, in: .rect(cornerRadius: 8))
            }
        }
    }

    // ── Lerngruppen ───────────────────────────────────────────────────────

    private func lerngruppen(_ lernende: Lernendenbestand, _ verzeichnis: Lernendenverzeichnis) -> some View {
        Table(verzeichnis.gruppen(archivierte: true)) {
            TableColumn("Lerngruppe", value: \.name)
            TableColumn("Fach") { g in Text(g.fach.isEmpty ? "—" : g.fach) }
            TableColumn("Art") { g in Text(g.art == .klasse ? "Klasse" : "Kurs") }
                .width(80)
            TableColumn("Mitglieder") { g in Text("\(verzeichnis.mitglieder(g.id, archivierte: true).count)") }
                .width(90)
        }
    }

    // ── Anliegen mit Stand ────────────────────────────────────────────────

    private func anliegenliste(_ archiv: Archivbestand, _ jahr: Archivjahr, _ lernende: Lernendenbestand,
                               _ verzeichnis: Lernendenverzeichnis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if lernende.anliegen.isEmpty {
                Text("In diesem Schuljahr gab es keine Mitteilungen, Maßnahmen oder Termine.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                Table(lernende.anliegen, selection: $anliegen) {
                    TableColumn("Art") { a in Text(a.art.titel) }
                        .width(90)
                    TableColumn("Titel", value: \.titel)
                    TableColumn("Lerngruppe") { a in Text(verzeichnis.gruppe(a.lerngruppe)?.beschriftung ?? "—") }
                    TableColumn("Tag") { a in Text(Anliegenbezug.tagtext(a.art == .massnahme ? a.frist : a.datum)) }
                        .width(90)
                    TableColumn("Stand") { a in Text(standtext(a, verzeichnis)) }
                }
                if let id = anliegen, let a = lernende.anliegen.first(where: { $0.id == id }) {
                    HStack(spacing: 8) {
                        Text(a.titel).font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Löschen …", role: .destructive) {
                            speicher.archivAnliegenLoeschenFragen(a.id, imJahr: jahr.id, in: archiv) { schreiben($0) }
                        }
                        .keyboardShortcut(Self.loeschtaste, modifiers: .command)
                        .help("Das Anliegen samt seinen Rückläufen endgültig aus dem Archiv löschen (⌘⌫)")
                    }
                    .padding(8)
                    .background(.quinary, in: .rect(cornerRadius: 8))
                }
            }
        }
    }

    /// „8 erledigt · 1 abgelehnt · 3 offen“ — bei einer Maßnahme „erfüllt / nicht erfüllt“,
    /// bei einem Termin „stattgefunden / abgesagt“.
    private func standtext(_ a: Anliegen, _ verzeichnis: Lernendenverzeichnis) -> String {
        let staende = a.betroffene.map { verzeichnis.stand(a.id, $0) }
        return Rueckmeldestand.allCases.compactMap { s -> String? in
            let n = staende.filter { $0 == s }.count
            return n == 0 ? nil : "\(n) \(s.beschriftung(fuer: a.art))"
        }.joined(separator: " · ")
    }
}
