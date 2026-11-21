# Detailregionen: Vertiefen legt eine dauerhafte, verknüpfte Region an (21. 11. 2026)

Auftrag: Beim Vertiefen soll aus dem gewählten Ausschnitt eine höher aufgelöste, verknüpfte
Detailregion entstehen – vorhandene Geografie und Bearbeitungen übernommen, feinere Strukturen
ergänzt, dauerhaft gespeichert; übergeordnete Ansichten zeigen eine vereinfachte Zusammenfassung.
Dazu die Frage, ob der bisherige Stand schon zusätzliche geografische Daten erzeugt oder vor allem
die Kamera vergrößert und Darstellungsmuster wechselt.

## 1 Antwort: Was tat „Vertiefen“ bisher?

**Es entstanden schon echte zusätzliche Geländedaten – aber nur gerechnet, nie gespeichert, und
die gröberen Ansichten fassten sie nicht zusammen.**

- Jeder Ausschnitt wurde vollständig neu ausgewertet (`TerrainSampler.window`): Grundform,
  Erosionsrelief und alle Bearbeitungen in der Auflösung des Ausschnitts (257 × 257 Punkte,
  Kontinent 513 × 513). 25 km haben ein 98-m-Raster, der Kontinent ein 3-km-Raster. Die
  Erosionskacheln werden je Raster so fein ausgewertet, wie es trägt – beim Vertiefen kommen also
  wirklich neue Grate, Rinnen und Seitentäler hinzu.
- Gemessen an einem Gipfel der Vergleichswelt brachte jede Stufe gegenüber dem (interpolierten)
  übergeordneten Bild neues Relief: 200-km-Region (781-m-Raster) im Mittel 133 m (höchstens
  766 m), 25 km 66 m (331 m), 3 km 11 m (62 m). Das ist Geografie, keine Textur.
- **Gespeichert wurde davon nichts.** In der Weltdatei standen nur Rahmen `{cx, cy, size}`. Alles
  entstand bei jedem Besuch neu aus Ausgangswert und Strichliste – gleich, solange sich die
  Erzeugung nicht änderte; nach einer neuen Variante oder Programmfassung sah jede vertiefte
  Landschaft anders aus.
- **Die gröberen Ansichten waren keine Zusammenfassung**, sondern dieselbe Erzeugung gröber
  gerechnet. Am Rasterpunkt wichen sie vom Mittel des feinen Geländes über ihre Zelle um bis zu
  250–470 m (Kontinent) bzw. 76–130 m (200 km) ab.
- Zusätzlich wechselt die **Darstellung** je Maßstab: Karte mit Luftbild-Texturen und Kleinrelief
  unter der Rasterweite (`landscape.gdshader`), ab 4,2 km Zielstil-Boden, ab 1,7 km Bäume, Gras,
  Felsen als Modelle. Das ist Material und Beiwerk, keine Geografie.

## 2 Was jetzt geschieht

**Vertiefen legt eine Detailregion an** (`Editor.ensure_region`, `RegionStore`):

1. Der gewählte Ausschnitt (1/8 der Ansicht) wird in Regionsauflösung gerechnet (257 × 257) – mit
   allem, was der Kontinent dort hat (Grundform, Erosionsrelief, Schutz, Bearbeitungen), und den
   feineren Strukturen, die erst dieses Raster tragen kann.
2. **Gespeichert** werden die Grunddaten: Landanteil, grobes und feines Relief, Waldanlage (ohne
   Klima), Erosionsrelief (Massive, Seitentäler, Hügel) – `<welt>_regionen/<id>.region`,
   komprimiert, ≈ 1,5 MB. Die Weltdatei vermerkt Kennung, Lage, Größe, Stufe, übergeordnete Größe,
   Anlagezeit, **Prüfsumme** und den **Stand der Erzeugung** beim Anlegen. Eine beschädigte oder
   fehlende Datei wird erkannt (Meldung; dort gilt wieder die Erzeugung).
3. **Verknüpft bleiben die Bearbeitungen:** Die Strichliste ist die eine Quelle. Ein im Kontinent
   gezogenes Gebirge erscheint in der Region, in der Region Gemaltes erscheint oben. Rückgängig und
   Wiederholen wirken auf allen Stufen gleich.
4. **Gleiches Raster** (die Region selbst, ein verschobener Ausschnitt gleicher Größe): gespeicherte
   Grunddaten statt Erzeugung, am Rand weich übergehend. Ist die Ansicht genau die Region, wird
   nichts mehr erzeugt.
5. **Feinere Ausschnitte in einer Region** folgen ihr: Erzeugung im eigenen Raster plus (gespeicherte
   Regionsdaten − Erzeugung im Regionsraster). Solange sich die Erzeugung nicht geändert hat, ist
   dieser Unterschied null und kostet nichts; nach einer neuen Variante, einer Skalierung oder einer
   neuen Programmfassung behält die Region ihre Geografie, und feinere Stufen ergänzen nur das
   Kleinere.
6. **Gröbere Ansichten fassen zusammen:** Höhe und Wald jeder groben Zelle sind das **Mittel des
   fertigen Regionsgeländes** (Grunddaten + Bearbeitungen) über die Zellfläche. Je Stichprobe gilt
   die feinste Region, die sie bedeckt (Kontinent ← 200 km ← 25 km ← 3 km); wo keine Region liegt,
   bleibt die eigene Rechnung.
7. **Klima bleibt lebendig:** Gespeichert ist die Waldanlage ohne Klima; die jetzige Trockenheit
   wirkt beim Zusammensetzen. Verschiebt man den Kontinent in eine andere Breite, folgt der Wald.
8. Eine erneut vertiefte Stelle nutzt die vorhandene Region; beim Skalieren des Kontinents wächst
   sie mit („Alles wächst mit“). Rückgängig einer Größenänderung oder des Anlegens eines Kontinents
   verliert seither angelegte Regionen nicht.

**Zwischenstände** (`<id>.ergebnis`, ≈ 0,25 MB, mit Prüfwert über Stand und Inhalt): Das fertige
Regionsgelände (Höhe, Wald) wird nach seinem Stand gemerkt – Grundform, Klima, Regionen im Gebiet
(feinere mit ihrem ganzen Stand) und alle Bearbeitungen, die die Region berühren. Eine Bearbeitung
rechnet nur die berührten Regionen neu; nach dem Öffnen wird der gespeicherte Zwischenstand
genutzt, wenn er passt. Beim Speichern der Welt wird er auf den aktuellen Stand gebracht.

## 3 Geprüft

- **91 Tests** der Fachlogik bestanden; neu in `tests/test_regions.gd`: Datei hin und zurück
  bitgleich, beschädigte Datei abgewiesen; Region zeigt genau das übernommene Gelände und behält es
  nach neuer Variante; grobe Ansicht = Zellmittel des Regionsgeländes (≤ 0,5 m); Bearbeitung ändert
  nur den Stand der berührten Region und erscheint in der Übersicht; Übersicht aus gespeicherten
  Zwischenständen bitgleich zur Neuberechnung; Stand nach Speichern und Laden gleich; Zwischenstand
  folgt Rückgängig/Wiederholen; Live-Malen verändert kein gemerktes Ergebnis; Rückgängig der
  Größenänderung und des Anlegens behält Regionen; feinerer Ausschnitt folgt der Region nach neuer
  Variante; Wald der Region folgt dem Klima; beschädigter Zwischenstand abgewiesen.
- **Ortsprüfung** (`--orte`): Jedes Vertiefen legt jetzt eine Region an; gemessen wird der Stand nach
  dem Hinabsteigen (so, wie die Stufen beim Herauszoomen erscheinen). Die Gegenrechnung nutzt
  eigene, leere Zwischenspeicher und rechnet jede Region neu. Letzter Lauf: Schritt 1 81 Prüfungen, 7 fehlgeschlagen; Schritt 2 (Neustart) 22/22.
  Neu: **Rasterpunkte = Zellmittel des feinen Geländes** an allen drei Stellen auf Kontinent, 200 km
  und 25 km bestanden (größte Abweichung 0,1–2,3 m; vor den Regionen bis 470 m). Fehlgeschlagen
  sind nur die Vergleiche *zwischen* den Rasterpunkten (siehe Grenzen) und einmal „Glätten
  −13 % statt −15 %“ (schon vorher grenzwertig). Vergleichsablauf 24/24 (unter Parallellast einmal
  ein Mausklick-Zeitfehler, ohne Last 4/4), Abnahme 20/20 und 11/11.
- **Eigenständige Prüfung** (drei Prüfer, jeder Befund von einem Gegenprüfer nachgerechnet): 7
  bestätigte Fehler, alle behoben (gemeinsame Felder von Zwischenspeicher und Anzeige; Regionen
  gingen bei Rückgängig einer Größenänderung verloren; feinere Ausschnitte folgten der Region nach
  neuer Variante nicht; Wald eingefroren; Stand nicht transitiv; Live-Malen-Reichweite;
  beschädigte Zwischenstände unerkannt); 3 Befunde widerlegt.
- **Rechenzeiten** (RTX-Rechner, Probewelt mit 8 Regionen):

  | Vorgang (Echtzeitlauf, Rechenpause) | vorher | jetzt |
  | --- | --- | --- |
  | Vertiefen 200 km / 25 km / 3 km | 0,6 / 0,6 / 0,6 s | 2,2 / 1,5 / 1,6 s |
  | Rückgängig / Wiederholen (3 km) | 0,8 s | 1,0 s |
  | Herauszoomen auf 200 km | 1,1 s | 1,6 s |
  | Kontinent öffnen nach Neustart | ≈ 1,4 s | ≈ 2,8 s (Zwischenstände von der Platte) |
  | Region anlegen und speichern | – | 0,4–1,3 s (darin enthalten) |
  | Speicher je Region | – | ≈ 1,5 MB Daten + 0,25 MB Zwischenstand |

## 4 Grenzen (ehrlich)

- **Zwischen den Rasterpunkten** bleibt die grobe Stufe an scharfen Gipfeln und Tälern glatter als das
  Zellmittel um genau diese Stelle (Kontinent im Mittel 80–160 m, 200 km einzelne Punkte bis ≈ 100 m).
  Ursache: Das Raster hält Zellmittel an seinen Punkten, dazwischen wird interpoliert; ein Gipfel
  kleiner als eine Zelle (3 km) wird dadurch doppelt geglättet. Die Ortsprüfung meldet das weiter
  als Fehlschlag. Die Darstellung ergänzt den Anteil feiner als das Raster (Kleinrelief).
- **Rechenzeit bei Bearbeitungen über Regionen:** Jede berührte Region und jede übergeordnete Ansicht
  wird neu gerechnet. Live-Malen über einer feineren Region zeigt das zusammengefasste Ergebnis erst
  nach dem Loslassen. *Nächster Schritt:* Regionsergebnisse im Hintergrund rechnen und die
  Zusammenfassung einblenden, sobald sie fertig ist.
- **Anlegen ist kein Rückgängig-Schritt** (eine Region ändert das Bild nicht). Löschen von Regionen
  gibt es noch nicht.
- Regionsdaten liegen neben der Weltdatei und sind wie Spielstände nicht im Repository
  (`*_regionen/`). Wer eine Welt sichert oder weitergibt, muss den Ordner mitnehmen.
- Die Region speichert ihre Waldanlage ohne Klima; eine Klimaänderung wirkt also auf den Wald der
  Region, nicht aber auf ihr Relief – das ist gewollt (Geografie bleibt, abgeleitetes Klima folgt).
