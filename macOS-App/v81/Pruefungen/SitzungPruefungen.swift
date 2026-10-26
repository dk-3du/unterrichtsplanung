// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Unser `Tag`, nicht der von `Testing`.
private typealias Tag = Unterrichtsplanung.Tag

// ── Der Sitzungszustand ───────────────────────────────────────────────────
// Ein Wert statt vier Merker: Was er hergibt, kommt nur aus ihm; was es nicht
// geben darf, lässt sich nicht bauen.

@Suite("Sitzungszustand")
@MainActor
struct SitzungPruefungen {

    private func planung(_ titel: String = "Sitzung") throws -> Planung {
        Planung.leer(titel: titel, start: try #require(Tag(iso: "2026-08-03")), wochen: 4,
                     basis: "", klassen: Standardkurse.aufbauen([("G6a", "Informatik")]),
                     fachfarben: [:])
    }

    private func tresor() throws -> Tresor {
        let t = Tresor.neu()
        try t.passphraseSetzen("Ein Satz, den man behält", runden: Tresor.rundenMindestens)
        return t
    }

    /// Ein versiegelter Behälter samt gelesenem Kopf — das, was beim Start
    /// auf der Platte liegt.
    private func behaelter(_ t: Tresor) throws -> (roh: Data, kopf: Behaelterkopf) {
        let roh = try t.versiegeln(try Planungsdatei.schreiben(try planung()), inhalt: .planung, ziel: .ablage)
        return (roh, try Tresor.kopfLesen(roh))
    }

    @Test("Leer und gesperrt geben nichts zum Speichern her; Klartext und verschlüsselt liefern Klartext samt Schlüssel")
    func serialisierungsgrenze() throws {
        #expect(throws: Planungssitzung.Speicherhindernis.leer) {
            try Planungssitzung.leer.planungsdatenZumSpeichern()
        }
        let t = try tresor()
        let (roh, kopf) = try behaelter(t)
        #expect(throws: Planungssitzung.Speicherhindernis.gesperrt) {
            try Planungssitzung.gesperrt(.ablage(roh), kopf).planungsdatenZumSpeichern()
        }
        #expect(throws: Planungssitzung.Speicherhindernis.gesperrt) {
            try Planungssitzung.gesperrt(.ablage(roh), nil).planungsdatenZumSpeichern()
        }

        let p = try planung("Im Klartext")
        let klar = try Planungssitzung.klartext(p).planungsdatenZumSpeichern()
        #expect(klar.tresor == nil)
        #expect(try Planungsdatei.lesen(klar.klartext).titel == "Im Klartext")

        let ver = try Planungssitzung.verschluesselt(p, t).planungsdatenZumSpeichern()
        #expect(ver.tresor?.kennung == t.kennung)
        #expect(!Tresor.istBehaelter(ver.klartext), "die Grenze reicht Klartext — versiegelt wird in der Ablage")
        #expect(try Planungsdatei.lesen(ver.klartext).titel == "Im Klartext")

        #expect(throws: Planungssitzung.Speicherhindernis.leer) {
            try Planungssitzung.verschluesselt(nil, t).planungsdatenZumSpeichern()
        }
    }

    @Test("Stand, Planung, Schlüssel und Freigabe kommen allein aus dem Wert")
    func ableitungen() throws {
        let t = try tresor()
        let (roh, kopf) = try behaelter(t)
        let p = try planung()

        let leer = Planungssitzung.leer
        #expect(leer.stand == .aus && leer.planung == nil && leer.tresor == nil && leer.entsperrung == nil)

        let gesperrt = Planungssitzung.gesperrt(.ablage(roh), kopf)
        #expect(gesperrt.stand == .gesperrt && gesperrt.planung == nil && gesperrt.tresor == nil)
        #expect(gesperrt.entsperrung?.kopf.kennung == kopf.kennung)
        #expect(gesperrt.entsperrung?.ziel.istAblage == true)

        let ohneKopf = Planungssitzung.gesperrt(.ablage(roh), nil)
        #expect(ohneKopf.stand == .gesperrt && ohneKopf.entsperrung == nil,
                "eine neuere Fassung hat versiegelt: gesperrt, aber nichts zu entsperren")

        let klartext = Planungssitzung.klartext(p)
        #expect(klartext.stand == .aus && klartext.planung?.titel == p.titel && klartext.tresor == nil)

        let verschluesselt = Planungssitzung.verschluesselt(p, t)
        #expect(verschluesselt.stand == .an && verschluesselt.planung?.titel == p.titel)
        #expect(verschluesselt.tresor?.kennung == t.kennung)

        let bereit = Planungssitzung.verschluesselt(nil, t)
        #expect(bereit.stand == .an && bereit.planung == nil && bereit.tresor?.kennung == t.kennung,
                "nach einem unlesbaren Stand: Schlüssel offen, Planung noch keine")
    }

    @Test("Planung tauschen lässt den Schlüssel stehen, Schlüssel tauschen die Planung")
    func uebergaenge() throws {
        let t = try tresor()
        let (roh, kopf) = try behaelter(t)
        let p = try planung("Erste")
        let p2 = try planung("Zweite")

        guard case .klartext(let k) = Planungssitzung.leer.mit(planung: p) else { Issue.record("erwartet .klartext"); return }
        #expect(k.titel == "Erste")
        guard case .leer = Planungssitzung.klartext(p).mit(planung: nil) else { Issue.record("erwartet .leer"); return }

        guard case .verschluesselt(let v?, let vt) = Planungssitzung.verschluesselt(p, t).mit(planung: p2)
        else { Issue.record("erwartet .verschluesselt mit Planung"); return }
        #expect(v.titel == "Zweite" && vt.kennung == t.kennung)

        guard case .verschluesselt(let w?, let wt) = Planungssitzung.klartext(p).mit(tresor: t)
        else { Issue.record("erwartet .verschluesselt"); return }
        #expect(w.titel == "Erste" && wt.kennung == t.kennung)

        guard case .klartext(let z) = Planungssitzung.verschluesselt(p, t).mit(tresor: nil)
        else { Issue.record("erwartet .klartext"); return }
        #expect(z.titel == "Erste")

        guard case .verschluesselt(nil, let gt) = Planungssitzung.gesperrt(.ablage(roh), kopf).mit(tresor: t)
        else { Issue.record("erwartet .verschluesselt ohne Planung"); return }
        #expect(gt.kennung == t.kennung, "aus der Sperre heraus: der Schlüssel zuerst, die Planung kommt von der Platte")
    }

    @Test("Im Speicher sind Einschalten und Aufheben ein Wert, kein Merkerpaar")
    func imSpeicher() throws {
        let speicher = Planungsspeicher(vorschau: try planung("Im Speicher"))
        guard case .klartext = speicher.sitzung else { Issue.record("erwartet .klartext"); return }
        #expect(speicher.verschluesselungsstand == .aus && speicher.tresor == nil && !speicher.entsperrungOffen)

        try speicher.pruefverschluesselung()
        guard case .verschluesselt(let p?, let t) = speicher.sitzung else { Issue.record("erwartet .verschluesselt"); return }
        #expect(p.titel == "Im Speicher")
        #expect(speicher.tresor === t)
        #expect(speicher.verschluesselungsstand == .an && speicher.verschluesselt)

        speicher.titelSetzen("Umbenannt")
        guard case .verschluesselt(let p2?, let t2) = speicher.sitzung else { Issue.record("erwartet .verschluesselt"); return }
        #expect(p2.titel == "Umbenannt" && t2 === t, "die Planung wechselt, der Schlüssel bleibt")

        speicher.verschluesselungAufheben()
        guard case .klartext(let k) = speicher.sitzung else { Issue.record("erwartet .klartext"); return }
        #expect(k.titel == "Umbenannt")
        #expect(speicher.verschluesselungsstand == .aus && speicher.tresor == nil)
    }
}
