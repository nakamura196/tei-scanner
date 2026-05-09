#!/usr/bin/env python3
"""Verify App Store Connect setup: auth, app record, Bundle ID."""
import sys

from _asc import APP_NAME, BUNDLE_ID, ISSUER_ID, KEY_ID, request


def main() -> int:
    print(f"Key ID:    {KEY_ID}")
    print(f"Issuer ID: {ISSUER_ID}")
    print(f"Bundle ID: {BUNDLE_ID}")
    print(f"App name:  {APP_NAME}")
    print()

    status, _ = request("GET", "apps?limit=1", raise_on_error=False)
    if status != 200:
        print(f"[FAIL] Auth: HTTP {status}")
        return 1
    print("[OK ] Auth")

    status, data = request("GET", f"apps?filter[bundleId]={BUNDLE_ID}", raise_on_error=False)
    if status == 200 and data.get("data"):
        a = data["data"][0]
        print(f"[OK ] ASC app record: {a['attributes']['name']} (id {a['id']})")
    else:
        print(f"[--] No ASC app record for '{BUNDLE_ID}' yet")

    status, data = request("GET", f"bundleIds?filter[identifier]={BUNDLE_ID}", raise_on_error=False)
    if status == 200 and data.get("data"):
        b = data["data"][0]
        print(f"[OK ] Developer Portal Bundle ID: {b['attributes']['identifier']} ({b['attributes']['platform']})")
    else:
        print(f"[--] No Bundle ID resource for '{BUNDLE_ID}' yet")

    return 0


if __name__ == "__main__":
    sys.exit(main())
