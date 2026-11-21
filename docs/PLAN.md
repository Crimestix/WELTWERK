# Technischer Plan (Stand 21. 11. 2026)

Kurzfassung des Auftrags „Sandbox Worldbuilder“ und Abgleich mit dem, was es schon gibt.
**A1, A2 …** sind Annahmen: Ich habe sie selbst getroffen, und sie lassen sich ändern.

## Abgleich

| Auftrag | Stand | Nächster Schritt |
|---|---|---|
| Godot, 3D, feste Schrägkamera, verschieben und zoomen | vorhanden (erster Schritt) | Kamera für jede Ansicht wiederverwenden |
| Stiltest: dieselbe Szene als A (vorhandener Bestand) und B (Blender), Arbeits- und Nahansicht, Herkunft, Aufwand, Messwerte | fehlt | **jetzt** (`scenes/style_test.tscn`, Bericht in `docs/STILTEST.md`) |
| Landform → Globus → Kontinent → vertiefter Ausschnitt | fehlt | **jetzt**, als kleiner Nachweis |
| Rückgängig/Wiederholen, Speichern, wiederholbare Erzeugung | nur feste Erzeugung | **jetzt**, im Nachweis |
| Flüssiger Übergang zwischen Maßstäben | fehlt | im Aufbau berücksichtigt (A3), gebaut wird er später |
| Festsetzen, Konfliktanzeige, Import, Flüsse am Gefälle | fehlt | nach dem Nachweis |
| Leistung auf dem MacBook Air | nicht gemessen | Messung im Programm vorhanden, Lauf auf dem Mac steht aus |

## Weltmodell

- **Ein Weltstand** = Planeteinstellungen + Kontinente. Ein Kontinent besteht aus
  1. seiner **Lage** auf dem Globus (Breite, Länge, Ausrichtung, Größe in km),
  2. einem **Ausgangswert** für die Erzeugung (Grundform, Höhen, Bewuchs) und
  3. einer geordneten **Liste von Bearbeitungen** (Pinselstriche: Land hinzufügen/abtragen,
     erhöhen/senken, glätten, Wald, Wasser), gespeichert in **Kontinentkoordinaten in Metern**.
- **Eine Auswertungsfunktion** liefert für einen beliebigen Punkt und eine Auflösung Höhe,
  Landanteil, Wald und Wasser. Sie nimmt die Erzeugung (nur Rauschanteile, die zur Auflösung
  passen) und legt die Bearbeitungen darüber.
- Daraus folgt:
  - Herauszoomen zeigt Detailarbeit **automatisch vereinfacht**: dieselben Striche,
    gröber abgetastet.
  - Hineinzoomen **übernimmt** Küste, Höhen, Wasser und Wald. Es ist dieselbe Funktion, nur feiner.
  - **Rückgängig/Wiederholen** heißt: einen Strich entfernen oder zurücklegen. Abgeleitetes
    (Baumverteilung, Globusbild, gröbere Ansichten) wird neu berechnet und ist damit immer mit dabei.
  - **Speichern** = Planeteinstellungen + Lage + Ausgangswerte + Strichliste als JSON. Klein, lesbar, verlustfrei.
  - **Wiederholbar**: Die Erzeugung hängt nur vom Ausgangswert ab. Bäume werden je Weltzelle mit
    festem Ausgangswert verteilt und stehen daher in jeder Ansicht an derselben Stelle.
  - **Erzeugung überschreibt Handarbeit nicht**: Eine neue Variante ändert nur die Erzeugung.
    Die Striche bleiben obenauf.

## Annahmen

- **A1 – Kontinent lokal eben.** Kontinentkoordinaten sind eine ebene Abbildung um den
  Kontinentmittelpunkt (mittabstandstreu). Auf dem Globus wird zurückgerechnet. Bei
  Kontinentgröße bis einige tausend km ist die Verzerrung für den Nachweis vertretbar. Später
  kommen Kacheln auf der Kugel.
- **A2 – Bearbeitungen als Striche, nicht als Pixel.** Bei sehr vielen Strichen werden
  Zwischenstände je Kachel zwischengespeichert (später). Für den Nachweis wird alles direkt ausgewertet.
- **A3 – Ansichten als Fenster.** Eine Ansicht ist ein quadratisches Fenster (Mitte, Größe)
  auf dem Kontinent, abgetastet mit 257–513 Punkten je Seite. „Vertiefen“ öffnet ein Fenster mit
  1/8 der Größe. Der spätere flüssige Zoom setzt mehrere solcher Fenster als Kacheln
  verschiedener Feinheit nebeneinander, mit derselben Auswertungsfunktion. Im Nachweis wird
  die Ansicht noch sichtbar gewechselt.
- **A4 – Überhöhung nur in der Darstellung.** In groben Ansichten werden Höhen überhöht
  gezeigt (wie auf den Zielbildern). Die Daten bleiben in echten Metern.
- **A5 – Genauigkeit.** Kontinentkoordinaten sind GDScript-Gleitkommazahlen (64 Bit). Jede
  Ansicht wird um ihren eigenen Ursprung gezeichnet. Das Rauschen arbeitet intern mit 32 Bit:
  Bei bis zu ±1200 km um die Kontinentmitte genügt das (etwa 0,1 m).
- **A6 – Leistung.** Bearbeitungen rechnen die Höhen im Pinselbereich auf der CPU neu und
  laden sie als Höhentextur auf die Grafikkarte. Das Gitter wird im Shader verschoben, nicht
  neu gebaut.
- **A7 – Klima.** Ein einfaches Ableitungsmodell aus Breitengrad und Höhe (Schneegrenze,
  Trockenheit). Im Nachweis ist es von Hand überschreibbar und dient als Hinweis, nicht als Vorgabe.

## Reihenfolge

1. **Stiltest** A/B mit Messwerten → du wählst die Bildsprache.
2. **Nachweis**: Landform (malen, Variante erzeugen) → Globus (Größe, Breite, Länge, Ausrichtung,
   Klima aus Lage) → Kontinent (Gebirge/erhöhen, glätten, Wald, Wasser) → Ausschnitt vertiefen →
   Herauszoomen; Rückgängig/Wiederholen; Speichern und Neustart.
3. **Messung** auf dem MacBook Air (Bildrate, Speicher, Reaktion der Werkzeuge).
4. Danach: flüssiger Zoom (Kacheln), Festsetzen, Konfliktanzeige, Flüsse am Gefälle, Import.
