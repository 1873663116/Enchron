#!/usr/bin/env python3

from __future__ import annotations

import argparse
from contextlib import redirect_stderr
import hashlib
from io import StringIO
from pathlib import Path
from types import SimpleNamespace
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[2]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from regression.core.contracts import ArgumentValueKind, BoundLane, FactDeclaration
from regression.core.digest import canonical_bytes, canonical_digest
from regression.core.ids import FactID
from regression.core.plan import ToolchainIdentity
from regression.core.review import ReviewClass, ReviewUnitKind
from regression.execution_identity import (
    ExecutionIdentityError,
    LinkProvenance,
    PreparedLaneProvenance,
)
from regression.runctl import (
    RunControlError,
    _execute,
    _parser,
    compile_execution_plan,
    derive_reviewed_facts,
    load_blueprint_fact_values,
    main,
)


class RunControlTests(unittest.TestCase):
    @staticmethod
    def command_options(command: str) -> set[str]:
        parser = _parser()
        subparsers = next(
            action
            for action in parser._actions
            if isinstance(action, argparse._SubParsersAction)
        )
        return {
            option
            for action in subparsers.choices[command]._actions
            for option in action.option_strings
        }

    def test_prepare_build_has_the_exact_argument_surface(self) -> None:
        self.assertEqual(
            {"-h", "--help", "--repository-root", "--artifact-root"},
            self.command_options("prepare-build"),
        )
        with redirect_stderr(StringIO()), self.assertRaises(SystemExit) as raised:
            _parser().parse_args(["prepare-build"])
        self.assertEqual(2, raised.exception.code)

    def test_debug_app_target_inherits_the_runtime_provenance_linker_flag(self) -> None:
        project = (
            SCRIPTS.parent / "Enchron.xcodeproj" / "project.pbxproj"
        ).read_text(encoding="utf-8")
        debug = project.split(
            "C3B0F99A2F5726B40064596E /* Debug */ = {", 1
        )[1].split("C3B0F99B2F5726B40064596E /* Release */ = {", 1)[0]
        self.assertIn(
            'OTHER_LDFLAGS = (\n\t\t\t\t\t"$(inherited)",\n'
            '\t\t\t\t\t"$(ENCHRON_REGRESSION_LINK_PROVENANCE_FLAG)",\n'
            "\t\t\t\t);",
            debug,
        )
        self.assertNotIn(".scratch", debug)
        release = project.split(
            "C3B0F99B2F5726B40064596E /* Release */ = {", 1
        )[1].split("C3B0F99C2F5726B40064596E /* Debug */ = {", 1)[0]
        self.assertNotIn("ENCHRON_REGRESSION_LINK_PROVENANCE_FLAG", release)

    def test_prepare_build_returns_build_settings_for_both_lanes(self) -> None:
        with TemporaryDirectory() as temporary:
            repository = Path(temporary).resolve()
            artifact_root = repository / ".scratch" / "regression"
            toolchain = ToolchainIdentity(
                "27.0",
                "24A123",
                "27.0",
                "24N123",
                "27.0",
                "24N124",
            )
            identity = LinkProvenance(
                "a" * 40,
                canonical_digest({"source": "tree"}),
                toolchain,
            )
            prepared = tuple(
                PreparedLaneProvenance(
                    lane,
                    artifact_root / "build-provenance" / f"{lane.value}.json",
                    canonical_digest({"lane": lane.value}),
                    identity,
                    (
                        "ENCHRON_REGRESSION_LINK_PROVENANCE_FLAG="
                        "-Wl,-sectcreate,__TEXT,__enchsrc,"
                        f"{artifact_root}/build-provenance/{lane.value}.json"
                    ),
                )
                for lane in (BoundLane.SIMULATOR, BoundLane.DEVICE)
            )
            arguments = _parser().parse_args(
                [
                    "prepare-build",
                    "--repository-root",
                    str(repository),
                    "--artifact-root",
                    ".scratch/regression",
                ]
            )

            with patch(
                "regression.runctl.prepare_build_provenance",
                return_value=prepared,
            ) as prepare:
                payload, status = _execute(arguments)

        prepare.assert_called_once_with(repository, artifact_root)
        self.assertEqual(0, status)
        self.assertEqual(
            {
                "operation": "prepare-build",
                "artifactRoot": str(artifact_root),
                "gitRevision": "a" * 40,
                "sourceTreeDigest": str(identity.source_tree_digest),
                "toolchain": {
                    "xcodeVersion": "27.0",
                    "xcodeBuild": "24A123",
                    "visionOSSDKVersion": "27.0",
                    "visionOSSDKBuild": "24N123",
                    "visionOSSimulatorSDKVersion": "27.0",
                    "visionOSSimulatorSDKBuild": "24N124",
                },
                "lanes": [
                    {
                        "lane": item.lane.value,
                        "provenancePath": str(item.path),
                        "provenanceDigest": str(item.digest),
                        "xcodeBuildSetting": item.xcode_build_setting,
                    }
                    for item in prepared
                ],
            },
            payload,
        )
        for lane in payload["lanes"]:
            self.assertTrue(
                lane["xcodeBuildSetting"].endswith(
                    "," + lane["provenancePath"]
                )
            )

    def test_freeze_has_only_v2_orchestration_arguments(self) -> None:
        expected = {
            "-h",
            "--help",
            "--repository-root",
            "--artifact-root",
            "--simulator-target",
            "--device-target",
            "--agent-model",
            "--agent-executable",
            "--output",
            "--bootstrap",
        }
        self.assertEqual(expected, self.command_options("freeze"))
        valid = [
            "freeze",
            "--artifact-root",
            ".scratch/regression",
            "--simulator-target",
            "SIM-UDID",
            "--device-target",
            "DEVICE-ID",
            "--agent-model",
            "gpt-5",
            "--output",
            "execution-input.json",
        ]
        self.assertEqual("codex", _parser().parse_args(valid).agent_executable)
        for option in (
            "--artifact-root",
            "--simulator-target",
            "--device-target",
            "--agent-model",
            "--output",
        ):
            with self.subTest(missing=option):
                index = valid.index(option)
                missing = valid[:index] + valid[index + 2 :]
                stderr = StringIO()
                with redirect_stderr(stderr), self.assertRaises(SystemExit) as raised:
                    _parser().parse_args(missing)
                self.assertEqual(2, raised.exception.code)
                self.assertIn(f"required: {option}", stderr.getvalue())
        for option in (
            "--bundle-identifier",
            "--configuration-receipt",
            "--simulator-binary",
            "--device-binary",
        ):
            with self.subTest(option=option):
                stderr = StringIO()
                with redirect_stderr(stderr), self.assertRaises(SystemExit) as raised:
                    _parser().parse_args([*valid, option, "obsolete"])
                self.assertEqual(2, raised.exception.code)
                self.assertIn(f"unrecognized arguments: {option}", stderr.getvalue())

    def test_freeze_delegates_only_derived_v2_inputs(self) -> None:
        value = SimpleNamespace(
            build_identity=SimpleNamespace(digest="sha256:build"),
            evidence_environment_identity=SimpleNamespace(
                digest="sha256:environment"
            ),
        )
        with TemporaryDirectory() as temporary:
            repository = Path(temporary).resolve()
            artifact_root = repository / ".scratch" / "regression"
            output = artifact_root / "execution-input.json"
            arguments = _parser().parse_args(
                [
                    "freeze",
                    "--repository-root",
                    str(repository),
                    "--artifact-root",
                    ".scratch/regression",
                    "--simulator-target",
                    "SIM-UDID",
                    "--device-target",
                    "DEVICE-ID",
                    "--agent-model",
                    "gpt-5",
                    "--agent-executable",
                    "codex-custom",
                    "--output",
                    "execution-input.json",
                ]
            )

            with (
                patch(
                    "regression.runctl.freeze_execution_input",
                    return_value=value,
                ) as freeze,
                patch("regression.runctl.write_execution_input") as write,
            ):
                payload, status = _execute(arguments)

        freeze.assert_called_once_with(
            repository,
            artifact_root,
            {
                BoundLane.SIMULATOR: "SIM-UDID",
                BoundLane.DEVICE: "DEVICE-ID",
            },
            "gpt-5",
            "codex-custom",
            bootstrap=False,
        )
        write.assert_called_once_with(output, value)
        self.assertEqual(0, status)
        self.assertEqual(
            {
                "operation": "freeze",
                "path": str(output),
                "buildIdentityDigest": "sha256:build",
                "evidenceEnvironmentDigest": "sha256:environment",
            },
            payload,
        )

    def test_compile_loads_the_v2_input_without_a_repository_hint(self) -> None:
        execution = SimpleNamespace(
            build_identity="build-identity",
            evidence_environment_identity="evidence-identity",
            bootstrap=False,
        )
        reviewed_catalog = SimpleNamespace(catalog="catalog")
        completed_review = object()
        compiled = object()
        repository = Path("/tmp/enchron-repository")
        execution_input = repository / "execution-input.json"
        with (
            patch(
                "regression.runctl.load_execution_input",
                return_value=execution,
            ) as load,
            patch(
                "regression.runctl.load_current_reviewed_catalog",
                return_value=(reviewed_catalog, completed_review),
            ),
            patch("regression.runctl._repository_path"),
            patch("regression.runctl.load_blueprint_fact_values", return_value={}),
            patch("regression.runctl.derive_reviewed_facts", return_value=()),
            patch("regression.runctl.CompileRequest"),
            patch("regression.runctl.compile_run", return_value=compiled),
        ):
            result, loaded = compile_execution_plan(
                repository,
                execution_input,
                Path("Regression"),
                Path("Regression/review-policy.md"),
                Path("Regression/reviews"),
                Path("Config/regression/catalog-v2.json"),
            )

        load.assert_called_once_with(execution_input)
        self.assertIs(compiled, result)
        self.assertIs(execution, loaded)

    def test_execution_identity_failures_exit_at_the_cli_boundary(self) -> None:
        for command, error in (
            (
                ["prepare-build", "--artifact-root", "invalid,artifact"],
                "artifact root path cannot contain comma or newline",
            ),
            (
                [
                    "freeze",
                    "--artifact-root",
                    ".scratch/regression",
                    "--simulator-target",
                    "SIM-UDID",
                    "--device-target",
                    "DEVICE-ID",
                    "--agent-model",
                    "gpt-5",
                    "--output",
                    "execution-input.json",
                ],
                "lane products are stale",
            ),
        ):
            target = (
                "regression.runctl.prepare_build_provenance"
                if command[0] == "prepare-build"
                else "regression.runctl.freeze_execution_input"
            )
            with self.subTest(command=command[0]):
                stderr = StringIO()
                with (
                    patch(target, side_effect=ExecutionIdentityError(error)),
                    redirect_stderr(stderr),
                    self.assertRaises(SystemExit) as raised,
                ):
                    main(command)
                self.assertEqual(2, raised.exception.code)
                self.assertEqual(f"runctl: {error}\n", stderr.getvalue())

    def test_blueprint_fact_values_require_a_current_content_digest(self) -> None:
        with TemporaryDirectory() as temporary:
            path = Path(temporary) / "catalog-v2.json"
            unsigned = {
                "schemaVersion": 2,
                "analysisFactValues": {
                    "fact:runtime.no-human-or-wearer": True,
                },
            }
            payload = {
                **unsigned,
                "contentDigest": "sha256:"
                + hashlib.sha256(canonical_bytes(unsigned)).hexdigest(),
            }
            path.write_bytes(canonical_bytes(payload) + b"\n")
            self.assertEqual(
                {"fact:runtime.no-human-or-wearer": True},
                load_blueprint_fact_values(path),
            )
            payload["analysisFactValues"]["fact:runtime.no-human-or-wearer"] = False
            path.write_bytes(canonical_bytes(payload) + b"\n")
            with self.assertRaisesRegex(RunControlError, "digest"):
                load_blueprint_fact_values(path)

    def test_reviewed_facts_bind_human_receipt_and_current_fact_source(self) -> None:
        fact = FactDeclaration(
            FactID("fact:runtime.no-human-or-wearer"),
            "No runtime human",
            "No runtime human is needed.",
            ArgumentValueKind.BOOLEAN,
            "Body",
            canonical_digest({"fact": "source"}),
        )
        packet_digest = canonical_digest({"packet": "human"})
        receipt_digest = canonical_digest({"receipt": "human"})
        unit = SimpleNamespace(kind=ReviewUnitKind.FACT, ref=str(fact.id))
        packet = SimpleNamespace(
            reviewer=ReviewClass.HUMAN_COVERAGE,
            packet_digest=packet_digest,
            units=(unit,),
        )
        receipt = SimpleNamespace(
            packet_digest=packet_digest,
            receipt_digest=receipt_digest,
        )
        catalog = SimpleNamespace(facts=(fact,))
        completed = SimpleNamespace(packets=(packet,), receipts=(receipt,))
        values = {str(fact.id): True}

        reviewed = derive_reviewed_facts(catalog, completed, values)

        self.assertEqual(1, len(reviewed))
        self.assertEqual(fact.id, reviewed[0].id)
        self.assertIs(True, reviewed[0].value)
        self.assertEqual(fact.source_digest, reviewed[0].source_digest)
        self.assertEqual(receipt_digest, reviewed[0].review_receipt_digest)
        with self.assertRaisesRegex(RunControlError, "exactly"):
            derive_reviewed_facts(catalog, completed, {})


if __name__ == "__main__":
    unittest.main()
