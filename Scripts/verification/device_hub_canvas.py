#!/usr/bin/env python3
"""Drive the Device Hub Vision Pro Simulator canvas as a real gaze-and-pinch input surface.

Two hard-won facts are enforced here rather than written down and forgotten.
First, cliclick only reaches the canvas while Device Hub is the frontmost
application; anything else silently swallows the event and the run looks like a
product failure. Every pointer command therefore asserts frontmost and refuses
to fire otherwise. Second, targeting error scales with canvas size, so the
window is enlarged before use and the canvas rect is measured from pixels
instead of assumed.

The canvas renders the same first-person view that `simctl io screenshot`
captures, so the map from simulator screenshot pixels to Mac screen points is a
plain scale-and-offset once the canvas rect is known.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WINDOW_HELPER = Path(__file__).resolve().parent / "device_hub_window.swift"
OWNER = "Device Hub"
APP_PATH = "Contents/Applications/DeviceHub.app"
CHROME_DISTANCE = 40
ROW_COVERAGE = 0.5
COLUMN_COVERAGE = 0.5
CANVAS_ASPECT = 16 / 9
ASPECT_TOLERANCE = 0.01
CANVAS_WIDTH_FLOOR = 1200
MODE_GLYPH_DARKNESS = 100
MODE_GLYPH_GAP = 20
MODE_GLYPH_EDGE_MARGIN = 0.02
MODE_BUTTON_COUNTS = frozenset({10, 11})
BUTTONS_FROM_POINTER_TO_END = 7
SYSTEM_CONTROL_INDEX = {"home": 0}
DRAG_STEPS = 24
DRAG_SETTLE = 0.012


class CanvasError(RuntimeError):
    pass


def _run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def developer_root() -> Path:
    result = _run(["xcode-select", "-p"])
    if result.returncode != 0:
        raise CanvasError("xcode-select -p failed")
    return Path(result.stdout.strip()).parent.parent


def device_hub_app() -> Path:
    return developer_root() / APP_PATH


def frontmost_application() -> str:
    result = _run(
        [
            "osascript",
            "-e",
            'tell application "System Events" to return name of first process whose frontmost is true',
        ]
    )
    return result.stdout.strip()


def require_frontmost() -> None:
    current = frontmost_application()
    if current != "DeviceHub":
        raise CanvasError(
            f"Device Hub is not frontmost (frontmost={current!r}); pointer events would be delivered elsewhere"
        )


def activate(timeout: float = 8.0) -> None:
    _run(["open", "-a", str(device_hub_app())])
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if frontmost_application() == "DeviceHub":
            return
        time.sleep(0.2)
    raise CanvasError("Device Hub did not become frontmost")


def window_rect() -> dict[str, float]:
    result = _run(["xcrun", "swift", str(WINDOW_HELPER), OWNER])
    if result.returncode != 0:
        raise CanvasError(f"window helper failed: {result.stderr.strip()}")
    payload = json.loads(result.stdout)
    windows = payload.get("windows", [])
    if not windows:
        raise CanvasError("Device Hub has no on-screen window; open one from the Device Hub app")
    return max(windows, key=lambda w: w["width"] * w["height"])


def screen_size() -> tuple[int, int]:
    result = _run(
        [
            "osascript",
            "-e",
            'tell application "Finder" to return bounds of window of desktop',
        ]
    )
    parts = [int(p.strip()) for p in result.stdout.strip().split(",")]
    return parts[2], parts[3]


def drag(start: tuple[float, float], end: tuple[float, float]) -> None:
    require_frontmost()
    sx, sy = start
    ex, ey = end
    steps = [f"dd:{int(sx)},{int(sy)}"]
    for index in range(1, DRAG_STEPS + 1):
        ratio = index / DRAG_STEPS
        steps.append(f"dm:{int(sx + (ex - sx) * ratio)},{int(sy + (ey - sy) * ratio)}")
        steps.append(f"w:{int(DRAG_SETTLE * 1000)}")
    steps.append(f"du:{int(ex)},{int(ey)}")
    _run(["cliclick", *steps])
    time.sleep(0.4)


def enlarge(margin: int = 4, menu_bar: int = 38) -> dict[str, float]:
    activate()
    rect = window_rect()
    try:
        if canvas_rect(rect)["width"] >= CANVAS_WIDTH_FLOOR:
            return rect
    except CanvasError:
        pass
    screen_width, screen_height = screen_size()
    title_grip = (rect["x"] + rect["width"] - 240, rect["y"] + 24)
    drag(title_grip, (title_grip[0] - rect["x"] + margin, title_grip[1] - rect["y"] + menu_bar))
    rect = window_rect()
    corner = (rect["x"] + rect["width"] - 1, rect["y"] + rect["height"] - 1)
    drag(corner, (screen_width - margin, screen_height - margin))
    return window_rect()


def _longest_run(flags) -> tuple[int, int, int]:
    best = (0, 0, 0)
    current = None
    for index, value in enumerate(flags):
        if value and current is None:
            current = index
        elif not value and current is not None:
            if index - current > best[0]:
                best = (index - current, current, index - 1)
            current = None
    if current is not None and len(flags) - current > best[0]:
        best = (len(flags) - current, current, len(flags) - 1)
    return best


def _canvas_pixel_rect(image) -> dict[str, int]:
    import numpy

    flat = image.reshape(-1, 3)
    colors, counts = numpy.unique(flat, axis=0, return_counts=True)
    chrome = colors[counts.argmax()]
    mask = numpy.abs(image - chrome).sum(axis=2) > CHROME_DISTANCE
    row_hits = mask.sum(axis=1)
    rows = _longest_run(row_hits > ROW_COVERAGE * row_hits.max())
    if rows[0] == 0:
        raise CanvasError(
            "no canvas band found; is the simulator canvas rendering, and is the zoom control set to fit rather than 1:1?"
        )
    band = mask[rows[1] : rows[2] + 1, :]
    columns = _longest_run(band.sum(axis=0) > COLUMN_COVERAGE * band.shape[0])
    if columns[0] == 0:
        raise CanvasError("canvas band has no contiguous columns")
    aspect = columns[0] / rows[0]
    if abs(aspect - CANVAS_ASPECT) / CANVAS_ASPECT > ASPECT_TOLERANCE:
        raise CanvasError(
            f"detected canvas aspect {aspect:.4f} is not the simulator's {CANVAS_ASPECT:.4f}; refusing to target off a bad "
            "measurement. At 1:1 zoom the canvas does not fill the pane and this check fails; set the toolbar zoom "
            "control to fit."
        )
    return {
        "x": columns[1],
        "y": rows[1],
        "width": columns[0],
        "height": rows[0],
    }


def canvas_rect(rect: dict[str, float] | None = None) -> dict[str, int]:
    rect = rect or window_rect()
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as handle:
        shot = Path(handle.name)
    region = f"{int(rect['x'])},{int(rect['y'])},{int(rect['width'])},{int(rect['height'])}"
    _run(["screencapture", "-x", "-R", region, str(shot)])
    try:
        from PIL import Image
        import numpy

        image = numpy.asarray(Image.open(shot).convert("RGB")).astype(numpy.int16)
        pixels = _canvas_pixel_rect(image)
    finally:
        shot.unlink(missing_ok=True)
    scale = image.shape[1] / rect["width"]
    return {
        "x": int(round(rect["x"] + pixels["x"] / scale)),
        "y": int(round(rect["y"] + pixels["y"] / scale)),
        "width": int(round(pixels["width"] / scale)),
        "height": int(round(pixels["height"] / scale)),
    }


def _glyph_spans(band) -> tuple[list[list[int]], object]:
    dark = band < MODE_GLYPH_DARKNESS
    columns = dark.sum(axis=0) > 2
    spans: list[list[int]] = []
    for index, lit in enumerate(columns):
        if not lit:
            continue
        if spans and index - spans[-1][1] <= MODE_GLYPH_GAP:
            spans[-1][1] = index
        else:
            spans.append([index, index])
    lower = band.shape[1] * MODE_GLYPH_EDGE_MARGIN
    upper = band.shape[1] * (1 - MODE_GLYPH_EDGE_MARGIN)
    spans = [
        span
        for span in spans
        if span[1] - span[0] >= 2
        and lower <= (span[0] + span[1]) / 2 <= upper
    ]
    return spans, dark


def mode_buttons(rect: dict[str, float], canvas: dict[str, int]) -> list[tuple[float, float]]:
    top = canvas["y"] + canvas["height"]
    height = rect["y"] + rect["height"] - top
    if height <= 0:
        raise CanvasError("no toolbar band below the canvas")
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as handle:
        shot = Path(handle.name)
    _run(["screencapture", "-x", "-R", f"{int(rect['x'])},{int(top)},{int(rect['width'])},{int(height)}", str(shot)])
    try:
        from PIL import Image
        import numpy

        band = numpy.asarray(Image.open(shot).convert("L")).astype(numpy.int16)
    finally:
        shot.unlink(missing_ok=True)
    scale = band.shape[1] / rect["width"]
    spans, dark = _glyph_spans(band)
    glyph_mask = numpy.zeros_like(dark)
    for lower, upper in spans:
        glyph_mask[:, lower : upper + 1] = dark[:, lower : upper + 1]
    rows = numpy.where(glyph_mask)[0]
    if rows.size == 0:
        raise CanvasError("toolbar band has no glyphs")
    centre = top + (int(rows.min()) + int(rows.max())) / 2 / scale
    return [(rect["x"] + (span[0] + span[1]) / 2 / scale, centre) for span in spans]


def _pointer_mode_index(button_count: int) -> int:
    if button_count not in MODE_BUTTON_COUNTS:
        expected = ", ".join(str(count) for count in sorted(MODE_BUTTON_COUNTS))
        raise CanvasError(
            f"found {button_count} canvas toolbar buttons, expected one of {expected}; "
            "the toolbar layout changed and the pointer-mode index can no longer be trusted"
        )
    return button_count - BUTTONS_FROM_POINTER_TO_END


def select_pointer_mode(rect: dict[str, float], canvas: dict[str, int]) -> tuple[float, float]:
    buttons = mode_buttons(rect, canvas)
    target = buttons[_pointer_mode_index(len(buttons))]
    require_frontmost()
    _run(["cliclick", f"c:{int(round(target[0]))},{int(round(target[1]))}"])
    time.sleep(0.3)
    return target


def click_system_control(
    rect: dict[str, float], canvas: dict[str, int], control: str
) -> tuple[float, float]:
    buttons = mode_buttons(rect, canvas)
    _pointer_mode_index(len(buttons))
    target = buttons[SYSTEM_CONTROL_INDEX[control]]
    require_frontmost()
    _run(["cliclick", f"c:{int(round(target[0]))},{int(round(target[1]))}"])
    time.sleep(0.5)
    return target


def simulator_screenshot(device: str, destination: Path | None = None) -> tuple[Path, tuple[int, int]]:
    if destination is None:
        handle = tempfile.NamedTemporaryFile(suffix=".png", delete=False, dir=os.environ.get("TMPDIR"))
        handle.close()
        destination = Path(handle.name)
    result = _run(["xcrun", "simctl", "io", device, "screenshot", str(destination)])
    if not destination.exists():
        raise CanvasError(
            f"simctl refused to write {destination}; screenshots must land in TMPDIR, not inside the repository ({result.stderr.strip()})"
        )
    from PIL import Image

    with Image.open(destination) as image:
        return destination, image.size


def bind_booted_vision_target(device: str) -> dict[str, str]:
    if not device:
        raise CanvasError("--device must identify the Simulator controlled by Device Hub")
    result = _run(["xcrun", "simctl", "list", "devices", "booted", "--json"])
    if result.returncode != 0:
        raise CanvasError(f"cannot enumerate booted simulators: {result.stderr.strip()}")
    try:
        runtimes = json.loads(result.stdout)["devices"]
        candidates = [
            {
                "device": str(entry["udid"]),
                "name": str(entry["name"]),
                "runtime": str(runtime),
            }
            for runtime, entries in runtimes.items()
            for entry in entries
            if entry.get("state") == "Booted"
            and "Apple-Vision" in str(entry.get("deviceTypeIdentifier", ""))
        ]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        raise CanvasError("simctl returned an invalid booted-device document") from error
    if len(candidates) != 1:
        raise CanvasError(
            "Device Hub input requires exactly one booted visionOS Simulator; "
            f"observed {len(candidates)}"
        )
    binding = candidates[0]
    if binding["device"].casefold() != device.casefold():
        raise CanvasError(
            f"Device Hub controls {binding['device']}, not requested target {device}"
        )
    return binding


def map_point(canvas: dict[str, int], shot_size: tuple[int, int], x: float, y: float) -> tuple[int, int]:
    shot_width, shot_height = shot_size
    return (
        int(round(canvas["x"] + x / shot_width * canvas["width"])),
        int(round(canvas["y"] + y / shot_height * canvas["height"])),
    )


def require_targetable(canvas: dict[str, int], allow_small: bool) -> None:
    if allow_small or canvas["width"] >= CANVAS_WIDTH_FLOOR:
        return
    raise CanvasError(
        f"canvas is only {canvas['width']} points wide; run `enlarge` first or pass --allow-small. "
        "A small canvas multiplies pointing error by the same factor it shrinks the view. Enlarging the window is "
        "not enough on its own: the toolbar zoom control must be on fit, not 1:1."
    )


def gaze(point: tuple[int, int]) -> None:
    require_frontmost()
    _run(["cliclick", f"m:{point[0]},{point[1]}"])


def pinch(point: tuple[int, int], dwell: float = 0.6) -> None:
    require_frontmost()
    _run(["cliclick", f"m:{point[0]},{point[1]}", f"w:{int(dwell * 1000)}", f"c:{point[0]},{point[1]}"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--device", default=os.environ.get("ENCHRON_TARGET_DEVICE", ""))
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("enlarge")
    system_control = sub.add_parser("system-control")
    system_control.add_argument(
        "--control", choices=tuple(SYSTEM_CONTROL_INDEX), required=True
    )
    for name in ("gaze", "pinch"):
        action = sub.add_parser(name)
        action.add_argument("--shot-x", type=float, required=True)
        action.add_argument("--shot-y", type=float, required=True)
        action.add_argument("--shot-width", type=float, required=True)
        action.add_argument("--shot-height", type=float, required=True)
        action.add_argument("--allow-small", action="store_true")

    args = parser.parse_args(argv)
    try:
        target_binding = bind_booted_vision_target(args.device)
        if args.command == "enlarge":
            rect = enlarge()
            canvas = canvas_rect(rect)
            pointer = select_pointer_mode(rect, canvas)
            print(
                json.dumps(
                    {
                        "window": rect,
                        "canvas": canvas,
                        "pointerMode": pointer,
                        "targetBinding": target_binding,
                    },
                    sort_keys=True,
                )
            )
            return 0
        if args.command == "status":
            rect = window_rect()
            print(
                json.dumps(
                    {
                        "frontmost": frontmost_application(),
                        "window": rect,
                        "canvas": canvas_rect(rect),
                        "modeButtons": mode_buttons(rect, canvas_rect(rect)),
                        "screen": screen_size(),
                        "targetBinding": target_binding,
                    },
                    sort_keys=True,
                )
            )
            return 0
        activate()
        rect = window_rect()
        canvas = canvas_rect(rect)
        require_targetable(canvas, getattr(args, "allow_small", False))
        if args.command == "system-control":
            target = click_system_control(rect, canvas, args.control)
            print(
                json.dumps(
                    {
                        "canvas": canvas,
                        "control": args.control,
                        "point": target,
                        "targetBinding": target_binding,
                    },
                    sort_keys=True,
                )
            )
            return 0
        select_pointer_mode(rect, canvas)
        point = map_point(canvas, (args.shot_width, args.shot_height), args.shot_x, args.shot_y)
        if args.command == "gaze":
            gaze(point)
        else:
            pinch(point)
        print(
            json.dumps(
                {"canvas": canvas, "point": point, "targetBinding": target_binding},
                sort_keys=True,
            )
        )
        return 0
    except CanvasError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
