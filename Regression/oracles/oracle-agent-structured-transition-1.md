---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-structured-transition@1",
  "title": "Agent Structured Transition",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "transition.trace",
      "evidenceSchema": "transition-trace@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212"
  }
}
---
# Agent Structured Transition

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
