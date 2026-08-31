---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:panorama-to-portal-exit",
  "title": "Panorama 控件退出到 portal",
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
  "estimatedCostMillis": 210000,
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
      "callId": "call:presentation-tour:panorama-to-portal-exit:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:panorama-to-portal-exit:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:panorama-to-portal-exit:03",
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
      "callId": "call:presentation-tour:panorama-to-portal-exit:04",
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
      "callId": "call:presentation-tour:panorama-to-portal-exit:05",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "summonControls": true
      },
      "callId": "call:presentation-tour:panorama-to-portal-exit:06",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-panorama@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:panorama-to-portal-exit:07",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.arm@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "from": "panorama"
      },
      "callId": "call:presentation-tour:panorama-to-portal-exit:08",
      "maxInvocations": 1,
      "operation": "operation:presentation.exit-spatial@1"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:panorama-to-portal-exit:07/generationToken"
      },
      "callId": "call:presentation-tour:panorama-to-portal-exit:09",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.fetch@1"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:panorama-to-portal-exit:07/generationToken"
      },
      "callId": "call:presentation-tour:panorama-to-portal-exit:10",
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
      "id": "obligation:presentation-tour:panorama-to-portal-exit:o01:default",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:panorama-to-portal-exit:08",
      "rubric": "rubric:presentation-tour.panorama-to-portal-exit.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:presentation-tour:panorama-to-portal-exit:o01:default"
  }
}
---
# Panorama 控件退出到 portal

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
