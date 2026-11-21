# Entwurf: Kontinente, Kontinentalkarten, Regionen (21. 11. 2026)

Arbeitsgrundlage für den Auftrag „eigene Kontinente anlegen, auf dem Globus platzieren,
detaillierbare Kontinentalkarten gestalten; danach Regionen“. Bestehendes Weltmodell:
`docs/PLAN.md` (Erzeugung + Strichliste in Kontinentmetern, Ausschnitte als Fenster).

## 1 Datenmodell

- **Welt** = Planet + Liste von Kontinenten. Jeder Kontinent hat eine **feste ID** (Text).
  Befehle verweisen auf die **ID, nicht den Listenplatz**, damit Rückgängig nach Anlegen/Löschen
  anderer Kontinente stimmt.
- **Kontinent** = ID, Name (vom Spielleiter, sonst leer), Lage (Breite, Länge, Ausrichtung),
  Größe (Seitenlänge des Kontinentfensters in km), **Grundform** (`"generated"`: Fleck aus
  Ausgangswert · `"drawn"`: leer, nur gezeichnete Formen), Ausgangswert, Klima-Anpassung,
  Strichliste (Operationen in Kontinentmetern), gemerkte Regionen.
- **Operationen** (Strichliste, in Reihenfolge angewendet, jede mit eigenem Ausgangswert):
  - Pinsel: `land_add`, `land_remove`, `raise`, `lower`, `smooth`, `flatten` (Ebene auf Zielhöhe),
    `forest_add`, `forest_remove`, `water` (wie bisher, Zielhöhe unter Meer).
  - Form: `shape_add` / `shape_remove` – geschlossener Linienzug (frei gezeichnet), gefüllt,
    weicher Rand, Küste per `roughness` mit festem Ausgangswert natürlich ausgefranst.
  - Erzeugung (örtlich, wiederholbar): `gen_mountains` (Gebirgszug entlang Strich, Kammrauschen
    mit eigenem Ausgangswert), `gen_hills`, `gen_forest` (natürliche Waldflecken in der Fläche),
    `gen_islands` (Inselgruppe im Pinselbereich).
  - Gewässer: `river` (Linienzug mit gespeichertem Höhenprofil, Breite, Tiefe; Profil beim
    Anlegen monoton fallend gemacht) · `lake` (Fläche mit gespeichertem Wasserspiegel).
  - `protect` – geschützter Bereich: Erzeugung (neue Variante der Grundform, Erzeugungs-
    Operationen) wirkt dort nicht; der Bereich behält die Grundform des Ausgangswerts, der beim
    Schützen galt. Handarbeit wirkt weiterhin.
- **Befehle**: `add_stroke`, `set`, `resize`, `add_continent`, `remove_continent` (mit vollständiger
  Kopie für Rückgängig), `replace_stroke` (z. B. „neu würfeln“: anderer Ausgangswert).

## 2 Auswertung

- `TerrainWindow` bekommt zusätzlich **Wasserspiegel** je Punkt (für Flüsse/Seen; sonst leer)
  und **Schutzanteil**.
- Gebirge/Hügel/Wald-Erzeugung als Ebenen-Beitrag (wie Striche), mit Schutzmaske multipliziert.
- Fluss: Bett entlang des Linienzugs auf Profilhöhe minus Tiefe abgesenkt (weicher Rand);
  Wasserspiegel = Profilhöhe. Grob (Kontinent) bleibt die Linie mindestens eine Rasterzelle breit
  sichtbar (vereinfachte Darstellung).
- See: Fläche auf Spiegel minus Tiefe abgesenkt, Wasserspiegel gesetzt.

## 3 Darstellung

- **Globus**: alle Kontinente gleichzeitig (Texturfeld, bis 8 Kontinente), gewählter Kontinent
  mit Messingrand; Klick wählt, Ziehen auf dem gewählten Kontinent verschiebt ihn, Ziehen daneben
  dreht den Globus; Regler für Größe/Breite/Länge/Ausrichtung; „Öffnen“ und Doppelklick öffnen.
- **Kontinentkarte**: Schummerung (Hangschatten), Höhenstufenfarben, Schnee, Wald als
  Kronendach, Flüsse und Seen als Wasser, Küstensaum; Auflösung 385 statt 257.
- **Feine Ausschnitte**: Zielstil (Fototexturen, klares Wasser, Bäume, Gras, Felsen); Gras in
  Ringen um die Kamera statt im ganzen Ausschnitt; mehr Baumarten (Nadelbäume), Farb- und
  Größenstreuung; Ufersaum (Kies/Sand/Fels, Schaum, Schilf).
- **Inland-Wasser**: eigenes Netz, auf Wasserspiegel gehoben, außerhalb verworfen.

## 4 Bedienung

- Werkzeugleiste mit Gruppen: Navigieren · Form (zeichnen, abtragen) · Gelände (Erhöhen,
  Senken, Glätten, Ebene, Gebirge) · Wasser (Fluss, See, Küste) · Bewuchs (Wald, Wald entfernen,
  Wald erzeugen) · Schützen. Aktives Werkzeug hervorgehoben + Name in der Statuszeile.
- Pinselvorschau: Kreis mit Größe in m/km, Formwerkzeug zeigt Linienzug live.
- Kontextfeld: nur Größe/Stärke und je Werkzeug höchstens eine weitere Einstellung.
- Orientierung: Pfad (Welt / Kontinent X / Region …), Übersichtskarte unten rechts mit
  Fensterrahmen, Zurück-Schaltflächen.

## 5 Regionen

- Hineinzoomen am Anschlag oder „Ausschnitt wählen“ (Rechteck aufziehen) öffnet einen feineren
  Ausschnitt an genauer Lage/Größe. Beim Verschieben über den Rand wird der Ausschnitt mitgeführt
  (neu ausgewertet) – Nachbarbereiche sind dieselbe Funktion, daher nahtlos.
- Detailarbeit = Operationen in Kontinentmetern; grob vereinfacht/markiert; bleibt gespeichert.

## 6 Abnahme

Neue Testwelt: Kontinent zeichnen → auf Globus setzen → Landschaft bearbeiten (Gebirge, Fluss,
See, Wald, Schutz) → speichern → neu starten → weiterarbeiten; Region öffnen, bearbeiten,
herauszoomen, wiederfinden. Zweiter Kontinent: anlegen, platzieren, löschen, Rückgängig.
