// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Alle Prüfungen auf einen Blick — chronologisch, kursübergreifend.
struct PruefungsDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen
    @FocusState private var fokus: String?

    private var planung: Planung? { speicher.planung }

    var body: some View {
        let liste = speicher.pruefungsliste
        // Einmal je Liste statt je Zeile: für den Zeilen-Body zu teuer.
        let stand = planung?.wochenstand() ?? .leer
        // Höchstens 700 hoch (E1151; bis 2.7.1 760 — bei 1440 × 900 mit großem Dock reichte eine lange Liste unter das
        // Dock); die Liste rollt. 744 breit wie jedes Blatt mit gruppiertem `Form` (E1156; bis 2.7.1 860).
        Dialograhmen(titel: "Prüfungen", unterzeile: unterzeile(liste),
                     breite: Formblatt.breite, hoehe: 700) {
            if liste.isEmpty {
                Section {
                    Text("Noch keine Prüfung gekennzeichnet.")
                        .foregroundStyle(.secondary)
                    // Nach dem Leertext, im Kasten (E1122).
                    Erlaeuterung("Ein Vorhaben wird zur Prüfung über einen Doppelklick auf die Kachel "
                                 + "und den Schalter „Als Prüfung führen“ — oder mit einem Rechtsklick "
                                 + "auf die Kachel. Prüfungen tragen im Raster einen roten Rahmen und "
                                 + "über dem Titel ihren Termin.")
                }
            } else {
                Section {
                    Pruefungsspaltenkopf()
                    ForEach(gruppen(liste), id: \.titel) { gruppe in
                        Text(gruppe.titel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(gruppe.eintraege, id: \.vorhaben.id) { eintrag in
                            let woche = stand.woche(eintrag.vorhaben.woche)
                            Pruefungszeile(vorhaben: eintrag.vorhaben, klasse: eintrag.klasse,
                                           planung: planung, woche: woche,
                                           schulwoche: woche.flatMap { stand.schulwoche($0) })
                        }
                    }
                    // Gilt allen Zeilen: als letzte Zeile im Kasten (E1122).
                    Erlaeuterung("Ein Klick auf eine Zeile springt im Raster zu dem Vorhaben. Liegt ein "
                                 + "Termin außerhalb der Woche, in der das Vorhaben steht, ist er "
                                 + "gekennzeichnet — das ist erlaubt (etwa beim Nachschreiben), aber "
                                 + "meist ein Vertippen.")
                } header: {
                    Text("Termine")
                }
            }
            sperrbereich
        } fuss: {
            Spacer(minLength: 0)
            Button("Fertig") { schliessen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Zeiträume, in denen keine Prüfung liegen darf.
    @ViewBuilder
    private var sperrbereich: some View {
        let sperren = planung?.sperrzeiten ?? []
        Section {
            if sperren.isEmpty {
                Text("Kein Zeitraum gesperrt.").foregroundStyle(.secondary)
            } else {
                Sperrspaltenkopf()
                ForEach(sperren) { zeitraum in
                    Sperrposten(zeitraum: zeitraum, fokus: $fokus)
                }
            }
            Button {
                if let neu = speicher.sperrzeitHinzufuegen() { fokus = neu }
            } label: {
                Label("Sperrzeitraum hinzufügen", systemImage: Zeichen.plus)
            }
            // Gilt allen Zeilen: als letzte Zeile im Kasten, die Absätze bleiben (E1122).
            Erlaeuterung("In einem Sperrzeitraum lässt sich kein Prüfungstermin eintragen — der "
                         + "Versuch wird mit Hinweis abgewiesen. Gedacht ist das für Zeiten, in "
                         + "denen zwar unterrichtet, aber nicht geprüft werden darf. "
                         + "Ferien brauchen keine Sperre — dort steht ohnehin nichts.\n\n"
                         + "„Gilt für“ sagt, wen die Sperre bindet: alle Klassen und Kurse oder "
                         + "ausgewählte. Für alle heißt auch für die, die erst später angelegt "
                         + "werden. Wird die letzte ausgewählte Zeile wieder abgewählt, gilt die "
                         + "Sperre daher erneut für alle — eine Sperre ohne Bezug gibt es nicht.\n\n"
                         + "Wird ein Zeitraum nachträglich über bereits eingetragene Termine "
                         + "gelegt, bleiben diese stehen und werden oben gekennzeichnet; was "
                         + "einmal geplant war, verschwindet nicht von selbst.")
        } header: {
            Text("Sperrzeiträume")
        }
    }

    private func unterzeile(_ liste: [(vorhaben: Vorhaben, klasse: Klasse)]) -> String {
        guard !liste.isEmpty else { return "keine Prüfung gekennzeichnet" }
        let ohneTermin = liste.count { $0.vorhaben.pruefungstag == nil }
        let offen = liste.count { !$0.vorhaben.erledigt }
        var text = liste.count == 1 ? "1 Prüfung" : "\(liste.count) Prüfungen"
        text += " · \(offen) noch offen"
        if ohneTermin > 0 { text += " · \(ohneTermin) ohne Termin" }
        return text
    }

    /// Nach Monat gruppiert, „Ohne Termin“ als eigene Gruppe am Ende.
    private func gruppen(_ liste: [(vorhaben: Vorhaben, klasse: Klasse)])
        -> [(titel: String, eintraege: [(vorhaben: Vorhaben, klasse: Klasse)])] {
        var reihenfolge: [String] = []
        var nachTitel: [String: [(vorhaben: Vorhaben, klasse: Klasse)]] = [:]
        for eintrag in liste {
            let titel = eintrag.vorhaben.pruefungstag.map(Zeitrechnung.monatUndJahr) ?? "Ohne Termin"
            if nachTitel[titel] == nil { reihenfolge.append(titel) }
            nachTitel[titel, default: []].append(eintrag)
        }
        return reihenfolge.map { ($0, nachTitel[$0] ?? []) }
    }
}

// ── Maße ──────────────────────────────────────────────────────────────────

// Beide Tabellen füllen ihren Kasten von selbst: Das Blatt ist so breit, wie das gruppierte `Form` seine Kästen ausfüllt
// (`Formblatt.breite`, E1156) — eine Zeile hat 684 pt Platz, die Sperrzeile belegt sie ganz. Bis 2.7.1 waren die Zeilen
// überbreit (798 pt in einem Blatt von 860); die Kästen wuchsen mit, die Trennlinien nicht.

private enum Pruefungsspalten {
    static let datum: CGFloat = 104
    static let kurs: CGFloat = 150
    /// Breit genug für „KW 41 / 12. Schulwoche" — die Spalte trägt
    /// dieselbe Beschriftung wie Rasterkopf und Ansichtsfassung.
    static let woche: CGFloat = 150
    static let abstand: CGFloat = 10
}

private struct Pruefungsspaltenkopf: View {
    var body: some View {
        HStack(spacing: Pruefungsspalten.abstand) {
            Spaltenkopf(titel: "Termin").frame(width: Pruefungsspalten.datum, alignment: .leading)
            Spaltenkopf(titel: "Klasse/Kurs").frame(width: Pruefungsspalten.kurs, alignment: .leading)
            Spaltenkopf(titel: "Vorhaben").frame(maxWidth: .infinity, alignment: .leading)
            Spaltenkopf(titel: "Woche").frame(width: Pruefungsspalten.woche, alignment: .leading)
        }
        // Derselbe Einzug wie in den Zeilen; sonst steht die Überschrift um 6 Punkte versetzt.
        .padding(.horizontal, 6)
    }
}

// ── Eine Zeile ────────────────────────────────────────────────────────────

private struct Pruefungszeile: View {
    let vorhaben: Vorhaben
    let klasse: Klasse
    let planung: Planung?
    let woche: Woche?
    let schulwoche: Int?

    @Environment(Planungsspeicher.self) private var speicher
    @State private var ueberfahren = false

    private var ausserhalb: Bool {
        guard let planung else { return false }
        return vorhaben.terminAusserhalb(start: planung.start)
    }

    /// Möglich, wenn die Sperre erst nachträglich darübergelegt wurde.
    private var gesperrt: Sperrzeitraum? {
        guard let planung, let tag = vorhaben.pruefungstag else { return nil }
        return planung.sperre(am: tag, fuer: vorhaben.klasseId)
    }

    var body: some View {
        Button {
            speicher.zeigeVorhaben(vorhaben.id)
        } label: {
            HStack(spacing: Pruefungsspalten.abstand) {
                termin
                    .frame(width: Pruefungsspalten.datum, alignment: .leading)

                HStack(spacing: 6) {
                    Farbpunkt(ton: Farbwelt.ton(klasse.farbe), groesse: 8)
                    Text(klasse.beschriftung).lineLimit(1).truncationMode(.tail)
                }
                .frame(width: Pruefungsspalten.kurs, alignment: .leading)

                HStack(spacing: 6) {
                    Text(vorhaben.anzeigeTitel)
                        .strikethrough(vorhaben.erledigt, color: .secondary)
                        .foregroundStyle(vorhaben.erledigt ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if vorhaben.erledigt {
                        Image(systemName: Zeichen.haken)
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .help("bereits durchgeführt")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(wochentext)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: Pruefungsspalten.woche, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(.rect(cornerRadius: 6))
            .background(ueberfahren ? Systemfarben.verweiszeile : .clear,
                        in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { ueberfahren = $0 }
        .help("Im Raster zeigen")
        .accessibilityLabel(bedienungshilfentext)
    }

    @ViewBuilder
    private var termin: some View {
        if let tag = vorhaben.pruefungstag {
            HStack(spacing: 5) {
                Text(tag.mitWochentag).monospacedDigit()
                if let gesperrt {
                    Image(systemName: Zeichen.warnung)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .help(gesperrt.abweisung)
                } else if ausserhalb {
                    Image(systemName: Zeichen.warnung)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("Der Termin liegt außerhalb der Woche, in der das Vorhaben steht.")
                }
            }
            .foregroundStyle(Systemfarben.pruefung)
        } else {
            Text("ohne Termin").foregroundStyle(.secondary)
        }
    }

    private var wochentext: String {
        woche.map { $0.beschriftung(schulwoche: schulwoche) } ?? ""
    }

    private var bedienungshilfentext: String {
        var text = vorhaben.pruefungstag.map { "Prüfung am " + $0.deutsch } ?? "Prüfung ohne Termin"
        text += ", \(klasse.beschriftung), \(vorhaben.anzeigeTitel)"
        if vorhaben.erledigt { text += ", durchgeführt" }
        if gesperrt != nil { text += ", Termin liegt in einem Sperrzeitraum" }
        else if ausserhalb { text += ", Termin außerhalb der geplanten Woche" }
        return text + " — im Raster zeigen"
    }
}


// ── Sperrzeiträume ────────────────────────────────────────────────────────

enum Sperrspalten {
    // In 684 pt (E1156): 152 + 2 · 126 + 160 + 48 + 24 + 6 · 8 — bis 2.7.1 160, 168, 96 und Abstand 10 (760 pt).
    static let name: CGFloat = 152
    static let datum: CGFloat = 126
    static let kurse: CGFloat = 160
    /// Feste Breite: Ohne sie stand „5 Tage“ senkrecht, ein Buchstabe je Zeile.
    static let dauer: CGFloat = 48
    /// Fest gemessen, damit die Summe der Spalten aufgeht.
    static let papierkorb: CGFloat = 24
    static let abstand: CGFloat = 8
    /// Die ganze Zeile: sieben Glieder samt Spacer, sechs Abstände — höchstens `Formblatt.zeile` (R-BG8c-02); die Prüfung
    /// misst die Zeile selbst dagegen (R-BG8cn-01).
    static let zeile: CGFloat = name + 2 * datum + kurse + dauer + papierkorb + 6 * abstand
    /// Steht in der Dauer-Spalte, wenn das Ende vor dem Beginn liegt — in zwei Zeilen (R-BG8c-01, `Sperrdauer`).
    static let warnung = "Ende vor Beginn"
}

private struct Sperrspaltenkopf: View {
    var body: some View {
        HStack(spacing: Sperrspalten.abstand) {
            Spaltenkopf(titel: "Bezeichnung").frame(width: Sperrspalten.name, alignment: .leading)
            Spaltenkopf(titel: "Von").frame(width: Sperrspalten.datum, alignment: .leading)
            Spaltenkopf(titel: "Bis").frame(width: Sperrspalten.datum, alignment: .leading)
            Spaltenkopf(titel: "Gilt für").frame(width: Sperrspalten.kurse, alignment: .leading)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

struct Sperrposten: View {
    let zeitraum: Sperrzeitraum
    @FocusState.Binding var fokus: String?

    @Environment(Planungsspeicher.self) private var speicher
    @State private var name = ""
    @State private var entpreller = Entpreller()

    var body: some View {
        HStack(spacing: Sperrspalten.abstand) {
            Tabellenfeld(hinweis: "Bezeichnung", text: $name,
                         beimVerlassen: bezeichnungAbschliessen)
                .focused($fokus, equals: zeitraum.id)
                .frame(width: Sperrspalten.name)
                .accessibilityLabel("Bezeichnung des Sperrzeitraums")
                .onChange(of: name) { _, neu in
                    entpreller.nach(300) { speicher.sperrzeitNamenSetzen(id: zeitraum.id, name: neu) }
                }

            // Wie im Ferien-Dialog: Das andere Datum zieht mit (siehe `Zeitspanne`).
            // Eine Sperre, die nichts sperrt, wäre hier die teurere Falle — sie
            // soll Prüfungstermine verhindern.
            Datumsfeld(tag: Binding(
                get: { zeitraum.von },
                set: { speicher.sperrzeitAendern(zeitraum.mitBeginn($0)) }))
                .frame(width: Sperrspalten.datum)
                .accessibilityLabel("Beginn der Sperre")

            Datumsfeld(tag: Binding(
                get: { zeitraum.bis },
                set: { speicher.sperrzeitAendern(zeitraum.mitEnde($0)) }))
                .frame(width: Sperrspalten.datum)
                .accessibilityLabel("Ende der Sperre")

            Kurszuweisung(zeitraum: zeitraum)
                .frame(width: Sperrspalten.kurse)

            Spacer(minLength: 0)

            Sperrdauer(ungueltig: zeitraum.ungueltig, tage: zeitraum.von.tageBis(zeitraum.bis) + 1)
                .frame(width: Sperrspalten.dauer, alignment: .trailing)

            Papierkorbknopf(hilfe: "Sperrzeitraum entfernen",
                            kennzeichnung: "Sperrzeitraum \(zeitraum.name) entfernen") {
                speicher.sperrzeitEntfernen(zeitraum.id)
            }
            .frame(width: Sperrspalten.papierkorb, alignment: .trailing)
        }
        .onAppear { name = zeitraum.name }
        .onChange(of: zeitraum.name) { _, neu in if neu != name { name = neu } }
    }

    /// Beim Verlassen des Feldes beschneiden und, wenn nichts übrig bleibt, auf
    /// denselben Ersatz setzen, den der Dateileser vergäbe — sonst hieße der
    /// Zeitraum in der Anzeige anders als nach dem nächsten Start.
    private func bezeichnungAbschliessen() {
        let sauber = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = sauber.isEmpty ? "Sperrzeitraum" : sauber
        entpreller.abbrechen()
        speicher.sperrzeitNamenSetzen(id: zeitraum.id, name: name)
    }
}

/// Die Dauer-Spalte einer Sperrzeile — eine eigene View, damit die Prüfung genau sie misst (R-BG8cn2-01): die Dauer
/// einzeilig, „Ende vor Beginn“ in zwei Zeilen (R-BG8c-01). Eine vertippte Spanne über 999 Tage (das Modell nimmt Jahre
/// von 1900 bis 2999) verkleinert sich, statt abgeschnitten zu werden (R-BG8cn2-02).
struct Sperrdauer: View {
    let ungueltig: Bool
    let tage: Int
    /// Zeilen des Warntexts; `nil` nur für die Prüfung, die ihn ohne Grenze gegen zwei Zeilen misst.
    var warnzeilen: Int? = 2

    /// So weit verkleinert sich die Dauer höchstens — genug für sechs Ziffern in der Spalte.
    static let kleinsterMassstab: CGFloat = 0.7

    var body: some View {
        Group {
            if ungueltig {
                Text(Sperrspalten.warnung).foregroundStyle(.red)
                    .lineLimit(warnzeilen)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(Self.text(tage: tage)).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(Self.kleinsterMassstab)
            }
        }
        .font(.caption)
    }

    static func text(tage: Int) -> String { tage == 1 ? "1 Tag" : "\(tage) Tage" }
}

/// Für welche Klassen und Kurse eine Sperre gilt.
///
/// „Alle Klassen/Kurse“ ist etwas anderes als „jede Zeile einzeln angekreuzt“: Es meint
/// auch die, die erst später dazukommen.
private struct Kurszuweisung: View {
    let zeitraum: Sperrzeitraum

    @Environment(Planungsspeicher.self) private var speicher

    private var klassen: [Klasse] { speicher.planung?.klassen ?? [] }
    private var gewaehlt: Set<String> { Set(zeitraum.kurse) }

    var body: some View {
        Menu {
            if !klassen.isEmpty {
                Toggle("Alle Klassen/Kurse", isOn: Binding(
                    get: { zeitraum.giltFuerAlle },
                    set: { alle in setzen(alle ? [] : Set(klassen.map(\.id))) }))
                Divider()
            }
            ForEach(klassen) { klasse in
                Toggle(klasse.beschriftung, isOn: Binding(
                    get: { gewaehlt.contains(klasse.id) },
                    set: { an in
                        var neu = gewaehlt
                        if an { neu.insert(klasse.id) } else { neu.remove(klasse.id) }
                        setzen(neu)
                    }))
            }
        } label: {
            Text(beschriftung).lineLimit(1).truncationMode(.tail)
        }
        .help(hilfe)
        .accessibilityLabel("Gilt für")
        .accessibilityValue(hilfe)
    }

    /// Kein Farbpunkt: Der Knopf eines Aufklappmenüs nimmt nur Text auf.
    private var beschriftung: String {
        if zeitraum.giltFuerAlle { return "Alle Klassen/Kurse" }
        if zeitraum.kurse.count == 1,
           let einziger = klassen.first(where: { $0.id == zeitraum.kurse[0] }) {
            return einziger.beschriftung
        }
        return "\(zeitraum.kurse.count) Klassen/Kurse"
    }

    private var hilfe: String {
        guard !zeitraum.giltFuerAlle else {
            return "Die Sperre gilt für alle Klassen und Kurse — auch für später angelegte."
        }
        let namen = zeitraum.kurse.compactMap { kennung in
            klassen.first { $0.id == kennung }?.beschriftung
        }
        return "Die Sperre gilt für: " + namen.joined(separator: ", ")
    }

    private func setzen(_ kurse: Set<String>) {
        speicher.sperrzeitKurseSetzen(id: zeitraum.id, kurse: kurse)
    }
}
