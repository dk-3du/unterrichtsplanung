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

## [1.4.1 (41)] - 2026-09-09

Die Nachbesserung des Schlüssellebenszyklus: Ein Wechsel von Passphrase,
Datenschlüssel oder Wicklung erreicht jetzt jede Datei, die diese App
verwaltet — und die Lesezeichen fallen im versiegelten Zustand nie in den
Klartext zurück.

### Security

- **Passphrase ändern wickelt alles neu** — Bisher blieben der Behälter der
  Lesezeichen und die Statusdatei der Ansicht unter der alten Passphrase; mit
  ihr ließ sich der Datenschlüssel weiter entwickeln und die Planung öffnen.
  Jetzt bekommen Ablage, Nebendateien, Lesezeichen, Kopie außer Haus und
  Statusdatei die neue Hülle sofort; die alte Passphrase öffnet danach keine
  Datei mehr, die diese App schreibt.
- **Touch ID abschalten erreicht die Vorgängerfassung** — `planung-vorher.json`
  behielt die Wicklung dieses Macs. Jeder Wechsel der Hülle zieht jetzt alle
  Nebendateien über ein Register nach — auch die Rettungskopien.
- **Schlüssel erneuern verlangt eine neue Passphrase** — Bisher blieb die
  Passphrase beim Erneuern erhalten, obwohl es als Antwort auf eine verbrannte
  Passphrase empfohlen war. Übersicht und Blatt sagen, was Ändern und Erneuern
  leisten — und dass keines von beiden Kopien zurückholt, die vorher jemand
  mitgenommen hat.
- **Kein Klartext-Rückfall der Lesezeichen** — Lässt sich der Behälter nicht
  schreiben, bleibt der Vorrat in der Sitzung und wird beim nächsten Anlass
  erneut versiegelt; Einstellungen und Verschlüsselungs-Übersicht zeigen den
  Zustand, bis er behoben ist. Einschalten schreibt den Behälter vor der
  Ablage und findet ohne ihn nicht statt.
- **Verweise in Release-Notizen** — Links im Update-Blatt öffnen nur noch als
  http/https, wie der Download-Knopf.

### Fixed

- **Behälter der Lesezeichen wird nicht mehr überschrieben** — Ein Behälter,
  der sich nicht lesen ließ oder aus einer neueren Fassung stammt, bleibt
  unangetastet; der Vorrat ist bis zum nächsten Start gesperrt. Ein Behälter
  unter einem fremden Schlüssel wird als `lesezeichen-fremd-…` beiseitegelegt,
  ein beschädigter als `lesezeichen-beschaedigt-…` — erst dann wird neu
  angelegt. Der Rettungsweg über die Vorgängerfassung öffnet die Lesezeichen
  erst, wenn der Schlüssel der Sitzung feststeht.
- **Neue Planung im gesperrten Zustand** — Lag die Ablage von einer neueren
  Fassung versiegelt, wurde eine neue oder geöffnete Planung still verworfen
  und trotzdem Erfolg gemeldet. Jetzt sagt die App, warum nichts angelegt
  wird; eine Planungsdatei aus einer neueren Fassung bleibt unangetastet.
- **Kursdatei-Menü** — „Im Finder zeigen“ zeigte die Zugriffs-Rückfrage
  hinter dem offenen Blatt und blockierte Menüs.
- **Zielordner verloren** — Geht der Zielordner mit dem Behälter verloren,
  fragt die Nachwahl danach, und das Beenden merkt die ausgebliebene Kopie
  vor, statt still keine zu schreiben.
- **Passphrase aus Leerraum** — ließ sich anlegen, aber am Mac nicht
  eingeben; sie wird jetzt beim Anlegen abgewiesen.
- **Passphrase ändern, Schlüssel erneuern** — Ist die neue Passphrase die
  bisherige, sagt das Blatt es jetzt, statt nur den Knopf zu sperren.
- **Ansicht fürs iPad** — Der normale Rundlauf meldete jeden übernommenen
  Eintrag als „bereits neuer beantwortet und verworfen“, und ein tatsächlich
  überholter Eintrag blieb im Browserspeicher liegen und wurde bei jedem Öffnen
  erneut gemeldet — jetzt einmal, mit Vorhaben und beiden Zeitpunkten; ein
  Klartext-Altstand im Browserspeicher blieb bei verschlüsselter Planung liegen;
  ein fremder Behälterinhalt wurde erst nach der Passphrase benannt.

### Changed

- **Vormerkung eines Kopiefehlers** — trägt keinen Systemtext mit Datei- und
  Ordnernamen mehr in die Einstellungen; den Grund nennt „Jetzt schreiben“.
- **Leistung** — Mehrere gewählte oder hergezogene Dateien schreiben den
  Behälter der Lesezeichen einmal statt je Datei.

## [1.4.0 (40)] - 2026-09-08

Die Lesezeichen versiegelt: Bei eingeschalteter Verschlüsselung liegen die
gemerkten Orte des App Sandbox und der Zielordner der Sicherungskopie als
Behälter neben der Planung — unter demselben Datenschlüssel, nirgends mehr
im Klartext. Am Behälterformat, am Tresor und an der Ansicht ändert sich
nichts als die Nummer.

### Security

- **Lesezeichen und Zielordner versiegelt** — Die Lesezeichen mit
  Sicherheitsbereich (Materialien, Kursdateien, Ordner der Sicherungskopie)
  und der Pfad des Zielordners lagen bisher im Klartext in den Einstellungen
  des Containers. Ist die Verschlüsselung eingeschaltet, liegen sie jetzt als
  Behälter `lesezeichen.json` neben `planung.json`, versiegelt unter dem
  Datenschlüssel der Planung; die Einstellungen tragen dann keinen Pfad mehr.
  Bis zum Entsperren ist der Vorrat zu: Nichts ist zuständig, und nichts fragt
  vorher nach einem Ort.

### Changed

- **Übergänge** — Einschalten bringt die Lesezeichen aus den Einstellungen in
  den Behälter (zurückgelesen; misslingt es, bleibt der Klartext, und die
  Meldung sagt es), Erneuern schreibt den Behälter unter den neuen Schlüssel,
  Aufheben holt die Lesezeichen in die Einstellungen zurück und entfernt den
  Behälter; Passphrase ändern lässt ihn unangetastet. Beim ersten Start
  dieser Fassung hinter einer versiegelten Ablage wandert der bisherige
  Klartext-Vorrat nach dem Entsperren in den Behälter — die App sagt es
  einmal. Ein beschädigter oder fremd versiegelter Behälter wird als
  `lesezeichen-beschaedigt-<Stempel>.json` beiseitegelegt, benannt und leer
  neu angelegt; ein Fehlschlag beim Schreiben wird gemeldet, nicht verschluckt.
- **Ordnerzugriff je Ablage** — Der Vorrat der Lesezeichen ist kein
  prozessweiter Zustand mehr, sondern gehört zum Sicherungsdienst der Ablage;
  Prüfungen mit eigener Ablage haben ihren eigenen.
- **Prüfstand** — `--ordnertest` belegt an einer versiegelten Ablage, dass der
  Vorrat vor dem Entsperren zu ist, das neue Lesezeichen im Behälter liegt,
  die Einstellungen keinen Pfad tragen und ein zweiter Lauf derselben Ablage
  Lesezeichen und Zielordner ohne Nachwahl wiederfindet.

## [1.3.2 (39)] - 2026-09-08

Härtung nach einer externen Code-Review: Der Weg vom iPad zurück zur App
nimmt bei verschlüsselter Planung nur noch Beglaubigtes an, das Einschalten
der Verschlüsselung belegt sein Ergebnis auf der Platte, und die Dateileser
lesen nur noch, was eine veröffentlichte Fassung geschrieben hat. Am
Behälterformat, am Tresor und an der Oberfläche ändert sich nichts.

### Security

- **Status nur beglaubigt** — Ist die Planung verschlüsselt, nehmen App und
  Ansicht eine unverschlüsselte Statusdatei nicht mehr an: Sie wird benannt,
  nicht übernommen und nicht überschrieben. Eine Statusdatei ändert nichts
  mehr am Schlüsselkopf — Wicklungen aus ihr werden nicht übernommen.
- **Schlüsselableitung** — Die Rundenzahl wird an der tiefsten Stelle geprüft,
  an der kein Aufrufer vorbeikommt; ein Wahrheitswert gilt nicht als Fassung
  eines Behälters.

### Changed

- **Einschalten, Erneuern, Passphrase ändern** — Der Übergang läuft in fester
  Reihenfolge: erst den letzten Stand der Ansicht übernehmen, dann die Ablage
  schreiben und zurücklesen, dann Nebendateien, Kopie außer Haus und
  Statusdatei sofort nachziehen — nicht erst beim Beenden. Die Meldung kommt
  aus dem Ergebnis; lässt sich die Ablage nicht schreiben, bleibt alles beim
  Alten, und die Meldung sagt es.
- **Dateileser** — Eine Planungsdatei braucht Typ und Fassung 2, wie sie jede
  veröffentlichte Fassung schreibt; eine ältere wird benannt abgewiesen statt
  mit falschen Farben geöffnet, eine neuere nicht gedeutet. Eine Statusdatei
  braucht die Fassung 1. Zahlen gelten nur als Zahlen; die alten Feldnamen
  `basisordner` und `beschreibung` und die Übersetzung der alten Farbpalette
  entfallen — in App und Ansicht gleich (Abzugvergleich).
- **Entsperren** — Passphrase und Wiederherstellungsschlüssel werden abseits
  des Hauptstrangs abgeleitet; das Blatt bleibt bedienbar, ein verspätetes
  Ergebnis für ein anderes Ziel wird verworfen.
- **Ansicht** — Ein Schreibziel, das sich nicht lesen lässt oder keine
  Statusdatei ist, wird nicht überschrieben; ein Stand, der nicht gilt, wird
  mit Grund benannt. Der schlüssellose Altstand des Browserspeichers wird
  nicht mehr umgehängt.
- **Kleineres** — Lässt sich eine Datei nicht öffnen, sagt es die App; die
  vorgemerkte Warnung zur Sicherungskopie nennt keinen Pfad mehr; das
  Prüfziel von `swift test` arbeitet auch ohne `PLANUNGSORDNER` in einem
  eigenen Ordner. 409 Prüfungen in 47 Suiten, neue Suite „Schutzübergang“.

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
