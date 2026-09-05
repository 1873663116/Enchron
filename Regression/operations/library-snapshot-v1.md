---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:library.snapshot@1",
  "title": "Library Snapshot",
  "role": "evidence",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "baselineReferenceIDs",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineFolderIDs",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineSourceIdentities",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineSourcePaths",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineSourceDigests",
        "type": "string-list",
        "required": false
      },
      {
        "name": "baselineFileNames",
        "type": "string-list",
        "required": false
      },
      {
        "name": "priorSnapshot",
        "type": "string",
        "required": false
      },
      {
        "name": "systemImportExpectation",
        "type": "string",
        "required": false
      }
    ],
    "rules": [
      {
        "kind": "all-or-none",
        "fields": [
          "baselineReferenceIDs",
          "baselineFolderIDs",
          "baselineSourceIdentities",
          "baselineSourcePaths",
          "baselineSourceDigests",
          "baselineFileNames"
        ]
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "library.command",
      "evidenceSchema": "library-command@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:3c1fe7eecc5a1d752b086e109d55959e59ee7db0be3b2564d535351fb8101919"
  }
}
---
# Library Snapshot

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
