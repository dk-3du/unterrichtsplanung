// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Wie eine Woche zu den unterrichtsfreien Zeiten steht. Ganz oder teilweise
/// getroffen ist zweierlei; gezählt werden Montag bis Freitag.
struct Wochenlage: Hashable, Sendable {
    var frei = false
    var teilweise = false
    var name = ""
    var tage = 0

    static let unterricht = Wochenlage()
}

extension Woche {
    /// Wie viele der fünf Unterrichtstage in **irgendeinen** der Zeiträume
    /// fallen — die Vereinigung, nicht die Summe: Zwei Zeiträume dürfen sich
    /// überlappen und eine Woche gemeinsam ganz bedecken. Die Zählregel steht
    /// nur hier. `tage` spart in Schleifen die Kalenderrechnung.
    func tageIn(_ zeitraeume: [Ferienzeitraum], tage: [Tag]? = nil) -> Int {
        (tage ?? unterrichtstage).count { tag in
            zeitraeume.contains { tag >= $0.von && tag <= $0.bis }
        }
    }

    /// Wie viele der fünf Unterrichtstage in diesen einen Zeitraum fallen.
    func tageIn(_ zeitraum: Ferienzeitraum, tage: [Tag]? = nil) -> Int {
        tageIn([zeitraum], tage: tage)
    }
}

extension Tag {
    /// Liegt der Tag im Zeitraum einer Planung — vom Montag der Startwoche bis
    /// zum Sonntag der letzten Woche? Start und Wochenzahl kommen einzeln,
    /// weil die Prüfung auch **vor** dem Anlegen einer Planung gebraucht wird.
    /// Die eine Stelle für diese Grenzen; Dialoge und Speicher fragen hier.
    func liegtImZeitraum(start: Tag, wochen: Int) -> Bool {
        let montag = start.montagDerWoche
        return self >= montag && self <= montag.plus(tage: wochen * 7 - 1)
    }
}

/// Wochenliste, Ferienlagen und Schulwochen einer Planung als **ein** Wert.
///
/// Die drei stellengleichen Listen entstehen an genau einer Stelle
/// (`Planung.wochenstand`) — ein aus verschiedenen Quellen zusammengewürfelter
/// Stand ist damit nicht mehr baubar. Nachgeschlagen wird über `woche.nummer`;
/// die Zugriffe funktionieren deshalb auch dort, wo eine Ansicht nur einen
/// Ausschnitt der Wochen zeigt (Druck: Blattgruppen).
struct Wochenstand: Hashable, Sendable {
    /// Immer die ganze Liste — auch wenn eine Ansicht nur einen Ausschnitt zeigt.
    let wochen: [Woche]
    let lagen: [Wochenlage]
    /// `nil` für volle Ferienwochen und Wochen vor Schulbeginn.
    let schulwochen: [Int?]

    static let leer = Wochenstand(wochen: [], lagen: [], schulwochen: [])

    init(wochen: [Woche], lagen: [Wochenlage], schulwochen: [Int?]) {
        precondition(lagen.count == wochen.count && schulwochen.count == wochen.count,
                     "Die drei Listen müssen stellengleich sein")
        precondition(wochen.enumerated().allSatisfy { $1.nummer == $0 },
                     "Die Wochenliste muss vollständig sein — keine Teilliste")
        self.wochen = wochen
        self.lagen = lagen
        self.schulwochen = schulwochen
    }

    func lage(_ woche: Woche) -> Wochenlage { lagen[woche.nummer] }
    func schulwoche(_ woche: Woche) -> Int? { schulwochen[woche.nummer] }

    /// Die Woche zu einer gespeicherten Nummer (Spaltenindex) — `nil`, wenn
    /// sie außerhalb der Planung liegt. Die Nummer **ist** der Index
    /// (`Woche.init` vergibt sie fortlaufend); diese eine Stelle trägt die
    /// Invariante, statt dass jede Aufrufstelle sie neu beweist.
    func woche(_ nummer: Int) -> Woche? {
        wochen.indices.contains(nummer) ? wochen[nummer] : nil
    }
}

extension Planung {

    /// Wie die Woche zu den unterrichtsfreien Zeiten steht.
    ///
    /// Berühren mehrere Zeiträume dieselbe Woche (etwa Ferien plus beweglicher
    /// Ferientag), benennt sie der Zeitraum, der die meisten ihrer
    /// Unterrichtstage stellt; erst bei Gleichstand tritt die Anzahl an die
    /// Stelle des Namens. `tage` bleibt die Vereinigung aller Zeiträume.
    func lage(_ w: Woche) -> Wochenlage {
        if frei.contains(w.montag) {
            return Wochenlage(frei: true, teilweise: false, name: "unterrichtsfrei", tage: 5)
        }

        let tageDerWoche = w.unterrichtstage
        let getroffen = w.tageIn(ferien, tage: tageDerWoche)
        guard getroffen > 0 else { return .unterricht }

        let treffer = ferien.map { (name: $0.name, tage: w.tageIn($0, tage: tageDerWoche)) }
            .filter { $0.tage > 0 }
        let meiste = treffer.map(\.tage).max() ?? 0
        let fuehrende = treffer.filter { $0.tage == meiste }
        let name = fuehrende.count == 1
            ? fuehrende[0].name
            : "\(treffer.count) Zeiträume"
        return getroffen >= 5
            ? Wochenlage(frei: true, teilweise: false, name: name, tage: getroffen)
            : Wochenlage(frei: false, teilweise: true, name: name, tage: getroffen)
    }

    /// Die Ferienlage hängt nur an der Woche — einmal je Spalte statt je Zelle.
    /// Die Wochenliste kommt von außen, weil ihr Aufbau teuer ist.
    func alleLagen(_ wochen: [Woche]) -> [Wochenlage] { wochen.map(lage) }

    /// Fortlaufende Schulwochen-Nummern, stellengleich zur Wochenliste; `nil`
    /// für volle Ferienwochen und für Wochen vor Schulbeginn.
    ///
    /// Ist ein **erster Schultag** gesetzt (beim Anlegen erfragt),
    /// ist die 1. Schulwoche die Kalenderwoche, in die er fällt. Ohne ihn —
    /// ältere oder außerhalb der App bearbeitete Dateien, oder der Tag liegt
    /// außerhalb der Planung (in der App selbst weisen Dialoge und Speicher
    /// das ab) — wird die Zählung hergeleitet: Die 1. Schulwoche
    /// ist die chronologisch erste Woche mit einem Vorhaben, die keine volle
    /// Ferienwoche ist; trägt noch keine einzige zählbare Woche ein Vorhaben,
    /// die erste Woche ohne volle Ferien. In beiden Fällen tragen volle
    /// Ferienwochen nie eine Nummer (fällt der erste Schultag in eine, zählt
    /// die erste zählbare Woche danach als 1.); nach den Ferien läuft die
    /// Zählung fortlaufend weiter, angeschnittene Wochen zählen mit.
    func schulwochen(_ wochen: [Woche], lagen gegeben: [Wochenlage]? = nil) -> [Int?] {
        // Die Stellengleichheit der Listen wächtert `Wochenstand.init`.
        let lagen = gegeben ?? alleLagen(wochen)

        let beginn: Int?
        let ankerMontag = ersterSchultag?.montagDerWoche
        if let ankerMontag,
           let stelle = wochen.firstIndex(where: { $0.montag == ankerMontag }) {
            beginn = stelle
        } else {
            let belegt = Set(eintraege.map(\.woche))
            beginn = wochen.indices.first { !lagen[$0].frei && belegt.contains(wochen[$0].nummer) }
                ?? wochen.indices.first { !lagen[$0].frei }
        }
        guard let beginn else { return wochen.map { _ in nil } }

        var zaehler = 0
        return wochen.indices.map { stelle in
            guard stelle >= beginn, !lagen[stelle].frei else { return nil }
            zaehler += 1
            return zaehler
        }
    }

    /// Der abgeleitete Wochen-Datensatz als **ein** Wert. Die Wochenliste kann
    /// hereingereicht werden, wenn sie schon vorliegt — ihr Aufbau ist teuer.
    func wochenstand(_ gegeben: [Woche]? = nil) -> Wochenstand {
        let wochen = gegeben ?? wochenListe
        let lagen = alleLagen(wochen)
        return Wochenstand(wochen: wochen, lagen: lagen,
                           schulwochen: schulwochen(wochen, lagen: lagen))
    }

    func istZelleFrei(klasse: String, woche: Woche) -> Bool {
        zellenfrei.contains(FreieZelle(klasseId: klasse, woche: woche.montag))
    }

    /// Wie viele Wochen ein einzelner Zeitraum ganz bzw. angeschnitten trifft.
    func wochenZaehlen(_ zeitraum: Ferienzeitraum) -> (voll: Int, teilweise: Int) {
        var voll = 0, teilweise = 0
        for w in wochenListe {
            let tage = w.tageIn(zeitraum)
            if tage >= 5 { voll += 1 } else if tage > 0 { teilweise += 1 }
        }
        return (voll, teilweise)
    }

    struct Bilanz: Hashable, Sendable {
        var gesamt = 0
        var frei = 0
        var teilweise = 0
        var unterricht = 0
    }

    func ferienBilanz(_ liste: [Woche]? = nil) -> Bilanz {
        var b = Bilanz()
        b.gesamt = wochen
        for lage in alleLagen(liste ?? wochenListe) {
            if lage.frei { b.frei += 1 } else if lage.teilweise { b.teilweise += 1 }
        }
        b.unterricht = b.gesamt - b.frei
        return b
    }

    func laufendeWoche(in wochen: [Woche]) -> Int? {
        let montag = Tag.heute.montagDerWoche
        return wochen.first { $0.montag == montag }?.nummer
    }

    var laufendeWoche: Int? { laufendeWoche(in: wochenListe) }
}

extension Planung.Bilanz {
    var text: String {
        "\(unterricht) Unterrichtswochen · \(frei) unterrichtsfrei"
            + (teilweise > 0 ? " · \(teilweise) angeschnitten" : "")
            + " · \(gesamt) insgesamt"
    }
}

extension Ferienzeitraum {
    /// Überschneidet sich der Zeitraum überhaupt mit der Planung? Die Grenzen
    /// kommen aus `liegtImZeitraum`. Deckt der Zeitraum die ganze Planung ab,
    /// liegt keiner seiner Ränder darin — dann entscheidet der erste Montag.
    func trifftPlanung(_ planung: Planung) -> Bool {
        let drin = { (tag: Tag) in
            tag.liegtImZeitraum(start: planung.start, wochen: planung.wochen)
        }
        let montag = planung.start.montagDerWoche
        return drin(von) || drin(bis) || (von <= montag && montag <= bis)
    }

    func lageText(in planung: Planung) -> String {
        if ungueltig { return "Ende vor Beginn" }
        let z = planung.wochenZaehlen(self)
        if z.voll == 0 && z.teilweise == 0 {
            // Gezählt werden nur Montag bis Freitag: Ein Zeitraum mitten in der
            // Planung, der keinen Unterrichtstag trifft, liegt auf einem
            // Wochenende — nicht außerhalb.
            return trifftPlanung(planung)
                ? "nur am Wochenende" : "außerhalb des Zeitraums"
        }
        let ganz = z.voll > 0 ? "\(z.voll) ganze \(z.voll == 1 ? "Woche" : "Wochen")" : ""
        let teil = z.teilweise > 0 ? "\(z.teilweise) angeschnitten" : ""
        return ganz + (z.voll > 0 && z.teilweise > 0 ? " · " : "") + teil
    }
}
