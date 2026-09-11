from __future__ import annotations

import json
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT_PATH = REPOSITORY_ROOT / "Config/regression/catalog-v2.json"

CASE_SCOPED_RUBRICS = {
    "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1": (
        "dv-profile-5",
        "dv-profile-7-dual",
        "dv-profile-8-hdr10",
        "dv-profile-8-hlg",
        "dv-profile-10",
    ),
    "rubric:dynamic-range-interpretation.hdr10-hlg-interpretation.o01@1": (
        "hdr10",
        "hlg",
    ),
    "rubric:format-coverage.audio-delivery-codec-matrix.o01@1": (
        "ac3",
        "eac3-joc",
        "dts",
        "truehd",
        "vorbis",
        "aac",
        "flac",
    ),
    "rubric:network-resilience.playback-failure-category-matrix.o01@1": (
        "connection-interrupted",
        "file-missing",
        "access-refused",
        "data-corrupt",
    ),
    "rubric:presentation-tour.format-editor-hosts-window-and-portal.o01@1": (
        "window",
        "portal",
    ),
    "rubric:issue-surface-behavior.source-failure-guidance-matrix.o01@1": (
        "credentials-rejected",
        "server-unreachable",
        "invalid-address",
        "requires-https",
    ),
    "rubric:local-media-lifecycle.audio-track-switch-same-session.o01@1": (
        "unique-label",
        "duplicate-label-index-0",
        "duplicate-label-index-1",
    ),
    "rubric:presentation-tour.format-application-route.o01@1": (
        "panoramic-to-portal",
        "flat-to-window",
    ),
    "rubric:presentation-tour.initial-presentation-routing.o01@1": (
        "source-flat",
        "source-panorama",
        "persisted-flat",
        "persisted-panorama",
    ),
    "rubric:presentation-tour.spatial-controls-summon.o01@1": (
        "docked-show",
        "docked-hide",
        "panorama-show",
        "panorama-hide",
    ),
    "rubric:presentation-tour.track-selection-survives-seek-and-presentation.o01@1": (
        "seek",
        "window-docked-window",
        "window-portal-window",
        "format-replacement",
    ),
    "rubric:projection-and-stereo.panorama-coverage-angle.o01@1": (
        "equirectangular-180",
        "equirectangular-360",
        "custom-angle-200",
        "custom-angle-240",
    ),
    "rubric:projection-and-stereo.stereo-view-separation.o01@1": (
        "side-by-side",
        "top-bottom",
        "mv-hevc-two-view",
    ),
}


class RegressionRubricCaseScopeTests(unittest.TestCase):
    def test_success_conjoins_every_case_scoped_obligation(self) -> None:
        blueprint = json.loads(BLUEPRINT_PATH.read_text(encoding="utf-8"))
        scenarios_by_rubric = {
            rubric_id: [
                scenario
                for scenario in blueprint["scenarios"]
                if any(
                    obligation["rubric"] == rubric_id
                    for obligation in scenario["obligations"]
                )
            ]
            for rubric_id in CASE_SCOPED_RUBRICS
        }

        for rubric_id, expected_cases in CASE_SCOPED_RUBRICS.items():
            with self.subTest(rubric=rubric_id):
                self.assertEqual(len(scenarios_by_rubric[rubric_id]), 1)
                scenario = scenarios_by_rubric[rubric_id][0]
                obligations = [
                    obligation
                    for obligation in scenario["obligations"]
                    if obligation["rubric"] == rubric_id
                ]
                self.assertEqual(
                    tuple(obligation["caseKey"] for obligation in obligations),
                    expected_cases,
                )
                self.assertEqual(tuple(scenario["staticCases"]), expected_cases)
                self.assertEqual(
                    scenario["success"],
                    {
                        "all": [
                            {"observation": obligation["id"]}
                            for obligation in obligations
                        ]
                    },
                )


if __name__ == "__main__":
    unittest.main()
