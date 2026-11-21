# Bericht: Kontinente, Kontinentalkarten, Regionen (21. 11. 2026)

Auftrag: eigene Kontinente anlegen, auf dem Globus platzieren, daraus brauchbare,
detaillierbare Kontinentalkarten gestalten; Regionen als anschließendes Ziel. Entwurf:
`docs/ENTWURF_KONTINENTE.md`. Abnahme mit neuer Testwelt: bestanden (siehe unten).

## Starten

```powershell
$godot = "C:\Users\Mattes\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
& $godot --path D:\WELTWERK                       # Editor mit der eigenen Welt (user://welt.json)
& $godot --path D:\WELTWERK -- --neu              # leere Probewelt (user://welt_neu.json, nie die Hauptwelt)
& $godot --position 2000,60 --path D:\WELTWERK -- --abnahme=D:\WELTWERK\docs\abnahme --schritt=1   # Abnahme Teil 1
& $godot --position 2000,60 --path D:\WELTWERK -- --abnahme=D:\WELTWERK\docs\abnahme --schritt=2   # Teil 2 (Neustart)
```

Der Editor startet dort, wo zuletzt gearbeitet wurde (Globus, Kontinent oder Region).

## Ablauf in der Oberfläche

1. **Globus**: rechts „Neu zeichnen“ (leere Meeresfläche, gleich mit „Land zeichnen“) oder
   „Neu erzeugen“ (erzeugte Grundform als Ausgangspunkt). Klick wählt einen Kontinent, Ziehen
   auf dem gewählten verschiebt ihn, Ziehen daneben dreht den Globus, Doppelklick öffnet.
   Regler: Planetengröße (bis doppelte Erde), Größe, Breite, Länge, Ausrichtung, Klima;
   Namensfeld (bleibt leer, bis der Spielleiter einen Namen vergibt); „Löschen“ mit Rückfrage.
2. **Kontinent**: Werkzeugleiste links in Gruppen – Form (Land zeichnen, Land wegschneiden,
   Küste anfügen/abtragen), Gelände (Erhöhen, Senken, Glätten, Ebene, Gebirge, Hügelland),
   Wasser (Fluss, See, Inseln), Bewuchs (Wald malen/entfernen, Wald verteilen), Schützen.
   Oben daneben steht immer das aktive Werkzeug mit einem Satz zur Bedienung und nur den
   Reglern, die es braucht; „Neu würfeln“ bei Erzeugung. Pinselkreis in echter Größe,
   Umriss und Fluss als Linie vor dem Loslassen. Unten rechts die Übersichtskarte mit dem
   sichtbaren Ausschnitt (Klick springt), unten die Statuszeile mit Landfläche, Ausdehnung
   und Breitenlage.
3. **Regionen**: am Zoom-Anschlag weiter hineinzoomen öffnet 1/8 unter dem Mauszeiger (bis
   etwa 400 m Seitenlänge). Pfad oben (Welt / Kontinent / Region 1:8 / …) führt zurück.
   Verschiebt man über den Rand, wandert der Ausschnitt mit.

## Was funktioniert (geprüft)

Abnahme mit echten Mausereignissen in zwei getrennten Programmläufen (`docs/abnahme/`):
**Teil 1: 20/20 Prüfungen, Teil 2 (nach Neustart): 9/9.** Dazu 49 Tests der Fachlogik.

| Prüfung | Bild |
| --- | --- |
| Neue, leere Welt; „Neu zeichnen“ öffnet den Kontinent mit „Land zeichnen“ | `a01`, `a02` |
| Umriss mit der Maus gezeichnet → Land; Bucht weggeschnitten → Meer | `a03` |
| Gebirge (bis 3.200 m), „Neu würfeln“ ersetzt die Erzeugung | `a04`, `a05` |
| Hügelland, Wald verteilen, Fluss (Spiegel fällt), See (Wasser über Grund), Inseln, Schutz | `a04`, `a05` |
| Zurück zum Globus, Kontinent mit der Maus verschoben (ein Rückgängig-Schritt) | `a06`, `a07` |
| Ausrichtung und Größe je ein Schritt; Planetengröße 9.000 km | `a07` |
| Zweiter, erzeugter Kontinent; Löschen; Rückgängig stellt ihn wieder her | `a08` |
| Doppelklick öffnet den Kontinent; Region 1:64 vertiefen, Wald und Höhe malen | `a09` |
| Herauszoomen: Detailarbeit vereinfacht und am richtigen Ort markiert | `a10` |
| Gespeichert = geladen (gleicher Stand) | – |
| Neustart: beide Kontinente, gleicher Weltstand, Höhen bitgleich, letzte Ansicht (Region) | `b01` |
| Weiterarbeiten nach Neustart, Rückgängig und Wiederholen | `b02` |
| Ausschnitt wandert beim Verschieben über den Rand mit | `b02b` |
| Globus nach Neustart | `b03` |

Weitere geprüfte Eigenschaften (Tests): Land-Bearbeitungen wirken in Reihenfolge (zweimal
anfügen, dann abtragen = Meer); kein Land jenseits des Kontinentfensters; Grundform wächst beim
Skalieren mit („Alles wächst mit“); Live-Malen ergibt genau dasselbe wie die Neuberechnung;
Schutz hält die alte Variante fest und blockiert spätere Erzeugung, ältere Erzeugung bleibt;
beschädigte Weltdatei wird beiseitegelegt und der letzte gute Stand geladen; alte Weltdateien
(ohne Kennungen) werden übernommen; Landfläche einer gezeichneten Form auf ±6 % genau.

**Grafik** – bewertet auf fünf Stufen im benutzbaren Editor (`docs/stufen/`, vorher/nachher):

- Feinster Ausschnitt (≈ 400 m): gemischter Wald mit Laub- und neuen Nadelbäumen, Farb- und
  Größenstreuung je Baum, Arten nach Höhe und Klima; feineres Gras, das zu Ufer und Waldrand
  hin ausläuft; klares Flachwasser mit Felsen am Ufer.
- Mittlere Stufen (3–240 km): Wiesenfarben aus der Zielpalette in festen Meterwellen (gleiche
  Welt auf jeder Stufe statt mitwachsender Musterung), Wald als Kronendach-Luftbild.
- Kontinent: Schummerung, Höhenstufen, Schnee, Flüsse und Seen als Wasser.
- Globus: alle Kontinente, gewählter mit Messingrahmen, helleres Meer, Atmosphärensaum.

Messwerte (RTX 2070 Super, 1440 × 900): Kontinent bis Region 3 km 280–310 Bilder/s;
feinster Ausschnitt 160 Bilder/s (Wiese/Ufer) bzw. 62 Bilder/s (dichter Mischwald,
3,4 Mio. Dreiecke). Ausschnitt berechnen 0,2–0,6 s, feinster mit Bäumen und Gras 0,7–1,0 s.

## Eingeschränkt

- **Formen einzeln ändern**: Ein gezeichneter Umriss lässt sich nicht nachträglich anfassen
  und verschieben; ändern heißt übermalen (anfügen/wegschneiden/Küste) oder Rückgängig.
  „Umriss aus erzeugter Grundform“ (Erzeugung als bearbeitbare Form) fehlt.
- **Flüsse** folgen dem Gefälle nur entlang des gezogenen Laufs (Spiegel steigt nie an, Lauf
  wird zum tieferen Ende ausgerichtet); sie suchen sich keinen Weg selbst. Seen sind rund.
- **Regionen** haben keinen Namen und keine Liste; man öffnet sie durch Hineinzoomen oder die
  Übersichtskarte, gemerkte Ausschnitte erscheinen als Messingrahmen. Ein Rechteck aufziehen
  („Ausschnitt wählen“) gibt es nicht. Beim Mitwandern stockt das Bild kurz (0,4–1 s).
- **Rückgängig** gilt je Sitzung; nach einem Neustart beginnt der Verlauf neu (Weltstand bleibt).
- **Überlappende Kontinente** werden nur gemeldet (Statuszeile); auf dem Globus gilt das höhere
  Land, in der Landschaft zeigt jeder Kontinent nur sich selbst.
- **Übergang zwischen Stufen** ist ein Wechsel, kein fließender Zoom (Daten sind dafür bereit).
- Die gröbere Umgebung um einen Ausschnitt ist sichtbar gröber (Ring im Hintergrund).

## Ungeprüft

- Sehr viele Kontinente (geprüft: 2; vorgesehen sind über 2.000) und sehr lange Strichlisten
  (Leistung). Trackpad-Bedienung, MacBook (laut Absprache nicht vorrangig).
- Bedienung von Hand über längere Zeit (alle Prüfungen sind automatische Mausabläufe plus
  Bildkontrolle; die Bedienwege sind dieselben).
- Sehr kleine oder sehr große Planeten in Kombination mit großen Kontinenten (Verzerrung der
  mittabstandstreuen Abbildung über ~3.000 km).

## Bestand und Guthaben

Higgsfield in diesem Auftrag: **4 Bilder, 8 Guthaben** (561,85 → 553,85; Grenze 400):
Nadelzweig-Atlas, dunklerer Laubatlas, Kronendach Laubwald und Nadelwald (Luftbild, nahtlos).
Protokoll mit Anweisungen in `assets/target/source/generated.json`. Nadelbäume per
Blender-Skript (`tools/blender/make_target_assets.py`, fester Ausgangswert).

## Unabhängige Prüfung

Zwei Prüfrunden mit getrennten Prüfern und Gegenprüfung. Runde 1: 18 bestätigte Befunde,
alle behoben (u. a. Schutz gegen ältere Erzeugung, Live/Neuberechnung bei Land und Ebene,
abgebrochenes Ziehen, Name beim falschen Kontinent, Ersatzdatei nach Beschädigung). Runde 2:
siehe Abschnitt unten.
