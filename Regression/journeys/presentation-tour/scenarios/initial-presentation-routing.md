---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:initial-presentation-routing",
  "title": "首开呈现由来源分类或持久格式覆盖决定",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:mode-transitions:c01"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 630000,
  "staticCases": [
    "source-flat",
    "source-panorama",
    "persisted-flat",
    "persisted-panorama"
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
      "callId": "call:presentation-tour:initial-presentation-routing:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:03",
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
      "callId": "call:presentation-tour:initial-presentation-routing:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:initial-presentation-routing:05",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:initial-presentation-routing:06",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:07",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-APMP-180-example.mp4"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:08",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "either-main-window"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:09",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:initial-presentation-routing:10",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:initial-presentation-routing:11",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:12",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-APMP-180-example.mp4"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:13",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "either-main-window"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:14",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "flat",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:15",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:initial-presentation-routing:16",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:initial-presentation-routing:17",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:18",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-APMP-180-example.mp4",
        "relatedResults": [
          "result://call:presentation-tour:initial-presentation-routing:16/sourceIdentity",
          "result://call:presentation-tour:initial-presentation-routing:16/contentRevision"
        ]
      },
      "callId": "call:presentation-tour:initial-presentation-routing:19",
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
      "callId": "call:presentation-tour:initial-presentation-routing:20",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:initial-presentation-routing:21",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:22",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:23",
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
      "callId": "call:presentation-tour:initial-presentation-routing:24",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:25",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:initial-presentation-routing:26",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:initial-presentation-routing:27",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:28",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4",
        "relatedResults": [
          "result://call:presentation-tour:initial-presentation-routing:26/sourceIdentity",
          "result://call:presentation-tour:initial-presentation-routing:26/contentRevision"
        ]
      },
      "callId": "call:presentation-tour:initial-presentation-routing:29",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "either-main-window"
      },
      "callId": "call:presentation-tour:initial-presentation-routing:30",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "source-flat",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:presentation-tour:initial-presentation-routing:o01:source-flat",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:initial-presentation-routing:03",
      "rubric": "rubric:presentation-tour.initial-presentation-routing.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "source-panorama",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:presentation-tour:initial-presentation-routing:o01:source-panorama",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:initial-presentation-routing:08",
      "rubric": "rubric:presentation-tour.initial-presentation-routing.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "persisted-flat",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:presentation-tour:initial-presentation-routing:o01:persisted-flat",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:initial-presentation-routing:19",
      "rubric": "rubric:presentation-tour.initial-presentation-routing.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "persisted-panorama",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:presentation-tour:initial-presentation-routing:o01:persisted-panorama",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:initial-presentation-routing:29",
      "rubric": "rubric:presentation-tour.initial-presentation-routing.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:initial-presentation-routing:o01:source-flat"
      },
      {
        "observation": "obligation:presentation-tour:initial-presentation-routing:o01:source-panorama"
      },
      {
        "observation": "obligation:presentation-tour:initial-presentation-routing:o01:persisted-flat"
      },
      {
        "observation": "obligation:presentation-tour:initial-presentation-routing:o01:persisted-panorama"
      }
    ]
  }
}
---
# 首开呈现由来源分类或持久格式覆盖决定

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
