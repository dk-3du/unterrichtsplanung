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
    enum Ergebnis { case geschrieben, unveraendert, ueberholt }

    private let ablage: Ablage
    private let sperre = NSLock()
    private var vergeben = 0
    private var letzteNummer = 0
    private var letzterStand: String?

    init(ablage: Ablage) {
        self.ablage = ablage
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
            try ablage.schreiben(daten, tresor: tresor)
            letzterStand = stand
            return .geschrieben
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
    let ablage: Ablage
    /// Eine Vorschau (Prüfungen) schreibt absichtlich nicht — das ist keine
    /// Störung und gehört nicht in die Werkzeugleiste.
    let istVorschau: Bool
    /// Ein Prüflauf erbt die Kopie nicht — sonst schriebe er in den echten
    /// Ordner — und liest die vorgemerkte Warnung nicht, die beim Lesen
    /// verbraucht würde.
    let pruefstand: Bool

    private let folge: Sicherungsfolge
    @ObservationIgnored private var auftrag: Task<Void, Never>?

    /// Zeitstempel des zuletzt geschriebenen Standes.
    private(set) var gesicherterStand: String?
    private(set) var letzteSicherung: Date?
    private(set) var gestoert = false
    /// Gesetzt, wenn ein vorhandener Stand nicht gelesen werden konnte — dann
    /// wird nichts geschrieben, damit er nicht verlorengeht.
    var gesperrt = false
    /// Nur die Startsperre nach unlesbarem Stand lässt sich wieder aufheben;
    /// die einer Vorschau bleibt für deren ganze Lebensdauer bestehen.
    var startsperre = false

    /// Für die Werkzeugleiste: Seit wann auch immer — es wird gerade nichts
    /// gesichert, und das muss sichtbar bleiben, nicht nur kurz aufblitzen.
    var liegtStill: Bool { !istVorschau && (gesperrt || gestoert) }

    /// Die Sitzung, die geschrieben wird — abgefragt, wenn der Auftrag feuert,
    /// nicht wenn er angestoßen wird: Dazwischen tippt der Nutzer weiter.
    @ObservationIgnored var sitzungsquelle: @MainActor () -> Planungssitzung = { .leer }
    /// Die Sicherung ist gerade in Störung geraten — einmal je Wechsel.
    @ObservationIgnored var beiStoerung: @MainActor () -> Void = {}

    init(ablage: Ablage, vorschau: Bool = false, pruefstand: Bool) {
        self.ablage = ablage
        istVorschau = vorschau
        self.pruefstand = pruefstand
        folge = Sicherungsfolge(ablage: ablage)
        kopieAktiv = pruefstand
            ? false : UserDefaults.standard.bool(forKey: Einstellungen.Schluessel.autoexportAktiv)
        kopieOrdner = pruefstand
            ? "" : (UserDefaults.standard.string(forKey: Einstellungen.Schluessel.autoexportOrdner) ?? "")
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
            lageMelden(geklappt: false)
            return
        }
        switch ergebnis {
        case .geschrieben:
            gesicherterStand = stand
            letzteSicherung = Date()
        case .unveraendert:
            // Ein gleichlaufendes `jetztSichern()` hat diesen Stand schon
            // hingelegt; offen war nur noch der Merker.
            gesicherterStand = stand
        case .ueberholt:
            // Auf der Platte liegt ein jüngerer Stand — nichts zu melden.
            return
        }
        lageMelden(geklappt: true)
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
            _ = try folge.schreiben(nummer: nummer, stand: planung.geaendert,
                                    daten: klartext, tresor: tresor)
            gesicherterStand = planung.geaendert
            letzteSicherung = Date()
            lageMelden(geklappt: true)
        } catch {
            lageMelden(geklappt: false)
        }
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
        letzteSicherung = ablage.stand()
    }

    func lageMelden(geklappt: Bool) {
        let gestoert = !geklappt
        guard gestoert != self.gestoert else { return }
        self.gestoert = gestoert
        if gestoert { beiStoerung() }
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
        gestoert = false
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

    /// Leer heißt: noch keiner gewählt.
    var kopieOrdner: String {
        didSet { Einstellungen.setzen(kopieOrdner, Einstellungen.Schluessel.autoexportOrdner) }
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
        guard Ordnerzugriff.zustaendig(fuer: gemerkt.path) != nil else {
            guard !Ordnerzugriff.imSandbox else { throw Zielordnerlage.keinZugriff }
            guard istOrdner(gemerkt) else { throw Zielordnerlage.fehlt }
            return try arbeit(gemerkt)
        }
        do {
            return try Ordnerzugriff.mit(gemerkt.path) { ordner in
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
              Ordnerzugriff.zustaendig(fuer: kopieOrdner) == nil else { return }
        let ordner = URL(fileURLWithPath: kopieOrdner, isDirectory: true)
        guard istOrdner(ordner) else { return }
        lesezeichenAblegen(ordner)
    }

    /// Ein Ort, der der App gerade offensteht — nach einer Wahl —, bekommt
    /// sein Lesezeichen; misslingt das, fragt der nächste Start.
    func lesezeichenAblegen(_ ordner: URL) {
        _ = try? Ordnerzugriff.merken(ordner)
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

    /// Die Kopie im Zielordner — nur verschlüsselt, atomar; liefert die Datei.
    /// Läuft beim Beenden: Nichts wartet auf einen Ablaufwechsel.
    func kopieSchreiben(_ sitzung: Planungssitzung, name: String) throws(Kopiehindernis) -> URL {
        guard let planung = sitzung.planung else { throw .nichtsZuSchreiben }
        do {
            return try imZielordner { ordner in
                guard let tresor = sitzung.tresor else { throw Kopiehindernis.keinTresor }
                let ziel = ordner.appending(component: name, directoryHint: .notDirectory)
                do {
                    try tresor.versiegeln(try Planungsdatei.schreiben(planung),
                                          inhalt: .planung, ziel: .kopie)
                        .write(to: ziel, options: [.atomic])
                } catch {
                    throw Kopiehindernis.schreiben(ordner: ordner, fehler: error)
                }
                Einstellungen.entfernen(Einstellungen.Schluessel.autoexportFehler)
                letzteKopie = Date()
                Einstellungen.setzen(letzteKopie?.timeIntervalSinceReferenceDate ?? 0,
                                     Einstellungen.Schluessel.autoexportStand)
                return ziel
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
    /// Warnung, die damit verbraucht ist. Ein Prüflauf liest sie nicht.
    func kopielageBeimStart() -> String? {
        guard !pruefstand else { return nil }
        let stand = UserDefaults.standard.double(forKey: Einstellungen.Schluessel.autoexportStand)
        if stand > 0 { letzteKopie = Date(timeIntervalSinceReferenceDate: stand) }
        guard let fehler = UserDefaults.standard.string(forKey: Einstellungen.Schluessel.autoexportFehler),
              !fehler.isEmpty else { return nil }
        Einstellungen.entfernen(Einstellungen.Schluessel.autoexportFehler)
        return fehler
    }

    /// Eine Statusdatei, die nicht eingelesen wird.
    enum Statusdateilage: Error, Equatable {
        /// Unverhältnismäßig groß — Größe in Byte.
        case zuGross(Int)
    }

    /// Die Statusdatei der iPad-Ansicht aus dem Zielordner — `nil`, wenn keine
    /// liegt oder der Ordner gerade nicht erreichbar ist (das meldet sich beim
    /// Schreiben der Kopie). Gelesen im Sicherheitsbereich des Zielordners.
    func statusdateiLesen() throws(Statusdateilage) -> Data? {
        do {
            return try imZielordner { ordner in
                let datei = ordner.appending(component: Statusdatei.name, directoryHint: .notDirectory)
                let groesse = (try? datei.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard groesse > 0 else { return nil }
                guard groesse <= Statusdatei.hoechstgroesse else { throw Statusdateilage.zuGross(groesse) }
                return try? Data(contentsOf: datei)
            }
        } catch let lage as Statusdateilage {
            throw lage
        } catch {
            return nil
        }
    }
}
