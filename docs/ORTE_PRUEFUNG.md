# Ortsprüfung: dieselbe Landschaft auf allen Maßstäben

Die Ortsprüfung zeigt und misst, ob ein markanter **Gipfel**, ein **Pass** und ein **Tal** an
festen Stellen des Kontinents auf jeder Stufe dieselben bleiben – Kontinent (1.600 km),
Region 1:8 (200 km), Region 1:64 (25 km) und Detail 1:512 (3,1 km). Danach wird dort mit der
Maus bearbeitet und geprüft, ob Darstellung, Speichern, Neustart und Rückgängig stimmen.

Programmteile: `src/editor/landmark_run.gd` (Ablauf, Markierungen, Bilder),
`src/domain/world/landmarks.gd` (Suche und Einordnung, reine Funktionen, Tests in
`tests/test_landmarks.gd`). Der Kontinent wird wie im Referenzvergleich gebaut
(`ComparisonRun.build_outline` / `build_features`, echte Mausereignisse, 42° Breite).

## Aufruf

```powershell
$godot = "C:\Users\Mattes\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
& $godot --position 2000,60 --path D:\WELTWERK -- --orte=D:\WELTWERK\docs\orte --schritt=1
& $godot --position 2000,60 --path D:\WELTWERK -- --orte=D:\WELTWERK\docs\orte --schritt=2
```

Schritt 1 legt immer eine neue Welt in `<Ordner>/welt.json` an (nie die Hauptwelt). Schritt 2 ist
ein neuer Programmstart mit derselben Datei. Beide Schritte geben am Ende
`ORTE Schritt N: x Prüfungen, y fehlgeschlagen` und jede Prüfung als Zeile aus und schreiben
`orte_1.json` bzw. `orte_2.json`. Dauer Schritt 1 etwa 1½ Minuten.

Hinweis: „Neu zeichnen“ wählt den Ausgangswert eines neuen Kontinents zufällig – jeder Lauf von
Schritt 1 baut daher denselben Umriss mit denselben Strichen, aber andere Gebirgsformen. Die
Stellen werden deshalb immer aus den Daten gesucht, nie aus festen Koordinaten.

## Wie die Stellen gefunden werden

- **Gipfel:** Auf der Kontinentstufe die Mitte des größten Massivs (Höhen über 30 km gemittelt),
  dort der höchste Punkt; in zwei feineren Ausschnitten (10 km, 1,5 km) nachgeschärft.
- **Pass:** Von oben „geflutet“: Wo das Gebiet des Gipfels zuerst mit dem eines anderen hohen
  Gipfels (mind. 15 km entfernt, mind. 120 m über dem Joch) zusammenwächst, liegt das Joch des
  höchsten Verbindungswegs – der tiefste Punkt der Kammlinie dazwischen. Gewählt wird der
  Partner mit dem höchsten Joch (Hauptkamm), dann in 8 km und 2 km nachgeschärft.
- **Tal:** Die Stelle, an der beide Talseiten im Abstand von 6 km am deutlichsten höher sind –
  auch 5 km talauf und talab (lange Rinne, kein Loch), auf Land ohne Binnenwasser, mindestens
  15 km von der Küste; danach der tiefste Punkt der Talsohle in der Nähe.

Lage (Kontinentmeter, x = Osten, y = Norden), Höhe, Achsen und der Suchweg stehen in `orte.json`.

## Bilder

| Datei | Inhalt |
|---|---|
| `vergleich_alle.jpg` | Übersicht: je Zeile eine Stelle, je Spalte eine Stufe |
| `vergleich_gipfel.jpg`, `_pass`, `_tal` | eine Stelle auf vier Stufen nebeneinander |
| `ort_<stelle>_<0–3>.jpg` | Einzelbilder (0 Kontinent … 3 Detail; nur lokal, nicht im Repository) |
| `bearbeitung_<stelle>.jpg` | vorher / nachher auf der 25-km-Stufe |
| `bearbeitung_kontinent_vorher/nachher.jpg` | Kontinentstufe vor und nach den Bearbeitungen |
| `bearbeitung_<stelle>_rueckgaengig.jpg` | nach Rückgängig der Bearbeitung an dieser Stelle |
| `neustart_*.jpg` | Schritt 2: wiederhergestellte Ansicht, Bearbeitung, Ende |

**Lesen:** Jede Stelle trägt eine Messingnadel – Ring am Boden, senkrechter Stiel, Kopf mit Name
und **Höhe dieser Stufe**. Die Überschrift nennt Stelle und Stufe. Alle Bilder einer Zeile haben
denselben Kameraabstand und Blickwinkel; die Nadel steht immer in der Bildmitte. Dieselbe
Landschaft heißt: Auf jeder Stufe sitzt die Nadel auf derselben Form (Gipfelkuppe, Einsattelung
im Kamm, Talsohle), und die Umgebung der nächstgröberen Stufe findet sich vergrößert wieder.
Liegen Stellen dicht beieinander, werden die Köpfe übereinander gestaffelt.

## Messung (Schritt 1)

Gemessen wird in den Ausschnitten, die der Editor auf jeder Stufe tatsächlich zeigt.

- **Höhen je Stufe:** 5 × 5 Punkte im Abstand 625 m (1/40 der 25-km-Stufe) um jede Stelle. Jede
  gröbere Stufe wird mit dem **über eine ihrer Zellen gemittelten feinen Gelände** verglichen
  (Kreis mit halber Zellbreite; aus der Detailstufe, wo sie die ganze Zelle enthält, sonst aus
  dem 24-km-Vergleichsausschnitt mit 94-m-Raster). Erlaubt sind je Punkt 20 m plus 15 % der
  Spannweite des feinen Geländes innerhalb einer Zelle der Stufe, und der mittlere Versatz über
  die 25 Punkte darf höchstens 20 m plus 10 % der Höhenspanne des Rasters betragen. Die frühere
  Messung (Abweichung zur Detailstufe, erlaubt 20 m plus halbe Spannweite innerhalb von
  1,5 Zellen) steht nur noch zur Information in `orte_1.json` (`info_…`).
- **Im Maßstab des Kontinents:** 13 × 13 Punkte im Abstand 10 km (120 km) um jede Stelle; die
  Kontinentstufe gegen den 200-km-Ausschnitt, auf eine Kontinentzelle (3,1 km) gemittelt.
  Verlangt: Korrelation mindestens 0,9 und mittlerer Versatz höchstens 20 m plus 10 % der
  Höhenspanne des Rasters. Dazu der **Verlauf**: beim Pass der Hauptkamm Gipfel → Joch →
  Nachbargipfel (aus der Passsuche), beim Tal die Haupttalachse (± 10 km entlang der Richtung aus
  der Talsuche im 200-km-Ausschnitt). Punkte im Abstand einer halben Kontinentzelle; an jedem muss
  der höchste (Kamm) bzw. tiefste (Tal) Wert innerhalb einer Zelle quer zur Linie über bzw. unter
  beiden Seiten im Abstand von zwei Zellen liegen. Gezählt werden die Punkte, an denen der
  gemittelte 200-km-Ausschnitt den Verlauf selbst zeigt (das müssen mindestens die Hälfte sein);
  davon muss die Kontinentstufe mindestens 90 % halten.
- **Formgröße:** Halbrelief-Radius aus einem 24-km-Vergleichsausschnitt (94-m-Raster): beim
  Gipfel der Abstand, in dem das Kreismittel um die Hälfte des Gipfelreliefs gefallen ist; beim
  Tal quer zum Tal; beim Pass getrennt für Kammanstieg und Querabfall.
- **Form je Stufe:** Ein Formteil kleiner als 1,5 Rasterzellen (unter 3 Zellen Durchmesser) gilt
  als nicht aufgelöst und ist ausgenommen; beim Pass werden Kammanstieg und Querabfall einzeln
  beurteilt – ist nur einer zu klein, wird der andere trotzdem geprüft. Für aufgelöste Teile muss
  mindestens 30 % des Reliefs erhalten sein, und der Gipfel bzw. Talgrund dieser Stufe darf
  höchstens eine Rasterzelle (mindestens ¼ der Formgröße) neben der Stelle liegen – oder dort kaum
  höher bzw. tiefer sein (20 m + 10 % des Reliefs). Beim Pass muss es entlang des Kamms steigen
  und quer dazu fallen.

## Bearbeiten, Rückgängig, Neustart

Auf der 25-km-Stufe mit echten Mausereignissen: Gipfel **erhöhen** (verlangt mindestens +100 m),
Tal entlang der Sohle **senken**, Pass entlang des Kamms **glätten** (großer Pinsel, volle Stärke;
verlangt: Rauheit – mittlere Abweichung vom Mittel der Nachbarn im Abstand zweier Rasterzellen –
mindestens 15 % geringer und Änderung mindestens 20 m). Vor jeder Bearbeitung wird der angezeigte
Ausschnitt mit einem frisch berechneten verglichen: eigener Sampler, Zwischenspeicher der
Grundform geleert (`TerrainSampler.clear_base_cache()`), also einschließlich Grundform. Geprüft
wird, dass die Darstellung sich ändert und die Änderung auf der Kontinentstufe vereinfacht in
gleicher Richtung erscheint. **Jede** der drei Bearbeitungen wird danach an Ort und Stelle
rückgängig gemacht – angezeigter Ausschnitt und Kontinentstufe müssen bitgleich zum frisch
berechneten Stand davor sein – und wiederholt: Der angezeigte Ausschnitt (derselbe Ausschnitt)
wird mit dem direkt nach dem Mausstrich live bemalten Stand verglichen, die Kontinentstufe muss
bitgleich zur frisch berechneten nach dem Malen sein. Zum Schluss wird gespeichert.

Schritt 2 (Neustart) prüft: gleiche Bearbeitungen, letzte Ansicht wiederhergestellt; Lagen und
Achsen der Stellen sowie Mitte, Größe und Auflösung der Vergleichsausschnitte werden aus
Bitmustern in `orte_1.json` gelesen (Godots JSON-Leser kann die letzte Binärstelle verschieben).
An jeder Stelle muss ein frisch berechneter 25-km-Ausschnitt (Zwischenspeicher geleert) bitgleich
sein (Prüfsumme), ebenso die Höhen an der Stelle und auf dem 5 × 5-Raster, und die Kontinentstufe;
dann Erhöhen → Rückgängig (bitgleich) → Wiederholen, eine weitere Bearbeitung → Rückgängig
(bitgleich), Speichern.

## Befunde des Laufs vom 21. 11. 2026

Schritt 1: 72 Prüfungen, 8 fehlgeschlagen; Schritt 2: 22 Prüfungen, 0 fehlgeschlagen. (Jeder
Lauf baut andere Gebirgsformen; ein Lauf davor ergab 7 Fehlschläge mit demselben Bild.)

- **Kontinentstufe an Gipfel und Tal zu glatt:** Am Gipfel liegt sie im Mittel 176 m (anderer
  Lauf 361 m) unter dem Zellmittel des feinen Geländes, bis 346 m (493 m) bei erlaubt 151 m
  (175 m); am Talgrund im Mittel 398 m (127 m) darüber, bis 530 m (255 m) bei erlaubt 215 m
  (153 m). Die alte, weite Toleranz hatte das durchgelassen. Im 120-km-Raster stimmen Verlauf
  (Korrelation 0,99) und Mittel (bis 12 m) dagegen gut, Hauptkamm und Haupttalachse bleiben auf
  der Kontinentstufe erhalten (12/12, 14/14 Punkte; anderer Lauf 11/12, 13/13).
- **Region 200 km:** einzelne Punkte 104–132 m vom Zellmittel bei erlaubt 61–79 m, mittlerer
  Versatz im Rahmen.
- **Glätten wirkt kaum auf die Rauheit:** Die Höhen ändern sich bis 346 m, die Rauheit im
  Zwei-Zellen-Abstand aber nicht (16,6 → 17,0 m; anderer Lauf 18,8 → 18,6 m). Glätten nimmt nur
  feine Täler und Rinnen zurück; Massive und Haupttäler des Erosionsreliefs bleiben und bestimmen
  die Rauheit (zur Information: im Abstand von 8 Zellen −11 %, von 16 Zellen +13 %).
- **Pass im zweiten Lauf nur eine kleine Einkerbung:** Das Nachschärfen landete auf einem Joch mit
  Formgröße 190 m (Kamm) bzw. 380 m (quer) und 8 bzw. 61 m Relief; auf Kontinent- und 200-km-Stufe
  ist er damit „zu klein für das Raster“ (im ersten Lauf: 6,2 / 8,2 km, als Sattel auf allen
  Stufen bestätigt). Die Kammprüfung im Kontinentmaßstab gilt unabhängig davon.
- Rückgängig und Wiederholen sind für alle drei Bearbeitungen bitgleich (Kontinentstufe) bzw.
  höchstens 0,001 m vom live bemalten Stand entfernt.
