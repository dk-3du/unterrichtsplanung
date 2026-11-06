// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Womit der Bogen „Rückmeldungsliste“ aufgeht — im Betrieb leer: nichts vorgewählt, kein Kennwort (E408), nur
/// Betroffene (E1044). Prüfstand und Abbild geben Auswahl, Kennwort und Umfang vor.
struct Rueckmeldungsbogenvorgabe: Equatable, Sendable {
    var auswahl: Set<String> = []
    var kennwort = ""
    var wiederholung = ""
    var umfang: Rueckmeldungsliste.Umfang = .nurBetroffene
}

/// Der Bogen für eine Lerngruppe, solange er steht.
struct Rueckmeldungslistenvorlage: Identifiable {
    let id = UUID()
    let gruppe: Lerngruppe
    var vorgabe = Rueckmeldungsbogenvorgabe()
}

/// Was der Bogen an Sichern und Drucken gibt (E1044): die gewählten Mitteilungen und wen die Liste nennt — ein Wert,
/// damit kein Weg der Ausgabe die Wahl verliert.
struct Rueckmeldungslistenwahl: Equatable, Sendable {
    var mitteilungen: Set<String>
    var umfang: Rueckmeldungsliste.Umfang
}

/// Was der Bogen zeigt und erlaubt — rein, damit die Suite es prüft (E401, E406, E408).
@MainActor
enum Rueckmeldungslistenbogen {
    // Fest: die drei Knöpfe.
    static let knopftitel = "Rückmeldungsliste …"
    static let sichernTitel = "Als PDF sichern (verschlüsselt) …"
    static let druckenTitel = "Drucken …"

    // Vorschläge zur Sichtprüfung.
    static let titel = "Rückmeldungsliste"
    static let knopfhilfe = "Die Rückläufe gewählter Mitteilungen als Liste — verschlüsselt als PDF oder auf Papier"
    static let knopfhilfeOhneMitteilung = "Die Lerngruppe hat noch keine Mitteilung."
    /// Erklärt auch die Wahl, die als Zeile in diesem Abschnitt steht (E1055).
    static let auswahlFuss = "Nichts ist vorgewählt. Je gewählte Mitteilung eine Spalte mit allen Rückläufen und "
        + "ihrem Stand; die Notizen stehen im Anhang. „nur Betroffene“: wer von mindestens einer gewählten Mitteilung "
        + "betroffen ist. „alle Mitglieder“: die ganze Lerngruppe."
    /// Wen die Liste nennt (E1044) — die beiden Titel stehen am `Rueckmeldungsliste.Umfang`.
    static let umfangTitel = "Die Liste nennt"
    /// Sagt auch, wann „Als PDF sichern“ wählbar ist (E738).
    static let kennwortFuss = "Mindestens 12, höchstens 32 Zeichen, nur ASCII — keine Umlaute, kein ß. „Als PDF sichern "
        + "(verschlüsselt) …“ ist erst wählbar, wenn das Kennwort zweimal gleich getippt ist. Die App merkt sich das "
        + "Kennwort nicht; getrennt vom PDF weitergeben."
    static let wiederholungWeichtAb = "Die Wiederholung weicht ab."
    static let ausgabeText = "„Als PDF sichern (verschlüsselt) …“ schreibt das PDF nur verschlüsselt (AES-128); es "
        + "öffnet in jeder PDF-Anzeige mit dem Kennwort. „Drucken …“ geht nur an einen Drucker — die PDF-Wege des "
        + "Druckdialogs weist die App ab. Ein Druckauftrag liegt beim System, bis er gedruckt ist."
    static let sichernNachricht = "Rückmeldungsliste als verschlüsseltes PDF sichern"
    static let ohneAuswahl = "Keine gewählte Mitteilung gehört zu dieser Lerngruppe — nichts ausgegeben."
    /// Ohne eine Zeile mit einem Namen gibt der Bogen nichts aus (E1057).
    static let niemandBetroffen = "Von den gewählten Mitteilungen ist niemand mehr betroffen — mit „alle Mitglieder“ "
        + "nennt die Liste die ganze Lerngruppe."
    static let ohneMitglieder = "Die Lerngruppe hat kein aktives Mitglied, und niemand ist betroffen — nichts ausgegeben."
    static let nichtGesetzt = "Die Rückmeldungsliste ließ sich nicht setzen."
    /// Ein PDF-Weg des Druckdialogs wurde abgewiesen (E407).
    static let pdfWegAbgewiesen = "Nicht ausgegeben: Ein PDF aus dem Druckdialog wäre unverschlüsselt. Als PDF geht die "
        + "Rückmeldungsliste nur über „Als PDF sichern (verschlüsselt) …“."

    /// Welche Knöpfe gehen: beide nur mit einer gewählten Mitteilung der Gruppe (E408); „Als PDF sichern“
    /// zudem nur mit einem Kennwort, das taugt und zweimal gleich getippt ist (E406).
    struct Knoepfe: Equatable, Sendable {
        var sichern: Bool
        var drucken: Bool
    }

    static func knoepfe(gewaehlt: Set<String>, mitteilungen: [String], kennwort: String,
                        wiederholung: String) -> Knoepfe {
        let auswahl = mitteilungen.contains(where: gewaehlt.contains)
        let kennwortGilt = Listensatz.kennwortEinwand(kennwort) == nil && kennwort == wiederholung
        return Knoepfe(sichern: auswahl && kennwortGilt, drucken: auswahl)
    }

    /// Was unter den Kennwortfeldern steht, solange etwas nicht stimmt — `nil`, wenn nichts zu sagen ist:
    /// der Einwand des Listensatzes, sonst eine abweichende Wiederholung.
    static func kennworthinweis(_ kennwort: String, _ wiederholung: String) -> String? {
        guard !kennwort.isEmpty || !wiederholung.isEmpty else { return nil }
        if let einwand = Listensatz.kennwortEinwand(kennwort) { return einwand }
        return !wiederholung.isEmpty && wiederholung != kennwort ? wiederholungWeichtAb : nil
    }

    /// Was beim Öffnen gewählt ist — im Betrieb nichts (E408); nur Mitteilungen der Gruppe.
    static func startauswahl(_ vorgabe: Rueckmeldungsbogenvorgabe, mitteilungen: [String]) -> Set<String> {
        vorgabe.auswahl.intersection(mitteilungen)
    }

    /// „2 von 5 gewählt“
    static func zaehlung(gewaehlt: Set<String>, mitteilungen: [String]) -> String {
        "\(mitteilungen.filter(gewaehlt.contains).count) von \(mitteilungen.count) gewählt"
    }

    /// „Wandertag · 01.09.2026“ — wie die Wahl unter der Rücklaufliste; der Spaltenkopf nennt den Tag vorn, ohne Jahr
    /// (E739, E775).
    static func mitteilungszeile(_ mitteilung: Anliegen) -> String {
        Ruecklaufliste.wahltitel(mitteilung)
    }

    /// Der Knopf im Blatt: gesperrt, solange die Gruppe keine Mitteilung hat.
    static func knopf(mitteilungen: Int) -> (gesperrt: Bool, hilfe: String) {
        mitteilungen > 0 ? (false, knopfhilfe) : (true, knopfhilfeOhneMitteilung)
    }

    /// „Rückmeldungsliste_6a_2026-10-14.pdf“ — wie der Sitzplan. Nur die Lerngruppe: Ein Fach trägt sie nicht (E656).
    static func dateiname(_ gruppe: Lerngruppe) -> String {
        Planungsdatei.exportName(titel: titel + " " + gruppe.name, endung: "pdf")
    }

    /// Der Titel des Druckauftrags: „Rückmeldungsliste 6a“.
    static func auftragstitel(_ gruppe: Lerngruppe) -> String {
        titel + " " + gruppe.beschriftung
    }

    /// Die Liste aus dem Bestand, wie der Bogen sie wählt (E1044) — für das PDF und den Druck; `nil` auch ohne eine Zeile mit
    /// einem Namen (E1057), den Grund nennt `grund`.
    static func liste(_ bestand: Lernendenbestand, gruppe: String, wahl: Rueckmeldungslistenwahl, stand: Tag) -> Liste? {
        guard let liste = Rueckmeldungsliste.liste(bestand, gruppe: gruppe, mitteilungen: wahl.mitteilungen,
                                                   umfang: wahl.umfang, stand: stand),
              liste.zeilen.contains(where: { !$0.trenner }) else { return nil }
        return liste
    }

    /// Warum keine Liste entsteht: keine gewählte Mitteilung der Gruppe, oder keine Zeile mit einem Namen (E1057).
    static func grund(_ bestand: Lernendenbestand, gruppe: String, wahl: Rueckmeldungslistenwahl, stand: Tag) -> String {
        guard Rueckmeldungsliste.liste(bestand, gruppe: gruppe, mitteilungen: wahl.mitteilungen, umfang: wahl.umfang,
                                       stand: stand) != nil else { return ohneAuswahl }
        // Ohne aktive Mitglieder hülfe auch „alle Mitglieder“ nicht.
        return Lernendenverzeichnis(bestand).mitglieder(gruppe).isEmpty ? ohneMitglieder : niemandBetroffen
    }

    /// Das verschlüsselte PDF aus dem Bestand — oder der Grund, warum keines entstand.
    static func pdf(_ bestand: Lernendenbestand, gruppe: String, wahl: Rueckmeldungslistenwahl, kennwort: String,
                    stand: Tag) -> Listensatz.Ausgabe {
        guard let liste = liste(bestand, gruppe: gruppe, wahl: wahl, stand: stand) else {
            return .abgewiesen(grund(bestand, gruppe: gruppe, wahl: wahl, stand: stand))
        }
        return Listensatz.pdf(liste, kennwort: kennwort)
    }

    /// Der Meldungstext nach dem Sichern.
    static func gesichert(_ gruppe: String) -> String {
        "Die Rückmeldungsliste „\(gruppe)“ ist als verschlüsseltes PDF gesichert — es öffnet nur mit dem Kennwort."
    }
}

/// Der Bogen „Rückmeldungsliste“ am Blatt „Lernende“ (E401): die Mitteilungen der Gruppe von Hand gewählt, nichts
/// vorgewählt (E408); wen die Liste nennt, vorgegeben nur Betroffene (E1044); das Kennwort zweimal getippt (E406). Beide
/// Knöpfe der Ausgabe schließen den Bogen — Sichern- und Druckdialog gehen erst am Blatt auf, ein Fenster trägt einen Bogen.
struct RueckmeldungslisteBogen: View {
    let gruppe: Lerngruppe
    /// Die Mitteilungen der Gruppe, in der Folge der Spalten.
    let mitteilungen: [Anliegen]
    var vorgabe = Rueckmeldungsbogenvorgabe()
    /// `true`: Der Bogen geht, der Sichern-Dialog folgt. Sonst bleibt er, und die Meldung sagt, warum.
    let sichern: (Rueckmeldungslistenwahl, String) -> Bool
    /// `true`: Der Bogen geht, der Druckdialog folgt.
    let drucken: (Rueckmeldungslistenwahl) -> Bool

    @Environment(\.dismiss) private var schliessen
    @State private var gewaehlt: Set<String> = []
    @State private var kennwort = ""
    @State private var wiederholung = ""
    @State private var umfang = Rueckmeldungsliste.Umfang.nurBetroffene

    private var kennungen: [String] { mitteilungen.map(\.id) }

    /// Was „Drucken …“ und „Als PDF sichern …“ bekommen (E1044).
    private var wahl: Rueckmeldungslistenwahl { Rueckmeldungslistenwahl(mitteilungen: gewaehlt, umfang: umfang) }

    private var knoepfe: Rueckmeldungslistenbogen.Knoepfe {
        Rueckmeldungslistenbogen.knoepfe(gewaehlt: gewaehlt, mitteilungen: kennungen, kennwort: kennwort,
                                         wiederholung: wiederholung)
    }

    var body: some View {
        // Der Bogen liegt auf dem Blatt „Lernende“ und zeigt dessen Zeile (E490).
        Dialograhmen(titel: Rueckmeldungslistenbogen.titel, unterzeile: gruppe.beschriftung, breite: 560, hoehe: 640,
                     meldungsblatt: .lernende) {
            // Der Rahmen legt die Abschnitte in seine gruppierte Form — keine zweite hier.
            Section {
                HStack(spacing: 8) {
                    Text(Rueckmeldungslistenbogen.zaehlung(gewaehlt: gewaehlt, mitteilungen: kennungen))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    // Die Hilfen nach E761 — gesperrt über die durchsichtige Fläche wie H1 (Z-AW5bN-06).
                    let alle = kennungen.allSatisfy(gewaehlt.contains)
                    Button("Alle wählen") { gewaehlt = Set(kennungen) }
                        .disabled(alle)
                        .hilfe(Knopfhilfe.alleWaehlen, gesperrt: alle)
                    let keine = !kennungen.contains(where: gewaehlt.contains)
                    Button("Auswahl aufheben") { gewaehlt = [] }
                        .disabled(keine)
                        .hilfe(Knopfhilfe.auswahlAufheben, gesperrt: keine)
                }
                ForEach(mitteilungen) { m in
                    Toggle(Rueckmeldungslistenbogen.mitteilungszeile(m), isOn: Binding(
                        get: { gewaehlt.contains(m.id) },
                        set: { an in
                            if an { gewaehlt.insert(m.id) } else { gewaehlt.remove(m.id) }
                        }))
                        .toggleStyle(.checkbox)
                }
                // Wen die Liste nennt — vorgegeben nur Betroffene (E1044), als Zeile unter den Mitteilungen (E1055).
                Picker(Rueckmeldungslistenbogen.umfangTitel, selection: $umfang) {
                    ForEach(Rueckmeldungsliste.Umfang.allCases, id: \.self) { u in
                        Text(u.titel).tag(u)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
            } header: {
                Text("Mitteilungen")
            } footer: {
                Text(Rueckmeldungslistenbogen.auswahlFuss)
            }

            Section {
                SecureField("Kennwort", text: $kennwort)
                SecureField("Wiederholung", text: $wiederholung)
            } header: {
                Text("Kennwort für das PDF")
            } footer: {
                if let hinweis = Rueckmeldungslistenbogen.kennworthinweis(kennwort, wiederholung) {
                    Text(hinweis).foregroundStyle(.orange)
                } else {
                    Text(Rueckmeldungslistenbogen.kennwortFuss)
                }
            }

            Section {
                Text(Rueckmeldungslistenbogen.ausgabeText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Ausgabe")
            }
        } fuss: {
            Fussluecke()
            Button("Abbrechen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            // Gesperrt mit eigenen Texten (E761).
            Button(Rueckmeldungslistenbogen.druckenTitel) {
                if drucken(wahl) { schliessen() }
            }
            .disabled(!knoepfe.drucken)
            .hilfe(Knopfhilfe.drucken(gesperrt: !knoepfe.drucken), gesperrt: !knoepfe.drucken)
            Button(Rueckmeldungslistenbogen.sichernTitel) {
                if sichern(wahl, kennwort) { schliessen() }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!knoepfe.sichern)
            .hilfe(Knopfhilfe.sichern(gesperrt: !knoepfe.sichern), gesperrt: !knoepfe.sichern)
        }
        .onAppear {
            gewaehlt = Rueckmeldungslistenbogen.startauswahl(vorgabe, mitteilungen: kennungen)
            kennwort = vorgabe.kennwort
            wiederholung = vorgabe.wiederholung
            umfang = vorgabe.umfang
        }
    }
}
