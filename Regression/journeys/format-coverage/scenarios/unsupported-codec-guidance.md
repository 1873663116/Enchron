---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:format-coverage:unsupported-codec-guidance",
  "title": "Unsupported codec guidance",
  "journey": "journey:format-coverage",
  "promiseRefs": [
    "promise:format-support:c01"
  ],
  "applicability": {
    "constant": true
  },
  "lane": "device",
  "estimatedCostMillis": 90000,
  "staticCases": [
    "default"
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
      "callId": "call:format-coverage:unsupported-codec-guidance:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:unsupported-codec-guidance:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedIssueCategory": "unsupportedVideoCodec",
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-packed_bframes.avi"
      },
      "callId": "call:format-coverage:unsupported-codec-guidance:03",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "PlayerUI-loadFailure-secondary"
      },
      "callId": "call:format-coverage:unsupported-codec-guidance:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:format-coverage:unsupported-codec-guidance:o01:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:format-coverage:unsupported-codec-guidance:04",
      "rubric": "rubric:format-coverage.unsupported-codec-guidance.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:format-coverage:unsupported-codec-guidance:o01:default"
  }
}
---
# Unsupported codec guidance

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
