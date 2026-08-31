---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
  "title": "注入式导入重新进入生产入库管线",
  "journey": "journey:local-media-lifecycle",
  "promiseRefs": [
    "promise:media-import:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "either",
  "estimatedCostMillis": 30000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "local-aggregate-staged",
      "schema": "fixture-set.local-aggregate-staged@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "fileName": "sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:injected-import-rejoins-ingest:01",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:injected-import-rejoins-ingest:02",
      "maxInvocations": 1,
      "operation": "operation:library.snapshot@1"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:injected-import-rejoins-ingest:03",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:local-media-lifecycle:injected-import-rejoins-ingest:04",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:injected-import-rejoins-ingest:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "library-command@1",
      "evidenceType": "library.command",
      "id": "obligation:local-media-lifecycle:injected-import-rejoins-ingest:o01:default",
      "oracle": "oracle:agent-structured-library-command@1",
      "producedByCall": "call:local-media-lifecycle:injected-import-rejoins-ingest:02",
      "rubric": "rubric:local-media-lifecycle.injected-import-rejoins-ingest.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:local-media-lifecycle:injected-import-rejoins-ingest:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:local-media-lifecycle:injected-import-rejoins-ingest:05",
      "rubric": "rubric:local-media-lifecycle.injected-import-rejoins-ingest.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:local-media-lifecycle:injected-import-rejoins-ingest:o01:default"
      },
      {
        "observation": "obligation:local-media-lifecycle:injected-import-rejoins-ingest:o02:default"
      }
    ]
  }
}
---
# 注入式导入重新进入生产入库管线

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
