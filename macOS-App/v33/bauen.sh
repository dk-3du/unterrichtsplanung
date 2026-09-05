#!/bin/bash
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: GPL-3.0-or-later
# ──────────────────────────────────────────────────────────────────────────
#  Unterrichtsplanung — bauen und als App-Paket schnüren
#
#     ./bauen.sh              Release bauen, App-Paket erzeugen
#     ./bauen.sh --debug      Debug bauen (schnellerer Übersetzungslauf)
#     ./bauen.sh --starten    danach gleich öffnen
#     ./bauen.sh --installieren   zusätzlich nach /Applications legen
#     ./bauen.sh --dmg        zusätzlich ein DMG-Image zur Weitergabe schnüren
#     ./bauen.sh --nur-dmg    kein Neubau: das Abbild um das vorhandene Paket
#                             schnüren — nach der Beglaubigung, damit die App
#                             ihr Ticket behält (./beglaubigen.sh)
#
#  Umgebung:
#     SIGNATUR="Developer ID Application: Name (TEAMID)"
#                             mit dieser Kennung signieren, samt beglaubigtem
#                             Zeitstempel — Bedingung für die Beglaubigung bei
#                             Apple (siehe beglaubigen.sh);
#                             ohne SIGNATUR wird wie bisher ad hoc signiert
#     SCHLUESSELBUND=<Pfad>   Schlüsselbund mit der Kennung, nur für Prüfläufe
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HIER"

NAME="Unterrichtsplanung"
KONFIGURATION="release"
STARTEN=0
INSTALLIEREN=0
DMG=0
NURDMG=0
SIGNATUR="${SIGNATUR:-}"
SCHLUESSELBUND="${SCHLUESSELBUND:-}"
SYMBOLBAU=""
BUEHNE=""
PROTOKOLL=""

# Sonst bleiben die mktemp-Ordner bei jedem Abbruch stehen.
trap 'rm -rf "$SYMBOLBAU" "$BUEHNE" "$PROTOKOLL"' EXIT

for arg in "$@"; do
  case "$arg" in
    --debug)        KONFIGURATION="debug" ;;
    --starten)      STARTEN=1 ;;
    --installieren) INSTALLIEREN=1 ;;
    --dmg)          DMG=1 ;;
    --nur-dmg)      DMG=1; NURDMG=1 ;;
    *) echo "Unbekannte Angabe: $arg"; exit 2 ;;
  esac
done

PAKET="$HIER/Paket/$NAME.app"

# Was die Signatur eines Pakets oder Abbilds tatsächlich trägt.
signaturBeschreibung() { codesign -dvv "$1" 2>&1; }

# Mit SIGNATUR muss das Paket genau diese Kennung, den Hardened Runtime und
# einen Zeitstempel tragen und darf nicht ad hoc gesiegelt sein — sonst weist
# Apple die Einreichung ab, und zwar erst nach dem Hochladen.
signaturPruefen() {
  [ "$ENTWICKLERSIGNATUR" = "1" ] || return 0
  local b fehler=0
  b="$(signaturBeschreibung "$1")"
  grep -qxF "Authority=$SIGNATUR" <<<"$b" || { echo "Signaturkennung fehlt: $SIGNATUR"; fehler=1; }
  grep -q '^Signature=adhoc' <<<"$b" && { echo "Das Paket ist ad hoc gesiegelt."; fehler=1; }
  grep -q '^CodeDirectory .*runtime' <<<"$b" || { echo "Hardened Runtime fehlt."; fehler=1; }
  grep -q '^Timestamp=' <<<"$b" || { echo "Der beglaubigte Zeitstempel fehlt."; fehler=1; }
  return $fehler
}

signaturZeile() {
  local b
  b="$(signaturBeschreibung "$1")"
  printf 'Team-ID %s, Zeitstempel %s' \
    "$(sed -n 's/^TeamIdentifier=//p' <<<"$b")" "$(sed -n 's/^Timestamp=//p' <<<"$b")"
}

# Developer ID oder ad hoc? Beim Neubau entscheidet SIGNATUR; ohne Neubau das
# Paket selbst, und SIGNATUR muss dazu passen (das Abbild wird damit signiert).
if [ "$NURDMG" = "1" ]; then
  if [ ! -d "$PAKET" ]; then
    echo "Kein Paket unter $PAKET — erst ./bauen.sh."
    exit 1
  fi
  # Erst in eine Variable: `befehl | grep -q` lügt unter pipefail, sobald grep
  # die Leitung vor dem Ende schließt.
  if grep -q '^Signature=adhoc' <<<"$(signaturBeschreibung "$PAKET")"; then
    ENTWICKLERSIGNATUR=0
    if [ -n "$SIGNATUR" ]; then
      echo "Das Paket ist ad hoc gesiegelt, SIGNATUR ist aber gesetzt — erst ./bauen.sh mit SIGNATUR."
      exit 1
    fi
  else
    ENTWICKLERSIGNATUR=1
    if [ -z "$SIGNATUR" ]; then
      echo "Das Paket trägt eine Developer-ID-Signatur; zum Signieren des Abbilds fehlt SIGNATUR."
      exit 1
    fi
    signaturPruefen "$PAKET" || exit 1
  fi
  echo "▸ Kein Neubau — das Abbild entsteht um $PAKET"
elif [ -n "$SIGNATUR" ]; then
  ENTWICKLERSIGNATUR=1
else
  ENTWICKLERSIGNATUR=0
fi

if [ "$(uname -m)" != "arm64" ]; then
  echo "Diese App ist ausschließlich für Macs mit M-Prozessor gedacht (arm64)."
  exit 1
fi

if [ "$NURDMG" = "0" ]; then
  echo "▸ Übersetze ($KONFIGURATION, arm64) …"
  swift build --configuration "$KONFIGURATION" --arch arm64

  BINAER="$(swift build --configuration "$KONFIGURATION" --arch arm64 --show-bin-path)/$NAME"
  if [ ! -x "$BINAER" ]; then
    echo "Das Programm wurde nicht gefunden: $BINAER"
    exit 1
  fi

  echo "▸ Schnüre $PAKET …"
  rm -rf "$PAKET"
  mkdir -p "$PAKET/Contents/MacOS" "$PAKET/Contents/Resources"

  cp "$BINAER" "$PAKET/Contents/MacOS/$NAME"
  cp "$HIER/Beiwerk/Info.plist" "$PAKET/Contents/Info.plist"

  # Der Lizenztext gehört zu jeder Weitergabe (GPL § 4 und § 6) — ohne ihn kein Paket.
  if [ ! -f "$HIER/LICENSE.txt" ]; then
    echo "Der Lizenztext fehlt: $HIER/LICENSE.txt — ohne ihn wird nicht gepackt."
    exit 1
  fi
  cp "$HIER/LICENSE.txt" "$PAKET/Contents/Resources/LICENSE.txt"
  printf 'APPL????' > "$PAKET/Contents/PkgInfo"

  # Vor dem Signieren, sonst bricht die Signatur. Spart 2,21 MB.
  if [ "$KONFIGURATION" = "release" ]; then
    echo "▸ Beschneide die Symboltabelle …"
    strip -x "$PAKET/Contents/MacOS/$NAME" 2>/dev/null || \
      echo "  (fehlgeschlagen — das Programm läuft trotzdem, nur größer)"
  fi

  SYMBOL="$HIER/Beiwerk/AppIcon.icon"
  if [ -d "$SYMBOL" ] && xcrun --find actool >/dev/null 2>&1; then
    echo "▸ Übersetze das Symbol …"
    SYMBOLBAU="$(mktemp -d)"
    ( cd "$HIER/Beiwerk" && xcrun actool AppIcon.icon \
        --compile "$SYMBOLBAU" --app-icon AppIcon --platform macosx \
        --minimum-deployment-target 26.0 \
        --output-partial-info-plist "$SYMBOLBAU/partial.plist" \
        --errors ) > "$SYMBOLBAU/protokoll.txt" 2>&1 \
      || { cat "$SYMBOLBAU/protokoll.txt"; exit 1; }
    # actool meldet ein fehlendes Ebenenbild nur im Protokoll und liefert 0 zurück.
    if grep -q "does not exist" "$SYMBOLBAU/protokoll.txt"; then
      echo "  Achtung: eine Ebene verweist auf ein fehlendes Bild:"
      grep "does not exist" "$SYMBOLBAU/protokoll.txt" | sed 's/^/    /'
    fi
    if [ -f "$SYMBOLBAU/Assets.car" ]; then
      cp "$SYMBOLBAU/Assets.car" "$PAKET/Contents/Resources/"
      [ -f "$SYMBOLBAU/AppIcon.icns" ] && cp "$SYMBOLBAU/AppIcon.icns" "$PAKET/Contents/Resources/"
    else
      echo "  (fehlgeschlagen — die App läuft auch ohne eigenes Symbol)"
    fi
  else
    echo "▸ Symbol übersprungen (actool nicht gefunden — dafür braucht es Xcode)."
  fi

  # Hardened Runtime greift auch bei ad hoc signierten Paketen und ist Bedingung
  # für die Beglaubigung. Kein --deep: es gibt keinen geschachtelten Code, das
  # Signieren des Bündels signiert das Hauptprogramm mit. Mit SIGNATUR kommt der
  # beglaubigte Zeitstempel dazu: Ohne ihn nimmt Apple nichts an, und mit ihm
  # bleibt die Signatur gültig, wenn das Zertifikat abläuft.
  SIGNIEREN=(codesign --force --options runtime \
             --entitlements "$HIER/Beiwerk/Berechtigungen.plist")
  if [ "$ENTWICKLERSIGNATUR" = "1" ]; then
    echo "▸ Signiere (Developer ID, Hardened Runtime, Zeitstempel) …"
    SIGNIEREN+=(--timestamp --sign "$SIGNATUR")
    [ -n "$SCHLUESSELBUND" ] && SIGNIEREN+=(--keychain "$SCHLUESSELBUND")
  else
    echo "▸ Signiere (ad hoc, Hardened Runtime) …"
    SIGNIEREN+=(--sign -)
  fi
  PROTOKOLL="$(mktemp)"
  if "${SIGNIEREN[@]}" "$PAKET" >"$PROTOKOLL" 2>&1 &&
     codesign --verify --strict "$PAKET" >>"$PROTOKOLL" 2>&1 &&
     signaturPruefen "$PAKET" >>"$PROTOKOLL" 2>&1; then
    echo "  geprüft (codesign --verify --strict)"
    [ "$ENTWICKLERSIGNATUR" = "1" ] && echo "  $(signaturZeile "$PAKET")"
  else
    echo "  Signieren fehlgeschlagen:"
    sed 's/^/    /' "$PROTOKOLL"
    # Ohne gültiges Bündelsiegel führt der in der Anleitung genannte Weg über
    # „Dennoch öffnen“ beim Empfänger nicht weiter; die App gilt dort als kaputt.
    # Und mit SIGNATUR ist die Signatur der Zweck des Laufs.
    if [ "$ENTWICKLERSIGNATUR" = "1" ] || [ "$DMG" = "1" ] || [ "$INSTALLIEREN" = "1" ]; then
      echo "  Abbruch: aus einem so gesiegelten Paket entsteht weder DMG noch Installation."
      exit 1
    fi
    echo "  (die App läuft lokal trotzdem)"
  fi

  # Damit der Finder Symbol und Namen sofort übernimmt.
  touch "$PAKET"

  echo "▸ Fertig: $PAKET"
fi

# ── Weitergabe ────────────────────────────────────────────────────────────
# DMG statt ZIP: bringt den Ordner „Applications“ mit, und die Signatur übersteht das Kopieren.
if [ "$DMG" = "1" ]; then
  # Ohne Neubau gibt es noch kein Protokoll.
  [ -n "$PROTOKOLL" ] || PROTOKOLL="$(mktemp)"
  FASSUNG="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$PAKET/Contents/Info.plist" 2>/dev/null || echo "0")"
  STUFE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$PAKET/Contents/Info.plist" 2>/dev/null || echo "")"
  DATENTRAEGER="$NAME $FASSUNG${STUFE:+ ($STUFE)}"
  ABBILD="$HIER/Paket/$NAME-$FASSUNG${STUFE:+-$STUFE}.dmg"
  # Wo der Quelltext liegt — derselbe Schlüssel, den der Über-Dialog liest.
  QUELLTEXT="$(/usr/libexec/PlistBuddy -c 'Print :UPQuelltext' \
    "$PAKET/Contents/Info.plist" 2>/dev/null || echo "")"
  if [ -n "$QUELLTEXT" ]; then
    QUELLTEXTZEILE="Quelltext: $QUELLTEXT"
  else
    QUELLTEXTZEILE="Der Quelltext wird an derselben Stelle angeboten wie dieses Abbild."
  fi

  # Reihenfolge der Beglaubigung: erst die App einreichen und ihr Ticket
  # anheften, dann das Abbild darum — sonst steckt eine unbeglaubigte App im
  # Abbild, und ein Neubau nähme der App das Ticket wieder.
  if [ "$ENTWICKLERSIGNATUR" = "1" ]; then
    if xcrun stapler validate -q "$PAKET" >/dev/null 2>&1; then
      echo "▸ Die App trägt ihr Beglaubigungsticket (stapler validate)."
    else
      echo "▸ Die App trägt noch kein Beglaubigungsticket — kein Abbild."
      echo "  Reihenfolge: ./bauen.sh → ./beglaubigen.sh --app → ./bauen.sh --nur-dmg;"
      echo "  ./beglaubigen.sh ohne Angabe erledigt alles ab dem zweiten Schritt."
      exit 1
    fi
  fi

  echo "▸ Schnüre $ABBILD …"
  BUEHNE="$(mktemp -d)"
  cp -R "$PAKET" "$BUEHNE/"
  ln -s /Applications "$BUEHNE/Applications"
  cp "$HIER/LICENSE.txt" "$BUEHNE/Lizenz (GNU GPL v3).txt"

  # Der Absatz zum ersten Start hängt an der Signatur: Ohne den Hinweis gilt
  # die nur ad hoc signierte App beim Empfänger als kaputt; die beglaubigte
  # braucht nur den Doppelklick.
  if [ "$ENTWICKLERSIGNATUR" = "1" ]; then
    STARTHINWEIS="$(cat <<TEXT
Beim ersten Start
  Die App ist mit Developer ID signiert und von Apple beglaubigt (notarisiert);
  das Ticket dazu steckt in App und Abbild. macOS fragt beim ersten Öffnen
  einmal, ob die aus dem Internet geladene App geöffnet werden soll — „Öffnen“
  genügt. Meldet macOS stattdessen, die App sei beschädigt, ist das Abbild
  unvollständig angekommen: bitte erneut laden.
TEXT
)"
  else
    STARTHINWEIS="$(cat <<TEXT
Beim ersten Start
  Die App ist ad hoc signiert und nicht notariell beglaubigt. macOS weist sie
  deshalb beim ersten Doppelklick ab. Die Meldung mit „Fertig“ schließen — auf
  keinen Fall „In den Papierkorb legen“ — und dann die Systemeinstellungen
  öffnen: unter „Datenschutz & Sicherheit“ steht weiter unten ein Hinweis auf
  „$NAME“ mit der Schaltfläche „Dennoch öffnen“. Diese anklicken und mit Touch
  ID oder Kennwort bestätigen. Danach startet sie wie jedes andere Programm.
TEXT
)"
  fi

  cat > "$BUEHNE/Bitte zuerst lesen.txt" <<HINWEIS
$NAME $FASSUNG${STUFE:+ ($STUFE)}

Ablegen
  Das Programmsymbol auf den Ordner „Applications“ ziehen.

$STARTHINWEIS

Voraussetzung
  macOS 26 oder neuer, Mac mit M-Prozessor.

Daten
  Alles bleibt auf diesem Rechner. Die Planung wird laufend unter
  ~/Library/Application Support/$NAME/ gesichert; die verbindliche Sicherung
  bleibt der Export als JSON-Datei (⌘S). Auf Wunsch legt die App beim Beenden
  zusätzlich eine Kopie in einem frei gewählten Ordner ab — einzustellen unter
  „Einstellungen“.

Verschlüsselung
  Die Planung lässt sich mit AES-256 versiegeln: Ablage, Sicherungskopie und
  Export tragen dann nur noch Chiffrat. Auf diesem Mac öffnet Touch ID oder das
  Anmeldepasswort (Secure Enclave), überall sonst die Passphrase — oder der
  gedruckte Wiederherstellungsschlüssel, wenn die Passphrase vergessen ist.
  Der Klartext-Export bleibt als eigener Befehl im Menü „Ablage“.

Bevor personenbezogene Daten hineingehen
  Hinweis zur Datenverwaltung: Die Sicherungskopie beim Beenden wird nur
  verschlüsselt geschrieben (AES-256) — mit der Wahl eines Zielordners wird die
  Verschlüsselung eingerichtet, mit Passphrase und Wiederherstellungsschlüssel.
  Die laufende Sicherung auf diesem Rechner ist unverschlüsselt, solange die
  Verschlüsselung unter „Einstellungen“ nicht eingeschaltet ist; FileVault
  schützt sie unabhängig davon. Ältere Kopien, Schnappschüsse und Sicherungen
  des Systems bleiben von einem späteren Einschalten unberührt.

Ansicht fürs iPad
  Die Planung lässt sich unterwegs ansehen unter

      https://3ducation.org/upapp/

  Dort die JSON-Datei öffnen, die diese App beim Beenden ablegt oder die über
  „Als JSON sichern“ (⌘S) entsteht; ist sie verschlüsselt, fragt die Ansicht
  nach der Passphrase. In Safari lässt sich die Ansicht über
  „Teilen → Zum Home-Bildschirm“ wie eine App ablegen.

  Dort lassen sich Vorhaben abhaken und kommentieren. Beides legt die Ansicht
  als „current_status.json“ im Ordner der Sicherungskopie ab; diese App liest
  die Datei beim nächsten Start ein und sagt, was sie übernommen hat. Alles
  Übrige an der Planung — Titel, Wochen, Klassen/Kurse, Termine — bleibt dem Mac
  vorbehalten.

Erstellt mit Claude Code (Opus 5 & Fable 5/5.1).
© 2026 Dominik Kluge. Freie Software unter der GNU General Public License,
Version 3 oder neuer — ohne Gewährleistung. Der vollständige Lizenztext liegt
als „Lizenz (GNU GPL v3).txt“ in diesem Abbild.
$QUELLTEXTZEILE
HINWEIS

  rm -f "$ABBILD"
  hdiutil create -volname "$DATENTRAEGER" -srcfolder "$BUEHNE" \
    -fs HFS+ -format UDZO -ov -quiet "$ABBILD"

  if hdiutil verify "$ABBILD" >"$PROTOKOLL" 2>&1; then
    echo "  geprüft, $(du -h "$ABBILD" | cut -f1) — Datenträger „$DATENTRAEGER“"
  else
    echo "  Das Abbild ließ sich nicht prüfen:"
    sed 's/^/    /' "$PROTOKOLL"
    rm -f "$ABBILD"
    echo "  Abbruch — ein ungeprüftes Abbild wird nicht weitergegeben."
    exit 1
  fi

  # Das Abbild selbst wird signiert, damit Apple es beglaubigt und Gatekeeper
  # schon das Abbild einordnen kann; die Prüfsumme des Abbilds übersteht das.
  if [ "$ENTWICKLERSIGNATUR" = "1" ]; then
    echo "▸ Signiere das Abbild (Developer ID, Zeitstempel) …"
    SIEGEL=(codesign --force --timestamp --sign "$SIGNATUR")
    [ -n "$SCHLUESSELBUND" ] && SIEGEL+=(--keychain "$SCHLUESSELBUND")
    if "${SIEGEL[@]}" "$ABBILD" >"$PROTOKOLL" 2>&1 &&
       codesign --verify "$ABBILD" >>"$PROTOKOLL" 2>&1 &&
       hdiutil verify "$ABBILD" >>"$PROTOKOLL" 2>&1; then
      echo "  geprüft (codesign --verify, hdiutil verify) — beglaubigt ist das"
      echo "  Abbild damit noch nicht: ./beglaubigen.sh --dmg"
    else
      echo "  Das Abbild ließ sich nicht signieren:"
      sed 's/^/    /' "$PROTOKOLL"
      rm -f "$ABBILD"
      echo "  Abbruch — ein unsigniertes Abbild um eine signierte App wird nicht weitergegeben."
      exit 1
    fi
  fi
fi

if [ "$INSTALLIEREN" = "1" ]; then
  echo "▸ Lege die App nach /Applications …"
  rm -rf "/Applications/$NAME.app"
  cp -R "$PAKET" "/Applications/$NAME.app"
  echo "  /Applications/$NAME.app"
fi

if [ "$STARTEN" = "1" ]; then
  open "$PAKET"
fi
