// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Die Wahl der Lerngruppen ins neue Schuljahr (E271) — in „Neue Planung“ und im Blatt „Neues Schuljahr öffnen“ (E305):
/// der Schalter „Lerngruppen hochstufen“ (E307), die Zusammenfassung und der Knopf zum Bogen „Lerngruppen zuordnen“
/// (E382–E388). Namen und Zeilen stehen nur im Bogen (E383).
struct LerngruppenWahl: View {
    let fuss: String
    let hochstufen: Bool
    let stufentext: String
    let hochstufenSetzen: (Bool) -> Void
    /// „3 von 4 Lerngruppen zugeordnet“
    let zusammenfassung: String
    let zuordnen: () -> Void

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { hochstufen }, set: { hochstufenSetzen($0) })) {
                Text("Lerngruppen hochstufen")
                Text(stufentext)
            }
            LabeledContent {
                Button("Lerngruppen zuordnen …", action: zuordnen)
                    .help("Namen im neuen Schuljahr und Zeilen der neuen Planung je Lerngruppe")
            } label: {
                Text(zusammenfassung)
            }
        } header: {
            Text("Lerngruppen ins neue Schuljahr")
        } footer: {
            Text(fuss)
        }
    }
}

extension LerngruppenWahl {
    /// Ob es den Abschnitt mit dem Knopf „Lerngruppen zuordnen …“ gibt (E647) — an beiden Blättern dieselbe Regel: nur
    /// verschlüsselt und mit aktiven Lerngruppen.
    nonisolated static func knopfFrei(verschluesselt: Bool, gruppen: [Lerngruppe]) -> Bool {
        verschluesselt && gruppen.contains { $0.archiviert.isEmpty }
    }

    /// Die Zeilen, die eine Lerngruppe im neuen Schuljahr tragen kann — nicht Vertretungen (E161, Z-AT9B-12). Blatt, Bogen,
    /// Vorschlag und neues Jahr rechnen mit diesem Angebot.
    nonisolated static func angebot(_ zeilen: [Hochstufung.Zeile]) -> [Hochstufung.Zeile] {
        zeilen.filter { $0.art.erlaubt(.verwaltung) }
    }

    /// Der Fuß des Abschnitts (Z-AT9M-19, Z-AT9a1-02): wer mitkommt (E657), ohne Fach (E656) — an „Neue Planung“ mit dem Import.
    nonisolated static func fuss(mitImport: Bool) -> String {
        "Mit kommen die Lerngruppen, die eine Zeile der neuen Planung tragen" + (mitImport ? " oder im IServ-Import erkannt sind" : "")
            + " — mit ihren Personen und offenen Anliegen; die übrigen bleiben mit der bisherigen Planung im Archiv. "
            + "Vorgeschlagen sind für jede Lerngruppe ihre übernommenen Zeilen und die Zeilen ihres neuen Namens."
    }
}

/// Der Zustand der Wahl, wie beide Blätter ihn führen: der Schalter, getippte
/// Namen und von Hand festgelegte Zeilen — fehlend: der Vorschlag. Wer
/// mitkommt, folgt aus den Zeilen, bei „Neue Planung“ auch aus dem Import (E657, `Hochstufung.mitkommend`).
struct Hochstufungswahl {
    var hochstufen: Bool?
    var namen: [String: String] = [:]
    /// Die Zeilen je Gruppe, von Hand festgelegt und vollständig — leer heißt keine (E649).
    var zeilen: [String: [String]] = [:]
    /// Zeilen, die am Menü „Keine Gruppe“ bekamen — der Vorschlag gibt sie keiner Lerngruppe; von Hand weiter (E652).
    var freieZeilen: Set<String> = []

    mutating func nameSetzen(_ name: String, fuer gruppe: Lerngruppe, stufen: Int) {
        // Gibt das Feld beim Verlassen nur zurück, was es zeigt, ist nichts geändert (Z14c2-09).
        guard name != self.name(gruppe, stufen: stufen) else { return }
        namen[gruppe.id] = name
    }

    mutating func hochstufenSetzen(_ an: Bool) {
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

    /// Am Menü einer Zeile eine Gruppe wählen (E649): Die Gruppe kommt hinzu und behält ihre Zeilen; keiner anderen
    /// wird etwas genommen (E670, E675). Eine freie Zeile bleibt für den Vorschlag frei (E652) — die Wahl gilt.
    mutating func zeileGeben(_ zeile: String, an gruppe: String, zuteilung: [String: [String]]) {
        var eigene = zuteilung[gruppe] ?? []
        // Eine Gruppe trägt höchstens 20 Zeilen wie im neuen Jahr — an eine volle geht keine weitere (Z-AT9M-04).
        guard !eigene.contains(zeile), eigene.count < Lernendendatei.maxZeilenJeGruppe else { return }
        eigene.append(zeile)
        zeilen[gruppe] = eigene
    }

    /// Am Menü einer Zeile eine Lerngruppe von ihr nehmen (E670): Nur diese verliert sie, die übrigen behalten sie; die Zeile
    /// wird nicht frei.
    mutating func zeileNehmen(_ zeile: String, von gruppe: String, zuteilung: [String: [String]]) {
        guard let eigene = zuteilung[gruppe], eigene.contains(zeile) else { return }
        zeilen[gruppe] = eigene.filter { $0 != zeile }
    }

    /// „Vorschlag wiederherstellen“ (E386): Was von Hand an den Zeilen geschah, geht; Namen und Schalter bleiben.
    mutating func vorschlagWiederherstellen() {
        zeilen = [:]
        freieZeilen = []
    }

    /// Die Lage, die Prüfstand und Abbild vorgeben (E629, E630), auf dem Vorschlag: `verdraengt` — die letzte Lerngruppe
    /// bekommt die erste Zeile der ersten mit Zeile dazu (E649, E670); `ohne` — die letzte mit Zeile verliert ihre Zeilen am
    /// Menü „Keine Gruppe“, sie stehen frei (E652). `gruppen` nach `Lerngruppe.vorgehen` geordnet.
    mutating func lage(_ lage: Zuordnungslage, gruppen: [Lerngruppe], zuteilung: [String: [String]]) {
        let mitZeile = gruppen.filter { !(zuteilung[$0.id] ?? []).isEmpty }
        switch lage {
        case .vorschlag:
            return
        case .verdraengt:
            guard let erste = mitZeile.first, let zeile = zuteilung[erste.id]?.first,
                  let letzte = gruppen.last(where: { $0.id != erste.id }) else { return }
            zeileGeben(zeile, an: letzte.id, zuteilung: zuteilung)
        case .ohne:
            guard let letzte = mitZeile.last else { return }
            var stand = zuteilung
            for zeile in zuteilung[letzte.id] ?? [] {
                zeileLoesen(zeile, zuteilung: stand)
                for (g, folge) in zeilen { stand[g] = folge }
            }
        }
    }

    /// „Keine Gruppe“ am Menü einer Zeile (E649): Alle, die sie hatten, verlieren nur sie; der Vorschlag gibt sie
    /// keiner mehr (E652) — von Hand bekommt sie eine Gruppe weiter.
    mutating func zeileLoesen(_ zeile: String, zuteilung: [String: [String]]) {
        for (andere, folge) in zuteilung where folge.contains(zeile) { zeilen[andere] = folge.filter { $0 != zeile } }
        freieZeilen.insert(zeile)
    }
}

/// ⌘O mit einer Planung anderer Herkunft (E277, E305): Die bisherige Planung
/// geht samt ihren Lernendendaten ins Archiv; mit kommen die Lerngruppen, die
/// eine Zeile tragen (E657) — wie bei „Neue Planung“, mit Namen und Zeilen (E307–E311, E649).
struct SchuljahrOeffnenDialog: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Environment(\.dismiss) private var schliessen
    @State private var wahl = Hochstufungswahl()
    /// Der Wechsel, solange das Blatt steht — beim Schließen ist er im Speicher schon fort (Z14c2-05).
    @State private var gehalten: Schuljahrwechsel?
    /// Der Bogen „Lerngruppen zuordnen“, solange er steht.
    @State private var zuordnung: Zuordnungsvorlage?

    static let titel = "Neues Schuljahr öffnen"
    static let absatz = "Die bisherige Planung wird samt ihren Lernendendaten ins Archiv gelegt; mit der geöffneten "
        + "beginnt eine neue Jahresdatei."
    static let fuss = LerngruppenWahl.fuss(mitImport: false)
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
        let namen = Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, wahl.name($0, stufen: stufen)) })
        let (zuteilung, mitkommend) = rechnen(wahl)
        let frei = LerngruppenWahl.knopfFrei(verschluesselt: speicher.tresor != nil, gruppen: gruppen)
        Dialograhmen(titel: Self.titel(stufen: stufen),
                     unterzeile: wechsel.map(Self.unterzeile) ?? "",
                     breite: 720, hoehe: 680, mindesthoehe: frei ? Self.mindesthoehe : nil, beimSchliessen: abbrechen) {
            Section {
                Text(Self.absatz)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if frei {
                LerngruppenWahl(fuss: Self.fuss,
                                hochstufen: wahl.hochstufen ?? (stufen > 0),
                                stufentext: Hochstufung.stufentext(bisher: wechsel?.bisherigesSchuljahr ?? "",
                                                                   neu: wechsel?.neuesSchuljahr ?? "", stufen: stufen,
                                                                   an: wahl.hochstufen ?? (stufen > 0)),
                                hochstufenSetzen: { wahl.hochstufenSetzen($0) },
                                zusammenfassung: Hochstufung.zeilenmodell(gruppen, mitkommend: mitkommend, namen: namen,
                                                                          zeilen: LerngruppenWahl.angebot(wechsel?.zeilen ?? []),
                                                                          zuteilung: zuteilung).zusammenfassung,
                                zuordnen: speicher.blattknopf { zuordnungOeffnen(.vorschlag) })
            }
        } fuss: {
            Spacer(minLength: 0)
            Button("Abbrechen") { abbrechen() }
                .keyboardShortcut(.cancelAction)
            Button(Self.knopf, role: .destructive, action: speicher.blattknopf {
                let ziele = Dictionary(uniqueKeysWithValues: gruppen.filter { mitkommend.contains($0.id) }.map {
                    ($0.id, Gruppenziel(name: namen[$0.id] ?? $0.name, zeilen: zuteilung[$0.id] ?? []))
                })
                schliessen()
                speicher.schuljahrOeffnen(gruppen: mitkommend, ziele: ziele)
            })
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(speicher.schuljahrwechsel == nil)
        }
        .onAppear { gehalten = speicher.schuljahrwechsel }
        .sheet(item: $zuordnung) { vorlage in
            ZuordnungsBogen(gruppen: gruppen, stufen: stufen, zeilen: LerngruppenWahl.angebot(wechsel?.zeilen ?? []),
                            mitgliederzahl: { speicher.lernende.verzeichnis?.mitgliederzahl($0) ?? 0 },
                            rechnen: rechnen, vorlage: vorlage, fertig: { wahl = $0 },
                            ohneZeile: "Die geöffnete Planung hat keine Zeile, die eine Lerngruppe tragen kann.")
        }
        // Prüfstand und Abbild geben die Lage vor, wenn das Blatt steht (E629, E630) — wie der Knopf; verbraucht wird sie
        // immer. Beobachtet: keine Frist im Programm (wie E610).
        .onChange(of: speicher.zuordnungsbogenVorgabe) { _, lage in
            guard let lage else { return }
            speicher.zuordnungsbogenVorgabe = nil
            zuordnungOeffnen(lage)
        }
    }

    /// Die Mindesthöhe des Blatts mit dem Abschnitt der Lerngruppen (E694): Der Bogen „Lerngruppen zuordnen“ hängt daran
    /// so hoch wie an „Neue Planung“.
    static let mindesthoehe: CGFloat = 620

    /// Die Zuteilung aus einer Wahl — für das Blatt und den Bogen dieselbe Rechnung (E696 b); mit kommt, wer eine Zeile trägt
    /// (E657).
    private func rechnen(_ w: Hochstufungswahl) -> (zuteilung: [String: [String]], mitkommend: Set<String>) {
        let gruppen = speicher.lerngruppenZurWahl
        // Beim Schließen hält das Blatt den Wechsel (Z14c2-05, Z-AT15N-04).
        let wechsel = speicher.schuljahrwechsel ?? gehalten
        let stufen = wechsel?.stufen ?? 0
        let z = Hochstufung.zuteilung(
            gruppen, namen: Dictionary(uniqueKeysWithValues: gruppen.map { ($0.id, w.suchname($0, stufen: stufen)) }),
            uebernommen: wechsel?.uebernommen ?? [:], zeilen: LerngruppenWahl.angebot(wechsel?.zeilen ?? []), gewaehlt: w.zeilen,
            frei: w.freieZeilen)
        return (z, Hochstufung.mitkommend(z))
    }

    /// Der Bogen auf einer Kopie der Wahl (E384) — nur mit Lerngruppen (E647), nie über einem Alert am Blatt.
    private func zuordnungOeffnen(_ lage: Zuordnungslage) {
        let gruppen = speicher.lerngruppenZurWahl
        guard zuordnung == nil, speicher.rueckfrage == nil,
              LerngruppenWahl.knopfFrei(verschluesselt: speicher.tresor != nil, gruppen: gruppen),
              speicher.schuljahrwechsel != nil else { return }
        let zuteilung = rechnen(wahl).zuteilung
        var anfang = wahl
        anfang.lage(lage, gruppen: gruppen.filter { $0.archiviert.isEmpty }.sorted(by: Lerngruppe.vorgehen), zuteilung: zuteilung)
        zuordnung = Zuordnungsvorlage(anfang: anfang)
    }

    private func abbrechen() {
        // In der Lücke nach einer Antwort prallt der Knopf ab, auch ⎋ (E437).
        guard !speicher.frageSperrtBefehl() else { return }
        speicher.schuljahrOeffnenAbbrechen()
        schliessen()
    }
}
