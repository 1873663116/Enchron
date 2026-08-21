#!/usr/bin/env python3
"""Stop hook: while this session has an in-progress regression-journey run
ledger with pending journeys, refuse to end the turn and feed back what
remains. The ledger is written by `regression_journeys.py run ...`; this hook
only reads facts from it and never judges journey content.

Fail-open rules, in order: no ledger, unreadable ledger, artifact volume not
mounted, ledger not in-progress, ledger owned by another session, or two
consecutive blocks with a byte-identical ledger (the driver is stuck; trapping
the session helps nobody). An in-progress ledger with no sessionId is adopted
by the first session that stops while it is open."""

import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(
    0, str(Path(__file__).resolve().parents[2] / "Scripts" / "verification")
)


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def write_json(path: Path, document) -> None:
    scratch = path.with_name(path.name + ".tmp")
    scratch.write_text(
        json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    scratch.replace(path)


def allow(message: str | None = None) -> int:
    if message:
        print(json.dumps({"systemMessage": message}, ensure_ascii=False))
    return 0


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    session_id = str(payload.get("session_id") or "")
    stop_hook_active = bool(payload.get("stop_hook_active"))

    try:
        from enchron_artifact_paths import artifact_root

        ledger_path = artifact_root() / "Temporary" / "regression-run" / "current.json"
    except BaseException:
        return 0

    ledger = load_json(ledger_path)
    if not isinstance(ledger, dict) or ledger.get("status") != "in-progress":
        return 0

    owner = ledger.get("sessionId")
    if owner and session_id and owner != session_id:
        return allow(
            "存在另一会话遗留的进行中旅程台账（"
            f"{ledger_path}）。本回合不拦截；"
            "接手请先用 regression_journeys.py run status 核对，"
            "放弃请 run abort --reason 记录原因。"
        )
    if not owner and session_id:
        ledger["sessionId"] = session_id
        write_json(ledger_path, ledger)

    journeys = [j for j in ledger.get("journeys", []) if isinstance(j, dict)]
    pending = [str(j.get("id")) for j in journeys if j.get("status") == "pending"]
    if not pending:
        return allow(
            "旅程台账全部条目已有终态但状态仍为 in-progress；"
            "运行 regression_journeys.py run close 收账。"
        )

    digest = hashlib.sha256(
        json.dumps(ledger, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()
    sidecar_path = ledger_path.with_name("stop-gate-state.json")
    sidecar = load_json(sidecar_path) or {}
    if stop_hook_active and sidecar.get("lastBlockedDigest") == digest:
        write_json(sidecar_path, {})
        return allow(
            "Stop hook 连续两次拦截期间台账无任何变化，放行以避免死循环。"
            f"仍有 {len(pending)} 条旅程未完成：{', '.join(pending)}。"
            "驱动通道若已不可用，用 run abort --reason 显式记录。"
        )
    write_json(sidecar_path, {"lastBlockedDigest": digest})

    terminal = {"passed": 0, "failed": 0, "voided": 0, "blocked": 0}
    for j in journeys:
        status = str(j.get("status"))
        if status in terminal:
            terminal[status] += 1
    summary = "、".join(
        f"{name} {count}" for name, count in terminal.items() if count
    ) or "尚无终态"
    print(
        json.dumps(
            {
                "decision": "block",
                "reason": (
                    "本会话的回归旅程轮次尚未结束："
                    f"{len(pending)} 条旅程待驱动（{', '.join(pending)}），"
                    f"已有终态：{summary}。下一条按台账顺序为 {pending[0]}。"
                    "继续逐条驱动并用 regression_journeys.py run verdict "
                    "<Jid> passed|failed|voided|blocked --reason 记录判定；"
                    "全部终态后 run close。无法继续时用 run abort --reason "
                    "显式放弃——旅程轮次可以不完整地结束，但只能带书面理由地结束。"
                ),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
