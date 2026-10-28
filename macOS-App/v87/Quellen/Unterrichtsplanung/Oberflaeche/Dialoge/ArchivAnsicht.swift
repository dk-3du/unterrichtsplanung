// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// ── Das Archiv im Blatt „Lernende“ (E246, E274, E276) ────────────────────
// Die Vorjahre, schreibgeschützt: Schuljahr wählen, Personen, Lerngruppen und
// Anliegen mit Stand lesen. Ändern lässt es sich nur durch die drei
// Löschungen — sie gelten sofort, nicht erst mit „Übernehmen“. Die Planung
// eines Jahres lässt sich wie mit ⌘S als Datei sichern; die Web App zeigt sie.
// Gelesen wird das Archiv erst, wenn diese Ansicht erscheint, und abseits des
// Hauptstrangs. Oben in der Wahl steht seit v86 das laufende Schuljahr (E643,
// E644, E760): seine archivierten Personen und Lerngruppen aus dem Entwurf des
// Blatts, mit „Zurückholen“ — ein Schritt am Entwurf, gesichert mit „Übernehmen“.

/// Was die Archivansicht zu einem Schuljahr zeigt.
enum Archivteil: String, CaseIterable, Sendable {
    case personen, lerngruppen, anliegen

    var titel: String {
        switch self {
        case .personen: "Personen"
        case .lerngruppen: "Lerngruppen"
        case .anliegen: "Anliegen"
        }
    }
}

/// Eine Zeile der Lerngruppen im Archiv — Felder, damit ein Kopfklick ordnet (E362); Mitglieder als Zahl.
struct Archivgruppenzeile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let mitglieder: Int
    /// Der Zeitstempel der Archivierung, leer bei einer aktiven — die Spalte „Archiviert“ im laufenden Schuljahr (E799);
    /// lexikografisch zugleich zeitlich wie „Angelegt“ (E363).
    let archiviert: String
}

/// Eine Zeile der Anliegen im Archiv; `tag` als ISO-Tag — lexikografisch zugleich zeitlich (E363).
struct Archivanliegenzeile: Identifiable, Hashable, Sendable {
    let id: String
    let art: String
    let titel: String
    let lerngruppe: String
    let tag: String
    /// Was die Spalte „Tag“ zeigt: der Tag — bei einer Vereinbarung „gültig bis einschließlich 31.10.2026“, ohne Datum „—“
    /// (E807, Z-R2A1-03); geordnet wird nach `tag`.
    let tagtext: String
    let stand: String
}

/// Die Ordnung der drei Archiv-Tabellen — am Blatt gehalten, damit sie erst mit ihm verfällt (E364, Z-AT2b-07);
/// leer heißt: die Folge wie bisher.
struct Archivordnung: Equatable {
    var personen = Personenzeile.vorgabe
    var gruppen: [KeyPathComparator<Archivgruppenzeile>] = []
    var anliegen: [KeyPathComparator<Archivanliegenzeile>] = []

    /// Die Lerngruppen des laufenden Schuljahrs ordnen für sich — nur dort gibt es die Spalte „Archiviert“ (E799); ein
    /// Klick darauf wirkt nicht in der Tabelle eines Vorjahrs (Z-R2A2-04). Die Vorjahre teilen `gruppen` wie bisher.
    var laufendeGruppen: [KeyPathComparator<Archivgruppenzeile>] = []

    func gruppenordnung(_ wahl: Archivwahl) -> [KeyPathComparator<Archivgruppenzeile>] {
        wahl == .laufend ? laufendeGruppen : gruppen
    }

    mutating func gruppenordnungSetzen(_ neu: [KeyPathComparator<Archivgruppenzeile>], fuer wahl: Archivwahl) {
        if wahl == .laufend { laufendeGruppen = neu } else { gruppen = neu }
    }
}

// ── Das laufende Schuljahr im Archiv (v86, AX1: E643, E644, E760) ─────────

/// Ein Eintrag der Wahl „Schuljahr“ (E760): oben das laufende Schuljahr, darunter die Jahre des Archivs, das jüngste zuerst.
/// Ein eigener Fall statt einer Kennung — keine Kennung aus der Archivdatei kann ihn treffen.
enum Archivwahl: Hashable, Sendable {
    case laufend
    case vorjahr(String)

    struct Eintrag: Identifiable, Hashable, Sendable {
        let wahl: Archivwahl
        let titel: String
        var id: Archivwahl { wahl }
    }

    /// Beim Öffnen gewählt: der oberste Eintrag, das laufende Schuljahr — dort steht, was eben archiviert wurde (E643).
    static let vorwahl = Archivwahl.laufend

    /// Die Einträge der Wahl: das laufende Schuljahr, dann die Vorjahre, das jüngste zuerst. `archiv` ist `nil`, solange das
    /// Archiv gelesen wird oder wenn es sich nicht lesen lässt — der Eintrag des laufenden steht trotzdem.
    static func eintraege(laufend titel: String, archiv: Archivbestand?) -> [Eintrag] {
        [Eintrag(wahl: .laufend, titel: titel)]
            + (archiv.map(vorjahre) ?? []).map { Eintrag(wahl: .vorjahr($0.id), titel: $0.schuljahr) }
    }

    /// Die Jahre des Archivs, das jüngste zuerst.
    static func vorjahre(_ archiv: Archivbestand) -> [Archivjahr] {
        archiv.jahre.sorted { $0.schuljahr > $1.schuljahr }
    }

    /// Nach dem Lesen und nach einer Löschung: Die Wahl bleibt, solange es ihr Jahr gibt; sonst das jüngste übrige — wie
    /// bisher —, ohne Vorjahr das laufende.
    static func nachLesen(_ wahl: Archivwahl, archiv: Archivbestand) -> Archivwahl {
        guard case .vorjahr(let id) = wahl, !archiv.jahre.contains(where: { $0.id == id }) else { return wahl }
        return vorjahre(archiv).first.map { .vorjahr($0.id) } ?? .laufend
    }
}

extension Archivteil {
    /// Die Teile je Eintrag: im laufenden Schuljahr ohne „Anliegen“ — die stehen in der Lerngruppe und an der Person (E760).
    static func teile(_ wahl: Archivwahl) -> [Archivteil] {
        wahl == .laufend ? [.personen, .lerngruppen] : allCases
    }
}

/// Was der Eintrag des laufenden Schuljahrs zeigt (E643, E644, E760): die archivierten Personen und Lerngruppen aus dem
/// Entwurf des Blatts, nicht aus der Archivdatei — rein, damit die Suite es prüft. Wortlaute nach E760.
enum LaufendesSchuljahr {
    static let hinweis = "Archivierte Lerngruppen und Personen des laufenden Schuljahrs. „Zurückholen“ nimmt sie wieder in "
        + "die Listen; gesichert wird mit „Übernehmen“."
    static let nichtsArchiviert = "Im laufenden Schuljahr ist nichts archiviert."
    /// Der Satz von bisher — er bleibt, wenn es auch kein Vorjahr gibt.
    static let archivLeer = "Das Archiv ist leer. Beim Wechsel ins nächste Schuljahr („Neue Planung“) kommt das laufende "
        + "hierher — samt seiner Planung."
    static let zurueckholen = "Zurückholen"
    static let gruppeHilfe = "Wieder in die Listen — mit ihren Mitgliedern"
    static let personHilfe = "Wieder in die Listen"

    /// „2026/27 (laufendes Schuljahr)“
    static func titel(_ schuljahr: String) -> String {
        "\(schuljahr) (laufendes Schuljahr)"
    }

    /// Die Zahl aus der Jahresdatei der geltenden Planung; trägt sie keine, aus dem Beginn der Planung — wie beim Archivieren
    /// (`Archivbestand.mitJahr`).
    static func schuljahr(_ entwurf: Lernendenbestand, planung: Planung?) -> String {
        guard entwurf.schuljahr.isEmpty, let planung else { return entwurf.schuljahr }
        return Lernendenbestand.schuljahr(fuer: planung.start)
    }

    /// Die archivierten Personen, in der Folge der Listen; die Spalte „Lerngruppen“ nennt auch archivierte wie im Archiv.
    static func personen(_ verzeichnis: Lernendenverzeichnis) -> [Personenzeile] {
        verzeichnis.personenzeilen(verzeichnis.alleMitArchivierten.filter { !$0.archiviert.isEmpty }, archivierteGruppen: true)
    }

    /// Die archivierten Lerngruppen, in der Folge der Listen — mit der Zahl ihrer aktiven Mitglieder, wie das Blatt zählt:
    /// „Zurückholen“ bringt die Lerngruppe wieder, eine archivierte Person bleibt archiviert (Z-AX1-01, E793).
    static func gruppen(_ verzeichnis: Lernendenverzeichnis) -> [Archivgruppenzeile] {
        verzeichnis.gruppen(archivierte: true).filter { !$0.archiviert.isEmpty }.map { g in
            Archivgruppenzeile(id: g.id, name: g.name, mitglieder: verzeichnis.mitglieder(g.id).count, archiviert: g.archiviert)
        }
    }

    /// Was steht, wenn nichts archiviert ist — leer, sobald etwas da ist. `vorjahre` ist `nil`, solange das Archiv gelesen
    /// wird oder wenn es sich nicht lesen lässt; dann fehlt der Satz zum leeren Archiv.
    static func leer(personen: Int, gruppen: Int, vorjahre: Int?) -> [String] {
        guard personen == 0, gruppen == 0 else { return [] }
        return [nichtsArchiviert] + (vorjahre == 0 ? [archivLeer] : [])
    }
}

struct ArchivAnsicht: View {
    @Environment(Planungsspeicher.self) private var speicher
    @Binding var ordnung: Archivordnung
    /// Der Entwurf des Blatts und sein Verzeichnis — daraus der Eintrag des laufenden Schuljahrs (E760).
    let entwurf: Lernendenbestand
    let laufend: Lernendenverzeichnis
    /// „Zurückholen“ im Eintrag des laufenden Schuljahrs: derselbe Weg wie im Blatt — ein Schritt am Entwurf (⌘Z),
    /// gesichert mit „Übernehmen“ (E689, E760).
    let gruppeZurueckholen: @MainActor (String) -> Void
    let personZurueckholen: @MainActor (String) -> Void

    private enum Lage: Equatable {
        case liest
        case gelesen(Archivbestand)
        case nichtLesbar(String)
    }

    @State private var lage: Lage = .liest
    @State private var wahl = Archivwahl.vorwahl
    @State private var teil: Archivteil
    @State private var person: String?
    @State private var anliegen: String?
    @State private var groesse: Int?
    /// Je gewähltem Jahr gebaut, nicht je Auswertung des Körpers.
    @State private var verzeichnis: Lernendenverzeichnis?

    /// `startteil`: der Teil beim Öffnen — Prüfstand und Abbild (`Lernendenvorgabe.archivteil`).
    init(ordnung: Binding<Archivordnung>, entwurf: Lernendenbestand, laufend: Lernendenverzeichnis,
         startteil: Archivteil = .personen, gruppeZurueckholen: @escaping @MainActor (String) -> Void,
         personZurueckholen: @escaping @MainActor (String) -> Void) {
        _ordnung = ordnung
        self.entwurf = entwurf
        self.laufend = laufend
        self.gruppeZurueckholen = gruppeZurueckholen
        self.personZurueckholen = personZurueckholen
        _teil = State(initialValue: startteil)
    }

    /// Das Archiv, sobald es gelesen ist — `nil`, solange es gelesen wird oder wenn es sich nicht lesen lässt.
    private var archiv: Archivbestand? {
        if case .gelesen(let archiv) = lage { return archiv }
        return nil
    }

    /// Das gewählte Vorjahr — `nil` beim laufenden Schuljahr.
    private var gewaehlt: Archivjahr? {
        guard case .vorjahr(let id) = wahl else { return nil }
        return archiv?.jahre.first { $0.id == id }
    }

    var body: some View {
        // Der Eintrag des laufenden Schuljahrs steht sofort — die Vorjahre kommen dazu, sobald das Archiv gelesen ist.
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Schuljahr", selection: $wahl) {
                    let titel = LaufendesSchuljahr.titel(LaufendesSchuljahr.schuljahr(entwurf, planung: speicher.planung))
                    ForEach(Archivwahl.eintraege(laufend: titel, archiv: archiv)) { Text($0.titel).tag($0.wahl) }
                }
                .fixedSize()
                if let archiv, let gewaehlt {
                    vorjahrKopf(archiv, gewaehlt)
                } else {
                    Spacer(minLength: 0)
                }
            }
            if let archiv, let gewaehlt {
                vorjahr(archiv, gewaehlt)
            } else {
                laufendesSchuljahr()
            }
        }
        .onChange(of: wahl) { _, _ in jahrLaden() }
        .task { await laden() }
    }

    // ── Lesen und Schreiben ───────────────────────────────────────────────

    private func laden() async {
        let befund = await speicher.lernende.archivLesenAsynchron(stempel: Zeitrechnung.dateistempel())
        switch befund {
        case .nichtLesbar(let grund):
            lage = .nichtLesbar(grund)
        case .gelesen(let archiv, _, _):
            // Ein bereinigtes Archiv meldet der Dienst, wo die Kopie entsteht (Z-AV6-03).
            uebernehmen(archiv)
        }
        groesse = speicher.lernende.archivGroesse()
    }

    /// Ein Stand des Archivs — gelesen oder nach einer Löschung.
    private func uebernehmen(_ archiv: Archivbestand) {
        lage = .gelesen(archiv)
        wahl = Archivwahl.nachLesen(wahl, archiv: archiv)
        jahrLaden()
    }

    private func jahrLaden() {
        let jahr = self.gewaehlt
        verzeichnis = jahr?.lernende.map { Lernendenverzeichnis($0) }
        if let id = person, verzeichnis?.person(id) == nil { person = nil }
        if let id = anliegen, jahr?.lernende?.anliegen.contains(where: { $0.id == id }) != true { anliegen = nil }
    }

    private func schreiben(_ neu: Archivbestand) {
        guard speicher.archivSchreiben(neu) == nil else { return }
        uebernehmen(neu)
        groesse = speicher.lernende.archivGroesse()
    }

    /// Die Wahl des Teils — gezeigt wird ein Teil, den der Eintrag hat; der gewählte bleibt für das nächste Vorjahr.
    private func teilwahl(_ wahl: Archivwahl) -> some View {
        Picker("Teil des Archivs", selection: Binding(get: { gezeigterTeil(wahl) }, set: { teil = $0 })) {
            ForEach(Archivteil.teile(wahl), id: \.self) { Text($0.titel).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private func gezeigterTeil(_ wahl: Archivwahl) -> Archivteil {
        let teile = Archivteil.teile(wahl)
        return teile.contains(teil) ? teil : teile[0]
    }

    // ── Das laufende Schuljahr (E760) ─────────────────────────────────────

    /// Ohne „archiviert am …“, ohne „Planung sichern …“ und „Schuljahr löschen …“, ohne „Anliegen“ — aus dem Entwurf.
    @ViewBuilder
    private func laufendesSchuljahr() -> some View {
        Text(LaufendesSchuljahr.hinweis)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        // Die Größenwarnung auch hier (E798) — gelöscht wird unter dem Eintrag eines Vorjahrs.
        if let warnung = Self.groessenwarnung(groesse, laufend: true) {
            Text(warnung)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Wie es um die Vorjahre steht — die Sätze von bisher, klein unter dem Hinweis.
        switch lage {
        case .liest:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Das Archiv wird gelesen …")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .nichtLesbar(let grund):
            Text("Das Archiv lässt sich nicht lesen (\(grund.ohneSchlusspunkt)). Es bleibt unangetastet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .gelesen:
            EmptyView()
        }
        let personen = LaufendesSchuljahr.personen(laufend)
        let gruppen = LaufendesSchuljahr.gruppen(laufend)
        let leer = LaufendesSchuljahr.leer(personen: personen.count, gruppen: gruppen.count, vorjahre: archiv?.jahre.count)
        if leer.isEmpty {
            teilwahl(.laufend)
            switch gezeigterTeil(.laufend) {
            case .lerngruppen: laufendeGruppen(gruppen)
            default: laufendePersonen(personen)
            }
        } else {
            ForEach(leer, id: \.self) { satz in
                Text(satz)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func laufendePersonen(_ zeilen: [Personenzeile]) -> some View {
        Table(Tabellenordnung.geordnet(zeilen, nach: ordnung.personen), sortOrder: Binding(get: { ordnung.personen }, set: {
            ordnung.personen = Tabellenordnung.mitVorigem($0, vorher: ordnung.personen)
        })) {
            TableColumn(kopf("Nachname", ordnung.personen, \.nachname), sortUsing: Personenspalte.nachname.vergleicher) { z in
                Text(z.nachname)
            }
            TableColumn(kopf("Vorname", ordnung.personen, \.vorname), sortUsing: Personenspalte.vorname.vergleicher) { z in
                Text(z.vorname)
            }
            TableColumn(kopf("Lerngruppen", ordnung.personen, \.lerngruppen),
                        sortUsing: Personenspalte.lerngruppen.vergleicher) { z in
                Text(z.lerngruppen.isEmpty ? "—" : z.lerngruppen)
            }
            TableColumn(kopf("Angelegt", ordnung.personen, \.angelegt), sortUsing: Personenspalte.angelegt.vergleicher) { z in
                Text(Self.tag(z.angelegt))
            }
            .width(90)
            // Je Eintrag ein Knopf (E760).
            TableColumn("") { z in
                Button(LaufendesSchuljahr.zurueckholen) { personZurueckholen(z.id) }
                    .controlSize(.small)
                    .help(LaufendesSchuljahr.personHilfe)
            }
            .width(110)
        }
    }

    private func laufendeGruppen(_ zeilen: [Archivgruppenzeile]) -> some View {
        let eigene = ordnung.gruppenordnung(.laufend)
        return Table(Self.geordnet(zeilen, eigene), sortOrder: Binding(get: { ordnung.gruppenordnung(.laufend) }, set: {
            ordnung.gruppenordnungSetzen(Tabellenordnung.mitVorigem($0, vorher: ordnung.gruppenordnung(.laufend)), fuer: .laufend)
        })) {
            TableColumn(kopf("Lerngruppe", eigene, \.name), value: \.name, comparator: .localizedStandard) { z in
                Text(z.name)
            }
            TableColumn(kopf("Mitglieder", eigene, \.mitglieder), value: \.mitglieder) { z in Text("\(z.mitglieder)") }
                .width(90)
            // Der Tag der Archivierung, geordnet nach dem Zeitstempel — wie „Angelegt“ bei den Personen (E799).
            TableColumn(kopf("Archiviert", eigene, \.archiviert), sortUsing: Self.archiviertOrdnung) { z in
                Text(Self.tag(z.archiviert))
            }
            .width(90)
            TableColumn("") { z in
                Button(LaufendesSchuljahr.zurueckholen) { gruppeZurueckholen(z.id) }
                    .controlSize(.small)
                    .help(LaufendesSchuljahr.gruppeHilfe)
            }
            .width(110)
        }
    }

    // ── Ein Vorjahr ───────────────────────────────────────────────────────

    /// Neben der Wahl: wann und aus welcher Planung archiviert, dazu sichern und löschen.
    @ViewBuilder
    private func vorjahrKopf(_ archiv: Archivbestand, _ gewaehlt: Archivjahr) -> some View {
        Text("archiviert am \(Self.tag(gewaehlt.archiviert)) · Planung „\(gewaehlt.planung.titel)“")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        Spacer(minLength: 0)
        Button("Planung sichern …") { speicher.archivPlanungSichern(gewaehlt) }
            .fixedSize()
            .help("Die Planung dieses Schuljahrs als verschlüsselte Datei sichern — wie ⌘S; "
                  + "sie öffnet mit der Passphrase, auch in der Web App")
        Button("Schuljahr löschen …", role: .destructive) {
            speicher.archivJahrLoeschenFragen(gewaehlt.id, in: archiv) { schreiben($0) }
        }
        .fixedSize()
        .help("Das ganze Schuljahr samt Planung und Lernendendaten endgültig löschen — mit Rückfrage")
    }

    @ViewBuilder
    private func vorjahr(_ archiv: Archivbestand, _ gewaehlt: Archivjahr) -> some View {
        Text(hinweis)
            .font(.caption)
            .foregroundStyle(groesseGross ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)

        // Beim ersten Wechsel vom laufenden Eintrag ist das Verzeichnis noch nicht gebaut (es folgt in `onChange`) — bis
        // dahin aus dem Jahr selbst, statt kurz „keine Lernendendaten“ zu zeigen (Z-AX1-04).
        if let lernende = gewaehlt.lernende {
            let verzeichnis = self.verzeichnis ?? Lernendenverzeichnis(lernende)
            teilwahl(wahl)
            switch gezeigterTeil(wahl) {
            case .personen: personen(archiv, verzeichnis)
            case .lerngruppen: lerngruppen(lernende, verzeichnis)
            case .anliegen: anliegenliste(archiv, gewaehlt, lernende, verzeichnis)
            }
        } else {
            Text("In diesem Schuljahr gab es keine Lernendendaten — archiviert ist nur die Planung.")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Die Hilfen der beiden Löschknöpfe — ohne Kürzel: kein ⌘⌫, einheitlich mit dem Blatt „Lernende“ (E835).
    static let personLoeschenHilfe = "Die Person in allen archivierten Schuljahren endgültig löschen — das laufende bleibt "
        + "unberührt"
    static let anliegenLoeschenHilfe = "Das Anliegen samt seinen Rückläufen endgültig aus dem Archiv löschen"

    private var groesseGross: Bool { (groesse ?? 0) >= Archivdatei.hinweisgroesse }

    private var hinweis: String {
        "Schreibgeschützt — ändern lässt sich das Archiv nur durch Löschen: ein Schuljahr, eine Person "
            + "in allen Schuljahren oder ein Anliegen." + (Self.groessenwarnung(groesse, laufend: false).map { " " + $0 } ?? "")
    }

    /// Ab 64 MB die Warnung (E798): unter einem Vorjahr „… hier löschen.“, unter dem laufenden Schuljahr „… unter ihrem
    /// Eintrag löschen.“ — dort gibt es nichts zu löschen. Die Zahlen aus der Größe und `Archivdatei.hoechstgroesse`.
    nonisolated static func groessenwarnung(_ groesse: Int?, laufend: Bool) -> String? {
        guard let groesse, groesse >= Archivdatei.hinweisgroesse else { return nil }
        return "Das Archiv ist \(groesse / 1024 / 1024) MB groß; ab \(Archivdatei.hoechstgroesse / 1024 / 1024) MB nimmt es "
            + "kein weiteres Schuljahr auf — ältere Schuljahre lassen sich " + (laufend ? "unter ihrem Eintrag" : "hier")
            + " löschen."
    }

    nonisolated static func tag(_ stempel: String) -> String {
        Zeitrechnung.zeitpunkt(aus: stempel).map { Tag($0).deutsch } ?? "—"
    }

    /// Ob die Spalte „Tag“ im Archiv breit wird: nur in einem Jahr, das eine Vereinbarung trägt (Z-R2A2-05).
    nonisolated static func tagspalteBreit(_ lernende: Lernendenbestand) -> Bool {
        lernende.anliegen.contains { $0.art == .vereinbarung }
    }

    /// Die Spalte „Archiviert“ ordnet nach dem Zeitstempel — lexikografisch zugleich zeitlich (E363, E799).
    nonisolated static var archiviertOrdnung: KeyPathComparator<Archivgruppenzeile> {
        KeyPathComparator(\.archiviert, comparator: String.StandardComparator.lexical)
    }

    /// Der Kopf einer Spalte — hervorgehoben, wenn sie vorn ordnet (E498).
    private func kopf<Zeile>(_ titel: String, _ ordnung: [KeyPathComparator<Zeile>], _ pfad: PartialKeyPath<Zeile>) -> Text {
        Ordnungskopf.text(titel, vorn: Lernendenblatt.vorn(ordnung, pfad))
    }

    /// Geordnet nach dem Kopfklick — ohne Klick in der Folge wie bisher.
    private static func geordnet<Zeile: Identifiable>(_ zeilen: [Zeile], _ ordnung: [KeyPathComparator<Zeile>]) -> [Zeile]
        where Zeile.ID == String {
        ordnung.isEmpty ? zeilen : Tabellenordnung.geordnet(zeilen, nach: ordnung)
    }

    /// Die Lerngruppen eines Jahres als Zeilen, in der Folge der Listen.
    nonisolated static func gruppenzeilen(_ verzeichnis: Lernendenverzeichnis) -> [Archivgruppenzeile] {
        verzeichnis.gruppen(archivierte: true).map { g in
            Archivgruppenzeile(id: g.id, name: g.name,
                               mitglieder: verzeichnis.mitglieder(g.id, archivierte: true).count, archiviert: g.archiviert)
        }
    }

    /// Die Anliegen eines Jahres als Zeilen, in der Folge der Jahresdatei.
    nonisolated static func anliegenzeilen(_ lernende: Lernendenbestand,
                                           _ verzeichnis: Lernendenverzeichnis) -> [Archivanliegenzeile] {
        lernende.anliegen.map { a in
            Archivanliegenzeile(id: a.id, art: a.art.titel, titel: a.titel,
                                lerngruppe: verzeichnis.gruppe(a.lerngruppe)?.beschriftung ?? "",
                                tag: a.art == .massnahme || a.art == .vereinbarung ? a.frist : a.datum,
                                tagtext: a.art == .vereinbarung ? Vereinbarungstext.tag(a)
                                    : Anliegenbezug.tagtext(a.art == .massnahme ? a.frist : a.datum),
                                stand: standtext(a, verzeichnis))
        }
    }

    // ── Personen ──────────────────────────────────────────────────────────

    private func personen(_ archiv: Archivbestand, _ verzeichnis: Lernendenverzeichnis) -> some View {
        let liste = Tabellenordnung.geordnet(
            verzeichnis.personenzeilen(verzeichnis.alleMitArchivierten, archivierteGruppen: true), nach: ordnung.personen)
        return VStack(alignment: .leading, spacing: 8) {
            Table(liste, selection: $person, sortOrder: Binding(get: { ordnung.personen }, set: {
                ordnung.personen = Tabellenordnung.mitVorigem($0, vorher: ordnung.personen)
            })) {
                TableColumn(kopf("Nachname", ordnung.personen, \.nachname), sortUsing: Personenspalte.nachname.vergleicher) { z in
                    Text(z.nachname)
                }
                TableColumn(kopf("Vorname", ordnung.personen, \.vorname), sortUsing: Personenspalte.vorname.vergleicher) { z in
                    Text(z.vorname)
                }
                TableColumn(kopf("Lerngruppen", ordnung.personen, \.lerngruppen),
                            sortUsing: Personenspalte.lerngruppen.vergleicher) { z in
                    Text(z.lerngruppen.isEmpty ? "—" : z.lerngruppen)
                }
                TableColumn(kopf("Angelegt", ordnung.personen, \.angelegt), sortUsing: Personenspalte.angelegt.vergleicher) { z in
                    Text(Self.tag(z.angelegt))
                }
                .width(90)
            }
            if let id = person, let p = verzeichnis.person(id) {
                HStack(spacing: 8) {
                    Text(p.anzeigename).font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("In allen Schuljahren löschen …", role: .destructive) {
                        speicher.archivPersonLoeschenFragen(p.id, in: archiv) { schreiben($0) }
                    }
                    .help(Self.personLoeschenHilfe)
                }
                .padding(8)
                .background(.quinary, in: .rect(cornerRadius: 8))
            }
        }
    }

    // ── Lerngruppen ───────────────────────────────────────────────────────

    private func lerngruppen(_ lernende: Lernendenbestand, _ verzeichnis: Lernendenverzeichnis) -> some View {
        Table(Self.geordnet(Self.gruppenzeilen(verzeichnis), ordnung.gruppen), sortOrder: Binding(get: { ordnung.gruppen }, set: {
            ordnung.gruppen = Tabellenordnung.mitVorigem($0, vorher: ordnung.gruppen)
        })) {
            TableColumn(kopf("Lerngruppe", ordnung.gruppen, \.name), value: \.name, comparator: .localizedStandard) { z in
                Text(z.name)
            }
            TableColumn(kopf("Mitglieder", ordnung.gruppen, \.mitglieder), value: \.mitglieder) { z in Text("\(z.mitglieder)") }
                .width(90)
        }
    }

    // ── Anliegen mit Stand ────────────────────────────────────────────────

    private func anliegenliste(_ archiv: Archivbestand, _ jahr: Archivjahr, _ lernende: Lernendenbestand,
                               _ verzeichnis: Lernendenverzeichnis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if lernende.anliegen.isEmpty {
                Text("In diesem Schuljahr gab es keine Mitteilungen, Maßnahmen oder Termine.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                Table(Self.geordnet(Self.anliegenzeilen(lernende, verzeichnis), ordnung.anliegen), selection: $anliegen,
                      sortOrder: Binding(get: { ordnung.anliegen }, set: {
                          ordnung.anliegen = Tabellenordnung.mitVorigem($0, vorher: ordnung.anliegen)
                      })) {
                    TableColumn(kopf("Art", ordnung.anliegen, \.art), value: \.art, comparator: .localizedStandard) { z in
                        Text(z.art)
                    }
                    .width(90)
                    TableColumn(kopf("Titel", ordnung.anliegen, \.titel), value: \.titel, comparator: .localizedStandard) { z in
                        Text(z.titel)
                    }
                    TableColumn(kopf("Lerngruppe", ordnung.anliegen, \.lerngruppe), value: \.lerngruppe,
                                comparator: .localizedStandard) { z in
                        Text(z.lerngruppe.isEmpty ? "—" : z.lerngruppe)
                    }
                    TableColumn(kopf("Tag", ordnung.anliegen, \.tag), value: \.tag,
                                comparator: String.StandardComparator.lexical) { z in
                        Text(z.tagtext)
                    }
                    // „gültig bis einschließlich 31.10.2026“ (E807) braucht mehr als die 90 pt eines Tags — nur in einem Jahr mit
                    // Vereinbarung; sonst bleibt die Spalte bei 90 (Z-R2A2-05).
                    .width(min: 90, ideal: Self.tagspalteBreit(lernende) ? 230 : 90, max: Self.tagspalteBreit(lernende) ? nil : 90)
                    TableColumn(kopf("Stand", ordnung.anliegen, \.stand), value: \.stand, comparator: .localizedStandard) { z in
                        Text(z.stand)
                    }
                }
                // Je Jahr eine eigene Tabelle — sonst behielte sie beim Wechsel von Vorjahr zu Vorjahr die Breiten des
                // vorigen, auch die der Spalte „Tag“ (Z-R2A2N-02).
                .id(jahr.id)
                if let id = anliegen, let a = lernende.anliegen.first(where: { $0.id == id }) {
                    HStack(spacing: 8) {
                        Text(a.titel).font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Löschen …", role: .destructive) {
                            speicher.archivAnliegenLoeschenFragen(a.id, imJahr: jahr.id, in: archiv) { schreiben($0) }
                        }
                        .help(Self.anliegenLoeschenHilfe)
                    }
                    .padding(8)
                    .background(.quinary, in: .rect(cornerRadius: 8))
                }
            }
        }
    }

    /// „8 erledigt · 1 abgelehnt · 3 offen“ — bei einer Maßnahme „erfüllt / nicht erfüllt“,
    /// bei einem Termin „stattgefunden / abgesagt“.
    nonisolated private static func standtext(_ a: Anliegen, _ verzeichnis: Lernendenverzeichnis) -> String {
        // Eine Vereinbarung: „1 gültig · 1 ungültig“ (Tabelle 9, E755).
        if a.art == .vereinbarung {
            let staende = a.betroffene.map { verzeichnis.gueltigkeit(a, $0) }
            return Vereinbarungstext.standtext(gueltig: staende.filter { $0 == .gueltig }.count,
                                               ungueltig: staende.filter { $0 == .ungueltig }.count)
        }
        let staende = a.betroffene.map { verzeichnis.stand(a.id, $0) }
        return Rueckmeldestand.allCases.compactMap { s -> String? in
            let n = staende.filter { $0 == s }.count
            return n == 0 ? nil : "\(n) \(s.beschriftung(fuer: a.art))"
        }.joined(separator: " · ")
    }
}
