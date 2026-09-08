// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Materialien, Links und der Zugriff auf Dateien ───────────────────────────
extension Planungsspeicher {

    // ── Materialien und Links im offenen Dialog ───────────────────────────

    /// Pfade prüfen, entdoppeln und relativ zum Basisordner ablegen.
    ///
    /// Die Obergrenze steht hier wie beim Lesen: Was darüber hinaus aufgenommen
    /// würde, läse `Planungsdatei` beim nächsten Start nicht mehr zurück.
    @discardableResult
    func materialAufnehmen(_ pfade: [String], in entwurf: inout VorhabenEntwurf) -> Int {
        let basis = planung?.basis ?? ""
        var neu = 0
        var unaufloesbar = 0
        var ohnePlatz = 0
        for roh in pfade {
            let absolut = Pfade.normalisieren(roh, basis: basis)
            if absolut.isEmpty { continue }
            if absolut.hasPrefix("~") { unaufloesbar += 1; continue }
            let gespeichert = Pfade.relativMachen(absolut, basis: basis)
            if entwurf.materialien.contains(where: { $0.pfad == gespeichert }) { continue }
            guard entwurf.materialien.count < Planungsdatei.maxMaterialien else {
                ohnePlatz += 1
                continue
            }
            entwurf.materialien.append(Material(titel: Pfade.dateiName(absolut), pfad: gespeichert))
            neu += 1
        }
        if neu > 0 {
            melden("\(neu)\(neu == 1 ? " Material verknüpft." : " Materialien verknüpft.")")
        }
        if unaufloesbar > 0 {
            melden("Ein Pfad mit „~“ ließ sich nicht auflösen.", .warnung)
        }
        if ohnePlatz > 0 {
            melden("Höchstens \(Planungsdatei.maxMaterialien) Materialien je Vorhaben — "
                   + "\(ohnePlatz) \(ohnePlatz == 1 ? "Datei blieb" : "Dateien blieben") "
                   + "außen vor.", .warnung)
        }
        return neu
    }

    /// Auch hier gilt die Grenze des Lesers, siehe `materialAufnehmen`.
    @discardableResult
    func linksAufnehmen(_ adressen: [String], in entwurf: inout VorhabenEntwurf) -> Int {
        var neu = 0
        var abgewiesen = 0
        var ohnePlatz = 0
        for roh in adressen where !roh.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let adresse = Weblinks.pruefen(roh) else { abgewiesen += 1; continue }
            if entwurf.links.contains(where: { $0.adresse == adresse }) { continue }
            guard entwurf.links.count < Planungsdatei.maxLinks else {
                ohnePlatz += 1
                continue
            }
            entwurf.links.append(Weblink(titel: Weblinks.name(adresse), adresse: adresse))
            neu += 1
        }
        if neu > 0 { melden(neu == 1 ? "Link hinterlegt." : "\(neu) Links hinterlegt.") }
        if ohnePlatz > 0 {
            melden("Höchstens \(Planungsdatei.maxLinks) Links je Vorhaben — "
                   + "\(ohnePlatz) \(ohnePlatz == 1 ? "Adresse blieb" : "Adressen blieben") "
                   + "außen vor.", .warnung)
        }
        if abgewiesen > 0 {
            melden(abgewiesen == 1
                   ? "Eine Adresse wurde abgewiesen — nur http und https sind zugelassen."
                   : "\(abgewiesen) Adressen wurden abgewiesen — nur http und https sind zugelassen.",
                   .warnung)
        }
        return neu
    }

    // ── Zugriff auf Dateien und Adressen ──────────────────────────────────

    func vollerPfad(_ pfad: String) -> String {
        Pfade.vollerPfad(pfad, basis: planung?.basis ?? "")
    }

    func imFinderZeigen(_ pfad: String, ort: Rueckfrageort = .hauptansicht) {
        switch Systemzugriff.imFinderZeigen(vollerPfad(pfad)) {
        case .erledigt: break
        case .fehlt(let text), .abgewiesen(let text): melden(text, .warnung)
        case .keinZugriff(let text):
            zugriffErbitten(fuer: vollerPfad(pfad), grund: text, ort: ort) { [weak self] in
                self?.imFinderZeigen(pfad, ort: ort)
            }
        }
    }

    func dateiOeffnen(_ pfad: String, ort: Rueckfrageort = .hauptansicht) {
        switch Systemzugriff.dateiOeffnen(vollerPfad(pfad)) {
        case .erledigt:
            break
        case .fehlt(let text):
            melden(text, .warnung)
        case .abgewiesen(let text):
            melden(text, .warnung)
            _ = Systemzugriff.imFinderZeigen(vollerPfad(pfad))
        case .keinZugriff(let text):
            zugriffErbitten(fuer: vollerPfad(pfad), grund: text, ort: ort) { [weak self] in
                self?.dateiOeffnen(pfad, ort: ort)
            }
        }
    }

    /// Der Ort ist der App in dieser Fassung noch nicht gezeigt worden:
    /// Rückfrage, Auswahl, dann dieselbe Handlung noch einmal. Deckt die Wahl
    /// den Pfad nicht, wird das benannt — nichts wird still verworfen.
    private func zugriffErbitten(fuer voll: String, grund: String, ort: Rueckfrageort,
                                 danach: @escaping @MainActor () -> Void) {
        let name = Pfade.dateiName(voll)
        fragen(grund + "\n\nDie App darf nur auf Orte zugreifen, die du ihr einmal gezeigt hast. "
               + "Im nächsten Dialog „\(name)“ auswählen — oder den Ordner, in dem es liegt; "
               + "die App merkt sich die Wahl.",
               bestaetigung: "Auswählen …", ort: ort) { [weak self] in
            guard let self, let gewaehlt = Systemzugriff.zugriffWaehlen(fuer: voll) else { return }
            freigabenNachfuehren()
            if Ordnerzugriff.zustaendig(fuer: voll) != nil {
                danach()
            } else {
                melden("„\(gewaehlt.lastPathComponent)“ enthält „\(name)“ nicht — bitte die "
                       + "Datei selbst oder ihren Ordner wählen.", .warnung)
            }
        }
    }

    func pfadKopieren(_ pfad: String) {
        melden(Systemzugriff.inZwischenablage(vollerPfad(pfad))
               ? "Pfad in der Zwischenablage — im Finder mit ⇧⌘G einsetzen."
               : "Kopieren nicht möglich.", .hinweis)
    }
}
