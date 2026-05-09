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

echo "[2/4] Building .dmg..."
DMG_SRC="$(mktemp -d -t teiscanner-dmg)"
ditto "$APP_PATH" "$DMG_SRC/$SCHEME.app"
ln -s /Applications "$DMG_SRC/Applications"
ICNS_SRC="$APP_PATH/Contents/Resources/AppIcon.icns"
HDIUTIL_VOLICON_ARGS=()
if [[ -f "$ICNS_SRC" ]]; then
  HDIUTIL_VOLICON_ARGS=(-volicon "$ICNS_SRC")
fi
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "$DMG_SRC" \
  "${HDIUTIL_VOLICON_ARGS[@]}" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$DMG_SRC"
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

echo
echo "Done."
echo "  Notarized .dmg: $DMG_PATH"
xcrun stapler validate "$DMG_PATH" || true
spctl -a -vv "$APP_PATH" 2>&1 | sed 's/^/  app: /' || true
