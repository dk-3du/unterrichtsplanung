// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Der Sitzplan-Editor — ein Blatt im Hauptfenster, 820 × 700 (E1192; bis 2.8.0 1000 × 720, E30), auf kleinem
/// Bildschirm niedriger wie das Vorhaben-Blatt, höchstens 40 pt über dem Rand (E1150, E1188); dann rollt der Körper. Die
/// Bedienung der Fläche steht hinter einem ⓘ (E1191). Ohne Plan: die Namensliste, eine Zeile je Name, und „Tische
/// anordnen“. Mit Plan: die Fläche mit Tafel, Lehrertisch und Tischen. Das Blatt arbeitet auf einem Entwurf; „Übernehmen“
/// schreibt ihn, „Abbrechen“ verwirft alles seit dem Öffnen — mehr Undo gibt es nicht.
struct SitzplanDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    /// Nur für die Abbilder: der Stand ohne Datenschutzhinweis wie bei einer verschlüsselten Planung — die lässt sich
    /// abseits des Bildschirms nicht herstellen (R-BH4-01). Sonst entscheidet der Stand der Verschlüsselung.
    let ohneDatenschutzhinweis: Bool

    init(ohneDatenschutzhinweis: Bool = false) {
        self.ohneDatenschutzhinweis = ohneDatenschutzhinweis
    }

    /// 820 × 700 (E1192); auf kleinem Bildschirm niedriger wie das Vorhaben-Blatt (E1150, E1188).
    static let blattbreite: CGFloat = 820
    static let blatthoehe: CGFloat = 700
    /// Unter dem Körper 4 pt, darauf folgt der Fuß mit 16 pt Abstand oben (`Dialograhmen`, `Blattfuss`). Über der Fläche
    /// steht dieselbe Summe, damit sie oben und unten gleich viel Luft hat (E1195; am Abbild 19e nachgemessen — die
    /// Ränder der Knöpfe darüber und darunter liegen gleich weit von der Fläche).
    static let koerperUnten: CGFloat = 4
    static let fussOben: CGFloat = 16
    /// Die Höhe dieses Blatts, beim ersten Zeichnen festgelegt (E1150) — wie am Vorhaben-Blatt.
    @State private var blattmass = Blatthoehe(SitzplanDialog.blatthoehe)

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
    /// Wer hinter den Zeilen steht (E255): aus der Lerngruppe übernommen oder
    /// von den gebundenen Tischen bei „Namen neu eingeben …“. Beim Anordnen
    /// bindet eine Zeile nur, wenn sie unverändert ist.
    @State private var vorlage: [Sitzplan.Platzvorlage] = []
    /// Die Plätze aus der Gruppe, solange die Rückfrage vor dem Anordnen steht.
    @State private var ausGruppe: [Sitzplan.Platzvorlage]?
    /// Die Antwort auf ein eigenes Alert läuft erst nach dessen Schließen; bis dahin bleiben ⎋/„Abbrechen“,
    /// „Übernehmen“ (auch mit „Verschlüsselung einrichten …“), „Sitzplan entfernen“, „Namen neu eingeben …“
    /// und ⇧⌘L ohne Wirkung (Z-AU4b-01/-02/-07).
    @State private var antwortAussteht = false
    /// Das Popover mit der Bedienung der Fläche (E1191).
    @State private var bedienungOffen = false
    /// Die sichtbare Höhe der Rollfläche — der Körper ist mindestens so hoch (E1194, E1195).
    @State private var sichtbar: CGFloat = 0

    private var klasse: Klasse? { speicher.sitzplanKlasseStand }
    private var pruefung: Sitzplan.Namensliste { Sitzplan.namenLesen(namenstext) }

    private var veraendert: Bool {
        if let plan { return plan != ausgang }
        return ausgang != nil || !namenstext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Die Unterzeile: „32 Plätze · Lehrertisch“ — ohne Grenze der Tische (E979; bis 2.4.0 „32 von 40 Plätzen“).
    nonisolated static func plaetzezeile(_ plan: Sitzplan) -> String {
        let n = plan.tische.count
        return "\(n) \(n == 1 ? "Platz" : "Plätze")" + (plan.lehrertisch == nil ? "" : " · Lehrertisch")
    }

    /// Ab dem 51. Tisch steht neben der Zahl der Plätze die Empfehlung (E1052) — auch beim Öffnen eines solchen Plans;
    /// abgelehnt wird nichts (E1051), Verschieben bleibt, wie es ist (E1050, R91-01). Die Regel steht hier, nicht im
    /// Modell: wie `plaetzezeile` rein und ohne Fenster prüfbar, der Wortlaut gehört zur Oberfläche.
    nonisolated static let empfohleneTische = 50
    nonisolated static let tischempfehlung = "Es wird empfohlen, nicht mehr als 50 Tische zu platzieren."

    /// Die Ansage für VoiceOver (E1059): beim Wechsel von höchstens 50 auf mehr als 50 Tische und beim Öffnen eines Plans
    /// mit mehr als 50 (vorher kein Plan) — sonst `nil`. Der Kopf wird vorgelesen, wenn man dorthin geht; ein Wechsel
    /// während der Arbeit nicht.
    nonisolated static func tischansage(vorher: Sitzplan?, nachher: Sitzplan?) -> String? {
        guard tischhinweis(nachher) != nil, tischhinweis(vorher) == nil else { return nil }
        return tischempfehlung
    }

    /// Der Hinweis im Kopf des Blatts — `nil` ohne Plan oder mit höchstens 50 Tischen; der Lehrertisch zählt nicht.
    nonisolated static func tischhinweis(_ plan: Sitzplan?) -> String? {
        guard let plan, plan.tische.count > empfohleneTische else { return nil }
        return tischempfehlung
    }

    private var unterzeile: String {
        guard let plan else { return "Namen eingeben — eine Zeile je Schülerin oder Schüler" }
        return Self.plaetzezeile(plan)
    }

    var body: some View {
        Dialograhmen(titel: "Sitzplan — " + (klasse?.beschriftung ?? ""),
                     unterzeile: unterzeile, hinweis: Self.tischhinweis(plan), breite: Self.blattbreite,
                     hoehe: blattmass.wert, mindesthoehe: blattmass.wert,
                     beimSchliessen: abbrechen, freierKoerper: true) {
            // Fest in beiden Richtungen; was nicht in die Höhe passt (kleiner Bildschirm), rollt — Kopf und Fuß bleiben
            // stehen (E1158, E1188). In voller Höhe passt der Körper ohne Rollen (E1191).
            ScrollView(.vertical) {
                // Mindestens so hoch wie sichtbar: Das Namensfeld nimmt den Rest (E1194), die Fläche steht mit gleich viel
                // Luft darüber und darunter (E1195). Ist weniger Platz, rollt der Körper wie bisher.
                Mindesthoehe(hoehe: sichtbar) {
                    // 12 pt unter dem Datenschutzhinweis wie bis 2.8.0 (E1197; 8 pt im Vergleich verworfen).
                    VStack(alignment: .leading, spacing: 12) {
                        if speicher.verschluesselungsstand == .aus && !ohneDatenschutzhinweis {
                            datenschutzhinweis
                        }
                        if let plan, !namenEingeben {
                            flaechenabschnitt(plan)
                        } else {
                            namensabschnitt
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, Self.koerperUnten)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sichtbar = $0 }
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
        .onAppear {
            laden()
            // Solange das Blatt steht, gehört ⌘Z ihm (E82, E87): Der Verlauf
            // liegt im Speicher, damit das Menü ihn erreicht, der Entwurf hier.
            speicher.sitzplanblattUebernimmt { zurueck in
                plan = zurueck
                auswahl = auswahl.filter { kennung in
                    zurueck.tische.contains { $0.id == kennung }
                        || kennung == Sitzplan.lehrertischKennung && zurueck.lehrertisch != nil
                }
            }
        }
        // Abgemeldet wird beim Schließen im `didSet` von `offenerDialog`; dies ist nur das Netz. Es kann verspätet kommen —
        // nach dem Rückweg über ⌘K auch erst, wenn der nächste Editor schon steht und sich angemeldet hat. Dann meldete es
        // diesen ab, und ⌘Z ginge an die Planung (AT4a, E513, wie D-AT4-01).
        .onDisappear { if speicher.offenerDialog != .sitzplan { speicher.sitzplanblattGibtAb() } }
        .onChange(of: plan) { alt, neu in
            speicher.sitzplanEntwurf = neu
            // Nur für VoiceOver, ohne Kapsel (E1059) — über den Ansager, der wartet, bis der Fokus ruht: Beim Öffnen wechselt
            // er gerade, und eine Ansage im selben Augenblick entfiele (B108, E461). Geht die App vorher in den Hintergrund,
            // verfällt sie beim Zurückkehren wie jede Ansage ohne stehende Meldung — hingenommen, der Hinweis steht im Kopf
            // (H1-04).
            if let ansage = Self.tischansage(vorher: alt, nachher: neu) {
                Ansager.gemeinsam.ansagen([Ansageeintrag(id: UUID(), warnung: false, text: ansage)])
            }
        }
        // Die eigenen Alerts: Deren Handlungen schließen das Blatt oder bauen es um — erst nach dem
        // Schließen des Alerts (B95, E433).
        .alert("Die Änderungen am Sitzplan verwerfen?", isPresented: $verwerfenFragen) {
            Button("Weiter bearbeiten", role: .cancel) {}
            Button("Verwerfen", role: .destructive) { nachDemAlert { zumachen() } }
        }
        .alert("Die Namen neu eingeben?", isPresented: $neuEingebenFragen) {
            Button("Abbrechen", role: .cancel) {}
            Button("Neu eingeben") {
                nachDemAlert {
                    namenstext = plan?.namenstext ?? ""
                    vorlage = plan?.platzvorlage ?? []
                    namenEingeben = true
                }
            }
        } message: {
            Text("Die Anordnung wird aus der Liste neu erzeugt — verschobene Tische stehen "
                 + "danach wieder in Reihen.")
        }
        .alert("Die Tische aus der Lerngruppe anordnen?", isPresented: Binding(
            get: { ausGruppe != nil }, set: { if !$0 { ausGruppe = nil } })) {
            Button("Abbrechen", role: .cancel) { ausGruppe = nil }
            Button("Anordnen") {
                if let plaetze = ausGruppe { nachDemAlert { ausDerGruppeAnordnen(plaetze) } }
                ausGruppe = nil
            }
        } message: {
            Text("Die eingegebenen Namen gehen dabei verloren.")
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
            // Immer kurz beschriftet: Breiter bräche der Hinweis dreizeilig um, und der Körper rollte nach einer Änderung
            // (E1198, R-BH4-02). Dass er Änderungen zuerst übernimmt, sagt der Tooltip.
            Button("Verschlüsselung einrichten …") {
                guard !speicher.frageSperrtBefehl(), !antwortAussteht else { return }
                if let plan, veraendert { planUebernehmen(plan) }
                speicher.sitzplanDialogSchliessen()
                speicher.verschluesselungEinrichten()
                schliessen()
            }
            // Eine getippte, noch nicht angeordnete Liste ginge sonst verloren.
            .disabled(plan == nil && veraendert)
            .help(plan == nil && veraendert ? "Erst „Tische anordnen“ — die Liste ginge sonst verloren."
                  : veraendert ? "Übernimmt die Änderungen, schließt den Editor und öffnet die Einrichtung der Verschlüsselung."
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
        let angebot = klasse.flatMap { speicher.sitzplatzangebot(fuer: $0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Eine Zeile je Schülerin oder Schüler. "
                 + "Die Tische entstehen daraus in Reihen zu acht, von der Tafel aus gezählt; das "
                 + "Raster fasst zehn Plätze je Reihe, zwei bleiben für Gänge frei — danach lassen "
                 + "sich die Tische frei verschieben. Mehr als 40 Tische belegen zuerst die Gänge, dann den oberen "
                 + "Rand; was das Raster dann nicht mehr fasst, liegt übereinander oben links und lässt sich von dort "
                 + "verschieben."
                 + (angebot == nil ? "" : " Aus der Lerngruppe übernommen, trägt jeder Tisch den Namen der ihm "
                    + "zugeordneten Person; der Name am Tisch lässt sich danach ändern, ohne die Zuordnung zu lösen."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Eine Liste von Namen wie im Blatt „Lernende“: keine Korrektur, kein Großschreiben (B84, B73).
            Textfeld(text: $namenstext, mindesthoehe: 300,
                     beschriftung: "Namensliste, eine Zeile je Name", namen: true)
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
                if let angebot {
                    gruppenknopf(angebot.gruppe, angebot.plaetze)
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

    /// „Namen aus der Lerngruppe übernehmen“ (E255, E284) — ordnet die Tische
    /// gleich an; gekürzt wird danach am Tisch, die Person bleibt. ⇧⌘L, denn
    /// die Schreibmarke steht in der Liste.
    private func gruppenknopf(_ gruppe: Lerngruppe?, _ plaetze: [Sitzplan.Platzvorlage]) -> some View {
        Button("Namen aus der Lerngruppe übernehmen") {
            guard !speicher.frageSperrtBefehl(), !antwortAussteht else { return }
            // Nur eine selbst getippte Liste ginge verloren — die aus dem Plan nicht.
            let ausgang = namenEingeben ? (plan?.namenstext ?? "") : ""
            let getippt = !namenstext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && namenstext != ausgang
            if getippt { ausGruppe = plaetze } else { ausDerGruppeAnordnen(plaetze) }
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .disabled(plaetze.isEmpty)
        .help(Self.gruppenhilfe(gruppe, plaetze: plaetze.count,
                                gebunden: klasse.map { speicher.lerngruppen(fuerZeile: $0.id) } ?? []))
    }

    /// Die Hilfe am Knopf „Namen aus der Lerngruppe übernehmen“ — trägt die Zeile mehrere Lerngruppen, der Weg zu
    /// einer eigenen (E673, E674).
    nonisolated static func gruppenhilfe(_ gruppe: Lerngruppe?, plaetze: Int, gebunden: [Lerngruppe]) -> String {
        if let g = gruppe {
            return plaetze == 0 ? "„\(g.beschriftung)“ hat keine aktiven Mitglieder"
                : "Die \(plaetze) Mitglieder von „\(g.beschriftung)“ als Tische anordnen (⇧⌘L)"
        }
        guard gebunden.count < 2 else {
            return "Mit dieser Zeile sind mehrere Lerngruppen verknüpft (" + gebunden.map { "„\($0.name)“" }.joined(separator: ", ")
                + ") — für den Sitzplan in der Kurszelle eine Lerngruppe für diese Zeile festlegen"
        }
        return "An diese Zeile ist keine Lerngruppe gebunden — binden unter „Klassen/Kurse und Fächer“ (⌘K)"
    }

    private func ausDerGruppeAnordnen(_ plaetze: [Sitzplan.Platzvorlage]) {
        guard let klasse else { return }
        entwurfAendern(Sitzplan.anordnen(klasseId: klasse.id, lernende: plaetze),
                       Sitzplanhandgriff(name: Schrittname.tischeAnordnen))
        namenstext = ""
        vorlage = []
        auswahl = []
        namenEingeben = false
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
        entwurfAendern(Sitzplan.anordnen(klasseId: klasse.id,
                                         lernende: Sitzplan.zuordnen(namen: ergebnis.namen, vorlage: vorlage)),
                       Sitzplanhandgriff(name: Schrittname.tischeAnordnen))
        auswahl = []
        namenEingeben = false
    }

    // ── Die Fläche ────────────────────────────────────────────────────────

    private func flaechenabschnitt(_ stand: Sitzplan) -> some View {
        let ton = Farbwelt.ton(klasse?.farbe ?? Farbwelt.ohneFarbe)
        let planBindung = Binding<Sitzplan>(
            get: { plan ?? stand },
            set: { plan = $0 })
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Kurz beschriftet, damit die Reihe bei 820 pt auch mit dem Lehrertisch-Knopf passt (E1193); für VoiceOver
                // der volle Name.
                Button {
                    tischHinzufuegen()
                } label: {
                    Label("Tisch", systemImage: Zeichen.plus)
                }
                .help("Einen Tisch an eine freie Stelle setzen und benennen — ist keine frei, oben links")
                .accessibilityLabel("Tisch hinzufügen")

                if stand.lehrertisch == nil {
                    Button {
                        entwurfAendern(stand.mitLehrertisch(),
                                       Sitzplanhandgriff(name: Schrittname.lehrertischHinzufuegen))
                    } label: {
                        Label("Lehrertisch", systemImage: Zeichen.plus)
                    }
                    .help("Lehrertisch hinzufügen")
                    .accessibilityLabel("Lehrertisch hinzufügen")
                }

                Button("Namen neu eingeben …") { if !speicher.frageSperrtBefehl(), !antwortAussteht { neuEingebenFragen = true } }
                    .help("Die Liste erneut eingeben — die Anordnung wird neu erzeugt")

                // Die Bedienung der Fläche hinter dem ⓘ statt als Text darunter (E1191) — gebaut wie der Kalender am
                // Datumsfeld: ein schlichter Knopf, im Popover nur Text.
                Button { bedienungOffen = true } label: {
                    Image(systemName: Zeichen.hinweis)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Bedienung der Fläche")
                .accessibilityLabel("Bedienung der Fläche")
                .popover(isPresented: $bedienungOffen, arrowEdge: .bottom) {
                    Sitzplanbedienung()
                }

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

            // Über und unter der Fläche gleich viel Luft bis zur Knopfreihe bzw. zu den Knöpfen im Fuß (E1195): oben der
            // feste Abstand, den unten Körper und Fuß beitragen, dazu je die Hälfte des freien Platzes.
            Spacer(minLength: 0)
            Sitzplanflaeche(plan: planBindung, auswahl: $auswahl, umbenennen: $umbenennen, ton: ton,
                            personenname: { Self.personenname($0, in: speicher.lernende.verzeichnis) },
                            beiUebernehmen: { uebernehmen() },
                            beiAenderung: { neu, handgriff in entwurfAendern(neu, handgriff) })
                .frame(width: Sitzplanmasse.breite, height: Sitzplanmasse.hoehe)
                .frame(maxWidth: .infinity)
                .padding(.top, Self.koerperUnten + Self.fussOben)
            Spacer(minLength: 0)
        }
    }

    private func tischHinzufuegen() {
        guard let stand = plan else { return }
        let neu = stand.mitNeuemTisch(name: "Name")
        entwurfAendern(neu, Sitzplanhandgriff(name: Schrittname.tischHinzufuegen))
        if let letzter = neu.tische.last {
            auswahl = [letzter.id]
            umbenennen = letzter.id
        }
    }

    private func alsPDFSichern(_ stand: Sitzplan) {
        guard let klasse else { return }
        Sitzplandruck.alsPDFSichern(stand, klasse: klasse, speicher: speicher)
    }

    private func drucken(_ stand: Sitzplan) {
        guard let klasse else { return }
        Sitzplandruck.drucken(stand, klasse: klasse, speicher: speicher)
    }

    /// **Der Weg, auf dem der Entwurf sich ändert** — er meldet den Schritt an
    /// und setzt ihn dann (S6). Der erste Plan ist kein Schritt: Vor ihm gibt es
    /// nichts, wohin ein Widerrufen führte.
    private func entwurfAendern(_ neu: Sitzplan, _ handgriff: Sitzplanhandgriff) {
        guard let vorher = plan else { plan = neu; return }
        guard neu != vorher else { return }
        plan = neu
        speicher.sitzplanverlauf.anmelden(handgriff.name, kennung: handgriff.kennung,
                                          vorher: vorher, nachher: neu)
    }

    // ── Öffnen, Übernehmen, Abbrechen, Entfernen ──────────────────────────

    private func laden() {
        let gespeichert = speicher.sitzplanKlasse.flatMap { speicher.sitzplan(fuer: $0) }
        plan = gespeichert
        ausgang = gespeichert
        speicher.sitzplanEntwurf = gespeichert
        speicher.sitzplanverlauf.leeren()
        namenstext = ""
        vorlage = []
        namenEingeben = false
        auswahl = []
    }

    private func zumachen() {
        speicher.sitzplanDialogSchliessen()
        schliessen()
    }

    /// Die Handlung eines eigenen Alerts — nach dessen Schließen (B95, E433); bis dahin sperrt `antwortAussteht`.
    private func nachDemAlert(_ handlung: @escaping @MainActor () -> Void) {
        antwortAussteht = true
        speicher.nachDemSchliessenAusfuehren {
            antwortAussteht = false
            handlung()
        }()
    }

    private func abbrechen() {
        // Steht das Popover der Bedienung, schließen ⎋ und „Abbrechen“ nur dieses, nicht den Editor (R-BH4-03).
        if bedienungOffen { bedienungOffen = false; return }
        guard !speicher.frageSperrtBefehl(), !antwortAussteht else { return }
        if veraendert { verwerfenFragen = true } else { zumachen() }
    }

    private func uebernehmen() {
        guard !speicher.frageSperrtBefehl(), !antwortAussteht, let plan else { return }
        planUebernehmen(plan)
        zumachen()
    }

    /// Übernimmt den Plan; ließ er sich nicht sichern, sagt es eine Warnung — auch vor „Verschlüsselung einrichten …“
    /// (R-BH8-W2-08).
    private func planUebernehmen(_ plan: Sitzplan) {
        if let grund = speicher.sitzplanUebernehmen(plan) {
            speicher.melden("Der Sitzplan gilt für diese Sitzung, ließ sich aber nicht sichern (\(grund)).",
                            .warnung)
        }
    }

    private func entfernen() {
        guard !speicher.frageSperrtBefehl(), !antwortAussteht, let klasse else { return }
        speicher.sitzplanEntfernen(klasse: klasse.id, ort: .sitzplan) {
            speicher.sitzplanDialogSchliessen()
            schliessen()
        }
    }

    /// Die Person am Tisch, für Hilfetext und Bedienungshilfe — mit Rufname (E390), in der Form der
    /// Rückmeldungsliste: „Abel, Anna (Anni)“. `nil` ohne offene Verwaltung.
    nonisolated static func personenname(_ id: String, in verzeichnis: Lernendenverzeichnis?) -> String? {
        verzeichnis?.person(id).map(Rueckmeldungsliste.name)
    }
}

/// Schlägt dem Inhalt einer Rollfläche die sichtbare Höhe vor, solange er hineinpasst — sonst seine eigene, dann rollt er
/// (E1194, E1195). `.frame(minHeight:)` reicht dort nicht: Die Rollfläche schlägt keine Höhe vor, der Rahmen wird zwar so
/// hoch, der Inhalt aber nicht, und der freie Platz bliebe ganz unten (R-BH4-01, Abbild 19e: 24 gegen 87 pt).
struct Mindesthoehe: Layout {
    let hoehe: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let inhalt = subviews.first else { return .zero }
        let eigen = inhalt.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let hoch = max(eigen.height, hoehe)
        let gestreckt = inhalt.sizeThatFits(ProposedViewSize(width: proposal.width, height: hoch))
        return CGSize(width: gestreckt.width, height: max(gestreckt.height, hoch))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// Die Bedienung der Sitzplanfläche — im Popover hinter dem ⓘ (E1191; bis 2.8.0 als Text unter der Fläche). Nur Text, nie
/// leer; eigene Ansicht, damit auch das Abbild sie zeigt.
struct Sitzplanbedienung: View {
    nonisolated static let text = "Ziehen verschiebt einen Tisch oder alle angewählten; die rechte Maustaste zieht "
        + "eine Bereichsauswahl auf und öffnet kurz gedrückt das Menü. Doppelklick oder ⌥⏎ "
        + "benennt um — ein Tisch mit Personen-Symbol behält dabei seine Person —, ⌫ entfernt die "
        + "Auswahl, ⏎ übernimmt. Pfeiltasten verschieben um "
        + "8 Punkt, mit ⇧ um 1. Die Tische rasten unsichtbar ein, zehn Plätze je Reihe für "
        + "bis zu zwei Gänge — ⌥ beim Ziehen hebt das auf, für schräge Sitzgruppen und "
        + "freie Anordnungen."

    var body: some View {
        Text(Self.text)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 340, alignment: .leading)
            .padding(14)
    }
}
