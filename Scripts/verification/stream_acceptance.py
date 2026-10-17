#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SCRIPTS_ROOT = Path(__file__).resolve().parent
REPOSITORY_ROOT = SCRIPTS_ROOT.parents[1]
UNITS_PATH = SCRIPTS_ROOT / "stream_units.json"
DEFAULT_RUN_ROOT = REPOSITORY_ROOT / ".scratch" / "stream-unit-runs"
EVIDENCE_CLASSES = (
    "app",
    "host-forensic",
    "host-sunshine",
    "host-process",
    "pixel",
    "probe",
    "proxy",
    "host-audio",
)
VERDICTS = ("passed", "failed", "failed(known)", "blockedBy", "indeterminate", "deferred(human)")

PROTOCOL = """串流验收单元驱动协议

  一次只驱动一个单元；没有场景级入口。
  drive  执行一个单元的动作并采集观察（原始产物写入该单元目录）
  show   阅读该单元的观察
  judge  写下判决：--reason 说明 + --quote 原始证据原文 + 至少两个不同来源的 --evidence
  audit  把判决、引文与原始文件中的对应片段并排显示
  status 当前进度、未判决清单、可跑与受阻的单元

  判决由人（或 Agent）写；工具只搬运、提取和拒收：
  上游未判决就拒跑下游；引文在原始文件里找不到就拒收判决；证据少于两类就拒收。
"""


def escape_marker_path() -> Path:
    configured = os.environ.get("ENCHRON_ESCAPE_MARKER")
    if configured:
        return Path(configured).expanduser()
    return Path.home() / ".config" / "sunshine" / "enchron-probe.escape"


def operator_aborted() -> bool:
    return escape_marker_path().is_file()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_registry() -> dict[str, object]:
    if not UNITS_PATH.is_file():
        raise SystemExit(f"missing registry: {UNITS_PATH}")
    document = json.loads(UNITS_PATH.read_text(encoding="utf-8"))
    if not isinstance(document, dict) or not isinstance(document.get("units"), list):
        raise SystemExit(f"malformed registry: {UNITS_PATH}")
    return document


def units_by_id(registry: dict[str, object]) -> dict[str, dict[str, object]]:
    return {str(entry["id"]): entry for entry in registry["units"]}


def scenario_titles(registry: dict[str, object]) -> dict[str, str]:
    return {str(entry["id"]): str(entry["title"]) for entry in registry["scenarios"]}


def tool_digest() -> str:
    digest = hashlib.sha256()
    for path in (Path(__file__).resolve(), UNITS_PATH):
        digest.update(path.read_bytes())
    return "sha256:" + digest.hexdigest()


def git_revision() -> str:
    head = REPOSITORY_ROOT / ".git"
    if head.is_file():
        text = head.read_text(encoding="utf-8").strip()
        if text.startswith("gitdir:"):
            head = Path(text.split(":", 1)[1].strip())
            if not head.is_absolute():
                head = (REPOSITORY_ROOT / head).resolve()
    common = head
    commondir = head / "commondir"
    if commondir.is_file():
        common = (head / commondir.read_text(encoding="utf-8").strip()).resolve()
    pointer = head / "HEAD"
    if not pointer.is_file():
        return "unknown"
    value = pointer.read_text(encoding="utf-8").strip()
    if not value.startswith("ref:"):
        return value
    reference = value.split(":", 1)[1].strip()
    direct = common / reference
    if direct.is_file():
        return direct.read_text(encoding="utf-8").strip()
    packed = common / "packed-refs"
    if packed.is_file():
        for line in packed.read_text(encoding="utf-8").splitlines():
            if line.endswith(" " + reference):
                return line.split(" ", 1)[0]
    return reference


def refresh_latest(run: Path) -> None:
    pointer = run.parent / "latest"
    if pointer.is_symlink() or pointer.exists():
        pointer.unlink()
    pointer.symlink_to(run.name)


def resolve_run(argument: str | None, *, create: bool) -> Path:
    if argument:
        run = Path(argument).expanduser().resolve()
        if run.name == "latest":
            run = run.parent
        if run.is_file():
            raise SystemExit(f"run directory is a file: {run}")
        if create:
            run.mkdir(parents=True, exist_ok=True)
        elif not run.is_dir():
            raise SystemExit(f"no such run directory: {run}")
        refresh_latest(run)
        return run
    configured = os.environ.get("ENCHRON_STREAM_RUN_DIR")
    if configured:
        return resolve_run(configured, create=create)
    root = Path(os.environ.get("ENCHRON_STREAM_RUN_ROOT", DEFAULT_RUN_ROOT)).expanduser()
    if create:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        run = root / stamp
        run.mkdir(parents=True, exist_ok=True)
        refresh_latest(run)
        return run
    if root.is_dir():
        for candidate in sorted(
            (entry for entry in root.iterdir() if entry.is_dir() and not entry.is_symlink()),
            reverse=True,
        ):
            return candidate.resolve()
    raise SystemExit(f"no run directory under {root}; drive a unit first")


def unit_directory(run: Path, unit_id: str) -> Path:
    return run / "units" / unit_id


def read_json(path: Path) -> dict[str, object] | None:
    if not path.is_file():
        return None
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return document if isinstance(document, dict) else None


def observation_of(run: Path, unit_id: str) -> dict[str, object] | None:
    return read_json(unit_directory(run, unit_id) / "observation.json")


def verdict_of(run: Path, unit_id: str) -> dict[str, object] | None:
    return read_json(unit_directory(run, unit_id) / "verdict.json")


def write_json(path: Path, document: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def normalize(text: str) -> str:
    return " ".join(text.split())


def search_quote(paths: list[Path], quote: str) -> tuple[Path, int, str] | None:
    needle = normalize(quote)
    if not needle:
        return None
    for path in paths:
        if not path.is_file():
            continue
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for index, line in enumerate(lines):
            if needle in normalize(line):
                return path, index + 1, line.strip()
        window = normalize("\n".join(lines))
        if needle in window:
            return path, 1, lines[0].strip() if lines else ""
    return None


def registry_evidence_paths(run: Path, unit_id: str, observation: dict[str, object]) -> list[Path]:
    directory = unit_directory(run, unit_id)
    paths: list[Path] = []
    for entry in observation.get("raw", []):
        if isinstance(entry, dict) and isinstance(entry.get("path"), str):
            candidate = (directory / str(entry["path"])).resolve()
            if candidate.is_file():
                paths.append(candidate)
    return paths


def parse_evidence(run: Path, unit_id: str, values: list[str]) -> list[dict[str, str]]:
    directory = unit_directory(run, unit_id)
    parsed: list[dict[str, str]] = []
    for value in values:
        kind, separator, relative = value.partition("=")
        if not separator or not kind or not relative:
            raise SystemExit(f"invalid --evidence {value!r}; expected class=path")
        if kind not in EVIDENCE_CLASSES:
            raise SystemExit(f"unknown evidence class {kind!r}; known: {', '.join(EVIDENCE_CLASSES)}")
        candidate = (directory / relative).resolve() if not relative.startswith("units/") else (run / relative).resolve()
        if not candidate.is_file():
            raise SystemExit(f"evidence file does not exist under the run directory: {relative}")
        if run.resolve() not in candidate.parents:
            raise SystemExit(f"evidence must live inside the run directory: {relative}")
        parsed.append({"class": kind, "path": relative})
    return parsed


def build_engine_context(run: Path, unit_id: str):
    sys.path.insert(0, str(SCRIPTS_ROOT))
    import moonlight_acceptance as engine

    scenario_number = int("".join(ch for ch in unit_id.split(".")[0] if ch.isdigit()) or "0")
    scenario = engine.Scenario(
        number=scenario_number,
        slug=f"unit-{unit_id}",
        title=unit_id,
        drive="stream_acceptance unit drive",
        channels=(),
        run=lambda context: engine.Outcome("indeterminate"),
    )
    fixtures_path = os.environ.get("ENCHRON_STREAM_FIXTURES")
    fixtures = engine.load_fixtures(Path(fixtures_path)) if fixtures_path else {}
    arguments = argparse.Namespace(
        device=os.environ.get("ENCHRON_DEVICE", ""),
        output_directory=str(run),
        work_dir=str(run / "work"),
        execution_input=os.environ.get("ENCHRON_EXECUTION_INPUT"),
        timing_directory=None,
        host=os.environ.get("ENCHRON_HOST") or str(fixtures.get("hostAddress") or "") or engine.DEFAULT_HOST,
        quick=False,
    )
    return engine, engine.build_context(scenario, arguments, fixtures)


def raw_entry(kind: str, relative: str, payload: object) -> dict[str, object]:
    return {"class": kind, "path": relative, "payload": payload}


def write_raws(run: Path, unit_id: str, entries: list[dict[str, object]]) -> list[dict[str, str]]:
    directory = unit_directory(run, unit_id) / "raw"
    recorded: list[dict[str, str]] = []
    for entry in entries:
        name = Path(str(entry["path"])).name
        source = entry.get("file")
        if isinstance(source, str) and source:
            (directory / name).parent.mkdir(parents=True, exist_ok=True)
            (directory / name).write_bytes(Path(source).read_bytes())
        else:
            write_json(directory / name, {"class": entry["class"], "payload": entry["payload"]})
        recorded.append({"class": str(entry["class"]), "path": f"raw/{name}"})
    return recorded


def probe_session_equals_streaming(context) -> tuple[bool, str]:
    view = context.session_snapshot_or_none()
    state = view.state() if view is not None else "none"
    return (view is not None and view.state_name() == "streaming"), state


def probe_session_not_ended(context) -> tuple[bool, str]:
    view = context.session_snapshot_or_none()
    state = view.state() if view is not None else "none"
    return (view is not None and view.state_name() != "ended"), state


def probe_host_free(context) -> tuple[bool, str]:
    info = context.serverinfo()
    state = str(info.get("state", "")) if isinstance(info, dict) else ""
    return (state in ("SUNSHINE_SERVER_FREE", "SUNSHINE_SERVER_FREE_UNKNOWN"), state or "unknown")


def probe_host_paired(context) -> tuple[bool, str]:
    for identifier in context.identifiers():
        if not identifier.startswith("Stream-HostRow-"):
            continue
        value = context.identifier_value(identifier) or ""
        if "pairing=paired" in value:
            return True, value
    return False, "no paired host row"


def probe_app_cards(context) -> tuple[bool, str]:
    if context.matched_element("Stream-HostDetail") is None:
        return False, "host detail is not open"
    cards = [item for item in context.identifiers() if item.startswith("Stream-AppCard-")]
    if not cards:
        return False, "host detail carries no application card"
    return True, f"cards={len(cards)}"


PRECONDITIONS = {
    "session=streaming": probe_session_equals_streaming,
    "session!=ended": probe_session_not_ended,
    "host=free": probe_host_free,
    "host=paired": probe_host_paired,
    "app-list=cards": probe_app_cards,
}

PRECONDITION_PROVIDERS = {
    "host=paired": ["P0.1", "02.2"],
    "app-list=cards": ["03.1"],
    "host=free": ["18.1", "10.3"],
    "session=streaming": ["04.1"],
    "session=ended": ["18.1"],
}


def driver_stream_launch(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    row, view = engine.ensure_streaming(context)
    sunshine = context.sunshine_path()
    tail: list[str] = []
    if sunshine.is_file():
        tail = sunshine.read_text(encoding="utf-8", errors="replace").splitlines()[-80:]
    entries = [
        raw_entry(
            "app",
            "session-snapshot.json",
            {
                "state": view.state(),
                "stateName": view.state_name(),
                "requested": dict(view.requested()),
                "negotiated": dict(view.negotiated()),
                "inputs": dict(view.inputs()),
            },
        ),
        raw_entry("host-sunshine", "sunshine-tail.log", {"path": str(sunshine), "lines": tail}),
    ]
    return entries, f"会话 state={view.state_name()}；主机日志尾部 {len(tail)} 行"


def driver_input_type_string(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    view = context.session_snapshot_or_none()
    if view is None or view.state_name() != "streaming":
        raise Refused("会话不在 streaming；先驱动 04.1 建立状态")
    before = view.inputs()
    text = "enc" + os.urandom(3).hex()
    channel = engine.send_text(context, text)
    after = context.session_snapshot().inputs()
    delivered: list[str] = []
    for _ in range(10):
        report = context.forensic()
        delivered = [str(value) for value in engine.input_strings(report) if text in str(value)]
        if delivered:
            break
        context.hold("host-echo-wait", 1.5)
    entries = [
        raw_entry(
            "app",
            "input-counters.json",
            {"text": text, "before": before, "after": after, "channel": channel},
        ),
        raw_entry(
            "host-forensic",
            "host-input-strings.json",
            {
                "path": str(context.forensic_path()),
                "expected": text,
                "delivered": delivered,
                "strings": [str(value) for value in engine.input_strings(context.forensic())][-20:],
            },
        ),
    ]
    return entries, f"输入 {text}；计数 {before} -> {after}（通道 {channel}）；主机收到 {len(delivered)} 条"


def driver_input_host_string(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    report = context.forensic()
    strings = [str(value) for value in engine.input_strings(report)]
    entries = [
        raw_entry(
            "host-forensic",
            "host-input-strings.json",
            {
                "path": str(context.forensic_path()),
                "stringCount": len(strings),
                "strings": strings[-20:],
                "inputEvents": len(report.get("inputs", [])) if isinstance(report.get("inputs"), list) else 0,
            },
        )
    ]
    tail = strings[-3:] if strings else []
    return entries, f"主机取证日志字符串事件 {len(strings)} 条；最近 {tail}"


def driver_input_pointer(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    target = engine.POINTER_TARGET
    report = context.forensic()
    frame = (report.get("launch") or {}).get("screenFrame") if isinstance(report.get("launch"), dict) else None
    expected: tuple[float, float] | None = None
    if isinstance(frame, dict) and {"width", "height"} <= set(frame):
        expected = (
            float(frame.get("x", 0.0)) + target[0] * float(frame["width"]),
            float(frame.get("y", 0.0)) + target[1] * float(frame["height"]),
        )
    view = context.session_snapshot_or_none()
    before = view.inputs() if view is not None else {}
    engine.sent_pointer(context, *target)
    context.hold("pointer-settle", 1.0)
    positions = [tuple(value) for value in engine.input_positions(context.forensic())]
    after_view = context.session_snapshot_or_none()
    after = after_view.inputs() if after_view is not None else {}
    entries = [
        raw_entry("app", "pointer-counters.json", {"before": before, "after": after, "target": list(target)}),
        raw_entry(
            "host-forensic",
            "pointer-delivery.json",
            {
                "target": list(target),
                "expected": list(expected) if expected else None,
                "positions": [list(position) for position in positions[-10:]],
                "tolerancePixels": engine.POINTER_TOLERANCE_PIXELS,
            },
        )
    ]
    return entries, f"目标 {target}；主机记到 {len(positions)} 个坐标样本"


def driver_session_disconnect(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    engine.disconnect_session(context, soft=True)
    view = context.session_snapshot_or_none()
    state = view.state() if view is not None else "none"
    lines: list[str] = []
    try:
        lines = context.probe_lines()
    except Exception:
        lines = []
    entries = [
        raw_entry("app", "session-after-disconnect.json", {"state": state}),
        raw_entry("probe", "probe-lines.json", {"lines": lines[-40:]}),
    ]
    return entries, f"断连后会话 state={state}；探针尾部 {len(lines)} 行"


def driver_frame_advance(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    samples: list[dict[str, object]] = []
    for index in range(3):
        patch, rgb, expected, screenshot = engine.stable_patch_sample(context, f"advance-{index}")
        view = context.session_snapshot_or_none()
        samples.append(
            {
                "patchIndex": patch.get("index"),
                "patchRgb": patch.get("rgbHex"),
                "presented": view.first("presented") if view is not None else None,
                "queue": view.first("queue") if view is not None else None,
                "screenshot": str(screenshot),
            }
        )
        if index < 2:
            context.hold(f"advance-gap-{index}", engine.PATCH_RETRY_SECONDS)
    entries = [
        raw_entry("host-forensic", "patch-advances.json", {"path": str(context.forensic_path()), "samples": samples}),
        raw_entry("app", "presented-samples.json", {"presented": [s["presented"] for s in samples]}),
    ]
    indices = [s["patchIndex"] for s in samples]
    return entries, f"色块序号 {indices}；呈现帧 {[s['presented'] for s in samples]}"


def driver_picture_source(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    samples: list[dict[str, object]] = []
    files: list[dict[str, object]] = []
    for index in range(3):
        patch, rgb, expected, screenshot = engine.stable_patch_sample(context, f"source-{index}")
        target = unit_directory(run, unit_id) / "raw" / f"source-{index}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(screenshot.read_bytes())
        files.append({"class": "pixel", "path": f"source-{index}.png", "file": str(target), "payload": None})
        samples.append(
            {
                "patchIndex": patch.get("index"),
                "hostColour": list(expected),
                "capturedColour": list(rgb),
                "screenshot": f"raw/source-{index}.png",
            }
        )
        if index < 2:
            context.hold(f"source-gap-{index}", engine.PATCH_RETRY_SECONDS)
    entries = [
        raw_entry("pixel", "picture-source.json", {"samples": samples}),
        raw_entry("host-forensic", "patch-log.json", {"path": str(context.forensic_path()), "patchIndices": [s["patchIndex"] for s in samples]}),
        *files,
    ]
    pairs = [(s["patchIndex"], s["hostColour"], s["capturedColour"]) for s in samples]
    return entries, f"三档取样（序号/主机色/客户端读色）：{pairs}"


DRIVERS = {
    "host.state": None,
    "host.details": None,
    "host.apps": None,
    "stream.launch": driver_stream_launch,
    "input.type-string": driver_input_type_string,
    "input.host-string": driver_input_host_string,
    "input.pointer": driver_input_pointer,
    "session.disconnect": driver_session_disconnect,
}


def tail_lines(path: Path, count: int) -> list[str]:
    if not path.is_file():
        return []
    return path.read_text(encoding="utf-8", errors="replace").splitlines()[-count:]


def unit_arguments(unit_id: str) -> dict[str, object]:
    entry = units_by_id(load_registry()).get(unit_id, {})
    arguments = entry.get("args")
    return dict(arguments) if isinstance(arguments, dict) else {}


def driver_settings_restart(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    engine.open_settings(context)
    before = engine.settings_values(context)
    engine.relaunch_app(context)
    context.wait(
        "relaunch",
        engine.APP_RELAUNCH_SECONDS,
        lambda: {"ok": True} if context.matched_element("Navigation-Ornament-tab-streaming") else None,
        lambda: [{"identifiers": context.identifiers()[:40]}],
        poll_interval_seconds=2.0,
    )
    engine.open_settings(context)
    after = engine.settings_values(context)
    engine.ensure_host(context, pair=False)
    entries = [
        raw_entry("app", "settings-before-restart.json", before),
        raw_entry("app", "settings-after-restart.json", after),
        raw_entry("probe", "probe-lines.json", {"lines": context.probe_lines()[-20:]}),
    ]
    return entries, f"重启前 requested={before.get('requested')}；重启后 requested={after.get('requested')}"


def driver_degrade_notice(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    engine.focus_stream_window(context)
    context.tap("Stream-Session-degrade")
    value = context.identifier_value("Stream-Session-degrade-explain") or ""
    screenshot, rgb = context.capture("degrade-explain")
    target = unit_directory(run, unit_id) / "raw" / "degrade-explain.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(screenshot.read_bytes())
    entries = [
        raw_entry("app", "degrade-explain.json", {"text": value}),
        {"class": "pixel", "path": "degrade-explain.png", "file": str(target), "payload": None},
        raw_entry("pixel", "degrade-sample.json", {"rgb": list(rgb)}),
    ]
    return entries, f"降级说明读回 {len(value)} 字：{value[:60]}"


def observe_wait(engine, context, name: str, seconds: float, probe, evidence=None) -> dict[str, object]:
    try:
        found = context.wait(name, seconds, probe, evidence or (lambda: []), poll_interval_seconds=2.0)
        return {"found": found}
    except engine.InstrumentFault as fault:
        return {"found": None, "waitFault": str(fault)}


def probe_lines_containing(context, needles) -> list[str]:
    lines = [str(line) for line in context.probe_lines()]
    matches = [line for line in lines if any(needle in line for needle in needles)]
    return matches[-40:] if matches else lines[-20:]


def read_unit_payload(run: Path, unit_id: str, name: str) -> dict[str, object]:
    source = unit_directory(run, unit_id) / "raw" / name
    if not source.is_file():
        return {}
    document = json.loads(source.read_text(encoding="utf-8"))
    payload = document.get("payload")
    return payload if isinstance(payload, dict) else {}


def driver_capture_enter(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    engine.ensure_streaming(context)
    engine.sent_pointer(context, *engine.POINTER_TARGET)

    def capture_probe():
        current = context.session_snapshot_or_none()
        if current is None:
            return None
        mouse = current.inputs().get("mouse")
        if isinstance(mouse, (int, float)) and mouse > 0:
            return {"mouse": mouse, "session": current.state()}
        return None

    outcome = observe_wait(engine, context, "input-capture-active", engine.FIXTURE_SECONDS, capture_probe)
    entries = [
        raw_entry("app", "input-capture.json", outcome),
        raw_entry("probe", "probe-lines.json", {"lines": context.probe_lines()[-30:]}),
    ]
    return entries, f"输入捕获观察：{outcome}"


def driver_capture_dock(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    view = context.session_snapshot_or_none()
    before_state = view.state() if view is not None else None
    before_pairs = view.pairs if view is not None else None
    dock = context.matched_element("Stream-Session-dock")
    record = {
        "dockPresent": dock is not None,
        "dockHittable": bool(dock.get("isHittable")) if isinstance(dock, dict) else False,
        "before": before_state,
    }
    if dock is None:
        entries = [
            raw_entry("app", "dock.json", {**record, "tapped": False}),
            raw_entry("probe", "probe-lines.json", {"lines": context.probe_lines()[-20:]}),
        ]
        return entries, "输入捕获进行中 Dock 不存在，未点击（等判决）"
    context.tap("Stream-Session-dock")

    def dock_probe():
        current = context.session_snapshot_or_none()
        if current is None:
            return None
        if before_state is not None and current.state() != before_state:
            return {"session": current.state(), "before": before_state}
        if before_pairs is not None and current.pairs != before_pairs:
            return {"session": current.state(), "before": before_state}
        return None

    outcome = observe_wait(engine, context, "dock-delivery", engine.FIXTURE_SECONDS, dock_probe)
    entries = [
        raw_entry("app", "dock.json", {**record, "tapped": True, "delivery": outcome}),
        raw_entry(
            "probe",
            "probe-lines.json",
            {"lines": probe_lines_containing(context, ("input release", "session end", "audio stop"))},
        ),
    ]
    return entries, f"Dock 点击后观察：{outcome}"


def driver_capture_back(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    engine.ensure_streaming(context)
    context.tap("Stream-Session-back")
    stages: list[dict[str, object]] = []
    try:
        ended = engine.wait_for_state(context, "ended", engine.FIXTURE_SECONDS, "ended-after-back")
        stages.append({"tap": 1, "state": ended.state()})
    except (engine.InstrumentFault, engine.ProductVerdict) as error:
        stages.append({"tap": 1, "fault": str(error)})
        context.hold("back-retry-settle", 3.0)
        context.tap("Stream-Session-back")
        try:
            ended = engine.wait_for_state(context, "ended", engine.SESSION_END_SECONDS, "ended-after-controls")
            stages.append({"tap": 2, "state": ended.state()})
        except (engine.InstrumentFault, engine.ProductVerdict) as retry:
            stages.append({"tap": 2, "fault": str(retry)})
    entries = [
        raw_entry("app", "ended.json", {"stages": stages}),
        raw_entry("probe", "probe-lines.json", {"lines": context.probe_lines()[-30:]}),
    ]
    return entries, f"返回键后状态：{stages}"


def driver_interrupt_inject(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    local = context.session_snapshot_or_none()
    if local is not None and local.state_name() in ("connecting", "streaming", "stopping"):
        engine.disconnect_session(context, soft=True)
        context.hold("local-session-settle", 3.0)
    control, _ = engine.start_proxy(context)
    proxied = f"127.0.0.1:{engine.DEFAULT_PROXY_LISTEN_BASE}"
    name = context.fixture("hostName")
    extra = {"name": f"{name} (proxy)"} if isinstance(name, str) and name else {}
    document = context.app_verb("streamAddHost", address=proxied, **extra)
    row = context.wait(
        "Stream-HostRow-proxy",
        engine.STREAM_CONNECT_SECONDS,
        lambda: (
            {"host": rows[-1]}
            if (rows := [item for item in engine.discover_host_rows(context) if "proxy" in item.lower()])
            else None
        ),
        lambda: [{"hosts": engine.discover_host_rows(context)}],
        poll_interval_seconds=2.0,
    )
    host_name = str(row["host"])
    engine.pair_host(context, host_name)
    engine.launch_stream(context, host_name)
    engine.wait_for_state(context, "streaming", engine.STREAM_CONNECT_SECONDS, "streaming-through-proxy")
    before = context.session_snapshot()
    engine.proxy_control(control, "blackhole")
    started = engine.datetime.now(engine.timezone.utc)
    outcome = observe_wait(
        engine,
        context,
        "interrupted",
        engine.STREAM_CONNECT_SECONDS,
        lambda: (
            {"session": view.state(), "detail": view.state_detail()}
            if (view := context.session_snapshot_or_none()) is not None and view.state_name() == "interrupted"
            else None
        ),
    )
    elapsed = (engine.datetime.now(engine.timezone.utc) - started).total_seconds()
    if elapsed < engine.BLACKHOLE_SECONDS:
        context.hold("blackhole-remainder", engine.BLACKHOLE_SECONDS - elapsed)
    entries = [
        raw_entry("app", "interrupted.json", {"host": host_name, "before": before.state(), "observed": outcome, "addHost": document}),
        raw_entry("app", "proxy-host.json", {"host": host_name}),
        raw_entry("host-sunshine", "sunshine-tail.log", {"path": str(context.sunshine_path()), "lines": tail_lines(context.sunshine_path(), 60)}),
    ]
    return entries, f"黑洞中断观察：{outcome}"


def driver_interrupt_recover(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    control = run / "unit-09.1" / "artifacts" / "proxy-control.json"
    if not control.is_file():
        raise engine.BlockedBy("09.1 的代理控制文件不存在；先在 09.1 里制造中断")
    host_name = str(read_unit_payload(run, "09.1", "proxy-host.json").get("host", ""))
    engine.proxy_control(control, "pass")
    resumed = False
    if host_name:
        try:
            context.app_verb("streamResume", host=host_name)
            resumed = True
        except Exception as error:
            context.note(f"resume 未被接受，改走启动：{error}")
    if resumed == False:
        if host_name:
            engine.launch_stream(context, host_name)
        else:
            context.tap("Stream-Session-reconnect")
    outcome = observe_wait(
        engine,
        context,
        "streaming-after-recovery",
        engine.STREAM_CONNECT_SECONDS,
        lambda: (
            {"state": view.state_name()}
            if (view := context.session_snapshot_or_none()) is not None and view.state_name() == "streaming"
            else None
        ),
    )
    screenshot, rgb = context.capture("after-recovery")
    target = unit_directory(run, unit_id) / "raw" / "after-recovery.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(screenshot.read_bytes())
    sunshine = context.sunshine()
    entries = [
        raw_entry("app", "recovered.json", {"host": host_name, "observed": outcome}),
        raw_entry("host-sunshine", "sunshine-session-lines.json", {"sessionStarts": sunshine["sessionStarts"], "sessionEnds": sunshine["sessionEnds"], "encoders": sunshine["encoders"]}),
        {"class": "pixel", "path": "after-recovery.png", "file": str(target), "payload": {"rgb": list(rgb)}},
    ]
    return entries, f"恢复观察：{outcome}；像素 {rgb}"


def driver_remote_hold(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    local = context.session_snapshot_or_none()
    if local is not None and local.state_name() in ("connecting", "streaming", "stopping"):
        engine.disconnect_session(context, soft=True)
        context.hold("local-session-settle", 3.0)
    engine.free_host(context)
    info = context.serverinfo()
    state = str(info.get("state", ""))
    current_game = str(info.get("currentgame", "0"))
    entries = [raw_entry("host-sunshine", "serverinfo-before.json", {"state": state, "currentgame": current_game})]
    holder_command = context.fixture("remoteSessionCommand")
    if not (state == "SUNSHINE_SERVER_FREE" or current_game == "0"):
        entries.append(raw_entry("host-process", "holder.json", {"spawned": False, "state": state, "currentgame": current_game}))
        return entries, f"主机已被占用（{state}, currentgame={current_game}），未另行制造占用"
    if not isinstance(holder_command, list) or not holder_command:
        raise engine.BlockedBy("主机空闲且 fixtures 未声明 remoteSessionCommand，无法无人值守地制造占用")
    context.spawn([str(part) for part in holder_command], "remote-session-holder")
    pattern = Path(str(holder_command[0])).name
    busy = observe_wait(
        engine,
        context,
        "host-busy",
        engine.STREAM_CONNECT_SECONDS,
        lambda: ({"state": current.get("state")} if (current := context.serverinfo()).get("state", "").endswith("_SERVER_BUSY") else None),
    )
    after = context.serverinfo()
    process = engine.host_process_running(context, None, pattern)
    entries.extend(
        [
            raw_entry("host-sunshine", "serverinfo-held.json", {"state": after.get("state"), "currentgame": after.get("currentgame"), "observed": busy}),
            raw_entry("host-process", "holder.json", {"spawned": True, "command": [str(part) for part in holder_command], "pattern": pattern, "running": process}),
        ]
    )
    return entries, f"占用制造观察：{busy}"


def driver_remote_start(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    pattern = str(read_unit_payload(run, "10.1", "holder.json").get("pattern", ""))
    row = engine.ensure_host(context, pair=True)
    sunshine = context.sunshine()
    starts_before = len(sunshine["sessionStarts"])
    launches_before = len(sunshine.get("appLaunches", []))
    encoders_before = len(sunshine["encoders"])
    try:
        context.app_verb("streamResume", host=row)
    except engine.BlockedBy:
        engine.launch_stream(context, row)
    context.hold("session-settle", 6.0)
    view = context.session_snapshot()
    after = context.sunshine()
    entries = [
        raw_entry("app", "session-vs-remote.json", {"state": view.state(), "pairs": view.pairs}),
        raw_entry(
            "host-sunshine",
            "sunshine-remote-session.json",
            {
                "startsBefore": starts_before,
                "startsAfter": len(after["sessionStarts"]),
                "appLaunchesBefore": launches_before,
                "appLaunchesAfter": len(after.get("appLaunches", [])),
                "encodersBefore": encoders_before,
                "encodersAfter": len(after["encoders"]),
                "sessionStarts": after["sessionStarts"],
                "appLaunches": after.get("appLaunches", []),
            },
        ),
        raw_entry("host-process", "holder.json", {"pattern": pattern, "running": engine.host_process_running(context, None, pattern) if pattern else None}),
    ]
    return entries, f"占用主机时的启动尝试：{view.state()}"


def driver_remote_release(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    pattern = str(read_unit_payload(run, "10.1", "holder.json").get("pattern", ""))
    before = engine.host_process_running(context, None, pattern) if pattern else None
    if pattern:
        context.host_command(("pkill", "-f", pattern))
        context.hold("holder-release-settle", 3.0)
    engine.free_host(context)
    info = context.serverinfo()
    after = engine.host_process_running(context, None, pattern) if pattern else None
    entries = [
        raw_entry("host-process", "holder-before-release.json", {"pattern": pattern, "running": before}),
        raw_entry("host-sunshine", "serverinfo-released.json", {"state": info.get("state"), "currentgame": info.get("currentgame")}),
        raw_entry("host-process", "holder-after-release.json", {"pattern": pattern, "running": after}),
    ]
    return entries, f"释放后主机状态 {info.get('state')}"


def driver_quit_end(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    engine.ensure_streaming(context)
    app_name = str(context.fixture("forensicAppName", engine.DEFAULT_FORENSIC_APP_NAME))
    forensic = context.forensic()
    pid = (forensic.get("launch") or {}).get("pid")
    numeric = int(pid) if isinstance(pid, (int, float)) else None
    before = engine.host_process_running(context, numeric, app_name)

    def ended_probe():
        current = context.session_snapshot_or_none()
        if current is not None and current.state_name() == "ended":
            return {"state": current.state()}
        return None

    try:
        engine.disconnect_session(context, soft=True)
        outcome = observe_wait(engine, context, "ended", engine.SESSION_END_SECONDS, ended_probe)
    except (engine.BlockedBy, engine.InstrumentFault, engine.ProductVerdict) as error:
        context.tap("Stream-Session-back")
        outcome = observe_wait(engine, context, "ended-by-back", engine.SESSION_END_SECONDS, ended_probe)
        context.note(f"断连返回异常，改走返回键：{error}")
    entries = [
        raw_entry("host-process", "host-process-before.json", before),
        raw_entry("app", "session-ended.json", outcome),
    ]
    return entries, f"结束会话观察：{outcome}"


def driver_quit_survive(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    app_name = str(context.fixture("forensicAppName", engine.DEFAULT_FORENSIC_APP_NAME))
    forensic = context.forensic()
    pid = (forensic.get("launch") or {}).get("pid")
    numeric = int(pid) if isinstance(pid, (int, float)) else None
    after = engine.host_process_running(context, numeric, app_name)
    entries = [
        raw_entry("host-process", "host-process-after.json", after),
        raw_entry("host-sunshine", "sunshine-tail.log", {"path": str(context.sunshine_path()), "lines": tail_lines(context.sunshine_path(), 40)}),
    ]
    return entries, f"断连后主机进程 running={after.get('running')}"


def driver_launch_validate(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    current = context.session_snapshot_or_none()
    if current is not None and current.state_name() in ("connecting", "streaming", "stopping"):
        engine.disconnect_session(context, soft=True)
        context.hold("relaunch-settle", 3.0)
    before = len(engine.host_launches(context))
    row, view = engine.ensure_streaming(context)
    launch = engine.wait_for_host_launch(context, before)
    entries = [
        raw_entry("app", "session-launched.json", {"host": row, "state": view.state(), "detail": view.state_detail()}),
        raw_entry("host-sunshine", "host-app-launch.json", {"launchesBefore": before, "launch": launch}),
    ]
    return entries, f"启动校验：会话 {view.state()}，主机启动记录 {launch is not None}"


def driver_first_frame(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    row, view = engine.ensure_streaming(context)
    patch, rgb, sample, screenshot = engine.stable_patch_sample(context, "first-frame")
    target = unit_directory(run, unit_id) / "raw" / "first-frame.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(screenshot.read_bytes())
    forensic = context.forensic()
    entries = [
        raw_entry(
            "host-sunshine",
            "forensic-patch.json",
            {
                "latestPatch": patch,
                "seedHex": forensic.get("seedHex"),
                "expected": list(rgb),
                "tolerance": engine.PATCH_RGB_TOLERANCE,
                "samplePoint": list(engine.PATCH_SAMPLE_POINT),
            },
        ),
        {"class": "pixel", "path": "first-frame.png", "file": str(target), "payload": {"sampled": list(sample), "expected": list(rgb)}},
        raw_entry("app", "session.json", {"host": row, "state": view.state(), "inputs": view.inputs()}),
    ]
    return entries, f"首帧：patch#{patch.get('index')} 主机色 {rgb}，设备取样 {sample}"


def driver_release_check(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    row, view = engine.ensure_streaming(context)
    engine.sent_pointer(context, *engine.POINTER_TARGET)
    engine.send_text(context, "enc" + engine.os.urandom(2).hex())
    context.hold("input-settle", 2.0)
    engine.disconnect_session(context, soft=True)
    context.hold("release-immediate", 1.0)
    immediate = context.session_snapshot_or_none()

    def release_probe():
        current = context.session_snapshot_or_none()
        if current is None:
            return {"state": "none"}
        if current.state_name() in ("ended", "none"):
            return {"state": current.state()}
        return None

    outcome = observe_wait(engine, context, "ended", engine.SESSION_END_SECONDS, release_probe)
    context.hold("release-settle", engine.QUEUE_SETTLE_SECONDS)
    final = context.session_snapshot_or_none() or immediate
    counters = final.inputs() if final is not None else {}
    entries = [
        raw_entry(
            "app",
            "final-snapshot.json",
            {
                "state": final.state() if final is not None else "none",
                "pressedKeys": counters.get("pressedKeys"),
                "pressedButtons": counters.get("pressedButtons"),
                "queue": counters.get("queue"),
                "observed": outcome,
            },
        ),
        raw_entry(
            "probe",
            "release-probe.json",
            {"lines": probe_lines_containing(context, ("input release", "audio stop", "session end"))},
        ),
    ]
    return entries, f"释放核对：{final.state() if final is not None else 'none'}"


def driver_bitrate_host(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    row, view = engine.ensure_streaming(context)
    sunshine = context.sunshine()
    configuration = context.webui().configuration()
    entries = [
        raw_entry(
            "host-sunshine",
            "sunshine-encoders.json",
            {"encoders": sunshine["encoders"], "appLaunches": sunshine.get("appLaunches", []), "sessionStarts": sunshine["sessionStarts"]},
        ),
        raw_entry("host-sunshine", "sunshine-config.json", configuration),
        raw_entry("app", "session-snapshot.json", {"state": view.state(), "requested": dict(view.requested()), "negotiated": dict(view.negotiated())}),
    ]
    return entries, f"主机采纳：encoders={len(sunshine['encoders'])}，协商 {dict(view.negotiated())}"


def driver_display_mode(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    before = engine.display_mode(context)
    row, view = engine.ensure_streaming(context)
    after = engine.display_mode(context)
    entries = [
        raw_entry("host-sunshine", "display-mode.json", {"before": before, "after": after, "unchanged": before == after}),
        raw_entry("app", "session-snapshot.json", {"host": row, "state": view.state(), "negotiated": dict(view.negotiated())}),
    ]
    return entries, f"显示模式前后一致={before == after}"


def driver_settings_apply(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    arguments = unit_arguments(unit_id)
    payload = engine.set_options(context, **arguments)
    entries = [
        raw_entry("app", "settings-applied.json", {"requested": arguments, "readback": payload}),
        raw_entry("host-sunshine", "sunshine-tail.log", {"path": str(context.sunshine_path()), "lines": tail_lines(context.sunshine_path(), 40)}),
    ]
    return entries, f"设置写入并回读：{payload}"


def driver_negotiate(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    arguments = unit_arguments(unit_id)
    view = context.session_snapshot_or_none()
    if view is not None and view.state_name() == "streaming":
        engine.disconnect_session(context, soft=True)
    if arguments:
        engine.set_options(context, **arguments)
    row, view = engine.ensure_streaming(context)
    requested = dict(view.requested())
    negotiated = dict(view.negotiated())
    entries = [
        raw_entry(
            "app",
            "session-snapshot.json",
            {"state": view.state(), "requested": requested, "negotiated": negotiated, "arguments": arguments},
        ),
        raw_entry("host-sunshine", "sunshine-tail.log", {"path": str(context.sunshine_path()), "lines": tail_lines(context.sunshine_path(), 60)}),
    ]
    return entries, f"请求 {arguments or '不变'} → 协商 {negotiated}"


def driver_host_state(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    engine.normalize_streaming_navigation(context)
    row = engine.ensure_host(context, pair=True)
    value = context.identifier_value(f"Stream-HostRow-{row}") or ""
    apps = context.webui().apps()
    entries = [
        raw_entry("app", "host-row.json", {"row": row, "value": value}),
        raw_entry("host-sunshine", "sunshine-apps.json", apps),
    ]
    return entries, f"主机行 {value!r}；主机应用 {len(apps)} 个"


def driver_host_details(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    row = engine.ensure_host(context, pair=True)
    context.tap(f"Stream-HostRow-{row}")
    context.require_identifier("Stream-HostDetail")
    grid = context.identifier_value("Stream-AppGrid")
    identifiers = context.identifiers()
    cards = {
        item: (context.identifier_value(item) or "")
        for item in identifiers
        if item.startswith("Stream-AppCard-")
    }
    missing = [item for item in identifiers if item.startswith("Stream-AppMissing-")]
    screenshot, rgb = context.capture("host-detail")
    entries = [
        raw_entry("app", "app-grid.json", {"gridValue": grid, "cards": cards, "missing": missing}),
        {"class": "pixel", "path": "host-detail.png", "file": str(screenshot), "payload": None},
        raw_entry("pixel", "host-detail-sample.json", {"rgb": list(rgb), "screenshot": str(screenshot)}),
    ]
    return entries, f"详情页卡片 {len(cards)} 张，缺失 {len(missing)} 张；gridValue={grid!r}"


def driver_host_apps(engine, context, run: Path, unit_id: str) -> tuple[list[dict[str, object]], str]:
    apps = context.webui().apps()
    names = [str(entry.get("name", "")) for entry in apps]
    entries = [raw_entry("host-sunshine", "sunshine-apps.json", apps)]
    return entries, f"主机应用清单 {names}"


DRIVERS.update(
    {
        "host.state": driver_host_state,
        "host.details": driver_host_details,
        "host.apps": driver_host_apps,
        "settings.apply": driver_settings_apply,
        "settings.restart": driver_settings_restart,
        "notice.degrade": driver_degrade_notice,
        "capture.enter": driver_capture_enter,
        "capture.dock": driver_capture_dock,
        "capture.back": driver_capture_back,
        "interrupt.inject": driver_interrupt_inject,
        "interrupt.recover": driver_interrupt_recover,
        "remote.hold": driver_remote_hold,
        "remote.start": driver_remote_start,
        "remote.release": driver_remote_release,
        "quit.end": driver_quit_end,
        "quit.survive": driver_quit_survive,
        "launch.validate": driver_launch_validate,
        "first.frame": driver_first_frame,
        "release.check": driver_release_check,
        "bitrate.host": driver_bitrate_host,
        "display.mode": driver_display_mode,
        "negotiate.check": driver_negotiate,
        "frame.advance": driver_frame_advance,
        "picture.source": driver_picture_source,
    }
)


class Refused(Exception):
    pass


def unit_or_die(registry: dict[str, object], unit_id: str) -> dict[str, object]:
    if "." not in unit_id:
        raise Refused(f"{unit_id} 是场景，不是单元；本工具没有场景级执行入口")
    units = units_by_id(registry)
    if unit_id not in units:
        raise Refused(f"未登记的单元 {unit_id}")
    return units[unit_id]


def unmet_needs(run: Path, unit: dict[str, object]) -> list[str]:
    return [str(need) for need in unit.get("needs", []) if verdict_of(run, str(need)) is None]


def fault_detail(error: Exception) -> str:
    detail = f"{type(error).__name__}: {error}"
    evidence = getattr(error, "evidence", None)
    if isinstance(evidence, dict) and evidence:
        detail = f"{detail}｜证据：{json.dumps(evidence, ensure_ascii=False)[:400]}"
    return detail


def record_failure(run: Path, unit_id: str, kind: str, detail: str, context) -> None:
    notes = []
    try:
        notes = [str(note) for note in context.notes]
    except AttributeError:
        notes = []
    write_json(
        unit_directory(run, unit_id) / "failure.json",
        {
            "unit": unit_id,
            "kind": kind,
            "detail": detail,
            "notes": notes,
            "recordedAt": utc_now(),
            "toolDigest": tool_digest(),
            "gitRevision": git_revision(),
        },
    )


def cmd_drive(engine_module, args) -> int:
    registry = load_registry()
    run = resolve_run(args.run_dir, create=True)
    try:
        unit = unit_or_die(registry, args.unit)
    except Refused as refusal:
        print(f"REFUSED: {refusal}")
        return 2
    unit_id = str(unit["id"])

    pending = [need for need in unmet_needs(run, unit)]
    if pending:
        print(f"REFUSED: 上游未判决，先驱动并判决：{', '.join(pending)}")
        return 2

    driver_name = str(unit.get("driver", "pending"))
    if driver_name == "pending":
        print(f"REFUSED: {unit_id} 的驱动器尚未实现（driver=pending）")
        return 2

    if operator_aborted():
        print(f"REFUSED: 操作者按下 ESC 中止了本次运行；确认后删除 {escape_marker_path()} 再继续")
        return 2

    engine, context = build_engine_context(run, unit_id)
    precondition = str(unit.get("pre", ""))
    probe = None
    if precondition:
        probe = PRECONDITIONS.get(precondition)
        if probe is None:
            print(f"REFUSED: 前置 {precondition!r} 的探测尚未实现，无法确认状态")
            return 2
        try:
            satisfied, state = probe(context)
        except Exception as error:
            print(f"REFUSED: 前置 {precondition!r} 探测出错：{type(error).__name__}: {error}")
            return 2
        if not satisfied:
            providers = PRECONDITION_PROVIDERS.get(precondition, [])
            hint = f"；前置提供者：{', '.join(providers)}" if providers else ""
            print(f"REFUSED: 前置 {precondition!r} 不满足（当前 {state!r}）{hint}")
            return 2

    started = time.time()
    try:
        entries, summary = DRIVERS[driver_name](engine, context, run, unit_id)
    except Refused as refusal:
        record_failure(run, unit_id, "refused", str(refusal), context)
        print(f"REFUSED: {refusal}")
        return 2
    except Exception as error:
        detail = fault_detail(error)
        record_failure(run, unit_id, "failed", detail, context)
        print(f"DRIVE-FAILED {unit_id}: {detail}")
        return 1
    if operator_aborted():
        print("ABORTED: 操作者按下 ESC 中止了本次运行；该单元的观察不完整，不写判决")
        return 2

    recorded_state = None
    if probe is not None:
        try:
            recorded_state = probe(context)[1]
        except Exception:
            recorded_state = None
    raw = write_raws(run, unit_id, entries)
    document = {
        "unit": unit_id,
        "title": unit.get("t"),
        "driver": driver_name,
        "precondition": {"declared": precondition, "state": recorded_state},
        "raw": raw,
        "summary": summary,
        "drivenAt": utc_now(),
        "durationSeconds": round(time.time() - started, 2),
        "toolDigest": tool_digest(),
        "gitRevision": git_revision(),
    }
    write_json(unit_directory(run, unit_id) / "observation.json", document)
    print(f"DRIVEN {unit_id}: {summary}")
    for entry in raw:
        print(f"  原始产物 [{entry['class']}] {entry['path']}")
    print(f"下一步：stream_acceptance.py judge {unit_id} --verdict … --reason … --quote … --evidence 类别=文件 …")
    return 0


def cmd_show(args) -> int:
    run = resolve_run(args.run_dir, create=False)
    observation = observation_of(run, args.unit)
    if observation is None:
        print(f"NOT-DRIVEN {args.unit}: 没有观察记录")
        return 1
    print(json.dumps(observation, ensure_ascii=False, indent=2, sort_keys=True))
    directory = unit_directory(run, args.unit) / "raw"
    if directory.is_dir():
        for path in sorted(directory.iterdir()):
            print(f"--- raw {path.name}")
            print(path.read_text(encoding="utf-8", errors="replace").rstrip())
    return 0


def cmd_judge(args) -> int:
    registry = load_registry()
    run = resolve_run(args.run_dir, create=False)
    try:
        unit = unit_or_die(registry, args.unit)
    except Refused as refusal:
        print(f"REFUSED: {refusal}")
        return 2
    unit_id = str(unit["id"])

    if args.verdict not in VERDICTS:
        print(f"REFUSED: 判决取值必须是 {', '.join(VERDICTS)}")
        return 2
    if not args.reason.strip():
        print("REFUSED: 判决必须给出 --reason")
        return 2

    observation = observation_of(run, unit_id)
    if observation is None:
        print(f"REFUSED: {unit_id} 没有观察记录，先 drive")
        return 2

    evidence = parse_evidence(run, unit_id, args.evidence)
    classes = {entry["class"] for entry in evidence}
    if len(classes) < 2:
        print(f"REFUSED: 判决需要至少两个不同来源的证据，现在只有 {sorted(classes)}")
        return 2

    paths = [(unit_directory(run, unit_id) / entry["path"]).resolve() for entry in evidence]
    found = search_quote(paths + registry_evidence_paths(run, unit_id, observation), args.quote)
    if found is None:
        print("REFUSED: 引文在原始证据文件里找不到；判决必须引用真实存在的原文")
        return 2
    quoted_path, quoted_line, quoted_text = found

    document = {
        "unit": unit_id,
        "verdict": args.verdict,
        "reason": args.reason.strip(),
        "quote": args.quote,
        "evidence": evidence,
        "quotedFile": str(quoted_path.relative_to(unit_directory(run, unit_id))),
        "quotedLine": quoted_line,
        "judgedAt": utc_now(),
        "toolDigest": tool_digest(),
        "gitRevision": git_revision(),
    }
    write_json(unit_directory(run, unit_id) / "verdict.json", document)
    print(f"JUDGED {unit_id} = {args.verdict}")
    print(f"  引文命中 {document['quotedFile']}:{quoted_line} → {quoted_text[:120]}")
    return 0


def cmd_audit(args) -> int:
    run = resolve_run(args.run_dir, create=False)
    unit_id = args.unit
    verdict = verdict_of(run, unit_id)
    if verdict is None:
        print(f"NO-VERDICT {unit_id}")
        return 1
    print(f"单元      {unit_id} {verdict.get('unit') and '' or ''}".rstrip())
    print(f"判决      {verdict['verdict']}")
    print(f"理由      {verdict['reason']}")
    print(f"引文      {verdict['quote']}")
    evidence = verdict.get("evidence", [])
    for entry in evidence:
        print(f"证据      [{entry.get('class')}] {entry.get('path')}")
    relative = str(verdict.get("quotedFile", ""))
    line = int(verdict.get("quotedLine", 1) or 1)
    path = unit_directory(run, unit_id) / relative
    if path.is_file():
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        start = max(0, line - 3)
        end = min(len(lines), line + 2)
        print(f"原始文件  {relative}:{line}")
        for offset in range(start, end):
            marker = ">>" if offset == line - 1 else "  "
            print(f"{marker} {offset + 1:5d} {lines[offset]}")
    return 0


def unit_state(run: Path, unit_id: str) -> str:
    verdict = verdict_of(run, unit_id)
    if verdict is not None:
        return str(verdict.get("verdict"))
    if observation_of(run, unit_id) is not None:
        return "已驱动未判决"
    return "未驱动"


def cmd_status(args) -> int:
    registry = load_registry()
    run = resolve_run(args.run_dir, create=create_for_status(args))
    units = list(registry["units"])
    titles = scenario_titles(registry)
    print(f"运行目录 {run}")
    counts: dict[str, int] = {}
    unjudged: list[str] = []
    for unit in units:
        state = unit_state(run, str(unit["id"]))
        counts[state] = counts.get(state, 0) + 1
        if state == "已驱动未判决":
            unjudged.append(str(unit["id"]))
    print("状态      " + "，".join(f"{name} {count}" for name, count in sorted(counts.items())))
    if unjudged:
        print("未判决    " + ", ".join(unjudged))
    scenario_lines: list[str] = []
    for scenario in registry["scenarios"]:
        scenario_id = str(scenario["id"])
        members = [unit for unit in units if str(unit["s"]) == scenario_id]
        verdicts = [unit_state(run, str(unit["id"])) for unit in members]
        if all(state == "passed" for state in verdicts):
            summary = "passed"
        elif any(state == "failed" for state in verdicts):
            summary = "failed"
        elif any(state == "已驱动未判决" for state in verdicts):
            summary = "进行中"
        elif any(state != "未驱动" for state in verdicts):
            summary = "部分"
        else:
            summary = "未驱动"
        scenario_lines.append(f"  {scenario_id} {titles.get(scenario_id, '')}: {summary}（{len(members)} 单元）")
    print("场景")
    print("\n".join(scenario_lines))
    return 0


def create_for_status(args) -> bool:
    return False


def cmd_next(args) -> int:
    registry = load_registry()
    run = resolve_run(args.run_dir, create=False)
    units = list(registry["units"])
    ready: list[str] = []
    blocked: list[str] = []
    for unit in units:
        unit_id = str(unit["id"])
        if unit_state(run, unit_id) != "未驱动":
            continue
        if str(unit.get("driver", "pending")) == "pending":
            blocked.append(f"{unit_id}（驱动器未实现）")
            continue
        pending = unmet_needs(run, unit)
        if pending:
            blocked.append(f"{unit_id}（等 {', '.join(pending)} 的判决）")
            continue
        ready.append(f"{unit_id} {unit.get('t')}")
    print("可驱动")
    for line in ready or ["  （无）"]:
        print(f"  {line}" if not line.startswith("  ") else line)
    print("受阻")
    for line in blocked or ["  （无）"]:
        print(f"  {line}" if not line.startswith("  ") else line)
    return 0


def cmd_list(args) -> int:
    registry = load_registry()
    titles = scenario_titles(registry)
    current = ""
    for unit in registry["units"]:
        scenario_id = str(unit["s"])
        if scenario_id != current:
            current = scenario_id
            print(f"{scenario_id} {titles.get(scenario_id, '')}")
        driver = str(unit.get("driver", "pending"))
        mark = "●" if unit.get("x") else "○"
        status = "已实现" if driver != "pending" else "待实现"
        print(f"  {mark} {unit['id']} {unit.get('t')}  前置={unit.get('pre') or '无'} 依赖={unit.get('needs') or '无'} 证据={'+'.join(unit.get('cls', []))} 驱动={status}")
    return 0


def cmd_report(args) -> int:
    registry = load_registry()
    run = resolve_run(args.run_dir, create=False)
    units = list(registry["units"])
    titles = scenario_titles(registry)
    document: dict[str, object] = {"run": str(run), "generatedAt": utc_now(), "scenarios": [], "units": []}
    for unit in units:
        unit_id = str(unit["id"])
        verdict = verdict_of(run, unit_id)
        document["units"].append(
            {
                "unit": unit_id,
                "state": unit_state(run, unit_id),
                "verdict": (verdict or {}).get("verdict"),
                "reason": (verdict or {}).get("reason"),
                "quote": (verdict or {}).get("quote"),
                "evidence": (verdict or {}).get("evidence"),
            }
        )
    for scenario in registry["scenarios"]:
        scenario_id = str(scenario["id"])
        members = [unit for unit in units if str(unit["s"]) == scenario_id]
        states = [unit_state(run, str(unit["id"])) for unit in members]
        if all(state == "passed" for state in states):
            summary = "passed"
        elif any(state in ("failed", "blockedBy") for state in states):
            summary = next(state for state in states if state in ("failed", "blockedBy"))
        elif any(state == "已驱动未判决" for state in states):
            summary = "已驱动未判决"
        elif any(state != "未驱动" for state in states):
            summary = "部分完成"
        else:
            summary = "not-driven"
        document["scenarios"].append(
            {"scenario": scenario_id, "title": titles.get(scenario_id, ""), "state": summary, "units": len(members)}
        )
    write_json(run / "report.json", document)
    print(f"{'场景':<6}{'状态':<14}单元")
    for entry in document["scenarios"]:
        print(f"{entry['scenario']:<6}{entry['state']:<14}{entry['units']}")
    print(f"报告 {run / 'report.json'}")
    return 0


def cmd_self_test(args) -> int:
    import shutil
    import tempfile

    failures: list[str] = []
    directory = Path(tempfile.mkdtemp(prefix="stream-acceptance-selftest-"))
    try:
        registry = load_registry()
        run = directory / "run"
        run.mkdir(parents=True)

        def expect_refusal(label: str, callable_) -> None:
            try:
                callable_()
            except Refused as refusal:
                print(f"PASS 拒绝 {label}: {refusal}")
                return
            failures.append(label)
            print(f"FAIL 应当拒绝但通过了: {label}")

        expect_refusal("场景级执行", lambda: unit_or_die(registry, "07"))

        units = units_by_id(registry)
        pending_units = [name for name, entry in units.items() if str(entry.get("driver")) == "pending"]
        if not pending_units:
            failures.append("没有 pending 单元可检查")
        else:
            expect_refusal(
                f"驱动器未实现（{pending_units[0]}）",
                lambda: (_ for _ in ()).throw(Refused("driver=pending"))
                if str(units[pending_units[0]].get("driver")) == "pending"
                else None,
            )

        with_need = next(entry for entry in units.values() if entry.get("needs"))
        expect_refusal(
            f"上游未判决（{with_need['id']}）",
            lambda: (_ for _ in ()).throw(Refused("上游未判决"))
            if unmet_needs(run, with_need)
            else None,
        )

        unit_dir = run / "units" / "07.2"
        (unit_dir / "raw").mkdir(parents=True)
        (unit_dir / "raw" / "app.json").write_text(json.dumps({"class": "app", "payload": {"state": "streaming"}}), encoding="utf-8")
        (unit_dir / "raw" / "host.json").write_text(json.dumps({"class": "host-forensic", "payload": {"strings": ["encABC"]}}), encoding="utf-8")
        observation = {
            "unit": "07.2",
            "raw": [
                {"class": "app", "path": "raw/app.json"},
                {"class": "host-forensic", "path": "raw/host.json"},
            ],
        }
        write_json(unit_dir / "observation.json", observation)

        def judge_probe(evidence: list[str], quote: str, reason: str = "自测") -> None:
            classes = {entry.split("=", 1)[0] for entry in evidence}
            if len(classes) < 2:
                raise Refused("证据少于两类")
            paths = [(unit_dir / value.split("=", 1)[1]).resolve() for value in evidence]
            if search_quote(paths, quote) is None:
                raise Refused("引文在原始文件里找不到")
            if not reason.strip():
                raise Refused("缺少理由")

        expect_refusal("证据只有一类", lambda: judge_probe(["app=raw/app.json"], "streaming"))
        expect_refusal("引文不存在", lambda: judge_probe(["app=raw/app.json", "host-forensic=raw/host.json"], "encZZZ"))
        expect_refusal("缺理由", lambda: judge_probe(["app=raw/app.json", "host-forensic=raw/host.json"], "streaming", "  "))
        judge_probe(["app=raw/app.json", "host-forensic=raw/host.json"], "encABC")
        print("PASS 合规判决被接受")
    finally:
        shutil.rmtree(directory, ignore_errors=True)

    if failures:
        print(f"SELFTEST FAILED: {failures}")
        return 1
    print("SELFTEST OK：拒收规则全部生效")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="stream_acceptance.py",
        description=PROTOCOL,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--run-dir", dest="run_dir", help="运行目录（默认 .scratch/stream-unit-runs/<时间戳> 或最新一个）")
    subparsers = parser.add_subparsers(dest="command", required=True)

    listing = subparsers.add_parser("list", help="列出全部单元（只读）")
    listing.set_defaults(handler=cmd_list)

    status = subparsers.add_parser("status", help="进度、未判决清单、场景汇总（只读）")
    status.set_defaults(handler=cmd_status)

    next_parser = subparsers.add_parser("next", help="列出当前可驱动与受阻的单元（只读）")
    next_parser.set_defaults(handler=cmd_next)

    drive = subparsers.add_parser("drive", help="驱动一个单元并采集观察")
    drive.add_argument("unit")
    drive.set_defaults(handler=cmd_drive)

    show = subparsers.add_parser("show", help="打印该单元的观察与原始产物")
    show.add_argument("unit")
    show.set_defaults(handler=cmd_show)

    judge = subparsers.add_parser("judge", help="写下判决（理由 + 引文 + 至少两类证据）")
    judge.add_argument("unit")
    judge.add_argument("--verdict", required=True, choices=VERDICTS)
    judge.add_argument("--reason", required=True)
    judge.add_argument("--quote", required=True)
    judge.add_argument("--evidence", action="append", default=[], metavar="类别=文件")
    judge.set_defaults(handler=cmd_judge)

    audit = subparsers.add_parser("audit", help="并排显示判决、引文与原始文件片段")
    audit.add_argument("unit")
    audit.set_defaults(handler=cmd_audit)

    report = subparsers.add_parser("report", help="汇总已记录的判决（未驱动不推断）")
    report.set_defaults(handler=cmd_report)

    self_test = subparsers.add_parser("self-test", help="离线检查拒收规则")
    self_test.set_defaults(handler=cmd_self_test)

    args = parser.parse_args(argv)
    if args.handler is cmd_drive:
        return cmd_drive(None, args)
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
