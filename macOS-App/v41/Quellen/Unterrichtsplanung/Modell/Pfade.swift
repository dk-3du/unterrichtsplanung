// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Umgang mit Materialpfaden. Materialien werden **nie kopiert oder
/// verschoben**; hinterlegt wird ein Verweis — relativ zum Basisordner, sofern
/// die Datei darin liegt, sonst als vollständiger Pfad.
enum Pfade {

    /// Finder-Ablage, eingesetzter Pfad oder `file://`-Adresse → POSIX-Pfad.
    static func normalisieren(_ roh: String, basis: String) -> String {
        var p = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return "" }

        if p.lowercased().hasPrefix("file://") {
            if let url = URL(string: p), url.isFileURL {
                p = url.path
            } else {
                let ohneVorsatz = p.ersetzen(muster: #"^file://(localhost)?"#, durch: "")
                p = ohneVorsatz.removingPercentEncoding ?? ohneVorsatz
            }
        }

        if let erstes = p.first, erstes == "\"" || erstes == "'" { p.removeFirst() }
        if let letztes = p.last, letztes == "\"" || letztes == "'" { p.removeLast() }

        if p.hasPrefix("~/") || p == "~" {
            p = heimatOrdner(basis: basis) + String(p.dropFirst())
        }

        var gekuerzt = p
        while gekuerzt.count > 1, gekuerzt.hasSuffix("/") { gekuerzt.removeLast() }
        return gekuerzt.isEmpty ? p : gekuerzt
    }

    /// Der Heimatordner; der Basisordner hat Vorrang, falls dort ein anderes
    /// Benutzerverzeichnis steht (etwa auf einem übertragenen Rechner).
    static func heimatOrdner(basis: String) -> String {
        if let treffer = basis.range(of: #"^/Users/[^/]+"#, options: .regularExpression) {
            return String(basis[treffer])
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Innerhalb des Basisordners relativ speichern, außerhalb absolut.
    static func relativMachen(_ absoluterPfad: String, basis: String) -> String {
        let ordner = ohneEndschraegstrich(basis)
        guard !ordner.isEmpty else { return absoluterPfad }
        if absoluterPfad.hasPrefix(ordner + "/") {
            return String(absoluterPfad.dropFirst(ordner.count + 1))
        }
        if absoluterPfad == ordner { return "." }
        return absoluterPfad
    }

    static func vollerPfad(_ gespeichert: String, basis: String) -> String {
        if gespeichert.hasPrefix("/") { return gespeichert }
        let ordner = ohneEndschraegstrich(basis)
        return ordner.isEmpty ? gespeichert : ordner + "/" + gespeichert
    }

    static func dateiName(_ pfad: String) -> String {
        let teile = pfad.split(separator: "/", omittingEmptySubsequences: true)
        return teile.last.map(String.init) ?? pfad
    }

    static func istAbsolut(_ pfad: String) -> Bool { pfad.hasPrefix("/") }

    /// Nötig, weil ein `..` in einer eingelesenen Datei den Basisordner
    /// verlässt, ohne mit `/` zu beginnen — danach stimmt „↗ außerhalb“ wieder.
    static func zusammenfassen(_ gespeichert: String, basis: String) -> String {
        let voll = vollerPfad(gespeichert, basis: basis)
        guard voll.hasPrefix("/") else { return gespeichert }
        let eindeutig = URL(fileURLWithPath: voll).standardizedFileURL.path
        return relativMachen(eindeutig, basis: basis)
    }

    private static func ohneEndschraegstrich(_ pfad: String) -> String {
        var p = pfad
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p == "/" ? "" : p
    }
}

/// Prüfung der Weblinks. Die Adresse wird später geöffnet: Zugelassen sind
/// ausschließlich `http` und `https` — `file:`, `data:` und `javascript:`
/// bleiben draußen, auch beim Import.
enum Weblinks {

    static func pruefen(_ roh: String) -> String? {
        var text = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<") { text.removeFirst() }
        if text.hasSuffix(">") { text.removeLast() }
        // Tabulator und Zeilenumbrüche fallen heraus, wie im URL-Leser der
        // Browser: Prozentkodiert wären sie hier Teil des Pfades und dort
        // ersatzlos fort — dieselbe Adresse zeigte auf zwei Ziele.
        text.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" }
        if text.isEmpty { return nil }
        // Ein Gegenschrägstrich steht in keiner Adresse. Der Browser macht
        // daraus stillschweigend einen Schrägstrich; abzuweisen ist enger und
        // hält beide Fassungen beieinander.
        if text.contains("\\") { return nil }
        // Eine angebrochene Prozentfolge ist keine Adresse: Der Rückfall unten
        // machte aus „%zz“ ein „%25zz“ — eine andere Adresse als die, die die
        // Ansicht daraus liest.
        guard prozentfolgenGueltig(text) else { return nil }

        let schemaLaenge = schemaVorsatz(text)
        let istPort: Bool = {
            guard schemaLaenge > 0 else { return false }
            let rest = text.dropFirst(schemaLaenge)
            let ziffern = rest.prefix { $0.isASCII && $0.isNumber }
            guard !ziffern.isEmpty else { return false }
            let danach = rest.dropFirst(ziffern.count).first
            return danach == nil || danach == "/" || danach == "?" || danach == "#"
        }()
        let hatSchema = schemaLaenge > 0 && !istPort

        if !hatSchema {
            // Nur bei erkennbarem Rechnernamen — sonst wird jeder Vertipper zur Adresse.
            let ersterTeil = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
                .prefix { $0 != ":" }
            if !ersterTeil.contains("."), ersterTeil.lowercased() != "localhost" { return nil }
            text = "https://" + text
        }

        guard var teile = zerlegen(text),
              let schema = teile.scheme?.lowercased(),
              schema == "http" || schema == "https",
              let rechner = teile.host, !rechner.isEmpty
        else { return nil }
        // `URLComponents` nimmt jede Zahl als Anschluss an; über 65 535 gibt es
        // keinen. Die Ansicht weist solche Adressen ab — eine hier zugelassene
        // stünde in der Datei und fehlte dort samt Meldung „1 Link übergangen“.
        if let anschluss = teile.port, anschluss < 0 || anschluss > 65_535 { return nil }

        teile.scheme = schema
        teile.host = rechner.lowercased()
        if teile.path.isEmpty { teile.path = "/" }
        if (schema == "http" && teile.port == 80) || (schema == "https" && teile.port == 443) {
            teile.port = nil
        }
        return teile.string
    }

    /// Bei unerlaubten Zeichen — meist ein Leerzeichen aus einer Textzeile —
    /// ein zweiter Versuch mit kodierten Sonderzeichen, wie im Browser.
    private static func zerlegen(_ text: String) -> URLComponents? {
        if let teile = URLComponents(string: text) { return teile }
        guard let kodiert = text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        else { return nil }
        return URLComponents(string: kodiert)
    }

    /// Rechnername ohne „www.“ — die Beschriftung, wenn keine eigene gesetzt ist.
    static func name(_ adresse: String) -> String {
        guard let rechner = URLComponents(string: adresse)?.host else { return adresse }
        return rechner.hasPrefix("www.") ? String(rechner.dropFirst(4)) : rechner
    }

    /// `%` nur als Anfang einer zweistelligen Hexfolge — eine angebrochene
    /// Folge macht die Adresse ungültig. Genau die Prüfung wendet die Ansicht an.
    private static func prozentfolgenGueltig(_ text: String) -> Bool {
        let zeichen = Array(text)
        var stelle = 0
        while stelle < zeichen.count {
            guard zeichen[stelle] == "%" else {
                stelle += 1
                continue
            }
            guard stelle + 2 < zeichen.count,
                  zeichen[stelle + 1].isASCII, zeichen[stelle + 1].isHexDigit,
                  zeichen[stelle + 2].isASCII, zeichen[stelle + 2].isHexDigit
            else { return false }
            stelle += 3
        }
        return true
    }

    /// Länge des Schemavorsatzes einschließlich Doppelpunkt, 0 wenn keiner da ist.
    /// Entspricht `/^([a-z][a-z0-9+.\-]*):/i`.
    private static func schemaVorsatz(_ text: String) -> Int {
        var laenge = 0
        for zeichen in text {
            if laenge == 0 {
                guard zeichen.isASCII, zeichen.isLetter else { return 0 }
            } else if zeichen == ":" {
                return laenge + 1
            } else {
                let erlaubt = zeichen.isASCII && (zeichen.isLetter || zeichen.isNumber
                    || zeichen == "+" || zeichen == "." || zeichen == "-")
                guard erlaubt else { return 0 }
            }
            laenge += 1
        }
        return 0
    }
}
