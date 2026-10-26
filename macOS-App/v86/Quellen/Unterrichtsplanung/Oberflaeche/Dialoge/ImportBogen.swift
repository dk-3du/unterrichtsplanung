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
/// Entwurf des Blatts, als ein Schritt in seinem Verlauf. Am Blatt „Neue Planung“
/// (E605) nur „Je Klasse“, ohne Ziel und Fehlende: „Übernehmen“ gibt die Lesung
/// ans Blatt, geschrieben wird erst mit „Planung anlegen“.
struct ImportBogen: View {
    let quelle: Importquelle
    /// Die aktiven Lerngruppen des Entwurfs, in der Ordnung des Blatts.
    let gruppen: [Lerngruppe]
    /// Die Gruppe, die im Blatt gewählt war.
    let vorwahl: String?
    /// Was der Import am jetzigen Entwurf ergäbe — ohne ihn zu ändern.
    let vorschau: (IServImport.Lesung, Importziel) -> Importbilanz
    /// Der Import in den Entwurf des Blatts; die Bilanz kommt zurück. Der dritte Wert: neue Lerngruppen an
    /// gleichnamige Zeilen binden (nur bei „Je Klasse“, E352).
    let importieren: (IServImport.Lesung, Importziel, Bool) -> Importbilanz
    let archivieren: ([String]) -> Void
    /// Fehlende, die in einer anderen Lerngruppe stehen, nur aus der Zielgruppe nehmen (E368).
    let herausnehmen: ([Fehlmitgliedschaft]) -> Void
    /// „Nachname, Vorname“ einer Person des Entwurfs.
    let personenname: (String) -> String
    /// Am Blatt „Neue Planung“ (E605): nur „Je Klasse“, keine Fehlenden; „Übernehmen“ (E606) gibt die Lesung ans Blatt
    /// und schließt — geschrieben wird erst mit „Planung anlegen“.
    var amBlattNeuePlanung = false

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
    /// „Neue Lerngruppen an gleichnamige Zeilen binden“ — Vorgabe an (E352).
    @State private var binden = true
    @State private var bilanz: Importbilanz?
    @State private var archiviert = false
    @State private var herausgenommen = false

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
                     // Der Bogen liegt auf dem Blatt „Lernende“ und zeigt dessen Zeile (E490); am Blatt „Neue Planung“
                     // so breit wie das Blatt — ein eigener Bogen steht nicht über.
                     breite: amBlattNeuePlanung ? 720 : 820, hoehe: 640,
                     meldungsblatt: amBlattNeuePlanung ? nil : .lernende) {
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
                Fussluecke()
                Button("Fertig") { schliessen() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Text(amBlattNeuePlanung ? "Übernommen wird mit „Planung anlegen“ — die Lerngruppen entstehen mit der Planung."
                     : importziel.map { vorschau(lesung, $0).kurz } ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Fussluecke()
                Button("Abbrechen") { schliessen() }
                    .keyboardShortcut(.cancelAction)
                Button(amBlattNeuePlanung ? "Übernehmen" : "Importieren") {
                    guard let importziel else { return }
                    if amBlattNeuePlanung {
                        _ = importieren(lesung, importziel, true)
                        schliessen()
                    } else {
                        bilanz = importieren(lesung, importziel, importziel == .jeKlasse && binden)
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                // Am Blatt „Neue Planung“ zählt nur, wer eine Klasse trägt — ohne eine entstünde nichts.
                .disabled(importziel == nil || !zuordnung.vollstaendig || lesung.zeilen.isEmpty
                          || (amBlattNeuePlanung && !lesung.zeilen.contains { !$0.klasse.isEmpty }))
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
            spaltenwahl("Klasse", \.klasse, pflicht: amBlattNeuePlanung)
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

        if !amBlattNeuePlanung {
            zielabschnitt
        }
    }

    /// Wohin der Import geht — am Blatt „Neue Planung“ immer „Je Klasse“ (E605).
    private var zielabschnitt: some View {
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
            // Nur bei gültigem Ziel — ohne Klassenspalte wirkte der Schalter nicht (Z-AT5-08).
            if importziel == .jeKlasse {
                Toggle("Neue Lerngruppen an gleichnamige Zeilen binden", isOn: $binden)
                    .help("Jede neue Lerngruppe an die Unterrichtszeilen gleichen Namens binden, die keine aktive "
                          + "Lerngruppe tragen — das Fach der Zeile zählt nicht")
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
            // Getrennt (E368): Wer in einer anderen Lerngruppe steht, wird nicht archiviert, nur aus dieser genommen.
            let texte = Self.fehlendeTexte(bilanz, personenname: personenname)
            if let fehlen = texte.fehlen {
                VStack(alignment: .leading, spacing: 6) {
                    Text(fehlen)
                        .fixedSize(horizontal: false, vertical: true)
                    if let anderswo = texte.anderswo {
                        Text(anderswo)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !bilanz.fehlende.isEmpty {
                        if archiviert {
                            Label("Archiviert — ihre Einträge bleiben, „Zurückholen“ geht jederzeit.", systemImage: Zeichen.haken)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Fehlende archivieren") {
                                archivieren(bilanz.fehlende)
                                archiviert = true
                            }
                            .help("Die Personen ohne andere Lerngruppe aus den Listen nehmen — ihre Einträge bleiben")
                        }
                    }
                    if !bilanz.fehlendeAnderswo.isEmpty {
                        if herausgenommen {
                            Label("Aus der Lerngruppe genommen — in ihren anderen Lerngruppen bleiben sie.",
                                  systemImage: Zeichen.haken)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Fehlende aus der Lerngruppe nehmen") {
                                herausnehmen(bilanz.fehlendeAnderswo)
                                herausgenommen = true
                            }
                            .help("Nur aus der Lerngruppe entfernen, in der sie fehlen — in ihren anderen Lerngruppen "
                                  + "verbleiben sie, ebenso ihre Einträge")
                        }
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
        if amBlattNeuePlanung {
            ziel = .jeKlasse
        } else if let vorwahl, gruppen.contains(where: { $0.id == vorwahl }) {
            ziel = .gruppe(vorwahl)
        } else if zuordnung.klasse != nil {
            ziel = .jeKlasse
        } else {
            ziel = .neu
        }
    }
}

extension ImportBogen {
    /// Wer beim Klick noch in einer anderen aktiven Lerngruppe steht — einer, in der er nicht fehlt. Am Stand des
    /// Klicks gerechnet, nicht an dem der Vorschau: Wer sonst nirgends mehr steht, bleibt (Z-AT3-02).
    nonisolated static func nochAnderswo(_ liste: [Fehlmitgliedschaft], in bestand: Lernendenbestand) -> [Fehlmitgliedschaft] {
        var fehlgruppen: [String: Set<String>] = [:]
        for f in liste { fehlgruppen[f.person, default: []].insert(f.gruppe) }
        return liste.filter { f in
            bestand.lerngruppen.contains { g in
                g.archiviert.isEmpty && g.mitglieder.contains(f.person) && fehlgruppen[f.person]?.contains(g.id) != true
            }
        }
    }

    /// Die Sätze zu den Fehlenden (E368): alle, die in der Datei fehlen, und wie viele davon in einer anderen Lerngruppe
    /// stehen — die werden nicht archiviert, nur aus dieser genommen. `nil`, wo es nichts zu sagen gibt.
    nonisolated static func fehlendeTexte(_ bilanz: Importbilanz,
                                          personenname: (String) -> String) -> (fehlen: String?, anderswo: String?) {
        // Je Person einmal — mit „Je Klasse“ kann jemand in mehreren Zielgruppen fehlen.
        var personen = bilanz.fehlende
        for f in bilanz.fehlendeAnderswo where !personen.contains(f.person) { personen.append(f.person) }
        guard !personen.isEmpty else { return (nil, nil) }
        let n = personen.count
        let fehlen = "In der Datei \(n == 1 ? "fehlt 1 bisheriges Mitglied" : "fehlen \(n) bisherige Mitglieder"): "
            + personen.map(personenname).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .joined(separator: "; ") + "."
        let k = Set(bilanz.fehlendeAnderswo.map(\.person)).subtracting(bilanz.fehlende).count
        guard k > 0 else { return (fehlen, nil) }
        // Erst der Knopf nimmt heraus (Z-AT3-03); Wortlaut des Nutzers je Fall.
        let knopf = "„Fehlende aus der Lerngruppe nehmen“ entfernt sie nur dort, wo sie"
        if k == 1 {
            return (fehlen, n == 1
                    ? "1 Person steht noch in einer anderen Lerngruppe und wird nicht archiviert; \(knopf) fehlt."
                    : "1 davon steht noch in einer anderen Lerngruppe — sie wird nicht archiviert; \(knopf) fehlt.")
        }
        return (fehlen, "\(k == n ? "Alle \(k)" : "\(k)") davon stehen noch in einer anderen Lerngruppe — sie werden "
                + "nicht archiviert; \(knopf) fehlen.")
    }
}
