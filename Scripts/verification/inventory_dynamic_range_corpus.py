#!/usr/bin/env python3
"""Inventory the Emby library's dynamic-range corpus by probed Dolby Vision profile.

Emby reports a coarse VideoRange and leaves its Dv* fields empty, so the profile
that decides which PlaybackCore path a title exercises comes from ffprobe on the
file itself. The library sits on this host's rclone NFS mount at Emby's own
library root, so the paths Emby reports are directly readable.

Credentials come from EMBY_USER and EMBY_PASSWORD, so `set -a; . .env; set +a`
covers it and nothing lands in argv.
"""

import argparse
import concurrent.futures
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe_emby_direct_play import authenticate, request

def _default_emby_address() -> str:
    try:
        import sys as _sys
        from pathlib import Path as _Path
        import json as _json
        _sys.path.insert(0, str(_Path(__file__).resolve().parent))
        import ensure_test_services as _ets
        receipt = _ets._read_object(_ets.emby_spec().receipt_file)
        if isinstance(receipt, dict) and isinstance(receipt.get("address"), str) and receipt.get("address"):
            return str(receipt["address"])
        spec = _ets.emby_spec()
        if spec.recorded_address:
            return spec.recorded_address
    except Exception:
        pass
    try:
        from pathlib import Path as _Path2
        import json as _json2
        p = _Path2(__file__).resolve().parents[2] / "Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json"
        if p.is_file():
            d = _json2.loads(p.read_text(encoding="utf-8"))
            if isinstance(d.get("address"), str) and d.get("address"):
                return str(d["address"])
    except Exception:
        pass
    return "http://Mac-mini.local:8096"
EMBY_ADDRESS = _default_emby_address()


def library_video_streams(address, token, user_id):
    result = request(
        address,
        f"/Users/{user_id}/Items",
        token=token,
        query={
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Episode,Video",
            "Fields": "MediaSources,Path",
            "Limit": "5000",
        },
    )
    for item in result.get("Items") or []:
        for source in item.get("MediaSources") or []:
            for stream in source.get("MediaStreams") or []:
                if stream.get("Type") != "Video":
                    continue
                yield {
                    "itemID": item.get("Id"),
                    "name": item.get("Name"),
                    "range": stream.get("VideoRangeType") or stream.get("VideoRange"),
                    "codec": stream.get("Codec"),
                    "container": source.get("Container"),
                    "width": stream.get("Width"),
                    "height": stream.get("Height"),
                    "serverPath": source.get("Path"),
                }


def probe_dolby_vision(path, timeout):
    if not path or not os.path.exists(path):
        return {"probe": "missing"}
    try:
        completed = subprocess.run(
            [
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_streams", "-of", "json", path,
            ],
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"probe": "timeout"}
    if completed.returncode != 0:
        return {"probe": "error", "detail": completed.stderr.decode()[:200]}
    streams = json.loads(completed.stdout or "{}").get("streams") or []
    if not streams:
        return {"probe": "no video stream"}
    stream = streams[0]
    probed = {
        "probe": "ok",
        "codecProfile": stream.get("profile"),
        "pixelFormat": stream.get("pix_fmt"),
        "transfer": stream.get("color_transfer"),
        "primaries": stream.get("color_primaries"),
    }
    for side_data in stream.get("side_data_list") or []:
        if "dv_profile" not in side_data:
            continue
        probed.update({
            "dvProfile": side_data.get("dv_profile"),
            "dvLevel": side_data.get("dv_level"),
            "blPresent": side_data.get("bl_present_flag"),
            "elPresent": side_data.get("el_present_flag"),
            "rpuPresent": side_data.get("rpu_present_flag"),
            "compatibilityID": side_data.get("dv_bl_signal_compatibility_id"),
        })
    return probed


def playback_path(entry):
    """The PlaybackCore branch a title exercises, from its probed configuration."""
    profile = entry.get("dvProfile")
    if profile is None:
        return "HDR10" if entry.get("range") == "HDR 10" else "SDR"
    if profile == 7 and entry.get("blPresent") and entry.get("elPresent"):
        return "DolbyVision profile 7 dual-layer split"
    if profile == 5:
        return "DolbyVision profile 5 single-layer"
    return f"DolbyVision profile {profile} single-layer"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", default=EMBY_ADDRESS)
    parser.add_argument("--include-sdr", action="store_true")
    parser.add_argument("--probe-timeout", type=int, default=300)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--output")
    args = parser.parse_args()

    username = os.environ.get("EMBY_USER")
    password = os.environ.get("EMBY_PASSWORD")
    if not username or not password:
        sys.exit("set EMBY_USER and EMBY_PASSWORD")
    token, user_id = authenticate(args.address, username, password)

    entries = [
        entry for entry in library_video_streams(args.address, token, user_id)
        if args.include_sdr or entry["range"] != "SDR"
    ]
    for entry in entries:
        entry["localPath"] = entry["serverPath"]

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        probes = pool.map(
            lambda entry: probe_dolby_vision(entry["localPath"], args.probe_timeout),
            entries,
        )
        for entry, probed in zip(entries, probes):
            entry.update(probed)
            entry["playbackPath"] = playback_path(entry)

    entries.sort(key=lambda entry: (entry["playbackPath"], entry["name"] or ""))
    counts = {}
    for entry in entries:
        counts[entry["playbackPath"]] = counts.get(entry["playbackPath"], 0) + 1

    for path, count in sorted(counts.items()):
        print(f"{count:4d}  {path}")
    print()
    for entry in entries:
        print(
            f"  {entry['playbackPath']:44s} "
            f"{entry['range']:12s} {entry['container'] or '?':5s} "
            f"{entry['itemID']:>6s}  {(entry['name'] or '')[:48]}"
        )

    unreadable = [entry for entry in entries if entry.get("probe") != "ok"]
    if unreadable:
        print(f"\n{len(unreadable)} entries could not be probed:")
        for entry in unreadable:
            print(f"  {entry.get('probe')}: {(entry['name'] or '')[:48]}")

    if args.output:
        with open(args.output, "w") as handle:
            json.dump({"counts": counts, "entries": entries}, handle,
                      ensure_ascii=False, indent=2)
        print(f"\nwrote {args.output}")
    return 1 if unreadable else 0


if __name__ == "__main__":
    sys.exit(main())
