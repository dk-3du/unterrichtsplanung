#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: GPL-3.0-or-later
"""Die Prüfstandsrunde am gebauten Paket — 29 Läufe an einer Probe-Kopie.

    python3 runde.py                 Runde am Paket dieses Fassungsordners
                                     (Paket/Unterrichtsplanung.app); Saat wird
                                     erzeugt; Protokoll nach Paket/Runde-<Stempel>/
    python3 runde.py --packen ZIEL   Rundenpaket für einen anderen Rechner (VM):
                                     ZIEL/Rundenpaket-<Fassung>-<Stufe>/ mit der
                                     fertigen Probe, saat/, diesem Skript, LIESMICH,
                                     Anleitung-VM.txt, Terminalbefehl.txt, PRUEFSUMMEN.txt
                                     und MANIFEST.txt (nach dem Siegeln, über alles) —
                                     im Gast wird nichts signiert
    python3 runde.py --laufen        im Rundenpaket: prüft zuerst jede Datei gegen
                                     MANIFEST.txt und die Signatur der Probe (sonst
                                     startet kein Prüfstand), dann Probe und Saat aus
                                     dem eigenen Ordner, Protokoll-<Rechner>-<Stempel>/
    python3 runde.py --selbsttest    die Bewertung eines Laufs an synthetischen
                                     Ausgaben prüfen (für pruefen.sh; enthält --syntax)
    python3 runde.py --syntax        nur die Form dieses Skripts

Rezept (seit v37, Routine je Fassung): Kopie des Pakets mit der Kennung
`org.3ducation.Unterrichtsplanung.probe`, Manifest ohne Umzugsquelle, ad hoc mit
den Berechtigungen neu gesiegelt; das Programm ist vor dem Umsignieren bytegleich
mit dem Paket (Prüfsumme im Protokoll). **Das echte Paket startet nie** — hier
nicht und im Gast nicht (E147). Jeder Lauf allein, mit Abstand; Prüfordner
unterhalb des Containers der Probe (`Unterrichtsplanung --container`); Saat aus
`tresor_pruefen.py --erzeugen` (Passphrase und Schlüssel aus `vektoren.json`).
Jeder Prüfstand beginnt mit seiner Paketzeile (E128, E144) und endet — nach seiner
Abmeldung (N67-01 Rest, v69; vorher beendet hieße „ABGEBROCHEN <Name> ✗“; die
Gegenprobe der Runde verlangt dafür seit v70 alle Voraussetzungen ihres Szenarios,
N69-01) — mit „ENDE
<Name>“ (seit v68, N67-01: ein Lauf ohne Ende oder ohne Zusicherung besteht
nicht; ein gewollter Abbruch beweist sich mit der Zeile des Dienstes); jede rote
Zeile ist ein Befund (seit v66 kein „bekanntes ✗“ mehr). Auf jedem System gelten dieselben
29 Läufe und Erwartungen (E148); was vom System abhängt — Rechner, Touch ID, die
Bedingung der Wicklung dieses Macs —, steht in der Bilanz, und die Erwartung an
die Bedingung folgt dem Gerät: ohne angelernte Finger „Anmeldepasswort“.
Das Rundenpaket beweist seine Unversehrtheit (seit v68, N67-02): `--packen`
schreibt nach dem Siegeln MANIFEST.txt (SHA-256 jeder Datei); `--laufen` prüft
jede Datei dagegen und die Signatur der Probe, bevor es die Quarantäne entfernt
oder etwas startet, und nennt die Prüfsumme des Manifests — sie muss der Zeile
„Manifest:“ im Packprotokoll auf dem Mac gleichen (der Vertrauensanker liegt
außerhalb des Pakets). Byteverschiedenheit und ein verify-Fehler beim Anlegen
der Probe brechen ab.
Braucht nur, was macOS mitbringt: python3, codesign, PlistBuddy, xattr,
killall, bioutil, sw_vers.
"""
import glob, hashlib, json, os, plistlib, shutil, subprocess, sys, time

KENNUNG = "org.3ducation.Unterrichtsplanung.probe"
LSREGISTER = ("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework"
              "/Support/lsregister")
NAME = "Unterrichtsplanung"
# Die Vorlage der Materialliste in Pruefungen/Vorlagen/ (ohne Endung), v71.
MATERIAL_VORLAGE = "inhalte-2026-09-17"
ABSTAND = 4
# Der Ende-Vertrag (v68, N67-01): Ein regulär beendeter Prüfstand druckt als
# Letztes „ENDE <Name>“ (der Delegat, beim Beenden); ein gewollter Abbruch
# (Exit 3) druckt stattdessen die Zeile des Dienstes — mit der Stelle, an der
# er geschah (N68-01, v69: die Runde verlangt vier Stellen und vergleicht sie)
# — und kein ENDE.
ENDE = "ENDE"
# Ein Prüfstand, der vor seinem Abschluss regulär beendet wird, hinterlässt
# statt ENDE diese Meldung (N67-01 Rest, v69) — mit ✗, denn er ist unvollständig.
ABGEBROCHEN = "ABGEBROCHEN"
ABBRUCHZEILE = "UEBERGANG_ABBRUCH: harter Abbruch nach"
# Die Zeile des Hakens `Pruefstaende.fruehesEndeFallsVerlangt` — „<Name> PRUEFSTAND_FRUEHES_ENDE: …“;
# die Gegenprobe verlangt sie genau einmal (N69-01, v70).
HAKENZEILE = "PRUEFSTAND_FRUEHES_ENDE:"

MANIFEST = "MANIFEST.txt"
ANLEITUNG = "Anleitung-VM.txt"
TERMINALBEFEHL = "Terminalbefehl.txt"
HIER = os.path.dirname(os.path.abspath(__file__))


# ── Hilfen ────────────────────────────────────────────────────────────────
def sha(pfad):
    h = hashlib.sha256()
    with open(pfad, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def befehl(*teile, **kw):
    return subprocess.run(list(teile), capture_output=True, text=True, **kw)


def plist(pfad):
    with open(pfad, "rb") as f:
        return plistlib.load(f)


def dateisumme(pfad):
    if os.path.islink(pfad):
        return hashlib.sha256(("link:" + os.readlink(pfad)).encode("utf-8")).hexdigest()
    return sha(pfad)


def manifestDateien(ordner):
    """Alle Dateien des Rundenpakets mit relativem Pfad — ohne das Manifest selbst,
    ohne Packprotokoll/ und Protokoll-*/ (entstehen beim Packen und im Gast), ohne
    __pycache__ und ohne .DS_Store (den legt der Finder beim Kopieren an). Ein
    Ordner, der sich nicht lesen lässt, ist ein Fehler (OSError), keine Lücke —
    os.walk übergeht ihn sonst still (R75-02, v76)."""
    treffer = []

    def lesefehler(fehler):
        raise fehler

    for wurzel, unterordner, dateien in os.walk(ordner, onerror=lesefehler):
        rel = os.path.relpath(wurzel, ordner)
        if rel == ".":
            unterordner[:] = [o for o in unterordner
                              if o != "Packprotokoll" and not o.startswith("Protokoll-") and o != "__pycache__"]
        for d in dateien:
            if d == ".DS_Store" or (rel == "." and d == MANIFEST):
                continue
            treffer.append(os.path.normpath(os.path.join(rel, d)))
    return sorted(treffer)


def manifestSumme(ordner):
    return sha(os.path.join(ordner, MANIFEST))


def manifestSchreiben(ordner):
    """Nach dem Siegeln: SHA-256 jeder Datei, eine Zeile je Datei. Liefert die
    Prüfsumme des Manifests — die kommt ins Packprotokoll, nach VERSIONEN und in
    die Release-Notiz, damit der Gast sie vergleichen kann."""
    zeilen = [f"{dateisumme(os.path.join(ordner, rel))}  {rel}" for rel in manifestDateien(ordner)]
    with open(os.path.join(ordner, MANIFEST), "w", encoding="utf-8") as f:
        f.write("\n".join(zeilen) + "\n")
    return manifestSumme(ordner)


def manifestPruefen(ordner):
    """Jede Datei gegen das Manifest: fehlend, anders, zusätzlich. → (ok, Gründe)."""
    pfad = os.path.join(ordner, MANIFEST)
    if not os.path.exists(pfad):
        return False, [f"{MANIFEST} fehlt"]
    erwartet = {}
    with open(pfad, encoding="utf-8") as f:
        for zeile in f:
            zeile = zeile.rstrip("\n")
            if zeile:
                summe, _, rel = zeile.partition("  ")
                erwartet[rel] = summe
    try:
        ist = manifestDateien(ordner)
    except OSError as fehler:
        return False, [f"{os.path.relpath(fehler.filename, ordner)}: nicht lesbar ({fehler.strerror})"]
    gruende = []
    for rel in ist:
        if rel not in erwartet:
            gruende.append(f"{rel}: zusätzlich")
        elif dateisumme(os.path.join(ordner, rel)) != erwartet[rel]:
            gruende.append(f"{rel}: anders")
    gruende += [f"{rel}: fehlt" for rel in erwartet if rel not in set(ist)]
    return not gruende, sorted(gruende)


def probePruefen(probe, verify=None):
    """`codesign --verify --strict` an der Probe → (ok, Text). `verify` ist für den
    Selbsttest einspritzbar."""
    if verify is None:
        def verify(pfad):
            r = befehl("codesign", "--verify", "--strict", pfad)
            return r.returncode, r.stderr
    code, text = verify(probe)
    return code == 0, text.strip()


def rechner():
    fassung = befehl("sw_vers", "-productVersion").stdout.strip()
    bau = befehl("sw_vers", "-buildVersion").stdout.strip()
    modell = befehl("sysctl", "-n", "hw.model").stdout.strip()
    return f"macOS {fassung} ({bau}), {modell}"


def touchIDEingerichtet():
    """Angelernte Finger, wie `bioutil` sie zählt — None, wenn nicht zu lesen."""
    r = befehl("bioutil", "-c")
    if r.returncode != 0:
        return None
    for zeile in r.stdout.splitlines():
        if "biometric template" in zeile:
            try:
                return int(zeile.split(":")[1].split()[0]) > 0
            except (IndexError, ValueError):
                return None
    return None


class Bilanz:
    def __init__(self, ordner):
        os.makedirs(ordner, exist_ok=True)
        self.ordner = ordner
        self.datei = open(os.path.join(ordner, "runde.txt"), "w", encoding="utf-8")

    def sag(self, *teile):
        zeile = " ".join(str(t) for t in teile)
        print(zeile, flush=True)
        self.datei.write(zeile + "\n")
        self.datei.flush()


# ── Die Probe-Kopie (E147: hier gebaut, ad hoc gesiegelt) ─────────────────
def probename(info):
    """„Probe 1.7.8 (67)“ — so heißt die Kopie im Bündelnamen, im Finder und
    damit auch ihr Container (B34)."""
    return f"Probe {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})"


def probebuendel(paket):
    return probename(plist(os.path.join(paket, "Contents", "Info.plist"))).replace(" ", "-").replace("(", "").replace(")", "") + ".app"


def probeAnlegen(paket, ziel, berechtigungen, bilanz):
    if os.path.exists(ziel):
        shutil.rmtree(ziel)
    programmPaket = os.path.join(paket, "Contents", "MacOS", NAME)
    bilanz.sag("Paket:", paket)
    bilanz.sag("Programm im Paket:", sha(programmPaket))
    subprocess.run(["cp", "-R", paket, ziel], check=True)
    programmProbe = os.path.join(ziel, "Contents", "MacOS", NAME)
    gleich = sha(programmProbe) == sha(programmPaket)
    bilanz.sag("Programm der Probe vor dem Umsignieren:", sha(programmProbe),
               "— bytegleich" if gleich else "— VERSCHIEDEN ✗")
    if not gleich:
        bilanz.sag("Die Probe trägt nicht das Programm des Pakets — abgebrochen, nichts gestartet (N67-02).")
        sys.exit(1)
    # Eigene Kennung — und ein eigener Anzeigename (B34, 16.09.2026): Der Finder
    # zeigt Container-Ordner unter dem Anzeigenamen ihrer App, und der war bei
    # Original und Probe gleich („Unterrichtsplanung“) — zwei gleichnamige
    # Ordner nebeneinander, der echte nicht von der Probe zu unterscheiden.
    infoPfad = os.path.join(ziel, "Contents", "Info.plist")
    info = plist(infoPfad)
    info["CFBundleIdentifier"] = KENNUNG
    info["CFBundleDisplayName"] = probename(info)
    info["CFBundleName"] = probename(info)   # der Finder nimmt diesen Namen (gemessen 16.09.2026)
    with open(infoPfad, "wb") as f:
        plistlib.dump(info, f)
    with open(os.path.join(ziel, "Contents", "Resources", "container-migration.plist"), "wb") as f:
        plistlib.dump({"Move": []}, f)      # Manifest ohne Umzugsquelle
    r = befehl("codesign", "--force", "--options", "runtime", "--entitlements", berechtigungen, "--sign", "-", ziel)
    if r.returncode:
        bilanz.sag("codesign ✗", r.stderr)
        sys.exit(1)
    ok, text = probePruefen(ziel)
    bilanz.sag("Probe ad hoc gesiegelt, verify --strict:", "✓" if ok else "✗ " + text)
    if not ok:
        bilanz.sag("Die Signatur der Probe hält nicht — abgebrochen, nichts gestartet (N67-02).")
        sys.exit(1)
    # LaunchServices den neuen Namen sagen — sonst zeigt der Finder den Container
    # unter dem Namen einer früheren Probe mit derselben Kennung (B34).
    befehl(LSREGISTER, "-f", ziel)
    return gleich


def probeBeschreiben(probe, bilanz):
    info = plist(os.path.join(probe, "Contents", "Info.plist"))
    bilanz.sag(f"Probe: {info['CFBundleIdentifier']} {info['CFBundleShortVersionString']} "
               f"({info['CFBundleVersion']}), Quellenstand {info.get('UPQuellenstand', '?')[:12]}…, "
               f"Werkzeugstand {info.get('UPWerkzeugstand', '?')[:12]}…, "
               f"Konfiguration {info.get('UPKonfiguration', 'fehlt')}")
    return info


# ── Die Saat ──────────────────────────────────────────────────────────────
def saatErzeugen(fassungsordner, ziel):
    ansicht = os.path.join(os.path.dirname(os.path.dirname(fassungsordner)), "Web-App",
                           os.path.basename(fassungsordner))
    skript = os.path.join(ansicht, "tresor_pruefen.py")
    if not os.path.exists(skript):
        sys.exit(f"Die Saat lässt sich nicht erzeugen: {skript} fehlt")
    r = befehl("python3", skript, "--erzeugen", ziel)
    if r.returncode:
        sys.exit("tresor_pruefen.py --erzeugen scheiterte:\n" + r.stdout + r.stderr)
    # Die Materialliste (v71, E182): die Vorlage des Tages und ihr erwartetes JSON
    # aus jsc — der Prüfstand --materialtest liest die eine und hält die Zahlen
    # gegen das andere. Nichts davon geht ins Netz.
    vorlagen = os.path.join(fassungsordner, "Pruefungen", "Vorlagen")
    for name, ziel_name in ((MATERIAL_VORLAGE + ".js", "inhalte.js"),
                            (MATERIAL_VORLAGE + ".erwartet.json", "inhalte.erwartet.json")):
        quelle = os.path.join(vorlagen, name)
        if not os.path.exists(quelle):
            sys.exit(f"Die Saat lässt sich nicht erzeugen: {quelle} fehlt")
        shutil.copy(quelle, os.path.join(ziel, ziel_name))


def geheimnisse(saat):
    """Passphrase und Wiederherstellungsschlüssel aus vektoren.json."""
    with open(os.path.join(saat, "vektoren.json"), encoding="utf-8") as f:
        daten = json.load(f)

    def suche(objekt, name):
        if isinstance(objekt, dict):
            for schluessel, wert in objekt.items():
                if schluessel.lower() == name and isinstance(wert, str):
                    return wert
                treffer = suche(wert, name)
                if treffer:
                    return treffer
        elif isinstance(objekt, list):
            for eintrag in objekt:
                treffer = suche(eintrag, name)
                if treffer:
                    return treffer
        return None
    return suche(daten, "passphrase"), (suche(daten, "wiederherstellung") or suche(daten, "schluessel"))


# ── Die Läufe ─────────────────────────────────────────────────────────────
def auftragsname(argumente):
    """„--klicktest“ → „KLICKTEST“; „--entsperrtest passphrase“ → „ENTSPERRTEST“:
    der Name, den der Prüfstand vor jeder Zeile und in seiner Ende-Zeile trägt."""
    return argumente[0][2:].upper()


def abbruchzeile(stelle):
    """Die Zeile, die `Uebergang.abbruchFallsVerlangt` für diese Stelle druckt."""
    return f"{ABBRUCHZEILE} „{stelle}“"


def abbruchstelleLesen(zeilen):
    """Die Stelle aus der ersten Abbruchzeile des Protokolls — oder None, wenn
    keine Zeile mit dem Präfix da ist oder ihr die Anführung fehlt."""
    for z in zeilen:
        z = z.strip()
        if z.startswith(ABBRUCHZEILE):
            rest = z[len(ABBRUCHZEILE):].strip()
            if len(rest) >= 3 and rest[0] == "„" and rest[-1] == "“":
                return rest[1:-1]
            return None
    return None


def bewerten(zeilen, code, erwartet, paketanfang, auftrag, abbruchstelle=None):
    """Die Bewertung eines Laufs — eine reine Funktion, damit --selbsttest sie
    füttern kann. Bestanden hat ein Lauf, der (1) mit der erwarteten Rückgabe
    endet, (2) mit der Paketzeile beginnt, (3) keine rote Zeile hat, (4) wenigstens
    eine Zusicherung trägt — ein Lauf ohne eine einzige ist kein Lauf — und (5)
    sein Ende beweist: bei erwarteter Rückgabe 0 die Zeile „ENDE <Name>“, die der
    Delegat beim regulären Beenden druckt; bei einem gewollten Abbruch (Exit 3)
    die Zeile des Dienstes **mit genau der verlangten Stelle** und *kein* ENDE.
    Bis v67 fehlten (4) und (5): Ein Prüfstand, der nach der Paketzeile still
    endete, galt als bestanden (N67-01). Bis v68 genügte bei (5) jede Abbruchzeile:
    Ein Protokoll, das „vorbereitet“ meldete, bestand den Lauf für „einsetzen“
    (N68-01) — jetzt muss `abbruchstelle` genannt sein und gemeldet werden.
    Liefert (ok, gruen, rot, paketOk, endeOk, beobachtet); `beobachtet` ist die
    gemeldete Stelle oder None."""
    erste = zeilen[0] if zeilen else ""
    gruen = sum(1 for z in zeilen if "✓" in z)
    rot = [z for z in zeilen if "✗" in z]
    paketOk = erste.startswith(paketanfang)
    hatEnde = any(z.strip() == f"{ENDE} {auftrag}" for z in zeilen)
    beobachtet = abbruchstelleLesen(zeilen)
    hatAbbruch = (abbruchstelle is not None and beobachtet == abbruchstelle
                  and any(z.strip() == abbruchzeile(abbruchstelle) for z in zeilen))
    endeOk = hatEnde if erwartet == 0 else (hatAbbruch and not hatEnde)
    ok = code == erwartet and paketOk and not rot and gruen >= 1 and endeOk
    return ok, gruen, rot, paketOk, endeOk, beobachtet


# Das Merkmal Korrektur am Paket: Die Saat führt eine Korrektur, der Klicktest
# liest sie aus der Datei und sagt es in dieser Zeile — ohne sie oder ohne ✓
# ist das Merkmal am Paket nicht belegt, und die Runde besteht nicht.
KORREKTURZEILE = "Korrektur aus der Datei"


def korrekturBelegt(zeilen):
    return any(KORREKTURZEILE in z and "✓" in z and "✗" not in z for z in zeilen)


# Die Voraussetzungen der Gegenprobe, in der Reihenfolge der Bilanz (N69-01, v70).
GEGENPROBE_VORAUSSETZUNGEN = ("Paketzeile", "Zusicherung vor dem Haken", "Hakenzeile einmal",
                              "Rückgabe 0", "ABGEBROCHEN einmal, zuletzt", "ENDE fehlt",
                              "keine weitere ✗-Zeile")


def gegenprobeBewerten(zeilen, code, paketanfang, auftrag):
    """Die Gegenprobe (N67-01 Rest, v69; N69-01, v70): Ein Lauf, der mit
    PRUEFSTAND_FRUEHES_ENDE nach seiner ersten Zusicherung regulär endet, darf
    *nicht* bestehen — und er muss sagen, warum: „ABGEBROCHEN <Name>“ statt
    „ENDE <Name>“. Bis v69 genügte der Gegenprobe, dass die Bewertung den Lauf
    abwies, ABGEBROCHEN stand und ENDE fehlte — eine einzelne ABGEBROCHEN-Zeile
    mit Rückgabe 1 und fremder Paketzeile bestand sie (fünfzehnte Review). Jetzt
    beweist sie zuerst ihr Szenario: (1) die Paketzeile, (2) wenigstens eine
    Zusicherung ✓ *vor* der Hakenzeile, (3) die Hakenzeile genau einmal, (4)
    Rückgabe 0 — der Ausstieg war regulär —, (5) „ABGEBROCHEN <Name> ✗“ genau
    einmal, nach dem Haken und als letzte Zeile des Prüfstands, (6) kein ENDE,
    (7) keine weitere ✗-Zeile (ein anderer Fehler wäre ein anderer Befund). Erst
    dann zählt, dass die gewöhnliche Bewertung den Lauf abweist. Liefert
    (ok, voraussetzungen, bewertungOk); `voraussetzungen` ist ein Dict in der
    Reihenfolge von GEGENPROBE_VORAUSSETZUNGEN."""
    glatt = [z.strip() for z in zeilen]
    hakenstellen = [i for i, z in enumerate(glatt) if z.startswith(f"{auftrag} {HAKENZEILE}")]
    haken = hakenstellen[0] if len(hakenstellen) == 1 else None
    abbruchstellen = [i for i, z in enumerate(glatt) if z.startswith(f"{ABGEBROCHEN} {auftrag} ✗")]
    # Die letzte Zeile, die dem Prüfstand gehört — Paketzeile, Name, ENDE, ABGEBROCHEN.
    eigene = [i for i, z in enumerate(glatt)
              if z.startswith(paketanfang) or z.startswith(f"{auftrag} ")
              or z.startswith(f"{ENDE} {auftrag}") or z.startswith(f"{ABGEBROCHEN} {auftrag}")]
    letzte = eigene[-1] if eigene else None
    v = {
        "Paketzeile": bool(glatt) and glatt[0].startswith(paketanfang),
        "Zusicherung vor dem Haken": haken is not None and any("✓" in z for z in glatt[:haken]),
        "Hakenzeile einmal": haken is not None,
        "Rückgabe 0": code == 0,
        "ABGEBROCHEN einmal, zuletzt": (len(abbruchstellen) == 1 and haken is not None
                                        and abbruchstellen[0] > haken and abbruchstellen[0] == letzte),
        "ENDE fehlt": not any(z == f"{ENDE} {auftrag}" for z in glatt),
        "keine weitere ✗-Zeile": all("✗" not in z for i, z in enumerate(glatt) if i not in abbruchstellen),
    }
    assert tuple(v) == GEGENPROBE_VORAUSSETZUNGEN
    bewertungOk = bewerten(zeilen, code, 0, paketanfang, auftrag)[0]
    return all(v.values()) and not bewertungOk, v, bewertungOk


def gegenprobeAusgang(voraussetzungen, bewertungOk):
    """Der Ausgang der Gegenprobe in Worten — für die Bilanz (E163)."""
    fehlend = [name for name, gilt in voraussetzungen.items() if not gilt]
    if fehlend:
        return "Voraussetzung nicht erfüllt: " + ", ".join(fehlend)
    if bewertungOk:
        return "DER BEFUND — ein früher regulärer Ausstieg besteht die Bewertung"
    return "vor dem Abschluss beendet und abgewiesen — wie verlangt"


def runde(probe, saat, bilanz):
    info = probeBeschreiben(probe, bilanz)
    app = os.path.join(probe, "Contents", "MacOS", NAME)
    container = befehl(app, "--container").stdout.strip()
    bilanz.sag("Container:", container)
    if not container.endswith(KENNUNG + "/Data"):
        bilanz.sag("Container unerwartet ✗")
        sys.exit(1)
    tmp = os.path.join(container, "tmp")
    os.makedirs(tmp, exist_ok=True)
    for alt in glob.glob(os.path.join(tmp, "pruef-*")):
        shutil.rmtree(alt, ignore_errors=True)
    passphrase, schluessel = geheimnisse(saat)
    bilanz.sag("Saat:", saat, "— Passphrase und Schlüssel gefunden" if passphrase and schluessel else "— UNVOLLSTÄNDIG ✗")
    fingerabdruecke = touchIDEingerichtet()
    bilanz.sag("Rechner:", rechner())
    bilanz.sag("Touch ID:", {True: "eingerichtet", False: "nicht eingerichtet", None: "nicht zu lesen (bioutil)"}[fingerabdruecke])
    erwarteteBedingung = {True: "(Touch ID oder Anmeldepasswort)", False: "(Anmeldepasswort)", None: None}[fingerabdruecke]

    paketanfang = (f"Paket: {KENNUNG} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), "
                   f"Quellenstand {info.get('UPQuellenstand', '?')[:12]}…, Werkzeugstand {info.get('UPWerkzeugstand', '?')[:12]}…")
    ergebnisse = []
    protokolle = {}

    def ordner(name, saatdatei=None):
        pfad = os.path.join(tmp, f"pruef-{name}")
        if os.path.exists(pfad):
            shutil.rmtree(pfad)
        if saatdatei is not None:
            os.makedirs(pfad)
            shutil.copy(os.path.join(saat, saatdatei), os.path.join(pfad, "planung.json"))
        return pfad

    def lauf(name, argumente, umgebung=None, ordnerpfad=None, erwartet=0, frist=420, abbruchstelle=None,
             gegenprobe=False):
        env = dict(os.environ)
        env.pop("PLANUNGSORDNER", None)
        if ordnerpfad is not None:
            env["PLANUNGSORDNER"] = ordnerpfad
        if umgebung:
            env.update(umgebung)
        start = time.time()
        try:
            r = subprocess.run([app] + argumente, env=env, capture_output=True, text=True, timeout=frist)
            code, ausgabe = r.returncode, r.stdout + r.stderr
        except subprocess.TimeoutExpired as e:
            code = "FRIST"
            ausgabe = (e.stdout.decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or ""))
            subprocess.run(["pkill", "-f", app])
        dauer = time.time() - start
        zeilen = ausgabe.splitlines()
        nummer = len(ergebnisse) + 1
        with open(os.path.join(bilanz.ordner, f"{nummer:02d}-{name}.txt"), "w", encoding="utf-8") as f:
            f.write(ausgabe)
        protokolle[name] = zeilen
        erste = zeilen[0] if zeilen else ""
        ok, gruen, rot, paketOk, endeOk, beobachtet = bewerten(zeilen, code, erwartet, paketanfang,
                                                              auftragsname(argumente), abbruchstelle)
        if gegenprobe:
            # Die Gegenprobe zählt ✓, wenn die Bewertung den Lauf abweist und die
            # Abbruchmeldung steht; „Ende“ heißt hier: der Abbruch ist bewiesen.
            ok, voraussetzungen, bewertungOk = gegenprobeBewerten(zeilen, code, paketanfang,
                                                                  auftragsname(argumente))
            endeOk = ok
            ergebnisse.append((name, ok, gruen, len(rot), paketOk, endeOk))
            # Jede Voraussetzung einzeln, dann der Ausgang in Worten (N69-01, E163).
            bilanz.sag(f"{nummer:02d} {name:28s} {'✓' if ok else '✗'}  GEGENPROBE — Rückgabe {code}, {gruen} ✓, {len(rot)} ✗; "
                       + "Voraussetzungen: "
                       + ", ".join(f"{n} {'✓' if g else '✗'}" for n, g in voraussetzungen.items())
                       + f"; Bewertung {'✗ wie verlangt' if not bewertungOk else '✓'}; "
                       + f"Ausgang: {gegenprobeAusgang(voraussetzungen, bewertungOk)}, {dauer:.0f} s")
            time.sleep(ABSTAND)
            return ok
        ergebnisse.append((name, ok, gruen, len(rot), paketOk, endeOk))
        # Bei einem gewollten Abbruch nennt die Bilanz verlangte und beobachtete
        # Stelle nebeneinander (N68-01) — „Ende“ heißt hier: Abbruch bewiesen.
        ende = (f"Ende {'✓' if endeOk else '✗'}" if abbruchstelle is None else
                f"Abbruch nach „{abbruchstelle}“ verlangt, „{beobachtet or '—'}“ beobachtet {'✓' if endeOk else '✗'}")
        bilanz.sag(f"{nummer:02d} {name:28s} {'✓' if ok else '✗'}  Rückgabe {code} (erwartet {erwartet}), "
                   f"{gruen} ✓, {len(rot)} ✗, Paketzeile {'✓' if paketOk else '✗ ' + erste[:80]}, "
                   f"{ende}, {dauer:.0f} s")
        for z in rot[:6]:
            bilanz.sag("      ", z[:160])
        time.sleep(ABSTAND)
        return ok

    versiegelt = {"ENTSPERRPROBE_PASSPHRASE": passphrase or ""}
    uebergang = {"UEBERGANG_PASSPHRASE": passphrase or ""}

    # Vorlauf, ungezählt (B35, 16.09.2026): Der erste Dateidialog eines frischen
    # Systems löst die Abfrage „Geräte im lokalen Netzwerk suchen?“ aus; solange
    # sie steht, geht kein Bogen auf, und die Reißleine des Dialogtests (6 s)
    # meldete in der zurückgesetzten VM stets ein ✗ in Lauf 12. Darum nimmt
    # dieser Vorlauf den ersten Dateidialog vorweg — wer die Abfrage quittiert,
    # bekommt danach eine Runde ohne Systemdialoge. Sein Ergebnis steht nur
    # zur Auskunft in der Bilanz.
    vorlauf = ordner("vorlauf", "klartext.json")
    start = time.time()
    try:
        r = subprocess.run([app, "--dialogtest"], env={**os.environ, "PLANUNGSORDNER": vorlauf},
                           capture_output=True, text=True, timeout=600)
        ausgabe = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        ausgabe = ""
        subprocess.run(["pkill", "-f", app])
    with open(os.path.join(bilanz.ordner, "00-vorlauf-dialog.txt"), "w", encoding="utf-8") as f:
        f.write(ausgabe)
    bilanz.sag(f"00 Vorlauf (erster Dateidialog, ungezählt): {sum(1 for z in ausgabe.splitlines() if '✓' in z)} ✓, "
               f"{sum(1 for z in ausgabe.splitlines() if '✗' in z)} ✗, {time.time() - start:.0f} s — "
               "Systemabfragen (lokales Netzwerk) gehören hierhin, nicht in die Runde")
    time.sleep(ABSTAND)

    # 1 Erststart mit PLANUNGSORDNER auf einen Ordner, den es nicht gibt
    lauf("erststart-ordner", ["--erststarttest"], ordnerpfad=ordner("erststart-neu"))
    # 2 Erststart im Probepaket ohne PLANUNGSORDNER: Ablage und Domäne beiseite, cfprefsd leeren
    ablage = os.path.join(container, "Library", "Application Support", NAME)
    domaene = os.path.join(container, "Library", "Preferences", KENNUNG + ".plist")
    beiseite = os.path.join(tmp, f"pruef-beiseite-{int(time.time())}")
    os.makedirs(beiseite)
    for pfad in (ablage, domaene):
        if os.path.exists(pfad):
            shutil.move(pfad, os.path.join(beiseite, os.path.basename(pfad)))
    subprocess.run(["killall", "cfprefsd"], capture_output=True)
    time.sleep(2)
    lauf("erststart-container", ["--erststarttest"])
    # 3–4
    lauf("klick", ["--klicktest"], ordnerpfad=ordner("klick", "klartext.json"))
    # Die Gegenprobe (N67-01 Rest): derselbe Prüfstand, regulär beendet nach der
    # ersten Zusicherung — er darf nicht bestehen und muss ABGEBROCHEN sagen.
    lauf("klick-fruehes-ende", ["--klicktest"], {"PRUEFSTAND_FRUEHES_ENDE": "1"},
         ordnerpfad=ordner("klick-frueh", "klartext.json"), gegenprobe=True)
    tour = ordner("tour", "klartext.json")
    lauf("tour", ["--tourtest"], {"TOURBILD": os.path.join(tour, "tour")}, ordnerpfad=tour)
    # 5–8 je Klartext und versiegelt
    lauf("ordner-klartext", ["--ordnertest"], ordnerpfad=ordner("ordner-klartext", "klartext.json"))
    lauf("ordner-versiegelt", ["--ordnertest"], versiegelt, ordnerpfad=ordner("ordner-versiegelt", "planung.json"))
    lauf("sitzplan-klartext", ["--sitzplantest"], ordnerpfad=ordner("sitzplan-klartext", "klartext.json"))
    lauf("sitzplan-versiegelt", ["--sitzplantest"], versiegelt, ordnerpfad=ordner("sitzplan-versiegelt", "planung.json"))
    # 9 Entsperren
    lauf("entsperr-passphrase", ["--entsperrtest", "passphrase"], versiegelt, ordnerpfad=ordner("entsperr", "planung.json"))
    # 10–11 Widerrufen, zweimal Klartext (der Test entsperrt nicht)
    lauf("widerruf-1", ["--widerruftest"], ordnerpfad=ordner("widerruf-1", "klartext.json"))
    lauf("widerruf-2", ["--widerruftest"], ordnerpfad=ordner("widerruf-2", "klartext.json"))
    # 12–13 Dialoge — mit der Materialliste aus der Saat (v71), damit der Bogen
    # „Material von 3ducation.org“ die Liste zeigt, nicht „nicht erreichbar“
    # Im Sandbox liest die Probe nur ihren Container — die Dateien wandern dorthin
    # (nachgemessen 17.09.2026: von außerhalb hieß es „nicht erreichbar“).
    materialordner = os.path.join(tmp, "pruef-material-quelle")
    if os.path.exists(materialordner):
        shutil.rmtree(materialordner)
    os.makedirs(materialordner)
    for name in ("inhalte.js", "inhalte.erwartet.json"):
        shutil.copy(os.path.join(saat, name), os.path.join(materialordner, name))
    material = {"MATERIAL_QUELLE": os.path.join(materialordner, "inhalte.js"),
                "MATERIAL_ERWARTET": os.path.join(materialordner, "inhalte.erwartet.json")}
    lauf("dialog-klartext", ["--dialogtest"], material, ordnerpfad=ordner("dialog-klartext", "klartext.json"))
    lauf("dialog-versiegelt", ["--dialogtest"], {**versiegelt, **material}, ordnerpfad=ordner("dialog-versiegelt", "planung.json"))
    # 14–18 Übergänge, fünf Arten
    lauf("uebergang-einschalten", ["--uebergangstest", "einschalten"], uebergang, ordnerpfad=ordner("ueb-einschalten", "klartext.json"))
    for art in ("erneuern", "passphrase", "wicklung", "aufheben"):
        lauf(f"uebergang-{art}", ["--uebergangstest", art], uebergang, ordnerpfad=ordner(f"ueb-{art}", "planung.json"))
    # 19–26 vier Abbrüche (Exit 3) mit zweitem Start
    for stelle in ("vorbereitet", "uebergeben", "einsetzen", "aufgeraeumt"):
        pfad = ordner(f"ueb-abbruch-{stelle}", "klartext.json")
        lauf(f"abbruch-{stelle}", ["--uebergangstest", "einschalten"], {**uebergang, "UEBERGANG_ABBRUCH": stelle},
             ordnerpfad=pfad, erwartet=3, abbruchstelle=stelle)
        lauf(f"abbruch-{stelle}-2.Start", ["--uebergangstest", "pruefen"], uebergang, ordnerpfad=pfad)

    # 27 Die Materialliste von 3ducation.org (v71, E182): aus der Saat, die
    # Sollzahlen aus dem erwarteten JSON — nichts geht ins Netz.
    lauf("material-katalog", ["--materialtest"], material, ordnerpfad=ordner("material", "klartext.json"))

    # 29 Der Stand der Web App nach dem Aufwachen und auf Befehl (v75, E216 d, E218):
    # Der Prüfstand sendet die Meldung des Aufwachens selbst und wartet die echten
    # 15 Sekunden ab — etwa eine Minute.
    lauf("status-aufwachen", ["--statustest"], ordnerpfad=ordner("status", "klartext.json"))

    # Die Bedingung der Wicklung dieses Macs folgt dem Gerät (E148, E141).
    bedingungZeile = next((z for z in protokolle.get("uebergang-wicklung", []) if "Wicklung dieses Macs: angelegt" in z), "")
    bedingungOk = None
    if erwarteteBedingung is not None and bedingungZeile:
        bedingungOk = erwarteteBedingung in bedingungZeile
        bilanz.sag(f"Bedingung der Wicklung dieses Macs: {bedingungZeile.strip()} — erwartet nach dem Gerät "
                   f"{erwarteteBedingung} {'✓' if bedingungOk else '✗'}")

    # Das Merkmal Korrektur: aus der Saat gelesen — am Paket, nicht nur in den Prüfungen.
    korrekturOk = korrekturBelegt(protokolle.get("klick", []))
    bilanz.sag(f"Merkmal Korrektur aus der Saat am Paket gelesen (Lauf klick): {'✓' if korrekturOk else '✗'}")

    gruenGesamt = sum(e[2] for e in ergebnisse)
    rotGesamt = sum(e[3] for e in ergebnisse)
    okLaeufe = sum(1 for e in ergebnisse if e[1])
    bilanz.sag(f"\nRUNDE: {okLaeufe}/{len(ergebnisse)} Läufe grün, {gruenGesamt} Zusicherungen, {rotGesamt} ✗; "
               f"Paketzeile in {sum(1 for e in ergebnisse if e[4])}/{len(ergebnisse)} Läufen; "
               f"Ende in {sum(1 for e in ergebnisse if e[5])}/{len(ergebnisse)} Läufen; "
               f"Bedingung der Wicklung {'✓' if bedingungOk else ('✗' if bedingungOk is False else 'nicht geprüft')}; "
               f"Korrektur aus der Saat {'✓' if korrekturOk else '✗'}; "
               f"{rechner()}; Touch ID {'eingerichtet' if fingerabdruecke else 'nicht eingerichtet' if fingerabdruecke is False else 'unbekannt'}")
    bilanz.sag(f"Probe-Container (im Finder „{probename(info)}“, zu entfernen):", os.path.dirname(container))
    return okLaeufe == len(ergebnisse) and bedingungOk is not False and korrekturOk


# ── Die Aufrufarten ───────────────────────────────────────────────────────
def stempel():
    return time.strftime("%Y-%m-%d-%H%M%S")


def imFassungsordner():
    paket = os.path.join(HIER, "Paket", f"{NAME}.app")
    if not os.path.isdir(paket):
        sys.exit(f"Kein Paket unter {paket} — erst ./bauen.sh (mit SIGNATUR für die Routine).")
    protokoll = os.path.join(HIER, "Paket", f"Runde-{stempel()}")
    bilanz = Bilanz(protokoll)
    probe = os.path.join(protokoll, probebuendel(paket))
    probeAnlegen(paket, probe, os.path.join(HIER, "Beiwerk", "Berechtigungen.plist"), bilanz)
    saat = os.path.join(protokoll, "saat")
    saatErzeugen(HIER, saat)
    ok = runde(probe, saat, bilanz)
    bilanz.sag("Protokoll:", protokoll)
    return ok


def packen(ziel):
    paket = os.path.join(HIER, "Paket", f"{NAME}.app")
    if not os.path.isdir(paket):
        sys.exit(f"Kein Paket unter {paket} — erst ./bauen.sh mit SIGNATUR.")
    info = plist(os.path.join(paket, "Contents", "Info.plist"))
    name = f"Rundenpaket-{info['CFBundleShortVersionString']}-{info['CFBundleVersion']}"
    ordner = os.path.join(os.path.abspath(ziel), name)
    if os.path.exists(ordner):
        sys.exit(f"{ordner} gibt es schon — erst in den Papierkorb legen.")
    os.makedirs(ordner)
    bilanz = Bilanz(os.path.join(ordner, "Packprotokoll"))
    probe = os.path.join(ordner, probebuendel(paket))
    gleich = probeAnlegen(paket, probe, os.path.join(HIER, "Beiwerk", "Berechtigungen.plist"), bilanz)
    probeBeschreiben(probe, bilanz)
    saatErzeugen(HIER, os.path.join(ordner, "saat"))
    shutil.copy(os.path.abspath(__file__), os.path.join(ordner, "runde.py"))
    with open(os.path.join(ordner, "PRUEFSUMMEN.txt"), "w", encoding="utf-8") as f:
        f.write(f"Programm im Paket und in der Probe (vor dem Umsignieren, bytegleich: {'ja' if gleich else 'NEIN'}): "
                f"{sha(os.path.join(paket, 'Contents', 'MacOS', NAME))}\n")
        f.write(f"Quellenstand: {info.get('UPQuellenstand', '?')}\nWerkzeugstand: {info.get('UPWerkzeugstand', '?')}\n"
                f"Konfiguration: {info.get('UPKonfiguration', '?')}\nGepackt: {stempel()} auf {rechner()}\n")
    with open(os.path.join(ordner, "LIESMICH.txt"), "w", encoding="utf-8") as f:
        f.write(f"""Rundenpaket {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}) — die Prüfstandsrunde auf einem anderen Mac

Inhalt: {os.path.basename(probe)} (Kopie des Pakets mit der Kennung {KENNUNG} und
dem Anzeigenamen „{probename(info)}“, ad hoc gesiegelt, Manifest ohne Umzugsquelle —
nicht das echte Paket; ihr Container heißt im Finder ebenso), saat/ (Prüfdaten),
runde.py, {ANLEITUNG} (für eine frische virtuelle Maschine), {TERMINALBEFEHL},
PRUEFSUMMEN.txt (Angaben vor dem Umsignieren) und {MANIFEST} (SHA-256 jeder Datei,
nach dem Siegeln). Braucht nur macOS und python3 (3.9 oder neuer), kein Xcode.

Den ganzen Ordner in das Benutzerverzeichnis des Rechners kopieren, dann im Terminal,
angemeldet am Bildschirm (die Prüfstände öffnen Fenster):

    python3 ~/{name}/runde.py --laufen

Das Skript prüft zuerst jede Datei gegen {MANIFEST} und die Signatur der Probe — weicht
etwas ab, startet kein Prüfstand — und nennt die Prüfsumme des Manifests: Sie muss der
Zeile „Manifest:“ im Packprotokoll auf dem Mac gleichen. Dann entfernt es die Quarantäne
des Ordners, macht einen ungezählten Vorlauf mit dem ersten Dateidialog — auf einem
frischen System fragt macOS dabei einmal, ob die App Geräte im lokalen Netzwerk suchen
darf; wie das ausbleibt, steht in {ANLEITUNG} —, fährt dann die 29 Läufe (etwa sechs
Minuten, jeder Lauf allein — den Rechner derweil nicht benutzen) und schreibt
Protokoll-<Rechner>-<Stempel>/ in diesen Ordner. Diesen Protokollordner zurückbringen.
Danach den Probe-Container entfernen — im Finder heißt er „{probename(info)}“:
~/Library/Containers/{KENNUNG}
""")
    with open(os.path.join(ordner, TERMINALBEFEHL), "w", encoding="utf-8") as f:
        f.write(f"python3 ~/{name}/runde.py --laufen\n")
    with open(os.path.join(ordner, ANLEITUNG), "w", encoding="utf-8") as f:
        f.write(f"""Rundenpaket auf einer frischen virtuellen Maschine — reibungsloser Ablauf

  0. Den Ordner {name} in das Benutzerverzeichnis kopieren. Aus dem Packprotokoll
     auf dem Mac die Zeile „Manifest:“ bereithalten: --laufen nennt zu Beginn dieselbe
     Prüfsumme, sonst ist das Paket nicht das gepackte — dann startet kein Prüfstand.

Damit die Systemabfrage „Darf die Probe nach Geräten in lokalen Netzwerken suchen?“
während der Prüfstände ausbleibt (sie käme sonst beim ersten Öffnen-Dialog und ließe
einen Lauf rot werden), vor dem Start:

  1. Die Probe ({os.path.basename(probe)} aus diesem Ordner) einmal per Doppelklick
     öffnen und wieder beenden — damit kennt macOS sie.
  2. Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk →
     den Schalter für die Probe einschalten.
  3. Den Container der Probe löschen: ~/Library/Containers/ → Ordner der Probe
     (im Finder „{probename(info)}“) in den Papierkorb — der erste Start hat ihn
     angelegt; die Runde braucht einen frischen.
  4. Das Rundenpaket im Terminal starten (Befehl in {TERMINALBEFEHL}):
         python3 ~/{name}/runde.py --laufen

Empfehlung des Autors vom 16.09.2026; macOS merkt sich die Erlaubnis für die Probe,
bis die virtuelle Maschine zurückgesetzt wird.
""")
    try:
        summe = manifestSchreiben(ordner)
    except OSError as fehler:
        bilanz.sag(f"MANIFEST ✗ — {fehler.filename} nicht lesbar ({fehler.strerror}); das Rundenpaket ist unvollständig")
        return False
    bilanz.sag(f"Manifest: {summe} ({len(manifestDateien(ordner))} Dateien) — im Gast nennt --laufen dieselbe Prüfsumme")
    bilanz.sag("Rundenpaket:", ordner)
    return True


def laufen():
    ordner = HIER
    proben = glob.glob(os.path.join(ordner, "Probe-*.app"))
    saat = os.path.join(ordner, "saat")
    if len(proben) != 1 or not os.path.isdir(saat):
        sys.exit("--laufen gehört ins Rundenpaket: genau eine Probe-<Fassung>-<Stufe>.app und saat/ liegen neben runde.py")
    probe = proben[0]
    kurz = befehl("scutil", "--get", "ComputerName").stdout.strip().replace(" ", "-") or "Rechner"
    bilanz = Bilanz(os.path.join(ordner, f"Protokoll-{kurz}-{stempel()}"))
    bilanz.sag("Rundenpaket:", ordner)
    # Erst der Beweis, dann die Quarantäne, dann der erste Start (N67-02, E152).
    ok, gruende = manifestPruefen(ordner)
    if not ok:
        bilanz.sag(f"MANIFEST ✗ — das Rundenpaket ist nicht das gepackte ({len(gruende)} Abweichungen); kein Prüfstand startet:")
        for grund in gruende[:20]:
            bilanz.sag("   ", grund)
        bilanz.sag("Protokoll:", bilanz.ordner)
        return False
    bilanz.sag(f"Manifest: {manifestSumme(ordner)} ✓ ({len(manifestDateien(ordner))} Dateien unverändert) — mit dem Packprotokoll am Mac vergleichen")
    ok, text = probePruefen(probe)
    if not ok:
        bilanz.sag("codesign --verify --strict ✗ — die Signatur der Probe hält nicht; kein Prüfstand startet:", text)
        bilanz.sag("Protokoll:", bilanz.ordner)
        return False
    bilanz.sag("Probe verify --strict: ✓")
    subprocess.run(["xattr", "-dr", "com.apple.quarantine", ordner], capture_output=True)
    with open(os.path.join(ordner, "PRUEFSUMMEN.txt"), encoding="utf-8") as f:
        for zeile in f:
            bilanz.sag("  " + zeile.rstrip())
    ok = runde(probe, saat, bilanz)
    bilanz.sag("Protokoll:", bilanz.ordner)
    return ok


def selbsttest():
    """Die Bewertung an synthetischen Ausgaben — die Abnahmefälle der dreizehnten
    Review (N67-01) und der eigene Fund (stiller Frühausstieg). Kein Prüfstand
    startet, kein Paket wird gebraucht."""
    syntax()
    P = "Paket: org.3ducation.Unterrichtsplanung.probe 1.9.5 (76), Quellenstand abcabcabcabc…, Werkzeugstand d840422ba290…"
    F = "Paket: org.3ducation.Unterrichtsplanung 1.9.5 (76), Quellenstand abcabcabcabc…, Werkzeugstand d840422ba290…"
    def abbruch(stelle="vorbereitet", gemeldet=None):
        gemeldet = stelle if gemeldet is None else gemeldet
        return ["UEBERGANGSTEST (einschalten)", "  ✓ Planung geladen — Stand aus",
                f"  UEBERGANG_ABBRUCH={stelle}: der Prozess endet nach diesem Schritt",
                abbruchzeile(gemeldet) if gemeldet else "UEBERGANG_ABBRUCH: harter Abbruch nach"]
    # (Beschreibung, Zeilen, Rückgabe, erwartet, Auftrag, verlangte Abbruchstelle, soll bestehen)
    V = "vorbereitet"
    faelle = [
        ("nur Paketzeile und Rückgabe 0 besteht nicht", [P], 0, 0, "KLICKTEST", None, False),
        ("Zusicherungen ohne Ende bestehen nicht", [P, "KLICKTEST a ✓", "KLICKTEST b ✓", "KLICKTEST c ✓"], 0, 0, "KLICKTEST", None, False),
        ("stiller Frühausstieg (kein ✓, kein ✗, kein Ende) besteht nicht", [P, "KLICKTEST keine Planung"], 0, 0, "KLICKTEST", None, False),
        ("Ende ohne eine einzige Zusicherung besteht nicht", [P, f"{ENDE} KLICKTEST"], 0, 0, "KLICKTEST", None, False),
        ("ein ✗ vor dem Ende besteht nicht", [P, "KLICKTEST a ✓", "KLICKTEST ✗ b", f"{ENDE} KLICKTEST"], 0, 0, "KLICKTEST", None, False),
        ("falsche Paketzeile besteht nicht", [F, "KLICKTEST a ✓", f"{ENDE} KLICKTEST"], 0, 0, "KLICKTEST", None, False),
        ("das Ende eines anderen Prüfstands zählt nicht", [P, "KLICKTEST a ✓", f"{ENDE} TOURTEST"], 0, 0, "KLICKTEST", None, False),
        ("falsche Rückgabe besteht nicht", [P, "KLICKTEST a ✓", f"{ENDE} KLICKTEST"], 1, 0, "KLICKTEST", None, False),
        ("Frist besteht nicht", [P, "KLICKTEST a ✓"], "FRIST", 0, "KLICKTEST", None, False),
        ("vollständiger Lauf besteht", [P, "KLICKTEST a ✓", "KLICKTEST b ✓", f"{ENDE} KLICKTEST"], 0, 0, "KLICKTEST", None, True),
        ("Ende darf vor Zeilen der Fehlerausgabe stehen", [P, "KLICKTEST a ✓", f"{ENDE} KLICKTEST", "2026-09-17 … NSWindow warning"], 0, 0, "KLICKTEST", None, True),
        ("gewollter Abbruch (Exit 3) mit der Zeile des Dienstes an der verlangten Stelle besteht", [P] + abbruch(), 3, 3, "UEBERGANGSTEST", V, True),
        ("Rückgabe 3 ohne die Abbruchzeile besteht nicht", [P, "UEBERGANGSTEST (einschalten)", "  ✓ Planung geladen"], 3, 3, "UEBERGANGSTEST", V, False),
        ("Abbruch mit Ende-Zeile besteht nicht — regulär beendet statt abgebrochen", [P] + abbruch() + [f"{ENDE} UEBERGANGSTEST"], 3, 3, "UEBERGANGSTEST", V, False),
        ("Abbruch ohne eine einzige Zusicherung besteht nicht", [P, abbruch()[0], abbruch()[2], abbruch()[3]], 3, 3, "UEBERGANGSTEST", V, False),
        # Die vier Fälle der vierzehnten Review (N68-01): die gemeldete Stelle muss die verlangte sein.
        ("verlangt „vorbereitet“, gemeldet „vorbereitet“ besteht", [P] + abbruch("vorbereitet"), 3, 3, "UEBERGANGSTEST", "vorbereitet", True),
        ("verlangt „einsetzen“, gemeldet „vorbereitet“ besteht nicht", [P] + abbruch("einsetzen", "vorbereitet"), 3, 3, "UEBERGANGSTEST", "einsetzen", False),
        ("verlangt „aufgeraeumt“, gemeldet „uebergeben“ besteht nicht", [P] + abbruch("aufgeraeumt", "uebergeben"), 3, 3, "UEBERGANGSTEST", "aufgeraeumt", False),
        ("Abbruchzeile ohne Stelle besteht nicht", [P] + abbruch("einsetzen", ""), 3, 3, "UEBERGANGSTEST", "einsetzen", False),
        ("Abbruch ohne verlangte Stelle besteht nicht — der Treiber muss sagen, was er verlangt", [P] + abbruch(), 3, 3, "UEBERGANGSTEST", None, False),
        # Das Abschluss-Protokoll (N67-01 Rest, v69): vor dem Abschluss beendet heißt nicht bestanden.
        ("✓, dann ABGEBROCHEN mit Rückgabe 0 besteht nicht", [P, "KLICKTEST a ✓", f"{ABGEBROCHEN} KLICKTEST ✗ — beendet vor dem Abschluss"], 0, 0, "KLICKTEST", None, False),
        ("ABGEBROCHEN und dennoch ENDE besteht nicht", [P, "KLICKTEST a ✓", f"{ABGEBROCHEN} KLICKTEST ✗ — beendet vor dem Abschluss", f"{ENDE} KLICKTEST"], 0, 0, "KLICKTEST", None, False),
    ]
    alle = True
    for text, zeilen, code, erwartet, auftrag, stelle, soll in faelle:
        ist = bewerten(zeilen, code, erwartet, P, auftrag, stelle)[0]
        gilt = ist == soll
        alle = alle and gilt
        print(f"  {'✓' if gilt else '✗'} {text}" + ("" if gilt else f" — Bewertung sagt {'bestanden' if ist else 'nicht bestanden'}"))
    # Die Gegenprobe (N67-01 Rest): (Beschreibung, Zeilen, Rückgabe, soll bestehen)
    frueh = "KLICKTEST PRUEFSTAND_FRUEHES_ENDE: der Prozess endet jetzt regulär, vor dem Abschluss des Prüfstands"
    abgebrochen = f"{ABGEBROCHEN} KLICKTEST ✗ — beendet vor dem Abschluss"
    gegenfaelle = [
        ("früher regulärer Ausstieg mit ENDE besteht die Gegenprobe nicht — der Befund", [P, "KLICKTEST a ✓", frueh, f"{ENDE} KLICKTEST"], 0, False),
        ("früher Ausstieg mit ABGEBROCHEN und ohne ENDE besteht die Gegenprobe", [P, "KLICKTEST a ✓", frueh, abgebrochen], 0, True),
        ("ABGEBROCHEN und dennoch ENDE besteht die Gegenprobe nicht — widersprüchlich", [P, "KLICKTEST a ✓", frueh, abgebrochen, f"{ENDE} KLICKTEST"], 0, False),
        ("stiller Ausstieg ohne beides besteht die Gegenprobe nicht — nichts bewiesen", [P, "KLICKTEST a ✓", frueh], 0, False),
        ("die Abbruchmeldung eines anderen Prüfstands zählt nicht", [P, "KLICKTEST a ✓", frueh, f"{ABGEBROCHEN} TOURTEST ✗"], 0, False),
        # Die Tabelle der fünfzehnten Review (N69-01) und die eigenen Fälle (v70):
        ("N69-01, der Fall des Berichts: nur ABGEBROCHEN, Rückgabe 1, fremde Paketzeile — besteht nicht", [abgebrochen], 1, False),
        ("N69-01: Paketzeile fehlt — besteht nicht", ["KLICKTEST a ✓", frueh, abgebrochen], 0, False),
        ("N69-01: fremde Paketzeile (das echte Paket) — besteht nicht", [F, "KLICKTEST a ✓", frueh, abgebrochen], 0, False),
        ("N69-01: keine Zusicherung vor dem Haken — besteht nicht", [P, frueh, abgebrochen], 0, False),
        ("N69-01: Zusicherung erst nach dem Haken — besteht nicht", [P, frueh, "KLICKTEST a ✓", abgebrochen], 0, False),
        ("N69-01: Hakenzeile fehlt — besteht nicht", [P, "KLICKTEST a ✓", abgebrochen], 0, False),
        ("N69-01: Hakenzeile zweimal — besteht nicht", [P, "KLICKTEST a ✓", frueh, frueh, abgebrochen], 0, False),
        ("N69-01: Rückgabe 1 — besteht nicht", [P, "KLICKTEST a ✓", frueh, abgebrochen], 1, False),
        ("N69-01: Frist statt Rückgabe — besteht nicht", [P, "KLICKTEST a ✓", frueh, abgebrochen], "FRIST", False),
        ("N69-01: ABGEBROCHEN zweimal — besteht nicht", [P, "KLICKTEST a ✓", frueh, abgebrochen, abgebrochen], 0, False),
        ("N69-01: ABGEBROCHEN vor dem Haken — besteht nicht", [P, "KLICKTEST a ✓", abgebrochen, frueh], 0, False),
        ("N69-01: nach ABGEBROCHEN noch eine Prüfstandszeile — besteht nicht", [P, "KLICKTEST a ✓", frueh, abgebrochen, "KLICKTEST b ✓"], 0, False),
        ("N69-01: eine fremde ✗-Zeile dazu — ein anderer Befund, besteht nicht", [P, "KLICKTEST a ✓", "KLICKTEST b ✗", frueh, abgebrochen], 0, False),
        ("N69-01: fremde Zeilen ohne Kennzeichen (stderr) stören nicht", [P, "KLICKTEST a ✓", frueh, abgebrochen, "irgendein Systemhinweis"], 0, True),
    ]
    for text, zeilen, code, soll in gegenfaelle:
        ist = gegenprobeBewerten(zeilen, code, P, "KLICKTEST")[0]
        gilt = ist == soll
        alle = alle and gilt
        print(f"  {'✓' if gilt else '✗'} Gegenprobe: {text}" + ("" if gilt else f" — Gegenprobe sagt {'bestanden' if ist else 'nicht bestanden'}"))
    # Der Ausgang in Worten (E163): drei Wege, drei Sätze.
    for text, zeilen, code, erwartetText in [
        ("vollständig", [P, "KLICKTEST a ✓", frueh, abgebrochen], 0, "vor dem Abschluss beendet und abgewiesen — wie verlangt"),
        ("der Befund", [P, "KLICKTEST a ✓", frueh, f"{ENDE} KLICKTEST"], 0, "Voraussetzung nicht erfüllt: ABGEBROCHEN einmal, zuletzt, ENDE fehlt"),
        ("Rückgabe 1", [P, "KLICKTEST a ✓", frueh, abgebrochen], 1, "Voraussetzung nicht erfüllt: Rückgabe 0"),
    ]:
        _, v, bewertungOk = gegenprobeBewerten(zeilen, code, P, "KLICKTEST")
        ist = gegenprobeAusgang(v, bewertungOk)
        gilt = ist == erwartetText
        alle = alle and gilt
        print(f"  {'✓' if gilt else '✗'} Gegenprobe, Ausgang „{text}“: {ist}")
    # Das Merkmal Korrektur am Paket: Die Zeile des Klicktests muss stehen und ✓ tragen.
    for text, zeilen, soll in [
        ("gelesen — belegt", [P, "KLICKTEST Korrektur aus der Datei: 1 gelesen ✓"], True),
        ("keine in der Planung — nicht belegt", [P, "KLICKTEST Korrektur aus der Datei: keine in dieser Planung — übersprungen"], False),
        ("die Zeile fehlt — nicht belegt", [P, "KLICKTEST Hausaufgabe an ✓, aus ✓"], False),
        ("gelesen, aber mit ✗ — nicht belegt", [P, "KLICKTEST Korrektur aus der Datei: 0 gelesen ✗"], False),
    ]:
        gilt = korrekturBelegt(zeilen) == soll
        alle = alle and gilt
        print(f"  {'✓' if gilt else '✗'} Korrektur aus der Saat: {text}")
    for argumente, soll in ((["--klicktest"], "KLICKTEST"), (["--entsperrtest", "passphrase"], "ENTSPERRTEST"),
                            (["--uebergangstest", "einschalten"], "UEBERGANGSTEST"),
                            (["--materialtest"], "MATERIALTEST")):
        gilt = auftragsname(argumente) == soll
        alle = alle and gilt
        print(f"  {'✓' if gilt else '✗'} Auftragsname {argumente} → {soll}")
    alle = manifestSelbsttest() and alle
    print("Selbsttest des Rundentreibers:", "bestanden" if alle else "mit Befund ✗")
    return alle


def manifestSelbsttest():
    """Das Rundenpaket beweist seine Unversehrtheit (N67-02): an einem Wegwerf-Paket
    im Temporärordner — geändert, fehlend, zusätzlich, verify eingespritzt."""
    import tempfile
    alle = True

    def fall(text, gilt, grund=""):
        nonlocal alle
        alle = alle and gilt
        print(f"  {'✓' if gilt else '✗'} {text}" + ("" if gilt or not grund else f" — {grund}"))

    with tempfile.TemporaryDirectory() as wurzel:
        paket = os.path.join(wurzel, "Rundenpaket-0.0.0-0")
        for rel, inhalt in (("Probe-0.0.0-0.app/Contents/MacOS/x", b"programm"), ("Probe-0.0.0-0.app/Contents/Info.plist", b"<plist/>"),
                            ("saat/klartext.json", b"{}"), ("runde.py", b"# skript"), ("LIESMICH.txt", b"lies"),
                            ("Anleitung-VM.txt", b"anleitung"), ("Terminalbefehl.txt", b"befehl"), ("PRUEFSUMMEN.txt", b"summen")):
            pfad = os.path.join(paket, rel)
            os.makedirs(os.path.dirname(pfad), exist_ok=True)
            with open(pfad, "wb") as f:
                f.write(inhalt)
        os.makedirs(os.path.join(paket, "Packprotokoll"))
        with open(os.path.join(paket, "Packprotokoll", "runde.txt"), "w") as f:
            f.write("Packprotokoll\n")
        try:
            summe = manifestSchreiben(paket)
            fall("Manifest geschrieben (8 Dateien, Packprotokoll ausgenommen)", isinstance(summe, str) and len(summe) == 64
                 and sum(1 for _ in open(os.path.join(paket, MANIFEST), encoding="utf-8")) == 8)
            ok, gruende = manifestPruefen(paket)
            fall("unverändertes Paket besteht", ok and not gruende, "; ".join(gruende))
            # Ein Ordner, der sich nicht lesen lässt: benannt, nicht übergangen —
            # beim Prüfen wie beim Schreiben (R75-02, v76).
            saat = os.path.join(paket, "saat")
            os.chmod(saat, 0)
            try:
                ok, gruende = manifestPruefen(paket)
                fall("ein unlesbarer Ordner wird benannt, nicht übergangen",
                     not ok and any("saat" in g and "nicht lesbar" in g for g in gruende), "; ".join(gruende))
                try:
                    manifestSchreiben(paket)
                    fall("über einem unlesbaren Ordner entsteht kein Manifest", False, "geschrieben")
                except OSError:
                    fall("über einem unlesbaren Ordner entsteht kein Manifest", True)
            finally:
                os.chmod(saat, 0o755)
                summe = manifestSchreiben(paket)
            with open(os.path.join(paket, "saat", "klartext.json"), "ab") as f:
                f.write(b" ")
            ok, gruende = manifestPruefen(paket)
            fall("eine geänderte Saatdatei wird benannt", not ok and any("saat/klartext.json" in g and "anders" in g for g in gruende), "; ".join(gruende))
            with open(os.path.join(paket, "saat", "klartext.json"), "wb") as f:
                f.write(b"{}")
            os.remove(os.path.join(paket, "Terminalbefehl.txt"))
            ok, gruende = manifestPruefen(paket)
            fall("eine fehlende Datei wird benannt", not ok and any("Terminalbefehl.txt" in g and "fehlt" in g for g in gruende), "; ".join(gruende))
            with open(os.path.join(paket, "Terminalbefehl.txt"), "wb") as f:
                f.write(b"befehl")
            with open(os.path.join(paket, "Probe-0.0.0-0.app", "Contents", "Resources.txt"), "wb") as f:
                f.write(b"fremd")
            ok, gruende = manifestPruefen(paket)
            fall("eine zusätzliche Datei im Bündel wird benannt", not ok and any("Resources.txt" in g and "zusätzlich" in g for g in gruende), "; ".join(gruende))
            os.remove(os.path.join(paket, "Probe-0.0.0-0.app", "Contents", "Resources.txt"))
            for harmlos in (".DS_Store", "saat/.DS_Store"):
                with open(os.path.join(paket, harmlos), "wb") as f:
                    f.write(b"finder")
            os.makedirs(os.path.join(paket, "Protokoll-Rechner-2026-09-17-120000"))
            with open(os.path.join(paket, "Protokoll-Rechner-2026-09-17-120000", "runde.txt"), "w") as f:
                f.write("x")
            ok, gruende = manifestPruefen(paket)
            fall(".DS_Store des Finders, Packprotokoll und Protokollordner stören nicht", ok and not gruende, "; ".join(gruende))
            with open(os.path.join(paket, MANIFEST), "ab") as f:
                f.write(b"\n")
            fall("ein verändertes Manifest hat eine andere Prüfsumme", manifestSumme(paket) != summe)
            os.remove(os.path.join(paket, MANIFEST))
            ok, gruende = manifestPruefen(paket)
            fall("ohne Manifest besteht nichts", not ok and any(MANIFEST in g for g in gruende), "; ".join(gruende))
            probe = os.path.join(paket, "Probe-0.0.0-0.app")
            ok, text = probePruefen(probe, verify=lambda p: (1, "invalid signature (eingespritzt)"))
            fall("ein eingespritzter verify-Fehler ist tödlich", not ok and "eingespritzt" in text)
            ok, text = probePruefen(probe, verify=lambda p: (0, ""))
            fall("verify ohne Befund besteht", ok)
        except NameError as e:
            fall("Manifestprüfung vorhanden", False, str(e))
    return alle


def syntax():
    # Im Speicher übersetzt, nicht mit py_compile: Das schriebe __pycache__ in
    # den Fassungsordner — neben den Quellenstand, in den es nicht gehört.
    with open(os.path.abspath(__file__), encoding="utf-8") as f:
        compile(f.read(), __file__, "exec")
    print("Form des Rundentreibers stimmig (compile)")
    return True


if __name__ == "__main__":
    argumente = sys.argv[1:]
    if argumente == ["--syntax"]:
        ok = syntax()
    elif argumente == ["--selbsttest"]:
        ok = selbsttest()
    elif argumente == ["--laufen"]:
        ok = laufen()
    elif len(argumente) == 2 and argumente[0] == "--packen":
        ok = packen(argumente[1])
    elif not argumente:
        ok = imFassungsordner()
    else:
        sys.exit(__doc__)
    sys.exit(0 if ok else 1)
