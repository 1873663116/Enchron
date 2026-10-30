---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:format-coverage:subtitle-follows-seek",
  "title": "跳转之后字幕继续跟随",
  "journey": "journey:format-coverage",
  "promiseRefs": [
    "promise:track-selection:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 70000,
  "staticCases": [
    "seek"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "arguments": {
        "check": "subtitle-lane-seek"
      },
      "callId": "call:format-coverage:subtitle-follows-seek:01",
      "maxInvocations": 1,
      "operation": "operation:evidence.structural-test@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "seek",
      "evidenceSchema": "structural-test@2",
      "evidenceType": "structural.test",
      "id": "obligation:format-coverage:subtitle-follows-seek:o01:seek",
      "oracle": "oracle:agent-structured-structural-test@2",
      "producedByCall": "call:format-coverage:subtitle-follows-seek:01",
      "rubric": "rubric:format-coverage.subtitle-follows-seek.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:format-coverage:subtitle-follows-seek:o01:seek"
      }
    ]
  }
}
---
# 跳转之后字幕继续跟随

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
