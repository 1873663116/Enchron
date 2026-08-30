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
    "digest": "sha256:0c453b44779d223dd50352df488c324651a3cad019b894c0b4226ad34f3440a3"
  }
}
---
# Issue Present

No public product identifier presents an arbitrary playback issue. This diagnostic-bypass Operation rejects every invocation instead of mutating product state through the test command channel.
