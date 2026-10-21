---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:portal-episode-switch-lands-in-window",
  "title": "portal 内切换到平面剧集时翻回 window",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:mode-transitions:c02"
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
      "callId": "call:presentation-tour:portal-episode-switch-lands-in-window:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:portal-episode-switch-lands-in-window:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-180_3D.mp4"
      },
      "callId": "call:presentation-tour:portal-episode-switch-lands-in-window:03",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "portal"
      },
      "callId": "call:presentation-tour:portal-episode-switch-lands-in-window:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "portal",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-episodes"
        ],
        "labels": [
          "sdr-bframe-multiaudio-avsync-120s.mp4"
        ],
        "labelsAfterIdentifiers": true,
        "summonControls": true
      },
      "callId": "call:presentation-tour:portal-episode-switch-lands-in-window:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:portal-episode-switch-lands-in-window:06",
      "maxInvocations": 1,
      "operation": "operation:harness.assert-channels@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:presentation-tour:portal-episode-switch-lands-in-window:07",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "relatedResults": [
          "result://call:presentation-tour:portal-episode-switch-lands-in-window:07/response"
        ]
      },
      "callId": "call:presentation-tour:portal-episode-switch-lands-in-window:08",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:presentation-tour:portal-episode-switch-lands-in-window:o01:default",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:portal-episode-switch-lands-in-window:07",
      "rubric": "rubric:presentation-tour.portal-episode-switch-lands-in-window.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:presentation-tour:portal-episode-switch-lands-in-window:o02:default",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:presentation-tour:portal-episode-switch-lands-in-window:08",
      "rubric": "rubric:presentation-tour.portal-episode-switch-lands-in-window.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:portal-episode-switch-lands-in-window:o01:default"
      },
      {
        "observation": "obligation:presentation-tour:portal-episode-switch-lands-in-window:o02:default"
      }
    ]
  }
}
---
# portal 内切换到平面剧集时翻回 window

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
