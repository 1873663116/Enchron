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
    projection = model.get("projection", {})
    scenes = projection.get("scenes", [])
    surfaces = projection.get("surfaces", [])
    structure_map = projection.get("structureMap")
    state_landscape = projection.get("stateLandscape")

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

    structure_context: dict[str, Any] = {}
    structure_nodes: list[dict[str, Any]] = []
    structure_relations: list[dict[str, Any]] = []
    if not isinstance(structure_map, dict):
        errors.append("projection.structureMap 必须存在且为对象")
    else:
        structure_context = structure_map.get("systemContext", {})
        structure_nodes = structure_map.get("nodes", [])
        structure_relations = structure_map.get("relations", [])
        if not isinstance(structure_context, dict) or not structure_context:
            errors.append("projection.structureMap.systemContext 必须是非空对象")
            structure_context = {}
        if not isinstance(structure_nodes, list) or not structure_nodes:
            errors.append("projection.structureMap.nodes 必须是非空数组")
            structure_nodes = []
        if not isinstance(structure_relations, list) or not structure_relations:
            errors.append("projection.structureMap.relations 必须是非空数组")
            structure_relations = []

    structure_node_ids = ids_unique(structure_nodes, "structure nodes", errors)
    structure_relation_ids = ids_unique(structure_relations, "structure relations", errors)
    allowed_structure_node_roles = {
        "main", "volume", "immersive", "environment-port", "playback-port", "controls"
    }
    allowed_structure_relation_roles = {
        "presentation", "environment", "controls", "session"
    }
    node_roles = [item.get("role") for item in structure_nodes]
    relation_roles = [item.get("role") for item in structure_relations]
    node_by_role = {
        item.get("role"): item for item in structure_nodes if item.get("role")
    }
    if set(node_roles) != allowed_structure_node_roles or len(node_roles) != len(set(node_roles)):
        errors.append(
            "structure nodes 必须为每个有限 renderer role 提供且只提供一个节点"
        )
    if (
        set(relation_roles) != allowed_structure_relation_roles
        or len(relation_roles) != len(set(relation_roles))
    ):
        errors.append(
            "structure relations 必须为每个有限 renderer role 提供且只提供一条关系"
        )
    structure_ids = [
        structure_context.get("id"),
        *[item.get("id") for item in structure_nodes],
        *[item.get("id") for item in structure_relations],
    ]
    structure_ids = [item for item in structure_ids if item]
    duplicate_structure_ids = [
        item_id for item_id, count in Counter(structure_ids).items() if count > 1
    ]
    if duplicate_structure_ids:
        errors.append(
            "structureMap 的 systemContext、nodes、relations ID 必须全局唯一："
            f"{sorted(duplicate_structure_ids)}"
        )
    if structure_context.get("sceneId") != "scene.system":
        errors.append("structureMap.systemContext.sceneId 必须严格等于 scene.system")

    required_structure_text = {"id", "label", "kind", "responsibility"}
    for item in [structure_context, *structure_nodes]:
        context = f"structure node {item.get('id')}"
        missing = required_structure_text - set(item)
        if missing:
            errors.append(f"{context} 缺少字段：{', '.join(sorted(missing))}")
        for field in required_structure_text:
            if field in item and (
                not isinstance(item.get(field), str) or not item.get(field, "").strip()
            ):
                errors.append(f"{context} 的 {field} 必须是非空文本")
        scene_id = item.get("sceneId")
        surface_id = item.get("surfaceId")
        if scene_id is not None and scene_id not in scene_ids:
            errors.append(f"{context} 引用未知 scene {scene_id}")
        if surface_id is not None and surface_id not in surface_ids:
            errors.append(f"{context} 引用未知 surface {surface_id}")
        parent_node_id = item.get("parentNodeId")
        if parent_node_id is not None and parent_node_id not in structure_node_ids:
            errors.append(f"{context} 引用未知 parent node {parent_node_id}")
        if item is not structure_context and not scene_id and not surface_id:
            errors.append(f"{context} 必须引用 sceneId 或 surfaceId")
        if item is not structure_context and item.get("role") not in allowed_structure_node_roles:
            errors.append(f"{context} role 不在有限 structure renderer 集合中")
        if item is structure_context:
            continue
        related_actions = item.get("relatedActions")
        if not isinstance(related_actions, dict) or len(related_actions) != 1:
            errors.append(f"{context} relatedActions 必须只声明一种稳定查询")
            continue
        query_kind, query_value = next(iter(related_actions.items()))
        if query_kind == "bySceneId":
            if query_value not in scene_ids:
                errors.append(f"{context} relatedActions 引用未知 scene {query_value}")
            if query_value != scene_id:
                errors.append(f"{context} relatedActions.bySceneId 必须等于节点 sceneId")
        elif query_kind == "bySurfaceId":
            if query_value not in surface_ids:
                errors.append(f"{context} relatedActions 引用未知 surface {query_value}")
            if query_value != surface_id:
                errors.append(f"{context} relatedActions.bySurfaceId 必须等于节点 surfaceId")
        elif query_kind == "actionIds":
            if item.get("role") not in {"environment-port", "playback-port"}:
                errors.append(f"{context} 只有 Immersive 内策展端口可显式声明 actionIds")
            if not isinstance(query_value, list):
                errors.append(f"{context} relatedActions.actionIds 必须是数组")
                continue
            duplicate_actions = [
                action_id
                for action_id, count in Counter(query_value).items()
                if count > 1
            ]
            if duplicate_actions:
                errors.append(f"{context} relatedActions.actionIds 重复：{sorted(duplicate_actions)}")
            for action_id in query_value:
                if action_id not in action_ids:
                    errors.append(f"{context} 引用未知 action {action_id}")
        else:
            errors.append(f"{context} relatedActions 使用未知查询 {query_kind}")

    node_binding_contract = {
        "main": ("scene.mainWindow", None, None),
        "volume": ("scene.environmentVolume", None, None),
        "immersive": ("scene.immersiveSpace", None, None),
        "environment-port": (
            None, "surface.enchronImmersiveSpace", "structure.immersiveSpace"
        ),
        "playback-port": (
            None, "surface.enchronImmersiveSpace", "structure.immersiveSpace"
        ),
        "controls": ("scene.playerControls", None, None),
    }
    for role, (expected_scene, expected_surface, expected_parent) in node_binding_contract.items():
        node = node_by_role.get(role, {})
        actual = (
            node.get("sceneId"), node.get("surfaceId"), node.get("parentNodeId")
        )
        expected = (expected_scene, expected_surface, expected_parent)
        if actual != expected:
            errors.append(
                f"structure role {role} 的 scene/surface/parent 必须严格等于 {expected}，"
                f"实际为 {actual}"
            )

    structure_node_by_id = {
        item.get("id"): item for item in structure_nodes if item.get("id")
    }
    for node in structure_nodes:
        parent_id = node.get("parentNodeId")
        if not parent_id:
            continue
        parent = structure_node_by_id.get(parent_id, {})
        if parent.get("parentNodeId"):
            errors.append(f"structure node {node.get('id')} 的 parent 深度不得超过一层")
        if parent_id == node.get("id"):
            errors.append(f"structure node {node.get('id')} 不得以自身为 parent")

    required_relation_fields = {
        "id", "label", "kind", "role", "fromNodeId", "toNodeId"
    }
    for relation in structure_relations:
        context = f"structure relation {relation.get('id')}"
        missing = required_relation_fields - set(relation)
        if missing:
            errors.append(f"{context} 缺少字段：{', '.join(sorted(missing))}")
        for field in required_relation_fields:
            if field in relation and (
                not isinstance(relation.get(field), str)
                or not relation.get(field, "").strip()
            ):
                errors.append(f"{context} 的 {field} 必须是非空文本")
        from_node_id = relation.get("fromNodeId")
        to_node_id = relation.get("toNodeId")
        if from_node_id not in structure_node_ids:
            errors.append(f"{context} 的 fromNodeId 引用未知 node {from_node_id}")
        if to_node_id not in structure_node_ids:
            errors.append(f"{context} 的 toNodeId 引用未知 node {to_node_id}")
        if from_node_id == to_node_id:
            errors.append(f"{context} 的 fromNodeId 与 toNodeId 不得相同")
        if relation.get("role") not in allowed_structure_relation_roles:
            errors.append(f"{context} role 不在有限 structure renderer 集合中")

    relation_role_contract = {
        "presentation": ("main", "playback-port"),
        "environment": ("volume", "environment-port"),
        "controls": ("controls", "playback-port"),
        "session": ("main", "playback-port"),
    }
    node_role_by_id = {
        item.get("id"): item.get("role") for item in structure_nodes
    }
    for relation in structure_relations:
        expected = relation_role_contract.get(relation.get("role"))
        actual = (
            node_role_by_id.get(relation.get("fromNodeId")),
            node_role_by_id.get(relation.get("toNodeId")),
        )
        if expected and actual != expected:
            errors.append(
                f"structure relation role {relation.get('role')} 的 from/to role "
                f"必须严格等于 {expected}，实际为 {actual}"
            )

    dimensions = {item["id"]: item for item in dimension_items if "id" in item}
    invariant_ids = {item.get("id") for item in invariants if item.get("id")}
    constraint_ids = {item.get("id") for item in constraints if item.get("id")}

    landscape_questions: list[dict[str, Any]] = []
    landscape_fields: list[dict[str, Any]] = []
    landscape_snapshots: list[dict[str, Any]] = []
    landscape_branches: list[dict[str, Any]] = []
    landscape_shared: list[dict[str, Any]] = []
    landscape_reference: dict[str, Any] = {}
    if not isinstance(state_landscape, dict):
        errors.append("projection.stateLandscape 必须存在且为对象")
    else:
        landscape_fields = state_landscape.get("fields", [])
        landscape_questions = state_landscape.get("questions", [])
        landscape_snapshots = state_landscape.get("snapshots", [])
        landscape_branches = state_landscape.get("branches", [])
        landscape_shared = state_landscape.get("sharedScopes", [])
        landscape_reference = state_landscape.get("reference", {})
        for key, value in (
            ("fields", landscape_fields),
            ("questions", landscape_questions),
            ("snapshots", landscape_snapshots),
            ("branches", landscape_branches),
            ("sharedScopes", landscape_shared),
        ):
            if not isinstance(value, list) or not value:
                errors.append(f"projection.stateLandscape.{key} 必须是非空数组")
        if not isinstance(landscape_reference, dict) or not landscape_reference:
            errors.append("projection.stateLandscape.reference 必须是非空对象")
            landscape_reference = {}

    landscape_question_ids = ids_unique(
        landscape_questions, "state landscape questions", errors
    )
    landscape_field_ids = ids_unique(
        landscape_fields, "state landscape fields", errors
    )
    landscape_snapshot_ids = ids_unique(
        landscape_snapshots, "state landscape snapshots", errors
    )
    ids_unique(landscape_branches, "state landscape branches", errors)
    ids_unique(landscape_shared, "state landscape shared scopes", errors)
    expected_question_ids = {
        "question.picture",
        "question.playback",
        "question.surroundings",
        "question.actions",
    }
    if landscape_question_ids != expected_question_ids:
        errors.append("stateLandscape 必须严格提供四个自然问题")
    expected_snapshot_ids = {
        "snapshot.mediaLibrary",
        "snapshot.environmentOnly",
        "snapshot.windowPlayback",
        "snapshot.dockedPlayback",
        "snapshot.panoramaPlayback",
    }
    if landscape_snapshot_ids != expected_snapshot_ids:
        errors.append("stateLandscape 必须严格提供五个稳定产品快照")
    expected_field_ids = {"field.noSession", "field.activeSession"}
    if landscape_field_ids != expected_field_ids:
        errors.append("stateLandscape 必须严格提供无 Session 与活动 Session 两个无方向场域")
    field_snapshot_membership: Counter[str] = Counter()
    for field in landscape_fields:
        context = f"state landscape field {field.get('id')}"
        if not isinstance(field.get("label"), str) or not field.get("label", "").strip():
            errors.append(f"{context} 缺少非空 label")
        if not isinstance(field.get("summary"), str) or not field.get("summary", "").strip():
            errors.append(f"{context} 缺少非空 summary")
        snapshot_ids = field.get("snapshotIds")
        if not isinstance(snapshot_ids, list) or not snapshot_ids:
            errors.append(f"{context} snapshotIds 必须是非空数组")
            continue
        for snapshot_id in snapshot_ids:
            if snapshot_id not in landscape_snapshot_ids:
                errors.append(f"{context} 引用未知 snapshot {snapshot_id}")
            field_snapshot_membership[snapshot_id] += 1
    if field_snapshot_membership != Counter({snapshot_id: 1 for snapshot_id in landscape_snapshot_ids}):
        errors.append("stateLandscape 两个场域必须各自且完整地登记五个 snapshot")

    valid_landscape_branches = {
        "decision",
        "failure",
        "temporary",
        "stable-variation",
        "terminal",
        "system-interruption",
    }
    valid_landmark_shapes = {"window", "environment", "docked", "panorama"}
    landscape_coverage: set[str] = set()

    def validate_landscape_refs(
        item: dict[str, Any], context: str, require_applicability: bool = False
    ) -> None:
        if not isinstance(item.get("label"), str) or not item.get("label", "").strip():
            errors.append(f"{context} 缺少非空 label")
        if not isinstance(item.get("summary"), str) or not item.get("summary", "").strip():
            errors.append(f"{context} 缺少非空 summary")
        applicable = item.get("applicableSnapshotIds")
        if require_applicability:
            if not isinstance(applicable, list) or not applicable:
                errors.append(f"{context} applicableSnapshotIds 必须是非空数组")
            else:
                if len(applicable) != len(set(applicable)):
                    errors.append(f"{context} applicableSnapshotIds 不得重复")
                for snapshot_id in applicable:
                    if snapshot_id not in landscape_snapshot_ids:
                        errors.append(f"{context} 引用未知 snapshot {snapshot_id}")
        for invariant_id in item.get("invariantIds", []):
            if invariant_id not in invariant_ids:
                errors.append(f"{context} 引用未知 invariant {invariant_id}")
        for constraint_id in item.get("constraintIds", []):
            if constraint_id not in constraint_ids:
                errors.append(f"{context} 引用未知 constraint {constraint_id}")

    for question in landscape_questions:
        context = f"state landscape question {question.get('id')}"
        if not isinstance(question.get("label"), str) or not question.get("label", "").strip():
            errors.append(f"{context} 缺少非空 label")

    for snapshot in landscape_snapshots:
        context = f"state landscape snapshot {snapshot.get('id')}"
        validate_landscape_refs(snapshot, context)
        snapshot_state = snapshot.get("state")
        if not isinstance(snapshot_state, dict) or not snapshot_state:
            errors.append(f"{context} state 必须是非空对象")
        else:
            patch_valid(snapshot_state, dimensions, errors, context)
            landscape_coverage.update(snapshot_state)
        landmark = snapshot.get("landmark")
        if not isinstance(landmark, dict) or set(landmark) != {"x", "y", "shape"}:
            errors.append(f"{context} landmark 必须只包含 x、y、shape")
        else:
            if (
                not isinstance(landmark.get("x"), (int, float))
                or not 0 <= landmark["x"] <= 100
                or not isinstance(landmark.get("y"), (int, float))
                or not 0 <= landmark["y"] <= 100
            ):
                errors.append(f"{context} landmark x/y 必须位于 0–100")
            if landmark.get("shape") not in valid_landmark_shapes:
                errors.append(f"{context} landmark shape 不在有限集合中")
        answers = snapshot.get("answers")
        if not isinstance(answers, dict) or set(answers) != landscape_question_ids:
            errors.append(f"{context} answers 必须严格回答四个自然问题")
        elif any(not isinstance(value, str) or not value.strip() for value in answers.values()):
            errors.append(f"{context} answers 必须全部为非空文本")
        drilldown = snapshot.get("drilldown")
        if not isinstance(drilldown, list):
            errors.append(f"{context} drilldown 必须是数组")
            continue
        drilldown_ids = ids_unique(drilldown, f"{context} drilldown", errors)
        if drilldown_ids != {"visible", "product", "mechanism"}:
            errors.append(f"{context} drilldown 必须严格包含 visible、product、mechanism")
        for layer in drilldown:
            layer_context = f"{context} layer {layer.get('id')}"
            if not isinstance(layer.get("label"), str) or not layer.get("label", "").strip():
                errors.append(f"{layer_context} 缺少非空 label")
            if not isinstance(layer.get("description"), str) or not layer.get("description", "").strip():
                errors.append(f"{layer_context} 缺少非空 description")
            layer_dimensions = layer.get("dimensionIds", [])
            if layer.get("id") in {"product", "mechanism"} and not layer_dimensions:
                errors.append(f"{layer_context} 必须引用至少一个 dimension")
            for dimension_id in layer_dimensions:
                if dimension_id not in dimension_ids:
                    errors.append(f"{layer_context} 引用未知 dimension {dimension_id}")
                landscape_coverage.add(dimension_id)

    for branch in landscape_branches:
        context = f"state landscape branch {branch.get('id')}"
        validate_landscape_refs(branch, context, require_applicability=True)
        if branch.get("kind") not in valid_landscape_branches:
            errors.append(f"{context} kind 不在有限 branch 集合中")
        branch_state = branch.get("state")
        if not isinstance(branch_state, dict) or not branch_state:
            errors.append(f"{context} state 必须是非空对象")
        else:
            patch_valid(branch_state, dimensions, errors, context)
            landscape_coverage.update(branch_state)
        answers = branch.get("answers", {})
        if not isinstance(answers, dict) or not answers:
            errors.append(f"{context} answers 必须为非空 question override")
        else:
            unknown_answers = set(answers) - landscape_question_ids
            if unknown_answers:
                errors.append(f"{context} answers 引用未知问题 {sorted(unknown_answers)}")
            if any(not isinstance(value, str) or not value.strip() for value in answers.values()):
                errors.append(f"{context} answers 必须全部为非空文本")

    snapshot_by_id = {
        snapshot.get("id"): snapshot
        for snapshot in landscape_snapshots
        if snapshot.get("id")
    }
    constraint_dimension_ids = {
        condition.get("dimensionId")
        for constraint in constraints
        for condition in constraint.get("whenAll", [])
        if condition.get("dimensionId")
    }
    for snapshot_id, snapshot in snapshot_by_id.items():
        snapshot_state = snapshot.get("state", {})
        missing_constraint_dimensions = constraint_dimension_ids - set(snapshot_state)
        if missing_constraint_dimensions:
            errors.append(
                f"state landscape snapshot {snapshot_id} 缺少 constraint 判定维度 "
                f"{sorted(missing_constraint_dimensions)}"
            )
        violated = [
            item.get("id")
            for item in constraints
            if constraint_matches(item, snapshot_state)
        ]
        if violated:
            errors.append(f"state landscape snapshot {snapshot_id} 违反 constraints {violated}")
    for branch in landscape_branches:
        branch_state = branch.get("state", {})
        for snapshot_id in branch.get("applicableSnapshotIds", []):
            snapshot = snapshot_by_id.get(snapshot_id)
            if not snapshot or not isinstance(branch_state, dict):
                continue
            snapshot_state = snapshot.get("state", {})
            merged = {**snapshot_state, **branch_state}
            if all(snapshot_state.get(key) == value for key, value in branch_state.items()):
                errors.append(
                    f"state landscape branch {branch.get('id')} 对 {snapshot_id} 没有产生任何状态变化"
                )
            violated = [
                item.get("id")
                for item in constraints
                if constraint_matches(item, merged)
            ]
            if violated:
                errors.append(
                    f"state landscape branch {branch.get('id')} + {snapshot_id} "
                    f"违反 constraints {violated}"
                )

    shared_dimension_membership: Counter[str] = Counter()
    for shared in landscape_shared:
        context = f"state landscape shared scope {shared.get('id')}"
        validate_landscape_refs(shared, context, require_applicability=True)
        shared_dimensions = shared.get("dimensionIds")
        if not isinstance(shared_dimensions, list) or not shared_dimensions:
            errors.append(f"{context} dimensionIds 必须是非空数组")
            continue
        if len(shared_dimensions) != len(set(shared_dimensions)):
            errors.append(f"{context} dimensionIds 不得重复")
        for dimension_id in shared_dimensions:
            if dimension_id not in dimension_ids:
                errors.append(f"{context} 引用未知 dimension {dimension_id}")
            shared_dimension_membership[dimension_id] += 1
            landscape_coverage.add(dimension_id)
        related_action_ids = shared.get("relatedActionIds", [])
        if not isinstance(related_action_ids, list):
            errors.append(f"{context} relatedActionIds 必须是数组")
        else:
            for action_id in related_action_ids:
                if action_id not in action_ids:
                    errors.append(f"{context} 引用未知 action {action_id}")
    duplicated_shared_dimensions = sorted(
        dimension_id
        for dimension_id, count in shared_dimension_membership.items()
        if count > 1
    )
    if duplicated_shared_dimensions:
        errors.append(
            "stateLandscape sharedScopes 必须只登记共享 dimension 一次："
            f"{duplicated_shared_dimensions}"
        )

    if landscape_coverage != dimension_ids:
        errors.append(
            "stateLandscape 必须覆盖全部正式 dimension；"
            f"缺少 {sorted(dimension_ids - landscape_coverage)}，"
            f"未知 {sorted(landscape_coverage - dimension_ids)}"
        )
    if landscape_reference.get("dimensionQuery") != "all":
        errors.append("stateLandscape.reference.dimensionQuery 必须严格等于 all")
    if landscape_reference.get("id") != "reference.allDimensions":
        errors.append("stateLandscape.reference.id 必须严格等于 reference.allDimensions")

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
        ("structure node", [structure_context, *structure_nodes]),
        ("structure relation", structure_relations),
        ("state landscape field", landscape_fields),
        ("state landscape question", landscape_questions),
        ("state landscape snapshot", landscape_snapshots),
        ("state landscape branch", landscape_branches),
        ("state landscape shared scope", landscape_shared),
        ("state landscape reference", [landscape_reference]),
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
    presentation_session_constraint = next(
        (
            constraint
            for constraint in constraints
            if constraint.get("id") == "constraint.presentationNeedsSession"
        ),
        None,
    )
    expected_presentation_session_conditions = [
        {
            "dimensionId": "state.playbackPresentation",
            "notEquals": "none",
        },
        {
            "dimensionId": "state.mediaSessionResidency",
            "notEquals": "active",
        },
    ]
    if (
        presentation_session_constraint is None
        or presentation_session_constraint.get("whenAll")
        != expected_presentation_session_conditions
    ):
        errors.append(
            "constraint.presentationNeedsSession 必须严格禁止非 none Presentation "
            "与非 active Media Session Residency 的组合"
        )

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
            "spatial-transition": {
                "fromSurface", "toSurface", "invariantLabel", "transactionLabel", "phases"
            },
            "format-to-space-transition": {
                "projectionOptions", "stereoOptions", "selected", "shape", "invariant"
            },
            "system-interruption": {
                "lanes", "warmPhases", "coldPhases", "invariant"
            },
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
        if grammar == "spatial-transition" and isinstance(visual, dict):
            for field in ("fromSurface", "toSurface", "invariantLabel", "transactionLabel"):
                if not isinstance(visual.get(field), str) or not visual.get(field, "").strip():
                    errors.append(f"{context} spatial-transition {field} 必须是非空文本")
            phases = visual.get("phases")
            if not isinstance(phases, list) or not phases:
                errors.append(f"{context} spatial-transition phases 必须是非空数组")
            else:
                for phase_index, phase in enumerate(phases, 1):
                    if not isinstance(phase, dict) or not {"id", "label", "actorId"} <= set(phase):
                        errors.append(f"{context} spatial-transition phase {phase_index} 缺少 id、label 或 actorId")
                    else:
                        if (
                            not isinstance(phase.get("id"), str)
                            or not phase.get("id", "").strip()
                            or not isinstance(phase.get("label"), str)
                            or not phase.get("label", "").strip()
                        ):
                            errors.append(f"{context} spatial-transition phase {phase_index} 的 id/label 必须是非空文本")
                        if phase.get("actorId") not in actor_ids:
                            errors.append(f"{context} spatial-transition phase {phase_index} 引用未知 actor")
        if grammar == "format-to-space-transition" and isinstance(visual, dict):
            for field in ("shape", "invariant"):
                if not isinstance(visual.get(field), str) or not visual.get(field, "").strip():
                    errors.append(f"{context} format-to-space-transition {field} 必须是非空文本")
            for option_key in ("projectionOptions", "stereoOptions"):
                options = visual.get(option_key)
                if not isinstance(options, list) or not options:
                    errors.append(f"{context} {option_key} 必须是非空数组")
                elif any(
                    not isinstance(option, dict)
                    or not {"id", "label"} <= set(option)
                    or not isinstance(option.get("id"), str)
                    or not option.get("id", "").strip()
                    or not isinstance(option.get("label"), str)
                    or not option.get("label", "").strip()
                    for option in options
                ):
                    errors.append(f"{context} {option_key} 每项必须包含 id 与 label")
            projection_ids = [
                option.get("id") for option in visual.get("projectionOptions", [])
                if isinstance(option, dict)
            ]
            stereo_ids = [
                option.get("id") for option in visual.get("stereoOptions", [])
                if isinstance(option, dict)
            ]
            if projection_ids != ["180", "360", "fisheye"]:
                errors.append(f"{context} projectionOptions 必须按 180、360、fisheye 排列")
            if stereo_ids != ["mono", "sideBySide", "topBottom"]:
                errors.append(f"{context} stereoOptions 必须按 mono、sideBySide、topBottom 排列")
            selected = visual.get("selected")
            projection_id_set = {
                option.get("id") for option in visual.get("projectionOptions", [])
                if isinstance(option, dict)
            }
            stereo_id_set = {
                option.get("id") for option in visual.get("stereoOptions", [])
                if isinstance(option, dict)
            }
            if not isinstance(selected, dict) or set(selected) != {"projection", "stereo"}:
                errors.append(f"{context} selected 必须只包含 projection 与 stereo")
            elif selected.get("projection") not in projection_id_set or selected.get("stereo") not in stereo_id_set:
                errors.append(f"{context} selected 必须引用已登记的格式选项")
        if grammar == "system-interruption" and isinstance(visual, dict):
            if not isinstance(visual.get("invariant"), str) or not visual.get("invariant", "").strip():
                errors.append(f"{context} system-interruption invariant 必须是非空文本")
            lanes = visual.get("lanes")
            if not isinstance(lanes, list) or not lanes:
                errors.append(f"{context} system-interruption lanes 必须是非空数组")
            elif any(
                not isinstance(lane, dict)
                or not {"id", "label", "states"} <= set(lane)
                or not isinstance(lane.get("id"), str)
                or not lane.get("id", "").strip()
                or not isinstance(lane.get("label"), str)
                or not lane.get("label", "").strip()
                or not isinstance(lane.get("states"), list)
                or not lane.get("states")
                or any(
                    not isinstance(lane_state, str) or not lane_state.strip()
                    for lane_state in lane.get("states", [])
                )
                for lane in lanes
            ):
                errors.append(f"{context} 每条 lifecycle lane 必须包含 id、label 与非空 states")
            elif [lane.get("id") for lane in lanes] != ["process", "space", "intent"]:
                errors.append(f"{context} lifecycle lanes 必须严格按 process、space、intent 排列")
            for phases_key in ("warmPhases", "coldPhases"):
                phases = visual.get(phases_key)
                if (
                    not isinstance(phases, list)
                    or not phases
                    or any(not isinstance(phase, str) or not phase.strip() for phase in phases)
                ):
                    errors.append(f"{context} {phases_key} 必须是非空数组")

        visual_layers = action.get("visualLayers")
        allowed_layer_keys = {"primary", "journey", "blueprint", "machine"}
        allowed_layer_basis = {
            "journey": "product-demonstrations",
            "blueprint": "structural-placement-and-ownership",
            "machine": "state-demonstrations-and-branches",
        }
        if not isinstance(visual_layers, dict):
            errors.append(f"{context} 缺少 visualLayers")
            visual_layers = {}
        elif set(visual_layers) - allowed_layer_keys:
            errors.append(f"{context} visualLayers 包含未知层")
        if visual_layers.get("primary") != "journey" or "journey" not in visual_layers:
            errors.append(f"{context} 必须以 journey 为主层")
        for layer_id, expected_basis in allowed_layer_basis.items():
            layer = visual_layers.get(layer_id)
            expected_keys = {"basis", "summaryDimensions"} if layer_id == "machine" else {"basis"}
            if layer is not None:
                if (
                    not isinstance(layer, dict)
                    or set(layer) != expected_keys
                    or layer.get("basis") != expected_basis
                ):
                    errors.append(f"{context} {layer_id} 的声明结构或 basis 无效")

        structural_surface_kinds = {"behavior", "semantic-rule"}
        structural_placements = [
            placement for placement in action.get("placements", [])
            if surface_map.get(placement.get("surfaceId"), {}).get("kind")
            not in structural_surface_kinds
        ]
        if "blueprint" in visual_layers and (
            not structural_placements or not action.get("ownerIds")
        ):
            errors.append(f"{context} blueprint 缺少真实 surface/Scene placement 或 owner")
        demonstrations = action.get("demonstrations", [])
        changed_dimensions = {
            dimension_id
            for demonstration in demonstrations
            for sequence in (
                demonstration.get("steps", []),
                [
                    step
                    for branch in demonstration.get("branches", [])
                    for step in branch.get("steps", [])
                ],
            )
            for step in sequence
            for dimension_id in step.get("patch", {})
        }
        if "machine" in visual_layers:
            machine_ready = bool(demonstrations) and all(
                isinstance(demonstration.get("initialState"), dict)
                and bool(demonstration.get("steps") or demonstration.get("branches"))
                for demonstration in demonstrations
            )
            summary_dimensions = visual_layers["machine"].get("summaryDimensions", [])
            if not machine_ready or not changed_dimensions:
                errors.append(f"{context} machine 缺少非空状态变化或完整 demonstration")
            if (
                not isinstance(summary_dimensions, list)
                or not summary_dimensions
                or len(summary_dimensions) > 3
                or len(summary_dimensions) != len(set(summary_dimensions))
                or any(item not in changed_dimensions for item in summary_dimensions)
            ):
                errors.append(f"{context} machine summaryDimensions 必须是 1–3 个实际变化维度")
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
                if set(branch) - {"label", "result", "steps", "decisionStatus", "visualSemantic"}:
                    errors.append(f"{context}/branch {branch_index} 包含未知字段")
                branch_semantic = branch.get("visualSemantic")
                if branch_semantic not in {
                    "alternativeOutcome",
                    "guardedOutcome",
                    "recoverableFailure",
                    "rollback",
                    "systemInterruption",
                    "unresolved",
                }:
                    errors.append(f"{context}/branch {branch_index} visualSemantic 无效或缺失")
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
