#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Abzugvergleich beider Dateileser: Dieselben erzeugten Grenzfall-Planungen gehen
durch `Planungsdatei.lesenMitBilanz` der App (die Modell-Dateien werden mit
`swiftc` zu einem kleinen Programm übersetzt — sie hängen an nichts als
Foundation) und durch `planungPruefen` der Ansicht (per `jsc`). Beide geben je
Planung einen zeilenweisen Abzug aus; verglichen wird Zeile für Zeile.

Anders als `leser_pruefen.py` braucht das keine Erwartungswerte: Gefüttert wird
mit **erzeugten** Fällen — krumme Zahlen, unsichtbare Zeichen, doppelte und
leere Kennungen, Datumsformen am Rand, Farben außerhalb der Palette,
Unterrichtstage aller Art. Der Erzeuger setzt U+FEFF gezielt auch vor `woche`,
`wochen`, `version` und Wahrheitswerte — die Stelle, an der zwei JSON-Leser am
leichtesten auseinandergehen (siehe DateiPruefungen.vorspannBeiderFassungen).
Ein Werkzeug, das nie ausschlägt, belegt nichts: Mit `--html` und `--modell`
lässt es sich gegen eine andere Fassung richten, bei der es ausschlagen muss.

Was hier NICHT geprüft wird: Weblinks (`jsc` kennt kein `URL` — siehe
`weblinks_pruefen.py`).

**Doppelte Schlüssel im selben Objekt** sind die eine dokumentierte Abweichung:
`JSONSerialization` behält den ersten Wert, `JSON.parse` den letzten (beides
nachgemessen; die App schreibt nie doppelte Schlüssel, nur eine von Hand
bearbeitete Datei hat welche). Die Fälle `doppelt-*` unten halten genau das
fest — schlägt einer aus, hat sich ein Leser geändert, und die dokumentierte
Regel (README, CHANGELOG 1.4.2) stimmt nicht mehr. Kanonisch äquivalente Schlüssel
(é gegen e + U+0301) lesen beide seit v42 als einen (NFC); der Erzeuger baut sie.

Aufruf:  python3 abzug_pruefen.py [--anzahl 1500] [--saat 7] [--zeigen 12]
Braucht `swiftc` (Xcode Command Line Tools) und `jsc`. Ergebnis: Exit 0/1.
"""

import argparse
import glob
import json
import os
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import pruefhilfen

HIER = Path(__file__).resolve().parent
HTML = HIER / "unterrichtsplanung-ansicht.html"
# …/Web-App/vNN → …/macOS-App/vNN/Quellen/Unterrichtsplanung/Modell
MODELL = HIER.parent.parent / "macOS-App" / HIER.name / "Quellen" / "Unterrichtsplanung" / "Modell"
JSC = Path("/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc")

GELUNGEN = "Beide Dateileser lesen alle erzeugten Faelle gleich."

# ── Der Erzeuger ──────────────────────────────────────────────────────

BOM, NEL, LS, NBSP, VOLL3 = "\ufeff", "\u0085", "\u2028", "\u00a0", "\uff13"
SONDER = ["", " ", "\t", "\n", NEL, LS, BOM, NBSP, "  a  ", BOM + "Mathe", "Mathe" + BOM,
          "a" + BOM + "b", "Mathe", "\tk1 ", "k1\n", "x" * 600, "Ü", "ß",
          "constructor", "__proto__", "a – b", "AG – LEGO-Robotik", "5a",
          NEL + "Mathe" + LS, "\U0001F600" * 3, "e\u0301" * 4,
          # Steuer- und Bidi-Zeichen, NFC gegen NFD.
          "a\u0000b", "\u001b[31mrot", "links\u202eRTL", "\u2066a\u2069", "\u007f",
          "e\u0301", "\u00e9", "\r\n", "\ta\tb"]
KENNUNGEN = ["k1", "k2", "k3", "k1\n", "\tk1 ", "", None, 7, "x" * 64, "x" * 65,
             "-k1", "k 1", "K_1.a:b", "kä", "__proto__", BOM + "k1", BOM + BOM + "k1", "k1\u0000",
             " k1", "k1 ", 1e16, True]
# Zahl, Wahrheitswert, Objekt in einem Textfeld: Texte sind Zeichenketten —
# alles andere gilt in beiden Lesern als leer (1e16 und 1e-7 schrieben sie verschieden).
NICHTTEXTE = [1e16, 1e-7, 12345678901234567890, 0, -1, 1.5, True, False, None, 7, {}, [], "3"]
ZAHLEN = [0, 1, 2, 3, 4, 5, 6, 7, -1, 1.9, 4.99, 5.0, "3", " 2", "2 ", "+1", "-1", "1e2",
          "1-2", "x", "", None, True, False, 1e15, 1e16, 2 ** 63, -(2 ** 63) - 1, 3.5,
          BOM + "3", VOLL3, "\n3", "5\n", " 3", 0.9999, -0.5]
DATEN = ["2026-08-10", "2026-08-12", "2026-08-15", "2026-08-16", "2026-02-29", "2024-02-29",
         "2026-13-01", "2026-8-1", "", None, 5, "1899-12-31", "1900-01-01", "2999-12-31",
         "3000-01-01", "2026-08-10T00:00", " 2026-08-10", "2026-08-32", "0000-01-01",
         "2027-01-01", BOM + "2026-08-10", "2026-08-10\n"]
FARBEN = [0, 1, 5, 23, 24, -1, 2.5, "3", True, None, "", 1e15, 12, 23.0]
TOENE = ["blau-mittel", "rot-hell", "gruen-dunkel", "lila", "", None, 3, "BLAU-MITTEL",
         "orange-dunkel", BOM + "blau-mittel"]


def wahl(liste):
    return random.choice(liste)


def text():
    r = random.random()
    if r < 0.08:
        return wahl(NICHTTEXTE)
    return wahl(SONDER) if r < 0.4 else wahl(["Titel", "5a", "Bio", "Info", "G6a"])


def klasse(i):
    k = {"id": wahl(KENNUNGEN + ["k%d" % i])
         if random.random() < 0.5 else "k%d" % i,
         "name": text(), "fach": text()}
    if random.random() < 0.7:
        k["farbe"] = wahl(FARBEN)
    if random.random() < 0.5:
        k["farbeManuell"] = wahl([True, False, 0, 1, "", "ja", None, BOM])
    if random.random() < 0.5:
        k["notiz"] = text()
    if random.random() < 0.4:
        k["verwaltung"] = wahl(["/a/b.numbers", "rel/x.pdf", "p" * 1300, "", "~/x", "file:///a/b"])
    if random.random() < 0.4:
        k["curriculum"] = wahl(["/a/b.pdf", "../x.pdf", ""])
    r = random.random()
    if r < 0.6:
        k["unterrichtstage"] = [wahl(ZAHLEN) for _ in range(random.randint(0, 8))]
    elif r < 0.75:
        k["unterrichtstage"] = wahl(["Mo", 3, None, True, {}, {"0": 1}, "", "1,2"])
    return k


def eintrag(i, ids, wochen):
    e = {"id": wahl(["e1", "e1", "e2", "", None, "e%d" % i, "e1 ", "e1\n", "e 1", "-e1",
                     "x" * 65, "e\u00e4"])
         if random.random() < 0.4 else "e%d" % i,
         "klasseId": wahl(ids + ["k9", "", None, "k1 ", " k1", BOM + BOM + "k1", 7, True]),
         "woche": wahl([0, 1, wochen - 1, wochen, -1, "2", 1.5, None, "x", True, BOM + "1"])}
    if random.random() < 0.8:
        e["titel"] = text()
    if random.random() < 0.5:
        e["text"] = wahl(["Text", "", "t" * 25000, None, 3])
    if random.random() < 0.3:
        e["beschreibung"] = wahl(["Alt", "b" * 25000])
    if random.random() < 0.5:
        e["erledigt"] = wahl([True, False, 0, 1, "", "ja", None, BOM])
    if random.random() < 0.5:
        e["pruefung"] = wahl([True, False, 0, "x", BOM])
    if random.random() < 0.5:
        e["pruefungstag"] = wahl(DATEN)
    if random.random() < 0.6:
        e["datum"] = wahl(DATEN)
    if random.random() < 0.4:
        e["dringend"] = wahl([True, False, "", 0, 2])
    if random.random() < 0.4:
        e["kommentar"] = wahl(["Kommentar", "", "k" * 25000, None, 1e-7, False])
    if random.random() < 0.3:
        e["statusGeaendert"] = wahl(["2026-08-10T10:00:00.000Z", "", "x", 5])
    if random.random() < 0.4:
        e["hausaufgabe"] = wahl([True, False, 0, 1, "", "x", BOM, None])
    if random.random() < 0.4:
        e["hausaufgabenText"] = wahl(["S. 42", "", "h" * 600, BOM + "S. 1", None, 3, "a\nb", "x\u0007y"])
    if random.random() < 0.3:
        e["materialien"] = [wahl([{"titel": text(),
                                   "pfad": wahl(["a/b.pdf", "/abs/c.key", "", "../d", "~/e",
                                                 "file:///f/g", "p" * 1100])},
                                  {"pfad": "x.pdf"}, {}, "kaputt", None])
                            for _ in range(random.randint(0, 4))]
    return e


def planung(i):
    wochen = wahl([4, 8, 52, 53, 0, -3, "6", None, 1, 1.9, BOM + "6"])
    klassen = [klasse(j) for j in range(random.randint(0, 6))]
    ids = [k["id"] for k in klassen if isinstance(k.get("id"), str)]
    w_int = wochen if isinstance(wochen, int) and wochen > 0 else 52
    p = {"typ": wahl(["unterrichtsplanung"] * 8 + ["", "fremd"]),
         "version": wahl([2, 1, 0, "2", None, 3, 1e15, BOM + "2"]),
         "titel": text(), "start": wahl(DATEN), "wochen": wochen,
         "klassen": klassen if random.random() < 0.9 else "kaputt",
         "eintraege": [eintrag(j, ids, w_int) for j in range(random.randint(0, 8))]}
    if random.random() < 0.5:
        p["ersterSchultag"] = wahl(DATEN)
    if random.random() < 0.5:
        p["basis"] = wahl(["/Users/x/U", "", "p" * 1300, None, "rel"])
    if random.random() < 0.3:
        p["basisordner"] = wahl(["/alt", "q" * 1300])
    if random.random() < 0.5:
        p["frei"] = [wahl(DATEN) for _ in range(random.randint(0, 5))]
    if random.random() < 0.5:
        p["ferien"] = [{"id": wahl(["f1", "f1", "", None, "f 1", "x" * 65]), "name": text(),
                        "von": wahl(DATEN), "bis": wahl(DATEN)}
                       for _ in range(random.randint(0, 3))]
    if random.random() < 0.5:
        p["sperrzeiten"] = [{"id": wahl(["s1", "s1", "", "-s1", 3]), "name": text(),
                             "von": wahl(DATEN), "bis": wahl(DATEN),
                             "kurse": ([wahl(ids + ["k9", 3, None])
                                        for _ in range(random.randint(0, 3))]
                                       if ids else wahl([[], "x"]))}
                            for _ in range(random.randint(0, 3))]
    if random.random() < 0.6:
        p["fachfarben"] = {wahl(SONDER + ["mathe", "Mathe", "bio", "\u00e9", "e\u0301",
                                          "\u00c9", "E\u0301"]): wahl(TOENE)
                           for _ in range(random.randint(0, 5))}
    if random.random() < 0.4:
        p["zellenfrei"] = [wahl([{"klasseId": wahl(ids + ["k9", "", " k1", 7]), "woche": wahl(DATEN)}, "x", {}])
                           for _ in range(random.randint(0, 4))]
    return p


# ── Der Abzug in Swift ────────────────────────────────────────────────

MAIN_SWIFT = r'''
import Foundation

/// Stellvertreter für Gestaltung/Bausteine.swift — das Modell nennt nur die
/// Symbolnamen der Kursdateien.
enum Zeichen {
    static let kursdatei = ""
    static let kursdateiGesetzt = ""
    static let curriculum = ""
    static let curriculumGesetzt = ""
}

func esc(_ s: String) -> String {
    var aus = ""
    for scalar in s.unicodeScalars {
        if scalar.value < 32 || scalar.value > 126 || scalar == "|" || scalar == ";" {
            aus += String(format: "\\u%04X", scalar.value)
        } else {
            aus.unicodeScalars.append(scalar)
        }
    }
    return aus
}

let erzeugt = try! NSRegularExpression(pattern: "^[kefs]-[0-9a-z]+-[0-9a-z]{5}$")
func norm(_ id: String) -> String {
    erzeugt.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil ? "<neu>" : esc(id)
}

func abzug(_ daten: Data) -> [String] {
    var zeilen: [String] = []
    let planung: Planung
    let bilanz: Planungsdatei.Verlustbilanz
    do {
        (planung, bilanz) = try Planungsdatei.lesenMitBilanz(daten)
    } catch {
        return ["FEHLER=" + esc((error as? Planungsfehler)?.text ?? "\(error)")]
    }
    zeilen.append("kopf=\(esc(planung.titel))|\(planung.start.iso)|\(planung.wochen)|"
                  + "\(esc(planung.basis))|\(planung.ersterSchultag?.iso ?? "")")
    zeilen.append("frei=" + planung.frei.map(\.iso).sorted().joined(separator: ","))
    for f in planung.ferien {
        zeilen.append("ferien=\(norm(f.id))|\(esc(f.name))|\(f.von.iso)|\(f.bis.iso)")
    }
    for s in planung.sperrzeiten {
        zeilen.append("sperre=\(norm(s.id))|\(esc(s.name))|\(s.von.iso)|\(s.bis.iso)|"
                      + s.kurse.map(norm).joined(separator: ","))
    }
    let farben = planung.fachfarben.map { (esc($0.key), esc($0.value)) }.sorted { $0.0 < $1.0 }
    zeilen.append("fachfarben=" + farben.map { "\($0.0)=\($0.1)" }.joined(separator: ";"))
    for k in planung.klassen {
        zeilen.append("klasse=\(norm(k.id))|\(esc(k.name))|\(esc(k.fach))|\(esc(k.notiz))|"
                      + "\(k.farbe)|\(k.farbeManuell)|\(esc(k.verwaltung))|\(esc(k.curriculum))|"
                      + k.unterrichtstage.gespeichert.map(String.init).joined(separator: ","))
    }
    let zellen = planung.zellenfrei.map { "\(norm($0.klasseId))|\($0.woche.iso)" }.sorted()
    zeilen.append("zellenfrei=" + zellen.joined(separator: ";"))
    for e in planung.eintraege {
        let material = e.materialien.map { "\(esc($0.titel))>\(esc($0.pfad))" }.joined(separator: ",")
        zeilen.append("eintrag=\(norm(e.id))|\(norm(e.klasseId))|\(e.woche)|\(esc(e.titel))|"
                      + "\(esc(e.text))|\(e.erledigt)|\(e.pruefung)|\(e.pruefungstag?.iso ?? "")|"
                      + "\(e.datum?.iso ?? "")|\(e.wochentag?.rawValue ?? 0)|\(e.dringend)|"
                      + "\(esc(e.kommentar))|\(esc(e.statusGeaendert))|"
                      + "\(e.hausaufgabe)|\(esc(e.hausaufgabenText))|\(material)")
    }
    let teile = bilanz.verworfenes + bilanz.hinweise
    zeilen.append("bilanz=" + (bilanz.istLeer ? "" : esc("Übergangen: " + teile.joined(separator: ", ") + ".")))
    return zeilen
}

for pfad in CommandLine.arguments.dropFirst() {
    print("### " + (pfad as NSString).lastPathComponent)
    guard let daten = FileManager.default.contents(atPath: pfad) else {
        print("FEHLER=unlesbar")
        continue
    }
    for zeile in abzug(daten) { print(zeile) }
}
'''

# ── Der Abzug in JavaScript ───────────────────────────────────────────

JS_ABZUG = r'''
const ERZEUGT = /^[kefs]-[0-9a-z]+-[0-9a-z]{5}$/;
function esc(s) {
  let aus = "";
  for (const ch of String(s)) {
    const c = ch.codePointAt(0);
    aus += (c < 32 || c > 126 || ch === "|" || ch === ";")
      ? "\\u" + c.toString(16).toUpperCase().padStart(4, "0") : ch;
  }
  return aus;
}
function norm(id) { return ERZEUGT.test(id) ? "<neu>" : esc(id); }
function abzug(text) {
  const z = [];
  let p;
  // Aus dem Rohtext, wie `dateiLesen`: So kommen auch doppelte Schlüssel an.
  let roh;
  try { roh = JSON.parse(text); }
  catch { return ["FEHLER=" + esc("Die Datei ist kein lesbares JSON.")]; }
  try { p = planungPruefen(roh); }
  catch (e) { return ["FEHLER=" + esc(e && (e.nachricht ?? e.message) || e)]; }
  z.push(`kopf=${esc(p.titel)}|${p.startISO}|${p.wochen}|${esc(p.basis)}|${p.ersterSchultagISO}`);
  z.push("frei=" + [...p.frei].sort().join(","));
  for (const f of p.ferien) z.push(`ferien=${norm(f.id)}|${esc(f.name)}|${f.von}|${f.bis}`);
  for (const s of p.sperrzeiten) z.push(`sperre=${norm(s.id)}|${esc(s.name)}|${s.von}|${s.bis}|` + s.kurse.map(norm).join(","));
  const farben = Object.keys(p.fachfarben).map((k) => [esc(k), esc(p.fachfarben[k])]).sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
  z.push("fachfarben=" + farben.map(([k, v]) => `${k}=${v}`).join(";"));
  for (const k of p.klassen) {
    z.push(`klasse=${norm(k.id)}|${esc(k.name)}|${esc(k.fach)}|${esc(k.notiz)}|${k.farbe}|${k.farbeManuell}|${esc(k.verwaltung)}|${esc(k.curriculum)}|` + k.unterrichtstage.join(","));
  }
  z.push("zellenfrei=" + p.zellenfrei.map((x) => `${norm(x.klasseId)}|${x.woche}`).sort().join(";"));
  for (const e of p.eintraege) {
    const material = e.materialien.map((m) => `${esc(m.titel)}>${esc(m.pfad)}`).join(",");
    const tag = e.datumISO ? (wochentagISO(tagAusISO(e.datumISO)) ?? 0) : 0;
    z.push(`eintrag=${norm(e.id)}|${norm(e.klasseId)}|${e.woche}|${esc(e.titel)}|${esc(e.text)}|${e.erledigt}|${e.pruefung}|${e.pruefungstagISO}|${e.datumISO}|${tag}|${e.dringend}|${esc(e.kommentar)}|${esc(e.statusGeaendert)}|${e.hausaufgabe}|${esc(e.hausaufgabenText)}|${material}`);
  }
  z.push("bilanz=" + esc(p.uebergangen));
  return z;
}
const AUS = [];
for (const [name, text] of ALLE) { AUS.push("### " + name); AUS.push(...abzug(text)); }
print(AUS.join("\n"));
'''


# ── Doppelte Schlüssel: die dokumentierte Abweichung ─────────────────
# Rohtexte, die kein Wörterbuch hergibt. Erwartet: die App liest den ERSTEN
# Wert, die Ansicht den LETZTEN. (Name, Rohtext, Zeile der App, Zeile der Ansicht)
DOPPELT = [
    ("doppelt-titel",
     '{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","wochen":4,'
     '"titel":"Erster","titel":"Letzter","klassen":[],"eintraege":[]}',
     "kopf=Erster|2026-08-10|4||", "kopf=Letzter|2026-08-10|4||"),
    ("doppelt-eintraege",
     '{"typ":"unterrichtsplanung","version":2,"start":"2026-08-10","wochen":4,'
     '"klassen":[{"id":"k1","name":"5a"}],'
     '"eintraege":[{"id":"e1","klasseId":"k1","woche":0,"titel":"A"}],'
     '"eintraege":[{"id":"e2","klasseId":"k1","woche":1,"titel":"B"}]}',
     "eintrag=e1|k1|0|A||false|false|||0|false|||", "eintrag=e2|k1|1|B||false|false|||0|false|||"),
    ("doppelt-version",
     '{"typ":"unterrichtsplanung","version":2,"version":3,"klassen":[],"eintraege":[]}',
     "kopf=Unterrichtsplanung|", "FEHLER=Die Datei stammt aus einer neueren Fassung (3)"),
]


def doppeltePruefen(app: dict, ansicht: dict) -> int:
    fehler = 0
    for name, _text, appZeile, ansichtZeile in DOPPELT:
        schluessel = name + ".json"
        sa, sb = app.get(schluessel, []), ansicht.get(schluessel, [])
        treffer_app = any(z.startswith(appZeile) for z in sa)
        treffer_ansicht = any(z.startswith(ansichtZeile) for z in sb)
        if treffer_app and treffer_ansicht:
            print(f"  dokumentiert  {name}: App liest den ersten, Ansicht den letzten Wert")
        else:
            fehler += 1
            print(f"  ABWEICHUNG {name}: erwartet App {appZeile!r} / Ansicht {ansichtZeile!r}")
            print(f"              App     : {sa[:3]}")
            print(f"              Ansicht : {sb[:3]}")
    return fehler


def zerlegen(text: str) -> dict:
    faelle, aktuell = {}, None
    for zeile in text.split("\n"):
        if zeile.startswith("### "):
            aktuell = zeile[4:]
            faelle[aktuell] = []
        elif aktuell is not None and zeile != "":
            faelle[aktuell].append(zeile)
    return faelle


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--anzahl", type=int, default=1500)
    parser.add_argument("--saat", type=int, default=7)
    parser.add_argument("--zeigen", type=int, default=12)
    # Für die Gegenprobe gegen eine andere Fassung: Das Werkzeug muss einmal
    # ausgeschlagen haben, bevor ein grüner Lauf etwas belegt.
    parser.add_argument("--html", type=Path, default=HTML)
    parser.add_argument("--modell", type=Path, default=MODELL)
    args = parser.parse_args()
    html, modell = args.html, args.modell

    if not JSC.exists():
        print(f"jsc nicht gefunden: {JSC}")
        return 1
    if not modell.exists():
        print(f"Modell der App nicht gefunden: {modell}")
        return 1
    teil = pruefhilfen.abschnitt(pruefhilfen.skript(html), "const GRUNDFARBEN", "planungPruefen")

    random.seed(args.saat)
    alle = [planung(i) for i in range(args.anzahl)]

    with tempfile.TemporaryDirectory() as ordner:
        ordner = Path(ordner)
        (ordner / "main.swift").write_text(MAIN_SWIFT, encoding="utf-8")
        quellen = sorted(glob.glob(str(modell / "*.swift")))
        print(f"  uebersetze {len(quellen)} Modell-Dateien mit swiftc …")
        bau = subprocess.run(["swiftc", "-O", "-o", str(ordner / "abzug_swift"),
                              str(ordner / "main.swift")] + quellen,
                             capture_output=True, text=True)
        if bau.returncode != 0:
            print("swiftc meldet einen Fehler:")
            print((bau.stdout + bau.stderr)[-3000:])
            return 1

        fallordner = ordner / "faelle"
        fallordner.mkdir()
        # Beide Leser bekommen denselben Rohtext — die Ansicht parst ihn selbst,
        # wie im Browser; nur so kommen doppelte Schlüssel überhaupt an.
        rohtexte = [("%04d.json" % i, json.dumps(p, ensure_ascii=False))
                    for i, p in enumerate(alle)]
        rohtexte += [(name + ".json", text) for name, text, _a, _b in DOPPELT]
        for name, text in rohtexte:
            (fallordner / name).write_text(text, encoding="utf-8")
        dateien = sorted(glob.glob(str(fallordner / "*.json")))
        sw = subprocess.run([str(ordner / "abzug_swift")] + dateien,
                            capture_output=True, text=True)
        if sw.returncode != 0:
            print("Das Swift-Programm meldet einen Fehler:")
            print((sw.stdout + sw.stderr)[-3000:])
            return 1

        # Als JSON-Text, nicht als Objektliteral: Ein Literal mit dem Schlüssel
        # "__proto__" setzt den Prototyp; JSON.parse legt eine eigene
        # Eigenschaft an — wie im Browser.
        probe = (teil + "\nconst ALLE = JSON.parse("
                 + json.dumps(json.dumps(rohtexte, ensure_ascii=False), ensure_ascii=False)
                 + ");\n" + JS_ABZUG)
        (ordner / "probe.js").write_text(probe, encoding="utf-8")
        js = subprocess.run([str(JSC), str(ordner / "probe.js")], capture_output=True, text=True)
        if js.returncode != 0:
            print("jsc meldet einen Fehler:")
            print((js.stdout + js.stderr)[-3000:])
            return 1

    app, ansicht = zerlegen(sw.stdout), zerlegen(js.stdout)
    doppelt = doppeltePruefen(app, ansicht)
    doppeltNamen = {name + ".json" for name, _t, _a, _b in DOPPELT}
    abweichend = 0
    gezeigt = 0
    ursachen = {}
    for name in sorted(app):
        if name in doppeltNamen or app[name] == ansicht.get(name):
            continue
        abweichend += 1
        sa, sb = app[name], ansicht.get(name, [])
        erste = next(((x, y) for x, y in zip(sa, sb) if x != y),
                     (sa[len(sb):len(sb) + 1], sb[len(sa):len(sa) + 1]))
        schluessel = str(erste[0]).split("=", 1)[0]
        ursachen[schluessel] = ursachen.get(schluessel, 0) + 1
        if gezeigt < args.zeigen:
            gezeigt += 1
            print(f"  ABWEICHUNG {name}")
            print(f"              App     : {str(erste[0])[:160]}")
            print(f"              Ansicht : {str(erste[1])[:160]}")
    if abweichend:
        print(f"\n{abweichend} von {len(app) - len(doppeltNamen)} Faellen weichen ab (Saat {args.saat}).")
        print("Erste abweichende Zeile, nach Feld:")
        for k, v in sorted(ursachen.items(), key=lambda kv: -kv[1]):
            print(f"  {v:5d}  {k}")
        return 1
    if doppelt:
        print(f"\n{doppelt} Faelle mit doppelten Schluesseln lesen nicht wie dokumentiert.")
        return 1
    print(f"\n{GELUNGEN} ({len(app) - len(doppeltNamen)} Faelle, Saat {args.saat}; "
          f"{len(DOPPELT)} dokumentierte Faelle mit doppelten Schluesseln)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
