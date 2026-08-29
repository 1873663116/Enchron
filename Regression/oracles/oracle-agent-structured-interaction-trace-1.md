---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-structured-interaction-trace@1",
  "title": "Agent Structured Interaction Trace",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "interaction.trace",
      "evidenceSchema": "interaction-trace@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686"
  }
}
---
# Agent Structured Interaction Trace

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
