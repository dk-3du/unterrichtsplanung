// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// Die zwei Schritte der Einrichtung — dieselben unter „Einstellungen →
// Verschlüsselung“ und in der Ersteinrichtung. Abschnitte einer
// gruppierten Form; den Fuß mit „Weiter“ und „Einschalten“ stellt das Blatt,
// das sie zeigt.

/// Schritt 1: die Passphrase wählen (Einrichtung) oder belegen (Schlüssel
/// erneuern).
struct Passphrasenwahl: View {
    @Binding var passphrase: String
    @Binding var wiederholung: String
    /// Belegen statt wählen: ein Feld, keine Wiederholung, keine Längenzeile.
    var erneuern = false
    /// Der Absatz „Worum es geht“ — die Ersteinrichtung hat ihn schon gesagt.
    var mitEinleitung = true

    /// Ob „Weiter“ freizugeben ist — für den Fuß des Blatts.
    static func vollstaendig(_ passphrase: String, _ wiederholung: String,
                             erneuern: Bool = false) -> Bool {
        passphrase.count >= Tresor.passphraseMindestlaenge
            && (erneuern || passphrase == wiederholung)
    }

    private var langGenug: Bool { passphrase.count >= Tresor.passphraseMindestlaenge }
    private var laengentext: String {
        let zahl = "\(passphrase.count) Zeichen"
        return langGenug ? zahl : zahl + " — mindestens \(Tresor.passphraseMindestlaenge)"
    }

    var body: some View {
        if mitEinleitung {
            Section {
                if erneuern {
                    Text("Ein frischer Datenschlüssel versiegelt Ablage und Nebendateien neu; die "
                         + "Kopie beim Beenden folgt beim nächsten Beenden. Die Passphrase bleibt — "
                         + "sie ist hier zu belegen — und es entsteht ein neues "
                         + "Wiederherstellungsblatt.")
                } else {
                    Text("Ein zufälliger Datenschlüssel versiegelt die Planung mit AES-256. Auf "
                         + "diesem Mac öffnet ihn Touch ID oder das Anmeldepasswort; die Passphrase "
                         + "öffnet ihn überall — in der Ansicht fürs iPad, auf einem neuen Rechner, "
                         + "aus einer exportierten Datei.")
                }
            } header: {
                Text("Worum es geht")
            }
        }

        Section {
            SecureField("Passphrase", text: $passphrase)
                .textContentType(erneuern ? .password : .newPassword)
            if !erneuern {
                SecureField("Passphrase wiederholen", text: $wiederholung)
                    .textContentType(.newPassword)
                LabeledContent("Länge") {
                    Text(laengentext)
                        .foregroundStyle(langGenug ? Color.secondary : Color.orange)
                        .monospacedDigit()
                }
            }
        } header: {
            Text(erneuern ? "Die Passphrase" : "Eine Passphrase wählen")
        } footer: {
            if erneuern {
                Text("Nur wer die Passphrase kennt, darf den Schlüssel erneuern.")
            } else {
                Text("Mindestens \(Tresor.passphraseMindestlaenge) Zeichen, sonst keine Regeln. "
                     + "Ein Satz, den man behält, ist besser als acht Sonderzeichen, die man "
                     + "aufschreibt. Die Härte der Verschlüsselung ist die Härte dieser "
                     + "Passphrase — eine kurze gleicht kein Verfahren aus. FileVault schützt "
                     + "mehr als diese Einstellung; sie ist die Schicht für die Kopie, die den "
                     + "Rechner verlässt.")
            }
        }
    }
}

/// Schritt 2: das Blatt mit dem Wiederherstellungsschlüssel — drucken oder als
/// PDF sichern — und die Bestätigung, die erst scharf schaltet.
struct Wiederherstellungsschritt: View {
    @Environment(Planungsspeicher.self) private var speicher

    let schluessel: String
    var erneuern = false
    @Binding var verwahrt: Bool

    private var planungstitel: String { speicher.planung?.titel ?? "Unterrichtsplanung" }

    var body: some View {
        Section {
            // Nicht markierbar: Die Zwischenablage wandert über den Rechner hinaus
            // (Universal Clipboard); der digitale Weg ist die PDF-Datei.
            Text(schluessel)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .kerning(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            HStack(spacing: 12) {
                Button {
                    Wiederherstellungsblatt.drucken(schluessel: schluessel,
                                                    planungstitel: planungstitel, speicher: speicher)
                } label: {
                    Label("Drucken …", systemImage: Zeichen.drucker)
                }
                Button {
                    Wiederherstellungsblatt.alsPDFSichern(schluessel: schluessel,
                                                          planungstitel: planungstitel,
                                                          speicher: speicher)
                } label: {
                    Label("Als PDF sichern …", systemImage: Zeichen.datei)
                }
            }
        } header: {
            Text("Der Wiederherstellungsschlüssel")
        } footer: {
            Text("Er öffnet die Planung, wenn die Passphrase vergessen ist — die Ablage, die "
                 + "Kopie und jede exportierte Datei. Er wird nirgends gespeichert und nur "
                 + "jetzt gezeigt. Verwahren wie bei FileVault: gedruckt, an einem sicheren "
                 + "Ort, nicht neben der Planung und nicht in der Cloud der Kopie.")
        }

        Section {
            Toggle("Ich habe den Wiederherstellungsschlüssel verwahrt", isOn: $verwahrt)
        } footer: {
            Text(erneuern
                 ? "Erst mit dieser Bestätigung wird der Schlüssel erneuert."
                 : "Erst mit dieser Bestätigung wird die Verschlüsselung eingeschaltet. Bis "
                   + "dahin ist nichts geschehen.")
        }
    }
}
