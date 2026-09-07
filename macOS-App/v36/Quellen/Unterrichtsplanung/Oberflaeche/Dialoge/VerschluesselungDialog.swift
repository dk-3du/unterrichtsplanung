// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// ── Entsperren ────────────────────────────────────────────────────────────

/// Die Freigabe beim Start oder für eine fremde Datei: Touch ID läuft von
/// selbst an; darunter, wie in der Ansicht, immer nur eines von zwei Feldern —
/// Passphrase oder Wiederherstellungsschlüssel — kein Aufklappen: Ein Knopf am
/// Aufklappzustand einer `DisclosureGroup` blieb wirkungslos, und ein aufgeklapptes
/// Feld zeigte in der gruppierten Form nur seine Beschriftung. Das Blatt schließt
/// sich, sobald der Speicher die Freigabe hat.
struct EntsperrenDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @State private var passphrase = ""
    @State private var wiederherstellung = ""
    @FocusState private var fokus: Planungsspeicher.Entsperrungsweg?

    private var fuerAblage: Bool { speicher.entsperrungFuerAblage }
    private var mitWiederherstellung: Bool { speicher.entsperrungsweg == .wiederherstellung }
    private var eingabeLeer: Bool {
        (mitWiederherstellung ? wiederherstellung : passphrase)
            .trimmingCharacters(in: .whitespaces).isEmpty
    }
    /// Das Häkchen gibt es nur für die Ablage und nur, wo eine Enklave da ist.
    private var mitHaekchen: Bool { fuerAblage && Tresor.enklaveVerfuegbar }
    /// Das Blatt wächst mit dem, was es zeigt — sonst rutscht der
    /// Fehlerabschnitt unter den Rand.
    private var hoehe: CGFloat {
        430 + (mitHaekchen ? 50 : 0) + (speicher.enklaveMoeglich ? 46 : 0)
            + (speicher.entsperrungFehler == nil ? 0 : 74)
    }

    var body: some View {
        @Bindable var speicher = speicher
        // Kompakt wie das Passwortblatt von Numbers: ein Feld, das Häkchen, die
        // Wege daneben; die Systemabfrage steht davor allein.
        Dialograhmen(titel: fuerAblage ? "Passphrase eingeben" : "Datei entsperren",
                     unterzeile: fuerAblage
                        ? "Die Planung auf diesem Mac ist verschlüsselt"
                        : "Die geöffnete Datei ist unter einem anderen Schlüssel versiegelt",
                     breite: 540, hoehe: hoehe,
                     beimSchliessen: abbrechen) {
            Section {
                if mitWiederherstellung {
                    TextField("Wiederherstellungsschlüssel", text: $wiederherstellung,
                              prompt: Text("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"))
                        .labelsHidden()
                        .monospaced()
                        .autocorrectionDisabled()
                        .focused($fokus, equals: .wiederherstellung)
                        .onSubmit(entsperren)
                } else {
                    // Die eigene Zeile lässt dem Knopf „Passwörter …“ der
                    // Systemergänzung Platz; er erreicht den Eintrag der Passwörter-App.
                    SecureField("Passphrase", text: $passphrase, prompt: Text("Passphrase"))
                        .labelsHidden()
                        .textContentType(.password)
                        .focused($fokus, equals: .passphrase)
                        .onSubmit(entsperren)
                }
            } header: {
                Text(mitWiederherstellung ? "Wiederherstellungsschlüssel" : "Passphrase")
            } footer: {
                Text(fusszeile)
            }

            if mitHaekchen {
                Section {
                    Toggle("Mit Touch ID öffnen", isOn: $speicher.enklaveMerken)
                        .toggleStyle(.checkbox)
                } footer: {
                    Text(haekchentext)
                }
            }

            Section {
                Button(mitWiederherstellung
                       ? "Stattdessen die Passphrase eingeben"
                       : "Stattdessen den Wiederherstellungsschlüssel eingeben") {
                    speicher.entsperrungswegWechseln()
                }
                if speicher.enklaveMoeglich {
                    Button {
                        speicher.entsperrenMitEnklave()
                    } label: {
                        Label("Touch ID oder Anmeldepasswort erneut versuchen",
                              systemImage: Zeichen.touchID)
                    }
                    .disabled(speicher.entsperrungLaeuft)
                }
            }

            if let fehler = speicher.entsperrungFehler {
                Section {
                    Label(fehler, systemImage: Zeichen.warnung)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } fuss: {
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button("Entsperren") { entsperren() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(eingabeLeer)
        }
        .onAppear { fokus = speicher.entsperrungsweg }
        .onChange(of: speicher.entsperrungsweg) { _, weg in fokus = weg }
        .onChange(of: passphrase) { _, _ in speicher.entsperrungFehlerVerwerfen() }
        .onChange(of: wiederherstellung) { _, _ in speicher.entsperrungFehlerVerwerfen() }
    }

    private var fusszeile: String {
        if mitWiederherstellung {
            return "Das gedruckte Blatt aus der Einrichtung. Groß- und Kleinschreibung, "
                + "Bindestriche und Leerzeichen spielen keine Rolle."
        }
        return fuerAblage ? "Dieselbe Passphrase öffnet die Kopie in der Ansicht fürs iPad."
                          : "Die Passphrase, mit der die Datei geschrieben wurde."
    }

    private var haekchentext: String {
        if speicher.enklaveWicklungPasstNicht {
            return "Mit dem Häkchen wird dieser Mac nach der Freigabe neu eingerichtet — sein "
                + "Schlüssel passt nicht mehr, etwa nach einem Umzug oder Neuaufsetzen."
        }
        return speicher.enklaveMerken
            ? "Danach genügen Touch ID oder das Anmeldepasswort dieses Macs; die Passphrase "
              + "bleibt für die Kopie fürs iPad und für andere Macs."
            : "Ohne Häkchen ist die Passphrase bei jedem Start fällig."
    }

    private func entsperren() {
        guard !eingabeLeer else { return }
        if mitWiederherstellung {
            speicher.entsperren(wiederherstellung: wiederherstellung)
        } else {
            speicher.entsperren(passphrase: passphrase)
        }
    }

    private func abbrechen() {
        speicher.entsperrungAbbrechen()
        schliessen()
    }
}

// ── Einrichten und verwalten ──────────────────────────────────────────────

/// Einschalten in zwei Schritten (Passphrase, dann das Blatt — scharf erst
/// nach der Bestätigung, eine verlorene Jahresplanung wäre der größere
/// Schaden) und verwalten (Passphrase ändern, Schlüssel erneuern, aufheben).
struct VerschluesselungDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    private enum Schritt: Equatable {
        case uebersicht
        /// Passphrase wählen (Einrichtung) oder belegen (Schlüssel erneuern).
        case passphrase(erneuern: Bool)
        case blatt(schluessel: String, erneuern: Bool)
        case passphraseAendern
    }

    @State private var schritt: Schritt = .uebersicht
    @State private var passphrase = ""
    @State private var wiederholung = ""
    @State private var bisherige = ""
    @State private var verwahrt = false
    @State private var fehler: String?

    var body: some View {
        Dialograhmen(titel: "Verschlüsselung", unterzeile: unterzeile,
                     breite: 640, hoehe: 680, beimSchliessen: abbrechen) {
            switch schritt {
            case .uebersicht: uebersicht
            case .passphrase(let erneuern):
                Passphrasenwahl(passphrase: $passphrase, wiederholung: $wiederholung,
                                erneuern: erneuern)
            case .blatt(let schluessel, let erneuern):
                Wiederherstellungsschritt(schluessel: schluessel, erneuern: erneuern,
                                          verwahrt: $verwahrt)
            case .passphraseAendern: passphraseAenderung
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
        .rueckfrage(speicher, ort: .verschluesselung)
        .onAppear {
            if !speicher.verschluesselt { schritt = .passphrase(erneuern: false) }
        }
    }

    private var unterzeile: String {
        switch schritt {
        case .uebersicht: "Eingeschaltet — Ablage, Sicherungskopie und Export sind versiegelt"
        case .passphrase(false): "Schritt 1 von 2: eine Passphrase wählen"
        case .passphrase(true): "Schlüssel erneuern — Schritt 1 von 2: die Passphrase belegen"
        case .blatt: "Schritt 2 von 2: den Wiederherstellungsschlüssel verwahren"
        case .passphraseAendern: "Passphrase ändern"
        }
    }

    // ── Übersicht ─────────────────────────────────────────────────────────

    @ViewBuilder
    private var uebersicht: some View {
        Section {
            ForEach(speicher.wicklungen, id: \.art) { wicklung in
                Label(wicklung.beschriftung, systemImage: Zeichen.schluessel)
            }
        } header: {
            Text("Wicklungen des Datenschlüssels")
        } footer: {
            Text("Jede Wicklung öffnet denselben Datenschlüssel. Die Wicklung dieses Macs "
                 + "verlässt ihn nie; die Kopie beim Beenden und der Export tragen nur "
                 + "Passphrase und Wiederherstellungsschlüssel.")
        }

        if Tresor.enklaveVerfuegbar {
            Section {
                Toggle("Mit Touch ID öffnen", isOn: Binding(
                    get: { speicher.enklaveEingerichtet },
                    set: { speicher.enklaveAufDiesemMac($0) }))
            } header: {
                Text("Dieser Mac")
            } footer: {
                Text("An: Touch ID oder das Anmeldepasswort öffnen die Planung beim Start. "
                     + "Aus: Beim Start ist die Passphrase fällig. Die Kopie beim Beenden und "
                     + "der Export bleiben davon unberührt.")
            }
        }

        Section {
            Button("Passphrase ändern …") {
                fehler = nil
                schritt = .passphraseAendern
            }
            Button("Schlüssel erneuern …") {
                fehler = nil
                schritt = .passphrase(erneuern: true)
            }
        } header: {
            Text("Ändern")
        } footer: {
            Text("Eine geänderte Passphrase gilt für die Ablage sofort und für die Kopie beim "
                 + "nächsten Beenden — eine ältere Kopie in der Cloud kennt noch die alte. Wer "
                 + "die alte für verbrannt hält, erneuert den Schlüssel: neuer Datenschlüssel, "
                 + "neues Wiederherstellungsblatt, alles neu versiegelt.")
        }

        Section {
            Button("Verschlüsselung aufheben …", role: .destructive) {
                speicher.fragen(
                    "Die Ablage auf diesem Mac wird wieder im Klartext geschrieben, ebenso die "
                    + "Nebendateien. Die Sicherungskopie beim Beenden wird ausgeschaltet — es "
                    + "gibt sie nur verschlüsselt.\n\nFortfahren?",
                    bestaetigung: "Aufheben", gefahr: true, ort: .verschluesselung) {
                    speicher.verschluesselungAufheben()
                    schliessen()
                }
            }
        } header: {
            Text("Aufheben")
        } footer: {
            Text("Der Klartext-Export („Als Klartext-JSON sichern …“ im Menü „Ablage“) bleibt "
                 + "davon unabhängig verfügbar.")
        }
    }

    // ── Passphrase ändern ─────────────────────────────────────────────────

    @ViewBuilder
    private var passphraseAenderung: some View {
        Section {
            SecureField("Bisherige Passphrase", text: $bisherige)
                .textContentType(.password)
            SecureField("Neue Passphrase", text: $passphrase)
                .textContentType(.newPassword)
            SecureField("Neue Passphrase wiederholen", text: $wiederholung)
                .textContentType(.newPassword)
        } header: {
            Text("Passphrase")
        } footer: {
            Text("Es werden 32 Byte neu gewickelt — die Daten bleiben unberührt. Mindestens "
                 + "\(Tresor.passphraseMindestlaenge) Zeichen.")
        }
    }

    // ── Fuß ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private var fuss: some View {
        switch schritt {
        case .uebersicht:
            Spacer(minLength: 0)
            Button("Fertig") { schliessen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        case .passphrase(let erneuern):
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button("Weiter") { weiter(erneuern: erneuern) }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!Passphrasenwahl.vollstaendig(passphrase, wiederholung,
                                                        erneuern: erneuern))
        case .blatt(_, let erneuern):
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button(erneuern ? "Schlüssel erneuern" : "Verschlüsselung einschalten") {
                speicher.verschluesselungEinschalten()
                schliessen()
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!verwahrt)
        case .passphraseAendern:
            Button("Abbrechen") {
                fehler = nil
                schritt = .uebersicht
            }
            .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button("Ändern") { aendern() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(bisherige.isEmpty || passphrase.count < Tresor.passphraseMindestlaenge
                          || passphrase != wiederholung)
        }
    }

    private func weiter(erneuern: Bool) {
        fehler = nil
        do {
            let schluessel = erneuern
                ? try speicher.schluesselErneuernVorbereiten(passphrase: passphrase)
                : try speicher.verschluesselungVorbereiten(passphrase: passphrase)
            verwahrt = false
            schritt = .blatt(schluessel: schluessel, erneuern: erneuern)
        } catch {
            fehler = error.localizedDescription
        }
    }

    private func aendern() {
        fehler = nil
        do {
            try speicher.passphraseAendern(alt: bisherige, neu: passphrase)
            bisherige = ""
            passphrase = ""
            wiederholung = ""
            schritt = .uebersicht
        } catch {
            fehler = error.localizedDescription
        }
    }

    private func abbrechen() {
        speicher.verschluesselungVerwerfen()
        schliessen()
    }
}
