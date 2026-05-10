#!/usr/bin/env bash
# Export the archive as a Developer ID-signed .app, package as .dmg,
# then notarize and staple the .dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

# Load .env
[[ -f .env ]] && set -a && source .env && set +a

SCHEME="TEIScanner"
ARCHIVE_PATH="build/$SCHEME.xcarchive"
EXPORT_PATH="build/Export/DeveloperID"
OPTIONS="exportOptions/DeveloperID.plist"
KEY_PATH="$HOME/.private_keys/AuthKey_${APP_STORE_API_KEY}.p8"

[[ -d "$ARCHIVE_PATH" ]] || { echo "Archive not found. Run scripts/archive.sh first." >&2; exit 1; }
[[ -f "$KEY_PATH" ]] || { echo "API key not found at $KEY_PATH" >&2; exit 1; }

rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

echo "[1/4] Exporting .app..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates \
  -quiet

APP_PATH="$EXPORT_PATH/$SCHEME.app"
DMG_PATH="$EXPORT_PATH/$SCHEME.dmg"
[[ -d "$APP_PATH" ]] || { echo "App not exported" >&2; exit 1; }

echo "[2/4] Building .dmg via create-dmg..."
ICNS_SRC="$APP_PATH/Contents/Resources/AppIcon.icns"
BG_PNG="$PWD/docs/dmg-background.png"
rm -f "$DMG_PATH"

CREATE_DMG_ARGS=(
  --volname "${APP_NAME}"
  --window-pos 200 120
  --window-size 600 400
  --icon-size 120
  --icon "$SCHEME.app" 150 200
  --hide-extension "$SCHEME.app"
  --app-drop-link 450 200
  --no-internet-enable
)
if [[ -f "$ICNS_SRC" ]]; then
  CREATE_DMG_ARGS+=(--volicon "$ICNS_SRC")
fi
if [[ -f "$BG_PNG" ]]; then
  CREATE_DMG_ARGS+=(--background "$BG_PNG")
fi
create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_PATH" "$APP_PATH" >/dev/null
echo "  Built: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

echo "[3/4] Submitting .dmg to notary service..."
xcrun notarytool submit "$DMG_PATH" \
  --key "$KEY_PATH" \
  --key-id "$APP_STORE_API_KEY" \
  --issuer "$APP_STORE_API_ISSUER" \
  --wait

echo "[4/4] Stapling ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler staple "$APP_PATH"

# Set the .dmg file's own Finder icon to the app icon, so the file shown
# in the user's Downloads folder picks up the brand. Skipped silently if
# `fileicon` (Homebrew) is not installed.
if command -v fileicon >/dev/null && [[ -f "$ICNS_SRC" ]]; then
  fileicon set "$DMG_PATH" "$ICNS_SRC" >/dev/null
fi

echo
echo "Done."
echo "  Notarized .dmg: $DMG_PATH"
xcrun stapler validate "$DMG_PATH" || true
spctl -a -vv "$APP_PATH" 2>&1 | sed 's/^/  app: /' || true
