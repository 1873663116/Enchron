---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:smb-source-lifecycle:smb-browse-shares-and-directories",
  "title": "SMB 共享与目录逐层浏览",
  "journey": "journey:smb-source-lifecycle",
  "promiseRefs": [
    "promise:remote-source-connection:c02"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 85000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "smb-test-source-ready",
      "schema": "remote-source.smb-fixture@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "check": "smb-aggregate"
      },
      "callId": "call:smb-source-lifecycle:smb-browse-shares-and-directories:01",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {},
      "callId": "call:smb-source-lifecycle:smb-browse-shares-and-directories:02",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:smb-source-lifecycle:smb-browse-shares-and-directories:03",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "expectedVideoName": "result://call:smb-source-lifecycle:smb-browse-shares-and-directories:01/aggregateVideoName",
        "hostShareName": "result://call:smb-source-lifecycle:smb-browse-shares-and-directories:01/shareName",
        "hostShares": "result://call:smb-source-lifecycle:smb-browse-shares-and-directories:01/hostShares",
        "pathComponents": [
          "TestMedia",
          "TestVectors",
          "Enchron",
          "PlaybackBehavior"
        ],
        "sourceLabel": "Enchron Regression SMB"
      },
      "callId": "call:smb-source-lifecycle:smb-browse-shares-and-directories:04",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.browse-hierarchy@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:smb-source-lifecycle:smb-browse-shares-and-directories:05",
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
      "id": "obligation:smb-source-lifecycle:smb-browse-shares-and-directories:o01:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:smb-source-lifecycle:smb-browse-shares-and-directories:04",
      "rubric": "rubric:smb-source-lifecycle.smb-browse-shares-and-directories.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:smb-source-lifecycle:smb-browse-shares-and-directories:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:smb-source-lifecycle:smb-browse-shares-and-directories:05",
      "rubric": "rubric:smb-source-lifecycle.smb-browse-shares-and-directories.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:smb-source-lifecycle:smb-browse-shares-and-directories:o01:default"
      },
      {
        "observation": "obligation:smb-source-lifecycle:smb-browse-shares-and-directories:o02:default"
      }
    ]
  }
}
---
# SMB 共享与目录逐层浏览

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
