#!/usr/bin/env bash
# Capture App Store-sized screenshots. Reuses the regular capture pipeline
# and pads the resulting PNGs to 2880×1800 (the largest "Mac" display type
# accepted by App Store Connect).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="$(cd docs && pwd)/asc-screenshots"
mkdir -p "$OUT_DIR"

# Capture into the regular dir first, then copy + pad.
bash scripts/capture_screenshots.sh

PAD_W=2880
PAD_H=1800
for f in docs/screenshots/0*.png; do
  base="$(basename "$f")"
  out="$OUT_DIR/$base"
  cp "$f" "$out"
  # White-pad to App Store dimensions; sips centers the original.
  sips --padToHeightWidth "$PAD_H" "$PAD_W" --padColor FFFFFF "$out" \
    --out "$out" >/dev/null
done

echo
ls -la "$OUT_DIR"
echo
sips -g pixelWidth -g pixelHeight "$OUT_DIR"/01-empty.png 2>/dev/null | tail -3
