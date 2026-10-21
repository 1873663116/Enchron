---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:dynamic-range-interpretation:hdr10-hlg-interpretation",
  "title": "HDR10 与 HLG 传递函数和画面解释",
  "journey": "journey:dynamic-range-interpretation",
  "promiseRefs": [
    "promise:picture-interpretation:c01"
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
    "hdr10",
    "hlg"
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
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-pq-hevc-10bit-avsync-10s.mp4"
      },
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:03",
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
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:05",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:06",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:07",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-hlg-hevc-10bit-avsync-10s.mp4"
      },
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:08",
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
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:09",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:10",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "hdr10",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:hdr10-hlg-interpretation:o01:hdr10",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:05",
      "rubric": "rubric:dynamic-range-interpretation.hdr10-hlg-interpretation.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "hlg",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:hdr10-hlg-interpretation:o01:hlg",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:hdr10-hlg-interpretation:10",
      "rubric": "rubric:dynamic-range-interpretation.hdr10-hlg-interpretation.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:dynamic-range-interpretation:hdr10-hlg-interpretation:o01:hdr10"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:hdr10-hlg-interpretation:o01:hlg"
      }
    ]
  }
}
---
# HDR10 与 HLG 传递函数和画面解释

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
