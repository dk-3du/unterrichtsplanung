// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Eigener Typ, damit das Raster fallengelassenen Text nicht mit einem
    /// Vorhaben verwechselt.
    static let vorhabenverweis = UTType(exportedAs: "org.3ducation.unterrichtsplanung.vorhaben")
}

/// Was beim Ziehen mitgereicht wird: eine oder mehrere Kachelkennungen.
struct Vorhabenverweis: Codable, Transferable {
    var ids: [String]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .vorhabenverweis)
    }
}

/// Das Wochenraster: Ecke, Wochenkopfzeile, Klassenspalte, Rollbereich.
///
/// Beide Köpfe liegen **außerhalb** des Rollbereichs und werden nur verschoben.
/// Die Zeilenhöhen stehen vorab fest (`Zellenmass`) — erst dadurch dürfen die
/// Spalten nachladen.
struct Raster: View {
    @Environment(Planungsspeicher.self) private var speicher

    var body: some View {
        if let planung = speicher.planung {
            inhalt(planung)
        }
    }

    @ViewBuilder
    private func inhalt(_ planung: Planung) -> some View {
        let breite = CGFloat(speicher.spaltenbreite)
        let daten = Rasterdaten.bereitstellen(planung, stand: speicher.planungsstand,
                                              breite: breite)
        Rasteransicht(speicher: speicher, daten: daten, planung: planung,
                      sprung: speicher.sprung)
    }
}

// ── Kopfzeile ─────────────────────────────────────────────────────────────

struct Wochenkopfzeile: View {
    let stand: Wochenstand
    let breite: CGFloat
    /// `laufendeWoche` baut die ganze Wochenliste auf — deshalb einmal von
    /// außen bestimmt statt je Spalte.
    let vonHand: Set<Tag>
    let laufende: Int?

    var body: some View {
        // Kein nachladender Stapel: beim Rollen ändert sich nur die Verschiebung.
        HStack(spacing: 0) {
            ForEach(stand.wochen) { woche in
                Wochenkopf(woche: woche,
                           lage: stand.lage(woche),
                           schulwoche: stand.schulwoche(woche),
                           vonHand: vonHand.contains(woche.montag),
                           laufend: laufende == woche.nummer)
                    .frame(width: breite)
            }
        }
        .frame(width: breite * CGFloat(stand.wochen.count),
               height: Masse.wochenkopfHoehe, alignment: .topLeading)
    }
}

private struct Wochenkopf: View {
    let woche: Woche
    let lage: Wochenlage
    let schulwoche: Int?
    let vonHand: Bool
    let laufend: Bool

    @Environment(Planungsspeicher.self) private var speicher
    @State private var ueberfahren = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(woche.beschriftung(schulwoche: schulwoche))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(lage.frei ? .secondary : .primary)
                        .lineLimit(1)
                    if laufend {
                        Text("Heute")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(woche.spanne)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if lage.frei || lage.teilweise {
                    Text(lage.teilweise ? "\(lage.name) (\(lage.tage) von 5 Tagen)" : lage.name)
                        .font(.caption2)
                        .foregroundStyle(lage.teilweise ? Color.orange : Color.secondary)
                        .lineLimit(1)
                        .help(lage.teilweise
                              ? "\(lage.name) — \(lage.tage) von 5 Unterrichtstagen fallen aus"
                              : lage.name)
                }
            }
            Spacer(minLength: 0)

            if lage.frei, !vonHand {
                Image(systemName: Zeichen.ferien)
                    .foregroundStyle(Color.accentColor)
                    .help("\(lage.name) — unterrichtsfrei laut Ferienzeitraum (⌘E)")
                    .accessibilityLabel("Woche \(woche.kw): \(lage.name), unterrichtsfrei")
            } else {
                Einblendknopf(sichtbar: ueberfahren || vonHand, handlung: {
                    speicher.wocheFreiSchalten(woche)
                }) {
                    Image(systemName: Zeichen.ferien)
                        .foregroundStyle(vonHand ? Color.accentColor : Color.secondary)
                }
                .help(vonHand ? "Wieder als Unterrichtswoche führen"
                              : "Als unterrichtsfrei kennzeichnen")
                .accessibilityLabel(vonHand
                                    ? "Woche \(woche.kw) wieder als Unterrichtswoche"
                                    : "Woche \(woche.kw) als unterrichtsfrei")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if laufend { Color.accentColor.frame(height: 2) }
        }
        .trennlinie(.trailing)
        .onHover { ueberfahren = $0 }
        .animation(.easeOut(duration: 0.15), value: ueberfahren)
    }
}

struct Ecke: View {
    let wochen: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Klasse/Kurs").font(.subheadline.weight(.semibold))
            Text("\(wochen) Wochen").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .trennlinie(.trailing)
    }
}

/// Ein Klick öffnet die Datei; alles Weitere steht im Rechtsklickmenü — auch
/// eine andere Datei wählen, wie in ⌘K (E34).
private struct Kursdateiverweis: View {
    let klasse: Klasse
    let art: Kursdateiart

    @Environment(Planungsspeicher.self) private var speicher
    @State private var ueberfahren = false

    private var pfad: String { klasse.pfad(art) }
    private var voll: String { speicher.vollerPfad(pfad) }

    var body: some View {
        Button { speicher.dateiOeffnen(pfad) } label: {
            Verweiszeile(symbol: art.symbolGesetzt, text: Pfade.dateiName(pfad),
                         ueberfahren: ueberfahren)
        }
        .buttonStyle(.plain)
        .onHover { ueberfahren = $0 }
        .help(art.beschriftung + " öffnen: " + voll)
        .accessibilityLabel("\(art.beschriftung) von \(klasse.name) öffnen")
        .contextMenu {
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
        }
    }
}

/// Die gesetzte Zeile: Symbol und Text auf leiser Fläche, beim Überfahren
/// Akzent — so hoch wie das Angebot, damit `Zellenmass.kopfhoehe` für beide
/// gilt.
private struct Verweiszeile: View {
    let symbol: String
    let text: String
    let ueberfahren: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2)
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .foregroundStyle(ueberfahren ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 5)
        .frame(height: Zellenmass.hoeheVerwaltungszeile)
        .background(ueberfahren ? Systemfarben.verweiszeileAktiv : Systemfarben.verweiszeile,
                    in: .rect(cornerRadius: 5))
    }
}

/// Was fehlt, steht als Angebot da — in leiser Schrift, beim Überfahren
/// Akzent (E34 (a)).
private struct Angebotszeile: View {
    let text: String
    let ueberfahren: Bool

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(ueberfahren ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
            .padding(.horizontal, 5)
            .frame(height: Zellenmass.hoeheVerwaltungszeile)
    }
}

/// „+ Verwaltungsdatei“, „+ Curriculum“: ein Klick öffnet den Wähler — der
/// Weg, den sonst nur ⌘K bot (E34, E35 (b)).
private struct Kursdateiangebot: View {
    let klasse: Klasse
    let art: Kursdateiart

    @Environment(Planungsspeicher.self) private var speicher
    @State private var ueberfahren = false

    var body: some View {
        Button { speicher.kursdateiWaehlen(klasse: klasse.id, art: art) } label: {
            Angebotszeile(text: art.angebot, ueberfahren: ueberfahren)
        }
        .buttonStyle(.plain)
        .onHover { ueberfahren = $0 }
        .help("\(art.dateibeschriftung) für \(klasse.name) wählen")
        .accessibilityLabel("\(art.dateibeschriftung) für \(klasse.name) wählen")
    }
}

/// Die dritte Zeile: der Sitzplan der Klasse. Gesetzt öffnet ein Klick den
/// Editor, das Rechtsklickmenü sichert die PDF oder entfernt den Plan — mit
/// Rückfrage; ohne Plan das Angebot „+ Sitzplan“ (E34, E36). Gesperrte
/// Sitzpläne nennt der Speicher beim Klick.
private struct Sitzplanverweis: View {
    let klasse: Klasse

    @Environment(Planungsspeicher.self) private var speicher
    @State private var ueberfahren = false

    private var plan: Sitzplan? { speicher.sitzplan(fuer: klasse.id) }

    var body: some View {
        if let plan {
            let plaetze = "\(plan.tische.count) " + (plan.tische.count == 1 ? "Platz" : "Plätze")
            Button { speicher.sitzplanOeffnen(klasse: klasse.id) } label: {
                Verweiszeile(symbol: Zeichen.sitzplanGesetzt, text: "Sitzplan",
                             ueberfahren: ueberfahren)
            }
            .buttonStyle(.plain)
            .onHover { ueberfahren = $0 }
            .help("Sitzplan bearbeiten: " + plaetze)
            .accessibilityLabel("Sitzplan von \(klasse.name) bearbeiten, " + plaetze)
            .contextMenu {
                Button("Bearbeiten …") { speicher.sitzplanOeffnen(klasse: klasse.id) }
                Button("Als PDF sichern …") {
                    Sitzplandruck.alsPDFSichern(plan, klasse: klasse, speicher: speicher,
                                                ort: .hauptansicht)
                }
                Divider()
                Button("Sitzplan entfernen", role: .destructive) {
                    speicher.sitzplanEntfernen(klasse: klasse.id, ort: .hauptansicht)
                }
            }
        } else {
            Button { speicher.sitzplanOeffnen(klasse: klasse.id) } label: {
                Angebotszeile(text: "+ Sitzplan", ueberfahren: ueberfahren)
            }
            .buttonStyle(.plain)
            .onHover { ueberfahren = $0 }
            .help(speicher.sitzplaene.sperrhinweis
                  ?? ("Sitzplan für \(klasse.name) anlegen"
                      + (speicher.verschluesselt ? ""
                         : " — die Verschlüsselung ist ausgeschaltet; der Editor nennt den Weg (⌘,)")))
            .accessibilityLabel("Sitzplan für \(klasse.name) anlegen")
        }
    }
}

struct Klassenkopf: View {
    let klasse: Klasse
    @Environment(Planungsspeicher.self) private var speicher
    @State private var ueberfahren = false

    var body: some View {
        let ton = Farbwelt.ton(klasse.farbe)
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(klasse.name.isEmpty ? "Ohne Bezeichnung" : klasse.name)
                    .font(.headline)
                if !klasse.fach.isEmpty {
                    Text(klasse.fach).font(.subheadline).foregroundStyle(.secondary)
                }
                if !klasse.notiz.isEmpty {
                    Text(klasse.notiz).font(.caption).foregroundStyle(.tertiary)
                }
                // Drei Zeilen, immer — gesetzt oder als Angebot (E34);
                // `Zellenmass.kopfhoehe` zählt dieselben.
                ForEach(Kursdateiart.allCases) { art in
                    if klasse.hat(art) {
                        Kursdateiverweis(klasse: klasse, art: art)
                    } else {
                        Kursdateiangebot(klasse: klasse, art: art)
                    }
                }
                Sitzplanverweis(klasse: klasse)
            }
            Spacer(minLength: 0)
            Einblendknopf(sichtbar: ueberfahren, handlung: {
                speicher.offenerDialog = .klassen
            }) {
                Image(systemName: Zeichen.stift).foregroundStyle(.secondary)
            }
            .help("Klassen/Kurse und Fächer bearbeiten")
            .accessibilityLabel("Klasse/Kurs \(klasse.name) bearbeiten")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Reihenfolge zählt: Aufeinanderfolgende `.background` stapeln nach
        // hinten. Die Tönung muss VOR der deckenden Fläche stehen, sonst
        // verdeckt diese sie vollständig.
        .background(Kursfarben.farbe(ton).opacity(0.12))
        // Deckend, damit beim Rollen nichts durchscheint.
        .background(Systemfarben.fensterflaeche)
        .overlay(alignment: .leading) { Kursfarben.farbe(ton).frame(width: 3) }
        .trennlinie(.trailing)
        .trennlinie(.bottom)
        .onHover { ueberfahren = $0 }
        .animation(.easeOut(duration: 0.15), value: ueberfahren)
    }
}
