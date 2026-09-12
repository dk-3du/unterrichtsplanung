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
/// Zwillings — oder dass die Datei entfällt. Kein Schlüsselmaterial.
struct Uebergangsmarke: Codable, Equatable, Sendable {
    static let typ = "unterrichtsplanung-uebergang"
    static let version = 1

    struct Eintrag: Codable, Equatable, Sendable {
        let name: String
        /// SHA-256 des Zwillings, hexadezimal; `nil`: Die Datei wird entfernt.
        let sha256: String?
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

    var gueltig: Bool { typ == Uebergangsmarke.typ && version == Uebergangsmarke.version }
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
/// Endet der Prozess vor der Marke, sind die Zwillinge Kopien eines Stands,
/// der nie galt: Der nächste Start entfernt sie (*verwerfen*). Endet er nach
/// der Marke, vollendet der nächste Start das Einsetzen über die Prüfsummen
/// der Marke — ohne Schlüssel (*wiederanlaufen*). Reine Dateilogik am
/// Ablageordner; was in die Zwillinge kommt, erzeugen die Dienste.
///
/// Einer je Sicherungsdienst, an dessen Ordner; `wiederanlaufen` läuft beim
/// Start vor dem ersten Lesen.
@MainActor
final class Uebergangsdienst {
    nonisolated static let markenname = "uebergang.json"
    nonisolated static let zwillingssuffix = ".uebergang"
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
    enum Schritt: String, Sendable { case vorbereitet, uebergeben, einsetzen }

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

    nonisolated static func sha256(_ daten: Data) -> String {
        SHA256.hash(data: daten).map { String(format: "%02x", $0) }.joined()
    }

    /// Ein Name der Generation: eine Datei im Ordner, nicht die Marke, kein Zwilling.
    nonisolated static func nameZulaessig(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
            && name != markenname && !name.hasSuffix(zwillingssuffix)
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
                if verwaltung.fileExists(atPath: original.path, isDirectory: &istOrdner) {
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
                    eintraege.append(.init(name: name, sha256: nil))
                case .daten(let daten):
                    let zwilling = Uebergangsdienst.zwilling(name, in: ordner)
                    try daten.write(to: zwilling, options: [.atomic])
                    geschrieben.append(zwilling)
                    guard try Data(contentsOf: zwilling) == daten else {
                        throw Uebergangsfehler(text: "der Zwilling von „\(name)“ liest sich anders, als er geschrieben wurde")
                    }
                    eintraege.append(.init(name: name, sha256: Uebergangsdienst.sha256(daten)))
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

    /// Jeden Zwilling atomar über sein Original, dann die Marke fort.
    func einsetzen() -> Einsetzbefund {
        guard let laufend, istUebergeben else { return .unvollendet("keine übergebene Generation") }
        let befund = Uebergangsdienst.einsetzen(laufend, in: ordner) {
            self.haken?(.einsetzen)
            Uebergangsdienst.abbruchFallsVerlangt(nach: .einsetzen)
        }
        if befund == .vollendet {
            self.laufend = nil
            istUebergeben = false
        }
        return befund
    }

    /// Der eine Weg vom Zwilling zum Original — im Übergang und beim
    /// Wiederanlauf derselbe. Ein schon getauschter Eintrag (das Original
    /// trägt die Prüfsumme, kein Zwilling mehr) ist erledigt: Einsetzen ist
    /// wiederholbar. `nachErstemTausch` ist der Haken des Übergangs (Prüfung,
    /// Abbruchmarke); der Wiederanlauf hat keinen.
    nonisolated private static func einsetzen(_ marke: Uebergangsmarke, in ordner: URL,
                                              nachErstemTausch: (() -> Void)? = nil) -> Einsetzbefund {
        let verwaltung = FileManager.default
        var fehler: [String] = []
        var ersterTausch = true
        for eintrag in marke.dateien {
            let original = ordner.appendingPathComponent(eintrag.name, isDirectory: false)
            let zwilling = Uebergangsdienst.zwilling(eintrag.name, in: ordner)
            do {
                if let sha256 = eintrag.sha256 {
                    if verwaltung.fileExists(atPath: zwilling.path) {
                        if verwaltung.fileExists(atPath: original.path) {
                            _ = try verwaltung.replaceItemAt(original, withItemAt: zwilling)
                        } else {
                            try verwaltung.moveItem(at: zwilling, to: original)
                        }
                    } else if pruefsumme(original) != sha256 {
                        throw Uebergangsfehler(text: "der Zwilling von „\(eintrag.name)“ fehlt")
                    }
                } else if verwaltung.fileExists(atPath: original.path) {
                    try verwaltung.removeItem(at: original)
                }
                if ersterTausch {
                    ersterTausch = false
                    nachErstemTausch?()
                }
            } catch {
                fehler.append("\(eintrag.name): \(error.localizedDescription)")
            }
        }
        guard fehler.isEmpty else { return .unvollendet(fehler.joined(separator: "; ")) }
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
        /// Die Marke lag, aber ein Zwilling fehlt oder weicht ab (oder die
        /// Marke ist nicht lesbar): Der alte Stand bleibt; Marke und Zwillinge
        /// liegen unter `rettung` im Ordner.
        case nichtVollendbar(Uebergangsart?, grund: String, rettung: [String])
        /// Nichts ließ sich einsetzen oder beiseitelegen: Alles bleibt liegen
        /// bis zum nächsten Start.
        case gesperrt(Uebergangsart?, String)
    }

    /// Beim Start, vor dem Lesen der Ablage.
    func wiederanlaufen(stempel: String) -> Wiederanlaufbefund {
        Uebergangsdienst.wiederanlaufen(ordner: ordner, stempel: stempel)
    }

    /// Ohne Schlüssel, allein über die Dateien: eine Marke vollenden, Zwillinge
    /// ohne Marke entfernen. Was nicht zu vollenden ist, kommt beiseite —
    /// benannt mit dem Stempel.
    nonisolated static func wiederanlaufen(ordner: URL, stempel: String) -> Wiederanlaufbefund {
        let verwaltung = FileManager.default
        let gelesen: Uebergangsmarke
        switch Ablage.gebundenLesen(marke(in: ordner), hoechstens: markeHoechstens) {
        case .keine:
            // Ohne Marke sind Zwillinge Kopien eines Stands, der nie galt.
            let zwillinge = liegendeZwillinge(in: ordner)
            guard !zwillinge.isEmpty else { return .nichts }
            var uebrig: [String] = []
            for zwilling in zwillinge {
                do { try verwaltung.removeItem(at: zwilling) } catch { uebrig.append(zwilling.lastPathComponent) }
            }
            guard uebrig.isEmpty else {
                return .gesperrt(nil, "Zwillinge ohne Marke ließen sich nicht entfernen: " + uebrig.joined(separator: ", "))
            }
            return .verworfen(zwillinge.count)
        case .zuGross(let groesse):
            return beiseitelegen(nil, grund: "die Marke ist ungewöhnlich groß (\(groesse / 1024) KB)",
                                 zwillinge: liegendeZwillinge(in: ordner), stempel: stempel, in: ordner)
        case .unlesbar(let fehler):
            return .gesperrt(nil, "die Marke ließ sich nicht lesen (\(fehler.localizedDescription))")
        case .daten(let roh):
            do {
                let marke = try JSONDecoder().decode(Uebergangsmarke.self, from: roh)
                guard marke.gueltig else { throw Uebergangsfehler(text: "unbekannte Art oder Fassung") }
                gelesen = marke
            } catch {
                return beiseitelegen(nil, grund: "die Marke ist nicht lesbar (\(error.localizedDescription))",
                                     zwillinge: liegendeZwillinge(in: ordner), stempel: stempel, in: ordner)
            }
        }
        var maengel: [String] = []
        for eintrag in gelesen.dateien {
            guard let sha256 = eintrag.sha256 else { continue }
            let zwilling = zwilling(eintrag.name, in: ordner)
            if verwaltung.fileExists(atPath: zwilling.path) {
                if pruefsumme(zwilling) != sha256 { maengel.append("„\(eintrag.name)“ weicht ab") }
            } else if pruefsumme(ordner.appendingPathComponent(eintrag.name, isDirectory: false)) != sha256 {
                maengel.append("„\(eintrag.name)“ fehlt")
            }
        }
        guard maengel.isEmpty else {
            return beiseitelegen(gelesen.art, grund: maengel.joined(separator: ", "),
                                 zwillinge: liegendeZwillinge(in: ordner), stempel: stempel, in: ordner)
        }
        switch einsetzen(gelesen, in: ordner) {
        case .vollendet:
            // Was daneben noch als Zwilling liegt, gehört zu keiner Marke mehr.
            for zwilling in liegendeZwillinge(in: ordner) { try? verwaltung.removeItem(at: zwilling) }
            return .vollendet(gelesen.art)
        case .unvollendet(let grund):
            return .gesperrt(gelesen.art, grund)
        }
    }

    nonisolated private static func liegendeZwillinge(in ordner: URL) -> [URL] {
        let namen = (try? FileManager.default.contentsOfDirectory(atPath: ordner.path)) ?? []
        return namen.filter { $0.hasSuffix(zwillingssuffix) }.sorted()
            .map { ordner.appendingPathComponent($0, isDirectory: false) }
    }

    /// Der Name der Rettungskopie eines Zwillings: `planung.json.uebergang`
    /// → `planung-uebergang-<Stempel>.json` — im Register der Ablage, damit
    /// sie jeden weiteren Wechsel des Schutzes mitgeht.
    nonisolated static func rettungsname(zwilling: String, stempel: String) -> String {
        var name = zwilling
        if name.hasSuffix(zwillingssuffix) { name.removeLast(zwillingssuffix.count) }
        if name.hasSuffix(".json") {
            name.removeLast(".json".count)
            return "\(name)-uebergang-\(stempel).json"
        }
        return "\(name)-uebergang-\(stempel)"
    }

    /// Marke und Zwillinge unter Stempelnamen beiseite — der alte Stand bleibt.
    nonisolated private static func beiseitelegen(_ art: Uebergangsart?, grund: String, zwillinge: [URL],
                                                  stempel: String, in ordner: URL) -> Wiederanlaufbefund {
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
        return .nichtVollendbar(art, grund: grund, rettung: rettung)
    }
}
