---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:issue-surface-behavior:typed-single-slot-contract",
  "title": "Typed single-slot issues",
  "journey": "journey:issue-surface-behavior",
  "promiseRefs": [
    "promise:issue-surface:c01"
  ],
  "applicability": {
    "constant": true
  },
  "lane": "device",
  "estimatedCostMillis": 60000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "issue-fixtures-ready",
      "schema": "fixture-set.issue-surfaces@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:issue-surface-behavior:typed-single-slot-contract:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "category": "mediaOpeningFailed"
      },
      "callId": "call:issue-surface-behavior:typed-single-slot-contract:02",
      "maxInvocations": 1,
      "operation": "operation:issue.present@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "PlayerUI-loadFailure-primary"
      },
      "callId": "call:issue-surface-behavior:typed-single-slot-contract:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "category": "playbackControlFailed"
      },
      "callId": "call:issue-surface-behavior:typed-single-slot-contract:04",
      "maxInvocations": 1,
      "operation": "operation:issue.present@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "PlayerUI-playbackIssue-confirm"
      },
      "callId": "call:issue-surface-behavior:typed-single-slot-contract:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "PlayerUI-playbackIssue-confirm"
      },
      "callId": "call:issue-surface-behavior:typed-single-slot-contract:06",
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
      "id": "obligation:issue-surface-behavior:typed-single-slot-contract:o01:first-post-state",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:issue-surface-behavior:typed-single-slot-contract:05",
      "rubric": "rubric:issue-surface-behavior.typed-single-slot-contract.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:issue-surface-behavior:typed-single-slot-contract:o01:replacement-post-state",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:issue-surface-behavior:typed-single-slot-contract:06",
      "rubric": "rubric:issue-surface-behavior.typed-single-slot-contract.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:issue-surface-behavior:typed-single-slot-contract:o01:first-post-state"
      },
      {
        "observation": "obligation:issue-surface-behavior:typed-single-slot-contract:o01:replacement-post-state"
      }
    ]
  }
}
---
# Typed single-slot issues

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
