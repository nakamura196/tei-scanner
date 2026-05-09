#!/usr/bin/env bash
# Export the archive as a Mac App Store .pkg, then upload to App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."

# Load .env
[[ -f .env ]] && set -a && source .env && set +a

SCHEME="TEIScanner"
ARCHIVE_PATH="build/$SCHEME.xcarchive"
EXPORT_PATH="build/Export/AppStore"
OPTIONS="exportOptions/AppStore.plist"

[[ -d "$ARCHIVE_PATH" ]] || { echo "Archive not found. Run scripts/archive.sh first." >&2; exit 1; }
mkdir -p "$EXPORT_PATH"

echo "[1/2] Exporting .pkg..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates \
  -quiet

PKG_FILE=$(find "$EXPORT_PATH" -maxdepth 1 -name "*.pkg" | head -1)
[[ -n "$PKG_FILE" ]] || { echo "No .pkg produced" >&2; exit 1; }
echo "  Exported: $PKG_FILE"

if [[ "${1:-}" == "--no-upload" ]]; then
  echo "Skipping upload (--no-upload)."
  exit 0
fi

echo "[2/2] Uploading to App Store Connect..."
xcrun altool --upload-app \
  --type macos \
  --file "$PKG_FILE" \
  --apiKey "$APP_STORE_API_KEY" \
  --apiIssuer "$APP_STORE_API_ISSUER"

echo
echo "Upload complete. Build will appear in App Store Connect after processing (~5-30 min)."
