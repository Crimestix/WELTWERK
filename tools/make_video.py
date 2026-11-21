"""Film aus einer Echtzeit-Aufnahme des Editors (--echtzeit=<Ordner>) zusammensetzen.

Die Bilder in <Ordner>/frames/ tragen Wanduhr-Zeitstempel (frames/zeiten.csv). Der Film läuft
mit fester Bildrate (Vorgabe 25 Bilder/s); jedes Filmbild zeigt das letzte aufgenommene Bild zu
oder vor seinem Zeitpunkt. Rechnet der Editor (kein neues Bild), steht das Bild im Film genau so
lange still, wie die Pause wirklich dauerte. Während einer Pause (aus <Ordner>/echtzeit.json)
wird „Rechenpause x,x s von y,y s“ mit Fortschrittsbalken und Ursache eingeblendet; in allen
Bildern läuft unten links die Uhr.

Ausgabe: Motion-JPEG in einem selbst geschriebenen AVI-Behälter (RIFF: hdrl/strl/movi mit
'00dc'-Blöcken und idx1, Kennung MJPG) – ohne ffmpeg, nur Python 3 und Pillow. Nach dem
Schreiben wird die Datei wieder eingelesen und geprüft (Kopf, Bildzahl, Dauer, Index).
Stehende Bilder (gleiches Ausgangsbild, gleiche Einblendung) werden nur einmal kodiert. Vor dem
Schreiben wird die Größe geschätzt; über --max-mb (Vorgabe 1000 MiB, unter der 1-GiB-Grenze von
AVI 1.0) wird in Teile <Name>_teilN.avi geteilt (oder mit --nicht-teilen abgebrochen).

Aufruf:
  python tools/make_video.py <Ordner> [--out film.avi] [--fps 25] [--quality 85]
                             [--kontaktbogen bogen.jpg] [--max-mb 1000] [--nicht-teilen]
  python tools/make_video.py --pruefen film.avi [film_teil2.avi …]
"""

import argparse
import bisect
import csv
import io
import json
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFont

# Farben der Oberfläche (Dark Fantasy): geschwärztes Holz, Messing, Pergament.
WOOD = (24, 20, 16)
BRASS = (184, 142, 76)
PARCHMENT = (238, 226, 196)

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\segoeui.ttf",
    r"C:\Windows\Fonts\arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]
FONT_BOLD_CANDIDATES = [
    r"C:\Windows\Fonts\segoeuib.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
] + FONT_CANDIDATES


def load_font(size, bold=False):
    for path in (FONT_BOLD_CANDIDATES if bold else FONT_CANDIDATES):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def num(value, digits=1):
    """Zahl mit deutschem Komma."""
    return ("%.*f" % (digits, value)).replace(".", ",")


def clock(seconds):
    """Minuten:Sekunden,Zehntel – erst auf Zehntel runden, dann teilen (nie „0:60,0“)."""
    tenths = int(round(max(seconds, 0.0) * 10.0))
    minutes, rest = divmod(tenths, 600)
    return "%d:%02d,%d" % (minutes, rest // 10, rest % 10)


# --- Aufnahme lesen --------------------------------------------------------------------------

def read_capture(folder):
    times = []
    with open(os.path.join(folder, "frames", "zeiten.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter=";"):
            times.append(float(row["ms"]) / 1000.0)
    report = {}
    path = os.path.join(folder, "echtzeit.json")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            report = json.load(f)
    return times, report


def frame_path(folder, index):
    return os.path.join(folder, "frames", "f_%06d.jpg" % index)


# --- Einblendungen ---------------------------------------------------------------------------

class Stamper:
    def __init__(self, width):
        scale = width / 1280.0
        self.scale = scale
        self.font = load_font(int(round(20 * scale)))
        self.font_small = load_font(int(round(16 * scale)))
        self.font_big = load_font(int(round(24 * scale)), bold=True)

    @staticmethod
    def texts(t, pause):
        """Alles, was eingeblendet wird, als Schlüssel: Uhr, Pausentitel, Ursache, Balken (Zehntel).
        Gleicher Schlüssel und gleiches Ausgangsbild → gleiches Filmbild."""
        if pause is None:
            return ("Zeit " + clock(t), None, None, None)
        elapsed = round(min(t - pause["start_s"], pause["duration_s"]), 1)
        title = "Rechenpause %s s von %s s – das Bild steht still" % (num(elapsed), num(pause["duration_s"]))
        cause = pause.get("ursache") or pause.get("handlung") or ""
        frac = elapsed / pause["duration_s"] if pause["duration_s"] > 0 else 1.0
        return ("Zeit " + clock(t), title, cause, round(min(frac, 1.0), 3))

    def stamp(self, image, key):
        s = self.scale
        draw = ImageDraw.Draw(image, "RGBA")
        w, h = image.size
        text, title, cause, frac = key
        # Uhr unten links (über der Maßstabsleiste des Editors).
        box = draw.textbbox((0, 0), text, font=self.font)
        x, y = int(14 * s), h - int(78 * s)
        draw.rounded_rectangle((x - 8 * s, y - 6 * s, x + box[2] + 8 * s, y + box[3] + 8 * s),
                               radius=6 * s, fill=WOOD + (200,), outline=BRASS + (200,), width=max(1, int(s)))
        draw.text((x, y), text, font=self.font, fill=PARCHMENT)
        if title is None:
            return
        # Rechenpause: Tafel in Bildmitte oben, Laufzeit, Fortschritt, Ursache.
        tb = draw.textbbox((0, 0), title, font=self.font_big)
        cb = draw.textbbox((0, 0), cause, font=self.font_small)
        pw = max(tb[2], cb[2]) + int(40 * s)
        ph = tb[3] + cb[3] + int(44 * s)
        px = (w - pw) // 2
        py = int(118 * s)
        draw.rounded_rectangle((px, py, px + pw, py + ph), radius=8 * s, fill=WOOD + (225,),
                               outline=BRASS + (255,), width=max(2, int(2 * s)))
        draw.text((px + 20 * s, py + 10 * s), title, font=self.font_big, fill=PARCHMENT)
        draw.text((px + 20 * s, py + 16 * s + tb[3]), cause, font=self.font_small, fill=BRASS)
        bar_y = py + ph - int(10 * s)
        bar_x0, bar_x1 = px + 20 * s, px + pw - 20 * s
        draw.rectangle((bar_x0, bar_y, bar_x1, bar_y + 4 * s), fill=(70, 60, 48, 255))
        draw.rectangle((bar_x0, bar_y, bar_x0 + (bar_x1 - bar_x0) * frac, bar_y + 4 * s), fill=BRASS + (255,))


def pause_at(pauses, starts, t):
    """Pause, in der der Zeitpunkt t liegt (oder None)."""
    k = bisect.bisect_right(starts, t) - 1
    if k >= 0:
        p = pauses[k]
        if p["start_s"] <= t < p["start_s"] + p["duration_s"]:
            return p
    return None


def source_index(times, t):
    return max(0, bisect.bisect_right(times, t + 1e-6) - 1)


def render(folder, times, pauses, starts, stamper, t, size, cache):
    k = source_index(times, t)
    if cache.get("index") != k:
        image = Image.open(frame_path(folder, k)).convert("RGB")
        if image.size != size:
            image = image.resize(size, Image.BILINEAR)
        cache["index"] = k
        cache["image"] = image
    image = cache["image"].copy()
    stamper.stamp(image, Stamper.texts(t, pause_at(pauses, starts, t)))
    return image, k


class FrameEncoder:
    """Filmbilder als JPEG; ein stehendes Bild (gleiches Ausgangsbild, gleiche Einblendung) wird
    nur einmal kodiert, die Bytes werden wiederverwendet."""

    def __init__(self, folder, times, pauses, starts, stamper, size, quality):
        self.folder, self.times, self.pauses, self.starts = folder, times, pauses, starts
        self.stamper, self.size, self.quality = stamper, size, quality
        self.images = {}
        self.jpegs = {}
        self.encoded = 0
        self.reused = 0

    def _source(self, k):
        if k not in self.images:
            self.images.clear()
            image = Image.open(frame_path(self.folder, k)).convert("RGB")
            if image.size != self.size:
                image = image.resize(self.size, Image.BILINEAR)
            self.images[k] = image
        return self.images[k]

    def jpeg(self, t):
        k = source_index(self.times, t)
        key = (k,) + Stamper.texts(t, pause_at(self.pauses, self.starts, t))
        data = self.jpegs.get(key)
        if data is not None:
            self.reused += 1
            return data, k
        image = self._source(k).copy()
        self.stamper.stamp(image, key[1:])
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=self.quality)
        data = buffer.getvalue()
        # Nur die jüngsten Einträge halten: Wiederholungen folgen unmittelbar aufeinander.
        if len(self.jpegs) > 64:
            self.jpegs.clear()
        self.jpegs[key] = data
        self.encoded += 1
        return data, k


# --- AVI (RIFF) schreiben --------------------------------------------------------------------

def fourcc(text):
    return text.encode("ascii")


class AviWriter:
    """Motion-JPEG-AVI mit einem Videostrom, Index idx1 (Versätze relativ zu 'movi')."""

    def __init__(self, path, width, height, fps):
        self.f = open(path, "wb")
        self.width, self.height, self.fps = width, height, fps
        self.index = []
        self.max_size = 0
        f = self.f
        f.write(fourcc("RIFF") + b"\0\0\0\0" + fourcc("AVI "))
        hdrl_start = self._list_start("hdrl")
        # avih: MainAVIHeader (56 Byte)
        f.write(fourcc("avih") + struct.pack("<I", 56))
        self.avih_pos = f.tell()
        f.write(struct.pack("<IIIIIIIIII4I",
                            int(round(1000000 / fps)),  # dwMicroSecPerFrame
                            0,  # dwMaxBytesPerSec (später)
                            0,  # dwPaddingGranularity
                            0x10,  # dwFlags: AVIF_HASINDEX
                            0,  # dwTotalFrames (später)
                            0,  # dwInitialFrames
                            1,  # dwStreams
                            0,  # dwSuggestedBufferSize (später)
                            width, height, 0, 0, 0, 0))
        strl_start = self._list_start("strl")
        # strh: AVIStreamHeader (56 Byte)
        f.write(fourcc("strh") + struct.pack("<I", 56))
        self.strh_pos = f.tell()
        f.write(fourcc("vids") + fourcc("MJPG"))
        f.write(struct.pack("<IHHIIIIIIIIhhhh",
                            0,  # dwFlags
                            0, 0,  # wPriority, wLanguage
                            0,  # dwInitialFrames
                            1, fps,  # dwScale, dwRate → fps Bilder/s
                            0,  # dwStart
                            0,  # dwLength (später)
                            0,  # dwSuggestedBufferSize (später)
                            0xFFFFFFFF,  # dwQuality: Vorgabe
                            0,  # dwSampleSize
                            0, 0, width, height))  # rcFrame
        # strf: BITMAPINFOHEADER (40 Byte)
        f.write(fourcc("strf") + struct.pack("<I", 40))
        f.write(struct.pack("<IiiHH4sIiiII", 40, width, height, 1, 24, fourcc("MJPG"),
                            width * height * 3, 0, 0, 0, 0))
        self._list_end(strl_start)
        self._list_end(hdrl_start)
        self.movi_start = self._list_start("movi")
        self.movi_fourcc_pos = self.movi_start + 8

    def _list_start(self, kind):
        pos = self.f.tell()
        self.f.write(fourcc("LIST") + b"\0\0\0\0" + fourcc(kind))
        return pos

    def _list_end(self, pos):
        end = self.f.tell()
        self.f.seek(pos + 4)
        self.f.write(struct.pack("<I", end - pos - 8))
        self.f.seek(end)

    def projected(self, jpeg_len):
        """Dateigröße, wenn noch ein Bild dieser Länge dazukommt (mit Index)."""
        return self.f.tell() + 8 + jpeg_len + (jpeg_len & 1) + 8 + 16 * (len(self.index) + 1)

    def add(self, jpeg):
        pos = self.f.tell()
        self.f.write(fourcc("00dc") + struct.pack("<I", len(jpeg)) + jpeg)
        if len(jpeg) % 2:
            self.f.write(b"\0")
        self.index.append((pos - self.movi_fourcc_pos, len(jpeg)))
        self.max_size = max(self.max_size, len(jpeg))

    def close(self):
        f = self.f
        self._list_end(self.movi_start)
        f.write(fourcc("idx1") + struct.pack("<I", 16 * len(self.index)))
        for offset, size in self.index:
            f.write(fourcc("00dc") + struct.pack("<III", 0x10, offset, size))  # AVIIF_KEYFRAME
        end = f.tell()
        f.seek(4)
        f.write(struct.pack("<I", end - 8))
        n = len(self.index)
        total = sum(size for _, size in self.index)
        seconds = n / float(self.fps) if n else 1.0
        f.seek(self.avih_pos + 4)
        f.write(struct.pack("<I", int(total / seconds)))
        f.seek(self.avih_pos + 16)
        f.write(struct.pack("<I", n))
        f.seek(self.avih_pos + 28)
        f.write(struct.pack("<I", self.max_size + 8))
        # strh: dwLength bei +32, dwSuggestedBufferSize bei +36 (nach fccType, fccHandler, …).
        f.seek(self.strh_pos + 32)
        f.write(struct.pack("<II", n, self.max_size + 8))
        f.close()


# --- AVI prüfen ------------------------------------------------------------------------------

def check_avi(path):
    """Datei wieder einlesen: Kopf, Bildzahl, Dauer, Index gegen die Blöcke prüfen."""
    problems = []
    with open(path, "rb") as f:
        data = f.read()
    if data[0:4] != b"RIFF" or data[8:12] != b"AVI ":
        return {"ok": False, "probleme": ["kein RIFF/AVI-Kopf"]}
    riff_size = struct.unpack_from("<I", data, 4)[0]
    if riff_size + 8 != len(data):
        problems.append("RIFF-Größe %d passt nicht zur Datei (%d)" % (riff_size + 8, len(data)))
    info = {"datei_bytes": len(data)}
    chunks = 0
    movi_fourcc = None
    idx1 = None

    def walk(start, end, depth):
        nonlocal chunks, movi_fourcc, idx1
        pos = start
        while pos + 8 <= end:
            cid = data[pos:pos + 4]
            size = struct.unpack_from("<I", data, pos + 4)[0]
            body = pos + 8
            if body + size > end:
                problems.append("Block %r über das Ende hinaus" % cid)
                return
            if cid == b"LIST":
                kind = data[body:body + 4]
                if kind == b"movi":
                    movi_fourcc = body
                walk(body + 4, body + size, depth + 1)
            elif cid == b"avih":
                (usec, _, _, flags, total, _, streams, _, w, h) = struct.unpack_from("<IIIIIIIIII", data, body)
                info.update(us_je_bild=usec, bilder_avih=total, stroeme=streams, breite=w, hoehe=h, index_flag=bool(flags & 0x10))
            elif cid == b"strh":
                ftype, handler = data[body:body + 4], data[body + 4:body + 8]
                scale, rate, start_, length = struct.unpack_from("<IIII", data, body + 20)
                info.update(stromart=ftype.decode(), codec=handler.decode(), rate=rate, scale=scale, bilder_strh=length)
            elif cid == b"strf":
                info["strf_kompression"] = data[body + 16:body + 20].decode()
            elif cid == b"00dc":
                chunks += 1
            elif cid == b"idx1":
                idx1 = (body, size)
            pos = body + size + (size & 1)

    walk(12, len(data), 0)
    info["bloecke_00dc"] = chunks
    if idx1 is None or movi_fourcc is None:
        problems.append("idx1 oder movi fehlt")
    else:
        body, size = idx1
        entries = size // 16
        info["index_eintraege"] = entries
        bad = 0
        for k in range(entries):
            cid, flags, offset, length = struct.unpack_from("<4sIII", data, body + 16 * k)
            at = movi_fourcc + offset
            if cid != b"00dc" or data[at:at + 4] != b"00dc" or struct.unpack_from("<I", data, at + 4)[0] != length \
                    or data[at + 8:at + 10] != b"\xff\xd8" or data[at + 8 + length - 2:at + 8 + length] != b"\xff\xd9":
                bad += 1
        if bad:
            problems.append("%d Indexeinträge zeigen nicht auf ein vollständiges JPEG" % bad)
    n = info.get("bilder_avih", 0)
    if not (n == info.get("bilder_strh") == chunks == info.get("index_eintraege")):
        problems.append("Bildzahlen uneinheitlich: avih %s, strh %s, Blöcke %s, Index %s"
                        % (n, info.get("bilder_strh"), chunks, info.get("index_eintraege")))
    if info.get("codec") != "MJPG" or info.get("strf_kompression") != "MJPG":
        problems.append("Kennung nicht MJPG")
    if info.get("rate"):
        info["bilder_je_s"] = info["rate"] / float(info["scale"])
        info["dauer_s"] = round(n * info["scale"] / float(info["rate"]), 3)
    info["ok"] = not problems
    info["probleme"] = problems
    return info


# --- Kontaktbogen ----------------------------------------------------------------------------

def contact_sheet(folder, times, pauses, starts, stamper_full, size, duration, out_path, count=12):
    """~12 Bilder: gleichmäßig verteilt, dazu unmittelbar vor, während und nach der längsten Pause."""
    picks = []
    if pauses:
        longest = max(pauses, key=lambda p: p["duration_s"])
        start, end = longest["start_s"], longest["start_s"] + longest["duration_s"]
        picks.append((start - 0.001, "kurz vor der längsten Pause"))
        picks.append((start + longest["duration_s"] * 0.6, "während der Pause (Bild steht)"))
        k = bisect.bisect_left(times, end - 0.005)
        after = times[k] if k < len(times) else end
        picks.append((max(after, end) + 0.001, "erstes Bild nach der Pause"))
    rest = count - len(picks)
    for k in range(rest):
        picks.append((duration * (k + 0.5) / rest, ""))
    picks.sort(key=lambda p: p[0])
    cols = 4
    rows = (len(picks) + cols - 1) // cols
    tw, th = 400, 250
    label_h = 26
    sheet = Image.new("RGB", (cols * (tw + 8) + 8, rows * (th + label_h + 8) + 8), WOOD)
    draw = ImageDraw.Draw(sheet)
    font = load_font(15)
    for n, (t, label) in enumerate(picks):
        image, _ = render(folder, times, pauses, starts, stamper_full, t, size, {})
        image = image.resize((tw, th), Image.LANCZOS)
        x = 8 + (n % cols) * (tw + 8)
        y = 8 + (n // cols) * (th + label_h + 8)
        sheet.paste(image, (x, y))
        text = "%s s" % num(t, 2) + ("  ·  " + label if label else "")
        draw.text((x + 4, y + th + 4), text, font=font, fill=BRASS if label else PARCHMENT)
    sheet.save(out_path, quality=90)
    return [(round(t, 3), label) for t, label in picks]


# --- Ablauf ----------------------------------------------------------------------------------

def part_path(out, number, expected):
    """Erster Teil heißt wie verlangt, solange nur einer erwartet wird; sonst <Name>_teilN.avi."""
    if number == 1 and expected == 1:
        return out
    base, ext = os.path.splitext(out)
    return "%s_teil%d%s" % (base, number, ext or ".avi")


def main():
    # Windows-Konsole (cp1252) kennt Zeichen wie „≈“ nicht: Ausgabe immer als UTF-8.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description="Film aus einer Echtzeit-Aufnahme (--echtzeit=<Ordner>).")
    parser.add_argument("ordner", nargs="?")
    parser.add_argument("--out")
    parser.add_argument("--fps", type=int, default=25)
    parser.add_argument("--quality", type=int, default=85)
    parser.add_argument("--kontaktbogen")
    parser.add_argument("--max-mb", type=float, default=1000.0,
                        help="höchstens so groß wird eine AVI-Datei (MiB, Vorgabe 1000 – unter der 1-GiB-Grenze "
                             "von AVI 1.0); größere Filme werden in Teile geteilt")
    parser.add_argument("--nicht-teilen", action="store_true",
                        help="statt zu teilen abbrechen, wenn die Schätzung über --max-mb liegt")
    parser.add_argument("--pruefen", metavar="AVI", nargs="+", help="nur vorhandene AVI-Dateien prüfen")
    args = parser.parse_args()

    if args.pruefen:
        all_ok = True
        for path in args.pruefen:
            info = check_avi(path)
            print(path)
            print(json.dumps(info, ensure_ascii=False, indent=1))
            all_ok = all_ok and info["ok"]
        return 0 if all_ok else 1
    if not args.ordner:
        parser.error("Ordner der Aufnahme fehlt")

    folder = args.ordner
    times, report = read_capture(folder)
    if not times:
        print("Keine Bilder in", folder)
        return 1
    pauses = sorted(report.get("pausen", []), key=lambda p: p["start_s"])
    starts = [p["start_s"] for p in pauses]
    first = Image.open(frame_path(folder, 0))
    size = first.size
    stamper = Stamper(size[0])
    out = args.out or os.path.join(folder, "echtzeit.avi")
    duration = times[-1] + 0.5
    total = int(duration * args.fps)
    limit = int(args.max_mb * 1048576)
    encoder = FrameEncoder(folder, times, pauses, starts, stamper, size, args.quality)

    # Größe vorher schätzen: gleichmäßig verteilte Probebilder kodieren (jedes Filmbild wird
    # geschrieben, auch ein wiederholtes – nur das Kodieren entfällt).
    samples = min(total, 40)
    sample_bytes = [len(encoder.jpeg((n + 0.5) * duration / samples)[0]) for n in range(samples)]
    mean = sum(sample_bytes) / float(len(sample_bytes))
    estimate = 8192 + total * (mean + 8 + 1 + 16)
    parts = 1 if estimate <= limit else int(-(-estimate // (limit * 0.95)))
    print("Schätzung: %d Filmbilder × %s KB ≈ %s MB (Grenze je Datei %s MB) → %d Datei%s"
          % (total, num(mean / 1024.0, 1), num(estimate / 1048576.0, 1), num(limit / 1048576.0, 1),
             parts, "" if parts == 1 else "en"))
    if parts > 1 and args.nicht_teilen:
        print("Abbruch: Film wäre größer als %s MB (--nicht-teilen)." % num(limit / 1048576.0, 1))
        return 2
    per_part = -(-total // parts)
    encoder.encoded = encoder.reused = 0

    outputs = []
    number = 1
    path = part_path(out, number, parts)
    writer = AviWriter(path, size[0], size[1], args.fps)
    in_part = 0
    used = set()
    for n in range(total):
        t = n / float(args.fps)
        jpeg, k = encoder.jpeg(t)
        used.add(k)
        if in_part > 0 and (in_part >= per_part or writer.projected(len(jpeg)) > limit):
            writer.close()
            outputs.append(path)
            number += 1
            path = part_path(out, number, max(parts, number))
            writer = AviWriter(path, size[0], size[1], args.fps)
            in_part = 0
        writer.add(jpeg)
        in_part += 1
        if n % 250 == 0:
            print("  Filmbild %d / %d" % (n, total))
    writer.close()
    outputs.append(path)

    all_ok = True
    total_bytes = 0
    total_seconds = 0.0
    for path in outputs:
        info = check_avi(path)
        too_big = info["datei_bytes"] > limit
        ok = info["ok"] and not too_big
        all_ok = all_ok and ok
        total_bytes += info["datei_bytes"]
        total_seconds += info.get("dauer_s", 0.0)
        print("Film: %s" % path)
        print("  %d Bilder, %s Bilder/s, %s s, %s MB" % (info.get("bilder_avih", 0), num(info.get("bilder_je_s", 0), 0),
                                                       num(info.get("dauer_s", 0), 2), num(info["datei_bytes"] / 1048576.0, 1)))
        print("  Prüfung: %s %s" % ("in Ordnung" if ok else "FEHLER",
                                    "; ".join(info["probleme"] + (["größer als die Grenze"] if too_big else []))))
    print("Zusammen: %d Datei%s, %s s, %s MB; %d Filmbilder kodiert, %d wiederverwendet; %d von %d aufgenommenen Bildern verwendet"
          % (len(outputs), "" if len(outputs) == 1 else "en", num(total_seconds, 2), num(total_bytes / 1048576.0, 1),
             encoder.encoded, encoder.reused, len(used), len(times)))
    print("  Rechenpausen (ab %s ms): %d, zusammen %s s; längste %s s" % (
        num(report.get("pause_ab_ms", 0), 0), len(pauses), num(sum(p["duration_s"] for p in pauses), 2),
        num(max((p["duration_s"] for p in pauses), default=0.0), 2)))
    for p in pauses:
        print("    %6s s  %5s s  %s" % (num(p["start_s"], 2), num(p["duration_s"], 2), p.get("ursache", "")))
    hitches = report.get("ruckler")
    if isinstance(hitches, dict):
        print("  Ruckler (%s–%s ms): %d, zusammen %s s, davon beim Malen %d" % (
            num(hitches["bereich_ms"][0], 0), num(hitches["bereich_ms"][1], 0), hitches["anzahl"],
            num(hitches["gesamt_s"], 2), hitches.get("beim_malen", 0)))
        for h in hitches.get("groesste", [])[:8]:
            print("    %6s s  %5s ms  %s (%s)" % (num(h["start_s"], 2), num(h["dauer_ms"], 1), h["handlung"], h["zustand"]))
    if args.kontaktbogen:
        picks = contact_sheet(folder, times, pauses, starts, stamper, size, duration, args.kontaktbogen)
        print("Kontaktbogen: %s (%d Bilder)" % (args.kontaktbogen, len(picks)))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
