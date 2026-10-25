#!/usr/bin/env python3
"""Draw the demo-mode art (launch with -MNDemoMode YES): box art tiles and the stream still.

All of it is MoonLume's own drawing (Eclipse style: dark ground, one accent, a simple
geometric motif and the game's name). No logos or official artwork.

    python3 tools/gen-demo-art.py [--font /path/to/Manrope.ttf] [--boxart-dir DIR]

Writes into Limelight/Images.xcassets/DemoArt/:
  DemoArt-<App>.imageset   box art for the demo PC's apps (600x800)
  DemoStreamFrame.imageset the still shown as the "video" on the demo stream screen (1920x1080)

To use a real captured frame instead of the placeholder, replace the PNG inside
DemoStreamFrame.imageset (keep the asset name DemoStreamFrame; any 16:9 PNG works, and if
the file name changes, update that imageset's Contents.json). Don't rerun this script
afterwards, or pass --no-frame.

--boxart-dir also writes the tiles as plain 600x800 PNGs (<name>.png), e.g. to use as
Sunshine box art on a real host.
"""
import argparse
import json
import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Limelight" / "Images.xcassets" / "DemoArt"
FONTS = [
    pathlib.Path.home() / "projects/glassfin-shots/fonts/Manrope.ttf",
    pathlib.Path("/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"),
]
SS = 3  # supersampling

ACCENT = (0x8A, 0xB4, 0xFF)
TEXT = (0xF2, 0xF2, 0xF2)

# app name -> (asset suffix, motif, tint)
APPS = {
    "Desktop": ("Desktop", "desktop", (0x8A, 0xB4, 0xFF)),
    "SuperTuxKart": ("SuperTuxKart", "track", (0xFF, 0xB8, 0x6B)),
    "Xonotic": ("Xonotic", "reticle", (0x7D, 0xE3, 0xC8)),
    "0 A.D.": ("0AD", "sun", (0xF0, 0xC8, 0x7A)),
}


def font(path, size):
    f = ImageFont.truetype(str(path), size)
    try:
        f.set_variation_by_axes([800])  # Manrope is a variable font
    except Exception:
        pass
    return f


def vgradient(w, h, top, bottom):
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(h - 1, 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return im


def glow(size, center, radius, color, alpha):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.6))


def motif(d, kind, W, H, tint):
    line = tuple(tint) + (230,)
    soft = tuple(tint) + (70,)
    s = W / 600
    cx, cy = W / 2, H * 0.40
    w = round(10 * s)
    if kind == "desktop":
        # A monitor with three windows
        x0, y0, x1, y1 = cx - 170 * s, cy - 110 * s, cx + 170 * s, cy + 100 * s
        d.rounded_rectangle([x0, y0, x1, y1], radius=22 * s, outline=line, width=w)
        d.line([(cx, y1), (cx, y1 + 50 * s)], fill=line, width=w)
        d.rounded_rectangle([cx - 80 * s, y1 + 45 * s, cx + 80 * s, y1 + 60 * s], radius=8 * s, fill=line)
        d.rounded_rectangle([x0 + 40 * s, y0 + 40 * s, cx + 10 * s, cy + 10 * s], radius=10 * s, fill=soft)
        d.rounded_rectangle([cx + 30 * s, y0 + 40 * s, x1 - 40 * s, cy - 20 * s], radius=10 * s, fill=soft)
        d.rounded_rectangle([cx - 30 * s, cy + 30 * s, x1 - 40 * s, y1 - 30 * s], radius=10 * s, fill=soft)
    elif kind == "track":
        # A racing line: a stadium-shaped track with chevrons
        for i, inset in enumerate((0, 46)):
            r = (150 - inset) * s
            d.rounded_rectangle([cx - 210 * s + inset * s, cy - 150 * s + inset * s,
                                 cx + 210 * s - inset * s, cy + 150 * s - inset * s],
                                radius=r, outline=line if i == 0 else soft, width=w)
        for k in range(3):
            x = cx - 60 * s + k * 50 * s
            d.line([(x, cy - 40 * s), (x + 34 * s, cy), (x, cy + 40 * s)], fill=line, width=w, joint="curve")
        # start line squares
        for k in range(4):
            for j in range(2):
                if (k + j) % 2 == 0:
                    x, y = cx - 23 * s + j * 23 * s, cy - 150 * s + 2 * s + k * 11.5 * s
                    d.rectangle([x, y, x + 23 * s, y + 11.5 * s], fill=line)
    elif kind == "reticle":
        # A hexagon with a crosshair
        R = 170 * s
        hexagon = [(cx + R * math.cos(math.radians(60 * i + 30)), cy + R * math.sin(math.radians(60 * i + 30))) for i in range(6)]
        d.polygon(hexagon, outline=line, width=w)
        d.ellipse([cx - 80 * s, cy - 80 * s, cx + 80 * s, cy + 80 * s], outline=soft, width=w)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            d.line([(cx + dx * 30 * s, cy + dy * 30 * s), (cx + dx * 120 * s, cy + dy * 120 * s)], fill=line, width=w)
        d.ellipse([cx - 9 * s, cy - 9 * s, cx + 9 * s, cy + 9 * s], fill=line)
    elif kind == "sun":
        # A low sun over terraced ground
        r = 100 * s
        d.ellipse([cx - r, cy - r - 20 * s, cx + r, cy + r - 20 * s], outline=line, width=w)
        for k, half in enumerate((230, 175, 120)):
            y = cy + 70 * s + k * 42 * s
            d.line([(cx - half * s, y), (cx + half * s, y)], fill=line if k == 0 else soft, width=w)
        d.polygon([(cx - 70 * s, cy + 70 * s), (cx, cy - 10 * s), (cx + 70 * s, cy + 70 * s)], fill=soft)


def box_art(name, kind, tint, font_path):
    W, H = 600 * SS, 800 * SS
    im = vgradient(W, H, (0x17, 0x17, 0x1D), (0x08, 0x08, 0x0B)).convert("RGBA")
    im = Image.alpha_composite(im, glow((W, H), (W / 2, H * 0.40), 230 * SS, tint, 40))
    d = ImageDraw.Draw(im)
    motif(d, kind, W, H, tint)
    # Eclipse accent rule along the top
    d.rectangle([0, 0, W, 6 * SS], fill=ACCENT + (150,))
    # The name, bottom-left, shrunk to fit
    size = 92 * SS
    while True:
        f = font(font_path, size)
        if d.textlength(name, font=f) <= W - 2 * 48 * SS or size <= 40 * SS:
            break
        size -= 4 * SS
    d.text((48 * SS, H - 64 * SS), name, font=f, fill=TEXT + (255,), anchor="ls")
    d.rectangle([48 * SS, H - 44 * SS, 48 * SS + 64 * SS, H - 38 * SS], fill=tuple(tint) + (255,))
    return im.resize((600, 800), Image.LANCZOS).convert("RGB")


def stream_frame():
    # An abstract night drive: gradient sky, a glow on the horizon, layered ridges and a road
    W, H = 1920 * 2, 1080 * 2
    im = vgradient(W, H, (0x0A, 0x0E, 0x22), (0x2A, 0x1A, 0x3A)).convert("RGBA")
    horizon = H * 0.58
    im = Image.alpha_composite(im, glow((W, H), (W * 0.5, horizon), 700, (0xFF, 0x9A, 0x6B), 170))
    im = Image.alpha_composite(im, glow((W, H), (W * 0.5, horizon), 300, (0xFF, 0xD0, 0x9A), 200))
    d = ImageDraw.Draw(im)
    # stars
    rng = random.Random(7)
    for i in range(160):
        x, y = rng.uniform(0, W), rng.uniform(0, horizon * 0.8)
        r = rng.uniform(1.5, 4)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, rng.randint(50, 200)))
    # ridges, back to front
    ridges = [
        ((0x2B, 0x22, 0x4A), 0.50, 260, 3),
        ((0x1C, 0x17, 0x34), 0.55, 200, 5),
        ((0x10, 0x0E, 0x20), 0.60, 150, 7),
    ]
    for color, base, amp, freq in ridges:
        pts = [(0, H)]
        for k in range(0, 101):
            x = W * k / 100
            y = H * base - amp * (0.5 + 0.5 * math.sin(k / 100 * freq * math.pi + base * 10)) * (0.6 + 0.4 * math.sin(k * 0.37))
            pts.append((x, y))
        pts.append((W, H))
        d.polygon(pts, fill=color + (255,))
    # ground and road in perspective
    d.rectangle([0, horizon, W, H], fill=(0x07, 0x07, 0x10, 255))
    vx, vy = W * 0.5, horizon
    d.polygon([(vx - 20, vy), (vx + 20, vy), (W * 0.92, H), (W * 0.08, H)], fill=(0x16, 0x16, 0x24, 255))
    for side in (-1, 1):
        d.line([(vx + side * 20, vy), (W * 0.5 + side * W * 0.42, H)], fill=(0x8A, 0xB4, 0xFF, 200), width=10)
    # dashed centre line
    for k in range(9):
        t0 = (k / 9) ** 2
        t1 = ((k + 0.5) / 9) ** 2
        y0, y1 = vy + (H - vy) * t0, vy + (H - vy) * t1
        w0, w1 = 4 + 30 * t0, 4 + 30 * t1
        d.polygon([(vx - w0, y0), (vx + w0, y0), (vx + w1, y1), (vx - w1, y1)], fill=(0xFF, 0xE0, 0xA0, 220))
    return im.resize((1920, 1080), Image.LANCZOS).convert("RGB")


def imageset(name, image):
    folder = OUT / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"idiom": "universal", "filename": f"{name}.png"}],
        "info": {"version": 1, "author": "xcode"},
    }, indent=2) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", type=pathlib.Path, default=next((f for f in FONTS if f.exists()), None))
    ap.add_argument("--boxart-dir", type=pathlib.Path)
    ap.add_argument("--no-frame", action="store_true", help="keep the existing DemoStreamFrame")
    args = ap.parse_args()
    if args.font is None:
        ap.error("no font found: pass --font")

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    for name, (suffix, kind, tint) in APPS.items():
        art = box_art(name, kind, tint, args.font)
        assert art.size == (600, 800)
        imageset(f"DemoArt-{suffix}", art)
        if args.boxart_dir:
            args.boxart_dir.mkdir(parents=True, exist_ok=True)
            art.save(args.boxart_dir / f"{suffix}.png", optimize=True)
    if not args.no_frame:
        frame = stream_frame()
        assert frame.size == (1920, 1080)
        imageset("DemoStreamFrame", frame)


if __name__ == "__main__":
    main()
