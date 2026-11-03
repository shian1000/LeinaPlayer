#!/usr/bin/env python3
"""Draws the Leina Player icon and writes every size Android and iOS need.

Run from the repo root: `python3 tool/generate_icons.py` (needs Pillow). The design: a flat azure
play triangle on a near-black blue, with the old Leina Radio icon's "((•))" broadcast sign cut
out of it.
"""
import colorsys
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw

RES = "android/app/src/main/res"
IOS = "ios/Runner/Assets.xcassets/AppIcon.appiconset"


def hsv(h, s, v):
    return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h / 360, s, v))


BACKGROUND = hsv(200, 0.67, 0.13)
AZURE = hsv(200, 0.59, 0.92)
WHITE = (255, 255, 255)


def glyph_mask(size, height):
    """The triangle with the sign cut out, as a mask; [height] = the triangle's share of [size]."""
    big = size * 4
    layer = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(layer)
    h = big * height
    w = h * math.sqrt(3) / 2
    cx, cy = big / 2 + w * 0.08, big / 2  # a triangle's weight is on its left: nudge it right
    pts = [(cx - w / 2, cy - h / 2), (cx - w / 2, cy + h / 2), (cx + w / 2, cy)]
    corner = h * 0.067
    d.polygon(pts, fill=255)
    d.line(pts + [pts[0]], fill=255, width=round(corner * 2), joint="curve")
    for x, y in pts:
        d.ellipse([x - corner, y - corner, x + corner, y + corner], fill=255)

    # The sign sits on the triangle's incircle, a third of the way from its flat side.
    cut = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(cut)
    sx, sy = cx - w / 2 + w / 3, cy
    unit = h * 0.31  # half the sign's width
    dot = unit * 0.17
    d.ellipse([sx - dot, sy - dot, sx + dot, sy + dot], fill=255)
    for radius in (0.45, 0.80):
        r = unit * radius
        for start in (-50, 130):  # right and left arcs
            d.arc([sx - r, sy - r, sx + r, sy + r], start, start + 100, fill=255,
                  width=round(unit * 0.16))
    return ImageChops.subtract(layer, cut).resize((size, size), Image.LANCZOS)


def glyph(size, height, color):
    out = Image.new("RGBA", (size, size), color + (0,))
    out.putalpha(glyph_mask(size, height))
    return out


def full_icon(size):
    icon = Image.new("RGBA", (size, size), BACKGROUND + (255,))
    return Image.alpha_composite(icon, glyph(size, 0.52, AZURE))


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def main():
    master = full_icon(1024)

    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    # Legacy launcher icon (Android < 8): the whole square, rounded slightly.
    for name, k in densities.items():
        size = round(48 * k)
        icon = master.resize((size, size), Image.LANCZOS)
        rounded = Image.new("L", (size, size), 0)
        ImageDraw.Draw(rounded).rounded_rectangle(
            [0, 0, size - 1, size - 1], radius=size * 0.18, fill=255
        )
        icon.putalpha(ImageChops.multiply(icon.getchannel("A"), rounded))
        save(icon, f"{RES}/mipmap-{name}/ic_launcher.png")

        # Adaptive icon layers (Android 8+): 108dp, of which a ~72dp circle shows; the
        # triangle keeps the full icon's proportion of it and stays inside the 66dp safe zone.
        fg = round(108 * k)
        height = 0.52 * 72 / 108
        save(glyph(fg, height, AZURE), f"{RES}/mipmap-{name}/ic_launcher_foreground.png")
        save(
            Image.new("RGB", (fg, fg), BACKGROUND),
            f"{RES}/mipmap-{name}/ic_launcher_background.png",
        )
        # Themed icon (Android 13+): the launcher tints this shape itself.
        save(glyph(fg, height, WHITE), f"{RES}/mipmap-{name}/ic_launcher_monochrome.png")

        # Notification small icon: white on transparent, 24dp.
        stat = round(24 * k)
        save(glyph(stat, 0.80, WHITE), f"{RES}/drawable-{name}/ic_stat_leina.png")

    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n"
    )
    os.makedirs(f"{RES}/mipmap-anydpi-v26", exist_ok=True)
    with open(f"{RES}/mipmap-anydpi-v26/ic_launcher.xml", "w") as f:
        f.write(adaptive)

    # iOS: every size listed in the asset catalog, without transparency.
    with open(f"{IOS}/Contents.json") as f:
        images = json.load(f)["images"]
    for image in images:
        points = float(image["size"].split("x")[0])
        px = round(points * int(image["scale"].rstrip("x")))
        save(
            master.resize((px, px), Image.LANCZOS).convert("RGB"),
            f"{IOS}/{image['filename']}",
        )


if __name__ == "__main__":
    main()
