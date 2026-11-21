"""Erosionskacheln (16-Bit-PNG) als rohe 32-Bit-Kommazahlen (little endian, 0..1) ablegen.

Godot liest diese Rohdaten verlustfrei (FileAccess + to_float32_array); der PNG-Import würde die
16 Bit nicht sicher erhalten. Aufruf: python tools/make_height_raw.py
"""
import struct
from PIL import Image

for name in ("alpine", "hills"):
    src = f"assets/map/erosion_{name}_height.png"
    im = Image.open(src)
    assert im.mode in ("I;16", "I;16B", "I"), im.mode
    w, h = im.size
    data = list(im.getdata())
    lo, hi = min(data), max(data)
    out = struct.pack("<%df" % len(data), *[(v - lo) / (hi - lo) for v in data])
    with open(f"assets/map/erosion_{name}_height.r32", "wb") as f:
        f.write(out)
    print(name, w, h, lo, hi, len(out))
