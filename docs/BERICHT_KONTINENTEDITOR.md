# Zwischenstand: Kontinenteditor ausgearbeitet (21. 11. 2026)

Abnahmeziel: Ein Kontinent lässt sich angenehm gestalten, seine Übersicht wirkt wie eine
hochwertige, gut lesbare Fantasykarte. Maßstab war das eigene Konzeptbild
„Kontinent schräg von oben“ (`docs/referenz/kontinent_konzept.webp`).

## Ansehen

| Was | Datei |
| --- | --- |
| Vorher: Referenz links, Editor rechts | `docs/vergleich/v00_vorher.jpg` |
| Nachher: gleicher Umriss, gleiche Ansicht | `docs/vergleich/v01_nachher.jpg` |
| Kontinent allein, nah | `docs/vergleich/v01_nachher_kontinent.jpg`, `v01_nachher_nah.jpg` |
| Gewählte Landform mit Anfasspunkten | `docs/vergleich/v01_form_gewaehlt.jpg` |
| Film des Bedienablaufs (81 s, Ogg/Theora, z. B. mit VLC) | `docs/aufnahme/bedienablauf.ogv` (nicht im Repository, 28 MB) |
| Standbilder aus dem Film | `docs/aufnahme/bedienablauf_standbilder.jpg` |

```powershell
$godot = "C:\Users\Mattes\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
& $godot --path D:\WELTWERK                                                   # Editor
& $godot --position 2000,60 --path D:\WELTWERK -- --vergleich=C:\pfad\ordner     # Vergleich mit der Referenz
& $godot --position 2000,60 --path D:\WELTWERK --write-movie C:\pfad\film.ogv --fixed-fps 30 -- --aufnahme=C:\pfad\ordner
```

## Was sich geändert hat

**Kartenbild (Kontinent und grobe Regionen)**
- Doppelt so feines Raster auf Kontinentebene (513 Punkte); Licht und Schummerung aus glatt
  gefilterten Höhen – keine Facetten, Treppen oder Rasterkästchen mehr.
- Wald als Dichte: geschlossen, wo dicht; locker als Haine und Lichtungen, ausgefranste Ränder
  (statt der Tarnflecken). Wiesen nach Feuchte (Täler grüner), Hochland olivbraun, Fels auf Graten
  und steilen Flanken, Schnee auf Kämmen, schmaler Strand an Küsten.
- Meer: Farbe nach echter Tiefe, türkiser Schein entlang der Küsten, matt statt blendend.
- Flüsse als glatte Bänder (zur Mündung breiter, nie unlesbar schmal), Seen als ebene
  Wasserfläche auf ihrem Spiegel – keine Stufenwände und kein Kraterwall mehr.
- Ansicht beim Öffnen auf das Land eingepasst; aus der Ferne schmaler Bildwinkel wie eine Karte.
- Übersichtskarte in denselben Farben, mit Schummerung.

**Ursache der Streifen und Kanten (untersucht)**
- Die schrägen Streifen waren die Schraffur geschützter Flächen – jetzt nur beim Werkzeug
  „Schützen“ sichtbar.
- Treppen an Flüssen und Seen: Wasser wurde je Rasterpunkt angehoben. Jetzt eigene Flächen.
- Kantige Berge: grobes Raster, Licht aus groben Normalen, Gebirgsrauschen mal runder Pinsel.
  Jetzt feineres Raster, glatte Normalen und ein neuer Gebirgsgenerator.
- Kästchen im Wald- und Wiesenmuster: Wertrauschen auf Gitter. Jetzt gedrehtes Gradientenrauschen.

**Natürliche Geländeformen** (`terrain_sampler.gd`)
- „Gebirge“ folgt dem gezogenen Strich als Kette: Hauptkamm mit Gipfeln und Pässen,
  Seitengrate mit Tälern, Vorberge am Rand. Gleicher Ausgangswert → gleiche Kette.
- Hügelland weich gewellt, Inseln als Archipel, Wald mit unregelmäßigen Rändern.
- Erzeugte Grundform: buchtenreiche Küste, lange Gebirgsgürtel statt runder Flecken, Hochebenen.
  Gezeichnete Kontinente haben eine ruhige Grundlage (flache Hügel) – Gebirge setzt man selbst.
- Gezeichnete Küsten bekommen natürliches Küstendetail; Seen und Flüsse sanfte Ufer.
- Neuberechnung nach einer Bearbeitung schneller (Grundform zwischengespeichert): ≈ 0,8 s statt 1,2 s.

**Landformen nachträglich ändern** (neues Werkzeug „Formen bearbeiten“ in der Gruppe Form)
- Klick wählt die Form (Umriss und Anfasspunkte); Ziehen verschiebt; Punkt ziehen formt um
  (Nachbarpunkte folgen weich, Alt: nur der Punkt); Doppelklick auf den Rand fügt einen Punkt
  ein; Entf löscht Punkt oder Form; Umschalt + Mausrad skaliert, Strg + Mausrad dreht; Esc.
- Jede Änderung ist genau ein Rückgängig-Schritt und wird gespeichert. Gezeichnete Umrisse werden
  beim Loslassen vereinfacht, damit die Punkte handlich bleiben.

**Bedienung**
- Links eine schmale Leiste mit fünf Gruppen (Ansehen, Form, Gelände, Wasser, Bewuchs); die
  Werkzeuge der Gruppe erscheinen unten. Einstellungen (nur die passenden Regler) erst nach Wahl
  eines Werkzeugs; jedes Werkzeug merkt sich Größe und Stärke.
- Eine dezente Hinweiszeile, die verblasst; Meldungen erscheinen kurz am selben Ort.
- Pfad oben nur „Welt / Kontinent / Region“ (keine Kette 1:8 / 1:64), in Regionen „‹ Kontinent“.
- Orientierung: Maßstabsleiste, Übersichtskarte mit Nordpfeil; technische Angaben als Hinweis
  beim Maßstab und beim Kontinentnamen statt in einer Statuszeile.
- Globus: Feld „Kontinent platzieren“ (Größe, Breite, Länge, Ausrichtung als Drehscheibe, Klima
  aus Lage aufklappbar), „Kontinent bearbeiten“, „Löschen“; „Planet einstellen“ unten links.

## Geprüft

- 68 Tests der Fachlogik bestanden (neu: Formen bearbeiten, Gebirgskamm, Gleichheit Live-Malen
  und Neuberechnung für alle Erzeuger, Zwischenspeicher).
- Vergleichsablauf mit echten Mausereignissen: 24/24 Prüfungen – Umriss gezeichnet, alle
  Werkzeuge, Punkt ziehen macht Meer zu Land, Verschieben, Skalieren, Punkt einfügen/löschen,
  Bucht löschen, jeweils Rückgängig, im vertieften Ausschnitt, Wiederholen, gespeichert = geladen.
- Bisherige Abnahme mit Neustart: Schritt 1 20/20, Schritt 2 11/11.
- Aufnahme: alle Schaltflächen über die Oberfläche gefunden und geklickt, Form durch Ziehen
  verändert, Rückgängig/Wiederholen.
- Bildrate (RTX 2070 Super, 1440 × 900): Kontinent ≈ 200, Regionen 210–260, feinster Ausschnitt 135.
- Drei unabhängige Prüfungen der Arbeitsstränge; alle Befunde behoben (Wahl folgt der Form bei
  Rückgängig, Entf prüft den Punkt unter dem Zeiger, Maßstab in Bodenhöhe, Flussbreite).

## Verbleibende Abweichungen von der Referenz (ehrlich)

- **Gesamteindruck:** Die Referenz ist ein gemaltes Bild mit sehr feinem Detail auf jedem
  Bildpunkt. Unsere Karte ist deutlich ruhiger: weniger Kleinrelief, Wald und Wiese stilisiert.
  Das Grün ist heller und gelblicher, große Flächen wirken noch etwas gleichförmig.
- **Gebirge** sind schmaler und weniger zerklüftet als die breiten Gebirgslandschaften der
  Referenz; eine Kette endet rund statt auszulaufen. Wo sich zwei Striche überlagern, entsteht eine
  große Schneekappe.
- **Gewässernetz:** Die Referenz zeigt verästelte Flüsse und Fjorde. Bei uns gibt es nur
  gezeichnete Flüsse (folgen dem gezogenen Lauf, suchen keinen eigenen Weg); Fjorde muss man von
  Hand wegschneiden. Seen sind rund.
- **Landformen:** Ein einzeln weit herausgezogener Punkt ergibt nur eine schmale Landzunge (der
  weiche Küstenrand ist auf Kontinentebene etwa 19 km breit). Während des Ziehens wird nur der
  Umriss gezeigt, das Gelände folgt beim Loslassen (≈ 0,8 s). Erzeugte Grundformen lassen sich
  noch nicht als Form anfassen.
- **Bedienung:** Schriften noch Godot-Standard (Cormorant, Cinzel, Crimson Pro fehlen); Gruppen
  links nur mit Hinweistext, ohne Beschriftung; das Globusfeld hat keinen Bildlauf für sehr kleine
  Fenster.
- **Film:** In Godots Filmaufnahme läuft jedes Bild in fester Zeit – Rechenpausen sind im Film
  nicht zu sehen (gemessen: Umriss bis fertiges Land etwa 1 s, jede Formänderung ≈ 0,8 s). Die
  gemäßigte Breite (42° N) wird zu Beginn ohne Mausbewegung gesetzt.
- **Weltdateien:** Die Grundform wird jetzt anders erzeugt. Bestehende Welten sähen anders aus
  (Seen und Flüsse speichern feste Spiegelhöhen). Eine eigene Welt gibt es noch nicht, daher
  betrifft das nur Probewelten.
- Ungeprüft: Bedienung von Hand über längere Zeit, Trackpad, sehr lange Strichlisten.

Higgsfield in diesem Abschnitt: nicht genutzt (0 Guthaben).
