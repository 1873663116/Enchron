"""Answer J04's host-side content condition before the journey touches the app.

J04 forbids server-side changes, so the only honest way to know whether the
aggregate fixture is reachable through Emby is to ask the server directly:
is it up, is the item in a library, and does its stream composition match the
local file the other journeys play. Credentials come from the repository .env
and never reach the command line or the evidence.
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[2]
CREDENTIALS = REPOSITORY / ".env"
FIXTURE = REPOSITORY.parent / "TestMedia" / "TestVectors" / "Enchron" / "PlaybackBehavior" / "sdr-bframe-aggregate-30s.mkv"
DEFAULT_SERVER = "http://192.168.5.20:8096"
AUTHORIZATION = 'MediaBrowser Client="EnchronVerify", Device="Mac", DeviceId="enchron-verify", Version="1.0"'
TIMEOUT_SECONDS = 10


class ProbeError(Exception):
    pass


def credentials():
    if not CREDENTIALS.is_file():
        raise ProbeError(f"no credential file at {CREDENTIALS}")
    values = {}
    for line in CREDENTIALS.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    for key in ("EMBY_USER", "EMBY_PASSWORD"):
        if not values.get(key):
            raise ProbeError(f"{key} is missing from the credential file")
    return values["EMBY_USER"], values["EMBY_PASSWORD"]


def request(server, path, token=None, payload=None, params=None):
    url = f"{server}{path}"
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    headers = {"X-Emby-Authorization": AUTHORIZATION, "Accept": "application/json"}
    if token:
        headers["X-Emby-Token"] = token
    body = None
    if payload is not None:
        body = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers), timeout=TIMEOUT_SECONDS) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        raise ProbeError(f"{path} returned HTTP {error.code}") from None
    except urllib.error.URLError as error:
        raise ProbeError(f"{path} is unreachable: {error.reason}") from None
    return json.loads(raw) if raw else {}


def local_streams():
    if not FIXTURE.is_file():
        raise ProbeError(f"local fixture missing at {FIXTURE}")
    output = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name", "-of", "json", str(FIXTURE)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return [normalise(s["codec_type"], s.get("codec_name")) for s in json.loads(output)["streams"]]


CODEC_ALIASES = {"dvbsub": "dvb_subtitle", "srt": "subrip", "ssa": "ass"}


def normalise(kind, codec):
    codec = (codec or "").lower()
    return kind.lower(), CODEC_ALIASES.get(codec, codec)


def remote_streams(item):
    embedded, external = [], []
    for stream in item.get("MediaStreams", []):
        kind = stream.get("Type", "").lower()
        if kind not in {"video", "audio", "subtitle"}:
            continue
        entry = normalise(kind, stream.get("Codec"))
        (external if stream.get("IsExternal") else embedded).append(entry)
    return embedded, external


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", default=DEFAULT_SERVER)
    parser.add_argument("--name", default=FIXTURE.stem)
    args = parser.parse_args()

    report = {"server": args.server, "fixture": args.name}
    try:
        user, password = credentials()
        session = request(args.server, "/Users/AuthenticateByName", payload={"Username": user, "Pw": password})
        token = session["AccessToken"]
        account = session["User"]["Id"]
        report["reachable"] = True
        report["libraries"] = [
            {"name": f["Name"], "type": f.get("CollectionType"), "locations": f.get("Locations", [])}
            for f in request(args.server, "/Library/VirtualFolders", token=token)
        ]

        found = request(
            args.server,
            f"/Users/{account}/Items",
            token=token,
            params={"Recursive": "true", "SearchTerm": args.name, "Fields": "Path,MediaStreams", "Limit": 20},
        )
        matches = [i for i in found.get("Items", []) if args.name.lower() in (i.get("Name", "") + (i.get("Path") or "")).lower()]
        report["inLibrary"] = bool(matches)

        if matches:
            item = request(args.server, f"/Users/{account}/Items/{matches[0]['Id']}", token=token)
            expected = local_streams()
            embedded, external = remote_streams(item)
            report["item"] = {"name": item.get("Name"), "path": item.get("Path"), "id": item.get("Id")}
            report["streamsLocal"] = [f"{kind}:{codec}" for kind, codec in expected]
            report["streamsEmbedded"] = [f"{kind}:{codec}" for kind, codec in embedded]
            report["streamsSidecar"] = [f"{kind}:{codec}" for kind, codec in external]
            report["streamsMatch"] = sorted(expected) == sorted(embedded)
            report["sidecarSubtitles"] = len(external)
        else:
            report["reason"] = "the aggregate fixture is not in any Emby library"
    except ProbeError as error:
        report["reachable"] = report.get("reachable", False)
        report["error"] = str(error)

    report["satisfied"] = bool(report.get("reachable") and report.get("inLibrary") and report.get("streamsMatch"))
    json.dump(report, sys.stdout, indent=2, sort_keys=True, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0 if report["satisfied"] else 1


if __name__ == "__main__":
    sys.exit(main())
