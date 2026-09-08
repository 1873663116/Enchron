---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:docked-episode-switch-settles-and-exits",
  "title": "Docked 内切换剧集后重新落地并安全退出",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:mode-transitions:c05"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 200000,
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
      "callId": "call:presentation-tour:docked-episode-switch-settles-and-exits:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:docked-episode-switch-settles-and-exits:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:docked-episode-switch-settles-and-exits:03",
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
      "callId": "call:presentation-tour:docked-episode-switch-settles-and-exits:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "summonControls": true
      },
      "callId": "call:presentation-tour:docked-episode-switch-settles-and-exits:05",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-docked-skybox@1"
    },
    {
      "arguments": {
        "context": "docked",
        "identifiers": [
          "PlayerPanel-menu-more",
          "PlayerPanel-menu-episodes"
        ],
        "labels": [
          "180_3D.mp4"
        ],
        "labelsAfterIdentifiers": true,
        "summonControls": true
      },
      "callId": "call:presentation-tour:docked-episode-switch-settles-and-exits:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:docked-episode-switch-settles-and-exits:07",
      "maxInvocations": 1,
      "operation": "operation:harness.assert-channels@2"
    },
    {
      "arguments": {
        "context": "docked",
        "deadlineSeconds": 30,
        "identifier": "PlayerUI-spatial-state",
        "requireMatchedElement": true,
        "summonControls": true
      },
      "callId": "call:presentation-tour:docked-episode-switch-settles-and-exits:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "from": "docked"
      },
      "callId": "call:presentation-tour:docked-episode-switch-settles-and-exits:09",
      "maxInvocations": 1,
      "operation": "operation:presentation.exit-spatial@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:presentation-tour:docked-episode-switch-settles-and-exits:o01:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:presentation-tour:docked-episode-switch-settles-and-exits:08",
      "rubric": "rubric:presentation-tour.docked-episode-switch-settles-and-exits.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:presentation-tour:docked-episode-switch-settles-and-exits:o02:default",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:docked-episode-switch-settles-and-exits:09",
      "rubric": "rubric:presentation-tour.docked-episode-switch-settles-and-exits.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:docked-episode-switch-settles-and-exits:o01:default"
      },
      {
        "observation": "obligation:presentation-tour:docked-episode-switch-settles-and-exits:o02:default"
      }
    ]
  }
}
---
# Docked 内切换剧集后重新落地并安全退出

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
