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
import report as report_module
from report import (
    EXIT_CAPABILITY,
    EXIT_ENGINE,
    EXIT_KNOWN,
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
    run.add_argument("--case", default="")
    run.add_argument("--timeout-scale", type=float, default=1.0, dest="timeout_scale")
    run.add_argument("--reuse", action="store_true")
    run.add_argument("--assume", action="append", default=[], dest="assume")
    run.add_argument("--force", action="store_true")

    inspect = commands.add_parser("inspect")
    inspect.add_argument("unit")
    inspect.add_argument("--as-json", action="store_true")
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
    tier.add_argument("--changed-staged", action="store_true", dest="changed_staged")
    tier.add_argument("--changed-list", default="", dest="changed_list")
    tier.add_argument(
        "--event", default="", choices=("", "commit", "push", "pr", "merge"),
        dest="event",
    )
    tier.add_argument("--remote-oid", default="", dest="remote_oid")
    tier.add_argument("--base-ref", default="main", dest="base_ref")
    tier.add_argument("--local-oid", default="HEAD", dest="local_oid")
    tier.add_argument("--force", action="store_true")

    merge = commands.add_parser("merge")
    merge.add_argument("action", choices=("check",))

    op = commands.add_parser("op")
    op.add_argument("verb")
    op.add_argument("--args", default="{}")
    op.add_argument("--session", default="")
    op.add_argument("--timeout-scale", type=float, default=1.0, dest="timeout_scale")

    replay = commands.add_parser("replay")
    replay.add_argument("session")
    replay.add_argument("--timeout-scale", type=float, default=1.0, dest="timeout_scale")

    unit = commands.add_parser("unit")
    unit_commands = unit.add_subparsers(dest="subcommand", required=True)
    scaffold = unit_commands.add_parser("scaffold")
    scaffold.add_argument("session")
    scaffold.add_argument("--out", default="")
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
    if arguments.command == "inspect":
        import explain as explain_module

        payload = explain_module.report(root, arguments.unit)
        print(
            json.dumps(payload, indent=1)
            if arguments.as_json
            else explain_module.render(payload)
        )
        return EXIT_OK
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
    if arguments.command == "merge":
        return _merge(root, arguments, profile)
    if arguments.command == "op":
        return _op(root, arguments, profile)
    if arguments.command == "replay":
        return _replay(root, arguments, profile)
    if arguments.command == "unit":
        return _unit(root, arguments, profile)
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
        if not daemon_module.wait_for_exit(root, profile.target or "", 6.0):
            daemon_module.force_stop(root, profile.target or "")
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


def _op(root: Path, arguments, profile) -> int:
    import ops

    try:
        args = ops.parse_arguments(arguments.args)
        result = ops.run_operation(
            root,
            profile,
            arguments.verb,
            args,
            session=arguments.session,
            timeout_scale=arguments.timeout_scale,
        )
    except ops.OperationRefusal as refusal:
        if arguments.as_json:
            print(json.dumps({"ok": False, "message": str(refusal)}, indent=1))
        else:
            print(f"refused: {refusal}", file=sys.stderr)
        return EXIT_USAGE
    if arguments.as_json:
        print(json.dumps(result, indent=1))
    else:
        print(ops.render_operation(result))
    return EXIT_OK if result["ok"] else EXIT_TERMINAL


def _replay(root: Path, arguments, profile) -> int:
    import ops

    try:
        summary = ops.replay_session(
            root, profile, arguments.session, arguments.timeout_scale
        )
    except ops.OperationRefusal as refusal:
        if arguments.as_json:
            print(json.dumps({"ok": False, "message": str(refusal)}, indent=1))
        else:
            print(f"refused: {refusal}", file=sys.stderr)
        return EXIT_USAGE
    if arguments.as_json:
        print(json.dumps(summary, indent=1))
    else:
        print(ops.render_replay(summary))
    return EXIT_OK if not summary["mismatched"] else EXIT_TERMINAL


def _unit(root: Path, arguments, profile) -> int:
    import ops

    try:
        summary = ops.scaffold_unit(root, arguments.session, arguments.out)
    except ops.OperationRefusal as refusal:
        if arguments.as_json:
            print(json.dumps({"ok": False, "message": str(refusal)}, indent=1))
        else:
            print(f"refused: {refusal}", file=sys.stderr)
        return EXIT_USAGE
    if arguments.as_json:
        print(json.dumps(summary, indent=1))
    else:
        print(ops.render_scaffold(summary))
    return EXIT_OK


def _merge(root: Path, arguments, profile) -> int:
    import merge_gate

    exit_code, payload = merge_gate.run_gate(
        root, profile.target, evidence_root(root)
    )
    if arguments.as_json:
        print(json.dumps(payload, indent=1))
    return exit_code


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
            getattr(arguments, "changed_staged", False),
            getattr(arguments, "changed_list", ""),
            getattr(arguments, "event", ""),
            getattr(arguments, "remote_oid", ""),
            getattr(arguments, "base_ref", "main"),
            getattr(arguments, "local_oid", "HEAD"),
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
        elif not getattr(arguments, "full", False):
            units = {
                name: unit
                for name, unit in units.items()
                if unit.pace not in {"catalog", "scenario"}
            }
        import daemon as daemon_module
        import reuse as reuse_module

        def recover_session() -> None:
            daemon_module.ensure_running(root, profile.target)
            daemon_module.request(
                root,
                {"op": "restart", "lane": "simulator"},
                profile.target,
                timeout=300,
            )

        current_product = reuse_module.product_digest(root)
        reuse_enabled = not getattr(arguments, "force", False)
        reused: list[str] = []
        for identifier in sorted(units):
            per_unit = types.SimpleNamespace(
                unit=identifier,
                tier="e2e",
                as_json=False,
                timeout_scale=1.0,
                reuse=False,
                assume=[],
                force=False,
            )
            if reuse_enabled:
                plan, _, _ = compiler_module.compile_unit(
                    root, identifier, "e2e", profile
                )
                if plan is not None and reuse_module.reusable_report(
                    evidence_root(root), identifier, plan.digest, current_product
                ):
                    reused.append(identifier)
                    codes.append((identifier, EXIT_OK))
                    continue
            if arguments.as_json:
                with contextlib.redirect_stdout(sys.stderr):
                    code = _run(root, per_unit, profile)
            else:
                code = _run(root, per_unit, profile)
            codes.append((identifier, code))
            if code not in (0, EXIT_KNOWN):
                if not arguments.as_json:
                    print(f"  recover {identifier}: restarting the session", file=sys.stderr)
                try:
                    recover_session()
                except OSError as error:
                    print(f"  recovery failed: {error}", file=sys.stderr)
        known = [
            name for name, code in codes if code == EXIT_KNOWN
        ]
        failed = [
            name
            for name, code in codes
            if code not in (0, EXIT_KNOWN)
        ]
        if arguments.as_json:
            print(
                json.dumps(
                    {
                        "ok": bool(codes) and not failed,
                        "tier": "e2e",
                        "reused": reused,
                        "units": [
                            {"unit": name, "exitCode": code} for name, code in codes
                        ],
                    },
                    indent=1,
                )
            )
        else:
            print(
                f"e2e {len(codes) - len(failed)}/{len(codes)} unit(s) passed"
                f" (reused {len(reused)}, ran {len(codes) - len(reused)})"
            )
            for name in known:
                print(f"  known  {name}")
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
        "physical": profile.physical,
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
        print(f"physical {payload['physical'] or 'none'}")
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
                "cases": [case["key"] for case in unit.cases],
            }
        )
    if arguments.as_json:
        print(json.dumps({"units": rows, "count": len(rows)}, indent=1))
    else:
        for row in rows:
            cases = f"  cases={len(row['cases'])}" if row["cases"] else ""
            print(
                f"{row['unit']}  layer={row['layer']}  "
                f"{', '.join(row['requires']) or 'none'}{cases}"
            )
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
    case_key = str(getattr(arguments, "case", ""))
    if case_key:
        subset, refusal = compiler_module.case_plan(plan, unit, case_key)
        if subset is None:
            print(refusal, file=sys.stderr)
            return EXIT_USAGE
        plan = subset
    import reuse as reuse_module

    current_product = reuse_module.product_digest(root)
    reuse_flag = bool(getattr(arguments, "reuse", False)) and not bool(
        getattr(arguments, "force", False)
    )
    if reuse_flag:
        matched = reuse_module.reusable_report(
            evidence_root(root), plan.unit, plan.digest, current_product
        )
        if matched is not None:
            if arguments.as_json:
                print(json.dumps({"unit": plan.unit, "verdict": "reused",
                                  "evidenceDirectory": matched["evidenceDirectory"]}, indent=1))
            else:
                print(f"reused  {plan.unit}  {matched['evidenceDirectory']}")
            return EXIT_OK
    declared = {reuse_module.precondition_key(pre) for pre in plan.preconditions}
    requested = set()
    for item in getattr(arguments, "assume", []) or []:
        requested.update(part for part in item.split(",") if part)
    unknown = reuse_module.unknown_assumptions(plan.preconditions, requested)
    if unknown:
        print(
            f"前置未声明：{', '.join(unknown)}；本单元声明的是 "
            f"{', '.join(sorted(declared)) or '无'}",
            file=sys.stderr,
        )
        return EXIT_USAGE
    if requested and not reuse_module.passing_evidence(
        evidence_root(root), plan.unit, plan.digest
    ):
        print(
            "假定前置需要同一单元在当前计划下有一次通过记录。",
            file=sys.stderr,
        )
        return EXIT_USAGE
    assumed = requested
    report = engine.run_plan(
        plan, root, evidence_root(root), arguments.timeout_scale, assumed
    )
    if arguments.as_json:
        print(json.dumps(engine_report(report), indent=1))
    else:
        print(render_report(report))
        summary = report_module.failure_summary(report, plan)
        if summary:
            print(summary)
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
