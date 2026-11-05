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
    static let alsKorrekturKennzeichnen = "Als Korrektur kennzeichnen"
    static let korrekturEntfernen = "Kennzeichnung als Korrektur entfernen"
    static let hausaufgabeHinzufuegen = "Hausaufgabe hinzufügen"
    static let hausaufgabeEntfernen = "Hausaufgabe entfernen"
    static let vorhabenVerschieben = "Vorhaben verschieben"
    static let vorhabenAendern = "Vorhaben ändern"
    static let vorhabenHinzufuegen = "Vorhaben hinzufügen"
    static let vorhabenEntfernen = "Vorhaben entfernen"
    // Ablegen von außen auf eine Kachel (v88, AZ2; E907, E916): benannt nach dem Inhalt.
    static let materialAblegen = "Material ablegen"
    static let linkAblegen = "Link ablegen"
    static let linksAblegen = "Links ablegen"
    static let alsPruefungFuehren = "Als Prüfung führen"
    static let pruefungEntfernen = "Prüfung entfernen"
    /// Aus dem Kontextmenü (E296): Der Termin geht mit — gelöscht immer beide.
    static let terminkennzeichnungEntfernen = "Kennzeichnung als Termin entfernen"
    /// Aus dem Untermenü „Wochentag“ der Kachel (E655; Wortlaut vorgeschlagen in v86, AX5).
    static let wochentagSetzen = "Wochentag setzen"
    static let wochentagEntfernen = "Wochentag entfernen"

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
    /// Die Leistungsdokumentation an der Zeile (E662).
    static let leistungsdokumentationHinterlegen = "Externe Leistungsdokumentation hinterlegen"
    static let leistungsdokumentationEntfernen = "Externe Leistungsdokumentation entfernen"

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
    /// Der IServ-Import ins Blatt „Lernende“ und das Archivieren der Fehlenden (AP13).
    static let ausIServImportieren = "Aus IServ importieren"
    static let fehlendeArchivieren = "Fehlende archivieren"
    /// Ein Tisch ohne seine Person — der Name bleibt (E284).
    static let tischBindungLoesen = "Bindung lösen"
    /// Nicht im Blatt, sondern an der Kurszelle — betrifft die Ablage der Sitzpläne.
    static let sitzplanEntfernen = "Sitzplan entfernen"

    // ── Im Blatt „Lernende“ (eigener Schauplatz wie der Sitzplan, v80) ────
    static let lerngruppeAnlegen = "Lerngruppe anlegen"
    static let lerngruppeUmbenennen = "Lerngruppe umbenennen"
    static let lerngruppeArchivieren = "Lerngruppe archivieren"
    static let lerngruppeZurueckholen = "Lerngruppe zurückholen"
    static let lerngruppeLoeschen = "Lerngruppe löschen"
    static let namenEintragen = "Namen eintragen"
    static let nameAendern = "Name ändern"
    static let personArchivieren = "Person archivieren"
    static let personZurueckholen = "Person zurückholen"
    static let personLoeschen = "Person endgültig löschen"
    static let ausLerngruppeNehmen = "Aus der Lerngruppe nehmen"
    /// Das Menü „Lerngruppen“ der Personenzeile (v84, E365): Häkchen setzen, „Umziehen nach“.
    static let inLerngruppeAufnehmen = "In Lerngruppe aufnehmen"
    static let inAndereLerngruppeUmziehen = "In andere Lerngruppe umziehen"
    /// Der Kopf der Lerngruppe (v84, AT9a-2): „Zeilen wählen …“ (E669) und „Zusammenführen“ (E667, E672).
    static let zeilenWaehlen = "Zeilen wählen"
    static let lerngruppenZusammenfuehren = "Lerngruppen zusammenführen"
    static let mitteilungAnlegen = "Mitteilung anlegen"
    static let massnahmeAnlegen = "Maßnahme anlegen"
    static let mitteilungAendern = "Mitteilung ändern"
    static let massnahmeAendern = "Maßnahme ändern"
    static let mitteilungLoeschen = "Mitteilung löschen"
    static let massnahmeLoeschen = "Maßnahme löschen"
    static let terminAnlegen = "Termin anlegen"
    static let terminAendern = "Termin ändern"
    static let terminLoeschen = "Termin löschen"
    /// Was „Übernehmen“ des Blatts „Lernende“ an Terminen in die Planung trägt (E293).
    static let termineUebernehmen = "Termine übernehmen"
    static let betroffeneAendern = "Betroffene ändern"
    static let ruecklaufEintragen = "Rücklauf eintragen"

    // ── Strang A (AX3): Vereinbarungen (E741, Tabelle 7) ──────────────────
    static let vereinbarungAnlegen = "Vereinbarung anlegen"
    static let vereinbarungAendern = "Vereinbarung ändern"
    static let vereinbarungLoeschen = "Vereinbarung löschen"
    /// Der Stand einer Vereinbarung je Person (E746, E751).
    static let gueltigkeitAendern = "Gültigkeit ändern"

    // ── Strang A (AX4): Sammelgriffe an mehreren Gewählten (E757, E759, Tabelle 13) ──
    // Gebildet mit der Zahl der Personen, die der Griff betrifft: „3 Personen umziehen“. Betrifft er
    // nur 1 Person, gilt ihr Name von heute. In `alle` steht je Griff die Form mit 2 — mit ihr läuft der
    // Hin-und-zurück-Lauf.
    static func personenAufnehmen(_ zahl: Int) -> String {
        zahl == 1 ? inLerngruppeAufnehmen : "\(zahl) Personen aufnehmen"
    }
    static func personenUmziehen(_ zahl: Int) -> String {
        zahl == 1 ? inAndereLerngruppeUmziehen : "\(zahl) Personen umziehen"
    }
    static func personenAusLerngruppeNehmen(_ zahl: Int) -> String {
        zahl == 1 ? ausLerngruppeNehmen : "\(zahl) Personen aus der Lerngruppe nehmen"
    }
    static func personenArchivieren(_ zahl: Int) -> String {
        zahl == 1 ? personArchivieren : "\(zahl) Personen archivieren"
    }
    /// Nicht in Tabelle 13 — gebildet wie die Rückfrage „3 Personen endgültig löschen?“ (E838).
    static func personenLoeschen(_ zahl: Int) -> String {
        zahl == 1 ? personLoeschen : "\(zahl) Personen endgültig löschen"
    }
    /// Der Stand für mehrere an einer Mitteilung (v88, AZ4; E909, E915, E929): bei einer Person der Name von heute.
    static func ruecklaeufeAendern(_ zahl: Int) -> String {
        zahl == 1 ? ruecklaufEintragen : "Rücklauf von \(zahl) Personen ändern"
    }

    /// Je Namensform ein Name, den die App vergibt — die Liste, gegen die geprüft wird. Gebildete
    /// Namen stehen in der Form, die der Hin-und-zurück-Lauf erzeugt: die Sammelgriffe mit 2 (Z-AX4-06).
    static let alle: [String] = [
        titelAendern, vorhabenUmstellen, vorhabenAbhaken, hakenEntfernen,
        dringlichKennzeichnen, dringlichkeitEntfernen, alsKorrekturKennzeichnen, korrekturEntfernen,
        hausaufgabeHinzufuegen,
        hausaufgabeEntfernen, vorhabenVerschieben, vorhabenAendern, vorhabenHinzufuegen,
        vorhabenEntfernen, materialAblegen, linkAblegen, linksAblegen,
        alsPruefungFuehren, pruefungEntfernen, terminkennzeichnungEntfernen,
        wochentagSetzen, wochentagEntfernen,
        vorhabenEinsetzen, reihenfolgeAendern, wocheFrei, wocheUnterricht, zelleFrei,
        zelleUnterricht,
        planungstitelAendern, einstellungenUebernehmen, kursHinzufuegen, kursEntfernen,
        kursAendern, kurseUmstellen, bezeichnungAendern, fachAendern, notizAendern,
        unterrichtstagHinzufuegen, unterrichtstagEntfernen, fachUmbenennen, fachEntfernen,
        klassenleitungHinzufuegen, weiteresHinzufuegen, vertretungenHinzufuegen,
        farbeWaehlen, farbeDemFachFolgen, fachfarbeWaehlen,
        fachfarbeEntfernen, verwaltungsdateiHinterlegen, verwaltungsdateiEntfernen,
        curriculumHinterlegen, curriculumEntfernen, leistungsdokumentationHinterlegen,
        leistungsdokumentationEntfernen,
        ferienHinzufuegen, ferienUmbenennen, ferienAendern, ferienEntfernen,
        sperrzeitHinzufuegen, sperrzeitUmbenennen, sperrzeitAendern, sperrzeitKurse,
        sperrzeitEntfernen,
        tischeVerschieben, tischHinzufuegen, tischUmbenennen, tischEntfernen, tischeEntfernen,
        lehrertischHinzufuegen, lehrertischEntfernen, tischeAnordnen, tischBindungLoesen, sitzplanEntfernen,
        lerngruppeAnlegen, lerngruppeUmbenennen,
        lerngruppeArchivieren,
        lerngruppeZurueckholen, lerngruppeLoeschen, namenEintragen, nameAendern, personArchivieren,
        personZurueckholen, personLoeschen, ausLerngruppeNehmen, inLerngruppeAufnehmen, inAndereLerngruppeUmziehen,
        zeilenWaehlen, lerngruppenZusammenfuehren,
        mitteilungAnlegen, massnahmeAnlegen, mitteilungAendern, massnahmeAendern, mitteilungLoeschen,
        massnahmeLoeschen, terminAnlegen, terminAendern, terminLoeschen, termineUebernehmen, betroffeneAendern,
        ruecklaufEintragen,
        ausIServImportieren, fehlendeArchivieren,
        // Strang A (AX3)
        vereinbarungAnlegen, vereinbarungAendern, vereinbarungLoeschen, gueltigkeitAendern,
        // Strang A (AX4) — je Griff die Form mit 2
        personenAufnehmen(2), personenUmziehen(2), personenAusLerngruppeNehmen(2), personenArchivieren(2),
        personenLoeschen(2),
        // v88 (AZ4) — die Form mit 2
        ruecklaeufeAendern(2),
    ]
}
