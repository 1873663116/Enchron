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
    "additionalProperties": false
  },
  "invalidatesTags": [
    "input.device-hub",
    "lane.instance"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:46beec247e912597e51e4f21f22b426c17c2d8a1ab7fbd84018fd4f3b24b83fd"
  }
}
---
# Input Device Hub Prepare

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
