#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: GPL-3.0-or-later
"""Die Prüfstandsrunde am gebauten Paket — 26 Läufe an einer Probe-Kopie.

    python3 runde.py                 Runde am Paket dieses Fassungsordners
                                     (Paket/Unterrichtsplanung.app); Saat wird
                                     erzeugt; Protokoll nach Paket/Runde-<Stempel>/
    python3 runde.py --packen ZIEL   Rundenpaket für einen anderen Rechner (VM):
                                     ZIEL/Rundenpaket-<Fassung>-<Stufe>/ mit der
                                     fertigen Probe, saat/, diesem Skript, LIESMICH,
                                     PRUEFSUMMEN.txt — im Gast wird nichts signiert
    python3 runde.py --laufen        im Rundenpaket: Probe und Saat aus dem eigenen
                                     Ordner, Protokoll-<Rechner>-<Stempel>/ daneben
    python3 runde.py --syntax        nur die Form dieses Skripts (für pruefen.sh)

Rezept (seit v37, Routine je Fassung): Kopie des Pakets mit der Kennung
`org.3ducation.Unterrichtsplanung.probe`, Manifest ohne Umzugsquelle, ad hoc mit
den Berechtigungen neu gesiegelt; das Programm ist vor dem Umsignieren bytegleich
mit dem Paket (Prüfsumme im Protokoll). **Das echte Paket startet nie** — hier
nicht und im Gast nicht (E147). Jeder Lauf allein, mit Abstand; Prüfordner
unterhalb des Containers der Probe (`Unterrichtsplanung --container`); Saat aus
`tresor_pruefen.py --erzeugen` (Passphrase und Schlüssel aus `vektoren.json`).
Jeder Prüfstand beginnt mit seiner Paketzeile (E128, E144); jede rote Zeile ist
ein Befund (seit v66 kein „bekanntes ✗“ mehr). Auf jedem System gelten dieselben
26 Läufe und Erwartungen (E148); was vom System abhängt — Rechner, Touch ID, die
Bedingung der Wicklung dieses Macs —, steht in der Bilanz, und die Erwartung an
die Bedingung folgt dem Gerät: ohne angelernte Finger „Anmeldepasswort“.
Braucht nur, was macOS mitbringt: python3, codesign, PlistBuddy, xattr,
killall, bioutil, sw_vers.
"""
import glob, hashlib, json, os, plistlib, shutil, subprocess, sys, time

KENNUNG = "org.3ducation.Unterrichtsplanung.probe"
LSREGISTER = ("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework"
              "/Support/lsregister")
NAME = "Unterrichtsplanung"
ABSTAND = 4
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
    r = befehl("codesign", "--verify", "--strict", ziel)
    bilanz.sag("Probe ad hoc gesiegelt, verify --strict:", "✓" if r.returncode == 0 else "✗ " + r.stderr)
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

    def lauf(name, argumente, umgebung=None, ordnerpfad=None, erwartet=0, frist=420):
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
        gruen = sum(1 for z in zeilen if "✓" in z)
        rot = [z for z in zeilen if "✗" in z]
        paketOk = erste.startswith(paketanfang)
        ok = code == erwartet and not rot and paketOk
        ergebnisse.append((name, ok, gruen, len(rot), paketOk))
        bilanz.sag(f"{nummer:02d} {name:28s} {'✓' if ok else '✗'}  Rückgabe {code} (erwartet {erwartet}), "
                   f"{gruen} ✓, {len(rot)} ✗, Paketzeile {'✓' if paketOk else '✗ ' + erste[:80]}, {dauer:.0f} s")
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
    # 12–13 Dialoge
    lauf("dialog-klartext", ["--dialogtest"], ordnerpfad=ordner("dialog-klartext", "klartext.json"))
    lauf("dialog-versiegelt", ["--dialogtest"], versiegelt, ordnerpfad=ordner("dialog-versiegelt", "planung.json"))
    # 14–18 Übergänge, fünf Arten
    lauf("uebergang-einschalten", ["--uebergangstest", "einschalten"], uebergang, ordnerpfad=ordner("ueb-einschalten", "klartext.json"))
    for art in ("erneuern", "passphrase", "wicklung", "aufheben"):
        lauf(f"uebergang-{art}", ["--uebergangstest", art], uebergang, ordnerpfad=ordner(f"ueb-{art}", "planung.json"))
    # 19–26 vier Abbrüche (Exit 3) mit zweitem Start
    for stelle in ("vorbereitet", "uebergeben", "einsetzen", "aufgeraeumt"):
        pfad = ordner(f"ueb-abbruch-{stelle}", "klartext.json")
        lauf(f"abbruch-{stelle}", ["--uebergangstest", "einschalten"], {**uebergang, "UEBERGANG_ABBRUCH": stelle},
             ordnerpfad=pfad, erwartet=3)
        lauf(f"abbruch-{stelle}-2.Start", ["--uebergangstest", "pruefen"], uebergang, ordnerpfad=pfad)

    # Die Bedingung der Wicklung dieses Macs folgt dem Gerät (E148, E141).
    bedingungZeile = next((z for z in protokolle.get("uebergang-wicklung", []) if "Wicklung dieses Macs: angelegt" in z), "")
    bedingungOk = None
    if erwarteteBedingung is not None and bedingungZeile:
        bedingungOk = erwarteteBedingung in bedingungZeile
        bilanz.sag(f"Bedingung der Wicklung dieses Macs: {bedingungZeile.strip()} — erwartet nach dem Gerät "
                   f"{erwarteteBedingung} {'✓' if bedingungOk else '✗'}")

    gruenGesamt = sum(e[2] for e in ergebnisse)
    rotGesamt = sum(e[3] for e in ergebnisse)
    okLaeufe = sum(1 for e in ergebnisse if e[1])
    bilanz.sag(f"\nRUNDE: {okLaeufe}/{len(ergebnisse)} Läufe grün, {gruenGesamt} Zusicherungen, {rotGesamt} ✗; "
               f"Paketzeile in {sum(1 for e in ergebnisse if e[4])}/{len(ergebnisse)} Läufen; "
               f"Bedingung der Wicklung {'✓' if bedingungOk else ('✗' if bedingungOk is False else 'nicht geprüft')}; "
               f"{rechner()}; Touch ID {'eingerichtet' if fingerabdruecke else 'nicht eingerichtet' if fingerabdruecke is False else 'unbekannt'}")
    bilanz.sag(f"Probe-Container (im Finder „{probename(info)}“, zu entfernen):", os.path.dirname(container))
    return okLaeufe == len(ergebnisse) and bedingungOk is not False


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
runde.py, PRUEFSUMMEN.txt. Braucht nur macOS und python3 (3.9 oder neuer), kein Xcode.

Den ganzen Ordner auf den Rechner kopieren (Programme-Ordner oder Schreibtisch), dann im
Terminal, angemeldet am Bildschirm (die Prüfstände öffnen Fenster):

    python3 "{name}/runde.py" --laufen

Das Skript entfernt zuerst die Quarantäne des Ordners, macht einen ungezählten Vorlauf
mit dem ersten Dateidialog — auf einem frischen System fragt macOS dabei einmal, ob die
App Geräte im lokalen Netzwerk suchen darf: bitte quittieren —, fährt dann die 26 Läufe
(etwa fünf Minuten, jeder Lauf allein — den Rechner derweil nicht benutzen) und schreibt
Protokoll-<Rechner>-<Stempel>/ in diesen Ordner. Diesen Protokollordner zurückbringen.
Danach den Probe-Container entfernen — im Finder heißt er „{probename(info)}“:
~/Library/Containers/{KENNUNG}
""")
    bilanz.sag("Rundenpaket:", ordner)
    return True


def laufen():
    ordner = HIER
    proben = glob.glob(os.path.join(ordner, "Probe-*.app"))
    saat = os.path.join(ordner, "saat")
    if len(proben) != 1 or not os.path.isdir(saat):
        sys.exit("--laufen gehört ins Rundenpaket: genau eine Probe-<Fassung>-<Stufe>.app und saat/ liegen neben runde.py")
    probe = proben[0]
    subprocess.run(["xattr", "-dr", "com.apple.quarantine", ordner], capture_output=True)
    kurz = befehl("scutil", "--get", "ComputerName").stdout.strip().replace(" ", "-") or "Rechner"
    bilanz = Bilanz(os.path.join(ordner, f"Protokoll-{kurz}-{stempel()}"))
    bilanz.sag("Rundenpaket:", ordner)
    with open(os.path.join(ordner, "PRUEFSUMMEN.txt"), encoding="utf-8") as f:
        for zeile in f:
            bilanz.sag("  " + zeile.rstrip())
    ok = runde(probe, saat, bilanz)
    bilanz.sag("Protokoll:", bilanz.ordner)
    return ok


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
    elif argumente == ["--laufen"]:
        ok = laufen()
    elif len(argumente) == 2 and argumente[0] == "--packen":
        ok = packen(argumente[1])
    elif not argumente:
        ok = imFassungsordner()
    else:
        sys.exit(__doc__)
    sys.exit(0 if ok else 1)
