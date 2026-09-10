// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

// ── Planung anlegen, laden, sichern ──────────────────────────────────────────
extension Planungsspeicher {

    func neuePlanung(titel: String, start: Tag, wochen: Int, basis: String,
                     klassen: [Klasse], ersterSchultag: Tag?,
                     uebernahme: [Planung.Uebernahmewunsch]) {
        if let erster = ersterSchultag, !erster.liegtImZeitraum(start: start, wochen: wochen) {
            melden("Der erste Schultag liegt außerhalb des Planungszeitraums.", .warnung)
            return
        }
        guard !ablageGesperrt, !entsperrungOffen else {
            melden(sperrhinweis, .warnung)
            return
        }
        sicherung.startsperreAufheben()
        // Gleicher fester Dateiname: Die neue Planung überschreibt die Sicherung der bisherigen.
        let nameKollidiert = planung.map {
            Planungsdatei.festerName(titel: $0.titel)
                == Planungsdatei.festerName(titel: titel)
        } ?? false

        let fachfarben = planung?.fachfarben ?? [:]
        // Auf die Lesegrenzen kappen: Was der Leser beim nächsten Start kürzte,
        // soll gar nicht erst entstehen.
        let sauberer = Planungsdatei.ohneSteuerzeichen(titel).trimmingCharacters(in: .whitespaces)
        let gekappt = sauberer.isEmpty
            ? "Unterrichtsplanung"
            : String(sauberer.prefix(Planungsdatei.maxNamenslaenge))
        let sauberekurse = klassen.map { kurs -> Klasse in
            var k = kurs
            k.name = String(Planungsdatei.ohneSteuerzeichen(k.name).prefix(Planungsdatei.maxNamenslaenge))
            k.fach = String(Planungsdatei.ohneSteuerzeichen(k.fach).prefix(Planungsdatei.maxNamenslaenge))
            return k
        }
        let (neue, bilanz) = Planung.mitUebernahme(
            titel: gekappt,
            start: start, wochen: wochen,
            basis: Pfade.normalisieren(basis, basis: basis),
            klassen: sauberekurse, fachfarben: fachfarben,
            ersterSchultag: ersterSchultag,
            von: planung, uebernahme: uebernahme)
        planung = neue
        suchbegriff = ""
        sichern()
        zurLaufendenWoche()
        var meldung = "\(wochen) Wochen angelegt"
            + (neue.klassen.isEmpty ? "." : " für \(neue.klassen.count) Klassen/Kurse.")
        if bilanz.klassen > 0 {
            meldung += " Übernommen: \(bilanz.klassen) "
                + (bilanz.klassen == 1 ? "Zeile" : "Zeilen")
                + (bilanz.vorhaben > 0 ? " mit \(bilanz.vorhaben) Vorhaben" : "") + "."
        }
        if bilanz.uebergangen > 0 {
            meldung += " \(bilanz.uebergangen) Vorhaben ohne passende Schulwoche übergangen."
        }
        melden(meldung, bilanz.uebergangen > 0 ? .warnung : .hinweis)
        if nameKollidiert, autoexportAktiv, !autoexportOrdner.isEmpty {
            melden("Die Sicherungskopie heißt weiterhin „\(autoexportDateiname)“ — beim "
                   + "Beenden ersetzt sie die der bisherigen Planung. Für ein zweites "
                   + "Schuljahr besser einen anderen Titel wählen.", .warnung)
        }
        if neue.klassen.isEmpty { offenerDialog = .klassen }
        tourAnbieten = true
    }

    /// Satz über das, was beim Lesen wegfiel — leer, wenn nichts wegfiel.
    static func verlusttext(_ bilanz: Planungsdatei.Verlustbilanz) -> String {
        guard !bilanz.istLeer else { return "" }
        let teile = bilanz.verworfenes + bilanz.hinweise
        return " Übergangen: " + teile.joined(separator: ", ") + "."
    }

    func importieren(von url: URL) {
        guard !ablageGesperrt, !entsperrungOffen else {
            melden(sperrhinweis, .warnung)
            return
        }
        // Gebunden gelesen: Art und Größe am geöffneten Objekt, nie mehr als
        // die Grenze im Speicher — was keine Planung sein kann, wird nicht geöffnet.
        let daten: Data
        switch Ablage.gebundenLesen(url, hoechstens: Planungsdatei.hoechstgroesse) {
        case .keine:
            melden("„\(url.lastPathComponent)“ ist nicht mehr da und wurde nicht geöffnet.", .warnung)
            return
        case .zuGross(let groesse):
            melden("Die Datei ist mit \(groesse / 1024 / 1024) MB zu groß für eine "
                   + "Planungsdatei und wurde nicht geöffnet.", .warnung)
            return
        case .unlesbar(let fehler):
            melden(fehler.localizedDescription.ohneSchlusspunkt + " — die Datei wurde nicht geöffnet.", .warnung)
            return
        case .daten(let gelesen):
            daten = gelesen
        }
        do {
            guard Tresor.istBehaelter(daten) else {
                importierenKlartext(daten, von: url)
                return
            }
            let kopf = try Tresor.kopfLesen(daten)
            guard kopf.inhalt == Tresor.Inhalt.planung.rawValue else {
                melden("Die Datei ist ein verschlüsselter Behälter mit Inhalt „\(kopf.inhalt)“, "
                       + "keine Planung.", .warnung)
                return
            }
            if let tresor, tresor.passt(zu: kopf) {
                importierenKlartext(try tresor.oeffnen(kopf: kopf), von: url)
                return
            }
            // In eine unverschlüsselte Ablage läge die Planung danach im Klartext —
            // das entscheidet der Nutzer vorher.
            guard tresor != nil else {
                melden("Die Datei ist verschlüsselt, die Ablage auf diesem Mac ist es nicht. "
                       + "Bitte zuerst unter „Einstellungen“ die Verschlüsselung einschalten, "
                       + "dann die Datei erneut öffnen.", .warnung)
                return
            }
            // Fremder Schlüssel: Passphrase oder Wiederherstellungsschlüssel der Datei.
            entsperrungBeginnen(.datei(daten, url))
        } catch {
            melden(error.localizedDescription, .warnung)
        }
    }

    func importierenKlartext(_ daten: Data, von url: URL) {
        do {
            let (geladen, bilanz) = try Planungsdatei.lesenMitBilanz(daten)
            let uebernehmen: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                sicherung.startsperreAufheben()
                planung = geladen
                // „Neue Planungsdatei“ steht beim Start offen und läge sonst über der Planung.
                if offenerDialog == .neuePlanung { offenerDialog = nil }
                sichern()
                zurLaufendenWoche()
                let verlust = Planungsspeicher.verlusttext(bilanz)
                let nachsatz = verlust.isEmpty
                    ? ""
                    : verlust + " Die geöffnete Datei selbst bleibt unverändert."
                melden("Planung „\(geladen.titel)“ geladen." + nachsatz,
                       verlust.isEmpty ? .hinweis : .warnung)
            }
            if let vorhanden = planung, !vorhanden.eintraege.isEmpty {
                fragen("Die geöffnete Planung „\(vorhanden.titel)“ mit \(vorhanden.eintraege.count) "
                       + "Vorhaben wird ersetzt.\n\nFortfahren? (Vorher ggf. exportieren.)",
                       bestaetigung: "Ersetzen", gefahr: true, handlung: uebernehmen)
            } else {
                uebernehmen()
            }
        } catch {
            melden(error.localizedDescription, .warnung)
        }
    }

    func importDialog() {
        guard let url = Systemzugriff.quelleWaehlen() else { return }
        importieren(von: url)
    }

    /// ⌘S — bei eingeschalteter Verschlüsselung als Behälter mit Passphrase-
    /// und Wiederherstellungswicklung, sonst Klartext wie bisher.
    func exportieren() {
        exportSchreiben(klartext: false)
    }

    /// Der bewusste Weg zum Klartext: die Datei, die in zehn Jahren jedes
    /// Programm liest — mit Rückfrage, damit sie niemand versehentlich schreibt.
    func exportierenKlartext() {
        guard planung != nil else { return }
        guard tresor != nil else { exportSchreiben(klartext: true); return }
        fragen("Die Datei wird unverschlüsselt geschrieben. Sie ist die Fassung, die in zehn "
               + "Jahren jedes Programm liest — und sie liegt im Klartext, wo immer sie "
               + "hinkommt.\n\nFortfahren?",
               bestaetigung: "Als Klartext sichern", gefahr: true) { [weak self] in
            self?.exportSchreiben(klartext: true)
        }
    }

    private func exportSchreiben(klartext: Bool) {
        // AppKit führt NSModalPanelRunLoopMode als gemeinsamen Modus: Während
        // `runModal()` feuern Entpreller weiter. Deshalb vorher übernehmen — sonst
        // trüge die Datei einen überholten Titel — und danach neu lesen.
        Entpreller.allesUebernehmen()
        guard let titel = planung?.titel else { return }
        // Erst fragen, dann den Zeitstempel anheben: sonst bliebe nach Abbruch eine Scheinänderung.
        guard let ziel = Systemzugriff.zielWaehlen(
            name: Planungsdatei.exportName(titel: titel)) else { return }
        guard var aktuell = planung else { return }
        aktuell.geaendert = Zeitrechnung.jetztAlsZeitstempel()
        planung = aktuell
        do {
            var daten = try Planungsdatei.schreiben(aktuell)
            let tresor = klartext ? nil : self.tresor
            if let tresor { daten = try tresor.versiegeln(daten, inhalt: .planung, ziel: .export) }
            try daten.write(to: ziel, options: [.atomic])
            // Sonst gingen Autosicherung und Exportdatei auseinander.
            jetztSichern()
            melden(tresor == nil
                   ? "Planung als JSON gesichert."
                   : "Planung als verschlüsselte JSON-Datei gesichert — sie öffnet mit der "
                     + "Passphrase oder dem Wiederherstellungsschlüssel.")
            // Geschrieben wird sie trotzdem — aber nicht still: Kein Leser
            // dieses Projekts öffnet sie, und der Nutzer soll das jetzt hören.
            if let hinweis = Planungsspeicher.lesegrenzeHinweis(groesse: daten.count) {
                melden(hinweis, .warnung)
            }
        } catch {
            melden("Die Datei konnte nicht geschrieben werden: \(error.localizedDescription)", .warnung)
        }
    }

    /// Eine geschriebene Datei jenseits der Lesegrenze — `nil`, solange sie
    /// darunter bleibt. Für Export und Sicherungskopie.
    static func lesegrenzeHinweis(groesse: Int) -> String? {
        guard groesse > Planungsdatei.hoechstgroesse else { return nil }
        return "Die Datei ist mit \(groesse / 1024 / 1024) MB größer als die Lesegrenze von App und "
            + "Ansicht (\(Planungsdatei.hoechstgroesse / 1024 / 1024) MB) — so lässt sie sich nicht "
            + "mehr öffnen. Bitte Beschreibungen und Kommentare kürzen."
    }

    /// Auch die erste Woche ist eine Woche: Eine Untergrenze hier ließe den
    /// Sprung genau dann still verpuffen, wenn heute im ersten Zeitraum liegt.
    func zurLaufendenWoche() {
        guard let nummer = planung?.laufendeWoche else {
            melden("Die laufende Woche liegt außerhalb des geplanten Zeitraums.", .hinweis)
            return
        }
        sprung = Rastersprung(woche: nummer)
    }
}
