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
        #expect(ohne.contains("„Mit dem Anmeldepasswort öffnen“") && ohne.contains("auf dem iPad und auf jedem anderen Rechner öffnet immer die Passphrase"))
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

    @Test("Scheitert die Wicklung dieses Macs, wird ohne sie vorbereitet — Passphrase und Wiederherstellung stehen, der Grund liegt bei")
    func vorbereitenOhneWicklung() throws {
        let vorbereitet = try Planungsspeicher.tresorVorbereiten(
            passphrase: EnklavePruefungen.passphrase, enklave: true,
            anleger: { _ in throw EnklavePruefungen.vmFehler })
        #expect(vorbereitet.tresor.hat(Wicklung.passphrase) && vorbereitet.tresor.hat(Wicklung.wiederherstellung))
        #expect(!vorbereitet.tresor.hat(Wicklung.enklave))
        #expect(vorbereitet.enklaveGrund?.contains("Beim Start ist die Passphrase fällig") == true)
        #expect(vorbereitet.tresor.passphraseStimmt(EnklavePruefungen.passphrase))
        #expect(vorbereitet.blatt.count > 20)
    }

    @Test("Gelingt die Wicklung, liegt sie im Tresor und es gibt keinen Grund")
    func vorbereitenMitWicklung() throws {
        let vorbereitet = try Planungsspeicher.tresorVorbereiten(
            passphrase: EnklavePruefungen.passphrase, enklave: true,
            anleger: { $0.wicklungUebernehmen(EnklavePruefungen.gestellteWicklung()) })
        #expect(vorbereitet.tresor.hat(Wicklung.enklave) && vorbereitet.enklaveGrund == nil)
        // Ohne Enklave (Prüfziel, Vorgabe) wird der Anleger gar nicht gerufen.
        let ohne = try Planungsspeicher.tresorVorbereiten(
            passphrase: EnklavePruefungen.passphrase, enklave: false,
            anleger: { _ in throw EnklavePruefungen.vmFehler })
        #expect(!ohne.tresor.hat(Wicklung.enklave) && ohne.enklaveGrund == nil)
    }

    @Test("Dasselbe beim Erneuern des Schlüssels")
    func erneuernOhneWicklung() throws {
        let alter = try Planungsspeicher.tresorVorbereiten(passphrase: EnklavePruefungen.passphrase, enklave: false).tresor
        let neu = try Planungsspeicher.erneuernVorbereiten(
            alter, alt: EnklavePruefungen.passphrase, neu: "Ein anderer Satz, den man behält", enklave: true,
            anleger: { _ in throw EnklavePruefungen.vmFehler })
        #expect(!neu.tresor.hat(Wicklung.enklave) && neu.enklaveGrund != nil)
        #expect(neu.tresor.kennung != alter.kennung, "ein frischer Tresor")
    }

    @MainActor
    @Test("Am Speicher: Einschalten gelingt ohne Wicklung, das Blatt kennt den Hinweis, die Meldung sagt ihn, die Passphrase öffnet die Ablage")
    func einschaltenOhneWicklung() throws {
        let ordner = URL.temporaryDirectory.appending(component: "enklave-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let s = Planungsspeicher(ablage: Ablage(ordner: ordner))
        var p = Planung.leer(titel: "Enklave", start: try #require(Tag(iso: "2026-08-03")), wochen: 4, basis: "",
                             klassen: [Klasse(id: "k1", name: "G6a", fach: "Informatik", notiz: "", farbe: 0, farbeManuell: false)],
                             fachfarben: [:])
        p.eintraege = [Vorhaben(id: "v1", klasseId: "k1", woche: 1, titel: "Erstes", text: "", erledigt: false, materialien: [], links: [])]
        s.planung = p
        s.jetztSichern()

        let blatt = try s.verschluesselungVorbereiten(passphrase: EnklavePruefungen.passphrase, enklave: true,
                                                      anleger: { _ in throw EnklavePruefungen.vmFehler })
        #expect(blatt.count > 20)
        #expect(s.vorbereitungHinweis?.contains("ließ sich nicht anlegen") == true, "Schritt 2 des Blatts zeigt den Grund")

        let ergebnis = s.verschluesselungEinschalten()
        #expect(ergebnis.ablage == .geschrieben)
        let tresor = try #require(s.tresor)
        #expect(!tresor.hat(Wicklung.enklave) && tresor.hat(Wicklung.passphrase))
        #expect(s.vorbereitungHinweis == nil, "nach dem Einschalten ist der Hinweis abgeräumt")
        #expect(s.meldungen.contains { $0.text.contains("Beim Start ist die Passphrase fällig") }, "die Meldung sagt den Grund")

        // Die Datei trägt keine Wicklung dieses Macs — und die Passphrase öffnet sie.
        let roh = try Data(contentsOf: Ablage(ordner: ordner).datei)
        let kopf = try Tresor.kopfLesen(roh)
        #expect(kopf.wicklung(Wicklung.enklave) == nil && kopf.wicklung(Wicklung.passphrase) != nil)
        #expect(try Tresor.oeffnen(kopf: kopf, passphrase: EnklavePruefungen.passphrase).kennung == tresor.kennung)
    }
}
