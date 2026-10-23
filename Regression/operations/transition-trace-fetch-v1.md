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
    "digest": "sha256:65f683b20444ff5d3a0fa9be0237dda59e4716b9754d04a37b2ce19627c4aef1"
  }
}
---
# Transition Trace Fetch

The operation fetches the transition trace snapshot and derives analysis. It requires that fetchTransitionTraceSnapshot requires generationToken, validating that the generation token matches the armed trace generation, and reports when the transition snapshot generation does not match the arm token. It snapshots the ring and returns generation, record count, overwritten count, the typed snapshot and analysis, and the terminal control-plane state.
