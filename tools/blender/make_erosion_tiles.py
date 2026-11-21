"""Kachelbare Erosions-Detailkacheln für die Kontinentkarte (eigene Herstellung, numpy in Blender).

Aufruf (Blender bringt Python und numpy mit, es wird keine Szene gebaut):
  blender -b --factory-startup --python tools/blender/make_erosion_tiles.py -- <projektordner> [kachel] [--vorschau=<ordner>]
    kachel   = alpine | hills | all   (Vorgabe: all)
    Vorschau = Ordner für Vorschaubilder (Vorgabe: <projekt>/assets/map/source)

Ergebnis je Kachel <name> in <projekt>/assets/map/:
  erosion_<name>_height.png  16 Bit Grau, volle Spanne (0 = tiefster, 65535 = höchster Punkt)
  erosion_<name>_normal.png  8 Bit RGB, Tangentenraum, OpenGL (Grün = +Y = im Bild nach oben)
  erosion_<name>_masks.png   8 Bit RGBA: R Abflussmenge/Rinnen (log), G Grate (Konvexität),
                             B Neigung (0 flach .. 1 = 60° und steiler), A Höhe (0..1)
Alle Karten sind periodisch (Torus): Sie schließen in x und y nahtlos an sich selbst an.

Ablauf (alles periodisch, fester Ausgangswert über numpy PCG64 – gleiches Ergebnis bei jedem Lauf):
  1. Grundform: Hebungsfeld aus periodischem Bandrauschen (FFT) plus gratbildendes Rauschen
     (ridged multifractal); wenige Tiefstbereiche werden Abflusspunkte (Talböden).
  2. Flusserosion nach dem Stream-Power-Gesetz (implizit, wie „Fastscape“) auf 256² und 512²:
     Senken auffüllen (Priority-Flood), steilster Abfluss, Einzugsfläche, Einschneiden; dazu
     Hangbegrenzung (Schutthalden-Winkel) bzw. Hangkriechen für die Hügel.
     So entstehen verzweigte (dendritische) Talnetze und messerscharfe Grate.
  3. 1024²: feines Gratrauschen, einige Flusserosionsschritte, dann Tropfenerosion
     (einige hunderttausend Tropfen, vektorisiert, mit Umlauf) für Rinnen und Schwemmfächer,
     zum Schluss thermische Erosion (Schutt, Halden).
  4. Masken, Normalenkarte, Vorschaubilder (Schummerung, Licht aus Nordwest, 2 × 2 gekachelt).

Annahmen für Normalen und Neigung (die Höhe selbst ist auf 0..1 normiert):
  alpine: Kachel 24 km × 24 km, Höhenspanne 2,5 km  (23,4 m je Bildpunkt)
  hills:  Kachel 12 km × 12 km, Höhenspanne 0,5 km  (11,7 m je Bildpunkt)
Wer die Kachel größer aufträgt, teilt die Normalen-Steigung durch das Verhältnis (z. B. 96 km:
Neigung × 0,25) – oder nimmt sie bewusst überhöht (Kartenansicht).
"""
import heapq
import json
import math
import os
import sys
import time

import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
POSITIONAL = [a for a in argv if not a.startswith("--")]
OPTIONS = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
PROJECT = os.path.abspath(POSITIONAL[0] if POSITIONAL else os.getcwd())
WHICH = POSITIONAL[1] if len(POSITIONAL) > 1 else "all"
OUT = os.path.join(PROJECT, "assets", "map")
PREVIEW = os.path.abspath(OPTIONS.get("vorschau", os.path.join(OUT, "source")))
os.makedirs(OUT, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

# Kacheln: alle Zahlen fest, damit jeder Lauf dasselbe Ergebnis liefert.
TILES = {
    "alpine": dict(
        seed=20261121, tile_m=24000.0, relief_m=2500.0,
        m=0.45, ks=200.0, a_c=2.0e5, base_var_m=500.0,                 # Steilheit: Gefälle S = ks · A^-m (A in m²)
        uplift_min=0.30, outlet_share=0.015,
        ridged_f0=5.0, ridged_oct=5, warp=0.0,
        init_relief=600.0,
        levels=[(256, 110, 1.05, 1500.0), (512, 36, 1.15, 600.0)],  # (Raster, Schritte, Grenzneigung, Kriechen m²)
        fine_iters=5, fine_talus=1.25, fine_kd=150.0, round_px=0.0, round_mix=0.0, fine_noise_m=35.0,
        drops=320000, drop_erode=0.015, drop_deposit=0.25, drop_capacity=3.0,
        thermal_talus=1.20, thermal_iters=25,
    ),
    "hills": dict(
        seed=20261122, tile_m=12000.0, relief_m=500.0,
        m=0.40, ks=32.0, a_c=2.0e4, base_var_m=120.0,
        uplift_min=0.45, outlet_share=0.025,
        ridged_f0=4.0, ridged_oct=4, warp=0.0,
        init_relief=150.0,
        levels=[(256, 110, 0.55, 6000.0), (512, 30, 0.60, 3000.0)],
        fine_iters=3, fine_talus=0.62, fine_kd=400.0, round_px=3.0, round_mix=0.55, fine_noise_m=6.0,
        drops=220000, drop_erode=0.02, drop_deposit=0.35, drop_capacity=2.0,
        thermal_talus=0.55, thermal_iters=30,
    ),
}

# Nachbarn (dy, dx) und Abstände in Bildpunkten
OFFS = [(0, -1), (0, 1), (-1, 0), (1, 0), (-1, -1), (-1, 1), (1, -1), (1, 1)]
DIST = [1.0, 1.0, 1.0, 1.0, math.sqrt(2), math.sqrt(2), math.sqrt(2), math.sqrt(2)]


def log(*a):
    print("[erosion]", *a, flush=True)


# ---------------------------------------------------------------- periodische Hilfen
def shifted(h, oy, ox):
    """shifted(h, oy, ox)[y, x] = h[y + oy, x + ox] (mit Umlauf)."""
    return np.roll(h, (-oy, -ox), axis=(0, 1))


def freq_grid(n):
    k = np.fft.fftfreq(n) * n
    kx, ky = np.meshgrid(k, k)
    return np.sqrt(kx * kx + ky * ky)


def band_noise(rng, n, f, width=0.38):
    """Periodisches Rauschen um f Schwingungen je Kachel (log-normales Band), Std = 1."""
    white = rng.standard_normal((n, n))
    k = freq_grid(n)
    k[0, 0] = 1e-9
    filt = np.exp(-0.5 * (np.log(k / f) / width) ** 2)
    filt[0, 0] = 0.0
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
    return out / (out.std() + 1e-12)


def gauss_blur(h, sigma_px):
    if sigma_px <= 0:
        return h
    n = h.shape[0]
    k = np.fft.fftfreq(n)
    kx, ky = np.meshgrid(k, k)
    filt = np.exp(-2.0 * (math.pi * sigma_px) ** 2 * (kx * kx + ky * ky))
    return np.real(np.fft.ifft2(np.fft.fft2(h) * filt))


def upsample2(h):
    """Periodische kubische Verdopplung (Catmull-Rom-Gewichte -1, 9, 9, -1 / 16)."""
    def axis_up(a, axis):
        mid = (-np.roll(a, 1, axis) + 9 * a + 9 * np.roll(a, -1, axis) - np.roll(a, -2, axis)) / 16.0
        shape = list(a.shape)
        shape[axis] *= 2
        out = np.empty(shape, dtype=a.dtype)
        if axis == 0:
            out[0::2] = a
            out[1::2] = mid
        else:
            out[:, 0::2] = a
            out[:, 1::2] = mid
        return out
    return axis_up(axis_up(h, 0), 1)


def ridged(rng, n, f0, octaves):
    total = np.zeros((n, n))
    weight = np.ones((n, n))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        nz = band_noise(rng, n, f0 * 2 ** o)
        sig = np.clip(1.0 - np.abs(nz) * 0.55, 0.0, 1.0) ** 2
        sig *= weight
        weight = np.clip(sig * 1.6, 0.0, 1.0)
        total += sig * amp
        norm += amp
        amp *= 0.5
    total /= norm
    return (total - total.min()) / (total.max() - total.min())


# ---------------------------------------------------------------- Abfluss (Python-Schleifen)
def priority_flood(h, outlet, eps=1e-4):
    """Senken auffüllen (Torus). Rückgabe: aufgefülltes Feld, jeder Nicht-Abflusspunkt hat
    danach einen tieferen Nachbarn."""
    n = h.shape[0]
    shift = n.bit_length() - 1
    mask = n - 1
    hf = h.ravel().tolist()
    closed = bytearray(n * n)
    heap = []
    for i in np.flatnonzero(outlet.ravel()).tolist():
        closed[i] = 1
        heap.append((hf[i], i))
    heapq.heapify(heap)
    pop, push = heapq.heappop, heapq.heappush
    while heap:
        hc, c = pop(heap)
        x = c & mask
        yc = c >> shift
        xm = (x - 1) & mask
        xp = (x + 1) & mask
        ym = ((yc - 1) & mask) << shift
        yp = ((yc + 1) & mask) << shift
        y0 = yc << shift
        for nb in (y0 | xm, y0 | xp, ym | x, yp | x, ym | xm, ym | xp, yp | xm, yp | xp):
            if not closed[nb]:
                closed[nb] = 1
                hn = hf[nb]
                if hn <= hc:
                    hn = hc + eps
                    hf[nb] = hn
                push(heap, (hn, nb))
    return np.array(hf).reshape(n, n)


def d8_receivers(hf, outlet):
    n = hf.shape[0]
    best = np.zeros((n, n))
    rec_off = np.full((n, n), -1, dtype=np.int64)
    for k, (oy, ox) in enumerate(OFFS):
        s = (hf - shifted(hf, oy, ox)) / DIST[k]
        better = s > best
        best = np.where(better, s, best)
        rec_off = np.where(better, k, rec_off)
    yy, xx = np.indices((n, n))
    oy = np.array([o[0] for o in OFFS])
    ox = np.array([o[1] for o in OFFS])
    ko = np.maximum(rec_off, 0)
    ry = (yy + oy[ko]) % n
    rx = (xx + ox[ko]) % n
    rec = ry * n + rx
    own = yy * n + xx
    rec = np.where((rec_off < 0) | outlet, own, rec)
    dist = np.where(ko >= 4, math.sqrt(2), 1.0)
    return rec.ravel(), dist.ravel()


def stream_power_step(h, uplift, outlet, cell_m, m, kdt, a_c=0.0):
    """Ein impliziter Schritt (Braun & Willett 2013), Höhen in Metern."""
    n = h.shape[0]
    hf = priority_flood(h, outlet)
    rec, dist = d8_receivers(hf, outlet)
    order = np.argsort(hf.ravel(), kind="stable")
    rec_l = rec.tolist()
    order_l = order.tolist()
    area = [1.0] * (n * n)
    for i in reversed(order_l):
        r = rec_l[i]
        if r != i:
            area[r] += area[i]
    area = np.array(area) * cell_m * cell_m
    # a_c: kleine Zusatzfläche – unterhalb davon wirkt der Hang (Kriechen, Schutt) statt Rinnen;
    # das verhindert Rinnen in jeder einzelnen Rasterzelle (Gittermuster).
    f = (kdt.ravel() * (area + a_c) ** m / (dist * cell_m)).tolist()
    hl = (hf.ravel() + np.where(outlet.ravel(), 0.0, uplift.ravel())).tolist()
    for i in order_l:
        r = rec_l[i]
        if r != i:
            fi = f[i]
            hl[i] = (hl[i] + fi * hl[r]) / (1.0 + fi)
    return np.array(hl).reshape(n, n), area.reshape(n, n)


def thermal(h, talus_px, iters, rate=0.5, outlet=None):
    """Thermische Erosion: Material oberhalb des Grenzwinkels rutscht zu tieferen Nachbarn.
    talus_px = Höhenunterschied je Bildpunkt (gleiche Einheit wie h)."""
    for _ in range(iters):
        exc = []
        for k, (oy, ox) in enumerate(OFFS):
            d = h - shifted(h, oy, ox) - talus_px * DIST[k]
            exc.append(np.maximum(d, 0.0))
        total = sum(exc) + 1e-12
        biggest = np.maximum.reduce(exc)
        move = rate * 0.5 * biggest
        delta = -move
        for k, (oy, ox) in enumerate(OFFS):
            amt = move * exc[k] / total
            delta = delta + np.roll(amt, (oy, ox), axis=(0, 1))
        h = h + delta
        if outlet is not None:
            pass
    return h


def limit_slope(h, outlet, talus_m_per_px, iters=4):
    """Grenzneigung im Flussmodell: Hänge steiler als der Schuttwinkel brechen nach."""
    return thermal(h, talus_m_per_px, iters, rate=0.8)


def creep(h, kd_dt_m2, cell_m):
    """Hangkriechen (lineare Diffusion, exakt im Frequenzraum)."""
    if kd_dt_m2 <= 0:
        return h
    sigma_px = math.sqrt(2.0 * kd_dt_m2) / cell_m
    return gauss_blur(h, sigma_px)


# ---------------------------------------------------------------- Tropfenerosion
def droplet_erosion(h, rng, drops, batch, erode, deposit, capacity, max_steps=48,
                    inertia=0.08, gravity=4.0, evaporate=0.025, min_cap=0.002, radius=2):
    """Tropfen (nach S. Lague), vektorisiert: viele Tropfen gleichzeitig, Umlauf an den Rändern.
    h in Bildpunkt-Einheiten (Höhe / Rastermaß). Rückgabe: Höhe, Wassermenge je Zelle."""
    n = h.shape[0]
    nn = n * n
    hf = h.ravel().copy()
    water_map = np.zeros(nn)
    bo = []
    for oy in range(-radius, radius + 1):
        for ox in range(-radius, radius + 1):
            d = math.hypot(ox, oy)
            if d < radius:
                bo.append((oy, ox, radius - d))
    bw = np.array([b[2] for b in bo])
    bw /= bw.sum()
    done = 0
    while done < drops:
        b = min(batch, drops - done)
        done += b
        x = rng.uniform(0, n, b)
        y = rng.uniform(0, n, b)
        dx = np.zeros(b)
        dy = np.zeros(b)
        v = np.ones(b)
        w = np.ones(b)
        s = np.zeros(b)
        for _ in range(max_steps):
            ix = np.floor(x).astype(np.int64)
            iy = np.floor(y).astype(np.int64)
            fx = x - ix
            fy = y - iy
            ix %= n
            iy %= n
            ix1 = (ix + 1) % n
            iy1 = (iy + 1) % n
            i00 = iy * n + ix
            i10 = iy * n + ix1
            i01 = iy1 * n + ix
            i11 = iy1 * n + ix1
            h00, h10, h01, h11 = hf[i00], hf[i10], hf[i01], hf[i11]
            gx = (h10 - h00) * (1 - fy) + (h11 - h01) * fy
            gy = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
            hcur = h00 * (1 - fx) * (1 - fy) + h10 * fx * (1 - fy) + h01 * (1 - fx) * fy + h11 * fx * fy
            dx = dx * inertia - gx * (1 - inertia)
            dy = dy * inertia - gy * (1 - inertia)
            ln = np.sqrt(dx * dx + dy * dy)
            flat = ln < 1e-9
            if flat.any():
                a = rng.uniform(0, 2 * math.pi, int(flat.sum()))
                dx[flat] = np.cos(a)
                dy[flat] = np.sin(a)
                ln[flat] = 1.0
            dx /= ln
            dy /= ln
            nx = (x + dx) % n
            ny = (y + dy) % n
            jx = np.floor(nx).astype(np.int64)
            jy = np.floor(ny).astype(np.int64)
            gx2 = nx - jx
            gy2 = ny - jy
            jx %= n
            jy %= n
            jx1 = (jx + 1) % n
            jy1 = (jy + 1) % n
            hnew = (hf[jy * n + jx] * (1 - gx2) * (1 - gy2) + hf[jy * n + jx1] * gx2 * (1 - gy2)
                    + hf[jy1 * n + jx] * (1 - gx2) * gy2 + hf[jy1 * n + jx1] * gx2 * gy2)
            dh = hnew - hcur
            cap = np.maximum(-dh * v * w * capacity, min_cap)
            dep_mask = (s > cap) | (dh > 0)
            dep = np.where(dh > 0, np.minimum(dh, s), (s - cap) * deposit)
            dep = np.where(dep_mask, np.maximum(dep, 0.0), 0.0)
            ero = np.where(dep_mask, 0.0, np.minimum((cap - s) * erode, -dh))
            ero = np.maximum(ero, 0.0)
            s = s - dep + ero
            idx = [i00, i10, i01, i11]
            amt = [dep * (1 - fx) * (1 - fy), dep * fx * (1 - fy), dep * (1 - fx) * fy, dep * fx * fy]
            for (oy, ox, _), wk in zip(bo, bw):
                idx.append(((iy + oy) % n) * n + (ix + ox) % n)
                amt.append(-ero * wk)
            hf += np.bincount(np.concatenate(idx), np.concatenate(amt), minlength=nn)
            water_map += np.bincount(i00, w, minlength=nn)
            v = np.sqrt(np.maximum(v * v - dh * gravity, 0.0))
            w *= (1.0 - evaporate)
            x, y = nx, ny
    return hf.reshape(n, n), water_map.reshape(n, n)


# ---------------------------------------------------------------- Abflussakkumulation (MFD)
def mfd_accumulation(h, outlet, p=1.6):
    n = h.shape[0]
    hf = priority_flood(h, outlet, eps=1e-5)
    weights = []
    for k, (oy, ox) in enumerate(OFFS):
        s = np.maximum((hf - shifted(hf, oy, ox)) / DIST[k], 0.0)
        weights.append(s ** p)
    tot = sum(weights) + 1e-30
    weights = [(wk / tot).ravel().tolist() for wk in weights]
    order = np.argsort(hf.ravel(), kind="stable").tolist()
    shift = n.bit_length() - 1
    mask = n - 1
    area = [1.0] * (n * n)
    w0, w1, w2, w3, w4, w5, w6, w7 = weights
    for c in reversed(order):
        a = area[c]
        x = c & mask
        yc = c >> shift
        xm = (x - 1) & mask
        xp = (x + 1) & mask
        ym = ((yc - 1) & mask) << shift
        yp = ((yc + 1) & mask) << shift
        y0 = yc << shift
        q = w0[c]
        if q: area[y0 | xm] += a * q
        q = w1[c]
        if q: area[y0 | xp] += a * q
        q = w2[c]
        if q: area[ym | x] += a * q
        q = w3[c]
        if q: area[yp | x] += a * q
        q = w4[c]
        if q: area[ym | xm] += a * q
        q = w5[c]
        if q: area[ym | xp] += a * q
        q = w6[c]
        if q: area[yp | xm] += a * q
        q = w7[c]
        if q: area[yp | xp] += a * q
    return np.array(area).reshape(n, n)


# ---------------------------------------------------------------- PNG schreiben (ohne Fremdbibliothek)
def write_png(path, arr):
    import struct
    import zlib
    arr = np.ascontiguousarray(arr)
    hgt, wid = arr.shape[:2]
    ch = 1 if arr.ndim == 2 else arr.shape[2]
    ctype = {1: 0, 2: 4, 3: 2, 4: 6}[ch]
    depth = 16 if arr.dtype == np.uint16 else 8
    data = arr.astype(">u2") if depth == 16 else arr.astype(np.uint8)
    raw = np.frombuffer(data.tobytes(), dtype=np.uint8).reshape(hgt, -1).astype(np.int16)
    bpp = ch * depth // 8
    prev = np.vstack([np.zeros((1, raw.shape[1]), np.int16), raw[:-1]])
    left = np.hstack([np.zeros((hgt, bpp), np.int16), raw[:, :-bpp]])
    upleft = np.hstack([np.zeros((hgt, bpp), np.int16), prev[:, :-bpp]])
    pa = np.abs(prev - upleft)
    pb = np.abs(left - upleft)
    pc = np.abs(left + prev - 2 * upleft)
    paeth = np.where((pa <= pb) & (pa <= pc), left, np.where(pb <= pc, prev, upleft))
    cands = [raw, raw - left, raw - prev, raw - (left + prev) // 2, raw - paeth]
    cands = [(c % 256).astype(np.uint8) for c in cands]
    score = np.stack([np.minimum(c, 256 - c.astype(np.int16)).sum(axis=1) for c in cands])
    best = score.argmin(axis=0)
    rows = np.stack(cands)[best, np.arange(hgt)]
    filtered = np.hstack([best.astype(np.uint8)[:, None], rows])
    comp = zlib.compress(filtered.tobytes(), 9)

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", wid, hgt, depth, ctype, 0, 0, 0)))
        fh.write(chunk(b"IDAT", comp))
        fh.write(chunk(b"IEND", b""))


def to_u8(a):
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- Ableitungen
def gradients(h_m, cell_m):
    gx = (shifted(h_m, 0, 1) - shifted(h_m, 0, -1)) / (2 * cell_m)   # d/dx (Osten, Bild rechts)
    gr = (shifted(h_m, 1, 0) - shifted(h_m, -1, 0)) / (2 * cell_m)   # d/d(Zeile) (Bild unten)
    return gx, gr


def normal_map(h_m, cell_m):
    gx, gr = gradients(h_m, cell_m)
    # OpenGL: +Y zeigt im Bild nach oben, also dh/dy = -dh/dZeile
    nx = -gx
    ny = gr
    nz = np.ones_like(gx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], axis=-1)


def hillshade(h_m, cell_m, exaggeration=1.0):
    nrm = normal_map(h_m * exaggeration, cell_m)
    light = np.array([-1.0, 1.0, 1.15])   # aus Nordwest (links oben), schräg
    light /= np.linalg.norm(light)
    sh = np.clip((nrm * light).sum(axis=-1), 0.0, 1.0)
    return sh


def quantile_norm(a, lo, hi):
    a0, a1 = np.quantile(a, lo), np.quantile(a, hi)
    return np.clip((a - a0) / (a1 - a0 + 1e-12), 0.0, 1.0)


# ---------------------------------------------------------------- eine Kachel
def make_tile(name, cfg):
    t0 = time.time()
    rng = np.random.Generator(np.random.PCG64(cfg["seed"]))
    stats = {"seed": cfg["seed"]}

    # 1. Grundform auf 256²
    n0 = cfg["levels"][0][0]
    massif = gauss_blur(band_noise(rng, n0, 2.0, 0.45) + 0.6 * band_noise(rng, n0, 4.0), 1.0)
    massif = (massif - massif.min()) / (massif.max() - massif.min())
    ridge = ridged(rng, n0, cfg["ridged_f0"], cfg["ridged_oct"])
    uplift_shape = np.clip(cfg["uplift_min"] + (1 - cfg["uplift_min"]) * (0.65 * massif + 0.35 * ridge), 0, 1)
    # Abflusspunkte als gewundene Linien (Nulllinien eines sehr groben Rauschens): große
    # Haupttäler, die über den Kachelrand weiterlaufen – keine runden Kessel.
    # Linien werden unterbrochen (Torwert) und leicht verbogen; ihre Sohle liegt verschieden hoch.
    trunk = np.abs(gauss_blur(band_noise(rng, n0, 1.6, 0.35) + 0.35 * band_noise(rng, n0, 3.5), 1.0))
    gate = band_noise(rng, n0, 2.5)
    trunk = np.where(gate > -0.2, trunk, trunk.max())
    outlet = trunk <= np.quantile(trunk, cfg["outlet_share"])
    base = band_noise(rng, n0, 1.5)
    base = (base - base.min()) / (base.max() - base.min()) * cfg["base_var_m"]
    h = (0.55 * massif + 0.45 * ridge) * cfg["init_relief"] + 5.0 * band_noise(rng, n0, 24.0) + base
    h[outlet] = base[outlet]
    log(name, "Grundform", f"{time.time() - t0:.1f}s")

    # 2. Flusserosion auf den groben Stufen
    m = cfg["m"]
    ks = cfg["ks"]
    u_dt = 120.0                     # Hebung je Schritt in Metern (Zeitmaß frei gewählt)
    for li, (n, steps, talus, kd) in enumerate(cfg["levels"]):
        cell = cfg["tile_m"] / n
        if h.shape[0] != n:
            while h.shape[0] < n:
                h = upsample2(h)
                uplift_shape = upsample2(uplift_shape)
                outlet = upsample2(outlet.astype(float)) > 0.5
                base = upsample2(base)
            h += 0.25 * talus * cell * 0.15 * band_noise(rng, n, n / 6.0)
            h[outlet] = base[outlet]
        uplift = uplift_shape * u_dt
        kdt = np.full_like(uplift, u_dt / ks)   # Gleichgewicht: S = (U/K) A^-m = ks · A^-m bei voller Hebung
        tl = time.time()
        for it in range(steps):
            h, area = stream_power_step(h, uplift, outlet, cell, m, kdt, cfg["a_c"])
            h = limit_slope(h, outlet, talus * cell)
            if kd > 0:
                for _ in range(4):           # in Teilschritten, Talsohlen bleiben dabei fest
                    h = creep(h, kd / 4.0, cell)
                    h[outlet] = base[outlet]
            h[outlet] = base[outlet]
            h = np.maximum(h, 0.0)
        log(name, f"Stufe {n}² {steps} Schritte", f"{time.time() - tl:.1f}s",
            f"Höhe max {h.max():.0f} m, Mittel {h.mean():.0f} m")

    # 3. feinste Stufe 1024²
    n = 1024
    while h.shape[0] < n:
        h = upsample2(h)
        uplift_shape = upsample2(uplift_shape)
        outlet = upsample2(outlet.astype(float)) > 0.5
        base = upsample2(base)
    cell = cfg["tile_m"] / n
    fine = ridged(rng, n, 48.0, 3) - 0.5
    h += cfg["fine_noise_m"] * fine * np.clip(h / (h.max() * 0.3), 0, 1)
    h[outlet] = base[outlet]
    uplift = uplift_shape * u_dt * 0.5
    kdt = np.full_like(uplift, u_dt * 0.5 / ks)
    tl = time.time()
    for it in range(cfg["fine_iters"]):
        h, area = stream_power_step(h, uplift, outlet, cell, m, kdt, cfg["a_c"])
        h = limit_slope(h, outlet, cfg["fine_talus"] * cell, iters=3)
        h = creep(h, cfg["fine_kd"], cell)
        h[outlet] = base[outlet]
        h = np.maximum(h, 0.0)
    log(name, f"Stufe 1024² {cfg['fine_iters']} Flussschritte", f"{time.time() - tl:.1f}s")

    # Tropfenerosion (Höhe in Bildpunkt-Einheiten)
    tl = time.time()
    hp = h / cell
    before = hp.copy()
    hp, water = droplet_erosion(hp, rng, cfg["drops"], 16384, cfg["drop_erode"], cfg["drop_deposit"],
                                cfg["drop_capacity"])
    # Tropfen arbeiten parallel; das ergibt Körnung in Ablagerungen – Änderung leicht glätten
    hp = before + gauss_blur(hp - before, 0.6)
    change = (hp - before) * cell
    log(name, f"Tropfen {cfg['drops']}", f"{time.time() - tl:.1f}s",
        f"Abtrag max {-change.min():.0f} m, Auftrag max {change.max():.0f} m, mittl. |Δ| {np.abs(change).mean():.1f} m")
    stats["droplet_mean_abs_change_m"] = float(np.abs(change).mean())

    # thermische Erosion (Schutt), Grenzwinkel in Bildpunkt-Einheiten
    tl = time.time()
    hp = thermal(hp, cfg["thermal_talus"], cfg["thermal_iters"], rate=0.5)
    h = hp * cell
    # flache Talsohlen beruhigen (parallele Tropfen hinterlassen dort Körnung)
    gx, gr = gradients(h, cell)
    calm = np.clip(1.0 - np.degrees(np.arctan(np.sqrt(gx * gx + gr * gr))) / 18.0, 0.0, 1.0)
    h = h * (1.0 - calm) + gauss_blur(h, 1.5) * calm
    # Hügel: Kuppen und Grate runden (gewichtetes Weichzeichnen), Täler bleiben erkennbar
    if cfg["round_mix"] > 0:
        h = h * (1.0 - cfg["round_mix"]) + gauss_blur(h, cfg["round_px"]) * cfg["round_mix"]
    log(name, "Thermik", f"{time.time() - tl:.1f}s")

    # auf die angenommene Höhenspanne bringen
    h -= h.min()
    natural = float(h.max())
    h *= cfg["relief_m"] / natural
    stats["natural_relief_m"] = natural
    log(name, f"natürliche Spanne {natural:.0f} m → {cfg['relief_m']:.0f} m")

    # 4. Masken
    tl = time.time()
    acc = mfd_accumulation(h, outlet)
    log(name, "Abflussakkumulation", f"{time.time() - tl:.1f}s")
    flow = np.log(acc)
    f0 = math.log(6.0)               # Hänge (wenige Zellen Einzugsfläche) bleiben schwarz
    flow = np.clip((flow - f0) / (np.quantile(flow, 0.995) - f0), 0.0, 1.0)
    lap = lambda a: sum(shifted(a, oy, ox) for oy, ox in OFFS[:4]) - 4 * a
    conv = 0.6 * -lap(gauss_blur(h, 1.0)) + 0.4 * -lap(gauss_blur(h, 3.0)) / 3.0
    ridge_m = np.clip(conv / np.quantile(conv, 0.985), 0.0, 1.0)
    gx, gr = gradients(h, cell)
    slope_deg = np.degrees(np.arctan(np.sqrt(gx * gx + gr * gr)))
    slope = np.clip(slope_deg / 60.0, 0.0, 1.0)
    height = h / h.max()
    stats["slope_deg_median"] = float(np.median(slope_deg))
    stats["slope_deg_p90"] = float(np.quantile(slope_deg, 0.9))
    stats["outlet_share"] = float(outlet.mean())
    log(name, f"Neigung Median {np.median(slope_deg):.1f}°, 90 % {np.quantile(slope_deg, 0.9):.1f}°")

    # Dateien
    hq = np.round(height * 65535.0).astype(np.uint16)
    write_png(os.path.join(OUT, f"erosion_{name}_height.png"), hq)
    nrm = normal_map(h, cell)
    write_png(os.path.join(OUT, f"erosion_{name}_normal.png"), to_u8(nrm * 0.5 + 0.5))
    masks = np.stack([to_u8(flow), to_u8(ridge_m), to_u8(slope), to_u8(height)], axis=-1)
    write_png(os.path.join(OUT, f"erosion_{name}_masks.png"), masks)

    # Vorschaubilder
    shade = hillshade(h, cell, 1.0)
    shade_img = to_u8(0.12 + 0.88 * shade)
    write_png(os.path.join(PREVIEW, f"vorschau_{name}_relief.png"), shade_img)
    tiled = np.tile(shade_img, (2, 2))
    write_png(os.path.join(PREVIEW, f"vorschau_{name}_2x2.png"), tiled)
    write_png(os.path.join(PREVIEW, f"vorschau_{name}_naht.png"), tiled[512:1536, 512:1536])
    # Masken nebeneinander (halbe Größe)
    half = lambda a: a.reshape(512, 2, 512, 2).mean(axis=(1, 3))
    strip = np.hstack([half(flow), half(ridge_m), half(slope), half(height)])
    write_png(os.path.join(PREVIEW, f"vorschau_{name}_masken.png"), to_u8(strip))
    # Farbprobe: Wiese/Wald unten, Fels an steilen Hängen, Schnee oben (nur zur Beurteilung)
    grass = np.array([0.42, 0.52, 0.20])
    forest = np.array([0.16, 0.28, 0.12])
    rock = np.array([0.62, 0.58, 0.52])
    gully = np.array([0.36, 0.33, 0.30])
    snow = np.array([0.93, 0.94, 0.96])
    sl = slope[..., None]
    hh = height[..., None]
    fl = flow[..., None]
    col = grass * (1 - hh) + forest * np.clip(hh * 1.5, 0, 1) * 0.6
    rocky = np.clip((sl - 0.35) / 0.25 + hh * 0.6 - 0.2, 0, 1)
    rcol = rock * (1 - fl * 0.6) + gully * fl * 0.6
    col = col * (1 - rocky) + rcol * rocky
    sn = np.clip((hh - 0.62) / 0.12, 0, 1) * np.clip(1.2 - sl * 1.1, 0, 1) if name == "alpine" else 0 * hh
    col = col * (1 - sn) + snow * sn
    col = col * (0.35 + 0.85 * shade[..., None])
    write_png(os.path.join(PREVIEW, f"vorschau_{name}_farbe.png"), to_u8(np.tile(col, (2, 2, 1))))

    stats["seconds"] = time.time() - t0
    log(name, f"fertig in {stats['seconds']:.1f}s")
    return stats


if __name__ == "__main__":
    names = list(TILES) if WHICH == "all" else [WHICH]
    result = {}
    for nm in names:
        result[nm] = make_tile(nm, TILES[nm])
    with open(os.path.join(PREVIEW, f"erosion_lauf_{WHICH}.json"), "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
    log("Ergebnis", json.dumps(result))
