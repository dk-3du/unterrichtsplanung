// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import Unterrichtsplanung

@Suite("Blatt „Verschlüsselung“: Erinnerung ans Übertragen (R97-04, E1309)")
@MainActor
struct UebertragenErinnerungPruefungen {

    @Test("Erinnerung vor dem Einschalten und vor dem Aufheben (R97-04, E1309, Wortlaute E1317)")
    func erinnerungen() {
        #expect(Passphrasenwahl.erinnerungEinrichten == "Haken und Kommentare aus der Web App bitte vorher übertragen: "
                + "Nach dem Einschalten gilt ein unverschlüsselter Stand der Web App nicht mehr.")
        #expect(VerschluesselungDialog.erinnerungAufheben == "Haken und Kommentare aus der Web App bitte vorher "
                + "übertragen: Nach dem Aufheben gilt ein verschlüsselter Stand der Web App nicht mehr.")
    }

    @Test("Erinnerung auch vor „Schlüssel erneuern“ (R97-E1, E1322)")
    func erinnerungErneuern() {
        #expect(Passphrasenwahl.erinnerung(erneuern: false) == Passphrasenwahl.erinnerungEinrichten)
        #expect(Passphrasenwahl.erinnerung(erneuern: true) == "Haken und Kommentare aus der Web App bitte vorher "
                + "übertragen: Nach dem Erneuern gilt ein Stand der Web App unter dem alten Schlüssel nicht mehr.")
    }
}
