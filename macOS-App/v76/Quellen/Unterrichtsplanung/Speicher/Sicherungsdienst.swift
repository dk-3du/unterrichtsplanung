// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
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
        /// Nicht geschrieben: Ein übergebener Übergang ist noch nicht
        /// eingesetzt, und auch dieser Anlass konnte es nicht nachholen (E54).
        case uebergangOffen(String)
        /// Nicht geschrieben: Auf der Platte liegt ein anderer Schutz, als die
        /// Sitzung mitbringt — der Formwächter hat abgewiesen (E72).
        case form(String)
        /// Nicht geschrieben: Was auf der Platte liegt, war nicht einzusehen —
        /// der Wächter sperrt, statt zu raten (E76).
        case formUnklar(String)
        /// Nicht geschrieben: Dort liegt ein Behälter, den der Leser abweist —
        /// eine neuere Fassung, ein beschädigter Rumpf (N57-01).
        case formUnbrauchbar(String)
    }

    private let ablage: Ablage
    /// Die Lesegrenze von App und Ansicht — was darüber liegt, wird nicht
    /// geschrieben, sonst legte der nächste Start die eigene Ablage beiseite.
    private let grenze: Int
    private let sperre = NSLock()
    private var vergeben = 0
    private var letzteNummer = 0
    /// Abdruck der Byte, die zuletzt auf die Platte gingen — Klartext, wie ihn
    /// der Aufrufer hereinreicht, nicht der Behälter (der trägt bei jedem
    /// Versiegeln einen neuen Nonce und sähe darum immer anders aus).
    ///
    /// **Warum nicht der Zeitstempel (N56-02):** Er sagt, *wann* zuletzt
    /// geändert wurde, nicht *was*. Zwei Änderungen in derselben Millisekunde
    /// tragen denselben; wer daran „liegt schon“ festmacht, verwirft die
    /// zweite stillschweigend — und verbucht sie zugleich als geschrieben.
    private var letzterAbdruck: Data?

    /// SHA-256 über den Klartext; gemessen 0,31 ms bei 1 MB.
    static func abdruck(_ daten: Data) -> Data { Data(SHA256.hash(data: daten)) }

    /// Was der Ordner der Ablage gerade zulässt (E66).
    ///
    /// Die Lage liegt hier und nicht im Dienst, weil hier alle fragen: die
    /// Sicherungsfolge selbst, die Ablage mit jeder Änderung, Sitzplandienst
    /// und Ordnerzugriff. Eine Blockade des Wiederanlaufs erreicht damit jeden
    /// Schreiber, nicht nur den Hauptweg (N53-01).
    private enum Zustand {
        /// Der Wiederanlauf ist noch nicht gelaufen — der Anfangswert. Frei
        /// wird der Ordner erst, wenn er es belegt; liegt eine Spur eines
        /// Übergangs, bleibt es dabei.
        case ungeprueft
        /// Der Wiederanlauf hat den Ordner freigegeben.
        case bereit
        /// Ein übergebener Übergang wartet auf sein Einsetzen: Marke, Ordner
        /// und der Stand, den seine Generation trägt. Jeder Anlass holt ihn
        /// zuerst nach (E54).
        case einsetzenOffen(marke: Uebergangsmarke, ordner: URL, abdruck: Data)
        /// Der Wiederanlauf konnte keinen stimmigen Stand feststellen: Es wird
        /// nichts geändert, bis der Nutzer den Weg räumt (E67).
        case blockiert(String)
    }
    private var zustand: Zustand = .ungeprueft

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
        sperre.withLock { letzterAbdruck = nil }
    }

    /// Der Übergang des Schutzes setzt seine Generation ein — unter derselben
    /// Sperre wie jedes Schreiben, damit kein abgetrennter Auftrag mit dem
    /// alten Schutz dazwischen oder danach schreibt: Seine Nummer ist danach
    /// überholt. `stand` trägt die Generation; bleibt das Einsetzen
    /// unvollendet, bleibt der Übergang offen — kein Schreiben geht an ihm
    /// vorbei, jeder Anlass holt ihn zuerst nach (E54).
    func uebergeben(nummer: Int, abdruck: Data, marke: Uebergangsmarke, ordner: URL,
                    _ einsetzen: () -> Uebergangsdienst.Einsetzbefund) -> Uebergangsdienst.Einsetzbefund {
        sperre.withLock {
            let befund = einsetzen()
            letzteNummer = max(letzteNummer, nummer)
            if befund == .vollendet {
                letzterAbdruck = abdruck
                zustand = .bereit
            } else {
                letzterAbdruck = nil
                zustand = .einsetzenOffen(marke: marke, ordner: ordner, abdruck: abdruck)
            }
            return befund
        }
    }

    /// Ein übergebener Übergang wartet noch auf sein Einsetzen.
    var uebergangOffen: Bool {
        sperre.withLock { if case .einsetzenOffen = zustand { true } else { false } }
    }

    /// Warum gerade nichts geändert werden darf — `nil`, wenn der Ordner frei
    /// ist. Blockiert ist blockiert; ein offenes Einsetzen wird nachgeholt.
    var blockade: String? {
        sperre.withLock { if case .blockiert(let grund) = zustand { grund } else { nil } }
    }

    /// Der Wiederanlauf hat den Ordner geprüft und gibt ihn frei — oder der
    /// Nutzer hat die Blockade ausdrücklich geräumt (E67).
    func freigeben() { sperre.withLock { zustand = .bereit } }

    /// Der Wiederanlauf konnte keinen stimmigen Stand feststellen.
    func blockieren(_ grund: String) { sperre.withLock { zustand = .blockiert(grund) } }

    /// Vor jeder Änderung gefragt: Liefert den Grund, wenn nicht geschrieben
    /// werden darf; sonst `nil`. Ein offenes Einsetzen wird dabei nachgeholt.
    func nachholen() -> String? { sperre.withLock { nachholenGesperrt() } }

    /// Unter der Sperre — für `nachholen()` und `schreiben(...)`.
    private func nachholenGesperrt() -> String? {
        switch zustand {
        case .bereit:
            return nil
        case .blockiert(let grund):
            return grund
        case .ungeprueft:
            // Ohne gelaufenen Wiederanlauf gilt der Ordner nur dann als frei,
            // wenn keine Spur eines Übergangs liegt. Eingesetzt wird hier
            // nichts — das ist Sache des Starts (E66).
            if let spur = Uebergangsdienst.spur(in: ablage.ordner) {
                zustand = .blockiert(spur)
                return spur
            }
            zustand = .bereit
            return nil
        case .einsetzenOffen(let marke, let ordner, let abdruck):
            switch Uebergangsdienst.einsetzenErneut(marke, in: ordner) {
            case .vollendet:
                zustand = .bereit
                letzterAbdruck = abdruck
                return nil
            case .unvollendet(let grund):
                return grund
            }
        }
    }

    /// `daten` ist Klartext; versiegelt wird in der Ablage, unter `tresor`.
    /// Ob sie schon dort liegen, sagt ihr Abdruck — nicht ein Zeitstempel,
    /// den zwei Änderungen in derselben Millisekunde teilen (N56-02).
    /// Ein offener Übergang wird zuerst nachgeholt; bleibt er offen, wird
    /// nicht geschrieben (E54).
    func schreiben(nummer: Int, daten: Data, tresor: Tresor?) throws -> Ergebnis {
        try sperre.withLock {
            guard nummer > letzteNummer else { return .ueberholt }
            letzteNummer = nummer
            if let grund = nachholenGesperrt() { return .uebergangOffen(grund) }  // auch: blockiert
            let abdruck = Sicherungsfolge.abdruck(daten)
            guard abdruck != letzterAbdruck else { return .unveraendert }
            let groesse: Int
            do { groesse = try ablage.schreiben(daten, tresor: tresor, hoechstens: grenze) }
            catch let fehler as Ablage.Schreibfehler { return .zuGross(fehler.groesse) }
            catch let sperre as Ablage.Formsperre {
                return switch sperre.anlass {
                case .ungewiss: .formUnklar(sperre.grund)
                case .unbrauchbar: .formUnbrauchbar(sperre.grund)
                case .fremderSchutz: .form(sperre.grund)
                }
            }
            letzterAbdruck = abdruck
            return .geschrieben(groesse)
        }
    }
}

/// Die Naht zwischen dem Schreiben und dem Melden — für Prüfläufe (E92).
///
/// Im Betrieb steht hier nichts, und `passieren` kehrt sofort zurück. Ein
/// Prüflauf stellt sie für die Dauer eines Aufrufs und hält damit die
/// Veröffentlichung einer Rückmeldung an: Nur so lässt sich die Reihenfolge
/// herstellen, die im Betrieb der Zufall herstellt — A schreibt, B scheitert,
/// A meldet (N57-02). **Sie ändert keine Regel**, sie verzögert nur, was
/// ohnehin verzögert ankommen kann; und außerhalb des Prüfziels wirkt sie
/// nicht, wie die `Pruefuhr` (E81), von der sie auch die Lehre übernimmt:
/// aufgabenweit, denn Prüfläufe laufen nebeneinander.
enum Sicherungsnaht {
    @TaskLocal static var halten: (@Sendable @MainActor (Int) async -> Void)?

    /// Wie `Pruefuhr.angehalten`: `isolation` hält die Funktion beim Akteur
    /// des Aufrufers; an `withValue` geht sie nicht mehr — die Überladung ohne
    /// `isolation:` läuft seit Swift 6.4 ohnehin dort (`nonisolated(nonsending)`).
    static func gestellt<T>(_ halten: @escaping @Sendable @MainActor (Int) async -> Void,
                            isolation: isolated (any Actor)? = #isolation,
                            _ waehrenddessen: () async throws -> T) async rethrows -> T {
        try await $halten.withValue(halten) { try await waehrenddessen() }
    }

    @MainActor
    static func passieren(_ nummer: Int) async {
        guard Pruefziel.ja, let halten else { return }
        await halten(nummer)
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
    /// Der Übergabestand der Schutzübergänge — an derselben Ablage (E47).
    let uebergang: Uebergangsdienst

    private let folge: Sicherungsfolge
    @ObservationIgnored private var auftrag: Task<Void, Never>?

    /// Warum gerade nichts auf die Platte kommt.
    enum Stoerung: Equatable {
        /// Das Schreiben selbst schlug fehl.
        case schreiben
        /// Die Planung läge mit so vielen Byte über der Lesegrenze — nicht
        /// geschrieben, der letzte gute Stand bleibt liegen.
        case zuGross(Int)
        /// Ein übergebener Übergang ist noch nicht eingesetzt (E54): Nichts
        /// schreibt an ihm vorbei; jeder Anlass holt ihn zuerst nach.
        case uebergangOffen(String)
        /// Die Platte trägt einen anderen Schutz als die Sitzung (E72).
        case form(String)
        /// Was auf der Platte liegt, war nicht einzusehen (E76).
        case formUnklar(String)
        /// Dort liegt ein Behälter, den diese App nicht lesen kann (N57-01).
        case formUnbrauchbar(String)

        var text: String {
            switch self {
            case .schreiben:
                "Die Autosicherung schlägt fehl. Bitte über „Export“ als Datei sichern."
            case .zuGross(let groesse):
                "Die Planung ist mit \(groesse / 1024 / 1024) MB über der Schreibgrenze "
                    + "(\(Sicherungsdienst.schreibgrenze / 1024 / 1024) MB — zugleich die Lesegrenze von App "
                    + "und Web App). Die Autosicherung schreibt sie nicht — auf der Platte bleibt der "
                    + "zuletzt gesicherte Stand. Bitte Beschreibungen und Kommentare kürzen oder Vorhaben "
                    + "entfernen; danach sichert die App wieder von selbst."
            case .uebergangOffen(let grund):
                "Ein Übergang des Schutzes ist übergeben, aber noch nicht eingesetzt (\(grund)). Die "
                    + "Autosicherung ruht, bis er eingesetzt ist — jeder Schreibanlass versucht es erneut, der "
                    + "nächste Start vollendet ihn. Falls es eilt: über „Export“ als Datei sichern."
            case .form(let grund):
                "Auf der Platte liegt ein anderer Schutz, als diese Sitzung mitbringt: \(grund). Die "
                    + "Autosicherung ruht — überschrieben wird nichts. Bitte die App neu starten und die "
                    + "Planung entsperren; falls es eilt: über „Export“ als Datei sichern."
            case .formUnklar(let grund):
                "Es ließ sich nicht feststellen, was auf der Platte liegt: \(grund). Die Autosicherung "
                    + "ruht — solange offen ist, ob dort Schutz liegt, wird nichts überschrieben. Bitte "
                    + "im Ablageordner nachsehen („Ordner der Autosicherung zeigen“) und die Datei lesbar "
                    + "machen oder beiseitelegen; falls es eilt: über „Export“ als Datei sichern."
            case .formUnbrauchbar(let grund):
                "Auf der Platte liegt ein verschlüsselter Stand, den diese App nicht lesen kann: "
                    + "\(grund) Die Autosicherung ruht — überschrieben wird nichts. Stammt die Datei "
                    + "aus einer neueren Fassung, hilft ein Update dieser App; sonst bitte im "
                    + "Ablageordner nachsehen („Ordner der Autosicherung zeigen“) und die Datei "
                    + "beiseitelegen; falls es eilt: über „Export“ als Datei sichern."
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
            case .uebergangOffen(let grund):
                "der vorige Übergang ist noch nicht eingesetzt (\(grund))"
            case .form(let grund):
                "die Platte trägt einen anderen Schutz als die Sitzung (\(grund))"
            case .formUnklar(let grund):
                "was auf der Platte liegt, war nicht einzusehen (\(grund))"
            case .formUnbrauchbar(let grund):
                "die Platte trägt einen Behälter, den diese App nicht lesen kann (\(grund))"
            }
        }
    }

    /// Zeitstempel des zuletzt geschriebenen Standes — **Auskunft, kein
    /// Kennzeichen**: Woran erkannt wird, ob die Platte den Stand der Sitzung
    /// trägt, ist der Zähler darunter (N56-02).
    private(set) var gesicherterStand: String?

    /// Jede angemeldete Änderung zählt eins weiter; `gesicherteFassung` sagt,
    /// welche davon auf der Platte liegt (`nil`: unbekannt — dann wird beim
    /// nächsten Anlass geschrieben). Zwei Zahlen, die nur hier entstehen,
    /// statt einer Zeichenkette, die aus der Uhr kommt.
    private(set) var fassung = 0
    private(set) var gesicherteFassung: Int?

    /// Die Sitzung hat Änderungen, die die Platte noch nicht trägt.
    var ungesichert: Bool { gesicherteFassung != fassung }

    /// Übersprungen wird nur, wenn **beides** dafür spricht: Es ist nichts
    /// angemeldet, und der Stempel der Sitzung liegt schon auf der Platte.
    ///
    /// Keiner der beiden allein ist eine Zusicherung. Der Zähler sieht keine
    /// Planung, die von außen eingesetzt wurde (Import, Rettung, Statusstand);
    /// der Stempel sieht zwei Änderungen in derselben Millisekunde nicht
    /// (N56-02). Zusammen können sie nur zu *viel* Arbeit veranlassen, nie zu
    /// wenig — und was wirklich auf der Platte liegt, entscheidet unten der
    /// Abdruck der Byte.
    private func nichtsZuTun(_ planung: Planung) -> Bool {
        !ungesichert && planung.geaendert == gesicherterStand
    }
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
        uebergang = Uebergangsdienst(ordner: ablage.ordner)
        // Über die Schranke: Ein Prüflauf erbt die Kopie nicht — sonst schriebe
        // er in den echten Ordner.
        kopieAktiv = Einstellungen.wert(Einstellungen.Schluessel.autoexportAktiv) ?? false
        // Die Dienste schreiben nicht über die Sicherungsfolge — die Sperre
        // eines offenen Übergangs gilt auch für sie (E54).
        sitzplaene.schreibsperre = { [unowned self] in self.uebergangNachholen() }
        zugriff.schreibsperre = { [unowned self] in self.uebergangNachholen() }
        // Die Ablage fragt an jeder Stelle, die etwas ändert — auch abseits des
        // Hauptstrangs; sie hängt deshalb an der Sicherungsfolge, nicht am
        // Dienst (E62, B25). Nicht gefragt wird in `Ablage.schreiben`: Dort
        // hält die Folge schon ihre Sperre.
        //
        // Eine Vorschau bekommt `Ablage.shared` der Sitzung hereingereicht und
        // setzt kein Tor: Ihre Folge kennt keinen offenen Übergang, und ein
        // Druckfenster, das nach einem unvollendeten Einsetzen aufgeht, würde
        // sonst das Tor der Sitzung durch ein offenes ersetzen (R1). Sie
        // schreibt ohnehin nicht.
        if !vorschau {
            let sicherungsfolge = folge
            ablage.schreibsperre = { sicherungsfolge.nachholen() }
        }
    }

    // ── Die laufende Sicherung ────────────────────────────────────────────

    /// Nach jeder Änderung; schreibt entprellt.
    func sichern() {
        fassung += 1
        auftrag?.cancel()
        auftrag = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.imHintergrundSichern()
        }
    }

    /// Den entprellten Weg **jetzt** gehen — für Prüfungen (E145, v66): dieselbe
    /// Hintergrundarbeit wie nach den 700 ms, nur ohne die Uhr; ein wartender
    /// Auftrag wird dabei aufgehoben, damit er nicht ein zweites Mal schreibt.
    /// Im Betrieb ruft das niemand; `jetztSichern()` ist der gleichlaufende
    /// Weg mit eigener Reihenfolge, nicht dieser.
    func entprelltJetzt() async {
        auftrag?.cancel()
        auftrag = nil
        await imHintergrundSichern()
    }

    /// Umwandeln und Schreiben laufen abseits des Hauptstrangs (4,9 ms bei 400
    /// Vorhaben). Beim Beenden bleibt es bei `jetztSichern()`.
    private func imHintergrundSichern() async {
        let sitzung = sitzungsquelle()
        guard let planung = sitzung.planung, !gesperrt, !nichtsZuTun(planung) else { return }
        let stand = planung.geaendert
        let fassung = self.fassung
        // Die Nummer wird vor dem `await` gezogen: Schreibt `jetztSichern()`
        // währenddessen einen jüngeren Stand, verwirft die Sicherungsfolge
        // diesen hier, statt ihn darüberzulegen.
        let nummer = folge.naechsteNummer()
        let folge = self.folge
        let ergebnis = await Task.detached(priority: .utility) { () -> Sicherungsfolge.Ergebnis? in
            // Die Serialisierungsgrenze liefert Klartext und Schlüssel — die
            // Ablage versiegelt.
            guard let (klartext, tresor) = try? sitzung.planungsdatenZumSpeichern() else { return nil }
            return try? folge.schreiben(nummer: nummer, daten: klartext, tresor: tresor)
        }.value
        // Hier stellt im Betrieb der Zufall die Reihenfolge; im Prüflauf stellt
        // sie die Naht (E92). Im Betrieb steht hier nicht einmal ein `await`:
        // Die Schranke ist eine Konstante, der Zweig fällt weg.
        if Pruefziel.ja { await Sicherungsnaht.passieren(nummer) }
        guard let ergebnis else {
            if rueckmeldungGilt(nummer) { lageMelden(.schreiben) }
            return
        }
        uebernehmen(ergebnis, stand: stand, fassung: fassung, nummer: nummer)
    }

    /// Was die Sicherungsfolge zurückgab, in die Merker — und in die Lage.
    ///
    /// **Nur, wenn es noch gilt (N57-02, E91):** Geschrieben wird geordnet, die
    /// Sicherungsfolge nimmt unter ihrer Sperre nur wachsende Nummern. Fertig
    /// werden die Aufträge in beliebiger Reihenfolge — und wer zuletzt
    /// zurückkam, setzte bisher die Merker. Ein alter Erfolg löschte damit
    /// einen jungen Fehlschlag, ein alter Fehlschlag meldete eine überholte
    /// Störung.
    private func uebernehmen(_ ergebnis: Sicherungsfolge.Ergebnis, stand: String, fassung: Int,
                             nummer: Int) {
        guard rueckmeldungGilt(nummer) else { return }
        switch ergebnis {
        case .geschrieben(let groesse):
            gesicherterStand = stand
            gesicherteFassung = fassung
            letzteSicherung = Date()
            ablagegroesse = groesse
            vorgaengerAblesen()
        case .unveraendert:
            // Byte für Byte liegt das schon dort — ein gleichlaufender Weg war
            // schneller, oder die Änderung war keine. Offen war nur der Merker.
            gesicherterStand = stand
            gesicherteFassung = fassung
        case .ueberholt:
            // Auf der Platte liegt ein jüngerer Stand — nichts zu melden.
            return
        case .zuGross(let groesse):
            ablagegroesse = groesse
            lageMelden(.zuGross(groesse))
            return
        case .uebergangOffen(let grund):
            lageMelden(.uebergangOffen(grund))
            return
        case .form(let grund):
            lageMelden(.form(grund))
            return
        case .formUnklar(let grund):
            lageMelden(.formUnklar(grund))
            return
        case .formUnbrauchbar(let grund):
            lageMelden(.formUnbrauchbar(grund))
            return
        }
        // Hat dieser Anlass ein offenes Einsetzen nachgeholt, ist die
        // Generation nicht mehr in Arbeit.
        uebergangAbgeschlossenFallsNachgeholt()
        lageMelden(nil)
    }

    /// Ein Schreibanlass hat das offene Einsetzen nachgeholt: keine Generation
    /// mehr in Arbeit, die Störung ist vorbei.
    private func uebergangAbgeschlossenFallsNachgeholt() {
        guard uebergang.istUebergeben, !folge.uebergangOffen else { return }
        uebergang.abgeschlossen()
    }

    /// Das offene Einsetzen nachholen — für die Schreibanlässe der Dienste
    /// (Sitzpläne, Lesezeichen), die nicht über die Sicherungsfolge gehen
    /// (E54). Liefert den Grund, wenn es weiter offen bleibt; sonst ist die
    /// Störung vorbei, und der nächste Anlass der Sicherung schreibt.
    func uebergangNachholen() -> String? {
        let warOffen = folge.uebergangOffen
        if let grund = folge.nachholen() { return grund }
        guard warOffen else { return nil }
        uebergangAbgeschlossenFallsNachgeholt()
        if case .uebergangOffen = stoerung { lageMelden(nil) }
        return nil
    }

    // ── Die Lage der Ablage (E66, E67) ────────────────────────────────────

    /// Der Wiederanlauf hat den Ordner geprüft und gibt ihn frei.
    func wiederanlaufFreigeben() { folge.freigeben() }

    /// Der Wiederanlauf konnte keinen stimmigen Stand feststellen: Ab hier
    /// ändert kein Weg mehr etwas im Ordner — auch nicht Sitzpläne,
    /// Lesezeichen, Rettungskopien oder das Nachziehen der Nebendateien.
    func wiederanlaufBlockieren(_ grund: String) {
        folge.blockieren(grund)
        gesperrt = true
    }

    /// Warum der Ordner blockiert ist — `nil`, wenn er frei ist.
    var wiederanlaufBlockade: String? { folge.blockade }

    /// Was an Spuren eines Übergangs im Ordner liegt — für die Rückfrage vor
    /// dem Räumen. Leer, wenn nichts liegt oder der Ordner nicht lesbar ist.
    var blockadespuren: [String] { (try? Uebergangsdienst.spuren(in: ablage.ordner)) ?? [] }

    /// Die Blockade räumen (E67): Marke, Zwillinge und Vorgänger gehen
    /// gestempelt ins Register, gelöscht wird nichts. Erst wenn das
    /// vollständig gelang, ist der Ordner wieder frei.
    enum Raeumbefund: Equatable {
        /// Alles liegt gestempelt im Register — mit diesen Namen.
        case geraeumt([String])
        /// Ein Stück blieb im Weg: Der Ordner bleibt blockiert.
        case gescheitert(String)
    }

    func blockadeRaeumen() -> Raeumbefund {
        guard wiederanlaufBlockade != nil else { return .gescheitert("der Ordner ist nicht blockiert") }
        do {
            let gerettet = try Uebergangsdienst.blockadeRaeumen(in: ablage.ordner,
                                                                stempel: Zeitrechnung.dateistempel())
            // Freigegeben wird hier nichts: Das tut allein der Wiederanlauf, der
            // den geräumten Ordner danach noch einmal ansieht (N54-01, E71).
            // Bleibt er aus, bleibt die Ablage gesperrt — wie es sich gehört.
            gesperrt = false
            stoerung = nil
            uebergang.abgeschlossen()
            return .geraeumt(gerettet)
        } catch {
            return .gescheitert(error.localizedDescription)
        }
    }

    /// Ohne Entprellung — beim Wegschalten und beim Beenden, durchgängig
    /// gleichlaufend.
    func jetztSichern() {
        let sitzung = sitzungsquelle()
        auftrag?.cancel()
        auftrag = nil
        guard let planung = sitzung.planung, !gesperrt else { return }
        // Sonst verdrängte jedes Wegschalten die Vorgängerfassung durch eine Kopie.
        guard !nichtsZuTun(planung) else { return }
        let fassung = self.fassung
        // Wartet, falls ein abgetrennter Auftrag gerade schreibt (Millisekunden);
        // genau daraus entsteht die Reihenfolge zwischen beiden Wegen.
        let nummer = folge.naechsteNummer()
        do {
            let (klartext, tresor) = try sitzung.planungsdatenZumSpeichern()
            uebernehmen(try folge.schreiben(nummer: nummer, daten: klartext, tresor: tresor),
                        stand: planung.geaendert, fassung: fassung, nummer: nummer)
        } catch {
            if rueckmeldungGilt(nummer) { lageMelden(.schreiben) }
        }
    }

    // ── Die Reihenfolge der Rückmeldungen (N57-02, E91) ───────────────────

    /// Die Nummer der zuletzt veröffentlichten Rückmeldung. Was älter ist, sagt
    /// nichts mehr über den Stand: Auf der Platte liegt längst etwas anderes.
    private var letzteRueckmeldung = 0

    /// Gilt diese Rückmeldung noch? Fragt und merkt zugleich — wie die Schranke
    /// der Sicherungsfolge eine Ebene tiefer.
    func rueckmeldungGilt(_ nummer: Int) -> Bool {
        guard nummer > letzteRueckmeldung else { return false }
        letzteRueckmeldung = nummer
        return true
    }

    /// Was hier gilt, ist neuer als alles, was gerade unterwegs ist: Laden,
    /// Rettungswege und ein vollendeter Übergang setzen den Stand selbst, ohne
    /// die Sicherungsfolge zu fragen. Eine Rückmeldung von vorher darf sie
    /// danach nicht überschreiben — darum zieht diese Stelle eine frische
    /// Nummer und lässt alle älteren verfallen.
    private func rueckmeldungenUeberholen() {
        letzteRueckmeldung = folge.naechsteNummer()
    }

    /// Warum die Generation eines Übergangs nicht entsteht.
    enum Schreibhindernis: Error, Equatable {
        /// Eine Vorschau schreibt nicht.
        case vorschau
        /// Keine Planung in der Sitzung — leer oder gesperrt.
        case nichtsZuSchreiben
        /// Ein unlesbarer Stand liegt noch im Weg.
        case gesperrt
        case schreiben(String)
    }

    /// Die Generation der Ablage für einen Übergang des Schutzes (E47):
    /// `planung.json` aus der Sitzung unter `neu`, die Vorgängerfassung und
    /// das Register unter `neu` (Klartext bei `nil`) — nichts wird
    /// geschrieben. Dazu die Nummer in der Sicherungsfolge, die das Einsetzen
    /// später trägt, und der Stand, den die Generation trägt. Eine Vorschau,
    /// eine Sitzung ohne Planung und ein gesperrter Stand werfen.
    func generationErzeugen(neu: Tresor?, alter: Tresor?) throws(Schreibhindernis)
        -> (dateien: [String: Data], bilanz: Ablage.Nebendateienbilanz, nummer: Int, stand: String,
            abdruck: Data) {
        // Ein entprellter Auftrag bleibt stehen: Feuert er nach dem Einsetzen,
        // findet er den Stand der Generation schon auf der Platte (unverändert);
        // ein älterer ist in der Sicherungsfolge überholt.
        let sitzung = sitzungsquelle()
        guard !istVorschau else { throw .vorschau }
        guard !gesperrt else { throw .gesperrt }
        guard let planung = sitzung.planung else { throw .nichtsZuSchreiben }
        let nummer = folge.naechsteNummer()
        var dateien: [String: Data]
        let bilanz: Ablage.Nebendateienbilanz
        let abdruck: Data
        do {
            let (klartext, _) = try sitzung.planungsdatenZumSpeichern()
            abdruck = Sicherungsfolge.abdruck(klartext)
            (dateien, bilanz) = ablage.generationErzeugen(neu: neu, alter: alter, hoechstens: Sicherungsdienst.lesedecke)
            dateien[ablage.datei.lastPathComponent] = try ablage.planungErzeugen(
                klartext, tresor: neu, hoechstens: Sicherungsdienst.schreibgrenze)
        } catch let fehler as Ablage.Schreibfehler {
            ablagegroesse = fehler.groesse
            lageMelden(.zuGross(fehler.groesse))
            throw .schreiben(Stoerung.zuGross(fehler.groesse).kurz)
        } catch {
            throw .schreiben(Stoerung.schreiben.kurz + " (" + error.localizedDescription.ohneSchlusspunkt + ")")
        }
        return (dateien, bilanz, nummer, planung.geaendert, abdruck)
    }

    /// Nach der Marke: die Generation einsetzen — unter der Sperre der
    /// Sicherungsfolge, damit kein Auftrag mit dem alten Schutz dazwischenkommt.
    /// Vollendet trägt die Platte den Stand der Sitzung; sonst bleibt der
    /// Übergang offen: Nichts schreibt an ihm vorbei, jeder Anlass holt ihn
    /// nach, der nächste Start vollendet ihn (E54).
    func uebergangEinsetzen(nummer: Int, stand: String, abdruck: Data) -> Uebergangsdienst.Einsetzbefund {
        guard let marke = uebergang.laufend else { return .unvollendet("keine übergebene Generation") }
        let befund = folge.uebergeben(nummer: nummer, abdruck: abdruck, marke: marke,
                                      ordner: ablage.ordner) {
            uebergang.einsetzen()
        }
        switch befund {
        case .vollendet:
            rueckmeldungenUeberholen()
            gesicherterStand = stand
            gesicherteFassung = fassung
            (letzteSicherung, ablagegroesse) = ablage.stand()
            lageMelden(nil)
        case .unvollendet(let grund):
            standUnbekannt()
            // Still — die Meldung des Übergangs nennt es unter „Offen“; die
            // Werkzeugleiste zeigt die Störung, bis ein Anlass sie nachholt.
            stoerung = .uebergangOffen(grund)
        }
        return befund
    }

    /// Beim Start, vor dem Lesen der Ablage (E50): einen Übergang vollenden,
    /// der nicht zu Ende kam, oder verwerfen, was nie galt.
    func uebergangWiederanlaufen(stempel: String) -> Uebergangsdienst.Wiederanlaufbefund {
        guard !istVorschau else { return .nichts }
        return uebergang.wiederanlaufen(stempel: stempel)
    }

    /// Warum ein Übergang des Schutzes gar nicht erst beginnt: Die Planung liegt
    /// über der Schreibgrenze — jede neue Hülle bliebe in der Sitzung, die
    /// Platte behielte die alte —, der vorige Übergang ist noch nicht
    /// eingesetzt, oder die Platte trägt einen anderen Schutz als die Sitzung
    /// (E72). Das Blatt zeigt den Grund und sperrt die Knöpfe.
    var schreibsperrgrund: String? {
        guard !istVorschau else { return nil }
        switch stoerung {
        case .zuGross, .uebergangOffen, .form, .formUnklar, .formUnbrauchbar: return stoerung?.kurz
        case .schreiben, nil: return nil
        }
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

    /// Ein offener Übergang wird zuerst nachgeholt; bleibt er offen, wird keine
    /// Nebendatei angefasst, und der Grund steht in der Bilanz (E62). Die
    /// Ablage fragt noch einmal für sich — das hier hält zusätzlich die
    /// Werkzeugleiste im Bild.
    @discardableResult
    func altbestaendeVersiegeln(mit tresor: Tresor, nurAbweichende: Bool = false) -> Ablage.Nebendateienbilanz {
        if let grund = uebergangNachholen() {
            var bilanz = Ablage.Nebendateienbilanz()
            bilanz.uebrig.append(.init(name: ablage.ordner.lastPathComponent, grund: grund))
            return bilanz
        }
        return ablage.altbestaendeVersiegeln(mit: tresor, nurAbweichende: nurAbweichende,
                                             hoechstens: Sicherungsdienst.lesedecke)
    }

    /// Der nächste Schreibvorgang geht auch bei unverändertem Stand auf die
    /// Platte — die Hülle hat sich am Tresor geändert, ohne dass ein Übergang
    /// lief (Prüfungen).
    func neuSchreibenErzwingen() {
        standUnbekannt()
        folge.neuSchreibenErzwingen()
    }

    /// Was auf der Platte liegt, ist nicht mehr der Stand der Sitzung: Der
    /// nächste Anlass schreibt. Für die Rettungswege, die eine Planung von
    /// Hand einsetzen, und für einen Übergang, der unvollendet blieb.
    func standUnbekannt() {
        rueckmeldungenUeberholen()
        gesicherterStand = nil
        gesicherteFassung = nil
    }

    /// Nach dem Laden von der Platte: Dieser Stand liegt dort schon.
    func standUebernommen(_ geaendert: String) {
        rueckmeldungenUeberholen()
        gesicherterStand = geaendert
        gesicherteFassung = fassung
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
        case (nil, nil), (.schreiben, .schreiben), (.zuGross, .zuGross), (.uebergangOffen, .uebergangOffen): false
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
            guard Sicherungsdienst.istOrdner(gemerkt) else { throw Zielordnerlage.fehlt }
            return try arbeit(gemerkt)
        }
        do {
            return try zugriff.mit(gemerkt.path) { ordner in
                guard Sicherungsdienst.istOrdner(ordner) else { throw Zielordnerlage.fehlt }
                if ordner.path != kopieOrdner { kopieOrdner = ordner.path }
                return try arbeit(ordner)
            }
        } catch let fehler as Ordnerzugriff.Fehler {
            throw fehler.art == .unaufloesbar ? Zielordnerlage.fehlt : Zielordnerlage.keinZugriff
        }
    }

    nonisolated private static func istOrdner(_ ziel: URL) -> Bool {
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
        guard Sicherungsdienst.istOrdner(ordner) else { return }
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
    nonisolated private static func statusRoh(_ datei: URL) throws(Statusdateilage) -> Data? {
        switch Ablage.gebundenLesen(datei, hoechstens: Statusdatei.hoechstgroesse) {
        case .keine: return nil
        case .zuGross(let groesse): throw .zuGross(groesse)
        case .unlesbar(let fehler): throw .schreiben(fehler.localizedDescription)
        case .daten(let roh): return roh.isEmpty ? nil : roh
        }
    }

    /// Die Statusdatei der Web App aus dem Zielordner — `nil`, wenn keine
    /// liegt. Ist der Ordner gerade nicht erreichbar, heißt das `.zielordner`,
    /// nicht „keine Datei“: Der Befehl „Stand der Web App abrufen“ nennt ihn,
    /// beim Start und nach dem Aufwachen bleibt es still — das Schreiben der
    /// Kopie meldet ihn (B61, v75). Gelesen im Sicherheitsbereich des Zielordners,
    /// gleichlaufend: Zugang, Lesen, Nachführen hintereinander.
    func statusdateiLesen() throws(Statusdateilage) -> Data? {
        let zugang = try statuszugang()
        do {
            let daten = try Sicherungsdienst.statusdateiLesen(zugang)
            nachfuehren(zugang)
            return daten
        } catch {
            if case .zielordner = error {} else { nachfuehren(zugang) }
            throw error
        }
    }

    /// Der Zugang zur Statusdatei, aufgelöst auf dem Hauptstrang — ohne eine
    /// Datei zu berühren (R75-01, v76). Gelesen wird mit
    /// `statusdateiLesen(_:)`, gleich oder abseits des Hauptstrangs.
    struct Statuszugang: Sendable {
        /// Der Bereich des Lesezeichens; ohne ihn (nur ohne Sandbox) der Pfad allein.
        let bereich: Ordnerzugriff.Bereich?
        let ordner: URL
    }

    func statuszugang() throws(Statusdateilage) -> Statuszugang {
        let gemerkt = URL(fileURLWithPath: kopieOrdner, isDirectory: true)
        guard zugriff.zustaendig(fuer: gemerkt.path) != nil else {
            guard !Ordnerzugriff.imSandbox else { throw .zielordner(.keinZugriff) }
            return Statuszugang(bereich: nil, ordner: gemerkt)
        }
        do {
            let bereich = try zugriff.bereich(gemerkt.path)
            return Statuszugang(bereich: bereich, ordner: bereich.ordner)
        } catch let fehler as Ordnerzugriff.Fehler {
            throw .zielordner(fehler.art == .unaufloesbar ? .fehlt : .keinZugriff)
        } catch {
            throw .zielordner(.fehlt)
        }
    }

    /// Die Statusdatei im Bereich lesen — in einem Stück und ohne `await`:
    /// Bereich öffnen, nach dem Ordner sehen, gebunden lesen, Bereich schließen.
    /// Berührt weder die Sitzung noch die Oberfläche.
    nonisolated static func statusdateiLesen(_ zugang: Statuszugang) throws(Statusdateilage) -> Data? {
        let lesen: (URL) throws -> Data? = { ordner in
            guard istOrdner(ordner) else { throw Zielordnerlage.fehlt }
            return try statusRoh(ordner.appending(component: Statusdatei.name, directoryHint: .notDirectory))
        }
        do {
            if let bereich = zugang.bereich { return try bereich.mit(lesen) }
            return try lesen(zugang.ordner)
        } catch let lage as Statusdateilage {
            throw lage
        } catch let lage as Zielordnerlage {
            throw .zielordner(lage)
        } catch let fehler as Ordnerzugriff.Fehler {
            throw .zielordner(fehler.art == .unaufloesbar ? .fehlt : .keinZugriff)
        } catch {
            throw .zielordner(.fehlt)
        }
    }

    /// Ein umbenannter Zielordner, über sein Lesezeichen wiedergefunden: Der
    /// Pfad wird nachgeführt — wie in `imZielordner`.
    func nachfuehren(_ zugang: Statuszugang) {
        if zugang.bereich != nil, zugang.ordner.path != kopieOrdner { kopieOrdner = zugang.ordner.path }
    }
}
