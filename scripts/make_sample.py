#!/usr/bin/env python3
"""Generate small synthetic page images for demo/screenshot use."""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SAMPLES_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "docs", "sample-pages"
)

PAGE1 = [
    "On the Composition of TEI",
    "",
    "The text is encoded in TEI P5,",
    "with one <surface> per page image",
    "and one <zone> per recognized line.",
    "",
    "Each line of text is wrapped in",
    "an <ab> element whose @facs",
    "attribute points back to the zone",
    "in the facsimile section.",
]

PAGE2 = [
    "Workflow",
    "",
    "1. Drop a folder of page images",
    "2. Pick OCR language or auto",
    "3. Run OCR on N pages",
    "4. Inspect bounding boxes",
    "5. Export TEI/XML",
    "",
    "The output validates against",
    "the official tei_all.rng schema.",
]


def render_page(lines, out_path, size=(640, 880), title_size=34, body_size=24):
    img = Image.new("RGB", size, "white")
    d = ImageDraw.Draw(img)
    title_font = ImageFont.truetype(
        "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf", title_size)
    body_font = ImageFont.truetype(
        "/System/Library/Fonts/Supplemental/Times New Roman.ttf", body_size)

    y = 70
    for i, line in enumerate(lines):
        if not line:
            y += 14
            continue
        font = title_font if i == 0 else body_font
        d.text((60, y), line, font=font, fill="black")
        y += int(font.size * 1.5)
    img.save(out_path, "PNG")


def main():
    os.makedirs(SAMPLES_DIR, exist_ok=True)
    render_page(PAGE1, os.path.join(SAMPLES_DIR, "page-01.png"))
    render_page(PAGE2, os.path.join(SAMPLES_DIR, "page-02.png"))
    print(f"Wrote sample pages to {SAMPLES_DIR}")


if __name__ == "__main__":
    sys.exit(main())
