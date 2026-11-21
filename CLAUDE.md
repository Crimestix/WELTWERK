# Weltwerk

Arbeitsname, noch nicht sicher. Visueller Kampagneneditor für Pen & Paper (D&D 2024, Welt
„Elaris“). Ein Nutzer: der Spielleiter.

## Die Idee
- Welten bauen vom Globus bis hinunter ins Haus – so weit hineinzoomen wie möglich.
- Sehr hohe grafische Qualität: „extrem schöne Welten, die intelligent sind“.
- Straßen zeichnen, Dinge direkt mit Informationen belegen. Gefühl wie ein Aufbau- oder
  Städtebauspiel.
- Vorbilder: Level-Editor von Baldur's Gate, Stronghold, Weltenbau in der Unreal Engine,
  **Menyr** (Worldbuilding- und VTT-Programm von NOG Studio – nicht Manor Lords; 21. 11. 2026).
  Minecraft für kreative Freiheit, Planet Zoo für die Landschaftsansicht.
- Sandbox Worldbuilder: Schon das Landschaftsbauen soll spielerisch Freude machen – formen,
  ausprobieren, hineinzoomen, weiterbauen. Auftrag und Ablauf: `docs/PLAN.md`.
- Später: Anbindung an Wayfarer, den digitalen Spielleiterschirm des Spielleiters (Kampagne =
  Ordner mit JSON-Dateien). Vorerst ignorieren (Entscheidung des Spielleiters, 21. 11. 2026:
  „Ignoriere aktuell noch Wayfarer“) – erst das Werkzeug selbst.

## Technik (entschieden, 21. 11. 2026)
- Godot 4.7.2 stable, normale Fassung (ohne .NET). GDScript, Renderer Forward+.
- Projekt in `D:\WELTWERK`, privates GitHub-Repository `Crimestix/WELTWERK`.
- **Zielgerät ist vorerst nur der Windows-PC** (RTX 2070 Super; Entscheidung des Spielleiters,
  21. 11. 2026: „Macbook ist erstmal egal – nur wichtig für den Windows-Rechner“). Leistung
  trotzdem mitdenken; Trackpad-Bedienung bleibt drin, wird aber nicht vorrangig gepflegt.
- **Testfenster nie auf dem Hauptbildschirm** (Wunsch des Spielleiters, 21. 11. 2026): Godot mit
  `--position 2000,60` starten (rechter Bildschirm; Hauptbildschirm liegt bei 0,0, 1920×1080).
- Higgsfield-Programm: `%LOCALAPPDATA%\Programs\higgsfield\higgsfield.exe` (Windows-Fassung,
  nicht im Systempfad; angemeldet). Für Referenzbilder, Atlanten, Texturen und 3D-Modelle
  (Multi-Image to 3D ≈ 30 Guthaben, Bild ≈ 2). Erzeugung über `tools/higgsfield_assets.ps1`,
  jede Anweisung wird protokolliert; Kosten im Bericht festhalten.
- Bezeichner englisch; alle sichtbaren Texte deutsch, klare ganze Wörter, kein
  Entwicklerjargon, deutsche Regelbegriffe.

## Grundsätze
- **Geschichte und Welt schreibt der Spielleiter** – nie eine KI, nie das Programm. Keine
  mitgelieferten Beispielinhalte.
- **Fester Zufall:** Prozedurales (Gelände, Bewuchs, Beiwerk) entsteht nach festen,
  wiederholbaren Regeln. Immer ein eigener `RandomNumberGenerator` (bzw. `FastNoiseLite`) mit
  festem Ausgangswert über `src/domain/fixed_random.gd`, nie die globalen `randi()`/`randf()`/
  `randomize()`. Gleicher Ausgangswert → gleiches Ergebnis. Erzeugtes ist als solches
  erkennbar und lässt sich von Hand übersteuern.
- **Nie erzeugt** wird, was für die Geschichte wichtig ist: Handlung, bedeutende Personen und
  Orte, Geheimnisse.
- **Nie einschränken, nur Hinweise:** Vorlagen und Einordnungen helfen, filtern aber nie etwas
  weg; es bleibt immer ein freier Weg.
- **Geschichte zuerst:** Man muss nicht erst die ganze Welt bauen; Dinge dürfen als
  Platzhalter entstehen und später fertig werden.
- **Fachlogik getrennt:** reine Funktionen in `src/domain/` (ohne Szenen, ohne Knoten), mit
  Tests in `tests/`. Szenen und Oberfläche rufen sie nur auf.
- **Nie einchecken:** Spielstände, Kampagnen, Backups, Schlüssel.

## Aussehen
Oberfläche wie Wayfarer: Dark Fantasy – geschwärztes Holz, Leder, angelaufenes Messing als
Akzent, Pergament als Schrift, Blutrot nur für Gefahr. Schriften: Cormorant Garamond (Namen,
Überschriften), Cinzel (Versalien für Etiketten), Crimson Pro (Fließtext) – noch nicht im
Projekt. Ein hochwertiges Werkzeug aus der Spielwelt, kein Admin-Dashboard.

## Antworten des Spielleiters (21. 11. 2026)
1. **3D** als räumliche Grundlage, **feste angewinkelte Kamera**. Globus und Landschaften haben
   echte Geometrie und Höhe. Beim Landschaftsbau nur verschieben und zoomen, nicht drehen.
   Hochwertig und natürlich, Blick wie in modernen Aufbauspielen. Siedlungen und Gebäude sind
   spätere Ausbaustufen.
2. **Flüssiges Zoomen** ist das Ziel: vom Globus in Kontinente und immer kleinere
   Landschaftsausschnitte. Dahinter dürfen Detailstufen und nachgeladene Bereiche liegen. Alle
   Maßstäbe gehören zu **derselben Welt**: Eine Region übernimmt die vorhandene Geografie; ihre
   Änderungen erscheinen beim Herauszoomen passend vereinfacht. Die Datenstruktur muss von
   Anfang an dafür ausgelegt sein.
3. **Zunächst ein kleiner, zusammenpassender Landschaftsbestand:** Geländeoberflächen, Wasser,
   Felsen, Vegetation – gemeinsame Bildsprache. Aus Paketen oder eigener Produktion; konkrete
   Pakete erst nach einem **sichtbaren Stiltest** wählen. Häuser, Möbel, Figuren zurückgestellt.
4. **„Intelligent“** = nachvollziehbare räumliche Zusammenhänge und Arbeitserleichterung, z. B.:
   Ein platzierter Kontinent kennt Größe und Lage auf dem Globus · Klima wird aus
   Planeteneinstellungen, Lage und Gelände abgeleitet und ist von Hand anpassbar · Wälder als
   Fläche malen, Bäume nach einstellbaren Regeln verteilt · Flüsse folgen dem Gefälle, bewusste
   Ausnahmen bleiben möglich · eine vertiefte Region übernimmt Küste, Höhen, Gewässer und
   Vegetationsflächen · neue Erzeugung erhält festgesetzte Bereiche und Handänderungen.
5. **Freies Formen und Erzeugung ergänzen sich.** Schwerpunkt zuerst Landschaftsbau: Land
   hinzufügen und abtragen, Gelände erhöhen und glätten, Gewässer zeichnen, Vegetation
   verteilen. Erzeugung liefert Ausgangspunkt oder Details; alles bleibt bearbeitbar. Schon
   das Gestalten soll spielerisch Freude machen.
6. **Wayfarers Editoren bleiben vorerst.** Weltwerk ist ein eigenständiges Programm; langfristig
   soll seine Welt über Wayfarer am Spieltisch nutzbar werden. Was ersetzt wird, entscheidet
   sich an tatsächlich funktionierenden Abläufen. Keine Migration im ersten Abschnitt.
7. **Weltwerk führt die Geografie** einer dort erschaffenen Welt (Gelände, Positionen,
   Maßstäbe, räumliche Zugehörigkeiten). Wayfarer führt den Kampagnenverlauf (Gruppenposition,
   Zeit, Besuche, Ereignisse). Gemeinsame Orte brauchen stabile Identitäten und einen
   ausdrücklich festgelegten Austausch. Namen und Beschreibungen nur einmal pflegen – die
   Zuständigkeit dafür vor der Integration festlegen.

## Bildideen (21. 11. 2026)
Vier Konzeptbilder (`docs/referenz/*_konzept.webp`; Kontinentalreferenz: `kontinent_konzept.webp`): Globus mit Breitengraden und „Kontinent platzieren“
(Größe, Breitengrad, Ausrichtung, „Klima aus Lage“) · Landform von oben (Land hinzufügen,
Land abtragen, Küste glätten, Pinselgröße in km) · Kontinent schräg von oben (Gebirge, Wald,
Fluss, See; „Bereich vertiefen“ → Region, „Landschaft wird übernommen“) · Region nah
(Erhöhen, Glätten, Wasser, Wald, Felsen, Wiese; „Wald malen“ mit Dichte, Größe, Abstand zu
Wasser; Übersichtskarte; „Aus Kontinent übernommen“). Laut Spielleiter **sitzt der grafische
Stil der Karten sehr gut**: kräftiges Gelbgrün, ockerfarbene Trockenflächen, felsige Gebirge
mit Schnee, Sandstrände, türkisfarbenes Flachwasser über tiefem Blau, natürliche Beleuchtung.
Bedienung dort: Werkzeugleiste links, Pfad oben (Welt / Kontinent / Region), Rückgängig,
„Gespeichert“, Pinselkreis mit Einstellungen.

## Noch offen (Stand 21. 11. 2026, Einzelheiten docs/BERICHT_KONTINENTEDITOR.md)
- Kartenbild noch ruhiger als die Referenz (Kleinrelief, verästelte Gewässer, Fjorde).
- Flüssiger Übergang zwischen Maßstäben (heute Wechsel; Daten sind dafür bereit).
- Erzeugte Grundform als bearbeitbare Form; Gelände folgt beim Formziehen erst beim Loslassen.
- Regionen mit Namen und Liste, Rechteck aufziehen; Flüsse, die sich selbst einen Weg suchen.
- Überlappende Kontinente nur gemeldet, nicht zusammengeführt; Rückgängig gilt je Sitzung.
- Schriften (Cormorant, Cinzel, Crimson Pro) noch nicht im Projekt.

## Bestand und Lizenzen
- Fremdbestände nur mit klarer Lizenz; Herkunft, Lizenz, Urheber und Größe in `docs/STILTEST.md`
  bzw. `assets/external/polyhaven/sources.json` festhalten. Poly Haven = CC0.
- Große Downloads nicht einchecken (`assets/external/` ist ausgeschlossen); stattdessen ein
  Ladeskript (`tools/fetch_polyhaven.ps1`). Eigene Blender-Bestände per Skript
  (`tools/blender/`), mit festem Ausgangswert, Ergebnis klein genug fürs Repository.
- Laubmodelle nicht mit Godots automatischer Vereinfachung (LOD) importieren – sie rechnet
  Blätter weg. Normalenkarten beim Import als solche markieren (`tools/run_style_test.ps1`).

## Weltmodell (Kurzfassung, Einzelheiten in `docs/PLAN.md`, `docs/ENTWURF_KONTINENTE.md`)
- `WorldDocument` = Planet (Radius bis doppelte Erde) + beliebig viele Kontinente mit **fester
  ID** (Name, Grundform `generated`/`drawn`, Lage, Größe, `base_size_km`, Ausgangswert,
  `scatter_seed`, Klima-Anpassung, **Strichliste**, gemerkte Regionen). Befehle verweisen auf die
  ID, nie auf den Listenplatz; Planetwerte über `WorldDocument.PLANET`. Jede Änderung ist ein
  Befehl → Rückgängig/Wiederholen. Gespeichert wird nur dieser Stand (JSON, volle Genauigkeit,
  `.bak`; beschädigte Datei → `.defekt`, nie überschrieben); alles Abgeleitete wird neu berechnet.
- Striche: Pinsel, Formen (`shape_add`/`shape_remove`), Erzeugung (`gen_*`, eigener Ausgangswert,
  
- `TerrainSampler` = die eine Auswertungsfunktion: Erzeugung (nur so fein wie das Raster) plus
  Striche → `TerrainWindow` (Ausschnitt: Höhe, Wald, Bearbeitungsmarken). Kontinentkoordinaten
  in Metern, 64 Bit, x = Osten, y = Norden.
- Ansichten sind Fenster (Mitte, Größe); „Vertiefen“ = 1/8. Darstellung auf 1000 Einheiten
  normiert, grobe Ansichten überhöht (nur Darstellung).
- Packed-Arrays fremder Objekte nie elementweise beschreiben (`w.feld[k] = …` kopiert jedes Mal
  das ganze Feld): lokal holen, ändern, einmal zurückweisen.

## Aufbau
- `project.godot` – Projekteinstellungen, Tastenbelegung (`[input]`).
- `scenes/editor.tscn`, `src/editor/` – **der Editor (Startszene)**: `editor.gd` (Ablauf,
  Maßstäbe, Speichern, Vorführmodus), `landscape_view.gd` (Ausschnitt, Malen, Bäume, Umgebung),
  `globe_view.gd`, `editor_ui.gd`, Shader `landscape`/`globe`.
- `src/domain/world/` – Weltmodell: `world_document.gd`, `terrain_sampler.gd`,
  `terrain_window.gd`, `stroke.gd`, `climate.gd`, `globe_math.gd`.
- `scenes/main.tscn` – erster Schritt (einzelne Insel), nur noch zum Vergleich.
- `scenes/lighting.tscn` – gemeinsames Licht (Himmel, Sonne, Nebel) für alle Szenen.
- `scenes/style_test.tscn`, `src/style_test/` – Stiltest A/B/C (`docs/STILTEST.md`).
- `scenes/target_scene.tscn`, `src/target/` – Zielszene und gemeinsamer Zielstil:
  `target_materials.gd` (Bäume, Felsen, Büsche, Gras – auch vom Editor genutzt),
  `meadow.gdshaderinc` (eine Wiesenfarbe für Boden und Gras), `water_clear.gdshader`,
  `rock_granite.gdshader`, `grass_cards.gdshader`, `target_landscape.gd` (Landschaft, rein).
- `src/editor/landscape_detail.gdshader` – Editor-Boden im Zielstil (Ausschnitte bis 4,2 km).
- `src/editor/landscape.gdshader` – Kartenbild grober Ausschnitte (bikubische Schummerung, Wald als
  Dichte, Muster in festen Metern); `sea.gdshader` (Meer/Seen nach Tiefe, Küstenschein),
  `river.gdshader` (Flüsse als Bänder).
- `src/editor/shape_editor.gd` + `src/domain/world/shape_edit.gd` – Werkzeug „Formen bearbeiten“
  (Wählen, Verschieben, Punkte, Skalieren, Drehen, Löschen; Befehle replace/remove_stroke).
- `src/editor/editor_ui.gd` – Oberfläche: Gruppenleiste links, Werkzeugleiste unten, Einstellungen
  erst nach Wahl, Hinweiszeile, Maßstab, Übersichtskarte; Symbole in `assets/ui/icons/*.svg`.
- `src/editor/comparison_run.gd` (`--vergleich`), `recording_run.gd` (`--aufnahme`) – Vergleich mit
  der Kontinentalreferenz und aufgezeichneter Bedienablauf.
- `docs/BERICHT_KONTINENTE.md` – Bericht des Kontinent-Auftrags; `docs/abnahme/`, `docs/stufen/` Bilder.
- `tools/profile_window.gd` – Auswertungszeit eines Ausschnitts je Bearbeitung messen.
- `assets/target/` – Zielbestand (Blender-Skript + Higgsfield; Originale und Protokoll in
  `assets/target/source/`, nur `generated.json` im Repository).
- `tools/` – Ladeskript Poly Haven, Blender-Skripte, Stiltest-Messlauf.
- `docs/` – Plan, Stiltest-Bericht (für Godot ausgeblendet per `.gdignore`).
- `src/domain/` – reine Fachlogik: `fixed_random.gd` (fester Zufall), `heightfield.gd`
  (Höhenfeld: Erzeugung, Höhe an Punkt, Strahl trifft Gelände).
- `src/world/` – Darstellung der Welt: `terrain.gd` (Netz aus dem Höhenfeld, Wasser),
  `terrain.gdshader`, `water.gdshader`.
- `src/camera/strategy_camera.gd` – Kamera wie im Aufbauspiel.
- `src/ui/` – Oberfläche (`controls_help.gd`).
- `tests/` – Tests der Fachlogik.

## Steuerung (Kamera)
Fester Blickwinkel, kein Drehen. Verschieben: W A S D / Pfeiltasten, rechte oder mittlere
Maustaste ziehen, Trackpad mit zwei Fingern. Zoomen: Mausrad (zum Mauszeiger hin), + / −,
Trackpad Finger spreizen oder Strg/Befehl + zwei Finger. Umschalt = schneller, Pos1 =
Übersicht. Am Zoom-Anschlag weiterzoomen wechselt den Maßstab (hinein: Ausschnitt 1/8 unter
dem Mauszeiger; hinaus: gröber, zuletzt Globus). Malen: Werkzeug wählen, linke Maustaste.
Rückgängig Strg/⌘+Z, Wiederholen Strg/⌘+Y oder Strg/⌘+Umschalt+Z.

## Befehle
Godot liegt auf dem Windows-PC unter
`C:\Users\Mattes\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.

```powershell
$godot = "C:\Users\Mattes\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path D:\WELTWERK --import                                 # Klassen/Importe auffrischen
& $godot --headless --path D:\WELTWERK --script res://tests/run_tests.gd        # Tests
& $godot --path D:\WELTWERK                                                     # starten
& $godot --path D:\WELTWERK -- --screenshot=C:\pfad\bild.png                    # Bild speichern, beenden
& $godot --position 2000,60 --path D:\WELTWERK -- --demo=D:\WELTWERK\docs\nachweis  # Nachweis vorführen (Bilder, Messwerte)
& $godot --path D:\WELTWERK -- --welt=C:\pfad\welt.json --screenshot=C:\pfad\b.jpg  # andere Weltdatei, Bild
& $godot --path D:\WELTWERK -- --neu                                            # leere Probewelt (user://welt_neu.json)
& $godot --position 2000,60 --path D:\WELTWERK -- --abnahme=D:\WELTWERK\docs\abnahme --schritt=1  # Abnahme, dann --schritt=2
& $godot --position 2000,60 --path D:\WELTWERK -- --welt=<welt.json> --stufen=<ordner> [--richtung=250]  # Bildreihe aller Stufen
& $godot --position 2000,60 --path D:\WELTWERK -- --vergleich=<ordner>    # gleicher Umriss wie die Referenz, Bilder + Prüfungen
& $godot --position 2000,60 --path D:\WELTWERK --write-movie <film.ogv> --fixed-fps 30 -- --aufnahme=<ordner>  # Bedienablauf filmen
& $godot --path D:\WELTWERK res://scenes/style_test.tscn                         # Stiltest
powershell -ExecutionPolicy Bypass -File tools\run_style_test.ps1                # Stiltest messen
```
Weltdatei: `user://welt.json` (Windows `%APPDATA%\Godot\app_userdata\Weltwerk\welt.json`).

## Entscheidungen
- 21. 11. 2026 – Technik wie oben; erster Schritt: Gelände mit Sonne, Himmel, Schatten und
  Aufbauspiel-Kamera (fester Winkel 52°, verschieben und zoomen). Gelände vorerst als ein
  einzelnes Höhenfeld (Insel, 400 m × 400 m, 1 m Raster) ohne Texturen – Farbe nach Neigung
  und Höhe im Shader, an den Bildideen ausgerichtet. Das ist ein Platzhalter: Weltmodell für
  Globus → Region und Stiltest kommen danach.
- 21. 11. 2026 – Fester Zufall über Godots `RandomNumberGenerator`/`FastNoiseLite` mit festem
  Ausgangswert (`FixedRandom`), Teil-Ausgangswerte per `FixedRandom.derive(wert, "Bezeichnung")`.
  Keine Übernahme aus Wayfarer (dort mulberry32/FNV-1a) – gleiche Zahlen wie Wayfarer sind
  erst bei der späteren Anbindung zu klären.
- 21. 11. 2026 – Plan des Spielleiters übernommen (`docs/PLAN.md`, Annahmen A1–A7). Weltmodell
  „Erzeugung + Strichliste in Kontinentmetern“, Ansichten als Fenster mit Faktor 8,
  Bearbeitungen in gröberen Ansichten vereinfacht und – wo zu klein – messingfarben markiert.
  Standardgröße eines neuen Kontinents 1.600 km. Kein Name wird erzeugt.
- 21. 11. 2026 – **Zielbild bestätigt** (Spielleiter: „Das hier ist definitiv das Ziel“):
  `docs/stiltest/zielbild_higgsfield.jpg` – sonnige Hügelwiese mit einzelnen Laubbäumen
  (sichtbare Stämme, lockere Kronen), Wildblumen und Halme, flechtige Granitbänke am Ufer,
  klares Wasser mit sichtbaren Steinen, türkis zu tiefblau, warmes Licht. Weg dorthin:
  Stiltest-Variante C (Blattkarten-Bäume, Higgsfield-Laub, Poly-Haven-Gelände mit Farbanpassung).
- 21. 11. 2026 – Kontinent skalieren: **„Alles wächst mit.“** (Spielleiter) – Befehl `resize`.
- 21. 11. 2026 – Auftrag „arbeite, bis wir beim Zielbild sind; nutze Higgsfield-Guthaben wie
  nötig“. Ergebnis: Zielszene (`scenes/target_scene.tscn`, Bericht `docs/ZIEL.md`) und
  Übertragung in die feinsten Editor-Ausschnitte. Die Editor-Kamera wird beim Hineinzoomen
  flacher (52° → 30°, nur zoomabhängig, nicht drehbar) – sonst wirken Gras und Bäume von oben
  wie Striche. Spielleiter hat 500 Higgsfield-Guthaben nachgelegt (Stand danach 561,85).
- 21. 11. 2026 – Auftrag Kontinente (6–7 Stunden, bis 400 Higgsfield-Guthaben). Entscheidungen des
  Spielleiters: **Planetengröße anpassbar bis doppelte Erde**; **Anzahl der Landmassen auf dem
  Globus nicht begrenzen** (umgesetzt: 8 × 8 Kontinente je Texturebene, über 130.000).
  Routineentscheidungen: neue Welt startet leer auf dem Globus; Kontinentfenster begrenzt das
  Land (weicher Rand); Schutz wirkt gegen Erzeugung erst ab seiner Stelle in der Strichliste;
  Bäume streuen nach eigenem Ausgangswert (bleiben bei neuer Variante); Wiese und Wald auf
  mittleren Stufen in echten Metern (Kronendach-Luftbild); letzte Ansicht wird gemerkt (eigene
  Datei neben der Welt). Ausgegeben: 8 Guthaben (Stand 553,85). Bericht `docs/BERICHT_KONTINENTE.md`.
- 21. 11. 2026 – Auftrag „Kontinenteditor ausarbeiten“ (Abnahmeziel: angenehm gestalten, Übersicht
  wie eine hochwertige Fantasykarte). Routineentscheidungen: Kontinentebene mit 513er Raster; aus der
  Ferne schmaler Bildwinkel (28°) und Neigung 55°; Überhöhung höchstens 7; Gewässer als eigene
  Flächen; Schutzschraffur nur beim Werkzeug „Schützen“; gezeichnete Umrisse werden vereinfacht;
  jedes Werkzeug merkt sich seine Größe; Gebirge folgt dem Strich als Kette; gezeichnete Kontinente
  ohne eigene Gebirge in der Grundform. Higgsfield nicht genutzt. Bericht `docs/BERICHT_KONTINENTEDITOR.md`.
