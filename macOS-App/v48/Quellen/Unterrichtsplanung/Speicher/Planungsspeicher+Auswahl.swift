// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Auswählen, kopieren, verschieben ─────────────────────────────────────────
extension Planungsspeicher {

    func istAngewaehlt(_ id: String) -> Bool { auswahl.contains(id) }

    func istAngewaehlt(_ ort: Zellenort) -> Bool { zielzelle == ort }

    /// Mit `erweitern` kommt es zur bisherigen Auswahl dazu.
    func anwaehlen(vorhaben id: String, erweitern: Bool = false) {
        zielzelle = nil
        if erweitern {
            if auswahl.contains(id) { auswahl.remove(id) } else { auswahl.insert(id) }
        } else {
            auswahl = [id]
        }
        auswahlanker = id
    }

    /// Spanne entlang der Leserichtung des Rasters, Zeile für Zeile.
    func anwaehlenBis(vorhaben id: String) {
        guard let p = planung, let anker = auswahlanker ?? auswahl.first else {
            anwaehlen(vorhaben: id)
            return
        }
        let ordnung = ordnungsschluessel(p)
        guard let a = ordnung[anker], let b = ordnung[id] else {
            anwaehlen(vorhaben: id)
            return
        }
        let bereich = min(a, b)...max(a, b)
        auswahl = Set(ordnung.filter { bereich.contains($0.value) }.map(\.key))
        zielzelle = nil
        // Der Anker bleibt stehen: Ein zweites ⇧ verändert die Spanne.
    }

    func anwaehlen(zelle: Zellenort) {
        auswahl = []
        auswahlanker = nil
        zielzelle = zelle
    }

    func allesAnwaehlen() {
        guard let p = planung, !p.eintraege.isEmpty else { return }
        zielzelle = nil
        auswahl = Set(p.eintraege.map(\.id))
        auswahlanker = inRasterordnung(p.eintraege, p).first?.id
    }

    /// Gebraucht von den Prüfständen.
    func ablageLeeren() { ablage = nil }

    func auswahlAufheben() {
        auswahl = []
        auswahlanker = nil
        zielzelle = nil
    }

    /// Wirft aus Auswahl, Anker, Zielzelle und Ablage alles heraus, was es in
    /// der Planung nicht mehr gibt.
    func auswahlNachfuehren() {
        guard !auswahl.isEmpty || zielzelle != nil || ablage != nil else { return }
        guard let p = planung else {
            auswahl = []; auswahlanker = nil; zielzelle = nil; ablage = nil
            return
        }
        let vorhandene = Set(p.eintraege.map(\.id))
        if !auswahl.isEmpty { auswahl.formIntersection(vorhandene) }
        if let anker = auswahlanker, !vorhandene.contains(anker) { auswahlanker = nil }
        if let ziel = zielzelle,
           !p.klassen.contains(where: { $0.id == ziel.klasse })
            || !(0..<p.wochen).contains(ziel.woche) {
            zielzelle = nil
        }
        // Die Ablage hält Abzüge, keine Verweise — ohne den Kurs ginge das Einfügen ins Leere.
        if let inhalt = ablage {
            let kurse = Set(p.klassen.map(\.id))
            if !inhalt.vorhaben.allSatisfy({ kurse.contains($0.klasseId) }) { ablage = nil }
        }
    }

    /// Erst die Kurszeile, dann die Woche. Auswahlspanne, Kopieren und
    /// Versetzen müssen sich in derselben Reihenfolge einig sein.
    private func inRasterordnung(_ eintraege: [Vorhaben], _ p: Planung) -> [Vorhaben] {
        let reihe = kursreihen(p)
        return eintraege.sorted {
            (reihe[$0.klasseId] ?? 0, $0.woche) < (reihe[$1.klasseId] ?? 0, $1.woche)
        }
    }

    /// Doppelte Kennungen wehrt `Planungsdatei.lesen` ab; hier gilt trotzdem
    /// der erste Treffer, damit eine Anzeige nie über die Daten abbricht.
    private func ordnungsschluessel(_ p: Planung) -> [String: Int] {
        let sortiert = inRasterordnung(p.eintraege, p)
        return Dictionary(sortiert.enumerated().map { ($1.id, $0) },
                          uniquingKeysWith: { erster, _ in erster })
    }

    private func kursreihen(_ p: Planung) -> [String: Int] {
        Dictionary(p.klassen.enumerated().map { ($1.id, $0) },
                   uniquingKeysWith: { erster, _ in erster })
    }

    var angewaehlteVorhaben: [Vorhaben] {
        guard let p = planung else { return [] }
        return inRasterordnung(p.eintraege.filter { auswahl.contains($0.id) }, p)
    }

    /// In die angewählte Zelle, sonst in die des ersten angewählten Vorhabens.
    var einfuegeziel: Zellenort? {
        if let zielzelle { return zielzelle }
        return angewaehlteVorhaben.first.map { Zellenort(klasse: $0.klasseId, woche: $0.woche) }
    }

    var kannEinfuegen: Bool { ablage != nil && einfuegeziel != nil }

    private func inDieAblage(verschieben: Bool) {
        let gewaehlt = angewaehlteVorhaben
        guard !gewaehlt.isEmpty else { return }
        ablage = Ablageinhalt(vorhaben: gewaehlt, verschieben: verschieben)
        let was = gewaehlt.count == 1 ? "„\(gewaehlt[0].anzeigeTitel)“"
                                      : "\(gewaehlt.count) Vorhaben"
        melden(verschieben ? was + " zum Verschieben vorgemerkt — Zielzelle wählen und einfügen"
                           : was + " kopiert")
    }

    func kopieren() { inDieAblage(verschieben: false) }

    func verschiebenVormerken() { inDieAblage(verschieben: true) }

    func einfuegen() {
        guard let inhalt = ablage, let ziel = einfuegeziel else { return }
        versetzen(inhalt.vorhaben, nach: ziel, verschieben: inhalt.verschieben)
        if inhalt.verschieben { ablage = nil }
    }

    /// Mehrere behalten ihre Anordnung zueinander: Das am weitesten oben links
    /// liegende landet auf der Zielzelle. Was aus dem Raster fiele, bleibt
    /// liegen.
    ///
    /// `vor` ist die Kennung des Vorhabens, vor dem eingesetzt wird — `nil`
    /// heißt: ans Ende der Zielzelle. Sie zählt nur, wenn alles aus **einer**
    /// Zelle stammt.
    func versetzen(_ vorhaben: [Vorhaben], nach ziel: Zellenort, verschieben: Bool,
                   vor: String? = nil) {
        guard let erstes = vorhaben.first else { return }
        if vorhaben.allSatisfy({ $0.klasseId == erstes.klasseId && $0.woche == erstes.woche }) {
            einsetzen(vorhaben, nach: ziel, verschieben: verschieben, vor: vor)
            return
        }
        guard var p = planung else { return }
        let reihe = kursreihen(p)
        guard let zielreihe = reihe[ziel.klasse] else { return }
        let geordnet = inRasterordnung(vorhaben, p)
        guard let anker = geordnet.first, let ankerreihe = reihe[anker.klasseId] else { return }

        var neueAuswahl = Set<String>()
        var uebersprungen = 0
        var verfallen = 0
        for eintrag in geordnet {
            let zeile = zielreihe + ((reihe[eintrag.klasseId] ?? 0) - ankerreihe)
            let woche = ziel.woche + (eintrag.woche - anker.woche)
            guard p.klassen.indices.contains(zeile), (0..<p.wochen).contains(woche) else {
                uebersprungen += 1
                continue
            }
            let kurs = p.klassen[zeile].id
            if verschieben {
                guard let stelle = p.eintraege.firstIndex(where: { $0.id == eintrag.id }) else {
                    continue
                }
                p.eintraege[stelle].klasseId = kurs
                if p.eintraege[stelle].wocheWechseln(nach: woche) { verfallen += 1 }
                neueAuswahl.insert(eintrag.id)
            } else {
                var kopie = eintrag
                kopie.id = Kennung.neu("e")
                kopie.klasseId = kurs
                kopie.woche = woche
                if kopie.datumVerwerfen() { verfallen += 1 }
                p.eintraege.append(kopie)
                neueAuswahl.insert(kopie.id)
            }
        }
        guard !neueAuswahl.isEmpty else {
            melden("Dort ist kein Platz — das Ziel liegt außerhalb des Rasters.", .warnung)
            return
        }
        planung = p
        auswahl = neueAuswahl
        zielzelle = nil
        sichern()
        let anzahl = neueAuswahl.count
        var text = anzahl == 1 ? "Vorhaben " : "\(anzahl) Vorhaben "
        text += verschieben ? "verschoben" : "eingefügt"
        if uebersprungen > 0 { text += " · \(uebersprungen) außerhalb des Rasters ausgelassen" }
        melden(text)
        if verfallen > 0 {
            melden(verschieben ? Planungsspeicher.zurueckgesetzt(verfallen)
                               : Planungsspeicher.kopieOhneDatum(verfallen))
        }
    }

    /// Eine Gruppe aus einer Zelle an eine bestimmte Stelle der Zielzelle.
    /// Eingesetzt wird an einer Stelle der EINTRAGSLISTE, nicht der Zelle.
    private func einsetzen(_ vorhaben: [Vorhaben], nach ziel: Zellenort,
                           verschieben: Bool, vor: String?) {
        guard var p = planung, !vorhaben.isEmpty else { return }
        guard p.klassen.contains(where: { $0.id == ziel.klasse }),
              (0..<p.wochen).contains(ziel.woche) else {
            melden("Dort ist kein Platz — das Ziel liegt außerhalb des Rasters.", .warnung)
            return
        }

        // Zweiter Sortierwert: hält die Ordnung vollständig, wenn ein Vorhaben fehlt.
        let listenstelle = Dictionary(p.eintraege.enumerated().map { ($0.element.id, $0.offset) },
                                      uniquingKeysWith: { erste, _ in erste })
        let geordnet = vorhaben.enumerated()
            .sorted { (listenstelle[$0.element.id] ?? Int.max, $0.offset)
                    < (listenstelle[$1.element.id] ?? Int.max, $1.offset) }
            .map(\.element)
        let kennungen = Set(geordnet.map(\.id))

        // Wandert das Vorhaben an der Einfügestelle mit, gilt das nächste bleibende —
        // sonst fiele die Gruppe ans Zellenende.
        var anker = vor
        if let stelle = anker, kennungen.contains(stelle) {
            let zelle = p.eintraege.filter { $0.klasseId == ziel.klasse && $0.woche == ziel.woche }
            let ab = zelle.firstIndex { $0.id == stelle } ?? 0
            anker = zelle[ab...].first { !kennungen.contains($0.id) }?.id
        }

        let vorher = zellenordnung(p.eintraege)
        var verfallen = 0
        let eingesetzt = geordnet.map { eintrag -> Vorhaben in
            // Der Stand aus der Planung gilt: Ein Ablageinhalt ist ein Abzug von vorhin.
            var neu = listenstelle[eintrag.id].map { p.eintraege[$0] } ?? eintrag
            if !verschieben { neu.id = Kennung.neu("e") }
            neu.klasseId = ziel.klasse
            // Verschoben verfällt das Datum nur beim Wochenwechsel; eine Kopie
            // kommt immer ohne an — sie wird neu platziert und neu terminiert.
            if verschieben {
                if neu.wocheWechseln(nach: ziel.woche) { verfallen += 1 }
            } else {
                neu.woche = ziel.woche
                if neu.datumVerwerfen() { verfallen += 1 }
            }
            return neu
        }
        if verschieben { p.eintraege.removeAll { kennungen.contains($0.id) } }

        // Erst nach dem Herausnehmen nachschlagen — vorher zeigte die Stelle ins Leere.
        let stelle = anker.flatMap { kennung in p.eintraege.firstIndex { $0.id == kennung } }
            ?? hinterDerZelle(ziel, in: p)
        p.eintraege.insert(contentsOf: eingesetzt, at: stelle)
        guard zellenordnung(p.eintraege) != vorher else { return }

        let ausDerselbenZelle = geordnet[0].klasseId == ziel.klasse
            && geordnet[0].woche == ziel.woche
        planung = p
        auswahl = Set(eingesetzt.map(\.id))
        zielzelle = nil
        sichern()

        let anzahl = eingesetzt.count
        if verschieben, ausDerselbenZelle {
            melden(anzahl == 1 ? "Reihenfolge geändert."
                               : "Reihenfolge von \(anzahl) Vorhaben geändert.")
        } else {
            melden((anzahl == 1 ? "Vorhaben " : "\(anzahl) Vorhaben ")
                   + (verschieben ? "verschoben" : "eingefügt"))
        }
        if verfallen > 0 {
            melden(verschieben ? Planungsspeicher.zurueckgesetzt(verfallen)
                               : Planungsspeicher.kopieOhneDatum(verfallen))
        }
    }

    /// Was am Raster zu sehen ist: je Zelle die Reihenfolge der Kennungen —
    /// die Stelle in der Eintragsliste darf sich dabei verschieben.
    private func zellenordnung(_ eintraege: [Vorhaben]) -> [Zellenort: [String]] {
        var karte: [Zellenort: [String]] = [:]
        for eintrag in eintraege {
            karte[Zellenort(klasse: eintrag.klasseId, woche: eintrag.woche), default: []]
                .append(eintrag.id)
        }
        return karte
    }

    /// Die Stelle in der Eintragsliste hinter dem letzten Vorhaben dieser
    /// Zelle; bei leerer Zelle das Listenende.
    private func hinterDerZelle(_ ziel: Zellenort, in p: Planung) -> Int {
        let letzte = p.eintraege.lastIndex { $0.klasseId == ziel.klasse && $0.woche == ziel.woche }
        return letzte.map { $0 + 1 } ?? p.eintraege.count
    }

    /// Die Rückfrage hängt an der Hauptansicht — der Dialog ist hier nicht offen.
    func auswahlLoeschen() {
        let gewaehlt = angewaehlteVorhaben
        guard !gewaehlt.isEmpty else { return }
        if gewaehlt.count == 1 {
            vorhabenLoeschen(gewaehlt[0].id, ort: .hauptansicht)
            return
        }
        let kennungen = Set(gewaehlt.map(\.id))
        fragen("\(gewaehlt.count) Vorhaben endgültig entfernen?\n\n"
               + "Verknüpfte Dateien bleiben unangetastet auf der Festplatte.",
               bestaetigung: "Entfernen", gefahr: true, ort: .hauptansicht) { [weak self] in
            guard let self, var p = planung else { return }
            p.eintraege.removeAll { kennungen.contains($0.id) }
            planung = p
            auswahl = []
            if let inhalt = ablage,
               inhalt.vorhaben.contains(where: { kennungen.contains($0.id) }) {
                ablage = nil
            }
            sichern()
            melden("\(kennungen.count) Vorhaben entfernt.")
        }
    }
}
