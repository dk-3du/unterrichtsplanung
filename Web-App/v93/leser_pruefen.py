#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Gleicht den Dateileser der Web App (`planungPruefen`) gegen den der App ab
(macOS-App: Modell/Planungsdatei.swift, Prüfungen: DateiPruefungen.swift, dort
„Die Grenzen des Lesers gelten wie in der Web App“ — dieselben Fälle).

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
    ("Fassung 3: neuer als diese Web App",
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

    # Korrektur: gelesen wie die Dringlichkeit, aber nie neben einer Prüfung —
    # trägt eine Datei beides, gilt die Prüfung. KorrekturmerkmalPruefungen.swift.
    ("Korrektur: fehlt = falsch, Fremdwerte wie bei dringend, neben der Prüfung fällt sie",
     mit(version=2, wochen=6,
         klassen=[{"id": "k1", "name": "8b", "fach": "Chemie", "farbe": 1}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 1, "titel": "Arbeit korrigieren", "korrektur": True},
                    {"id": "e2", "klasseId": "k1", "woche": 1, "titel": "Arbeit", "pruefung": True,
                     "pruefungstag": "2026-08-19", "korrektur": True},
                    {"id": "e3", "klasseId": "k1", "woche": 2, "titel": "von früher"},
                    {"id": "e4", "klasseId": "k1", "woche": 2, "titel": "Fremdwert", "korrektur": "ja",
                     "datum": "2026-08-20", "dringend": True}]),
     {"eintraege": 4, "korrekturEins": True, "korrekturZwei": False, "pruefungZwei": True,
      "korrekturDrei": False, "korrekturVier": True, "dringendVier": True, "uebergangen": ""}),

    # Vorbereitung (v93, E1074, E1075): gelesen wie die Korrektur; Prüfung und Korrektur gehen vor — am Rohwert.
    # Neben einem Termin bleibt sie (E1080: beide Leser gleich; die Web App übergeht den Termin).
    # VorbereitungsmerkmalPruefungen.swift.
    ("Vorbereitung: fehlt = falsch, Fremdwerte wie bei dringend, neben Prüfung oder Korrektur fällt sie",
     mit(version=2, wochen=6,
         klassen=[{"id": "k1", "name": "8b", "fach": "Chemie", "farbe": 1}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 1, "titel": "Arbeit vorbereiten", "vorbereitung": True,
                     "termin": "m-1"},
                    {"id": "e2", "klasseId": "k1", "woche": 1, "titel": "Arbeit", "pruefung": True,
                     "pruefungstag": "2026-08-19", "vorbereitung": True},
                    {"id": "e3", "klasseId": "k1", "woche": 2, "titel": "Korrigieren", "korrektur": True,
                     "vorbereitung": True},
                    {"id": "e4", "klasseId": "k1", "woche": 2, "titel": "Fremdwert", "vorbereitung": "ja",
                     "datum": "2026-08-20", "dringend": True},
                    {"id": "e5", "klasseId": "k1", "woche": 3, "titel": "von früher"}]),
     {"eintraege": 5, "vorbereitungEins": True, "vorbereitungZwei": False, "pruefungZwei": True,
      "vorbereitungDrei": False, "korrekturDrei": True, "vorbereitungVier": True, "dringendVier": True,
      "vorbereitungFuenf": False, "uebergangen": ""}),

    # Unbekannte Angaben an Vorhaben (v93, E1079): je Vorhaben einmal gezählt; der Altname beschreibung und Angaben
    # oben in der Datei zählen nicht. UnbekannteAngabenPruefungen.swift.
    ("Unbekannte Angaben: je Vorhaben gezählt, der Altname beschreibung und Angaben oben nicht",
     mit(version=2, wochen=6, zukunft=1,
         klassen=[{"id": "k1", "name": "8b", "fach": "Chemie", "farbe": 1}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 1, "titel": "a", "zukunft": 1},
                    {"id": "e2", "klasseId": "k1", "woche": 1, "titel": "b", "zukunft": True, "farbe": "rot"},
                    {"id": "e3", "klasseId": "k1", "woche": 2, "titel": "c", "beschreibung": "alt"},
                    {"id": "e4", "klasseId": "k1", "woche": 2, "titel": "d", "vorbereitung": True,
                     "termin": "m-1", "terminzeit": "07:45"},
                    {"id": "e5", "klasseId": "fehlt", "woche": 2, "titel": "e", "zukunft": 1}]),
     {"eintraege": 4, "unbekannt": 2, "uebergangen": "Übergangen: 1 Vorhaben.",
      "unbekanntSatz": "Die Datei enthält Angaben einer neueren Fassung, die diese Fassung nicht kennt (2 Vorhaben)."}),

    # Eine Datei aus 2.7.0 meldet nichts (Z-BE4-R03): alle 21 bekannten Angaben an einem Vorhaben.
    ("Unbekannte Angaben: eine Datei aus 2.7.0 mit allen bekannten Angaben meldet nichts",
     mit(version=2, wochen=6,
         klassen=[{"id": "k1", "name": "8b", "fach": "Chemie", "farbe": 1}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 1, "titel": "a", "text": "", "erledigt": False,
                     "materialien": [], "links": [], "pruefung": False, "pruefungstag": "", "datum": "2026-08-18",
                     "dringend": True, "korrektur": False, "vorbereitung": True, "kommentar": "",
                     "statusGeaendert": "", "hausaufgabe": False, "hausaufgabenText": "", "termin": "m-1",
                     "terminzeit": "07:45", "beschreibung": "alt"}]),
     {"eintraege": 1, "unbekannt": 0, "uebergangen": ""}),

    # Termin am Vorhaben (v80, E293): ein Feld nur der App (TerminabgleichPruefungen.swift)
    # — die Web App übergeht es und meldet keinen Verlust.
    ("Termin am Vorhaben: die Web App übergeht termin und terminzeit ohne Verlust",
     mit(klassen=[{"id": "k1", "name": "Weiteres", "art": "weiteres"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "Elterngespräch",
                     "datum": "2026-08-13", "termin": "m-abc", "terminzeit": "07:45"}]),
     {"eintraege": 1, "titelEins": "Elterngespräch", "uebergangen": ""}),

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

    # Sonderzeilen (v69, E157): die Art aus `art` — fehlend oder unbekannt heißt
    # Unterricht —, der Titel einer Sonderzeile ist fest, Sonderzeilen stehen
    # stets unter den Klassen/Kursen in fester Folge; Fach und Notiz bleiben
    # frei, Verweise wandern mit. DateiPruefungen.sonderzeilenBeiderFassungen.
    ("Sonderzeilen: Art, fester Titel und Ordnung wie in der App",
     mit(klassen=[{"id": "k1", "name": "Vertretungen", "art": "vertretungen", "fach": "7a"},
                  {"id": "k2", "name": "5a"},
                  {"id": "k3", "name": "irgendwas", "art": "klassenleitung", "fach": "7a"},
                  {"id": "k4", "name": "5b", "art": "sonstiges"},
                  {"id": "k5", "name": "5c", "art": 7},
                  {"id": "k6", "name": "", "art": "weiteres", "notiz": "AG-Leitung"}],
         eintraege=[{"id": "v1", "klasseId": "k3", "woche": 0, "titel": "Elternabend"}]),
     {"klassenIds": "k2,k4,k5,k3,k6,k1",
      "klassenArten": "unterricht,unterricht,unterricht,klassenleitung,weiteres,vertretungen",
      "klassenNamen": "5a,5b,5c,Klassenleitung,Weiteres,Vertretungen",
      "fachVier": "7a", "fachSechs": "", "notizFuenf": "AG-Leitung", "verweisEins": "k3", "uebergangen": ""}),

    # E823 (v86, R2-B1N): Ein fuehrendes U+FEFF vor der Art verschluckt der Leser wie `JSONSerialization` — wie bei jedem
    # anderen Text; eines am Ende nicht. Gefunden im Abzugvergleich (E818, `abzug_pruefen.py`).
    # Nur eines: Zwei führende U+FEFF lesen beide Seiten als Unterricht (Zwilling DateiSonderzeilenPruefungen.zeilenartMitBOM).
    ("Zeilenart: ein fuehrendes U+FEFF verschluckt der Leser wie JSONSerialization — nur eines",
     mit(klassen=[{"id": "k1", "name": "AG", "art": BOM + "weiteres"},
                  {"id": "k2", "name": "5a"},
                  {"id": "k3", "name": "5b", "art": "vertretungen" + BOM},
                  {"id": "k4", "name": "5c", "art": BOM + BOM + "weiteres"}]),
     {"klassenIds": "k2,k3,k4,k1", "klassenArten": "unterricht,unterricht,unterricht,weiteres",
      "klassenNamen": "5a,5b,5c,Weiteres", "uebergangen": ""}),

    # B34 (v70, E164): Ein Dateiverweis, den die Art nicht vorsieht (Verwaltung an
    # Vertretungen, Curriculum an jeder Sonderzeile), fällt und zählt in der
    # Verlustbilanz — DateiPruefungen.unerlaubteDateiverweiseFallen.
    ("Dateiverweise, die die Art nicht vorsieht, fallen und zählen",
     mit(klassen=[{"id": "k1", "name": "7a", "verwaltung": "a.numbers", "curriculum": "a.pdf"},
                  {"id": "k2", "art": "klassenleitung", "verwaltung": "b.numbers", "curriculum": "b.pdf"},
                  {"id": "k3", "art": "weiteres", "curriculum": "c.pdf"},
                  {"id": "k4", "art": "vertretungen", "verwaltung": "d.numbers", "curriculum": "d.pdf"}]),
     {"verwaltungen": "a.numbers,b.numbers,,", "curricula": "a.pdf,,,",
      "uebergangen": "Übergangen: 4 Dateiverweise."}),
    ("ein einzelner Dateiverweis in der Einzahl",
     mit(klassen=[{"id": "k1", "art": "vertretungen", "verwaltung": "d.numbers"}]),
     {"verwaltungen": "", "uebergangen": "Übergangen: 1 Dateiverweis."}),

    # E662 (v85, AW8a): Die Leistungsdokumentation ist ein Pfad wie Verwaltungsdatei
    # und Curriculum, aber an jeder Zeilenart vorgesehen — gelesen, gemessen an
    # MAX_PFADLAENGE, bereinigt und gezählt wie jeder Text; angezeigt wird sie in der
    # Web App nicht. LeistungsdokumentationPruefungen.lesenWieDieWebApp.
    ("Leistungsdokumentation: der Pfad misst an MAX_PFADLAENGE",
     mit(klassen=[{"id": "k1", "name": "5a", "leistungsdokumentation": LANGER_PFAD}]),
     {"leistungsdokumentationLaenge": 1024, "uebergangen": "Übergangen: 1 gekürzter Text."}),
    ("Leistungsdokumentation: an jeder Zeilenart gelesen, nichts verworfen",
     mit(klassen=[{"id": "k1", "name": "7a", "leistungsdokumentation": "a.numbers"},
                  {"id": "k2", "art": "klassenleitung", "leistungsdokumentation": "b.numbers"},
                  {"id": "k3", "art": "weiteres", "leistungsdokumentation": "c.numbers"},
                  {"id": "k4", "art": "vertretungen", "leistungsdokumentation": "d.numbers"}]),
     {"leistungsdokumentationen": "a.numbers,b.numbers,c.numbers,d.numbers", "uebergangen": ""}),
    ("Leistungsdokumentation: Steuerzeichen fallen und zählen",
     mit(klassen=[{"id": "k1", "name": "5a", "leistungsdokumentation": "Noten" + chr(0x202E) + "5a.numbers"}]),
     {"leistungsdokumentationen": "Noten5a.numbers", "uebergangen": "Übergangen: 1 bereinigter Text."}),
    ("Leistungsdokumentation: nur Text ist ein Pfad",
     mit(klassen=[{"id": "k1", "name": "5a", "leistungsdokumentation": 7},
                  {"id": "k2", "name": "5b", "leistungsdokumentation": True},
                  {"id": "k3", "name": "5c", "leistungsdokumentation": {}}]),
     {"leistungsdokumentationen": ",,", "uebergangen": ""}),

    # B35 (v70, E165): Zwei Sonderzeilen derselben Art bleiben beide — fester
    # Titel, Dateireihenfolge, Vorhaben hängen — DateiPruefungen.doppelteSonderzeilenBleiben.
    ("Zwei Sonderzeilen derselben Art bleiben beide",
     mit(klassen=[{"id": "k1", "name": "KL 7a", "art": "klassenleitung", "fach": "7a"},
                  {"id": "k2", "name": "9c"},
                  {"id": "k3", "name": "KL 9c", "art": "klassenleitung", "fach": "9c"}],
         eintraege=[{"id": "v1", "klasseId": "k1", "woche": 0, "titel": "A"},
                    {"id": "v2", "klasseId": "k3", "woche": 1, "titel": "B"}]),
     {"klassenIds": "k2,k1,k3", "klassenNamen": "9c,Klassenleitung,Klassenleitung",
      "faecher": ",7a,9c", "verweise": "k1,k3", "uebergangen": ""}),

    # B53 (v74, E209): Den Ersatznamen einer leeren Bezeichnung nimmt der Leser
    # bereinigt und gestutzt, wie der Schreiber ihn schreibt — ein Dateiname nur
    # aus Leerraum, einer nur aus U+202E, einer mit Leerraum am Rand.
    # DateiPruefungen.ersatznameWieBeimSchreiben.
    ("Ersatzname bereinigt und gestutzt wie beim Schreiben",
     mit(klassen=[{"id": "k1", "name": "5a"}],
         eintraege=[{"id": "e1", "klasseId": "k1", "woche": 0, "titel": "T",
                     "materialien": [{"titel": "", "pfad": "/tmp/ "},
                                     {"titel": "", "pfad": "/tmp/" + chr(0x202E)},
                                     {"titel": "", "pfad": "/tmp/ blatt.pdf "}]}]),
     {"materialtitelEins": "", "materialtitelZwei": "", "materialtitelDrei": "blatt.pdf",
      "uebergangen": ""}),
]

# Ausdruck je Wert, ausgewertet in JS über die gelesene Planung `p`.
ABFRAGEN = {
    "materialtitelEins": "p.eintraege[0].materialien[0].titel",
    "materialtitelZwei": "p.eintraege[0].materialien[1].titel",
    "materialtitelDrei": "p.eintraege[0].materialien[2].titel",
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
    "klassenIds": "p.klassen.map((k) => k.id).join(',')",
    "klassenArten": "p.klassen.map((k) => k.art).join(',')",
    "klassenNamen": "p.klassen.map((k) => k.name).join(',')",
    "fachVier": "p.klassen[3].fach",
    "fachSechs": "p.klassen[5].fach",
    "notizFuenf": "p.klassen[4].notiz",
    "verweisEins": "p.eintraege[0].klasseId",
    "verweise": "p.eintraege.map((e) => e.klasseId).join(',')",
    "faecher": "p.klassen.map((k) => k.fach).join(',')",
    "verwaltungen": "p.klassen.map((k) => k.verwaltung).join(',')",
    "curricula": "p.klassen.map((k) => k.curriculum).join(',')",
    "leistungsdokumentationen": "p.klassen.map((k) => k.leistungsdokumentation).join(',')",
    "leistungsdokumentationLaenge": "p.klassen[0].leistungsdokumentation.length",
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
    "dringendVier": "p.eintraege[3].dringend",
    "korrekturEins": "p.eintraege[0].korrektur",
    "korrekturZwei": "p.eintraege[1].korrektur",
    "korrekturDrei": "p.eintraege[2].korrektur",
    "korrekturVier": "p.eintraege[3].korrektur",
    "vorbereitungEins": "p.eintraege[0].vorbereitung",
    "vorbereitungZwei": "p.eintraege[1].vorbereitung",
    "vorbereitungDrei": "p.eintraege[2].vorbereitung",
    "vorbereitungVier": "p.eintraege[3].vorbereitung",
    "vorbereitungFuenf": "p.eintraege[4].vorbereitung",
    "pruefungZwei": "p.eintraege[1].pruefung",
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
    "unbekannt": "p.unbekannteAngaben",
    "unbekanntSatz": "(typeof unbekannteAngabenText === 'function' ? unbekannteAngabenText(p.unbekannteAngaben) : '')",
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
    ("Behaelter mit Inhalt sitzplaene", behaelter(inhalt="sitzplaene"), True, "fehler"),
    ("Planungsdatei statt Status", '{"typ":"unterrichtsplanung","version":2,"eintraege":[]}', False, "fehler"),
    ("kein JSON", 'kein JSON', True, "fehler"),
    ("leer ohne Schluessel", '', False, "null"),
    ("leer mit Schluessel", '', True, "null"),
    ("andere Fassung ohne Schluessel", '{"version":2,"eintraege":{}}', False, "fremd"),
]


def statusFaelleLaufen(skript: str, deklarationen: str) -> int:
    """Laesst `statusstandLesen` der Web App ueber STATUSFAELLE laufen; Zahl der Abweichungen."""
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
        lauf = jsc_laufen(pfad)
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
            print(f"  ABWEICHUNG Statusdatei, {name}: erwartet {erwartet!r}, Web App {ist!r}")
        else:
            print(f"  stimmt    Statusdatei, {name}")
    return fehler


# Der Kommentar der Statusdatei (B52, v74, E208): `kommentarKuerzen` der Web App
# wie `Statusdatei.lesen` der App — bereinigen, stutzen, kappen, was das Kappen
# am Ende freilegt, weg. Dieselben Faelle stehen in DateiPruefungen.swift
# („Zwillinge“); dazu je Fall: Zweimal gekuerzt ist einmal gekuerzt.
_A = "a" * (20000 - 1)
KOMMENTARFAELLE = [
    ("Leerzeichen an der Grenze", _A + " b", _A),
    ("Zeilenumbruch an der Grenze", _A + "\nb", _A),
    ("CRLF an der Grenze", _A + "\r\nb", _A),
    ("NEL an der Grenze", _A + chr(0x85) + "b", _A),
    ("U+2028 an der Grenze", _A + chr(0x2028) + "b", _A),
    ("NBSP an der Grenze", _A + chr(0xA0) + "b", _A),
    ("Leerraum innen bleibt", "  a  b  ", "a  b"),
    ("Steuerzeichen und Rand", chr(7) + " x " + chr(0x202E), "x"),
    ("kurz und ohne Rand", "Gut gelaufen.", "Gut gelaufen."),
]


def kommentarFaelleLaufen(skript: str, deklarationen: str) -> int:
    """Laesst die echte `kommentarKuerzen` ueber KOMMENTARFAELLE laufen; Zahl der Abweichungen."""
    grenze = re.search(r"^const STATUS_KOMMENTAR_MAX = [A-Z_]+;", skript, re.M)
    if not grenze:
        print("  STATUS_KOMMENTAR_MAX nicht gefunden.")
        return 1
    probe = deklarationen + "\n" + grenze.group(0) + "\n" + pruefhilfen.funktion(skript, "kommentarKuerzen") + f"""
const FAELLE = {json.dumps([[n, roh] for n, roh, _e in KOMMENTARFAELLE], ensure_ascii=True)};
const ausgabe = [];
for (const [name, roh] of FAELLE) {{
  const einmal = kommentarKuerzen(roh);
  ausgabe.push([name, einmal, kommentarKuerzen(einmal) === einmal]);
}}
print(JSON.stringify(ausgabe));
"""
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        pfad = Path(datei.name)
    try:
        lauf = jsc_laufen(pfad)
    finally:
        pfad.unlink(missing_ok=True)
    if lauf.returncode != 0:
        print("jsc meldet einen Fehler (Kommentar):")
        print((lauf.stdout + lauf.stderr)[-2000:])
        return 1
    ergebnisse = {name: (ist, fest) for name, ist, fest in json.loads(lauf.stdout)}
    fehler = 0
    for name, _roh, erwartet in KOMMENTARFAELLE:
        ist, fest = ergebnisse.get(name, (None, False))
        if ist != erwartet or not fest:
            fehler += 1
            laenge = "—" if ist is None else len(ist)
            print(f"  ABWEICHUNG Kommentar, {name}: erwartet {len(erwartet)} Zeichen, "
                  f"Web App {laenge}{'' if fest else ', beim zweiten Mal anders'}")
        else:
            print(f"  stimmt    Kommentar, {name}")
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
    ("Klartext: Neue Marke schreibt genau einmal", {"versuche": 3, "gespeichertMarke": 2}),
    ("Verschluesselt: Chiffrat bereit, Schreiben nachgeholt ohne neues Versiegeln",
     {"versiegelt": 1, "versuche": 5, "statusChiffratMarke": 3, "gespeichertMarke": 3, "warnungen": 2}),
    ("Verschluesselt: ohne Aenderung weder versiegelt noch geschrieben", {"versiegelt": 1, "versuche": 5}),
    ("Warnung nach jedem Erfolg wieder scharf", {"warnungen": 3, "merkenVerwehrt": True}),
    ("Fremder Stand im Speicher: nichts geschrieben, nichts gemerkt", {"versuche": 6, "gespeichertMarke": 3}),
    # B13: Ein Planungswechsel (statusWiederaufnehmen erhoeht merkLauf) waehrend
    # des Versiegelns — der ueberholte Lauf schreibt nichts unter den neuen Schluessel.
    ("Planungswechsel waehrend des Versiegelns: nichts geschrieben",
     {"versiegelt": 3, "versuche": 6, "gespeichertMarke": 3}),
    ("Ohne Wechsel schreibt der Lauf wie gewohnt", {"versiegelt": 4, "versuche": 7, "gespeichertMarke": 8}),
    # F05: Scheitert das Versiegeln eines ueberholten Laufs, bleibt die neue
    # Planung ohne Warnung und ohne Sperre; der eigene Lauf warnt weiter.
    ("Planungswechsel waehrend des Versiegelns, Versiegeln scheitert: keine Warnung",
     {"versiegelt": 5, "versuche": 7, "warnungen": 3, "merkenVerwehrt": False}),
    ("Versiegeln der eigenen Planung scheitert: Warnung",
     {"versiegelt": 6, "versuche": 7, "warnungen": 4, "merkenVerwehrt": True}),
]


SCHREIBFAELLE = [
    ("Ungestoert: geschrieben und gesichert", {"geschrieben": ["A:text:klar"], "gesichert": 1}),
    # B13: Wechselt die Planung (und mit ihr die Zieldatei), waehrend der Vorgang
    # liest, schreibt er nicht in die neue Datei.
    ("Planungswechsel waehrend des Lesens: nichts in die neue Datei geschrieben",
     {"geschrieben": ["A:text:klar"], "gesichert": 1}),
    # B13: Ein Fehler des ueberholten Vorgangs loest die neue Verbindung nicht.
    ("Fehler nach Neuverbindung: Die neue Verbindung bleibt",
     {"geschrieben": ["A:text:klar"], "verbunden": "D", "schreibtGerade": False}),
    ("Danach schreibt die neue Verbindung", {"geschrieben": ["A:text:klar", "D:text:klar"], "gesichert": 2}),
    # B22: Wechselt die Verbindung, waehrend der Strom schreibt, wird er
    # verworfen (abort), nicht geschlossen — nichts landet in der Datei.
    ("Wechsel waehrend des Schreibens: Strom verworfen, nicht geschlossen",
     {"geschlossen": 2, "abgebrochen": 1, "gesichert": 2, "verbunden": "F", "schreibtGerade": False}),
    ("Danach schreibt die Verbindung F", {"geschrieben": ["A:text:klar", "D:text:klar", "E:text:klar", "F:text:klar"],
                                         "geschlossen": 3, "gesichert": 3}),
]


def schreibFaelleLaufen(skript: str) -> int:
    """Laesst `inDateiSchreiben` gegen Handle-Attrappen laufen (B13); Zahl der Abweichungen."""
    rumpf = pruefhilfen.funktion(skript, "inDateiSchreiben")
    if not rumpf.startswith("async"):
        rumpf = "async " + rumpf
    probe = rumpf + "\n" + """
let geschrieben = [], gesichert = 0, geschlossen = 0, abgebrochen = 0;
function melden() {}
function statusGesichert(nachricht, marke) { gesichert += 1; }
async function eintraegeVereinen(text) { return "vereint"; }
async function statusAlsDatei(vereint, tresor) { return "text:" + (tresor ? tresor.kennung : "klar"); }
class Planungsfehler extends Error {}
const MAX_STATUSGROESSE = 1000;
function handle(name) {
  return { name,
    getFile: async () => ({ size: 10, text: async () => "" }),
    createWritable: async () => ({ write: async (t) => { geschrieben.push(name + ":" + t); },
                                   close: async () => { geschlossen += 1; },
                                   abort: async () => { abgebrochen += 1; } }) };
}
const zustand = { zieldatei: null, zieldateiFuer: "", zieldateiFremdGemeldet: false, schreibtGerade: false,
                  schreibLauf: 0, statusMarke: 1, planung: { erstellt: "a" }, tresor: null };
function stand() {
  return { geschrieben: geschrieben.slice(), gesichert, geschlossen, abgebrochen,
           verbunden: zustand.zieldatei ? zustand.zieldatei.name : null, schreibtGerade: zustand.schreibtGerade };
}
const ausgabe = [];
(async () => {
  zustand.zieldatei = handle("A");
  await inDateiSchreiben(false);
  ausgabe.push(["Ungestoert: geschrieben und gesichert", stand()]);

  const alt = handle("A2");
  alt.getFile = async () => {
    zustand.planung = { erstellt: "b" }; zustand.zieldatei = handle("B");
    return { size: 10, text: async () => "" };
  };
  zustand.zieldatei = alt;
  await inDateiSchreiben(false);
  ausgabe.push(["Planungswechsel waehrend des Lesens: nichts in die neue Datei geschrieben", stand()]);

  const c = handle("C");
  c.createWritable = async () => { zustand.zieldatei = handle("D"); throw new Error("weg"); };
  zustand.zieldatei = c;
  await inDateiSchreiben(false);
  ausgabe.push(["Fehler nach Neuverbindung: Die neue Verbindung bleibt", stand()]);

  await inDateiSchreiben(false);
  ausgabe.push(["Danach schreibt die neue Verbindung", stand()]);

  const e = handle("E");
  e.createWritable = async () => ({
    write: async (t) => { geschrieben.push("E:" + t); zustand.zieldatei = handle("F"); },
    close: async () => { geschlossen += 1; },
    abort: async () => { abgebrochen += 1; } });
  zustand.zieldatei = e;
  await inDateiSchreiben(false);
  ausgabe.push(["Wechsel waehrend des Schreibens: Strom verworfen, nicht geschlossen", stand()]);

  await inDateiSchreiben(false);
  ausgabe.push(["Danach schreibt die Verbindung F", stand()]);
  print(JSON.stringify(ausgabe));
})();
"""
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        pfad = Path(datei.name)
    try:
        lauf = jsc_laufen(pfad)
    finally:
        pfad.unlink(missing_ok=True)
    if lauf.returncode != 0:
        print("jsc meldet einen Fehler (Schreiben):")
        print((lauf.stdout + lauf.stderr)[-2000:])
        return 1
    ergebnisse = dict((name, werte) for name, werte in json.loads(lauf.stdout.strip().splitlines()[-1]))
    fehler = 0
    for name, erwartet in SCHREIBFAELLE:
        ist = ergebnisse.get(name, {})
        abweichend = [f"{feld}: erwartet {soll!r}, gelesen {ist.get(feld)!r}"
                      for feld, soll in erwartet.items() if ist.get(feld) != soll]
        if abweichend:
            fehler += 1
            print(f"  ABWEICHUNG {name}")
            for zeile in abweichend:
                print(f"              {zeile}")
        else:
            print(f"  stimmt    {name}")
    return fehler


# B22: Die Wiederaufnahme aus dem Browserspeicher gehoert der Planung, fuer
# die sie begann — wird waehrend des Wartens eine andere geoeffnet, landet
# nichts von der ersten im Status oder Speicher der zweiten.
WIEDERAUFNAHMEFAELLE = [
    ("Ungestoert: ein Eintrag wieder aufgenommen, gemerkt",
     {"zahl": 1, "status": ["a1"], "offen": True, "gemerkt": 1}),
    ("Wechsel waehrend der Wiederaufnahme: nichts von A in B",
     {"zahlA": 0, "zahlB": 0, "status": [], "offen": False, "gemerkt": 1}),
    # F05: Ein fremder Stand (neuere Fassung), der erst nach dem Wechsel zu B
    # gedeutet wird, sperrt B nicht und warnt B nicht.
    ("Fremder Stand fuer A nach dem Wechsel zu B: B bleibt merkbar, keine Warnung",
     {"zahlA": 0, "zahlB": 0, "speicherFremd": False, "warnungen": 0}),
    ("Fremder Stand der eigenen Planung: gesperrt und gemeldet",
     {"zahl": 0, "speicherFremd": True, "warnungen": 1}),
]


def wiederaufnahmeFaelleLaufen(skript: str) -> int:
    """Laesst `statusWiederaufnehmen` gegen Speicher-Attrappen laufen (B22); Zahl der Abweichungen."""
    rumpf = pruefhilfen.funktion(skript, "statusWiederaufnehmen")
    if not rumpf.startswith("async"):
        rumpf = "async " + rumpf
    probe = rumpf + "\n" + """
let gemerkt = 0, freigabe = null, gespeichertStand = null, fremdStand = false, warnungen = 0;
function statusMerken() { gemerkt += 1; }
function melden(text, warnung) { if (warnung) warnungen += 1; }
function kommentarKuerzen(t) { return typeof t === "string" ? t : ""; }
function textwert(v) { return typeof v === "string" ? v : ""; }
function zeitstempelBrauchbar(s) { return /^\\d{4}-\\d{2}-\\d{2}T/.test(s); }
function wahrheit(v) { return v === true; }
function istObjekt(v) { return v !== null && typeof v === "object" && !Array.isArray(v); }
const GEFAEHRLICHE_SCHLUESSEL = new Set(["__proto__", "constructor", "prototype"]);
async function statusAusSpeicher(planung) {
  await new Promise((r) => { freigabe = r; });
  return { stand: gespeichertStand, fremd: fremdStand, grund: fremdStand ? "fremd" : "" };
}
const zustand = { status: Object.create(null), ausgang: null, statusOffen: false, statusVerworfen: 0,
                  statusVerworfene: [], merkenVerwehrt: false, kennungGemeldet: false, speicherFremd: false,
                  zieldateiFremdGemeldet: false, statusGesichert: null, statusChiffrat: "",
                  statusChiffratMarke: -1, gespeichertMarke: -1, merkLauf: 0, schreibLauf: 0,
                  schreibtGerade: false, planung: null };
function eintrag(id) { return { id, titel: id, erledigt: false, kommentar: "", statusGeaendert: "" }; }
const A = { titel: "A", eintraege: [eintrag("a1")] };
const B = { titel: "B", eintraege: [eintrag("b1")] };
const gespeichertA = { eintraege: { a1: { erledigt: true, kommentar: "k", geaendert: "2026-09-12T10:00:00.000Z" } } };
const ausgabe = [];
(async () => {
  zustand.planung = A;
  const p1 = statusWiederaufnehmen(A);
  gespeichertStand = gespeichertA; freigabe();
  const zahl = await p1;
  ausgabe.push(["Ungestoert: ein Eintrag wieder aufgenommen, gemerkt",
                { zahl, status: Object.keys(zustand.status), offen: zustand.statusOffen, gemerkt }]);

  zustand.planung = A;
  const pA = statusWiederaufnehmen(A);
  const freigabeA = freigabe;
  zustand.planung = B;
  const pB = statusWiederaufnehmen(B);
  const freigabeB = freigabe;
  gespeichertStand = gespeichertA; freigabeA();
  const zahlA = await pA;
  gespeichertStand = null; freigabeB();
  const zahlB = await pB;
  ausgabe.push(["Wechsel waehrend der Wiederaufnahme: nichts von A in B",
                { zahlA, zahlB, status: Object.keys(zustand.status), offen: zustand.statusOffen, gemerkt }]);

  zustand.planung = A;
  const pA2 = statusWiederaufnehmen(A);
  const freigabeA2 = freigabe;
  zustand.planung = B;
  const pB2 = statusWiederaufnehmen(B);
  const freigabeB2 = freigabe;
  gespeichertStand = null; fremdStand = true; freigabeA2();
  const zahlA2 = await pA2;
  fremdStand = false; freigabeB2();
  const zahlB2 = await pB2;
  ausgabe.push(["Fremder Stand fuer A nach dem Wechsel zu B: B bleibt merkbar, keine Warnung",
                { zahlA: zahlA2, zahlB: zahlB2, speicherFremd: zustand.speicherFremd, warnungen }]);

  zustand.planung = B;
  const pB3 = statusWiederaufnehmen(B);
  fremdStand = true; freigabe();
  const zahlB3 = await pB3;
  fremdStand = false;
  ausgabe.push(["Fremder Stand der eigenen Planung: gesperrt und gemeldet",
                { zahl: zahlB3, speicherFremd: zustand.speicherFremd, warnungen }]);
  print(JSON.stringify(ausgabe));
})();
"""
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        pfad = Path(datei.name)
    try:
        lauf = jsc_laufen(pfad)
    finally:
        pfad.unlink(missing_ok=True)
    if lauf.returncode != 0:
        print("jsc meldet einen Fehler (Wiederaufnahme):")
        print((lauf.stdout + lauf.stderr)[-2000:])
        return 1
    ergebnisse = dict((name, werte) for name, werte in json.loads(lauf.stdout.strip().splitlines()[-1]))
    fehler = 0
    for name, erwartet in WIEDERAUFNAHMEFAELLE:
        ist = ergebnisse.get(name, {})
        abweichend = [f"{feld}: erwartet {soll!r}, gelesen {ist.get(feld)!r}"
                      for feld, soll in erwartet.items() if ist.get(feld) != soll]
        if abweichend:
            fehler += 1
            print(f"  ABWEICHUNG Wiederaufnahme, {name}: " + "; ".join(abweichend))
        else:
            print(f"  stimmt    Wiederaufnahme, {name}")
    return fehler


# Öffnen einer Datei (v93, R92-01, E1072, E1081): Zwei Öffnungen dürfen sich überlappen — Ablegen und Dateiwahl rufen
# `dateiLesen` ohne Abstimmung. Eine verschlüsselte Planung kommt nie ohne ihren Schlüssel an; eine Öffnung, die älter
# ist als eine schon übernommene, übernimmt nichts, meldet nichts und fragt nicht mehr nach der Passphrase; eine jüngere,
# die scheitert, entwertet eine ältere nicht. Entsiegelung, Passphrase-Blatt und Lesen sind angehalten und werden von
# Hand freigegeben.
DATEIOEFFNENFAELLE = [
    ("Allein: die verschlüsselte Planung mit ihrem Schlüssel",
     {"uebernommen": ["C:k"], "meldungen": 0, "tresorAmEnde": "k", "rueckfragen": 0}),
    ("Überholt von Klartext: die ältere übernimmt nicht",
     {"uebernommen": ["B:klar"], "meldungen": 0, "tresorAmEnde": "klar"}),
    ("Zwei verschlüsselte, die spätere zuerst fertig: nur die spätere",
     {"uebernommen": ["C2:k"], "meldungen": 0, "tresorAmEnde": "k"}),
    ("Ältere scheitert nach einer jüngeren: keine Meldung",
     {"uebernommen": ["B:klar"], "meldungen": 0, "tresorAmEnde": "klar"}),
    ("Ältere übernimmt während des Entsiegelns: die jüngere kommt mit ihrem Schlüssel",
     {"uebernommen": ["B:klar", "C:k"], "meldungen": 0, "tresorAmEnde": "k"}),
    ("Mit Passphrase: die Planung mit dem neuen Schlüssel",
     {"uebernommen": ["C:m"], "meldungen": 0, "tresorAmEnde": "m", "rueckfragen": 1}),
    ("Jüngere scheitert, ältere danach fertig: die ältere übernimmt",
     {"uebernommen": ["A:k"], "meldungen": 1, "tresorAmEnde": "k"}),
    ("Jüngere am offenen Passphrase-Blatt abgewiesen: die ältere übernimmt danach",
     {"uebernommen": ["A:m"], "meldungen": 1, "tresorAmEnde": "m", "rueckfragen": 2}),
    ("Überholt vor der Passphrase: keine Rückfrage mehr",
     {"uebernommen": ["B:klar"], "meldungen": 0, "tresorAmEnde": "klar", "rueckfragen": 0, "aelterFertig": True}),
    ("Ältere übernimmt bei offenem Blatt einer jüngeren: das Blatt bleibt, die jüngere übernimmt danach",
     {"uebernommen": ["A:klar", "B:m"], "meldungen": 0, "tresorAmEnde": "m", "rueckfragen": 1}),
    ("Übernehmen wirft: die Meldung kommt",
     {"uebernommen": [], "meldungen": 1}),
    # Drei Öffnungen (H3-01): Die jüngste wird am Blatt der mittleren abgewiesen — das Blatt gehört weiter der mittleren.
    ("Drei Öffnungen, die jüngste am Blatt der mittleren abgewiesen: das Blatt bleibt, die mittlere übernimmt danach",
     {"uebernommen": ["A:klar", "B:m"], "meldungen": 1, "tresorAmEnde": "m", "rueckfragen": 2}),
]


def dateiOeffnenFaelleLaufen(skript: str) -> int:
    """Lässt `dateiLesen` und `behaelterMitFreigabeOeffnen` mit angehaltener Entsiegelung laufen; Zahl der Abweichungen."""
    rumpf = ""
    for name in ("dateiLesen", "behaelterMitFreigabeOeffnen"):
        teil = pruefhilfen.funktion(skript, name)
        rumpf += ("" if teil.startswith("async") else "async ") + teil + "\n"
    # Welches Blatt beim Übernehmen offen bleibt (Z-BE2n-01) — aus der Datei; fehlt die Funktion (vor v93), schließt
    # die Attrappe jedes Blatt wie damals.
    try:
        rumpf += pruefhilfen.funktion(skript, "blattBleibt") + "\n"
    except (SystemExit, ValueError, KeyError):
        rumpf += "function blattBleibt() { return false; }\n"
    probe = rumpf + """
class Planungsfehler extends Error {}
const MAX_DATEIGROESSE = 1e9;
const uebernommen = [];
let meldungen = 0;
let freigaben = [];
const zustand = { tresor: null, statusChiffrat: "", statusChiffratMarke: -1, planung: null, oeffnenLauf: 0,
                  oeffnenUebernommen: 0, passphraseGilt: null, passphraseOffen: false };
let rueckfragen = 0;
let passphrasen = [];
let textFreigaben = [];
let blattAbweisen = null;
let aelterFertig = false;
function tresorMoeglich() { return true; }
function istBehaelter(z) { return z.verschluesselt === true; }
function kopfLesen(z) { return { inhalt: "planung", kennung: z.kennung, titel: z.titel, scheitert: z.scheitert }; }
// Wie das Blatt der Web App: eines zugleich, geführt in `zustand.passphraseOffen` wie im Original (H3-01) — eine
// zweite Frage wird abgewiesen; geschlossen weist es ab.
async function passphraseErfragen(kopf) {
  rueckfragen += 1;
  if (zustand.passphraseOffen) throw new Planungsfehler("Gerade wird schon eine Datei entsperrt.");
  zustand.passphraseOffen = true;
  try {
    await new Promise((erfuellen, abweisen) => { passphrasen.push(erfuellen); blattAbweisen = abweisen; });
  } finally {
    zustand.passphraseOffen = false; blattAbweisen = null;
  }
  return { kennung: kopf.kennung };
}
async function behaelterOeffnen(kopf, tresor) {
  await new Promise((r) => { freigaben.push(r); });
  if (kopf.scheitert) throw new Planungsfehler("beschädigt");
  return JSON.stringify({ titel: kopf.titel });
}
function planungPruefen(z) { return z; }
// Wie das Original: Offene Blätter gehen zu, außer was `blattBleibt` (aus der Datei gezogen) offen lässt.
async function planungUebernehmen(planung) {
  if (planung.titel === "wirft") throw new Error("unerwartet");
  if (blattAbweisen && !blattBleibt({ id: "blatt-passphrase" })) {
    blattAbweisen(new Planungsfehler("Ohne Passphrase bleibt die Datei geschlossen."));
  }
  uebernommen.push(planung.titel + ":" + (zustand.tresor ? zustand.tresor.kennung : "klar"));
  zustand.planung = planung;
}
function melden() { meldungen += 1; }
function datei(inhalt) { return { size: 10, name: "x.json", text: async () => JSON.stringify(inhalt) }; }
function langsam(inhalt) {
  return { size: 10, name: "l.json", text: async () => {
    await new Promise((r) => { textFreigaben.push(r); });
    return JSON.stringify(inhalt);
  } };
}
const C = (titel, scheitert) => datei({ verschluesselt: true, kennung: "k", titel, scheitert: !!scheitert });
const Cm = (titel, kennung) => datei({ verschluesselt: true, kennung, titel });
const B = datei({ titel: "B" });
const kaputt = { size: 10, name: "k.json", text: async () => "{kein json" };
async function ruhe() { for (let i = 0; i < 20; i += 1) await Promise.resolve(); }
function neu(tresor) {
  uebernommen.length = 0; meldungen = 0; freigaben = [];
  rueckfragen = 0; passphrasen = []; textFreigaben = []; blattAbweisen = null; aelterFertig = false;
  zustand.tresor = tresor; zustand.planung = null; zustand.passphraseOffen = false; zustand.passphraseGilt = null;
}
function stand(name) {
  return [name, { uebernommen: uebernommen.slice(), meldungen, rueckfragen, aelterFertig,
                  tresorAmEnde: zustand.tresor ? zustand.tresor.kennung : "klar" }];
}
const ausgabe = [];
(async () => {
  neu({ kennung: "k" });
  const p0 = dateiLesen(C("C")); await ruhe(); freigaben.shift()(); await p0;
  ausgabe.push(stand("Allein: die verschlüsselte Planung mit ihrem Schlüssel"));

  neu({ kennung: "k" });
  const p1 = dateiLesen(C("C")); await ruhe();
  const p2 = dateiLesen(B); await p2;
  freigaben.shift()(); await p1;
  ausgabe.push(stand("Überholt von Klartext: die ältere übernimmt nicht"));

  neu({ kennung: "k" });
  const p3 = dateiLesen(C("C1")); await ruhe();
  const p4 = dateiLesen(C("C2")); await ruhe();
  freigaben[1](); await p4;
  freigaben[0](); await p3;
  ausgabe.push(stand("Zwei verschlüsselte, die spätere zuerst fertig: nur die spätere"));

  neu({ kennung: "k" });
  const p5 = dateiLesen(C("C", true)); await ruhe();
  const p6 = dateiLesen(B); await p6;
  freigaben.shift()(); await p5;
  ausgabe.push(stand("Ältere scheitert nach einer jüngeren: keine Meldung"));

  // Der Schlüssel wechselt nur durch ein Öffnen: Eine ältere Klartextdatei übernimmt, während die jüngere mit dem
  // Schlüssel der Sitzung entsiegelt — die jüngere kommt mit ihrem Schlüssel an (Z-BE2-04, Z-BE2n-03).
  neu({ kennung: "k" });
  const p7a = dateiLesen(langsam({ titel: "B" })); await ruhe();
  const p7 = dateiLesen(C("C")); await ruhe();
  textFreigaben.shift()(); await p7a;
  freigaben.shift()(); await p7;
  ausgabe.push(stand("Ältere übernimmt während des Entsiegelns: die jüngere kommt mit ihrem Schlüssel"));

  neu(null);
  const p8 = dateiLesen(Cm("C", "m")); await ruhe();
  passphrasen.shift()(); await ruhe();
  freigaben.shift()(); await p8;
  ausgabe.push(stand("Mit Passphrase: die Planung mit dem neuen Schlüssel"));

  neu({ kennung: "k" });
  const p9 = dateiLesen(C("A")); await ruhe();
  const p10 = dateiLesen(kaputt); await p10;
  freigaben.shift()(); await p9;
  ausgabe.push(stand("Jüngere scheitert, ältere danach fertig: die ältere übernimmt"));

  neu(null);
  const p11 = dateiLesen(Cm("A", "m")); await ruhe();
  const p12 = dateiLesen(Cm("B", "n")); await p12;
  passphrasen.shift()(); await ruhe();
  freigaben.shift()(); await p11;
  ausgabe.push(stand("Jüngere am offenen Passphrase-Blatt abgewiesen: die ältere übernimmt danach"));

  // Die ältere wartet noch aufs Lesen; ein offenes Blatt nach ihr bliebe stehen — darum ohne `await` auf sie.
  neu(null);
  dateiLesen(langsam({ verschluesselt: true, kennung: "m", titel: "A" })).then(() => { aelterFertig = true; });
  await ruhe();
  const p14 = dateiLesen(B); await p14;
  textFreigaben.shift()(); await ruhe();
  ausgabe.push(stand("Überholt vor der Passphrase: keine Rückfrage mehr"));

  // Die ältere (Klartext, langsam gelesen) übernimmt, während das Blatt der jüngeren offen ist (Z-BE2n-01).
  neu(null);
  const p15 = dateiLesen(langsam({ titel: "A" })); await ruhe();
  const p16 = dateiLesen(Cm("B", "m")); await ruhe();
  textFreigaben.shift()(); await p15;
  if (passphrasen.length) passphrasen.shift()();
  await ruhe();
  if (freigaben.length) freigaben.shift()();
  await p16;
  ausgabe.push(stand("Ältere übernimmt bei offenem Blatt einer jüngeren: das Blatt bleibt, die jüngere übernimmt danach"));

  // Ein unerwarteter Fehler nach dem eigenen Übernehmen bleibt nicht still (Z-BE2n-02).
  neu({ kennung: "k" });
  await dateiLesen(datei({ titel: "wirft" }));
  ausgabe.push(stand("Übernehmen wirft: die Meldung kommt"));

  // Drei Öffnungen (H3-01): die älteste (Klartext, langsam gelesen), die mittlere am offenen Blatt, die jüngste am Blatt
  // abgewiesen. Danach übernimmt die älteste — das Blatt gehört weiter der mittleren und bleibt offen.
  neu(null);
  const p17 = dateiLesen(langsam({ titel: "A" })); await ruhe();
  const p18 = dateiLesen(Cm("B", "m")); await ruhe();
  const p19 = dateiLesen(Cm("C", "n")); await p19;
  textFreigaben.shift()(); await p17;
  if (passphrasen.length) passphrasen.shift()();
  await ruhe();
  if (freigaben.length) freigaben.shift()();
  await p18;
  ausgabe.push(stand("Drei Öffnungen, die jüngste am Blatt der mittleren abgewiesen: das Blatt bleibt, die mittlere übernimmt danach"));
  print(JSON.stringify(ausgabe));
})();
"""
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        pfad = Path(datei.name)
    try:
        lauf = jsc_laufen(pfad)
    finally:
        pfad.unlink(missing_ok=True)
    if lauf.returncode != 0:
        print("jsc meldet einen Fehler (Öffnen):")
        print((lauf.stdout + lauf.stderr)[-2000:])
        return 1
    ergebnisse = dict((name, werte) for name, werte in json.loads(lauf.stdout.strip().splitlines()[-1]))
    fehler = 0
    for name, erwartet in DATEIOEFFNENFAELLE:
        ist = ergebnisse.get(name, {})
        abweichend = [f"{feld}: erwartet {soll!r}, gelesen {ist.get(feld)!r}"
                      for feld, soll in erwartet.items() if ist.get(feld) != soll]
        if abweichend:
            fehler += 1
            print(f"  ABWEICHUNG Öffnen, {name}: " + "; ".join(abweichend))
        else:
            print(f"  stimmt    Öffnen, {name}")
    return fehler


# Darstellung der Vorbereitung (v93, E1076, E1078): Klasse, erste Zeile und Text für Bildschirmleser der Kachel aus
# `kachelFuellen` (jsc, kleine DOM-Attrappe), dazu der Stil — Farbe hell/dunkel/Druck, gestrichelter Rahmen, mit dringlich
# gelb durchgezogen, Zeile, Marke im Detailblatt, Wort in der Tagesliste. Die App hält VorbereitungsmerkmalPruefungen.swift.
DARSTELLUNGSFAELLE = [
    ("Vorbereitung: Klasse, Zeile „Vorbereitung“, Text für Bildschirmleser",
     {"vorbereitung": True},
     {"klasse": "kachel vorbereitung", "erste": "vorbereitungsmarke:Vorbereitung", "vorlesenHat": ", Vorbereitung",
      "vorlesenOhne": "Korrektur"}),
    ("Vorbereitung und dringlich: beide Klassen, dringlich vor Vorbereitung vorgelesen",
     {"vorbereitung": True, "dringend": True},
     {"klasse": "kachel vorbereitung dringend", "erste": "vorbereitungsmarke:Vorbereitung",
      "vorlesenHat": ", dringlich, Vorbereitung"}),
    ("Korrektur bleibt, wie sie war",
     {"korrektur": True},
     {"klasse": "kachel korrektur", "erste": "korrekturmarke:Korrektur", "vorlesenHat": ", Korrektur",
      "vorlesenOhne": "Vorbereitung"}),
    ("Ohne Kennzeichnung: keine Zeile",
     {},
     {"klasse": "kachel", "erste": "kopf:"}),
]

STILREGELN = [
    # Je Block (Z-BE6-01): hell in `:root`, dunkel in `[data-thema="dunkel"]`, im Druck der dunkle Block auf Papierfarben.
    ("Farbe hell #0062cc in :root", r"^:root \{[^}]*?--vorbereitung:\s*#0062cc;", 1),
    ("Farbe dunkel #409cff", r"^\[data-thema=\"dunkel\"\] \{[^}]*?--vorbereitung:\s*#409cff;", 1),
    # Nur Zeilen im Druckblock — keine, die mit dessen schließender Klammer beginnt (H2-03).
    ("Farbe im Druck #0062cc", r"^@media print \{\n(?:(?!\}).*\n)*?  \[data-thema=\"dunkel\"\] \{[^}]*?--vorbereitung:\s*#0062cc;", 1),
    ("Rahmen gestrichelt im Blau", r"\.kachel\.vorbereitung\s*\{\s*border-style:\s*dashed;\s*border-color:[^;]*var\(--vorbereitung\)", 1),
    # Mit Inhalt und Lage (Z-BE6-02): gleich spezifisch wie `.kachel.vorbereitung:hover` — es gilt, was später steht.
    ("Mit dringlich: gelber Rahmen, 2px, nach dem Blau",
     r"\.kachel\.vorbereitung:hover \{[^}]*\}\n(?:.*\n)*?\.kachel\.dringend,\s*\n\.kachel\.dringend\.korrektur,\s*\n"
     r"\.kachel\.dringend\.vorbereitung,\s*\n\.kachel\.dringend\.pruefung\s*\{\s*border-color:\s*color-mix\(in srgb, "
     r"var\(--dringend\) 80%, transparent\);\s*border-width:\s*2px;\s*\}\n(?:.*\n)*?\.kachel\.dringend:hover", 1),
    ("Mit dringlich: durchgezogen", r"\.kachel\.dringend\.korrektur,\s*\.kachel\.dringend\.vorbereitung\s*\{\s*border-style:\s*solid;", 1),
    ("Zeile umrandet im Blau", r"\.vorbereitungsmarke\s*\{[^}]*border:\s*1px solid color-mix\(in srgb, var\(--vorbereitung\)", 1),
    ("Marke im Detailblatt gestrichelt im Blau",
     r"\.marke\.vorbereitung-marke\s*\{[^}]*color:\s*var\(--vorbereitung\);[^}]*border:\s*1px dashed color-mix\(in srgb, var\(--vorbereitung\)", 1),
    ("Wort in der Tagesliste", r"\.tagesziel \.vorbereitungswort\s*\{\s*color:\s*var\(--vorbereitung\)", 1),
    ("Druckgröße der Zeile", r"\.pruefungsmarke, \.korrekturmarke, \.vorbereitungsmarke, \.datumsmarke \{ font-size: 9px; \}", 1),
    # An Bedingung und Folge verankert (Z-BE6-03): dringlich · … · Vorbereitung · Korrektur.
    ("Detailblatt: Vorbereitung unter ihrer Bedingung, nach dringlich, vor der Korrektur",
     r"if \(vorhaben\.dringend\) \{\n\s*inhalt\.append\(bau\(\"span\", \"marke dringend-marke\", \"Dringlich\"\)\);\n(?:.*\n)*?"
     r"\s*if \(vorhaben\.vorbereitung\) \{\n\s*inhalt\.append\(bau\(\"span\", \"marke vorbereitung-marke\", \"Vorbereitung\"\)\);\n"
     r"\s*\}\n\s*if \(vorhaben\.korrektur\) \{", 1),
    ("Tagesliste: Vorbereitung unter ihrer Bedingung, nach dringlich, vor der Korrektur",
     r"if \(vorhaben\.dringend\) \{\n\s*neben\.append\(bau\(\"span\", \"dringlich\", \"dringlich\"\)[^\n]*\n\s*\}\n"
     r"\s*if \(vorhaben\.vorbereitung\) \{\n\s*neben\.append\(bau\(\"span\", \"vorbereitungswort\", \"Vorbereitung\"\)[^\n]*\n"
     r"\s*\}\n\s*if \(vorhaben\.korrektur\) \{", 1),
    # Außerhalb der Vorbereitung (R-BE8-09): Die Öffnen-Meldung trägt den Satz über unbekannte Angaben und wird mit ihm zur Warnung (H3-07).
    ("Öffnen-Meldung mit dem Satz über unbekannte Angaben",
     r'^         \+ \(planung\.unbekannteAngaben \? " " \+ unbekannteAngabenText\(planung\.unbekannteAngaben\) : ""\),\n'
     r'         verworfen > 0 \|\| verbindungGeloest \|\| planung\.uebergangen !== "" \|\| planung\.unbekannteAngaben > 0\);', 1),
]


def darstellungPruefen(html: str, skript: str) -> int:
    """Stilregeln im Text, die Kachel in jsc; Zahl der Abweichungen."""
    fehler = 0
    for name, muster, anzahl in STILREGELN:
        gefunden = len(re.findall(muster, html, re.MULTILINE))
        if gefunden == anzahl:
            print(f"  stimmt    Darstellung, {name}")
        else:
            fehler += 1
            print(f"  ABWEICHUNG Darstellung, {name}: {gefunden}× statt {anzahl}×")
    rumpf = pruefhilfen.funktion(skript, "bau") + "\n" + pruefhilfen.funktion(skript, "kachelFuellen") + "\n"
    probe = rumpf + """
class Knoten {
  constructor(tag) { this.tagName = tag; this.className = ""; this.textContent = ""; this.kinder = []; this.attribute = {}; }
  append(...k) { for (const x of k) this.kinder.push(x); }
  replaceChildren(...k) { this.kinder = []; this.append(...k); }
  setAttribute(n, v) { this.attribute[n] = String(v); }
  getAttribute(n) { return this.attribute[n] ?? null; }
}
const document = { createElement: (t) => new Knoten(t), createElementNS: (ns, t) => new Knoten(t),
                   createTextNode: (t) => { const k = new Knoten("#text"); k.textContent = t; return k; } };
function ikon(name, klasse) { const k = new Knoten("svg"); k.className = klasse || "ikon"; return k; }
function pruefungstext() { return "Prüfung"; }
function datumstext() { return "Datum"; }
function hausaufgabenBeschriftung() { return "Hausaufgabe"; }
function hausaufgabenDruckmarke() { return "HA"; }
function verweiszeile() { return new Knoten("div"); }
function linkName(a) { return a; }
const zustand = { wochen: [] };
const FAELLE = __FAELLE__;
const ausgabe = [];
for (const [name, felder] of FAELLE) {
  const vorhaben = Object.assign({ id: "e1", titel: "Versuch", text: "", kommentar: "", erledigt: false, pruefung: false,
    korrektur: false, vorbereitung: false, dringend: false, hausaufgabe: false, datumISO: "", pruefungstagISO: "",
    links: [], materialien: [], woche: 0 }, felder);
  const kachel = kachelFuellen(new Knoten("div"), vorhaben, { name: "8b" });
  const erste = kachel.kinder[0];
  ausgabe.push([name, { klasse: kachel.className, erste: erste ? erste.className + ":" + erste.textContent : "",
                        vorlesen: kachel.getAttribute("aria-label") || "" }]);
}
print(JSON.stringify(ausgabe));
""".replace("__FAELLE__", json.dumps([[n, f] for n, f, _ in DARSTELLUNGSFAELLE], ensure_ascii=False))
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        pfad = Path(datei.name)
    try:
        lauf = jsc_laufen(pfad)
    finally:
        pfad.unlink(missing_ok=True)
    if lauf.returncode != 0:
        print("jsc meldet einen Fehler (Darstellung):")
        print((lauf.stdout + lauf.stderr)[-2000:])
        return fehler + 1
    ergebnisse = dict((n, w) for n, w in json.loads(lauf.stdout.strip().splitlines()[-1]))
    for name, _, erwartet in DARSTELLUNGSFAELLE:
        ist = ergebnisse.get(name, {})
        abweichend = []
        for feld in ("klasse", "erste"):
            if feld in erwartet and ist.get(feld) != erwartet[feld]:
                abweichend.append(f"{feld}: erwartet {erwartet[feld]!r}, gelesen {ist.get(feld)!r}")
        if "vorlesenHat" in erwartet and erwartet["vorlesenHat"] not in ist.get("vorlesen", ""):
            abweichend.append(f"vorgelesen ohne {erwartet['vorlesenHat']!r}: {ist.get('vorlesen')!r}")
        if "vorlesenOhne" in erwartet and erwartet["vorlesenOhne"] in ist.get("vorlesen", ""):
            abweichend.append(f"vorgelesen mit {erwartet['vorlesenOhne']!r}: {ist.get('vorlesen')!r}")
        if abweichend:
            fehler += 1
            print(f"  ABWEICHUNG Darstellung, {name}: " + "; ".join(abweichend))
        else:
            print(f"  stimmt    Darstellung, {name}")
    return fehler


JSC_FRIST = 120  # Sekunden — ein haengender jsc haelt die Pruefung nicht ewig (B15)


def jsc_laufen(pfad: Path) -> subprocess.CompletedProcess:
    """jsc mit Frist; laeuft die Frist ab, ist das ein Fehlschlag mit Wortlaut."""
    try:
        return subprocess.run([str(JSC), str(pfad)], capture_output=True, text=True, timeout=JSC_FRIST)
    except subprocess.TimeoutExpired:
        raise SystemExit(f"jsc antwortete nicht binnen {JSC_FRIST} s — Pruefung abgebrochen")


def merkFaelleLaufen(skript: str) -> int:
    """Laesst `statusMerken` der Web App gegen Speicher-Attrappen laufen; Zahl der Abweichungen."""
    probe = pruefhilfen.funktion(skript, "statusMerken") + "\n" \
        + pruefhilfen.funktion(skript, "inSpeicherSchreiben") + "\n" + """
let warnungen = 0, versuche = 0, versiegelt = 0, scheitern = false, versiegelnScheitert = false;
const speicher = {};
function melden(text, warnung) { if (warnung) warnungen += 1; }
function statusSchluessel(p) { return "status:" + p.titel; }
function statusAlsText() { return JSON.stringify({ marke: zustand.statusMarke }); }
async function behaelterVersiegeln(text, inhalt, tresor) {
  versiegelt += 1;
  if (versiegelnScheitert) throw new Error("Versiegeln verweigert");
  return "chiffrat:" + text;
}
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
  ausgabe.push(["Klartext: Neue Marke schreibt genau einmal", stand()]);
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
  zustand.speicherFremd = false; zustand.statusMarke = 7; statusMerken();
  zustand.merkLauf += 1; zustand.planung = { titel: "Q" }; zustand.statusChiffratMarke = -1;
  await abwarten();
  ausgabe.push(["Planungswechsel waehrend des Versiegelns: nichts geschrieben", stand()]);
  zustand.statusMarke = 8; statusMerken(); await abwarten();
  ausgabe.push(["Ohne Wechsel schreibt der Lauf wie gewohnt", stand()]);
  zustand.statusMarke = 9; versiegelnScheitert = true; statusMerken();
  zustand.merkLauf += 1; zustand.planung = { titel: "R" }; zustand.statusChiffratMarke = -1;
  await abwarten(); versiegelnScheitert = false;
  ausgabe.push(["Planungswechsel waehrend des Versiegelns, Versiegeln scheitert: keine Warnung", stand()]);
  zustand.statusMarke = 10; versiegelnScheitert = true; statusMerken(); await abwarten();
  versiegelnScheitert = false;
  ausgabe.push(["Versiegeln der eigenen Planung scheitert: Warnung", stand()]);
  print(JSON.stringify(ausgabe));
})();
"""
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        pfad = Path(datei.name)
    try:
        lauf = jsc_laufen(pfad)
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
        abweichend = [f"{feld}: erwartet {soll!r}, Web App {ist.get(feld)!r}"
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
        print(f"Web App nicht gefunden: {HTML}")
        return 1
    rumpf = pruefhilfen.skript(HTML)

    # Von den Farbtafeln bis zum Leser: Alles dazwischen sind Deklarationen.
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
        lauf = jsc_laufen(pfad)
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
    fehler += kommentarFaelleLaufen(rumpf, teil)
    fehler += merkFaelleLaufen(rumpf)
    fehler += schreibFaelleLaufen(rumpf)
    fehler += wiederaufnahmeFaelleLaufen(rumpf)
    fehler += dateiOeffnenFaelleLaufen(rumpf)
    fehler += darstellungPruefen(HTML.read_text(encoding="utf-8"), rumpf)

    gesamt = (len(FAELLE) + len(STATUSFAELLE) + len(OEFFNENFAELLE) + len(KOMMENTARFAELLE) + len(MERKFAELLE)
              + len(SCHREIBFAELLE) + len(WIEDERAUFNAHMEFAELLE) + len(DATEIOEFFNENFAELLE)
              + len(DARSTELLUNGSFAELLE) + len(STILREGELN))
    if fehler:
        print(f"\n{fehler} von {gesamt} Faellen weichen vom Leser der App ab.")
        return 1
    print(f"\n{GELUNGEN} ({len(FAELLE)} Faelle, dazu {len(STATUSFAELLE)} zur Fassung der Statusdatei, "
          f"{len(OEFFNENFAELLE)} zur Schranke vor dem Lesen, {len(KOMMENTARFAELLE)} zum Kommentar, "
          f"{len(MERKFAELLE)} zum Merken und "
          f"{len(SCHREIBFAELLE)} zum Schreiben in die Zieldatei, {len(WIEDERAUFNAHMEFAELLE)} zur Wiederaufnahme und "
          f"{len(DATEIOEFFNENFAELLE)} zum Öffnen einer Datei; dazu {len(DARSTELLUNGSFAELLE) + len(STILREGELN)} zur "
          f"Darstellung der Vorbereitung und der Öffnen-Meldung)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
