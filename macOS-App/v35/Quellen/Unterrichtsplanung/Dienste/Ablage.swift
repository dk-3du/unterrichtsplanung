// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Die laufende Sicherung auf der Festplatte — geschrieben atomar, die vorige
/// Fassung bleibt als `planung-vorher.json` liegen. Bewusst kein Akteur,
/// sondern eine Sperre: Ein `await` beim Beenden ließe die App hängen.
///
/// Die **einzige Stelle**, an der versiegelt wird: Liegt ein
/// `Tresor` an, geht jeder Schreibvorgang als Behälter auf die Platte;
/// `Planungsspeicher` und die Ansichten merken nichts. Gelesen wird roh —
/// das Öffnen braucht unter Umständen eine Freigabe, also entscheidet der
/// Aufrufer.
final class Ablage: @unchecked Sendable {
    static let shared = Ablage()

    let ordner: URL
    let datei: URL
    let vorherigeFassung: URL

    private let sperre = NSLock()
    private var eigenerTresor: Tresor?

    /// Der Datenschlüssel der Sitzung — `nil` heißt Klartext oder noch nicht
    /// entsperrt. Unter derselben Sperre wie das Schreiben.
    var tresor: Tresor? {
        get { sperre.withLock { eigenerTresor } }
        set { sperre.withLock { eigenerTresor = newValue } }
    }

    /// Läuft die App an einem verlegten Ablageort, also in einem Prüflauf?
    /// Ein Prüflauf darf nichts außerhalb seines Ordners hinterlassen — weder in
    /// der Planung noch in den Einstellungen des Nutzers.
    static let istPruefstand: Bool = {
        let eigener = ProcessInfo.processInfo.environment["PLANUNGSORDNER"] ?? ""
        return !eigener.isEmpty
    }()

    /// Die Enklave auch im Prüfstand — nur für `--entsperrtest enklave|tot`
    /// (`ENTSPERRPROBE_ENKLAVE`) und für Prüfungen, die eine absichtlich
    /// unbrauchbare Wicklung vorlegen. Kein `swift test` darf je in einen
    /// Touch-ID-Dialog laufen.
    nonisolated(unsafe) static var enklaveImPruefstand: Bool =
        ProcessInfo.processInfo.environment["ENTSPERRPROBE_ENKLAVE"] != nil

    convenience init() {
        // Ohne `PLANUNGSORDNER` arbeiten auch Prüfstände an der echten Planung.
        let eigener = ProcessInfo.processInfo.environment["PLANUNGSORDNER"] ?? ""
        self.init(ordner: eigener.isEmpty
            ? URL.applicationSupportDirectory
                .appending(component: "Unterrichtsplanung", directoryHint: .isDirectory)
            : URL(fileURLWithPath: eigener, isDirectory: true))
    }

    /// Für Prüfungen, die den Schreibweg untersuchen, ohne `shared` zu berühren.
    init(ordner: URL) {
        self.ordner = ordner
        datei = ordner.appendingPathComponent("planung.json", isDirectory: false)
        vorherigeFassung = ordner.appendingPathComponent("planung-vorher.json", isDirectory: false)
    }

    /// Nimmt Klartext entgegen — versiegelt, sobald ein Tresor anliegt.
    func schreiben(_ daten: Data) throws {
        try sperre.withLock {
            let auszuschreiben = try eigenerTresor.map {
                try $0.versiegeln(daten, inhalt: .planung, ziel: .ablage)
            } ?? daten
            let dateiverwaltung = FileManager.default
            try dateiverwaltung.createDirectory(at: ordner, withIntermediateDirectories: true)

            if dateiverwaltung.fileExists(atPath: datei.path) {
                vorigeFassungFortschreiben(dateiverwaltung)
            }
            try auszuschreiben.write(to: datei, options: [.atomic])
        }
    }

    /// Erst in eine Nebendatei kopieren, dann atomar darübertauschen: Beim
    /// Löschen-dann-Kopieren stand zwischendurch keine Vorgängerfassung da, und
    /// ein voller Datenträger ließ sie ersatzlos verschwinden.
    private func vorigeFassungFortschreiben(_ verwaltung: FileManager) {
        let nebendatei = ordner.appendingPathComponent("planung-vorher.json.neu",
                                                       isDirectory: false)
        try? verwaltung.removeItem(at: nebendatei)
        do {
            try verwaltung.copyItem(at: datei, to: nebendatei)
            if verwaltung.fileExists(atPath: vorherigeFassung.path) {
                _ = try verwaltung.replaceItemAt(vorherigeFassung, withItemAt: nebendatei)
            } else {
                try verwaltung.moveItem(at: nebendatei, to: vorherigeFassung)
            }
        } catch {
            try? verwaltung.removeItem(at: nebendatei)
        }
    }

    enum Bestand {
        case keine
        case daten(Data)
        /// Liegt da, ließ sich aber nicht lesen — darf nicht überschrieben werden.
        case unlesbar(any Error)
    }

    /// Roh, wie es auf der Platte liegt — Klartext oder Behälter.
    func lesen() -> Bestand {
        sperre.withLock {
            guard FileManager.default.fileExists(atPath: datei.path) else { return .keine }
            do { return .daten(try Data(contentsOf: datei)) }
            catch { return .unlesbar(error) }
        }
    }

    func vorigeFassungLesen() -> Data? {
        sperre.withLock { try? Data(contentsOf: vorherigeFassung) }
    }

    /// Klartext aus dem, was auf der Platte liegt: Ein Behälter wird mit dem
    /// Tresor der Sitzung geöffnet, Klartext geht durch. Ohne Tresor fragt der
    /// Aufrufer nach der Freigabe, nicht diese Klasse.
    func entsiegelt(_ roh: Data) throws -> Data {
        guard Tresor.istBehaelter(roh) else { return roh }
        guard let tresor else {
            throw Tresorfehler(art: .abgebrochen,
                               text: "Die Ablage ist verschlüsselt und noch nicht entsperrt.")
        }
        return try tresor.oeffnen(roh)
    }

    func stand() -> Date? {
        sperre.withLock {
            try? datei.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    }

    /// `true`, wenn danach keine `planung.json` mehr im Weg liegt — erst dann
    /// darf wieder geschrieben werden.
    @discardableResult
    func beschaedigtenStandBeiseitelegen(stempel: String) -> Bool {
        sperre.withLock {
            let verwaltung = FileManager.default
            guard verwaltung.fileExists(atPath: datei.path) else { return true }
            // Der Zeitanteil trennt zwei Störungen desselben Tages.
            let ziel = ordner.appendingPathComponent("planung-beschaedigt-\(stempel).json")
            try? verwaltung.removeItem(at: ziel)
            try? verwaltung.moveItem(at: datei, to: ziel)
            return !verwaltung.fileExists(atPath: datei.path)
        }
    }

    // ── Altbestände: überschreiben, nie löschen ───────────────────────────
    // Löschen ließe den Klartext im Papierkorb liegen.

    /// Die Vorgängerfassung, ihre gestempelten Kopien und die Rettungskopien —
    /// alles, was die App selbst erreicht.
    func nebendateien() -> [URL] {
        let namen = (try? FileManager.default.contentsOfDirectory(atPath: ordner.path)) ?? []
        return namen.filter {
            $0 != "planung.json" && $0.hasSuffix(".json")
                && ($0.hasPrefix("planung-vorher") || $0.hasPrefix("planung-beschaedigt-"))
        }.sorted().map { ordner.appendingPathComponent($0, isDirectory: false) }
    }

    /// Versiegelt jede Nebendatei unter dem Tresor der Sitzung — Klartext an Ort
    /// und Stelle, Behälter unter einem älteren Schlüssel (`alter`) neu. Die
    /// Vorgängerfassung bleibt lesbare Planung; ein beschädigter Stand ist kein
    /// JSON und geht als `rohdaten` hinein. Liefert die Zahl der Dateien.
    @discardableResult
    func altbestaendeVersiegeln(alter: Tresor? = nil) -> Int {
        sperre.withLock {
            guard let tresor = eigenerTresor else { return 0 }
            var anzahl = 0
            for url in nebendateien() {
                guard let roh = try? Data(contentsOf: url) else { continue }
                let klartext: Data
                if Tresor.istBehaelter(roh) {
                    guard let kopf = try? Tresor.kopfLesen(roh) else { continue }
                    if tresor.passt(zu: kopf) {
                        guard let offen = try? tresor.oeffnen(kopf: kopf) else { continue }
                        klartext = offen
                    } else if let alter, alter.passt(zu: kopf), let offen = try? alter.oeffnen(kopf: kopf) {
                        klartext = offen
                    } else {
                        continue
                    }
                } else {
                    klartext = roh
                }
                let inhalt: Tresor.Inhalt = url.lastPathComponent == "planung-vorher.json"
                    ? .planung : .rohdaten
                guard let versiegelt = try? tresor.versiegeln(klartext, inhalt: inhalt, ziel: .ablage),
                      (try? versiegelt.write(to: url, options: [.atomic])) != nil else { continue }
                anzahl += 1
            }
            return anzahl
        }
    }

    /// Der Rückweg: Jede Nebendatei unter diesem Tresor wird wieder als Klartext hingelegt.
    @discardableResult
    func altbestaendeEntsiegeln(_ tresor: Tresor) -> Int {
        sperre.withLock {
            var anzahl = 0
            for url in nebendateien() {
                guard let roh = try? Data(contentsOf: url), Tresor.istBehaelter(roh),
                      let klartext = try? tresor.oeffnen(roh),
                      (try? klartext.write(to: url, options: [.atomic])) != nil else { continue }
                anzahl += 1
            }
            return anzahl
        }
    }
}
