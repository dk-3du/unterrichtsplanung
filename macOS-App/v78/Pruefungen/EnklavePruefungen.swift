// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security
import Testing

@testable import Unterrichtsplanung

/// Die Wicklung dieses Macs ist eine Bequemlichkeit, keine Bedingung (B32,
/// E131–E134). In der VM des Nutzers (macOS 27.0, ohne eingerichtete Touch
/// ID) meldete die Secure Enclave sich verfügbar, aber der Schlüssel mit
/// `.biometryCurrentSet` ließ sich nicht anlegen (LocalAuthentication −1000)
/// — und `tresorVorbereiten` brach damit die ganze Einrichtung ab: kein Weg
/// zur Verschlüsselung auf einem Mac ohne Touch ID.
///
/// Ohne echte Enklave, ohne Fenster, ohne Touch-ID-Dialog: Der Anleger der
/// Wicklung wird eingespritzt — Erfolg wie Fehlschlag —, die Zugriffsbedingung
/// und die Wörter sind reine Funktionen des Geräts.
///
/// Seit v65 (E139, N64-02) liefert die Vorbereitung ein **Ergebnis** der
/// Wicklung dieses Macs — angelegt (mit welcher Bedingung), nicht verfügbar,
/// gescheitert —, und Blatt wie Meldung lesen daraus. Bis 1.7.5 gab es nur
/// „ein Grund“ oder `nil`, und `nil` hieß „Wicklung da“, auch wenn nie eine
/// versucht worden war: Schritt 2 versprach dann das Anmeldepasswort.
///
/// Seit v65 (E139, N64-02) liefert die Vorbereitung ein **Ergebnis** der
/// Wicklung dieses Macs — angelegt (mit welcher Bedingung), nicht verfügbar,
/// gescheitert —, und Blatt wie Meldung lesen daraus. Bis 1.7.5 gab es nur
/// „ein Grund“ oder `nil`, und `nil` hieß „Wicklung da“, auch wenn nie eine
/// versucht worden war: Schritt 2 versprach dann das Anmeldepasswort.
@Suite("Enklave: ohne Touch ID")
struct EnklavePruefungen {

    private static let passphrase = "Ein Satz, den man behält"

    /// Ein Fehlschlag, wie ihn die VM meldete.
    private static let vmFehler = NSError(domain: "com.apple.LocalAuthentication", code: -1000,
                                          userInfo: [NSLocalizedDescriptionKey: "Fehler bei der Authentifizierung."])

    /// Eine Wicklung, die aussieht wie die eines Macs — ohne Enklave angelegt.
    private static func gestellteWicklung() -> Wicklung {
        Wicklung(art: Wicklung.enklave, felder: ["geraet": .text("gestellt")])
    }

    @Test("Die Zugriffsbedingung folgt dem Gerät: mit Biometrie wie bisher, ohne sie das Anmeldepasswort allein (E132)")
    func zugriffsbedingung() {
        #expect(Tresor.zugriffsbedingung(biometrie: true) == [.privateKeyUsage, .biometryCurrentSet, .or, .devicePasscode])
        #expect(Tresor.zugriffsbedingung(biometrie: false) == [.privateKeyUsage, .devicePasscode])
    }

    @Test("Die Wörter folgen dem Gerät (E134)")
    func woerter() {
        #expect(Tresor.freigabeName(biometrie: true) == "Touch ID oder das Anmeldepasswort")
        #expect(Tresor.freigabeName(biometrie: false) == "das Anmeldepasswort")
        #expect(Tresor.schalterName(biometrie: true) == "Mit Touch ID öffnen")
        #expect(Tresor.schalterName(biometrie: false) == "Mit dem Anmeldepasswort öffnen")
        #expect(Tresor.freigabeNameGross(biometrie: true) == "Touch ID oder das Anmeldepasswort")
        #expect(Tresor.freigabeNameGross(biometrie: false) == "Das Anmeldepasswort")
    }

    @Test("Die Einrichtung sagt, womit dieser Mac beim Start öffnet — ohne Touch ID das Anmeldepasswort, unmissverständlich (B33)")
    func startHinweis() {
        let ohne = Tresor.startHinweis(biometrie: false)
        #expect(ohne.hasPrefix("Dieser Mac hat keine eingerichtete Touch ID. Beim Start öffnet deshalb das Anmeldepasswort dieses Macs die Planung"))
        #expect(ohne.contains("dasselbe Passwort wie bei der Anmeldung am Mac"))
        #expect(ohne.contains("„Mit dem Anmeldepasswort öffnen“") && ohne.contains("in der Web App und auf jedem anderen Rechner öffnet immer die Passphrase"))
        let mit = Tresor.startHinweis(biometrie: true)
        #expect(mit.hasPrefix("Beim Start öffnet Touch ID oder das Anmeldepasswort dieses Macs die Planung"))
        #expect(mit.contains("„Mit Touch ID öffnen“") && mit.contains("immer die Passphrase"))
        // Der Kernsatz wird im Blatt fett gesetzt (Nutzer, 16.09.2026) — er ist der Teil, der ins Auge fallen muss.
        let ohneTeile = Tresor.starthinweis(biometrie: false)
        #expect(ohneTeile.vorsatz == "Dieser Mac hat keine eingerichtete Touch ID.")
        #expect(ohneTeile.kern == "Beim Start öffnet deshalb das Anmeldepasswort dieses Macs die Planung — dasselbe Passwort wie bei der Anmeldung am Mac.")
        #expect(ohneTeile.text == ohne)
        let mitTeile = Tresor.starthinweis(biometrie: true)
        #expect(mitTeile.vorsatz == nil && mitTeile.kern == "Beim Start öffnet Touch ID oder das Anmeldepasswort dieses Macs die Planung.")
        #expect(mitTeile.text == mit)
    }

    @Test("Der Hinweis nennt den Grund und den Weg — ohne Touch ID im Wortlaut des Nutzers (E131)")
    func hinweis() {
        let ohne = Planungsspeicher.enklaveHinweis(EnklavePruefungen.vmFehler, biometrie: false)
        #expect(ohne.hasPrefix("Dieser Mac verfügt nicht über Touch ID. Die Wicklung mit dem Anmeldepasswort ließ sich nicht anlegen: Fehler bei der Authentifizierung."))
        #expect(ohne.hasSuffix("Beim Start ist die Passphrase fällig; unter „Verschlüsselung → Dieser Mac“ lässt sie sich später einschalten."))
        let mit = Planungsspeicher.enklaveHinweis(EnklavePruefungen.vmFehler, biometrie: true)
        #expect(mit.hasPrefix("Die Wicklung für diesen Mac (Touch ID oder Anmeldepasswort) ließ sich nicht anlegen: Fehler bei der Authentifizierung."))
        #expect(mit.hasSuffix("lässt sie sich später einschalten."))
    }

    @Test("Scheitert die Wicklung dieses Macs, wird ohne sie vorbereitet — Passphrase und Wiederherstellung stehen, das Ergebnis trägt den Grund")
    func vorbereitenOhneWicklung() throws {
        let vorbereitet = try Planungsspeicher.tresorVorbereiten(
            passphrase: EnklavePruefungen.passphrase, enklave: true, biometrie: false,
            anleger: { _, _ in throw EnklavePruefungen.vmFehler })
        #expect(vorbereitet.tresor.hat(Wicklung.passphrase) && vorbereitet.tresor.hat(Wicklung.wiederherstellung))
        #expect(!vorbereitet.tresor.hat(Wicklung.enklave))
        guard case .gescheitert(let grund) = vorbereitet.geraet else {
            Issue.record("erwartet: gescheitert, ist \(vorbereitet.geraet)"); return
        }
        #expect(grund.hasPrefix("Dieser Mac verfügt nicht über Touch ID.") && grund.contains("Beim Start ist die Passphrase fällig"))
        #expect(vorbereitet.geraet.starthinweis == nil, "das Scheitern zeigt das Blatt als Warnung mit dem Grund, nicht als Starthinweis")
        #expect(vorbereitet.geraet.meldung?.warnung == true && vorbereitet.geraet.meldung?.text == grund)
        #expect(vorbereitet.tresor.passphraseStimmt(EnklavePruefungen.passphrase))
        #expect(vorbereitet.blatt.count > 20)
    }

    @Test("Gelingt die Wicklung, sagt das Ergebnis die Bedingung; nicht versucht heißt „nicht verfügbar“ — nie „angelegt“ (N64-02)")
    func vorbereitenMitWicklung() throws {
        for biometrie in [true, false] {
            let vorbereitet = try Planungsspeicher.tresorVorbereiten(
                passphrase: EnklavePruefungen.passphrase, enklave: true, biometrie: biometrie,
                anleger: { tresor, _ in tresor.wicklungUebernehmen(EnklavePruefungen.gestellteWicklung()) })
            #expect(vorbereitet.tresor.hat(Wicklung.enklave) && vorbereitet.geraet == .angelegt(biometrie: biometrie))
            #expect(vorbereitet.geraet.starthinweis == Tresor.starthinweis(biometrie: biometrie))
        }
        #expect(Tresor.Geraetewicklung.angelegt(biometrie: true).meldung == nil, "mit Touch ID gibt es nichts zu sagen")
        #expect(Tresor.Geraetewicklung.angelegt(biometrie: false).meldung?.text.contains("Anmeldepasswort dieses Macs") == true)
        // Ohne Enklave (Prüfziel, Vorgabe) wird der Anleger gar nicht gerufen —
        // und das Ergebnis sagt genau das. Bis 1.7.5 hieß es `nil`, und das Blatt
        // las daraus „Wicklung da“ (N64-02).
        let ohne = try Planungsspeicher.tresorVorbereiten(
            passphrase: EnklavePruefungen.passphrase, enklave: false, biometrie: false,
            anleger: { _, _ in throw EnklavePruefungen.vmFehler })
        #expect(!ohne.tresor.hat(Wicklung.enklave) && ohne.geraet == .nichtVerfuegbar)
        let hinweis = try #require(ohne.geraet.starthinweis)
        #expect(hinweis.kern == "Beim Start ist deshalb die Passphrase fällig.")
        #expect(!hinweis.text.contains("Anmeldepasswort") && !hinweis.text.contains("Touch ID"), "keine Zusage, die keine Wicklung deckt")
        #expect(ohne.geraet.meldung?.warnung == false && ohne.geraet.meldung?.text.contains("Passphrase fällig") == true)
    }

    @Test("Dasselbe beim Erneuern des Schlüssels")
    func erneuernOhneWicklung() throws {
        let alter = try Planungsspeicher.tresorVorbereiten(passphrase: EnklavePruefungen.passphrase, enklave: false).tresor
        let neu = try Planungsspeicher.erneuernVorbereiten(
            alter, alt: EnklavePruefungen.passphrase, neu: "Ein anderer Satz, den man behält", enklave: true, biometrie: true,
            anleger: { _, _ in throw EnklavePruefungen.vmFehler })
        #expect(!neu.tresor.hat(Wicklung.enklave))
        guard case .gescheitert(let grund) = neu.geraet else { Issue.record("erwartet: gescheitert, ist \(neu.geraet)"); return }
        #expect(grund.hasPrefix("Die Wicklung für diesen Mac (Touch ID oder Anmeldepasswort) ließ sich nicht anlegen:"))
        #expect(neu.tresor.kennung != alter.kennung, "ein frischer Tresor")
    }

    @MainActor
    @Test("Am Speicher: Einschalten gelingt ohne Wicklung, das Blatt kennt den Grund, die Meldung sagt ihn, die Passphrase öffnet die Ablage")
    func einschaltenOhneWicklung() throws {
        let (s, ordner) = try EnklavePruefungen.speicher("enklave")
        let blatt = try s.verschluesselungVorbereiten(passphrase: EnklavePruefungen.passphrase, enklave: true,
                                                      anleger: { _, _ in throw EnklavePruefungen.vmFehler })
        #expect(blatt.count > 20)
        guard case .gescheitert(let grund)? = s.vorbereitungGeraet else {
            Issue.record("Schritt 2 des Blatts kennt den Grund nicht: \(String(describing: s.vorbereitungGeraet))"); return
        }
        #expect(grund.contains("ließ sich nicht anlegen"))

        let ergebnis = s.verschluesselungEinschalten()
        #expect(ergebnis.ablage == .geschrieben)
        let tresor = try #require(s.tresor)
        #expect(!tresor.hat(Wicklung.enklave) && tresor.hat(Wicklung.passphrase))
        #expect(s.vorbereitungGeraet == nil, "nach dem Einschalten ist das Ergebnis abgeräumt")
        #expect(s.meldungen.contains { $0.text == grund && $0.art == .warnung }, "die Meldung sagt den Grund, als Warnung")
        try EnklavePruefungen.passphraseOeffnet(ordner, tresor)
    }

    @MainActor
    @Test("Am Speicher ohne Enklave: Einschalten gelingt, keine Wicklung, keine Zusage von Anmeldepasswort oder Touch ID — die Passphrase ist fällig (N64-02)")
    func einschaltenOhneEnklave() throws {
        let (s, ordner) = try EnklavePruefungen.speicher("keine-enklave")
        _ = try s.verschluesselungVorbereiten(passphrase: EnklavePruefungen.passphrase, enklave: false,
                                              anleger: { _, _ in Issue.record("der Anleger darf ohne Enklave nicht gerufen werden") })
        #expect(s.vorbereitungGeraet == .nichtVerfuegbar)
        let hinweis = try #require(s.vorbereitungGeraet?.starthinweis)
        #expect(hinweis.text.contains("Passphrase fällig") && !hinweis.text.contains("Anmeldepasswort") && !hinweis.text.contains("Touch ID"))

        let ergebnis = s.verschluesselungEinschalten()
        #expect(ergebnis.ablage == .geschrieben)
        let tresor = try #require(s.tresor)
        #expect(!tresor.hat(Wicklung.enklave) && tresor.hat(Wicklung.passphrase) && tresor.hat(Wicklung.wiederherstellung))
        #expect(s.vorbereitungGeraet == nil)
        #expect(s.meldungen.contains { $0.text.contains("beim Start ist die Passphrase fällig") && $0.art != .warnung })
        #expect(!s.meldungen.contains { $0.text.contains("Anmeldepasswort") || $0.text.contains("Touch ID") },
                "keine Meldung verspricht, was keine Wicklung deckt")
        try EnklavePruefungen.passphraseOeffnet(ordner, tresor)
    }

    @Test("Nicht jedes „nein“ heißt „keine Biometrie“: Sperre und getrennte Tastatur gelten als eingerichtet (E140)")
    func abbildungDerFehler() {
        #expect(Tresor.biometrieEingerichtet(kann: true, fehler: nil))
        #expect(Tresor.biometrieEingerichtet(kann: false, fehler: .biometryLockout), "zu oft danebengelegt — die Finger sind angelernt")
        #expect(Tresor.biometrieEingerichtet(kann: false, fehler: .biometryDisconnected), "Tastatur mit Touch ID getrennt")
        #expect(Tresor.biometrieEingerichtet(kann: false, fehler: .biometryNotPaired))
        #expect(!Tresor.biometrieEingerichtet(kann: false, fehler: .biometryNotEnrolled), "die VM: −7")
        #expect(!Tresor.biometrieEingerichtet(kann: false, fehler: .biometryNotAvailable))
        #expect(!Tresor.biometrieEingerichtet(kann: false, fehler: .passcodeNotSet))
        #expect(!Tresor.biometrieEingerichtet(kann: false, fehler: nil))
    }

    @Test("Die Wicklung dieses Macs trägt ihre Bedingung; ohne Feld (Dateien bis 1.7.5) ist sie unbekannt (E141)")
    func bedingungDerWicklung() {
        let mit = Wicklung(art: Wicklung.enklave, felder: ["geraet": .text("x"), Wicklung.bedingung: .text(Wicklung.bedingungBiometrie)])
        let passwort = Wicklung(art: Wicklung.enklave, felder: ["geraet": .text("x"), Wicklung.bedingung: .text(Wicklung.bedingungPasswort)])
        let alt = Wicklung(art: Wicklung.enklave, felder: ["geraet": .text("x")])
        #expect(mit.biometrieBedingung == true && passwort.biometrieBedingung == false && alt.biometrieBedingung == nil)
        #expect(mit.beschriftung == "Dieser Mac (Secure Enclave, Touch ID oder Anmeldepasswort)")
        #expect(passwort.beschriftung == "Dieser Mac (Secure Enclave, Anmeldepasswort)")
        #expect(alt.beschriftung == "Dieser Mac (Secure Enclave, Touch ID oder Anmeldepasswort)")
        #expect(Wicklung(art: Wicklung.enklave, felder: [Wicklung.bedingung: .text("morgen")]).biometrieBedingung == nil, "unbekannter Wert: unbekannt")
        #expect(Wicklung(art: Wicklung.passphrase, felder: [Wicklung.bedingung: .text("biometrie")]).biometrieBedingung == nil, "nur die Wicklung dieses Macs")
    }

    @MainActor
    @Test("Die Fähigkeit wird im Augenblick bestimmt: zwei Vorbereitungen am selben Speicher folgen der umgestellten Quelle; danach beschreibt der Speicher die liegende Wicklung (N64-01)")
    func quelleImAugenblick() throws {
        let (s, _) = try EnklavePruefungen.speicher("quelle")
        var gesehen: [Bool] = []
        let anleger: (Tresor, Bool) throws -> Void = { tresor, biometrie in
            gesehen.append(biometrie)
            tresor.wicklungUebernehmen(Wicklung(art: Wicklung.enklave, felder: [
                "geraet": .text("gestellt"),
                Wicklung.bedingung: .text(biometrie ? Wicklung.bedingungBiometrie : Wicklung.bedingungPasswort)]))
        }
        s.biometrieQuelle = { false }
        _ = try s.verschluesselungVorbereiten(passphrase: EnklavePruefungen.passphrase, enklave: true, anleger: anleger)
        #expect(s.vorbereitungGeraet == .angelegt(biometrie: false))
        s.verschluesselungVerwerfen()
        s.biometrieQuelle = { true }   // Touch ID inzwischen eingerichtet — ohne Neustart
        _ = try s.verschluesselungVorbereiten(passphrase: EnklavePruefungen.passphrase, enklave: true, anleger: anleger)
        #expect(s.vorbereitungGeraet == .angelegt(biometrie: true))
        #expect(gesehen == [false, true], "der Anleger bekommt den Wert des Augenblicks, nicht den vom Start")
        #expect(s.verschluesselungEinschalten().ablage == .geschrieben)
        #expect(s.geraeteWicklungBedingung == true && s.geraeteBiometrie == true, "aus dem Feld der liegenden Wicklung")
        #expect(!s.geraetewicklungVeraltet)
    }

    @MainActor
    @Test("Eine Wicklung mit dem Passwort allein bleibt hinter einem Gerät mit Touch ID zurück — der Speicher sagt es (N64-01)")
    func veralteteWicklung() throws {
        let (s, _) = try EnklavePruefungen.speicher("veraltet")
        s.biometrieQuelle = { false }
        _ = try s.verschluesselungVorbereiten(passphrase: EnklavePruefungen.passphrase, enklave: true, anleger: { tresor, biometrie in
            tresor.wicklungUebernehmen(Wicklung(art: Wicklung.enklave, felder: [
                "geraet": .text("gestellt"),
                Wicklung.bedingung: .text(biometrie ? Wicklung.bedingungBiometrie : Wicklung.bedingungPasswort)]))
        })
        #expect(s.verschluesselungEinschalten().ablage == .geschrieben)
        #expect(s.geraeteWicklungBedingung == false && !s.geraeteBiometrie)
        s.biometrieQuelle = { true }
        #expect(s.geraeteWicklungBedingung == false && !s.geraeteBiometrie, "die liegende Wicklung öffnet weiter nur mit dem Passwort")
        #expect(s.geraetewicklungVeraltet, "Aus und wieder An stellt um")
    }

    // ── Hilfen ────────────────────────────────────────────────────────────

    /// Ein Speicher mit einer kleinen Planung in einem eigenen Ordner, gesichert.
    @MainActor
    private static func speicher(_ name: String) throws -> (Planungsspeicher, URL) {
        let ordner = URL.temporaryDirectory.appending(component: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        var p = Planung.leer(titel: "Enklave", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                             klassen: [Klasse(id: "k1", name: "G6a", fach: "Informatik", notiz: "", farbe: 0, farbeManuell: false)],
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "v1", klasseId: "k1", woche: 1, titel: "Erstes", text: "", erledigt: false, materialien: [], links: [])]
        s.planung = p
        s.jetztSichern()
        return (s, ordner)
    }

    /// Die Datei trägt keine Wicklung dieses Macs — und die Passphrase öffnet sie.
    @MainActor
    private static func passphraseOeffnet(_ ordner: URL, _ tresor: Tresor) throws {
        let roh = try Data(contentsOf: Ablage(ordner: ordner).datei)
        let kopf = try Tresor.kopfLesen(roh)
        #expect(kopf.wicklung(Wicklung.enklave) == nil && kopf.wicklung(Wicklung.passphrase) != nil)
        #expect(try Tresor.oeffnen(kopf: kopf, passphrase: EnklavePruefungen.passphrase).kennung == tresor.kennung)
    }
}
