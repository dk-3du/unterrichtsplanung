#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Gleicht den Dateileser der Ansicht (`planungPruefen`) gegen den der App ab
(macOS-App: Modell/Planungsdatei.swift, Prüfungen: DateiPruefungen.swift, dort
„Die Grenzen des Lesers gelten wie in der Ansichtsfassung“ — dieselben Fälle).

Beide Fassungen lesen dieselbe Datei. Eine Obergrenze, ein Ersatzwert oder eine
Wertumdeutung, die nur eine Seite kennt, lässt dieselbe Planung auf Mac und
iPad Verschiedenes bedeuten — in den beiden letzten Nachprüfungen war genau
das der schwerste Befund. Die Funktionen werden per Klammerzählung aus
`unterrichtsplanung-ansicht.html` gezogen und mit `jsc` (JavaScriptCore, ohne
Node) laufen gelassen.

**Neue gemeinsame Regel = neuer Fall hier UND in DateiPruefungen.swift.**

**Was hier NICHT geht: Weblinks.** `jsc` ist die reine Sprachmaschine und kennt
kein `URL`; `linkPruefen` liefe dort in seinen Fangblock und wiese jede Adresse
ab — ein Linkfall waere hier gruen und sagte nichts. Solche Faelle gehoeren an
den echten Browser und nach `ModellPruefungen.swift` („Was der URL-Leser der
Browser abweist, weist auch die App ab“). Die Schranke unten haelt das fest.

Aufruf:  python3 leser_pruefen.py        (Ergebnis je Fall, Exit 0/1)
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HIER = Path(__file__).resolve().parent
HTML = HIER / "unterrichtsplanung-ansicht.html"
JSC = Path("/System/Library/Frameworks/JavaScriptCore.framework"
           "/Versions/A/Helpers/jsc")

GELUNGEN = "Alle Faelle deckungsgleich mit dem Dateileser der App."

LANGER_PFAD = "p" * (1024 + 200)
LANGER_NAME = "n" * (500 + 100)
LANGER_TEXT = "t" * (20000 + 5000)

GRUND = {"typ": "unterrichtsplanung", "version": 2, "start": "2026-08-10", "wochen": 4}

# Zeichen, an denen die beiden Fassungen bis 0.22 auseinanderliefen.
BOM = "\ufeff"      # verschluckt `JSONSerialization`, `JSON.parse` nicht
NEL = "\u0085"      # stutzt `CharacterSet.newlines`, `String.trim()` nicht


def mit(**felder):
    return {**GRUND, **felder}


# (Name, Rohdaten, erwartete Werte). Die Namen der Werte stehen unten in
# `ABFRAGEN`; jeder ist ein Ausdruck über die gelesene Planung.
FAELLE = [
    ("Pfade messen an MAX_PFADLAENGE",
     mit(basis=LANGER_PFAD,
         klassen=[{"id": "k1", "name": "5a", "verwaltung": LANGER_PFAD}], eintraege=[]),
     {"basisLaenge": 1024, "verwaltungLaenge": 1024,
      "uebergangen": "Übergangen: 2 gekürzte Texte."}),

    ("Ungebrauchter Rueckfall zaehlt sein Kuerzen nicht mit",
     mit(basis="/kurz", basisordner=LANGER_PFAD, klassen=[], eintraege=[]),
     {"basis": "/kurz", "uebergangen": ""}),

    ("Gebrauchter Rueckfall kuerzt und zaehlt einmal",
     mit(basis="", basisordner=LANGER_PFAD, klassen=[], eintraege=[]),
     {"basisLaenge": 1024, "uebergangen": "Übergangen: 1 gekürzter Text."}),

    ("Namen messen an MAX_NAMENSLAENGE",
     mit(titel=LANGER_NAME, klassen=[{"id": "k1", "name": LANGER_NAME, "fach": LANGER_NAME}],
         eintraege=[]),
     {"titelLaenge": 500, "klassennameLaenge": 500, "fachLaenge": 500,
      "uebergangen": "Übergangen: 3 gekürzte Texte."}),

    ("Fachfarben ueber der Grenze fallen sortiert weg",
     mit(fachfarben={f"fach{i}": "blau-mittel" for i in range(500 + 100)},
         klassen=[], eintraege=[]),
     {"fachfarben": 500, "fachNullDa": True,
      "uebergangen": "Übergangen: 100 Fachfarben."}),

    ("Texte und Kommentare messen an MAX_TEXTLAENGE",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T",
                     "text": LANGER_TEXT, "kommentar": LANGER_TEXT}]),
     {"textLaenge": 20000, "kommentarLaenge": 20000,
      "uebergangen": "Übergangen: 2 gekürzte Texte."}),

    ("Beschreibung ist der Rueckfall des Textes",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T",
                     "text": "", "beschreibung": LANGER_TEXT}]),
     {"textLaenge": 20000, "uebergangen": "Übergangen: 1 gekürzter Text."}),

    ("Steht der Text, bleibt die Beschreibung ungelesen",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T",
                     "text": "kurz", "beschreibung": LANGER_TEXT}]),
     {"textLaenge": 4, "uebergangen": ""}),

    ("Freie Tage und Zellen sind Mengen",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         frei=["2026-08-10", "2026-08-10", "krumm"],
         zellenfrei=[{"klasseId": "k1", "woche": "2026-08-10"} for _ in range(10)],
         eintraege=[]),
     {"frei": 1, "zellenfrei": 1, "uebergangen": "Übergangen: 1 freier Tag."}),

    ("Ende vor Beginn wird nicht gedreht",
     mit(klassen=[], eintraege=[],
         ferien=[{"id": "f1", "name": "F", "von": "2026-08-28", "bis": "2026-08-24"}],
         sperrzeiten=[{"id": "s1", "name": "S", "von": "2026-09-04", "bis": "2026-09-01"}]),
     {"ferienVon": "2026-08-28", "ferienBis": "2026-08-24",
      "sperreVon": "2026-09-04", "sperreBis": "2026-09-01"}),

    ("Ein fuehrendes U+FEFF verschluckt der Leser wie JSONSerialization",
     mit(titel=BOM + "Titel",
         klassen=[{"id": "k1", "name": BOM + "5a", "fach": BOM + "Mathe"}],
         eintraege=[]),
     {"titel": "Titel", "klassenname": "5a", "fach": "Mathe", "uebergangen": ""}),

    ("Nur das erste U+FEFF, und nur am Anfang",
     mit(titel="a" + BOM + "b", klassen=[], eintraege=[]),
     {"titel": "a" + BOM + "b"}),

    ("Kennungen werden ohne Zeilenumbrueche gestutzt",
     mit(klassen=[{"id": "k1\n", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T"}]),
     {"klassenId": "k1\n", "eintraege": 0,
      "uebergangen": "\u00dcbergangen: 1 Vorhaben."}),

    ("Leerzeichen und Tabulator fallen an der Kennung weg",
     mit(klassen=[{"id": "\tk1 ", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T"}]),
     {"klassenId": "k1", "eintraege": 1, "uebergangen": ""}),

    ("Der Fachschluessel stutzt U+0085, aber kein U+FEFF",
     mit(klassen=[{"id": "k1", "name": "5a", "fach": NEL + "Mathe"},
                  {"id": "k2", "name": "5b", "fach": "Mathe"},
                  {"id": "k3", "name": "5c", "fach": "Mathe" + BOM}],
         eintraege=[], fachfarben={"mathe": "blau-mittel"}),
     {"farbeEins": 5, "farbeZwei": 5, "farbeDreiAnders": True}),

    # Seit 0.24: Was keinen Tag Montag bis Freitag nennt, faellt still weg,
    # Dubletten fallen zusammen — DateiPruefungen.unterrichtstageBeiderFassungen.
    ("Unterrichtstage werden nachsichtig gelesen",
     mit(klassen=[{"id": "k1", "name": "5a",
                   "unterrichtstage": [5, "3", 3, 0, 6, 1.9, True, "x", None, -1]},
                  {"id": "k2", "name": "5b", "unterrichtstage": "Mo"},
                  {"id": "k3", "name": "5c"}],
         eintraege=[]),
     {"tageEins": [1, 3, 5], "tageZwei": [], "tageDrei": [], "uebergangen": ""}),

    # Abzugvergleich 02.09.2026 (abzug_pruefen.py, 1 500 Faelle, 136 Abweichungen
    # mit EINER Ursache): JSONSerialization verschluckt das fuehrende U+FEFF
    # jeder Zeichenkette — auch vor Zahlen, in Wahrheitswerten und Schluesseln;
    # bei zwei danach gleichen Schluesseln gilt der erste.
    # DateiPruefungen.vorspannBeiderFassungen.
    ("U+FEFF vor Zahlen, Wahrheitswerten und Schluesseln",
     mit(version=BOM + "2", wochen=BOM + "6",
         fachfarben={BOM + "mathe": "blau-mittel", "mathe": "rot-hell"},
         klassen=[{"id": "k1", "name": "5a", "fach": "Mathe", "farbe": 9,
                   "farbeManuell": BOM, "unterrichtstage": [BOM + "3"]}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": BOM + "1", "titel": "T",
                     "erledigt": BOM, "dringend": BOM + "x"}]),
     {"wochen": 6, "farbeEins": 9, "manuellEins": False, "tageEins": [3],
      "eintraege": 1, "wocheEins": 1, "erledigtEins": False, "dringendEins": True,
      "fachfarbeMathe": "blau-mittel", "uebergangen": ""}),

    ("Leere Bezeichnungen bekommen den Ersatz der App",
     mit(klassen=[{"id": "k1", "name": "", "fach": ""}], eintraege=[],
         ferien=[{"id": "f1", "name": "", "von": "2026-08-10", "bis": "2026-08-14"}],
         sperrzeiten=[{"id": "s1", "name": "", "von": "2026-08-17", "bis": "2026-08-18"}]),
     {"titel": "Unterrichtsplanung", "klassenname": "Klasse/Kurs 1",
      "ferienname": "Ferien", "sperrenname": "Sperrzeitraum", "uebergangen": ""}),
]

# Ausdruck je Wert, ausgewertet in JS über die gelesene Planung `p`.
ABFRAGEN = {
    "basis": "p.basis",
    "basisLaenge": "p.basis.length",
    "titel": "p.titel",
    "titelLaenge": "p.titel.length",
    "klassenname": "p.klassen[0].name",
    "klassennameLaenge": "p.klassen[0].name.length",
    "fach": "p.klassen[0].fach",
    "fachLaenge": "p.klassen[0].fach.length",
    "klassenId": "p.klassen[0].id",
    "eintraege": "p.eintraege.length",
    "farbeEins": "p.klassen[0].farbe",
    "farbeZwei": "p.klassen[1].farbe",
    "farbeDreiAnders": "p.klassen[2].farbe !== p.klassen[1].farbe",
    "verwaltungLaenge": "p.klassen[0].verwaltung.length",
    "fachfarben": "Object.keys(p.fachfarben).length",
    "fachNullDa": "p.fachfarben.fach0 === 'blau-mittel'",
    "textLaenge": "p.eintraege[0].text.length",
    "kommentarLaenge": "p.eintraege[0].kommentar.length",
    "frei": "p.frei.length",
    "zellenfrei": "p.zellenfrei.length",
    "ferienVon": "p.ferien[0].von",
    "ferienBis": "p.ferien[0].bis",
    "sperreVon": "p.sperrzeiten[0].von",
    "sperreBis": "p.sperrzeiten[0].bis",
    "ferienname": "p.ferien[0].name",
    "tageEins": "p.klassen[0].unterrichtstage",
    "wochen": "p.wochen",
    "manuellEins": "p.klassen[0].farbeManuell",
    "wocheEins": "p.eintraege[0].woche",
    "erledigtEins": "p.eintraege[0].erledigt",
    "dringendEins": "p.eintraege[0].dringend",
    "fachfarbeMathe": "p.fachfarben.mathe",
    "tageZwei": "p.klassen[1].unterrichtstage",
    "tageDrei": "p.klassen[2].unterrichtstage",
    "sperrenname": "p.sperrzeiten[0].name",
    # Wortgleich zur Meldung der App (`Planungsspeicher` fügt sie an den
    # Öffnen-Hinweis an): dieselben Posten, dieselbe Reihenfolge, dieselben
    # Ein- und Mehrzahlformen.
    "uebergangen": "p.uebergangen",
}

# `length` zählt UTF-16-Einheiten, beide Fassungen kappen aber nach Zeichen
# (`aufLaenge` teilt mit `Intl.Segmenter`, Swift zählt `Character`). Für die
# Fälle hier ist das dasselbe (nur ASCII); neue Fälle mit Emoji oder
# zusammengesetzten Zeichen über die Zeichenzahl prüfen, nicht über `length`.


def block(quelle: str, anfangsmarke: str, endmarke: str) -> str:
    a = quelle.index(anfangsmarke)
    b = quelle.index(endmarke)
    tiefe = 0
    start = quelle.index("{", b)
    for stelle in range(start, len(quelle)):
        if quelle[stelle] == "{":
            tiefe += 1
        elif quelle[stelle] == "}":
            tiefe -= 1
            if tiefe == 0:
                return quelle[a:stelle + 1]
    raise SystemExit("Klammern unausgeglichen — endet planungPruefen nicht?")


def linkfallGefunden() -> str:
    """Traegt ein Fall Weblinks? Siehe die Warnung im Kopf dieser Datei."""
    for name, roh, _erwartet in FAELLE:
        for eintrag in roh.get("eintraege", []):
            if eintrag.get("links"):
                return name
    return ""


def main() -> int:
    stolperstein = linkfallGefunden()
    if stolperstein:
        print(f"Fall \u201e{stolperstein}\u201c traegt Weblinks. `jsc` kennt kein "
              "`URL`; `linkPruefen` wiese dort jede Adresse ab, und der Fall "
              "waere gruen, ohne etwas zu belegen. Linkfaelle gehoeren nach "
              "ModellPruefungen.swift und an den Browser.")
        return 1
    if not JSC.exists():
        print(f"jsc nicht gefunden: {JSC}")
        return 1
    if not HTML.exists():
        print(f"Ansichtsfassung nicht gefunden: {HTML}")
        return 1
    skript = re.search(r"<script>(.*?)</script>", HTML.read_text(encoding="utf-8"), re.S)
    if not skript:
        print("Kein Skriptblock in der HTML gefunden.")
        return 1

    # Von den Farbtafeln bis zum Leser: alles dazwischen sind Deklarationen.
    teil = block(skript.group(1), "const GRUNDFARBEN", "function planungPruefen(")

    faelle = [[name, roh, erwartet] for name, roh, erwartet in FAELLE]
    probe = teil + f"""
const FAELLE = {json.dumps(faelle, ensure_ascii=False)};
const ABFRAGEN = {json.dumps(ABFRAGEN, ensure_ascii=False)};
const ausgabe = [];
for (const [name, roh, erwartet] of FAELLE) {{
  const werte = {{}};
  try {{
    const p = planungPruefen(roh);
    for (const feld of Object.keys(erwartet)) {{
      const ausdruck = ABFRAGEN[feld];
      if (!ausdruck) {{ werte[feld] = "unbekannter Wert " + feld; continue; }}
      werte[feld] = Function("p", "return (" + ausdruck + ");")(p);
    }}
  }} catch (fehler) {{
    werte.fehler = String((fehler && fehler.nachricht) || fehler);
  }}
  ausgabe.push([name, werte]);
}}
print(JSON.stringify(ausgabe));
"""
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        pfad = Path(datei.name)
    try:
        lauf = subprocess.run([str(JSC), str(pfad)], capture_output=True, text=True)
    finally:
        pfad.unlink(missing_ok=True)
    if lauf.returncode != 0:
        print("jsc meldet einen Fehler:")
        print((lauf.stdout + lauf.stderr)[-2000:])
        return 1

    ergebnisse = dict(json.loads(lauf.stdout))
    fehler = 0
    for name, _roh, erwartet in FAELLE:
        ist = ergebnisse.get(name, {"fehler": "kein Ergebnis"})
        abweichend = [f"{feld}: erwartet {soll!r}, gelesen {ist.get(feld)!r}"
                      for feld, soll in erwartet.items() if ist.get(feld) != soll]
        if "fehler" in ist:
            abweichend.append("Ausnahme: " + str(ist["fehler"]))
        if abweichend:
            fehler += 1
            print(f"  ABWEICHUNG {name}")
            for zeile in abweichend:
                print(f"              {zeile}")
        else:
            print(f"  stimmt    {name}")

    if fehler:
        print(f"\n{fehler} von {len(FAELLE)} Faellen weichen vom Dateileser der App ab.")
        return 1
    print(f"\n{GELUNGEN} ({len(FAELLE)} Faelle)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
