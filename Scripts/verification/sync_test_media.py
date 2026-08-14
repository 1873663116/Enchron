#!/usr/bin/env python3
"""Copy new media from the Desktop staging tree into the shared TestMedia tree.

The Desktop tree is where new sources land, because it shares an iCloud account
with the headset. iCloud may evict a Desktop file to a placeholder at any time,
so nothing that a sweep reads may live only there. The shared tree on the
external disk is the one verification reads, and its paths are what the sweep
scripts already name.

The two trees organize the same file differently: Desktop keeps the download
layout, the shared tree groups by provenance. Matching on name and byte size
rather than on path is what lets a file that was already filed under a different
directory be recognized instead of copied twice.
"""

import argparse
import os
import shutil
import sys

DEFAULT_SOURCE = os.path.expanduser("~/Desktop/TestMedia")
DEFAULT_TARGET = "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
IGNORED = {".DS_Store"}


def index_by_name_and_size(root):
    index = {}
    for directory, _, files in os.walk(root):
        for name in files:
            if name in IGNORED:
                continue
            path = os.path.join(directory, name)
            try:
                index.setdefault((name, os.path.getsize(path)), path)
            except OSError:
                continue
    return index


def evicted(path):
    """An iCloud placeholder reports its full logical size but occupies no blocks."""
    status = os.stat(path)
    return status.st_size > 0 and status.st_blocks == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=DEFAULT_SOURCE)
    parser.add_argument("--target", default=DEFAULT_TARGET)
    parser.add_argument("--apply", action="store_true")
    arguments = parser.parse_args()

    if not os.path.isdir(arguments.source):
        sys.exit(f"source tree is absent: {arguments.source}")
    if not os.path.isdir(arguments.target):
        sys.exit(f"target tree is absent: {arguments.target}")

    known = index_by_name_and_size(arguments.target)
    pending, placeholders = [], []
    for directory, _, files in os.walk(arguments.source):
        for name in sorted(files):
            if name in IGNORED:
                continue
            path = os.path.join(directory, name)
            size = os.path.getsize(path)
            if (name, size) in known:
                continue
            (placeholders if evicted(path) else pending).append(
                (os.path.relpath(path, arguments.source), size)
            )

    for relative, size in placeholders:
        print(f"EVICTED  {size / 1048576:9.1f} MB  {relative}")
    for relative, size in pending:
        print(f"{'COPY' if arguments.apply else 'NEW '}     "
              f"{size / 1048576:9.1f} MB  {relative}")

    if arguments.apply:
        for relative, _ in pending:
            source = os.path.join(arguments.source, relative)
            target = os.path.join(arguments.target, relative)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(source, target)

    total = sum(size for _, size in pending)
    print(f"\n{len(pending)} file(s), {total / 1073741824:.2f} GB"
          f"{' copied' if arguments.apply else ' pending, pass --apply to copy'}")
    if placeholders:
        print(f"{len(placeholders)} file(s) are iCloud placeholders. Open them on the "
              f"Mac to materialize, then rerun.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
