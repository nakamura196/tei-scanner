#!/usr/bin/env python3
"""Generate a 600x400 background PNG for the .dmg installer window.

Outputs to docs/dmg-background.png. Re-run if you change the look.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont


OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "docs"
)
OUT_PATH = os.path.join(OUT_DIR, "dmg-background.png")
OUT_PATH_2X = os.path.join(OUT_DIR, "dmg-background@2x.png")


def make_bg(width: int, height: int) -> Image.Image:
    img = Image.new("RGB", (width, height), "#F5F1E8")  # warm cream
    d = ImageDraw.Draw(img)

    # Subtle radial-ish gradient via concentric rings of darker cream
    cx, cy = width / 2, height / 2
    max_d = (cx ** 2 + cy ** 2) ** 0.5
    for y in range(height):
        for_x_step = max(1, width // 200)
        for x in range(0, width, for_x_step):
            d_to_center = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            t = d_to_center / max_d
            r = int(245 - t * 18)
            g = int(241 - t * 22)
            b = int(232 - t * 30)
            d.line([(x, y), (x + for_x_step, y)], fill=(r, g, b))

    # Drag arrow between app icon (left) and Applications (right)
    arrow_color = (170, 145, 110, 255)
    arrow_y = int(height * 0.5)
    arrow_x_start = int(width * 0.40)
    arrow_x_end = int(width * 0.60)
    d.line([(arrow_x_start, arrow_y), (arrow_x_end, arrow_y)],
           fill=arrow_color, width=max(2, width // 300))
    head = max(8, width // 75)
    d.polygon(
        [(arrow_x_end, arrow_y),
         (arrow_x_end - head, arrow_y - head),
         (arrow_x_end - head, arrow_y + head)],
        fill=arrow_color
    )

    # Footer label
    try:
        font = ImageFont.truetype(
            "/System/Library/Fonts/Supplemental/Avenir Next.ttc", max(11, width // 50))
    except OSError:
        font = ImageFont.load_default()
    label = "Drag TEI Scanner into Applications"
    bbox = d.textbbox((0, 0), label, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    d.text(((width - tw) / 2, height - th - max(12, height // 25)),
           label, font=font, fill=(110, 90, 60))

    return img


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    make_bg(600, 400).save(OUT_PATH, "PNG", optimize=True)
    make_bg(1200, 800).save(OUT_PATH_2X, "PNG", optimize=True)
    print(f"Wrote {OUT_PATH} and {OUT_PATH_2X}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
