---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:library-management:current-folder-search-counts",
  "title": "Current-folder search and counts",
  "journey": "journey:library-management",
  "promiseRefs": [
    "promise:library-management:c05"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "simulator",
  "estimatedCostMillis": 100000,
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
        "rootFolderName": "Regression Search Folder"
      },
      "callId": "call:library-management:current-folder-search-counts:01",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:library-management:current-folder-search-counts:02",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:library-management:current-folder-search-counts:03",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "baselineFileNames": [
          "result://call:library-management:current-folder-search-counts:02/fileName"
        ],
        "baselineFolderIDs": [
          "result://call:library-management:current-folder-search-counts:02/folderID"
        ],
        "baselineReferenceIDs": [
          "result://call:library-management:current-folder-search-counts:02/referenceID"
        ],
        "baselineSourceDigests": [
          "result://call:library-management:current-folder-search-counts:02/sourceDigest"
        ],
        "baselineSourceIdentities": [
          "result://call:library-management:current-folder-search-counts:02/sourceIdentity"
        ],
        "baselineSourcePaths": [
          "result://call:library-management:current-folder-search-counts:02/sourcePath"
        ]
      },
      "callId": "call:library-management:current-folder-search-counts:04",
      "maxInvocations": 1,
      "operation": "operation:library.snapshot@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-grid-folder-Regression Search Folder"
        ]
      },
      "callId": "call:library-management:current-folder-search-counts:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:library-management:current-folder-search-counts:06",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-FilesScreen-search",
        "mode": "replace",
        "secret": false,
        "text": "sdr-bframe"
      },
      "callId": "call:library-management:current-folder-search-counts:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-FilesScreen",
        "relatedResults": [
          "result://call:library-management:current-folder-search-counts:04/snapshot",
          "result://call:library-management:current-folder-search-counts:06/afterSnapshot",
          "result://call:library-management:current-folder-search-counts:07/postActionState"
        ]
      },
      "callId": "call:library-management:current-folder-search-counts:08",
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
      "id": "obligation:library-management:current-folder-search-counts:o01:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:library-management:current-folder-search-counts:08",
      "rubric": "rubric:library-management.current-folder-search-counts.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:library-management:current-folder-search-counts:o01:default"
  }
}
---
# Current-folder search and counts

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
