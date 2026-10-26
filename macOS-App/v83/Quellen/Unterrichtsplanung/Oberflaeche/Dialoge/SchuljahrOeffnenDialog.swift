// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Die Wahl der Lerngruppen ins neue Schuljahr (E271) — in „Neue Planung“ und
/// im Blatt „Neues Schuljahr öffnen“ (E305). Dazu der Schalter „Lerngruppen
/// hochstufen“ (E307) und je Gruppe ein Namensfeld (E308) und die Zeile der
/// neuen Planung (E310).
struct LerngruppenWahl: View {
    let gruppen: [Lerngruppe]
    let mitgliederzahl: (String) -> Int
    let gewaehlt: Set<String>
    let breite: CGFloat
    let fuss: String
    let setzen: (Set<String>) -> Void
    let hochstufen: Bool
    let stufentext: String
    let hochstufenSetzen: (Bool) -> Void
    /// Was im Namensfeld steht — getippt oder vorgeschlagen.
    let namen: [String: String]
    let nameSetzen: (Lerngruppe, String) -> Void
    let zeilen: [Hochstufung.Zeile]
    /// Die Zeile je Gruppe; fehlt sie, „Keine Zeile“.
    let zuteilung: [String: String]
    /// `""` heißt „Keine Zeile“.
    let zeileSetzen: (String, String) -> Void

    static let namensbreite: CGFloat = 130

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { hochstufen }, set: { hochstufenSetzen($0) })) {
                Text("Lerngruppen hochstufen")
                Text(stufentext)
            }
            ForEach(gruppen) { gruppe in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(gruppe.beschriftung).lineLimit(1)
                        Text("\(mitgliederzahl(gruppe.id)) Lernende")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                        Hakenknopf(aktiv: gewaehlt.contains(gruppe.id),
                                   breite: breite,
                                   hilfe: gewaehlt.contains(gruppe.id) ? "Nicht ins neue Schuljahr übernehmen"
                                                                       : "Mit Personen und offenen Anliegen übernehmen",
                                   kennzeichnung: "Lerngruppe übernehmen — " + gruppe.beschriftung) {
                            var neu = gewaehlt
                            if neu.contains(gruppe.id) { neu.remove(gruppe.id) } else { neu.insert(gruppe.id) }
                            setzen(neu)
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Name", text: Binding(get: { namen[gruppe.id] ?? gruppe.name },
                                                        set: { nameSetzen(gruppe, $0) }),
                                  prompt: Text(gruppe.name))
                            .labelsHidden()
                            // Im gruppierten Formular sonst rahmenlos — wie Text, nicht wie ein Feld.
                            .textFieldStyle(.roundedBorder)
                            .frame(width: Self.namensbreite)
                            .accessibilityLabel("Name im neuen Schuljahr — " + gruppe.beschriftung)
                        Picker("Zeile", selection: Binding(get: { zuteilung[gruppe.id] ?? "" },
                                                           set: { zeileSetzen(gruppe.id, $0) })) {
                            Text("Keine Zeile").tag("")
                            ForEach(zeilen) { zeile in
                                Text(zeile.titel).tag(zeile.id)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Zeile im neuen Schuljahr — " + gruppe.beschriftung)
                    }
                }
            }
        } header: {
            Text("Lerngruppen ins neue Schuljahr")
        } footer: {
            Text(fuss)
        }
    }
}

/// Der Zustand der Wahl, wie beide Blätter ihn führen: der Schalter, getippte
/// Namen, von Hand gewählte Zeilen und die Haken — `nil` bzw. fehlend: die Vorgabe.
struct Hochstufungswahl {
    var hochstufen: Bool?
    var namen: [String: String] = [:]
    var zeilen: [String: String] = [:]
    /// Die Haken — `nil`: die Vorwahl, live bis zur ersten Änderung in der Liste (E312).
    var haken: Set<String>?

    func gewaehlt(vorwahl: Set<String>) -> Set<String> {
        haken ?? vorwahl
    }

    /// Die erste Änderung in der Liste friert die Vorwahl ein (E312).
    private mutating func einfrieren(_ vorwahl: Set<String>) {
        if haken == nil { haken = vorwahl }
    }

    mutating func nameSetzen(_ name: String, fuer gruppe: Lerngruppe, stufen: Int, vorwahl: Set<String>) {
        // Gibt das Feld beim Verlassen nur zurück, was es zeigt, ist nichts geändert (Z14c2-09).
        guard name != self.name(gruppe, stufen: stufen) else { return }
        einfrieren(vorwahl)
        namen[gruppe.id] = name
    }

    mutating func hochstufenSetzen(_ an: Bool, vorwahl: Set<String>) {
        einfrieren(vorwahl)
        hochstufen = an
    }

    /// Was im Namensfeld steht: getippt, sonst der Vorschlag (E308).
    func name(_ gruppe: Lerngruppe, stufen: Int) -> String {
        namen[gruppe.id] ?? (hochstufen ?? (stufen > 0) ? Hochstufung.name(gruppe.name, um: max(stufen, 1)) : gruppe.name)
    }

    /// Der Name, nach dem die Zeile gesucht wird — ein leeres Feld heißt der bisherige.
    func suchname(_ gruppe: Lerngruppe, stufen: Int) -> String {
        let n = name(gruppe, stufen: stufen)
        return n.trimmingCharacters(in: .whitespaces).isEmpty ? gruppe.name : n
    }

    /// Eine Zeile trägt eine Gruppe: Wer sie hatte, steht danach auf „Keine Zeile“ (Voreinstellung 4)
    /// und behält seinen Haken; eine gewählte Zeile setzt den Haken ihrer Gruppe (E312).
    mutating func zeileWaehlen(_ zeile: String, fuer gruppe: String, zuteilung: [String: String],
                               vorwahl: Set<String>) {
        einfrieren(vorwahl)
        if !zeile.isEmpty {
            for (andere, z) in zuteilung where z == zeile && andere != gruppe { zeilen[andere] = "" }
            haken?.insert(gruppe)
        }
        zeilen[gruppe] = zeile
    }
}

/// ⌘O mit einer Planung anderer Herkunft (E277, E305): Die bisherige Planung
/// geht samt ihren Lernendendaten ins Archiv; gewählt wird, welche Lerngruppen
/// mitkommen — wie bei „Neue Planung“, mit Namen und Zeile (E307–E311).
struct SchuljahrOeffnenDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen
    @State private var wahl = Hochstufungswahl()
    /// Der Wechsel, solange das Blatt steht — beim Schließen ist er im Speicher schon fort (Z14c2-05).
    @State private var gehalten: Schuljahrwechsel?

    static let titel = "Neues Schuljahr öffnen"
    static let absatz = "Die bisherige Planung wird samt ihren Lernendendaten ins Archiv gelegt; mit der geöffneten "
        + "beginnt eine neue Jahresdatei."
    static let fuss = "Die gewählten Lerngruppen kommen mit ihren Personen und offenen Anliegen in die neue Jahresdatei; "
        + "alles Erledigte bleibt mit der bisherigen Planung im Archiv. Vorgewählt sind die Gruppen, für die sich eine "
        + "Zeile findet — die übernommene oder die eine mit dem neuen Namen. Das Fach einer Gruppe folgt der gewählten "
        + "Klasse/dem gewählten Kurs."
    static let knopf = "Archivieren und öffnen"

    /// Ohne Wechsel des Schuljahrs heißt das Blatt anders (E307, E309).
    static func titel(stufen: Int) -> String {
        stufen == 0 ? "Andere Planung öffnen" : stufen < 0 ? "Früheres Schuljahr öffnen" : titel
    }

    static func unterzeile(_ wechsel: Schuljahrwechsel) -> String {
        wechsel.stufen == 0
            ? "„\(wechsel.titel)“ und „\(wechsel.bisher)“ gehören beide zum Schuljahr \(wechsel.bisherigesSchuljahr)"
            : "„\(wechsel.titel)“ (\(wechsel.neuesSchuljahr)) gehört zu einem anderen Schuljahr als „\(wechsel.bisher)“ "
                + "(\(wechsel.bisherigesSchuljahr))"
    }

    var body: some View {
        let wechsel = speicher.schuljahrwechsel ?? gehalten
        let gruppen = speicher.lerngruppenZurWahl
        let stufen = wechsel?.stufen ?? 0
        // Vorgewählt, wofür sich beim Öffnen eine Zeile fand — bis zur ersten Änderung in der Liste (E311, E312).
        let vorwahl = wechsel?.vorgabe ?? []
        let gewaehlt = wahl.gewaehlt(vorwahl: vorwahl)
        let namen = Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, wahl.name($0, stufen: stufen)) })
        let zuteilung = Hochstufung.zuteilung(
            gruppen, namen: Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, wahl.suchname($0, stufen: stufen)) }),
            uebernommen: wechsel?.uebernommen ?? [:], zeilen: wechsel?.zeilen ?? [], gewaehlt: wahl.zeilen)
        Dialograhmen(titel: Self.titel(stufen: stufen),
                     unterzeile: wechsel.map(Self.unterzeile) ?? "",
                     breite: 640, hoehe: 560, beimSchliessen: abbrechen) {
            Section {
                Text(Self.absatz)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !gruppen.isEmpty {
                LerngruppenWahl(gruppen: gruppen,
                                mitgliederzahl: { speicher.lernende.verzeichnis?.mitgliederzahl($0) ?? 0 },
                                gewaehlt: gewaehlt, breite: 84, fuss: Self.fuss,
                                setzen: { wahl.haken = $0 },
                                hochstufen: wahl.hochstufen ?? (stufen > 0),
                                stufentext: Hochstufung.stufentext(bisher: wechsel?.bisherigesSchuljahr ?? "",
                                                                   neu: wechsel?.neuesSchuljahr ?? "", stufen: stufen,
                                                                   an: wahl.hochstufen ?? (stufen > 0)),
                                hochstufenSetzen: { wahl.hochstufenSetzen($0, vorwahl: vorwahl) },
                                namen: namen,
                                nameSetzen: { wahl.nameSetzen($1, fuer: $0, stufen: stufen, vorwahl: vorwahl) },
                                zeilen: wechsel?.zeilen ?? [],
                                zuteilung: zuteilung,
                                zeileSetzen: { wahl.zeileWaehlen($1, fuer: $0, zuteilung: zuteilung, vorwahl: vorwahl) })
            }
        } fuss: {
            Spacer(minLength: 0)
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Button(Self.knopf, role: .destructive, action: speicher.blattknopf {
                let ziele = Dictionary(uniqueKeysWithValues: gruppen.filter { gewaehlt.contains($0.id) }.map {
                    ($0.id, Gruppenziel(name: namen[$0.id] ?? $0.name, zeile: zuteilung[$0.id]))
                })
                schliessen()
                speicher.schuljahrOeffnen(gruppen: gewaehlt, ziele: ziele)
            })
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(speicher.schuljahrwechsel == nil)
        }
        .onAppear { gehalten = speicher.schuljahrwechsel }
    }

    private func abbrechen() {
        // In der Lücke nach einer Antwort prallt der Knopf ab, auch ⎋ (E437).
        guard !speicher.frageSperrtBefehl() else { return }
        speicher.schuljahrOeffnenAbbrechen()
        schliessen()
    }
}
