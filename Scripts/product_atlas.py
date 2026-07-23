#!/usr/bin/env python3
"""Build and maintain the local, derived Enchron Product Atlas."""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "docs" / "atlas"
MODEL_PATH = ATLAS / "model.json"
BASELINE_PATH = ATLAS / "source-baseline.json"
TEMPLATE_PATH = ATLAS / "index.template.html"
CSS_PATH = ATLAS / "atlas.css"
JS_PATH = ATLAS / "atlas.js"
OUTPUT_PATH = ATLAS / "index.html"

PLACEHOLDERS = {
    "css": "/*__ATLAS_CSS__*/",
    "model": "/*__ATLAS_MODEL__*/",
    "js": "/*__ATLAS_JS__*/",
}


class AtlasError(Exception):
    pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AtlasError(f"无法读取 {path.relative_to(ROOT)}：{error}") from error


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def current_blob(path: Path) -> str:
    result = git("hash-object", "--", str(path.relative_to(ROOT)))
    return result.stdout.strip()


def source_maps(model: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], dict[str, Path]]:
    sources = {item["id"]: item for item in model.get("sources", [])}
    paths = {source_id: ROOT / item["path"] for source_id, item in sources.items()}
    return sources, paths


def rendered_bytes() -> bytes:
    model = read_json(MODEL_PATH)
    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    for name, placeholder in PLACEHOLDERS.items():
        count = template.count(placeholder)
        if count != 1:
            raise AtlasError(f"{TEMPLATE_PATH.relative_to(ROOT)} 中 {placeholder} 应恰好出现一次，实际为 {count}")
    model_text = json.dumps(model, ensure_ascii=False, separators=(",", ":")).replace("</script", "<\\/script")
    rendered = template.replace(PLACEHOLDERS["css"], CSS_PATH.read_text(encoding="utf-8").rstrip())
    rendered = rendered.replace(PLACEHOLDERS["model"], model_text)
    rendered = rendered.replace(PLACEHOLDERS["js"], JS_PATH.read_text(encoding="utf-8").rstrip())
    return (rendered.rstrip() + "\n").encode("utf-8")


def build(output: Path = OUTPUT_PATH) -> None:
    output.write_bytes(rendered_bytes())
    print(f"built {output.relative_to(ROOT)}")


def ids_unique(items: list[dict[str, Any]], label: str, errors: list[str]) -> set[str]:
    values = [item.get("id") for item in items]
    missing = sum(value is None for value in values)
    if missing:
        errors.append(f"{label} 有 {missing} 项缺少 id")
    duplicates = [value for value, count in Counter(values).items() if value is not None and count > 1]
    if duplicates:
        errors.append(f"{label} ID 重复：{', '.join(sorted(duplicates))}")
    return {value for value in values if isinstance(value, str)}


def heading_count(path: Path, heading: str) -> int:
    target = heading.strip()
    return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip() == target)


def condition_valid(condition: dict[str, Any], dimensions: dict[str, dict[str, Any]], errors: list[str], context: str) -> None:
    allowed_keys = {"dimensionId", "equals", "notEquals", "in"}
    unknown_keys = set(condition) - allowed_keys
    if unknown_keys:
        errors.append(f"{context} predicate 包含未知字段：{', '.join(sorted(unknown_keys))}")
    dimension_id = condition.get("dimensionId")
    if dimension_id not in dimensions:
        errors.append(f"{context} 引用未知状态轴 {dimension_id}")
        return
    operators = [key for key in ("equals", "notEquals", "in") if key in condition]
    if len(operators) != 1:
        errors.append(f"{context} predicate 必须且只能使用 equals、notEquals、in 之一")
        return
    values = {
        value if isinstance(value, str) else value.get("id")
        for value in dimensions[dimension_id].get("values", [])
    }
    operator = operators[0]
    if operator == "in":
        candidates = condition["in"]
        if not isinstance(candidates, list) or not candidates:
            errors.append(f"{context} 的 in 必须是非空数组")
            return
        unknown = [value for value in candidates if value not in values]
        if unknown:
            errors.append(f"{context} 引用 {dimension_id} 的未知值 {unknown}")
    elif condition[operator] not in values:
        errors.append(f"{context} 引用 {dimension_id} 的未知值 {condition[operator]}")


def patch_valid(patch: dict[str, Any], dimensions: dict[str, dict[str, Any]], errors: list[str], context: str) -> None:
    for dimension_id, value in patch.items():
        if dimension_id not in dimensions:
            errors.append(f"{context} patch 引用未知状态轴 {dimension_id}")
            continue
        value_id = value.get("value") if isinstance(value, dict) else value
        allowed = {
            item if isinstance(item, str) else item.get("id")
            for item in dimensions[dimension_id].get("values", [])
        }
        if value_id not in allowed:
            errors.append(f"{context} patch 使用 {dimension_id} 的未知值 {value_id}")


def constraint_matches(constraint: dict[str, Any], state: dict[str, Any]) -> bool:
    conditions = constraint.get("whenAll", [])
    if not conditions:
        return False
    for condition in conditions:
        dimension_id = condition.get("dimensionId")
        if dimension_id not in state:
            return False
        current = state.get(dimension_id)
        if "equals" in condition and current != condition["equals"]:
            return False
        if "notEquals" in condition and current == condition["notEquals"]:
            return False
        if "in" in condition and current not in condition["in"]:
            return False
    return True


def verify() -> None:
    model = read_json(MODEL_PATH)
    baseline = read_json(BASELINE_PATH)
    errors: list[str] = []

    if model.get("schemaVersion") != 1:
        errors.append("schemaVersion 必须严格等于 1")
    expected_vocabulary = {
        "decisionStatus": ["confirmed", "unresolved"],
        "implementation": ["observed", "partial", "notFound", "notAssessed"],
        "verification": ["verifiedCurrent", "historicalEvidence", "blocked", "notEvidenced"],
    }
    if model.get("statusVocabulary") != expected_vocabulary:
        errors.append("statusVocabulary 与 schemaVersion 1 的固定枚举不一致")

    sources = model.get("sources", [])
    owners = model.get("owners", [])
    state = model.get("stateRegistry", {})
    entities = state.get("entities", [])
    dimension_items = state.get("dimensions", [])
    invariants = state.get("invariants", [])
    constraints = state.get("constraints", [])
    actions = model.get("actionRegistry", [])
    scenes = model.get("projection", {}).get("scenes", [])
    surfaces = model.get("projection", {}).get("surfaces", [])

    source_ids = ids_unique(sources, "sources", errors)
    actor_ids = ids_unique(model.get("actorRegistry", []), "actors", errors)
    owner_ids = ids_unique(owners, "owners", errors)
    ids_unique(entities, "state entities", errors)
    dimension_ids = ids_unique(dimension_items, "state dimensions", errors)
    ids_unique(invariants, "invariants", errors)
    ids_unique(constraints, "constraints", errors)
    action_ids = ids_unique(actions, "actions", errors)
    scene_ids = ids_unique(scenes, "scenes", errors)
    surface_ids = ids_unique(surfaces, "surfaces", errors)

    dimensions = {item["id"]: item for item in dimension_items if "id" in item}
    required_dimension_owners = {
        "state.presentationTransition": ["playback-presentation"],
        "state.immersiveContent": ["playback-presentation"],
    }
    for dimension_id, expected_owners in required_dimension_owners.items():
        actual_owners = dimensions.get(dimension_id, {}).get("ownerIds")
        if actual_owners != expected_owners:
            errors.append(
                f"{dimension_id} ownerIds 必须严格等于 {expected_owners}，实际为 {actual_owners}"
            )
    surface_map = {item["id"]: item for item in surfaces if "id" in item}
    region_ids = {
        surface_id: {region.get("id") for region in surface.get("regions", [])}
        for surface_id, surface in surface_map.items()
    }

    for scene in scenes:
        for surface_id in scene.get("surfaceIds", []):
            if surface_id not in surface_ids:
                errors.append(f"scene {scene.get('id')} 引用未知 surface {surface_id}")
    scene_membership = Counter(
        surface_id
        for scene in scenes
        for surface_id in scene.get("surfaceIds", [])
    )
    for surface_id in surface_ids:
        count = scene_membership[surface_id]
        if count != 1:
            errors.append(f"surface {surface_id} 必须属于恰好一个 scene，实际为 {count}")

    refs_to_check: list[tuple[str, list[dict[str, Any]]]] = []
    for kind, items in (
        ("owner", owners),
        ("entity", entities),
        ("dimension", dimension_items),
        ("invariant", invariants),
        ("constraint", constraints),
        ("scene", scenes),
        ("surface", surfaces),
        ("action", actions),
    ):
        for item in items:
            refs = item.get("sourceRefs", [])
            if not refs:
                errors.append(f"{kind} {item.get('id')} 缺少 sourceRefs")
            refs_to_check.append((f"{kind} {item.get('id')}", refs))
            for owner_id in item.get("ownerIds", []):
                if owner_id not in owner_ids:
                    errors.append(f"{kind} {item.get('id')} 引用未知 owner {owner_id}")

    source_by_id, source_paths = source_maps(model)
    for source_id, path in source_paths.items():
        if not path.is_file():
            errors.append(f"source {source_id} 不存在：{path.relative_to(ROOT)}")

    heading_cache: dict[tuple[str, str], int] = {}
    for context, refs in refs_to_check:
        for ref in refs:
            source_id = ref.get("sourceId")
            if source_id not in source_ids:
                errors.append(f"{context} 引用未知 source {source_id}")
                continue
            heading = ref.get("heading")
            if heading and source_paths[source_id].is_file():
                cache_key = (source_id, heading)
                if cache_key not in heading_cache:
                    heading_cache[cache_key] = heading_count(source_paths[source_id], heading)
                count = heading_cache[cache_key]
                if count != 1:
                    errors.append(f"{context} 的锚点 {source_id}:{heading} 应恰好出现一次，实际为 {count}")

    for constraint in constraints:
        for condition in constraint.get("whenAll", []):
            condition_valid(condition, dimensions, errors, f"constraint {constraint.get('id')}")

    valid_decisions = set(model.get("statusVocabulary", {}).get("decisionStatus", ["confirmed", "unresolved"]))
    valid_implementations = set(model.get("statusVocabulary", {}).get("implementation", []))
    valid_verifications = set(model.get("statusVocabulary", {}).get("verification", []))
    allowed_grammars = {
        "causal-chain",
        "state-difference",
        "queue-sequence",
        "spatial-transition",
        "format-to-space-transition",
        "system-interruption",
    }
    for action in actions:
        context = f"action {action.get('id')}"
        if action.get("visualGrammar") not in allowed_grammars:
            errors.append(f"{context} visualGrammar 不在有限 renderer 集合中")
        grammar = action.get("visualGrammar")
        visual = action.get("visual")
        required_visual_fields = {
            "spatial-transition": {"fromSurface", "toSurface", "phases"},
            "format-to-space-transition": {"projectionOptions", "stereoOptions", "selected", "shape"},
            "system-interruption": {"lanes", "warmPhases", "coldPhases"},
        }
        if grammar in required_visual_fields:
            if not isinstance(visual, dict):
                errors.append(f"{context} 的 {grammar} 必须提供 visual")
            else:
                missing_fields = required_visual_fields[grammar] - set(visual)
                if missing_fields:
                    errors.append(
                        f"{context} 的 {grammar} visual 缺少字段："
                        f"{', '.join(sorted(missing_fields))}"
                    )
        placements = action.get("placements", [])
        if not placements:
            errors.append(f"{context} 没有 placement")
        for placement in placements:
            surface_id = placement.get("surfaceId")
            region_id = placement.get("regionId")
            if surface_id not in surface_ids:
                errors.append(f"{context} placement 引用未知 surface {surface_id}")
            elif region_id not in region_ids[surface_id]:
                errors.append(f"{context} placement 引用 {surface_id} 的未知 region {region_id}")
        if action.get("decisionStatus") not in valid_decisions:
            errors.append(f"{context} decisionStatus 无效")
        delivery = action.get("delivery", {})
        if valid_implementations and delivery.get("implementation") not in valid_implementations:
            errors.append(f"{context} implementation 状态无效")
        if valid_verifications and delivery.get("verification") not in valid_verifications:
            errors.append(f"{context} verification 状态无效")
        verification = delivery.get("verification")
        evidence_refs = action.get("evidenceRefs", [])
        if verification != "notEvidenced" and not evidence_refs:
            errors.append(f"{context} 的 {verification} 缺少 evidenceRefs")
        for evidence_index, evidence in enumerate(evidence_refs, 1):
            if set(evidence) != {"sourceId", "heading", "scope"}:
                errors.append(f"{context} evidenceRefs[{evidence_index}] 必须只包含 sourceId、heading、scope")
            source_id = evidence.get("sourceId")
            heading = evidence.get("heading")
            if source_id not in source_ids:
                errors.append(f"{context} evidenceRefs[{evidence_index}] 引用未知 source {source_id}")
            elif heading and source_paths[source_id].is_file():
                count = heading_count(source_paths[source_id], heading)
                if count != 1:
                    errors.append(
                        f"{context} evidenceRefs[{evidence_index}] 锚点 "
                        f"{source_id}:{heading} 应恰好出现一次，实际为 {count}"
                    )
            if not isinstance(evidence.get("scope"), str) or not evidence.get("scope", "").strip():
                errors.append(f"{context} evidenceRefs[{evidence_index}] 缺少具体 scope")
        for condition in action.get("availableWhen", []):
            condition_valid(condition, dimensions, errors, context)
        for demonstration in action.get("demonstrations", []):
            simulated = dict(demonstration.get("initialState", {}))
            patch_valid(simulated, dimensions, errors, f"{context}/{demonstration.get('id')}/initial")
            for step_index, step in enumerate(demonstration.get("steps", []), 1):
                if set(step) - {"label", "actorId", "patch"}:
                    errors.append(f"{context}/{demonstration.get('id')}/step {step_index} 包含未知字段")
                if step.get("actorId") not in actor_ids:
                    errors.append(f"{context}/{demonstration.get('id')}/step {step_index} 引用未知 actor {step.get('actorId')}")
                patch = step.get("patch", {})
                patch_valid(patch, dimensions, errors, f"{context}/{demonstration.get('id')}/step {step_index}")
                simulated.update(patch)
            violated = [item.get("id") for item in constraints if constraint_matches(item, simulated)]
            if violated:
                errors.append(f"{context}/{demonstration.get('id')} 最终讲解状态触发约束：{', '.join(violated)}")
            for branch_index, branch in enumerate(demonstration.get("branches", []), 1):
                if set(branch) - {"label", "result", "steps", "decisionStatus"}:
                    errors.append(f"{context}/branch {branch_index} 包含未知字段")
                branch_decision = branch.get("decisionStatus")
                if branch_decision is not None and branch_decision not in valid_decisions:
                    errors.append(f"{context}/branch {branch_index} decisionStatus 无效")
                branch_state = dict(demonstration.get("initialState", {}))
                for step_index, step in enumerate(branch.get("steps", []), 1):
                    if step.get("actorId") not in actor_ids:
                        errors.append(f"{context}/branch {branch_index}/step {step_index} 引用未知 actor {step.get('actorId')}")
                    patch = step.get("patch", {})
                    patch_valid(patch, dimensions, errors, f"{context}/branch {branch_index}/step {step_index}")
                    branch_state.update(patch)
                branch_violations = [
                    item.get("id")
                    for item in constraints
                    if constraint_matches(item, branch_state)
                ]
                if branch_violations:
                    errors.append(
                        f"{context}/branch {branch_index} 最终讲解状态触发约束："
                        f"{', '.join(branch_violations)}"
                    )

    baseline_ids = set(baseline.get("blobs", {}))
    if baseline_ids != source_ids:
        errors.append(
            "source-baseline 与 model sources 不一致："
            f"缺少 {sorted(source_ids - baseline_ids)}；多出 {sorted(baseline_ids - source_ids)}"
        )
    for source_id, path in source_paths.items():
        if path.is_file():
            actual = current_blob(path)
            expected = baseline.get("blobs", {}).get(source_id)
            if expected != actual:
                errors.append(f"source {source_id} 已变化：baseline {expected or 'missing'}，current {actual}")

    try:
        expected_output = rendered_bytes()
        if not OUTPUT_PATH.is_file():
            errors.append("docs/atlas/index.html 尚未生成")
        elif OUTPUT_PATH.read_bytes() != expected_output:
            errors.append("docs/atlas/index.html 不是当前输入的确定性 build 结果")
        with tempfile.TemporaryDirectory(prefix="enchon-atlas-") as directory:
            first = Path(directory) / "first.html"
            second = Path(directory) / "second.html"
            first.write_bytes(expected_output)
            second.write_bytes(rendered_bytes())
            if first.read_bytes() != second.read_bytes():
                errors.append("连续两次 build 结果不同")
    except (OSError, AtlasError) as error:
        errors.append(str(error))

    if errors:
        print("verification failed:")
        for error in errors:
            print(f"  - {error}")
        raise AtlasError(f"{len(errors)} 个机械验证错误")
    print(
        "verified "
        f"{len(actions)} actions · {len(dimension_items)} dimensions · "
        f"{len(invariants)} invariants · {len(surfaces)} surfaces · {len(sources)} sources"
    )


def reverse_source_refs(model: dict[str, Any]) -> dict[str, list[str]]:
    affected: dict[str, list[str]] = defaultdict(list)
    state = model.get("stateRegistry", {})
    collections = [
        ("owner", model.get("owners", [])),
        ("entity", state.get("entities", [])),
        ("dimension", state.get("dimensions", [])),
        ("invariant", state.get("invariants", [])),
        ("constraint", state.get("constraints", [])),
        ("scene", model.get("projection", {}).get("scenes", [])),
        ("surface", model.get("projection", {}).get("surfaces", [])),
        ("action", model.get("actionRegistry", [])),
    ]
    for kind, items in collections:
        for item in items:
            for ref in item.get("sourceRefs", []):
                affected[ref.get("sourceId")].append(f"{kind}:{item.get('id')}")
    return affected


def status() -> int:
    model = read_json(MODEL_PATH)
    baseline = read_json(BASELINE_PATH)
    _, paths = source_maps(model)
    affected = reverse_source_refs(model)
    changed = 0
    for source_id, path in paths.items():
        expected = baseline.get("blobs", {}).get(source_id)
        actual = current_blob(path) if path.is_file() else None
        marker = "unchanged" if actual == expected else "changed"
        print(f"{source_id:24} {marker}")
        if marker == "changed":
            changed += 1
            for node in affected.get(source_id, [])[:12]:
                print(f"  - {node}")
            remaining = len(affected.get(source_id, [])) - 12
            if remaining > 0:
                print(f"  - … and {remaining} more")
    print(f"{changed} changed source(s)")
    return 1 if changed else 0


def baseline_text(blob: str) -> str | None:
    result = git("cat-file", "-p", blob, check=False)
    if result.returncode != 0:
        return None
    return result.stdout


def diff_source(source_id: str) -> int:
    model = read_json(MODEL_PATH)
    baseline = read_json(BASELINE_PATH)
    _, paths = source_maps(model)
    if source_id not in paths:
        raise AtlasError(f"未知 source id：{source_id}")
    path = paths[source_id]
    blob = baseline.get("blobs", {}).get(source_id)
    if not blob:
        raise AtlasError(f"{source_id} 没有 baseline")
    old = baseline_text(blob)
    if old is None:
        print(
            f"baseline blob {blob} 尚不可由当前 Git 对象库读取。\n"
            "先在 Git 历史中提交接受该 baseline 的 Atlas 版本，之后 diff 才能还原旧内容。"
        )
        return 2
    current = path.read_text(encoding="utf-8")
    output = difflib.unified_diff(
        old.splitlines(keepends=True),
        current.splitlines(keepends=True),
        fromfile=f"{source_id}@{blob[:12]}",
        tofile=str(path.relative_to(ROOT)),
    )
    sys.stdout.writelines(output)
    return 0


def accept(source_id: str) -> None:
    model = read_json(MODEL_PATH)
    baseline = read_json(BASELINE_PATH)
    _, paths = source_maps(model)
    if source_id not in paths:
        raise AtlasError(f"未知 source id：{source_id}")
    path = paths[source_id]
    blob = current_blob(path)
    baseline.setdefault("blobs", {})[source_id] = blob
    write_json(BASELINE_PATH, baseline)
    reachable = git("cat-file", "-e", blob, check=False).returncode == 0
    print(f"accepted {source_id} {blob}")
    if not reachable:
        print("note: 该内容尚未出现在可读取的 Git object 中；提交后历史 diff 才可用。")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("build", help="确定性生成 docs/atlas/index.html")
    subparsers.add_parser("verify", help="验证 Registry、来源、覆盖与确定性")
    subparsers.add_parser("status", help="比较一手来源与已审阅 blob baseline")
    diff_parser = subparsers.add_parser("diff", help="显示某一来源从 baseline 到工作区的 diff")
    diff_parser.add_argument("source_id")
    accept_parser = subparsers.add_parser("accept", help="审阅后接受某一来源的当前 blob")
    accept_parser.add_argument("source_id")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "build":
            build()
        elif args.command == "verify":
            verify()
        elif args.command == "status":
            return status()
        elif args.command == "diff":
            return diff_source(args.source_id)
        elif args.command == "accept":
            accept(args.source_id)
        return 0
    except AtlasError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
