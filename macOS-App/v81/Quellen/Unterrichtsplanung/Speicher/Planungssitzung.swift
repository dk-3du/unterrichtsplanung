// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Was die Sitzung hält und unter welchem Schutz — ein Wert statt vier Merker.
///
/// Unmögliche Kombinationen gibt es darin nicht: keine Planung bei
/// eingeschalteter Verschlüsselung ohne Schlüssel, kein Schlüssel im
/// gesperrten Zustand, kein Kopf ohne versiegelte Ablage. Die Merker über die
/// Platte (`sicherungGesperrt`, `startsperre`) bleiben daneben stehen — sie
/// sagen etwas über die Datei, nicht über die Sitzung.
enum Planungssitzung: Sendable {
    /// Nichts geladen, kein Schlüssel.
    case leer
    /// Die Ablage — oder nach unlesbarem Stand die Fassung davor — liegt
    /// versiegelt; der Schlüssel ist noch zu. Ohne Kopf, wenn eine neuere
    /// Fassung versiegelt hat: dann ist nichts zu entsperren, nur zu warten.
    case gesperrt(Planungsspeicher.Entsperrungsziel, Behaelterkopf?)
    /// Die Planung, unverschlüsselt.
    case klartext(Planung)
    /// Schlüssel offen. Ohne Planung nur, solange nach einem unlesbaren Stand
    /// noch keine neue angelegt ist — der Schlüssel bleibt dann für sie bereit.
    case verschluesselt(Planung?, Tresor)

    var planung: Planung? {
        switch self {
        case .klartext(let planung): planung
        case .verschluesselt(let planung, _): planung
        case .leer, .gesperrt: nil
        }
    }

    /// Der Datenschlüssel der Sitzung — `nil` heißt Klartext oder noch zu.
    var tresor: Tresor? {
        if case .verschluesselt(_, let tresor) = self { tresor } else { nil }
    }

    var stand: Planungsspeicher.Verschluesselungsstand {
        switch self {
        case .leer, .klartext: .aus
        case .gesperrt: .gesperrt
        case .verschluesselt: .an
        }
    }

    /// Die ausstehende Freigabe der Ablage — nur im gesperrten Zustand mit Kopf.
    var entsperrung: Planungsspeicher.Entsperrung? {
        if case .gesperrt(let ziel, let kopf?) = self { Planungsspeicher.Entsperrung(ziel: ziel, kopf: kopf) } else { nil }
    }

    /// Dieselbe Sitzung mit anderer Planung — der Schlüssel bleibt, der
    /// Leerzustand wird zur Klartext-Sitzung und zurück. Eine gesperrte
    /// Sitzung nimmt keine Planung an; die Schranke dafür steht bei den
    /// Aufrufern (`entsperrungOffen`), hier wird sie nur noch festgestellt.
    func mit(planung: Planung?) -> Planungssitzung {
        switch self {
        case .verschluesselt(_, let tresor): return .verschluesselt(planung, tresor)
        case .leer, .klartext: return planung.map { .klartext($0) } ?? .leer
        case .gesperrt:
            assertionFailure("eine gesperrte Sitzung nimmt keine Planung an")
            return self
        }
    }

    /// Dieselbe Planung unter anderem Schlüssel — `nil` heißt Klartext. Aus
    /// dem gesperrten Zustand führt nur ein Schlüssel heraus; die Planung
    /// kommt danach von der Platte.
    func mit(tresor: Tresor?) -> Planungssitzung {
        if let tresor { return .verschluesselt(planung, tresor) }
        if case .gesperrt = self {
            assertionFailure("eine gesperrte Sitzung öffnet sich nur mit einem Schlüssel")
            return self
        }
        return planung.map { .klartext($0) } ?? .leer
    }

    /// Warum gerade nichts auf die Platte darf.
    enum Speicherhindernis: Error, Equatable {
        /// Keine Planung in der Sitzung.
        case leer
        /// Die Ablage liegt versiegelt und ist noch nicht entsperrt.
        case gesperrt
    }

    /// Die Serialisierungsgrenze: der Klartext der Planung samt dem Schlüssel,
    /// unter dem die Ablage ihn versiegelt — nie schon ein Behälter, sonst
    /// versiegelte die Ablage doppelt. Leer und gesperrt werfen; wer hier
    /// vorbei will, hat nichts zu schreiben.
    func planungsdatenZumSpeichern() throws -> (klartext: Data, tresor: Tresor?) {
        switch self {
        case .leer: throw Speicherhindernis.leer
        case .gesperrt: throw Speicherhindernis.gesperrt
        case .klartext(let planung): (try Planungsdatei.schreiben(planung), nil)
        case .verschluesselt(let planung?, let tresor): (try Planungsdatei.schreiben(planung), tresor)
        case .verschluesselt(nil, _): throw Speicherhindernis.leer
        }
    }
}

extension Planungsspeicher {
    /// Eine Freigabe, die gerade aussteht: für die gesperrte Ablage (in der
    /// Sitzung) oder für eine Datei von außen unter fremdem Schlüssel (neben
    /// der Sitzung — die Ablage bleibt dabei offen).
    struct Entsperrung: Sendable {
        let ziel: Entsperrungsziel
        let kopf: Behaelterkopf
    }
}
