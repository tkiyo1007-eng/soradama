#!/usr/bin/env python3
"""アプリ内イベントの日英ローカリゼーションへ、カード・詳細の画像を App Store Connect API で入れる。

使い方:
  python3 asc_event_images.py <issuer_id> list      # ローカリゼーションと既存の画像を表示するだけ
  python3 asc_event_images.py <issuer_id> upload    # 画像の無い欄にだけ入れる

EVENT_ID と ART は対象のイベントに合わせて書き換える。鍵は ~/.appstoreconnect/private_keys に置き、リポジトリには入れない。
App Store Connect の変更になるので、upload は利用者の承認を得てから実行する。
"""
import hashlib, json, sys, time, urllib.request, urllib.error
from pathlib import Path
import jwt

KEY_ID = "BDKP895P4B"
KEY_PATH = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{KEY_ID}.p8"
EVENT_ID = "6821042134"
ART = Path(__file__).resolve().parent.parent / "AppStore/InAppEvents/winter-start-2026"
ASSETS = {"EVENT_CARD": ART / "event-card-1920x1080.png", "EVENT_DETAILS_PAGE": ART / "event-detail-1080x1920.png"}
API = "https://api.appstoreconnect.apple.com"


def token(issuer):
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      KEY_PATH.read_text(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def call(tok, method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            data = r.read()
            return json.loads(data) if data else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} -> {e.code}\n{e.read().decode()[:1500]}")


def main():
    issuer, mode = sys.argv[1], sys.argv[2]
    tok = token(issuer)
    locs = call(tok, "GET", f"/v1/appEvents/{EVENT_ID}/localizations?include=appEventScreenshots&limit=50")
    shots = {s["id"]: s for s in locs.get("included", []) if s["type"] == "appEventScreenshots"}
    for loc in locs["data"]:
        have = [shots[r["id"]]["attributes"].get("appEventAssetType") + ":" +
                str((shots[r["id"]]["attributes"].get("assetDeliveryState") or {}).get("state"))
                for r in loc["relationships"]["appEventScreenshots"].get("data", []) if r["id"] in shots]
        print(loc["id"], loc["attributes"]["locale"], loc["attributes"].get("name"), "existing:", have)
        if mode != "upload":
            continue
        for asset_type, path in ASSETS.items():
            if any(h.startswith(asset_type + ":") for h in have):
                print("  skip", asset_type, "(already set)")
                continue
            data = path.read_bytes()
            created = call(tok, "POST", "/v1/appEventScreenshots", {"data": {
                "type": "appEventScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(data), "appEventAssetType": asset_type},
                "relationships": {"appEventLocalization": {"data": {"type": "appEventLocalizations", "id": loc["id"]}}}}})
            shot_id = created["data"]["id"]
            for op in created["data"]["attributes"]["uploadOperations"]:
                part = data[op["offset"]:op["offset"] + op["length"]]
                headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
                urllib.request.urlopen(urllib.request.Request(op["url"], method=op["method"], data=part, headers=headers)).read()
            call(tok, "PATCH", f"/v1/appEventScreenshots/{shot_id}", {"data": {
                "type": "appEventScreenshots", "id": shot_id, "attributes": {"uploaded": True}}})
            print("  uploaded", asset_type, shot_id, "md5", hashlib.md5(data).hexdigest())


if __name__ == "__main__":
    main()
