"""Shared App Store Connect helpers (load .env, sign JWT, send requests)."""
import json
import os
import time
import urllib.error
import urllib.request

import jwt

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_PATH = os.path.join(PROJECT_DIR, ".env")


def _load_env() -> dict:
    env = {}
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH) as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                v = v.strip()
                if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                    v = v[1:-1]
                env[k.strip()] = v
    return env


_ENV = _load_env()


def env(key, required=True, default=None):
    val = os.environ.get(key) or _ENV.get(key) or default
    if required and not val:
        raise SystemExit(f"missing env var: {key} (set in .env or shell)")
    return val


KEY_ID = env("APP_STORE_API_KEY")
ISSUER_ID = env("APP_STORE_API_ISSUER")
TEAM_ID = env("TEAM_ID")
BUNDLE_ID = env("BUNDLE_ID")
APP_NAME = env("APP_NAME")
SKU = env("SKU")
KEY_PATH = os.path.expanduser(f"~/.private_keys/AuthKey_{KEY_ID}.p8")


def token() -> str:
    with open(KEY_PATH) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )


def request(method, path, body=None, raise_on_error=True):
    url = f"https://api.appstoreconnect.apple.com/v1/{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
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
        body = e.read().decode(errors="replace")
        if raise_on_error:
            print(f"HTTP {e.code} {method} {path}\n{body}")
            raise
        try:
            return e.code, json.loads(body)
        except Exception:
            return e.code, {"raw": body}
