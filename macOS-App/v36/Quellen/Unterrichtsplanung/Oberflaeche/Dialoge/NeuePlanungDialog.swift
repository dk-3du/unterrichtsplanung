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
    @FocusState private var titelFokus: Bool

    // ── Übernahme aus der aktuellen Planung ──
    /// Erster Schritt: Soll überhaupt etwas übernommen werden?
    @State private var uebernahmeGewuenscht = false
    /// Zweiter Schritt, je Zeile: Eintrag vorhanden heißt „Klasse/Kurs und
    /// Fach übernehmen“, `true` heißt „samt aller zugehörigen Vorhaben“.
    @State private var mitnehmen: [String: Bool] = [:]

    private var anzahl: Int { min(Kennwerte.wochenMax, max(1, Int(wochen.rounded()))) }
    private var pruefung: Kurszeilen.Ergebnis { Kurszeilen.pruefen(kurstext) }

    /// Vor dem 1. August meint `laufendesSchuljahr` noch das alte — bleibt es
    /// bei der Vorbelegung, gleicht der Vorschlagstitel dem der laufenden
    /// Planung, und der Autoexport schriebe beide unter denselben Dateinamen.
    private var nameKollidiert: Bool {
        guard speicher.autoexportAktiv, !speicher.autoexportOrdner.isEmpty,
              let bisher = speicher.planung?.titel else { return false }
        return Planungsdatei.festerName(titel: bisher)
            == Planungsdatei.festerName(titel: titel)
    }

    var body: some View {
        Dialograhmen(titel: "Neue Planungsdatei",
                     unterzeile: "Zeitraum sowie Klassen und Kurse festlegen",
                     hoehe: 700) {
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

            if !alteKlassen.isEmpty {
                uebernahmeabschnitt
            }
        } fuss: {
            if speicher.planung != nil {
                Text("Die aktuelle Planung wird ersetzt — vorher ggf. exportieren.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Abbrechen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            Button("Planung anlegen") { anlegen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear(perform: vorbelegen)
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
        } header: {
            Text("Klassen/Kurse")
        } footer: {
            Text("Bis zu \(Kennwerte.maxKlassen) Einträge. Verbindlich ist allein die "
                 + "Bezeichnung der Klasse oder des Kurses. Ein Fach lässt sich anhängen: "
                 + "Leerzeichen, - oder –, Leerzeichen, dann das Fach. Jedes Fach bekommt "
                 + "eine eigene Farbe; unter „Klassen/Kurse und Fächer“ ist sie zu ändern.")
        }
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
        uebernahmeGewuenscht = false
        mitnehmen = [:]
        titelFokus = true
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
        let klassen = Standardkurse.aufbauen(ergebnis.kurse)
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
        // Kein Basisordner: Materialien werden mit vollem Pfad hinterlegt.
        speicher.neuePlanung(titel: titel, start: start, wochen: anzahl,
                             basis: "", klassen: klassen, ersterSchultag: ersterSchultag,
                             uebernahme: auswahl)
        // Ohne Klassen schaltet `neuePlanung` selbst auf das Folgeblatt weiter;
        // `schliessen()` schriebe die Blattbindung synchron wieder auf nil.
        if speicher.offenerDialog == .neuePlanung { schliessen() }
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
