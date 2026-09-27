// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Vorhaben und ihre Reihenfolge in der Zelle ───────────────────────────────
// Die Kacheln stehen in der Reihenfolge der Eintragsliste; sortiert wird nirgends.
extension Planungsspeicher {

    // ── Vorhaben ──────────────────────────────────────────────────────────

    /// Fürs Umbenennen an der Kachel. Ein leerer Titel wird nicht abgewiesen —
    /// die Kachel zeigt dann „Ohne Titel“.
    func titelSetzen(vorhaben id: String, titel: String) {
        let sauber = bereinigt(titel, auf: Planungsdatei.maxNamenslaenge, feld: "Der Titel")
        // Mit Kennung: Wer den Titel tippt, erzeugt einen Schritt, nicht sechs (E88).
        aendern(Schrittname.titelAendern, kennung: id) { p in
            guard let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
            p.eintraege[stelle].titel = sauber
        }
    }

    // ── Reihenfolge innerhalb einer Zelle ─────────────────────────────────

    /// Die Stellen aller Vorhaben, die mit diesem in einer Zelle liegen.
    private func zellenstellen(_ id: String, in p: Planung) -> (stellen: [Int], eigene: Int)? {
        guard let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return nil }
        let kurs = p.eintraege[stelle].klasseId
        let woche = p.eintraege[stelle].woche
        let stellen = p.eintraege.indices.filter {
            p.eintraege[$0].klasseId == kurs && p.eintraege[$0].woche == woche
        }
        guard let eigene = stellen.firstIndex(of: stelle) else { return nil }
        return (stellen, eigene)
    }

    func kannReihen(_ id: String, nachOben: Bool) -> Bool {
        guard let p = planung, let (stellen, eigene) = zellenstellen(id, in: p) else { return false }
        return nachOben ? eigene > 0 : eigene < stellen.count - 1
    }

    func reihen(_ id: String, nachOben: Bool) {
        aendern(Schrittname.vorhabenUmstellen) { p in
            guard let (stellen, eigene) = zellenstellen(id, in: p) else { return }
            let nachbar = nachOben ? eigene - 1 : eigene + 1
            guard stellen.indices.contains(nachbar) else { return }
            p.eintraege.swapAt(stellen[eigene], stellen[nachbar])
        }
    }

    func auswahlReihen(nachOben: Bool) {
        guard auswahl.count == 1, let id = auswahl.first else { return }
        reihen(id, nachOben: nachOben)
    }

    var kannAuswahlReihen: (hoch: Bool, runter: Bool) {
        guard auswahl.count == 1, let id = auswahl.first else { return (false, false) }
        return (kannReihen(id, nachOben: true), kannReihen(id, nachOben: false))
    }

    func erledigtUmschalten(_ id: String) {
        let gesetzt = planung?.eintraege.first { $0.id == id }?.erledigt == true
        aendern(gesetzt ? Schrittname.hakenEntfernen : Schrittname.vorhabenAbhaken) { p in
            guard let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
            p.eintraege[stelle].erledigt.toggle()
            p.eintraege[stelle].statusGeaendert = Zeitrechnung.jetztAlsZeitstempel()
        }
    }

    func dringlichUmschalten(_ id: String) {
        let gesetzt = planung?.eintraege.first { $0.id == id }?.dringend == true
        aendern(gesetzt ? Schrittname.dringlichkeitEntfernen : Schrittname.dringlichKennzeichnen) { p in
            guard let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
            p.eintraege[stelle].dringend.toggle()
        }
    }

    /// Als Korrektur kennzeichnen oder die Kennzeichnung entfernen — gehandhabt
    /// wie die Dringlichkeit. An einer Prüfung ohne Wirkung: Ein Vorhaben ist
    /// entweder Prüfung oder Korrektur, und ein Klick nimmt nie still einen
    /// Prüfungstermin weg.
    func korrekturUmschalten(_ id: String) {
        guard let vorhanden = planung?.eintraege.first(where: { $0.id == id }), !vorhanden.pruefung else { return }
        aendern(vorhanden.korrektur ? Schrittname.korrekturEntfernen : Schrittname.alsKorrekturKennzeichnen) { p in
            guard let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
            p.eintraege[stelle].korrektur.toggle()
        }
    }

    /// Aus dem Rechtsklickmenü: Hausaufgabe hinzufügen oder entfernen. Entfernen
    /// nimmt die Zeile mit — sie gilt nur mit Hausaufgabe, und beim nächsten
    /// Hinzufügen soll nichts Altes wiederkommen.
    func hausaufgabeUmschalten(_ id: String) {
        let gesetzt = planung?.eintraege.first { $0.id == id }?.hausaufgabe == true
        aendern(gesetzt ? Schrittname.hausaufgabeEntfernen : Schrittname.hausaufgabeHinzufuegen) { p in
            guard let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
            let an = !p.eintraege[stelle].hausaufgabe
            p.eintraege[stelle].hausaufgabe = an
            if !an { p.eintraege[stelle].hausaufgabenText = "" }
        }
    }

    func vorhabenVerschieben(_ id: String, klasse: String, woche: Int) {
        var verfallen = false
        aendern(Schrittname.vorhabenVerschieben) { p in
            guard let stelle = p.eintraege.firstIndex(where: { $0.id == id }),
                  p.eintraege[stelle].klasseId != klasse || p.eintraege[stelle].woche != woche
            else { return }
            p.eintraege[stelle].klasseId = klasse
            verfallen = p.eintraege[stelle].wocheWechseln(nach: woche)
        }
        if verfallen { melden(Planungsspeicher.zurueckgesetzt(1)) }
    }

    /// Die Meldung zum verfallenen Datum — für ein Vorhaben in der Einzahl,
    /// für mehrere in der Mehrzahl.
    static func zurueckgesetzt(_ anzahl: Int) -> String {
        anzahl == 1
            ? "Durch das Verschieben des Ereignisses in eine andere Woche wurden Wochentag "
              + "und Datum für dieses Vorhaben zurückgesetzt."
            : "Durch das Verschieben in eine andere Woche wurden Wochentag und Datum für "
              + "\(anzahl) Vorhaben zurückgesetzt."
    }

    /// Dasselbe für Kopien: Sie kommen grundsätzlich ohne Wochentag und Datum an.
    static func kopieOhneDatum(_ anzahl: Int) -> String {
        (anzahl == 1 ? "Die Kopie wurde" : "Die \(anzahl) Kopien wurden")
            + " ohne Wochentag und Datum eingefügt; beides wird neu festgelegt."
    }

    // ── Vorhaben anlegen, ändern, entfernen ───────────────────────────────

    func vorhabenSichern(_ entwurf: VorhabenEntwurf) {
        guard let bestand = planung else { return }
        let titel = bereinigt(entwurf.titel, auf: Planungsdatei.maxNamenslaenge,
                              feld: "Der Titel")
        let text = bereinigt(entwurf.text, auf: Planungsdatei.maxTextlaenge,
                             feld: "Die Beschreibung")
        let kommentar = bereinigt(entwurf.kommentar, auf: Planungsdatei.maxTextlaenge,
                                  feld: "Der Kommentar")
        // Ohne Schalter keine Zeile; mit Schalter eine Zeile — Umbrüche aus
        // einem eingesetzten Text werden zu Leerzeichen.
        let hausaufgabenText = entwurf.hausaufgabe
            ? bereinigt(Planungsspeicher.einzeilig(entwurf.hausaufgabenText),
                        auf: Planungsdatei.maxNamenslaenge, feld: "Die Hausaufgabe")
            : ""
        // Den Überhang weisen `materialAufnehmen` und `linksAufnehmen` schon mit
        // Meldung ab; hier steht nur noch die Schranke vor der Datei.
        var langeNamen = 0
        // Eine Reihenfolge wie der Dateileser (`nichtLeer`), ohne dessen Rest:
        // bereinigen, trimmen, bei leer sein Ersatzname, kappen (E200, v73), was
        // das Kappen freilegt, weg (E208, v74) —
        // was hier bliebe, änderte sich beim nächsten Start still.
        func benennung(_ wert: String, ersatz: @autoclosure () -> String) -> String {
            let (text, gekuerzt) = VorhabenEntwurf.bezeichnung(wert, ersatz: ersatz())
            if gekuerzt { langeNamen += 1 }
            return text
        }
        let materialien = entwurf.materialien.prefix(Planungsdatei.maxMaterialien)
            .map { Material(id: $0.id, titel: benennung($0.titel, ersatz: Pfade.dateiName($0.pfad)), pfad: $0.pfad) }
        let links = entwurf.gereinigteLinks().prefix(Planungsdatei.maxLinks)
            .map { Weblink(id: $0.id, titel: benennung($0.titel, ersatz: Weblinks.name($0.adresse)), adresse: $0.adresse) }
        if langeNamen > 0 {
            melden("Bezeichnungen von Materialien und Links sind auf "
                   + "\(Planungsdatei.maxNamenslaenge) Zeichen begrenzt — \(langeNamen) "
                   + "\(langeNamen == 1 ? "wurde" : "wurden") gekürzt.", .warnung)
        }
        var verfallen = false
        let bearbeitet = entwurf.vorhabenId.map { kennung in
            bestand.eintraege.contains { $0.id == kennung }
        } ?? false
        aendern(bearbeitet ? Schrittname.vorhabenAendern : Schrittname.vorhabenHinzufuegen) { p in
            if let id = entwurf.vorhabenId, let stelle = p.eintraege.firstIndex(where: { $0.id == id }) {
                let vorher = p.eintraege[stelle]
                p.eintraege[stelle].titel = titel
                p.eintraege[stelle].text = text
                p.eintraege[stelle].klasseId = entwurf.klasseId
                p.eintraege[stelle].woche = entwurf.woche
                p.eintraege[stelle].materialien = materialien
                p.eintraege[stelle].links = links
                p.eintraege[stelle].pruefung = entwurf.pruefung
                p.eintraege[stelle].pruefungstag = zulaessigerTermin(entwurf, in: p)
                // Wechselt die Woche und steht das Datum noch auf dem alten Stand,
                // verfällt es wie beim Verschieben im Raster — der Dialog tut das
                // selbst und sagt es; hier steht die Schranke für jeden Weg daran
                // vorbei. Ein in der neuen Woche gewähltes Datum bleibt.
                if vorher.woche != entwurf.woche, vorher.datum != nil,
                   entwurf.datum == vorher.datum {
                    p.eintraege[stelle].datum = nil
                    verfallen = true
                } else {
                    p.eintraege[stelle].datum = entwurf.datum
                }
                p.eintraege[stelle].dringend = entwurf.dringend
                p.eintraege[stelle].korrektur = entwurf.korrektur && !entwurf.pruefung
                p.eintraege[stelle].hausaufgabe = entwurf.hausaufgabe
                p.eintraege[stelle].hausaufgabenText = hausaufgabenText
                // Haken und Kommentar teilt sich die App mit der iPad-Ansicht.
                // Geschrieben wird nur, was das Blatt geändert hat (E122): Ein
                // Stand vom iPad, der die Planung erreicht, während das Blatt
                // offen ist, bliebe sonst unter dem unberührten Ausgangsstand
                // des Entwurfs — überschrieben und frisch ausgestempelt. Und
                // gestempelt wird nur, was sich am Bestand wirklich ändert.
                if entwurf.hakenGeaendert { p.eintraege[stelle].erledigt = entwurf.erledigt }
                if entwurf.kommentarGeaendert { p.eintraege[stelle].kommentar = kommentar }
                if p.eintraege[stelle].kommentar != vorher.kommentar
                    || p.eintraege[stelle].erledigt != vorher.erledigt {
                    p.eintraege[stelle].statusGeaendert = Zeitrechnung.jetztAlsZeitstempel()
                }
            } else {
                // Auch ein neu angelegtes Vorhaben braucht den Stempel, sobald es
                // belegt ist: Sonst überschriebe ihn ein älterer iPad-Stand.
                let stempel = (entwurf.erledigt || !kommentar.isEmpty)
                    ? Zeitrechnung.jetztAlsZeitstempel() : ""
                p.eintraege.append(Vorhaben(
                    id: Kennung.neu("e"), klasseId: entwurf.klasseId, woche: entwurf.woche,
                    titel: titel, text: text,
                    erledigt: entwurf.erledigt,
                    materialien: materialien, links: links,
                    pruefung: entwurf.pruefung,
                    pruefungstag: zulaessigerTermin(entwurf, in: p),
                    datum: entwurf.datum, dringend: entwurf.dringend,
                    korrektur: entwurf.korrektur && !entwurf.pruefung,
                    kommentar: kommentar, statusGeaendert: stempel,
                    hausaufgabe: entwurf.hausaufgabe, hausaufgabenText: hausaufgabenText))
            }
        }
        vorhabenDialog = nil
        if verfallen { melden(Planungsspeicher.zurueckgesetzt(1)) }
    }

    /// Zeilenumbrüche zu Leerzeichen, Mehrfache zu einem: Die Hausaufgabe ist
    /// eine Zeile, auch wenn ein Absatz eingesetzt wurde.
    static func einzeilig(_ wert: String) -> String { Planungsdatei.einzeilig(wert) }

    /// Schneidet zu (`Planungsdatei.zugeschnitten`) auf die Grenze, die
    /// `Planungsdatei` beim Lesen anlegt — sonst verschwände der Überhang beim
    /// nächsten Start ohne jede Meldung. Idempotent seit v74 (E208, R73-02):
    /// Ein zweites Sichern ändert nichts und meldet nichts.
    private func bereinigt(_ wert: String, auf grenze: Int, feld: String) -> String {
        let (text, gekuerzt) = Planungsdatei.zugeschnitten(wert, grenze: grenze)
        if gekuerzt { melden("\(feld) war länger als \(grenze) Zeichen und wurde gekürzt.", .warnung) }
        return text
    }

    /// Die letzte Schranke vor der Datei — sie fängt jeden Weg, der am Dialog
    /// vorbeiführt.
    ///
    /// **Geprüft wird nur, was sich ändert:** Ein Termin, der schon in der Datei
    /// steht, bleibt auch unter einer später gelegten Sperre stehen.
    private func zulaessigerTermin(_ entwurf: VorhabenEntwurf, in p: Planung) -> Tag? {
        guard entwurf.pruefung, let tag = entwurf.pruefungstag else { return nil }
        let bisher = entwurf.vorhabenId
            .flatMap { kennung in p.eintraege.first { $0.id == kennung } }
        if bisher?.pruefung == true, bisher?.pruefungstag == tag { return tag }
        guard let gesperrt = p.sperre(am: tag, fuer: entwurf.klasseId) else { return tag }
        melden(gesperrt.abweisung + " Die Prüfung ist ohne Termin eingetragen.", .warnung)
        return nil
    }

    /// `ort` sagt, an welchem Fenster die Rückfrage hängt — aus dem Raster
    /// heraus muss das die Hauptansicht sein, sonst bliebe sie unsichtbar.
    func vorhabenLoeschen(_ id: String, ort: Rueckfrageort = .vorhaben) {
        guard let p = planung, let vorhaben = p.eintraege.first(where: { $0.id == id }) else { return }
        fragen("Das Vorhaben „\(vorhaben.anzeigeTitel)“ endgültig entfernen?\n\n"
               + "Verknüpfte Dateien bleiben unangetastet auf der Festplatte.",
               bestaetigung: "Entfernen", gefahr: true, ort: ort) { [weak self] in
            guard let self, planung != nil else { return }
            // Vorher merken: Das Zuweisen der Planung führt die Auswahl nach.
            let warAngewaehlt = auswahl.contains(id)
            aendern(Schrittname.vorhabenEntfernen) { $0.eintraege.removeAll { $0.id == id } }
            vorhabenDialog = nil
            if warAngewaehlt, auswahl.isEmpty {
                zielzelle = Zellenort(klasse: vorhaben.klasseId, woche: vorhaben.woche)
            }
            if ablage?.vorhaben.contains(where: { $0.id == id }) == true { ablage = nil }
            melden("Vorhaben entfernt.")
        }
    }

    func vorhabenOeffnen(id: String? = nil, klasse: String? = nil, woche: Int = 0) {
        guard let p = planung else {
            offenerDialog = .neuePlanung
            return
        }
        guard !p.klassen.isEmpty else {
            melden("Zuerst eine Klasse oder einen Kurs anlegen.", .warnung)
            offenerDialog = .klassen
            return
        }
        if let id, let vorhanden = p.eintraege.first(where: { $0.id == id }) {
            vorhabenDialog = VorhabenEntwurf(vorhanden)
        } else {
            vorhabenDialog = VorhabenEntwurf(klasseId: klasse ?? p.klassen[0].id, woche: woche)
        }
    }
}
