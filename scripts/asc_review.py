#!/usr/bin/env python3
"""Configure App Store review details and (optionally) submit the version
for review.

Steps:
- Upsert appStoreReviewDetails on the editable version (contact info,
  no demo account required, empty notes).
- Print a readiness summary.
- With --submit, create a reviewSubmission, attach the version as a
  reviewSubmissionItem, and PATCH submitted=true.

This will NOT submit unless --submit is passed; the default run only
sets up review details and reports state. App Privacy data declarations
must be configured manually in the App Store Connect web UI before
submission.
"""
import argparse
import sys

from _asc import BUNDLE_ID, request


REVIEW_DETAILS = {
    "contactFirstName": "Satoru",
    "contactLastName": "Nakamura",
    "contactEmail": "na.kamura.1263@gmail.com",
    "contactPhone": "+81-90-7191-9495",
    "demoAccountRequired": False,
    "demoAccountName": "",
    "demoAccountPassword": "",
    "notes": (
        "TEI Scanner runs entirely on-device. No login or network access "
        "is required. To exercise the app: launch, click 'Try sample' on "
        "the empty window to load two bundled English page images, click "
        "'Run OCR', then 'Export TEI/XML…' and save the result anywhere."
    ),
}


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


def upsert_review_details(version_id):
    _, data = request("GET",
                      f"appStoreVersions/{version_id}/appStoreReviewDetail",
                      raise_on_error=False)
    existing = data.get("data") if isinstance(data, dict) else None
    if existing and isinstance(existing, dict):
        rid = existing["id"]
        request("PATCH", f"appStoreReviewDetails/{rid}", {
            "data": {
                "type": "appStoreReviewDetails",
                "id": rid,
                "attributes": REVIEW_DETAILS,
            }
        })
        print(f"  patched review details {rid}")
        return rid

    _, data = request("POST", "appStoreReviewDetails", {
        "data": {
            "type": "appStoreReviewDetails",
            "attributes": REVIEW_DETAILS,
            "relationships": {
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": version_id}
                }
            },
        }
    })
    rid = data["data"]["id"]
    print(f"  created review details {rid}")
    return rid


def report_readiness(app_id, version_id):
    print()
    print("Readiness check:")

    # `build` must be listed in the sparse fieldset, or the relationship is
    # omitted and the "build attached" check below is a false negative.
    _, data = request("GET",
                      f"appStoreVersions/{version_id}?include=build"
                      f"&fields[appStoreVersions]=copyright,appStoreState,versionString,build")
    a = data["data"]["attributes"]
    print(f"  version {a['versionString']}: state={a['appStoreState']}, "
          f"copyright={'set' if a.get('copyright') else 'MISSING'}")

    has_build = bool(data["data"].get("relationships", {}).get("build", {}).get("data"))
    print(f"  build attached: {has_build}")

    _, data = request("GET",
                      f"appStoreVersions/{version_id}/appStoreVersionLocalizations")
    for loc in data.get("data", []):
        a = loc["attributes"]
        locale = a["locale"]
        print(f"  loc {locale}:  description={'set' if a.get('description') else 'MISSING'}, "
              f"keywords={'set' if a.get('keywords') else 'MISSING'}, "
              f"supportUrl={'set' if a.get('supportUrl') else 'MISSING'}")
        _, ss = request("GET",
                        f"appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")
        print(f"          screenshot sets: {len(ss.get('data', []))}")

    print()
    print("Reminder: App Privacy data declarations must be set via the App Store Connect")
    print("web UI: https://appstoreconnect.apple.com/apps/{}/distribution/privacy".format(app_id))


def submit_for_review(app_id, version_id):
    _, data = request("POST", "reviewSubmissions", {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "MAC_OS"},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}}
            },
        }
    })
    sub_id = data["data"]["id"]
    print(f"  submission created: {sub_id}")

    request("POST", "reviewSubmissionItems", {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {
                    "data": {"type": "reviewSubmissions", "id": sub_id}
                },
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": version_id}
                },
            },
        }
    })
    print("  version added as a submission item")

    request("PATCH", f"reviewSubmissions/{sub_id}", {
        "data": {
            "type": "reviewSubmissions",
            "id": sub_id,
            "attributes": {"submitted": True},
        }
    })
    print(f"  submitted: {sub_id}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--submit", action="store_true",
                    help="actually submit to App Store review")
    args = ap.parse_args()

    app_id = get_app_id()
    print(f"app_id={app_id}")
    version_id = get_editable_version_id(app_id)
    print(f"version_id={version_id}")
    print()

    print("[1/2] review details")
    upsert_review_details(version_id)

    print("[2/2] readiness")
    report_readiness(app_id, version_id)

    if args.submit:
        print()
        print("Submitting for review...")
        submit_for_review(app_id, version_id)
    else:
        print()
        print("Dry run only. Re-run with --submit to actually submit.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
