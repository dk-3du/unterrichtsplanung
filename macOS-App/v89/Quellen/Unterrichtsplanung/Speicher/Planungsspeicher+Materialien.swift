// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Materialien, Links und der Zugriff auf Dateien ───────────────────────────
extension Planungsspeicher {

    // ── Materialien und Links: der gemeinsame Kern von Blatt und Raster ────

    /// Was ein Aufnehmen ergab — die Zahlen, aus denen Blatt und Raster ihre Meldungen bilden (v88, AZ2).
    struct Aufnahme {
        var materialien = 0
        var unaufloesbar = 0
        var materialOhnePlatz = 0
        var links = 0
        var abgewiesen = 0
        var linkOhnePlatz = 0
        /// Neu verknüpfte Dateien an einem fremden Ort, mit dem Ort für die Warnung (E918–E920).
        var fremdeAblage: [(name: String, ort: String)] = []
    }

    /// Liegt die Datei an einem Ort, an dem eine andere App oder das System sie wieder löschen kann (E918, E920)? Mail
    /// legt einen Anhang beim Ziehen als fertige Datei in seinen Ordner „Mail Downloads“ (gemessen am 28.10.2026, E917).
    /// Gelesen wird die Kennung aus dem Pfad — mit und ohne App Sandbox gleich; der eigene Container zählt nicht
    /// (Z-AZ2-03).
    static func fremderAblageort(_ pfad: String, eigeneKennung: String? = Bundle.main.bundleIdentifier) -> String? {
        let teile = pfad.split(separator: "/").map(String.init)
        // …/Library/Containers/<Kennung>/… und …/Library/Group Containers/<Gruppe>/… — gleich, wo der Benutzerordner
        // liegt: unter /Users, /Network/Users oder verlegt (G1-02).
        if let stelle = teile.indices.first(where: { $0 + 2 < teile.count && teile[$0] == "Library"
                                                && ["Containers", "Group Containers"].contains(teile[$0 + 1]) }) {
            if teile[stelle + 1] == "Containers" {
                guard teile[stelle + 2] != eigeneKennung else { return nil }
                return teile[stelle + 2] == "com.apple.mail" ? "im Download-Ordner von Mail" : "im Ordner einer anderen App"
            }
            return "im Ordner einer anderen App"
        }
        if pfad.hasPrefix("/private/var/folders/") || pfad.hasPrefix("/var/folders/") { return "in einem temporären Ordner" }
        return nil
    }

    /// Der gemeinsame Kern von Blatt und Raster (v88, AZ2): Pfade prüfen, entdoppeln und relativ zum Basisordner
    /// ablegen. Die Obergrenze steht hier wie beim Lesen: Was darüber hinaus aufgenommen würde, läse `Planungsdatei` beim
    /// nächsten Start nicht mehr zurück. Die Pfade kommen aus dem Ablegen und der Dateiwahl und bleiben, wie sie sind —
    /// auch mit Leerraum am Ende des Namens (E960); nur der Titel wird zugeschnitten.
    static func materialKern(_ pfade: [String], basis: String, in materialien: inout [Material],
                             _ aufnahme: inout Aufnahme) {
        for roh in pfade {
            let absolut = Pfade.ausDemSystem(roh)
            if absolut.isEmpty { continue }
            // Ein Pfad aus dem System beginnt mit „/“; die Schranke bleibt für einen Aufrufer mit Text.
            if absolut.hasPrefix("~") { aufnahme.unaufloesbar += 1; continue }
            let gespeichert = Pfade.relativMachen(absolut, basis: basis)
            if materialien.contains(where: { $0.pfad == gespeichert }) { continue }
            guard materialien.count < Planungsdatei.maxMaterialien else {
                aufnahme.materialOhnePlatz += 1
                continue
            }
            // Zugeschnitten wie beim Sichern im Blatt (E208): Am Rasterweg geht der Titel ohne Blatt in die Planung —
            // Steuerzeichen meldete der Leser beim nächsten Start als bereinigt, ein Rand wiche vom Blatt ab (G1-01).
            // Ein Linktitel braucht das nicht: Die Prüfung der Adresse weist Steuerzeichen im Rechnernamen ab.
            let name = Pfade.dateiName(absolut)
            let titel = VorhabenEntwurf.bezeichnung(name, ersatz: name).text
            materialien.append(Material(titel: titel, pfad: gespeichert))
            aufnahme.materialien += 1
            if let ort = fremderAblageort(absolut) { aufnahme.fremdeAblage.append((titel, ort)) }
        }
    }

    /// Ebenso für Links; auch hier gilt die Grenze des Lesers.
    static func linkKern(_ adressen: [String], in links: inout [Weblink], _ aufnahme: inout Aufnahme) {
        for roh in adressen where !roh.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let adresse = Weblinks.pruefen(roh) else { aufnahme.abgewiesen += 1; continue }
            if links.contains(where: { $0.adresse == adresse }) { continue }
            guard links.count < Planungsdatei.maxLinks else {
                aufnahme.linkOhnePlatz += 1
                continue
            }
            links.append(Weblink(titel: Weblinks.name(adresse), adresse: adresse))
            aufnahme.links += 1
        }
    }

    /// Die Warnungen zu den Materialien — dieselben in Blatt und Raster.
    func materialWarnen(_ aufnahme: Aufnahme, ohneFremde: Bool = false) {
        if aufnahme.unaufloesbar > 0 {
            melden("Ein Pfad mit „~“ ließ sich nicht auflösen.", .warnung)
        }
        if aufnahme.materialOhnePlatz > 0 {
            let zahl = aufnahme.materialOhnePlatz
            melden("Höchstens \(Planungsdatei.maxMaterialien) Materialien je Vorhaben — "
                   + "\(zahl) \(zahl == 1 ? "Datei blieb" : "Dateien blieben") außen vor.", .warnung)
        }
        // E918–E920: verknüpft, aber mit dem Hinweis, dass die andere App oder das System die Datei löschen kann. Das
        // Ablegen auf eine Kachel nennt ihn in seiner eigenen Zeile (E923) und lässt ihn hier aus.
        if !ohneFremde, let satz = Self.fremderOrtSatz(aufnahme.fremdeAblage) {
            melden(satz + " — sicherer zuerst im Finder sichern und neu verknüpfen.", .warnung)
        }
    }

    /// „„logo.png“ liegt im Download-Ordner von Mail und kann dort verschwinden“. Mehrere: nur aus Mail „im Download-Ordner
    /// von Mail“, nur aus temporären Ordnern „in temporären Ordnern“, sonst „in Ordnern anderer Apps“ — ist ein
    /// temporärer darunter, „… oder des Systems“ (E919, E922).
    static func fremderOrtSatz(_ fremde: [(name: String, ort: String)]) -> String? {
        guard let erste = fremde.first else { return nil }
        guard fremde.count > 1 else { return "„\(erste.name)“ liegt \(erste.ort) und kann dort verschwinden" }
        let orte = Set(fremde.map(\.ort))
        let temporaer = "in einem temporären Ordner"
        let wo = orte == ["im Download-Ordner von Mail"] ? "im Download-Ordner von Mail"
            : orte == [temporaer] ? "in temporären Ordnern"
            : orte.contains(temporaer) ? "in Ordnern anderer Apps oder des Systems" : "in Ordnern anderer Apps"
        return "\(fremde.count) Dateien liegen \(wo) und können dort verschwinden"
    }

    /// Die Warnungen zu den Links — dieselben in Blatt und Raster.
    func linkWarnen(_ aufnahme: Aufnahme) {
        if aufnahme.linkOhnePlatz > 0 {
            let zahl = aufnahme.linkOhnePlatz
            melden("Höchstens \(Planungsdatei.maxLinks) Links je Vorhaben — "
                   + "\(zahl) \(zahl == 1 ? "Adresse blieb" : "Adressen blieben") außen vor.", .warnung)
        }
        if aufnahme.abgewiesen > 0 {
            let zahl = aufnahme.abgewiesen
            melden(zahl == 1
                   ? "Eine Adresse wurde abgewiesen — nur http und https sind zugelassen."
                   : "\(zahl) Adressen wurden abgewiesen — nur http und https sind zugelassen.",
                   .warnung)
        }
    }

    /// Pfade ins Blatt: der Kern und die Meldungen wie seit jeher.
    @discardableResult
    func materialAufnehmen(_ pfade: [String], in entwurf: inout VorhabenEntwurf) -> Int {
        var aufnahme = Aufnahme()
        Self.materialKern(pfade, basis: planung?.basis ?? "", in: &entwurf.materialien, &aufnahme)
        let neu = aufnahme.materialien
        if neu > 0 {
            melden("\(neu)\(neu == 1 ? " Material verknüpft." : " Materialien verknüpft.")")
        }
        materialWarnen(aufnahme)
        return neu
    }

    /// Links ins Blatt: der Kern und die Meldungen wie seit jeher.
    @discardableResult
    func linksAufnehmen(_ adressen: [String], in entwurf: inout VorhabenEntwurf) -> Int {
        var aufnahme = Aufnahme()
        Self.linkKern(adressen, in: &entwurf.links, &aufnahme)
        let neu = aufnahme.links
        if neu > 0 { melden(neu == 1 ? "Link hinterlegt." : "\(neu) Links hinterlegt.") }
        linkWarnen(aufnahme)
        return neu
    }

    // ── Ablegen von außen auf ein Vorhaben im Raster (v88, AZ2; E904–E907, E914, E916, E918) ──

    /// Dateien und Links, auf eine Kachel gezogen: ein Schritt — Dateien und Ordner nach „Material“, Webadressen nach
    /// „Links“ (E905), mit Entdoppeln und Grenzen des Blatts. Die Dateien bekommen ihr Lesezeichen wie im Blatt. Der
    /// Schritt heißt nach dem, was neu dazukam (E916, E921); die Meldung nennt das Vorhaben mit Zeile, Fach und Woche
    /// vorn, weil kein Blatt es zeigt (E907, E914), eine fremde Ablage in derselben Zeile (E923); die übrigen Warnungen
    /// sind die des Blatts. Ändert sich nichts, gibt es keinen Schritt.
    @discardableResult
    func ablegen(dateien: [URL], links: [String], auf id: String) -> Bool {
        guard let stand = planung, let vorhaben = stand.eintraege.first(where: { $0.id == id }),
              !dateien.isEmpty || !links.isEmpty else { return false }
        zugriff.merken(alle: dateien)
        // Erst an Kopien, damit der Schritt nach dem heißt, was neu dazukam (E921): eine schon verknüpfte Datei und ein
        // neuer Link sind „Link ablegen“ — wie die Meldung.
        var aufnahme = Aufnahme()
        var materialien = vorhaben.materialien
        var verweise = vorhaben.links
        Self.materialKern(dateien.map(\.path), basis: stand.basis, in: &materialien, &aufnahme)
        Self.linkKern(links, in: &verweise, &aufnahme)
        let name = aufnahme.materialien > 0 ? Schrittname.materialAblegen
            : aufnahme.links == 1 ? Schrittname.linkAblegen : Schrittname.linksAblegen
        let geaendert = aendern(name) { planung in
            guard let stelle = planung.eintraege.firstIndex(where: { $0.id == id }) else { return }
            planung.eintraege[stelle].materialien = materialien
            planung.eintraege[stelle].links = verweise
        }
        // Eine fremde Ablage steht in derselben Zeile wie die Bestätigung — sonst löste die Warnung sie sofort ab (E923).
        if let meldung = Self.ablagemeldung(vorhaben, in: stand, aufnahme) {
            if let satz = Self.fremderOrtSatz(aufnahme.fremdeAblage) {
                melden(String(meldung.dropLast()) + " — " + satz + "; sicherer zuerst im Finder sichern und neu verknüpfen.",
                       .warnung)
            } else {
                melden(meldung)
            }
        }
        materialWarnen(aufnahme, ohneFremde: true)
        linkWarnen(aufnahme)
        return geaendert
    }

    /// „„Photosynthese“ (F5b Biologie · KW 35): 2 Materialien verknüpft, 1 Link hinterlegt.“ (E907, E914) — die Zeile mit
    /// Fach, wo eines eingetragen ist. Kam nichts Neues und auch keine Warnung: „…: nichts Neues — alles war schon
    /// verknüpft.“ Sagen die Warnungen, was war, steht keine eigene Zeile.
    static func ablagemeldung(_ vorhaben: Vorhaben, in planung: Planung, _ aufnahme: Aufnahme) -> String? {
        let zeile = planung.klasse(vorhaben.klasseId).map { $0.fach.isEmpty ? $0.name : "\($0.name) \($0.fach)" }
        let woche = planung.wochenListe.indices.contains(vorhaben.woche)
            ? planung.wochenListe[vorhaben.woche].beschriftung : nil
        let wo = [zeile, woche].compactMap { $0 }.joined(separator: " · ")
        let kopf = "„\(vorhaben.anzeigeTitel)“" + (wo.isEmpty ? "" : " (\(wo))") + ": "
        var teile: [String] = []
        if aufnahme.materialien > 0 {
            teile.append("\(aufnahme.materialien) \(aufnahme.materialien == 1 ? "Material" : "Materialien") verknüpft")
        }
        if aufnahme.links > 0 { teile.append("\(aufnahme.links) \(aufnahme.links == 1 ? "Link" : "Links") hinterlegt") }
        if !teile.isEmpty { return kopf + teile.joined(separator: ", ") + "." }
        let warnung = aufnahme.unaufloesbar + aufnahme.materialOhnePlatz + aufnahme.linkOhnePlatz + aufnahme.abgewiesen > 0
        return warnung ? nil : kopf + "nichts Neues — alles war schon verknüpft."
    }

    /// Ein Material der Website als Link (E179, E180): Bezeichnung ist der
    /// Kacheltitel, die Adresse ist schon geprüft — geprüft wird sie trotzdem
    /// noch einmal, die Schranke gilt an jeder Stelle. Liegt die Adresse schon
    /// am Vorhaben, ist nichts zu tun und die Antwort trotzdem ja. Die
    /// Höchstzahl meldet sich wie bei `linksAufnehmen`.
    @discardableResult
    func linkAufnehmen(titel: String, adresse roh: String, in entwurf: inout VorhabenEntwurf) -> Bool {
        guard let adresse = Weblinks.pruefen(roh) else { return false }
        if entwurf.links.contains(where: { $0.adresse == adresse }) { return true }
        guard entwurf.links.count < Planungsdatei.maxLinks else {
            melden("Höchstens \(Planungsdatei.maxLinks) Links je Vorhaben — die Adresse blieb außen vor.",
                   .warnung)
            return false
        }
        // Bereinigt wie beim Dateileser — der Titel kommt aus dem Netz.
        let bezeichnung = Materialkatalog.zeile(titel)
        entwurf.links.append(Weblink(titel: bezeichnung.isEmpty ? Weblinks.name(adresse) : bezeichnung,
                                     adresse: adresse))
        return true
    }

    /// Der zweite Klick auf eine hinterlegte Kachel (E179): Der Link mit dieser
    /// Adresse geht wieder aus dem Entwurf. Sagt, ob einer da war.
    @discardableResult
    func linkEntfernen(adresse: String, in entwurf: inout VorhabenEntwurf) -> Bool {
        let vorher = entwurf.links.count
        entwurf.links.removeAll { $0.adresse == adresse }
        return entwurf.links.count < vorher
    }

    // ── Zugriff auf Dateien und Adressen ──────────────────────────────────

    func vollerPfad(_ pfad: String) -> String {
        Pfade.vollerPfad(pfad, basis: planung?.basis ?? "")
    }

    func imFinderZeigen(_ pfad: String, ort: Rueckfrageort = .hauptansicht) {
        switch Systemzugriff.imFinderZeigen(vollerPfad(pfad), zugriff: zugriff) {
        case .erledigt: break
        case .fehlt(let text), .abgewiesen(let text): melden(text, .warnung)
        case .keinZugriff(let text):
            zugriffErbitten(fuer: vollerPfad(pfad), grund: text, ort: ort) { [weak self] in
                self?.imFinderZeigen(pfad, ort: ort)
            }
        }
    }

    func dateiOeffnen(_ pfad: String, ort: Rueckfrageort = .hauptansicht) {
        switch Systemzugriff.dateiOeffnen(vollerPfad(pfad), zugriff: zugriff) {
        case .erledigt:
            break
        case .fehlt(let text):
            melden(text, .warnung)
        case .abgewiesen(let text):
            melden(text, .warnung)
            _ = Systemzugriff.imFinderZeigen(vollerPfad(pfad), zugriff: zugriff)
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
        fragen(grund + "\n\nDie App darf nur auf Orte zugreifen, die ihr einmal gezeigt wurden. "
               + "Im nächsten Dialog „\(name)“ auswählen — oder den Ordner, in dem es liegt; "
               + "die App merkt sich die Wahl.",
               bestaetigung: "Auswählen …", ort: ort) { [weak self] in
            guard let self else { return }
            Systemzugriff.zugriffWaehlen(fuer: voll, zugriff: zugriff) { [weak self] gewaehlt in
                guard let self, let gewaehlt else { return }
                freigabenNachfuehren()
                if zugriff.zustaendig(fuer: voll) != nil {
                    danach()
                } else {
                    melden("„\(gewaehlt.lastPathComponent)“ enthält „\(name)“ nicht — bitte die "
                           + "Datei selbst oder ihren Ordner wählen.", .warnung)
                }
            }
        }
    }

    func pfadKopieren(_ pfad: String) {
        melden(Systemzugriff.inZwischenablage(vollerPfad(pfad))
               ? "Pfad in der Zwischenablage — im Finder mit ⇧⌘G einsetzen."
               : "Kopieren nicht möglich.", .hinweis)
    }
}
