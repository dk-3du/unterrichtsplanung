// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Der einmalige Hinweis gegen den Rückweg auf eine Vorversion (v80, E286, E297; seit 2.5.0 E971–E973, E981) — Wortlaut
/// des Nutzers, je Weg. Keine Anleitung zum Rückweg (E971). Gelesen ist gelesen: Knopf und ⎋ merken ihn.
struct RueckwegHinweisDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    static let titel = "Bitte bei Version 2.5.0 oder höher bleiben"
    static let unterzeile = "Ein Hinweis zur neuen Fassung — einmalig"
    static let knopf = "Verstanden"

    /// Die Absätze je Weg (E981): (a) nach einem Update von vor 2.0.0 und nach einer Neuinstallation, (b) nach einem Update
    /// von einer Fassung seit 2.0.0.
    static func absaetze(_ weg: Rueckwegweg) -> [String] {
        let bitte = "Bitte deshalb keine ältere Version mehr installieren; neue Fassungen kommen über „Nach Updates suchen“."
        switch weg {
        case .vorZweiNull:
            return [
                "Seit 2.0.0 verfügt die App über eine Lernendenverwaltung. Daran geknüpft sind zahlreiche neue Funktionen.",
                "Eine ältere Version bis einschließlich 1.9.8 verfügt über keine Lernendenverwaltung und lässt daher Eingaben, "
                    + "welche bei Verwendung von Version 2.0.0 oder höher gemacht wurden, beim nächsten Sichern fallen.",
                "Seit 2.5.0 speichert die App die Lernendendaten und die Sitzpläne in einer neuen Fassung, die ältere "
                    + "Versionen nicht lesen können.",
                bitte,
            ]
        case .seitZweiNull:
            return [
                "Seit 2.5.0 gibt es keine Obergrenze mehr für die Zahl der Personen je Lerngruppe, Anliegen und Termin und "
                    + "für die Tische je Sitzplan.",
                "Dafür speichert die App die Lernendendaten und die Sitzpläne in einer neuen Fassung, die ältere Versionen "
                    + "nicht lesen können.",
                bitte,
            ]
        }
    }

    var body: some View {
        Dialograhmen(titel: Self.titel, unterzeile: Self.unterzeile, breite: 640, hoehe: 480,
                     beimSchliessen: gelesen) {
            Section {
                ForEach(Self.absaetze(speicher.rueckwegHinweisWeg), id: \.self) { absatz in
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
