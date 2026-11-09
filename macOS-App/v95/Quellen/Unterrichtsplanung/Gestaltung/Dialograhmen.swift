// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Die Meldungszeile in Blättern (E476, E487): Ein Blatt nennt sich mit `Dialograhmen(meldungsblatt:)`; steht es in
/// `eingeschaltet`, zeigt es seine Meldungen selbst, und solange nur solche Blätter stehen, bleibt die Kapsel des
/// Hauptfensters still (E489). `imAbbild` zeigt sie für ein Abbild in jedem Blatt (Auftrag `--abbild` mit
/// `ABBILD_MELDUNG`, `Selbstabbild`). Einmal gelesen, nie gesetzt: Ein Blatt, das schon steht, zeichnete sich nach
/// einem Setzen nicht neu.
@MainActor
enum Meldungszeile {
    /// Die Blätter, die eine eigene Meldungszeile tragen können.
    enum Blatt: Hashable {
        case lernende, vorhaben, klassen

        /// Das Blatt eines Dialogfensters; nil für eines ohne eigene Zeile.
        init?(_ dialog: Dialogfenster) {
            switch dialog {
            case .lernende: self = .lernende
            case .klassen: self = .klassen
            default: return nil
            }
        }
    }

    /// Die Blätter, die ihre Meldungen selbst zeigen — „Lernende“ samt seinen Bögen (AT2, E490), das Vorhaben-Blatt
    /// samt dem Material-Bogen (AT13, AW3-neu) und ⌘K samt dem Bogen „Farbe wählen“ (v89, E968). Der Rahmen und das
    /// Hauptfenster lesen beide nur hier.
    static let eingeschaltet: Set<Blatt> = [.lernende, .vorhaben, .klassen]

    /// Steht die Meldung über den Knöpfen statt in der Lücke daneben (E1061)? In schmalen Bögen am Blatt „Lernende“ —
    /// neben drei Knöpfen blieben dort nur zwei Wörter.
    static func ueberDenKnoepfen(_ blatt: Blatt?, breite: CGFloat) -> Bool {
        blatt == .lernende && breite < 720
    }

    static let imAbbild: Bool = {
        guard case .abbild? = Pruefstaende.Auftrag.lesen(ProcessInfo.processInfo.arguments) else { return false }
        return !(ProcessInfo.processInfo.environment["ABBILD_MELDUNG"] ?? "").isEmpty
    }()

    /// Bleibt die Kapsel des Hauptfensters still (E489)? Nur wenn jedes stehende Blatt seine Meldungen selbst
    /// zeigt — sonst läge die Zeile unter einem Blatt ohne Zeile; im Abbild zeigt jedes Blatt die Zeile.
    static func hauptfensterStill(offenerDialog: Dialogfenster?, vorhabenOffen: Bool, materialOffen: Bool,
                                  eingeschaltet: Set<Blatt>, imAbbild: Bool) -> Bool {
        // Was steht: das Blatt des Dialogs, darüber das Vorhaben-Blatt, darauf der Material-Bogen — er nennt das
        // Vorhaben-Blatt und zeigt dessen Zeile (E490 a).
        var stehend: [Blatt?] = []
        if let offenerDialog { stehend.append(Blatt(offenerDialog)) }
        if vorhabenOffen { stehend.append(.vorhaben) }
        if materialOffen { stehend.append(.vorhaben) }
        guard !stehend.isEmpty else { return false }
        return imAbbild || stehend.allSatisfy { $0.map(eingeschaltet.contains) ?? false }
    }

    static func hauptfensterStill(_ speicher: Planungsspeicher, eingeschaltet: Set<Blatt> = eingeschaltet,
                                  imAbbild: Bool = imAbbild) -> Bool {
        hauptfensterStill(offenerDialog: speicher.offenerDialog, vorhabenOffen: speicher.vorhabenDialog != nil,
                          materialOffen: speicher.materialblattOffen, eingeschaltet: eingeschaltet, imAbbild: imAbbild)
    }
}

/// Die Lücke im Fuß eines Blatts mit eigener Meldungszeile (E855): dort stehen seine Meldungen — außer in schmalen Bögen am
/// Blatt „Lernende“, dort über den Knöpfen (E1061) — zwischen dem, was links
/// steht, und den Knöpfen rechts; sie decken nichts zu, und nichts springt. Ohne eigene Zeile ein `Spacer(minLength: 0)`.
/// Jeder Fuß eines solchen Blatts trägt sie (`VereinbarungsleistePruefungen.meldungImFuss`).
struct Fussluecke: View {
    @Environment(\.meldungImFuss) private var meldungImFuss
    @Environment(Planungsspeicher.self) private var speicher: Planungsspeicher?

    var body: some View {
        if meldungImFuss, let speicher {
            Meldungskapseln(kompakt: true, nurJuengste: true)
                .environment(speicher)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
        } else {
            Spacer(minLength: 0)
        }
    }
}

extension EnvironmentValues {
    /// Ob der Fuß die Meldungen des Blatts zeigt (E855) — gesetzt vom `Dialograhmen`.
    @Entry var meldungImFuss = false
}

/// Maße der Blätter mit gruppiertem `Form` (E1156).
enum Formblatt {
    /// Die Breite eines Blatts, dessen Kästen das `Form` ganz ausfüllt: Es deckelt sie bei 704 pt (gemessen 703,5; macOS
    /// 15 und neuer, keine Einstellung dafür); dazu je 20 pt Rand wie bei schmaleren Blättern. Breiter gibt nur breitere
    /// Ränder — eine überbreite Zeile weitet zwar ihren Kasten, die Trennlinien bleiben aber an der alten Stelle.
    static let breite: CGFloat = 744
    /// Der Platz einer Zeile mit festen Spalten im Kasten: 703,5 pt Kasten abzüglich je 9,75 pt Einzug — gemessen in
    /// 2.7.1 bei 860 und 960 pt Blattbreite, bei 744 im Abbild bestätigt. Belegt eine Zeile mehr, wächst der Kasten mit,
    /// die Trennlinien nicht (R-BG8c-02).
    static let zeile: CGFloat = 684
}

/// Der Papierkorb am Ende einer Tabellenzeile (Ferien, Sperrzeiträume) — ein Baustein für beide, damit die Prüfung genau
/// ihn gegen die Spalten misst (R-BG8cn2-01).
struct Papierkorbknopf: View {
    let hilfe: String
    let kennzeichnung: String
    let aktion: () -> Void

    var body: some View {
        Button(role: .destructive, action: aktion) {
            Image(systemName: Zeichen.muell)
        }
        .buttonStyle(.borderless)
        .help(hilfe)
        .accessibilityLabel(kennzeichnung)
    }
}

/// Die gemeinsame Form aller Dialoge: ein gruppiertes `Form`, das Liquid Glass,
/// Abstände und Beschriftungsspalten selbst mitbringt.
struct Dialograhmen<Koerper: View, Fuss: View>: View {
    let titel: String
    var unterzeile: String?
    /// Ein Hinweis neben der Unterzeile, mit Info-Zeichen (E1060) — etwa die Empfehlung im Sitzplan ab dem 51. Tisch (E1052). Nur
    /// mit Unterzeile: Ohne sie steht er nicht.
    var hinweis: String?
    var breite: CGFloat = 720
    var hoehe: CGFloat = 640
    /// Eine Mindesthöhe — für ein Blatt, an dem ein hoher Bogen hängt (E694: ⌘O mit „Lerngruppen zuordnen“).
    var mindesthoehe: CGFloat?
    /// Statt des einfachen Schließens, wenn vorher nachzufragen ist.
    var beimSchliessen: (() -> Void)?
    /// Ohne das gruppierte `Form`: Es deckelt seinen Inhalt auf rund 700
    /// Punkt — die Sitzplanfläche braucht die ganze Breite.
    var freierKoerper = false
    /// Welches Blatt das ist, wenn es seine Meldungen zeigen kann: Steht es in `Meldungszeile.eingeschaltet`,
    /// stehen sie in der Lücke seines Fußes (E476, E487; E855: nicht mehr über dem Körper, dort deckten sie die Knöpfe der
    /// Leiste zu), in schmalen Bögen am Blatt „Lernende“ über den Knöpfen (E1061) — die Kapsel des Hauptfensters läge bei
    /// kleinem Fenster unter dem Blatt. Nur die Anzeige; angesagt wird weiter vom Hauptfenster.
    var meldungsblatt: Meldungszeile.Blatt?
    /// Das Blatt hat seine Zeile an einen Bogen darauf abgegeben (E490) — dann zeigt auch das Abbild in seinem Fuß keine
    /// Kapsel, sonst stünde die Meldung zweimal (Z-AX9R2-10).
    var zeileAbgegeben = false
    @ViewBuilder let koerper: Koerper
    @ViewBuilder let fuss: Fuss

    @Environment(\.dismiss) private var schliessen
    /// Ohne Speicher (ein Abbild) sperrt ⎋ nichts.
    @Environment(Planungsspeicher.self) private var speicher: Planungsspeicher?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titel).font(.title3.weight(.semibold))
                    if let unterzeile, let hinweis {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(unterzeile)
                            Label {
                                Text(hinweis)
                            } icon: {
                                Image(systemName: Zeichen.hinweis)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else if let unterzeile {
                        Text(unterzeile).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Group {
                if freierKoerper {
                    koerper
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    Form { koerper }
                        .formStyle(.grouped)
                        .scrollContentBackground(.hidden)
                }
            }

            Blattfuss(meldungsblatt: meldungsblatt, zeileAbgegeben: zeileAbgegeben, breite: breite, senkrecht: 16) {
                fuss
            }
        }
        .frame(width: breite)
        .frame(minHeight: mindesthoehe, maxHeight: hoehe)
        .onExitCommand {
            // In der Lücke nach einer Antwort prallt ⎋ ab, mit Ton (E437).
            guard speicher?.frageSperrtBefehl() != true else { return }
            if let beimSchliessen { beimSchliessen() } else { schliessen() }
        }
    }
}

/// Der Fuß eines Blatts mit seiner Meldungszeile (E476, E487, E855) — ein Baustein für `Dialograhmen` und
/// `Seitenleistenrahmen` (v95, R-BG5-01), damit die Regel an einer Stelle steht. `breite` ist die Breite der Spalte, in
/// der der Fuß steht; `senkrecht` der Abstand oben und unten (im Rahmen mit Leiste 12 statt 16 pt — jeder Punkt gehört
/// dem Inhalt).
struct Blattfuss<Fuss: View>: View {
    let meldungsblatt: Meldungszeile.Blatt?
    let zeileAbgegeben: Bool
    let breite: CGFloat
    let senkrecht: CGFloat
    @ViewBuilder let fuss: Fuss
    @Environment(Planungsspeicher.self) private var speicher: Planungsspeicher?

    var body: some View {
        let eigene = meldungsblatt.map(Meldungszeile.eingeschaltet.contains) == true
        // In schmalen Bögen am Blatt „Lernende“ steht die jüngste Meldung auf eigener Zeile über den Knöpfen (E1061).
        let darueber = eigene && Meldungszeile.ueberDenKnoepfen(meldungsblatt, breite: breite)
        VStack(alignment: .leading, spacing: 8) {
            if darueber, let speicher,
               !Meldungskapseln.gezeigt(speicher.meldungen, nurJuengste: true,
                                        verdraengt: speicher.gewicheneMeldungen).isEmpty {
                Meldungskapseln(kompakt: true, nurJuengste: true)
                    .environment(speicher)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                // Im Abbild zeigt auch ein Blatt ohne eigene Zeile die Meldungen — vorn im Fuß, alle (Z-AX9R3-08).
                if !eigene, !zeileAbgegeben, Meldungszeile.imAbbild, let speicher {
                    Meldungskapseln(kompakt: true).environment(speicher)
                }
                fuss
            }
            .environment(\.meldungImFuss, eigene && !darueber)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, senkrecht)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Ein Fenster trägt nur ein Blatt: An der Hauptansicht angemeldet bliebe
    /// die Rückfrage über einem Dialog unsichtbar.
    func rueckfrage(_ speicher: Planungsspeicher, ort: Rueckfrageort) -> some View {
        let meine = speicher.rueckfrage?.ort == ort ? speicher.rueckfrage : nil
        return alert("Rückfrage", isPresented: Binding(
            get: { meine != nil },
            // Nur die gezeigte Frage geht mit dem Schließen — eine inzwischen gestellte bleibt (Z14b-11).
            set: { if !$0, let gezeigt = meine, speicher.rueckfrage?.id == gezeigt.id { speicher.rueckfrage = nil } }),
                     presenting: meine) { frage in
            if frage.ablehnung.isEmpty {
                // Ein Hinweis ohne zweite Antwort: Ein Knopf, ⎋ schließt ihn ebenso (W3-06).
                Button(frage.bestaetigung, role: .cancel) { speicher.rueckfrageBeantworten(true) }
            } else {
                Button(frage.ablehnung, role: .cancel) { speicher.rueckfrageBeantworten(false) }
                // Die Bestätigung über dem dritten Knopf, wo die Frage es verlangt (E894: „Löschen“ zuerst).
                if frage.bestaetigungZuerst {
                    Button(frage.bestaetigung, role: frage.gefahr ? .destructive : nil) {
                        speicher.rueckfrageBeantworten(true)
                    }
                }
                if let weitere = frage.weitere {
                    Button(weitere, role: frage.weitereGefahr ? .destructive : nil) { speicher.rueckfrageWeitere() }
                }
                if !frage.bestaetigungZuerst {
                    Button(frage.bestaetigung, role: frage.gefahr ? .destructive : nil) {
                        speicher.rueckfrageBeantworten(true)
                    }
                }
            }
        } message: { frage in
            Text(frage.text)
        }
    }
}

/// Ein Datumsfeld: Eingabefeld plus ausklappbarer Kalender. Der eingebaute
/// `DatePicker(.field)` schied aus — er meldet für „3.  8.2026“ die Breite der
/// kurzen Form, der Text stand über dem Rahmen.
///
/// **Angezeigt wird `tag` selbst, keine Kopie davon**; nur solange getippt
/// wird, tritt `getipptes` an seine Stelle. Die Dialoge reichen ihre Bindung
/// über ein Abbild herein — Lesen nach dem Schreiben liefert den alten Wert.
struct Datumsfeld: View {
    @Binding var tag: Tag
    /// Wie weit die Pfeiltasten springen. Sieben dort, wo der Setter auf den
    /// Montag einrastet — ein Tagesschritt verpuffte dann nach oben und ginge
    /// nach unten gleich eine Woche zurück.
    var schritt: Int = 1

    /// Was gerade getippt wird — `nil`, sobald nichts in Arbeit ist.
    @State private var getipptes: String?
    /// Was der letzte Pfeildruck geschrieben hat — zum Abgleich, ob die Bindung
    /// ihn überhaupt angenommen hat.
    @State private var geschoben: Tag?
    @State private var ueberfahren = false
    @State private var kalenderOffen = false
    @FocusState private var fokussiert: Bool
    /// Der Zähler der Seitenwechsel, wenn das Feld auf einer Seite eines Blatts mit Leiste steht, und sein Stand beim
    /// Erscheinen (R-BG5d-01).
    @Environment(\.seitenwechsel) private var seitenwechsel
    @State private var wechselstand: Int?

    /// Der Zwischenstand gilt nur, solange die Bindung ihn angenommen hat: Setter
    /// dürfen abweisen (etwa ein Sperrzeitraum im Prüfungsdialog). Zurücklesen ist
    /// erst im nächsten Durchgang belastbar, also hier statt gleich beim Schreiben.
    private var zwischenstand: String? {
        if let geschoben, geschoben != tag { return nil }
        return getipptes
    }

    private var anzeige: Binding<String> {
        Binding(get: { zwischenstand ?? tag.deutsch },
                set: { getipptes = $0; geschoben = nil })
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("TT.MM.JJJJ", text: anzeige)
                .textFieldStyle(.plain)
                .labelsHidden()
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .focused($fokussiert)
                .frame(width: 88)
                .onSubmit(uebernehmen)
                .onKeyPress(.upArrow) { schieben(schritt) }
                .onKeyPress(.downArrow) { schieben(-schritt) }
                .onChange(of: fokussiert) { _, hat in if !hat { uebernehmen() } }
                // Geht das Feld mit seiner Seite (gleich, wie sie wechselte — `Seitenwechsel`), gilt das Getippte wie beim
                // Fokusverlust — `onChange` käme dann nicht mehr an (R-BG5a-03, R-BG5d-01). Ohne Seitenwechsel bleibt es
                // verworfen wie bisher.
                .onAppear { wechselstand = seitenwechsel?.stand }
                .onDisappear { if let seitenwechsel, seitenwechsel.stand != wechselstand { uebernehmen() } }
                .accessibilityLabel("Datum")

            Button { kalenderOffen = true } label: {
                Image(systemName: Zeichen.kalender).font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Kalender einblenden")
            .accessibilityLabel("Datum im Kalender wählen")
            .popover(isPresented: $kalenderOffen, arrowEdge: .bottom) {
                DatePicker("", selection: Binding(
                    get: { tag.datum },
                    set: { gewaehlt in
                        // `NSDatePicker` meldet je Klick zweimal.
                        guard kalenderOffen else { return }
                        kalenderOffen = false
                        getipptes = nil        // ein Zwischenstand verfällt
                        geschoben = nil
                        tag = Tag(gewaehlt)
                    }),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "de_DE"))
                    .padding(12)
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .background(Systemfarben.feldflaeche, in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(fokussiert ? Color.accentColor
                                         : Systemfarben.feldkante.opacity(ueberfahren ? 1 : 0.55),
                              lineWidth: fokussiert ? 2 : 1)
        }
        .onHover { ueberfahren = $0 }
    }

    /// Verwirft, was sich nicht lesen lässt — ein halb getipptes Datum darf die
    /// Planung nicht verstellen.
    private func uebernehmen() {
        defer { getipptes = nil; geschoben = nil }
        guard let getippt = zwischenstand, let neu = Tag(deutsch: getippt),
              neu != tag else { return }
        tag = neu
    }

    /// Worauf ein Pfeildruck aufsetzt: auf dem zuletzt geschobenen Wert, sonst
    /// auf dem Getippten, sonst auf dem angezeigten Tag.
    ///
    /// Nimmt die Bindung einen geschobenen Wert nicht an — sie darf ihn abweisen
    /// (Sperrzeitraum) oder umformen (der Anlege-Dialog rastet auf Montage ein) —,
    /// steht in `tag` weiter der alte Stand. Von dort aus zu rechnen ergäbe bei
    /// jedem weiteren Druck denselben nicht angenommenen Tag; der Pfeil bewegte
    /// das Feld nie. Vom geschobenen Wert aus wandert er Druck für Druck weiter,
    /// bis die Bindung wieder annimmt.
    static func grundlage(geschoben: Tag?, getipptes: String?, tag: Tag) -> Tag {
        geschoben ?? getipptes.flatMap(Tag.init(deutsch:)) ?? tag
    }

    /// Arbeitet auf dem Zwischenstand weiter, damit schnelle Tastenfolgen
    /// Schritt für Schritt zählen.
    private func schieben(_ tage: Int) -> KeyPress.Result {
        guard fokussiert else { return .ignored }
        let neu = Datumsfeld.grundlage(geschoben: geschoben, getipptes: getipptes,
                                       tag: tag).plus(tage: tage)
        getipptes = neu.deutsch
        geschoben = neu
        tag = neu
        return .handled
    }
}

struct Pruefzeile: View {
    let gut: Bool
    let inhalt: Text

    var body: some View {
        Label {
            inhalt.font(.callout).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: gut ? Zeichen.haken : Zeichen.warnung)
                .foregroundStyle(gut ? Color.green : Color.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
