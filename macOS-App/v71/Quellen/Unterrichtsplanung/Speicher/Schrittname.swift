// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Die Namen der Schritte — an einer Stelle, weil sie im Menü stehen.
///
/// „Widerrufen: Vorhaben entfernen“ liest der Nutzer; hier steht, was er liest.
/// Zwei Gründe für den einen Ort: Wortlaute lassen sich so als Ganzes ansehen
/// und in einem Zug ändern — und `alle` ist die Liste, gegen die die Prüfung
/// hält, dass **jeder** Name in einem Hin-und-zurück-Lauf vorkommt. Eine neue
/// Änderung ohne Rücknahmeprüfung fällt damit durch, statt still
/// durchzurutschen.
enum Schrittname {

    // ── Vorhaben ──────────────────────────────────────────────────────────
    static let titelAendern = "Titel ändern"
    static let vorhabenUmstellen = "Vorhaben umstellen"
    static let vorhabenAbhaken = "Vorhaben abhaken"
    static let hakenEntfernen = "Haken entfernen"
    static let dringlichKennzeichnen = "Als dringlich kennzeichnen"
    static let dringlichkeitEntfernen = "Dringlichkeit entfernen"
    static let hausaufgabeHinzufuegen = "Hausaufgabe hinzufügen"
    static let hausaufgabeEntfernen = "Hausaufgabe entfernen"
    static let vorhabenVerschieben = "Vorhaben verschieben"
    static let vorhabenAendern = "Vorhaben ändern"
    static let vorhabenHinzufuegen = "Vorhaben hinzufügen"
    static let vorhabenEntfernen = "Vorhaben entfernen"
    static let alsPruefungFuehren = "Als Prüfung führen"
    static let pruefungEntfernen = "Prüfung entfernen"

    // ── Zwischenablage und Fläche ─────────────────────────────────────────
    static let vorhabenEinsetzen = "Vorhaben einsetzen"
    static let reihenfolgeAendern = "Reihenfolge ändern"
    static let wocheFrei = "Woche als unterrichtsfrei kennzeichnen"
    static let wocheUnterricht = "Woche wieder als Unterricht führen"
    static let zelleFrei = "Zelle als unterrichtsfrei kennzeichnen"
    static let zelleUnterricht = "Zelle wieder als Unterricht führen"

    // ── Planung, Kurse, Fächer, Farben ────────────────────────────────────
    static let planungstitelAendern = "Titel der Planung ändern"
    static let einstellungenUebernehmen = "Einstellungen übernehmen"
    static let kursHinzufuegen = "Klasse/Kurs hinzufügen"
    static let kursEntfernen = "Klasse/Kurs entfernen"
    static let kursAendern = "Klasse/Kurs ändern"
    static let kurseUmstellen = "Klassen/Kurse umstellen"
    static let bezeichnungAendern = "Bezeichnung ändern"
    static let fachAendern = "Fach ändern"
    static let notizAendern = "Notiz ändern"
    static let unterrichtstagHinzufuegen = "Unterrichtstag hinzufügen"
    static let unterrichtstagEntfernen = "Unterrichtstag entfernen"
    static let fachUmbenennen = "Fach umbenennen"
    static let fachEntfernen = "Fach entfernen"
    /// Je Sonderzeile ihr Name (E157): „Klassenleitung hinzufügen“ usw.
    static let klassenleitungHinzufuegen = "Klassenleitung hinzufügen"
    static let weiteresHinzufuegen = "Weiteres hinzufügen"
    static let vertretungenHinzufuegen = "Vertretungen hinzufügen"
    static func sonderzeileHinzufuegen(_ art: Zeilenart) -> String {
        switch art {
        case .klassenleitung: klassenleitungHinzufuegen
        case .weiteres: weiteresHinzufuegen
        case .vertretungen: vertretungenHinzufuegen
        case .unterricht: kursHinzufuegen
        }
    }
    static let farbeWaehlen = "Farbe wählen"
    static let farbeDemFachFolgen = "Farbe dem Fach folgen lassen"
    static let fachfarbeWaehlen = "Fachfarbe wählen"
    static let fachfarbeEntfernen = "Fachfarbe entfernen"
    static let verwaltungsdateiHinterlegen = "Verwaltungsdatei hinterlegen"
    static let verwaltungsdateiEntfernen = "Verwaltungsdatei entfernen"
    static let curriculumHinterlegen = "Curriculumdatei hinterlegen"
    static let curriculumEntfernen = "Curriculumdatei entfernen"

    // ── Ferien und Sperrzeiten ────────────────────────────────────────────
    static let ferienHinzufuegen = "Ferienzeitraum hinzufügen"
    static let ferienUmbenennen = "Ferienzeitraum umbenennen"
    static let ferienAendern = "Ferienzeitraum ändern"
    static let ferienEntfernen = "Ferienzeitraum entfernen"
    static let sperrzeitHinzufuegen = "Sperrzeitraum hinzufügen"
    static let sperrzeitUmbenennen = "Sperrzeitraum umbenennen"
    static let sperrzeitAendern = "Sperrzeitraum ändern"
    static let sperrzeitKurse = "Kurse der Sperrzeit ändern"
    static let sperrzeitEntfernen = "Sperrzeitraum entfernen"

    // ── Im Sitzplanblatt (eigener Schauplatz, E82) ────────────────────────
    static let tischeVerschieben = "Tische verschieben"
    static let tischHinzufuegen = "Tisch hinzufügen"
    static let tischUmbenennen = "Tisch umbenennen"
    static let tischEntfernen = "Tisch entfernen"
    static let tischeEntfernen = "Tische entfernen"
    static let lehrertischHinzufuegen = "Lehrertisch hinzufügen"
    static let lehrertischEntfernen = "Lehrertisch entfernen"
    static let tischeAnordnen = "Tische anordnen"
    /// Nicht im Blatt, sondern an der Kurszelle — betrifft die Ablage der Sitzpläne.
    static let sitzplanEntfernen = "Sitzplan entfernen"

    /// Jeder Name, den die App vergibt — die Liste, gegen die geprüft wird.
    static let alle: [String] = [
        titelAendern, vorhabenUmstellen, vorhabenAbhaken, hakenEntfernen,
        dringlichKennzeichnen, dringlichkeitEntfernen, hausaufgabeHinzufuegen,
        hausaufgabeEntfernen, vorhabenVerschieben, vorhabenAendern, vorhabenHinzufuegen,
        vorhabenEntfernen, alsPruefungFuehren, pruefungEntfernen,
        vorhabenEinsetzen, reihenfolgeAendern, wocheFrei, wocheUnterricht, zelleFrei,
        zelleUnterricht,
        planungstitelAendern, einstellungenUebernehmen, kursHinzufuegen, kursEntfernen,
        kursAendern, kurseUmstellen, bezeichnungAendern, fachAendern, notizAendern,
        unterrichtstagHinzufuegen, unterrichtstagEntfernen, fachUmbenennen, fachEntfernen,
        klassenleitungHinzufuegen, weiteresHinzufuegen, vertretungenHinzufuegen,
        farbeWaehlen, farbeDemFachFolgen, fachfarbeWaehlen,
        fachfarbeEntfernen, verwaltungsdateiHinterlegen, verwaltungsdateiEntfernen,
        curriculumHinterlegen, curriculumEntfernen,
        ferienHinzufuegen, ferienUmbenennen, ferienAendern, ferienEntfernen,
        sperrzeitHinzufuegen, sperrzeitUmbenennen, sperrzeitAendern, sperrzeitKurse,
        sperrzeitEntfernen,
        tischeVerschieben, tischHinzufuegen, tischUmbenennen, tischEntfernen, tischeEntfernen,
        lehrertischHinzufuegen, lehrertischEntfernen, tischeAnordnen, sitzplanEntfernen,
    ]
}
