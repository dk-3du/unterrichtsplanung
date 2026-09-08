#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Prüfvektoren für den Tresor — derselbe Behälter, von beiden Seiten geöffnet.

Die App (`Dienste/Tresor.swift`) und die Ansicht (`kopfLesen`, `entwickeln`,
`behaelterOeffnen`, `behaelterVersiegeln` …) müssen denselben verschlüsselten
Behälter lesen und schreiben — Passphrase über PBKDF2-HMAC-SHA256, der
Wiederherstellungsschlüssel über HKDF, die Nutzlast über AES-256-GCM, die
Zusatzdaten als kurze feste Zeichenketten. Zwei Stellen, an denen die beiden
Fassungen stumm auseinanderlaufen könnten: die NFC-Normalisierung der
Passphrase und die Base64/Hex-Kodierung der Felder. `jsc` kennt kein
`crypto.subtle`; die Ansichtsseite läuft deshalb nur im echten Browser.

Dieses Skript liefert beides:

* die App-Seite als kleines Programm — `Tresor.swift` und `Ablage.swift` der
  App werden mit `swiftc` übersetzt (sie hängen an nichts als Foundation,
  CryptoKit, Security und LocalAuthentication);
* eine Probeseite `tresor_probe.html`, die die Tresor-Funktionen der Ansicht
  (per Klammerzählung aus der HTML gezogen) mit eingebetteten Vektoren im
  Browser laufen lässt, jedes Ergebnis groß auf den Schirm schreibt und einen
  von der Ansicht versiegelten Statusbehälter zum Gegenlesen anbietet.

  python3 tresor_pruefen.py --erzeugen ORDNER            Vektoren mit der App-Seite schreiben
  python3 tresor_pruefen.py --oeffnen DATEI --passphrase WORT
  python3 tresor_pruefen.py --oeffnen DATEI --wiederherstellung SCHLUESSEL
  python3 tresor_pruefen.py --kopf DATEI                 den Kopf ohne Schlüssel prüfen
  python3 tresor_pruefen.py --probe ORDNER               Probeseite aus den Vektoren in ORDNER bauen

Braucht `swiftc` (Xcode). Die Probeseite verlangt einen sicheren Kontext
(http://localhost oder https). Ergebnis: Exit 0/1.
"""

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HIER = Path(__file__).resolve().parent
HTML = HIER / "unterrichtsplanung-ansicht.html"
DIENSTE = HIER.parent.parent / "macOS-App" / HIER.name / "Quellen" / "Unterrichtsplanung" / "Dienste"
PASSPHRASE = "Ein Satz, den man behält — mit ä und ß"

CLI = r'''
import CryptoKit
import Foundation

func lesen(_ pfad: String) -> Data { FileManager.default.contents(atPath: pfad) ?? Data() }
func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
func sha(_ d: Data) -> String { hex(Data(SHA256.hash(data: d))) }
func aus(_ zeilen: [String: Any]) {
    let daten = try! JSONSerialization.data(withJSONObject: zeilen, options: [.sortedKeys])
    print(String(decoding: daten, as: UTF8.self))
}

// Keine Enklave in einem Werkzeug: Der Prüfstand-Riegel der App greift über die Umgebung.
setenv("PLANUNGSORDNER", "/nirgends", 1)
let args = CommandLine.arguments
switch args[1] {
case "erzeugen":
    let klartext = lesen(args[2])
    let passphrase = args[3]
    let ziel = args[4]
    let t = Tresor.neu()
    try t.passphraseSetzen(passphrase)
    let blatt = try t.wiederherstellungAnlegen()
    try t.versiegeln(klartext, inhalt: .planung, ziel: .kopie)
        .write(to: URL(fileURLWithPath: ziel + "/planung.json"))
    try t.versiegeln(klartext, inhalt: .planung, ziel: .export)
        .write(to: URL(fileURLWithPath: ziel + "/export.json"))
    let status = Data("{\"typ\":\"unterrichtsplanung-status\",\"version\":1,\"eintraege\":{}}".utf8)
    try t.versiegeln(status, inhalt: .status, ziel: .kopie)
        .write(to: URL(fileURLWithPath: ziel + "/status.json"))
    aus(["kennung": t.kennungHex, "wiederherstellung": blatt, "passphrase": passphrase,
         "runden": Tresor.rundenStandard, "klartextSHA256": sha(klartext), "klartextBytes": klartext.count])
case "oeffnen":
    let kopf = try Tresor.kopfLesen(lesen(args[2]))
    let t = args[3] == "passphrase"
        ? try Tresor.oeffnen(kopf: kopf, passphrase: args[4])
        : try Tresor.oeffnen(kopf: kopf, wiederherstellung: args[4])
    let klar = try t.oeffnen(kopf: kopf)
    if args.count > 5 { try klar.write(to: URL(fileURLWithPath: args[5])) }
    aus(["inhalt": kopf.inhalt, "kennung": kopf.kennungHex, "sha256": sha(klar), "bytes": klar.count,
         "wicklungen": kopf.wicklungen.map(\.art)])
case "kopf":
    let kopf = try Tresor.kopfLesen(lesen(args[2]))
    aus(["inhalt": kopf.inhalt, "kennung": kopf.kennungHex, "version": kopf.version,
         "wicklungen": kopf.wicklungen.map(\.art), "chiffratBytes": kopf.daten.count])
default:
    FileHandle.standardError.write(Data("unbekannt: \(args[1])\n".utf8))
    exit(2)
}
'''


def cli_bauen(arbeitsordner: Path) -> Path:
    """Übersetzt Tresor.swift und Ablage.swift der App samt Hauptprogramm."""
    ziel = arbeitsordner / "tresor_cli"
    if ziel.exists():
        return ziel
    quellen = [DIENSTE / "Tresor.swift", DIENSTE / "Ablage.swift"]
    for q in quellen:
        if not q.exists():
            raise SystemExit(f"Quelle der App nicht gefunden: {q}")
    haupt = arbeitsordner / "main.swift"
    haupt.write_text(CLI, encoding="utf-8")
    befehl = ["swiftc", "-O", "-swift-version", "6", "-target", "arm64-apple-macosx26.0",
              "-module-name", "TresorCLI", *map(str, quellen), str(haupt), "-o", str(ziel)]
    lauf = subprocess.run(befehl, capture_output=True, text=True)
    if lauf.returncode != 0:
        raise SystemExit("swiftc scheiterte:\n" + lauf.stderr)
    return ziel


def cli(arbeitsordner: Path, *args: str) -> dict:
    lauf = subprocess.run([str(cli_bauen(arbeitsordner)), *args], capture_output=True, text=True)
    if lauf.returncode != 0:
        raise SystemExit("tresor_cli scheiterte: " + (lauf.stderr or lauf.stdout).strip())
    return json.loads(lauf.stdout.strip().splitlines()[-1])


def probeplanung() -> bytes:
    """Eine kleine, gültige Planung — mit Umlaut, Kommentar und einem Link."""
    p = {
        "typ": "unterrichtsplanung", "version": 2, "titel": "Prüfvektor 2026/27",
        "erstellt": "2026-09-04T12:00:00.000Z", "geaendert": "2026-09-04T12:00:00.000Z",
        "basis": "", "start": "2026-08-10", "wochen": 6, "ersterSchultag": "2026-08-10",
        "frei": [], "ferien": [], "sperrzeiten": [], "fachfarben": {},
        "klassen": [{"id": "k-1", "name": "G6a", "fach": "Informatik", "notiz": "",
                     "farbe": 0, "farbeManuell": False, "verwaltung": "", "curriculum": "",
                     "unterrichtstage": [1, 3]}],
        "zellenfrei": [],
        "eintraege": [{"id": "e-1", "klasseId": "k-1", "woche": 1, "titel": "Bits und Bytes",
                       "text": "Zeichen, Daten, Information — mit ä, ö, ü und ß.",
                       "erledigt": False, "materialien": [], "links": [
                           {"titel": "3ducation", "url": "https://3ducation.org/"}],
                       "pruefung": False, "pruefungstag": "", "datum": "", "dringend": False,
                       "kommentar": "", "statusGeaendert": ""}],
    }
    return json.dumps(p, ensure_ascii=False, indent=2).encode("utf-8")


def erzeugen(ordner: Path) -> int:
    ordner.mkdir(parents=True, exist_ok=True)
    klartext = ordner / "klartext.json"
    klartext.write_bytes(probeplanung())
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as arbeit:
        ergebnis = cli(Path(arbeit), "erzeugen", str(klartext), PASSPHRASE, str(ordner))
        # Gegenprobe mit derselben Seite: Passphrase und Wiederherstellung öffnen.
        for datei in ("planung.json", "export.json", "status.json"):
            kopf = cli(Path(arbeit), "kopf", str(ordner / datei))
            print(f"  {datei}: inhalt={kopf['inhalt']} wicklungen={kopf['wicklungen']}")
        mitPass = cli(Path(arbeit), "oeffnen", str(ordner / "planung.json"), "passphrase", PASSPHRASE)
        mitBlatt = cli(Path(arbeit), "oeffnen", str(ordner / "export.json"), "wiederherstellung",
                       ergebnis["wiederherstellung"].lower())
    if mitPass["sha256"] != ergebnis["klartextSHA256"] or mitBlatt["sha256"] != ergebnis["klartextSHA256"]:
        print("Die App-Seite öffnet ihre eigenen Vektoren nicht — abgebrochen.")
        return 1
    (ordner / "vektoren.json").write_text(json.dumps(ergebnis, ensure_ascii=False, indent=2),
                                          encoding="utf-8")
    print(f"Vektoren geschrieben nach {ordner} (Kennung {ergebnis['kennung']}, "
          f"{ergebnis['runden']} Runden).")
    return 0


def oeffnen(datei: Path, passphrase: str | None, wiederherstellung: str | None,
            klartext_nach: Path | None) -> int:
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as arbeit:
        if passphrase is not None:
            args = ["oeffnen", str(datei), "passphrase", passphrase]
        else:
            args = ["oeffnen", str(datei), "wiederherstellung", wiederherstellung or ""]
        if klartext_nach:
            args.append(str(klartext_nach))
        ergebnis = cli(Path(arbeit), *args)
    print(json.dumps(ergebnis, ensure_ascii=False))
    return 0


def kopf_pruefen(datei: Path) -> int:
    """Strukturell, ohne Schlüssel und ohne Swift: Was Python prüfen kann."""
    roh = datei.read_bytes()
    if not roh.startswith(b'{"typ":"unterrichtsplanung-tresor"'):
        print("  Hinweis: `typ` steht nicht vorne (die Ansicht schreibt es so, die App auch).")
    zerlegt = json.loads(roh.decode("utf-8"))
    fehler = []
    if zerlegt.get("typ") != "unterrichtsplanung-tresor":
        fehler.append("typ")
    if zerlegt.get("version") != 1:
        fehler.append("version")
    if zerlegt.get("inhalt") not in ("planung", "status", "rohdaten", "lesezeichen"):
        fehler.append("inhalt")
    kennung = zerlegt.get("schluesselkennung", "")
    if not re.fullmatch(r"[0-9a-f]{32}", str(kennung)):
        fehler.append("schluesselkennung (32 Hexziffern, klein)")
    if zerlegt.get("verfahren") != "AES-256-GCM":
        fehler.append("verfahren")

    def b64(text, laenge=None):
        try:
            bytes_ = base64.b64decode(text, validate=True)
        except Exception:
            return None
        return bytes_ if laenge is None or len(bytes_) == laenge else None

    if b64(zerlegt.get("nonce", ""), 12) is None:
        fehler.append("nonce (12 Byte Base64 mit Auffüllung)")
    daten = b64(zerlegt.get("daten", ""))
    if daten is None or len(daten) < 16:
        fehler.append("daten (Base64, Chiffrat + 16 Byte)")
    for w in zerlegt.get("wicklungen", []):
        art = w.get("art")
        if not isinstance(art, str) or not art:
            fehler.append("wicklung ohne art")
            continue
        if b64(w.get("nonce", ""), 12) is None or b64(w.get("umschlag", ""), 48) is None:
            fehler.append(f"{art}: nonce 12 Byte, umschlag 48 Byte")
        if art == "passphrase":
            if w.get("kdf") != "PBKDF2-HMAC-SHA256":
                fehler.append("passphrase: kdf")
            if not isinstance(w.get("runden"), int) or not 100_000 <= w["runden"] <= 10_000_000:
                fehler.append("passphrase: runden")
            if b64(w.get("salz", "")) is None or len(b64(w.get("salz", ""))) < 8:
                fehler.append("passphrase: salt (Feld salz)")
        if art == "wiederherstellung" and w.get("kdf") != "HKDF-SHA256":
            fehler.append("wiederherstellung: kdf")
        if art == "enklave":
            fehler.append("enklave: darf keine Kopie und keinen Export verlassen")
    print(f"  {datei.name}: inhalt={zerlegt.get('inhalt')} "
          f"wicklungen={[w.get('art') for w in zerlegt.get('wicklungen', [])]} "
          f"chiffrat={len(daten) if daten else 0} B")
    for f in fehler:
        print("  ABWEICHUNG", f)
    return 1 if fehler else 0


# ── Die Probeseite ────────────────────────────────────────────────────

BLOECKE = ["class Planungsfehler", "function istObjekt", "function textwert",
           "function ganzzahl",
           "const TRESOR_TYP", "const TRESOR_VERSION", "const TRESOR_VERFAHREN",
           "const TRESOR_KDF_PASSPHRASE", "const TRESOR_KDF_WIEDERHERSTELLUNG",
           "const TRESOR_RUNDEN_MINDESTENS", "const TRESOR_RUNDEN_HOECHSTENS",
           "const TRESOR_PASSPHRASE_MINDESTLAENGE", "const TRESOR_KENNUNG_LAENGE",
           "const TRESOR_WIEDERHERSTELLUNG_LAENGE", "const TRESOR_WIEDERHERSTELLUNG_ALPHABET",
           "const KODIERER", "const DEKODIERER",
           "function tresorMoeglich", "function istBehaelter", "function base64Zu",
           "function base64Von", "function hexVon", "function zusatz", "function kopfLesen",
           "function wicklung", "async function schluesselAusPassphrase",
           "async function schluesselAusWiederherstellung", "function wiederherstellungRoh",
           "async function entwickeln", "async function datenschluesselMitPassphrase",
           "async function datenschluesselMitWiederherstellung", "async function tresorAnlegen",
           "async function behaelterOeffnen", "async function behaelterVersiegeln"]


def block(skript: str, kopf: str) -> str:
    """Zieht `kopf …` samt Rumpf aus dem Skript: bei `const` bis zum `;` auf
    Tiefe 0, sonst bis die geschweiften Klammern wieder aufgehen."""
    start = skript.find("\n" + kopf)
    if start < 0:
        raise SystemExit(f"Block nicht gefunden: {kopf}")
    start += 1
    if kopf.startswith("const "):
        ende = skript.find(";\n", start)
        return skript[start:ende + 1]
    tiefe = 0
    i = skript.find("{", start)
    while i < len(skript):
        z = skript[i]
        if z == "{":
            tiefe += 1
        elif z == "}":
            tiefe -= 1
            if tiefe == 0:
                return skript[start:i + 1]
        elif z in "\"'`":
            # Zeichenketten überspringen — auch Vorlagen mit ${…}.
            j = i + 1
            while j < len(skript) and skript[j] != z:
                j += 2 if skript[j] == "\\" else 1
            i = j
        elif skript.startswith("//", i):
            i = skript.find("\n", i)
        elif skript.startswith("/*", i):
            i = skript.find("*/", i) + 1
        i += 1
    raise SystemExit(f"Block ohne Ende: {kopf}")


def probe_bauen(ordner: Path) -> int:
    html = HTML.read_text(encoding="utf-8")
    skript = re.search(r"<script>(.*?)</script>", html, re.S).group(1)
    teile = [block(skript, k) for k in BLOECKE]
    vektoren = json.loads((ordner / "vektoren.json").read_text(encoding="utf-8"))
    dateien = {name: (ordner / name).read_text(encoding="utf-8")
               for name in ("planung.json", "export.json", "status.json")}
    seite = PROBE.replace("/*FUNKTIONEN*/", "\n\n".join(teile)) \
        .replace("/*VEKTOREN*/", json.dumps(vektoren, ensure_ascii=False)) \
        .replace("/*DATEIEN*/", json.dumps(dateien, ensure_ascii=False))
    ziel = ordner / "tresor_probe.html"
    ziel.write_text(seite, encoding="utf-8")
    print(f"Probeseite: {ziel} — über http://localhost oder https aufrufen; die Ergebnisse "
          "stehen groß auf der Seite, der versiegelte Status zum Gegenlesen im Textfeld.")
    return 0


PROBE = r'''<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"><title>Tresor-Probe</title>
<style>
body { font: 16px/1.5 -apple-system, system-ui, sans-serif; margin: 24px; }
#ergebnis { font-size: 28px; line-height: 1.35; white-space: pre-wrap; }
#ergebnis .gut { color: #0f766e; } #ergebnis .schlecht { color: #b42318; font-weight: 700; }
textarea { width: 100%; height: 160px; font: 12px ui-monospace, monospace; }
</style></head><body>
<h1>Tresor-Probe</h1>
<div id="ergebnis">läuft …</div>
<h2>Von der Ansicht versiegelter Status (zum Gegenlesen mit tresor_pruefen.py --oeffnen)</h2>
<textarea id="status" readonly></textarea>
<script>
/*FUNKTIONEN*/

const VEKTOREN = /*VEKTOREN*/;
const DATEIEN = /*DATEIEN*/;
const zeilen = [];
function schreiben(gut, text) {
  zeilen.push(`<span class="${gut ? "gut" : "schlecht"}">${gut ? "✔" : "✘"} ${text}</span>`);
  document.getElementById("ergebnis").innerHTML = zeilen.join("\n");
}
async function sha(text) {
  const h = await crypto.subtle.digest("SHA-256", KODIERER.encode(text));
  return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
(async () => {
  schreiben(window.isSecureContext, `isSecureContext = ${window.isSecureContext}, crypto.subtle = ${tresorMoeglich()}`);
  if (!tresorMoeglich()) return;
  try {
    const kopf = kopfLesen(JSON.parse(DATEIEN["planung.json"]));
    schreiben(kopf.kennung === VEKTOREN.kennung, `Kopf gelesen: Kennung ${kopf.kennung}, Wicklungen ${kopf.wicklungen.map((w) => w.art).join(", ")}`);
    const t0 = performance.now();
    const roh = await datenschluesselMitPassphrase(kopf, VEKTOREN.passphrase);
    const ms = Math.round(performance.now() - t0);
    schreiben(true, `Passphrase-Wicklung offen — PBKDF2 mit ${VEKTOREN.runden} Runden: ${ms} ms`);
    const tresor = await tresorAnlegen(roh, kopf);
    const klar = await behaelterOeffnen(kopf, tresor);
    const digest = await sha(klar);
    schreiben(digest === VEKTOREN.klartextSHA256, `Nutzlast entsiegelt: SHA-256 ${digest.slice(0, 16)}… (${klar.length} Zeichen) — erwartet ${VEKTOREN.klartextSHA256.slice(0, 16)}…`);
    // NFC: zerlegte Umlaute
    const zerlegt = VEKTOREN.passphrase.normalize("NFD");
    const roh2 = await datenschluesselMitPassphrase(kopf, zerlegt);
    schreiben(roh2.length === 32, "Dieselbe Passphrase in zerlegter Form (NFD) öffnet ebenfalls");
    try {
      await datenschluesselMitPassphrase(kopf, VEKTOREN.passphrase + "x");
      schreiben(false, "Falsche Passphrase hat geöffnet — das darf nicht sein");
    } catch (f) {
      schreiben(/passt nicht/.test(f.message), `Falsche Passphrase: „${f.message}“`);
    }
    const exportKopf = kopfLesen(JSON.parse(DATEIEN["export.json"]));
    const roh3 = await datenschluesselMitWiederherstellung(exportKopf, VEKTOREN.wiederherstellung.toLowerCase().replace(/-/g, " ").replace(/O/gi, "0"));
    const t3 = await tresorAnlegen(roh3, exportKopf);
    schreiben((await sha(await behaelterOeffnen(exportKopf, t3))) === VEKTOREN.klartextSHA256, "Wiederherstellungsschlüssel (klein, ohne Striche, 0 statt O) öffnet den Export");
    const statusKopf = kopfLesen(JSON.parse(DATEIEN["status.json"]));
    const statusKlar = await behaelterOeffnen(statusKopf, tresor);
    schreiben(JSON.parse(statusKlar).typ === "unterrichtsplanung-status", "Statusbehälter der App entsiegelt: " + statusKlar.slice(0, 60));
    const eigener = await behaelterVersiegeln(JSON.stringify({ typ: "unterrichtsplanung-status", version: 1, gespeichert: new Date().toISOString(), planungstitel: "Prüfvektor", eintraege: { "e-1": { erledigt: true, kommentar: "aus dem Browser — mit ä und ß", geaendert: new Date().toISOString() } } }), "status", tresor);
    document.getElementById("status").value = eigener;
    const eigenerKopf = kopfLesen(JSON.parse(eigener));
    const wieder = await behaelterOeffnen(eigenerKopf, tresor);
    schreiben(/aus dem Browser/.test(wieder) && eigener.startsWith('{"typ":"unterrichtsplanung-tresor"'), `Eigener Status versiegelt und wieder geöffnet (${eigener.length} Zeichen, Wicklungen ${eigenerKopf.wicklungen.map((w) => w.art).join(", ")})`);
    schreiben(true, "FERTIG");
  } catch (f) {
    schreiben(false, "Abbruch: " + (f && f.message ? f.message : f));
  }
})();
</script></body></html>
'''


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--erzeugen", metavar="ORDNER")
    p.add_argument("--oeffnen", metavar="DATEI")
    p.add_argument("--passphrase")
    p.add_argument("--wiederherstellung")
    p.add_argument("--klartext", metavar="DATEI", help="bei --oeffnen: den Klartext dorthin schreiben")
    p.add_argument("--kopf", metavar="DATEI")
    p.add_argument("--probe", metavar="ORDNER")
    a = p.parse_args()
    if a.erzeugen:
        return erzeugen(Path(a.erzeugen))
    if a.oeffnen:
        if a.passphrase is None and a.wiederherstellung is None:
            raise SystemExit("--oeffnen braucht --passphrase oder --wiederherstellung")
        return oeffnen(Path(a.oeffnen), a.passphrase, a.wiederherstellung,
                       Path(a.klartext) if a.klartext else None)
    if a.kopf:
        return kopf_pruefen(Path(a.kopf))
    if a.probe:
        return probe_bauen(Path(a.probe))
    p.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
