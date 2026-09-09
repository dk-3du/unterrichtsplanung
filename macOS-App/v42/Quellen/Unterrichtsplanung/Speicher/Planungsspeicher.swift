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
    /// Ein neueres Release — und die einmalige Frage nach der Prüfung für
    /// Planungen, die es vor dieser Frage schon gab.
    case update, updateNachfrage
    /// Die Nachwahl im Sandbox: bisher genutzte Ordner einmal neu wählen.
    case nachwahl
    var id: String { rawValue }
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
            // Ableitungen, damit die Hauptansicht nicht `planung` liest: Sie würde
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

    /// Leer heißt: noch keiner gewählt.
    var autoexportOrdner: String {
        get { sicherung.kopieOrdner }
        set { sicherung.kopieOrdner = newValue }
    }

    var letzterAutoexport: Date? { sicherung.letzteKopie }

    // ── Verschlüsselung — geschrieben in Planungsspeicher+Verschluesselung.swift ───

    /// Eine Datei von außen unter fremdem Schlüssel wartet auf ihre Freigabe —
    /// neben der Sitzung: Die Ablage bleibt dabei offen. Die Freigabe der
    /// Ablage selbst steckt in `sitzung` (`.gesperrt`).
    var dateiEntsperrung: Entsperrung?

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

    /// Wird erst nach dem bestätigten Wiederherstellungsblatt zum Tresor der Ablage.
    var vorbereitung: Tresor?

    var nachEinrichtung: (@MainActor () -> Void)?

    var freigabegriff: Freigabegriff?

    /// Das Blatt hat abgebrochen, während die Abfrage stand: Ihr Ende darf
    /// dann kein Blatt mehr öffnen.
    var freigabeStillAbgebrochen = false

    /// Zählt jedes neue Entsperrungsziel und jeden Abbruch: Ein Ergebnis der
    /// Schlüsselableitung, dessen Ziel inzwischen gewechselt hat, wird verworfen.
    var entsperrungsgeneration = 0

    /// Einrichten, Passphrase ändern oder Erneuern rechnet gerade abseits des
    /// Hauptstrangs (PBKDF2, Wicklungen); die Blätter sperren derweil ihre
    /// Knöpfe und nehmen keine zweite Eingabe an.
    var schluesselarbeitLaeuft = false

    /// Zählt jedes Verwerfen (Abbrechen, Blatt zu): Ein Ergebnis der
    /// Schlüsselarbeit, dessen Anlass inzwischen dahin ist, wird verworfen.
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

    // ── Tour durch die Oberfläche — geschrieben in Planungsspeicher+Tour.swift ───

    var tourSchritt: Tourschritt?

    /// Die Beispielzelle („G6a, KW 33“) — vom Raster gesetzt, für den Kartentext.
    var tourZelle = ""

    /// Nach dem Anlegen einer Planung vorgemerkt; gefragt wird, sobald kein
    /// Blatt mehr offen ist (Ersteinrichtung zuerst).
    var tourAnbieten = false

    var tourAngebotenInSitzung = false

    // ── Titel und Einstellungen — geschrieben in Planungsspeicher+Bearbeiten.swift ───

    var titelentwurf: String?

    let titelentpreller = Entpreller()

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

    /// Einwilligung, Frist und Angebot der Prüfung auf Updates.
    let updates: Updatekoordinator

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
        sicherung = Sicherungsdienst(ablage: ablage, vorschau: vorschau, pruefstand: Ablage.istPruefstand)
        updates = Updatekoordinator(pruefstand: Ablage.istPruefstand)
        // `didSet` läuft für die Zuweisung im Aufbau nicht — hier selbst rasten.
        let gespeicherteBreite = UserDefaults.standard.double(forKey: Einstellungen.Schluessel.spaltenbreite)
        spaltenbreite = gespeicherteBreite > 0
            ? Kennwerte.spalteRasten(gespeicherteBreite) : Kennwerte.spalteStandard
        erscheinung = Erscheinung(
            rawValue: UserDefaults.standard.string(forKey: Einstellungen.Schluessel.erscheinung) ?? "") ?? .system

        sicherung.sitzungsquelle = { [weak self] in
            // Offene Feldeingaben zuerst — sonst ginge das zuletzt Getippte verloren.
            Entpreller.allesUebernehmen()
            return self?.sitzung ?? .leer
        }
        // Eine Meldungssenke für alle Dienste: Sie schreiben, der Speicher spricht.
        let senke: @MainActor (String, Meldung.Art) -> Void = { [weak self] text, art in self?.melden(text, art) }
        sicherung.melden = senke
        sicherung.zugriff.melden = senke
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

        switch sicherung.ablage.lesen(hoechstens: Planungsdatei.hoechstgroesse) {
        case .keine:
            offenerDialog = .neuePlanung
        case .unlesbar(let fehler):
            unlesbarenStandBehandeln(fehler)
        case .zuGross(let groesse):
            // Was so groß ist, hat diese App nicht geschrieben: beiseite wie ein
            // beschädigter Stand, mit der Größe im Satz.
            sicherung.ablage.beschaedigtenStandBeiseitelegen(stempel: Zeitrechnung.dateistempel())
            beschaedigtenStandRetten(beschreibung: "mit \(groesse / 1024 / 1024) MB größer als die "
                                     + "Lesegrenze (\(Planungsdatei.hoechstgroesse / 1024 / 1024) MB)")
        case .daten(let gelesen):
            if Tresor.istBehaelter(gelesen) {
                // Verschlüsselt: erst entsperren, dann laden. Der Datenschlüssel
                // kommt aus der Enklave (fragt Touch ID) oder aus der Passphrase.
                entsperrungBeginnen(.ablage(gelesen))
            } else {
                geladenAusKlartext(gelesen)
            }
        }
        // Die Lesezeichen stehen offen, sobald die Ablage es ist: im Klartext
        // jetzt; hinter einer versiegelten Ablage erst nach dem Entsperren —
        // das holt `entsperrt(mit:)` nach.
        if verschluesselungsstand != .gesperrt { lesezeichenNachruesten() }
    }

    /// Nicht überschreiben, was sich nur nicht lesen ließ — und, wenn es geht,
    /// die Fassung davor retten. Derselbe Rettungsweg wie beim unlesbaren
    /// JSON: Ohne ihn legte der Nutzer eine neue Planung an, und deren erstes
    /// Schreiben schöbe planung-vorher.json fort — die letzte gute Fassung
    /// wäre dahin.
    func unlesbarenStandBehandeln(_ fehler: any Error) {
        sicherung.gesperrt = true
        sicherung.startsperre = true
        if let vorige = sicherung.ablage.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse) {
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
        sicherung.lageMelden(geklappt: false)
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
        // `gesicherterStand` bleibt offen, damit `jetztSichern()` die gerettete
        // Fassung hinlegt, sobald der unlesbare Stand beiseiteliegt.
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
        } catch let fehler as Planungsfehler where fehler.art == .neuereFassung {
            // Eine neuere Fassung hat geschrieben: nichts anfassen, nichts
            // beiseitelegen — die Sitzung bleibt zu, bis die App nachgezogen ist.
            sicherung.gesperrt = true
            sitzung = .gesperrt(.ablage(daten), nil)
            zugriff.schliessen()
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
        if let vorige = sicherung.ablage.vorigeFassungLesen(hoechstens: Planungsdatei.hoechstgroesse),
           let klartext = try? sicherung.ablage.entsiegelt(vorige, tresor: tresor),
           let (gerettet, bilanz) = try? Planungsdatei.lesenMitBilanz(klartext) {
            planung = gerettet
            zurLaufendenWoche()
            // Jetzt, solange keine planung.json daneben liegt: Der übernächste
            // Schreibvorgang schöbe die ungekürzte Vorgängerfassung sonst fort.
            sicherung.vorigeFassungMitstempeln()
            // `gesicherterStand` bleibt offen, damit `jetztSichern()` den geretteten
            // Stand als planung.json hinlegt — sonst fände der nächste Start nichts.
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


    // ── Sichern ───────────────────────────────────────────────────────────
    // Geschrieben wird im Sicherungsdienst; hier bekommt die Planung ihren Stempel.

    /// Nach jeder Änderung aufzurufen; schreibt entprellt.
    func sichern() {
        guard planung != nil else { return }
        planung?.geaendert = Zeitrechnung.jetztAlsZeitstempel()
        sicherung.sichern()
    }

    /// Ohne Entprellung — beim Wegschalten und beim Beenden, durchgängig
    /// gleichlaufend.
    func jetztSichern() {
        sicherung.jetztSichern()
    }
}
