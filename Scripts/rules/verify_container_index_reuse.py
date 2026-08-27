#!/usr/bin/env python3
"""Prove a second open of the same remote file fetches no container index.

The Container Index Cache claims that once a remote file has been opened, a
later open of the same Content Revision reads the moov/Cues region from disk
instead of the network. The authoritative witness is the media server's own
request log: on the second open, no byte-range request may touch the head or
tail window of the file, because that is where every supported container keeps
its index.

Usage:
    verify_container_index_reuse.py --log <embyserver.txt> --item <id>
        [--source-ip <device ip>] [--gap-seconds 30] [--window-bytes 8388608]

Protocol: in a quiet window with no other client touching the item, open the
file on the device, exit playback, wait past --gap-seconds, open it again,
then run this script. Pass --source-ip with the device address so probes from
other machines cannot contaminate the verdict; a 2026-08-16 run misread a curl
probe from the Mac as an index fetch until the filter existed.

Reads every range request for /Videos/<id>/stream.* from the log, groups them
into opens separated by --gap-seconds of silence, and judges the LAST open:
pass when none of its requests intersect the first or last --window-bytes of
the file. The file size comes from Content-Range totals in the same log.

Exit codes: 0 index reuse proven, 1 the second open still fetched index bytes,
2 the check could not run (fewer than two opens, no size, unreadable log).
"""

import argparse
import re
import sys
import unicodedata
from datetime import datetime
from pathlib import Path

TIMESTAMP = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)")
RANGE = re.compile(r"Range=bytes=(\d+)-(\d*)")
TOTAL = re.compile(r"Content-Range=bytes \d+-\d+/(\d+)")
SOURCE_IP = re.compile(r"Source Ip: ([0-9.]+)")


def clean(line: str) -> str:
    return "".join(c for c in line if unicodedata.category(c) != "Cf")


def parse(log: Path, item: str, source_ip: str | None):
    stream_marker = f"/Videos/{item}/stream"
    requests, totals = [], set()
    for raw in log.open(encoding="utf-8", errors="replace"):
        line = clean(raw)
        if stream_marker not in line:
            continue
        stamp = TIMESTAMP.match(line)
        if not stamp:
            continue
        when = datetime.fromisoformat(stamp.group(1))
        if total := TOTAL.search(line):
            totals.add(int(total.group(1)))
        elif byte_range := RANGE.search(line):
            if source_ip:
                seen = SOURCE_IP.search(line)
                if not seen or seen.group(1) != source_ip:
                    continue
            start = int(byte_range.group(1))
            end = int(byte_range.group(2)) if byte_range.group(2) else None
            requests.append((when, start, end))
    return requests, totals


def group_opens(requests, gap_seconds: float):
    opens, current = [], []
    for request in sorted(requests, key=lambda r: r[0]):
        if current and (request[0] - current[-1][0]).total_seconds() > gap_seconds:
            opens.append(current)
            current = []
        current.append(request)
    if current:
        opens.append(current)
    return opens


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--item", required=True)
    parser.add_argument("--source-ip", default=None)
    parser.add_argument("--gap-seconds", type=float, default=30.0)
    parser.add_argument("--window-bytes", type=int, default=8 * 1024 * 1024)
    arguments = parser.parse_args()

    if not arguments.log.is_file():
        print(f"log not found: {arguments.log}", file=sys.stderr)
        return 2
    requests, totals = parse(arguments.log, arguments.item, arguments.source_ip)
    if len(totals) > 1:
        print(f"conflicting file sizes in log: {sorted(totals)}", file=sys.stderr)
        return 2
    if not totals:
        print("no Content-Range total found; cannot locate the tail window", file=sys.stderr)
        return 2
    size = totals.pop()

    opens = group_opens(requests, arguments.gap_seconds)
    if len(opens) < 2:
        print(
            f"found {len(opens)} open(s) for item {arguments.item}; "
            "need a first open to warm the cache and a second to judge",
            file=sys.stderr,
        )
        return 2

    second = opens[-1]
    head_end = arguments.window_bytes
    tail_start = size - arguments.window_bytes
    index_hits = [
        (when, start, end)
        for when, start, end in second
        if start < head_end or (end if end is not None else size - 1) >= tail_start
    ]

    print(
        f"item {arguments.item}: {len(opens)} opens, size {size}, "
        f"second open at {second[0][0]} with {len(second)} requests"
    )
    if not index_hits:
        print(f"  no request touched the first or last {arguments.window_bytes} bytes")
        return 0
    print(f"  {len(index_hits)} index-window request(s) on the second open:")
    for when, start, end in index_hits:
        print(f"    {when}  bytes={start}-{'' if end is None else end}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
