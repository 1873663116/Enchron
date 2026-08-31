---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:network-resilience:prefetch-without-waiting-consumer",
  "title": "无阻塞消费者时仍预取至水位线",
  "journey": "journey:network-resilience",
  "promiseRefs": [
    "promise:network-resilience:c01"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 70000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "faultable-remote-source-ready",
      "schema": "remote-source.faultable@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "check": "playback-core-network-resilience"
      },
      "callId": "call:network-resilience:prefetch-without-waiting-consumer:01",
      "maxInvocations": 1,
      "operation": "operation:evidence.structural-test@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "structural-test@2",
      "evidenceType": "structural.test",
      "id": "obligation:network-resilience:prefetch-without-waiting-consumer:o01:default",
      "oracle": "oracle:agent-structured-structural-test@2",
      "producedByCall": "call:network-resilience:prefetch-without-waiting-consumer:01",
      "rubric": "rubric:network-resilience.prefetch-without-waiting-consumer.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:network-resilience:prefetch-without-waiting-consumer:o01:default"
  }
}
---
# 无阻塞消费者时仍预取至水位线

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
