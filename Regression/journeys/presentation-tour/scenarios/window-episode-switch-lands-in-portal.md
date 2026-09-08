---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:window-episode-switch-lands-in-portal",
  "title": "窗口内切换到全景剧集时翻到 portal",
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
      "callId": "call:presentation-tour:window-episode-switch-lands-in-portal:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:window-episode-switch-lands-in-portal:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:window-episode-switch-lands-in-portal:03",
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
      "callId": "call:presentation-tour:window-episode-switch-lands-in-portal:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-episodes"
        ],
        "labels": [
          "180_3D.mp4"
        ],
        "labelsAfterIdentifiers": true,
        "summonControls": true
      },
      "callId": "call:presentation-tour:window-episode-switch-lands-in-portal:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:window-episode-switch-lands-in-portal:06",
      "maxInvocations": 1,
      "operation": "operation:harness.assert-channels@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "portal"
      },
      "callId": "call:presentation-tour:window-episode-switch-lands-in-portal:07",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "portal",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "relatedResults": [
          "result://call:presentation-tour:window-episode-switch-lands-in-portal:07/response"
        ]
      },
      "callId": "call:presentation-tour:window-episode-switch-lands-in-portal:08",
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
      "id": "obligation:presentation-tour:window-episode-switch-lands-in-portal:o01:default",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:window-episode-switch-lands-in-portal:07",
      "rubric": "rubric:presentation-tour.window-episode-switch-lands-in-portal.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:presentation-tour:window-episode-switch-lands-in-portal:o02:default",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:presentation-tour:window-episode-switch-lands-in-portal:08",
      "rubric": "rubric:presentation-tour.window-episode-switch-lands-in-portal.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:window-episode-switch-lands-in-portal:o01:default"
      },
      {
        "observation": "obligation:presentation-tour:window-episode-switch-lands-in-portal:o02:default"
      }
    ]
  }
}
---
# 窗口内切换到全景剧集时翻到 portal

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
