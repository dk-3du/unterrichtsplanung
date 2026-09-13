#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Erzeugt die Symbole der Ansichtsfassung aus dem App-Symbol der macOS-App.

Quelle ist dasselbe Bündel, aus dem das Programmsymbol entsteht:
`Beiwerk/AppIcon.icon` der macOS-App — die SVG-Ebenen und `icon.json`, aus
**derselben Fassung** wie dieses Skript (`../../macOS-App/<vN>/`, der Name des
Ordners, in dem es liegt). Ein anderes Bündel nennt `--buendel`.

    python3 symbole_bauen.py            baut alle Symbole nach symbol/
    python3 symbole_bauen.py --pruefen  meldet nur, ob sie noch zur Quelle passen
    python3 symbole_bauen.py --buendel PFAD   aus einem anderen AppIcon.icon

Auf dem iPad zeichnet das System für ein Web-Symbol **kein** Liquid Glass — es
bekommt eine flache Rastergrafik und rundet sie selbst. Deshalb werden die
Ebenen hier zusammengelegt und gerastert, mit dem Verlauf aus `icon.json` als
Grund und dem Schlagschatten unter dem Buch.

Gerastert wird mit `qlmanage` (Quick Look), verkleinert mit Pillow.
"""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HIER = Path(__file__).resolve().parent
APPWURZEL = HIER.parent.parent / "macOS-App"
ZIEL = HIER / "symbol"


def eigenesSymbolbuendel(wurzel=APPWURZEL):
    """Das Symbolbündel der Fassung, zu der dieses Skript gehört — `HIER.name`
    ist der Fassungsordner (`v43`). Die höchste Fassung wäre nach dem nächsten
    Versionssprung eine andere, und eine ältere Fassung baute aus fremdem Symbol.
    """
    buendel = wurzel / HIER.name / "Beiwerk" / "AppIcon.icon"
    return buendel if buendel.is_dir() else None


SYMBOLBUENDEL = eigenesSymbolbuendel()

SCHATTENEBENE = "buch.svg"

# 180 iOS-Home-Bildschirm, 167/152 ältere iPads, 192/512 Manifest, 32 Browser-Tab.
GROESSEN = {
    "touch-180.png": 180,
    "touch-167.png": 167,
    "touch-152.png": 152,
    "symbol-192.png": 192,
    "symbol-512.png": 512,
    "symbol-32.png": 32,
}

RUMPF = """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" \
viewBox="0 0 1024 1024" fill="none">
<!-- Erzeugt von symbole_bauen.py aus %s — nicht von Hand ändern. -->
<defs>
%s
<filter id="schatten" x="46" y="12" width="932" height="1018" \
filterUnits="userSpaceOnUse">
<feDropShadow dx="0" dy="38" stdDeviation="32" flood-color="#24135D" \
flood-opacity=".35"/>
</filter>
</defs>
%s
</svg>
"""


def inneres(svg_text):
    """Trennt den Inhalt einer Ebene in (defs, Zeichnung)."""
    ohne_wurzel = re.sub(r"^.*?<svg[^>]*>", "", svg_text, count=1, flags=re.S)
    ohne_wurzel = re.sub(r"</svg>\s*$", "", ohne_wurzel, flags=re.S)
    defs = "".join(re.findall(r"<defs>(.*?)</defs>", ohne_wurzel, flags=re.S))
    zeichnung = re.sub(r"<defs>.*?</defs>", "", ohne_wurzel, flags=re.S)
    return defs.strip(), zeichnung.strip()


def beschreibung():
    """Der Inhalt von `icon.json` — Verlauf und Ebenenfolge in einem."""
    return json.loads((SYMBOLBUENDEL / "icon.json").read_text(encoding="utf-8"))


def ebenen(daten):
    """Die Ebenennamen von unten nach oben.

    Gelesen statt verdrahtet: gegen eine eigene Liste geprüft, bliebe eine dem
    App-Symbol hinzugefügte Ebene auch im Prüfmodus unbemerkt. `icon.json` führt
    Gruppen wie Ebenen von oben nach unten, deshalb beide umgekehrt.
    """
    namen = []
    for gruppe in reversed(daten.get("groups", [])):
        for ebene in reversed(gruppe.get("layers", [])):
            name = ebene.get("image-name")
            if name:
                namen.append(name)
    if not namen:
        raise SystemExit("FEHLER: %s nennt keine Ebene." % (SYMBOLBUENDEL / "icon.json"))
    return namen


def zusammenlegen(namen):
    """Baut aus den Ebenen eine einzige SVG-Zeichnung."""
    alle_defs = []
    alle_zeichnungen = []
    for name in namen:
        pfad = SYMBOLBUENDEL / "Assets" / name
        if not pfad.is_file():
            raise SystemExit("FEHLER: Ebene fehlt: %s" % pfad)
        defs, zeichnung = inneres(pfad.read_text(encoding="utf-8"))
        if defs:
            alle_defs.append(defs)
        if name == SCHATTENEBENE:
            zeichnung = '<g filter="url(#schatten)">\n%s\n</g>' % zeichnung
        alle_zeichnungen.append("<!-- %s -->\n%s" % (name, zeichnung))
    return RUMPF % (SYMBOLBUENDEL.name, "\n".join(alle_defs), "\n".join(alle_zeichnungen))


def grundfarbe(daten):
    """Die Füllfarbe aus icon.json — der Grund, auf den flach gerechnet wird."""
    roh = daten.get("fill", {}).get("automatic-gradient", "")
    zahlen = re.findall(r"[\d.]+", roh.split(":")[-1])
    if len(zahlen) < 3:
        return (255, 255, 255)
    return tuple(round(float(z) * 255) for z in zahlen[:3])


def rastern(svg_text, ordner):
    """SVG → PNG mit 1024 Punkten Kantenlänge, über Quick Look."""
    quelle = ordner / "symbol.svg"
    quelle.write_text(svg_text, encoding="utf-8")
    subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", str(ordner), str(quelle)],
                   check=True, capture_output=True)
    abzug = ordner / "symbol.svg.png"
    if not abzug.is_file():
        raise SystemExit("FEHLER: Quick Look hat kein Bild geliefert.")
    return abzug


def ablegen(abzug, grund, nur_pruefen):
    """Verkleinert auf alle gebrauchten Maße. Gibt True zurück, wenn alles passt."""
    try:
        from PIL import Image
    except ImportError:
        raise SystemExit("FEHLER: Pillow fehlt. Installieren mit: python3 -m pip install pillow")

    with Image.open(abzug) as bild:
        # Ein Symbol mit Alphakanal zeigt iOS auf schwarzem Grund.
        flach = Image.new("RGB", bild.size, grund)
        flach.paste(bild, mask=bild.getchannel("A") if bild.mode == "RGBA" else None)

        alles_gleich = True
        for name, kante in GROESSEN.items():
            klein = flach.resize((kante, kante), Image.LANCZOS)
            ziel = ZIEL / name
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as zwischen:
                klein.save(zwischen.name, "PNG", optimize=True)
                neu = Path(zwischen.name).read_bytes()
            if nur_pruefen:
                alt = ziel.read_bytes() if ziel.is_file() else b""
                gleich = hashlib.sha256(alt).digest() == hashlib.sha256(neu).digest()
                print("  %-16s %s" % (name, "aktuell" if gleich else ">>> weicht ab <<<"))
                alles_gleich &= gleich
            else:
                ZIEL.mkdir(exist_ok=True)
                ziel.write_bytes(neu)
                print("  %-16s %4d × %-4d  %6.1f KB" % (name, kante, kante, len(neu) / 1024))
            Path(zwischen.name).unlink(missing_ok=True)
    return alles_gleich


def main():
    zerleger = argparse.ArgumentParser(
        description="Erzeugt die Symbole der Ansichtsfassung aus dem App-Symbol.")
    zerleger.add_argument("--pruefen", action="store_true",
                          help="nur melden, ob die Symbole noch zur Quelle passen")
    zerleger.add_argument("--buendel", type=Path,
                          help="ein anderes AppIcon.icon statt dem der eigenen Fassung")
    argumente = zerleger.parse_args()

    global SYMBOLBUENDEL
    if argumente.buendel is not None:
        SYMBOLBUENDEL = argumente.buendel.resolve()
    if SYMBOLBUENDEL is None or not SYMBOLBUENDEL.is_dir():
        raise SystemExit(
            "FEHLER: kein Symbolbündel unter %s — erwartet %s/%s/Beiwerk/AppIcon.icon "
            "oder --buendel." % (APPWURZEL, APPWURZEL, HIER.name))

    daten = beschreibung()
    namen = ebenen(daten)
    print("Quelle: %s (%s)" % (SYMBOLBUENDEL, ", ".join(namen)))
    svg = zusammenlegen(namen)
    grund = grundfarbe(daten)

    ordner = Path(tempfile.mkdtemp())
    try:
        abzug = rastern(svg, ordner)
        heil = ablegen(abzug, grund, argumente.pruefen)
    finally:
        shutil.rmtree(ordner, ignore_errors=True)

    if argumente.pruefen and not heil:
        print("\nDie Symbole passen nicht mehr zur Quelle. Beheben mit:")
        print("  python3 %s" % Path(__file__).name)
        return 1
    print("\nFertig." if not argumente.pruefen else "\nAlle Symbole sind aktuell.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
