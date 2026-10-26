// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import Unterrichtsplanung

/// Die Lücke zwischen einem Bogen und dem Dialog, der aus ihm aufgeht (G2-01, E784).
///
/// Ein Sichern- oder Druckdialog aus einem Bogen wartet, bis das Blatt frei ist (B107), und hängt sich dann an. In dieser
/// Lücke kann das Blatt gehen — ⎋ einer schnellen Hand. Dann darf nichts mehr an ihm hängen. Die Entscheidung ist rein; am
/// Lauf schließt ein Prüfweg das Blatt genau in der Lücke (Lernendenprobe, Schritt „Rückmeldungsliste“, Teil C2).
@Suite("Dialogort: die Lücke zwischen Bogen und Dialog (G2-01, E784)")
struct DialogortLueckePruefungen {

    @Test("Ein freies, sichtbares Blatt am Hauptfenster nimmt den Dialog")
    func frei() {
        #expect(Dialogort.anhaengbar(belegt: false, sichtbar: true, amHauptfenster: true))
    }

    @Test("Noch belegt (B107): Nichts hängt an")
    func belegt() {
        #expect(!Dialogort.anhaengbar(belegt: true, sichtbar: true, amHauptfenster: true))
    }

    @Test("In der Lücke gegangen (G2-01): nicht mehr sichtbar oder nicht mehr am Hauptfenster — nichts hängt an")
    func gegangen() {
        #expect(!Dialogort.anhaengbar(belegt: false, sichtbar: false, amHauptfenster: true), "nicht mehr sichtbar")
        #expect(!Dialogort.anhaengbar(belegt: false, sichtbar: true, amHauptfenster: false), "nicht mehr am Hauptfenster")
        #expect(!Dialogort.anhaengbar(belegt: false, sichtbar: false, amHauptfenster: false), "beides")
    }
}
