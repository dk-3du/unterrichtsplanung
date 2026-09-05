// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// ── Die Frage ─────────────────────────────────────────────────────────────

/// Beim Öffnen nach Updates suchen? Steht in der Ersteinrichtung als dritte
/// Frage und — für eine Planung, die es vor dieser Frage schon gab — einmal
/// als eigenes Blatt. Was dabei übertragen wird, steht hier wörtlich, nicht
/// als Verweis: Ohne das lässt sich nicht einwilligen.
struct Updatefrage: View {
    var body: some View {
        Section {
            Text("Die App kann beim Öffnen nachsehen, ob im Repository eine neuere Fassung "
                 + "veröffentlicht ist, und dann ein Blatt mit den Neuerungen und dem Weg "
                 + "zur Download-Seite zeigen. Heruntergeladen oder installiert wird nichts "
                 + "von selbst.")
        } header: {
            Text("Worum es geht")
        }

        Section {
            Label {
                Text(Updates.datenschutzhinweis)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: Zeichen.hinweis)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Was dabei übertragen wird")
        } footer: {
            Text("Jederzeit änderbar unter „Einstellungen → Updates“. Von Hand suchen geht "
                 + "immer — über „\(Updates.menuebefehl)“ im Menü „Unterrichtsplanung“; "
                 + "dann fragt die App auf diesen Befehl hin, sonst nie.")
        }
    }
}

/// Das eigene Blatt für Planungen, die vor der dritten Frage entstanden sind:
/// dieselbe Frage, einmal, beim ersten Öffnen dieser Fassung.
struct UpdateNachfrageDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        Dialograhmen(titel: "Updates",
                     unterzeile: "Eine Frage, freiwillig — später jederzeit unter „Einstellungen“",
                     breite: 640, hoehe: 520, beimSchliessen: { antworten(false) }) {
            Updatefrage()
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
        speicher.updatesErlauben(erlaubt)
        schliessen()
    }
}

// ── Das Blatt ─────────────────────────────────────────────────────────────

/// Ein neueres Release liegt vor: Name, Datum, die Notizen aus dem Release und
/// drei Wege — zur Release-Seite, später noch einmal, diese Fassung auslassen.
struct UpdateDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    private var release: Veroeffentlichung? { speicher.update }

    var body: some View {
        Dialograhmen(titel: "Update verfügbar", unterzeile: unterzeile,
                     breite: 640, hoehe: 640, beimSchliessen: spaeter) {
            if let release {
                Section {
                    LabeledContent("Neu", value: release.titel)
                    LabeledContent("Installiert", value: Updates.installierteFassung)
                    if let datum = release.veroeffentlicht {
                        LabeledContent("Veröffentlicht", value: Zeitrechnung.zeitpunktLang(datum))
                    }
                }

                let notizen = release.notizen
                if !notizen.isEmpty {
                    Section {
                        notizentext(notizen)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Text("Was die Fassung bringt")
                    }
                }

                Section {
                    Text("„Zum Download“ öffnet die Release-Seite im Browser; dort liegt das "
                         + "beglaubigte Abbild (DMG). Installiert wird wie beim ersten Mal — das "
                         + "Programmsymbol auf „Applications“ ziehen, die alte Kopie ersetzen. Die "
                         + "Planung bleibt, wo sie ist.")
                } header: {
                    Text("So geht es weiter")
                }
            }
        } fuss: {
            Button("Diese Version überspringen") {
                speicher.updateUeberspringen()
                schliessen()
            }
            Spacer(minLength: 0)
            Button("Später") { spaeter() }
                .keyboardShortcut(.cancelAction)
            Button("Zum Download") {
                speicher.updateSeiteOeffnen()
                schliessen()
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(release?.seite == nil)
        }
    }

    private var unterzeile: String {
        release.map { "\($0.titel) — installiert ist \(Updates.installierteFassung)" } ?? ""
    }

    /// Die Notizen sind Markdown; gesetzt wird nur, was in einer Zeile geht
    /// (Fett, Kursiv, Verweise), die Zeilen bleiben, wie sie sind.
    private func notizentext(_ text: String) -> Text {
        if let gesetzt = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(gesetzt)
        }
        return Text(text)
    }

    /// „Später“ und ⎋: Das Blatt geht zu, die nächste Prüfung zeigt es wieder.
    private func spaeter() {
        speicher.updateSpaeter()
        schliessen()
    }
}
