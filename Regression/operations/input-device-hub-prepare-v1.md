---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:input.device-hub-prepare@1",
  "title": "Input Device Hub Prepare",
  "role": "setup",
  "lanes": [
    "simulator"
  ],
  "argumentSchema": {
    "fields": [],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "input.device-hub",
    "lane.instance"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:2202f9fcb28c1f28cebdc70eec2435c09a2f49f882a581861f2b42590330f2c5"
  }
}
---
# Input Device Hub Prepare

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
