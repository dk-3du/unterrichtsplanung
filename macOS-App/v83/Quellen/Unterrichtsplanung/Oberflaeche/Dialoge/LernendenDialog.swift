// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Das Blatt „Lernende“ (⌘L) — die Lernendenverwaltung des laufenden
/// Schuljahrs. Drei Ansichten: die Lerngruppen mit ihren Mitgliedern, die
/// Übersicht aller Personen und das Archiv. Das Blatt arbeitet auf einem Entwurf mit eigenem
/// Verlauf (⌘Z); „Übernehmen“ trägt eine getippte Namensliste mit ein (E457)
/// und schreibt ihn versiegelt, „Abbrechen“ verwirft alles seit dem Öffnen.
/// Es gibt das Blatt nur mit eingeschalteter Verschlüsselung (E249) — darum
/// kein Datenschutzhinweis.
struct LernendenDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    /// Der Entwurf; `nil`, wenn die Lernendenverwaltung nicht offen ist.
    @State private var entwurf: Lernendenbestand?
    /// Der Stand beim Öffnen — für „Änderungen verwerfen?“.
    @State private var ausgang: Lernendenbestand?
    /// Je Stand gebaut, nicht je Auswertung des Körpers.
    @State private var verzeichnis = Lernendenverzeichnis(.leer(planung: "", schuljahr: "", jetzt: ""))
    @State private var ansicht: Lernendenansicht = .gruppen
    @State private var gruppe: String?
    @State private var person: String?
    @State private var archivierteZeigen = false
    @State private var neueGruppe = ""
    @State private var gruppenname = ""
    @State private var gruppenfach = ""
    @State private var nachname = ""
    @State private var vorname = ""
    @State private var rufname = ""
    /// Zu welcher Gruppe und Person die Felder geladen sind — dorthin wird
    /// geschrieben. Wechselt die Auswahl im selben Zug wie ein Handgriff (ein
    /// Klick auf den Stand in der Rücklaufliste), gehörten die Felder sonst der
    /// neuen Person, trugen aber die Namen der vorigen (B74).
    @State private var gruppenfelderFuer: String?
    @State private var namenFuer: String?
    @State private var namenstext = ""
    @State private var namenEingeben = false
    /// Was die Gruppenansicht rechts zeigt (E272).
    @State private var teil: Gruppenteil = .mitglieder
    /// Das Anliegen, das Rücklaufliste oder Maßnahmen beim Erscheinen wählen.
    @State private var startAnliegen: String?
    /// Der Filter „offen“ der Übersicht.
    @State private var nurOffen = false
    /// Die Datei des IServ-Imports, solange sein Bogen steht.
    @State private var importquelle: Importquelle?
    /// Maßnahme oder Termin ohne Gruppe, solange ihr Bogen steht (E290).
    @State private var anliegenvorlage: Anliegenvorlage?
    @FocusState private var fokus: Feld?

    private enum Feld: Hashable {
        case neueGruppe, gruppenname, gruppenfach, nachname, vorname, rufname
    }

    private var veraendert: Bool { entwurf != ausgang }
    private var jetzt: String { Zeitrechnung.jetztAlsZeitstempel() }

    private var unterzeile: String {
        guard let entwurf else { return speicher.lernende.sperrhinweis ?? "" }
        let personen = verzeichnis.alle.count
        let gruppen = entwurf.lerngruppen.filter { $0.archiviert.isEmpty }.count
        return "\(personen) \(personen == 1 ? "Person" : "Personen") in \(gruppen) "
            + (gruppen == 1 ? "Lerngruppe" : "Lerngruppen")
    }

    var body: some View {
        Dialograhmen(titel: "Lernende — Schuljahr " + (entwurf?.schuljahr ?? ""),
                     unterzeile: unterzeile, breite: 1000, hoehe: 720,
                     beimSchliessen: abbrechen, freierKoerper: true) {
            VStack(alignment: .leading, spacing: 12) {
                if let entwurf {
                    HStack(spacing: 16) {
                        Picker("Zeigen", selection: $ansicht) {
                            ForEach(Lernendenansicht.allCases, id: \.self) { Text($0.titel).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Spacer(minLength: 0)
                        if ansicht != .archiv {
                            Button("Aus IServ importieren …") { importdateiWaehlen() }
                                .help("Eine Exportdatei der IServ-Benutzerverwaltung lesen — nur Vorname, Nachname und Klasse")
                            Toggle("Archivierte zeigen", isOn: Binding(get: { archivierteZeigen },
                                                                    set: { archivierteZeigenSetzen($0) }))
                                .help("Archivierte Lerngruppen und Personen in den Listen zeigen — grau")
                        }
                    }
                    switch ansicht {
                    case .gruppen: gruppenansicht(entwurf)
                    case .alle: uebersicht
                    case .archiv: ArchivAnsicht()
                    }
                } else {
                    Text(speicher.lernende.sperrhinweis ?? "Die Lernendenverwaltung ist gerade nicht verfügbar.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
            // Fest wie beim Sitzplan: Listen haben keine eigene Höhe, das Blatt
            // nähme sonst nur die seines übrigen Inhalts an.
            .frame(height: 560, alignment: .top)
        } fuss: {
            Spacer(minLength: 0)
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Button("Übernehmen") { uebernehmen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(entwurf == nil)
        }
        .onAppear {
            laden()
            // Solange das Blatt steht, gehört ⌘Z ihm — wie im Sitzplan-Editor.
            speicher.lernendenblattUebernimmt({ zurueck in stand(zurueck) }, griff: Lernendenblattgriff(
                vorbereiten: { ausstehendeUebernehmen() },
                // Ein offener Bogen fragt beim Beenden zuerst, auf sich selbst (offener Punkt 2).
                bogenOffen: { importquelle != nil || anliegenvorlage != nil },
                bogenSchliessen: {
                    importquelle = nil
                    anliegenvorlage = nil
                },
                // Bliebe die gewählte Gruppe nach ⌘Z/⇧⌘Z sichtbar? (offener Punkt 1)
                gruppeBleibt: { stand in
                    guard let id = gruppe else { return true }
                    return Lernendenverzeichnis(stand).gruppe(id).map { archivierteZeigen || $0.archiviert.isEmpty } == true
                },
                ausgang: { ausgang },
                namenOffen: { namenOffen },
                namenVerwerfen: { namenVerwerfen() },
                aenderungen: { veraendert ? entwurf : nil }))
        }
        .onDisappear { speicher.lernendenblattGibtAb() }
        .onChange(of: gruppe) { alt, _ in
            gruppenfelderUebernehmen()
            // Ein Wechsel der Gruppe beendet die Eingabe — nicht das erste Wählen beim Öffnen.
            if alt != nil {
                namenEingeben = false
                namenstext = ""
            }
            felderLaden()
        }
        .onChange(of: person) { alt, _ in
            namenUebernehmen()
            felderLaden()
        }
        .onChange(of: fokus) { alt, _ in
            switch alt {
            case .gruppenname, .gruppenfach: gruppenfelderUebernehmen()
            case .nachname, .vorname, .rufname: namenUebernehmen()
            default: break
            }
        }
        .onChange(of: archivierteZeigen) { _, _ in auswahlPruefen() }
        .sheet(item: $importquelle) { quelle in
            ImportBogen(
                quelle: quelle,
                gruppen: (entwurf?.lerngruppen ?? []).filter { $0.archiviert.isEmpty }.sorted(by: Lerngruppe.vorgehen),
                vorwahl: ansicht == .gruppen ? gruppe : nil,
                vorschau: { lesung, ziel in
                    entwurf?.mitImport(lesung, ziel: ziel, jetzt: jetzt).bilanz ?? Importbilanz()
                },
                importieren: { lesung, ziel in importieren(lesung, ziel) },
                archivieren: { ids in
                    handgriff(Schrittname.fehlendeArchivieren) { $0.mitArchiviertenPersonen(ids, jetzt: jetzt) }
                },
                personenname: { verzeichnis.person($0)?.anzeigename ?? "—" })
            // Eine Frage, die den Bogen betrifft, steht auf ihm (offener Punkt 2).
            .rueckfrage(speicher, ort: .bogen)
        }
        .rueckfrage(speicher, ort: .lernende)
    }

    // ── Lerngruppen und ihre Mitglieder ───────────────────────────────────

    private func gruppenansicht(_ entwurf: Lernendenbestand) -> some View {
        HStack(alignment: .top, spacing: 16) {
            gruppenliste(entwurf)
                .frame(width: 240)
            Group {
                if let id = gruppe, let g = verzeichnis.gruppe(id) {
                    gruppenabschnitt(g)
                } else {
                    Text(entwurf.lerngruppen.isEmpty
                         ? "Noch keine Lerngruppe — links eine anlegen, dann die Namen eintragen."
                         : "Links eine Lerngruppe wählen.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Ob eine getippte, noch nicht eingetragene Namensliste steht — am Text
    /// allein: In einer leeren Gruppe steht die Eingabe auch ohne `namenEingeben` (Z14b-10).
    private var namenOffen: Bool {
        !namenstext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func namenVerwerfen() {
        namenstext = ""
        namenEingeben = false
    }

    /// Ob die getippte Liste gerade zu sehen ist — dieselbe Bedingung wie die Darstellung (Z-AV2a-01).
    private var namenSichtbar: Bool {
        guard ansicht == .gruppen, teil == .mitglieder, let id = gruppe, verzeichnis.gruppe(id) != nil else { return false }
        return namenEingeben || verzeichnis.mitglieder(id, archivierte: archivierteZeigen).isEmpty
    }

    /// Die Liste wieder vorn: Lerngruppen, Mitglieder, die Eingabe offen (Z-AV2a-01).
    private func namenZeigen() {
        ansicht = .gruppen
        teil = .mitglieder
        namenEingeben = true
    }

    /// Was eine getippte, noch nicht eingetragene Namensliste verwerfen würde,
    /// fragt zuerst (E303) — wie im Sitzplan-Editor; „Weiter bearbeiten“ lässt
    /// alles, wie es ist. `weiter` folgt der Frage verzögert: Eine nächste
    /// Rückfrage hängt am selben Blatt und ginge sonst mit dem Schließen dieser.
    private func namenVorher(_ weiter: @escaping @MainActor () -> Void) {
        guard namenOffen else {
            weiter()
            return
        }
        speicher.fragen("Die eingegebenen Namen verwerfen?", bestaetigung: "Verwerfen", gefahr: true, ort: .lernende,
                        ablehnung: "Weiter bearbeiten", nachDemSchliessen: true) {
            namenVerwerfen()
            // Steht inzwischen eine andere Frage, gilt sie — nichts überschreibt sie (Z14b-11).
            speicher.nachDerAntwort { weiter() }
        }
    }

    /// Abschalten blendet eine archivierte gewählte Gruppe aus — mit ihr ginge eine getippte Liste (E303, Z14b-01).
    private func archivierteZeigenSetzen(_ an: Bool) {
        let verdeckt = !an && gruppe.flatMap { verzeichnis.gruppe($0) }.map { !$0.archiviert.isEmpty } == true
        guard verdeckt else {
            archivierteZeigen = an
            return
        }
        namenVorher { archivierteZeigen = an }
    }

    /// Ein Klick in die Gruppenliste (E303): bis zur Antwort bleibt die Gruppe gewählt.
    private func gruppeWaehlen(_ neu: String?) {
        guard neu != gruppe else { return }
        guard gruppe != nil else {
            gruppe = neu
            return
        }
        namenVorher { gruppe = neu }
    }

    private func gruppenliste(_ entwurf: Lernendenbestand) -> some View {
        let gruppen = entwurf.lerngruppen
            .filter { archivierteZeigen || $0.archiviert.isEmpty }
            .sorted(by: Lerngruppe.vorgehen)
        return VStack(alignment: .leading, spacing: 8) {
            List(selection: Binding(get: { gruppe }, set: { gruppeWaehlen($0) })) {
                ForEach(gruppen) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.beschriftung)
                        Text(gruppenzeile(g))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(g.archiviert.isEmpty ? .primary : .secondary)
                    .tag(g.id)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()

            HStack(spacing: 8) {
                TextField("Neue Lerngruppe", text: $neueGruppe)
                    .focused($fokus, equals: .neueGruppe)
                    .onSubmit { gruppeAnlegen() }
                Button {
                    gruppeAnlegen()
                } label: {
                    Label("Anlegen", systemImage: Zeichen.plus)
                }
                .disabled(neueGruppe.trimmingCharacters(in: .whitespaces).isEmpty
                          || entwurf.lerngruppen.count >= Kennwerte.maxLerngruppen)
                .help("Eine Lerngruppe mit diesem Namen anlegen (⏎)")
            }
        }
    }

    private func gruppenzeile(_ g: Lerngruppe) -> String {
        let zahl = verzeichnis.mitgliederzahl(g.id)
        var teile = ["\(zahl) \(zahl == 1 ? "Mitglied" : "Mitglieder")",
                     g.art == .klasse ? "Klasse" : "Kurs"]
        if !g.archiviert.isEmpty { teile.append("archiviert") }
        return teile.joined(separator: " · ")
    }

    private func gruppenabschnitt(_ g: Lerngruppe) -> some View {
        let mitglieder = verzeichnis.mitglieder(g.id, archivierte: archivierteZeigen)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Name", text: $gruppenname)
                    .focused($fokus, equals: .gruppenname)
                    .onSubmit { gruppenfelderUebernehmen() }
                    .frame(width: 180)
                TextField("Fach", text: $gruppenfach)
                    .focused($fokus, equals: .gruppenfach)
                    .onSubmit { gruppenfelderUebernehmen() }
                    .frame(width: 160)
                Picker("Art", selection: Binding(
                    get: { g.art },
                    set: { art in
                        handgriff(Schrittname.lerngruppenartAendern, kennung: g.id) { $0.mitArt(g.id, art, jetzt: jetzt) }
                    })) {
                    Text("Klasse").tag(Lerngruppenart.klasse)
                    Text("Kurs").tag(Lerngruppenart.kurs)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                if g.archiviert.isEmpty {
                    Button("Archivieren") {
                        let archivieren: @MainActor () -> Void = {
                            handgriff(Schrittname.lerngruppeArchivieren) { $0.mitArchivierterGruppe(g.id, jetzt: jetzt) }
                        }
                        // Ausgeblendet ginge mit der Gruppe eine getippte Liste (E303, Z14b-01).
                        if archivierteZeigen { archivieren() } else { namenVorher(archivieren) }
                    }
                    .help("Die Lerngruppe aus den Listen nehmen — Mitglieder und Einträge bleiben")
                } else {
                    Button("Zurückholen") {
                        handgriff(Schrittname.lerngruppeZurueckholen) { $0.mitZurueckgeholterGruppe(g.id, jetzt: jetzt) }
                    }
                }
                Button("Löschen …", role: .destructive) {
                    // Erst die getippte Liste, dann die Gruppe (E303, Z14b-01).
                    namenVorher {
                        ausstehendeUebernehmen()
                        guard let jetziger = self.entwurf else { return }
                        speicher.lerngruppeLoeschenFragen(g.id, in: jetziger) { neu in
                            entwurfAendern(Schrittname.lerngruppeLoeschen, neu)
                        }
                    }
                }
                .help("Die Lerngruppe samt ihren Mitteilungen löschen — mit Rückfrage und Zahl")
            }

            Picker("Teil", selection: $teil) {
                ForEach(Gruppenteil.allCases, id: \.self) { Text($0.titel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if teil == .mitteilungen, let bezug {
                Ruecklaufliste(gruppe: g, bezug: bezug, person: $person, startAnliegen: startAnliegen)
            } else if teil == .massnahmen, let bezug {
                Massnahmenliste(gruppe: g, bezug: bezug,
                                startZeile: startAnliegen.flatMap { a in person.map { "\(a)/\($0)" } })
            } else if namenEingeben || mitglieder.isEmpty {
                namensabschnitt(g, mitAbbruch: !mitglieder.isEmpty)
            } else {
                List(selection: $person) {
                    ForEach(mitglieder) { m in
                        HStack {
                            Text(m.anzeigename)
                            Spacer(minLength: 0)
                            if !m.archiviert.isEmpty {
                                Text("archiviert").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(m.archiviert.isEmpty ? .primary : .secondary)
                        .tag(m.id)
                    }
                }
                .listStyle(.bordered)
                .alternatingRowBackgrounds()

                if let id = person, let p = verzeichnis.person(id), mitglieder.contains(where: { $0.id == id }) {
                    personenleiste(p, gruppe: g.id)
                }
                HStack(spacing: 12) {
                    Button("Namen eingeben …") { namenEingeben = true }
                        .help("Weitere Namen zeilenweise eintragen — mit Vorschau der Trennung")
                    Text("\(mitglieder.count) von \(Kennwerte.maxMitgliederJeLerngruppe) Plätzen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // ── Eingabe von Hand mit Vorschau der Trennung (E273) ─────────────────

    private static let beispiel = """
        Yilmaz, Amira
        Ben Fischer
        van der Berg, Lena
        …
        """

    private struct Vorschauzeile: Identifiable {
        let id: Int
        let name: Namenszeilen.Name
        let ausgang: Namensausgang

        /// Eingetragen wird, wer neu ist, zugeordnet oder zurückgeholt wird.
        var traegtEin: Bool {
            switch ausgang {
            case .neu, .zugeordnet, .zurueckgeholt: true
            default: false
            }
        }
    }

    /// Dieselbe Rechnung wie beim Eintragen — die Vorschau sagt, was geschieht (E288).
    private func vorschau(_ namen: [Namenszeilen.Name], gruppe g: String) -> [Vorschauzeile] {
        let ausgaenge = entwurf?.mitPersonen(namen, inGruppe: g, jetzt: jetzt).ausgaenge ?? []
        return zip(namen, ausgaenge).enumerated().map { stelle, paar in
            Vorschauzeile(id: stelle, name: paar.0, ausgang: paar.1)
        }
    }

    private func zustandstext(_ ausgang: Namensausgang) -> String {
        switch ausgang {
        case .neu, .leer: ""
        case .zugeordnet(let id):
            {
                let gruppen = verzeichnis.gruppen(von: id).filter { $0.archiviert.isEmpty }.map { "„\($0.beschriftung)“" }
                return gruppen.isEmpty ? "zugeordnet" : "zugeordnet (aus \(gruppen.joined(separator: ", ")))"
            }()
        case .zurueckgeholt: "zurückgeholt (war archiviert)"
        case .schonDa: "schon in der Lerngruppe"
        case .gleichnamig: "mehrfach im Schuljahr — nicht eingetragen"
        case .ueberGrenze: "über der Grenze"
        }
    }

    private func fehlerzeile(_ fehler: Namenszeilen.Fehler) -> AttributedString {
        var kopf = AttributedString("Zeile \(fehler.nummer): ")
        kopf.inlinePresentationIntent = .stronglyEmphasized
        return kopf + AttributedString("„\(fehler.zeile)“ — \(fehler.grund)")
    }

    private func namensabschnitt(_ g: Lerngruppe, mitAbbruch: Bool) -> some View {
        let gelesen = Namenszeilen.lesen(namenstext)
        let zeilen = vorschau(gelesen.namen, gruppe: g.id)
        let eintragen = zeilen.filter(\.traegtEin).count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Eine Zeile je Person: „Nachname, Vorname“ — ohne Komma gilt das letzte Wort als Nachname. "
                 + "Wer schon in der Lerngruppe steht, wird übergangen; wer in einer anderen Lerngruppe dieses "
                 + "Schuljahrs steht, wird zugeordnet — dieselbe Person, keine neue. "
                 + "Archivierte Personen der Lerngruppe werden zurückgeholt.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                Textfeld(text: $namenstext, mindesthoehe: 260, beschriftung: "Namen, eine Zeile je Person", namen: true)
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
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vorschau").font(.headline)
                    ScrollView {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow {
                                Text("Nachname").font(.caption).foregroundStyle(.secondary)
                                Text("Vorname").font(.caption).foregroundStyle(.secondary)
                                Text("")
                            }
                            ForEach(zeilen) { zeile in
                                GridRow {
                                    Text(zeile.name.nachname.isEmpty ? "—" : zeile.name.nachname)
                                    Text(zeile.name.vorname.isEmpty ? "—" : zeile.name.vorname)
                                    Text(zustandstext(zeile.ausgang))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(zeile.traegtEin ? .primary : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                    ForEach(gelesen.fehler.prefix(3)) { fehler in
                        Pruefzeile(gut: false, inhalt: Text(fehlerzeile(fehler)))
                    }
                    if gelesen.fehler.count > 3 {
                        Pruefzeile(gut: false, inhalt: Text("… und \(gelesen.fehler.count - 3) weitere Zeilen"))
                    }
                    if gelesen.fehler.isEmpty, !zeilen.isEmpty {
                        let zahlen = Dictionary(grouping: zeilen.map(\.ausgang)) { ausgang -> String in
                            switch ausgang {
                            case .neu: "neu"
                            case .zugeordnet: "zugeordnet"
                            case .zurueckgeholt: "zurückgeholt"
                            case .schonDa: "schon in der Lerngruppe"
                            case .gleichnamig: "mehrfach im Schuljahr"
                            case .ueberGrenze: "über der Grenze"
                            case .leer: "leer"
                            }
                        }.mapValues(\.count)
                        let teile = ["neu", "zugeordnet", "zurückgeholt", "schon in der Lerngruppe", "mehrfach im Schuljahr",
                                     "über der Grenze"]
                            .compactMap { art in zahlen[art].map { "\($0) \(art)" } }
                        Pruefzeile(gut: zahlen["mehrfach im Schuljahr"] == nil && zahlen["über der Grenze"] == nil,
                                   inhalt: Text(teile.joined(separator: " · ")))
                    }
                }
                .frame(width: 330)
            }
            HStack(spacing: 12) {
                if mitAbbruch {
                    Button("Zurück zur Liste") {
                        namenstext = ""
                        namenEingeben = false
                    }
                }
                Button("Eintragen") { namenEintragen(g.id) }
                    .buttonStyle(.borderedProminent)
                    // ⌘⏎: Die Schreibmarke steht in der Liste, ⏎ macht dort eine neue Zeile.
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(eintragen == 0 || !gelesen.fehler.isEmpty)
                    .help("Die Namen in die Lerngruppe eintragen (⌘⏎)")
            }
        }
    }

    private func namenEintragen(_ g: String) {
        let gelesen = Namenszeilen.lesen(namenstext)
        guard gelesen.fehler.isEmpty, !gelesen.namen.isEmpty, let entwurf else { return }
        let ergebnis = entwurf.mitPersonen(gelesen.namen, inGruppe: g, jetzt: jetzt)
        eingetragen(ergebnis.bestand, meldung: Self.eintragsmeldung(ergebnis))
    }

    /// Eingetragen — mit „Eintragen“ oder „Übernehmen“ (E457): ein Schritt im Verlauf, die Eingabe leer.
    private func eingetragen(_ neu: Lernendenbestand, meldung: String?) {
        entwurfAendern(Schrittname.namenEintragen, neu)
        namenstext = ""
        namenEingeben = false
        if let meldung { speicher.melden(meldung, .warnung) }
    }

    /// Wer mehrfach im Schuljahr steht oder über der Grenze liegt — `nil`, wenn
    /// alle eingetragen oder schon da sind. „Übernehmen“ meldet dasselbe (E458).
    nonisolated static func eintragsmeldung(_ ergebnis: Namenseintrag) -> String? {
        guard ergebnis.ueberGrenze > 0 || ergebnis.gleichnamig > 0 else { return nil }
        return "\(ergebnis.neu.count + ergebnis.zugeordnet.count + ergebnis.zurueckgeholt.count) eingetragen"
            + (ergebnis.ueberGrenze > 0 ? " — \(ergebnis.ueberGrenze) über der Grenze von "
               + "\(Kennwerte.maxMitgliederJeLerngruppe) je Lerngruppe blieben draußen" : "")
            + (ergebnis.gleichnamig > 0 ? " — \(ergebnis.gleichnamig) Namen stehen mehrfach im Schuljahr "
               + "und wurden nicht eingetragen (nichts geraten)" : "") + "."
    }

    /// Was „Übernehmen“ mit der Namenseingabe tut (E457, E458) — rein, damit die Suite es prüft.
    /// Dieselbe Rechnung wie „Eintragen“; die Warnung nennt die erste Zeile, die die Vorschau rot zeigt.
    /// Eine verdeckte lesbare Liste wird erst gezeigt, nicht eingetragen (Z-AV2a-01).
    nonisolated static func listeBeimUebernehmen(_ text: String, gruppe: String?, sichtbar: Bool,
                                                 entwurf: Lernendenbestand, jetzt: String) -> Listenausgang {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .ohneListe }
        guard let gruppe, entwurf.lerngruppen.contains(where: { $0.id == gruppe }) else { return .fragen }
        let gelesen = Namenszeilen.lesen(text)
        if let fehler = gelesen.fehler.first {
            return .offenBleiben(warnung: "Zeile \(fehler.nummer) lässt sich nicht eintragen — nichts übernommen.")
        }
        guard sichtbar else {
            return .zeigen(hinweis: "Die getippten Namen sind noch nicht eingetragen — „Übernehmen“ trägt sie ein.")
        }
        let ergebnis = entwurf.mitPersonen(gelesen.namen, inGruppe: gruppe, jetzt: jetzt)
        return .eintragen(ergebnis.bestand, meldung: eintragsmeldung(ergebnis))
    }

    // ── Alle Lernenden ────────────────────────────────────────────────────

    private var uebersicht: some View {
        let personen = (archivierteZeigen ? verzeichnis.alleMitArchivierten : verzeichnis.alle)
            .filter { !nurOffen || verzeichnis.offeneZahl(von: $0.id) > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Nur mit offenen Anliegen", isOn: $nurOffen)
                    .help("Nur Personen mit offenen Mitteilungen, Maßnahmen oder Terminen zeigen")
                Spacer(minLength: 0)
                Text("\(personen.count) \(personen.count == 1 ? "Person" : "Personen")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Table(personen, selection: $person) {
                TableColumn("Nachname") { p in Text(p.nachname).foregroundStyle(ton(p)) }
                TableColumn("Vorname") { p in Text(p.vorname).foregroundStyle(ton(p)) }
                TableColumn("Rufname") { p in Text(p.rufname.isEmpty ? "—" : p.rufname).foregroundStyle(ton(p)) }
                    .width(110)
                TableColumn("Lerngruppen") { p in Text(gruppentext(p.id)).foregroundStyle(ton(p)) }
                TableColumn("Offene Anliegen") { p in
                    let offen = verzeichnis.offeneZahl(von: p.id)
                    Text(offen == 0 ? "—" : "\(offen)").foregroundStyle(ton(p))
                }
                .width(110)
                TableColumn("Angelegt") { p in Text(datum(p.angelegt)).foregroundStyle(ton(p)) }
                    .width(90)
            }
            if let id = person, let p = verzeichnis.person(id), personen.contains(where: { $0.id == id }) {
                Text(offeneAnliegenText(p.id))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                personenleiste(p, gruppe: nil)
                if let bezug {
                    Personenanliegen(person: p, bezug: bezug) { anliegenvorlage = mitPlanung($0) }
                }
            }
        }
        .sheet(item: $anliegenvorlage) { vorlage in
            AnliegenBogen(vorlage: vorlage) { titel, tag, uhrzeit, notiz, zeile in
                anliegenOhneGruppe(vorlage, titel: titel, tag: tag, uhrzeit: uhrzeit, notiz: notiz, zeile: zeile)
            }
            .rueckfrage(speicher, ort: .bogen)
        }
    }

    /// „Offen: Elternbrief (Mitteilung vom 07.09.2026) · Nacharbeit (Maßnahme bis 14.09.2026)“
    private func offeneAnliegenText(_ person: String) -> String {
        let offen = verzeichnis.offeneAnliegen(von: person)
        guard !offen.isEmpty else { return "Keine offenen Anliegen." }
        return "Offen: " + offen.map { a in
            switch a.art {
            case .mitteilung: a.titel + (Tag(iso: a.datum).map { " (Mitteilung vom \($0.deutsch))" } ?? " (Mitteilung)")
            case .massnahme: a.titel + (Tag(iso: a.frist).map { " (Maßnahme bis \($0.deutsch))" } ?? " (Maßnahme)")
            case .termin: a.titel + " (Termin am " + Anliegenbezug.tagtext(a.datum)
                + (a.uhrzeit.isEmpty ? "" : ", \(a.uhrzeit) Uhr") + ")"
            }
        }.joined(separator: " · ")
    }

    private func ton(_ p: Lernender) -> HierarchicalShapeStyle { p.archiviert.isEmpty ? .primary : .secondary }

    private func gruppentext(_ person: String) -> String {
        let gruppen = verzeichnis.gruppen(von: person).filter { archivierteZeigen || $0.archiviert.isEmpty }
        return gruppen.isEmpty ? "—" : gruppen.map(\.beschriftung).joined(separator: ", ")
    }

    private func datum(_ iso: String) -> String {
        Zeitrechnung.zeitpunkt(aus: iso).map { Tag($0).deutsch } ?? "—"
    }

    // ── Eine Person ───────────────────────────────────────────────────────

    /// Zwei Zeilen (E340): oben die Felder, unten „angelegt …“ und die Knöpfe — im Teil „Lerngruppen“
    /// reichte eine Zeile nicht, und die Knöpfe wurden stumm gekürzt (Punkt 9). Die Knöpfe in
    /// Eigenbreite (E341): Reicht der Platz ein andermal nicht, laufen sie sichtbar über.
    private func personenleiste(_ p: Lernender, gruppe g: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Nachname", text: $nachname)
                    .focused($fokus, equals: .nachname)
                    .onSubmit { namenUebernehmen() }
                    .frame(width: 170)
                TextField("Vorname", text: $vorname)
                    .focused($fokus, equals: .vorname)
                    .onSubmit { namenUebernehmen() }
                    .frame(width: 170)
                TextField("Rufname", text: $rufname)
                    .focused($fokus, equals: .rufname)
                    .onSubmit { namenUebernehmen() }
                    .frame(width: 130)
                    .help("Freiwillig: der Name, mit dem die Person gerufen wird — der Sitzplan nimmt ihn statt des Vornamens")
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text("angelegt " + datum(p.angelegt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Der Zeitpunkt der Anlage in dieser App")
                Spacer(minLength: 0)
                if let g {
                    Button("Aus der Lerngruppe nehmen") {
                        handgriff(Schrittname.ausLerngruppeNehmen) { $0.ohneMitglied(p.id, ausGruppe: g) }
                    }
                    .fixedSize()
                    .help("Die Person bleibt in der Lernendenverwaltung, ihre Einträge bleiben")
                }
                if p.archiviert.isEmpty {
                    Button("Archivieren") {
                        handgriff(Schrittname.personArchivieren) { $0.mitArchivierterPerson(p.id, jetzt: jetzt) }
                    }
                    .fixedSize()
                    .help("Die Person aus den Listen nehmen — ihre Einträge bleiben")
                } else {
                    Button("Zurückholen") {
                        handgriff(Schrittname.personZurueckholen) { $0.mitZurueckgeholterPerson(p.id, jetzt: jetzt) }
                    }
                    .fixedSize()
                }
                Button("Endgültig löschen …", role: .destructive) {
                    ausstehendeUebernehmen()
                    guard let jetziger = self.entwurf else { return }
                    speicher.personLoeschenFragen(p.id, in: jetziger) { neu in
                        entwurfAendern(Schrittname.personLoeschen, neu)
                    }
                }
                .fixedSize()
                .help("Die Person samt ihren Rückläufen und Einträgen dieses Schuljahrs löschen — mit Rückfrage")
            }
        }
        .padding(8)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }

    // ── Anliegen: der Weg der Ansichten in den Entwurf ────────────────────

    private var bezug: Anliegenbezug? {
        guard let entwurf else { return nil }
        return Anliegenbezug(
            entwurf: entwurf, verzeichnis: verzeichnis, archivierteZeigen: archivierteZeigen,
            handgriff: { name, kennung, tun in handgriff(name, kennung: kennung, tun) },
            anlegen: { art, titel, betroffene, datum, frist in
                anliegenAnlegen(art, titel: titel, betroffene: betroffene, datum: datum, frist: frist)
            },
            loeschen: { id in anliegenLoeschen(id) })
    }

    private func anliegenAnlegen(_ art: Anliegenart, titel: String, betroffene: [String], datum: String,
                                 frist: String) -> String? {
        ausstehendeUebernehmen()
        guard let entwurf, let gruppe else { return nil }
        guard let ergebnis = entwurf.mitNeuemAnliegen(art, titel: titel, lerngruppe: gruppe, betroffene: betroffene,
                                                      datum: datum, frist: frist, jetzt: jetzt) else {
            if entwurf.anliegen.count >= Lernendendatei.maxAnliegen {
                speicher.melden("Höchstens \(Lernendendatei.maxAnliegen) Mitteilungen, Maßnahmen und Termine je Schuljahr.",
                                .warnung)
            }
            return nil
        }
        entwurfAendern(art == .mitteilung ? Schrittname.mitteilungAnlegen : Schrittname.massnahmeAnlegen, ergebnis.bestand)
        return ergebnis.id
    }

    /// Aus dem Bogen an der Person: eine Maßnahme oder ein Termin ohne Gruppe
    /// anlegen oder ändern — ein Schritt im Verlauf. `false`: nichts geschah.
    private func anliegenOhneGruppe(_ v: Anliegenvorlage, titel: String, tag: Tag, uhrzeit: String,
                                    notiz: String, zeile: String?) -> Bool {
        ausstehendeUebernehmen()
        guard let entwurf else { return false }
        let termin = v.art == .termin
        if let alt = v.anliegen {
            let geaendert = entwurf.mitAnliegen(alt.id, titel: titel, datum: termin ? tag.iso : alt.datum,
                                                frist: termin ? alt.frist : tag.iso, notiz: notiz,
                                                uhrzeit: termin ? uhrzeit : nil, jetzt: jetzt)
            // Der Wunsch gehört zum Stand — derselbe Schritt, ⌘Z nimmt ihn mit (W3-03).
            entwurfAendern(termin ? Schrittname.terminAendern : Schrittname.massnahmeAendern, kennung: alt.id,
                           termin ? geaendert.mitTerminwunsch(alt.id, zeile: zeile) : geaendert)
            return true
        }
        guard let ergebnis = entwurf.mitNeuemAnliegen(v.art, titel: titel, lerngruppe: "", betroffene: [v.person.id],
                                                      datum: termin ? tag.iso : Tag.heute.iso,
                                                      frist: termin ? "" : tag.iso, uhrzeit: termin ? uhrzeit : "",
                                                      jetzt: jetzt) else {
            if entwurf.anliegen.count >= Lernendendatei.maxAnliegen {
                speicher.melden("Höchstens \(Lernendendatei.maxAnliegen) Mitteilungen, Maßnahmen und Termine je Schuljahr.",
                                .warnung)
            }
            return false
        }
        // Die Notiz im selben Schritt — angelegt wird ohne.
        let a = ergebnis.bestand.anliegen.first { $0.id == ergebnis.id }
        let neu = a.map { ergebnis.bestand.mitAnliegen($0.id, titel: $0.titel, datum: $0.datum, frist: $0.frist,
                                                        notiz: notiz, jetzt: jetzt) } ?? ergebnis.bestand
        // Das Vorhaben entsteht erst beim „Übernehmen“ — ⌘Z und „Abbrechen“ nehmen den Wunsch mit.
        entwurfAendern(termin ? Schrittname.terminAnlegen : Schrittname.massnahmeAnlegen,
                       termin ? neu.mitTerminwunsch(ergebnis.id, zeile: zeile) : neu)
        return true
    }

    /// Ein Termin bekommt, was der Bogen über die Planung wissen muss (E293).
    private func mitPlanung(_ v: Anliegenvorlage) -> Anliegenvorlage {
        guard v.art == .termin, let p = speicher.planung, let entwurf else { return v }
        var neu = v
        let erster = p.start.montagDerWoche
        neu.planung = Terminplanung(
            zeilen: p.klassen.map { Terminplanung.Zeile(id: $0.id, titel: $0.beschriftung) },
            vorbelegt: Terminabgleich.vorbelegteZeile(fuer: v.person.id, planung: p, bestand: entwurf),
            verbunden: v.anliegen.flatMap { a in p.eintraege.first { $0.termin == a.id }?.klasseId },
            erster: erster, letzter: erster.plus(tage: max(1, p.wochen) * 7 - 1))
        return neu
    }

    private func anliegenLoeschen(_ id: String) {
        ausstehendeUebernehmen()
        guard let entwurf, let anliegen = entwurf.anliegen.first(where: { $0.id == id }) else { return }
        speicher.anliegenLoeschenFragen(id, in: entwurf) { neu in
            let name = switch anliegen.art {
            case .mitteilung: Schrittname.mitteilungLoeschen
            case .massnahme: Schrittname.massnahmeLoeschen
            case .termin: Schrittname.terminLoeschen
            }
            entwurfAendern(name, neu)
        }
    }

    // ── Der Entwurf ───────────────────────────────────────────────────────

    /// **Der Weg, auf dem der Entwurf sich ändert** — er meldet den Schritt an
    /// und setzt ihn.
    private func entwurfAendern(_ name: String, kennung: String? = nil, _ neu: Lernendenbestand) {
        guard let vorher = entwurf, neu != vorher else { return }
        stand(neu)
        speicher.lernendenverlauf.anmelden(name, kennung: kennung, vorher: vorher, nachher: neu)
    }

    /// Ein Handgriff an Knopf oder Wahl: erst das Ausstehende aus den Feldern,
    /// dann der Handgriff am Entwurf, wie er dann ist — nicht am Stand, den
    /// das Blatt beim Zeichnen sah.
    private func handgriff(_ name: String, kennung: String? = nil,
                           _ tun: (Lernendenbestand) -> Lernendenbestand) {
        ausstehendeUebernehmen()
        guard let vorher = entwurf else { return }
        entwurfAendern(name, kennung: kennung, tun(vorher))
    }

    /// Einen Stand einsetzen — aus einem Handgriff oder aus dem Verlauf.
    private func stand(_ neu: Lernendenbestand) {
        entwurf = neu
        verzeichnis = Lernendenverzeichnis(neu)
        auswahlPruefen()
        felderLaden()
    }

    /// Was nicht mehr da ist oder nicht mehr gezeigt wird, ist nicht mehr gewählt.
    private func auswahlPruefen() {
        if let id = gruppe, verzeichnis.gruppe(id).map({ archivierteZeigen || $0.archiviert.isEmpty }) != true {
            gruppe = nil
        }
        if let id = person, verzeichnis.person(id).map({ archivierteZeigen || $0.archiviert.isEmpty }) != true {
            person = nil
        }
    }

    /// Die Felder zeigen den Stand — außer dem, in dem gerade geschrieben wird.
    private func felderLaden() {
        if fokus != .gruppenname && fokus != .gruppenfach {
            let g = gruppe.flatMap { verzeichnis.gruppe($0) }
            gruppenname = g?.name ?? ""
            gruppenfach = g?.fach ?? ""
            gruppenfelderFuer = g?.id
        }
        if fokus != .nachname && fokus != .vorname && fokus != .rufname {
            let p = person.flatMap { verzeichnis.person($0) }
            nachname = p?.nachname ?? ""
            vorname = p?.vorname ?? ""
            rufname = p?.rufname ?? ""
            namenFuer = p?.id
        }
    }

    /// Die neue Gruppe wird gewählt — eine getippte Liste der bisherigen fragt zuerst (E303, Z14b-01).
    private func gruppeAnlegen() {
        namenVorher { gruppeAnlegenOhneFrage() }
    }

    private func gruppeAnlegenOhneFrage() {
        ausstehendeUebernehmen()
        guard let entwurf else { return }
        guard let ergebnis = entwurf.mitNeuerGruppe(name: neueGruppe, fach: "", art: .klasse, jetzt: jetzt) else {
            if entwurf.lerngruppen.count >= Kennwerte.maxLerngruppen {
                speicher.melden("Höchstens \(Kennwerte.maxLerngruppen) Lerngruppen je Schuljahr.", .warnung)
            }
            return
        }
        entwurfAendern(Schrittname.lerngruppeAnlegen, ergebnis.bestand)
        neueGruppe = ""
        gruppe = ergebnis.id
        namenEingeben = true
    }

    /// Name und Fach der Gruppe `id`, wie sie in den Feldern stehen — nichts,
    /// wenn sie gleich sind.
    private func gruppenfelderUebernehmen() {
        guard let id = gruppenfelderFuer, let vorher = entwurf, let g = verzeichnis.gruppe(id) else { return }
        let name = Lernendenbestand.zeile(gruppenname, Planungsdatei.maxNamenslaenge)
        if name.isEmpty {
            gruppenname = g.name
        } else if name != g.name {
            entwurfAendern(Schrittname.lerngruppeUmbenennen, kennung: id,
                           vorher.mitGruppe(id, name: name, fach: g.fach, jetzt: jetzt))
        }
        guard let danach = entwurf, let h = verzeichnis.gruppe(id),
              Lernendenbestand.zeile(gruppenfach, Planungsdatei.maxNamenslaenge) != h.fach else { return }
        entwurfAendern(Schrittname.lerngruppenfachAendern, kennung: id,
                       danach.mitGruppe(id, name: h.name, fach: gruppenfach, jetzt: jetzt))
    }

    private func namenUebernehmen() {
        guard let id = namenFuer, let entwurf else { return }
        let neu = entwurf.mitPerson(id, vorname: vorname, nachname: nachname, rufname: rufname, jetzt: jetzt)
        if neu == entwurf {
            felderLaden()
        } else {
            entwurfAendern(Schrittname.nameAendern, kennung: id, neu)
        }
    }

    // ── Der IServ-Import (AP13) ───────────────────────────────────────────

    private func importdateiWaehlen() {
        ausstehendeUebernehmen()
        Systemzugriff.quelleWaehlen(nachricht: "Exportdatei der IServ-Benutzerverwaltung wählen",
                                    typen: [.commaSeparatedText, .tabSeparatedText, .plainText]) { url in
            if let url { importdateiLesen(url) }
        }
    }

    private func importdateiLesen(_ url: URL) {
        switch Ablage.gebundenLesen(url, hoechstens: IServImport.hoechstgroesse) {
        case .daten(let daten): importquelle = Importquelle(name: url.lastPathComponent, daten: daten)
        case .keine: speicher.melden("„\(url.lastPathComponent)“ ist nicht mehr da.", .warnung)
        case .zuGross(let groesse):
            speicher.melden("Die Datei ist mit \(groesse / 1024) KB zu groß für eine Liste der Benutzerverwaltung.", .warnung)
        case .unlesbar(let fehler): speicher.melden(fehler.localizedDescription, .warnung)
        }
    }

    /// Ein Schritt im Verlauf des Blatts; geschrieben wird mit „Übernehmen“.
    private func importieren(_ lesung: IServImport.Lesung, _ ziel: Importziel) -> Importbilanz {
        ausstehendeUebernehmen()
        guard let vorher = entwurf else { return Importbilanz() }
        let (neu, bilanz) = vorher.mitImport(lesung, ziel: ziel, jetzt: jetzt)
        entwurfAendern(Schrittname.ausIServImportieren, neu)
        speicher.melden("IServ-Import: \(bilanz.kurz).")
        return bilanz
    }

    // ── Öffnen, Übernehmen, Abbrechen ─────────────────────────────────────

    private func laden() {
        let start = speicher.lernendenEntwurfBeginnen()
        ausgang = start
        entwurf = start
        if let start { verzeichnis = Lernendenverzeichnis(start) }
        speicher.lernendenverlauf.leeren()
        let vorgabe = speicher.lernendenVorgabe ?? Lernendenvorgabe()
        speicher.lernendenVorgabe = nil
        ansicht = vorgabe.ansicht
        let erste = start?.lerngruppen.filter { $0.archiviert.isEmpty }.min(by: Lerngruppe.vorgehen)?.id
        gruppe = vorgabe.gruppe.flatMap { verzeichnis.gruppe($0)?.id } ?? erste
        person = nil
        felderLaden()
        if let text = vorgabe.namenstext {
            namenstext = text
            namenEingeben = true
        }
        teil = vorgabe.gruppenteil
        startAnliegen = vorgabe.anliegen
        nurOffen = vorgabe.nurOffen
        if let id = vorgabe.person, verzeichnis.person(id) != nil { person = id }
        // Der Bogen erst, wenn das Blatt steht — ein Fenster trägt einen Bogen.
        if let datei = vorgabe.importdatei {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { importdateiLesen(datei) }
        }
        if let art = vorgabe.anliegenbogen, let p = person.flatMap({ verzeichnis.person($0) }) {
            let bestehend = vorgabe.anliegen.flatMap { id in start?.anliegen.first { $0.id == id } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                anliegenvorlage = mitPlanung(Anliegenvorlage(art: art, person: p, anliegen: bestehend,
                                                             tag: vorgabe.anliegentag))
            }
        }
        if let ziel = vorgabe.gruppenwechsel {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { gruppeWaehlen(ziel) }
        }
    }

    /// Was in einem Feld steht und noch nicht übernommen ist, kommt mit.
    private func ausstehendeUebernehmen() {
        gruppenfelderUebernehmen()
        namenUebernehmen()
    }

    private func abbrechen() {
        // In der Lücke nach einer Antwort prallt der Knopf ab, auch ⎋ (E437).
        guard !speicher.frageSperrtBefehl() else { return }
        ausstehendeUebernehmen()
        // Eine getippte, nicht eingetragene Liste ist auch eine Änderung (Z14b-02).
        if veraendert || namenOffen {
            speicher.lernendenVerwerfenFragen { schliessen() }
        } else {
            schliessen()
        }
    }

    /// „Übernehmen“ schließt „Eintragen“ ein (E457): Eine lesbare getippte Liste wird eingetragen wie mit
    /// „Eintragen“, dann übernommen; mit einer fehlerhaften Zeile bleibt das Blatt offen (E458).
    private func uebernehmen() {
        guard !speicher.frageSperrtBefehl() else { return }
        ausstehendeUebernehmen()
        guard let entwurf else {
            schliessen()
            return
        }
        switch Self.listeBeimUebernehmen(namenstext, gruppe: gruppe, sichtbar: namenSichtbar, entwurf: entwurf, jetzt: jetzt) {
        case .ohneListe:
            entwurfUebernehmen()
        case .eintragen(let neu, let meldung):
            eingetragen(neu, meldung: meldung)
            entwurfUebernehmen()
        case .offenBleiben(let warnung):
            namenZeigen()
            speicher.melden(warnung, .warnung)
        case .zeigen(let hinweis):
            namenZeigen()
            speicher.melden(hinweis, .hinweis)
        case .fragen:
            // Ohne Lerngruppe zur Liste fragt es wie die übrigen Wege (E303, Z14b-02).
            namenVorher { entwurfUebernehmen() }
        }
    }

    /// Übernommen wird der Entwurf, dann geht das Blatt.
    private func entwurfUebernehmen() {
        ausstehendeUebernehmen()
        // Ein Wunsch allein ist auch eine Änderung: ein Vorhaben für einen bestehenden Termin (W3-03).
        if let entwurf, veraendert {
            speicher.lernendenUebernehmen(entwurf, ausgang: ausgang)
        }
        schliessen()
    }
}

/// Was „Übernehmen“ im Blatt „Lernende“ mit der Namenseingabe tut (E457, E458).
enum Listenausgang: Equatable, Sendable {
    /// Keine getippte Liste — übernommen wird wie bisher.
    case ohneListe
    /// Eine lesbare Liste: der Stand nach dem Eintragen wie mit „Eintragen“ und dessen Meldung
    /// (mehrfach im Schuljahr, über der Grenze); danach wird übernommen.
    case eintragen(Lernendenbestand, meldung: String?)
    /// Eine fehlerhafte Zeile: Das Blatt bleibt offen, nichts übernommen, nichts verloren — die Warnung nennt die erste.
    /// Die Liste kommt wieder nach vorn, auch wenn sie verdeckt war (Z-AV2a-01).
    case offenBleiben(warnung: String)
    /// Eine lesbare Liste, verdeckt von einer anderen Darstellung: Sie kommt nach vorn, das Blatt bleibt offen, der
    /// Hinweis sagt es — eingetragen wird erst mit dem nächsten „Übernehmen“ (Z-AV2a-01).
    case zeigen(hinweis: String)
    /// Eine Liste ohne ihre Lerngruppe im Entwurf — es fragt wie die übrigen Wege (E303).
    case fragen
}
