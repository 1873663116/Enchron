import argparse
import json
from pathlib import Path
import struct


def main() -> int:
    parser = argparse.ArgumentParser(description="Check captured series detail, episode order, and resume visibility.")
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--provider", choices=("emby", "jellyfin", "plex"), required=True)
    parser.add_argument("--series", required=True)
    parser.add_argument("--season", required=True)
    parser.add_argument("--expected-order", type=Path, required=True)
    parser.add_argument("--episode")
    parser.add_argument("--target-snapshot", type=Path)
    arguments = parser.parse_args()
    if bool(arguments.episode) != bool(arguments.target_snapshot):
        parser.error("--episode and --target-snapshot must be supplied together")
    failures = []
    try:
        snapshot = json.loads(arguments.snapshot.read_text())
        expected_order = json.loads(arguments.expected_order.read_text())
        if not isinstance(expected_order, list) or not expected_order or not all(isinstance(item, str) for item in expected_order):
            raise ValueError("expected order must be a nonempty array of episode IDs")
        if len(set(expected_order)) != len(expected_order):
            raise ValueError("expected order contains duplicate episode IDs")
        if snapshot["success"] is not True:
            raise ValueError("detail snapshot capture failed")
        matched = snapshot["matchedElement"]
        if matched["identifier"] != "Emby-Evidence":
            raise ValueError("detail snapshot must capture Emby-Evidence")
        document = json.loads(matched["value"])
        if document["detail"]["status"] != "observed":
            raise ValueError("series detail was not observed")
        detail = document["detail"]["value"]
        checks = {
            "provider": (document["account"]["provider"], arguments.provider),
            "detail kind": (detail["itemKind"], "series"),
            "detail identity": (detail["itemID"], arguments.series),
            "series identity": (detail["seriesID"], arguments.series),
            "selected season": (detail.get("selectedSeasonID"), arguments.season),
            "episode order": (detail["episodeIDs"], expected_order),
        }
        if arguments.episode:
            checks["resume target"] = (detail.get("primaryPlaybackItemID"), arguments.episode)
            target_snapshot = json.loads(arguments.target_snapshot.read_text())
            if target_snapshot["success"] is not True:
                raise ValueError("target snapshot capture failed")
            if target_snapshot["sessionID"] != snapshot["sessionID"]:
                raise ValueError("detail and target snapshots belong to different sessions")
            target = target_snapshot["matchedElement"]
            checks["visible episode"] = (target["identifier"], "Emby-Episode-" + arguments.episode)
            checks["episode is hittable"] = (target["isHittable"], True)
            screenshot = Path(target_snapshot["localScreenshotPath"]).read_bytes()
            if screenshot[:8] != b"\x89PNG\r\n\x1a\n":
                raise ValueError("target screenshot must be a PNG")
            width, height = struct.unpack(">II", screenshot[16:24])
            if width <= 1 or height <= 1:
                raise ValueError("target screenshot has no usable pixels")
            frame = target["frame"]
            visible = (
                frame["width"] > 0 and frame["height"] > 0
                and frame["x"] >= 0 and frame["y"] >= 0
                and frame["x"] + frame["width"] <= width
                and frame["y"] + frame["height"] <= height
            )
            checks["episode is inside screenshot"] = (visible, True)
        failures.extend(name for name, (observed, expected) in checks.items() if observed != expected)
    except (OSError, ValueError, KeyError, TypeError, struct.error) as error:
        failures.append(str(error))
    print(json.dumps({
        "verdict": "failed" if failures else "passed",
        "provider": arguments.provider,
        "seriesID": arguments.series,
        "seasonID": arguments.season,
        "targetEpisodeID": arguments.episode,
        "failures": failures,
    }, ensure_ascii=False, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
