// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing

@testable import Unterrichtsplanung

// ── Ablegen im Raster: was die Zwischenablage bringt (v88, AZ3; E905, E913, E917) ──
//
// Die Einträge in der Form, die das Hilfsprogramm am 28.10.2026 gemessen hat: der Finder je Datei `public.file-url` und
// `com.apple.finder.node` als Verweis, Safari `public.url` samt Titel, Text und Typen eines Dateiversprechens, Mail
// eine fertige Datei als Pfad. Den Weg über das Raster prüft die Klickprobe.

@Suite("Ablegen im Raster: was die Zwischenablage bringt", .serialized)
@MainActor
struct ZiehinhaltPruefungen {

    private func ablage(_ eintraege: [NSPasteboardItem]) -> NSPasteboard {
        let ablage = NSPasteboard(name: NSPasteboard.Name("org.3ducation.Unterrichtsplanung.Pruefung.\(UUID().uuidString)"))
        ablage.clearContents()
        ablage.writeObjects(eintraege)
        return ablage
    }

    /// Die Aufrufer räumen den Ordner mit `defer` wieder fort (G1-06).
    private func probedatei() throws -> URL {
        // Mit Leerzeichen im Namen, wie „Mail Downloads“ (Z-AZ3-02).
        let ordner = FileManager.default.temporaryDirectory.appending(component: "Mail Downloads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let datei = ordner.appending(component: "Arbeitsblatt.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: datei)
        return datei
    }

    private func finder(_ datei: URL) throws -> NSPasteboardItem {
        let roh = (datei as NSURL).perform(#selector(NSURL.fileReferenceURL))?.takeUnretainedValue() as? NSURL
        let verweis = try #require(roh?.absoluteString)
        #expect(verweis.hasPrefix("file:///.file/id="), "ein Verweis wie aus dem Finder")
        let eintrag = NSPasteboardItem()
        eintrag.setString(verweis, forType: .fileURL)
        eintrag.setString(verweis, forType: NSPasteboard.PasteboardType("com.apple.finder.node"))
        return eintrag
    }

    private func safari(_ adresse: String) -> NSPasteboardItem {
        let eintrag = NSPasteboardItem()
        eintrag.setString(adresse, forType: .URL)
        eintrag.setString("Photosynthese", forType: NSPasteboard.PasteboardType("public.url-name"))
        eintrag.setString(adresse, forType: .string)
        eintrag.setData(Data(), forType: NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"))
        eintrag.setString("com.apple.web-internet-location",
                          forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"))
        return eintrag
    }

    @Test("Ein Dateiverweis aus dem Finder wird zur Datei aufgelöst — kein Link daneben")
    func ausDemFinder() throws {
        let datei = try probedatei()
        defer { try? FileManager.default.removeItem(at: datei.deletingLastPathComponent()) }
        let zwischen = ablage([try finder(datei)])
        defer { zwischen.releaseGlobally() }
        let inhalt = Ziehinhalt.lesen(zwischen)
        #expect(inhalt.dateien.map { $0.resolvingSymlinksInPath().path } == [datei.resolvingSymlinksInPath().path])
        #expect(inhalt.links.isEmpty)
    }

    @Test("Ein Ordnerverweis aus dem Finder wird zum Ordner aufgelöst — kein Link daneben (Z-AZ6N-05)")
    func ordnerAusDemFinder() throws {
        let ordner = try probedatei().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: ordner) }
        let zwischen = ablage([try finder(ordner)])
        defer { zwischen.releaseGlobally() }
        let inhalt = Ziehinhalt.lesen(zwischen)
        #expect(inhalt.dateien.map { $0.resolvingSymlinksInPath().path } == [ordner.resolvingSymlinksInPath().path])
        #expect(inhalt.links.isEmpty)
    }

    @Test("Ein Anhang aus Mail kommt als Pfad und bleibt eine Datei")
    func ausMail() throws {
        let datei = try probedatei()
        defer { try? FileManager.default.removeItem(at: datei.deletingLastPathComponent()) }
        let eintrag = NSPasteboardItem()
        eintrag.setString(datei.absoluteString, forType: .fileURL)
        let zwischen = ablage([eintrag])
        defer { zwischen.releaseGlobally() }
        #expect(Ziehinhalt.lesen(zwischen).dateien.map(\.path) == [datei.path])
    }

    @Test("Ein Link aus Safari bleibt genau ein Link — das Dateiversprechen daneben hindert ihn nicht (E913)")
    func ausSafari() {
        let zwischen = ablage([safari("https://example.org/photosynthese")])
        defer { zwischen.releaseGlobally() }
        let inhalt = Ziehinhalt.lesen(zwischen)
        #expect(inhalt.links == ["https://example.org/photosynthese"])
        #expect(inhalt.dateien.isEmpty)
    }

    @Test("Nur http und https; ein Versprechen allein bringt nichts")
    func nichts() {
        let ftp = NSPasteboardItem()
        ftp.setString("ftp://example.org/x", forType: .URL)
        let versprechen = NSPasteboardItem()
        versprechen.setData(Data(), forType: NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"))
        let zwischen = ablage([ftp, versprechen])
        defer { zwischen.releaseGlobally() }
        let inhalt = Ziehinhalt.lesen(zwischen)
        #expect(inhalt.dateien.isEmpty && inhalt.links.isEmpty)
    }

    @Test("Ein Verweis, der sich nicht auflöst, bringt nichts — und bricht nichts")
    func verwaist() throws {
        let datei = try probedatei()
        defer { try? FileManager.default.removeItem(at: datei.deletingLastPathComponent()) }
        let roh = (datei as NSURL).perform(#selector(NSURL.fileReferenceURL))?.takeUnretainedValue() as? NSURL
        let verweis = try #require(roh?.absoluteString)
        // Die Dateinummer nach „id=<Volume>.“ gegen eine unbelegte getauscht.
        let teile = verweis.split(separator: ".", omittingEmptySubsequences: false)
        let verwaist = teile.dropLast().joined(separator: ".") + ".999999999999"
        let eintrag = NSPasteboardItem()
        eintrag.setString(verwaist, forType: .fileURL)
        let zwischen = ablage([eintrag])
        defer { zwischen.releaseGlobally() }
        let inhalt = Ziehinhalt.lesen(zwischen)
        #expect(inhalt.dateien.isEmpty && inhalt.links.isEmpty)
    }

    @Test("Nur Text, der wie eine Adresse aussieht, ist kein URL-Eintrag")
    func nurText() {
        let eintrag = NSPasteboardItem()
        eintrag.setString("https://example.org", forType: .string)
        let zwischen = ablage([eintrag])
        defer { zwischen.releaseGlobally() }
        let inhalt = Ziehinhalt.lesen(zwischen)
        #expect(inhalt.dateien.isEmpty && inhalt.links.isEmpty)
    }

    @Test("Gemischt: Datei und Link in einem Ziehen (E905)")
    func gemischt() throws {
        let datei = try probedatei()
        defer { try? FileManager.default.removeItem(at: datei.deletingLastPathComponent()) }
        let zwischen = ablage([try finder(datei), safari("https://example.org/a")])
        defer { zwischen.releaseGlobally() }
        let inhalt = Ziehinhalt.lesen(zwischen)
        #expect(inhalt.dateien.count == 1 && inhalt.links == ["https://example.org/a"])
    }
}
