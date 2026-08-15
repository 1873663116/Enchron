#!/usr/bin/env python3

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from urllib.parse import quote


REPOSITORY = Path(__file__).resolve().parents[2]
PACKAGE = REPOSITORY / "Packages" / "PlaybackCore"
SERVER = REPOSITORY / "Scripts" / "fixtures" / "range-http-server.py"
DEFAULT_MEDIA = (
    REPOSITORY.parent
    / "TestMedia"
    / "Samples"
    / "Spatial"
    / "Stereo180"
    / "HNVR-158_H_4096p_8K_LR_180_clip.mp4"
)
DEFAULT_SCRATCH = Path(
    "/Volumes/Cortisol/DerivedData/Enchron-remote-media-open-probe"
)
STAGES = ("tracks", "video-reader", "audio-reader")


def run_checked(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def read_events(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line]


def stage_result(
    stage,
    output,
    events,
    previous_event_count,
):
    match = re.search(r"bytes_read=(\d+)", output)
    if not match:
        raise RuntimeError(f"probe did not report bytes for {stage}: {output.strip()}")
    current_events = events[previous_event_count:]
    wire_requests = [entry for entry in current_events if entry["event"] == "request"]
    media_requests = [
        entry for entry in wire_requests if 200 <= entry["status"] < 400
    ]
    authentication_requests = [
        entry for entry in wire_requests if entry["status"] == 401
    ]
    connections = [
        entry for entry in current_events if entry["event"] == "connection_open"
    ]
    return {
        "stage": stage,
        "requests": len(media_requests),
        "tcp_connections": len(
            {entry["connection_id"] for entry in media_requests}
        ),
        "bytes_read": int(match.group(1)),
        "authentication_requests": len(authentication_requests),
        "wire_requests": len(wire_requests),
        "wire_tcp_connections": len(connections),
        "statuses": [entry["status"] for entry in wire_requests],
        "ranges": [entry.get("range") for entry in media_requests],
    }, len(events)


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Serve a real media file over authenticated range HTTP, run PlaybackCore's "
            "track enumeration plus video and audio reader opens, and report successful "
            "media request, media connection, FFmpeg-read byte, and authentication "
            "wire counts by stage."
        )
    )
    parser.add_argument("--media", type=Path, default=DEFAULT_MEDIA)
    parser.add_argument("--scratch-path", type=Path, default=DEFAULT_SCRATCH)
    parser.add_argument("--username", default="enchron-probe")
    parser.add_argument("--password", default="remote-media")
    parser.add_argument("--json", action="store_true")
    arguments = parser.parse_args()

    media = arguments.media.resolve()
    if not media.is_file():
        parser.error(f"media file does not exist: {media}")
    scratch = arguments.scratch_path.resolve()
    if not str(scratch).startswith("/Volumes/Cortisol/"):
        parser.error("--scratch-path must be under /Volumes/Cortisol")
    scratch.mkdir(parents=True, exist_ok=True)

    run_checked(
        [
            "swift",
            "build",
            "--package-path",
            str(PACKAGE),
            "--scratch-path",
            str(scratch),
            "--product",
            "PlaybackCoreRemoteMediaProbe",
        ],
        stdout=sys.stderr,
    )
    bin_path = run_checked(
        [
            "swift",
            "build",
            "--package-path",
            str(PACKAGE),
            "--scratch-path",
            str(scratch),
            "--show-bin-path",
        ],
        capture_output=True,
    ).stdout.strip()
    probe = Path(bin_path) / "PlaybackCoreRemoteMediaProbe"

    with tempfile.TemporaryDirectory(
        prefix="Enchron-remote-media-open-", dir="/Volumes/Cortisol"
    ) as temporary:
        temporary_path = Path(temporary)
        log_file = temporary_path / "server.jsonl"
        ready_file = temporary_path / "port"
        server = subprocess.Popen(
            [
                sys.executable,
                str(SERVER),
                "--directory",
                str(media.parent),
                "--port",
                "0",
                "--username",
                arguments.username,
                "--password",
                arguments.password,
                "--log-file",
                str(log_file),
                "--ready-file",
                str(ready_file),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            while not ready_file.exists():
                if server.poll() is not None:
                    raise RuntimeError(server.stderr.read())
                time.sleep(0.01)
            port = int(ready_file.read_text())
            url = (
                f"http://{quote(arguments.username, safe='')}:{quote(arguments.password, safe='')}"
                f"@127.0.0.1:{port}/{quote(media.name)}"
            )
            results = []
            event_count = 0
            for stage in STAGES:
                completed = run_checked(
                    [str(probe), "--stage", stage, "--url", url],
                    capture_output=True,
                )
                events = read_events(log_file)
                result, event_count = stage_result(
                    stage,
                    completed.stdout,
                    events,
                    event_count,
                )
                results.append(result)
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()

    report = {
        "media": str(media),
        "stages": results,
        "total": {
            "requests": sum(item["requests"] for item in results),
            "tcp_connections": sum(item["tcp_connections"] for item in results),
            "bytes_read": sum(item["bytes_read"] for item in results),
        },
        "wire_total": {
            "requests": sum(item["wire_requests"] for item in results),
            "tcp_connections": sum(
                item["wire_tcp_connections"] for item in results
            ),
            "authentication_requests": sum(
                item["authentication_requests"] for item in results
            ),
        },
    }
    if arguments.json:
        print(json.dumps(report, indent=2))
        return
    for item in results:
        print(
            f"{item['stage']}: requests={item['requests']} "
            f"connections={item['tcp_connections']} bytes={item['bytes_read']}"
        )
        print(
            f"  wire_requests={item['wire_requests']} "
            f"wire_connections={item['wire_tcp_connections']} "
            f"authentication_requests={item['authentication_requests']}"
        )
        print("  ranges=" + ", ".join(value or "none" for value in item["ranges"]))
    total = report["total"]
    print(
        f"total: requests={total['requests']} "
        f"connections={total['tcp_connections']} bytes={total['bytes_read']}"
    )
    wire_total = report["wire_total"]
    print(
        f"wire_total: requests={wire_total['requests']} "
        f"connections={wire_total['tcp_connections']} "
        f"authentication_requests={wire_total['authentication_requests']}"
    )


if __name__ == "__main__":
    main()
