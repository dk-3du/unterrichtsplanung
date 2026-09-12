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
    /// Die Sitzpläne neben der Planung — Klartext oder Behälter, wie die
    /// Planung selbst. Sie schreibt der Sitzplandienst; `nebendateien()`
    /// erfasst nur die Rettungskopien.
    let sitzplaene: URL

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
        sitzplaene = ordner.appendingPathComponent("sitzplaene.json", isDirectory: false)
    }

    /// Was am Schreiben scheitert, bevor ein Byte auf der Platte ist: Die Datei
    /// läge über der Grenze, die der Aufrufer hereinreicht — Byte, die sie hätte.
    struct Schreibfehler: LocalizedError {
        let groesse: Int
        let grenze: Int
        var errorDescription: String? {
            "Die Planung ist mit \(groesse / 1024 / 1024) MB größer als die Lesegrenze "
                + "(\(grenze / 1024 / 1024) MB) und wurde nicht geschrieben."
        }
    }

    /// Nimmt Klartext entgegen — versiegelt unter `tresor`; `nil` heißt Klartext.
    /// Über `grenze` wird nicht geschrieben (`Schreibfehler`): Was diese App
    /// nicht mehr liest, legt sie auch nicht hin — der letzte Stand bleibt
    /// liegen. Liefert die Byte auf der Platte.
    @discardableResult
    func schreiben(_ daten: Data, tresor: Tresor?, hoechstens grenze: Int = .max) throws -> Int {
        try sperre.withLock {
            let auszuschreiben = try tresor.map {
                try $0.versiegeln(daten, inhalt: .planung, ziel: .ablage)
            } ?? daten
            guard auszuschreiben.count <= grenze else {
                throw Schreibfehler(groesse: auszuschreiben.count, grenze: grenze)
            }
            let dateiverwaltung = FileManager.default
            try dateiverwaltung.createDirectory(at: ordner, withIntermediateDirectories: true)

            letzteVorgaengerStoerung = dateiverwaltung.fileExists(atPath: datei.path)
                ? vorigeFassungFortschreiben(dateiverwaltung) : nil
            try auszuschreiben.write(to: datei, options: [.atomic])
            return auszuschreiben.count
        }
    }

    /// Warum die Vorgängerfassung beim letzten Schreiben nicht fortgeschrieben
    /// wurde — `nil`, wenn sie es wurde oder nichts fortzuschreiben war. Die
    /// Hauptdatei ist davon unberührt; der Sicherungsdienst sagt es einmal.
    var vorgaengerStoerung: String? { sperre.withLock { letzteVorgaengerStoerung } }
    private var letzteVorgaengerStoerung: String?

    /// Erst in eine Nebendatei kopieren, dann atomar darübertauschen: Beim
    /// Löschen-dann-Kopieren stand zwischendurch keine Vorgängerfassung da, und
    /// ein voller Datenträger ließ sie ersatzlos verschwinden. Liefert den
    /// Grund, wenn es nicht ging — die ältere Fassung davor bleibt dann liegen.
    private func vorigeFassungFortschreiben(_ verwaltung: FileManager) -> String? {
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
            return error.localizedDescription
        }
        return nil
    }

    enum Bestand {
        case keine
        case daten(Data)
        /// Liegt da, ist aber größer als die Lesegrenze — nicht gelesen; die
        /// Größe in Byte. Was so groß ist, hat diese App nicht geschrieben.
        case zuGross(Int)
        /// Liegt da, ließ sich aber nicht lesen — darf nicht überschrieben werden.
        case unlesbar(any Error)
    }

    /// Was am Lesen scheitert, bevor ein Byte gelesen ist.
    struct Lesefehler: LocalizedError {
        let text: String
        var errorDescription: String? { text }
    }

    /// Roh, wie es auf der Platte liegt — Klartext oder Behälter. Die Grenze
    /// reicht der Aufrufer herein (`Planungsdatei.hoechstgroesse`): Diese
    /// Datei wird von `tresor_pruefen.py` allein mit `Tresor.swift` übersetzt
    /// und kennt das Modell nicht.
    func lesen(hoechstens grenze: Int) -> Bestand {
        sperre.withLock { bestand(datei, hoechstens: grenze) }
    }

    private func bestand(_ url: URL, hoechstens grenze: Int) -> Bestand {
        Ablage.gebundenLesen(url, hoechstens: grenze)
    }

    /// Der eine Leseweg für alles mit Grenze — Ablage, Fassung davor,
    /// Lesezeichen, Nebendateien, Import, Statusdatei: Die Datei wird geöffnet,
    /// Art und Größe am geöffneten Deskriptor gemessen (nicht am Pfad, der
    /// zwischen Messen und Lesen ein anderes Objekt bekommen kann), dann
    /// höchstens `grenze + 1` Byte gelesen. Wächst die Datei nach dem Messen,
    /// endet das Lesen an der Grenze. Ein Symlink führt zu seinem Ziel, und
    /// gemessen wird das Ziel; eine Pipe blockiert nicht und ist keine reguläre
    /// Datei. `nachDemMessen` ist der Haken der Prüfungen.
    static func gebundenLesen(_ url: URL, hoechstens grenze: Int,
                              nachDemMessen: () -> Void = {}) -> Bestand {
        let name = url.lastPathComponent
        let deskriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard deskriptor >= 0 else {
            if errno == ENOENT { return .keine }
            return .unlesbar(Lesefehler(text: "„\(name)“ ließ sich nicht öffnen (\(String(cString: strerror(errno)))."))
        }
        let griff = FileHandle(fileDescriptor: deskriptor, closeOnDealloc: false)
        defer { try? griff.close() }
        var status = stat()
        guard fstat(deskriptor, &status) == 0 else {
            return .unlesbar(Lesefehler(text: "Die Größe von „\(name)“ ließ sich nicht bestimmen."))
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else {
            return .unlesbar(Lesefehler(text: "„\(name)“ ist keine reguläre Datei."))
        }
        let gemessen = Int(status.st_size)
        guard gemessen <= grenze else { return .zuGross(gemessen) }
        nachDemMessen()
        let hoechstens = grenze < .max ? grenze + 1 : .max
        var daten = Data(capacity: gemessen)
        do {
            while daten.count < hoechstens {
                guard let stueck = try griff.read(upToCount: min(1 << 20, hoechstens - daten.count)),
                      !stueck.isEmpty else { break }
                daten.append(stueck)
            }
        } catch {
            return .unlesbar(error)
        }
        guard daten.count <= grenze else {
            // Nach dem Messen gewachsen: so groß, wie sie jetzt ist.
            let jetzt = fstat(deskriptor, &status) == 0 ? Int(status.st_size) : 0
            return .zuGross(max(jetzt, daten.count))
        }
        return .daten(daten)
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

    /// `nil`, wenn keine liegt, sie zu groß ist oder sich nicht lesen lässt.
    func vorigeFassungLesen(hoechstens grenze: Int) -> Data? {
        sperre.withLock {
            if case .daten(let daten) = bestand(vorherigeFassung, hoechstens: grenze) { daten } else { nil }
        }
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

    /// Zeitpunkt und Byte der Ablage auf der Platte — `nil`, wenn keine liegt.
    func stand() -> (zeitpunkt: Date?, groesse: Int?) {
        sperre.withLock {
            let werte = try? Ablage.frisch(datei).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return (werte?.contentModificationDate, werte?.fileSize)
        }
    }

    /// Ein `URL`-Wert merkt sich seine Ressourcenwerte: Wer nach dem Schreiben
    /// über denselben Wert die Größe fragt, bekommt die alte (nachgemessen).
    /// `datei` und `vorherigeFassung` leben so lange wie die Ablage — darum
    /// vor jeder Abfrage der Vorrat weg.
    private static func frisch(_ url: URL) -> URL {
        var frisch = url
        frisch.removeAllCachedResourceValues()
        return frisch
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

    func lesezeichenLesen(hoechstens grenze: Int) -> Bestand {
        sperre.withLock { bestand(lesezeichen, hoechstens: grenze) }
    }

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

    // ── Die Sitzpläne ─────────────────────────────────────────────────────
    // Roh gelesen und geschrieben; Klartext oder Behälter entscheidet der
    // Sitzplandienst, der den Datenschlüssel der Sitzung bekommt.

    func sitzplaeneLesen(hoechstens grenze: Int) -> Bestand {
        sperre.withLock { bestand(sitzplaene, hoechstens: grenze) }
    }

    func sitzplaeneSchreiben(_ daten: Data) throws {
        try sperre.withLock {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            try daten.write(to: sitzplaene, options: [.atomic])
        }
    }

    /// Ohne Sitzpläne liegt keine Datei — beim letzten Entfernen und bei der
    /// Rücknahme eines Behälters.
    func sitzplaeneEntfernen() {
        sperre.withLock { try? FileManager.default.removeItem(at: sitzplaene) }
    }

    /// Der Name der Rettungskopie — `fremd` für einen Behälter unter einem
    /// anderen Schlüssel oder neben einer Klartext-Planung; `nil`, wenn die
    /// Datei noch im Weg liegt.
    func sitzplaeneBeiseitelegen(stempel: String, fremd: Bool) -> String? {
        sitzplaeneBeiseitelegen(als: "sitzplaene-\(fremd ? "fremd" : "beschaedigt")-\(stempel).json")
    }

    /// Beiseitelegen unter eigenem Namen — Klartext neben der versiegelten
    /// Planung, den der Nutzer nicht übernehmen will (E43).
    func sitzplaeneBeiseitelegen(als name: String) -> String? {
        sperre.withLock { beiseitelegen(sitzplaene, als: name) }
    }

    /// Eine Kopie der Sitzplandatei, wie sie liegt — bevor eine
    /// verlustbehaftete Bereinigung beim nächsten Schreiben darüber geht
    /// (B14). `nil`, wenn keine liegt oder das Kopieren scheitert.
    func sitzplaeneKopieren(als name: String) -> String? {
        sperre.withLock {
            let verwaltung = FileManager.default
            guard verwaltung.fileExists(atPath: sitzplaene.path) else { return nil }
            let ziel = ordner.appendingPathComponent(name, isDirectory: false)
            try? verwaltung.removeItem(at: ziel)
            do {
                try verwaltung.copyItem(at: sitzplaene, to: ziel)
                return name
            } catch {
                return nil
            }
        }
    }

    /// Verwaiste Pläne in eine eigene Rettungskopie im Register — Klartext
    /// oder Behälter, wie der Dienst sie reicht (E41).
    func sitzplaeneRettungSchreiben(_ daten: Data, als name: String) throws -> String {
        try sperre.withLock {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            try daten.write(to: ordner.appendingPathComponent(name, isDirectory: false), options: [.atomic])
            return name
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
    /// die Rettungskopien der Planung, der Lesezeichen und der Sitzpläne. Jeder
    /// Wechsel der Hülle geht über diese Liste — nichts daneben wird von Hand
    /// nachgezogen.
    /// Ein Ordner, der sich nicht lesen lässt, ist ein Fehler, keine leere Liste.
    func nebendateien() throws -> [URL] {
        let namen = try FileManager.default.contentsOfDirectory(atPath: ordner.path)
        return namen.filter {
            $0.hasSuffix(".json") && ($0.hasPrefix("planung-vorher") || $0.hasPrefix("planung-beschaedigt-")
                                      || $0.hasPrefix("lesezeichen-") || $0.hasPrefix("sitzplaene-"))
        }.sorted().map { ordner.appendingPathComponent($0, isDirectory: false) }
    }

    /// Nur Tresor- und Dateifehler kommen hier an — `tresor_pruefen.py` übersetzt
    /// diese Datei allein mit `Tresor.swift`, also nichts aus dem Modell.
    private static func grund(_ fehler: any Error) -> String {
        (fehler as? Tresorfehler)?.text ?? fehler.localizedDescription
    }

    /// Eine Nebendatei, gebunden gelesen wie die Ablage selbst — oder der
    /// Grund, warum nicht: zu groß oder keine reguläre Datei heißt übrig, nie gelesen.
    private func nebendatei(_ url: URL, hoechstens grenze: Int) throws -> Data {
        switch bestand(url, hoechstens: grenze) {
        case .daten(let roh): return roh
        case .keine: throw Lesefehler(text: "nicht mehr da")
        case .zuGross(let groesse): throw Lesefehler(text: "ungewöhnlich groß (\(groesse / 1024 / 1024) MB), nicht gelesen")
        case .unlesbar(let fehler): throw fehler
        }
    }

    /// Versiegelt jede Nebendatei unter `tresor` — Klartext an Ort und
    /// Stelle, Behälter unter einem älteren Schlüssel (`alter`) oder unter
    /// einer älteren Hülle neu; ein Behälter behält seinen Inhalt, Klartext
    /// geht als `planung` (Vorgängerfassung) oder `rohdaten` hinein. Mit
    /// `nurKlartext` (Nachholen beim Start) bleibt liegen, was schon Schlüssel
    /// und Hülle der Sitzung trägt; ein Behälter unter einem fremden Schlüssel
    /// zählt als übrig. Kein Fehler wird verschluckt: Jede Datei, die nicht
    /// umgestellt wurde, steht in der Bilanz. Die Grenze reicht der Aufrufer
    /// herein wie bei `lesen(hoechstens:)`.
    @discardableResult
    func altbestaendeVersiegeln(mit tresor: Tresor, alter: Tresor? = nil,
                                nurKlartext: Bool = false, hoechstens grenze: Int) -> Nebendateienbilanz {
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
                    let roh = try nebendatei(url, hoechstens: grenze)
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
    func altbestaendeEntsiegeln(_ tresor: Tresor, hoechstens grenze: Int) -> Nebendateienbilanz {
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
                    let roh = try nebendatei(url, hoechstens: grenze)
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
