#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Prüft und schreibt die CSP-Hashes der Ansichtsfassung.

Die Seite trägt eine Content-Security-Policy als <meta http-equiv>, die nur die
SHA-256-Prüfsummen der eigenen Inline-Blöcke erlaubt. Ändert sich an einem Block
auch nur ein Leerzeichen, führt der Browser ihn **stillschweigend nicht mehr
aus** — der Hinweis steht allein in der Entwicklerkonsole.

  python3 csp_hashes.py                 prüft die Ansichtsfassung (ändert nichts)
  python3 csp_hashes.py --schreiben     trägt die aktuellen Hashes ein
  python3 csp_hashes.py datei.html …    prüft stattdessen die genannten Dateien

Fehlt die Datei lose im Ordner, wird sie in einem gleichnamigen ZIP daneben
gesucht und von dort geprüft; geschrieben wird nie in ein ZIP. Rückgabewert 0,
wenn alle Hashes stimmen — so lässt sich der Aufruf vor einem Upload einhängen.

Warum ein HTML-Parser und kein regulärer Ausdruck: <script>(.*?)</script> findet
auch die Wörter im Kommentar über dem Meta-Tag und liefert falsche Hashes. Aus
demselben Grund kommt auch das Meta-Tag selbst aus dem Parser — ein Muster über
den Rohtext träfe ein auskommentiertes zweites Tag und trüge die neuen Hashes
dort ein, während die wirksame Policy veraltet stehen bliebe.

--schreiben sichert die bisherige Fassung in einen privaten Temporaerordner
(mkdtemp, kein vorhersagbarer Pfad) und setzt die neue ueber eine unvorhersagbar
benannte Nachbardatei (mkstemp im selben Ordner) per os.replace an ihre Stelle;
ein Abbruch mittendrin laesst die alte Datei unversehrt.

Gehasht wird, was der Browser hasht: Sein Tokenizer macht aus CR LF und einem
einzelnen CR ein LF, bevor er den Blockinhalt sieht — eine Datei mit
Windows-Zeilenenden traegt deshalb dieselben Hashes wie mit Unix-Zeilenenden.

Nur Standardbibliothek. Geprüft mit Python 3.9.6 und 3.14.7 (auch python3.14t).
"""

import argparse
import base64
import hashlib
import os
import re
import shutil
import sys
import tempfile
import zipfile
from collections import namedtuple
from html.parser import HTMLParser
from pathlib import Path

STANDARDDATEIEN = ('unterrichtsplanung-ansicht.html',)

#: Ein gefundenes CSP-Meta-Tag samt seiner Fundstelle im Quelltext.
Policytag = namedtuple('Policytag', 'inhalt attribute zeile spalte roh')


class BlockSammler(HTMLParser):
    """Sammelt den Textinhalt aller Inline-Skript- und -Stilblöcke — genau den
    Text zwischen Start- und Endtag, über den auch der Browser den Hash bildet —
    sowie jedes Content-Security-Policy-Meta-Tag mit seiner Fundstelle.
    """

    def __init__(self):
        super().__init__()
        self._offen = None
        self._puffer = []
        self._zeile = 0
        self.bloecke = []
        self.policytags = []

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self._offen = tag
            self._puffer = []
            self._zeile = self.getpos()[0]
        elif tag == 'meta':
            merkmale = {name.lower(): (wert or '') for name, wert in attrs}
            if merkmale.get('http-equiv', '').lower() == 'content-security-policy':
                zeile, spalte = self.getpos()
                self.policytags.append(Policytag(
                    merkmale.get('content', ''), attrs, zeile, spalte,
                    self.get_starttag_text()))

    def handle_endtag(self, tag):
        if tag in ('script', 'style') and self._offen == tag:
            self.bloecke.append((tag, ''.join(self._puffer), self._zeile))
            self._offen = None

    def handle_data(self, text):
        if self._offen:
            self._puffer.append(text)


def lesen(pfad):
    """Liest die Datei ohne Zeilenende-Umwandlung – der Browser sieht sie genauso."""
    with open(pfad, 'r', encoding='utf-8', newline='') as datei:
        return datei.read()


def aus_zip_lesen(zip_pfad, name):
    """Holt eine HTML-Datei aus dem Offline-Paket, ohne sie auszupacken."""
    with zipfile.ZipFile(zip_pfad) as paket:
        eintraege = [e for e in paket.namelist()
                     if not e.startswith('__MACOSX/') and e.rsplit('/', 1)[-1] == name]
        if not eintraege:
            return None
        return paket.read(eintraege[0]).decode('utf-8')


def quelle_bestimmen(pfad):
    """Liefert (Quelltext, Beschriftung, aus_zip) – notfalls aus dem Offline-Paket."""
    if pfad.is_file():
        return lesen(pfad), pfad.name, False

    paket = pfad.with_suffix('.zip')
    if paket.is_file():
        inhalt = aus_zip_lesen(paket, pfad.name)
        if inhalt is not None:
            return inhalt, '%s (aus %s)' % (pfad.name, paket.name), True

    return None, pfad.name, False


def zeilenenden(text):
    """Wie der HTML-Tokenizer: CR LF und einzelnes CR werden LF."""
    return text.replace('\r\n', '\n').replace('\r', '\n')


def hashwert(text):
    """SHA-256 über den Blockinhalt, in der Schreibweise der CSP."""
    roh = hashlib.sha256(zeilenenden(text).encode('utf-8')).digest()
    return 'sha256-' + base64.b64encode(roh).decode('ascii')


def bloecke_lesen(quelltext):
    """Liefert {'script': [hash, …], 'style': […]}, Fundstellen und CSP-Tags."""
    sammler = BlockSammler()
    sammler.feed(quelltext)
    sammler.close()

    nach_tag = {'script': [], 'style': []}
    fundstellen = []
    for tag, text, zeile in sammler.bloecke:
        if not text.strip():
            continue                      # <script src="…"> hat keinen Inhalt
        wert = hashwert(text)
        nach_tag[tag].append(wert)
        fundstellen.append((tag, wert, zeile))
    return nach_tag, fundstellen, sammler.policytags


def policy_lesen(policytags, pfad):
    """Liefert das eine CSP-Meta-Tag; bei keinem oder mehreren bricht der Lauf ab."""
    if not policytags:
        raise SystemExit(
            'FEHLER: %s enthält kein Content-Security-Policy-Meta-Tag.' % pfad.name)
    if len(policytags) > 1:
        zeilen = ', '.join(str(tag.zeile) for tag in policytags)
        raise SystemExit(
            'FEHLER: %s enthält mehrere Content-Security-Policy-Meta-Tags '
            '(Zeilen %s) — welches gilt, ist nicht zu entscheiden.'
            % (pfad.name, zeilen))
    return policytags[0]


def direktive_setzen(policy, name, hashes):
    """Ersetzt in der genannten Direktive nur die Hashes; andere Quellen darin
    ('self', eine Adresse, ein Nonce) bleiben stehen, die übrige Policy ebenso."""
    teile = [t.strip() for t in policy.split(';') if t.strip()]
    for i, teil in enumerate(teile):
        worte = teil.split()
        if worte[0].lower() == name:
            fremde = [w for w in worte[1:] if not w.startswith("'sha256-")]
            teile[i] = ' '.join([name] + fremde + ["'%s'" % h for h in hashes])
            break
    else:
        teile.append(name + ' ' + ' '.join("'%s'" % h for h in hashes))
    return '; '.join(teile)


def hashes_der_policy(policy, name):
    for teil in policy.split(';'):
        teil = teil.strip()
        if teil and teil.split()[0].lower() == name:
            return re.findall(r"'(sha256-[^']+)'", teil)
    return []


def pruefen(beschriftung, quelltext, nach_tag, fundstellen, policy):
    """Gibt True zurück, wenn Policy und Datei zusammenpassen."""
    print('%s' % beschriftung)
    heil = True

    for tag, direktive in (('script', 'script-src'), ('style', 'style-src')):
        eingetragen = hashes_der_policy(policy, direktive)
        berechnet = nach_tag[tag]

        for t, wert, zeile in fundstellen:
            if t != tag:
                continue
            if wert in eingetragen:
                zustand = 'in der Policy'
            else:
                zustand = '>>> FEHLT in %s <<<' % direktive
                heil = False
            print('  Zeile %4d  %-6s %s  %s' % (zeile, tag, wert, zustand))

        for ueberzaehlig in [h for h in eingetragen if h not in berechnet]:
            print('  %-11s %-6s %s  >>> steht in %s, gehoert zu keinem Block <<<'
                  % ('', tag, ueberzaehlig, direktive))
            heil = False

    print('  Ergebnis: %s\n' % ('alle Hashes gueltig' if heil else 'Policy passt NICHT zur Datei'))
    return heil


def tagspanne(quelltext, tag):
    """Liefert (Anfang, Ende) des Meta-Tags als Index in den Quelltext."""
    anfang = 0
    for _ in range(tag.zeile - 1):
        anfang = quelltext.index('\n', anfang) + 1
    anfang += tag.spalte
    ende = anfang + len(tag.roh)
    if quelltext[anfang:ende] != tag.roh:
        raise SystemExit('FEHLER: Die Fundstelle des Meta-Tags liegt nicht, '
                         'wo der Parser sie meldet — nichts geschrieben.')
    return anfang, ende


def metatag_bauen(attribute, neue_policy):
    """Baut das Meta-Tag mit neuer Policy neu, in der Reihenfolge der Attribute."""
    teile = []
    for name, wert in attribute:
        if name.lower() == 'content':
            wert = neue_policy
        wert = (wert or '').replace('&', '&amp;').replace('"', '&quot;')
        teile.append('%s="%s"' % (name, wert))
    return '<meta ' + ' '.join(teile) + '>'


def ersetzend_schreiben(pfad, text):
    """Legt eine Sicherung an und setzt den neuen Text per os.replace an seine
    Stelle. Ein `open(pfad, 'w')` kürzte die Datei sofort auf 0 Byte und ließe
    sie bei einem Abbruch leer zurück.

    Die Sicherung liegt in einem privaten Temporaerordner (mkdtemp, nur fuer
    diesen Nutzer, kein vorhersagbarer Name), nicht daneben: Der Fassungsordner
    wird als Ganzes ins Netz geladen, eine .bak-Kopie der Seite ginge mit hoch.
    Die Nachbardatei entsteht per mkstemp im Ordner der Seite — exklusiv und
    unvorhersagbar benannt, damit kein untergeschobener Symlink das Ziel
    umlenkt; os.replace braucht dasselbe Dateisystem."""
    sicherung = Path(tempfile.mkdtemp(prefix='csp_hashes-')) / (pfad.name + '.bak')
    shutil.copy2(pfad, sicherung)

    griff, neben = tempfile.mkstemp(prefix='.' + pfad.name + '.', suffix='.neu', dir=pfad.parent)
    try:
        with os.fdopen(griff, 'w', encoding='utf-8', newline='') as datei:
            datei.write(text)
            datei.flush()
            os.fsync(datei.fileno())
        shutil.copymode(pfad, neben)
        os.replace(neben, pfad)
    except BaseException:
        Path(neben).unlink(missing_ok=True)
        raise
    return sicherung


def schreiben(pfad, quelltext, nach_tag, tag):
    """Trägt die aktuellen Hashes ein. Gibt True zurück, wenn sich etwas geändert hat."""
    neue_policy = direktive_setzen(tag.inhalt, 'script-src', nach_tag['script'])
    neue_policy = direktive_setzen(neue_policy, 'style-src', nach_tag['style'])

    if neue_policy == tag.inhalt:
        print('%s: Hashes waren bereits aktuell – Datei unveraendert.\n' % pfad.name)
        return False

    anfang, ende = tagspanne(quelltext, tag)
    neuer_text = quelltext[:anfang] + metatag_bauen(tag.attribute, neue_policy) \
        + quelltext[ende:]
    sicherung = ersetzend_schreiben(pfad, neuer_text)

    print('%s: Policy aktualisiert (Zeile %d).' % (pfad.name, tag.zeile))
    print('  vorher:  %s' % tag.inhalt)
    print('  nachher: %s' % neue_policy)
    print('  Sicherung der alten Fassung: %s\n' % sicherung)
    return True


def main():
    zerleger = argparse.ArgumentParser(
        description='Prueft und schreibt die CSP-Hashes der Ansichtsfassung.')
    zerleger.add_argument('dateien', nargs='*',
                          help='zu pruefende HTML-Dateien (Vorgabe: die Ansichtsfassung)')
    zerleger.add_argument('--schreiben', action='store_true',
                          help='aktuelle Hashes in die Policy eintragen statt nur zu pruefen')
    argumente = zerleger.parse_args()

    ordner = Path(__file__).resolve().parent
    if argumente.dateien:
        pfade = [Path(d) if Path(d).is_absolute() else Path.cwd() / d for d in argumente.dateien]
    else:
        pfade = [ordner / name for name in STANDARDDATEIEN]

    alles_heil = True
    for pfad in pfade:
        quelltext, beschriftung, aus_zip = quelle_bestimmen(pfad)
        if quelltext is None:
            print('FEHLER: %s nicht gefunden – weder lose noch im Offline-Paket daneben.\n' % pfad)
            alles_heil = False
            continue

        nach_tag, fundstellen, policytags = bloecke_lesen(quelltext)
        tag = policy_lesen(policytags, pfad)

        if not nach_tag['script'] and not nach_tag['style']:
            print('FEHLER: %s enthaelt keine Inline-Bloecke.\n' % beschriftung)
            alles_heil = False
            continue

        if argumente.schreiben:
            if aus_zip:
                print('%s: liegt nur im Offline-Paket – wird nur geprueft.' % beschriftung)
                print('  Zum Aendern: auspacken, bearbeiten, --schreiben, neu packen.\n')
            else:
                schreiben(pfad, quelltext, nach_tag, tag)
                quelltext = lesen(pfad)
                nach_tag, fundstellen, policytags = bloecke_lesen(quelltext)
                tag = policy_lesen(policytags, pfad)

        alles_heil &= pruefen(beschriftung, quelltext, nach_tag, fundstellen, tag.inhalt)

    if not alles_heil:
        print('Mindestens eine Datei passt nicht zu ihrer Policy.')
        if not argumente.schreiben:
            print('Beheben mit:  python3 %s --schreiben' % Path(__file__).name)
        return 1

    print('Alle geprueften Dateien sind stimmig.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
