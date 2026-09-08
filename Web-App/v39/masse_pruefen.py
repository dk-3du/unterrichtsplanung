#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Stellt die Zahlen und Namen, die in BEIDEN Fassungen stehen müssen, gegen
den Quelltext der App (macOS-App/vNN/Quellen/…).

Anders als `leser_pruefen.py` und `schulwochen_pruefen.py` läuft hier kein
JavaScript: Verglichen werden die Festwerte selbst — Obergrenzen des Lesers,
Dateigrenzen, Druckmaße, die Rasten des Breitenreglers, Datei- und Typnamen.
Das ist die Sorte Abweichung, die still bleibt: Der Bau ist grün, die Prüfungen
sind grün (sie kennen je nur eine Seite), und trotzdem kappt die eine Fassung,
wo die andere durchlässt.

Das Beispiel dafür: Übernimmt die Ansicht `Druckmasse` als **Zahl ohne
Einheit**, rechnet die App in Punkt (72 je Zoll), eine Webseite aber in
CSS-Pixeln (96 je Zoll) — aus denselben 150 und 190 werden hier vier Wochen je
Blatt und dort drei. Kein Skript sieht das, solange keines die beiden Zahlen
nebeneinanderlegt.

**Neuer gemeinsamer Festwert = neue Zeile in `PAARE`.**

Aufruf:  python3 masse_pruefen.py        (Ergebnis je Wert, Exit 0/1)
"""

import ast
import re
import sys
from pathlib import Path

HIER = Path(__file__).resolve().parent
HTML = HIER / "unterrichtsplanung-ansicht.html"
# …/Web-App/vNN → …/macOS-App/vNN
APP = HIER.parent.parent / "macOS-App" / HIER.name / "Quellen" / "Unterrichtsplanung"

GELUNGEN = "Alle gemeinsamen Festwerte stimmen mit der App ueberein."

# (Anzeigename, Swift-Datei, Swift-Name, JS-Name, Umrechnung)
#
# Verglichen wird der Text hinter `static let <name> =` mit dem hinter
# `const <name> =`; beide werden als Produkt/Quotient von Zahlen und bekannten
# Namen ausgerechnet (siehe `zahl`), damit auch `32 * 1024 * 1024` und
# `150 * PIXEL_JE_PUNKT` vergleichbar sind.
PAARE = [
    ("Klassen/Kurse je Datei", "Modell/Planung.swift", "maxKlassen",
     "MAX_KLASSEN", 1),
    ("Wochen, Obergrenze", "Modell/Planung.swift", "wochenMax",
     "WOCHEN_MAX", 1),
    ("Wochen, Standard", "Modell/Planung.swift", "wochenStandard",
     "WOCHEN_STANDARD", 1),
    ("Vorhaben je Datei", "Modell/Planungsdatei.swift", "maxVorhaben",
     "MAX_VORHABEN", 1),
    ("Materialien je Vorhaben", "Modell/Planungsdatei.swift", "maxMaterialien",
     "MAX_MATERIALIEN", 1),
    ("Links je Vorhaben", "Modell/Planungsdatei.swift", "maxLinks",
     "MAX_LINKS", 1),
    ("Beschreibung und Kommentar", "Modell/Planungsdatei.swift", "maxTextlaenge",
     "MAX_TEXTLAENGE", 1),
    ("Titel, Namen, Kennungen", "Modell/Planungsdatei.swift", "maxNamenslaenge",
     "MAX_NAMENSLAENGE", 1),
    ("Dateiverweise", "Modell/Planungsdatei.swift", "maxPfadlaenge",
     "MAX_PFADLAENGE", 1),
    ("Fachfarben je Datei", "Modell/Planungsdatei.swift", "maxFachfarben",
     "MAX_FACHFARBEN", 1),
    ("Ferienzeitraeume", "Modell/Planungsdatei.swift", "maxFerien",
     "MAX_FERIEN", 1),
    ("Sperrzeitraeume", "Modell/Planungsdatei.swift", "maxSperrzeiten",
     "MAX_SPERRZEITEN", 1),
    ("Freie Tage", "Modell/Planungsdatei.swift", "maxFreieTage",
     "MAX_FREIE_TAGE", 1),
    ("Planungsdatei, Groesse", "Speicher/Planungsspeicher+Dateien.swift",
     "hoechstePlanungsgroesse", "MAX_DATEIGROESSE", 1),
    ("Statusdatei, Groesse", "Modell/Statusdatei.swift", "hoechstgroesse",
     "MAX_STATUSGROESSE", 1),
    # Die App misst in Punkt, die Seite in CSS-Pixeln: 96/72.
    ("Druck, Kursspalte", "Dienste/Drucken.swift", "spalteKlasse",
     "DRUCK_SPALTE_KLASSE", 96 / 72),
    ("Druck, Wochenspalte", "Dienste/Drucken.swift", "spalteWoche",
     "DRUCK_SPALTE_WOCHE", 96 / 72),
    # Der Tresor: Beide Seiten öffnen denselben Behälter.
    ("Tresor, Fassung des Behaelters", "Dienste/Tresor.swift", "version",
     "TRESOR_VERSION", 1),
    ("Tresor, Runden mindestens", "Dienste/Tresor.swift", "rundenMindestens",
     "TRESOR_RUNDEN_MINDESTENS", 1),
    ("Tresor, Runden hoechstens", "Dienste/Tresor.swift", "rundenHoechstens",
     "TRESOR_RUNDEN_HOECHSTENS", 1),
    ("Tresor, Passphrase mindestens", "Dienste/Tresor.swift", "passphraseMindestlaenge",
     "TRESOR_PASSPHRASE_MINDESTLAENGE", 1),
    ("Tresor, Kennung (Byte)", "Dienste/Tresor.swift", "kennungLaenge",
     "TRESOR_KENNUNG_LAENGE", 1),
    ("Tresor, Wiederherstellung (Byte)", "Dienste/Tresor.swift", "wiederherstellungLaenge",
     "TRESOR_WIEDERHERSTELLUNG_LAENGE", 1),
]

# Namen und Kennungen, die wortgleich sein müssen.
NAMENSPAARE = [
    ("Dateityp", "Modell/Planung.swift", "dateiTyp", "DATEITYP"),
    ("Dateiversion", "Modell/Planung.swift", "dateiVersion", "DATEIVERSION"),
    ("Statusdatei, Name", "Modell/Statusdatei.swift", "name", "STATUS_DATEINAME"),
    ("Statusdatei, Typ", "Modell/Statusdatei.swift", "typ", "STATUS_TYP"),
    ("Tresor, Typ", "Dienste/Tresor.swift", "typ", "TRESOR_TYP"),
    ("Tresor, Verfahren", "Dienste/Tresor.swift", "verfahren", "TRESOR_VERFAHREN"),
    ("Tresor, KDF Passphrase", "Dienste/Tresor.swift", "kdfPassphrase", "TRESOR_KDF_PASSPHRASE"),
    ("Tresor, KDF Wiederherstellung", "Dienste/Tresor.swift", "kdfWiederherstellung",
     "TRESOR_KDF_WIEDERHERSTELLUNG"),
    ("Tresor, Base32-Alphabet", "Dienste/Tresor.swift", "wiederherstellungAlphabet",
     "TRESOR_WIEDERHERSTELLUNG_ALPHABET"),
]


def wochentage_pruefen(rumpf: str) -> list:
    """„Mo.“ … „Fr.“ und „Montag“ … „Freitag“: `Wochentag.kurz`/`.lang` gegen
    `WOCHENTAGE` — Literale auf beiden Seiten."""
    quelle = (APP / "Modell/Tag.swift").read_text(encoding="utf-8")
    aus = []
    for feld in ("kurz", "lang"):
        swift = re.search(rf"var {feld}: String \{{\s*\[([^\]]+)\]", quelle)
        js = re.findall(rf'{feld}: "([^"]+)"', rumpf.split("const WOCHENTAGE = [", 1)[1]
                        .split("];", 1)[0])
        links = re.findall(r'"([^"]+)"', swift.group(1)) if swift else None
        if links != js:
            aus.append(f"Wochentage ({feld}): App {links!r}, Ansicht {js!r}")
    return aus


def fassung_pruefen(rumpf: str) -> list:
    """`VERSION`/`VERSIONSSTUFE` der Ansicht gegen die Info.plist der App —
    das Info-Blatt nennt dieselbe Fassung wie „Über“; dazu `QUELLTEXT` gegen
    `UPQuelltext`, die Adresse des Repositorys."""
    import plistlib
    plist = APP.parent.parent / "Beiwerk" / "Info.plist"
    with plist.open("rb") as datei:
        werte = plistlib.load(datei)
    aus = []
    for anzeige, schluessel, jsname in (("Fassung", "CFBundleShortVersionString", "VERSION"),
                                        ("Stufe", "CFBundleVersion", "VERSIONSSTUFE"),
                                        ("Quelltextadresse", "UPQuelltext", "QUELLTEXT")):
        links = str(werte.get(schluessel, ""))
        rechts = js_wert(rumpf, jsname).strip('"')
        if links != rechts:
            aus.append(f"{anzeige}: App {links!r}, Ansicht {rechts!r}")
    return aus


def swift_wert(datei: str, name: str) -> str:
    quelle = (APP / datei).read_text(encoding="utf-8")
    treffer = re.search(rf"static (?:let|var) {name}(?:\s*:[^=]+)?\s*=\s*(.+)", quelle)
    if not treffer:
        raise SystemExit(f"Nicht gefunden in {datei}: static let {name}")
    return treffer.group(1).split("//")[0].strip()


def js_wert(quelle: str, name: str) -> str:
    treffer = re.search(rf"const {name} = ([^;]+);", quelle)
    if not treffer:
        raise SystemExit(f"Nicht gefunden in der Ansicht: const {name}")
    return treffer.group(1).strip()


def zahl(ausdruck: str, umgebung: dict) -> float:
    """Zahlen, bekannte Namen, Mal und Geteilt — mehr steht in keinem der
    verglichenen Werte, und mehr soll hier auch nicht ausgeführt werden."""

    def wert(knoten):
        if isinstance(knoten, ast.Constant) and isinstance(knoten.value, (int, float)):
            return float(knoten.value)
        if isinstance(knoten, ast.Name):
            if knoten.id not in umgebung:
                raise SystemExit(f"Unbekannter Name im Ausdruck: {knoten.id}")
            return float(umgebung[knoten.id])
        if isinstance(knoten, ast.BinOp) and isinstance(knoten.op, (ast.Mult, ast.Div)):
            links, rechts = wert(knoten.left), wert(knoten.right)
            return links * rechts if isinstance(knoten.op, ast.Mult) else links / rechts
        raise SystemExit(f"Nicht auswertbarer Ausdruck: {ausdruck}")

    # Nur die Zifferngruppierung der Swift-Literale (20_000), nicht die
    # Unterstriche in Namen.
    ohneGruppen = re.sub(r"(?<=\d)_(?=\d)", "", ausdruck)
    return wert(ast.parse(ohneGruppen, mode="eval").body)


def reglerstufen_pruefen(html: str) -> list:
    """Die Rasten des Breitenreglers: `[data-breite="…"]` gegen `Kennwerte`."""
    aus = []
    mini = zahl(swift_wert("Modell/Planung.swift", "spalteMin"), {})
    maxi = zahl(swift_wert("Modell/Planung.swift", "spalteMax"), {})
    stufen = int(zahl(swift_wert("Modell/Planung.swift", "spalteStufen"), {}))
    raster = (maxi - mini) / (stufen - 1)
    soll = [mini + i * raster for i in range(stufen)]

    ist = sorted(float(w) for w in
                 re.findall(r'\[data-breite="(\d+)"\] \{ --spalte-woche', html))
    if ist != soll:
        aus.append(f"Reglerstufen: App {soll}, Ansicht {ist}")

    feld = re.search(r'id="breite" min="(\d+)" max="(\d+)" step="(\d+)"', html)
    if not feld:
        aus.append("Regler: `input#breite` nicht gefunden")
    elif [float(feld.group(1)), float(feld.group(2)), float(feld.group(3))] \
            != [mini, maxi, raster]:
        aus.append(f"Regler: App min/max/Raster {mini:g}/{maxi:g}/{raster:g}, "
                   f"Ansicht {feld.group(1)}/{feld.group(2)}/{feld.group(3)}")

    rasten = re.search(r'<div class="rasten" aria-hidden="true">(.*?)</div>', html)
    if not rasten:
        aus.append("Regler: Rastpunkte nicht gefunden")
    elif rasten.group(1).count("<i>") != stufen:
        aus.append(f"Rastpunkte: App {stufen}, Ansicht "
                   f"{rasten.group(1).count('<i>')}")

    standard = zahl(swift_wert("Modell/Planung.swift", "spalteStandard"), {})
    koerper = re.search(r'<body data-thema="hell" data-breite="(\d+)">', html)
    if not koerper:
        aus.append("Regler: Ausgangsstufe am `body` nicht gefunden")
    elif float(koerper.group(1)) != standard:
        aus.append(f"Ausgangsstufe: App {standard:g}, Ansicht {koerper.group(1)}")
    return aus


def main() -> int:
    if not HTML.exists():
        print(f"Ansichtsfassung nicht gefunden: {HTML}")
        return 1
    if not APP.exists():
        print(f"Quellen der App nicht gefunden: {APP}")
        return 1
    html = HTML.read_text(encoding="utf-8")
    skript = re.search(r"<script>(.*?)</script>", html, re.S)
    if not skript:
        print("Kein Skriptblock in der HTML gefunden.")
        return 1
    rumpf = skript.group(1)

    fehler = 0
    umgebung = {"PIXEL_JE_PUNKT": 96 / 72}
    for name in ("WOCHEN_MAX", "MAX_KLASSEN"):
        umgebung[name] = zahl(js_wert(rumpf, name), umgebung)

    for anzeige, datei, swiftname, jsname, faktor in PAARE:
        links = zahl(swift_wert(datei, swiftname), {}) * faktor
        rechts = zahl(js_wert(rumpf, jsname), umgebung)
        if links == rechts:
            print(f"  stimmt    {anzeige} ({links:g})")
        else:
            fehler += 1
            print(f"  ABWEICHUNG {anzeige}: App {links:g}, Ansicht {rechts:g}")

    for anzeige, datei, swiftname, jsname in NAMENSPAARE:
        links = swift_wert(datei, swiftname).strip('"')
        rechts = js_wert(rumpf, jsname).strip('"')
        if links == rechts:
            print(f"  stimmt    {anzeige} ({links})")
        else:
            fehler += 1
            print(f"  ABWEICHUNG {anzeige}: App {links!r}, Ansicht {rechts!r}")

    reglermeldungen = reglerstufen_pruefen(html)
    for meldung in reglermeldungen:
        fehler += 1
        print(f"  ABWEICHUNG {meldung}")
    if not reglermeldungen:
        print("  stimmt    Breitenregler (Stufen, Grenzen, Rastpunkte, Ausgang)")

    for name, pruefung in (("Wochentage (kurz, lang)", wochentage_pruefen),
                           ("Fassung und Stufe (Info.plist)", fassung_pruefen)):
        meldungen = pruefung(rumpf)
        for meldung in meldungen:
            fehler += 1
            print(f"  ABWEICHUNG {meldung}")
        if not meldungen:
            print(f"  stimmt    {name}")

    if fehler:
        print(f"\n{fehler} gemeinsame Festwerte weichen von der App ab.")
        return 1
    print(f"\n{GELUNGEN}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
