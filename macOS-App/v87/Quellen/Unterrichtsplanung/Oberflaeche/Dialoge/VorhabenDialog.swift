// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct VorhabenDialog: View {
    let start: VorhabenEntwurf

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

        // Wie das Blatt „Lernende“ (Nutzer, 20.10.2026): gleich groß, freier Körper, die Leiste oben links, darunter der
        // Inhalt des gewählten Reiters in fester Höhe — das Blatt springt beim Wechsel nicht.
        // Liegt der Material-Bogen darauf, zeigt nur er die Meldungen — wie die Bögen am Blatt „Lernende“ (E490 a).
        Dialograhmen(titel: entwurf.istNeu ? "Neues Vorhaben" : "Vorhaben bearbeiten",
                     unterzeile: unterzeile(stand: stand), breite: 1000, hoehe: 720,
                     beimSchliessen: abbrechen, freierKoerper: true,
                     meldungsblatt: speicher.materialblattOffen ? nil : .vorhaben,
                     zeileAbgegeben: speicher.materialblattOffen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    reiterleiste
                    Spacer(minLength: 0)
                }
                // Die Kästen über die ganze Breite, bündig mit der Leiste (E733 a): Ein gruppiertes `Form` wird nie
                // breiter als rund 704 pt und stünde mittig.
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch speicher.vorhabenReiter {
                        case .grundlegendes: grundlegendes(stand)
                        case .kommentar: kommentarbereich
                        case .pruefung: pruefungsbereich
                        case .termin: terminbereich
                        case .hausaufgabe: hausaufgabenbereich
                        case .material: materialbereich
                        case .links:
                            linkbereich
                            websitebereich
                        }
                    }
                    .labeledContentStyle(Zeilenstil())
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
            .frame(height: 560, alignment: .top)
        } fuss: {
            if !entwurf.istNeu {
                Button(role: .destructive) {
                    if let id = entwurf.vorhabenId { speicher.vorhabenLoeschen(id) }
                } label: {
                    Label("Löschen", systemImage: Zeichen.muell)
                }
            }
            Fussluecke()
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Button("Übernehmen") { uebernehmen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            if speicher.vorhabenReiter == .hausaufgabe { hausaufgabenFokus = true } else { titelFokus = true }
        }
        // Das Material-Blatt von 3ducation.org — ein Bogen an diesem Blatt (v71).
        .sheet(isPresented: Binding(get: { speicher.materialblattOffen },
                                    set: { speicher.materialblattOffen = $0 })) {
            MaterialDialog(entwurf: $entwurf)
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

    // ── Reiterleiste ──────────────────────────────────────────────────────

    /// Dasselbe Steuerelement wie im Blatt „Lernende“: gleich breite Segmente, das gewählte im aktiven Fenster blau.
    private var reiterleiste: some View {
        // Die Bedienhilfe wie im Blatt „Lernende“ — nie das Wort „Reiter“ (Z-AW3n-05).
        Picker("Zeigen", selection: Binding(get: { speicher.vorhabenReiter },
                                            set: { speicher.vorhabenReiter = $0 })) {
            ForEach(Vorhabenreiter.allCases) { reiter in
                Text(leistentitel(reiter)).tag(reiter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// Der Titel in der Leiste, mit Kennzeichen (E373). Jedes Segment ist so breit wie das breiteste; „Grundlegendes“
    /// bekommt je einen schmalen Leerraum (U+2009) davor und dahinter — dann ist es breiter als jedes Kennzeichen
    /// („Hausaufgabe ✓“), und die Leiste behält ihre Breite, wenn ein Kennzeichen erscheint (gemessen: 117 zu 116 pt).
    private func leistentitel(_ reiter: Vorhabenreiter) -> String {
        reiter == .grundlegendes ? "\u{2009}" + reiter.titel + "\u{2009}"
            : entwurf.beschriftung(reiter, verwaltungOffen: verwaltungOffen)
    }

    // ── Grundlegendes ─────────────────────────────────────────────────────

    /// Alles, was früher über dem Kommentar stand.
    @ViewBuilder
    private func grundlegendes(_ stand: Wochenstand) -> some View {
        Kasten {
            Steuerzeile(beschriftung: "Titel") {
                TextField("Titel", text: $entwurf.titel,
                          prompt: Text("z. B. Stoffe und ihre Eigenschaften"))
                    .zeilenfeld()
                    .focused($titelFokus)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Weiterführende Informationen").foregroundStyle(.secondary)
                Textfeld(text: $entwurf.text, mindesthoehe: 60,
                         beschriftung: "Weiterführende Informationen")
            }

            Steuerzeile(beschriftung: "Klasse/Kurs") {
                Picker("Klasse/Kurs", selection: $entwurf.klasseId) {
                    ForEach(planung?.klassen ?? []) { klasse in
                        Text(klasse.beschriftung).tag(klasse.id)
                    }
                }
                .zeilenauswahl()
            }
            Steuerzeile(beschriftung: "Woche") {
                Picker("Woche", selection: $entwurf.woche) {
                    ForEach(stand.wochen) { woche in
                        Text(wochentext(woche, schulwoche: stand.schulwoche(woche)))
                            .tag(woche.nummer)
                    }
                }
                .zeilenauswahl()
            }

            wochentagsbereich
            datumsbereich

            Schalterzeile(beschriftung: "Durchgeführt", an: $entwurf.erledigt)
            Schalterzeile(beschriftung: "Als dringlich kennzeichnen", an: $entwurf.dringend)
                .help("Dringliche Vorhaben tragen im Raster einen gelben Rahmen.")
            // Entweder Prüfung oder Korrektur: gesperrt statt umgeschaltet —
            // ein Klick nimmt nie still einen Prüfungstermin weg.
            Schalterzeile(beschriftung: "Als Korrektur kennzeichnen", an: $entwurf.korrektur)
                .disabled(entwurf.pruefung || entwurf.termin)
                .help(entwurf.pruefung || entwurf.termin
                      ? VorhabenDialog.entwederOder
                      : "Korrekturen tragen im Raster einen gestrichelten roten Rahmen und die Zeile „Korrektur“.")
        }
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
    @ViewBuilder
    private var wochentagsbereich: some View {
        LabeledContent("Wochentag") {
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
        }
        if !wochenhinweis.isEmpty {
            Label(wochenhinweis, systemImage: Zeichen.hinweis)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(unterrichtstageText)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        if ausserhalbDerWoche(entwurf.datum) {
            Label("Das Datum liegt außerhalb der gewählten Woche.", systemImage: Zeichen.warnung)
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ── Kommentar und Hausaufgabe ─────────────────────────────────────────

    /// Was im Unterricht daraus wurde.
    private var kommentarbereich: some View {
        Kasten {
            Textfeld(text: $entwurf.kommentar, mindesthoehe: 70,
                     beschriftung: "Kommentar zum Verlauf")
        } fuss: {
            Text("Wie das Vorhaben gelaufen ist — getrennt von den weiterführenden "
                 + "Informationen, die sagen, was geplant war. Dieses Feld füllt auch die "
                 + "Web App; ihr Stand wird beim Start, nach dem Aufwachen des Macs aus dem "
                 + "Ruhezustand und über „Stand der Web App abrufen“ übernommen.")
        }
    }

    /// Eine Hausaufgabe am Vorhaben — ein Merkmal, kein anderes Vorhaben —
    /// samt einer Zeile. Die Zeile gibt es nur mit Schalter; aus lässt sie bis
    /// zum Übernehmen stehen, übernommen wird dann eine leere.
    private var hausaufgabenbereich: some View {
        Kasten {
            Schalterzeile(beschriftung: "Hausaufgabe hinzufügen", an: $entwurf.hausaufgabe)
                .help("Das Vorhaben bekommt eine Hausaufgabe — mit Zeichen im Raster, in der "
                      + "Tagesliste und in der Web App.")
            if entwurf.hausaufgabe {
                Steuerzeile(beschriftung: "Hausaufgabe") {
                    TextField("Hausaufgabe", text: $entwurf.hausaufgabenText,
                              prompt: Text("z. B. S. 42, Nr. 3–5 (optional)"))
                        .zeilenfeld()
                        .lineLimit(1)
                        .focused($hausaufgabenFokus)
                        .accessibilityLabel("Hausaufgabe, eine Zeile, optional")
                }
            }
        } fuss: {
            if entwurf.hausaufgabe {
                Text("Die Zeile ist freiwillig — sie steht in der Tagesliste, im Ausdruck "
                     + "und im Detail der Web App; im Raster zeigt die Kachel nur das Zeichen.")
            }
        }
    }

    static let entwederOder = "Ein Vorhaben ist entweder Prüfung, Korrektur oder Termin."

    /// Kennzeichnung als Prüfung samt Termin.
    private var pruefungsbereich: some View {
        Kasten {
            Schalterzeile(beschriftung: "Als Prüfung führen", an: Binding(
                get: { entwurf.pruefung },
                set: { an in
                    entwurf.pruefung = an
                    sperrhinweis = ""
                    guard an, entwurf.pruefungstag == nil else { return }
                    terminSetzen(wochenmontag)
                }))
            .disabled(entwurf.korrektur || entwurf.termin)
            .help(entwurf.korrektur || entwurf.termin ? VorhabenDialog.entwederOder : "")

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
                    Label(hinweis, systemImage: Zeichen.warnung)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if entwurf.pruefungstag == nil {
                    Text("Noch kein Termin — die Prüfung steht in der Übersicht unter "
                         + "„ohne Termin“.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if ausserhalbDerWoche(entwurf.pruefungstag) {
                    Label("Der Termin liegt außerhalb der gewählten Woche.",
                          systemImage: Zeichen.warnung)
                        .font(.caption).foregroundStyle(.orange)
                }
                if let sperren = speicher.planung?.sperrzeiten, !sperren.isEmpty {
                    Text(sperren.count == 1
                         ? "Ein Sperrzeitraum ist hinterlegt — zu sehen unter „Prüfungen“ (⌘R)."
                         : "\(sperren.count) Sperrzeiträume sind hinterlegt — zu sehen unter "
                           + "„Prüfungen“ (⌘R).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
        return verzeichnis.alle
            .filter { p in !ausser.contains(p.id) && Lernendenverzeichnis.trifft(p, suche) }
            .sorted { (mitglieder.contains($0.id) ? 0 : 1) < (mitglieder.contains($1.id) ? 0 : 1) }
            .prefix(8)
            .map { $0 }
    }

    private func gruppentext(_ person: Lernender) -> String {
        let gruppen = speicher.lernende.verzeichnis?.gruppen(von: person.id).filter { $0.archiviert.isEmpty } ?? []
        return gruppen.isEmpty ? "" : " · " + gruppen.map(\.beschriftung).joined(separator: ", ")
    }

    /// Kennzeichnung als Termin: Uhrzeit und Personen; Titel und Tag sind die des Vorhabens.
    private var terminbereich: some View {
        Kasten {
            Schalterzeile(beschriftung: "Als Termin führen", an: Binding(
                get: { entwurf.termin },
                set: { an in
                    entwurf.termin = an
                    // Ein Termin braucht einen Tag — vorgeschlagen der erste Unterrichtstag der Woche.
                    if an, entwurf.datum == nil {
                        entwurf.datum = unterrichtstage.sorted().first.map { $0.datum(inWocheVon: wochenmontag) }
                            ?? wochenmontag
                    }
                }))
            .disabled(entwurf.terminSchalterGesperrt(verwaltungOffen: verwaltungOffen))
            // Ohne offene Verwaltung: am bedienbaren Schalter eines bestehenden Termins ein eigener Text (E778). Gesperrt
            // trägt eine durchsichtige Fläche die Hilfe (H1; Z-AX6a-01).
            .hilfe(entwurf.pruefung || entwurf.korrektur ? VorhabenDialog.entwederOder
                   : entwurf.terminSchalterHilfe(verwaltungOffen: verwaltungOffen),
                   gesperrt: entwurf.terminSchalterGesperrt(verwaltungOffen: verwaltungOffen))

            if entwurf.termin {
                // Ohne offene Verwaltung bleibt ein bestehender Termin, wie er war (E721) — auch seine Uhrzeit; das
                // Feld ist dann gesperrt, statt eine Eingabe still fallen zu lassen (Z-AW3n-01).
                let uhrzeitSperre = entwurf.uhrzeitSperre(verwaltungOffen: verwaltungOffen)
                Steuerzeile(beschriftung: "Uhrzeit") {
                    TextField("Uhrzeit", text: $entwurf.terminzeit, prompt: Text("hh:mm"))
                        .zeilenfeld()
                        .frame(width: 90)
                }
                .disabled(uhrzeitSperre != nil)
                .hilfe(uhrzeitSperre ?? "", gesperrt: uhrzeitSperre != nil)  // gesperrt sonst unsichtbar (H1; Z-AX6a-01)
                if verwaltungOffen {
                    LabeledContent("Personen") {
                        Text("\(entwurf.terminpersonen.count) von \(Kennwerte.maxMitgliederJeLerngruppe)")
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
                // Höchstens 40 Personen je Termin (E279) — darüber ließe sich die Jahresdatei nicht schreiben (W1-02).
                if verwaltungOffen, entwurf.terminpersonen.count < Kennwerte.maxMitgliederJeLerngruppe {
                    TextField("Person hinzufügen", text: $personensuche, prompt: Text("Person hinzufügen — Name suchen"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
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
        } fuss: {
            if entwurf.termin, let fehlt = entwurf.terminFehlt(verwaltungOffen: verwaltungOffen) {
                Text(fehlt).foregroundStyle(.orange)
            } else if entwurf.termin {
                Text("Die Planung trägt Titel, Tag und Uhrzeit, keinen Namen; Personen und Stand führt die "
                     + "Lernendenverwaltung — beide Seiten bleiben synchron.")
                    .foregroundStyle(.secondary)
            } else if let fuss = entwurf.terminFussAusgeschaltet(verwaltungOffen: verwaltungOffen) {
                Text(fuss).foregroundStyle(.secondary)
            }
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
        Kasten {
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
                    Systemzugriff.ordnerWaehlen(start: planung?.basis ?? "",
                                                zugriff: speicher.zugriff) { aufnehmen(pfade: $0) }
                } label: { Label("Ordner wählen …", systemImage: Zeichen.ordner) }
            }
        } fuss: {
            Text("Hinterlegt wird ein Verweis, kopiert wird nichts. Die App merkt sich jede "
                 + "gewählte oder hergezogene Datei und jeden Ordner — nur so darf sie sie "
                 + "später öffnen.")
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
                // Die hergezogene Datei steht der App jetzt offen — das Lesezeichen
                // hält das fest, sonst wäre sie nach dem Neustart unerreichbar.
                speicher.zugriff.merken(alle: teile.dateien)
                if !teile.dateien.isEmpty { aufnehmen(pfade: teile.dateien.map(\.path)) }
                if !teile.links.isEmpty { speicher.linksAufnehmen(teile.links, in: &entwurf) }
                if let meldung = teile.meldung { speicher.melden(meldung, .warnung) }
                return !teile.dateien.isEmpty || !teile.links.isEmpty
            } isTargeted: { ablageAktiv = $0 }
            .animation(.easeOut(duration: 0.15), value: ablageAktiv)
    }

    // ── Links ─────────────────────────────────────────────────────────────

    /// Aufgebaut wie „Material“: die Liste, die Ablagefläche (E375 b, nur Links: E734), der Knopf — so in der
    /// Handprobe abgenommen; der Fußtext unter dem Kasten verweist auf die Fläche oben.
    private var linkbereich: some View {
        Kasten {
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
        } fuss: {
            Text("Nur http- und https-Adressen; fehlt der Vorsatz, wird https:// ergänzt. "
                 + "Links lassen sich auch aus dem Browser auf die Ablagefläche oben ziehen.")
        }
    }

    // ── Material von 3ducation.org ────────────────────────────────────────

    /// Unter „Links“ (Nutzer, 20.10.2026: Rückfall auf den bisherigen Knopf). Der Knopf steht immer; ohne Erlaubnis
    /// zeigt das Blatt zuerst die Frage (E177). Ein Klick auf eine Kachel hinterlegt das Material als Link, wie die
    /// Links darüber — der Entwurf teilt sich das Feld.
    private var websitebereich: some View {
        Kasten(titel: "Material von 3ducation.org") {
            Button {
                speicher.materialblattOffen = true
            } label: {
                Label("Material von 3ducation.org hinzufügen", systemImage: Zeichen.verweis)
            }
        } fuss: {
            Text("Öffnet die Materialliste der Website 3ducation.org — ein Klick auf eine Kachel "
                 + "hinterlegt das Material als Link am Vorhaben, wie die Links darüber.")
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
        // Weist „Übernehmen“ ab, steht das Blatt auf dem Reiter des Grundes (E374, E732) — dieselbe Regel, die die
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
                Text("Keine gültige http- oder https-Adresse.")
                    .font(.caption)
                    .foregroundStyle(.orange)
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

// ── Kästen über die ganze Breite (E733 a) ─────────────────────────────────

/// Die Flächen eines gruppierten `Form`, am Abbild gemessen (20.10.2026): der Kasten 248 auf 255 (hell) bzw. 49 auf 40
/// (dunkel), die Trennlinie 239 bzw. 61 auf dem Kasten. Keine Systemfarbe trifft beide Erscheinungen.
private enum Kastenfarben {
    static let flaeche = Color(nsColor: NSColor(name: nil) { erscheinung in
        erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.042) : NSColor(white: 0, alpha: 0.027)
    })
    static let linie = Color(nsColor: NSColor(name: nil) { erscheinung in
        erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.058) : NSColor(white: 0, alpha: 0.036)
    })
}

/// Ein Kasten wie im gruppierten `Form` — Zeilen mit Trennlinien, darüber eine Überschrift, darunter ein Fußtext —,
/// aber so breit wie das Blatt: Ein `Form` wird nie breiter als rund 704 pt. Maße wie dort: Ecken 12 pt, Zeilen gut
/// 37 pt, 10 pt Einzug.
private struct Kasten<Inhalt: View, Fuss: View>: View {
    var titel: String?
    @ViewBuilder var inhalt: Inhalt
    @ViewBuilder var fuss: Fuss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let titel {
                // Für VoiceOver eine Überschrift wie der Kopf eines Abschnitts im gruppierten `Form` (G1-05, E787).
                Text(titel).font(.headline).padding(.horizontal, 10)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: inhalt) { zeilen in
                    ForEach(zeilen) { zeile in
                        if zeile.id != zeilen.first?.id {
                            Kastenfarben.linie.frame(height: 1)
                        }
                        zeile
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 10)
            .background(Kastenfarben.flaeche, in: .rect(cornerRadius: 12))
            fuss
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
        }
    }
}

extension Kasten where Fuss == EmptyView {
    init(titel: String? = nil, @ViewBuilder inhalt: () -> Inhalt) {
        self.init(titel: titel, inhalt: inhalt, fuss: { EmptyView() })
    }
}

/// Eine Zeile: links die Beschriftung, rechts das Steuerelement — wie `LabeledContent` im gruppierten `Form`.
private struct Zeilenstil: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 16) {
            configuration.label
            Spacer(minLength: 0)
            configuration.content
        }
    }
}

/// Eine Zeile, deren Steuerelement seine Beschriftung selbst trägt (`labelsHidden`): Die sichtbare Beschriftung davor
/// bleibt der Bedienhilfe verborgen — sonst läse VoiceOver sie zweimal; im `Form` war es ein Element. Gesperrt wird
/// sie blass wie dort.
private struct Steuerzeile<Inhalt: View>: View {
    let beschriftung: String
    @ViewBuilder var inhalt: Inhalt
    @Environment(\.isEnabled) private var aktiv

    var body: some View {
        LabeledContent {
            inhalt
        } label: {
            Text(beschriftung)
                .foregroundStyle(aktiv ? .primary : .tertiary)
                .accessibilityHidden(true)
        }
    }
}

/// Ein Schalter in seiner Zeile.
private struct Schalterzeile: View {
    let beschriftung: String
    @Binding var an: Bool

    var body: some View {
        Steuerzeile(beschriftung: beschriftung) {
            Toggle(beschriftung, isOn: $an)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

private extension View {
    /// Ein Eingabefeld in einer Zeile: ohne eigene Beschriftung und Rahmen, rechtsbündig — wie im gruppierten `Form`.
    func zeilenfeld() -> some View {
        labelsHidden().textFieldStyle(.plain).multilineTextAlignment(.trailing)
    }

    /// Eine Auswahl in einer Zeile: ohne eigene Beschriftung, so breit wie ihr Inhalt.
    func zeilenauswahl() -> some View {
        labelsHidden().buttonStyle(.borderless).fixedSize()
    }
}
