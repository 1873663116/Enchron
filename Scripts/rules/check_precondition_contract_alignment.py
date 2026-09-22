#!/usr/bin/env python3
from __future__ import annotations
import re
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CHANNEL_PATH = REPOSITORY_ROOT / "Apps/Enchron/DebugSupport/TestCommandChannel.swift"
OPERATIONS_ROOT = REPOSITORY_ROOT / "Regression/operations"

VERB_TO_OPERATION = {
    "armTransitionTrace": "transition-trace-arm-v1.md",
    "fetchTransitionTraceSnapshot": "transition-trace-fetch-v1.md",
    "resetState": "harness-reset-product-state-v2.md",
    "importMedia": "media-import-staged-v2.md",
    "importMediaDirectory": "preparation-local-directory-subtitle-source-v1.md",
}

def failures() -> list[str]:
    found: list[str] = []
    try:
        text = CHANNEL_PATH.read_text(encoding="utf-8")
    except OSError:
        return [f"{CHANNEL_PATH}: cannot read file"]
    for verb, filename in VERB_TO_OPERATION.items():
        pattern = re.compile(r'case\s+"%s"\s*:' % re.escape(verb))
        m = pattern.search(text)
        if not m:
            continue
        start = m.end()
        next_match = re.search(r'case\s+"[^"]+"\s*:', text[start:])
        end = start + next_match.start() if next_match else len(text)
        body = text[start:end]
        throws = re.findall(r'throw\s+CommandError\s*\(\s*message\s*:\s*"([^"]+)"\s*\)', body)
        requires = [msg for msg in throws if "requires" in msg.lower()]
        if not requires:
            continue
        op_path = OPERATIONS_ROOT / filename
        try:
            op_text = op_path.read_text(encoding="utf-8")
        except OSError:
            found.append(f"{op_path}: cannot read operation contract for verb {verb}")
            continue
        for msg in requires:
            key = msg.split("requires")[1].strip().split()[0:3]
            phrase = " ".join(key).strip('".,')
            if phrase.lower() not in op_text.lower() and "requires" not in op_text.lower():
                found.append(f"{op_path.relative_to(REPOSITORY_ROOT)}: missing precondition '{msg}' for verb {verb}")
            elif msg.lower() not in op_text.lower():
                snippet = msg[:40]
                if snippet.lower() not in op_text.lower():
                    found.append(f"{op_path.relative_to(REPOSITORY_ROOT)}: missing precondition '{msg}' for verb {verb}")
    return sorted(found)

def main() -> int:
    found = failures()
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} precondition contract alignment violations")
        return 1
    print("no precondition contract alignment violations")
    return 0

if __name__ == "__main__":
    sys.exit(main())
