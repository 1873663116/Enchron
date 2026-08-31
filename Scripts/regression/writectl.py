#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))

from write_set import WriteSetError, parse_json_bytes, report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Reject concurrently runnable tasks with overlapping repository write scopes."
    )
    parser.add_argument("plan", type=Path)
    arguments = parser.parse_args()
    try:
        plan = parse_json_bytes(arguments.plan.read_bytes())
    except (OSError, WriteSetError) as error:
        print(f"invalid write plan: {error}", file=sys.stderr)
        return 2
    payload = report(plan)
    print(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True))
    return 0 if payload["safe"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
