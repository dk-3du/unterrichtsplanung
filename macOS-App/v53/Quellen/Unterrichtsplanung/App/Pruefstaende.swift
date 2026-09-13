// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Die Schranke vor den Prüfständen.
///
/// Ohne `PLANUNGSORDNER` liefe jeder Prüfstand gegen die echte Planung:
/// `--klicktest`, `--messreihe`, `--menuetest`, `--dauertest`, `--ziehtest`,
/// `--sitzplantest` und `--uebergangstest` änderten sie, die lesenden Stände (`--abbild`,
/// `--rolltest`, `--rastermasse`, `--auswahltest`, `--mischtest`,
/// `--titeltest`, `--entsperrtest`, `--tourtest`) bildeten sie ungefragt ab. Darum stehen alle
/// hinter derselben Schranke.
@MainActor
enum Pruefstandsschranke {
    static func eigenerOrdnerVerlangt(_ name: String) -> Bool {
        guard Ablage.istPruefstand else {
            print("\(name) abgebrochen: PLANUNGSORDNER ist nicht gesetzt. Prüfstände "
                  + "laufen nur gegen eine eigene Ablage, nie gegen die echte Planung.")
            NSApp.terminate(nil)
            return false
        }
        // Im Sandbox erreicht der Prüfstand nur seinen Container — `starten()`
        // hat nichts geladen und kein Blatt geöffnet, das Beenden geht durch.
        guard Ablage.pruefordnerZulaessig else {
            print("\(name) abgebrochen: PLANUNGSORDNER liegt außerhalb des Containers. Im "
                  + "Sandbox arbeitet ein Prüfstand nur unterhalb von "
                  + "\(Ablage.container?.path ?? "—") — etwa in dessen tmp/; "
                  + "`Unterrichtsplanung --container` nennt den Pfad.")
            NSApp.terminate(nil)
            return false
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
        case sitzplantest
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
                ("--sitzplantest", .sitzplantest),
            ]
            for (flagge, auftrag) in weitere where argumente.contains(flagge) { return auftrag }
            return nil
        }
    }

    /// Der eine Aufruf aus `applicationDidFinishLaunching`.
    static func starten(_ speicher: Planungsspeicher,
                        argumente: [String] = ProcessInfo.processInfo.arguments) {
        guard let auftrag = Auftrag.lesen(argumente) else { return }
        guard Pruefstandsschranke.eigenerOrdnerVerlangt(auftrag.name) else { return }
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
