/* =========================================================
   SYNTHETISCHE VORLAGE für den Leser der Materialliste
   (Pruefungen/MaterialkatalogPruefungen.swift, katalog_pruefen.py)
   ---------------------------------------------------------
   Enthält alles, was die Literal-Teilmenge kennt und die
   Live-Datei heute nicht braucht: Zeilenkommentare, einfache
   Anführungszeichen, Escapes, Nachkommas, Zahlen, true/false/
   null, Schlüssel in Anführungszeichen, unbekannte Felder,
   fehlende Felder, eine Adresse, die keine ist.
   ========================================================= */
// Ein Zeilenkommentar vor der Zuweisung.
const   KATEGORIEN=[
  {
    titel: "Kategorie A", // Kommentar am Zeilenende
    beschreibung: 'Einfache Anführungszeichen — mit „Gänsefüßchen“ und \'Apostroph\'',
    kacheln: [
      {
        "titel": "Kachel A1 (relativ)",
        beschreibung: "Zeile 1\nZeile 2 mit Tab\tund Backslash \\ und \"Zitat\" und äöü",
        meta: "Fach · 1. Lernjahr",
        schlagworte: ["a", 'b', "c",],
        lizenz: "CC BY-SA 4.0",
        link: "ordner/unterordner/datei.html",
        download: "",
        qr: "ordner/datei.png",
        qrMin: "ordner/datei_64px.png",
        zusatz: { zahl: 42, bruch: -1.5, wahr: true, falsch: false, nichts: null, leer: [], leer2: {} },
      },
      {
        titel: "Kachel A2 (absolut, http)",
        beschreibung: "",
        meta: "",
        schlagworte: [],
        lizenz: "",
        link: "http://example.org/material?x=1&y=2#abschnitt",
        download: "x.zip",
        qr: "x.png",
        qrMin: "x_64px.png"
      },
      {
        titel: "Kachel A3 (ohne Adresse — wird übergangen)",
        beschreibung: "kein link-Feld",
        meta: "Fach · 2. Lernjahr",
        schlagworte: ["ohne"],
        lizenz: "CC0"
      },
      {
        titel: "Kachel A4 (javascript: — wird übergangen)",
        beschreibung: "keine http/https-Adresse",
        link: "javascript:alert(1)",
        schlagworte: []
      },
      {
        beschreibung: "Kachel ohne Titel — wird übergangen",
        link: "ohne-titel.html"
      }
    ]
  },
  {
    titel: 'Kategorie B (leer)',
    beschreibung: "",
    kacheln: []
  },
  {
    titel: "Kategorie C",
    beschreibung: "Einträge in anderer Reihenfolge",
    kacheln: [
      { link: "https://3ducation.org/c/1.html", titel: "Kachel C1 (Adresse zuerst)", lizenz: "MIT", schlagworte: ["Digitale Welt", "1./2. Lernjahr"], meta: "DW · 1./2. Lernjahr", beschreibung: "Absolut auf der eigenen Website" },
    ],
  },
]
;
