// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Der Abgleich mit der Statusdatei der iPad-Ansicht — ohne Datei und ohne
/// Speicher, damit er prüfbar ist: Die Datei liest der `Sicherungsdienst` im
/// Zielordner, gemeldet wird im Speicher. Hier steht, was drin ist, ob es
/// gilt, und was sich daraus an der Planung ändert.
enum Statusabgleich {

    /// Warum eine Statusdatei nicht eingelesen wird — mit dem Satz dazu.
    enum Hindernis: Error, Equatable {
        /// Klartext, obwohl die Ablage versiegelt ist — gilt nicht.
        case klartextNichtErlaubt
        case verschluesseltOhneTresor
        /// Ein Behälter mit anderem Inhalt.
        case keinStatus(String)
        case fremderSchluessel
        case nichtEntsiegelt(String)
        case unlesbar(String)

        var text: String {
            switch self {
            case .klartextNichtErlaubt:
                "Die Statusdatei aus der iPad-Ansicht ist unverschlüsselt, die Ablage auf "
                + "diesem Mac ist versiegelt — sie wurde nicht eingelesen. Bitte in der Ansicht "
                + "die aktuelle Kopie öffnen; ihr Status kommt dann versiegelt."
            case .verschluesseltOhneTresor:
                "Die Statusdatei aus der iPad-Ansicht ist verschlüsselt, die Ablage "
                + "auf diesem Mac ist es nicht — sie wurde nicht eingelesen."
            case .keinStatus(let inhalt):
                "Die Statusdatei aus der iPad-Ansicht ist ein Behälter mit Inhalt "
                + "„\(inhalt)“, kein Status — sie wurde nicht eingelesen."
            case .fremderSchluessel:
                "Die Statusdatei aus der iPad-Ansicht ist unter einem anderen Schlüssel "
                + "versiegelt und wurde nicht eingelesen — die Ansicht hat eine ältere "
                + "Kopie geöffnet."
            case .nichtEntsiegelt(let grund):
                "Die Statusdatei aus der iPad-Ansicht ließ sich nicht entsiegeln: "
                + "\(grund) Die Planung bleibt unverändert."
            case .unlesbar(let grund):
                "Die Statusdatei aus der iPad-Ansicht ließ sich nicht lesen: "
                + "\(grund) Die Planung bleibt unverändert."
            }
        }
    }

    /// Die Schranke vor dem Lesen: Bei versiegelter Ablage zählt nur ein
    /// Behälter unter dem eigenen Schlüssel, ohne Schlüssel nur Klartext. Ein
    /// Behälter unter fremdem Schlüssel wird benannt, nicht geraten. Was hier
    /// durchfällt, wird nicht gelesen — und am Schlüsselkopf ändert der
    /// Abgleich nichts: Er bewegt Haken, Kommentare und Stempel, sonst nichts.
    static func entsiegeln(_ roh: Data, tresor: Tresor?) throws(Hindernis) -> Data {
        guard Tresor.istBehaelter(roh) else {
            guard tresor == nil else { throw .klartextNichtErlaubt }
            return roh
        }
        guard let tresor else { throw .verschluesseltOhneTresor }
        let kopf: Behaelterkopf
        do { kopf = try Tresor.kopfLesen(roh) } catch { throw .nichtEntsiegelt(error.localizedDescription) }
        guard kopf.inhalt == Tresor.Inhalt.status.rawValue else { throw .keinStatus(kopf.inhalt) }
        do {
            return try tresor.oeffnen(kopf: kopf)
        } catch let fehler as Tresorfehler where fehler.art == .falscherSchluessel {
            throw .fremderSchluessel
        } catch {
            throw .nichtEntsiegelt(error.localizedDescription)
        }
    }

    static func lesen(_ daten: Data) throws(Hindernis) -> Statusstand {
        do { return try Statusdatei.lesen(daten) } catch { throw .unlesbar(error.localizedDescription) }
    }

    /// Der reine Abgleich, ohne Datei.
    ///
    /// **Der jüngere Stand gilt** — auch ein zurückgenommener Haken und ein
    /// geleerter Kommentar, sofern der Eintrag nach der letzten Änderung an
    /// dieser Planung entstand. Dieselbe Regel wendet die Ansicht in der
    /// Gegenrichtung an; ohne sie überschriebe ein liegengebliebener
    /// iPad-Stand neuere Eingaben am Mac. `geaendert` sagt, ob die Planung zu
    /// schreiben ist — auch wenn nur Stempel gesetzt wurden: Sie sind die
    /// Schranke gegen den älteren Stand eines zweiten Geräts.
    static func anwenden(_ stand: Statusstand, auf p: inout Planung,
                         jetzt: Date = Date()) -> (erledigt: Int, kommentare: Int, geaendert: Bool) {
        var haken = 0
        var notizen = 0
        var stempelGesetzt = false
        for stelle in p.eintraege.indices {
            guard let eintrag = stand.eintraege[p.eintraege[stelle].id] else { continue }
            // Ältere Dateien tragen den Stempel nur an der Datei, nicht am Eintrag.
            let stempel = eintrag.geaendert.isEmpty ? stand.gespeichert : eintrag.geaendert
            guard zeitstempelBrauchbar(stempel, jetzt: jetzt) else { continue }
            // Gegen den Stempel dieses Vorhabens, nicht gegen `planung.geaendert`:
            // sonst entwertete jede Mac-Änderung den ganzen Stand. Leer: nie angefasst.
            let hier = p.eintraege[stelle].statusGeaendert
            // Ein unbrauchbarer Stempel — aus einer falsch gestellten Uhr in die
            // Planungsdatei geraten — sperrte das Vorhaben sonst für immer.
            let schranke = zeitstempelBrauchbar(hier, jetzt: jetzt) ? hier : ""
            guard schranke.isEmpty || stempel > schranke else { continue }
            if p.eintraege[stelle].erledigt != eintrag.erledigt {
                p.eintraege[stelle].erledigt = eintrag.erledigt
                haken += 1
            }
            if p.eintraege[stelle].kommentar != eintrag.kommentar {
                p.eintraege[stelle].kommentar = eintrag.kommentar
                notizen += 1
            }
            // Sonst drehte eine später auftauchende ältere Statusdatei das zurück.
            if p.eintraege[stelle].statusGeaendert != stempel {
                p.eintraege[stelle].statusGeaendert = stempel
                stempelGesetzt = true
            }
        }
        return (haken, notizen, haken > 0 || notizen > 0 || stempelGesetzt)
    }

    /// Taugt der Zeitstempel als Schranke zwischen beiden Fassungen?
    ///
    /// Genau die Form von `toISOString()` — die Vergleiche in `anwenden`
    /// ordnen zeichenweise, und das trägt nur bei fester Stellenzahl in UTC —
    /// und nicht in der Zukunft, mit einer Minute Nachsicht für
    /// auseinanderlaufende Uhren. Ein Stand mit „2099-…“ aus einem Gerät mit
    /// falsch gestellter Uhr gewänne sonst für immer gegen jeden späteren.
    /// Dieselbe Regel wendet die Ansicht an (`zeitstempelBrauchbar`).
    static func zeitstempelBrauchbar(_ wert: String, jetzt: Date = Date()) -> Bool {
        let maske = "0000-00-00T00:00:00.000Z"
        guard wert.count == maske.count else { return false }
        for (zeichen, vorlage) in zip(wert, maske) {
            if vorlage == "0" {
                guard zeichen.isASCII, zeichen.isNumber else { return false }
            } else if zeichen != vorlage {
                return false
            }
        }
        // Die Felder selbst prüfen statt sie dem Datumsleser zu überlassen: Der
        // der App nimmt den 30. Februar an und rechnet ihn auf den 2. März
        // weiter, der des Browsers weist ihn ab — bei der Schaltsekunde
        // („…:59:60Z“) ist es umgekehrt. Ein Stempel, den nur eine Seite gelten
        // lässt, entscheidet denselben Abgleich hier und dort verschieden.
        let zeichen = Array(wert)
        func zahl(_ von: Int, _ bis: Int) -> Int { Int(String(zeichen[von..<bis])) ?? -1 }
        guard Tag(iso: String(wert.prefix(10))) != nil,
              zahl(11, 13) <= 23, zahl(14, 16) <= 59, zahl(17, 19) <= 59
        else { return false }
        guard let zeitpunkt = Zeitrechnung.zeitpunkt(aus: wert) else { return false }
        return zeitpunkt <= jetzt.addingTimeInterval(60)
    }
}
