// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Eine gewählte Datei für den Import — gelesen, noch nicht ausgewertet.
struct Importquelle: Identifiable {
    let id = UUID()
    let name: String
    let daten: Data
}

/// „Aus IServ importieren“ (AP13, Plan 4.4) — ein Bogen am Blatt „Lernende“:
/// Kodierung und Trenner (erkannt, umschaltbar), die drei Spalten, die Vorschau,
/// das Ziel. Gezeigt werden nur die zugeordneten Spalten; die übrigen tragen
/// nur ihren Namen in der Wahl. Geschrieben wird erst mit „Importieren“ — in den
/// Entwurf des Blatts, als ein Schritt in seinem Verlauf.
struct ImportBogen: View {
    let quelle: Importquelle
    /// Die aktiven Lerngruppen des Entwurfs, in der Ordnung des Blatts.
    let gruppen: [Lerngruppe]
    /// Die Gruppe, die im Blatt gewählt war.
    let vorwahl: String?
    /// Was der Import am jetzigen Entwurf ergäbe — ohne ihn zu ändern.
    let vorschau: (IServImport.Lesung, Importziel) -> Importbilanz
    /// Der Import in den Entwurf des Blatts; die Bilanz kommt zurück.
    let importieren: (IServImport.Lesung, Importziel) -> Importbilanz
    let archivieren: ([String]) -> Void
    /// „Nachname, Vorname“ einer Person des Entwurfs.
    let personenname: (String) -> String

    @Environment(\.dismiss) private var schliessen

    private enum Ziel: Hashable {
        case gruppe(String)
        case neu
        case jeKlasse
    }

    @State private var kodierung: IServImport.Kodierung?
    @State private var trenner: IServImport.Trenner?
    @State private var kopfzeile = true
    @State private var zuordnung = IServImport.Zuordnung()
    @State private var ziel: Ziel = .neu
    @State private var neuerName = ""
    @State private var bilanz: Importbilanz?
    @State private var archiviert = false

    private var text: IServImport.Text? { IServImport.entschluesseln(quelle.daten, kodierung: kodierung) }
    private var erkannterTrenner: IServImport.Trenner {
        IServImport.trennerErkennen(text?.inhalt ?? "")
    }
    private var tabelle: [[String]] {
        IServImport.zerlegen(text?.inhalt ?? "", trenner: trenner ?? erkannterTrenner)
    }
    private var spaltenzahl: Int { tabelle.prefix(20).map(\.count).max() ?? 0 }
    private var lesung: IServImport.Lesung { IServImport.lesen(tabelle, kopfzeile: kopfzeile, zuordnung: zuordnung) }

    private var importziel: Importziel? {
        switch ziel {
        case .gruppe(let id): .gruppe(id)
        case .jeKlasse: zuordnung.klasse == nil ? nil : .jeKlasse
        case .neu:
            Lernendenbestand.zeile(neuerName, Planungsdatei.maxNamenslaenge).isEmpty
                ? nil : .neueGruppe(Lernendenbestand.zeile(neuerName, Planungsdatei.maxNamenslaenge))
        }
    }

    /// Der Name einer Spalte in der Wahl — aus der Kopfzeile, sonst die Nummer.
    private func spaltenname(_ stelle: Int) -> String {
        Self.spaltenname(stelle, tabelle: tabelle, kopfzeile: kopfzeile)
    }

    /// Namen nur aus einer erkannten IServ-Kopfzeile — eine Datenzeile, als Kopf
    /// geschaltet, zeigte sonst Konto und Adresse einer Person (W3-02).
    nonisolated static func spaltenname(_ stelle: Int, tabelle: [[String]], kopfzeile: Bool) -> String {
        let erkannt = kopfzeile && tabelle.first.flatMap(IServImport.zuordnungAusKopf) != nil
        let kopf = erkannt ? tabelle.first?[safe: stelle]?.trimmingCharacters(in: .whitespaces) ?? "" : ""
        return kopf.isEmpty ? "Spalte \(stelle + 1)" : "Spalte \(stelle + 1) „\(kopf)“"
    }

    var body: some View {
        Dialograhmen(titel: "Aus IServ importieren",
                     unterzeile: "„\(quelle.name)“ · \(quelle.daten.count) Byte",
                     breite: 820, hoehe: 640) {
            // Der Rahmen legt die Abschnitte in seine gruppierte Form — keine zweite hier.
            if let bilanz {
                ergebnis(bilanz)
            } else if text == nil {
                Section {
                    kodierungswahl
                } footer: {
                    Text("Die Datei lässt sich als \(kodierung?.rawValue ?? "Text") nicht lesen — bitte eine andere "
                         + "Kodierung wählen.")
                }
            } else {
                einstellungen
            }
        } fuss: {
            if bilanz != nil {
                Spacer(minLength: 0)
                Button("Fertig") { schliessen() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Text(importziel.map { vorschau(lesung, $0).kurz } ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Abbrechen") { schliessen() }
                    .keyboardShortcut(.cancelAction)
                Button("Importieren") {
                    guard let importziel else { return }
                    bilanz = importieren(lesung, importziel)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(importziel == nil || !zuordnung.vollstaendig || lesung.zeilen.isEmpty)
            }
        }
        .onAppear(perform: vorbelegen)
    }

    // ── Vor dem Import ────────────────────────────────────────────────────

    private var kodierungswahl: some View {
        Picker("Kodierung", selection: Binding(
            get: { kodierung ?? text?.kodierung ?? .utf8 },
            set: { kodierung = $0 })) {
            ForEach(IServImport.Kodierung.allCases) { Text($0.rawValue).tag($0) }
        }
    }

    @ViewBuilder
    private var einstellungen: some View {
        Section {
            kodierungswahl
            Picker("Trenner", selection: Binding(
                get: { trenner ?? erkannterTrenner },
                set: { trenner = $0 })) {
                ForEach(IServImport.Trenner.allCases) { Text($0.name).tag($0) }
            }
            Toggle("Erste Zeile ist die Kopfzeile", isOn: $kopfzeile)
        } header: {
            Text("Datei")
        } footer: {
            Text("Erkannt: \(text?.kodierung.rawValue ?? "—")\(text?.bom == true ? " mit BOM" : ""), "
                 + "\(erkannterTrenner.name). Beides lässt sich umstellen, falls die Vorschau falsch aussieht.")
        }

        Section {
            spaltenwahl("Vorname", \.vorname, pflicht: true)
            spaltenwahl("Nachname", \.nachname, pflicht: true)
            spaltenwahl("Klasse", \.klasse, pflicht: false)
        } header: {
            Text("Spalten")
        } footer: {
            Text("Gelesen werden nur diese drei Spalten; alle übrigen — Account, E-Mail-Adresse und was die "
                 + "Datei sonst trägt — bleiben ungelesen und werden nicht gezeigt. Namen der Spalten nennt die Wahl "
                 + "nur aus einer erkannten IServ-Kopfzeile, sonst ihre Nummern.")
        }

        Section {
            vorschautabelle
        } header: {
            Text("Vorschau")
        } footer: {
            if !lesung.fehler.isEmpty {
                Text("Übergangen: " + lesung.fehler.prefix(4).map { "Zeile \($0.nummer) (\($0.grund.ohneSchlusspunkt))" }
                    .joined(separator: ", ") + (lesung.fehler.count > 4 ? " …" : ""))
            }
        }

        Section {
            Picker("Lerngruppe", selection: $ziel) {
                ForEach(gruppen) { Text($0.beschriftung).tag(Ziel.gruppe($0.id)) }
                Divider()
                Text("Neue Lerngruppe").tag(Ziel.neu)
                if zuordnung.klasse != nil {
                    Text("Je Klasse eine Lerngruppe").tag(Ziel.jeKlasse)
                }
            }
            if ziel == .neu {
                // Im gruppierten Formular nur mit verborgener Beschriftung sichtbar (macOS 26).
                TextField("Name der neuen Lerngruppe", text: $neuerName, prompt: Text("Name der neuen Lerngruppe"))
                    .labelsHidden()
            }
        } header: {
            Text("Ziel")
        } footer: {
            Text("Wer in der Lerngruppe mit gleichem Vor- und Nachnamen schon steht, bleibt unverändert; wer in "
                 + "einer anderen Lerngruppe dieses Schuljahrs steht, wird zugeordnet — dieselbe Person, keine neue. "
                 + "Archivierte Personen der Lerngruppe werden zurückgeholt. "
                 + "Gleichnamige werden genannt, nicht geraten. Gelöscht wird nichts.")
        }
    }

    private func spaltenwahl(_ titel: String, _ feld: WritableKeyPath<IServImport.Zuordnung, Int?>,
                             pflicht: Bool) -> some View {
        Picker(titel, selection: Binding(
            get: { zuordnung[keyPath: feld] ?? -1 },
            set: { zuordnung[keyPath: feld] = $0 < 0 ? nil : $0 })) {
            Text(pflicht ? "— bitte wählen —" : "— keine —").tag(-1)
            ForEach(0..<spaltenzahl, id: \.self) { Text(spaltenname($0)).tag($0) }
        }
    }

    private var vorschautabelle: some View {
        let zeilen = Array(lesung.zeilen.prefix(IServImport.vorschauzeilen))
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("Zeile").gridColumnAlignment(.trailing)
                Text("Vorname")
                Text("Nachname")
                Text("Klasse")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(zeilen, id: \.nummer) { z in
                GridRow {
                    Text("\(z.nummer)").monospacedDigit().foregroundStyle(.secondary)
                    Text(z.vorname)
                    Text(z.nachname)
                    Text(z.klasse.isEmpty ? "—" : z.klasse)
                }
            }
            if lesung.zeilen.count > zeilen.count {
                GridRow {
                    Text("")
                    Text("… und \(lesung.zeilen.count - zeilen.count) weitere").foregroundStyle(.secondary)
                }
            }
        }
    }

    // ── Nach dem Import ───────────────────────────────────────────────────

    private func ergebnis(_ bilanz: Importbilanz) -> some View {
        Section {
            Text(bilanz.kurz).font(.title3)
            if !bilanz.neueGruppen.isEmpty {
                Text("Neue Lerngruppen: " + bilanz.neueGruppenGeordnet.joined(separator: ", "))
            }
            if !bilanz.uebergangen.isEmpty {
                DisclosureGroup("Übergangen: \(bilanz.uebergangen.count) Zeilen") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(bilanz.uebergangen) { f in
                            Text("Zeile \(f.nummer): \(f.grund)").font(.callout)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            if !bilanz.fehlende.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In der Datei fehlen \(bilanz.fehlende.count) "
                         + (bilanz.fehlende.count == 1 ? "Person" : "Personen") + " der Lerngruppe: "
                         + bilanz.fehlende.map(personenname).joined(separator: "; "))
                        .fixedSize(horizontal: false, vertical: true)
                    if archiviert {
                        Label("Archiviert — ihre Einträge bleiben, „Zurückholen“ geht jederzeit.", systemImage: Zeichen.haken)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Fehlende archivieren") {
                            archivieren(bilanz.fehlende)
                            archiviert = true
                        }
                        .help("Die Personen aus den Listen nehmen — ihre Einträge bleiben")
                    }
                }
            }
        } header: {
            Text("Bilanz")
        } footer: {
            Text("Übernommen wird mit „Übernehmen“ im Blatt „Lernende“; ⌘Z nimmt den Import dort zurück.")
        }
    }

    // ── Vorbelegung ───────────────────────────────────────────────────────

    /// Die Kopfzeile belegt die Spalten vor; ohne sie wird nichts geraten.
    /// Ziel: die gewählte Gruppe, sonst je Klasse, sonst eine neue.
    private func vorbelegen() {
        let erkannt = tabelle.first.flatMap(IServImport.zuordnungAusKopf)
        kopfzeile = erkannt != nil
        zuordnung = erkannt ?? IServImport.Zuordnung()
        if let vorwahl, gruppen.contains(where: { $0.id == vorwahl }) {
            ziel = .gruppe(vorwahl)
        } else if zuordnung.klasse != nil {
            ziel = .jeKlasse
        } else {
            ziel = .neu
        }
    }
}
