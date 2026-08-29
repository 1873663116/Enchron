---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:network-resilience",
  "title": "远程播放的网络韧性",
  "scenarioRefs": [
    "scenario:network-resilience:prefetch-without-waiting-consumer",
    "scenario:network-resilience:recoverable-read-resumes-from-checkpoint",
    "scenario:network-resilience:finite-backoff-reconnect",
    "scenario:network-resilience:buffered-reconnect-has-no-indicator",
    "scenario:network-resilience:playback-failure-category-matrix",
    "scenario:network-resilience:certificate-change-stops-without-trust"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "faultable-remote-source-ready",
      "schema": "remote-source.faultable@2"
    }
  ]
}
---
# 远程播放的网络韧性

The Journey groups scenarios and declares only the five reviewed state-handoff edges.
