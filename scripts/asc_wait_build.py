#!/usr/bin/env python3
"""Poll App Store Connect until a specific uploaded build is VALID.

After altool uploads a build it takes roughly 5-30 minutes to finish
processing before it can be attached to a version. This blocks until the
build with the given version string (CFBundleVersion) is VALID, then
exits 0; it exits non-zero on timeout.

Waiting for a *specific* build matters: an older build may already be
VALID, so "wait for any VALID build" would return immediately with the
wrong one.

Usage: asc_wait_build.py <build_version> [timeout_minutes]   (default 45)
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
    if len(sys.argv) < 2:
        raise SystemExit("usage: asc_wait_build.py <build_version> [timeout_minutes]")
    build_version = sys.argv[1]
    timeout_min = int(sys.argv[2]) if len(sys.argv) > 2 else 45

    app_id = get_app_id()
    deadline = time.time() + timeout_min * 60

    while True:
        _, data = request("GET",
                          f"builds?filter[app]={app_id}"
                          f"&filter[version]={build_version}"
                          f"&sort=-uploadedDate&limit=1",
                          raise_on_error=False)
        items = (data or {}).get("data", [])
        if items:
            b = items[0]
            state = b["attributes"].get("processingState")
            if state == "VALID":
                print(f"VALID build {build_version} ({b['id']})")
                return 0
            print(f"  build {build_version}: {state}, checking again in 60s ...")
        else:
            print(f"  build {build_version}: not visible yet, checking again in 60s ...")

        if time.time() > deadline:
            print(f"Timed out after {timeout_min} min waiting for build "
                  f"{build_version} to become VALID.", file=sys.stderr)
            return 1
        time.sleep(60)


if __name__ == "__main__":
    sys.exit(main())
