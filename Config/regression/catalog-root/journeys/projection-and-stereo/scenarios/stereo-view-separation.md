---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:projection-and-stereo:stereo-view-separation",
  "title": "立体打包被分离为正确单眼画面",
  "journey": "journey:projection-and-stereo",
  "promiseRefs": [
    "promise:picture-interpretation:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 400000,
  "staticCases": [
    "side-by-side",
    "top-bottom",
    "mv-hevc-two-view"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "projection-corpus-ready",
      "schema": "fixture-set.projection-stereo@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:projection-and-stereo:stereo-view-separation:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:projection-and-stereo:stereo-view-separation:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-180_3D.mp4"
      },
      "callId": "call:projection-and-stereo:stereo-view-separation:03",
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
      "callId": "call:projection-and-stereo:stereo-view-separation:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "sideBySide"
      },
      "callId": "call:projection-and-stereo:stereo-view-separation:05",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {},
      "callId": "call:projection-and-stereo:stereo-view-separation:06",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:projection-and-stereo:stereo-view-separation:07",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-180_3D_TB.mp4"
      },
      "callId": "call:projection-and-stereo:stereo-view-separation:08",
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
      "callId": "call:projection-and-stereo:stereo-view-separation:09",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "topBottom"
      },
      "callId": "call:projection-and-stereo:stereo-view-separation:10",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {},
      "callId": "call:projection-and-stereo:stereo-view-separation:11",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:projection-and-stereo:stereo-view-separation:12",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-3D-example.mp4"
      },
      "callId": "call:projection-and-stereo:stereo-view-separation:13",
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
      "callId": "call:projection-and-stereo:stereo-view-separation:14",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 500
      },
      "callId": "call:projection-and-stereo:stereo-view-separation:15",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "side-by-side",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:projection-and-stereo:stereo-view-separation:o01:side-by-side",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:projection-and-stereo:stereo-view-separation:05",
      "rubric": "rubric:projection-and-stereo.stereo-view-separation.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "top-bottom",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:projection-and-stereo:stereo-view-separation:o01:top-bottom",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:projection-and-stereo:stereo-view-separation:10",
      "rubric": "rubric:projection-and-stereo.stereo-view-separation.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "mv-hevc-two-view",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:projection-and-stereo:stereo-view-separation:o01:mv-hevc-two-view",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:projection-and-stereo:stereo-view-separation:15",
      "rubric": "rubric:projection-and-stereo.stereo-view-separation.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:projection-and-stereo:stereo-view-separation:o01:side-by-side"
      },
      {
        "observation": "obligation:projection-and-stereo:stereo-view-separation:o01:top-bottom"
      },
      {
        "observation": "obligation:projection-and-stereo:stereo-view-separation:o01:mv-hevc-two-view"
      }
    ]
  }
}
---
# 立体打包被分离为正确单眼画面

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
