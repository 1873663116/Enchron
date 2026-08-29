---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-structured-library-command@1",
  "title": "Agent Structured Library Command",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "library.command",
      "evidenceSchema": "library-command@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686"
  }
}
---
# Agent Structured Library Command

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
