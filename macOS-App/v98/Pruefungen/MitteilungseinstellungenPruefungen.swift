// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// „Fertig“ im Unterblatt „Einstellungen der Mitteilung“ (v96, BH5, E1175, R-BH5-11): Was nicht angefasst wurde, bleibt,
/// wie es war. Am Wert, ohne Oberfläche.
@Suite("Einstellungen der Mitteilung: „Fertig“ schreibt nur Geändertes (R-BH5-11)")
@MainActor
struct MitteilungseinstellungenPruefungen {
    private static let heute = Tag(iso: "2026-11-11")!

    private static func mitteilung(datum: String, frist: String) -> Anliegen {
        Anliegen(id: "a-1", art: .mitteilung, titel: "Elternbrief Wandertag", lerngruppe: "g-1", betroffene: ["p-1"],
                 datum: datum, frist: frist, notiz: "", angelegt: "", geaendert: "")
    }

    /// „Fertig“ ohne eine Eingabe — so, wie die Felder begannen.
    private static func unberuehrt(_ m: Anliegen) -> (datum: String, frist: String) {
        let a = MitteilungseinstellungenBlatt.anfang(m, heute: heute)
        return MitteilungseinstellungenBlatt.werte(m, anfang: a, tag: a.tag, mitFrist: a.mitFrist, frist: a.frist)
    }

    @Test("Ohne Eingabe bleiben Tag und Frist — auch ohne Tag und mit unlesbarer Frist")
    func ohneEingabe() {
        // „kaputt“ erreicht das Blatt nicht — der Lader leert unlesbare Tage; hier nur, dass `werte` nichts erfindet (R-BH5N-02).
        for (datum, frist) in [("2026-09-07", ""), ("2026-09-07", "2026-09-21"), ("", ""), ("2026-09-07", "kaputt"), ("", "kaputt")] {
            let w = Self.unberuehrt(Self.mitteilung(datum: datum, frist: frist))
            #expect(w.datum == datum && w.frist == frist, "„\(datum)“/„\(frist)“ → „\(w.datum)“/„\(w.frist)“")
        }
    }

    @Test("Ein geänderter Tag, eine gesetzte, verschobene oder entfernte Frist werden geschrieben")
    func geaendert() {
        let m = Self.mitteilung(datum: "2026-09-07", frist: "2026-09-21")
        let a = MitteilungseinstellungenBlatt.anfang(m, heute: Self.heute)
        let tag = Tag(iso: "2026-09-08")!
        let frist = Tag(iso: "2026-09-28")!
        #expect(MitteilungseinstellungenBlatt.werte(m, anfang: a, tag: tag, mitFrist: true, frist: a.frist)
            == (datum: "2026-09-08", frist: "2026-09-21"), "der Tag")
        #expect(MitteilungseinstellungenBlatt.werte(m, anfang: a, tag: a.tag, mitFrist: true, frist: frist)
            == (datum: "2026-09-07", frist: "2026-09-28"), "die Frist verschoben")
        #expect(MitteilungseinstellungenBlatt.werte(m, anfang: a, tag: a.tag, mitFrist: false, frist: a.frist)
            == (datum: "2026-09-07", frist: ""), "die Frist entfernt")
        // Ohne Frist und ohne Tag: Das Häkchen setzt die vorgeschlagene, der Tag bleibt leer.
        let ohne = Self.mitteilung(datum: "", frist: "")
        let b = MitteilungseinstellungenBlatt.anfang(ohne, heute: Self.heute)
        #expect(MitteilungseinstellungenBlatt.werte(ohne, anfang: b, tag: b.tag, mitFrist: true, frist: b.frist)
            == (datum: "", frist: Self.heute.plus(tage: Mitteilungstext.fristTage).iso), "die Frist gesetzt")
    }
}
