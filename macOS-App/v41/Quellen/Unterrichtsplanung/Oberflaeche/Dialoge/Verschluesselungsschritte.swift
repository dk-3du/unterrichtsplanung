// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// Die zwei Schritte der Einrichtung — dieselben unter „Einstellungen →
// Verschlüsselung“ und in der Ersteinrichtung. Abschnitte einer
// gruppierten Form; den Fuß mit „Weiter“ und „Einschalten“ stellt das Blatt,
// das sie zeigt.

/// Schritt 1: die Passphrase wählen (Einrichtung) — oder beim Erneuern des
/// Schlüssels die bisherige belegen und eine neue wählen.
struct Passphrasenwahl: View {
    @Binding var passphrase: String
    @Binding var wiederholung: String
    /// Erneuern: dazu die bisherige Passphrase, die belegt wird.
    var bisherige: Binding<String>? = nil
    var erneuern: Bool { bisherige != nil }
    /// Der Absatz „Worum es geht“ — die Ersteinrichtung hat ihn schon gesagt.
    var mitEinleitung = true

    /// Ob „Weiter“ freizugeben ist — für den Fuß des Blatts. Beim Erneuern
    /// muss die bisherige belegt und die neue eine andere sein.
    static func vollstaendig(_ passphrase: String, _ wiederholung: String,
                             bisherige: String? = nil) -> Bool {
        Tresor.passphraseZulaessig(passphrase) && passphrase == wiederholung
            && (bisherige.map { !$0.isEmpty && $0 != passphrase } ?? true)
    }

    private var langGenug: Bool { Tresor.passphraseZulaessig(passphrase) }
    private var laengentext: String {
        let zahl = "\(passphrase.count) Zeichen"
        return langGenug ? zahl : zahl + " — mindestens \(Tresor.passphraseMindestlaenge)"
    }

    /// Warum „Weiter“ gesperrt bleibt, sobald es nicht die Länge ist —
    /// sonst stünde nur ein grauer Knopf da.
    private var hinweis: String? {
        if passphrase.count >= Tresor.passphraseMindestlaenge, !langGenug {
            return "Nur Leerraum gilt nicht."
        }
        if let bisherige, !bisherige.wrappedValue.isEmpty, passphrase == bisherige.wrappedValue {
            return "Die neue Passphrase ist die bisherige — bitte eine andere wählen."
        }
        if !wiederholung.isEmpty, wiederholung != passphrase {
            return "Die Wiederholung weicht ab."
        }
        return nil
    }

    var body: some View {
        if mitEinleitung {
            Section {
                if erneuern {
                    Text("Ein frischer Datenschlüssel versiegelt Ablage, Lesezeichen, Nebendateien, "
                         + "Kopie und Statusdatei neu — mit einer neuen Passphrase und einem neuen "
                         + "Wiederherstellungsblatt. Die bisherige Passphrase öffnet danach nichts "
                         + "mehr, was diese App schreibt; Kopien, die vorher jemand mitgenommen hat, "
                         + "erreicht auch das nicht.")
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
            if let bisherige {
                SecureField("Bisherige Passphrase", text: bisherige)
                    .textContentType(.password)
            }
            SecureField(erneuern ? "Neue Passphrase" : "Passphrase", text: $passphrase)
                .textContentType(.newPassword)
            SecureField(erneuern ? "Neue Passphrase wiederholen" : "Passphrase wiederholen", text: $wiederholung)
                .textContentType(.newPassword)
            LabeledContent("Länge") {
                Text(laengentext)
                    .foregroundStyle(langGenug ? Color.secondary : Color.orange)
                    .monospacedDigit()
            }
            if let hinweis {
                Label(hinweis, systemImage: Zeichen.warnung)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(erneuern ? "Bisherige belegen, neue wählen" : "Eine Passphrase wählen")
        } footer: {
            if erneuern {
                Text("Nur wer die bisherige Passphrase kennt, darf den Schlüssel erneuern; die neue "
                     + "muss eine andere sein — mindestens \(Tresor.passphraseMindestlaenge) Zeichen.")
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
