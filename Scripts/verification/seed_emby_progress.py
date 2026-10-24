#!/usr/bin/env python3
"""Give the seeded regression episodes the viewing progress a journey may need."""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
IDENTITY_FILE = REPOSITORY_ROOT / "Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json"
OWNED_PREFIX = "Enchron Regression"
SCHEMA = "enchron.test-services.emby-progress@1"


def call(request: urllib.request.Request, opener: urllib.request.OpenerDirector) -> Any:
    with opener.open(request) as response:
        payload = response.read()
    return json.loads(payload) if payload.strip() else {}


def main() -> int:
    identity = json.loads(IDENTITY_FILE.read_text(encoding="utf-8"))
    base = str(identity["address"]).rstrip("/")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    token = call(
        urllib.request.Request(
            f"{base}/Users/AuthenticateByName",
            data=json.dumps({"Username": identity["username"], "Pw": identity["password"]}).encode(),
            headers={
                "Content-Type": "application/json",
                "X-Emby-Authorization": 'MediaBrowser Client="seed", Device="cli", DeviceId="seed-progress", Version="1.0"',
            },
        ),
        opener,
    )["AccessToken"]
    headers = {"Content-Type": "application/json", "X-Emby-Token": token}
    items = call(
        urllib.request.Request(
            f"{base}/Users/{identity['userID']}/Items?Recursive=true&IncludeItemTypes=Episode&api_key={token}",
            headers=headers,
        ),
        opener,
    ).get("Items", [])
    owned = [item for item in items if str(item.get("Name", "")).startswith(OWNED_PREFIX)]
    owned.sort(key=lambda item: str(item.get("Id")))
    if not owned:
        print(json.dumps({"schema": SCHEMA, "ready": False, "reason": "no seeded episodes"}, indent=2))
        return 1
    receipt: list[dict[str, Any]] = []
    for position, item in enumerate(owned):
        identifier = str(item["Id"])
        before = call(
            urllib.request.Request(f"{base}/Users/{identity['userID']}/Items/{identifier}", headers=headers),
            opener,
        ).get("UserData", {})
        body = (
            {"Played": True, "PlaybackPositionTicks": 0}
            if position == 0
            else {"Played": False, "PlaybackPositionTicks": 30_000_000}
        )
        call(
            urllib.request.Request(
                f"{base}/Users/{identity['userID']}/Items/{identifier}/UserData",
                data=json.dumps(body).encode(),
                headers=headers,
                method="POST",
            ),
            opener,
        )
        receipt.append(
            {
                "itemID": identifier,
                "name": item.get("Name"),
                "played": body["Played"],
                "positionTicks": body["PlaybackPositionTicks"],
                "originalPlayed": bool(before.get("Played", False)),
                "originalPositionTicks": int(before.get("PlaybackPositionTicks", 0)),
            }
        )
    print(
        json.dumps(
            {"schema": SCHEMA, "ready": True, "episodes": receipt},
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
