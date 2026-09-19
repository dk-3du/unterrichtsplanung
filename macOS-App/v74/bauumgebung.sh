# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: GPL-3.0-or-later
# ──────────────────────────────────────────────────────────────────────────
#  Unterrichtsplanung — die Bauumgebung an einer Stelle (E124–E127, v63)
#
#  Nicht ausführbar, nur zum Einlesen:   . "$HIER/bauumgebung.sh"
#  Leser: pruefen.sh (Prüfbau), bauen.sh (Paket), beglaubigen.sh (Vergleich).
#
#  Der Quellenstand bindet, *welche Quellen* geprüft und gebaut wurden — nicht,
#  *womit*. Der Sprung v58→v59 zeigte, dass die Werkzeugkette das Programm
#  ändert (LC_BUILD_VERSION trug sdk 26.0 statt 27.0, E106). Darum trägt seit
#  v63 jeder Prüfvermerk, jedes Paket (UPWerkzeugstand, mitsigniert) und jede
#  Beglaubigungs-Zusammenfassung den **Werkzeugstand** — eine SHA-256 über den
#  Block unten —, und beglaubigen.sh verlangt, dass alle drei dem aktuellen
#  gleichen (N61-01, elfte Review).
#
#  Stellt bereit (Bash 3.2, kein mapfile, keine assoziativen Felder):
#     mindestsystem            LSMinimumSystemVersion aus Beiwerk/Info.plist
#     sdkversion               xcrun --show-sdk-version
#     linkerargumente          füllt das Feld LINKER (-platform_version …)
#     werkzeugstand [konfiguration]   der Block: Xcode, Swift, SDK, Mindestsystem,
#                              Ziel (arm64 und die Konfiguration, Vorgabe
#                              release), Linker — in fester Reihenfolge
#     werkzeugkennung [konfiguration] SHA-256 des Blocks, 64 Hexziffern oder Fehlschlag
#                              Die Konfiguration gehört zur Kennung (E138,
#                              N61-01 Rest, seit v65): Ein Debug-Bau trägt
#                              damit eine andere als der Release-Bau, den der
#                              Prüfbau und die Beglaubigung meinen.
#     bauversion <Programm>    „minos sdk“ aus LC_BUILD_VERSION
#     bauversionPruefen <Programm>   dasselbe, geprüft gegen Mindestsystem und SDK
#     rechner                  macOS-Fassung und -Build — nur zur Auskunft,
#                              nicht Teil der Kennung (E125: ein Punktupdate
#                              des Macs ändert das Programm nicht)
#
#  Jede Funktion schreibt ihren Grund nach stderr und liefert 1, wenn eine
#  Angabe fehlt: Ein Werkzeugstand, dem ein Glied fehlt, ist keiner (wie der
#  Quellenstand, E63). xcodebuild braucht seinen Cache unter /var/folders —
#  die Skripte laufen ohnehin ohne Sandbox.
# ──────────────────────────────────────────────────────────────────────────

BAUUMGEBUNG_HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mindestsystem() {
  local m
  m="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$BAUUMGEBUNG_HIER/Beiwerk/Info.plist" 2>/dev/null || true)"
  case "$m" in
    *[!0-9.]*|"") echo "Das Mindestsystem (LSMinimumSystemVersion) ließ sich nicht lesen: „$m“" >&2; return 1 ;;
  esac
  printf '%s\n' "$m"
}

sdkversion() {
  local s
  s="$(xcrun --show-sdk-version 2>/dev/null || true)"
  case "$s" in
    *[!0-9.]*|"") echo "Die SDK-Fassung ließ sich nicht bestimmen (xcrun --show-sdk-version): „$s“" >&2; return 1 ;;
  esac
  printf '%s\n' "$s"
}

# Mindestsystem und Bau-SDK getrennt benennen (E106): Der neue `swift build`
# trüge sonst das Mindestsystem zugleich als Bau-SDK ein. Füllt LINKER — Bash
# 3.2 gibt keine Felder zurück.
linkerargumente() {
  local m s
  m="$(mindestsystem)" || return 1
  s="$(sdkversion)" || return 1
  LINKER=(-Xlinker -platform_version -Xlinker macos -Xlinker "$m" -Xlinker "$s")
}

werkzeugstand() {
  local xcode swiftzeile sdk sdkbau m konfiguration
  konfiguration="${1:-release}"
  case "$konfiguration" in
    release|debug) ;;
    *) echo "Unbekannte Konfiguration „$konfiguration“ — release oder debug" >&2; return 1 ;;
  esac
  # „Xcode 27.0“ + „Build version 27A266a“ → „27.0 (27A266a)“
  xcode="$(xcodebuild -version 2>/dev/null | awk '/^Xcode /{v=$2} /^Build version /{b=$3} END{if (v!="" && b!="") print v" ("b")"}')"
  # „swift-driver version: … Apple Swift version 6.4 (swiftlang-… clang-…)“ → ab „Apple“
  swiftzeile="$(swift --version 2>/dev/null | head -1 | sed -E 's/^.*(Apple Swift version .*)$/\1/')"
  case "$swiftzeile" in "Apple Swift version "*) ;; *) swiftzeile="" ;; esac
  sdk="$(sdkversion)" || return 1
  sdkbau="$(xcrun --show-sdk-build-version 2>/dev/null || true)"
  m="$(mindestsystem)" || return 1
  if [ -z "$xcode" ] || [ -z "$swiftzeile" ] || [ -z "$sdkbau" ]; then
    echo "Der Werkzeugstand ließ sich nicht vollständig bestimmen (Xcode „$xcode“, Swift „$swiftzeile“, SDK-Build „$sdkbau“)" >&2
    return 1
  fi
  printf 'Xcode: %s\nSwift: %s\nSDK: macOS %s (%s)\nMindestsystem: %s\nZiel: arm64, %s\nLinker: -platform_version macos %s %s\n' \
    "$xcode" "$swiftzeile" "$sdk" "$sdkbau" "$m" "$konfiguration" "$m" "$sdk"
}

werkzeugkennung() {
  local block k
  block="$(werkzeugstand "${1:-release}")" || return 1
  k="$(printf '%s\n' "$block" | shasum -a 256 | cut -c1-64)" || return 1
  if [ "${#k}" != "64" ] || [ -n "${k//[0-9a-f]/}" ]; then
    echo "Die Kennung des Werkzeugstands ließ sich nicht bilden." >&2
    return 1
  fi
  printf '%s\n' "$k"
}

rechner() {
  printf 'macOS %s (%s)\n' "$(sw_vers -productVersion 2>/dev/null)" "$(sw_vers -buildVersion 2>/dev/null)"
}

# „minos sdk“ aus LC_BUILD_VERSION eines Programms.
bauversion() {
  otool -l "$1" 2>/dev/null | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{m=$2} f&&/sdk/{s=$2; exit} END{print m" "s}'
}

# Nachgeprüft, nicht vermutet: Das Programm trägt beides so, wie es gebaut
# werden sollte (E106). Gibt „minos sdk“ aus oder scheitert mit Grund.
bauversionPruefen() {
  local ist soll m s
  m="$(mindestsystem)" || return 1
  s="$(sdkversion)" || return 1
  soll="$m $s"
  ist="$(bauversion "$1")"
  if [ "$ist" != "$soll" ]; then
    echo "LC_BUILD_VERSION trägt „$ist“ (minos sdk), erwartet „$soll“: $1" >&2
    return 1
  fi
  printf '%s\n' "$ist"
}
