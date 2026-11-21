# -*- coding: utf-8 -*-
"""Macht die Higgsfield-Kartentexturen nahtlos kachelbar (nur Python 3 + Pillow).

Ablauf je Original (assets/map/source/<name>.png):
 1. mittig quadratisch zuschneiden;
 2. grossraeumigen Helligkeitsverlauf entfernen (Helligkeit durch stark geglaettete Helligkeit
    teilen, mit dem Mittelwert malnehmen; nur Helligkeit, Farbtoene bleiben);
 3. nahtlos machen durch Ueberlappung: Der rechte (untere) Randstreifen der Breite B wird in den
    linken (oberen) Streifen ueberblendet und dann abgeschnitten. Dadurch schliesst die rechte
    Kante an die linke an, ohne dass Inhalte doppelt vorkommen. Die Ueberblendmaske folgt der
    Helligkeit (helle Kronen/Grate setzen sich durch) und ist mit festem Rauschen gestoert - so
    entsteht keine gerade, verwaschene Naht;
 4. auf Zielgroesse bringen, als assets/map/<name>.jpg (Qualitaet 90) speichern;
 5. fuer Fels und Wald eine Hoehenkarte aus der Helligkeit (assets/map/<name>_height.png);
 6. Vorschau 2 x 2 gekachelt nach assets/map/source/<name>_tiled.jpg.

Fester Zufall: das Stoerrauschen kommt aus random.Random mit festem Ausgangswert je Name.
Aufruf: python tools/make_seamless_textures.py [name ...]
"""
import os
import random
import sys
import zlib

from PIL import Image, ImageChops, ImageFilter, ImageMath, ImageOps

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "assets", "map", "source")
OUT = os.path.join(ROOT, "assets", "map")

# name -> (Ausgabegroesse, Hoehenkarte?, Quelle)  Quelle = Dateiname ohne .png in source/
TEXTURES = {
    "rock_massif": (2048, True),
    "alpine_snow": (2048, False),
    "forest_mixed": (2048, True),
    "forest_conifer": (2048, True),
    "meadow_mosaic": (2048, False),
    "dry_ground": (1024, False),
    "coast_shallows": (1024, False),
    "beach_rock": (1024, False),
    "rock_massif_b": (2048, True),
    "scrub_heath": (2048, False),
}
# Neufassungen, die die erste Fassung ersetzen: name -> Quelldatei (ohne .png).
SOURCE_OVERRIDE = {
    "meadow_mosaic": "meadow_mosaic_v2",
    "coast_shallows": "coast_shallows_v2",
    "beach_rock": "beach_rock_v2",
}

BAND_FRACTION = 1.0 / 8.0   # Breite des Ueberblendstreifens relativ zur Kantenlaenge
SEED_BASE = 20261121


def lum(img):
    return img.convert("L")


def remove_lighting_gradient(img):
    """Teilt die Helligkeit durch ihren sehr weichen Verlauf (Tiefpass ~ 1/3 Bildgroesse)."""
    n = img.size[0]
    l_img = lum(img)
    low = l_img.resize((12, 12), Image.BOX).filter(ImageFilter.GaussianBlur(1.2))
    low = low.resize((n, n), Image.BICUBIC)
    mean = sum(i * c for i, c in enumerate(l_img.histogram())) / float(n * n)
    channels = []
    for ch in img.split():
        out = ImageMath.lambda_eval(
            lambda a: a["float"](a["c"]) * mean / a["max"](a["float"](a["low"]), 1.0),
            c=ch, low=low)
        channels.append(out.convert("L"))  # F -> L rundet und begrenzt auf 0..255
    return Image.merge("RGB", channels)


def noise_field(w, h, seed, cells=6):
    """Weiches Wertrauschen 0..255 (fester Ausgangswert)."""
    rng = random.Random(seed)
    small = Image.new("L", (cells + 1, cells + 1))
    small.putdata([rng.randint(0, 255) for _ in range((cells + 1) * (cells + 1))])
    return small.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(max(w, h) / 40.0))


def ramp(w, h):
    """Waagrechter Verlauf 0 (links) .. 255 (rechts) als L-Bild."""
    g = Image.linear_gradient("L").rotate(90, expand=True)
    if g.getpixel((0, 0)) > g.getpixel((g.size[0] - 1, 0)):
        g = g.transpose(Image.FLIP_LEFT_RIGHT)
    return g.resize((w, h), Image.BILINEAR)


def blend_mask(a_band, b_band, seed):
    """Maske: 0 = B (Inhalt hinter der Kante), 255 = A (Bildanfang). Endpunkte sind fest,
    dazwischen entscheidet die Helligkeit (Hoehenueberblendung) plus Stoerrauschen."""
    w, h = a_band.size
    t = ramp(w, h)
    ha = lum(a_band).filter(ImageFilter.GaussianBlur(2))
    hb = lum(b_band).filter(ImageFilter.GaussianBlur(2))
    nz = noise_field(w, h, seed)
    # Steiler Uebergang (Faktor 3): die eigentliche Ueberblendung ist schmal und laeuft entlang
    # einer durch Rauschen und Helligkeit verbogenen Linie - wie ein Schnitt, nicht wie ein Schleier.
    m = ImageMath.lambda_eval(
        lambda a: a["min"](a["max"](
            127.5 + (a["float"](a["t"]) - 127.5) * 3.0
            + (a["float"](a["ha"]) - a["float"](a["hb"])) * 0.25
            + (a["float"](a["nz"]) - 127.5) * 0.9, 0.0), 255.0),
        t=t, ha=ha, hb=hb, nz=nz)
    return m.convert("L").filter(ImageFilter.GaussianBlur(1.5))


def match_low_frequency(blended, reference, radius):
    """Gleicht die grobe Helligkeit von 'blended' an 'reference' an (je Kanal, nur Tiefpass).
    Die helligkeitsgefuehrte Maske bevorzugt helle Bildteile und hellt den Streifen sonst auf."""
    out = []
    for cb, cr in zip(blended.split(), reference.split()):
        lb = cb.filter(ImageFilter.GaussianBlur(radius))
        lr = cr.filter(ImageFilter.GaussianBlur(radius))
        out.append(ImageMath.lambda_eval(
            lambda a: a["float"](a["c"]) * a["float"](a["r"]) / a["max"](a["float"](a["b"]), 1.0),
            c=cb, r=lr, b=lb).convert("L"))
    return Image.merge("RGB", out)


def make_seamless_x(img, band, seed):
    n_w, n_h = img.size
    m_w = n_w - band
    a_band = img.crop((0, 0, band, n_h))
    b_band = img.crop((m_w, 0, n_w, n_h))
    mask = blend_mask(a_band, b_band, seed)
    # Endpunkte erzwingen: erste Spalte ganz B, letzte Spalte ganz A.
    px = mask.load()
    for y in range(n_h):
        px[0, y] = 0
        px[band - 1, y] = 255
    blended = Image.composite(a_band, b_band, mask)
    linear = Image.composite(a_band, b_band, ramp(band, n_h))  # ohne Helligkeitsvorliebe
    matched = match_low_frequency(blended, linear, band / 6.0)
    # Angleichung nur in der Streifenmitte; an beiden Enden bleibt das Bild unveraendert,
    # damit an der Kachelkante keine Stufe entsteht. Fenster w = 4 t (1 - t).
    window = ramp(band, n_h).point(lambda v: int(round(4.0 * (v / 255.0) * (1.0 - v / 255.0) * 255.0)))
    blended = Image.composite(matched, blended, window)
    out = img.crop((0, 0, m_w, n_h))
    out.paste(blended, (0, 0))
    return out


def make_seamless(img, seed):
    n = img.size[0]
    band = int(n * BAND_FRACTION)
    x_done = make_seamless_x(img, band, seed)
    y_done = make_seamless_x(x_done.transpose(Image.TRANSPOSE), band, seed + 1)
    return y_done.transpose(Image.TRANSPOSE)


def flatten_line_bands(img, window=48):
    """Entfernt gerade, zeilen- oder spaltenweise Helligkeitsbaender (z. B. ein etwas dunklerer
    Streifen entlang der Kachelkante). Natuerliche Bilder haben keine achsparallelen Baender; der
    Mittelwert ueber die ganze Zeile verduennt echte Bildinhalte so stark, dass sie bleiben.
    Das Profil wird kreisfoermig geglaettet, damit die Kachel nahtlos bleibt."""
    n = img.size[0]
    l_img = lum(img)
    mean = sum(i * c for i, c in enumerate(l_img.histogram())) / float(n * n)

    def profile(strip_img):  # strip_img: n x 1 (Zeilen) als L
        vals = list(strip_img.getdata())
        half = window // 2
        out = []
        for i in range(n):
            s = 0.0
            for k in range(-half, half + 1):
                s += vals[(i + k) % n]
            out.append(s / (2 * half + 1))
        return out

    rows = profile(l_img.resize((1, n), Image.BOX).convert("L"))
    cols = profile(l_img.resize((n, 1), Image.BOX).convert("L").transpose(Image.TRANSPOSE))
    g_row = Image.new("F", (1, n))
    g_row.putdata([mean / max(v, 1.0) for v in rows])
    g_col = Image.new("F", (n, 1))
    g_col.putdata([mean / max(v, 1.0) for v in cols])
    gain = ImageMath.lambda_eval(lambda a: a["r"] * a["c"],
                                 r=g_row.resize((n, n), Image.NEAREST),
                                 c=g_col.resize((n, n), Image.NEAREST))
    chans = [ImageMath.lambda_eval(lambda a: a["float"](a["x"]) * a["g"], x=ch, g=gain).convert("L")
             for ch in img.split()]
    return Image.merge("RGB", chans)


def height_map(img, size):
    """Hoehenkarte aus der Helligkeit: hell = hoch (Kronen, Grate, Geroell), dunkel = tief
    (Schatten, Rinnen). Grossraeumiges entfernt, Kontrast gestreckt. Bleibt nahtlos, weil
    nur kachelnde Filter benutzt werden (Weichzeichnen auf 3 x 3 gekacheltem Bild)."""
    l_img = lum(img)
    n = l_img.size[0]
    tiled = Image.new("L", (n * 3, n * 3))
    for i in range(3):
        for j in range(3):
            tiled.paste(l_img, (i * n, j * n))
    low = tiled.filter(ImageFilter.GaussianBlur(n / 24.0)).crop((n, n, 2 * n, 2 * n))
    fine = tiled.filter(ImageFilter.GaussianBlur(1.0)).crop((n, n, 2 * n, 2 * n))
    hp = ImageMath.lambda_eval(
        lambda a: a["float"](a["f"]) - a["float"](a["lo"]) * 0.75 + 32.0, f=fine, lo=low)
    hp = hp.convert("L")
    hp = ImageOps.autocontrast(hp, cutoff=1)
    return hp.resize((size, size), Image.LANCZOS)


def tiled_preview(img, path, size=1024):
    small = img.resize((size, size), Image.LANCZOS)
    prev = Image.new("RGB", (size * 2, size * 2))
    for i in range(2):
        for j in range(2):
            prev.paste(small, (i * size, j * size))
    prev.save(path, quality=88)


def seam_crop(img, path, half=384):
    """Ausschnitt in voller Aufloesung um die Kachelkante (2 x 2 gekachelt, Mitte = Kanten-Ecke)."""
    n = img.size[0]
    big = Image.new("RGB", (n * 2, n * 2))
    for i in range(2):
        for j in range(2):
            big.paste(img, (i * n, j * n))
    big.crop((n - half, n - half, n + half, n + half)).save(path, quality=90)


def process(name):
    size, with_height = TEXTURES[name]
    src_name = SOURCE_OVERRIDE.get(name, name)
    src = os.path.join(SRC, src_name + ".png")
    img = Image.open(src).convert("RGB")
    w, h = img.size
    s = min(w, h)
    img = img.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))
    img = remove_lighting_gradient(img)
    seed = SEED_BASE + zlib.crc32(name.encode("utf-8")) % 100000
    img = make_seamless(img, seed)
    final = img.resize((size, size), Image.LANCZOS)
    final = flatten_line_bands(final, window=max(16, size // 40))
    out_path = os.path.join(OUT, name + ".jpg")
    final.save(out_path, quality=90, optimize=True)
    if with_height:
        height_map(final, 1024).save(os.path.join(OUT, name + "_height.png"), optimize=True)
    tiled_preview(final, os.path.join(SRC, name + "_tiled.jpg"))
    seam_crop(final, os.path.join(SRC, name + "_seam.jpg"))
    print("fertig:", name, "<-", src_name, final.size, os.path.getsize(out_path), "Byte")


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    names = argv or [n for n in TEXTURES if os.path.exists(
        os.path.join(SRC, SOURCE_OVERRIDE.get(n, n) + ".png"))]
    for name in names:
        process(name)


if __name__ == "__main__":
    main(sys.argv[1:])
