#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Gemeinsame Hilfen der Prüfskripte: Funktionen, Konstanten und Abschnitte aus
dem Skript der Ansicht ziehen — zeichenketten- und kommentarfest.

Die Klammerzählung überspringt Zeichenketten (auch Vorlagen mit `${…}`),
Kommentare und Regex-Literale: Eine geschweifte Klammer oder ein Anführungszeichen
darin brächte sonst die Zählung durcheinander, und ein Skript, das zufällig
aufging, belegte nichts. Ob ein `/` ein Literal beginnt oder teilt, entscheidet
das letzte bedeutsame Zeichen davor (nach `)`, `]`, einem Namen oder einer Zahl
ist es eine Division).

Eingebunden von `abzug_pruefen.py`, `leser_pruefen.py`, `schulwochen_pruefen.py`
und `tresor_pruefen.py`; je Fassung liegt es daneben. Nur Standardbibliothek,
Python 3.10 oder neuer. `python3 pruefhilfen.py` lässt den Selbsttest laufen.
"""

import sys

if sys.version_info < (3, 10):
    raise SystemExit("pruefhilfen.py braucht Python 3.10 oder neuer — /usr/bin/python3 ist 3.9; "
                     "python3 aus Xcode, Homebrew oder python.org nehmen.")

import re
from pathlib import Path

# Wonach ein `/` ein Regex-Literal beginnt: nach einem Operator, einer öffnenden
# Klammer, einem Trenner oder einem dieser Schlüsselwörter — sonst teilt es.
_REGEX_NACH_ZEICHEN = set("(,=:[!&|?{};+-*%<>~^")
_REGEX_NACH_WOERTERN = {"return", "typeof", "case", "in", "of", "do", "else", "instanceof",
                        "void", "delete", "throw", "new", "yield", "await"}


def _regexBeginnt(text: str, i: int) -> bool:
    j = i - 1
    while j >= 0 and text[j] in " \t\r\n":
        j -= 1
    if j < 0:
        return True
    z = text[j]
    if z in _REGEX_NACH_ZEICHEN:
        return True
    if z.isalnum() or z in "_$":
        k = j
        while k >= 0 and (text[k].isalnum() or text[k] in "_$"):
            k -= 1
        return text[k + 1:j + 1] in _REGEX_NACH_WOERTERN
    return False


def _regexende(text: str, i: int) -> int | None:
    """Die Stelle des letzten Zeichens (samt Flags) des Regex-Literals ab `i` — None, wenn
    vor dem Zeilenende kein schließender `/` kommt (dann war es kein Literal)."""
    j = i + 1
    klasse = False
    while j < len(text):
        z = text[j]
        if z == "\\":
            j += 2
            continue
        if z == "\n":
            return None
        if klasse:
            klasse = z != "]"
        elif z == "[":
            klasse = True
        elif z == "/":
            k = j + 1
            while k < len(text) and text[k].isalpha():
                k += 1
            return k - 1
        j += 1
    return None


def skript(html) -> str:
    """Der Inhalt des einen `<script>`-Blocks der Ansicht — aus dem Pfad oder dem Text."""
    text = html.read_text(encoding="utf-8") if isinstance(html, Path) else html
    treffer = re.search(r"<script>(.*?)</script>", text, re.S)
    if not treffer:
        raise SystemExit("Kein Skriptblock in der HTML gefunden.")
    return treffer.group(1)


def _ueberspringen(text: str, i: int) -> int | None:
    """Steht bei `i` eine Zeichenkette, ein Kommentar oder ein Regex-Literal, die
    Stelle ihres letzten Zeichens — sonst None."""
    z = text[i]
    if z in "\"'`":
        j = i + 1
        while j < len(text) and text[j] != z:
            j += 2 if text[j] == "\\" else 1
        return j
    if text.startswith("//", i):
        return text.index("\n", i)
    if text.startswith("/*", i):
        return text.index("*/", i) + 1
    if z == "/" and _regexBeginnt(text, i):
        return _regexende(text, i)
    return None


def klammerende(text: str, start: int) -> int:
    """Die Stelle der schließenden `}` zur ersten `{` ab `start`."""
    i = text.index("{", start)
    tiefe = 0
    while i < len(text):
        ende = _ueberspringen(text, i)
        if ende is not None:
            i = ende + 1
            continue
        if text[i] == "{":
            tiefe += 1
        elif text[i] == "}":
            tiefe -= 1
            if tiefe == 0:
                return i
        i += 1
    raise SystemExit("Klammern unausgeglichen — endet der Block nicht?")


def semikolonende(text: str, start: int) -> int:
    """Die Stelle des ersten `;` ab `start` außerhalb von Klammern, Zeichenketten und Kommentaren."""
    i = start
    tiefe = 0
    while i < len(text):
        ende = _ueberspringen(text, i)
        if ende is not None:
            i = ende + 1
            continue
        z = text[i]
        if z in "{[(":
            tiefe += 1
        elif z in "}])":
            tiefe -= 1
        elif z == ";" and tiefe == 0:
            return i
        i += 1
    raise SystemExit("Kein Ende der Anweisung gefunden.")


def funktion(text: str, name: str) -> str:
    """`function <name>(…) {…}` samt Rumpf — ein `async` davor kommt mit."""
    kopf = f"function {name}("
    try:
        anfang = text.index(kopf)
    except ValueError:
        raise SystemExit(f"Funktion nicht gefunden: {name}") from None
    if anfang >= 6 and text.startswith("async ", anfang - 6):
        anfang -= 6
    return text[anfang:klammerende(text, anfang) + 1]


def konstante(text: str, name: str) -> str:
    """`const <name> = …;` — bis zum Semikolon außerhalb aller Klammern."""
    kopf = f"\nconst {name} = "
    try:
        anfang = text.index(kopf) + 1
    except ValueError:
        raise SystemExit(f"Konstante nicht gefunden: {name}") from None
    return text[anfang:semikolonende(text, anfang) + 1]


def block(text: str, kopf: str) -> str:
    """Ein Block nach seinem Kopf: `const X`, `function X`, `async function X`, `class X`."""
    if kopf.startswith("const "):
        return konstante(text, kopf[len("const "):])
    try:
        anfang = text.index("\n" + kopf) + 1
    except ValueError:
        raise SystemExit(f"Block nicht gefunden: {kopf}") from None
    return text[anfang:klammerende(text, anfang) + 1]


def abschnitt(text: str, anfangsmarke: str, endfunktion: str) -> str:
    """Alles von `anfangsmarke` bis zum Ende der Funktion `endfunktion` — die
    Deklarationen dazwischen samt der Funktion selbst."""
    try:
        anfang = text.index(anfangsmarke)
        ende = text.index(f"function {endfunktion}(")
    except ValueError as fehler:
        raise SystemExit(f"Abschnitt nicht gefunden: {fehler}") from None
    return text[anfang:klammerende(text, ende) + 1]


def selbsttest() -> int:
    """Die Extraktion an dem, was sie stolpern ließe: Regex mit Klammer und
    Anführungszeichen, Divisionen, Vorlagen, Kommentare. Zahl der Fehler."""
    g = "\nfunction g() { return 0; }\n"
    faelle = [
        ("Regex mit }", "function f(x) { if (/[}]/.test(x)) { return 1; } return 2; }" + g,
         "function f(x) { if (/[}]/.test(x)) { return 1; } return 2; }"),
        ("Regex mit Anführungszeichen", 'function f(x) { return /"[^"]*"/.test(x); }' + g,
         'function f(x) { return /"[^"]*"/.test(x); }'),
        ("Regex mit Escape und Flags", "function f(x) { return x.replace(/\\/{2}/g, \"/\"); }" + g,
         "function f(x) { return x.replace(/\\/{2}/g, \"/\"); }"),
        ("Division bleibt Division", "function f(a, b, c) { return a / b / c; }" + g,
         "function f(a, b, c) { return a / b / c; }"),
        ("Division nach Klammer", "function f(a) { return (a + 1) / 2 } " + g,
         "function f(a) { return (a + 1) / 2 }"),
        ("Vorlage mit Objekt", "function f(a) { return `${ {a: 1}.a }`; }" + g,
         "function f(a) { return `${ {a: 1}.a }`; }"),
        ("Kommentar mit Klammer", "function f() { // {\n  return 1; /* } */ }" + g,
         "function f() { // {\n  return 1; /* } */ }"),
        ("async davor", "async function f() { await x; }" + g, "async function f() { await x; }"),
    ]
    fehler = 0
    for name, text, erwartet in faelle:
        try:
            ist = funktion(text, "f")
        except SystemExit as grund:
            ist = f"Abbruch: {grund}"
        if ist != erwartet:
            fehler += 1
            print(f"  FEHLER  {name}: {ist!r}")
        else:
            print(f"  stimmt  {name}")
    konst = "\nconst M = /;[}]/;\nconst N = 1;\n"
    if konstante(konst, "M") != "const M = /;[}]/;":
        fehler += 1
        print(f"  FEHLER  Konstante mit Regex: {konstante(konst, 'M')!r}")
    else:
        print("  stimmt  Konstante mit Regex")
    print("Selbsttest: " + ("bestanden" if not fehler else f"{fehler} Fehler"))
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(selbsttest())
