from __future__ import annotations

import argparse
import contextlib
import json
import sys
from pathlib import Path

import compile as compiler_module
import engine
import machine as machine_module
from loader import LoadRefusal, load_units
from model import TIER_ORDER
from report import (
    EXIT_CAPABILITY,
    EXIT_ENGINE,
    EXIT_OK,
    EXIT_REFUSED,
    EXIT_TERMINAL,
    EXIT_USAGE,
    diagnostics_payload,
    plan_payload,
    render_diagnostics,
    render_plan,
    render_report,
)


def repository_root(value: str | None) -> Path:
    if value:
        return Path(value).resolve()
    return Path(__file__).resolve().parents[2]


def evidence_root(root: Path) -> Path:
    return root / "TestEvidence" / "console"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="console", add_help=True)
    parser.add_argument("--root", default=None)
    parser.add_argument("--machine", default=None)
    parser.add_argument("--json", action="store_true", dest="as_json")
    commands = parser.add_subparsers(dest="command", required=True)

    plan = commands.add_parser("plan")
    plan_commands = plan.add_subparsers(dest="subcommand", required=True)
    for name in ("compile", "show", "check"):
        item = plan_commands.add_parser(name)
        if name != "check":
            item.add_argument("unit")
        item.add_argument("--tier", default=None if name == "check" else "e2e")
        item.add_argument("--all", action="store_true", dest="all_units")
        item.add_argument("--out", default=None)

    run = commands.add_parser("run")
    run.add_argument("unit")
    run.add_argument("--tier", default="e2e")
    run.add_argument("--timeout-scale", type=float, default=1.0, dest="timeout_scale")

    listing = commands.add_parser("list")
    listing.add_argument("--tier", default=None)
    listing.add_argument("--layer", type=int, default=None)

    commands.add_parser("doctor")

    daemon = commands.add_parser("daemon")
    daemon.add_argument("action", choices=("start", "stop", "status"))

    tier = commands.add_parser("tier")
    tier.add_argument("name", choices=("static", "build", "unit", "e2e"))
    tier.add_argument("--quick", action="store_true")
    tier.add_argument("--code-only", action="store_true", dest="code_only")
    tier.add_argument("--gate", action="store_true", dest="gate")
    tier.add_argument("--full", action="store_true", dest="full")
    tier.add_argument("--changed-since", default="", dest="changed_since")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(argv)
    root = repository_root(arguments.root)
    profile = machine_module.load(arguments.machine)
    try:
        return _dispatch(arguments, root, profile)
    except LoadRefusal as refusal:
        return _refuse(refusal, arguments.as_json)


def _dispatch(arguments, root, profile) -> int:
    if arguments.command == "doctor":
        return _doctor(profile, arguments.as_json)
    if arguments.command == "list":
        return _list(root, arguments, profile)
    if arguments.command == "plan":
        return _plan(root, arguments, profile)
    if arguments.command == "run":
        return _run(root, arguments, profile)
    if arguments.command == "daemon":
        return _daemon(root, arguments, profile)
    if arguments.command == "tier":
        return _tier(root, arguments, profile)
    return EXIT_USAGE


def _daemon(root: Path, arguments, profile) -> int:
    import daemon as daemon_module

    if arguments.action == "status":
        target = profile.target or ""
        answer = daemon_module.request(root, {"op": "ping"}, target, timeout=2)
        alive = answer.get("kind") == "result"
        payload = {
            "alive": alive,
            "target": target,
            "socket": str(daemon_module.socket_path(root, target)),
        }
        if arguments.as_json:
            print(json.dumps(payload, indent=1))
        else:
            print(f"daemon {'alive' if alive else 'not running'}")
        return EXIT_OK
    if arguments.action == "stop":
        daemon_module.request(root, {"op": "stop"}, profile.target or "", timeout=5)
        if not arguments.as_json:
            print("daemon stopped")
        return EXIT_OK
    if not profile.target:
        message = "no target device; set ENCHRON_TARGET_DEVICE or boot a simulator"
        if arguments.as_json:
            print(json.dumps({"ok": False, "message": message}, indent=1))
        else:
            print(message, file=sys.stderr)
        return EXIT_CAPABILITY
    started = daemon_module.ensure_running(root, profile.target)
    if arguments.as_json:
        print(json.dumps({"ok": started, "target": profile.target}, indent=1))
    else:
        print(f"daemon {'running' if started else 'failed to start'} on {profile.target}")
    return EXIT_OK if started else EXIT_ENGINE


STARTS_ON_DEMAND = frozenset({"daemon"})


def _tier(root: Path, arguments, profile) -> int:
    import static_tier

    if arguments.name == "static":
        payload = static_tier.run_static_tier(
            root,
            evidence_root(root),
            arguments.quick,
            arguments.code_only,
            getattr(arguments, "full", False),
            getattr(arguments, "changed_since", ""),
            getattr(arguments, "gate", False),
        )
        if arguments.as_json:
            print(json.dumps(payload, indent=1))
        else:
            print(static_tier.summarize(payload))
        return static_tier.static_exit(payload)
    required = compiler_module.TIER_CAPABILITIES[arguments.name]
    absent = sorted(required - profile.capabilities - STARTS_ON_DEMAND)
    if absent:
        message = f"tier {arguments.name} needs {', '.join(absent)}"
        if arguments.as_json:
            print(json.dumps({"ok": False, "tier": arguments.name, "missing": absent}, indent=1))
        else:
            print(message, file=sys.stderr)
        return EXIT_CAPABILITY
    import build_tier

    tier_evidence = evidence_root(root) / "tiers"
    if arguments.name == "build":
        payload = build_tier.run_build(root, profile.target, tier_evidence)
    elif arguments.name == "unit":
        payload = build_tier.run_unit(root, profile.target, tier_evidence)
    else:
        import types
        import loader as loader_module

        codes: list[tuple[str, int]] = []
        units = loader_module.load_units(root)
        if getattr(arguments, "quick", False):
            units = {
                name: unit for name, unit in units.items() if unit.pace == "fast"
            }
        for identifier in sorted(units):
            per_unit = types.SimpleNamespace(
                unit=identifier,
                tier="e2e",
                as_json=False,
                timeout_scale=1.0,
            )
            if arguments.as_json:
                with contextlib.redirect_stdout(sys.stderr):
                    codes.append((identifier, _run(root, per_unit, profile)))
            else:
                codes.append((identifier, _run(root, per_unit, profile)))
        failed = [name for name, code in codes if code != 0]
        if arguments.as_json:
            print(
                json.dumps(
                    {
                        "ok": bool(codes) and not failed,
                        "tier": "e2e",
                        "units": [
                            {"unit": name, "exitCode": code} for name, code in codes
                        ],
                    },
                    indent=1,
                )
            )
        else:
            print(f"e2e {len(codes) - len(failed)}/{len(codes)} unit(s) passed")
            for name in failed:
                print(f"  failed {name}", file=sys.stderr)
        return EXIT_OK if codes and not failed else EXIT_TERMINAL
    if arguments.as_json:
        print(json.dumps(payload, indent=1))
    else:
        print(build_tier.summarize(arguments.name, payload))
    return build_tier.exit_of(payload)


def _doctor(profile, as_json: bool) -> int:
    missing = {
        tier: sorted(compiler_module.TIER_CAPABILITIES[tier] - profile.capabilities)
        for tier in TIER_ORDER
        if not compiler_module.TIER_CAPABILITIES[tier] <= profile.capabilities
    }
    payload = {
        "capabilities": sorted(profile.capabilities),
        "target": profile.target,
        "tiers": [
            tier
            for tier in TIER_ORDER
            if compiler_module.TIER_CAPABILITIES[tier] <= profile.capabilities
        ],
        "missing": {tier: capabilities for tier, capabilities in missing.items()},
    }
    if as_json:
        print(json.dumps(payload, indent=1))
    else:
        print(f"capabilities {', '.join(payload['capabilities'])}")
        print(f"target {payload['target'] or 'none'}")
        print(f"tiers {', '.join(payload['tiers']) or 'none'}")
        for tier, capabilities in missing.items():
            print(f"missing {tier}: {', '.join(capabilities)}")
    return EXIT_OK


def _list(root: Path, arguments, profile) -> int:
    try:
        units = load_units(root)
    except LoadRefusal as refusal:
        return _refuse(refusal, arguments.as_json)
    rows = []
    for identifier, unit in sorted(units.items()):
        if arguments.layer is not None and unit.layer != arguments.layer:
            continue
        rows.append(
            {
                "unit": identifier,
                "layer": unit.layer,
                "requires": sorted(unit.requires),
                "role": unit.role,
            }
        )
    if arguments.as_json:
        print(json.dumps({"units": rows, "count": len(rows)}, indent=1))
    else:
        for row in rows:
            print(f"{row['unit']}  layer={row['layer']}  {', '.join(row['requires']) or 'none'}")
        print(f"{len(rows)} unit(s)")
    return EXIT_OK


def _plan(root: Path, arguments, profile) -> int:
    if arguments.subcommand == "check":
        findings = compiler_module.check_all(root, arguments.tier, profile)
        if arguments.as_json:
            print(json.dumps(diagnostics_payload(findings), indent=1))
        else:
            print(render_diagnostics(findings))
        return EXIT_OK if not findings else EXIT_REFUSED
    plan, errors, unit = compiler_module.compile_unit(
        root, arguments.unit, arguments.tier, profile
    )
    if plan is None:
        code = EXIT_REFUSED
        if any(error[0] == "C004" for error in errors):
            code = EXIT_CAPABILITY
        if not arguments.as_json:
            for error_code, message in errors:
                print(f"{error_code}  {arguments.unit}  {message}", file=sys.stderr)
        else:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "unit": arguments.unit,
                        "findings": [
                            {"code": code_name, "message": message}
                            for code_name, message in errors
                        ],
                    },
                    indent=1,
                )
            )
        return code
    if arguments.subcommand == "show":
        if arguments.as_json:
            print(json.dumps(plan_payload(plan), indent=1))
        else:
            print(render_plan(plan))
        return EXIT_OK
    target = Path(arguments.out) if arguments.out else evidence_root(root) / "plans"
    target.mkdir(parents=True, exist_ok=True)
    destination = target / (
        plan.unit.replace(":", "-").replace("/", "-") + ".json"
    )
    destination.write_text(json.dumps(plan_payload(plan), indent=1) + "\n", encoding="utf-8")
    if arguments.as_json:
        print(json.dumps({"ok": True, "plan": str(destination)}, indent=1))
    else:
        print(f"wrote {destination}")
    return EXIT_OK


def _run(root: Path, arguments, profile) -> int:
    plan, errors, unit = compiler_module.compile_unit(
        root, arguments.unit, arguments.tier, profile
    )
    if plan is None and any(error[0] in ("C004", "C015") for error in errors):
        import daemon as daemon_module
        import machine as machine_module

        target = profile.target or machine_module.probe().target
        if target and daemon_module.ensure_running(root, target):
            profile = machine_module.probe()
            plan, errors, unit = compiler_module.compile_unit(
                root, arguments.unit, arguments.tier, profile
            )
    if plan is None:
        return _refuse_many(arguments.unit, errors, arguments.as_json)
    report = engine.run_plan(
        plan, root, evidence_root(root), arguments.timeout_scale
    )
    if arguments.as_json:
        print(json.dumps(engine_report(report), indent=1))
    else:
        print(render_report(report))
    return report.exit_code


def engine_report(report):
    from report import report_payload

    return report_payload(report)


def _refuse(refusal: LoadRefusal, as_json: bool) -> int:
    return _refuse_many(
        refusal.source or "unknown",
        [(refusal.code, refusal.message)],
        as_json,
    )


def _refuse_many(unit: str, errors, as_json: bool) -> int:
    code = EXIT_REFUSED
    if any(error[0] == "C004" for error in errors):
        code = EXIT_CAPABILITY
    if as_json:
        print(
            json.dumps(
                {
                    "ok": False,
                    "unit": unit,
                    "findings": [
                        {"code": error_code, "message": message}
                        for error_code, message in errors
                    ],
                },
                indent=1,
            )
        )
    else:
        for error_code, message in errors:
            print(f"{error_code}  {unit}  {message}", file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
