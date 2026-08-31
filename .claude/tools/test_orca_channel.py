#!/usr/bin/env python3

"""Probes for the sanctioned Orca path.

A fake Orca answers every call, so each branch runs without a runtime and the
sequence of calls is inspectable. The sequence is what matters: whether the
acknowledgement was chained into the next check is not visible in the messages,
only in the argument list of the call that carried it.

Run against a mutated copy by setting ENCHRON_CLAUDE_DIR.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile

CLAUDE = Path(os.environ.get("ENCHRON_CLAUDE_DIR") or Path(__file__).resolve().parents[1])
sys.path.insert(0, str(CLAUDE / "tools"))

import coordinator_state as ledger
import orca_channel as channel


class FakeOrca:
    def __init__(self, batches=None, workers=None):
        self.batches = list(batches or [])
        self.workers = list(workers or [])
        self.calls: list[tuple[str, ...]] = []
        self.closed: list[str] = []
        self.reads: list[str] = []

    def __call__(self, args: tuple[str, ...]) -> str:
        self.calls.append(args)
        joined = " ".join(args)
        if "orchestration check" in joined:
            if self.batches:
                delivery, messages = self.batches.pop(0)
                return json.dumps({"result": {"deliveryId": delivery, "messages": messages}})
            return json.dumps({"result": {"deliveryId": None, "messages": []}})
        if "worker-list" in joined:
            return json.dumps({"result": {"workers": self.workers}})
        if "worker-read" in joined:
            self.reads.append(args[-1])
            return json.dumps({"result": {"output": "report"}})
        if "terminal close" in joined:
            self.closed.append(args[-1])
            return json.dumps({"result": {"close": {"ptyKilled": True}}})
        return json.dumps({"result": {}})


def message(kind="worker_done", subject="s", payload=None):
    entry = {"type": kind, "subject": subject, "body": "b"}
    if payload:
        entry["payload"] = json.dumps(payload)
    return entry


def worker(dispatch, status="completed", handle="term_x", task=None):
    return {"dispatchId": dispatch, "taskId": task or f"task_{dispatch}",
            "dispatchStatus": status, "agentTerminalHandle": handle,
            "lastHeartbeatAt": "t0"}


FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"OK   {name}")
    else:
        FAILURES.append(name)
        print(f"FAIL {name}: {detail}")


def with_project(body):
    with tempfile.TemporaryDirectory() as directory:
        project = Path(directory)
        (project / ".claude/state").mkdir(parents=True)
        body(project)


def probe_ack_is_chained(project: Path) -> None:
    fake = FakeOrca(batches=[("d1", [message()]), ("d2", [message()])])
    channel.runner = fake
    channel.drain("run_x", project / "messages.json")
    checks = [args for args in fake.calls if "check" in " ".join(args)]
    check("drain-chains-each-ack-into-the-next-check",
          len(checks) == 3
          and "--ack" not in " ".join(checks[0])
          and "--ack d1" in " ".join(checks[1])
          and "--ack d2" in " ".join(checks[2]),
          f"{checks}")
    check("drain-never-peeks",
          all("--peek" not in " ".join(args) for args in fake.calls), f"{fake.calls}")
    check("drain-always-names-the-run",
          all("--run run_x" in " ".join(args) for args in checks), f"{checks}")


def probe_questions_hold_a_terminal(project: Path) -> None:
    asked = message("question", payload={"dispatchId": "disp_a"})
    fake = FakeOrca(batches=[("d1", [asked, message()])],
                    workers=[worker("disp_a"), worker("disp_b", handle="term_b")])
    channel.runner = fake
    kept = channel.drain("run_x", project / "messages.json")
    waiting = channel.open_questions(kept)
    channel.retire("run_x", project / "out.jsonl", waiting)
    check("an-unanswered-question-keeps-its-terminal-open",
          fake.closed == ["term_b"], f"{fake.closed}")
    check("a-report-is-archived-before-the-terminal-closes",
          fake.reads == ["disp_b"] and (project / "out.jsonl").is_file(), f"{fake.reads}")


def probe_only_settled_dispatches_are_retired(project: Path) -> None:
    """A running worker's terminal is where its remaining deliveries come from.

    Retiring on presence rather than on settled status kills the pty of a worker
    that has delivered one report of four, and the rest of its output and its
    worker_done are lost with it.
    """
    fake = FakeOrca(workers=[worker("disp_live", status="dispatched", handle="term_live"),
                             worker("disp_done", status="completed", handle="term_done")])
    channel.runner = fake
    channel.retire("run_x", project / "out.jsonl", set())
    check("a-running-dispatch-keeps-its-terminal",
          fake.closed == ["term_done"], f"{fake.closed}")
    check("a-running-dispatch-is-not-read-out",
          fake.reads == ["disp_done"], f"{fake.reads}")


def probe_the_digest_tracks_what_changed(project: Path) -> None:
    """Stall detection compares digests, so a digest that ignores its input
    reports every Run as stalled after three samples."""
    channel.runner = FakeOrca(workers=[worker("disp_a", status="dispatched")])
    before = channel.sample("run_x")["digest"]
    channel.runner = FakeOrca(workers=[worker("disp_a", status="completed")])
    after_status = channel.sample("run_x")["digest"]
    moved = worker("disp_a", status="dispatched")
    moved["lastHeartbeatAt"] = "t1"
    channel.runner = FakeOrca(workers=[moved])
    after_beat = channel.sample("run_x")["digest"]
    check("a-status-change-moves-the-digest", before != after_status,
          f"{before} == {after_status}")
    check("a-heartbeat-moves-the-digest", before != after_beat,
          f"{before} == {after_beat}")
    channel.runner = FakeOrca(workers=[worker("disp_a", status="dispatched")])
    check("an-unchanged-run-holds-its-digest",
          channel.sample("run_x")["digest"] == before, "digest is not a function of the rows")


def probe_heartbeats_are_not_reports(project: Path) -> None:
    fake = FakeOrca(batches=[("d1", [message("heartbeat"), message()])])
    channel.runner = fake
    kept = channel.drain("run_x", project / "messages.json")
    check("a-heartbeat-is-not-kept-as-a-report",
          [entry["type"] for entry in kept] == ["worker_done"], f"{kept}")


def probe_channel_must_push(project: Path) -> None:
    code = channel.main(["--project", str(project), "watch", "open"])
    check("a-watch-with-no-channel-is-refused", code == 2, f"exit {code}")
    channel.runner = FakeOrca(workers=[worker("disp_a", status="dispatched")])
    channel.spawner = lambda *args, **kwargs: type("P", (), {"pid": 4242})()
    code = channel.main(["--project", str(project), "watch", "open", "--run", "run_x"])
    payload = ledger.load(project)
    check("a-run-is-a-channel", code == 0 and len(ledger.open_watches(payload)) == 1,
          f"exit {code} {payload.get('watches')}")
    observation = ledger.latest_observation(list(ledger.open_watches(payload).values())[0])
    check("opening-a-watch-samples-it-at-once",
          observation and observation.get("total") == 1, f"{observation}")


def probe_stall_is_counted_in_samples(project: Path) -> None:
    """Sizes are literal here on purpose.

    The first version of this probe built its observation lists with
    range(STALE_OBSERVATIONS), so raising the constant raised the fixture with
    it and the case passed for every value. The mutation harness found it: the
    guard was inverted and nothing turned red.
    """
    def watch_with(digests, settled=0):
        return {"channel": {"kind": "orca-run", "run": "r"}, "openedTurn": 0,
                "closedTurn": None,
                "observations": [{"turn": index, "total": 8, "settled": settled,
                                  "digest": digest}
                                 for index, digest in enumerate(digests)]}

    check("three-identical-samples-mark-a-stall",
          ledger.is_stalled(watch_with(["same", "same", "same"])), "")
    check("two-identical-samples-do-not",
          not ledger.is_stalled(watch_with(["same", "same"])), "")
    check("a-moving-digest-is-not-a-stall",
          not ledger.is_stalled(watch_with(["d0", "d1", "d2"])), "")
    check("a-change-inside-the-window-is-not-a-stall",
          not ledger.is_stalled(watch_with(["same", "other", "same"])), "")
    check("finished-work-is-not-a-stall",
          not ledger.is_stalled(watch_with(["same", "same", "same"], settled=8)), "")
    check("the-threshold-is-a-sample-count-of-three",
          ledger.STALE_OBSERVATIONS == 3, f"{ledger.STALE_OBSERVATIONS}")


def probe_sweep_clears_the_dispatch_ledger(project: Path) -> None:
    payload = ledger.load(project)
    payload["turn"] = 3
    payload["dispatches"] = [{"turn": 1, "command": "worker-start"}]
    ledger.save(project, payload)
    channel.runner = FakeOrca(batches=[("d1", [message()])], workers=[worker("disp_a")])
    channel.main(["--project", str(project), "sweep", "--run", "run_x"])
    payload = ledger.load(project)
    check("a-sweep-clears-what-dispatching-recorded",
          payload["dispatches"] == [] and payload["sweeps"], f"{payload}")


def probe_out_of_band_wake(project: Path) -> None:
    payload = ledger.load(project)
    payload["watches"] = {"watch_a": {"channel": {"kind": "orca-run", "run": "r"},
                                      "openedTurn": 1, "closedTurn": None,
                                      "observations": [{"turn": 1, "total": 2, "settled": 0,
                                                        "digest": "old"}]}}
    ledger.save(project, payload)
    channel.runner = FakeOrca(workers=[worker("a"), worker("b", handle="term_b")])
    reason = channel.wake_reason(project)
    check("the-watchdog-wakes-when-every-dispatch-has-settled",
          reason is not None and "2/2" in reason, f"{reason}")

    payload = ledger.load(project)
    payload["watches"]["watch_a"]["observations"].append(
        {"turn": 2, "total": 2, "settled": 2,
         "digest": channel.sample("r")["digest"]})
    ledger.save(project, payload)
    check("the-watchdog-stays-quiet-once-the-coordinator-has-seen-it",
          channel.wake_reason(project) is None, f"{channel.wake_reason(project)}")

    channel.runner = FakeOrca(workers=[worker("a", status="dispatched"),
                                       worker("b", status="dispatched", handle="term_b")])
    payload = ledger.load(project)
    payload["watches"]["watch_a"]["observations"] = [
        {"turn": 1, "total": 2, "settled": 0, "digest": "old"}]
    ledger.save(project, payload)
    check("the-watchdog-does-not-wake-on-work-still-running",
          channel.wake_reason(project) is None, f"{channel.wake_reason(project)}")


def main() -> int:
    for probe in (probe_ack_is_chained, probe_questions_hold_a_terminal,
                  probe_heartbeats_are_not_reports, probe_channel_must_push,
                  probe_stall_is_counted_in_samples,
                  probe_only_settled_dispatches_are_retired,
                  probe_the_digest_tracks_what_changed,
                  probe_sweep_clears_the_dispatch_ledger, probe_out_of_band_wake):
        with_project(probe)
    print(f"channel probes: {len(FAILURES)} failed")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    raise SystemExit(main())
