// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Der Stand aus der Ansichtsfassung fürs iPad: was abgehakt und was
/// kommentiert wurde.
///
/// **Eine eigene Datei neben der Planung, kein zweiter Planungsstand.** Die
/// Ansicht legt nur ihre beiden Angaben ab, je Vorhaben unter dessen Kennung;
/// alles Übrige bleibt Sache der App.
struct Statusstand: Sendable, Equatable {
    struct Eintrag: Sendable, Equatable {
        var erledigt: Bool
        var kommentar: String
        /// Wann die Ansicht diesen Eintrag zuletzt angefasst hat. Leer nur bei
        /// Dateien aus der Zeit vor diesem Feld; dann gilt `gespeichert`.
        var geaendert: String = ""
    }

    /// Wie in der Planungsdatei (`new Date().toISOString()`).
    var gespeichert: String
    /// Reine Durchreichung: Die Ansicht schreibt den Titel hinein, die App
    /// liest ihn und legt ihn unverändert wieder ab. Weder angezeigt noch
    /// gegen die geöffnete Planung geprüft — eine fremde Statusdatei bleibt
    /// mangels übereinstimmender Vorhaben-Kennungen ohnehin wirkungslos.
    var planungstitel: String
    /// Nach Vorhaben-Kennung.
    var eintraege: [String: Eintrag]

    var abgehakt: Int { eintraege.values.count(where: \.erledigt) }
    var kommentiert: Int { eintraege.values.count { !$0.kommentar.isEmpty } }
}

/// Lesen und Schreiben von `current_status.json`.
///
/// Gelesen wird, was ein **Browser** geschrieben hat — also mit derselben
/// Vorsicht wie bei der Planungsdatei.
enum Statusdatei {
    static let name = "current_status.json"
    static let typ = "unterrichtsplanung-status"
    static let version = 1
    /// Obergrenze beim Lesen: Die Datei kommt über einen Ordner herein, in den
    /// auch anderes geraten kann.
    static let hoechstgroesse = 8 * 1024 * 1024

    // ── Lesen ─────────────────────────────────────────────────────────────

    static func lesen(_ daten: Data) throws -> Statusstand {
        let roh: Any
        do {
            roh = try JSONSerialization.jsonObject(with: daten, options: [])
        } catch {
            throw Planungsfehler(text: "Die Statusdatei ist kein lesbares JSON.")
        }
        guard let d = roh as? [String: Any] else {
            throw Planungsfehler(text: "Die Statusdatei hat nicht die erwartete Form.")
        }
        let gefundenerTyp = text(d["typ"])
        if !gefundenerTyp.isEmpty, gefundenerTyp != typ {
            throw Planungsfehler(text: "Die Datei gehört zu einer anderen Anwendung.")
        }
        guard let rohEintraege = d["eintraege"] as? [String: Any] else {
            throw Planungsfehler(text: "Die Statusdatei enthält keine Einträge.")
        }

        var eintraege: [String: Statusstand.Eintrag] = [:]
        for (kennung, wert) in rohEintraege {
            guard !kennung.isEmpty, let e = wert as? [String: Any] else { continue }
            // Dieselbe Grenze wie im Planungsleser: Sonst nähme die Planung
            // über den Statusweg einen Kommentar auf, den sie beim nächsten
            // Start wieder kappt — derselbe Stand bedeutete vor und nach einem
            // Neustart Verschiedenes.
            let kommentar = text(e["kommentar"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Planungsdatei.maxTextlaenge)
            // Auch der leere Eintrag zählt: `erledigt: false` heißt „Haken entfernen“.
            eintraege[kennung] = Statusstand.Eintrag(
                erledigt: wahrheit(e["erledigt"]),
                kommentar: String(kommentar),
                geaendert: text(e["geaendert"]))
        }

        return Statusstand(gespeichert: text(d["gespeichert"]),
                           planungstitel: text(d["planungstitel"]),
                           eintraege: eintraege)
    }

    // ── Schreiben ─────────────────────────────────────────────────────────

    static func schreiben(_ stand: Statusstand) throws -> Data {
        let objekt: [String: Any] = [
            "typ": typ,
            "version": version,
            "gespeichert": stand.gespeichert,
            "planungstitel": stand.planungstitel,
            "eintraege": stand.eintraege.mapValues {
                ["erledigt": $0.erledigt, "kommentar": $0.kommentar,
                 "geaendert": $0.geaendert] as [String: Any]
            },
        ]
        return try JSONSerialization.data(withJSONObject: objekt,
                                          options: [.prettyPrinted, .sortedKeys,
                                                    .withoutEscapingSlashes])
    }

    // ── Hilfen ────────────────────────────────────────────────────────────

    // Dieselbe Eintragsform liest auch die Ansichtsfassung wieder ein
    // (`statusWiederaufnehmen`); beide Leser müssen sie gleich deuten. Darum
    // die Hilfen der Planungsdatei statt eigener, strengerer.
    private static func text(_ wert: Any?) -> String {
        Planungsdatei.text(wert)
    }

    private static func wahrheit(_ wert: Any?) -> Bool {
        Planungsdatei.wahrheit(wert)
    }
}
