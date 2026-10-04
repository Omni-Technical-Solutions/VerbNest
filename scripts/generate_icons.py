#!/usr/bin/env python3
"""Regenerate every platform app icon from assets/icon/postit_icon.svg.

Requires `rsvg-convert` (brew install librsvg) and Pillow.
Run from anywhere: python3 scripts/generate_icons.py
"""
import io
import json
import re
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/icon/postit_icon.svg"
APP = ROOT / "apps/postit_app"


def render(svg: str, size: int) -> Image.Image:
    png = subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size)],
        input=svg.encode(), capture_output=True, check=True,
    ).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


rounded = SRC.read_text()
# iOS and Android adaptive masks round the corners themselves: full-bleed square.
square = re.sub(r'rx="224"', 'rx="0"', rounded)
# macOS (Big Sur+) icon grid: 824px body centred on a 1024px transparent canvas.
inner = re.sub(r"^<svg[^>]*>|</svg>\s*$", "", rounded.strip())
mac = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
    f'<g transform="translate(100 100) scale(0.8047)">{inner}</g></svg>'
)


def save(img: Image.Image, path: Path, opaque: bool = False) -> None:
    if opaque:
        img = img.convert("RGB")
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"wrote {path.relative_to(ROOT)}")


# Shared assets
save(render(rounded, 1024), ROOT / "assets/icon/postit_icon_1024.png")
save(render(square, 1024), ROOT / "assets/icon/postit_icon_square_1024.png", opaque=True)
save(render(rounded, 512), ROOT / "assets/icon/postit_icon_512.png")

# Android legacy launcher icons
for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    save(render(rounded, size), APP / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")

# iOS: sizes come from the asset catalog; App Store requires no alpha channel.
ios_set = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for image in json.loads((ios_set / "Contents.json").read_text())["images"]:
    pts = float(image["size"].split("x")[0])
    px = round(pts * int(image["scale"].rstrip("x")))
    save(render(square, px), ios_set / image["filename"], opaque=True)

# macOS asset catalog
mac_set = APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in (16, 32, 64, 128, 256, 512, 1024):
    save(render(mac, size), mac_set / f"app_icon_{size}.png")

# Windows .ico with the standard sizes
ico_sizes = [16, 24, 32, 48, 64, 128, 256]
ico = APP / "windows/runner/resources/app_icon.ico"
render(rounded, 256).save(ico, sizes=[(s, s) for s in ico_sizes])
print(f"wrote {ico.relative_to(ROOT)}")

# Linux: installed to <bundle>/data by linux/CMakeLists.txt and set as the
# window icon by linux/runner/my_application.cc.
save(render(rounded, 256), APP / "linux/runner/resources/app_icon.png")
