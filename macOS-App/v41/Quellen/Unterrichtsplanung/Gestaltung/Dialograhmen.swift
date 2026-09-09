// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Die gemeinsame Form aller Dialoge: ein gruppiertes `Form`, das Liquid Glass,
/// Abstände und Beschriftungsspalten selbst mitbringt.
struct Dialograhmen<Koerper: View, Fuss: View>: View {
    let titel: String
    var unterzeile: String?
    var breite: CGFloat = 720
    var hoehe: CGFloat = 640
    /// Statt des einfachen Schließens, wenn vorher nachzufragen ist.
    var beimSchliessen: (() -> Void)?
    @ViewBuilder let koerper: Koerper
    @ViewBuilder let fuss: Fuss

    @Environment(\.dismiss) private var schliessen

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titel).font(.title3.weight(.semibold))
                    if let unterzeile {
                        Text(unterzeile).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Form { koerper }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)

            HStack(spacing: 12) { fuss }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: breite)
        .frame(maxHeight: hoehe)
        .onExitCommand { if let beimSchliessen { beimSchliessen() } else { schliessen() } }
    }
}

extension View {
    /// Ein Fenster trägt nur ein Blatt: An der Hauptansicht angemeldet bliebe
    /// die Rückfrage über einem Dialog unsichtbar.
    func rueckfrage(_ speicher: Planungsspeicher, ort: Rueckfrageort) -> some View {
        let meine = speicher.rueckfrage?.ort == ort ? speicher.rueckfrage : nil
        return alert("Rückfrage", isPresented: Binding(
            get: { meine != nil },
            set: { if !$0, speicher.rueckfrage?.ort == ort { speicher.rueckfrage = nil } }),
                     presenting: meine) { frage in
            Button("Abbrechen", role: .cancel) { speicher.rueckfrageBeantworten(false) }
            Button(frage.bestaetigung, role: frage.gefahr ? .destructive : nil) {
                speicher.rueckfrageBeantworten(true)
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
