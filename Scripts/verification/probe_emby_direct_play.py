#!/usr/bin/env python3
"""Settle which Emby URL actually serves the original bytes.

The app negotiates via /Items/{id}/PlaybackInfo, discards the response's URL
fields, and hand-builds a direct-play URL from the *library item's* id. A
server 404 on that URL says the path is wrong, but not which part. This probe
asks the server the same questions the app asks, dumps what the server offers
under both direct-stream settings, then tries every candidate URL so the
answer comes from the server rather than from reading the client.

The access token reaches the server but never the terminal. It is redacted out
of every printed URL, because this probe's output is what gets pasted into an
audit trail. Credentials come from EMBY_USER and EMBY_PASSWORD when the flags
are absent, so the repository's own `set -a; . .env` covers it without putting
a password in argv where every process on the machine can read it.

Usage:
    set -a; . .env; set +a
    probe_emby_direct_play.py --address http://host:8096
    probe_emby_direct_play.py --address http://host:8096 --token T --user-id U
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

CLIENT = "Enchron"
DEVICE = "EnchronProbe"
DEVICE_ID = "enchron-direct-play-probe"
VERSION = "1.0"


def authorization_header(token=None):
    fields = [
        f'Client="{CLIENT}"',
        f'Device="{DEVICE}"',
        f'DeviceId="{DEVICE_ID}"',
        f'Version="{VERSION}"',
    ]
    if token:
        fields.append(f'Token="{token}"')
    return "MediaBrowser " + ", ".join(fields)


def request(address, path, token=None, method="GET", body=None, query=None):
    url = address.rstrip("/") + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("X-Emby-Authorization", authorization_header(token))
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=30) as response:
        payload = response.read()
    return json.loads(payload) if payload else {}


def probe(url, token):
    req = urllib.request.Request(url, method="GET")
    req.add_header("X-Emby-Authorization", authorization_header(token))
    req.add_header("Range", "bytes=0-1023")
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status, response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as error:
        return error.code, error.headers.get("Content-Type", "")
    except urllib.error.URLError as error:
        return None, str(error.reason)


def authenticate(address, username, password):
    try:
        result = request(
            address,
            "/Users/AuthenticateByName",
            method="POST",
            body={"Username": username, "Pw": password},
        )
    except urllib.error.HTTPError as error:
        if error.code == 401:
            sys.exit(f"server rejected the password for {username}")
        raise
    return result["AccessToken"], result["User"]["Id"]


def first_playable_item(address, token, user_id):
    result = request(
        address,
        f"/Users/{user_id}/Items",
        token=token,
        query={
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Episode",
            "Fields": "MediaSources",
            "Limit": "1",
        },
    )
    items = result.get("Items") or []
    if not items:
        sys.exit("library returned no Movie or Episode items")
    return items[0]


def playback_info(address, token, user_id, item_id, direct_stream):
    return request(
        address,
        f"/Items/{item_id}/PlaybackInfo",
        token=token,
        method="POST",
        body={
            "UserId": user_id,
            "EnableDirectPlay": True,
            "EnableDirectStream": direct_stream,
            "EnableTranscoding": False,
            "IsPlayback": True,
        },
    )


def candidates(address, token, item_id, source):
    source_id = source.get("Id")
    container = source.get("Container") or "mp4"
    static = {"Static": "true", "MediaSourceId": source_id, "api_key": token}
    base = address.rstrip("/")

    yield (
        "app today: item id + container suffix",
        f"{base}/Videos/{item_id}/stream.{container}?" + urllib.parse.urlencode(static),
    )
    yield (
        "media source id in path",
        f"{base}/Videos/{source_id}/stream.{container}?" + urllib.parse.urlencode(static),
    )
    yield (
        "item id, no container suffix",
        f"{base}/Videos/{item_id}/stream?" + urllib.parse.urlencode(static),
    )
    yield (
        "raw download endpoint",
        f"{base}/Items/{item_id}/Download?" + urllib.parse.urlencode({"api_key": token}),
    )
    for field in ("DirectStreamUrl", "TranscodingUrl"):
        value = source.get(field)
        if value:
            joined = value if value.startswith("http") else base + value
            separator = "&" if "?" in joined else "?"
            yield (
                f"server-supplied {field}",
                f"{joined}{separator}api_key={token}",
            )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", required=True)
    parser.add_argument("--token")
    parser.add_argument("--user-id")
    parser.add_argument("--username")
    parser.add_argument("--password")
    parser.add_argument("--item-id")
    args = parser.parse_args()

    username = args.username or os.environ.get("EMBY_USER")
    password = args.password or os.environ.get("EMBY_PASSWORD")

    if username:
        token, user_id = authenticate(args.address, username, password or "")
    elif args.token and args.user_id:
        token, user_id = args.token, args.user_id
    else:
        sys.exit("give either --username/--password or --token/--user-id")

    if args.item_id:
        item_id = args.item_id
        item_name = "(supplied)"
    else:
        item = first_playable_item(args.address, token, user_id)
        item_id, item_name = item["Id"], item.get("Name", "")

    print(f"item {item_id}  {item_name}\n")

    for direct_stream in (False, True):
        label = "EnableDirectStream=true" if direct_stream else "EnableDirectStream=false (what the app sends)"
        print(f"--- PlaybackInfo, {label} ---")
        info = playback_info(args.address, token, user_id, item_id, direct_stream)
        print(f"PlaySessionId: {info.get('PlaySessionId')}")
        for source in info.get("MediaSources") or []:
            print(json.dumps({
                key: source.get(key)
                for key in (
                    "Id", "Name", "Container", "SupportsDirectPlay",
                    "SupportsDirectStream", "SupportsTranscoding",
                    "DirectStreamUrl", "TranscodingUrl", "Path",
                )
            }, indent=2, ensure_ascii=False))
        print()

    info = playback_info(args.address, token, user_id, item_id, True)
    for source in info.get("MediaSources") or []:
        print(f"--- candidate URLs for media source {source.get('Id')} ---")
        for label, url in candidates(args.address, token, item_id, source):
            status, detail = probe(url, token)
            verdict = "OK" if status in (200, 206) else "FAIL"
            print(f"  [{verdict}] {status or 'ERR'}  {label}")
            print(f"          {detail}")
            print(f"          {url.replace(token, 'REDACTED')}")
        print()


if __name__ == "__main__":
    main()
