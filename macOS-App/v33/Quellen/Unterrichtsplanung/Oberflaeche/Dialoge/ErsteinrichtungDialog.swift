// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Die zwei Fragen beim ersten Start, beide freiwillig. Zuerst:
/// Soll die Planung verschlüsselt werden? Wer will, richtet sie gleich hier
/// ein — in den zwei Schritten aus „Einstellungen → Verschlüsselung“ —, wer
/// nicht, überspringt. Danach: Soll die App beim Beenden zusätzlich eine
/// Kopie ablegen? Sie ist die Datei, die die Ansichtsfassung fürs iPad liest.
/// Gefragt wird genau einmal; „Überspringen“ und „Später“ zählen als Antwort.
///
/// Dazu der Hinweis zur Datenverwaltung: Die Kopie gibt es nur
/// verschlüsselt, mit der Wahl des Ordners wird die Verschlüsselung
/// eingerichtet, falls die erste Frage sie nicht schon gebracht hat. Das
/// gehört gesagt, bevor die ersten Daten hineingehen.
struct ErsteinrichtungDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @State private var passphrase = ""
    @State private var wiederholung = ""
    @State private var verwahrt = false
    @State private var fehler: String?
    @State private var hinweis: String?
    /// Ob das Blatt mit der Verschlüsselungsfrage begann — sonst zählt die
    /// Unterzeile keine „Frage 2 von 2“.
    @State private var zweiFragen = true

    var body: some View {
        Dialograhmen(titel: titel, unterzeile: unterzeile,
                     breite: 640, hoehe: 680, beimSchliessen: zurueck) {
            switch speicher.ersteinrichtungsschritt {
            case .verschluesselung:
                verschluesselungsfrage
            case .passphrase:
                Passphrasenwahl(passphrase: $passphrase, wiederholung: $wiederholung,
                                mitEinleitung: false)
            case .blatt(let schluessel):
                Wiederherstellungsschritt(schluessel: schluessel, verwahrt: $verwahrt)
            case .sicherung:
                sicherungsfrage
            }
            if let fehler {
                Section {
                    Label(fehler, systemImage: Zeichen.warnung)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } fuss: {
            fuss
        }
        .onAppear { zweiFragen = speicher.ersteinrichtungsschritt != .sicherung }
    }

    private var titel: String {
        switch speicher.ersteinrichtungsschritt {
        case .verschluesselung, .passphrase, .blatt: "Verschlüsselung"
        case .sicherung: "Sicherungskopie beim Beenden"
        }
    }

    private var unterzeile: String {
        let freiwillig = "freiwillig, einmalig — später jederzeit unter „Einstellungen“"
        return switch speicher.ersteinrichtungsschritt {
        case .verschluesselung: "Ersteinrichtung, Frage 1 von 2 — " + freiwillig
        case .passphrase: "Ersteinrichtung — Schritt 1 von 2: eine Passphrase wählen"
        case .blatt: "Ersteinrichtung — Schritt 2 von 2: den Wiederherstellungsschlüssel verwahren"
        case .sicherung: zweiFragen
            ? "Ersteinrichtung, Frage 2 von 2 — " + freiwillig
            : "Ersteinrichtung — eine Frage, " + freiwillig
        }
    }

    // ── Frage 1: die Verschlüsselung ──────────────────────────────────────

    @ViewBuilder
    private var verschluesselungsfrage: some View {
        Section {
            Text("Die Planung wird laufend auf diesem Rechner gesichert — im Klartext, "
                 + "solange die Verschlüsselung aus ist; FileVault schützt sie unabhängig "
                 + "davon. Eingeschaltet versiegelt ein zufälliger Datenschlüssel die Ablage, "
                 + "jede Kopie und jeden Export mit AES-256.")
            Text("Geöffnet wird die Planung auf diesem Mac mit Touch ID oder dem "
                 + "Anmeldepasswort; die Passphrase öffnet sie überall — in der Ansicht "
                 + "fürs iPad, auf einem neuen Rechner, aus einer exportierten Datei. Für "
                 + "den Notfall gibt es einen gedruckten Wiederherstellungsschlüssel.")
        } header: {
            Text("Worum es geht")
        }

        Section {
            Text("Jetzt einrichten heißt zwei kurze Schritte: eine Passphrase wählen, den "
                 + "Wiederherstellungsschlüssel verwahren. Überspringen heißt: Die Planung "
                 + "bleibt im Klartext, bis die Verschlüsselung unter „Einstellungen“ "
                 + "eingeschaltet wird.")
            Text("Die Sicherungskopie beim Beenden — die nächste Frage — gibt es nur "
                 + "verschlüsselt: Wer sie wählt, richtet die Verschlüsselung spätestens "
                 + "damit ein.")
        } header: {
            Text("Das ist die Frage")
        } footer: {
            Text("Eingeschaltet ist erst nach dem bestätigten Wiederherstellungsblatt; bis "
                 + "dahin ist nichts geschehen. Der Rückweg bleibt offen: „Verschlüsselung "
                 + "aufheben“ unter „Einstellungen“.")
        }
    }

    // ── Frage 2: die Sicherungskopie ──────────────────────────────────────

    @ViewBuilder
    private var sicherungsfrage: some View {
        Section {
            Text("Die Planung wird laufend auf diesem Rechner gesichert. Daran ändert "
                 + "diese Frage nichts, und dafür ist nichts einzustellen.")
        } header: {
            Text("Das läuft ohnehin")
        }

        Section {
            Text("Zusätzlich kann die App bei jedem Beenden eine Kopie der Planung in "
                 + "einen Ordner deiner Wahl legen — immer unter demselben Namen, immer "
                 + "die vorige überschreibend.")
            Text("Liegt dieser Ordner in iCloud Drive, lässt sich die Planung unterwegs "
                 + "ansehen: Die Ansichtsfassung unter 3ducation.org/upapp/ öffnet die "
                 + "Datei auf dem iPad.")
            Text("Dort lassen sich Vorhaben abhaken und kommentieren — beides holt diese "
                 + "App beim nächsten Start von selbst zurück. Die Planung selbst (Titel, "
                 + "Wochen, Klassen/Kurse, Termine) bleibt dem Mac vorbehalten.")
            if let hinweis {
                Label(hinweis, systemImage: Zeichen.warnung)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Das ist die Frage")
        } footer: {
            Text("Gelesen wird im Ordner nur die Statusdatei der Ansicht, aufgeräumt wird "
                 + "dort nie. Gleich nach der Wahl schreibt die App einmal hin — dann steht "
                 + "sofort fest, dass es klappt. Die verbindliche Sicherung bleibt der Export "
                 + "als JSON-Datei (⌘S).")
        }

        // Wortgleich mit dem Beipackzettel des DMG (bauen.sh) —
        // solange die Verschlüsselung aus ist; danach bleibt, was noch gilt.
        Section {
            Label {
                if speicher.verschluesselt {
                    Text("Die Verschlüsselung ist eingeschaltet: Die Kopie wird nur versiegelt "
                         + "geschrieben, die Ansicht fürs iPad öffnet sie mit der Passphrase. "
                         + "Schnappschüsse und Sicherungen des Systems, die vor dem Einschalten "
                         + "entstanden sind, bleiben davon unberührt.")
                } else {
                    Text(Planungsspeicher.datenschutzhinweis)
                }
            } icon: {
                Image(systemName: Zeichen.schloss)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Das ist zu bedenken")
        }
    }

    // ── Fuß ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private var fuss: some View {
        switch speicher.ersteinrichtungsschritt {
        case .verschluesselung:
            Button("Überspringen") { speicher.ersteinrichtungUeberspringen() }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button("Verschlüsselung einrichten …") { speicher.ersteinrichtungEinrichten() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        case .passphrase:
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button("Weiter") { weiter() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!Passphrasenwahl.vollstaendig(passphrase, wiederholung))
        case .blatt:
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button("Verschlüsselung einschalten") { speicher.ersteinrichtungEinschalten() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!verwahrt)
        case .sicherung:
            Button("Später") { spaeter() }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button("Ordner wählen …") { waehlen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// ⎋: auf der ersten Frage überspringen, in der Einrichtung zurück zur
    /// Frage, auf der zweiten „Später“ — nie aus der ersten Frage heraus das
    /// ganze Blatt, sonst fiele die zweite Frage unbeantwortet weg.
    private func zurueck() {
        switch speicher.ersteinrichtungsschritt {
        case .verschluesselung: speicher.ersteinrichtungUeberspringen()
        case .passphrase, .blatt: abbrechen()
        case .sicherung: spaeter()
        }
    }

    private func weiter() {
        fehler = nil
        verwahrt = false
        do { try speicher.ersteinrichtungWeiter(passphrase: passphrase) }
        catch { fehler = error.localizedDescription }
    }

    private func abbrechen() {
        fehler = nil
        passphrase = ""
        wiederholung = ""
        verwahrt = false
        speicher.ersteinrichtungAbbrechen()
    }

    private func spaeter() {
        speicher.ersteinrichtungBeantwortet()
        schliessen()
    }

    /// Geschlossen wird erst, wenn die Kopie wirklich liegt — sonst verschwände
    /// mit dem Dialog die Gelegenheit, einen anderen Ordner zu wählen.
    private func waehlen() {
        speicher.ersteinrichtungBeantwortet()
        hinweis = nil
        if speicher.autoexportOrdnerWaehlen() { schliessen(); return }
        // Leer heißt: abgebrochen.
        guard !speicher.autoexportOrdner.isEmpty else { return }
        hinweis = "In diesen Ordner ließ sich nicht schreiben — bitte einen anderen wählen."
    }
}
