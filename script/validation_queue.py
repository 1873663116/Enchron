#!/usr/bin/env python3
"""Coordinate Enchron's single local Apple-heavy validation slot.

This tool records facts and atomically leases the slot. It intentionally never
starts, interrupts, kills, or releases another process on a review deadline.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


ACTIVE_STATES = ("running", "attention_required", "blocked")
TERMINAL_STATES = ("passed", "failed", "cancelled")


class CommandError(Exception):
    pass


def now() -> datetime:
    return datetime.now(timezone.utc)


def timestamp(value: datetime | None = None) -> str:
    return (value or now()).isoformat(timespec="seconds")


def database_path(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()
    configured = os.environ.get("ENCHRON_VALIDATION_DB")
    if configured:
        return Path(configured).expanduser().resolve()
    try:
        common_dir = subprocess.check_output(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if common_dir:
            return Path(common_dir) / "enchron-validation.sqlite3"
    except (OSError, subprocess.CalledProcessError):
        pass
    return Path.cwd() / ".enchron-validation.sqlite3"


def connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path, timeout=10, isolation_level=None)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA journal_mode = WAL")
    connection.execute("PRAGMA busy_timeout = 10000")
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS validation_tasks (
            task_id TEXT PRIMARY KEY,
            summary TEXT NOT NULL,
            worktree TEXT NOT NULL,
            requested_by TEXT NOT NULL,
            validation_kind TEXT NOT NULL,
            command_text TEXT,
            state TEXT NOT NULL CHECK (state IN (
                'queued', 'running', 'attention_required', 'blocked',
                'passed', 'failed', 'cancelled'
            )),
            review_after_minutes INTEGER NOT NULL CHECK (review_after_minutes > 0),
            submitted_at TEXT NOT NULL,
            claimed_at TEXT,
            review_at TEXT,
            worker TEXT,
            reason TEXT,
            evidence TEXT,
            pid INTEGER,
            pgid INTEGER,
            completed_at TEXT,
            terminal_result TEXT,
            updated_at TEXT NOT NULL,
            slot INTEGER NOT NULL DEFAULT 1
        );
        CREATE UNIQUE INDEX IF NOT EXISTS one_active_validation_slot
            ON validation_tasks(slot)
            WHERE state IN ('running', 'attention_required', 'blocked');
        """
    )
    return connection


def row_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    result = dict(row)
    result["process_alive"] = process_alive(result["pid"])
    review_at = result.get("review_at")
    review_due = False
    if review_at and result["state"] in ACTIVE_STATES:
        review_due = datetime.fromisoformat(review_at) <= now()
    result["review_due"] = review_due
    result["controller_attention_required"] = result["state"] in ACTIVE_STATES and (
        review_due or (result["pid"] is not None and not result["process_alive"])
    )
    return result


def process_alive(pid: int | None) -> bool | None:
    if pid is None:
        return None
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def emit(args: argparse.Namespace, payload: dict[str, Any], exit_code: int = 0) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        message = payload.get("message") or payload.get("error") or "ok"
        print(message)
        task = payload.get("task")
        if task:
            print(f"{task['task_id']}: {task['state']}")
        active = payload.get("active")
        if active:
            print(f"active: {active['task_id']} ({active['state']})")
    raise SystemExit(exit_code)


def require_task(connection: sqlite3.Connection, task_id: str) -> sqlite3.Row:
    row = connection.execute(
        "SELECT * FROM validation_tasks WHERE task_id = ?", (task_id,)
    ).fetchone()
    if row is None:
        raise CommandError(f"unknown task: {task_id}")
    return row


def initialize(args: argparse.Namespace, connection: sqlite3.Connection, path: Path) -> None:
    emit(args, {"message": "validation queue initialized", "database": str(path)})


def submit(args: argparse.Namespace, connection: sqlite3.Connection, path: Path) -> None:
    try:
        connection.execute(
            """
            INSERT INTO validation_tasks (
                task_id, summary, worktree, requested_by, validation_kind,
                command_text, state, review_after_minutes, submitted_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, ?)
            """,
            (
                args.task_id,
                args.summary,
                str(Path(args.worktree).expanduser().resolve()),
                args.requested_by,
                args.kind,
                args.command,
                args.review_after_minutes,
                timestamp(),
                timestamp(),
            ),
        )
    except sqlite3.IntegrityError as error:
        raise CommandError(f"task already exists: {args.task_id}") from error
    task = require_task(connection, args.task_id)
    emit(args, {"message": "validation submitted", "task": row_dict(task)})


def claim(args: argparse.Namespace, connection: sqlite3.Connection, path: Path) -> None:
    connection.execute("BEGIN IMMEDIATE")
    try:
        active = connection.execute(
            "SELECT * FROM validation_tasks WHERE state IN ('running', 'attention_required', 'blocked')"
        ).fetchone()
        if active is not None:
            raise CommandError(
                f"validation slot is held by {active['task_id']} ({active['state']}); controller decision required"
            )
        task = connection.execute(
            "SELECT * FROM validation_tasks WHERE state = 'queued' ORDER BY submitted_at, task_id LIMIT 1"
        ).fetchone()
        if task is None:
            connection.execute("COMMIT")
            emit(args, {"message": "no queued validation task", "task": None})
        review_at = timestamp(now() + timedelta(minutes=task["review_after_minutes"]))
        connection.execute(
            """
            UPDATE validation_tasks
            SET state = 'running', worker = ?, claimed_at = ?, review_at = ?, updated_at = ?
            WHERE task_id = ?
            """,
            (args.worker, timestamp(), review_at, timestamp(), task["task_id"]),
        )
        connection.execute("COMMIT")
    except Exception:
        connection.execute("ROLLBACK")
        raise
    claimed = require_task(connection, task["task_id"])
    emit(args, {"message": "validation slot claimed", "task": row_dict(claimed)})


def record_process(args: argparse.Namespace, connection: sqlite3.Connection, path: Path) -> None:
    task = require_task(connection, args.task_id)
    if task["state"] not in ACTIVE_STATES:
        raise CommandError("only an active task may record a process")
    try:
        pgid = os.getpgid(args.pid)
    except ProcessLookupError as error:
        raise CommandError(f"process does not exist: {args.pid}") from error
    connection.execute(
        """
        UPDATE validation_tasks
        SET pid = ?, pgid = ?, command_text = COALESCE(?, command_text), updated_at = ?
        WHERE task_id = ?
        """,
        (args.pid, pgid, args.command, timestamp(), args.task_id),
    )
    emit(args, {"message": "validation process recorded", "task": row_dict(require_task(connection, args.task_id))})


def change_state(args: argparse.Namespace, connection: sqlite3.Connection, path: Path) -> None:
    task = require_task(connection, args.task_id)
    if task["state"] not in ACTIVE_STATES:
        raise CommandError("only an active task can be escalated, blocked, or resumed")
    if args.action == "resume":
        state = "running"
        reason = args.reason or task["reason"]
        review_at = timestamp(now() + timedelta(minutes=task["review_after_minutes"]))
    else:
        state = "attention_required" if args.action == "escalate" else "blocked"
        reason = args.reason
        review_at = task["review_at"]
    connection.execute(
        "UPDATE validation_tasks SET state = ?, reason = ?, review_at = ?, updated_at = ? WHERE task_id = ?",
        (state, reason, review_at, timestamp(), args.task_id),
    )
    emit(args, {"message": f"task {args.action}d", "task": row_dict(require_task(connection, args.task_id))})


def complete(args: argparse.Namespace, connection: sqlite3.Connection, path: Path) -> None:
    task = require_task(connection, args.task_id)
    if task["state"] not in ACTIVE_STATES:
        raise CommandError("only an active task can be completed")
    if process_alive(task["pid"]):
        raise CommandError(
            "recorded process is still alive; controller must stop or verify it before releasing the slot"
        )
    connection.execute(
        """
        UPDATE validation_tasks
        SET state = ?, terminal_result = ?, evidence = ?, completed_at = ?, updated_at = ?
        WHERE task_id = ?
        """,
        (args.outcome, args.outcome, args.evidence, timestamp(), timestamp(), args.task_id),
    )
    emit(args, {"message": "validation completed and slot released", "task": row_dict(require_task(connection, args.task_id))})


def status(args: argparse.Namespace, connection: sqlite3.Connection, path: Path) -> None:
    rows = connection.execute(
        "SELECT * FROM validation_tasks ORDER BY submitted_at, task_id"
    ).fetchall()
    tasks = [row_dict(row) for row in rows]
    active = next((task for task in tasks if task["state"] in ACTIVE_STATES), None)
    notifications = []
    if active and active["review_due"]:
        notifications.append(
            f"review deadline reached for {active['task_id']}; slot remains held until controller decision"
        )
    if active and active["pid"] is not None and not active["process_alive"]:
        notifications.append(
            f"recorded process for {active['task_id']} is not alive; slot remains held pending controller review"
        )
    emit(
        args,
        {
            "message": "validation queue status",
            "database": str(path),
            "active": active,
            "queue": [task for task in tasks if task["state"] == "queued"],
            "history": [task for task in tasks if task["state"] in TERMINAL_STATES],
            "notifications": notifications,
        },
    )


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    root.add_argument("--db", help="shared SQLite database path")
    root.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    commands = root.add_subparsers(dest="subcommand", required=True)
    commands.add_parser("init")

    submit_parser = commands.add_parser("submit")
    submit_parser.add_argument("task_id")
    submit_parser.add_argument("--summary", required=True)
    submit_parser.add_argument("--worktree", required=True)
    submit_parser.add_argument("--requested-by", required=True)
    submit_parser.add_argument("--kind", default="apple-heavy-validation")
    submit_parser.add_argument("--command")
    submit_parser.add_argument("--review-after-minutes", type=int, default=45)

    claim_parser = commands.add_parser("claim")
    claim_parser.add_argument("--worker", required=True)

    process_parser = commands.add_parser("record-process")
    process_parser.add_argument("task_id")
    process_parser.add_argument("--pid", type=int, required=True)
    process_parser.add_argument("--command")

    for action in ("escalate", "block", "resume"):
        action_parser = commands.add_parser(action)
        action_parser.add_argument("task_id")
        action_parser.add_argument("--reason")

    complete_parser = commands.add_parser("complete")
    complete_parser.add_argument("task_id")
    complete_parser.add_argument("--outcome", choices=TERMINAL_STATES, required=True)
    complete_parser.add_argument("--evidence", required=True)
    commands.add_parser("status")
    return root


def main() -> None:
    args = parser().parse_args()
    if getattr(args, "review_after_minutes", 1) <= 0:
        raise CommandError("--review-after-minutes must be positive")
    path = database_path(args.db)
    connection = connect(path)
    try:
        actions = {
            "init": initialize,
            "submit": submit,
            "claim": claim,
            "record-process": record_process,
            "escalate": change_state,
            "block": change_state,
            "resume": change_state,
            "complete": complete,
            "status": status,
        }
        actions[args.subcommand](args, connection, path)
    except CommandError as error:
        emit(args, {"error": str(error)}, exit_code=2)
    finally:
        connection.close()


if __name__ == "__main__":
    main()
