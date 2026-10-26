#!/bin/bash
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: GPL-3.0-or-later
# ──────────────────────────────────────────────────────────────────────────
#  Unterrichtsplanung — die Prüfungen vor dem Bau, in einem Lauf (E39)
#
#     ./pruefen.sh             swift test im eigenen Prüfordner — frisch
#                              übersetzt, mit Zählung der Warnungen (E104) —,
#                              ohne die Messungen der Rechenzeit, die danach
#                              allein und seriell laufen (E553, E591), dann
#                              die Verzögerungsprobe (die Suite ohne die
#                              Messungen noch zweimal seriell, gestaucht und
#                              gedehnt; E551, E590), dann der Release-Bau,
#                              ebenso frisch übersetzt und gezählt, dann die Skripte
#                              der Ansicht (katalog_pruefen, csp_hashes --selbsttest und
#                              Abgleich, masse, leser, schulwochen, weblinks,
#                              abzug); Vermerk Paket/Pruefung-<Stempel>.txt mit
#                              dem Stand der Quellen, jedem Ergebnis und den
#                              Zeilen „Warnungen (…): 0“ — jede Warnung ist ein
#                              Befund (✗), und beglaubigen.sh verlangt die Zählung;
#                              bei ✗ dazu die Befundzeilen und das ganze Protokoll
#                              als Paket/Pruefprotokoll-<Stempel>-<n>.txt (E486)
#     ./pruefen.sh --schnell   ohne abzug_pruefen.py, tresor_pruefen.py (beide
#                              brauchen swiftc, zusammen ~2 min) und die
#                              Verzögerungsprobe (~4 min) — der
#                              Vermerk trägt dann „Profil: schnell“ und reicht
#                              für die Beglaubigung nicht
#     ./pruefen.sh --stand     nur den Stand der Quellen ausgeben (für bauen.sh
#                              und beglaubigen.sh) — ohne stimmiges Inventar
#                              keiner: Rückgabe 1, der Grund auf stderr
#     ./pruefen.sh --werkzeugstand   nur den Werkzeugstand ausgeben (Block aus
#                              bauumgebung.sh: Xcode, Swift, SDK, Mindestsystem,
#                              Ziel, Linker) — für Doku und Vergleich
#     ./pruefen.sh --inventar  nur das Inventar prüfen (siehe unten)
#     ./pruefen.sh --inventar-selbsttest   nur die Regel „ohne stimmiges
#                              Inventar kein Stand“ an kleinen Prüfordnern
#     ./pruefen.sh --wartestellen   nur die Regel „keine Prüfung wartet mit Takt
#                              oder Uhr, außer sie ist am Ort mit ihrer Art
#                              benannt und die Art hat noch Platz“ (E145, E210,
#                              E215, E550, E555), mit ihrer Gegenprobe
#     ./pruefen.sh --zeitgeber   nur die Regel „die Zeitgeber des Programms
#                              gehen über den Taktgeber, außer den benannten
#                              Ausnahmen“ (E561, E589, E595), mit ihrer Gegenprobe
#     ./pruefen.sh --webappname   nur die Regel „was jemand sieht, nennt die
#                              Web App Web App“ (E219), mit ihrer Gegenprobe
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
#  Seit v73 (E197, R72-01) ist das Inventar Bedingung jedes Stands, nicht nur ein
#  Schritt des Laufs: Ohne es gibt --stand nichts aus — bauen.sh übersetzt dann
#  nicht, beglaubigen.sh nennt den Grund. Ein Selbsttest hält die Regel. Am
#  Ende des Laufs wird der Stand noch einmal bestimmt (E201, B49); ist er ein
#  anderer als am Anfang, trägt der Vermerk einen Befund.
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
NURSELBSTTEST=0
NURWARTESTELLEN=0
NURZEITGEBER=0
NURWEBAPPNAME=0
for arg in "$@"; do
  case "$arg" in
    --schnell) SCHNELL=1 ;;
    --stand)   NURSTAND=1 ;;
    --werkzeugstand) NURWERKZEUG=1 ;;
    --inventar) NURINVENTAR=1 ;;
    --inventar-selbsttest) NURSELBSTTEST=1 ;;
    --wartestellen) NURWARTESTELLEN=1 ;;
    --zeitgeber) NURZEITGEBER=1 ;;
    --webappname) NURWEBAPPNAME=1 ;;
    *) echo "Unbekannte Angabe: $arg"; exit 2 ;;
  esac
done
# Hauptlauf und Messdurchgang laufen im Normalmaß des Systemtakts; PRUEFTAKT
# setzt nur die Verzögerungsprobe, je Aufruf (E551, Z-AT6h3-03).
unset PRUEFTAKT
if [ -z "$ANSICHT" ]; then echo "Die Web App fehlt: ../../Web-App/$FASSUNG"; exit 2; fi

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

# $1 Wurzel der App, $2 Wurzel der Ansicht — für den Selbsttest auch fremde.
inventarVon() {
  local app="$1" ansicht="$2" ergebnis=0
  inventarPruefen "$app" ${APP_ORDNER[@]+"${APP_ORDNER[@]}"} -- "${APP_MUSTER[@]}" -- "${APP_AUSNAHMEN[@]}" || ergebnis=1
  inventarPruefen "$ansicht" ${ANSICHT_ORDNER[@]+"${ANSICHT_ORDNER[@]}"} -- "${ANSICHT_MUSTER[@]}" -- "${ANSICHT_AUSNAHMEN[@]}" || ergebnis=1
  [ "$ergebnis" = "0" ] && echo "Inventar stimmig"
  return "$ergebnis"
}

inventar() { inventarVon "$HIER" "$ANSICHT"; }

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

# $1 Wurzel der App, $2 Wurzel der Ansicht. Ohne stimmiges Inventar kein Stand
# (E197, R72-01): Jeder, der den Stand liest — der Prüflauf, bauen.sh,
# beglaubigen.sh —, bekommt dann keinen, und der Grund steht auf stderr;
# stdout trägt nur die Kennung.
quellenstandVon() {
  local app="$1" ansicht="$2" sammlung stand befund ergebnis=0
  if ! befund="$(inventarVon "$app" "$ansicht")"; then
    { echo "Das Inventar ist nicht stimmig — kein Quellenstand:"; printf '%s\n' "$befund"; } >&2
    return 1
  fi
  sammlung="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/unterrichtsplanung-stand.XXXXXX")" || return 1
  standTeil "$app" "$sammlung" ${APP_ORDNER[@]+"${APP_ORDNER[@]}"} -- "${APP_MUSTER[@]}" || ergebnis=1
  if [ "$ergebnis" = "0" ]; then
    standTeil "$ansicht" "$sammlung" ${ANSICHT_ORDNER[@]+"${ANSICHT_ORDNER[@]}"} -- "${ANSICHT_MUSTER[@]}" || ergebnis=1
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

quellenstand() { quellenstandVon "$HIER" "$ANSICHT"; }

# Der Selbsttest des Inventars (E197, R72-01): Eine Regel über den Stand gilt
# erst, wenn sie an einem Ordner geprüft ist, an dem sie greifen muss. Je Fall
# eine kleine Fassung (Wurzel der App und der Ansicht) in einem eigenen
# Prüfordner; erwartet wird ein Stand oder keiner.
inventarSelbsttest() {
  local wurzel basis sauber stand grund ergebnis=0 gezaehlt=0
  wurzel="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unterrichtsplanung-inventar.XXXXXX")" || return 1
  basis="$wurzel/basis"
  mkdir -p "$basis/app/Quellen/Ziel" "$basis/app/Pruefungen" "$basis/app/Beiwerk" \
           "$basis/ansicht/symbol" "$wurzel/aussen/ordner" || { rm -rf "$wurzel"; return 1; }
  echo 'let a = 1' > "$basis/app/Quellen/Ziel/a.swift"
  echo 'let b = 2' > "$basis/app/Pruefungen/b.swift"
  echo '<plist/>' > "$basis/app/Beiwerk/Info.plist"
  echo '// swift-tools-version: 6.0' > "$basis/app/Package.swift"
  echo 'echo' > "$basis/app/bauen.sh"
  echo 'Lizenz' > "$basis/app/LICENSE.txt"
  echo 'Hinweis' > "$basis/app/LIESMICH.md"
  echo '<html></html>' > "$basis/ansicht/ansicht.html"
  echo 'Lizenz' > "$basis/ansicht/LICENSE.txt"
  echo 'png' > "$basis/ansicht/symbol/s.png"
  echo 'let c = 3' > "$wurzel/aussen/c.swift"
  echo 'let d = 4' > "$wurzel/aussen/ordner/d.swift"
  # $1 Fall: eine Kopie der kleinen Fassung.
  fall() { cp -R "$basis" "$wurzel/$1"; }
  # $1 Beschreibung, $2 Fall: Hier darf kein Stand herauskommen.
  keinStand() {
    gezaehlt=$((gezaehlt + 1))
    if quellenstandVon "$wurzel/$2/app" "$wurzel/$2/ansicht" >/dev/null 2>&1; then
      echo "  ✗ $1: ein Stand, obwohl das Inventar nicht stimmt"
      ergebnis=1
    else
      echo "  ✓ $1: kein Stand"
    fi
  }

  fall sauber
  gezaehlt=$((gezaehlt + 1))
  if sauber="$(quellenstandVon "$wurzel/sauber/app" "$wurzel/sauber/ansicht")"; then
    echo "  ✓ sauber: Stand $(cut -c1-12 <<<"$sauber")…"
  else
    echo "  ✗ sauber: kein Stand, obwohl das Inventar stimmt"
    ergebnis=1
  fi
  fall anderswo
  gezaehlt=$((gezaehlt + 1))
  stand="$(quellenstandVon "$wurzel/anderswo/app" "$wurzel/anderswo/ansicht" 2>/dev/null)" || stand=""
  if [ -n "$sauber" ] && [ "$stand" = "$sauber" ]; then
    echo "  ✓ dieselbe Fassung an anderem Ort: derselbe Stand"
  else
    echo "  ✗ dieselbe Fassung an anderem Ort: ein anderer Stand"
    ergebnis=1
  fi

  fall quelle-verknuepft
  ln -s "$wurzel/aussen/c.swift" "$wurzel/quelle-verknuepft/app/Quellen/Ziel/c.swift"
  keinStand "Verknüpfung in einem gedeckten Ordner" quelle-verknuepft
  # Der Grund steht auf stderr — ihn lesen bauen.sh und beglaubigen.sh.
  gezaehlt=$((gezaehlt + 1))
  grund="$(quellenstandVon "$wurzel/quelle-verknuepft/app" "$wurzel/quelle-verknuepft/ansicht" 2>&1 >/dev/null || true)"
  if grep -q "symbolische Verknüpfung.*Quellen/Ziel/c.swift" <<<"$grund"; then
    echo "  ✓ der Grund steht auf stderr"
  else
    echo "  ✗ der Grund fehlt auf stderr"
    ergebnis=1
  fi
  fall ordner-verknuepft
  ln -s "$wurzel/aussen/ordner" "$wurzel/ordner-verknuepft/app/Quellen/Ordner"
  keinStand "verknüpfter Ordner in einem gedeckten Ordner" ordner-verknuepft
  fall wurzel-verknuepft
  ln -s "$wurzel/aussen/c.swift" "$wurzel/wurzel-verknuepft/app/hilfe.sh"
  keinStand "Verknüpfung in der Wurzel unter gedecktem Muster" wurzel-verknuepft
  fall ungedeckt
  echo 'Notiz' > "$wurzel/ungedeckt/app/notiz.txt"
  keinStand "ungedeckte Datei in der Wurzel" ungedeckt
  fall ansicht-verknuepft
  ln -s "$wurzel/aussen/c.swift" "$wurzel/ansicht-verknuepft/ansicht/symbol/t.png"
  keinStand "Verknüpfung in der Web App" ansicht-verknuepft

  rm -rf "$wurzel"
  if [ "$ergebnis" = "0" ]; then
    echo "Inventar-Selbsttest: $gezaehlt Fälle bestanden"
  else
    echo "Inventar-Selbsttest: MIT BEFUND"
  fi
  return "$ergebnis"
}

# Wartestellen ohne Takt (E145 seit v66, gehalten seit v74 — E207, E210, E215):
# Eine Prüfung wartet auf ein Signal, auf das Ende einer Aufgabe oder mit
# abwarten(_:bis:) auf eine Bedingung — nie eine Zahl von Yields und nie eine
# Uhr. Erkannt wird jedes Task.yield(), jedes .sleep( (Task, Thread, eine
# Clock), sleep/usleep/nanosleep, RunLoop….run( und asyncAfter, in allen
# Unterordnern. Eine Uhr, die bleiben soll, trägt in ihrer Zeile die Marke
# „// E145: Uhr (<Art>) — <Grund>“; je Zeile zählt die erste Marke, reine
# Kommentarzeilen zählen nicht.
# Arten (v84, E550, E555): Stempel, Abbild, Messung und Takt dürfen bleiben;
# Ausbleiben, Eintreten, Reihenfolge, Verfall und Warteschlange (zwei Zeitgeber
# auf derselben Warteschlange) sind verboten: Höchstzahl 0. Ersatz: die Stelluhr
# (`vorruecken`), ein Signal des Programms (etwa ausstehendeFortsetzungen), der
# Meldungsfang oder Handeln vor dem ersten await. Auch erlaubte können unter Last
# kippen — Messung, Abbild.
# Die Höchstzahlen sind eine Ratsche:
# Zahl und Höchstzahl sind gleich, wer Uhren entfernt, senkt sie im selben Zug (E556).
# Rot, je mit den Stellen: eine Marke ohne Art oder unlesbar, eine unbekannte
# Art, ein unbekannter Schlüssel in den Höchstzahlen, eine Art über oder unter
# ihrer Höchstzahl. Die Schlusszeile nennt je Art Zahl/Höchstzahl (im Vermerk).
# Der Schritt liest Zeilen, nicht Bedeutung: Eine Wartestelle in einer Form,
# die das Muster nicht kennt, sieht er nicht, eine falsch genannte Art auch
# nicht — die Verzögerungsprobe findet sie nur, wo sie an einer Frist des
# Systemtakts hängt. Ein Lesefehler und ein Ordner ohne Swift-Datei sind rot —
# sonst hieße „nichts gefunden“ auch „nichts gelesen“.
UHRARTEN="Stempel Abbild Messung Takt Ausbleiben Eintreten Reihenfolge Verfall Warteschlange"
UHREN_HOECHSTENS="Stempel=5 Abbild=4 Messung=2 Takt=1 Ausbleiben=0 Eintreten=0 Reihenfolge=0 Verfall=0 Warteschlange=0"
# $1 Ordner der Prüfungen, $2 die Höchstzahlen (sonst UHREN_HOECHSTENS; eine
# fehlende Art hat 0). Rückgabe 1 bei jeder Abweichung oder einem Lesefehler.
wartestellenVon() {
  local ordner="$1" hoechstens="${2-$UHREN_HOECHSTENS}" treffer funde bericht rc anzahl
  [ -d "$ordner" ] || { echo "Kein Ordner der Prüfungen: $ordner"; return 1; }
  anzahl="$(/usr/bin/find "$ordner" -type f -name '*.swift' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  [ "$anzahl" -gt 0 ] || { echo "✗ Wartestellen: keine Swift-Datei in $ordner — gelesen wurde nichts"; return 1; }
  # -H: den Dateinamen auch bei einer einzigen Datei (B57); -r: auch in Unterordnern.
  treffer="$(cd "$ordner" && grep -rnHE --include='*.swift' \
    'Task\.yield\(\)|\.sleep[[:space:]]*\(|(^|[^A-Za-z0-9_.])(u|nano)?sleep[[:space:]]*\(|RunLoop.*\.run[[:space:]]*\(|asyncAfter[[:space:]]*\(' . 2>&1)"
  rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "✗ Wartestellen: grep scheiterte (Rückgabe $rc) — gelesen wurde nicht alles:"
    printf '%s\n' "$treffer" | grep -E '^grep:' | sed 's/^/  /'
    return 1
  fi
  treffer="$(printf '%s\n' "$treffer" | sed 's#^\./##' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)"
  # Gültig ist eine Marke mit nicht leerer Art; alles andere mit „E145: Uhr“ ist unlesbar.
  funde="$(grep -vE '// E145: Uhr \([^)]+\) — ' <<<"$treffer" | grep -v '^$' || true)"
  if [ -n "$funde" ]; then
    printf '%s\n' "$funde" | awk -F: '{ w = ($0 ~ /\/\/ E145: Uhr — /) ? "Marke ohne Art" : (($0 ~ /E145: Uhr/) ? "Marke unlesbar" : "ungenannt")
      print "✗ Wartestelle mit Takt oder Uhr in Pruefungen/" $1 ":" $2 " (" w ") — auf ein Signal, das Ende der Aufgabe oder abwarten(_:bis:) warten, oder benennen: // E145: Uhr (<Art>) — <Grund>" }'
    return 1
  fi
  # Je Zeile die erste Marke, je Art gezählt und gegen die Ratsche gehalten — awk, weil /bin/bash 3.2 keine Tabellen kennt.
  bericht="$(printf '%s\n' "$treffer" | awk -v arten="$UHRARTEN" -v hoechstens="$hoechstens" '
      BEGIN { marke = "// E145: Uhr ("; fehler = 0
              n = split(arten, a, " "); for (i = 1; i <= n; i++) bekannt[a[i]] = 1
              m = split(hoechstens, h, " ")
              for (i = 1; i <= m; i++) { split(h[i], kv, "="); grenze[kv[1]] = kv[2] + 0
                if (!(kv[1] in bekannt)) { print "✗ Unbekannter Schlüssel „" kv[1] "“ in den Höchstzahlen — bekannt: " arten; fehler = 1 } } }
      { p = index($0, marke); if (p == 0) next
        rest = substr($0, p + length(marke)); art = substr(rest, 1, index(rest, ")") - 1)
        split($0, f, ":"); ort = "Pruefungen/" f[1] ":" f[2]
        zahl[art]++; gesamt++; orte[art] = orte[art] (orte[art] == "" ? "" : ", ") ort }
      END { liste = ""
        for (art in zahl) if (!(art in bekannt)) { print "✗ Uhr mit unbekannter Art „" art "“ (" zahl[art] "×): " orte[art] " — bekannt: " arten; fehler = 1 }
        for (i = 1; i <= n; i++) { art = a[i]; z = zahl[art] + 0; g = (art in grenze) ? grenze[art] : 0
          if (z > g) { print "✗ Uhren der Art " art ": " z " benannt, höchstens " g " (Ratsche, E550): " orte[art]; fehler = 1 }
          else if (z < g) { print "✗ Ratsche nicht gesenkt: Art " art " hat " z " Uhren, Höchstzahl " g " — in UHREN_HOECHSTENS auf " z " senken (E556)"; fehler = 1 }
          if (z > 0 || g > 0) liste = liste (liste == "" ? "" : ", ") art " " z "/" g }
        print "SUMME " gesamt + 0 " (" liste ")"
        exit fehler }')"
  rc=$?
  grep -v '^SUMME ' <<<"$bericht" || true
  [ "$rc" -eq 0 ] || return 1
  echo "Wartestellen stimmig — $anzahl Dateien gelesen, benannt: $(sed -n 's/^SUMME //p' <<<"$bericht"), ungenannt: 0 (E145, E550)"
}

# Der Schritt: zuerst die Gegenprobe — ein Prüfordner mit jeder erkannten Form
# (elf Stellen, die gemeldet werden müssen, eine davon in einem Unterordner) und
# zwei, die bleiben dürfen (eine benannte Uhr, ein Kommentar); dazu ein Ordner
# mit einer unlesbaren Datei, einer ohne Swift-Datei und einer mit einer
# einzigen Datei; dazu elf Ordner für Arten und Ratsche (E550, E555, E556) —,
# dann die Prüfungen der Fassung.
wartestellen() {
  local probe gegen ergebnis=0
  probe="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unterrichtsplanung-wartestellen.XXXXXX")" || return 1
  mkdir -p "$probe/formen/Unter" "$probe/gesperrt" "$probe/leer" "$probe/einzeln" "$probe/einzeln-kommentar" \
    "$probe/alt" "$probe/unbekannt" "$probe/ratsche" "$probe/verboten" "$probe/ungesenkt" "$probe/genau" \
    "$probe/leer-art" "$probe/doppelt" "$probe/leerzeichen" "$probe/kommentar-verboten" "$probe/fremd"
  printf '%s\n' '        for _ in 0..<20 { await Task.yield() }' > "$probe/formen/TaktEinzeilig.swift"
  printf '%s\n' '        for _ in 0..<20 {' '            await Task.yield()' '        }' > "$probe/formen/TaktMehrzeilig.swift"
  printf '%s\n' '        while !fertig { await Task.yield() }' > "$probe/formen/Bedingung.swift"
  printf '%s\n' '        while rest > 0 { await Task.yield(); rest -= 1 }' > "$probe/formen/Zaehler.swift"
  printf '%s\n' '        try await Task.sleep(for: .milliseconds(50))' > "$probe/formen/TaskSleep.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)' > "$probe/formen/ThreadSleep.swift"
  printf '%s\n' '        usleep(1000)' > "$probe/formen/Usleep.swift"
  printf '%s\n' '        try await ContinuousClock().sleep(for: .milliseconds(5))' > "$probe/formen/ClockSleep.swift"
  printf '%s\n' '        RunLoop.current.run(until: Date().addingTimeInterval(0.35))' > "$probe/formen/RunLoop.swift"
  printf '%s\n' '        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { fertig = true }' > "$probe/formen/AsyncAfter.swift"
  printf '%s\n' '        try await Task.sleep(for: .seconds(1))' > "$probe/formen/Unter/Tief.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr (Stempel) — Stempelvorschub' > "$probe/formen/Benannt.swift"
  printf '%s\n' '        // Früher stand hier Task.sleep(for: .seconds(1)).' > "$probe/formen/Kommentar.swift"
  printf '%s\n' '        let x = 1' > "$probe/gesperrt/Offen.swift"
  printf '%s\n' '        let y = 2' > "$probe/gesperrt/Gesperrt.swift"
  /bin/chmod 000 "$probe/gesperrt/Gesperrt.swift"
  printf '%s\n' '        try await Task.sleep(for: .seconds(1))' > "$probe/einzeln/Einzeln.swift"
  printf '%s\n' '        // Früher stand hier Task.sleep(for: .seconds(1)).' > "$probe/einzeln-kommentar/Nur.swift"
  # Die Arten und die Ratsche (E550, E555, E556): Rot sind eine Marke ohne Art, eine leere Art „()“, eine unbekannte
  # Art (auch „( Stempel )“), eine Art über ihrer Grenze, eine verbotene (Grenze 0), eine Art unter ihrer Grenze
  # (nicht gesenkt) und ein unbekannter Schlüssel in den Höchstzahlen; grün sind eine getroffene Grenze (in der
  # Schlusszeile „Art z/g“), zwei Marken in einer Zeile (eine Uhr, einmal gezählt) und eine Marke im Kommentar.
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr — Stempelvorschub' > "$probe/alt/Alt.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr (Laune) — ohne Grund' > "$probe/unbekannt/Laune.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr (Stempel) — eins' \
    '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr (Stempel) — zwei' > "$probe/ratsche/Zwei.swift"
  printf '%s\n' '        try await Task.sleep(for: .milliseconds(150))  // E145: Uhr (Reihenfolge) — vor dem Zeitgeber' \
    > "$probe/verboten/Folge.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr (Stempel) — eins' > "$probe/ungesenkt/Eins.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr (Stempel) — eins' > "$probe/genau/Eins.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr () — ohne Art' > "$probe/leer-art/Leer.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr (Stempel) — eins // E145: Uhr (Stempel) — noch einmal' \
    > "$probe/doppelt/Doppelt.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr ( Stempel ) — mit Leerzeichen' > "$probe/leerzeichen/Raum.swift"
  printf '%s\n' '        // try await Task.sleep(for: .milliseconds(150))  // E145: Uhr (Reihenfolge) — alt, auskommentiert' \
    > "$probe/kommentar-verboten/Alt.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr (Stempel) — eins' > "$probe/fremd/Eins.swift"

  gegen="$(wartestellenVon "$probe/formen")"
  if [ "$(grep -c '^✗' <<<"$gegen")" != "11" ] || grep -qE 'Benannt|Kommentar' <<<"$gegen" \
     || ! grep -q 'Pruefungen/Unter/Tief.swift:1 ' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Die Formen greifen nicht wie verlangt —"
    printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  if wartestellenVon "$probe/gesperrt" > /dev/null; then
    echo "Gegenprobe der Wartestellen: Eine unlesbare Datei galt als gelesen."; ergebnis=1
  fi
  if wartestellenVon "$probe/leer" > /dev/null; then
    echo "Gegenprobe der Wartestellen: Ein Ordner ohne Swift-Datei galt als stimmig."; ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/einzeln")"
  if ! grep -q '^✗ Wartestelle mit Takt oder Uhr in Pruefungen/Einzeln.swift:1 ' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Eine einzelne Datei wird nicht mit Namen gemeldet —"
    printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  if ! wartestellenVon "$probe/einzeln-kommentar" "" > /dev/null; then
    echo "Gegenprobe der Wartestellen: Ein Kommentar in einer einzelnen Datei galt als Wartestelle."; ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/alt" "Stempel=5")"
  if [ $? -eq 0 ] || ! grep -q '^✗ Wartestelle mit Takt oder Uhr in Pruefungen/Alt.swift:1 (Marke ohne Art)' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Eine Marke ohne Art galt als benannt —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/unbekannt" "")"
  if [ $? -eq 0 ] || ! grep -q '^✗ Uhr mit unbekannter Art „Laune“ (1×)' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Eine unbekannte Art galt als zulässig —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/ratsche" "Stempel=1")"
  if [ $? -eq 0 ] || ! grep -q '^✗ Uhren der Art Stempel: 2 benannt, höchstens 1 (Ratsche, E550)' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Eine Art über ihrer Grenze galt als stimmig —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/verboten" "")"
  if [ $? -eq 0 ] || ! grep -q '^✗ Uhren der Art Reihenfolge: 1 benannt, höchstens 0 (Ratsche, E550)' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Eine verbotene Art galt als zulässig —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/ungesenkt" "Stempel=3")"
  if [ $? -eq 0 ] || ! grep -q '^✗ Ratsche nicht gesenkt: Art Stempel hat 1 Uhren, Höchstzahl 3' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Eine Art unter ihrer Grenze galt als stimmig (E556) —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/genau" "Stempel=1")"
  if [ $? -ne 0 ] || ! grep -q 'benannt: 1 (Stempel 1/1)' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Eine getroffene Grenze steht nicht als „Stempel 1/1“ in der Schlusszeile —"
    printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/leer-art" "")"
  if [ $? -eq 0 ] || ! grep -q '^✗ Wartestelle mit Takt oder Uhr in Pruefungen/Leer.swift:1 (Marke unlesbar)' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Eine leere Art „()“ galt als benannt —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/doppelt" "Stempel=1")"
  if [ $? -ne 0 ] || ! grep -q 'benannt: 1 (Stempel 1/1)' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Zwei Marken in einer Zeile zählten nicht als eine Uhr —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/leerzeichen" "")"
  if [ $? -eq 0 ] || ! grep -q '^✗ Uhr mit unbekannter Art „ Stempel “' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: „( Stempel )“ galt als zulässige Art —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  if ! wartestellenVon "$probe/kommentar-verboten" "" > /dev/null; then
    echo "Gegenprobe der Wartestellen: Eine Marke in einer Kommentarzeile wurde gezählt."; ergebnis=1
  fi
  gegen="$(wartestellenVon "$probe/fremd" "Stempel=1 Stmpel=2")"
  if [ $? -eq 0 ] || ! grep -q '^✗ Unbekannter Schlüssel „Stmpel“ in den Höchstzahlen' <<<"$gegen"; then
    echo "Gegenprobe der Wartestellen: Ein unbekannter Schlüssel in den Höchstzahlen blieb still —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  /bin/chmod 600 "$probe/gesperrt/Gesperrt.swift"
  rm -rf "$probe"
  wartestellenVon "$HIER/Pruefungen" || ergebnis=1
  [ "$ergebnis" = 0 ] || echo "✗ Wartestellen: Abweichung — die Gründe stehen im Protokoll des Schritts"
  return "$ergebnis"
}

# Zeitgeber im Programm (v84, AT6h-1, E548, E561, E589): Die Fristen des Speichers
# gehen über den Taktgeber — im Betrieb der Systemtakt, im Prüfziel die Stelluhr,
# in Debug-Bauten dazu PRUEFTAKT (E551). Außerhalb stehen nur die benannten
# Ausnahmen aus E561; jede trägt in ihrer Zeile die Marke
# „// E561: Zeitgeber (<Art>) — <Grund>“, je Zeile zählt die erste. Arten: AppKit
# (warten, bis ein Blatt frei ist), Oberfläche (Tour, Update-Blatt, Ansager,
# Lernenden-Blatt im Prüfstand), Aufwachabruf und Takt — der Systemtakt selbst,
# nur in Speicher/Taktgeber.swift und nur mit dem Faktor von PRUEFTAKT
# (Quelltextprobe, Z-AT6f1-03). Die Höchstzahlen sind eine Ratsche wie bei den
# Uhren (E550, E556).
# Gelesen wird je Datei wie vom Übersetzer — Zeichenketten (auch mehrzeilig, roh
# und mit Interpolation), Regex-Literale mit Rauten (#/…/#), Zeilen- und
# geschachtelte Blockkommentare —, gesucht im Code über Zeilen hinweg; ein
# Zeitgeber steht in der Zeile seines erkannten Worts (asyncAfter, .sleep, Timer
# …). Bleibt eine einzeilige Zeichenkette am Zeilenende offen oder am Dateiende
# ein Kommentar, eine Zeichenkette oder ein Literal, ist die Zerlegung unsicher —
# rot statt still. Regex-Literale ohne Rauten (/…/) liest sie als Code. Erkannt
# werden asyncAfter(, jedes .sleep( und sleep/usleep/nanosleep, .run(until:/mode:,
# Timer( und Timer.init/scheduledTimer/publish, afterDelay:, makeTimerSource,
# wait(timeout:/wallTimeout:/until:), schedule(after:), debounce/throttle/delay(for:),
# .timeout(, TimelineView(, CFRunLoopRunInMode, CFRunLoopTimerCreate und nextEvent(.
# Die Prüfstände unter App/ laufen nur mit Prüfschaltern am Paket und sind
# namentlich ausgenommen (E589), je mit der Zahl ihrer Zeitgeber als Ratsche
# (E595): Ein neuer hebt die Zahl im selben Zug, ein entfernter senkt sie; rot
# ist ein ausgenommener, der fehlt, keinen Zeitgeber hat, doppelt oder außerhalb
# von App/ steht. Außerhalb des Scans bleiben die Fristen des Netzes
# (timeoutInterval): Diese Fristen begrenzen eine Anfrage und werden je Instanz
# über zeitgrenze gesetzt (E233, E593); ebenso Abschlüsse von Animationen (E594).
# Der Schritt liest Code, nicht Bedeutung: Eine Form, die sein Muster nicht kennt,
# sieht er nicht. Ein Lesefehler und ein Ordner ohne Swift-Datei sind rot.
ZEITGEBERARTEN="AppKit Oberfläche Aufwachabruf Takt"
ZEITGEBER_HOECHSTENS="AppKit=2 Oberfläche=8 Aufwachabruf=1 Takt=2"
ZEITGEBER_PRUEFSTAENDE="App/Dauerprobe.swift=4 App/Dialogprobe.swift=25 App/Entsperrprobe.swift=11 App/Erststartprobe.swift=1
  App/Klickproben.swift=27 App/Lernendenprobe.swift=9 App/Messreihe.swift=8 App/Pruefstaende.swift=9 App/Selbstabbild.swift=10
  App/Sitzplanprobe.swift=37 App/Statusprobe.swift=1 App/Tourprobe.swift=14 App/Uebergangsprobe.swift=2 App/Widerrufprobe.swift=25"
# $1 Ordner der Quellen, $2 die Höchstzahlen (sonst ZEITGEBER_HOECHSTENS; eine
# fehlende Art hat 0), $3 die ausgenommenen Prüfstände als Datei=Zahl, relativ zum
# Ordner (sonst ZEITGEBER_PRUEFSTAENDE). Rückgabe 1 bei jeder Abweichung oder
# einem Lesefehler.
zeitgeberVon() {
  python3 - "$1" "${2-$ZEITGEBER_HOECHSTENS}" "${3-$ZEITGEBER_PRUEFSTAENDE}" "$ZEITGEBERARTEN" <<'PY'
import bisect, os, re, sys

FORMEN = re.compile(
    r"\basyncAfter[ \t]*\("
    r"|\.sleep[ \t]*\(|(?<![A-Za-z0-9_.])(?:u|nano)?sleep[ \t]*\("
    r"|\.run[ \t]*\(\s*(?:until|mode)\s*:"
    r"|\bTimer(?:\s*\.\s*init)?[ \t]*\(|\bTimer\s*\.\s*(?:scheduledTimer|publish)\b"
    r"|\bafterDelay\s*:"
    r"|\bmakeTimerSource\b"
    r"|\.wait[ \t]*\(\s*(?:wallTimeout|timeout|until)\s*:"
    r"|\bschedule[ \t]*\(\s*after\s*:"
    r"|\.(?:debounce|throttle|delay)[ \t]*\(\s*for\s*:"
    r"|\.timeout[ \t]*\(|\bTimelineView[ \t]*\(|\bCFRunLoop(?:RunInMode|TimerCreate)\b|\bnextEvent[ \t]*\(")
TEXTANFANG = re.compile(r'(#*)("""|")')
REGEXANFANG = re.compile(r"(#+)/")
MARKE = "// E561: Zeitgeber ("
GUELTIG = re.compile(r"// E561: Zeitgeber \(([^)]+)\) — ")
TAKT_ORT = "Speicher/Taktgeber.swift"

def zerlegen(text):
    """Je Zeile (Code, Kommentar), wie der Übersetzer liest: Zeichenketten geleert — auch mehrzeilig, roh (#…#) und mit
    Interpolation, deren Code wieder Code ist —, Regex-Literale mit Rauten (#/…/#) geleert, Zeilen- und geschachtelte
    Blockkommentare in den Kommentar. Dazu die Stellen, an denen die Zerlegung unsicher ist: eine einzeilige
    Zeichenkette, die am Zeilenende offen ist, und was am Dateiende offen bleibt — gültiges Swift kennt beides nicht."""
    zeilen, code, kommentar, unsicher = [], [], [], []
    rahmen = [["code", 0]]  # ["code", offene Klammern], ["text", Zahl der #, mehrzeilig] oder ["regex", Zahl der #]
    block, zeilenkommentar, i, n = 0, False, 0, len(text)
    while i < n:
        z = text[i]
        if z == "\n":
            zeilen.append(("".join(code), "".join(kommentar))); code, kommentar = [], []
            zeilenkommentar = False
            for k, r in enumerate(rahmen):
                if r[0] == "text" and not r[2]:
                    unsicher.append((len(zeilen), "eine einzeilige Zeichenkette ist am Zeilenende offen"))
                    del rahmen[k:]; break
            i += 1; continue
        if zeilenkommentar:
            kommentar.append(z); i += 1; continue
        if block:
            for zeichen, schritt in (("/*", 1), ("*/", -1)):
                if text.startswith(zeichen, i):
                    block += schritt; kommentar.append(zeichen); i += 2; break
            else:
                kommentar.append(z); i += 1
            continue
        oben = rahmen[-1]
        if oben[0] == "code":
            if text.startswith("//", i):
                zeilenkommentar = True; kommentar.append("//"); i += 2; continue
            if text.startswith("/*", i):
                block = 1; kommentar.append("/*"); i += 2; continue
            m = REGEXANFANG.match(text, i)
            if m:
                rahmen.append(["regex", len(m.group(1))]); code.append(" " * len(m.group(0))); i = m.end(); continue
            m = TEXTANFANG.match(text, i)
            if m:
                rahmen.append(["text", len(m.group(1)), m.group(2) == '"""'])
                code.append(" " * len(m.group(0))); i = m.end(); continue
            if z == "(":
                oben[1] += 1
            elif z == ")":
                if len(rahmen) > 1 and oben[1] == 0:
                    rahmen.pop(); code.append(" "); i += 1; continue
                oben[1] -= 1
            code.append(z); i += 1; continue
        if oben[0] == "regex":
            ende = "/" + "#" * oben[1]
            if text.startswith(ende, i):
                rahmen.pop(); code.append(" " * len(ende)); i += len(ende); continue
            if z == "\\" and i + 1 < n and text[i + 1] != "\n":
                code.append("  "); i += 2; continue
            code.append(" "); i += 1; continue
        _, rauten, mehrzeilig = oben
        ende = ('"""' if mehrzeilig else '"') + "#" * rauten
        if text.startswith(ende, i):
            rahmen.pop(); code.append(" " * len(ende)); i += len(ende); continue
        flucht = "\\" + "#" * rauten
        if text.startswith(flucht, i):
            i += len(flucht); code.append(" " * len(flucht))
            if i < n and text[i] == "(":
                rahmen.append(["code", 0]); code.append(" "); i += 1
            elif i < n and text[i] != "\n":
                code.append(" "); i += 1
            continue
        code.append(" "); i += 1
    zeilen.append(("".join(code), "".join(kommentar)))
    offen = [r[0] for r in rahmen[1:]]
    if block or offen:
        was = "Blockkommentar" if block else {"text": "Zeichenkette", "regex": "Regex-Literal", "code": "Interpolation"}[offen[-1]]
        unsicher.append((len(zeilen), f"am Dateiende offen: {was}"))
    return zeilen, unsicher

def mit_form(zeilen):
    """Die Zeilen, in denen ein Zeitgeber beginnt — gesucht im Code über Zeilen hinweg."""
    strom = "\n".join(c for c, _ in zeilen)
    anfaenge = [0] + [k + 1 for k, z in enumerate(strom) if z == "\n"]
    return {bisect.bisect_right(anfaenge, m.start()) for m in FORMEN.finditer(strom)}

def pruefen(ordner, hoechstens, ausnahmen, arten):
    arten = arten.split()
    if not os.path.isdir(ordner):
        print(f"✗ Zeitgeber: {ordner} ist kein Ordner — gelesen wurde nichts"); return 1
    fehler, grenze = 0, {}
    for paar in hoechstens.split():
        art, _, zahl = paar.partition("=")
        if art not in arten:
            print(f"✗ Unbekannter Schlüssel „{art}“ in den Höchstzahlen — bekannt: {' '.join(arten)}"); fehler = 1
        if not zahl.isdigit():
            print(f"✗ Höchstzahl für „{art}“ unlesbar: „{zahl}“"); return 1
        grenze[art] = int(zahl)
    ausgenommen = {}  # Datei → [verzeichnet, gefunden]
    for eintrag in ausnahmen.split():
        datei, gleich, zahl = eintrag.partition("=")
        if not gleich or not zahl.isdigit():
            print(f"✗ Prüfstand ohne lesbare Zahl: „{eintrag}“ — verlangt: Datei=Zahl der Zeitgeber (E595)"); fehler = 1
            continue
        if not datei.startswith("App/"):
            print(f"✗ Prüfstand außerhalb von App/: {datei} — ausgenommen sind nur Prüfstände (E589)"); fehler = 1
            continue
        if datei in ausgenommen:
            print(f"✗ Prüfstand doppelt verzeichnet: {datei} — je Datei ein Eintrag (E595)"); fehler = 1
            continue
        ausgenommen[datei] = [int(zahl), 0]
    # Ohne onerror übergeht os.walk einen Ordner, der sich nicht lesen lässt, still (R75-02).
    lesefehler, dateien = [], []
    for wurzel, unter, namen in os.walk(ordner, onerror=lesefehler.append):
        unter.sort()
        dateien += [os.path.relpath(os.path.join(wurzel, n), ordner) for n in sorted(namen) if n.endswith(".swift")]
    for f in lesefehler:
        print(f"✗ Zeitgeber: {os.path.relpath(f.filename, ordner)} nicht lesbar ({f.strerror}) — gelesen wurde nicht alles")
    if lesefehler:
        return 1
    if not dateien:
        print(f"✗ Zeitgeber: keine Swift-Datei in {ordner} — gelesen wurde nichts"); return 1
    zahl, orte = {}, {}
    for rel in dateien:
        try:
            text = open(os.path.join(ordner, rel), encoding="utf-8").read()
        except (OSError, UnicodeDecodeError) as e:
            print(f"✗ Zeitgeber: {rel} nicht lesbar ({e}) — gelesen wurde nicht alles"); return 1
        zeilen, unsicher = zerlegen(text)
        for nr, grund in unsicher:
            print(f"✗ Zerlegung unsicher in {rel}:{nr} — {grund}; ein Zeitgeber dahinter bliebe ungesehen"); fehler = 1
        formen = mit_form(zeilen)
        if rel in ausgenommen:
            ausgenommen[rel][1] = len(formen)
            continue
        for nr, (code, kommentar) in enumerate(zeilen, 1):
            ort = f"{rel}:{nr}"
            if nr not in formen:
                if code.strip() and "E561: Zeitgeber" in kommentar:
                    print(f"✗ Marke ohne Zeitgeber in {ort} — die Marke steht in der Zeile, in der der Zeitgeber beginnt"); fehler = 1
                continue
            p = kommentar.find(MARKE)
            gueltig = GUELTIG.match(kommentar, p) if p >= 0 else None
            if not gueltig:
                w = ("Marke ohne Art" if "// E561: Zeitgeber — " in kommentar
                     else "Marke unlesbar" if "E561: Zeitgeber" in kommentar else "ungenannt")
                print(f"✗ Zeitgeber außerhalb des Taktgebers in {ort} ({w}) — über den Takt des Speichers gehen"
                      " oder benennen: // E561: Zeitgeber (<Art>) — <Grund>"); fehler = 1
                continue
            art = gueltig.group(1)
            if art == "Takt" and rel != TAKT_ORT:
                print(f"✗ Zeitgeber der Art Takt außerhalb von {TAKT_ORT}: {ort} — der Systemtakt steht nur dort"); fehler = 1
            elif art == "Takt" and not re.search(r"\*\s*Self\.faktor\b", code):
                print(f"✗ Zeitgeber der Art Takt ohne den Faktor von PRUEFTAKT in {ort} — die Frist mal Self.faktor (E551)"); fehler = 1
            zahl[art] = zahl.get(art, 0) + 1
            orte.setdefault(art, []).append(ort)
    for datei, (verzeichnet, gefunden) in ausgenommen.items():
        if datei not in dateien:
            print(f"✗ Ausgenommener Prüfstand fehlt: {datei} — aus ZEITGEBER_PRUEFSTAENDE nehmen"); fehler = 1
        elif gefunden == 0:
            print(f"✗ Ausgenommener Prüfstand ohne Zeitgeber: {datei} — aus ZEITGEBER_PRUEFSTAENDE nehmen"); fehler = 1
        elif gefunden > verzeichnet:
            print(f"✗ Zeitgeber im Prüfstand {datei}: {gefunden}, verzeichnet {verzeichnet}"
                  f" — im selben Zug in ZEITGEBER_PRUEFSTAENDE auf {gefunden} heben (E595)"); fehler = 1
        elif gefunden < verzeichnet:
            print(f"✗ Ratsche nicht gesenkt: Prüfstand {datei} hat {gefunden} Zeitgeber, verzeichnet {verzeichnet}"
                  f" — in ZEITGEBER_PRUEFSTAENDE auf {gefunden} senken (E595)"); fehler = 1
    for art in zahl:
        if art not in arten:
            print(f"✗ Zeitgeber mit unbekannter Art „{art}“ ({zahl[art]}×): {', '.join(orte[art])}"
                  f" — bekannt: {' '.join(arten)}"); fehler = 1
    liste = []
    for art in arten:
        z, g = zahl.get(art, 0), grenze.get(art, 0)
        if z > g:
            print(f"✗ Zeitgeber der Art {art}: {z} benannt, höchstens {g} (Ratsche, E550): {', '.join(orte[art])}"); fehler = 1
        elif z < g:
            print(f"✗ Ratsche nicht gesenkt: Art {art} hat {z} Zeitgeber, Höchstzahl {g}"
                  f" — in ZEITGEBER_HOECHSTENS auf {z} senken (E556)"); fehler = 1
        if z or g:
            liste.append(f"{art} {z}/{g}")
    if fehler:
        return 1
    benannt = f"{sum(zahl.values())}" + (f" ({', '.join(liste)})" if liste else "")
    pruefstaende = sum(g for _, g in ausgenommen.values())
    print(f"Zeitgeber stimmig — {len(dateien)} Dateien gelesen, ausgenommene Prüfstände: {len(ausgenommen)}"
          f" (Zeitgeber: {pruefstaende}), benannt: {benannt}, ungenannt: 0 (E561)")
    return 0

sys.exit(pruefen(*sys.argv[1:5]))
PY
}

# Der Schritt: zuerst die Gegenprobe an Prüfordnern — jede erkannte Form, je in
# einer eigenen Datei (36 Stellen, eine in einem Unterordner, sechs über zwei
# Zeilen), was bleiben darf (eine benannte Stelle, Kommentare, Zeichenketten und
# Regex-Literale aller Arten, ähnliche Namen), Zeitgeber hinter dem, was die
# Zerlegung täuschen könnte („/*“ in Zeichenkette und Kommentar, Interpolation,
# \", \\, Raw-Strings, Regex-Literal, mehrzeilige Zeichenkette, geschachtelter
# Kommentar), was sie unsicher macht (am Zeilen- und am Dateiende offen); dazu,
# was nicht gelesen wurde (eine unlesbare oder falsch kodierte Datei, ein
# unlesbarer Unterordner, ein Ordner ohne Swift-Datei, kein Ordner), die Marken
# und Arten, die Ratschen, der Takt außerhalb seines Orts oder ohne Faktor und die
# ausgenommenen Prüfstände (Zahl, fehlt, ohne Zeitgeber, doppelt, außerhalb von
# App/) —, dann die Quellen der Fassung. Eine Schlusszeile mit „Abweichung“ trägt
# einen Befund in den Vermerk.
zeitgeber() {
  local probe gegen ergebnis=0
  probe="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unterrichtsplanung-zeitgeber.XXXXXX")" || return 1
  mkdir -p "$probe/formen/Unter" "$probe/erlaubt" "$probe/zerlegung" "$probe/mehrzeilig-benannt" "$probe/gesperrt" \
    "$probe/gesperrt-ordner/Unter" "$probe/kodierung" "$probe/leer" "$probe/alt" "$probe/leer-art" "$probe/unbekannt" \
    "$probe/leerzeichen" "$probe/ratsche" "$probe/ungesenkt" "$probe/genau" "$probe/doppelt" "$probe/fremd" \
    "$probe/takt/Speicher" "$probe/takt/Dienste" "$probe/takt-ohne-faktor/Speicher" "$probe/uebrig" "$probe/pruefstand/App" \
    "$probe/pruefstand-ohne/App" "$probe/pruefstand-aussen/Dienste" "$probe/unsicher-zeile" "$probe/unsicher-ende" \
    "$probe/takt-geteilt/Speicher"
  # Jede Form in einer eigenen Datei, Ort = Datei:Zeile, in der sie beginnt.
  printf '%s\n' '        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { fertig = true }' > "$probe/formen/AsyncAfter.swift"
  printf '%s\n' '        try await Task.sleep(for: .milliseconds(50))' > "$probe/formen/TaskSleep.swift"
  printf '%s\n' '        try await Task.sleep(until: .now + .seconds(1))' > "$probe/formen/TaskSleepUntil.swift"
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)' > "$probe/formen/ThreadSleep.swift"
  printf '%s\n' '        try await ContinuousClock().sleep(for: .milliseconds(5))' > "$probe/formen/ClockSleep.swift"
  printf '%s\n' '        sleep(1)' > "$probe/formen/Sleep.swift"
  printf '%s\n' '        usleep(1000)' > "$probe/formen/Usleep.swift"
  printf '%s\n' '        nanosleep(&zeit, nil)' > "$probe/formen/Nanosleep.swift"
  printf '%s\n' '        RunLoop.current.run(until: Date().addingTimeInterval(0.35))' > "$probe/formen/RunLoop.swift"
  printf '%s\n' '        let t = Timer(timeInterval: 1, repeats: false) { _ in }' > "$probe/formen/Timer.swift"
  printf '%s\n' '        let t = Timer.init(timeInterval: 1, repeats: false) { _ in }' > "$probe/formen/TimerInit.swift"
  printf '%s\n' '        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in }' > "$probe/formen/TimerPlan.swift"
  printf '%s\n' '        let takt = Timer.publish(every: 1, on: .main, in: .common)' > "$probe/formen/TimerPublish.swift"
  printf '%s\n' '        perform(#selector(weiter), with: nil, afterDelay: 0.5)' > "$probe/formen/AfterDelay.swift"
  printf '%s\n' '        let quelle = DispatchSource.makeTimerSource(queue: .main)' > "$probe/formen/TimerSource.swift"
  printf '%s\n' '        _ = signal.wait(timeout: .now() + 1)' > "$probe/formen/WaitTimeout.swift"
  printf '%s\n' '        _ = signal.wait(wallTimeout: .now() + 1)' > "$probe/formen/WaitWall.swift"
  printf '%s\n' '        _ = bedingung.wait(until: Date() + 1)' > "$probe/formen/WaitUntil.swift"
  printf '%s\n' '        DispatchQueue.main.schedule(after: .init(.now() + 1)) { }' > "$probe/formen/ScheduleAfter.swift"
  printf '%s\n' '        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)' > "$probe/formen/Debounce.swift"
  printf '%s\n' '        .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)' > "$probe/formen/Throttle.swift"
  printf '%s\n' '        .delay(for: .seconds(1), scheduler: RunLoop.main)' > "$probe/formen/Delay.swift"
  printf '%s\n' '        .timeout(.seconds(1), scheduler: RunLoop.main)' > "$probe/formen/CombineTimeout.swift"
  printf '%s\n' '        TimelineView(.periodic(from: .now, by: 1)) { _ in }' > "$probe/formen/TimelineView.swift"
  printf '%s\n' '        CFRunLoopRunInMode(.defaultMode, 1, false)' > "$probe/formen/CFRunLoopRun.swift"
  printf '%s\n' '        let t = CFRunLoopTimerCreate(nil, 0, 1, 0, 0, nil, nil)' > "$probe/formen/CFTimer.swift"
  printf '%s\n' '        _ = NSApp.nextEvent(matching: .any, until: Date() + 1, inMode: .default, dequeue: true)' \
    > "$probe/formen/NextEvent.swift"
  printf '%s\n' '        schleife.run(until: Date() + 1)' > "$probe/formen/RunLoopVariable.swift"
  printf '%s\n' '        RunLoop.main.run(mode: .default, before: Date() + 1)' > "$probe/formen/RunLoopMode.swift"
  printf '%s\n' '        try await Task.sleep(for: .seconds(1))' > "$probe/formen/Unter/Tief.swift"
  printf '%s\n' '        try await Task' '            .sleep(for: .seconds(1))' > "$probe/formen/MehrzeiligTask.swift"
  printf '%s\n' '        let takt = Timer' '            .publish(every: 1, on: .main, in: .common)' > "$probe/formen/MehrzeiligPublish.swift"
  printf '%s\n' '        RunLoop.current' '            .run(until: Date())' > "$probe/formen/MehrzeiligRunLoop.swift"
  printf '%s\n' '        _ = signal.wait(' '            timeout: .now() + 1)' > "$probe/formen/MehrzeiligWait.swift"
  printf '%s\n' '        DispatchQueue.main.schedule(' '            after: .init(.now() + 1)) { }' > "$probe/formen/MehrzeiligSchedule.swift"
  printf '%s\n' '        .debounce(' '            for: .milliseconds(300), scheduler: RunLoop.main)' > "$probe/formen/MehrzeiligDebounce.swift"
  # Was bleiben darf: zusammen grün, mit einer benannten Stelle.
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber (AppKit) — Blatt abwarten' \
    > "$probe/erlaubt/Benannt.swift"
  printf '%s\n' '        // Früher stand hier Task.sleep(for: .seconds(1)).' > "$probe/erlaubt/Kommentar.swift"
  printf '%s\n' '        let a = 1  // statt DispatchQueue.main.asyncAfter(deadline: .now() + 1)' > "$probe/erlaubt/Nachsatz.swift"
  printf '%s\n' '        let s = "Task.sleep(for: .seconds(1)) // kein Kommentar"' > "$probe/erlaubt/Text.swift"
  printf '%s\n' '        let s = "a\"Task.sleep(for: .seconds(1))\"b"' > "$probe/erlaubt/Flucht.swift"
  printf '%s\n' '        let s = "\(zahl) Sekunden: Task.sleep(for: .seconds(1))"' > "$probe/erlaubt/Interpolation.swift"
  printf '%s\n' '        let r = #"ein "Zitat" mit Task.sleep(for: .seconds(1))"#' > "$probe/erlaubt/Roh.swift"
  printf '%s\n' '        let t = """' '            Task.sleep(for: .seconds(1))' '            """' > "$probe/erlaubt/MehrzeiligText.swift"
  printf '%s\n' '        /* Task.sleep(for: .seconds(1)) */ let b = 2' '        /*' '        Thread.sleep(forTimeInterval: 1)' \
    '        */' > "$probe/erlaubt/Block.swift"
  printf '%s\n' '        /* außen /* innen */ try await Task.sleep(for: .seconds(1)) */ let c = 3' > "$probe/erlaubt/Verschachtelt.swift"
  printf '%s\n' '        let c = schlafenlegen(3) + deepsleep(3) + TimerLabel(1) + zeitTimer(2) + warten.wait()' \
    > "$probe/erlaubt/Namen.swift"
  printf '%s\n' '        let r = #"a "b"# + #" Task.sleep(for: .seconds(1)) "#' > "$probe/erlaubt/RohUngerade.swift"
  printf '%s\n' '        let m = #/a"b(Task.sleep(for: .seconds(1)))/#' > "$probe/erlaubt/Regex.swift"
  # Zeitgeber hinter dem, was die Zerlegung täuschen könnte — je an seinem Ort gemeldet.
  printf '%s\n' '        let m = "image/*"' '        try await Task.sleep(for: .seconds(1))' '        let x = 1 /* Ende */' \
    > "$probe/zerlegung/SternInText.swift"
  printf '%s\n' '        // Pruefungen/*.swift' '        try await Task.sleep(for: .seconds(1))' '        let x = 1 /* Ende */' \
    > "$probe/zerlegung/SternImKommentar.swift"
  printf '%s\n' '        let u = "\(a ? "https://x" : "")"; try await Task.sleep(for: .seconds(1))' \
    > "$probe/zerlegung/InterpolationDanach.swift"
  printf '%s\n' '        let s = "a\"b"; try await Task.sleep(for: .seconds(1))' > "$probe/zerlegung/FluchtDanach.swift"
  printf '%s\n' '        let r = #"ein "Zitat""#; try await Task.sleep(for: .seconds(1))' > "$probe/zerlegung/RohDanach.swift"
  printf '%s\n' '        let t = """' '            Text' '            """' '        try await Task.sleep(for: .seconds(1))' \
    > "$probe/zerlegung/NachMehrzeilig.swift"
  printf '%s\n' '        /* a /* b */ c */' '        try await Task.sleep(for: .seconds(1))' > "$probe/zerlegung/NachVerschachtelt.swift"
  printf '%s\n' '        let r = #"ein " Zeichen"#; try await Task.sleep(for: .seconds(1))' > "$probe/zerlegung/RohEinzeln.swift"
  printf '%s\n' '        let s = "\\"; try await Task.sleep(for: .seconds(1))' > "$probe/zerlegung/FluchtRueck.swift"
  printf '%s\n' '        let n = #/https?://x/#; try await Task.sleep(for: .seconds(1))' > "$probe/zerlegung/RegexDanach.swift"
  printf '%s\n' '        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {  // E561: Zeitgeber (Oberfläche) — erst, wenn es steht' \
    '            weiter()' '        }' > "$probe/mehrzeilig-benannt/Blatt.swift"
  printf '%s\n' '        let x = 1' > "$probe/gesperrt/Offen.swift"
  printf '%s\n' '        let y = 2' > "$probe/gesperrt/Gesperrt.swift"
  /bin/chmod 000 "$probe/gesperrt/Gesperrt.swift"
  printf '%s\n' '        let x = 1' > "$probe/gesperrt-ordner/Offen.swift"
  printf '%s\n' '        try await Task.sleep(for: .seconds(1))' > "$probe/gesperrt-ordner/Unter/Tief.swift"
  /bin/chmod 000 "$probe/gesperrt-ordner/Unter"
  printf '\xff\xfe let z = 1\n' > "$probe/kodierung/Kaputt.swift"
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber — ohne Art' > "$probe/alt/Alt.swift"
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber () — leer' > "$probe/leer-art/Leer.swift"
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber (Laune) — ohne Grund' \
    > "$probe/unbekannt/Laune.swift"
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber ( AppKit ) — mit Leerzeichen' \
    > "$probe/leerzeichen/Raum.swift"
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber (AppKit) — eins' \
    '        try? await Task.sleep(for: .milliseconds(50))  // E561: Zeitgeber (AppKit) — zwei' > "$probe/ratsche/Zwei.swift"
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber (AppKit) — eins' > "$probe/ungesenkt/Eins.swift"
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber (AppKit) — eins' > "$probe/genau/Eins.swift"
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber (AppKit) — eins // E561: Zeitgeber (AppKit) — noch einmal' \
    > "$probe/doppelt/Doppelt.swift"
  printf '%s\n' '        try? await Task.sleep(for: .milliseconds(40))  // E561: Zeitgeber (AppKit) — eins' > "$probe/fremd/Eins.swift"
  printf '%s\n' '        try await Task.sleep(for: dauer * Self.faktor)  // E561: Zeitgeber (Takt) — der Systemtakt' \
    > "$probe/takt/Speicher/Taktgeber.swift"
  printf '%s\n' '        try await Task.sleep(for: dauer * Self.faktor)  // E561: Zeitgeber (Takt) — ein zweiter Takt' \
    > "$probe/takt/Dienste/Uhr.swift"
  printf '%s\n' '        try await Task.sleep(for: dauer)  // E561: Zeitgeber (Takt) — ohne Faktor' \
    > "$probe/takt-ohne-faktor/Speicher/Taktgeber.swift"
  printf '%s\n' '        let a = 1  // E561: Zeitgeber (AppKit) — übrig geblieben' > "$probe/uebrig/Uebrig.swift"
  printf '%s\n' '        try await Task.sleep(for: .seconds(1))' '        Thread.sleep(forTimeInterval: 1)' \
    > "$probe/pruefstand/App/Probe.swift"
  printf '%s\n' '        let a = 1' > "$probe/pruefstand-ohne/App/Probe.swift"
  printf '%s\n' '        try await Task.sleep(for: .seconds(1))' > "$probe/pruefstand-aussen/Dienste/Probe.swift"
  printf '%s\n' '        let m = /a"b/' '        try await Task.sleep(for: .seconds(1))' > "$probe/unsicher-zeile/Offen.swift"
  printf '%s\n' '        let x = 1 /* nie geschlossen' '        try await Task.sleep(for: .seconds(1))' \
    > "$probe/unsicher-ende/OffenAmEnde.swift"
  printf '%s\n' '        try await Task.sleep(for: dauer / Self.faktor)  // E561: Zeitgeber (Takt) — geteilt' \
    > "$probe/takt-geteilt/Speicher/Taktgeber.swift"

  # $1 Fall, $2 verlangte Meldung, $3 0 = grün verlangt, 1 = rot verlangt, danach die Argumente für zeitgeberVon.
  gegenprobe() {
    local fall="$1" meldung="$2" rot="$3" aus rc
    shift 3
    aus="$(zeitgeberVon "$@" 2>&1)"; rc=$?
    if { [ "$rot" = 1 ] && [ "$rc" = 0 ]; } || { [ "$rot" = 0 ] && [ "$rc" != 0 ]; } || ! grep -qF -- "$meldung" <<<"$aus"; then
      echo "Gegenprobe der Zeitgeber: $fall (Rückgabe $rc) —"; printf '%s\n' "$aus" | sed 's/^/  /'
      ergebnis=1
    fi
  }
  # $1 Fall, $2 Ordner, $3 die verlangten Orte (Datei:Zeile, ungenannt) — genau diese, keine weiteren.
  genauDiese() {
    local fall="$1" aus ort fehlt="" zahl=0
    aus="$(zeitgeberVon "$2" "" "" 2>&1)"
    for ort in $3; do
      zahl=$((zahl + 1))
      grep -qF "in $ort (ungenannt)" <<<"$aus" || fehlt="$fehlt $ort"
    done
    if [ -n "$fehlt" ] || [ "$(grep -c '^✗' <<<"$aus")" != "$zahl" ]; then
      echo "Gegenprobe der Zeitgeber: $fall (verlangt $zahl Stellen, fehlt:${fehlt:- nichts}) —"; printf '%s\n' "$aus" | sed 's/^/  /'
      ergebnis=1
    fi
  }
  genauDiese "Die Formen greifen nicht wie verlangt" "$probe/formen" "AsyncAfter.swift:1 TaskSleep.swift:1 TaskSleepUntil.swift:1
    ThreadSleep.swift:1 ClockSleep.swift:1 Sleep.swift:1 Usleep.swift:1 Nanosleep.swift:1 RunLoop.swift:1 Timer.swift:1
    TimerInit.swift:1 TimerPlan.swift:1 TimerPublish.swift:1 AfterDelay.swift:1 TimerSource.swift:1 WaitTimeout.swift:1
    WaitWall.swift:1 WaitUntil.swift:1 ScheduleAfter.swift:1 Debounce.swift:1 Throttle.swift:1 Delay.swift:1
    CombineTimeout.swift:1 TimelineView.swift:1 CFRunLoopRun.swift:1 CFTimer.swift:1 NextEvent.swift:1 Unter/Tief.swift:1
    RunLoopVariable.swift:1 RunLoopMode.swift:1     MehrzeiligTask.swift:2 MehrzeiligPublish.swift:1 MehrzeiligRunLoop.swift:2 MehrzeiligWait.swift:1
    MehrzeiligSchedule.swift:1 MehrzeiligDebounce.swift:1"
  gegenprobe "Was bleiben darf, wurde gemeldet" "benannt: 1 (AppKit 1/1)" 0 "$probe/erlaubt" "AppKit=1" ""
  genauDiese "Die Zerlegung verdeckt einen Zeitgeber oder meldet zu viel" "$probe/zerlegung" "SternInText.swift:2
    SternImKommentar.swift:2 InterpolationDanach.swift:1 FluchtDanach.swift:1 RohDanach.swift:1 NachMehrzeilig.swift:4
    NachVerschachtelt.swift:2 RohEinzeln.swift:1 FluchtRueck.swift:1 RegexDanach.swift:1"
  gegenprobe "Eine Marke in der ersten Zeile eines mehrzeiligen Aufrufs zählte nicht" "benannt: 1 (Oberfläche 1/1)" 0 \
    "$probe/mehrzeilig-benannt" "Oberfläche=1" ""
  gegenprobe "Eine unlesbare Datei galt als gelesen" "Gesperrt.swift nicht lesbar" 1 "$probe/gesperrt" "" ""
  gegenprobe "Ein unlesbarer Unterordner galt als gelesen" "Unter nicht lesbar" 1 "$probe/gesperrt-ordner" "" ""
  gegenprobe "Eine falsch kodierte Datei galt als gelesen" "Kaputt.swift nicht lesbar" 1 "$probe/kodierung" "" ""
  gegenprobe "Ein Ordner ohne Swift-Datei galt als stimmig" "keine Swift-Datei" 1 "$probe/leer" "" ""
  gegenprobe "Ein fehlender Ordner galt als gelesen" "ist kein Ordner" 1 "$probe/gibt-es-nicht" "" ""
  gegenprobe "Eine unlesbare Höchstzahl blieb still" "✗ Höchstzahl für „AppKit“ unlesbar" 1 "$probe/genau" "AppKit=zwei" ""
  gegenprobe "Eine Marke ohne Art galt als benannt" "in Alt.swift:1 (Marke ohne Art)" 1 "$probe/alt" "AppKit=1" ""
  gegenprobe "Eine leere Art „()“ galt als benannt" "in Leer.swift:1 (Marke unlesbar)" 1 "$probe/leer-art" "" ""
  gegenprobe "Eine unbekannte Art galt als zulässig" "✗ Zeitgeber mit unbekannter Art „Laune“ (1×)" 1 "$probe/unbekannt" "" ""
  gegenprobe "„( AppKit )“ galt als zulässige Art" "✗ Zeitgeber mit unbekannter Art „ AppKit “" 1 "$probe/leerzeichen" "" ""
  gegenprobe "Eine Art über ihrer Grenze galt als stimmig" "✗ Zeitgeber der Art AppKit: 2 benannt, höchstens 1 (Ratsche, E550)" 1 \
    "$probe/ratsche" "AppKit=1" ""
  gegenprobe "Eine Art unter ihrer Grenze galt als stimmig (E556)" "✗ Ratsche nicht gesenkt: Art AppKit hat 1 Zeitgeber, Höchstzahl 3" 1 \
    "$probe/ungesenkt" "AppKit=3" ""
  gegenprobe "Eine getroffene Grenze steht nicht als „AppKit 1/1“ in der Schlusszeile" "benannt: 1 (AppKit 1/1)" 0 \
    "$probe/genau" "AppKit=1" ""
  gegenprobe "Zwei Marken in einer Zeile zählten nicht als ein Zeitgeber" "benannt: 1 (AppKit 1/1)" 0 "$probe/doppelt" "AppKit=1" ""
  gegenprobe "Ein unbekannter Schlüssel in den Höchstzahlen blieb still" "✗ Unbekannter Schlüssel „Appkit“ in den Höchstzahlen" 1 \
    "$probe/fremd" "AppKit=1 Appkit=2" ""
  gegenprobe "Der Takt außerhalb des Taktgebers blieb still" \
    "✗ Zeitgeber der Art Takt außerhalb von Speicher/Taktgeber.swift: Dienste/Uhr.swift:1" 1 "$probe/takt" "Takt=2" ""
  gegen="$(zeitgeberVon "$probe/takt" "Takt=2" "" 2>&1)"
  if grep -qE 'außerhalb von Speicher/Taktgeber.swift: Speicher/|ohne den Faktor' <<<"$gegen"; then
    echo "Gegenprobe der Zeitgeber: Der Takt im Taktgeber galt als außerhalb oder ohne Faktor —"; printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  gegenprobe "Der Takt ohne Faktor blieb still" \
    "✗ Zeitgeber der Art Takt ohne den Faktor von PRUEFTAKT in Speicher/Taktgeber.swift:1" 1 "$probe/takt-ohne-faktor" "Takt=1" ""
  gegenprobe "Eine Marke ohne Zeitgeber blieb still" "✗ Marke ohne Zeitgeber in Uebrig.swift:1" 1 "$probe/uebrig" "" ""
  gegenprobe "Ein verzeichneter Prüfstand wurde gemeldet" "ausgenommene Prüfstände: 1 (Zeitgeber: 2)" 0 \
    "$probe/pruefstand" "" "App/Probe.swift=2"
  gegenprobe "Ein neuer Zeitgeber im Prüfstand blieb still (E595)" "✗ Zeitgeber im Prüfstand App/Probe.swift: 2, verzeichnet 1" 1 \
    "$probe/pruefstand" "" "App/Probe.swift=1"
  gegenprobe "Ein Prüfstand unter seiner Zahl galt als stimmig (E595)" \
    "✗ Ratsche nicht gesenkt: Prüfstand App/Probe.swift hat 2 Zeitgeber, verzeichnet 3" 1 "$probe/pruefstand" "" "App/Probe.swift=3"
  gegenprobe "Ein Prüfstand ohne Zahl galt als verzeichnet" "✗ Prüfstand ohne lesbare Zahl: „App/Probe.swift“" 1 \
    "$probe/pruefstand" "" "App/Probe.swift"
  gegenprobe "Ein fehlender ausgenommener Prüfstand blieb still" "✗ Ausgenommener Prüfstand fehlt: App/Weg.swift" 1 \
    "$probe/pruefstand" "" "App/Probe.swift=2 App/Weg.swift=1"
  gegenprobe "Ein ausgenommener Prüfstand ohne Zeitgeber blieb still" "✗ Ausgenommener Prüfstand ohne Zeitgeber: App/Probe.swift" 1 \
    "$probe/pruefstand-ohne" "" "App/Probe.swift=1"
  gegenprobe "Ein doppelt verzeichneter Prüfstand blieb still" "✗ Prüfstand doppelt verzeichnet: App/Probe.swift" 1 \
    "$probe/pruefstand" "" "App/Probe.swift=2 App/Probe.swift=2"
  gegenprobe "Ein Prüfstand außerhalb von App/ wurde ausgenommen" "✗ Prüfstand außerhalb von App/: Dienste/Probe.swift" 1 \
    "$probe/pruefstand-aussen" "" "Dienste/Probe.swift=1"
  gegenprobe "Eine am Zeilenende offene Zeichenkette blieb still" "✗ Zerlegung unsicher in Offen.swift:1" 1 \
    "$probe/unsicher-zeile" "" ""
  gegenprobe "Ein am Dateiende offener Kommentar blieb still" "am Dateiende offen: Blockkommentar" 1 "$probe/unsicher-ende" "" ""
  gegenprobe "Ein geteilter statt multiplizierter Faktor galt als stimmig" \
    "✗ Zeitgeber der Art Takt ohne den Faktor von PRUEFTAKT in Speicher/Taktgeber.swift:1" 1 "$probe/takt-geteilt" "Takt=1" ""
  /bin/chmod 600 "$probe/gesperrt/Gesperrt.swift"
  /bin/chmod 700 "$probe/gesperrt-ordner/Unter"
  rm -rf "$probe"
  zeitgeberVon "$HIER/Quellen/Unterrichtsplanung" || ergebnis=1
  [ "$ergebnis" = 0 ] || echo "✗ Zeitgeber: Abweichung — die Gründe stehen im Protokoll des Schritts"
  return "$ergebnis"
}

# Name der Web App (E219, v75): Was jemand sieht, nennt die Web App „Web App“ —
# nie „Ansicht“, „Ansichtsfassung“, „iPad-Ansicht“ oder „Ansicht fürs iPad“ —,
# und die App nennt das iPad nicht: Die Web App läuft auch auf anderen Geräten.
# Gelesen werden die Zeichenketten der App (Quellen/, ohne Kommentare), in der
# Web App der sichtbare Text, die Attribute, die ein Tooltip zeigt oder VoiceOver
# vorliest, der Titel und die Zeichenketten der Skripte (dort
# darf das iPad als Gerät vorkommen), im Manifest Name, Kurzname und
# Beschreibung, dazu der Beipackzettel des Abbilds in bauen.sh. Dateinamen wie
# unterrichtsplanung-ansicht.html sind klein geschrieben und fallen nicht
# darunter. Der Schritt liest Zeichenketten, nicht Bedeutung.
# $1 Quellen der App, $2 Web App, $3 bauen.sh. Rückgabe 1 bei einem Fund oder
# wenn nicht alles gelesen wurde — auch ein Ordner, der sich nicht lesen lässt.
webappnameVon() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, os, re, sys

MUSTER = re.compile(r"(?<![A-Za-zÄÖÜäöüß])Ansicht")
# In der App nennt kein Text das iPad: Die Web App läuft auch auf anderen Geräten.
MUSTER_APP = re.compile(r"(?<![A-Za-zÄÖÜäöüß])Ansicht|iPad")

def swift_zeichenketten(text):
    """(Zeile, Zeichenkette) — Zeilenkommentare und Blockkommentare heraus."""
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    ergebnis = []
    mehr = None  # Beginn eines mehrzeiligen Literals
    for nr, zeile in enumerate(text.splitlines(), 1):
        if mehr is not None:
            if '"""' in zeile:
                ergebnis.append((mehr[0], mehr[1] + "\n" + zeile.split('"""')[0])); mehr = None
            else:
                mehr = (mehr[0], mehr[1] + "\n" + zeile)
            continue
        roh = zeile.strip()
        if roh.startswith("//"):
            continue
        if '"""' in zeile:
            mehr = (nr, zeile.split('"""', 1)[1]); continue
        code = re.split(r'(?<!:)//(?=[^"]*$)', zeile)[0]
        for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', code):
            ergebnis.append((nr, m.group(1)))
    return ergebnis

def html_texte(text):
    ergebnis = []
    def zeile_von(pos): return text.count("\n", 0, pos) + 1
    for m in re.finditer(r"<title>(.*?)</title>", text, flags=re.S):
        ergebnis.append((zeile_von(m.start()), m.group(1)))
    # HTML-Text außerhalb von Kommentar, Skript und Stil
    maske = re.sub(r"<!--.*?-->|<script.*?</script>|<style.*?</style>",
                   lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    for m in re.finditer(r">([^<>]+)<", maske):
        if m.group(1).strip():
            ergebnis.append((zeile_von(m.start()), m.group(1).strip()))
    # Was ein Tooltip zeigt oder VoiceOver vorliest, sieht auch jemand (B60, v75).
    for m in re.finditer(r'\b(?:aria-label|aria-description|title|alt|placeholder)\s*=\s*"([^"]*)"', maske):
        ergebnis.append((zeile_von(m.start()), m.group(1)))
    # Zeichenketten in den Skripten, ohne Kommentare
    for s in re.finditer(r"<script[^>]*>(.*?)</script>", text, flags=re.S):
        inhalt = s.group(1)
        basis = s.start(1)
        inhalt_ohne = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), inhalt, flags=re.S)
        zeilen = inhalt_ohne.split("\n")
        versatz = zeile_von(basis) - 1
        for i, z in enumerate(zeilen):
            if z.strip().startswith("//"):
                continue
            code = re.split(r"(?<![:\\\"'])//(?=[^\"'`]*$)", z)[0]
            for m in re.finditer(r'"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'|`((?:[^`\\]|\\.)*)`', code):
                ergebnis.append((versatz + i + 1, m.group(1) or m.group(2) or m.group(3) or ""))
    return ergebnis

def pruefen(quellen, webapp, bauen):
    funde, gelesen, lesefehler = [], 0, []
    if not os.path.isdir(quellen):
        print(f"✗ Name der Web App: {quellen} ist kein Ordner — gelesen wurde nichts"); return 1
    # Ohne onerror übergeht os.walk einen Ordner, der sich nicht lesen lässt, still
    # (R75-02, v76) — hier ist er ein Fehler.
    for wurzel, _, dateien in os.walk(quellen, onerror=lesefehler.append):
        for d in sorted(dateien):
            if not d.endswith(".swift"):
                continue
            pfad = os.path.join(wurzel, d)
            gelesen += 1
            for nr, s in swift_zeichenketten(open(pfad, encoding="utf-8").read()):
                if MUSTER_APP.search(s):
                    funde.append((os.path.relpath(pfad, os.path.dirname(quellen)), nr, s))
    for fehler in lesefehler:
        print(f"✗ Name der Web App: {os.path.relpath(fehler.filename, quellen)} nicht lesbar"
              f" ({fehler.strerror}) — gelesen wurde nicht alles")
    if lesefehler:
        return 1
    html = os.path.join(webapp, "unterrichtsplanung-ansicht.html")
    manifest = os.path.join(webapp, "manifest.webmanifest")
    for pfad in (html, manifest):
        if not os.path.isfile(pfad):
            print(f"✗ Name der Web App: {pfad} fehlt — gelesen wurde nicht alles"); return 1
    gelesen += 2
    for nr, s in html_texte(open(html, encoding="utf-8").read()):
        if MUSTER.search(s):
            funde.append(("Web-App/" + os.path.basename(html), nr, s))
    m = json.load(open(manifest, encoding="utf-8"))
    for schluessel in ("name", "short_name", "description"):
        if MUSTER.search(m.get(schluessel, "")):
            funde.append(("Web-App/manifest.webmanifest", schluessel, m[schluessel]))
    # Der Beipackzettel des Abbilds (bauen.sh, zwischen <<HINWEIS und HINWEIS) —
    # er liegt der App bei, also wie die App: auch kein „iPad“.
    if not os.path.isfile(bauen):
        print(f"✗ Name der Web App: {bauen} fehlt — gelesen wurde nicht alles"); return 1
    zeilen = open(bauen, encoding="utf-8").read().split("\n")
    anfang = next((i for i, z in enumerate(zeilen) if "<<HINWEIS" in z), None)
    ende = next((i for i, z in enumerate(zeilen) if anfang is not None and i > anfang and z == "HINWEIS"), None)
    if anfang is None or ende is None:
        print("✗ Name der Web App: Der Beipackzettel in bauen.sh ist nicht zu finden"); return 1
    gelesen += 1
    for i in range(anfang + 1, ende):
        if MUSTER_APP.search(zeilen[i]):
            funde.append(("bauen.sh (Beipackzettel)", i + 1, zeilen[i]))
    if gelesen < 4:
        print("✗ Name der Web App: keine Swift-Datei gelesen"); return 1
    funde = list(dict.fromkeys(funde))  # der Titel steht als HTML-Text und als <title>
    for datei, nr, s in funde:
        print(f"✗ Name der Web App in {datei}:{nr} — „{' '.join(s.split())[:90]}“ — „Web App“ statt „Ansicht“, das Gerät statt des iPads")
    if funde:
        return 1
    print(f"Name der Web App stimmig — {gelesen} Dateien gelesen, „Ansicht“ als Name und „iPad“ in der App: 0 (E219)")
    return 0

sys.exit(pruefen(sys.argv[1], sys.argv[2], sys.argv[3]))
PY
}

# Der Schritt: zuerst die Gegenprobe an Prüfordnern — zehn Stellen, die gemeldet
# werden müssen (eine davon in einem Unterordner, eine in einem mehrzeiligen
# Literal, zwei in Attributen), und was bleiben darf: ein Kommentar, ein Dateiname, das iPad als
# Gerät in der Web App; dazu, an sauberen Eingaben, was nicht gelesen wurde und
# rot sein muss: ein Ordner ohne Swift-Datei, ein unlesbarer Unterordner, ein
# fehlender Ordner, ein fehlendes Manifest (R75-02, B65) —, dann die App, die
# Web App und der Beipackzettel.
webappname() {
  local probe gegen ergebnis=0
  probe="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unterrichtsplanung-webappname.XXXXXX")" || return 1
  mkdir -p "$probe/quellen/Unter" "$probe/web" "$probe/leer"
  printf '%s\n' '        Text("in der Ansicht fürs iPad")' > "$probe/quellen/A.swift"
  printf '%s\n' '        Text("in der Web App")' > "$probe/quellen/B.swift"
  printf '%s\n' '        // die Ansicht fürs iPad' > "$probe/quellen/C.swift"
  printf '%s\n' '        let s = "auf dem iPad"' > "$probe/quellen/Unter/D.swift"
  printf '%s\n' '        let t = """' '        Die Ansicht' '        """' > "$probe/quellen/E.swift"
  printf '%s\n' '<title>X — Ansicht</title>' '<p>Über diese Ansicht</p>' '<script>' \
    '// die Ansicht' 'const a = "diese Ansicht";' 'const b = "unterrichtsplanung-ansicht.html";' \
    'const c = "auf dem iPad";' '</script>' '<button title="Über diese Ansicht" aria-label="Info zur Ansicht">i</button>' \
    > "$probe/web/unterrichtsplanung-ansicht.html"
  printf '%s\n' '{"name": "U — Ansicht", "short_name": "U", "description": "Web App"}' \
    > "$probe/web/manifest.webmanifest"
  printf '%s\n' 'cat > x <<HINWEIS' 'Ansicht fürs iPad' 'Web App' 'HINWEIS' > "$probe/bauen.sh"
  gegen="$(webappnameVon "$probe/quellen" "$probe/web" "$probe/bauen.sh")"
  if [ "$(grep -c '^✗' <<<"$gegen")" != "10" ] || grep -qE 'B\.swift|C\.swift|:6 |:7 ' <<<"$gegen" \
     || ! grep -q 'Unter/D.swift' <<<"$gegen"; then
    echo "Gegenprobe des Namens: Die Regel greift nicht wie verlangt —"
    printf '%s\n' "$gegen" | sed 's/^/  /'
    ergebnis=1
  fi
  # Was nicht gelesen wurde, ist rot — geprüft an sauberen Eingaben, damit die
  # Meldung zählt und nicht ein Fund, der ohnehin rot machte (B65, v76).
  mkdir -p "$probe/sauber" "$probe/web-sauber" "$probe/gesperrt/Unter"
  printf '%s\n' '        Text("in der Web App")' > "$probe/sauber/A.swift"
  printf '%s\n' '<title>X — Web App</title>' > "$probe/web-sauber/unterrichtsplanung-ansicht.html"
  printf '%s\n' '{"name": "U — Web App", "short_name": "U", "description": "Web App"}' \
    > "$probe/web-sauber/manifest.webmanifest"
  printf '%s\n' 'cat > x <<HINWEIS' 'Web App' 'HINWEIS' > "$probe/bauen-sauber.sh"
  printf '%s\n' '        Text("in der Web App")' > "$probe/gesperrt/A.swift"
  printf '%s\n' '        Text("in der Ansicht fürs iPad")' > "$probe/gesperrt/Unter/D.swift"
  /bin/chmod 000 "$probe/gesperrt/Unter"
  # $1 Fall, $2 verlangte Meldung, danach die Argumente für webappnameVon.
  nichtGelesen() {
    local fall="$1" meldung="$2" aus rc
    shift 2
    aus="$(webappnameVon "$@" 2>&1)"; rc=$?
    if [ "$rc" = 0 ] || ! grep -q -- "$meldung" <<<"$aus"; then
      echo "Gegenprobe des Namens: $fall galt als gelesen (Rückgabe $rc) —"
      printf '%s\n' "$aus" | sed 's/^/  /'
      ergebnis=1
    fi
  }
  if ! webappnameVon "$probe/sauber" "$probe/web-sauber" "$probe/bauen-sauber.sh" > /dev/null; then
    echo "Gegenprobe des Namens: Saubere Eingaben galten nicht als stimmig."; ergebnis=1
  fi
  nichtGelesen "Ein Ordner ohne Swift-Datei" "keine Swift-Datei gelesen" \
    "$probe/leer" "$probe/web-sauber" "$probe/bauen-sauber.sh"
  nichtGelesen "Ein unlesbarer Unterordner" "Unter nicht lesbar" \
    "$probe/gesperrt" "$probe/web-sauber" "$probe/bauen-sauber.sh"
  nichtGelesen "Ein fehlender Ordner der Quellen" "kein Ordner" \
    "$probe/gibt-es-nicht" "$probe/web-sauber" "$probe/bauen-sauber.sh"
  rm -f "$probe/web-sauber/manifest.webmanifest"
  nichtGelesen "Eine Web App ohne Manifest" "manifest.webmanifest fehlt" \
    "$probe/sauber" "$probe/web-sauber" "$probe/bauen-sauber.sh"
  /bin/chmod -R u+rwx "$probe"
  rm -rf "$probe"
  webappnameVon "$HIER/Quellen" "$ANSICHT" "$HIER/bauen.sh" || ergebnis=1
  return "$ergebnis"
}

if [ "$NURSTAND" = "1" ]; then quellenstand; exit $?; fi
if [ "$NURSELBSTTEST" = "1" ]; then inventarSelbsttest; exit $?; fi
if [ "$NURWARTESTELLEN" = "1" ]; then wartestellen; exit $?; fi
if [ "$NURZEITGEBER" = "1" ]; then zeitgeber; exit $?; fi
if [ "$NURWEBAPPNAME" = "1" ]; then webappname; exit $?; fi
if [ "$NURWERKZEUG" = "1" ]; then werkzeugstand; exit $?; fi
if [ "$NURINVENTAR" = "1" ]; then inventar; exit $?; fi

# Ohne Stand kein Vermerk: Er sagt, wofür er gilt — das muss er halten können.
STAND="$(quellenstand)" || {
  echo "Der Stand der Quellen ließ sich nicht vollständig bestimmen (Grund darüber) — kein Vermerk, keine Prüfung."
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
# Bei ✗ dazu die Befundzeilen von Swift Testing („recorded an issue“, „failed after“, „error:“;
# sie stehen oft weiter oben als die letzten 30 Zeilen; die Schlusszeile ist schon die Kernzeile)
# und das ganze Protokoll als Paket/Pruefprotokoll-<Stempel>-<n>.txt neben dem Vermerk;
# sonst ginge mit dem Protokoll der Name eines sporadischen Befunds verloren (E486).
# Die Python-Schritte haben eigene Marken — ihr Befund steht im Protokoll.
PROTOKOLLNUMMER=0
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
    local befunde kopie
    befunde="$(sed -E 's/\x1b\[[0-9;]*m//g' "$PROTOKOLL" | grep -E 'recorded an issue|failed after|error:' | grep -v 'Test run with' || true)"
    if [ -n "$befunde" ]; then
      echo "  Befundzeilen:"
      printf '%s\n' "$befunde" | sed 's/^/    /'
      printf '%s\n' "$befunde" | sed 's/^/    /' >> "$LAUFEND"
    fi
    PROTOKOLLNUMMER=$((PROTOKOLLNUMMER + 1))
    kopie="$HIER/Paket/Pruefprotokoll-$STEMPEL-$PROTOKOLLNUMMER.txt"
    if cp "$PROTOKOLL" "$kopie"; then
      echo "  Protokoll: $kopie"
      echo "    Protokoll: Paket/$(basename "$kopie")" >> "$LAUFEND"
    else
      echo "  Protokoll: nicht gesichert"
      echo "    Protokoll: nicht gesichert (cp scheiterte)" >> "$LAUFEND"
    fi
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

# Die Messungen der Rechenzeit (E553, E591): `handgriffsdauer` misst die Rechenzeit
# des Hauptstrangs nach Durchläufen der Ereignisschleife, `vollausbau` die Anordnung
# mit der Wanduhr — beides Uhren. Im vollen Lauf rechnen nebenher alle Suiten, die
# Messung liefe unter fremder Last. Der Hauptlauf überspringt sie (--skip), danach
# laufen sie allein und seriell (--no-parallel) auf demselben Bau. Verlangt sind
# genau MESSUNGEN_ZAHL Prüfungen: Trifft das Muster eine umbenannte nicht mehr, liefe
# sie im Hauptlauf unter Last mit — der Durchgang ist dann rot.
MESSUNGEN='Abbilder/(handgriffsdauer|vollausbau)\('
MESSUNGEN_ZAHL=2
messdurchgang() {
  local aus rc zahl
  aus="$(env PLANUNGSORDNER="$PRUEFORDNER" swift test --scratch-path "$BAUORDNER" --no-parallel \
    --filter "$MESSUNGEN" "${LINKER[@]}" 2>&1)"; rc=$?
  printf '%s\n' "$aus"
  [ "$rc" -eq 0 ] || return 1
  zahl="$(sed -E 's/\x1b\[[0-9;]*m//g' <<<"$aus" | sed -nE 's/.*Test run with ([0-9]+) tests? .*/\1/p' | tail -1)"
  if [ "$zahl" != "$MESSUNGEN_ZAHL" ]; then
    echo "✗ Messdurchgang (Abweichung): Prüfungen gelaufen: ${zahl:-keine}, verlangt: $MESSUNGEN_ZAHL — trifft „$MESSUNGEN“ noch alle Messungen?"
    return 1
  fi
}

# Die ständige Verzögerungsprobe (E551, E590): Ein voller Lauf fährt die Suite
# ohne die Messungen (E553, E591) noch zweimal seriell — PRUEFTAKT=stauchen (jede
# Frist des Systemtakts null, alles so früh wie möglich — E609) und PRUEFTAKT=dehnen
# (zehnfach), wirksam nur in
# Debug-Bauten (Taktgeber.swift). Kippt dabei eine Prüfung, wartet sie mit einer
# Frist auf den Systemtakt, setzt eine Folge zweier Fristen voraus oder setzt
# voraus, dass eine Frist noch nicht fällig ist (etwa der Verfall einer Meldung,
# gezählt nach einem `await`, E600) — sie gehört auf die Stelluhr (AT6h-2). Wer
# ohne Frist auf den Systemtakt wartet, kippt nicht, sondern wartet gedehnt
# zehnmal so lang. Seriell, weil im Parallellauf die Last die Kipper verdeckt
# (AT6c, AT6h). Verlangt ist die Zahl der Prüfungen des Hauptlaufs — sonst
# schrumpfte die Probe still. Übersetzt wird nichts neu — dieselben
# Bauargumente; `--no-parallel` und `--skip` sind Laufoptionen. Eine bleibende
# Änderung der Quellen fängt „Quellenstand am Ende derselbe“, eine bis dahin
# zurückgenommene nicht. Die Ausgabe steht während des Laufs in
# probe-<art>.txt im Prüfordner — hängt die Probe, steht dort, woran. Die
# Prüfung `prueftakt` läuft mit und weist einen unbekannten Wert ab (Z-AT6h1-07).
# $1 stauchen oder dehnen.
verzoegerungsprobe() {
  local art="$1" aus="$PRUEFORDNER/probe-$1.txt" rc zahl
  mkdir -p "$PRUEFORDNER/probe-$art" || return 1
  env PLANUNGSORDNER="$PRUEFORDNER/probe-$art" PRUEFTAKT="$art" swift test --scratch-path "$BAUORDNER" \
    --no-parallel --skip "$MESSUNGEN" "${LINKER[@]}" > "$aus" 2>&1; rc=$?
  cat "$aus"
  [ "$rc" -eq 0 ] || return 1
  zahl="$(sed -E 's/\x1b\[[0-9;]*m//g' "$aus" | sed -nE 's/.*Test run with ([0-9]+) tests? .*/\1/p' | tail -1)"
  if [ "$zahl" != "$HAUPTZAHL" ]; then
    echo "✗ Verzögerungsprobe (PRUEFTAKT=$art, Abweichung): Prüfungen gelaufen: ${zahl:-keine}, im Hauptlauf: ${HAUPTZAHL:-keine}"
    return 1
  fi
}

# Zuerst das Inventar: Der Vermerk gilt für den Stand — also muss der Stand
# alles decken, was zur Fassung gehört.
schritt "Inventar (der Quellenstand deckt die Fassungswurzeln)" inventar
# Und die Regel dahinter, an Ordnern, an denen sie greifen muss (E197).
schritt "Inventar-Selbsttest (ohne stimmiges Inventar kein Stand)" inventarSelbsttest
# Keine Prüfung wartet mit Takt oder Uhr (E145, E207).
schritt "Wartestellen ohne Takt, Uhren nach Art (E145, E550)" wartestellen
# Die Zeitgeber des Programms gehen über den Taktgeber, außer den benannten (E561).
schritt "Zeitgeber nur über den Taktgeber, Ausnahmen nach Art (E561)" zeitgeber
schritt "Name der Web App (E219)" webappname

# Mit den Linkerargumenten des Pakets (E126): Geprüft wird, was gebaut wird.
schritt "swift test (frisch übersetzt, PLANUNGSORDNER=$PRUEFORDNER, -platform_version, ohne die Messungen)" \
    env PLANUNGSORDNER="$PRUEFORDNER" swift test --scratch-path "$BAUORDNER" --skip "$MESSUNGEN" "${LINKER[@]}"
warnungenZaehlen "Programm und Prüfungen"
# Die Zahl der Prüfungen des Hauptlaufs — die Verzögerungsprobe verlangt dieselbe.
HAUPTZAHL="$(sed -E 's/\x1b\[[0-9;]*m//g' "$PROTOKOLL" | sed -nE 's/.*Test run with ([0-9]+) tests? .*/\1/p' | tail -1)"
schritt "Messungen allein und seriell (E553, E591)" messdurchgang
if [ "$SCHNELL" = "1" ]; then
  echo "· Verzögerungsprobe übersprungen (--schnell)" >> "$LAUFEND"
else
  schritt "Verzögerungsprobe gestaucht (PRUEFTAKT=stauchen, seriell; E551, E590)" verzoegerungsprobe stauchen
  schritt "Verzögerungsprobe gedehnt (PRUEFTAKT=dehnen, seriell; E551, E590)" verzoegerungsprobe dehnen
fi
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
# Der Stand am Ende (E201, B49): Die Schritte lesen die Quellen noch minutenlang
# nach dem Stand vom Anfang. Ist er jetzt ein anderer, gilt der Vermerk nicht —
# beglaubigen.sh nimmt keinen mit Befund. (Eine Änderung, die bis zum Ende schon
# wieder zurückgenommen ist, sieht kein Vergleich zweier Stände.)
STANDENDE="$(quellenstand 2>/dev/null)" || STANDENDE=""
if [ "$STANDENDE" = "$STAND" ]; then
  echo "  ✓ Quellenstand am Ende derselbe"
  echo "✓ Quellenstand am Ende derselbe" >> "$LAUFEND"
else
  echo "  ✗ Die Quellen haben sich während des Prüflaufs geändert ($(cut -c1-12 <<<"$STAND")… → $(cut -c1-12 <<<"${STANDENDE:-kein Stand}")…)"
  echo "✗ Die Quellen haben sich während des Prüflaufs geändert ($(cut -c1-12 <<<"$STAND")… → $(cut -c1-12 <<<"${STANDENDE:-kein Stand}")…)" >> "$LAUFEND"
  ERGEBNIS=1
fi
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
