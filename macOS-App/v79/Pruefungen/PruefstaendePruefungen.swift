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
            ("--materialtest", .materialtest),
            ("--ordnertest", .ordnertest), ("--messreihe", .messreihe), ("--rastermasse", .rastermasse),
            ("--dauertest", .dauertest), ("--sitzplantest", .sitzplantest),
            ("--erststarttest", .erststarttest), ("--widerruftest", .widerruftest),
            ("--dialogtest", .dialogtest), ("--statustest", .statustest),
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

    @Test("Jeder Prüfstand nennt zuerst sein Paket — Kennung, Fassung, Quellen- und Werkzeugstand (E128)")
    func paketzeile() {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "org.3ducation.Unterrichtsplanung.probe",
            "CFBundleShortVersionString": "1.7.4", "CFBundleVersion": "63",
            "UPQuellenstand": String(repeating: "a", count: 64),
            "UPWerkzeugstand": "d840422ba2909c1b" + String(repeating: "0", count: 48),
        ]
        #expect(Pruefstaende.paketzeile(plist)
                == "Paket: org.3ducation.Unterrichtsplanung.probe 1.7.4 (63), Quellenstand aaaaaaaaaaaa…, Werkzeugstand d840422ba290…")
        #expect(Pruefstaende.paketzeile(nil) == "Paket: kein Bündel (Entwicklungsbau)")
        #expect(Pruefstaende.paketzeile(["CFBundleName": "Unterrichtsplanung"]) == "Paket: kein Bündel (Entwicklungsbau)",
                "ohne Kennung ist es kein Bündel")
        var aelter = plist
        aelter["UPWerkzeugstand"] = nil
        #expect(Pruefstaende.paketzeile(aelter).hasSuffix("Werkzeugstand fehlt"),
                "ein Paket aus einer Fassung vor v63 sagt, dass ihm der Werkzeugstand fehlt")
    }

    @Test("Jeder Prüfstand beweist sein Ende: „ENDE <Name>“ — vor dem Start läuft keiner (N67-01)")
    func endezeile() {
        #expect(Pruefstaende.endezeile(.klicktest) == "ENDE KLICKTEST")
        #expect(Pruefstaende.endezeile(.uebergangstest("einschalten")) == "ENDE UEBERGANGSTEST",
                "die Art gehört nicht in die Ende-Zeile — der Treiber kennt nur den Namen")
        #expect(Pruefstaende.endezeile(.entsperrtest("passphrase")) == "ENDE ENTSPERRTEST")
        // Die Zeile beginnt mit dem Wort, das runde.py sucht, und trägt genau den
        // Namen, der vor jeder Zeile des Prüfstands steht.
        for auftrag: Pruefstaende.Auftrag in [.rolltest, .tourtest, .ordnertest, .sitzplantest, .erststarttest,
                                              .widerruftest, .dialogtest, .materialtest, .statustest,
                                              .abbild(URL(fileURLWithPath: "/tmp/x.png"))] {
            #expect(Pruefstaende.endezeile(auftrag) == "ENDE " + auftrag.name, Comment(rawValue: auftrag.name))
        }
        #expect(Pruefstaende.laufender == nil, "im Prüfziel hat kein Prüfstand gestartet")
    }

    @Test("ENDE nur nach dem Abschluss — ein regulär beendeter, nicht abgemeldeter Prüfstand sagt ABGEBROCHEN ✗ (N67-01 Rest)")
    func abschlussprotokoll() {
        #expect(Pruefstaende.schlusszeile(.klicktest, abgeschlossen: false)
                == "ABGEBROCHEN KLICKTEST ✗ — beendet vor dem Abschluss",
                "die Abbruchmeldung trägt ✗ — der Lauf ist unvollständig — und nie das Wort ENDE")
        #expect(Pruefstaende.schlusszeile(.klicktest, abgeschlossen: true) == Pruefstaende.endezeile(.klicktest))
        #expect(!Pruefstaende.schlusszeile(.tourtest, abgeschlossen: false).contains("ENDE"))
        // Der Delegat liest den Stand des Laufs: ohne Abmeldung die Abbruchmeldung,
        // nach `abschliessen()` die Ende-Zeile; ohne Prüfstand nichts.
        #expect(Pruefstaende.beendet() == nil, "im Betrieb ohne Prüfstand druckt der Delegat nichts")
        Pruefstaende.laufender = .klicktest
        Pruefstaende.abgeschlossen = false
        defer { Pruefstaende.laufender = nil; Pruefstaende.abgeschlossen = false }
        #expect(Pruefstaende.beendet() == "ABGEBROCHEN KLICKTEST ✗ — beendet vor dem Abschluss")
        Pruefstaende.abschliessen()
        #expect(Pruefstaende.beendet() == "ENDE KLICKTEST")
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
