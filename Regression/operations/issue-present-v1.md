---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:issue.present@1",
  "title": "Issue Present",
  "role": "diagnostic-bypass",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "category",
        "type": "string",
        "required": true
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:65e1419b109ee9171294e01fb5f49ae6acfbbca612dc63764bd1bbc686df0622"
  }
}
---
# Issue Present

No public product identifier presents an arbitrary playback issue. This diagnostic-bypass Operation rejects every invocation instead of mutating product state through the test command channel.
