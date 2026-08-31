---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:library-management:move-references",
  "title": "Move references",
  "journey": "journey:library-management",
  "promiseRefs": [
    "promise:library-management:c03"
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
    },
    {
      "key": "local-aggregate-staged",
      "schema": "fixture-set.local-aggregate-staged@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "rootFolderName": "Regression Destination"
      },
      "callId": "call:library-management:move-references:01",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:library-management:move-references:02",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:library-management:move-references:03",
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
      "callId": "call:library-management:move-references:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-Manage-selectMultiple"
        ]
      },
      "callId": "call:library-management:move-references:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4"
        ]
      },
      "callId": "call:library-management:move-references:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-MultiSelect-move"
        ]
      },
      "callId": "call:library-management:move-references:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Regression Destination"
        ]
      },
      "callId": "call:library-management:move-references:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "baselineFileNames": [
          "result://call:library-management:move-references:02/fileName"
        ],
        "baselineFolderIDs": [
          "result://call:library-management:move-references:02/folderID"
        ],
        "baselineReferenceIDs": [
          "result://call:library-management:move-references:02/referenceID"
        ],
        "baselineSourceDigests": [
          "result://call:library-management:move-references:02/sourceDigest"
        ],
        "baselineSourceIdentities": [
          "result://call:library-management:move-references:02/sourceIdentity"
        ],
        "baselineSourcePaths": [
          "result://call:library-management:move-references:02/sourcePath"
        ]
      },
      "callId": "call:library-management:move-references:09",
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
      "id": "obligation:library-management:move-references:o01:default",
      "oracle": "oracle:agent-structured-library-command@1",
      "producedByCall": "call:library-management:move-references:09",
      "rubric": "rubric:library-management.move-references.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:library-management:move-references:o01:default"
  }
}
---
# Move references

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
