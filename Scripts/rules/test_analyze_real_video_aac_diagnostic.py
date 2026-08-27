import sys
from pathlib import Path
import unittest


sys.path.insert(0, str(Path(__file__).parents[2] / "Scripts" / "verification"))
import analyze_real_video_aac_diagnostic as analyzer


class RealVideoAACDiagnosticTests(unittest.TestCase):
    def test_two_checkpoints_and_complete_first_enqueue_pass(self) -> None:
        first = self.checkpoint(1, 10, 20, 30, 40)
        second = self.checkpoint(2, 11, 21, 31, 41)
        result = analyzer.validate({
            "preRateState": first,
            "preRateCore": self.core(),
            "tailState": first,
            "tailCore": self.tail_core(),
            "checkpointA": first,
            "checkpointB": second,
            "coreA": self.core(),
            "coreB": self.core(),
        })
        self.assertEqual(result["outcome"], "passed")
        self.assertEqual(
            result["preRate"]["playbackActivationPhases"],
            ["call.before", "call.returned"],
        )

    def test_stalled_audio_is_rejected(self) -> None:
        first = self.checkpoint(1, 10, 20, 30, 40)
        second = self.checkpoint(2, 11, 21, 30, 40)
        result = analyzer.validate({
            "preRateState": first,
            "preRateCore": self.core(),
            "tailState": first,
            "tailCore": self.tail_core(),
            "checkpointA": first,
            "checkpointB": second,
            "coreA": self.core(),
            "coreB": self.core(),
        })
        self.assertEqual(result["outcome"], "failed")
        self.assertIn("audioSamples did not increase", result["failures"])

    def test_pre_rate_evidence_survives_missing_continuous_checkpoints(self) -> None:
        result = analyzer.validate({
            "preRateState": self.checkpoint(0, 6, 6, 49, 48),
            "preRateCore": self.core(include_rate_activated=False),
            "tailState": self.checkpoint(0, 10, 10, 54, 53),
            "tailCore": self.tail_core(),
            "checkpointA": None,
            "checkpointB": None,
            "coreA": None,
            "coreB": None,
        })
        self.assertEqual(result["outcome"], "failed")
        self.assertFalse(result["preRate"]["hasRateActivated"])
        self.assertIn(
            "actual-rate gate prevented continuous A/B checkpoints",
            result["failures"],
        )
        self.assertEqual(result["tail"]["missingScheduledDelays"], [])
        self.assertEqual(len(result["tail"]["playbackActivationTimeline"]), 22)
        self.assertTrue(all(
            not report["missingPhases"]
            for report in result["tail"]["observationTaskPhases"]["byDelay"].values()
        ))

    def test_missing_pre_rate_activation_observation_is_rejected(self) -> None:
        core = self.core()
        core["events"] = [
            event for event in core["events"]
            if not event["kind"].startswith("playbackActivation.")
        ]
        first = self.checkpoint(1, 10, 20, 30, 40)
        second = self.checkpoint(2, 11, 21, 31, 41)
        result = analyzer.validate({
            "preRateState": first,
            "preRateCore": core,
            "tailState": first,
            "tailCore": self.tail_core(),
            "checkpointA": first,
            "checkpointB": second,
            "coreA": core,
            "coreB": core,
        })
        self.assertEqual(result["outcome"], "failed")
        self.assertIn(
            "pre-rate observation is missing call.before",
            result["failures"],
        )

    def test_sync_enqueue_without_return_reports_enter_as_last_stage(self) -> None:
        tail = self.tail_core()
        tail["events"] = [
            event for event in tail["events"]
            if event.get("kind") not in {
                "playbackDelivery.stage.video.enqueueImmediately.returned",
                "playbackDelivery.stage.video.enqueueImmediately.outcome",
            }
        ]
        first = self.checkpoint(1, 10, 20, 30, 40)
        second = self.checkpoint(2, 11, 21, 31, 41)
        result = analyzer.validate({
            "preRateState": first,
            "preRateCore": self.core(),
            "tailState": first,
            "tailCore": tail,
            "checkpointA": first,
            "checkpointB": second,
            "coreA": self.core(),
            "coreB": self.core(),
        })
        self.assertEqual(
            result["tail"]["lastDeliveryStages"]["video"]["stage"],
            "enqueueImmediately.enter",
        )
        self.assertIsNone(
            result["tail"]["lastDeliveryStages"]["video"]["outcome"]
        )

    def test_disabled_observer_failure_preserves_tail_without_core_events(self) -> None:
        pre_rate = self.checkpoint(0, 6, 6, 49, 48)
        tail = self.checkpoint(0, 10, 10, 54, 53)
        tail["actualRate"] = "0.0"
        result = analyzer.validate({
            "preRateState": pre_rate,
            "tailState": tail,
            "checkpointA": None,
            "checkpointB": None,
        }, observer_mode="disabled")

        self.assertEqual(result["observerMode"], "disabled")
        self.assertEqual(result["controlOutcome"]["outcome"], "failed")
        self.assertFalse(result["controlOutcome"]["actualRateGatePassed"])
        self.assertEqual(result["tail"]["state"], tail)
        self.assertIn(
            "actual-rate gate prevented continuous A/B checkpoints",
            result["failures"],
        )

    def test_disabled_observer_passes_without_core_events(self) -> None:
        first = self.checkpoint(1, 10, 20, 30, 40)
        second = self.checkpoint(2, 11, 21, 31, 41)
        result = analyzer.validate({
            "preRateState": first,
            "tailState": first,
            "checkpointA": first,
            "checkpointB": second,
        }, observer_mode="disabled")

        self.assertEqual(result["observerMode"], "disabled")
        self.assertEqual(result["outcome"], "passed")
        self.assertEqual(result["controlOutcome"]["outcome"], "passed")
        self.assertTrue(result["controlOutcome"]["actualRateGatePassed"])
        self.assertTrue(
            result["controlOutcome"]["continuousCheckpointsCaptured"]
        )

    def test_sufficient_reapply_passes_from_state_only_evidence(self) -> None:
        pre_rate = self.reapply_checkpoint(actual_rate=0, effective_rate=0)
        tail = self.reapply_checkpoint(actual_rate=1, effective_rate=1)
        first = self.reapply_checkpoint(
            position=1,
            video=10,
            renderer=20,
            audio=30,
            audio_renderer=40,
        )
        second = self.reapply_checkpoint(
            position=2,
            video=11,
            renderer=21,
            audio=31,
            audio_renderer=41,
        )
        result = analyzer.validate({
            "preRateState": pre_rate,
            "tailState": tail,
            "checkpointA": first,
            "checkpointB": second,
        }, observer_mode="disabled", experiment_mode="sufficient-reapply")

        self.assertEqual(result["outcome"], "passed")
        self.assertEqual(
            result["classification"],
            "reapply_restored_continuous_playback",
        )
        self.assertEqual(result["causalConclusion"], "hypothesis_supported")
        self.assertEqual(result["controlOutcome"]["attemptCount"], 1)
        self.assertEqual(result["controlOutcome"]["claimCount"], 1)

    def test_sufficient_reapply_classifies_video_never_sufficient(self) -> None:
        pre_rate = self.reapply_checkpoint(actual_rate=0, effective_rate=0)
        tail = self.reapply_checkpoint(
            actual_rate=0,
            effective_rate=0,
            video_sufficient=False,
            audio_sufficient=True,
            attempt_count=0,
            outcome="timedOut",
        )
        result = analyzer.validate({
            "preRateState": pre_rate,
            "tailState": tail,
            "checkpointA": None,
            "checkpointB": None,
        }, observer_mode="disabled", experiment_mode="sufficient-reapply")

        self.assertEqual(result["outcome"], "inconclusive")
        self.assertEqual(result["classification"], "video_never_sufficient")
        self.assertEqual(result["causalConclusion"], "not_evaluated")
        self.assertFalse(result["controlOutcome"]["hypothesisRejected"])
        self.assertEqual(result["tail"]["state"], tail)

    def test_sufficient_reapply_rejects_hypothesis_only_after_one_claim(self) -> None:
        pre_rate = self.reapply_checkpoint(actual_rate=0, effective_rate=0)
        tail = self.reapply_checkpoint(actual_rate=0, effective_rate=0)
        result = analyzer.validate({
            "preRateState": pre_rate,
            "tailState": tail,
            "checkpointA": None,
            "checkpointB": None,
        }, observer_mode="disabled", experiment_mode="sufficient-reapply")

        self.assertEqual(result["outcome"], "failed")
        self.assertEqual(
            result["classification"],
            "reapply_did_not_activate_rate",
        )
        self.assertEqual(result["causalConclusion"], "hypothesis_rejected")
        self.assertTrue(result["controlOutcome"]["hypothesisRejected"])

    def test_sufficient_reapply_does_not_evaluate_duplicate_attempt(self) -> None:
        pre_rate = self.reapply_checkpoint(actual_rate=0, effective_rate=0)
        tail = self.reapply_checkpoint(
            actual_rate=0,
            effective_rate=0,
            attempt_count=2,
        )
        result = analyzer.validate({
            "preRateState": pre_rate,
            "tailState": tail,
            "checkpointA": None,
            "checkpointB": None,
        }, observer_mode="disabled", experiment_mode="sufficient-reapply")

        self.assertEqual(result["classification"], "preconditions_not_established")
        self.assertEqual(result["causalConclusion"], "not_evaluated")
        self.assertFalse(result["controlOutcome"]["hypothesisRejected"])

    @staticmethod
    def checkpoint(position, video, renderer, audio, audio_renderer):
        return {
            "session": "fixture-session",
            "position": str(position),
            "videoSamples": str(video),
            "rendererInputs": str(renderer),
            "audioSamples": str(audio),
            "audioRendererSamples": str(audio_renderer),
            "actualRate": "1.0",
            "targetRate": "1.0",
            "audioRendererStatus": "rendering",
            "audioRendererError": "none",
        }

    @classmethod
    def reapply_checkpoint(
        cls,
        position=0,
        video=10,
        renderer=10,
        audio=49,
        audio_renderer=48,
        actual_rate=1,
        effective_rate=1,
        video_sufficient=True,
        audio_sufficient=True,
        attempt_count=1,
        outcome="reapplied",
    ):
        state = cls.checkpoint(position, video, renderer, audio, audio_renderer)
        state.update({
            "hasAudio": "true",
            "actualRate": str(actual_rate),
            "effectiveRate": str(effective_rate),
            "reapplyActivationSequence": "1",
            "reapplyAnchorValue": "0",
            "reapplyAnchorTimescale": "1",
            "reapplyAnchorEpoch": "0",
            "reapplyAnchorFlags": "1",
            "reapplyRequestedRate": "1.0",
            "reapplyAudioRequired": "true",
            "reapplyVideoSufficient": str(video_sufficient).lower(),
            "reapplyAudioSufficient": str(audio_sufficient).lower(),
            "reapplyDirectRate": "0.0",
            "reapplyEffectiveRate": "0.0",
            "reapplyAttemptCount": str(attempt_count),
            "reapplyClaimCount": str(attempt_count),
            "reapplyOutcome": outcome,
        })
        return state

    @staticmethod
    def core(include_rate_activated=True):
        details = {key: "fixture" for key in {
            "asbd.sampleRate", "asbd.formatID", "asbd.formatFlags",
            "asbd.bytesPerPacket", "asbd.framesPerPacket", "asbd.bytesPerFrame",
            "asbd.channelsPerFrame", "asbd.bitsPerChannel", "channelLayoutSize",
            "magicCookieSize", "magicCookieHash", "ffmpeg.cookieSource",
            "ffmpeg.payloadByteCount", "ffmpeg.packetPTS", "ffmpeg.packetDTS",
            "ffmpeg.packetDuration", "ffmpeg.timeBaseNumerator",
            "ffmpeg.timeBaseDenominator", "presentationTime.value",
            "presentationTime.timescale", "decodeTime.value", "decodeTime.timescale",
            "duration.value", "duration.timescale",
        }}
        events = [
            {"kind": "audioRenderer.firstEnqueue", "details": details},
            {"kind": "audioRenderer.prerollCompleted", "details": {}},
            {"kind": "audioRenderer.statusChanged", "details": {}},
            {
                "kind": "playbackActivation.observation",
                "sequenceNumber": 5,
                "details": {"phase": "call.returned"},
            },
            {
                "kind": "playbackActivation.observation",
                "sequenceNumber": 4,
                "details": {"phase": "call.before"},
            },
        ]
        if include_rate_activated:
            events.append({"kind": "audioRenderer.rateActivated", "details": {}})
        return {
            "snapshot": {"sampleCount": 1, "audioSampleBufferCount": 1},
            "events": events,
        }

    @classmethod
    def tail_core(cls):
        core = cls.core()
        observation_details = {
            "activationSequence": "1",
            "streamEpoch": "1",
            "audioStreamEpoch": "1",
            "delaysRateChangeUntilHasSufficientMediaData": "false",
            "synchronizerRate": "1.0",
            "directTimebaseRate": "0.0",
            "effectiveTimebaseRate": "0.0",
            "directTimebaseTimeSeconds": "0.0",
            "videoStatus": "rendering",
            "videoHasSufficientMedia": "false",
            "videoReadyForMoreMedia": "true",
            "videoAcceptedMinPTSSeconds": "0.0",
            "videoAcceptedMaxPTSSeconds": "0.4",
            "videoAcceptedMinDTSSeconds": "0.0",
            "videoAcceptedMaxDTSSeconds": "0.3",
            "videoAcceptedMaxEndSeconds": "0.5",
            "videoAcceptedCount": "10",
            "audioStatus": "rendering",
            "audioHasSufficientMedia": "true",
            "audioReadyForMoreMedia": "true",
            "audioAcceptedMinPTSSeconds": "0.0",
            "audioAcceptedMaxEndSeconds": "1.0",
            "audioAcceptedCount": "49",
        }
        core["events"].extend({
            "kind": "playbackActivation.observation",
            "sequenceNumber": 10 + index,
            "details": {
                **observation_details,
                "phase": "scheduledSample",
                "delayMs": str(delay),
            },
        } for index, delay in enumerate((10, 50, 100, 500, 2_000)))
        sequence = 20
        for delay in (10, 50, 100, 500, 2_000):
            for phase in analyzer.OBSERVATION_TASK_PHASES:
                core["events"].append({
                    "kind": "playbackActivation.stageMarker",
                    "sequenceNumber": sequence,
                    "details": {
                        "activationSequence": "1",
                        "streamEpoch": "1",
                        "audioStreamEpoch": "1",
                        "phase": phase,
                        "delayMs": str(delay),
                    },
                })
                sequence += 1
        core["events"].extend([
            {
                "kind": "playbackDelivery.stage.video.enqueueImmediately.enter",
                "sequenceNumber": sequence,
                "details": {
                    "streamEpoch": "1",
                    "sampleOrdinal": "7",
                    "presentationTimeSeconds": "0.2",
                    "decodeTimeSeconds": "0.16",
                },
            },
            {
                "kind": "playbackDelivery.stage.video.enqueueImmediately.returned",
                "sequenceNumber": sequence + 1,
                "details": {
                    "streamEpoch": "1",
                    "sampleOrdinal": "7",
                    "presentationTimeSeconds": "0.2",
                    "decodeTimeSeconds": "0.16",
                },
            },
            {
                "kind": "playbackDelivery.stage.video.enqueueImmediately.outcome",
                "sequenceNumber": sequence + 2,
                "details": {
                    "streamEpoch": "1",
                    "sampleOrdinal": "7",
                    "presentationTimeSeconds": "0.2",
                    "decodeTimeSeconds": "0.16",
                    "outcome": "accepted",
                },
            },
            {
                "kind": "playbackDelivery.stage.audio.enqueueImmediately.outcome",
                "sequenceNumber": sequence + 3,
                "details": {
                    "streamEpoch": "1",
                    "sampleOrdinal": "33",
                    "presentationTimeSeconds": "0.68",
                    "decodeTimeSeconds": "0.68",
                    "outcome": "accepted",
                },
            },
        ])
        return core


if __name__ == "__main__":
    unittest.main()
