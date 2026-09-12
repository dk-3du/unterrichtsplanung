#!/bin/bash
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: GPL-3.0-or-later
# ──────────────────────────────────────────────────────────────────────────
#  Unterrichtsplanung — die Prüfungen vor dem Bau, in einem Lauf (E39)
#
#     ./pruefen.sh             swift test im eigenen Prüfordner, dann die
#                              Skripte der Ansicht (csp_hashes --selbsttest und
#                              Abgleich, masse, leser, schulwochen, weblinks,
#                              abzug); Vermerk Paket/Pruefung-<Stempel>.txt mit
#                              dem Stand der Quellen und jedem Ergebnis
#     ./pruefen.sh --schnell   ohne abzug_pruefen.py und tresor_pruefen.py
#                              (beide brauchen swiftc, zusammen ~2 min)
#     ./pruefen.sh --stand     nur den Stand der Quellen ausgeben (für --probe)
#
#  beglaubigen.sh --probe weist hin, wenn der Vermerk fehlt, nicht zum Stand
#  der Quellen passt oder einen Befund trägt — Hinweis, keine Sperre; der
#  Entwicklungsbau (./bauen.sh) bleibt so schnell wie bisher.
# ──────────────────────────────────────────────────────────────────────────
set -uo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HIER"
FASSUNG="$(basename "$HIER")"
ANSICHT="$(cd "$HIER/../../Web-App/$FASSUNG" 2>/dev/null && pwd || true)"
SCHNELL=0
NURSTAND=0
for arg in "$@"; do
  case "$arg" in
    --schnell) SCHNELL=1 ;;
    --stand)   NURSTAND=1 ;;
    *) echo "Unbekannte Angabe: $arg"; exit 2 ;;
  esac
done
if [ -z "$ANSICHT" ]; then echo "Die Ansicht fehlt: ../../Web-App/$FASSUNG"; exit 2; fi

# Der Stand der Quellen: eine Prüfsumme über alles, was ins Programm und in
# die Ansicht eingeht — damit der Vermerk sagt, wofür er gilt.
quellenstand() {
  {
    (cd "$HIER" && find Quellen Pruefungen Beiwerk Package.swift bauen.sh beglaubigen.sh pruefen.sh \
        -type f ! -name .DS_Store | LC_ALL=C sort | xargs shasum -a 256)
    (cd "$ANSICHT" && find . -maxdepth 1 -type f \( -name '*.html' -o -name '*.py' -o -name '*.json' -o -name '*.webmanifest' \) \
        | LC_ALL=C sort | xargs shasum -a 256)
  } | shasum -a 256 | cut -c1-64
}
if [ "$NURSTAND" = "1" ]; then quellenstand; exit 0; fi

STEMPEL="$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$HIER/Paket"
VERMERK="$HIER/Paket/Pruefung-$STEMPEL.txt"
PRUEFORDNER="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unterrichtsplanung-pruefung.XXXXXX")"
PROTOKOLL="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/unterrichtsplanung-protokoll.XXXXXX")"
trap 'rm -rf "$PRUEFORDNER" "$PROTOKOLL"' EXIT
if [ -z "$PRUEFORDNER" ] || [ ! -d "$PRUEFORDNER" ]; then echo "Kein Prüfordner — Abbruch."; exit 2; fi

ERGEBNIS=0
{
  echo "Unterrichtsplanung $FASSUNG — Prüfvermerk"
  echo "Stempel:      $STEMPEL"
  echo "Quellenstand: $(quellenstand)"
  echo "Prüfordner:   $PRUEFORDNER"
  echo
} > "$VERMERK"

# $1 Name, dann der Befehl. Ergebnis und die Kernzeile des Protokolls in den Vermerk.
schritt() {
  local name="$1"; shift
  echo "▸ $name"
  if "$@" > "$PROTOKOLL" 2>&1; then
    echo "  ✓ $name"
    echo "✓ $name" >> "$VERMERK"
  else
    echo "  ✗ $name"
    tail -30 "$PROTOKOLL"
    echo "✗ $name" >> "$VERMERK"
    ERGEBNIS=1
  fi
  grep -E "Test run with|Faelle|Faellen|stimmig|bestanden|Festwerte|gruen|Abweichung|ABWEICHUNG" "$PROTOKOLL" \
    | tail -1 | sed 's/^/    /' >> "$VERMERK"
}

schritt "swift test (PLANUNGSORDNER=$PRUEFORDNER)" env PLANUNGSORDNER="$PRUEFORDNER" swift test
cd "$ANSICHT"
schritt "csp_hashes.py --selbsttest" python3 csp_hashes.py --selbsttest
schritt "csp_hashes.py (Hashes stimmig)" python3 csp_hashes.py
schritt "masse_pruefen.py" python3 masse_pruefen.py
schritt "leser_pruefen.py" python3 leser_pruefen.py
schritt "schulwochen_pruefen.py" python3 schulwochen_pruefen.py
schritt "weblinks_pruefen.py" python3 weblinks_pruefen.py
if [ "$SCHNELL" = "1" ]; then
  echo "· abzug_pruefen.py und tresor_pruefen.py übersprungen (--schnell)" >> "$VERMERK"
else
  schritt "abzug_pruefen.py" python3 abzug_pruefen.py
  schritt "tresor_pruefen.py --erzeugen" python3 tresor_pruefen.py --erzeugen "$PRUEFORDNER/tresor"
fi
cd "$HIER"
{
  echo
  if [ "$ERGEBNIS" = "0" ]; then echo "Ergebnis: bestanden"; else echo "Ergebnis: mit Befund"; fi
} >> "$VERMERK"
echo
echo "Vermerk: $VERMERK"
cat "$VERMERK"
exit "$ERGEBNIS"
