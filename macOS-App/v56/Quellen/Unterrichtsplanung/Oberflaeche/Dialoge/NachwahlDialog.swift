// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Die Nachwahl nach dem Wechsel ins App Sandbox: Ordner, die die App bisher
/// benutzt hat, einmal neu wählen. Erklärt ohne Fachsprache, warum — und was
/// ohne die Wahl liegen bleibt.
struct NachwahlDialog: View {
    @Environment(Planungsspeicher.self) private var speicher

    var body: some View {
        Dialograhmen(titel: "Zugriff auf deine Ordner",
                     unterzeile: "Einmal nach dem Update — die App merkt sich deine Wahl",
                     breite: 660, hoehe: 600, beimSchliessen: { speicher.nachwahlSpaeter() }) {
            Section {
                Text("Diese Fassung der App darf von sich aus nur noch ihre eigenen Dateien "
                     + "lesen und schreiben. Auf andere Ordner darf sie erst zugreifen, wenn du "
                     + "sie ihr einmal zeigst — das schützt deine Dateien, falls die App je "
                     + "missbraucht würde.")
                Text("Bitte wähle die Ordner, die du bisher verwendet hast, noch einmal aus. "
                     + "Der Dialog zeigt den bisherigen Ordner schon an; „Wählen“ genügt. Auch "
                     + "ein Ordner darüber ist möglich — er gilt dann für alles darin.")
            } header: {
                Text("Warum diese Frage?")
            }

            Section {
                ForEach(speicher.ausstehendeFreigaben) { freigabe in
                    LabeledContent(freigabe.titel) {
                        HStack(spacing: 8) {
                            Text(freigabe.pfad.isEmpty ? "noch keiner gewählt" : freigabe.pfad)
                                .font(.callout.monospaced())
                                .foregroundStyle(freigabe.pfad.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(freigabe.pfad)
                            Button("Wählen …") { speicher.nachwahlWaehlen(freigabe) }
                        }
                    }
                }
            } header: {
                Text("Ordner")
            } footer: {
                Text("Ohne die Wahl bleibt der Ordner liegen: keine Sicherungskopie beim "
                     + "Beenden, Materialien darin lassen sich nicht öffnen. Beim nächsten "
                     + "Start fragt die App noch einmal; einzelne Dateien fragt sie beim Öffnen.")
            }
        } fuss: {
            Button("Später") { speicher.nachwahlSpaeter() }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
        }
    }
}
