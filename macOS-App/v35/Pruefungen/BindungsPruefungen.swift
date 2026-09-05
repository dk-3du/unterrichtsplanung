// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Testing

@testable import Unterrichtsplanung

/// Unser `Material`, nicht das von SwiftUI.
private typealias Material = Unterrichtsplanung.Material

/// Der Absturz beim Löschen eines Links.
///
/// `ForEach($liste)` reicht Bindungen durch, die über den Index greifen. Nach
/// dem Löschen zeigt die Bindung der verschwundenen Zeile weiter auf ihre alte
/// Stelle; liest SwiftUI sie noch einmal — ein Textfeld meldet beim
/// Verschwinden seinen Wert nach —, greift es hinter das Ende des Feldes.
@Suite("Bindung an ein Listenelement")
@MainActor
struct Bindungspruefungen {

    /// Ein Behälter, damit sich eine echte `Binding` bilden lässt.
    private final class Kiste {
        var links: [Weblink] = []
        var materialien: [Material] = []
    }

    private func kisteMitDreiLinks() -> (Kiste, Binding<[Weblink]>) {
        let kiste = Kiste()
        kiste.links = [Weblink(titel: "Eins", adresse: "https://a.example/"),
                       Weblink(titel: "Zwei", adresse: "https://b.example/"),
                       Weblink(titel: "Drei", adresse: "https://c.example/")]
        return (kiste, Binding(get: { kiste.links }, set: { kiste.links = $0 }))
    }

    @Test("Nach dem Löschen liest die Bindung den letzten Stand statt ins Leere")
    func lesenNachLoeschen() throws {
        let (kiste, liste) = kisteMitDreiLinks()
        let letzter = try #require(kiste.links.last)
        let zeile = liste[kennung: letzter.id, letzterStand: letzter]

        kiste.links.removeAll { $0.id == letzter.id }

        #expect(kiste.links.count == 2)
        #expect(zeile.wrappedValue.id == letzter.id)
        #expect(zeile.wrappedValue.titel == "Drei")
    }

    @Test("Nach dem Löschen läuft ein Schreibversuch ins Leere, nicht in den Speicher")
    func schreibenNachLoeschen() throws {
        let (kiste, liste) = kisteMitDreiLinks()
        let letzter = try #require(kiste.links.last)
        let zeile = liste[kennung: letzter.id, letzterStand: letzter]
        kiste.links.removeAll { $0.id == letzter.id }

        // Genau das tut das Textfeld beim Verschwinden.
        zeile.wrappedValue.adresse = "https://nachtraeglich.example/"

        #expect(kiste.links.count == 2)
        #expect(!kiste.links.contains { $0.adresse.contains("nachtraeglich") })
    }

    @Test("Solange der Eintrag da ist, schreibt die Bindung an die richtige Stelle")
    func schreibenTrifftDenRichtigen() throws {
        let (kiste, liste) = kisteMitDreiLinks()
        let mittlerer = kiste.links[1]
        let zeile = liste[kennung: mittlerer.id, letzterStand: mittlerer]

        zeile.wrappedValue.titel = "Geändert"

        #expect(kiste.links.map(\.titel) == ["Eins", "Geändert", "Drei"])
    }

    @Test("Die Stelle im Feld darf sich verschieben, die Bindung folgt der Kennung")
    func verschiebenAendertNichts() throws {
        let (kiste, liste) = kisteMitDreiLinks()
        let dritter = kiste.links[2]
        let zeile = liste[kennung: dritter.id, letzterStand: dritter]

        // Der erste Eintrag fällt weg — aus Stelle 2 wird Stelle 1.
        kiste.links.removeFirst()
        zeile.wrappedValue.titel = "Immer noch der dritte"

        #expect(kiste.links.map(\.titel) == ["Zwei", "Immer noch der dritte"])
    }

    @Test("Dasselbe gilt für Materialien")
    func materialienEbenso() throws {
        let kiste = Kiste()
        kiste.materialien = [Material(titel: "A", pfad: "a.pdf"),
                             Material(titel: "B", pfad: "b.pdf")]
        let liste = Binding(get: { kiste.materialien }, set: { kiste.materialien = $0 })
        let letzter = try #require(kiste.materialien.last)
        let zeile = liste[kennung: letzter.id, letzterStand: letzter]

        kiste.materialien.removeAll { $0.id == letzter.id }

        #expect(zeile.wrappedValue.titel == "B")
        zeile.wrappedValue.titel = "verworfen"
        #expect(kiste.materialien.map(\.titel) == ["A"])
    }
}
