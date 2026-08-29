---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:library-management:confirmed-batch-deletion",
  "title": "Confirmed batch deletion",
  "journey": "journey:library-management",
  "promiseRefs": [
    "promise:library-management:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "simulator",
  "estimatedCostMillis": 120000,
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
      "arguments": {},
      "callId": "call:library-management:confirmed-batch-deletion:01",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:library-management:confirmed-batch-deletion:02",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:library-management:confirmed-batch-deletion:03",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-subtitles-30s.mkv"
      },
      "callId": "call:library-management:confirmed-batch-deletion:04",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:library-management:confirmed-batch-deletion:05",
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
      "callId": "call:library-management:confirmed-batch-deletion:06",
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
      "callId": "call:library-management:confirmed-batch-deletion:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4",
          "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv"
        ]
      },
      "callId": "call:library-management:confirmed-batch-deletion:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-MultiSelect-delete"
        ]
      },
      "callId": "call:library-management:confirmed-batch-deletion:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "baselineFileNames": [
          "result://call:library-management:confirmed-batch-deletion:02/fileName",
          "result://call:library-management:confirmed-batch-deletion:03/fileName",
          "result://call:library-management:confirmed-batch-deletion:04/fileName"
        ],
        "baselineFolderIDs": [
          "result://call:library-management:confirmed-batch-deletion:02/folderID",
          "result://call:library-management:confirmed-batch-deletion:03/folderID",
          "result://call:library-management:confirmed-batch-deletion:04/folderID"
        ],
        "baselineReferenceIDs": [
          "result://call:library-management:confirmed-batch-deletion:02/referenceID",
          "result://call:library-management:confirmed-batch-deletion:03/referenceID",
          "result://call:library-management:confirmed-batch-deletion:04/referenceID"
        ],
        "baselineSourceDigests": [
          "result://call:library-management:confirmed-batch-deletion:02/sourceDigest",
          "result://call:library-management:confirmed-batch-deletion:03/sourceDigest",
          "result://call:library-management:confirmed-batch-deletion:04/sourceDigest"
        ],
        "baselineSourceIdentities": [
          "result://call:library-management:confirmed-batch-deletion:02/sourceIdentity",
          "result://call:library-management:confirmed-batch-deletion:03/sourceIdentity",
          "result://call:library-management:confirmed-batch-deletion:04/sourceIdentity"
        ],
        "baselineSourcePaths": [
          "result://call:library-management:confirmed-batch-deletion:02/sourcePath",
          "result://call:library-management:confirmed-batch-deletion:03/sourcePath",
          "result://call:library-management:confirmed-batch-deletion:04/sourcePath"
        ]
      },
      "callId": "call:library-management:confirmed-batch-deletion:10",
      "maxInvocations": 1,
      "operation": "operation:library.snapshot@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-MultiSelect-confirmDelete"
        ]
      },
      "callId": "call:library-management:confirmed-batch-deletion:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "baselineFileNames": [
          "result://call:library-management:confirmed-batch-deletion:02/fileName",
          "result://call:library-management:confirmed-batch-deletion:03/fileName",
          "result://call:library-management:confirmed-batch-deletion:04/fileName"
        ],
        "baselineFolderIDs": [
          "result://call:library-management:confirmed-batch-deletion:02/folderID",
          "result://call:library-management:confirmed-batch-deletion:03/folderID",
          "result://call:library-management:confirmed-batch-deletion:04/folderID"
        ],
        "baselineReferenceIDs": [
          "result://call:library-management:confirmed-batch-deletion:02/referenceID",
          "result://call:library-management:confirmed-batch-deletion:03/referenceID",
          "result://call:library-management:confirmed-batch-deletion:04/referenceID"
        ],
        "baselineSourceDigests": [
          "result://call:library-management:confirmed-batch-deletion:02/sourceDigest",
          "result://call:library-management:confirmed-batch-deletion:03/sourceDigest",
          "result://call:library-management:confirmed-batch-deletion:04/sourceDigest"
        ],
        "baselineSourceIdentities": [
          "result://call:library-management:confirmed-batch-deletion:02/sourceIdentity",
          "result://call:library-management:confirmed-batch-deletion:03/sourceIdentity",
          "result://call:library-management:confirmed-batch-deletion:04/sourceIdentity"
        ],
        "baselineSourcePaths": [
          "result://call:library-management:confirmed-batch-deletion:02/sourcePath",
          "result://call:library-management:confirmed-batch-deletion:03/sourcePath",
          "result://call:library-management:confirmed-batch-deletion:04/sourcePath"
        ]
      },
      "callId": "call:library-management:confirmed-batch-deletion:12",
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
      "id": "obligation:library-management:confirmed-batch-deletion:o01:default",
      "oracle": "oracle:agent-structured-library-command@1",
      "producedByCall": "call:library-management:confirmed-batch-deletion:12",
      "rubric": "rubric:library-management.confirmed-batch-deletion.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:library-management:confirmed-batch-deletion:o01:default"
  }
}
---
# Confirmed batch deletion

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
