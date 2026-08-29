---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-structured-playback-probe@1",
  "title": "Agent Structured Playback Probe",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "playback.probe",
      "evidenceSchema": "playback-probe@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686"
  }
}
---
# Agent Structured Playback Probe

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
