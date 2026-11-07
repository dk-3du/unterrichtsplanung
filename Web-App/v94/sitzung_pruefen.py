#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Dominik Kluge
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Sitzungswechsel im echten Browser: Haken und Kommentar bleiben bei der Planung, zu der das Blatt gehört (R93-01).

`leser_pruefen.py` läuft in `jsc` mit nachgebautem DOM — Blätter, Fokus und Zeitgeber über einen Wechsel der Planung
hinweg sieht es nicht. Genau dort lag R93-01: Ein Kommentar, im Blatt einer Planung getippt, landete nach dem Ablegen
einer anderen Datei in deren Status und Gerätespeicher; in seiner eigenen Planung kam er nie an. Hier läuft je Fall eine
Testkopie der Web App in Headless-Chrome, mit frischem Profil und mit der CSP der ausgelieferten Seite (`script-src`
mit den Hashes der drei Skripte der Testkopie, `connect-src 'self'` für das Protokoll, alles andere wie ausgeliefert):

* vor dem Skript der Web App ein **Taktgeber**: `setTimeout` und `setInterval` der Seite feuern nur, wenn der Treiber
  den Takt vorschiebt — keine Wanduhr, keine Frist als Prüfbedingung (E1093). Die virtuelle Zeit von Chrome taugt dafür
  nicht: Sie läuft weiter, während WebCrypto rechnet. Grenze: Auch Zeitgeber mit 0 ms warten auf den Takt; wartet die
  Web App beim Öffnen auf einen Zeitgeber, hängt der Fall bis zum Wächter — die Zwischenstände nennen dann den letzten
  Schritt;
* hinter dem Skript der **Treiber**: Er legt Dateien ab wie die Hand (`drop` auf das offene Blatt), tippt, setzt Haken,
  hält Asynchrones an **Schranken** fest (um `planungPruefen`, `statusAusSpeicher`, `behaelterVersiegeln`) und schickt
  Zwischenstände und Protokoll an den Server dieses Skripts (127.0.0.1, freier Port);
* die Prüfplanungen aus der Saat von `tresor_pruefen.py --erzeugen`: `klartext.json` und derselbe Inhalt als Behälter
  `export.json` mit der Probe-Passphrase (E1094). B ist A mit anderem Titel, anderem `erstellt` und eigenen Kennungen.

Die Testkopie verlässt sich auf Namen der Web App — wer einen davon ändert, sieht es hier als Fehler im Protokoll
(W2-06):
* globale Funktionen `dateiLesen`, `planungPruefen`, `statusAusSpeicher`, `behaelterVersiegeln`, `melden`,
  `istBehaelter`, `kopfLesen`, `behaelterOeffnen`, `statusMerken` (S10) und die Konstanten `STATUS_SCHLUESSEL`,
  `STATUS_TYP`, `STATUS_VERSION` (S7, S10);
* in `zustand`: `planung`, `kacheln` (je `vorhaben` und `element`), `status`, `tresor` — und `themaVonHand`, das als
  einziges still wirkungslos bliebe (nur das Farbthema, ohne Einfluss auf die Messung);
* im Dokument die Kennungen `blatt-vorhaben`, `blatt-passphrase`, `passphrase-feld`, `passphrase-formular` und die
  Klassen `blatt` (an `dialog`), `kommentarfeld`, `statusschalter`.
Jeder Fall prüft auch seinen Aufbau (Fokus, blur, Schranke, Saat); ein Fall, dessen Aufbau nicht stand, ist rot mit
„Aufbau: …“, nie grün.

Fälle (S1–S6 gegen 2.7.0 rot, E1092; S7 siehe dort; S8 gegen v94 vor dem Nachfassen rot, W1-01; S9 gegen den Stand
mit Runden ohne einen Abschluss je Blatt — dort hing die Seite, R-BF5-01; S10 gegen den Stand ohne Schranke
„Wiederaufnahme liest“, E1100):
  S1  Kommentar im Blatt von A, Fokus im Feld; B auf das offene Blatt abgelegt (blur kommt nach dem Wechsel).
  S2  wie S1, ohne Fokus — nur der Entpreller (500 ms) trägt den Kommentar.
  S3  Kommentar im Blatt von A; A noch einmal abgelegt (dieselben Kennungen, neue Objekte).
  S4  A verschlüsselt, Kommentar getippt; B (Klartext) abgelegt — der Kommentar steht nirgends im Klartext.
  S5  Haken im alten Raster, während die Wiederaufnahme von B angehalten ist.
  S6  Haken in A (verschlüsselt), sofort B abgelegt, während das Versiegeln angehalten ist.
  S7  Ein Stand von B liegt schon im Gerätespeicher; B wird abgelegt, seine Wiederaufnahme angehalten, dann C abgelegt —
      der Stand von B bleibt (R-BF2-01). S7 hält eine Regel fest, die erst das Abschließen vor dem Wechsel gefährdet;
      gegen 2.7.0 ist es grün.
  S8  A verschlüsselt, Kommentar getippt, B abgelegt; während das Versiegeln aus dem Abschließen angehalten ist, kommt
      weiterer Text ins noch offene Blatt — auch er gehört zu A, verschlüsselt, ohne Meldung.
  S9  Das offene Blatt baut sich neu auf (derselbe Weg wie ein Tipp in der Tagesliste über dem Blatt), getippt wird ins
      neue Feld, dann B abgelegt — das Abschließen endet, der Kommentar gehört zu A.
  S10 Ein Stand von B liegt schon im Gerätespeicher; B wird abgelegt, seine Wiederaufnahme angehalten, und währenddessen
      wird gemerkt wie mit ⌘S oder der Diskette — der Stand von B bleibt und wird wieder aufgenommen (R-BF5-08, E1100).
In jedem Fall: Kennungen aus A stehen nur unter dem Schlüssel von A, es gibt keinen dritten Schlüssel, und am Ende ist
kein Blatt mehr offen. Die Meldung „… gehört zur vorher geöffneten Planung“ steht nur in S5 — sonst hat das Abschließen
alles übernommen, und ein spätes blur bleibt still.

Aufruf:
  python3 sitzung_pruefen.py --tresor ORDNER                 die Fälle in Headless-Chrome
  python3 sitzung_pruefen.py --tresor ORDNER --dienen ZIEL [--port N] [--frist S] [--stand STAND]
        nur den Server mit den Testkopien (für die Messung in WebKit, iOS-Simulator); die Seiten nacheinander öffnen,
        nie zwei zugleich (sie teilen den Gerätespeicher); jede Testkopie wird nur einmal ausgeliefert, ein erneutes
        Laden bekommt eine Seite ohne Skript, mit `--stand` ebenso jeder Abruf ohne `?stand=STAND` (ein Tab, den
        Safari aus einem früheren Lauf wiederherstellt). Jedes Protokoll als ZIEL/<Fall>.json; Ende, wenn alle zehn
        da sind oder nach S Sekunden (Vorgabe 900). Wo der Browser kein `DragEvent` mit Datei bauen lässt, ruft der
        Treiber den Leser selbst; das zählt hier, und die Ausgabe nennt den Weg.
ORDNER ist der Ausgabeordner von `tresor_pruefen.py --erzeugen`. Braucht Google Chrome (`CHROME` setzt einen anderen
Pfad); fehlt es, ist das rot — nie übersprungen. Die Schlusszeile nennt die Fassung von Chrome. Ergebnis: Exit 0/1 (auch
mit `--dienen`: 1, sobald ein Fall rot ist oder fehlt); ein Abbruch vor dem ersten Fall — Saat, Aufbau der Web App,
Server — beginnt mit „sitzung_pruefen.py:“.
"""

import argparse
import base64
import hashlib
import http.server
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HIER = Path(__file__).resolve().parent
HTML = HIER / "unterrichtsplanung-ansicht.html"
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
PASSPHRASE = "Ein Satz, den man behält — mit ä und ß"  # die Probe-Passphrase aus tresor_pruefen.py
FAELLE = ("S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10")
MIT_FOKUS = ("S1", "S3", "S4")
KOMMENTAR = "Kommentar aus A — Sitzungsprobe"
KOMMENTAR_WEITER = KOMMENTAR + ", weitergetippt"  # S8: beginnt mit KOMMENTAR, damit die Klartextprüfung ihn findet
KENNUNG = "e-1"
B_TITEL = "Sitzungsprobe B"
B_ERSTELLT = "2026-11-01T08:00:00.000Z"
C_TITEL = "Sitzungsprobe C"
C_ERSTELLT = "2026-11-02T08:00:00.000Z"
SCHLUESSEL = "unterrichtsplanung.status:"
FRIST = 120  # Wächter je Fall: bricht nur einen hängenden Lauf ab — immer rot, nie eine Prüfbedingung (B15)

# Vor dem Skript der Web App: Zeitgeber der Seite laufen am Takt des Treibers (E1093).
TAKTGEBER = r"""
(() => {
  const schlange = [];
  let jetzt = 0;
  let naechste = 1;
  const planen = (rueckruf, ms, args, wiederholt) => {
    const id = naechste;
    naechste += 1;
    const abstand = Math.max(0, Number(ms) || 0);
    schlange.push({ id, faellig: jetzt + abstand, rueckruf, args, wiederholt: wiederholt ? Math.max(1, abstand) : 0 });
    return id;
  };
  const weg = (id) => {
    const i = schlange.findIndex((e) => e.id === id);
    if (i >= 0) schlange.splice(i, 1);
  };
  window.setTimeout = (rueckruf, ms, ...args) => planen(rueckruf, ms, args, false);
  window.setInterval = (rueckruf, ms, ...args) => planen(rueckruf, ms, args, true);
  window.clearTimeout = weg;
  window.clearInterval = weg;
  window.__takt = {
    vor(ms) {
      const ziel = jetzt + ms;
      for (;;) {
        schlange.sort((a, b) => a.faellig - b.faellig || a.id - b.id);
        const e = schlange[0];
        if (!e || e.faellig > ziel) break;
        jetzt = e.faellig;
        if (e.wiederholt) e.faellig += e.wiederholt; else schlange.shift();
        try {
          if (typeof e.rueckruf === "function") e.rueckruf(...e.args);
        } catch (fehler) {
          window.__taktFehler = String(fehler && fehler.stack || fehler);
        }
      }
      jetzt = ziel;
    },
  };
})();
"""

# Hinter dem Skript der Web App: der Treiber eines Falls.
TREIBER = r"""
(async () => {
  const FALL = __FALL__;
  const A_TEXT = __A_TEXT__;
  const A_GEHEIM = __A_GEHEIM__;
  const B_TEXT = __B_TEXT__;
  const B_TITEL = __B_TITEL__;
  const B_ERSTELLT = __B_ERSTELLT__;
  const C_TEXT = __C_TEXT__;
  const KOMMENTAR = __KOMMENTAR__;
  const KOMMENTAR_WEITER = __KOMMENTAR_WEITER__;
  const KENNUNG = __KENNUNG__;
  const prot = { fall: FALL, schritte: [], meldungen: [], weg: "" };
  const titel = () => (zustand.planung ? zustand.planung.titel : "keine");
  // Je Schritt ein Zwischenstand an den Server: Hängt ein Fall, nennt der Wächter den letzten Schritt.
  const schritt = (text) => {
    prot.schritte.push(text + " — " + titel());
    fetch("/zwischen/" + FALL, { method: "POST", body: JSON.stringify(prot) }).catch(() => {});
  };
  const bilder = (n) => new Promise((fertig) => {
    const eins = () => { if (n <= 0) fertig(); else { n -= 1; window.requestAnimationFrame(eins); } };
    eins();
  });
  let tresorA = null;
  try {
    window.localStorage.clear();
    zustand.themaVonHand = true;

    // Mitschnitt: Meldungen, Öffnungen, Versiegelungen.
    const meldenVorher = melden;
    melden = (text, warnend) => { prot.meldungen.push(String(text)); return meldenVorher(text, warnend); };
    let letzteOeffnung = null;
    const lesenVorher = dateiLesen;
    dateiLesen = (datei) => { letzteOeffnung = lesenVorher(datei); return letzteOeffnung; };
    const versiegelungen = new Set();
    let versiegelnSchranke = null;
    let beimAnhalten = null;  // S8: einmal gerufen, sobald ein Versiegeln an der Schranke wartet
    const versiegelnVorher = behaelterVersiegeln;
    behaelterVersiegeln = (...args) => {
      const schranke = versiegelnSchranke;
      if (schranke && beimAnhalten) {
        const angekommen = beimAnhalten;
        beimAnhalten = null;
        angekommen();
      }
      const lauf = (async () => {
        if (schranke) await schranke;
        return versiegelnVorher(...args);
      })();
      versiegelungen.add(lauf);
      lauf.finally(() => versiegelungen.delete(lauf)).catch(() => {});
      return lauf;
    };
    // Bis kein Versiegeln mehr läuft und seine Rückrufe durch sind.
    const ruhe = async () => {
      while (versiegelungen.size) await Promise.allSettled([...versiegelungen]);
      await Promise.resolve();
      await Promise.resolve();
    };

    // Ablegen wie die Hand: `drop` auf das offene Blatt (oder die Seite); nur wo der Browser kein `DragEvent` mit Datei
    // bauen lässt, ruft der Treiber den Leser selbst — das Protokoll sagt, welcher Weg lief.
    const ablegen = (text, name) => {
      const datei = new File([text], name, { type: "application/json" });
      letzteOeffnung = null;
      let ereignis = null;
      try {
        const uebergabe = new DataTransfer();
        uebergabe.items.add(datei);
        ereignis = new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: uebergabe });
      } catch { ereignis = null; }
      if (ereignis && ereignis.dataTransfer && ereignis.dataTransfer.files.length === 1) {
        (document.querySelector("dialog.blatt[open]") || document.body).dispatchEvent(ereignis);
        if (!prot.weg) prot.weg = "drop";
      }
      if (!letzteOeffnung) {
        prot.weg = "dateiLesen (kein drop mit Datei in diesem Browser)";
        dateiLesen(datei);
      }
      return letzteOeffnung;
    };
    const passphraseEingeben = () => new Promise((fertig) => {
      const blatt = document.getElementById("blatt-passphrase");
      const ausfuellen = () => {
        document.getElementById("passphrase-feld").value = __PASSPHRASE__;
        document.getElementById("passphrase-formular").requestSubmit();
        fertig();
      };
      if (blatt.open) { ausfuellen(); return; }
      const beobachter = new MutationObserver(() => {
        if (blatt.open) { beobachter.disconnect(); ausfuellen(); }
      });
      beobachter.observe(blatt, { attributes: true, attributeFilter: ["open"] });
    });
    // A öffnen und den Aufbau festhalten: `erstellt` und der Anfangsstand von e-1 (die Saat).
    const oeffnenA = async (text, name, verschluesselt) => {
      const offen = ablegen(text, name);
      if (verschluesselt) await Promise.race([passphraseEingeben(), offen]);
      await offen;
      const e = zustand.planung ? zustand.planung.eintraege.find((x) => x.id === KENNUNG) : null;
      prot.aErstellt = zustand.planung ? zustand.planung.erstellt : null;
      prot.aAnfang = e ? { erledigt: Boolean(e.erledigt), kommentar: e.kommentar || "" } : null;
      schritt("geöffnet: " + name);
    };
    const postenVon = (id) => zustand.kacheln.find((k) => k.vorhaben.id === id);
    const blattVon = (id) => {
      const posten = postenVon(id);
      if (!posten) throw new Error("keine Kachel für " + id);
      posten.element.click();
      const blatt = document.getElementById("blatt-vorhaben");
      if (!blatt.open) throw new Error("das Vorhaben-Blatt ist nicht offen");
      return blatt;
    };
    // Kommentar tippen, dann eine Datei ablegen; danach auf das blur des Feldes warten, das der Browser nach dem
    // Schließen des Blattes meldet — ein Ereignis, keine Frist (höchstens 30 Bilder; ob der Fall dann noch gilt,
    // entscheidet die Bewertung am Aufbau).
    const tippenUndAblegen = async (fokus, text, name) => {
      const blatt = blattVon(KENNUNG);
      const feld = blatt.querySelector(".kommentarfeld");
      const planungBeimTippen = zustand.planung;
      let blurWann = "";
      const blurDa = new Promise((fertig) => feld.addEventListener("blur", () => {
        blurWann = zustand.planung === planungBeimTippen ? "vor dem Wechsel" : "nach dem Wechsel";
        fertig();
      }, { once: true }));
      if (fokus) feld.focus();
      prot.fokusImFeld = document.activeElement === feld;
      feld.value = KOMMENTAR;
      feld.dispatchEvent(new Event("input"));
      schritt("getippt");
      await ablegen(text, name);
      schritt("übernommen");
      if (prot.fokusImFeld) await Promise.race([blurDa, bilder(30)]);
      prot.blurGesehen = Boolean(blurWann);
      prot.fokusNachher = document.activeElement === feld;
      prot.feldVerbunden = feld.isConnected;
      prot.blur = blurWann ? "blur " + blurWann : "kein blur";
      window.__takt.vor(600);
      schritt("Takt +600 ms (Entpreller)");
    };

    if (FALL === "S1" || FALL === "S2") {
      await oeffnenA(A_TEXT, "A.json", false);
      await tippenUndAblegen(FALL === "S1", B_TEXT, "B.json");
    } else if (FALL === "S3") {
      await oeffnenA(A_TEXT, "A.json", false);
      await tippenUndAblegen(true, A_TEXT, "A.json");
    } else if (FALL === "S4") {
      await oeffnenA(A_GEHEIM, "A-verschluesselt.json", true);
      tresorA = zustand.tresor;
      prot.aVerschluesselt = Boolean(tresorA);
      await tippenUndAblegen(true, B_TEXT, "B.json");
    } else if (FALL === "S5") {
      await oeffnenA(A_TEXT, "A.json", false);
      let auf = null;
      let angehalten = null;
      const angehaltenDa = new Promise((fertig) => { angehalten = fertig; });
      const ausVorher = statusAusSpeicher;
      statusAusSpeicher = async (planung) => {
        if (planung && planung.titel === B_TITEL && !auf) {
          await new Promise((fertig) => { auf = fertig; angehalten(); });
        }
        return ausVorher(planung);
      };
      const offenB = ablegen(B_TEXT, "B.json");
      await Promise.race([angehaltenDa, offenB]);
      prot.angehalten = Boolean(auf);
      schritt("Wiederaufnahme angehalten");
      const altePosten = postenVon(KENNUNG);
      prot.altesRaster = Boolean(altePosten && zustand.planung && !zustand.planung.eintraege.includes(altePosten.vorhaben));
      if (altePosten) {
        altePosten.element.click();
        const schalter = document.querySelector("#blatt-vorhaben[open] .statusschalter");
        prot.hakenGesetzt = Boolean(schalter);
        if (schalter) schalter.click();
        schritt("Haken am alten Raster");
      }
      if (auf) auf();
      await offenB;
      schritt("übernommen");
      window.__takt.vor(600);
    } else if (FALL === "S6") {
      await oeffnenA(A_GEHEIM, "A-verschluesselt.json", true);
      tresorA = zustand.tresor;
      prot.aVerschluesselt = Boolean(tresorA);
      const blatt = blattVon(KENNUNG);
      let auf = null;
      versiegelnSchranke = new Promise((fertig) => { auf = fertig; });
      // Erst wenn B als Planung bestanden hat, geht die Schranke auf — als Mikrotask, also nach allem, was das Öffnen
      // danach ohne Warten tut.
      const pruefenVorher = planungPruefen;
      planungPruefen = (roh) => {
        const planung = pruefenVorher(roh);
        if (planung.titel === B_TITEL && auf) {
          const oeffnen = auf;
          auf = null;
          queueMicrotask(() => { versiegelnSchranke = null; oeffnen(); });
        }
        return planung;
      };
      blatt.querySelector(".statusschalter").click();
      // Der Beleg des Aufbaus: Der Haken hat ein Versiegeln angestoßen, und es wartet an der Schranke.
      prot.versiegelnAngehalten = versiegelungen.size > 0 && versiegelnSchranke !== null;
      schritt("Haken gesetzt, Versiegeln angehalten");
      await ablegen(B_TEXT, "B.json");
      schritt("übernommen");
      if (auf) { versiegelnSchranke = null; auf(); prot.schrankeNieGeoeffnet = true; }
    } else if (FALL === "S7") {
      await oeffnenA(A_TEXT, "A.json", false);
      // Ein Stand von B auf diesem Gerät, noch nicht abgelegt.
      window.localStorage.setItem(STATUS_SCHLUESSEL + ":" + B_ERSTELLT, JSON.stringify({
        typ: STATUS_TYP, version: STATUS_VERSION,
        eintraege: { "B-e-1": { erledigt: true, kommentar: "", geaendert: new Date(Date.now() - 60000).toISOString() } },
      }));
      let auf = null;
      let angehalten = null;
      const angehaltenDa = new Promise((fertig) => { angehalten = fertig; });
      const ausVorher = statusAusSpeicher;
      statusAusSpeicher = async (planung) => {
        if (planung && planung.titel === B_TITEL && !auf) {
          await new Promise((fertig) => { auf = fertig; angehalten(); });
        }
        return ausVorher(planung);
      };
      const offenB = ablegen(B_TEXT, "B.json");
      await Promise.race([angehaltenDa, offenB]);
      prot.angehalten = Boolean(auf);
      schritt("Wiederaufnahme von B angehalten");
      await ablegen(C_TEXT, "C.json");
      schritt("C übernommen");
      if (auf) auf();
      await offenB;
      schritt("B zu Ende (überholt)");
    } else if (FALL === "S8") {
      await oeffnenA(A_GEHEIM, "A-verschluesselt.json", true);
      tresorA = zustand.tresor;
      prot.aVerschluesselt = Boolean(tresorA);
      const blatt = blattVon(KENNUNG);
      const feld = blatt.querySelector(".kommentarfeld");
      const planungBeimTippen = zustand.planung;
      let blurWann = "";
      const blurDa = new Promise((fertig) => feld.addEventListener("blur", () => {
        blurWann = zustand.planung === planungBeimTippen ? "vor dem Wechsel" : "nach dem Wechsel";
        fertig();
      }, { once: true }));
      feld.focus();
      prot.fokusImFeld = document.activeElement === feld;
      feld.value = KOMMENTAR;
      feld.dispatchEvent(new Event("input"));
      schritt("getippt");
      // Das Versiegeln, das der Abschluss beim Ablegen von B anstößt, hält an der Schranke — und derweil kommt weiterer
      // Text ins noch offene Blatt (W1-01). Der Entpreller dieser Eingabe feuert erst am Takt, nach dem Wechsel.
      let auf = null;
      versiegelnSchranke = new Promise((fertig) => { auf = fertig; });
      const angekommen = new Promise((fertig) => { beimAnhalten = () => fertig(true); });
      const offenB = ablegen(B_TEXT, "B.json");
      prot.versiegelnAngehalten = await Promise.race([angekommen, offenB.then(() => false)]);
      feld.value = KOMMENTAR_WEITER;
      feld.dispatchEvent(new Event("input"));
      prot.weitergetippt = blatt.open && feld.isConnected && zustand.planung === planungBeimTippen;
      schritt("weitergetippt, Versiegeln angehalten");
      versiegelnSchranke = null;
      auf();
      await offenB;
      schritt("übernommen");
      await Promise.race([blurDa, bilder(30)]);
      prot.blur = blurWann ? "blur " + blurWann : "kein blur";
      window.__takt.vor(600);
      schritt("Takt +600 ms (Entpreller)");
    } else if (FALL === "S9") {
      await oeffnenA(A_TEXT, "A.json", false);
      const blatt = blattVon(KENNUNG);
      const feldAlt = blatt.querySelector(".kommentarfeld");
      // Das offene Blatt baut sich neu auf — derselbe Weg wie ein Tipp auf dieses Vorhaben in der Tagesliste, die ⌘D
      // über das Blatt legt: `vorhabenZeigen` bei offenem Blatt (R-BF5-01). Hier über den Klick der Kachel.
      postenVon(KENNUNG).element.click();
      const feld = blatt.querySelector(".kommentarfeld");
      prot.neuAufgebaut = blatt.open && feld !== feldAlt && !feldAlt.isConnected;
      const planungBeimTippen = zustand.planung;
      let blurWann = "";
      const blurDa = new Promise((fertig) => feld.addEventListener("blur", () => {
        blurWann = zustand.planung === planungBeimTippen ? "vor dem Wechsel" : "nach dem Wechsel";
        fertig();
      }, { once: true }));
      feld.focus();
      feld.value = KOMMENTAR;
      feld.dispatchEvent(new Event("input"));
      schritt("Blatt neu aufgebaut, getippt");
      await ablegen(B_TEXT, "B.json");
      schritt("übernommen");
      // Auf das späte blur warten wie in S1/S8 — sonst käme eine Meldung erst nach dem Protokoll (Gegenprobe G413).
      await Promise.race([blurDa, bilder(30)]);
      prot.blur = blurWann ? "blur " + blurWann : "kein blur";
      window.__takt.vor(600);
      schritt("Takt +600 ms (Entpreller)");
    } else if (FALL === "S10") {
      await oeffnenA(A_TEXT, "A.json", false);
      // Ein Stand von B auf diesem Gerät, noch nicht abgelegt (wie S7).
      window.localStorage.setItem(STATUS_SCHLUESSEL + ":" + B_ERSTELLT, JSON.stringify({
        typ: STATUS_TYP, version: STATUS_VERSION,
        eintraege: { "B-e-1": { erledigt: true, kommentar: "",
                                geaendert: new Date(Date.now() - 60000).toISOString() } },
      }));
      let auf = null;
      let angehalten = null;
      const angehaltenDa = new Promise((fertig) => { angehalten = fertig; });
      const ausVorher = statusAusSpeicher;
      statusAusSpeicher = async (planung) => {
        if (planung && planung.titel === B_TITEL && !auf) {
          await new Promise((fertig) => { auf = fertig; angehalten(); });
        }
        return ausVorher(planung);
      };
      const offenB = ablegen(B_TEXT, "B.json");
      await Promise.race([angehaltenDa, offenB]);
      prot.angehalten = Boolean(auf) && Boolean(zustand.planung) && zustand.planung.titel === B_TITEL;
      // ⌘S und die Diskette rufen als Erstes `statusMerken` (R-BF5-08, E1100) — das Weitere (Zieldatei, Teilen-Blatt)
      // braucht eine echte Geste und bleibt hier außen vor.
      statusMerken();
      schritt("Wiederaufnahme von B angehalten, gemerkt wie mit ⌘S");
      if (auf) auf();
      await offenB;
      schritt("B übernommen");
    }

    await ruhe();
    window.__takt.vor(5000);
    schritt("Takt +5 s (Statusuhr)");
    await ruhe();

    const aktuelle = new Set(zustand.planung ? zustand.planung.eintraege : []);
    const kennungen = new Set([...aktuelle].map((e) => e.id));
    prot.planungJetzt = titel();
    prot.statusJetzt = Object.fromEntries(Object.entries(zustand.status)
      .map(([k, v]) => [k, { erledigt: Boolean(v.erledigt), kommentar: v.kommentar || "" }]));
    prot.fremdImStatus = Object.keys(zustand.status).filter((k) => !kennungen.has(k));
    prot.kachelnFremd = zustand.kacheln.filter((k) => !aktuelle.has(k.vorhaben)).map((k) => k.vorhaben.id);
    prot.blaetterOffen = [...document.querySelectorAll("dialog.blatt[open]")].map((b) => b.id);
    prot.vorhabenJetzt = {};
    for (const e of aktuelle) prot.vorhabenJetzt[e.id] = { erledigt: Boolean(e.erledigt), kommentar: e.kommentar || "" };
    prot.speicher = {};
    for (let i = 0; i < window.localStorage.length; i += 1) {
      const schluessel = window.localStorage.key(i);
      const text = window.localStorage.getItem(schluessel) || "";
      const eintrag = { klartextTraegtKommentar: text.includes(KOMMENTAR), art: "klartext", eintraege: null };
      try {
        let stand = JSON.parse(text);
        if (istBehaelter(stand)) {
          const kopf = kopfLesen(stand);
          eintrag.art = tresorA && tresorA.kennung === kopf.kennung ? "behälter" : "behälter ohne Schlüssel";
          stand = eintrag.art === "behälter" ? JSON.parse(await behaelterOeffnen(kopf, tresorA)) : null;
        }
        if (stand && stand.eintraege) {
          eintrag.eintraege = Object.fromEntries(Object.entries(stand.eintraege)
            .map(([k, v]) => [k, { erledigt: Boolean(v.erledigt), kommentar: v.kommentar || "" }]));
        }
      } catch (fehler) {
        eintrag.art = "unlesbar: " + fehler;
      }
      prot.speicher[schluessel] = eintrag;
    }
    if (window.__taktFehler) prot.fehler = "Zeitgeber der Seite warf: " + window.__taktFehler;
  } catch (fehler) {
    prot.fehler = String(fehler && fehler.stack || fehler);
  }
  prot.fertig = true;
  document.title = "fertig " + FALL;
  try {
    await fetch("/ergebnis/" + FALL, { method: "POST", body: JSON.stringify(prot) });
  } catch (fehler) {
    document.title = "Protokoll nicht gesendet: " + fehler;
  }
})();
"""


def js(wert) -> str:
    """Ein Wert als JavaScript-Literal, sicher innerhalb von <script>: jedes `<` als Escape."""
    return json.dumps(wert, ensure_ascii=False).replace("<", "\\u003c")


def hashwert(inhalt: str) -> str:
    return "'sha256-" + base64.b64encode(hashlib.sha256(inhalt.encode("utf-8")).digest()).decode("ascii") + "'"


def abbrechen(grund: str):
    """Rot vor dem ersten Fall — mit dem Präfix, an dem `pruefen.sh` die Befundzeile erkennt (W2-05)."""
    raise SystemExit("sitzung_pruefen.py: " + grund)


def planungen(tresor: Path) -> tuple[str, str, str, str, str]:
    """A im Klartext, A als Behälter (dieselbe Planung), B, C — und das `erstellt` von A."""
    try:
        a_text = (tresor / "klartext.json").read_text(encoding="utf-8")
        a_geheim = (tresor / "export.json").read_text(encoding="utf-8")
        a = json.loads(a_text)
        geheim = json.loads(a_geheim)
    except (OSError, ValueError) as fehler:
        abbrechen(f"Saat in {tresor} nicht lesbar: {fehler}")
    if not isinstance(a, dict) or not any(isinstance(e, dict) and e.get("id") == KENNUNG
                                          for e in a.get("eintraege", [])):
        abbrechen(f"klartext.json trägt kein Vorhaben „{KENNUNG}“ — die Saat passt nicht zu dieser Prüfung")
    if not isinstance(geheim, dict) or geheim.get("inhalt") != "planung":
        abbrechen("export.json ist kein Behälter mit Inhalt „planung“")
    b = json.loads(a_text)
    b["titel"] = B_TITEL
    b["erstellt"] = B_ERSTELLT
    for e in b["eintraege"]:
        e["id"] = "B-" + e["id"]
    c = json.loads(a_text)
    c["titel"] = C_TITEL
    c["erstellt"] = C_ERSTELLT
    for e in c["eintraege"]:
        e["id"] = "C-" + e["id"]
    return a_text, a_geheim, json.dumps(b, ensure_ascii=False), json.dumps(c, ensure_ascii=False), a["erstellt"]


def testkopie(fall: str, a_text: str, a_geheim: str, b_text: str, c_text: str) -> str:
    zeilen = HTML.read_text(encoding="utf-8").split("\n")
    csp = [i for i, z in enumerate(zeilen) if 'http-equiv="Content-Security-Policy"' in z]
    skript = [i for i, z in enumerate(zeilen) if z.strip() == "<script>"]
    if len(csp) != 1 or len(skript) != 1:
        abbrechen(f"Aufbau der Web App unerwartet: {len(csp)} CSP-Zeilen, {len(skript)} Skriptanfänge")
    treiber = TREIBER
    for marke, wert in (("__FALL__", fall), ("__A_TEXT__", a_text), ("__A_GEHEIM__", a_geheim),
                        ("__B_TEXT__", b_text), ("__B_TITEL__", B_TITEL), ("__B_ERSTELLT__", B_ERSTELLT),
                        ("__C_TEXT__", c_text), ("__KOMMENTAR_WEITER__", KOMMENTAR_WEITER),
                        ("__KOMMENTAR__", KOMMENTAR),
                        ("__KENNUNG__", KENNUNG), ("__PASSPHRASE__", PASSPHRASE)):
        treiber = treiber.replace(marke, js(wert))
    # Die CSP der ausgelieferten Seite bleibt: `script-src` lässt genau die drei Skripte der Testkopie zu — Taktgeber,
    # Web App und Treiber, je mit dem Hash ihres Inhalts —, `connect-src` nur das Protokoll an den eigenen Server; sonst
    # gilt jede Regel wie ausgeliefert (R-BF1-08). Der Hash der Web App wird hier berechnet, nicht aus der Datei
    # übernommen: Eine Gegenprobe ändert das Skript, und die Seite liefe sonst gar nicht. Ob der Hash in der Datei
    # stimmt, prüft `csp_hashes.py`.
    anfang = skript[0] + 1
    ende_app = next((i for i in range(anfang, len(zeilen)) if zeilen[i].strip() == "</script>"), None)
    if ende_app is None:
        abbrechen("Aufbau der Web App unerwartet: kein </script> nach dem Skriptanfang")
    app = "\n" + "\n".join(zeilen[anfang:ende_app]) + "\n"
    policy = zeilen[csp[0]]
    alt_script = re.findall(r"script-src 'sha256-[^']+'", policy)
    if len(alt_script) != 1 or policy.count("connect-src 'none'") != 1:
        abbrechen("Aufbau der CSP unerwartet: script-src mit einem Hash und connect-src 'none' erwartet")
    policy = policy.replace(alt_script[0], f"script-src {hashwert(TAKTGEBER)} {hashwert(app)} {hashwert(treiber)}")
    policy = policy.replace("connect-src 'none'", "connect-src 'self'")
    zeilen[csp[0]] = policy
    zeilen[skript[0]] = "<script>" + TAKTGEBER + "</script>\n" + zeilen[skript[0]]
    seite = "\n".join(zeilen)
    ende = seite.rfind("</body>")
    if ende < 0:
        abbrechen("Aufbau der Web App unerwartet: kein </body>")
    return seite[:ende] + "<script>" + treiber + "</script>\n" + seite[ende:]


# Was ein zweiter Abruf derselben Testkopie bekommt: eine Seite ohne Skript. Safari im iOS-Simulator lud eine schon
# gemessene Seite neu, während der nächste Fall lief — die Wiederholung leerte den gemeinsamen Gerätespeicher und
# schrieb hinein (v94 BF5, gemessen: S2 und S3 je zweimal). Je Fall läuft deshalb genau ein Treiber.
SCHON_GELIEFERT = ("<!doctype html><meta charset=\"utf-8\"><title>schon geliefert</title>"
                   "<p>Diese Testkopie wurde schon einmal ausgeliefert und läuft nicht noch einmal.</p>")


class Dienst:
    """Liefert die Testkopien aus — jede genau einmal — und nimmt Zwischenstände und Protokolle an, nur auf
    127.0.0.1. `abrufe` zählt je Seite, wie oft sie verlangt wurde."""

    def __init__(self, seiten: dict, port: int = 0, ziel: Path | None = None, stand: str | None = None):
        self.seiten = seiten
        self.abrufe = {}
        self.protokolle = {}
        self.zwischen = {}
        self.eingang = threading.Condition()
        self.ziel = ziel
        self.stand = stand
        dienst = self

        class Bearbeiter(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                name, _, anfrage = self.path.partition("?")
                name = name.lstrip("/")
                seite = dienst.seiten.get(name)
                if seite is None:
                    self.send_error(404)
                    return
                # Mit `--stand` nur Abrufe dieses Messlaufs: Safari stellt beim Start den zuletzt offenen Tab eines
                # früheren Laufs wieder her und lädt ihn neu — der bekommt die Seite ohne Skript.
                fremd = dienst.stand is not None and f"stand={dienst.stand}" not in anfrage.split("&")
                with dienst.eingang:
                    if not fremd:
                        dienst.abrufe[name] = dienst.abrufe.get(name, 0) + 1
                    if fremd or dienst.abrufe[name] > 1:
                        seite = SCHON_GELIEFERT
                daten = seite.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(daten)))
                self.end_headers()
                self.wfile.write(daten)

            def do_POST(self):
                teile = self.path.split("?", 1)[0].strip("/").split("/")
                laenge = int(self.headers.get("Content-Length") or 0)
                roh = self.rfile.read(laenge).decode("utf-8", "replace")
                self.send_response(204)
                self.end_headers()
                if len(teile) != 2 or teile[0] not in ("ergebnis", "zwischen") or teile[1] not in FAELLE:
                    return
                art, fall = teile
                try:
                    protokoll = json.loads(roh)
                except ValueError:
                    protokoll = {"fehler": "Protokoll ist kein JSON: " + roh[:200]}
                with dienst.eingang:
                    if art == "zwischen":
                        dienst.zwischen[fall] = protokoll
                        return
                    dienst.protokolle[fall] = protokoll
                    dienst.eingang.notify_all()
                if dienst.ziel:
                    (dienst.ziel / f"{fall}.json").write_text(json.dumps(protokoll, ensure_ascii=False, indent=1),
                                                             encoding="utf-8")

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Bearbeiter)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def warten(self, faelle, frist: float) -> bool:
        with self.eingang:
            return self.eingang.wait_for(lambda: all(f in self.protokolle for f in faelle), timeout=frist)

    def letzter_schritt(self, fall: str) -> str:
        with self.eingang:
            schritte = (self.zwischen.get(fall) or {}).get("schritte") or []
        return schritte[-1] if schritte else "keiner"

    def schliessen(self):
        self.server.shutdown()
        self.server.server_close()


def chrome_lauf(dienst: Dienst, fall: str, profile: Path) -> dict:
    # Ohne Schlüsselbund, ohne Media Router (mDNS im lokalen Netz), ohne Namensauflösung außer 127.0.0.1 (R-BF1-07).
    befehl = [CHROME, "--headless=new", f"--user-data-dir={profile / fall}", "--no-first-run",
              "--no-default-browser-check", "--disable-gpu", "--disable-extensions", "--disable-sync",
              "--disable-background-networking", "--disable-component-update", "--disable-default-apps",
              "--no-pings", "--use-mock-keychain", "--disable-features=MediaRouter,OptimizationHints,Translate",
              "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1",
              f"http://127.0.0.1:{dienst.port}/{fall}.html"]
    fehlerausgabe = profile / f"{fall}-stderr.txt"
    with open(fehlerausgabe, "w", encoding="utf-8") as stderr:
        prozess = subprocess.Popen(befehl, stdout=subprocess.DEVNULL, stderr=stderr)
    beginn = time.monotonic()
    try:
        # In Scheiben: Endet Chrome vorzeitig, ist das sofort rot, nicht erst am Wächter.
        while not dienst.warten([fall], 1):
            if prozess.poll() is not None:
                rest = fehlerausgabe.read_text(encoding="utf-8", errors="replace")[-400:]
                return {"fehler": f"Chrome endete vorzeitig (Rückgabe {prozess.returncode}), letzter Schritt "
                                  f"„{dienst.letzter_schritt(fall)}“: {rest}"}
            if time.monotonic() - beginn > FRIST:
                return {"fehler": f"Chrome lieferte binnen {FRIST} s kein Protokoll — Prüfung abgebrochen; letzter "
                                  f"Schritt „{dienst.letzter_schritt(fall)}“"}
        return dienst.protokolle[fall]
    finally:
        prozess.terminate()
        try:
            prozess.wait(timeout=20)
        except subprocess.TimeoutExpired:
            prozess.kill()
            prozess.wait()


def chrome_fassung() -> str:
    """Die Fassung des Browsers für die Schlusszeile: Chrome aktualisiert sich selbst, und das Ergebnis hängt an seinem
    Verhalten (Fokus beim Schließen eines Blattes, `DragEvent` mit Datei) — der Vermerk nennt den Stand (W2-04)."""
    try:
        aus = subprocess.run([CHROME, "--version"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return "Chrome-Fassung unbekannt"
    zeilen = aus.stdout.strip().splitlines()
    return zeilen[0].strip() if aus.returncode == 0 and zeilen else "Chrome-Fassung unbekannt"


def bewerten(fall: str, p: dict, a_erstellt: str, drop_pflicht: bool = True) -> list[str]:
    """Die Gründe, aus denen ein Fall rot ist — leer heißt bestanden. „Aufbau: …“ heißt: Der Fall hat nicht gemessen,
    was er messen soll."""
    if p.get("fehler"):
        return ["Fehler: " + str(p["fehler"])[:600]]
    if not p.get("fertig"):
        return ["Protokoll unvollständig"]
    gruende = []

    def soll(bedingung: bool, grund: str):
        if not bedingung:
            gruende.append(grund)

    # Der Aufbau: Weg, Saat, Fokus und blur, Schranken.
    if drop_pflicht:
        soll(p.get("weg") == "drop", f"Aufbau: Weg „{p.get('weg')}“ statt drop")
    soll(p.get("aErstellt") == a_erstellt, f"Aufbau: A trägt erstellt {p.get('aErstellt')!r} statt {a_erstellt!r}")
    soll(p.get("aAnfang") == {"erledigt": False, "kommentar": ""},
         f"Aufbau: {KENNUNG} beginnt mit {p.get('aAnfang')!r} statt ohne Haken und Kommentar")
    if fall in MIT_FOKUS:
        soll(p.get("fokusImFeld") is True, "Aufbau: Fokus kam nicht ins Feld")
        # Gemessen wird das blur, das erst nach dem Wechsel ankommt (R93-01) — kam es vorher oder gar nicht, misst der
        # Fall nur noch, was S2 misst (W2-01).
        soll(p.get("blur") == "blur nach dem Wechsel", f"Aufbau: {p.get('blur') or 'kein blur'} statt nach dem Wechsel")
    if fall == "S2":
        soll(p.get("fokusImFeld") is False, "Aufbau: Fokus im Feld, der Fall misst dann nicht den Entpreller allein")
    if fall in ("S4", "S6", "S8"):
        soll(p.get("aVerschluesselt") is True, "Aufbau: A ließ sich nicht verschlüsselt öffnen")
    if fall == "S9":
        soll(p.get("neuAufgebaut") is True, "Aufbau: das offene Blatt baute sich nicht neu auf")
    if fall == "S8":
        soll(p.get("fokusImFeld") is True, "Aufbau: Fokus kam nicht ins Feld")
        soll(p.get("versiegelnAngehalten") is True, "Aufbau: das Abschließen stieß kein Versiegeln an der Schranke an")
        soll(p.get("weitergetippt") is True, "Aufbau: weitergetippt erst, als das Blatt zu oder B schon offen war")
    if fall == "S5":
        soll(p.get("angehalten") is True and p.get("altesRaster") is True and p.get("hakenGesetzt") is True,
             "Aufbau: Wiederaufnahme nicht angehalten oder kein Haken am alten Raster")
    if fall in ("S7", "S10"):
        soll(p.get("angehalten") is True, "Aufbau: Wiederaufnahme von B nicht angehalten")
    if fall == "S6":
        soll(p.get("versiegelnAngehalten") is True, "Aufbau: kein Versiegeln an der Schranke")
        soll(not p.get("schrankeNieGeoeffnet"), "Aufbau: B bestand nie als Planung")

    # Der Speicher: nur die Schlüssel von A und B; Kennungen aus A nur unter A, aus B nur unter B; alles lesbar.
    speicher = p.get("speicher") or {}
    a_schluessel, b_schluessel = SCHLUESSEL + a_erstellt, SCHLUESSEL + B_ERSTELLT
    erlaubt = {a_schluessel: "", b_schluessel: "B-"}
    if fall == "S7":
        erlaubt[SCHLUESSEL + C_ERSTELLT] = "C-"
    dritte = sorted(set(speicher) - set(erlaubt))
    soll(not dritte, f"Speicher trägt weitere Schlüssel {dritte}")
    for schluessel, eintrag in speicher.items():
        soll(eintrag.get("art") in ("klartext", "behälter"), f"Speicher {schluessel}: {eintrag.get('art')!r}")
        praefix = erlaubt.get(schluessel)
        if praefix is None:
            continue
        kennungen = eintrag.get("eintraege") or {}
        falsch = sorted(k for k in kennungen
                        if (not k.startswith(praefix) if praefix else k.startswith(("B-", "C-"))))
        soll(not falsch, f"Speicher {schluessel} trägt fremde Kennungen {falsch}")
    a_speicher = speicher.get(a_schluessel) or {}
    b_speicher = speicher.get(b_schluessel) or {}
    a_eintrag = (a_speicher.get("eintraege") or {}).get(KENNUNG) or {}

    # Die Sitzung am Ende: keine fremden Kennungen, keine alten Objekte, kein offenes Blatt.
    soll(not p.get("fremdImStatus"), f"Status der offenen Planung trägt fremde Kennungen {p.get('fremdImStatus')}")
    soll(not p.get("kachelnFremd"), f"Kacheln halten Vorhaben einer früheren Planung {p.get('kachelnFremd')}")
    soll(not p.get("blaetterOffen"), f"am Ende noch offen: {p.get('blaetterOffen')}")
    # Die Meldung „gehört zur vorher geöffneten Planung“ steht nur, wo ein Rückruf wirklich etwas abwies (S5); sonst
    # hat das Abschließen alles übernommen, und ein spätes blur bleibt still (W2-03).
    if fall != "S5":
        spaet = [m for m in p.get("meldungen") or [] if "vorher geöffneten Planung" in m]
        soll(not spaet, "nach dem Wechsel abgewiesen (das Abschließen hat nicht alles übernommen): "
             + " | ".join(spaet))

    if fall == "S3":
        soll(p.get("planungJetzt") != B_TITEL, "B statt A offen")
        soll(a_eintrag.get("kommentar") == KOMMENTAR, f"Speicher von A: Kommentar {a_eintrag.get('kommentar')!r}")
        jetzt = (p.get("vorhabenJetzt") or {}).get(KENNUNG) or {}
        soll(jetzt.get("kommentar") == KOMMENTAR, f"das offene Vorhaben trägt {jetzt.get('kommentar')!r}")
        return gruende
    if fall == "S7":
        soll(p.get("planungJetzt") == C_TITEL, f"offen ist „{p.get('planungJetzt')}“ statt C")
        b_eintrag = (b_speicher.get("eintraege") or {}).get("B-e-1") or {}
        soll(b_eintrag.get("erledigt") is True,
             f"der Stand von B im Gerätespeicher ist überschrieben (B-e-1: {b_eintrag or 'fehlt'})")
        return gruende
    soll(p.get("planungJetzt") == B_TITEL, f"offen ist „{p.get('planungJetzt')}“ statt B")
    if fall == "S10":
        b_eintrag = (b_speicher.get("eintraege") or {}).get("B-e-1") or {}
        soll(b_eintrag.get("erledigt") is True,
             f"der Stand von B im Gerätespeicher ist überschrieben (B-e-1: {b_eintrag or 'fehlt'})")
        jetzt = (p.get("vorhabenJetzt") or {}).get("B-e-1") or {}
        soll(jetzt.get("erledigt") is True, f"B-e-1 nicht wieder aufgenommen ({jetzt or 'fehlt'})")
    if fall in ("S1", "S2", "S4", "S9"):
        soll(a_eintrag.get("kommentar") == KOMMENTAR,
             f"Speicher von A: Kommentar {a_eintrag.get('kommentar')!r} statt des getippten")
    if fall == "S8":
        soll(a_eintrag.get("kommentar") == KOMMENTAR_WEITER,
             f"Speicher von A: Kommentar {a_eintrag.get('kommentar')!r} statt des weitergetippten")
    if fall in ("S4", "S6", "S8"):
        soll(a_speicher.get("art") == "behälter", f"Speicher von A: {a_speicher.get('art')!r} statt Behälter")
    if fall in ("S4", "S8"):
        klar = sorted(k for k, v in speicher.items() if v.get("klartextTraegtKommentar"))
        soll(not klar, f"der Kommentar aus A steht im Klartext unter {klar}")
    if fall == "S5":
        soll(any("vorher geöffneten Planung" in m for m in p.get("meldungen") or []),
             "keine Meldung, dass der Haken zur vorher geöffneten Planung gehörte")
    if fall == "S6":
        soll(a_eintrag.get("erledigt") is True, f"Speicher von A: Haken {a_eintrag.get('erledigt')!r} statt gesetzt")
    return gruende


def ausgeben(fall: str, protokoll: dict, gruende: list[str], mit_weg: bool = False, abrufe: int = 1) -> None:
    zusatz = []
    if protokoll.get("blur"):
        zusatz.append(protokoll["blur"])
    if mit_weg and protokoll.get("weg"):
        zusatz.append("Weg: " + protokoll["weg"])
    if abrufe > 1:
        zusatz.append(f"{abrufe} Abrufe, gelaufen nur der erste")
    klammer = f" ({'; '.join(zusatz)})" if zusatz else ""
    if gruende:
        print(f"✗ {fall}{klammer}: " + "; ".join(gruende))
        for s in protokoll.get("schritte", []):
            print(f"     {s}")
    else:
        print(f"✓ {fall}{klammer}")


def main() -> int:
    argumente = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    argumente.add_argument("--tresor", required=True, type=Path, help="Ausgabeordner von tresor_pruefen.py --erzeugen")
    argumente.add_argument("--dienen", type=Path, help="nur den Server starten; Protokolle nach ZIEL/<Fall>.json")
    argumente.add_argument("--port", type=int, default=0)
    argumente.add_argument("--frist", type=int, default=900)
    argumente.add_argument("--stand", help="mit --dienen: nur Abrufe mit ?stand=STAND bekommen die Testkopie")
    a = argumente.parse_args()

    # Der Aufbau vor dem ersten Fall: Was hier scheitert (Saat, Web App, Port), kommt mit Präfix in den Vermerk
    # (R-BF5-06).
    try:
        a_text, a_geheim, b_text, c_text, a_erstellt = planungen(a.tresor)
        seiten = {f"{f}.html": testkopie(f, a_text, a_geheim, b_text, c_text) for f in FAELLE}
    except (OSError, KeyError, TypeError, ValueError, AttributeError) as fehler:
        abbrechen(f"Aufbau gescheitert: {type(fehler).__name__}: {fehler}")

    if a.dienen:
        try:
            a.dienen.mkdir(parents=True, exist_ok=True)
            dienst = Dienst(seiten, a.port, a.dienen, a.stand)
        except OSError as fehler:
            abbrechen(f"Server nicht gestartet: {fehler}")
        print(f"Testkopien unter http://127.0.0.1:{dienst.port}/S1.html … {FAELLE[-1]}.html — Protokolle nach "
              f"{a.dienen}", flush=True)
        dienst.warten(FAELLE, a.frist)
        dienst.schliessen()
        rot = 0
        for fall in FAELLE:
            if fall not in dienst.protokolle:
                rot += 1
                print(f"✗ {fall}: kein Protokoll (letzter Schritt „{dienst.letzter_schritt(fall)}“)")
                continue
            gruende = bewerten(fall, dienst.protokolle[fall], a_erstellt, drop_pflicht=False)
            rot += bool(gruende)
            ausgeben(fall, dienst.protokolle[fall], gruende, mit_weg=True, abrufe=dienst.abrufe.get(f"{fall}.html", 1))
        print(f"\nSitzungsprüfung (Server): {rot} von {len(FAELLE)} Fällen rot." if rot
              else f"\nSitzungsprüfung (Server): alle {len(FAELLE)} Fälle bestanden.")
        return 1 if rot else 0

    if not Path(CHROME).is_file():
        print(f"✗ Google Chrome fehlt ({CHROME}) — die Sitzungsprüfung braucht einen echten Browser; "
              "CHROME setzt einen anderen Pfad.")
        return 1
    fassung = chrome_fassung()
    try:
        dienst = Dienst(seiten)
    except OSError as fehler:
        abbrechen(f"Server nicht gestartet: {fehler}")
    rot = 0
    try:
        with tempfile.TemporaryDirectory(prefix="sitzung-", dir=os.environ.get("TMPDIR")) as profile:
            for fall in FAELLE:
                protokoll = chrome_lauf(dienst, fall, Path(profile))
                gruende = bewerten(fall, protokoll, a_erstellt)
                rot += bool(gruende)
                ausgeben(fall, protokoll, gruende, abrufe=dienst.abrufe.get(f"{fall}.html", 1))
    finally:
        dienst.schliessen()
    if rot:
        print(f"\nSitzungsprüfung: {rot} von {len(FAELLE)} Fällen rot ({fassung}, headless).")
        return 1
    print(f"\nSitzungsprüfung: alle {len(FAELLE)} Fälle bestanden ({fassung}, headless, Taktgeber).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
