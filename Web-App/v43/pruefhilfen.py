#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Gemeinsame Hilfen der Prüfskripte: Funktionen, Konstanten und Abschnitte aus
dem Skript der Ansicht ziehen — zeichenketten- und kommentarfest.

Die Klammerzählung überspringt Zeichenketten (auch Vorlagen mit `${…}`) und
Kommentare: Eine geschweifte Klammer in einem Text oder Kommentar brächte sonst
die Zählung durcheinander, und ein Skript, das zufällig aufging, belegte nichts.
Reguläre Ausdrücke in Literalform werden nicht gesondert behandelt — ihre
Klammern (`{4}`) sind paarig und stören die Zählung nicht.

Eingebunden von `abzug_pruefen.py`, `leser_pruefen.py`, `schulwochen_pruefen.py`
und `tresor_pruefen.py`; je Fassung liegt es daneben. Nur Standardbibliothek.
"""

import re
from pathlib import Path


def skript(html) -> str:
    """Der Inhalt des einen `<script>`-Blocks der Ansicht — aus dem Pfad oder dem Text."""
    text = html.read_text(encoding="utf-8") if isinstance(html, Path) else html
    treffer = re.search(r"<script>(.*?)</script>", text, re.S)
    if not treffer:
        raise SystemExit("Kein Skriptblock in der HTML gefunden.")
    return treffer.group(1)


def _ueberspringen(text: str, i: int) -> int | None:
    """Steht bei `i` eine Zeichenkette oder ein Kommentar, die Stelle ihres
    letzten Zeichens — sonst None."""
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
