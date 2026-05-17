#!/usr/bin/env python3
"""Ensure a MAC_OS appStoreVersion exists for the given version string.

The other asc_* scripts operate on an existing editable version; App Store
Connect does not create it as a side effect of uploading a build. This
creates the version record (in PREPARE_FOR_SUBMISSION) if it is absent, so
the release flow can run unattended.

Usage: asc_version.py <versionString>
"""
import sys

from _asc import BUNDLE_ID, request


def get_app_id() -> str:
    _, data = request("GET", f"apps?filter[bundleId]={BUNDLE_ID}")
    items = data.get("data") or []
    if not items:
        raise SystemExit(f"App record for {BUNDLE_ID} not found in App Store Connect.")
    return items[0]["id"]


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: asc_version.py <versionString>")
    version = sys.argv[1]

    app_id = get_app_id()
    _, data = request("GET", f"apps/{app_id}/appStoreVersions?filter[platform]=MAC_OS")
    for v in data.get("data", []):
        if v["attributes"]["versionString"] == version:
            print(f"[OK ] appStoreVersion {version} exists -> {v['id']} "
                  f"({v['attributes']['appStoreState']})")
            return 0

    _, data = request("POST", "appStoreVersions", {
        "data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "MAC_OS", "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    })
    print(f"[OK ] created appStoreVersion {version} -> {data['data']['id']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
