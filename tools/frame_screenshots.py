#!/usr/bin/env python3
"""Frames raw simulator screenshots for the App Store.

Takes the captures from tools/screenshots.sh and puts each one on a branded
background under a short caption, at exactly the size App Store Connect wants:

    iPhone 6.9"   1320x2868
    iPad 13"      2064x2752

    python3 tools/frame_screenshots.py ~/Desktop/AlarmDM-screenshots

Writes into a `framed/` folder next to the originals. Captions live in
CAPTIONS below, keyed by file name.
"""

import sys
import pathlib
from PIL import Image, ImageDraw, ImageFont

BRAND = (78, 154, 183)          # #4E9AB7, the app's blue
INK = (25, 32, 38)              # near-black for the caption
DEVICE_BEZEL = (18, 20, 22)

CAPTIONS = {
    "01-radio": "Radio uživo,\nceo dan",
    "02-emisije": "Sve emisije\nna jednom mestu",
    "03-player": "Preuzmi i slušaj\nbez interneta",
    "04-epizode": "Sa muzikom\nili bez nje",
    "05-podrzi": "Podrži Daška\ni Mlađu",
}

TARGETS = {
    "iphone-6.9": (1320, 2868),
    "ipad-13": (2064, 2752),
}

FONT_PATHS = [
    "/System/Library/Fonts/SFCompact.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size):
    for path in FONT_PATHS:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            continue
    return ImageFont.load_default()


def frame(shot: Image.Image, caption: str, size: tuple[int, int]) -> Image.Image:
    width, height = size
    canvas = Image.new("RGB", size, BRAND)

    # A soft vertical wash so the flat brand blue does not read as a colour swatch.
    wash = Image.new("L", (1, height))
    for y in range(height):
        wash.putpixel((0, y), int(255 - 38 * (y / height)))
    canvas = Image.composite(
        canvas, Image.new("RGB", size, (255, 255, 255)), wash.resize(size)
    )

    draw = ImageDraw.Draw(canvas)

    # Caption: a fixed band at the top, text centred within it.
    band = int(height * 0.17)
    font = load_font(int(width * 0.075))
    lines = caption.split("\n")
    line_h = int(font.size * 1.18)
    text_h = line_h * len(lines)
    y = (band - text_h) // 2 + int(height * 0.02)
    for line in lines:
        w = draw.textbbox((0, 0), line, font=font)[2]
        draw.text(((width - w) // 2, y), line, font=font, fill=(255, 255, 255))
        y += line_h

    # Screenshot: rounded corners, thin bezel, shadow, bleeding off the bottom
    # so the frame reads as a device rather than a pasted rectangle.
    side_margin = int(width * 0.09)
    shot_w = width - side_margin * 2
    shot_h = int(shot.height * (shot_w / shot.width))
    shot = shot.resize((shot_w, shot_h), Image.LANCZOS)

    radius = int(shot_w * 0.055)
    mask = Image.new("L", (shot_w, shot_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot_w, shot_h], radius, fill=255)

    bezel = int(width * 0.008)
    plate = Image.new("RGB", (shot_w + bezel * 2, shot_h + bezel * 2), DEVICE_BEZEL)
    plate_mask = Image.new("L", plate.size, 0)
    ImageDraw.Draw(plate_mask).rounded_rectangle(
        [0, 0, plate.size[0], plate.size[1]], radius + bezel, fill=255
    )
    plate.paste(shot, (bezel, bezel), mask)

    top = band + int(height * 0.015)
    canvas.paste(plate, ((width - plate.size[0]) // 2, top), plate_mask)
    return canvas


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1
                        else pathlib.Path.home() / "Desktop/AlarmDM-screenshots")
    made = 0

    for folder, size in TARGETS.items():
        src = root / folder
        if not src.is_dir():
            continue
        out = root / "framed" / folder
        out.mkdir(parents=True, exist_ok=True)

        for png in sorted(src.glob("*.png")):
            caption = CAPTIONS.get(png.stem)
            if caption is None:
                print(f"  preskočeno (nema natpisa): {png.name}")
                continue
            framed = frame(Image.open(png).convert("RGB"), caption, size)
            framed.save(out / png.name)
            print(f"  ✓ {folder}/{png.name}  {framed.size[0]}×{framed.size[1]}")
            made += 1

    print(f"\n{made} slika u {root / 'framed'}")


if __name__ == "__main__":
    main()
