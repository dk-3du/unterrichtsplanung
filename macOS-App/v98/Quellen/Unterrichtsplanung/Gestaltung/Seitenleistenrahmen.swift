// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Maße der Blätter mit Seitenleiste (v95, E1101) — gemeinsam für alle Blätter mit diesem Rahmen.
enum Seitenleistenmass {
    /// Die Breite der Leiste. Vermessen statt geschätzt (Systemschrift der Leiste 13 pt, wie am Bild der Vorlage
    /// abgelesen, E1120): vom Rand der Spalte bis zum Text 55 pt, nach dem Text bis zum Rand 12 + 18,5 pt; der
    /// breiteste Eintrag mit Plakette ist „Hausaufgabe ✓“ (80,2 + 8 + 11,2 pt), dazu oben der Blatttitel „Vorhaben
    /// bearbeiten“ (149,7 pt) — zusammen knapp 199 pt. 250 lässt Reserve (Nutzer: „Die Breite … stimmt nun.“).
    /// In den Einstellungen ist „Sicherungskopie“ der breiteste Eintrag (100,5 pt), der Titel „Einstellungen“ 96,5 pt
    /// (E1111).
    static let breite: CGFloat = 250
    /// Abstand der Glasfläche vom Rand der Spalte bzw. des Blatts — in der Vorlage 8,5 pt.
    static let glasrand: CGFloat = 8
    /// Ecken der Glasfläche: konzentrisch zur Blattecke, abzüglich des Glasrands.
    static let glasecke: CGFloat = 18
    /// Abstand eines Blatts zum unteren Rand der sichtbaren Fläche — über dem Dock (E1150). Wo es oben steht, entscheidet
    /// macOS (siehe `hoechstens`).
    static let abstandUnten: CGFloat = 40
    /// So klein wird ein Blatt höchstens — Titel, Leiste mit sieben Einträgen, Kopf und Fuß des Inhalts haben Platz;
    /// das greift nur, wenn das Hauptfenster sehr weit unten steht (E1150).
    static let mindesthoehe: CGFloat = 480

    /// Die Höhe eines Blatts nach E1150: wie bestellt, höchstens `hoechstens`, nie unter `mindesthoehe`. Reicht der Platz
    /// — bei 820 mindestens 860 pt von der Unterkante des Fensterkopfs bis zum unteren Rand der sichtbaren Fläche, und das
    /// Fenster steht hoch genug —, bleibt es bei der bestellten Höhe; sonst rollt der Inhalt (R-BG8b-04).
    static func begrenzt(_ bestellt: CGFloat, hoechstens: CGFloat) -> CGFloat {
        min(bestellt, max(mindesthoehe, hoechstens))
    }

    /// Wie hoch ein Blatt höchstens sein darf, damit es `abstandUnten` über dem unteren Rand der sichtbaren Fläche endet
    /// (E1150). Gemessen unter macOS 26: Ein Blatt steht senkrecht mittig im ganzen Fenster (den Kopf eingerechnet), aber
    /// nie über der Unterkante des Fensterkopfs — ist es dafür zu hoch, liegt es dort an und ragt unten aus dem Fenster.
    /// Unten endet es also bei min(Kopfunterkante − h, (Fensterunterkante + Fensteroberkante − h) / 2); beides muss
    /// `abstandUnten` über `sichtbarUnten` bleiben. Bildschirmkoordinaten, y nach oben.
    static func hoechstens(kopfUnten: CGFloat, fensterOben: CGFloat, fensterUnten: CGFloat,
                           sichtbarUnten: CGFloat) -> CGFloat {
        min(kopfUnten - sichtbarUnten - abstandUnten,
            fensterUnten + fensterOben - 2 * sichtbarUnten - 2 * abstandUnten)
    }

    /// Die bestellte Höhe, begrenzt nach Lage und Bildschirm des Hauptfensters (E1150) — auch minimiert gilt sein Rahmen
    /// (R-BG8bn-05). Ohne Hauptfenster auf einem Bildschirm die bestellte: Prüfungen ohne Fenster, Abbilder (sie liegen
    /// außerhalb jedes Bildschirms). Je Blatt einmal, über `Blatthoehe`.
    @MainActor static func hoehe(_ bestellt: CGFloat) -> CGFloat {
        guard let app = NSApp,
              var fenster = app.mainWindow
                ?? app.windows.first(where: { ($0.isVisible || $0.isMiniaturized) && $0.sheetParent == nil && !($0 is NSPanel) })
        else { return bestellt }
        while let eltern = fenster.sheetParent { fenster = eltern }
        guard fenster.isVisible || fenster.isMiniaturized, let schirm = fenster.screen else { return bestellt }
        return begrenzt(bestellt, hoechstens: hoechstens(kopfUnten: fenster.frame.minY + fenster.contentLayoutRect.maxY,
                                                         fensterOben: fenster.frame.maxY,
                                                         fensterUnten: fenster.frame.minY,
                                                         sichtbarUnten: schirm.visibleFrame.minY))
    }
}

/// Die Höhe eines Blatts, beim ersten Zeichnen einmal nach Lage und Bildschirm bestimmt (E1150) — im `@State` des Blatts
/// gehalten: Sie bleibt fest, solange das Blatt offen ist, gilt auch für den Bogen darauf (R-BG8b-01) und wird nicht bei
/// jedem Neuaufbau des Blatts neu gelesen (R-BG8b-06).
@MainActor
final class Blatthoehe {
    let bestellt: CGFloat
    private(set) lazy var wert: CGFloat = Seitenleistenmass.hoehe(bestellt)

    init(_ bestellt: CGFloat) {
        self.bestellt = bestellt
    }
}

/// Ein Blatt mit Seitenleiste (v95, E1101–E1111): links die Einträge
/// auf einer Glasfläche, oben in ihr Titel und Unterzeile des Blatts; rechts oben eine gläserne Kapsel mit Zurück und
/// Vorwärts und der Name des gewählten Eintrags; darunter sein Inhalt, unten der Fuß mit der Meldungszeile wie im
/// `Dialograhmen` (E476, E487, E855; derselbe Baustein `Blattfuss`).
///
/// **Eine Komponente für alle Blätter mit Leiste**: Die Blätter reichen nur Einträge, Namen,
/// Symbole, Plaketten, die Auswahl, den Inhalt und den Fuß herein. Die Leiste baut allein der Rahmen — über
/// `Seitenleiste` (eigene Datei `Seitenleiste.swift`), die einzige Stelle, an der sie getauscht wird. Ein Fix an der
/// Leiste trägt so alle Blätter zugleich (E1120).
///
/// **Die Spalte ist von Hand gesetzt** (E1111): In einer `NavigationSplitView` übergingen die
/// ersten beiden Versuche deren Breite (≈ 138 pt statt 220 bzw. 250). Jetzt: ein `HStack` mit fester Breite, darin die Leiste
/// auf einer Glasfläche (`glassEffect`), Abstand und Ecken wie in der Vorlage. Ebenfalls von Hand: die Kapsel — Zurück und
/// Vorwärts als gläserne Kapsel gibt es in SwiftUI nur in der Werkzeugleiste eines Fensters. Den Verlauf führt der Rahmen
/// selbst — jeder Wechsel der Auswahl geht hinein, gleich woher er kommt.
///
/// **Inhalt in fester Höhe** (E1110; sonst standen Einstellungen und ⌘K bis auf den Fuß leer): Das Blatt ist
/// fest `breite` × `hoehe`; der Inhalt bekommt, was zwischen Kopf und Fuß bleibt, nie mehr. Die Höhe legt das Blatt beim
/// Öffnen fest (`Blatthoehe`, E1150).
struct Seitenleistenrahmen<Eintrag: Hashable, Koerper: View, Fuss: View>: View {
    let titel: String
    let unterzeile: String?
    let eintraege: [Eintrag]
    @Binding var auswahl: Eintrag
    let name: (Eintrag) -> String
    let symbol: (Eintrag) -> String
    /// Das Kennzeichen eines Eintrags als Plakette am Ende der Zeile; nil für keine.
    let plakette: (Eintrag) -> String?
    let breite: CGFloat
    let hoehe: CGFloat
    /// Statt des einfachen Schließens, wenn vorher nachzufragen ist — wie im `Dialograhmen`.
    let beimSchliessen: (() -> Void)?
    /// Wie im `Dialograhmen`: welches Blatt das ist, wenn es seine Meldungen zeigen kann.
    let meldungsblatt: Meldungszeile.Blatt?
    /// Wie im `Dialograhmen`: Das Blatt hat seine Zeile an einen Bogen darauf abgegeben.
    let zeileAbgegeben: Bool
    let koerper: Koerper
    let fuss: Fuss

    @State private var verlauf = Blaetterverlauf<Eintrag>()
    /// Zählt die Seitenwechsel dieses Blatts für die Felder seiner Seiten (R-BG5d-01, R-BG8-W2-03).
    @State private var seitenwechsel = Seitenwechsel()
    @Environment(\.dismiss) private var schliessen
    /// Ohne Speicher (ein Abbild) sperrt ⎋ nichts.
    @Environment(Planungsspeicher.self) private var speicher: Planungsspeicher?

    init(titel: String, unterzeile: String? = nil, eintraege: [Eintrag], auswahl: Binding<Eintrag>,
         name: @escaping (Eintrag) -> String, symbol: @escaping (Eintrag) -> String,
         plakette: @escaping (Eintrag) -> String? = { _ in nil },
         breite: CGFloat, hoehe: CGFloat, beimSchliessen: (() -> Void)? = nil,
         meldungsblatt: Meldungszeile.Blatt? = nil, zeileAbgegeben: Bool = false,
         @ViewBuilder koerper: () -> Koerper, @ViewBuilder fuss: () -> Fuss) {
        self.titel = titel
        self.unterzeile = unterzeile
        self.eintraege = eintraege
        _auswahl = auswahl
        self.name = name
        self.symbol = symbol
        self.plakette = plakette
        self.breite = breite
        self.hoehe = hoehe
        self.beimSchliessen = beimSchliessen
        self.meldungsblatt = meldungsblatt
        self.zeileAbgegeben = zeileAbgegeben
        self.koerper = koerper()
        self.fuss = fuss()
    }

    var body: some View {
        // Gezählt, wenn der Rahmen die neue Auswahl zeichnet — vor dem `onDisappear` der alten Seite, gleich woher
        // der Wechsel kommt (R-BG8-W2-03).
        let _ = seitenwechsel.zeichnet(auswahl)
        HStack(spacing: 0) {
            leistenspalte
            VStack(spacing: 0) {
                eintragskopf
                koerper
                    .environment(\.seitenwechsel, seitenwechsel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                fussbereich
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: breite, height: hoehe)
        .onChange(of: auswahl) { alt, neu in verlauf.gewechselt(von: alt, zu: neu) }
        .onExitCommand {
            // In der Lücke nach einer Antwort prallt ⎋ ab, mit Ton (E437) — wie im `Dialograhmen`.
            guard speicher?.frageSperrtBefehl() != true else { return }
            if let beimSchliessen { beimSchliessen() } else { schliessen() }
        }
    }

    /// Die Spalte der Leiste: fest `Seitenleistenmass.breite` breit, darin die Glasfläche mit Abstand zum Rand; auf ihr
    /// oben der Titel des Blatts, darunter die Leiste.
    private var leistenspalte: some View {
        VStack(alignment: .leading, spacing: 0) {
            blattkopf
            Seitenleiste(eintraege: eintraege, auswahl: $auswahl, name: name, symbol: symbol, plakette: plakette)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Seitenleistenmass.glasecke, style: .continuous))
        .padding(Seitenleistenmass.glasrand)
        .frame(width: Seitenleistenmass.breite)
        .frame(maxHeight: .infinity)
    }

    /// Titel und Unterzeile des Blatts oben in der Leiste.
    private var blattkopf: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titel)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let unterzeile {
                Text(unterzeile)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    /// Die Kapsel und der Name des gewählten Eintrags daneben. Knapp
    /// gehalten: Jeder Punkt hier fehlt dem Inhalt.
    private var eintragskopf: some View {
        HStack(spacing: 14) {
            blaetterkapsel
            Text(name(auswahl))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    /// Zurück und Vorwärts in einer Glaskapsel (von Hand, siehe oben), ⌘[ und ⌘].
    private var blaetterkapsel: some View {
        HStack(spacing: 0) {
            Button { blaettern(zurueck: true) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 26)
                    .contentShape(.rect)
            }
            .disabled(!verlauf.kannZurueck)
            .keyboardShortcut("[", modifiers: .command)
            .help("Zurück")
            .accessibilityLabel("Zurück")

            Divider().frame(height: 14)

            Button { blaettern(zurueck: false) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 30, height: 26)
                    .contentShape(.rect)
            }
            .disabled(!verlauf.kannVorwaerts)
            .keyboardShortcut("]", modifiers: .command)
            .help("Vorwärts")
            .accessibilityLabel("Vorwärts")
        }
        .buttonStyle(.borderless)
        .fontWeight(.medium)
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Ein Schritt im Verlauf; das Ziel setzt die Auswahl, wie ein Klick in die Leiste.
    private func blaettern(zurueck: Bool) {
        let ziel = zurueck ? verlauf.schrittZurueck(von: auswahl) : verlauf.schrittVorwaerts(von: auswahl)
        if let ziel { auswahl = ziel }
    }

    /// Der Fuß — derselbe Baustein wie im `Dialograhmen` (`Blattfuss`, R-BG5-01), in der Breite der Inhaltsspalte;
    /// senkrecht 12 statt 16 pt.
    private var fussbereich: some View {
        Blattfuss(meldungsblatt: meldungsblatt, zeileAbgegeben: zeileAbgegeben,
                  breite: breite - Seitenleistenmass.breite, senkrecht: 12) {
            fuss
        }
    }
}

/// Der Inhalt eines Eintrags: ein gruppiertes `Form` — Kästen, Abstände und
/// Beschriftungsspalten bringt es mit, Schalter stehen als Schalter. Den eigenen Grund blendet es aus. Gemeinsam für
/// alle Blätter mit Seitenleiste; was ein Blatt dazu braucht (etwa den Anfangsfokus), hängt es außen an.
struct Seitenform<Inhalt: View>: View {
    @ViewBuilder let inhalt: Inhalt

    var body: some View {
        Form { inhalt }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .toggleStyle(.switch)
    }
}

/// Zählt die Seitenwechsel eines Blatts mit Leiste — jeden, gleich woher er kommt: Leiste, Kapsel, ⌘[ ⌘] und der
/// Sprung auf den Eintrag des Grundes, wenn „Übernehmen“ abweist (E374; R-BG5d-01, R-BG8-W2-03). Gezählt wird, wenn der
/// Rahmen eine andere Auswahl zeichnet als zuletzt — vor dem `onDisappear` der alten Seite. Ein Feld,
/// das beim Verschwinden einen anderen Stand sieht als beim Erscheinen, ist mit seiner Seite gegangen: Was darin
/// getippt und noch nicht bestätigt war, gilt dann wie beim Fokusverlust — dessen `onChange` käme nicht mehr an
/// (R-BG5a-03). Verschwindet ein Feld ohne Seitenwechsel („Ohne Tag“, ein Schalter aus), bleibt es verworfen wie
/// bisher. Geht das Vorhaben-Blatt zu, springt es zugleich auf „Grundlegendes“ (E731) — das zählt; was ein Feld dann
/// übernimmt, landet im Entwurf, der mit dem Blatt geht (R-BG8n-01). Außerhalb eines Blatts mit Leiste gibt es keinen
/// Zähler.
@MainActor
final class Seitenwechsel {
    private(set) var stand = 0
    private var gezeichnet: AnyHashable?

    /// Aus dem `body` des Rahmens, je Zeichnen: zählt, wenn die Auswahl eine andere ist als beim letzten Mal; das erste
    /// Zeichnen zählt nicht.
    func zeichnet(_ auswahl: AnyHashable) {
        if let gezeichnet, gezeichnet != auswahl { stand += 1 }
        gezeichnet = auswahl
    }
}

extension EnvironmentValues {
    @Entry var seitenwechsel: Seitenwechsel? = nil
}

/// Der Verlauf der gewählten Einträge eines Blatts mit Seitenleiste — für Zurück und Vorwärts (Kapsel,
/// ⌘[ ⌘]). Nur in der Sitzung des Blatts. Vermerkt wird jeder Wechsel, gleich woher er kommt (Leiste, Programm,
/// „Übernehmen“ auf dem Eintrag des Grundes); ein Schritt im Verlauf selbst wird nicht noch einmal vermerkt. Ohne
/// Obergrenze und ohne Kürzen — nichts daran schlägt nach einer festen Zahl von Wechseln um.
struct Blaetterverlauf<Wert: Equatable> {
    private(set) var rueckwaerts: [Wert] = []
    private(set) var vorwaerts: [Wert] = []
    /// Das Ziel eines Schritts zurück oder vorwärts, bis sein Wechsel ankommt.
    private var unterwegs: Wert?

    var kannZurueck: Bool { !rueckwaerts.isEmpty }
    var kannVorwaerts: Bool { !vorwaerts.isEmpty }

    /// Ein Wechsel von `alt` nach `neu`.
    mutating func gewechselt(von alt: Wert, zu neu: Wert) {
        if let ziel = unterwegs, ziel == neu {
            unterwegs = nil
            return
        }
        unterwegs = nil
        rueckwaerts.append(alt)
        vorwaerts.removeAll()
    }

    /// Ein Schritt zurück von `jetzt` aus: das Ziel, nil bei leerem Verlauf.
    mutating func schrittZurueck(von jetzt: Wert) -> Wert? {
        guard let ziel = rueckwaerts.popLast() else { return nil }
        vorwaerts.append(jetzt)
        unterwegs = ziel
        return ziel
    }

    /// Ein Schritt vorwärts von `jetzt` aus: das Ziel, nil bei leerem Verlauf.
    mutating func schrittVorwaerts(von jetzt: Wert) -> Wert? {
        guard let ziel = vorwaerts.popLast() else { return nil }
        rueckwaerts.append(jetzt)
        unterwegs = ziel
        return ziel
    }
}
