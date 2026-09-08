---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:panorama-episode-switch-settles-with-pixels",
  "title": "Panorama 内切换剧集后以像素证明落地",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:mode-transitions:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 230000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "presentation-fixtures-ready",
      "schema": "fixture-set.presentation-tour@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:03",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono",
        "summonControls": true
      },
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:05",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "summonControls": true
      },
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:06",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-panorama@1"
    },
    {
      "arguments": {
        "context": "panorama",
        "identifiers": [
          "PlayerPanel-menu-more",
          "PlayerPanel-menu-episodes"
        ],
        "labels": [
          "360.mp4"
        ],
        "labelsAfterIdentifiers": true,
        "summonControls": true
      },
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:08",
      "maxInvocations": 1,
      "operation": "operation:harness.assert-channels@2"
    },
    {
      "arguments": {
        "context": "panorama",
        "deadlineSeconds": 30,
        "identifier": "PlayerUI-spatial-state",
        "requireMatchedElement": true,
        "summonControls": true
      },
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "panorama",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "relatedResults": [
          "result://call:presentation-tour:panorama-episode-switch-settles-with-pixels:09/matchedElement",
          "result://call:presentation-tour:panorama-episode-switch-settles-with-pixels:09/response"
        ]
      },
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:10",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "from": "panorama"
      },
      "callId": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:11",
      "maxInvocations": 1,
      "operation": "operation:presentation.exit-spatial@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:presentation-tour:panorama-episode-switch-settles-with-pixels:o01:default",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:10",
      "rubric": "rubric:presentation-tour.panorama-episode-switch-settles-with-pixels.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:presentation-tour:panorama-episode-switch-settles-with-pixels:o02:default",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:panorama-episode-switch-settles-with-pixels:11",
      "rubric": "rubric:presentation-tour.panorama-episode-switch-settles-with-pixels.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:panorama-episode-switch-settles-with-pixels:o01:default"
      },
      {
        "observation": "obligation:presentation-tour:panorama-episode-switch-settles-with-pixels:o02:default"
      }
    ]
  }
}
---
# Panorama 内切换剧集后以像素证明落地

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
