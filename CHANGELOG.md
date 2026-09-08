<!--
SPDX-FileCopyrightText: 2026 Dominik Kluge
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Changelog

Alle nennenswerten Änderungen an der Unterrichtsplanung — macOS-App und
Ansicht fürs iPad — stehen in dieser Datei. Das Format folgt
[Keep a Changelog](https://keepachangelog.com/de/1.1.0/); die Versionsnummer
ist Apples Zählung „Version (Build)“, der Build ist zugleich die Nummer des
Fassungsordners (`macOS-App/v35`, `Web-App/v35`).

Die Fassungen vor 1.2.3 (33) wurden nicht veröffentlicht, sondern
ausschließlich intern entwickelt; sie sind in diesem öffentlichen Changelog
deshalb nicht dokumentiert. Es beginnt mit der ersten Fassung, die unter der
GNU GPL (macOS-App) und der GNU AGPL (Ansicht fürs iPad) freigegeben ist.

## [1.3.1 (38)] - 2026-09-07

Innerer Umbau des Quelltextes, ohne Änderung am Verhalten: Am Dateiformat, am
Tresor, an der Oberfläche und an der Ansicht fürs iPad ändert sich nichts.

### Changed

- **Aufteilung des Speichers** — Der Planungsspeicher besteht aus einer
  Hauptdatei und zwölf Erweiterungen je Abschnitt. Der Sitzungszustand — leer,
  gesperrt, Klartext, verschlüsselt — ist ein einziger Wert mit einer
  Serialisierungsgrenze; unmögliche Kombinationen (Planung ohne Schlüssel bei
  eingeschalteter Verschlüsselung) gibt es darin nicht. Die Ablage versiegelt
  weiter allein, bekommt den Schlüssel aber je Schreibvorgang mit, statt ihn
  zu halten.
- **Dienste** — Die laufende Sicherung samt Kopie außer Haus, der Abgleich mit
  der Statusdatei der iPad-Ansicht und die Prüfung auf Updates sind eigene
  Typen mit hereingereichter Ablage; `Ablage.shared` kennt nur noch der
  Anwendungsdelegat, Prüfungen arbeiten mit einem Temp-Ordner.
- **Prüfstände** — Ein Verteiler (`App/Pruefstaende.swift`) liest die
  Argumente einmal, prüft die Schranke einmal und ruft genau einen Prüfstand
  (`--mischtest` geht `--abbild` vor); die Prüfstände liegen nach Aufgaben in
  eigenen Dateien und laufen weiter gegen den signierten Bau. 402 Prüfungen
  in 46 Suiten (neu: Sitzungszustand, Dienste, Verteiler).

## [1.3.0 (37)] - 2026-09-07

Die App läuft im App Sandbox von macOS. Am Dateiformat, am Tresor und an der
Ansicht fürs iPad ändert sich nichts.

### Added

- **App Sandbox** — Von sich aus liest und schreibt die App nur noch ihre
  eigenen Dateien. Auf alles andere — Materialien, Kursdateien, den Ordner
  der Sicherungskopie — darf sie erst zugreifen, wenn es ihr einmal gezeigt
  wurde: über „Datei wählen …“, „Ordner wählen …“ oder Ziehen aus dem Finder.
  Die Wahl wird als Lesezeichen gemerkt; ein Ordner gilt für alles darin. Ein
  Ort, der noch nicht gezeigt wurde, fragt beim Öffnen nach der Auswahl.
- **Nachwahl nach dem Update** — Beim ersten Start fragt die App einmal nach
  den Ordnern, die sie bisher benutzt hat (Sicherungskopie, Basisordner der
  Materialien), und erklärt, warum. „Später“ ist möglich; die Frage kommt beim
  nächsten Start wieder, bis die Ordner gewählt sind.
- **Prüfstände** — `--container` nennt den Container der App, `--ordnertest`
  belegt die Lesezeichen im Sandbox, `--abbild --dialog nachwahl` zeigt das
  Blatt. Prüfstände arbeiten nur noch unterhalb des Containers; ein Abbild mit
  Ziel außerhalb wandert in den Prüfordner. 385 Prüfungen in 43 Suiten.

### Changed

- **Ablage** — Die laufende Sicherung liegt im Container der App
  (`~/Library/Containers/org.3ducation.Unterrichtsplanung/Data/Library/Application Support/Unterrichtsplanung/`);
  beim ersten Start dieser Fassung ziehen Planung und Einstellungen von selbst
  dorthin um.
- **Berechtigungen** — neben dem Sandbox: vom Nutzer gewählte Dateien und
  Ordner, Lesezeichen mit Sicherheitsbereich, Netz nur für die Prüfung auf
  Updates, Drucken. `bauen.sh` und `beglaubigen.sh --probe` prüfen, dass das
  Sandbox in der Signatur steht.

### Removed

- **„Pfad einfügen“** im Vorhaben-Dialog — ein eingetippter Pfad gewährt im
  Sandbox keinen Zugriff. Materialien kommen über „Datei wählen …“, „Ordner
  wählen …“ und Ziehen hinzu.

## [1.2.6 (36)] - 2026-09-07

Behebungen nach einer externen Code-Review von 1.2.5 (35); am Dateiformat
und am Tresor ändert sich nichts.

### Fixed

- **Ansicht fürs iPad** — eine abgewiesene Planungsdatei ließ die geöffnete,
  verschlüsselte Planung ohne Schlüssel zurück: Haken und Kommentare wären ab
  dann im Klartext gemerkt und geschrieben worden. Jetzt wird eine Datei erst
  vollständig gelesen und geprüft; Planung und Schlüssel wechseln nur zusammen.
- **Verschlüsselte Dateien** — ein Kopf mit einer Rundenzahl außerhalb des
  darstellbaren Bereichs (etwa `1e100`) beendete die App beim Öffnen; jetzt
  gilt er als beschädigt. Dieselbe Schranke greift bei „Passphrase ändern“.
- **Versiegeln der Nebendateien** — was sich beim Einschalten der
  Verschlüsselung, beim Erneuern des Schlüssels oder beim Ändern der
  Passphrase nicht versiegeln ließ, wird benannt statt übergangen; beim
  nächsten Start holt die App es nach und meldet, was übrig bleibt.
- **Materialien öffnen** — ein Alias wird einmal aufgelöst, geprüft und genau
  so geöffnet; ein Alias, der sich nicht auflösen lässt, wird abgewiesen.
- **Statusdatei** — App und Ansicht prüfen die Fassung der Datei: Fehlt sie,
  gilt der Altbestand; `1` wird gelesen; alles andere wird benannt und weder
  gelesen noch überschrieben.

### Changed

- **Repository** — `beglaubigen.sh` und die Prüf- und Abgleichskripte der
  Ansicht liegen je Fassung bei, auch für 1.2.3 und 1.2.5.
- **Prüfungen** — 372 in 42 Suiten; `leser_pruefen.py` hält zusätzlich die
  Fassung der Statusdatei in beiden Lesern gegeneinander.

## [1.2.5 (35)] - 2026-09-06

### Added

- **Prüfung auf Updates** — auf Wunsch sieht die App beim Öffnen nach, ob
  unter *Releases* dieses Repositorys eine neuere Fassung liegt, und zeigt
  dann ein Blatt mit den Release-Notizen und dem Weg zur Release-Seite;
  geladen oder installiert wird nichts von selbst. Nur mit Einwilligung: als
  dritte Frage der Ersteinrichtung, für bestehende Planungen einmal als
  eigenes Blatt, jederzeit unter „Einstellungen → Updates“; höchstens einmal
  je Woche. Von Hand über „Nach Updates suchen …“ im Menü „Unterrichtsplanung“.
- **Was dabei übertragen wird** — eine Anfrage an api.github.com (GitHub,
  Inc., USA) mit der IP-Adresse, der Versionsnummer der App und dem
  Kennzeichen der zuletzt gesehenen Antwort (ETag); keine Planungsdaten, keine
  Gerätekennung, keine Cookies. Ausgeschaltet geht beim Öffnen nichts ins Netz.
- **Prüfstände** — `--updatetest` (Befund gegen die Schnittstelle oder eine
  Datei aus `UPDATE_QUELLE`), `--abbild --dialog update|updateNachfrage`,
  `ABBILD_SCHRITT=updates`; 367 Prüfungen in 41 Suiten.

### Changed

- **Ersteinrichtung** — drei Fragen: Verschlüsselung, Sicherungskopie, Updates.
- **Einstellungen** — Abschnitt „Updates“ mit Schalter, „Zuletzt geprüft“,
  „Jetzt suchen“ und dem Ergebnis der letzten Prüfung.
- **Beipackzettel und Kurzanleitung** nennen die Prüfung und was sie überträgt.
- **Ansicht fürs iPad** — unverändert bis auf die Versionsnummer.

## [1.2.3 (33)] - 2026-09-05

Erste Veröffentlichung unter GPL-3.0-or-later (macOS-App) und
AGPL-3.0-or-later (Ansicht fürs iPad).

### Added

- **Jahresplanung im Wochenraster** — native macOS-App (Swift/SwiftUI,
  macOS 26, Apple Silicon, ohne fremde Bibliothek): Kalenderwochen als
  Spalten, Klassen und Kurse als Zeilen, Vorhaben als Kacheln je Zelle;
  Schulwochen-Zählung („KW X / Y. Schulwoche“) ab dem ersten Schultag.
- **Planungsdateien** — neue Planung mit Zeitraum, Wochenzahl, erstem
  Schultag und Klassen/Kursen aus einer Standardliste, wahlweise mit Übernahme
  aus der aktiven Planung; Öffnen und Sichern als JSON (`⌘O`, `⌘S`),
  Klartext-Export mit Rückfrage (`⌥⌘S`); laufende Sicherung auf dem Rechner
  samt Vorgängerfassung.
- **Klassen, Kurse und Fächer** — Fächer mit Fachfarben, Farbe je Zeile aus
  einer Palette von 24 Farben, Unterrichtstage je Klasse/Kurs, Verwaltungs-
  und Curriculumdatei je Kurs.
- **Vorhaben** — Titel, Wochentag und Datum, Dringlichkeit, Haken
  „durchgeführt“ und Kommentar; anlegen, kopieren, verschieben und ziehen (auch mehrere),
  Reihenfolge in der Zelle, Titel direkt ändern, Suche (`⌘F`).
- **Materialien kuratieren** — je Vorhaben Verweise auf Dateien und Ordner
  über einen Basisordner sowie Weblinks; je Klasse/Kurs eine Verwaltungs- und
  eine Curriculumdatei, aus der Kursspalte zu öffnen.
- **Ferien und unterrichtsfreie Zeiten** — Ferienzeiträume, Sperrzeiträume
  je Kurs, ganze Wochen oder einzelne Zellen unterrichtsfrei.
- **Überblicke** — alle Prüfungen chronologisch und kursübergreifend, die
  heute anstehenden Vorhaben zum Abhaken (`⌘D`), Sprung zur laufenden Woche
  (`⌘J`), Spaltenbreite in drei Stufen, Hell/Dunkel/Systemvorgabe.
- **Drucken und PDF** — blattweiser Ausdruck des Rasters und Export als
  PDF.
- **Verschlüsselung** — AES-256-GCM über einen zufälligen Datenschlüssel,
  der in drei Wicklungen im Kopf jeder Datei liegt: Secure Enclave dieses
  Macs (Touch ID oder Anmeldepasswort), Passphrase (PBKDF2) und gedruckter
  Wiederherstellungsschlüssel; Freigabe beim Start wie bei iWork; Passphrase
  ändern, Schlüssel erneuern, Verschlüsselung aufheben; die Ersteinrichtung
  fragt zuerst nach der Verschlüsselung, dann nach der Sicherungskopie. Kein
  Geheimnis liegt irgendwo im Klartext.
- **Sicherungskopie beim Beenden** — eine Kopie der Planung in einen Ordner
  der Wahl (etwa iCloud Drive), ausschließlich verschlüsselt; Haken und
  Kommentare aus der Ansicht kommen über die Statusdatei versiegelt zurück.
- **Hilfe** — Tour durch die Oberfläche, Kurzanleitung, Über-Dialog mit
  Lizenz und Adresse des Quelltextes.
- **Ansicht fürs iPad** — eine einzige HTML-Datei ohne Abhängigkeiten
  (<https://3ducation.org/upapp/>): öffnet die verschlüsselte Kopie mit der
  Passphrase (Web Crypto), zeigt die Planung als Raster oder Liste, nimmt
  Haken und Kommentare je Vorhaben entgegen und schreibt die Statusdatei
  versiegelt zurück (Teilen, verbundene Datei oder Download); blattweiser
  Ausdruck; Content Security Policy mit Hashes; Info-Blatt mit Lizenz und
  Quelltext.
- **Weitergabe** — mit Developer ID signiert und von Apple beglaubigt; Abbild
  (DMG) mit Lizenztext und Beipackzettel; `bauen.sh` und `beglaubigen.sh`;
  346 Prüfungen in 39 Suiten sowie Abgleichskripte, die App und Ansicht
  gegeneinander halten (`masse_pruefen.py`, `abzug_pruefen.py`,
  `tresor_pruefen.py`, `csp_hashes.py`, `schulwochen_pruefen.py`,
  `leser_pruefen.py`, `weblinks_pruefen.py`).
