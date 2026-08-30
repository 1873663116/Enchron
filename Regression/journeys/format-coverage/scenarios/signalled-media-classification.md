---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:format-coverage:signalled-media-classification",
  "title": "带信令媒体按来源声明选择呈现",
  "journey": "journey:format-coverage",
  "promiseRefs": [
    "promise:clean-state-playback:c02"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 214000,
  "staticCases": [
    "apple-apmp-180",
    "mv-hevc-stereo"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "format-corpus-ready",
      "schema": "fixture-set.format-corpus@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:format-coverage:signalled-media-classification:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:signalled-media-classification:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-APMP-180-example.mp4"
      },
      "callId": "call:format-coverage:signalled-media-classification:03",
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
      "callId": "call:format-coverage:signalled-media-classification:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "portal",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:format-coverage:signalled-media-classification:05",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:signalled-media-classification:06",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:signalled-media-classification:07",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-spatial_lighthouse_flowers_waves_short.mov"
      },
      "callId": "call:format-coverage:signalled-media-classification:08",
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
      "callId": "call:format-coverage:signalled-media-classification:09",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "portal",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:format-coverage:signalled-media-classification:10",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "apple-apmp-180",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:format-coverage:signalled-media-classification:o01:apple-apmp-180",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:format-coverage:signalled-media-classification:05",
      "rubric": "rubric:format-coverage.signalled-media-classification.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "mv-hevc-stereo",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:format-coverage:signalled-media-classification:o01:mv-hevc-stereo",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:format-coverage:signalled-media-classification:10",
      "rubric": "rubric:format-coverage.signalled-media-classification.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:format-coverage:signalled-media-classification:o01:apple-apmp-180"
      },
      {
        "observation": "obligation:format-coverage:signalled-media-classification:o01:mv-hevc-stereo"
      }
    ]
  }
}
---
# 带信令媒体按来源声明选择呈现

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
