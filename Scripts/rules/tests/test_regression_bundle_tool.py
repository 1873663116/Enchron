#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

SCRIPTS = Path(__file__).resolve().parents[2]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
if str(SCRIPTS / "rules") not in sys.path:
    sys.path.insert(0, str(SCRIPTS / "rules"))

from regression.core.contracts import BoundLane
from regression.core.ids import NodeID, SidekickID
from regression.core.runtime import OperationResult, StateFingerprint, open_run
from regression.tools import bundle_tool
from regression.tools.bundle_tool import BundleError, ExceptionBundle, run
from regression.tools.raster import Raster, decode_png, encode_png
from regression.tools.signatures import ALL_BLACK, CAPTURE_FAILED, FRAME_UNCHANGED

from test_regression_core_runtime import (
    FakeOperationAdapter,
    _call,
    _digest,
    _invoke_current,
    _request,
    _single_node_plan,
)

NODE = NodeID("node:gate")
SIDEKICK = SidekickID("sidekick:one")


def frame(width: int, height: int, value: int) -> bytes:
    return encode_png(Raster(width, height, 3, bytes([value]) * (width * height * 3)))


def gradient_frame(width: int, height: int) -> bytes:
    samples = bytes(
        (row * width + column + channel * 61) % 256
        for row in range(height)
        for column in range(width)
        for channel in range(3)
    )
    return encode_png(Raster(width, height, 3, samples))


class BundleFixture(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name) / "run"
        self.shots = Path(self.temporary.name) / "shots"
        self.shots.mkdir(parents=True)

    def shot(self, name: str, png: bytes) -> str:
        path = self.shots / f"{name}.png"
        path.write_bytes(png)
        return str(path)

    def build(self, results) -> ExceptionBundle:
        calls = tuple(_call(f"step-{index}") for index in range(len(results)))
        plan = _single_node_plan(calls=calls)
        main = open_run(plan, self.directory)
        try:
            lease = main.claim(BoundLane.SIMULATOR, SIDEKICK, now_millis=0)
            for outcome in results:
                call = main.view.lease(lease.id).current_call
                fingerprints = tuple(
                    StateFingerprint(item.key, item.schema, _digest(f"state:{item.key}"))
                    for item in call.state_productions
                )
                _invoke_current(
                    main,
                    lease,
                    FakeOperationAdapter(
                        [
                            OperationResult(
                                outcome["succeeded"],
                                fingerprints,
                                outcome.get("detail", ""),
                                outcome.get("outputs", {}),
                            )
                        ]
                    ),
                )
        finally:
            main.close()
        return run(self.directory, NODE, 1)


class BundleContentTests(BundleFixture):
    """The bundle is the only input to an attribution, so what it does not carry
    the Agent cannot see. Every image it counts has to be an image it holds."""

    def test_the_frame_count_matches_the_frames_the_montage_tiles(self) -> None:
        bundle = self.build(
            [
                {
                    "succeeded": True,
                    "outputs": {"localScreenshotPath": self.shot("one", frame(8, 6, 200))},
                },
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("two", frame(8, 6, 40))},
                },
            ]
        )

        self.assertEqual(2, bundle.frame_count)
        self.assertEqual(2, len(bundle.before_after))
        self.assertIsNotNone(bundle.contact_sheet)
        montage = decode_png(bundle.contact_sheet.png)
        self.assertGreater(montage.width, 0)
        self.assertGreater(montage.height, 0)

    def test_a_first_call_has_no_before_frame(self) -> None:
        bundle = self.build(
            [
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("only", frame(8, 6, 90))},
                }
            ]
        )

        self.assertEqual(1, bundle.frame_count)
        self.assertEqual(1, len(bundle.before_after))
        self.assertIn("after", bundle.before_after[0].caption)

    def test_the_image_count_is_the_before_after_plus_montage_plus_crops(self) -> None:
        bundle = self.build(
            [
                {
                    "succeeded": True,
                    "outputs": {"localScreenshotPath": self.shot("a", frame(8, 6, 10))},
                },
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("b", frame(8, 6, 12))},
                },
            ]
        )

        self.assertEqual(
            len(bundle.before_after) + 1 + len(bundle.crops), len(bundle.images())
        )

    def test_the_field_diff_carries_the_whole_field_set_with_no_baseline(self) -> None:
        outputs = {"lifecycle": "Paused", "controls": "hidden", "succeeded": False}
        bundle = self.build([{"succeeded": False, "outputs": outputs}])

        self.assertEqual(set(outputs), set(bundle.field_diff))
        for key, value in outputs.items():
            self.assertEqual((None, value), bundle.field_diff[key])
        self.assertNotEqual({}, dict(bundle.field_diff))

    def test_a_crop_is_refused_in_words_rather_than_cut_at_a_guessed_scale(
        self,
    ) -> None:
        bundle = self.build(
            [
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("d", frame(8, 6, 30))},
                }
            ]
        )

        self.assertEqual((), bundle.crops)
        self.assertIn("point", bundle.crop_refusal)
        self.assertEqual(bundle.crop_refusal, bundle.payload()["cropRefusal"])

    def test_a_bundle_with_no_frame_refuses_no_crop_it_never_had(self) -> None:
        bundle = self.build([{"succeeded": False, "outputs": {}}])

        self.assertIsNone(bundle.crop_refusal)
        self.assertIsNone(bundle.contact_sheet)
        self.assertIn("captured no frame", bundle.montage_refusal)
        self.assertIn("captured no frame", bundle.signature_refusal)

    def test_a_frame_that_does_not_decode_says_so_rather_than_reading_clean(
        self,
    ) -> None:
        bundle = self.build(
            [
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("e", b"not a png")},
                }
            ]
        )

        self.assertEqual((), bundle.matched_signature)
        self.assertIsNone(bundle.contact_sheet)
        self.assertIn("did not decode", bundle.montage_refusal)
        self.assertIn("did not decode", bundle.signature_refusal)
        self.assertEqual(
            bundle.signature_refusal, bundle.payload()["signatureRefusal"]
        )

    def test_the_payload_names_every_image_it_returns(self) -> None:
        bundle = self.build(
            [
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("c", frame(8, 6, 30))},
                }
            ]
        )
        payload = bundle.payload()

        self.assertEqual(
            len(payload["beforeAfter"]) + 1 + len(payload["crops"]),
            len(bundle.images()),
        )
        self.assertEqual(bundle.frame_count, payload["frameCount"])
        self.assertEqual(str(NODE), payload["node"])


class DeviantCallTests(BundleFixture):
    """The bundle shows the call that deviated, not the last call that happened
    to run, so an attempt whose first call failed does not present its second."""

    def test_a_failed_call_ends_the_attempt_and_is_the_one_shown(self) -> None:
        bundle = self.build(
            [
                {"succeeded": True, "outputs": {"mark": "first"}},
                {"succeeded": False, "outputs": {"mark": "second"}},
            ]
        )

        self.assertEqual("call:step-1", str(bundle.call))
        self.assertEqual((None, "second"), bundle.field_diff["mark"])

    def test_an_attempt_with_no_failure_shows_its_last_call(self) -> None:
        bundle = self.build(
            [
                {"succeeded": True, "outputs": {"mark": "first"}},
                {"succeeded": True, "outputs": {"mark": "second"}},
            ]
        )

        self.assertEqual("call:step-1", str(bundle.call))
        self.assertEqual((None, "second"), bundle.field_diff["mark"])


class SignatureTests(BundleFixture):
    def test_an_all_black_frame_matches_its_signature(self) -> None:
        bundle = self.build(
            [
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("dark", frame(40, 30, 0))},
                }
            ]
        )

        self.assertIn(ALL_BLACK, bundle.matched_signature)

    def test_a_one_pixel_capture_matches_its_signature(self) -> None:
        bundle = self.build(
            [
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("tiny", frame(1, 1, 128))},
                }
            ]
        )

        self.assertIn(CAPTURE_FAILED, bundle.matched_signature)

    def test_two_identical_frames_match_the_unchanged_signature(self) -> None:
        same = gradient_frame(24, 18)
        bundle = self.build(
            [
                {
                    "succeeded": True,
                    "outputs": {"localScreenshotPath": self.shot("before", same)},
                },
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("after", same)},
                },
            ]
        )

        self.assertIn(FRAME_UNCHANGED, bundle.matched_signature)

    def test_two_different_frames_do_not_match_the_unchanged_signature(self) -> None:
        bundle = self.build(
            [
                {
                    "succeeded": True,
                    "outputs": {
                        "localScreenshotPath": self.shot("light", frame(24, 18, 240))
                    },
                },
                {
                    "succeeded": False,
                    "outputs": {
                        "localScreenshotPath": self.shot("mid", gradient_frame(24, 18))
                    },
                },
            ]
        )

        self.assertNotIn(FRAME_UNCHANGED, bundle.matched_signature)

    def test_every_matched_signature_is_registered(self) -> None:
        from regression.tools.signatures import signature

        bundle = self.build(
            [
                {
                    "succeeded": False,
                    "outputs": {"localScreenshotPath": self.shot("dark2", frame(40, 30, 0))},
                }
            ]
        )

        for item in bundle.matched_signature:
            self.assertIsNotNone(signature(item))


class AttemptTests(BundleFixture):
    def test_an_attempt_the_ledger_never_recorded_is_refused_with_the_count(
        self,
    ) -> None:
        self.build([{"succeeded": False, "outputs": {}}])

        with self.assertRaisesRegex(BundleError, "recorded 1 attempt"):
            run(self.directory, NODE, 2)

    def test_an_attempt_below_one_is_refused(self) -> None:
        self.build([{"succeeded": False, "outputs": {}}])

        with self.assertRaisesRegex(BundleError, "numbered from one"):
            run(self.directory, NODE, 0)

    def test_a_node_the_run_does_not_hold_is_refused(self) -> None:
        self.build([{"succeeded": False, "outputs": {}}])

        with self.assertRaises(Exception) as raised:
            run(self.directory, NodeID("node:absent"), 1)

        self.assertNotIsInstance(raised.exception, AssertionError)

    def test_a_claimed_attempt_that_ran_no_call_is_refused(self) -> None:
        plan = _single_node_plan()
        main = open_run(plan, self.directory)
        try:
            main.claim(BoundLane.SIMULATOR, SIDEKICK, now_millis=0)
        finally:
            main.close()

        with self.assertRaisesRegex(BundleError, "completed no Operation call"):
            run(self.directory, NODE, 1)

    def test_a_node_that_was_never_claimed_is_refused(self) -> None:
        plan = _single_node_plan()
        main = open_run(plan, self.directory)
        main.close()

        with self.assertRaisesRegex(BundleError, "never claimed"):
            run(self.directory, NODE, 1)


if __name__ == "__main__":
    unittest.main()
