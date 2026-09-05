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
    case hauptansicht, klassen, einstellungen, vorhaben, verschluesselung
}

struct Rueckfrage: Identifiable {
    let id = UUID()
    let text: String
    let bestaetigung: String
    var gefahr: Bool = false
    var ort: Rueckfrageort = .hauptansicht
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
    var id: String { rawValue }
}

/// Reihenfolgewächter der Autosicherung.
///
/// Der entprellte Auftrag wandelt abseits des Hauptstrangs um und schreibt
/// deshalb später, als er seinen Stand gelesen hat; `jetztSichern()` schreibt
/// gleichlaufend dazwischen. Jeder Schreibvorgang zieht vorher — auf dem
/// Hauptakteur, also in der Reihenfolge der Änderungen — eine fortlaufende
/// Nummer und gibt sie hier ab: Ein überholter Auftrag legt seinen älteren
/// Stand nicht mehr über den jüngeren, und ein Stand, der bereits auf der
/// Platte liegt, wird nicht ein zweites Mal geschrieben — sonst wäre
/// `planung-vorher.json` nur noch eine Kopie von `planung.json`.
///
/// Wie `Ablage` bewusst eine Sperre und kein Akteur: Ein `await` beim Beenden
/// ließe die App hängen.
private final class Sicherungsfolge: @unchecked Sendable {
    static let shared = Sicherungsfolge()

    enum Ergebnis { case geschrieben, unveraendert, ueberholt }

    private let sperre = NSLock()
    private var vergeben = 0
    private var letzteNummer = 0
    private var letzterStand: String?

    func naechsteNummer() -> Int {
        sperre.withLock {
            vergeben += 1
            return vergeben
        }
    }

    /// Der nächste Schreibvorgang geht auch bei unverändertem Stand auf die
    /// Platte — wenn sich nicht die Planung, sondern ihre Hülle geändert hat
    /// (Tresor gesetzt, Wicklung getauscht, Schlüssel erneuert).
    func neuSchreibenErzwingen() {
        sperre.withLock { letzterStand = nil }
    }

    func schreiben(nummer: Int, stand: String, daten: Data) throws -> Ergebnis {
        try sperre.withLock {
            guard nummer > letzteNummer else { return .ueberholt }
            letzteNummer = nummer
            guard stand != letzterStand else { return .unveraendert }
            try Ablage.shared.schreiben(daten)
            letzterStand = stand
            return .geschrieben
        }
    }
}

/// Der Zustand der Anwendung und alles, was ihn ändert.
@MainActor
@Observable
final class Planungsspeicher {

    // ── Zustand ───────────────────────────────────────────────────────────

    /// Beim Zuweisen wird die Auswahl nachgeführt — an einer Stelle statt an
    /// dreißig: Auswahl, Zwischenablage und Zielzelle zeigen auf Kennungen, die
    /// es danach nicht mehr geben muss.
    private(set) var planung: Planung? {
        didSet {
            Planungsspeicher.standzaehler &+= 1
            planungsstand = Planungsspeicher.standzaehler
            // Ableitungen, damit die Hauptansicht nicht `planung` liest: Sie würde
            // samt Liquid-Glass-Werkzeugleiste je Handgriff rund 20 ms neu ausgewertet.
            let neuHat = planung != nil
            if neuHat != hatPlanung { hatPlanung = neuHat }
            let neuKennzahlen = planung?.kennzahlen ?? "Noch keine Planung angelegt"
            if neuKennzahlen != kennzahlen { kennzahlen = neuKennzahlen }
            auswahlNachfuehren()
        }
    }

    private(set) var hatPlanung = false
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

    private(set) var auswahl: Set<String> = []
    /// Die angewählte Zelle, sofern kein Vorhaben angewählt ist — das Ziel
    /// fürs Einfügen.
    private(set) var zielzelle: Zellenort?
    /// Von wo aus ⇧ eine Spanne aufzieht.
    private var auswahlanker: String?
    private(set) var ablage: Ablageinhalt?

    var offenerDialog: Dialogfenster?
    var vorhabenDialog: VorhabenEntwurf?
    var farbwahlFuer: Farbwahlziel?
    var rueckfrage: Rueckfrage?
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

    func alleDialogeSchliessen() {
        offenerDialog = nil
        naechsterDialog = nil
        vorhabenDialog = nil
        farbwahlFuer = nil
        rueckfrage = nil
    }

    /// Ein Fenster trägt nur ein Blatt: Ist eines offen, wird es geschlossen
    /// und das nächste vorgemerkt — die Hauptansicht öffnet es, sobald das
    /// alte abgelöst ist (`naechstenDialogOeffnen`).
    private(set) var naechsterDialog: Dialogfenster?

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
        offenerDialog = naechster
    }

    /// Steht, sobald die Rückfrage nach ungesicherten Änderungen beantwortet
    /// ist — sonst stellte `beendenErlauben()` sie ein zweites Mal.
    private var beendenFreigegeben = false

    /// Das Fenster, in dem eine Rückfrage stehen kann — auch ein geschlossenes:
    /// SwiftUI hält das Fenster der Szene und ordnet es beim Schließen nur aus.
    ///
    /// `canBecomeMain` scheidet als Merkmal aus; AppKit meldet dort für ein
    /// unsichtbares Fenster `false`.
    private func rueckfragefenster() -> NSWindow? {
        let taugliche = NSApp.windows.filter {
            $0.styleMask.contains(.titled) && !($0 is NSPanel) && $0.parent == nil
        }
        return taugliche.first(where: \.isVisible) ?? taugliche.first
    }

    /// Die Rückfrage, die ein stilles Verlieren verhindert. `nil` heißt: Es
    /// gibt nichts zu fragen, es darf gegangen werden.
    ///
    /// **Ohne Fenster wird nicht gefragt, sondern gegangen:** Die Rückfrage
    /// hängt als Blatt an der Ansicht; fehlte das Fenster, hingen ⌘Q, das Dock
    /// und das Abmelden ohne jede Rückmeldung fest.
    private func verlustfrage() -> (@MainActor () -> Void)? {
        guard !beendenFreigegeben, sicherungLiegtStill, planung != nil else { return nil }
        guard let fenster = rueckfragefenster() else { return nil }
        return { [self] in
            // Nach dem Schließen des letzten Fensters läuft die App weiter
            // (`beendenBeiLetztemFenster`); die Frage braucht es sichtbar.
            if !fenster.isVisible {
                NSApp.activate()
                fenster.makeKeyAndOrderFront(nil)
            }
            fragen("Die Planung ließ sich nicht sichern. Beim Beenden gehen die Änderungen "
                   + "seit der letzten gelungenen Sicherung verloren.\n\n"
                   + "Vorher über „Als JSON sichern …“ (⌘S) exportieren?",
                   bestaetigung: "Trotzdem beenden", gefahr: true) { [self] in
                beendenFreigegeben = true
                NSApp.terminate(nil)
            }
        }
    }

    /// Antwort auf das Beenden-Ereignis von AppKit — und die letzte Stelle vor
    /// dem Gehen: Hier wird ein letztes Mal gesichert, und was dabei nicht
    /// gelingt, kommt hier noch zur Sprache. Eine über `beenden()` bereits
    /// beantwortete Rückfrage wird nicht wiederholt.
    func beendenErlauben() -> Bool {
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
    var beendenBeiLetztemFenster: Bool { !sicherungLiegtStill || planung == nil }

    /// Ein offenes Blatt hält das Beenden auf — AppKit weist den Befehl ab,
    /// bevor der Delegat davon erfährt. Erst schließen, dann sichern, dann gehen.
    ///
    /// **Freigegeben wird hier nichts:** Das Blatt schreibt beim Verschwinden
    /// noch (`onDisappear`), also hat `beendenErlauben()` das letzte Wort — dort
    /// wird ein letztes Mal gesichert, und erst dort zeigt sich, ob dabei etwas
    /// verlorenginge.
    /// Ob der letzte `beenden()`-Aufruf die App wirklich auf den Weg gebracht
    /// hat — `false`, solange eine Rückfrage aussteht. Der AppleEvent-Griff
    /// meldet danach Erfolg oder Ablehnung.
    private(set) var beendetGleich = false

    func beenden() {
        beendetGleich = false
        let warEinBlattOffen = dialogOffen
        alleDialogeSchliessen()
        jetztSichern()

        if let fragen = verlustfrage() {
            fragen()
            return
        }
        beendetGleich = true

        guard warEinBlattOffen else {
            NSApp.terminate(nil)
            // Zurück heißt abgelehnt: `applicationShouldTerminate` kennt nur
            // `.terminateNow` und `.terminateCancel`, und abgelehnt wird nur
            // mit stehender Rückfrage. Der AppleEvent-Griff darf dann kein
            // Gelingen melden.
            beendetGleich = false
            return
        }
        Task { @MainActor in
            await Planungsspeicher.blaetterAbloesenAbwarten()
            NSApp.terminate(nil)
        }
    }

    /// Wartet, bis kein Blatt mehr angeheftet und kein modales Fenster mehr
    /// offen ist — höchstens rund 1,2 s. AppKit weist `terminate` bei
    /// angeheftetem Blatt ab, noch bevor der Delegat gefragt wird; wer ein
    /// Blatt schließt und gleich gehen will, wartet hier. Die eine Stelle
    /// dafür — trüge `beenden()` die Schleife allein, schlössen die
    /// Prüfstände ihre Blätter und gingen ungebremst: `--abbild` bliebe
    /// stehen.
    static func blaetterAbloesenAbwarten() async {
        for _ in 0..<30 {
            let offen = NSApp.windows.contains { $0.attachedSheet != nil }
            if !offen, NSApp.modalWindow == nil { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private(set) var meldungen: [Meldung] = []
    private(set) var sicherungGestoert = false
    private(set) var letzteSicherung: Date?

    /// Das Einrasten steht an dieser einen Stelle, damit Regler, Tastenkürzel
    /// und der wiederhergestellte Wert dieselben Stufen liefern.
    var spaltenbreite: Double {
        didSet {
            let neu = Kennwerte.spalteRasten(spaltenbreite)
            if neu != spaltenbreite { spaltenbreite = neu; return }
            Einstellungen.setzen(neu, Schluessel.spaltenbreite)
        }
    }

    var erscheinung: Erscheinung {
        didSet { Einstellungen.setzen(erscheinung.rawValue, Schluessel.erscheinung) }
    }

    // ── Sicherungskopie beim Beenden ──────────────────────────────────────

    var autoexportAktiv: Bool {
        didSet { Einstellungen.setzen(autoexportAktiv, Schluessel.autoexportAktiv) }
    }

    /// Leer heißt: noch keiner gewählt.
    var autoexportOrdner: String {
        didSet { Einstellungen.setzen(autoexportOrdner, Schluessel.autoexportOrdner) }
    }

    private(set) var letzterAutoexport: Date?

    /// Derselbe Zielordner ein zweites Mal, als Lesezeichen: Der Pfad allein
    /// ist eine Momentaufnahme und zeigt nach dem Umbenennen ins Leere.
    ///
    /// Bewusst OHNE `.withSecurityScope` — das gehört zur Sandbox, in der diese
    /// App nicht läuft.
    private var autoexportLesezeichen: Data?

    /// Sichtbar in den Einstellungen, damit klar ist, welche Datei die Ansicht
    /// öffnen soll.
    var autoexportDateiname: String {
        Planungsdatei.festerName(titel: planung?.titel ?? "Unterrichtsplanung")
    }

    /// Den Zielordner wählen — und sofort hinschreiben, damit ein Fehlschlag
    /// hier auffällt und nicht erst beim Beenden.
    @discardableResult
    func autoexportOrdnerWaehlen() -> Bool {
        guard let gewaehlt = Systemzugriff.ordnerWaehlen(
            start: autoexportOrdner, mehrere: false,
            titel: "Ordner für die Sicherungskopie wählen").first
        else { return false }
        // Die Kopie gibt es nur verschlüsselt: Ohne Tresor erst die Einrichtung,
        // dann Schalter und Probeschreibung.
        guard tresor != nil else {
            autoexportOrdner = gewaehlt
            autoexportAktiv = false
            lesezeichenAblegen(URL(fileURLWithPath: gewaehlt, isDirectory: true))
            verschluesselungEinrichten { [weak self] in
                guard let self else { return }
                autoexportAktiv = true
                autoexportAusfuehren(vomNutzer: true)
            }
            return true
        }
        autoexportZielSetzen(gewaehlt)
        return autoexportAusfuehren(vomNutzer: true)
    }

    /// Der Schalter in den Einstellungen. Einschalten ohne Tresor richtet erst
    /// die Verschlüsselung ein und schaltet dann; ohne Zielordner wird der
    /// zuerst gewählt.
    func autoexportUmschalten(_ an: Bool) {
        guard an else { autoexportAktiv = false; return }
        guard !autoexportOrdner.isEmpty else { autoexportOrdnerWaehlen(); return }
        guard tresor != nil else {
            verschluesselungEinrichten { [weak self] in
                guard let self else { return }
                autoexportAktiv = true
                autoexportAusfuehren(vomNutzer: true)
            }
            return
        }
        autoexportAktiv = true
    }

    /// Pfad, Schalter und Lesezeichen zusammen — sie dürfen nie auseinanderlaufen.
    func autoexportZielSetzen(_ pfad: String) {
        autoexportOrdner = pfad
        autoexportAktiv = true
        lesezeichenAblegen(URL(fileURLWithPath: pfad, isDirectory: true))
    }

    /// Den Zielordner suchen: erst dort, wo er stand, dann über das Lesezeichen.
    private func zielordnerFinden() -> URL? {
        let gemerkt = URL(fileURLWithPath: autoexportOrdner, isDirectory: true)
        if istOrdner(gemerkt) { return gemerkt }

        guard let daten = autoexportLesezeichen else { return nil }
        var veraltet = false
        // `.withoutUI`/`.withoutMounting`: hielte sonst das Beenden auf.
        guard let gefunden = try? URL(resolvingBookmarkData: daten,
                                      options: [.withoutUI, .withoutMounting],
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &veraltet),
              istOrdner(gefunden)
        else { return nil }

        autoexportOrdner = gefunden.path
        if veraltet { lesezeichenAblegen(gefunden) }
        return gefunden
    }

    private func istOrdner(_ ziel: URL) -> Bool {
        var ordner: ObjCBool = false
        return FileManager.default.fileExists(atPath: ziel.path, isDirectory: &ordner)
            && ordner.boolValue
    }

    /// Nachrüsten für eine Einstellung, die nur den Pfad kennt: Wer den
    /// Zielordner einmal ohne Lesezeichen gewählt hat, bekommt es hier.
    func lesezeichenNachruesten() {
        guard autoexportLesezeichen == nil, !autoexportOrdner.isEmpty else { return }
        let ordner = URL(fileURLWithPath: autoexportOrdner, isDirectory: true)
        guard istOrdner(ordner) else { return }
        lesezeichenAblegen(ordner)
    }

    private func lesezeichenAblegen(_ ordner: URL) {
        guard let daten = try? ordner.bookmarkData() else {
            autoexportLesezeichen = nil
            Einstellungen.entfernen(Schluessel.autoexportLesezeichen)
            return
        }
        autoexportLesezeichen = daten
        Einstellungen.setzen(daten, Schluessel.autoexportLesezeichen)
    }

    /// Läuft beim Beenden: Nichts darf auf einen Ablaufwechsel warten, und ein
    /// Fehlschlag wird für den nächsten Start vorgemerkt.
    @discardableResult
    func autoexportAusfuehren(vomNutzer: Bool = false) -> Bool {
        guard let planung, autoexportAktiv || vomNutzer, !autoexportOrdner.isEmpty
        else { return false }

        guard let ordner = zielordnerFinden() else {
            autoexportFehlerVormerken(
                "Der Zielordner der Sicherungskopie ist nicht mehr da: \(autoexportOrdner). "
                + "Er wurde gelöscht, oder er liegt auf einem Datenträger, der gerade fehlt. "
                + "Bitte unter „Einstellungen“ einen neuen wählen.", zeigen: vomNutzer)
            return false
        }
        let ziel = ordner.appending(component: autoexportDateiname, directoryHint: .notDirectory)

        // Nur verschlüsselt. Gesperrt heißt gesperrt; ohne Verschlüsselung sagt
        // der Weg, warum nichts kommt.
        guard let tresor else {
            if verschluesselungsstand == .gesperrt { return false }
            autoexportFehlerVormerken(
                "Die Sicherungskopie beim Beenden wird nur verschlüsselt "
                + "geschrieben. Bitte unter „Einstellungen“ die Verschlüsselung einschalten — "
                + "bis dahin wird keine Kopie geschrieben.", zeigen: vomNutzer)
            return false
        }

        do {
            try tresor.versiegeln(try Planungsdatei.schreiben(planung), inhalt: .planung, ziel: .kopie)
                .write(to: ziel, options: [.atomic])
            Einstellungen.entfernen(Schluessel.autoexportFehler)
            letzterAutoexport = Date()
            Einstellungen.setzen(letzterAutoexport?.timeIntervalSinceReferenceDate ?? 0,
                                 Schluessel.autoexportStand)
            if vomNutzer { melden("Sicherungskopie geschrieben: \(ziel.path)") }
            return true
        } catch {
            autoexportFehlerVormerken(
                "Die Sicherungskopie ließ sich nicht in \(ordner.path) schreiben: "
                + "\(error.localizedDescription)", zeigen: vomNutzer)
            return false
        }
    }

    /// Sofort zeigen, wo jemand davorsitzt — sonst für den nächsten Start
    /// vormerken.
    private func autoexportFehlerVormerken(_ text: String, zeigen: Bool) {
        if zeigen {
            melden(text, .warnung)
        } else {
            Einstellungen.setzen("Beim letzten Beenden: " + text, Schluessel.autoexportFehler)
        }
    }

    // ── Verschlüsselung ───────────────────────────────────────────────────
    // Ein Datenschlüssel, offene Wicklungsliste, kein Klartext an keiner Stelle.

    /// Der Hinweis zur Datenverwaltung — wortgleich im Ersteinrichtungsdialog
    /// und im Beipackzettel des DMG (bauen.sh).
    static let datenschutzhinweis =
        "Hinweis zur Datenverwaltung: Die Sicherungskopie beim Beenden wird nur "
        + "verschlüsselt geschrieben (AES-256) — mit der Wahl eines Zielordners wird die "
        + "Verschlüsselung eingerichtet, mit Passphrase und Wiederherstellungsschlüssel. Die "
        + "laufende Sicherung auf diesem Rechner ist unverschlüsselt, solange die "
        + "Verschlüsselung unter „Einstellungen“ nicht eingeschaltet ist; FileVault schützt "
        + "sie unabhängig davon. Ältere Kopien, Schnappschüsse und Sicherungen des Systems "
        + "bleiben von einem späteren Einschalten unberührt."

    enum Verschluesselungsstand: Sendable { case aus, gesperrt, an }

    private(set) var verschluesselungsstand: Verschluesselungsstand = .aus
    var verschluesselt: Bool { verschluesselungsstand != .aus }

    /// Der Datenschlüssel der Sitzung — der der Ablage. Eine Vorschau (Prüfungen)
    /// führt einen eigenen, damit sich nicht alle Prüfläufe den einen globalen
    /// teilen und sich gegenseitig die Ablage versiegeln.
    private var vorschauTresor: Tresor?
    var tresor: Tresor? { istVorschau ? vorschauTresor : Ablage.shared.tresor }

    private func tresorAnlegen(_ neu: Tresor?) {
        if istVorschau { vorschauTresor = neu } else { Ablage.shared.tresor = neu }
        enklaveEingerichtet = neu?.hat(Wicklung.enklave) ?? false
    }

    /// Ablage beim Start, Vorgängerfassung nach unlesbarem Stand, oder eine
    /// von außen geöffnete Datei unter fremdem Schlüssel.
    enum Entsperrungsziel: Sendable {
        case ablage(Data)
        case vorige(Data, String)
        case datei(Data, URL)
        var daten: Data {
            switch self {
            case .ablage(let d), .vorige(let d, _), .datei(let d, _): d
            }
        }
        var istAblage: Bool { if case .datei = self { false } else { true } }
    }

    private var entsperrung: Entsperrungsziel?
    private(set) var gesperrterKopf: Behaelterkopf?
    private(set) var entsperrungOffen = false
    /// Der Touch-ID-Dialog steht gerade.
    private(set) var entsperrungLaeuft = false
    private(set) var entsperrungFehler: String?
    /// Welches Feld das Blatt zeigt — wie in der Ansicht immer nur eines, damit
    /// die Eingabe eindeutig ist. Im Speicher statt im Blatt, damit der Prüfstand
    /// `--entsperrtest` umschalten kann.
    enum Entsperrungsweg: Hashable, Sendable { case passphrase, wiederherstellung }
    private(set) var entsperrungsweg: Entsperrungsweg = .passphrase
    /// Das Häkchen „Mit Touch ID öffnen“ im Blatt — wie bei Numbers: Nach der
    /// nächsten Freigabe per Passphrase oder Wiederherstellungsschlüssel bekommt
    /// dieser Mac seine Enklaven-Wicklung, notfalls neu; ohne Häkchen verliert
    /// er sie. Im Speicher, damit der Prüfstand es schalten kann.
    var enklaveMerken = false
    /// Die Wicklung dieses Macs ließ sich nicht öffnen — ein neuer oder neu
    /// aufgesetzter Mac; das Blatt sagt es dazu.
    private(set) var enklaveWicklungPasstNicht = false
    /// Trägt der offene Tresor eine Wicklung für diesen Mac? Für den Schalter
    /// unter „Einstellungen“ — beobachtbar, was der Tresor selbst nicht ist.
    private(set) var enklaveEingerichtet = false
    /// Nur für Prüfungen: den Enklaven-Schlüssel auch im Prüfstand anlegen.
    /// Das Anlegen fragt nicht nach; erst das Öffnen verlangt die Freigabe.
    var enklaveImPruefstandAnlegen = false
    /// Ob es um die Ablage geht (Touch ID, Leerzustand) oder um eine Datei.
    var entsperrungFuerAblage: Bool { entsperrung?.istAblage ?? true }
    /// Wird erst nach dem bestätigten Wiederherstellungsblatt zum Tresor der Ablage.
    private var vorbereitung: Tresor?
    private var nachEinrichtung: (@MainActor () -> Void)?

    /// Die Wicklungen der Ablage — auch im gesperrten Zustand, aus dem Kopf.
    var wicklungen: [Wicklung] {
        tresor?.wicklungen ?? gesperrterKopf?.wicklungen ?? []
    }

    /// Touch ID ist möglich, wenn der Kopf eine Wicklung für diesen Mac trägt.
    var enklaveMoeglich: Bool {
        Tresor.enklaveVerfuegbar && gesperrterKopf?.wicklung(Wicklung.enklave) != nil
            && entsperrungFuerAblage
    }

    /// Öffnet die Einrichtung; `danach` läuft, sobald eingeschaltet ist —
    /// etwa das Einschalten der Kopie beim Beenden.
    func verschluesselungEinrichten(danach: (@MainActor () -> Void)? = nil) {
        nachEinrichtung = danach
        dialogOeffnen(.verschluesselung)
    }

    /// Schritt 1: Datenschlüssel und Wicklungen; liefert den Wiederherstellungs-
    /// schlüssel, der einmal gezeigt und nie gespeichert wird. Eingeschaltet ist
    /// damit noch nichts.
    func verschluesselungVorbereiten(passphrase: String) throws -> String {
        let tresor = Tresor.neu()
        try tresor.passphraseSetzen(passphrase)
        let blatt = try tresor.wiederherstellungAnlegen()
        if Tresor.enklaveVerfuegbar { try tresor.enklaveAnlegen() }
        vorbereitung = tresor
        return blatt
    }

    /// Schritt 2, nach dem bestätigten Blatt: Ablage und Nebendateien sofort,
    /// die Kopie beim nächsten Beenden.
    func verschluesselungEinschalten() {
        guard let tresor = vorbereitung else { return }
        vorbereitung = nil
        let alter = self.tresor
        tresorAnlegen(tresor)
        verschluesselungsstand = .an
        neuVersiegeln()
        let alt = Ablage.shared.altbestaendeVersiegeln(alter: alter)
        melden((alter == nil ? "Verschlüsselung eingeschaltet." : "Schlüssel erneuert.")
               + " Die Ablage auf diesem Mac ist versiegelt"
               + (alt > 0 ? ", \(alt) ältere \(alt == 1 ? "Stand" : "Stände") daneben ebenfalls" : "")
               // In der Ersteinrichtung gibt es die Kopie noch nicht — dann kein Versprechen.
               + (autoexportAktiv ? ". Die Kopie beim Beenden folgt beim nächsten Beenden." : "."))
        let fortsetzung = nachEinrichtung
        nachEinrichtung = nil
        fortsetzung?()
    }

    func verschluesselungVerwerfen() {
        vorbereitung = nil
        nachEinrichtung = nil
    }

    /// Alles neu versiegeln, was die App erreicht: die Ablage jetzt — auch ohne
    /// Änderung an der Planung —, die Kopie beim nächsten Beenden.
    private func neuVersiegeln() {
        gesicherterStand = nil
        Sicherungsfolge.shared.neuSchreibenErzwingen()
        jetztSichern()
    }

    /// Der Rückweg — eine Einbahnstraße wäre bei einer Jahresplanung nicht zu
    /// verantworten. Die Kopie außer Haus gibt es danach nicht mehr.
    func verschluesselungAufheben() {
        guard let tresor else { return }
        tresorAnlegen(nil)
        verschluesselungsstand = .aus
        // Erst die Ablage im Klartext hinlegen — dabei wandert der versiegelte
        // Stand nach planung-vorher.json —, dann die Nebendateien entsiegeln.
        neuVersiegeln()
        let alt = istVorschau ? 0 : Ablage.shared.altbestaendeEntsiegeln(tresor)
        var text = "Verschlüsselung aufgehoben — die Ablage liegt wieder im Klartext"
            + (alt > 0 ? ", \(alt) ältere \(alt == 1 ? "Stand" : "Stände") daneben ebenfalls" : "")
            + "."
        if autoexportAktiv {
            autoexportAktiv = false
            text += " Die Sicherungskopie beim Beenden ist ausgeschaltet: Es gibt sie nur verschlüsselt."
        }
        melden(text, .warnung)
    }

    /// 32 Byte neu wickeln; eine ältere Kopie in der Cloud kennt noch die alte Passphrase.
    func passphraseAendern(alt: String, neu: String) throws {
        guard let tresor else { return }
        guard tresor.passphraseStimmt(alt) else {
            throw Tresorfehler(art: .falscherSchluessel, text: "Die bisherige Passphrase passt nicht.")
        }
        try tresor.passphraseSetzen(neu)
        neuVersiegeln()
        Ablage.shared.altbestaendeVersiegeln()
        melden("Passphrase geändert. Sie gilt für die Ablage sofort und für die Kopie beim "
               + "nächsten Beenden.")
    }

    /// Frischer Datenschlüssel samt neuem Blatt, wenn die alte Passphrase als
    /// verbrannt gilt; scharf erst nach dem bestätigten Blatt.
    func schluesselErneuernVorbereiten(passphrase: String) throws -> String {
        guard let alter = tresor else {
            throw Tresorfehler(art: .keineWicklung, text: "Die Verschlüsselung ist nicht eingeschaltet.")
        }
        guard alter.passphraseStimmt(passphrase) else {
            throw Tresorfehler(art: .falscherSchluessel, text: "Die Passphrase passt nicht.")
        }
        return try verschluesselungVorbereiten(passphrase: passphrase)
    }

    // Entsperren — beim Start, nach einem unlesbaren Stand, für eine fremde Datei

    private func entsperrungBeginnen(_ ziel: Entsperrungsziel) {
        let kopf: Behaelterkopf
        do {
            kopf = try Tresor.kopfLesen(ziel.daten)
        } catch let fehler as Tresorfehler where fehler.art == .neuereFassung {
            // Eine neuere Fassung hat geschrieben: nichts anfassen, nichts
            // beiseitelegen — nur sagen, was zu tun ist.
            if ziel.istAblage {
                sicherungGesperrt = true
                verschluesselungsstand = .gesperrt
            }
            melden(fehler.text, .warnung)
            return
        } catch {
            switch ziel {
            case .ablage:
                // Ein Behälter, dessen Kopf nicht zu lesen ist, ist ein unlesbarer
                // Stand: beiseitelegen und die Fassung davor retten.
                unlesbarenStandBehandeln(Tresorfehler(
                    art: .beschaedigt, text: "der verschlüsselte Behälter ist beschädigt"))
            case .vorige(_, let grund):
                sicherungslageMelden(geklappt: false)
                melden("Die Autosicherung ließ sich nicht lesen (\(grund)), und auch die "
                       + "Fassung davor ist beschädigt. Es wird nichts überschrieben, bis eine "
                       + "Planung angelegt oder geöffnet wird.", .warnung)
                offenerDialog = .neuePlanung
            case .datei:
                melden("Die Datei ist ein beschädigter verschlüsselter Behälter.", .warnung)
            }
            return
        }
        entsperrung = ziel
        gesperrterKopf = kopf
        entsperrungOffen = true
        entsperrungFehler = nil
        entsperrungsweg = .passphrase
        enklaveWicklungPasstNicht = false
        // Vorgabe wie bei Numbers: Häkchen gesetzt, wo eine Enklave da ist.
        enklaveMerken = ziel.istAblage && Tresor.enklaveVerfuegbar
        if ziel.istAblage {
            sicherungGesperrt = true
            verschluesselungsstand = .gesperrt
        }
        freigabeAnfordern()
    }

    /// Wie bei Numbers: Trägt der Kopf eine Wicklung für diesen Mac, steht
    /// zuerst allein die Systemabfrage — das Blatt kommt erst, wenn sie ohne
    /// Ergebnis endet. Sonst gleich das Blatt.
    private func freigabeAnfordern() {
        if enklaveMoeglich { entsperrenMitEnklave() } else { dialogOeffnen(.entsperren) }
    }

    /// Hält den `LAContext` über die abgesetzte Aufgabe hinweg, damit
    /// `invalidate()` die stehende Abfrage abbrechen kann. `LAContext` ist
    /// nicht `Sendable`; benutzt wird er nur in der einen Aufgabe.
    private final class Freigabegriff: @unchecked Sendable {
        let kontext = LAContext()
    }
    private var freigabegriff: Freigabegriff?
    /// Das Blatt hat abgebrochen, während die Abfrage stand: Ihr Ende darf
    /// dann kein Blatt mehr öffnen.
    private var freigabeStillAbgebrochen = false

    /// Touch ID abseits des Hauptstrangs — der Aufruf blockiert bis zur Antwort.
    /// Endet die Abfrage ohne Freigabe, kommt sofort das Blatt; passt die
    /// Wicklung nicht mehr, sagt es das
    /// dazu. Ein Abbruch ist kein Fehler und bekommt keine Warnung.
    func entsperrenMitEnklave() {
        guard let kopf = gesperrterKopf, enklaveMoeglich, !entsperrungLaeuft else { return }
        entsperrungLaeuft = true
        entsperrungFehler = nil
        freigabeStillAbgebrochen = false
        let griff = Freigabegriff()
        griff.kontext.localizedReason = "die Planung zu entsperren"
        freigabegriff = griff
        Task { [weak self] in
            let ergebnis: Result<Tresor, Tresorfehler> = await Task.detached(priority: .userInitiated) {
                do { return .success(try Tresor.oeffnen(kopf: kopf, enklave: griff.kontext)) }
                catch let fehler as Tresorfehler { return .failure(fehler) }
                catch { return .failure(Tresorfehler(art: .abgebrochen, text: error.localizedDescription)) }
            }.value
            guard let self else { return }
            entsperrungLaeuft = false
            if freigabegriff === griff { freigabegriff = nil }
            switch ergebnis {
            case .success(let tresor):
                entsperrt(mit: tresor, durchEnklave: true)
            case .failure(let fehler):
                guard entsperrung != nil, !freigabeStillAbgebrochen else {
                    freigabeStillAbgebrochen = false
                    return
                }
                enklaveWicklungPasstNicht = fehler.art != .abgebrochen
                entsperrungFehler = fehler.art == .abgebrochen ? nil : fehler.text
                if offenerDialog != .entsperren { dialogOeffnen(.entsperren) }
            }
        }
    }

    /// Die stehende Systemabfrage abbrechen — sie endet dann wie „Abbrechen“
    /// darin, und das Blatt kommt. Für den Prüfstand.
    func freigabeAbbrechen() {
        freigabegriff?.kontext.invalidate()
    }

    func entsperren(passphrase: String) {
        guard let kopf = gesperrterKopf else { return }
        do { entsperrt(mit: try Tresor.oeffnen(kopf: kopf, passphrase: passphrase), durchEnklave: false) }
        catch { entsperrungFehler = (error as? Tresorfehler)?.text ?? error.localizedDescription }
    }

    func entsperren(wiederherstellung: String) {
        guard let kopf = gesperrterKopf else { return }
        do { entsperrt(mit: try Tresor.oeffnen(kopf: kopf, wiederherstellung: wiederherstellung), durchEnklave: false) }
        catch { entsperrungFehler = (error as? Tresorfehler)?.text ?? error.localizedDescription }
    }

    func entsperrungswegWechseln() {
        entsperrungsweg = entsperrungsweg == .passphrase ? .wiederherstellung : .passphrase
        entsperrungFehler = nil
    }

    /// Sobald neu getippt wird, ist der alte Fehlertext hinfällig.
    func entsperrungFehlerVerwerfen() {
        entsperrungFehler = nil
    }

    /// Ohne Freigabe geschlossen: Die Ablage bleibt zu (der Leerzustand bietet
    /// das Entsperren weiter an), eine fremde Datei bleibt ungeöffnet.
    func entsperrungAbbrechen() {
        guard let ziel = entsperrung else { return }
        if entsperrungLaeuft {
            freigabeStillAbgebrochen = true
            freigabeAbbrechen()
        }
        if offenerDialog == .entsperren { offenerDialog = nil }
        guard ziel.istAblage else {
            entsperrung = nil
            gesperrterKopf = nil
            entsperrungOffen = false
            return
        }
    }

    /// Aus dem Leerzustand: Touch ID zuerst, sonst das Blatt.
    func entsperrungFortsetzen() {
        guard entsperrung != nil, !entsperrungLaeuft else { return }
        entsperrungFehler = nil
        freigabeAnfordern()
    }

    /// Aus dem Leerzustand gleich zur Passphrase — an der Enklave vorbei.
    func entsperrungMitBlatt() {
        guard entsperrung != nil, !entsperrungLaeuft else { return }
        entsperrungFehler = nil
        dialogOeffnen(.entsperren)
    }

    // ── Die Wicklung dieses Macs ──────────────────────────────────────────

    /// Das Häkchen nach einer Freigabe ohne die Enklave: Wicklung dieses Macs
    /// anlegen — auch anstelle einer, die nicht mehr passt — oder entfernen,
    /// und die Ablage neu versiegeln, damit der nächste Start sie so vorfindet.
    /// Eine Wicklung, die trägt, bleibt unangetastet: Wer Touch ID nur diesmal
    /// abgebrochen hat, bekommt keinen neuen Schlüssel. Die Kopie außer Haus
    /// trägt diese Wicklung ohnehin nie.
    private func enklaveAngleichen(_ tresor: Tresor) {
        defer { enklaveWicklungPasstNicht = false }
        if enklaveMerken {
            guard !tresor.hat(Wicklung.enklave) || enklaveWicklungPasstNicht else { return }
            guard enklaveWicklungAnlegen(tresor) else { return }
            melden(enklaveWicklungPasstNicht
                   ? "Dieser Mac ist neu eingerichtet — Touch ID oder das Anmeldepasswort "
                     + "öffnen die Planung wieder."
                   : "Touch ID oder das Anmeldepasswort öffnen die Planung ab jetzt auf diesem Mac.")
        } else if tresor.hat(Wicklung.enklave) {
            enklaveWicklungEntfernen(tresor)
            melden("Die Wicklung dieses Macs ist entfernt — beim Start ist die Passphrase fällig.")
        }
    }

    /// Der Schalter unter „Einstellungen“ bei offener Planung.
    func enklaveAufDiesemMac(_ an: Bool) {
        guard let tresor, verschluesselungsstand == .an else { return }
        if an {
            guard !tresor.hat(Wicklung.enklave), enklaveWicklungAnlegen(tresor) else { return }
            melden("Touch ID oder das Anmeldepasswort öffnen die Planung ab jetzt auf diesem Mac.")
        } else {
            guard tresor.hat(Wicklung.enklave) else { return }
            enklaveWicklungEntfernen(tresor)
            melden("Die Wicklung dieses Macs ist entfernt — beim Start ist die Passphrase fällig.")
        }
    }

    private func enklaveWicklungAnlegen(_ tresor: Tresor) -> Bool {
        guard Tresor.enklaveVerfuegbar || enklaveImPruefstandAnlegen else { return false }
        do { try tresor.enklaveAnlegen(auchImPruefstand: enklaveImPruefstandAnlegen) }
        catch {
            melden("Die Wicklung für diesen Mac ließ sich nicht anlegen: "
                   + ((error as? Tresorfehler)?.text ?? error.localizedDescription), .warnung)
            return false
        }
        enklaveEingerichtet = true
        neuVersiegeln()
        return true
    }

    private func enklaveWicklungEntfernen(_ tresor: Tresor) {
        tresor.entfernen(art: Wicklung.enklave)
        enklaveEingerichtet = false
        neuVersiegeln()
    }

    private func entsperrt(mit tresor: Tresor, durchEnklave: Bool) {
        guard let ziel = entsperrung else { return }
        entsperrung = nil
        gesperrterKopf = nil
        entsperrungOffen = false
        entsperrungFehler = nil
        if offenerDialog == .entsperren { offenerDialog = nil }
        switch ziel {
        case .ablage(let daten):
            tresorAnlegen(tresor)
            sicherungGesperrt = false
            verschluesselungsstand = .an
            do {
                geladenAusKlartext(try tresor.oeffnen(daten))
                if !durchEnklave { enklaveAngleichen(tresor) }
            } catch { unlesbarenStandBehandeln(error) }
        case .vorige(let vorige, let grund):
            tresorAnlegen(tresor)
            verschluesselungsstand = .an
            if let klartext = try? tresor.oeffnen(vorige),
               let (gerettet, bilanz) = try? Planungsdatei.lesenMitBilanz(klartext) {
                vorigeRettung(gerettet, bilanz: bilanz, grund: grund)
                if !durchEnklave { enklaveAngleichen(tresor) }
            } else {
                sicherungslageMelden(geklappt: false)
                melden("Die Autosicherung ließ sich nicht lesen (\(grund)), und auch die "
                       + "Fassung davor ließ sich nicht entsiegeln. Es wird nichts überschrieben, "
                       + "bis eine Planung angelegt oder geöffnet wird.", .warnung)
                offenerDialog = .neuePlanung
            }
        case .datei(let daten, let url):
            do { importierenKlartext(try tresor.oeffnen(daten), von: url) }
            catch { melden(error.localizedDescription, .warnung) }
        }
    }

    // ── Ersteinrichtung ───────────────────────────────────────────────────
    // Zwei Fragen nach der ersten Planung, beide freiwillig: erst
    // die Verschlüsselung — mit der Einrichtung gleich im Blatt —, dann die
    // Sicherungskopie beim Beenden.

    /// Wer den Ordner schon gewählt hat, wird nicht gefragt.
    var ersteinrichtungFaellig: Bool {
        Planungsspeicher.ersteinrichtungFaellig(
            pruefstand: Ablage.istPruefstand,
            ordner: autoexportOrdner,
            gefragt: UserDefaults.standard.bool(forKey: Schluessel.autoexportGefragt))
    }

    /// Die Entscheidung ohne ihre drei Quellen — sonst ließe sie sich nicht
    /// prüfen: Im Prüflauf ist `Ablage.istPruefstand` gesetzt.
    static func ersteinrichtungFaellig(pruefstand: Bool, ordner: String, gefragt: Bool) -> Bool {
        !pruefstand && ordner.isEmpty && !gefragt
    }

    /// Die Stationen des Blatts: die Frage nach der Verschlüsselung, deren
    /// zwei Einrichtungsschritte, die Frage nach der Sicherungskopie. Im
    /// Speicher statt im Blatt, damit Prüfungen und Abbilder jede erreichen.
    enum Ersteinrichtungsschritt: Equatable, Sendable {
        case verschluesselung
        case passphrase
        /// Mit dem Wiederherstellungsschlüssel, der nur hier gezeigt wird.
        case blatt(String)
        case sicherung
    }
    private(set) var ersteinrichtungsschritt: Ersteinrichtungsschritt = .verschluesselung

    /// Die Frage kommt erst, wenn eine Planung da ist und kein anderes Blatt
    /// offen liegt — sonst nähme sie ihm das Fenster weg.
    func ersteinrichtungPruefen() {
        guard ersteinrichtungFaellig, hatPlanung, !dialogOffen else { return }
        ersteinrichtungOeffnen()
    }

    /// Das Blatt öffnen, ohne die Schranke — für Prüfungen und Prüfstände.
    /// Ist die Verschlüsselung schon eingeschaltet (eine versiegelte Datei als
    /// erste Planung), bleibt nur die zweite Frage.
    func ersteinrichtungOeffnen() {
        ersteinrichtungsschritt = verschluesselt ? .sicherung : .verschluesselung
        offenerDialog = .ersteinrichtung
    }

    /// „Verschlüsselung einrichten …“: Schritt 1, die Passphrase.
    func ersteinrichtungEinrichten() {
        ersteinrichtungsschritt = .passphrase
    }

    /// „Weiter“ nach der Passphrase: Datenschlüssel und Wicklungen liegen
    /// bereit, das Blatt mit dem Wiederherstellungsschlüssel folgt. Scharf ist
    /// noch nichts; eine zu kurze Passphrase wirft und lässt den Schritt stehen.
    func ersteinrichtungWeiter(passphrase: String) throws {
        ersteinrichtungsschritt = .blatt(try verschluesselungVorbereiten(passphrase: passphrase))
    }

    /// „Verschlüsselung einschalten“ nach dem bestätigten Blatt — und weiter
    /// zur zweiten Frage, deren Kopie dann von Anfang an versiegelt ist.
    func ersteinrichtungEinschalten() {
        guard case .blatt = ersteinrichtungsschritt else { return }
        verschluesselungEinschalten()
        ersteinrichtungsschritt = .sicherung
    }

    /// „Abbrechen“ in der Einrichtung: zurück zur Frage; geschehen ist nichts.
    func ersteinrichtungAbbrechen() {
        verschluesselungVerwerfen()
        ersteinrichtungsschritt = .verschluesselung
    }

    /// „Überspringen“: Die Verschlüsselung bleibt aus — nachzuholen unter
    /// „Einstellungen“, spätestens mit der Kopie, die es nur versiegelt gibt.
    func ersteinrichtungUeberspringen() {
        ersteinrichtungsschritt = .sicherung
    }

    /// Beantwortet ist beantwortet — auch „Später“; nachzuholen ist es unter
    /// „Einstellungen“.
    func ersteinrichtungBeantwortet() {
        Einstellungen.setzen(true, Schluessel.autoexportGefragt)
    }

    // ── Tour durch die Oberfläche ─────────────────────────────────────────

    /// Ein Schritt der Tour: woran die Karte hängt und was sie sagt. Die Texte
    /// stehen hier, nicht in der Ansicht, damit die Prüfungen sie lesen.
    enum Tourschritt: String, CaseIterable, Sendable {
        case dateien, planung, ansicht, zelle, anlegen, frei, ohneZeile

        /// Einträge der Werkzeugleiste (Beschriftung des `Label`, ersatzweise
        /// der Anfang des Hilfetexts, in dieser Reihenfolge) — oder die
        /// Beispielzelle des Rasters. Der Breitenregler meldet AppKit keine
        /// Beschriftung; die dritte Karte hängt am Knopf daneben.
        enum Anker: Equatable, Sendable {
            case werkzeug([String])
            case zelle
        }

        var anker: Anker {
            switch self {
            case .dateien: .werkzeug(["Neue Planung"])
            case .planung, .ohneZeile: .werkzeug(["Klassen/Kurse"])
            case .ansicht: .werkzeug(["Darstellung umschalten"])
            case .zelle, .anlegen, .frei: .zelle
            }
        }

        var titel: String {
            switch self {
            case .dateien: "Planungsdateien"
            case .planung: "Die Planung einrichten"
            case .ansicht: "Suchen, Breite, Darstellung"
            case .zelle: "Das Raster"
            case .anlegen: "Ein Vorhaben anlegen"
            case .frei: "Unterrichtsfrei kennzeichnen"
            case .ohneZeile: "Noch keine Zeile"
            }
        }

        /// `zelle` nennt die Beispielzelle („G6a, KW 33“), vom Raster gesetzt.
        func text(zelle: String) -> String {
            switch self {
            case .dateien:
                "Ganz links: eine neue Planung anlegen (⌘N), eine gesicherte Datei öffnen "
                + "(⌘O) und die aktuelle als JSON-Datei sichern (⌘S). Gesichert wird ohnehin "
                + "laufend auf diesem Mac — der Export ist die Kopie zum Mitnehmen oder "
                + "Weitergeben."
            case .planung:
                "Diese Gruppe führt durch die Planung: zur laufenden Woche springen (⌘J), "
                + "die Tagesliste zum Abhaken (⌘D), Klassen/Kurse mit Fächern und Farben "
                + "(⌘K), Ferien und unterrichtsfreie Zeiten (⌘E), alle Prüfungstermine (⌘R) "
                + "und die Einstellungen mit Zeitraum, Sicherungskopie und Verschlüsselung (⌘,)."
            case .ansicht:
                "Rechts: Das Suchfeld (⌘F) blendet alle Kacheln aus, die nicht passen — "
                + "Escape leert es. Der Regler stellt die Spaltenbreite in drei Stufen (⌘+ "
                + "und ⌘−), der Knopf daneben schaltet zwischen heller und dunkler Darstellung."
            case .zelle:
                "Jede Zeile ist eine Klasse oder ein Kurs, jede Spalte eine Woche — im "
                + "Spaltenkopf stehen Kalenderwoche und Schulwoche. Diese Zelle sammelt die "
                + "Vorhaben von \(zelle.isEmpty ? "der ersten Zeile in ihrer ersten Woche" : zelle)"
                + ". Ein Klick wählt sie an; Kacheln lassen sich anwählen, öffnen und in "
                + "andere Zellen ziehen."
            case .anlegen:
                "Beim Überfahren zeigt jede Zelle unten links „+ Vorhaben“ — ein Klick öffnet "
                + "den Dialog mit Titel, Beschreibung, Materialien, Links, Wochentag und "
                + "Prüfungskennzeichen. Genauso: Doppelklick auf freie Fläche, ⌘T oder das "
                + "Rechtsklickmenü der Zelle."
            case .frei:
                "Das Schirmsymbol unten rechts stellt nur diese Klasse in dieser Woche frei — "
                + "etwa bei Exkursion oder Praktikum; die Zelle wird schraffiert, ein zweiter "
                + "Klick nimmt es zurück. Dasselbe Symbol im Spaltenkopf stellt die ganze Woche "
                + "frei; Ferien kommen über ⌘E."
            case .ohneZeile:
                "Das Raster bekommt seine Zeilen aus „Klassen/Kurse“ (⌘K). Sobald eine Zeile "
                + "da ist, zeigt die Tour dort, wie ein Vorhaben entsteht und wie eine Zelle "
                + "unterrichtsfrei wird — Hilfe → Tour durch die Oberfläche."
            }
        }
    }

    private(set) var tourSchritt: Tourschritt?
    var tourLaeuft: Bool { tourSchritt != nil }
    /// Die Beispielzelle („G6a, KW 33“) — vom Raster gesetzt, für den Kartentext.
    var tourZelle = ""
    /// Nach dem Anlegen einer Planung vorgemerkt; gefragt wird, sobald kein
    /// Blatt mehr offen ist (Ersteinrichtung zuerst).
    private var tourAnbieten = false
    private var tourAngebotenInSitzung = false

    /// Ohne Zeile gibt es keine Beispielzelle — dann sagt der letzte Schritt, wo sie herkommt.
    var tourSchritte: [Tourschritt] {
        (planung?.klassen.isEmpty ?? true)
            ? [.dateien, .planung, .ansicht, .ohneZeile]
            : [.dateien, .planung, .ansicht, .zelle, .anlegen, .frei]
    }

    /// Für „Schritt n von N“.
    var tourStelle: (stelle: Int, zahl: Int) {
        let schritte = tourSchritte
        let stelle = tourSchritt.flatMap { schritte.firstIndex(of: $0) } ?? 0
        return (stelle + 1, schritte.count)
    }
    var tourAmAnfang: Bool { tourSchritt == tourSchritte.first }
    var tourAmEnde: Bool { tourSchritt == tourSchritte.last }

    private var tourAngeboten: Bool {
        tourAngebotenInSitzung || UserDefaults.standard.bool(forKey: Schluessel.tourAngeboten)
    }

    /// Gefragt wird genau einmal, und nie über ein offenes Blatt hinweg.
    func tourAnbietenPruefen() {
        guard tourAnbieten, hatPlanung, !dialogOffen, !tourLaeuft, !tourAngeboten else { return }
        tourAnbieten = false
        tourAngebotenInSitzung = true
        Einstellungen.setzen(true, Schluessel.tourAngeboten)
        offenerDialog = .tour
    }

    /// Aus dem Angebot, dem Hilfe-Menü oder der Kurzanleitung — auch aus einem
    /// Blatt heraus: Die Karte kommt erst, wenn das Blatt abgelöst ist.
    func tourStarten() {
        tourAnbieten = false
        Task { @MainActor [weak self] in
            await Planungsspeicher.blaetterAbloesenAbwarten()
            self?.tourBeginnen()
        }
    }

    /// Der erste Schritt, sofort — für die Prüfungen ohne Fenster.
    func tourBeginnen() {
        guard hatPlanung else {
            melden("Die Tour braucht eine Planung — zuerst eine anlegen oder öffnen.", .warnung)
            return
        }
        guard !dialogOffen else { return }
        tourSchritt = tourSchritte.first
    }

    func tourWeiter() {
        guard let aktuell = tourSchritt else { return }
        let schritte = tourSchritte
        guard let stelle = schritte.firstIndex(of: aktuell), stelle + 1 < schritte.count else {
            tourBeenden(abgeschlossen: true)
            return
        }
        tourSchritt = schritte[stelle + 1]
    }

    func tourZurueck() {
        guard let aktuell = tourSchritt,
              let stelle = tourSchritte.firstIndex(of: aktuell), stelle > 0 else { return }
        tourSchritt = tourSchritte[stelle - 1]
    }

    /// Die Meldung kommt einen Augenblick später: erst geht die Karte zu, dann
    /// blendet die Glaskapsel ein — zugleich lief die Materialauflösung heiß.
    func tourBeenden(abgeschlossen: Bool = false) {
        guard tourLaeuft else { return }
        tourSchritt = nil
        tourZelle = ""
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.melden(abgeschlossen
                         ? "Das war die Tour. Wiederholen: Hilfe → Tour durch die Oberfläche."
                         : "Tour beendet — jederzeit wieder unter Hilfe → Tour durch die Oberfläche.")
        }
    }

    // ── Stand aus der Ansicht fürs iPad ───────────────────────────────────

    /// Sucht die Statusdatei im Ordner der Sicherungskopie und übernimmt sie.
    /// Gemeldet wird nur, was sich geändert hat, und ein Fehler in der Datei.
    func statusUebernehmen() {
        guard planung != nil, !autoexportOrdner.isEmpty,
              let ordner = zielordnerFinden() else { return }
        let datei = ordner.appending(component: Statusdatei.name, directoryHint: .notDirectory)

        let groesse = (try? datei.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard groesse > 0 else { return }
        guard groesse <= Statusdatei.hoechstgroesse else {
            melden("Die Statusdatei aus der iPad-Ansicht ist ungewöhnlich groß "
                   + "(\(groesse / 1024 / 1024) MB) und wurde nicht eingelesen.", .warnung)
            return
        }
        guard let roh = try? Data(contentsOf: datei) else { return }

        // Ein Behälter unter fremdem Schlüssel wird benannt, nicht geraten.
        let daten: Data
        if Tresor.istBehaelter(roh) {
            guard let tresor else {
                melden("Die Statusdatei aus der iPad-Ansicht ist verschlüsselt, die Ablage "
                       + "auf diesem Mac ist es nicht — sie wurde nicht eingelesen.", .warnung)
                return
            }
            do {
                let kopf = try Tresor.kopfLesen(roh)
                guard kopf.inhalt == Tresor.Inhalt.status.rawValue else {
                    melden("Die Statusdatei aus der iPad-Ansicht ist ein Behälter mit Inhalt "
                           + "„\(kopf.inhalt)“, kein Status — sie wurde nicht eingelesen.", .warnung)
                    return
                }
                daten = try tresor.oeffnen(kopf: kopf)
                // Wicklungen der Ansicht reisen in die nächste Kopie — nur aus einer
                // Datei, die unter dem eigenen Schlüssel aufging.
                if tresor.fremdeWicklungenUebernehmen(aus: kopf) > 0 { neuVersiegeln() }
            } catch let fehler as Tresorfehler where fehler.art == .falscherSchluessel {
                melden("Die Statusdatei aus der iPad-Ansicht ist unter einem anderen Schlüssel "
                       + "versiegelt und wurde nicht eingelesen — die Ansicht hat eine ältere "
                       + "Kopie geöffnet.", .warnung)
                return
            } catch {
                melden("Die Statusdatei aus der iPad-Ansicht ließ sich nicht entsiegeln: "
                       + "\(error.localizedDescription) Die Planung bleibt unverändert.", .warnung)
                return
            }
        } else {
            daten = roh
            if tresor != nil {
                melden("Die Statusdatei aus der iPad-Ansicht kam unverschlüsselt an — sie "
                       + "stammt aus einer älteren Ansichtsfassung oder aus einer älteren Kopie.",
                       .warnung)
            }
        }

        do {
            let stand = try Statusdatei.lesen(daten)
            // Welcher Eintrag zählt, entscheidet `statusAnwenden` je Vorhaben —
            // eine Schranke über die ganze Datei bräuchte einen gemerkten Stempel,
            // und ein einziger falscher sperrte damit jeden späteren Stand aus.
            if !Planungsspeicher.zeitstempelBrauchbar(stand.gespeichert) {
                melden("Die Statusdatei aus der iPad-Ansicht trägt keinen brauchbaren "
                       + "Zeitpunkt. Bitte Datum und Uhrzeit des iPads prüfen — sonst "
                       + "bleiben Einträge ohne eigenen Stempel liegen.", .warnung)
            }

            let (haken, notizen) = statusAnwenden(stand)
            guard haken > 0 || notizen > 0 else { return }
            melden("Aus der Ansicht fürs iPad übernommen: "
                   + [haken > 0 ? "\(haken) \(haken == 1 ? "Markierung" : "Markierungen")" : nil,
                      notizen > 0 ? "\(notizen) \(notizen == 1 ? "Kommentar" : "Kommentare")" : nil]
                        .compactMap { $0 }.joined(separator: " und ") + ".")
        } catch {
            melden("Die Statusdatei aus der iPad-Ansicht ließ sich nicht lesen: "
                   + "\(error.localizedDescription) Die Planung bleibt unverändert.", .warnung)
        }
    }

    /// Der reine Abgleich, ohne Datei — so ist er prüfbar.
    ///
    /// **Der jüngere Stand gilt** — auch ein zurückgenommener Haken und ein
    /// geleerter Kommentar, sofern der Eintrag nach der letzten Änderung an
    /// dieser Planung entstand. Dieselbe Regel wendet die Ansicht in der
    /// Gegenrichtung an; ohne sie überschriebe ein liegengebliebener
    /// iPad-Stand neuere Eingaben am Mac.
    @discardableResult
    func statusAnwenden(_ stand: Statusstand) -> (erledigt: Int, kommentare: Int) {
        guard var p = planung else { return (0, 0) }
        var haken = 0
        var notizen = 0
        var stempelGesetzt = false
        for stelle in p.eintraege.indices {
            guard let eintrag = stand.eintraege[p.eintraege[stelle].id] else { continue }
            // Ältere Dateien tragen den Stempel nur an der Datei, nicht am Eintrag.
            let stempel = eintrag.geaendert.isEmpty ? stand.gespeichert : eintrag.geaendert
            guard Planungsspeicher.zeitstempelBrauchbar(stempel) else { continue }
            // Gegen den Stempel dieses Vorhabens, nicht gegen `planung.geaendert`:
            // sonst entwertete jede Mac-Änderung den ganzen Stand. Leer: nie angefasst.
            let hier = p.eintraege[stelle].statusGeaendert
            // Ein unbrauchbarer Stempel — aus einer falsch gestellten Uhr in die
            // Planungsdatei geraten — sperrte das Vorhaben sonst für immer.
            let schranke = Planungsspeicher.zeitstempelBrauchbar(hier) ? hier : ""
            guard schranke.isEmpty || stempel > schranke else { continue }
            if p.eintraege[stelle].erledigt != eintrag.erledigt {
                p.eintraege[stelle].erledigt = eintrag.erledigt
                haken += 1
            }
            if p.eintraege[stelle].kommentar != eintrag.kommentar {
                p.eintraege[stelle].kommentar = eintrag.kommentar
                notizen += 1
            }
            // Sonst drehte eine später auftauchende ältere Statusdatei das zurück.
            if p.eintraege[stelle].statusGeaendert != stempel {
                p.eintraege[stelle].statusGeaendert = stempel
                stempelGesetzt = true
            }
        }
        // Der Stempel wird auch dann festgeschrieben, wenn kein Wert abwich:
        // Er ist die Schranke gegen den älteren Stand eines zweiten Geräts.
        guard haken > 0 || notizen > 0 || stempelGesetzt else { return (0, 0) }
        planung = p
        sichern()
        return (haken, notizen)
    }

    /// Taugt der Zeitstempel als Schranke zwischen beiden Fassungen?
    ///
    /// Genau die Form von `toISOString()` — die Vergleiche in `statusAnwenden`
    /// ordnen zeichenweise, und das trägt nur bei fester Stellenzahl in UTC —
    /// und nicht in der Zukunft, mit einer Minute Nachsicht für
    /// auseinanderlaufende Uhren. Ein Stand mit „2099-…“ aus einem Gerät mit
    /// falsch gestellter Uhr gewänne sonst für immer gegen jeden späteren.
    /// Dieselbe Regel wendet die Ansicht an (`zeitstempelBrauchbar`).
    static func zeitstempelBrauchbar(_ wert: String, jetzt: Date = Date()) -> Bool {
        let maske = "0000-00-00T00:00:00.000Z"
        guard wert.count == maske.count else { return false }
        for (zeichen, vorlage) in zip(wert, maske) {
            if vorlage == "0" {
                guard zeichen.isASCII, zeichen.isNumber else { return false }
            } else if zeichen != vorlage {
                return false
            }
        }
        // Die Felder selbst prüfen statt sie dem Datumsleser zu überlassen: Der
        // der App nimmt den 30. Februar an und rechnet ihn auf den 2. März
        // weiter, der des Browsers weist ihn ab — bei der Schaltsekunde
        // („…:59:60Z“) ist es umgekehrt. Ein Stempel, den nur eine Seite gelten
        // lässt, entscheidet denselben Abgleich hier und dort verschieden.
        let zeichen = Array(wert)
        func zahl(_ von: Int, _ bis: Int) -> Int { Int(String(zeichen[von..<bis])) ?? -1 }
        guard Tag(iso: String(wert.prefix(10))) != nil,
              zahl(11, 13) <= 23, zahl(14, 16) <= 59, zahl(17, 19) <= 59
        else { return false }
        guard let zeitpunkt = Zeitrechnung.zeitpunkt(aus: wert) else { return false }
        return zeitpunkt <= jetzt.addingTimeInterval(60)
    }

    /// Beim Start nachreichen, was beim Beenden nicht mehr zu sehen war.
    ///
    /// **Ein Prüflauf bleibt außen vor:** Der vorgemerkte Fehler wird beim
    /// Anzeigen verbraucht, also darf ein Prüflauf ihn nicht einmal lesen.
    private func autoexportlageMelden() {
        guard !Ablage.istPruefstand else { return }
        let stand = UserDefaults.standard.double(forKey: Schluessel.autoexportStand)
        if stand > 0 { letzterAutoexport = Date(timeIntervalSinceReferenceDate: stand) }
        guard let fehler = UserDefaults.standard.string(forKey: Schluessel.autoexportFehler),
              !fehler.isEmpty else { return }
        Einstellungen.entfernen(Schluessel.autoexportFehler)
        melden(fehler, .warnung)
    }

    /// Einstellungen schreiben — außer im Prüflauf: Eine Prüfung darf nichts in
    /// den Einstellungen des Nutzers hinterlassen.
    enum Einstellungen {
        static func setzen(_ wert: Any, _ schluessel: String) {
            guard !Ablage.istPruefstand else { return }
            UserDefaults.standard.set(wert, forKey: schluessel)
        }

        /// **Löschen ist auch Schreiben.** Als blankes
        /// `UserDefaults.standard.removeObject(…)` lief das an dieser Schranke
        /// vorbei, und ein Prüflauf verbrauchte die Warnung des Nutzers.
        static func entfernen(_ schluessel: String) {
            guard !Ablage.istPruefstand else { return }
            UserDefaults.standard.removeObject(forKey: schluessel)
        }
    }

    private enum Schluessel {
        static let spaltenbreite = "unterrichtsplanung.spaltenbreite"
        static let erscheinung = "unterrichtsplanung.erscheinung"
        static let autoexportAktiv = "unterrichtsplanung.autoexport.aktiv"
        static let autoexportOrdner = "unterrichtsplanung.autoexport.ordner"
        static let autoexportStand = "unterrichtsplanung.autoexport.stand"
        static let autoexportFehler = "unterrichtsplanung.autoexport.fehler"
        static let autoexportLesezeichen = "unterrichtsplanung.autoexport.lesezeichen"
        static let autoexportGefragt = "unterrichtsplanung.autoexport.gefragt"
        static let tourAngeboten = "unterrichtsplanung.tour.angeboten"
    }

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

    private var sicherungsAuftrag: Task<Void, Never>?
    /// Der Stand von der Platte wird genau einmal geladen.
    private var gestartet = false
    /// Zeitstempel des zuletzt geschriebenen Standes.
    private var gesicherterStand: String?
    /// Gesetzt, wenn ein vorhandener Stand nicht gelesen werden konnte — dann
    /// wird nichts geschrieben, damit er nicht verlorengeht.
    private var sicherungGesperrt = false
    /// Nur die Startsperre nach unlesbarem Stand lässt sich wieder aufheben;
    /// die einer Vorschau bleibt für deren ganze Lebensdauer bestehen.
    private var startsperre = false
    /// Eine Vorschau schreibt absichtlich nicht — das ist keine Störung und
    /// gehört nicht in die Werkzeugleiste.
    private var istVorschau = false

    /// Für die Werkzeugleiste: Seit wann auch immer — es wird gerade nichts
    /// gesichert, und das muss sichtbar bleiben, nicht nur kurz aufblitzen.
    var sicherungLiegtStill: Bool {
        !istVorschau && (sicherungGesperrt || sicherungGestoert)
    }

    // ── Start ─────────────────────────────────────────────────────────────

    init() {
        // `didSet` läuft für die Zuweisung im Aufbau nicht — hier selbst rasten.
        let gespeicherteBreite = UserDefaults.standard.double(forKey: Schluessel.spaltenbreite)
        spaltenbreite = gespeicherteBreite > 0
            ? Kennwerte.spalteRasten(gespeicherteBreite) : Kennwerte.spalteStandard
        erscheinung = Erscheinung(
            rawValue: UserDefaults.standard.string(forKey: Schluessel.erscheinung) ?? "") ?? .system
        // Ein Prüflauf erbt die Sicherungskopie nicht — sonst schriebe er in den echten Ordner.
        autoexportAktiv = Ablage.istPruefstand
            ? false : UserDefaults.standard.bool(forKey: Schluessel.autoexportAktiv)
        autoexportOrdner = Ablage.istPruefstand
            ? "" : (UserDefaults.standard.string(forKey: Schluessel.autoexportOrdner) ?? "")
        autoexportLesezeichen = Ablage.istPruefstand
            ? nil : UserDefaults.standard.data(forKey: Schluessel.autoexportLesezeichen)
    }

    /// Für Vorschauen und Prüfungen: mit fertiger Planung starten, ohne die
    /// Platte anzufassen. Die Sicherung bleibt gesperrt.
    convenience init(vorschau: Planung?) {
        self.init()
        planung = vorschau
        gestartet = true
        sicherungGesperrt = true
        istVorschau = true
    }

    /// Den letzten Stand laden. Ist keiner da, fragt die Oberfläche nach einer
    /// neuen Planung.
    func starten() {
        guard !gestartet else { return }
        gestartet = true
        autoexportlageMelden()
        lesezeichenNachruesten()

        switch Ablage.shared.lesen() {
        case .keine:
            offenerDialog = .neuePlanung
        case .unlesbar(let fehler):
            unlesbarenStandBehandeln(fehler)
        case .daten(let gelesen):
            if Tresor.istBehaelter(gelesen) {
                // Verschlüsselt: erst entsperren, dann laden. Der Datenschlüssel
                // kommt aus der Enklave (fragt Touch ID) oder aus der Passphrase.
                entsperrungBeginnen(.ablage(gelesen))
                return
            }
            geladenAusKlartext(gelesen)
        }
    }

    /// Nicht überschreiben, was sich nur nicht lesen ließ — und, wenn es geht,
    /// die Fassung davor retten. Derselbe Rettungsweg wie beim unlesbaren
    /// JSON: Ohne ihn legte der Nutzer eine neue Planung an, und deren erstes
    /// Schreiben schöbe planung-vorher.json fort — die letzte gute Fassung
    /// wäre dahin.
    private func unlesbarenStandBehandeln(_ fehler: any Error) {
        sicherungGesperrt = true
        startsperre = true
        if let vorige = Ablage.shared.vorigeFassungLesen() {
            if Tresor.istBehaelter(vorige), Ablage.shared.tresor == nil {
                // Auch die Fassung davor ist verschlüsselt: erst entsperren, dann retten.
                entsperrungBeginnen(.vorige(vorige, fehler.localizedDescription))
                return
            }
            if let klartext = try? Ablage.shared.entsiegelt(vorige),
               let (gerettet, bilanz) = try? Planungsdatei.lesenMitBilanz(klartext) {
                vorigeRettung(gerettet, bilanz: bilanz, grund: fehler.localizedDescription)
                return
            }
        }
        sicherungslageMelden(geklappt: false)
        melden("Die Autosicherung ließ sich nicht lesen (\(fehler.localizedDescription)). "
               + "Es wird nichts überschrieben, bis eine Planung angelegt oder geöffnet "
               + "wird — bitte die Datei prüfen.", .warnung)
        offenerDialog = .neuePlanung
    }

    /// Die gerettete Vorgängerfassung laden und wieder hinlegen.
    private func vorigeRettung(_ gerettet: Planung, bilanz: Planungsdatei.Verlustbilanz,
                               grund: String) {
        planung = gerettet
        zurLaufendenWoche()
        // `gesicherterStand` bleibt offen, damit `jetztSichern()` die gerettete
        // Fassung hinlegt, sobald der unlesbare Stand beiseiteliegt.
        startsperreAufheben()
        jetztSichern()
        let nachsatz = sicherungGesperrt
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
    private func geladenAusKlartext(_ daten: Data) {
        do {
            let (gelesen, bilanz) = try Planungsdatei.lesenMitBilanz(daten)
            planung = gelesen
            gesicherterStand = gelesen.geaendert
            letzteSicherung = Ablage.shared.stand()
            zurLaufendenWoche()
            // Was der eigene Stand beim Lesen verliert, schriebe die nächste
            // Autosicherung sonst kommentarlos gekürzt zurück.
            let verlust = Planungsspeicher.verlusttext(bilanz)
            if !verlust.isEmpty {
                melden("Beim Laden der Autosicherung" + verlust
                       + " Die Fassung davor liegt als planung-vorher.json daneben.",
                       .warnung)
            }
            // Erst die Planung, dann der Stand vom iPad — er ändert sie.
            statusUebernehmen()
        } catch {
            // Sonst überschriebe die nächste neue Planung den letzten Rest.
            Ablage.shared.beschaedigtenStandBeiseitelegen(stempel: Zeitrechnung.dateistempel())

            if let vorige = Ablage.shared.vorigeFassungLesen(),
               let klartext = try? Ablage.shared.entsiegelt(vorige),
               let (gerettet, bilanz) = try? Planungsdatei.lesenMitBilanz(klartext) {
                planung = gerettet
                zurLaufendenWoche()
                // Jetzt, solange keine planung.json daneben liegt: Der übernächste
                // Schreibvorgang schöbe die ungekürzte Vorgängerfassung sonst fort.
                vorigeFassungMitstempeln()
                // `gesicherterStand` bleibt offen, damit `jetztSichern()` den geretteten
                // Stand als planung.json hinlegt — sonst fände der nächste Start nichts.
                jetztSichern()
                melden("Die letzte Autosicherung war unlesbar — die Fassung davor "
                       + "(\(Zeitrechnung.zeitpunktLang(gerettet.geaendert))) wurde geladen "
                       + "und wieder gesichert. Der unlesbare Stand liegt als "
                       + "Rettungskopie daneben." + Planungsspeicher.verlusttext(bilanz),
                       .warnung)
                return
            }

            melden("Die letzte Autosicherung war unlesbar und wurde als Rettungskopie beiseitegelegt.",
                   .warnung)
            offenerDialog = .neuePlanung
        }
    }

    /// Legt der Nutzer bewusst eine Planung an oder öffnet eine Datei, ist der
    /// unlesbare Stand nicht mehr das, was die Sperre schützen soll. Er wird
    /// beiseitegelegt; erst wenn das gelang, darf wieder geschrieben werden.
    private func startsperreAufheben() {
        guard startsperre else { return }
        guard Ablage.shared.beschaedigtenStandBeiseitelegen(
                stempel: Zeitrechnung.dateistempel()) else { return }
        vorigeFassungMitstempeln()
        startsperre = false
        sicherungGesperrt = false
        sicherungGestoert = false
    }

    /// Legt eine Kopie der vorhandenen `planung-vorher.json` unter einem
    /// Stempelnamen daneben.
    ///
    /// Sie ist nach einem unlesbaren Stand die letzte maschinell lesbare
    /// Fassung, und `Ablage.schreiben` schiebt beim zweiten Schreibvorgang die
    /// neue Planung darüber. Aufzurufen, solange das Schreiben gesperrt ist
    /// oder keine `planung.json` daneben liegt — nur dann kommt der
    /// Sicherungsweg der Kopie nicht in die Quere.
    private func vorigeFassungMitstempeln() {
        let verwaltung = FileManager.default
        let quelle = Ablage.shared.vorherigeFassung
        guard verwaltung.fileExists(atPath: quelle.path) else { return }
        let ziel = Ablage.shared.ordner.appendingPathComponent(
            "planung-vorher-\(Zeitrechnung.dateistempel()).json", isDirectory: false)
        guard !verwaltung.fileExists(atPath: ziel.path) else { return }
        try? verwaltung.copyItem(at: quelle, to: ziel)
    }

    // ── Sichern ───────────────────────────────────────────────────────────

    /// Nach jeder Änderung aufzurufen; schreibt entprellt.
    func sichern() {
        guard planung != nil else { return }
        planung?.geaendert = Zeitrechnung.jetztAlsZeitstempel()
        sicherungsAuftrag?.cancel()
        sicherungsAuftrag = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.imHintergrundSichern()
        }
    }

    /// Umwandeln und Schreiben laufen abseits des Hauptstrangs (4,9 ms bei 400
    /// Vorhaben). Beim Beenden bleibt es bei `jetztSichern()`.
    private func imHintergrundSichern() async {
        Entpreller.allesUebernehmen()
        guard let planung, !sicherungGesperrt,
              planung.geaendert != gesicherterStand else { return }
        let stand = planung.geaendert
        // Die Nummer wird vor dem `await` gezogen: Schreibt `jetztSichern()`
        // währenddessen einen jüngeren Stand, verwirft die Sicherungsfolge
        // diesen hier, statt ihn darüberzulegen.
        let nummer = Sicherungsfolge.shared.naechsteNummer()
        let ergebnis = await Task.detached(priority: .utility) {
            try? Sicherungsfolge.shared.schreiben(
                nummer: nummer, stand: stand,
                daten: Planungsdatei.schreiben(planung))
        }.value
        guard let ergebnis else {
            sicherungslageMelden(geklappt: false)
            return
        }
        switch ergebnis {
        case .geschrieben:
            gesicherterStand = stand
            letzteSicherung = Date()
        case .unveraendert:
            // Ein gleichlaufendes `jetztSichern()` hat diesen Stand schon
            // hingelegt; offen war nur noch der Merker.
            gesicherterStand = stand
        case .ueberholt:
            // Auf der Platte liegt ein jüngerer Stand — nichts zu melden.
            return
        }
        sicherungslageMelden(geklappt: true)
    }

    /// Ohne Entprellung — beim Wegschalten und beim Beenden, durchgängig
    /// gleichlaufend.
    func jetztSichern() {
        Entpreller.allesUebernehmen()
        sicherungsAuftrag?.cancel()
        sicherungsAuftrag = nil
        guard let planung, !sicherungGesperrt else { return }
        // Sonst verdrängte jedes Wegschalten die Vorgängerfassung durch eine Kopie.
        guard planung.geaendert != gesicherterStand else { return }
        // Wartet, falls ein abgetrennter Auftrag gerade schreibt (Millisekunden);
        // genau daraus entsteht die Reihenfolge zwischen beiden Wegen.
        let nummer = Sicherungsfolge.shared.naechsteNummer()
        do {
            _ = try Sicherungsfolge.shared.schreiben(
                nummer: nummer, stand: planung.geaendert,
                daten: Planungsdatei.schreiben(planung))
            gesicherterStand = planung.geaendert
            letzteSicherung = Date()
            sicherungslageMelden(geklappt: true)
        } catch {
            sicherungslageMelden(geklappt: false)
        }
    }

    private func sicherungslageMelden(geklappt: Bool) {
        let gestoert = !geklappt
        guard gestoert != sicherungGestoert else { return }
        sicherungGestoert = gestoert
        if gestoert {
            melden("Die Autosicherung schlägt fehl. Bitte über „Export“ als Datei sichern.", .warnung)
        }
    }

    // ── Meldungen ─────────────────────────────────────────────────────────

    func melden(_ text: String, _ art: Meldung.Art = .hinweis) {
        let meldung = Meldung(text: text, art: art)
        meldungen.append(meldung)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(art == .warnung ? 5200 : 2800))
            self?.meldungen.removeAll { $0.id == meldung.id }
        }
    }

    func meldungSchliessen(_ id: UUID) {
        meldungen.removeAll { $0.id == id }
    }

    func fragen(_ text: String, bestaetigung: String, gefahr: Bool = false,
                ort: Rueckfrageort = .hauptansicht,
                handlung: @escaping @MainActor () -> Void) {
        rueckfrage = Rueckfrage(text: text, bestaetigung: bestaetigung,
                                gefahr: gefahr, ort: ort, handlung: handlung)
    }

    func rueckfrageBeantworten(_ bestaetigt: Bool) {
        let frage = rueckfrage
        rueckfrage = nil
        if bestaetigt { frage?.handlung() }
    }

    // ── Suche ─────────────────────────────────────────────────────────────

    private static func zerlegen(_ begriff: String) -> [String] {
        begriff.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Titel, Beschreibung, Kurs, Materialien und Links — alle Suchworte
    /// müssen vorkommen.
    func trifft(_ vorhaben: Vorhaben, klasse: Klasse?) -> Bool {
        guard !suchworte.isEmpty else { return true }
        var heu = vorhaben.titel + " " + vorhaben.text
        heu += " " + (klasse?.name ?? "") + " " + (klasse?.fach ?? "")
        for m in vorhaben.materialien { heu += " " + m.titel + " " + m.pfad }
        for l in vorhaben.links { heu += " " + l.titel + " " + l.adresse }
        let kleingeschrieben = heu.lowercased()
        return suchworte.allSatisfy { kleingeschrieben.contains($0) }
    }

    var sucheLaeuft: Bool { !suchworte.isEmpty }

    // ── Planung anlegen, laden, sichern ───────────────────────────────────

    func neuePlanung(titel: String, start: Tag, wochen: Int, basis: String,
                     klassen: [Klasse], ersterSchultag: Tag?,
                     uebernahme: [Planung.Uebernahmewunsch]) {
        if let erster = ersterSchultag, !erster.liegtImZeitraum(start: start, wochen: wochen) {
            melden("Der erste Schultag liegt außerhalb des Planungszeitraums.", .warnung)
            return
        }
        guard !entsperrungOffen else {
            melden("Die Planung ist verschlüsselt und noch nicht entsperrt — bitte zuerst "
                   + "entsperren.", .warnung)
            return
        }
        startsperreAufheben()
        // Gleicher fester Dateiname: Die neue Planung überschreibt die Sicherung der bisherigen.
        let nameKollidiert = planung.map {
            Planungsdatei.festerName(titel: $0.titel)
                == Planungsdatei.festerName(titel: titel)
        } ?? false

        let fachfarben = planung?.fachfarben ?? [:]
        // Auf die Lesegrenzen kappen: Was der Leser beim nächsten Start kürzte,
        // soll gar nicht erst entstehen.
        let sauberer = titel.trimmingCharacters(in: .whitespaces)
        let gekappt = sauberer.isEmpty
            ? "Unterrichtsplanung"
            : String(sauberer.prefix(Planungsdatei.maxNamenslaenge))
        let sauberekurse = klassen.map { kurs -> Klasse in
            var k = kurs
            k.name = String(k.name.prefix(Planungsdatei.maxNamenslaenge))
            k.fach = String(k.fach.prefix(Planungsdatei.maxNamenslaenge))
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

    /// Obergrenze beim Öffnen — das Gegenstück zu `Statusdatei.hoechstgroesse`,
    /// nur großzügiger: Auch die Planungsdatei kommt von außen, wird aber auf
    /// dem Hauptstrang gelesen.
    static let hoechstePlanungsgroesse = 32 * 1024 * 1024

    /// Satz über das, was beim Lesen wegfiel — leer, wenn nichts wegfiel.
    private static func verlusttext(_ bilanz: Planungsdatei.Verlustbilanz) -> String {
        guard !bilanz.istLeer else { return "" }
        var teile = bilanz.verworfenes
        if let gekuerzt = bilanz.gekuerztes { teile.append(gekuerzt) }
        return " Übergangen: " + teile.joined(separator: ", ") + "."
    }

    func importieren(von url: URL) {
        let groesse = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard groesse <= Planungsspeicher.hoechstePlanungsgroesse else {
            melden("Die Datei ist mit \(groesse / 1024 / 1024) MB zu groß für eine "
                   + "Planungsdatei und wurde nicht geöffnet.", .warnung)
            return
        }
        guard !entsperrungOffen else {
            melden("Die Planung ist verschlüsselt und noch nicht entsperrt — bitte zuerst "
                   + "entsperren.", .warnung)
            return
        }
        do {
            let daten = try Data(contentsOf: url)
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

    private func importierenKlartext(_ daten: Data, von url: URL) {
        do {
            let (geladen, bilanz) = try Planungsdatei.lesenMitBilanz(daten)
            let uebernehmen: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                startsperreAufheben()
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
        } catch {
            melden("Die Datei konnte nicht geschrieben werden: \(error.localizedDescription)", .warnung)
        }
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

    // ── Titel und Einstellungen ───────────────────────────────────────────

    /// Der Titel als Bindung für die Fensterleiste; entprellt geschrieben, weil
    /// jeder Tastendruck sonst einen Neuaufbau des Rasters nach sich zöge.
    var planungstitel: String {
        get { planung?.titel ?? "Unterrichtsplanung" }
        set {
            guard planung != nil else { return }
            titelentwurf = newValue
            titelentpreller.nach(400) { [weak self] in
                guard let self, let entwurf = titelentwurf else { return }
                titelentwurf = nil
                titelSetzen(entwurf)
            }
        }
    }

    private var titelentwurf: String?
    private let titelentpreller = Entpreller()

    func titelSetzen(_ titel: String) {
        let gekappt = Planungsspeicher.aufNamenslaenge(titel)
        guard planung != nil, planung?.titel != gekappt else { return }
        planung?.titel = gekappt
        sichern()
        if gekappt != titel { kuerzungMelden("Der Titel") }
    }

    /// Vorhaben hinter der neuen letzten Woche gehen verloren — deshalb vorher
    /// die Rückfrage.
    func einstellungenUebernehmen(start: Tag, wochen: Int, ersterSchultag: Tag?) {
        guard let aktuell = planung else { return }
        let anzahl = min(Kennwerte.wochenMax, max(1, wochen))
        let verlust = aktuell.eintraege.count { $0.woche >= anzahl }

        // Ein Tag außerhalb des Zeitraums ließe die Zählung still auf die Herleitung zurückfallen.
        if let erster = ersterSchultag, !erster.liegtImZeitraum(start: start, wochen: anzahl) {
            melden("Der erste Schultag liegt außerhalb des Planungszeitraums.", .warnung)
            return
        }

        let uebernehmen: @MainActor () -> Void = { [weak self] in
            guard let self, var p = planung else { return }
            p.start = start.montagDerWoche
            p.wochen = anzahl
            p.ersterSchultag = ersterSchultag
            p.eintraege.removeAll { $0.woche >= anzahl }
            // `frei` und `zellenfrei` bleiben stehen wie `ferien` und
            // `sperrzeiten`: Sie hängen am Montagsdatum, nicht am Spaltenindex,
            // werden nur über die Wochenliste nachgeschlagen und sind
            // gedeckelt. Gefiltert verschwänden sie beim bloßen Verschieben des
            // Starts still und wären nicht zurückzuholen.

            planung = p
            sichern()
            offenerDialog = nil
            melden("Einstellungen übernommen.")
        }

        if verlust > 0 {
            fragen("\(verlust) Vorhaben liegen hinter der neuen letzten Woche und werden entfernt. Fortfahren?",
                   bestaetigung: "Entfernen", gefahr: true, ort: .einstellungen,
                   handlung: uebernehmen)
        } else {
            uebernehmen()
        }
    }

    // ── Unterrichtsfreie Zeiten ───────────────────────────────────────────

    func wocheFreiSchalten(_ woche: Woche) {
        guard var p = planung else { return }
        if p.frei.contains(woche.montag) { p.frei.remove(woche.montag) }
        else { p.frei.insert(woche.montag) }
        planung = p
        sichern()
    }

    func zelleFreiSchalten(klasse: String, woche: Woche) {
        guard var p = planung else { return }
        let zelle = FreieZelle(klasseId: klasse, woche: woche.montag)
        if p.zellenfrei.contains(zelle) { p.zellenfrei.remove(zelle) }
        else { p.zellenfrei.insert(zelle) }
        planung = p
        sichern()
    }

    @discardableResult
    func ferienHinzufuegen() -> String? {
        guard var p = planung else { return nil }
        let letzte = p.ferien.map(\.bis).max()
        let start = letzte?.plus(tage: 7) ?? p.start
        let montag = start.montagDerWoche
        let neu = Ferienzeitraum(id: Kennung.neu("f"), name: "Ferien",
                                 von: montag, bis: montag.plus(tage: 4))
        p.ferien.append(neu)
        planung = p
        sichern()
        return neu.id
    }

    /// Nur den Namen: Ein entprellter Schreibvorgang trüge sonst den alten
    /// Zeitraum mit sich und nähme eine Datumsänderung zurück.
    func ferienNamenSetzen(id: String, name: String) {
        guard var p = planung, let stelle = p.ferien.firstIndex(where: { $0.id == id }) else { return }
        let gekappt = Planungsspeicher.aufNamenslaenge(name)
        guard p.ferien[stelle].name != gekappt else { return }
        p.ferien[stelle].name = gekappt
        planung = p
        sichern()
        if gekappt != name { kuerzungMelden("Die Bezeichnung des Ferienzeitraums") }
    }

    func ferienAendern(_ zeitraum: Ferienzeitraum) {
        guard var p = planung, let stelle = p.ferien.firstIndex(where: { $0.id == zeitraum.id }) else { return }
        p.ferien[stelle] = zeitraum
        planung = p
        sichern()
    }

    func ferienEntfernen(_ id: String) {
        guard var p = planung else { return }
        p.ferien.removeAll { $0.id == id }
        planung = p
        sichern()
    }

    // ── Klassen ───────────────────────────────────────────────────────────

    /// Liefert die Kennung, damit die Liste die Schreibmarke gleich in das
    /// Namensfeld setzen kann.
    @discardableResult
    func klasseHinzufuegen() -> String? {
        guard var p = planung else { return nil }
        guard p.klassen.count < Kennwerte.maxKlassen else {
            melden("Mehr als \(Kennwerte.maxKlassen) Klassen/Kurse sind nicht vorgesehen.",
                   .warnung)
            return nil
        }
        let neu = Klasse(
            id: Kennung.neu("k"), name: "", fach: "", notiz: "",
            farbe: Farbwelt.ohneFarbe, farbeManuell: false)
        p.klassen.append(neu)
        p.farbenVervollstaendigen()
        planung = p
        sichern()
        return neu.id
    }

    /// Die Fachfarbe zieht nach, solange sie nicht von Hand gesetzt wurde.
    /// Das Fachfeld ist entprellt und meldet auch Halbgetipptes („Mat“) — das
    /// darf nichts hinterlassen, deshalb entscheidet allein `farbeNachziehen`.
    func klasseAendern(id: String, name: String? = nil, fach: String? = nil, notiz: String? = nil) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
        let vorher = p.klassen[stelle]
        // Der Leser kappt Bezeichnung, Fach und Notiz auf `maxNamenslaenge`;
        // ungekappt geschrieben verschwände der Überhang beim nächsten Start.
        var gekuerztes: String?
        func gekappt(_ wert: String, _ feld: String) -> String {
            let kurz = Planungsspeicher.aufNamenslaenge(wert)
            if kurz != wert { gekuerztes = feld }
            return kurz
        }
        if let name { p.klassen[stelle].name = gekappt(name, "Die Bezeichnung") }
        if let notiz { p.klassen[stelle].notiz = gekappt(notiz, "Die Notiz") }
        if let fach { p.klassen[stelle].fach = gekappt(fach, "Das Fach") }
        p.farbeNachziehen(zeile: stelle)
        // Wie bei `ferienNamenSetzen`: Sonst löste schon das Befüllen der Felder
        // beim Erscheinen je Zeile einen Schreibvorgang aus, der die
        // Vorgängerfassung durch eine gleichlautende Kopie verdrängte.
        guard p.klassen[stelle] != vorher else { return }
        planung = p
        sichern()
        if let gekuerztes { kuerzungMelden(gekuerztes) }
    }

    /// Kreuzt einen Unterrichtstag an oder ab. Absichtlich ohne Blick auf die
    /// Vorhaben: Die Angabe hebt im Vorhaben-Dialog Wochentage hervor, sie
    /// weist keinem bestehenden Vorhaben einen Tag zu und nimmt keinem einen.
    func unterrichtstagSetzen(klasse id: String, tag: Wochentag, an: Bool) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
        let vorher = p.klassen[stelle].unterrichtstage
        if an { p.klassen[stelle].unterrichtstage.insert(tag) }
        else { p.klassen[stelle].unterrichtstage.remove(tag) }
        // Ein Klick, der nichts ändert, schreibt nichts — wie `klasseAendern`.
        guard p.klassen[stelle].unterrichtstage != vorher else { return }
        planung = p
        sichern()
    }

    /// Samt der Klassen und Kurse, die das Fach tragen.
    func fachUmbenennen(von alt: String, nach rohNeu: String) {
        guard var p = planung else { return }
        let neu = Planungsspeicher.aufNamenslaenge(rohNeu)
        let alterSchluessel = Farbwelt.fachSchluessel(alt)
        let neuerSchluessel = Farbwelt.fachSchluessel(neu)
        guard alterSchluessel != neuerSchluessel else { return }
        guard !neuerSchluessel.isEmpty else { return }
        // `fachfarben` genügt als Prüfung nicht: Die meisten Fächer hängen an ihren Zeilen.
        guard !p.kenntFach(neu) else {
            melden("„\(neu)“ steht bereits in der Liste.", .warnung)
            return
        }
        if let familie = p.fachfarben.removeValue(forKey: alterSchluessel) {
            p.fachfarben[neuerSchluessel] = familie
        }
        for stelle in p.klassen.indices
        where Farbwelt.fachSchluessel(p.klassen[stelle].fach) == alterSchluessel {
            p.klassen[stelle].fach = neu.trimmingCharacters(in: .whitespaces)
        }
        planung = p
        sichern()
    }

    /// Nur für Fächer ohne Zeile — sonst stünde der Eintrag gleich wieder da.
    func fachEntfernen(_ schluessel: String) {
        guard let p = planung,
              !p.klassen.contains(where: { Farbwelt.fachSchluessel($0.fach) == schluessel })
        else { return }
        fachfarbeSetzen(fach: schluessel, ton: nil)
    }

    /// Setzt oder entfernt eine der beiden Dateien eines Kurses; hinterlegt
    /// wird wie bei den Materialien nur der Verweis.
    func kursdateiSetzen(klasse id: String, art: Kursdateiart, pfad: String?) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else {
            return
        }
        let wert = if let pfad, !pfad.trimmingCharacters(in: .whitespaces).isEmpty {
            Pfade.normalisieren(pfad, basis: p.basis)
        } else {
            ""
        }
        switch art {
        case .verwaltung: p.klassen[stelle].verwaltung = wert
        case .curriculum: p.klassen[stelle].curriculum = wert
        }
        planung = p
        sichern()
    }

    func kursdateiWaehlen(klasse id: String, art: Kursdateiart) {
        guard let gewaehlt = Systemzugriff.dateiWaehlen(start: planung?.basis ?? "",
                                                        titel: art.auswahltitel)
        else { return }
        kursdateiSetzen(klasse: id, art: art, pfad: gewaehlt)
    }

    func klassenTauschen(_ a: Int, _ b: Int) {
        guard var p = planung, p.klassen.indices.contains(a), p.klassen.indices.contains(b) else { return }
        p.klassen.swapAt(a, b)
        planung = p
        sichern()
    }

    func klasseEntfernen(_ klasse: Klasse) {
        guard let p = planung else { return }
        let anzahl = p.anzahlVorhaben(klasse: klasse.id)
        let frage = anzahl > 0
            ? "„\(klasse.name)“ entfernen? Damit werden auch \(anzahl) Vorhaben gelöscht.\n\nVerknüpfte Dateien bleiben unangetastet."
            : "„\(klasse.name)“ entfernen?"
        fragen(frage, bestaetigung: "Entfernen", gefahr: true, ort: .klassen) { [weak self] in
            guard let self, var p = planung else { return }
            p.klassen.removeAll { $0.id == klasse.id }
            p.eintraege.removeAll { $0.klasseId == klasse.id }
            p.zellenfrei = p.zellenfrei.filter { $0.klasseId != klasse.id }
            // Fällt der letzte Kurs aus einer Sperre, gilt sie wieder für alle.
            for stelle in p.sperrzeiten.indices {
                p.sperrzeiten[stelle].kurse.removeAll { $0 == klasse.id }
            }
            planung = p
            sichern()
        }
    }

    /// Ergänzt nur, was fehlt.
    func standardkurseErgaenzen() {
        guard var p = planung else { return }
        let vorhanden = Set(p.klassen.map { ($0.name + "|" + $0.fach).lowercased() })
        let fehlend = Standardkurse.liste.filter { !vorhanden.contains(($0.name + "|" + $0.fach).lowercased()) }
        guard !fehlend.isEmpty else {
            melden("Die Standardliste ist bereits vollständig angelegt.")
            return
        }
        let platz = Kennwerte.maxKlassen - p.klassen.count
        guard platz > 0 else {
            melden("Kein Platz mehr — es sind höchstens \(Kennwerte.maxKlassen) "
                   + "Klassen/Kurse vorgesehen.", .warnung)
            return
        }
        p.klassen.append(contentsOf: Standardkurse.aufbauen(Array(fehlend.prefix(platz))))
        p.farbenVervollstaendigen()
        planung = p
        sichern()
        let zahl = min(fehlend.count, platz)
        melden("\(zahl) \(zahl == 1 ? "Zeile ergänzt." : "Zeilen ergänzt.")"
               + (fehlend.count > platz ? " \(fehlend.count - platz) passten nicht mehr." : ""))
    }

    // ── Farben ────────────────────────────────────────────────────────────

    func farbeSetzen(klasse id: String, farbe: Int) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
        p.klassen[stelle].farbe = farbe
        p.klassen[stelle].farbeManuell = true
        planung = p
        sichern()
    }

    /// Erst die Farbe holen, dann das Merkmal löschen: Sonst zählte die Zeile
    /// als erste ihres Fachs und folgte ihrer eigenen Handauswahl.
    func farbeDemFachFolgen(klasse id: String) {
        guard var p = planung, let stelle = p.klassen.firstIndex(where: { $0.id == id }) else { return }
        if let farbe = p.fachfarbe(p.klassen[stelle].fach) { p.klassen[stelle].farbe = farbe }
        p.klassen[stelle].farbeManuell = false
        planung = p
        sichern()
    }

    /// Färbt alle Zeilen des Fachs nach — außer denen, deren Farbe von Hand
    /// gesetzt wurde.
    func fachfarbeSetzen(fach schluessel: String, ton: String?) {
        guard var p = planung else { return }
        if let ton, Farbwelt.tonNachSchluessel[ton] != nil {
            // Der Leser kappt bei `maxFachfarben`; ein bereits belegtes Fach
            // darf seine Farbe auch am Rand der Grenze noch wechseln.
            guard p.fachfarben[schluessel] != nil
                    || p.fachfarben.count < Planungsdatei.maxFachfarben else {
                melden("Es sind bereits \(Planungsdatei.maxFachfarben) Fachfarben vergeben.",
                       .warnung)
                return
            }
            p.fachfarben[schluessel] = ton
        } else {
            p.fachfarben.removeValue(forKey: schluessel)
        }

        let betroffen = p.klassen.indices.filter {
            Farbwelt.fachSchluessel(p.klassen[$0].fach) == schluessel && !p.klassen[$0].farbeManuell
        }
        if let farbe = p.fachfarbenWirksam()[schluessel] {
            for stelle in betroffen { p.klassen[stelle].farbe = farbe }
        }
        planung = p
        sichern()
    }

    // ── Vorhaben ──────────────────────────────────────────────────────────

    /// Fürs Umbenennen an der Kachel. Ein leerer Titel wird nicht abgewiesen —
    /// die Kachel zeigt dann „Ohne Titel“.
    func titelSetzen(vorhaben id: String, titel: String) {
        let sauber = bereinigt(titel, auf: Planungsdatei.maxNamenslaenge, feld: "Der Titel")
        guard var p = planung, let stelle = p.eintraege.firstIndex(where: { $0.id == id }),
              p.eintraege[stelle].titel != sauber else { return }
        p.eintraege[stelle].titel = sauber
        planung = p
        sichern()
    }

    // ── Reihenfolge innerhalb einer Zelle ─────────────────────────────────
    // Die Kacheln stehen in der Reihenfolge der Eintragsliste; sortiert wird nirgends.

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
        guard var p = planung, let (stellen, eigene) = zellenstellen(id, in: p) else { return }
        let nachbar = nachOben ? eigene - 1 : eigene + 1
        guard stellen.indices.contains(nachbar) else { return }
        p.eintraege.swapAt(stellen[eigene], stellen[nachbar])
        planung = p
        sichern()
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
        guard var p = planung, let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
        p.eintraege[stelle].erledigt.toggle()
        p.eintraege[stelle].statusGeaendert = Zeitrechnung.jetztAlsZeitstempel()
        planung = p
        sichern()
    }

    func dringlichUmschalten(_ id: String) {
        guard var p = planung, let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
        p.eintraege[stelle].dringend.toggle()
        planung = p
        sichern()
    }

    func vorhabenVerschieben(_ id: String, klasse: String, woche: Int) {
        guard var p = planung, let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
        guard p.eintraege[stelle].klasseId != klasse || p.eintraege[stelle].woche != woche else { return }
        p.eintraege[stelle].klasseId = klasse
        let verfallen = p.eintraege[stelle].wocheWechseln(nach: woche)
        planung = p
        sichern()
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

    // ── Prüfungen ─────────────────────────────────────────────────────────

    /// Nach Termin geordnet, ohne Termin ans Ende; innerhalb desselben Tages
    /// nach Kurs, damit die Reihenfolge feststeht.
    var pruefungsliste: [(vorhaben: Vorhaben, klasse: Klasse)] {
        guard let p = planung else { return [] }
        var nachKurs: [String: Klasse] = [:]
        for klasse in p.klassen { nachKurs[klasse.id] = klasse }
        return p.eintraege
            .filter(\.pruefung)
            .compactMap { eintrag in
                nachKurs[eintrag.klasseId].map { (vorhaben: eintrag, klasse: $0) }
            }
            .sorted { a, b in
                switch (a.vorhaben.pruefungstag, b.vorhaben.pruefungstag) {
                case let (x?, y?) where x != y: x < y
                case (nil, _?): false
                case (_?, nil): true
                default: (a.klasse.name, a.vorhaben.anzeigeTitel)
                    < (b.klasse.name, b.vorhaben.anzeigeTitel)
                }
            }
    }

    // ── Heute ─────────────────────────────────────────────────────────────

    /// Was heute ansteht — bei jedem Abruf frisch gerechnet: Der Haken im
    /// Dialog ändert die Planung, eine gehaltene Kopie zeigte den alten Stand.
    var tagesliste: Tagesliste { planung?.tagesliste() ?? Tagesliste() }

    // ── Sperrzeiträume ────────────────────────────────────────────────────

    /// Die eine Stelle, an der die Frage beantwortet wird: Der Dialog fragt sie,
    /// bevor er ein Datum annimmt, das Sichern noch einmal.
    func sperre(am tag: Tag, fuer klasseId: String) -> Sperrzeitraum? {
        planung?.sperre(am: tag, fuer: klasseId)
    }

    /// Entsteht, wenn ein Sperrzeitraum **nachträglich** über einen Termin
    /// gelegt wird. Bestehende Eintragungen bleiben stehen.
    var gesperrteTermine: [(vorhaben: Vorhaben, sperre: Sperrzeitraum)] {
        guard let p = planung else { return [] }
        return p.eintraege.compactMap { eintrag in
            guard eintrag.pruefung, let tag = eintrag.pruefungstag,
                  let sperre = p.sperre(am: tag, fuer: eintrag.klasseId) else { return nil }
            return (eintrag, sperre)
        }
    }

    func sperrzeitHinzufuegen() -> String? {
        guard var p = planung else { return nil }
        let letzte = p.sperrzeiten.map(\.bis).max()
        let montag = (letzte?.plus(tage: 7) ?? p.start).montagDerWoche
        let neu = Sperrzeitraum(id: Kennung.neu("s"), name: "Sperrzeitraum",
                                von: montag, bis: montag.plus(tage: 4))
        p.sperrzeiten.append(neu)
        planung = p
        sichern()
        meldeGesperrteTermine()
        return neu.id
    }

    /// Nur den Namen — wie bei den Ferien (siehe `ferienNamenSetzen`).
    func sperrzeitNamenSetzen(id: String, name: String) {
        guard var p = planung, let stelle = p.sperrzeiten.firstIndex(where: { $0.id == id })
        else { return }
        let gekappt = Planungsspeicher.aufNamenslaenge(name)
        guard p.sperrzeiten[stelle].name != gekappt else { return }
        p.sperrzeiten[stelle].name = gekappt
        planung = p
        sichern()
        if gekappt != name { kuerzungMelden("Die Bezeichnung des Sperrzeitraums") }
    }

    func sperrzeitAendern(_ zeitraum: Sperrzeitraum) {
        guard var p = planung,
              let stelle = p.sperrzeiten.firstIndex(where: { $0.id == zeitraum.id }) else { return }
        p.sperrzeiten[stelle] = zeitraum
        planung = p
        sichern()
        meldeGesperrteTermine()
    }

    /// Leere Liste heißt: für alle. Die Reihenfolge folgt der Kursliste, nicht
    /// der des Anklickens.
    func sperrzeitKurseSetzen(id: String, kurse: Set<String>) {
        guard var p = planung, let stelle = p.sperrzeiten.firstIndex(where: { $0.id == id })
        else { return }
        let geordnet = p.klassen.map(\.id).filter(kurse.contains)
        guard p.sperrzeiten[stelle].kurse != geordnet else { return }
        p.sperrzeiten[stelle].kurse = geordnet
        planung = p
        sichern()
        meldeGesperrteTermine()
    }

    func sperrzeitEntfernen(_ id: String) {
        guard var p = planung else { return }
        p.sperrzeiten.removeAll { $0.id == id }
        planung = p
        sichern()
    }

    private func meldeGesperrteTermine() {
        let betroffen = gesperrteTermine
        guard !betroffen.isEmpty else { return }
        melden(betroffen.count == 1
               ? "Eine bereits eingetragene Prüfung liegt jetzt in einem Sperrzeitraum — "
                 + "sie steht in der Übersicht mit Hinweis."
               : "\(betroffen.count) bereits eingetragene Prüfungen liegen jetzt in einem "
                 + "Sperrzeitraum — sie stehen in der Übersicht mit Hinweis.", .warnung)
    }

    func zeigeVorhaben(_ id: String) {
        guard let p = planung, let eintrag = p.eintraege.first(where: { $0.id == id }) else { return }
        alleDialogeSchliessen()
        anwaehlen(vorhaben: id)
        sprung = Rastersprung(woche: eintrag.woche)
    }

    func pruefungUmschalten(_ id: String) {
        guard var p = planung, let stelle = p.eintraege.firstIndex(where: { $0.id == id }) else { return }
        let an = !p.eintraege[stelle].pruefung
        p.eintraege[stelle].pruefung = an
        // Beim Ausschalten den Termin mitnehmen — sonst käme er beim erneuten Einschalten wieder.
        var hinweis: String?
        if an {
            let vorschlag = p.start.montagDerWoche.plus(tage: p.eintraege[stelle].woche * 7)
            if let gesperrt = p.sperre(am: vorschlag, fuer: p.eintraege[stelle].klasseId) {
                p.eintraege[stelle].pruefungstag = nil
                hinweis = gesperrt.abweisung + " Die Prüfung ist ohne Termin eingetragen."
            } else {
                p.eintraege[stelle].pruefungstag = vorschlag
            }
        } else {
            p.eintraege[stelle].pruefungstag = nil
        }
        planung = p
        sichern()
        if let hinweis { melden(hinweis, .warnung) }
    }

    // ── Auswählen, kopieren, verschieben ──────────────────────────────────

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
    private func auswahlNachfuehren() {
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

    func vorhabenSichern(_ entwurf: VorhabenEntwurf) {
        guard var p = planung else { return }
        let titel = bereinigt(entwurf.titel, auf: Planungsdatei.maxNamenslaenge,
                              feld: "Der Titel")
        let text = bereinigt(entwurf.text, auf: Planungsdatei.maxTextlaenge,
                             feld: "Die Beschreibung")
        let kommentar = bereinigt(entwurf.kommentar, auf: Planungsdatei.maxTextlaenge,
                                  feld: "Der Kommentar")
        // Den Überhang weisen `materialAufnehmen` und `linksAufnehmen` schon mit
        // Meldung ab; hier steht nur noch die Schranke vor der Datei.
        var langeNamen = 0
        func benennung(_ wert: String) -> String {
            guard wert.count > Planungsdatei.maxNamenslaenge else { return wert }
            langeNamen += 1
            return String(wert.prefix(Planungsdatei.maxNamenslaenge))
        }
        let materialien = entwurf.materialien.prefix(Planungsdatei.maxMaterialien)
            .map { Material(id: $0.id, titel: benennung($0.titel), pfad: $0.pfad) }
        let links = entwurf.gereinigteLinks().prefix(Planungsdatei.maxLinks)
            .map { Weblink(id: $0.id, titel: benennung($0.titel), adresse: $0.adresse) }
        if langeNamen > 0 {
            melden("Bezeichnungen von Materialien und Links sind auf "
                   + "\(Planungsdatei.maxNamenslaenge) Zeichen begrenzt — \(langeNamen) "
                   + "\(langeNamen == 1 ? "wurde" : "wurden") gekürzt.", .warnung)
        }
        var verfallen = false
        if let id = entwurf.vorhabenId, let stelle = p.eintraege.firstIndex(where: { $0.id == id }) {
            let vorher = p.eintraege[stelle]
            p.eintraege[stelle].titel = titel
            p.eintraege[stelle].text = text
            p.eintraege[stelle].klasseId = entwurf.klasseId
            p.eintraege[stelle].woche = entwurf.woche
            p.eintraege[stelle].erledigt = entwurf.erledigt
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
            p.eintraege[stelle].kommentar = kommentar
            // Diese beiden Felder teilt sich die App mit der iPad-Ansicht; der Stempel entscheidet.
            if vorher.kommentar != kommentar || vorher.erledigt != entwurf.erledigt {
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
                kommentar: kommentar, statusGeaendert: stempel))
        }
        planung = p
        sichern()
        vorhabenDialog = nil
        if verfallen { melden(Planungsspeicher.zurueckgesetzt(1)) }
    }

    /// Kappt eine Bezeichnung auf die Grenze, die `Planungsdatei` beim Lesen
    /// anlegt. Ohne Trimmen: Die Felder schreiben entprellt schon beim Tippen,
    /// ein weggenommenes Leerzeichen stünde gegen das, was im Feld steht.
    private static func aufNamenslaenge(_ wert: String) -> String {
        wert.count > Planungsdatei.maxNamenslaenge
            ? String(wert.prefix(Planungsdatei.maxNamenslaenge)) : wert
    }

    /// Erst **nach** dem Schreiben zu melden: Die entprellten Felder liefern
    /// den überlangen Wert bei jedem weiteren Tastendruck erneut, und erst der
    /// Vergleich mit dem schon gekappten Stand fängt die Wiederholung ab.
    private func kuerzungMelden(_ feld: String) {
        melden("\(feld) war länger als \(Planungsdatei.maxNamenslaenge) Zeichen "
               + "und wurde gekürzt.", .warnung)
    }

    /// Trimmt und kappt auf die Grenze, die `Planungsdatei` beim Lesen anlegt —
    /// sonst verschwände der Überhang beim nächsten Start ohne jede Meldung.
    private func bereinigt(_ wert: String, auf grenze: Int, feld: String) -> String {
        let sauber = wert.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sauber.count > grenze else { return sauber }
        melden("\(feld) war länger als \(grenze) Zeichen und wurde gekürzt.", .warnung)
        return String(sauber.prefix(grenze))
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
            guard let self, var p = planung else { return }
            // Vorher merken: Das Zuweisen der Planung führt die Auswahl nach.
            let warAngewaehlt = auswahl.contains(id)
            p.eintraege.removeAll { $0.id == id }
            planung = p
            sichern()
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

    func imFinderZeigen(_ pfad: String) {
        switch Systemzugriff.imFinderZeigen(vollerPfad(pfad)) {
        case .erledigt: break
        case .fehlt(let text), .abgewiesen(let text): melden(text, .warnung)
        }
    }

    func dateiOeffnen(_ pfad: String) {
        switch Systemzugriff.dateiOeffnen(vollerPfad(pfad)) {
        case .erledigt:
            break
        case .fehlt(let text):
            melden(text, .warnung)
        case .abgewiesen(let text):
            melden(text, .warnung)
            _ = Systemzugriff.imFinderZeigen(vollerPfad(pfad))
        }
    }

    func pfadKopieren(_ pfad: String) {
        melden(Systemzugriff.inZwischenablage(vollerPfad(pfad))
               ? "Pfad in der Zwischenablage — im Finder mit ⇧⌘G einsetzen."
               : "Kopieren nicht möglich.", .hinweis)
    }
}

/// Der Arbeitsstand des Vorhaben-Dialogs. Erst „Übernehmen“ schreibt ihn in die
/// Planung zurück.
struct VorhabenEntwurf: Identifiable, Equatable {
    /// Kennung dieser **Bearbeitung**, nicht die des Vorhabens — damit der
    /// Dialog auch beim zweiten neuen Vorhaben wieder aufgeht.
    let id = UUID()
    /// Kennung des bearbeiteten Vorhabens; nil bei einem neuen.
    let vorhabenId: String?
    var titel: String
    var text: String
    var klasseId: String
    var woche: Int
    var erledigt: Bool
    var materialien: [Material]
    var links: [Weblink]
    var pruefung: Bool
    var pruefungstag: Tag?
    var datum: Tag?
    var dringend: Bool
    var kommentar: String

    private let ausgangsstand: Stand

    private struct Stand: Equatable {
        var titel: String
        var text: String
        var klasseId: String
        var woche: Int
        var erledigt: Bool
        var materialien: [Material]
        var links: [Weblink]
        var pruefung: Bool
        var pruefungstag: Tag?
        var datum: Tag?
        var dringend: Bool
        var kommentar: String
    }

    init(_ vorhaben: Vorhaben) {
        vorhabenId = vorhaben.id
        titel = vorhaben.titel
        text = vorhaben.text
        klasseId = vorhaben.klasseId
        woche = vorhaben.woche
        erledigt = vorhaben.erledigt
        materialien = vorhaben.materialien
        links = vorhaben.links
        pruefung = vorhaben.pruefung
        pruefungstag = vorhaben.pruefungstag
        datum = vorhaben.datum
        dringend = vorhaben.dringend
        kommentar = vorhaben.kommentar
        ausgangsstand = Stand(titel: titel, text: text, klasseId: klasseId, woche: woche,
                              erledigt: erledigt, materialien: materialien, links: links,
                              pruefung: pruefung, pruefungstag: pruefungstag,
                              datum: datum, dringend: dringend, kommentar: kommentar)
    }

    init(klasseId: String, woche: Int) {
        vorhabenId = nil
        titel = ""
        text = ""
        self.klasseId = klasseId
        self.woche = woche
        erledigt = false
        materialien = []
        links = []
        pruefung = false
        pruefungstag = nil
        datum = nil
        dringend = false
        kommentar = ""
        ausgangsstand = Stand(titel: "", text: "", klasseId: klasseId, woche: woche,
                              erledigt: false, materialien: [], links: [],
                              pruefung: false, pruefungstag: nil,
                              datum: nil, dringend: false, kommentar: "")
    }

    var istNeu: Bool { vorhabenId == nil }

    /// Wie `Vorhaben.wochentag`: abgeleitet aus dem Datum, kein eigener Stand.
    var wochentag: Wochentag? { datum?.wochentag }

    /// Escape schließt einen Dialog von Haus aus ohne Rückfrage — eine eben
    /// getippte Beschreibung wäre damit verloren.
    var veraendert: Bool {
        Stand(titel: titel, text: text, klasseId: klasseId, woche: woche,
              erledigt: erledigt, materialien: materialien, links: links,
              pruefung: pruefung, pruefungstag: pruefungstag,
              datum: datum, dringend: dringend, kommentar: kommentar) != ausgangsstand
    }

    var leer: Bool {
        titel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && materialien.isEmpty && links.isEmpty
    }

    /// Leere Zeilen stillschweigend fallen lassen, ungültige Adressen benennen.
    func ungueltigeLinks() -> [String] {
        links.compactMap { link in
            let roh = link.adresse.trimmingCharacters(in: .whitespaces)
            if roh.isEmpty { return nil }
            return Weblinks.pruefen(roh) == nil ? roh : nil
        }
    }

    func gereinigteLinks() -> [Weblink] {
        links.compactMap { link in
            guard let adresse = Weblinks.pruefen(link.adresse) else { return nil }
            let titel = link.titel.trimmingCharacters(in: .whitespaces)
            return Weblink(id: link.id, titel: titel.isEmpty ? Weblinks.name(adresse) : titel,
                           adresse: adresse)
        }
    }
}
