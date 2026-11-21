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
  nicht im Systempfad; angemeldet). Für Referenzbilder und Texturen; Kosten vorher mit
  `generate cost` prüfen und im Bericht festhalten.
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
Vier Konzeptbilder (nicht im Repository): Globus mit Breitengraden und „Kontinent platzieren“
(Größe, Breitengrad, Ausrichtung, „Klima aus Lage“) · Landform von oben (Land hinzufügen,
Land abtragen, Küste glätten, Pinselgröße in km) · Kontinent schräg von oben (Gebirge, Wald,
Fluss, See; „Bereich vertiefen“ → Region, „Landschaft wird übernommen“) · Region nah
(Erhöhen, Glätten, Wasser, Wald, Felsen, Wiese; „Wald malen“ mit Dichte, Größe, Abstand zu
Wasser; Übersichtskarte; „Aus Kontinent übernommen“). Laut Spielleiter **sitzt der grafische
Stil der Karten sehr gut**: kräftiges Gelbgrün, ockerfarbene Trockenflächen, felsige Gebirge
mit Schnee, Sandstrände, türkisfarbenes Flachwasser über tiefem Blau, natürliche Beleuchtung.
Bedienung dort: Werkzeugleiste links, Pfad oben (Welt / Kontinent / Region), Rückgängig,
„Gespeichert“, Pinselkreis mit Einstellungen.

## Noch offen
- Bildsprache nach dem Stiltest (`docs/STILTEST.md`): Empfehlung Variante C (Blattkarten-Bäume
  mit Higgsfield-Laub, Poly-Haven-Gelände mit Farbanpassung) – Entscheidung des Spielleiters
  steht aus. Der Editor nutzt C-Bäume bereits im feinsten Ausschnitt.
- Kontinentgröße ändern skaliert nur die Grundform, Striche bleiben in Metern – wie soll
  Skalieren mit Handarbeit umgehen?
- Flüssiger Übergang zwischen Maßstäben, Flüsse am Gefälle, Seen über Meereshöhe, Festsetzen,
  Konfliktanzeige, Form zeichnen/importieren, mehrere Kontinente – noch nicht gebaut.

## Bestand und Lizenzen
- Fremdbestände nur mit klarer Lizenz; Herkunft, Lizenz, Urheber und Größe in `docs/STILTEST.md`
  bzw. `assets/external/polyhaven/sources.json` festhalten. Poly Haven = CC0.
- Große Downloads nicht einchecken (`assets/external/` ist ausgeschlossen); stattdessen ein
  Ladeskript (`tools/fetch_polyhaven.ps1`). Eigene Blender-Bestände per Skript
  (`tools/blender/`), mit festem Ausgangswert, Ergebnis klein genug fürs Repository.
- Laubmodelle nicht mit Godots automatischer Vereinfachung (LOD) importieren – sie rechnet
  Blätter weg. Normalenkarten beim Import als solche markieren (`tools/run_style_test.ps1`).

## Weltmodell (Kurzfassung, Einzelheiten in `docs/PLAN.md`)
- `WorldDocument` = Planet + Kontinente (Lage, Ausgangswert, Klima-Anpassung, **Strichliste**,
  gemerkte Regionen). Jede Änderung ist ein Befehl → Rückgängig/Wiederholen. Gespeichert wird
  nur dieser Stand (JSON); alles Abgeleitete wird neu berechnet.
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
- `scenes/style_test.tscn`, `src/style_test/` – Stiltest A/B (`docs/STILTEST.md`).
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
