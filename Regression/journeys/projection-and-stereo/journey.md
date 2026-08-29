---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:projection-and-stereo",
  "title": "投影与立体解释",
  "scenarioRefs": [
    "scenario:projection-and-stereo:stereo-view-separation",
    "scenario:projection-and-stereo:panorama-coverage-angle",
    "scenario:projection-and-stereo:apple-immersive-projection"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "projection-corpus-ready",
      "schema": "fixture-set.projection-stereo@2"
    }
  ]
}
---
# 投影与立体解释

The Journey groups scenarios and declares only the five reviewed state-handoff edges.
