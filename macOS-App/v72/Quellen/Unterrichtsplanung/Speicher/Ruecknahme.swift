// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Der Verlauf eines Schauplatzes: Momentaufnahmen, keine Gegenoperationen (E82).
///
/// **Warum Momentaufnahmen.** `Planung` und `Sitzplan` sind Werttypen; eine
/// Kopie teilt ihren Speicher, bis sich wirklich etwas ändert (copy-on-write).
/// Eine Rücknahme ist damit ein Zurücklegen, kein Rückrechnen — und sie kann
/// nicht auseinanderlaufen, wie es eine Gegenoperation je Aktion könnte. Genau
/// daran krankten in diesem Haus schon drei Befunde: zwei Wege, die dieselbe
/// Frage beantworten sollten.
///
/// **Was ein Schritt ist.** Eine abgeschlossene Handlung mit ihrem Namen — der
/// steht im Menü („Widerrufen: Vorhaben löschen“). Eingaben, die zusammen eine
/// Handlung sind, fasst die Schreibphase zusammen (E88): Wer einen Namen tippt,
/// erzeugt sonst je Tipppause einen Schritt — ein halbes Dutzend für einen
/// Kursnamen, und der Verlauf erzählt die Tipparbeit statt der Arbeit.
@MainActor
@Observable
final class Ruecknahme<Stand: Equatable> {

    /// Was außerhalb der Momentaufnahme liegt und doch zum selben Handgriff
    /// gehört — der Sitzplan einer entfernten Klasse etwa: Er hat seine eigene
    /// Datei und seinen eigenen Schauplatz (E82), verschwindet aber mit dem
    /// Kurs. Ein Widerrufen, das den Kurs zurückbrächte und den Sitzplan nicht,
    /// wäre ein halbes Zurück — und ein halbes Zurück ist keines.
    ///
    /// Die Regel dazu: **Beiwerk nur für das, was derselbe Handgriff mitnimmt**
    /// — nicht als Hintertür für Zustand, der ins Modell gehört.
    ///
    /// **Eine Tasche, keine Momentaufnahme (N58-02, E110).** Bis v59 fing das
    /// Beiwerk den Sitzplan beim Löschen und legte beim zweiten ⌘Z genau den
    /// zurück — auch wenn dazwischen ein neuer übernommen worden war: ⌘Z,
    /// Sitzplan zu P1, ⇧⌘Z, ⌘Z brachte P0, und P1 war fort. Jetzt greift `vor`
    /// beim Wiederholen das, was dann da ist, in die `Tasche`, und `zurueck`
    /// legt genau das zurück: Wiederholen entfernt, was da ist; Widerrufen
    /// bringt, was entfernt wurde. Eine leere Tasche ist erlaubt — ein Kurs
    /// ohne Sitzplan trägt sie trotzdem, damit ein später angelegter Sitzplan
    /// beim Wiederholen mitreist (B31).
    struct Beiwerk {
        /// Wohin der Schritt gerade geht — `moeglich` fragt richtungsweise:
        /// Zurücklegen braucht die Sitzpläne nur, wenn die Tasche etwas trägt.
        enum Richtung: Sendable { case zurueck, vor }
        /// Geht es gerade? `nil` heißt ja, sonst steht hier der Grund. Ein
        /// Schritt, dessen Beiwerk nicht mitkommt, wird **gar nicht** genommen:
        /// Ein halbes Zurück ist keines.
        let moeglich: @MainActor (Richtung) -> String?
        let zurueck: @MainActor () -> Void
        let vor: @MainActor () -> Void
    }

    /// Was ein Löschschritt außerhalb der Momentaufnahme bei sich trägt — als
    /// Verweis, damit `vor` und `zurueck` desselben Schrittes dieselbe Tasche
    /// füllen und leeren (E110).
    @MainActor
    final class Tasche<Inhalt> {
        var inhalt: Inhalt?
        init(_ inhalt: Inhalt?) { self.inhalt = inhalt }
    }

    struct Schritt {
        /// Der Wortlaut fürs Menü — „Vorhaben löschen“, nicht „löschen“.
        let name: String
        /// Woran die Schreibphase dasselbe Ziel erkennt (E88) — die Kennung des
        /// Kurses, des Vorhabens, des Tisches. Ohne Kennung wird nie
        /// zusammengefasst: Zwei Löschungen sind zwei Schritte.
        let kennung: String?
        let vorher: Stand
        var nachher: Stand
        var zeitpunkt: Date
        var beiwerk: Beiwerk?
    }

    /// Wie viele Schritte der Verlauf hält (E83).
    let tiefe: Int
    /// Wie lange eine Schreibphase offen bleibt (E88).
    let phasendauer: TimeInterval

    init(tiefe: Int = 50, phasendauer: TimeInterval = 2) {
        self.tiefe = tiefe
        self.phasendauer = phasendauer
    }

    private(set) var zurueck: [Schritt] = []
    private(set) var vor: [Schritt] = []

    var kannZurueck: Bool { !zurueck.isEmpty }
    var kannVor: Bool { !vor.isEmpty }
    /// Was ein „Widerrufen“ jetzt zurücknähme — für den Menütitel.
    var naechsterName: String? { zurueck.last?.name }
    /// Was ein „Wiederholen“ jetzt wiederholte.
    var wiederholungsName: String? { vor.last?.name }

    /// Einen abgeschlossenen Schritt anmelden. Dieselbe Handlung am selben Ziel
    /// innerhalb der Schreibphase wächst in den letzten Schritt hinein, statt
    /// einen neuen zu beginnen.
    func anmelden(_ name: String, kennung: String? = nil, vorher: Stand, nachher: Stand,
                  beiwerk: Beiwerk? = nil) {
        guard vorher != nachher else { return }
        vor.removeAll()
        let jetzt = Pruefuhr.jetzt
        // Ein Schritt mit Beiwerk wächst in keinen anderen hinein und nimmt
        // keinen auf: Sein Beiwerk gehört zu genau diesem Handgriff.
        if let kennung, beiwerk == nil, var letzter = zurueck.last, letzter.beiwerk == nil,
           letzter.name == name, letzter.kennung == kennung,
           jetzt.timeIntervalSince(letzter.zeitpunkt) <= phasendauer {
            letzter.nachher = nachher
            letzter.zeitpunkt = jetzt
            zurueck[zurueck.count - 1] = letzter
            return
        }
        zurueck.append(Schritt(name: name, kennung: kennung, vorher: vorher, nachher: nachher,
                               zeitpunkt: jetzt, beiwerk: beiwerk))
        // Der älteste fällt heraus; ein Verlauf ohne Grenze wüchse mit jeder
        // Sitzung weiter. Fünfzig, weil gemessen: Zwanzig volle Schritte an
        // einer gefüllten Planung kosten 1,6 MB, fünfzig also gut 4 MB — die
        // Momentaufnahmen teilen sich alles außer der Liste, die sich ändert.
        if zurueck.count > tiefe { zurueck.removeFirst(zurueck.count - tiefe) }
    }

    /// Ein Handgriff, der die Momentaufnahme gar nicht berührt und doch
    /// zurückgenommen werden soll: das Entfernen eines Sitzplans. Er liegt
    /// neben der Planung — verschwindet aber auf Wunsch des Nutzers, und ⌘Z
    /// muss ihn zurückholen können (S6).
    func anmelden(_ name: String, stand: Stand, beiwerk: Beiwerk) {
        vor.removeAll()
        zurueck.append(Schritt(name: name, kennung: nil, vorher: stand, nachher: stand,
                               zeitpunkt: Pruefuhr.jetzt, beiwerk: beiwerk))
        if zurueck.count > tiefe { zurueck.removeFirst(zurueck.count - tiefe) }
    }

    /// Den letzten Schritt herausnehmen — der Aufrufer legt `vorher` zurück.
    func zuruecknehmen() -> Schritt? {
        guard let schritt = zurueck.popLast() else { return nil }
        vor.append(schritt)
        return schritt
    }

    /// Den zuletzt zurückgenommenen Schritt wiederholen — `nachher` gilt wieder.
    func wiederholen() -> Schritt? {
        guard let schritt = vor.popLast() else { return nil }
        zurueck.append(schritt)
        return schritt
    }

    /// Nach einem Wechsel des Schauplatzes: Laden, Import, neue Planung,
    /// Entsperren, ein Schutzübergang. Was danach gilt, hat mit dem, was vorher
    /// galt, nichts mehr zu tun — ein Widerrufen darüber hinweg wäre eine Falle
    /// (E82, E85).
    func leeren() {
        guard kannZurueck || kannVor else { return }
        zurueck.removeAll()
        vor.removeAll()
    }
}
