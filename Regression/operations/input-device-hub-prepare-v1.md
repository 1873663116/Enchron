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
    "digest": "sha256:c3cdd54218485b9d0e37162bbbc5976fc1f7c0a1bec2cdd908e729cddd832c86"
  }
}
---
# Input Device Hub Prepare

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
