// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Die Schranke vor den Prüfständen.
///
/// Ohne `PLANUNGSORDNER` liefe jeder Prüfstand gegen die echte Planung:
/// `--klicktest`, `--messreihe`, `--menuetest`, `--dauertest`, `--ziehtest`,
/// `--sitzplantest`, `--uebergangstest`, `--dialogtest` und `--erststarttest` änderten sie, die lesenden Stände (`--abbild`,
/// `--rolltest`, `--rastermasse`, `--auswahltest`, `--mischtest`,
/// `--titeltest`, `--entsperrtest`, `--tourtest`) bildeten sie ungefragt ab. Darum stehen alle
/// hinter derselben Schranke.
///
/// Eine Ausnahme, und nur eine (E78): `--erststarttest` in einem **Probepaket**.
/// Dort ist der voreingestellte Ablageort der Container der Probe — genau der
/// Weg, den eine frisch eingerichtete App geht und den ein gesetzter
/// `PLANUNGSORDNER` nie berührt. An der echten Kennung bleibt die Schranke zu.
/// Was auch dieser Weg nicht deckt, steht bei `Erststartprobe`: Das Probepaket
/// ist nicht die ausgelieferte App.
@MainActor
enum Pruefstandsschranke {

    /// Die Kennung eines Probepakets endet so; das echte Paket nie.
    static let probenachsatz = ".probe"

    /// Abgewiesen: drucken, ausspülen, gehen.
    ///
    /// Nicht `NSApp.terminate`: In einem leeren Ordner geht gleich nach dem
    /// Start das Blatt „Neue Planung“ auf, und ein angeheftetes Blatt weist das
    /// Beenden ab — der abgewiesene Lauf bliebe mit offenem Fenster stehen, und
    /// seine Meldung versackt im Puffer, wenn die Ausgabe in eine Datei geht
    /// (beides am 14.09.2026 nachgemessen). Ein Lauf, der gar nicht erst
    /// anfängt, hat nichts zu sichern.
    private static func abweisen(_ text: String) -> Never {
        print(text)
        fflush(stdout)
        exit(2)
    }

    /// Darf dieser Prüfstand ohne eigenen Ordner laufen? Die Regel ohne ihre
    /// drei Quellen, damit sie prüfbar ist.
    ///
    /// **Die Kennung allein genügt nicht.** Ohne App Sandbox zeigt der
    /// voreingestellte Ort nicht in einen Container, sondern auf
    /// `~/Library/Application Support/Unterrichtsplanung` — den Ablageort der
    /// Fassungen vor v37. Ein Probepaket, dessen Berechtigungen beim Umsignieren
    /// verlorengingen, schriebe also in das Benutzerverzeichnis (am 14.09.2026
    /// genau so passiert). Also wird der Container verlangt, nicht vermutet.
    static func ohneEigenenOrdnerZulaessig(_ auftrag: Pruefstaende.Auftrag,
                                           kennung: String?, imContainer: Bool) -> Bool {
        guard case .erststarttest = auftrag, imContainer else { return false }
        return kennung?.hasSuffix(probenachsatz) ?? false
    }

    static func eigenerOrdnerVerlangt(_ auftrag: Pruefstaende.Auftrag) -> Bool {
        let name = auftrag.name
        guard Ablage.istPruefstand else {
            guard ohneEigenenOrdnerZulaessig(auftrag, kennung: Bundle.main.bundleIdentifier,
                                             imContainer: Ablage.container != nil) else {
                abweisen("\(name) abgebrochen: PLANUNGSORDNER ist nicht gesetzt. Prüfstände "
                         + "laufen nur gegen eine eigene Ablage, nie gegen die echte Planung. "
                         + "Ohne Ordner läuft allein --erststarttest, und nur in einem "
                         + "Probepaket im Sandbox (Kennung auf \(probenachsatz), Container "
                         + "vorhanden) — hier: Kennung \(Bundle.main.bundleIdentifier ?? "—"), "
                         + "Container \(Ablage.container?.path ?? "keiner").")
            }
            print("\(name): ohne PLANUNGSORDNER im Probepaket "
                  + "\(Bundle.main.bundleIdentifier ?? "—") — der Lauf geht an den "
                  + "voreingestellten Ort im Container der Probe (E78).")
            return true
        }
        // Im Sandbox erreicht der Prüfstand nur seinen Container — `starten()`
        // hat nichts geladen und kein Blatt geöffnet, das Beenden geht durch.
        guard Ablage.pruefordnerZulaessig else {
            abweisen("\(name) abgebrochen: PLANUNGSORDNER liegt außerhalb des Containers. Im "
                     + "Sandbox arbeitet ein Prüfstand nur unterhalb von "
                     + "\(Ablage.container?.path ?? "—") — etwa in dessen tmp/; "
                     + "`Unterrichtsplanung --container` nennt den Pfad.")
        }
        return true
    }
}

/// Die Prüfstände am gebauten Paket — ein Aufruf, ein Prüfstand je Lauf.
///
/// Sie laufen gegen den echten, signierten Bau, ohne Compile-Out: Nur so kam
/// heraus, was das Prüfziel von `swift test` nicht zeigt (Sandbox, Blätter,
/// Menüs, Enklave). Der Verteiler liest die Argumente einmal, prüft die
/// Schranke einmal und ruft genau einen Prüfstand; der Beipackzettel nennt
/// sie weiterhin nicht.
@MainActor
enum Pruefstaende {

    /// Was ein Aufruf verlangt — genau eines.
    enum Auftrag: Equatable {
        case abbild(URL)
        case rolltest, klicktest, auswahltest, mischtest, ziehtest, titeltest, menuetest
        case entsperrtest(String)
        case tourtest, updatetest, ordnertest, messreihe, rastermasse, dauertest
        case sitzplantest, erststarttest, widerruftest, dialogtest
        case uebergangstest(String)

        /// Der Name vor der Schranke und in der Ausgabe.
        var name: String {
            switch self {
            case .abbild: "ABBILD"
            case .rolltest: "ROLLTEST"
            case .klicktest: "KLICKTEST"
            case .auswahltest: "AUSWAHLTEST"
            case .mischtest: "MISCHTEST"
            case .ziehtest: "ZIEHTEST"
            case .titeltest: "TITELTEST"
            case .menuetest: "MENUETEST"
            case .entsperrtest: "ENTSPERRTEST"
            case .tourtest: "TOURTEST"
            case .updatetest: "UPDATETEST"
            case .ordnertest: "ORDNERTEST"
            case .messreihe: "MESSREIHE"
            case .rastermasse: "RASTERMASSE"
            case .dauertest: "DAUERTEST"
            case .sitzplantest: "SITZPLANTEST"
            case .erststarttest: "ERSTSTARTTEST"
            case .widerruftest: "WIDERRUFTEST"
            case .dialogtest: "DIALOGTEST"
            case .uebergangstest: "UEBERGANGSTEST"
            }
        }

        /// Aus den Argumenten, in fester Reihenfolge — der erste Treffer zählt.
        /// `--mischtest` geht `--abbild` vor: Er legt sein Bild selbst ab
        /// (`MISCHBILD`); ein Abbild nebenher störte ihn nur. `--abbild` ohne
        /// Ziel und `--entsperrtest` ohne Weg: kein Abbild, Weg `passphrase`;
        /// `--uebergangstest` ohne Art: `pruefen` (der zweite Start).
        static func lesen(_ argumente: [String]) -> Auftrag? {
            func wert(nach flagge: String) -> String? {
                guard let stelle = argumente.firstIndex(of: flagge), stelle + 1 < argumente.count
                else { return nil }
                return argumente[stelle + 1]
            }
            if argumente.contains("--mischtest") { return .mischtest }
            if argumente.contains("--abbild") {
                return wert(nach: "--abbild").map { .abbild(URL(fileURLWithPath: $0)) }
            }
            let einfache: [(String, Auftrag)] = [
                ("--rolltest", .rolltest), ("--klicktest", .klicktest), ("--auswahltest", .auswahltest),
                ("--ziehtest", .ziehtest), ("--titeltest", .titeltest), ("--menuetest", .menuetest),
            ]
            for (flagge, auftrag) in einfache where argumente.contains(flagge) { return auftrag }
            if argumente.contains("--entsperrtest") {
                return .entsperrtest(wert(nach: "--entsperrtest") ?? "passphrase")
            }
            if argumente.contains("--uebergangstest") {
                return .uebergangstest(wert(nach: "--uebergangstest") ?? "pruefen")
            }
            let weitere: [(String, Auftrag)] = [
                ("--tourtest", .tourtest), ("--updatetest", .updatetest), ("--ordnertest", .ordnertest),
                ("--messreihe", .messreihe), ("--rastermasse", .rastermasse), ("--dauertest", .dauertest),
                ("--sitzplantest", .sitzplantest), ("--erststarttest", .erststarttest),
                ("--widerruftest", .widerruftest), ("--dialogtest", .dialogtest),
            ]
            for (flagge, auftrag) in weitere where argumente.contains(flagge) { return auftrag }
            return nil
        }
    }

    /// Welches Paket läuft — die erste Zeile jedes Prüfstands (E128, v63).
    ///
    /// Die Prüfstände laufen an einer Probe-Kopie des signierten Pakets; bis
    /// v62 hielt nur das Rezept fest, *welches*. Jetzt sagt es der Lauf selbst,
    /// aus der Info.plist des laufenden Bündels: Kennung, Fassung, Quellenstand
    /// und Werkzeugstand (beide von `bauen.sh` mitsigniert; die Probe-Kopie
    /// ändert nur die Kennung). So steht im Protokoll der Runde und im
    /// Releasebericht, welches Paket die Rauchtests bekam (N61-01). Der
    /// Entwicklungsbau aus `swift run` hat keine Plist mit Kennung — er heißt so.
    /// Seit v66 steht sie auch vor der Schranke (E144): Jeder Lauf, der einen
    /// Prüfstand nennt, beginnt mit ihr — auch der abgewiesene.
    static func paketzeile(_ angaben: [String: Any]?) -> String {
        guard let angaben, let kennung = angaben["CFBundleIdentifier"] as? String else {
            return "Paket: kein Bündel (Entwicklungsbau)"
        }
        func kurz(_ schluessel: String) -> String {
            guard let wert = angaben[schluessel] as? String, !wert.isEmpty else { return "fehlt" }
            return wert.count > 12 ? String(wert.prefix(12)) + "…" : wert
        }
        let fassung = angaben["CFBundleShortVersionString"] as? String ?? "?"
        let stufe = angaben["CFBundleVersion"] as? String ?? "?"
        return "Paket: \(kennung) \(fassung) (\(stufe)), Quellenstand \(kurz("UPQuellenstand")), "
            + "Werkzeugstand \(kurz("UPWerkzeugstand"))"
    }

    /// Der Auftrag dieses Laufs — gesetzt in `starten`, gelesen beim Beenden.
    static var laufender: Auftrag?

    /// Die letzte Zeile eines regulär beendeten Prüfstands (N67-01, v68).
    ///
    /// Die Paketzeile steht *vor* dem Prüfstand und beweist den Start; bis v67
    /// bewies nichts das Ende — ein Prüfstand, der nach ihr still mit Rückgabe 0
    /// endete, galt dem Rundentreiber als bestanden. Jetzt druckt der Delegat
    /// beim regulären Beenden (`applicationWillTerminate`) diese Zeile, und
    /// `runde.py` verlangt sie. Ein gewollter Abbruch (`exit(3)` im Dienst) und
    /// die Schranke (`exit(2)`) kommen nicht hierher — so soll es sein: Dort
    /// beweist die Zeile des Dienstes, dass der Abbruch an der Stelle geschah.
    static func endezeile(_ auftrag: Auftrag) -> String { "ENDE \(auftrag.name)" }

    /// Vom Delegaten beim Beenden gerufen — druckt die Ende-Zeile, wenn ein
    /// Prüfstand lief; im Betrieb ohne Prüfstand nichts.
    static func beendet() {
        guard let laufender else { return }
        print(endezeile(laufender))
        fflush(stdout)
    }

    /// Der eine Aufruf aus `applicationDidFinishLaunching`.
    static func starten(_ speicher: Planungsspeicher,
                        argumente: [String] = ProcessInfo.processInfo.arguments) {
        guard let auftrag = Auftrag.lesen(argumente) else { return }
        laufender = auftrag
        // Zuerst das Paket, dann die Schranke, dann der Prüfstand — sofort
        // ausgespült, damit auch ein Absturz oder eine Abweisung die Zeile
        // stehen lässt (E128: die *erste* Zeile; bis v65 sprach im Erststart
        // ohne PLANUNGSORDNER die Schranke davor, E144).
        print(paketzeile(Bundle.main.infoDictionary))
        fflush(stdout)
        guard Pruefstandsschranke.eigenerOrdnerVerlangt(auftrag) else { return }
        // Abbilder außerhalb des Containers wandern in den Prüfordner.
        Selbstabbild.pruefordner = speicher.sicherung.ablage.ordner
        switch auftrag {
        case .abbild(let ziel): Selbstabbild.ablegenUndBeenden(speicher, ziel: ziel)
        case .rolltest: Klickproben.rolltestUndBeenden(zerlegen: argumente.contains("--zerlegen"))
        case .klicktest: Klickproben.klicktestUndBeenden(speicher)
        case .auswahltest: Klickproben.auswahltestUndBeenden(speicher)
        case .mischtest: Klickproben.mischtestUndBeenden(speicher)
        case .ziehtest: Klickproben.ziehtestUndBeenden(speicher)
        case .titeltest: Klickproben.titeltestUndBeenden(speicher)
        case .menuetest: Klickproben.menuetestUndBeenden(speicher)
        case .entsperrtest(let weg): Entsperrprobe.laufenUndBeenden(speicher, weg: weg)
        case .tourtest: Tourprobe.laufenUndBeenden(speicher)
        case .updatetest: Updateprobe.laufenUndBeenden(speicher)
        case .ordnertest: Ordnerprobe.laufenUndBeenden(speicher)
        case .messreihe: Messreihe.laufenUndBeenden(speicher)
        case .rastermasse: Messreihe.masseUndBeenden()
        case .dauertest: Dauerprobe.laufenUndBeenden(speicher)
        case .sitzplantest: Sitzplanprobe.laufenUndBeenden(speicher)
        case .erststarttest: Erststartprobe.laufenUndBeenden(speicher)
        case .widerruftest: Widerrufprobe.laufenUndBeenden(speicher)
        case .dialogtest: Dialogprobe.laufenUndBeenden(speicher)
        case .uebergangstest(let art): Uebergangsprobe.laufenUndBeenden(speicher, art: art)
        }
    }

    /// Ein angeheftetes Blatt lässt AppKit `terminate` abweisen, noch bevor
    /// der Delegat gefragt wird. Ohne diese Stelle bliebe der Prüfstand nach
    /// `--dialog …` mit fertigen Abbildern stehen. Also erst die
    /// Blätter schließen, das Ablösen abwarten, dann gehen.
    static func blaetterSchliessenUndBeenden(_ speicher: Planungsspeicher) async {
        // Ein vorgegebenes Release käme mit dem Schließen als Blatt wieder und
        // hielte AppKit am Beenden fest — erst beantworten, dann schließen.
        // Dasselbe gilt für die Nachwahl: „Später“ hält sie für die Sitzung fern.
        speicher.updateSpaeter()
        speicher.nachwahlSpaeter()
        speicher.alleDialogeSchliessen()
        await Planungsspeicher.blaetterAbloesenAbwarten()
        NSApp.terminate(nil)
    }
}
