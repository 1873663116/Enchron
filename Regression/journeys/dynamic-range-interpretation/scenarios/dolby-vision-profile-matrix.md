---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:dynamic-range-interpretation:dolby-vision-profile-matrix",
  "title": "Dolby Vision profile 5、7、8、10 与 20 处理矩阵",
  "journey": "journey:dynamic-range-interpretation",
  "promiseRefs": [
    "promise:picture-interpretation:c02"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 582000,
  "staticCases": [
    "dv-profile-5",
    "dv-profile-7-dual",
    "dv-profile-8-hdr10",
    "dv-profile-8-hlg",
    "dv-profile-10",
    "dv-profile-20"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "dynamic-range-corpus-ready",
      "schema": "fixture-set.dynamic-range@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:03",
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
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:05",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:06",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:07",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-FEL_test_for_AVS.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:08",
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
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:09",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:10",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:11",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:12",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:13",
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
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:14",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:15",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:16",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:17",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:18",
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
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:19",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:20",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:21",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:22",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-media-video-dav1-dav1-1.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:23",
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
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:24",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:25",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:26",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:27",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-3D-example.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:28",
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
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:29",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:30",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-5",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-5",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:05",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-7-dual",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-7-dual",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:10",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-8-hdr10",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-8-hdr10",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:15",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-8-hlg",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-8-hlg",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:20",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-10",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-10",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:25",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-20",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-20",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:30",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-5"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-7-dual"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-8-hdr10"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-8-hlg"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-10"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-20"
      }
    ]
  }
}
---
# Dolby Vision profile 5、7、8、10 与 20 处理矩阵

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
