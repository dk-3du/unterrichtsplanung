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
    /// Die Suche unter „Alle Lernenden“ und der Filter der Gruppenliste (E359, E360) — je Sitzung.
    @State private var suche = ""
    @State private var gruppensuche = ""
    /// Die Ordnung der Tabelle „Alle Lernenden“ — je Sitzung, verfällt mit dem Blatt (E362–E364).
    @State private var ordnung = Personenzeile.vorgabe
    /// Die Zeilen von „Alle Lernenden“ — gebaut, wenn sich Stand, Suche, Filter oder Ordnung ändern, nicht bei jeder
    /// Auswertung des Körpers (Z-AT2b-01: nach Vorname geordnet rund 50 ms bei 2 000 Personen).
    @State private var zeilen: [Personenzeile] = []
    /// Die Ordnung der drei Archiv-Tabellen — am Blatt, damit sie erst mit ihm verfällt (E364, Z-AT2b-07).
    @State private var archivordnung = Archivordnung()
    /// Die Ordnung der Tabellen der Anliegen — am Blatt, damit sie erst mit ihm verfällt (E364, E501).
    @State private var anliegenordnung = Anliegenordnung()
    /// Die Datei des IServ-Imports, solange sein Bogen steht.
    @State private var importquelle: Importquelle?
    /// Maßnahme oder Termin ohne Gruppe, solange ihr Bogen steht (E290).
    @State private var anliegenvorlage: Anliegenvorlage?
    /// Der Bogen „Zeilen wählen“, solange er steht (E669).
    @State private var zeilenwahl: Zeilenwahlvorlage?
    /// Aus der Vorgabe: den Bogen öffnen, sobald der Kopf der gewählten Gruppe erscheint (E678) — einmal.
    @State private var zeilenwahlBeimKopf = false
    /// Der Bogen „Rückmeldungsliste“, solange er steht (E401).
    @State private var rueckmeldungsbogen: Rueckmeldungslistenvorlage?
    /// Was nach dem Schließen dieses Bogens folgt: der Sichern- oder der Druckdialog — erst am Blatt, ein Fenster
    /// trägt einen Bogen.
    @State private var nachDemBogen: (@MainActor () -> Void)?
    /// Aus der Vorgabe: den Bogen „Rückmeldungsliste“ dieser Gruppe öffnen, sobald ihr Teil „Mitteilungen“ erscheint — einmal.
    @State private var rueckmeldungslisteBeimTeil: (gruppe: String, vorgabe: Rueckmeldungsbogenvorgabe)?
    /// Wohin es nach dem Blatt zurückgeht — aus ⌘K dorthin (E358, E505), sonst ins Hauptfenster.
    @State private var rueckweg: Dialogfenster?
    @FocusState private var fokus: Feld?

    private enum Feld: Hashable {
        case neueGruppe, gruppenname, nachname, vorname, rufname, suche, gruppensuche
    }

    /// Ein Suchfeld wie im Material-Blatt: Lupe, Feld, Löschknopf.
    private struct Suchfeld: View {
        @Binding var text: String
        let platzhalter: String
        let beschriftung: String
        var fokus: FocusState<Feld?>.Binding
        let feld: Feld

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(platzhalter, text: $text)
                    .textFieldStyle(.plain)
                    // ⏎ bleibt im Feld — sonst löste es „Übernehmen“ aus (Z-AT2b-06).
                    .onSubmit {}
                    .focused(fokus, equals: feld)
                    .accessibilityLabel(beschriftung)
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Suche löschen")
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(Systemfarben.feldflaeche, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Systemfarben.feldkante.opacity(0.55)))
        }
    }

    /// ⌘F im Blatt (E361): die Schreibmarke in die Suche der Ansicht — unter „Lerngruppen“ in den Filter der Liste.
    private var suchkuerzel: some View {
        Button("Suchen") {
            switch ansicht {
            case .gruppen: fokus = .gruppensuche
            case .alle: fokus = .suche
            case .archiv: break
            }
        }
        .keyboardShortcut("f", modifiers: .command)
        .opacity(0)
        .allowsHitTesting(false)
        .focusable(false)
        .accessibilityHidden(true)
    }

    private var veraendert: Bool { entwurf != ausgang }
    private var jetzt: String { Zeitrechnung.jetztAlsZeitstempel() }

    private var unterzeile: String {
        guard let entwurf else { return speicher.lernende.sperrhinweis ?? "" }
        // Dieselbe Zeile wie in ⌘K (Z-AT4-03).
        return Lernendenblatt.zaehlzeile(personen: verzeichnis.alle.count,
                                         gruppen: entwurf.lerngruppen.filter { $0.archiviert.isEmpty }.count)
    }

    var body: some View {
        // Liegt ein Bogen auf dem Blatt, zeigt nur er die Meldungen — die Zeile des Blatts schaute sonst unter dem
        // niedrigeren Bogen hervor, und dieselbe Meldung stünde zweimal (Z-AT2-10, E490).
        Dialograhmen(titel: "Lernende — Schuljahr " + (entwurf?.schuljahr ?? ""),
                     unterzeile: unterzeile, breite: 1000, hoehe: 720,
                     beimSchliessen: abbrechen, freierKoerper: true,
                     meldungsblatt: importquelle == nil && anliegenvorlage == nil && zeilenwahl == nil
                        && rueckmeldungsbogen == nil ? .lernende : nil) {
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
                    case .archiv: ArchivAnsicht(ordnung: $archivordnung)
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
            .background { suchkuerzel }
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
                bogenOffen: { importquelle != nil || anliegenvorlage != nil || zeilenwahl != nil || rueckmeldungsbogen != nil },
                bogenSchliessen: {
                    importquelle = nil
                    anliegenvorlage = nil
                    zeilenwahl = nil
                    nachDemBogen = nil
                    rueckmeldungsbogen = nil
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
        // Abgemeldet wird beim Schließen im `didSet` von `offenerDialog`; dies ist nur das Netz. Es kann verspätet kommen —
        // nach dem Rückweg über ⌘K auch erst, wenn das nächste Blatt „Lernende“ schon steht und sich angemeldet hat.
        // Dann meldete es dieses ab (⌘Z ginge an die Planung, beim Beenden fehlte die Frage; D-AT4-01, E512).
        .onDisappear { if speicher.offenerDialog != .lernende { speicher.lernendenblattGibtAb() } }
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
            case .gruppenname: gruppenfelderUebernehmen()
            case .nachname, .vorname, .rufname: namenUebernehmen()
            default: break
            }
        }
        .onChange(of: archivierteZeigen) { _, _ in
            auswahlPruefen()
            zeilenBauen()
        }
        .onChange(of: suche) { _, _ in zeilenBauen() }
        .onChange(of: nurOffen) { _, _ in zeilenBauen() }
        .onChange(of: ordnung) { _, _ in zeilenBauen() }
        .sheet(item: $importquelle) { quelle in
            ImportBogen(
                quelle: quelle,
                gruppen: (entwurf?.lerngruppen ?? []).filter { $0.archiviert.isEmpty }.sorted(by: Lerngruppe.vorgehen),
                vorwahl: ansicht == .gruppen ? sichtbareGruppe : nil,
                vorschau: { lesung, ziel in
                    entwurf?.mitImport(lesung, ziel: ziel, jetzt: jetzt).bilanz ?? Importbilanz()
                },
                importieren: { lesung, ziel, binden in importieren(lesung, ziel, binden: binden) },
                archivieren: { ids in
                    handgriff(Schrittname.fehlendeArchivieren) { $0.mitArchiviertenPersonen(ids, jetzt: jetzt) }
                },
                // Nur die Mitgliedschaft in der Zielgruppe geht (E368), und nur, wenn die Person beim Klick noch
                // anderswo steht (Z-AT3-02) — derselbe Schritt wie im Blatt.
                herausnehmen: { liste in
                    handgriff(Schrittname.ausLerngruppeNehmen) {
                        $0.ohneMitgliedschaften(ImportBogen.nochAnderswo(liste, in: $0), jetzt: jetzt)
                    }
                },
                personenname: { verzeichnis.person($0)?.anzeigename ?? "—" })
            // Eine Frage, die den Bogen betrifft, steht auf ihm (offener Punkt 2).
            .rueckfrage(speicher, ort: .bogen)
        }
        .sheet(item: $rueckmeldungsbogen, onDismiss: nachDemBogenAusfuehren) { vorlage in
            RueckmeldungslisteBogen(
                gruppe: vorlage.gruppe,
                mitteilungen: verzeichnis.mitteilungen(der: vorlage.gruppe.id),
                vorgabe: vorlage.vorgabe,
                sichern: { auswahl, kennwort in rueckmeldungslisteSichern(vorlage.gruppe, auswahl, kennwort) },
                drucken: { auswahl in rueckmeldungslisteDrucken(vorlage.gruppe, auswahl) })
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
                // Fällt die gewählte aus der Suche, ist rechts keine gewählt — wie in „Alle Lernenden“ (E685).
                if let id = sichtbareGruppe, let g = verzeichnis.gruppe(id) {
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
        .sheet(item: $zeilenwahl) { vorlage in
            ZeilenwahlBogen(vorlage: vorlage) { gewaehlt in zeilenUebernehmen(vorlage.id, gewaehlt) }
                .rueckfrage(speicher, ort: .bogen)
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

    /// Die rechts gezeigte Lerngruppe (E685): gewählt und nicht vom Suchfeld der Liste verdeckt — eine Bedingung für Darstellung,
    /// Namensliste und Import (Z-AT15N-02).
    private var sichtbareGruppe: String? {
        guard let entwurf else { return nil }
        return Lernendenblatt.sichtbareWahl(gruppe, in: entwurf, suche: gruppensuche,
                                            zeilentitel: Lernendenblatt.zeilentitel(speicher.planung))
    }

    /// Ob die getippte Liste gerade zu sehen ist — dieselbe Bedingung wie die Darstellung (Z-AV2a-01, Z-AT15N-02).
    private var namenSichtbar: Bool {
        guard ansicht == .gruppen, teil == .mitglieder, let id = sichtbareGruppe, verzeichnis.gruppe(id) != nil else { return false }
        return namenEingeben || verzeichnis.mitglieder(id, archivierte: archivierteZeigen).isEmpty
    }

    /// Die Liste wieder vorn: Lerngruppen, Mitglieder, die Eingabe offen (Z-AV2a-01) — und das Suchfeld nur dann leer, wenn es
    /// die Lerngruppe verdeckt (Z-AT15N-02, Z-AT15M-02, Z-AT15L-01, Z-AT15K-03).
    private func namenZeigen() {
        ansicht = .gruppen
        teil = .mitglieder
        suchfeldFuerWahl()
        namenEingeben = true
    }

    /// Das Suchfeld nach `Lernendenblatt.sucheFuerWahl` — leer nur, wenn es die gewählte Lerngruppe verdeckt (Z-AT15L-02).
    private func suchfeldFuerWahl() {
        guard let entwurf else { return }
        gruppensuche = Lernendenblatt.sucheFuerWahl(gruppe, in: entwurf, suche: gruppensuche,
                                                    zeilentitel: Lernendenblatt.zeilentitel(speicher.planung))
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
        let gruppen = Lernendenblatt.gruppenliste(entwurf, archivierte: archivierteZeigen, suche: gruppensuche,
                                                  zeilentitel: Lernendenblatt.zeilentitel(speicher.planung))
        return VStack(alignment: .leading, spacing: 8) {
            Suchfeld(text: $gruppensuche, platzhalter: "Lerngruppe suchen", beschriftung: "Lerngruppen durchsuchen",
                     fokus: $fokus, feld: .gruppensuche)
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
            .overlay {
                if gruppen.isEmpty, let hinweis = Lernendenblatt.leerHinweis(suche: gruppensuche, nurOffen: false) {
                    Text(hinweis).foregroundStyle(.secondary).padding()
                }
            }

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
        var teile = ["\(zahl) \(zahl == 1 ? "Mitglied" : "Mitglieder")"]
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
                Spacer(minLength: 0)
                // Gleichnamige zusammenführen (E667, E672) — bei mehreren ein Menü, unterschieden an Zahl und erster Zeile.
                let gleich = entwurf.map { Lernendenblatt.gleichnamige(g.id, in: $0) } ?? []
                if gleich.count == 1, let andere = gleich.first {
                    Button("Zusammenführen mit …") { zusammenfuehren(g, andere) }
                        .help("Die andere Lerngruppe „\(andere.name)“ (\(mitgliedertext(andere.id))) mit dieser zusammenführen — "
                              + "mit Rückfrage")
                } else if gleich.count > 1 {
                    Menu("Zusammenführen mit") {
                        ForEach(gleich) { andere in
                            Button(zusammenfuehrenTitel(andere)) { zusammenfuehren(g, andere) }
                        }
                    }
                    .fixedSize()
                    .help("Eine andere Lerngruppe „\(g.name)“ mit dieser zusammenführen — mit Rückfrage")
                }
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
                        // Zeilen mit Sitzplan, mit denen inzwischen eine andere verknüpft ist, bekommt sie nicht wieder — der Hinweis
                        // sagt es (E689, Z-AT15N-01); der Name nach dem Handgriff, der eine getippte Änderung einträgt (Z-AT15N-08).
                        let sitz = Lernendenblatt.sitzplanzeilen(speicher.planung)
                        let besetzt = entwurf?.besetzteZeilen(von: g.id, unter: sitz) ?? []
                        handgriff(Schrittname.lerngruppeZurueckholen) {
                            $0.mitZurueckgeholterGruppe(g.id, jetzt: jetzt, sitzplanzeilen: sitz)
                        }
                        let name = entwurf?.lerngruppen.first { $0.id == g.id }?.name ?? g.name
                        if let hinweis = Lernendenblatt.zurueckgeholtHinweis(name, besetzt: besetzt,
                                                                             zeilentitel: Lernendenblatt.zeilentitel(speicher.planung)) {
                            speicher.melden(hinweis, .hinweis)
                        }
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

            // Mitgliederzahl, die verknüpften Zeilen und der Weg, sie zu wählen (E669).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                let verknuepft = Lernendenblatt.verknuepft(g, zeilentitel: Lernendenblatt.zeilentitel(speicher.planung),
                                                           planung: speicher.planung?.erstellt)
                Text(mitgliedertext(g.id) + " · " + verknuepft)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(verknuepft)
                Spacer(minLength: 0)
                Button("Zeilen wählen …") { zeilenWaehlen(g) }
                    .disabled(speicher.planung == nil || !g.archiviert.isEmpty)
                    .help("Die Zeilen dieser Planung wählen, mit denen die Lerngruppe verknüpft ist — eine Zeile kann mehrere tragen")
            }
            // Prüfstand und Abbild (E678): der Bogen aus der Vorgabe, wenn der Kopf steht — ohne Verzögerung.
            .task(id: g.id) {
                guard zeilenwahlBeimKopf else { return }
                zeilenwahlBeimKopf = false
                zeilenWaehlen(g)
            }

            Picker("Teil", selection: $teil) {
                ForEach(Gruppenteil.allCases, id: \.self) { Text($0.titel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if teil == .mitteilungen, let bezug {
                Ruecklaufliste(gruppe: g, bezug: bezug, person: $person, startAnliegen: startAnliegen,
                               ordnung: $anliegenordnung.ruecklauf, listeOeffnen: { rueckmeldungslisteOeffnen(g.id) })
                // Prüfstand und Abbild: der Bogen aus der Vorgabe, wenn der Teil steht — ohne Verzögerung, wie E678.
                .task(id: g.id) {
                    guard let ziel = rueckmeldungslisteBeimTeil else { return }
                    // Beim ersten Erscheinen verbraucht — für eine andere Gruppe öffnet er nie (Z-AW5a-06).
                    rueckmeldungslisteBeimTeil = nil
                    if ziel.gruppe == g.id { rueckmeldungslisteOeffnen(g.id, vorgabe: ziel.vorgabe) }
                }
            } else if teil == .massnahmen, let bezug {
                Massnahmenliste(gruppe: g, bezug: bezug,
                                startZeile: startAnliegen.flatMap { a in person.map { "\(a)/\($0)" } },
                                ordnung: $anliegenordnung.massnahmen)
            } else if namenEingeben || mitglieder.isEmpty {
                namensabschnitt(g, mitAbbruch: !mitglieder.isEmpty)
            } else {
                List(selection: $person) {
                    ForEach(mitglieder) { m in
                        HStack {
                            Text(m.anzeigename)
                            Spacer(minLength: 0)
                            // Mehrfachmitgliedschaft am Ort sichtbar (E370).
                            if let auch = Lernendenblatt.auchIn(verzeichnis.auchIn(m.id, ausser: g.id)) {
                                Text(auch).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
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
                    Text(Lernendenblatt.plaetze(g, verzeichnis, archivierte: archivierteZeigen))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func mitgliedertext(_ id: String) -> String {
        let zahl = verzeichnis.mitgliederzahl(id)
        return "\(zahl) \(zahl == 1 ? "Mitglied" : "Mitglieder")"
    }

    /// Im Menü „Zusammenführen mit“: „„6a“ — 10 Mitglieder, 6a · Chemie“ — Zahl und erste Zeile unterscheiden gleichnamige.
    private func zusammenfuehrenTitel(_ andere: Lerngruppe) -> String {
        let erste = Lernendenblatt.ersteZeile(andere, zeilentitel: Lernendenblatt.zeilentitel(speicher.planung),
                                              planung: speicher.planung?.erstellt)
        return "„\(andere.name)“ — \(mitgliedertext(andere.id)), \(erste)"
    }

    /// „Zeilen wählen …“ (E669): der Bogen mit einem Kästchen je Zeile der geöffneten Planung.
    private func zeilenWaehlen(_ gezeichnet: Lerngruppe) {
        ausstehendeUebernehmen()
        guard let planung = speicher.planung, let entwurf,
              let g = entwurf.lerngruppen.first(where: { $0.id == gezeichnet.id && $0.archiviert.isEmpty }) else { return }
        let titel = Lernendenblatt.zeilentitel(planung)
        zeilenwahl = Zeilenwahlvorlage(id: g.id, name: g.name, zeilen: Zeilenwahl.zeilen(planung, bestand: entwurf, gruppe: g.id),
                                       aussen: g.zeilen.count { titel[$0] == nil })
    }

    /// Aus dem Bogen: die Wahl als ein Schritt im Entwurf — wie jeder Bindeweg erst die Herkunft der Planung auf die
    /// Platte (A4, E525). `false`: Der Bogen bleibt offen, die Meldung sagt warum.
    private func zeilenUebernehmen(_ gruppe: String, _ gewaehlt: Set<String>) -> Bool {
        // Ändert die Wahl nichts, schließt der Bogen ohne Schritt und ohne Sicherung (Z-AT9a2-05).
        if let planung = speicher.planung, let entwurf,
           entwurf.mitZeilen(gruppe, gewaehlt, zeilen: planung.klassen, planung: planung.erstellt, jetzt: jetzt) == entwurf {
            return true
        }
        if let grund = speicher.herkunftSichern() {
            speicher.melden(grund, .warnung)
            return false
        }
        guard let planung = speicher.planung else { return false }
        handgriff(Schrittname.zeilenWaehlen) {
            $0.mitZeilen(gruppe, gewaehlt, zeilen: planung.klassen, planung: planung.erstellt, jetzt: jetzt)
        }
        return true
    }

    /// Zwei gleichnamige zusammenführen (E667, E672) — nach der Rückfrage ein Schritt im Verlauf des Blatts; über den
    /// Grenzen gleich die Meldung, ohne Frage.
    private func zusammenfuehren(_ gezeichnet: Lerngruppe, _ andere: Lerngruppe) {
        // Erst das Ausstehende (ein getippter Name), dann neu lesen: Gilt die andere dann nicht mehr als gleichnamig, nichts
        // (Z-AT9a2-03).
        ausstehendeUebernehmen()
        guard let jetziger = entwurf, let g = jetziger.lerngruppen.first(where: { $0.id == gezeichnet.id }),
              Lernendenblatt.gleichnamige(g.id, in: jetziger).contains(where: { $0.id == andere.id }) else { return }
        if let grund = jetziger.mitZusammenfuehrung(andere.id, in: g.id, jetzt: jetzt).grund {
            speicher.melden(grund, .warnung)
            return
        }
        // Wie jede Frage am Blatt erst nach dem Schließen des Alerts (E431).
        speicher.fragen(Lernendenblatt.zusammenfuehrenFrage(name: g.name, andere: verzeichnis.mitgliederzahl(andere.id)),
                        bestaetigung: "Zusammenführen", ort: .lernende, nachDemSchliessen: true) {
            handgriff(Schrittname.lerngruppenZusammenfuehren) { $0.mitZusammenfuehrung(andere.id, in: g.id, jetzt: jetzt).bestand }
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
        // Erst gesucht und gefiltert, dann geordnet (E360, E363); die Auswahl bleibt, wenn der Treffer sie trägt.
        let personen = zeilen
        let gesamt = (archivierteZeigen ? verzeichnis.alleMitArchivierten : verzeichnis.alle).count
        let gefiltert = nurOffen || !Lernendenverzeichnis.suchworte(suche).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Suchfeld(text: $suche, platzhalter: "Nachname, Vorname oder Rufname", beschriftung: "Lernende durchsuchen",
                         fokus: $fokus, feld: .suche)
                    .frame(width: 300)
                Toggle("Nur mit offenen Anliegen", isOn: $nurOffen)
                    .help("Nur Personen mit offenen Mitteilungen, Maßnahmen oder Terminen zeigen")
                Spacer(minLength: 0)
                Text(Lernendenblatt.zaehler(treffer: personen.count, gesamt: gesamt, gefiltert: gefiltert))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Ein Kopfklick ordnet nach der Spalte; die vorige bleibt Zweitschlüssel (E363), je Sitzung (E364).
            Table(personen, selection: $person,
                  sortOrder: Binding(get: { ordnung }, set: { ordnung = Tabellenordnung.mitVorigem($0, vorher: ordnung) })) {
                TableColumn(kopf("Nachname", \.nachname), sortUsing: Personenspalte.nachname.vergleicher) { z in
                    Text(z.nachname).foregroundStyle(ton(z.id))
                }
                TableColumn(kopf("Vorname", \.vorname), sortUsing: Personenspalte.vorname.vergleicher) { z in
                    Text(z.vorname).foregroundStyle(ton(z.id))
                }
                TableColumn(kopf("Rufname", \.rufname), sortUsing: Personenspalte.rufname.vergleicher) { z in
                    Text(z.rufname.isEmpty ? "—" : z.rufname).foregroundStyle(ton(z.id))
                }
                .width(110)
                TableColumn(kopf("Lerngruppen", \.lerngruppen), sortUsing: Personenspalte.lerngruppen.vergleicher) { z in
                    Text(z.lerngruppen.isEmpty ? "—" : z.lerngruppen).foregroundStyle(ton(z.id))
                }
                TableColumn(kopf("Offene Anliegen", \.offene), sortUsing: Personenspalte.offene.vergleicher) { z in
                    Text(z.offene == 0 ? "—" : "\(z.offene)").foregroundStyle(ton(z.id))
                }
                .width(110)
                TableColumn(kopf("Angelegt", \.angelegt), sortUsing: Personenspalte.angelegt.vergleicher) { z in
                    Text(datum(z.angelegt)).foregroundStyle(ton(z.id))
                }
                .width(90)
            }
            .overlay {
                if personen.isEmpty, let hinweis = Lernendenblatt.leerHinweis(suche: suche, nurOffen: nurOffen) {
                    Text(hinweis).foregroundStyle(.secondary)
                }
            }
            if let id = person, let p = verzeichnis.person(id), personen.contains(where: { $0.id == id }) {
                Text(offeneAnliegenText(p.id))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                personenleiste(p, gruppe: nil)
                if let bezug {
                    Personenanliegen(person: p, bezug: bezug, ordnung: $anliegenordnung.personenanliegen) {
                        anliegenvorlage = mitPlanung($0)
                    }
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

    /// Der Kopf einer Spalte von „Alle Lernenden“ — hervorgehoben, wenn sie vorn ordnet (E498).
    private func kopf(_ titel: String, _ pfad: PartialKeyPath<Personenzeile>) -> Text {
        Ordnungskopf.text(titel, vorn: Lernendenblatt.vorn(ordnung, pfad))
    }

    /// Die Zeilen neu bauen — nach jedem Stand und jeder Änderung von Suche, Filter, Schalter oder Ordnung.
    private func zeilenBauen() {
        zeilen = Lernendenblatt.uebersicht(verzeichnis, suche: suche, archivierte: archivierteZeigen, nurOffen: nurOffen,
                                           ordnung: ordnung)
    }

    /// Archivierte grau.
    private func ton(_ person: String) -> HierarchicalShapeStyle {
        verzeichnis.person(person)?.archiviert.isEmpty == false ? .secondary : .primary
    }

    private func datum(_ iso: String) -> String {
        Zeitrechnung.zeitpunkt(aus: iso).map { Tag($0).deutsch } ?? "—"
    }

    // ── Eine Person ───────────────────────────────────────────────────────

    /// Zwei Zeilen (E340): oben die Felder und „angelegt …“, unten die Knöpfe — im Teil „Lerngruppen“
    /// reichte eine Zeile nicht, und die Knöpfe wurden stumm gekürzt (Punkt 9). „angelegt …“ steht seit dem
    /// Menü „Lerngruppen“ oben (E500), unten bräche es um. Die Knöpfe in Eigenbreite (E341): Reicht der Platz
    /// ein andermal nicht, laufen sie sichtbar über.
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
                Text("angelegt " + datum(p.angelegt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("Der Zeitpunkt der Anlage in dieser App")
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let entwurf {
                    lerngruppenmenue(p, gruppe: g, bestand: entwurf)
                }
                if let g {
                    Button("Aus der Lerngruppe nehmen") {
                        handgriff(Schrittname.ausLerngruppeNehmen) { $0.ohneMitglied(p.id, ausGruppe: g, jetzt: jetzt) }
                    }
                    .fixedSize()
                    .help("Die Person verbleibt in der Lernendenverwaltung. Beim Übernehmen wird sie auch aus dem Sitzplan "
                          + "dieser Lerngruppe entfernt.")
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

    /// Das Menü „Lerngruppen“ (E365, E369, E497): Häkchen je aktiver Lerngruppe; im Teil „Lerngruppen“ dazu
    /// „Umziehen nach“ — nur in Gruppen, in denen die Person noch nicht ist. Je Handgriff ein Schritt im Verlauf.
    private func lerngruppenmenue(_ p: Lernender, gruppe g: String?, bestand: Lernendenbestand) -> some View {
        let menue = Mitgliedschaftsmenue(person: p.id, aus: g, bestand: bestand)
        return Menu("Lerngruppen") {
            ForEach(menue.haekchen) { e in
                Toggle(e.titel, isOn: Binding(get: { e.mitglied }, set: { mitgliedschaft(p.id, e.id, $0) }))
                    .disabled(!e.waehlbar)
            }
            if let g {
                Divider()
                Menu("Umziehen nach") {
                    ForEach(menue.umziehen) { e in
                        Button(e.titel) { umziehen(p.id, von: g, nach: e.id) }
                            .disabled(!e.waehlbar)
                    }
                }
                .disabled(menue.umziehen.isEmpty)
            }
        }
        .fixedSize()
        .disabled(menue.haekchen.isEmpty && g == nil)
        .help("Mitgliedschaft in Lerngruppen — Häkchen setzen oder nehmen; eine Person kann mehreren Lerngruppen angehören."
              + (g == nil ? "" : " „Umziehen nach“ nimmt sie aus dieser Lerngruppe und trägt sie in die andere ein."))
    }

    private func mitgliedschaft(_ person: String, _ gruppe: String, _ an: Bool) {
        if an {
            handgriff(Schrittname.inLerngruppeAufnehmen) { $0.mitMitglied(person, inGruppe: gruppe, jetzt: jetzt) ?? $0 }
        } else {
            handgriff(Schrittname.ausLerngruppeNehmen) { $0.ohneMitglied(person, ausGruppe: gruppe, jetzt: jetzt) }
        }
    }

    /// Ein Schritt (E365): aufnehmen und aus der Quelle nehmen; Mitteilungen und Rückläufe der Quelle bleiben (E366).
    private func umziehen(_ person: String, von: String, nach: String) {
        handgriff(Schrittname.inAndereLerngruppeUmziehen) { $0.mitUmzug(person, von: von, nach: nach, jetzt: jetzt) ?? $0 }
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
    /// anlegen oder ändern — ein Schritt im Verlauf. `false`: Nichts geschah.
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

    // ── Die Rückmeldungsliste (E401, E405–E408, E633) ─────────────────────

    /// Der Bogen für die Gruppe — erst das Ausstehende aus den Feldern: Der Name steht im Kopf der Liste. Wie der Knopf
    /// nur mit einer Mitteilung der Gruppe.
    private func rueckmeldungslisteOeffnen(_ id: String, vorgabe: Rueckmeldungsbogenvorgabe = Rueckmeldungsbogenvorgabe()) {
        guard !speicher.frageSperrtBefehl() else { return }
        ausstehendeUebernehmen()
        guard let g = verzeichnis.gruppe(id), !verzeichnis.mitteilungen(der: id).isEmpty else { return }
        nachDemBogen = nil
        rueckmeldungsbogen = Rueckmeldungslistenvorlage(gruppe: g, vorgabe: vorgabe)
    }

    /// „Als PDF sichern (verschlüsselt) …“: Das PDF entsteht hier, im Speicher und verschlüsselt (E405) — aus dem
    /// Entwurf, wie das Blatt ihn zeigt. Erst dann geht der Bogen, und der Sichern-Dialog folgt am Blatt; weist der
    /// Listensatz ab, bleibt der Bogen, und die Meldung sagt, warum.
    private func rueckmeldungslisteSichern(_ g: Lerngruppe, _ auswahl: Set<String>, _ kennwort: String) -> Bool {
        guard !speicher.frageSperrtBefehl(), let entwurf else { return false }
        switch Rueckmeldungslistenbogen.pdf(entwurf, gruppe: g.id, auswahl: auswahl, kennwort: kennwort, stand: .heute) {
        case .abgewiesen(let grund):
            speicher.melden(grund, .warnung)
            return false
        case .verschluesselt(let daten):
            let name = Rueckmeldungslistenbogen.dateiname(g)
            nachDemBogen = { [speicher] in
                Listendruck.sichern(daten, dateiname: name, gruppe: g.beschriftung, speicher: speicher)
            }
            return true
        }
    }

    /// „Drucken …“: über das Schriftstück im Speicher; der Druckdialog folgt am Blatt. Einen PDF-Weg des Dialogs
    /// weist das Blatt des Drucks ab und meldet es (E407).
    private func rueckmeldungslisteDrucken(_ g: Lerngruppe, _ auswahl: Set<String>) -> Bool {
        guard !speicher.frageSperrtBefehl(), let entwurf else { return false }
        guard let liste = Rueckmeldungsliste.liste(entwurf, gruppe: g.id, mitteilungen: auswahl, stand: .heute) else {
            speicher.melden(Rueckmeldungslistenbogen.ohneAuswahl, .warnung)
            return false
        }
        let titel = Rueckmeldungslistenbogen.auftragstitel(g)
        guard let vorgang = Listendruck.vorgang(liste, titel: titel, abgewiesen: { [speicher] in
            speicher.melden(Rueckmeldungslistenbogen.pdfWegAbgewiesen, .warnung)
        }) else {
            speicher.melden(Rueckmeldungslistenbogen.nichtGesetzt, .warnung)
            return false
        }
        nachDemBogen = { Dialogort.drucken(vorgang) }
        return true
    }

    /// Nach dem Schließen des Bogens, was er hinterließ — höchstens einmal.
    private func nachDemBogenAusfuehren() {
        let weiter = nachDemBogen
        nachDemBogen = nil
        weiter?()
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
        zeilenBauen()
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
        if fokus != .gruppenname {
            let g = gruppe.flatMap { verzeichnis.gruppe($0) }
            gruppenname = g?.name ?? ""
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
        guard let ergebnis = entwurf.mitNeuerGruppe(name: neueGruppe, art: .klasse, jetzt: jetzt) else {
            if entwurf.lerngruppen.count >= Kennwerte.maxLerngruppen {
                speicher.melden("Höchstens \(Kennwerte.maxLerngruppen) Lerngruppen je Schuljahr.", .warnung)
            }
            return
        }
        entwurfAendern(Schrittname.lerngruppeAnlegen, ergebnis.bestand)
        neueGruppe = ""
        gruppe = ergebnis.id
        // Verdeckt das Suchfeld die neue, wird es geleert — sonst schiene „Anlegen“ nichts zu tun (Z-AT15M-01).
        suchfeldFuerWahl()
        namenEingeben = true
    }

    /// Der Name der Gruppe `id`, wie er im Feld steht — nichts, wenn er gleich ist.
    private func gruppenfelderUebernehmen() {
        guard let id = gruppenfelderFuer, let vorher = entwurf, let g = verzeichnis.gruppe(id) else { return }
        let name = Lernendenbestand.zeile(gruppenname, Planungsdatei.maxNamenslaenge)
        if name.isEmpty {
            gruppenname = g.name
        } else if name != g.name {
            entwurfAendern(Schrittname.lerngruppeUmbenennen, kennung: id,
                           vorher.mitGruppe(id, name: name, jetzt: jetzt))
        }
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

    /// Ein Schritt im Verlauf des Blatts; geschrieben wird mit „Übernehmen“. `binden`: neue Lerngruppen an die
    /// gleichnamigen Zeilen der Planung — im selben Schritt (E352).
    private func importieren(_ lesung: IServImport.Lesung, _ ziel: Importziel, binden: Bool) -> Importbilanz {
        ausstehendeUebernehmen()
        guard let vorher = entwurf else { return Importbilanz() }
        let planung = speicher.planung
        var zeilen = binden ? planung?.klassen : nil
        // Wie jeder Bindeweg erst die Herkunft der Planung auf die Platte (A4, E525) — gelingt das nicht, ohne Bindung.
        var grund: String?
        if zeilen != nil, let fehlt = speicher.herkunftSichern() {
            grund = fehlt
            zeilen = nil
        }
        let (neu, bilanz, bindung) = vorher.mitImport(lesung, ziel: ziel, binden: zeilen,
                                                      planung: planung?.erstellt ?? "", jetzt: jetzt)
        entwurfAendern(Schrittname.ausIServImportieren, neu)
        speicher.melden(bilanz.meldung(bindung))
        if let grund { speicher.melden(grund, .warnung) }
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
        rueckweg = vorgabe.zurueck
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
        // Nur, wenn ein Kopf kommt — sonst öffnete ihn eine später gewählte Gruppe ungefragt (Z-AT9a2-18).
        zeilenwahlBeimKopf = vorgabe.zeilenwahl && ansicht == .gruppen && gruppe != nil
        startAnliegen = vorgabe.anliegen
        nurOffen = vorgabe.nurOffen
        suche = vorgabe.suche ?? ""
        gruppensuche = vorgabe.gruppensuche ?? ""
        // Ebenso nur, wenn der Teil „Mitteilungen“ dieser Gruppe rechts kommt — verdeckte ihn die Suche, öffnete ihn
        // später ein Wechsel ungefragt (Z-AW5a-06).
        if let g = gruppe, ansicht == .gruppen, teil == .mitteilungen, sichtbareGruppe == g,
           let liste = vorgabe.rueckmeldungsliste {
            rueckmeldungslisteBeimTeil = (g, liste)
        } else {
            rueckmeldungslisteBeimTeil = nil
        }
        ordnung = vorgabe.sortierung?.ordnung ?? Personenzeile.vorgabe
        zeilenBauen()
        if let id = vorgabe.person, verzeichnis.person(id) != nil { person = id }
        // Der Umzug wie im Menü, wenn das Blatt steht — aus der gewählten Gruppe (Prüfstand, E365).
        if let ziel = vorgabe.umzug, let von = gruppe, let wer = person {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { umziehen(wer, von: von, nach: ziel) }  // E561: Zeitgeber (Oberfläche) — Prüfstand: erst, wenn das Blatt steht
        }
        // Der Bogen erst, wenn das Blatt steht — ein Fenster trägt einen Bogen.
        if let datei = vorgabe.importdatei {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { importdateiLesen(datei) }  // E561: Zeitgeber (Oberfläche) — Prüfstand: erst, wenn das Blatt steht
        }
        if let art = vorgabe.anliegenbogen, let p = person.flatMap({ verzeichnis.person($0) }) {
            let bestehend = vorgabe.anliegen.flatMap { id in start?.anliegen.first { $0.id == id } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {  // E561: Zeitgeber (Oberfläche) — Prüfstand: erst, wenn das Blatt steht
                anliegenvorlage = mitPlanung(Anliegenvorlage(art: art, person: p, anliegen: bestehend,
                                                             tag: vorgabe.anliegentag))
            }
        }
        if let ziel = vorgabe.gruppenwechsel {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { gruppeWaehlen(ziel) }  // E561: Zeitgeber (Oberfläche) — Prüfstand: erst, wenn das Blatt steht
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
            speicher.lernendenVerwerfenFragen { zumachen() }
        } else {
            zumachen()
        }
    }

    /// Das Blatt geht über seine Knöpfe oder ⎋ — aus ⌘K mit dem Rückweg dorthin (E358). Nur, solange es das offene
    /// ist: Ein zweiter Aufruf aus der Lücke nach einer Antwort schlösse sonst ein Blatt, das schon fort ist (Z-AT4-01).
    private func zumachen() {
        guard speicher.offenerDialog == .lernende else { return }
        speicher.lernendenblattSchliessen(zurueck: rueckweg)
        schliessen()
    }

    /// „Übernehmen“ schließt „Eintragen“ ein (E457): Eine lesbare getippte Liste wird eingetragen wie mit
    /// „Eintragen“, dann übernommen; mit einer fehlerhaften Zeile bleibt das Blatt offen (E458).
    private func uebernehmen() {
        guard !speicher.frageSperrtBefehl() else { return }
        ausstehendeUebernehmen()
        guard let entwurf else {
            zumachen()
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
        zumachen()
    }
}

/// Was der Bogen „Zeilen wählen“ braucht (E669).
struct Zeilenwahlvorlage: Identifiable {
    /// Die Lerngruppe.
    let id: String
    let name: String
    let zeilen: [Zeilenwahl.Zeile]
    /// Bindungen an Zeilen, die diese Planung nicht führt — sie zählen zur Grenze von 20.
    let aussen: Int
}

/// Der Bogen „Zeilen wählen“ am Blatt „Lernende“ (E669): ein Kästchen je Zeile der Planung, die eine Lerngruppe tragen kann;
/// andere Lerngruppen an der Zeile als Hinweis (E670). Geschrieben wird erst mit „Übernehmen“ des Blatts.
struct ZeilenwahlBogen: View {
    let vorlage: Zeilenwahlvorlage
    /// `false`: Nichts geschah — der Bogen bleibt.
    let fertig: @MainActor (Set<String>) -> Bool

    @Environment(\.dismiss) private var schliessen
    @State private var gewaehlt: Set<String> = []

    private var voll: Bool { gewaehlt.count + vorlage.aussen >= Lernendendatei.maxZeilenJeGruppe }

    var body: some View {
        Dialograhmen(titel: "Zeilen wählen", unterzeile: "Lerngruppe „\(vorlage.name)“", breite: 520, hoehe: 520,
                     meldungsblatt: .lernende) {
            Section {
                ForEach(vorlage.zeilen) { z in
                    Toggle(isOn: Binding(get: { gewaehlt.contains(z.id) },
                                         set: { an in if an { gewaehlt.insert(z.id) } else { gewaehlt.remove(z.id) } })) {
                        HStack(spacing: 8) {
                            Text(z.titel)
                            Spacer(minLength: 8)
                            if let auch = z.auch {
                                Text(auch).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(voll && !gewaehlt.contains(z.id))
                }
            } footer: {
                Text(vorlage.zeilen.isEmpty ? "Die Planung hat keine Zeile, die eine Lerngruppe tragen kann."
                     : voll ? "Höchstens \(Lernendendatei.maxZeilenJeGruppe) Zeilen je Lerngruppe."
                     : "Eine Zeile kann mehrere Lerngruppen tragen; den anderen wird nichts genommen.")
                    .foregroundStyle(.secondary)
            }
        } fuss: {
            Spacer(minLength: 0)
            Button("Abbrechen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            Button("Übernehmen") { if fertig(gewaehlt) { schliessen() } }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { gewaehlt = Set(vorlage.zeilen.filter(\.gewaehlt).map(\.id)) }
    }
}

/// Der Kopf einer Tabellenspalte der Lernendenverwaltung (E498): Ordnet sie vorn, steht ihr Titel fett in der
/// Akzentfarbe — der Pfeil allein fiel zu wenig auf.
enum Ordnungskopf {
    static func text(_ titel: String, vorn: Bool) -> Text {
        vorn ? Text(titel).bold().foregroundColor(.accentColor) : Text(titel)
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
    /// Eine lesbare Liste, verdeckt von einer anderen Darstellung: Die Liste kommt nach vorn, das Blatt bleibt offen, der
    /// Hinweis sagt es — eingetragen wird erst mit dem nächsten „Übernehmen“ (Z-AV2a-01).
    case zeigen(hinweis: String)
    /// Eine Liste ohne ihre Lerngruppe im Entwurf — es fragt wie die übrigen Wege (E303).
    case fragen
}
