---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:library-management:folder-naming",
  "title": "Folder naming",
  "journey": "journey:library-management",
  "promiseRefs": [
    "promise:library-management:c01"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "simulator",
  "estimatedCostMillis": 90000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "system-import-fixtures-ready",
      "schema": "fixture-set.system-import@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:library-management:folder-naming:01",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:library-management:folder-naming:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-Manage-button"
        ]
      },
      "callId": "call:library-management:folder-naming:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-Manage-newFolder"
        ]
      },
      "callId": "call:library-management:folder-naming:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "MediaLibrary-NewFolder-name",
        "mode": "replace",
        "secret": false,
        "text": "Catalog V2 Folder"
      },
      "callId": "call:library-management:folder-naming:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-NewFolder-create"
        ]
      },
      "callId": "call:library-management:folder-naming:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {},
      "callId": "call:library-management:folder-naming:07",
      "maxInvocations": 1,
      "operation": "operation:library.snapshot@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "library-command@1",
      "evidenceType": "library.command",
      "id": "obligation:library-management:folder-naming:o01:default",
      "oracle": "oracle:agent-structured-library-command@1",
      "producedByCall": "call:library-management:folder-naming:07",
      "rubric": "rubric:library-management.folder-naming.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:library-management:folder-naming:o01:default"
  }
}
---
# Folder naming

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
