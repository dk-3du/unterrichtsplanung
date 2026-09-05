// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Klassen, Kurse und Fächer verwalten. Eine Klasse („G6a“) und ein Kurs
/// („WPU Informatik“) stehen in derselben Liste, weil beides eine Zeile im
/// Raster bekommt; Pflicht ist allein die Bezeichnung. Das Fach ist freiwillig
/// und ordnet zu: Alle Zeilen desselben Fachs tragen dieselbe Farbe. Dazu
/// trägt jede Zeile ihre **Unterrichtstage** (Mo.–Fr. als Kästchen).
struct KlassenDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @FocusState private var fokus: String?

    private var planung: Planung? { speicher.planung }

    var body: some View {
        // Breiter als die übrigen Dialoge — mit Maß: Das gruppierte `Form`
        // deckelt seinen Inhalt auf rund 700 Punkt und zentriert ihn; jenseits
        // von etwa 740 Punkt Fensterbreite kommt nur noch Rand dazu (nachgemessen
        // an 880 und 900: der Abschnitt bleibt 700 breit). Platz für die fünf
        // Kästchen schafft deshalb nicht das Fenster, sondern die Zeile selbst.
        Dialograhmen(titel: "Klassen/Kurse und Fächer",
                     unterzeile: "\(planung?.klassen.count ?? 0) von \(Kennwerte.maxKlassen)",
                     breite: Kursspalten.dialogbreite, hoehe: 700) {
            if let planung {
                Section {
                    if planung.klassen.isEmpty {
                        Text("Noch keine Klasse und kein Kurs angelegt.")
                            .foregroundStyle(.secondary)
                    } else {
                        Kursspaltenkopf()
                        ForEach(Array(planung.klassen.enumerated()), id: \.element.id) { stelle, klasse in
                            Kursposten(klasse: klasse, stelle: stelle,
                                       anzahl: planung.klassen.count, fokus: $fokus)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            if let neu = speicher.klasseHinzufuegen() { fokus = neu }
                        } label: {
                            Label("Klasse/Kurs hinzufügen", systemImage: Zeichen.plus)
                        }
                        .disabled(planung.klassen.count >= Kennwerte.maxKlassen)

                        Button { speicher.standardkurseErgaenzen() } label: {
                            Label("Standardliste ergänzen", systemImage: Zeichen.klassen)
                        }
                    }
                } header: {
                    Text("Klassen/Kurse")
                } footer: {
                    Text("Verbindlich ist die Bezeichnung der Klasse oder des Kurses; das Fach "
                         + "ist freiwillig. Der Farbpunkt an einer Zeile öffnet die Farbwahl für "
                         + "genau diese Zeile; eine dort gesetzte Farbe bleibt unangetastet. Die "
                         + "Reihenfolge der Zeilen bestimmt die Reihenfolge im Raster. Die "
                         + "Unterrichtstage sagen, an welchen Wochentagen laut Stundenplan "
                         + "regelmäßig Unterricht stattfindet; der Vorhaben-Dialog hebt sie "
                         + "hervor. Eine Änderung hier rührt bestehende Vorhaben nicht an.")
                }

                Section {
                    Fachfarbenliste(planung: planung)
                } header: {
                    Text("Fachfarben")
                } footer: {
                    Text("Jedes eingetragene Fach bekommt eine der 24 Farben — die erste, die in "
                         + "dieser Planung noch nicht vorkommt. Hier lässt sie sich ändern; sie "
                         + "gilt dann für alle Klassen und Kurse dieses Fachs. „Fachfarbe "
                         + "festlegen“ nimmt ein Fach vorab auf, auch ohne Klasse und Kurs.")
                }
            }
        } fuss: {
            Spacer(minLength: 0)
            Button("Fertig") { schliessen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        // Ein Fenster trägt nur ein Blatt: an der Hauptansicht angemeldet käme keins zum Vorschein.
        .sheet(item: Binding(get: { speicher.farbwahlFuer },
                             set: { speicher.farbwahlFuer = $0 })) { ziel in
            FarbwahlDialog(ziel: ziel)
        }
        .rueckfrage(speicher, ort: .klassen)
        .onDisappear { bezeichnungenSichern() }
    }

    /// Eine Zeile ohne Bezeichnung bliebe im Ausdruck leer und bekäme beim
    /// nächsten Laden einen Namen, den niemand vergeben hat; ein Fach aus
    /// lauter Leerzeichen ergäbe die Beschriftung „7a · “ und einen
    /// Fachschlüssel, der auf nichts zeigt. Die Felder selbst holen das beim
    /// Verlassen nach — hier für die Zeile, die nie angetippt wurde.
    private func bezeichnungenSichern() {
        Entpreller.allesUebernehmen()
        for klasse in speicher.planung?.klassen ?? [] {
            let gestutzt = klasse.name.trimmingCharacters(in: .whitespaces)
            let name = gestutzt.isEmpty ? "Ohne Bezeichnung" : gestutzt
            let fach = klasse.fach.trimmingCharacters(in: .whitespaces)
            guard name != klasse.name || fach != klasse.fach else { continue }
            speicher.klasseAendern(id: klasse.id, name: name, fach: fach)
        }
    }
}

/// Kopf und Zeilen richten sich nach denselben Werten.
private enum Kursspalten {
    static let punkt: CGFloat = 18
    /// Schmal, weil „Klasse/Kurs“ kurz ist („G6a“, „AG“) und
    /// das Fach braucht den Platz.
    static let name: CGFloat = 112
    static let abstand: CGFloat = 10
    /// Fünf randlose Symbolknöpfe samt Zwischenraum — jeder auf `knopf`
    /// gesetzt, sonst stünden die Kästchen der Zeile neben den Kürzeln des
    /// Kopfes (die Pfeil- und Papierkorbknöpfe sind von sich aus schmaler).
    static let knopf: CGFloat = 22
    static let knoepfe: CGFloat = 5 * knopf + 4 * abstand
    /// Fünf Kästchen Montag bis Freitag — **beschriftet im Spaltenkopf**, nicht
    /// am Kästchen: Mit Beschriftung je Kästchen maß die Gruppe 224 Punkt und
    /// ließe dem Fachfeld nur 124 statt 334; als Matrix mit den Kürzeln
    /// darüber misst sie 126, und das Fachfeld behält zwei Drittel — die
    /// Untergrenze. Feste Spalte, damit Kopf und
    /// Zeilen bündig stehen.
    static let tagabstand: CGFloat = 4
    static let tagbreite: CGFloat = 22
    static let tage: CGFloat = 5 * tagbreite + 4 * tagabstand
    /// 720 wie alle Dialoge, dazu ein wenig Luft — mehr bringt wegen des Deckels
    /// des gruppierten `Form` (siehe `KlassenDialog.body`) nichts.
    static let dialogbreite: CGFloat = 800
}

/// Der Farbpunkt, der die Farbwahl öffnet — an einer Zeile wie an einem Fach.
private struct Farbwahlknopf: View {
    let ton: Farbton
    let ziel: Farbwahlziel
    let hinweis: String
    let beschriftung: String

    @Environment(Planungsspeicher.self) private var speicher

    var body: some View {
        Button { speicher.farbwahlFuer = ziel } label: {
            Circle()
                .fill(Kursfarben.farbe(ton))
                .frame(width: Kursspalten.punkt, height: Kursspalten.punkt)
        }
        .buttonStyle(.borderless)
        .help(hinweis)
        .accessibilityLabel(beschriftung)
    }
}

private struct Kursdateimenue: View {
    let klasse: Klasse
    let art: Kursdateiart

    @Environment(Planungsspeicher.self) private var speicher

    private var gesetzt: Bool { klasse.hat(art) }
    private var pfad: String { klasse.pfad(art) }

    var body: some View {
        Menu {
            if gesetzt {
                Button("Öffnen") { speicher.dateiOeffnen(pfad) }
                Button("Im Finder zeigen") { speicher.imFinderZeigen(pfad) }
                Button("Vollständigen Pfad kopieren") { speicher.pfadKopieren(pfad) }
                Divider()
                Button("Andere Datei wählen …") {
                    speicher.kursdateiWaehlen(klasse: klasse.id, art: art)
                }
                Button("Verweis entfernen", role: .destructive) {
                    speicher.kursdateiSetzen(klasse: klasse.id, art: art, pfad: nil)
                }
            } else {
                Button("Datei wählen …") {
                    speicher.kursdateiWaehlen(klasse: klasse.id, art: art)
                }
            }
        } label: {
            Image(systemName: gesetzt ? art.symbolGesetzt : art.symbol)
                .foregroundStyle(gesetzt ? Color.accentColor : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Kursspalten.knopf)
        .help(gesetzt ? art.beschriftung + ": " + speicher.vollerPfad(pfad)
                      : art.dateibeschriftung + " zuweisen")
        .accessibilityLabel(gesetzt ? "\(art.beschriftung) von \(klasse.name)"
                                    : "\(art.dateibeschriftung) für \(klasse.name) zuweisen")
    }
}

private struct Kursspaltenkopf: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: Kursspalten.abstand) {
            Color.clear.frame(width: Kursspalten.punkt, height: 1)
            Spaltenkopf(titel: "Klasse/Kurs").frame(width: Kursspalten.name, alignment: .leading)
            Spaltenkopf(titel: "Fach (optional)").frame(maxWidth: .infinity, alignment: .leading)
            // Zwei Zeilen: der Name der Spalte, darunter die Kürzel über den
            // Kästchen — die Kästchen selbst tragen keine Beschriftung.
            VStack(spacing: 2) {
                Text("Unterrichtstage").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: Kursspalten.tagabstand) {
                    ForEach(Wochentag.allCases) { tag in
                        Text(tag.kurz).font(.caption).foregroundStyle(.secondary)
                            .frame(width: Kursspalten.tagbreite)
                    }
                }
            }
            .frame(width: Kursspalten.tage)
            Color.clear.frame(width: Kursspalten.knoepfe, height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Die fünf Kästchen einer Zeile, beschriftet über den Spaltenkopf; für die
/// Bedienungshilfen trägt jedes seinen Wochentag. Jeder Klick schreibt sofort
/// — es gibt nichts zu entprellen, und ein Klick, der nichts ändert, schreibt
/// nichts.
private struct Unterrichtstagewahl: View {
    let klasse: Klasse

    @Environment(Planungsspeicher.self) private var speicher

    var body: some View {
        HStack(spacing: Kursspalten.tagabstand) {
            ForEach(Wochentag.allCases) { tag in
                Toggle(tag.lang, isOn: Binding(
                    get: { klasse.unterrichtstage.contains(tag) },
                    set: { an in speicher.unterrichtstagSetzen(klasse: klasse.id, tag: tag, an: an) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Kursspalten.tagbreite)
                .help("\(tag.lang): regelmäßig Unterricht in \(klasse.name)")
                .accessibilityLabel("\(tag.lang), Unterrichtstag von \(klasse.name)")
            }
        }
        .frame(width: Kursspalten.tage, alignment: .leading)
    }
}

private struct Kursposten: View {
    let klasse: Klasse
    let stelle: Int
    let anzahl: Int
    @FocusState.Binding var fokus: String?

    @Environment(Planungsspeicher.self) private var speicher

    @State private var name = ""
    @State private var fach = ""
    // Je Feld ein eigener Entpreller: ein gemeinsamer verwürfe den wartenden Schreibvorgang des anderen.
    @State private var namensentpreller = Entpreller()
    @State private var fachentpreller = Entpreller()

    private func vollerPfad(_ pfad: String) -> String {
        speicher.vollerPfad(pfad)
    }

    /// Der Stand im Speicher statt der Kopie aus dem Aufbau der Ansicht: Ein
    /// entprellter Schreibvorgang fragt erst, wenn er an der Reihe ist.
    private var stand: Klasse? {
        speicher.planung?.klassen.first { $0.id == klasse.id }
    }

    /// Nur bei echter Abweichung: Sonst löste schon das Befüllen der Felder
    /// beim Erscheinen je Zeile einen Schreibvorgang aus, der die
    /// Vorgängerfassung durch eine gleichlautende Kopie verdrängte.
    private func namenSchreiben(_ neu: String) {
        guard let stand, stand.name != neu else { return }
        speicher.klasseAendern(id: klasse.id, name: neu)
    }

    private func fachSchreiben(_ neu: String) {
        guard let stand, stand.fach != neu else { return }
        speicher.klasseAendern(id: klasse.id, fach: neu)
    }

    /// Beim Verlassen festschreiben: Eine Zeile ohne Bezeichnung bliebe im
    /// Ausdruck leer und trüge nach dem nächsten Laden einen Namen, den
    /// niemand vergeben hat.
    private func namenAbschliessen() {
        namensentpreller.abbrechen()
        let sauber = name.trimmingCharacters(in: .whitespaces)
        name = sauber.isEmpty ? "Ohne Bezeichnung" : sauber
        namenSchreiben(name)
    }

    /// Ebenso das Fach: Aus lauter Leerzeichen entstünde ein Fachschlüssel,
    /// der auf nichts zeigt — die Zeile bliebe ohne Fachfarbe und trüge doch
    /// die Beschriftung „7a · “.
    private func fachAbschliessen() {
        fachentpreller.abbrechen()
        fach = fach.trimmingCharacters(in: .whitespaces)
        fachSchreiben(fach)
    }

    var body: some View {
        let ton = Farbwelt.ton(klasse.farbe)
        HStack(spacing: Kursspalten.abstand) {
            Farbwahlknopf(
                ton: ton, ziel: .kurs(klasse.id),
                hinweis: "Farbe: " + ton.name
                    + (klasse.farbeManuell ? " · von Hand gesetzt" : ""),
                beschriftung: "Farbe von \(klasse.name) ändern")

            Tabellenfeld(hinweis: "Klasse/Kurs", text: $name,
                         beimVerlassen: namenAbschliessen)
                .frame(width: Kursspalten.name)
                .focused($fokus, equals: klasse.id)
                .accessibilityLabel("Bezeichnung der Klasse bzw. des Kurses")
                .onChange(of: name) { _, neu in
                    namensentpreller.nach(300) { namenSchreiben(neu) }
                }
            Tabellenfeld(hinweis: "Fach (optional)", text: $fach,
                         beimVerlassen: fachAbschliessen)
                .accessibilityLabel("Fach von \(klasse.name)")
                .onChange(of: fach) { _, neu in
                    fachentpreller.nach(300) { fachSchreiben(neu) }
                }

            Unterrichtstagewahl(klasse: klasse)

            ForEach(Kursdateiart.allCases) { art in
                Kursdateimenue(klasse: klasse, art: art)
            }

            Button { speicher.klassenTauschen(stelle, stelle - 1) } label: {
                Image(systemName: Zeichen.hoch)
            }
            .buttonStyle(.borderless)
            .frame(width: Kursspalten.knopf)
            .disabled(stelle == 0)
            .help("Nach oben")

            Button { speicher.klassenTauschen(stelle, stelle + 1) } label: {
                Image(systemName: Zeichen.runter)
            }
            .buttonStyle(.borderless)
            .frame(width: Kursspalten.knopf)
            .disabled(stelle == anzahl - 1)
            .help("Nach unten")

            Button(role: .destructive) { speicher.klasseEntfernen(klasse) } label: {
                Image(systemName: Zeichen.muell)
            }
            .buttonStyle(.borderless)
            .frame(width: Kursspalten.knopf)
            .help("Klasse bzw. Kurs entfernen")
        }
        .onAppear { name = klasse.name; fach = klasse.fach }
        .onChange(of: klasse.name) { _, neu in if neu != name { name = neu } }
        .onChange(of: klasse.fach) { _, neu in if neu != fach { fach = neu } }
    }
}

/// Jedes vorkommende Fach einmal — samt derer, die vorab aufgenommen wurden.
private struct Fachfarbenliste: View {
    let planung: Planung
    @Environment(Planungsspeicher.self) private var speicher

    /// Ein Fach ohne Zeile steht nur als kleingeschriebener Schlüssel in
    /// `fachfarben`; seine geschriebene Form hält der Dialog, bis eine Klasse
    /// oder ein Kurs das Fach trägt.
    @State private var geschrieben: [String: String] = [:]

    private struct Fachposten: Identifiable {
        let id: String
        let fach: String
        let zeilen: Int
        let farbe: Int
    }

    private var faecher: [Fachposten] {
        // Einmal gebaut statt `fachfarbe(_:)` je Fach — läuft bei jedem Neuzeichnen.
        let karte = planung.fachfarbenWirksam()
        var reihenfolge: [String] = []
        var gesehen: [String: Fachposten] = [:]
        for klasse in planung.klassen {
            let schluessel = Farbwelt.fachSchluessel(klasse.fach)
            guard !schluessel.isEmpty else { continue }
            if let vorhanden = gesehen[schluessel] {
                gesehen[schluessel] = Fachposten(id: schluessel, fach: vorhanden.fach,
                                                 zeilen: vorhanden.zeilen + 1,
                                                 farbe: vorhanden.farbe)
            } else {
                reihenfolge.append(schluessel)
                let farbe = karte[schluessel] ?? klasse.farbe
                gesehen[schluessel] = Fachposten(
                    id: schluessel, fach: klasse.fach.trimmingCharacters(in: .whitespaces),
                    zeilen: 1, farbe: farbe)
            }
        }
        for schluessel in planung.fachfarben.keys.sorted() where gesehen[schluessel] == nil {
            reihenfolge.append(schluessel)
            gesehen[schluessel] = Fachposten(
                id: schluessel, fach: geschrieben[schluessel] ?? schluessel, zeilen: 0,
                farbe: karte[schluessel] ?? 0)
        }
        return reihenfolge.compactMap { gesehen[$0] }
    }

    var body: some View {
        if faecher.isEmpty {
            Text("Noch kein Fach eingetragen.").foregroundStyle(.secondary)
        }
        ForEach(faecher) { posten in
            zeile(posten)
        }

        Button {
            neuesFachAnlegen()
        } label: {
            Label("Fachfarbe festlegen", systemImage: Zeichen.plus)
        }
    }

    /// Ein Fach ohne Zeile; die Farbe ist die nächste freie.
    private func neuesFachAnlegen() {
        var name = "neues fach"
        var zahl = 2
        while planung.kenntFach(name) {
            name = "neues fach \(zahl)"
            zahl += 1
        }
        let frei = Farbwelt.naechsteFreieFarbe(planung.farbnutzung)
        speicher.fachfarbeSetzen(fach: name, ton: Farbwelt.ton(frei).schluessel)
    }

    @ViewBuilder
    private func zeile(_ posten: Fachposten) -> some View {
        let ton = Farbwelt.ton(posten.farbe)

        LabeledContent {
            HStack(spacing: Kursspalten.abstand) {
                Text(ton.name).foregroundStyle(.secondary)

                if posten.zeilen == 0 {
                    Button(role: .destructive) {
                        speicher.fachEntfernen(posten.id)
                        geschrieben[posten.id] = nil
                    } label: {
                        Image(systemName: Zeichen.muell)
                    }
                    .buttonStyle(.borderless)
                    .help("Fach aus der Liste nehmen")
                    .accessibilityLabel("Fach \(posten.fach) entfernen")
                } else {
                    Color.clear.frame(width: 22, height: 1)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Farbwahlknopf(ton: ton, ziel: .fach(posten.id),
                              hinweis: "Farbe für „\(posten.fach)“ wählen",
                              beschriftung: "Farbe von \(posten.fach) ändern")

                if posten.zeilen == 0 {
                    Fachname(schluessel: posten.id, fach: posten.fach,
                             gemerkt: $geschrieben)
                        .frame(width: Kursspalten.name)
                    Text("noch keine Klasse, kein Kurs").foregroundStyle(.secondary)
                } else {
                    Text(posten.fach)
                    Text(posten.zeilen == 1 ? "1 Klasse/Kurs" : "\(posten.zeilen) Klassen/Kurse")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Erst beim Verlassen des Feldes umbenannt: Der Schlüssel ist zugleich die
/// Kennung der Zeile — änderte er sich beim Tippen, verlöre das Feld die
/// Schreibmarke.
private struct Fachname: View {
    let schluessel: String
    let fach: String
    @Binding var gemerkt: [String: String]

    @Environment(Planungsspeicher.self) private var speicher
    @State private var text = ""

    var body: some View {
        Tabellenfeld(hinweis: "Fach", text: $text, beimVerlassen: umbenennen)
            .onSubmit(umbenennen)
            .onAppear { text = fach }
            .onChange(of: fach) { _, neu in if neu != text { text = neu } }
    }

    private func umbenennen() {
        let sauber = text.trimmingCharacters(in: .whitespaces)
        // Nur solange der Schlüssel noch steht: Ein zweiter Anlauf derselben
        // Umbenennung träfe auf ein Fach, das die Liste bereits kennt.
        guard speicher.planung?.fachfarben[schluessel] != nil else { return }
        guard !sauber.isEmpty, Farbwelt.fachSchluessel(sauber) != schluessel else {
            text = fach
            return
        }
        speicher.fachUmbenennen(von: schluessel, nach: sauber)
        // Der alte Schlüssel ist fort: Die Umbenennung ist durchgegangen.
        guard speicher.planung?.fachfarben[schluessel] == nil else {
            text = fach
            return
        }
        gemerkt[schluessel] = nil
        gemerkt[Farbwelt.fachSchluessel(sauber)] = sauber
    }
}
