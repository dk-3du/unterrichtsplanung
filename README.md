<!--
SPDX-FileCopyrightText: 2026 Dominik Kluge
SPDX-License-Identifier: GPL-3.0-or-later
-->

<p align="center">
<img height="256" src="https://github.com/dk-3du/unterrichtsplanung/blob/main/AppIcon/Unterrichtsplanung-AppIcon-macOS-Default-512x512@1x.png">
</p>

<h1 align="center">Unterrichtsplanung</h1>

<p align="center">Unterricht planen, weitere Vorhaben organisieren und passende Lehr- und Lernmaterialien kuratieren</p>

<p align="center">
· <a href="https://github.com/dk-3du/unterrichtsplanung/releases">Releases</a> ·
</p>

---

# Unterrichtsplanung

*Unterrichtsplanung* ist eine Jahresplanung im Wochenraster für Lehrkräfte:
eine native macOS-App (Swift/SwiftUI, macOS 26 auf Apple Silicon, ohne fremden
Code), in der Unterricht und weitere Vorhaben Woche für Woche geplant und die
passenden Lehr- und Lernmaterialien kuratiert werden — Verweise auf Dateien und
Ordner sowie Weblinks je Vorhaben, eine Verwaltungs- und eine Curriculumdatei
je Klasse und Kurs —, dazu eine rein lesende Ansicht fürs iPad, die eine
exportierte Planung anzeigt und Haken und Kommentare an die App zurückgibt.

Das Raster zeigt die Kalenderwochen des Schuljahres als Spalten und die Klassen
und Kurse als Zeilen; Ferien, freie Tage und Sperrzeiträume sind darin
eingetragen. Ein Vorhaben besteht aus Titel und Beschreibung und kann einen
Wochentag oder ein Datum, eine Dringlichkeit oder einen Prüfungstermin tragen.
Eine Suche, eine Liste der heute anstehenden Vorhaben und ein blattweiser
Ausdruck ergänzen das Raster.

Alle Daten bleiben auf dem Mac. Die Planung lässt sich mit AES-256
verschlüsseln — auf dem Mac über Touch ID oder das Anmeldepasswort (Secure
Enclave), überall sonst über eine Passphrase, für den Notfall über einen
gedruckten Wiederherstellungsschlüssel. Die App läuft im App Sandbox von macOS
und erreicht Dateien und Ordner nur dort, wo sie ihr einmal gezeigt wurden; bei
eingeschalteter Verschlüsselung liegen auch diese Lesezeichen versiegelt neben
der Planung. Eine freiwillige, wöchentliche Prüfung auf Updates gegen die
Releases dieses Repositorys überträgt nur die IP-Adresse, die Versionsnummer
der App und ein ETag und lädt oder installiert nie etwas von selbst.

## Bauen, prüfen, weitergeben

Die macOS-App (`macOS-App/v43/`) ist in Swift und SwiftUI geschrieben, für
macOS 26 auf Apple Silicon und ohne fremde Bibliothek. `./bauen.sh` baut sie
(Xcode wird gebraucht; `--dmg` schnürt zusätzlich ein Abbild),
`PLANUNGSORDNER=$(mktemp -d) swift test` prüft sie. Weitergegeben wird ein mit
Developer ID signiertes und von Apple beglaubigtes Abbild (`./beglaubigen.sh`)
unter **Releases**. Dort liegt auch die Ansicht als Datei mit ihrer
SHA-256-Prüfsumme, damit sich die Seite im Netz prüfen lässt:
`curl -s https://3ducation.org/upapp/index.html | shasum -a 256` muss die
Zeile im Release ergeben. Gelesen werden Planungsdateien ab Version 1.2.3;
eine ältere öffnet man einmal mit einer früheren Fassung und sichert sie. Was
sich je Fassung ändert, steht in [`CHANGELOG.md`](CHANGELOG.md).

**Lizenzen.** Freie Software: die macOS-App und alles Übrige unter der GNU
General Public License, Version 3 oder neuer ([`LICENSE`](LICENSE)), die
Ansicht unter der GNU Affero General Public License, Version 3 oder neuer
([`Web-App/v43/LICENSE.txt`](Web-App/v43/LICENSE.txt)). Die Zuordnung je Datei
steht in [`REUSE.toml`](REUSE.toml), die Lizenztexte liegen in
[`LICENSES/`](LICENSES/). © 2026 Dominik Kluge. Erstellt mit Claude Code
(Opus 5 & Fable 5/5.1).

**Aufbau.** Je Fassung ein eigener, für sich baubarer Ordner (`macOS-App/v43/`,
`Web-App/v43/`; ältere Fassungen bleiben daneben stehen); die Nummer im
Ordnernamen ist der Build der Version. Was sich je Fassung ändert, steht in
[`CHANGELOG.md`](CHANGELOG.md). Oberfläche und
Dokumentation sind deutsch.

---

**English.** *Unterrichtsplanung* is a year-at-a-glance planner for teachers:
a native macOS app (Swift/SwiftUI, macOS 26 on Apple Silicon, no third-party
code) in which lessons and other projects are planned in a week grid and the
matching teaching and learning materials are curated — file and folder
references and web links per item, administrative and curriculum documents per
course —, plus a read-only web view for the iPad that displays an exported plan
and hands check marks and comments back to the app. All data stays on the Mac.
Plans can be encrypted with AES-256 (Touch ID or the login password via the
Secure Enclave, a passphrase elsewhere, a printed recovery key for
emergencies); the app runs in the macOS App Sandbox and reaches files and
folders only where the user has pointed it once; an optional weekly update
check against this repository's releases transmits only the IP address, the
app's version number and an ETag and never downloads or installs anything by
itself. The user interface and all documentation are in German. Free software:
the macOS app and everything else is licensed under the GNU GPL v3 or later,
the web view under the GNU AGPL v3 or later (see `LICENSE`, `LICENSES/`,
`REUSE.toml`). Signed and notarized disk images are published under
*Releases*. Created with Claude Code.
