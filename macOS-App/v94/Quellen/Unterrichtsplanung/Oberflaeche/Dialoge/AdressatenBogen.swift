// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// ── „Einzelne …“: an wen eine neue Mitteilung geht (v91, BC4, V4) ─────────
// Ein Bogen am Blatt „Lernende“ wie „Rückmeldungsliste“: die aktiven Mitglieder der Lerngruppe zum Ankreuzen, „Alle
// wählen“ und „Auswahl aufheben“, „‹n› von ‹m› gewählt“. „Übernehmen“ setzt die Adressaten der Anlegezeile — angelegt wird
// erst dort, mit „Anlegen“. Kein Popover: SwiftUI-Inhalt in `NSPopover` stürzt unter Liquid Glass in eine Rekursion.

/// Der Bogen für eine Lerngruppe, solange er steht.
struct Adressatenvorlage: Identifiable {
    let id = UUID()
    let gruppe: Lerngruppe
    /// Die aktiven Mitglieder, in der Folge der Liste — archivierte stehen nicht zur Wahl (E252).
    let mitglieder: [Lernender]
    /// Was beim Öffnen gewählt ist: die Auswahl von vorhin, im Betrieb anfangs nichts; Prüfstand und Abbild geben vor.
    var vorgewaehlt: Set<String> = []
}

/// Was der Bogen rechnet — rein, damit die Suite es prüft (W2-07). `kennungen` sind die aktiven Mitglieder in der Folge der
/// Liste.
enum Adressatenwahl {
    /// Beim Öffnen gewählt: die Auswahl von vorhin, soweit sie unter den aktiven steht.
    static func anfang(_ vorgewaehlt: Set<String>, _ kennungen: [String]) -> Set<String> {
        vorgewaehlt.intersection(kennungen)
    }
    /// „‹n› von ‹m› gewählt“ zählt nur aktive.
    static func zaehler(_ gewaehlt: Set<String>, _ kennungen: [String]) -> Int { kennungen.filter(gewaehlt.contains).count }
    /// „Übernehmen“ und „Auswahl aufheben“ gesperrt, solange kein aktives Mitglied gewählt ist.
    static func leer(_ gewaehlt: Set<String>, _ kennungen: [String]) -> Bool { !kennungen.contains(where: gewaehlt.contains) }
    /// Was „Übernehmen“ setzt: die Gewählten unter den aktiven.
    static func ergebnis(_ gewaehlt: Set<String>, _ kennungen: [String]) -> Set<String> { gewaehlt.intersection(kennungen) }
}

struct AdressatenBogen: View {
    let vorlage: Adressatenvorlage
    /// „Übernehmen“: die Gewählten, nie leer.
    let fertig: @MainActor (Set<String>) -> Void

    @Environment(\.dismiss) private var schliessen
    @State private var gewaehlt: Set<String> = []

    private var kennungen: [String] { vorlage.mitglieder.map(\.id) }

    var body: some View {
        // Der Bogen liegt auf dem Blatt „Lernende“ und zeigt dessen Zeile (E490).
        Dialograhmen(titel: Mitteilungstext.bogenTitel, unterzeile: vorlage.gruppe.beschriftung, breite: 520, hoehe: 600,
                     meldungsblatt: .lernende) {
            // Der Rahmen legt die Abschnitte in seine gruppierte Form — keine zweite hier.
            Section {
                HStack(spacing: 8) {
                    Text(Mitteilungstext.gewaehlt(Adressatenwahl.zaehler(gewaehlt, kennungen), von: kennungen.count))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    // Die Hilfen nach E761 — gesperrt über die durchsichtige Fläche wie H1 (W2-03).
                    let alle = kennungen.allSatisfy(gewaehlt.contains)
                    Button(Mitteilungstext.bogenAlle) { gewaehlt = Set(kennungen) }
                        .disabled(alle)
                        .hilfe(Mitteilungstext.bogenAlleHilfe, gesperrt: alle)
                    let keine = Adressatenwahl.leer(gewaehlt, kennungen)
                    Button(Mitteilungstext.bogenKeine) { gewaehlt = [] }
                        .disabled(keine)
                        .hilfe(Mitteilungstext.bogenKeineHilfe, gesperrt: keine)
                }
                ForEach(vorlage.mitglieder) { p in
                    Toggle(p.anzeigename, isOn: Binding(
                        get: { gewaehlt.contains(p.id) },
                        set: { an in
                            if an { gewaehlt.insert(p.id) } else { gewaehlt.remove(p.id) }
                        }))
                        .toggleStyle(.checkbox)
                }
            } header: {
                Text(Mitteilungstext.bogenAbschnitt)
            } footer: {
                Text(Mitteilungstext.bogenFuss)
            }
        } fuss: {
            Fussluecke()
            Button("Abbrechen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            let leer = Adressatenwahl.leer(gewaehlt, kennungen)
            Button("Übernehmen") {
                fertig(Adressatenwahl.ergebnis(gewaehlt, kennungen))
                schliessen()
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(leer)
            .hilfe(leer ? Mitteilungstext.bogenUebernehmenGesperrt : Mitteilungstext.bogenUebernehmenHilfe, gesperrt: leer)
        }
        .onAppear { gewaehlt = Adressatenwahl.anfang(vorlage.vorgewaehlt, kennungen) }
    }
}
