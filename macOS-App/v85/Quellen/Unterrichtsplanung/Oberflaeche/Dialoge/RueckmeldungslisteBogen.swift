// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Womit der Bogen „Rückmeldungsliste“ aufgeht — im Betrieb leer: nichts vorgewählt, kein Kennwort (E408).
/// Prüfstand und Abbild geben Auswahl und Kennwort vor.
struct Rueckmeldungsbogenvorgabe: Equatable, Sendable {
    var auswahl: Set<String> = []
    var kennwort = ""
    var wiederholung = ""
}

/// Der Bogen für eine Lerngruppe, solange er steht.
struct Rueckmeldungslistenvorlage: Identifiable {
    let id = UUID()
    let gruppe: Lerngruppe
    var vorgabe = Rueckmeldungsbogenvorgabe()
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
    static let auswahlFuss = "Nichts ist vorgewählt. Je gewählte Mitteilung eine Spalte mit allen Rückläufen und "
        + "ihrem Stand; die Notizen stehen im Anhang."
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

    /// „Wandertag · 01.09.2026“ — wie der Spaltenkopf der Liste.
    static func mitteilungszeile(_ mitteilung: Anliegen) -> String {
        ([mitteilung.titel] + (Tag(iso: mitteilung.datum).map { [$0.deutsch] } ?? [])).joined(separator: " · ")
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

    /// Das verschlüsselte PDF aus dem Bestand — oder der Grund, warum keines entstand.
    static func pdf(_ bestand: Lernendenbestand, gruppe: String, auswahl: Set<String>, kennwort: String,
                    stand: Tag) -> Listensatz.Ausgabe {
        guard let liste = Rueckmeldungsliste.liste(bestand, gruppe: gruppe, mitteilungen: auswahl, stand: stand) else {
            return .abgewiesen(ohneAuswahl)
        }
        return Listensatz.pdf(liste, kennwort: kennwort)
    }

    /// Der Meldungstext nach dem Sichern.
    static func gesichert(_ gruppe: String) -> String {
        "Die Rückmeldungsliste „\(gruppe)“ ist als verschlüsseltes PDF gesichert — es öffnet nur mit dem Kennwort."
    }
}

/// Der Bogen „Rückmeldungsliste“ am Blatt „Lernende“ (E401): die Mitteilungen der Gruppe von Hand gewählt,
/// nichts vorgewählt (E408); das Kennwort zweimal getippt (E406). Beide Knöpfe der Ausgabe schließen den
/// Bogen — Sichern- und Druckdialog gehen erst am Blatt auf, ein Fenster trägt einen Bogen.
struct RueckmeldungslisteBogen: View {
    let gruppe: Lerngruppe
    /// Die Mitteilungen der Gruppe, in der Folge der Spalten.
    let mitteilungen: [Anliegen]
    var vorgabe = Rueckmeldungsbogenvorgabe()
    /// `true`: Der Bogen geht, der Sichern-Dialog folgt. Sonst bleibt er, und die Meldung sagt, warum.
    let sichern: (Set<String>, String) -> Bool
    /// `true`: Der Bogen geht, der Druckdialog folgt.
    let drucken: (Set<String>) -> Bool

    @Environment(\.dismiss) private var schliessen
    @State private var gewaehlt: Set<String> = []
    @State private var kennwort = ""
    @State private var wiederholung = ""

    private var kennungen: [String] { mitteilungen.map(\.id) }

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
                    Button("Alle wählen") { gewaehlt = Set(kennungen) }
                        .disabled(kennungen.allSatisfy(gewaehlt.contains))
                    Button("Auswahl aufheben") { gewaehlt = [] }
                        .disabled(!kennungen.contains(where: gewaehlt.contains))
                }
                ForEach(mitteilungen) { m in
                    Toggle(Rueckmeldungslistenbogen.mitteilungszeile(m), isOn: Binding(
                        get: { gewaehlt.contains(m.id) },
                        set: { an in
                            if an { gewaehlt.insert(m.id) } else { gewaehlt.remove(m.id) }
                        }))
                        .toggleStyle(.checkbox)
                }
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
            Spacer(minLength: 0)
            Button("Abbrechen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            Button(Rueckmeldungslistenbogen.druckenTitel) {
                if drucken(gewaehlt) { schliessen() }
            }
            .disabled(!knoepfe.drucken)
            Button(Rueckmeldungslistenbogen.sichernTitel) {
                if sichern(gewaehlt, kennwort) { schliessen() }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!knoepfe.sichern)
        }
        .onAppear {
            gewaehlt = Rueckmeldungslistenbogen.startauswahl(vorgabe, mitteilungen: kennungen)
            kennwort = vorgabe.kennwort
            wiederholung = vorgabe.wiederholung
        }
    }
}
