// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Klassen, Kurse und Fächer verwalten. Eine Klasse („G6a“) und ein Kurs
/// („WPU Informatik“) stehen in derselben Liste, weil beides eine Zeile im
/// Raster bekommt; Pflicht ist allein die Bezeichnung. Darunter, in fester
/// Folge, die drei **Sonderzeilen** „Klassenleitung“, „Weiteres“ und
/// „Vertretungen“ (v69, E157): je eine, mit festem Titel, sonst wie jede Zeile. Das Fach ist freiwillig
/// und ordnet zu: Alle Zeilen desselben Fachs tragen dieselbe Farbe. Dazu
/// trägt jede Zeile ihre **Unterrichtstage** (Mo.–Fr. als Kästchen), die
/// Verweise auf Verwaltungsdatei und Curriculum, als dritte Spalte ihren
/// **Sitzplan** und danach die Leistungsdokumentation (E662, E773). Ganz oben
/// steht der Weg zur Lernendenverwaltung (v84, E356).
struct KlassenDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    @FocusState private var fokus: String?

    private var planung: Planung? { speicher.planung }

    var body: some View {
        // Breiter als die übrigen Dialoge — mit Maß: Das gruppierte `Form`
        // deckelt seinen Inhalt auf rund 700 Punkt und zentriert ihn; jenseits
        // von etwa 740 Punkt Fensterbreite kommt nur noch Rand dazu (nachgemessen
        // an 880 und 900: Der Abschnitt bleibt 700 breit). Platz für die fünf
        // Kästchen schafft deshalb nicht das Fenster, sondern die Zeile selbst.
        Dialograhmen(titel: "Lernende, Klassen/Kurse und Fächer",
                     // Gezählt werden die Klassen/Kurse; die Sonderzeilen stehen daneben,
                     // die Höchstzahl gilt für alle Zeilen zusammen (E157).
                     unterzeile: "\(planung?.unterrichtszeilen ?? 0) Klassen/Kurse"
                         + ((planung?.sonderzeilenzahl ?? 0) > 0 ? ", \(planung?.sonderzeilenzahl ?? 0) Sonderzeilen" : "")
                         + " — \(planung?.klassen.count ?? 0) von \(Kennwerte.maxKlassen) Zeilen",
                     breite: Kursspalten.dialogbreite, hoehe: 700,
                     // Liegt „Farbe wählen“ darauf, zeigt der Bogen die Meldungen — wie bei „Lernende“ (E490, E968).
                     meldungsblatt: speicher.farbwahlFuer != nil ? nil : .klassen,
                     zeileAbgegeben: speicher.farbwahlFuer != nil) {
            if let planung {
                // Der Weg zur Lernendenverwaltung, ganz oben (E356) — nach dem Blatt geht es hierher zurück (E358).
                Section {
                    HStack(spacing: 12) {
                        Button("Lernende …", action: speicher.blattknopf {
                            speicher.lernendenBlattOeffnen(ort: .klassen, zurueck: .klassen)
                        })
                        .help(speicher.lernendenKnopfhilfe)
                        // Der Knopf behält seine Breite; ein langer Sperrhinweis bricht rechts um (Z-AT4-07).
                        .fixedSize()
                        Spacer(minLength: 0)
                        Text(speicher.lernendenZusammenfassung)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Lernende")
                } footer: {
                    Text("Die Lernendenverwaltung (⌘L) führt die Lerngruppen des Schuljahrs mit ihren Mitgliedern, "
                         + "Mitteilungen und Maßnahmen. Dort lassen sich Lerngruppen samt Mitgliedern freiwillig aus "
                         + "einer Exportdatei der IServ-Benutzerverwaltung importieren — gelesen werden nur Vorname, "
                         + "Nachname und Klasse. Es gibt die Lernendenverwaltung nur mit eingeschalteter Verschlüsselung.")
                }

                Section {
                    if planung.klassen.isEmpty {
                        Text("Noch keine Klasse und kein Kurs angelegt.")
                            .foregroundStyle(.secondary)
                    } else {
                        Kursspaltenkopf()
                        ForEach(Array(planung.klassen.enumerated()), id: \.element.id) { stelle, klasse in
                            Kursposten(klasse: klasse, stelle: stelle,
                                       unterrichtszeilen: planung.unterrichtszeilen, fokus: $fokus)
                        }
                    }

                    Button {
                        if let neu = speicher.klasseHinzufuegen() { fokus = neu }
                    } label: {
                        Label("Klasse/Kurs hinzufügen", systemImage: Zeichen.plus)
                    }
                    .disabled(planung.klassen.count >= Kennwerte.maxKlassen)

                    // Die drei Sonderzeilen (E157) — je eine; ist sie da, ist der
                    // Knopf abgeblendet. „Standardliste ergänzen“ stand hier bis v68.
                    HStack(spacing: 8) {
                        ForEach(Zeilenart.sonderzeilen, id: \.self) { art in
                            Button { speicher.sonderzeileHinzufuegen(art) } label: {
                                Label("\(art.titel) hinzufügen", systemImage: Zeichen.plus)
                            }
                            .disabled(planung.hatSonderzeile(art)
                                      || planung.klassen.count >= Kennwerte.maxKlassen)
                            .help(planung.hatSonderzeile(art)
                                  ? "„\(art.titel)“ ist bereits vorhanden"
                                  : "Sonderzeile „\(art.titel)“ unterhalb der Klassen/Kurse anlegen")
                        }
                    }
                } header: {
                    Text("Klassen/Kurse")
                } footer: {
                    Text(KlassenDialog.fussKlassen)
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
            // Die Meldungen des Blatts stehen hier, nicht in der Kapsel des Hauptfensters darunter (E968).
            Fussluecke()
            // In der Lücke nach einer Antwort prallt der Knopf ab (E437).
            Button("Fertig", action: speicher.blattknopf { schliessen() })
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        // Ein Fenster trägt nur ein Blatt: An der Hauptansicht angemeldet käme keins zum Vorschein.
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
            // Der Titel einer Sonderzeile ist fest (E157); ihr Fach wird gestutzt wie jedes.
            let name = klasse.istSonderzeile ? klasse.name
                : (gestutzt.isEmpty ? "Ohne Bezeichnung" : gestutzt)
            let fach = klasse.fach.trimmingCharacters(in: .whitespaces)
            guard name != klasse.name || fach != klasse.fach else { continue }
            speicher.klasseAendern(id: klasse.id, name: name, fach: fach)
        }
    }
}

// ── Fuß und Hilfen an gesperrten Spalten — rein, damit prüfbar (E800, Z-AX6N-02, -03) ──
extension KlassenDialog {
    /// Der Fuß unter „Klassen/Kurse“ — mit der Leistungsdokumentation an jeder Zeile (E800) und dem Untermenü
    /// „Wochentag“, das die Unterrichtstage hervorhebt (E825).
    nonisolated static let fussKlassen = "Verbindlich ist die Bezeichnung der Klasse oder des Kurses; das Fach "
        + "ist freiwillig. Der Farbpunkt an einer Zeile öffnet die Farbwahl für "
        + "genau diese Zeile; eine dort gesetzte Farbe bleibt unangetastet. Die "
        + "Reihenfolge der Zeilen bestimmt die Reihenfolge im Raster. Die "
        + "Unterrichtstage sagen, an welchen Wochentagen laut Stundenplan "
        + "regelmäßig Unterricht stattfindet; der Vorhaben-Dialog und das Untermenü "
        + "„Wochentag“ der Kachel heben sie hervor. Eine Änderung hier rührt bestehende Vorhaben nicht an. "
        + "Der Stuhl öffnet den Sitzplan der Zeile — anlegen, bearbeiten, als "
        + "PDF sichern, entfernen. Sonderzeilen stehen stets unterhalb der "
        + "Klassen/Kurse in fester Reihenfolge; ihr Titel ist fest. Klassenleitung "
        + "und Weiteres tragen eine Verwaltungsdatei, aber kein Curriculum und "
        + "keinen Sitzplan; Vertretungen keines von dreien. Die externe Leistungsdokumentation "
        + "trägt jede Zeile. Ein Fach trägt neben "
        + "den Klassen/Kursen nur die Klassenleitung (ihre Klasse) — Abgeblendetes "
        + "ist nicht vorgesehen. Das Personen-Symbol bindet eine Lerngruppe an die Zeile — "
        + "dann zeigt sie im Raster die Lerngruppe statt der Verwaltungsdatei, deren Verweis "
        + "bleibt."

    /// Die Hilfen der Spalten an einer Zeile, die sie nicht trägt (E161) — derselbe Satz wie in der Kurszelle und in der
    /// Meldung (`Kursdateiart.nichtVorgesehen`), nach dem Vorbild `Klassenkopf.gesperrtHilfe` (Z-AX6N-02, -03).
    nonisolated static func gesperrtHilfe(_ art: Kursdateiart, zeile: String) -> String {
        Kursdateiart.nichtVorgesehen(an: zeile, verneint: art.verneint)
    }

    nonisolated static func sitzplanGesperrtHilfe(zeile: String) -> String {
        Kursdateiart.nichtVorgesehen(an: zeile, verneint: Klassenkopf.keinSitzplan)
    }

    nonisolated static func lerngruppeGesperrtHilfe(zeile: String) -> String {
        Kursdateiart.nichtVorgesehen(an: zeile, verneint: "keine Lerngruppe")
    }

    nonisolated static func fachGesperrtHilfe(zeile: String) -> String {
        Kursdateiart.nichtVorgesehen(an: zeile, verneint: "kein Fach")
    }
}

/// Kopf und Zeilen richten sich nach denselben Werten.
private enum Kursspalten {
    static let punkt: CGFloat = 18
    /// Schmal, weil „Klasse/Kurs“ kurz ist („G6a“, „AG“) und
    /// das Fach braucht den Platz.
    static let name: CGFloat = 112
    static let abstand: CGFloat = 10
    /// Acht randlose Symbolknöpfe samt Zwischenraum — jeder auf `knopf`
    /// gesetzt, sonst stünden die Kästchen der Zeile neben den Kürzeln des
    /// Kopfes (die Pfeil- und Papierkorbknöpfe sind von sich aus schmaler). Der
    /// achte, die Leistungsdokumentation (E773), nimmt dem Fachfeld 32 Punkt —
    /// gemessen (v86, AX6) an einem Blatt von 800 Punkt: das Eingabefeld des
    /// Fachs von 162 auf 130 Punkt, samt Fläche von 178 auf 146.
    static let knopf: CGFloat = 22
    static let knoepfe: CGFloat = 8 * knopf + 7 * abstand
    /// Fünf Kästchen Montag bis Freitag — **beschriftet im Spaltenkopf**, nicht
    /// am Kästchen: Mit Beschriftung je Kästchen maß die Gruppe 224 Punkt, als
    /// Matrix mit den Kürzeln darüber misst sie 126 (5 × 22 + 4 × 4). Das Fachfeld
    /// bekommt, was bleibt — gemessen (v86, AX6) 146 Punkt samt Fläche, siehe
    /// `knoepfe`; eine feste Untergrenze hat es nicht. Feste Spalte, damit Kopf
    /// und Zeilen bündig stehen.
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
    /// Eine Sonderzeile kann nicht alles (E161): abgeblendet, nicht klickbar.
    private var erlaubt: Bool { klasse.erlaubt(art) }

    var body: some View {
        Menu {
            if gesetzt {
                Button("Öffnen") { speicher.dateiOeffnen(pfad, ort: .klassen) }
                Button("Im Finder zeigen") { speicher.imFinderZeigen(pfad, ort: .klassen) }
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
            Image(systemName: gesetzt && erlaubt ? art.symbolGesetzt : art.symbol)
                .foregroundStyle(!erlaubt ? Color(nsColor: .quaternaryLabelColor)
                                 : gesetzt ? Color.accentColor : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Kursspalten.knopf)
        .disabled(!erlaubt)
        .help(!erlaubt ? KlassenDialog.gesperrtHilfe(art, zeile: klasse.name)
              : art.zuweisenHilfe(gesetzt: gesetzt ? speicher.vollerPfad(pfad) : nil))
        .accessibilityLabel(!erlaubt ? "\(art.dateibeschriftung) für \(klasse.name) nicht vorgesehen"
                            : art.zuweisenBedienung(klasse.name, gesetzt: gesetzt))
    }
}

/// Die dritte Menüspalte: der Sitzplan der Zeile (E28: genau einer). Ohne
/// Plan „anlegen“, mit Plan bearbeiten, als PDF sichern oder — zweistufig,
/// mit Rückfrage — entfernen. Zu, solange die Sitzpläne es sind.
private struct Sitzplanmenue: View {
    let klasse: Klasse

    @Environment(Planungsspeicher.self) private var speicher

    private var plan: Sitzplan? { speicher.sitzplan(fuer: klasse.id) }

    var body: some View {
        Menu {
            if let plan {
                Button("Sitzplan bearbeiten …") {
                    speicher.sitzplanOeffnen(klasse: klasse.id, zurueck: .klassen)
                }
                Button("Als PDF sichern …") {
                    Sitzplandruck.alsPDFSichern(plan, klasse: klasse, speicher: speicher)
                }
                Divider()
                Button("Sitzplan entfernen", role: .destructive) {
                    speicher.sitzplanEntfernen(klasse: klasse.id, ort: .klassen)
                }
            } else {
                Button("Sitzplan anlegen …") {
                    speicher.sitzplanOeffnen(klasse: klasse.id, zurueck: .klassen)
                }
            }
        } label: {
            Image(systemName: plan != nil && klasse.erlaubtSitzplan ? Zeichen.sitzplanGesetzt : Zeichen.sitzplan)
                .foregroundStyle(!klasse.erlaubtSitzplan ? Color(nsColor: .quaternaryLabelColor)
                                 : plan != nil ? Color.accentColor : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Kursspalten.knopf)
        // Eine Sonderzeile hat keinen Sitzplan (E161): abgeblendet, nicht klickbar.
        .disabled(!speicher.sitzplaene.schreibbar || !klasse.erlaubtSitzplan)
        .help(!klasse.erlaubtSitzplan ? KlassenDialog.sitzplanGesperrtHilfe(zeile: klasse.name)
              : speicher.sitzplaene.sperrhinweis
              ?? plan.map { "Sitzplan: \($0.tische.count) " + ($0.tische.count == 1 ? "Platz" : "Plätze") }
              ?? "Sitzplan anlegen")
        .accessibilityLabel(!klasse.erlaubtSitzplan ? "Sitzplan für \(klasse.name) nicht vorgesehen"
                            : plan != nil ? "Sitzplan von \(klasse.name)"
                                          : "Sitzplan für \(klasse.name) anlegen")
    }
}

/// Die fünfte Menüspalte: die Lerngruppen der Zeile (E256, E670). Je gebundener
/// öffnet sie das Blatt „Lernende“ oder löst die Bindung; dazu legt sie eine
/// Lerngruppe aus der Zeile an oder bindet eine weitere — eine gleichnamige
/// zuerst (E667). Ohne offene Lernendenverwaltung zeigt ein Klick den Hinweis
/// (E249) — versiegelt oder gesperrt als Rückfrage am Blatt (E357). Vertretungen
/// tragen keine Gruppe.
private struct Lerngruppenmenue: View {
    let klasse: Klasse

    @Environment(Planungsspeicher.self) private var speicher

    private func melden(_ grund: String?) {
        if let grund { speicher.melden(grund, .warnung) }
    }

    var body: some View {
        let erlaubt = klasse.erlaubt(.verwaltung)
        let gebunden = speicher.lerngruppen(fuerZeile: klasse.id)
        let gleichnamige = speicher.gleichnamigeLerngruppe(fuerZeile: klasse.id)
        let andere = (speicher.lernende.verzeichnis?.gruppen() ?? [])
            .filter { g in !gebunden.contains { $0.id == g.id } && g.id != gleichnamige?.id }
        let symbol = Image(systemName: !gebunden.isEmpty && erlaubt ? Zeichen.lerngruppe : Zeichen.klassen)
            .foregroundStyle(!erlaubt ? Color(nsColor: .quaternaryLabelColor)
                             : !gebunden.isEmpty ? Color.accentColor : Color.secondary)
        Group {
            if speicher.lernende.schreibbar {
                Menu {
                    // Auch von hier zurück zu ⌘K (E505); in der Lücke nach einer Antwort prallt er ab (E437).
                    if gebunden.count == 1, let gruppe = gebunden.first {
                        Button("Lernende … („\(gruppe.name)“)", action: speicher.blattknopf {
                            speicher.lernendenBlattOeffnen(gruppe: gruppe.id, ort: .klassen, zurueck: .klassen)
                        })
                        Button("Bindung lösen") { melden(speicher.lerngruppeLoesen(klasse.id, gruppe: gruppe.id)) }
                    } else {
                        ForEach(gebunden) { g in
                            Menu("„\(g.name)“") {
                                Button("Lernende …", action: speicher.blattknopf {
                                    speicher.lernendenBlattOeffnen(gruppe: g.id, ort: .klassen, zurueck: .klassen)
                                })
                                Button("Bindung lösen") { melden(speicher.lerngruppeLoesen(klasse.id, gruppe: g.id)) }
                            }
                        }
                    }
                    if !gebunden.isEmpty { Divider() }
                    if let g = gleichnamige {
                        Button("An „\(g.name)“ binden") { melden(speicher.lerngruppeBinden(g.id, an: klasse.id)) }
                    }
                    if speicher.lerngruppeAusZeileAngeboten(klasse.id) {
                        Button("Lerngruppe aus der Zeile anlegen") { melden(speicher.lerngruppeAusZeileAnlegen(klasse.id)) }
                    }
                    if !andere.isEmpty {
                        Menu("An eine Lerngruppe binden") {
                            ForEach(andere) { g in
                                Button(g.beschriftung) { melden(speicher.lerngruppeBinden(g.id, an: klasse.id)) }
                            }
                        }
                    }
                } label: { symbol }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            } else {
                Button(action: speicher.blattknopf { speicher.lernendenBlattOeffnen(ort: .klassen) }) { symbol }
                    .buttonStyle(.borderless)
            }
        }
        .frame(width: Kursspalten.knopf)
        .disabled(!erlaubt)
        .help(!erlaubt ? KlassenDialog.lerngruppeGesperrtHilfe(zeile: klasse.name)
              : gebunden.isEmpty
                ? (speicher.lernende.schreibbar ? "Lerngruppe anlegen oder binden" : speicher.lerngruppenhilfeOhneVerwaltung)
                : (gebunden.count == 1 ? "Lerngruppe " : "Lerngruppen ")
                    + gebunden.map { "„\($0.beschriftung)“" }.joined(separator: ", "))
        .accessibilityLabel(!erlaubt ? "Lerngruppe für \(klasse.name) nicht vorgesehen"
                            : gebunden.isEmpty ? "Lerngruppe für \(klasse.name) anlegen oder binden"
                            : (gebunden.count == 1 ? "Lerngruppe " : "Lerngruppen ")
                                + gebunden.map(\.name).joined(separator: ", ") + " von \(klasse.name)")
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
    /// Wie viele Zeilen Unterricht sind — die Pfeile bleiben darunter (E157).
    let unterrichtszeilen: Int
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

            if klasse.istSonderzeile {
                // Der Titel einer Sonderzeile ist fest (E157) — kein Feld.
                Text(klasse.name)
                    .frame(width: Kursspalten.name, alignment: .leading)
                    .help("Sonderzeile „\(klasse.name)“ — der Titel ist fest")
                    .accessibilityLabel("Sonderzeile \(klasse.name)")
            } else {
                Tabellenfeld(hinweis: "Klasse/Kurs", text: $name,
                             beimVerlassen: namenAbschliessen)
                    .frame(width: Kursspalten.name)
                    .focused($fokus, equals: klasse.id)
                    .accessibilityLabel("Bezeichnung der Klasse bzw. des Kurses")
                    .onChange(of: name) { _, neu in
                        namensentpreller.nach(300) { namenSchreiben(neu) }
                    }
            }
            if klasse.erlaubtFach {
                Tabellenfeld(hinweis: "Fach (optional)", text: $fach,
                             beimVerlassen: fachAbschliessen)
                    .accessibilityLabel("Fach von \(klasse.name)")
                    .onChange(of: fach) { _, neu in
                        fachentpreller.nach(300) { fachSchreiben(neu) }
                    }
            } else {
                // Weiteres und Vertretungen tragen kein Fach (E161): abgeblendet, kein Feld.
                Text("kein Fach vorgesehen")
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(KlassenDialog.fachGesperrtHilfe(zeile: klasse.name))
                    .accessibilityLabel("Kein Fach für \(klasse.name) vorgesehen")
            }

            Unterrichtstagewahl(klasse: klasse)

            // Die Folge der Kurszelle: Verwaltungsdatei, Curriculum, Sitzplan, Leistungsdokumentation (E662,
            // E773) — dann die Lerngruppe.
            ForEach(Kursdateiart.ueberDemSitzplan) { art in
                Kursdateimenue(klasse: klasse, art: art)
            }
            Sitzplanmenue(klasse: klasse)
            ForEach(Kursdateiart.unterDemSitzplan) { art in
                Kursdateimenue(klasse: klasse, art: art)
            }
            Lerngruppenmenue(klasse: klasse)

            Button { speicher.klassenTauschen(stelle, stelle - 1) } label: {
                Image(systemName: Zeichen.hoch)
            }
            .buttonStyle(.borderless)
            .frame(width: Kursspalten.knopf)
            .disabled(klasse.istSonderzeile || stelle == 0)
            .help(klasse.istSonderzeile ? "Sonderzeilen stehen fest" : "Nach oben")

            Button { speicher.klassenTauschen(stelle, stelle + 1) } label: {
                Image(systemName: Zeichen.runter)
            }
            .buttonStyle(.borderless)
            .frame(width: Kursspalten.knopf)
            .disabled(klasse.istSonderzeile || stelle >= unterrichtszeilen - 1)
            .help(klasse.istSonderzeile ? "Sonderzeilen stehen fest" : "Nach unten")

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
