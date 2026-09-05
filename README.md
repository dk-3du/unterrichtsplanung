<!--
SPDX-FileCopyrightText: 2026 Dominik Kluge
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Unterrichtsplanung

Jahresplanung im Wochenraster für Lehrkräfte, mit Blick auf Datensicherheit:
eine native **macOS-App**, in der geplant wird und Lehr- und Lernmaterialien
kuratiert werden, und eine rein lesende **Ansicht fürs iPad**, die eine
exportierte Planung anzeigt und Haken und Kommentare zur App zurückreicht.

- **macOS-App** (`macOS-App/v35/`): Swift und SwiftUI, macOS 26 auf Apple
  Silicon, ohne fremde Bibliothek. Bauen mit `./bauen.sh` (Xcode wird
  gebraucht; `./bauen.sh --dmg` schnürt zusätzlich ein Abbild), Prüfungen mit
  `PLANUNGSORDNER=$(mktemp -d) swift test`. Weitergegeben wird ein mit
  Developer ID signiertes und von Apple beglaubigtes Abbild — zu finden unter
  **Releases** dieses Repositorys.
- **Materialien kuratieren:** je Vorhaben Verweise auf Dateien und Ordner
  (über einen Basisordner) und Weblinks; je Klasse/Kurs eine Verwaltungs- und
  eine Curriculumdatei, aus der Kursspalte zu öffnen.
- **Ansicht fürs iPad** (`Web-App/v35/`): eine einzige HTML-Datei, im Netz
  unter <https://3ducation.org/upapp/>; sie ist ihr eigener Quelltext.
- **Verschlüsselung:** Die Planung lässt sich mit AES-256 versiegeln — auf
  dem Mac über Touch ID oder das Anmeldepasswort (Secure Enclave), überall
  sonst über eine Passphrase, für den Notfall über einen gedruckten
  Wiederherstellungsschlüssel. Kein Geheimnis liegt irgendwo im Klartext.
- **Updates:** Auf Wunsch sieht die App beim Öffnen nach, ob unter
  **Releases** eine neuere Fassung liegt — nur mit Einwilligung (Frage bei der
  Ersteinrichtung, Schalter unter „Einstellungen“), höchstens einmal je Woche;
  von Hand über „Nach Updates suchen …“. Übertragen werden dabei die
  IP-Adresse, die Versionsnummer der App und das Kennzeichen der zuletzt
  gesehenen Antwort (ETag), sonst nichts; geladen oder installiert wird nichts
  von selbst.

**Lizenzen.** Freie Software: die macOS-App und alles Übrige unter der GNU
General Public License, Version 3 oder neuer ([`LICENSE`](LICENSE)), die
Ansicht unter der GNU Affero General Public License, Version 3 oder neuer
([`Web-App/v35/LICENSE.txt`](Web-App/v35/LICENSE.txt)). Die Zuordnung je Datei
steht in [`REUSE.toml`](REUSE.toml), die Lizenztexte liegen in
[`LICENSES/`](LICENSES/). © 2026 Dominik Kluge. Erstellt mit Claude Code
(Opus 5 & Fable 5/5.1).

**Aufbau.** Je Fassung ein eigener, für sich baubarer Ordner (`macOS-App/v35/`,
`Web-App/v35/`; ältere Fassungen bleiben daneben stehen); die Nummer im
Ordnernamen ist der Build der Version. Was sich je Fassung ändert, steht in
[`CHANGELOG.md`](CHANGELOG.md). Oberfläche und
Dokumentation sind deutsch.

---

**English.** *Unterrichtsplanung* („lesson planning“) is a year-at-a-glance
planner for teachers with a focus on data security: a native macOS app
(Swift/SwiftUI, macOS 26 on Apple Silicon, no third-party code) in which the
planning is done and teaching and learning materials are curated (file and
folder references and web links per item, administrative and curriculum
documents per course), plus a read-only
web view for the iPad that displays an exported plan and hands check marks
and comments back to the app. Plans can be encrypted with AES-256 — on the
Mac via Touch ID or the login password (Secure Enclave), elsewhere via a
passphrase, with a printed recovery key for emergencies. An optional, weekly
update check against this repository's releases can be enabled (opt-in); it
transmits only the IP address, the app's version number and an ETag, and it
never downloads or installs anything by itself. The user interface
and all documentation are in German. Free software: the macOS app and
everything else is licensed under the GNU GPL v3 or later, the web view under
the GNU AGPL v3 or later (see `LICENSE`, `LICENSES/`, `REUSE.toml`). Signed
and notarized disk images are published under *Releases*. Created with
Claude Code.
