#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, call, patch

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

import interactive_visionpro_ui as controller


class ReadyStateCacheTests(unittest.TestCase):
    def arguments(self, device: str) -> argparse.Namespace:
        return argparse.Namespace(
            device=device,
            runner_bundle_id="runner",
            output_directory=tempfile.mkdtemp(prefix="ready-cache-"),
        )

    def ready_writer(self, session_id: str):
        def write(**kwargs) -> bool:
            kwargs["local_path"].write_text(
                json.dumps({"sessionID": session_id}), encoding="utf-8"
            )
            return True
        return write

    def test_physical_device_reads_ready_once_per_session(self) -> None:
        arguments = self.arguments("00008142-0001")
        with patch.object(controller, "is_simulator", return_value=False), patch.object(
            controller, "copy_from_device", side_effect=self.ready_writer("s1")
        ) as copy_from:
            first = controller.read_ready_state(arguments)
            second = controller.read_ready_state(arguments)
        self.assertEqual((first["sessionID"], second["sessionID"]), ("s1", "s1"))
        self.assertEqual(copy_from.call_count, 1)

    def test_fresh_read_bypasses_the_cache(self) -> None:
        arguments = self.arguments("00008142-0001")
        with patch.object(controller, "is_simulator", return_value=False), patch.object(
            controller, "copy_from_device", side_effect=self.ready_writer("s1")
        ) as copy_from:
            controller.read_ready_state(arguments)
            controller.read_ready_state(arguments, fresh=True)
        self.assertEqual(copy_from.call_count, 2)

    def test_forgetting_the_cache_forces_the_next_read_to_copy(self) -> None:
        arguments = self.arguments("00008142-0001")
        with patch.object(controller, "is_simulator", return_value=False), patch.object(
            controller, "copy_from_device", side_effect=self.ready_writer("s1")
        ) as copy_from:
            controller.read_ready_state(arguments)
            controller.forget_ready_state(arguments)
            controller.read_ready_state(arguments)
        self.assertEqual(copy_from.call_count, 2)

    def test_simulator_never_caches_ready_state(self) -> None:
        arguments = self.arguments("3DD8E196-SIM")
        with patch.object(controller, "is_simulator", return_value=True), patch.object(
            controller, "copy_from_device", side_effect=self.ready_writer("s1")
        ) as copy_from:
            controller.read_ready_state(arguments)
            controller.read_ready_state(arguments)
        self.assertEqual(copy_from.call_count, 2)


class DeferredAppCommandTests(unittest.TestCase):
    def test_deferred_command_sends_once_without_copying_its_response(self) -> None:
        sent: dict[str, object] = {}
        arguments = argparse.Namespace(
            verb="toggleControls",
            timeout_seconds=30.0,
            app_arguments=["evidenceSession=session-10", "visible=true"],
            device="device",
            defer_response=True,
        )
        def capture_request(**kwargs) -> None:
            sent.update(json.loads(kwargs["local_path"].read_text(encoding="utf-8")))

        with patch.object(
            controller.uuid, "uuid4", return_value="command-10"
        ), patch.object(
            controller, "copy_to_device", side_effect=capture_request
        ) as copy_to, patch.object(
            controller, "copy_from_device"
        ) as copy_from, patch.object(controller.time, "sleep"):
            response = controller.app_command(arguments)

        copy_to.assert_called_once()
        self.assertEqual(
            copy_to.call_args.kwargs["remote_path"],
            "Documents/test-commands/command-10.json",
        )
        copy_from.assert_not_called()
        self.assertEqual(
            sent,
            {
                "id": "command-10",
                "verb": "toggleControls",
                "args": {
                    "evidenceSession": "session-10",
                    "visible": "true",
                },
            },
        )
        self.assertEqual(
            response,
            {
                "success": True,
                "deferred": True,
                "id": "command-10",
                "verb": "toggleControls",
            },
        )


class CommandTextTests(unittest.TestCase):
    def test_json_field_is_loaded_without_putting_secret_in_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            credentials = Path(directory) / "credentials.json"
            credentials.write_text(
                json.dumps({"username": "viewer", "password": "secret-value"}),
                encoding="utf-8",
            )
            arguments = argparse.Namespace(
                text=None,
                text_file=credentials,
                text_json_key="password",
            )

            self.assertEqual(controller.resolve_command_text(arguments), "secret-value")
            self.assertNotIn("secret-value", repr(arguments))

    def test_response_redaction_removes_the_input_from_nested_text(self) -> None:
        response = {
            "hierarchy": "Username: private-user",
            "matchedElement": {"value": "private-user"},
        }

        redacted = controller.redact_command_text(response, "private-user")

        self.assertNotIn("private-user", json.dumps(redacted))
        self.assertEqual(redacted["matchedElement"]["value"], "<redacted-input>")


class RunnerLaunchIdentityTests(unittest.TestCase):
    @staticmethod
    def physical_registry():
        return controller.PhysicalVisionOSDeviceRegistry(
            (
                controller.PhysicalVisionOSDevice("DEVICE-A-UDID", "DEVICE-A-CORE"),
                controller.PhysicalVisionOSDevice("DEVICE-B-UDID", "DEVICE-B-CORE"),
            )
        )

    def launch_arguments(
        self, *, device: str, destination_id: str | None = None
    ) -> argparse.Namespace:
        return argparse.Namespace(
            device=device,
            destination_id=destination_id,
            execution_input=Path("/run/frozen-execution-input.json"),
            developer_dir=None,
        )

    @staticmethod
    def frozen_launch(
        *,
        lane: controller.BoundLane,
        target_id: str,
        destination: str,
        suffix: str = "current",
    ) -> SimpleNamespace:
        return SimpleNamespace(
            lane=lane,
            target_id=target_id,
            xctestrun_path=Path(f"/frozen/{suffix}.xctestrun"),
            destination_specifier=destination,
            lane_artifact=SimpleNamespace(
                lane=lane,
                xctestrun_digest=f"sha256:xctestrun-{suffix}",
                test_products_digest=f"sha256:products-{suffix}",
                application_code_digest=f"sha256:app-{suffix}",
            ),
        )

    def launch(
        self,
        arguments: argparse.Namespace,
        directory: str,
        popen: Mock,
        *,
        simulator_udid_source=None,
        frozen_test_launch_loader: Mock | None = None,
    ) -> dict[str, object]:
        requested_target = arguments.destination_id or arguments.device
        target_id = (
            "SIM-UDID" if requested_target == "SIM-UDID" else "DEVICE-A-UDID"
        )
        launch_is_simulator = target_id == "SIM-UDID"
        default_launch = self.frozen_launch(
            lane=(
                controller.BoundLane.SIMULATOR
                if launch_is_simulator
                else controller.BoundLane.DEVICE
            ),
            target_id=target_id,
            destination=(
                "platform=visionOS Simulator,id=SIM-UDID"
                if launch_is_simulator
                else "platform=visionOS,id=DEVICE-A-UDID"
            ),
        )
        loader = frozen_test_launch_loader or Mock(return_value=default_launch)
        popen.return_value.pid = 4102
        with patch.object(controller.subprocess, "Popen", popen):
            return controller.launch_runner(
                arguments,
                Path(directory) / "runner.log",
                Path(directory) / "runner.xcresult",
                simulator_udid_source=(
                    simulator_udid_source
                    if simulator_udid_source is not None
                    else lambda: frozenset({"SIM-UDID"})
                ),
                physical_visionos_device_registry_source=self.physical_registry,
                frozen_test_launch_loader=loader,
            )

    def test_launch_uses_registered_simulator_classification(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            loader = Mock(
                return_value=self.frozen_launch(
                    lane=controller.BoundLane.SIMULATOR,
                    target_id="SIM-UDID",
                    destination="platform=visionOS Simulator,id=SIM-UDID",
                )
            )
            provenance = self.launch(
                self.launch_arguments(device="SIM-UDID"),
                directory,
                popen,
                frozen_test_launch_loader=loader,
            )

        command = popen.call_args.args[0]
        self.assertEqual(
            command,
            [
                "xcodebuild",
                "test-without-building",
                "-xctestrun",
                "/frozen/current.xctestrun",
                "-destination",
                "platform=visionOS Simulator,id=SIM-UDID",
                "-parallel-testing-enabled",
                "NO",
                "-test-timeouts-enabled",
                "NO",
                "-resultBundlePath",
                str(Path(directory) / "runner.xcresult"),
            ],
        )
        self.assertEqual(
            loader.call_args_list,
            [
                call(
                    Path("/run/frozen-execution-input.json"),
                    controller.BoundLane.SIMULATOR,
                    "SIM-UDID",
                ),
                call(
                    Path("/run/frozen-execution-input.json"),
                    controller.BoundLane.SIMULATOR,
                    "SIM-UDID",
                ),
            ],
        )
        self.assertEqual(provenance["processId"], 4102)
        self.assertEqual(provenance["xctestrunDigest"], "sha256:xctestrun-current")
        forbidden = {
            "-project",
            "-scheme",
            "-testPlan",
            "-configuration",
            "-derivedDataPath",
            "-clonedSourcePackagesDirPath",
        }
        self.assertTrue(forbidden.isdisjoint(command))
        self.assertFalse(any(item.startswith("-only-testing") for item in command))

    def test_launch_normalizes_same_device_aliases_to_the_hardware_udid(self) -> None:
        cases = (
            ("DEVICE-A-CORE", None),
            ("DEVICE-A-CORE", "DEVICE-A-UDID"),
            ("DEVICE-A-UDID", "DEVICE-A-CORE"),
        )
        for device, destination_id in cases:
            with self.subTest(device=device, destination_id=destination_id):
                with tempfile.TemporaryDirectory() as directory:
                    popen = Mock()
                    target_id = "DEVICE-A-UDID"
                    loader = Mock(
                        return_value=self.frozen_launch(
                            lane=controller.BoundLane.DEVICE,
                            target_id=target_id,
                            destination="platform=visionOS,id=DEVICE-A-UDID",
                        )
                    )
                    self.launch(
                        self.launch_arguments(
                            device=device, destination_id=destination_id
                        ),
                        directory,
                        popen,
                        frozen_test_launch_loader=loader,
                    )

                command = popen.call_args.args[0]
                destination = command[command.index("-destination") + 1]
                self.assertEqual(
                    destination, "platform=visionOS,id=DEVICE-A-UDID"
                )
                self.assertEqual(
                    loader.call_args_list,
                    [
                        call(
                            Path("/run/frozen-execution-input.json"),
                            controller.BoundLane.DEVICE,
                            target_id,
                        ),
                        call(
                            Path("/run/frozen-execution-input.json"),
                            controller.BoundLane.DEVICE,
                            target_id,
                        ),
                    ],
                )

    def test_launch_rejects_transport_and_destination_on_different_devices(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            with self.assertRaisesRegex(RuntimeError, "different physical.*devices"):
                self.launch(
                    self.launch_arguments(
                        device="DEVICE-A-CORE", destination_id="DEVICE-B-UDID"
                    ),
                    directory,
                    popen,
                )

        popen.assert_not_called()

    def test_launch_rejects_a_cross_lane_frozen_launch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            loader = Mock(
                return_value=self.frozen_launch(
                    lane=controller.BoundLane.DEVICE,
                    target_id="SIM-UDID",
                    destination="platform=visionOS Simulator,id=SIM-UDID",
                )
            )
            with self.assertRaisesRegex(RuntimeError, "different lane"):
                self.launch(
                    self.launch_arguments(device="SIM-UDID"),
                    directory,
                    popen,
                    frozen_test_launch_loader=loader,
                )

        popen.assert_not_called()

    def test_launch_revalidates_tamper_immediately_before_popen(self) -> None:
        launch = self.frozen_launch(
            lane=controller.BoundLane.SIMULATOR,
            target_id="SIM-UDID",
            destination="platform=visionOS Simulator,id=SIM-UDID",
        )
        loader = Mock(
            side_effect=(launch, RuntimeError("xctestrun digest changed"))
        )
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            with self.assertRaisesRegex(RuntimeError, "digest changed"):
                self.launch(
                    self.launch_arguments(device="SIM-UDID"),
                    directory,
                    popen,
                    frozen_test_launch_loader=loader,
                )

        self.assertEqual(loader.call_count, 2)
        popen.assert_not_called()

    def test_launch_rejects_valid_input_replacement_during_revalidation(self) -> None:
        first = self.frozen_launch(
            lane=controller.BoundLane.SIMULATOR,
            target_id="SIM-UDID",
            destination="platform=visionOS Simulator,id=SIM-UDID",
            suffix="first",
        )
        replacement = self.frozen_launch(
            lane=controller.BoundLane.SIMULATOR,
            target_id="SIM-UDID",
            destination="platform=visionOS Simulator,id=SIM-UDID",
            suffix="replacement",
        )
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            with self.assertRaisesRegex(RuntimeError, "changed during"):
                self.launch(
                    self.launch_arguments(device="SIM-UDID"),
                    directory,
                    popen,
                    frozen_test_launch_loader=Mock(
                        side_effect=(first, replacement)
                    ),
                )

        popen.assert_not_called()

    def test_launch_rejects_transport_and_destination_from_different_lanes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            with self.assertRaisesRegex(RuntimeError, "different lanes"):
                self.launch(
                    self.launch_arguments(
                        device="DEVICE-A-CORE", destination_id="SIM-UDID"
                    ),
                    directory,
                    popen,
                )

        popen.assert_not_called()

    def test_launch_rejects_different_simulator_devices(self) -> None:
        arguments = self.launch_arguments(
            device="SIM-UDID", destination_id="OTHER-SIM-UDID"
        )
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            with self.assertRaisesRegex(RuntimeError, "different simulator devices"):
                self.launch(
                    arguments,
                    directory,
                    popen,
                    simulator_udid_source=lambda: frozenset(
                        {"SIM-UDID", "OTHER-SIM-UDID"}
                    ),
                )

        popen.assert_not_called()

    def test_launch_fails_closed_without_frozen_input_locator(self) -> None:
        arguments = self.launch_arguments(device="SIM-UDID")
        arguments.execution_input = None
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            with self.assertRaisesRegex(RuntimeError, "--execution-input"):
                self.launch(arguments, directory, popen)

        popen.assert_not_called()

    def test_launch_rejects_an_unregistered_physical_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            with self.assertRaisesRegex(RuntimeError, "paired physical visionOS"):
                self.launch(
                    self.launch_arguments(device="FAKE-DEVICE"), directory, popen
                )

        popen.assert_not_called()

    def test_launch_fails_closed_when_simulator_registry_is_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            popen = Mock()
            simulator_source = Mock(
                side_effect=RuntimeError("simctl registry unavailable")
            )
            with self.assertRaisesRegex(RuntimeError, "simctl registry unavailable"):
                self.launch(
                    self.launch_arguments(device="DEVICE-A-CORE"),
                    directory,
                    popen,
                    simulator_udid_source=simulator_source,
                )

        popen.assert_not_called()


class RunnerSessionOutputTests(unittest.TestCase):
    def test_ready_session_records_post_popen_provenance_and_run_owned_result(self) -> None:
        provenance = {
            "lane": "simulator",
            "targetId": "SIM-UDID",
            "xctestrunDigest": "sha256:xctestrun",
            "processId": 4102,
        }
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(
                device="SIM-UDID",
                output_directory=directory,
                ready_timeout=30.0,
                result_bundle_path="/outside/not-run-owned.xcresult",
            )
            with patch.object(
                controller,
                "halt_session",
                return_value={"remaining": [], "terminated": []},
            ), patch.object(
                controller,
                "current_session_id",
                side_effect=("stale-session", "new-session"),
            ), patch.object(
                controller, "launch_runner", return_value=provenance
            ) as launch, patch.object(
                controller,
                "send_command",
                return_value={"success": True, "appState": "runningForeground"},
            ), patch.object(
                controller, "read_ready_state", side_effect=RuntimeError("The interactive XCUI runner is not ready. Start its dedicated UI test first.")
            ), patch.object(
                controller, "_resident_runner_path", return_value=Path(directory) / "resident.json"
            ), patch.object(
                controller, "_write_resident_runner"
            ):
                response = controller.ensure_session(arguments)

            result_bundle = launch.call_args.args[2]
            self.assertEqual(result_bundle.parent, Path(directory))
            self.assertNotEqual(result_bundle, Path(arguments.result_bundle_path))

        self.assertEqual(response["launchProvenance"], provenance)
        self.assertEqual(response["resultBundlePath"], str(result_bundle))


class RunnerCompletionScopeTests(unittest.TestCase):
    def test_frozen_interactive_runner_remains_visible_to_halt_completion(self) -> None:
        interactive = (
            "xcodebuild test-without-building -xctestrun "
            "/frozen/Enchron_InteractiveDeviceSession_xros27.0-arm64.xctestrun "
            "-destination platform=visionOS,id=DEVICE-A-UDID"
        )
        unrelated = (
            "xcodebuild test-without-building -xctestrun "
            "/frozen/Enchron_Enchron_xros27.0-arm64.xctestrun"
        )
        with patch.object(
            controller,
            "process_table",
            return_value=[(4102, 1, interactive), (4103, 1, unrelated)],
        ), patch.object(
            controller, "own_lineage", return_value=set()
        ), patch.object(
            controller, "working_directory", return_value=str(controller.REPOSITORY_ROOT)
        ):
            scoped = controller.scoped_processes()

        self.assertEqual(scoped, [(4102, interactive)])

    def test_a_runner_working_in_another_worktree_is_out_of_scope(self) -> None:
        interactive = (
            "xcodebuild test-without-building -xctestrun "
            f"{controller.REPOSITORY_ROOT}/.scratch/campaign/artifacts/lanes/simulator/"
            "Enchron_InteractiveDeviceSession_xrsimulator27.0-arm64.xctestrun "
            "-destination platform=visionOS Simulator,id=SIM-UDID"
        )
        with patch.object(
            controller, "process_table", return_value=[(4102, 1, interactive)]
        ), patch.object(
            controller, "own_lineage", return_value=set()
        ), patch.object(
            controller, "working_directory", return_value="/other/worktree"
        ):
            self.assertEqual(controller.scoped_processes(), [])

    def test_the_path_counts_only_when_the_working_directory_is_unreadable(self) -> None:
        interactive = (
            "xcodebuild test-without-building -xctestrun "
            f"{controller.REPOSITORY_ROOT}/.scratch/campaign/artifacts/lanes/device/"
            "Enchron_InteractiveDeviceSession_xros27.0-arm64.xctestrun"
        )
        with patch.object(
            controller, "process_table", return_value=[(4102, 1, interactive)]
        ), patch.object(
            controller, "own_lineage", return_value=set()
        ), patch.object(
            controller, "working_directory", return_value=None
        ):
            self.assertEqual(controller.scoped_processes(), [(4102, interactive)])


class ResponseWaitTests(unittest.TestCase):
    ARGUMENTS = SimpleNamespace(device="udid", runner_bundle_id="bundle")

    def wait(self, *, copied, clock, liveness, deadline=60.0):
        with patch.object(
            controller, "copy_from_device", return_value=copied
        ), patch.object(
            controller.time, "sleep"
        ), patch.object(
            controller.time, "monotonic", side_effect=clock
        ):
            return controller.wait_for_response(
                arguments=self.ARGUMENTS,
                command_id="c1",
                response_path=Path("/nowhere/response.json"),
                deadline_seconds=deadline,
                liveness=liveness,
            )

    def test_an_answer_arrives(self) -> None:
        outcome = self.wait(copied=True, clock=[0.0], liveness=lambda: True)
        self.assertEqual(outcome, controller.RESPONSE_ARRIVED)

    def test_a_gone_runner_ends_the_wait_before_the_deadline(self) -> None:
        outcome = self.wait(copied=False, clock=[0.0, 0.0], liveness=lambda: False)
        self.assertEqual(outcome, controller.RESPONSE_RUNNER_GONE)

    def test_a_live_runner_waits_out_the_deadline(self) -> None:
        outcome = self.wait(copied=False, clock=[0.0, 100.0], liveness=lambda: True)
        self.assertEqual(outcome, controller.RESPONSE_TIMED_OUT)

    def test_the_liveness_probe_runs_at_most_every_interval(self) -> None:
        probes: list[float] = []

        def liveness() -> bool:
            probes.append(1.0)
            return True

        outcome = self.wait(
            copied=False, clock=[0.0, 0.0, 1.0, 2.0, 6.0, 100.0], liveness=liveness
        )
        self.assertEqual(outcome, controller.RESPONSE_TIMED_OUT)
        self.assertEqual(len(probes), 3)

    def test_runner_gone_is_an_instrument_fault_of_its_own_kind(self) -> None:
        response = controller._attach_failure(
            SimpleNamespace(action="tap"),
            {"success": False, "stage": "runnerGone", "message": "gone"},
        )
        self.assertEqual(response["failure"]["class"], "instrument")
        self.assertEqual(response["failure"]["kind"], "runner-gone")


class RunnerArgumentTests(unittest.TestCase):
    def test_developer_directory_validation_never_mutates_process_environment(self) -> None:
        with patch.dict(
            controller.os.environ,
            {"DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer"},
        ):
            before = dict(controller.os.environ)
            environment = controller._developer_environment(
                "/Applications/Xcode-beta.app/Contents/Developer"
            )
            after = dict(controller.os.environ)

        self.assertEqual(after, before)
        self.assertEqual(
            environment["DEVELOPER_DIR"],
            "/Applications/Xcode-beta.app/Contents/Developer",
        )

    def test_developer_directory_must_match_frozen_loader_toolchain(self) -> None:
        with patch.dict(
            controller.os.environ,
            {"DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer"},
        ):
            with self.assertRaisesRegex(RuntimeError, "must match"):
                controller._developer_environment(
                    "/Applications/Other-Xcode.app/Contents/Developer"
                )

    def test_explicit_execution_input_overrides_environment_locator(self) -> None:
        with patch.dict(
            controller.os.environ,
            {"ENCHRON_EXECUTION_INPUT": "/run/from-environment.json"},
        ):
            arguments = controller.parse_arguments(
                [
                    "--device",
                    "SIM-UDID",
                    "--execution-input",
                    "/run/explicit.json",
                    "ensure-session",
                ]
            )

        self.assertEqual(arguments.execution_input, Path("/run/explicit.json"))

    def test_execution_input_uses_environment_locator_by_default(self) -> None:
        with patch.dict(
            controller.os.environ,
            {"ENCHRON_EXECUTION_INPUT": "/run/from-environment.json"},
        ):
            arguments = controller.parse_arguments(
                ["--device", "SIM-UDID", "ensure-session"]
            )

        self.assertEqual(
            arguments.execution_input, Path("/run/from-environment.json")
        )


class AssertAbsentFlagTests(unittest.TestCase):
    def test_parse_arguments_accepts_assert_absent(self) -> None:
        arguments = controller.parse_arguments(
            [
                "--device",
                "SIM-UDID",
                "tapSequence",
                "--identifiers",
                "PlayerUI-window-playback-surface",
                "PlayerUI-TopAction-videoFormat",
                "PlayerUI-VideoFormat-cancel",
                "--assert-absent",
                "PlayerUI-VideoFormat-CustomAngle",
            ]
        )
        self.assertEqual(
            arguments.assertAbsent, ["PlayerUI-VideoFormat-CustomAngle"]
        )
        self.assertEqual(
            arguments.identifiers,
            [
                "PlayerUI-window-playback-surface",
                "PlayerUI-TopAction-videoFormat",
                "PlayerUI-VideoFormat-cancel",
            ],
        )


class EnsureSessionAdoptionTests(unittest.TestCase):
    def test_adoption_skips_launch_runner(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(
                device="SIM-UDID",
                output_directory=directory,
                ready_timeout=30.0,
                runner_bundle_id="runner",
                result_bundle_path="/tmp/not.xcresult",
            )
            resident_path = Path(directory) / "resident.json"
            resident_path.write_text(json.dumps({"sessionID": "s-adopted", "xctestrunDigest": "sha256:xctestrun-current", "testProductsDigest": "sha256:products-current", "applicationCodeDigest": "sha256:app-current"}), encoding="utf-8")
            with patch.object(
                controller, "read_ready_state", side_effect=[
                    {"sessionID": "s-adopted"},
                    {"sessionID": "s-adopted"},
                ]
            ) as mock_read, patch.object(
                controller, "send_command", return_value={"success": True}
            ) as mock_send, patch.object(
                controller, "halt_session"
            ) as mock_halt, patch.object(
                controller, "launch_runner"
            ) as mock_launch, patch.object(
                controller, "_resident_runner_path", return_value=resident_path
            ), patch.object(
                controller, "_current_lane_digests", return_value=("sha256:xctestrun-current", "sha256:products-current", "sha256:app-current")
            ):
                mock_halt.side_effect = AssertionError("halt must not be called on adoption")
                mock_launch.side_effect = AssertionError("launch must not be called on adoption")
                response = controller.ensure_session(arguments)
            self.assertEqual(response["stage"], "adopted")
            self.assertEqual(response["sessionID"], "s-adopted")
            self.assertTrue(response["success"])
            self.assertEqual(response["adoption"], {"attempted": True, "refused": None})
            self.assertEqual(mock_read.call_count, 2)
            self.assertTrue(all(call.kwargs.get("fresh") is True for call in mock_read.call_args_list))
            mock_send.assert_called_once()
            probe = mock_send.call_args.args[0]
            self.assertEqual(probe.action, "snapshot")
            self.assertTrue(probe.no_screenshot)

    def test_dead_runner_still_launches(self) -> None:
        provenance = {
            "lane": "simulator",
            "targetId": "SIM-UDID",
            "xctestrunDigest": "sha256:xctestrun",
            "processId": 4102,
        }
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(
                device="SIM-UDID",
                output_directory=directory,
                ready_timeout=30.0,
                runner_bundle_id="runner",
                result_bundle_path="/tmp/not.xcresult",
            )
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s-old", "xctestrunDigest": "sha256:xctestrun-current", "testProductsDigest": "sha256:products-current", "applicationCodeDigest": "sha256:app-current"}), encoding="utf-8")
            with patch.object(
                controller, "read_ready_state", return_value={"sessionID": "s-old"}
            ), patch.object(
                controller, "send_command", side_effect=[
                    {"success": False},
                    {"success": True, "appState": "runningForeground"},
                ]
            ) as mock_send, patch.object(
                controller, "halt_session", return_value={"remaining": [], "terminated": []}
            ) as mock_halt, patch.object(
                controller, "current_session_id", side_effect=("s-old", "s-new")
            ), patch.object(
                controller, "launch_runner", return_value=provenance
            ) as mock_launch, patch.object(
                controller, "_resident_runner_path", return_value=resident
            ), patch.object(
                controller, "_current_lane_digests", return_value=("sha256:xctestrun-current", "sha256:products-current", "sha256:app-current")
            ), patch.object(
                controller, "_write_resident_runner"
            ):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["stage"], "ready")
            self.assertEqual(mock_launch.call_count, 1)
            self.assertEqual(mock_halt.call_count, 1)
            self.assertEqual(mock_send.call_count, 2)
            self.assertEqual(response["adoption"]["attempted"], True)
            self.assertIsNotNone(response["adoption"]["refused"])

    def test_adoption_never_returns_session_whose_ready_disappeared(self) -> None:
        provenance = {
            "lane": "simulator",
            "targetId": "SIM-UDID",
            "xctestrunDigest": "sha256:xctestrun",
            "processId": 4102,
        }
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(
                device="SIM-UDID",
                output_directory=directory,
                ready_timeout=30.0,
                runner_bundle_id="runner",
                result_bundle_path="/tmp/not.xcresult",
            )
            resident_path = Path(directory) / "resident.json"
            resident_path.write_text(json.dumps({"sessionID": "s-vanish", "xctestrunDigest": "sha256:xctestrun-current", "testProductsDigest": "sha256:products-current", "applicationCodeDigest": "sha256:app-current"}), encoding="utf-8")
            with patch.object(
                controller, "read_ready_state", side_effect=[
                    {"sessionID": "s-vanish"},
                    RuntimeError("The interactive XCUI runner is not ready. Start its dedicated UI test first."),
                ]
            ), patch.object(
                controller, "send_command", side_effect=[
                    {"success": True},
                    {"success": True, "appState": "runningForeground"},
                ]
            ), patch.object(
                controller, "halt_session", return_value={"remaining": [], "terminated": []}
            ) as mock_halt, patch.object(
                controller, "launch_runner", return_value=provenance
            ) as mock_launch, patch.object(
                controller, "current_session_id", side_effect=("s-vanish", "s-new")
            ), patch.object(
                controller, "_resident_runner_path", return_value=resident_path
            ), patch.object(
                controller, "_current_lane_digests", return_value=("sha256:xctestrun-current", "sha256:products-current", "sha256:app-current")
            ), patch.object(
                controller, "_write_resident_runner"
            ):
                response = controller.ensure_session(arguments)
            self.assertNotEqual(response.get("stage"), "adopted")
            self.assertEqual(mock_launch.call_count, 1)
            self.assertEqual(response["stage"], "ready")
            self.assertEqual(response["sessionID"], "s-new")


class ResidentRunnerStalenessTests(unittest.TestCase):
    def test_adoption_refused_when_file_missing(self) -> None:
        provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "sha256:xctestrun", "testProductsDigest": "sha256:products", "applicationCodeDigest": "sha256:app", "processId": 4102}
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            missing = Path(directory) / "nope.json"
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s1"}), patch.object(controller, "send_command", return_value={"success": True}), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s1", "s2")), patch.object(controller, "launch_runner", return_value=provenance) as mock_launch, patch.object(controller, "_resident_runner_path", return_value=missing), patch.object(controller, "_current_lane_digests", return_value=("sha256:xctestrun", "sha256:products", "sha256:app")), patch.object(controller, "_write_resident_runner"):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["stage"], "ready")
            self.assertEqual(response["adoption"]["attempted"], True)
            self.assertEqual(response["adoption"]["refused"], "resident-file-missing")
            self.assertEqual(mock_launch.call_count, 1)

    def test_adoption_refused_when_applicationCodeDigest_differs(self) -> None:
        provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "sha256:xctestrun", "testProductsDigest": "sha256:products", "applicationCodeDigest": "sha256:app-new", "processId": 4102}
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s1", "xctestrunDigest": "sha256:xctestrun", "testProductsDigest": "sha256:products", "applicationCodeDigest": "sha256:app-old"}), encoding="utf-8")
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s1"}), patch.object(controller, "send_command", return_value={"success": True}), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s1", "s2")), patch.object(controller, "launch_runner", return_value=provenance) as mock_launch, patch.object(controller, "_resident_runner_path", return_value=resident), patch.object(controller, "_current_lane_digests", return_value=("sha256:xctestrun", "sha256:products", "sha256:app-new")), patch.object(controller, "_write_resident_runner"):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["stage"], "ready")
            self.assertEqual(response["adoption"]["refused"], "applicationCodeDigest-mismatch")
            self.assertEqual(mock_launch.call_count, 1)

    def test_adoption_accepted_when_all_three_match(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s1", "xctestrunDigest": "sha256:xctestrun", "testProductsDigest": "sha256:products", "applicationCodeDigest": "sha256:app"}), encoding="utf-8")
            with patch.object(controller, "read_ready_state", side_effect=[{"sessionID": "s1"}, {"sessionID": "s1"}]), patch.object(controller, "send_command", return_value={"success": True}), patch.object(controller, "halt_session") as mock_halt, patch.object(controller, "launch_runner") as mock_launch, patch.object(controller, "_resident_runner_path", return_value=resident), patch.object(controller, "_current_lane_digests", return_value=("sha256:xctestrun", "sha256:products", "sha256:app")):
                mock_halt.side_effect = AssertionError("halt must not be called")
                mock_launch.side_effect = AssertionError("launch must not be called")
                response = controller.ensure_session(arguments)
            self.assertEqual(response["stage"], "adopted")
            self.assertEqual(response["adoption"], {"attempted": True, "refused": None})

    def test_file_is_rewritten_on_every_real_launch(self) -> None:
        provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "sha256:xctestrun-new", "testProductsDigest": "sha256:products-new", "applicationCodeDigest": "sha256:app-new", "processId": 4102}
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            missing = Path(directory) / "missing.json"
            written: dict[str, object] = {}
            def fake_write(path, session_id, prov):
                written["path"] = path
                written["sessionID"] = session_id
                written["provenance"] = prov
                Path(path).parent.mkdir(parents=True, exist_ok=True)
                Path(path).write_text(json.dumps({"sessionID": session_id, "xctestrunDigest": prov["xctestrunDigest"], "testProductsDigest": prov["testProductsDigest"], "applicationCodeDigest": prov["applicationCodeDigest"]}), encoding="utf-8")
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s-old"}), patch.object(controller, "send_command", side_effect=[{"success": False}, {"success": True, "appState": "runningForeground"}]), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s-old", "s-new")), patch.object(controller, "launch_runner", return_value=provenance), patch.object(controller, "_resident_runner_path", return_value=missing), patch.object(controller, "_current_lane_digests", return_value=("sha256:xctestrun-new", "sha256:products-new", "sha256:app-new")), patch.object(controller, "_write_resident_runner", side_effect=fake_write) as mock_write:
                response = controller.ensure_session(arguments)
            self.assertEqual(response["stage"], "ready")
            mock_write.assert_called_once()
            self.assertEqual(written["sessionID"], "s-new")
            self.assertEqual(written["provenance"]["applicationCodeDigest"], "sha256:app-new")
            self.assertTrue(missing.is_file())
            data = json.loads(missing.read_text(encoding="utf-8"))
            self.assertEqual(data["sessionID"], "s-new")
            self.assertEqual(data["applicationCodeDigest"], "sha256:app-new")
            provenance2 = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "sha256:xctestrun-v2", "testProductsDigest": "sha256:products-v2", "applicationCodeDigest": "sha256:app-v2", "processId": 4103}
            written.clear()
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s-new"}), patch.object(controller, "send_command", side_effect=[{"success": False}, {"success": True, "appState": "runningForeground"}]), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s-new", "s-new2")), patch.object(controller, "launch_runner", return_value=provenance2), patch.object(controller, "_resident_runner_path", return_value=missing), patch.object(controller, "_current_lane_digests", return_value=("sha256:xctestrun-v2", "sha256:products-v2", "sha256:app-v2")), patch.object(controller, "_write_resident_runner", side_effect=fake_write):
                response2 = controller.ensure_session(arguments)
            self.assertEqual(response2["stage"], "ready")
            data2 = json.loads(missing.read_text(encoding="utf-8"))
            self.assertEqual(data2["sessionID"], "s-new2")
            self.assertEqual(data2["applicationCodeDigest"], "sha256:app-v2")


class EnsureSessionAdoptionFieldTests(unittest.TestCase):
    def test_adoption_field_present_on_adopted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s1", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c"}), encoding="utf-8")
            with patch.object(controller, "read_ready_state", side_effect=[{"sessionID": "s1"}, {"sessionID": "s1"}]), patch.object(controller, "send_command", return_value={"success": True}), patch.object(controller, "_resident_runner_path", return_value=resident), patch.object(controller, "_current_lane_digests", return_value=("a", "b", "c")):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["adoption"], {"attempted": True, "refused": None})

    def test_adoption_field_shows_refused_reason(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            missing = Path(directory) / "missing.json"
            provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c", "processId": 1}
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s1"}), patch.object(controller, "send_command", return_value={"success": True}), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s1", "s2")), patch.object(controller, "launch_runner", return_value=provenance), patch.object(controller, "_resident_runner_path", return_value=missing), patch.object(controller, "_current_lane_digests", return_value=("a", "b", "c")), patch.object(controller, "_write_resident_runner"):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["adoption"]["attempted"], True)
            self.assertEqual(response["adoption"]["refused"], "resident-file-missing")

    def test_unexpected_exception_propagates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s1", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c"}), encoding="utf-8")
            with patch.object(controller, "read_ready_state", side_effect=[{"sessionID": "s1"}, ValueError("bad json")]), patch.object(controller, "send_command", return_value={"success": True}), patch.object(controller, "_resident_runner_path", return_value=resident), patch.object(controller, "_current_lane_digests", return_value=("a", "b", "c")):
                with self.assertRaises(ValueError):
                    controller.ensure_session(arguments)

    def test_send_command_unexpected_exception_propagates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s1", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c"}), encoding="utf-8")
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s1"}), patch.object(controller, "send_command", side_effect=ValueError("unexpected")), patch.object(controller, "_resident_runner_path", return_value=resident), patch.object(controller, "_current_lane_digests", return_value=("a", "b", "c")):
                with self.assertRaises(ValueError):
                    controller.ensure_session(arguments)

    def test_xctestrunDigest_mismatch_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s1", "xctestrunDigest": "old", "testProductsDigest": "b", "applicationCodeDigest": "c"}), encoding="utf-8")
            provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "new", "testProductsDigest": "b", "applicationCodeDigest": "c", "processId": 1}
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s1"}), patch.object(controller, "send_command", return_value={"success": True}), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s1", "s2")), patch.object(controller, "launch_runner", return_value=provenance), patch.object(controller, "_resident_runner_path", return_value=resident), patch.object(controller, "_current_lane_digests", return_value=("new", "b", "c")), patch.object(controller, "_write_resident_runner"):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["adoption"]["refused"], "xctestrunDigest-mismatch")

    def test_testProductsDigest_mismatch_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s1", "xctestrunDigest": "a", "testProductsDigest": "old", "applicationCodeDigest": "c"}), encoding="utf-8")
            provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "a", "testProductsDigest": "new", "applicationCodeDigest": "c", "processId": 1}
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s1"}), patch.object(controller, "send_command", return_value={"success": True}), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s1", "s2")), patch.object(controller, "launch_runner", return_value=provenance), patch.object(controller, "_resident_runner_path", return_value=resident), patch.object(controller, "_current_lane_digests", return_value=("a", "new", "c")), patch.object(controller, "_write_resident_runner"):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["adoption"]["refused"], "testProductsDigest-mismatch")

    def test_resident_session_mismatch_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s-other", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c"}), encoding="utf-8")
            provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c", "processId": 1}
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s1"}), patch.object(controller, "send_command", return_value={"success": True}), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s1", "s2")), patch.object(controller, "launch_runner", return_value=provenance), patch.object(controller, "_resident_runner_path", return_value=resident), patch.object(controller, "_current_lane_digests", return_value=("a", "b", "c")), patch.object(controller, "_write_resident_runner"):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["adoption"]["refused"], "resident-session-mismatch")

    def test_probe_not_success_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            resident = Path(directory) / "resident.json"
            resident.write_text(json.dumps({"sessionID": "s1", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c"}), encoding="utf-8")
            provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c", "processId": 1}
            with patch.object(controller, "read_ready_state", return_value={"sessionID": "s1"}), patch.object(controller, "send_command", return_value={"success": False}), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s1", "s2")), patch.object(controller, "launch_runner", return_value=provenance), patch.object(controller, "_resident_runner_path", return_value=resident), patch.object(controller, "_current_lane_digests", return_value=("a", "b", "c")), patch.object(controller, "_write_resident_runner"):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["adoption"]["refused"], "probe-not-success")

    def test_no_ready_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = argparse.Namespace(device="SIM-UDID", output_directory=directory, ready_timeout=30.0, runner_bundle_id="runner", result_bundle_path="/tmp/not.xcresult")
            missing = Path(directory) / "missing.json"
            provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c", "processId": 1}
            with patch.object(controller, "read_ready_state", side_effect=RuntimeError("The interactive XCUI runner is not ready. Start its dedicated UI test first.")), patch.object(controller, "halt_session", return_value={"remaining": [], "terminated": []}), patch.object(controller, "current_session_id", side_effect=("s1", "s2")), patch.object(controller, "launch_runner", return_value=provenance), patch.object(controller, "send_command", return_value={"success": True, "appState": "runningForeground"}), patch.object(controller, "_resident_runner_path", return_value=missing), patch.object(controller, "_write_resident_runner"):
                response = controller.ensure_session(arguments)
            self.assertEqual(response["adoption"]["refused"], "no-ready")


class ReadyTimeoutTests(unittest.TestCase):
    def arguments(self, directory: str) -> argparse.Namespace:
        return argparse.Namespace(
            device="SIM-UDID",
            output_directory=directory,
            ready_timeout=0.05,
            runner_bundle_id="runner",
            result_bundle_path="/tmp/not.xcresult",
        )

    def timed_out(self, directory: str, log_lines: list[str]):
        provenance = {"lane": "simulator", "targetId": "SIM-UDID", "xctestrunDigest": "a", "testProductsDigest": "b", "applicationCodeDigest": "c", "processId": 1}
        missing = Path(directory) / "missing.json"
        no_runner = RuntimeError(
            "The interactive XCUI runner is not ready. Start its dedicated UI test first."
        )
        with patch.object(controller, "read_ready_state", side_effect=no_runner), patch.object(
            controller, "halt_session", return_value={"remaining": [], "terminated": []}
        ), patch.object(
            controller, "current_session_id", return_value=None
        ), patch.object(
            controller, "launch_runner", return_value=provenance
        ) as launch, patch.object(
            controller, "log_tail", return_value=log_lines
        ), patch.object(
            controller.time, "sleep"
        ), patch.object(
            controller, "_resident_runner_path", return_value=missing
        ), patch.object(
            controller, "_write_resident_runner"
        ):
            return controller.ensure_session(self.arguments(directory)), launch

    def test_a_session_that_never_publishes_times_out_after_one_launch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            response, launch = self.timed_out(directory, ["no session yet"])

        self.assertEqual("readyTimeout", response["stage"])
        self.assertFalse(response["success"])
        self.assertEqual(1, launch.call_count, "the launch is not retried")
        self.assertIn("runnerLog", response)
        self.assertIn("launchProvenance", response)

    def test_the_timeout_states_observations_without_naming_a_wearer_step(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            response, _ = self.timed_out(directory, ["no session yet"])

        self.assertIn("what was seen, not why", response["message"])
        for absent in ("automation mode", "authorization", "wearer"):
            self.assertNotIn(absent, response["message"].lower())
        self.assertEqual(1, len(response["observations"]))

    def test_the_idle_synchronization_line_is_reported_as_normal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            response, _ = self.timed_out(directory, ["Wait for com.enchron.app to idle"])

        sources = [str(item["source"]) for item in response["observations"]]
        self.assertTrue(any("diagnostics.md" in source for source in sources))




class AlertsFromHierarchyTests(unittest.TestCase):
    HIERARCHY = "\n".join([
        "Attributes: Application, 0x105cf4a00, pid: 64679, label: 'Enchron'",
        "Element subtree:",
        " →Application, 0x105cf4a00, pid: 64679, label: 'Enchron'",
        "    Other, 0x105cf4640, {{0.0, 0.0}, {328.0, 297.0}}",
        "      StaticText, 0x105cf4700, {{0.0, 0.0}, {10.0, 10.0}}, label: 'Outside'",
        "      Alert, 0x105cdb980, {{0.0, 0.0}, {328.0, 297.0}}, label: 'Conversion Failed'",
        "        Other, 0x105cdaf80, {{0.0, 0.0}, {328.0, 297.0}}",
        "          StaticText, 0x105cd8f00, {{0.0, 0.0}, {328.0, 20.0}}, label: 'Conversion Failed'",
        "          StaticText, 0x105cda440, {{0.0, 0.0}, {328.0, 40.0}}, identifier: 'PlayerUI-presentation-conversion-diagnostic', label: 'The display could not be changed.', value: 'mainWindowUnavailable'",
        "          Button, 0x105cdae40, {{0.0, 0.0}, {328.0, 44.0}}, identifier: 'PlayerUI-presentation-conversion-dismiss', label: 'OK'",
        "      Button, 0x105cdb340, {{0.0, 0.0}, {328.0, 44.0}}, identifier: 'Navigation-Ornament-tab-files', label: 'Files'",
    ])

    def test_alert_title_lines_and_buttons_come_from_the_alert_subtree(self) -> None:
        alerts = controller.alerts_from_hierarchy(self.HIERARCHY)
        self.assertEqual(alerts, [{
            "title": "Conversion Failed",
            "lines": [{
                "identifier": "PlayerUI-presentation-conversion-diagnostic",
                "label": "The display could not be changed.",
                "value": "mainWindowUnavailable",
            }],
            "buttons": ["PlayerUI-presentation-conversion-dismiss"],
        }])

    def test_a_hierarchy_without_alerts_yields_an_empty_list(self) -> None:
        lines = [line for line in self.HIERARCHY.splitlines() if "Alert" not in line and "conversion" not in line]
        self.assertEqual(controller.alerts_from_hierarchy("\n".join(lines)), [])

class ChromeContainmentTests(unittest.TestCase):
    """The measured shape of a simulator hierarchy: a scene container, a main
    window, an ornament carrying its own coordinate space, and a developer
    readout anchored to the window's bottom trailing corner."""

    def hierarchy(self, overlay_frame: str, ornament_frame: str = "{{32.0, 12.0}, {680.0, 72.0}}") -> str:
        return "\n".join([
            "Attributes: Application, 0x109cf30c0, pid: 62328, label: 'Enchron'",
            "Element subtree:",
            " \u2192Application, 0x109cf30c0, pid: 62328, label: 'Enchron'",
            "    Other, 0x109cf2940, {{0.0, 0.0}, {905.0, 1018.0}}, identifier: 'com.example.App:SFBSystemService-A5A1'",
            "      Window (Main), 0x109cf2f80, {{0.0, 0.0}, {905.0, 1018.0}}",
            "        Other, 0x109cf1e00, {{24.0, 20.0}, {857.0, 60.0}}, identifier: 'PlayerUI-window-top-overlay'",
            f"        Other, 0x109ca6bc0, {overlay_frame}, identifier: 'DeveloperStatsOverlay', label: 'MEM 123MB'",
            "      Window, 0x109ca7840, {{0.0, 0.0}, {744.0, 168.0}}",
            "        Other, 0x109ca5b80, {{0.0, 0.0}, {744.0, 168.0}}, identifier: 'PlayerPanel-controls'",
            f"          Other, 0x109ca7700, {ornament_frame}, identifier: 'PlayerPanel-media-information'",
        ])

    def test_chrome_inside_its_window_reports_nothing(self) -> None:
        hierarchy = self.hierarchy("{{235.5, 983.5}, {657.5, 22.5}}")
        self.assertEqual(controller.chrome_containment_violations(hierarchy), [])

    def test_a_readout_anchored_to_a_wider_content_rect_escapes_to_the_right(self) -> None:
        hierarchy = self.hierarchy("{{620.5, 821.5}, {657.5, 22.5}}")
        self.assertEqual(controller.chrome_containment_violations(hierarchy), [{
            "identifier": "DeveloperStatsOverlay",
            "role": "Other",
            "frame": [620.5, 821.5, 657.5, 22.5],
            "host": "Window (Main)",
            "hostFrame": [0.0, 0.0, 905.0, 1018.0],
            "edges": ["right"],
        }])

    def test_a_readout_below_and_left_of_its_window_names_both_edges(self) -> None:
        hierarchy = self.hierarchy("{{-40.0, 1010.0}, {657.5, 22.5}}")
        violations = controller.chrome_containment_violations(hierarchy)
        self.assertEqual([violation["edges"] for violation in violations], [["left", "bottom"]])

    def test_an_ornament_is_judged_against_its_own_window(self) -> None:
        """The ornament's window starts its own coordinate space at zero, so a
        child at x=760 escapes a 744-wide ornament while sitting well inside the
        905-wide window beside it."""
        hierarchy = self.hierarchy(
            "{{235.5, 983.5}, {657.5, 22.5}}",
            ornament_frame="{{760.0, 12.0}, {680.0, 72.0}}",
        )
        violations = controller.chrome_containment_violations(hierarchy)
        self.assertEqual(
            [(violation["identifier"], violation["hostFrame"]) for violation in violations],
            [("PlayerPanel-media-information", [0.0, 0.0, 744.0, 168.0])],
        )

    def test_an_unnamed_framework_remnant_is_not_a_product_placement(self) -> None:
        hierarchy = self.hierarchy("{{235.5, 983.5}, {657.5, 22.5}}") + "\n".join([
            "",
            "        TabBar, 0x109cc3c00, {{0.0, 0.0}, {0.0, 0.0}}, label: 'Tab Bar'",
            "          Other, 0x109cc3ac0, {{0.0, -10.0}, {68.0, 20.0}}",
        ])
        self.assertEqual(controller.chrome_containment_violations(hierarchy), [])

    def test_sub_point_rounding_stays_inside_and_half_a_point_more_does_not(self) -> None:
        rounded = self.hierarchy("{{247.9, 983.5}, {657.5, 22.5}}")
        self.assertEqual(controller.chrome_containment_violations(rounded), [])
        escaped = self.hierarchy("{{248.5, 983.5}, {657.5, 22.5}}")
        self.assertEqual(
            [violation["edges"] for violation in controller.chrome_containment_violations(escaped)],
            [["right"]],
        )


if __name__ == "__main__":
    unittest.main()
