#!/usr/bin/env bash
# Ship a Mac App Store update end to end:
#   archive + .pkg upload  ->  wait for build processing  ->  ensure the
#   App Store version exists  ->  metadata  ->  attach build + screenshots
#   ->  review details  ->  (optionally) submit for review.
#
# The version / build numbers are read from project.yml (MARKETING_VERSION
# and CURRENT_PROJECT_VERSION). Bump them and commit before running this.
#
# Prerequisites:
#   - An "Apple Distribution" certificate + Mac App Store provisioning.
#   - .env + ~/.private_keys/AuthKey_<APP_STORE_API_KEY>.p8.
#   - The ASC app record already exists (see scripts/asc_register.py).
#   - App Privacy data declarations set once in the App Store Connect web
#     UI — the API does not cover them.
#
# Usage:
#   scripts/release-appstore.sh               # everything except the submit
#   scripts/release-appstore.sh --submit      # also submit for review
#   scripts/release-appstore.sh --skip-build  # resume: the build is already
#                                             #   uploaded, skip archive/upload
set -euo pipefail
cd "$(dirname "$0")/.."

SUBMIT=""
SKIP_BUILD=""
for arg in "$@"; do
  case "$arg" in
    --submit) SUBMIT=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

VERSION=$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION:' project.yml \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
[[ -n "$VERSION" && -n "$BUILD" ]] || {
  echo "Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml" >&2
  exit 1
}

echo "App Store release: $VERSION (build $BUILD)"

if [[ -z "$SKIP_BUILD" ]]; then
  echo "[1/6] Archiving + exporting .pkg + uploading to App Store Connect ..."
  scripts/archive.sh --appstore
else
  echo "[1/6] Skipping archive/upload (--skip-build) — using the build already on ASC."
fi

echo "[2/6] Waiting for build $BUILD to finish processing ..."
python3 scripts/asc_wait_build.py "$BUILD" 45

echo "[3/6] Ensuring the App Store version $VERSION exists ..."
python3 scripts/asc_version.py "$VERSION"

echo "[4/6] Setting metadata (description / whatsNew / categories / ...) ..."
python3 scripts/asc_metadata.py

echo "[5/6] Attaching the build + encryption compliance + screenshots ..."
python3 scripts/asc_build_and_screenshots.py

echo "[6/6] Review details ..."
if [[ -n "$SUBMIT" ]]; then
  python3 scripts/asc_review.py --submit
  echo
  echo "Submitted $VERSION for App Store review."
else
  python3 scripts/asc_review.py
  echo
  echo "Everything is staged but NOT submitted. Confirm App Privacy is set in"
  echo "the web UI, then re-run with --submit (or submit from App Store Connect)."
fi
