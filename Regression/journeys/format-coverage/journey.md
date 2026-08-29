---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:format-coverage",
  "title": "格式与解码覆盖",
  "scenarioRefs": [
    "scenario:format-coverage:audio-retirement-on-failure",
    "scenario:format-coverage:audio-delivery-codec-matrix",
    "scenario:format-coverage:signalled-media-classification",
    "scenario:format-coverage:unsupported-codec-guidance"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "format-corpus-ready",
      "schema": "fixture-set.format-corpus@2"
    }
  ]
}
---
# 格式与解码覆盖

The Journey groups scenarios and declares only the five reviewed state-handoff edges.
