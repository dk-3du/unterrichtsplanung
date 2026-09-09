// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Die laufende Sicherung auf der Festplatte — geschrieben atomar, die vorige
/// Fassung bleibt als `planung-vorher.json` liegen. Bewusst kein Akteur,
/// sondern eine Sperre: Ein `await` beim Beenden ließe die App hängen.
///
/// Die **einzige Stelle**, an der versiegelt wird: Jeder Schreibvorgang
/// bekommt den Schlüssel der Sitzung mit und geht damit als Behälter auf die
/// Platte — hereingereicht wird Klartext, den Schlüssel hält der Speicher
/// (`Planungssitzung`), nicht die Ablage. Gelesen wird roh — das Öffnen
/// braucht unter Umständen eine Freigabe, also entscheidet der Aufrufer.
final class Ablage: @unchecked Sendable {
    static let shared = Ablage()

    let ordner: URL
    let datei: URL
    let vorherigeFassung: URL
    /// Der Behälter der Lesezeichen neben der Planung — nur bei eingeschalteter
    /// Verschlüsselung. Ihn schreibt der Ordnerzugriff; `nebendateien()`
    /// erfasst nur seine Rettungskopien.
    let lesezeichen: URL

    private let sperre = NSLock()

    /// Läuft die App an einem verlegten Ablageort, also in einem Prüflauf?
    /// Ein Prüflauf darf nichts außerhalb seines Ordners hinterlassen — weder in
    /// der Planung noch in den Einstellungen des Nutzers. Das Prüfziel von
    /// `swift test` zählt immer dazu, auch ohne `PLANUNGSORDNER`.
    static let istPruefstand: Bool = {
        let eigener = ProcessInfo.processInfo.environment["PLANUNGSORDNER"] ?? ""
        return !eigener.isEmpty || imPruefziel
    }()

    /// Läuft dieser Prozess als Prüfziel (`swift test`, Xcode)? Dann gibt es
    /// ohne `PLANUNGSORDNER` einen eigenen Ordner je Prozess — nie die echte
    /// Ablage in Application Support.
    static let imPruefziel: Bool = {
        let prozess = ProcessInfo.processInfo
        let programm = (prozess.arguments.first as NSString?)?.lastPathComponent ?? ""
        // `swift test` läuft über den swiftpm-testing-helper, Xcode über xctest.
        return programm == "swiftpm-testing-helper" || programm == "xctest"
            || Bundle.main.bundleURL.pathExtension == "xctest"
            || prozess.environment["XCTestConfigurationFilePath"] != nil
            || prozess.environment["XCTestBundlePath"] != nil
    }()

    /// Der Ablageort aus seinen zwei Quellen, damit die Regel prüfbar ist.
    static func ablageort(umgebung: String, imPruefziel: Bool) -> URL {
        if !umgebung.isEmpty { return URL(fileURLWithPath: umgebung, isDirectory: true) }
        if imPruefziel {
            return URL.temporaryDirectory.appending(
                component: "Unterrichtsplanung-Pruefziel-\(ProcessInfo.processInfo.processIdentifier)",
                directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory
            .appending(component: "Unterrichtsplanung", directoryHint: .isDirectory)
    }

    /// Der Container der App im App Sandbox — `nil`, wenn die App ohne Sandbox
    /// läuft (das Prüfziel von `swift test`, ein ungesiegelter Bau). Im Sandbox
    /// ist das Benutzerverzeichnis des Prozesses der Container.
    static let container: URL? = {
        let heimat = NSHomeDirectory()
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
                || heimat.contains("/Library/Containers/")
        else { return nil }
        return URL(fileURLWithPath: heimat, isDirectory: true)
    }()

    /// Im Sandbox darf ein Prüflauf nur im Container arbeiten — anderswo käme
    /// er nicht an seine Ablage, und ein leerer Ordner öffnete „Neue Planung“.
    static let pruefordnerZulaessig: Bool = pruefordnerZulaessig(
        ProcessInfo.processInfo.environment["PLANUNGSORDNER"] ?? "", container: container)

    /// Die Regel ohne ihre zwei Quellen, damit sie prüfbar ist.
    static func pruefordnerZulaessig(_ pfad: String, container: URL?) -> Bool {
        guard !pfad.isEmpty, let container else { return true }
        let ordner = vergleichbar(pfad)
        let wurzel = vergleichbar(container.path)
        return ordner == wurzel || ordner.hasPrefix(wurzel + "/")
    }

    /// Ein Pfad in der Form, in der er sich mit anderen vergleichen lässt:
    /// ohne `..`, ohne Endschrägstrich, Symlinks aufgelöst — und ohne das
    /// `/private`, das Foundation je nachdem, ob der Ort existiert, vor
    /// `/var`, `/tmp` und `/etc` stehen lässt oder nicht.
    static func vergleichbar(_ pfad: String) -> String {
        var p = URL(fileURLWithPath: pfad).standardizedFileURL.resolvingSymlinksInPath().path
        for kurz in ["/var", "/tmp", "/etc"] where p == "/private" + kurz || p.hasPrefix("/private" + kurz + "/") {
            p = String(p.dropFirst("/private".count))
        }
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// Die Enklave auch im Prüfstand — nur für `--entsperrtest enklave|tot`
    /// (`ENTSPERRPROBE_ENKLAVE`) und für Prüfungen, die eine absichtlich
    /// unbrauchbare Wicklung vorlegen. Kein `swift test` darf je in einen
    /// Touch-ID-Dialog laufen.
    static let enklaveImPruefstand: Bool =
        ProcessInfo.processInfo.environment["ENTSPERRPROBE_ENKLAVE"] != nil

    convenience init() {
        // Ohne `PLANUNGSORDNER` arbeiten Prüfstände am gebauten Paket an der
        // echten Planung — darum die Schranke vor jedem; das Prüfziel bekommt
        // seinen eigenen Ordner.
        self.init(ordner: Ablage.ablageort(
            umgebung: ProcessInfo.processInfo.environment["PLANUNGSORDNER"] ?? "",
            imPruefziel: Ablage.imPruefziel))
    }

    /// Für Prüfungen, die den Schreibweg untersuchen, ohne `shared` zu berühren.
    init(ordner: URL) {
        self.ordner = ordner
        datei = ordner.appendingPathComponent("planung.json", isDirectory: false)
        vorherigeFassung = ordner.appendingPathComponent("planung-vorher.json", isDirectory: false)
        lesezeichen = ordner.appendingPathComponent("lesezeichen.json", isDirectory: false)
    }

    /// Nimmt Klartext entgegen — versiegelt unter `tresor`; `nil` heißt Klartext.
    func schreiben(_ daten: Data, tresor: Tresor?) throws {
        try sperre.withLock {
            let auszuschreiben = try tresor.map {
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
    func lesen() -> Bestand { sperre.withLock { bestand(datei) } }

    private func bestand(_ url: URL) -> Bestand {
        guard FileManager.default.fileExists(atPath: url.path) else { return .keine }
        do { return .daten(try Data(contentsOf: url)) }
        catch { return .unlesbar(error) }
    }

    /// Verschieben statt löschen; `nil`, wenn danach noch etwas im Weg liegt.
    private func beiseitelegen(_ quelle: URL, als name: String) -> String? {
        let verwaltung = FileManager.default
        guard verwaltung.fileExists(atPath: quelle.path) else { return name }
        let ziel = ordner.appendingPathComponent(name, isDirectory: false)
        try? verwaltung.removeItem(at: ziel)
        try? verwaltung.moveItem(at: quelle, to: ziel)
        return verwaltung.fileExists(atPath: quelle.path) ? nil : name
    }

    func vorigeFassungLesen() -> Data? {
        sperre.withLock { try? Data(contentsOf: vorherigeFassung) }
    }

    /// Klartext aus dem, was auf der Platte liegt: Ein Behälter wird mit
    /// `tresor` geöffnet, Klartext geht durch. Ohne Tresor fragt der
    /// Aufrufer nach der Freigabe, nicht diese Klasse.
    func entsiegelt(_ roh: Data, tresor: Tresor?) throws -> Data {
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
        // Der Zeitanteil trennt zwei Störungen desselben Tages.
        sperre.withLock { beiseitelegen(datei, als: "planung-beschaedigt-\(stempel).json") != nil }
    }

    // ── Die Lesezeichen als Behälter ──────────────────────────────────────
    // Roh gelesen und geschrieben; versiegelt und geöffnet wird im
    // Ordnerzugriff, der den Datenschlüssel der Sitzung bekommt.

    func lesezeichenLesen() -> Bestand { sperre.withLock { bestand(lesezeichen) } }

    func lesezeichenSchreiben(_ behaelter: Data) throws {
        try sperre.withLock {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            try behaelter.write(to: lesezeichen, options: [.atomic])
        }
    }

    /// Beim Aufheben der Verschlüsselung: Der Behälter trägt nur Chiffrat,
    /// er darf weg.
    func lesezeichenEntfernen() {
        sperre.withLock { try? FileManager.default.removeItem(at: lesezeichen) }
    }

    /// Der Name der Rettungskopie — `fremd` für einen Behälter unter einem
    /// anderen Schlüssel, der nicht beschädigt ist; `nil`, wenn der Behälter
    /// noch im Weg liegt.
    func lesezeichenBeiseitelegen(stempel: String, fremd: Bool) -> String? {
        sperre.withLock {
            beiseitelegen(lesezeichen, als: "lesezeichen-\(fremd ? "fremd" : "beschaedigt")-\(stempel).json")
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

    /// Das Register dessen, was neben der Ablage versiegelt liegt und keinen
    /// eigenen Schreiber hat: die Vorgängerfassung, ihre gestempelten Kopien,
    /// die Rettungskopien der Planung und der Lesezeichen. Jeder Wechsel der
    /// Hülle geht über diese Liste — nichts daneben wird von Hand nachgezogen.
    /// Ein Ordner, der sich nicht lesen lässt, ist ein Fehler, keine leere Liste.
    func nebendateien() throws -> [URL] {
        let namen = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        return namen.filter {
            $0.hasSuffix(".json") && ($0.hasPrefix("planung-vorher") || $0.hasPrefix("planung-beschaedigt-")
                                      || $0.hasPrefix("lesezeichen-"))
        }.sorted().map { ordner.appendingPathComponent($0, isDirectory: false) }
    }

    /// Nur Tresor- und Dateifehler kommen hier an — `tresor_pruefen.py` übersetzt
    /// diese Datei allein mit `Tresor.swift`, also nichts aus dem Modell.
    private static func grund(_ fehler: any Error) -> String {
        (fehler as? Tresorfehler)?.text ?? fehler.localizedDescription
    }

    /// Versiegelt jede Nebendatei unter `tresor` — Klartext an Ort und
    /// Stelle, Behälter unter einem älteren Schlüssel (`alter`) oder unter
    /// einer älteren Hülle neu; ein Behälter behält seinen Inhalt, Klartext
    /// geht als `planung` (Vorgängerfassung) oder `rohdaten` hinein. Mit
    /// `nurKlartext` (Nachholen beim Start) bleibt liegen, was schon Schlüssel
    /// und Hülle der Sitzung trägt; ein Behälter unter einem fremden Schlüssel
    /// zählt als übrig. Kein Fehler wird verschluckt: Jede Datei, die nicht
    /// umgestellt wurde, steht in der Bilanz.
    @discardableResult
    func altbestaendeVersiegeln(mit tresor: Tresor, alter: Tresor? = nil,
                                nurKlartext: Bool = false) -> Nebendateienbilanz {
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
                    let klartext: Data
                    let inhalt: Tresor.Inhalt
                    if Tresor.istBehaelter(roh) {
                        let kopf = try Tresor.kopfLesen(roh)
                        if tresor.passt(zu: kopf) {
                            if nurKlartext, tresor.huelleGleich(kopf, ziel: .ablage) { continue }
                            klartext = try tresor.oeffnen(kopf: kopf)
                        } else if let alter, alter.passt(zu: kopf) {
                            klartext = try alter.oeffnen(kopf: kopf)
                        } else {
                            throw Tresorfehler(art: .falscherSchluessel,
                                               text: "unter einem anderen Schlüssel versiegelt")
                        }
                        inhalt = Tresor.Inhalt(rawValue: kopf.inhalt) ?? .rohdaten
                    } else {
                        klartext = roh
                        inhalt = name == "planung-vorher.json" ? .planung : .rohdaten
                    }
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
