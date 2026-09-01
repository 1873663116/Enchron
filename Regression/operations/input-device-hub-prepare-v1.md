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
    "digest": "sha256:1d898ed90d6199a310eb518f6000131cb818e57a00be69e15059d5451b9c0b7e"
  }
}
---
# Input Device Hub Prepare

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
