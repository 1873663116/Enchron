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
    "digest": "sha256:466edc12da9c3126cc7ba845bb2ad3dda158905c5a143133d8e647efc71593b7"
  }
}
---
# Input Device Hub Prepare

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
