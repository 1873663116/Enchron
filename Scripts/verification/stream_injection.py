#!/usr/bin/env python3
"""Drive the controller and feedback paths that a device would drive.

The G1 and G2 gates ask for hardware this machine does not have: a pad that
reports motion, battery and a light, extended buttons, a touchpad, a keyboard and
a five button mouse. The client-side halves of those paths are reachable through
the debug test channel, so this script is their driver: it sends the injection
verb, the app enters the same function the real GameController callback or the
real host feedback would enter, and the probes the gates read are written by the
production code.

Every subcommand forwards to ``Scripts/console/transport.py app-command``; the
verb names appear here so the orphan-verb check has an owner for each one.

usage:
    stream_injection.py --device <UDID> profile --kind playstation --caps all --buttons a,special
    stream_injection.py --device <UDID> profile-remove
    stream_injection.py --device <UDID> feedback --type rumble --arg low=100 --arg high=200
    stream_injection.py --device <UDID> feedback --type motion --arg motionType=1 --arg rate=60
    stream_injection.py --device <UDID> touchpad --x 0.25 --y -0.5
    stream_injection.py --device <UDID> motion --enable true
    stream_injection.py --device <UDID> battery --state 2 --percentage 55
    stream_injection.py --device <UDID> highres-scroll --vertical 1 --horizontal 0
    stream_injection.py --device <UDID> settings
    stream_injection.py --device <UDID> set-settings --audio-layout surround51 --stats-overlay true
    stream_injection.py --device <UDID> quality --value 1
    stream_injection.py --device <UDID> discovered
    stream_injection.py --device <UDID> start-discovery
    stream_injection.py --device <UDID> stop-discovery
    stream_injection.py --device <UDID> pin-host --host 127.0.0.1 --port 47989
    stream_injection.py --device <UDID> reconnect
    stream_injection.py --device <UDID> wake --host DESKTOP-LBIAG7N

The options before the subcommand are the transport's own; ``--execution-input``
is required whenever the console has not already frozen a launch.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

VERIFICATION_ROOT = Path(__file__).resolve().parent
REPOSITORY_ROOT = VERIFICATION_ROOT.parents[1]
sys.path.insert(0, str(VERIFICATION_ROOT))

from harness.local import LocalToolRunner

CONTROLLER = REPOSITORY_ROOT / "Scripts/console/transport.py"


def controller(arguments: argparse.Namespace, *command: str) -> dict:
    invocation = LocalToolRunner(lane="stream-injection").run(
        "stream-injection",
        [
            sys.executable,
            str(CONTROLLER),
            "--device",
            arguments.device,
            "--execution-input",
            arguments.execution_input,
            "--output-directory",
            str(Path(arguments.evidence_dir) / "session"),
            *command,
            "--no-screenshot",
        ],
    )
    try:
        return json.loads(invocation.stdout, strict=False)
    except json.JSONDecodeError:
        return {
            "success": False,
            "error": invocation.stdout[-400:] or invocation.stderr[-400:],
        }


def app_command(arguments: argparse.Namespace, verb: str, pairs: list[str]) -> dict:
    command = ["app-command", "--verb", verb]
    for pair in pairs:
        command += ["--arg", pair]
    return controller(arguments, *command)


def inject_profile(arguments: argparse.Namespace) -> dict:
    return app_command(
        arguments,
        "streamInjectProfile",
        [
            f"kind={arguments.kind}",
            f"caps={arguments.caps}",
            f"buttons={arguments.buttons}",
            f"number={arguments.number}",
            f"mask={arguments.mask}",
        ],
    )


def inject_feedback(arguments: argparse.Namespace) -> dict:
    pairs = [f"type={arguments.type}"]
    for item in arguments.arg:
        if "=" not in item:
            raise SystemExit(f"invalid --arg {item!r}; expected key=value")
        pairs.append(item)
    return app_command(arguments, "streamInjectFeedback", pairs)


def inject_touchpad(arguments: argparse.Namespace) -> dict:
    return app_command(
        arguments,
        "streamInjectTouchpad",
        [f"x={arguments.x}", f"y={arguments.y}", f"index={arguments.index}"],
    )


def inject_motion(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamInjectMotion", [f"enable={arguments.enable}"])


def inject_battery(arguments: argparse.Namespace) -> dict:
    return app_command(
        arguments,
        "streamInjectBattery",
        [f"state={arguments.state}", f"percentage={arguments.percentage}"],
    )


def remove_profile(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamInjectProfileRemove", [])


def high_res_scroll(arguments: argparse.Namespace) -> dict:
    return app_command(
        arguments,
        "streamSendHighResScroll",
        [f"vertical={arguments.vertical}", f"horizontal={arguments.horizontal}"],
    )


def pin_host(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamPinHost", [f"host={arguments.host}", f"port={arguments.port}"])


def stop_discovery(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamStopDiscovery", [])


def start_discovery(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamStartDiscovery", [])


def discovered(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamDiscoveredHosts", [])


def quality(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamInjectQuality", [f"value={arguments.value}"])


def reconnect(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamReconnect", [])


def wake(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamWakeHost", [f"host={arguments.host}"])


def read_settings(arguments: argparse.Namespace) -> dict:
    return app_command(arguments, "streamReadSettings", [])


def write_settings(arguments: argparse.Namespace) -> dict:
    pairs = [
        f"audioLayout={arguments.audio_layout}",
        f"statsOverlay={arguments.stats_overlay}",
        f"absoluteTouchMode={arguments.absolute_touch_mode}",
    ]
    return app_command(arguments, "streamSetSettings", pairs)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--device", required=True)
    parser.add_argument("--execution-input", default=None)
    parser.add_argument("--evidence-dir", default=".scratch/stream-injection")
    subparsers = parser.add_subparsers(dest="command", required=True)

    profile = subparsers.add_parser("profile", help="inject a controller arrival")
    profile.add_argument("--kind", default="xbox")
    profile.add_argument(
        "--caps",
        default="all",
        help="capability names joined by commas, or the raw field as 0x…",
    )
    profile.add_argument("--buttons", default="", help="button names or the raw bit field")
    profile.add_argument("--number", default="0")
    profile.add_argument("--mask", default="1")
    profile.set_defaults(handler=inject_profile)

    remove = subparsers.add_parser("profile-remove", help="inject a controller removal")
    remove.set_defaults(handler=remove_profile)

    feedback = subparsers.add_parser("feedback", help="inject one host feedback event")
    feedback.add_argument("--type", required=True, choices=["rumble", "trigger", "motion", "light"])
    feedback.add_argument(
        "--arg",
        action="append",
        default=[],
        help="feedback argument as key=value; repeats",
    )
    feedback.set_defaults(handler=inject_feedback)

    touchpad = subparsers.add_parser("touchpad", help="inject a touchpad coordinate")
    touchpad.add_argument("--x", required=True)
    touchpad.add_argument("--y", required=True)
    touchpad.add_argument("--index", default="0")
    touchpad.set_defaults(handler=inject_touchpad)

    motion = subparsers.add_parser("motion", help="turn the simulated motion source on or off")
    motion.add_argument("--enable", default="true")
    motion.set_defaults(handler=inject_motion)

    battery = subparsers.add_parser("battery", help="inject one battery reading")
    battery.add_argument("--state", required=True)
    battery.add_argument("--percentage", required=True)
    battery.set_defaults(handler=inject_battery)

    scroll = subparsers.add_parser("highres-scroll", help="send one high resolution scroll packet")
    scroll.add_argument("--vertical", default="0")
    scroll.add_argument("--horizontal", default="0")
    scroll.set_defaults(handler=high_res_scroll)

    pin_parser = subparsers.add_parser("pin-host", help="pin the stored host to one address")
    pin_parser.add_argument("--host", required=True)
    pin_parser.add_argument("--port", type=int, default=47989)
    pin_parser.set_defaults(handler=pin_host)

    stop_discovery_parser = subparsers.add_parser("stop-discovery", help="stop host discovery")
    stop_discovery_parser.set_defaults(handler=stop_discovery)

    start_discovery_parser = subparsers.add_parser("start-discovery", help="start host discovery")
    start_discovery_parser.set_defaults(handler=start_discovery)

    discovered_parser = subparsers.add_parser("discovered", help="list discovered hosts")
    discovered_parser.set_defaults(handler=discovered)

    quality_parser = subparsers.add_parser("quality", help="inject a connection quality status")
    quality_parser.add_argument("--value", required=True)
    quality_parser.set_defaults(handler=quality)

    reconnect_parser = subparsers.add_parser("reconnect", help="reconnect the current session")
    reconnect_parser.set_defaults(handler=reconnect)

    wake_parser = subparsers.add_parser("wake", help="send a wake packet to a host")
    wake_parser.add_argument("--host", required=True)
    wake_parser.set_defaults(handler=wake)

    read = subparsers.add_parser("settings", help="read the streaming settings")
    read.set_defaults(handler=read_settings)

    write = subparsers.add_parser("set-settings", help="write streaming settings")
    write.add_argument("--audio-layout", default="")
    write.add_argument("--stats-overlay", default="")
    write.add_argument("--absolute-touch-mode", default="")
    write.set_defaults(handler=write_settings)

    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    response = arguments.handler(arguments)
    print(json.dumps(response, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if response.get("success") is True else 1


if __name__ == "__main__":
    sys.exit(main())
