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
| `bearbeitung_pass_rueckgaengig.jpg` | nach Rückgängig der letzten Bearbeitung |
| `neustart_*.jpg` | Schritt 2: wiederhergestellte Ansicht, Bearbeitung, Ende |

**Lesen:** Jede Stelle trägt eine Messingnadel – Ring am Boden, senkrechter Stiel, Kopf mit Name
und **Höhe dieser Stufe**. Die Überschrift nennt Stelle und Stufe. Alle Bilder einer Zeile haben
denselben Kameraabstand und Blickwinkel; die Nadel steht immer in der Bildmitte. Dieselbe
Landschaft heißt: Auf jeder Stufe sitzt die Nadel auf derselben Form (Gipfelkuppe, Einsattelung
im Kamm, Talsohle), und die Umgebung der nächstgröberen Stufe findet sich vergrößert wieder.
Liegen Stellen dicht beieinander, werden die Köpfe übereinander gestaffelt.

## Messung (Schritt 1)

Gemessen wird in den Ausschnitten, die der Editor auf jeder Stufe tatsächlich zeigt.

- **Höhen:** 5 × 5 Punkte im Abstand 625 m (1/40 der 25-km-Stufe) um jede Stelle; jede Stufe
  gegen die Detailstufe. Erlaubt sind 20 m plus die halbe Spannweite des feinen Geländes
  innerhalb von 1,5 Rasterzellen der Stufe – was eine Stufe nicht auflösen kann, darf geglättet
  sein. Zur Information zusätzlich die Abweichung vom über eine Zelle gemittelten feinen Gelände
  („zum Zellmittel“): So groß wäre der Unterschied, wenn die grobe Stufe das Feine nur mittelte.
- **Formgröße:** Halbrelief-Radius aus einem 24-km-Vergleichsausschnitt (94-m-Raster): beim
  Gipfel der Abstand, in dem das Kreismittel um die Hälfte des Gipfelreliefs gefallen ist; beim
  Tal quer zum Tal; beim Pass der kleinere Wert aus Kammanstieg und Querabfall.
- **Form je Stufe:** Ist die Form kleiner als 1,5 Rasterzellen (unter 3 Zellen Durchmesser), gilt
  sie als nicht aufgelöst und darf geglättet sein. Sonst muss mindestens 30 % ihres Reliefs
  erhalten sein, und der Gipfel bzw. Talgrund dieser Stufe darf höchstens eine Rasterzelle
  (mindestens ¼ der Formgröße) neben der Stelle liegen – oder dort kaum höher bzw. tiefer sein
  (20 m + 10 % des Reliefs). Beim Pass muss es entlang des Kamms steigen und quer dazu fallen.

## Bearbeiten, Rückgängig, Neustart

Auf der 25-km-Stufe mit echten Mausereignissen: Gipfel **erhöhen**, Tal entlang der Sohle
**senken**, Pass entlang des Kamms **glätten**. Geprüft wird, dass die Darstellung sich dort ändert
und die Änderung auf der Kontinentstufe vereinfacht in gleicher Richtung erscheint. Die letzte
Bearbeitung wird rückgängig gemacht – angezeigter Ausschnitt und Kontinentstufe müssen bitgleich
zum Stand davor sein – und wiederholt; dann wird gespeichert.

Schritt 2 (Neustart) prüft: gleiche Bearbeitungen, letzte Ansicht wiederhergestellt, an jeder
Stelle ein frisch berechneter 25-km-Ausschnitt bitgleich (Prüfsumme) und die Höhen an der Stelle
und auf dem 5 × 5-Raster bitgleich (als Bitmuster gespeichert, da Godots JSON-Leser die letzte
Binärstelle verschieben kann), Kontinentstufe bitgleich; dann Erhöhen → Rückgängig (bitgleich)
→ Wiederholen, eine weitere Bearbeitung → Rückgängig (bitgleich), Speichern.
