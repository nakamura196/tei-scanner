#!/usr/bin/env python3
"""Register Bundle ID (and remind to create the ASC app record via Web UI)."""
import sys

from _asc import APP_NAME, BUNDLE_ID, request


def ensure_bundle_id() -> str:
    _, data = request("GET", f"bundleIds?filter[identifier]={BUNDLE_ID}")
    existing = data.get("data") or []
    if existing:
        bid = existing[0]["id"]
        print(f"[OK ] Bundle ID exists: {BUNDLE_ID} -> {bid}")
        return bid

    print(f"[..] Registering Bundle ID {BUNDLE_ID} ...")
    _, data = request("POST", "bundleIds", {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": BUNDLE_ID,
                "name": APP_NAME,
                "platform": "MAC_OS",
            },
        },
    })
    bid = data["data"]["id"]
    print(f"[OK ] Bundle ID created: {bid}")
    return bid


def check_app():
    _, data = request("GET", f"apps?filter[bundleId]={BUNDLE_ID}")
    existing = data.get("data") or []
    if existing:
        a = existing[0]
        print(f"[OK ] ASC app record: {a['attributes']['name']} -> {a['id']}")
        return a["id"]
    print(f"[--] App record missing. ASC API does not allow CREATE on 'apps'.")
    print(f"     Open https://appstoreconnect.apple.com/apps and create '{APP_NAME}' for {BUNDLE_ID}.")
    return None


def main() -> int:
    ensure_bundle_id()
    check_app()
    return 0


if __name__ == "__main__":
    sys.exit(main())
