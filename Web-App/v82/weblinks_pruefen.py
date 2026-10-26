#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Rüstet die Messung von `linkPruefen` im echten Browser aus.

Weblinks sind die eine gemeinsame Regel, die sich **nicht** wie die anderen mit
`jsc` prüfen lässt: `jsc` ist die reine Sprachmaschine und kennt kein `URL`;
`linkPruefen` liefe dort in seinen Fangblock und wiese jede Adresse ab. Der
URL-Leser, auf den es ankommt, steckt im Browser — und genau dessen Urteil muss
mit `Weblinks.pruefen` der App übereinstimmen (`ModellPruefungen.swift`, Suite
„Weblinks prüfen“).

Dieses Skript rechnet selbst nichts nach. Es gibt einen fertigen Einzeiler aus,
der die Fälle aus `weblink_faelle.json` mitbringt (die Meta-CSP der Ansicht
erlaubt kein `fetch`) und in der Konsole des Browsers jede Abweichung nennt.

    python3 -m http.server           # in diesem Ordner
    python3 weblinks_pruefen.py      # Einzeiler ausgeben und einsetzen

**Mit Fragezeichen aufrufen** (`…-ansicht.html?frisch=1`): Der Browser hält die
Seite sonst im Zwischenspeicher, und gemessen wird die Fassung von vorhin — beim
Bauen dieser Messung genau einmal passiert, mit sechs Scheinabweichungen.

`--liste` gibt stattdessen die Fälle mit ihren Erwartungswerten aus.
**Neue Adresse = neuer Fall hier UND in ModellPruefungen.swift.**
"""

import json
import sys
from pathlib import Path

HIER = Path(__file__).resolve().parent
FAELLE = HIER / "weblink_faelle.json"


def main() -> int:
    if not FAELLE.exists():
        print(f"Fallsammlung nicht gefunden: {FAELLE}")
        return 1
    daten = json.loads(FAELLE.read_text(encoding="utf-8"))
    faelle = daten["faelle"]

    if "--liste" in sys.argv:
        for adresse, soll in faelle.items():
            print(f"  {adresse!r:52} -> {soll!r}")
        print(f"\n{len(faelle)} Faelle.")
        return 0

    einzeiler = (
        "(() => { const S = " + json.dumps(faelle, ensure_ascii=False)
        + "; const ab = []; for (const [f, soll] of Object.entries(S)) {"
        " let r; try { r = linkPruefen(f); } catch (e) { r = 'AUSNAHME: ' + e.message; }"
        " if (r !== soll) ab.push([f, soll, r]); }"
        " return ab.length ? ab : 'alle ' + Object.keys(S).length"
        " + ' Adressen deckungsgleich mit der App'; })()")

    print("Die Ansicht ueber einen lokalen Server oeffnen "
          "(python3 -m http.server) und diesen Einzeiler in die Konsole "
          f"einsetzen — {len(faelle)} Faelle:\n")
    print(einzeiler)
    print("\nErwartet: „alle … Adressen deckungsgleich mit der App“. "
          "Jede genannte Adresse ist ein Paritaetsbefund.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
