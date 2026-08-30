---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:diagnostics.surface-probe@1",
  "title": "Diagnostics Surface Probe",
  "role": "evidence",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "cursorToken",
        "type": "string",
        "required": false
      },
      {
        "name": "settleDelayMillis",
        "type": "integer",
        "required": false
      },
      {
        "name": "remoteExpectation",
        "type": "string",
        "required": false
      },
      {
        "name": "remoteGenerationToken",
        "type": "string",
        "required": false
      },
      {
        "name": "remoteReceiptID",
        "type": "string",
        "required": false
      },
      {
        "name": "restoredGenerationToken",
        "type": "string",
        "required": false
      },
      {
        "name": "productBindingDigest",
        "type": "string",
        "required": false
      },
      {
        "name": "containerIndexExpectation",
        "type": "string",
        "required": false
      },
      {
        "name": "expectedBaselineDigest",
        "type": "string",
        "required": false
      },
      {
        "name": "expectedLocalActiveDigest",
        "type": "string",
        "required": false
      },
      {
        "name": "expectedLocalAfterDigest",
        "type": "string",
        "required": false
      },
      {
        "name": "includeViewingStorage",
        "type": "boolean",
        "required": false
      },
      {
        "name": "priorViewingStorageDigests",
        "type": "string-list",
        "required": false
      },
      {
        "name": "awaitEmptyStores",
        "type": "string-list",
        "required": false
      },
      {
        "name": "deadlineSeconds",
        "type": "integer",
        "required": false
      },
      {
        "name": "remoteRequestCursor",
        "type": "string",
        "required": false
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "interaction.trace",
      "evidenceSchema": "interaction-trace@1"
    },
    {
      "evidenceType": "spatial.input",
      "evidenceSchema": "spatial-input@1"
    },
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:13c255d379a9552cf4249b3ac27a69c016115c2cacd6f5ef3783480ca7bc9335"
  }
}
---
# Diagnostics Surface Probe

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
