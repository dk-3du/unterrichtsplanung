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
            // Ohne die Tour — sie gehört zur neuen Planung, nicht zur geladenen.
            speicher.angeboteUndFragenPruefen(mitTour: false)
            speicher.updatesBeimStartPruefen()
            erscheinungDurchreichen()
        }
        // Ein Blatt trägt nur ein Blatt: Die Rückfrage wartet, bis der Dialog zu ist —
        // und ein vorgemerktes Blatt kommt erst, wenn das alte abgelöst ist.
        .onChange(of: speicher.offenerDialog) { _, neu in
            guard neu == nil else { return }
            Task { @MainActor in
                await Planungsspeicher.blaetterAbloesenAbwarten()
                speicher.naechstenDialogOeffnen()
                speicher.nachwahlPruefen()
                speicher.angeboteUndFragenPruefen()
                speicher.updateAnzeigenPruefen()
            }
        }
        // Die Planung kommt auch ohne Blatt: nach der Freigabe per Touch ID
        // (kein Blatt, kein Schließen), nach einem Öffnen von außen. Was auf
        // sie wartet, kommt dann hier — mit denselben Schranken wie oben.
        .onChange(of: speicher.hatPlanung) { _, hat in
            guard hat else { return }
            speicher.nachwahlPruefen()
            speicher.angeboteUndFragenPruefen()
            speicher.updatesBeimStartPruefen()
        }
        .onChange(of: speicher.erscheinung) { _, _ in erscheinungDurchreichen() }
        // Die Karte der Tour ist ein Popover von AppKit; ein Blatt darüber
        // wäre ein Widerspruch — es beendet die Tour.
        .onChange(of: speicher.tourSchritt) { _, schritt in
            Tourfuehrer.shared.nachfuehren(speicher)
            // Ein Blatt, das auf die Tour gewartet hat, kommt nach ihr — mit
            // Abstand zur Karte und zur Glaskapsel der Abschlussmeldung.
            guard schritt == nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))  // E561: Zeitgeber (Oberfläche) — das Update-Blatt mit Abstand nach der Tour
                speicher.updateAnzeigenPruefen()
            }
        }
        .onChange(of: speicher.dialogOffen) { _, offen in if offen { speicher.tourBeenden() } }
        // Der Name des Schrittes im Menü „Bearbeiten“ — hier, weil der Rumpf
        // von `Befehle` nur einmal läuft (S7).
        .onChange(of: speicher.widerrufenTitel + "·" + speicher.wiederholenTitel, initial: true) { _, _ in
            Menuetitel.nachfuehren(speicher)
        }
        // Der graue Stand von „Lernende …“ folgt der Bedingung, nicht erst dem
        // nächsten Öffnen des Menüs (B72).
        .onChange(of: speicher.lernendenBlattAngeboten) { _, _ in
            Task { @MainActor in LernendenBefehl.nachfuehren() }
        }
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
            case .update: UpdateDialog()
            case .updateNachfrage: UpdateNachfrageDialog()
            case .materialNachfrage: MaterialNachfrageDialog()
            case .rueckwegHinweis: RueckwegHinweisDialog()
            case .schuljahrOeffnen: SchuljahrOeffnenDialog()
            case .nachwahl: NachwahlDialog()
            case .sitzplan: SitzplanDialog()
            case .lernende: LernendenDialog()
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
                speicher.neuePlanungOeffnen()
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
                .help(speicher.sicherung.stillgrund)
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

        // Gerastert: Sonst würden die Zeilenhöhen bei jeder Mausbewegung neu gerechnet.
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

/// Die Kapseln der Meldungen — im Hauptfenster (`Melder`) und in den Blättern, die ihre Meldungen zeigen
/// (E476, E487). Nur die Anzeige: Die Ansage für VoiceOver gibt allein der `Melder`, sonst käme sie doppelt.
struct Meldungskapseln: View {
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
        .animation(.easeOut(duration: 0.22), value: speicher.meldungen.map(\.id))
    }
}

struct Melder: View {
    @Environment(Planungsspeicher.self) private var speicher

    var body: some View {
        // Zeigt das Blatt seine Meldungen selbst, bleibt die Kapsel hier still — die Ansage nicht (E489).
        let still = Meldungszeile.hauptfensterStill(speicher)
        Meldungskapseln()
        .opacity(still ? 0 : 1)
        .allowsHitTesting(!still)
        .accessibilityHidden(still)
        .padding(.bottom, 24)
        .onAppear {
            // Welche Meldungen stehen, fragt der Ansager beim Wiederaktivieren (E473).
            let s = speicher
            Ansager.gemeinsam.stehend = { Set(s.meldungen.map(\.id)) }
            // Was schon steht, bevor der Melder erscheint — beim Kaltstart aus dem Finder —, kommt mit (B108).
            Ansager.gemeinsam.ansagen(Melder.ansageeintraege(bisher: [], jetzt: speicher.meldungen))
        }
        .onChange(of: speicher.meldungen.map(\.id)) { alt, _ in
            Ansager.gemeinsam.ansagen(Melder.ansageeintraege(bisher: alt, jetzt: speicher.meldungen))
        }
    }

    /// Die Ansage selbst, gerufen vom `Ansager`, sobald der Fokus ruht: mit hohem Vorrang und
    /// abgesetzt an der App — Haupt- und Schlüsselfenster fehlen, solange die App nicht vorn ist, und
    /// mit einem Blatt vorn ist das Schlüsselfenster das Blatt (B105, E450).
    fileprivate static func ansagen(_ text: String) {
        guard let app = NSApp as NSApplication? else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Für die Prüfungen der Bündelung — die App sammelt über den `Ansager` (`ansageeintraege`, `zusammen`).
    /// Der Text der Ansage für VoiceOver nach einer Änderung der Meldungen: alle, die dazukamen, in
    /// einer Ansage und in ihrer Reihenfolge — VoiceOver unterbricht rasche Folgen einzelner Ansagen
    /// (B86, E422). Neu ist, was `bisher` nicht kennt, nicht, was die Zahl wachsen lässt:
    /// Verfällt zugleich eine alte, käme die neue sonst nicht an. Schon Angesagtes schweigt, derselbe
    /// gesprochene Text kommt in einer Änderung einmal. Eine Warnung sagt, dass sie eine ist — Symbol und
    /// Farbe in der Kapsel hört niemand (E422, V3 b). nil: nichts Neues.
    nonisolated static func ansagetext(bisher: [UUID], jetzt: [Meldung]) -> String? {
        let texte = ansagetexte(bisher: bisher, jetzt: jetzt)
        return texte.isEmpty ? nil : zusammen(texte)
    }

    /// Die gesprochenen Texte der neuen Meldungen, einzeln und ohne Doppel — zusammengefügt wird erst beim
    /// Hinausgeben, damit eine wartende Ansage nichts doppelt sagt.
    nonisolated static func ansagetexte(bisher: [UUID], jetzt: [Meldung]) -> [String] {
        ansageeintraege(bisher: bisher, jetzt: jetzt).map(\.text)
    }

    /// Wie `ansagetexte`, mit der Meldung dahinter und ihrer Art — der `Ansager` lässt einen Hinweis
    /// verfallen, der beim Wiederaktivieren nicht mehr steht (E473).
    nonisolated static func ansageeintraege(bisher: [UUID], jetzt: [Meldung]) -> [Ansageeintrag] {
        let angesagt = Set(bisher)
        var eintraege: [Ansageeintrag] = []
        for meldung in jetzt where !angesagt.contains(meldung.id) {
            let gesprochen = meldung.art == .warnung ? "Warnung: " + meldung.text : meldung.text
            eintraege = Ansager.gesammelt(eintraege, [Ansageeintrag(id: meldung.id, warnung: meldung.art == .warnung,
                                                                    text: gesprochen)])
        }
        return eintraege
    }

    /// Mehrere Ansagen in einer, mit Satzende dazwischen (B86).
    nonisolated static func zusammen(_ texte: [String]) -> String {
        guard let letzter = texte.last else { return "" }
        return (texte.dropLast().map(satzende) + [letzter]).joined(separator: " ")
    }

    /// Ohne Satzzeichen am Ende liefe der nächste Text ohne Pause an.
    private nonisolated static func satzende(_ text: String) -> String {
        let satz = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let zeichen = satz.last, !".!?…".contains(zeichen) else { return satz }
        return satz + "."
    }
}

// ── Die Ansage der Meldungen ──────────────────────────────────────────────

/// Eine ausstehende Ansage: der gesprochene Text, ob er eine Warnung ist, und die Meldung dahinter.
struct Ansageeintrag: Equatable, Sendable {
    let id: UUID
    let warnung: Bool
    let text: String
}

/// Sagt Meldungen an, sobald der Fokus ruht (B108, E461): Erscheint eine Meldung im Augenblick eines
/// Fokuswechsels — ein Dialog schließt, die App kommt aus dem Finder nach vorn —, spricht VoiceOver, was der
/// Wechsel auslöst, und eine Ansage im selben Augenblick entfällt, auch mit hohem Vorrang. Darum wartet sie,
/// bis die App vorn ist, kein freier Dialog steht und der letzte Fokuswechsel `ruhe` zurückliegt; was
/// derweil dazukommt, geht in derselben Ansage hinaus. Gemessen wird mit der Laufzeit seit dem Start des
/// Rechners — eine umgestellte Uhr verschiebt nichts.
@MainActor
final class Ansager {
    static let gemeinsam = Ansager()

    /// So lange nach dem letzten Fokuswechsel wartet eine Ansage.
    nonisolated static let ruhe: TimeInterval = 0.8

    /// Ist die App vorn, wartet eine Ansage nie länger — dann geht sie hinaus, auch wenn ein Dialog steht
    /// oder der Fokus noch wechselt. Im Hintergrund ruht sie ohne Takt, bis die App wieder vorn ist; ein
    /// Hinweis, dessen Meldung dann nicht mehr steht, verfällt, Warnungen bleiben (E473).
    nonisolated static let hoechstens: TimeInterval = 30

    private var ausstehend: [Ansageeintrag] = []
    private var letzterWechsel: TimeInterval = 0
    private var wartet = false
    /// Die Ansage ruhte im Hintergrund — vor dem nächsten Warten verfällt ein Hinweis, der nicht mehr steht.
    private var geruht = false
    private var beobachter: [NSObjectProtocol] = []
    /// Welche Meldungen gerade stehen — gesetzt vom Melder; ohne ihn verfällt nichts.
    var stehend: (@MainActor () -> Set<UUID>)?

    /// Ruht der Fokus? Eine reine Funktion, damit die Prüfungen sie halten.
    nonisolated static func fokusRuht(appVorn: Bool, freieDialoge: Int, seitWechsel: TimeInterval) -> Bool {
        appVorn && freieDialoge == 0 && seitWechsel >= ruhe
    }

    /// Was die wartende Ansage als Nächstes tut.
    enum Schritt: Equatable, Sendable { case sprechen, warten, ruhen }

    /// Die Entscheidung je Blick — rein, damit die Prüfungen sie halten.
    nonisolated static func naechsterSchritt(appVorn: Bool, freieDialoge: Int, seitWechsel: TimeInterval,
                                             seitBeginn: TimeInterval) -> Schritt {
        if !appVorn { return .ruhen }
        if fokusRuht(appVorn: appVorn, freieDialoge: freieDialoge, seitWechsel: seitWechsel) { return .sprechen }
        if appVorn && seitBeginn >= hoechstens { return .sprechen }
        return .warten
    }

    /// Neu Gemeldetes zu dem, was schon wartet — derselbe gesprochene Text einmal, an seiner ersten Stelle, mit
    /// der jüngsten Meldung, denn sie bleibt am längsten stehen (I2-04, Z-AV10-05).
    nonisolated static func gesammelt(_ ausstehend: [Ansageeintrag], _ neu: [Ansageeintrag]) -> [Ansageeintrag] {
        var alle = ausstehend
        for eintrag in neu {
            if let stelle = alle.firstIndex(where: { $0.text == eintrag.text }) {
                alle[stelle] = eintrag
            } else {
                alle.append(eintrag)
            }
        }
        return alle
    }

    /// Was nach dem Wiederaktivieren noch angesagt wird.
    nonisolated static func nachDemAktivieren(_ ausstehend: [Ansageeintrag], stehend: Set<UUID>) -> [Ansageeintrag] {
        ausstehend.filter { $0.warnung || stehend.contains($0.id) }
    }

    private static var jetzt: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Fokuswechsel mitzählen: Die App kommt nach vorn, ein Fenster — auch ein Blatt — wird Schlüsselfenster.
    /// Angemeldet beim Start, vor dem Aktivieren; die Anmeldung selbst zählt als Wechsel — was davor lag, sah
    /// niemand.
    func beobachten() {
        guard beobachter.isEmpty else { return }
        letzterWechsel = Ansager.jetzt
        for name in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification] {
            beobachter.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { meldung in
                let aktiviert = meldung.name == NSApplication.didBecomeActiveNotification
                MainActor.assumeIsolated {
                    Ansager.gemeinsam.letzterWechsel = Ansager.jetzt
                    if aktiviert { Ansager.gemeinsam.aktiviert() }
                }
            })
        }
    }

    func ansagen(_ eintraege: [Ansageeintrag]) {
        guard !eintraege.isEmpty else { return }
        beobachten()
        ausstehend = Ansager.gesammelt(ausstehend, eintraege)
        warten()
    }

    /// Die App kommt wieder nach vorn: Ruhte eine Ansage, wartet sie nun wie sonst, bis der Fokus ruht.
    private func aktiviert() {
        warten()
    }

    /// Ruhte die Ansage im Hintergrund, verfällt beim ersten Blick mit der App vorn ein Hinweis, der nicht mehr
    /// steht (E473) — eingelöst in der Schleife, gleich, ob das Aktivieren oder eine neue Meldung zuerst ankommt
    /// und wer `warten()` zuerst ruft (Z-AV10-06, Z-AV10-11).
    private func warten() {
        guard !wartet, !ausstehend.isEmpty else { return }
        wartet = true
        let beginn = Ansager.jetzt
        Task { @MainActor [weak self] in
            guard let self else { return }
            while true {
                let vorn = (NSApp as NSApplication?)?.isActive ?? false
                if vorn && geruht {
                    geruht = false
                    if let stehend { ausstehend = Ansager.nachDemAktivieren(ausstehend, stehend: stehend()) }
                    if ausstehend.isEmpty {
                        wartet = false
                        return
                    }
                }
                switch Ansager.naechsterSchritt(appVorn: vorn, freieDialoge: Dialogort.freieDialoge,
                                                seitWechsel: Ansager.jetzt - letzterWechsel,
                                                seitBeginn: Ansager.jetzt - beginn) {
                case .warten:
                    try? await Task.sleep(for: .milliseconds(150))  // E561: Zeitgeber (Oberfläche) — der Ansager wartet auf freie Dialoge
                case .ruhen:
                    // Hinten ohne Takt — das Aktivieren weckt sie (E473).
                    wartet = false
                    geruht = true
                    return
                case .sprechen:
                    wartet = false
                    let text = Melder.zusammen(ausstehend.map(\.text))
                    ausstehend = []
                    Melder.ansagen(text)
                    return
                }
            }
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
            // Nach der liegenden Wicklung, nicht nach dem Gerät (E141).
            Text(speicher.entsperrungLaeuft
                 ? "Die Freigabe über \(Tresor.freigabeName(biometrie: speicher.geraeteBiometrie)) steht noch aus."
                 : "Die Planung auf diesem Mac ist verschlüsselt. Zum Öffnen braucht es "
                   + "\(Tresor.freigabeName(biometrie: speicher.geraeteBiometrie)), die Passphrase oder den "
                   + "Wiederherstellungsschlüssel.")
        } actions: {
            HStack(spacing: 12) {
                Button {
                    speicher.entsperrungFortsetzen()
                } label: {
                    // Kurz: Der Leerzustand kürzt lange Beschriftungen mit „…“.
                    Label(speicher.enklaveMoeglich
                          ? (speicher.geraeteBiometrie ? "Mit Touch ID" : "Mit Anmeldepasswort")
                          : "Entsperren …",
                          systemImage: speicher.enklaveMoeglich
                              ? (speicher.geraeteBiometrie ? Zeichen.touchID : Zeichen.schluessel)
                              : Zeichen.schlossOffen)
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
                    speicher.neuePlanungOeffnen()
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
