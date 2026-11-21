# Kartengrafik: Bestand für Fels, Boden, Wiese, Wald, Schnee und Küste (21. 11. 2026)

Auftrag: den grafischen Abstand zur Kontinentalreferenz (`docs/referenz/kontinent_konzept.webp`)
durch einen tatsächlich eingebauten Grafikbestand schließen. Zuerst ein Ausschnitt mit Gebirge,
Tal, Wald und Küste in zwei Varianten, dann die bessere auf die Kontinentansicht übertragen.

## 1 Was fehlte (Referenz gegen Editor, gleiche Bildstellen)

Bilder: `docs/kartengrafik/luecke_vorher_*.jpg` (links Referenz, rechts Editor vorher).

| Sichtbare Eigenschaft | Referenz | Editor vorher | Ursache |
| --- | --- | --- | --- |
| Gebirgslandschaft | breite Massive, Messerkämme und dunkle Rinnen alle 10–20 Bildpunkte | weiche Buckel, kein Kleinrelief | Raster 3 km: alles unter ≈ 6 km fehlt; Gebirgsstriche schmal |
| Felsflächen | hell grau-beige, Rinnenstreifen, Schutt, Klippen | eine Mischfarbe | keine Textur, nur Farbe nach Neigung |
| Wiesen und Böden | Mosaik aus Oliv, Gelbgrün, Dunkelgrün, Ocker, Gebüsch | große gleichförmige Flächen | nur Rauschfarben |
| Wald | Kronenkörnung mit Schatten, Wald in Tälern und an Unterhängen | ausgestanzte dunkle Flecken | Muster ohne Kronen, kein Bezug zum Relief |
| Küste | Steilküsten, Strände in Buchten, türkise Riffe, Petrolton | Sandsaum, Türkisband, marineblau | keine Küstenmaterialien |

## 2 Erstellter Bestand und Begründung

Alles in `assets/map/` (Einzelheiten, Herkunft, Lizenz, empfohlene Kachelgröße: `assets/map/README.md`).

| Bestand | Herkunft | schließt die Lücke |
| --- | --- | --- |
| `erosion_alpine_*` (Normale, Masken: Rinne, Grat, Steilheit, Höhe; 16-Bit-Höhe) | eigene Erzeugung, Blender + numpy, Erosionssimulation (Fließgewässer, Tropfen, Hangschutt), fester Ausgangswert, nahtlos – `tools/blender/make_erosion_tiles.py` | Kleinrelief der Massive: Grate, verästelte Täler unter der Rasterweite |
| `erosion_hills_*` | wie oben, weicher | Hügel- und Bergland zwischen den Massiven |
| `rock_massif`, `rock_massif_b` | Higgsfield (Luftbild aus ≈ 10 km), nahtlos gemacht | Felsstruktur mit Rinnen und Schutt |
| `alpine_snow` | Higgsfield | Schneefelder zwischen Felsgraten |
| `forest_mixed`, `forest_conifer` | Higgsfield (≈ 3 km), farblich an die vorhandenen Kronendach-Bilder angeglichen | Kronenkörnung, Nadelwald dunkler |
| `meadow_mosaic`, `scrub_heath`, `dry_ground` | Higgsfield | Wiesenmosaik, Gebüsch, trockene Böden |
| `coast_shallows` | Higgsfield | Meeresgrund im Flachwasser |
| `beach_rock` | Higgsfield – **nicht verwendet**: zeigt Kiesel aus Bodennähe, im Kartenmaßstab falsch | – |

Warum zwei Quellen: Das Relief muss nahtlos, wiederholbar und physikalisch stimmig sein
(Täler laufen zusammen) – das leistet eine eigene Simulation, ein KI-Bild nicht. Farbe und
Materialstruktur (Fels, Kronen, Wiese) liefert ein Luftbild glaubwürdiger als Regeln.
Geometrie/Modelle: Auf Kontinentebene trägt ein Bildpunkt 1–1,5 km; einzelne Modelle wären
unsichtbar. Die „Geometrie“ ist hier das Kleinrelief der Erosionskacheln (als Normale gezeichnet).

Werkzeuge: `tools/higgsfield_map_textures.py` (Erzeugung, Protokoll `assets/map/source/generated.json`),
`tools/make_seamless_textures.py` (Ausschnitt, Lichtausgleich, nahtlos, Höhenkarten aus Helligkeit).
Higgsfield: 13 Bilder, **26 Guthaben** (553,85 → 527,85; frei waren noch 392 von 400).

## 3 Einbau

`src/editor/landscape.gdshader` (grobe Ausschnitte, Kontinent bis 4,2 km):
- **Kleinrelief:** Erosionskachel in festen Metern, Kachelgröße folgt dem Zoom (Zweierschritte,
  überblendet), je Stufe gedreht und versetzt; gewichtet nach Gebirge (Höhe, Neigung) bzw.
  Hügelland. Wirkt auf Licht, Schummerung und Schatten.
- **Materialverteilung nach Relief:** Fels auf Graten und Steilflanken, Wald und Wiese in den
  Rinnen und an Unterhängen (unter der Baumgrenze), Schnee auf Kämmen über der Schneegrenze.
  Übergänge folgen der Kachelstruktur statt weicher Höhenlinien.
- **Texturen** (`tex_world`): je Zoomstufe zwei gedrehte Abtastungen, von großem Rauschen
  gemischt – gegen sichtbare Wiederholung.
- **Küste:** Steilküsten zeigen Fels, flache Küsten hellen Sand; Flachwasser über Meeresgrund-
  Textur; Meer im Petrolton der Referenz, Küstenschein breiter (`sea.gdshader`).
- Kamera: in Arbeitsentfernung bleibt der Blick steiler (erst ganz nah flacher).

## 4 Zwei Varianten unter gleichen Bedingungen

Gleiche Welt, gleiche Kamera, gleicher Ausschnitt (Gebirge, Tal, Wald, Küste im Nordwesten),
im laufenden Editor: `--vergleich=<Ordner>` erzeugt `ausschnitt_A_luftbild.jpg`,
`ausschnitt_B_gemalt.jpg`, `varianten.jpg` (Referenz | A | B) und je Variante den ganzen Kontinent.

- **A – Luftbild:** Fels, Schnee, Wald, Wiese, Boden aus den Higgsfield-Texturen, Kleinrelief aus
  den Erosionskacheln. → `docs/kartengrafik/ausschnitt_A_luftbild.jpg`
- **B – gemalt:** gleiche Erosionskacheln und Verteilung, Farben nach Regeln (keine Fototexturen).
  → `docs/kartengrafik/ausschnitt_B_gemalt.jpg`

| Kriterium | A Luftbild | B gemalt |
| --- | --- | --- |
| Nähe zur Referenz: Gebirge | Felsstruktur, Rinnen, Schutt – deutlich näher | Relief ja, Fels flächig |
| Wald | echte Kronenkörnung | Flecken mit Musterung |
| Wiese | Mosaik, aber allein zu ocker | grüner, aber gleichförmig |
| Bearbeitbarkeit | gleich: alles aus Höhe/Wald/Masken, Malen wirkt sofort | gleich |
| Wiederholung | gering (gedreht, zwei Stufen); Talformen bei genauem Hinsehen wiedererkennbar | gleich beim Relief |
| Leistung (Kontinent, 1440 × 900, RTX 2070 Super) | ≈ 78 Bilder/s | ≈ 100 Bilder/s |

**Entscheidung: A**, ergänzt um B's grüne Wiesentönung (Lichtgleichheit bewahrt) und dunklere
Waldmassen. Diese Lösung ist jetzt Standard (`LandscapeView.map_style = 1`) für Kontinent und Regionen.
Ergebnis: `docs/kartengrafik/kontinent_referenz_nachher.jpg`, `kontinent_A_B.jpg`,
`luecke_nachher_*.jpg`, Stufen 1.600 km bis 25 km: `stufen_nachher.jpg`.

## 5 Geprüft

- 68 Tests, Vergleichsablauf 24/24 Prüfungen (Formen bearbeiten, Rückgängig, Speichern unverändert).
- Bildraten: Kontinent 78–122, Regionen 200 km ≈ 86, 25 km ≈ 77, feine Stufen 136–250 (vorher
  Kontinent ≈ 200). Gemessen ohne Fremdlast.
- Unabhängige Prüfung der Bestände: Nahtlosigkeit, Normalenkonvention, Protokoll, Lizenzen in
  Ordnung; Befunde behoben (Strandtextur nicht verwendet, Normalenkarten als solche importiert,
  Masken verlustfrei, Quellordner von Godot ausgenommen, Laufprotokolle der Kacheln im Repository).

## 6 Was die Qualität noch begrenzt – Ursache und nachprüfbarer Lösungsversuch

1. **Kleinrelief ist Material, nicht Geografie.** Die Grate der Kachel liegen nicht dort, wo beim
   Vertiefen die gerechneten Grate liegen; beim Hineinzoomen wechselt das Muster.
   *Versuch:* die Erosionskachel als Höhenbeitrag im `TerrainSampler` (feste Weltlage, nur im
   Gebirge) einrechnen – dann zeigen alle Maßstäbe dieselben Grate. Prüfbar: gleicher Grat im
   1.600-km- und 200-km-Bild an derselben Stelle.
2. **Leistung** sank von ≈ 200 auf ≈ 80 Bilder/s (viele Texturzugriffe je Bildpunkt).
   *Versuch:* Materialmischung je Ausschnitt einmal in eine Farbtextur backen (nur bei Änderung
   neu) – Messung mit `--vergleich` (Bilder/s je Variante).
3. **Wald- und Wiesenverteilung im Tiefland** folgt noch dem groben Waldrauschen der Grundform
   (große Flecken) statt Feuchte und Relief. *Versuch:* Wald im Generator aus Tal-/Hanglage
   ableiten; prüfbar im Vergleichsbild (Tiefland).
4. **Küsten:** keine Strand-/Brandungstextur im richtigen Maßstab, Fjorde nur von Hand.
   *Versuch:* Strandmaterial neu erzeugen („aus 2 km Höhe, Sandbucht mit Brandungslinie“, ≈ 2–4
   Guthaben) und Brandungssaum im Meer-Shader aus der Küstennähe; prüfbar in `luecke_nachher_kueste_west.jpg`.
5. **Wiederholung:** Die Talschleifen der Erosionskachel sind bei genauem Hinsehen wiederzuerkennen.
   *Versuch:* zweite alpine Kachel mit anderem Ausgangswert und Mischung nach großem Rauschen
   (Skript erzeugt sie in ≈ 2 Minuten).
6. Gesamteindruck: Die Referenz bleibt dichter und kontrastreicher (gemalt, jeder Bildpunkt
   gestaltet); unsere Massive sind etwas weicher, das Tiefland heller.
