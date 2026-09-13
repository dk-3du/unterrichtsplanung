// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// Welcher Übergang des Schutzes — steht in der Marke und in den Meldungen.
enum Uebergangsart: String, Codable, Sendable, CaseIterable {
    case einschalten
    case erneuern
    case aufheben
    case passphrase
    case wicklungAnlegen = "wicklung-anlegen"
    case wicklungEntfernen = "wicklung-entfernen"

    /// „Das Einschalten der Verschlüsselung“ — am Satzanfang.
    var satzanfang: String { beschreibung.prefix(1).uppercased() + beschreibung.dropFirst() }

    /// „das Einschalten der Verschlüsselung“ — für die Meldungen des Wiederanlaufs.
    var beschreibung: String {
        switch self {
        case .einschalten: "das Einschalten der Verschlüsselung"
        case .erneuern: "das Erneuern des Schlüssels"
        case .aufheben: "das Aufheben der Verschlüsselung"
        case .passphrase: "das Ändern der Passphrase"
        case .wicklungAnlegen: "das Anlegen der Wicklung dieses Macs"
        case .wicklungEntfernen: "das Entfernen der Wicklung dieses Macs"
        }
    }
}

/// Die Marke `uebergang.json`: der eine Moment, in dem der neue Stand gilt.
/// Sie nennt den Übergang, seinen Stempel, die Kennung des neuen Schlüssels
/// (leer heißt Klartext) und je Datei den Namen und die Prüfsumme des
/// Zwillings — oder dass die Datei entfällt. Kein Schlüsselmaterial. Was
/// `gueltig` nicht besteht, setzt der Wiederanlauf nicht ein — die Marke ist
/// eine Datei im Ordner und wird wie jede andere geprüft, nicht geglaubt.
struct Uebergangsmarke: Codable, Equatable, Sendable {
    static let typ = "unterrichtsplanung-uebergang"
    static let version = 1

    struct Eintrag: Codable, Equatable, Sendable {
        let name: String
        /// SHA-256 des Zwillings, hexadezimal; `nil`: Die Datei wird entfernt.
        let sha256: String?
        /// Das Original lag beim Vorbereiten: Dann behält das Einsetzen es als
        /// Vorgänger, und der Rückweg stellt es zurück; sonst geht die Datei
        /// beim Rückweg wieder fort (E53).
        let vorhanden: Bool

        init(name: String, sha256: String?, vorhanden: Bool = true) {
            self.name = name
            self.sha256 = sha256
            self.vorhanden = vorhanden
        }

        init(from decoder: any Decoder) throws {
            let behaelter = try decoder.container(keyedBy: CodingKeys.self)
            name = try behaelter.decode(String.self, forKey: .name)
            sha256 = try behaelter.decodeIfPresent(String.self, forKey: .sha256)
            // Eine Marke aus 1.5.1 kennt das Feld nicht: Dann entscheidet der
            // Vorgänger auf der Platte, ob es einen Rückweg gibt.
            vorhanden = try behaelter.decodeIfPresent(Bool.self, forKey: .vorhanden) ?? true
        }
    }

    let typ: String
    let version: Int
    let art: Uebergangsart
    let stempel: String
    let kennung: String
    let dateien: [Eintrag]

    init(art: Uebergangsart, stempel: String, kennung: String, dateien: [Eintrag]) {
        typ = Uebergangsmarke.typ
        version = Uebergangsmarke.version
        self.art = art
        self.stempel = stempel
        self.kennung = kennung
        self.dateien = dateien
    }

    /// Typ und Fassung stimmen, und jeder Eintrag ist ein Name der Generation
    /// — kein Pfad, nicht die Marke, kein Zwilling —, einmalig, mit einer
    /// Prüfsumme aus 64 Hexziffern oder ohne (die Datei entfällt). Eine
    /// Prüfsumme belegt nur, dass ein Zwilling unversehrt ist; wohin er kommt,
    /// entscheidet allein diese Prüfung (N51-02).
    var gueltig: Bool {
        guard typ == Uebergangsmarke.typ, version == Uebergangsmarke.version, !dateien.isEmpty else { return false }
        var namen: Set<String> = []
        for eintrag in dateien {
            guard Uebergangsdienst.nameZulaessig(eintrag.name), namen.insert(eintrag.name).inserted else { return false }
            if let sha256 = eintrag.sha256 {
                guard sha256.count == 64, sha256.allSatisfy(\.isHexDigit) else { return false }
            }
        }
        return true
    }
}

/// Ein benannter Fehlschlag im Übergang — im Dienst und in den Diensten,
/// die seine Inhalte liefern.
struct Uebergangsfehler: LocalizedError, Sendable {
    let text: String
    var errorDescription: String? { text }
}

/// Der Übergabestand mit Generationen (E47): Ein Übergang des Schutzes
/// schreibt nichts über das, was gilt. Er legt je Datei einen Zwilling
/// `<name>.uebergang` unter dem neuen Schutz daneben und liest ihn zurück
/// (*vorbereiten*), schreibt dann atomar die Marke `uebergang.json`
/// (*übergeben*) — von da an gilt der neue Stand — und tauscht danach jeden
/// Zwilling atomar über sein Original, zuletzt die Marke fort (*einsetzen*).
/// Jedes ersetzte Original bleibt dabei als `<name>.vorgaenger` liegen, bis
/// die Marke fort ist (E53). Endet der Prozess vor der Marke, sind die
/// Zwillinge Kopien eines Stands, der nie galt: Der nächste Start entfernt
/// sie (*verwerfen*). Endet er nach der Marke, vollendet der nächste Start das
/// Einsetzen über die Prüfsummen der Marke — ohne Schlüssel
/// (*wiederanlaufen*); geht das nicht, stellt er über die Vorgänger den alten
/// Stand her (*Rückweg*) oder lässt, fehlt ein Vorgänger, alles liegen.
/// Bleibt ein Einsetzen im laufenden Prozess unvollendet, holt jeder
/// Schreibanlass es nach, bevor er schreibt (E54, `einsetzenErneut`). Reine
/// Dateilogik am Ablageordner; was in die Zwillinge kommt, erzeugen die Dienste.
///
/// Einer je Sicherungsdienst, an dessen Ordner; `wiederanlaufen` läuft beim
/// Start vor dem ersten Lesen.
@MainActor
final class Uebergangsdienst {
    nonisolated static let markenname = "uebergang.json"
    nonisolated static let zwillingssuffix = ".uebergang"
    /// Das ersetzte Original, bis die Marke fort ist (E53).
    nonisolated static let vorgaengersuffix = ".vorgaenger"
    /// Eine Marke hat ein paar hundert Byte.
    nonisolated static let markeHoechstens = 64 * 1024

    let ordner: URL

    /// Was in eine Datei der Generation kommt.
    enum Inhalt: Equatable {
        case daten(Data)
        /// Nach dem Übergang liegt die Datei nicht mehr — der Behälter der
        /// Lesezeichen beim Aufheben, die Sitzpläne ohne Pläne.
        case entfernen
    }

    /// Die Schritte, nach denen der Prüfstand hart abbrechen kann (E52).
    /// `aufgeraeumt`: alle Zwillinge sind getauscht und die Vorgänger fort, die
    /// Marke liegt noch — die Stelle, die E60 neu schafft.
    enum Schritt: String, Sendable { case vorbereitet, uebergeben, einsetzen, aufgeraeumt }

    /// Für die Prüfungen: nach jedem Schritt gerufen — die Prüfung hält den
    /// Ordner fest, wie ein Abbruch an dieser Stelle ihn hinterließe.
    var haken: ((Schritt) -> Void)?

    /// Die vorbereitete Generation — zwischen Vorbereiten und Einsetzen.
    private(set) var laufend: Uebergangsmarke?
    /// Die Marke liegt: Der neue Stand gilt, zurück geht es nicht mehr.
    private(set) var istUebergeben = false

    init(ordner: URL) {
        self.ordner = ordner
    }

    private var marke: URL { Uebergangsdienst.marke(in: ordner) }

    nonisolated static func marke(in ordner: URL) -> URL {
        ordner.appendingPathComponent(markenname, isDirectory: false)
    }

    nonisolated static func zwilling(_ name: String, in ordner: URL) -> URL {
        ordner.appendingPathComponent(name + zwillingssuffix, isDirectory: false)
    }

    nonisolated static func vorgaenger(_ name: String, in ordner: URL) -> URL {
        ordner.appendingPathComponent(name + vorgaengersuffix, isDirectory: false)
    }

    nonisolated static func sha256(_ daten: Data) -> String {
        SHA256.hash(data: daten).map { String(format: "%02x", $0) }.joined()
    }

    /// Eine Datei und ihren Verzeichniseintrag auf die Platte zwingen (E64).
    ///
    /// `write(options: .atomic)` schreibt in eine Nebendatei und benennt um.
    /// Das überlebt den Tod des Prozesses, nicht aber einen Stromausfall: Der
    /// Verzeichniseintrag kann vor den Daten liegen. Der Übergabestand sagt
    /// zu, dass von der Marke an der neue Stand gilt — diese Zusage hält nur,
    /// wenn Zwillinge und Marke wirklich auf dem Medium stehen, bevor der
    /// nächste Schritt beginnt. Nur dort, nicht bei jeder Sicherung: Ein
    /// erzwungenes Schreiben kostet Zeit, und ein Übergang ist selten.
    nonisolated static func aufDiePlatteZwingen(_ url: URL) throws {
        try zwingen(url.path, name: url.lastPathComponent)
        let ordner = url.deletingLastPathComponent()
        try zwingen(ordner.path, name: ordner.lastPathComponent)
    }

    nonisolated private static func zwingen(_ pfad: String, name: String) throws {
        let griff = Darwin.open(pfad, O_RDONLY | O_CLOEXEC)
        guard griff >= 0 else {
            throw Uebergangsfehler(text: "„\(name)“ ließ sich zum Sichern nicht öffnen "
                                   + "(\(String(cString: strerror(errno))))")
        }
        defer { Darwin.close(griff) }
        if fcntl(griff, F_FULLFSYNC) == -1 {
            // Wo das Dateisystem das Durchschreiben nicht kennt, bleibt fsync.
            let ersterFehler = errno
            let ersatz = (ersterFehler == ENOTSUP || ersterFehler == EINVAL) && Darwin.fsync(griff) == 0
            guard ersatz else {
                throw Uebergangsfehler(text: "„\(name)“ ließ sich nicht auf die Platte zwingen "
                                       + "(\(String(cString: strerror(ersterFehler))))")
            }
        }
    }

    /// Ein Name der Generation: eine Datei im Ordner, nicht die Marke, kein
    /// Zwilling, kein Vorgänger.
    nonisolated static func nameZulaessig(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
            && name != markenname && !name.hasSuffix(zwillingssuffix) && !name.hasSuffix(vorgaengersuffix)
    }

    /// Der Prüfstand `--uebergangstest` bricht nach diesem Schritt hart ab —
    /// nur mit `UEBERGANG_ABBRUCH` und hinter der Schranke (`PLANUNGSORDNER`).
    nonisolated static func abbruchFallsVerlangt(nach schritt: Schritt) {
        guard Ablage.istPruefstand,
              ProcessInfo.processInfo.environment["UEBERGANG_ABBRUCH"] == schritt.rawValue else { return }
        print("UEBERGANG_ABBRUCH: harter Abbruch nach „\(schritt.rawValue)“")
        fflush(stdout)
        exit(3)
    }

    // ── Vorbereiten ───────────────────────────────────────────────────────

    /// Je Datei den Zwilling schreiben und zurücklesen. `kennung` ist die des
    /// neuen Schlüssels, `nil` heißt Klartext. Liefert den Grund, wenn es
    /// nicht ging — dann liegt kein Zwilling mehr, nichts hat sich geändert.
    func vorbereiten(_ art: Uebergangsart, kennung: Data?, stempel: String,
                     dateien: [String: Inhalt]) -> String? {
        let verwaltung = FileManager.default
        guard !istUebergeben, !verwaltung.fileExists(atPath: marke.path) else {
            return "ein früherer Übergang ist nicht abgeschlossen — bitte die App neu starten"
        }
        guard laufend == nil else { return "ein Übergang ist schon in Vorbereitung" }
        guard !dateien.isEmpty else { return "nichts zu übergeben" }
        var eintraege: [Uebergangsmarke.Eintrag] = []
        var geschrieben: [URL] = []
        do {
            try verwaltung.createDirectory(at: ordner, withIntermediateDirectories: true)
            for name in dateien.keys.sorted() {
                guard Uebergangsdienst.nameZulaessig(name) else {
                    throw Uebergangsfehler(text: "„\(name)“ ist kein Name für die Generation")
                }
                let original = ordner.appendingPathComponent(name, isDirectory: false)
                var istOrdner: ObjCBool = false
                let vorhanden = verwaltung.fileExists(atPath: original.path, isDirectory: &istOrdner)
                if vorhanden {
                    guard !istOrdner.boolValue else {
                        throw Uebergangsfehler(text: "an der Stelle von „\(name)“ liegt ein Ordner")
                    }
                    // Was sich nicht zum Schreiben öffnen lässt (unveränderbar, fremdes
                    // Recht), ließe sich nach der Marke nicht ersetzen — besser jetzt.
                    let griff = Darwin.open(original.path, O_WRONLY | O_CLOEXEC)
                    guard griff >= 0 else {
                        throw Uebergangsfehler(text: "„\(name)“ lässt sich nicht ersetzen (\(String(cString: strerror(errno))))")
                    }
                    Darwin.close(griff)
                }
                switch dateien[name]! {
                case .entfernen:
                    eintraege.append(.init(name: name, sha256: nil, vorhanden: vorhanden))
                case .daten(let daten):
                    let zwilling = Uebergangsdienst.zwilling(name, in: ordner)
                    try daten.write(to: zwilling, options: [.atomic])
                    geschrieben.append(zwilling)
                    guard try Data(contentsOf: zwilling) == daten else {
                        throw Uebergangsfehler(text: "der Zwilling von „\(name)“ liest sich anders, als er geschrieben wurde")
                    }
                    // Erst wenn er auf der Platte steht, darf die Marke von ihm
                    // sprechen (E64).
                    try Uebergangsdienst.aufDiePlatteZwingen(zwilling)
                    eintraege.append(.init(name: name, sha256: Uebergangsdienst.sha256(daten), vorhanden: vorhanden))
                }
            }
        } catch {
            for zwilling in geschrieben { try? verwaltung.removeItem(at: zwilling) }
            return error.localizedDescription
        }
        laufend = Uebergangsmarke(art: art, stempel: stempel, kennung: kennung?.hex ?? "", dateien: eintraege)
        istUebergeben = false
        haken?(.vorbereitet)
        Uebergangsdienst.abbruchFallsVerlangt(nach: .vorbereitet)
        return nil
    }

    // ── Übergeben ─────────────────────────────────────────────────────────

    /// Die Marke atomar schreiben und zurücklesen — der eine Moment. Liefert
    /// den Grund, wenn es nicht ging; dann liegt keine Marke, die Zwillinge
    /// bleiben für `verwerfen()`.
    func uebergeben() -> String? {
        guard let laufend else { return "keine Generation vorbereitet" }
        guard !istUebergeben else { return nil }
        do {
            let codierer = JSONEncoder()
            codierer.outputFormatting = [.sortedKeys]
            try codierer.encode(laufend).write(to: marke, options: [.atomic])
            guard try JSONDecoder().decode(Uebergangsmarke.self, from: try Data(contentsOf: marke)) == laufend else {
                throw Uebergangsfehler(text: "die Marke liest sich anders, als sie geschrieben wurde")
            }
            // Der eine Moment gilt erst, wenn er auch einen Stromausfall
            // übersteht (E64).
            try Uebergangsdienst.aufDiePlatteZwingen(marke)
        } catch {
            try? FileManager.default.removeItem(at: marke)
            return error.localizedDescription
        }
        istUebergeben = true
        haken?(.uebergeben)
        Uebergangsdienst.abbruchFallsVerlangt(nach: .uebergeben)
        return nil
    }

    // ── Einsetzen ─────────────────────────────────────────────────────────

    enum Einsetzbefund: Equatable, Sendable {
        /// Jede Datei getauscht, die Marke fort.
        case vollendet
        /// Nicht jede Datei getauscht — die Marke bleibt liegen, der nächste
        /// Start vollendet.
        case unvollendet(String)
    }

    /// Jeden Zwilling atomar über sein Original, dann die Marke fort. Bleibt
    /// es unvollendet, bleibt die Generation in Arbeit — bis ein Schreibanlass
    /// sie nachholt (`einsetzenErneut`, dann `abgeschlossen()`) oder der
    /// nächste Start sie vollendet.
    func einsetzen() -> Einsetzbefund {
        guard let laufend, istUebergeben else { return .unvollendet("keine übergebene Generation") }
        var erster = true
        let befund = Uebergangsdienst.einsetzen(laufend, in: ordner, nachTausch: {
            self.haken?(.einsetzen)
            if erster {
                erster = false
                Uebergangsdienst.abbruchFallsVerlangt(nach: .einsetzen)
            }
        }, nachAufraeumen: {
            self.haken?(.aufgeraeumt)
            Uebergangsdienst.abbruchFallsVerlangt(nach: .aufgeraeumt)
        })
        if befund == .vollendet { abgeschlossen() }
        return befund
    }

    /// Das Einsetzen ist vollendet — hier oder nachgeholt von einem
    /// Schreibanlass: keine Generation mehr in Arbeit.
    func abgeschlossen() {
        laufend = nil
        istUebergeben = false
    }

    /// Ein unvollendetes Einsetzen noch einmal — von jedem Schreibanlass aus,
    /// auch abseits des Hauptstrangs (E54): wiederholbar, weil ein schon
    /// getauschter Eintrag als erledigt gilt. Ohne Haken.
    nonisolated static func einsetzenErneut(_ marke: Uebergangsmarke, in ordner: URL) -> Einsetzbefund {
        einsetzen(marke, in: ordner)
    }

    /// Der eine Weg vom Zwilling zum Original — im Übergang, beim Nachholen
    /// und beim Wiederanlauf derselbe. Jedes ersetzte Original bleibt als
    /// Vorgänger liegen, Entfernen ist ein Umbenennen auf den Vorgänger; erst
    /// nach der Marke sind die Vorgänger fort (E53). Ein schon getauschter
    /// Eintrag (das Original trägt die Prüfsumme, kein Zwilling mehr) ist
    /// erledigt: Einsetzen ist wiederholbar. `nachTausch` ist der Haken des
    /// Übergangs (Prüfung, Abbruchmarke), nach jedem Eintrag; Nachholen und
    /// Wiederanlauf haben keinen.
    nonisolated private static func einsetzen(_ marke: Uebergangsmarke, in ordner: URL,
                                              nachTausch: (() -> Void)? = nil,
                                              nachAufraeumen: (() -> Void)? = nil) -> Einsetzbefund {
        let verwaltung = FileManager.default
        var fehler: [String] = []
        for eintrag in marke.dateien {
            let original = ordner.appendingPathComponent(eintrag.name, isDirectory: false)
            let zwilling = Uebergangsdienst.zwilling(eintrag.name, in: ordner)
            let vorgaenger = Uebergangsdienst.vorgaenger(eintrag.name, in: ordner)
            do {
                if let sha256 = eintrag.sha256 {
                    if verwaltung.fileExists(atPath: zwilling.path) {
                        // Vor dem Tausch: Der Zwilling ist der, von dem die
                        // Marke spricht — eine reguläre Datei unter der
                        // Lesedecke mit seiner Prüfsumme. Zwischen Vorbereiten
                        // und Einsetzen kann eine Wiederherstellung, ein
                        // Abgleichdienst oder ein Datenträgerfehler ihn
                        // verändert haben; der Wiederanlauf prüfte das, das
                        // Nachholen im Lauf nicht (N52-02, E61).
                        guard pruefsumme(zwilling) == sha256 else {
                            throw Uebergangsfehler(text: "der Zwilling von „\(eintrag.name)“ weicht von der Marke ab")
                        }
                        if verwaltung.fileExists(atPath: original.path) {
                            _ = try verwaltung.replaceItemAt(original, withItemAt: zwilling,
                                                             backupItemName: vorgaenger.lastPathComponent,
                                                             options: [.withoutDeletingBackupItem])
                        } else {
                            try verwaltung.moveItem(at: zwilling, to: original)
                        }
                        // Und nach dem Tausch: Was jetzt liegt, ist es auch.
                        // Erst danach darf der Vorgänger fallen (E61).
                        guard pruefsumme(original) == sha256 else {
                            throw Uebergangsfehler(text: "„\(eintrag.name)“ liest sich nach dem Tausch anders als die Marke")
                        }
                    } else if pruefsumme(original) != sha256 {
                        throw Uebergangsfehler(text: "der Zwilling von „\(eintrag.name)“ fehlt")
                    }
                } else if verwaltung.fileExists(atPath: original.path) {
                    try? verwaltung.removeItem(at: vorgaenger)
                    try verwaltung.moveItem(at: original, to: vorgaenger)
                }
                nachTausch?()
            } catch {
                fehler.append("\(eintrag.name): \(error.localizedDescription)")
            }
        }
        guard fehler.isEmpty else { return .unvollendet(fehler.joined(separator: "; ")) }
        // Erst die Vorgänger, dann die Marke (E60): Danach kann „keine Marke,
        // aber ein Vorgänger“ nicht mehr aus einem sauberen Abschluss stammen —
        // und der nächste Start muss einen liegenden Vorgänger nicht mehr für
        // Abfall halten. Geht einer nicht fort, bleibt die Marke liegen; das
        // Einsetzen ist wiederholbar, der nächste Anlass räumt zu Ende.
        var reste: [String] = []
        for eintrag in marke.dateien {
            let vorgaenger = Uebergangsdienst.vorgaenger(eintrag.name, in: ordner)
            guard verwaltung.fileExists(atPath: vorgaenger.path) else { continue }
            do { try verwaltung.removeItem(at: vorgaenger) }
            catch { reste.append("\(eintrag.name): \(error.localizedDescription)") }
        }
        guard reste.isEmpty else {
            return .unvollendet("die Vorgänger ließen sich nicht entfernen (" + reste.joined(separator: "; ") + ")")
        }
        nachAufraeumen?()
        do {
            try verwaltung.removeItem(at: Uebergangsdienst.marke(in: ordner))
        } catch {
            return .unvollendet("die Marke ließ sich nicht entfernen (\(error.localizedDescription))")
        }
        return .vollendet
    }

    /// Die Prüfsumme einer Datei, gebunden gelesen — `nil`, wenn sie nicht
    /// liegt oder sich nicht lesen lässt.
    nonisolated private static func pruefsumme(_ url: URL) -> String? {
        guard case .daten(let roh) = Ablage.gebundenLesen(url, hoechstens: Sicherungsdienst.lesedecke) else {
            return nil
        }
        return sha256(roh)
    }

    // ── Verwerfen ─────────────────────────────────────────────────────────

    /// Vor der Marke: die Zwillinge fort, nichts hat sich geändert. Nach der
    /// Marke gilt der neue Stand — dann tut dies nichts.
    func verwerfen() {
        guard let laufend, !istUebergeben else { return }
        let verwaltung = FileManager.default
        for eintrag in laufend.dateien where eintrag.sha256 != nil {
            try? verwaltung.removeItem(at: Uebergangsdienst.zwilling(eintrag.name, in: ordner))
        }
        self.laufend = nil
    }

    // ── Wiederanlauf ──────────────────────────────────────────────────────

    enum Wiederanlaufbefund: Equatable, Sendable {
        /// Weder Marke noch Zwillinge.
        case nichts
        /// Die Marke lag, die Zwillinge trugen ihre Prüfsummen: eingesetzt.
        case vollendet(Uebergangsart)
        /// Zwillinge ohne Marke — Kopien eines Stands, der nie galt: entfernt.
        case verworfen(Int)
        /// Vorgänger ohne Marke: Seit E60 stammen sie aus keinem sauberen
        /// Abschluss. Sie sind gestempelt ins Register gegangen, nicht in den
        /// Papierkorb — der Stand auf der Platte bleibt, wie er ist.
        case vorgaengerVerwahrt([String])
        /// Die Marke lag, ein Zwilling fehlte oder wich ab — und ein Teil der
        /// Dateien trug schon den neuen Stand: Über die Vorgänger ist der alte
        /// wiederhergestellt. Marke und Zwillinge liegen unter `rettung`.
        case zurueckgenommen(Uebergangsart?, grund: String, rettung: [String])
        /// Die Marke lag, aber ein Zwilling fehlt oder weicht ab (oder die
        /// Marke ist nicht lesbar) — eingesetzt war nichts: Der alte Stand
        /// stand ohnehin; Marke und Zwillinge liegen unter `rettung`.
        case beiseitegelegt(Uebergangsart?, grund: String, rettung: [String])
        /// Die Marke lässt sich nicht deuten, und ein Vorgänger liegt: Welche
        /// Dateien zur Generation gehören, ist unbekannt, ein Teil kann schon
        /// den neuen Stand tragen. Es wird nichts angerührt und nichts geladen
        /// (E59).
        case blockiert(Uebergangsart?, String)
        /// Nichts ließ sich einsetzen oder beiseitelegen: Alles bleibt liegen
        /// bis zum nächsten Start.
        case gesperrt(Uebergangsart?, String)
        /// Weder zu vollenden noch zurückzunehmen: Ein Teil der Dateien trägt
        /// schon den neuen Stand, und ein Vorgänger fehlt (oder der Rückweg
        /// scheiterte). Alles bleibt liegen — zwei Stände, von Hand zu prüfen.
        case gemischt(Uebergangsart?, String)
    }

    /// Beim Start, vor dem Lesen der Ablage.
    func wiederanlaufen(stempel: String) -> Wiederanlaufbefund {
        Uebergangsdienst.wiederanlaufen(ordner: ordner, stempel: stempel)
    }

    /// Ohne Schlüssel, allein über die Dateien: eine Marke vollenden, Zwillinge
    /// ohne Marke entfernen. Was nicht zu vollenden ist, geht über die
    /// Vorgänger zurück und kommt beiseite — benannt mit dem Stempel.
    nonisolated static func wiederanlaufen(ordner: URL, stempel: String) -> Wiederanlaufbefund {
        let verwaltung = FileManager.default
        let gelesen: Uebergangsmarke
        switch Ablage.gebundenLesen(marke(in: ordner), hoechstens: markeHoechstens) {
        case .keine:
            // Ohne Marke sind Zwillinge Kopien eines Stands, der nie galt: fort
            // mit ihnen. Vorgänger dagegen sind kein Abfall — seit E60 räumt
            // das Einsetzen sie vor der Marke fort, also stammt keiner mehr aus
            // einem sauberen Abschluss. Was hier liegt, kann der einzige Weg
            // zurück sein und geht gestempelt ins Register (N52-01).
            let zwillinge = liegendeZwillinge(in: ordner)
            let vorgaengerdateien = liegende(mit: vorgaengersuffix, in: ordner)
            guard !zwillinge.isEmpty || !vorgaengerdateien.isEmpty else { return .nichts }
            var uebrig: [String] = []
            for datei in zwillinge {
                do { try verwaltung.removeItem(at: datei) } catch { uebrig.append(datei.lastPathComponent) }
            }
            var verwahrt: [String] = []
            for datei in vorgaengerdateien {
                let name = rettungsname(datei.lastPathComponent, kennzeichen: "vorgaenger", stempel: stempel)
                let ziel = ordner.appendingPathComponent(name, isDirectory: false)
                try? verwaltung.removeItem(at: ziel)
                do {
                    try verwaltung.moveItem(at: datei, to: ziel)
                    verwahrt.append(name)
                } catch {
                    uebrig.append(datei.lastPathComponent)
                }
            }
            guard uebrig.isEmpty else {
                return .gesperrt(nil, "Zwillinge oder Vorgänger ohne Marke ließen sich nicht wegräumen: " + uebrig.joined(separator: ", "))
            }
            if !verwahrt.isEmpty { return .vorgaengerVerwahrt(verwahrt) }
            return zwillinge.isEmpty ? .nichts : .verworfen(zwillinge.count)
        case .zuGross(let groesse):
            return unbrauchbareMarke(grund: "die Marke ist ungewöhnlich groß (\(groesse / 1024) KB)",
                                     stempel: stempel, in: ordner)
        case .unlesbar(let fehler):
            return .gesperrt(nil, "die Marke ließ sich nicht lesen (\(fehler.localizedDescription))")
        case .daten(let roh):
            do {
                let marke = try JSONDecoder().decode(Uebergangsmarke.self, from: roh)
                guard marke.gueltig else {
                    throw Uebergangsfehler(text: "unbekannte Art oder Fassung, oder ein Eintrag ist kein Name der Generation")
                }
                gelesen = marke
            } catch {
                return unbrauchbareMarke(grund: "die Marke ist nicht lesbar (\(error.localizedDescription))",
                                         stempel: stempel, in: ordner)
            }
        }
        // Je Eintrag: eingesetzt (das Original trägt schon den neuen Stand),
        // ausstehend (der Zwilling liegt und stimmt) oder mangelhaft.
        var eingesetzt: [Uebergangsmarke.Eintrag] = []
        var maengel: [String] = []
        for eintrag in gelesen.dateien {
            let original = ordner.appendingPathComponent(eintrag.name, isDirectory: false)
            if let sha256 = eintrag.sha256 {
                let zwilling = zwilling(eintrag.name, in: ordner)
                if verwaltung.fileExists(atPath: zwilling.path) {
                    if pruefsumme(zwilling) != sha256 { maengel.append("„\(eintrag.name)“ weicht ab") }
                } else if pruefsumme(original) == sha256 {
                    eingesetzt.append(eintrag)
                } else {
                    maengel.append("„\(eintrag.name)“ fehlt")
                }
            } else if !verwaltung.fileExists(atPath: original.path) {
                eingesetzt.append(eintrag)
            }
        }
        guard maengel.isEmpty else {
            return rueckweg(gelesen, eingesetzt: eingesetzt, grund: maengel.joined(separator: ", "),
                            stempel: stempel, in: ordner)
        }
        switch einsetzen(gelesen, in: ordner) {
        case .vollendet:
            // Was daneben noch als Zwilling oder Vorgänger liegt, gehört zu keiner Marke mehr.
            for datei in liegendeZwillinge(in: ordner) + liegende(mit: vorgaengersuffix, in: ordner) {
                try? verwaltung.removeItem(at: datei)
            }
            return .vollendet(gelesen.art)
        case .unvollendet(let grund):
            return .gesperrt(gelesen.art, grund)
        }
    }

    /// Der Rückweg (E53): Was schon den neuen Stand trägt, kommt aus seinem
    /// Vorgänger zurück, eine neu angelegte Datei geht fort — erst geprüft,
    /// dann getan: Fehlt ein Vorgänger, wird nichts angerührt. Danach Marke
    /// und Zwillinge beiseite — der alte Stand gilt dann wirklich.
    nonisolated private static func rueckweg(_ marke: Uebergangsmarke, eingesetzt: [Uebergangsmarke.Eintrag],
                                             grund: String, stempel: String, in ordner: URL) -> Wiederanlaufbefund {
        let verwaltung = FileManager.default
        // Was zurückzustellen ist, sagt die Platte, nicht die Einstufung: Ein
        // Vorgänger liegt genau dort, wo das Einsetzen ein Original ersetzt
        // oder entfernt hat — auch wenn die eingesetzte Datei inzwischen
        // beschädigt ist und deshalb als „fehlt“ gilt (N52-01).
        let mitVorgaenger = Set(marke.dateien.map(\.name).filter {
            verwaltung.fileExists(atPath: vorgaenger($0, in: ordner).path)
        })
        // Eingesetzt, vorher lag etwas, und kein Vorgänger: kein Rückweg.
        let ohneVorgaenger = eingesetzt.filter { $0.vorhanden && !mitVorgaenger.contains($0.name) }
            .map { "„\($0.name)“" }
        guard ohneVorgaenger.isEmpty else {
            return .gemischt(marke.art, grund + "; " + eingesetzt.map { "„\($0.name)“" }.joined(separator: ", ")
                             + (eingesetzt.count == 1 ? " trägt" : " tragen") + " schon den neuen Stand, ohne Vorgänger: "
                             + ohneVorgaenger.joined(separator: ", "))
        }
        // Neu angelegt heißt: Der Rückweg löscht. Gelöscht wird aber nur, was
        // aus dieser Generation stammt — liegt an der Stelle etwas anderes, hat
        // es eine fremde Hand dorthin gelegt, und der Rückweg endet hier (R2).
        let fremdAngelegt = marke.dateien.filter { eintrag in
            guard !eintrag.vorhanden, let sha256 = eintrag.sha256, !mitVorgaenger.contains(eintrag.name) else { return false }
            let original = ordner.appendingPathComponent(eintrag.name, isDirectory: false)
            guard verwaltung.fileExists(atPath: original.path) else { return false }
            return pruefsumme(original) != sha256
        }.map { "„\($0.name)“" }
        guard fremdAngelegt.isEmpty else {
            return .gemischt(marke.art, grund + "; an der Stelle von " + fremdAngelegt.joined(separator: ", ")
                             + " lag vor dem Übergang nichts, und was dort liegt, stammt nicht aus dieser Generation")
        }
        var fehler: [String] = []
        var zurueckgestellt = 0
        for eintrag in marke.dateien {
            let original = ordner.appendingPathComponent(eintrag.name, isDirectory: false)
            let vorgaengerdatei = vorgaenger(eintrag.name, in: ordner)
            do {
                if mitVorgaenger.contains(eintrag.name) {
                    if verwaltung.fileExists(atPath: original.path) {
                        _ = try verwaltung.replaceItemAt(original, withItemAt: vorgaengerdatei)
                    } else {
                        try verwaltung.moveItem(at: vorgaengerdatei, to: original)
                    }
                    zurueckgestellt += 1
                } else if !eintrag.vorhanden, let sha256 = eintrag.sha256,
                          verwaltung.fileExists(atPath: original.path), pruefsumme(original) == sha256 {
                    // Vor dem Übergang lag nichts, und was liegt, ist unseres:
                    // Die neue Datei geht fort.
                    try verwaltung.removeItem(at: original)
                    zurueckgestellt += 1
                }
            } catch {
                fehler.append("„\(eintrag.name)“: \(error.localizedDescription)")
            }
        }
        guard fehler.isEmpty else {
            return .gemischt(marke.art, grund + "; der Rückweg scheiterte: " + fehler.joined(separator: ", "))
        }
        return beiseitelegen(marke.art, grund: grund, zwillinge: liegendeZwillinge(in: ordner), stempel: stempel,
                             in: ordner, zurueckgenommen: zurueckgestellt > 0)
    }

    /// Eine Marke, die sich nicht deuten lässt: Welche Dateien zur Generation
    /// gehören, ist damit unbekannt. Liegt ein Vorgänger, kann ein Teil des
    /// neuen Stands schon auf der Platte stehen — dann wird nichts angerührt,
    /// und es wird nichts geladen (E59). Liegt keiner, war nichts eingesetzt:
    /// Marke und Zwillinge gehen ins Register, der bisherige Stand gilt.
    nonisolated private static func unbrauchbareMarke(grund: String, stempel: String,
                                                      in ordner: URL) -> Wiederanlaufbefund {
        let vorgaengerdateien = liegende(mit: vorgaengersuffix, in: ordner)
        guard vorgaengerdateien.isEmpty else {
            let namen = vorgaengerdateien.map { "„\($0.lastPathComponent)“" }.joined(separator: ", ")
            return .blockiert(nil, grund + "; " + namen + (vorgaengerdateien.count == 1 ? " liegt" : " liegen")
                              + " als Vorgänger: Ein Teil der Dateien kann schon den neuen Stand tragen")
        }
        return beiseitelegen(nil, grund: grund, zwillinge: liegendeZwillinge(in: ordner), stempel: stempel, in: ordner)
    }

    nonisolated private static func liegendeZwillinge(in ordner: URL) -> [URL] {
        liegende(mit: zwillingssuffix, in: ordner)
    }

    nonisolated private static func liegende(mit suffix: String, in ordner: URL) -> [URL] {
        let namen = (try? FileManager.default.contentsOfDirectory(atPath: ordner.path)) ?? []
        return namen.filter { $0.hasSuffix(suffix) }.sorted()
            .map { ordner.appendingPathComponent($0, isDirectory: false) }
    }

    /// Der Name der Rettungskopie eines Zwillings: `planung.json.uebergang`
    /// → `planung-uebergang-<Stempel>.json` — im Register der Ablage, damit
    /// sie jeden weiteren Wechsel des Schutzes mitgeht.
    nonisolated static func rettungsname(zwilling: String, stempel: String) -> String {
        rettungsname(zwilling, kennzeichen: "uebergang", stempel: stempel)
    }

    /// Derselbe Weg für den Vorgänger: `planung.json.vorgaenger`
    /// → `planung-vorgaenger-<Stempel>.json` (E60).
    nonisolated static func rettungsname(_ datei: String, kennzeichen: String, stempel: String) -> String {
        var name = datei
        for suffix in [zwillingssuffix, vorgaengersuffix] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        if name.hasSuffix(".json") {
            name.removeLast(".json".count)
            return "\(name)-\(kennzeichen)-\(stempel).json"
        }
        return "\(name)-\(kennzeichen)-\(stempel)"
    }

    /// Marke und Zwillinge unter Stempelnamen beiseite — der alte Stand bleibt.
    nonisolated private static func beiseitelegen(_ art: Uebergangsart?, grund: String, zwillinge: [URL],
                                                  stempel: String, in ordner: URL,
                                                  zurueckgenommen: Bool = false) -> Wiederanlaufbefund {
        let verwaltung = FileManager.default
        var rettung: [String] = []
        var uebrig: [String] = []
        let ziele = [(marke(in: ordner), "uebergang-\(stempel).json")]
            + zwillinge.map { ($0, rettungsname(zwilling: $0.lastPathComponent, stempel: stempel)) }
        for (quelle, name) in ziele {
            let ziel = ordner.appendingPathComponent(name, isDirectory: false)
            try? verwaltung.removeItem(at: ziel)
            do {
                try verwaltung.moveItem(at: quelle, to: ziel)
                rettung.append(name)
            } catch {
                uebrig.append(quelle.lastPathComponent)
            }
        }
        guard uebrig.isEmpty else {
            return .gesperrt(art, grund + "; nicht beiseitezulegen: " + uebrig.joined(separator: ", "))
        }
        return zurueckgenommen ? .zurueckgenommen(art, grund: grund, rettung: rettung)
                               : .beiseitegelegt(art, grund: grund, rettung: rettung)
    }
}
