#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: GPL-3.0-or-later
"""Die Vorlagen der Materialliste gegen `jsc` (E183, v71).

Die App liest die `inhalte.js` von 3ducation.org mit einem eigenen Leser der
Literal-Teilmenge — ohne ein Skript auszuführen (E175). Ob der Leser dasselbe
sieht wie eine JavaScript-Maschine, beweist dieses Skript zusammen mit der
Prüfsuite `MaterialkatalogPruefungen`:

    ./katalog_pruefen.py                 prüft jede Vorlage Pruefungen/Vorlagen/*.js
                                         gegen ihr erwartetes JSON (*.erwartet.json):
                                         Prüfsumme der Vorlage, Inhalt aus jsc
    ./katalog_pruefen.py --erzeugen      schreibt die erwarteten JSONs neu aus jsc —
                                         nach jeder neuen oder geänderten Vorlage;
                                         danach gehört ein neuer Prüflauf dazu

Das erwartete JSON trägt die Prüfsumme der Vorlage, den Stempel und die Zahlen
(Kategorien, Kacheln); die Sollzahlen des Prüfwerks stammen von hier, nie aus
dem Code — die Kachelzahl der Website steigt (Nutzer, 17.09.2026). Die Swift-
Prüfung vergleicht den Leser Feld für Feld gegen `daten`; der Rundentreiber
legt Vorlage und JSON in die Saat und hält den Prüfstand `--materialtest`
dagegen.

`jsc` liegt bei jedem macOS im JavaScriptCore-Framework; es wertet die Datei aus
und druckt `KATEGORIEN` als JSON. Das Skript selbst führt keinen Code der
Vorlage aus — jsc tut es, in einem eigenen Prozess, nur hier im Prüfwerk.
"""
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime

HIER = os.path.dirname(os.path.abspath(__file__))
VORLAGEN = os.path.join(HIER, "Pruefungen", "Vorlagen")
JSC = "/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc"
# Das Skript für jsc: Die Vorlage wird ausgewertet, ihr `KATEGORIEN` gedruckt.
JSC_SKRIPT = 'print(JSON.stringify(eval(readFile(arguments[0]) + "\\n;KATEGORIEN")));'


def sha256(pfad):
    with open(pfad, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def mitJsc(pfad):
    """`KATEGORIEN` der Vorlage, wie jsc sie sieht."""
    if not os.path.exists(JSC):
        sys.exit(f"jsc fehlt: {JSC}")
    r = subprocess.run([JSC, "-e", JSC_SKRIPT, "--", pfad], capture_output=True, text=True, timeout=60)
    if r.returncode or not r.stdout.strip():
        sys.exit(f"jsc scheiterte an {os.path.basename(pfad)}:\n{r.stdout}{r.stderr}")
    return json.loads(r.stdout)


def zahlen(daten):
    kategorien = len(daten)
    kacheln = sum(len(k.get("kacheln", [])) for k in daten if isinstance(k, dict))
    return kategorien, kacheln


def vorlagen():
    return sorted(p for p in os.listdir(VORLAGEN) if p.endswith(".js"))


def erwartetPfad(name):
    return os.path.join(VORLAGEN, name[:-3] + ".erwartet.json")


def erzeugen():
    for name in vorlagen():
        pfad = os.path.join(VORLAGEN, name)
        daten = mitJsc(pfad)
        kategorien, kacheln = zahlen(daten)
        inhalt = {
            "vorlage": name,
            "sha256": sha256(pfad),
            "erzeugt": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "kategorien": kategorien,
            "kacheln": kacheln,
            "daten": daten,
        }
        with open(erwartetPfad(name), "w", encoding="utf-8") as f:
            json.dump(inhalt, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(f"  {name}: {kategorien} Kategorien, {kacheln} Kacheln → {os.path.basename(erwartetPfad(name))}")
    print("Erwartete JSONs erzeugt — jetzt gehört ein neuer Prüflauf dazu.")


def pruefen():
    alle = True
    namen = vorlagen()
    if not namen:
        sys.exit("Keine Vorlage unter Pruefungen/Vorlagen/")
    for name in namen:
        pfad = os.path.join(VORLAGEN, name)
        befunde = []
        if not os.path.exists(erwartetPfad(name)):
            befunde.append("kein erwartetes JSON — ./katalog_pruefen.py --erzeugen")
            erwartet = None
        else:
            with open(erwartetPfad(name), encoding="utf-8") as f:
                erwartet = json.load(f)
            if erwartet.get("sha256") != sha256(pfad):
                befunde.append("die Vorlage hat sich seit dem Erzeugen geändert (Prüfsumme)")
        if erwartet is not None:
            daten = mitJsc(pfad)
            if daten != erwartet.get("daten"):
                befunde.append("jsc sieht die Vorlage anders als das erwartete JSON")
            kategorien, kacheln = zahlen(daten)
            if (kategorien, kacheln) != (erwartet.get("kategorien"), erwartet.get("kacheln")):
                befunde.append("die Zahlen im JSON passen nicht zu seinen Daten")
        else:
            kategorien = kacheln = 0
        gut = not befunde
        alle = alle and gut
        print(f"  {'✓' if gut else '✗'} {name}: {kategorien} Kategorien, {kacheln} Kacheln"
              + ("" if gut else " — " + "; ".join(befunde)))
    print(f"katalog_pruefen: {len(namen)} Vorlagen {'stimmig' if alle else 'MIT BEFUND'}")
    return alle


if __name__ == "__main__":
    argumente = sys.argv[1:]
    if argumente == ["--erzeugen"]:
        erzeugen()
    elif not argumente:
        sys.exit(0 if pruefen() else 1)
    else:
        sys.exit(__doc__)
