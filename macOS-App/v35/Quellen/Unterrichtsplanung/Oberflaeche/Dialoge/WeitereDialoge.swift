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
        Dialograhmen(titel: "Farbe wählen", unterzeile: unterzeile, hoehe: 460) {
            Section {
                raster
            } footer: {
                Text(hinweis)
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
            Spacer(minLength: 0)
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
    // Keine Mindestbreite: ein zu breites Raster ließe das gruppierte Form seine Einzüge fallen.

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

struct EinstellungenDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @State private var start = Tag.heute
    @State private var wochen = Double(Kennwerte.wochenStandard)
    /// `nil` heißt: kein erster Schultag gesetzt, die Zählung wird hergeleitet.
    @State private var ersterSchultag: Tag?

    private var planung: Planung? { speicher.planung }
    private var anzahl: Int { min(Kennwerte.wochenMax, max(1, Int(wochen.rounded()))) }

    private var ersterSchultagAusserhalb: Bool {
        guard let erster = ersterSchultag else { return false }
        return !erster.liegtImZeitraum(start: start, wochen: anzahl)
    }

    var body: some View {
        Dialograhmen(titel: "Einstellungen",
                     unterzeile: "Zeitraum, Sicherungskopie, Verschlüsselung, Updates und Stand",
                     hoehe: 820) {
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
                if ersterSchultagAusserhalb {
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
                        .frame(minWidth: 160)

                        Wochenzahlfeld(wochen: $wochen)
                    }
                }
            } header: {
                Text("Zeitraum")
            } footer: {
                Text(vorschau)
            }

            sicherungskopie

            verschluesselung

            updates

            if let planung { kennzahlen(planung) }
        } fuss: {
            Spacer(minLength: 0)
            Button("Abbrechen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            Button("Übernehmen") {
                speicher.einstellungenUebernehmen(start: start, wochen: anzahl,
                                                  ersterSchultag: ersterSchultag)
            }
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

    /// Die zusätzliche Kopie beim Beenden.
    @ViewBuilder
    private var sicherungskopie: some View {
        @Bindable var speicher = speicher
        let gewaehlt = !speicher.autoexportOrdner.isEmpty

        Section {
            // Gekoppelt: Einschalten ohne Tresor richtet erst die Verschlüsselung
            // ein — die Kopie gibt es nur verschlüsselt.
            Toggle("Beim Beenden zusätzlich sichern",
                   isOn: Binding(get: { speicher.autoexportAktiv },
                                 set: { speicher.autoexportUmschalten($0) }))

            LabeledContent("Zielordner") {
                HStack(spacing: 8) {
                    Text(gewaehlt ? speicher.autoexportOrdner : "noch keiner gewählt")
                        .foregroundStyle(gewaehlt ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(gewaehlt ? speicher.autoexportOrdner : "")
                    Button("Wählen …") { speicher.autoexportOrdnerWaehlen() }
                }
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
        } header: {
            Text("Sicherungskopie beim Beenden")
        } footer: {
            Text("Schalter und Zielordner wirken sofort — „Abbrechen“ nimmt sie nicht "
                 + "zurück; „Übernehmen“ gilt allein dem Zeitraum oben.")
            Text("Die laufende Autosicherung bleibt davon unberührt — sie ist weiterhin der "
                 + "maßgebliche Stand. Die Kopie wird bei jedem Beenden unter demselben Namen "
                 + "neu geschrieben und ist die Datei, die die Ansichtsfassung fürs iPad liest. "
                 + "Gelesen wird im Zielordner nur die Statusdatei der Ansicht; aufgeräumt "
                 + "wird dort nie.")
            Text("Ein frisch gewählter Ordner wird sofort einmal beschrieben — damit hier und "
                 + "nicht erst beim Beenden feststeht, dass es klappt. Wird er später umbenannt "
                 + "oder verschoben, findet ihn die App wieder und führt den Pfad nach.")
            Text("Die Kopie wird nur verschlüsselt geschrieben: Mit der Wahl des Ordners wird "
                 + "die Verschlüsselung eingerichtet, falls sie noch aus ist.")
        }
    }

    /// Die Prüfung auf Updates: der Schalter, die letzte Prüfung, der Weg von
    /// Hand — und wörtlich, was dabei übertragen wird.
    @ViewBuilder
    private var updates: some View {
        Section {
            Toggle("Beim Öffnen nach Updates suchen",
                   isOn: Binding(get: { speicher.updatesErlaubt },
                                 set: { speicher.updatesErlauben($0) }))

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
        } header: {
            Text("Updates")
        } footer: {
            Text(Updates.datenschutzhinweis)
            Text("Der Schalter wirkt sofort. „Jetzt suchen“ fragt auch bei ausgeschalteter "
                 + "Prüfung — auf diesen Befehl hin, wie „\(Updates.menuebefehl)“ im Menü "
                 + "„Unterrichtsplanung“. Gefunden wird das jüngste Release des Repositorys; "
                 + "geladen und installiert wird nichts von selbst.")
        }
    }

    /// Die Verschlüsselung: Stand, Wicklungen und der Weg zum Dialog.
    @ViewBuilder
    private var verschluesselung: some View {
        Section {
            LabeledContent("Stand") {
                HStack(spacing: 10) {
                    Label(speicher.verschluesselt ? "eingeschaltet" : "ausgeschaltet",
                          systemImage: speicher.verschluesselt ? Zeichen.schloss : Zeichen.schlossOffen)
                    Button(speicher.verschluesselt ? "Verwalten …" : "Einschalten …") {
                        speicher.dialogOeffnen(.verschluesselung)
                    }
                }
            }
            if speicher.verschluesselt {
                LabeledContent("Wicklungen") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(speicher.wicklungen, id: \.art) { wicklung in
                            Text(wicklung.beschriftung)
                        }
                    }
                }
            }
        } header: {
            Text("Verschlüsselung")
        } footer: {
            Text(speicher.verschluesselt
                 ? "Ablage, Sicherungskopie und Export sind mit AES-256 versiegelt. Beim Start "
                   + "entsperrt Touch ID oder das Anmeldepasswort; auf dem iPad öffnet die "
                   + "Passphrase. Der Klartext-Export bleibt als eigener Befehl im Menü „Ablage“."
                 : "Ausgeschaltet liegt die Planung als lesbares JSON auf diesem Mac. FileVault "
                   + "schützt mehr als diese Einstellung — sie ist die Schicht für die Kopie, "
                   + "die den Rechner verlässt, und für Rechner ohne FileVault.")
        }
    }

    @ViewBuilder
    private func kennzahlen(_ planung: Planung) -> some View {
        let materialien = planung.eintraege.reduce(0) { $0 + $1.materialien.count }
        let aussen = planung.basis.isEmpty
            ? 0 : planung.eintraege.reduce(0) { $0 + $1.materialien.count(where: \.istAbsolut) }
        let links = planung.eintraege.reduce(0) { $0 + $1.links.count }

        Section("Stand") {
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
                HStack(spacing: 8) {
                    Text(speicher.letzteSicherung.map(Zeitrechnung.zeitpunktLang)
                         ?? "wird beim nächsten Speichern angelegt")
                    Button {
                        _ = Systemzugriff.imFinderZeigen(Ablage.shared.datei.path)
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
        ("Wochentag und Datum festlegen", "im Vorhaben-Dialog: ein Wochentag setzt das Datum in "
         + "der gewählten Woche; es steht dann über dem Titel der Kachel. Beides ist "
         + "freiwillig und verfällt beim Verschieben in eine andere Woche"),
        ("Als dringlich kennzeichnen", "im Vorhaben-Dialog oder im Rechtsklickmenü — die Kachel "
         + "bekommt einen gelben Rahmen"),
        ("Ferienzeitraum eintragen", "⌘E"),
        ("Ganze Woche unterrichtsfrei", "Schirmsymbol im Spaltenkopf"),
        ("Einzelne Klasse/Kurs in einer Woche freistellen", "Schirmsymbol in der Zelle"),
        ("Suchen", "⌘F — Escape leert"),
        ("Zur laufenden Woche", "⌘J"),
        ("Heute anstehende Vorhaben", "⌘D — die Liste zum Abhaken für den heutigen Tag"),
        ("Klassen/Kurse und Fächer / Einstellungen", "⌘K / ⌘,"),
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

            Section("Sicherung") {
                Text("Alle Daten bleiben auf diesem Rechner. Die Planung wird laufend in "
                     + "~/Library/Application Support/Unterrichtsplanung/planung.json gesichert; "
                     + "die vorige Fassung bleibt daneben liegen. Die verbindliche Sicherung "
                     + "bleibt der Export als JSON-Datei (⌘S).")
                Text("Auf Wunsch legt die App beim Beenden zusätzlich eine Kopie in einem "
                     + "frei gewählten Ordner ab — einzustellen unter „Einstellungen“. Diese "
                     + "Kopie liest die Ansichtsfassung fürs iPad.")
                Text("Dort lassen sich Vorhaben abhaken und kommentieren. Beides legt die "
                     + "Ansicht als „current_status.json“ neben der Kopie ab; diese App liest "
                     + "die Datei beim nächsten Start ein und sagt, was sie übernommen hat. "
                     + "Alles Übrige an der Planung bleibt dem Mac vorbehalten.")
                Text("Ins Netz geht die App nur, um nach Updates zu suchen — und das nur, "
                     + "wenn es bei der Ersteinrichtung oder unter „Einstellungen → Updates“ "
                     + "erlaubt wurde, höchstens einmal je Woche; oder von Hand über "
                     + "„\(Updates.menuebefehl)“ im Menü „Unterrichtsplanung“.")
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
