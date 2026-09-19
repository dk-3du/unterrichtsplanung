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
#                              oder Uhr, außer sie ist am Ort benannt“ (E145,
#                              E210, E215), mit ihrer Gegenprobe
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
NURWEBAPPNAME=0
for arg in "$@"; do
  case "$arg" in
    --schnell) SCHNELL=1 ;;
    --stand)   NURSTAND=1 ;;
    --werkzeugstand) NURWERKZEUG=1 ;;
    --inventar) NURINVENTAR=1 ;;
    --inventar-selbsttest) NURSELBSTTEST=1 ;;
    --wartestellen) NURWARTESTELLEN=1 ;;
    --webappname) NURWEBAPPNAME=1 ;;
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
  keinStand "Verknüpfung in der Ansicht" ansicht-verknuepft

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
# „// E145: Uhr — <Grund>“ und wird gezählt; reine Kommentarzeilen zählen nicht.
# Der Schritt liest Zeilen, nicht Bedeutung: Eine Wartestelle in einer Form,
# die das Muster nicht kennt, sieht er nicht. Ein Lesefehler und ein Ordner
# ohne Swift-Datei sind rot — sonst hieße „nichts gefunden“ auch „nichts gelesen“.
# $1 Ordner der Prüfungen. Nennt jede ungenannte Stelle; Rückgabe 1, wenn es
# eine gibt oder nicht gelesen werden konnte.
wartestellenVon() {
  local ordner="$1" treffer funde benannt rc anzahl
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
  benannt="$(grep -c '// E145: Uhr — ' <<<"$treffer" || true)"
  funde="$(grep -v '// E145: Uhr — ' <<<"$treffer" | grep -v '^$' || true)"
  if [ -n "$funde" ]; then
    printf '%s\n' "$funde" | awk -F: '{ print "✗ Wartestelle mit Takt oder Uhr in Pruefungen/" $1 ":" $2 " — auf ein Signal, das Ende der Aufgabe oder abwarten(_:bis:) warten, oder benennen: // E145: Uhr — <Grund>" }'
    return 1
  fi
  echo "Wartestellen stimmig — $anzahl Dateien gelesen, benannt: $benannt, ungenannt: 0 (E145)"
}

# Der Schritt: zuerst die Gegenprobe — ein Prüfordner mit jeder erkannten Form
# (elf Stellen, die gemeldet werden müssen, eine davon in einem Unterordner) und
# zwei, die bleiben dürfen (eine benannte Uhr, ein Kommentar); dazu ein Ordner
# mit einer unlesbaren Datei, einer ohne Swift-Datei und einer mit einer
# einzigen Datei —, dann die Prüfungen der Fassung.
wartestellen() {
  local probe gegen ergebnis=0
  probe="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/unterrichtsplanung-wartestellen.XXXXXX")" || return 1
  mkdir -p "$probe/formen/Unter" "$probe/gesperrt" "$probe/leer" "$probe/einzeln" "$probe/einzeln-kommentar"
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
  printf '%s\n' '        Thread.sleep(forTimeInterval: 0.003)  // E145: Uhr — Stempelvorschub' > "$probe/formen/Benannt.swift"
  printf '%s\n' '        // Früher stand hier Task.sleep(for: .seconds(1)).' > "$probe/formen/Kommentar.swift"
  printf '%s\n' '        let x = 1' > "$probe/gesperrt/Offen.swift"
  printf '%s\n' '        let y = 2' > "$probe/gesperrt/Gesperrt.swift"
  /bin/chmod 000 "$probe/gesperrt/Gesperrt.swift"
  printf '%s\n' '        try await Task.sleep(for: .seconds(1))' > "$probe/einzeln/Einzeln.swift"
  printf '%s\n' '        // Früher stand hier Task.sleep(for: .seconds(1)).' > "$probe/einzeln-kommentar/Nur.swift"

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
  if ! wartestellenVon "$probe/einzeln-kommentar" > /dev/null; then
    echo "Gegenprobe der Wartestellen: Ein Kommentar in einer einzelnen Datei galt als Wartestelle."; ergebnis=1
  fi
  /bin/chmod 600 "$probe/gesperrt/Gesperrt.swift"
  rm -rf "$probe"
  wartestellenVon "$HIER/Pruefungen" || ergebnis=1
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
# wenn nicht alles gelesen wurde.
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
    funde, gelesen = [], 0
    for wurzel, _, dateien in os.walk(quellen):
        for d in sorted(dateien):
            if not d.endswith(".swift"):
                continue
            pfad = os.path.join(wurzel, d)
            gelesen += 1
            for nr, s in swift_zeichenketten(open(pfad, encoding="utf-8").read()):
                if MUSTER_APP.search(s):
                    funde.append((os.path.relpath(pfad, os.path.dirname(quellen)), nr, s))
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
        print("✗ Name der Web App: der Beipackzettel in bauen.sh ist nicht zu finden"); return 1
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
# Gerät in der Web App —, dann die App, die Web App und der Beipackzettel.
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
  if webappnameVon "$probe/leer" "$probe/web" "$probe/bauen.sh" > /dev/null; then
    echo "Gegenprobe des Namens: Ohne Swift-Datei galt alles als gelesen."; ergebnis=1
  fi
  rm -f "$probe/web/manifest.webmanifest"
  if webappnameVon "$probe/quellen" "$probe/web" "$probe/bauen.sh" > /dev/null; then
    echo "Gegenprobe des Namens: Ohne Manifest galt alles als gelesen."; ergebnis=1
  fi
  rm -rf "$probe"
  webappnameVon "$HIER/Quellen" "$ANSICHT" "$HIER/bauen.sh" || ergebnis=1
  return "$ergebnis"
}

if [ "$NURSTAND" = "1" ]; then quellenstand; exit $?; fi
if [ "$NURSELBSTTEST" = "1" ]; then inventarSelbsttest; exit $?; fi
if [ "$NURWARTESTELLEN" = "1" ]; then wartestellen; exit $?; fi
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
# Und die Regel dahinter, an Ordnern, an denen sie greifen muss (E197).
schritt "Inventar-Selbsttest (ohne stimmiges Inventar kein Stand)" inventarSelbsttest
# Keine Prüfung wartet mit Takt oder Uhr (E145, E207).
schritt "Wartestellen ohne Takt (E145)" wartestellen
schritt "Name der Web App (E219)" webappname

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
