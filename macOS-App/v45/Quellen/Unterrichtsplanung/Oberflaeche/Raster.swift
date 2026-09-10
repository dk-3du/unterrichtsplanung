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

/// Ein Klick öffnet die Datei; alles Weitere steht im Rechtsklickmenü.
private struct Kursdateiverweis: View {
    let klasse: Klasse
    let art: Kursdateiart

    @Environment(Planungsspeicher.self) private var speicher
    @State private var ueberfahren = false

    private var pfad: String { klasse.pfad(art) }
    private var voll: String { speicher.vollerPfad(pfad) }

    var body: some View {
        Button { speicher.dateiOeffnen(pfad) } label: {
            HStack(spacing: 4) {
                Image(systemName: art.symbolGesetzt).font(.caption2)
                Text(Pfade.dateiName(pfad))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(ueberfahren ? Color.accentColor : Color.secondary)
            .padding(.vertical, 2)
            .padding(.horizontal, 5)
            .background(ueberfahren ? Systemfarben.verweiszeileAktiv : Systemfarben.verweiszeile,
                        in: .rect(cornerRadius: 5))
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
            Button("Verweis entfernen", role: .destructive) {
                speicher.kursdateiSetzen(klasse: klasse.id, art: art, pfad: nil)
            }
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
                // Nur die gesetzten — `Zellenmass.kopfhoehe` zählt dieselben.
                ForEach(Kursdateiart.allCases.filter { klasse.hat($0) }) { art in
                    Kursdateiverweis(klasse: klasse, art: art)
                }
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
