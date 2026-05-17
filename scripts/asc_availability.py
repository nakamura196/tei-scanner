#!/usr/bin/env python3
"""Configure App Store app availability (territories) via the App Store
Connect API V2.

The app was removed from App Store distribution because no territory
availability was ever set. This creates an appAvailabilities resource
covering every available territory.

Usage:
  scripts/asc_availability.py            # show current availability
  scripts/asc_availability.py --apply    # create availability for all territories
"""
import argparse
import json
import sys
import urllib.error
import urllib.request

from _asc import BUNDLE_ID, request, token


def request_v2(method, path, body=None):
    """App Availability lives under the /v2/ API; _asc.request is /v1/ only."""
    url = f"https://api.appstoreconnect.apple.com/v2/{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def get_app_id() -> str:
    _, data = request("GET", f"apps?filter[bundleId]={BUNDLE_ID}")
    return data["data"][0]["id"]


def list_territories() -> list[str]:
    _, data = request("GET", "territories?limit=200")
    return sorted(t["id"] for t in data["data"])


def show_current(app_id: str) -> bool:
    status, data = request("GET", f"apps/{app_id}/appAvailabilityV2",
                           raise_on_error=False)
    if status == 404:
        print("  no app availability configured (app not distributed)")
        return False
    if status == 200:
        attrs = data["data"]["attributes"]
        print(f"  app availability exists: id={data['data']['id']}, "
              f"availableInNewTerritories={attrs.get('availableInNewTerritories')}")
        s2, td = request_v2("GET",
                            f"appAvailabilities/{data['data']['id']}"
                            f"/territoryAvailabilities?limit=200&"
                            f"fields[territoryAvailabilities]=available")
        if s2 == 200:
            avail = [t for t in td.get("data", [])
                     if t["attributes"].get("available")]
            print(f"  territories available: {len(avail)}")
        return True
    print(f"  unexpected status {status}: {data}")
    return False


def create_availability(app_id: str, territories: list[str],
                         available_in_new: bool) -> None:
    body = {
        "data": {
            "type": "appAvailabilities",
            "attributes": {"availableInNewTerritories": available_in_new},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
                "territoryAvailabilities": {
                    "data": [
                        {"type": "territoryAvailabilities", "id": "${%s}" % t}
                        for t in territories
                    ]
                },
            },
        },
        "included": [
            {
                "type": "territoryAvailabilities",
                "id": "${%s}" % t,
                "attributes": {"available": True},
                "relationships": {
                    "territory": {
                        "data": {"type": "territories", "id": t}
                    }
                },
            }
            for t in territories
        ],
    }
    status, data = request_v2("POST", "appAvailabilities", body)
    if status in (200, 201):
        print(f"  created app availability: id={data['data']['id']}")
    else:
        print(f"  FAILED: HTTP {status}")
        print(f"  {data}")
        raise SystemExit(1)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="actually create the app availability")
    args = ap.parse_args()

    app_id = get_app_id()
    print(f"app_id={app_id}")

    print("Current availability:")
    exists = show_current(app_id)

    if not args.apply:
        print()
        print("Dry run. Re-run with --apply to set availability for all "
              "territories.")
        return 0

    if exists:
        print()
        print("App availability already exists; nothing to create.")
        return 0

    territories = list_territories()
    print()
    print(f"Creating availability for {len(territories)} territories "
          f"(availableInNewTerritories=True)...")
    create_availability(app_id, territories, available_in_new=True)

    print()
    print("Done. Verifying:")
    show_current(app_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
