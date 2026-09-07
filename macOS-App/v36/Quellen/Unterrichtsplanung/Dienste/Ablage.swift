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

    /// Was beim Versiegeln oder Entsiegeln der Nebendateien herauskam. Was
    /// übrig blieb, wird benannt — die Meldung soll nicht mehr versprechen, als
    /// auf der Platte liegt.
    struct Nebendateienbilanz: Sendable, Equatable {
        struct Uebrig: Sendable, Equatable {
            let name: String
            let grund: String
        }
        var umgestellt: [String] = []
        var uebrig: [Uebrig] = []
        var vollstaendig: Bool { uebrig.isEmpty }
        var beschreibung: String {
            uebrig.map { "\($0.name) (\($0.grund))" }.joined(separator: ", ")
        }
    }

    /// Die Vorgängerfassung, ihre gestempelten Kopien und die Rettungskopien —
    /// alles, was die App selbst erreicht. Ein Ordner, der sich nicht lesen
    /// lässt, ist ein Fehler, keine leere Liste.
    func nebendateien() throws -> [URL] {
        let namen = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        return namen.filter {
            $0 != "planung.json" && $0.hasSuffix(".json")
                && ($0.hasPrefix("planung-vorher") || $0.hasPrefix("planung-beschaedigt-"))
        }.sorted().map { ordner.appendingPathComponent($0, isDirectory: false) }
    }

    /// Nur Tresor- und Dateifehler kommen hier an — `tresor_pruefen.py` übersetzt
    /// diese Datei allein mit `Tresor.swift`, also nichts aus dem Modell.
    private static func grund(_ fehler: any Error) -> String {
        (fehler as? Tresorfehler)?.text ?? fehler.localizedDescription
    }

    /// Versiegelt jede Nebendatei unter dem Tresor der Sitzung — Klartext an Ort
    /// und Stelle, Behälter unter einem älteren Schlüssel (`alter`) neu. Die
    /// Vorgängerfassung bleibt lesbare Planung; ein beschädigter Stand ist kein
    /// JSON und geht als `rohdaten` hinein. Mit `nurKlartext` bleiben Behälter
    /// unter dem eigenen Schlüssel liegen (Nachholen beim Start); ein Behälter
    /// unter einem fremden Schlüssel zählt dann als übrig. Kein Fehler wird
    /// verschluckt: Jede Datei, die nicht umgestellt wurde, steht in der Bilanz.
    @discardableResult
    func altbestaendeVersiegeln(alter: Tresor? = nil, nurKlartext: Bool = false) -> Nebendateienbilanz {
        sperre.withLock {
            var bilanz = Nebendateienbilanz()
            guard let tresor = eigenerTresor else { return bilanz }
            let dateien: [URL]
            do { dateien = try nebendateien() } catch {
                bilanz.uebrig.append(.init(name: ordner.lastPathComponent,
                                           grund: "Ordner nicht lesbar: " + Ablage.grund(error)))
                return bilanz
            }
            for url in dateien {
                let name = url.lastPathComponent
                do {
                    let roh = try Data(contentsOf: url)
                    let klartext: Data
                    if Tresor.istBehaelter(roh) {
                        let kopf = try Tresor.kopfLesen(roh)
                        if tresor.passt(zu: kopf) {
                            if nurKlartext { continue }
                            klartext = try tresor.oeffnen(kopf: kopf)
                        } else if let alter, alter.passt(zu: kopf) {
                            klartext = try alter.oeffnen(kopf: kopf)
                        } else {
                            throw Tresorfehler(art: .falscherSchluessel,
                                               text: "unter einem anderen Schlüssel versiegelt")
                        }
                    } else {
                        klartext = roh
                    }
                    let inhalt: Tresor.Inhalt = name == "planung-vorher.json" ? .planung : .rohdaten
                    try tresor.versiegeln(klartext, inhalt: inhalt, ziel: .ablage)
                        .write(to: url, options: [.atomic])
                    bilanz.umgestellt.append(name)
                } catch {
                    bilanz.uebrig.append(.init(name: name, grund: Ablage.grund(error)))
                }
            }
            return bilanz
        }
    }

    /// Der Rückweg: Jede Nebendatei unter diesem Tresor wird wieder als Klartext hingelegt.
    @discardableResult
    func altbestaendeEntsiegeln(_ tresor: Tresor) -> Nebendateienbilanz {
        sperre.withLock {
            var bilanz = Nebendateienbilanz()
            let dateien: [URL]
            do { dateien = try nebendateien() } catch {
                bilanz.uebrig.append(.init(name: ordner.lastPathComponent,
                                           grund: "Ordner nicht lesbar: " + Ablage.grund(error)))
                return bilanz
            }
            for url in dateien {
                let name = url.lastPathComponent
                do {
                    let roh = try Data(contentsOf: url)
                    guard Tresor.istBehaelter(roh) else { continue }
                    try tresor.oeffnen(roh).write(to: url, options: [.atomic])
                    bilanz.umgestellt.append(name)
                } catch {
                    bilanz.uebrig.append(.init(name: name, grund: Ablage.grund(error)))
                }
            }
            return bilanz
        }
    }
}
