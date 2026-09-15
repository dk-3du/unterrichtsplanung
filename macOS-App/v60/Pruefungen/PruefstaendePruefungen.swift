// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Der Verteiler der Prüfstände ──────────────────────────────────────────
// Ein Aufruf liest die Argumente einmal und wählt genau einen Prüfstand.

@Suite("Prüfstände: Verteiler")
@MainActor
struct PruefstaendePruefungen {

    @Test("Jede Flagge trifft ihren Prüfstand — und ohne Flagge läuft keiner")
    func flaggen() {
        let paare: [(String, Pruefstaende.Auftrag)] = [
            ("--rolltest", .rolltest), ("--klicktest", .klicktest), ("--auswahltest", .auswahltest),
            ("--mischtest", .mischtest), ("--ziehtest", .ziehtest), ("--titeltest", .titeltest),
            ("--menuetest", .menuetest), ("--tourtest", .tourtest), ("--updatetest", .updatetest),
            ("--ordnertest", .ordnertest), ("--messreihe", .messreihe), ("--rastermasse", .rastermasse),
            ("--dauertest", .dauertest), ("--sitzplantest", .sitzplantest),
            ("--erststarttest", .erststarttest), ("--widerruftest", .widerruftest),
        ]
        for (flagge, auftrag) in paare {
            #expect(Pruefstaende.Auftrag.lesen(["Unterrichtsplanung", flagge]) == auftrag, Comment(rawValue: flagge))
        }
        #expect(Pruefstaende.Auftrag.lesen(["Unterrichtsplanung"]) == nil)
        #expect(Pruefstaende.Auftrag.lesen(["Unterrichtsplanung", "--container", "-NSQuitAlwaysKeepsWindows", "0"]) == nil,
                "was kein Prüfstand ist, wählt keinen")
        #expect(Set(paare.map(\.1.name)).count == paare.count, "jeder Name ist eindeutig")
    }

    @Test("Ohne eigenen Ordner läuft nur der Erststarttest, und nur im Probepaket (E78)")
    func schrankeOhneEigenenOrdner() {
        typealias Schranke = Pruefstandsschranke
        let probe = "org.3ducation.Unterrichtsplanung.probe"
        let echt = "org.3ducation.Unterrichtsplanung"
        #expect(Schranke.ohneEigenenOrdnerZulaessig(.erststarttest, kennung: probe, imContainer: true))
        #expect(!Schranke.ohneEigenenOrdnerZulaessig(.erststarttest, kennung: echt, imContainer: true),
                "an der echten Kennung bleibt die Schranke zu")
        #expect(!Schranke.ohneEigenenOrdnerZulaessig(.erststarttest, kennung: nil, imContainer: true))
        #expect(!Schranke.ohneEigenenOrdnerZulaessig(.widerruftest, kennung: probe, imContainer: true),
                "jeder andere Prüfstand braucht seinen eigenen Ordner")
        // Ohne Sandbox zeigt der voreingestellte Ort ins Benutzerverzeichnis, nicht
        // in einen Container — am 14.09.2026 genau so gemessen, als einem Probepaket
        // beim Umsignieren die Berechtigungen abhandenkamen.
        #expect(!Schranke.ohneEigenenOrdnerZulaessig(.erststarttest, kennung: probe, imContainer: false),
                "ohne Container ist der voreingestellte Ort der echte")
        // Kein anderer Prüfstand, auch nicht im Probepaket: Sie alle ändern oder
        // bilden ab, was dort schon liegt.
        for auftrag: Pruefstaende.Auftrag in [.klicktest, .sitzplantest, .tourtest, .ordnertest,
                                              .uebergangstest("pruefen"), .entsperrtest("passphrase"),
                                              .abbild(URL(fileURLWithPath: "/tmp/x.png"))] {
            #expect(!Schranke.ohneEigenenOrdnerZulaessig(auftrag, kennung: probe, imContainer: true),
                    Comment(rawValue: auftrag.name))
        }
    }

    @Test("Abbild und Entsperrprobe nehmen ihren Wert; ohne Ziel kein Abbild, ohne Weg die Passphrase")
    func werte() {
        #expect(Pruefstaende.Auftrag.lesen(["app", "--abbild", "/tmp/bild.png", "--dialog", "hilfe"])
                == .abbild(URL(fileURLWithPath: "/tmp/bild.png")))
        #expect(Pruefstaende.Auftrag.lesen(["app", "--abbild"]) == nil)
        #expect(Pruefstaende.Auftrag.lesen(["app", "--entsperrtest", "enklave"]) == .entsperrtest("enklave"))
        #expect(Pruefstaende.Auftrag.lesen(["app", "--entsperrtest"]) == .entsperrtest("passphrase"))
        #expect(Pruefstaende.Auftrag.lesen(["app", "--abbild", "/tmp/bild.png"])?.name == "ABBILD")
        #expect(Pruefstaende.Auftrag.lesen(["app", "--entsperrtest", "tot"])?.name == "ENTSPERRTEST")
    }

    @Test("Genau einer je Lauf: der Mischtest geht dem Abbild vor, sonst zählt die feste Reihenfolge")
    func genauEiner() {
        #expect(Pruefstaende.Auftrag.lesen(["app", "--abbild", "/tmp/b.png", "--mischtest"]) == .mischtest)
        #expect(Pruefstaende.Auftrag.lesen(["app", "--tourtest", "--rolltest"]) == .rolltest)
        #expect(Pruefstaende.Auftrag.lesen(["app", "--dauertest", "--entsperrtest", "gemischt"]) == .entsperrtest("gemischt"))
        #expect(Pruefstaende.Auftrag.lesen(["app", "--rolltest", "--zerlegen"]) == .rolltest,
                "--zerlegen ist ein Zusatz des Rolltests, kein eigener Prüfstand")
    }
}
