// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct NeuePlanungDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @State private var titel = ""
    @State private var wochen = Double(Kennwerte.wochenStandard)

    /// Die erste Woche der Planung — vorbelegt mit dem laufenden Schuljahr,
    /// einstellbar, damit vor dem 1. August das kommende anlegbar ist.
    @State private var start = Tag.laufendesSchuljahr
    /// Von hier leitet sich die 1. Schulwoche ab: die Kalenderwoche, in die
    /// dieser Tag fällt.
    @State private var ersterSchultag = Tag.laufendesSchuljahr
    @State private var kurstext = ""
    /// Die gewählten Sonderzeilen (E157) — unterhalb der freien Eingabe.
    @State private var sonderzeilen: Set<Zeilenart> = []
    @FocusState private var titelFokus: Bool

    // ── Übernahme aus der aktuellen Planung ──
    /// Erster Schritt: Soll überhaupt etwas übernommen werden?
    @State private var uebernahmeGewuenscht = false
    /// Zweiter Schritt, je Zeile: Eintrag vorhanden heißt „Klasse/Kurs und
    /// Fach übernehmen“, `true` heißt „samt aller zugehörigen Vorhaben“.
    @State private var mitnehmen: [String: Bool] = [:]
    /// Schalter, Namen und Zeilen der Lerngruppen (E271, E307–E311, E649) — wer
    /// mitkommt, folgt aus den Zeilen und dem Import (E657, `mitkommend`).
    @State private var wahl = Hochstufungswahl()

    // ── Lernende aus IServ (D) ──
    /// Ein Bogen am Blatt — eine Stelle für jeden Bogen dieses Blatts.
    enum Bogen: Identifiable {
        case iserv(Importquelle)
        /// „Lerngruppen zuordnen“ (E382–E388) auf einer Kopie der Wahl.
        case zuordnung(Zuordnungsvorlage)
        var id: UUID {
            switch self {
            case .iserv(let quelle): quelle.id
            case .zuordnung(let vorlage): vorlage.id
            }
        }
    }
    @State private var bogen: Bogen?
    /// Der übernommene Import und der Name seiner Datei — geschrieben wird erst mit „Planung anlegen“ (D1b).
    @State private var iserv: (lesung: IServImport.Lesung, datei: String)?

    private var anzahl: Int { min(Kennwerte.wochenMax, max(1, Int(wochen.rounded()))) }
    private var pruefung: Kurszeilen.Ergebnis { Kurszeilen.pruefen(kurstext) }

    /// Vor dem 1. August meint `laufendesSchuljahr` noch das alte — bleibt es
    /// bei der Vorbelegung, gleicht der Vorschlagstitel dem der laufenden
    /// Planung, und der Autoexport schriebe beide unter denselben Dateinamen.
    private var nameKollidiert: Bool {
        guard speicher.autoexportAktiv, !speicher.autoexportOrdner.isEmpty else { return false }
        return speicher.kopienameBliebe(neuerTitel: titel)
    }

    var body: some View {
        Dialograhmen(titel: "Neue Planungsdatei",
                     unterzeile: "Zeitraum sowie Klassen und Kurse festlegen",
                     hoehe: 700, beimSchliessen: abbrechen, zeileAbgegeben: bogen != nil) {
            Section {
                TextField("Bezeichnung der Planung", text: $titel)
                    .focused($titelFokus)
                if nameKollidiert {
                    Label("Dieser Titel ergibt denselben Dateinamen wie die bisherige "
                          + "Planung — die Sicherungskopie beim Beenden würde sie ersetzen.",
                          systemImage: Zeichen.warnung)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Erste Woche des Schuljahres") {
                    HStack(spacing: 8) {
                        // Wochenweise: Der Setter rastet auf den Montag ein,
                        // ein Schritt um einen Tag verpuffte dadurch nach oben
                        // und sprang nach unten gleich eine Woche zurück.
                        Datumsfeld(tag: Binding(get: { start },
                                                set: { start = $0.montagDerWoche }),
                                   schritt: 7)
                        Text("Montag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Erster Schultag") {
                    Datumsfeld(tag: $ersterSchultag)
                }
                if !ersterSchultag.liegtImZeitraum(start: start, wochen: anzahl) {
                    Label("Der erste Schultag liegt außerhalb des Zeitraums.",
                          systemImage: Zeichen.warnung)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Unterrichtswochen") {
                    HStack(spacing: 12) {
                        Slider(value: $wochen, in: 1...Double(Kennwerte.wochenMax), step: 1) {
                            Text("Unterrichtswochen")
                        }
                        .labelsHidden()
                        .frame(minWidth: 180)

                        Wochenzahlfeld(wochen: $wochen)
                    }
                }
            } header: {
                Text("Zeitraum")
            } footer: {
                Text(zeitraumfussnote)
            }

            kursabschnitt

            lernendenabschnitt

            if !alteKlassen.isEmpty {
                uebernahmeabschnitt
            }

            if LerngruppenWahl.knopfFrei(verschluesselt: speicher.tresor != nil, gruppen: lerngruppen) {
                lerngruppenabschnitt
            }

            // Der Rückfall zum Umzug in den Container: Zog die bisherige Ablage
            // beim ersten Start nicht von selbst um, steht hier, wo sie liegt.
            if Ordnerzugriff.imSandbox, alteKlassen.isEmpty {
                Section {
                    Text("Eine Planung aus einer früheren Fassung zieht beim ersten Start "
                         + "dieser Fassung von selbst um. Fehlt sie dennoch, liegt sie unter "
                         + "~/Library/Application Support/Unterrichtsplanung/planung.json und "
                         + "lässt sich über „Öffnen …“ (⌘O) hereinholen — im Dialog mit ⇧⌘G "
                         + "zum Ordner springen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Bisherige Planung")
                }
            }
        } fuss: {
            if speicher.planung != nil {
                Text((speicher.tresor != nil
                      ? "Die aktuelle Planung geht samt ihren Lernendendaten ins Archiv."
                      : "Die aktuelle Planung wird ersetzt — vorher ggf. exportieren.")
                     + (speicher.sitzplaene.hatPlaene
                        ? " Sitzpläne folgen nur übernommenen Klassen." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if speicher.einschaltenBeimAnlegen {
                // Vorbereitet in Frage 1 (v84, D1b, E538).
                Text("Mit „Planung anlegen“ wird die Verschlüsselung eingeschaltet; „Abbrechen“ verwirft sie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // In der Lücke nach einer Antwort prallen die Knöpfe ab (E437).
            Button("Abbrechen", action: speicher.blattknopf { abbrechen() })
                .keyboardShortcut(.cancelAction)
            Button("Planung anlegen", action: speicher.blattknopf { anlegen() })
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear(perform: vorbelegen)
        // Ein Fenster trägt nur ein Blatt: An der Hauptansicht angemeldet bliebe
        // die Rückfrage vor dem Anlegen unsichtbar (E275).
        .rueckfrage(speicher, ort: .neuePlanung)
        .sheet(item: $bogen) { bogen in
            switch bogen {
            case .iserv(let quelle):
                // Am Blatt nur „Je Klasse“; übernommen wird die Lesung, geschrieben mit „Planung anlegen“ (E605, E606).
                ImportBogen(quelle: quelle, gruppen: [], vorwahl: nil,
                            vorschau: { _, _ in Importbilanz() },
                            importieren: { lesung, _, _ in
                                uebernehmen(lesung, datei: quelle.name)
                                return Importbilanz()
                            },
                            archivieren: { _ in }, herausnehmen: { _ in }, personenname: { _ in "—" },
                            amBlattNeuePlanung: true)
            case .zuordnung(let vorlage):
                ZuordnungsBogen(gruppen: lerngruppen, stufen: stufen, zeilen: zeilenangebot,
                                mitglieder: { speicher.lernende.verzeichnis?.mitglieder($0).map(\.id) ?? [] },
                                rechnen: { w in
                                    let z = zuteilung(w, lerngruppen, stufen, zeilenangebot)
                                    return (z, mitkommend(w, z))
                                },
                                vorlage: vorlage, fertig: { wahl = $0 },
                                ohneZeile: "Keine Zeile, die eine Lerngruppe tragen kann — im Blatt unter „Klassen/Kurse“ eintragen "
                                    + "oder übernehmen.")
            }
        }
        // Prüfstand und Abbild geben die Lage des Bogens „Lerngruppen zuordnen“ vor, wenn das Blatt steht (E629, E630) — wie
        // der Knopf; verbraucht wird sie immer. Beobachtet: keine Frist im Programm (wie E610).
        .onChange(of: speicher.zuordnungsbogenVorgabe) { _, lage in
            guard let lage else { return }
            speicher.zuordnungsbogenVorgabe = nil
            zuordnungOeffnen(lage)
        }
        // Prüfstand und Abbild geben die Datei vor, wenn das Blatt steht (E610) — wie der Knopf, ohne Dateiwahl.
        .onChange(of: speicher.neuePlanungImportdatei) { _, datei in
            guard let datei else { return }
            speicher.neuePlanungImportdatei = nil
            if knopf.aktiv, bogen == nil { importdateiLesen(datei) }
        }
        // Titel und erster Schultag folgen der Wahl, solange sie unangetastet sind.
        .onChange(of: start) { alt, neu in
            if titel == vorschlagstitel(alt) { titel = vorschlagstitel(neu) }
            if ersterSchultag == alt { ersterSchultag = neu }
        }
    }

    // ── Klassen und Kurse ─────────────────────────────────────────────────

    private var kursabschnitt: some View {
        Section {
            eigeneEingabe
            sonderzeilenwahl
        } header: {
            Text("Klassen/Kurse")
        } footer: {
            Text("Bis zu \(Kennwerte.maxKlassen) Einträge, Sonderzeilen mitgezählt. Verbindlich ist allein die "
                 + "Bezeichnung der Klasse oder des Kurses. Ein Fach lässt sich anhängen: "
                 + "Leerzeichen, - oder –, Leerzeichen, dann das Fach. Jedes Fach bekommt "
                 + "eine eigene Farbe; unter „Lernende, Klassen/Kurse und Fächer“ ist sie zu ändern.")
        }
    }

    /// Die drei Sonderzeilen (E157), je ein Kästchen — abgeblendet, wenn
    /// dieselbe Art aus der aktuellen Planung übernommen wird.
    private var sonderzeilenwahl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sonderzeilen")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(Zeilenart.sonderzeilen, id: \.self) { art in
                    Toggle(art.titel, isOn: Binding(
                        get: { sonderzeilen.contains(art) },
                        set: { an in if an { sonderzeilen.insert(art) } else { sonderzeilen.remove(art) } }))
                        .toggleStyle(.checkbox)
                        .disabled(uebernommen(art))
                        .help(uebernommen(art)
                              ? "„\(art.titel)“ wird aus der aktuellen Planung übernommen"
                              : "Sonderzeile „\(art.titel)“ anlegen")
                }
            }
            Text("Stehen unterhalb der Klassen/Kurse in fester Reihenfolge und lassen sich wie "
                 + "eine Klasse nutzen — Vorhaben, Termine, Farbe; Klassenleitung und Weiteres "
                 + "dazu mit Verwaltungsdatei, ohne Curriculum und Sitzplan, Vertretungen ohne "
                 + "alle drei. Nur die Klassenleitung trägt ihre Klasse anstelle eines Faches, "
                 + "etwa „7a“ — gesetzt unter „Lernende, Klassen/Kurse und Fächer“.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    /// Wird eine Sonderzeile dieser Art aus der aktuellen Planung übernommen?
    private func uebernommen(_ art: Zeilenart) -> Bool {
        uebernahmeGewuenscht && alteKlassen.contains { $0.art == art && mitnehmen[$0.id] != nil }
    }

    /// „Zeile 3:“ fett, der Rest gewöhnlich.
    private func fehlerzeile(_ fehler: Kurszeilen.Fehler) -> AttributedString {
        var kopf = AttributedString("Zeile \(fehler.nummer): ")
        kopf.inlinePresentationIntent = .stronglyEmphasized
        return kopf + AttributedString("„\(fehler.zeile)“ — \(fehler.grund)")
    }

    private static let beispiel = """
        7a - Mathematik
        G9 - Chemie
        AG – LEGO-Robotik
        Chorprobe
        """

    private var eigeneEingabe: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eine Zeile je Klasse oder Kurs; ein Fach kann mit einem Bindestrich "
                 + "angehängt werden.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Textfeld(text: $kurstext, mindesthoehe: 120,
                     beschriftung: "Liste, eine Zeile je Klasse oder Kurs")
                .overlay(alignment: .topLeading) {
                    if kurstext.isEmpty {
                        Text(Self.beispiel)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            // Deckungsgleich mit der ersten Textzeile: 6 plus deren Rand (5 bzw. 3).
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                }

            if !kurstext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ergebnis = pruefung
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ergebnis.fehler.prefix(6)) { fehler in
                        Pruefzeile(gut: false, inhalt: Text(fehlerzeile(fehler)))
                    }
                    if ergebnis.fehler.count > 6 {
                        Pruefzeile(gut: false,
                                   inhalt: Text("… und \(ergebnis.fehler.count - 6) weitere Zeilen"))
                    }
                    if ergebnis.fehler.isEmpty {
                        Pruefzeile(gut: true, inhalt: Text(
                            "\(ergebnis.kurse.count) "
                            + (ergebnis.kurse.count == 1 ? "gültige Zeile" : "gültige Zeilen")
                            + (ergebnis.kurse.count > Kennwerte.maxKlassen
                               ? " — nur die ersten \(Kennwerte.maxKlassen) werden übernommen" : "")))
                    }
                }
            }
        }
    }

    // ── Lernende aus IServ (D) ────────────────────────────────────────────

    /// Nur mit Verschlüsselung — eingeschaltet oder in Frage 1 vorbereitet (E350); ohne sie gibt es keine Lernendenverwaltung.
    private var importMoeglich: Bool { speicher.tresor != nil || speicher.einschaltenBeimAnlegen }

    /// Verschlüsselt, aber die Lernendenverwaltung ist gesperrt (E533): Der Knopf ist grau, sein Hilfetext der
    /// Sperrhinweis (E614).
    private var sperrhinweis: String? {
        guard speicher.tresor != nil, !speicher.lernende.schreibbar else { return nil }
        return speicher.lernende.sperrhinweis ?? "Die Lernendenverwaltung ist gerade nicht verfügbar."
    }

    private var knopf: (aktiv: Bool, hilfe: String) {
        Self.importknopf(moeglich: importMoeglich, sperrhinweis: sperrhinweis, uebernommen: iserv != nil)
    }

    /// Der Knopf „Aus IServ importieren …“: aktiv nur mit Verschlüsselung (E350), offener Lernendenverwaltung (E614) und
    /// noch ohne Import (E612); der Hilfetext sagt, was fehlt — in dieser Folge.
    nonisolated static func importknopf(moeglich: Bool, sperrhinweis: String?, uebernommen: Bool) -> (aktiv: Bool, hilfe: String) {
        if !moeglich {
            return (false, "Nur mit eingeschalteter Verschlüsselung — die Lernendenverwaltung gibt es nur verschlüsselt")
        }
        if let sperrhinweis { return (false, sperrhinweis) }
        if uebernommen { return (false, "Schon übernommen — zum Ersetzen erst „Entfernen“") }
        return (true, "Eine Exportdatei der IServ-Benutzerverwaltung lesen — nur Vorname, Nachname und Klasse; "
                + "je Klasse entsteht eine Zeile und eine Lerngruppe")
    }

    /// Die Namen der Unterrichtszeilen, die „Planung anlegen“ schüfe — die eingetippten bis zur Grenze und die
    /// übernommenen ohne Sonderzeilen. Der Hinweis vergleicht nur den Namen (E617, E621).
    nonisolated static func unterrichtszeilen(eingaben: [(name: String, fach: String)], uebernommene: [Klasse]) -> [String] {
        eingaben.prefix(Kennwerte.maxKlassen).map(\.name) + uebernommene.filter { !$0.istSonderzeile }.map(\.name)
    }

    private var lernendenabschnitt: some View {
        Section {
            Button("Aus IServ importieren …") { importdateiWaehlen() }
                .disabled(!knopf.aktiv)
                .help(knopf.hilfe)
            if let iserv {
                HStack(spacing: 8) {
                    Text(Self.importzeile(iserv.lesung, datei: iserv.datei))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    // Nur der Import entfällt; die Zeilen im Feld bleiben — Handeingaben nie ungefragt (E611).
                    Button("Entfernen") { self.iserv = nil }
                }
                // Steht eine Klasse nicht (mehr) als Zeile im Feld, entsteht ihre Lerngruppe trotzdem — ohne Zeile (E613).
                let zeilen = Self.unterrichtszeilen(eingaben: pruefung.kurse, uebernommene: uebernommeneKlassen)
                if let hinweis = Self.ohneZeileHinweis(Self.ohneZeile(iserv.lesung, zeilennamen: zeilen)) {
                    Label(hinweis, systemImage: Zeichen.warnung)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Lernende")
        } footer: {
            Text("Freiwillig: Statt die Klassen von Hand einzutragen, lässt sich die Liste der Benutzerverwaltung lesen. "
                 + "Je Klasse der Datei entsteht oben eine Zeile — änderbar, ein Fach lässt sich anhängen — und eine "
                 + "Lerngruppe mit ihren Personen, an die Zeile gebunden. Gelesen werden nur Vorname, Nachname und Klasse; "
                 + "geschrieben wird erst mit „Planung anlegen“, verschlüsselt.")
        }
    }

    /// Die Klassen der Lesung, je Name einmal — Groß/Klein und Leerraum am Rand unerheblich, wie die Bindung (E521).
    nonisolated static func klassen(_ lesung: IServImport.Lesung) -> [String] {
        var gesehen = Set<String>()
        var klassen: [String] = []
        for zeile in lesung.zeilen {
            let name = zeile.klasse.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, gesehen.insert(name.lowercased()).inserted else { continue }
            klassen.append(name)
        }
        return klassen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// „Aus „‹Datei›“: ‹n› Personen in ‹m› Klassen — je Klasse eine Zeile und eine Lerngruppe.“
    /// Gezählt wird, wer eine Klasse trägt — nur sie kommen mit „Je Klasse“ an.
    nonisolated static func importzeile(_ lesung: IServImport.Lesung, datei: String) -> String {
        let n = lesung.zeilen.filter { !$0.klasse.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let m = klassen(lesung).count
        return "Aus „\(datei)“: \(n == 1 ? "1 Person" : "\(n) Personen") in \(m == 1 ? "1 Klasse" : "\(m) Klassen") — "
            + "je Klasse eine Zeile und eine Lerngruppe."
    }

    /// Die Klassen der Lesung ohne Unterrichtszeile gleichen Namens unter `zeilennamen` — ihre Lerngruppen entstehen
    /// ohne Zeile (E613). Verglichen wie die Bindung nach Namen: Groß/Klein und Leerraum am Rand unerheblich (E521).
    nonisolated static func ohneZeile(_ lesung: IServImport.Lesung, zeilennamen: [String]) -> [String] {
        let namen = Set(zeilennamen.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        return klassen(lesung).filter { !namen.contains($0.lowercased()) }
    }

    /// „Ohne Zeile im Feld: 6c, 7b — diese Lerngruppen entstehen ohne Zeile.“ — nach sechs Namen gekürzt (E617).
    nonisolated static func ohneZeileHinweis(_ klassen: [String]) -> String? {
        guard !klassen.isEmpty else { return nil }
        let liste = klassen.prefix(6).joined(separator: ", ") + (klassen.count > 6 ? " und \(klassen.count - 6) weitere" : "")
        return "Ohne Zeile im Feld: \(liste) — "
            + (klassen.count == 1 ? "diese Lerngruppe entsteht ohne Zeile." : "diese Lerngruppen entstehen ohne Zeile.")
    }

    /// Die Klassen der Lesung als Zeilen ans Ende des Felds — eine schon eingetippte oder übernommene Zeile gleichen
    /// Namens nicht noch einmal (E351, E623). Verglichen mit dem Namen jeder Zeile und mit der ganzen Zeile: „Q1 - LK“
    /// heißt im Feld „Q1“.
    nonisolated static func mitKlassen(_ kurstext: String, _ lesung: IServImport.Lesung, uebernommen: [String] = []) -> String {
        let vorhanden = Set((Kurszeilen.pruefen(kurstext).kurse.map(\.name) + kurstext.components(separatedBy: .newlines)
                             + uebernommen).map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let neu = klassen(lesung).filter { !vorhanden.contains($0.lowercased()) }
        guard !neu.isEmpty else { return kurstext }
        let basis = kurstext.trimmingCharacters(in: .newlines)
        return (basis.isEmpty ? "" : basis + "\n") + neu.joined(separator: "\n")
    }

    private func uebernehmen(_ lesung: IServImport.Lesung, datei: String) {
        iserv = (lesung, datei)
        kurstext = Self.mitKlassen(kurstext, lesung,
                                   uebernommen: uebernommeneKlassen.filter { !$0.istSonderzeile }.map(\.name))
    }

    private func importdateiWaehlen() {
        Systemzugriff.quelleWaehlen(nachricht: "Exportdatei der IServ-Benutzerverwaltung wählen",
                                    typen: [.commaSeparatedText, .tabSeparatedText, .plainText]) { url in
            if let url { importdateiLesen(url) }
        }
    }

    private func importdateiLesen(_ url: URL) {
        switch Ablage.gebundenLesen(url, hoechstens: IServImport.hoechstgroesse) {
        case .daten(let daten): bogen = .iserv(Importquelle(name: url.lastPathComponent, daten: daten))
        case .keine: speicher.melden("„\(url.lastPathComponent)“ ist nicht mehr da.", .warnung)
        case .zuGross(let groesse):
            speicher.melden("Die Datei ist mit \(groesse / 1024) KB zu groß für eine Liste der Benutzerverwaltung.", .warnung)
        case .unlesbar(let fehler): speicher.melden(fehler.localizedDescription, .warnung)
        }
    }

    // ── Übernahme aus der aktuellen Planung ───────────────────────────────

    private var alteKlassen: [Klasse] { speicher.planung?.klassen ?? [] }

    private var uebernahmeabschnitt: some View {
        Section {
            Toggle("Inhalte aus „\(speicher.planung?.titel ?? "")“ übernehmen",
                   isOn: $uebernahmeGewuenscht.animation())
            if uebernahmeGewuenscht {
                auswahlmatrix
            }
        } header: {
            Text("Übernahme aus der aktuellen Planung")
        } footer: {
            Text("Je Zeile wählbar: nur Klasse/Kurs und Fach — oder samt aller zugehörigen "
                 + "Vorhaben. Übernommene Vorhaben behalten ihren Abstand zum Schulbeginn: "
                 + "Das Vorhaben der 5. Schulwoche liegt in der 5. gezählten Woche der "
                 + "neuen Planung. "
                 + "Deren Zählung beginnt mit der Kalenderwoche des oben angegebenen ersten "
                 + "Schultags und richtet sich nach später eingetragenen Ferien. "
                 + "Übernommene Vorhaben beginnen unerledigt und ohne Termine; die "
                 + "Prüfungs-Kennzeichnung bleibt erhalten (Termin offen).")
        }
    }

    private var auswahlmatrix: some View {
        var zahl: [String: Int] = [:]
        for eintrag in speicher.planung?.eintraege ?? [] {
            zahl[eintrag.klasseId, default: 0] += 1
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button("Alle") {
                    // Eine schon getroffene „samt Vorhaben“-Wahl bleibt bestehen.
                    mitnehmen = Dictionary(uniqueKeysWithValues:
                        alteKlassen.map { ($0.id, mitnehmen[$0.id] == true) })
                }
                Button("Alle samt Vorhaben") {
                    // Ohne Vorhaben bleibt es beim Zeilen-Haken; der abgeblendete Haken soll nicht angekreuzt wirken.
                    mitnehmen = Dictionary(uniqueKeysWithValues:
                        alteKlassen.map { ($0.id, (zahl[$0.id] ?? 0) > 0) })
                }
                Button("Keine") { mitnehmen = [:] }
                Spacer(minLength: 0)
                Text("Klasse/Kurs\nund Fach")
                    .frame(width: Self.spalteHaken)
                Text("+ alle\nVorhaben")
                    .frame(width: Self.spalteHaken)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .buttonStyle(.borderless)
            .padding(.bottom, 2)

            ForEach(alteKlassen) { klasse in
                auswahlzeile(klasse, vorhaben: zahl[klasse.id] ?? 0)
            }
        }
    }

    private func auswahlzeile(_ klasse: Klasse, vorhaben: Int) -> some View {
        let stufe = mitnehmen[klasse.id]
        return HStack(spacing: 8) {
            Farbpunkt(ton: Farbwelt.ton(klasse.farbe), groesse: 8)
            Text(klasse.beschriftung)
                .lineLimit(1)
            Text("\(vorhaben) Vorhaben")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Hakenknopf(aktiv: stufe != nil,
                       breite: Self.spalteHaken,
                       hilfe: stufe != nil ? "Zeile nicht übernehmen"
                                           : "Klasse/Kurs und Fach übernehmen",
                       kennzeichnung: "Übernehmen — " + klasse.beschriftung) {
                if stufe != nil { mitnehmen[klasse.id] = nil }
                else { mitnehmen[klasse.id] = false }
            }
            Hakenknopf(aktiv: stufe == true,
                       breite: Self.spalteHaken,
                       hilfe: stufe == true ? "Vorhaben nicht mitnehmen"
                                            : "Samt aller zugehörigen Vorhaben übernehmen",
                       kennzeichnung: "Samt Vorhaben — " + klasse.beschriftung) {
                mitnehmen[klasse.id] = (stufe == true) ? false : true
            }
            .disabled(vorhaben == 0)
        }
    }

    private static let spalteHaken: CGFloat = 84

    // ── Lerngruppen ins neue Schuljahr (E271) ─────────────────────────────

    /// Nur mit eingeschalteter Verschlüsselung — ohne sie gibt es keine Lernendenverwaltung.
    private var lerngruppen: [Lerngruppe] {
        guard speicher.tresor != nil else { return [] }
        return speicher.lerngruppenZurWahl
    }

    /// Der Fuß des Abschnitts „Lerngruppen ins neue Schuljahr“, mit dem Import: nach den Stufen wie an ⌘O — beim echten
    /// Wechsel E827, im selben oder einem früheren Schuljahr E831 (E832).
    nonisolated static func fuss(stufen: Int) -> String {
        LerngruppenWahl.fuss(mitImport: true, termine: Lernendenbestand.terminwahl(stufen: stufen))
    }

    /// Die Schuljahre zwischen der Jahresdatei und der ersten Woche (E307).
    private var stufen: Int {
        speicher.stufen(zu: start)
    }

    /// Die neu gewählten Sonderzeilen — eine übernommene derselben Art zählt als übernommen.
    private var neueSonderzeilen: [Zeilenart] {
        Zeilenart.sonderzeilen.filter { sonderzeilen.contains($0) && !uebernommen($0) }
    }

    private var uebernommeneKlassen: [Klasse] {
        uebernahmeGewuenscht ? alteKlassen.filter { mitnehmen[$0.id] != nil } : []
    }

    /// Ohne Vertretungen (Z-AT9B-12) — eine Lerngruppe trägt sie nie.
    private var zeilenangebot: [Hochstufung.Zeile] {
        LerngruppenWahl.angebot(Self.zeilenangebot(eingaben: pruefung.kurse, sonderzeilen: neueSonderzeilen,
                                                   uebernommene: uebernommeneKlassen))
    }

    /// Die Zeilen je Gruppe (E311, E649) aus einer Wahl — als Schlüssel des Zeilenangebots.
    private func zuteilung(_ wahl: Hochstufungswahl, _ gruppen: [Lerngruppe], _ stufen: Int,
                           _ angebot: [Hochstufung.Zeile]) -> [String: [String]] {
        let herkunft = speicher.lernende.bestand?.planung ?? ""
        let schluessel = Dictionary(uniqueKeysWithValues: uebernommeneKlassen.map { ($0.id, "u:" + $0.id) })
        var uebernommen: [String: [String]] = [:]
        var namen: [String: String] = [:]
        for g in gruppen {
            let folge = Hochstufung.uebernommeneZeilen(g, planung: herkunft, zuordnung: schluessel)
            if !folge.isEmpty { uebernommen[g.id] = folge }
            namen[g.id] = wahl.suchname(g, stufen: stufen)
        }
        return Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: uebernommen, zeilen: angebot,
                                     gewaehlt: wahl.zeilen, frei: wahl.freieZeilen)
    }

    /// Wer ins neue Schuljahr mitkommt (E657): wer eine Zeile trägt oder mit dem neuen Namen als einzige im Import steht.
    private var mitkommendeGruppen: Set<String> {
        mitkommend(wahl, zuteilung(wahl, lerngruppen, stufen, zeilenangebot))
    }

    /// Dasselbe für eine Wahl und ihre Zuteilung — für das Blatt und den Bogen.
    private func mitkommend(_ w: Hochstufungswahl, _ zugeteilt: [String: [String]]) -> Set<String> {
        let gruppen = lerngruppen
        let zahl = stufen
        let namen = Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, w.suchname($0, stufen: zahl)) })
        return Self.mitkommend(gruppen, namen: namen, zuteilung: zugeteilt, lesung: iserv?.lesung)
    }

    /// Wer ins neue Schuljahr mitkommt (E657): wer eine Zeile trägt, dazu wer mit dem neuen Namen (`namen`) als einzige in der
    /// übernommenen Lesung steht (`Hochstufung.imImport`, Z-AT9M-11).
    nonisolated static func mitkommend(_ gruppen: [Lerngruppe], namen: [String: String], zuteilung: [String: [String]],
                                       lesung: IServImport.Lesung?) -> Set<String> {
        let importiert = lesung.map { Hochstufung.imImport(gruppen, namen: namen, klassen: klassen($0)) } ?? []
        return Hochstufung.mitkommend(zuteilung, importiert: importiert)
    }

    private var lerngruppenabschnitt: some View {
        let gruppen = lerngruppen
        let zahl = stufen
        let angebot = zeilenangebot
        let zugeteilt = zuteilung(wahl, gruppen, zahl, angebot)
        let an = wahl.hochstufen ?? (zahl > 0)
        let modell = Hochstufung.zeilenmodell(gruppen, mitkommend: mitkommend(wahl, zugeteilt),
                                              namen: Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, wahl.name($0, stufen: zahl)) }),
                                              zeilen: angebot, zuteilung: zugeteilt, ohneMitglieder: wahl.ohneMitglieder(gruppen))
        return LerngruppenWahl(
            fuss: Self.fuss(stufen: zahl),
            hochstufen: an,
            stufentext: Hochstufung.stufentext(bisher: speicher.bisherigesSchuljahr,
                                               neu: Lernendenbestand.schuljahr(fuer: start), stufen: zahl, an: an),
            hochstufenSetzen: { wahl.hochstufenSetzen($0) },
            zusammenfassung: modell.zusammenfassung,
            zuordnen: speicher.blattknopf { zuordnungOeffnen(.vorschlag) })
    }

    /// Der Bogen „Lerngruppen zuordnen“ auf einer Kopie der Wahl (E384) — nur mit Lerngruppen (E647), nie über einem Alert
    /// oder einem anderen Bogen am Blatt.
    private func zuordnungOeffnen(_ lage: Zuordnungslage) {
        let gruppen = lerngruppen
        guard bogen == nil, speicher.rueckfrage == nil,
              LerngruppenWahl.knopfFrei(verschluesselt: speicher.tresor != nil, gruppen: gruppen) else { return }
        var anfang = wahl
        anfang.lage(lage, gruppen: gruppen.filter { $0.archiviert.isEmpty }.sorted(by: Lerngruppe.vorgehen),
                    zuteilung: zuteilung(wahl, gruppen, stufen, zeilenangebot))
        bogen = .zuordnung(Zuordnungsvorlage(anfang: anfang))
    }

    /// Name und Zeilen je gewählter Gruppe, beim Anlegen — die Zeilen an der
    /// Kennung, die `klassen` trägt, übernommene an ihrer alten (E308, E310, E649).
    private func gruppenziele(_ gruppen: Set<String>, klassen: [Klasse]) -> [String: Gruppenwahl] {
        let alle = lerngruppen
        let zahl = stufen
        let zugeteilt = zuteilung(wahl, alle, zahl, zeilenangebot)
        var ziele: [String: Gruppenwahl] = [:]
        for g in alle where gruppen.contains(g.id) {
            ziele[g.id] = Gruppenwahl(name: wahl.name(g, stufen: zahl),
                                      zeilen: (zugeteilt[g.id] ?? []).map {
                                          Self.zielzeile($0, eingaben: pruefung.kurse, klassen: klassen)
                                      }.filter { $0 != .keine })
        }
        return ziele
    }

    /// Ohne Groß/Klein und Leerraum am Rand — wie die Zuteilung vergleicht.
    private nonisolated static func schluessel(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private nonisolated static func eingabeschluessel(_ name: String, _ fach: String) -> String {
        "e:" + schluessel(name) + "\u{1F}" + schluessel(fach)
    }

    /// Die Zeilen der neuen Planung, wie das Blatt sie einer Lerngruppe
    /// anbietet (E310): eingetippte, neu gewählte Sonderzeilen, übernommene.
    /// Noch ohne Kennung — der Schlüssel bleibt beim Tippen in der Liste stehen:
    /// „e:“ Name und Fach, „s:“ die Art, „u:“ die alte Kennung.
    nonisolated static func zeilenangebot(eingaben: [(name: String, fach: String)], sonderzeilen: [Zeilenart],
                                          uebernommene: [Klasse]) -> [Hochstufung.Zeile] {
        var angebot: [Hochstufung.Zeile] = []
        var gesehen = Set<String>()
        for e in eingaben.prefix(Kennwerte.maxKlassen) {
            let id = eingabeschluessel(e.name, e.fach)
            guard gesehen.insert(id).inserted else { continue }
            let name = e.name.trimmingCharacters(in: .whitespaces)
            let fach = e.fach.trimmingCharacters(in: .whitespaces)
            angebot.append(Hochstufung.Zeile(id: id, name: name, fach: fach, art: .unterricht,
                                             titel: name + (fach.isEmpty ? "" : " · " + fach)))
        }
        for art in sonderzeilen {
            angebot.append(Hochstufung.Zeile(id: "s:" + art.rawValue, name: art.titel, fach: "", art: art, titel: art.titel))
        }
        for klasse in uebernommene {
            angebot.append(Hochstufung.Zeile(klasse, id: "u:" + klasse.id))
        }
        return angebot
    }

    /// Der Schlüssel als Zeile der neuen Planung — eingetippte und Sonderzeilen
    /// an der Kennung, die sie in `klassen` (beim Anlegen gebaut) tragen.
    nonisolated static func zielzeile(_ schluessel: String?, eingaben: [(name: String, fach: String)],
                                      klassen: [Klasse]) -> Zielzeile {
        guard let schluessel, !schluessel.isEmpty else { return .keine }
        if schluessel.hasPrefix("u:") { return .uebernommen(String(schluessel.dropFirst(2))) }
        if schluessel.hasPrefix("s:") {
            guard let art = Zeilenart(rawValue: String(schluessel.dropFirst(2))),
                  let k = klassen.first(where: { $0.art == art }) else { return .keine }
            return .kennung(k.id)
        }
        // Eine eingetippte Zeile steht in `klassen` an der Stelle ihrer ersten Eingabe.
        let getippt = min(eingaben.count, Kennwerte.maxKlassen)
        guard let stelle = eingaben.prefix(getippt).firstIndex(where: { eingabeschluessel($0.name, $0.fach) == schluessel }),
              stelle < klassen.count, klassen[stelle].art == .unterricht else { return .keine }
        return .kennung(klassen[stelle].id)
    }

    // ── Ableitungen ───────────────────────────────────────────────────────

    private var zeitraumText: String {
        let liste = Tag.wochenListe(start: start, anzahl: anzahl)
        guard let erste = liste.first, let letzte = liste.last else { return "KW – bis KW –" }
        return "KW \(erste.kw)/\(erste.jahr) bis KW \(letzte.kw)/\(letzte.jahr)"
    }

    /// Zusammengesetzt statt im `Text` verkettet: Sechs Teile in einem Ausdruck
    /// überfordern die Typprüfung des Übersetzers.
    private var zeitraumfussnote: String {
        let satz = "Das Schuljahr beginnt am 1. August; vorbelegt ist die Woche, in die "
            + "dieser Tag fällt — ein anderes Datum rückt auf den Montag seiner Woche. "
        let regel = "Die 1. Schulwoche ist die Kalenderwoche, in die der erste Schultag "
            + "fällt — davor liegende Wochen tragen keine Schulwochen-Nummer. "
        return satz + regel + zeitraumText
    }

    /// Das Schuljahr, das die erste Woche eröffnet: Der 1. August liegt mitten
    /// in dieser Woche, deshalb entscheidet ihr Sonntag.
    private func vorschlagstitel(_ erste: Tag) -> String {
        let jahr = erste.plus(tage: 6).schuljahresbeginn.jahr
        return "Unterrichtsplanung \(jahr)/\(String(jahr + 1).suffix(2))"
    }

    private func vorbelegen() {
        start = Tag.laufendesSchuljahr
        titel = vorschlagstitel(start)
        ersterSchultag = start
        wochen = Double(Kennwerte.wochenStandard)
        kurstext = ""
        sonderzeilen = []
        uebernahmeGewuenscht = false
        mitnehmen = [:]
        wahl = Hochstufungswahl()
        iserv = nil
        bogen = nil
        // Eine liegengebliebene Datei aus Prüfstand oder Abbild öffnet später nichts (E610).
        speicher.neuePlanungImportdatei = nil
        // Nur ein Abbild gibt etwas vor (AP14c-2).
        if let vorgabe = speicher.neuePlanungVorgabe {
            speicher.neuePlanungVorgabe = nil
            start = vorgabe.start
            titel = vorschlagstitel(vorgabe.start)
            ersterSchultag = vorgabe.start
            kurstext = vorgabe.kurstext
            mitnehmen = vorgabe.mitnehmen
            uebernahmeGewuenscht = !vorgabe.mitnehmen.isEmpty
        }
        titelFokus = true
    }

    /// „Abbrechen“ und ⎋: Was Frage 1 vorbereitet hat, geht mit (E477 b).
    private func abbrechen() {
        speicher.neuePlanungAbbrechen()
        schliessen()
    }

    private func anlegen() {
        let ergebnis = pruefung
        guard ergebnis.fehler.isEmpty else {
            speicher.melden(ergebnis.fehler.count == 1
                            ? "Zeile \(ergebnis.fehler[0].nummer) ist unvollständig."
                            : "\(ergebnis.fehler.count) Zeilen sind unvollständig.",
                            .warnung)
            return
        }
        // Die gewählten Sonderzeilen in fester Folge; wird dieselbe Art
        // übernommen, zählt die Übernahme (E157: eine je Art).
        let gewaehlte = Zeilenart.sonderzeilen
            .filter { sonderzeilen.contains($0) && !uebernommen($0) }
            .map(Klasse.sonderzeile)
        let klassen = Standardkurse.aufbauen(ergebnis.kurse) + gewaehlte
        let auswahl: [Planung.Uebernahmewunsch] = uebernahmeGewuenscht
            ? alteKlassen.compactMap { klasse in
                mitnehmen[klasse.id].map { Planung.Uebernahmewunsch(klasse: klasse,
                                                                    mitVorhaben: $0) }
            }
            : []
        guard klassen.count + auswahl.count <= Kennwerte.maxKlassen else {
            speicher.melden("Höchstens \(Kennwerte.maxKlassen) Klassen/Kurse — "
                            + "bitte die Auswahl verringern.", .warnung)
            return
        }
        guard ersterSchultag.liegtImZeitraum(start: start, wochen: anzahl) else {
            speicher.melden("Der erste Schultag liegt außerhalb des Planungszeitraums "
                            + "(\(zeitraumText)).", .warnung)
            return
        }
        let gruppen: Set<String>? = speicher.tresor != nil ? mitkommendeGruppen : nil
        let ziele = gruppen.map { gruppenziele($0, klassen: klassen) } ?? [:]
        // Die Menge immer mit — auch wenn der Bogen nie offen war, gilt die Vorbelegung (E708).
        let ohne: Set<String> = gruppen == nil ? [] : wahl.ohneMitglieder(lerngruppen)
        let titel = titel
        let start = start
        let anzahl = anzahl
        let ersterSchultag = ersterSchultag
        let gelesen = iserv.map { (lesung: $0.lesung, ziel: Importziel.jeKlasse) }
        // Ohne Verschlüsselung über einer bisherigen Planung erst fragen (E275).
        speicher.neuePlanungFragen(ort: .neuePlanung) { [speicher, schliessen] in
            // Kein Basisordner: Materialien werden mit vollem Pfad hinterlegt.
            // Eingeschaltet wird, was Frage 1 vorbereitet hat (E531).
            speicher.neuePlanung(titel: titel, start: start, wochen: anzahl,
                                 basis: "", klassen: klassen, ersterSchultag: ersterSchultag,
                                 uebernahme: auswahl, lerngruppen: gruppen, ziele: ziele, ohneMitglieder: ohne,
                                 iserv: gelesen, einschalten: speicher.einschaltenBeimAnlegen)
            // Ohne Klassen schaltet `neuePlanung` selbst auf das Folgeblatt weiter;
            // `schliessen()` schriebe die Blattbindung synchron wieder auf nil.
            if speicher.offenerDialog == .neuePlanung { schliessen() }
        }
    }
}

/// Hält den Wert im erlaubten Bereich.
struct Wochenzahlfeld: View {
    @Binding var wochen: Double

    var body: some View {
        TextField("Wochen", value: Binding(
            get: { Int(wochen) },
            set: { wochen = Double(min(Kennwerte.wochenMax, max(1, $0))) }),
                  format: .number)
            .multilineTextAlignment(.trailing)
            .frame(width: 60)
            .labelsHidden()
    }
}
