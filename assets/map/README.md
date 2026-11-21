# Kartentexturen (Kontinentansicht)

Luftbild-Texturen für die Kontinentansicht (Kontinent 1.600 km, Raster etwa 3 km, Arbeitsentfernung
etwa 1–1,5 km je Bildschirmpunkt, dazu 2–4-fach näher). Alle Bilder sind **nahtlos kachelbar**, senkrecht
von oben, ohne Horizont, Straßen, Felder oder Schrift, mit weichem Licht von oben links.
Erzeugt am 21. 11. 2026.

## Herkunft und Lizenz

- **Erzeugt mit Higgsfield** (Modell GPT Image 2.6, Qualität hoch, 2k, 1:1, je 2 Guthaben).
  Nutzungsrechte nach den Higgsfield-Bedingungen des Kontos (Starter-Plan) – **vor einer
  Veröffentlichung prüfen**. Keine Fremdbestände, keine Fotos Dritter.
- Jede Anweisung mit Auftragsnummer, Adresse, Modell, Guthaben und Datum steht in
  `source/generated.json` (UTF-8 ohne BOM, im Repository). Die Originale (je etwa 10 MB PNG, 2048²)
  liegen in `source/` und sind **nicht** im Repository.
- KI-Erzeugung ist nicht wiederholbar. Wiederholbar ist die **Nachbearbeitung**: Sie verwendet festen
  Zufall (fester Ausgangswert je Name) und liefert aus denselben Originalen dieselben Dateien.
- Kosten: 13 Bilder = **26 Guthaben** (Stand vorher 553,85, nachher 527,85). Vier Bilder davon sind
  verworfene erste Fassungen (siehe unten).

## Werkzeuge

```powershell
python tools\higgsfield_map_textures.py [name ...]   # Originale erzeugen (nur fehlende; je etwa 2 Guthaben)
python tools\make_seamless_textures.py [name ...]    # nahtlos machen, verkleinern, Höhenkarten, Vorschauen
```

`tools/make_seamless_textures.py` braucht nur Python 3 und Pillow (kein numpy). Die Schritte je Original:

1. mittig quadratisch zuschneiden;
2. großräumigen Helligkeitsverlauf entfernen: nur die Helligkeit, Farbtöne bleiben;
3. nahtlos machen **durch Überlappung**: Der rechte bzw. untere Randstreifen (1/8 der Breite) wird in den
   linken bzw. oberen Streifen überblendet und dann abgeschnitten. Dadurch kommt kein Bildinhalt doppelt
   vor, anders als beim Verschieben um eine halbe Kachel. Die Überblendmaske folgt der Helligkeit und
   festem Rauschen, also einer unregelmäßigen Linie statt eines Schleiers. Danach wird die grobe Helligkeit
   des Streifens an eine einfache Überblendung angeglichen;
4. gerade Helligkeitsbänder entlang der Zeilen und Spalten entfernen (kreisförmig geglättet, bleibt nahtlos);
5. auf 2048² bzw. 1024² bringen, JPG Qualität 90;
6. für Fels und Wald eine Höhenkarte aus der Helligkeit (1024², Graustufen-PNG);
7. Vorschauen: `source/<name>_tiled.jpg` (2 × 2 gekachelt) und `source/<name>_seam.jpg` (Kachelecke in
   voller Auflösung).

Prüfung der Nähte: Der Helligkeitssprung über die Kachelkante entspricht bei allen Texturen dem Sprung
zwischen zwei benachbarten Spalten im Bildinneren. Der Randstreifen weicht höchstens 0,3 Graustufen vom
Bildmittel ab.

## Dateien

Kachelgröße = empfohlene Weltgröße einer Kachel (Texturwiederholung) in der Kontinentansicht.

| Datei | Inhalt | Größe | Quelle (in `source/`) | Kachel | Gedacht für |
|---|---|---|---|---|---|
| `rock_massif.jpg` | zerklüftetes Kalk-/Granitgebirge aus ~10 km: dichte Grate, dunkle Rinnen, Geröllfächer, wenig Grün, kein Schnee | 2048², 1,6 MB | `rock_massif` | **80 km** (≈ 39 m je Texel; Hauptgrate alle ~10 km) | Fels, Gebirge (Lücke 1 und 2) |
| `rock_massif_b.jpg` | zweite Felsvariante: wärmeres Beige, Kare, Felswände, breite Schuttflächen | 2048², 1,6 MB | `rock_massif_b` | 80–100 km | mit `rock_massif` mischen (gegen Wiederholung) |
| `rock_massif_height.png`, `rock_massif_b_height.png` | Höhenkarte aus der Helligkeit (hell = Grat, Geröll; dunkel = Rinne, Schatten) | 1024², 0,8 MB | – | wie die Farbtextur | Höhenüberblendung Fels ↔ Schnee ↔ Wiese, Rinnen abdunkeln |
| `alpine_snow.jpg` | Hochgebirge aus ~10 km: Firnfelder, schneegefüllte Rinnen, dunkle Grate | 2048², 1,4 MB | `alpine_snow` | 80 km (wie Fels) | Schnee oberhalb der Schneegrenze |
| `forest_mixed.jpg` | dichter Mischwald aus ~3 km: feine Kronen-Tüpfel, dunkle Nadel- und hellere Laubgruppen, Kronenschatten | 2048², 1,8 MB | `forest_mixed` | 40–60 km (Näheres unten) | Wald im Tal und Hügelland (Lücke 4) |
| `forest_conifer.jpg` | dichter Bergnadelwald aus ~3 km: blaugrün, feine Tüpfel, einzelne Lärchen | 2048², 1,4 MB | `forest_conifer` | 40–60 km | Wald an Hängen und in der Höhe |
| `forest_mixed_height.png`, `forest_conifer_height.png` | Kronenhöhe aus der Helligkeit (hell = Krone, dunkel = Lücke) | 1024², 0,9 MB | – | wie die Farbtextur | ausgefranste Waldränder (Schwelle gegen Rauschen), Kronenschatten |
| `meadow_mosaic.jpg` | Grasland aus ~5 km: weiches Mosaik aus Oliv, Gelbgrün, Ocker und frischem Grün, Buschgruppen entlang Abflusslinien | 2048², 1,5 MB | `meadow_mosaic_v2` | **100 km** (Flecken ≈ 15–25 km) | Wiesen und Böden (Lücke 3) |
| `scrub_heath.jpg` | Übergangszone: Heide und Gras, dicht mit dunklen Büschen und Jungbäumen betupft | 2048², 1,8 MB | `scrub_heath` | 40–60 km | weicher Waldrand Wald → Busch → Wiese (Lücke 4) |
| `dry_ground.jpg` | trockene Hochsteppe: ockerfarbenes und blasses olivfarbenes Gras, offener Boden, vereinzelte Büsche | 1024², 0,5 MB | `dry_ground` | 30–40 km | trockene Lagen, Südhänge, Ockerflächen (Lücke 3) |
| `coast_shallows.jpg` | Flachwasser aus ~3 km: Türkis über hellen Sandbänken mit Rippeln, dunkle Riff- und Seegrasflecken, überall gleich tief | 1024², 0,4 MB | `coast_shallows_v2` | 20–30 km | Küstensaum im Meer (Lücke 5); Tiefe und Farbe im Shader |
| `beach_rock.jpg` | Felsküste aus ~1 km: Sand, Kiesbänder, dunkle nasse Felsplatten, Tang | 1024², 0,6 MB | `beach_rock_v2` | 8–15 km | Felsküste, Landzungen (Lücke 5) |

Verworfene erste Fassungen (nur im Protokoll und in `source/`, nicht verwendet):
- `meadow_mosaic`: einheitlich grelles Grün, zu nah, kein Mosaik;
- `coast_shallows`: Meeresgrund aus wenigen Metern Höhe (Lichtnetze, Einzelsteine), wird bei 20–60 m je Texel zu Rauschen;
- `beach_rock`: Kiesel in Bodennähe, ebenfalls viel zu nah.

## Begründung der Auswahl (sichtbare Lücken: Referenz gegen Editor)

1. **Breite, zerklüftete Gebirge.** Im Editor sind Berge weiche Beulen ohne Binnenzeichnung. Die
   Referenz zeigt dichte Messergrate mit dunklen Rinnen alle 10–20 Bildpunkte. Deshalb zwei Felsmassive
   mit hoher Gratdichte, dazu Höhenkarten, mit denen sich Rinnen abdunkeln und Schnee in Mulden legen
   lässt.
2. **Strukturierte Felsflächen.** Hellgrau-beige mit Erosionsstreifen und Geröll: beide Felstexturen.
   Die Variante b ist wärmer und flächiger, damit sich Hänge unterscheiden.
3. **Differenzierte Wiesen und Böden.** Statt einer Fläche Gelbgrün ein Mosaik aus Oliv, Gelbgrün, Ocker
   und Buschpunkten (`meadow_mosaic`), dazu `dry_ground` für Ockerflächen.
4. **Glaubwürdige Wälder.** Statt glatter Dunkelgrünflecken Kronen-Tüpfel mit Schatten, Mischwald
   und Nadelwald getrennt, dazu `scrub_heath` und die Kronenhöhe für ausgefranste, weiche Ränder.
   Die Farben passen zur Familie der 300-m-Texturen in `assets/target/`: Mittelwerte RGB
   Mischwald (56, 79, 35) zu Laubdach (66, 93, 29); Nadelwald (27, 48, 36) zu Nadeldach (31, 52, 38).
5. **Natürliche Küsten.** Türkisfarbenes Flachwasser mit Sand und Riff (`coast_shallows`) sowie
   Felsküste (`beach_rock`).

## Hinweise zur Einbindung

- **Maßstab der Wälder.** Die Referenz übertreibt die Baumgröße stark: Kronen-Tüpfel von 1–3 Bildpunkten
  bei 1–1,5 km je Bildpunkt wären echte Kronen von 1–4 km. Mit echtem Maßstab (40–60 km je Kachel)
  verschwimmen die Tüpfel in der Arbeitsentfernung zu einer Tönung und werden erst beim Näherzoomen
  sichtbar. Für den Kartenblick ist eine zweite, **stilisierte Abtastung mit etwa 200–300 km je Kachel**
  sinnvoll, die mit der echten Abtastung je nach Zoom überblendet wird. Ob das gefällt, zeigt nur der
  Vergleich im Editor.
- **Wiederholung.** In der 2 × 2-Vorschau sind einzelne auffällige Formen wiedererkennbar (z. B. die
  diagonale Rinne in `rock_massif`, Ockerflecken in `meadow_mosaic`). Abhilfe im Shader: `rock_massif`
  und `rock_massif_b` nach Rauschen mischen, je Kachel drehen oder spiegeln (die Lichtrichtung von oben
  links dreht dann mit; bei Fels und Schnee höchstens spiegeln entlang der Lichtachse), oder zwei Maßstäbe
  (×1 und ×0,27) mischen.
- **Eingebranntes Licht.** Fels, Schnee und Wald tragen Schatten von oben links. Die Sonne im Editor
  sollte ungefähr von Nordwesten kommen, sonst widersprechen sich Texturschatten und Geländeschattierung.
- **Farbanpassung.** `coast_shallows` ist eher grünlich-türkis; die Referenz ist kühler (Cyan). Im
  Shader tönen und mit der Wassertiefe zu Tiefblau überblenden. `meadow_mosaic` ist gedämpft und darf in
  den Tälern Richtung Gelbgrün gezogen werden (Referenz: kräftiges Gelbgrün).
- Normalenkarten gibt es nicht; die Höhenkarten können im Shader als Ableitung (Steigung je Texel)
  benutzt werden, falls feine Schattierung nötig ist.

## Erosionskacheln (eigene Herstellung, Blender + numpy)

Kachelbare Geländeform-Details: abgetragene Gebirge mit verzweigten Talnetzen, Messergraten,
Rinnen und Schwemmfächern. **Kein KI-Bild, keine Fremdbestände** – vollständig berechnet,
fester Ausgangswert, jeder Lauf liefert dieselben Dateien. Lizenz: eigenes Werk des Projekts.

```powershell
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup `
  --python tools\blender\make_erosion_tiles.py -- D:\WELTWERK all     # oder: alpine | hills
```

Ablauf (Einzelheiten im Kopf des Skripts): periodisches Hebungsfeld + Gratrauschen (FFT, Torus) →
Flusserosion nach dem Stream-Power-Gesetz mit Senkenfüllung und Hangkriechen auf 256² und 512²
(verzweigte Täler, scharfe Grate) → 1024²: feines Gratrauschen, Flussschritte, Tropfenerosion mit
Umlauf (Rinnen, Ablagerungen), thermische Erosion (Schutthalden) → Masken, Normalen.
Laufzeit je Kachel etwa 1,5–2 Minuten (beide parallel etwa 2 Minuten).

| Datei | Inhalt | Größe | Ausgangswert | Annahme für Normalen | Empfohlene Kachel |
|---|---|---|---|---|---|
| `erosion_alpine_height.png` | Höhe, 16 Bit Grau, volle Spanne 0..65535 | 1024², 1,6 MB | 20261121 | 24 km breit, 2,5 km Höhenspanne (23,4 m je Texel); Neigung Median 40°, 90 % 49° | **48–96 km** in der Arbeitsentfernung (Hauptgrate dann alle ~5–10 km, Rinnen alle 1–3 Bildschirmpunkte); beim Näherzoomen zusätzlich mit 24 km mischen |
| `erosion_alpine_normal.png` | Normalen im Tangentenraum, 8 Bit RGB, OpenGL (Grün = +Y = im Bild oben) | 1024², 1,9 MB | | wie oben | wie die Höhe |
| `erosion_alpine_masks.png` | RGBA: **R** Abflussmenge/Rinnen (log, 0..1, Hänge schwarz), **G** Grate (Konvexität), **B** Neigung (0 flach .. 1 = 60° und steiler), **A** Höhe 0..1 (= Höhenkarte in 8 Bit) | 1024², 2,7 MB | | wie oben | wie die Höhe |
| `erosion_hills_height.png` | Höhe, 16 Bit, weichere, gerundete Hügel mit Tälern | 1024², 1,5 MB | 20261122 | 12 km breit, 0,5 km Höhenspanne (11,7 m je Texel); Neigung Median 18°, 90 % 22° | **24–48 km** (Vorberge, Hochland, Hügelland) |
| `erosion_hills_normal.png` | wie oben | 1024², 1,0 MB | | wie oben | wie die Höhe |
| `erosion_hills_masks.png` | wie oben | 1024², 2,2 MB | | wie oben | wie die Höhe |

Hinweise:
- **Maßstab der Normalen.** Die Steigung in der Normalenkarte gilt für die genannte Annahme. Liegt die
  Kachel mit L km statt 24 km (bzw. 12 km), entspricht die echte Steigung dem Faktor 24/L. Für die
  überhöhte Kartenansicht ist die stärkere Steigung erwünscht; sonst im Shader `n.xy *= faktor` und neu
  normieren.
- **Verwendung.** Höhe bzw. A als Feinform zur groben Kontinenthöhe addieren (gewichtet nach Gebirgsmaske);
  R für dunkle Rinnen, Schnee in Rinnen, Geröll an deren Fuß; G für helle Grate und Schneefreiheit;
  B für Fels gegen Wiese. Alle Karten passen pixelgenau zueinander und schließen nahtlos an.
- **Wiederholung.** Talnetze sind unverwechselbar und daher wiedererkennbar. Gegenmittel: zwei Maßstäbe
  mischen, alpine und hills nach Rauschen überblenden, Kachel je Zelle spiegeln (bei Spiegelung die
  x- bzw. y-Komponente der Normale umkehren).
- Vorschauen (nicht im Repository): `source/vorschau_<name>_relief.png` (Schummerung, Licht aus
  Nordwest), `_2x2.png` (gekachelt), `_naht.png` (Kachelecke in der Bildmitte), `_masken.png`
  (R, G, B, A nebeneinander), `_farbe.png` (grobe Farbprobe), `erosion_lauf_<name>.json` (Messwerte).
