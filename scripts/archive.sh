#!/usr/bin/env bash
# Archive the app for distribution.
# Regenerates the Xcode project via xcodegen, then archives Release config.
#
# Usage:
#   scripts/archive.sh                # Archive only
#   scripts/archive.sh --appstore     # Archive + export Mac App Store .pkg + upload
#   scripts/archive.sh --devid        # Archive + export Developer ID .app + notarize
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="TEIScanner"
PROJECT="$PWD/$SCHEME.xcodeproj"
ARCHIVE_DIR="$PWD/build"
ARCHIVE_PATH="$ARCHIVE_DIR/$SCHEME.xcarchive"

echo "[1/3] Regenerating Xcode project..."
if command -v xcodegen >/dev/null; then
  xcodegen generate
else
  echo "  xcodegen not found, skipping (using existing $PROJECT)"
fi

echo "[2/3] Cleaning previous archive..."
rm -rf "$ARCHIVE_PATH"
mkdir -p "$ARCHIVE_DIR"

echo "[3/3] Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -quiet

echo
echo "Archive: $ARCHIVE_PATH"

case "${1:-}" in
  --appstore)
    bash "$(dirname "$0")/export-appstore.sh"
    ;;
  --devid)
    bash "$(dirname "$0")/export-devid.sh"
    ;;
  "")
    echo "Done. Run with --appstore or --devid to export and ship."
    ;;
  *)
    echo "unknown flag: $1" >&2
    exit 2
    ;;
esac
