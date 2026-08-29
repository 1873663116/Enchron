---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-structured-emby-range-log@1",
  "title": "Agent Structured Emby Range Log",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "emby.range-log",
      "evidenceSchema": "emby-range-log@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686"
  }
}
---
# Agent Structured Emby Range Log

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
