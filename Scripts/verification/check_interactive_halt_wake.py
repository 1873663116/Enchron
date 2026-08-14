#!/usr/bin/env python3

"""Asserts that a halt delivers its stop by the same mechanism a tap uses, and
that a delivery which fails is raised rather than discarded.

The runner sits parked on a Darwin notification between commands. A command file
that lands with no notification behind it is read only if the runner happens to
loop again for another reason, so a stop delivered without one is a race. Halt
used to run `devicectl device process signal --device X --signal SIGCONT`, which
that tool rejects for want of `--pid`, and passed `quiet=True`, which threw the
rejection away. The stop went undelivered, the test never returned, halt killed
xcodebuild, the result bundle was never sealed, and XCTest therefore never wrote
the screen recording it only writes on a clean exit. Two defects: a command that
could not work, and a discarded return code that hid it for five days.

Four checks, because either defect alone reproduces the outage:

  delivery   `halt_session` runs against a devicectl emulator and must post the
             command notification, issuing nothing that tool rejects.
  reporting  a wake whose devicectl invocation fails must raise.
  structure  one wake path, reached by both `halt_session` and `send_command`,
             and no process signal anywhere in the module.
  channel    the name the controller posts is the name the runner parks on, which
             is written out on both sides and would fail the same silent way.

The emulator learns which options each devicectl verb requires by reading that
tool's own `--help`, which prints usage and exits without contacting a device.
The emulator's fidelity is what makes this check mean anything, so it is
calibrated against the tool rather than against a memory of it.
"""

from __future__ import annotations

import argparse
import ast
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import types

sys.path.insert(0, str(Path(__file__).parent))

from enchron_artifact_paths import scratch_directory

CONTROLLER = Path(__file__).parent / "interactive_visionpro_ui.py"
RUNNER = (
    Path(__file__).resolve().parents[2]
    / "Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift"
)

# What `devicectl <verb> --help` reported when this check was written, used only
# when devicectl is not installed. Required options are the ones its usage line
# prints outside brackets.
RECORDED_REQUIRED_OPTIONS = {
    "device process signal": ["--device", "--pid", "--signal"],
    "device notification post": ["--device", "--name"],
    "device copy from": ["--device", "--source", "--domain-type"],
    "device copy to": ["--device", "--source", "--destination", "--domain-type"],
}

VERBS = tuple(RECORDED_REQUIRED_OPTIONS)

STUB_SOURCE = '''#!/usr/bin/env python3
"""Stands in for `xcrun devicectl` so a halt can be driven with no device.

Models the one behaviour that matters: the runner is parked, and reads its
command file only when a Darwin notification wakes it. A stop delivered without
one is never seen, which is exactly what the outage looked like.
"""

import json
import os
from pathlib import Path
import shutil
import sys

state = Path(os.environ["ENCHRON_DEVICECTL_STATE"])
container = state / "container"
contract = json.loads((state / "contract.json").read_text())
fail_verbs = json.loads(os.environ.get("ENCHRON_DEVICECTL_FAIL", "[]"))
COMMAND_NOTIFICATION = "com.enchron.interactive-device-ui.command"


def option(argv, name):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None


def record(argv, code, message):
    with (state / "calls.jsonl").open("a") as log:
        log.write(json.dumps({"argv": argv, "returncode": code, "message": message}) + "\\n")
    if message:
        print(message, file=sys.stderr)
    sys.exit(code)


argv = sys.argv[1:]
if not argv or argv[0] != "devicectl":
    sys.exit(0)
argv = argv[1:]
verb = next((name for name in contract if argv[: len(name.split())] == name.split()), None)
if verb is None:
    record(argv, 0, "")

for required in contract[verb]:
    if required not in argv:
        record(argv, 64, "Error: Missing expected argument '%s <value>'" % required)

if verb in fail_verbs:
    record(argv, 1, "Error: the emulator was asked to fail %s." % verb)

if verb == "device copy from":
    source = container / option(argv, "--source")
    destination = Path(option(argv, "--destination"))
    if not source.is_file():
        record(argv, 1, "Error: no such file on device.")
    shutil.copy(source, destination)
    record(argv, 0, "")

if verb == "device copy to":
    destination = container / option(argv, "--destination")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(Path(option(argv, "--source")), destination)
    record(argv, 0, "")

if verb == "device notification post":
    if option(argv, "--name") == COMMAND_NOTIFICATION:
        command_path = container / "Documents/EnchronInteractiveUI/command.json"
        if command_path.is_file():
            command = json.loads(command_path.read_text())
            responses = container / "Documents/EnchronInteractiveUI/responses"
            responses.mkdir(parents=True, exist_ok=True)
            (responses / ("%s.json" % command["id"])).write_text(
                json.dumps({"id": command["id"], "ok": True})
            )
    record(argv, 0, "")

record(argv, 0, "")
'''


def required_options(verb: str) -> tuple[list[str], str]:
    """Reads the required options out of devicectl's own usage line. Options it
    prints in brackets are optional; the rest are not."""
    devicectl = shutil.which("xcrun")
    if devicectl is None:
        return RECORDED_REQUIRED_OPTIONS[verb], "recorded"
    completed = subprocess.run(
        ["xcrun", "devicectl", *verb.split(), "--help"],
        check=False,
        text=True,
        capture_output=True,
    )
    match = re.search(r"^USAGE: (.*)$", completed.stdout, re.MULTILINE)
    if completed.returncode != 0 or match is None:
        return RECORDED_REQUIRED_OPTIONS[verb], "recorded"
    usage = re.sub(r"\[[^\]]*\]", " ", match.group(1))
    return re.findall(r"--[a-z-]+", usage), "devicectl --help"


def build_emulator(name: str) -> tuple[Path, Path]:
    """Returns the directory to put on PATH and the emulator's state directory."""
    scratch = scratch_directory(f"interactive-halt-wake/{name}")
    for stale in ("calls.jsonl",):
        (scratch / stale).unlink(missing_ok=True)
    if (scratch / "container").is_dir():
        shutil.rmtree(scratch / "container")
    contract = {}
    sources = set()
    for verb in VERBS:
        options, source = required_options(verb)
        contract[verb] = options
        sources.add(source)
    (scratch / "contract.json").write_text(json.dumps(contract, indent=2), encoding="utf-8")
    channel = scratch / "container/Documents/EnchronInteractiveUI"
    channel.mkdir(parents=True, exist_ok=True)
    (channel / "ready.json").write_text(
        json.dumps({"sessionID": "emulated-session"}), encoding="utf-8"
    )
    binaries = scratch / "bin"
    binaries.mkdir(exist_ok=True)
    stub = binaries / "xcrun"
    stub.write_text(STUB_SOURCE, encoding="utf-8")
    stub.chmod(0o755)
    print(
        f"  devicectl required options read from {', '.join(sorted(sources))}: "
        f"{contract['device process signal']} for a process signal"
    )
    return binaries, scratch


def calls(state: Path) -> list[dict[str, object]]:
    log = state / "calls.jsonl"
    if not log.is_file():
        return []
    return [json.loads(line) for line in log.read_text().splitlines() if line.strip()]


def load_controller(path: Path) -> types.ModuleType:
    specification = importlib.util.spec_from_file_location(f"controller_{id(path)}", path)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


class UnkillableOS:
    """Everything the controller asks of `os`, except the one call that would end
    a process. This check runs beside real builds that match the same scope
    markers halt kills by, so a signal that escapes containment must raise rather
    than land."""

    def __getattr__(self, name: str) -> object:
        return getattr(os, name)

    def kill(self, pid: int, number: int) -> None:
        raise AssertionError(
            f"halt tried to signal pid {pid}; this check must never reach a process table."
        )


def check_delivery(controller: Path, failures: list[str]) -> None:
    print("\ndelivery: halt posts the notification the runner is parked on")
    binaries, state = build_emulator("delivery")
    module = load_controller(controller)
    if not hasattr(module, "halt_session") or not hasattr(module, "scoped_processes"):
        failures.append("the controller has no halt_session and scoped_processes to drive")
        return
    # Containment before anything runs. A device agent's xcodebuild matches the
    # same scope markers this controller kills by, so the process table is put out
    # of reach twice: nothing to find, and a signal that raises instead of landing.
    module.scoped_processes = lambda: []
    module.os = UnkillableOS()
    module.GRACEFUL_STOP_DEADLINE_SECONDS = 2.0
    module.RESULT_BUNDLE_WRITE_DEADLINE_SECONDS = 2.0
    module.TERMINATION_DEADLINE_SECONDS = 0.2
    assert module.scoped_processes() == []

    environment = dict(os.environ)
    environment["PATH"] = f"{binaries}:{environment.get('PATH', '')}"
    environment["ENCHRON_DEVICECTL_STATE"] = str(state)
    # The controller stages its command files through the temporary directory, and
    # those belong on the artifact volume like everything else it writes.
    environment["TMPDIR"] = str(state)
    arguments = argparse.Namespace(
        device="emulated-device", runner_bundle_id="com.example.runner"
    )
    with replaced_environment(environment):
        result = module.halt_session(arguments)
    print(f"  halt returned gracefulStop={result['gracefulStop']!r}")

    recorded = calls(state)
    wakes = [
        call
        for call in recorded
        if call["argv"][:3] == ["device", "notification", "post"]
        and module.COMMAND_NOTIFICATION in call["argv"]
    ]
    signals = [call for call in recorded if call["argv"][:3] == ["device", "process", "signal"]]
    # A poll for a response that has not arrived exits 1 and the caller reads that,
    # so a non-zero exit is not by itself a defect. A usage error is: it means the
    # controller issued a command the tool cannot accept, which no amount of
    # retrying will change and which only a discarded return code can hide.
    malformed = sorted(
        {
            f"{' '.join(call['argv'][:3])} exited {call['returncode']}: {call['message'].strip()}"
            for call in recorded
            if call["returncode"] == 64
        }
    )

    for name, ok, detail in (
        (
            "halt posted the command notification",
            len(wakes) == 1,
            f"{len(wakes)} notification posts carrying {module.COMMAND_NOTIFICATION}",
        ),
        (
            "halt sent no process signal",
            not signals,
            "; ".join(
                f"{' '.join(call['argv'])} exited {call['returncode']}: {call['message'].strip()}"
                for call in signals
            )
            or "none",
        ),
        (
            "halt issued no command devicectl rejects as malformed",
            not malformed,
            "; ".join(malformed) or "none",
        ),
        (
            "the stop was acknowledged, so it reached a runner that was asleep",
            result["gracefulStop"] == "acknowledged",
            str(result["gracefulStop"]),
        ),
    ):
        print(f"  {'ok  ' if ok else 'FAIL'} {name}: {detail}")
        if not ok:
            failures.append(f"{name} — {detail}")


def check_reporting(controller: Path, failures: list[str]) -> None:
    print("\nreporting: a wake that devicectl rejects is raised, not discarded")
    binaries, state = build_emulator("reporting")
    module = load_controller(controller)
    wake = getattr(module, "wake_runner", None)
    if wake is None:
        failures.append(
            "the controller has no wake_runner; halt and send_command deliver a command "
            "by separate mechanisms, which is the arrangement that let one of them rot"
        )
        print("  FAIL there is no single wake path to test")
        return
    environment = dict(os.environ)
    environment["PATH"] = f"{binaries}:{environment.get('PATH', '')}"
    environment["ENCHRON_DEVICECTL_STATE"] = str(state)
    # The controller stages its command files through the temporary directory, and
    # those belong on the artifact volume like everything else it writes.
    environment["TMPDIR"] = str(state)
    environment["ENCHRON_DEVICECTL_FAIL"] = json.dumps(["device notification post"])
    arguments = argparse.Namespace(
        device="emulated-device", runner_bundle_id="com.example.runner"
    )
    raised = None
    with replaced_environment(environment):
        try:
            wake(arguments)
        except Exception as error:  # noqa: BLE001 - any propagation is the point
            raised = error
    ok = raised is not None
    print(f"  {'ok  ' if ok else 'FAIL'} a rejected wake raised: {raised!r}")
    if not ok:
        failures.append(
            "wake_runner returned normally after devicectl rejected the notification post"
        )


def devicectl_constants(node: ast.AST) -> set[str]:
    found: set[str] = set()
    for descendant in ast.walk(node):
        if not isinstance(descendant, ast.Call):
            continue
        if not isinstance(descendant.func, ast.Name) or descendant.func.id != "run_devicectl":
            continue
        for literal in ast.walk(descendant):
            if isinstance(literal, ast.Constant) and isinstance(literal.value, str):
                found.add(literal.value)
    return found


def called_names(node: ast.AST) -> set[str]:
    return {
        descendant.func.id
        for descendant in ast.walk(node)
        if isinstance(descendant, ast.Call) and isinstance(descendant.func, ast.Name)
    }


def check_structure(controller: Path, failures: list[str]) -> None:
    print("\nstructure: one wake path, reached by every caller that needs one")
    tree = ast.parse(controller.read_text(encoding="utf-8"))
    functions = {
        node.name: node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)
    }
    wake_paths = sorted(
        name
        for name, node in functions.items()
        if {"notification", "post"} <= devicectl_constants(node)
    )
    signal_paths = sorted(
        name
        for name, node in functions.items()
        if {"process", "signal"} <= devicectl_constants(node)
    )

    ok = not signal_paths
    print(
        f"  {'ok  ' if ok else 'FAIL'} no devicectl process signal: "
        f"{signal_paths or 'none'}"
    )
    if not ok:
        failures.append(
            f"{', '.join(signal_paths)} still runs a devicectl process signal, which that "
            "tool rejects without --pid"
        )

    ok = len(wake_paths) == 1
    print(f"  {'ok  ' if ok else 'FAIL'} exactly one function posts the notification: {wake_paths}")
    if not ok:
        failures.append(f"the notification is posted from {len(wake_paths)} places: {wake_paths}")

    if len(wake_paths) == 1:
        wake = wake_paths[0]
        for caller in ("halt_session", "send_command"):
            if caller == wake:
                # The delivery lives inside one command's own body, so no other
                # command can reach it without duplicating it.
                print(f"  FAIL the only wake path is {wake} itself, so nothing else shares it")
                failures.append(
                    f"the notification is posted inside {wake}, which leaves every other "
                    "command to deliver its own way"
                )
                continue
            node = functions.get(caller)
            reaches = node is not None and wake in called_names(node)
            print(f"  {'ok  ' if reaches else 'FAIL'} {caller} delivers through {wake}: {reaches}")
            if not reaches:
                failures.append(
                    f"{caller} does not call {wake}, so it delivers a command by some other "
                    "means than the one every other command uses"
                )
        body = functions[wake]
        raises = any(isinstance(node, ast.Raise) for node in ast.walk(body))
        reads = "returncode" in {
            node.attr for node in ast.walk(body) if isinstance(node, ast.Attribute)
        }
        ok = raises and reads
        print(f"  {'ok  ' if ok else 'FAIL'} {wake} reads the return code and raises: {ok}")
        if not ok:
            failures.append(f"{wake} does not turn a failed devicectl invocation into a raise")


def check_notification_name(controller: Path, runner: Path, failures: list[str]) -> None:
    """The name is written out on both sides of the channel. A rename on either
    reproduces the original outage exactly: a well formed post that no runner is
    listening for, and a stop that is therefore never read."""
    print("\nchannel: the name posted is the name the runner parks on")
    if not runner.is_file():
        print(f"  FAIL the runner is not where this check expects it: {runner}")
        failures.append(f"the interactive runner source is missing: {runner}")
        return
    posted = re.findall(
        r'COMMAND_NOTIFICATION\s*=\s*"([^"]+)"', controller.read_text(encoding="utf-8")
    )
    observed = re.findall(
        r'commandNotification\s*=\s*\n?\s*"([^"]+)"', runner.read_text(encoding="utf-8")
    )
    ok = len(posted) == 1 and posted == observed
    print(
        f"  {'ok  ' if ok else 'FAIL'} controller posts {posted}, runner parks on {observed}"
    )
    if not ok:
        failures.append(
            f"the controller posts {posted} and the runner parks on {observed}; a stop "
            "posted under a name nothing is listening for is never delivered"
        )


class replaced_environment:
    """The controller resolves devicectl through PATH, so the emulator is installed
    by replacing the environment for the duration of the call and restoring it
    afterwards."""

    def __init__(self, environment: dict[str, str]) -> None:
        self.environment = environment
        self.saved: dict[str, str] = {}

    def __enter__(self) -> None:
        self.saved = dict(os.environ)
        os.environ.clear()
        os.environ.update(self.environment)

    def __exit__(self, *_: object) -> None:
        os.environ.clear()
        os.environ.update(self.saved)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--controller",
        type=Path,
        default=CONTROLLER,
        help="The interactive UI controller to check. Point this at an older copy to "
        "confirm the check still fails on the state it was written for.",
    )
    parser.add_argument("--runner", type=Path, default=RUNNER)
    arguments = parser.parse_args()
    controller = arguments.controller.resolve()
    if not controller.is_file():
        raise SystemExit(f"no controller to check at {controller}")
    print(f"checking {controller}")

    failures: list[str] = []
    check_delivery(controller, failures)
    check_reporting(controller, failures)
    check_structure(controller, failures)
    check_notification_name(controller, arguments.runner.resolve(), failures)

    print()
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
