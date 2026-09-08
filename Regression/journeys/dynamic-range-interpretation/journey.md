---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:dynamic-range-interpretation",
  "title": "动态范围解释",
  "scenarioRefs": [
    "scenario:dynamic-range-interpretation:hdr10-hlg-interpretation",
    "scenario:dynamic-range-interpretation:dolby-vision-profile-matrix",
    "scenario:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch",
    "scenario:dynamic-range-interpretation:docked-hlg-audio-integrity"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "dynamic-range-corpus-ready",
      "schema": "fixture-set.dynamic-range@2"
    }
  ]
}
---
# 动态范围解释

The Journey groups scenarios and declares only the reviewed state-handoff edges.
