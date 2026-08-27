import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest import mock
import wave


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import analyze_acoustic_timeline as analyzer


class PhaseAwareCalibrationTests(unittest.TestCase):
    def test_attachment_loader_ignores_binary_non_acoustic_attachments(self) -> None:
        with tempfile.TemporaryDirectory(prefix="enchron-attachment-loader-") as directory:
            exported = Path(directory)

            def fake_export(_: Path, destination: Path) -> None:
                (destination / "screen.bin").write_bytes(b"\x89PNG\r\n\x1a\n\xd4")
                (destination / "marker.txt").write_text(
                    "wallClock=123.5;state=status=ready"
                )
                (destination / "runtime.json").write_text(
                    json.dumps({"samples": [{"wallClock": 123.5}]})
                )
                (destination / "manifest.json").write_text(json.dumps([{
                    "attachments": [
                        {
                            "suggestedHumanReadableName": "screen_1_attachment.png",
                            "exportedFileName": "screen.bin",
                        },
                        {
                            "suggestedHumanReadableName": "acoustic-control-start_1_attachment.txt",
                            "exportedFileName": "marker.txt",
                        },
                        {
                            "suggestedHumanReadableName": "acoustic-runtime-timeline_1_attachment.txt",
                            "exportedFileName": "runtime.json",
                        },
                    ]
                }]))

            with mock.patch.object(analyzer, "export_attachments", side_effect=fake_export):
                markers, manifest, attached_hash, source, runtime, mixer, mixer_hash = (
                    analyzer.load_acoustic_evidence(exported / "fixture.xcresult")
                )

            self.assertEqual(markers["control-start"]["wallClock"], 123.5)
            self.assertIsNone(manifest)
            self.assertIsNone(attached_hash)
            self.assertIsNone(source)
            self.assertEqual(runtime, {"samples": [{"wallClock": 123.5}]})
            self.assertIsNone(mixer)
            self.assertIsNone(mixer_hash)

    def test_attachment_loader_rejects_duplicate_manifests(self) -> None:
        with tempfile.TemporaryDirectory(prefix="enchron-duplicate-manifest-") as directory:
            exported = Path(directory)

            def fake_export(_: Path, destination: Path) -> None:
                (destination / "one.txt").write_text("{}")
                (destination / "two.txt").write_text("{}")
                (destination / "manifest.json").write_text(json.dumps([{
                    "attachments": [
                        {
                            "suggestedHumanReadableName": "acoustic-tone-manifest_0_one.txt",
                            "exportedFileName": "one.txt",
                        },
                        {
                            "suggestedHumanReadableName": "acoustic-tone-manifest_1_two.txt",
                            "exportedFileName": "two.txt",
                        },
                    ]
                }]))

            with mock.patch.object(analyzer, "export_attachments", side_effect=fake_export):
                with self.assertRaisesRegex(ValueError, "Duplicate AcousticToneManifest"):
                    analyzer.load_acoustic_evidence(exported / "fixture.xcresult")

    def test_manifest_validation_rejects_missing_and_wrong_hash(self) -> None:
        with self.assertRaisesRegex(ValueError, "Missing AcousticToneManifest"):
            analyzer.validate_tone_manifest(None, None)

        manifest = self.make_manifest()
        with self.assertRaisesRegex(ValueError, "source hash mismatch"):
            analyzer.validate_tone_manifest(manifest, "0" * 64)

    def test_manifest_routing_does_not_accept_runtime_json_as_manifest(self) -> None:
        with tempfile.TemporaryDirectory(prefix="enchron-cross-class-") as directory:
            exported = Path(directory)

            def fake_export(_: Path, destination: Path) -> None:
                (destination / "wrong.txt").write_text(json.dumps({"samples": []}))
                (destination / "manifest.json").write_text(json.dumps([{
                    "attachments": [{
                        "suggestedHumanReadableName": "acoustic-tone-manifest_0_wrong.txt",
                        "exportedFileName": "wrong.txt",
                    }]
                }]))

            with mock.patch.object(analyzer, "export_attachments", side_effect=fake_export):
                _, manifest, _, _, _, _, _ = analyzer.load_acoustic_evidence(
                    exported / "fixture.xcresult"
                )
            with self.assertRaisesRegex(ValueError, "sourceContract"):
                analyzer.validate_tone_manifest(manifest, None)

    def test_mixer_tap_period_localizes_measured_and_infra_fixtures(self) -> None:
        manifest = self.make_manifest()
        manifest["calibrationSessionID"] = "fixture-session"

        def envelope(period: int) -> dict[str, object]:
            bursts = []
            for cycle in range(5):
                bursts.extend([
                    {
                        "frequencyHz": 997,
                        "startSampleTime": cycle * period,
                        "startHostTimeSeconds": cycle * period / 48_000,
                    },
                    {
                        "frequencyHz": 1499,
                        "startSampleTime": cycle * period + period // 2,
                        "startHostTimeSeconds": (cycle * period + period // 2) / 48_000,
                    },
                ])
            callbacks = [
                {
                    "bufferSampleRate": 48_000,
                    "bufferChannelCount": 2,
                    "bufferFrameLength": 7_200,
                    "audioTimeSampleRate": 48_000,
                    "sampleTime": index * 7_200,
                    "hostTimeSeconds": index * 0.15,
                }
                for index in range(10)
            ]
            return {
                "schemaVersion": 1,
                "calibrationSessionID": "fixture-session",
                "preStartBusFormat": {"sampleRate": 44_100, "channelCount": 2},
                "callbacks": callbacks,
                "callbackCount": len(callbacks),
                "totalFrames": 72_000,
                "discontinuityCount": 0,
                "overrunCount": 0,
                "finished": True,
                "bursts": bursts,
            }

        nominal = envelope(72_000)
        nominal_hash = hashlib.sha256(json.dumps(
            nominal, sort_keys=True, separators=(",", ":")
        ).encode()).hexdigest()
        measured = analyzer.validate_mixer_tap_evidence(
            manifest, nominal, nominal_hash
        )
        self.assertEqual(measured["status"], "measured")
        self.assertTrue(measured["periodWithinTwoPercent"])
        self.assertTrue(measured["runtimeFormatTransition"])

        fast = envelope(60_000)
        fast_hash = hashlib.sha256(json.dumps(
            fast, sort_keys=True, separators=(",", ":")
        ).encode()).hexdigest()
        self.assertFalse(analyzer.validate_mixer_tap_evidence(
            manifest, fast, fast_hash
        )["periodWithinTwoPercent"])
        self.assertEqual(
            analyzer.validate_mixer_tap_evidence(manifest, None, None)["status"],
            "infra",
        )

        inconsistent = envelope(72_000)
        inconsistent["callbacks"][0]["audioTimeSampleRate"] = 44_100
        inconsistent_hash = hashlib.sha256(json.dumps(
            inconsistent, sort_keys=True, separators=(",", ":")
        ).encode()).hexdigest()
        rejected = analyzer.validate_mixer_tap_evidence(
            manifest, inconsistent, inconsistent_hash
        )
        self.assertEqual(rejected["status"], "infra")
        self.assertIn("sample rates disagree", rejected["reason"])

    def test_repeated_alternating_tones_pass(self) -> None:
        result = self.analyze_fixture(enabled_cycles=set(range(5)), include_1499=True)

        self.assertEqual(result["outcome"], "passed")
        self.assertEqual(result["failures"], [])
        for frequency in result["frequencies"]:
            self.assertGreaterEqual(frequency["windowCount"], 3)
            self.assertGreaterEqual(frequency["passFraction"], 0.8)

    def test_missing_second_tone_fails(self) -> None:
        result = self.analyze_fixture(enabled_cycles=set(range(5)), include_1499=False)

        self.assertEqual(result["outcome"], "acoustic_failed")
        failure_text = " ".join(result["failures"])
        self.assertIn("1499 Hz", failure_text)

    def test_single_intermittent_cycle_fails_repetition_requirement(self) -> None:
        result = self.analyze_fixture(enabled_cycles={0}, include_1499=True)

        self.assertEqual(result["outcome"], "acoustic_failed")
        self.assertTrue(
            any(frequency["passFraction"] < 0.8 for frequency in result["frequencies"])
        )

    def test_observed_period_drift_is_contract_mismatch_not_fitted_pass(self) -> None:
        result = self.analyze_fixture(
            enabled_cycles=set(range(6)),
            include_1499=True,
            signal_period=1.25,
        )

        self.assertEqual(result["outcome"], "contract_mismatch")
        self.assertGreater(
            result["observedEnvelopeAffineFit"]["periodDeviationFraction"], 0.02
        )

    def test_1065_hz_interference_is_not_bridged_into_997_bursts(self) -> None:
        result = self.analyze_fixture(
            enabled_cycles=set(range(5)),
            include_1499=True,
            interference_1065=True,
        )

        observed = result["observedEnvelopeAffineFit"]["bursts"]
        bursts_997 = next(item for item in observed if item["frequencyHz"] == 997)
        self.assertEqual(len(bursts_997["observations"]), 5)
        self.assertTrue(all(
            977 <= burst["mainPeakFrequencyHz"] <= 1_017
            for burst in bursts_997["observations"]
        ))

    def test_ransac_keeps_period_with_missing_and_extra_burst(self) -> None:
        result = self.analyze_fixture(
            enabled_cycles=set(range(5)),
            include_1499=True,
            missing_bursts={(997, 2)},
            extra_997_interval=(1.10, 1.30),
        )

        fit = result["observedEnvelopeAffineFit"]
        self.assertLess(fit["periodDeviationFraction"], 0.02)
        self.assertGreaterEqual(
            fit["missingBurstPenaltyCount"] + fit["extraBurstPenaltyCount"], 1
        )

    def analyze_fixture(
        self,
        *,
        enabled_cycles: set[int],
        include_1499: bool,
        signal_period: float = 1.5,
        interference_1065: bool = False,
        missing_bursts: set[tuple[int, int]] | None = None,
        extra_997_interval: tuple[float, float] | None = None,
    ) -> dict[str, object]:
        sample_rate = 8_000
        duration = 8.0
        phase_offset = 0.2
        with tempfile.TemporaryDirectory(prefix="enchron-phase-aware-test-") as directory:
            wav_path = Path(directory) / "fixture.wav"
            manifest_path = Path(directory) / "tone-manifest.json"
            source_contract = self.source_contract()
            canonical = json.dumps(
                source_contract, sort_keys=True, separators=(",", ":")
            ).encode()
            manifest_path.write_text(json.dumps({
                "sourceContract": source_contract,
                "sourceHashAlgorithm": "sha256-json-sorted-keys",
                "sourceHash": hashlib.sha256(canonical).hexdigest(),
                "runtime": {
                    "engineOutputSampleRate": 48_000,
                    "mainMixerSampleRate": 48_000,
                },
            }))
            frames = []
            for index in range(round(sample_rate * duration)):
                time = index / sample_rate
                relative = time - phase_offset
                sample = 0.0
                if relative >= 0:
                    cycle = int(relative // signal_period)
                    phase = relative % signal_period
                    phase_scale = signal_period / 1.5
                    if cycle in enabled_cycles:
                        if (
                            0 <= phase < 0.5 * phase_scale
                            and (997, cycle) not in (missing_bursts or set())
                        ):
                            sample = 0.2 * math.sin(2 * math.pi * 997 * time)
                        elif (
                            include_1499
                            and 0.75 * phase_scale <= phase < 1.25 * phase_scale
                            and (1_499, cycle) not in (missing_bursts or set())
                        ):
                            sample = 0.2 * math.sin(2 * math.pi * 1_499 * time)
                        elif interference_1065 and 0.52 <= phase < 0.70:
                            sample = 0.2 * math.sin(2 * math.pi * 1_065 * time)
                if extra_997_interval and extra_997_interval[0] <= time < extra_997_interval[1]:
                    sample = 0.2 * math.sin(2 * math.pi * 997 * time)
                frames.append(struct.pack("<h", round(sample * 32_767)))
            with wave.open(str(wav_path), "wb") as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(sample_rate)
                audio.writeframes(b"".join(frames))

            arguments = argparse.Namespace(
                wav=wav_path,
                xcresult=None,
                recording_start_wall_clock=None,
                calibration_start_seconds=0.0,
                calibration_end_seconds=duration,
                calibration_marker_prefix=analyzer.CALIBRATION_INTERVAL,
                edge_trim_seconds=0.0,
                neighbor_offset_hz=25.0,
                minimum_tone_over_neighbor_db=12.0,
                phase_offset_step_seconds=0.025,
                phase_tone_edge_trim_seconds=0.075,
                phase_minimum_window_count=3,
                phase_minimum_pass_fraction=0.8,
                maximum_observed_period_deviation_fraction=0.02,
                tone_manifest=manifest_path,
            )
            return analyzer.analyze_phase_aware_calibration(arguments)

    @staticmethod
    def source_contract() -> dict[str, object]:
        return {
                "schemaVersion": 1,
                "generatorID": "com.enchron.acoustic.dual-tone-cycle.v1",
                "sampleRate": 48_000,
                "totalFrames": 384_000,
                "cycleFrames": 72_000,
                "rampFrames": 480,
                "phases": [
                    {"frequencyHz": 997, "startFrame": 0, "endFrame": 24_000},
                    {"frequencyHz": 1_499, "startFrame": 36_000, "endFrame": 60_000},
                ],
                "requestedPlaybackRate": "1.0",
            }

    @classmethod
    def make_manifest(cls) -> dict[str, object]:
        source = cls.source_contract()
        canonical = json.dumps(source, sort_keys=True, separators=(",", ":")).encode()
        return {
            "sourceContract": source,
            "sourceHashAlgorithm": "sha256-json-sorted-keys",
            "sourceHash": hashlib.sha256(canonical).hexdigest(),
            "runtime": {
                "engineOutputSampleRate": 48_000,
                "mainMixerSampleRate": 48_000,
            },
        }


if __name__ == "__main__":
    unittest.main()
