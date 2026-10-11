---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-audio@2",
  "title": "Agent Audio",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "audio.measurement",
      "evidenceSchema": "audio-measurement@2"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:f1bf08d2e6e3e280f0de9115951c5b8cb3cca93d612340b8663bc7b35504645d"
  }
}
---
# Agent Audio

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
