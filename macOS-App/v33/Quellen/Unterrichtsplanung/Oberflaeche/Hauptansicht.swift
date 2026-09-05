// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct Hauptansicht: View {
    @Environment(Planungsspeicher.self) private var speicher
    @FocusState private var suchfeldFokus: Bool

    var body: some View {
        @Bindable var speicher = speicher

        Group {
            if !speicher.hatPlanung {
                Leerzustand()
            } else {
                Raster()
            }
        }
        // Kein eigener Hintergrund: Liquid Glass rechnet mit der Fensterfläche des Systems.
        .navigationTitle($speicher.planungstitel)
        .navigationSubtitle(speicher.kennzahlen)
        .toolbar { werkzeugleiste }
        .searchable(text: $speicher.suchbegriff, placement: .toolbar,
                    prompt: "Vorhaben durchsuchen")
        .searchFocused($suchfeldFokus)
        .onReceive(NotificationCenter.default.publisher(for: Suchfeldbefehl.name)) { _ in
            suchfeldFokus = true
        }
        .onChange(of: suchfeldFokus) { _, hat in speicher.suchfeldAktiv = hat }
        // Kein `preferredColorScheme` neben `NSApp.appearance`: zwei Quellen ergeben
        // je Durchlauf eine neue `NSCompositeAppearance`, +15 MB je zwei Sekunden.
        .overlay(alignment: .bottom) { Melder() }
        .onAppear {
            speicher.starten()
            speicher.ersteinrichtungPruefen()
            erscheinungDurchreichen()
        }
        // Ein Blatt trägt nur ein Blatt: die Rückfrage wartet, bis der Dialog zu ist —
        // und ein vorgemerktes Blatt kommt erst, wenn das alte abgelöst ist.
        .onChange(of: speicher.offenerDialog) { _, neu in
            guard neu == nil else { return }
            Task { @MainActor in
                await Planungsspeicher.blaetterAbloesenAbwarten()
                speicher.naechstenDialogOeffnen()
                speicher.ersteinrichtungPruefen()
                speicher.tourAnbietenPruefen()
            }
        }
        .onChange(of: speicher.erscheinung) { _, _ in erscheinungDurchreichen() }
        // Die Karte der Tour ist ein Popover von AppKit; ein Blatt darüber
        // wäre ein Widerspruch — es beendet die Tour.
        .onChange(of: speicher.tourSchritt) { _, _ in Tourfuehrer.shared.nachfuehren(speicher) }
        .onChange(of: speicher.dialogOffen) { _, offen in if offen { speicher.tourBeenden() } }
        .sheet(item: $speicher.offenerDialog) { fenster in
            switch fenster {
            case .neuePlanung: NeuePlanungDialog()
            case .ersteinrichtung: ErsteinrichtungDialog()
            case .klassen: KlassenDialog()
            case .ferien: FerienDialog()
            case .pruefungen: PruefungsDialog()
            case .heute: HeuteDialog()
            case .einstellungen: EinstellungenDialog()
            case .hilfe: HilfeDialog()
            case .entsperren: EntsperrenDialog()
            case .verschluesselung: VerschluesselungDialog()
            case .tour: TourDialog()
            }
        }
        .sheet(item: $speicher.vorhabenDialog) { entwurf in
            VorhabenDialog(start: entwurf)
        }
        .rueckfrage(speicher, ort: .hauptansicht)
    }

    // ── Werkzeugleiste ────────────────────────────────────────────────────
    // Zwischen jedem Abschnitt derselbe `ToolbarSpacer(.fixed)`, sonst rücken Nachbarn
    // zusammen; `.glassProminent` legte eine zweite Glaskapsel über das geteilte `ToolbarItem`.

    @ToolbarContentBuilder
    private var werkzeugleiste: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                speicher.offenerDialog = .neuePlanung
            } label: {
                Label("Neue Planung", systemImage: Zeichen.neuePlanung)
            }
            .help("Neue Planungsdatei anlegen (⌘N)")

            Button {
                speicher.importDialog()
            } label: {
                Label("Öffnen", systemImage: Zeichen.einfuhr)
            }
            .help("Planungsdatei öffnen (⌘O)")

            if speicher.hatPlanung {
                Button {
                    speicher.exportieren()
                } label: {
                    Label("Sichern", systemImage: Zeichen.export)
                }
                .help(speicher.verschluesselt ? "Als verschlüsselte JSON-Datei sichern (⌘S)"
                                              : "Als JSON-Datei sichern (⌘S)")
            }
        }

        if speicher.hatPlanung {
            ToolbarSpacer(.fixed)

            ToolbarItemGroup {
                Button {
                    speicher.zurLaufendenWoche()
                } label: {
                    Label("Zur laufenden Woche", systemImage: Zeichen.kalender)
                }
                .help("Zur laufenden Woche (⌘J)")

                Button {
                    speicher.offenerDialog = .heute
                } label: {
                    Label("Heute anstehende Vorhaben", systemImage: Zeichen.tagesliste)
                }
                .help("Heute anstehende Vorhaben — Liste zum Abhaken (⌘D)")

                Button {
                    speicher.offenerDialog = .klassen
                } label: {
                    Label("Klassen/Kurse", systemImage: Zeichen.klassen)
                }
                .help("Klassen/Kurse, Fachfarben und Reihenfolge (⌘K)")

                Button {
                    speicher.offenerDialog = .ferien
                } label: {
                    Label("Ferien", systemImage: Zeichen.ferien)
                }
                .help("Ferien und unterrichtsfreie Zeiten (⌘E)")

                Button {
                    speicher.offenerDialog = .pruefungen
                } label: {
                    Label("Prüfungen", systemImage: Zeichen.pruefung)
                }
                .help("Übersicht aller Prüfungstermine (⌘R)")

                Button {
                    speicher.offenerDialog = .einstellungen
                } label: {
                    Label("Einstellungen", systemImage: Zeichen.einstellungen)
                }
                .help("Zeitraum, Sicherungskopie und Verschlüsselung (⌘,)")
            }
        }

        if speicher.verschluesselungsstand == .an {
            ToolbarSpacer(.fixed)

            ToolbarItem {
                Button {
                    speicher.dialogOeffnen(.verschluesselung)
                } label: {
                    Label("Verschlüsselt", systemImage: Zeichen.schloss)
                }
                .help("Die Planung ist verschlüsselt — Passphrase, Schlüssel und Wicklungen")
            }
        }

        if speicher.hatPlanung {
            ToolbarSpacer(.fixed)

            ToolbarItem {
                Breitenregler()
            }
        }

        if speicher.sicherungLiegtStill {
            ToolbarSpacer(.fixed)

            ToolbarItem {
                Button {
                    speicher.exportieren()
                } label: {
                    Label("Sicherung liegt still", systemImage: Zeichen.warnung)
                }
                .help("Die Autosicherung schreibt gerade nicht. "
                      + "Hier als JSON-Datei sichern (⌘S).")
            }
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Darstellungsschalter()
        }
    }

    /// Auswahldialoge, Menüs und Glasflächen folgen `NSApp.appearance`; ohne
    /// diesen Schritt bliebe die halbe Anwendung im alten Thema stehen.
    private func erscheinungDurchreichen() {
        NSApp?.appearance = switch speicher.erscheinung {
        case .system: nil
        case .hell: NSAppearance(named: .aqua)
        case .dunkel: NSAppearance(named: .darkAqua)
        }
    }
}

// ── Spaltenbreite ─────────────────────────────────────────────────────────

struct Breitenregler: View {
    @Environment(Planungsspeicher.self) private var speicher

    var body: some View {
        @Bindable var speicher = speicher

        // Gerastert: sonst würden die Zeilenhöhen bei jeder Mausbewegung neu gerechnet.
        Slider(value: $speicher.spaltenbreite,
               in: Kennwerte.spalteMin...Kennwerte.spalteMax,
               step: Kennwerte.spalteRaster) {
            Text("Spaltenbreite")
        }
        .labelsHidden()
        .frame(width: 162)
        .help("Spaltenbreite der Wochen — drei Stufen (⌘+ und ⌘−)")
        .accessibilityLabel("Spaltenbreite")
    }
}

// ── Hell / Dunkel ─────────────────────────────────────────────────────────

/// Hell oder dunkel — ein Knopf, keine Auswahl. Der dritte Zustand,
/// „Systemvorgabe“, bleibt im Menü „Darstellung“ erreichbar; steht sie,
/// schaltet der Knopf von dem weg, was gerade tatsächlich gilt.
struct Darstellungsschalter: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.colorScheme) private var schema

    var body: some View {
        Button {
            speicher.erscheinung = dunkelAktiv ? .hell : .dunkel
        } label: {
            Label("Darstellung umschalten", systemImage: Zeichen.darstellung)
        }
        .help(dunkelAktiv ? "Auf helle Darstellung umschalten "
                          + "(„Systemvorgabe“ im Menü „Darstellung“)"
                          : "Auf dunkle Darstellung umschalten "
                          + "(„Systemvorgabe“ im Menü „Darstellung“)")
        .accessibilityLabel(dunkelAktiv ? "Auf helle Darstellung umschalten"
                                        : "Auf dunkle Darstellung umschalten")
    }

    /// Was gerade wirklich gilt.
    private var dunkelAktiv: Bool {
        switch speicher.erscheinung {
        case .dunkel: true
        case .hell: false
        case .system: schema == .dark
        }
    }
}

// ── Meldungen ─────────────────────────────────────────────────────────────

struct Melder: View {
    @Environment(Planungsspeicher.self) private var speicher

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                ForEach(speicher.meldungen) { meldung in
                    Label {
                        Text(meldung.text).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: meldung.art == .warnung ? Zeichen.warnung : Zeichen.haken)
                            .foregroundStyle(meldung.art == .warnung ? Color.orange : Color.green)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 620, alignment: .leading)
                    .glassEffect(.regular, in: .capsule)
                    // Nur die Kapsel selbst fängt ab, sonst läge eine unsichtbare
                    // Fläche über dem Raster. `allowsHitTesting(false)` am Behälter
                    // spräche die Geste mit ab — es sperrt den ganzen Teilbaum.
                    .contentShape(.capsule)
                    .onTapGesture { speicher.meldungSchliessen(meldung.id) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(.bottom, 24)
        .animation(.easeOut(duration: 0.22), value: speicher.meldungen.map(\.id))
        .onChange(of: speicher.meldungen.map(\.id)) { alt, neu in
            guard neu.count > alt.count, let letzte = speicher.meldungen.last else { return }
            AccessibilityNotification.Announcement(letzte.text).post()
        }
    }
}

// ── Leerzustand ───────────────────────────────────────────────────────────

struct Leerzustand: View {
    @Environment(Planungsspeicher.self) private var speicher

    var body: some View {
        if speicher.verschluesselungsstand == .gesperrt {
            gesperrt
        } else {
            willkommen
        }
    }

    /// Die Ablage ist verschlüsselt und noch nicht offen: kein „Willkommen“,
    /// keine neue Planung — nur der Weg zur Freigabe.
    private var gesperrt: some View {
        ContentUnavailableView {
            Label("Planung verschlüsselt", systemImage: Zeichen.schloss)
        } description: {
            Text(speicher.entsperrungLaeuft
                 ? "Die Freigabe über Touch ID oder das Anmeldepasswort steht noch aus."
                 : "Die Planung auf diesem Mac ist verschlüsselt. Zum Öffnen braucht es "
                   + "Touch ID, das Anmeldepasswort, die Passphrase oder den "
                   + "Wiederherstellungsschlüssel.")
        } actions: {
            HStack(spacing: 12) {
                Button {
                    speicher.entsperrungFortsetzen()
                } label: {
                    // Kurz: Der Leerzustand kürzt lange Beschriftungen mit „…“.
                    Label(speicher.enklaveMoeglich ? "Mit Touch ID" : "Entsperren …",
                          systemImage: speicher.enklaveMoeglich ? Zeichen.touchID : Zeichen.schlossOffen)
                }
                .buttonStyle(.glassProminent)
                if speicher.enklaveMoeglich {
                    Button {
                        speicher.entsperrungMitBlatt()
                    } label: {
                        Label("Mit Passphrase …", systemImage: Zeichen.schluessel)
                    }
                }
            }
            .controlSize(.large)
            .disabled(speicher.entsperrungLaeuft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var willkommen: some View {
        ContentUnavailableView {
            Label("Willkommen", systemImage: Zeichen.raster)
        } description: {
            Text("Lege eine neue Planungsdatei an — du bestimmst die Anzahl der "
                 + "Unterrichtswochen sowie deine Klassen und Kurse — oder öffne eine gesicherte "
                 + "JSON-Datei.")
        } actions: {
            HStack(spacing: 12) {
                Button {
                    speicher.offenerDialog = .neuePlanung
                } label: {
                    Label("Neue Planung", systemImage: Zeichen.plus)
                }
                .buttonStyle(.glassProminent)

                Button {
                    speicher.importDialog()
                } label: {
                    Label("Datei öffnen", systemImage: Zeichen.einfuhr)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
