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

## [1.5.0 (50)] - 2026-09-12

Die Kurszelle: Was an einer Klasse oder einem Kurs hängt — Verwaltungsdatei,
Curriculum, Sitzplan —, steht in der Zeile des Rasters, hinterlegt oder als
Angebot. Dazu die Behebungen nach der zweiten externen Review (an 1.4.9): die
Rücknahme nach einem gescheiterten Aufheben, Klartext-Sitzpläne neben der
versiegelten Planung, die Grenzen des PDF-Kennworts, die Ansicht beim
Planungswechsel, die Sitzplandatei und der Prüfvermerk.

### Fixed

- **Rücknahme nach dem Aufheben:** Scheitert das Aufheben der Verschlüsselung,
  nachdem die Sitzpläne vorab im Klartext lagen, gilt für sie der versiegelte
  Zustand weiter — auch wenn das erneute Versiegeln scheitert: Der Stand gilt
  für die Sitzung, die App versiegelt beim nächsten Schreiben, beim Beenden
  und beim nächsten Start, die Klartextdatei wird entfernt, und die Meldung
  nennt die Sitzpläne. Bisher fiel der Dienst in den Klartext-Modus zurück und
  schrieb bis zum nächsten Start Klartext, ohne es zu sagen. (B17)
- **PDF-Kennwort:** Der Sichern-Dialog weist ein Kennwort mit Zeichen außerhalb
  von ASCII oder mit mehr als 32 Zeichen ab und sagt warum — der
  Kennwortschutz des PDF-Formats nimmt nichts anderes; bisher scheiterte die
  PDF ohne Grund oder das Kennwort galt nur bis zum 32. Zeichen. (B18, E45)
- **Ansicht fürs iPad:** Die Wiederaufnahme aus dem Browserspeicher gehört der
  Planung, für die sie begann — eine zweite Datei, während sie wartete, bekommt
  nichts davon; ein Schreiben in die verbundene Datei, das während des
  Schreibens überholt wurde, wird verworfen statt abgeschlossen. (B22)
- **Sitzplandatei:** Ein Plan, dessen Tischliste keine Liste ist, wird
  verworfen und gezählt, nicht still zum leeren Plan; scheitert die
  Rettungskopie eines verlustbehaftet gelesenen Originals, geht nichts
  darüber, bis die Kopie liegt — der Stand gilt für die Sitzung, der
  Beenden-Wächter greift. (B23, E46)
- **Prüfvermerk:** `pruefen.sh` benennt den Vermerk erst nach dem letzten
  Schritt und trägt Profil und Ergebniszeile; `beglaubigen.sh --probe` nennt
  einen abgebrochenen oder verkürzten Lauf beim Namen, und `--ja` reicht nur
  mit vollständigem Vermerk ohne Befund zum Stand der Quellen ein —
  `--ohne-pruefung` umgeht das ausdrücklich und wird protokolliert. (B19, B24,
  E44)

### Added

- **Kurszelle mit drei Zeilen, immer:** Unter Klasse, Fach und Notiz stehen
  Verwaltungsdatei, Curriculum und Sitzplan — hinterlegt mit Symbol und Name,
  sonst als Angebot „+ Verwaltungsdatei“, „+ Curriculum“, „+ Sitzplan“ in
  leiser Schrift. Ein Klick auf ein Angebot öffnet den Dateiwähler bzw. den
  Sitzplan-Editor; ein Klick auf „Sitzplan“ öffnet den Editor, das
  Rechtsklickmenü sichert die PDF oder entfernt den Plan mit Rückfrage; das
  Rechtsklickmenü einer hinterlegten Datei kann jetzt auch eine andere Datei
  wählen. Der Weg über „Klassen/Kurse und Fächer“ (⌘K) bleibt. (E34, E35, E36)
- **Tour:** eine siebte Karte „Die Kurszelle“ nach „Die Planung einrichten“,
  am ersten Klassenkopf des Rasters; findet die Tour keinen, hängt die Karte
  am Werkzeug „Klassen/Kurse“.
- **Klartext-Sitzpläne neben der versiegelten Planung** übernimmt die App
  nicht mehr stillschweigend: Beim Entsperren fragt sie, ob sie versiegelt
  oder beiseitegelegt werden; Beiseitegelegtes liegt als
  `sitzplaene-unerwartet-<Stempel>.json` neben der Planung. (B21, E43)

### Changed

- Die Zeile einer Klasse ohne hinterlegte Dateien wird höher: Drei Zeilen zu
  22 pt kommen zum Kopf hinzu, bei zehn Klassen bis zu 660 pt mehr Rollweg —
  die Folge der drei Zeilen, immer (E34).
- Prüfstände: `--klicktest` klickt „+ Sitzplan“ in der Kurszelle und prüft die
  Rückfrage beim Entfernen, `--tourtest` zählt sieben Karten; Abbilder der
  Kurszelle hell und dunkel und der siebten Karte; 529 Prüfungen in 53
  Suiten, `leser_pruefen.py` mit vier weiteren jsc-Fällen.
- Ein abgebrochener Schutzübergang bleibt das benannte Restrisiko aus 1.4.9
  (E37, E42); ein Übergabestand mit Generationen ist für 1.5.1 vorgemerkt.

## [1.4.9 (49)] - 2026-09-12

Behebungen nach den beiden Reviews an 1.4.8 — der internen (B01–B08) und der
externen (F01–F08, nachgeprüft als B09–B16): die Übergänge des Schutzes rund
um die Sitzpläne symmetrisch und ehrlich, das Beenden wachsam, die Lesebilanz
sichtbar, Tastatur und Werkzeuge nachgezogen. Dazu der Kennwortschutz der
Sitzplan-PDF.

### Fixed

- **Aufheben der Verschlüsselung** legt die Sitzpläne zuerst im Klartext hin;
  scheitert das, bleibt alles, wie es ist — Schlüssel, Behälter, Sitzung.
  Bisher blieb ein Behälter, der nicht in den Klartext kam, unter einem
  Schlüssel liegen, den es danach nicht mehr gab, und der nächste Start legte
  ihn als „fremd“ beiseite. Sind die Sitzpläne gerade nicht lesbar, wird das
  Aufheben abgewiesen und auf einen Neustart verwiesen. (B02, E38)
- **Rücknahmen** beim Ein- und Ausschalten nennen die Sitzpläne, wenn ihr
  Rückweg in den Klartext scheitert; die Meldung nach einem gescheiterten
  Schreiben verspricht den nächsten Start nur, wenn die Datei auf der Platte
  dazu passt. (B02)
- **Einschalten aus dem Klartext** wird von gesperrten Sitzplänen oder
  Lesezeichen nicht mehr abgewiesen: Die Datei bleibt liegen und wird beim
  nächsten Start versiegelt; beim Erneuern bleibt die Abweisung. (B03)
- **„Nachgeholt“** meldet das Versiegeln nur, wenn es gelang. (B05)
- **Nebendateien unter einer älteren Hülle** (Passphrase geändert, während
  ihr Schreiben scheiterte) werden beim nächsten Start nachgezogen —
  Lesezeichen und Sitzpläne; bis dahin sagt die Meldung, dass die bisherige
  Passphrase die Datei noch öffnet. (B09, extern F01)
- **Beenden:** Ein Sitzplan, den die Platte nicht trägt, hält das Beenden auf
  wie eine ungesicherte Planung; „Jetzt sichern“ und das Beenden holen ihn
  nach. (B10, extern F02)
- **Namensliste:** Jeder Zeilenwechsel trennt (auch `\r` und U+2028); ein
  eingesetzter Absatz wird beim Umbenennen eine Zeile. (B01)
- **Lesen der Sitzplandatei:** Was das Lesen wegnimmt oder kürzt, wird
  gemeldet, und das Original liegt als `sitzplaene-bereinigt-<Stempel>.json`
  daneben; ein unlesbarer Zeitstempel wird geleert. (B14, extern F06; H01)
- **Editor:** ⏎ übernimmt verlässlich (über die Fläche, nicht über die
  Responder-Kette), ⌫/⌦ entfernt die Auswahl, ⌥⏎ benennt um; ein Tisch über
  dem Lehrertisch ist das, was der Klick trifft; in der Listenphase sagen ⌘P
  und ⇧⌘P, dass noch nichts zu drucken ist. (B06, B07, B08, H04)
- **Ansicht fürs iPad:** Das Schreiben in die verbundene Statusdatei und das
  Versiegeln für den Browserspeicher gehören der Planung, dem Schlüssel und
  der Verbindung, mit denen sie begannen — ein Planungswechsel oder eine
  Neuverbindung währenddessen bleibt unberührt. (B13, extern F05)
- Die Meldung im Vorhaben-Dialog, wenn nichts eingetragen ist, passt zur
  Regel: Titel, Beschreibung, Material oder Link. (H03)

### Added

- **Kennwortschutz der Sitzplan-PDF:** Im Sichern-Dialog lässt sich die PDF
  mit einem Kennwort schützen — Kennwort und Wiederholung, vorgewählt bei
  eingeschalteter Verschlüsselung; der Standard-Kennwortschutz des
  PDF-Formats, den Vorschau und andere Leser abfragen. (E40)
- **Verwaiste Sitzpläne** — Pläne, deren Klasse die Planung nicht kennt —
  räumt die App beim Laden einer Planung auf und bewahrt sie als
  `sitzplaene-verwaist-<Stempel>.json` im Register der Nebendateien. (B04, E41)
- **`pruefen.sh`:** alle Prüfungen vor dem Bau in einem Lauf — `swift test` im
  eigenen Prüfordner, die Skripte der Ansicht — mit Vermerk
  `Paket/Pruefung-<Stempel>.txt` und dem Stand der Quellen; `beglaubigen.sh
  --probe` weist hin, wenn der Vermerk fehlt, nicht zum Stand passt oder
  einen Befund trägt. (B16, extern F08; E39)

### Changed

- Die Prüfskripte der Ansicht geben jedem Kindprozess eine Frist (jsc,
  swiftc) — ein hängender Lauf hält die Prüfung nicht ewig. (B15, extern F07)
- Prüfstand `--sitzplantest` prüft ⌫, ⌥⏎ und ⏎ — ein Rückfall über den
  Speicher ist ein Befund; `leser_pruefen.py` mit Fällen zum Schreiben in die
  Zieldatei und zum Planungswechsel; 520 Prüfungen in 53 Suiten.
- Ein abgebrochener Schutzübergang — die App stirbt zwischen zwei
  Schreibvorgängen — bleibt ein benanntes Restrisiko (E37): Die Planung bleibt
  heil, die Nebendateien werden beim nächsten Start beiseitegelegt, und die
  Meldung nennt den Fall samt Rettungskopie. Dokumentiert unter „Datenschutz“.

## [1.4.8 (48)] - 2026-09-12

Sitzplan — Jede Klasse und jeder Kurs kann einen Sitzplan tragen: Namen als
Liste eingeben, Tische entstehen in Reihen und lassen sich frei verschieben,
die Tafel steht unten, eine PDF DIN A4 quer kommt heraus. Nur in der
macOS-App; die Ansicht fürs iPad zeigt keine Sitzpläne und zieht nur in der
Nummer mit.

### Added

- **Sitzplan je Klasse und Kurs** — in „Klassen/Kurse und Fächer“ (⌘K) als
  dritte Spalte neben Verwaltungsdatei und Curriculum (der Stuhl): anlegen,
  bearbeiten, als PDF sichern, entfernen. Der Editor ist ein breites Blatt:
  Zuerst die Namensliste (eine Zeile je Name, höchstens 35, je Name höchstens
  100 Zeichen), dann die Fläche — Tische in Reihen zu acht von der Tafel weg,
  ab dem 33. Namen eine fünfte Reihe, dazu ein Lehrertisch vorn seitlich neben
  der Tafel. Das Raster fasst zehn Plätze je Reihe, die Anfangsanordnung belegt
  die mittleren acht — so lassen sich bis zu zwei Gänge aussparen. Ziehen verschiebt einen Tisch oder alle angewählten, die rechte
  Maustaste zieht eine Bereichsauswahl auf und öffnet kurz gedrückt das Menü
  (Umbenennen, Entfernen), Doppelklick benennt um, Pfeiltasten verschieben um
  8 Punkt (⇧ um 1), „Tisch hinzufügen“ setzt einen an eine freie Stelle,
  „Namen neu eingeben …“ erzeugt die Anordnung neu. Die Tische rasten an einem
  unsichtbaren 8-Punkt-Raster ein; ⌥ beim Ziehen hebt das auf. „Übernehmen“
  schreibt, „Abbrechen“ verwirft alles seit dem Öffnen; „Sitzplan entfernen“
  fragt vor dem endgültigen Löschen nach — im Editor wie in ⌘K.
- **PDF und Druck** — „Als PDF sichern …“ (⇧⌘P) und „Drucken …“ (⌘P) im
  Editor: eine Seite DIN A4 quer mit der Kopfzeile „Klasse/Kurs · Fach ·
  Sitzplan · Stand“, die Fläche 1:1 wie im Editor, die Tafel unten. Bei
  eingeschalteter Verschlüsselung fragt die App vorher: Die PDF trägt die
  Namen im Klartext.
- **Ablage und Schutz** — Die Sitzpläne liegen als `sitzplaene.json` neben der
  Planung im Container und tragen denselben Schutz wie sie: Klartext, solange
  die Planung Klartext ist; versiegelt unter dem Datenschlüssel, sobald die
  Verschlüsselung eingeschaltet ist (Einschalten versiegelt, Aufheben legt
  wieder Klartext hin, Passphrase ändern und Schlüssel erneuern nehmen die
  Datei mit — mit derselben Rücknahme wie bei den Lesezeichen). Solange die
  Verschlüsselung aus ist, empfiehlt der Editor sie beim Öffnen. Sitzpläne
  gehen nie in den Export, die Sicherungskopie oder die Ansicht fürs iPad;
  eine gesicherte PDF ist ihre dauerhafte Form. Wird eine Klasse entfernt,
  geht ihr Sitzplan mit (die Rückfrage nennt ihn); bei „Neue Planung“ folgen
  Sitzpläne nur den übernommenen Klassen.

### Changed

- Prüfstände und Skripte: `--sitzplantest` führt den Editor am Fenster durch
  (tippen, anordnen, ziehen, Bereichsauswahl, Rückfrage, übernehmen, Datei,
  PDF), `--abbild --dialog sitzplan` bildet ihn ab (`ABBILD_SITZPLAN=namen`
  für die Liste, `ABBILD_DUNKEL=1` für die dunkle Darstellung);
  `leser_pruefen.py` belegt, dass die Ansicht einen Behälter mit Inhalt
  `sitzplaene` abweist.

## [1.4.7 (47)] - 2026-09-12

Hausaufgaben — Ein Vorhaben kann eine Hausaufgabe tragen: ein Schalter im
Dialog, dazu eine freiwillige Zeile, was aufgegeben ist. Das Zeichen dafür
steht an der Kachel, in der Tagesliste, im Ausdruck und in der Ansicht fürs
iPad.

### Added

- **Hausaufgabe je Vorhaben** — „Hausaufgabe hinzufügen“ im Dialog und im
  Rechtsklickmenü der Kachel: ein Merkmal am Vorhaben, dazu eine Zeile („S. 42,
  Nr. 3–5“, freiwillig, höchstens 500 Zeichen). Im Raster trägt die Kachel den
  Ranzen rechts neben dem Titel; die Zeile steht in der Tagesliste
  („Hausaufgabe: …“), im Ausdruck („Hausaufgabe · …“) und in der Ansicht fürs
  iPad (Kachel, Detail, Tagesliste, Ausdruck). Die Suche findet sie.
- **Dateiformat** — zwei Felder je Vorhaben, `hausaufgabe` und
  `hausaufgabenText`; die Fassung der Datei bleibt 2. Ältere Fassungen der App
  und der Ansicht lesen die Datei weiter; eine ältere App lässt beide Felder
  beim Sichern fallen.

### Changed

- **Prüfstände und Skripte** — `--klicktest` schaltet die Hausaufgabe an und
  aus; `--abbild` legt mit `ABBILD_ENDE=1` ein langes Blatt ans Ende gerollt
  ab; `leser_pruefen.py` mit vier Fällen zur Hausaufgabe, `abzug_pruefen.py`
  erzeugt und vergleicht beide Felder.

## [1.4.6 (46)] - 2026-09-10

Fehlerpfade — nach einem externen Prüfbericht zu 1.4.5: Wenn ein Schritt
scheitert, steht danach nichts, was niemand benennt. Der Behälter der
Lesezeichen kehrt beim Erneuern des Schlüssels auf den geltenden Schlüssel
zurück, die Ansicht hält einen Stand erst für gemerkt, wenn er im Speicher
liegt, eine liegen gebliebene Fassung davor wird benannt, jede Datei wird an
dem Objekt gemessen, das gelesen wird, und die Prüfskripte wachen über die
ganze Policy.

### Fixed

- **Lesezeichen beim Erneuern des Schlüssels** — Scheiterte beim Erneuern das
  Versiegeln des Lesezeichen-Behälters, blieb der Behälter auf dem abgewiesenen
  Schlüssel, während Ablage und Sitzung beim alten blieben; der nächste
  Schreibvorgang legte ihn unter dem falschen Schlüssel hin, und der nächste
  Start legte die Lesezeichen beiseite — jeder Ort war neu zu wählen. Jetzt
  kehrt der Behälter bei jedem Fehlschlag auf den geltenden Schlüssel zurück,
  ein schon abgelegter wird einmal nachgeschrieben, und scheitert die Rücknahme
  nach einer gescheiterten Ablage, steht es in der Meldung.
- **Ansicht: gemerkt heißt gespeichert** — Ein gescheitertes Ablegen im
  Speicher des Browsers (voll, gesperrt, privater Modus) galt seit 1.4.3 als
  erledigt; der Stand blieb bis zur nächsten Änderung unpersistiert. Jetzt gilt
  ein Stand erst als gemerkt, wenn er im Speicher liegt; die Uhr holt einen
  Fehlschlag nach, ohne neu zu versiegeln, und die Warnung wird nach jedem
  Erfolg wieder scharf.
- **Fassung davor** — Ließ sich `planung-vorher.json` nicht fortschreiben
  (etwa unveränderbar), blieb die ältere still liegen. Jetzt sagt es die App
  einmal je Wechsel und zeigt den Grund unter „Einstellungen → Stand“; die
  Autosicherung selbst läuft weiter.

### Changed

- **Gebundenes Lesen** — Ablage, Fassung davor, Lesezeichen, Nebendateien,
  Import und Statusdatei werden auf einem Weg gelesen: Datei öffnen, Art und
  Größe am geöffneten Objekt messen, höchstens die Grenze plus ein Byte lesen.
  Eine Datei, die zwischen Messen und Lesen wächst oder ersetzt wird, geht
  nicht mehr ganz in den Speicher; ein Symlink führt zu seinem Ziel, eine Pipe
  blockiert nicht.
- **Werkzeuge** — `bauen.sh --installieren` legt die neue App neben die alte,
  prüft ihre Signatur und tauscht erst dann; `csp_hashes.py` prüft die ganze
  Policy gegen ihr Soll (`--selbsttest`); `pruefhilfen.py` kennt Regex-Literale
  (Selbsttest per Aufruf) und verlangt Python 3.10 oder neuer mit einem Satz
  statt eines `TypeError`; `leser_pruefen.py` prüft das Merken der Ansicht.

## [1.4.5 (45)] - 2026-09-10

Nachfassen nach der Code-Review an v43 und dessen Nachprüfung: Die Grenzen der
eigenen Ablage stehen an einer Stelle, ein Übergang der Verschlüsselung beginnt
nur, wenn die Ablage geschrieben werden kann, und gilt erst, wenn sie ihn trägt;
beide Leser folgen einer Verweisregel und lesen Textfelder gleich. (1.4.4 (44)
blieb eine interne Zwischenfassung.)

### Fixed

- **Eine Decke für die eigene Ablage** — Der Start las die eigene Ablage bis
  128 MB, das Rücklesen nach einem Übergang der Verschlüsselung nur bis 32 MB.
  Ein Bestand dazwischen ließ Sitzung und Platte auseinanderlaufen: die
  Sitzung versiegelt, die Ablage im Klartext, die Lesezeichen verwaist. Jetzt
  gilt eine Decke auf jedem Leseweg. Dazu liest die Ablage Größe und Art einer
  Datei frisch statt aus dem Vorrat des URL-Werts.
- **Verschlüsselung nur bei schreibbarer Ablage** — „Passphrase ändern“ und
  der Schalter „Mit Touch ID öffnen“ übernahmen die neue Wicklung, bevor die
  Ablage geschrieben war; lag die Planung über der Schreibgrenze, trugen
  Kopie, Lesezeichen und Statusdatei die neue Hülle, die Ablage die alte — und
  die Meldung versprach das Gegenteil. Jetzt beginnt kein Übergang, solange
  die Sicherung wegen der Größe still liegt (das Blatt nennt den Grund und
  sperrt Knöpfe und Schalter), und die neue Wicklung gilt erst, wenn die
  Ablage sie trägt: Scheitert das Schreiben, bleibt alles bei der alten.
  Auch die Ersteinrichtung nennt den Grund und schaltet dann nichts ein.

### Changed

- **Verweisregel** — Ein Verweis auf eine ersetzte Kennung folgt ihr, wenn der
  Wert nach dem Stutzen nicht leer ist, nicht Kennung einer früheren Zeile ist
  und noch keiner Zeile gehört. Die leere Kennung wird nie mehr Verweis (bisher
  hingen Vorhaben ohne `klasseId` an der ersten Zeile ohne Kennung); ein
  Duplikat mit Leerraum („ k1“ neben „k1“) zieht seine Verweise nach. In App
  und Ansicht gleich; die Ansicht nimmt ein führendes U+FEFF vor einer
  Zeilen-Kennung nur noch einmal ab, wie die App.
- **Texte sind Zeichenketten** — Eine Zahl, ein Wahrheitswert oder ein Objekt
  in einem Textfeld gilt in beiden Lesern als leer; bisher schrieben sie
  `1e16` und `1e-7` verschieden, und dieselbe Datei zeigte auf Mac und iPad
  Verschiedenes. `abzug_pruefen.py` erzeugt solche Felder.
- **Eine Prüfung der Passphrase-Wicklung** — Öffnen, das Belegen der
  bisherigen Passphrase („Passphrase ändern“, „Schlüssel erneuern“) und das
  Neuwickeln prüfen den Kopf gleich (`kdf`, Rundenzahl, Salt); ein beschädigter
  Kopf heißt auf jedem Weg beschädigt, nicht „passt nicht“.
- **Struktur** — Ein Schreibfehler im Übergang wird einmal gesprochen (kurzer
  Grund in der Meldung, ein Systemfehler in Klammern, der ganze Satz nur an
  der Werkzeugleiste); die Grenze der Autosicherung heißt überall
  Schreibgrenze (zugleich die Lesegrenze von App und Ansicht); ein Ort, den
  die Wahl im Dialog schon gemerkt hat, bekommt kein zweites Lesezeichen.

## [1.4.3 (43)] - 2026-09-10

Grenzen, Verweise, Sparsamkeit — der Feinschliff nach der Code-Review an v42:
Was die App nicht liest, schreibt sie auch nicht; ein Leser, der eine Kennung
ersetzt, zieht die Verweise darauf nach; die Ansicht rechnet nur, wenn sich
etwas geändert hat; kein Blatt behält ein Geheimnis, und die letzten Lesewege
ohne Schranke bekommen eine.

### Fixed

- **Schreibgrenze der Autosicherung** — Die Autosicherung schrieb jede Größe,
  der nächste Start las aber nur bis 32 MB und legte die eigene Planung als
  beschädigt beiseite. Jetzt schreibt sie nichts über der Lesegrenze: Der
  letzte gute Stand bleibt auf der Platte, die Werkzeugleiste zeigt
  „Sicherung liegt still“, eine Meldung nennt Größe, Grenze und den Weg hinaus
  (Beschreibungen und Kommentare kürzen, Vorhaben entfernen), und das Beenden
  fragt zurück, solange die Platte nicht den Stand der Sitzung trägt. Eine
  eigene Ablage aus früheren Fassungen wird bis zu einer Decke von 128 MB noch
  geladen; unter „Einstellungen → Stand“ steht die Größe der Autosicherung
  neben ihrer Grenze.
- **Verweise folgen einer ersetzten Kennung** — Bekam eine Zeile beim Lesen
  eine neue Kennung, verloren ihre Vorhaben, freien Zellen und die Kurse eines
  Sperrzeitraums den Anschluss. Jetzt folgen sie ihr — in App und Ansicht
  gleich, gezählt bleibt die ersetzte Kennung; bei einer doppelten bleiben sie
  bei der ersten Zeile.
- **Passphrase ändern: Abbrechen leert die Felder** — Bisherige, neue und
  wiederholte Passphrase blieben im Blatt stehen und erschienen beim nächsten
  Öffnen wieder; auch nach „Weiter“ bleibt keine Passphrase mehr im Blatt.

### Changed

- **Ansicht fürs iPad: Merken nur bei Änderung** — Der Stand wurde alle fünf
  Sekunden neu versiegelt und in den Browserspeicher geschrieben, auch ohne
  Änderung. Jetzt nur, wenn seit dem letzten Merken ein Haken oder Kommentar
  dazukam; der Behälter fürs Teilen-Blatt liegt weiter bereit.
- **Schlüsselarbeit gegen Schlüsselwechsel** — Ein Ergebnis von „Passphrase
  ändern“, das für einen inzwischen abgelösten Sitzungsschlüssel gerechnet
  wurde (Aufheben, Einschalten, Erneuern oder Entsperren dazwischen), wird
  verworfen; eine Wicklung kommt nur in den Tresor, für dessen Kennung sie
  gerechnet wurde.
- **Gebunden gelesen** — Die Nebendateien des Registers (Vorgängerfassung,
  Rettungskopien) werden beim Versiegeln und Entsiegeln wie die Ablage
  gemessen, bevor ein Byte gelesen wird; Übergroßes und Nicht-Reguläres bleibt
  benannt liegen. Die Antwort der Update-Prüfung ist auf 1 MiB begrenzt — an
  `Content-Length` und an der Bytezahl; mehr ist unlesbar und wird nicht
  gemerkt.
- **Struktur** — Jeder Lesezugriff auf Einstellungen geht über die eine
  Schranke (`Einstellungen.wert`): Ein Prüflauf erbt nichts, Prüfstände und
  Abbilder laufen mit Vorgabewerten. `Tresor.entwickeln` nimmt Kennung und
  Wicklungen statt eines Attrappen-Kopfes; eine Durchreichung im Speicher
  entfällt.

## [1.4.2 (42)] - 2026-09-09

Format, Grenzen, Ansicht, Werkzeuge, Struktur — Phase B der Nachbesserung
nach den Reviews an v40: Beide Leser sind gleich streng, jede Datei wird vor
dem Lesen gemessen, Schlüsselarbeit läuft abseits des Hauptstrangs, die
Werkzeuge halten Geheimnisse von der Kommandozeile fern, und die Ansicht fürs
iPad ist als Release-Asset prüfbar.

### Security

- **Formatstrenge beider Leser** — Kennungen in Planung und Status müssen
  einem Muster genügen (ASCII-Buchstaben und Ziffern, dazu `-` `_` `.` `:`,
  höchstens 64 Zeichen); leere, doppelte und unpassende bekommen eine neue,
  gezählt — jetzt auch bei Ferien und Sperrzeiten, deren doppelte Kennungen
  bisher Löschen und Ändern durcheinanderbrachten. Steuer- und Bidi-Zeichen
  fallen aus Titeln, Texten und Kommentaren heraus, gezählt; die App schreibt
  sie auch beim Eingeben nicht. Ein Nicht-Objekt in `klassen` wird verworfen
  statt als leere Zeile nachgebildet. Zwei Fachfarben-Schlüssel, die sich nur
  in der Unicode-Form unterscheiden, sind einer (NFC). Doppelte JSON-Schlüssel
  bleiben Sache der Parser: Die App liest den ersten, die Ansicht den letzten
  Wert — dokumentiert und in `abzug_pruefen.py` festgehalten; die App schreibt
  nie welche.
- **Grenzen vor dem Lesen** — Ablage, Vorgängerfassung und der Behälter der
  Lesezeichen werden gemessen, bevor ein Byte gelesen wird (`Planungsdatei.
  hoechstgroesse` 32 MB, `Statusdatei.hoechstgroesse` 8 MB, geteilt mit den
  Lesezeichen). Übergroßes wird beiseitegelegt und benannt; keine reguläre
  Datei und eine gescheiterte Größenabfrage sind ein Fehler, keine Null — beim
  Öffnen von außen, an der Statusdatei, an der Ablage. Der Behälter der
  Lesezeichen wird vor dem Ablegen geprüft und über denselben Weg zurückgelesen
  wie beim Öffnen. Ein Behälterkopf trägt höchstens vier Wicklungen mit
  begrenzter Tiefe, Breite und Textlänge — in App und Ansicht; die Ansicht
  nimmt in einen Statusbehälter nur Passphrase und Wiederherstellung mit.
  Export und Sicherungskopie sagen, wenn die geschriebene Datei über der
  Lesegrenze liegt.
- **Werkzeuge** — `tresor_pruefen.py` nimmt Passphrase und
  Wiederherstellungsschlüssel verdeckt oder von stdin entgegen und reicht sie
  per Pipe weiter, nie über die Kommandozeile; `--kopf --ziel` unterscheidet
  Ablage (Enklave erlaubt) von Kopie und Export; die Fassung muss genau die
  Zahl 1 sein; die Probeseite schreibt über das Dokumentmodell.
  `csp_hashes.py` sichert in einen privaten Temporärordner, schreibt über eine
  unvorhersagbar benannte Nachbardatei, hasht mit den Zeilenenden des Browsers
  (CR LF → LF) und lässt fremde Quellen einer Direktive stehen.
  `beglaubigen.sh --probe` bleibt ohne Netz; das Profil belegt `--online` oder
  der Lauf vor `--ja`. `bauen.sh` und `beglaubigen.sh` lesen die Berechtigungen
  als XML-Plist.

### Changed

- **Schlüsselarbeit abseits des Hauptstrangs** — Einrichten, Passphrase ändern
  und Schlüssel erneuern rechnen wie das Entsperren in einer abgesetzten
  Aufgabe; die Blätter zeigen einen Kreisel und sperren ihre Knöpfe, ein
  zweites Absenden ist wirkungslos, Abbrechen verwirft das Ergebnis.
- **Ansicht fürs iPad** — Teilen-Blatt und Download laufen synchron in der
  Geste (der Behälter liegt seit dem letzten Haken bereit); scheitert das
  Herausgeben, bleibt der Stand offen, und die Meldung sagt es. Das
  Passphrase-Blatt nimmt eine Datei zur Zeit. Die Prüfungsliste sortiert nach
  Codepunkten wie die App. Das Info-Blatt sagt, wie sich die Echtheit der
  Seite prüfen lässt.
- **Zusatzdaten nach dem Kopf** — Die App beglaubigt einen Behälter mit der
  Fassung aus seinem Kopf, wie die Ansicht; heute byteweise dasselbe.
  Rettungskopien tragen ihren Zeitstempel in Ortszeit.
- **Struktur** — Der Schlüssel eines gemerkten Ortes ist rein lexikalisch:
  Ein Ort hinter einem Symlink bleibt unter dem gewählten Namen gemerkt — das
  Auflösen bräuchte Zugriff, den der nächste Start noch nicht hat.
  `Ordnerzugriff.zugang(fuer:)` ist die eine Frage der Nachwahl; alle Dienste
  melden über eine Senke; ein Einstellungsspeicher mit einer
  Prüfstand-Schranke; eine Ganzzahl-Hilfe je Übersetzungseinheit.
  `pruefhilfen.py` bündelt die zeichenketten- und kommentarfeste
  Blockextraktion der vier Prüfskripte; `symbole_bauen.py` nimmt das Symbol
  der eigenen Fassung; `schulwochen_pruefen.py` legt seine Probe im
  Temporärordner ab.

### Documentation

- **Was die Verschlüsselung verspricht** und das **Vertrauensmodell der
  Ansicht** in LIESMICH und README: Die Hash-CSP schützt vor eingeschleustem
  Code, nicht vor einem ersetzten Server — darum liegt die Ansicht jedem
  Release als Datei mit SHA-256-Prüfsumme bei, samt Anleitung zum Abgleich.

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
