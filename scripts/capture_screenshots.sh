#!/usr/bin/env bash
# Build the .app and have it self-snapshot in four states.
#
# Outputs to docs/screenshots/:
#   01-empty.png       — empty drop-zone state
#   02-loaded.png      — folder loaded, OCR not yet run
#   03-ocr-done.png    — OCR finished, image preview with bbox overlay
#   04-xml.png         — TEI/XML preview tab
#
# Uses the app's own --screenshot launch arg to capture its content view —
# no Screen Recording permission required.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="TEIScanner"
SAMPLE_DIR="$(cd docs/sample-pages && pwd)"
OUT_DIR="$(cd docs && pwd)/screenshots"
DD="/tmp/teiscanner-dd"

mkdir -p "$OUT_DIR"
[[ -d "$SAMPLE_DIR" ]] || python3 scripts/make_sample.py

echo "[1/2] Build .app..."
xcodegen generate >/dev/null
xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" \
  -configuration Debug -destination "platform=macOS" \
  -derivedDataPath "$DD" build -quiet

APP="$DD/Build/Products/Debug/$SCHEME.app"
BIN="$APP/Contents/MacOS/$SCHEME"
[[ -x "$BIN" ]] || { echo "build failed: $BIN not found" >&2; exit 1; }

shoot() {
  local out="$1"; shift
  echo "  → $out"
  "$BIN" --screenshot - "$@" 2>/dev/null > "$out" || true
  if [[ ! -s "$out" ]]; then
    echo "    (empty output, capture may have failed)" >&2
    rm -f "$out"
  fi
}

echo "[2/2] Capture..."

# 1. Empty drop zone
shoot "$OUT_DIR/01-empty.png" --screenshot-delay 1.5

# 2. Folder loaded, pre-OCR
shoot "$OUT_DIR/02-loaded.png" \
  --demo-folder "$SAMPLE_DIR" \
  --screenshot-delay 2.0

# 3. OCR done (let two pages finish). Note: --auto-run-ocr must come last —
# placing it between --demo-folder and --screenshot-delay prevented the view
# from rendering in testing.
shoot "$OUT_DIR/03-ocr-done.png" \
  --demo-folder "$SAMPLE_DIR" \
  --screenshot-delay 8.0 \
  --auto-run-ocr

# 4. TEI/XML view
shoot "$OUT_DIR/04-xml.png" \
  --demo-folder "$SAMPLE_DIR" \
  --show-tab xml \
  --screenshot-delay 8.0 \
  --auto-run-ocr

echo
echo "Screenshots written to $OUT_DIR:"
ls -la "$OUT_DIR"
