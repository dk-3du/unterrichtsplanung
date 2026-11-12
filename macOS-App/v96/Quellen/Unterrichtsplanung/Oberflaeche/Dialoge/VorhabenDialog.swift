// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct VorhabenDialog: View {
    let start: VorhabenEntwurf

    /// 980 × 820 (E1103); auf kleinem Bildschirm niedriger (E1150).
    static let blatthoehe: CGFloat = 820
    /// Die Höhe dieses Blatts, beim ersten Zeichnen festgelegt (E1150) — auch für den Material-Bogen darauf (R-BG8b-01).
    @State private var blattmass = Blatthoehe(VorhabenDialog.blatthoehe)

    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @State private var entwurf: VorhabenEntwurf
    @State private var ablageAktiv = false
    @State private var verwerfenFragen = false
    /// Die Antwort auf das eigene Alert läuft erst nach dessen Schließen; bis dahin bleiben ⎋/„Abbrechen“
    /// und „Übernehmen“ ohne Wirkung (Z-AU4b-01/-02).
    @State private var antwortAussteht = false
    /// Steht unter dem Datumsfeld, bis ein zulässiger Tag gewählt ist.
    @State private var sperrhinweis = ""
    /// Steht unter den Wochentagen, nachdem ein Wochenwechsel das Datum
    /// verfallen ließ — bis der nächste Tag gewählt oder getippt ist.
    @State private var wochenhinweis = ""
    /// Was im Suchfeld der Personen eines Termins steht (E295).
    @State private var personensuche = ""
    /// Die Schreibmarke beim Öffnen ist gesetzt — danach nie wieder von selbst.
    @State private var anfangsfokusGesetzt = false
    @FocusState private var titelFokus: Bool
    /// „Hausaufgabe hinzufügen …“ öffnet auf „Hausaufgabe“ (E653) — die Schreibmarke dann in die Zeile (Z-AW3n-06).
    @FocusState private var hausaufgabenFokus: Bool
    @FocusState private var linkFokus: UUID?

    init(start: VorhabenEntwurf) {
        self.start = start
        _entwurf = State(initialValue: start)
    }

    private var planung: Planung? { speicher.planung }

    var body: some View {
        // Einmal je Body-Durchlauf statt zweimal: Wochenliste und Lagen sind teuer.
        let stand = planung?.wochenstand() ?? .leer
        let gewaehlt = speicher.vorhabenReiter

        // Blatt mit Seitenleiste (v95, E1101–E1111): die bisherigen sieben Reiter als Einträge einer
        // Seitenleiste — in ihrer Folge (Nutzer, 20.10.2026), je mit Symbol, das Kennzeichen (E373) als Plakette —, rechts
        // der Inhalt des gewählten als gruppiertes `Form`. 980 × 820 (Nutzer, 07.11.2026: Platz für die breitere Leiste samt
        // Zählern, „Grundlegendes“ ohne Rollen). Liegt der Material-Bogen darauf, zeigt nur er die Meldungen — wie die Bögen
        // am Blatt „Lernende“ (E490 a).
        Seitenleistenrahmen(titel: entwurf.istNeu ? "Neues Vorhaben" : "Vorhaben bearbeiten",
                            unterzeile: unterzeile(stand: stand),
                            eintraege: Vorhabenreiter.allCases,
                            auswahl: Binding(get: { speicher.vorhabenReiter },
                                             set: { speicher.vorhabenReiter = $0 }),
                            name: \.titel, symbol: \.symbol, plakette: plakette,
                            breite: 980, hoehe: blattmass.wert,
                            beimSchliessen: abbrechen,
                            meldungsblatt: speicher.materialblattOffen ? nil : .vorhaben,
                            zeileAbgegeben: speicher.materialblattOffen) {
            seite(gewaehlt, stand: stand)
        } fuss: {
            if !entwurf.istNeu {
                Button(role: .destructive) {
                    if let id = entwurf.vorhabenId { speicher.vorhabenLoeschen(id) }
                } label: {
                    Label("Löschen", systemImage: Zeichen.muell)
                }
                .buttonStyle(.glass)
            }
            Fussluecke()
            Button("Abbrechen") { abbrechen() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button("Übernehmen") { uebernehmen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        // Das Material-Blatt von 3ducation.org — ein Bogen an diesem Blatt (v71).
        .sheet(isPresented: Binding(get: { speicher.materialblattOffen },
                                    set: { speicher.materialblattOffen = $0 })) {
            MaterialDialog(entwurf: $entwurf, blatthoehe: blattmass.wert)
        }
        // Der Hinweis gilt der getroffenen Wahl; nach einem Wechsel sagt er
        // über die neue nichts mehr aus — `bestehendeSperre` rechnet sie nach.
        .onChange(of: entwurf.klasseId) { _, _ in sperrhinweis = "" }
        // Ein Wochenwechsel lässt Wochentag und Datum verfallen — wie beim
        // Verschieben im Raster (`Vorhaben.wocheWechseln`), nur mit dem
        // Hinweis an Ort und Stelle statt als Meldung.
        .onChange(of: entwurf.woche) { alt, neu in
            sperrhinweis = ""
            // Ein Termin behält seinen Wochentag (E293) — wie beim Verschieben im Raster.
            if entwurf.termin, let tag = entwurf.datum, alt != neu {
                entwurf.datum = tag.plus(tage: (neu - alt) * 7)
                return
            }
            guard alt != neu, entwurf.datum != nil else { return }
            entwurf.datum = nil
            wochenhinweis = "Durch den Wechsel in eine andere Woche wurden Wochentag und Datum "
                + "zurückgesetzt."
        }
        // Ein neu gesetztes Datum — geklickt oder getippt — macht den Hinweis
        // gegenstandslos; das Verfallen selbst (auf nil) lässt ihn stehen.
        .onChange(of: entwurf.datum) { _, neu in if neu != nil { wochenhinweis = "" } }
        // Das eigene Alert: „Verwerfen“ schließt das Blatt — erst nach dem Schließen des Alerts (B95, E433).
        .alert("Die Änderungen an diesem Vorhaben verwerfen?", isPresented: $verwerfenFragen) {
            Button("Weiter bearbeiten", role: .cancel) {}
            Button("Verwerfen", role: .destructive) { nachDemAlert { schliessen() } }
        }
        .rueckfrage(speicher, ort: .vorhaben)
    }

    // ── Seitenleiste ──────────────────────────────────────────────────────

    /// Das Kennzeichen des Eintrags (E373) als Plakette: die Zahl ohne „· “ davor — auch „0“ am Termin ohne Person
    /// (E572) —, sonst „•“ bzw. „✓“; nil, solange der Eintrag nichts trägt. Gezeichnet wird sie vom Rahmen, in der Zeile.
    private func plakette(_ reiter: Vorhabenreiter) -> String? {
        entwurf.kennzeichen(reiter, verwaltungOffen: verwaltungOffen).map { zeichen in
            zeichen.hasPrefix("· ") ? String(zeichen.dropFirst(2)) : zeichen
        }
    }

    // ── Seiten ────────────────────────────────────────────────────────────

    /// Der Inhalt des gewählten Eintrags — je Eintrag ein eigenes gruppiertes `Form`: Neben der Leiste ist die Spalte
    /// kaum breiter als die 704 pt, bei denen ein `Form` seine Kästen deckelt (E733 a); die Kästen von Hand entfallen.
    @ViewBuilder
    private func seite(_ reiter: Vorhabenreiter, stand: Wochenstand) -> some View {
        switch reiter {
        case .grundlegendes: blattform { grundlegendes(stand) }
        case .kommentar: blattform { kommentarbereich }
        case .pruefung: blattform { pruefungsbereich }
        case .termin: blattform { terminbereich }
        case .hausaufgabe: blattform { hausaufgabenbereich }
        case .material: blattform { materialbereich }
        case .links:
            blattform {
                linkbereich
                websitebereich
            }
        }
    }

    /// Das gemeinsame `Seitenform` (Schalter als Schalter; die Wochentage bleiben Kästchen, `Wochentagskaestchen`) mit dem
    /// Anfangsfokus (R-BG5-08).
    private func blattform<Inhalt: View>(@ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        Seitenform { inhalt() }
            .onAppear(perform: anfangsfokusSetzen)
    }

    /// Die Schreibmarke beim Öffnen (Z-AW3n-06): auf „Hausaufgabe“ in deren Zeile, sonst in den Titel — einmal je Blatt,
    /// sobald die erste Seite steht. Der Inhalt entsteht mit seiner Spalte; vom Blatt aus gesetzt, fände der Fokus sein
    /// Feld womöglich noch nicht.
    private func anfangsfokusSetzen() {
        guard !anfangsfokusGesetzt else { return }
        anfangsfokusGesetzt = true
        if speicher.vorhabenReiter == .hausaufgabe { hausaufgabenFokus = true } else { titelFokus = true }
    }

    // ── Grundlegendes ─────────────────────────────────────────────────────

    /// Alles, was früher über dem Kommentar stand — in drei Abschnitten.
    @ViewBuilder
    private func grundlegendes(_ stand: Wochenstand) -> some View {
        Section {
            TextField("Titel", text: $entwurf.titel,
                      prompt: Text("z. B. Stoffe und ihre Eigenschaften"))
                .focused($titelFokus)

            VStack(alignment: .leading, spacing: 6) {
                Text("Weiterführende Informationen")
                Textfeld(text: $entwurf.text, mindesthoehe: 60,
                         beschriftung: "Weiterführende Informationen")
            }
        } header: {
            Text("Inhalt")
        }

        Section {
            Picker("Klasse/Kurs", selection: $entwurf.klasseId) {
                ForEach(planung?.klassen ?? []) { klasse in
                    Text(klasse.beschriftung).tag(klasse.id)
                }
            }
            Picker("Woche", selection: $entwurf.woche) {
                ForEach(stand.wochen) { woche in
                    Text(wochentext(woche, schulwoche: stand.schulwoche(woche)))
                        .tag(woche.nummer)
                }
            }

            wochentagsbereich
            datumsbereich
        } header: {
            Text("Einordnung")
        }

        Section {
            Toggle("Durchgeführt", isOn: $entwurf.erledigt)
            Toggle(isOn: $entwurf.dringend) {
                Text("Als dringlich kennzeichnen")
                Text(VorhabenDialog.dringlichHilfe)
            }
            .help(VorhabenDialog.dringlichHilfe)
            // Entweder Prüfung, Korrektur, Vorbereitung oder Termin: gesperrt statt umgeschaltet —
            // ein Klick nimmt nie still einen Prüfungstermin weg. Lösen bleibt frei (E1080, Z-BE3-04).
            // Die Unterzeile ist immer genau ein `Text`: Wechselt nur ihr Wortlaut, bleibt die Zeile dieselbe.
            Toggle(isOn: $entwurf.vorbereitung) {
                Text("Als Vorbereitung kennzeichnen")
                Text(vorbereitungHilfe)
            }
            .disabled(entwurf.vorbereitungGesperrt)
            // Gesperrt zeigt SwiftUI keine Hilfe — eine durchsichtige Fläche trägt sie (H1, Z-AX6a-01; Z-BE5-01).
            .hilfe(vorbereitungHilfe, gesperrt: entwurf.vorbereitungGesperrt)
            Toggle(isOn: $entwurf.korrektur) {
                Text("Als Korrektur kennzeichnen")
                Text(korrekturHilfe)
            }
            .disabled(entwurf.korrekturGesperrt)
            // Wie bei der Vorbereitung: gesperrt trägt die durchsichtige Fläche die Hilfe (E1084).
            .hilfe(korrekturHilfe, gesperrt: entwurf.korrekturGesperrt)
        } header: {
            Text("Stand und Kennzeichen")
        }
    }

    static let dringlichHilfe = "Dringliche Vorhaben tragen im Raster einen gelben Rahmen."

    private var vorbereitungHilfe: String {
        entwurf.vorbereitungGesperrt
            ? VorhabenDialog.entwederOder
            : "Vorbereitungen tragen im Raster einen gestrichelten blauen Rahmen und die Zeile „Vorbereitung“."
    }

    private var korrekturHilfe: String {
        entwurf.korrekturGesperrt
            ? VorhabenDialog.entwederOder
            : "Korrekturen tragen im Raster einen gestrichelten roten Rahmen und die Zeile „Korrektur“."
    }

    // ── Wochentag ─────────────────────────────────────────────────────────

    /// Die Unterrichtstage der gewählten Klasse bzw. des Kurses — sie werden
    /// hervorgehoben, wählbar sind alle fünf: Ein Vorhaben kann auch abseits
    /// des Unterrichts liegen.
    private var unterrichtstage: Set<Wochentag> {
        planung?.klasse(entwurf.klasseId)?.unterrichtstage ?? []
    }

    /// Fünf Kästchen, von denen höchstens eines angekreuzt ist: Der Wochentag
    /// **ist** das Datum (`Vorhaben.wochentag`); ein Klick setzt den Tag der
    /// gewählten Woche, ein zweiter Klick nimmt ihn wieder. Keiner ist Pflicht.
    /// Der Hinweis steht als Unterzeile unter „Wochentag“ (E1122).
    private var wochentagsbereich: some View {
        LabeledContent {
            HStack(spacing: 6) {
                ForEach(Wochentag.allCases) { tag in
                    Wochentagskaestchen(tag: tag,
                                        unterricht: unterrichtstage.contains(tag),
                                        gewaehlt: entwurf.wochentag == tag) { an in
                        wochenhinweis = ""
                        entwurf.datum = an ? tag.datum(inWocheVon: wochenmontag) : nil
                    }
                }
            }
        } label: {
            Text("Wochentag")
            wochentagsunterzeile
        }
    }

    /// Nach einem Wochenwechsel der Hinweis, sonst die Unterrichtstage — immer genau ein `Text`: Wechselt nur der
    /// Wortlaut, bleibt die Zeile dieselbe, und ein Kästchen behält den Fokus.
    private var wochentagsunterzeile: Text {
        wochenhinweis.isEmpty
            ? Text(unterrichtstageText)
            : Text("\(Image(systemName: Zeichen.hinweis)) \(wochenhinweis)")
    }

    private var unterrichtstageText: String {
        let name = planung?.klasse(entwurf.klasseId)?.name ?? "diese Klasse bzw. diesen Kurs"
        let tage = unterrichtstage
        let folge = "Ein Wochentag setzt das Datum in der gewählten Woche; beides bleibt freiwillig."
        return tage.isEmpty
            ? "Für \(name) sind unter „Lernende, Klassen/Kurse und Fächer“ keine Unterrichtstage "
              + "hinterlegt. " + folge
            : "Hervorgehoben sind die Unterrichtstage von \(name) (\(tage.beschriftung)). " + folge
    }

    // ── Datum ─────────────────────────────────────────────────────────────

    /// Der Tag, an dem das Vorhaben stattfindet — unabhängig vom
    /// Prüfungstermin, der eigenen Regeln folgt.
    @ViewBuilder
    private var datumsbereich: some View {
        LabeledContent("Datum") {
            HStack(spacing: 8) {
                if entwurf.datum == nil {
                    Button("Datum festlegen") { entwurf.datum = wochenmontag }
                        .buttonStyle(.link)
                    Text("keines").foregroundStyle(.secondary)
                } else {
                    Datumsfeld(tag: Binding(get: { entwurf.datum ?? wochenmontag },
                                            set: { entwurf.datum = $0 }))
                    Button("Ohne Datum") { entwurf.datum = nil }
                        .buttonStyle(.link)
                }
            }
        }
        // Eine eigene Zeile, keine Unterzeile: Die Warnung kommt und geht, während im Datumsfeld getippt wird. Warnzeilen im Kasten
        // haben eine Erscheinung (E1122): `Erlaeuterung` mit Warnzeichen.
        if ausserhalbDerWoche(entwurf.datum) {
            Erlaeuterung("Das Datum liegt außerhalb der gewählten Woche.", warnung: true)
        }
    }

    // ── Kommentar und Hausaufgabe ─────────────────────────────────────────

    /// Was im Unterricht daraus wurde. Die Erläuterung steht im Kasten, als graue Unterzeile unter dem Feld, auf das sie
    /// sich bezieht (Nutzer, 07.11.2026: „Erläuterungen stets im grau hinterlegten Feld …, nicht darunter“).
    private var kommentarbereich: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Textfeld(text: $entwurf.kommentar, mindesthoehe: 160,
                         beschriftung: "Kommentar zum Verlauf")
                Erlaeuterung("Wie das Vorhaben gelaufen ist — getrennt von den weiterführenden "
                             + "Informationen, die sagen, was geplant war. Dieses Feld füllt auch die "
                             + "Web App; ihr Stand wird beim Start, nach dem Aufwachen des Macs aus dem "
                             + "Ruhezustand und über „Stand der Web App abrufen“ übernommen.")
            }
        } header: {
            Text("Kommentar zum Verlauf")
        }
    }

    /// Eine Hausaufgabe am Vorhaben — ein Merkmal, kein anderes Vorhaben —
    /// samt einer Zeile. Die Zeile gibt es nur mit Schalter; aus lässt sie bis
    /// zum Übernehmen stehen, übernommen wird dann eine leere.
    private var hausaufgabenbereich: some View {
        Section {
            Toggle(isOn: $entwurf.hausaufgabe) {
                Text("Hausaufgabe hinzufügen")
                Text(VorhabenDialog.hausaufgabeHilfe)
            }
            .help(VorhabenDialog.hausaufgabeHilfe)
            if entwurf.hausaufgabe {
                // Die Erläuterung als graue Unterzeile der Zeile, wie bei „Wochentag“ (Nutzer, 07.11.2026).
                LabeledContent {
                    TextField("Hausaufgabe", text: $entwurf.hausaufgabenText,
                              prompt: Text("z. B. S. 42, Nr. 3–5 (optional)"))
                        .labelsHidden()
                        .lineLimit(1)
                        .focused($hausaufgabenFokus)
                        .accessibilityLabel("Hausaufgabe, eine Zeile, optional")
                } label: {
                    Text("Hausaufgabe")
                    Text("Die Zeile ist freiwillig — sie steht in der Tagesliste, im Ausdruck "
                         + "und im Detail der Web App; im Raster zeigt die Kachel nur das Zeichen.")
                }
            }
        }
    }

    static let hausaufgabeHilfe = "Das Vorhaben bekommt eine Hausaufgabe — mit Zeichen im Raster, in der "
        + "Tagesliste und in der Web App."

    static let entwederOder = "Ein Vorhaben ist entweder Prüfung, Korrektur, Vorbereitung oder Termin."

    /// Kennzeichnung als Prüfung samt Termin.
    private var pruefungsbereich: some View {
        Section {
            Toggle(isOn: Binding(
                get: { entwurf.pruefung },
                set: { an in
                    entwurf.pruefung = an
                    sperrhinweis = ""
                    guard an, entwurf.pruefungstag == nil else { return }
                    terminSetzen(wochenmontag)
                })) {
                Text("Als Prüfung führen")
                // Ob gesperrt, ändert sich nicht auf dieser Seite — die Unterzeile kommt und geht nicht unter der Hand.
                if entwurf.pruefungGesperrt { Text(VorhabenDialog.entwederOder) }
            }
            .disabled(entwurf.pruefungGesperrt)
            // Gesperrt trägt die durchsichtige Fläche die Hilfe (E1084).
            .hilfe(entwurf.pruefungGesperrt ? VorhabenDialog.entwederOder : "", gesperrt: entwurf.pruefungGesperrt)

            if entwurf.pruefung {
                LabeledContent("Termin") {
                    HStack(spacing: 8) {
                        // Kein Ersatzdatum anzeigen, solange keiner gespeichert ist:
                        // Der Wochenmontag läse sich sonst wie ein gesetzter Termin.
                        if entwurf.pruefungstag == nil {
                            Button("Termin festlegen") { terminSetzen(ersterZulaessigerTermin) }
                                .buttonStyle(.link)
                            Text("keiner").foregroundStyle(.secondary)
                        } else {
                            Datumsfeld(tag: Binding(
                                get: { entwurf.pruefungstag ?? wochenmontag },
                                set: { terminSetzen($0) }))
                            Button("Ohne Termin") {
                                entwurf.pruefungstag = nil
                                sperrhinweis = ""
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                if let hinweis = sperrhinweis.isEmpty ? bestehendeSperre?.abweisung : sperrhinweis {
                    Erlaeuterung(hinweis, warnung: true)
                } else if entwurf.pruefungstag == nil {
                    Erlaeuterung("Noch kein Termin — die Prüfung steht in der Übersicht unter "
                                 + "„ohne Termin“.")
                } else if ausserhalbDerWoche(entwurf.pruefungstag) {
                    Erlaeuterung("Der Termin liegt außerhalb der gewählten Woche.", warnung: true)
                }
                if let sperren = speicher.planung?.sperrzeiten, !sperren.isEmpty {
                    Erlaeuterung(sperren.count == 1
                                 ? "Ein Sperrzeitraum ist hinterlegt — zu sehen unter „Prüfungen“ (⌘R)."
                                 : "\(sperren.count) Sperrzeiträume sind hinterlegt — zu sehen unter "
                                   + "„Prüfungen“ (⌘R).")
                }
            }
        } header: {
            Text("Prüfung")
        }
    }

    // ── Termin (E293, E295) ───────────────────────────────────────────────

    /// Die Lernendenverwaltung dieser Planung ist offen — sonst gibt es keine Termine.
    private var verwaltungOffen: Bool {
        speicher.lernende.schreibbar && speicher.lernende.bestand?.planung == planung?.erstellt
    }

    private var gewaehltePersonen: [Lernender] {
        entwurf.terminpersonen.compactMap { speicher.lernende.verzeichnis?.person($0) }
    }

    private var treffer: [Lernender] {
        guard let verzeichnis = speicher.lernende.verzeichnis else { return [] }
        return Self.treffer(personensuche, in: verzeichnis, ausser: entwurf.terminpersonen,
                            zuerst: Self.zuerst(speicher.lernende.bestand, planung: planung?.erstellt, klasseId: entwurf.klasseId))
    }

    /// Wer in der Terminsuche zuerst steht: die Mitglieder aller Lerngruppen der Zeile (E670).
    nonisolated static func zuerst(_ bestand: Lernendenbestand?, planung: String?, klasseId: String) -> Set<String> {
        guard let bestand, let planung else { return [] }
        return Set(bestand.gruppen(an: Zeilenbindung(planung: planung, klasseId: klasseId)).flatMap(\.mitglieder))
    }

    /// Treffer der Suche: aktive Personen, deren Name passt — nach derselben Regel wie die Suche im Blatt
    /// „Lernende“ (E360, E481); die Mitglieder der Lerngruppen dieser Zeile zuerst (`zuerst`); höchstens acht.
    nonisolated static func treffer(_ suche: String, in verzeichnis: Lernendenverzeichnis, ausser: [String],
                                    zuerst mitglieder: Set<String>) -> [Lernender] {
        guard !Lernendenverzeichnis.suchworte(suche).isEmpty else { return [] }
        let schon = Set(ausser)  // je Tastendruck: eine Menge statt der Liste der Terminpersonen (Z-BB8-W2, Hinweis)
        return verzeichnis.alle
            .filter { p in !schon.contains(p.id) && Lernendenverzeichnis.trifft(p, suche) }
            .sorted { (mitglieder.contains($0.id) ? 0 : 1) < (mitglieder.contains($1.id) ? 0 : 1) }
            .prefix(8)
            .map { $0 }
    }

    private func gruppentext(_ person: Lernender) -> String {
        let gruppen = speicher.lernende.verzeichnis?.gruppen(von: person.id).filter { $0.archiviert.isEmpty } ?? []
        return gruppen.isEmpty ? "" : " · " + gruppen.map(\.beschriftung).joined(separator: ", ")
    }

    /// Die Hilfe am Schalter „Als Termin führen“ — leer mit offener Verwaltung, solange nichts anderes vorgeht.
    private var terminSchalterHilfe: String {
        entwurf.pruefung || entwurf.korrektur || entwurf.vorbereitung ? VorhabenDialog.entwederOder
            : entwurf.terminSchalterHilfe(verwaltungOffen: verwaltungOffen)
    }

    /// Kennzeichnung als Termin: Uhrzeit und Personen; Titel und Tag sind die des Vorhabens.
    private var terminbereich: some View {
        Section {
            Toggle(isOn: Binding(
                get: { entwurf.termin },
                set: { an in
                    entwurf.termin = an
                    // Ein Termin braucht einen Tag — vorgeschlagen der erste Unterrichtstag der Woche.
                    if an, entwurf.datum == nil {
                        entwurf.datum = unterrichtstage.sorted().first.map { $0.datum(inWocheVon: wochenmontag) }
                            ?? wochenmontag
                    }
                })) {
                Text("Als Termin führen")
                // Hängt an der Verwaltung und an Prüfung, Korrektur, Vorbereitung — nichts davon ändert sich auf dieser Seite.
                if !terminSchalterHilfe.isEmpty { Text(terminSchalterHilfe) }
            }
            .disabled(entwurf.terminSchalterGesperrt(verwaltungOffen: verwaltungOffen))
            // Ohne offene Verwaltung: am bedienbaren Schalter eines bestehenden Termins ein eigener Text (E778). Gesperrt
            // trägt eine durchsichtige Fläche die Hilfe (H1; Z-AX6a-01).
            .hilfe(terminSchalterHilfe, gesperrt: entwurf.terminSchalterGesperrt(verwaltungOffen: verwaltungOffen))

            if entwurf.termin {
                // Ohne offene Verwaltung bleibt ein bestehender Termin, wie er war (E721) — auch seine Uhrzeit; das
                // Feld ist dann gesperrt, statt eine Eingabe still fallen zu lassen (Z-AW3n-01).
                let uhrzeitSperre = entwurf.uhrzeitSperre(verwaltungOffen: verwaltungOffen)
                TextField("Uhrzeit", text: $entwurf.terminzeit, prompt: Text("hh:mm"))
                    .disabled(uhrzeitSperre != nil)
                    .hilfe(uhrzeitSperre ?? "", gesperrt: uhrzeitSperre != nil)  // gesperrt sonst unsichtbar (H1; Z-AX6a-01)
                if verwaltungOffen {
                    LabeledContent("Personen") {
                        Text("\(entwurf.terminpersonen.count)")
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                ForEach(gewaehltePersonen) { person in
                    LabeledContent(person.anzeigename) {
                        Button("Herausnehmen") { entwurf.terminpersonen.removeAll { $0 == person.id } }
                            .buttonStyle(.link)
                    }
                }
                // Keine Grenze der Personen je Termin (E978).
                if verwaltungOffen {
                    TextField("Person hinzufügen", text: $personensuche, prompt: Text("Name suchen"))
                    ForEach(treffer) { person in
                        Button {
                            entwurf.terminpersonen.append(person.id)
                            personensuche = ""
                        } label: {
                            Text(person.anzeigename + gruppentext(person))
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            // Was früher unter dem Kasten stand, als eigene Zeile im Kasten (Nutzer, 07.11.2026): Es gilt dem ganzen
            // Termin und kommt und geht mit ihm. Ausgeschaltet ohne offene Verwaltung nur, wenn der Satz nicht schon als
            // Unterzeile am Schalter steht — sonst stünde er zweimal untereinander.
            if entwurf.termin, let fehlt = entwurf.terminFehlt(verwaltungOffen: verwaltungOffen) {
                Erlaeuterung(fehlt, warnung: true)
            } else if entwurf.termin {
                Erlaeuterung("Die Planung trägt Titel, Tag und Uhrzeit, keinen Namen; Personen und Stand führt die "
                             + "Lernendenverwaltung — beide Seiten bleiben synchron.")
            } else if let fuss = entwurf.terminFussAusgeschaltet(verwaltungOffen: verwaltungOffen),
                      fuss != terminSchalterHilfe {
                Erlaeuterung(fuss)
            }
        } header: {
            Text("Termin")
        }
    }

    private var wochenmontag: Tag {
        guard let planung else { return Tag.heute.montagDerWoche }
        return planung.start.montagDerWoche.plus(tage: entwurf.woche * 7)
    }

    /// Der erste Werktag der gewählten Woche, an dem geprüft werden darf.
    /// Ohne Termin gibt es kein Datumsfeld, über das ein anderer Tag zu wählen
    /// wäre — ein gesperrter Montag führte sonst in eine Sackgasse.
    private var ersterZulaessigerTermin: Tag {
        let woche = (0...4).map { wochenmontag.plus(tage: $0) }
        return woche.first { speicher.sperre(am: $0, fuer: entwurf.klasseId) == nil }
            ?? wochenmontag
    }

    /// Übernimmt den Tag nur, wenn er nicht gesperrt ist; sonst bleibt der
    /// Termin offen und der Hinweis nennt den Sperrzeitraum.
    private func terminSetzen(_ tag: Tag) {
        if let gesperrt = speicher.sperre(am: tag, fuer: entwurf.klasseId) {
            sperrhinweis = gesperrt.abweisung
        } else {
            sperrhinweis = ""
            entwurf.pruefungstag = tag
        }
    }

    /// Der Sperrzeitraum, in dem der **gespeicherte** Termin liegt.
    private var bestehendeSperre: Sperrzeitraum? {
        guard let tag = entwurf.pruefungstag else { return nil }
        return speicher.sperre(am: tag, fuer: entwurf.klasseId)
    }

    private func ausserhalbDerWoche(_ tag: Tag?) -> Bool {
        guard let tag else { return false }
        return tag < wochenmontag || tag > wochenmontag.plus(tage: 6)
    }

    // ── Material ──────────────────────────────────────────────────────────

    private var materialbereich: some View {
        Section {
            if entwurf.materialien.isEmpty {
                Text("Noch keine Materialien verknüpft.").foregroundStyle(.secondary)
            } else {
                Spaltenkopfzeile(zweite: "Datei")
                ForEach(entwurf.materialien) { eintrag in
                    Materialposten(
                        material: $entwurf.materialien[kennung: eintrag.id,
                                                       letzterStand: eintrag]
                    ) {
                        entwurf.materialien.removeAll { $0.id == eintrag.id }
                    }
                }
            }

            ablageflaeche(.dateien)

            HStack(spacing: 8) {
                Button {
                    Systemzugriff.dateienWaehlen(start: planung?.basis ?? "",
                                                 zugriff: speicher.zugriff) { aufnehmen(pfade: $0) }
                } label: { Label("Datei wählen …", systemImage: Zeichen.datei) }

                Button {
                    // Das Lesezeichen setzt `materialAufnehmen` — nur für die aufgenommenen (R89-04).
                    Systemzugriff.ordnerWaehlen(start: planung?.basis ?? "", zugriff: speicher.zugriff,
                                                merken: false) { aufnehmen(pfade: $0) }
                } label: { Label("Ordner wählen …", systemImage: Zeichen.ordner) }
            }

            // Gilt dem ganzen Kasten: eigene Zeile darin, am Ende (Nutzer, 07.11.2026).
            Erlaeuterung("Hinterlegt wird ein Verweis, kopiert wird nichts. Die App merkt sich den Zugriff auf jede "
                         + "verknüpfte Datei und jeden verknüpften Ordner — nur so darf sie sie später öffnen.")
        } header: {
            Text("Verknüpfte Dateien und Ordner")
        }
    }

    // ── Ablageflächen (E375 b, E734) ──────────────────────────────────────

    /// Was eine Ablagefläche annimmt: unter „Material“ nur Dateien, unter „Links“ nur Links (E734).
    enum Ablageart: Sendable { case dateien, links }

    /// Teilt Hergezogenes nach der Fläche (E734): Das Passende wird übernommen, für den Rest steht die Meldung —
    /// W3/W4, wenn das Falsche dabei war, W5/W6, wenn weder Datei noch Webadresse kam.
    nonisolated static func ablage(_ adressen: [URL], art: Ablageart)
        -> (dateien: [URL], links: [String], meldung: String?) {
        let dateien = adressen.filter(\.isFileURL)
        let links = adressen.filter { !$0.isFileURL }.map(\.absoluteString)
        switch art {
        case .dateien:
            let meldung = !links.isEmpty ? "Links gehören unter „Links“ — hier lassen sich nur Dateien ablegen."
                : dateien.isEmpty ? "Keine Datei erkannt — bitte „Datei wählen …“ nutzen." : nil
            return (dateien, [], meldung)
        case .links:
            let meldung = !dateien.isEmpty ? "Dateien gehören unter „Material“ — hier lassen sich nur Links ablegen."
                : links.isEmpty ? "Keine Webadresse erkannt — bitte „Link hinzufügen“ nutzen." : nil
            return ([], links, meldung)
        }
    }

    private func ablageflaeche(_ art: Ablageart) -> some View {
        Text(art == .dateien ? "Dateien aus dem Finder hierher ziehen" : "Links aus dem Browser hierher ziehen")
            .font(.callout)
            .foregroundStyle(ablageAktiv ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(ablageAktiv ? Color.accentColor : Color.secondary.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .dropDestination(for: URL.self) { adressen, _ in
                let teile = Self.ablage(adressen, art: art)
                // Das Lesezeichen setzt `materialAufnehmen` — nur für die aufgenommenen Dateien (R89-04).
                if !teile.dateien.isEmpty { aufnehmen(pfade: teile.dateien.map(\.path)) }
                if !teile.links.isEmpty { speicher.linksAufnehmen(teile.links, in: &entwurf) }
                if let meldung = teile.meldung { speicher.melden(meldung, .warnung) }
                return !teile.dateien.isEmpty || !teile.links.isEmpty
            } isTargeted: { ablageAktiv = $0 }
            .animation(.easeOut(duration: 0.15), value: ablageAktiv)
    }

    // ── Links ─────────────────────────────────────────────────────────────

    /// Aufgebaut wie „Material“: die Liste, die Ablagefläche (E375 b, nur Links: E734), der Knopf — so in der
    /// Handprobe abgenommen; die Erläuterung am Ende des Kastens verweist auf die Fläche oben.
    private var linkbereich: some View {
        Section {
            if entwurf.links.isEmpty {
                Text("Noch kein Link hinterlegt.").foregroundStyle(.secondary)
            } else {
                Spaltenkopfzeile(zweite: "Adresse")
                ForEach(entwurf.links) { eintrag in
                    Linkposten(link: $entwurf.links[kennung: eintrag.id, letzterStand: eintrag],
                               fokus: $linkFokus) {
                        entwurf.links.removeAll { $0.id == eintrag.id }
                    }
                }
            }
            ablageflaeche(.links)
            Button {
                let neu = Weblink(titel: "", adresse: "")
                entwurf.links.append(neu)
                linkFokus = neu.id
            } label: { Label("Link hinzufügen", systemImage: Zeichen.verweis) }

            // Gilt dem ganzen Kasten: eigene Zeile darin, am Ende (Nutzer, 07.11.2026).
            Erlaeuterung("Nur http- und https-Adressen; fehlt der Vorsatz, wird https:// ergänzt. "
                         + "Links lassen sich auch aus dem Browser auf die Ablagefläche oben ziehen.")
        } header: {
            Text("Links")
        }
    }

    // ── Material von 3ducation.org ────────────────────────────────────────

    /// Unter „Links“ (Nutzer, 20.10.2026: Rückfall auf den bisherigen Knopf). Der Knopf steht immer; ohne Erlaubnis
    /// zeigt das Blatt zuerst die Frage (E177). Ein Klick auf eine Kachel hinterlegt das Material als Link, wie die
    /// Links darüber — der Entwurf teilt sich das Feld.
    private var websitebereich: some View {
        Section {
            // Die Erläuterung als graue Unterzeile in derselben Zeile wie der Knopf, dem sie gilt (Nutzer, 07.11.2026).
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    speicher.materialblattOffen = true
                } label: {
                    Label("Material von 3ducation.org hinzufügen", systemImage: Zeichen.verweis)
                }
                Erlaeuterung("Öffnet die Materialliste der Website 3ducation.org — ein Klick auf eine Kachel "
                             + "hinterlegt das Material als Link am Vorhaben, wie die Links darüber.")
            }
        } header: {
            Text("Material von 3ducation.org")
        }
    }

    // ── Handgriffe ────────────────────────────────────────────────────────

    private func unterzeile(stand: Wochenstand) -> String {
        let kurs = planung?.klasse(entwurf.klasseId)?.name ?? ""
        guard let woche = stand.woche(entwurf.woche) else {
            return kurs + " · KW –"
        }
        return kurs + " · " + woche.beschriftung(schulwoche: stand.schulwoche(woche))
    }

    private func wochentext(_ woche: Woche, schulwoche: Int?) -> String {
        woche.beschriftung(schulwoche: schulwoche) + " · \(woche.spanne)"
            + ((planung?.frei.contains(woche.montag) ?? false) ? " (unterrichtsfrei)" : "")
    }

    private func aufnehmen(pfade: [String]) {
        guard !pfade.isEmpty else { return }
        speicher.materialAufnehmen(pfade, in: &entwurf)
    }

    /// Die Handlung des eigenen Alerts — nach dessen Schließen (B95, E433); bis dahin sperrt `antwortAussteht`.
    private func nachDemAlert(_ handlung: @escaping @MainActor () -> Void) {
        antwortAussteht = true
        speicher.nachDemSchliessenAusfuehren {
            antwortAussteht = false
            handlung()
        }()
    }

    private func abbrechen() {
        guard !speicher.frageSperrtBefehl(), !antwortAussteht else { return }
        if entwurf.veraendert { verwerfenFragen = true } else { schliessen() }
    }

    private func uebernehmen() {
        guard !speicher.frageSperrtBefehl(), !antwortAussteht else { return }
        // Weist „Übernehmen“ ab, steht das Blatt auf dem Eintrag des Grundes (E374, E732) — dieselbe Regel, die die
        // Prüfungen sichern (Z-AW3n-04); nil heißt: nichts weist ab.
        if let reiter = entwurf.reiterDesGrundes(verwaltungOffen: verwaltungOffen) {
            speicher.vorhabenReiter = reiter
        }
        if entwurf.leer {
            speicher.melden("Bitte wenigstens einen Titel, eine Beschreibung, ein Material oder einen Link eintragen.", .warnung)
            return
        }
        let schlecht = entwurf.ungueltigeLinks()
        if !schlecht.isEmpty {
            speicher.melden(schlecht.count == 1
                            ? "„\(schlecht[0])“ ist keine gültige http- oder https-Adresse."
                            : "\(schlecht.count) Adressen sind weder http noch https.", .warnung)
            return
        }
        speicher.vorhabenSichernFragen(entwurf)
    }
}

// ── Symbole der Seitenleiste (v95, E1109) ─────────────────────────────────

private extension Vorhabenreiter {
    /// Das Symbol des Eintrags — wo es eins gibt, das der App (Prüfung, Links); sonst frei neben ihnen: der Ranzen der
    /// Hausaufgabe (E17) als Umriss wie alle Symbole einer Seitenleiste.
    var symbol: String {
        switch self {
        case .grundlegendes: return "doc.text"
        case .kommentar: return "text.bubble"
        case .pruefung: return Zeichen.pruefung
        case .termin: return "calendar.badge.clock"
        case .hausaufgabe: return "backpack"
        case .material: return "paperclip"
        case .links: return Zeichen.verweis
        }
    }
}

// ── Wochentag ─────────────────────────────────────────────────────────────

/// Ein Kästchen der Wochentagszeile. Unterrichtstage der Klasse bzw. des
/// Kurses stehen fett auf getönter Fläche; die übrigen bleiben wählbar.
private struct Wochentagskaestchen: View {
    let tag: Wochentag
    let unterricht: Bool
    let gewaehlt: Bool
    /// Auf dem Hauptakteur, weil die Bindung eine `@Sendable`-Handlung will.
    let waehlen: @MainActor (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { gewaehlt }, set: { an in waehlen(an) })) {
            Text(tag.kurz).fontWeight(unterricht ? .semibold : .regular)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(unterricht ? Color.accentColor.opacity(0.16) : Color.clear,
                    in: .rect(cornerRadius: 7))
        .help(unterricht ? "\(tag.lang) — Unterrichtstag laut „Lernende, Klassen/Kurse und Fächer“"
                         : tag.lang)
        .accessibilityLabel(unterricht ? "\(tag.lang), Unterrichtstag" : tag.lang)
    }
}

// ── Einzelposten ──────────────────────────────────────────────────────────

private struct Materialposten: View {
    @Binding var material: Material
    let entfernen: () -> Void

    @Environment(Planungsspeicher.self) private var speicher

    /// Ohne Basisordner ist jeder Pfad absolut — „liegt außerhalb“ hieße dann
    /// nichts.
    private var draussen: Bool {
        material.istAbsolut && !(speicher.planung?.basis ?? "").isEmpty
    }

    /// Im Sandbox: ein Ort, den die App in dieser Fassung noch nicht gezeigt
    /// bekam — beim Öffnen fragt sie nach der Wahl.
    private var unerreichbar: Bool {
        !speicher.zugriff.erreichbar(speicher.vollerPfad(material.pfad))
    }

    var body: some View {
        // Einmal je Durchlauf: Die Antwort kostet einen Blick ins Dateisystem.
        let unerreichbar = unerreichbar
        HStack(spacing: Linkspalten.abstand) {
            Button { speicher.imFinderZeigen(material.pfad, ort: .vorhaben) } label: {
                Image(systemName: Zeichen.ordner)
            }
            .buttonStyle(.borderless)
            .frame(width: Linkspalten.symbol)
            .help("Im Finder zeigen")
            .accessibilityLabel("Im Finder zeigen")

            Tabellenfeld(hinweis: "Bezeichnung", text: $material.titel)
                .frame(width: Linkspalten.titel)

            Text((unerreichbar ? "⚠︎ " : draussen ? "↗ " : "") + material.pfad)
                .font(.caption.monospaced())
                .foregroundStyle(draussen || unerreichbar ? Color.orange : Color.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(unerreichbar
                      ? "Auf diesen Ort darf die App noch nicht zugreifen — beim Öffnen fragt "
                        + "sie nach der Wahl und merkt sie sich."
                      : draussen
                      ? "Liegt außerhalb des Basisordners und ist deshalb absolut hinterlegt."
                      : "Verweis auf die Datei — kopiert wird nichts.")

            Button(role: .destructive, action: entfernen) {
                Image(systemName: Zeichen.muell)
            }
            .buttonStyle(.borderless)
            .frame(width: Linkspalten.knopf)
            .help("Verweis entfernen")
            .accessibilityLabel("Material entfernen")
        }
    }
}

private enum Linkspalten {
    static let symbol: CGFloat = 18
    static let titel: CGFloat = 150
    static let abstand: CGFloat = 10
    static let knopf: CGFloat = 22
}

/// Die Spalten werden einmal beschriftet statt in jeder Zeile — siehe
/// `Tabellenfeld`.
private struct Spaltenkopfzeile: View {
    /// „Datei“ bei den Materialien, „Adresse“ bei den Links.
    let zweite: String

    var body: some View {
        HStack(spacing: Linkspalten.abstand) {
            Color.clear.frame(width: Linkspalten.symbol, height: 1)
            Spaltenkopf(titel: "Bezeichnung").frame(width: Linkspalten.titel, alignment: .leading)
            Spaltenkopf(titel: zweite).frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: Linkspalten.knopf, height: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct Linkposten: View {
    @Binding var link: Weblink
    @FocusState.Binding var fokus: UUID?
    let entfernen: () -> Void

    private var geprueft: String? { Weblinks.pruefen(link.adresse) }
    private var ungueltig: Bool { !link.adresse.isEmpty && geprueft == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Linkspalten.abstand) {
                Button {
                    if let ziel = geprueft { Systemzugriff.adresseOeffnen(ziel) }
                } label: {
                    Image(systemName: Zeichen.verweis)
                }
                .buttonStyle(.borderless)
                .frame(width: Linkspalten.symbol)
                .disabled(geprueft == nil)
                .help(geprueft.map { "Im Browser öffnen: " + $0 } ?? "Adresse noch nicht gültig")
                .accessibilityLabel("Link im Browser öffnen")

                Tabellenfeld(hinweis: "Bezeichnung", text: $link.titel)
                    .frame(width: Linkspalten.titel)

                Tabellenfeld(hinweis: "https://…", text: $link.adresse,
                             beimVerlassen: zurechtruecken)
                    .frame(maxWidth: .infinity)
                    .focused($fokus, equals: link.id)

                Button(role: .destructive, action: entfernen) {
                    Image(systemName: Zeichen.muell)
                }
                .buttonStyle(.borderless)
                .frame(width: Linkspalten.knopf)
                .help("Link entfernen")
                .accessibilityLabel("Link entfernen")
            }

            if ungueltig {
                // Unter dem Adressfeld, dem sie gilt — als Warnzeile in der einen Erscheinung (E1122).
                Erlaeuterung("Keine gültige http- oder https-Adresse.", warnung: true)
                    .padding(.leading, Linkspalten.symbol + Linkspalten.titel
                             + Linkspalten.abstand * 2)
            }
        }
    }

    /// Zeigt beim Verlassen, was tatsächlich gespeichert würde.
    private func zurechtruecken() {
        guard let fertig = Weblinks.pruefen(link.adresse) else { return }
        link.adresse = fertig
        if link.titel.trimmingCharacters(in: .whitespaces).isEmpty {
            link.titel = Weblinks.name(fertig)
        }
    }
}
