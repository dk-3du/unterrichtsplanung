// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Eine Erläuterung im Kasten eines gruppierten Formulars, als eigene Zeile (v95, E1122). Nutzer,
/// 07.11.2026: „Achte darauf, dass die Erläuterungen stets im grau hinterlegten Feld stehen, nicht darunter.“
///
/// Die Zeile sieht aus wie die native Unterzeile, also wie der zweite `Text` im Etikett einer Zeile (etwa „Wochentag“):
/// - gleiche Schrift und Größe (`.subheadline`; an der Vorlage gemessen 11 pt bei 14 pt Zeilenabstand);
/// - gleiche Farbe (`.secondary`);
/// - linke Kante wie der Titel der Zeile, umbrechend, nie abgeschnitten.
///
/// Wofür: Eine Unterzeile, wo der Text einer Zeile mit Etikett gilt; diese eigene Zeile, wo er mehreren Zeilen oder dem
/// ganzen Kasten gilt oder kommt und geht. Braucht nichts außer SwiftUI — jede Fassung und jedes Blatt kann die Datei
/// unverändert übernehmen.
///
/// **Warnung** (`warnung: true`): die eine Erscheinung jeder Warnzeile im Kasten (E1122) — das Warnzeichen
/// `exclamationmark.triangle` (entspricht `Zeichen.warnung`; hier als Literal, damit die Datei allein steht) vor dem
/// Text, beides orange, Schrift wie oben (`.subheadline`), umbrechend; die linke Kante ist die der Textzeile, das Zeichen
/// steht davor.
struct Erlaeuterung: View {
    let text: String
    var warnung = false

    init(_ text: String, warnung: Bool = false) {
        self.text = text
        self.warnung = warnung
    }

    var body: some View {
        Group {
            if warnung {
                Label(text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.orange)
            } else {
                Text(text)
                    .foregroundStyle(HierarchicalShapeStyle.secondary)
            }
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
