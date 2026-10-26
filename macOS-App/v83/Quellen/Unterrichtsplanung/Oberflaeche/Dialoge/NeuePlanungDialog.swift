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
    /// Schalter, Namen, Zeilen und Haken der Lerngruppen (E271, E307–E312) —
    /// vorgewählt, wofür sich eine Zeile findet, bis zur ersten Änderung in der Liste.
    @State private var wahl = Hochstufungswahl()

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

            if !lerngruppen.isEmpty {
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
            }
            Spacer(minLength: 0)
            // In der Lücke nach einer Antwort prallen die Knöpfe ab (E437).
            Button("Abbrechen", action: speicher.blattknopf { schliessen() })
                .keyboardShortcut(.cancelAction)
            Button("Planung anlegen", action: speicher.blattknopf { anlegen() })
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear(perform: vorbelegen)
        // Ein Fenster trägt nur ein Blatt: an der Hauptansicht angemeldet bliebe
        // die Rückfrage vor dem Anlegen unsichtbar (E275).
        .rueckfrage(speicher, ort: .neuePlanung)
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
                 + "eine eigene Farbe; unter „Klassen/Kurse und Fächer“ ist sie zu ändern.")
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
                 + "etwa „7a“ — gesetzt unter „Klassen/Kurse und Fächer“.")
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

    /// Die Schuljahre zwischen der Jahresdatei und der ersten Woche (E307).
    private var stufen: Int {
        Hochstufung.stufen(von: speicher.bisherigesSchuljahr, zu: Lernendenbestand.schuljahr(fuer: start)) ?? 0
    }

    /// Die neu gewählten Sonderzeilen — eine übernommene derselben Art zählt als übernommen.
    private var neueSonderzeilen: [Zeilenart] {
        Zeilenart.sonderzeilen.filter { sonderzeilen.contains($0) && !uebernommen($0) }
    }

    private var uebernommeneKlassen: [Klasse] {
        uebernahmeGewuenscht ? alteKlassen.filter { mitnehmen[$0.id] != nil } : []
    }

    private var zeilenangebot: [Hochstufung.Zeile] {
        Self.zeilenangebot(eingaben: pruefung.kurse, sonderzeilen: neueSonderzeilen, uebernommene: uebernommeneKlassen)
    }

    /// Die Zeile je Gruppe (E311) — als Schlüssel des Zeilenangebots.
    private func zuteilung(_ gruppen: [Lerngruppe], _ stufen: Int, _ angebot: [Hochstufung.Zeile]) -> [String: String] {
        let herkunft = speicher.lernende.bestand?.planung ?? ""
        let schluessel = Dictionary(uniqueKeysWithValues: uebernommeneKlassen.map { ($0.id, "u:" + $0.id) })
        var uebernommen: [String: String] = [:]
        var namen: [String: String] = [:]
        for g in gruppen {
            uebernommen[g.id] = Hochstufung.uebernommeneZeile(g, planung: herkunft, zuordnung: schluessel)
            namen[g.id] = wahl.suchname(g, stufen: stufen)
        }
        return Hochstufung.zuteilung(gruppen, namen: namen, uebernommen: uebernommen, zeilen: angebot,
                                     gewaehlt: wahl.zeilen)
    }

    private var gewaehlteGruppen: Set<String> {
        wahl.gewaehlt(vorwahl: Set(zuteilung(lerngruppen, stufen, zeilenangebot).keys))
    }

    private var lerngruppenabschnitt: some View {
        let gruppen = lerngruppen
        let zahl = stufen
        let angebot = zeilenangebot
        let zugeteilt = zuteilung(gruppen, zahl, angebot)
        // Live bis zur ersten Änderung in der Liste: die Gruppen, für die sich eine Zeile findet (E311, E312).
        let vorwahl = Set(zugeteilt.keys)
        let an = wahl.hochstufen ?? (zahl > 0)
        return LerngruppenWahl(
            gruppen: gruppen,
            mitgliederzahl: { speicher.lernende.verzeichnis?.mitgliederzahl($0) ?? 0 },
            gewaehlt: wahl.gewaehlt(vorwahl: vorwahl), breite: Self.spalteHaken,
            fuss: "Die gewählten Lerngruppen kommen mit ihren Personen und offenen Anliegen in die neue "
                + "Jahresdatei; alles Erledigte bleibt mit der bisherigen Planung im Archiv. Vorgewählt sind die "
                + "Gruppen, für die sich eine Zeile findet — die übernommene oder die eine mit dem neuen Namen. "
                + "Das Fach einer Gruppe folgt der gewählten Klasse/dem gewählten Kurs.",
            setzen: { wahl.haken = $0 },
            hochstufen: an,
            stufentext: Hochstufung.stufentext(bisher: speicher.bisherigesSchuljahr,
                                               neu: Lernendenbestand.schuljahr(fuer: start), stufen: zahl, an: an),
            hochstufenSetzen: { wahl.hochstufenSetzen($0, vorwahl: vorwahl) },
            namen: Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, wahl.name($0, stufen: zahl)) }),
            nameSetzen: { wahl.nameSetzen($1, fuer: $0, stufen: zahl, vorwahl: vorwahl) },
            zeilen: angebot,
            zuteilung: zugeteilt,
            zeileSetzen: { wahl.zeileWaehlen($1, fuer: $0, zuteilung: zugeteilt, vorwahl: vorwahl) })
    }

    /// Name und Zeile je gewählter Gruppe, beim Anlegen — die Zeilen an der
    /// Kennung, die `klassen` trägt, übernommene an ihrer alten (E308, E310).
    private func gruppenziele(_ gruppen: Set<String>, klassen: [Klasse]) -> [String: Gruppenwahl] {
        let alle = lerngruppen
        let zahl = stufen
        let zugeteilt = zuteilung(alle, zahl, zeilenangebot)
        var ziele: [String: Gruppenwahl] = [:]
        for g in alle where gruppen.contains(g.id) {
            ziele[g.id] = Gruppenwahl(name: wahl.name(g, stufen: zahl),
                                      zeile: Self.zielzeile(zugeteilt[g.id], eingaben: pruefung.kurse, klassen: klassen))
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
        let gruppen: Set<String>? = speicher.tresor != nil ? gewaehlteGruppen : nil
        let ziele = gruppen.map { gruppenziele($0, klassen: klassen) } ?? [:]
        let titel = titel
        let start = start
        let anzahl = anzahl
        let ersterSchultag = ersterSchultag
        // Ohne Verschlüsselung über einer bisherigen Planung erst fragen (E275).
        speicher.neuePlanungFragen(ort: .neuePlanung) { [speicher, schliessen] in
            // Kein Basisordner: Materialien werden mit vollem Pfad hinterlegt.
            speicher.neuePlanung(titel: titel, start: start, wochen: anzahl,
                                 basis: "", klassen: klassen, ersterSchultag: ersterSchultag,
                                 uebernahme: auswahl, lerngruppen: gruppen, ziele: ziele)
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
