// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct Planungsfehler: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

/// Lesen und Schreiben der Planungsdatei.
///
/// Gelesen wird **nachsichtig und geprüft**: Eine fremde oder beschädigte Datei
/// darf die Planung nicht beschädigen und erst recht nichts ausführen.
enum Planungsdatei {

    // ── Obergrenzen beim Lesen ────────────────────────────────────────────
    // Gehören sachlich neben `Kennwerte.maxKlassen` (Modell/Planung.swift).
    // Großzügig bemessen: Gekappt wird nur eine fremde oder verdorbene Datei,
    // eine wirkliche Planung bleibt weit darunter.

    /// Vorhaben je Datei; 75 Zeilen mal 52 Wochen sind 3.900 Zellen.
    static let maxVorhaben = 20_000
    /// Materialien je Vorhaben.
    static let maxMaterialien = 200
    /// Links je Vorhaben.
    static let maxLinks = 200
    /// Zeichen in Beschreibung und Kommentar.
    static let maxTextlaenge = 20_000
    /// Zeichen in Titeln, Namen und Kennungen.
    static let maxNamenslaenge = 500
    /// Zeichen in Dateiverweisen. macOS lässt einen Pfad bis 1024 Byte zu;
    /// enger gekappt zeigte der Verweis nach dem nächsten Öffnen ins Leere.
    static let maxPfadlaenge = 1_024
    /// Ferien- und Sperrzeiträume je Datei. Jeder kostet den Rasteraufbau
    /// einen Vergleich je Schultag; ohne Grenze wächst er quadratisch.
    static let maxFerien = 2_000
    static let maxSperrzeiten = 2_000
    /// Einzeln freigestellte Tage; 52 Wochen haben 364.
    static let maxFreieTage = 4_000
    /// Freie Zellen; mehr unterscheidbare gibt das Raster nicht her.
    static let maxFreieZellen = Kennwerte.wochenMax * Kennwerte.maxKlassen
    /// Festgelegte Fachfarben je Datei. Großzügig über `Kennwerte.maxKlassen`,
    /// weil eine festgelegte Farbe ihr Fach überdauert; die Liste im
    /// Klassendialog führt jede einzelne und wird bei jedem Neuzeichnen gebaut.
    static let maxFachfarben = 500

    /// Was die Datei nannte und die Planung nicht übernommen hat.
    ///
    /// Der Leser ist nachsichtig und kappt; ohne Bilanz bliebe das unbemerkt,
    /// und die nächste Sicherung schriebe den verkürzten Stand zurück — eine
    /// Grenze, die nur beim Lesen gälte, wäre eine Datenfalle.
    struct Verlustbilanz: Equatable, Sendable {
        var klassen = 0
        var vorhaben = 0
        var materialien = 0
        var links = 0
        var ferien = 0
        var sperrzeiten = 0
        var freieTage = 0
        var freieZellen = 0
        var fachfarben = 0
        /// Titel, Namen und Texte, die auf ihre Höchstlänge gekürzt wurden.
        var gekuerzteTexte = 0

        var istLeer: Bool {
            klassen == 0 && vorhaben == 0 && materialien == 0 && links == 0
                && ferien == 0 && sperrzeiten == 0 && freieTage == 0
                && freieZellen == 0 && fachfarben == 0 && gekuerzteTexte == 0
        }

        /// Das Verworfene in Worten, feste Reihenfolge. Gekürzte Texte stehen
        /// nicht darin — sie sind beschnitten, nicht verworfen.
        var verworfenes: [String] {
            var teile: [String] = []
            if klassen > 0 { teile.append(wort(klassen, "Zeile", "Zeilen")) }
            if vorhaben > 0 { teile.append(wort(vorhaben, "Vorhaben", "Vorhaben")) }
            if ferien > 0 {
                teile.append(wort(ferien, "Ferienzeitraum", "Ferienzeiträume"))
            }
            if sperrzeiten > 0 {
                teile.append(wort(sperrzeiten, "Sperrzeitraum", "Sperrzeiträume"))
            }
            if freieTage > 0 {
                teile.append(wort(freieTage, "freier Tag", "freie Tage"))
            }
            if freieZellen > 0 {
                teile.append(wort(freieZellen, "freie Zelle", "freie Zellen"))
            }
            if fachfarben > 0 {
                teile.append(wort(fachfarben, "Fachfarbe", "Fachfarben"))
            }
            if materialien > 0 {
                teile.append(wort(materialien, "Material", "Materialien"))
            }
            if links > 0 { teile.append(wort(links, "Link", "Links")) }
            return teile
        }

        /// Die gekürzten Texte in Worten, sonst `nil`.
        var gekuerztes: String? {
            gekuerzteTexte == 0
                ? nil
                : wort(gekuerzteTexte, "gekürzter Text", "gekürzte Texte")
        }

        private func wort(_ anzahl: Int, _ einzahl: String,
                          _ mehrzahl: String) -> String {
            "\(anzahl) " + (anzahl == 1 ? einzahl : mehrzahl)
        }
    }

    // ── Lesen ─────────────────────────────────────────────────────────────

    static func lesen(_ daten: Data) throws -> Planung {
        try lesenMitBilanz(daten).planung
    }

    /// Wie `lesen`, gibt aber zusätzlich heraus, was dabei verlorenging.
    static func lesenMitBilanz(_ daten: Data) throws
        -> (planung: Planung, bilanz: Verlustbilanz) {
        let roh: Any
        do {
            roh = try JSONSerialization.jsonObject(with: daten, options: [])
        } catch {
            throw Planungsfehler(text: "Die Datei ist kein lesbares JSON.")
        }
        return try pruefenMitBilanz(roh)
    }

    static func pruefen(_ roh: Any) throws -> Planung {
        try pruefenMitBilanz(roh).planung
    }

    static func pruefenMitBilanz(_ roh: Any) throws
        -> (planung: Planung, bilanz: Verlustbilanz) {
        guard let d = roh as? [String: Any] else {
            throw Planungsfehler(text: "Die Datei ist keine gültige Planung.")
        }
        let typ = text(d["typ"])
        if !typ.isEmpty, typ != Kennwerte.dateiTyp {
            throw Planungsfehler(text: "Die Datei gehört zu einer anderen Anwendung.")
        }
        if typ.isEmpty, !(d["klassen"] is [Any]), d["wochen"] == nil {
            throw Planungsfehler(text: "Die Datei enthält keine Unterrichtsplanung.")
        }

        var bilanz = Verlustbilanz()
        // Leer → Ersatz, zu lang → gekürzt. Gezählt wird als Bezugswert der
        // umschließenden `bilanz`; ein `inout`-Zähler verstieße dort, wo zwei
        // Aufrufe in einem Ausdruck stehen, gegen die Ausschließlichkeit.
        // `sonst` als `@autoclosure`: Ein geschachtelter Rückfall zählte sein
        // eigenes Kürzen sonst auch dann mit, wenn sein Wert verworfen wird.
        func nichtLeer(_ wert: Any?, sonst ersatz: @autoclosure () -> String,
                       hoechstens grenze: Int = maxNamenslaenge) -> String {
            let t = text(wert)
            let voll = t.isEmpty ? ersatz() : t
            guard voll.count > grenze else { return voll }
            bilanz.gekuerzteTexte += 1
            return String(voll.prefix(grenze))
        }

        let altePalette = (ganzzahl(d["version"]) ?? 0) < 2

        let jetzt = Zeitrechnung.jetztAlsZeitstempel()
        let startRoh = (d["start"].flatMap { Tag(iso: text($0)) }) ?? Tag.heute.montagDerWoche
        // Wie `parseInt(d.wochen, 10) || 52`: auch die Null fällt auf den Standard.
        let gelesen = ganzzahl(d["wochen"]) ?? 0
        let wochen = min(Kennwerte.wochenMax,
                         max(1, gelesen == 0 ? Kennwerte.wochenStandard : gelesen))

        let roheTage = d["frei"] as? [Any] ?? []
        bilanz.freieTage = max(0, roheTage.count - maxFreieTage)
        var freieTage = Set<Tag>()
        for fall in roheTage.prefix(maxFreieTage) {
            guard let tag = Tag(iso: text(fall)) else {
                bilanz.freieTage += 1
                continue
            }
            freieTage.insert(tag)
        }

        // Ein Pfad, kein Name: an `maxPfadlaenge` gemessen.
        let basis = nichtLeer(d["basis"],
                              sonst: nichtLeer(d["basisordner"], sonst: "",
                                               hoechstens: maxPfadlaenge),
                              hoechstens: maxPfadlaenge)

        var planung = Planung(
            titel: nichtLeer(d["titel"], sonst: "Unterrichtsplanung"),
            erstellt: nichtLeer(d["erstellt"], sonst: jetzt),
            geaendert: nichtLeer(d["geaendert"], sonst: jetzt),
            basis: basis,
            start: startRoh.montagDerWoche,
            wochen: wochen,
            ersterSchultag: d["ersterSchultag"].flatMap { Tag(iso: text($0)) },
            frei: freieTage,
            ferien: [], fachfarben: [:], klassen: [], zellenfrei: [], eintraege: [])

        let roheFerien = d["ferien"] as? [Any] ?? []
        bilanz.ferien = max(0, roheFerien.count - maxFerien)
        for fall in roheFerien.prefix(maxFerien) {
            guard let f = fall as? [String: Any],
                  let von = Tag(iso: text(f["von"])), let bis = Tag(iso: text(f["bis"]))
            else {
                bilanz.ferien += 1
                continue
            }
            // Roh übernommen, auch wenn `bis` vor `von` liegt: Gedreht würde ein
            // Zeitraum, den die App als „Ende vor Beginn“ ausweist und den
            // `ungueltig` überall aussortiert, beim nächsten Öffnen stillschweigend
            // wirksam. Dieselbe Datei muss vor und nach einem Neustart dasselbe
            // bedeuten.
            planung.ferien.append(Ferienzeitraum(
                id: nichtLeer(f["id"], sonst: Kennung.neu("f")),
                name: nichtLeer(f["name"], sonst: "Ferien"),
                von: von, bis: bis))
        }

        let roheSperren = d["sperrzeiten"] as? [Any] ?? []
        bilanz.sperrzeiten = max(0, roheSperren.count - maxSperrzeiten)
        for fall in roheSperren.prefix(maxSperrzeiten) {
            guard let s = fall as? [String: Any],
                  let von = Tag(iso: text(s["von"])), let bis = Tag(iso: text(s["bis"]))
            else {
                bilanz.sperrzeiten += 1
                continue
            }
            // Ungedreht wie die Ferien.
            planung.sperrzeiten.append(Sperrzeitraum(
                id: nichtLeer(s["id"], sonst: Kennung.neu("s")),
                name: nichtLeer(s["name"], sonst: "Sperrzeitraum"),
                von: von, bis: bis,
                // Geprüft wird weiter unten, sobald die Zeilen gelesen sind.
                kurse: (s["kurse"] as? [Any] ?? []).map(text)))
        }

        if let karte = d["fachfarben"] as? [String: Any] {
            // Sortiert gelesen: Welche Einträge über der Grenze wegfallen und
            // welcher zweier Schlüssel mit gleichem Fachschlüssel gilt, wäre
            // über eine Swift-Karte sonst von Lauf zu Lauf verschieden.
            let roheFaecher = karte.keys.sorted()
            bilanz.fachfarben = max(0, roheFaecher.count - maxFachfarben)
            for fach in roheFaecher.prefix(maxFachfarben) {
                // Gekappt wie der Fachname einer Zeile, damit beide nach dem
                // Kürzen noch zueinanderfinden.
                let schluessel = Farbwelt.fachSchluessel(nichtLeer(fach, sonst: ""))
                let roh = text(karte[fach])
                let wert = altePalette ? Altfarben.tonSchluessel(zuFamilie: roh) : roh
                if !schluessel.isEmpty, let wert, Farbwelt.tonNachSchluessel[wert] != nil {
                    planung.fachfarben[schluessel] = wert
                }
            }
        }

        // Doppelte Kennungen: Sonst erschiene jedes Vorhaben in zwei Zeilen.
        var idsBelegt = Set<String>()
        let roheKlassen = d["klassen"] as? [Any] ?? []
        bilanz.klassen = max(0, roheKlassen.count - Kennwerte.maxKlassen)
        for (stelle, fall) in roheKlassen.prefix(Kennwerte.maxKlassen).enumerated() {
            let k = fall as? [String: Any] ?? [:]
            let name = nichtLeer(k["name"], sonst: "Klasse/Kurs \(stelle + 1)")
            let fach = nichtLeer(k["fach"], sonst: "")
            let gespeichert = strengeGanzzahl(k["farbe"])
            let farbe = (altePalette
                         ? gespeichert.flatMap { Altfarben.tonSchluessel(zuPlatz: $0) }
                                      .flatMap(Farbwelt.stelle)
                         : gespeichert.flatMap { Farbwelt.istGueltig($0) ? $0 : nil })
                ?? Farbwelt.ohneFarbe

            var id = text(k["id"]).trimmingCharacters(in: .whitespaces)
            if id.isEmpty { id = Kennung.neu("k") }
            while idsBelegt.contains(id) { id = Kennung.neu("k") }
            idsBelegt.insert(id)

            // Pfade, keine Namen: siehe `basis`.
            let verwaltung = nichtLeer(k["verwaltung"], sonst: "",
                                       hoechstens: maxPfadlaenge)
            let curriculum = nichtLeer(k["curriculum"], sonst: "",
                                       hoechstens: maxPfadlaenge)
            // Wie `farbe`: Was keinen Wochentag Montag bis Freitag nennt,
            // fällt still weg — eine Menge kennt keine Dubletten, und die
            // Ansichtsfassung liest wortgleich (`leser_pruefen.py`).
            let roheTage = k["unterrichtstage"] as? [Any] ?? []
            let unterrichtstage = Set(roheTage.compactMap { wert -> Wochentag? in
                ganzzahl(wert).flatMap(Wochentag.init(rawValue:))
            })

            planung.klassen.append(Klasse(id: id, name: name, fach: fach,
                                          notiz: nichtLeer(k["notiz"], sonst: ""),
                                          farbe: farbe,
                                          // Ohne gültige Farbe sagt das Merkmal nichts aus.
                                          farbeManuell: Farbwelt.istGueltig(farbe)
                                              && wahrheit(k["farbeManuell"]),
                                          verwaltung: verwaltung,
                                          curriculum: curriculum,
                                          unterrichtstage: unterrichtstage))
        }
        // Erst jetzt, mit allen Zeilen und Fachfarben beisammen.
        planung.farbenVervollstaendigen()

        let bekannt = idsBelegt

        for stelle in planung.sperrzeiten.indices {
            let genannt = Set(planung.sperrzeiten[stelle].kurse).intersection(bekannt)
            planung.sperrzeiten[stelle].kurse = planung.klassen.map(\.id).filter(genannt.contains)
        }

        let roheZellen = d["zellenfrei"] as? [Any] ?? []
        bilanz.freieZellen = max(0, roheZellen.count - maxFreieZellen)
        for fall in roheZellen.prefix(maxFreieZellen) {
            guard let z = fall as? [String: Any] else {
                bilanz.freieZellen += 1
                continue
            }
            let klasseId = text(z["klasseId"])
            guard bekannt.contains(klasseId), let woche = Tag(iso: text(z["woche"]))
            else {
                bilanz.freieZellen += 1
                continue
            }
            planung.zellenfrei.insert(FreieZelle(klasseId: klasseId, woche: woche))
        }

        var vorhabenBelegt = Set<String>()
        let roheVorhaben = d["eintraege"] as? [Any] ?? []
        bilanz.vorhaben = max(0, roheVorhaben.count - maxVorhaben)
        for fall in roheVorhaben.prefix(maxVorhaben) {
            guard let e = fall as? [String: Any] else {
                bilanz.vorhaben += 1
                continue
            }
            let klasseId = text(e["klasseId"])
            guard bekannt.contains(klasseId) else {
                bilanz.vorhaben += 1
                continue
            }
            guard let woche = ganzzahl(e["woche"]), woche >= 0, woche < planung.wochen
            else {
                bilanz.vorhaben += 1
                continue
            }

            let roheMaterialien = e["materialien"] as? [Any] ?? []
            let materialien: [Material] = roheMaterialien
                .prefix(maxMaterialien).compactMap { fall in
                    guard let m = fall as? [String: Any] else { return nil }
                    let roh = text(m["pfad"])
                    guard !roh.isEmpty else { return nil }
                    let pfad = Pfade.zusammenfassen(roh, basis: planung.basis)
                    guard !pfad.isEmpty else { return nil }
                    return Material(titel: nichtLeer(m["titel"],
                                                     sonst: Pfade.dateiName(pfad)),
                                    pfad: pfad)
                }

            bilanz.materialien += roheMaterialien.count - materialien.count

            let roheLinks = e["links"] as? [Any] ?? []
            let links: [Weblink] = roheLinks
                .prefix(maxLinks).compactMap { fall in
                    guard let l = fall as? [String: Any],
                          let adresse = Weblinks.pruefen(text(l["url"]))
                    else { return nil }
                    return Weblink(titel: nichtLeer(l["titel"],
                                                    sonst: Weblinks.name(adresse)),
                                   adresse: adresse)
                }

            bilanz.links += roheLinks.count - links.count

            // Doppelte Kennung: Die Auswahlspanne bräche ab, Löschen träfe beide.
            var id = text(e["id"]).trimmingCharacters(in: .whitespaces)
            if id.isEmpty { id = Kennung.neu("e") }
            while vorhabenBelegt.contains(id) { id = Kennung.neu("e") }
            vorhabenBelegt.insert(id)

            planung.eintraege.append(Vorhaben(
                id: id,
                klasseId: klasseId, woche: woche,
                titel: nichtLeer(e["titel"], sonst: ""),
                text: nichtLeer(e["text"],
                                sonst: nichtLeer(e["beschreibung"], sonst: "",
                                                 hoechstens: maxTextlaenge),
                                hoechstens: maxTextlaenge),
                erledigt: wahrheit(e["erledigt"]),
                materialien: materialien, links: links,
                pruefung: wahrheit(e["pruefung"]),
                pruefungstag: Tag(iso: text(e["pruefungstag"])),
                datum: Tag(iso: text(e["datum"])),
                dringend: wahrheit(e["dringend"]),
                kommentar: nichtLeer(e["kommentar"], sonst: "",
                                     hoechstens: maxTextlaenge),
                statusGeaendert: text(e["statusGeaendert"])))
        }

        return (planung, bilanz)
    }

    // ── Schreiben ─────────────────────────────────────────────────────────

    static func schreiben(_ planung: Planung) throws -> Data {
        let daten = try JSONSerialization.data(
            withJSONObject: alsObjekt(planung),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard let text = String(data: daten, encoding: .utf8) else { return daten }
        // JSONSerialization schreibt leere Sammlungen mehrzeilig; Umbrüche in
        // Zeichenketten stehen als \n und werden vom Zusammenziehen nicht getroffen.
        let aufgeraeumt = text
            .ersetzen(muster: #"\[\s*\n\s*\]"#, durch: "[]")
            .ersetzen(muster: #"\{\s*\n\s*\}"#, durch: "{}")
        return aufgeraeumt.data(using: .utf8) ?? daten
    }

    static func alsObjekt(_ p: Planung) -> [String: Any] {
        [
            "typ": Kennwerte.dateiTyp,
            "version": Kennwerte.dateiVersion,
            "titel": p.titel,
            "erstellt": p.erstellt,
            "geaendert": p.geaendert,
            "basis": p.basis,
            "start": p.start.iso,
            "wochen": p.wochen,
            // Leer statt fehlend: Die Ansichtsfassung liest dasselbe Feld.
            "ersterSchultag": p.ersterSchultag?.iso ?? "",
            "frei": p.frei.map(\.iso).sorted(),
            "ferien": p.ferien.map { ["id": $0.id, "name": $0.name, "von": $0.von.iso, "bis": $0.bis.iso] },
            "sperrzeiten": p.sperrzeiten.map {
                ["id": $0.id, "name": $0.name, "von": $0.von.iso, "bis": $0.bis.iso,
                 "kurse": $0.kurse]
            },
            "fachfarben": p.fachfarben,
            "klassen": p.klassen.map {
                ["id": $0.id, "name": $0.name, "fach": $0.fach, "notiz": $0.notiz,
                 "farbe": $0.farbe, "farbeManuell": $0.farbeManuell,
                 "verwaltung": $0.verwaltung, "curriculum": $0.curriculum,
                 "unterrichtstage": $0.unterrichtstage.gespeichert]
            },
            "zellenfrei": p.zellenfrei
                .sorted { ($0.klasseId, $0.woche.iso) < ($1.klasseId, $1.woche.iso) }
                .map { ["klasseId": $0.klasseId, "woche": $0.woche.iso] },
            "eintraege": p.eintraege.map { e in
                [
                    "id": e.id, "klasseId": e.klasseId, "woche": e.woche,
                    "titel": e.titel, "text": e.text, "erledigt": e.erledigt,
                    "materialien": e.materialien.map { ["titel": $0.titel, "pfad": $0.pfad] },
                    "links": e.links.map { ["titel": $0.titel, "url": $0.adresse] },
                    "pruefung": e.pruefung,
                    "pruefungstag": e.pruefungstag?.iso ?? "",
                    "datum": e.datum?.iso ?? "",
                    "dringend": e.dringend,
                    "kommentar": e.kommentar,
                    "statusGeaendert": e.statusGeaendert,
                ] as [String: Any]
            },
        ]
    }

    /// Aus dem Titel, entschärft und datiert.
    static func exportName(titel: String, endung: String = "json") -> String {
        entschaerft(titel) + "_" + Tag.heute.iso + "." + endung
    }

    /// Derselbe Name **ohne Datum** — für die Sicherungskopie beim Beenden, auf
    /// die die iPad-Ansicht dauerhaft zeigen können muss.
    static func festerName(titel: String, endung: String = "json") -> String {
        entschaerft(titel) + "." + endung
    }

    /// Dateisysteme nehmen 255 Byte je Namensbestandteil; ein Titel darf bis
    /// `maxNamenslaenge` lang sein. Gekürzt wird auf Bytes, nicht auf Zeichen,
    /// und an einer Zeichengrenze — ein halbes Zeichen wäre kein Name mehr.
    static let maxDateinamensbytes = 200

    /// Schrägstriche und Doppelpunkte heraus, Leerzeichen zu Unterstrichen.
    private static func entschaerft(_ titel: String) -> String {
        var sauber = titel.ersetzen(muster: #"[/\\:]+"#, durch: "-")
        sauber = sauber.ersetzen(muster: #"[^\p{L}\p{N} _-]+"#, durch: "")
        sauber = sauber.trimmingCharacters(in: .whitespaces).ersetzen(muster: #"\s+"#, durch: "_")
        while sauber.utf8.count > maxDateinamensbytes { sauber.removeLast() }
        return sauber.isEmpty ? "Unterrichtsplanung" : sauber
    }

    // ── Nachsichtiges Lesen einzelner Werte ───────────────────────────────

    private static func istWahrheitswert(_ wert: Any?) -> Bool {
        guard let z = wert as? NSNumber else { return false }
        return CFGetTypeID(z) == CFBooleanGetTypeID()
    }

    /// Auch von `Statusdatei` benutzt: Dieselbe Eintragsform liest die
    /// Ansichtsfassung mit `textwert` — beide Leser müssen gleich deuten.
    static func text(_ wert: Any?) -> String {
        if istWahrheitswert(wert) { return (wert as? NSNumber)?.boolValue == true ? "true" : "false" }
        switch wert {
        case let s as String: return s
        case let z as NSNumber: return z.stringValue
        default: return ""
        }
    }

    /// Wie `parseInt`: nimmt auch Zahlen in Zeichenkettenform an.
    private static func ganzzahl(_ wert: Any?) -> Int? {
        if istWahrheitswert(wert) { return nil }
        switch wert {
        case let z as NSNumber:
            let d = z.doubleValue.rounded(.towardZero)
            guard d.isFinite, abs(d) < 1e15 else { return nil }
            return Int(d)
        case let s as String:
            // Genau `/^\s*[+-]?\d+/` der Ansichtsfassung: ein Vorzeichen nur
            // ganz vorn, danach Ziffern. Nähme der Präfix das Vorzeichen an
            // jeder Stelle mit, ergäbe "1-2" hier nil und dort 1.
            var rest = Substring(s.trimmingCharacters(in: .whitespaces))
            var vorzeichen = ""
            if let erstes = rest.first, erstes == "+" || erstes == "-" {
                vorzeichen = String(erstes)
                rest = rest.dropFirst()
            }
            let ziffern = rest.prefix { $0.isASCII && $0.isNumber }
            return ziffern.isEmpty ? nil : Int(vorzeichen + ziffern)
        default:
            return nil
        }
    }

    /// Wie `Number.isInteger`: nur echte ganze Zahlen — Wahrheitswerte liefert
    /// JSONSerialization ebenfalls als `NSNumber`.
    private static func strengeGanzzahl(_ wert: Any?) -> Int? {
        guard !istWahrheitswert(wert), let z = wert as? NSNumber else { return nil }
        let d = z.doubleValue
        guard d.isFinite, d == d.rounded(), abs(d) < 1e15 else { return nil }
        return Int(d)
    }

    /// `true`, jede Zahl außer 0 und jede nichtleere Zeichenkette gelten —
    /// wie `wahrheit` in der Ansichtsfassung. Auch von `Statusdatei` benutzt.
    static func wahrheit(_ wert: Any?) -> Bool {
        switch wert {
        case let z as NSNumber: return z.doubleValue != 0
        case let s as String: return !s.isEmpty
        default: return false
        }
    }
}

extension String {
    func ersetzen(muster: String, durch ersatz: String) -> String {
        guard let ausdruck = try? NSRegularExpression(pattern: muster) else { return self }
        return ausdruck.stringByReplacingMatches(
            in: self, range: NSRange(startIndex..., in: self), withTemplate: ersatz)
    }
}
