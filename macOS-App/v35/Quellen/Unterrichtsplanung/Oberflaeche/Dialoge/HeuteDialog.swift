// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Was heute ansteht — mit einem Haken je Zeile.
///
/// **Kein eigener Stand:** Die Liste kommt je Durchlauf aus
/// `speicher.tagesliste`, der Haken geht über `erledigtUmschalten(_:)` in
/// dieselbe Planung wie der an der Kachel.
struct HeuteDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        let liste = speicher.tagesliste
        Dialograhmen(titel: "Heute anstehende Vorhaben",
                     unterzeile: unterzeile(liste), breite: 760, hoehe: 700) {
            if liste.istLeer {
                leerbereich(liste)
            } else {
                if !liste.amTag.isEmpty {
                    Section {
                        ForEach(liste.amTag) { posten in
                            Tageszeile(posten: posten)
                        }
                    } header: {
                        Text("Für heute eingetragen")
                    } footer: {
                        Text("Vorhaben mit einem Datum auf den \(liste.tag.deutsch) — dazu "
                             + "Prüfungen, die heute geschrieben werden.")
                    }
                }

                if !liste.inDerWoche.isEmpty {
                    Section {
                        ForEach(liste.inDerWoche) { posten in
                            Tageszeile(posten: posten)
                        }
                    } header: {
                        Text("Diese Woche, ohne festen Tag")
                    } footer: {
                        Text("Diese Vorhaben stehen in der laufenden Woche, tragen aber kein "
                             + "Datum. Was einen Tag trägt, der nicht heute ist, steht nicht "
                             + "hier — auch keine Prüfung, deren Termin auf einen anderen Tag "
                             + "der Woche fällt.")
                    }
                }

                Section {
                    Text("Der Haken ist derselbe wie an der Kachel im Raster und im Dialog des "
                         + "Vorhabens — es gibt nur einen Stand, alle drei zeigen ihn an. Ein "
                         + "Klick auf die Zeile springt im Raster zu dem Vorhaben und schließt "
                         + "diese Liste.")
                    .foregroundStyle(.secondary)
                }
            }
        } fuss: {
            Spacer(minLength: 0)
            Button("Fertig") { schliessen() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // ── Kopf und Leerzustand ──────────────────────────────────────────────

    private func unterzeile(_ liste: Tagesliste) -> String {
        var teile = [liste.tag.wochentagLang + ", " + liste.tag.deutsch]
        if let woche = liste.woche {
            let schulwoche = speicher.planung.flatMap { $0.wochenstand().schulwoche(woche) }
            teile.append(woche.beschriftung(schulwoche: schulwoche))
        }
        if liste.istLeer {
            teile.append("nichts eingetragen")
        } else {
            teile.append("\(liste.anzahl) Vorhaben · \(liste.offen) offen")
        }
        if let ferientag = liste.ferientag { teile.append("Ferien: " + ferientag) }
        return teile.joined(separator: " · ")
    }

    @ViewBuilder
    private func leerbereich(_ liste: Tagesliste) -> some View {
        Section {
            Text(leertext(liste)).foregroundStyle(.secondary)
        } header: {
            Text("Heute")
        } footer: {
            Text("Auf dieser Liste steht, was für heute datiert ist — und, solange kein Datum "
                 + "gesetzt wurde, was in der laufenden Woche geplant ist. Ein Datum bekommt "
                 + "ein Vorhaben im eigenen Dialog.")
        }
    }

    private func leertext(_ liste: Tagesliste) -> String {
        if liste.woche == nil {
            return "Der heutige Tag liegt außerhalb des Planungszeitraums."
        }
        if let ferientag = liste.ferientag {
            return "Heute sind Ferien („\(ferientag)“) — es steht nichts an."
        }
        if liste.lage.frei {
            return "Diese Woche ist unterrichtsfrei — es steht nichts an."
        }
        return "Für heute ist nichts eingetragen, und in der laufenden Woche steht kein "
            + "Vorhaben ohne festen Tag."
    }
}

// ── Eine Zeile ────────────────────────────────────────────────────────────

private enum Tagesspalten {
    static let haken: CGFloat = 22
    static let kurs: CGFloat = 168
    static let abstand: CGFloat = 10
}

/// Haken links, Vorhaben rechts — **zwei Knöpfe, keine verschachtelten:** Ein
/// Knopf im Knopf bekäme den Klick in AppKit beide Male.
private struct Tageszeile: View {
    let posten: Tagesposten

    @Environment(Planungsspeicher.self) private var speicher
    @State private var ueberfahren = false

    private var vorhaben: Vorhaben { posten.vorhaben }

    var body: some View {
        HStack(spacing: Tagesspalten.abstand) {
            Hakenknopf(aktiv: vorhaben.erledigt,
                       breite: Tagesspalten.haken,
                       hilfe: vorhaben.erledigt ? "Haken entfernen"
                                                : "Als durchgeführt kennzeichnen",
                       kennzeichnung: "Durchgeführt — " + posten.klasse.beschriftung
                           + ", " + vorhaben.anzeigeTitel) {
                speicher.erledigtUmschalten(vorhaben.id)
            }

            Button {
                speicher.zeigeVorhaben(vorhaben.id)
            } label: {
                HStack(spacing: Tagesspalten.abstand) {
                    HStack(spacing: 6) {
                        Farbpunkt(ton: Farbwelt.ton(posten.klasse.farbe), groesse: 8)
                        Text(posten.klasse.beschriftung).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(width: Tagesspalten.kurs, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(vorhaben.anzeigeTitel)
                            .strikethrough(vorhaben.erledigt, color: .secondary)
                            .foregroundStyle(vorhaben.erledigt ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        nebenzeile
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    marken
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect(cornerRadius: 6))
                .background(ueberfahren ? Systemfarben.verweiszeile : .clear,
                            in: .rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .onHover { ueberfahren = $0 }
            .help("Im Raster zeigen")
            .accessibilityLabel(bedienungshilfentext)
        }
    }

    /// Nur die Prüfung und der Kommentar tragen ein Zeichen. „Dringlich“ steht
    /// als Wort in der Nebenzeile — ein Warndreieck läse sich wie ein Fehler.
    @ViewBuilder
    private var marken: some View {
        HStack(spacing: 6) {
            if vorhaben.pruefung {
                Image(systemName: Zeichen.pruefung)
                    .font(.caption)
                    .foregroundStyle(Systemfarben.pruefung)
                    .help(posten.grund.pruefungHeute
                          ? "Prüfung heute" : "als Prüfung geführt")
            }
            if !vorhaben.kommentar.isEmpty {
                Image(systemName: Zeichen.stift)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(vorhaben.kommentar)
            }
        }
    }

    /// Die zweite Zeile: woher der Posten kommt, und was daran auffällt. Als
    /// `Text`, weil „dringlich“ die Farbe des Kachelrahmens trägt.
    private var nebenzeile: Text {
        var teile: [String] = [posten.grund.beschriftung]
        if let planung = speicher.planung, posten.ausserhalbSeinerWoche(start: planung.start) {
            teile.append("steht in einer anderen Woche")
        }
        if !vorhaben.kommentar.isEmpty { teile.append(vorhaben.kommentar) }

        let rest = Text(teile.joined(separator: " · "))
        guard vorhaben.dringend else { return rest }
            // Interpolation statt `+`: zwei `Text` zu addieren ist seit macOS 26 abgekündigt.
        return Text("\(Dringlichkeitsmarke.text) · \(rest)")
    }

    /// Tritt an die Stelle der abgeleiteten Beschriftung — was hier fehlt,
    /// hören die Bedienungshilfen nirgends.
    private var bedienungshilfentext: String {
        var text = posten.klasse.beschriftung + ", " + vorhaben.anzeigeTitel
        text += ", " + posten.grund.beschriftung
        // „Prüfung heute“ steht schon im Grund.
        if vorhaben.pruefung, !posten.grund.pruefungHeute {
            text += ", als Prüfung geführt"
        }
        if let planung = speicher.planung, posten.ausserhalbSeinerWoche(start: planung.start) {
            text += ", steht in einer anderen Woche"
        }
        if vorhaben.erledigt { text += ", durchgeführt" }
        if vorhaben.dringend { text += ", dringlich" }
        if !vorhaben.kommentar.isEmpty { text += ", Kommentar: " + vorhaben.kommentar }
        return text + " — im Raster zeigen"
    }
}
