#!/usr/bin/env python3

"""The one path from the coordinator to an Orca Run.

Waiting is a typed object here, not a shell habit. `watch open` refuses a
channel that does not push: a file appearing, a process still listed, a
terminal's tail. Those three carried no completion fact in the recorded
session -- a reaper killed a worker that had delivered one packet of four, and
a file count read 23/28 while every deliverable was already on disk -- and each
of them is what the coordinator reached for after the real channel had been
made unreadable by some other bypass.

`drain` is the queue's only consumer, because acknowledging is what removes a
message: two readers meant whichever ran first consumed the batch while the
other saw an empty queue. Each delivery's --ack is chained into the next check
rather than issued on its own, which is the difference between consuming a
batch and naming one that was never read.

`sweep` is drain plus retirement. It exists as one verb because the gate makes
a second round of dispatching wait for it, so reading the mailbox happens as a
side effect of dispatching again rather than as a thing to remember.

Subcommands:
    drain --run <id>            read and acknowledge every message
    sweep --run <id>            drain, then close every settled worker's terminal
    watch open --run <id>       start a wait bound to that Run
    watch open --task <bash id> declare a wait on a background task's push
    watch read [--id <watch>]   sample every open watch and record what it saw
    watch close --id <watch>    end a wait
    status                      watches, unswept dispatches, gate and watchdog
    watchdog                    the out-of-band re-wake loop; see wake_reason()
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

import coordinator_state as ledger

SETTLED = {"completed", "failed"}
WATCHDOG_INTERVAL = 60
WATCHDOG_IDLE_SAMPLES = 3


def _shell(args: tuple[str, ...]) -> str:
    return subprocess.run(
        ["orca", *args, "--json"], capture_output=True, text=True
    ).stdout


runner = _shell
"""Indirection so the probes drive every branch without an Orca runtime."""


def orca(*args: str) -> dict:
    out = runner(args)
    decoder, index = json.JSONDecoder(), 0
    while index < len(out):
        while index < len(out) and out[index] in " \t\r\n":
            index += 1
        if index >= len(out):
            break
        try:
            value, index = decoder.raw_decode(out, index)
        except json.JSONDecodeError:
            break
        if isinstance(value, dict) and "result" in value:
            return value["result"]
    return {}


def drain(run: str, archive: Path) -> list[dict]:
    """Print every message, keep it, and acknowledge the batch that carried it."""
    kept: list[dict] = []
    acknowledge: list[str] = []
    while True:
        batch = orca("orchestration", "check", "--run", run, *acknowledge)
        messages = batch.get("messages") or []
        delivery = batch.get("deliveryId")
        if not messages or not delivery:
            break
        acknowledge = ["--ack", str(delivery)]
        for message in messages:
            kind = message.get("type")
            if kind == "heartbeat":
                continue
            kept.append(message)
            print(f"  {kind}: {message.get('subject')}", flush=True)
            if kind != "worker_done":
                print("      " + str(message.get("body") or "")[:600], flush=True)
    if kept:
        archive.parent.mkdir(parents=True, exist_ok=True)
        existing = []
        if archive.is_file():
            try:
                existing = json.loads(archive.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                existing = []
        archive.write_text(
            json.dumps(existing + kept, ensure_ascii=False, indent=1), encoding="utf-8"
        )
    return kept


def open_questions(messages: list[dict]) -> set[str]:
    """Ids that asked something and have not been answered.

    An agent can ask and then settle, and closing its terminal is what makes the
    question unanswerable. A settled worker with an open question is left alone.
    """
    waiting: set[str] = set()
    for message in messages:
        if message.get("type") in {"worker_done", "heartbeat"}:
            continue
        payload = message.get("payload")
        if isinstance(payload, str):
            try:
                payload = json.loads(payload)
            except json.JSONDecodeError:
                payload = {}
        for key in ("dispatchId", "taskId"):
            value = (payload or {}).get(key) or message.get(key)
            if value:
                waiting.add(str(value))
    return waiting


def workers(run: str) -> list[dict]:
    listing = orca("orchestration", "worker-list", "--run", run).get("workers")
    return [worker for worker in (listing or []) if isinstance(worker, dict)]


def sample(run: str) -> dict:
    """What the Run looks like right now, plus a digest that stall detection reads.

    The digest covers dispatch status and heartbeat, which is what changes while
    a worker is alive. A heartbeat is a proxy for liveness, not for output, so
    the digest is compared across samples rather than trusted on its own.
    """
    found = workers(run)
    rows = sorted(
        (
            str(worker.get("dispatchId") or worker.get("taskId") or ""),
            str(worker.get("dispatchStatus") or ""),
            str(worker.get("lastHeartbeatAt") or ""),
        )
        for worker in found
    )
    digest = hashlib.sha256(
        json.dumps(rows, ensure_ascii=False).encode("utf-8")
    ).hexdigest()[:16]
    settled = sum(1 for _, status, _ in rows if status in SETTLED)
    return {"total": len(rows), "settled": settled, "digest": digest, "rows": rows}


def retire(run: str, output: Path, waiting: set[str]) -> int:
    closed = 0
    for worker in workers(run):
        if worker.get("dispatchStatus") not in SETTLED:
            continue
        if {worker.get("dispatchId"), worker.get("taskId")} & waiting:
            print(f"  keeping {worker.get('dispatchId')}: question unanswered", flush=True)
            continue
        handle = worker.get("agentTerminalHandle")
        if not handle:
            continue
        read = orca("orchestration", "worker-read", "--dispatch", str(worker["dispatchId"]))
        if read:
            output.parent.mkdir(parents=True, exist_ok=True)
            with output.open("a", encoding="utf-8") as sink:
                sink.write(
                    json.dumps(
                        {"dispatch": worker["dispatchId"], "read": read},
                        ensure_ascii=False,
                    )
                    + "\n"
                )
        result = orca("terminal", "close", "--terminal", str(handle))
        if ((result.get("close") or {}).get("ptyKilled")) is True:
            closed += 1
    return closed


def watchdog_pid_path(project: Path) -> Path:
    return project / ".claude/state/watchdog.pid"


def watchdog_alive(project: Path) -> int | None:
    try:
        pid = int(watchdog_pid_path(project).read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None
    try:
        os.kill(pid, 0)
    except OSError:
        return None
    return pid


spawner = subprocess.Popen
"""Indirection so the probes can watch the spawn without starting a process."""


def ensure_watchdog(project: Path, wake_command: str | None) -> str:
    """Put the re-wake outside the model loop.

    A turn the API refuses never runs, so no Stop hook fires and no wakeup is
    armed; one such refusal cost thirty-nine minutes of silence. Nothing inside
    the turn lifecycle can cover that, so the recovery has to be a process that
    is not a turn. This is the single sanctioned detached process in the
    harness, and it exists to restore the push the banned detachers destroy.
    """
    if watchdog_alive(project) is not None:
        return "already running"
    if not wake_command:
        return "not started: no --wake-command"
    log = project / ".claude/state/watchdog.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    handle = log.open("a", encoding="utf-8")
    process = spawner(
        [sys.executable, str(Path(__file__).resolve()), "watchdog",
         "--project", str(project), "--wake-command", wake_command],
        stdout=handle,
        stderr=handle,
        start_new_session=True,
        cwd=str(project),
    )
    watchdog_pid_path(project).write_text(str(process.pid), encoding="utf-8")
    return f"started pid {process.pid}"


def wake_reason(project: Path) -> str | None:
    """Why an out-of-band wake is owed.

    The channel says the work is finished and the ledger shows the coordinator
    has not looked since it finished. Duration is not part of this: the number
    of samples the Run has stood still is, because a round's length is driven by
    its operation units and is not knowable in advance.
    """
    payload = ledger.load(project)
    for identifier, watch in ledger.open_watches(payload).items():
        if watch.get("channel", {}).get("kind") != "orca-run":
            continue
        run = watch["channel"].get("run")
        if not run:
            continue
        now = sample(str(run))
        seen = ledger.latest_observation(watch) or {}
        if now["total"] and now["settled"] == now["total"]:
            if seen.get("settled") != now["settled"] or seen.get("digest") != now["digest"]:
                return f"{identifier}: {now['settled']}/{now['total']} dispatches settled"
    return None


def watchdog(project: Path, wake_command: str, once: bool = False) -> int:
    idle = 0
    while True:
        reason = wake_reason(project)
        if reason is not None:
            payload = ledger.load(project)
            payload.setdefault("wakes", []).append({"at": time.time(), "reason": reason})
            ledger.save(project, payload)
            subprocess.run(wake_command, shell=True, capture_output=True, text=True)
            print(f"woke: {reason}", flush=True)
            idle = 0
        else:
            idle += 1
        if once or not ledger.open_watches(ledger.load(project)):
            return 0
        if idle > WATCHDOG_IDLE_SAMPLES * 60:
            return 0
        time.sleep(WATCHDOG_INTERVAL)


def command_drain(arguments) -> int:
    project = Path(arguments.project)
    kept = drain(arguments.run, project / arguments.archive)
    print(f"messages drained: {len(kept)}")
    waiting = open_questions(kept)
    if waiting:
        print(f"NEEDS AN ANSWER: {len(waiting)} worker(s): {sorted(waiting)}")
    payload = ledger.load(project)
    payload.setdefault("sweeps", []).append(
        {"turn": payload.get("turn", 0), "kind": "drain", "messages": len(kept)}
    )
    payload["dispatches"] = []
    ledger.save(project, payload)
    return 0


def command_sweep(arguments) -> int:
    project = Path(arguments.project)
    kept = drain(arguments.run, project / arguments.archive)
    print(f"messages drained: {len(kept)}")
    waiting = open_questions(kept)
    if waiting:
        print(f"NEEDS AN ANSWER: {len(waiting)} worker(s): {sorted(waiting)}")
    closed = retire(arguments.run, project / arguments.output, waiting)
    print(f"terminals closed: {closed}")
    payload = ledger.load(project)
    payload.setdefault("sweeps", []).append(
        {"turn": payload.get("turn", 0), "kind": "sweep", "closed": closed}
    )
    payload["dispatches"] = []
    ledger.save(project, payload)
    return 0


def command_watch_open(arguments) -> int:
    project = Path(arguments.project)
    payload = ledger.load(project)
    turn = int(payload.get("turn") or 0)
    if arguments.run:
        channel = {"kind": "orca-run", "run": arguments.run}
        observation = sample(arguments.run)
    elif arguments.task:
        channel = {"kind": "background-task", "task": arguments.task}
        observation = {"total": 1, "settled": 0, "digest": arguments.task}
    else:
        print(
            "A watch names the channel that carries the completion fact. "
            "--run binds to a Run's dispatch status and its worker_done push; "
            "--task binds to a background command's task-notification. A path, "
            "a glob, a process or a terminal tail is not a channel: a file "
            "count read 23 of 28 while every deliverable was on disk, and a "
            "reaper killed a worker that had delivered one packet of four.",
            file=sys.stderr,
        )
        return 2
    identifier = "watch_" + hashlib.sha256(
        json.dumps(channel, sort_keys=True).encode("utf-8")
    ).hexdigest()[:8]
    watch = payload.setdefault("watches", {}).setdefault(
        identifier, {"channel": channel, "openedTurn": turn, "observations": []}
    )
    watch["closedTurn"] = None
    watch["observations"].append({"turn": turn, **observation})
    ledger.save(project, payload)
    print(f"{identifier} open on {channel}")
    print(f"watchdog: {ensure_watchdog(project, arguments.wake_command)}")
    return 0


def command_watch_read(arguments) -> int:
    project = Path(arguments.project)
    payload = ledger.load(project)
    turn = int(payload.get("turn") or 0)
    watching = ledger.open_watches(payload)
    if arguments.id:
        watching = {key: value for key, value in watching.items() if key == arguments.id}
    if not watching:
        print("no open watch")
        return 0
    for identifier, watch in watching.items():
        channel = watch.get("channel") or {}
        if channel.get("kind") == "orca-run":
            observation = sample(str(channel.get("run")))
            watch["observations"].append({"turn": turn, **observation})
            verdict = "live"
            if observation["total"] and observation["settled"] == observation["total"]:
                verdict = "settled"
            elif ledger.is_stalled(watch):
                verdict = "stalled"
            print(
                f"{identifier} {verdict}: {observation['settled']}/{observation['total']} "
                f"settled, digest {observation['digest']}"
            )
            if verdict == "stalled":
                print(
                    f"  {ledger.STALE_OBSERVATIONS} samples with no change in any "
                    "dispatch status or heartbeat. Retire and relaunch the ones "
                    "that produced nothing; a sample count is the criterion here "
                    "because a round's length is not knowable in advance."
                )
        else:
            watch["observations"].append(
                {"turn": turn, "total": 1, "settled": 0, "digest": channel.get("task")}
            )
            print(
                f"{identifier} bound to background task {channel.get('task')}: "
                "completion arrives as a task-notification, so there is nothing "
                "to poll. Close the watch when the notification lands."
            )
    ledger.save(project, payload)
    return 0


def command_watch_close(arguments) -> int:
    project = Path(arguments.project)
    payload = ledger.load(project)
    watch = (payload.get("watches") or {}).get(arguments.id)
    if not isinstance(watch, dict):
        print(f"no such watch: {arguments.id}", file=sys.stderr)
        return 2
    watch["closedTurn"] = int(payload.get("turn") or 0)
    ledger.save(project, payload)
    print(f"{arguments.id} closed")
    return 0


def command_status(arguments) -> int:
    project = Path(arguments.project)
    payload = ledger.load(project)
    turn = int(payload.get("turn") or 0)
    print(f"session {payload.get('session')} turn {turn}")
    off = project / ".claude/hooks-off"
    print(f"gate: {'OFF (.claude/hooks-off present)' if off.exists() else 'on'}")
    pid = watchdog_alive(project)
    print(f"watchdog: {'pid ' + str(pid) if pid else 'not running'}")
    stale = ledger.unswept_dispatches(payload, turn)
    print(f"unswept dispatches from earlier turns: {len(stale)}")
    for identifier, watch in ledger.open_watches(payload).items():
        observation = ledger.latest_observation(watch) or {}
        print(
            f"open {identifier} {watch.get('channel')} last seen turn "
            f"{observation.get('turn')} {observation.get('settled')}/"
            f"{observation.get('total')} read_this_turn="
            f"{ledger.read_this_turn(watch, turn)} stalled={ledger.is_stalled(watch)}"
        )
    for wake in payload.get("wakes") or []:
        print(f"out-of-band wake: {wake.get('reason')}")
    return 0


def command_watchdog(arguments) -> int:
    return watchdog(Path(arguments.project), arguments.wake_command, arguments.once)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument("--archive", default=".claude/state/messages.json")
    parser.add_argument("--output", default=".claude/state/worker-output.jsonl")
    sub = parser.add_subparsers(dest="command", required=True)

    for name, handler in (("drain", command_drain), ("sweep", command_sweep)):
        child = sub.add_parser(name)
        child.add_argument("--run", required=True)
        child.set_defaults(handler=handler)

    watch = sub.add_parser("watch")
    kinds = watch.add_subparsers(dest="watch_command", required=True)
    opener = kinds.add_parser("open")
    opener.add_argument("--run")
    opener.add_argument("--task")
    opener.add_argument("--wake-command")
    opener.set_defaults(handler=command_watch_open)
    reader = kinds.add_parser("read")
    reader.add_argument("--id")
    reader.set_defaults(handler=command_watch_read)
    closer = kinds.add_parser("close")
    closer.add_argument("--id", required=True)
    closer.set_defaults(handler=command_watch_close)

    sub.add_parser("status").set_defaults(handler=command_status)

    dog = sub.add_parser("watchdog")
    dog.add_argument("--wake-command", required=True)
    dog.add_argument("--once", action="store_true")
    dog.set_defaults(handler=command_watchdog)
    return parser


def main(argv: list[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    return arguments.handler(arguments)


if __name__ == "__main__":
    raise SystemExit(main())
