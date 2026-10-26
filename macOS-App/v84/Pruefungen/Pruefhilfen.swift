// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Unterrichtsplanung

/// Warten in Prüfungen (E145, v66): **Signale statt Zeit, wo ein Signal zu
/// haben ist** — `Sicherungsdienst.entprelltJetzt()`, die Fortsetzungen der
/// `Naht`, eine angehaltene `Pruefuhr`. Wo eine echte Nebenarbeit läuft, deren
/// Ende der Prüfling nicht meldet (Schlüsselarbeit, Systemabfrage, verzögerte
/// Meldung), wartet diese eine Hilfe auf die Bedingung — mit einer Zahl von
/// Versuchen als Sicherheitsnetz, die **mit Meldung** scheitert. Bis v65 liefen solche
/// Schleifen still aus, und erst die nächste Erwartung fiel, mit einer Meldung
/// über etwas anderes. Die Frist ist kein Takt; sie bemisst, wann etwas
/// eindeutig nicht mehr kommt (v59: Zeit-Warten kippte im Parallellauf, ohne
/// dass etwas falsch war).
@MainActor
func abwarten(_ was: String, versuche: Int = 600,
              sourceLocation: SourceLocation = #_sourceLocation,
              bis bedingung: @MainActor () -> Bool) async throws {
    // Gezählt werden die eigenen Versuche (je 5 ms Schlaf), nicht die Wanduhr:
    // Im vollen Parallellauf halten andere Suiten den Hauptakteur sekundenlang
    // mit synchronem PBKDF2 fest — eine Wanduhr-Frist liefe dann ab, ehe der
    // Prüfling überhaupt drankam (gemessen 16.09.2026: 5 s Frist, Meldung nach
    // 9 s). Die Versuche dehnen sich mit dem Hauptakteur; 600 Versuche sind
    // drei Sekunden eigener Wartezeit.
    let anfang = ContinuousClock.now
    for _ in 0..<versuche {
        if bedingung() { return }
        try await Task.sleep(for: .milliseconds(5))  // E145: Uhr (Takt) — Takt der Hilfe abwarten(_:bis:), begrenzt durch die Zahl der Versuche
    }
    guard bedingung() else {
        Issue.record("\(versuche) Versuche (\(ContinuousClock.now - anfang) Wanduhr) — nicht eingetreten: \(was)",
                     sourceLocation: sourceLocation)
        throw Fristablauf(was: was)
    }
}

struct Fristablauf: Error { let was: String }

// ── Der Taktschreiber (v84, AT6f-1, E562, E563) ───────────────────────────

/// Der Takt der Prüfungen, der nur mitschreibt: Jede verlangte Dauer steht in `verlangt`, in der Folge der Aufrufe —
/// so sieht eine Prüfung die Standardwerte. Er rückt nie vor. Eine Handlung aus `nach` läuft nur, wenn die Prüfung sie
/// mit `ausloesen()` von Hand auslöst, im Aufruf und ohne Zeit (E563); `warten` kehrt nicht von selbst zurück, sondern
/// endet nur mit einem Abbruch — dem der eigenen Aufgabe oder `abraeumen()` am Ende der Prüfung. Die Aufgabe ist dann
/// abgebrochen wie nach `Task.sleep`: Ein Sichern oder Entpreller dahinter läuft nicht (Z-AT6f-01). `gleich` läuft hier wie
/// im Betrieb von selbst, sobald der Hauptakteur frei ist, und steht nicht in `verlangt`.
@MainActor
final class Taktschreiber: Taktgeber {
    enum Verlangt: Equatable {
        case nach(Double)
        case warten(Duration)
    }

    private(set) var verlangt: [Verlangt] = []
    /// Die Handlungen aus `nach`, noch nicht ausgelöst — in der Folge der Aufrufe.
    private var handlungen: [@MainActor () -> Void] = []
    private var wartende: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var nummer = 0
    private var abgeraeumt = false

    /// Wie viele Handlungen und Wartende offen sind.
    var offen: Int { handlungen.count + wartende.count }

    func nach(_ sekunden: Double, _ handlung: @escaping @MainActor () -> Void) {
        verlangt.append(.nach(sekunden))
        guard !abgeraeumt else { return }
        handlungen.append(handlung)
    }

    /// Löst die älteste offene Handlung aus `nach` aus, im Aufruf; sagt, ob es eine gab. „Älteste“ heißt: in der
    /// Folge der Anmeldung, nicht in der des Betriebs — dort läuft zuerst, was zuerst fällig ist (Z-AT6f1-01). Für
    /// gemischte Fristen ist der Schreiber nicht gedacht; die Folge des Betriebs bringt die Stelluhr (AT6f-2).
    @discardableResult
    func ausloesen() -> Bool {
        guard !handlungen.isEmpty else { return false }
        handlungen.removeFirst()()
        return true
    }

    func warten(_ dauer: Duration) async throws {
        verlangt.append(.warten(dauer))
        nummer += 1
        let meine = nummer
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (weiter: CheckedContinuation<Void, any Error>) in
                    if abgeraeumt || Task.isCancelled {
                        weiter.resume(throwing: CancellationError())
                    } else {
                        wartende[meine] = weiter
                    }
                }
            } onCancel: {
                Task { @MainActor in self.wecken(meine) }
            }
        } catch {
            // Wie nach `Task.sleep`: Wer hier endet, ist abgebrochen — auch nach dem Abräumen.
            withUnsafeCurrentTask { $0?.cancel() }
            throw error
        }
    }

    /// Weckt einen Wartenden mit dem Abbruch — nur, wenn er noch wartet.
    private func wecken(_ nummer: Int) {
        wartende.removeValue(forKey: nummer)?.resume(throwing: CancellationError())
    }

    /// Am Ende jeder Prüfung: Offene Handlungen entfallen, Wartende enden mit dem Abbruch, und was danach noch warten
    /// will, bricht gleich ab — keine Aufgabe bleibt am Schreiber hängen. Wege ohne Abbruchprüfung laufen dabei los wie
    /// im Betrieb nach einem Abbruch: Die Meldung verfällt, die Tour meldet, die Prüfung auf Updates beginnt — im
    /// Prüfstand ohne Netz (Z-AT6f1-04); eine Prüfung liest danach nichts mehr, was davon abhängt.
    func abraeumen() {
        abgeraeumt = true
        handlungen.removeAll()
        for nummer in wartende.keys.sorted() { wecken(nummer) }
    }
}

// ── Die Stelluhr (v84, AT6f-2, E548, E565) ────────────────────────────────

/// Der Takt der Prüfungen, der vorrückt: Zeit vergeht nur in `vorruecken`, nie von selbst. Handlungen (`nach`) und
/// Aufgaben (`aufgabe`, `gleich`) melden sich im Aufruf an, mit ihrer Frist ab `jetzt`. `vorruecken` nimmt Ereignis für Ereignis den
/// frühesten fälligen Eintrag — gleiche Fristen in der Folge der Anmeldung (Z-AT6e-02) —, setzt `jetzt` auf seine Frist,
/// führt eine Handlung im Aufruf aus und lässt eine Aufgabe laufen, bis sie endet: Gewartet wird auf das Ende der Aufgabe,
/// nicht auf Ruhe und nicht auf Durchläufe (E145, E565). Was dabei neu angemeldet wird, zählt ab seiner Frist (Z-AT6f-02).
/// Abgebrochene Aufgaben wartet sie nicht ab — sie laufen gleich, wie nach `Task.sleep`. Eine negative Dauer zählt wie
/// null, wie im Betrieb; `jetzt` fällt nie.
/// Grenzen: Was eine Handlung oder Aufgabe ohne Taktgeber anstößt, wartet die Uhr nicht ab — dafür die Signale des
/// Programms; meldet es danach selbst über den Takt an, zählt seine Frist ab dem `jetzt`, zu dem es läuft, nicht ab der
/// Frist des Auslösers (Z-AT6f2-01). Endet eine Aufgabe nie, hängt `vorruecken`; wer die Sicherungsnaht hält, rückt
/// währenddessen nicht vor.
/// Ein Abbruch durch das Programm wirkt wie bei `Task.sleep`; nach `abraeumen()` ist abgebrochen, was noch wartete.
@MainActor
final class Stelluhr: Taktgeber {
    enum Verlangt: Equatable {
        case nach(Double)
        case aufgabe(Duration)
        case gleich
    }

    /// Die Zeit seit dem Anlegen der Uhr — ganzzahlig, damit eine Grenze nicht an der Aufteilung der Schritte hängt.
    private(set) var jetzt: Duration = .zero
    private(set) var verlangt: [Verlangt] = []

    /// Hinter dem Tor wartet eine Aufgabe, bis die Uhr es öffnet — oder ihr Abbruch.
    @MainActor
    private final class Tor {
        private var offen = false
        private var wartender: CheckedContinuation<Void, Never>?

        func oeffnen() {
            offen = true
            wartender?.resume()
            wartender = nil
        }

        func durchgehen() async {
            guard !offen else { return }
            await withCheckedContinuation { wartender = $0 }
        }
    }

    private enum Ausloeser {
        case handlung(@MainActor () -> Void)
        case aufgabe(Tor, Task<Void, Never>)
    }
    private struct Eintrag {
        let faellig: Duration
        let nummer: Int
        let ausloeser: Ausloeser
    }
    private var offen: [Eintrag] = []
    private var angemeldet = 0
    private var abgeraeumt = false
    private var rueckt = false

    /// Wie viele Handlungen und Aufgaben noch ausstehen — ohne abgebrochene.
    var ausstehend: Int { offen.filter(gilt).count }

    /// Eine abgebrochene Aufgabe zählt nicht mehr; ausgetragen wird sie erst, wenn ihr Abbruch auf der
    /// Hauptwarteschlange läuft (Z-AT6f2-05).
    private func gilt(_ eintrag: Eintrag) -> Bool {
        if case .aufgabe(_, let aufgabe) = eintrag.ausloeser { return !aufgabe.isCancelled }
        return true
    }

    /// Sekunden auf Mikrosekunden gerundet: 0,35 + 50 × 0,05 ergibt genau 2,85 s (N-05).
    private static func dauer(_ sekunden: Double) -> Duration {
        .microseconds(Int((sekunden * 1_000_000).rounded()))
    }

    func nach(_ sekunden: Double, _ handlung: @escaping @MainActor () -> Void) {
        verlangt.append(.nach(sekunden))
        guard !abgeraeumt else { return }
        angemeldet += 1
        offen.append(Eintrag(faellig: jetzt + max(.zero, Stelluhr.dauer(sekunden)), nummer: angemeldet,
                             ausloeser: .handlung(handlung)))
    }

    @discardableResult
    func aufgabe(nach dauer: Duration, _ arbeit: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        verlangt.append(.aufgabe(dauer))
        return anmelden(dauer, arbeit)
    }

    /// Ohne Frist: angemeldet mit `jetzt` — sie läuft, sobald die Uhr Ereignisse nimmt, auch um null; ein
    /// `vorruecken(bis:)`, dessen Bedingung schon gilt, nimmt keins (E568).
    @discardableResult
    func gleich(_ arbeit: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        verlangt.append(.gleich)
        return anmelden(.zero, arbeit)
    }

    private func anmelden(_ dauer: Duration, _ arbeit: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        angemeldet += 1
        let nummer = angemeldet
        let tor = Tor()
        let aufgabe = Task { @MainActor in
            await withTaskCancellationHandler {
                await tor.durchgehen()
            } onCancel: {
                Task { @MainActor in self.abbrechen(nummer, tor) }
            }
            await arbeit()
        }
        if abgeraeumt {
            aufgabe.cancel()
            tor.oeffnen()
        } else {
            offen.append(Eintrag(faellig: jetzt + max(.zero, dauer), nummer: nummer, ausloeser: .aufgabe(tor, aufgabe)))
        }
        return aufgabe
    }

    /// Das Programm wartet über `aufgabe`; ein `warten` hier wäre eine Stelle, die die Uhr nicht abwarten kann.
    func warten(_ dauer: Duration) async throws {
        Issue.record("Die Stelluhr kennt kein `warten` — Aufgaben gehen über `aufgabe(nach:)` (E565)")
        throw CancellationError()
    }

    /// Abgebrochen, ehe die Uhr sie weckte: Ausgetragen, und die Arbeit läuft gleich — wie nach `Task.sleep`.
    private func abbrechen(_ nummer: Int, _ tor: Tor) {
        offen.removeAll { $0.nummer == nummer }
        tor.oeffnen()
    }

    /// Rückt die Uhr um `dauer` vor, Ereignis für Ereignis (siehe oben). Eine negative Dauer und ein `vorruecken`, während
    /// ein anderes auf eine Aufgabe wartet, sind Befunde — die Zeit liefe zurück (Z-AT6f2-04).
    func vorruecken(um dauer: Duration, sourceLocation: SourceLocation = #_sourceLocation) async {
        _ = await schreiten(um: dauer, bis: { false }, sourceLocation: sourceLocation)
    }

    /// Rückt Ereignis für Ereignis vor, bis `bedingung` gilt, höchstens um `hoechstens`; sagt, ob sie gilt. Geprüft wird
    /// vor dem ersten und nach jedem Ereignis — so sieht eine Prüfung auch, was gleich danach verfiele. Die Grenze ist
    /// Zeit der Uhr, keine Wanduhr. Hält es an, steht noch aus, was zur selben Frist sonst fällig ist, auch was das
    /// letzte Ereignis anmeldete; gilt die Bedingung schon vorher, läuft nichts. `vorruecken(um: .zero)` lässt es laufen.
    func vorruecken(bis bedingung: () -> Bool, hoechstens: Duration,
                    sourceLocation: SourceLocation = #_sourceLocation) async -> Bool {
        await schreiten(um: hoechstens, bis: bedingung, sourceLocation: sourceLocation)
    }

    private func schreiten(um dauer: Duration, bis bedingung: () -> Bool, sourceLocation: SourceLocation) async -> Bool {
        guard dauer >= .zero else {
            Issue.record("Stelluhr: `vorruecken` mit negativer Dauer \(dauer)", sourceLocation: sourceLocation)
            return false
        }
        guard !rueckt else {
            Issue.record("Stelluhr: `vorruecken` in einem laufenden `vorruecken`", sourceLocation: sourceLocation)
            return false
        }
        rueckt = true
        defer { rueckt = false }
        if bedingung() { return true }
        let ziel = jetzt + dauer
        var ereignisse = 0
        while let stelle = naechstes(bis: ziel) {
            let eintrag = offen.remove(at: stelle)
            jetzt = eintrag.faellig
            switch eintrag.ausloeser {
            case .handlung(let handlung):
                handlung()
            case .aufgabe(let tor, let aufgabe):
                tor.oeffnen()
                await aufgabe.value
            }
            if bedingung() { return true }
            ereignisse += 1
            if ereignisse >= 10_000 {
                Issue.record("Stelluhr: 10 000 Ereignisse in einem Schritt — eine Schleife ohne Frist?", sourceLocation: sourceLocation)
                return false
            }
        }
        jetzt = ziel
        return bedingung()
    }

    private func naechstes(bis ziel: Duration) -> Int? {
        offen.indices.filter { offen[$0].faellig <= ziel && gilt(offen[$0]) }
            .min { (offen[$0].faellig, offen[$0].nummer) < (offen[$1].faellig, offen[$1].nummer) }
    }

    /// Am Ende jeder Prüfung: Handlungen entfallen, wartende Aufgaben laufen abgebrochen los, und was danach noch eine
    /// Aufgabe anmeldet, läuft gleich abgebrochen — keine Aufgabe bleibt an der Uhr hängen. Wege ohne Abbruchprüfung
    /// laufen dabei los wie im Betrieb nach einem Abbruch (Z-AT6f1-04).
    func abraeumen() {
        abgeraeumt = true
        let alle = offen
        offen.removeAll()
        for eintrag in alle {
            if case .aufgabe(let tor, let aufgabe) = eintrag.ausloeser {
                aufgabe.cancel()
                tor.oeffnen()
            }
        }
    }
}
