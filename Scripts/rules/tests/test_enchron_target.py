#!/usr/bin/env python3

"""The lane a container operation takes has to follow the target it was given."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

import enchron_target as target

TARGET_VARIABLE = "ENCHRON_TARGET_DEVICE"
CORE_DEVICE_VARIABLE = "ENCHRON_CORE_DEVICE"


def unconfigured_environment() -> object:
    """An environment with neither identifier in it.

    `clear=True` rather than popping two names, because a machine that happens
    to export one of them would otherwise decide what these cases test.
    """
    return patch.dict(os.environ, {}, clear=True)


class ContainerWriteRoutesByLane(unittest.TestCase):
    """Every read was routed and every write was not.

    The channel health probe writes a nonce, reads it back and empties the file.
    The first two steps went through the routed helpers and the third did not,
    so on the simulator the probe failed with "RemoteServiceDiscovery
    connectivity is not available to the device" naming the headset's
    CoreDevice - a message about a headset that was not involved. The segment
    stopped at its third step with nothing driven.
    """

    def test_the_simulator_branch_writes_into_the_container(self) -> None:
        with tempfile.TemporaryDirectory() as container, \
                tempfile.TemporaryDirectory() as staging:
            payload = Path(staging) / "fixture.mp4"
            payload.write_text("bytes")

            with patch.object(target, "is_simulator", return_value=True), \
                 patch.object(
                     target, "simulator_container", return_value=Path(container)
                 ):
                done = target.copy_to_container(
                    target="simulator-udid",
                    bundle_id="com.example.app",
                    source=payload,
                    destination="Documents/TestMediaInbox/fixture.mp4",
                    developer_dir="/dev/null",
                )

            self.assertEqual(done.returncode, 0)
            landed = Path(container) / "Documents/TestMediaInbox/fixture.mp4"
            self.assertEqual(landed.read_text(), "bytes")

    def test_the_device_branch_still_goes_through_devicectl(self) -> None:
        with tempfile.TemporaryDirectory() as staging:
            payload = Path(staging) / "fixture.mp4"
            payload.write_text("bytes")
            with patch.object(target, "is_simulator", return_value=False), \
                 patch.object(target.subprocess, "run") as run:
                run.return_value = subprocess.CompletedProcess([], 0, "", "")
                target.copy_to_container(
                    target="physical-udid",
                    bundle_id="com.example.app",
                    source=payload,
                    destination="Documents/x",
                    developer_dir="/dev/null",
                    core_device_identifier="CORE-DEVICE",
                )
        command = run.call_args.args[0]
        self.assertIn("devicectl", command)
        self.assertIn("CORE-DEVICE", command)


class ContainerTruncateRoutesByLane(unittest.TestCase):
    """Reads were routed and writes were not.

    Clearing the probe journal went through `devicectl --device <CoreDevice>`
    whatever the target was. A simulator has no CoreDevice, so on that lane the
    clear could only fail, and a segment started on top of whatever the previous
    run had written. A panorama segment came back with four hundred and
    sixty-two journal lines carrying a session id from an earlier run, and its
    replay could verify none of its deliveries.
    """

    def test_the_simulator_branch_empties_the_file_it_was_given(self) -> None:
        with tempfile.TemporaryDirectory() as container:
            journal = Path(container) / "probe.log"
            journal.write_text("a stale session's four hundred lines\n")

            with patch.object(target, "is_simulator", return_value=True), \
                 patch.object(
                     target, "simulator_container", return_value=Path(container)
                 ):
                done = target.truncate_in_container(
                    target="simulator-udid",
                    bundle_id="com.example.app",
                    source="probe.log",
                    developer_dir="/dev/null",
                )

            self.assertEqual(done.returncode, 0)
            self.assertEqual(journal.read_text(), "")

    def test_the_device_branch_still_goes_through_devicectl(self) -> None:
        with patch.object(target, "is_simulator", return_value=False), \
             patch.object(target.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "", "")

            target.truncate_in_container(
                target="physical-udid",
                bundle_id="com.example.app",
                source="probe.log",
                developer_dir="/dev/null",
                core_device_identifier="CORE-DEVICE",
            )

        command = run.call_args.args[0]
        self.assertIn("devicectl", command)
        self.assertIn("CORE-DEVICE", command)

    def test_an_unreadable_simulator_container_is_reported_not_assumed(self) -> None:
        with patch.object(target, "is_simulator", return_value=True), \
             patch.object(target, "simulator_container", return_value=None):
            done = target.truncate_in_container(
                target="simulator-udid",
                bundle_id="com.example.app",
                source="probe.log",
                developer_dir="/dev/null",
            )

        self.assertNotEqual(done.returncode, 0)


class AnUnsetTargetTravelsAsAnEmptyValue(unittest.TestCase):
    """Both identifiers come from the environment, so absence is a value.

    A pinned CoreDevice constant made an unconfigured run drive one particular
    headset. Reading the environment instead moves the question to what the
    helpers do when nothing is set, and several harnesses bind the answer at
    import time, so the empty value has to survive as far as the operation
    that needs it.
    """

    def test_an_unset_variable_gives_an_empty_target(self) -> None:
        with unconfigured_environment():
            self.assertEqual(target.target_device(), "")

    def test_an_unset_variable_gives_an_empty_core_device(self) -> None:
        with unconfigured_environment():
            self.assertEqual(target.core_device(), "")

    def test_a_set_variable_is_read_through(self) -> None:
        with patch.dict(os.environ, {TARGET_VARIABLE: "a-udid", CORE_DEVICE_VARIABLE: "a-core"}):
            self.assertEqual(target.target_device(), "a-udid")
            self.assertEqual(target.core_device(), "a-core")

    def test_the_refusal_reads_as_a_failed_run(self) -> None:
        refused = target.refusal(target.MISSING_TARGET)
        self.assertEqual(refused.returncode, 1)
        self.assertEqual(refused.stdout, "")
        self.assertEqual(refused.stderr, target.MISSING_TARGET)

    def test_both_refusal_messages_name_the_variable_to_set(self) -> None:
        self.assertIn(TARGET_VARIABLE, target.MISSING_TARGET)
        self.assertIn(CORE_DEVICE_VARIABLE, target.MISSING_CORE_DEVICE)


class AnEmptyTargetIsRefusedByEveryContainerOperation(unittest.TestCase):
    """An empty target has no lane, so no operation may guess one for it.

    `is_simulator("")` is false, so every one of these would otherwise take the
    devicectl branch and report a failure about a headset that was never
    selected. The refusal comes before the branch, which is also why none of
    them runs a subprocess.
    """

    def setUp(self) -> None:
        staging = tempfile.TemporaryDirectory()
        self.addCleanup(staging.cleanup)
        self.payload = Path(staging.name) / "fixture.mp4"
        self.payload.write_text("bytes")

    def operations(self) -> tuple[tuple[str, object], ...]:
        payload = self.payload
        return (
            ("copy_to_container", lambda: target.copy_to_container(
                target="", bundle_id="com.example.app", source=payload,
                destination="Documents/x", developer_dir="/dev/null",
            )),
            ("truncate_in_container", lambda: target.truncate_in_container(
                target="", bundle_id="com.example.app", source="probe.log",
                developer_dir="/dev/null",
            )),
            ("copy_from_container", lambda: target.copy_from_container(
                target="", bundle_id="com.example.app", source="probe.log",
                destination=payload, developer_dir="/dev/null",
            )),
            ("list_container_file", lambda: target.list_container_file(
                target="", bundle_id="com.example.app", source="probe.log",
                json_output=payload, developer_dir="/dev/null",
            )),
            ("launch_app", lambda: target.launch_app(
                target="", bundle_id="com.example.app",
            )),
            ("uninstall_app", lambda: target.uninstall_app(
                target="", bundle_id="com.example.app",
            )),
        )

    def test_every_operation_refuses_and_names_the_variable(self) -> None:
        for name, call in self.operations():
            with self.subTest(operation=name):
                done = call()
                self.assertEqual(done.returncode, 1)
                self.assertEqual(done.stderr, target.MISSING_TARGET)
                self.assertIn(TARGET_VARIABLE, done.stderr)

    def test_no_operation_runs_a_subprocess_for_an_empty_target(self) -> None:
        for name, call in self.operations():
            with self.subTest(operation=name):
                with patch.object(target.subprocess, "run") as run:
                    call()
                run.assert_not_called()


class AMissingCoreDeviceIsRefusedOnTheDeviceLane(unittest.TestCase):
    """devicectl needs a CoreDevice, and an empty one is not an argument.

    Passing the empty string to `--device` asks devicectl to find a headset
    named nothing, and the error that comes back describes connectivity rather
    than configuration. The refusal names the variable instead.
    """

    def setUp(self) -> None:
        staging = tempfile.TemporaryDirectory()
        self.addCleanup(staging.cleanup)
        self.payload = Path(staging.name) / "fixture.mp4"
        self.payload.write_text("bytes")

    def operations(self) -> tuple[tuple[str, object], ...]:
        payload = self.payload
        return (
            ("copy_to_container", lambda: target.copy_to_container(
                target="physical-udid", bundle_id="com.example.app", source=payload,
                destination="Documents/x", developer_dir="/dev/null",
            )),
            ("truncate_in_container", lambda: target.truncate_in_container(
                target="physical-udid", bundle_id="com.example.app", source="probe.log",
                developer_dir="/dev/null",
            )),
            ("copy_from_container", lambda: target.copy_from_container(
                target="physical-udid", bundle_id="com.example.app", source="probe.log",
                destination=payload, developer_dir="/dev/null",
            )),
            ("list_container_file", lambda: target.list_container_file(
                target="physical-udid", bundle_id="com.example.app", source="probe.log",
                json_output=payload, developer_dir="/dev/null",
            )),
        )

    def test_every_devicectl_operation_refuses_and_names_the_variable(self) -> None:
        for name, call in self.operations():
            with self.subTest(operation=name):
                with unconfigured_environment(), \
                     patch.object(target, "is_simulator", return_value=False):
                    done = call()
                self.assertEqual(done.returncode, 1)
                self.assertEqual(done.stderr, target.MISSING_CORE_DEVICE)
                self.assertIn(CORE_DEVICE_VARIABLE, done.stderr)

    def test_no_devicectl_operation_runs_a_subprocess_without_a_core_device(self) -> None:
        for name, call in self.operations():
            with self.subTest(operation=name):
                with unconfigured_environment(), \
                     patch.object(target, "is_simulator", return_value=False), \
                     patch.object(target.subprocess, "run") as run:
                    call()
                run.assert_not_called()

    def test_the_environment_supplies_the_core_device_when_the_call_does_not(self) -> None:
        with tempfile.TemporaryDirectory() as staging:
            payload = Path(staging) / "fixture.mp4"
            payload.write_text("bytes")
            with patch.dict(os.environ, {CORE_DEVICE_VARIABLE: "CORE-FROM-ENVIRONMENT"}), \
                 patch.object(target, "is_simulator", return_value=False), \
                 patch.object(target.subprocess, "run") as run:
                run.return_value = subprocess.CompletedProcess([], 0, "", "")
                target.copy_to_container(
                    target="physical-udid",
                    bundle_id="com.example.app",
                    source=payload,
                    destination="Documents/x",
                    developer_dir="/dev/null",
                )
        command = run.call_args.args[0]
        self.assertIn("devicectl", command)
        self.assertIn("CORE-FROM-ENVIRONMENT", command)

    def test_an_explicit_core_device_outranks_the_environment(self) -> None:
        with patch.dict(os.environ, {CORE_DEVICE_VARIABLE: "CORE-FROM-ENVIRONMENT"}), \
             patch.object(target, "is_simulator", return_value=False), \
             patch.object(target.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "", "")
            target.truncate_in_container(
                target="physical-udid",
                bundle_id="com.example.app",
                source="probe.log",
                developer_dir="/dev/null",
                core_device_identifier="CORE-FROM-THE-CALL",
            )
        command = run.call_args.args[0]
        self.assertIn("CORE-FROM-THE-CALL", command)
        self.assertNotIn("CORE-FROM-ENVIRONMENT", command)


class ALaneIsNotDerivedFromAnUnconfiguredTarget(unittest.TestCase):
    """Whoever needs a lane asks for the target, and is refused when there is none.

    `is_simulator("")` is false, so a lane computed straight from an empty
    target reads as the device lane and an unconfigured run reports itself as a
    physical-headset run. `require_target_device` is what the two matrices call
    instead.
    """

    def test_an_unset_variable_stops_the_run_and_names_it(self) -> None:
        with unconfigured_environment():
            with self.assertRaises(SystemExit) as refused:
                target.require_target_device()
        self.assertIn(TARGET_VARIABLE, str(refused.exception))

    def test_a_set_variable_is_returned_unchanged(self) -> None:
        with patch.dict(os.environ, {TARGET_VARIABLE: "a-simulator-udid"}):
            self.assertEqual(target.require_target_device(), "a-simulator-udid")

    def test_the_guard_reaches_no_further_than_the_variable(self) -> None:
        with unconfigured_environment(), patch.object(target.subprocess, "run") as run:
            with self.assertRaises(SystemExit):
                target.require_target_device()
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
