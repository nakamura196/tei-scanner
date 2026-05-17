#!/usr/bin/env bash
# Cut a GitHub release end to end:
#   archive -> Developer ID export + notarized .dmg -> tag -> publish release.
#
# The version is read from project.yml (MARKETING_VERSION); the tag is
# `v<version>`. Bump the version and commit before running this.
#
# Prerequisites:
#   - A "Developer ID Application" certificate in the login keychain.
#   - .env + ~/.private_keys/AuthKey_<APP_STORE_API_KEY>.p8 (for notarization).
#   - gh authenticated (`gh auth status`).
#   - Working tree clean; HEAD pushed to origin.
#
# Usage:
#   scripts/release.sh            # build, tag, publish
#   scripts/release.sh --dry-run  # build only, no tag, no publish
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

VERSION=$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
[[ -n "$VERSION" ]] || { echo "Could not read MARKETING_VERSION from project.yml" >&2; exit 1; }
TAG="v$VERSION"
DMG="build/Export/DeveloperID/TEIScanner.dmg"

echo "Release $TAG"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Working tree has uncommitted changes — commit or stash first." >&2
  exit 1
fi
if [[ -z "$DRY_RUN" ]] && git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists." >&2
  exit 1
fi

echo "[1/3] Archiving + exporting a notarized .dmg ..."
scripts/archive.sh --devid
[[ -f "$DMG" ]] || { echo "Expected .dmg not found at $DMG" >&2; exit 1; }

if [[ -n "$DRY_RUN" ]]; then
  echo
  echo "Dry run. Built: $DMG"
  echo "Re-run without --dry-run to tag $TAG and publish the release."
  exit 0
fi

echo "[2/3] Tagging $TAG ..."
git tag -a "$TAG" -m "TEI Scanner $TAG"
git push origin "$TAG"

echo "[3/3] Publishing the GitHub release ..."
gh release create "$TAG" "$DMG" \
  --title "$TAG" \
  --generate-notes \
  --verify-tag

echo
echo "Released: $(gh release view "$TAG" --json url -q .url)"
echo "Tip: edit the release notes on GitHub if you want a curated summary."
