---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:portal-to-panorama-explicit-entry",
  "title": "Portal 通过 Enter Panorama 显式进入 panorama",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:mode-transitions:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 180000,
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
      "callId": "call:presentation-tour:portal-to-panorama-explicit-entry:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:portal-to-panorama-explicit-entry:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:portal-to-panorama-explicit-entry:03",
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
      "callId": "call:presentation-tour:portal-to-panorama-explicit-entry:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:portal-to-panorama-explicit-entry:05",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:portal-to-panorama-explicit-entry:06",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.arm@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30
      },
      "callId": "call:presentation-tour:portal-to-panorama-explicit-entry:07",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-panorama@1"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:portal-to-panorama-explicit-entry:06/generationToken"
      },
      "callId": "call:presentation-tour:portal-to-panorama-explicit-entry:08",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.fetch@1"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:portal-to-panorama-explicit-entry:06/generationToken"
      },
      "callId": "call:presentation-tour:portal-to-panorama-explicit-entry:09",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.disarm@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:presentation-tour:portal-to-panorama-explicit-entry:o01:default",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:portal-to-panorama-explicit-entry:07",
      "rubric": "rubric:presentation-tour.portal-to-panorama-explicit-entry.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:presentation-tour:portal-to-panorama-explicit-entry:o01:default"
  }
}
---
# Portal 通过 Enter Panorama 显式进入 panorama

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
