---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:transition-trace.arm@1",
  "title": "Transition Trace Arm",
  "role": "setup",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "fault",
        "type": "string",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:37845e83cbb27174a8d5761b0e23127bc395031896d2772b640a04b5909f2e52"
  }
}
---
# Transition Trace Arm

The operation arms the playback transition trace for the active session and optionally arms a presentation settlement fault. It requires that armTransitionTrace requires active playback, throwing when playbackRuntime.activeSessionID is absent, and that armTransitionTrace received an unsupported fault when the fault argument is not settlement-timeout. It records the logical session, settled and target presentations, and byte stream counters, and returns the generation token and capacity.
