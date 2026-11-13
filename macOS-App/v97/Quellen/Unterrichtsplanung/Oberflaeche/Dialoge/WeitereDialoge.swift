// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// ── Farbwahl ──────────────────────────────────────────────────────────────

/// Die 24 Farben als Raster — für ein Fach oder für eine einzelne Zeile, die
/// sich damit vom Fach löst.
struct FarbwahlDialog: View {
    let ziel: Farbwahlziel

    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    private enum Feld {
        static let hoehe: CGFloat = 38
        static let stufenspalte: CGFloat = 52
        static let abstand: CGFloat = 6
    }

    private var planung: Planung? { speicher.planung }
    private var klasse: Klasse? { ziel.klasseId.flatMap { planung?.klasse($0) } }

    /// Wie das Fach in der Liste steht — sonst der kleingeschriebene Schlüssel.
    private var fachname: String? {
        guard let schluessel = ziel.fach else { return nil }
        let getragen = planung?.klassen.first {
            Farbwelt.fachSchluessel($0.fach) == schluessel
        }
        return getragen?.fach.trimmingCharacters(in: .whitespaces) ?? schluessel
    }

    private var gewaehlteStelle: Int? {
        if let klasse { return klasse.farbe }
        if let schluessel = ziel.fach { return planung?.fachfarbe(schluessel) }
        return nil
    }

    private var unterzeile: String {
        if let klasse { return klasse.beschriftung }
        if let fachname { return "Fach: " + fachname }
        return "—"
    }

    /// Auch ohne Fachfarbe anzubieten: Das Merkmal „von Hand gesetzt“ abzulegen
    /// heißt dann, dass die Zeile die Farbe ihres Fachs künftig mitträgt.
    private var kannDemFachFolgen: Bool {
        guard let klasse, klasse.farbeManuell else { return false }
        return !Farbwelt.fachSchluessel(klasse.fach).isEmpty
    }

    var body: some View {
        // Liegt nur auf ⌘K und zeigt dessen Meldungen, solange er steht — wie der Material-Bogen (E490, E968).
        Dialograhmen(titel: "Farbe wählen", unterzeile: unterzeile, hoehe: 460, meldungsblatt: .klassen) {
            Section {
                raster
                // Gilt dem ganzen Raster: eigene Zeile darunter, im Kasten (E1122).
                Erlaeuterung(hinweis)
            }
        } fuss: {
            if kannDemFachFolgen, let klasseId = ziel.klasseId {
                Button {
                    speicher.farbeDemFachFolgen(klasse: klasseId)
                    schliessen()
                } label: {
                    Label("Wieder dem Fach folgen", systemImage: Zeichen.neu)
                }
            }
            Fussluecke()
            Button("Fertig") { schliessen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var hinweis: String {
        if ziel.fach != nil {
            return "Die Farbe gilt für alle Klassen und Kurse dieses Fachs — außer "
                 + "denen, deren Farbe von Hand gesetzt wurde."
        }
        return "Die Farbe gilt nur für diese Klasse bzw. diesen Kurs. Alle übrigen "
             + "Klassen und Kurse des Fachs folgen weiterhin der Fachfarbe."
    }

    // ── Raster ────────────────────────────────────────────────────────────
    // Keine Mindestbreite: Ein zu breites Raster ließe das gruppierte Form seine Einzüge fallen.

    private var raster: some View {
        Grid(horizontalSpacing: Feld.abstand, verticalSpacing: Feld.abstand) {
            GridRow {
                Color.clear.frame(width: Feld.stufenspalte, height: 1)
                ForEach(Farbwelt.grundfarben, id: \.schluessel) { grund in
                    Text(grund.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            ForEach(Farbwelt.anzeigezeilen) { zeile in
                GridRow {
                    Text(zeile.stufe.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: Feld.stufenspalte, alignment: .trailing)
                        .accessibilityHidden(true)
                    ForEach(zeile.toene, id: \.stelle) { ton in
                        farbfeld(ton)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func farbfeld(_ ton: Farbton) -> some View {
        let gewaehlt = gewaehlteStelle == ton.stelle
        return Button {
            waehlen(ton)
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .fill(Kursfarben.farbe(ton))
                .frame(maxWidth: .infinity)
                .frame(height: Feld.hoehe)
                .overlay {
                    // Ohne Kante zerfließt die hellste Stufe auf weißem Grund.
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Systemfarben.feldkante, lineWidth: 1)
                }
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(gewaehlt ? Color.accentColor : .clear, lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
        .help(ton.name)
        .accessibilityLabel(ton.name)
        .accessibilityAddTraits(gewaehlt ? [.isSelected] : [])
    }

    private func waehlen(_ ton: Farbton) {
        if let klasseId = ziel.klasseId {
            speicher.farbeSetzen(klasse: klasseId, farbe: ton.stelle)
        } else if let schluessel = ziel.fach {
            speicher.fachfarbeSetzen(fach: schluessel, ton: ton.schluessel)
        }
        schliessen()
    }
}

// ── Einstellungen ─────────────────────────────────────────────────────────

/// Die Einträge der Leiste im Einstellungsblatt (v95, E1118) — aus den bisherigen Überschriften abgeleitet, in
/// dieser Folge (Nutzer, 07.11.2026).
enum Einstellungsbereich: String, CaseIterable, Hashable {
    case zeitraum, sicherungskopie, verschluesselung, updates, materialien, stand

    var titel: String {
        switch self {
        case .zeitraum: "Zeitraum"
        case .sicherungskopie: "Sicherungskopie"
        case .verschluesselung: "Verschlüsselung"
        case .updates: "Updates"
        case .materialien: "3ducation.org"
        case .stand: "Stand"
        }
    }

    var symbol: String {
        switch self {
        case .zeitraum: Zeichen.kalender
        case .sicherungskopie: "externaldrive"
        case .verschluesselung: Zeichen.schloss
        case .updates: "arrow.down.circle"
        case .materialien: "globe"
        case .stand: Zeichen.hinweis
        }
    }
}

struct EinstellungenDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @State private var start = Tag.heute
    @State private var wochen = Double(Kennwerte.wochenStandard)
    /// `nil` heißt: Kein erster Schultag gesetzt, die Zählung wird hergeleitet.
    @State private var ersterSchultag: Tag?
    /// Der gewählte Eintrag der Leiste — nur in der Sitzung des Blatts; jedes Öffnen beginnt bei „Zeitraum“.
    @State private var bereich: Einstellungsbereich

    /// Die App öffnet immer mit „Zeitraum“ (E1126); einen anderen Eintrag reichen nur die Abbilder herein (R-BG5a-01).
    init(bereich: Einstellungsbereich = .zeitraum) {
        _bereich = State(initialValue: bereich)
    }

    /// 780 breit (E1121: „Ändere die Breite im Einstellungsblatt bitte auf 780.“ — Leiste 250, Inhalt 530); 640 hoch
    /// (E1129) — gemessen braucht der längste Eintrag, die Sicherungskopie mit beiden Warnzeilen, 534 pt bei 552 sichtbar.
    static let blattbreite: CGFloat = 780
    static let blatthoehe: CGFloat = 640
    /// Die Höhe dieses Blatts, beim ersten Zeichnen festgelegt (E1150).
    @State private var blattmass = Blatthoehe(EinstellungenDialog.blatthoehe)

    private var planung: Planung? { speicher.planung }
    private var anzahl: Int { min(Kennwerte.wochenMax, max(1, Int(wochen.rounded()))) }

    private var ersterSchultagAusserhalb: Bool {
        guard let erster = ersterSchultag else { return false }
        return !erster.liegtImZeitraum(start: start, wochen: anzahl)
    }

    var body: some View {
        // Blatt mit Seitenleiste (v95, E1118): die bisherigen Abschnitte als Einträge einer
        // Seitenleiste — derselbe Rahmen wie das Vorhaben-Blatt —, rechts der Inhalt des gewählten als gruppiertes `Form`.
        // Logik, Bindungen und Meldungen wie bisher; nur die Anordnung ist neu.
        Seitenleistenrahmen(titel: "Einstellungen",
                            eintraege: Einstellungsbereich.allCases,
                            auswahl: $bereich,
                            name: \.titel, symbol: \.symbol,
                            breite: Self.blattbreite, hoehe: blattmass.wert) {
            seite(bereich)
        } fuss: {
            Spacer(minLength: 0)
            // In der Lücke nach einer Antwort prallen die Knöpfe ab (E437).
            // E1125: „Abbrechen“ gläsern wie im Vorhaben-Blatt, „Übernehmen“ hervorgehoben.
            Button("Abbrechen", action: speicher.blattknopf { schliessen() })
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button("Übernehmen", action: speicher.blattknopf {
                speicher.einstellungenUebernehmen(start: start, wochen: anzahl,
                                                  ersterSchultag: ersterSchultag)
            })
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
        .rueckfrage(speicher, ort: .einstellungen)
        .onAppear {
            guard let planung else { return }
            start = planung.start
            wochen = Double(planung.wochen)
            ersterSchultag = planung.ersterSchultag
        }
    }

    /// Der Inhalt des gewählten Eintrags — je Eintrag ein eigenes gruppiertes `Form` mit einem Abschnitt, ohne Kopf:
    /// Den Namen trägt schon der Kopf neben der Kapsel.
    @ViewBuilder
    private func seite(_ bereich: Einstellungsbereich) -> some View {
        switch bereich {
        case .zeitraum: Seitenform { zeitraum }
        case .sicherungskopie: Seitenform { sicherungskopie }
        case .verschluesselung: Seitenform { verschluesselung }
        case .updates: Seitenform { updates }
        case .materialien: Seitenform { materialien }
        case .stand: Seitenform { if let planung { kennzahlen(planung) } }
        }
    }

    /// Der Zeitraum der Planung — als Einziges erst mit „Übernehmen“ gültig.
    private var zeitraum: some View {
        Section {
            LabeledContent("Erste Woche des Schuljahres") {
                HStack(spacing: 8) {
                    // Wie im Anlege-Dialog: Der Setter rastet auf den Montag
                    // ein, ein Schritt um einen Tag verpuffte dadurch nach
                    // oben und sprang nach unten gleich eine Woche zurück.
                    Datumsfeld(tag: Binding(get: { start },
                                            set: { start = $0.montagDerWoche }),
                               schritt: 7)
                    Text("Montag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Erster Schultag") {
                HStack(spacing: 8) {
                    if ersterSchultag == nil {
                        Button("Tag festlegen") { ersterSchultag = start.montagDerWoche }
                            .buttonStyle(.link)
                        Text("keiner — die 1. Schulwoche wird hergeleitet")
                            .foregroundStyle(.secondary)
                    } else {
                        Datumsfeld(tag: Binding(get: { ersterSchultag ?? start },
                                                set: { ersterSchultag = $0 }))
                        Button("Ohne Tag") { ersterSchultag = nil }
                            .buttonStyle(.link)
                    }
                }
            }
            // Warnzeile in der einen Erscheinung (E1122, `Erlaeuterung`).
            if ersterSchultagAusserhalb {
                Erlaeuterung("Der erste Schultag liegt außerhalb des Zeitraums.", warnung: true)
            }
            // Die Vorschau steht als Unterzeile im Kasten, nicht mehr darunter (E1122: „Achte darauf,
            // dass die Erläuterungen stets im grau hinterlegten Feld stehen, nicht darunter.“).
            LabeledContent {
                HStack(spacing: 12) {
                    Slider(value: $wochen, in: 1...Double(Kennwerte.wochenMax), step: 1) {
                        Text("Unterrichtswochen")
                    }
                    .labelsHidden()
                    .frame(minWidth: 160)

                    Wochenzahlfeld(wochen: $wochen)
                }
            } label: {
                Text("Unterrichtswochen")
                Text(vorschau)
            }
            .help(vorschau)
        }
    }

    /// Die Warnung steht schon hier und nicht erst in der Rückfrage: Wer den
    /// Regler zieht, soll sehen, was er kostet.
    private var vorschau: String {
        let liste = Tag.wochenListe(start: start, anzahl: anzahl)
        guard let erste = liste.first, let letzte = liste.last, let planung else { return "" }
        let verlust = planung.eintraege.count { $0.woche >= anzahl }
        return "KW \(erste.kw)/\(erste.jahr) bis KW \(letzte.kw)/\(letzte.jahr)"
            + (verlust > 0
               ? " — Achtung: \(verlust) Vorhaben lägen außerhalb und würden entfernt." : "")
    }

    /// Unterzeile und Tooltip des Schalters — bis 2.7.1 der letzte Absatz unter dem Abschnitt (E1122).
    static let sicherungskopieHilfe = "Die Kopie wird nur verschlüsselt geschrieben: Mit der Wahl des Ordners wird "
        + "die Verschlüsselung eingerichtet, falls sie noch aus ist."

    /// Die zusätzliche Kopie beim Beenden.
    @ViewBuilder
    private var sicherungskopie: some View {
        @Bindable var speicher = speicher
        let gewaehlt = !speicher.autoexportOrdner.isEmpty

        Section {
            // Gekoppelt: Einschalten ohne Tresor richtet erst die Verschlüsselung
            // ein — die Kopie gibt es nur verschlüsselt.
            Toggle(isOn: Binding(get: { speicher.autoexportAktiv },
                                 set: { speicher.autoexportUmschalten($0) })) {
                Text("Beim Beenden zusätzlich sichern")
                Text(Self.sicherungskopieHilfe)
            }
            .help(Self.sicherungskopieHilfe)

            LabeledContent {
                HStack(spacing: 8) {
                    Text(gewaehlt ? speicher.autoexportOrdner : "noch keiner gewählt")
                        .foregroundStyle(gewaehlt ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(gewaehlt ? speicher.autoexportOrdner : "")
                    Button("Wählen …") { speicher.autoexportOrdnerWaehlen() }
                }
            } label: {
                Text("Zielordner")
                Text(Self.zielordnerHilfe)
            }
            // Gilt Schalter und Zielordner zugleich — eine eigene Zeile, gleich danach. „oben“ entfällt: Der Zeitraum ist
            // ein eigener Eintrag der Leiste.
            Erlaeuterung("Schalter und Zielordner wirken sofort — „Abbrechen“ nimmt sie nicht "
                         + "zurück; „Übernehmen“ gilt allein dem Zeitraum.")
            if let grund = speicher.zugriff.ungesichert ?? speicher.zugriff.sperrgrund {
                lesezeichenZeile(grund, ungesichert: speicher.zugriff.ungesichert != nil)
            }
            // Der Ordner ist gespeichert, aber der App in dieser Fassung noch nicht
            // gezeigt worden — ohne die Wahl gibt es keine Kopie.
            if let freigabe = speicher.ausstehendeFreigaben.first(where: { $0.zweck == .zielordner }) {
                zugriffZeile { speicher.nachwahlWaehlen(freigabe) }
            }

            LabeledContent("Dateiname", value: speicher.autoexportDateiname)

            LabeledContent("Zuletzt geschrieben") {
                HStack(spacing: 10) {
                    Text(speicher.letzterAutoexport.map(Zeitrechnung.zeitpunktLang) ?? "noch nie")
                        .foregroundStyle(speicher.letzterAutoexport == nil ? .secondary : .primary)
                    Button("Jetzt schreiben") {
                        speicher.autoexportAusfuehren(vomNutzer: true)
                    }
                    .disabled(!gewaehlt || planung == nil)
                }
            }
            // Gilt der Kopie als Ganzer — eine eigene Zeile am Ende des Kastens.
            Erlaeuterung("Die laufende Autosicherung bleibt davon unberührt — sie ist weiterhin der "
                         + "maßgebliche Stand. Die Kopie wird bei jedem Beenden unter demselben Namen "
                         + "neu geschrieben und ist die Datei, die die Web App liest. "
                         + "Gelesen wird im Zielordner nur die Statusdatei der Web App; aufgeräumt "
                         + "wird dort nie.")
        }
    }

    /// Die Warnzeile zu den Lesezeichen: das Etikett wie bisher, der Text als Warnung in der einen Erscheinung (E1122).
    private func lesezeichenZeile(_ grund: String, ungesichert: Bool) -> some View {
        LabeledContent("Lesezeichen") {
            Erlaeuterung(ungesichert
                         ? "nicht versiegelt gesichert (\(grund)) — gelten für diese Sitzung, die App "
                           + "versucht es beim nächsten Schreiben und Start erneut"
                         : "gesperrt (\(grund)) — bis der nächste Start den Behälter liest",
                         warnung: true)
        }
    }

    /// Die Warnzeile zum Zugriff auf den Zielordner, mit dem Knopf, der ihn erlaubt.
    private func zugriffZeile(_ erlauben: @escaping @MainActor () -> Void) -> some View {
        LabeledContent("Zugriff") {
            HStack(spacing: 8) {
                Erlaeuterung("noch nicht erlaubt — bitte den Ordner einmal wählen", warnung: true)
                Button("Erlauben …", action: erlauben)
            }
        }
    }

    /// Unterzeile des Zielordners — bis 2.7.1 der letzte Absatz unter dem Kasten (E1122).
    static let zielordnerHilfe = "Ein frisch gewählter Ordner wird sofort einmal beschrieben — damit hier und "
        + "nicht erst beim Beenden feststeht, dass es klappt. Wird er später umbenannt "
        + "oder verschoben, findet ihn die App wieder und führt den Pfad nach."

    /// Die Prüfung auf Updates: der Schalter, die letzte Prüfung, der Weg von
    /// Hand — und wörtlich, was dabei übertragen wird.
    @ViewBuilder
    private var updates: some View {
        Section {
            Toggle(isOn: Binding(get: { speicher.updatesErlaubt },
                                 set: { speicher.updatesErlauben($0) })) {
                Text("Beim Öffnen nach Updates suchen")
                Text(Updates.datenschutzhinweis)
            }
            .help(Updates.datenschutzhinweis)

            LabeledContent("Zuletzt geprüft") {
                HStack(spacing: 10) {
                    Text(speicher.updatestand.zuletzt.map(Zeitrechnung.zeitpunktLang) ?? "noch nie")
                        .foregroundStyle(speicher.updatestand.zuletzt == nil ? .secondary : .primary)
                    Button("Jetzt suchen") { speicher.updatesPruefen(erzwungen: true) }
                        .disabled(speicher.updateLaeuft)
                }
            }
            // Die Rückmeldung steht hier, nicht nur im Melder — der läge unter dem Blatt.
            if speicher.updateLaeuft {
                LabeledContent("Ergebnis") { Text("wird geprüft …").foregroundStyle(.secondary) }
            } else if let meldung = speicher.updateMeldung {
                LabeledContent("Ergebnis") { Text(meldung) }
            }
            // Gilt Schalter und „Jetzt suchen“ zugleich — eine eigene Zeile am Ende des Kastens.
            Erlaeuterung("Der Schalter wirkt sofort. „Jetzt suchen“ fragt auch bei ausgeschalteter "
                         + "Prüfung — auf diesen Befehl hin, wie „\(Updates.menuebefehl)“ im Menü "
                         + "„Unterrichtsplanung“. Gefunden wird das jüngste Release des Repositorys; "
                         + "geladen und installiert wird nichts von selbst.")
        }
    }

    /// Die Materialliste von 3ducation.org: der Schalter — und wörtlich, was
    /// beim Öffnen des Blatts übertragen wird (v71, E176).
    @ViewBuilder
    private var materialien: some View {
        Section {
            // Beide Absätze gelten allein dem Schalter: eine Unterzeile, die Absätze durch einen Zeilenwechsel getrennt.
            Toggle(isOn: Binding(get: { speicher.materialienErlaubt },
                                 set: { speicher.materialienErlauben($0) })) {
                Text("Materialliste von 3ducation.org im Vorhaben-Dialog anbieten")
                Text(Self.materialienHilfe)
            }
            .help(Self.materialienHilfe)
        }
    }

    /// Unterzeile des Schalters für die Materialliste — bis 2.7.1 die zwei Absätze unter dem Kasten (E1122).
    static let materialienHilfe = Materialien.datenschutzhinweis + "\n"
        + "Der Schalter wirkt sofort. Ausgeschaltet zeigt der Knopf im Vorhaben-Dialog "
        + "statt der Liste diese Frage — vor „Einschalten“ geht nichts ins Netz."

    /// Die Verschlüsselung: Stand, Wicklungen und der Weg zum Dialog.
    @ViewBuilder
    private var verschluesselung: some View {
        Section {
            LabeledContent {
                HStack(spacing: 10) {
                    Label(speicher.verschluesselt ? "eingeschaltet" : "ausgeschaltet",
                          systemImage: speicher.verschluesselt ? Zeichen.schloss : Zeichen.schlossOffen)
                    Button(speicher.verschluesselt ? "Verwalten …" : "Einschalten …") {
                        speicher.dialogOeffnen(.verschluesselung)
                    }
                }
            } label: {
                Text("Stand")
                Text(verschluesselungHinweis)
            }
            .help(verschluesselungHinweis)
            if speicher.verschluesselt {
                LabeledContent("Wicklungen") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(speicher.wicklungen, id: \.art) { wicklung in
                            Text(wicklung.beschriftung)
                        }
                    }
                }
            }
        }
    }

    /// Unterzeile des Stands der Verschlüsselung — bis 2.7.1 der Absatz unter dem Kasten, Wortlaut unverändert (E1122).
    private var verschluesselungHinweis: String {
        speicher.verschluesselt
            ? "Ablage, Lesezeichen, Sicherungskopie und Export sind mit AES-256 versiegelt. Beim Start "
              + "entsperrt \(Tresor.freigabeName(biometrie: speicher.geraeteBiometrie)); in der Web App öffnet die "
              + "Passphrase. Der Klartext-Export bleibt als eigener Befehl im Menü „Ablage“."
            : "Ausgeschaltet liegt die Planung als lesbares JSON auf diesem Mac. FileVault "
              + "schützt mehr als diese Einstellung — sie ist die Schicht für die Kopie, "
              + "die den Rechner verlässt, und für Rechner ohne FileVault."
    }

    @ViewBuilder
    private func kennzahlen(_ planung: Planung) -> some View {
        let materialien = planung.eintraege.reduce(0) { $0 + $1.materialien.count }
        let aussen = planung.basis.isEmpty
            ? 0 : planung.eintraege.reduce(0) { $0 + $1.materialien.count(where: \.istAbsolut) }
        let links = planung.eintraege.reduce(0) { $0 + $1.links.count }

        Section {
            LabeledContent("Vorhaben", value: "\(planung.eintraege.count)")
            LabeledContent("Materialverweise",
                           value: "\(materialien)"
                           + (aussen > 0 ? " (davon \(aussen) außerhalb des Basisordners)" : ""))
            LabeledContent(links == 1 ? "Link" : "Links", value: "\(links)")
            if !planung.zellenfrei.isEmpty {
                LabeledContent("Einzeln unterrichtsfrei",
                               value: planung.zellenfrei.count == 1
                                   ? "1 Zelle" : "\(planung.zellenfrei.count) Zellen")
            }
            LabeledContent("Zuletzt geändert",
                           value: Zeitrechnung.zeitpunktLang(planung.geaendert))
            LabeledContent("Autosicherung") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(speicher.letzteSicherung.map(Zeitrechnung.zeitpunktLang)
                             ?? "wird beim nächsten Speichern angelegt")
                        // Die Grenze ist zu sehen, bevor sie greift.
                        if let groesse = speicher.sicherung.ablagegroesse {
                            Text("\(groesse.formatted(.byteCount(style: .memory))) von "
                                 + "\(Sicherungsdienst.schreibgrenze / 1024 / 1024) MB")
                                .foregroundStyle(.secondary)
                        }
                        if let grund = speicher.sicherung.vorgaengerStoerung {
                            Text("Fassung davor nicht fortgeschrieben: \(grund.ohneSchlusspunkt.satzanfang)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        _ = Systemzugriff.imFinderZeigen(speicher.sicherung.ablage.datei.path,
                                                         zugriff: speicher.zugriff)
                    } label: {
                        Label("Im Finder zeigen", systemImage: Zeichen.ordner)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Ordner der Autosicherung im Finder zeigen")
                }
            }
        }
    }
}

// ── Kurzanleitung ─────────────────────────────────────────────────────────

struct HilfeDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    private let griffe: [(String, String)] = [
        ("Vorhaben anlegen", "„+ Vorhaben“ in einer Zelle oder Doppelklick auf leere Fläche (⌘T)"),
        ("Als durchgeführt kennzeichnen", "Häkchen an der Kachel (erscheint beim Überfahren)"),
        ("Vorhaben anwählen", "Klick — mehrere mit ⌘ oder ⇧ dazu, alle mit ⌘A"),
        ("Vorhaben öffnen", "Doppelklick, oder anwählen und ⏎"),
        ("Kopieren / Einfügen / Löschen", "⌘C / ⌘V / ⌫ — auch über das Rechtsklickmenü"),
        ("Vorhaben verschieben", "Kachel in eine andere Zelle ziehen (mehrere zugleich)"),
        ("Reihenfolge in der Zelle", "Kachel in ihrer Zelle ziehen — ein Strich zeigt, wo sie "
         + "landet; oder ⌥⌘↑ und ⌥⌘↓"),
        ("Unterrichtstage hinterlegen", "⌘K — je Zeile Mo. bis Fr. ankreuzen; der "
         + "Vorhaben-Dialog hebt diese Tage hervor"),
        ("Wochentag und Datum festlegen", "im Vorhaben-Dialog: Ein Wochentag setzt das Datum in "
         + "der gewählten Woche; es steht dann über dem Titel der Kachel. Beides ist "
         + "freiwillig und verfällt beim Verschieben in eine andere Woche"),
        ("Als dringlich kennzeichnen", "im Vorhaben-Dialog oder im Rechtsklickmenü — die Kachel "
         + "bekommt einen gelben Rahmen"),
        ("Als Vorbereitung kennzeichnen", "im Vorhaben-Dialog oder im Rechtsklickmenü; die Kachel "
         + "trägt einen gestrichelten blauen Rahmen und die Zeile „Vorbereitung“. Ein Datum braucht "
         + "sie nicht zwingend."),
        ("Als Korrektur kennzeichnen", "im Vorhaben-Dialog oder im Rechtsklickmenü; die Kachel "
         + "trägt einen gestrichelten roten Rahmen und die Zeile „Korrektur“. Ein Datum braucht "
         + "sie nicht zwingend."),
        ("Ferienzeitraum eintragen", "⌘E"),
        ("Ganze Woche unterrichtsfrei", "Schirmsymbol im Spaltenkopf"),
        ("Einzelne Klasse/Kurs in einer Woche freistellen", "Schirmsymbol in der Zelle"),
        ("Suchen", "⌘F — Escape leert"),
        ("Zur laufenden Woche", "⌘J"),
        ("Heute anstehende Vorhaben", "⌘D — die Liste zum Abhaken für den heutigen Tag"),
        ("Klassen/Kurse und Fächer / Einstellungen", "⌘K / ⌘,"),
        ("Lernende", "⌘L — auch über das Personen-Symbol in der Werkzeugleiste"),
        ("Sichern / Öffnen", "⌘S / ⌘O"),
        ("Spaltenbreite", "Regler in der Werkzeugleiste oder ⌘+ und ⌘−"),
        ("Tour durch die Oberfläche", "Hilfe → Tour durch die Oberfläche — Karten an der "
         + "Werkzeugleiste und an einer Zelle, jederzeit abzubrechen"),
    ]

    var body: some View {
        Dialograhmen(titel: "Kurzanleitung",
                     unterzeile: "Die wichtigsten Handgriffe",
                     breite: 640, hoehe: 620) {
            Section("Bedienung") {
                ForEach(griffe, id: \.0) { griff in
                    LabeledContent(griff.0, value: griff.1)
                }
            }

            Section("Materialien") {
                Text("Materialien werden nie kopiert oder verschoben. Hinterlegt wird ein "
                     + "Verweis — relativ zum Basisordner, sofern die Datei darin liegt, sonst "
                     + "als vollständiger Pfad (an ↗ erkennbar). Ein Klick auf ein Material "
                     + "zeigt es im Finder, der kleine Knopf daneben öffnet die Datei selbst. "
                     + "Ausführbares — Programme, .command-Dateien, Skripte — wird bewusst "
                     + "nicht geöffnet.")
            }

            Section("Zugriff auf Dateien") {
                Text("Die App läuft im App Sandbox von macOS: Von sich aus liest und schreibt "
                     + "sie nur ihre eigenen Dateien. Auf alles andere — Materialien, "
                     + "Kursdateien, den Ordner der Sicherungskopie — darf sie erst zugreifen, "
                     + "wenn es ihr einmal gezeigt wurde: über „Datei wählen …“, „Ordner "
                     + "wählen …“ oder durch Ziehen aus dem Finder. Die Wahl merkt sie sich; "
                     + "ein Ordner gilt für alles darin. Ist die Verschlüsselung eingeschaltet, "
                     + "liegen die gemerkten Orte und der Zielordner der Sicherungskopie "
                     + "versiegelt neben der Planung. Nach einem Update fragt sie einmal "
                     + "nach den Ordnern, die sie bisher benutzt hat.")
            }

            Section("Sicherung") {
                Text("Alle Daten bleiben auf diesem Rechner. Die Planung wird laufend in "
                     + "~/Library/Containers/org.3ducation.Unterrichtsplanung/Data/Library/"
                     + "Application Support/Unterrichtsplanung/planung.json gesichert; "
                     + "die vorige Fassung bleibt daneben liegen. Die verbindliche Sicherung "
                     + "bleibt der Export als JSON-Datei (⌘S).")
                Text("Auf Wunsch legt die App beim Beenden zusätzlich eine Kopie in einem "
                     + "frei gewählten Ordner ab — einzustellen unter „Einstellungen“. Diese "
                     + "Kopie liest die Web App.")
                Text("Dort lassen sich Vorhaben abhaken und kommentieren. Beides legt die "
                     + "Web App als „current_status.json“ neben der Kopie ab; diese App liest "
                     + "die Datei beim Start und 15 Sekunden nach dem Aufwachen des Macs aus dem "
                     + "Ruhezustand ein, jederzeit auch über „Stand der Web App abrufen“ im Menü "
                     + "„Ablage“, und "
                     + "sagt, was sie übernommen hat. "
                     + "Alles Übrige an der Planung bleibt dem Mac vorbehalten.")
                Text("Ins Netz geht die App nur für zwei Dinge, beide nur mit Erlaubnis: "
                     + "um nach Updates zu suchen (höchstens einmal je Woche, oder von Hand über "
                     + "„\(Updates.menuebefehl)“ im Menü „Unterrichtsplanung“) und um auf Klick im "
                     + "Vorhaben-Dialog die Materialliste von 3ducation.org zu laden. Beides lässt "
                     + "sich unter „Einstellungen“ ein- und ausschalten.")
            }
        } fuss: {
            Button("Tour durch die Oberfläche") {
                schliessen()
                speicher.tourStarten()
            }
            .disabled(!speicher.hatPlanung)
            Spacer(minLength: 0)
            Button("Fertig") { schliessen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
