// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Der Sitzplan-Editor — ein Blatt im Hauptfenster, breiter als die übrigen
/// (E30). Ohne Plan: die Namensliste, eine Zeile je Name, und „Tische
/// anordnen“. Mit Plan: die Fläche mit Tafel, Lehrertisch und Tischen. Das
/// Blatt arbeitet auf einem Entwurf; „Übernehmen“ schreibt ihn, „Abbrechen“
/// verwirft alles seit dem Öffnen — mehr Undo gibt es nicht.
struct SitzplanDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    /// Der Entwurf; `nil`, solange noch kein Plan angelegt ist.
    @State private var plan: Sitzplan?
    /// Der Stand beim Öffnen — für „Änderungen verwerfen?“.
    @State private var ausgang: Sitzplan?
    @State private var namenstext = ""
    /// Die Namensliste steht auch mit Plan — nach „Namen neu eingeben …“.
    @State private var namenEingeben = false
    @State private var auswahl: Set<String> = []
    @State private var umbenennen: String?
    @State private var verwerfenFragen = false
    @State private var neuEingebenFragen = false

    private var klasse: Klasse? { speicher.sitzplanKlasseStand }
    private var pruefung: Sitzplan.Namensliste { Sitzplan.namenLesen(namenstext) }

    private var veraendert: Bool {
        if let plan { return plan != ausgang }
        return ausgang != nil || !namenstext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unterzeile: String {
        guard let plan else { return "Namen eingeben — eine Zeile je Schülerin oder Schüler" }
        return "\(plan.tische.count) von \(Kennwerte.maxSitzplaetze) Plätzen"
            + (plan.lehrertisch == nil ? "" : " · Lehrertisch")
    }

    var body: some View {
        Dialograhmen(titel: "Sitzplan — " + (klasse?.beschriftung ?? ""),
                     unterzeile: unterzeile, breite: 1000, hoehe: 720,
                     beimSchliessen: abbrechen, freierKoerper: true) {
            VStack(alignment: .leading, spacing: 12) {
                if speicher.verschluesselungsstand == .aus {
                    datenschutzhinweis
                }
                if let plan, !namenEingeben {
                    flaechenabschnitt(plan)
                } else {
                    namensabschnitt
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        } fuss: {
            if ausgang != nil {
                Button(role: .destructive) {
                    entfernen()
                } label: {
                    Label("Sitzplan entfernen", systemImage: Zeichen.muell)
                }
                .help("Den Sitzplan endgültig löschen — mit Rückfrage")
            }
            Spacer(minLength: 0)
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Button("Übernehmen") { uebernehmen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(plan == nil)
        }
        .onAppear(perform: laden)
        .onChange(of: plan) { _, neu in speicher.sitzplanEntwurf = neu }
        .alert("Die Änderungen am Sitzplan verwerfen?", isPresented: $verwerfenFragen) {
            Button("Weiter bearbeiten", role: .cancel) {}
            Button("Verwerfen", role: .destructive) { zumachen() }
        }
        .alert("Die Namen neu eingeben?", isPresented: $neuEingebenFragen) {
            Button("Abbrechen", role: .cancel) {}
            Button("Neu eingeben") {
                namenstext = plan?.namenstext ?? ""
                namenEingeben = true
            }
        } message: {
            Text("Die Anordnung wird aus der Liste neu erzeugt — verschobene Tische stehen "
                 + "danach wieder in Reihen.")
        }
        .rueckfrage(speicher, ort: .sitzplan)
    }

    // ── Datenschutz (E22): solange die Verschlüsselung aus ist ────────────

    private var datenschutzhinweis: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label {
                Text(Planungsspeicher.sitzplanDatenschutzhinweis)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: Zeichen.warnung).foregroundStyle(.orange)
            }
            .font(.callout)
            Spacer(minLength: 0)
            Button(plan != nil && veraendert ? "Übernehmen und Verschlüsselung einrichten …"
                                             : "Verschlüsselung einrichten …") {
                if let plan, veraendert { speicher.sitzplanUebernehmen(plan) }
                speicher.sitzplanDialogSchliessen()
                speicher.verschluesselungEinrichten()
                schliessen()
            }
            // Eine getippte, noch nicht angeordnete Liste ginge sonst verloren.
            .disabled(plan == nil && veraendert)
            .help(plan == nil && veraendert ? "Erst „Tische anordnen“ — die Liste ginge sonst verloren."
                                            : "Schließt den Editor und öffnet die Einrichtung der Verschlüsselung.")
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 8))
    }

    // ── Die Namensliste ───────────────────────────────────────────────────

    private static let beispiel = """
        Amira Yilmaz
        Ben Fischer
        Clara Weber
        …
        """

    private func fehlerzeile(_ fehler: Sitzplan.Zeilenfehler) -> AttributedString {
        var kopf = AttributedString("Zeile \(fehler.nummer): ")
        kopf.inlinePresentationIntent = .stronglyEmphasized
        return kopf + AttributedString("„\(fehler.zeile)“ — \(fehler.grund)")
    }

    private var namensabschnitt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eine Zeile je Schülerin oder Schüler, höchstens \(Kennwerte.maxSitzplaetze). "
                 + "Die Tische entstehen daraus in Reihen zu acht, von der Tafel aus gezählt; das "
                 + "Raster fasst zehn Plätze je Reihe, zwei bleiben für Gänge frei — danach lassen "
                 + "sich die Tische frei verschieben.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Textfeld(text: $namenstext, mindesthoehe: 300,
                     beschriftung: "Namensliste, eine Zeile je Name")
                .overlay(alignment: .topLeading) {
                    if namenstext.isEmpty {
                        Text(Self.beispiel)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                }

            if !namenstext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ergebnis = pruefung
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ergebnis.fehler.prefix(4)) { fehler in
                        Pruefzeile(gut: false, inhalt: Text(fehlerzeile(fehler)))
                    }
                    if ergebnis.fehler.count > 4 {
                        Pruefzeile(gut: false,
                                   inhalt: Text("… und \(ergebnis.fehler.count - 4) weitere Zeilen"))
                    }
                    if ergebnis.fehler.isEmpty {
                        Pruefzeile(gut: true, inhalt: Text(
                            "\(ergebnis.namen.count) " + (ergebnis.namen.count == 1 ? "Name" : "Namen")))
                    }
                }
            }

            HStack(spacing: 12) {
                if plan != nil {
                    Button("Zurück zur Fläche") { namenEingeben = false }
                }
                Button("Tische anordnen") { anordnen() }
                    .buttonStyle(.borderedProminent)
                    // ⌘⏎: Die Schreibmarke steht in der Liste, ⏎ macht dort eine neue Zeile.
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(pruefung.namen.isEmpty || !pruefung.fehler.isEmpty)
                    .help("Aus der Liste die Tische anordnen (⌘⏎)")
            }
        }
    }

    private func anordnen() {
        guard let klasse else { return }
        let ergebnis = pruefung
        guard ergebnis.fehler.isEmpty, !ergebnis.namen.isEmpty else {
            speicher.melden(ergebnis.fehler.count == 1
                            ? "Zeile \(ergebnis.fehler[0].nummer) lässt sich nicht übernehmen."
                            : "\(ergebnis.fehler.count) Zeilen lassen sich nicht übernehmen.", .warnung)
            return
        }
        plan = Sitzplan.anordnen(klasseId: klasse.id, namen: ergebnis.namen)
        auswahl = []
        namenEingeben = false
    }

    // ── Die Fläche ────────────────────────────────────────────────────────

    private func flaechenabschnitt(_ stand: Sitzplan) -> some View {
        let ton = Farbwelt.ton(klasse?.farbe ?? Farbwelt.ohneFarbe)
        let planBindung = Binding<Sitzplan>(
            get: { plan ?? stand },
            set: { plan = $0 })
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    tischHinzufuegen()
                } label: {
                    Label("Tisch hinzufügen", systemImage: Zeichen.plus)
                }
                .disabled(stand.tische.count >= Kennwerte.maxSitzplaetze)
                .help("Einen Tisch an eine freie Stelle setzen und benennen")

                if stand.lehrertisch == nil {
                    Button("Lehrertisch hinzufügen") { plan = stand.mitLehrertisch() }
                }

                Button("Namen neu eingeben …") { neuEingebenFragen = true }
                    .help("Die Liste erneut eingeben — die Anordnung wird neu erzeugt")

                Spacer(minLength: 0)

                Button {
                    alsPDFSichern(stand)
                } label: {
                    Label("Als PDF sichern …", systemImage: Zeichen.export)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("DIN A4 quer, die Tafel unten (⇧⌘P)")

                Button {
                    drucken(stand)
                } label: {
                    Label("Drucken …", systemImage: Zeichen.drucker)
                }
                .keyboardShortcut("p", modifiers: .command)
                .help("Dieselbe Seite auf Papier (⌘P)")
            }

            Sitzplanflaeche(plan: planBindung, auswahl: $auswahl, umbenennen: $umbenennen, ton: ton)
                .frame(width: Sitzplanmasse.breite, height: Sitzplanmasse.hoehe)
                .frame(maxWidth: .infinity)

            Text("Ziehen verschiebt einen Tisch oder alle angewählten; die rechte Maustaste zieht "
                 + "eine Bereichsauswahl auf und öffnet kurz gedrückt das Menü. Doppelklick benennt "
                 + "um. Pfeiltasten verschieben um 8 Punkt, mit ⇧ um 1. Die Tische rasten "
                 + "unsichtbar ein, zehn Plätze je Reihe für bis zu zwei Gänge — ⌥ beim Ziehen "
                 + "hebt das auf, für schräge Sitzgruppen und freie Anordnungen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tischHinzufuegen() {
        guard let stand = plan, let neu = stand.mitNeuemTisch(name: "Name") else { return }
        plan = neu
        if let letzter = neu.tische.last {
            auswahl = [letzter.id]
            umbenennen = letzter.id
        }
    }

    private func alsPDFSichern(_ stand: Sitzplan) {
        guard let klasse else { return }
        Sitzplandruck.alsPDFSichern(stand, klasse: klasse, speicher: speicher, ort: .sitzplan)
    }

    private func drucken(_ stand: Sitzplan) {
        guard let klasse else { return }
        Sitzplandruck.drucken(stand, klasse: klasse, speicher: speicher)
    }

    // ── Öffnen, Übernehmen, Abbrechen, Entfernen ──────────────────────────

    private func laden() {
        let gespeichert = speicher.sitzplanKlasse.flatMap { speicher.sitzplan(fuer: $0) }
        plan = gespeichert
        ausgang = gespeichert
        speicher.sitzplanEntwurf = gespeichert
        namenstext = ""
        namenEingeben = false
        auswahl = []
    }

    private func zumachen() {
        speicher.sitzplanDialogSchliessen()
        schliessen()
    }

    private func abbrechen() {
        if veraendert { verwerfenFragen = true } else { zumachen() }
    }

    private func uebernehmen() {
        guard let plan else { return }
        if let grund = speicher.sitzplanUebernehmen(plan) {
            speicher.melden("Der Sitzplan gilt für diese Sitzung, ließ sich aber nicht sichern (\(grund)).",
                            .warnung)
        }
        zumachen()
    }

    private func entfernen() {
        guard let klasse else { return }
        speicher.sitzplanEntfernen(klasse: klasse.id, ort: .sitzplan) {
            speicher.sitzplanDialogSchliessen()
            schliessen()
        }
    }
}
