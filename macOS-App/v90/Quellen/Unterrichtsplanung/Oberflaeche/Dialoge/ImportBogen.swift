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
    /// Je Kodierung und Trenner einmal ausgewertet, je Kopfzeile und Zuordnung einmal gelesen (R86-04) — der Körper fragt
    /// Tabelle und Lesung vielfach, die Spaltenwahl je Spalte; vorher zerlegte jeder Zugriff die ganze Datei neu.
    @State private var vorrat = Importvorrat()

    private var auswertung: Importvorrat.Auswertung { vorrat.auswertung(quelle.daten, kodierung: kodierung, trenner: trenner) }
    private var text: IServImport.Text? { auswertung.text }
    private var erkannterTrenner: IServImport.Trenner { auswertung.erkannterTrenner }
    private var tabelle: [[String]] { auswertung.zerlegung.zeilen }
    private var spaltenzahl: Int { auswertung.spaltenzahl }
    private var lesung: IServImport.Lesung { vorrat.lesung(auswertung, kopfzeile: kopfzeile, zuordnung: zuordnung) }
    /// Ein Anführungszeichen, das bis zum Ende offen bleibt (E871 a), oder ein Feld über ein Zeilenende (E892 a) — dann
    /// wird nichts importiert; das hier sind die Wortlaute dazu.
    private var sperre: (fuss: String, zeile: String, hilfe: String)? { Self.sperrtexte(auswertung.zerlegung) }

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
                // Bei offenem Anführungszeichen statt der Zahlen der Grund — die Zahlen zählten nur den Teil davor (E885, E892).
                Text(sperre?.zeile
                     ?? (amBlattNeuePlanung ? "Übernommen wird mit „Planung anlegen“ — die Lerngruppen entstehen mit der Planung."
                         : importziel.map { z in
                             vorrat.vorschau(auswertung, kopfzeile: kopfzeile, zuordnung: zuordnung, ziel: z) { vorschau(lesung, z) }.kurz
                         } ?? ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Fussluecke()
                Button("Abbrechen") { schliessen() }
                    .keyboardShortcut(.cancelAction)
                Button(amBlattNeuePlanung ? "Übernehmen" : "Importieren") {
                    guard sperre == nil, let importziel else { return }
                    if amBlattNeuePlanung {
                        _ = importieren(lesung, importziel, true)
                        schliessen()
                    } else {
                        bilanz = importieren(lesung, importziel, importziel == .jeKlasse && binden)
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                // Am Blatt „Neue Planung“ zählt nur, wer eine Klasse trägt — ohne eine entstünde nichts. Ein offenes
                // Anführungszeichen sperrt den Import ganz (E871 a, E892 a), mit dem Grund am Knopf (E885).
                .disabled(sperre != nil || importziel == nil || !zuordnung.vollstaendig || lesung.zeilen.isEmpty
                          || (amBlattNeuePlanung && !lesung.zeilen.contains { !$0.klasse.isEmpty }))
                .hilfe(sperre?.hilfe ?? "", gesperrt: sperre != nil)
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
            if sperre != nil || !lesung.fehler.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if let sperre { Text(sperre.fuss) }
                    // Ohne Import ist nichts übergangen, und der offene Datensatz stünde hier mit falschem Grund (E891, Z-AY2-06).
                    if sperre == nil, !lesung.fehler.isEmpty {
                        Text("Übergangen: " + lesung.fehler.prefix(4).map { "Zeile \($0.nummer) (\($0.grund.ohneSchlusspunkt))" }
                            .joined(separator: ", ") + (lesung.fehler.count > 4 ? " …" : ""))
                    }
                }
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

extension ImportBogen {
    /// Die Wortlaute bei einem Anführungszeichen, das bis zum Ende der Datei offen bleibt (E871 a, E885): der Absatz unter
    /// der Vorschau, die Zeile neben den Knöpfen und die Hilfe am gesperrten Knopf.
    nonisolated static func offenTexte(_ zeile: Int) -> (fuss: String, zeile: String, hilfe: String) {
        ("Zeile \(zeile) öffnet ein Anführungszeichen, das bis zum Ende der Datei nicht geschlossen wird — der Rest der "
            + "Datei stünde in einem einzigen Feld. Bitte die Datei prüfen; so wird nichts importiert.",
         "Offenes Anführungszeichen in Zeile \(zeile) — nichts wird importiert.",
         "Die Datei öffnet in Zeile \(zeile) ein Anführungszeichen, das nicht geschlossen wird.")
    }

    /// Die Wortlaute bei einem Feld über ein Zeilenende (E892 a): ein Anführungszeichen, das erst in einer späteren Zeile
    /// schließt — wie bei `offenTexte` der Absatz, die Zeile neben den Knöpfen und die Hilfe am gesperrten Knopf.
    nonisolated static func ueberZeilenendeTexte(_ zeile: Int) -> (fuss: String, zeile: String, hilfe: String) {
        ("Zeile \(zeile) öffnet ein Anführungszeichen, das erst in einer späteren Zeile schließt — die Zeilen dazwischen "
            + "stünden in einem einzigen Feld. Bitte die Datei prüfen; so wird nichts importiert.",
         "Anführungszeichen über das Zeilenende in Zeile \(zeile) — nichts wird importiert.",
         "Die Datei öffnet in Zeile \(zeile) ein Anführungszeichen, das erst in einer späteren Zeile schließt.")
    }

    /// Was den Import sperrt, mit seinen Wortlauten — `nil`, wenn nichts. Ein Anführungszeichen, das bis zum Ende offen
    /// bleibt (E871 a), sagt mehr als eines, das später schließt (E892 a), und geht vor.
    nonisolated static func sperrtexte(_ zerlegung: IServImport.Zerlegung) -> (fuss: String, zeile: String, hilfe: String)? {
        if let offen = zerlegung.offenesAnfuehrungszeichen { return offenTexte(offen) }
        return zerlegung.feldUeberZeilenende.map(ueberZeilenendeTexte)
    }
}

/// Was der Bogen aus seiner Datei liest — gemerkt, solange Kodierung und Trenner bleiben, die Lesung, solange auch
/// Kopfzeile und Zuordnung bleiben, die Bilanz der Vorschau, solange dazu das Ziel bleibt (R86-04, Z-AY2-01). Kein
/// Zustand, den die Oberfläche beobachtet: nur ein Vorrat wie `Lernendendienst.verzeichnis`. Vorbedingungen (Z-AY2-03):
/// eine Datei je Vorrat — jeder Bogen bekommt seinen eigenen (`.sheet(item:)` mit eigener Kennung); und der Entwurf
/// hinter der Vorschau ändert sich nicht, solange der Bogen sie zeigt — erst „Importieren“ ändert ihn, danach zeigt der
/// Bogen die Bilanz des Imports. Belegt (Z-AY2N-01, Z-AY2N2-01): Der Entwurf des Blatts wechselt nach `laden()` nur über
/// `stand(_:)` — aus einem Handgriff, den das Blatt unter dem Bogen nicht annimmt (am Lauf: ⌘⏎ am Importbogen mit
/// getippter Liste dahinter, Lernendenprobe vor AP13), aus „Fehlende archivieren“ und „Herausnehmen“, die erst die Bilanz
/// zeigt, oder aus ⌘Z und ⇧⌘Z, die der Speicher bei offenem Bogen abweist (E776; am Lauf ⌘Z am Bogen
/// „Rückmeldungsliste“, Teil E — Importbogen und ⇧⌘Z über dieselbe Bedingung `bogenDarauf`). Am Blatt „Neue Planung“
/// rechnet die Vorschau nichts. Lesung und Bilanz gelten nur zur Auswertung mit ihrer Nummer.
@MainActor
final class Importvorrat {
    struct Auswertung {
        /// Je neuer Auswertung eine neue Nummer — Lesung und Bilanz hängen an ihr.
        let nummer: Int
        let text: IServImport.Text?
        let erkannterTrenner: IServImport.Trenner
        let zerlegung: IServImport.Zerlegung
        let spaltenzahl: Int
    }

    private var nummer = 0
    private var auswertungFuer: (kodierung: IServImport.Kodierung?, trenner: IServImport.Trenner?)?
    private var gemerkt: Auswertung?
    private var lesungFuer: (auswertung: Int, kopfzeile: Bool, zuordnung: IServImport.Zuordnung)?
    private var gelesen: IServImport.Lesung?
    private var vorschauFuer: (auswertung: Int, kopfzeile: Bool, zuordnung: IServImport.Zuordnung, ziel: Importziel)?
    private var vorgeschaut: Importbilanz?

    func auswertung(_ daten: Data, kodierung: IServImport.Kodierung?, trenner: IServImport.Trenner?) -> Auswertung {
        if let gemerkt, let fuer = auswertungFuer, fuer.kodierung == kodierung, fuer.trenner == trenner { return gemerkt }
        let text = IServImport.entschluesseln(daten, kodierung: kodierung)
        let inhalt = text?.inhalt ?? ""
        let erkannt = IServImport.trennerErkennen(inhalt)
        let zerlegung = IServImport.zerlegung(inhalt, trenner: trenner ?? erkannt)
        nummer += 1
        let neu = Auswertung(nummer: nummer, text: text, erkannterTrenner: erkannt, zerlegung: zerlegung,
                             spaltenzahl: zerlegung.zeilen.prefix(20).map(\.count).max() ?? 0)
        gemerkt = neu
        auswertungFuer = (kodierung, trenner)
        return neu
    }

    func lesung(_ auswertung: Auswertung, kopfzeile: Bool, zuordnung: IServImport.Zuordnung) -> IServImport.Lesung {
        if let gelesen, let fuer = lesungFuer, fuer.auswertung == auswertung.nummer, fuer.kopfzeile == kopfzeile,
           fuer.zuordnung == zuordnung { return gelesen }
        let neu = IServImport.lesen(auswertung.zerlegung.zeilen, kopfzeile: kopfzeile, zuordnung: zuordnung)
        gelesen = neu
        lesungFuer = (auswertung.nummer, kopfzeile, zuordnung)
        return neu
    }

    /// Die Bilanz der Vorschau — `rechnen` nur, wenn Auswertung, Kopfzeile, Zuordnung oder Ziel gewechselt haben.
    func vorschau(_ auswertung: Auswertung, kopfzeile: Bool, zuordnung: IServImport.Zuordnung, ziel: Importziel,
                  rechnen: () -> Importbilanz) -> Importbilanz {
        if let vorgeschaut, let fuer = vorschauFuer, fuer.auswertung == auswertung.nummer, fuer.kopfzeile == kopfzeile,
           fuer.zuordnung == zuordnung, fuer.ziel == ziel { return vorgeschaut }
        let neu = rechnen()
        vorgeschaut = neu
        vorschauFuer = (auswertung.nummer, kopfzeile, zuordnung, ziel)
        return neu
    }
}
