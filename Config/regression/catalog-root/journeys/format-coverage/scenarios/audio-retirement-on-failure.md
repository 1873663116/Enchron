---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:format-coverage:audio-retirement-on-failure",
  "title": "音轨在各失败阶段退休后视频仍可继续",
  "journey": "journey:format-coverage",
  "promiseRefs": [
    "promise:track-selection:c02"
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
    "open",
    "prewarm",
    "playback",
    "seek",
    "renderer"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "arguments": {
        "check": "audio-retirement-open"
      },
      "callId": "call:format-coverage:audio-retirement-on-failure:01",
      "maxInvocations": 1,
      "operation": "operation:evidence.structural-test@1"
    },
    {
      "arguments": {
        "check": "audio-retirement-prewarm"
      },
      "callId": "call:format-coverage:audio-retirement-on-failure:02",
      "maxInvocations": 1,
      "operation": "operation:evidence.structural-test@1"
    },
    {
      "arguments": {
        "check": "audio-retirement-playback"
      },
      "callId": "call:format-coverage:audio-retirement-on-failure:03",
      "maxInvocations": 1,
      "operation": "operation:evidence.structural-test@1"
    },
    {
      "arguments": {
        "check": "audio-retirement-seek"
      },
      "callId": "call:format-coverage:audio-retirement-on-failure:04",
      "maxInvocations": 1,
      "operation": "operation:evidence.structural-test@1"
    },
    {
      "arguments": {
        "check": "audio-retirement-renderer"
      },
      "callId": "call:format-coverage:audio-retirement-on-failure:05",
      "maxInvocations": 1,
      "operation": "operation:evidence.structural-test@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "open",
      "evidenceSchema": "structural-test@2",
      "evidenceType": "structural.test",
      "id": "obligation:format-coverage:audio-retirement-on-failure:o01:open",
      "oracle": "oracle:agent-structured-structural-test@2",
      "producedByCall": "call:format-coverage:audio-retirement-on-failure:01",
      "rubric": "rubric:format-coverage.audio-retirement-on-failure.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "prewarm",
      "evidenceSchema": "structural-test@2",
      "evidenceType": "structural.test",
      "id": "obligation:format-coverage:audio-retirement-on-failure:o01:prewarm",
      "oracle": "oracle:agent-structured-structural-test@2",
      "producedByCall": "call:format-coverage:audio-retirement-on-failure:02",
      "rubric": "rubric:format-coverage.audio-retirement-on-failure.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "playback",
      "evidenceSchema": "structural-test@2",
      "evidenceType": "structural.test",
      "id": "obligation:format-coverage:audio-retirement-on-failure:o01:playback",
      "oracle": "oracle:agent-structured-structural-test@2",
      "producedByCall": "call:format-coverage:audio-retirement-on-failure:03",
      "rubric": "rubric:format-coverage.audio-retirement-on-failure.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "seek",
      "evidenceSchema": "structural-test@2",
      "evidenceType": "structural.test",
      "id": "obligation:format-coverage:audio-retirement-on-failure:o01:seek",
      "oracle": "oracle:agent-structured-structural-test@2",
      "producedByCall": "call:format-coverage:audio-retirement-on-failure:04",
      "rubric": "rubric:format-coverage.audio-retirement-on-failure.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "renderer",
      "evidenceSchema": "structural-test@2",
      "evidenceType": "structural.test",
      "id": "obligation:format-coverage:audio-retirement-on-failure:o01:renderer",
      "oracle": "oracle:agent-structured-structural-test@2",
      "producedByCall": "call:format-coverage:audio-retirement-on-failure:05",
      "rubric": "rubric:format-coverage.audio-retirement-on-failure.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:format-coverage:audio-retirement-on-failure:o01:open"
      },
      {
        "observation": "obligation:format-coverage:audio-retirement-on-failure:o01:prewarm"
      },
      {
        "observation": "obligation:format-coverage:audio-retirement-on-failure:o01:playback"
      },
      {
        "observation": "obligation:format-coverage:audio-retirement-on-failure:o01:seek"
      },
      {
        "observation": "obligation:format-coverage:audio-retirement-on-failure:o01:renderer"
      }
    ]
  }
}
---
# 音轨在各失败阶段退休后视频仍可继续

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
