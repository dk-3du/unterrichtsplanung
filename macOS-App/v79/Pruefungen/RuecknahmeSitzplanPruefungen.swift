// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

/// Der zweite Schauplatz: der Entwurf im Sitzplanblatt (S6, E82).
///
/// Adaptiv kleinteilig, wie vom Nutzer vorgegeben: Umbenennen, Hinzufügen und
/// Entfernen je ein Schritt; das **Ziehen ein Schritt je Zug** — die Fläche
/// meldet erst beim Loslassen; die Pfeiltasten melden je Tastendruck und wachsen
/// über die Schreibphase zusammen (E88).
@Suite("Rücknahme: Sitzplan")
struct RuecknahmeSitzplanPruefungen {

    struct Fall: Sendable {
        let name: String
        /// Der Handgriff am Entwurf — genau die Wege, die auch die Fläche geht.
        let tun: @Sendable (Sitzplan) -> Sitzplan
        var kennung: String?
        /// Der Ausgangsstand, wenn der voreingestellte nicht taugt — ein
        /// Lehrertisch lässt sich nur hinzufügen, wo keiner steht.
        var vorbereiten: (@Sendable (Sitzplan) -> Sitzplan)?
    }

    static func entwurf() -> Sitzplan {
        Sitzplan.anordnen(klasseId: "k1", namen: ["Ada", "Alan", "Grace", "Edsger"])
    }

    static let faelle: [Fall] = [
        Fall(name: Schrittname.tischeVerschieben) { plan in
            plan.verschoben([plan.tische[0].id], um: CGPoint(x: 24, y: 16),
                            anker: plan.tische[0].id, fangen: true)
        },
        Fall(name: Schrittname.tischHinzufuegen) { plan in
            plan.mitNeuemTisch(name: "Neu") ?? plan
        },
        Fall(name: Schrittname.tischUmbenennen, tun: { plan in
            plan.umbenannt(plan.tische[0].id, name: "Ada Lovelace")
        }, kennung: "t1"),
        Fall(name: Schrittname.tischEntfernen) { plan in plan.ohne(plan.tische[0].id) },
        Fall(name: Schrittname.tischeEntfernen) { plan in
            plan.ohne(plan.tische[0].id).ohne(plan.tische[1].id)
        },
        Fall(name: Schrittname.lehrertischHinzufuegen, tun: { plan in plan.mitLehrertisch() },
             vorbereiten: { plan in plan.ohne(Sitzplan.lehrertischKennung) }),
        Fall(name: Schrittname.lehrertischEntfernen) { plan in
            plan.mitLehrertisch().ohne(Sitzplan.lehrertischKennung)
        },
        Fall(name: Schrittname.tischeAnordnen) { plan in
            Sitzplan.anordnen(klasseId: plan.klasseId, namen: ["Ada", "Alan"])
        },
    ]

    @MainActor
    @Test("Tun, widerrufen, wiederholen — über alle Handgriffe am Entwurf",
          arguments: RuecknahmeSitzplanPruefungen.faelle.indices)
    func hinUndZurueck(_ nummer: Int) throws {
        try Pruefuhr.angehalten {
            let fall = RuecknahmeSitzplanPruefungen.faelle[nummer]
            let verlauf = Ruecknahme<Sitzplan>()
            let ausgang = RuecknahmeSitzplanPruefungen.entwurf()
            let vorher = fall.vorbereiten?(ausgang) ?? ausgang
            let nachher = fall.tun(vorher)
            #expect(nachher != vorher, Comment(rawValue: "\(fall.name): der Handgriff muss etwas ändern"))

            verlauf.anmelden(fall.name, kennung: fall.kennung, vorher: vorher, nachher: nachher)
            #expect(verlauf.naechsterName == fall.name)
            let zurueck = try #require(verlauf.zuruecknehmen())
            #expect(zurueck.vorher == vorher, Comment(rawValue: "\(fall.name): Tisch für Tisch wie vorher"))
            let vor = try #require(verlauf.wiederholen())
            #expect(vor.nachher == nachher, Comment(rawValue: "\(fall.name): und wie danach"))
        }
    }

    // ── Die Körnung (E88) ─────────────────────────────────────────────────

    @MainActor
    @Test("Ein Zug ist ein Schritt — gemeldet wird beim Loslassen, nicht beim Ziehen")
    func ziehenIstEinSchritt() {
        // Die Fläche meldet in `mouseUp`, nicht in `mouseDragged`: Der Verlauf
        // sieht die Zwischenstände gar nicht erst.
        let verlauf = Ruecknahme<Sitzplan>()
        let anfang = RuecknahmeSitzplanPruefungen.entwurf()
        let ende = anfang.verschoben([anfang.tische[0].id], um: CGPoint(x: 80, y: 40),
                                     anker: anfang.tische[0].id, fangen: true)
        verlauf.anmelden(Schrittname.tischeVerschieben, vorher: anfang, nachher: ende)
        #expect(verlauf.zurueck.count == 1)
    }

    @MainActor
    @Test("Gehaltene Pfeiltasten schieben einen Tisch, nicht zehn (E88)")
    func pfeiltastenWachsenZusammen() {
        let verlauf = Ruecknahme<Sitzplan>()
        let anfang = RuecknahmeSitzplanPruefungen.entwurf()
        var stand = anfang
        let tisch = stand.tische[0].id
        Pruefuhr.angehalten {
            for _ in 0..<6 {
                let neu = stand.verschoben([tisch], um: CGPoint(x: 8, y: 0), fangen: false)
                verlauf.anmelden(Schrittname.tischeVerschieben, kennung: tisch,
                                 vorher: stand, nachher: neu)
                stand = neu
            }
        }
        #expect(verlauf.zurueck.count == 1, "sechs Tastendrücke, ein Schritt")
        #expect(verlauf.zurueck.first?.vorher == anfang, "und zurück geht es bis vor den ersten")
    }

    @MainActor
    @Test("Zwei Tische sind zwei Schritte")
    func zweiTischeZweiSchritte() {
        let verlauf = Ruecknahme<Sitzplan>()
        let anfang = RuecknahmeSitzplanPruefungen.entwurf()
        let eins = anfang.verschoben([anfang.tische[0].id], um: CGPoint(x: 8, y: 0), fangen: false)
        let zwei = eins.verschoben([eins.tische[1].id], um: CGPoint(x: 8, y: 0), fangen: false)
        Pruefuhr.angehalten {
            verlauf.anmelden(Schrittname.tischeVerschieben, kennung: anfang.tische[0].id,
                             vorher: anfang, nachher: eins)
            verlauf.anmelden(Schrittname.tischeVerschieben, kennung: eins.tische[1].id,
                             vorher: eins, nachher: zwei)
        }
        #expect(verlauf.zurueck.count == 2)
    }

    @MainActor
    @Test("Die Fläche nennt beim Entfernen, was entfernt wird")
    func namenDerEntfernung() {
        #expect(Sitzplanansicht.entfernungsname(["t1"]).name == Schrittname.tischEntfernen)
        #expect(Sitzplanansicht.entfernungsname(["t1", "t2"]).name == Schrittname.tischeEntfernen)
        #expect(Sitzplanansicht.entfernungsname([Sitzplan.lehrertischKennung]).name
                == Schrittname.lehrertischEntfernen)
    }

    @MainActor
    @Test("An der Fläche gemessen: ein Zug meldet einmal, beim Loslassen")
    func flaecheMeldetErstBeimLoslassen() throws {
        let plan = RuecknahmeSitzplanPruefungen.entwurf()
        let ansicht = Sitzplanansicht(plan: plan, ton: Farbwelt.ton(0))
        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                               styleMask: [.titled], backing: .buffered, defer: true)
        fenster.contentView = ansicht
        var handgriffe: [Sitzplanhandgriff] = []
        ansicht.beiAenderung = { _, handgriff in handgriffe.append(handgriff) }

        let start = plan.tische[0].rahmen
        func maus(_ art: NSEvent.EventType, _ punkt: CGPoint) {
            guard let ereignis = NSEvent.mouseEvent(with: art, location: punkt, modifierFlags: [],
                                                    timestamp: 0, windowNumber: fenster.windowNumber,
                                                    context: nil, eventNumber: 0, clickCount: 1,
                                                    pressure: 1)
            else { return }
            switch art {
            case .leftMouseDown: ansicht.mouseDown(with: ereignis)
            case .leftMouseDragged: ansicht.mouseDragged(with: ereignis)
            default: ansicht.mouseUp(with: ereignis)
            }
        }
        // Das Fenster rechnet von unten, die Fläche von oben.
        func imFenster(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            ansicht.convert(CGPoint(x: x, y: y), to: nil)
        }
        maus(.leftMouseDown, imFenster(start.midX, start.midY))
        for schritt in 1...5 {
            maus(.leftMouseDragged, imFenster(start.midX + CGFloat(schritt) * 12, start.midY))
        }
        #expect(handgriffe.isEmpty, "während des Ziehens meldet die Fläche nichts")
        maus(.leftMouseUp, imFenster(start.midX + 60, start.midY))
        #expect(handgriffe.count == 1, "erst das Loslassen ist der Schritt")
        #expect(handgriffe.first?.name == Schrittname.tischeVerschieben)
        #expect(handgriffe.first?.kennung == nil, "und jeder Zug ist ein eigener")
    }

    // ── Wem ⌘Z gehört (E82, E87) ──────────────────────────────────────────

    @MainActor
    @Test("Solange das Blatt steht, gehört der Verlauf ihm")
    func blattHatDenVorrang() throws {
        let ordner = URL.temporaryDirectory.appending(component: "sp-\(UUID().uuidString)",
                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        s.planung = Planung.leer(titel: "Sitzplan", start: try #require(Tag(iso: "2026-08-03")),
                                 wochen: 4, basis: "",
                                 klassen: [Klasse(id: "k1", name: "G6a", fach: "Informatik",
                                                  notiz: "", farbe: 0, farbeManuell: false)],
                                 fachfarben: [:])
        s.aendern(Schrittname.planungstitelAendern) { $0.titel = "Im Hauptfenster geändert" }
        #expect(s.widerrufenTitel.contains(Schrittname.planungstitelAendern))

        // Das Blatt tritt an — mit eigenem Verlauf und eigenem Entwurf.
        var entwurf = RuecknahmeSitzplanPruefungen.entwurf()
        s.sitzplanblattUebernimmt { zurueck in entwurf = zurueck }
        #expect(s.sitzplanblattOffen)
        #expect(!s.kannWiderrufen, "sein Verlauf ist noch leer")
        let nachher = entwurf.umbenannt(entwurf.tische[0].id, name: "Ada Lovelace")
        s.sitzplanverlauf.anmelden(Schrittname.tischUmbenennen, kennung: entwurf.tische[0].id,
                                   vorher: entwurf, nachher: nachher)
        entwurf = nachher
        #expect(s.widerrufenTitel == "Widerrufen: " + Schrittname.tischUmbenennen)

        s.widerrufen()
        #expect(entwurf.tische[0].name == "Ada", "das Blatt bekommt seinen Entwurf zurück")
        #expect(s.planung?.titel == "Im Hauptfenster geändert", "und die Planung bleibt unberührt")

        s.wiederholen()
        #expect(entwurf.tische[0].name == "Ada Lovelace")

        // Blatt zu: Der Verlauf des Hauptfensters gilt wieder.
        s.sitzplanblattGibtAb()
        #expect(s.widerrufenTitel.contains(Schrittname.planungstitelAendern))
        s.widerrufen()
        #expect(s.planung?.titel == "Sitzplan")
    }

    @MainActor
    @Test("Ein entfernter Sitzplan kommt mit ⌘Z zurück")
    func entfernterSitzplanKommtZurueck() throws {
        try Pruefuhr.angehalten {
            let ordner = URL.temporaryDirectory.appending(component: "sp2-\(UUID().uuidString)",
                                                          directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: ordner) }
            let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
            s.planung = Planung.leer(titel: "Sitzplan", start: try #require(Tag(iso: "2026-08-03")),
                                     wochen: 4, basis: "",
                                     klassen: [Klasse(id: "k1", name: "G6a", fach: "Informatik",
                                                      notiz: "", farbe: 0, farbeManuell: false)],
                                     fachfarben: [:])
            let plan = RuecknahmeSitzplanPruefungen.entwurf()
            #expect(s.sitzplaene.setzen(plan, fuer: "k1") == nil)

            s.sitzplanEntfernen(klasse: "k1", ort: .sitzplan)
            s.rueckfrageBeantworten(true)
            #expect(s.sitzplaene.plan(fuer: "k1") == nil)
            #expect(s.widerrufenTitel == "Widerrufen: " + Schrittname.sitzplanEntfernen)

            s.widerrufen()
            #expect(s.sitzplaene.plan(fuer: "k1") == plan, "Tisch für Tisch zurück")

            s.wiederholen()
            #expect(s.sitzplaene.plan(fuer: "k1") == nil, "und wieder fort")
        }
    }

    @MainActor
    @Test("Sitzplan löschen, ⌘Z, neuer Sitzplan, ⇧⌘Z, ⌘Z — zurück kommt der neue (N58-02)")
    func wiederholenNimmtDenNeuen() throws {
        try Pruefuhr.angehalten {
            let ordner = URL.temporaryDirectory.appending(component: "sp3-\(UUID().uuidString)",
                                                          directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: ordner) }
            let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
            s.planung = Planung.leer(titel: "Sitzplan", start: try #require(Tag(iso: "2026-08-03")),
                                     wochen: 4, basis: "",
                                     klassen: [Klasse(id: "k1", name: "G6a", fach: "Informatik",
                                                      notiz: "", farbe: 0, farbeManuell: false)],
                                     fachfarben: [:])
            #expect(s.sitzplaene.setzen(RuecknahmeSitzplanPruefungen.entwurf(), fuer: "k1") == nil)
            s.sitzplanEntfernen(klasse: "k1", ort: .sitzplan)
            s.rueckfrageBeantworten(true)
            s.widerrufen()
            #expect(s.sitzplaene.plan(fuer: "k1")?.tische.count == 4, "der alte ist zurück")

            let p1 = Sitzplan.anordnen(klasseId: "k1", namen: ["Edsger", "Barbara"])
            #expect(s.sitzplanUebernehmen(p1) == nil)
            s.wiederholen()
            #expect(s.sitzplaene.plan(fuer: "k1") == nil, "das Wiederholen löscht den, der da ist")
            s.widerrufen()
            #expect(s.sitzplaene.plan(fuer: "k1")?.tische.map(\.name) == ["Edsger", "Barbara"],
                    "und das Widerrufen bringt genau den zurück — nicht die Momentaufnahme")
        }
    }
}
