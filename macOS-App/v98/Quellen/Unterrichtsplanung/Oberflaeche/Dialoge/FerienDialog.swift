// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct FerienDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen
    @FocusState private var fokus: String?

    private var planung: Planung? { speicher.planung }

    var body: some View {
        // Maße wie das Blatt „Prüfungen“ (E1152): höchstens 700 hoch; 744 breit wie jedes Blatt mit gruppiertem `Form`
        // (E1156) — die Spalten belegen 674 der 684 pt einer Zeile.
        Dialograhmen(titel: "Ferien und unterrichtsfreie Zeiten",
                     unterzeile: planung?.ferienBilanz().text ?? "—",
                     breite: Formblatt.breite, hoehe: 700) {
            if let planung {
                Section {
                    if planung.ferien.isEmpty {
                        Text("Noch kein Zeitraum eingetragen.").foregroundStyle(.secondary)
                    } else {
                        Ferienspaltenkopf()
                        ForEach(planung.ferien) { zeitraum in
                            Ferienposten(zeitraum: zeitraum, planung: planung, fokus: $fokus)
                        }
                    }

                    Button {
                        if let neu = speicher.ferienHinzufuegen() { fokus = neu }
                    } label: {
                        Label("Zeitraum hinzufügen", systemImage: Zeichen.plus)
                    }
                    // Gilt allen Zeilen: als letzte Zeile im Kasten (E1122).
                    Erlaeuterung("Wochen, die ganz in einen Zeitraum fallen, werden im Raster als "
                                 + "unterrichtsfrei geführt. Trifft ein Zeitraum eine Woche nur teilweise "
                                 + "— etwa wenn die Ferien am Mittwoch enden —, bleibt die Woche "
                                 + "bespielbar und der Kopf weist die Zahl der freien Tage aus. Einzelne "
                                 + "Wochen lassen sich zusätzlich direkt im Spaltenkopf schalten.")
                } header: {
                    Text("Zeiträume")
                }
            }
        } fuss: {
            Spacer(minLength: 0)
            Button("Fertig") { schliessen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Kopf und Zeilen richten sich nach denselben Werten.
enum Ferienspalten {
    static let name: CGFloat = 190
    static let datum: CGFloat = 136
    static let lage: CGFloat = 140
    static let abstand: CGFloat = 10
    static let knopf: CGFloat = 22
    /// Die ganze Zeile: sechs Glieder samt Spacer, fünf Abstände — höchstens `Formblatt.zeile` (R-BG8c-02).
    static let zeile: CGFloat = name + 2 * datum + lage + knopf + 5 * abstand
}

private struct Ferienspaltenkopf: View {
    var body: some View {
        HStack(spacing: Ferienspalten.abstand) {
            Spaltenkopf(titel: "Bezeichnung")
                .frame(width: Ferienspalten.name, alignment: .leading)
            Spaltenkopf(titel: "Von").frame(width: Ferienspalten.datum, alignment: .leading)
            Spaltenkopf(titel: "Bis").frame(width: Ferienspalten.datum, alignment: .leading)
            Spacer(minLength: 0)
            Color.clear.frame(width: Ferienspalten.lage + Ferienspalten.knopf, height: 1)
        }
        .accessibilityHidden(true)
    }
}

struct Ferienposten: View {
    let zeitraum: Ferienzeitraum
    let planung: Planung
    @FocusState.Binding var fokus: String?

    @Environment(Planungsspeicher.self) private var speicher

    @State private var name = ""
    @State private var entpreller = Entpreller()

    var body: some View {
        HStack(spacing: Ferienspalten.abstand) {
            Tabellenfeld(hinweis: "Bezeichnung", text: $name,
                         beimVerlassen: bezeichnungAbschliessen)
                .focused($fokus, equals: zeitraum.id)
                .frame(width: Ferienspalten.name)
                .accessibilityLabel("Bezeichnung des Zeitraums")
                .onChange(of: name) { _, neu in
                    // Nur den Namen setzen — sonst nähme der wartende Auftrag Datumsänderungen zurück.
                    entpreller.nach(300) { speicher.ferienNamenSetzen(id: zeitraum.id, name: neu) }
                }

            // `mitBeginn`/`mitEnde`: Das andere Datum zieht mit (siehe `Zeitspanne`).
            Datumsfeld(tag: Binding(
                get: { zeitraum.von },
                set: { speicher.ferienAendern(zeitraum.mitBeginn($0)) }))
                .frame(width: Ferienspalten.datum)
                .accessibilityLabel("Beginn")

            Datumsfeld(tag: Binding(
                get: { zeitraum.bis },
                set: { speicher.ferienAendern(zeitraum.mitEnde($0)) }))
                .frame(width: Ferienspalten.datum)
                .accessibilityLabel("Ende")

            Spacer(minLength: 0)

            Text(zeitraum.lageText(in: planung))
                .font(.caption)
                .foregroundStyle(zeitraum.ungueltig ? Color.red : Color.secondary)
                .frame(width: Ferienspalten.lage, alignment: .trailing)

            Papierkorbknopf(hilfe: "Zeitraum entfernen", kennzeichnung: "Zeitraum \(zeitraum.name) entfernen") {
                speicher.ferienEntfernen(zeitraum.id)
            }
            .frame(width: Ferienspalten.knopf, alignment: .trailing)
        }
        .onAppear { name = zeitraum.name }
        .onChange(of: zeitraum.name) { _, neu in if neu != name { name = neu } }
    }

    /// Beim Verlassen des Feldes beschneiden und, wenn nichts übrig bleibt, auf
    /// denselben Ersatz setzen, den der Dateileser vergäbe — sonst hieße der
    /// Zeitraum in der Anzeige anders als nach dem nächsten Start.
    private func bezeichnungAbschliessen() {
        let sauber = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = sauber.isEmpty ? "Ferien" : sauber
        entpreller.abbrechen()
        speicher.ferienNamenSetzen(id: zeitraum.id, name: name)
    }
}
