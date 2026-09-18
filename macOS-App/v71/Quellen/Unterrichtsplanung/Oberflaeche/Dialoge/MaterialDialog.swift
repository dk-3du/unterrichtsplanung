// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// ── Die Frage ─────────────────────────────────────────────────────────────

/// Die Materialliste von 3ducation.org anbieten? Steht in der Ersteinrichtung
/// als vierte Frage, für eine Planung, die es vor dieser Frage schon gab,
/// einmal als eigenes Blatt — und im Material-Blatt selbst, solange keine
/// Erlaubnis vorliegt (E177). Was dabei übertragen wird, steht hier wörtlich,
/// nicht als Verweis: Ohne das lässt sich nicht einwilligen.
struct Materialfrage: View {
    var body: some View {
        Section {
            Text(Materialien.worumEsGeht)
        } header: {
            Text("Worum es geht")
        }

        Section {
            Label {
                Text(Materialien.datenschutzhinweis)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: Zeichen.hinweis)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Was dabei übertragen wird")
        } footer: {
            Text("Jederzeit änderbar unter „\(Materialien.einstellungsort)“.")
        }
    }
}

/// Das eigene Blatt für Planungen, die vor der vierten Frage entstanden sind:
/// dieselbe Frage, einmal, beim ersten Öffnen dieser Fassung.
struct MaterialNachfrageDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        Dialograhmen(titel: Materialien.titel,
                     unterzeile: "Eine Frage, freiwillig — später jederzeit unter „Einstellungen“",
                     breite: 640, hoehe: 520, beimSchliessen: { antworten(false) }) {
            Materialfrage()
        } fuss: {
            Button("Nicht jetzt") { antworten(false) }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button("Einschalten") { antworten(true) }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Beantwortet ist beantwortet — auch „Nicht jetzt“; die Frage kommt nicht wieder.
    private func antworten(_ erlaubt: Bool) {
        speicher.materialienErlauben(erlaubt)
        schliessen()
    }
}

// ── Das Blatt ─────────────────────────────────────────────────────────────

/// Was das Material-Blatt gerade zeigt.
enum Materialblattstand: Equatable, Sendable {
    /// Keine Erlaubnis — das Blatt stellt die Frage (E177).
    case frage
    case laedt
    case geladen(Materialkatalog)
    case nichtErreichbar
    case unlesbar(String)
}

/// Die Kacheln der Website im Vorhaben-Dialog (E179, E181): je Kategorie eine
/// Überschrift, die Kacheln in zwei Spalten, ein Suchfeld wie auf der
/// Startseite. Ein Klick hinterlegt das Material als Link am Vorhaben, ein
/// zweiter nimmt ihn wieder heraus; „Fertig“ schließt. Geladen wird beim
/// Öffnen, nur mit Erlaubnis — ohne sie steht hier die Frage, und vor
/// „Einschalten“ geht nichts ins Netz. Ein Bogen am Vorhaben-Blatt.
struct MaterialDialog: View {
    @Binding var entwurf: VorhabenEntwurf
    /// Für Abbilder und Prüfstände: ein Stand, der nicht geladen wird.
    var vorgabe: Materialblattstand?

    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @State private var stand: Materialblattstand = .laedt
    @State private var suche = ""

    var body: some View {
        if stand == .frage {
            Dialograhmen(titel: Materialien.titel,
                         unterzeile: "Eine Frage, freiwillig — später jederzeit unter „Einstellungen“",
                         breite: 640, hoehe: 520, beimSchliessen: { schliessen() }) {
                Materialfrage()
            } fuss: {
                Button("Nicht jetzt") {
                    speicher.materialienErlauben(false)
                    schliessen()
                }
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button("Einschalten") {
                    speicher.materialienErlauben(true)
                    // Der Wechsel auf das breite Blatt startet dessen `.task`, der
                    // lädt — eine zweite Aufgabe hier wäre eine zweite Anfrage.
                    stand = .laedt
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
            .task { await laden() }
        } else {
            Dialograhmen(titel: Materialien.titel,
                         unterzeile: "Ein Klick hinterlegt das Material als Link am Vorhaben",
                         // So breit wie das Vorhaben-Blatt, an dem der Bogen hängt.
                         breite: 720, hoehe: 720, beimSchliessen: { schliessen() },
                         freierKoerper: true) {
                koerper
            } fuss: {
                Text(zaehler).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Fertig") { schliessen() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .task { await laden() }
        }
    }

    // ── Laden ─────────────────────────────────────────────────────────────

    /// Die Vorgabe geht vor; sonst der Koordinator — ohne Erlaubnis die Frage.
    private func laden() async {
        if let vorgabe {
            stand = vorgabe
            return
        }
        guard stand == .laedt else { return }
        switch await speicher.materialkatalogLaden() {
        case .geladen(let katalog): stand = .geladen(katalog)
        case .nichtErreichbar: stand = .nichtErreichbar
        case .unlesbar(let grund): stand = .unlesbar(grund)
        case .keineErlaubnis: stand = .frage
        }
    }

    // ── Körper ────────────────────────────────────────────────────────────

    @ViewBuilder
    private var koerper: some View {
        switch stand {
        case .frage:
            EmptyView()
        case .laedt:
            hinweis("Die Materialliste wird von 3ducation.org geladen …", symbol: nil)
        case .nichtErreichbar:
            hinweis("3ducation.org ist gerade nicht erreichbar — bitte später noch einmal versuchen. "
                    + "Links lassen sich weiterhin von Hand hinterlegen.", symbol: Zeichen.warnung,
                    erneut: true)
        case .unlesbar:
            hinweis("Die Materialliste ließ sich nicht lesen — vermutlich ist die Website gerade im "
                    + "Umbau. Bitte später noch einmal versuchen.", symbol: Zeichen.warnung,
                    erneut: true)
        case .geladen(let katalog):
            liste(katalog)
        }
    }

    private func hinweis(_ text: String, symbol: String?, erneut: Bool = false) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if let symbol {
                Image(systemName: symbol).font(.largeTitle).foregroundStyle(.orange)
            } else {
                ProgressView()
            }
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)
                .fixedSize(horizontal: false, vertical: true)
            if erneut {
                Button("Erneut laden") {
                    stand = .laedt
                    Task { await laden() }
                }
            }
            Spacer(minLength: 0)
            datenschutz
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private func liste(_ katalog: Materialkatalog) -> some View {
        let kategorien = katalog.passend(suche)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Titel, Beschreibung, Fach, Schlagwort", text: $suche)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Materialliste durchsuchen")
                if !suche.isEmpty {
                    Button { suche = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Suche löschen")
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(Systemfarben.feldflaeche, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Systemfarben.feldkante.opacity(0.55)))
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if kategorien.isEmpty {
                        Text(suche.isEmpty ? "Die Liste ist leer." : "Nichts passt zu „\(suche)“.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                    ForEach(kategorien) { kategorie in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(kategorie.titel).font(.title3.weight(.semibold))
                            if !kategorie.beschreibung.isEmpty {
                                Text(kategorie.beschreibung).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                                      alignment: .leading, spacing: 10) {
                                ForEach(kategorie.kacheln) { kachel in
                                    Materialkachelkarte(kachel: kachel,
                                                        hinterlegt: istHinterlegt(kachel)) {
                                        klick(kachel)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            datenschutz
        }
    }

    private var datenschutz: some View {
        Text(Materialien.datenschutzhinweis)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.top, 8)
    }

    // ── Hinterlegen ───────────────────────────────────────────────────────

    private func istHinterlegt(_ kachel: Materialkachel) -> Bool {
        entwurf.links.contains { $0.adresse == kachel.adresse }
    }

    /// Ein Klick hinterlegt, ein zweiter nimmt zurück (E179).
    private func klick(_ kachel: Materialkachel) {
        if istHinterlegt(kachel) {
            speicher.linkEntfernen(adresse: kachel.adresse, in: &entwurf)
        } else {
            speicher.linkAufnehmen(titel: kachel.titel, adresse: kachel.adresse, in: &entwurf)
        }
    }

    /// Wie viele Kacheln der Liste am Vorhaben hängen.
    private var zaehler: String {
        guard case .geladen(let katalog) = stand else { return "" }
        let zahl = katalog.kategorien.flatMap(\.kacheln).filter(istHinterlegt).count
        switch zahl {
        case 0: return "Noch kein Material hinterlegt."
        case 1: return "1 Material hinterlegt."
        default: return "\(zahl) Materialien hinterlegt."
        }
    }
}

/// Eine Kachel wie auf der Startseite: Titel, Beschreibung, Fach und Lizenz —
/// als Knopf; hinterlegt trägt sie den Haken und den Akzentrahmen.
private struct Materialkachelkarte: View {
    let kachel: Materialkachel
    let hinterlegt: Bool
    let klick: () -> Void

    var body: some View {
        Button(action: klick) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(kachel.titel)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if hinterlegt {
                        Label("Hinterlegt", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .labelStyle(.titleAndIcon)
                    }
                }
                if !kachel.beschreibung.isEmpty {
                    Text(kachel.beschreibung)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    if !kachel.meta.isEmpty { Text(kachel.meta) }
                    if !kachel.meta.isEmpty, !kachel.lizenz.isEmpty { Text("·") }
                    if !kachel.lizenz.isEmpty { Text(kachel.lizenz) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(hinterlegt ? Color.accentColor.opacity(0.12) : Systemfarben.verweiszeile,
                        in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(hinterlegt ? Color.accentColor : Systemfarben.feldkante.opacity(0.6),
                                  lineWidth: hinterlegt ? 1.5 : 1)
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(hinterlegt ? "Hinterlegt — ein Klick nimmt den Link wieder heraus: " + kachel.adresse
                         : "Als Link hinterlegen: " + kachel.adresse)
        .accessibilityLabel(kachel.meta.isEmpty ? kachel.titel : "\(kachel.titel), \(kachel.meta)")
        .accessibilityValue(hinterlegt ? "hinterlegt" : "")
        .accessibilityHint(hinterlegt ? "Nimmt den Link wieder heraus" : "Hinterlegt das Material als Link")
    }
}
