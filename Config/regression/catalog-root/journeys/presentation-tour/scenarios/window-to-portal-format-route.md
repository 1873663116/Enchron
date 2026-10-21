---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:window-to-portal-format-route",
  "title": "应用全景格式从 window 路由到 portal",
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
  "estimatedCostMillis": 150000,
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
      "callId": "call:presentation-tour:window-to-portal-format-route:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:window-to-portal-format-route:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:window-to-portal-format-route:03",
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
      "callId": "call:presentation-tour:window-to-portal-format-route:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:window-to-portal-format-route:05",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.arm@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:window-to-portal-format-route:06",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:window-to-portal-format-route:05/generationToken"
      },
      "callId": "call:presentation-tour:window-to-portal-format-route:07",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.fetch@1"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:window-to-portal-format-route:05/generationToken"
      },
      "callId": "call:presentation-tour:window-to-portal-format-route:08",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.disarm@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:presentation-tour:window-to-portal-format-route:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "transition-trace@1",
      "evidenceType": "transition.trace",
      "id": "obligation:presentation-tour:window-to-portal-format-route:o01:default",
      "oracle": "oracle:agent-structured-transition@1",
      "producedByCall": "call:presentation-tour:window-to-portal-format-route:07",
      "rubric": "rubric:presentation-tour.window-to-portal-format-route.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:presentation-tour:window-to-portal-format-route:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:presentation-tour:window-to-portal-format-route:09",
      "rubric": "rubric:presentation-tour.window-to-portal-format-route.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:window-to-portal-format-route:o01:default"
      },
      {
        "observation": "obligation:presentation-tour:window-to-portal-format-route:o02:default"
      }
    ]
  }
}
---
# 应用全景格式从 window 路由到 portal

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
