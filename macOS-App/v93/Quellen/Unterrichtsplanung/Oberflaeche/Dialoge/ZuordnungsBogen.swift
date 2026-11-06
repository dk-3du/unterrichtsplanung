// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Was der Bogen „Lerngruppen zuordnen“ braucht — eine Kopie der Wahl, auf der er arbeitet (E384).
struct Zuordnungsvorlage: Identifiable {
    let id = UUID()
    let anfang: Hochstufungswahl
}

/// Der Bogen „Lerngruppen zuordnen“ (v84, AT9; E382–E388, E649, E652, E657, E670, E675) — am Blatt „Neue Planung“ und am
/// Blatt „Neues Schuljahr öffnen“. Links je aktive Lerngruppe der Name im neuen Schuljahr (E383) und ihre Zeilen; wer keine
/// Zeile trägt und nicht im Import erkannt ist, „wird archiviert“ (E657). Rechts je Zeile der neuen Planung die Lerngruppen
/// daran und ein Menü: Eine Lerngruppe kommt hinzu oder geht (E649, E670), „Keine Gruppe“ löst die Zeile (E652). Er arbeitet auf
/// einer Kopie der Wahl (E384): „Fertig“ gibt sie dem Blatt, „Abbrechen“ verwirft sie. 720 breit wie das Blatt (E388 b).
/// Je Lerngruppe der Schalter „mit Mitgliedern“ (v86, E699, E708): aus kommt sie nur mit Namen und Zeilen (E766).
struct ZuordnungsBogen: View {
    let gruppen: [Lerngruppe]
    let stufen: Int
    let zeilen: [Hochstufung.Zeile]
    /// Die aktiven Mitglieder je Lerngruppe (Kennungen) — für ihre Zahl und für „N Lernende bleiben im Archiv“ (E797).
    let mitglieder: (String) -> [String]
    /// Zuteilung und wer mitkommt, wie das Blatt sie aus einer Wahl rechnet (Übernommenes, Import).
    let rechnen: (Hochstufungswahl) -> (zuteilung: [String: [String]], mitkommend: Set<String>)
    let vorlage: Zuordnungsvorlage
    let fertig: (Hochstufungswahl) -> Void
    /// Nie höher als das Blatt, an dem er hängt — sonst stünde er über; an beiden Blättern 600 (⌘O mit Mindesthöhe, E694).
    var hoehe: CGFloat = 600
    /// Was rechts steht, wenn die Planung keine Zeile hat — je Blatt (Z-AT9B-07).
    var ohneZeile = "Die Planung hat keine Zeile, die eine Lerngruppe tragen kann."

    @Environment(\.dismiss) private var schliessen
    @State private var wahl = Hochstufungswahl()
    @State private var geladen = false
    /// Die Folge links, festgehalten beim Öffnen — beim Tippen eines Namens springt keine Lerngruppe (Z-AT9B-01).
    @State private var folge: [String] = []
    /// Die Zeile, über der gerade eine gezogene Lerngruppe schwebt (AT11).
    @State private var ablageziel: String?

    static let breite: CGFloat = 720

    var body: some View {
        let (zuteilung, mitkommend) = rechnen(wahl)
        let namen = Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, wahl.name($0, stufen: stufen)) })
        // `zeilen` ohne Vertretungen — das Blatt gibt sie schon so (`LerngruppenWahl.angebot`, E161, Z-AT9B-02, -12).
        let modell = Hochstufung.zeilenmodell(gruppen, mitkommend: mitkommend, namen: namen, zeilen: zeilen,
                                              zuteilung: zuteilung, ohneMitglieder: wahl.ohneMitglieder(gruppen))
        let links = folge.isEmpty ? modell.links : modell.links.sorted {
            (folge.firstIndex(of: $0.id) ?? Int.max) < (folge.firstIndex(of: $1.id) ?? Int.max)
        }
        Dialograhmen(titel: "Lerngruppen zuordnen", unterzeile: modell.zusammenfassung, breite: Self.breite, hoehe: hoehe,
                     freierKoerper: true) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lerngruppen").font(.headline)
                    List {
                        ForEach(links) { g in gruppenzeile(g, mitkommend: mitkommend, ohne: wahl.ohneMitglieder(gruppen)) }
                    }
                    .listStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Zeilen der neuen Planung").font(.headline)
                    List {
                        ForEach(modell.rechts) { z in zeilenzeile(z, links: links, zuteilung: zuteilung) }
                    }
                    .listStyle(.bordered)
                    .overlay {
                        if modell.rechts.isEmpty {
                            Text(ohneZeile)
                                .foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: hoehe - 160, alignment: .top)
        } fuss: {
            Button("Vorschlag wiederherstellen") { wahl.vorschlagWiederherstellen() }
                .disabled(wahl.zeilen.isEmpty && wahl.freieZeilen.isEmpty)
                .help(Self.vorschlagHilfe)
            Spacer(minLength: 0)
            Button("Abbrechen") { schliessen() }
                .keyboardShortcut(.cancelAction)
            Button("Fertig") {
                fertig(wahl)
                schliessen()
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            guard !geladen else { return }
            geladen = true
            wahl = vorlage.anfang
            let (z, m) = rechnen(vorlage.anfang)
            let n = Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, vorlage.anfang.name($0, stufen: stufen)) })
            folge = Hochstufung.zeilenmodell(gruppen, mitkommend: m, namen: n, zeilen: zeilen, zuteilung: z).links.map(\.id)
        }
    }

    /// Links: bisheriger Name, Zahl der Lernenden, Name im neuen Schuljahr, die erste Zeile und die weiteren; dazu der Schalter
    /// „mit Mitgliedern“ (E708) — ohne Zeile gesperrt (E657, E796), aus mit dem Hinweis darunter (E766). Was in welcher
    /// Zeile steht, sagt `reihen` (E821).
    private func gruppenzeile(_ g: Hochstufung.Zeilenmodell.Gruppe, mitkommend: Set<String>, ohne: Set<String>) -> some View {
        let reihen = Self.reihen(g)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(reihen.indices, id: \.self) { stelle in
                HStack(spacing: 8) {
                    ForEach(reihen[stelle], id: \.self) { teil in
                        gruppenteil(teil, g, mitkommend: mitkommend, ohne: ohne)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .foregroundStyle(g.kommtMit ? .primary : .secondary)
        // Ziehen und Ablegen obendrauf (AT11, E387 a): die Kennung als Text — auf eine Zeile rechts gezogen, kommt die
        // Lerngruppe dort hinzu wie am Menü (E670).
        .draggable(g.id)
        .help(Self.ziehenHilfe)
    }

    @ViewBuilder
    private func gruppenteil(_ teil: Teil, _ g: Hochstufung.Zeilenmodell.Gruppe, mitkommend: Set<String>,
                             ohne: Set<String>) -> some View {
        switch teil {
        case .bisher:
            // „bisher …“ bekommt den Platz zuerst und steht, wo es geht, in einer Zeile; wird es eng, bricht zuerst die Zahl
            // an Wortgrenzen um (E834). Die Priorität gibt ihm den Rest der Zeile vor Zahl und Abstand (Z-R2A2N3-01).
            Text(g.bisher).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        case .zahl:
            let bleiben = Hochstufung.bleibenImArchiv(g.id, mitglieder: mitglieder, mitkommend: mitkommend, ohneMitglieder: ohne)
            let text = Self.lernendentext(mitglieder(g.id).count, bleiben: bleiben, kommtMit: g.kommtMit,
                                          mitMitgliedern: g.mitMitgliedern)
            // Die Zahl bricht nur zwischen ganzen Wörtern um, nie im Wort, und wird nie gekürzt (E833, E834): nie schmaler
            // als ihr längstes Wort. Neben „bisher …“ bekommt die Zahl, was bleibt — vor dem Abstand.
            Text(text)
                .font(Font(Self.zahlschrift() as CTFont)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: Self.laengstesWort(text), alignment: .leading)
        case .abstand:
            // Zuletzt: Erst „bisher …“ (Priorität 1), dann die Zahl, dann der Abstand (E834).
            Spacer(minLength: 8).layoutPriority(-1)
        case .wirdArchiviert:
            // In eigener Zeile unter dem Ziel, wie der Hinweis bei „aus“ (E833).
            Text(Self.hinweis(kommtMit: false, mitMitgliedern: g.mitMitgliedern) ?? "")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .schalter:
            // Nur von Hand (E768): Umbenennen und „Vorschlag wiederherstellen“ legen ihn nicht um. Gesperrt mit eigener
            // Hilfe (E796) — über `hilfe`, damit sie auch gesperrt erscheint (H1).
            let frei = Self.schalterFrei(kommtMit: g.kommtMit)
            Toggle(Self.schaltertitel, isOn: Binding(get: { g.mitMitgliedern },
                                                     set: { wahl.mitMitgliedernSetzen($0, fuer: g.id) }))
                .toggleStyle(.checkbox)
                .font(.caption)
                .fixedSize()
                .disabled(!frei)
                .accessibilityLabel(Self.schalterhilfe(g.bisher))
                .hilfe(Self.schalterHilfe(frei: frei), gesperrt: !frei)
        case .name:
            TextField("Name", text: Binding(get: { g.name }, set: { neu in
                if let gruppe = gruppen.first(where: { $0.id == g.id }) { wahl.nameSetzen(neu, fuer: gruppe, stufen: stufen) }
            }), prompt: Text(g.neuerName))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)
            .accessibilityLabel("Name im neuen Schuljahr — " + g.bisher)
        case .ziel:
            // Die zweite Zeile gehört Name und Ziel allein — das Ziel bricht um, statt gekürzt zu werden (E821).
            Text(g.ziel).fixedSize(horizontal: false, vertical: true)
        case .weitere:
            // Die weiteren Zeilen der Gruppe gleich unter dem Ziel — vor „wird archiviert“ und dem Hinweis (Z-R2A2N3-04).
            VStack(alignment: .leading, spacing: 4) {
                ForEach(g.weitere, id: \.self) { titel in
                    Text("+ " + titel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        case .hinweis:
            // Der Hinweis zum Schalter aus — eine eigene Zeile: neben Name und Zahl würde er in der Breite der Liste gekürzt.
            Text(Self.hinweis(kommtMit: true, mitMitgliedern: g.mitMitgliedern) ?? "")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Rechts: die Zeile, die Lerngruppen daran und ihr Menü — je Lerngruppe ein Häkchen, dazu „Keine Gruppe“.
    private func zeilenzeile(_ z: Hochstufung.Zeilenmodell.Belegung, links: [Hochstufung.Zeilenmodell.Gruppe],
                             zuteilung: [String: [String]]) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(z.titel).lineLimit(1)
                if z.weitere {
                    Text("weitere Zeile").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Menu(z.traeger ?? "Keine Gruppe") {
                ForEach(links) { g in
                    Toggle(g.neuerName + " — " + g.bisher, isOn: Binding(get: { z.gruppen.contains(g.id) }, set: { an in
                        if an { wahl.zeileGeben(z.id, an: g.id, zuteilung: zuteilung) }
                        else { wahl.zeileNehmen(z.id, von: g.id, zuteilung: zuteilung) }
                    }))
                    // Höchstens 20 Zeilen je Lerngruppe (Z-AT9M-04) — eine volle bekommt keine weitere (Z-AT9B-08).
                    .disabled(!z.gruppen.contains(g.id) && (zuteilung[g.id]?.count ?? 0) >= Lernendendatei.maxZeilenJeGruppe)
                    .help((zuteilung[g.id]?.count ?? 0) >= Lernendendatei.maxZeilenJeGruppe
                          ? "Höchstens \(Lernendendatei.maxZeilenJeGruppe) Zeilen je Lerngruppe" : "")
                }
                Divider()
                Button("Keine Gruppe") { wahl.zeileLoesen(z.id, zuteilung: zuteilung) }
                    .disabled(!Self.keineGruppeFrei(z.gruppen))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Lerngruppen an " + z.titel)
            .accessibilityValue(z.traeger.map { String($0.dropFirst(2)) } ?? "Keine Gruppe")
        }
        .foregroundStyle(z.gruppen.isEmpty ? .secondary : .primary)
        .padding(.horizontal, 4)
        .background(ablageziel == z.id ? Color.accentColor.opacity(0.15) : Color.clear, in: .rect(cornerRadius: 6))
        // Abgelegt wird nur eine Kennung, die links steht; wie „Häkchen setzen“ am Menü — eine Zeile, die sie schon trägt,
        // und eine volle Lerngruppe ändern nichts (`zeileGeben`).
        .dropDestination(for: String.self) { kennungen, _ in
            let bekannt = kennungen.filter { id in links.contains { $0.id == id } }
            for id in bekannt { wahl.zeileGeben(z.id, an: id, zuteilung: zuteilung) }
            return !bekannt.isEmpty
        } isTargeted: { schwebt in
            if schwebt { ablageziel = z.id } else if ablageziel == z.id { ablageziel = nil }
        }
    }
}

extension ZuordnungsBogen {
    /// „Keine Gruppe“ am Menü einer Zeile (E684): nur, wenn mit ihr eine Lerngruppe verknüpft ist — an einer leeren gäbe es
    /// nichts zu lösen, und der Vorschlag ginge unsichtbar an ihr vorbei (E652).
    nonisolated static func keineGruppeFrei(_ gruppen: [String]) -> Bool {
        !gruppen.isEmpty
    }

    // ── Der Schalter „mit Mitgliedern“ (v86, AX2: E699, E708, E766, E768) ──

    nonisolated static let schaltertitel = "mit Mitgliedern"

    /// Die Schrift der Zahl — eine für den Text und für die Messung seines längsten Worts (Z-AX4N-04): wie `.caption`.
    nonisolated static func zahlschrift() -> NSFont {
        NSFont.preferredFont(forTextStyle: .caption1)
    }

    /// Die Breite des längsten Worts in der Schrift der Zahl (`zahlschrift`) — so schmal wird die Zahl nie, sie bricht nur
    /// zwischen ganzen Wörtern um (E834). Aufgerundet und 1 pt dazu, damit kein Rest an Rundung ein Wort teilt.
    nonisolated static func laengstesWort(_ text: String) -> CGFloat {
        let schrift = zahlschrift()
        let breiteste = text.split(whereSeparator: \.isWhitespace)
            .map { (String($0) as NSString).size(withAttributes: [.font: schrift]).width }
            .max() ?? 0
        return breiteste.rounded(.up) + 1
    }

    /// Neben dem bisherigen Namen: „12 Lernende“ — kommt die Lerngruppe ohne Mitglieder, wie viele im Archiv bleiben:
    /// „9 Lernende bleiben im Archiv“, wenn 3 über eine andere Lerngruppe mitkommen (E766, E797;
    /// `Hochstufung.bleibenImArchiv`). Kommen alle über andere mit, steht nur die Zahl. Ohne Zeile sagt „wird archiviert“
    /// schon alles.
    nonisolated static func lernendentext(_ zahl: Int, bleiben: Int, kommtMit: Bool, mitMitgliedern: Bool) -> String {
        kommtMit && !mitMitgliedern && bleiben > 0 ? "\(bleiben) Lernende bleiben im Archiv" : "\(zahl) Lernende"
    }

    /// Was an einer Lerngruppe links steht (E821, E833).
    enum Teil: Hashable, Sendable { case bisher, zahl, abstand, wirdArchiviert, schalter, name, ziel, weitere, hinweis }

    /// Die Zeilen einer Lerngruppe links: oben nur „bisher …“, die Zahl und rechts das Kästchen (E821, E833); darunter Name
    /// und Ziel für sich, damit das Ziel nicht gekürzt wird; darunter die weiteren Zeilen der Gruppe („+ …“, E649); darunter
    /// in eigener Zeile ohne Zeile „wird archiviert“ (E833), mit dem Kästchen aus der Hinweis nach E766 A (Z-R2A2N3-04).
    nonisolated static func reihen(kommtMit: Bool, mitMitgliedern: Bool, weitere: Bool) -> [[Teil]] {
        let mitte: [[Teil]] = weitere ? [[.weitere]] : []
        let unten: [[Teil]] = !kommtMit ? [[.wirdArchiviert]] : !mitMitgliedern ? [[.hinweis]] : []
        return [[.bisher, .zahl, .abstand, .schalter], [.name, .ziel]] + mitte + unten
    }

    /// Die Zeilen einer Lerngruppe, wie `gruppenzeile` sie zeigt — weitere Zeilen, wenn sie mehr als eine trägt.
    nonisolated static func reihen(_ g: Hochstufung.Zeilenmodell.Gruppe) -> [[Teil]] {
        reihen(kommtMit: g.kommtMit, mitMitgliedern: g.mitMitgliedern, weitere: !g.weitere.isEmpty)
    }

    /// E795: Die Hilfe an „Vorschlag wiederherstellen“.
    nonisolated static let vorschlagHilfe = "Die Zeilen wieder wie vorgeschlagen — die Namen und „mit Mitgliedern“ bleiben"

    /// Die Hilfe der ganzen Lerngruppe links — gezogen auf eine Zeile kommt sie dort hinzu (AT11).
    nonisolated static let ziehenHilfe = "Auf eine Zeile rechts ziehen — die Lerngruppe kommt dort hinzu"

    /// Die Hilfe am Kästchen „mit Mitgliedern“: gesperrt (ohne Zeile) eine eigene (E796), frei die der ganzen Lerngruppe.
    nonisolated static func schalterHilfe(frei: Bool) -> String {
        frei ? ziehenHilfe : "Erst mit einer Zeile kommt die Lerngruppe mit — auf eine Zeile rechts ziehen"
    }

    /// Klein an der Lerngruppe: ohne Zeile rechts „wird archiviert“ (E657), mit dem Schalter aus darunter der Hinweis (E766 A).
    nonisolated static func hinweis(kommtMit: Bool, mitMitgliedern: Bool) -> String? {
        guard kommtMit else { return "wird archiviert" }
        return mitMitgliedern ? nil : "ohne Mitglieder — sie bleiben in der Vorjahresplanung im Archiv"
    }

    /// Die Bedienhilfe des Schalters: „Mit Mitgliedern ins neue Schuljahr — bisher Mathe-Förder“.
    nonisolated static func schalterhilfe(_ bisher: String) -> String {
        "Mit Mitgliedern ins neue Schuljahr — " + bisher
    }

    /// Eine Lerngruppe ohne Zeile kommt nicht mit (E657) — ihr Schalter wirkt nicht und ist gesperrt.
    nonisolated static func schalterFrei(kommtMit: Bool) -> Bool {
        kommtMit
    }
}
