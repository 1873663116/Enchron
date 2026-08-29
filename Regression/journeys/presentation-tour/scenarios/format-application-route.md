---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:format-application-route",
  "title": "格式应用按 Flat 或全景投影路由",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:format-editing:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 270000,
  "staticCases": [
    "panoramic-to-portal",
    "flat-to-window"
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
      "callId": "call:presentation-tour:format-application-route:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:format-application-route:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-180_3D.mp4"
      },
      "callId": "call:presentation-tour:format-application-route:03",
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
      "callId": "call:presentation-tour:format-application-route:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:format-application-route:05",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.arm@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:format-application-route:06",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:format-application-route:05/generationToken"
      },
      "callId": "call:presentation-tour:format-application-route:07",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.fetch@1"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:format-application-route:05/generationToken"
      },
      "callId": "call:presentation-tour:format-application-route:08",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.disarm@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:format-application-route:09",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:format-application-route:10",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:format-application-route:11",
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
      "callId": "call:presentation-tour:format-application-route:12",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:format-application-route:13",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.arm@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "flat",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:format-application-route:14",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:format-application-route:13/generationToken"
      },
      "callId": "call:presentation-tour:format-application-route:15",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.fetch@1"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:format-application-route:13/generationToken"
      },
      "callId": "call:presentation-tour:format-application-route:16",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.disarm@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "panoramic-to-portal",
      "evidenceSchema": "transition-trace@1",
      "evidenceType": "transition.trace",
      "id": "obligation:presentation-tour:format-application-route:o01:panoramic-to-portal",
      "oracle": "oracle:agent-structured-transition@1",
      "producedByCall": "call:presentation-tour:format-application-route:07",
      "rubric": "rubric:presentation-tour.format-application-route.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "flat-to-window",
      "evidenceSchema": "transition-trace@1",
      "evidenceType": "transition.trace",
      "id": "obligation:presentation-tour:format-application-route:o01:flat-to-window",
      "oracle": "oracle:agent-structured-transition@1",
      "producedByCall": "call:presentation-tour:format-application-route:15",
      "rubric": "rubric:presentation-tour.format-application-route.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:format-application-route:o01:panoramic-to-portal"
      },
      {
        "observation": "obligation:presentation-tour:format-application-route:o01:flat-to-window"
      }
    ]
  }
}
---
# 格式应用按 Flat 或全景投影路由

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
