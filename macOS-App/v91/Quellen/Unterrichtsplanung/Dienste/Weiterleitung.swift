// SPDX-FileCopyrightText: 2026 Dominik Kluge
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Die Regel für Weiterleitungen auf beiden Netzwegen der App — Prüfung auf
/// Updates und Materialliste: Die Erlaubnis des Nutzers gilt einem Rechner.
/// Eine Weiterleitung wird deshalb nur verfolgt, wenn sie über https beim
/// selben Rechner und Anschluss bleibt und keine Zugangsdaten trägt. Alles
/// andere wird verweigert, **bevor** die Anfrage hinausgeht; dem Lader bleibt
/// die Antwort 3xx, und die ist für ihn „nicht erreichbar“.
enum Weiterleitung {
    /// `von` ist die Adresse der ersten Anfrage, nicht die der letzten Station —
    /// eine Kette kann sich so nicht Schritt für Schritt entfernen.
    static func erlaubt(von: URL?, nach: URL?) -> Bool {
        guard let von, let nach,
              von.scheme?.lowercased() == "https", nach.scheme?.lowercased() == "https",
              let quelle = von.host()?.lowercased(), !quelle.isEmpty,
              let ziel = nach.host()?.lowercased(), ziel == quelle,
              (von.port ?? 443) == (nach.port ?? 443),
              nach.user() == nil, nach.password() == nil
        else { return false }
        return true
    }

    /// Der Delegat je Auftrag. Ohne Zustand, also für jeden Auftrag derselbe.
    final class Waechter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            Weiterleitung.erlaubt(von: task.originalRequest?.url, nach: request.url) ? request : nil
        }
    }

    static let waechter = Waechter()
}
