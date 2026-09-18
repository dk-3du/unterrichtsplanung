#!/bin/bash
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: GPL-3.0-or-later
# ──────────────────────────────────────────────────────────────────────────
#  Unterrichtsplanung — die Prüfungen vor dem Bau, in einem Lauf (E39)
#
#     ./pruefen.sh             swift test im eigenen Prüfordner — frisch
#                              übersetzt, mit Zählung der Warnungen (E104) —,
#                              dann der Release-Bau ebenso, dann die Skripte
#                              der Ansicht (katalog_pruefen, csp_hashes --selbsttest und
#                              Abgleich, masse, leser, schulwochen, weblinks,
#                              abzug); Vermerk Paket/Pruefung-<Stempel>.txt mit
#                              dem Stand der Quellen, jedem Ergebnis und den
#                              Zeilen „Warnungen (…): 0“ — jede Warnung ist ein
#                              Befund (✗), und beglaubigen.sh verlangt die Zählung
#     ./pruefen.sh --schnell   ohne abzug_pruefen.py und tresor_pruefen.py
#                              (beide brauchen swiftc, zusammen ~2 min) — der
#                              Vermerk trägt dann „Profil: schnell“ und reicht
#                              für die Beglaubigung nicht
#     ./pruefen.sh --stand     nur den Stand der Quellen ausgeben (für --probe)
#     ./pruefen.sh --werkzeugstand   nur den Werkzeugstand ausgeben (Block aus
#                              bauumgebung.sh: Xcode, Swift, SDK, Mindestsystem,
#                              Ziel, Linker) — für Doku und Vergleich
#     ./pruefen.sh --inventar  nur das Inventar prüfen (siehe unten)
#
#  Der Stand der Quellen kommt aus einem Inventar statt aus einer Aufzählung von
#  Hand: die Ordner Quellen, Pruefungen, Beiwerk ganz, aus der Fassungswurzel
#  jedes Skript (*.sh, *.py), Package.swift und LICENSE.txt; von der Ansicht die
#  Dateien der Wurzel nach Muster und der Ordner symbol. Der erste Schritt des
#  Laufs prüft, dass in beiden Wurzeln nichts liegt, was weder gedeckt noch
#  ausdrücklich ausgenommen ist — ein neues Skript ändert den Stand von selbst,
#  und Unbekanntes macht den Lauf rot. Ebenso jede symbolische Verknüpfung in
#  einer Wurzel oder einem gedeckten Ordner: Der Stand sammelt nur gewöhnliche
#  Dateien, eine Verknüpfung wäre dem Namen nach gedeckt und dem Inhalt nach nicht.
#
#  Seit v63 (E126, E127): Prüfbau und Release-Prüfbau bekommen dieselben
#  Linkerargumente wie das Paket (-platform_version, E106), die LC_BUILD_VERSION
#  des Release-Prüfbaus wird geprüft, und der Vermerk trägt den Werkzeugstand
#  (Kennung und Block) — beglaubigen.sh verlangt, dass er dem des Pakets und
#  dem dieses Rechners gleicht. Geprüft ist damit, was gebaut wird, und womit.
#
#  Der Vermerk entsteht als Pruefung-<Stempel>.txt.laeuft und heißt erst nach
#  dem letzten Schritt Pruefung-<Stempel>.txt — mit „Profil:“ und der
#  Ergebniszeile als Abschluss; ein abgebrochener Lauf lässt die .laeuft-Datei
#  liegen (B19). beglaubigen.sh --probe weist hin, wenn der Vermerk fehlt,
#  unvollständig oder verkürzt ist, nicht zum Stand der Quellen passt oder
#  einen Befund trägt; --ja verlangt ihn (E44, --ohne-pruefung umgeht das
#  protokolliert). Der Entwicklungsbau (./bauen.sh) bleibt unberührt.
# ──────────────────────────────────────────────────────────────────────────
set -uo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HIER"
FASSUNG="$(basename "$HIER")"
# Die Bauumgebung an einer Stelle: Linkerargumente, Werkzeugstand, LC_BUILD_VERSION.
. "$HIER/bauumgebung.sh"
ANSICHT="$(cd "$HIER/../../Web-App/$FASSUNG" 2>/dev/null && pwd || true)"
SCHNELL=0
NURSTAND=0
NURWERKZEUG=0
NURINVENTAR=0
for arg in "$@"; do
  case "$arg" in
    --schnell) SCHNELL=1 ;;
    --stand)   NURSTAND=1 ;;
    --werkzeugstand) NURWERKZEUG=1 ;;
    --inventar) NURINVENTAR=1 ;;
    *) echo "Unbekannte Angabe: $arg"; exit 2 ;;
  esac
done
if [ -z "$ANSICHT" ]; then echo "Die Ansicht fehlt: ../../Web-App/$FASSUNG"; exit 2; fi

# Der Stand der Quellen: eine Prüfsumme über alles, was ins Programm und in
# die Ansicht eingeht — damit der Vermerk sagt, wofür er gilt. Der Stand
# behauptet Vollständigkeit; deshalb zählt jede Stufe (N52-04, E63): Scheitert
# eine Aufzählung oder eine Prüfsumme, kommt keine Kennung heraus, sondern ein
# Fehlschlag. Eine leere Aufzählung ist ebenfalls einer — sie hieße, dass der
# Ordner nicht der ist, für den wir ihn halten.

# Die Prüfsummen einer Aufzählung an die Sammeldatei hängen.
# $1 Ordner, $2 Sammeldatei, danach die Angaben für find (ab den Pfaden).
standSammeln() {
  local ordner="$1" sammlung="$2"; shift 2
  local liste ergebnis=0
  liste="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/unterrichtsplanung-standliste.XXXXXX")" || return 1
  # Namen mit \0 getrennt: kein Zerfallen an Leerzeichen oder Anführungszeichen.
  if ! (cd "$ordner" && find "$@" -print0) | LC_ALL=C sort -z > "$liste"; then ergebnis=1; fi
  if [ "$ergebnis" = "0" ] && [ ! -s "$liste" ]; then ergebnis=1; fi
  if [ "$ergebnis" = "0" ]; then
    if ! (cd "$ordner" && xargs -0 shasum -a 256 < "$liste") >> "$sammlung"; then ergebnis=1; fi
  fi
  rm -f "$liste"
  return "$ergebnis"
}

# Das Inventar an einer Stelle: Ordner ganz, dazu die Dateien der Wurzel nach
# Muster. Was sonst in der Wurzel liegt, steht in der Ausnahmeliste — oder der
# Prüflauf wird rot: Ein neues Skript ist gedeckt, ohne dass jemand daran
# denken muss, und Unbekanntes bleibt nicht unbemerkt draußen.
APP_ORDNER=(Quellen Pruefungen Beiwerk)
APP_MUSTER=('*.sh' '*.py' 'Package.swift' 'LICENSE.txt')
APP_AUSNAHMEN=(LIESMICH.md Paket .build .swiftpm .DS_Store .claude __pycache__)
ANSICHT_ORDNER=(symbol)
ANSICHT_MUSTER=('*.html' '*.py' '*.json' '*.webmanifest' 'LICENSE.txt')
ANSICHT_AUSNAHMEN=(LIESMICH.md .DS_Store .claude __pycache__)

# $1 Ordner, dann Ordnernamen -- Muster -- Ausnahmen. Nennt, was weder gedeckt
# noch ausgenommen ist; Rückgabe 1, sobald es so etwas gibt.
inventarPruefen() {
  local ordner="$1"; shift
  local teil=0 ordnernamen=() muster=() ausnahmen=() name m gedeckt ausgenommen offen=0 gezaehlt=0 verknuepft
  for m in "$@"; do
    if [ "$m" = "--" ]; then teil=$((teil + 1)); continue; fi
    case "$teil" in
      0) ordnernamen+=("$m") ;;
      1) muster+=("$m") ;;
      *) ausnahmen+=("$m") ;;
    esac
  done
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    gedeckt=0
    ausgenommen=0
    if [ -d "$ordner/$name" ]; then
      for m in ${ordnernamen[@]+"${ordnernamen[@]}"}; do [ "$name" = "$m" ] && gedeckt=1; done
    else
      # shellcheck disable=SC2254
      for m in ${muster[@]+"${muster[@]}"}; do case "$name" in $m) gedeckt=1 ;; esac; done
    fi
    for m in ${ausnahmen[@]+"${ausnahmen[@]}"}; do [ "$name" = "$m" ] && gedeckt=1 && ausgenommen=1; done
    # Eine symbolische Verknüpfung ist nie gedeckt: Der Stand sammelt nur
    # gewöhnliche Dateien (find -type f) — ihr Name stünde im Inventar, ihr
    # Inhalt in keiner Prüfsumme.
    if [ -L "$ordner/$name" ] && [ "$ausgenommen" = "0" ]; then
      echo "  symbolische Verknüpfung — der Quellenstand sammelt sie nicht: $(basename "$(dirname "$ordner")")/$(basename "$ordner")/$name"
      offen=$((offen + 1))
      continue
    fi
    if [ "$gedeckt" = "1" ]; then
      gezaehlt=$((gezaehlt + 1))
    else
      echo "  nicht im Quellenstand und nicht ausgenommen: $(basename "$(dirname "$ordner")")/$(basename "$ordner")/$name"
      offen=$((offen + 1))
    fi
  done < <(ls -A "$ordner")
  # Dasselbe in den gedeckten Ordnern, in jeder Tiefe.
  for m in ${ordnernamen[@]+"${ordnernamen[@]}"}; do
    [ -d "$ordner/$m" ] && [ ! -L "$ordner/$m" ] || continue
    while IFS= read -r verknuepft; do
      [ -z "$verknuepft" ] && continue
      echo "  symbolische Verknüpfung — der Quellenstand sammelt sie nicht: $(basename "$(dirname "$ordner")")/$(basename "$ordner")/$verknuepft"
      offen=$((offen + 1))
    done < <(cd "$ordner" && find "$m" -type l)
  done
  [ "$offen" = "0" ] || return 1
  echo "  $(basename "$(dirname "$ordner")")/$(basename "$ordner"): $gezaehlt Einträge der Wurzel gedeckt oder ausgenommen"
}

inventar() {
  local ergebnis=0
  inventarPruefen "$HIER" ${APP_ORDNER[@]+"${APP_ORDNER[@]}"} -- "${APP_MUSTER[@]}" -- "${APP_AUSNAHMEN[@]}" || ergebnis=1
  inventarPruefen "$ANSICHT" ${ANSICHT_ORDNER[@]+"${ANSICHT_ORDNER[@]}"} -- "${ANSICHT_MUSTER[@]}" -- "${ANSICHT_AUSNAHMEN[@]}" || ergebnis=1
  [ "$ergebnis" = "0" ] && echo "Inventar stimmig"
  return "$ergebnis"
}

# $1 Ordner, $2 Sammeldatei, dann Ordnernamen -- Muster: die Ordner ganz, aus
# der Wurzel die Dateien nach Muster — dieselben Listen wie im Inventar.
standTeil() {
  local ordner="$1" sammlung="$2"; shift 2
  local teil=0 ordnernamen=() auswahl=() m
  for m in "$@"; do
    if [ "$m" = "--" ]; then teil=1; continue; fi
    if [ "$teil" = "0" ]; then ordnernamen+=("$m"); else
      [ "${#auswahl[@]}" = "0" ] || auswahl+=(-o)
      auswahl+=(-name "$m")
    fi
  done
  if [ "${#ordnernamen[@]}" != "0" ]; then
    standSammeln "$ordner" "$sammlung" "${ordnernamen[@]}" -type f ! -name .DS_Store || return 1
  fi
  standSammeln "$ordner" "$sammlung" . -maxdepth 1 -type f \( "${auswahl[@]}" \) || return 1
}

quellenstand() {
  local sammlung stand ergebnis=0
  sammlung="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/unterrichtsplanung-stand.XXXXXX")" || return 1
  standTeil "$HIER" "$sammlung" ${APP_ORDNER[@]+"${APP_ORDNER[@]}"} -- "${APP_MUSTER[@]}" || ergebnis=1
  if [ "$ergebnis" = "0" ]; then
    standTeil "$ANSICHT" "$sammlung" ${ANSICHT_ORDNER[@]+"${ANSICHT_ORDNER[@]}"} -- "${ANSICHT_MUSTER[@]}" || ergebnis=1
  fi
  if [ "$ergebnis" = "0" ]; then
    stand="$(shasum -a 256 < "$sammlung" | cut -c1-64)" || ergebnis=1
  fi
  rm -f "$sammlung"
  # 64 Hexziffern oder nichts.
  if [ "$ergebnis" = "0" ] && [ "${#stand}" = "64" ] && [ -z "${stand//[0-9a-f]/}" ]; then
    printf '%s\n' "$stand"
    return 0
  fi
  return 1
}
if [ "$NURSTAND" = "1" ]; then quellenstand; exit $?; fi
if [ "$NURWERKZEUG" = "1" ]; then werkzeugstand; exit $?; fi
if [ "$NURINVENTAR" = "1" ]; then inventar; exit $?; fi

# Ohne Stand kein Vermerk: Er sagt, wofür er gilt — das muss er halten können.
STAND="$(quellenstand)" || {
  echo "Der Stand der Quellen ließ sich nicht vollständig bestimmen — kein Vermerk, keine Prüfung."
  exit 2
}
# Ebenso der Werkzeugstand (E127): Ein Vermerk, der nicht sagt, womit geprüft
# wurde, bindet die Beglaubigung nicht.
WERKZEUG="$(werkzeugkennung)" || {
  echo "Der Werkzeugstand ließ sich nicht bestimmen (bauumgebung.sh) — kein Vermerk, keine Prüfung."
  exit 2
}
WERKZEUGBLOCK="$(werkzeugstand)"
linkerargumente || exit 2

STEMPEL="$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$HIER/Paket"
VERMERK="$HIER/Paket/Pruefung-$STEMPEL.txt"
# Bis zum Abschluss unter anderem Namen — ein Abbruch hinterlässt ihn (B19).
LAUFEND="$VERMERK.laeuft"
PRUEFORDNER="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unterrichtsplanung-pruefung.XXXXXX")"
PROTOKOLL="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/unterrichtsplanung-protokoll.XXXXXX")"
trap 'rm -rf "$PRUEFORDNER" "$PROTOKOLL"' EXIT
if [ -z "$PRUEFORDNER" ] || [ ! -d "$PRUEFORDNER" ]; then echo "Kein Prüfordner — Abbruch."; exit 2; fi

ERGEBNIS=0
{
  echo "Unterrichtsplanung $FASSUNG — Prüfvermerk"
  echo "Stempel:      $STEMPEL"
  echo "Quellenstand: $STAND"
  echo "Werkzeugstand: $WERKZEUG"
  printf '%s\n' "$WERKZEUGBLOCK" | sed 's/^/  /'
  echo "Rechner:      $(rechner)"
  echo "Profil:       $([ "$SCHNELL" = "1" ] && echo schnell || echo vollständig)"
  echo "Prüfordner:   $PRUEFORDNER"
  echo
} > "$LAUFEND"

# $1 Name, dann der Befehl. Ergebnis und die Kernzeile des Protokolls in den Vermerk.
schritt() {
  local name="$1"; shift
  echo "▸ $name"
  if "$@" > "$PROTOKOLL" 2>&1; then
    echo "  ✓ $name"
    echo "✓ $name" >> "$LAUFEND"
  else
    echo "  ✗ $name"
    tail -30 "$PROTOKOLL"
    echo "✗ $name" >> "$LAUFEND"
    ERGEBNIS=1
  fi
  grep -E "Test run with|Faelle|Faellen|stimmig|bestanden|Festwerte|gruen|Abweichung|ABWEICHUNG" "$PROTOKOLL" \
    | tail -1 | sed 's/^/    /' >> "$LAUFEND"
}

# Warnungen zählen (E104, seit v59): Der Bau läuft mit eigenem --scratch-path
# im Prüfordner und übersetzt deshalb jede Datei neu — nur so stehen alle
# Warnungen im Protokoll; ein warmer .build-Ordner schwiege über Bekanntes.
# Gezählt werden die Stellen (Datei:Zeile:Spalte, ohne Wiederholungen); jede
# ist ein Befund. Unter Xcode 27 / Swift 6.4 waren es an v58 vierzehn.
# $1 Name des Baus; liest das Protokoll des letzten Schritts.
warnungenZaehlen() {
  local name="$1" stellen anzahl
  stellen="$(sed -E 's/\x1b\[[0-9;]*m//g' "$PROTOKOLL" | grep -E '^/.*:[0-9]+:[0-9]+: warning:' \
             | sed -E "s#^$HIER/##" | sort -u || true)"
  anzahl="$(grep -c . <<<"$stellen" || true)"
  if [ "$anzahl" = "0" ]; then
    echo "  ✓ Warnungen ($name): 0"
    echo "Warnungen ($name): 0" >> "$LAUFEND"
  else
    echo "  ✗ Warnungen ($name): $anzahl"
    echo "$stellen" | sed 's/^/    /'
    echo "✗ Warnungen ($name): $anzahl" >> "$LAUFEND"
    echo "$stellen" | sed 's/^/    /' >> "$LAUFEND"
    ERGEBNIS=1
  fi
}
BAUORDNER="$PRUEFORDNER/bau"

# Zuerst das Inventar: Der Vermerk gilt für den Stand — also muss der Stand
# alles decken, was zur Fassung gehört.
schritt "Inventar (der Quellenstand deckt die Fassungswurzeln)" inventar

# Mit den Linkerargumenten des Pakets (E126): Geprüft wird, was gebaut wird.
schritt "swift test (frisch übersetzt, PLANUNGSORDNER=$PRUEFORDNER, -platform_version)" \
    env PLANUNGSORDNER="$PRUEFORDNER" swift test --scratch-path "$BAUORDNER" "${LINKER[@]}"
warnungenZaehlen "Programm und Prüfungen"
schritt "swift build --configuration release (frisch übersetzt, -platform_version)" \
    swift build --configuration release --arch arm64 --scratch-path "$BAUORDNER" "${LINKER[@]}"
warnungenZaehlen "Programm, release"
# Nachgeprüft am Prüfbau, wie bauen.sh es am Paket tut: Der Vermerk sagt, wie
# das geprüfte Programm gebunden ist; beglaubigen.sh hält es gegen das Paket.
bauversionSchritt() {
  local programm ist
  programm="$(swift build --configuration release --arch arm64 --scratch-path "$BAUORDNER" --show-bin-path 2>/dev/null)/Unterrichtsplanung"
  echo "▸ LC_BUILD_VERSION (Prüfbau)"
  if ist="$(bauversionPruefen "$programm" 2>"$PROTOKOLL")"; then
    echo "  ✓ LC_BUILD_VERSION (Prüfbau): minos ${ist% *} sdk ${ist#* }"
    echo "✓ LC_BUILD_VERSION (Prüfbau): minos ${ist% *} sdk ${ist#* }" >> "$LAUFEND"
  else
    echo "  ✗ LC_BUILD_VERSION (Prüfbau): $(cat "$PROTOKOLL")"
    echo "✗ LC_BUILD_VERSION (Prüfbau): $(cat "$PROTOKOLL")" >> "$LAUFEND"
    ERGEBNIS=1
  fi
}
bauversionSchritt
# Der Rundentreiber gehört zum Quellenstand (E146, v67): Seit v68 (N67-01,
# E151) prüft er hier seine Bewertung an synthetischen Ausgaben — der Selbsttest
# übersetzt das Skript mit (--syntax); die Runde selbst fährt er am gebauten
# Paket (./runde.py).
schritt "runde.py --selbsttest (Bewertung des Rundentreibers)" python3 "$HIER/runde.py" --selbsttest
# Die Vorlagen der Materialliste gegen jsc (E183, v71): Prüfsumme und Inhalt
# jeder Vorlage gegen ihr erwartetes JSON — die Swift-Prüfung hält den eigenen
# Leser gegen dasselbe JSON.
schritt "katalog_pruefen.py (Vorlagen der Materialliste gegen jsc)" python3 "$HIER/katalog_pruefen.py"
cd "$ANSICHT"
schritt "csp_hashes.py --selbsttest" python3 csp_hashes.py --selbsttest
schritt "csp_hashes.py (Hashes stimmig)" python3 csp_hashes.py
schritt "masse_pruefen.py" python3 masse_pruefen.py
schritt "leser_pruefen.py" python3 leser_pruefen.py
schritt "schulwochen_pruefen.py" python3 schulwochen_pruefen.py
schritt "weblinks_pruefen.py" python3 weblinks_pruefen.py
if [ "$SCHNELL" = "1" ]; then
  echo "· abzug_pruefen.py und tresor_pruefen.py übersprungen (--schnell)" >> "$LAUFEND"
else
  schritt "abzug_pruefen.py" python3 abzug_pruefen.py
  schritt "tresor_pruefen.py --erzeugen" python3 tresor_pruefen.py --erzeugen "$PRUEFORDNER/tresor"
fi
cd "$HIER"
{
  echo
  if [ "$ERGEBNIS" = "0" ]; then echo "Ergebnis: bestanden"; else echo "Ergebnis: mit Befund"; fi
} >> "$LAUFEND"
# Erst jetzt trägt er seinen Namen: vollständig, mit Ergebniszeile.
mv "$LAUFEND" "$VERMERK"
echo
echo "Vermerk: $VERMERK"
cat "$VERMERK"
exit "$ERGEBNIS"
