#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Gleicht die JS-Zwillingsfunktionen `lage()` und `schulwochen()` der Ansicht
gegen die Fälle der Swift-Prüfungen ab (macOS-App: Pruefungen/
SchulwochenPruefungen.swift, Regel: Modell/Wochenlage.swift) — samt dem von
Hand gesetzten ersten Schultag.

Die mitgezogenen Kalenderfunktionen (`tagAusISO`, `montagDerWoche`,
`kalenderwoche`, `wochenListe`, `heute`) stehen dabei auch unmittelbar gegen
ModellPruefungen.swift (Regel: Modell/Tag.swift) — sonst bliebe ihr stiller
Umbau unbemerkt, solange nur die Schulwochen darüber noch aufgehen.

Die Funktionen werden per Klammerzählung aus `unterrichtsplanung-ansicht.html`
gezogen und mit `jsc` (JavaScriptCore, ohne Node) gegen dieselben Erwartungen
laufen gelassen. Jeder Fall beschreibt echte Ferienzeiträume; die Ferienlage
rechnet die Ansicht selbst, wie sie es zur Laufzeit tut. Läuft die Swift-Regel
davon, fällt dieses Skript — nicht erst eine Lehrkraft am iPad.

Aufruf:  python3 schulwochen_pruefen.py        (Ergebnis je Fall, Exit 0/1)
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

# Wie in den Swift-Prüfungen: Montag, acht Wochen.
START = "2026-08-10"

GELUNGEN = "Alle Faelle deckungsgleich mit der Swift-Regel."

# Fälle aus SchulwochenPruefungen.swift, dazu die von zwei Zeiträumen gemeinsam
# ganz bedeckte Woche: (Name, erster Schultag als ISO oder "", belegte Wochen,
# von Hand freigestellte Wochen, Ferienzeiträume als (erster, letzter) Tag ab
# START, erwartete Nummern — None = keine —, erwartete Lagen je Woche:
# "." Unterricht, Ziffer = angeschnittene Tage, "F" unterrichtsfrei).
FAELLE = [
    ("Ohne Ferien und ohne Vorhaben", "", [], [], [],
     [1, 2, 3, 4, 5, 6, 7, 8], "........"),
    ("Beginn beim ersten Vorhaben", "", [2], [], [],
     [None, None, 1, 2, 3, 4, 5, 6], "........"),
    ("Volle Ferienwoche zählt nicht", "", [0], [], [(21, 25)],
     [1, 2, 3, None, 4, 5, 6, 7], "...F...."),
    ("Angeschnittene Ferienwoche zählt mit", "", [0], [], [(16, 18)],
     [1, 2, 3, 4, 5, 6, 7, 8], "..3....."),
    # Ende vor Beginn: Keine der beiden Fassungen dreht den Zeitraum um, und der
    # Zeitraum bleibt dadurch überall wirkungslos.
    ("Ende vor Beginn wirkt nicht", "", [0], [], [(25, 21)],
     [1, 2, 3, 4, 5, 6, 7, 8], "........"),
    ("Von Hand freigestellt", "", [0], [1], [],
     [1, None, 2, 3, 4, 5, 6, 7], ".F......"),
    ("Sommerferien am Anfang", "", [2], [], [(0, 11)],
     [None, None, 1, 2, 3, 4, 5, 6], "FF......"),
    ("Vorhaben nur in Ferien", "", [0], [], [(0, 4)],
     [None, 1, 2, 3, 4, 5, 6, 7], "F......."),
    ("Alles Ferien", "", [], [], [(0, 53)],
     [None, None, None, None, None, None, None, None], "FFFFFFFF"),
    ("Zwei Zeiträume decken eine Woche gemeinsam ganz", "", [0],
     [], [(14, 16), (17, 18)], [1, 2, None, 3, 4, 5, 6, 7], "..F....."),
    ("Erster Schultag legt fest, Vorhaben zählen nicht",
     "2026-08-26", [0], [], [], [None, None, 1, 2, 3, 4, 5, 6], "........"),
    ("Erster Schultag, volle Ferienwoche ohne Nummer",
     "2026-08-17", [], [], [(21, 25)], [None, 1, 2, None, 3, 4, 5, 6],
     "...F...."),
    ("Erster Schultag in vollen Ferien: Woche danach ist die 1.",
     "2026-08-20", [], [], [(7, 11)], [None, None, 1, 2, 3, 4, 5, 6],
     ".F......"),
    ("Erster Schultag außerhalb: Herleitung greift",
     "2028-08-10", [2], [], [], [None, None, 1, 2, 3, 4, 5, 6], "........"),
    ("Erster Schultag am Sonntag ankert dieselbe Woche",
     "2026-08-30", [], [], [], [None, None, 1, 2, 3, 4, 5, 6], "........"),
    ("Unlesbarer erster Schultag: Herleitung greift",
     "kein-datum", [2], [], [], [None, None, 1, 2, 3, 4, 5, 6], "........"),
]

# Fälle aus ModellPruefungen.swift (Suite „Kalenderwochen nach ISO 8601"):
# Sie stellen die gezogenen Kalenderfunktionen selbst gegen die Swift-Regel —
# die Fälle oben prüfen nur, was auf ihnen aufbaut.

# `tagAusISO` gegen KalenderPruefungen.strengeForm und die Rückrechnung in
# `Tag(iso:)`: Eingabe → ISO-Form des Tages, None = kein Datum.
ISO_FAELLE = [
    ("2026-08-10", "2026-08-10"),
    ("2026-12-31", "2026-12-31"),
    ("2026-8-10", None),
    ("26-08-10", None),
    ("2026/08/10", None),
    ("", None),
    ("2026-08-10x", None),
    ("kein-datum", None),
    # Der Kalender rollt Unmögliches stillschweigend weiter; nur was die
    # Rückrechnung übersteht, ist ein Datum.
    ("2024-02-29", "2024-02-29"),
    ("2026-02-29", None),
    ("2026-02-31", None),
    ("2026-13-01", None),
    ("2026-08-32", None),
    ("2026-00-10", None),
    ("2026-08-00", None),
]

# `montagDerWoche` gegen KalenderPruefungen.montag: Tag → Montag seiner Woche.
MONTAG_FAELLE = [
    ("2026-08-12", "2026-08-10"),
    ("2026-08-16", "2026-08-10"),
    ("2026-08-10", "2026-08-10"),
    ("2027-01-01", "2026-12-28"),
]

# `wochentagISO` gegen ModellPruefungen.wochentage (`Tag.wochentag`): Montag = 1
# bis Freitag = 5, am Wochenende keiner — der Wochentag eines Vorhabens.
WOCHENTAG_FAELLE = [
    ("2026-08-10", 1),
    ("2026-08-12", 3),
    ("2026-08-14", 5),
    ("2026-08-15", None),
    ("2026-08-16", None),
    ("2027-01-01", 5),
]

# `kalenderwoche` gegen KalenderPruefungen.kalenderwoche: Tag → Kalenderwoche
# und ISO-Wochenjahr. 2026 hat 53 Wochen — der 01.01.2027 gehört noch dazu.
KW_FAELLE = [
    ("2026-08-10", 33, 2026),
    ("2026-01-01", 1, 2026),
    ("2027-01-01", 53, 2026),
    ("2024-12-31", 1, 2025),
]

# `wochenListe`, `isoVon` und `kurz` gegen KalenderPruefungen.wochenliste:
# Start, Anzahl, erwartete Montage, Freitag der ersten Woche, Kalenderwochen
# und Spanne der ersten Woche.
WOCHENLISTE = ("2026-08-12", 4,
               ["2026-08-10", "2026-08-17", "2026-08-24", "2026-08-31"],
               "2026-08-14", [33, 34, 35, 36], "10.08.–14.08.")


# `zeitstempelBrauchbar` gegen StatusPruefungen.zeitstempelGrenzfaelle: Der
# Stempel entscheidet im Statusabgleich, welcher Stand gilt — er muss deshalb
# hier und dort dieselben Werte gelten lassen. Beide Datumsleser sind
# verschieden nachsichtig (Foundation nimmt den 30. Februar, dieser hier die
# Schaltsekunde), darum prüfen beide Fassungen die Felder selbst.
STEMPEL_FAELLE = [
    ("2026-08-10T10:00:00.000Z", True),
    ("2026-02-30T10:00:00.000Z", False),   # 30. Februar
    ("2026-02-29T10:00:00.000Z", False),   # kein Schaltjahr
    ("2024-02-29T10:00:00.000Z", True),    # Schaltjahr
    ("2026-08-10T24:00:00.000Z", False),
    ("2026-08-10T10:60:00.000Z", False),
    ("2026-08-10T10:00:60.000Z", False),   # Schaltsekunde
    ("2026-08-10T10:00:00Z", False),       # ohne Bruchteile
    ("", False),
    ("2099-01-01T00:00:00.000Z", False),   # Zukunft
    ("1899-12-31T23:59:59.999Z", False),   # Jahresschranke wie `Tag(iso:)`
]


def main() -> int:
    if not JSC.exists():
        print(f"jsc nicht gefunden: {JSC}")
        return 1
    rumpf = pruefhilfen.skript(HTML)

    muster = re.search(r"const ISO_MUSTER = [^;]+;", rumpf)
    stempelmuster = re.search(r"const ZEITSTEMPEL_MUSTER = [^;]+;", rumpf)
    if not muster or not stempelmuster:
        print("ISO_MUSTER oder ZEITSTEMPEL_MUSTER nicht gefunden.")
        return 1
    teile = [muster.group(0), stempelmuster.group(0)] + [
        pruefhilfen.funktion(rumpf, name)
        for name in ("zwei", "plusTage", "montagDerWoche", "tagAusISO",
                     "isoVon", "kalenderwoche", "kurz", "heute",
                     "wochenListe", "zeitraumGueltig", "tageIn", "lage",
                     "schulwochen", "zeitstempelBrauchbar", "wochentagISO")]

    stempel_js = json.dumps(STEMPEL_FAELLE, ensure_ascii=False)
    faelle_js = ",\n".join(
        "  " + json.dumps([name, erster, belegt, frei, ferien, erwartet, lagen],
                          ensure_ascii=False)
        for name, erster, belegt, frei, ferien, erwartet, lagen in FAELLE)
    probe = "\n".join(teile) + f"""
const START = "{START}";
const start = tagAusISO(START);
const faelle = [
{faelle_js}
];
let fehler = 0;
for (const [name, erster, belegt, frei, ferien, erwartet, lagenSoll] of faelle) {{
  const wochen = wochenListe(START, erwartet.length);
  const planung = {{
    ersterSchultagISO: erster,
    eintraege: belegt.map((w) => ({{ woche: w }})),
    freiMenge: new Set(frei.map((i) => wochen[i].montagISO)),
    ferien: ferien.map(([von, bis], i) => ({{
      id: "f" + i,
      name: "Ferien " + (i + 1),
      von: isoVon(plusTage(start, von)),
      bis: isoVon(plusTage(start, bis)),
    }})),
  }};
  const lagen = wochen.map((w) => lage(planung, w));
  const lagenIst = lagen
    .map((l) => (l.frei ? "F" : l.teilweise ? String(l.tage) : ".")).join("");
  const ist = schulwochen(planung, wochen, lagen);
  const lagenOk = lagenIst === lagenSoll;
  const nummernOk = JSON.stringify(ist) === JSON.stringify(erwartet);
  if (lagenOk && nummernOk) {{
    print("  stimmt    " + name);
    continue;
  }}
  fehler += 1;
  print("  WEICHT AB " + name);
  if (!lagenOk) print("             Lagen   soll=" + lagenSoll
                      + "  ist=" + lagenIst);
  if (!nummernOk) print("             Nummern soll=" + JSON.stringify(erwartet)
                        + "  ist=" + JSON.stringify(ist));
}}
""" + f"""
// ── Die Kalenderfunktionen selbst (ModellPruefungen.swift) ────────────
const isoFaelle = {json.dumps(ISO_FAELLE, ensure_ascii=False)};
const montagFaelle = {json.dumps(MONTAG_FAELLE, ensure_ascii=False)};
const kwFaelle = {json.dumps(KW_FAELLE, ensure_ascii=False)};
const wochentagFaelle = {json.dumps(WOCHENTAG_FAELLE, ensure_ascii=False)};
const wochenFall = {json.dumps(WOCHENLISTE, ensure_ascii=False)};

function vergleiche(name, ist, soll) {{
  if (JSON.stringify(ist) === JSON.stringify(soll)) {{
    print("  stimmt    " + name);
    return 0;
  }}
  print("  WEICHT AB " + name);
  print("             soll=" + JSON.stringify(soll)
        + "  ist=" + JSON.stringify(ist));
  return 1;
}}

for (const [wert, soll] of isoFaelle) {{
  const tag = tagAusISO(wert);
  fehler += vergleiche('tagAusISO("' + wert + '")',
                       tag === null ? null : isoVon(tag), soll);
}}
for (const [wert, soll] of montagFaelle) {{
  fehler += vergleiche('montagDerWoche("' + wert + '")',
                       isoVon(montagDerWoche(tagAusISO(wert))), soll);
}}
for (const [wert, kw, jahr] of kwFaelle) {{
  const gerechnet = kalenderwoche(tagAusISO(wert));
  fehler += vergleiche('kalenderwoche("' + wert + '")',
                       [gerechnet.kw, gerechnet.jahr], [kw, jahr]);
}}
for (const [wert, soll] of wochentagFaelle) {{
  fehler += vergleiche('wochentagISO("' + wert + '")',
                       wochentagISO(tagAusISO(wert)), soll);
}}
const [wlStart, wlAnzahl, wlMontage, wlFreitag, wlKw, wlSpanne] = wochenFall;
const wlListe = wochenListe(wlStart, wlAnzahl);
fehler += vergleiche("wochenListe: Montage",
                     wlListe.map((w) => w.montagISO), wlMontage);
fehler += vergleiche("wochenListe: Freitag der ersten Woche",
                     wlListe[0].tage[4], wlFreitag);
fehler += vergleiche("wochenListe: Kalenderwochen",
                     wlListe.map((w) => w.kw), wlKw);
fehler += vergleiche("wochenListe: Spanne der ersten Woche",
                     wlListe[0].spanne, wlSpanne);
// `heute()` liest die Uhr: Wechselt der Tag zwischen den beiden Ablesungen,
// gilt jede von beiden.
const vorher = new Date();
const heutigerISO = isoVon(heute());
const nachher = new Date();
const ortstag = (d) => d.getFullYear() + "-" + zwei(d.getMonth() + 1)
                       + "-" + zwei(d.getDate());
fehler += vergleiche("heute() ist der Ortstag",
                     heutigerISO === ortstag(vorher)
                     || heutigerISO === ortstag(nachher), true);
fehler += vergleiche("heute() steht auf UTC-Mittag", heute().getUTCHours(), 12);

// ── Der Zeitstempel des Statusabgleichs (StatusPruefungen.swift) ──────
const stempelFaelle = {stempel_js};
for (const [wert, soll] of stempelFaelle) {{
  fehler += vergleiche('zeitstempelBrauchbar("' + wert + '")',
                       zeitstempelBrauchbar(wert), soll);
}}
""" + f"""
// `quit(1)` beendet jsc mit 0 — über Bestehen entscheidet die Schlusszeile.
if (fehler > 0) {{ print("ABWEICHUNGEN: " + fehler); }}
else {{ print("{GELUNGEN}"); }}
"""
    # Im Temporärordner, nicht versteckt im Fassungsordner: Der wird als
    # Ganzes ins Repository und ins Netz gestellt.
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as datei:
        datei.write(probe)
        ablage = Path(datei.name)
    try:
        lauf = subprocess.run([str(JSC), str(ablage)],
                              capture_output=True, text=True)
        print(lauf.stdout, end="")
        if lauf.stderr:
            print(lauf.stderr, end="", file=sys.stderr)
        return 0 if GELUNGEN in lauf.stdout.splitlines() else 1
    finally:
        ablage.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
