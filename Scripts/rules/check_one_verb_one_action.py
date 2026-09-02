#!/usr/bin/env python3
from __future__ import annotations
import re
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CHANNEL_PATH = REPOSITORY_ROOT / "Apps/Enchron/TestCommandChannel.swift"

def failures() -> list[str]:
    found: list[str] = []
    try:
        text = CHANNEL_PATH.read_text(encoding="utf-8")
    except OSError:
        return [f"{CHANNEL_PATH}: cannot read file"]
    pattern = re.compile(r'case\s+"([^"]+)"\s*:')
    matches = list(pattern.finditer(text))
    for idx, match in enumerate(matches):
        verb = match.group(1)
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        body = text[start:end]
        has_auth = bool(re.search(r'\bauthenticate\b', body, re.IGNORECASE) or re.search(r'prepareAutomationAccount', body) or re.search(r'session.*install|install.*session', body, re.IGNORECASE))
        has_fixture = bool(re.search(r'externalSubtitleStreamIndex', body) or re.search(r'\bfixture\b', body, re.IGNORECASE) or re.search(r'itemID.*mediaSourceID|mediaSourceID.*itemID', body) or re.search(r'playbackInfo', body))
        if has_auth and has_fixture:
            if verb == "prepareEmbyAccount":
                continue
            found.append(f"{CHANNEL_PATH.relative_to(REPOSITORY_ROOT)}: case \"{verb}\" references both authenticate/session install and fixture/stream verification")
    return sorted(found)

def main() -> int:
    found = failures()
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} one-verb-one-action violations")
        return 1
    print("no one-verb-one-action violations")
    return 0

if __name__ == "__main__":
    sys.exit(main())
