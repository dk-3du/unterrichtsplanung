#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Gleicht den Dateileser der Ansicht (`planungPruefen`) gegen den der App ab
(macOS-App: Modell/Planungsdatei.swift, Prüfungen: DateiPruefungen.swift, dort
„Die Grenzen des Lesers gelten wie in der Ansichtsfassung“ — dieselben Fälle).

Beide Fassungen lesen dieselbe Datei. Eine Obergrenze, ein Ersatzwert oder eine
Wertumdeutung, die nur eine Seite kennt, lässt dieselbe Planung auf Mac und
iPad Verschiedenes bedeuten — der schwerste Fehler, den ein Zwillingsleser
machen kann. Die Funktionen werden per Klammerzählung aus
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

import pruefhilfen

HIER = Path(__file__).resolve().parent
HTML = HIER / "unterrichtsplanung-ansicht.html"
JSC = Path("/System/Library/Frameworks/JavaScriptCore.framework"
           "/Versions/A/Helpers/jsc")

GELUNGEN = "Alle Faelle deckungsgleich mit dem Dateileser der App."

LANGER_PFAD = "p" * (1024 + 200)
LANGER_NAME = "n" * (500 + 100)
LANGER_TEXT = "t" * (20000 + 5000)

GRUND = {"typ": "unterrichtsplanung", "version": 2, "start": "2026-08-10", "wochen": 4}

# Zeichen, an denen zwei Leser leicht auseinanderlaufen.
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

    ("Der alte Feldname basisordner wird nicht mehr gelesen",
     mit(basis="", basisordner=LANGER_PFAD, klassen=[], eintraege=[]),
     {"basis": "", "uebergangen": ""}),

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

    ("Der alte Feldname beschreibung wird nicht mehr gelesen",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T",
                     "text": "", "beschreibung": LANGER_TEXT}]),
     {"textLaenge": 0, "uebergangen": ""}),

    # Typ und Fassung werden geprüft, nicht geraten — Planungsdatei.pruefenMitBilanz.
    ("Ohne typ ist es keine Planung",
     {"version": 2, "klassen": [], "eintraege": []},
     {"fehler": "keine Unterrichtsplanung"}),
    ("Ein fremder typ wird benannt",
     mit(typ="fremd", klassen=[], eintraege=[]),
     {"fehler": "anderen Anwendung"}),
    ("Ohne Fassung: nicht mehr unterstuetzt",
     {"typ": "unterrichtsplanung", "klassen": [], "eintraege": []},
     {"fehler": "nicht mehr unterstützten Fassung"}),
    ("Fassung 1: nicht mehr unterstuetzt",
     mit(version=1, klassen=[], eintraege=[]),
     {"fehler": "nicht mehr unterstützten Fassung"}),
    ("Fassung als Zeichenkette: keine Fassung",
     mit(version="2", klassen=[], eintraege=[]),
     {"fehler": "nicht mehr unterstützten Fassung"}),
    ("Fassung 3: neuer als diese Ansicht",
     mit(version=3, klassen=[], eintraege=[]),
     {"fehler": "neueren Fassung (3)"}),
    ("Zahlen nur als Zahlen: Wochen als Zeichenkette fallen auf den Standard",
     mit(wochen="6", klassen=[{"id": "k1", "name": "5a", "unterrichtstage": ["3", 3]}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": "1", "titel": "T"}]),
     {"wochen": 52, "tageEins": [3], "eintraege": 0, "uebergangen": "Übergangen: 1 Vorhaben."}),

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

    ("Kennungen werden ohne Zeilenumbrueche gestutzt — der Umbruch macht sie ungueltig",
     mit(klassen=[{"id": "k1\n", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T"},
                    {"id": "e2", "klasseId": "k1\n", "woche": 0, "titel": "U"}]),
     # Nur der Verweis, der die ersetzte Kennung wortgleich nennt, folgt ihr.
     {"klassenIdErsetzt": True, "eintraege": 1, "verweiseZeilen": [0],
      "uebergangen": "\u00dcbergangen: 1 Vorhaben, 1 ersetzte Kennung."}),

    # Ein Verweis folgt einer ersetzten Kennung — genannt, wie die Datei sie bei
    # der Zeile nannte; eine doppelte bleibt bei der ersten Zeile —
    # DateiPruefungen.verweiseBeiderFassungen.
    ("Verweise folgen einer ersetzten Kennung, eine doppelte bleibt bei der ersten Zeile",
     mit(klassen=[{"id": "k 1", "name": "5a"}, {"id": "k2", "name": "5b"},
                  {"id": "k2", "name": "5c"}, {"id": " k4", "name": "5d"}],
         zellenfrei=[{"klasseId": "k 1", "woche": "2026-08-10"},
                     {"klasseId": "k2", "woche": "2026-08-10"}],
         sperrzeiten=[{"id": "s1", "name": "S", "von": "2026-08-17", "bis": "2026-08-18",
                       "kurse": ["k 1", "k2", " k4", "k 1"]}],
         eintraege=[{"id": "e1", "klasseId": "k 1", "woche": 0, "titel": "A"},
                    {"id": "e2", "klasseId": "k2", "woche": 0, "titel": "B"},
                    {"id": "e3", "klasseId": " k4", "woche": 0, "titel": "C"},
                    {"id": "e4", "klasseId": "k4", "woche": 0, "titel": "D"}]),
     {"klassen": 4, "eintraege": 4, "zellenfrei": 2, "verweiseZeilen": [0, 1, 3, 3],
      "zellenZeilen": [0, 1], "sperreKurse": [0, 1, 3],
      "uebergangen": "Übergangen: 2 ersetzte Kennungen."}),

    # Kennungen sind Struktur, Texte ohne Steuerzeichen, ein Nicht-Objekt in
    # klassen ist keine Zeile, NFC-gleiche Fachfarben-Schluessel sind einer —
    # DateiPruefungen.formatstrengeBeiderFassungen.
    ("Kennungen, Steuerzeichen und Nicht-Objekte wie in der App",
     mit(titel="Ti\u0000tel\u202e",
         fachfarben={"\u00e9": "blau-mittel", "e\u0301": "rot-hell"},
         ferien=[{"id": "f1", "name": "Herbst", "von": "2026-10-05", "bis": "2026-10-16"},
                 {"id": "f1", "name": "Weihnachten", "von": "2026-12-21", "bis": "2027-01-01"}],
         sperrzeiten=[{"id": "s1", "name": "A", "von": "2026-09-01", "bis": "2026-09-02"},
                      {"id": "s1", "name": "B", "von": "2026-09-03", "bis": "2026-09-04"},
                      {"id": "", "name": "C", "von": "2026-09-07", "bis": "2026-09-08"}],
         klassen=[{"id": "K_1.a:b", "name": "5a", "fach": "\u00e9"}, "kaputt",
                  {"id": "x" * 65, "name": "5b"}, {"id": "k 3", "name": "5c"},
                  {"id": "-k4", "name": "5d"}],
         eintraege=[{"id": "e1", "klasseId": "K_1.a:b", "woche": 0, "titel": "T",
                     "kommentar": "links\u2066rechts\u2069"}]),
     {"titel": "Titel", "kommentarEins": "linksrechts", "ferien": 2, "ferienEinsId": "f1",
      "ferienZweiErsetzt": True, "sperren": 3, "sperrenEindeutig": True, "klassen": 4,
      "klassenId": "K_1.a:b", "klassenRestErsetzt": True, "fachfarben": 1,
      "fachfarbeE": "rot-hell", "farbeEinsRot": True,
      "uebergangen": "Übergangen: 1 Zeile, 2 bereinigte Texte, 6 ersetzte Kennungen."}),

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

    # Was keinen Tag Montag bis Freitag nennt, faellt still weg,
    # Dubletten fallen zusammen — DateiPruefungen.unterrichtstageBeiderFassungen.
    ("Unterrichtstage werden nachsichtig gelesen",
     mit(klassen=[{"id": "k1", "name": "5a",
                   "unterrichtstage": [5, "3", 3, 0, 6, 1.9, True, "x", None, -1, 1]},
                  {"id": "k2", "name": "5b", "unterrichtstage": "Mo"},
                  {"id": "k3", "name": "5c"}],
         eintraege=[]),
     {"tageEins": [1, 3, 5], "tageZwei": [], "tageDrei": [], "uebergangen": ""}),

    # Aus dem Abzugvergleich (abzug_pruefen.py): JSONSerialization verschluckt
    # das fuehrende U+FEFF jeder Zeichenkette — in Wahrheitswerten und
    # Schluesseln; bei zwei danach gleichen Schluesseln gilt der erste. Zahlen
    # nimmt keiner der Leser aus Zeichenketten.
    # DateiPruefungen.vorspannBeiderFassungen.
    ("U+FEFF in Wahrheitswerten und Schluesseln — Zahlen nur als Zahlen",
     mit(version=2, wochen=6,
         fachfarben={BOM + "mathe": "blau-mittel", "mathe": "rot-hell"},
         klassen=[{"id": "k1", "name": "5a", "fach": "Mathe", "farbe": 9,
                   "farbeManuell": BOM, "unterrichtstage": [3, BOM + "4"]}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 1, "titel": "T",
                     "erledigt": BOM, "dringend": BOM + "x",
                     "hausaufgabe": BOM, "hausaufgabenText": BOM + "S. 42"},
                    {"id": "e2", "klasseId": "k1", "woche": BOM + "1", "titel": "Zahl als Zeichenkette"}]),
     {"wochen": 6, "farbeEins": 9, "manuellEins": False, "tageEins": [3],
      "eintraege": 1, "wocheEins": 1, "erledigtEins": False, "dringendEins": True,
      "hausaufgabeEins": False, "hausaufgabenTextEins": "S. 42",
      "fachfarbeMathe": "blau-mittel", "uebergangen": "Übergangen: 1 Vorhaben."}),

    # Hausaufgabe (v47): Schalter und Zeile — HausaufgabenPruefungen.swift.
    ("Hausaufgabe: Schalter und Zeile werden gelesen",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T",
                     "hausaufgabe": True, "hausaufgabenText": "S. 42, Nr. 3–5"}]),
     {"hausaufgabeEins": True, "hausaufgabenTextEins": "S. 42, Nr. 3–5", "uebergangen": ""}),
    ("Die Hausaufgabenzeile misst an MAX_NAMENSLAENGE",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T",
                     "hausaufgabe": True, "hausaufgabenText": LANGER_NAME}]),
     {"hausaufgabenTextLaenge": 500, "uebergangen": "Übergangen: 1 gekürzter Text."}),
    ("Der Schalter gilt wie jeder Wahrheitswert: 0 ist aus, eine Zeichenkette an",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T", "hausaufgabe": 0},
                    {"id": "e2", "klasseId": "k1", "woche": 0, "titel": "T", "hausaufgabe": "x"}]),
     {"hausaufgabeEins": False, "hausaufgabeZwei": True, "uebergangen": ""}),
    ("Eine Zeile ohne Schalter bleibt beim Lesen stehen — die App schreibt sie so nie",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T",
                     "hausaufgabe": False, "hausaufgabenText": "Heft"}]),
     {"hausaufgabeEins": False, "hausaufgabenTextEins": "Heft", "uebergangen": ""}),

    # Gemerkt wird ein Wert, der nach dem Stutzen nicht leer ist, nicht Kennung
    # einer früheren Zeile ist und noch keiner Zeile gehört — die leere Kennung
    # wird nie Verweis, ein Duplikat mit Leerraum zieht seine Verweise nach.
    # DateiPruefungen.verweisregelBeiderFassungen.
    ("Die leere Kennung wird kein Verweis, ein Duplikat mit Leerraum zieht seine Verweise nach",
     mit(klassen=[{"id": "k1", "name": "5a"}, {"id": " k1", "name": "5b"}, {"id": "", "name": "5c"},
                  {"name": "5d"}, {"id": 7, "name": "5e"}],
         zellenfrei=[{"klasseId": "", "woche": "2026-08-10"},
                     {"klasseId": " k1", "woche": "2026-08-10"}],
         sperrzeiten=[{"id": "s1", "name": "S", "von": "2026-08-17", "bis": "2026-08-18",
                       "kurse": ["", " k1", "k1"]}],
         eintraege=[{"id": "e1", "klasseId": " k1", "woche": 0, "titel": "A"},
                    {"id": "e2", "klasseId": "k1", "woche": 0, "titel": "B"},
                    {"id": "e3", "klasseId": "", "woche": 0, "titel": "C"},
                    {"id": "e4", "woche": 0, "titel": "D"},
                    {"id": "e5", "klasseId": 7, "woche": 0, "titel": "E"}]),
     {"klassen": 5, "eintraege": 2, "verweiseZeilen": [1, 0], "zellenfrei": 1, "zellenZeilen": [1],
      "sperreKurse": [0, 1],
      "uebergangen": "Übergangen: 3 Vorhaben, 1 freie Zelle, 4 ersetzte Kennungen."}),

    # Texte sind Zeichenketten: Zahl und Wahrheitswert im Textfeld gelten als
    # leer — DateiPruefungen.texteBeiderFassungen.
    ("Zahl und Wahrheitswert im Textfeld gelten als leer",
     mit(titel=1e16, klassen=[{"id": "k1", "name": True, "fach": 1.5, "notiz": 12345678901234567890}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": 1e-7, "text": 7,
                     "kommentar": False, "statusGeaendert": 0}]),
     {"titel": "Unterrichtsplanung", "klassenname": "Klasse/Kurs 1", "fach": "", "notizEins": "",
      "eintraege": 1, "titelEins": "", "textLaenge": 0, "kommentarEins": "", "statusEins": "",
      "uebergangen": ""}),

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
    "klassenIdErsetzt": "p.klassen[0].id !== 'k1\\n' && kennungGueltig(p.klassen[0].id)",
    "klassenRestErsetzt": "p.klassen.slice(1).every((k) => kennungGueltig(k.id) && k.id !== 'k 3')",
    "klassen": "p.klassen.length",
    "kommentarEins": "p.eintraege[0].kommentar",
    "titelEins": "p.eintraege[0].titel",
    "statusEins": "p.eintraege[0].statusGeaendert",
    "notizEins": "p.klassen[0].notiz",
    "ferien": "p.ferien.length",
    "ferienEinsId": "p.ferien[0].id",
    "ferienZweiErsetzt": "p.ferien[1].id !== 'f1' && kennungGueltig(p.ferien[1].id)",
    "sperren": "p.sperrzeiten.length",
    "sperrenEindeutig": "new Set(p.sperrzeiten.map((s) => s.id)).size === p.sperrzeiten.length",
    "fachfarbeE": "p.fachfarben['\\u00e9']",
    "farbeEinsRot": "p.klassen[0].farbe === farbstelle('rot-hell')",
    "eintraege": "p.eintraege.length",
    "verweiseZeilen": "p.eintraege.map((e) => p.klassen.findIndex((k) => k.id === e.klasseId))",
    "zellenZeilen": "p.zellenfrei.map((z) => p.klassen.findIndex((k) => k.id === z.klasseId))",
    "sperreKurse": "p.sperrzeiten[0].kurse.map((id) => p.klassen.findIndex((k) => k.id === id))",
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
    "hausaufgabeEins": "p.eintraege[0].hausaufgabe",
    "hausaufgabeZwei": "p.eintraege[1].hausaufgabe",
    "hausaufgabenTextEins": "p.eintraege[0].hausaufgabenText",
    "hausaufgabenTextLaenge": "p.eintraege[0].hausaufgabenText.length",
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


# Die Fassung der Statusdatei: dieselben Faelle wie „Die Fassung wird geprüft“
# in DateiPruefungen.swift — 1 gilt, fehlend und alles andere nicht. Eine
# andere Fassung ist „fremd“ (nicht überschreiben), alles Übrige „fehler“.
STATUSFAELLE = [
    ("Fassung 1", '{"version":1,"eintraege":{}}', "gelesen"),
    ("Fassung 1.0", '{"version":1.0,"eintraege":{}}', "gelesen"),
    ("ohne Fassung", '{"eintraege":{}}', "fehler"),
    ("Fassung 0", '{"version":0,"eintraege":{}}', "fremd"),
    ("Fassung 2", '{"version":2,"eintraege":{}}', "fremd"),
    ("Fassung 9999", '{"version":9999,"eintraege":{}}', "fremd"),
    ("Fassung als Zeichenkette", '{"version":"1","eintraege":{}}', "fremd"),
    ("Fassung als Wahrheitswert", '{"version":true,"eintraege":{}}', "fremd"),
    ("Fassung null", '{"version":null,"eintraege":{}}', "fremd"),
    ("Fassung 1.5", '{"version":1.5,"eintraege":{}}', "fremd"),
    ("Fassung 1e100", '{"version":1e100,"eintraege":{}}', "fremd"),
    ("kein Statusstand", '{"x":1}', "fehler"),
    ("andere Anwendung", '{"typ":"x","version":1,"eintraege":{}}', "fehler"),
    ("kein JSON", 'kein JSON', "fehler"),
    ("leer", '', "null"),
]

# Die Schranke vor dem Lesen (`statusstandOeffnen`): dieselbe Regel wie
# `Statusabgleich.entsiegeln` der App (DienstePruefungen.swift) — bei
# verschluesselter Planung nur ein Behaelter unter demselben Schluessel, ohne
# Schluessel nur Klartext. Der Behaelter wird hier nur der Form nach geprueft;
# das Entsiegeln selbst prueft tresor_pruefen.py. Je Fall: Text, Tresor da?
KLARTEXT = '{"typ":"unterrichtsplanung-status","version":1,"eintraege":{}}'
def behaelter(inhalt="status", kennung="00" * 16):
    return json.dumps({"typ": "unterrichtsplanung-tresor", "version": 1, "inhalt": inhalt,
                       "schluesselkennung": kennung, "verfahren": "AES-256-GCM",
                       "nonce": "AAAAAAAAAAAAAAAA", "wicklungen": [], "daten": "AAAAAAAAAAAAAAAAAAAAAA=="})
OEFFNENFAELLE = [
    ("Klartext ohne Schluessel", KLARTEXT, False, "gelesen"),
    ("Klartext bei verschluesselter Planung", KLARTEXT, True, "fehler"),
    ("Behaelter unter demselben Schluessel", behaelter(), True, "gelesen"),
    ("Behaelter ohne Schluessel", behaelter(), False, "fehler"),
    ("Behaelter unter anderem Schluessel", behaelter(kennung="11" * 16), True, "fehler"),
    ("Behaelter mit Inhalt planung", behaelter(inhalt="planung"), True, "fehler"),
    ("Planungsdatei statt Status", '{"typ":"unterrichtsplanung","version":2,"eintraege":[]}', False, "fehler"),
    ("kein JSON", 'kein JSON', True, "fehler"),
    ("leer ohne Schluessel", '', False, "null"),
    ("leer mit Schluessel", '', True, "null"),
    ("andere Fassung ohne Schluessel", '{"version":2,"eintraege":{}}', False, "fremd"),
]


def statusFaelleLaufen(skript: str, deklarationen: str) -> int:
    """Laesst `statusstandLesen` der Ansicht ueber STATUSFAELLE laufen; Zahl der Abweichungen."""
    konstante = re.search(r"^const STATUS_VERSION = (\d+);", skript, re.M)
    if not konstante:
        print("  STATUS_VERSION nicht gefunden.")
        return 1
    statustyp = re.search(r"^const STATUS_TYP = \"[^\"]+\";", skript, re.M)
    if not statustyp:
        print("  STATUS_TYP nicht gefunden.")
        return 1
    probe = deklarationen + "\n" + konstante.group(0) + "\n" + statustyp.group(0) + "\n"
    for name in ("statusstandLesen", "statusstandDeuten", "statusFassungGilt", "istBehaelter",
                 "statusstandOeffnen"):
        probe += pruefhilfen.funktion(skript, name) + "\n"
    # Der Behaelter wird hier nur der Form nach geprueft: Kopf ohne Base64,
    # Entsiegeln liefert einen gueltigen Klartext-Status.
    probe += f"""
const KLARTEXT = {json.dumps(KLARTEXT)};
function kopfLesen(zerlegt) {{
  return {{ inhalt: textwert(zerlegt.inhalt), kennung: textwert(zerlegt.schluesselkennung) }};
}}
async function behaelterOeffnen(kopf, tresor) {{ return KLARTEXT; }}
const zustand = {{ tresor: null }};
function einordnen(fehler) {{
  if (fehler instanceof Statusfremd) return "fremd";
  return fehler instanceof Planungsfehler ? "fehler" : "Ausnahme: " + String(fehler);
}}
const STATUSFAELLE = {json.dumps([[n, t] for n, t, _e in STATUSFAELLE], ensure_ascii=False)};
const OEFFNENFAELLE = {json.dumps([[n, t, s] for n, t, s, _e in OEFFNENFAELLE], ensure_ascii=False)};
const ausgabe = [];
for (const [name, text] of STATUSFAELLE) {{
  let ergebnis;
  try {{
    ergebnis = statusstandLesen(text) === null ? "null" : "gelesen";
  }} catch (fehler) {{
    ergebnis = einordnen(fehler);
  }}
  ausgabe.push([name, ergebnis]);
}}
(async () => {{
  for (const [name, text, mitTresor] of OEFFNENFAELLE) {{
    zustand.tresor = mitTresor ? {{ kennung: "{"00" * 16}" }} : null;
    let ergebnis;
    try {{
      ergebnis = (await statusstandOeffnen(text)) === null ? "null" : "gelesen";
    }} catch (fehler) {{
      ergebnis = einordnen(fehler);
    }}
    ausgabe.push(["oeffnen: " + name, ergebnis]);
  }}
  print(JSON.stringify(ausgabe));
}})();
"""
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        pfad = Path(datei.name)
    try:
        lauf = subprocess.run([str(JSC), str(pfad)], capture_output=True, text=True)
    finally:
        pfad.unlink(missing_ok=True)
    if lauf.returncode != 0:
        print("jsc meldet einen Fehler (Statusleser):")
        print((lauf.stdout + lauf.stderr)[-2000:])
        return 1
    ergebnisse = dict(json.loads(lauf.stdout))
    fehler = 0
    alle = [(n, e) for n, _t, e in STATUSFAELLE] + [("oeffnen: " + n, e) for n, _t, _s, e in OEFFNENFAELLE]
    for name, erwartet in alle:
        ist = ergebnisse.get(name, "kein Ergebnis")
        if ist != erwartet:
            fehler += 1
            print(f"  ABWEICHUNG Statusdatei, {name}: erwartet {erwartet!r}, Ansicht {ist!r}")
        else:
            print(f"  stimmt    Statusdatei, {name}")
    return fehler


# Das Merken im Browser (`statusMerken`/`inSpeicherSchreiben`): Gemerkt heißt
# gespeichert. Ein gescheitertes `setItem` gilt nicht als erledigt und wird
# beim naechsten Ruf nachgeholt — ohne ein zweites Versiegeln, und ohne einen
# zweiten Schreibvorgang, wenn der Stand schon liegt (1.4.3). Attrappen fuer
# Speicher, Versiegeln und Meldung; `jsc` traegt die Promises aus.
MERKFAELLE = [
    ("Klartext: Fehlschlag, dann nachgeholt ohne Aenderung",
     {"versuche": 2, "gespeichert": 1, "gespeichertMarke": 1, "warnungen": 1}),
    ("Klartext: kein zweites Schreiben ohne Aenderung", {"versuche": 2}),
    ("Klartext: neue Marke schreibt genau einmal", {"versuche": 3, "gespeichertMarke": 2}),
    ("Verschluesselt: Chiffrat bereit, Schreiben nachgeholt ohne neues Versiegeln",
     {"versiegelt": 1, "versuche": 5, "statusChiffratMarke": 3, "gespeichertMarke": 3, "warnungen": 2}),
    ("Verschluesselt: ohne Aenderung weder versiegelt noch geschrieben", {"versiegelt": 1, "versuche": 5}),
    ("Warnung nach jedem Erfolg wieder scharf", {"warnungen": 3, "merkenVerwehrt": True}),
    ("Fremder Stand im Speicher: nichts geschrieben, nichts gemerkt", {"versuche": 6, "gespeichertMarke": 3}),
]


def merkFaelleLaufen(skript: str) -> int:
    """Laesst `statusMerken` der Ansicht gegen Speicher-Attrappen laufen; Zahl der Abweichungen."""
    probe = pruefhilfen.funktion(skript, "statusMerken") + "\n" \
        + pruefhilfen.funktion(skript, "inSpeicherSchreiben") + "\n" + """
let warnungen = 0, versuche = 0, versiegelt = 0, scheitern = false;
const speicher = {};
function melden(text, warnung) { if (warnung) warnungen += 1; }
function statusSchluessel(p) { return "status:" + p.titel; }
function statusAlsText() { return JSON.stringify({ marke: zustand.statusMarke }); }
async function behaelterVersiegeln(text, inhalt, tresor) { versiegelt += 1; return "chiffrat:" + text; }
const window = { localStorage: { setItem(k, v) {
  versuche += 1;
  if (scheitern) throw new Error("QuotaExceededError");
  speicher[k] = v;
} } };
const zustand = { planung: { titel: "P" }, tresor: null, statusMarke: 1, statusChiffrat: "",
                  statusChiffratMarke: -1, gespeichertMarke: -1, merkLauf: 0,
                  merkenVerwehrt: false, speicherFremd: false };
async function abwarten() { for (let i = 0; i < 6; i += 1) await null; }
function stand() {
  return { versuche, versiegelt, warnungen, gespeichert: Object.keys(speicher).length,
           gespeichertMarke: zustand.gespeichertMarke, statusChiffratMarke: zustand.statusChiffratMarke,
           merkenVerwehrt: zustand.merkenVerwehrt };
}
const ausgabe = [];
(async () => {
  scheitern = true; statusMerken(); await abwarten();
  scheitern = false; statusMerken(); await abwarten();
  ausgabe.push(["Klartext: Fehlschlag, dann nachgeholt ohne Aenderung", stand()]);
  statusMerken(); await abwarten();
  ausgabe.push(["Klartext: kein zweites Schreiben ohne Aenderung", stand()]);
  zustand.statusMarke = 2; statusMerken(); statusMerken(); await abwarten();
  ausgabe.push(["Klartext: neue Marke schreibt genau einmal", stand()]);
  zustand.tresor = { kennung: "k" }; zustand.statusMarke = 3;
  scheitern = true; statusMerken(); await abwarten();
  scheitern = false; statusMerken(); await abwarten();
  ausgabe.push(["Verschluesselt: Chiffrat bereit, Schreiben nachgeholt ohne neues Versiegeln", stand()]);
  statusMerken(); statusMerken(); await abwarten();
  ausgabe.push(["Verschluesselt: ohne Aenderung weder versiegelt noch geschrieben", stand()]);
  zustand.statusMarke = 4; scheitern = true; statusMerken(); await abwarten();
  ausgabe.push(["Warnung nach jedem Erfolg wieder scharf", stand()]);
  zustand.speicherFremd = true; scheitern = false; zustand.statusMarke = 3; statusMerken(); await abwarten();
  ausgabe.push(["Fremder Stand im Speicher: nichts geschrieben, nichts gemerkt", stand()]);
  print(JSON.stringify(ausgabe));
})();
"""
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        pfad = Path(datei.name)
    try:
        lauf = subprocess.run([str(JSC), str(pfad)], capture_output=True, text=True)
    finally:
        pfad.unlink(missing_ok=True)
    if lauf.returncode != 0:
        print("jsc meldet einen Fehler (Merken):")
        print((lauf.stdout + lauf.stderr)[-2000:])
        return 1
    ergebnisse = dict(json.loads(lauf.stdout))
    fehler = 0
    for name, erwartet in MERKFAELLE:
        ist = ergebnisse.get(name, {})
        abweichend = [f"{feld}: erwartet {soll!r}, Ansicht {ist.get(feld)!r}"
                      for feld, soll in erwartet.items() if ist.get(feld) != soll]
        if abweichend:
            fehler += 1
            print(f"  ABWEICHUNG Merken, {name}: " + "; ".join(abweichend))
        else:
            print(f"  stimmt    Merken, {name}")
    return fehler


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
    rumpf = pruefhilfen.skript(HTML)

    # Von den Farbtafeln bis zum Leser: alles dazwischen sind Deklarationen.
    teil = pruefhilfen.abschnitt(rumpf, "const GRUNDFARBEN", "planungPruefen")

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
        if "fehler" in erwartet:
            # Erwartet ist die Ablehnung — mit dem Satz der App darin.
            abweichend = ([] if erwartet["fehler"] in str(ist.get("fehler", ""))
                          else [f"fehler: erwartet {erwartet['fehler']!r}, gelesen {ist.get('fehler')!r}"])
        else:
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

    fehler += statusFaelleLaufen(rumpf, teil)
    fehler += merkFaelleLaufen(rumpf)

    if fehler:
        print(f"\n{fehler} von {len(FAELLE) + len(STATUSFAELLE) + len(OEFFNENFAELLE) + len(MERKFAELLE)} Faellen "
              "weichen vom Leser der App ab.")
        return 1
    print(f"\n{GELUNGEN} ({len(FAELLE)} Faelle, dazu {len(STATUSFAELLE)} zur Fassung der Statusdatei, "
          f"{len(OEFFNENFAELLE)} zur Schranke vor dem Lesen und {len(MERKFAELLE)} zum Merken im Browser)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
