#!/usr/bin/env python3
"""Draws the Leina Radio icon and writes every size Android and iOS need.

Run from the repo root: `python3 tool/generate_icons.py` (needs Pillow). The design: the Lain
theme's cyan "((•))" broadcast sign on its near-black navy, glowing like a CRT.
"""
import json
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

NAVY_TOP = (16, 28, 52)
NAVY_BOTTOM = (5, 8, 15)
CYAN = (92, 214, 235)
RES = "android/app/src/main/res"
IOS = "ios/Runner/Assets.xcassets/AppIcon.appiconset"


def background(size):
    """Radial navy gradient, lighter towards the top."""
    img = Image.new("RGB", (size, size), NAVY_BOTTOM)
    px = img.load()
    cx, cy, r = size * 0.5, size * 0.3, size * 0.9
    for y in range(size):
        for x in range(size):
            d = min(((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / r, 1.0)
            px[x, y] = tuple(
                round(t + (b - t) * d) for t, b in zip(NAVY_TOP, NAVY_BOTTOM)
            )
    return img


def sign(size, scale=1.0, color=CYAN, glow=True):
    """The broadcast sign on transparency; [scale] = share of the canvas it spans."""
    big = size * 4
    layer = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(layer)
    c = big / 2
    unit = big * scale / 2  # half the sign's width
    dot = unit * 0.17
    d.ellipse([c - dot, c - dot, c + dot, c + dot], fill=255)
    width = round(unit * 0.11)
    for radius in (0.42, 0.68, 0.94):
        r = unit * radius
        box = [c - r, c - r, c + r, c + r]
        for start in (-50, 130):  # right and left arcs
            d.arc(box, start, start + 100, fill=255, width=width)
    mask = layer.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), color + (0,))
    out.putalpha(mask)
    if glow:
        halo = mask.filter(ImageFilter.GaussianBlur(size * 0.03))
        halo = halo.point(lambda v: int(v * 0.7))
        glow_layer = Image.new("RGBA", (size, size), color + (0,))
        glow_layer.putalpha(halo)
        out = Image.alpha_composite(glow_layer, out)
    return out


def scanlines(img):
    """Faint CRT lines over the whole icon."""
    size = img.size[0]
    lines = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(lines)
    step = max(size // 64, 2)
    for y in range(0, size, step):
        d.line([(0, y), (size, y)], fill=18)
    dark = Image.new("RGBA", img.size, (0, 0, 0, 255))
    dark.putalpha(lines)
    return Image.alpha_composite(img.convert("RGBA"), dark)


def full_icon(size):
    icon = background(size).convert("RGBA")
    icon = Image.alpha_composite(icon, sign(size, scale=0.66))
    return scanlines(icon)


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

        # Adaptive icon layers (Android 8+): 108dp, the sign inside the 66dp safe zone.
        fg = round(108 * k)
        save(sign(fg, scale=0.44), f"{RES}/mipmap-{name}/ic_launcher_foreground.png")
        bg = background(fg)
        save(scanlines(bg), f"{RES}/mipmap-{name}/ic_launcher_background.png")
        # Themed icon (Android 13+): the launcher tints this shape itself.
        save(
            sign(fg, scale=0.44, color=(255, 255, 255), glow=False),
            f"{RES}/mipmap-{name}/ic_launcher_monochrome.png",
        )

        # Notification small icon: white on transparent, 24dp.
        stat = round(24 * k)
        save(
            sign(stat, scale=0.92, color=(255, 255, 255), glow=False),
            f"{RES}/drawable-{name}/ic_stat_leina.png",
        )

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
