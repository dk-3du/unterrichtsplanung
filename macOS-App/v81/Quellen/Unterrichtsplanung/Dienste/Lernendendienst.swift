// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Die Lernendenverwaltung auf der Platte (v80): die Jahresdatei
/// `lernende.json` und das Archiv der Vorjahre `archiv.json` — **beide nur als
/// Behälter unter dem Datenschlüssel der Sitzung, nie im Klartext** (E249).
/// Ohne eingeschaltete Verschlüsselung ist das Modul **aus**; bis zum
/// Entsperren **zu**.
///
/// Nach dem Muster des Sitzplandienstes, mit einem Unterschied: Es gibt keinen
/// Klartext. Liegt Klartext unter einem der Namen, wird er beiseitegelegt
/// (`lernende-unerwartet-<Stempel>.json`) und nie übernommen. Geschrieben wird
/// atomar und zurückgelesen; was sich nicht schreiben lässt, gilt für die
/// Sitzung (`ungesichert` nennt den Grund). Eine Datei, die nicht zu lesen ist,
/// wird beiseitegelegt; eine aus einer neueren Fassung bleibt unangetastet, und
/// das Modul ist **gesperrt**. Was das Lesen mit Verlust bereinigt, wird
/// gemeldet und als `lernende-bereinigt-<Stempel>.json` bewahrt.
///
/// Das Archiv wird nur auf Abruf gelesen und nie im Speicher gehalten; ein
/// Archiv, das sich nicht lesen lässt, bleibt liegen, und nichts geht darüber.
/// Die Übergänge des Schutzes gehen über den Übergabestand (E47): Der Dienst
/// liefert beide Dateien unter dem neuen Schlüssel und schaltet nach der Marke
/// um — entsiegelt wird nie.
@MainActor
@Observable
final class Lernendendienst {

    enum Quelle: Equatable, Sendable {
        /// Die Verschlüsselung ist nicht eingeschaltet — das Modul ist aus (E249).
        case aus
        /// Die Ablage liegt versiegelt, der Schlüssel ist noch zu.
        case zu
        /// Versiegelt unter dem Datenschlüssel, offen.
        case behaelter
        /// Die Datei liegt, wird aber nicht angefasst — bis der nächste Start sie liest.
        case gesperrt(String)
    }

    private(set) var quelle: Quelle = .aus

    /// Die Jahresdatei — `nil`, solange keine angelegt ist; gilt nur, solange `schreibbar`.
    private(set) var bestand: Lernendenbestand?

    /// Die Platte trägt nicht den Stand der Sitzung — der Grund; `nil` heißt gesichert.
    private(set) var ungesichert: String?

    /// Das Original einer verlustbehaftet gelesenen Jahresdatei ist noch nicht
    /// bewahrt — bis die Kopie liegt, geht nichts über die Datei (E46).
    private(set) var ausstehendeKopie: String?

    @ObservationIgnored private let ablage: Ablage
    @ObservationIgnored private let vorschau: Bool
    @ObservationIgnored private var tresor: Tresor?

    /// Die Meldungssenke des Speichers — ein Schreibfehler, einmal je Störung.
    @ObservationIgnored var melden: @MainActor (String, Meldung.Art) -> Void = { _, _ in }
    /// Vor jedem Schreiben gefragt, wie beim Sitzplandienst (E54).
    @ObservationIgnored var schreibsperre: (@MainActor () -> String?)?

    static let hoechstgroesse = Lernendendatei.hoechstgroesse
    static let archivgroesse = Archivdatei.hoechstgroesse

    init(ablage: Ablage, vorschau: Bool = false) {
        self.ablage = ablage
        self.vorschau = vorschau
    }

    var schreibbar: Bool { quelle == .behaelter }

    var sperrgrund: String? {
        if case .gesperrt(let grund) = quelle { grund } else { nil }
    }

    /// Warum gerade nichts zu haben ist — für die Oberfläche.
    var sperrhinweis: String? {
        switch quelle {
        case .behaelter: nil
        case .aus: "Die Lernendenverwaltung ist nur mit eingeschalteter Verschlüsselung verfügbar."
        case .zu: "Die Lernendenverwaltung ist noch versiegelt — bitte zuerst die Planung entsperren."
        case .gesperrt(let grund):
            "Die Lernendenverwaltung ist gerade nicht verfügbar (\(grund.ohneSchlusspunkt)) — die App liest "
                + "sie beim nächsten Start erneut."
        }
    }

    /// Trägt die Jahresdatei etwas, das beim Aufheben verloren ginge (E250)?
    var traegtInhalt: Bool {
        guard let b = bestand else { return false }
        return !(b.lernende.isEmpty && b.lerngruppen.isEmpty && b.anliegen.isEmpty && b.rueckmeldungen.isEmpty
                 && b.erfassung.isEmpty && b.beurteilung.isEmpty)
    }

    // ── Lesen ─────────────────────────────────────────────────────────────

    enum Ladebefund: Equatable, Sendable {
        /// Keine Datei — nichts angelegt.
        case keine
        /// So viele Personen trägt die Jahresdatei.
        case geladen(Int)
        /// Gelesen, aber mit Verlust bereinigt; das Original liegt als `kopie`
        /// daneben — `nil`, wenn die Kopie misslang.
        case bereinigt(Int, Lernendendatei.Bilanz, kopie: String?)
        /// Beschädigt oder fremd versiegelt: beiseitegelegt unter `rettung`.
        case beiseitegelegt(String, rettung: String)
        /// Klartext unter dem Namen: beiseitegelegt, nie übernommen.
        case klartextBeiseitegelegt(rettung: String)
        /// Die Datei liegt und bleibt unangetastet.
        case gesperrt(String)
    }

    private struct Deutung {
        var bestand: Lernendenbestand
        var bilanz: Lernendendatei.Bilanz
        var huelleVeraltet: Bool
    }

    /// Ein Behälter dieser Art unter diesem Schlüssel — sonst ein Fehler mit Grund.
    /// Ohne Zustand, damit das Archiv auch abseits des Hauptstrangs so geöffnet wird.
    nonisolated private static func geoeffnet(_ roh: Data, inhalt: Tresor.Inhalt,
                                              tresor: Tresor) throws -> (Data, Behaelterkopf) {
        let kopf = try Tresor.kopfLesen(roh)
        guard kopf.inhalt == inhalt.rawValue else {
            throw Tresorfehler(art: .beschaedigt, text: "Behälter mit Inhalt „\(kopf.inhalt)“")
        }
        guard tresor.passt(zu: kopf) else {
            throw Tresorfehler(art: .falscherSchluessel, text: "unter einem anderen Schlüssel versiegelt")
        }
        return (try tresor.oeffnen(kopf: kopf), kopf)
    }

    /// Der eine Weg von der Platte zur Jahresdatei — beim Laden und beim Zurücklesen derselbe.
    private func gedeutet(_ roh: Data, tresor: Tresor) throws -> Deutung {
        let (klartext, kopf) = try Lernendendienst.geoeffnet(roh, inhalt: .lernende, tresor: tresor)
        let (bestand, bilanz) = try Lernendendatei.lesenMitBilanz(klartext)
        return Deutung(bestand: bestand, bilanz: bilanz, huelleVeraltet: !tresor.huelleGleich(kopf, ziel: .ablage))
    }

    /// Beim Start neben einer Klartext-Planung (oder ohne Planung): Das Modul
    /// ist aus. Klartext unter dem Namen wird beiseitegelegt; ein Behälter
    /// bleibt unangetastet — ohne Schlüssel ist nichts mit ihm zu tun.
    func laden(stempel: String) -> Ladebefund {
        tresor = nil
        bestand = nil
        ungesichert = nil
        ausstehendeKopie = nil
        quelle = .aus
        guard !vorschau else { return .keine }
        switch ablage.dateiLesen(ablage.lernende, hoechstens: Lernendendienst.hoechstgroesse) {
        case .keine:
            return .keine
        case .daten(let roh):
            switch Tresor.deuten(roh) {
            case .klartext:
                return klartextBeiseitelegen(stempel: stempel)
            case .undeutbar:
                return beiseitelegen(grund: "die Datei lässt sich nicht deuten", fremd: false, stempel: stempel)
            case .behaelter:
                return .gesperrt("Die Lernendendatei liegt versiegelt neben einer Planung im Klartext und bleibt unangetastet")
            }
        case .zuGross, .unlesbar:
            return .gesperrt("Die Lernendendatei lässt sich nicht lesen und bleibt unangetastet")
        }
    }

    /// Nach dem Entsperren: die Jahresdatei unter dem Datenschlüssel öffnen.
    func oeffnen(mit tresor: Tresor, stempel: String) -> Ladebefund {
        self.tresor = tresor
        bestand = nil
        ungesichert = nil
        ausstehendeKopie = nil
        quelle = .behaelter
        guard !vorschau else { return .keine }
        let roh: Data
        switch ablage.dateiLesen(ablage.lernende, hoechstens: Lernendendienst.hoechstgroesse) {
        case .keine:
            return .keine
        case .unlesbar(let fehler):
            return sperren(fehler.localizedDescription)
        case .zuGross(let groesse):
            return beiseitelegen(grund: "ungewöhnlich groß (\(groesse / 1024 / 1024) MB)", fremd: false, stempel: stempel)
        case .daten(let daten):
            roh = daten
        }
        switch Tresor.deuten(roh) {
        case .klartext: return klartextBeiseitelegen(stempel: stempel)
        case .undeutbar: return beiseitelegen(grund: "die Datei lässt sich nicht deuten", fremd: false, stempel: stempel)
        case .behaelter: break
        }
        do {
            let deutung = try gedeutet(roh, tresor: tresor)
            var kopie: String?
            if deutung.bilanz.verlust {
                let name = "lernende-bereinigt-\(stempel).json"
                kopie = ablage.dateiKopieren(ablage.lernende, als: name)
                ausstehendeKopie = kopie == nil ? name : nil
            }
            bestand = deutung.bestand
            // Eine ältere Hülle: still neu schreiben.
            if deutung.huelleVeraltet { ablegen() }
            let anzahl = deutung.bestand.lernende.count
            return deutung.bilanz.verlust ? .bereinigt(anzahl, deutung.bilanz, kopie: kopie) : .geladen(anzahl)
        } catch let fehler as Tresorfehler where fehler.art == .neuereFassung {
            return sperren(fehler.text)
        } catch let fehler as Lernendendatei.Fehler where fehler.art == .neuereFassung {
            return sperren(fehler.text)
        } catch {
            return beiseitelegen(grund: error.localizedDescription,
                                 fremd: (error as? Tresorfehler)?.art == .falscherSchluessel, stempel: stempel)
        }
    }

    private func klartextBeiseitelegen(stempel: String) -> Ladebefund {
        let name = "lernende-unerwartet-\(stempel).json"
        guard ablage.dateiBeiseitelegen(ablage.lernende, als: name) != nil else {
            return sperren("Klartext liegt unter dem Namen der Lernendendatei, und er ließ sich nicht beiseitelegen")
        }
        return .klartextBeiseitegelegt(rettung: name)
    }

    private func beiseitelegen(grund: String, fremd: Bool, stempel: String) -> Ladebefund {
        let name = "lernende-\(fremd ? "fremd" : "beschaedigt")-\(stempel).json"
        guard let rettung = ablage.dateiBeiseitelegen(ablage.lernende, als: name) else {
            return sperren(grund + "; die Rettungskopie ließ sich nicht anlegen")
        }
        bestand = nil
        return .beiseitegelegt(grund, rettung: rettung)
    }

    private func sperren(_ grund: String) -> Ladebefund {
        bestand = nil
        quelle = .gesperrt(grund)
        return .gesperrt(grund)
    }

    /// Die Ablage liegt versiegelt, der Schlüssel ist noch zu.
    func schliessen() {
        quelle = .zu
        tresor = nil
        bestand = nil
        ungesichert = nil
        ausstehendeKopie = nil
    }

    // ── Schreiben ─────────────────────────────────────────────────────────

    /// Erst das Original bewahren (E46).
    private func originalBewahren() throws {
        guard let name = ausstehendeKopie else { return }
        if !FileManager.default.fileExists(atPath: ablage.lernende.path) || ablage.dateiKopieren(ablage.lernende, als: name) != nil {
            ausstehendeKopie = nil
            return
        }
        throw Uebergangsfehler(text: "das Original ist noch nicht bewahrt — die Kopie „\(name)“ ließ sich nicht anlegen")
    }

    /// Die Jahresdatei als Behälter unter `tresor`, im Speicher gebaut und
    /// geprüft — derselbe Weg für das Schreiben und für die Generation.
    private func dateiBauen(_ bestand: Lernendenbestand, unter tresor: Tresor) throws -> Data {
        let klartext = try Lernendendatei.schreiben(bestand)
        guard try Lernendendatei.lesen(klartext) == bestand else {
            throw Uebergangsfehler(text: "die Lernendendatei liest sich anders, als sie geschrieben wurde")
        }
        let daten = try tresor.versiegeln(klartext, inhalt: .lernende, ziel: .ablage)
        guard daten.count <= Lernendendienst.hoechstgroesse else {
            throw Uebergangsfehler(text: "die Lernendendatei wäre mit \(daten.count / 1024 / 1024) MB größer als die Lesegrenze")
        }
        return daten
    }

    /// Bauen, atomar ablegen, über denselben Weg wie das Lesen zurücklesen und vergleichen.
    private func schreiben() -> String? {
        guard !vorschau else { return nil }
        guard let tresor, let bestand else { return "nichts zu schreiben" }
        if let grund = schreibsperre?() { return grund }
        // Was fremd versiegelt liegt, wird nicht überschrieben (E72).
        if let sperre = Ablage.formwaechter(ablage.lernende, tresor: tresor) { return sperre.grund }
        do { try originalBewahren() } catch { return error.localizedDescription }
        do {
            try ablage.dateiSchreiben(try dateiBauen(bestand, unter: tresor), nach: ablage.lernende)
        } catch {
            return error.localizedDescription
        }
        guard case .daten(let roh) = ablage.dateiLesen(ablage.lernende, hoechstens: Lernendendienst.hoechstgroesse) else {
            return "nicht zurücklesbar"
        }
        guard (try? gedeutet(roh, tresor: tresor).bestand) == bestand else {
            return "die Platte trägt einen anderen Stand"
        }
        return nil
    }

    /// Schreiben und den Grund festhalten — gemeldet einmal je Störung.
    private func ablegen() {
        guard schreibbar, bestand != nil else { return }
        if let grund = schreiben() {
            if ungesichert == nil {
                melden("Die Lernendendaten ließen sich nicht sichern (\(grund.ohneSchlusspunkt)) — sie gelten für "
                       + "diese Sitzung; die App versucht es beim nächsten Schreiben und beim Beenden erneut.", .warnung)
            }
            ungesichert = grund
        } else {
            ungesichert = nil
        }
    }

    /// Die Jahresdatei setzen — der ganze Stand, wie ihn ein Blatt beim
    /// „Übernehmen“ reicht. Liefert den Grund, wenn die Platte ihn nicht trägt;
    /// er gilt dann für die Sitzung.
    @discardableResult
    func setzen(_ neu: Lernendenbestand) -> String? {
        guard schreibbar else { return sperrhinweis }
        bestand = neu
        ablegen()
        return ungesichert
    }

    /// Ein Stand, den die Platte nicht trägt, noch einmal — beim Sichern und beim Beenden.
    func nachholen() {
        guard schreibbar, ungesichert != nil else { return }
        ablegen()
    }

    // ── Das Archiv: nur auf Abruf ─────────────────────────────────────────

    enum Archivbefund: Equatable, Sendable {
        case gelesen(Archivbestand, Archivdatei.Bilanz, kopie: String?)
        case nichtLesbar(String)
    }

    /// Das Archiv lesen. Ohne Datei ist es leer. Mit Verlust gelesen, wird das
    /// Original zuerst bewahrt (`archiv-bereinigt-<Stempel>.json`); gelingt
    /// das nicht, gilt das Archiv als nicht lesbar.
    func archivLesen(stempel: String) -> Archivbefund {
        guard schreibbar, let tresor else { return .nichtLesbar(sperrhinweis ?? "gesperrt") }
        guard !vorschau else { return .gelesen(.leer, .init(), kopie: nil) }
        return archivAbschliessen(Lernendendienst.archivEntziffern(ablage, tresor), stempel: stempel)
    }

    /// Dasselbe abseits des Hauptstrangs — fürs Blatt, das ein Archiv von
    /// 64 MB lesen können muss, ohne zu stocken. Gilt der Schlüssel danach
    /// nicht mehr (geschlossen, gewechselt), ist das Ergebnis verworfen.
    func archivLesenAsynchron(stempel: String) async -> Archivbefund {
        guard schreibbar, let tresor else { return .nichtLesbar(sperrhinweis ?? "gesperrt") }
        guard !vorschau else { return .gelesen(.leer, .init(), kopie: nil) }
        let ablage = ablage
        let roh = await Task.detached(priority: .userInitiated) {
            Lernendendienst.archivEntziffern(ablage, tresor)
        }.value
        guard schreibbar, self.tresor === tresor else { return .nichtLesbar(sperrhinweis ?? "der Schlüssel hat gewechselt") }
        return archivAbschliessen(roh, stempel: stempel)
    }

    @ObservationIgnored private var verzeichnisVorrat: (bestand: Lernendenbestand, verzeichnis: Lernendenverzeichnis)?

    /// Das Verzeichnis des jetzigen Stands — neu gebaut, wenn er sich geändert
    /// hat; für die Zeilen des Rasters, die je Neuzeichnen fragen.
    var verzeichnis: Lernendenverzeichnis? {
        guard let bestand else { return nil }
        if let vorrat = verzeichnisVorrat, vorrat.bestand == bestand { return vorrat.verzeichnis }
        let neu = Lernendenverzeichnis(bestand)
        verzeichnisVorrat = (bestand, neu)
        return neu
    }

    /// Die Größe des Archivs auf der Platte — `nil` ohne Datei.
    func archivGroesse() -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: ablage.archiv.path)[.size] as? NSNumber)?.intValue
    }

    /// Was das Lesen fand, bevor der Dienst es übernimmt.
    enum Archivroh: Sendable {
        case keins
        case gelesen(Archivbestand, Archivdatei.Bilanz)
        case nichtLesbar(String)
    }

    /// Lesen und entziffern — ohne Zustand, auf jedem Strang derselbe Weg.
    nonisolated static func archivEntziffern(_ ablage: Ablage, _ tresor: Tresor) -> Archivroh {
        switch ablage.dateiLesen(ablage.archiv, hoechstens: Archivdatei.hoechstgroesse) {
        case .keine:
            return .keins
        case .unlesbar(let fehler):
            return .nichtLesbar(fehler.localizedDescription)
        case .zuGross(let groesse):
            return .nichtLesbar("Das Archiv ist ungewöhnlich groß (\(groesse / 1024 / 1024) MB) und wird nicht gelesen.")
        case .daten(let roh):
            do {
                let (archiv, bilanz) = try Archivdatei.lesenMitBilanz(try archivKlartext(roh, tresor: tresor))
                return .gelesen(archiv, bilanz)
            } catch {
                return .nichtLesbar(error.localizedDescription)
            }
        }
    }

    /// Mit Verlust gelesen: erst das Original bewahren (`archiv-bereinigt-<Stempel>.json`);
    /// gelingt das nicht, gilt das Archiv als nicht lesbar.
    private func archivAbschliessen(_ roh: Archivroh, stempel: String) -> Archivbefund {
        switch roh {
        case .keins:
            return .gelesen(.leer, .init(), kopie: nil)
        case .nichtLesbar(let grund):
            return .nichtLesbar(grund)
        case .gelesen(let archiv, let bilanz):
            var kopie: String?
            if bilanz.verlust {
                kopie = ablage.dateiKopieren(ablage.archiv, als: "archiv-bereinigt-\(stempel).json")
                guard kopie != nil else {
                    return .nichtLesbar("Das Archiv wurde mit Verlust gelesen, und das Original ließ sich nicht bewahren.")
                }
            }
            return .gelesen(archiv, bilanz, kopie: kopie)
        }
    }

    /// Beim Entsperren nur der Kopf des Archivs (B71): Was nicht als Archiv
    /// unter diesem Schlüssel liegt — fremd versiegelt, anderer Inhalt,
    /// Klartext, undeutbar —, wird beiseitegelegt und nie übernommen; sonst
    /// hielte es jeden Übergang des Schutzes auf. Ein Archiv aus einer neueren
    /// Fassung bleibt liegen. Gelesen wird das Archiv erst auf Abruf. Liefert
    /// den Namen der Rettungskopie.
    func archivkopfPruefen(stempel: String) -> String? {
        guard schreibbar, let tresor, !vorschau,
              case .daten(let roh) = ablage.dateiLesen(ablage.archiv, hoechstens: Lernendendienst.archivgroesse) else {
            return nil
        }
        let name: String
        switch Tresor.deuten(roh) {
        case .klartext:
            name = "archiv-unerwartet-\(stempel).json"
        case .undeutbar:
            name = "archiv-beschaedigt-\(stempel).json"
        case .behaelter:
            do {
                let kopf = try Tresor.kopfLesen(roh)
                guard tresor.passt(zu: kopf) else {
                    name = "archiv-fremd-\(stempel).json"
                    break
                }
                guard kopf.inhalt != Tresor.Inhalt.archiv.rawValue else { return nil }
                name = "archiv-beschaedigt-\(stempel).json"
            } catch let fehler as Tresorfehler where fehler.art == .neuereFassung {
                return nil
            } catch {
                name = "archiv-beschaedigt-\(stempel).json"
            }
        }
        return ablage.dateiBeiseitelegen(ablage.archiv, als: name)
    }

    nonisolated private static func archivKlartext(_ roh: Data, tresor: Tresor) throws -> Data {
        guard Tresor.istBehaelter(roh) else {
            throw Tresorfehler(art: .beschaedigt, text: "Das Archiv liegt nicht als Behälter vor.")
        }
        return try geoeffnet(roh, inhalt: .archiv, tresor: tresor).0
    }

    private func archivBauen(_ archiv: Archivbestand, unter tresor: Tresor) throws -> Data {
        let klartext = try Archivdatei.schreiben(archiv)
        guard try Archivdatei.schreiben(try Archivdatei.lesen(klartext)) == klartext else {
            throw Uebergangsfehler(text: "das Archiv liest sich anders, als es geschrieben wurde")
        }
        let daten = try tresor.versiegeln(klartext, inhalt: .archiv, ziel: .ablage)
        guard daten.count <= Lernendendienst.archivgroesse else {
            throw Uebergangsfehler(text: "das Archiv wäre mit \(daten.count / 1024 / 1024) MB größer als die Lesegrenze")
        }
        return daten
    }

    /// Das Archiv setzen — für die Löschungen (E276). Ein Archiv, das sich
    /// nicht lesen lässt, wird nicht überschrieben. Liefert den Grund, wenn
    /// nicht geschrieben wurde.
    @discardableResult
    func archivSetzen(_ archiv: Archivbestand, stempel: String) -> String? {
        guard schreibbar, let tresor else { return sperrhinweis }
        guard !vorschau else { return nil }
        if let grund = schreibsperre?() { return grund }
        if let sperre = Ablage.formwaechter(ablage.archiv, tresor: tresor) { return sperre.grund }
        if FileManager.default.fileExists(atPath: ablage.archiv.path),
           case .nichtLesbar(let grund) = archivLesen(stempel: stempel) {
            return "Das Archiv lässt sich nicht lesen (\(grund.ohneSchlusspunkt)) — es wird nicht überschrieben."
        }
        do {
            try ablage.dateiSchreiben(try archivBauen(archiv, unter: tresor), nach: ablage.archiv)
            guard case .daten(let roh) = ablage.dateiLesen(ablage.archiv, hoechstens: Lernendendienst.archivgroesse),
                  try Archivdatei.schreiben(try Archivdatei.lesen(try Lernendendienst.archivKlartext(roh, tresor: tresor)))
                    == (try Archivdatei.schreiben(archiv)) else {
                return "Das Archiv trägt nach dem Schreiben einen anderen Stand."
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // ── Der Übergang des Schutzes (E47): Inhalt liefern, dann umschalten ──

    /// Die Jahresdatei unter `neu`, im Speicher gebaut und geprüft. `nil`: keine
    /// Jahresdatei — oder beim Aufheben eine, die nichts trägt; sie entfällt.
    /// **Entsiegelt wird nie** (E249, E250): Trägt sie etwas, wirft das
    /// Aufheben. Wirft auch, wenn das Modul zu oder gesperrt ist.
    func inhalt(unter neu: Tresor?) throws -> Data? {
        guard schreibbar else {
            throw Uebergangsfehler(text: quelle == .zu ? "die Lernendenverwaltung ist noch nicht entsperrt"
                                   : (sperrgrund ?? "die Lernendenverwaltung ist aus"))
        }
        guard let bestand else { return nil }
        guard let neu else {
            if traegtInhalt {
                throw Uebergangsfehler(text: "die Lernendenverwaltung ist nicht leer — zuerst exportieren und löschen, dann aufheben")
            }
            return nil
        }
        if !vorschau { try originalBewahren() }
        return try dateiBauen(bestand, unter: neu)
    }

    /// Das Archiv unter `neu` — geöffnet und geprüft, dann neu versiegelt. Ohne
    /// Archiv `nil`; beim Aufheben entfällt ein Archiv ohne Jahre, eines mit
    /// Jahren wird nie entsiegelt. Ein Archiv, das sich nicht lesen lässt, geht
    /// in keine Generation.
    func archivInhalt(unter neu: Tresor?) throws -> Data? {
        guard schreibbar, let tresor else {
            throw Uebergangsfehler(text: sperrhinweis ?? "die Lernendenverwaltung ist nicht offen")
        }
        guard !vorschau else { return nil }
        let roh: Data
        switch ablage.dateiLesen(ablage.archiv, hoechstens: Lernendendienst.archivgroesse) {
        case .keine:
            return nil
        case .unlesbar(let fehler):
            throw Uebergangsfehler(text: "das Archiv ist nicht lesbar (\(fehler.localizedDescription.ohneSchlusspunkt))")
        case .zuGross(let groesse):
            throw Uebergangsfehler(text: "das Archiv ist ungewöhnlich groß (\(groesse / 1024 / 1024) MB)")
        case .daten(let daten):
            roh = daten
        }
        let klartext = try Lernendendienst.archivKlartext(roh, tresor: tresor)
        let archiv = try Archivdatei.lesen(klartext)
        guard let neu else {
            if archiv.jahre.isEmpty { return nil }
            throw Uebergangsfehler(text: "das Archiv der Lernendenverwaltung ist nicht leer — zuerst exportieren und löschen, dann aufheben")
        }
        let daten = try neu.versiegeln(klartext, inhalt: .archiv, ziel: .ablage)
        guard daten.count <= Lernendendienst.archivgroesse else {
            throw Uebergangsfehler(text: "das Archiv wäre mit \(daten.count / 1024 / 1024) MB größer als die Lesegrenze")
        }
        return daten
    }

    // ── Der Schuljahreswechsel (AP5): dieselben Bausteine, derselbe Schlüssel ──

    /// Eine Jahresdatei als Behälter unter dem Schlüssel der Sitzung — für die
    /// Generation des Wechsels. Ein ausstehendes Original wird zuerst bewahrt.
    func jahresdatei(_ neu: Lernendenbestand) throws -> Data {
        guard schreibbar, let tresor else {
            throw Uebergangsfehler(text: sperrhinweis ?? "die Lernendenverwaltung ist nicht offen")
        }
        if !vorschau { try originalBewahren() }
        return try dateiBauen(neu, unter: tresor)
    }

    /// Ein Archiv als Behälter unter dem Schlüssel der Sitzung — für die Generation des Wechsels.
    func archivdatei(_ archiv: Archivbestand) throws -> Data {
        guard schreibbar, let tresor else {
            throw Uebergangsfehler(text: sperrhinweis ?? "die Lernendenverwaltung ist nicht offen")
        }
        return try archivBauen(archiv, unter: tresor)
    }

    /// Nach dem Einsetzen des Wechsels: Die Platte trägt die neue Jahresdatei —
    /// die Sitzung folgt, nichts wird geschrieben.
    func nachJahreswechsel(_ neu: Lernendenbestand) {
        guard schreibbar else { return }
        bestand = neu
        ungesichert = nil
        ausstehendeKopie = nil
    }

    /// Nach dem Einsetzen der Generation: Die Platte trägt beide Dateien unter
    /// `neu` — oder, nach dem Aufheben, keine mehr; dann ist das Modul aus.
    /// Nach dem Einschalten wird es offen, noch ohne Datei. Nichts wird
    /// geschrieben. Zu oder gesperrt bleibt, was es war.
    func umschalten(auf neu: Tresor?) {
        guard schreibbar || (quelle == .aus && neu != nil) else { return }
        ungesichert = nil
        if let neu {
            tresor = neu
            quelle = .behaelter
        } else {
            tresor = nil
            bestand = nil
            ausstehendeKopie = nil
            quelle = .aus
        }
    }
}
