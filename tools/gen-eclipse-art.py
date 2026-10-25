#!/usr/bin/env python3
"""Regenerate the on-screen gamepad art and the app icon in the Eclipse style.

Every gamepad PNG is redrawn at its existing pixel size, so OnScreenControls' layout
(which sizes buttons from the images) is unchanged.

    python3 tools/gen-eclipse-art.py --font /path/to/Inter-SemiBold.ttf
    python3 tools/gen-eclipse-art.py --icon-only
"""
import argparse
import json
import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Limelight" / "Images.xcassets"
SS = 4  # supersampling factor for anti-aliasing

FILL = (0, 0, 0, 46)          # 18% black
RING = (255, 255, 255, 90)    # 35% white
LABEL = (255, 255, 255, 217)  # 85% white
STICK = (255, 255, 255, 56)   # 22% white
ACCENT = (0x8A, 0xB4, 0xFF, 255)

LABELS = {
    "AButton": "A", "BButton": "B", "XButton": "X", "YButton": "Y",
    "L1": "L1", "L2": "L2", "L3": "L3", "R1": "R1", "R2": "R2", "R3": "R3",
    "StartButton": "Start", "SelectButton": "Select",
}
CIRCLES = {"AButton", "BButton", "XButton", "YButton", "L3", "R3"}
SHOULDERS = {"L1", "L2", "R1", "R2"}
PILLS = {"StartButton", "SelectButton"}
DPAD = {"UpButton": "up", "DownButton": "down", "LeftButton": "left", "RightButton": "right"}


def render(name, w, h, scale, font_path):
    W, H = w * SS, h * SS
    ring = 1.5 * scale * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box = [ring / 2, ring / 2, W - ring / 2 - 1, H - ring / 2 - 1]

    if name in CIRCLES or name == "StickOuter":
        side = min(W, H) - ring
        x0, y0 = (W - side) / 2, (H - side) / 2
        d.ellipse([x0, y0, x0 + side, y0 + side], fill=FILL, outline=RING, width=round(ring))
    elif name == "StickInner":
        side = min(W, H) - ring
        x0, y0 = (W - side) / 2, (H - side) / 2
        d.ellipse([x0, y0, x0 + side, y0 + side], fill=STICK, outline=RING, width=round(ring))
    elif name in PILLS:
        d.rounded_rectangle(box, radius=H / 2, fill=FILL, outline=RING, width=round(ring))
    elif name in SHOULDERS:
        d.rounded_rectangle(box, radius=min(W, H) * 0.25, fill=FILL, outline=RING, width=round(ring))
    elif name in DPAD:
        d.rounded_rectangle(box, radius=min(W, H) * 0.22, fill=FILL, outline=RING, width=round(ring))
        s = min(W, H) * 0.16
        cx, cy = W / 2, H / 2
        tri = {
            "up": [(cx, cy - s), (cx - s, cy + s * 0.7), (cx + s, cy + s * 0.7)],
            "down": [(cx, cy + s), (cx - s, cy - s * 0.7), (cx + s, cy - s * 0.7)],
            "left": [(cx - s, cy), (cx + s * 0.7, cy - s), (cx + s * 0.7, cy + s)],
            "right": [(cx + s, cy), (cx - s * 0.7, cy - s), (cx - s * 0.7, cy + s)],
        }[DPAD[name]]
        d.polygon(tri, fill=LABEL)

    label = LABELS.get(name)
    if label:
        size = H * (0.42 if name in PILLS else 0.26 if name in {"L3", "R3"} else 0.36 if name in SHOULDERS else 0.42)
        font = ImageFont.truetype(font_path, round(size))
        d.text((W / 2, H / 2), label, font=font, fill=LABEL, anchor="mm")

    return im.resize((w, h), Image.LANCZOS)


def gamepad(font_path):
    names = list(LABELS) + list(DPAD) + ["StickOuter", "StickInner"]
    for name in dict.fromkeys(names):
        folder = ASSETS / f"{name}.imageset"
        contents = json.loads((folder / "Contents.json").read_text())
        for image in contents["images"]:
            filename = image.get("filename")
            if not filename:
                continue
            path = folder / filename
            w, h = Image.open(path).size
            scale = float(image.get("scale", "1x").rstrip("x"))
            render(name, w, h, scale, font_path).save(path, optimize=True)
            print(f"{path.relative_to(ROOT)} {w}x{h} @{scale:g}x")


def icon():
    """"Lume play" (option G, picked 10/25): a crescent with three light trails behind it and a
    white play triangle in its bite, on true black. Geometry in a 100-unit square, as drawn on
    the icon-options canvas."""
    N = 1024 * SS
    u = N / 100  # one canvas unit in pixels
    im = Image.new("RGBA", (N, N), (0, 0, 0, 255))
    d = ImageDraw.Draw(im)

    def disk(cx, cy, r, fill):
        d.ellipse([(cx - r) * u, (cy - r) * u, (cx + r) * u, (cy + r) * u], fill=fill)

    def dim(c, opacity):  # the accent at an opacity, over black
        return tuple(round(v * opacity) for v in c[:3]) + (255,)

    # Crescent: the accent disk with a black disk biting out of its upper right
    disk(60, 50, 26, ACCENT)
    disk(71, 43, 23, (0, 0, 0, 255))

    # Light trails, round-capped, fading toward the back
    for x1, x2, y, opacity in ((14, 34, 40, 0.9), (20, 34, 51, 0.6), (26, 36, 62, 0.35)):
        c = dim(ACCENT, opacity)
        d.line([(x1 * u, y * u), (x2 * u, y * u)], fill=c, width=round(4 * u))
        disk(x1, y, 2, c)
        disk(x2, y, 2, c)

    # Play triangle in the bite, corners rounded by a 2.4-unit stroke
    tri = [(63, 36.5), (63, 51.5), (75.5, 44)]
    white = (0xF2, 0xF2, 0xF2, 255)
    d.polygon([(x * u, y * u) for x, y in tri], fill=white)
    for a, b in zip(tri, tri[1:] + tri[:1]):
        d.line([(a[0] * u, a[1] * u), (b[0] * u, b[1] * u)], fill=white, width=round(2.4 * u))
    for x, y in tri:
        disk(x, y, 1.2, white)
    out = im.resize((1024, 1024), Image.LANCZOS).convert("RGB")

    folder = ASSETS / "AppIcon.appiconset"
    for old in folder.glob("*.png"):
        old.unlink()
    out.save(folder / "AppIcon-1024.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    print("AppIcon-1024.png")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", help="Inter-SemiBold.ttf (or any TTF); needed unless --icon-only")
    ap.add_argument("--icon-only", action="store_true", help="only redraw the app icon")
    args = ap.parse_args()
    if not args.icon_only:
        if not args.font:
            ap.error("--font is required unless --icon-only")
        gamepad(args.font)
    icon()
