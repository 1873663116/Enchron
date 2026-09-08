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
    "digest": "sha256:8fe746de8de0d96e7ab0c9fbd04c7ed2e429cb80095c529115b87c0b832eea7c"
  }
}
---
# Transition Trace Arm

The operation arms the playback transition trace for the active session and optionally arms a presentation settlement fault. It requires that armTransitionTrace requires active playback, throwing when playbackRuntime.activeSessionID is absent, and that armTransitionTrace received an unsupported fault when the fault argument is not settlement-timeout. It records the logical session, settled and target presentations, and byte stream counters, and returns the generation token and capacity.
