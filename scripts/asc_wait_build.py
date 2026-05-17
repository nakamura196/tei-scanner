#!/usr/bin/env python3
"""Poll App Store Connect until the latest uploaded build is VALID.

After altool uploads a build it takes roughly 5-30 minutes to finish
processing before it can be attached to a version. This blocks until a
VALID MAC_OS build exists, then exits 0; it exits non-zero on timeout.

Usage: asc_wait_build.py [timeout_minutes]   (default 45)
"""
import sys
import time

from _asc import BUNDLE_ID, request


def get_app_id() -> str:
    _, data = request("GET", f"apps?filter[bundleId]={BUNDLE_ID}")
    items = data.get("data") or []
    if not items:
        raise SystemExit(f"App record for {BUNDLE_ID} not found in App Store Connect.")
    return items[0]["id"]


def main() -> int:
    timeout_min = int(sys.argv[1]) if len(sys.argv) > 1 else 45
    app_id = get_app_id()
    deadline = time.time() + timeout_min * 60

    while True:
        _, data = request("GET",
                          f"builds?filter[app]={app_id}"
                          f"&filter[processingState]=VALID"
                          f"&sort=-uploadedDate&limit=1",
                          raise_on_error=False)
        items = (data or {}).get("data", [])
        if items:
            b = items[0]
            print(f"VALID build: {b['attributes'].get('version')} ({b['id']})")
            return 0
        if time.time() > deadline:
            print(f"Timed out after {timeout_min} min waiting for a VALID build.",
                  file=sys.stderr)
            return 1
        print("  build still processing, checking again in 60s ...")
        time.sleep(60)


if __name__ == "__main__":
    sys.exit(main())
