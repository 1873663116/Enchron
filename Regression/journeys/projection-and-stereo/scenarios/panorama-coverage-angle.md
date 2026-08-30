---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:projection-and-stereo:panorama-coverage-angle",
  "title": "180°、360° 与 Custom Angle 覆盖角",
  "journey": "journey:projection-and-stereo",
  "promiseRefs": [
    "promise:picture-interpretation:c05"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 540000,
  "staticCases": [
    "equirectangular-180",
    "equirectangular-360",
    "custom-angle-200",
    "custom-angle-240"
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
      "callId": "call:projection-and-stereo:panorama-coverage-angle:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-180_3D.mp4"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:03",
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
      "callId": "call:projection-and-stereo:panorama-coverage-angle:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "sideBySide"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:05",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "positionMillionths": 0
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:06",
      "maxInvocations": 1,
      "operation": "operation:playback.seek@2"
    },
    {
      "arguments": {
        "context": "portal",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:07",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:projection-and-stereo:panorama-coverage-angle:08",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:09",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-360.mp4"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:10",
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
      "callId": "call:projection-and-stereo:panorama-coverage-angle:11",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular360",
        "stereoLayout": "mono"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:12",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "positionMillionths": 0
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:13",
      "maxInvocations": 1,
      "operation": "operation:playback.seek@2"
    },
    {
      "arguments": {
        "context": "portal",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:14",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:projection-and-stereo:panorama-coverage-angle:15",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:16",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-APMP-180-example.mp4"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:17",
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
      "callId": "call:projection-and-stereo:panorama-coverage-angle:18",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "horizontalCoverageDegrees": 200,
        "projection": "customAngle",
        "stereoLayout": "mono"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:19",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "positionMillionths": 0
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:20",
      "maxInvocations": 1,
      "operation": "operation:playback.seek@2"
    },
    {
      "arguments": {
        "context": "portal",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:21",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:projection-and-stereo:panorama-coverage-angle:22",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:23",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-APMP-180-example.mp4"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:24",
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
      "callId": "call:projection-and-stereo:panorama-coverage-angle:25",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "horizontalCoverageDegrees": 240,
        "projection": "customAngle",
        "stereoLayout": "mono"
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:26",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "positionMillionths": 0
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:27",
      "maxInvocations": 1,
      "operation": "operation:playback.seek@2"
    },
    {
      "arguments": {
        "context": "portal",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:projection-and-stereo:panorama-coverage-angle:28",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "equirectangular-180",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:projection-and-stereo:panorama-coverage-angle:o01:equirectangular-180",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:projection-and-stereo:panorama-coverage-angle:05",
      "rubric": "rubric:projection-and-stereo.panorama-coverage-angle.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "equirectangular-360",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:projection-and-stereo:panorama-coverage-angle:o01:equirectangular-360",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:projection-and-stereo:panorama-coverage-angle:12",
      "rubric": "rubric:projection-and-stereo.panorama-coverage-angle.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "custom-angle-200",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:projection-and-stereo:panorama-coverage-angle:o01:custom-angle-200",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:projection-and-stereo:panorama-coverage-angle:19",
      "rubric": "rubric:projection-and-stereo.panorama-coverage-angle.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "custom-angle-240",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:projection-and-stereo:panorama-coverage-angle:o01:custom-angle-240",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:projection-and-stereo:panorama-coverage-angle:26",
      "rubric": "rubric:projection-and-stereo.panorama-coverage-angle.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:projection-and-stereo:panorama-coverage-angle:o01:equirectangular-180"
      },
      {
        "observation": "obligation:projection-and-stereo:panorama-coverage-angle:o01:equirectangular-360"
      },
      {
        "observation": "obligation:projection-and-stereo:panorama-coverage-angle:o01:custom-angle-200"
      },
      {
        "observation": "obligation:projection-and-stereo:panorama-coverage-angle:o01:custom-angle-240"
      }
    ]
  }
}
---
# 180°、360° 与 Custom Angle 覆盖角

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
