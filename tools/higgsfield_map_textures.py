# -*- coding: utf-8 -*-
"""Erzeugt die Kartentexturen (Kontinentansicht) mit Higgsfield.

Originale landen in assets/map/source/ (nicht im Repository). Jede Erzeugung wird mit
Anweisung, Auftragsnummer, Adresse, Modell und Guthaben in assets/map/source/generated.json
festgehalten (UTF-8 ohne BOM). KI-Erzeugung ist nicht wiederholbar - das Protokoll haelt fest,
woher jedes Bild stammt. Vorhandene Originale werden nicht neu erzeugt.

Aufruf:  python tools/higgsfield_map_textures.py [name ...]      (ohne Namen: alle fehlenden)
Danach:  python tools/make_seamless_textures.py
Achtung: Ohne Namen werden ALLE fehlenden Bilder erzeugt (je etwa 2 Guthaben).
"""
import datetime
import json
import os
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "assets", "map", "source")
LOG = os.path.join(OUT, "generated.json")
HF = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "higgsfield", "higgsfield.exe")
MODEL = "gpt_image_2_6"

# Gemeinsame Bildsprache: senkrecht von oben, keine Perspektive, gleichmaessiges weiches Licht.
COMMON = (", straight top-down nadir view, orthorectified satellite photograph, no perspective, "
          "no horizon, no sky, no clouds, no roads, no paths, no buildings, no villages, no fields "
          "with straight edges, no text, no labels, no border, natural European temperate landscape "
          "in early summer, soft even daylight from the top left, the pattern is uniform across the "
          "whole square with no single focal point, photorealistic, high detail, fills the whole square")

JOBS = {
    "rock_massif": (
        "Seamless tileable texture of a vast eroded limestone and granite mountain range seen from "
        "10 kilometers altitude: dense knife-edge ridges branching like a tree, deep dark gullies and "
        "ravines between them, light grey-beige bare rock faces with streaks of erosion, pale talus and "
        "scree fans at the foot of slopes, a few small patches of sparse green alpine grass in the "
        "hollows, absolutely no snow, no ice, no lakes, no rivers" + COMMON),
    "alpine_snow": (
        "Seamless tileable texture of high alpine terrain seen from 10 kilometers altitude: bright white "
        "snowfields and firn basins between sharp dark grey rock ridges and arêtes, snow-filled couloirs "
        "running down the gullies, crisp blue-grey shadows in the snow, some bare grey rock outcrops, no "
        "glacier lakes, no rivers" + COMMON),
    "forest_mixed": (
        "Seamless tileable texture of a dense temperate mixed forest seen from 3 kilometers altitude: "
        "thousands of small individual tree crowns forming a fine stipple, deep greens of spruce and fir "
        "mixed with lighter yellow-green patches of beech and oak, each crown with a small dark shadow on "
        "its lower right, closed canopy without clearings, no rivers, no lakes" + COMMON),
    "forest_conifer": (
        "Seamless tileable texture of a dense mountain spruce and fir forest seen from 3 kilometers "
        "altitude: thousands of tiny dark blue-green conifer crowns forming a fine even stipple, deep "
        "shadows between the crowns, a few slightly lighter larch crowns, closed canopy without clearings, "
        "no rivers, no lakes, no snow" + COMMON),
    "meadow_mosaic": (
        "Seamless tileable texture of natural grassland and pasture seen from 3 kilometers altitude: an "
        "irregular organic mosaic of olive green, warm yellow-green and fresh green grass patches with soft "
        "flowing borders, scattered dark green shrubs and hedgerow-free small groves of trees, faint "
        "natural drainage lines, no agricultural fields, no rectangles, no fences, no rivers" + COMMON),
    "dry_ground": (
        "Seamless tileable texture of dry upland steppe seen from 3 kilometers altitude: ochre and pale "
        "olive dry grass with patches of bare light brown soil and pale stony ground, sparse small dark "
        "green scrub bushes scattered irregularly, faint natural erosion rills, no fields, no rectangles, "
        "no rivers" + COMMON),
    "coast_shallows": (
        "Seamless tileable texture of clear shallow tropical-looking coastal sea seen from directly above: "
        "uniform bright turquoise water over pale sand seabed with gentle sand ripples, scattered dark "
        "rock reefs and seagrass patches showing through the water, the water depth is the same everywhere "
        "with no gradient to deep blue, no shoreline, no beach, no land, no waves breaking, no boats"
        + COMMON),
    "beach_rock": (
        "Seamless tileable texture of a rocky sand beach seen from directly above at low altitude: pale "
        "warm sand mixed with grey pebbles and shingle, scattered wet dark grey rocks and small rock "
        "slabs with a little seaweed, uniform everywhere, no water edge, no sea, no footprints, no people"
        + COMMON),
    # Zweite Runde (21. 11. 2026): Die ersten Fassungen von Wiese, Flachwasser und Strand waren zu
    # nah (Einzelbuesche, Lichtnetze, Kiesel) bzw. zu einfarbig. Neu mit groberem Massstab.
    # Dazu eine zweite Felsvariante gegen Wiederholung und ein Buschland fuer Waldraender.
    "meadow_mosaic_v2": (
        "Seamless tileable texture of rolling natural grassland and pasture seen from 5 kilometers "
        "altitude like a satellite image: an irregular organic patchwork with soft flowing borders of "
        "olive green, dull yellow-green, warm ochre dry grass and a few fresh green damp hollows, many tiny "
        "dark green dots of shrubs and small clumps of trees scattered unevenly and gathering along faint "
        "natural drainage lines, muted natural colours, not saturated, no agricultural fields, no "
        "rectangles, no fences, no rivers" + COMMON),
    "coast_shallows_v2": (
        "Seamless tileable texture of a shallow coastal sea seen from 3 kilometers altitude like a "
        "satellite image: clear turquoise water over pale sand banks with long soft sand ripple bars and "
        "channels, irregular darker patches of rock reef and seagrass meadows showing through the water, "
        "the depth is the same everywhere with no gradient to deep blue, no shoreline, no land, no waves, "
        "no boats, no sun glint" + COMMON),
    "beach_rock_v2": (
        "Seamless tileable texture of a rocky coastal shore seen from 1 kilometer altitude like a satellite "
        "image: pale warm sand beaches mixed with grey shingle bands, dark wet rock platforms and boulder "
        "fields with small tidal pools, scattered dark seaweed, uniform everywhere, no water edge, no open "
        "sea, no vegetation, no people" + COMMON),
    "rock_massif_b": (
        "Seamless tileable texture of a vast rugged granite and limestone mountain massif seen from 15 "
        "kilometers altitude: crest lines running in many different directions, sharp arêtes around "
        "empty cirques, steep cliffs, deep dark ravines, warm light grey and beige bare rock with erosion "
        "streaks, wide pale scree slopes, small patches of dull green alpine grass in the valley floors, "
        "absolutely no snow, no ice, no lakes, no rivers" + COMMON),
    "scrub_heath": (
        "Seamless tileable texture of a forest edge transition zone seen from 3 kilometers altitude like a "
        "satellite image: open olive and yellow-green heath and grassland densely dotted with countless "
        "small dark green shrubs, junipers and young trees forming loose irregular clusters of different "
        "sizes, a few ochre dry patches, no closed forest, no fields, no rectangles, no rivers" + COMMON),
}


def load_log():
    if not os.path.exists(LOG):
        return []
    with open(LOG, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def save_log(log):
    with open(LOG, "w", encoding="utf-8", newline="\n") as f:  # UTF-8 ohne BOM
        json.dump(log, f, ensure_ascii=False, indent=2)
        f.write("\n")


def generate(name, prompt_key):
    prompt = JOBS[prompt_key]
    target = os.path.join(OUT, name + ".png")
    cmd = [HF, "generate", "create", MODEL, "--prompt", prompt, "--quality", "high",
           "--resolution", "2k", "--aspect_ratio", "1:1", "--background", "opaque", "--wait", "--json"]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    raw = proc.stdout.strip()
    start = raw.find("[")
    data = json.loads(raw[start:]) if start >= 0 else json.loads(raw)
    result = data[0] if isinstance(data, list) else data
    url = result.get("result_url")
    if not url:
        raise RuntimeError("%s: keine Adresse im Ergebnis: %s %s" % (name, raw[:500], proc.stderr[:500]))
    req = urllib.request.Request(url, headers={"User-Agent": "weltwerk-asset-fetch"})
    with urllib.request.urlopen(req, timeout=300) as r, open(target, "wb") as f:
        f.write(r.read())
    return {
        "name": name,
        "prompt": prompt,
        "job_id": result.get("id"),
        "url": url,
        "model": MODEL,
        "quality": "high",
        "resolution": "2k",
        "aspect_ratio": "1:1",
        "credits": 2,
        "created": result.get("created_at"),
        "date": datetime.date.today().isoformat(),
        "file": "assets/map/source/" + name + ".png",
    }


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    log = load_log()
    todo = []
    for key in (argv or list(JOBS)):
        if os.path.exists(os.path.join(OUT, key + ".png")):
            print("vorhanden:", key)
            continue
        todo.append((key, key))
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(generate, n, k): n for n, k in todo}
        for fut, n in futures.items():
            try:
                entry = fut.result()
                log.append(entry)
                save_log(log)
                print("fertig:", n, entry["job_id"])
            except Exception as exc:  # noqa: BLE001 - weitermachen, Fehler melden
                print("FEHLER:", n, exc)
    save_log(log)


if __name__ == "__main__":
    main(sys.argv[1:])
