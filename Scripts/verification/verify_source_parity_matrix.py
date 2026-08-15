#!/usr/bin/env python3
"""Decode media through PlaybackCore from a local path and over HTTP, and compare.

Three modes share one measurement, PlaybackCoreRemoteMediaProbe's decode stage,
which builds the CMFormatDescription PlaybackCore would hand its renderer and runs
the samples through VideoToolbox.

  --local   decode every local corpus file once
  --parity  decode each local file twice, directly and over authenticated range
            HTTP, and require the decode-visible fields to match
  --emby    decode every non-SDR Emby item over the server's static stream URL

Transport changes how bytes arrive, so bytes_read is reported but never compared.
Everything the decoder sees must be identical.

Credentials come from EMBY_USER and EMBY_PASSWORD, so `set -a; . .env; set +a`
covers it and nothing lands in argv.
"""

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe_emby_direct_play import authenticate, request

REPOSITORY = Path(__file__).resolve().parents[2]
PACKAGE = REPOSITORY / "Packages" / "PlaybackCore"
SERVER = REPOSITORY / "Scripts" / "fixtures" / "range-http-server.py"
TEST_MEDIA = REPOSITORY.parent / "TestMedia"
EMBY_ADDRESS = "http://192.168.5.2:8096"
MEDIA_SUFFIXES = {".mp4", ".mkv", ".mov", ".m4v", ".ts", ".m2ts"}

# Transport decides how bytes arrive; it must not decide what the decoder sees.
COMPARED_FIELDS = (
    "codec", "samples", "sample_bytes", "decoded_frames",
    "submit_failures", "callback_failures", "decode",
)


def probe_binary(scratch):
    subprocess.run(
        ["swift", "build", "--package-path", str(PACKAGE),
         "--scratch-path", str(scratch), "--product", "PlaybackCoreRemoteMediaProbe"],
        check=True, stdout=sys.stderr,
    )
    bin_path = subprocess.run(
        ["swift", "build", "--package-path", str(PACKAGE),
         "--scratch-path", str(scratch), "--show-bin-path"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    return Path(bin_path) / "PlaybackCoreRemoteMediaProbe"


def parse_probe_output(text):
    fields = {}
    for token in text.split():
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


def run_probe(probe, url, seconds, timeout):
    command = [str(probe), "--stage", "decode", "--seconds", str(seconds), "--url", url]
    try:
        completed = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        return {"decode": "timeout"}
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip().splitlines()
        message = detail[-1] if detail else "unknown"
        # The corpus globs by suffix, and .mp4 also carries audio-only vectors.
        if "no audio stream" in message or "no video stream" in message:
            return {"decode": "not_video", "error": message}
        return {"decode": "probe_failed", "error": message}
    line = (completed.stdout or "").strip().splitlines()
    if not line:
        return {"decode": "no_output"}
    return parse_probe_output(line[-1])


class RangeServer:
    """Serves one directory over authenticated range HTTP for the parity comparison."""

    def __init__(self, directory, username="enchron-probe", password="remote-media"):
        self.directory = directory
        self.username = username
        self.password = password

    def __enter__(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="Enchron-parity-", dir="/Volumes/Cortisol"
        )
        ready = Path(self.temporary.name) / "port"
        self.process = subprocess.Popen(
            [sys.executable, str(SERVER), "--directory", str(self.directory),
             "--port", "0", "--username", self.username, "--password", self.password,
             "--log-file", str(Path(self.temporary.name) / "server.jsonl"),
             "--ready-file", str(ready)],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
        )
        deadline = time.time() + 30
        while not ready.exists():
            if self.process.poll() is not None:
                raise RuntimeError(self.process.stderr.read())
            if time.time() > deadline:
                raise RuntimeError("range server did not start")
            time.sleep(0.01)
        self.port = int(ready.read_text())
        return self

    def url_for(self, name):
        credentials = f"{quote(self.username, safe='')}:{quote(self.password, safe='')}"
        return f"http://{credentials}@127.0.0.1:{self.port}/{quote(name)}"

    def __exit__(self, *exception):
        self.process.terminate()
        self.process.wait(timeout=10)
        self.temporary.cleanup()


def local_corpus():
    for path in sorted(TEST_MEDIA.rglob("*")):
        if path.is_file() and path.suffix.lower() in MEDIA_SUFFIXES:
            yield path


def emby_corpus(address, include_sdr):
    token, user_id = authenticate(
        address, os.environ["EMBY_USER"], os.environ["EMBY_PASSWORD"]
    )
    result = request(
        address, f"/Users/{user_id}/Items", token=token,
        query={"Recursive": "true", "IncludeItemTypes": "Movie,Episode,Video",
               "Fields": "MediaSources", "Limit": "5000"},
    )
    for item in result.get("Items") or []:
        for source in item.get("MediaSources") or []:
            for stream in source.get("MediaStreams") or []:
                if stream.get("Type") != "Video":
                    continue
                video_range = stream.get("VideoRangeType") or stream.get("VideoRange")
                if not include_sdr and video_range == "SDR":
                    continue
                yield {
                    "name": item.get("Name"),
                    "itemID": item.get("Id"),
                    "range": video_range,
                    "url": f"{address}/Videos/{item['Id']}/stream"
                           f"?static=true&api_key={token}",
                }
                break


def compare(direct, served):
    differences = {}
    for field in COMPARED_FIELDS:
        if direct.get(field) != served.get(field):
            differences[field] = [direct.get(field), served.get(field)]
    return differences


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("local", "parity", "emby"), required=True)
    parser.add_argument("--seconds", type=float, default=5.0)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--address", default=EMBY_ADDRESS)
    parser.add_argument("--include-sdr", action="store_true")
    parser.add_argument("--filter", help="only media whose path or name matches this regex")
    parser.add_argument(
        "--scratch-path",
        default="/Volumes/Cortisol/DevSpace/Xcode/Enchron/PlaybackCoreBuild",
    )
    parser.add_argument("--output")
    arguments = parser.parse_args()

    if not str(arguments.scratch_path).startswith("/Volumes/Cortisol/"):
        parser.error("--scratch-path must be under /Volumes/Cortisol")
    probe = probe_binary(Path(arguments.scratch_path))
    pattern = re.compile(arguments.filter) if arguments.filter else None
    results = []

    if arguments.mode in ("local", "parity"):
        paths = [p for p in local_corpus()
                 if not pattern or pattern.search(str(p))]
        print(f"{len(paths)} local media files\n", file=sys.stderr)
        for path in paths:
            entry = {"name": str(path.relative_to(TEST_MEDIA)), "transport": "local"}
            entry.update(run_probe(probe, str(path), arguments.seconds, arguments.timeout))
            if arguments.mode == "parity":
                with RangeServer(path.parent) as server:
                    served = run_probe(
                        probe, server.url_for(path.name),
                        arguments.seconds, arguments.timeout,
                    )
                entry["http"] = served
                entry["differences"] = compare(entry, served)
            results.append(entry)
            status = entry.get("decode")
            mark = "differs" if entry.get("differences") else ""
            print(f"  {status:14s} {mark:8s} {entry['name'][:78]}", file=sys.stderr)
    else:
        items = [i for i in emby_corpus(arguments.address, arguments.include_sdr)
                 if not pattern or pattern.search(i["name"] or "")]
        print(f"{len(items)} Emby items\n", file=sys.stderr)
        with concurrent.futures.ThreadPoolExecutor(arguments.workers) as pool:
            probed = pool.map(
                lambda i: run_probe(probe, i["url"], arguments.seconds, arguments.timeout),
                items,
            )
            for item, fields in zip(items, probed):
                entry = {k: v for k, v in item.items() if k != "url"}
                entry["transport"] = "emby-http"
                entry.update(fields)
                results.append(entry)
                print(f"  {entry.get('decode'):14s} {entry['range']:12s} "
                      f"{(entry['name'] or '')[:60]}", file=sys.stderr)

    skipped = [r for r in results if r.get("decode") == "not_video"]
    failures = [r for r in results
                if r.get("decode") not in ("ok", "not_video")]
    mismatches = [r for r in results if r.get("differences")]
    print(f"\n{len(results)} probed, {len(failures)} not ok, "
          f"{len(skipped)} carried no video track, "
          f"{len(mismatches)} with transport differences")
    for entry in failures:
        print(f"  FAIL {entry.get('decode')}: {entry['name'][:70]} "
              f"{entry.get('error', '')}")
    for entry in mismatches:
        print(f"  DIFF {entry['name'][:70]}: {entry['differences']}")

    if arguments.output:
        Path(arguments.output).write_text(
            json.dumps(results, ensure_ascii=False, indent=2)
        )
        print(f"\nwrote {arguments.output}")
    return 1 if failures or mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
