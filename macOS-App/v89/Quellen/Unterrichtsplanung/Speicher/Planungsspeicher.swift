// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import LocalAuthentication
import Observation

struct Meldung: Identifiable, Sendable {
    enum Art: Sendable { case hinweis, warnung }
    let id = UUID()
    let text: String
    let art: Art
}

/// Wo eine Rückfrage erscheinen muss. Ein Fenster trägt nur ein Blatt: Aus
/// einem Dialog heraus muss sie an diesem hängen, sonst bleibt sie unsichtbar.
enum Rueckfrageort: Sendable, Hashable {
    case hauptansicht, klassen, einstellungen, vorhaben, verschluesselung, sitzplan, lernende, neuePlanung
    /// Ein Bogen auf dem Blatt „Lernende“ (Import, Maßnahme/Termin, Zeilen wählen, Rückmeldungsliste) — dort sichtbar, wo er steht.
    case bogen
}

struct Rueckfrage: Identifiable {
    let id = UUID()
    let text: String
    let bestaetigung: String
    var gefahr: Bool = false
    var ort: Rueckfrageort = .hauptansicht
    /// Beschriftung des zweiten Knopfs — „Abbrechen“, oder eine zweite
    /// Antwort, die selbst etwas tut (E43: „Beiseitelegen“).
    var ablehnung: String = "Abbrechen"
    var beiAblehnung: (@MainActor () -> Void)? = nil
    /// Ein dritter Knopf, der selbst etwas tut — neben „Abbrechen“ (E275:
    /// „Verschlüsselung einrichten …“).
    var weitere: String? = nil
    /// Der dritte Knopf ebenfalls rot (Rolle destruktiv) — wo er so endgültig ist wie die Bestätigung (E894).
    var weitereGefahr = false
    /// Die Bestätigung steht über dem dritten Knopf statt darunter (E894) — nur, wo sie gesetzt ist.
    var bestaetigungZuerst = false
    var beiWeitere: (@MainActor () -> Void)? = nil
    /// Was ein Beenden per AppleScript als Grund meldet, wenn es diese Frage stellte —
    /// stand sie schon, gilt der allgemeine Satz. Nur die Verlustfrage setzt es (Z14c3-07, E327).
    var skriptgrund: String? = nil
    let handlung: @MainActor () -> Void
}

struct Rastersprung: Equatable {
    let id = UUID()
    let woche: Int
}

struct Zellenort: Hashable, Sendable {
    let klasse: String
    let woche: Int
}

/// Der Inhalt der Zwischenablage. Beim Verschieben bleiben die Vorhaben
/// zunächst stehen — erst das Einfügen versetzt sie.
struct Ablageinhalt: Sendable {
    let vorhaben: [Vorhaben]
    let verschieben: Bool
}

/// Wofür die Farbwahl offen ist: für eine einzelne Zeile — oder für ein Fach,
/// dessen Farbe alle seine Zeilen tragen.
struct Farbwahlziel: Identifiable, Hashable {
    let id = UUID()
    let klasseId: String?
    let fach: String?

    static func kurs(_ id: String) -> Farbwahlziel {
        Farbwahlziel(klasseId: id, fach: nil)
    }

    static func fach(_ schluessel: String) -> Farbwahlziel {
        Farbwahlziel(klasseId: nil, fach: schluessel)
    }
}

/// Welcher Dialog gerade offen ist. Nur einer zugleich.
enum Dialogfenster: String, Identifiable {
    case neuePlanung, ersteinrichtung, klassen, ferien, pruefungen, heute, einstellungen, hilfe
    /// Die Freigabe beim Start und die Einrichtung der Verschlüsselung.
    case entsperren, verschluesselung
    /// Das Angebot der Tour nach der ersten Planung.
    case tour
    /// Ein neueres Release — und die einmalige Frage nach der Prüfung für
    /// Planungen, die es vor dieser Frage schon gab.
    case update, updateNachfrage
    /// Die einmalige Frage nach der Materialliste von 3ducation.org für
    /// Planungen, die es vor dieser Frage schon gab (v71, E176).
    case materialNachfrage
    /// Die Nachwahl im Sandbox: bisher genutzte Ordner einmal neu wählen.
    case nachwahl
    /// Der Sitzplan-Editor — für die Klasse in `sitzplanKlasse`.
    case sitzplan
    /// Die Lernendenverwaltung des laufenden Schuljahrs (v80) — nur mit
    /// eingeschalteter Verschlüsselung (E249).
    case lernende
    /// Der einmalige Hinweis gegen den Rückweg auf eine Vorversion (v80, E286, E297).
    case rueckwegHinweis
    /// ⌘O mit einer Planung anderer Herkunft: archivieren und öffnen, mit der
    /// Wahl der Lerngruppen wie bei „Neue Planung“ (E277, E305).
    case schuljahrOeffnen
    var id: String { rawValue }
}

/// Was das Blatt „Neues Schuljahr öffnen“ braucht (E305): Wer geöffnet wird,
/// was bisher galt, welche Lerngruppen mitkommen (E657) — und das Öffnen selbst.
/// Dazu, was Hochstufen und Zuordnen brauchen (E307–E311): die Schuljahre,
/// die Stufen dazwischen, die Zeilen der geöffneten Planung und je Gruppe die
/// übernommenen Zeilen (E277, E650).
struct Schuljahrwechsel {
    struct Vorgabe {
        let bisherigesSchuljahr: String
        let neuesSchuljahr: String
        let stufen: Int
        let zeilen: [Hochstufung.Zeile]
        let uebernommen: [String: [String]]
        /// Wer mitkommt, wie das Blatt aufgeht — wer nach dem Vorschlag eine Zeile trägt (E657).
        let mitkommend: Set<String>
    }

    let titel: String
    let bisher: String
    let hochstufen: Vorgabe
    /// Die gewählten Gruppen, Name und Zeilen je Gruppe und die Gruppen ohne Mitglieder (E699, E708).
    let oeffnen: @MainActor (Set<String>, [String: Gruppenziel], Set<String>) -> Void

    var bisherigesSchuljahr: String { hochstufen.bisherigesSchuljahr }
    var neuesSchuljahr: String { hochstufen.neuesSchuljahr }
    var stufen: Int { hochstufen.stufen }
    var zeilen: [Hochstufung.Zeile] { hochstufen.zeilen }
    var uebernommen: [String: [String]] { hochstufen.uebernommen }
    var mitkommend: Set<String> { hochstufen.mitkommend }
}

/// Die Zeile, die „Neue Planung“ einer Lerngruppe gibt (E310) — ehe die
/// übernommenen Zeilen ihre neue Kennung haben.
enum Zielzeile: Hashable, Sendable {
    case keine
    /// Eine Zeile, die das Blatt der neuen Planung mitgibt — an ihrer Kennung.
    case kennung(String)
    /// Eine übernommene Zeile der bisherigen Planung — an ihrer alten Kennung.
    case uebernommen(String)
}

/// Name und Zeilen einer Lerngruppe aus dem Blatt „Neue Planung“ (E308, E310,
/// E649), in ihrer Folge; ein Fach setzt der Wechsel nicht (E656).
struct Gruppenwahl: Hashable, Sendable {
    var name: String
    var zeilen: [Zielzeile]
}

/// Erste Woche, Eingabeliste und übernommene Zeilen, mit denen ein Abbild das
/// Blatt „Neue Planung“ öffnet.
struct Neuplanungsvorgabe {
    var start: Tag
    var kurstext: String
    var mitnehmen: [String: Bool]
}

/// Die Lagen des Bogens „Lerngruppen zuordnen“ für Prüfstand und Abbild (E630).
enum Zuordnungslage: String {
    /// Wie geöffnet: alles zugeordnet.
    case vorschlag
    /// An einer Zeile kommt eine weitere Lerngruppe hinzu, die bisherige behält sie (E649, E670 — der Name aus E385 bleibt).
    case verdraengt
    /// Eine Lerngruppe ohne Zeile hinten — sie kommt nur mit, wenn der Import sie erkennt (E382 b, E657) —, dazu eine Zeile „Keine Gruppe“.
    case ohne
}

/// Der Zustand der Anwendung — und was ihn ändert, nach Abschnitten in den
/// Erweiterungen `Planungsspeicher+*.swift`. Gespeicherte Eigenschaften
/// stehen nur hier; die Merker eines Abschnitts stehen unter seinem Titel.
/// Was eine Erweiterung schreibt, kann nicht `private(set)` sein — für die
/// Oberfläche gilt trotzdem: lesen, nicht setzen.
@MainActor
@Observable
final class Planungsspeicher {

    // ── Zustand ───────────────────────────────────────────────────────────

    /// Die Sitzung: Planung und Schutzzustand in einem Wert. Beim Zuweisen
    /// wird die Auswahl nachgeführt — an einer Stelle statt an dreißig:
    /// Auswahl, Zwischenablage und Zielzelle zeigen auf Kennungen, die es
    /// danach nicht mehr geben muss. Auch ein Schlüsselwechsel zählt als neuer
    /// Stand; das Raster baut seine Momentaufnahme dann einmal neu — selten.
    var sitzung: Planungssitzung = .leer {
        didSet {
            Planungsspeicher.standzaehler &+= 1
            planungsstand = Planungsspeicher.standzaehler
            // Jede Zuweisung, die nicht über `aendern` oder eine Rücknahme
            // kommt, ist ein Wechsel des Schauplatzes: Laden, Import, neue
            // Planung, Entsperren, ein Schutzübergang, ein Stand vom iPad
            // (E84). Der Verlauf davor gehört dann zu etwas anderem (E82) —
            // und die Sitzung ist eine andere (E236, v77).
            if !eigenerWeg {
                verlauf.leeren()
                sitzungsmarke &+= 1
            }
            // Termin ↔ Vorhaben (E293): Was die Planung ändert, zieht der Termin nach.
            // Kommt ein Termin mit weniger Personen zurück, folgt der Haken seinen
            // Ständen (Z14a-01): gesetzt hier, vor den Ableitungen. Unter
            // `@Observable` läuft die Zuweisung noch einmal durch (wie bei
            // `spaltenbreite`); dieser Durchlauf findet nichts mehr nachzuziehen.
            if planung != oldValue.planung,
               let nachgezogen = termineNachfuehren(von: oldValue.planung, inSitzung: eigenerWeg) {
                sitzung = sitzung.mit(planung: nachgezogen)
            }
            // Das Ende eines Entsperrens kommt über die Sitzung (E216 d).
            statusNachholenWennFrei()
            // Ableitungen, damit die Hauptansicht nicht `planung` liest — sie würde
            // samt Liquid-Glass-Werkzeugleiste je Handgriff rund 20 ms neu ausgewertet.
            let neuHat = planung != nil
            if neuHat != hatPlanung { hatPlanung = neuHat }
            let neuKennzahlen = planung?.kennzahlen ?? "Noch keine Planung angelegt"
            if neuKennzahlen != kennzahlen { kennzahlen = neuKennzahlen }
            auswahlNachfuehren()
            if planung?.basis != oldValue.planung?.basis { freigabenNachfuehren() }
        }
    }

    /// Die Planung der Sitzung — gelesen von der Oberfläche, geschrieben von
    /// den Erweiterungen des Speichers; der Schlüssel bleibt dabei, wo er ist.
    var planung: Planung? {
        get { sitzung.planung }
        set { sitzung = sitzung.mit(planung: newValue) }
    }

    private(set) var hatPlanung = false

    /// Woran die App ihre Sitzung wiedererkennt (R76-01, E236, v77).
    ///
    /// Eine Arbeit, die den Hauptstrang verlässt und später zurückkommt, darf
    /// ihr Ergebnis nur anwenden, wenn es noch zu derselben Lage gehört. Die
    /// Marke steigt bei jedem **Wechsel des Schauplatzes** — an derselben
    /// Stelle, an der auch der Verlauf geleert wird: Laden, Import, neue
    /// Planung, Entsperren, Schutzübergang, ein Stand aus der Web App — und
    /// bei einem neuen Zielordner. Die Marke steigt **nicht** bei gewöhnlicher
    /// Bearbeitung, auch nicht bei Widerrufen und Wiederholen: Dafür ist der
    /// Abgleich je Vorhaben nach Zeitstempel gebaut (E120), und ein Widerruf
    /// soll den Stand der Web App nicht aussperren.
    ///
    /// **Warum nicht `planung?.erstellt`:** Bis 1.9.5 prüfte der Wächter den
    /// Zeitstempel der Erstellung. Der steht in der Datei und überlebt jedes
    /// Sichern, Öffnen und Einlesen derselben Planung — er sagt, woher eine
    /// Planung stammt, nicht, welche Sitzung gerade läuft. `&+=` statt `+=`,
    /// damit die Zahl bei Überlauf umläuft.
    private(set) var sitzungsmarke = 0

    /// Der Verlauf des Hauptfensters — die Planung selbst (E82). Der Entwurf im
    /// Sitzplanblatt und das Textfeld führen ihre eigenen; welcher gilt,
    /// entscheidet der Ersthelfer der Tastatur (E87).
    let verlauf = Ruecknahme<Planung>()

    /// Läuft die Zuweisung gerade über `aendern`, eine Rücknahme oder den
    /// Stempel der Sicherung? Nur dann bleibt der Verlauf stehen.
    private var eigenerWeg = false

    /// Ein Termin ging mit seinem Vorhaben, kam mit ihm zurück oder entstand neu,
    /// und die Jahresdatei ist schon geschrieben — dann sichert `sichern()` die
    /// Planung sofort statt entprellt (H1-01, E896 a, E900 a, E901). Gesetzt in
    /// `termineNachfuehren`.
    var terminfolgeSofort = false

    /// Eine Zuweisung auf dem eigenen Weg — sie ist kein Wechsel des
    /// Schauplatzes und lässt den Verlauf stehen. Verschachtelt gilt sie
    /// weiter: `aendern` sichert, und die Sicherung stempelt.
    private func aufEigenemWeg(_ was: () -> Void) {
        let davor = eigenerWeg
        eigenerWeg = true
        was()
        eigenerWeg = davor
    }

    /// Ein Stand der Web App, der nur Stempel bringt — auf dem Gerät ein Haken
    /// gesetzt und wieder entfernt: Kein Wechsel des Schauplatzes, der Verlauf
    /// bleibt (B59, E217). Ein späteres Widerrufen senkt diese Stempel nicht
    /// (`Statusabgleich.nachRuecknahme`, E120). Bis 1.9.3 leerte ein solcher
    /// Stand still den Verlauf.
    func stempelEinsetzen(_ neu: Planung) {
        aufEigenemWeg { planung = neu }
    }

    /// Der Untertitel der Kopfleiste.
    private(set) var kennzahlen = "Noch keine Planung angelegt"

    /// Sagt dem Raster, wann seine Momentaufnahme veraltet ist.
    ///
    /// Prozessweit vergeben, nicht je Speicher: Der Vorrat in
    /// `Rasterdaten.bereitstellen` ist eine statische Momentaufnahme und
    /// erkennt nur den Stand wieder. Im Betrieb gibt es einen Speicher, im
    /// Prüflauf mehrere — zwei mit demselben Stand bekämen sonst die Daten des
    /// jeweils anderen. `&+=` statt `+=`, damit die Zahl bei Überlauf umläuft.
    private static var standzaehler = 0

    private(set) var planungsstand: Int = 0

    var suchbegriff = "" { didSet { suchworte = Planungsspeicher.zerlegen(suchbegriff) } }

    private(set) var suchworte: [String] = []

    /// Dann gehören ⌘C und ⌘V dem Textfeld, nicht dem Raster.
    var suchfeldAktiv = false

    var auswahl: Set<String> = []

    /// Die angewählte Zelle, sofern kein Vorhaben angewählt ist — das Ziel
    /// fürs Einfügen.
    var zielzelle: Zellenort?

    /// Von wo aus ⇧ eine Spanne aufzieht.
    var auswahlanker: String?

    var ablage: Ablageinhalt?

    var offenerDialog: Dialogfenster? {
        didSet {
            // Der Verlauf des Blatts endet mit dem Blatt. Nicht erst in dessen
            // `onDisappear`: Am gebauten Paket gemessen kam das nicht, wenn das
            // Blatt von außen geschlossen wurde (S7-R2) — und ein Verlauf, der
            // einem geschlossenen Blatt gehört, gehört niemandem.
            if oldValue == .sitzplan, offenerDialog != .sitzplan { sitzplanblattGibtAb() }
            // Die Zeile zum Verlust gehört dem Blatt der Ersteinrichtung (E779).
            if oldValue == .ersteinrichtung, offenerDialog != .ersteinrichtung, naechsterDialog != .ersteinrichtung {
                verlustUnterDerErsteinrichtung = nil
            }
            if oldValue == .lernende, offenerDialog != .lernende { lernendenblattGibtAb() }
            statusNachholenWennFrei()
            vorgemerkteMeldungenZeigen()
        }
    }

    var vorhabenDialog: VorhabenEntwurf? {
        // Geht das Vorhaben-Blatt von außen zu (Prüfstände, Löschen), geht der
        // Bogen mit — sonst öffnete das nächste Vorhaben-Blatt ihn gleich wieder.
        didSet {
            if vorhabenDialog == nil { materialblattOffen = false }
            // Der Reiter: beim Öffnen und mit dem Blatt zurück auf „Grundlegendes“ (E731).
            if vorhabenDialog?.id != oldValue?.id {
                vorhabenReiter = .grundlegendes
            }
            statusNachholenWennFrei()
            vorgemerkteMeldungenZeigen()
        }
    }

    /// Das Material-Blatt von 3ducation.org — ein Bogen am Vorhaben-Blatt
    /// (v71). Im Speicher, damit Prüfstände und Abbilder es öffnen können.
    var materialblattOffen = false

    /// Der Reiter des Vorhaben-Blatts (E731, v85) — im Speicher, damit Prüfstände und Abbilder ihn setzen
    /// können und „Hausaufgabe hinzufügen …“ das Blatt auf „Hausaufgabe“ öffnet (E653). Nur in der Sitzung.
    var vorhabenReiter: Vorhabenreiter = .grundlegendes

    var farbwahlFuer: Farbwahlziel? { didSet { statusNachholenWennFrei() } }

    var rueckfrage: Rueckfrage? {
        didSet { statusNachholenWennFrei(); wartendeNachholen(); vorgemerkteMeldungenZeigen(); zurueckgestellteNachholen() }
    }

    /// Ein Stand der Web App, der nach dem Aufwachen wartet, bis kein Blatt,
    /// kein Dialog und keine Rückfrage mehr offen ist (E216 d).
    @ObservationIgnored var statusVorgemerkt = false

    /// Die Nummer der jüngsten Übernahme im Hintergrund: Ein älteres Ergebnis
    /// wird verworfen, wenn inzwischen eine jüngere Anfrage lief (R75-01, v76).
    @ObservationIgnored var statusAnfrage = 0

    /// Es liest gerade einer (R76-03, E238, v77). Weitere Anfragen bündeln
    /// sich zu einer Wiederholung, und der Menüeintrag ist derweil grau —
    /// darum **nicht** `@ObservationIgnored`: Das Menü führt ihn nach.
    /// Geschrieben in `Planungsspeicher+Status.swift`, darum nicht
    /// `private(set)` — für die Oberfläche gilt trotzdem: lesen, nicht setzen.
    var statusLaeuft = false

    var sprung: Rastersprung?

    /// Solange ein Dialog offen ist, greifen die Kurzbefehle nicht.
    var dialogOffen: Bool {
        offenerDialog != nil || vorhabenDialog != nil || farbwahlFuer != nil || rueckfrage != nil
    }

    /// Gesetzt aus `NSText.didBeginEditingNotification` (siehe
    /// `Anwendungsdelegat`) — deckt den **Fenstertitel** ab, den SwiftUI nicht
    /// meldet. Zuvor löschte ⌫ beim Korrigieren des Titels Vorhaben.
    var textfeldAktiv = false

    var schreibstelleAktiv: Bool { dialogOffen || suchfeldAktiv || textfeldAktiv }

    /// `mitWartenden`: Wartende Fragen gehören zu dem, was hier schließt (E317) — beim
    /// Sprung zu einem Vorhaben bleiben sie (Z14c4-07); das Nachholen sortiert die
    /// Fragen geschlossener Blätter aus.
    func alleDialogeSchliessen(mitWartenden: Bool = true) {
        if mitWartenden { wartendeRueckfragen = [] }
        offenerDialog = nil
        naechsterDialog = nil
        vorhabenDialog = nil
        materialblattOffen = false
        farbwahlFuer = nil
        rueckfrage = nil
    }

    /// Ein Verlust beim Öffnen einer Planung, während die Ersteinrichtung steht oder kommt: der Titel der Planung — das
    /// Blatt zeigt eine Zeile, die Meldung selbst folgt nach dem Blatt (E779, Z-AW10N-04). Geht mit dem Blatt.
    var verlustUnterDerErsteinrichtung: String?

    /// Ein Fenster trägt nur ein Blatt: Ist eines offen, wird es geschlossen
    /// und das nächste vorgemerkt — die Hauptansicht öffnet es, sobald das
    /// alte abgelöst ist (`naechstenDialogOeffnen`). Auch sein Ende kann den
    /// vorgemerkten Stand der Web App freigeben (B62, v75).
    private(set) var naechsterDialog: Dialogfenster? { didSet { statusNachholenWennFrei(); vorgemerkteMeldungenZeigen() } }

    func dialogOeffnen(_ fenster: Dialogfenster) {
        if offenerDialog == nil {
            offenerDialog = fenster
        } else {
            naechsterDialog = fenster
            offenerDialog = nil
        }
    }

    func naechstenDialogOeffnen() {
        guard offenerDialog == nil, let naechster = naechsterDialog else { return }
        naechsterDialog = nil
        // Die vorgemerkte Einrichtung nimmt die Fortsetzung mit — bliebe der Merker stehen, käme sie nach ihrem Schließen
        // ein zweites Mal; hier, wo sie aufgeht, gleich in welcher Folge geprüft wird (Z-AX9M-01, Z-AX9T3-01).
        if naechster == .ersteinrichtung { ersteinrichtungFortsetzen = false }
        offenerDialog = naechster
    }

    /// Das Blatt, das nach dem gerade schließenden kommen soll — der Rückweg
    /// aus dem Sitzplan-Editor in die Klassen-/Kursverwaltung.
    func dialogVormerken(_ fenster: Dialogfenster) {
        naechsterDialog = fenster
    }

    /// Steht während des einen Beendens nach „Trotzdem beenden“ — sonst stellte
    /// `beendenErlauben()` die Verlustfrage ein zweites Mal (E414).
    private var beendenFreigegeben = false

    /// Die wievielte Verlustfrage gestellt ist — beendet wird nur aus der Antwort auf die jüngste (Z-AU2-01).
    @ObservationIgnored private var verlustfragen = 0

    /// Was ein Beenden per AppleScript meldet, wenn es wartet oder abgelehnt wurde
    /// (Z14b-03, E316) — `wartete`: Schon vor dem Beenden stand ein Alert, oder nach
    /// dem späten Versuch steht eine Frage ohne eigenen Grund.
    /// `blatt`: abgelehnt nach dem Schließen der Blätter, oder gleich, während ein Blatt hing (E428).
    static func beendengrund(frage: Rueckfrage?, wartete: Bool, archiv: Bool = false, blatt: Bool = false,
                             handlung: Bool = false) -> String {
        if wartete { return "Eine Rückfrage steht; das Beenden wartet auf eine Antwort." }
        // In der Lücke nach einer Antwort (E436, E439).
        if handlung { return "Eine bestätigte Handlung läuft noch; das Beenden wurde abgelehnt — ein erneutes Beenden beendet." }
        // Angehalten an einer Löschung im Archiv — es steht keine Frage (E396, Z-AS2a-11).
        if archiv {
            return "Eine Löschung im Archiv ließ sich nicht schreiben; das Beenden wurde angehalten — ein erneutes Beenden beendet."
        }
        // Die Verlustfrage nennt, was sich nicht sichern ließ (E327).
        if let grund = frage?.skriptgrund { return grund }
        // Ohne Frage an einem Blatt abgelehnt: AppKit fragte den Delegaten nicht (B90, E427, E428).
        if frage == nil, blatt { return "Ein Blatt ließ sich nicht schließen; das Beenden wurde abgelehnt." }
        // Der offene Bogen gehört zum Blatt „Lernende“.
        return frage?.ort == .lernende || frage?.ort == .bogen
            ? "Das Blatt „Lernende“ hat ungesicherte Änderungen; das Beenden wartet auf eine Antwort."
            : "Die Planung ließ sich nicht sichern; das Beenden wartet auf eine Antwort."
    }

    /// Der Grund der Verlustfrage für Skripte, in der Folge ihres Texts (E328).
    static func verlustgrund(planung: Bool, sitzplaene: Bool, lernende: Bool) -> String {
        var was: [String] = []
        if planung { was.append("die Planung") }
        if sitzplaene { was.append("die Sitzpläne") }
        if lernende { was.append("die Lernendendaten") }
        let satz = was.count <= 1 ? was.joined() : was.dropLast().joined(separator: ", ") + " und " + (was.last ?? "")
        let verb = was == ["die Planung"] ? "ließ" : "ließen"
        return satz.prefix(1).uppercased() + satz.dropFirst() + " \(verb) sich nicht sichern; das Beenden wartet auf eine Antwort."
    }

    /// Der Grund für Skripte aus dem Stand der Sicherung — die Verlustfrage trägt ihn (Z-AS4-05).
    var verlustgrundJetzt: String {
        Self.verlustgrund(planung: planungsverlustDroht, sitzplaene: sitzplaene.ungesichert != nil,
                          lernende: lernende.ungesichert != nil)
    }

    /// Das Beenden hielt an einer Löschung im Archiv an, die sich nicht schreiben ließ (Z-AS2a-11) — auch nach
    /// „Trotzdem beenden“ (Z-AU2-04), dort nur für die Diagnose: `beenden()` setzt den Merker zurück, ehe ein
    /// Skript ihn sähe.
    @ObservationIgnored private(set) var beendenAmArchivAngehalten = false

    /// Die Frage, nach der sich der Grund für ein Skript richtet: die gesetzte — oder die, die das Beenden eben
    /// stellte und die unter einem Bogen auf ihren Ort wartet (E418, Z-AU3-12). Ist ihr Ort fort, entfiel sie.
    var frageFuerSkript: Rueckfrage? { rueckfrage ?? wartendeRueckfragen.last }

    /// Steht ein Alert — eine Rückfrage oder ein eigener Alert eines Dialogs
    /// (Sitzplan, Vorhaben)? Danach fragen die Sperren (E315, Z14c4-10). Eine
    /// gesetzte, aber nicht angezeigte Rückfrage — am verdeckten Ort, oder ihr
    /// Blatt ging — hängt nicht und sperrt nichts; sie darf weg, ohne dass
    /// SwiftUI ein Alert-Blatt schließen muss (Z14c3-01, Z14c3-02).
    var alertSteht: Bool { rueckfrageSichtbar() }

    /// Wo eine Rückfrage an ihrem Ort stünde: zu sehen; verdeckt — ein Bogen liegt über
    /// ihrem Blatt, oder das Blatt ist im Kommen —; oder fort (Z14c4-06, Z-AS3-03).
    enum Ortslage { case sichtbar, verdeckt, fort }

    /// Die Hauptfläche ist nur ohne Blatt zu sehen — ein Fenster trägt nur eines; ein
    /// Blatt darüber zählt als fort (E394).
    func ortslage(_ ort: Rueckfrageort) -> Ortslage {
        switch ort {
        case .hauptansicht:
            return offenerDialog == nil && naechsterDialog == nil && vorhabenDialog == nil ? .sichtbar : .fort
        case .vorhaben:
            guard vorhabenDialog != nil else { return .fort }
            return materialblattOffen || offenerDialog != nil || bogenSichtbar() ? .verdeckt : .sichtbar
        case .bogen:
            guard offenerDialog == .lernende, lernendenblattGriff?.bogenOffen() == true else { return .fort }
            // Ein Vorhaben-Blatt darüber verdeckt auch den Bogen (Z-AS3-12).
            return vorhabenDialog != nil ? .verdeckt : .sichtbar
        case .klassen: return blattlage(.klassen, verdeckt: farbwahlFuer != nil)
        case .lernende: return blattlage(.lernende, verdeckt: lernendenblattGriff?.bogenOffen() == true)
        case .einstellungen: return blattlage(.einstellungen)
        case .verschluesselung: return blattlage(.verschluesselung)
        case .sitzplan: return blattlage(.sitzplan)
        case .neuePlanung: return blattlage(.neuePlanung)
        }
    }

    private func blattlage(_ blatt: Dialogfenster, verdeckt: Bool = false) -> Ortslage {
        if offenerDialog == blatt { return verdeckt || vorhabenDialog != nil || bogenSichtbar() ? .verdeckt : .sichtbar }
        return naechsterDialog == blatt ? .verdeckt : .fort
    }

    /// Ob eine Rückfrage an diesem Ort jetzt zu sehen wäre. Gesetzt ohne Oberfläche
    /// sperrte sie das Menü still (Z14c4-06).
    func ortAngezeigt(_ ort: Rueckfrageort) -> Bool { ortslage(ort) == .sichtbar }

    /// Der Hinweis, wenn eine wartende Frage entfällt — als Warnung (E332, E394, E395).
    static func entfallenhinweis(_ ort: Rueckfrageort) -> String {
        switch ort {
        case .hauptansicht: "Eine wartende Rückfrage entfiel, weil ein Blatt darüber geöffnet wurde."
        case .bogen: "Eine wartende Rückfrage entfiel, weil ihr Bogen geschlossen wurde."
        default: "Eine wartende Rückfrage entfiel, weil ihr Blatt geschlossen wurde."
        }
    }

    /// Der Hinweis, wenn eine neue Frage gleich entfällt — ihr Ort war beim Fragen nicht offen (Z-AU5-03).
    static func sofortEntfallenhinweis(_ ort: Rueckfrageort) -> String {
        switch ort {
        case .hauptansicht: "Eine Rückfrage entfiel, weil ein Blatt offen war."
        case .bogen: "Eine Rückfrage entfiel, weil ihr Bogen nicht mehr offen war."
        default: "Eine Rückfrage entfiel, weil ihr Blatt nicht mehr offen war."
        }
    }

    /// Wann eine wartende Frage frühestens erscheint: nach einer Folgefrage,
    /// deren Fortsetzung `folgefrageVerzug` wartet (Z14c4-01, Z14c4-11).
    static let nachholfrist = 2 * folgefrageVerzug

    /// Steht ein Alert als Blatt an einem Fenster der App (B82)? Ohne App —
    /// im Prüfziel — nie.
    static func alertAngeheftet() -> Bool { alertfenster() != nil }

    /// Hängt an einem Blatt ein Bogen, der kein Alert ist? Geprüft wird jedes Fenster
    /// ohne Kindfenster-Eltern, auch ein Blatt selbst — so zählt nur, was wirklich
    /// über einem Blatt liegt. Ohne App — im Prüfziel — nie.
    static func bogenAmBlatt() -> Bool {
        guard let app = NSApp as NSApplication? else { return false }
        return app.windows.contains { fenster in
            guard fenster.parent == nil, let bogen = fenster.attachedSheet?.attachedSheet else { return false }
            return !istAlert(bogen)
        }
    }

    /// Ein Alert-Fenster, erkannt am Klassennamen (`_NSAlertPanel`) — die eine Stelle dafür (Z14c3-16, Z-AS3-15).
    static func istAlert(_ fenster: NSWindow) -> Bool { String(describing: type(of: fenster)).contains("Alert") }

    /// Das Alert-Fenster in der Blattkette eines Fensters der App — erkannt am
    /// Klassennamen (`_NSAlertPanel`), die eine Stelle dafür (Z14c3-16).
    static func alertfenster() -> NSWindow? {
        guard let app = NSApp as NSApplication? else { return nil }
        for fenster in app.windows where fenster.parent == nil {
            var blatt = fenster.attachedSheet
            while let b = blatt {
                if istAlert(b) { return b }
                blatt = b.attachedSheet
            }
        }
        return nil
    }

    /// Eine Frage beim Beenden braucht die App vorn — über das Dock beendet,
    /// stünde sie sonst hinter anderen Programmen (Z14b-04). Aktivieren und
    /// Fokus nie im Prüflauf: `swift test` nähme dem Nutzer sonst den Fokus.
    func nachVornFuerFrage() {
        guard let app = NSApp as NSApplication? else { return }
        let fenster = Self.rueckfragefenster()
        // Aus dem Dock zurück — auch im Prüflauf: Es nimmt keinen Fokus und schließt kein
        // Blatt; `makeKeyAndOrderFront` holt ein minimiertes Fenster nicht (Z14c3-08, E329).
        if let fenster, fenster.isMiniaturized { fenster.deminiaturize(nil) }
        guard !Ablage.istPruefstand, !app.isActive else { return }
        app.activate()
        fenster?.makeKeyAndOrderFront(nil)
    }

    /// Das Fenster, in dem eine Rückfrage stehen kann — auch ein geschlossenes:
    /// SwiftUI hält das Fenster der Szene und ordnet es beim Schließen nur aus.
    ///
    /// `canBecomeMain` scheidet als Merkmal aus; AppKit meldet dort für ein
    /// unsichtbares Fenster `false`.
    private static func rueckfragefenster() -> NSWindow? {
        guard let app = NSApp as NSApplication? else { return nil }
        let taugliche = app.windows.filter {
            $0.styleMask.contains(.titled) && !($0 is NSPanel) && $0.parent == nil
        }
        // Kein Fenster zu sehen: das minimierte — nicht irgendeines der Liste (Z-AS4-03).
        return taugliche.first(where: \.isVisible) ?? taugliche.first(where: \.isMiniaturized) ?? taugliche.first
    }

    /// Das Fenster für die Frage beim Beenden: die Handlung, die es nach vorn holt — `nil`, wenn es keins
    /// gibt. Nach dem Schließen des letzten Fensters läuft die App weiter (`beendenBeiLetztemFenster`);
    /// die Frage braucht es sichtbar. Aus dem Dock zurück (Z14c3-08, E329).
    static func fensterFuerFrageSuchen() -> (@MainActor () -> Void)? {
        guard let fenster = rueckfragefenster() else { return nil }
        return {
            if fenster.isMiniaturized { fenster.deminiaturize(nil) }
            if !fenster.isVisible {
                NSApp.activate()
                fenster.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Die Rückfrage, die ein stilles Verlieren verhindert. `nil` heißt: Es
    /// gibt nichts zu fragen, es darf gegangen werden.
    ///
    /// **Ohne Fenster wird nicht gefragt, sondern gegangen:** Die Rückfrage
    /// hängt als Blatt an der Ansicht; fehlte das Fenster, hingen ⌘Q, das Dock
    /// und das Abmelden ohne jede Rückmeldung fest.
    private func verlustfrage() -> (@MainActor () -> Void)? {
        guard !beendenFreigegeben, verlustDroht else { return nil }
        guard let nachVorn = fensterFuerFrage() else { return nil }
        return { [self] in
            nachVorn()
            var text = ""
            if planungsverlustDroht {
                text = "Die Planung ließ sich nicht sichern. Beim Beenden gehen die Änderungen "
                    + "seit der letzten gelungenen Sicherung verloren."
            }
            if let grund = sitzplaene.ungesichert {
                text += (text.isEmpty ? "" : " ") + "Die Sitzpläne ließen sich nicht sichern "
                    + "(\(grund.ohneSchlusspunkt)) — was seit dem letzten gelungenen Schreiben "
                    + "geändert wurde, geht beim Beenden verloren."
            }
            if let grund = lernende.ungesichert {
                text += (text.isEmpty ? "" : " ") + "Die Lernendendaten ließen sich nicht sichern "
                    + "(\(grund.ohneSchlusspunkt)) — was seit dem letzten gelungenen Schreiben "
                    + "geändert wurde, geht beim Beenden verloren."
            }
            if planungsverlustDroht {
                text += "\n\nVorher über „Als JSON sichern …“ (⌘S) exportieren?"
            } else if lernende.ungesichert != nil {
                // Die Lernendendaten rettet der Export, nicht der Sitzplan (Z14b-08).
                text += "\n\nVorher die Lernenden über „Ablage → Lernende exportieren …“ sichern?"
            } else {
                text += "\n\nVorher den Sitzplan im Editor über „Als PDF sichern …“ festhalten?"
            }
            verlustfragen += 1
            let nummer = verlustfragen
            // Mit ihrem Grund für ein Beenden per AppleScript (E327, E328).
            frageStellen(Rueckfrage(text: text, bestaetigung: "Trotzdem beenden", gefahr: true,
                                    skriptgrund: verlustgrundJetzt) { [self] in
                // Scheiterte eine Löschung im Archiv schon vor der Antwort, stand ihre Warnung bei der Entscheidung (Z-AU2-04).
                let archivfehler = archivSchreibfehler
                // Nie im Knopf selbst: Dort hängt das Alert noch, und `beendenErlauben()` kehrte an seiner
                // Sperre um — abgelehnt, und das nächste ⌘Q fragte wieder (Z-AS4-06, wie Z14c3-12).
                nachDerAntwort(immer: true) { [weak self] in
                    // Kam inzwischen eine neue Verlustfrage, gilt deren Antwort — auch ihr „Abbrechen“ (Z-AU2-01).
                    guard let self, nummer == verlustfragen else { return }
                    // Wartet dahinter noch eine bestätigte Handlung, liefe sie mit diesem Beenden nie: nicht beenden,
                    // mit Ton wie in der Lücke — das nächste Beenden fragt wieder (H1-01, Z-AU11-01).
                    guard verschobeneHandlungen == 0 else {
                        systemton()
                        return
                    }
                    // Ist eine bestätigte Löschung, deren Fortsetzung schon lief, noch unterwegs — sie liest abseits, wartet
                    // auf die vorige oder nach dem Lesen hinter einer Frage oder einem ausblendenden Alert (F-02, E962) —,
                    // geschieht sie jetzt, gleichlaufend wie vor dem Beenden (Z-AS2a-07) — bis v88 wäre sie schon geschehen,
                    // und das Beenden entschiede sonst, bevor ihr Scheitern feststeht. Eine, deren Fortsetzung noch aussteht,
                    // bleibt dem Beenden selbst wie bisher (`beendenErlauben`, G1-04).
                    archivloeschungenUnterwegsAusfuehren()
                    // Scheiterte seit der Antwort eine bestätigte Löschung im Archiv, bleibt die App, vorn: Die Warnung
                    // ginge sonst mit ihr; das nächste Beenden fragt wieder (B99, Z-AU2-04, wie Z-AS2a-08).
                    guard archivSchreibfehler == archivfehler else {
                        beendenAmArchivAngehalten = true
                        nachVornFuerFrage()
                        return
                    }
                    // Die Freigabe gilt nur für dieses eine Beenden: Kehrt es zurück, war es abgelehnt — aus
                    // welchem Grund auch immer —, und das nächste fragt wieder (B91, G1-04, E414).
                    beendenFreigegeben = true
                    appBeenden()
                    beendenFreigegeben = false
                }
            })
        }
    }

    /// Antwort auf das Beenden-Ereignis von AppKit — und die letzte Stelle vor
    /// dem Gehen: Hier wird ein letztes Mal gesichert, und was dabei nicht
    /// gelingt, kommt hier noch zur Sprache. Eine über `beenden()` bereits
    /// beantwortete Rückfrage wird nicht wiederholt.
    func beendenErlauben() -> Bool {
        // Eine stehende Rückfrage — oder ein eigener Alert — wartet auf ihre Antwort (E315, B82, Z14c4-10).
        guard !alertSteht else {
            nachVornFuerFrage()
            return false
        }
        // In der Lücke nach einer Antwort: abgelehnt, mit Ton — die Handlung läuft noch (E436).
        guard !frageSperrtBefehl() else { return false }
        // Bestätigte Löschungen im Archiv geschehen noch — hier steht kein Alert mehr (Z-AS2a-07).
        // Scheitert eine, bleibt die App, vorn: Die Warnung wäre sonst mit ihr fort (Z-AS2a-08);
        // ein Skript erfährt den Grund (Z-AS2a-11).
        beendenAmArchivAngehalten = false
        guard archivloeschungenJetztAusfuehren() else {
            beendenAmArchivAngehalten = true
            nachVornFuerFrage()
            return false
        }
        jetztSichern()
        autoexportAusfuehren()
        guard let fragen = verlustfrage() else { return true }
        fragen()
        return false
    }

    /// Solange nicht gesichert werden kann, darf das Schließen des Fensters
    /// die App nicht mitnehmen: Die Rückfrage braucht ein Fenster, in dem sie
    /// stehen kann. Über das Dock-Symbol kommt es zurück — und die Rückfrage
    /// holt es sich selbst zurück, wenn dann beendet wird.
    var beendenBeiLetztemFenster: Bool { !verlustDroht }

    /// Beim Beenden ginge etwas verloren: Die Sicherung liegt still, und die
    /// Platte trägt nicht den Stand der Sitzung — eine Planung über der
    /// Lesegrenze, die seit dem Start niemand geändert hat, liegt dort schon.
    var verlustDroht: Bool {
        // Ein Sitzplan, den die Platte nicht trägt, zählt wie die Planung (B10).
        if sitzplaene.ungesichert != nil { return true }
        if lernende.ungesichert != nil { return true }
        return planungsverlustDroht
    }

    /// Die Planung selbst: Sicherung still und Stand nicht auf der Platte.
    /// Gefragt wird der Zähler der Sicherung, nicht der Zeitstempel — zwei
    /// Änderungen in derselben Millisekunde tragen denselben (N56-02).
    private var planungsverlustDroht: Bool {
        guard let planung, sicherungLiegtStill else { return false }
        return sicherung.ungesichert || planung.geaendert != sicherung.gesicherterStand
    }

    /// Ob der letzte `beenden()`-Aufruf die App auf den Weg gebracht hat — `false`,
    /// solange eine Rückfrage aussteht oder nachdem das Beenden abgelehnt wurde;
    /// `true`: Unterwegs, die Antwort an ein Skript kommt mit dem Ende oder über
    /// `beendenAbgelehnt`.
    private(set) var beendetGleich = false

    /// Ein offenes Blatt hält das Beenden auf — AppKit weist den Befehl ab,
    /// bevor der Delegat davon erfährt. Erst schließen, dann sichern, dann gehen.
    ///
    /// **Freigegeben wird hier nichts:** Das Blatt schreibt beim Verschwinden
    /// noch (`onDisappear`), also hat `beendenErlauben()` das letzte Wort — dort
    /// wird ein letztes Mal gesichert, und erst dort zeigt sich, ob dabei etwas
    /// verlorenginge.
    func beenden() {
        beendetGleich = false
        beendenAmArchivAngehalten = false
        // Steht eine Rückfrage, wartet das Beenden auf ihre Antwort: Die App nimmt
        // sie nie selbst weg und legt keine zweite darüber — SwiftUI schlösse das
        // Alert-Blatt sonst mitten im Layout, was macOS 26 abstürzen ließ (E315, B82, Z14c4-10).
        guard !alertSteht else {
            nachVornFuerFrage()
            return
        }
        // In der Lücke nach einer Antwort prallt es ab, mit Ton; ein erneutes beendet (E436).
        guard !frageSperrtBefehl() else { return }
        // Ein geändertes Blatt „Lernende“ fragt zuerst (E300) — geschlossen verlöre es seinen Entwurf.
        if lernendenblattBeimBeendenFragen(dann: { [weak self] in self?.beenden() }) { return }
        let warEinBlattOffen = dialogOffen
        // Die Nachwahl käme mit dem Schließen als Blatt wieder und hielte
        // AppKit am Beenden fest — der nächste Start fragt ohnehin erneut.
        nachwahlVerschoben = true
        alleDialogeSchliessen()
        jetztSichern()

        if let fragen = verlustfrage() {
            fragen()
            return
        }
        beendetGleich = true

        guard warEinBlattOffen else {
            appBeenden()
            // Zurück heißt abgelehnt — an einer Frage, im Archiv oder an einem Blatt
            // (`applicationShouldTerminate` kennt nur `.terminateNow` und `.terminateCancel`);
            // der AppleEvent-Griff meldet es mit Grund.
            beendetGleich = false
            return
        }
        takt.gleich { [self] in
            await Planungsspeicher.blaetterAbloesenAbwarten()
            // Der Halt im Archiv zählt nur aus diesem Versuch (Z-AU3-05).
            beendenAmArchivAngehalten = false
            appBeenden()
            // Zurück heißt abgelehnt — ein Skript, das auf das Beenden wartet, erfährt hier den Grund (B90, E416);
            // eine Frage ohne eigenen Grund heißt „Eine Rückfrage steht“ (Z-AU3-05).
            beendetGleich = false
            let frage = rueckfrage
            beendenAbgelehnt?(Self.beendengrund(frage: frage, wartete: frage != nil && frage?.skriptgrund == nil,
                                                archiv: beendenAmArchivAngehalten, blatt: true,
                                                handlung: handlungAussteht))
        }
    }

    /// Gleich nach einem abgelehnten `terminate` gemessen: Hing ein Blatt oder ein modales Fenster, fragte
    /// AppKit den Delegaten gar nicht (Z-AS4a-09).
    static func blattHaengt() -> Bool {
        guard let app = NSApp as NSApplication? else { return false }
        return app.windows.contains { $0.attachedSheet != nil } || app.modalWindow != nil
    }

    /// Wartet, bis kein Blatt mehr angeheftet und kein modales Fenster mehr
    /// offen ist — höchstens rund 1,2 s. AppKit weist `terminate` bei
    /// angeheftetem Blatt ab, noch bevor der Delegat gefragt wird; wer ein
    /// Blatt schließt und gleich gehen will, wartet hier. Die eine Stelle
    /// dafür — trüge `beenden()` die Schleife allein, schlössen die
    /// Prüfstände ihre Blätter und gingen ungebremst: `--abbild` bliebe
    /// stehen.
    static func blaetterAbloesenAbwarten() async {
        guard let app = NSApp as NSApplication? else { return }
        for _ in 0..<30 {
            let offen = app.windows.contains { $0.attachedSheet != nil }
            if !offen, app.modalWindow == nil { return }
            try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber (AppKit) — warten, bis AppKit die Blätter abgelöst hat
        }
    }

    private(set) var meldungen: [Meldung] = []

    var sicherungGestoert: Bool { sicherung.gestoert }

    var letzteSicherung: Date? { sicherung.letzteSicherung }

    /// Das Einrasten steht an dieser einen Stelle, damit Regler, Tastenkürzel
    /// und der wiederhergestellte Wert dieselben Stufen liefern.
    var spaltenbreite: Double {
        didSet {
            let neu = Kennwerte.spalteRasten(spaltenbreite)
            if neu != spaltenbreite { spaltenbreite = neu; return }
            Einstellungen.setzen(neu, Einstellungen.Schluessel.spaltenbreite)
        }
    }

    var erscheinung: Erscheinung {
        didSet { Einstellungen.setzen(erscheinung.rawValue, Einstellungen.Schluessel.erscheinung) }
    }

    // ── Sicherungskopie beim Beenden — geführt im Sicherungsdienst ────────

    var autoexportAktiv: Bool {
        get { sicherung.kopieAktiv }
        set { sicherung.kopieAktiv = newValue }
    }

    /// Leer heißt: noch keiner gewählt. Ein anderer Zielordner ist eine andere
    /// Lage — was für den alten gelesen wurde, gilt nicht mehr (E236, v77).
    var autoexportOrdner: String {
        get { sicherung.kopieOrdner }
        set {
            guard newValue != sicherung.kopieOrdner else { return }
            sicherung.kopieOrdner = newValue
            sitzungsmarke &+= 1
        }
    }

    var letzterAutoexport: Date? { sicherung.letzteKopie }

    // ── Verschlüsselung — geschrieben in Planungsspeicher+Verschluesselung.swift ───

    /// Eine Datei von außen unter fremdem Schlüssel wartet auf ihre Freigabe —
    /// neben der Sitzung: Die Ablage bleibt dabei offen. Die Freigabe der
    /// Ablage selbst steckt in `sitzung` (`.gesperrt`). Geleert wird sie erst
    /// nach dem Blatt — dann holt sie den vorgemerkten Stand nach (B62, v75).
    var dateiEntsperrung: Entsperrung? { didSet { statusNachholenWennFrei() } }

    /// Der Touch-ID-Dialog steht gerade.
    var entsperrungLaeuft = false

    var entsperrungFehler: String?

    var entsperrungsweg: Entsperrungsweg = .passphrase

    /// Das Häkchen „Mit Touch ID öffnen“ im Blatt — wie bei Numbers: Nach der
    /// nächsten Freigabe per Passphrase oder Wiederherstellungsschlüssel bekommt
    /// dieser Mac seine Enklaven-Wicklung, notfalls neu; ohne Häkchen verliert
    /// er sie. Im Speicher, damit der Prüfstand es schalten kann.
    var enklaveMerken = false

    /// Die Wicklung dieses Macs ließ sich nicht öffnen — ein neuer oder neu
    /// aufgesetzter Mac; das Blatt sagt es dazu.
    var enklaveWicklungPasstNicht = false

    /// Trägt der offene Tresor eine Wicklung für diesen Mac? Für den Schalter
    /// unter „Einstellungen“ — beobachtbar, was der Tresor selbst nicht ist.
    var enklaveEingerichtet = false

    /// Nur für Prüfungen: den Enklaven-Schlüssel auch im Prüfstand anlegen.
    /// Das Anlegen fragt nicht nach; erst das Öffnen verlangt die Freigabe.
    var enklaveImPruefstandAnlegen = false

    /// Wartet auf die Antwort zu Klartext-Sitzplänen (E43): das Angleichen der
    /// Wicklung dieses Macs nach dem Entsperren — es liefe sonst als Übergang
    /// über die unbestätigten Pläne, ehe die Frage beantwortet ist (F04).
    /// Beide Antworten holen es nach.
    var nachSitzplanantwort: (@MainActor () -> Void)?

    /// Wird erst nach dem bestätigten Wiederherstellungsblatt zum Tresor der Ablage.
    var vorbereitung: Tresor?
    /// Was aus der Wicklung dieses Macs bei der Vorbereitung wurde (E139,
    /// N64-02): angelegt mit welcher Bedingung, nicht verfügbar oder gescheitert
    /// mit Grund — Schritt 2 des Blatts und die Meldung nach dem Einschalten
    /// lesen daraus, nicht aus dem Gerät. `nil`: keine Vorbereitung im Gang.
    var vorbereitungGeraet: Tresor.Geraetewicklung?
    /// Ob auf diesem Mac Biometrie eingerichtet ist — im Augenblick des
    /// Anlegens gefragt (E140, N64-01). Vorgabe: das Gerät; die Prüfungen
    /// spritzen eine Quelle ein und stellen sie im Prozess um.
    var biometrieQuelle: () -> Bool = { Tresor.biometrieEingerichtet }

    var nachEinrichtung: (@MainActor () -> Void)?

    var freigabegriff: Freigabegriff?

    /// Das Blatt hat abgebrochen, während die Abfrage stand: Das Ende der Abfrage darf
    /// dann kein Blatt mehr öffnen.
    var freigabeStillAbgebrochen = false

    /// Zählt jedes neue Entsperrungsziel und jeden Abbruch: Ein Ergebnis der
    /// Schlüsselableitung, dessen Ziel inzwischen gewechselt hat, wird verworfen.
    var entsperrungsgeneration = 0

    /// Einrichten, Passphrase ändern oder Erneuern rechnet gerade abseits des
    /// Hauptstrangs (PBKDF2, Wicklungen); die Blätter sperren derweil ihre
    /// Knöpfe und nehmen keine zweite Eingabe an.
    var schluesselarbeitLaeuft = false { didSet {
        if schluesselarbeitLaeuft && !oldValue { schluesselarbeitBegonnen &+= 1 }  // nur der Wechsel zählt (Z-H8N-02)
        statusNachholenWennFrei()
    } }
    /// Wie oft eine Schlüsselarbeit begann — ein bleibendes Signal für Prüfungen: `schluesselarbeitLaeuft` ist kurzlebig, unter
    /// Last beginnt und endet eine Arbeit zwischen zwei Abfragen (H-AX9-08, E860).
    @ObservationIgnored private(set) var schluesselarbeitBegonnen = 0

    /// Zählt jedes Verwerfen (Abbrechen, Blatt zu) und jeden Wechsel des
    /// Sitzungsschlüssels: Ein Ergebnis der Schlüsselarbeit, dessen Anlass
    /// inzwischen dahin ist, wird verworfen.
    var schluesselgeneration = 0

    // ── Nachwahl: Zugriff auf bisher genutzte Ordner — geschrieben in Planungsspeicher+Nachwahl.swift ───

    /// Gespeicherte Ordner ohne Lesezeichen — nur im Sandbox; ein Prüflauf hat
    /// keine, sofern er sie nicht vorgibt.
    var ausstehendeFreigaben: [Ordnerfreigabe] = []

    /// „Später“ gilt für diese Sitzung; der nächste Start fragt wieder.
    var nachwahlVerschoben = false

    /// Für Prüfstand und Abbild: das Blatt auch ohne Sandbox.
    var nachwahlProbe = false

    // ── Ersteinrichtung — geschrieben in Planungsspeicher+Ersteinrichtung.swift ───

    var ersteinrichtungsschritt: Ersteinrichtungsschritt = .verschluesselung

    /// Ein anderes Blatt hat die Ersteinrichtung abgelöst, bevor ihre letzte
    /// Frage beantwortet war: Die Ersteinrichtung geht weiter, sobald wieder nichts offen ist
    /// — bei dem Schritt, den sie erreicht hatte (B67, E239, v77). Die Wahl
    /// des Zielordners ohne Schlüssel ist der eine Weg, auf dem das geschieht;
    /// ob die Verschlüsselung danach eingerichtet oder abgebrochen wird,
    /// ändert daran nichts.
    var ersteinrichtungFortsetzen = false

    /// Wie Frage 1 vor der ersten Planung ausging (v84, AT6: D1b, E355, E477 b) — nur in der Sitzung (E536).
    var verschluesselungsfrage: Verschluesselungsfrage = .offen

    /// Eine Übernahme einer versiegelten Planung begann in Frage 1 (E716) — gelingt eine, ist Frage 1 beantwortet (E355).
    /// Fällt erst mit dem Gelingen, nicht mit „Abbrechen“ (Z-AW1bM-01).
    @ObservationIgnored var uebernahmeAusFrage1 = false

    /// Der Hinweis gegen den Rückweg ist gelesen (E286, E297) — aus den
    /// Einstellungen, im Prüflauf nur hier (dort schreibt niemand hinein).
    var rueckwegHinweisGezeigt: Bool = Einstellungen.wert(Einstellungen.Schluessel.rueckwegHinweis) ?? false

    // ── Tour durch die Oberfläche — geschrieben in Planungsspeicher+Tour.swift ───

    var tourSchritt: Tourschritt?

    /// Die Beispielzelle („G6a, KW 33“) — vom Raster gesetzt, für den Kartentext.
    var tourZelle = ""

    /// Nach dem Anlegen einer Planung vorgemerkt; gefragt wird, sobald kein
    /// Blatt mehr offen ist (Ersteinrichtung zuerst).
    var tourAnbieten = false

    var tourAngebotenInSitzung = false

    // ── Sitzplan — geschrieben in Planungsspeicher+Sitzplan.swift ─────────

    /// Die Klasse, deren Sitzplan der Editor zeigt — der Dialogzustand neben
    /// `offenerDialog`.
    var sitzplanKlasse: String?

    /// Wohin es nach dem Editor zurückgeht (⌘K), sonst ins Hauptfenster.
    var sitzplanRueckweg: Dialogfenster?

    /// Der Entwurf, wie ihn der Editor gerade hält — für ⌘P und ⇧⌘P aus der
    /// Menüleiste, die das Blatt nicht sehen.
    var sitzplanEntwurf: Sitzplan?

    /// Der Verlauf des Sitzplanblatts — der zweite Schauplatz (E82).
    ///
    /// Er liegt hier und nicht im Blatt, weil das Menü ihn erreichen muss: ⌘Z
    /// gehört dem Blatt, solange es offen ist. Den Entwurf selbst trägt das
    /// Blatt; wie er zurückgelegt wird, sagt ihm `sitzplanEntwurfSetzen`.
    let sitzplanverlauf = Ruecknahme<Sitzplan>()

    /// Wie der Entwurf ins Blatt zurückkommt — vom Blatt hereingereicht.
    @ObservationIgnored private var sitzplanEntwurfSetzen: (@MainActor (Sitzplan) -> Void)?

    /// Ob das Blatt offen ist — daran hängt, wem ⌘Z gehört (E87). Beobachtbar,
    /// damit der Menütitel den Wechsel mitbekommt; der Griff daneben nicht,
    /// denn eine Funktion ändert sich nicht, sie ist nur da.
    private(set) var sitzplanblattOffen = false

    /// Das Blatt tritt an: Ab jetzt gilt sein Verlauf.
    func sitzplanblattUebernimmt(_ setzen: @escaping @MainActor (Sitzplan) -> Void) {
        sitzplanEntwurfSetzen = setzen
        sitzplanblattOffen = true
    }

    /// Das Blatt geht: Sein Verlauf gilt nicht mehr und ist fort.
    func sitzplanblattGibtAb() {
        sitzplanEntwurfSetzen = nil
        sitzplanblattOffen = false
        sitzplanverlauf.leeren()
    }

    // ── Lernende — geschrieben in Planungsspeicher+Lernende.swift ────────

    /// Womit das Blatt „Lernende“ aufgeht — gesetzt beim Öffnen, gelesen vom
    /// Blatt beim Erscheinen.
    var lernendenVorgabe: Lernendenvorgabe?

    /// Termine, deren Vorhaben ein Handgriff der Planung nahm — gemerkt für ihr
    /// Widerrufen (E293: Gelöscht gehen immer beide, widerrufen kommen beide).
    /// Nur für die Sitzung, wie der Verlauf.
    @ObservationIgnored var terminablage: [String: Terminablage] = [:]

    /// Der Verlauf des Blatts „Lernende“ — ein eigener Schauplatz wie der
    /// Sitzplan-Editor: Das Blatt arbeitet auf einem Entwurf, „Übernehmen“
    /// schreibt ihn. Hier und nicht im Blatt, weil das Menü ihn erreichen muss.
    let lernendenverlauf = Ruecknahme<Lernendenbestand>()

    /// Wie der Entwurf ins Blatt zurückkommt — vom Blatt hereingereicht.
    @ObservationIgnored private var lernendenEntwurfSetzen: (@MainActor (Lernendenbestand) -> Void)?

    /// Ob das Blatt steht — daran hängt, wem ⌘Z gehört.
    private(set) var lernendenblattOffen = false

    /// Wie lange eine Rückfrage, die auf eine andere am selben Ort folgt, wartet:
    /// Das Schließen der ersten setzt die Rückfrage dieses Orts zurück — eine
    /// sofort gestellte zweite ginge mit ihr.
    static let folgefrageVerzug = 0.35

    /// Was das offene Blatt für die Fragen beim Beenden hereinreicht (E300, E303).
    @ObservationIgnored var lernendenblattGriff: Lernendenblattgriff?

    /// Eine Planung anderer Herkunft, die ⌘O öffnen will — bis das Blatt entscheidet (E305).
    var schuljahrwechsel: Schuljahrwechsel?

    /// Womit das Blatt „Neue Planung“ aufgeht — nur von Abbildern (`ABBILD_NEUEPLANUNG`, `ABBILD_FELD`) und der
    /// Dialogprobe (E628) gesetzt, gelesen beim Erscheinen (AP14c-2).
    @ObservationIgnored var neuePlanungVorgabe: Neuplanungsvorgabe?

    /// Eine IServ-Datei für den Bogen am Blatt „Neue Planung“ — nur Prüfstand und Abbild setzen sie, wenn das Blatt
    /// steht; das Blatt liest sie ohne Dateiwahl und öffnet den Bogen. Beobachtet: keine Frist im Programm (E610).
    var neuePlanungImportdatei: URL?

    /// Die Lage des Bogens „Lerngruppen zuordnen“ für Prüfstand und Abbild (E629, E630) — gesetzt, wenn das Blatt „Neue
    /// Planung“ oder „Neues Schuljahr öffnen“ steht; das Blatt öffnet den Bogen in dieser Lage und verwirft die Vorgabe.
    /// Beobachtet: keine Frist im Programm (wie E610).
    var zuordnungsbogenVorgabe: Zuordnungslage?

    /// Fragen, die kamen, während eine andere sichtbar stand — sie erscheinen
    /// nach deren Antwort (E317, B82).
    @ObservationIgnored var wartendeRueckfragen: [Rueckfrage] = []

    /// Fortsetzungen nach einer Antwort, die noch ausstehen — solange eine
    /// aussteht, holt die Warteschlange nichts nach: Die Folgefrage der
    /// beantworteten geht jeder wartenden vor (Z14c4-12, E319).
    @ObservationIgnored private(set) var ausstehendeFortsetzungen = 0

    /// Bestätigte Handlungen, die auf das Ende ihres Alerts warten (`nachDemSchliessenAusfuehren`) — nicht die
    /// übrigen Fortsetzungen: Archivlöschungen holt das Beenden selbst nach (Z-AS2a-07), „Trotzdem beenden“ und
    /// das Weiter des Beendens sind selbst das Beenden.
    @ObservationIgnored private(set) var verschobeneHandlungen = 0

    /// Das Alert ist fort, eine verschobene Handlung steht noch aus — die Lücke (AU4c). Befehle, das Beenden
    /// und die Eingaben prallen dann ab (E435–E437). Steht inzwischen eine Frage, wartet die Handlung auf sie,
    /// und die Lücke sperrt nicht mehr — hinter einer Frage, die nicht zu sehen ist, sperrte sie sonst für
    /// immer (Z-AU4c-04).
    var handlungAussteht: Bool { verschobeneHandlungen > 0 && rueckfrage == nil }

    /// Laufen gerade Fortsetzungen? Deren Weiter (Beenden, ⌘Z) geht an der Sperre einer anderen Lücke vorbei:
    /// Die Sperre gilt Eingaben, nicht der App selbst (Z-AU4c-10). Ein Zähler, kein Schalter (Z-AU4c-18).
    @ObservationIgnored private var laufendeFortsetzungen = 0
    private var inFortsetzung: Bool { laufendeFortsetzungen > 0 }

    /// Für den Ereignis-Monitor der App (Z-AU4c-01/-02): In der Lücke prallen Tasten und Klicks ab, mit Ton.
    func eingabeSperrt() -> Bool {
        guard handlungAussteht else { return false }
        gesperrteBefehle += 1
        systemton()
        return true
    }

    /// Der Grund für ein Skript, dessen Beenden zurückkam — gebildet aus dem Zustand jetzt (Z-AU4c-07).
    /// `wartete`: Vor dem Beenden stand ein Alert. Blendete es nur noch aus, steht keine Frage — es gilt
    /// die Lücke (Z-AU4c-06). Die Frage ist die gesetzte oder die unter einem Bogen wartende (Z-AU3-12).
    func beendengrundJetzt(wartete: Bool) -> String {
        Self.beendengrund(frage: frageFuerSkript, wartete: wartete && !handlungAussteht, archiv: beendenAmArchivAngehalten,
                          blatt: Planungsspeicher.blattHaengt(), handlung: handlungAussteht)
    }

    /// Für die Knöpfe der Blätter (E437): In der Lücke prallt der Knopf ab wie ein Befehl, mit Ton —
    /// ohne das Blatt im Klick umzubauen (kein `.disabled`, Gattung B88). Die zweite Linie hinter dem Monitor.
    func blattknopf(_ handlung: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        { [weak self] in
            guard self?.frageSperrtBefehl() != true else { return }
            handlung()
        }
    }

    /// Bestätigte Löschungen im Archiv, die auf das Ende ihres Alerts warten — das Beenden
    /// führt sie vorher noch aus (Z-AS2a-07). Geschrieben in `Planungsspeicher+Lernende.swift`.
    /// Eine bleibt hier, bis sie angewandt ist, auch während sie das Archiv abseits liest (F-02);
    /// `loeschen` nimmt, was dabei gelesen wurde — `nil`: Dann liest sie selbst, gleichlaufend.
    @ObservationIgnored var ausstehendeArchivloeschungen: [(kennung: UUID,
                                                            loeschen: @MainActor (Lernendendienst.Archivbefund?) -> Void)] = []

    /// Die letzte Löschung, die das Archiv abseits liest — die nächste liest erst nach ihr; wartet eine hinter einer
    /// Frage oder einem ausblendenden Alert, liest sie danach neu. So schreibt keine einen Stand von vor einer anderen
    /// (F-02, Z-AS2a-02, E962). In `+Lernende.swift`.
    @ObservationIgnored var archivloeschungskette: Task<Void, Never>?

    /// Die Löschungen, deren Fortsetzung schon lief und die jetzt abseits lesen, auf die vorige warten oder nach dem
    /// Lesen hinter einer Frage oder einem ausblendenden Alert warten (F-02, Z-BA3-01, E962) — bis v88 wären sie in
    /// der Fortsetzung gleich geschehen. In `+Lernende.swift`.
    @ObservationIgnored var archivloeschungenUnterwegs: Set<UUID> = []

    /// Wie oft das Archiv sich nicht schreiben ließ — das Beenden sieht daran, ob eine
    /// ausstehende Löschung scheiterte (Z-AS2a-08), auch eine nach „Trotzdem beenden“ (Z-AU2-04).
    /// Geschrieben in `+Lernende.swift`.
    @ObservationIgnored var archivSchreibfehler = 0

    /// Was die Fortsetzung einer Löschung im Archiv eben las — nur, solange sie läuft, und nur für das erste
    /// Schreiben in `dann`, vor jeder anderen Änderung am Archiv: Es nimmt den Befund, statt das Archiv noch
    /// einmal zu entschlüsseln (B94, E454). In `+Lernende.swift`.
    @ObservationIgnored var archivVorgelesen: Lernendendienst.Archivbefund?

    /// Wie oft ein Befehl oder eine Eingabe abprallte — an einer sichtbaren Rückfrage oder in der Lücke danach;
    /// für den Prüfstand (Z14c4-05, AU4c).
    @ObservationIgnored private(set) var gesperrteBefehle = 0

    /// Ob eine Rückfrage als Alert zu sehen ist (E315) — die Prüfungen geben es vor.
    @ObservationIgnored var rueckfrageSichtbar: @MainActor () -> Bool = { Planungsspeicher.alertAngeheftet() }

    /// Das Beenden der App; kehrt es zurück, war es abgelehnt. Die Prüfungen hängen sich ein (E415, E426).
    @ObservationIgnored var appBeenden: @MainActor () -> Void = { NSApp.terminate(nil) }

    /// Ein Skript wartet auf das Beenden: Wird es erst nach dem Schließen der Blätter abgelehnt, erfährt
    /// der AppleEvent-Griff hier den Grund (B90, E416).
    @ObservationIgnored var beendenAbgelehnt: (@MainActor (String) -> Void)?

    /// Das Fenster für die Frage beim Beenden (`fensterFuerFrageSuchen`) — die Prüfungen geben es vor (E425).
    @ObservationIgnored var fensterFuerFrage: @MainActor () -> (@MainActor () -> Void)? = { Planungsspeicher.fensterFuerFrageSuchen() }

    /// Ob an einem Blatt ein Bogen hängt, der kein Alert ist — ein Sichern-, Öffnen- oder
    /// Druckdialog, ein Bogen der Oberfläche (Z-AS3-11). Die Prüfungen geben es vor.
    @ObservationIgnored var bogenSichtbar: @MainActor () -> Bool = { Planungsspeicher.bogenAmBlatt() }

    /// Der Anzeigename einer Datei, wie ihn der Finder zeigt — ohne Endung, wenn er sie ausblendet (Z-AU11-04).
    /// Die Prüfungen geben ihn vor.
    @ObservationIgnored var anzeigenameVon: @MainActor (URL) -> String = { FileManager.default.displayName(atPath: $0.path) }

    func lernendenblattUebernimmt(_ setzen: @escaping @MainActor (Lernendenbestand) -> Void,
                                  griff: Lernendenblattgriff = Lernendenblattgriff()) {
        lernendenEntwurfSetzen = setzen
        lernendenblattGriff = griff
        lernendenblattOffen = true
    }

    func lernendenblattGibtAb() {
        lernendenEntwurfSetzen = nil
        lernendenblattGriff = nil
        lernendenblattOffen = false
        lernendenverlauf.leeren()
    }

    // ── Titel und Einstellungen — geschrieben in Planungsspeicher+Bearbeiten.swift ───

    var titelentwurf: String?

    let titelentpreller = Entpreller()

    // ── Meldungen ─────────────────────────────────────────────────────────

    /// Fängt Meldungen auf, statt sie zu zeigen — solange `neuePlanung` beim Anlegen einschaltet: Wird das Einschalten
    /// zurückgenommen, ersetzt eine Warnung die allgemeine des Übergangs (E478, E529); sonst kommen sie wie gefangen.
    @ObservationIgnored var meldungsfang: [(text: String, art: Meldung.Art)]?

    /// Meldungen, denen eine neuere folgte — im Fuß eines Blatts kommen sie nicht wieder (E856). Am Speicher, nicht an der
    /// Kapsel: Ein neu entstehender Fuß kennte sie sonst nicht (Z-AX9R5-03). Mit der Meldung fällt der Vermerk.
    @ObservationIgnored private(set) var gewicheneMeldungen: Set<UUID> = []

    func melden(_ text: String, _ art: Meldung.Art = .hinweis) {
        if meldungsfang != nil {
            meldungsfang?.append((text, art))
            return
        }
        let meldung = Meldung(text: text, art: art)
        gewicheneMeldungen.formUnion(meldungen.map(\.id))
        meldungen.append(meldung)
        takt.aufgabe(nach: .milliseconds(art == .warnung ? 5200 : 2800)) { [weak self] in
            self?.meldungSchliessen(meldung.id)
        }
    }

    func meldungSchliessen(_ id: UUID) {
        meldungen.removeAll { $0.id == id }
        gewicheneMeldungen.remove(id)
    }

    /// Meldungen, die unter einer Frage oder hinter einem Blatt ungelesen
    /// verfielen — sie erscheinen, sobald nichts davon mehr offen ist; ihre
    /// Uhr läuft erst dann (Z14c4-14, E334). `datei`: die Datei, von der sie sagt,
    /// sie sei nicht geöffnet.
    @ObservationIgnored private var vorgemerkteMeldungen: [(text: String, art: Meldung.Art, datei: URL?)] = []

    /// Keine Frage — auch keine wartende und keine, die eine Fortsetzung noch
    /// stellen kann (Z-AS2-02) —, kein Blatt, auch keins im Kommen, kein freier
    /// Dialog (Z-AS2-04): Eine Meldung wäre zu sehen.
    private var meldungZuSehen: Bool {
        rueckfrage == nil && wartendeRueckfragen.isEmpty && ausstehendeFortsetzungen == 0
            && offenerDialog == nil && naechsterDialog == nil && vorhabenDialog == nil
            && Dialogort.freieDialoge == 0
    }

    /// Wie `melden` — steht eine Frage oder ein Blatt, erst danach; derselbe
    /// Text zur selben Datei nur einmal (ein ungeduldiger Doppelklick im Finder).
    func spaeterMelden(_ text: String, _ art: Meldung.Art = .hinweis, datei: URL? = nil) {
        guard !meldungZuSehen else { melden(text, art); return }
        let schluessel = datei.map(Planungsspeicher.dateischluessel)
        // Text und Datei: Zwei Dateien gleichen Namens sind zwei Abweisungen (Z-AS2-11).
        if !vorgemerkteMeldungen.contains(where: { $0.text == text && $0.datei == schluessel }) {
            vorgemerkteMeldungen.append((text, art, schluessel))
        }
    }

    /// Ging die Datei doch noch auf — ein zweites Öffnen derselben Datei, während
    /// das erste fragte —, gilt ihr „nicht geöffnet“ nicht mehr (Z-AS2-01).
    func vorgemerkteMeldungenVerwerfen(datei: URL) {
        let ziel = Planungsspeicher.dateischluessel(datei)
        vorgemerkteMeldungen.removeAll { $0.datei == ziel }
    }

    /// Dieselbe Datei auf jedem Weg — auch über einen Symlink (Z-AS2-12).
    static func dateischluessel(_ url: URL) -> URL { Systemzugriff.vereinheitlicht(url.path) }

    /// Die Datei, deren Öffnen gerade auf eine Entscheidung wartet: ihre Frage
    /// „… wird ersetzt“ (`frage`) oder ihr Blatt „Neues Schuljahr öffnen“.
    @ObservationIgnored var dateiInEntscheidung: (datei: URL, frage: UUID?)?

    /// Steht über diese Datei schon eine Entscheidung an? Dann weist ein zweites
    /// Öffnen still ab — kein „nicht geöffnet“ hinterher, was immer entschieden
    /// wird (Z-AS2-10).
    func entscheidungSteht(ueber url: URL) -> Bool {
        guard let steht = dateiInEntscheidung, steht.datei == Planungsspeicher.dateischluessel(url) else { return false }
        // Das Blatt muss wirklich stehen oder gleich kommen: Ein Sprung schließt es, ohne
        // `schuljahrwechsel` zu leeren (Z-AS2-16).
        guard let frage = steht.frage else {
            return schuljahrwechsel != nil && (offenerDialog == .schuljahrOeffnen || naechsterDialog == .schuljahrOeffnen)
        }
        return rueckfrage?.id == frage || wartendeRueckfragen.contains { $0.id == frage }
    }

    /// Aus den `didSet` von Frage und Blättern, nach einer Fortsetzung und nach
    /// dem letzten freien Dialog (`Dialogort.nachDemSchliessen`). Über eine
    /// Aufgabe wie `statusNachholenWennFrei`: nicht in derselben Änderung — und
    /// erst, wenn ein Wechsel der Blätter vorüber ist (`naechstenDialogOeffnen`
    /// setzt zwei Werte) und die Handlung einer Antwort gelaufen ist.
    func vorgemerkteMeldungenZeigen() {
        guard !vorgemerkteMeldungen.isEmpty, meldungZuSehen else { return }
        takt.gleich { [weak self] in
            guard let self, meldungZuSehen, !vorgemerkteMeldungen.isEmpty else { return }
            let faellige = vorgemerkteMeldungen
            vorgemerkteMeldungen = []
            // Die Zeile zum Verlust kündigt eine dieser Meldungen an — sie geht mit ihr (E779, Z-AX0b-02).
            verlustUnterDerErsteinrichtung = nil
            for meldung in faellige { melden(meldung.text, meldung.art) }
        }
    }

    /// `nachDemSchliessen`: Die Knöpfe bauen die Hauptfläche oder ein Blatt um — ihre Handlungen laufen
    /// erst, wenn das Alert fort ist (B88, B95, E417, E430).
    func fragen(_ text: String, bestaetigung: String, gefahr: Bool = false,
                ort: Rueckfrageort = .hauptansicht,
                ablehnung: String = "Abbrechen", beiAblehnung: (@MainActor () -> Void)? = nil,
                weitere: String? = nil, weitereGefahr: Bool = false, bestaetigungZuerst: Bool = false,
                beiWeitere: (@MainActor () -> Void)? = nil,
                nachDemSchliessen: Bool = false,
                handlung: @escaping @MainActor () -> Void) {
        var abgelehnt = beiAblehnung, dritte = beiWeitere
        if nachDemSchliessen, let ab = beiAblehnung { abgelehnt = nachDemSchliessenAusfuehren(ab) }
        if nachDemSchliessen, let weiter = beiWeitere { dritte = nachDemSchliessenAusfuehren(weiter) }
        frageStellen(Rueckfrage(text: text, bestaetigung: bestaetigung, gefahr: gefahr, ort: ort,
                                ablehnung: ablehnung, beiAblehnung: abgelehnt,
                                weitere: weitere, weitereGefahr: weitereGefahr, bestaetigungZuerst: bestaetigungZuerst,
                                beiWeitere: dritte,
                                handlung: nachDemSchliessen ? nachDemSchliessenAusfuehren(handlung) : handlung))
    }

    /// Eine Handlung, die erst läuft, wenn das Alert fort ist; hängt keines (mehr), gleich (E431). Kommt eine
    /// andere Frage dazwischen, nach deren Antwort — Bestätigtes geht nicht verloren (Z-AS2a-01).
    func nachDemSchliessenAusfuehren(_ handlung: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        { [weak self] in
            guard let self else { return }
            guard rueckfrageSichtbar() else {
                handlung()
                return
            }
            // Bis sie läuft, prallen Befehle, Beenden und die Knöpfe der Blätter ab (E435–E437).
            verschobeneHandlungen += 1
            nachDerAntwort(immer: true) { [weak self] in
                self?.verschobeneHandlungen -= 1
                handlung()
            }
        }
    }

    /// Der eine Weg, eine Rückfrage zu stellen. Solange ein Alert angeheftet
    /// ist, legt sich keine zweite darüber — SwiftUI schlösse dessen Blatt mitten
    /// im Layout (B82); sie wartet und erscheint danach (E317). Das gilt auch für
    /// eine Frage aus der Handlung der beantworteten: `rueckfrage` ist dann schon
    /// nil, das Alert-Blatt noch da (Z14c4-02). Eine gesetzte, aber nicht
    /// angezeigte weicht nur einer neuen, deren Ort zu sehen ist; die wartenden bleiben.
    ///
    /// Ohne Alert gilt die Lage ihres Orts wie in der Warteschlange (B89, E418):
    /// Gesetzt wird sie nur, wo sie zu sehen ist. Gesetzt hinter einem Blatt oder
    /// unter einem Bogen stünde sie unsichtbar — sie sperrte das Menü still,
    /// hielte zurückgestellte Handlungen samt der Lücke fest (Z-AU4b-05, Z-AU4b-12)
    /// und verdrängte im Grund für ein Skript das Blatt (Z-AU3-12).
    func frageStellen(_ frage: Rueckfrage) {
        if rueckfrageSichtbar() {
            // Aus der Handlung der eben beantworteten: eine Folgefrage — sie geht vor (Z14c4-12).
            if rueckfrage == nil { folgefrageEinreihen(frage) } else { wartendeRueckfragen.append(frage) }
            wartendeNachholen()
            return
        }
        switch ortslage(frage.ort) {
        case .sichtbar:
            rueckfrage = frage
        case .verdeckt:
            // Ein Bogen liegt über ihrem Blatt, oder es ist im Kommen — sie wartet und erscheint danach (Z-AS3-03).
            // Eine Folgefrage aus einer Fortsetzung geht vor, wie unter einem Alert (Z14c4-12, Z-AU5-02).
            if inFortsetzung { folgefrageEinreihen(frage) } else { wartendeRueckfragen.append(frage) }
            wartendeNachholen()
        case .fort:
            // Das Blatt der Frage ist zu, oder über der Hauptfläche liegt eines: Die Frage entfällt — der Ton sofort, der Text,
            // wenn nichts mehr offen ist (E330, E394, Z-AU5-03).
            systemton()
            spaeterMelden(Planungsspeicher.sofortEntfallenhinweis(frage.ort), .warnung)
        }
    }

    /// Ist die Rückfrage beantwortet, kommt die nächste wartende — nach einer
    /// Folgefrage, deren Fortsetzung `folgefrageVerzug` wartet (Z14c4-01), und
    /// erst, wenn kein Alert mehr hängt; nur, wenn bis dahin keine andere steht
    /// (Z14b-11). Eine Kette zugleich — jede weitere liefe neben ihr her (Z-AU5-09).
    private func wartendeNachholen() {
        guard rueckfrage == nil, !wartendeRueckfragen.isEmpty, !nachholenGeplant else { return }
        nachholenGeplant = true
        takt.nach(Planungsspeicher.nachholfrist) { [weak self] in
            guard let self else { return }
            nachholenGeplant = false
            guard rueckfrage == nil, !wartendeRueckfragen.isEmpty else { return }
            // Steht noch ein Alert — der ausblendende oder ein eigener eines Dialogs —, weiter
            // warten: Darüber gelegt, schlösse SwiftUI ihn mitten im Layout (B82, Z14c4-10).
            // Ebenso, solange eine Fortsetzung aussteht (E319).
            if rueckfrageSichtbar() || ausstehendeFortsetzungen > 0 {
                wartendeNachholen()
                return
            }
            // Eine Frage, deren Ort fort ist, entfällt — gesetzt bliebe sie unsichtbar und sperrte
            // das Menü still (Z14c4-06, E330). Gesagt erst nach dem Entfernen, sonst wartete der
            // Hinweis selbst auf die Warteschlange — und je Text einmal (Z-AS3-02).
            var hinweise: [String] = []
            while let naechste = wartendeRueckfragen.first, ortslage(naechste.ort) == .fort {
                wartendeRueckfragen.removeFirst()
                let hinweis = Planungsspeicher.entfallenhinweis(naechste.ort)
                if !hinweise.contains(hinweis) { hinweise.append(hinweis) }
            }
            for hinweis in hinweise { spaeterMelden(hinweis, .warnung) }
            guard let erste = wartendeRueckfragen.first else {
                // Kein Wechsel der Frage folgt — vorgemerkte Meldungen brauchen ihren Anstoß selbst.
                vorgemerkteMeldungenZeigen()
                return
            }
            // Verdeckt oder ihr Blatt im Kommen: später erneut nachsehen, nicht verwerfen (Z-AS3-03).
            guard ortslage(erste.ort) == .sichtbar else {
                wartendeNachholen()
                return
            }
            rueckfrage = wartendeRueckfragen.removeFirst()
        }
    }

    /// Ein Nachsehen der Warteschlange ist geplant (`wartendeNachholen`).
    @ObservationIgnored private var nachholenGeplant = false

    /// Die Folgefragen seit der letzten Antwort — sie stehen vorn, in der Folge ihrer Handlungen (Z-AU5-12).
    @ObservationIgnored private var folgefragenDerWelle: Set<UUID> = []

    /// Eine Folgefrage geht den wartenden vor, hinter die schon eingereihten derselben Antwort (Z14c4-12, Z-AU5-12).
    private func folgefrageEinreihen(_ frage: Rueckfrage) {
        let stelle = wartendeRueckfragen.prefix { folgefragenDerWelle.contains($0.id) }.count
        wartendeRueckfragen.insert(frage, at: stelle)
        folgefragenDerWelle.insert(frage.id)
    }

    /// Setzt nach einer Antwort fort, sobald ihr Alert-Blatt fort ist — und nur,
    /// wenn bis dahin keine andere Frage steht (Z14b-11). Nie in der
    /// Knopf-Handlung selbst: Dort hängt das Alert noch, und `beenden()` kehrte
    /// an seiner Sperre um (Z14c3-12, E319).
    /// `immer`: Steht bis dahin eine andere Frage, wird nicht verworfen, sondern nach
    /// deren Antwort fortgesetzt — für Bestätigtes, das geschehen muss (Z-AS2a-01).
    /// `entfaellt`: läuft, wenn die Fortsetzung ohne `immer` entfällt (Z-AU4a-12).
    func nachDerAntwort(immer: Bool = false, entfaellt: (@MainActor () -> Void)? = nil,
                        _ dann: @escaping @MainActor () -> Void) {
        // Aus Bestätigtem, das eine andere Frage abwartete: Über das Weitere entschied sie (Z14b-11, Z-AU4a-01).
        guard immer || !nachAndererFrage else {
            entfaellt?()
            return
        }
        ausstehendeFortsetzungen += 1
        fortsetzen(dann, nach: Planungsspeicher.folgefrageVerzug, versuch: 0, immer: immer, entfaellt: entfaellt)
    }

    private func fortsetzen(_ dann: @escaping @MainActor () -> Void, nach frist: Double, versuch: Int, immer: Bool,
                            entfaellt: (@MainActor () -> Void)?) {
        takt.nach(frist) { [weak self] in
            guard let self else { return }
            // Blendet das Alert noch aus: 50 ms später erneut, höchstens rund 2,9 s.
            if rueckfrage == nil, rueckfrageSichtbar(), versuch < 50 {
                fortsetzen(dann, nach: 0.05, versuch: versuch + 1, immer: immer, entfaellt: entfaellt)
                return
            }
            ausstehendeFortsetzungen -= 1
            // Auch eine vorgemerkte Meldung wartete auf sie (Z-AS2-02); die Aufgabe sieht erst nach `dann` nach.
            vorgemerkteMeldungenZeigen()
            // Steht inzwischen eine andere Frage, gilt sie — das Beenden wartet auf ein neues ⌘Q.
            // Bestätigtes dagegen geht nach ihrer Antwort weiter (Z-AS2a-01).
            guard rueckfrage == nil else {
                if immer { zurueckgestellt.append(dann) } else { entfaellt?() }
                return
            }
            laufendeFortsetzungen += 1
            defer { laufendeFortsetzungen -= 1 }
            dann()
        }
    }

    /// Bestätigte Handlungen, die eine andere Frage abwarten (Z-AS2a-01) — angestoßen
    /// aus dem `didSet` von `rueckfrage`, kein Takt.
    @ObservationIgnored private var zurueckgestellt: [@MainActor () -> Void] = []

    /// Läuft gerade Bestätigtes, das eine andere Frage abwartete? Eine Fortsetzung, die es anstößt, entfällt dann.
    @ObservationIgnored private var nachAndererFrage = false

    private func zurueckgestellteNachholen() {
        guard rueckfrage == nil, !zurueckgestellt.isEmpty else { return }
        let faellige = zurueckgestellt
        zurueckgestellt = []
        for dann in faellige {
            nachDerAntwort(immer: true) { [weak self] in
                guard let self else { return }
                nachAndererFrage = true
                defer { nachAndererFrage = false }
                dann()
            }
        }
    }

    /// Steht eine Rückfrage sichtbar, tut ein Befehl, der selbst fragen oder
    /// darunter ändern könnte, nichts — mit Systemton (E317, E318). Ebenso in der
    /// Lücke danach, bis die bestätigte Handlung gelaufen ist (E435).
    func frageSperrtBefehl() -> Bool {
        guard alertSteht || handlungAussteht && !inFortsetzung else { return false }
        gesperrteBefehle += 1
        systemton()
        return true
    }

    /// Wie oft ein Systemton fällig war — auch im Prüflauf gezählt, wo er stumm bleibt (Z-AS3-08).
    @ObservationIgnored private(set) var systemtoene = 0

    /// Der Systemton — nie im Prüflauf.
    func systemton() {
        systemtoene += 1
        guard !Ablage.istPruefstand else { return }
        NSSound.beep()
    }

    func rueckfrageBeantworten(_ bestaetigt: Bool) {
        let frage = rueckfrage
        folgefragenDerWelle = []
        rueckfrage = nil
        if bestaetigt { frage?.handlung() } else { frage?.beiAblehnung?() }
    }

    /// Der dritte Knopf einer Rückfrage.
    func rueckfrageWeitere() {
        let frage = rueckfrage
        folgefragenDerWelle = []
        rueckfrage = nil
        frage?.beiWeitere?()
    }

    // ── Suche ─────────────────────────────────────────────────────────────

    private static func zerlegen(_ begriff: String) -> [String] {
        begriff.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Titel, Beschreibung, Hausaufgabe, Kurs, Materialien und Links — alle
    /// Suchworte müssen vorkommen.
    func trifft(_ vorhaben: Vorhaben, klasse: Klasse?) -> Bool {
        guard !suchworte.isEmpty else { return true }
        var heu = vorhaben.titel + " " + vorhaben.text + " " + vorhaben.hausaufgabenText
        heu += " " + (klasse?.name ?? "") + " " + (klasse?.fach ?? "")
        for m in vorhaben.materialien { heu += " " + m.titel + " " + m.pfad }
        for l in vorhaben.links { heu += " " + l.titel + " " + l.adresse }
        let kleingeschrieben = heu.lowercased()
        return suchworte.allSatisfy { kleingeschrieben.contains($0) }
    }

    var sucheLaeuft: Bool { !suchworte.isEmpty }

    // ── Einstellungen ─────────────────────────────────────────────────────

    enum Erscheinung: String, CaseIterable, Identifiable, Sendable {
        case system, hell, dunkel
        var id: String { rawValue }
        var beschriftung: String {
            switch self {
            case .system: "Systemvorgabe"
            case .hell: "Hell"
            case .dunkel: "Dunkel"
            }
        }
    }

    // ── Dienste ───────────────────────────────────────────────────────────

    /// Die laufende Sicherung in der Ablage und die Kopie außer Haus — mit der
    /// hereingereichten Ablage; `Ablage.shared` kennt nur der Delegat.
    let sicherung: Sicherungsdienst

    /// Die Lesezeichen und der Zielordner der Kopie — der Vorrat des
    /// Sicherungsdienstes, für Oberfläche und Prüfstände.
    var zugriff: Ordnerzugriff { sicherung.zugriff }

    /// Die Sitzpläne neben der Planung — unter demselben Schutz wie sie.
    var sitzplaene: Sitzplandienst { sicherung.sitzplaene }
    var lernende: Lernendendienst { sicherung.lernende }

    /// Einwilligung, Frist und Angebot der Prüfung auf Updates.
    let updates: Updatekoordinator

    /// Der Takt der Zeitgeber (AT6f-1, E548) — im Betrieb der Systemtakt; eine Prüfung setzt ihren gleich nach dem
    /// Anlegen. Er gilt mit für das Sichern, den Titel und die Updates.
    @ObservationIgnored var takt: any Taktgeber = Systemtakt.gemeinsam {
        didSet {
            sicherung.takt = takt
            titelentpreller.takt = takt
            updates.takt = takt
        }
    }

    /// Die Erlaubnis für die Materialliste von 3ducation.org — und das Laden.
    let materialliste: Materialkoordinator

    /// Der Stand von der Platte wird genau einmal geladen.
    private var gestartet = false

    /// Für die Werkzeugleiste: Seit wann auch immer — es wird gerade nichts
    /// gesichert, und das muss sichtbar bleiben, nicht nur kurz aufblitzen.
    var sicherungLiegtStill: Bool { sicherung.liegtStill }

    // ── Start ─────────────────────────────────────────────────────────────

    /// Mit hereingereichter Ablage: `Ablage.shared` bringt der Delegat mit,
    /// Prüfungen eine `Ablage(ordner: temp)`. Die Dienste schreiben, der
    /// Speicher spricht — die Rückwege dafür werden hier geknüpft.
    init(ablage: Ablage, vorschau: Bool = false) {
        sicherung = Sicherungsdienst(ablage: ablage, vorschau: vorschau)
        updates = Updatekoordinator(pruefstand: Ablage.istPruefstand)
        materialliste = Materialkoordinator(pruefstand: Ablage.istPruefstand)
        // `didSet` läuft für die Zuweisung im Aufbau nicht — hier selbst rasten.
        let gespeicherteBreite: Double = Einstellungen.wert(Einstellungen.Schluessel.spaltenbreite) ?? 0
        spaltenbreite = gespeicherteBreite > 0
            ? Kennwerte.spalteRasten(gespeicherteBreite) : Kennwerte.spalteStandard
        erscheinung = Erscheinung(
            rawValue: Einstellungen.wert(Einstellungen.Schluessel.erscheinung) ?? "") ?? .system

        sicherung.sitzungsquelle = { [weak self] in
            // Offene Feldeingaben zuerst — sonst ginge das zuletzt Getippte verloren.
            Entpreller.allesUebernehmen()
            return self?.sitzung ?? .leer
        }
        // Eine Meldungssenke für alle Dienste — sie schreiben, der Speicher spricht.
        let senke: @MainActor (String, Meldung.Art) -> Void = { [weak self] text, art in self?.melden(text, art) }
        sicherung.melden = senke
        sicherung.zugriff.melden = senke
        sicherung.sitzplaene.melden = senke
        sicherung.lernende.melden = senke
        updates.melden = senke
        updates.beiAngebot = { [weak self] in self?.updateAnzeigenPruefen() }
    }

    /// Mit der Ablage des Prozesses — der Sicherungsweg der Prüfungen, die
    /// über `PLANUNGSORDNER` an einem eigenen Ort arbeiten.
    convenience init() {
        self.init(ablage: .shared)
    }

    /// Für Vorschauen und Prüfungen: mit fertiger Planung starten, ohne die
    /// Platte anzufassen. Die Sicherung bleibt gesperrt.
    convenience init(vorschau: Planung?) {
        self.init(ablage: .shared, vorschau: true)
        planung = vorschau
        gestartet = true
        sicherung.gesperrt = true
    }

    /// Den letzten Stand laden. Ist keiner da, fragt die Oberfläche nach einer
    /// neuen Planung.
    func starten() {
        guard !gestartet else { return }
        gestartet = true
        // Ein Prüfordner außerhalb des Containers: nichts laden, kein Blatt —
        // die Schranke vor dem Prüfstand nennt den Grund und beendet.
        guard Ablage.pruefordnerZulaessig else {
            melden("PLANUNGSORDNER liegt außerhalb des Containers — im Sandbox arbeitet "
                   + "ein Prüflauf nur dort.", .warnung)
            return
        }
        if let fehler = sicherung.kopielageBeimStart() { melden(fehler, .warnung) }
        standAufnehmen()
    }

    /// Wiederanlauf und Laden — der eine Weg, auf dem ein Stand in die Sitzung
    /// kommt. Er läuft beim Start und noch einmal, wenn der Nutzer eine
    /// Blockade geräumt hat: Der Ordner ist dann ein anderer geworden, und ein
    /// Ausweg, der nur die Sperre nähme, ließe eine leere Sitzung über einem
    /// ungelesenen Stand schreiben (N54-01, E71).
    private func standAufnehmen() {
        // Ein Übergang des Schutzes, der beim letzten Beenden nicht zu Ende kam
        // (E50): vollenden oder verwerfen — vor dem ersten Lesen, ohne Schlüssel.
        // Er allein gibt die Ablage frei.
        guard uebergangWiederanlaufen() else { return }

        switch sicherung.ablageLesen() {
        case .keine:
            // Beim ersten Start erst die Frage nach der Verschlüsselung (v84, D1b).
            neuePlanungOeffnen()
        case .unlesbar(let fehler):
            unlesbarenStandBehandeln(fehler)
        case .zuGross(let groesse):
            // Über der Decke hat diese App nicht geschrieben: beiseite wie ein
            // beschädigter Stand, mit der Größe im Satz.
            sicherung.ablage.beschaedigtenStandBeiseitelegen(stempel: Zeitrechnung.dateistempel())
            beschaedigtenStandRetten(beschreibung: "mit \(groesse / 1024 / 1024) MB größer als die "
                                     + "Decke der eigenen Ablage (\(Sicherungsdienst.lesedecke / 1024 / 1024) MB)")
        case .daten(let gelesen):
            // Zwischen Schreibgrenze und Decke (ein Bestand aus ≤ v42): geladen —
            // die Sicherung steht, bis die Planung kürzer ist.
            if gelesen.count > Sicherungsdienst.schreibgrenze { sicherung.lageMelden(.zuGross(gelesen.count)) }
            if Tresor.istBehaelter(gelesen) {
                // Verschlüsselt: erst entsperren, dann laden. Der Datenschlüssel
                // kommt aus der Enklave (fragt Touch ID) oder aus der Passphrase.
                entsperrungBeginnen(.ablage(gelesen))
            } else {
                geladenAusKlartext(gelesen)
            }
        }
        // Die Lesezeichen und die Sitzpläne stehen offen, sobald die Ablage es
        // ist: im Klartext jetzt; hinter einer versiegelten Ablage erst nach dem
        // Entsperren — das holt `entsperrt(mit:)` nach.
        if verschluesselungsstand != .gesperrt {
            lesezeichenNachruesten()
            sitzplaeneLaden()
            sitzplaeneAufraeumen()
            lernendeLaden()
        }
    }

    // ── Der Ausweg aus einer blockierten Ablage (E67) ─────────────────────

    /// Der Ordner ist blockiert: Der Wiederanlauf konnte keinen stimmigen
    /// Stand feststellen, und seither ändert kein Weg mehr etwas.
    var blockadeOffen: Bool { sicherung.wiederanlaufBlockade != nil }

    /// Die Rückfrage vor dem Räumen — sie zählt auf, was liegt, und sagt, wohin
    /// es geht. Gelöscht wird nichts — alles landet gestempelt im Register
    /// neben der Planung und geht jeden weiteren Wechsel des Schutzes mit.
    func blockadeRaeumenFragen() {
        guard let grund = sicherung.wiederanlaufBlockade, !frageSperrtBefehl() else { return }
        let spuren = sicherung.blockadespuren
        var text = "Die Ablage ist gesperrt, weil sich kein stimmiger Stand feststellen ließ "
            + "(\(grund)).\n\nBeiseitelegen räumt den Weg: "
        text += spuren.isEmpty
            ? "Es wird nichts gelöscht."
            : (spuren.count == 1 ? "Die Datei " : "Die \(spuren.count) Dateien ")
                + spuren.map { "„\($0)“" }.joined(separator: ", ")
                + (spuren.count == 1 ? " wandert" : " wandern")
                + " unter einem Stempelnamen neben die Planung. Gelöscht wird nichts."
        // Unpersönlich, Wortlaut des Nutzers (E829).
        text += "\n\nDanach schreibt die App wieder. Der Ordner muss für einen späteren Vergleich der "
            + "Dateien vorher gesichert werden."
        fragen(text, bestaetigung: "Beiseitelegen", nachDemSchliessen: true) { [weak self] in
            guard let self else { return }
            switch sicherung.blockadeRaeumen() {
            case .geraeumt(let namen):
                let beiseite = namen.isEmpty
                    ? "Es lag nichts mehr, was beiseitezulegen war."
                    : "\(namen.count == 1 ? "Die Datei liegt" : "\(namen.count) Dateien liegen") als "
                      + "\(namen.map { "„\($0)“" }.joined(separator: ", ")) neben der Planung."
                // Der Ordner ist ein anderer geworden: Wiederanlauf und Laden
                // laufen noch einmal wie bei einem Neustart (N54-01, E71).
                standAufnehmen()
                melden(beiseite + " " + standnachricht())
            case .gescheitert(let grund):
                melden("Die Sperre der Ablage bleibt: \(grund.satzanfang). Bitte im Ordner der Ablage nachsehen.", .warnung)
            }
        }
    }

    /// Was aus der Ablage geworden ist, nachdem der Ausweg sie geräumt hat —
    /// der Nutzer soll den Vorgang nicht erraten müssen (E71).
    private func standnachricht() -> String {
        if let grund = sicherung.wiederanlaufBlockade {
            return "Die Ablage bleibt gesperrt: \(grund.satzanfang)."
        }
        if verschluesselungsstand == .gesperrt {
            return "Die Planung ist versiegelt — sie wartet auf das Entsperren."
        }
        if planung != nil {
            return "Der bisherige Stand ist neu eingelesen; die App schreibt wieder."
        }
        return "In der Ablage liegt keine Planung — lege eine neue an."
    }

    /// Was der Übergabestand beim Start vorfindet (E50, E53): Eine Marke mit
    /// passenden Zwillingen wird eingesetzt; Zwillinge ohne Marke werden
    /// entfernt; was nicht zu vollenden ist, geht über die Vorgänger zurück und
    /// kommt gestempelt ins Register — der bisherige Stand gilt. Nur wenn
    /// nichts einzusetzen und nichts beiseitezulegen war (der Ordner lässt sich
    /// nicht schreiben) oder der Rückweg fehlt (zwei Stände), wird nichts
    /// geladen — `false`.
    private func uebergangWiederanlaufen() -> Bool {
        let befund = sicherung.uebergangWiederanlaufen(stempel: Zeitrechnung.dateistempel())
        // Erst die Lage der Ablage, dann die Meldung: Was nicht freigegeben
        // ist, ändert von hier an niemand mehr — kein Dienst, keine
        // Rettungskopie, kein Nachziehen (E66).
        switch befund {
        case .nichts, .vollendet, .zurueckgenommen, .beiseitegelegt:
            sicherung.wiederanlaufFreigeben()
        case .blockiert(_, let grund), .gesperrt(_, let grund), .gemischt(_, let grund):
            sicherung.wiederanlaufBlockieren(grund)
        }
        switch befund {
        case .nichts:
            break
        case .vollendet(let art):
            melden("\(art.satzanfang) war beim letzten Beenden nicht abgeschlossen und ist jetzt vollendet — "
                   + "die Ablage und ihre Nebendateien sind in einem Stand.")
        case .zurueckgenommen(let art, let grund, let rettung):
            melden("\(art?.satzanfang ?? "Ein Übergang des Schutzes") war beim letzten Beenden nicht abgeschlossen "
                   + "und ließ sich nicht vollenden (\(grund)) — was schon getauscht war, ist über die Vorgänger "
                   + "zurückgenommen: Es gilt der bisherige Stand. Marke und Zwillinge liegen als "
                   + "\(rettung.map { "„\($0)“" }.joined(separator: ", ")) neben der Planung. Bitte den Übergang "
                   + "erneut ausführen.", .warnung)
        case .beiseitegelegt(let art, let grund, let rettung):
            melden("\(art?.satzanfang ?? "Ein Übergang des Schutzes") war beim letzten Beenden nicht abgeschlossen "
                   + "und ließ sich nicht vollenden (\(grund)) — eingesetzt war nichts, es gilt der bisherige Stand; "
                   + "Marke und Zwillinge liegen als \(rettung.map { "„\($0)“" }.joined(separator: ", ")) neben der "
                   + "Planung. Bitte den Übergang erneut ausführen.", .warnung)
        case .blockiert(let art, let grund):
            melden("\(art?.satzanfang ?? "Ein Übergang des Schutzes") war beim letzten Beenden nicht abgeschlossen, "
                   + "und seine Marke lässt sich nicht mehr deuten (\(grund)). Welche Dateien zu ihm gehören, ist "
                   + "damit nicht zu sagen — es wird nichts geladen, nichts geschrieben und nichts angerührt; bitte "
                   + "den Ordner der Ablage sichern und die Dateien von Hand prüfen.", .warnung)
            return false
        case .gesperrt(let art, let grund):
            melden("\(art?.satzanfang ?? "Ein Übergang des Schutzes") war beim letzten Beenden nicht abgeschlossen "
                   + "und ließ sich nicht vollenden (\(grund)). Bis ein Start ihn vollendet, wird nichts geladen "
                   + "und nichts geschrieben — bitte den Ordner der Ablage prüfen und die App neu starten.", .warnung)
            return false
        case .gemischt(let art, let grund):
            melden("\(art?.satzanfang ?? "Ein Übergang des Schutzes") war beim letzten Beenden nicht abgeschlossen "
                   + "und ließ sich weder vollenden noch zurücknehmen (\(grund)). Die Ablage trägt zwei Stände; es "
                   + "wird nichts geladen und nichts geschrieben — bitte den Ordner der Ablage sichern und die "
                   + "Dateien von Hand prüfen; Marke, Zwillinge und Vorgänger liegen unverändert.", .warnung)
            sicherung.gesperrt = true
            return false
        }
        return true
    }

    /// Nicht überschreiben, was sich nur nicht lesen ließ — und, wenn es geht,
    /// die Fassung davor retten. Derselbe Rettungsweg wie beim unlesbaren
    /// JSON: Ohne ihn legte der Nutzer eine neue Planung an, und deren erstes
    /// Schreiben schöbe planung-vorher.json fort — die letzte gute Fassung
    /// wäre dahin.
    func unlesbarenStandBehandeln(_ fehler: any Error) {
        sicherung.gesperrt = true
        sicherung.startsperre = true
        if let vorige = sicherung.vorigeFassungLesen() {
            if Tresor.istBehaelter(vorige), tresor == nil {
                // Auch die Fassung davor ist verschlüsselt: erst entsperren, dann retten.
                entsperrungBeginnen(.vorige(vorige, fehler.localizedDescription))
                return
            }
            if let klartext = try? sicherung.ablage.entsiegelt(vorige, tresor: tresor),
               let (gerettet, bilanz) = try? Planungsdatei.lesenMitBilanz(klartext) {
                vorigeRettung(gerettet, bilanz: bilanz, grund: fehler.localizedDescription)
                return
            }
        }
        sicherung.lageMelden(.schreiben)
        melden("Die Autosicherung ließ sich nicht lesen (\(fehler.localizedDescription)). "
               + "Es wird nichts überschrieben, bis eine Planung angelegt oder geöffnet "
               + "wird — bitte die Datei prüfen.", .warnung)
        offenerDialog = .neuePlanung
    }

    /// Die gerettete Vorgängerfassung laden und wieder hinlegen.
    func vorigeRettung(_ gerettet: Planung, bilanz: Planungsdatei.Verlustbilanz,
                               grund: String) {
        planung = gerettet
        zurLaufendenWoche()
        // Die Platte trägt den geretteten Stand nicht — `jetztSichern()` legt
        // ihn hin, sobald der unlesbare Stand beiseiteliegt.
        sicherung.standUnbekannt()
        sicherung.startsperreAufheben()
        jetztSichern()
        let nachsatz = sicherung.gesperrt
            ? "Bis der unlesbare Stand beiseiteliegt, wird nichts geschrieben."
            : "Der unlesbare Stand liegt als Rettungskopie daneben."
        // Auch die gerettete Fassung kommt von außen, und das `jetztSichern()`
        // darüber hat sie gekürzt schon hingelegt.
        melden("Die Autosicherung ließ sich nicht lesen (\(grund)) — die Fassung davor "
               + "(\(Zeitrechnung.zeitpunktLang(gerettet.geaendert))) wurde geladen. "
               + nachsatz + Planungsspeicher.verlusttext(bilanz), .warnung)
    }

    /// Der Klartext der Ablage — gelesen wie bisher, samt Rettungsweg über die
    /// Vorgängerfassung, die ihrerseits ein Behälter sein kann.
    func geladenAusKlartext(_ daten: Data) {
        do {
            let (gelesen, bilanz) = try Planungsdatei.lesenMitBilanz(daten)
            planung = gelesen
            sicherung.standUebernommen(gelesen.geaendert)
            zurLaufendenWoche()
            // Ersetzte Kennungen wären bei jedem Lesen andere — ein Sitzplan oder eine Bindung an
            // sie ginge beim nächsten Start verloren (B102). Darum erst das Original bewahren, dann
            // einmal schreiben (E456 a) — nur, wenn geschrieben werden kann: Über der Schreibgrenze
            // entstünde sonst bei jedem Start eine Kopie (Z-AV7-02). Misslingt die Kopie oder trägt
            // sie nicht, was gelesen wurde (die Datei zwischen Start und Entsperren ersetzt,
            // Z-AV7-04), bleibt es beim Schreiben mit der nächsten Änderung.
            var kopie: String?
            if bilanz.ersetzteKennungen > 0, sicherung.stoerung == nil, !sicherung.gesperrt,
               let angelegt = sicherung.ablage.dateiKopieren(
                   sicherung.ablage.datei, als: "planung-bereinigt-\(Zeitrechnung.dateistempel()).json") {
                if sicherung.ablage.nebendateiTraegt(angelegt, daten, tresor: tresor) {
                    kopie = angelegt
                    // Das Schreiben rückt planung-vorher.json weiter — die Fassung davor bleibt
                    // gestempelt daneben (Z-AV7-03).
                    sicherung.vorigeFassungMitstempeln()
                    sicherung.standUnbekannt()
                } else {
                    sicherung.ablage.kopieVerwerfen(angelegt)
                }
            }
            // Was der eigene Stand beim Lesen verliert, schriebe die nächste
            // Autosicherung sonst kommentarlos gekürzt zurück.
            let verlust = Planungsspeicher.verlusttext(bilanz)
            if !verlust.isEmpty {
                melden("Beim Laden der Autosicherung" + verlust
                       + (kopie.map { " Das Original liegt als „\($0)“ neben der Planung." }
                          ?? " Die Fassung davor liegt als planung-vorher.json daneben."),
                       .warnung)
            }
            // Erst die Planung, dann der Stand vom iPad — er ändert sie.
            statusUebernehmen()
            if kopie != nil { jetztSichern() }
        } catch let fehler as Planungsfehler where fehler.art == .neuereFassung {
            // Eine neuere Fassung hat geschrieben: nichts anfassen, nichts
            // beiseitelegen — die Sitzung bleibt zu, bis die App nachgezogen ist.
            sicherung.gesperrt = true
            sitzung = .gesperrt(.ablage(daten), nil)
            zugriff.schliessen()
            sitzplaene.schliessen()
            lernende.schliessen()
            melden(fehler.text, .warnung)
        } catch {
            // Sonst überschriebe die nächste neue Planung den letzten Rest.
            sicherung.ablage.beschaedigtenStandBeiseitelegen(stempel: Zeitrechnung.dateistempel())
            beschaedigtenStandRetten(beschreibung: "unlesbar")
        }
    }

    /// Nach dem Beiseitelegen: die Fassung davor laden und wieder hinlegen —
    /// ohne brauchbare nach einer neuen Planung fragen. `beschreibung` sagt,
    /// was mit dem Stand war (unlesbar, größer als die Lesegrenze).
    private func beschaedigtenStandRetten(beschreibung: String) {
        if let vorige = sicherung.vorigeFassungLesen(),
           let klartext = try? sicherung.ablage.entsiegelt(vorige, tresor: tresor),
           let (gerettet, bilanz) = try? Planungsdatei.lesenMitBilanz(klartext) {
            planung = gerettet
            zurLaufendenWoche()
            // Jetzt, solange keine planung.json daneben liegt: Der übernächste
            // Schreibvorgang schöbe die ungekürzte Vorgängerfassung sonst fort.
            sicherung.vorigeFassungMitstempeln()
            // Die Platte trägt den geretteten Stand nicht — `jetztSichern()` legt
            // ihn als planung.json hin, sonst fände der nächste Start nichts.
            sicherung.standUnbekannt()
            jetztSichern()
            melden("Die letzte Autosicherung war \(beschreibung) — die Fassung davor "
                   + "(\(Zeitrechnung.zeitpunktLang(gerettet.geaendert))) wurde geladen "
                   + "und wieder gesichert. Der beiseitegelegte Stand liegt als "
                   + "Rettungskopie daneben." + Planungsspeicher.verlusttext(bilanz),
                   .warnung)
            return
        }
        melden("Die letzte Autosicherung war \(beschreibung) und wurde als Rettungskopie beiseitegelegt.",
               .warnung)
        offenerDialog = .neuePlanung
    }


    // ── Ändern und zurücknehmen (E82) ─────────────────────────────────────

    /// **Der Weg, auf dem die Planung geändert wird.** Er nimmt die
    /// Momentaufnahme, wendet die Änderung an, meldet sie beim Verlauf an und
    /// sichert — an einer Stelle, nicht an vierzig.
    ///
    /// `name` ist der Wortlaut fürs Menü („Vorhaben löschen“); `kennung` sagt
    /// der Schreibphase, worauf sich die Handlung bezieht (E88) — sie gehört zu
    /// Eingaben, die fortgesetzt werden (ein Name, den jemand tippt), nicht zu
    /// abgeschlossenen Handgriffen.
    ///
    /// Ändert die Handlung nichts, geschieht nichts: kein Schritt, kein
    /// Schreiben. Das ist keine Sparsamkeit, sondern die Bedingung dafür, dass
    /// ein Widerrufen immer etwas bewirkt.
    @discardableResult
    func aendern(_ name: String, kennung: String? = nil,
                 beiwerk: Ruecknahme<Planung>.Beiwerk? = nil,
                 _ handlung: (inout Planung) -> Void) -> Bool {
        guard var stand = planung else { return false }
        let vorher = stand
        handlung(&stand)
        guard stand != vorher else { return false }
        aufEigenemWeg { planung = stand }
        verlauf.anmelden(name, kennung: kennung, vorher: vorher, nachher: stand, beiwerk: beiwerk)
        sichern()
        return true
    }

    /// Was das Menü von einem Verlauf liest — gleich, welchen Stand er trägt.
    private struct Verlaufslage {
        let kannZurueck: Bool
        let kannVor: Bool
        let naechsterName: String?
        let wiederholungsName: String?

        @MainActor init<Stand>(_ verlauf: Ruecknahme<Stand>) {
            kannZurueck = verlauf.kannZurueck
            kannVor = verlauf.kannVor
            naechsterName = verlauf.naechsterName
            wiederholungsName = verlauf.wiederholungsName
        }
    }

    /// Welcher Verlauf gerade gilt — der eines Blatts mit eigenem Verlauf,
    /// solange es offen ist (Sitzplan, Lernende).
    private var geltenderVerlauf: Verlaufslage? {
        if sitzplanblattOffen { return Verlaufslage(sitzplanverlauf) }
        if lernendenblattOffen { return Verlaufslage(lernendenverlauf) }
        return nil
    }

    /// **Ein Blatt vor dem Schauplatz (E112, E118).** Das Vorhaben-Blatt
    /// puffert seinen Entwurf; ⌘Z änderte derweil die Planung dahinter, und
    /// „Übernehmen“ schrieb den Entwurf über den zurückgelegten Stand. Solange
    /// ein Blatt offen ist, **ruht** der Hauptverlauf darum — er wird nicht
    /// geleert, er wartet, bis das Blatt zu ist. Ausgenommen der
    /// Sitzplan-Editor: Er führt seinen eigenen Verlauf (E82), und solange das
    /// Blatt ihn führt, gilt der. Das Blatt „Lernende“ führt ebenfalls seinen
    /// eigenen; es zählt hier als Blatt, `geltenderVerlauf` geht vor. Dieselbe
    /// Regel, nach der `dialogOffen` die Kurzbefehle sperrt; ein Textfeld mit
    /// Schreibmarke behält seine Rücknahme (E87, entschieden in `Befehle`).
    var blattVorDemSchauplatz: Bool {
        vorhabenDialog != nil || (offenerDialog != nil && offenerDialog != .sitzplan)
    }

    /// Ein Schritt, der nur Beiwerk trägt — die Planung bleibt, wie sie ist (S6).
    func nurBeiwerkAnmelden(_ name: String, beiwerk: Ruecknahme<Planung>.Beiwerk) {
        guard let stand = planung else { return }
        verlauf.anmelden(name, stand: stand, beiwerk: beiwerk)
    }

    var kannWiderrufen: Bool { geltenderVerlauf?.kannZurueck ?? (!blattVorDemSchauplatz && verlauf.kannZurueck) }
    var kannWiederholen: Bool { geltenderVerlauf?.kannVor ?? (!blattVorDemSchauplatz && verlauf.kannVor) }

    /// Ein Bogen auf dem Blatt „Lernende“: ⌘Z und ⇧⌘Z tönen nur (G2-07, E776) — das Menü nennt dann keinen Schritt,
    /// nach derselben Regel wie ein Blatt vor dem Schauplatz (E841).
    var bogenAufDemBlatt: Bool { lernendenblattOffen && lernendenblattGriff?.bogenOffen() == true }

    /// „Widerrufen: Vorhaben löschen“ — der Name des Schrittes steht im Menü.
    var widerrufenTitel: String {
        let name = bogenAufDemBlatt ? nil
            : geltenderVerlauf?.naechsterName ?? (blattVorDemSchauplatz ? nil : verlauf.naechsterName)
        return name.map { "Widerrufen: \($0)" } ?? "Widerrufen"
    }

    var wiederholenTitel: String {
        let name = bogenAufDemBlatt ? nil
            : geltenderVerlauf?.wiederholungsName ?? (blattVorDemSchauplatz ? nil : verlauf.wiederholungsName)
        return name.map { "Wiederholen: \($0)" } ?? "Wiederholen"
    }

    func widerrufen() {
        guard !frageSperrtBefehl() else { return }
        offeneEingabenVerwerfen()
        if sitzplanblattOffen {
            guard let schritt = sitzplanverlauf.zuruecknehmen() else { return }
            sitzplanEntwurfSetzen?(schritt.vorher)
            return
        }
        if lernendenblattOffen {
            // Ein Bogen auf dem Blatt zeigt eine Kopie des Entwurfs — ⌘Z darunter liefe ihm davon (G2-07, E776, am Lauf
            // gemessen: ohne Schreibmarke im Bogen erreicht ⌘Z das Blatt). Abgewiesen, mit Ton; der Verlauf bleibt.
            guard lernendenblattGriff?.bogenOffen() != true else { systemton(); return }
            guard let naechster = lernendenverlauf.zurueck.last else { return }
            if namenVorDemSchritt(naechster.vorher, dann: { [weak self] in self?.widerrufen() }) { return }
            guard let schritt = lernendenverlauf.zuruecknehmen() else { return }
            lernendenEntwurfSetzen?(schritt.vorher)
            return
        }
        guard !blattVorDemSchauplatz else { return }
        guard let naechster = verlauf.zurueck.last, beiwerkGeht(naechster, .zurueck) else { return }
        guard let schritt = verlauf.zuruecknehmen() else { return }
        // Erst die Planung, dann das Beiwerk: Ein Sitzplan gehört zu einer
        // Klasse, die es wieder geben muss.
        zurueckAuf(schritt.vorher)
        schritt.beiwerk?.zurueck()
    }

    func wiederholen() {
        guard !frageSperrtBefehl() else { return }
        offeneEingabenVerwerfen()
        if sitzplanblattOffen {
            guard let schritt = sitzplanverlauf.wiederholen() else { return }
            sitzplanEntwurfSetzen?(schritt.nachher)
            return
        }
        if lernendenblattOffen {
            guard lernendenblattGriff?.bogenOffen() != true else { systemton(); return }  // wie ⌘Z (G2-07, E776)
            guard let naechster = lernendenverlauf.vor.last else { return }
            if namenVorDemSchritt(naechster.nachher, dann: { [weak self] in self?.wiederholen() }) { return }
            guard let schritt = lernendenverlauf.wiederholen() else { return }
            lernendenEntwurfSetzen?(schritt.nachher)
            return
        }
        guard !blattVorDemSchauplatz else { return }
        guard let naechster = verlauf.vor.last, beiwerkGeht(naechster, .vor) else { return }
        guard let schritt = verlauf.wiederholen() else { return }
        zurueckAuf(schritt.nachher)
        schritt.beiwerk?.vor()
    }

    /// Nähme ein Schritt im Blatt die gewählte Gruppe, ginge eine getippte, nicht
    /// eingetragene Namensliste mit — erst die Frage (E303, offener Punkt 1).
    /// `true`, wenn sie steht; auf „Verwerfen“ folgt der Schritt verzögert.
    private func namenVorDemSchritt(_ ziel: Lernendenbestand, dann: @escaping @MainActor () -> Void) -> Bool {
        guard let griff = lernendenblattGriff, griff.namenOffen(), !griff.gruppeBleibt(ziel) else { return false }
        fragen("Die eingegebenen Namen verwerfen?", bestaetigung: "Verwerfen", gefahr: true, ort: .lernende,
               ablehnung: "Weiter bearbeiten", nachDemSchliessen: true) { [weak self] in
            griff.namenVerwerfen()
            // Steht inzwischen eine andere Frage, gilt sie — nichts überschreibt sie (Z14b-11). Ist das Blatt
            // bis dahin zu, entfällt der Schritt: Er gehörte zu seinem Verlauf, nicht zu dem der Planung (Z-AU4a-01).
            self?.nachDerAntwort { [weak self] in
                guard self?.lernendenblattOffen == true else { return }
                dann()
            }
        }
        return true
    }

    /// Eine Planung in die Sitzung, ohne den Schauplatz zu wechseln — für einen
    /// Übergang, der noch scheitern kann; scheitert er, bleibt der Verlauf (W2-09).
    func planungVorlaeufigSetzen(_ neu: Planung?) {
        aufEigenemWeg { planung = neu }
    }

    /// Der Schauplatz ist gewechselt: Der Verlauf davor gehört zu etwas anderem (E82, E236).
    func schauplatzGewechselt() {
        verlauf.leeren()
        sitzungsmarke &+= 1
    }

    /// Ein Schritt, dessen Beiwerk gerade nicht mitkommt, wird nicht genommen —
    /// er bleibt stehen, und der Grund wird gesagt. Sonst käme die Klasse
    /// zurück und ihr Sitzplan nicht.
    private func beiwerkGeht(_ schritt: Ruecknahme<Planung>.Schritt,
                             _ richtung: Ruecknahme<Planung>.Beiwerk.Richtung) -> Bool {
        guard let grund = schritt.beiwerk?.moeglich(richtung) else { return true }
        melden("„\(schritt.name)“ lässt sich gerade nicht zurücknehmen: \(grund.satzanfang)", .warnung)
        return false
    }

    /// Was in einem Feld steht und noch nicht geschrieben ist, gehört zu dem
    /// Stand **vor** der Rücknahme. Ließe man es landen, schriebe es die
    /// Rücknahme zurück — und räumte dabei den Weg nach vorn, weil jede neue
    /// Anmeldung ihn leert. Am gebauten Paket gemessen: ⇧⌘Z stellte nichts mehr
    /// her, weil der Titel aus der Fensterleiste 400 ms später nachkam (S7-R3).
    private func offeneEingabenVerwerfen() {
        Entpreller.allesAbbrechen()
        titelentwurf = nil
    }

    /// Eine Rücknahme ist eine gewöhnliche Änderung — sie geht durch `sichern()`
    /// und damit durch Formwächter und Übergangssperre. Ruht das Schreiben,
    /// sagt das die vorhandene Störung — einen Sonderweg gibt es dafür nicht.
    ///
    /// Zurückgelegt wird der Inhalt, nicht die Autorität (N58-01, E109, E120):
    /// Was die Rücknahme an Haken oder Kommentar ändert, trägt danach einen
    /// frischen Statusstempel, und was gleich bleibt, behält den jüngeren, den
    /// es hat — sonst gewänne ein liegengebliebener iPad-Stand gegen das
    /// Widerrufen, auch noch nach einem zweiten (`Statusabgleich.nachRuecknahme`).
    private func zurueckAuf(_ stand: Planung) {
        var neu = stand
        if let bisher = planung {
            Statusabgleich.nachRuecknahme(&neu, gegen: bisher, jetzt: Zeitrechnung.jetztAlsZeitstempel())
        }
        aufEigenemWeg { planung = neu }
        sichern()
    }

    // ── Sichern ───────────────────────────────────────────────────────────
    // Geschrieben wird im Sicherungsdienst; hier bekommt die Planung ihren Stempel.

    /// Nach jeder Änderung aufzurufen; schreibt entprellt — sofort nur, wenn ein
    /// Termin mit seinem Vorhaben ging, zurückkam oder neu entstand (`terminfolgeSofort`).
    func sichern() {
        guard planung != nil else { return }
        // Der Stempel ist Buchführung, kein Wechsel des Schauplatzes: Er darf
        // den Verlauf nicht leeren — sonst löschte sich jede Änderung ihren
        // eigenen Schritt (am Lauf gesehen).
        aufEigenemWeg { planung?.geaendert = Zeitrechnung.jetztAlsZeitstempel() }
        sicherung.sichern()
        // Erst nach Stempel und Anmeldung: Ohne die Anmeldung beim Zähler hielte
        // der Dienst die Planung bei gleichem Stempel für gesichert und schriebe
        // nichts (E900, Z-AY9a-01). Die Jahresdatei steht schon auf der Platte —
        // die Planung sofort dazu (H1-01, E896 a); der eben gestellte Auftrag fällt weg.
        if terminfolgeSofort {
            terminfolgeSofort = false
            jetztSichern()
        }
    }

    /// Ohne Entprellung — beim Wegschalten, beim Beenden, wenn die Herkunft der
    /// Planung noch nicht auf der Platte steht (A4), nach „Übernehmen“ im
    /// Blatt „Lernende“ (B109) und wenn ein Termin mit seinem Vorhaben geht,
    /// zurückkommt oder neu entsteht (`sichern()`, H1-01), durchgängig gleichlaufend.
    func jetztSichern() {
        sicherung.jetztSichern()
        // Auch ein Sitzplan, den die Platte noch nicht trägt (B10) — und die Lernendendaten.
        sitzplaene.nachholen()
        lernende.nachholen()
    }
}
