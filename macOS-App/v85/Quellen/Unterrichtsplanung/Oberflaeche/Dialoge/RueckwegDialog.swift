// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Der einmalige Hinweis gegen den Rückweg auf eine Vorversion (v80, E286,
/// E297) — Wortlaut des Nutzers. Gelesen ist gelesen: Knopf und ⎋ merken ihn.
struct RueckwegHinweisDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    static let titel = "Bitte bei Version 2 bleiben"
    static let unterzeile = "Ein Hinweis zur neuen Fassung — einmalig"
    static let absaetze = [
        "Seit 2.0.0 verfügt die App über eine Lernendenverwaltung. Daran geknüpft sind zahlreiche neue Funktionen.",
        "Eine ältere Version bis einschließlich 1.9.8 verfügt über keine Lernendenverwaltung und lässt daher Eingaben, "
            + "welche bei Verwendung von Version 2.0.0 oder höher gemacht wurden, beim nächsten Sichern fallen. Bitte "
            + "deshalb keine ältere Version mehr installieren; neue Fassungen kommen über „Nach Updates suchen“.",
        "Falls eine Rückkehr dennoch notwendig ist, bitte die Lernendendaten vorher exportieren: Ablage → "
            + "„Lernende exportieren …“.",
    ]
    static let knopf = "Verstanden"

    var body: some View {
        Dialograhmen(titel: Self.titel, unterzeile: Self.unterzeile, breite: 640, hoehe: 480,
                     beimSchliessen: gelesen) {
            Section {
                ForEach(Self.absaetze, id: \.self) { absatz in
                    Text(absatz)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } fuss: {
            Spacer(minLength: 0)
            Button(Self.knopf) { gelesen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func gelesen() {
        speicher.rueckwegHinweisGelesen()
        schliessen()
    }
}
