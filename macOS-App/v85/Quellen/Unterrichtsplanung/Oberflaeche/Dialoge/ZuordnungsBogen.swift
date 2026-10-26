// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

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
struct ZuordnungsBogen: View {
    let gruppen: [Lerngruppe]
    let stufen: Int
    let zeilen: [Hochstufung.Zeile]
    let mitgliederzahl: (String) -> Int
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
                                              zuteilung: zuteilung)
        let links = folge.isEmpty ? modell.links : modell.links.sorted {
            (folge.firstIndex(of: $0.id) ?? Int.max) < (folge.firstIndex(of: $1.id) ?? Int.max)
        }
        Dialograhmen(titel: "Lerngruppen zuordnen", unterzeile: modell.zusammenfassung, breite: Self.breite, hoehe: hoehe,
                     freierKoerper: true) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lerngruppen").font(.headline)
                    List {
                        ForEach(links) { g in gruppenzeile(g) }
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
                .help("Die Zeilen wieder wie vorgeschlagen — die Namen bleiben")
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

    /// Links: bisheriger Name, Zahl der Lernenden, Name im neuen Schuljahr, die erste Zeile und die weiteren.
    private func gruppenzeile(_ g: Hochstufung.Zeilenmodell.Gruppe) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(g.bisher).font(.caption).foregroundStyle(.secondary)
                Text("\(mitgliederzahl(g.id)) Lernende").font(.caption).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                if !g.kommtMit {
                    Text("wird archiviert").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                TextField("Name", text: Binding(get: { g.name }, set: { neu in
                    if let gruppe = gruppen.first(where: { $0.id == g.id }) { wahl.nameSetzen(neu, fuer: gruppe, stufen: stufen) }
                }), prompt: Text(g.neuerName))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
                .accessibilityLabel("Name im neuen Schuljahr — " + g.bisher)
                Text(g.ziel).lineLimit(1)
            }
            ForEach(g.weitere, id: \.self) { titel in
                Text("+ " + titel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .foregroundStyle(g.kommtMit ? .primary : .secondary)
        // Ziehen und Ablegen obendrauf (AT11, E387 a): die Kennung als Text — auf eine Zeile rechts gezogen, kommt die
        // Lerngruppe dort hinzu wie am Menü (E670).
        .draggable(g.id)
        .help("Auf eine Zeile rechts ziehen — die Lerngruppe kommt dort hinzu")
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
}
