// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Reihenfolgewächter der Autosicherung.
///
/// Der entprellte Auftrag wandelt abseits des Hauptstrangs um und schreibt
/// deshalb später, als er seinen Stand gelesen hat; `jetztSichern()` schreibt
/// gleichlaufend dazwischen. Jeder Schreibvorgang zieht vorher — auf dem
/// Hauptakteur, also in der Reihenfolge der Änderungen — eine fortlaufende
/// Nummer und gibt sie hier ab: Ein überholter Auftrag legt seinen älteren
/// Stand nicht mehr über den jüngeren, und ein Stand, der bereits auf der
/// Platte liegt, wird nicht ein zweites Mal geschrieben — sonst wäre
/// `planung-vorher.json` nur noch eine Kopie von `planung.json`.
///
/// Wie `Ablage` bewusst eine Sperre und kein Akteur: Ein `await` beim Beenden
/// ließe die App hängen. Eine je Ablage, nicht je Prozess.
final class Sicherungsfolge: @unchecked Sendable {
    enum Ergebnis: Equatable {
        /// Geschrieben — die Byte auf der Platte.
        case geschrieben(Int)
        case unveraendert, ueberholt
        /// Nicht geschrieben: Die Datei läge mit so vielen Byte über der
        /// Schreibgrenze; der letzte gute Stand bleibt liegen.
        case zuGross(Int)
    }

    private let ablage: Ablage
    /// Die Lesegrenze von App und Ansicht — was darüber liegt, wird nicht
    /// geschrieben, sonst legte der nächste Start die eigene Ablage beiseite.
    private let grenze: Int
    private let sperre = NSLock()
    private var vergeben = 0
    private var letzteNummer = 0
    private var letzterStand: String?

    init(ablage: Ablage, hoechstens grenze: Int) {
        self.ablage = ablage
        self.grenze = grenze
    }

    func naechsteNummer() -> Int {
        sperre.withLock {
            vergeben += 1
            return vergeben
        }
    }

    /// Der nächste Schreibvorgang geht auch bei unverändertem Stand auf die
    /// Platte — wenn sich nicht die Planung, sondern ihre Hülle geändert hat
    /// (Tresor gesetzt, Wicklung getauscht, Schlüssel erneuert).
    func neuSchreibenErzwingen() {
        sperre.withLock { letzterStand = nil }
    }

    /// `daten` ist Klartext; versiegelt wird in der Ablage, unter `tresor`.
    func schreiben(nummer: Int, stand: String, daten: Data, tresor: Tresor?) throws -> Ergebnis {
        try sperre.withLock {
            guard nummer > letzteNummer else { return .ueberholt }
            letzteNummer = nummer
            guard stand != letzterStand else { return .unveraendert }
            let groesse: Int
            do { groesse = try ablage.schreiben(daten, tresor: tresor, hoechstens: grenze) }
            catch let fehler as Ablage.Schreibfehler { return .zuGross(fehler.groesse) }
            letzterStand = stand
            return .geschrieben(groesse)
        }
    }
}

/// Alles, was die Planung auf eine Platte schreibt oder von dort liest: die
/// laufende Sicherung in der Ablage — entprellt oder sofort, in fester
/// Reihenfolge — und die verschlüsselte Kopie außer Haus im Zielordner des
/// Nutzers. Die Ablage kommt herein; `Ablage.shared` kennt nur der Delegat,
/// Prüfungen bringen `Ablage(ordner: temp)` mit. Gemeldet wird hier nichts:
/// Der Speicher liest die Lage ab und spricht.
@MainActor
@Observable
final class Sicherungsdienst {
    // ── Die Grenzen der eigenen Ablage — beide hier, nirgends sonst ────────

    /// Was über der Lesegrenze von App und Ansicht läge, wird nicht geschrieben:
    /// Der nächste Start legte die eigene Ablage sonst beiseite.
    nonisolated static let schreibgrenze = Planungsdatei.hoechstgroesse
    /// Bis hierher wird die eigene Ablage noch gelesen: Bis v42 schrieb die
    /// Autosicherung jede Größe; ein solcher Bestand wird geladen und liegt
    /// still, bis er unter der Schreibgrenze ist. Darüber hat diese App nicht
    /// geschrieben.
    nonisolated static let lesedecke = 4 * schreibgrenze

    let ablage: Ablage
    /// Eine Vorschau (Prüfungen) schreibt absichtlich nicht — das ist keine
    /// Störung und gehört nicht in die Werkzeugleiste.
    let istVorschau: Bool
    /// Die Lesezeichen und der Zielordner der Kopie — an dieser Ablage, einer
    /// je Dienst: Ein Prüflauf mit eigener Ablage hat seinen eigenen Vorrat.
    let zugriff: Ordnerzugriff
    /// Die Sitzpläne neben der Planung — unter demselben Schutz wie sie.
    let sitzplaene: Sitzplandienst

    private let folge: Sicherungsfolge
    @ObservationIgnored private var auftrag: Task<Void, Never>?

    /// Warum gerade nichts auf die Platte kommt.
    enum Stoerung: Equatable {
        /// Das Schreiben selbst schlug fehl.
        case schreiben
        /// Die Planung läge mit so vielen Byte über der Lesegrenze — nicht
        /// geschrieben, der letzte gute Stand bleibt liegen.
        case zuGross(Int)

        var text: String {
            switch self {
            case .schreiben:
                "Die Autosicherung schlägt fehl. Bitte über „Export“ als Datei sichern."
            case .zuGross(let groesse):
                "Die Planung ist mit \(groesse / 1024 / 1024) MB über der Schreibgrenze "
                    + "(\(Sicherungsdienst.schreibgrenze / 1024 / 1024) MB — zugleich die Lesegrenze von App "
                    + "und Ansicht). Die Autosicherung schreibt sie nicht — auf der Platte bleibt der "
                    + "zuletzt gesicherte Stand. Bitte Beschreibungen und Kommentare kürzen oder Vorhaben "
                    + "entfernen; danach sichert die App wieder von selbst."
            }
        }

        /// Derselbe Sachverhalt in einem Nebensatz — für die Meldung eines
        /// Übergangs und für sein Blatt; den ganzen Satz spricht `lageMelden`.
        var kurz: String {
            switch self {
            case .schreiben:
                "die Ablage lässt sich nicht schreiben"
            case .zuGross(let groesse):
                "die Planung ist mit \(groesse / 1024 / 1024) MB über der Schreibgrenze von "
                    + "\(Sicherungsdienst.schreibgrenze / 1024 / 1024) MB"
            }
        }
    }

    /// Zeitstempel des zuletzt geschriebenen Standes.
    private(set) var gesicherterStand: String?
    private(set) var letzteSicherung: Date?
    private(set) var stoerung: Stoerung?
    var gestoert: Bool { stoerung != nil }
    /// Byte der Ablage auf der Platte — bei `.zuGross` die der verweigerten
    /// Planung. Die Kennzahl im Einstellungen-Stand.
    private(set) var ablagegroesse: Int?
    /// Die Fassung davor (`planung-vorher.json`) ließ sich beim letzten
    /// Schreiben nicht fortschreiben — der Grund, gemeldet einmal je Wechsel.
    /// Keine Störung der Sicherung: Die Ablage selbst ist geschrieben.
    private(set) var vorgaengerStoerung: String?
    /// Gesetzt, wenn ein vorhandener Stand nicht gelesen werden konnte — dann
    /// wird nichts geschrieben, damit er nicht verlorengeht.
    var gesperrt = false
    /// Nur die Startsperre nach unlesbarem Stand lässt sich wieder aufheben;
    /// die einer Vorschau bleibt für deren ganze Lebensdauer bestehen.
    var startsperre = false

    /// Für die Werkzeugleiste: Seit wann auch immer — es wird gerade nichts
    /// gesichert, und das muss sichtbar bleiben, nicht nur kurz aufblitzen.
    var liegtStill: Bool { !istVorschau && (gesperrt || gestoert) }

    /// Der Hinweis an der Werkzeugleiste: der Grund, wo er bekannt ist.
    var stillgrund: String {
        stoerung?.text ?? "Die Autosicherung schreibt gerade nicht. Hier als JSON-Datei sichern (⌘S)."
    }

    /// Die Sitzung, die geschrieben wird — abgefragt, wenn der Auftrag feuert,
    /// nicht wenn er angestoßen wird: Dazwischen tippt der Nutzer weiter.
    @ObservationIgnored var sitzungsquelle: @MainActor () -> Planungssitzung = { .leer }
    /// Die Meldungssenke des Speichers — die Sicherung ist in Störung
    /// geraten, einmal je Wechsel.
    @ObservationIgnored var melden: @MainActor (String, Meldung.Art) -> Void = { _, _ in }

    init(ablage: Ablage, vorschau: Bool = false) {
        self.ablage = ablage
        istVorschau = vorschau
        folge = Sicherungsfolge(ablage: ablage, hoechstens: Sicherungsdienst.schreibgrenze)
        zugriff = Ordnerzugriff(ablage: ablage)
        sitzplaene = Sitzplandienst(ablage: ablage, vorschau: vorschau)
        // Über die Schranke: Ein Prüflauf erbt die Kopie nicht — sonst schriebe
        // er in den echten Ordner.
        kopieAktiv = Einstellungen.wert(Einstellungen.Schluessel.autoexportAktiv) ?? false
    }

    // ── Die laufende Sicherung ────────────────────────────────────────────

    /// Nach jeder Änderung; schreibt entprellt.
    func sichern() {
        auftrag?.cancel()
        auftrag = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.imHintergrundSichern()
        }
    }

    /// Umwandeln und Schreiben laufen abseits des Hauptstrangs (4,9 ms bei 400
    /// Vorhaben). Beim Beenden bleibt es bei `jetztSichern()`.
    private func imHintergrundSichern() async {
        let sitzung = sitzungsquelle()
        guard let planung = sitzung.planung, !gesperrt,
              planung.geaendert != gesicherterStand else { return }
        let stand = planung.geaendert
        // Die Nummer wird vor dem `await` gezogen: Schreibt `jetztSichern()`
        // währenddessen einen jüngeren Stand, verwirft die Sicherungsfolge
        // diesen hier, statt ihn darüberzulegen.
        let nummer = folge.naechsteNummer()
        let folge = self.folge
        let ergebnis = await Task.detached(priority: .utility) { () -> Sicherungsfolge.Ergebnis? in
            // Die Serialisierungsgrenze liefert Klartext und Schlüssel — die
            // Ablage versiegelt.
            guard let (klartext, tresor) = try? sitzung.planungsdatenZumSpeichern() else { return nil }
            return try? folge.schreiben(nummer: nummer, stand: stand, daten: klartext, tresor: tresor)
        }.value
        guard let ergebnis else {
            lageMelden(.schreiben)
            return
        }
        uebernehmen(ergebnis, stand: stand)
    }

    /// Was die Sicherungsfolge zurückgab, in die Merker — und in die Lage.
    private func uebernehmen(_ ergebnis: Sicherungsfolge.Ergebnis, stand: String) {
        switch ergebnis {
        case .geschrieben(let groesse):
            gesicherterStand = stand
            letzteSicherung = Date()
            ablagegroesse = groesse
            vorgaengerAblesen()
        case .unveraendert:
            // Ein gleichlaufender Weg hat diesen Stand schon hingelegt; offen
            // war nur noch der Merker.
            gesicherterStand = stand
        case .ueberholt:
            // Auf der Platte liegt ein jüngerer Stand — nichts zu melden.
            return
        case .zuGross(let groesse):
            ablagegroesse = groesse
            lageMelden(.zuGross(groesse))
            return
        }
        lageMelden(nil)
    }

    /// Ohne Entprellung — beim Wegschalten und beim Beenden, durchgängig
    /// gleichlaufend.
    func jetztSichern() {
        let sitzung = sitzungsquelle()
        auftrag?.cancel()
        auftrag = nil
        guard let planung = sitzung.planung, !gesperrt else { return }
        // Sonst verdrängte jedes Wegschalten die Vorgängerfassung durch eine Kopie.
        guard planung.geaendert != gesicherterStand else { return }
        // Wartet, falls ein abgetrennter Auftrag gerade schreibt (Millisekunden);
        // genau daraus entsteht die Reihenfolge zwischen beiden Wegen.
        let nummer = folge.naechsteNummer()
        do {
            let (klartext, tresor) = try sitzung.planungsdatenZumSpeichern()
            uebernehmen(try folge.schreiben(nummer: nummer, stand: planung.geaendert,
                                            daten: klartext, tresor: tresor),
                        stand: planung.geaendert)
        } catch {
            lageMelden(.schreiben)
        }
    }

    /// Warum ein Übergang des Schutzes nicht auf die Platte kam.
    enum Schreibhindernis: Error, Equatable {
        /// Eine Vorschau schreibt nicht.
        case vorschau
        /// Keine Planung in der Sitzung — leer oder gesperrt.
        case nichtsZuSchreiben
        /// Ein unlesbarer Stand liegt noch im Weg.
        case gesperrt
        case schreiben(String)
    }

    /// Der werfende Zwilling von `jetztSichern()` für die Übergänge des
    /// Schutzes (Einschalten, Erneuern, Passphrase ändern, Aufheben): schreibt
    /// die Hülle neu — auch bei unverändertem Stand — und sagt, wenn es nicht
    /// ging. Ob es ging, belegt danach `ablagelage()`, nicht diese Rückkehr.
    func sofortSchreiben() throws(Schreibhindernis) {
        let sitzung = sitzungsquelle()
        auftrag?.cancel()
        auftrag = nil
        guard !istVorschau else { throw .vorschau }
        guard !gesperrt else { throw .gesperrt }
        guard let planung = sitzung.planung else { throw .nichtsZuSchreiben }
        neuSchreibenErzwingen()
        let nummer = folge.naechsteNummer()
        let ergebnis: Sicherungsfolge.Ergebnis
        do {
            let (klartext, tresor) = try sitzung.planungsdatenZumSpeichern()
            ergebnis = try folge.schreiben(nummer: nummer, stand: planung.geaendert,
                                           daten: klartext, tresor: tresor)
        } catch {
            lageMelden(.schreiben)
            throw .schreiben(Stoerung.schreiben.kurz + " (" + error.localizedDescription.ohneSchlusspunkt + ")")
        }
        uebernehmen(ergebnis, stand: planung.geaendert)
        if case .zuGross(let groesse) = ergebnis { throw .schreiben(Stoerung.zuGross(groesse).kurz) }
    }

    /// Warum ein Übergang des Schutzes gar nicht erst beginnt: Die Planung liegt
    /// über der Schreibgrenze — jede neue Hülle bliebe in der Sitzung, die
    /// Platte behielte die alte. Das Blatt zeigt den Grund und sperrt die Knöpfe.
    var schreibsperrgrund: String? {
        if case .zuGross = stoerung, !istVorschau { return stoerung?.kurz }
        return nil
    }

    /// Was auf der Platte liegt — zum Rücklesen nach einem Übergang.
    enum Ablagelage: Equatable {
        case keine
        case klartext
        case versiegelt(kennung: Data)
        case unlesbar(String)
    }

    func ablagelage() -> Ablagelage {
        switch ablageLesen() {
        case .keine: return .keine
        case .unlesbar(let fehler): return .unlesbar(fehler.localizedDescription)
        case .zuGross(let groesse): return .unlesbar("ungewöhnlich groß (\(groesse / 1024 / 1024) MB)")
        case .daten(let roh):
            guard Tresor.istBehaelter(roh) else { return .klartext }
            do { return .versiegelt(kennung: try Tresor.kopfLesen(roh).kennung) }
            catch { return .unlesbar(error.localizedDescription) }
        }
    }

    // ── Die eigene Ablage lesen — immer bis zur Decke ─────────────────────

    func ablageLesen() -> Ablage.Bestand {
        ablage.lesen(hoechstens: Sicherungsdienst.lesedecke)
    }

    func vorigeFassungLesen() -> Data? {
        ablage.vorigeFassungLesen(hoechstens: Sicherungsdienst.lesedecke)
    }

    @discardableResult
    func altbestaendeVersiegeln(mit tresor: Tresor, alter: Tresor? = nil,
                                nurKlartext: Bool = false) -> Ablage.Nebendateienbilanz {
        ablage.altbestaendeVersiegeln(mit: tresor, alter: alter, nurKlartext: nurKlartext,
                                      hoechstens: Sicherungsdienst.lesedecke)
    }

    func altbestaendeEntsiegeln(_ tresor: Tresor) -> Ablage.Nebendateienbilanz {
        ablage.altbestaendeEntsiegeln(tresor, hoechstens: Sicherungsdienst.lesedecke)
    }

    /// Alles neu schreiben, was die App erreicht — auch ohne Änderung an der
    /// Planung: Die Hülle hat gewechselt (Tresor gesetzt, Wicklung getauscht,
    /// Schlüssel erneuert).
    func neuSchreibenErzwingen() {
        gesicherterStand = nil
        folge.neuSchreibenErzwingen()
    }

    /// Nach dem Laden von der Platte: Dieser Stand liegt dort schon.
    func standUebernommen(_ geaendert: String) {
        gesicherterStand = geaendert
        (letzteSicherung, ablagegroesse) = ablage.stand()
    }

    /// Nach jedem Schreiben: Blieb die Fassung davor stehen, wird es einmal
    /// gesagt — und einmal, wenn es wieder geht, still.
    private func vorgaengerAblesen() {
        let neu = ablage.vorgaengerStoerung
        let wechsel = (vorgaengerStoerung == nil) != (neu == nil)
        vorgaengerStoerung = neu
        guard wechsel, let neu else { return }
        melden("Die Fassung davor (planung-vorher.json) ließ sich nicht fortschreiben: "
               + "\(neu.ohneSchlusspunkt) — die Autosicherung selbst ist geschrieben; als Fassung "
               + "davor bleibt die ältere liegen.", .warnung)
    }

    /// Gemeldet wird einmal je Wechsel der Art — eine Planung, die über der
    /// Grenze weiterwächst, ist dieselbe Störung.
    func lageMelden(_ neu: Stoerung?) {
        let wechsel = switch (stoerung, neu) {
        case (nil, nil), (.schreiben, .schreiben), (.zuGross, .zuGross): false
        default: true
        }
        if neu != stoerung { stoerung = neu }
        guard wechsel, let neu else { return }
        melden(neu.text, .warnung)
    }

    /// Legt der Nutzer bewusst eine Planung an oder öffnet eine Datei, ist der
    /// unlesbare Stand nicht mehr das, was die Sperre schützen soll. Er wird
    /// beiseitegelegt; erst wenn das gelang, darf wieder geschrieben werden.
    func startsperreAufheben() {
        guard startsperre else { return }
        guard ablage.beschaedigtenStandBeiseitelegen(stempel: Zeitrechnung.dateistempel()) else { return }
        vorigeFassungMitstempeln()
        startsperre = false
        gesperrt = false
        stoerung = nil
    }

    /// Legt eine Kopie der vorhandenen `planung-vorher.json` unter einem
    /// Stempelnamen daneben.
    ///
    /// Sie ist nach einem unlesbaren Stand die letzte maschinell lesbare
    /// Fassung, und `Ablage.schreiben` schiebt beim zweiten Schreibvorgang die
    /// neue Planung darüber. Aufzurufen, solange das Schreiben gesperrt ist
    /// oder keine `planung.json` daneben liegt — nur dann kommt der
    /// Sicherungsweg der Kopie nicht in die Quere.
    func vorigeFassungMitstempeln() {
        let verwaltung = FileManager.default
        let quelle = ablage.vorherigeFassung
        guard verwaltung.fileExists(atPath: quelle.path) else { return }
        let ziel = ablage.ordner.appendingPathComponent(
            "planung-vorher-\(Zeitrechnung.dateistempel()).json", isDirectory: false)
        guard !verwaltung.fileExists(atPath: ziel.path) else { return }
        try? verwaltung.copyItem(at: quelle, to: ziel)
    }

    // ── Die Kopie außer Haus ──────────────────────────────────────────────

    var kopieAktiv: Bool {
        didSet { Einstellungen.setzen(kopieAktiv, Einstellungen.Schluessel.autoexportAktiv) }
    }

    /// Leer heißt: noch keiner gewählt — oder die Lesezeichen sind noch zu.
    /// Geführt im Ordnerzugriff: in den Einstellungen oder, bei eingeschalteter
    /// Verschlüsselung, im Behälter neben der Ablage.
    var kopieOrdner: String {
        get { zugriff.zielordner }
        set { zugriff.zielordner = newValue }
    }

    private(set) var letzteKopie: Date?

    /// Warum der Zielordner gerade nicht zu erreichen ist.
    enum Zielordnerlage: Error, Equatable {
        /// Gelöscht, umbenannt ohne Lesezeichen, oder der Datenträger fehlt.
        case fehlt
        /// Im Sandbox ohne Lesezeichen — der Ort wurde in dieser Fassung noch
        /// nicht gewählt.
        case keinZugriff
    }

    /// Die Arbeit im Zielordner, im Sicherheitsbereich seines Lesezeichens.
    /// Ein umbenannter Ordner wird über das Lesezeichen wiedergefunden, der
    /// Pfad nachgeführt. Ohne Lesezeichen reicht der Pfad nur ohne Sandbox.
    func imZielordner<T>(_ arbeit: (URL) throws -> T) throws -> T {
        let gemerkt = URL(fileURLWithPath: kopieOrdner, isDirectory: true)
        guard zugriff.zustaendig(fuer: gemerkt.path) != nil else {
            guard !Ordnerzugriff.imSandbox else { throw Zielordnerlage.keinZugriff }
            guard istOrdner(gemerkt) else { throw Zielordnerlage.fehlt }
            return try arbeit(gemerkt)
        }
        do {
            return try zugriff.mit(gemerkt.path) { ordner in
                guard istOrdner(ordner) else { throw Zielordnerlage.fehlt }
                if ordner.path != kopieOrdner { kopieOrdner = ordner.path }
                return try arbeit(ordner)
            }
        } catch let fehler as Ordnerzugriff.Fehler {
            throw fehler.art == .unaufloesbar ? Zielordnerlage.fehlt : Zielordnerlage.keinZugriff
        }
    }

    private func istOrdner(_ ziel: URL) -> Bool {
        var ordner: ObjCBool = false
        return FileManager.default.fileExists(atPath: ziel.path, isDirectory: &ordner)
            && ordner.boolValue
    }

    /// Nachrüsten für eine Einstellung, die nur den Pfad kennt: Wer den
    /// Zielordner einmal ohne Lesezeichen gewählt hat, bekommt es hier — ohne
    /// Sandbox. Im Sandbox steht der Ordner nicht offen; dann fragt die
    /// Nachwahl. Ein Lesezeichen ohne Sicherheitsbereich (Einstellung von vor
    /// dem Sandbox) ist gegenstandslos und wird entfernt.
    func lesezeichenNachruesten() {
        Einstellungen.entfernen(Einstellungen.Schluessel.autoexportLesezeichenAlt)
        guard !kopieOrdner.isEmpty,
              zugriff.zustaendig(fuer: kopieOrdner) == nil else { return }
        let ordner = URL(fileURLWithPath: kopieOrdner, isDirectory: true)
        guard istOrdner(ordner) else { return }
        lesezeichenAblegen(ordner)
    }

    /// Ein Ort, der der App gerade offensteht, bekommt sein Lesezeichen —
    /// wenn noch keines für ihn gilt: Eine Wahl über den Dialog hat ihn schon
    /// gemerkt. Misslingt es, fragt der nächste Start.
    func lesezeichenAblegen(_ ordner: URL) {
        guard zugriff.zustaendig(fuer: ordner.path) == nil else { return }
        _ = try? zugriff.merken(ordner)
    }

    /// Warum keine Kopie geschrieben wurde.
    enum Kopiehindernis: Error {
        /// Keine Planung in der Sitzung — leer oder gesperrt.
        case nichtsZuSchreiben
        /// Die Kopie gibt es nur verschlüsselt.
        case keinTresor
        case zielordner(Zielordnerlage)
        case schreiben(ordner: URL, fehler: any Error)
    }

    /// Die Kopie im Zielordner — nur verschlüsselt, atomar; liefert die Datei
    /// und ihre Größe (der Aufrufer nennt, wenn sie über der Lesegrenze liegt).
    /// Läuft beim Beenden: Nichts wartet auf einen Ablaufwechsel.
    func kopieSchreiben(_ sitzung: Planungssitzung, name: String) throws(Kopiehindernis) -> (ziel: URL, groesse: Int) {
        guard let planung = sitzung.planung else { throw .nichtsZuSchreiben }
        do {
            return try imZielordner { ordner in
                guard let tresor = sitzung.tresor else { throw Kopiehindernis.keinTresor }
                let ziel = ordner.appending(component: name, directoryHint: .notDirectory)
                let daten: Data
                do {
                    daten = try tresor.versiegeln(try Planungsdatei.schreiben(planung),
                                                  inhalt: .planung, ziel: .kopie)
                    try daten.write(to: ziel, options: [.atomic])
                } catch {
                    throw Kopiehindernis.schreiben(ordner: ordner, fehler: error)
                }
                Einstellungen.entfernen(Einstellungen.Schluessel.autoexportFehler)
                letzteKopie = Date()
                Einstellungen.setzen(letzteKopie?.timeIntervalSinceReferenceDate ?? 0,
                                     Einstellungen.Schluessel.autoexportStand)
                return (ziel, daten.count)
            }
        } catch let hindernis as Kopiehindernis {
            throw hindernis
        } catch let lage as Zielordnerlage {
            throw .zielordner(lage)
        } catch {
            throw .zielordner(.fehlt)
        }
    }

    /// Für den nächsten Start vormerken, was beim Beenden niemand mehr sieht.
    func kopiefehlerVormerken(_ text: String) {
        Einstellungen.setzen("Beim letzten Beenden: " + text, Einstellungen.Schluessel.autoexportFehler)
    }

    /// Beim Start: der Zeitpunkt der letzten Kopie — und die vorgemerkte
    /// Warnung, die damit verbraucht ist. Ein Prüflauf liest sie nicht (Schranke).
    func kopielageBeimStart() -> String? {
        let stand: Double = Einstellungen.wert(Einstellungen.Schluessel.autoexportStand) ?? 0
        if stand > 0 { letzteKopie = Date(timeIntervalSinceReferenceDate: stand) }
        guard let fehler: String = Einstellungen.wert(Einstellungen.Schluessel.autoexportFehler),
              !fehler.isEmpty else { return nil }
        Einstellungen.entfernen(Einstellungen.Schluessel.autoexportFehler)
        return fehler
    }

    /// Eine Statusdatei, die nicht eingelesen oder nicht neu versiegelt wird.
    enum Statusdateilage: Error, Equatable {
        /// Unverhältnismäßig groß — Größe in Byte.
        case zuGross(Int)
        /// Der Zielordner ist gerade nicht zu erreichen.
        case zielordner(Zielordnerlage)
        /// Unter einem Schlüssel, den weder die Sitzung noch der Übergang kennt.
        case fremderSchluessel
        /// Ein Behälter mit anderem Inhalt, oder kein Status.
        case keinStatus(String)
        case schreiben(String)

        var text: String {
            switch self {
            case .zuGross(let groesse): "ungewöhnlich groß (\(groesse / 1024 / 1024) MB)"
            case .zielordner(.keinZugriff): "Zielordner noch nicht freigegeben"
            case .zielordner(.fehlt): "Zielordner nicht erreichbar"
            case .fremderSchluessel: "unter einem anderen Schlüssel versiegelt"
            case .keinStatus(let grund): grund
            case .schreiben(let grund): grund
            }
        }
    }

    /// Die Statusdatei der Ansicht im Zielordner unter Schlüssel und Hülle der
    /// Sitzung bringen — Klartext oder Behälter unter `alter` oder unter einer
    /// älteren Hülle → Behälter unter `neu`, Inhalt unverändert. Nur im
    /// Übergang des Schutzes, unmittelbar nach dem Übernehmen: Danach zählt bei
    /// versiegelter Ablage nur noch ein Behälter. `false`: nichts zu tun. Nur
    /// ein lesbarer Status wird neu versiegelt; was nicht gilt, bleibt liegen
    /// und wird benannt.
    func statusdateiNeuVersiegeln(alter: Tresor?, neu: Tresor) throws(Statusdateilage) -> Bool {
        do {
            return try imZielordner { ordner in
                let datei = ordner.appending(component: Statusdatei.name, directoryHint: .notDirectory)
                guard let roh = try Sicherungsdienst.statusRoh(datei) else { return false }
                let klartext: Data
                if Tresor.istBehaelter(roh) {
                    let kopf: Behaelterkopf
                    do { kopf = try Tresor.kopfLesen(roh) } catch { throw Statusdateilage.keinStatus(error.localizedDescription) }
                    guard kopf.inhalt == Tresor.Inhalt.status.rawValue else {
                        throw Statusdateilage.keinStatus("Behälter mit Inhalt „\(kopf.inhalt)“")
                    }
                    // Derselbe Schlüssel mit derselben Hülle: nichts zu tun. Nur eine
                    // andere Hülle (Passphrase geändert) verlangt das Neuschreiben.
                    if neu.huelleGleich(kopf, ziel: .kopie) { return false }
                    let oeffner: Tresor
                    if neu.passt(zu: kopf) { oeffner = neu }
                    else if let alter, alter.passt(zu: kopf) { oeffner = alter }
                    else { throw Statusdateilage.fremderSchluessel }
                    do { klartext = try oeffner.oeffnen(kopf: kopf) } catch { throw Statusdateilage.keinStatus(error.localizedDescription) }
                } else {
                    klartext = roh
                }
                do { _ = try Statusdatei.lesen(klartext) } catch { throw Statusdateilage.keinStatus(error.localizedDescription) }
                do {
                    try neu.versiegeln(klartext, inhalt: .status, ziel: .kopie).write(to: datei, options: [.atomic])
                } catch {
                    throw Statusdateilage.schreiben(error.localizedDescription)
                }
                return true
            }
        } catch let lage as Statusdateilage {
            throw lage
        } catch let lage as Zielordnerlage {
            throw .zielordner(lage)
        } catch {
            throw .zielordner(.fehlt)
        }
    }

    /// Die Statusdatei roh, gebunden gelesen — `nil`, wenn keine liegt oder
    /// sie leer ist. Ein Ordner, eine Pipe, eine gescheiterte Messung: ein
    /// Fehler, keine Null — sonst ginge etwas ungeprüft ganz in den Speicher.
    /// Über der Grenze: benannt.
    private static func statusRoh(_ datei: URL) throws(Statusdateilage) -> Data? {
        switch Ablage.gebundenLesen(datei, hoechstens: Statusdatei.hoechstgroesse) {
        case .keine: return nil
        case .zuGross(let groesse): throw .zuGross(groesse)
        case .unlesbar(let fehler): throw .schreiben(fehler.localizedDescription)
        case .daten(let roh): return roh.isEmpty ? nil : roh
        }
    }

    /// Die Statusdatei der iPad-Ansicht aus dem Zielordner — `nil`, wenn keine
    /// liegt oder der Ordner gerade nicht erreichbar ist (das meldet sich beim
    /// Schreiben der Kopie). Gelesen im Sicherheitsbereich des Zielordners.
    func statusdateiLesen() throws(Statusdateilage) -> Data? {
        do {
            return try imZielordner { ordner in
                let datei = ordner.appending(component: Statusdatei.name, directoryHint: .notDirectory)
                return try Sicherungsdienst.statusRoh(datei)
            }
        } catch let lage as Statusdateilage {
            throw lage
        } catch {
            return nil
        }
    }
}
