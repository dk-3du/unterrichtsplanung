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

Dazu die Grenzfälle (`Pruefungen/Vorlagen/literale-grenzfaelle.json`): je Fall
ein Literal und die Erwartung an den Leser — `gleich` (er nimmt es an und liest
dasselbe wie jsc) oder `abgewiesen` (er wirft). Was JavaScript anders läse als
der Leser — Oktal-Escapes, Zahlen mit führender Null, `__proto__` —, gehört zu
den Abgewiesenen: annehmen heißt dasselbe lesen. `--erzeugen` schreibt den Wert
aus jsc je Fall daneben (`literale-grenzfaelle.erwartet.json`); die Swift-Prüfung
hält den Leser dagegen.

Dazu die Datei-Grenzfälle (`Pruefungen/Vorlagen/datei-grenzfaelle.json`, seit
v73): je Fall eine ganze kleine Datei, wie die Website sie lädt — Deklaration,
Kommentare, Zeilenenden. jsc wertet jeden Fall in einem eigenen Prozess aus wie
die Vorlagen (Datei, dann `;KATEGORIEN`), damit kein Fall den nächsten sieht;
die Swift-Prüfung hält `Materialkatalog.literal(…, deklaration: true)` dagegen,
den Weg jeder geladenen Liste.

Eine Vorlage wird gelesen, bevor `--erzeugen` sie auswertet: jsc führt aus, was
in ihr steht. Kein Werkzeug lädt eine Datei und wertet sie in einem Zug aus.

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
import tempfile
from datetime import datetime

HIER = os.path.dirname(os.path.abspath(__file__))
VORLAGEN = os.path.join(HIER, "Pruefungen", "Vorlagen")
JSC = "/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc"
# Das Skript für jsc: Die Vorlage wird ausgewertet, ihr `KATEGORIEN` gedruckt.
JSC_SKRIPT = 'print(JSON.stringify(eval(readFile(arguments[0]) + "\\n;KATEGORIEN")));'
# Die Grenzfälle: jedes Literal für sich, in Klammern, nicht-strikt wie eine
# gewöhnliche Skriptdatei. Ein Fehler, `undefined`, nicht-endliche Zahlen und
# ein einzelnes Ersatzzeichen werden benannt — JSON kennte sie nicht oder ließe
# sich danach nicht mehr lesen.
GRENZFAELLE = "literale-grenzfaelle.json"
DATEIFAELLE = "datei-grenzfaelle.json"
JSC_GRENZFAELLE = """
var faelle = JSON.parse(readFile(arguments[0])).faelle;
var werten = eval;
print(JSON.stringify(faelle.map(function (fall) {
  try {
    var wert = werten("(" + fall.quelle + "\\n)");
    if (wert === undefined) return {undefiniert: true};
    if (typeof wert === "number" && !isFinite(wert)) return {nichtEndlich: true};
    if (typeof wert === "string" && !wert.isWellFormed()) return {einzelnesErsatzzeichen: true};
    if (typeof wert === "function" || typeof wert === "bigint" || wert instanceof RegExp || wert instanceof Date)
      return {keinLiteral: true};
    return {wert: wert};
  } catch (fehler) {
    return {fehler: fehler.name};
  }
})));
"""
# Ein Datei-Grenzfall: die Datei, dann `;KATEGORIEN` — dieselben Benennungen
# wie bei den Literalen.
JSC_DATEIFALL = """
var werten = eval;
var ergebnis;
try {
  var wert = werten(readFile(arguments[0]) + "\\n;KATEGORIEN");
  if (wert === undefined) ergebnis = {undefiniert: true};
  else if (typeof wert === "number" && !isFinite(wert)) ergebnis = {nichtEndlich: true};
  else if (typeof wert === "string" && !wert.isWellFormed()) ergebnis = {einzelnesErsatzzeichen: true};
  else if (typeof wert === "function" || typeof wert === "bigint" || wert instanceof RegExp || wert instanceof Date)
    ergebnis = {keinLiteral: true};
  else ergebnis = {wert: wert};
} catch (fehler) {
  ergebnis = {fehler: fehler.name};
}
print(JSON.stringify(ergebnis));
"""


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


def grenzfaellePfad(sammlung=GRENZFAELLE):
    return os.path.join(VORLAGEN, sammlung)


def grenzfaelleErwartetPfad(sammlung=GRENZFAELLE):
    return os.path.join(VORLAGEN, sammlung[:-5] + ".erwartet.json")


def grenzfaelleMitJsc(sammlung=GRENZFAELLE):
    """Je Fall, was jsc daraus macht — die Literale in einem Lauf, jede Datei
    in einem eigenen."""
    if not os.path.exists(JSC):
        sys.exit(f"jsc fehlt: {JSC}")
    if sammlung == DATEIFAELLE:
        return [dateifallMitJsc(fall) for fall in grenzfaelleLesen(sammlung)]
    r = subprocess.run([JSC, "-e", JSC_GRENZFAELLE, "--", grenzfaellePfad(sammlung)],
                       capture_output=True, text=True, timeout=60)
    if r.returncode or not r.stdout.strip():
        sys.exit(f"jsc scheiterte an {sammlung}:\n{r.stdout}{r.stderr}")
    return json.loads(r.stdout)


def dateifallMitJsc(fall):
    with tempfile.TemporaryDirectory() as ordner:
        pfad = os.path.join(ordner, "inhalte.js")
        with open(pfad, "w", encoding="utf-8", newline="") as f:
            f.write(fall["quelle"])
        r = subprocess.run([JSC, "-e", JSC_DATEIFALL, "--", pfad], capture_output=True, text=True, timeout=60)
    if r.returncode or not r.stdout.strip():
        sys.exit(f"jsc scheiterte am Datei-Grenzfall „{fall.get('name')}“:\n{r.stdout}{r.stderr}")
    return json.loads(r.stdout)


def grenzfaelleLesen(sammlung=GRENZFAELLE):
    with open(grenzfaellePfad(sammlung), encoding="utf-8") as f:
        return json.load(f)["faelle"]


def grenzfaelleBefunde(faelle, ergebnisse):
    """Was an der Vorlage selbst nicht stimmt: Ein Fall, den der Leser gleich
    lesen soll, muss für jsc ein Wert sein."""
    befunde = []
    if len(faelle) != len(ergebnisse):
        return ["jsc lieferte nicht je Fall ein Ergebnis"]
    for fall, ergebnis in zip(faelle, ergebnisse):
        if fall.get("leser") not in ("gleich", "abgewiesen"):
            befunde.append(f"„{fall.get('name')}“: leser ist weder gleich noch abgewiesen")
        if fall.get("leser") == "gleich" and "wert" not in ergebnis:
            befunde.append(f"„{fall.get('name')}“ soll gleich gelesen werden, jsc liefert aber {ergebnis}")
    return befunde


def grenzfaelleErzeugen(sammlung=GRENZFAELLE):
    faelle = grenzfaelleLesen(sammlung)
    ergebnisse = grenzfaelleMitJsc(sammlung)
    befunde = grenzfaelleBefunde(faelle, ergebnisse)
    if befunde:
        sys.exit(f"{sammlung} mit Befund:\n  " + "\n  ".join(befunde))
    inhalt = {
        "vorlage": sammlung,
        "sha256": sha256(grenzfaellePfad(sammlung)),
        "erzeugt": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "faelle": [dict(fall, jsc=ergebnis) for fall, ergebnis in zip(faelle, ergebnisse)],
    }
    with open(grenzfaelleErwartetPfad(sammlung), "w", encoding="utf-8") as f:
        json.dump(inhalt, f, ensure_ascii=True, indent=1)
        f.write("\n")
    gleich = sum(1 for fall in faelle if fall["leser"] == "gleich")
    print(f"  {sammlung}: {len(faelle)} Fälle ({gleich} gleich, {len(faelle) - gleich} abgewiesen)"
          f" → {os.path.basename(grenzfaelleErwartetPfad(sammlung))}")


def grenzfaellePruefen(sammlung=GRENZFAELLE):
    befunde = []
    faelle = []
    if not os.path.exists(grenzfaellePfad(sammlung)):
        befunde.append("die Grenzfälle fehlen")
    elif not os.path.exists(grenzfaelleErwartetPfad(sammlung)):
        befunde.append("kein erwartetes JSON — ./katalog_pruefen.py --erzeugen")
    else:
        faelle = grenzfaelleLesen(sammlung)
        with open(grenzfaelleErwartetPfad(sammlung), encoding="utf-8") as f:
            erwartet = json.load(f)
        if erwartet.get("sha256") != sha256(grenzfaellePfad(sammlung)):
            befunde.append("die Grenzfälle haben sich seit dem Erzeugen geändert (Prüfsumme)")
        ergebnisse = grenzfaelleMitJsc(sammlung)
        befunde += grenzfaelleBefunde(faelle, ergebnisse)
        if [dict(fall, jsc=ergebnis) for fall, ergebnis in zip(faelle, ergebnisse)] != erwartet.get("faelle"):
            befunde.append("jsc sieht die Grenzfälle anders als das erwartete JSON")
    gut = not befunde
    print(f"  {'✓' if gut else '✗'} {sammlung}: {len(faelle)} Fälle"
          + ("" if gut else " — " + "; ".join(befunde)))
    return gut


def erzeugen():
    grenzfaelleErzeugen(GRENZFAELLE)
    grenzfaelleErzeugen(DATEIFAELLE)
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
    alle = grenzfaellePruefen(GRENZFAELLE) and alle
    alle = grenzfaellePruefen(DATEIFAELLE) and alle
    print(f"katalog_pruefen: {len(namen)} Vorlagen und beide Grenzfall-Sammlungen {'stimmig' if alle else 'MIT BEFUND'}")
    return alle


if __name__ == "__main__":
    argumente = sys.argv[1:]
    if argumente == ["--erzeugen"]:
        erzeugen()
    elif not argumente:
        sys.exit(0 if pruefen() else 1)
    else:
        sys.exit(__doc__)
