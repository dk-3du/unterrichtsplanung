#!/bin/bash
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: GPL-3.0-or-later
# ──────────────────────────────────────────────────────────────────────────
#  Unterrichtsplanung — bei Apple beglaubigen lassen und das Ticket anheften
#
#     ./beglaubigen.sh --probe     prüfen, ob alles bereitliegt — nichts
#                                  verlässt den Rechner
#     ./beglaubigen.sh --ja        App einreichen und Ticket anheften; Abbild
#                                  schnüren und signieren (./bauen.sh --nur-dmg),
#                                  einreichen, Ticket anheften; Gatekeeper-Probe
#     ./beglaubigen.sh --app --ja  nur die App
#     ./beglaubigen.sh --dmg --ja  nur das Abbild (die App trägt ihr Ticket schon)
#
#  Jede Einreichung lädt das Paket zu Apples Beglaubigungsdienst hoch. Ohne
#  --ja fragt das Skript vorher — im Terminal; ohne Terminal bricht es vor dem
#  Hochladen ab. Voraussetzung ist ein Paket aus ./bauen.sh mit SIGNATUR.
#
#  Umgebung:
#     SIGNATUR="Developer ID Application: Name (TEAMID)"   wie bei ./bauen.sh
#     PROFIL=unterrichtsplanung   Schlüsselbund-Profil aus
#                                 `xcrun notarytool store-credentials` (Vorgabe)
#     SCHLUESSELBUND=<Pfad>       Schlüsselbund mit der Kennung, nur für Prüfläufe
#
#  Protokolle landen in Paket/Beglaubigung/ — Einreichung, Apples Prüfbericht
#  (JSON) und eine fortlaufende Zusammenfassung je Fassung.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HIER"

NAME="Unterrichtsplanung"
PAKET="$HIER/Paket/$NAME.app"
PROFIL="${PROFIL:-unterrichtsplanung}"
SIGNATUR="${SIGNATUR:-}"
SCHLUESSELBUND="${SCHLUESSELBUND:-}"
export SIGNATUR SCHLUESSELBUND
PROBE=0
NUR=""
JA=0

for arg in "$@"; do
  case "$arg" in
    --probe) PROBE=1 ;;
    --app)   NUR="app" ;;
    --dmg)   NUR="dmg" ;;
    --ja)    JA=1 ;;
    *) echo "Unbekannte Angabe: $arg"; exit 2 ;;
  esac
done
APP=1; DMG=1
[ "$NUR" = "dmg" ] && APP=0
[ "$NUR" = "app" ] && DMG=0

ORDNER="$HIER/Paket/Beglaubigung"
STEMPEL="$(date +%Y-%m-%d-%H%M%S)"
# Das ZIP ist nur der Transportbehälter — auch bei Abbruch weg damit.
ZIP=""
trap 'rm -f "$ZIP"' EXIT

# ── Was vorliegt ──────────────────────────────────────────────────────────
FEHLER=0
ok()   { echo "  ✓ $1"; }
nein() { echo "  ✗ $1"; FEHLER=$((FEHLER + 1)); }

beschreibung() { codesign -dvv "$1" 2>&1; }

echo "▸ Prüfe die Voraussetzungen …"

if xcrun --find notarytool >/dev/null 2>&1 && xcrun --find stapler >/dev/null 2>&1; then
  ok "notarytool $(xcrun notarytool --version 2>/dev/null | head -1) und stapler (Xcode unter $(xcode-select -p))"
else
  nein "notarytool oder stapler fehlt — Xcode auswählen (xcode-select)"
fi

if [ -n "$SIGNATUR" ]; then
  ok "SIGNATUR: $SIGNATUR"
  # Ausgaben erst in Variablen: `befehl | grep -q` lügt unter pipefail, sobald
  # grep die Leitung vor dem Ende schließt.
  ALLE=(security find-identity -p codesigning)
  GUELTIGE=(security find-identity -v -p codesigning)
  if [ -n "$SCHLUESSELBUND" ]; then ALLE+=("$SCHLUESSELBUND"); GUELTIGE+=("$SCHLUESSELBUND"); fi
  GEFUNDEN="$("${ALLE[@]}" 2>/dev/null || true)"
  GUELTIG="$("${GUELTIGE[@]}" 2>/dev/null || true)"
  if grep -qF "\"$SIGNATUR\"" <<<"$GEFUNDEN"; then
    if grep -qF "\"$SIGNATUR\"" <<<"$GUELTIG"; then
      ok "Kennung im Schlüsselbund, gültig (Zertifikat, privater Schlüssel, Vertrauenskette)"
    else
      nein "Kennung im Schlüsselbund, aber nicht gültig — fehlt das Zwischenzertifikat „Developer ID – G2“ oder der private Schlüssel?"
    fi
  else
    nein "Kennung nicht im Schlüsselbund: security find-identity -v -p codesigning nennt sie nicht (Phase A2 des Ablaufplans)"
  fi
else
  nein "SIGNATUR ist nicht gesetzt (export SIGNATUR=\"Developer ID Application: Name (TEAMID)\")"
fi

if [ -d "$PAKET" ]; then
  FASSUNG="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PAKET/Contents/Info.plist" 2>/dev/null || echo "0")"
  STUFE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PAKET/Contents/Info.plist" 2>/dev/null || echo "")"
  ABBILD="$HIER/Paket/$NAME-$FASSUNG${STUFE:+-$STUFE}.dmg"
  ok "Paket $NAME $FASSUNG${STUFE:+ ($STUFE)}: $PAKET"
  B="$(beschreibung "$PAKET")"
  if grep -q '^Signature=adhoc' <<<"$B"; then
    nein "Das Paket ist ad hoc gesiegelt — erst ./bauen.sh mit SIGNATUR"
  else
    if [ -n "$SIGNATUR" ] && grep -qxF "Authority=$SIGNATUR" <<<"$B"; then
      ok "signiert mit der Kennung, Team-ID $(sed -n 's/^TeamIdentifier=//p' <<<"$B")"
    else
      nein "signiert, aber nicht mit SIGNATUR: $(sed -n 's/^Authority=//p' <<<"$B" | head -1)"
    fi
    if grep -q '^CodeDirectory .*runtime' <<<"$B"; then ok "Hardened Runtime"; else nein "Hardened Runtime fehlt"; fi
    if grep -q '^Timestamp=' <<<"$B"; then ok "beglaubigter Zeitstempel $(sed -n 's/^Timestamp=//p' <<<"$B")"; else nein "kein beglaubigter Zeitstempel"; fi
  fi
  if codesign --verify --strict "$PAKET" >/dev/null 2>&1; then ok "codesign --verify --strict"; else nein "codesign --verify --strict schlägt fehl"; fi
  BERECHTIGUNGEN="$(codesign -d --entitlements - "$PAKET" 2>/dev/null || true)"
  if grep -q 'get-task-allow' <<<"$BERECHTIGUNGEN"; then
    nein "Berechtigung get-task-allow im Paket — Apple weist das ab"
  else
    ok "keine Debug-Berechtigung (get-task-allow) im Paket"
  fi
  if codesign -d --entitlements :- "$PAKET" 2>/dev/null \
       | grep -q '<key>com.apple.security.app-sandbox</key><true/>'; then
    ok "App Sandbox in der Signatur"
  else
    nein "App Sandbox fehlt in der Signatur (Beiwerk/Berechtigungen.plist)"
  fi
  if xcrun stapler validate -q "$PAKET" >/dev/null 2>&1; then
    ok "die App trägt ihr Beglaubigungsticket"
  elif [ "$APP" = "1" ]; then
    ok "die App trägt noch kein Ticket — das ist der Zweck dieses Laufs"
  else
    nein "die App trägt noch kein Ticket; --dmg setzt es voraus (erst --app)"
  fi
else
  nein "Kein Paket unter $PAKET — erst ./bauen.sh"
  FASSUNG="0"; STUFE=""; ABBILD=""
fi

# Nur lesend: die Liste bisheriger Einreichungen. Belegt Profil und Zugang.
if PROTOKOLL="$(xcrun notarytool history --keychain-profile "$PROFIL" 2>&1)"; then
  ok "Profil „$PROFIL“ angenommen (notarytool history: $(grep -c 'id:' <<<"$PROTOKOLL" || true) Einreichungen bisher)"
else
  nein "Profil „$PROFIL“: $(tail -1 <<<"$PROTOKOLL") (Phase A3: xcrun notarytool store-credentials \"$PROFIL\")"
fi

if [ "$FEHLER" -gt 0 ]; then
  echo "  $FEHLER Voraussetzung(en) fehlen — nichts eingereicht."
  exit 1
fi
if [ "$PROBE" = "1" ]; then
  echo "  Alles bereit. Ohne --probe würde jetzt eingereicht."
  exit 0
fi

# ── Einreichen ────────────────────────────────────────────────────────────
mkdir -p "$ORDNER"
ZUSAMMENFASSUNG="$ORDNER/Beglaubigung-$FASSUNG${STUFE:+-$STUFE}.txt"

# $1 Datei, $2 Kürzel (app|dmg). Fragt, lädt hoch, wartet, holt Apples Bericht.
einreichen() {
  local datei="$1" kurz="$2" antwort protokoll kennung status
  echo "▸ Einreichen: $(basename "$datei") ($(du -h "$datei" | cut -f1)) → Apples Beglaubigungsdienst, Profil „$PROFIL“"
  if [ "$JA" != "1" ]; then
    if [ -t 0 ]; then
      read -r -p "  Hochladen? [j/N] " antwort
      case "$antwort" in
        j|J|ja|Ja) ;;
        *) echo "  Abgebrochen — nichts hochgeladen."; exit 3 ;;
      esac
    else
      echo "  Kein Terminal für die Rückfrage: Einreichen braucht --ja. Nichts hochgeladen."
      exit 3
    fi
  fi
  protokoll="$ORDNER/$STEMPEL-$kurz-einreichung.txt"
  if ! xcrun notarytool submit "$datei" --keychain-profile "$PROFIL" --wait --timeout 1h 2>&1 | tee "$protokoll"; then
    echo "  notarytool meldet einen Fehler — siehe $protokoll"
  fi
  kennung="$(sed -n 's/^ *id: //p' "$protokoll" | head -1)"
  status="$(sed -n 's/^ *status: //p' "$protokoll" | tail -1)"
  if [ -n "$kennung" ]; then
    # Apples Bericht nennt auch bei „Accepted“ Hinweise; bei „Invalid“ die Gründe.
    xcrun notarytool log "$kennung" --keychain-profile "$PROFIL" \
      "$ORDNER/$STEMPEL-$kurz-bericht.json" >/dev/null 2>&1 || true
  fi
  printf '%s  %s  %s  id=%s  status=%s\n' "$STEMPEL" "$kurz" "$(basename "$datei")" \
    "${kennung:-?}" "${status:-?}" >> "$ZUSAMMENFASSUNG"
  if [ "$status" != "Accepted" ]; then
    echo "  Nicht beglaubigt (Status: ${status:-unbekannt}) — Gründe in $ORDNER/$STEMPEL-$kurz-bericht.json"
    exit 1
  fi
  echo "  Beglaubigt — Einreichung $kennung"
}

if [ "$APP" = "1" ]; then
  ZIP="$HIER/Paket/$NAME-$FASSUNG${STUFE:+-$STUFE}-App.zip"
  echo "▸ Packe die App zum Hochladen (ditto, bewahrt die Signatur) …"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$PAKET" "$ZIP"
  einreichen "$ZIP" app
  rm -f "$ZIP"
  echo "▸ Hefte das Ticket an die App …"
  xcrun stapler staple -q "$PAKET"
  xcrun stapler validate -q "$PAKET" && echo "  Ticket geprüft (stapler validate)"
  echo "▸ Gatekeepers Sicht auf die App:"
  spctl -a -t exec -vv "$PAKET" 2>&1 | sed 's/^/  /'
fi

if [ "$DMG" = "1" ]; then
  echo "▸ Abbild um die beglaubigte App (./bauen.sh --nur-dmg) …"
  ./bauen.sh --nur-dmg
  einreichen "$ABBILD" dmg
  echo "▸ Hefte das Ticket an das Abbild …"
  xcrun stapler staple -q "$ABBILD"
  xcrun stapler validate -q "$ABBILD" && echo "  Ticket geprüft (stapler validate)"
  echo "▸ Gatekeepers Sicht auf das Abbild:"
  spctl -a -t open --context context:primary-signature -v "$ABBILD" 2>&1 | sed 's/^/  /'
  if hdiutil verify "$ABBILD" >/dev/null 2>&1; then
    echo "  hdiutil verify: geprüft"
  else
    echo "  hdiutil verify schlägt nach dem Anheften fehl — das Abbild nicht weitergeben."
    exit 1
  fi
  printf '%s  dmg  Prüfsumme SHA-256 %s\n' "$STEMPEL" "$(shasum -a 256 "$ABBILD" | cut -d' ' -f1)" >> "$ZUSAMMENFASSUNG"
  echo "▸ Fertig: $ABBILD"
fi

echo "  Zusammenfassung: $ZUSAMMENFASSUNG"
