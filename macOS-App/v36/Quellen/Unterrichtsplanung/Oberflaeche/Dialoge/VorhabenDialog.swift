// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct VorhabenDialog: View {
    let start: VorhabenEntwurf

    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @State private var entwurf: VorhabenEntwurf
    @State private var pfadDialog = false
    @State private var pfadtext = ""
    @State private var ablageAktiv = false
    @State private var verwerfenFragen = false
    /// Steht unter dem Datumsfeld, bis ein zulässiger Tag gewählt ist.
    @State private var sperrhinweis = ""
    /// Steht unter den Wochentagen, nachdem ein Wochenwechsel das Datum
    /// verfallen ließ — bis der nächste Tag gewählt oder getippt ist.
    @State private var wochenhinweis = ""
    @FocusState private var titelFokus: Bool
    @FocusState private var linkFokus: UUID?

    init(start: VorhabenEntwurf) {
        self.start = start
        _entwurf = State(initialValue: start)
    }

    private var planung: Planung? { speicher.planung }

    var body: some View {
        // Einmal je Body-Durchlauf statt zweimal: Wochenliste und Lagen sind teuer.
        let stand = planung?.wochenstand() ?? .leer

        Dialograhmen(titel: entwurf.istNeu ? "Neues Vorhaben" : "Vorhaben bearbeiten",
                     unterzeile: unterzeile(stand: stand), hoehe: 720,
                     beimSchliessen: abbrechen) {
            Section {
                TextField("Titel", text: $entwurf.titel,
                          prompt: Text("z. B. Stoffe und ihre Eigenschaften"))
                    .focused($titelFokus)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Weiterführende Informationen").foregroundStyle(.secondary)
                    Textfeld(text: $entwurf.text,
                             beschriftung: "Weiterführende Informationen")
                }

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

                Toggle("Durchgeführt", isOn: $entwurf.erledigt)
                Toggle("Als dringlich kennzeichnen", isOn: $entwurf.dringend)
                    .help("Dringliche Vorhaben tragen im Raster einen gelben Rahmen.")
            }

            kommentarbereich
            pruefungsbereich
            materialbereich
            linkbereich
        } fuss: {
            if !entwurf.istNeu {
                Button(role: .destructive) {
                    if let id = entwurf.vorhabenId { speicher.vorhabenLoeschen(id) }
                } label: {
                    Label("Löschen", systemImage: Zeichen.muell)
                }
            }
            Spacer(minLength: 0)
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Button("Übernehmen") { uebernehmen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { titelFokus = true }
        // Der Hinweis gilt der getroffenen Wahl; nach einem Wechsel sagt er
        // über die neue nichts mehr aus — `bestehendeSperre` rechnet sie nach.
        .onChange(of: entwurf.klasseId) { _, _ in sperrhinweis = "" }
        // Ein Wochenwechsel lässt Wochentag und Datum verfallen — wie beim
        // Verschieben im Raster (`Vorhaben.wocheWechseln`), nur mit dem
        // Hinweis an Ort und Stelle statt als Meldung.
        .onChange(of: entwurf.woche) { alt, neu in
            sperrhinweis = ""
            guard alt != neu, entwurf.datum != nil else { return }
            entwurf.datum = nil
            wochenhinweis = "Durch den Wechsel in eine andere Woche wurden Wochentag und Datum "
                + "zurückgesetzt."
        }
        // Ein neu gesetztes Datum — geklickt oder getippt — macht den Hinweis
        // gegenstandslos; das Verfallen selbst (auf nil) lässt ihn stehen.
        .onChange(of: entwurf.datum) { _, neu in if neu != nil { wochenhinweis = "" } }
        .alert("Die Änderungen an diesem Vorhaben verwerfen?", isPresented: $verwerfenFragen) {
            Button("Weiter bearbeiten", role: .cancel) {}
            Button("Verwerfen", role: .destructive) { schliessen() }
        }
        .sheet(isPresented: $pfadDialog) { pfadeinfuegen }
        .rueckfrage(speicher, ort: .vorhaben)
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
            ? "Für \(name) sind unter „Klassen/Kurse und Fächer“ keine Unterrichtstage "
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

    // ── Materialien ───────────────────────────────────────────────────────

    /// Was im Unterricht daraus wurde. Der Abschnitt steht immer da, auch
    /// leer — sonst ließe sich am Mac keine Notiz anlegen.
    @ViewBuilder
    private var kommentarbereich: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Textfeld(text: $entwurf.kommentar, mindesthoehe: 70,
                         beschriftung: "Kommentar zum Verlauf")
            }
        } header: {
            Text("Kommentar")
        } footer: {
            Text("Wie das Vorhaben gelaufen ist — getrennt von den weiterführenden "
                 + "Informationen, die sagen, was geplant war. Dieses Feld füllt auch die "
                 + "Ansicht fürs iPad; ihr Stand wird beim Start übernommen.")
        }
    }

    /// Kennzeichnung als Prüfung samt Termin.
    @ViewBuilder
    private var pruefungsbereich: some View {
        Section {
            Toggle("Als Prüfung führen", isOn: Binding(
                get: { entwurf.pruefung },
                set: { an in
                    entwurf.pruefung = an
                    sperrhinweis = ""
                    guard an, entwurf.pruefungstag == nil else { return }
                    terminSetzen(wochenmontag)
                }))

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
        } header: {
            Text("Prüfung")
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

            ablageflaeche

            HStack(spacing: 8) {
                Button {
                    aufnehmen(pfade: Systemzugriff.dateienWaehlen(start: planung?.basis ?? ""))
                } label: { Label("Datei wählen …", systemImage: Zeichen.datei) }

                Button {
                    aufnehmen(pfade: Systemzugriff.ordnerWaehlen(start: planung?.basis ?? ""))
                } label: { Label("Ordner wählen …", systemImage: Zeichen.ordner) }

                Button {
                    pfadtext = ""
                    pfadDialog = true
                } label: { Label("Pfad einfügen", systemImage: Zeichen.tastatur) }
            }
        } header: {
            Text("Materialien")
        } footer: {
            Text("Im Finder: Datei anwählen und mit ⌥⌘C den Pfad kopieren, dann „Pfad einfügen“.")
        }
    }

    private var ablageflaeche: some View {
        Text("Dateien aus dem Finder oder Links aus dem Browser hierher ziehen")
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
                let pfade = adressen.filter(\.isFileURL).map(\.path)
                let netz = adressen.filter { !$0.isFileURL }.map(\.absoluteString)
                if !pfade.isEmpty { aufnehmen(pfade: pfade) }
                if !netz.isEmpty { speicher.linksAufnehmen(netz, in: &entwurf) }
                if pfade.isEmpty, netz.isEmpty {
                    speicher.melden("Weder Pfad noch Webadresse erkannt — bitte „Datei wählen …“, "
                                    + "„Pfad einfügen“ oder „Link hinzufügen“ nutzen.", .warnung)
                    return false
                }
                return true
            } isTargeted: { ablageAktiv = $0 }
            .animation(.easeOut(duration: 0.15), value: ablageAktiv)
    }

    // ── Links ─────────────────────────────────────────────────────────────

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
            Button {
                let neu = Weblink(titel: "", adresse: "")
                entwurf.links.append(neu)
                linkFokus = neu.id
            } label: { Label("Link hinzufügen", systemImage: Zeichen.verweis) }
        } header: {
            Text("Links")
        } footer: {
            Text("Nur http- und https-Adressen; fehlt der Vorsatz, wird https:// ergänzt. "
                 + "Links lassen sich auch aus dem Browser auf die Ablagefläche oben ziehen.")
        }
    }

    // ── Pfad einfügen ─────────────────────────────────────────────────────

    private var pfadeinfuegen: some View {
        Dialograhmen(titel: "Pfad einfügen",
                     unterzeile: "Einen oder mehrere Pfade, je Zeile einer",
                     breite: 600, hoehe: 360) {
            Section {
                Textfeld(text: $pfadtext, mindesthoehe: 100,
                         beschriftung: "Pfade, je Zeile einer")
                Button {
                    pfadtext = Systemzugriff.ausZwischenablage()
                } label: { Label("Aus der Zwischenablage einsetzen", systemImage: Zeichen.kopie) }
            } header: {
                Text("Pfade")
            } footer: {
                Text("Auch file://-Adressen und Pfade relativ zum Basisordner werden erkannt.")
            }
        } fuss: {
            Spacer(minLength: 0)
            Button("Abbrechen") { pfadDialog = false }
                .keyboardShortcut(.cancelAction)
            Button("Hinzufügen") {
                aufnehmen(pfade: pfadtext.components(separatedBy: "\n"))
                pfadDialog = false
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
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

    private func abbrechen() {
        if entwurf.veraendert { verwerfenFragen = true } else { schliessen() }
    }

    private func uebernehmen() {
        if entwurf.leer {
            speicher.melden("Bitte wenigstens einen Titel eintragen.", .warnung)
            return
        }
        let schlecht = entwurf.ungueltigeLinks()
        if !schlecht.isEmpty {
            speicher.melden(schlecht.count == 1
                            ? "„\(schlecht[0])“ ist keine gültige http- oder https-Adresse."
                            : "\(schlecht.count) Adressen sind weder http noch https.", .warnung)
            return
        }
        speicher.vorhabenSichern(entwurf)
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
        .help(unterricht ? "\(tag.lang) — Unterrichtstag laut „Klassen/Kurse und Fächer“"
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

    var body: some View {
        HStack(spacing: Linkspalten.abstand) {
            Button { speicher.imFinderZeigen(material.pfad) } label: {
                Image(systemName: Zeichen.ordner)
            }
            .buttonStyle(.borderless)
            .frame(width: Linkspalten.symbol)
            .help("Im Finder zeigen")
            .accessibilityLabel("Im Finder zeigen")

            Tabellenfeld(hinweis: "Bezeichnung", text: $material.titel)
                .frame(width: Linkspalten.titel)

            Text((draussen ? "↗ " : "") + material.pfad)
                .font(.caption.monospaced())
                .foregroundStyle(draussen ? Color.orange : Color.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(draussen
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
