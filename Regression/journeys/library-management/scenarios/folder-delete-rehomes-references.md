---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:library-management:folder-delete-rehomes-references",
  "title": "Folder deletion rehomes references",
  "journey": "journey:library-management",
  "promiseRefs": [
    "promise:library-management:c02"
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
        "rootFolderName": "Regression Parent"
      },
      "callId": "call:library-management:folder-delete-rehomes-references:01",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:library-management:folder-delete-rehomes-references:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-grid-folder-Regression Parent"
        ]
      },
      "callId": "call:library-management:folder-delete-rehomes-references:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-Manage-button"
        ]
      },
      "callId": "call:library-management:folder-delete-rehomes-references:04",
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
      "callId": "call:library-management:folder-delete-rehomes-references:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "label": "Folder name",
        "mode": "replace",
        "secret": false,
        "text": "Regression Child"
      },
      "callId": "call:library-management:folder-delete-rehomes-references:06",
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
      "callId": "call:library-management:folder-delete-rehomes-references:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-grid-folder-Regression Child"
        ]
      },
      "callId": "call:library-management:folder-delete-rehomes-references:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:library-management:folder-delete-rehomes-references:09",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-FilesScreen-navBackForward-back"
        ]
      },
      "callId": "call:library-management:folder-delete-rehomes-references:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-FilesScreen-navBackForward-back"
        ]
      },
      "callId": "call:library-management:folder-delete-rehomes-references:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "durationMillis": 1200,
        "gesture": "press",
        "identifiers": [
          "MediaLibrary-grid-folder-Regression Parent"
        ]
      },
      "callId": "call:library-management:folder-delete-rehomes-references:12",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Remove from Library"
        ]
      },
      "callId": "call:library-management:folder-delete-rehomes-references:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Remove from Library"
        ]
      },
      "callId": "call:library-management:folder-delete-rehomes-references:14",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "baselineFileNames": [
          "result://call:library-management:folder-delete-rehomes-references:09/fileName"
        ],
        "baselineFolderIDs": [
          "result://call:library-management:folder-delete-rehomes-references:09/folderID"
        ],
        "baselineReferenceIDs": [
          "result://call:library-management:folder-delete-rehomes-references:09/referenceID"
        ],
        "baselineSourceDigests": [
          "result://call:library-management:folder-delete-rehomes-references:09/sourceDigest"
        ],
        "baselineSourceIdentities": [
          "result://call:library-management:folder-delete-rehomes-references:09/sourceIdentity"
        ],
        "baselineSourcePaths": [
          "result://call:library-management:folder-delete-rehomes-references:09/sourcePath"
        ]
      },
      "callId": "call:library-management:folder-delete-rehomes-references:15",
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
      "id": "obligation:library-management:folder-delete-rehomes-references:o01:default",
      "oracle": "oracle:agent-structured-library-command@1",
      "producedByCall": "call:library-management:folder-delete-rehomes-references:15",
      "rubric": "rubric:library-management.folder-delete-rehomes-references.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:library-management:folder-delete-rehomes-references:o01:default"
  }
}
---
# Folder deletion rehomes references

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
