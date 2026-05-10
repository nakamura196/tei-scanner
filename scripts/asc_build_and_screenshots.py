#!/usr/bin/env python3
"""Attach the latest VALID build to the editable version, declare
encryption compliance, and upload App Store screenshots.

Screenshots are uploaded for each existing version localization at
display type APP_DESKTOP. PNGs are read from docs/asc-screenshots/ and
must be 2880x1800 (the Mac display type expected by App Store Connect).
"""
import base64
import hashlib
import os
import sys
import urllib.request

from _asc import BUNDLE_ID, request, token


SCREENSHOT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "docs", "asc-screenshots"
)
DISPLAY_TYPE = "APP_DESKTOP"


def get_app_id():
    _, data = request("GET", f"apps?filter[bundleId]={BUNDLE_ID}")
    return data["data"][0]["id"]


def get_editable_version_id(app_id):
    _, data = request("GET", f"apps/{app_id}/appStoreVersions?filter[platform]=MAC_OS")
    versions = data.get("data", [])
    editable_states = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                       "REJECTED", "METADATA_REJECTED"}
    for v in versions:
        if v["attributes"]["appStoreState"] in editable_states:
            return v["id"]
    raise SystemExit("No editable version found.")


def latest_valid_build_id(app_id):
    _, data = request("GET",
                      f"builds?filter[app]={app_id}"
                      f"&filter[processingState]=VALID"
                      f"&sort=-uploadedDate&limit=1")
    items = data.get("data", [])
    if not items:
        raise SystemExit("No VALID build yet — wait for processing to finish.")
    return items[0]["id"]


def declare_encryption(build_id):
    request("PATCH", f"builds/{build_id}", {
        "data": {
            "type": "builds",
            "id": build_id,
            "attributes": {"usesNonExemptEncryption": False},
        }
    })
    print(f"  encryption: usesNonExemptEncryption=false on {build_id}")


def attach_build(version_id, build_id):
    request("PATCH", f"appStoreVersions/{version_id}/relationships/build", {
        "data": {"type": "builds", "id": build_id},
    })
    print(f"  attached build {build_id} to version {version_id}")


def get_or_create_screenshot_set(version_loc_id):
    _, data = request("GET",
                      f"appStoreVersionLocalizations/{version_loc_id}/appScreenshotSets")
    for s in data.get("data", []):
        if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            return s["id"]
    _, data = request("POST", "appScreenshotSets", {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": version_loc_id,
                    }
                }
            },
        }
    })
    return data["data"]["id"]


def clear_screenshot_set(set_id):
    _, data = request("GET", f"appScreenshotSets/{set_id}/appScreenshots")
    for s in data.get("data", []):
        request("DELETE", f"appScreenshots/{s['id']}", raise_on_error=False)


def upload_screenshot(set_id, filepath, filename):
    with open(filepath, "rb") as f:
        body = f.read()
    checksum = base64.b64encode(hashlib.md5(body).digest()).decode()

    _, data = request("POST", "appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileName": filename, "fileSize": len(body)},
            "relationships": {
                "appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}
                }
            },
        }
    })
    sid = data["data"]["id"]
    ops = data["data"]["attributes"]["uploadOperations"]
    for op in ops:
        chunk = body[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req).read()
    request("PATCH", f"appScreenshots/{sid}", {
        "data": {
            "type": "appScreenshots",
            "id": sid,
            "attributes": {"uploaded": True, "sourceFileChecksum": checksum},
        }
    })
    return sid


def upload_all_screenshots(version_id):
    if not os.path.isdir(SCREENSHOT_DIR):
        print(f"  no screenshot dir at {SCREENSHOT_DIR}, skipping")
        return
    files = sorted(f for f in os.listdir(SCREENSHOT_DIR) if f.endswith(".png"))
    if not files:
        print("  no .png files in screenshot dir, skipping")
        return

    _, data = request("GET",
                      f"appStoreVersions/{version_id}/appStoreVersionLocalizations")
    locs = data.get("data", [])
    for loc in locs:
        loc_id = loc["id"]
        locale = loc["attributes"]["locale"]
        print(f"  locale {locale}:")
        set_id = get_or_create_screenshot_set(loc_id)
        clear_screenshot_set(set_id)
        for fname in files:
            path = os.path.join(SCREENSHOT_DIR, fname)
            sid = upload_screenshot(set_id, path, fname)
            print(f"    uploaded {fname} -> {sid}")


def main() -> int:
    app_id = get_app_id()
    print(f"app_id={app_id}")
    version_id = get_editable_version_id(app_id)
    print(f"version_id={version_id}")
    build_id = latest_valid_build_id(app_id)
    print(f"build_id={build_id}")
    print()

    print("[1/3] encryption compliance")
    declare_encryption(build_id)
    print()

    print("[2/3] attach build to version")
    attach_build(version_id, build_id)
    print()

    print("[3/3] upload screenshots")
    upload_all_screenshots(version_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
