from __future__ import annotations

import copy
from contextlib import redirect_stderr
from dataclasses import replace
import hashlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from Scripts.verification import regression_operation_adapter as operation_adapter
sys.modules.setdefault("regression_operation_adapter", operation_adapter)
from Scripts.verification import regression_oracle_adapter as oracle_adapter
from Scripts.verification import regression_preparation_adapter as preparation_adapter
from Scripts.regression import materialize_catalog_v2 as materializer

from Scripts.regression.materialize_catalog_v2 import (
    EXACT_JOURNEY_EDGES,
    LIVE_CATALOG_ROOT,
    MaterializationError,
    RESULT_REFERENCE,
    _canonical_json_bytes,
    _load_blueprint,
    _parser,
    _validate_blueprint,
    _validate_node_calls,
    _validate_registered_media_basenames,
    _validate_scenario_time_bounds,
    materialize,
)
from Scripts.regression.core.catalog import load_catalog
from Scripts.regression.core.ids import Digest
from Scripts.regression.review_io import load_review_policy
from Scripts.regression import review_stage


BLUEPRINT = ROOT / "Config/regression/catalog-v2.json"
CATALOG_SOURCE_ROOT = ROOT / "Config/regression/catalog-root"
STATIC_ROOT_PATHS = {
    "README.md",
    "agent-operability-review-protocol.md",
    "execution-protocol.md",
    "oracle-protocol.md",
    "review-policy.md",
    "semantic-authority.json",
}
GAP_SCENARIO_CAPABILITIES: dict[str, tuple[str, ...]] = {}
EXPECTED_JOURNEY_EDGES = frozenset(
    {
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:artwork-captured-on-exit",
        ),
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:audio-track-switch-same-session",
        ),
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:external-subtitle-source-matrix",
        ),
        (
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
            "scenario:local-media-lifecycle:subtitle-switch-and-off",
        ),
    }
)


class CatalogV2MaterializerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.blueprint = _load_blueprint(BLUEPRINT)

    def _write_blueprint(self, directory: Path, value: dict) -> Path:
        directory.mkdir(parents=True, exist_ok=True)
        value = copy.deepcopy(value)
        value.pop("contentDigest", None)
        value["contentDigest"] = "sha256:" + hashlib.sha256(
            _canonical_json_bytes(value)
        ).hexdigest()
        path = directory / "blueprint.json"
        path.write_text(
            json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return path

    def _materialize(self, directory: Path, name: str = "catalog") -> tuple[Path, Path, dict]:
        catalog = directory / name
        report = directory / f"{name}-report.json"
        value = materialize(BLUEPRINT, catalog, report, None)
        return catalog, report, value

    def _metadata(self, path: Path) -> dict:
        text = path.read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\n"))
        frontmatter, _ = text[4:].split("\n---\n", 1)
        return json.loads(frontmatter)

    def test_runtime_registries_are_the_only_operation_and_oracle_shape_authority(self) -> None:
        operation_metadata_keys = {
            "contract",
            "filename",
            "id",
            "invalidatesTags",
            "role",
            "title",
        }
        oracle_metadata_keys = {"contract", "filename", "id", "title"}
        preparation_metadata_keys = {
            "contract",
            "estimatedCostMillis",
            "filename",
            "id",
            "title",
        }
        self.assertTrue(
            all(set(item) == operation_metadata_keys for item in self.blueprint["operations"])
        )
        self.assertTrue(
            all(set(item) == oracle_metadata_keys for item in self.blueprint["oracles"])
        )
        self.assertTrue(
            all(
                set(item) == preparation_metadata_keys
                for item in self.blueprint["preparations"]
            )
        )

        with tempfile.TemporaryDirectory() as temporary:
            catalog, _, report = self._materialize(Path(temporary))
            generated_operations = {
                metadata["id"]: metadata
                for metadata in (
                    self._metadata(path) for path in (catalog / "operations").glob("*.md")
                )
            }
            generated_oracles = {
                metadata["id"]: metadata
                for metadata in (
                    self._metadata(path) for path in (catalog / "oracles").glob("*.md")
                )
            }
            generated_preparations = {
                metadata["id"]: metadata
                for metadata in (
                    self._metadata(path)
                    for path in (catalog / "preparations").glob("*.md")
                )
            }

        expected_operations = {
            item["id"]: item for item in operation_adapter.catalog_operation_shapes()
        }
        self.assertEqual(set(generated_operations), set(operation_adapter.SPECS))
        self.assertEqual(set(generated_operations), set(expected_operations))
        for identifier, expected in expected_operations.items():
            actual = generated_operations[identifier]
            self.assertEqual(actual["lanes"], expected["lanes"])
            self.assertEqual(actual["argumentSchema"]["fields"], expected["argumentFields"])
            self.assertEqual(actual["evidenceSchemas"], expected["evidenceSchemas"])
            self.assertEqual(actual["implementation"], expected["implementation"])

        self.assertEqual(set(generated_oracles), set(oracle_adapter.SPECS))
        for identifier, spec in oracle_adapter.SPECS.items():
            actual = generated_oracles[identifier]
            identity = oracle_adapter.implementation_identity(identifier)
            self.assertEqual(actual["kind"], spec.kind.value)
            self.assertEqual(
                actual["evidenceSchemas"],
                [
                    {
                        "evidenceType": spec.evidence_type,
                        "evidenceSchema": spec.evidence_schema,
                    }
                ],
            )
            self.assertEqual(
                actual["implementation"],
                {"locator": identity.locator, "digest": identity.digest},
            )

        self.assertEqual(
            set(generated_preparations), set(preparation_adapter.PREPARATION_REGISTRY)
        )
        authorities = report["runtimeAuthorities"]
        for identifier, spec in preparation_adapter.PREPARATION_REGISTRY.items():
            actual = generated_preparations[identifier]
            plan = preparation_adapter.build_plan(
                identifier, spec.lane, f"catalog-v2-{spec.lane}"
            )
            expected_ready = plan.blocker is None
            self.assertEqual(actual["lane"], plan.lane)
            self.assertEqual(
                actual["readiness"], "ready" if expected_ready else "implementation-gap"
            )
            self.assertEqual(
                actual["operations"],
                [
                    {**call.canonical(), "maxInvocations": 1}
                    for call in plan.calls
                ],
            )
            expected_projection = plan.canonical()
            del expected_projection["target"]
            del expected_projection["planDigest"]
            self.assertEqual(
                authorities["preparationPlanProjections"][identifier],
                expected_projection,
            )
            self.assertEqual(
                authorities["preparationImplementations"][identifier]["digest"],
                plan.implementation_digest,
            )
            self.assertEqual(
                actual["produces"],
                [
                    {
                        "key": plan.state.key,
                        "schema": plan.state.schema,
                        "producedByCall": plan.state.produced_by_call,
                        "dependsOnTags": list(plan.state.tags),
                    }
                ],
            )

    def test_blueprint_cannot_reintroduce_duplicate_runtime_shapes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            operation = copy.deepcopy(self.blueprint)
            operation["operations"][0]["lanes"] = ["device"]
            operation_path = self._write_blueprint(root / "operation", operation)
            with self.assertRaisesRegex(MaterializationError, "Operation runtime shape"):
                _validate_blueprint(_load_blueprint(operation_path))

            oracle = copy.deepcopy(self.blueprint)
            oracle["oracles"][0]["kind"] = "deterministic"
            oracle_path = self._write_blueprint(root / "oracle", oracle)
            with self.assertRaisesRegex(MaterializationError, "Oracle runtime shape"):
                _validate_blueprint(_load_blueprint(oracle_path))

            preparation = copy.deepcopy(self.blueprint)
            preparation["preparations"][0]["readiness"] = "ready"
            preparation_path = self._write_blueprint(root / "preparation", preparation)
            with self.assertRaisesRegex(MaterializationError, "Preparation runtime shape"):
                _validate_blueprint(_load_blueprint(preparation_path))

    def test_registry_drift_changes_generated_identity_instead_of_creating_two_authorities(self) -> None:
        operation_shapes = [dict(item) for item in operation_adapter.catalog_operation_shapes()]
        operation_shapes[0] = copy.deepcopy(operation_shapes[0])
        operation_shapes[0]["implementation"] = {
            "locator": "python://changed-operation",
            "digest": "sha256:" + "2" * 64,
        }
        oracle_identifier = next(iter(oracle_adapter.SPECS))
        changed_oracle_identity = oracle_adapter.ImplementationIdentity(
            "python://changed-oracle", "sha256:" + "3" * 64
        )

        original_identity = oracle_adapter.implementation_identity
        original_plan = preparation_adapter.build_plan
        preparation_identifier = next(iter(preparation_adapter.PREPARATION_REGISTRY))
        changed_preparation_digest = "sha256:" + "4" * 64

        def identity(identifier: str):
            if identifier == oracle_identifier:
                return changed_oracle_identity
            return original_identity(identifier)

        def build_plan(identifier: str, lane: str, target: str):
            plan = original_plan(identifier, lane, target)
            if identifier != preparation_identifier:
                return plan
            changed = replace(
                plan,
                implementation_digest=changed_preparation_digest,
                plan_digest="",
            )
            return replace(
                changed,
                plan_digest="sha256:"
                + hashlib.sha256(
                    _canonical_json_bytes(
                        changed.canonical(include_plan_digest=False)
                    )
                ).hexdigest(),
            )

        with (
            mock.patch.object(
                operation_adapter,
                "catalog_operation_shapes",
                return_value=tuple(operation_shapes),
            ),
            mock.patch.object(oracle_adapter, "implementation_identity", side_effect=identity),
            mock.patch.object(preparation_adapter, "build_plan", side_effect=build_plan),
            tempfile.TemporaryDirectory() as temporary,
        ):
            catalog, _, report = self._materialize(Path(temporary))
            generated_operations = [
                self._metadata(path) for path in (catalog / "operations").glob("*.md")
            ]
            generated_oracles = [
                self._metadata(path) for path in (catalog / "oracles").glob("*.md")
            ]
        operation_id = operation_shapes[0]["id"]
        self.assertEqual(
            next(item for item in generated_operations if item["id"] == operation_id)[
                "implementation"
            ],
            operation_shapes[0]["implementation"],
        )
        self.assertEqual(
            next(item for item in generated_oracles if item["id"] == oracle_identifier)[
                "implementation"
            ],
            {
                "locator": changed_oracle_identity.locator,
                "digest": changed_oracle_identity.digest,
            },
        )
        self.assertEqual(
            report["runtimeAuthorities"]["preparationImplementations"][
                preparation_identifier
            ]["digest"],
            changed_preparation_digest,
        )

    def test_exact_population_and_core_analysis(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            catalog, _, report = self._materialize(Path(temporary))

        self.assertEqual(
            report["counts"],
            {
                "promises": 65,
                "operations": 35,
                "oracles": 11,
                "rubrics": 97,
                "preparations": 18,
                "journeys": 14,
                "scenarios": 65,
                "staticCases": 115,
            },
        )
        self.assertEqual(report["obligationCount"], 149)
        expected_call_count = sum(
            len(
                preparation_adapter.build_plan(
                    identifier,
                    spec.lane,
                    f"catalog-v2-{spec.lane}",
                ).calls
            )
            for identifier, spec in preparation_adapter.PREPARATION_REGISTRY.items()
        ) + sum(
            len(scenario["operations"])
            for scenario in self.blueprint["scenarios"]
        )
        self.assertEqual(report["callCount"], expected_call_count)
        self.assertEqual(
            report["scenarioReadiness"],
            {"ready": 65},
        )
        self.assertEqual(
            report["preparationReadiness"],
            {"ready": 18},
        )
        self.assertEqual(
            report["objective"],
            {
                "scenarioReadiness": "declared",
                "preparationReadiness": "declared",
            },
        )
        self.assertEqual(report["coreAnalysis"]["status"], "loaded-and-analyzed")
        self.assertEqual(report["coreAnalysis"]["selectedScenarios"], 65)

        self.assertEqual(
            {
                (item["before"], item["after"])
                for item in report["coreAnalysis"]["journeyDependencies"]
            },
            EXPECTED_JOURNEY_EDGES,
        )
        self.assertEqual(
            {tuple(item) for item in report["journeyEdges"]},
            EXPECTED_JOURNEY_EDGES,
        )
        self.assertEqual(report["coreAnalysis"]["scenarioReadiness"], report["scenarioReadiness"])
        self.assertEqual(
            report["coreAnalysis"]["preparationReadiness"],
            report["preparationReadiness"],
        )
        self.assertEqual(
            {item["id"] for item in report["scenarioReadinessGaps"]},
            {
                item["id"]
                for item in self.blueprint["scenarios"]
                if item["readiness"] != "ready"
            },
        )
        self.assertEqual(
            {item["id"] for item in report["scenarioReadinessGaps"]},
            set(GAP_SCENARIO_CAPABILITIES),
        )
        self.assertFalse(report["preparationReadinessGaps"])
        authorities = report["runtimeAuthorities"]
        self.assertEqual(
            authorities["preparationRegistryDigest"], preparation_adapter.REGISTRY_DIGEST
        )
        self.assertTrue(
            all(
                "target" not in item and "planDigest" not in item
                for item in authorities["preparationPlanProjections"].values()
            )
        )

    def test_rejects_internally_consistent_118_obligation_blueprint(self) -> None:
        tampered = copy.deepcopy(self.blueprint)
        scenario = next(
            item
            for item in tampered["scenarios"]
            if item["id"]
            == "scenario:format-coverage:signalled-media-classification"
        )
        removed = scenario["obligations"].pop()
        scenario["success"]["all"] = [
            term
            for term in scenario["success"]["all"]
            if term["observation"] != removed["id"]
        ]
        self.assertEqual(
            sum(len(item["obligations"]) for item in tampered["scenarios"]),
            118,
        )
        self.assertEqual(
            {term["observation"] for term in scenario["success"]["all"]},
            {item["id"] for item in scenario["obligations"]},
        )

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            blueprint_path = self._write_blueprint(root, tampered)
            with self.assertRaisesRegex(
                MaterializationError,
                "Catalog must contain exactly 149 globally unique obligations",
            ):
                materialize(
                    blueprint_path,
                    root / "catalog",
                    root / "report.json",
                    None,
                )

    def test_materialization_rejects_unavailable_or_inconsistent_compiler_analysis(self) -> None:
        cases = (
            {"status": "unavailable", "reason": "missing compiler"},
            {
                "status": "loaded-and-analyzed",
                "selectedScenarios": 65,
                "scenarioReadiness": {"implementation-gap": 21, "ready": 44},
                "preparationReadiness": {"implementation-gap": 6, "ready": 11},
            },
        )
        for index, analysis in enumerate(cases):
            with (
                self.subTest(analysis=analysis),
                mock.patch(
                    "Scripts.regression.materialize_catalog_v2._load_and_analyze",
                    return_value=analysis,
                ),
                tempfile.TemporaryDirectory() as temporary,
            ):
                root = Path(temporary)
                with self.assertRaisesRegex(
                    MaterializationError, "compiler analysis"
                ):
                    materialize(
                        BLUEPRINT,
                        root / f"catalog-{index}",
                        root / f"report-{index}.json",
                        None,
                    )

    def test_cli_requires_blueprint_output_and_report(self) -> None:
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            _parser().parse_args([])

    def test_output_and_report_are_byte_stable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first, first_report, _ = self._materialize(root, "first")
            second, second_report, _ = self._materialize(root, "second")
            first_paths = sorted(
                path.relative_to(first).as_posix()
                for path in first.rglob("*")
                if path.is_file()
            )
            second_paths = sorted(
                path.relative_to(second).as_posix()
                for path in second.rglob("*")
                if path.is_file()
            )
            self.assertEqual(first_paths, second_paths)
            self.assertNotIn("reviews", first_paths)
            self.assertFalse((first / "reviews").exists())
            self.assertTrue(
                all((first / path).read_bytes() == (second / path).read_bytes() for path in first_paths)
            )
            self.assertEqual(first_report.read_bytes(), second_report.read_bytes())

    def test_persistent_copy_sources_are_closed_and_exclude_review_history(self) -> None:
        paths = {item["path"] for item in self.blueprint["copyDocuments"]}
        self.assertFalse(any(path.startswith("Regression/") for path in paths))
        self.assertEqual(
            {path for path in paths if "/" not in path},
            STATIC_ROOT_PATHS,
        )
        self.assertNotIn("human-coverage-questions.md", paths)
        self.assertFalse(any(path == "reviews" or path.startswith("reviews/") for path in paths))
        for item in self.blueprint["copyDocuments"]:
            with self.subTest(path=item["path"]):
                source = CATALOG_SOURCE_ROOT / item["path"]
                self.assertTrue(source.is_file())
                self.assertEqual(
                    item["digest"],
                    "sha256:" + hashlib.sha256(source.read_bytes()).hexdigest(),
                )

    def test_persistent_promise_population_drift_breaks_exact_total(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source_root = Path(temporary) / "catalog-root"
            shutil.copytree(CATALOG_SOURCE_ROOT, source_root)
            promise_path = source_root / "promises/cache-and-artwork.md"
            text = promise_path.read_text(encoding="utf-8")
            frontmatter, body = text[4:].split("\n---\n", 1)
            metadata = json.loads(frontmatter)
            added = copy.deepcopy(metadata["promises"][0])
            added["id"] = "promise:cache-and-artwork:drift"
            metadata["promises"].append(added)
            promise_path.write_text(
                "---\n"
                + json.dumps(metadata, ensure_ascii=False, indent=2)
                + "\n---\n"
                + body,
                encoding="utf-8",
            )

            with (
                mock.patch.object(materializer, "CATALOG_SOURCE_ROOT", source_root),
                self.assertRaisesRegex(
                    MaterializationError,
                    "blueprint count mismatch:.*'promises': 66",
                ),
            ):
                _validate_blueprint(self.blueprint)

    def test_empty_repository_materialization_closes_catalog_and_review_loaders(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            catalog, _, report = self._materialize(repository, "Regression")

            self.assertEqual(set(report["expectedPaths"]), {
                path.relative_to(catalog).as_posix()
                for path in catalog.rglob("*")
                if path.is_file()
            })
            self.assertTrue(STATIC_ROOT_PATHS <= set(report["expectedPaths"]))
            self.assertFalse(any(path.startswith("reviews/") for path in report["expectedPaths"]))
            self.assertNotIn("human-coverage-questions.md", report["expectedPaths"])
            self.assertEqual(len(load_catalog(catalog).scenarios), 65)
            self.assertIsNotNone(load_review_policy(catalog / "review-policy.md"))

            authority_payload = json.loads(
                (catalog / "semantic-authority.json").read_text(encoding="utf-8")
            )
            decision_log = repository / authority_payload["authority"]["source"]
            decision_log.parent.mkdir(parents=True, exist_ok=True)
            decision_log.write_bytes(
                (ROOT / authority_payload["authority"]["source"]).read_bytes()
            )
            for decision in authority_payload["decisions"]:
                for evidence in decision["evidence"]:
                    relative = evidence.partition("#")[0]
                    destination = repository / relative
                    if destination.exists():
                        continue
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes((ROOT / relative).read_bytes())
            loaded_authority = review_stage._semantic_authority(repository.resolve())
            self.assertEqual(loaded_authority.decision_ids, tuple(
                f"HC-{index:03d}" for index in range(24)
            ))
            self.assertRegex(
                str(review_stage.agent_review_environment_digest(
                    repository.resolve(), Digest("sha256:" + "1" * 64)
                )),
                r"^sha256:[0-9a-f]{64}$",
            )
            self.assertEqual(
                (catalog / "semantic-authority.json").read_bytes(),
                (CATALOG_SOURCE_ROOT / "semantic-authority.json").read_bytes(),
            )
            decision_source = ROOT / authority_payload["authority"]["source"]
            self.assertEqual(
                report["runtimeAuthorities"]["semanticAuthorityDecisionSource"],
                {
                    "locator": authority_payload["authority"]["source"],
                    "digest": "sha256:"
                    + hashlib.sha256(decision_source.read_bytes()).hexdigest(),
                },
            )
            oracle_protocol = (catalog / "oracle-protocol.md").read_text(encoding="utf-8")
            self.assertIn("Oracle", oracle_protocol)
            self.assertEqual(len(oracle_adapter.SPECS), 11)

    def test_materialization_does_not_read_the_live_catalog_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            empty_repository = root / "repository-without-live-regression"
            empty_repository.mkdir()
            with mock.patch(
                "Scripts.regression.materialize_catalog_v2.REPOSITORY_ROOT",
                empty_repository,
            ):
                catalog, _, _ = self._materialize(root, "isolated")
            self.assertTrue((catalog / "semantic-authority.json").is_file())

    def test_materialization_rejects_semantic_decision_source_digest_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tampered = root / "semantic-authority-decisions.tsv"
            tampered.write_bytes(
                (ROOT / "Config/regression/semantic-authority-decisions.tsv").read_bytes()
                + b"tampered\n"
            )
            with (
                mock.patch(
                    "Scripts.regression.materialize_catalog_v2.SEMANTIC_AUTHORITY_DECISIONS_PATH",
                    tampered,
                ),
                self.assertRaisesRegex(
                    MaterializationError,
                    "semantic authority decision source digest changed",
                ),
            ):
                self._materialize(root, "tampered")

    def test_check_ignores_review_outputs_and_rejects_other_stale_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline, _, _ = self._materialize(root, "baseline")
            checked_report = root / "checked-report.json"
            materialize(BLUEPRINT, root / "checked", checked_report, baseline)
            self.assertEqual(json.loads(checked_report.read_text())["check"], "matched")

            readme = baseline / "README.md"
            readme_bytes = readme.read_bytes()
            readme.write_bytes(readme_bytes + b"stale\n")
            with self.assertRaisesRegex(MaterializationError, "changed=README.md"):
                materialize(
                    BLUEPRINT,
                    root / "root-document-check",
                    root / "root-document-report.json",
                    baseline,
                )
            readme.write_bytes(readme_bytes)

            review_files = (
                baseline / "reviews/deterministic/receipt.json",
                baseline / "reviews/reports/report.md",
                baseline / "reviews/agent-operability/nested/evidence.json",
            )
            for review_file in review_files:
                review_file.parent.mkdir(parents=True, exist_ok=True)
                review_file.write_text("runtime review output\n", encoding="utf-8")
            reviews_report = root / "reviews-report.json"
            materialize(
                BLUEPRINT,
                root / "reviews-check",
                reviews_report,
                baseline,
            )
            self.assertEqual(
                json.loads(reviews_report.read_text())["check"], "matched"
            )

            stale = baseline / "operations/stale-v1.md"
            stale.write_text("stale\n", encoding="utf-8")
            retired_questions = baseline / "human-coverage-questions.md"
            retired_questions.write_text("retired\n", encoding="utf-8")
            (baseline / "legacy-empty-directory").mkdir()
            with self.assertRaises(MaterializationError) as raised:
                materialize(BLUEPRINT, root / "stale-check", root / "stale-report.json", baseline)
            detail = str(raised.exception)
            self.assertIn("human-coverage-questions.md", detail)
            self.assertIn("operations/stale-v1.md", detail)
            self.assertIn("extraDirectories=legacy-empty-directory", detail)
            self.assertNotIn("reviews/", detail)

    def test_blueprint_binds_exact_operation_oracle_and_edge_sets(self) -> None:
        operation_ids = {item["id"] for item in self.blueprint["operations"]}
        self.assertEqual(len(operation_ids), 35)
        self.assertTrue(
            {
                "operation:input.device-hub-prepare@1",
                "operation:diagnostics.browse-hierarchy@1",
                "operation:diagnostics.playback-state@1",
                "operation:evidence.structural-test@1",
                "operation:issue.present@1",
                "operation:playback.select-subtitle@1",
                "operation:transition-trace.arm@1",
                "operation:transition-trace.fetch@1",
                "operation:transition-trace.disarm@1",
            }
            <= operation_ids
        )
        self.assertFalse(
            {
                "operation:accessibility.swipe@2",
                "operation:diagnostics.emby-range-log@1",
                "operation:diagnostics.window-control-plane@1",
                "operation:evidence.archive@2",
                "operation:transition.trace-arm@1",
                "operation:transition.trace-fetch@1",
                "operation:transition.trace-disarm@1",
            }
            & operation_ids
        )
        self.assertEqual(len({item["id"] for item in self.blueprint["oracles"]}), 11)
        edges = {
            (edge["before"], edge["after"])
            for journey in self.blueprint["journeys"]
            for edge in journey["ordering"]
        }
        self.assertEqual(EXACT_JOURNEY_EDGES, EXPECTED_JOURNEY_EDGES)
        self.assertEqual(edges, EXPECTED_JOURNEY_EDGES)

    def test_blueprint_has_exact_fetch_then_disarm_transition_captures(self) -> None:
        materializer._validate_transition_trace_sequences(self.blueprint["scenarios"])
        transition_scenarios = []
        capture_count = 0
        for scenario in self.blueprint["scenarios"]:
            operations = scenario["operations"]
            arm_indexes = [
                index
                for index, call in enumerate(operations)
                if call["operation"] == "operation:transition-trace.arm@1"
            ]
            if arm_indexes:
                transition_scenarios.append(scenario["id"])
            for arm_index in arm_indexes:
                capture_count += 1
                fetch_index = next(
                    index
                    for index in range(arm_index + 1, len(operations))
                    if operations[index]["operation"]
                    == "operation:transition-trace.fetch@1"
                )
                token = (
                    f"result://{operations[arm_index]['callId']}/generationToken"
                )
                self.assertGreater(fetch_index, arm_index + 1, scenario["id"])
                fetch_arguments = operations[fetch_index]["arguments"]
                self.assertEqual(
                    fetch_arguments["generationToken"], token, scenario["id"]
                )
                self.assertLessEqual(
                    set(fetch_arguments),
                    {"generationToken", "relatedResults"},
                    scenario["id"],
                )
                self.assertEqual(
                    operations[fetch_index + 1]["operation"],
                    "operation:transition-trace.disarm@1",
                    scenario["id"],
                )
                self.assertEqual(
                    operations[fetch_index + 1]["arguments"],
                    {"generationToken": token},
                    scenario["id"],
                )
        self.assertEqual(capture_count, 7)
        self.assertEqual(len(transition_scenarios), 6)
        self.assertTrue(
            all(
                identifier.startswith("scenario:presentation-tour:")
                for identifier in transition_scenarios
            )
        )

    def test_rejects_invalid_transition_capture_lifecycles(self) -> None:
        def call(
            sequence: int,
            operation: str,
            arguments: dict | None = None,
        ) -> dict:
            return {
                "callId": f"call:presentation-tour:sample:{sequence:02d}",
                "operation": operation,
                "arguments": arguments or {},
                "maxInvocations": 1,
            }

        def capture(offset: int) -> list[dict]:
            arm = call(offset, "operation:transition-trace.arm@1")
            token = f"result://{arm['callId']}/generationToken"
            return [
                arm,
                call(offset + 1, "operation:format.apply@2"),
                call(
                    offset + 2,
                    "operation:transition-trace.fetch@1",
                    {"generationToken": token},
                ),
                call(
                    offset + 3,
                    "operation:transition-trace.disarm@1",
                    {"generationToken": token},
                ),
            ]

        scenarios = [
            {
                "id": f"scenario:presentation-tour:sample-{index}",
                "operations": capture(1),
            }
            for index in range(6)
        ]
        scenarios[0]["operations"].extend(capture(5))
        materializer._validate_transition_trace_sequences(scenarios)

        cases: list[tuple[str, list[dict], str]] = []

        disarm_before_fetch = copy.deepcopy(scenarios)
        operations = disarm_before_fetch[0]["operations"]
        operations[2], operations[3] = operations[3], operations[2]
        cases.append(
            (
                "disarm-before-fetch",
                disarm_before_fetch,
                "transition trace has no product action",
            )
        )

        missing_disarm = copy.deepcopy(scenarios)
        missing_disarm[0]["operations"].pop(3)
        cases.append(
            (
                "missing-disarm",
                missing_disarm,
                "transition trace is not fetch then disarm",
            )
        )

        non_adjacent_disarm = copy.deepcopy(scenarios)
        non_adjacent_disarm[0]["operations"].insert(
            3, call(99, "operation:format.apply@2")
        )
        cases.append(
            (
                "non-adjacent-disarm",
                non_adjacent_disarm,
                "transition trace is not fetch then disarm",
            )
        )

        token_mismatch = copy.deepcopy(scenarios)
        token_mismatch[0]["operations"][3]["arguments"] = {
            "generationToken": "result://call:presentation-tour:wrong:01/generationToken"
        }
        cases.append(
            (
                "token-mismatch",
                token_mismatch,
                "transition trace does not bind its arm token",
            )
        )

        control_in_action_slice = copy.deepcopy(scenarios)
        control_in_action_slice[0]["operations"][1]["operation"] = (
            "operation:transition-trace.disarm@1"
        )
        cases.append(
            (
                "control-in-action-slice",
                control_in_action_slice,
                "transition trace has no product action",
            )
        )

        zero = copy.deepcopy(scenarios)
        for scenario in zero:
            scenario["operations"] = [
                call(1, "operation:format.apply@2")
            ]
        cases.append(("zero", zero, "contains no transition capture sequence"))

        for name, value, message in cases:
            with self.subTest(name=name):
                with self.assertRaisesRegex(MaterializationError, message):
                    materializer._validate_transition_trace_sequences(value)

    def test_rejects_zero_missing_extra_reversed_cross_journey_narrative_and_main_gate_edges(self) -> None:
        local_id = "journey:local-media-lifecycle"
        webdav_id = "journey:webdav-source-lifecycle"
        injected = "scenario:local-media-lifecycle:injected-import-rejoins-ingest"
        artwork = "scenario:local-media-lifecycle:artwork-captured-on-exit"
        main_gate = "scenario:local-media-lifecycle:clean-flat-playback-main-gate"

        cases: dict[str, dict] = {}

        zero = copy.deepcopy(self.blueprint)
        for journey in zero["journeys"]:
            journey["ordering"] = []
        cases["zero"] = zero

        missing = copy.deepcopy(self.blueprint)
        next(
            item for item in missing["journeys"] if item["id"] == local_id
        )["ordering"].pop()
        cases["missing"] = missing

        extra = copy.deepcopy(self.blueprint)
        next(item for item in extra["journeys"] if item["id"] == local_id)[
            "ordering"
        ].append(
            {
                "before": "scenario:local-media-lifecycle:clean-start-position-zero",
                "after": "scenario:local-media-lifecycle:automatic-play-next-resume-policy",
            }
        )
        cases["extra"] = extra

        reversed_edge = copy.deepcopy(self.blueprint)
        local = next(
            item for item in reversed_edge["journeys"] if item["id"] == local_id
        )
        edge = next(
            item
            for item in local["ordering"]
            if item == {"before": injected, "after": artwork}
        )
        edge["before"], edge["after"] = edge["after"], edge["before"]
        cases["reversed"] = reversed_edge

        cross_journey = copy.deepcopy(self.blueprint)
        local = next(
            item for item in cross_journey["journeys"] if item["id"] == local_id
        )
        webdav = next(
            item for item in cross_journey["journeys"] if item["id"] == webdav_id
        )
        webdav["ordering"] = [local["ordering"].pop()]
        cases["cross-journey"] = cross_journey

        narrative = copy.deepcopy(self.blueprint)
        local = next(
            item for item in narrative["journeys"] if item["id"] == local_id
        )
        local["ordering"][0] = {
            "before": "scenario:local-media-lifecycle:clean-start-position-zero",
            "after": "scenario:local-media-lifecycle:automatic-play-next-resume-policy",
        }
        cases["narrative"] = narrative

        main_gate_edge = copy.deepcopy(self.blueprint)
        local = next(
            item for item in main_gate_edge["journeys"] if item["id"] == local_id
        )
        local["ordering"][0] = {"before": injected, "after": main_gate}
        cases["main-gate"] = main_gate_edge

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, value in cases.items():
                with self.subTest(name=name):
                    path = self._write_blueprint(root / name, value)
                    with self.assertRaisesRegex(
                        MaterializationError,
                        "declared shared-state handoff|stay within its Journey",
                    ):
                        _validate_blueprint(_load_blueprint(path))

    def test_runtime_registry_has_no_unknown_or_dead_operation_id(self) -> None:
        registered = set(operation_adapter.SPECS)
        declared = {item["id"] for item in self.blueprint["operations"]}
        used = {
            call["operation"]
            for scenario in self.blueprint["scenarios"]
            for call in scenario["operations"]
        }
        for identifier, spec in preparation_adapter.PREPARATION_REGISTRY.items():
            plan = preparation_adapter.build_plan(
                identifier, spec.lane, f"catalog-v2-{spec.lane}"
            )
            used.update(call.operation_id for call in plan.calls)
        self.assertEqual(registered, declared)
        self.assertEqual(used, declared)
        self.assertNotIn("operation:diagnostics.emby-range-log@1", declared)
        self.assertEqual(
            {item["id"] for item in self.blueprint["preparations"]},
            set(preparation_adapter.PREPARATION_REGISTRY),
        )

    def test_operation_roles_and_invalidations_match_runtime_effects(self) -> None:
        operations = {item["id"]: item for item in self.blueprint["operations"]}
        self.assertEqual(
            operations["operation:issue.present@1"]["role"],
            "product-behavior",
        )
        self.assertEqual(
            set(operations["operation:issue.present@1"]["invalidatesTags"]),
            {
                "certificate.trust",
                "fixture.corpus",
                "source.connection",
                "source.session",
                "issue.surface",
                "playback.position",
                "playback.selection",
                "playback.session",
                "presentation.mode",
                "presentation.state",
                "renderer.graph",
                "ui.navigation",
                "ui.state",
            },
        )
        self.assertEqual(
            operations["operation:playback.select-subtitle@1"]["role"],
            "product-behavior",
        )
        self.assertEqual(
            operations["operation:media.import-staged@2"]["role"],
            "setup",
        )
        self.assertEqual(
            operations["operation:diagnostics.browse-hierarchy@1"]["role"],
            "product-behavior",
        )
        self.assertEqual(
            set(
                operations["operation:diagnostics.browse-hierarchy@1"][
                    "invalidatesTags"
                ]
            ),
            {"source.session", "ui.navigation", "ui.state"},
        )
        self.assertTrue(
            {
                "app.session",
                "playback.session",
                "presentation.state",
                "renderer.graph",
                "ui.navigation",
                "ui.state",
            }
            <= set(
                operations["operation:app.relaunch@1"]["invalidatesTags"]
            )
        )
        self.assertTrue(
            {
                "media.format",
                "playback.session",
                "presentation.mode",
                "presentation.state",
                "renderer.graph",
            }
            <= set(operations["operation:format.apply@2"]["invalidatesTags"])
        )

    def test_storage_clear_invalidates_only_the_state_its_handler_can_change(self) -> None:
        operations = {item["id"]: item for item in self.blueprint["operations"]}
        current_tags = set(
            operations["operation:storage.clear@1"]["invalidatesTags"]
        )
        self.assertEqual(
            current_tags,
            {
                "cache.state",
                "ui.navigation",
                "ui.state",
                "viewing.progress",
                "viewing.state",
            },
        )

        former_tags = current_tags | {"library.contents", "settings.state"}
        freed = set()
        for identifier, spec in preparation_adapter.PREPARATION_REGISTRY.items():
            plan = preparation_adapter.build_plan(
                identifier, spec.lane, f"catalog-v2-{spec.lane}"
            )
            state_tags = set(plan.state.tags)
            if state_tags & former_tags and not state_tags & current_tags:
                freed.add(identifier)
        self.assertEqual(
            freed,
            {
                "preparation:audio-only-fixtures",
                "preparation:dynamic-range-corpus",
                "preparation:format-corpus",
                "preparation:local-directory-subtitle-source",
                "preparation:presentation-fixtures-device",
                "preparation:presentation-fixtures-simulator",
                "preparation:projection-corpus",
                "preparation:window-input-fixture",
            },
        )

    def test_device_webdav_preparations_snapshot_their_own_tls_trust_calls(self) -> None:
        operation_tags = {
            item["id"]: set(item["invalidatesTags"])
            for item in self.blueprint["operations"]
        }
        expected = {
            "preparation:presentation-fixtures-device": (
                "app.session",
                "certificate.trust",
                "fixture.corpus",
                "lane.instance",
                "library.contents",
                "presentation.state",
                "source.connection",
                "source.session",
                "source.webdav",
            ),
            "preparation:viewing-storage-fixtures-device": (
                "app.session",
                "cache.state",
                "certificate.trust",
                "fixture.corpus",
                "lane.instance",
                "library.contents",
                "settings.state",
                "source.connection",
                "source.session",
                "source.webdav",
                "viewing.state",
            ),
        }
        for identifier, expected_tags in expected.items():
            spec = preparation_adapter.PREPARATION_REGISTRY[identifier]
            plan = preparation_adapter.build_plan(
                identifier, spec.lane, f"catalog-v2-{spec.lane}"
            )
            invalidated_by_own_calls = set().union(
                *(operation_tags[call.operation_id] for call in plan.calls)
            )
            self.assertIn("certificate.trust", invalidated_by_own_calls)
            self.assertEqual(plan.state.tags, expected_tags)

    def test_remote_routes_clean_state_and_ephemeral_ui_sequences_are_closed(self) -> None:
        scenarios = {item["id"]: item for item in self.blueprint["scenarios"]}
        source_route = [
            "FileBrowsing-SourcesSidebar-sourceMore",
            "FileBrowsing-SourcesSidebar-add",
            "FileBrowsing-SourcesSidebar-addWebDAV",
        ]
        for scenario_id in (
            "scenario:webdav-source-lifecycle:webdav-add-source",
            "scenario:webdav-source-lifecycle:certificate-trust-boundary",
            "scenario:issue-surface-behavior:source-failure-guidance-matrix",
        ):
            scenario = scenarios[scenario_id]
            direct_entries = [
                call
                for call in scenario["operations"]
                if call["operation"] == "operation:accessibility.activate@2"
                and "FileBrowsing-SourcesSidebar-addWebDAV"
                in call["arguments"].get("identifiers", [])
            ]
            self.assertTrue(direct_entries, scenario_id)
            self.assertTrue(
                all(call["arguments"]["identifiers"] == source_route for call in direct_entries),
                scenario_id,
            )

        for scenario_id in (
            "scenario:local-media-lifecycle:clean-flat-playback-main-gate",
            "scenario:local-media-lifecycle:clean-start-position-zero",
        ):
            operations = scenarios[scenario_id]["operations"]
            self.assertEqual(
                [item["operation"] for item in operations[:2]],
                [
                    "operation:harness.reset-product-state@2",
                    "operation:app.relaunch@1",
                ],
            )
            imports = [
                item for item in operations
                if item["operation"] == "operation:media.import-staged@2"
            ]
            self.assertEqual(len(imports), 1, scenario_id)

        for scenario in self.blueprint["scenarios"]:
            operations = scenario["operations"]
            for index, operation in enumerate(operations):
                if operation["operation"] == "operation:transition-trace.fetch@1":
                    self.assertLess(index + 1, len(operations), scenario["id"])
                    self.assertEqual(
                        operations[index + 1]["operation"],
                        "operation:transition-trace.disarm@1",
                        scenario["id"],
                    )

        spatial = scenarios["scenario:presentation-tour:spatial-controls-summon"]
        self.assertEqual(
            spatial["operations"][0]["operation"],
            "operation:input.device-hub-prepare@1",
        )
        pinches = [
            item for item in spatial["operations"]
            if item["operation"] == "operation:input.device-hub-pinch@2"
        ]
        self.assertEqual(len(pinches), 6)
        self.assertTrue(all("allowSmall" not in item["arguments"] for item in pinches))

        audio_only = scenarios[
            "scenario:audio-only-playback:secondary-menu-pins-audio-controls"
        ]
        self.assertEqual(audio_only["staticCases"], ["audio-menu", "speed-menu"])
        nested = [
            call["arguments"]["identifiers"]
            for call in audio_only["operations"]
            if call["operation"] == "operation:accessibility.activate@2"
        ]
        self.assertEqual(
            nested,
            [
                [
                    "PlayerUI-window-playback-surface",
                    "PlayerUI-TopAction-more",
                    "PlayerUI-menu-audio",
                ],
                [
                    "PlayerUI-window-playback-surface",
                    "PlayerUI-TopAction-more",
                    "PlayerUI-menu-speed",
                ],
            ],
        )

    def test_typed_issue_and_unsupported_codec_use_real_runtime_routes(self) -> None:
        scenarios = {item["id"]: item for item in self.blueprint["scenarios"]}
        typed = scenarios[
            "scenario:issue-surface-behavior:typed-single-slot-contract"
        ]
        presented = [
            call["arguments"]["category"]
            for call in typed["operations"]
            if call["operation"] == "operation:issue.present@1"
        ]
        self.assertEqual(
            presented, ["source-file-missing", "server-certificate-changed"]
        )
        self.assertEqual(len(typed["obligations"]), 2)
        self.assertEqual(typed["success"].keys(), {"all"})

        unsupported = scenarios[
            "scenario:format-coverage:unsupported-codec-guidance"
        ]
        opened = next(
            call for call in unsupported["operations"]
            if call["operation"] == "operation:media.open@2"
        )
        self.assertEqual(
            opened["arguments"],
            {
                "deadlineSeconds": 45,
                "expectedIssueCategory": "unsupportedVideoCodec",
                "expectedLanding": "window",
                "identifier": "MediaLibrary-grid-video-packed_bframes.avi",
            },
        )

    def test_external_subtitle_matrix_is_three_closed_dynamic_attempts(self) -> None:
        scenario = next(
            item for item in self.blueprint["scenarios"]
            if item["id"]
            == "scenario:local-media-lifecycle:external-subtitle-source-matrix"
        )
        self.assertEqual(scenario["readiness"], "ready")
        self.assertFalse(scenario["blockers"])
        self.assertEqual(
            scenario["prerequisites"],
            [
                {
                    "key": "local-aggregate-staged",
                    "schema": "fixture-set.local-aggregate-staged@2",
                },
                {
                    "key": "local-directory-subtitle-source-ready",
                    "schema": "media-source.local-directory-sidecars@1",
                },
            ],
        )
        operations = [item["operation"] for item in scenario["operations"]]
        self.assertEqual(
            operations,
            [
                "operation:app.relaunch@1",
                "operation:navigation.select-tab@1",
                "operation:accessibility.activate@2",
                "operation:media.open@2",
                "operation:playback.await-window-state@1",
                "operation:playback.select-subtitle@1",
                "operation:evidence.capture-frames@1",
                "operation:app.relaunch@1",
                "operation:navigation.select-tab@1",
                "operation:accessibility.activate@2",
                "operation:accessibility.inspect@2",
                "operation:media.open@2",
                "operation:playback.await-window-state@1",
                "operation:playback.select-subtitle@1",
                "operation:evidence.capture-frames@1",
                "operation:app.relaunch@1",
                "operation:navigation.select-tab@1",
                "operation:accessibility.activate@2",
                "operation:playback.await-window-state@1",
                "operation:playback.select-subtitle@1",
                "operation:evidence.capture-frames@1",
            ],
        )
        self.assertEqual(
            scenario["operations"][2]["arguments"],
            {
                "context": "main-window-browser",
                "identifiers": [
                    "MediaLibrary-grid-folder-sdr-bframe-aggregate-30s-sidecars"
                ],
            },
        )
        selections = [
            item
            for item in scenario["operations"]
            if item["operation"] == "operation:playback.select-subtitle@1"
        ]
        self.assertEqual(
            [item["arguments"]["sourceKind"] for item in selections],
            [
                "local-sidecar",
                "source-directory-sidecar",
                "emby-external-stream",
            ],
        )
        self.assertEqual(
            [item["arguments"].get("trackLabel") for item in selections],
            [
                "sdr-bframe-aggregate-30s.zh-CN.srt",
                "sdr-bframe-aggregate-30s.zh-CN.srt",
                None,
            ],
        )
        frame_calls = [
            item
            for item in scenario["operations"]
            if item["operation"] == "operation:evidence.capture-frames@1"
        ]
        self.assertEqual(
            [item["producedByCall"] for item in scenario["obligations"]],
            [item["callId"] for item in frame_calls],
        )
        self.assertEqual(
            [item["arguments"]["relatedResults"] for item in frame_calls],
            [
                [
                    f"result://{selection['callId']}/{field}"
                    for field in (
                        "host",
                        "sourceKind",
                        "deadlineSeconds",
                        "discoveredTracks",
                        "selectedTrack",
                        "settlement",
                        "identityObservation",
                    )
                ]
                for selection in selections
            ],
        )
        self.assertTrue(
            all(
                item["oracle"] == "oracle:agent-visual@2"
                for item in scenario["obligations"]
            )
        )
        contract = scenario["contract"]
        self.assertIn("candidate-missing", contract)
        self.assertIn("selection-not-settled", contract)
        self.assertIn("succeeded=true", contract)
        self.assertIn("Oracle remain mandatory", contract)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixed_label = copy.deepcopy(self.blueprint)
            fixed_scenario = next(
                item
                for item in fixed_label["scenarios"]
                if item["id"] == scenario["id"]
            )
            selection = next(
                item
                for item in fixed_scenario["operations"]
                if item["operation"] == "operation:playback.select-subtitle@1"
            )
            selection["arguments"]["trackLabel"] = "fixed-label"
            fixed_path = self._write_blueprint(root / "fixed-label", fixed_label)
            with self.assertRaisesRegex(
                MaterializationError, "discover and select one dynamic track"
            ):
                _validate_blueprint(_load_blueprint(fixed_path))

            unlabeled = copy.deepcopy(self.blueprint)
            unlabeled_scenario = next(
                item
                for item in unlabeled["scenarios"]
                if item["id"] == scenario["id"]
            )
            unlabeled_selection = next(
                item
                for item in unlabeled_scenario["operations"]
                if item["operation"] == "operation:playback.select-subtitle@1"
            )
            unlabeled_selection["arguments"].pop("trackLabel", None)
            unlabeled_path = self._write_blueprint(root / "unlabeled", unlabeled)
            with self.assertRaisesRegex(
                MaterializationError, "discover and select one dynamic track"
            ):
                _validate_blueprint(_load_blueprint(unlabeled_path))

            unbound = copy.deepcopy(self.blueprint)
            unbound_scenario = next(
                item
                for item in unbound["scenarios"]
                if item["id"] == scenario["id"]
            )
            unbound_capture = next(
                item
                for item in unbound_scenario["operations"]
                if item["operation"] == "operation:evidence.capture-frames@1"
            )
            unbound_capture["arguments"].pop("relatedResults", None)
            unbound_path = self._write_blueprint(root / "unbound-capture", unbound)
            with self.assertRaisesRegex(
                MaterializationError, "bound to its own selection observation"
            ):
                _validate_blueprint(_load_blueprint(unbound_path))

            bypassed_oracle = copy.deepcopy(self.blueprint)
            bypassed_scenario = next(
                item
                for item in bypassed_oracle["scenarios"]
                if item["id"] == scenario["id"]
            )
            bypassed_scenario["obligations"][0]["producedByCall"] = (
                "call:local-media-lifecycle:external-subtitle-source-matrix:05"
            )
            bypassed_path = self._write_blueprint(
                root / "bypassed-oracle", bypassed_oracle
            )
            with self.assertRaisesRegex(
                MaterializationError, "mandatory Oracle adjudication"
            ):
                _validate_blueprint(_load_blueprint(bypassed_path))

    def test_subtitle_selection_semantic_failures_are_successful_observations(self) -> None:
        backend = operation_adapter.ResidentOperationBackend()
        context = object()
        state = {
            "succeeded": True,
            "response": {"success": True},
            "fields": {
                "collectionOrigin": "mediaLibrary",
                "playbackAddressKind": "local-file",
                "session": "session-1",
                "mediaName": "sdr-bframe-aggregate-30s.mkv",
                "sourceIdentity": "sha256:" + "1" * 64,
                "contentRevision": "sha256:" + "2" * 64,
                "subtitleTrack": "off",
                "lifecycle": "playing",
                "transition": "none",
                "error": "none",
            },
        }
        arguments = {
            "host": "playerUI",
            "sourceKind": "local-sidecar",
            "deadlineSeconds": 30,
        }
        candidate = {
            "id": "external.subtitle.directory.0",
            "label": "Chinese (Simplified)",
            "sourceKind": "local-sidecar",
            "isSelected": False,
        }

        with (
            mock.patch.object(
                backend,
                "_subtitle_window_state",
                return_value=state,
            ),
            mock.patch.object(
                backend,
                "_select_public_subtitle_item",
                return_value=({"success": False}, None),
            ),
        ):
            missing = backend._playback_select_subtitle_1(arguments, context)
        self.assertTrue(missing["succeeded"])
        self.assertEqual(missing["semanticOutcome"], "candidate-missing")
        self.assertFalse(missing["selectionSettled"])

        selection_response = {"success": True}
        arguments["deadlineSeconds"] = 1
        with (
            mock.patch.object(
                backend,
                "_subtitle_window_state",
                return_value=state,
            ),
            mock.patch.object(
                backend,
                "_select_public_subtitle_item",
                return_value=(selection_response, candidate),
            ),
        ):
            unsettled = backend._playback_select_subtitle_1(arguments, context)
        self.assertTrue(unsettled["succeeded"])
        self.assertEqual(unsettled["semanticOutcome"], "selection-not-settled")
        self.assertFalse(unsettled["selectionSettled"])

    def test_fail_closed_media_guard_rejects_all_retired_fake_basenames(self) -> None:
        retired = (
            "catalog-v2-buffered-reconnect-buffer-absorbed-interruption.mkv",
            "catalog-v2-buffered-reconnect-paired-control.mkv",
            "catalog-v2-issue-first.mkv",
            "catalog-v2-issue-second.mkv",
            "catalog-v2-playback-failure-access-refused.mkv",
            "catalog-v2-playback-failure-connection-interrupted.mkv",
            "catalog-v2-playback-failure-data-corrupt.mkv",
            "catalog-v2-playback-failure-file-missing.mkv",
            "catalog-v2-unsupported-codec.mkv",
        )
        encoded = json.dumps(self.blueprint)
        self.assertTrue(all(name not in encoded for name in retired))
        template = next(
            call
            for scenario in self.blueprint["scenarios"]
            for call in scenario["operations"]
            if call["operation"] == "operation:media.open@2"
            and call["arguments"]["identifier"].startswith(
                "MediaLibrary-grid-video-"
            )
        )
        for basename in retired:
            with self.subTest(basename=basename):
                scenarios = copy.deepcopy(self.blueprint["scenarios"])
                call = next(
                    candidate
                    for scenario in scenarios
                    for candidate in scenario["operations"]
                    if candidate["callId"] == template["callId"]
                )
                call["arguments"]["identifier"] = (
                    "MediaLibrary-grid-video-" + basename
                )
                with self.assertRaisesRegex(
                    MaterializationError,
                    "unregistered media basename",
                ):
                    _validate_registered_media_basenames(scenarios)

    def test_declared_time_budgets_cover_all_sequential_waits(self) -> None:
        _validate_scenario_time_bounds(self.blueprint["scenarios"])
        scenarios = copy.deepcopy(self.blueprint["scenarios"])
        scenario = next(
            item for item in scenarios
            if item["id"]
            == "scenario:local-media-lifecycle:clean-start-position-zero"
        )
        scenario["estimatedCostMillis"] = 0
        with self.assertRaisesRegex(
            MaterializationError,
            "estimatedCostMillis is below its declared sequential waits",
        ):
            _validate_scenario_time_bounds(scenarios)

    def test_canonical_delivery_rubrics_name_runtime_fields(self) -> None:
        rubrics = {item["id"]: item for item in self.blueprint["rubrics"]}
        audio = json.dumps(
            rubrics["rubric:format-coverage.audio-delivery-codec-matrix.o01@1"]
        )
        for field in (
            "audioProviderKind",
            "audioDeliveryMediaSubtype",
            "audioDeliveryTimestampsMonotonic",
        ):
            self.assertIn(field, audio)
        dynamic = " ".join(
            json.dumps(rubrics[identifier])
            for identifier in (
                "rubric:dynamic-range-interpretation.hdr10-hlg-interpretation.o01@1",
                "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1",
                "rubric:dynamic-range-interpretation.dolby-vision-cross-compatibility-switch.o01@1",
            )
        )
        for field in (
            "sampleTransferFunction",
            "rendererTransferFunction",
            "dolbyVisionCrossCompatibilityID",
            "sourceHasDvcC",
            "rendererHasDvvC",
        ):
            self.assertIn(field, dynamic)

    def test_semantic_authority_corrections_are_literal_contract_data(self) -> None:
        promises = {item["id"]: item["statement"] for item in self.blueprint["promises"]}
        self.assertIn("without an Ask Every Time resume prompt", promises["promise:playback-queue:c01"])
        self.assertIn("rehomes contained media references to its parent", promises["promise:library-management:c02"])
        self.assertIn("typed, codec-specific guidance", promises["promise:format-support:c01"])

        scenario_by_id = {item["id"]: item for item in self.blueprint["scenarios"]}
        self.assertIn("scenario:library-management:photo-picker-import-route", scenario_by_id)
        photo = scenario_by_id["scenario:library-management:photo-picker-import-route"]
        self.assertEqual(photo["readiness"], "ready")
        self.assertFalse(photo["blockers"])
        self.assertIn(
            "operation:input.device-hub-pinch@2",
            {item["operation"] for item in photo["operations"]},
        )

        rubric_text = "\n".join(
            text
            for rubric in self.blueprint["rubrics"]
            for text in rubric["criteria"] + rubric["negativeControls"]
        )
        self.assertIn("45000 ms", rubric_text)
        self.assertIn("90000 ms is only the harness liveness deadline", rubric_text)
        self.assertIn("Retry and Close", rubric_text)
        self.assertIn("generic playbackFailed", rubric_text)

    def test_exact_eight_reviewed_additions_are_present(self) -> None:
        self.assertEqual(
            {item["id"] for item in self.blueprint["promises"]},
            {
                "promise:format-support:c01",
                "promise:issue-surface:c01",
                "promise:library-management:c01",
                "promise:library-management:c02",
                "promise:library-management:c03",
                "promise:library-management:c04",
                "promise:library-management:c05",
                "promise:playback-queue:c01",
            },
        )
        scenario_ids = {item["id"] for item in self.blueprint["scenarios"]}
        self.assertTrue(
            {
                "scenario:format-coverage:unsupported-codec-guidance",
                "scenario:issue-surface-behavior:typed-single-slot-contract",
                "scenario:library-management:folder-naming",
                "scenario:library-management:folder-delete-rehomes-references",
                "scenario:library-management:move-references",
                "scenario:library-management:confirmed-batch-deletion",
                "scenario:library-management:current-folder-search-counts",
                "scenario:local-media-lifecycle:automatic-play-next-resume-policy",
            }
            <= scenario_ids
        )

    def test_each_static_case_has_one_semantic_artifact_per_obligation_family(self) -> None:
        for scenario in self.blueprint["scenarios"]:
            cases = scenario["staticCases"]
            obligations = scenario["obligations"]
            bound_cases = [item["caseKey"] for item in obligations]
            multiplier = (
                2
                if scenario["id"]
                in {
                    "scenario:local-media-lifecycle:clean-flat-playback-main-gate",
                    "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
                    "scenario:webdav-source-lifecycle:certificate-trust-boundary",
                    "scenario:issue-surface-behavior:typed-single-slot-contract",
                }
                else 1
            )
            self.assertEqual(len(obligations), len(cases) * multiplier, scenario["id"])
            self.assertEqual(set(bound_cases), set(cases), scenario["id"])
            if scenario["readiness"] == "ready":
                self.assertTrue(
                    all(item["producedByCall"] is not None for item in obligations)
                )
            else:
                self.assertTrue(all(item["producedByCall"] is None for item in obligations))
            self.assertNotIn("evidence-bundle", json.dumps(obligations))

    def test_state_requirements_preserve_journey_semantics_and_use_registered_v2_contracts(self) -> None:
        registered_state = {
            (spec.state_key, spec.state_schema)
            for spec in preparation_adapter.PREPARATION_REGISTRY.values()
        }
        journeys = {item["id"]: item for item in self.blueprint["journeys"]}
        for journey in journeys.values():
            self.assertEqual(len(journey["sharedState"]), 1, journey["id"])
            requirement = journey["sharedState"][0]
            self.assertIn(
                (requirement["key"], requirement["schema"]),
                registered_state,
                journey["id"],
            )
            self.assertTrue(requirement["schema"].endswith("@2"), journey["id"])

        for scenario in self.blueprint["scenarios"]:
            shared = {
                (item["key"], item["schema"])
                for item in journeys[scenario["journey"]]["sharedState"]
            }
            prerequisites = {
                (item["key"], item["schema"])
                for item in scenario["prerequisites"]
            }
            operations = {item["operation"] for item in scenario["operations"]}
            structural_only = operations == {"operation:evidence.structural-test@1"}
            if structural_only and not prerequisites:
                self.assertEqual(
                    scenario["id"],
                    "scenario:format-coverage:audio-retirement-on-failure",
                )
            else:
                self.assertTrue(shared <= prerequisites, scenario["id"])

    def test_only_runtime_complete_scenarios_are_ready_and_bind_exact_producers(self) -> None:
        ready = {
            item["id"] for item in self.blueprint["scenarios"] if item["readiness"] == "ready"
        }
        gaps = {
            item["id"]
            for item in self.blueprint["scenarios"]
            if item["readiness"] == "implementation-gap"
        }
        self.assertEqual(gaps, set(GAP_SCENARIO_CAPABILITIES))
        self.assertEqual(len(ready), 65)
        operation_shapes = {
            item["id"]: item for item in operation_adapter.catalog_operation_shapes()
        }
        for scenario in self.blueprint["scenarios"]:
            calls = {item["callId"]: item for item in scenario["operations"]}
            if scenario["id"] in GAP_SCENARIO_CAPABILITIES:
                self.assertFalse(calls, scenario["id"])
                self.assertEqual(
                    tuple(item["capability"] for item in scenario["blockers"]),
                    GAP_SCENARIO_CAPABILITIES[scenario["id"]],
                )
                self.assertTrue(
                    all(item["producedByCall"] is None for item in scenario["obligations"]),
                    scenario["id"],
                )
                continue

            self.assertFalse(scenario["blockers"], scenario["id"])
            self.assertTrue(calls, scenario["id"])
            concrete_lanes = {
                "device": ("device",),
                "simulator": ("simulator",),
                "either": ("device", "simulator"),
                "both": ("device", "simulator"),
            }[scenario["lane"]]
            for call in calls.values():
                spec = operation_adapter.SPECS[call["operation"]]
                for lane in concrete_lanes:
                    spec.validate(lane, call["arguments"])
            for obligation in scenario["obligations"]:
                producer = calls[obligation["producedByCall"]]
                self.assertIn(
                    {
                        "evidenceType": obligation["evidenceType"],
                        "evidenceSchema": obligation["evidenceSchema"],
                    },
                    operation_shapes[producer["operation"]]["evidenceSchemas"],
                    obligation["id"],
                )

    def test_every_scenario_has_a_closed_concrete_call_graph(self) -> None:
        operation_ids = set(operation_adapter.SPECS)
        global_call_ids: set[str] = set()
        for scenario in self.blueprint["scenarios"]:
            if scenario["readiness"] == "implementation-gap":
                self.assertIn(scenario["id"], GAP_SCENARIO_CAPABILITIES)
                self.assertFalse(scenario["operations"], scenario["id"])
                continue
            self.assertFalse(scenario["blockers"], scenario["id"])
            self.assertTrue(scenario["operations"], scenario["id"])
            local_call_ids = [call["callId"] for call in scenario["operations"]]
            self.assertEqual(
                len(local_call_ids), len(set(local_call_ids)), scenario["id"]
            )
            self.assertFalse(global_call_ids & set(local_call_ids), scenario["id"])
            global_call_ids.update(local_call_ids)
            seen: set[str] = set()
            prefix = "call:" + scenario["id"].removeprefix("scenario:") + ":"
            for index, call in enumerate(scenario["operations"], 1):
                self.assertEqual(call["callId"], f"{prefix}{index:02d}")
                self.assertIn(call["operation"], operation_ids, call["callId"])
                self.assertEqual(call["maxInvocations"], 1, call["callId"])
                for value in self._strings(call["arguments"]):
                    if not value.startswith("result://"):
                        continue
                    match = RESULT_REFERENCE.fullmatch(value)
                    self.assertIsNotNone(match, call["callId"])
                    assert match is not None
                    self.assertIn(match.group(1), seen, call["callId"])
                seen.add(call["callId"])
            self.assertTrue(
                all(
                    obligation["producedByCall"] in local_call_ids
                    for obligation in scenario["obligations"]
                ),
                scenario["id"],
            )
            call_index = {
                call_id: index for index, call_id in enumerate(local_call_ids)
            }
            case_producers = [
                [
                    obligation["producedByCall"]
                    for obligation in scenario["obligations"]
                    if obligation["caseKey"] == case
                ]
                for case in scenario["staticCases"]
            ]
            self.assertTrue(all(case_producers), scenario["id"])
            flattened = [producer for group in case_producers for producer in group]
            self.assertEqual(len(flattened), len(set(flattened)), scenario["id"])
            self.assertEqual(
                [min(call_index[producer] for producer in group) for group in case_producers],
                sorted(min(call_index[producer] for producer in group) for group in case_producers),
                scenario["id"],
            )

    def test_local_media_calls_are_staged_by_lane_prerequisites(self) -> None:
        _validate_blueprint(self.blueprint)

        tampered = copy.deepcopy(self.blueprint)
        call = next(
            call
            for scenario in tampered["scenarios"]
            for call in scenario["operations"]
            if call["operation"] == "operation:media.open@2"
            and call["arguments"]["identifier"].startswith(
                "MediaLibrary-grid-video-"
            )
        )
        call["arguments"]["identifier"] = (
            "MediaLibrary-grid-video-unregistered.mp4"
        )
        with self.assertRaisesRegex(
            MaterializationError,
            r"names unregistered media basename unregistered\.mp4",
        ):
            _validate_blueprint(tampered)

        missing_import = copy.deepcopy(self.blueprint)
        scenario = next(
            item
            for item in missing_import["scenarios"]
            if item["id"]
            == "scenario:local-media-lifecycle:clean-start-position-zero"
        )
        scenario["operations"] = [
            call
            for call in scenario["operations"]
            if call["operation"] != "operation:media.import-staged@2"
        ]
        with self.assertRaisesRegex(
            MaterializationError,
            "was not imported by a prerequisite Preparation or earlier Scenario call",
        ):
            _validate_blueprint(missing_import)

    def test_high_risk_playback_scenarios_drive_the_claimed_semantics(self) -> None:
        scenarios = {item["id"]: item for item in self.blueprint["scenarios"]}

        codec = scenarios["scenario:format-coverage:audio-delivery-codec-matrix"]
        self.assertEqual(
            [
                call["arguments"]["identifiers"]
                for call in codec["operations"]
                if call["operation"] == "operation:accessibility.activate@2"
            ],
            [
                [
                    "PlayerUI-TopAction-more",
                    "PlayerUI-menu-audio",
                    f"PlayerUI-menu-audio-{track}",
                ]
                for track in (2, 3, 1, 8)
            ],
        )
        self.assertTrue(
            all(
                call["arguments"].get("summonControls") is True
                for call in codec["operations"]
                if call["operation"] == "operation:accessibility.activate@2"
            ),
            "every codec-matrix menu activation summons the chrome it then taps",
        )

        audio = scenarios[
            "scenario:local-media-lifecycle:audio-track-switch-same-session"
        ]
        self.assertEqual(
            [
                call["arguments"]["identifier"]
                for call in audio["operations"]
                if call["operation"] == "operation:media.open@2"
            ],
            [
                "MediaLibrary-grid-video-"
                "sdr-bframe-duplicate-label-audio-30s.mkv"
            ],
        )
        self.assertEqual(
            sum(call["operation"] == "operation:app.relaunch@1" for call in audio["operations"]),
            1,
        )
        baseline = next(
            call
            for call in audio["operations"]
            if call["operation"] == "operation:diagnostics.playback-state@1"
        )
        audio_captures = [
            call for call in audio["operations"]
            if call["operation"] == "operation:evidence.capture-audio@2"
        ]
        self.assertEqual(
            [call["arguments"]["expectedAudioTrackID"] for call in audio_captures],
            ["1", "2", "3"],
        )
        self.assertEqual(
            {call["arguments"]["expectedSession"] for call in audio_captures},
            {f"result://{baseline['callId']}/session"},
        )

        subtitles = scenarios[
            "scenario:local-media-lifecycle:subtitle-switch-and-off"
        ]
        self.assertEqual(
            sum(call["operation"] == "operation:app.relaunch@1" for call in subtitles["operations"]),
            1,
        )
        self.assertEqual(
            sum(call["operation"] == "operation:media.open@2" for call in subtitles["operations"]),
            1,
        )
        self.assertEqual(
            [
                identifier
                for call in subtitles["operations"]
                if call["operation"] == "operation:accessibility.activate@2"
                for identifier in call["arguments"]["identifiers"]
                if identifier.startswith("PlayerUI-menu-subtitles-")
            ],
            [
                "PlayerUI-menu-subtitles-ffmpeg.subtitle.3",
                "PlayerUI-menu-subtitles-ffmpeg.subtitle.5",
                "PlayerUI-menu-subtitles-off",
                "PlayerUI-menu-subtitles-ffmpeg.subtitle.3",
            ],
        )

        panorama = scenarios[
            "scenario:projection-and-stereo:panorama-coverage-angle"
        ]
        self.assertEqual(
            [
                call["arguments"]["horizontalCoverageDegrees"]
                for call in panorama["operations"]
                if call["operation"] == "operation:format.apply@2"
                and call["arguments"]["projection"] == "customAngle"
            ],
            [200, 240],
        )

        play_next = scenarios[
            "scenario:local-media-lifecycle:automatic-play-next-resume-policy"
        ]
        imported = [
            call["arguments"]["fileName"]
            for call in play_next["operations"]
            if call["operation"] == "operation:media.import-staged@2"
        ]
        self.assertEqual(
            imported,
            [
                "sdr-bframe-multiaudio-avsync-30s.mp4",
                "viewing-storage-16m01s.mp4",
            ],
        )
        baseline = next(
            call
            for call in play_next["operations"]
            if call["operation"] == "operation:diagnostics.playback-state@1"
        )
        wait = next(
            call
            for call in play_next["operations"]
            if call["operation"] == "operation:playback.wait-position@2"
            and "differentSessionFrom" in call["arguments"]
        )
        self.assertEqual(
            wait["arguments"]["expectedMediaName"],
            "viewing-storage-16m01s.mp4",
        )
        self.assertEqual(
            wait["arguments"]["differentSessionFrom"],
            f"result://{baseline['callId']}/session",
        )
        play_next_rubric = next(
            rubric
            for rubric in self.blueprint["rubrics"]
            if rubric["id"]
            == "rubric:local-media-lifecycle.automatic-play-next-resume-policy.o01@1"
        )
        rubric_text = "\n".join(
            play_next_rubric["criteria"] + play_next_rubric["negativeControls"]
        )
        self.assertIn("resumePromptPresentations=1", rubric_text)
        self.assertIn("automaticResumeBypasses=1", rubric_text)
        self.assertIn("pendingResumePrompt=false", rubric_text)

        tampered = copy.deepcopy(self.blueprint)
        audio = next(
            scenario
            for scenario in tampered["scenarios"]
            if scenario["id"]
            == "scenario:local-media-lifecycle:audio-track-switch-same-session"
        )
        capture = next(
            call
            for call in audio["operations"]
            if call["operation"] == "operation:evidence.capture-audio@2"
        )
        capture["arguments"]["expectedAudioTrackID"] = "9"
        with self.assertRaisesRegex(
            MaterializationError,
            "audio capture does not bind all three tracks to one session",
        ):
            _validate_blueprint(tampered)

    def _strings(self, value: object):
        if isinstance(value, str):
            yield value
        elif isinstance(value, list):
            for item in value:
                yield from self._strings(item)
        elif isinstance(value, dict):
            for item in value.values():
                yield from self._strings(item)

    def test_no_generic_scenario_producer_placeholder_remains(self) -> None:
        placeholders = [
            (scenario["id"], blocker["capability"])
            for scenario in self.blueprint["scenarios"]
            for blocker in scenario["blockers"]
            if blocker["capability"].startswith("producer:")
        ]
        self.assertEqual(placeholders, [])
        tampered = copy.deepcopy(self.blueprint)
        scenario = tampered["scenarios"][0]
        scenario["readiness"] = "implementation-gap"
        scenario["operations"] = []
        scenario["blockers"] = [
            {
                "kind": "implementation-gap",
                "capability": "producer:" + scenario["id"],
                "detail": "Generic producers are not a typed implementation gap.",
            }
        ]
        for obligation in scenario["obligations"]:
            obligation["producedByCall"] = None
        with tempfile.TemporaryDirectory() as temporary:
            path = self._write_blueprint(Path(temporary), tampered)
            with self.assertRaisesRegex(
                MaterializationError, "generic producer blocker"
            ):
                _validate_blueprint(_load_blueprint(path))

    def test_rejects_dangling_obligation_producers(self) -> None:
        tampered = copy.deepcopy(self.blueprint)
        scenario = next(
            item for item in tampered["scenarios"] if item["readiness"] == "ready"
        )
        scenario["obligations"][0]["producedByCall"] = "call:other:01"
        with tempfile.TemporaryDirectory() as temporary:
            path = self._write_blueprint(Path(temporary), tampered)
            with self.assertRaisesRegex(MaterializationError, "lacks an exact producer"):
                _validate_blueprint(_load_blueprint(path))

    def test_ready_scenarios_use_ordered_real_calls_and_narrow_evidence(self) -> None:
        scenarios = {item["id"]: item for item in self.blueprint["scenarios"]}

        imported = scenarios[
            "scenario:local-media-lifecycle:injected-import-rejoins-ingest"
        ]
        imported_calls = {item["callId"]: item for item in imported["operations"]}
        self.assertEqual(
            [item["operation"] for item in imported["operations"]],
            [
                "operation:media.import-staged@2",
                "operation:library.snapshot@1",
                "operation:app.relaunch@1",
                "operation:navigation.select-tab@1",
                "operation:accessibility.inspect@2",
            ],
        )
        self.assertEqual(
            {
                (item["evidenceType"], item["evidenceSchema"])
                for item in imported["obligations"]
            },
            {
                ("library.command", "library-command@1"),
                ("accessibility.tree", "accessibility-tree@1"),
            },
        )

        self.assertEqual(
            {
                imported_calls[item["producedByCall"]]["operation"]
                for item in imported["obligations"]
            },
            {
                "operation:library.snapshot@1",
                "operation:accessibility.inspect@2",
            },
        )

        clean_start = scenarios[
            "scenario:local-media-lifecycle:clean-start-position-zero"
        ]
        self.assertEqual(
            clean_start["operations"][0]["operation"],
            "operation:harness.reset-product-state@2",
        )
        producer = clean_start["obligations"][0]["producedByCall"]
        self.assertEqual(
            next(item for item in clean_start["operations"] if item["callId"] == producer)[
                "operation"
            ],
            "operation:diagnostics.playback-state@1",
        )

        retirement = scenarios[
            "scenario:format-coverage:audio-retirement-on-failure"
        ]
        expected_checks = [
            "audio-retirement-open",
            "audio-retirement-prewarm",
            "audio-retirement-playback",
            "audio-retirement-seek",
            "audio-retirement-renderer",
        ]
        self.assertEqual(
            [item["operation"] for item in retirement["operations"]],
            ["operation:evidence.structural-test@1"] * 5,
        )
        self.assertEqual(
            [item["arguments"]["check"] for item in retirement["operations"]],
            expected_checks,
        )
        self.assertEqual(retirement["prerequisites"], [])
        self.assertEqual(
            {
                (item["caseKey"], item["evidenceType"], item["evidenceSchema"], item["oracle"])
                for item in retirement["obligations"]
            },
            {
                (
                    case,
                    "structural.test",
                    "structural-test@2",
                    "oracle:agent-structured-structural-test@2",
                )
                for case in ("open", "prewarm", "playback", "seek", "renderer")
            },
        )

    def test_remote_scenarios_bind_ui_identity_product_state_and_restored_receipts(self) -> None:
        scenarios = {item["id"]: item for item in self.blueprint["scenarios"]}
        remote_ids = {
            "scenario:webdav-source-lifecycle:webdav-add-source",
            "scenario:webdav-source-lifecycle:webdav-open-through-loopback",
            "scenario:webdav-source-lifecycle:certificate-trust-boundary",
            "scenario:network-resilience:recoverable-read-resumes-from-checkpoint",
            "scenario:network-resilience:finite-backoff-reconnect",
            "scenario:network-resilience:buffered-reconnect-has-no-indicator",
        }
        for identifier in remote_ids:
            scenario = scenarios[identifier]
            self.assertEqual(scenario["readiness"], "ready")
            self.assertFalse(scenario["blockers"])
            self.assertTrue(scenario["operations"])
            for call in scenario["operations"]:
                if call["operation"] == "operation:accessibility.type@2" and call[
                    "arguments"
                ].get("secret") is True:
                    self.assertNotIn("text", call["arguments"])
                    self.assertEqual(call["arguments"]["textJSONKey"], "password")

        added = scenarios["scenario:webdav-source-lifecycle:webdav-add-source"]
        runtime_call = next(
            call
            for call in added["operations"]
            if call["operation"] == "operation:host.preflight@1"
        )
        typed = [
            call
            for call in added["operations"]
            if call["operation"] == "operation:accessibility.type@2"
            and "textFile" in call["arguments"]
        ]
        self.assertEqual(
            {call["arguments"]["textJSONKey"] for call in typed},
            {"address", "user", "password"},
        )
        self.assertEqual(
            {call["arguments"]["textFile"] for call in typed},
            {f"result://{runtime_call['callId']}/runtimePath"},
        )

        opened = scenarios[
            "scenario:webdav-source-lifecycle:webdav-open-through-loopback"
        ]
        playback_binding = next(
            call
            for call in opened["operations"]
            if call["operation"] == "operation:diagnostics.playback-state@1"
            and call["arguments"].get("expectation") == "webdav-loopback"
        )
        frame_call = next(
            call
            for call in opened["operations"]
            if call["operation"] == "operation:evidence.capture-frames@1"
        )
        self.assertEqual(
            frame_call["arguments"]["productBindingDigest"],
            f"result://{playback_binding['callId']}/bindingDigest",
        )
        self.assertEqual(
            frame_call["arguments"]["remoteExpectation"],
            "webdav-playback-range",
        )

        buffered = scenarios[
            "scenario:network-resilience:buffered-reconnect-has-no-indicator"
        ]
        buffered_bindings = [
            call
            for call in buffered["operations"]
            if call["operation"] == "operation:diagnostics.playback-state@1"
            and call["arguments"].get("expectation") == "webdav-loopback"
        ]
        buffered_frames = [
            call
            for call in buffered["operations"]
            if call["operation"] == "operation:evidence.capture-frames@1"
        ]
        self.assertEqual(len(buffered_bindings), 2)
        self.assertEqual(len(buffered_frames), 2)
        self.assertEqual(
            [call["arguments"]["productBindingDigest"] for call in buffered_frames],
            [
                f"result://{buffered_bindings[0]['callId']}/bindingDigest",
                f"result://{buffered_bindings[1]['callId']}/bindingDigest",
            ],
        )
        self.assertEqual(
            [item["producedByCall"] for item in buffered["obligations"]],
            [call["callId"] for call in buffered_frames],
        )
        call_positions = {
            call["callId"]: index
            for index, call in enumerate(buffered["operations"])
        }
        for binding, frame in zip(
            buffered_bindings,
            buffered_frames,
        ):
            self.assertLess(
                call_positions[binding["callId"]],
                call_positions[frame["callId"]],
            )

        certificate = scenarios[
            "scenario:webdav-source-lifecycle:certificate-trust-boundary"
        ]
        trace = next(
            call
            for call in certificate["operations"]
            if call["operation"] == "operation:diagnostics.surface-probe@1"
            and call["arguments"].get("remoteExpectation")
        )
        self.assertEqual(
            trace["arguments"]["remoteExpectation"],
            "certificate-trust-boundary",
        )
        self.assertTrue(
            any(
                call["operation"] == "operation:accessibility.activate@2"
                and call["arguments"].get("identifiers", [])[-1:]
                == ["FileBrowsing-CertificateTrust-cancel"]
                for call in certificate["operations"]
            )
        )

        for scenario_id, recipe, expectation, reconnects in (
            (
                "scenario:network-resilience:recoverable-read-resumes-from-checkpoint",
                "recoverable-read-interruption",
                "recoverable-read",
                1,
            ),
            (
                "scenario:network-resilience:finite-backoff-reconnect",
                "finite-reconnect",
                "finite-backoff",
                3,
            ),
        ):
            scenario = scenarios[scenario_id]
            activation = next(
                call
                for call in scenario["operations"]
                if call["operation"] == "operation:host.preflight@1"
                and call["arguments"].get("phase") == "activate"
            )
            restore = next(
                call
                for call in scenario["operations"]
                if call["operation"] == "operation:host.preflight@1"
                and call["arguments"].get("phase") == "restore"
            )
            final_state = next(
                call
                for call in scenario["operations"]
                if call["operation"] == "operation:diagnostics.playback-state@1"
                and call["arguments"].get("expectation")
            )
            trace = next(
                call
                for call in scenario["operations"]
                if call["operation"] == "operation:diagnostics.surface-probe@1"
                and call["arguments"].get("remoteExpectation")
            )
            self.assertEqual(activation["arguments"]["recipe"], recipe)
            self.assertEqual(
                restore["arguments"]["receiptID"],
                f"result://{activation['callId']}/receiptID",
            )
            self.assertEqual(final_state["arguments"]["minimumReconnects"], reconnects)
            self.assertEqual(trace["arguments"]["remoteExpectation"], expectation)
            self.assertEqual(
                trace["arguments"]["restoredGenerationToken"],
                f"result://{restore['callId']}/restoredGenerationToken",
            )
            self.assertEqual(
                trace["arguments"]["productBindingDigest"],
                f"result://{final_state['callId']}/bindingDigest",
            )

    def test_direct_accessibility_actuator_declares_reviewed_invalidation_union(self) -> None:
        operations = {item["id"]: item for item in self.blueprint["operations"]}
        self.assertEqual(
            set(
                operations["operation:accessibility.activate@2"][
                    "invalidatesTags"
                ]
            ),
            {
                "cache.state",
                "certificate.trust",
                "issue.surface",
                "library.contents",
                "media.format",
                "playback.position",
                "playback.selection",
                "playback.session",
                "presentation.state",
                "renderer.graph",
                "settings.state",
                "source.session",
                "ui.navigation",
                "ui.state",
                "viewing.state",
            },
        )

    def test_source_failure_cases_drive_real_webdav_form_without_secret_literals(self) -> None:
        scenario = next(
            item
            for item in self.blueprint["scenarios"]
            if item["id"]
            == "scenario:issue-surface-behavior:source-failure-guidance-matrix"
        )
        self.assertEqual(scenario["readiness"], "ready")
        self.assertFalse(scenario["blockers"])
        calls = scenario["operations"]
        self.assertEqual(len(calls), 40)
        self.assertEqual(
            [item["producedByCall"] for item in scenario["obligations"]],
            [calls[index]["callId"] for index in (9, 19, 29, 39)],
        )
        for offset in (0, 10, 20, 30):
            self.assertEqual(
                calls[offset]["operation"], "operation:host.preflight@1"
            )
            self.assertEqual(
                calls[offset + 9]["arguments"]["identifier"],
                "FileBrowsing-SourceConnection-webDAV-error",
            )

        self.assertNotIn(
            "operation:harness.reset-product-state@2",
            {call["operation"] for call in calls},
        )
        password_calls = [
            call
            for call in calls
            if call["operation"] == "operation:accessibility.type@2"
            and call["arguments"]["identifier"].endswith("-password")
        ]
        self.assertEqual(len(password_calls), 4)
        self.assertTrue(all(call["arguments"]["secret"] for call in password_calls))
        self.assertTrue(
            all("text" not in call["arguments"] for call in password_calls)
        )

    def test_artwork_exit_uses_exact_byte_bound_four_frame_variant(self) -> None:
        scenario = next(
            item
            for item in self.blueprint["scenarios"]
            if item["id"]
            == "scenario:local-media-lifecycle:artwork-captured-on-exit"
        )
        self.assertEqual(scenario["readiness"], "ready")
        self.assertFalse(scenario["blockers"])
        self.assertEqual(
            scenario["operations"][0],
            {
                "arguments": {"target": "artwork-cache"},
                "callId": "call:local-media-lifecycle:artwork-captured-on-exit:01",
                "maxInvocations": 1,
                "operation": "operation:storage.clear@1",
            },
        )
        prefix = "call:local-media-lifecycle:artwork-captured-on-exit"
        captures = [
            call
            for call in scenario["operations"]
            if call["operation"] == "operation:evidence.capture-frames@1"
        ]


        for call in captures:
            arguments = call["arguments"]
            self.assertEqual(
                arguments["artworkExpectation"], "exit-replaces-current-frame"
            )
            self.assertEqual(arguments["context"], "window")
            self.assertEqual(arguments["count"], 4)
            self.assertEqual(arguments["minimumIntervalMillis"], 0)
        exits = [
            call
            for call in scenario["operations"]
            if call["operation"] == "operation:accessibility.activate@2"
            and call["arguments"].get("identifiers")
            == ["PlayerUI-InfoBar-button-back"]
        ]

        self.assertEqual(len(exits), 2)
        self.assertEqual(len(captures), 4)
        self.assertTrue(all(call["arguments"]["summonControls"] for call in exits))
        waits = [
            call["arguments"]["minimumPositionMillis"]
            for call in scenario["operations"]
            if call["operation"] == "operation:playback.wait-position@2"
        ]
        self.assertEqual(len(waits), 2)
        self.assertLess(waits[0], waits[1])
        producer = scenario["obligations"][0]["producedByCall"]
        self.assertEqual(producer, captures[-1]["callId"])
        capture = captures[-1]

        first_key = f"result://{captures[0]['callId']}/artworkKey"
        self.assertEqual(
            [call["arguments"].get("artworkKey") for call in captures],
            [None, first_key, first_key, first_key],
        )
        self.assertEqual(
            capture["arguments"]["relatedFrameManifests"],
            [f"result://{call['callId']}/frameManifest" for call in captures[:-1]],
        )
        self.assertTrue(
            all(
                value.startswith(f"result://{prefix}:")
                for value in capture["arguments"]["relatedResults"]
            )
        )

    def test_local_index_scenario_uses_empty_local_phases_and_remote_positive_control(self) -> None:
        scenario = next(
            item
            for item in self.blueprint["scenarios"]
            if item["id"]
            == "scenario:viewing-state-and-storage:local-playback-does-not-write-index"
        )
        self.assertEqual(scenario["readiness"], "ready")
        self.assertFalse(scenario["blockers"])
        calls = scenario["operations"]
        probes = [
            call
            for call in calls
            if call["operation"] == "operation:diagnostics.surface-probe@1"
        ]
        self.assertEqual(
            [call["arguments"]["containerIndexExpectation"] for call in probes],
            [
                "baseline-empty",
                "local-active-empty",
                "local-after-empty",
                "remote-positive-control",
            ],
        )
        baseline = probes[0]["callId"]
        local_active = probes[1]["callId"]
        local_after = probes[2]["callId"]
        self.assertTrue(all(call["arguments"]["includeViewingStorage"] for call in probes))
        self.assertEqual(
            probes[1]["arguments"]["priorViewingStorageDigests"],
            [f"result://{baseline}/viewingStorageDigest"],
        )
        self.assertEqual(
            probes[2]["arguments"]["priorViewingStorageDigests"],
            [
                f"result://{baseline}/viewingStorageDigest",
                f"result://{local_active}/viewingStorageDigest",
            ],
        )
        self.assertEqual(
            probes[1]["arguments"]["expectedBaselineDigest"],
            f"result://{baseline}/containerIndexDigest",
        )
        self.assertEqual(
            probes[2]["arguments"]["expectedBaselineDigest"],
            f"result://{baseline}/containerIndexDigest",
        )


        self.assertLessEqual(
            {
                key: value
                for key, value in probes[3]["arguments"].items()
                if key != "relatedResults"
            }.items(),
            {
                "containerIndexExpectation": "remote-positive-control",
                "expectedBaselineDigest": f"result://{baseline}/containerIndexDigest",
                "expectedLocalActiveDigest": (
                    f"result://{local_active}/containerIndexDigest"
                ),
                "expectedLocalAfterDigest": (
                    f"result://{local_after}/containerIndexDigest"
                ),
                "includeViewingStorage": True,
                "priorViewingStorageDigests": [
                    f"result://{baseline}/viewingStorageDigest",
                    f"result://{local_active}/viewingStorageDigest",
                    f"result://{local_after}/viewingStorageDigest",
                ],
            }.items(),
        )
        self.assertTrue(
            any(
                call["operation"] == "operation:media.open@2"
                and call["arguments"]["identifier"].startswith("MediaLibrary-grid-video-")
                for call in calls
            )
        )
        self.assertTrue(
            any(
                call["operation"] == "operation:media.open@2"
                and call["arguments"]["identifier"].startswith("FileBrowsing-grid-video-")
                for call in calls
            )
        )
        self.assertEqual(
            scenario["obligations"][0]["producedByCall"],
            probes[3]["callId"],
        )

    def test_remote_index_reuse_binds_first_and_second_open_ranges(self) -> None:
        scenario = next(
            item
            for item in self.blueprint["scenarios"]
            if item["id"]
            == "scenario:viewing-state-and-storage:remote-index-reused-on-second-open"
        )
        self.assertEqual(scenario["readiness"], "ready")
        self.assertFalse(scenario["blockers"])
        self.assertEqual(scenario["lane"], "either")
        calls = scenario["operations"]
        self.assertEqual(
            [
                call["arguments"]["target"]
                for call in calls
                if call["operation"] == "operation:storage.clear@1"
            ],
            ["container-index-cache"],
        )
        self.assertEqual(
            [
                call["arguments"]["identifier"]
                for call in calls
                if call["operation"] == "operation:media.open@2"
            ],
            [
                "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
                "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
            ],
        )
        probes = [
            call
            for call in calls
            if call["operation"] == "operation:diagnostics.surface-probe@1"
        ]
        self.assertEqual(
            [call["callId"].rsplit(":", 1)[-1] for call in probes],
            ["02", "09", "11", "17"],
        )
        baseline, first_open, after_exit, second_open = probes
        self.assertEqual(
            baseline["arguments"],
            {
                "awaitEmptyStores": ["container-index"],
                "deadlineSeconds": 30,
                "includeViewingStorage": True,
            },
        )
        self.assertEqual(
            first_open["arguments"]["priorViewingStorageDigests"],
            [f"result://{baseline['callId']}/viewingStorageDigest"],
        )
        self.assertEqual(
            after_exit["arguments"]["priorViewingStorageDigests"],
            [
                f"result://{baseline['callId']}/viewingStorageDigest",
                f"result://{first_open['callId']}/viewingStorageDigest",
            ],
        )
        self.assertEqual(
            second_open["arguments"]["priorViewingStorageDigests"],
            [
                f"result://{baseline['callId']}/viewingStorageDigest",
                f"result://{first_open['callId']}/viewingStorageDigest",
                f"result://{after_exit['callId']}/viewingStorageDigest",
            ],
        )
        self.assertTrue(
            all(call["arguments"]["includeViewingStorage"] is True for call in probes)
        )
        obligation = scenario["obligations"][0]
        self.assertEqual(obligation["producedByCall"], second_open["callId"])
        self.assertEqual(obligation["evidenceType"], "interaction.trace")
        self.assertEqual(obligation["evidenceSchema"], "interaction-trace@1")
        self.assertEqual(
            obligation["oracle"],
            "oracle:agent-structured-interaction-trace@1",
        )

    def test_rejects_tampered_digest_and_nonempty_or_live_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tampered = copy.deepcopy(self.blueprint)
            tampered["expectedCounts"]["operations"] = 34
            path = root / "tampered.json"
            path.write_text(json.dumps(tampered), encoding="utf-8")
            with self.assertRaisesRegex(MaterializationError, "digest mismatch"):
                _load_blueprint(path)

            occupied = root / "occupied"
            occupied.mkdir()
            (occupied / "keep.txt").write_text("keep", encoding="utf-8")
            with self.assertRaisesRegex(MaterializationError, "must be empty"):
                materialize(BLUEPRINT, occupied, root / "occupied-report.json", None)

        with self.assertRaisesRegex(MaterializationError, "live Regression"):
            materialize(BLUEPRINT, LIVE_CATALOG_ROOT, Path("/tmp/never-written.json"), None)

    def test_rejects_v1_ids_bundle_fake_edges_and_runtime_legacy_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cases = []
            retired = copy.deepcopy(self.blueprint)
            retired["operations"][0]["id"] = "operation:evidence.archive@1"
            cases.append((retired, "retired v1 Operation"))

            bundle = copy.deepcopy(self.blueprint)
            bundle["scenarios"][0]["obligations"][0]["evidenceType"] = "evidence-bundle"
            cases.append((bundle, "evidence-bundle is forbidden"))

            fake_edge = copy.deepcopy(self.blueprint)
            fake_edge["journeys"][0]["ordering"].append(
                {"before": fake_edge["journeys"][0]["scenarioRefs"][0], "after": fake_edge["journeys"][0]["scenarioRefs"][1]}
            )
            cases.append((fake_edge, "ordering without a declared shared-state handoff"))

            duplicate_edge = copy.deepcopy(self.blueprint)
            journey = duplicate_edge["journeys"][0]
            duplicate = {
                "before": journey["scenarioRefs"][0],
                "after": journey["scenarioRefs"][1],
            }
            journey["ordering"].extend([duplicate, copy.deepcopy(duplicate)])
            cases.append((duplicate_edge, "ordering without a declared shared-state handoff"))

            legacy_result = copy.deepcopy(self.blueprint)
            legacy_result["scenarios"][0]["title"] = "skipped"
            cases.append((legacy_result, "forbidden runtime"))

            for index, (value, message) in enumerate(cases):
                path = self._write_blueprint(root / f"case-{index}", value)
                with self.assertRaisesRegex(MaterializationError, message):
                    _validate_blueprint(_load_blueprint(path))

    def test_rejects_arbitrary_aliases_and_cross_node_results(self) -> None:
        base = {
            "callId": "call:sample:01",
            "operation": "operation:app.relaunch@1",
            "arguments": {},
            "maxInvocations": 1,
        }
        arbitrary = copy.deepcopy(base)
        arbitrary["arguments"] = {"query": "anything"}
        with self.assertRaisesRegex(MaterializationError, "arbitrary argument"):
            _validate_node_calls("scenario:sample", [arbitrary], set())

        alias = copy.deepcopy(base)
        alias["arguments"] = {"sourceID": "fixture:anything"}
        with self.assertRaisesRegex(MaterializationError, "semantic fixture alias"):
            _validate_node_calls("scenario:sample", [alias], set())

        cross_node = copy.deepcopy(base)
        cross_node["arguments"] = {"sourceID": "result://call:other:01/value"}
        with self.assertRaisesRegex(MaterializationError, "not earlier in the same node"):
            _validate_node_calls("scenario:sample", [cross_node], set())

        malformed = {
            "callId": "call:sample:01",
            "operation": "operation:transition-trace.fetch@1",
            "arguments": {"generationToken": "result://not-a-call/token"},
            "maxInvocations": 1,
        }
        with self.assertRaisesRegex(MaterializationError, "malformed result reference"):
            _validate_node_calls("scenario:sample", [malformed], set(), "device")

        forward = [
            {
                "callId": "call:sample:01",
                "operation": "operation:transition-trace.fetch@1",
                "arguments": {
                    "generationToken": "result://call:sample:02/generationToken"
                },
                "maxInvocations": 1,
            },
            {
                "callId": "call:sample:02",
                "operation": "operation:transition-trace.arm@1",
                "arguments": {},
                "maxInvocations": 1,
            },
        ]
        with self.assertRaisesRegex(MaterializationError, "not earlier in the same node"):
            _validate_node_calls("scenario:sample", forward, set(), "device")

        noncontiguous = copy.deepcopy(base)
        noncontiguous["callId"] = "call:sample:02"
        with self.assertRaisesRegex(MaterializationError, "not contiguous"):
            _validate_node_calls("scenario:sample", [noncontiguous], set())


if __name__ == "__main__":
    unittest.main()
