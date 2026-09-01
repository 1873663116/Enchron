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
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

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
                "PlayerUI-VideoFormat-HDRFallback",
            ]
        )
        self.assertEqual(
            arguments.assertAbsent, ["PlayerUI-VideoFormat-HDRFallback"]
        )
        self.assertEqual(
            arguments.identifiers,
            [
                "PlayerUI-window-playback-surface",
                "PlayerUI-TopAction-videoFormat",
                "PlayerUI-VideoFormat-cancel",
            ],
        )


if __name__ == "__main__":
    unittest.main()
