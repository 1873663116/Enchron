---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:transition-trace.fetch@1",
  "title": "Transition Trace Fetch",
  "role": "evidence",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "generationToken",
        "type": "string",
        "required": true
      },
      {
        "name": "relatedResults",
        "type": "string-list",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [
    {
      "evidenceType": "transition.trace",
      "evidenceSchema": "transition-trace@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:3c1fe7eecc5a1d752b086e109d55959e59ee7db0be3b2564d535351fb8101919"
  }
}
---
# Transition Trace Fetch

The operation fetches the transition trace snapshot and derives analysis. It requires that fetchTransitionTraceSnapshot requires generationToken, validating that the generation token matches the armed trace generation, and reports when the transition snapshot generation does not match the arm token. It snapshots the ring and returns generation, record count, overwritten count, the typed snapshot and analysis, and the terminal control-plane state.
